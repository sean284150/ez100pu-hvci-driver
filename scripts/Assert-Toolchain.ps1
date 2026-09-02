[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'Toolchain.ps1')
$msbuild = Get-EzMsBuild
$wdkRoot = Restore-EzWdk -Root $root
$sdkRoot = 'C:\Program Files (x86)\Windows Kits\10'
$required = @(
    (Join-Path $wdkRoot "Tools\$script:EzWdkContentVersion\x64\infverif.exe"),
    (Join-Path $wdkRoot "bin\$script:EzWdkContentVersion\x86\Inf2Cat.exe"),
    (Join-Path $wdkRoot "Include\$script:EzWdkContentVersion\km\smclib.h"),
    (Join-Path $wdkRoot "Lib\$script:EzWdkContentVersion\km\x64\smclib.lib"),
    (Join-Path $wdkRoot 'Include\wdf\kmdf\1.35\wdf.h'),
    (Join-Path $sdkRoot "Include\$script:EzWdkContentVersion\shared\sdkddkver.h"),
    (Join-Path $sdkRoot "Lib\$script:EzWdkContentVersion\um\x64\gdi32.lib")
)

$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count) {
    throw "Pinned WDK NuGet $script:EzWdkPackageVersion + KMDF 1.35 toolchain is incomplete:`n$($missing -join "`n")"
}

[pscustomobject]@{
    VisualStudio = '2022 Build Tools'
    SDK_WDK      = $script:EzWdkPackageVersion
    KMDF         = '1.35'
    Architecture = 'x64'
    Ready        = $true
    MSBuild      = $msbuild
    SdkRoot      = $sdkRoot
    WdkRoot      = $wdkRoot
}
