# WORKBOARD.md — Wer arbeitet gerade woran?

Pflichtdatei, sobald **mehr als ein Agent** am Repo arbeitet. Sie verhindert, dass zwei
Agents dieselbe Datei gleichzeitig ändern oder die Arbeit des anderen überschreiben.

## Regeln

1. **Vor der ersten Änderung** eine Zeile unter „Belegt“ eintragen: Agent, Bereich, Dateien,
   Datum. Erst danach Dateien ändern.
2. **Nur Dateien ändern, die man selbst belegt hat.** Braucht man eine fremd belegte Datei:
   nicht anfassen, sondern dem Nutzer sagen, was dort geändert werden müsste und warum.
   Der Nutzer entscheidet, ob man übernehmen darf.
3. **Fertig heißt: im Spiel vom Nutzer bestätigt.** Danach Zeile nach „Erledigt, nicht
   committet“ verschieben (mit einem Satz, was es tut). Committen nur auf Zuruf des Nutzers.
4. **Beim Committen nur eigene Dateien stagen.** Bei gemischten Dateien nur die eigenen
   Abschnitte: `git diff <datei>` → eigene Hunks herausschneiden → `git apply --cached`.
5. **Beim Beenden oder Pausieren** die eigenen Zeilen aktualisieren (Stand, offene Punkte)
   oder entfernen. Eine Zeile ohne Agent dahinter blockiert sonst ewig.
6. Datei **immer frisch lesen**, bevor man sie bearbeitet — der andere Agent schreibt auch.

---

## Belegt

- **„Neu in Fairshare“ (23.10.2026, Claude, nicht committet):** `KaosLoot/Neu.lua` nach dem Vorbild von KaosUI `WhatsNew.lua`: Fenster mit Änderungsliste (`/kl neu`, Knopf „Neu“ im Kopf des großen Fensters), „!“ am Knopf bis zum ersten Öffnen, „!“ an Einstellungsseiten mit Neuem (`seite`) bis zum Besuch, Chat-Hinweis einmal je Version. Gemerkt je Version in `FairshareDB.neu`. Enthält 0.9.2 und 0.9.1. **Pflicht bei jedem Release: oben in `Neu.LISTE` einen Abschnitt für die neue Version eintragen** (Texte DE + EN in `Locale.lua`). Szenario 74. Einträge mit `seite` zählen für alle Abschnitte der Liste (nicht nur den neuesten); alte Abschnitte beim Release kürzen.

- **Umbenennung in KaosLoot (23.10.2026, Claude):** Nutzerentscheid („KaosLoot, aber noch zu 1.0.0 hinzufügen, ich lade neu hoch“). Sichtbare Texte, `## Title`, README/Anleitung/Release-Texte, Neu-Eintrag. Ordner, `/kl`, `FairshareDB`, Rahmennamen bleiben. Das 1.0.0-Zip wird neu gebaut (gleiche Versionsnummer).

## ⭐ KaosLoot 1.0.1 (Release) – Ordner umbenannt (Stand 24.10.2026)

1.0.0 ist hochgeladen. **1.0.1** benennt alles auf KaosLoot um: Addon-Ordner `KaosLoot/`, `KaosLoot.toc`, Releases-Ordner `KaosLoot-releases`, Repo-Ordner `KaosLoot`, Zip `KaosLoot-1.0.1.zip` (Ordner `KaosLoot/` darin). Der Befehl heißt `/kl` (Altbefehl `/fs` geht vorerst weiter, `/kaosloot` neu); `FairshareDB`, Rahmennamen und Protokollpräfix bleiben. ⚠️ **Wer 1.0.0 mit dem Ordner `Fairshare` installiert hat, muss den alten Ordner löschen** (CurseForge-App macht das meist selbst), sonst läuft das Addon doppelt; die Daten liegen jetzt in `SavedVariables\KaosLoot.lua` statt `Fairshare.lua` und gehen nicht automatisch über (Abgleich füllt sie; sonst die Datei bei beendetem Spiel umbenennen). `deploy.ps1` räumt den alten Ordner im eigenen Spiel auf und übernimmt `Fairshare.lua` → `KaosLoot.lua`. Texte: `..\KaosLoot-releases\changelog-1.0.1-kaosloot.md` (nach dem Upload löschen). Zip: `python release/bauen.py --cf`.

## ⭐ CurseForge 1.0.0 (Release) (Stand 23.10.2026)

