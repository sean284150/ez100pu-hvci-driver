[CmdletBinding()]
param([string]$PackageDirectory = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
$expectedHardwareId = 'USB\VID_0CA6&PID_0010&REV_0010'
$minimumBuild = 26100
$statePath = Join-Path $env:ProgramData 'EZ100PU-Compatibility-Project\install-state.json'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath),
            '-PackageDirectory',('"{0}"' -f $PackageDirectory)) -join ' '
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
        exit
    }
}

function Test-TestSigningEnabled {
    $text = (& bcdedit.exe /enum '{current}' 2>&1 | Out-String)
    return $text -match '(?im)^testsigning\s+(yes|on|true|是|開啟)\s*$'
}

Assert-Administrator
if (-not [Environment]::Is64BitOperatingSystem) { throw 'Only Windows x64 is supported.' }
$os = Get-CimInstance Win32_OperatingSystem
if ([int]$os.BuildNumber -lt $minimumBuild) { throw "Windows build $minimumBuild or later is required." }
if (Test-TestSigningEnabled) { throw 'Production installation is blocked while Test Mode is enabled.' }

$secureBoot = $false
try { $secureBoot = [bool](Confirm-SecureBootUEFI) } catch { }
if (-not $secureBoot) { throw 'Secure Boot must be enabled for a production installation.' }

$inf = Join-Path $PackageDirectory 'ez100pu_kmdf.inf'
$cat = Join-Path $PackageDirectory 'ez100pu_kmdf.cat'
$sys = Join-Path $PackageDirectory 'ez100pu_kmdf.sys'
foreach ($file in @($inf,$cat,$sys)) {
    if (-not (Test-Path -LiteralPath $file)) { throw "Missing package file: $file" }
}

$signtool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Filter signtool.exe -Recurse |
    Where-Object FullName -Match '\\x64\\signtool\.exe$' |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $signtool) { throw 'Windows SDK SignTool is required to verify the production package.' }
& $signtool verify /kp /v /c $cat $sys
if ($LASTEXITCODE) { throw 'The package does not have a valid Microsoft kernel-policy catalog signature.' }
$catalogSignature = Get-AuthenticodeSignature -LiteralPath $cat
if ($catalogSignature.Status -ne 'Valid' -or
    $catalogSignature.SignerCertificate.Subject -notmatch 'Microsoft') {
    throw 'Catalog signer is not a valid Microsoft signer.'
}

$devices = @(Get-PnpDevice -PresentOnly | Where-Object {
    $_.InstanceId -like 'USB\VID_0CA6&PID_0010\*'
})
if ($devices.Count -ne 1) { throw 'Connect exactly one supported EZ100PU reader before installation.' }
$instanceId = $devices[0].InstanceId
$hardwareIds = @((Get-PnpDeviceProperty -InstanceId $instanceId -KeyName 'DEVPKEY_Device_HardwareIds').Data)
if ($hardwareIds -notcontains $expectedHardwareId) {
    throw "The connected device is not the supported REV_0010 hardware. Found: $($hardwareIds -join ', ')"
}

$before = Get-CimInstance Win32_PnPSignedDriver | Where-Object DeviceID -EQ $instanceId | Select-Object -First 1
& pnputil.exe /add-driver $inf /install
if ($LASTEXITCODE) { throw "PnPUtil installation failed with exit code $LASTEXITCODE." }
$after = Get-CimInstance Win32_PnPSignedDriver | Where-Object DeviceID -EQ $instanceId | Select-Object -First 1
if (-not $after -or $after.InfName -eq $before.InfName) { throw 'The new driver did not bind to the device.' }

$state = [ordered]@{
    SchemaVersion = 1
    InstalledAtUtc = [DateTime]::UtcNow.ToString('o')
    InstanceId = $instanceId
    InstalledInf = $after.InfName
    PreviousInf = $before.InfName
    PackageHashes = @{
        Inf = (Get-FileHash -Algorithm SHA256 $inf).Hash
        Cat = (Get-FileHash -Algorithm SHA256 $cat).Hash
        Sys = (Get-FileHash -Algorithm SHA256 $sys).Hash
    }
}
New-Item -ItemType Directory -Force -Path (Split-Path $statePath) | Out-Null
$state | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath $statePath
Write-Host "Installed Microsoft-signed driver $($after.InfName)."
