[CmdletBinding()]
param([string]$Apk = (Join-Path $PSScriptRoot '../build/app/outputs/flutter-apk/app-release.apk'))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$apkPath = (Resolve-Path -LiteralPath $Apk).Path
$archive = [System.IO.Compression.ZipFile]::OpenRead($apkPath)
try {
    $forbidden = @($archive.Entries | Where-Object {
        $_.FullName -match '^assets/flutter_assets/assets/games/[^/]+/docs/' -or
        $_.FullName -match '^assets/flutter_assets/.*[.]pdf$' -or
        $_.FullName -match '^assets/flutter_assets/assets/games/.*[.](md|txt|html?|zip|7z|rar|epub|docx?)$'
    })
    if ($forbidden.Count -gt 0) {
        throw "APK contains $($forbidden.Count) prohibited game documents: $((@($forbidden | Select-Object -First 10 -ExpandProperty FullName)) -join ', ')"
    }
    if ($null -eq $archive.GetEntry('assets/flutter_assets/assets/catalog.json')) {
        throw 'APK is missing its required game catalog.'
    }
    [pscustomobject]@{
        Apk = $apkPath
        SizeMiB = [math]::Round((Get-Item -LiteralPath $apkPath).Length / 1MB, 2)
        Entries = $archive.Entries.Count
        GameDocumentEntries = $forbidden.Count
    } | ConvertTo-Json
} finally {
    $archive.Dispose()
}