Die Forever-Beta ist seit dem 23.10.2026 geschlossen. 0.9.2 ist hochgeladen und gepusht (`7a86283`). **1.0.0** = 0.9.2 + „Neu in Fairshare“ (`/kl neu`, `Neu.lua`), Beta-Hinweise raus, `deploy.ps1` rollt auch in `_forever_` aus. Release-Typ auf CurseForge: **Release** (nicht Beta). Keine Protokolländerung, kompatibel mit 0.9.x. Texte: `..\KaosLoot-releases\changelog-1.0.0-kaosloot.md` (nach dem Upload löschen), Beschreibung `curseforge-description-kaosloot.md` (Beta-Hinweis gestrichen, auf CurseForge nachziehen). Zip: `python release/bauen.py --cf`. Upload macht der Nutzer. ⚠️ Der Release-Client `_forever_` hat eigene SavedVariables: Die Daten der Beta (`_classic_beta_`) liegen dort nicht; der Abgleich unter Spielern füllt es wieder.

## ⭐ CurseForge 0.9.2 (Beta) (Stand 23.10.2026)

0.9.1 ist hochgeladen und gepusht (`01418f2`). **0.9.2** bringt: Einladen per Flüstern (`/kl einladewort`), Raid erst bei 5 Mitgliedern (vorher sofort), Einteilung zeigt nur den Raidkader. Keine Protokolländerung, **kompatibel mit 0.9.0/0.9.1**. Texte: `..\KaosLoot-releases\changelog-0.9.2-kaosloot.md` (nach dem Upload löschen), Beschreibung `curseforge-description-kaosloot.md` (Einladen per Flüstern ergänzt, auf CurseForge nachziehen). Zip: `python release/bauen.py --cf`. Upload macht der Nutzer.

## ⭐ CurseForge 0.9.1 (Beta) (Stand 22.10.2026)

0.9.0 ist hochgeladen (aus `13bcbec`, Projekt-ID 1759404, `## X-Curse-Project-ID` steht seit 0.9.1 in der TOC). **0.9.1** bringt Kompaktfenster (`/kl kompakt`, Knopf Wurf starten), Rang-Sortierung und Klassenfarben, Item-Tooltip im Verlauf, Breitenfix. Keine Protokolländerung, **kompatibel mit 0.9.0**. Texte: `..\KaosLoot-releases\changelog-0.9.1-kaosloot.md` (nach dem Upload löschen), Beschreibung `curseforge-description-kaosloot.md` (Kompaktfenster ergänzt, auf CurseForge nachziehen). Zip: `python release/bauen.py --cf` → `..\KaosLoot-releases\curseforge\Fairshare-0.9.1.zip`. Upload macht der Nutzer. Bei 1.0.0 (Ende der Forever-Beta): Version heben, Beta-Hinweis streichen.

## ⭐ CurseForge-Release 0.9.0 (Beta) vorbereiten (Auftrag des Nutzers, 22.10.2026)

**Entscheide:** Version **0.9.0**, Typ **Beta** (die Forever-Beta endet in 2 Tagen, danach **1.0.0**); Lizenz **All Rights Reserved**; **nur CurseForge** (kein Wago, kein Discord vorerst); CurseForge-Projekt **existiert noch nicht**, der Nutzer legt es an (Name „Fairshare“) und gibt die Projekt-ID (`## X-Curse-Project-ID` in die TOC). Upload macht immer der Nutzer.
**Bereit (Claude, 22.10.2026):** TOC `0.9.0` mit neuen Notes (EN/DE); `..\KaosLoot-releases\curseforge-description-kaosloot.md` (Projektbeschreibung EN + DE, ohne Spenden-Block); `..\KaosLoot-releases\changelog-0.9.0-kaosloot.md` (EN zuerst, dann DE; nach dem Upload löschen); `README.md` neu; `python release/bauen.py --cf` baut das CurseForge-Zip (nur `KaosLoot/`, ohne LIESMICH, eine TOC, prüft die Version) nach `..\KaosLoot-releases\curseforge\Fairshare-0.9.0.zip`.
**Ablauf:** (1) im Spiel prüfen lassen, dass `/kl` und `/kl test` ohne Fehler laufen und eine Probe-Runde geht (`/kl probe`), (2) Projekt auf CurseForge anlegen, Beschreibung einfügen, Screenshots aus `..\AddonScreenshots` (neue für Fairshare nötig), Logo, Lizenz, Kategorie; (3) ID in die TOC, committen, **`python release/bauen.py --cf` aus dem Commit** (nicht `--aktuell`) neu bauen; (4) Upload als **Beta**, Changelog aus der Datei einfügen, Datei danach löschen. Danach pushen. Bei 1.0.0: TOC-Version ändern, Beschreibung „Public beta“-Hinweis streichen.
**Offen/Vorsicht:** Vieles ist im Spiel noch ungetestet (Anwesenheit, Raid-Größen, Wochenabschluss, Einladung, Probe-Modus, Leitungs-Abgleich). Spieler mit der alten lokalen 0.2.0 und die neue 0.9.0 sind **nicht** protokollkompatibel genug, um zusammen zu arbeiten: alle Gildenmitglieder müssen auf 0.9.0 wechseln.

