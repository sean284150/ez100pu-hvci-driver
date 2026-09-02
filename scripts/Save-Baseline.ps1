#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\baseline')
)
$ErrorActionPreference = 'Stop'
$device = Get-PnpDevice -PresentOnly | Where-Object InstanceId -Like 'USB\VID_0CA6&PID_0010*' | Select-Object -First 1
if (-not $device) { throw 'EZ100PU is not connected.' }
$ids = (Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_HardwareIds).Data
if ($ids -notcontains 'USB\VID_0CA6&PID_0010&REV_0010') { throw "Unexpected hardware revision: $($ids -join ', ')" }
$signed = Get-CimInstance Win32_PnPSignedDriver | Where-Object DeviceID -eq $device.InstanceId
if (-not $signed.InfName) { throw 'Could not determine the active published INF.' }
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$export = Join-Path $OutputDirectory 'original-driver'
New-Item -ItemType Directory -Force $export | Out-Null
& pnputil.exe /export-driver $signed.InfName $export | Out-File (Join-Path $OutputDirectory 'pnputil-export.txt')
if ($LASTEXITCODE -ne 0) { throw "pnputil export failed: $LASTEXITCODE" }
$device | Format-List * | Out-File (Join-Path $OutputDirectory 'device.txt')
$ids | Out-File (Join-Path $OutputDirectory 'hardware-ids.txt')
$signed | Format-List * | Out-File (Join-Path $OutputDirectory 'signed-driver.txt')
& pnputil.exe /enum-drivers /files | Out-File (Join-Path $OutputDirectory 'driver-store.txt')
& bcdedit.exe /enum all | Out-File (Join-Path $OutputDirectory 'bcd.txt')
reg.exe export 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' (Join-Path $OutputDirectory 'device-guard.reg') /y | Out-Null
try { Confirm-SecureBootUEFI | Out-File (Join-Path $OutputDirectory 'secure-boot.txt') } catch { $_ | Out-File (Join-Path $OutputDirectory 'secure-boot.txt') }
Get-CimInstance Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard | Format-List * | Out-File (Join-Path $OutputDirectory 'device-guard-runtime.txt')
Set-Content (Join-Path $OutputDirectory 'original-published-inf.txt') $signed.InfName
$resolvedOutput = (Resolve-Path $OutputDirectory).Path
$manifest = Join-Path $resolvedOutput 'sha256.csv'
$filesToHash = @(Get-ChildItem $resolvedOutput -Recurse -File | Where-Object Name -ne 'sha256.csv')
$filesToHash | Get-FileHash -Algorithm SHA256 | Select-Object Hash,@{Name='File';Expression={$_.Path.Substring($resolvedOutput.Length + 1)}} | Export-Csv $manifest -NoTypeInformation
Write-Host "Baseline saved to $resolvedOutput"
