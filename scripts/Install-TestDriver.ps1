[CmdletBinding()]
param(
    [string]$PackageDirectory = (Join-Path $PSScriptRoot '..\package\Test'),
    [string]$BaselineDirectory = (Join-Path $PSScriptRoot '..\baseline'),
    [switch]$AllowHvciAfterBaseline
)
$ErrorActionPreference = 'Stop'
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $log = Join-Path $PSScriptRoot 'Install-TestDriver.elevated.log'
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    $escapedScript = $PSCommandPath.Replace("'", "''")
    $escapedPackage = $PackageDirectory.Replace("'", "''")
    $escapedBaseline = $BaselineDirectory.Replace("'", "''")
    $allow = if ($AllowHvciAfterBaseline) { ' -AllowHvciAfterBaseline' } else { '' }
    $escapedLog = $log.Replace("'", "''")
    $command = "`$ErrorActionPreference='Stop'; try { & '$escapedScript' -PackageDirectory '$escapedPackage' -BaselineDirectory '$escapedBaseline'$allow *>&1 | Out-File -FilePath '$escapedLog'; exit 0 } catch { `$_ | Out-String | Out-File -FilePath '$escapedLog'; exit 1 }"
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process = Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand
    ) -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if (Test-Path $log) { Get-Content $log }
    exit $process.ExitCode
}
if (-not (Test-Path (Join-Path $BaselineDirectory 'original-driver'))) { throw 'Run Save-Baseline.ps1 first.' }
$startOptions = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions).SystemStartOptions
if ($startOptions -notmatch 'TESTSIGNING') { throw 'This boot is not running in Test Mode. Reboot after Prepare-TestBoot.ps1.' }
try {
    if (Confirm-SecureBootUEFI) { throw 'Secure Boot is enabled; refusing test-driver installation.' }
} catch {
    if ($_.Exception.Message -notmatch 'not supported') { throw }
}
$guard = Get-CimInstance Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard
if (($guard.SecurityServicesRunning -contains 2) -and -not $AllowHvciAfterBaseline) {
    throw 'Memory Integrity is running. Use -AllowHvciAfterBaseline only after an HVCI-off baseline pass.'
}
$thumbprint = (Get-Content (Join-Path $PSScriptRoot 'test-cert-thumbprint.txt') -Raw).Trim()
$sysPath = Join-Path $PackageDirectory 'ez100pu_kmdf.sys'
$catPath = Join-Path $PackageDirectory 'ez100pu_kmdf.cat'
$sysSignature = Get-AuthenticodeSignature $sysPath
$catSignature = Get-AuthenticodeSignature $catPath
if ($sysSignature.Status -ne 'Valid' -or $sysSignature.SignerCertificate.Thumbprint -ne $thumbprint) { throw 'SYS test signature is invalid or unexpected.' }
if ($catSignature.Status -ne 'Valid' -or $catSignature.SignerCertificate.Thumbprint -ne $thumbprint) { throw 'Catalog test signature is invalid or unexpected.' }
$baselineRoot = (Resolve-Path $BaselineDirectory).Path
$baselineMismatch = @(Import-Csv (Join-Path $baselineRoot 'sha256.csv') | Where-Object {
    (Get-FileHash (Join-Path $baselineRoot $_.File) -Algorithm SHA256).Hash -ne $_.Hash
})
if ($baselineMismatch.Count) { throw "Baseline hash verification failed for: $($baselineMismatch.File -join ', ')" }
$device = Get-PnpDevice -PresentOnly | Where-Object InstanceId -Like 'USB\VID_0CA6&PID_0010*' | Select-Object -First 1
if (-not $device) { throw 'EZ100PU is not connected.' }
$ids = (Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_HardwareIds).Data
if ($ids -notcontains 'USB\VID_0CA6&PID_0010&REV_0010') { throw 'Hardware revision does not match this prototype.' }
& pnputil.exe /add-driver (Join-Path $PackageDirectory 'ez100pu_kmdf.inf') /install
$pnpExitCode = $LASTEXITCODE
if ($pnpExitCode -ne 0 -and $pnpExitCode -ne 3010) { throw "Driver installation failed: $pnpExitCode" }
Start-Sleep -Seconds 2
$active = Get-CimInstance Win32_PnPSignedDriver | Where-Object DeviceID -eq $device.InstanceId
$active | Format-List * | Out-File (Join-Path $BaselineDirectory 'prototype-active-driver.txt')
if ($active.DriverProviderName -ne 'EZ100PU Compatibility Project') { throw 'Prototype was staged but did not become the active driver; no destructive rank override was attempted.' }
Set-Content (Join-Path $BaselineDirectory 'prototype-published-inf.txt') $active.InfName
if ($pnpExitCode -eq 3010) {
    Write-Host "Prototype $($active.DriverVersion) is staged as $($active.InfName). Reboot is required before device validation."
    exit 0
}
$device = Get-PnpDevice -InstanceId $device.InstanceId
if ($device.Status -ne 'OK') {
    $problemCode = (Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_ProblemCode).Data
    $problemStatus = (Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_ProblemStatus).Data
    throw "Prototype is selected but the device did not start (PnP code $problemCode, NTSTATUS 0x$('{0:X8}' -f $problemStatus))."
}
if ($guard.SecurityServicesRunning -contains 2) {
    Write-Host 'Prototype is active with Memory Integrity running. Perform the no-card and live-card regression suites.'
} else {
    Write-Host 'Prototype is active. Test enumeration and basic PC/SC with HVCI off before the HVCI pass.'
}