## Erledigt, nicht committet

- **Einladen per Flüstern (23.10.2026, Claude, nicht committet):** Persönliche Einstellung (`FairshareDB.einladen = { an, wort }`, Standard aus, Wort `invite`), nicht geteilt. `CHAT_MSG_WHISPER` mit genau dem Stichwort (ohne Groß-/Kleinschreibung, ohne Rand-Leerzeichen) lädt den Absender ein (`Anwesenheit.Fluestern`/`Einladen`/`EinladeWortSetzen`); nicht doppelt innerhalb 15 s, nicht wer schon in der Gruppe ist, im Raid nur als Leiter/Assistent, bei vollem Raid (40) nur Hinweis im Chat; eine volle normale Gruppe wird erst zum Raid. Einstellung: Einstellungen → Gruppen → Karte „Einladen per Flüstern“; Befehl `/kl einladewort [Wort|an|aus]` (`/kl invitekeyword`). Szenario 73. Bekannt: `Rolle.IstDabei` existiert nicht (Anwesenheit.lua prüft es nur bedingt, harmlos).
- **Raid erst bei 5 Mitgliedern (23.10.2026, Claude, nicht committet):** Das Addon machte aus jeder Gruppe sofort einen Raid, sobald eine Gruppe aktiv war. Jetzt wird eine normale Gruppe nur dann zum Raid, wenn sie schon 5 Mitglieder hat und noch jemand dazukommt: (a) Knopf „Gruppe einladen“ setzt eine Einladungsrunde (nur wenn mehr als 5 Spieler zusammenkommen sollen, läuft nach 3 Minuten ab), das Roster-Ereignis konvertiert bei 5; ist die Gruppe beim Einladen schon voll, wird vorher konvertiert; (b) Einladung von Hand (`hooksecurefunc` auf `InviteUnit`/`C_PartyInfo.InviteUnit`, nur wenn das Addon im Dienst ist und man Leiter ist) konvertiert eine volle Gruppe und wiederholt die Einladung nach 0,7 s. Szenario 66.
- **Einteilung zeigt nur den Raidkader (23.10.2026, Claude, nicht committet):** Links standen auch Spieler, die nicht (mehr) im Raidkader sind (Nutzerfund: 47 statt 25, Twink-Ränge abgewählt), weil der Pool alle in der Raid-ID Eingeteilten zusätzlich aufnahm. Jetzt stehen solche Spieler (`extern`) nie links; eine alte Einteilung bleibt rechts sichtbar und lässt sich dort entfernen. Szenario 48 prüft es.
- **Kompaktfenster (22.10.2026, Claude, nicht committet):** `KaosLoot/Kompakt.lua`, `/kl kompakt` (`/kl compact`) und Knopf „Kompakt“ im Kopf des großen Fensters. 232 px breit, nur die Wertung (niedrigste oben, eigene Zeile markiert, Platz; Verlauf und Abend gestrichen, Entscheid 22.10.2026); während eines Wurfs ersetzt der Wurf-Zustand die Reiter (Gegenstand, Zeitbalken, Würfe in der Reihenfolge der Übersicht, `Wurf.Laufend`/`Wurf.RangListe`). Knopf „–“ klappt auf eine Zeile (Dran: Name Wertung, im Wurf Gegenstand und Restzeit). Offen/zu, Zustand und Lage werden gemerkt (`FairshareDB.kompakt`, `fenster.kompakt`). Groß und Klein schließen sich gegenseitig (`Fenster.Zeigen` ↔ `Kompakt.Zeigen`; Auto-Öffnen beim Wurf überspringt das große Fenster, solange das kleine offen ist). Der Knopf „Wurf starten“ (nur wer starten darf, nur ohne laufenden Wurf) öffnet den Starter-Dialog (`Wurf.Dialog`). Offen: Nutzer sah das große Fenster beim Wurfstart trotz offenem kleinen wieder aufgehen; in der Simulation nicht nachstellbar (Szenario 72 prüft es), Ablauf im Spiel erfragen. `/kl kompakt test` zeigt eine Vorschau mit Beispieldaten (Wertung → Wurf → aus), auch solo. Szenario 72. Außerdem: Item-Tooltip im Verlauf/Spielerdetail (`Quelle.Gegenstandslink`), dynamische Mindestbreite der Knopfreihe (Einteilung/Anwesenheit), Klassenfarben auch in Spieler/Verlauf. Im Spiel ungetestet.
- **Rang-Sortierung und Klassenfarben (22.10.2026, Claude, nicht committet):** Einteilung und Anwesenheit sortieren nach Gildenrang (Gildenmeister oben, `Gruppen.RangVor`; Unbekannte zuletzt, gleicher Rang nach Name), Spielernamen in Klassenfarbe (`Gruppen.KlassenFarbe`: Klasse aus der Gildenliste, sonst aus der Gruppe via `UnitClass`). Die Gruppenfarbe steht weiter in der Gruppen-Spalte. Anwesenheit: reine Rang-Sortierung statt der bisherigen Statusgruppen. Szenario 65 prüft Reihenfolge und Farben. Im Spiel ungetestet.
- **Gargul-Anbindung entfernt (22.10.2026, Claude, nicht committet):** Auf Wunsch des Nutzers (keine Absprache mit dem Entwickler) ist alles Gargul aus dem Addon entfernt: TOC-`OptionalDeps`, `Quelle.Gargul*`, `Erfassung.Gargul*`, `Fenster.GargulAnbinden`, `/kl import`, `/kl bereiche setzen/uebernehmen`, die Gargul-Karte in Einstellungen → Würfeln & Abgleich, die Texte in `Locale.lua`, die Gargul-Szenarien (9, 12, Teile von 6, 11, 17, 26). Das Addon liest Würfe und Beute nur aus den normalen Spielmeldungen. Einstellungsseite heißt intern `wuerfeln` (vorher `gargul`).

