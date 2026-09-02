[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio Installer vswhere.exe was not found.' }
$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe |
    Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild was not found.' }
$required = @(
    'C:\Program Files (x86)\Windows Kits\10\Tools\10.0.26100.0\x64\infverif.exe',
    'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x86\Inf2Cat.exe',
    'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
    'C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\km\smclib.h',
    'C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\km\x64\smclib.lib',
    'C:\Program Files (x86)\Windows Kits\10\Include\wdf\kmdf\1.35\wdf.h'
)

$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count) {
    throw "Pinned VS/WDK 10.0.26100.0 + KMDF 1.35 toolchain is incomplete:`n$($missing -join "`n")"
}

[pscustomobject]@{
    VisualStudio = '2022 Build Tools'
    SDK_WDK      = '10.0.26100.0'
    KMDF         = '1.35'
    Architecture = 'x64'
    Ready        = $true
    MSBuild      = $msbuild
}
