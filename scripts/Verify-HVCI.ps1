[CmdletBinding()]
param([datetime]$Since = (Get-Date).AddHours(-1))
$device = Get-PnpDevice -PresentOnly | Where-Object InstanceId -Like 'USB\VID_0CA6&PID_0010*' | Select-Object -First 1
$guard = Get-CimInstance Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard
$blocked = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational'; StartTime=$Since} -ErrorAction SilentlyContinue |
    Where-Object Message -Match 'ez100pu_kmdf|ezusb64' | Select-Object TimeCreated,Id,Message
[pscustomobject]@{
    DeviceStatus = $device.Status
    DeviceName = $device.FriendlyName
    HVCIRunning = ($guard.SecurityServicesRunning -contains 2)
    HVCIConfigured = ($guard.SecurityServicesConfigured -contains 2)
    RelevantCodeIntegrityEvents = @($blocked).Count
} | Format-List
$blocked | Format-List
if (-not ($guard.SecurityServicesRunning -contains 2)) { Write-Warning 'Memory Integrity is not actually running.' }
if ($device.Status -ne 'OK' -or @($blocked).Count) { exit 1 }
