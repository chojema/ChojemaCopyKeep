param([switch]$Test)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio Build Tools with Desktop development with C++.' }
$vsRoot = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsRoot) { throw 'The Visual C++ toolchain was not found.' }
$vsDev = Join-Path $vsRoot 'Common7/Tools/VsDevCmd.bat'
$buildEnvironment = & $env:ComSpec /d /c "call `"$vsDev`" -no_logo -arch=x64 >nul && set"
if ($LASTEXITCODE -ne 0) { throw 'Visual C++ environment setup failed.' }
foreach ($entry in $buildEnvironment) {
    if ($entry -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
}
$buildRoot = Join-Path $projectRoot 'build/windows'
cmake -S $projectRoot -B $buildRoot -G Ninja -DCMAKE_BUILD_TYPE=Release
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }
cmake --build $buildRoot
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
if ($Test) {
    ctest --test-dir $buildRoot --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
}
