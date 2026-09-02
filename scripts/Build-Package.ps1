[CmdletBinding()]
param([ValidateSet('Debug','Test','Release')][string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'Toolchain.ps1')
$msbuild = Get-EzMsBuild
$package = Join-Path $root "package\$Configuration"
$source = if (Test-Path (Join-Path $root 'driver')) { Join-Path $root 'driver' } else { Join-Path $root 'source' }
$wdkRoot = Restore-EzWdk -Root $root
$wdkRootWithSlash = $wdkRoot.TrimEnd('\') + '\'
& $msbuild (Join-Path $source 'ez100pu_kmdf.vcxproj') /m /t:Rebuild /p:Configuration=$Configuration /p:Platform=x64 /p:ExcludeRestorePackageImports=true "/p:WDKContentRoot=$wdkRootWithSlash" /warnAsError /v:minimal
if ($LASTEXITCODE) { throw "Build failed: $LASTEXITCODE" }
$infverif = Join-Path $wdkRoot "Tools\$script:EzWdkContentVersion\x64\infverif.exe"
$inf2cat = Join-Path $wdkRoot "bin\$script:EzWdkContentVersion\x86\Inf2Cat.exe"
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
$hashes = @(Get-ChildItem $package -File | Where-Object FullName -ne $manifest | ForEach-Object {
    Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName
})
$hashes | Select-Object Hash,Path | Export-Csv $manifest -NoTypeInformation
Write-Host "Validated package: $package"
