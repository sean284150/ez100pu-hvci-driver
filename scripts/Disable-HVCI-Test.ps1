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

$scenario = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
New-Item -Path $scenario -Force | Out-Null
New-ItemProperty -Path $scenario -Name Enabled -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -Path $scenario -Name Locked -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -Path $scenario -Name WasEnabledBy -PropertyType DWord -Value 2 -Force | Out-Null
Write-Host 'Memory Integrity is configured off. Reboot is required; prototype driver and Test Mode are unchanged.'
