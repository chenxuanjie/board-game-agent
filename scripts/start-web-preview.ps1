#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Https,
    [string]$Certificate,
    [string]$PrivateKey,
    [string]$ApiUpstream = 'https://cznas.pp.ua:18281',
    [string]$Python = 'C:/Study/MyCode/MyProject/apps/app_data_service/.venv/Scripts/python.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildPath = Join-Path $projectRoot 'build/web'
if (-not (Test-Path -LiteralPath (Join-Path $buildPath 'index.html') -PathType Leaf)) {
    throw 'An existing Web build is required. This command does not compile Flutter.'
}
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
    throw 'Select an existing Python environment with httpx, starlette and uvicorn using -Python.'
}
$port = if ($Https) { 8084 } else { 8083 }
if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
    throw "Port $port is occupied; this entry will not stop another process."
}
$arguments = @((Join-Path $PSScriptRoot 'web_preview_server.py'), '--port', "$port",
    '--directory', $buildPath, '--api-upstream', $ApiUpstream)
if ($Https) {
    if (-not $Certificate -or -not $PrivateKey -or
        -not (Test-Path -LiteralPath $Certificate -PathType Leaf) -or
        -not (Test-Path -LiteralPath $PrivateKey -PathType Leaf)) {
        throw 'HTTPS needs an existing locally trusted certificate and private key. No trust settings are changed.'
    }
    $arguments += @('--ssl-certfile', $Certificate, '--ssl-keyfile', $PrivateKey)
} elseif ($Certificate -or $PrivateKey) {
    throw 'Certificate options require -Https.'
}
& $Python @arguments
exit $LASTEXITCODE
