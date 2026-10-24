# deploy.ps1 (KaosLoot in WoW Forever ausrollen: Release-Client und, falls noch da, die Beta)
#
# Das Addon ist nur fuer WoW Forever. TBC Anniversary braucht es
# nicht (Entscheid des Gildenleiters, 14.10.2026).
#
# Umzug von "Fairshare" nach "KaosLoot" (Version 1.0.1, 24.10.2026):
#   * Ordner und TOC heissen jetzt KaosLoot; die Daten liegen in SavedVariables\KaosLoot.lua
#     statt Fairshare.lua (die Variable FairshareDB bleibt). Dieses Skript uebernimmt
#     Fairshare.lua einmalig nach KaosLoot.lua und entfernt den alten Ordner Fairshare,
#     sonst liefe das Addon doppelt. Auch das braucht beendetes WoW; die alte Datei bleibt liegen.
#
# Umzug von "Loot-Historie" nach "Fairshare" (14.10.2026, heute nach KaosLoot.lua):
#   * WoW legt gespeicherte Daten unter dem Namen des Addon-Ordners ab
#     (SavedVariables\<Ordnername>.lua). Beim neuen Namen waere alles weg.
#   * Dieses Skript uebernimmt deshalb einmalig LootHistorie.lua nach
#     KaosLoot.lua (Variable LootHistorieDB -> FairshareDB) und entfernt den
#     alten Ordner.
#   * ⚠️ Das geht nur, wenn WoW BEENDET ist: Erst beim Ausloggen schreibt das
#     Spiel den aktuellen Stand. Solange der alte Ordner noch da ist und WoW
#     laeuft, bricht das Skript ab und aendert nichts.
#   * Die alte Datei bleibt als Sicherung liegen.
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File .\deploy.ps1

$ErrorActionPreference = "Stop"

$src  = Join-Path $PSScriptRoot "KaosLoot"
$root = "C:\Program Files (x86)\World of Warcraft"

$clients = @("_forever_", "_classic_beta_")

if (-not (Test-Path $src)) {
    throw "Quellordner nicht gefunden: $src"
}

function WowLaeuft {
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^Wow' }).Count -gt 0
}

$ausgerollt = 0
foreach ($client in $clients) {
    $addons = Join-Path $root "$client\Interface\AddOns"
    if (-not (Test-Path $addons)) {
        Write-Host "uebersprungen: $client (nicht installiert)" -ForegroundColor DarkGray
        continue
    }

    # ---- Umzug vom alten Namen -------------------------------------------
    $alt = Join-Path $addons "LootHistorie"
    if (Test-Path $alt) {
        if (WowLaeuft) {
            throw ("WoW laeuft noch. Der alte Stand von Loot-Historie muss erst gespeichert werden: " +
                   "bitte das Spiel BEENDEN (nicht nur /reload) und dieses Skript danach nochmal starten. " +
                   "Es wurde nichts veraendert.")
        }

        $konten = Join-Path $root "$client\WTF\Account\*\SavedVariables\LootHistorie.lua"
        foreach ($datei in @(Get-ChildItem -Path $konten -ErrorAction SilentlyContinue)) {
            $ziel = Join-Path $datei.DirectoryName "KaosLoot.lua"
            if (Test-Path $ziel) {
                Write-Host "Daten schon uebernommen: $ziel" -ForegroundColor DarkGray
                continue
            }
            $text = [System.IO.File]::ReadAllText($datei.FullName, [System.Text.Encoding]::UTF8)
            $text = $text -replace 'LootHistorieDB', 'FairshareDB'
            [System.IO.File]::WriteAllText($ziel, $text, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "Daten uebernommen: $($datei.Name) -> KaosLoot.lua" -ForegroundColor Green
        }

        Remove-Item -Recurse -Force $alt
        Write-Host "alter Ordner entfernt: LootHistorie" -ForegroundColor Yellow
    }

    # ---- Umzug vom Namen Fairshare (1.0.1) ---------------------------------
    $altF = Join-Path $addons "Fairshare"
    if (Test-Path $altF) {
        if (WowLaeuft) {
            throw ("WoW laeuft noch. Der Ordner Fairshare heisst jetzt KaosLoot: Die Daten muessen erst gespeichert werden. " +
                   "Bitte das Spiel BEENDEN (nicht nur /reload) und dieses Skript danach nochmal starten. " +
                   "Es wurde nichts veraendert.")
        }
        $kontenF = Join-Path $root "$client\WTF\Account\*\SavedVariables\Fairshare.lua"
        foreach ($datei in @(Get-ChildItem -Path $kontenF -ErrorAction SilentlyContinue)) {
            $zielF = Join-Path $datei.DirectoryName "KaosLoot.lua"
            if (Test-Path $zielF) {
                Write-Host "Daten schon uebernommen: $zielF" -ForegroundColor DarkGray
                continue
            }
            Copy-Item -Path $datei.FullName -Destination $zielF
            Write-Host "Daten uebernommen: Fairshare.lua -> KaosLoot.lua" -ForegroundColor Green
        }
        Remove-Item -Recurse -Force $altF
        Write-Host "alter Ordner entfernt: Fairshare" -ForegroundColor Yellow
    }

    # ---- Einbauen -----------------------------------------------------------
    $target = Join-Path $addons "KaosLoot"
    if (Test-Path $target) {
        Remove-Item -Recurse -Force $target
    }
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    Copy-Item -Path (Join-Path $src "KaosLoot.toc") -Destination $target
    Copy-Item -Path (Join-Path $src "*.lua")          -Destination $target
    Copy-Item -Path (Join-Path $src "Media")          -Destination $target -Recurse

    Write-Host "ausgerollt: $client" -ForegroundColor Green
    $ausgerollt++
}

if ($ausgerollt -eq 0) {
    throw "Kein Client gefunden unter $root"
}

Write-Host ""
Write-Host "Im Spiel: /reload, dann /fs test und /fs" -ForegroundColor Cyan