*(derzeit keine)*

## Erledigt
- **Antigravity (20.–21.10.2026 - Globale Wertung, Wochenabschluss, Einladung & Mehrfachvergabe):**
  - **Globale Wertung:** Wertungsberechnung (`haupt` und `wertung`) ist universell und raidübergreifend (10er, 20er, 40er). Gruppen-Dropdown steuert nur die Zeilenauswahl.
  - **Gruppenweiser Wochenabschluss:** Jede Gruppe schließt ihre Woche eigenständig ab (`[Woche abschließen]`). Automatischer Endabschluss und Zuschlagsverteilung, sobald alle relevanten Gruppen bereit sind; Pausier-Option (`[Gruppe pausiert]`) für ausgefallene Raids.
  - **1-Klick-Gruppeneinladung:** Knopf `[Gruppe einladen]` in Anwesenheit lädt anwesende/eingeteilte Spieler ein, filtert Offline-Spieler via C_Club heraus und konvertiert ab 6 Spielern automatisch in einen Raid.
  - **Mehrfachvergabe & Lokalisierung:** Mehrfachvergabe desselben Gegenstands an denselben Spieler wird nicht mehr fälschlich blockiert. Durchgängige englische Lokalisierung auf nicht-deutschen Clients ohne Sprachmischung.
  - **Verlauf-Suche & Persönliche Einteilung:** Ungefilterte Historie mit Suchfeld im Verlauf; persönliche Einteilung oben rechts im Reiter „Spieler“.
  - **Dateien:** `Anwesenheit.lua`, `Abgleich.lua`, `Befehle.lua`, `Erfassung.lua`, `Fenster.lua`, `Gruppen.lua`, `Kern.lua`, `Locale.lua`, `Wurf.lua`, `tests/szenarien.py`, `tests/texte.py`.
  - **Tests:** Alle 70 Szenarien, 478 Rechenkern-Tests, 827 Locale-Schlüssel und Luacheck fehlerfrei. `deploy.ps1` ausgeführt.

## Erledigt (Claude, 22.10.2026; committet und gepusht)

