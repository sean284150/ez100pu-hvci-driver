[CmdletBinding()]
param([string]$PackageDirectory = (Join-Path $PSScriptRoot '..\package\Test'))
$ErrorActionPreference = 'Stop'
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $log = Join-Path $PSScriptRoot 'Sign-TestPackage.elevated.log'
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    $command = "& '$($PSCommandPath.Replace("'", "''"))' *> '$($log.Replace("'", "''"))'; exit `$LASTEXITCODE"
    $process = Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command
    ) -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if (Test-Path $log) { Get-Content $log }
    exit $process.ExitCode
}
$thumbprint = (Get-Content (Join-Path $PSScriptRoot 'test-cert-thumbprint.txt') -Raw).Trim()
$signtool = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
$inf2cat = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x86\Inf2Cat.exe'
& $signtool sign /sm /s My /sha1 $thumbprint /fd SHA256 (Join-Path $PackageDirectory 'ez100pu_kmdf.sys')
if ($LASTEXITCODE) { throw 'SYS signing failed.' }
Remove-Item (Join-Path $PackageDirectory 'ez100pu_kmdf.cat') -ErrorAction SilentlyContinue
& $inf2cat /driver:$PackageDirectory /os:10_25H2_X64
if ($LASTEXITCODE) { throw 'Catalog generation failed.' }
& $signtool sign /sm /s My /sha1 $thumbprint /fd SHA256 (Join-Path $PackageDirectory 'ez100pu_kmdf.cat')
if ($LASTEXITCODE) { throw 'Catalog signing failed.' }
$sysPath = Join-Path $PackageDirectory 'ez100pu_kmdf.sys'
$catPath = Join-Path $PackageDirectory 'ez100pu_kmdf.cat'
& $signtool verify /pa /v $sysPath
if ($LASTEXITCODE) { throw 'SYS test-signature verification failed.' }
& $signtool verify /pa /v $catPath
if ($LASTEXITCODE) { throw 'Catalog test-signature verification failed.' }
& $signtool verify /pa /v /c $catPath (Join-Path $PackageDirectory 'ez100pu_kmdf.inf')
if ($LASTEXITCODE) { throw 'INF is not covered by the signed catalog.' }
& $signtool verify /pa /v /c $catPath $sysPath
if ($LASTEXITCODE) { throw 'SYS is not covered by the signed catalog.' }
$sysSignature = Get-AuthenticodeSignature $sysPath
$catSignature = Get-AuthenticodeSignature $catPath
if ($sysSignature.Status -ne 'Valid' -or $sysSignature.SignerCertificate.Thumbprint -ne $thumbprint) { throw 'SYS signer does not match the test certificate.' }
if ($catSignature.Status -ne 'Valid' -or $catSignature.SignerCertificate.Thumbprint -ne $thumbprint) { throw 'Catalog signer does not match the test certificate.' }
$resolvedPackage = (Resolve-Path $PackageDirectory).Path
$manifest = Join-Path $resolvedPackage 'sha256.csv'
$filesToHash = @(Get-ChildItem $resolvedPackage -File | Where-Object Name -ne 'sha256.csv')
$filesToHash | Get-FileHash -Algorithm SHA256 | Select-Object Hash,@{Name='File';Expression={$_.Path.Substring($resolvedPackage.Length + 1)}} | Export-Csv $manifest -NoTypeInformation
