[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $process = Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"')
    ) -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    exit $process.ExitCode
}

$baseline = (Resolve-Path (Join-Path $PSScriptRoot '..\baseline')).Path
$backup = Join-Path $baseline 'pre-hvci-test-device-guard.reg'
& reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' $backup /y | Out-Null
if ($LASTEXITCODE) { throw 'Device Guard registry backup failed.' }

$scenario = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
New-Item -Path $scenario -Force | Out-Null
New-ItemProperty -Path $scenario -Name Enabled -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $scenario -Name Locked -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -Path $scenario -Name WasEnabledBy -PropertyType DWord -Value 2 -Force | Out-Null
& bcdedit.exe /set hypervisorlaunchtype auto | Out-Null
if ($LASTEXITCODE) { throw 'Could not set hypervisorlaunchtype to auto.' }

Write-Host 'Memory Integrity is configured without UEFI lock. Reboot is required; Test Mode remains enabled.'
Write-Host 'Recovery after a driver-load failure: run Disable-HVCI-Test.ps1 and reboot.'
