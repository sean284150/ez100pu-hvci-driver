[CmdletBinding()]
param([string]$OutputPath = (Join-Path $PSScriptRoot '..\artifacts\source.spdx.json'))

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
try {
    $commit = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE) { throw 'A Git commit is required to create the source SBOM.' }
    $files = @()
    foreach ($relative in @(git ls-files)) {
        $absolute = Join-Path $root $relative
        if (Test-Path -LiteralPath $absolute -PathType Leaf) {
            $files += [ordered]@{
                fileName = $relative.Replace('\','/')
                SPDXID = 'SPDXRef-File-' + ([Convert]::ToBase64String(
                    [Text.Encoding]::UTF8.GetBytes($relative)).TrimEnd('=').Replace('/','-').Replace('+','_'))
                checksums = @(@{ algorithm='SHA256'; checksumValue=(Get-FileHash -Algorithm SHA256 $absolute).Hash.ToLowerInvariant() })
                licenseConcluded = 'MIT'
                copyrightText = 'NOASSERTION'
            }
        }
    }
    $document = [ordered]@{
        spdxVersion = 'SPDX-2.3'
        dataLicense = 'CC0-1.0'
        SPDXID = 'SPDXRef-DOCUMENT'
        name = 'ez100pu-hvci-driver-source'
        documentNamespace = "https://github.com/ez100pu-hvci-driver/sbom/$commit"
        creationInfo = @{
            created = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            creators = @('Tool: scripts/New-SourceSbom.ps1')
        }
        packages = @(@{
            name='ez100pu-hvci-driver'; SPDXID='SPDXRef-Package'; versionInfo='0.3.0';
            downloadLocation='NOASSERTION'; filesAnalyzed=$true; licenseConcluded='MIT';
            licenseDeclared='MIT'; copyrightText='Copyright (c) 2026'
        })
        files = $files
    }
    New-Item -ItemType Directory -Force (Split-Path $OutputPath) | Out-Null
    $document | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $OutputPath
    Get-Item $OutputPath
} finally { Pop-Location }
