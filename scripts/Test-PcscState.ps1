[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class EzPcscNative022 {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct ReaderState {
        [MarshalAs(UnmanagedType.LPWStr)] public string Reader;
        public IntPtr UserData;
        public UInt32 CurrentState;
        public UInt32 EventState;
        public UInt32 AtrLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=36)] public byte[] Atr;
    }
    [DllImport("winscard.dll")] public static extern int SCardEstablishContext(uint scope, IntPtr r1, IntPtr r2, out UIntPtr context);
    [DllImport("winscard.dll")] public static extern int SCardReleaseContext(UIntPtr context);
    [DllImport("winscard.dll", CharSet=CharSet.Unicode, EntryPoint="SCardListReadersW")] public static extern int SCardListReaders(UIntPtr context, string groups, IntPtr readers, ref uint chars);
    [DllImport("winscard.dll", CharSet=CharSet.Unicode, EntryPoint="SCardListReadersW")] public static extern int SCardListReaders(UIntPtr context, string groups, StringBuilder readers, ref uint chars);
    [DllImport("winscard.dll", CharSet=CharSet.Unicode, EntryPoint="SCardGetStatusChangeW")] public static extern int SCardGetStatusChange(UIntPtr context, uint timeout, [In, Out] ReaderState[] states, uint count);
}
'@
function Format-PcscResult([int]$Result) {
    '0x{0:X8}' -f ([int64]$Result -band 0xFFFFFFFFL)
}
$context = [UIntPtr]::Zero
$rc = [EzPcscNative022]::SCardEstablishContext(2, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$context)
if ($rc -ne 0) { throw ('SCardEstablishContext failed: {0}' -f (Format-PcscResult $rc)) }
try {
    [uint32]$chars = 0
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        $chars = 0
        $rc = [EzPcscNative022]::SCardListReaders($context, $null, [IntPtr]::Zero, [ref]$chars)
        if ($rc -eq 0) { break }
        if (([int64]$rc -band 0xFFFFFFFFL) -ne 0x8010002EL -or $attempt -eq 9) {
            throw ('SCardListReaders(size) failed: {0}' -f (Format-PcscResult $rc))
        }
        Start-Sleep -Milliseconds 500
    }
    $buffer = [Text.StringBuilder]::new([int]$chars)
    $rc = [EzPcscNative022]::SCardListReaders($context, $null, $buffer, [ref]$chars)
    if ($rc -ne 0) { throw ('SCardListReaders(data) failed: {0}' -f (Format-PcscResult $rc)) }
    $readers = @($buffer.ToString().Split([char]0, [StringSplitOptions]::RemoveEmptyEntries))
    foreach ($reader in $readers) {
        $state = [EzPcscNative022+ReaderState]::new()
        $state.Reader = $reader
        $state.CurrentState = 0
        $state.Atr = [byte[]]::new(36)
        $states = [EzPcscNative022+ReaderState[]]@($state)
        $rc = [EzPcscNative022]::SCardGetStatusChange($context, 0, $states, 1)
        if ($rc -ne 0) { throw ('SCardGetStatusChange failed for {0}: {1}' -f $reader, (Format-PcscResult $rc)) }
        [pscustomobject]@{
            Reader = $reader
            Present = [bool]($states[0].EventState -band 0x20)
            Empty = [bool]($states[0].EventState -band 0x10)
            Unavailable = [bool]($states[0].EventState -band 0x08)
            Mute = [bool]($states[0].EventState -band 0x200)
            EventState = ('0x{0:X8}' -f $states[0].EventState)
            ATR = if ($states[0].AtrLength) { [BitConverter]::ToString($states[0].Atr, 0, [int]$states[0].AtrLength).Replace('-', '') } else { '' }
        }
    }
} finally {
    [void][EzPcscNative022]::SCardReleaseContext($context)
}
