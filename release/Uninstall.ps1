[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$statePath = Join-Path $env:ProgramData 'EZ100PU-Compatibility-Project\install-state.json'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
if (-not (Test-Path -LiteralPath $statePath)) { throw 'No production installation state was found.' }
$state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
if ($state.SchemaVersion -ne 1 -or $state.InstalledInf -notmatch '^oem[0-9]+\.inf$') {
    throw 'Installation state is invalid; refusing to remove an unverified driver.'
}
$current = Get-CimInstance Win32_PnPSignedDriver |
    Where-Object DeviceID -EQ $state.InstanceId | Select-Object -First 1
if ($current -and $current.InfName -ne $state.InstalledInf) {
    throw "The device now uses $($current.InfName), not $($state.InstalledInf); nothing was removed."
}
& pnputil.exe /delete-driver $state.InstalledInf /uninstall
if ($LASTEXITCODE) { throw "PnPUtil removal failed with exit code $LASTEXITCODE." }
& pnputil.exe /scan-devices | Out-Null
Remove-Item -LiteralPath $statePath -Force
Write-Host 'The compatible driver was removed. Windows may rebind an existing vendor or inbox driver.'
