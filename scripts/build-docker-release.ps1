param(
    [ValidateSet('linux/amd64', 'linux/arm64')]
    [string]$Platform = 'linux/amd64',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../release'),
    [string]$ImageTag,
    [string]$WslDistribution = 'Ubuntu'
)
$ErrorActionPreference = 'Stop'
$releaseArguments = @((Join-Path $PSScriptRoot 'build-docker-release.py'), '--platform', $Platform, '--output', $OutputDirectory)
if ($ImageTag) { $releaseArguments += @('--image-tag', $ImageTag) }
if (Get-Command docker -ErrorAction SilentlyContinue) {
    & python @releaseArguments
} else {
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { throw 'Docker CLI or an installed WSL Docker engine is required' }
    $linuxScript = & wsl -d $WslDistribution -- wslpath -u ([IO.Path]::GetFullPath($releaseArguments[0]).Replace('\', '/'))
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the WSL build script path' }
    $linuxScript = $linuxScript.Trim()
    $linuxOutput = & wsl -d $WslDistribution -- wslpath -u ([IO.Path]::GetFullPath($OutputDirectory).Replace('\', '/'))
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the WSL output path' }
    $linuxOutput = $linuxOutput.Trim()
    $linuxArguments = @('python3', $linuxScript, '--platform', $Platform, '--output', $linuxOutput)
    if ($ImageTag) { $linuxArguments += @('--image-tag', $ImageTag) }
    & wsl -d $WslDistribution -- systemctl is-active --quiet bga-docker-proxy
    if ($LASTEXITCODE -eq 0) {
        $linuxArguments = @('env', 'HTTP_PROXY=http://127.0.0.1:18080', 'HTTPS_PROXY=http://127.0.0.1:18080', 'NO_PROXY=localhost,127.0.0.1,::1') + $linuxArguments
    }
    & wsl -d $WslDistribution -- @linuxArguments
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
