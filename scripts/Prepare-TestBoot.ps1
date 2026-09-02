#Requires -RunAsAdministrator
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
try {
    if (Confirm-SecureBootUEFI) {
        throw 'Secure Boot is enabled. Disable it in UEFI firmware before enabling Test Mode.'
    }
} catch {
    if ($_.Exception.Message -notmatch 'not supported') { throw }
}
$bitlocker = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
if ($bitlocker -and $bitlocker.ProtectionStatus -eq 'On') {
    throw 'BitLocker protection is active. Save the recovery key and suspend protection before changing boot policy.'
}
& bcdedit.exe /set testsigning on
if ($LASTEXITCODE) { throw "Could not enable Test Mode: $LASTEXITCODE" }
Write-Host 'Test Mode enabled. Reboot, then sign and install the Test package.'
