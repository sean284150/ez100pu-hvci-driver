[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual C++ build tools were not found.' }
$devcmd = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
$output = Join-Path $root 'artifacts\tests'
New-Item -ItemType Directory -Force $output | Out-Null
$testSource = Join-Path $PSScriptRoot 'protocol_core_tests.c'
$protocolSource = Join-Path $root 'driver\protocol_core.c'
$exe = Join-Path $output 'protocol_core_tests.exe'
$command = "`"$devcmd`" -arch=x64 -host_arch=x64 >nul && cd /d `"$output`" && cl.exe /nologo /W4 /WX /sdl /O2 `"$testSource`" `"$protocolSource`" /Fe:`"$exe`""
cmd.exe /d /s /c $command
if ($LASTEXITCODE) { throw 'Protocol test build failed.' }
& $exe
if ($LASTEXITCODE) { throw 'Protocol tests failed.' }
