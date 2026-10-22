param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../build/docker-source')
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '..'))
$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
$webPlanJson = & python (Join-Path $PSScriptRoot 'prepare-web-assets.py') (Join-Path $projectRoot 'pubspec.yaml')
if ($LASTEXITCODE -ne 0) { throw 'Web asset manifest preparation failed (Python 3 is required)' }
$webPlan = ($webPlanJson -join "`n") | ConvertFrom-Json
$versionMatch = [regex]::Match($manifest, '(?m)^version:\s*([^\s]+)')
if (-not $versionMatch.Success) { throw 'Missing version in pubspec.yaml' }
$version = $versionMatch.Groups[1].Value
if ($version -notmatch '^[0-9A-Za-z.+-]+$') { throw 'Invalid version for archive filename' }
$destination = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($destination) | Out-Null
$outputPath = Join-Path $destination "board-game-agent-$version-docker.zip"
if (Test-Path -LiteralPath $outputPath) {
    $outputPath = Join-Path $destination ("board-game-agent-$version-docker-{0}.zip" -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
}
$temporaryPath = "$outputPath.partial"
$entries = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
$directories = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

function Add-PackagePath([string]$Source, [string]$ArchivePath) {
    if (-not (Test-Path -LiteralPath $Source)) { throw "Missing packaging input: $Source" }
    $item = Get-Item -LiteralPath $Source
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Cannot package a symbolic link: $Source"
    }
    if ($item.PSIsContainer) {
        $directories.Add($ArchivePath.Replace('\', '/').TrimEnd('/') + '/') | Out-Null
        foreach ($child in Get-ChildItem -LiteralPath $Source -Force) {
            if ($child.Name -in @('.git', '.dart_tool', 'build', 'node_modules', '.idea', '.pub-cache', '.pub', 'coverage', 'test', 'example', 'examples', '.gradle', 'keystore')) { continue }
            if ($child.Name -in @('.env', 'pubspec_overrides.yaml', 'key.properties', 'local.properties', '.flutter-plugins-dependencies', 'webdav.local.json')) { continue }
            if ($child.Extension -in @('.jks', '.keystore', '.p12', '.pfx', '.pyc', '.log')) { continue }
            Add-PackagePath $child.FullName "$ArchivePath/$($child.Name)"
        }
    } else {
        if ($ArchivePath -match '/assets/games/[^/]+/docs/' -or $item.Extension -eq '.pdf') {
            throw "Game documents must not enter the Web deployment package: $ArchivePath"
        }
        $entries[$ArchivePath.Replace('\', '/')] = $item.FullName
    }
}

# Only ship runtime sources and deployment inputs, not the whole checkout.
foreach ($relative in @('Dockerfile', 'Dockerfile.dockerignore', 'docker-compose.yml', 'docker-compose.build.yml', 'pubspec.lock', 'lib', 'web', 'services/web_account/app.py', 'services/web_account/library.py', 'services/web_account/requirements.txt', 'services/web_account/Dockerfile', 'services/web_account/Dockerfile.dockerignore', 'packaging/docker', 'scripts/package-docker.ps1', 'scripts/prepare-web-assets.py', 'docs/docker-deployment.md', 'docs/web-account.md', 'docs/web-library.md')) {
    Add-PackagePath (Join-Path $projectRoot $relative) "board-game-agent/$relative"
}

# Include Web-declared images/fonts/metadata, never native-only game documents.
foreach ($relative in @('scripts/build-docker-release.py', 'scripts/build-docker-release.ps1', 'scripts/verify-docker-release.py', 'scripts/release_retention.py')) {
    Add-PackagePath (Join-Path $projectRoot $relative) "board-game-agent/$relative"
}
foreach ($relative in $webPlan.paths) {
    if ($relative.Split('/') -contains '..') { throw "Invalid asset path: $relative" }
    Add-PackagePath (Join-Path $projectRoot $relative) "board-game-agent/$relative"
}

# Follow path dependencies recursively, preserving their relative layout.
$pending = [Collections.Generic.Queue[string]]::new()
$visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$pending.Enqueue($projectRoot)
while ($pending.Count -gt 0) {
    $packageRoot = $pending.Dequeue()
    if (-not $visited.Add($packageRoot)) { continue }
    if ($packageRoot -ne $projectRoot) {
        $relative = $packageRoot.Substring($workspaceRoot.Length).TrimStart('\', '/').Replace('\', '/')
        Add-PackagePath $packageRoot $relative
    }
    $packageManifest = Get-Content -LiteralPath (Join-Path $packageRoot 'pubspec.yaml') -Raw
    foreach ($pathMatch in [regex]::Matches($packageManifest, '(?m)^\s+path:\s*["'']?((?:\.{1,2}/|packages/)[^\s"''#]+)')) {
        $dependencyRoot = [IO.Path]::GetFullPath((Join-Path $packageRoot $pathMatch.Groups[1].Value))
        if (-not $dependencyRoot.StartsWith($workspaceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Dependency outside deployment workspace: $dependencyRoot"
        }
        $pending.Enqueue($dependencyRoot)
    }
}

$skillRoot = Join-Path $env:USERPROFILE '.codex/skills/docker-deployer'
if (Test-Path -LiteralPath (Join-Path $skillRoot 'SKILL.md')) {
    Add-PackagePath $skillRoot 'codex-skills/docker-deployer'
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream = [IO.File]::Open($temporaryPath, [IO.FileMode]::CreateNew)
$archive = $null
try {
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
    $manifestEntry = $archive.CreateEntry('board-game-agent/pubspec.yaml')
    $writer = [IO.StreamWriter]::new($manifestEntry.Open(), [Text.UTF8Encoding]::new($false))
    try { $writer.Write($webPlan.manifest) } finally { $writer.Dispose() }
    foreach ($directory in ($directories | Sort-Object)) {
        $archive.CreateEntry($directory) | Out-Null
    }
    foreach ($name in ($entries.Keys | Sort-Object)) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $entries[$name], $name, [IO.Compression.CompressionLevel]::Fastest) | Out-Null
    }
} finally {
    if ($null -ne $archive) { $archive.Dispose() }
    $stream.Dispose()
}
Move-Item -LiteralPath $temporaryPath -Destination $outputPath
# Only delete recognized source packages directly inside this verified output
# directory, after the new archive is complete. Never recurse into folders.
foreach ($oldSource in Get-ChildItem -LiteralPath $destination -File) {
    if ($oldSource.FullName -ne $outputPath -and $oldSource.Name -match '^board-game-agent-.+-docker(?:-[0-9-]+)?\.zip$') {
        if ([IO.Path]::GetFullPath($oldSource.DirectoryName) -ne $destination) { throw 'Source cleanup escaped its output directory' }
        Remove-Item -LiteralPath $oldSource.FullName
    }
}
$size = (Get-Item -LiteralPath $outputPath).Length
Write-Output "Deployment source archive: $outputPath"
Write-Output ("Size: {0:N1} MiB; files: {1}" -f ($size / 1MB), $entries.Count)
Write-Output 'Flutter/Docker build and deployment validation were not run. Extract, enter board-game-agent, then run docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build.'