Claude, 22.10.2026: **Bedienung der Gruppen vereinfacht** („viel zu kompliziert“, vom Nutzer im Spiel als „viel einfacher und sauberer“ bestätigt). Wertung und Zuteilung sind unverändert. Alle Einzelheiten stehen in `AGENTS.md` (Abschnitt „Mehrere Gruppen“, „Einstellungen teilen“, „Abgleich“, „Leitungs-Abgleich“); hier nur die Landkarte:
- **Raid-ID:** Einteilung einmal je Raid-ID (`Gruppen.IdStart/IdWechsel/IdListe`, Wechseltag geteilt, Standard Mittwoch, Konfigzeile `I|`). `Anwesenheit.WochenTage` = die sieben Tage der Raid-ID.
- **Raidkader:** liest sich beim Anmelden von selbst ein (`Gruppen.RaidkaderAuto`), Rang geteilt (`N|`). Raidtage je Gruppe und der Gruppen-Mitgliederabgleich sind nur noch Altcode, nicht mehr in der Oberfläche.
- **Fenster (`Fenster.lua`, `Stil.lua`):** Reiter „Abwesenheit“/„Einteilung“ nur mit Schreibrecht; Gruppenwahl per Ausklappliste (`Stil.Dropdown`, Pfeil selbst gezeichnet, weil die Glyph ▾ in Inter fehlt); Einteilung mit zwei Listen (links nur nirgends Zugewiesene, rechts im Ziel); Prüfstand-Haken `Fenster.GruppeWaehlen/EinteilungKlick/EinteilungReihenfolge/ReiterSichtbar/AktuelleAnsicht`.
- **Einstellungen → Gruppen:** Gruppen, Raidkader (kumulative Rang-Schalter + Synchronisieren), Raid-ID (Wechsel-Wochentag).
- **Auto-Senden:** geteilte Einstellungen gehen nach einer Änderung (mit Schreibrecht) nach 4 s von selbst an alle (`Konfig.AutoSenden`, Szenario 58).
- **Abgleich:** Chat-Meldungen für die Empfänger beim Start eines Gruppen-Abgleichs (`Abgleich.AbschlussMelden` meldet das Ende). **Leitungs-Abgleich** (Szenario 59): Spieler mit Schreibrecht gleichen Historie und Datenbuch gildenweit per Flüstern ab (`V`-Meldung in der Gilde, dann `Q/Y/N/M/D/E` als `WHISPER:<Name>`), auch ohne Gruppe und ohne Plündermeister; Schalter `leitungSync`.
- **Fix:** Zugewiesene einer gelöschten Gruppe zählen in der Einteilung als frei.
- **Zip:** `..\KaosLoot-releases\Fairshare-0.2.0.zip` (`python release/bauen.py`, aus dem letzten Commit; `release/LIESMICH.txt` ist die Anleitung für die Gildenleitung). **Alle brauchen dieselbe Fassung** (Protokoll geändert).

## Übergabe (Stand 21.10.2026)

**Commits auf `main` (alle gepusht):**

| Commit | Inhalt |
|---|---|
| `7546594` | Loot-Regelwerk Resurrected (Wertung, Zuschläge, Anhebung, Datenbuch, Würfel-Fixes) |
| `0155fc7` | Mehrere Gruppen (Raidkader, Einteilung, Bench), Abgemeldet/Offen, geteilte Einstellungen mit Vertrauenswurzel |
| `e3de7ec` | Raidtage je Gruppe, „Keine Meldung“, Wochenabschluss, schlanke Abwesenheit, Farben |
| `f2c45c6` | Dokumentation Stand 18.10.2026 |
| `639aa59` | Bedienung vereinfacht (Raid-ID, Ausklappliste, zwei Listen, Reiter nach Schreibrecht, Einstellungen → Gruppen) |
| `5eed540` | Ausklappliste zeichnet ihren Pfeil selbst |
| `d51136d` | Auto-Senden, Leitungs-Abgleich, Abgleich-Meldungen, Fix gelöschte Gruppen |
| `81eb59c` | LIESMICH für 0.2.0 |
| `719ba45` | Gildenweiter Reset (`/kl reset gilde`, Reset-Marke `Z|`), manuelle Anhebung (automatische aus), OS 1-99, Handel-Fix, Selbsttest-Fix, Auto-Senden-Nachbesserung |
| `fe784e8` | Antigravity: Raid-Größen 10er/20er/40er, einzelne Gildenränge im Raidkader, Reiter „Anwesenheit“ (Default = Anwesend, Knöpfe Bank/Abwesend/Unent.), Probe-Abend, `bauen.py --aktuell` |
| `02f3df0` | Antigravity: Globale Wertung, gruppenweiser Wochenabschluss, 1-Klick-Einladung, Verlauf-Suche, Mehrfachvergabe |

