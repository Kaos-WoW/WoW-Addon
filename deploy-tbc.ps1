# deploy-tbc.ps1 (Loot-Ordnung in den TBC-Anniversary-Client ausrollen)
#
# Der Anniversary-Client dient als Prüfstand, bis World of Warcraft Forever
# da ist. Sobald dessen Ordnername feststeht, kommt ein zweites Skript dazu.
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File .\deploy-tbc.ps1

$ErrorActionPreference = "Stop"
$src    = Join-Path $PSScriptRoot "LootOrdnung"
$target = "C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\LootOrdnung"

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

Write-Host "Fertig. Loot-Ordnung nach _anniversary_ ausgerollt." -ForegroundColor Green
Write-Host "Im Spiel: /reload, dann /lo test" -ForegroundColor Cyan
