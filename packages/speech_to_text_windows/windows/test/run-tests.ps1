$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
$output = Join-Path $repo '.local/speech-native-tests'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'MSVC C++ tools are required.' }
Import-Module (Join-Path $installation 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $installation -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
$flutterHeaders = Join-Path $repo 'windows/flutter/ephemeral'
$wrapperHeaders = Join-Path $flutterHeaders 'cpp_client_wrapper/include'
$plugin = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $output
try {
    # Compile the production translation unit against the installed Flutter and
    # Windows SDK headers, without building or packaging the application.
    & cl.exe /nologo /std:c++17 /EHsc /W4 /WX /DWIN32_LEAN_AND_MEAN /DNOMINMAX "/I$flutterHeaders" "/I$wrapperHeaders" /c (Join-Path $plugin 'speech_to_text_windows_plugin.cpp')
    if ($LASTEXITCODE -ne 0) { throw 'Speech plugin compilation failed.' }
    & cl.exe /nologo /std:c++17 /EHsc /W4 /WX /DWIN32_LEAN_AND_MEAN /DNOMINMAX (Join-Path $PSScriptRoot 'platform_event_window_test.cpp') /Fe:platform_event_window_test.exe /link user32.lib
    if ($LASTEXITCODE -ne 0) { throw 'Native test compilation failed.' }
    & ./platform_event_window_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Native event dispatch test failed.' }
} finally {
    Pop-Location
}
