[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('android', 'windows')]
    [string]$Target,
    [ValidateSet('package', 'release', 'push')]
    [string]$Mode = 'package',
    [switch]$BumpBuild,
    [switch]$DryRun,
    [ValidateSet('default', 'service', 'webdav')]
    [string]$Destination = 'default',
    [string]$ProfilesDirectory = (Join-Path $env:USERPROFILE '.codex/skills/flutter-release-publisher/profiles'),
    [string]$PublisherRoot = 'C:/Study/MyCode/MyProject/shared_packages/flutter_release_publisher'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$matchedProfiles = @()
foreach ($file in Get-ChildItem -LiteralPath $ProfilesDirectory -Filter '*.json' -File) {
    $profileData = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if ($profileData.projectDir -and [StringComparer]::OrdinalIgnoreCase.Equals(
        [IO.Path]::GetFullPath($profileData.projectDir).TrimEnd('\', '/'), $projectRoot.TrimEnd('\', '/'))) {
        $matchedProfiles += [pscustomobject]@{ File = $file.FullName; Data = $profileData }
    }
}
if ($matchedProfiles.Count -ne 1) { throw 'Exactly one release profile must match this project' }
$selected = $matchedProfiles[0]
$releasePath = if ([IO.Path]::IsPathRooted($selected.Data.releaseDir)) {
    [IO.Path]::GetFullPath($selected.Data.releaseDir)
} else {
    [IO.Path]::GetFullPath((Join-Path $projectRoot $selected.Data.releaseDir))
}
if (-not [StringComparer]::OrdinalIgnoreCase.Equals($releasePath, (Join-Path $projectRoot 'release'))) {
    throw 'Local retention is restricted to this project release directory'
}
if ($BumpBuild -and ($Mode -ne 'release' -or $Target -ne 'android' -or $DryRun)) {
    throw 'BumpBuild requires an Android release without DryRun'
}
if ($DryRun -and $Mode -eq 'package') { throw 'Package is local-only; DryRun applies to push/release' }
if ($Destination -ne 'default' -and $Mode -eq 'package') { throw 'Destination applies to push/release' }
$arguments = @('run', 'bin/publish.dart', $Mode, '--profile', $selected.File, '--target', $Target)
if ($BumpBuild) { $arguments += '--bump-build' }
if ($DryRun) { $arguments += '--dry-run' }
if ($Destination -ne 'default') { $arguments += @('--destination', $Destination) }
Push-Location -LiteralPath $PublisherRoot
try {
    & dart @arguments
    $publisherExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($publisherExitCode -ne 0) { exit $publisherExitCode }
if ($DryRun) { exit 0 }
# No cleanup on failed build/package/upload, and no changes to remote retention.
& python (Join-Path $PSScriptRoot 'release_retention.py') --directory $releasePath --platform $Target
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
