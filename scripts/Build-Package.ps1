[CmdletBinding()]
param([ValidateSet('Debug','Test','Release')][string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe |
    Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild was not found.' }
$infverif = 'C:\Program Files (x86)\Windows Kits\10\Tools\10.0.26100.0\x64\infverif.exe'
$inf2cat = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x86\Inf2Cat.exe'
$package = Join-Path $root "package\$Configuration"
$source = if (Test-Path (Join-Path $root 'driver')) { Join-Path $root 'driver' } else { Join-Path $root 'source' }
& $msbuild (Join-Path $source 'ez100pu_kmdf.vcxproj') /m /t:Rebuild /p:Configuration=$Configuration /p:Platform=x64 /warnAsError /v:minimal
if ($LASTEXITCODE) { throw "Build failed: $LASTEXITCODE" }
New-Item -ItemType Directory -Force $package | Out-Null
Copy-Item (Join-Path $root "build\$Configuration\ez100pu_kmdf.sys") $package -Force
Copy-Item (Join-Path $root "build\$Configuration\ez100pu_kmdf.pdb") $package -Force
Copy-Item (Join-Path $source 'ez100pu_kmdf.inf') $package -Force
& (Join-Path $PSScriptRoot 'Test-PePolicy.ps1') -Path (Join-Path $package 'ez100pu_kmdf.sys') |
    Format-List | Out-String | Set-Content -Encoding UTF8 (Join-Path $package 'pe-policy.txt')
& $infverif /w (Join-Path $package 'ez100pu_kmdf.inf')
if ($LASTEXITCODE) { throw "InfVerif failed: $LASTEXITCODE" }
& $inf2cat /driver:$package /os:10_25H2_X64
if ($LASTEXITCODE) { throw "Inf2Cat failed: $LASTEXITCODE" }
$manifest = Join-Path $package 'sha256.csv'
Get-ChildItem $package -File | Where-Object FullName -ne $manifest | Get-FileHash -Algorithm SHA256 | Select-Object Hash,Path | Export-Csv $manifest -NoTypeInformation
Write-Host "Validated package: $package"
