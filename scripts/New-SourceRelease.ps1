[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^v0\.[3-9]\.[0-9]+$')][string]$Tag,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\artifacts')
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path (Join-Path $root '.git'))) {
    throw 'Source releases must be created from a Git repository.'
}
Push-Location $root
try {
    git diff --quiet --exit-code
    if ($LASTEXITCODE) { throw 'Tracked working tree changes must be committed first.' }
    git diff --cached --quiet --exit-code
    if ($LASTEXITCODE) { throw 'Staged changes must be committed first.' }
    git rev-parse --verify $Tag 2>$null | Out-Null
    if ($LASTEXITCODE) { throw "Tag does not exist: $Tag" }

    $tracked = @(git ls-tree -r --name-only $Tag)
    $forbidden = '(?i)(^|/)(baseline|build|obj|package|artifacts)/|\.(sys|cat|pdb|pfx|pvk|cer|etl|dmp)$|thumbprint|elevated\.log$'
    $bad = @($tracked | Where-Object { $_ -match $forbidden })
    if ($bad.Count) { throw "Forbidden release files:`n$($bad -join "`n")" }

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $zip = Join-Path $OutputDirectory "ez100pu-hvci-driver-$($Tag.TrimStart('v'))-source.zip"
    if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
    git archive --format=zip --output=$zip $Tag
    if ($LASTEXITCODE) { throw 'git archive failed.' }
    $hashTargets = @($zip)
    $sbom = Join-Path $OutputDirectory 'source.spdx.json'
    if (Test-Path -LiteralPath $sbom) { $hashTargets += $sbom }
    $hashes = @($hashTargets | ForEach-Object { Get-FileHash -Algorithm SHA256 -LiteralPath $_ })
    $hashes |
        Select-Object Hash,@{Name='File';Expression={Split-Path $_.Path -Leaf}} |
        Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $OutputDirectory 'SHA256SUMS.csv')
    Get-Item $zip
} finally {
    Pop-Location
}
