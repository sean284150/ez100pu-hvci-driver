[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = Get-Content -Raw (Join-Path $root 'driver\usb.c')
$device = Get-Content -Raw (Join-Path $root 'driver\device.c')
$smartcard = Get-Content -Raw (Join-Path $root 'driver\smartcard.c')
$protocol = Get-Content -Raw (Join-Path $root 'driver\protocol_core.c')
$inf = Get-Content -Raw (Join-Path $root 'driver\ez100pu_kmdf.inf')

$checks = [ordered]@{
    ExactRevisionOnly = $inf -match 'USB\\VID_0CA6&PID_0010&REV_0010' -and
        $inf -notmatch '(?m)^.*USB\\VID_0CA6&PID_0010\s*$'
    Windows26100X64 = $inf -match 'NTamd64\.10\.0\.\.\.26100'
    PnpLockdown = $inf -match '(?m)^PnpLockdown=1\r?$'
    SequentialSmclibQueue = $device -match 'WdfIoQueueDispatchSequential'
    ReleaseHardware = $device -match 'EvtDeviceReleaseHardware = EzKmEvtReleaseHardware'
    BoundedTimeExtensions = $source -match 'timeExtensions >= EZKM_MAX_TIME_EXTENSIONS' -and
        $source -match 'STATUS_IO_TIMEOUT'
    BigEndianLength = $source -match 'EzProtoPutBe32\(&commandBuffer\[1\]'
    ResponseLengthBounded = $protocol -match 'payloadLength > WireLength - EZPROTO_HEADER_SIZE'
    PpsTableSearch = $smartcard -match 'for \(candidate = 1u; candidate < 16u; candidate\+\+\)'
    NoApduBytesInDiagnostics = $smartcard -notmatch 'EzKmLogProtocolData\([\s\S]{0,180}SmartcardRequest\.Buffer\['
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object Key)
$checks.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Check=$_.Key; Passed=[bool]$_.Value } }
if ($failed.Count) { throw "Static contract failures: $($failed -join ', ')" }
