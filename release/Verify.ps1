[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$deviceGuard = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard
$secureBoot = $null
try { $secureBoot = [bool](Confirm-SecureBootUEFI) } catch { }
$bcd = (& bcdedit.exe /enum '{current}' 2>&1 | Out-String)
$startOptions = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name SystemStartOptions -ErrorAction SilentlyContinue).SystemStartOptions
$testMode = ($startOptions -match 'TESTSIGNING') -or
    ($bcd -match '(?im)^testsigning\s+(yes|on|true|是|開啟)\s*$')
$device = Get-PnpDevice -PresentOnly | Where-Object InstanceId -Like 'USB\VID_0CA6&PID_0010\*' |
    Select-Object -First 1
$signed = if ($device) {
    Get-CimInstance Win32_PnPSignedDriver | Where-Object DeviceID -EQ $device.InstanceId | Select-Object -First 1
}
$events = @(Get-WinEvent -FilterHashtable @{
    LogName='Microsoft-Windows-CodeIntegrity/Operational'
    StartTime=(Get-Date).AddDays(-1)
} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'ez100pu_kmdf' } |
    Select-Object -First 20 TimeCreated, Id, LevelDisplayName)

[pscustomobject]@{
    WindowsBuild = (Get-CimInstance Win32_OperatingSystem).BuildNumber
    SecureBoot = $secureBoot
    MemoryIntegrityRunning = (@($deviceGuard.SecurityServicesRunning) -contains 2)
    TestMode = $testMode
    DeviceStatus = if ($device) { $device.Status } else { 'Not present' }
    DeviceName = if ($device) { $device.FriendlyName } else { $null }
    HardwareInstance = if ($device) { $device.InstanceId } else { $null }
    DriverInf = if ($signed) { $signed.InfName } else { $null }
    DriverVersion = if ($signed) { $signed.DriverVersion } else { $null }
    CodeIntegrityEventsLast24Hours = $events.Count
}

if ($events.Count) { $events | Format-Table -AutoSize }
