# deploy.ps1 (Fairshare in die Forever-Beta ausrollen)
#
# Das Addon ist nur fuer WoW Forever (Beta). TBC Anniversary braucht es
# nicht (Entscheid des Gildenleiters, 14.10.2026).
#
# Umzug von "Loot-Historie" nach "Fairshare" (14.10.2026):
#   * WoW legt gespeicherte Daten unter dem Namen des Addon-Ordners ab
#     (SavedVariables\<Ordnername>.lua). Beim neuen Namen waere alles weg.
#   * Dieses Skript uebernimmt deshalb einmalig LootHistorie.lua nach
#     Fairshare.lua (Variable LootHistorieDB -> FairshareDB) und entfernt den
#     alten Ordner.
#   * ⚠️ Das geht nur, wenn WoW BEENDET ist: Erst beim Ausloggen schreibt das
#     Spiel den aktuellen Stand. Solange der alte Ordner noch da ist und WoW
#     laeuft, bricht das Skript ab und aendert nichts.
#   * Die alte Datei bleibt als Sicherung liegen.
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File .\deploy.ps1

$ErrorActionPreference = "Stop"

$src  = Join-Path $PSScriptRoot "Fairshare"
$root = "C:\Program Files (x86)\World of Warcraft"

$clients = @("_classic_beta_")

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
            $ziel = Join-Path $datei.DirectoryName "Fairshare.lua"
            if (Test-Path $ziel) {
                Write-Host "Daten schon uebernommen: $ziel" -ForegroundColor DarkGray
                continue
            }
            $text = [System.IO.File]::ReadAllText($datei.FullName, [System.Text.Encoding]::UTF8)
            $text = $text -replace 'LootHistorieDB', 'FairshareDB'
            [System.IO.File]::WriteAllText($ziel, $text, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "Daten uebernommen: $($datei.Name) -> Fairshare.lua" -ForegroundColor Green
        }

        Remove-Item -Recurse -Force $alt
        Write-Host "alter Ordner entfernt: LootHistorie" -ForegroundColor Yellow
    }

    # ---- Einbauen -----------------------------------------------------------
    $target = Join-Path $addons "Fairshare"
    if (Test-Path $target) {
        Remove-Item -Recurse -Force $target
    }
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    Copy-Item -Path (Join-Path $src "Fairshare.toc") -Destination $target
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
