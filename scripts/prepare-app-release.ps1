#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('prepare', 'freeze', 'verify', 'status')]
    [string]$Mode = 'status',
    [string]$Version,
    [switch]$New,
    [string]$ProfilesDirectory = (Join-Path $env:USERPROFILE '.codex/skills/flutter-release-publisher/profiles')
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$profiles = @(Get-ChildItem -LiteralPath $ProfilesDirectory -Filter '*.json' -File | Where-Object {
    $profile = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    $profile.projectDir -and [StringComparer]::OrdinalIgnoreCase.Equals(
        [IO.Path]::GetFullPath($profile.projectDir).TrimEnd('\', '/'), $projectRoot.TrimEnd('\', '/'))
})
if ($profiles.Count -ne 1) { throw 'Exactly one release profile must match this project' }
$helper = Join-Path $env:USERPROFILE '.codex/skills/flutter-release-publisher/scripts/release_batch.py'
$arguments = @($helper, $Mode, '--project', $projectRoot, '--profile', $profiles[0].FullName)
if ($Version) { $arguments += @('--version', $Version) }
if ($New) { $arguments += '--new' }
& python @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
