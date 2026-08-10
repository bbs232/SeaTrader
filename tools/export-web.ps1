# Re-exports the SeaTrader Web build (builds/web/) from current source.
# Run this any time after code changes to refresh what the browser build shows -
# the Web export is a frozen snapshot taken at export time, it does NOT auto-update.

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

$godotExe = $env:GODOT_EXE
if (-not $godotExe -or -not (Test-Path $godotExe)) {
    $candidates = @(
        "C:\Godot\Godot_v4.7.1-stable_win64_console.exe",
        "C:\Godot\Godot_v4.7.1-stable_win64.exe"
    )
    $godotExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $godotExe) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { $godotExe = $cmd.Source }
}
if (-not $godotExe) {
    Write-Host "Could not find the Godot executable. Set the GODOT_EXE environment variable to its full path and try again." -ForegroundColor Red
    exit 1
}

Write-Host "Using Godot: $godotExe"
Write-Host "Exporting Web build..."

& $godotExe --headless --path $projectRoot --export-release "Web" "builds/web/index.html"
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "Done. builds/web/index.html and its assets are up to date." -ForegroundColor Green
    Write-Host "If you already had the page open in a browser, hard-refresh it (Ctrl+Shift+R) - browsers cache the .wasm/.pck aggressively."
} else {
    Write-Host "Export failed with exit code $exitCode. See the Godot output above." -ForegroundColor Red
}
exit $exitCode
