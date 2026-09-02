[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class EzPcscConnect022 {
    [DllImport("winscard.dll")] public static extern int SCardEstablishContext(uint scope, IntPtr r1, IntPtr r2, out UIntPtr context);
    [DllImport("winscard.dll")] public static extern int SCardReleaseContext(UIntPtr context);
    [DllImport("winscard.dll", CharSet=CharSet.Unicode, EntryPoint="SCardListReadersW")] public static extern int SCardListReaders(UIntPtr context, string groups, IntPtr readers, ref uint chars);
    [DllImport("winscard.dll", CharSet=CharSet.Unicode, EntryPoint="SCardListReadersW")] public static extern int SCardListReaders(UIntPtr context, string groups, StringBuilder readers, ref uint chars);
    [DllImport("winscard.dll", CharSet=CharSet.Unicode, EntryPoint="SCardConnectW")] public static extern int SCardConnect(UIntPtr context, string reader, uint share, uint preferredProtocols, out UIntPtr card, out uint activeProtocol);
    [DllImport("winscard.dll", CharSet=CharSet.Unicode, EntryPoint="SCardStatusW")] public static extern int SCardStatus(UIntPtr card, StringBuilder reader, ref uint readerChars, out uint state, out uint protocol, [Out] byte[] atr, ref uint atrLength);
    [DllImport("winscard.dll")] public static extern int SCardDisconnect(UIntPtr card, uint disposition);
}
'@
function Format-PcscResult([int]$Result) {
    '0x{0:X8}' -f ([int64]$Result -band 0xFFFFFFFFL)
}
$context = [UIntPtr]::Zero
$card = [UIntPtr]::Zero
$rc = [EzPcscConnect022]::SCardEstablishContext(2, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$context)
if ($rc -ne 0) { throw ('SCardEstablishContext failed: {0}' -f (Format-PcscResult $rc)) }
try {
    [uint32]$chars = 0
    $rc = [EzPcscConnect022]::SCardListReaders($context, $null, [IntPtr]::Zero, [ref]$chars)
    if ($rc -ne 0) { throw ('SCardListReaders(size) failed: {0}' -f (Format-PcscResult $rc)) }
    $readerBuffer = [Text.StringBuilder]::new([int]$chars)
    $rc = [EzPcscConnect022]::SCardListReaders($context, $null, $readerBuffer, [ref]$chars)
    if ($rc -ne 0) { throw ('SCardListReaders(data) failed: {0}' -f (Format-PcscResult $rc)) }
    $reader = @($readerBuffer.ToString().Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))[0]
    [uint32]$activeProtocol = 0
    $rc = [EzPcscConnect022]::SCardConnect($context, $reader, 2, 3, [ref]$card, [ref]$activeProtocol)
    if ($rc -ne 0) { throw ('SCardConnect failed: {0}' -f (Format-PcscResult $rc)) }
    $statusReader = [Text.StringBuilder]::new(256)
    [uint32]$statusReaderChars = 256
    [uint32]$state = 0
    [uint32]$statusProtocol = 0
    [uint32]$atrLength = 36
    $atr = [byte[]]::new(36)
    $rc = [EzPcscConnect022]::SCardStatus($card, $statusReader, [ref]$statusReaderChars, [ref]$state, [ref]$statusProtocol, $atr, [ref]$atrLength)
    if ($rc -ne 0) { throw ('SCardStatus failed: {0}' -f (Format-PcscResult $rc)) }
    [pscustomobject]@{
        Reader = $statusReader.ToString()
        State = ('0x{0:X8}' -f $state)
        Protocol = if ($statusProtocol -eq 1) { 'T=0' } elseif ($statusProtocol -eq 2) { 'T=1' } else { 'Unknown ({0})' -f $statusProtocol }
        ATR = [BitConverter]::ToString($atr, 0, [int]$atrLength).Replace('-', '')
        ExplicitAPDUsSent = 0
    }
} finally {
    if ($card -ne [UIntPtr]::Zero) { [void][EzPcscConnect022]::SCardDisconnect($card, 0) }
    [void][EzPcscConnect022]::SCardReleaseContext($context)
}
