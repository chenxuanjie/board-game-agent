[CmdletBinding()]
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'local-docker-proxy.py'
$startupPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex local proxy 7890.lnk'
$pythonPath = (& python -c "import sys; from pathlib import Path; print(Path(sys.executable).with_name('pythonw.exe'))").Trim()
if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) { throw 'pythonw.exe is required.' }
$owned = @(Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -eq $pythonPath -and
    $_.CommandLine.Contains($scriptPath) -and
    $_.CommandLine.Contains('forward --listen-port 7890 --proxy-port 7897')
})
if ($Remove) {
    foreach ($process in $owned) { Stop-Process -Id $process.ProcessId }
    if (Test-Path -LiteralPath $startupPath) { Remove-Item -LiteralPath $startupPath }
    Write-Host 'Removed the owned 7890 proxy alias and login shortcut.'
    return
}
$listener = @(Get-NetTCPConnection -State Listen -LocalPort 7890 -ErrorAction SilentlyContinue)
if ($listener.Count -gt 0 -and @($listener | Where-Object { $_.OwningProcess -notin $owned.ProcessId }).Count -gt 0) {
    throw 'Port 7890 belongs to another process; it was left unchanged.'
}
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($startupPath)
$shortcut.TargetPath = $pythonPath
$shortcut.Arguments = '"' + $scriptPath + '" forward --listen-port 7890 --proxy-port 7897'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle = 7
$shortcut.Description = 'Loopback-only TCP proxy compatibility alias, 7890 to 7897'
$shortcut.Save()
if ($owned.Count -eq 0) {
    Start-Process -FilePath $pythonPath -ArgumentList $shortcut.Arguments -WindowStyle Hidden
}
$deadline = [DateTime]::UtcNow.AddSeconds(5)
do {
    $listener = @(Get-NetTCPConnection -State Listen -LocalPort 7890 -ErrorAction SilentlyContinue)
    if ($listener.Count -gt 0) { break }
    Start-Sleep -Milliseconds 200
} while ([DateTime]::UtcNow -lt $deadline)
if ($listener.Count -eq 0 -or @($listener | Where-Object { $_.LocalAddress -ne '127.0.0.1' }).Count -gt 0) {
    throw 'Loopback proxy alias did not start correctly.'
}
Write-Host '127.0.0.1:7890 -> 127.0.0.1:7897; login shortcut installed.'
