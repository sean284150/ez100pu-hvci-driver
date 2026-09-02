$script:EzWdkPackageVersion = '10.0.26100.6584'
$script:EzWdkContentVersion = '10.0.26100.0'
$script:EzWdkPackageSha256 = 'C393D03DFB640B5C92F546B32F6770EF68CD3AAF691956E7D66D8E2C28A1B55E'

function Get-EzMsBuild {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'Visual Studio Installer vswhere.exe was not found.'
    }

    $msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
        -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
    if (-not $msbuild) { throw 'MSBuild was not found.' }
    return $msbuild
}

function Restore-EzWdk {
    param([Parameter(Mandatory)][string]$Root)

    $toolchain = Join-Path $Root 'obj\toolchain'
    $expanded = Join-Path $toolchain "microsoft.windows.wdk.x64.$script:EzWdkPackageVersion"
    $wdkRoot = Join-Path $expanded 'c'
    $sentinel = Join-Path $wdkRoot "Include\$script:EzWdkContentVersion\km\smclib.h"

    New-Item -ItemType Directory -Force -Path $toolchain | Out-Null
    $archive = Join-Path $toolchain "microsoft.windows.wdk.x64.$script:EzWdkPackageVersion.zip"
    $uri = "https://api.nuget.org/v3-flatcontainer/microsoft.windows.wdk.x64/$script:EzWdkPackageVersion/microsoft.windows.wdk.x64.$script:EzWdkPackageVersion.nupkg"
    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-WebRequest -Uri $uri -OutFile $archive
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
    if ($actualHash -ne $script:EzWdkPackageSha256) {
        throw "WDK NuGet package checksum mismatch. Expected $script:EzWdkPackageSha256, got $actualHash."
    }

    if (Test-Path -LiteralPath $sentinel) { return $wdkRoot }

    Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
    if (-not (Test-Path -LiteralPath $sentinel)) {
        throw "WDK package extraction did not produce $sentinel"
    }
    return $wdkRoot
}