**Tests (immer vor dem Commit laufen lassen):**
`python luacheck.py` · `python tests/rechenkern.py` (478) · `python tests/szenarien.py` (72 Szenarien; **ohne `-I`**, sonst findet Python `lupa` nicht) ·
`python tests/texte.py --streng` (828 Schlüssel; ungenutzte Schlüssel aus `Locale.lua` entfernen) · danach `.\deploy.ps1` (rollt in `_classic_beta_` aus; Änderungen: `/reload`, neue Dateien: WoW-Neustart).
Patches bisher als Python-Skripte im Scratchpad (CRLF erhalten, `python -X utf8`); Lua-Text nie per Heredoc, sondern per Write-Werkzeug. Die Simulation (`tests/sim.py`) hat eine eigene Uhr, rechnet `time({Tabelle})` wie im Spiel und kennt Flüstern (`WHISPER`, nur der Empfänger bekommt es).

**Im Spiel vom Nutzer bestätigt:** Regelwerk (Wertung, Zuschläge, Anhebung, Neuling, Gast, Rückgabe), Würfelfenster inkl. Passen und frühem Ende, „Fairshare nutzen?“ nur für den Plündermeister, geteilte Einstellungen mit Sperre/Selbstheilung, Raidkader per Rangsync, Einteilung, Bench, „Keine Meldung“, Abschluss je Gruppe, Gruppenwechsel = anderer Abend, schlanke Abwesenheit, Wochenabschluss (Buchung); **neu 22.10.:** die vereinfachte Bedienung (Ausklappliste mit gezeichnetem Pfeil, zwei Listen, Reiter nur mit Schreibrecht – ein Spieler ohne Recht sah nur „Spieler“/„Verlauf“), Gruppen kommen per „An alle senden“ bei den anderen an.

**NOCH NICHT im Spiel gesehen (zuerst prüfen lassen):**
0. **Antigravity 20.–21.10.:** Raid-Größen (10er/20er/40er, Einteilung je Größe), Globale Wertung, gruppenweiser Wochenabschluss mit `[Gruppe pausiert]`, `[Gruppe einladen]`, Verlauf-Suche, persönliche Einteilung im Reiter Spieler. ⚠️ Protokoll/Datenstruktur geändert (`S|`, Einteilung je Größe, `T;?`): **alle brauchen die neue Fassung; Zip neu bauen** (`python release/bauen.py` aus dem Commit oder `--aktuell`).
0b. **Probe-Modus schützt die echten Daten** (21.10., Claude): `Erfassung.GildenReset/ResetAnwenden` sind im Probe-Modus gesperrt; `Konfig.Senden/AutoSenden` sperrt der Probe-Modus selbst (`Anwesenheit.lua`). Szenario 71.
1. **Reiter „Anwesenheit“ & Default = Anwesend** (neu 22.10.): Eingeteilte Spieler ohne Eintrag sind automatisch anwesend (grün). 3 Knöpfe `[Bank/Bench] [Abwesend] [Unent.]` zum 1-Klick-Toggle. Kein Panik-Abschluss mehr vor dem Verlassen der Gruppe nötig.
2. **Probe-Modus / Übungsmodus** (neu 22.10.): `/kl probe abend` (Chat-Simulation mit 14 Spielern, 6/6 Prüfungen) und `/kl probe` (UI-Leiste, Item-Vergabe, isolierte Wegwerf-DB).
3. **Leitungs-Abgleich** (Nutzer testet am 23.10.2026): zwei Spieler mit Schreibrecht, nicht in einer Gruppe, auf unterschiedlichem Stand; nach 1–2 Minuten muss der andere „Mit der Leitung abgeglichen: …“ im Chat sehen. Falls nichts passiert: `/kl abgleich status` (Zeile „Leitungs-Abgleich: aktiv“), `Konfig.Darf` (Gildenliste geladen? Rang im Bereich?), ob Flüstern in Forever Addon-Nachrichten durchlässt (ungemessen).
4. **Auto-Senden** der Einstellungen nach einer Änderung (Chat: „Geänderte Einstellungen wurden an alle gesendet.“).
5. **Raidkader liest sich beim Anmelden von selbst ein** (25 s; nur wenn ein Rang gewählt ist und die Gildenliste da ist).
6. Chat-Meldung beim Start eines Gruppen-Abgleichs bei den Empfängern.
7. Farben je Gruppe in der Einteilung, „Neuen Abend beginnen“ in einer abgeschlossenen Anwesenheit.
8. Das leere erste Öffnen nach dem Anmelden (Schrift vorladen, `Stil.SchriftVorladen`/`AuffrischenBisFertig`). Bleibt es leer: `/kl darstellung` ausgeben lassen.

