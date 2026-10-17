[CmdletBinding()]
param(
    [ValidateSet('plan', 'build', 'verify')]
    [string]$Mode = 'build',
    [string]$Publisher = (Join-Path $env:USERPROFILE '.codex/skills/flutter-release-publisher/scripts/flutter-release.ps1')
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Test-Path -LiteralPath $Publisher -PathType Leaf)) {
    throw 'Flutter release publisher is required. Register the project Docker profile before building.'
}
# One entry point owns version bump, build, verification and rollback together.
& $Publisher docker -Project $projectRoot -DockerMode $Mode
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
