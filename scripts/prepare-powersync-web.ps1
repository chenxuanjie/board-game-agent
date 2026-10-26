param([string]$Dart = 'dart')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & $Dart run powersync:setup_web --output-dir web/powersync
    if ($LASTEXITCODE -ne 0) { throw 'PowerSync Web asset download failed' }
    & $Dart compile js -O4 --no-source-maps tool/powersync_worker.dart -o web/powersync/powersync_db.worker.js
    if ($LASTEXITCODE -ne 0) { throw 'PowerSync worker compilation failed' }
    $workerPath = Join-Path (Get-Location) 'web/powersync/powersync_db.worker.js'
    Remove-Item -LiteralPath "$workerPath.deps" -ErrorAction SilentlyContinue
    $workerHash = (Get-FileHash -LiteralPath $workerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $source = "// Generated SDK worker fingerprint.`nconst boardWorkerVersion = '$workerHash';`n"
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) 'lib/features/identity/services/board_worker_version.dart'), $source, [System.Text.UTF8Encoding]::new($false))
    $names = @('powersync','sqlite_async','sqlite3_web','sqlite3','http','uuid','async','logging','collection','web','meta','path','typed_data','crypto')
    $lock = [System.IO.File]::ReadAllText((Join-Path (Get-Location) 'pubspec.lock'))
    $versions = [ordered]@{}
    foreach ($name in $names) {
        $block = [regex]::Match($lock, "(?ms)^  ${name}:\r?\n.*?(?=^  [a-zA-Z0-9_]+:|^sdks:)")
        $version = [regex]::Match($block.Value, 'version: "([^"]+)"')
        if (!$version.Success) { throw "Missing pinned dependency: $name" }
        $versions[$name] = $version.Groups[1].Value
    }
    $versions | ConvertTo-Json | Set-Content -LiteralPath web/powersync/dependencies.json -Encoding utf8
    & $Dart format lib/features/identity/services/board_worker_version.dart
    if ($LASTEXITCODE -ne 0) { throw 'Worker metadata formatting failed' }
} finally { Pop-Location }