**Entscheide des Nutzers, die nicht offensichtlich sind (nicht neu aufrollen):**
- ✅ **Vom Nutzer bestätigt (22.10.2026):** Im Raid = wer in der Einteilung der Gruppe steht und nicht als Bank/Abwesend/Unentschuldigt markiert ist (**Standard = Anwesend**). Grund: weniger zu verwalten, kein Zeitdruck beim Abschluss. Der Knopf „Abwesend“ bleibt. Die ältere Regel „Im Raid = am Abendende in der Gruppe“ (17.10.) gilt nicht mehr.
- Abgemeldete werden **nirgends eingeteilt**: Wer im Raidkader steht und in der **Raid-ID (Woche ab dem Wechseltag, Standard Mittwoch)** nirgends eingeteilt war, ist abgemeldet; Buchung per
  „Woche abschließen“, **zwei Zuschläge je Spieler**, Schnitt = Mittel der Gruppen-Schnitte je Abend-Nummer. „Keine Meldung“ ist ein Ziel der Einteilung.
- (seit 22.10.2026) Die Einteilung gilt **einmal je Raid-ID** (eine Woche ab einstellbarem Wechseltag, Standard Mittwoch); Raidleitung baut die Gruppen so, dass an beiden Tagen dieselben Spieler stehen, Teilzeit-Spieler kommen auf die Bank. Die Raidtage je Gruppe stehen nicht mehr in der Oberfläche.
- Anwesenheit und Einteilung sieht nur, wer Schreibrecht hat (Gildenrang); alle anderen nur Spieler und Verlauf. Raidkader automatisch beim Anmelden, Rang geteilt.
- **Stufe 1 und 2 sind die Wurzel des Vertrauens** (dürfen immer senden/einteilen/buchen); die Rangstufe ändern nur sie; andere sehen geteilte Einstellungen nur lesend.
- Verworfen: automatische Umteilung/Warnung, wenn jemand in einer anderen Gruppe raidet als eingeteilt (Raidleitung organisiert vorher).
- Fenster-Mindestbreite 880.

## Erledigte Sonderaufgaben

- **Übungsmodus „Probe-Abend“ & UI-Modus (`/kl probe`, `/kl probe abend`):**
  - Vollständige Simulation eines Abends mit 14 Spielern (10 im Raid [inkl. Igor 1. Abend Proberaid, Jonas 2. Abend Neuling], 2 abgemeldet [Kevin, Lisa], 1 weder an- noch abgemeldet [Max], 1 Bench [Nora]).
  - Textausgabe `/kl probe abend` (6/6 Prüfungen grün).
  - UI-Bedienleiste (`probeLeiste`) mit Spieler-Auswahl, Item-Vergabe (Main/OS), Status-Schaltern (Bench, Abwesend, Unent.), Fertiger Ablauf, Zurücksetzen.
  - Volle Netzwerk- und Speicherisolation (`Anwesenheit._SetDB`, `_SetAnwesende`, Senden gesperrt).
- **Reiter „Anwesenheit“ & Default = Anwesend:**
  - Reiter von „Abwesenheit“ in „Anwesenheit“ umbenannt.
  - 5-Spalten-Layout mit 3 Knöpfen `[Bank] [Abwesend] [Unent.]` je Zeile für direktes Umschalten mit 1 Klick.
  - Standard für eingeteilte Spieler ist `Anwesend` (grün, Faktor 0, kein Zuschlag).
  - Raidleiter kann den Abend auch nach dem Verlassen der Gruppe durch Spieler ohne Wertungsverfälschung abschließen.

