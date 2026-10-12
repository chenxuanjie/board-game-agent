param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../release')
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '..'))
$manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
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
        $entries[$ArchivePath.Replace('\', '/')] = $item.FullName
    }
}

# Only ship runtime sources and deployment inputs, not the whole checkout.
foreach ($relative in @('Dockerfile', 'Dockerfile.dockerignore', 'docker-compose.yml', 'pubspec.yaml', 'pubspec.lock', 'lib', 'web', 'packaging/docker', 'scripts/package-docker.ps1', 'docs/docker-deployment.md')) {
    Add-PackagePath (Join-Path $projectRoot $relative) "board-game-agent/$relative"
}

# Include declared fonts/assets, including local game resources ignored by Git.
foreach ($assetMatch in [regex]::Matches($manifest, '(?m)^\s*-\s+(?:(?:asset|path):\s*)?((?:assets|branding)/[^\r\n#]+)')) {
    $relative = $assetMatch.Groups[1].Value.Trim().Trim('"', "'")
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
$size = (Get-Item -LiteralPath $outputPath).Length
Write-Output "Deployment source archive: $outputPath"
Write-Output ("Size: {0:N1} MiB; files: {1}" -f ($size / 1MB), $entries.Count)
Write-Output 'Flutter/Docker build and deployment validation were not run. Extract, enter board-game-agent, then run docker compose up -d --build.'
