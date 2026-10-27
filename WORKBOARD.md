# WORKBOARD.md — Wer arbeitet gerade woran?

Pflichtdatei, sobald **mehr als ein Agent** am Repo arbeitet (verhindert gleichzeitige Änderungen derselben Datei).

## Regeln

1. **Vor der ersten Änderung** eine Zeile unter „Belegt“ eintragen: Agent, Bereich, Dateien, Datum.
2. **Nur selbst belegte Dateien ändern.** Fremd belegte nicht anfassen, sondern dem Nutzer sagen, was dort nötig wäre.
3. **Fertig heißt: im Spiel vom Nutzer bestätigt.** Committen nur auf Zuruf.
4. **Beim Committen nur eigene Dateien stagen** (bei gemischten Dateien: `git diff <datei>` → eigene Hunks → `git apply --cached`).
5. **Beim Beenden/Pausieren** eigene Zeilen aktualisieren oder entfernen.
6. Datei **immer frisch lesen**, bevor man sie bearbeitet.

---

## Belegt

*(derzeit keine)*

## Stand (27.10.2026)

**KaosLoot 1.1.1 ist veröffentlicht** (CurseForge, Release; `origin/main` = `8b6fbdb`, Arbeitsbaum sauber). Nur für Forever. Zips und Changelogs liegen in `..\KaosLoot-releases\`: die **aktuelle** Version (Zip, `changelog-<Version>-kaosloot.md`, `curseforge-description-kaosloot.md`) auf oberster Ebene, alles Hochgeladene und Ältere in `old.releases\`. Beim nächsten Release die alten Dateien dorthin verschieben.

**Release-Ablauf:** Tests (unten) → Version in TOC, `Neu.LISTE` (Neu.lua + Texte in `Locale.lua`; alte Abschnitte kürzen), `README.md`, `release/LIESMICH.txt`, Changelog (EN zuerst, dann DE) → committen → `python release/bauen.py --cf` **aus dem Commit** (nicht `--aktuell`) → Upload macht der Nutzer → Push nur auf Go (vorher `git fetch`, neben dem Nutzer schreibt `xqp`).

**Verlauf (Details: `git log`, Regeln in `AGENTS.md`):**

| Version | Inhalt |
|---|---|
| 0.9.0–0.9.2 (Beta) | erste CurseForge-Fassungen; Kompaktfenster, Rang-Sortierung/Klassenfarben, Einladen per Flüstern, Raid erst bei 5, Einteilung nur Raidkader |
| 1.0.0 | Forever-Beta beendet (23.10.), „Neu in KaosLoot“ (`/kl neu`), Umbenennung (Anzeigename) |
| 1.0.1 | Ordner/TOC/Repo/Zip `KaosLoot`, Befehl `/kl` (`/fs` bleibt stiller Altbefehl); Daten jetzt `SavedVariables\KaosLoot.lua` (`FairshareDB`, Rahmennamen, Präfix bleiben). ⚠️ Alter Ordner `Fairshare` muss weg |
| 1.1.0 | Verteilung: zwei Verfahren (Punkte mit Zuschlägen = Standard / Items pro Abend), Regel „Heute schon ein Item“ (Standard streng), Korrektur der Leitung (±20, Pflichtkommentar), `/kl verfahren|korrektur|vergleich`, Modul `Verteilung.lua`. **Keine Item-Gewichte** (Entscheid 24.10.). Alle brauchen 1.1.0 |
| 1.1.1 | Spielerliste: Items und Wertung getrennte Spalten (auch Kompaktfenster), „Haupt“ heißt „Wertung“ |

**Tests (vor jedem Commit):** `python luacheck.py` · `python tests/rechenkern.py` (501) · `python tests/szenarien.py` (75, **ohne `-I`**, sonst findet Python `lupa` nicht) · `python tests/texte.py --streng` (882) · dann `.\deploy.ps1` (rollt in `_forever_` und `_classic_beta_` aus; Änderungen `/reload`, neue Dateien WoW-Neustart). Lua-Text nie per Heredoc, sondern per Write-Werkzeug; Patches als Python-Skripte (CRLF erhalten, `python -X utf8`). `tests/sim.py` hat eine eigene Uhr und kennt Flüstern.

## Im Spiel bestätigt

Regelwerk (Wertung, Zuschläge, Neuling, Gast, Rückgabe), Würfelfenster inkl. Passen/frühem Ende, „Nutzen?“ nur für den Plündermeister, geteilte Einstellungen mit Sperre/Selbstheilung, Raidkader per Rangsync, Einteilung, Bench, Keine Meldung, Abschluss je Gruppe, Wochenabschluss, vereinfachte Bedienung (Ausklappliste, zwei Listen, Reiter nach Schreibrecht), gildenweiter Reset, Handel-Fix, Kompaktfenster mit Wurf starten, Klassenfarben, Sortierung, Tooltip.

## Noch nicht im Spiel gesehen (zuerst prüfen lassen)

1. **Verteilung 1.1.0:** Verfahren „Items pro Abend“, Heute-Regel, Korrektur der Leitung, `/kl vergleich`.
2. Raid-Größen 10er/20er/40er, Globale Wertung, gruppenweiser Wochenabschluss mit `[Gruppe pausiert]`, `[Gruppe einladen]`, Verlauf-Suche, persönliche Einteilung im Reiter Spieler.
3. Reiter „Anwesenheit“ (Default = Anwesend), Probe-Modus (`/kl probe`, `/kl probe abend`; schützt die echten Daten, Szenario 71).
4. **Leitungs-Abgleich** (zwei Schreibberechtigte ohne Gruppe; sonst `/kl abgleich status`, `Konfig.Darf`, ob Forever Addon-Flüstern durchlässt – ungemessen), Auto-Senden der Einstellungen, Raidkader beim Anmelden, Chat-Meldung beim Gruppen-Abgleich.
5. Einladen per Flüstern (`/kl einladewort`), Raid erst bei 5 Mitgliedern, manuelle Anhebung (`/kl anhebung`).
6. Leeres erstes Öffnen nach dem Anmelden (sonst `/kl darstellung`); offen: großes Fenster ging beim Wurfstart trotz offenem Kompaktfenster wieder auf (nicht nachstellbar).
7. Texte „Anmeldung vergessen“ → „Keine Meldung“ noch nicht überall vereinheitlicht.

## Entscheide des Nutzers (nicht neu aufrollen)

- **Default = Anwesend** (22.10.): Wer in der Einteilung der Gruppe steht und nicht als Bank/Abwesend/Unentschuldigt markiert ist, zählt als im Raid. Die ältere Regel „am Abendende in der Gruppe“ gilt nicht mehr.
- Abgemeldete werden **nirgends eingeteilt**: Raidkader und in der Raid-ID (Woche ab Wechseltag, Standard Mittwoch) nirgends eingeteilt = abgemeldet; Buchung per „Woche abschließen“, **zwei Zuschläge**, Schnitt = Mittel der Gruppen-Schnitte je Abend-Nummer. „Keine Meldung“ ist ein Ziel der Einteilung.
- Einteilung gilt **einmal je Raid-ID**; Raidleitung baut die Gruppen so, dass an beiden Tagen dieselben Spieler stehen, Teilzeit-Spieler auf die Bank. Wer irgendwo zugewiesen ist, erscheint in den anderen Rubriken nicht mehr (links nur Freie).
- Anwesenheit und Einteilung sieht nur, wer Schreibrecht hat (Gildenrang); Raidkader automatisch beim Anmelden, Rang geteilt. **Stufe 1 und 2 sind die Wurzel des Vertrauens**; nur sie ändern die Rangstufe.
- **Automatische Anhebung aus** (`Kern.AUTO_ANHEBUNG = false`), nur manuell; Neuling-Einstieg am 2. Abend bleibt. **OS-Standard 1-99** (gespeicherte Bereiche bleiben, bis „Standardbereiche“ geklickt und geteilt wird).
- **Keine Anbindung an andere Addons** (Gargul am 22.10. entfernt, keine Absprache mit dem Entwickler). Verworfen: automatische Umteilung/Warnung bei „raidet in anderer Gruppe“. Fenster-Mindestbreite 880.

## Offene Ideen (nichts beauftragt)

- Kleineres Fenster (Werkzeugleiste umbrechen/Überlaufmenü) – erst wenn alles andere durch ist.
- Übersicht „wer war an den letzten Abenden da“ (Daten liegen je Abend in `abschluss.spieler`).
- Einteilung hat kein Nachholen für Verpasste (Einstellungen haben es); Leitungs-Abgleich begrenzt eine Runde auf 600 Einträge je Spieler (`MAXEINTRAEGE`).
- Regelwerk-Doc der Gildenleitung und `ANLEITUNG.md` nennen die Anhebung noch automatisch bzw. sind nicht auf `REGELWERK-ENTWURF.md` (Stand 22.10.) abgeglichen; CurseForge-Beschreibung nach Änderungen nachziehen.

## Stolperfallen

- Die Zeilen der Übersicht (`Fenster.lua`) dienen allen Ansichten: Wer eine Ansicht erweitert, versteckt die Knöpfe der anderen ausdrücklich.
- ⚠️ `Fenster.lua` steht bei 60 Upvalues je Funktion (Lua 5.1): keine neuen Datei-`local`s, neue Fenster in eigene Dateien (wie `Kompakt.lua`). `luacheck.py` findet das nicht, `tests/szenarien.py` schon.
- Der Prüfstand (`Anwesenheit._SetDB`) nutzt die Liste des letzten Bosses statt der echten Gruppe; überall `date(…, time())`.
- Ein schlafendes Addon (kein Plündermeister, „Nein“) hört nur `K`, `A`, `T`, `U` (Weiche in `Abgleich.lua`).
- Die Fenster-Mindestbreite stützt sich auf die Knöpfe der Werkzeugleiste: neue Knöpfe dort zuerst auf Überlappung prüfen.
- ⚠️ Der Release-Client `_forever_` hat eigene SavedVariables; Beta-Daten (`_classic_beta_`) liegen dort nicht, der Abgleich füllt sie.
