# deploy-forever.ps1 (Loot-Ordnung in den WoW-Forever-Client ausrollen)
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File .\deploy-forever.ps1

$ErrorActionPreference = "Stop"
$src    = Join-Path $PSScriptRoot "LootOrdnung"
$target = "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\LootOrdnung"

Write-Host "Quelle: $src"
Write-Host "Ziel:   $target"

if (-not (Test-Path $src)) {
    throw "Quellordner nicht gefunden: $src"
}

if (Test-Path $target) {
    Remove-Item -Recurse -Force $target
    Write-Host "Altes Ziel entfernt."
}
New-Item -ItemType Directory -Force -Path $target | Out-Null

Copy-Item -Path (Join-Path $src "LootOrdnung.toc") -Destination $target
Copy-Item -Path (Join-Path $src "*.lua")           -Destination $target

Write-Host "Fertig. Loot-Ordnung nach _classic_beta_ ausgerollt." -ForegroundColor Green
Write-Host "Im Spiel: /reload, dann /lo test" -ForegroundColor Cyan
