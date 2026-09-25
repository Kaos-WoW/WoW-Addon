# deploy.ps1 (Loot-Historie in alle vorhandenen Clients ausrollen)
#
# Das Addon laeuft mit derselben Quelle im TBC-Anniversary-Client und in
# der Forever-Beta. Die TOC fuehrt alle noetigen Interface-Nummern; es
# gibt keinen Grund fuer zwei Ordner.
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File .\deploy.ps1

$ErrorActionPreference = "Stop"

$src  = Join-Path $PSScriptRoot "LootHistorie"
$root = "C:\Program Files (x86)\World of Warcraft"

# Nur Clients, die es wirklich gibt. Forever zuerst, dort wird entwickelt.
$clients = @("_classic_beta_", "_anniversary_")

if (-not (Test-Path $src)) {
    throw "Quellordner nicht gefunden: $src"
}

$ausgerollt = 0
foreach ($client in $clients) {
    $addons = Join-Path $root "$client\Interface\AddOns"
    if (-not (Test-Path $addons)) {
        Write-Host "uebersprungen: $client (nicht installiert)" -ForegroundColor DarkGray
        continue
    }

    $target = Join-Path $addons "LootHistorie"
    if (Test-Path $target) {
        Remove-Item -Recurse -Force $target
    }
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    Copy-Item -Path (Join-Path $src "LootHistorie.toc") -Destination $target
    Copy-Item -Path (Join-Path $src "*.lua")            -Destination $target

    Write-Host "ausgerollt: $client" -ForegroundColor Green
    $ausgerollt++
}

if ($ausgerollt -eq 0) {
    throw "Kein Client gefunden unter $root"
}

Write-Host ""
Write-Host "Im Spiel: /reload, dann /lh test und /lh" -ForegroundColor Cyan
