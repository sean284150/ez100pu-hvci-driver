#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Subject = 'CN=EZ100PU HVCI Prototype Test')
$ErrorActionPreference = 'Stop'
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Subject -CertStoreLocation Cert:\LocalMachine\My -HashAlgorithm SHA256 -KeyLength 3072 -NotAfter (Get-Date).AddYears(2)
$cer = Join-Path $PSScriptRoot 'ez100pu-test.cer'
Export-Certificate -Cert $cert -FilePath $cer -Force | Out-Null
Import-Certificate -FilePath $cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null
Import-Certificate -FilePath $cer -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
Set-Content (Join-Path $PSScriptRoot 'test-cert-thumbprint.txt') $cert.Thumbprint
Write-Host "Test certificate created: $($cert.Thumbprint)"
