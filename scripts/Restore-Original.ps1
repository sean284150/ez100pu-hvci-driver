#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$BaselineDirectory = (Join-Path $PSScriptRoot '..\baseline'))
$ErrorActionPreference = 'Stop'
$prototypeFile = Join-Path $BaselineDirectory 'prototype-published-inf.txt'
if (Test-Path $prototypeFile) {
    $prototypeInf = (Get-Content $prototypeFile -Raw).Trim()
    if ($prototypeInf -match '^oem\d+\.inf$') { & pnputil.exe /delete-driver $prototypeInf /uninstall /force }
}
$originalInf = Get-ChildItem (Join-Path $BaselineDirectory 'original-driver') -Filter '*.inf' -Recurse | Select-Object -First 1
if (-not $originalInf) { throw 'Original exported INF is missing.' }
& pnputil.exe /add-driver $originalInf.FullName /install
if ($LASTEXITCODE) { throw "Original driver restoration failed: $LASTEXITCODE" }
$deviceGuardBackup = Join-Path $BaselineDirectory 'device-guard.reg'
if (Test-Path $deviceGuardBackup) { & reg.exe import $deviceGuardBackup | Out-Null }
& bcdedit.exe /set testsigning off
Write-Host 'Original driver rebound and Test Mode disabled. Reboot required. If Secure Boot was changed in firmware, restore it there after reboot.'
