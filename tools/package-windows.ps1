param([string]$Compiler = 'makensis.exe', [string]$Executable = '', [string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$project = Get-Content -LiteralPath (Join-Path $projectRoot 'CMakeLists.txt') -Raw
if ($project -notmatch 'project\(ChojemaCopyKeep VERSION (\d+\.\d+\.\d+)') { throw 'Project version not found.' }
$version = $Matches[1]
if (-not $Executable) { $Executable = Join-Path $projectRoot 'build/windows/ChojemaCopyKeep.exe' }
$exe = Get-Item -LiteralPath $Executable
if ($exe.VersionInfo.FileVersion -cne $version) { throw 'Executable and project versions differ.' }
$compilerPath = (Get-Command $Compiler -ErrorAction Stop).Source
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot "dist/windows-distributions-v$version" }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$name = "ChojemaCopyKeep-windows-x64-portable-$version"
$payload = Join-Path $OutputDirectory $name
$setup = Join-Path $OutputDirectory "ChojemaCopyKeep-windows-x64-setup-$version.exe"
$archive = Join-Path $OutputDirectory "$name.zip"
foreach ($path in @($payload, $setup, $archive)) {
    if (Test-Path -LiteralPath $path) { throw "Output already exists: $path" }
}
New-Item -ItemType Directory -Path (Join-Path $payload 'docs') -Force | Out-Null
Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $payload 'ChojemaCopyKeep.exe')
foreach ($file in @('LICENSE', 'README.md', 'README.en.md', 'docs/BUILD.ko.md', 'docs/BUILD.en.md', 'docs/PRIVACY.ko.md', 'docs/PRIVACY.en.md')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $file) -Destination (Join-Path $payload $file)
}
& $compilerPath /INPUTCHARSET UTF8 /V2 "/DVERSION=$version" "/DPAYLOAD=$payload" "/DOUTPUT=$setup" (Join-Path $PSScriptRoot 'windows-installer.nsi')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Compress-Archive -LiteralPath $payload -DestinationPath $archive
$checksums = @($setup, $archive) | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($_))"
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS-windows.txt'), ($checksums -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
$checksums
