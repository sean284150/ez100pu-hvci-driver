[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^1\.[0-9]+\.[0-9]+$')][string]$Version,
    [Parameter(Mandatory=$true)][string]$MicrosoftSignedPackage,
    [Parameter(Mandatory=$true)][string]$HlkEvidence,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\artifacts')
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$package = (Resolve-Path $MicrosoftSignedPackage).Path
$evidence = (Resolve-Path $HlkEvidence).Path
foreach ($name in @('ez100pu_kmdf.inf','ez100pu_kmdf.cat','ez100pu_kmdf.sys')) {
    if (-not (Test-Path -LiteralPath (Join-Path $package $name))) { throw "Missing signed package file: $name" }
}
if (-not (Get-ChildItem -LiteralPath $evidence -Filter *.hlkx -File -Recurse)) {
    throw 'An HLKX evidence package is required.'
}

$cat = Join-Path $package 'ez100pu_kmdf.cat'
$sys = Join-Path $package 'ez100pu_kmdf.sys'
$signature = Get-AuthenticodeSignature -LiteralPath $cat
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
    throw 'The catalog is not signed by a valid Microsoft signer.'
}
$signtool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Filter signtool.exe -Recurse |
    Where-Object FullName -Match '\\x64\\signtool\.exe$' | Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName
& $signtool verify /kp /v /c $cat $sys
if ($LASTEXITCODE) { throw 'Kernel-policy verification failed.' }

Push-Location $root
try {
    git diff --quiet --exit-code
    if ($LASTEXITCODE) { throw 'The source tree must be clean.' }
    $commit = (git rev-parse HEAD).Trim()
    & (Join-Path $PSScriptRoot 'New-SourceSbom.ps1')

    $stage = Join-Path $env:TEMP ("ez100pu-production-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
        Copy-Item -Path (Join-Path $package '*') -Destination $stage -Force
        Copy-Item -LiteralPath (Join-Path $root 'release\Install.ps1') -Destination $stage
        Copy-Item -LiteralPath (Join-Path $root 'release\Uninstall.ps1') -Destination $stage
        Copy-Item -LiteralPath (Join-Path $root 'release\Verify.ps1') -Destination $stage
        Copy-Item -LiteralPath (Join-Path $root 'LICENSE.txt') -Destination $stage
        Copy-Item -LiteralPath (Join-Path $root 'SUPPORT.md') -Destination $stage
        Copy-Item -LiteralPath (Join-Path $root 'artifacts\source.spdx.json') -Destination $stage
        $manifest = [ordered]@{
            Version=$Version; SourceCommit=$commit; CreatedUtc=[DateTime]::UtcNow.ToString('o');
            Signer=$signature.SignerCertificate.Subject; HardwareId='USB\VID_0CA6&PID_0010&REV_0010';
            MinimumWindowsBuild=26100
        }
        $manifest | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $stage 'release-manifest.json')
        Get-ChildItem $stage -File | Get-FileHash -Algorithm SHA256 |
            Select-Object Hash,@{n='File';e={Split-Path $_.Path -Leaf}} |
            Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $stage 'SHA256SUMS.csv')
        New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
        $zip = Join-Path $OutputDirectory "ez100pu-compatible-driver-$Version-x64.zip"
        Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
        Get-FileHash -Algorithm SHA256 $zip
    } finally {
        $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        $stageFull = [IO.Path]::GetFullPath($stage)
        if ($stageFull.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $stageFull)) {
            Remove-Item -LiteralPath $stageFull -Recurse -Force
        }
    }
} finally { Pop-Location }