**Offene Punkte / Ideen (alle vom Nutzer so gewollt, nichts davon beauftragt):**
- **Kleineres Fenster ermöglichen** (später, erst wenn alles andere durch ist): Werkzeugleiste umbrechen/Überlaufmenü, kürzere Knöpfe, Spalten einklappen.
- „Anmeldung vergessen“ heißt in manchen Texten noch so, der Knopf/das Ziel heißt „Keine Meldung“ (Vereinheitlichung der Texte offen).
- Eine Übersicht „wer war an den letzten Abenden da“ (Spielerdetail oder Tabelle für alle) gibt es nicht; die Daten liegen je Abend in `abschluss.spieler`.
- Das für die Gildenleitung geteilte Regelwerk (Claude-Doc) ist **nicht** automatisch aktuell: Inhalt = `REGELWERK-ENTWURF.md` (Stand 22.10.2026) dort einfügen.
- Wer **Bench-Spieler einspringen** lassen will: in der Einteilung beim Ziel „Bench“ entfernen, dann der Gruppe zuweisen (links stehen nur nirgends Zugewiesene); in der Abwesenheit springt ein Bench-Spieler mit einem Klick auf „✓ Bench“ in die aktive Gruppe ein. Entscheid des Nutzers 22.10.2026: Wer irgendwo zugewiesen ist, erscheint in den anderen Rubriken nicht mehr.
- Die Einteilung hat kein Nachholen für Spieler, die sie verpasst haben (Einstellungen haben es); sie bekommen sie, wenn jemand mit Schreibrecht „Einteilung senden“ drückt.
- Der Leitungs-Abgleich begrenzt eine Runde auf 600 Einträge je Spieler (`MAXEINTRAEGE`); große Rückstände brauchen mehrere Runden (nächste `V`-Meldung, spätestens nach 15 Minuten).
- **OS-Standard seit 22.10.2026 1-99** (vorher 1-50, ): `Kern.BEREICHE`, `Erfassung.lua`, `Einstellungen.lua` (Knopf „Standardbereiche“). Bereits **gespeicherte** Bereiche (1-50) bleiben, bis die Gildenleitung „Standardbereiche“ klickt und die Einstellungen teilt (geht jetzt von selbst); alle Würfelfenster und Tests richten sich nach dem Bereich des Leiters.
- **Gildenweiter Reset (22.10.2026, committet `719ba45`, im Spiel bestätigt (kam bei Xalessa nach einiger Zeit an); Beschreibung und Szenario 60 in `AGENTS.md`):** `/kl reset gilde` / Einstellungen → Erfassung → „Für alle zurücksetzen“, nur Stufe 1 und 2. Reset-Marke `Z|` in den geteilten Einstellungen; Alt-Daten werden danach nicht mehr angenommen. **Im Spiel prüfen:** Reset als Gildenmeister, ein Offizier/Mitglied online sieht die Chatmeldung und eine leere Liste; ein Spieler, der beim Reset offline war, bekommt ihn beim Anmelden; `/kl reset undo` danach verweigert. Alle brauchen dieselbe Fassung.
- **Anhebung (19.10.2026, committet `719ba45`, im Spiel ungetestet):** Auf Entscheid des Nutzers ist die **automatische Anhebung abgeschafft** (`Kern.AUTO_ANHEBUNG = false`), es gibt eine **manuelle** (`Anwesenheit.AnhebungSetzen`, Einstellungen → Gruppen → Anhebung mit Namensfeld, `/kl anhebung <Name>`; nur Raid-/Gildenleitung). Der Neuling-Einstieg am 2. Abend bleibt. Beschreibung in `AGENTS.md`/`REGELWERK-ENTWURF.md` § 3. Das Google Doc „Fairshare Kurzanleitung“ und `ANLEITUNG.md` nennen die Anhebung noch automatisch und müssen angepasst werden.
- Push von `origin/main` vorher mit `git fetch` prüfen (neben dem Nutzer schreibt `xqp`).

**Stolperfallen, die uns Zeit gekostet haben:**
- Die Zeilen der Übersicht (`Fenster.lua`) werden von allen Ansichten benutzt: Wer eine Ansicht erweitert, muss die Knöpfe der anderen dort ausdrücklich verstecken.
- Der Prüfstand (`Anwesenheit._SetDB`/Tests) nutzt die Liste des letzten Bosses statt der echten Gruppe; die Simulation hat eine eigene Uhr (`time()`), daher überall `date(…, time())`.
- Ein schlafendes Addon (kein Plündermeister, „Nein“) hört nur `K`, `A`, `T`, `U` (Weiche in `Abgleich.lua`); alles andere ist gesperrt.
- Die Fenster-Mindestbreite stützt sich auf die Knöpfe in der Werkzeugleiste; neue Knöpfe dort zuerst auf Überlappung prüfen.
