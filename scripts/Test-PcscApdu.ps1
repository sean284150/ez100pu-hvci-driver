[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class EzPcscApdu024 {
    [StructLayout(LayoutKind.Sequential)]
    public struct IoRequest {
        public UInt32 Protocol;
        public UInt32 Length;
    }
    [DllImport("winscard.dll")] public static extern int SCardEstablishContext(uint scope, IntPtr r1, IntPtr r2, out UIntPtr context);
    [DllImport("winscard.dll")] public static extern int SCardReleaseContext(UIntPtr context);
    [DllImport("winscard.dll", CharSet=CharSet.Unicode, EntryPoint="SCardListReadersW")] public static extern int SCardListReaders(UIntPtr context, string groups, IntPtr readers, ref uint chars);
    [DllImport("winscard.dll", CharSet=CharSet.Unicode, EntryPoint="SCardListReadersW")] public static extern int SCardListReaders(UIntPtr context, string groups, StringBuilder readers, ref uint chars);
    [DllImport("winscard.dll", CharSet=CharSet.Unicode, EntryPoint="SCardConnectW")] public static extern int SCardConnect(UIntPtr context, string reader, uint share, uint preferredProtocols, out UIntPtr card, out uint activeProtocol);
    [DllImport("winscard.dll")] public static extern int SCardTransmit(UIntPtr card, ref IoRequest sendPci, byte[] sendBuffer, uint sendLength, IntPtr receivePci, [Out] byte[] receiveBuffer, ref uint receiveLength);
    [DllImport("winscard.dll")] public static extern int SCardDisconnect(UIntPtr card, uint disposition);
}
'@
function Format-PcscResult([int]$Result) {
    '0x{0:X8}' -f ([int64]$Result -band 0xFFFFFFFFL)
}
$context = [UIntPtr]::Zero
$card = [UIntPtr]::Zero
$rc = [EzPcscApdu024]::SCardEstablishContext(2, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$context)
if ($rc -ne 0) { throw ('SCardEstablishContext failed: {0}' -f (Format-PcscResult $rc)) }
try {
    [uint32]$chars = 0
    $rc = [EzPcscApdu024]::SCardListReaders($context, $null, [IntPtr]::Zero, [ref]$chars)
    if ($rc -ne 0) { throw ('SCardListReaders(size) failed: {0}' -f (Format-PcscResult $rc)) }
    $readerBuffer = [Text.StringBuilder]::new([int]$chars)
    $rc = [EzPcscApdu024]::SCardListReaders($context, $null, $readerBuffer, [ref]$chars)
    if ($rc -ne 0) { throw ('SCardListReaders(data) failed: {0}' -f (Format-PcscResult $rc)) }
    $reader = @($readerBuffer.ToString().Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))[0]
    [uint32]$protocol = 0
    $rc = [EzPcscApdu024]::SCardConnect($context, $reader, 2, 3, [ref]$card, [ref]$protocol)
    if ($rc -ne 0) { throw ('SCardConnect failed: {0}' -f (Format-PcscResult $rc)) }

    $sendPci = [EzPcscApdu024+IoRequest]::new()
    $sendPci.Protocol = $protocol
    $sendPci.Length = [Runtime.InteropServices.Marshal]::SizeOf([type][EzPcscApdu024+IoRequest])
    [byte[]]$command = 0x00, 0x84, 0x00, 0x00, 0x08
    [byte[]]$response = [byte[]]::new(258)
    [uint32]$responseLength = $response.Length
    $rc = [EzPcscApdu024]::SCardTransmit($card, [ref]$sendPci, $command, $command.Length, [IntPtr]::Zero, $response, [ref]$responseLength)
    if ($rc -ne 0) { throw ('SCardTransmit failed: {0}' -f (Format-PcscResult $rc)) }
    if ($responseLength -lt 2) { throw 'SCardTransmit returned fewer than two status bytes.' }
    [pscustomobject]@{
        Reader = $reader
        Protocol = if ($protocol -eq 2) { 'T=1' } elseif ($protocol -eq 1) { 'T=0' } else { "Unknown ($protocol)" }
        Command = 'GET CHALLENGE (8 bytes requested)'
        ResponseLength = $responseLength
        StatusWord = ('{0:X2}{1:X2}' -f $response[$responseLength - 2], $response[$responseLength - 1])
        ResponseDataLogged = $false
    }
} finally {
    if ($card -ne [UIntPtr]::Zero) { [void][EzPcscApdu024]::SCardDisconnect($card, 0) }
    [void][EzPcscApdu024]::SCardReleaseContext($context)
}
