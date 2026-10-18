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

*Nichts belegt.* Claude hat am 18.10.2026 abgegeben (Volumen aufgebraucht). Wer als Nächstes arbeitet,
trägt sich hier ein.

| Agent | Bereich | Dateien | Seit | Stand |
|---|---|---|---|---|

## Erledigt, nicht committet

Claude, 22.10.2026 (**ausgerollt, vom Nutzer im Spiel als „viel einfacher und sauberer“ bestätigt; committet, nicht gepusht**; die Punkte unten unter „Im Spiel prüfen lassen“ sind noch ohne Rückmeldung): **Bedienung der Gruppen vereinfacht** (Wertung und Zuteilung unverändert).
- **Raid-ID:** Die Einteilung gilt einmal je Raid-ID (`Gruppen.IdStart(datum)` = letzter Wechseltag ≤ Datum, Standard Mittwoch, geteilte Einstellung `idWechsel`, Konfigzeile `I|`); die Schlüssel in `FairshareDB.einteilung` sind die Startdaten. `Anwesenheit.WochenTage` = die sieben Tage der Raid-ID (statt Mo–So). `tagOk` erlaubt 10 Tage zurück bis 35 voraus.
- **Raidkader:** liest sich 25 s nach dem Anmelden von selbst ein (`Gruppen.RaidkaderAuto`); Rang geteilt (`raidkaderRang`, Konfigzeile `N|`); nach einer Übernahme geteilter Einstellungen wird neu eingelesen. Der Gruppen-Mitgliederabgleich (`AutoSynchronisieren`) läuft nicht mehr von selbst; seine Funktionen und die Raidtage je Gruppe bleiben im Code (Altdaten), sind aber nicht mehr in der Oberfläche.
- **Fenster:** Reiter „Abwesenheit“ und „Einteilung“ nur mit Schreibrecht (`Gruppen.EinteilungDarf`; ist der eigene Rang noch unbekannt, bleiben sie offen); die Gruppen-Schaltfläche ist eine **Ausklappliste** (`Stil.Dropdown`): Spieler/Verlauf = Filter, Abwesenheit = aktive Gruppe, Einteilung = Ziel (Gruppen, Bench, Keine Meldung). Einteilung mit **zwei Listen** (links verfügbar = nur nirgends Zugewiesene, rechts in der Ziel-Rubrik; Knöpfe Hinzufügen/Verschieben/Entfernen; Rechtsklick entfällt); Raid-ID-Wahl statt Tagesliste; „Raid mitzeigen“ in der Abwesenheit entfällt (immer an). Prüfstand: `Fenster.GruppeWaehlen`, `EinteilungKlick`, `EinteilungReihenfolge` (zwei Listen), `ReiterSichtbar`, `AktuelleAnsicht`.
- **Einstellungen → Gruppen:** nur noch Gruppen (anlegen/löschen), **Raidkader** (Ränge als kumulative Schalter, Knopf Synchronisieren) und **Raid-ID** (Wechsel-Wochentag). Die Karten „Aktive Gruppe“, „Gildenränge für den Kader“ und „Raidtage der Gruppe“ sind weg.
- **Auto-Senden (22.10.2026, nach dem Umbau):** geteilte Einstellungen gehen nach einer Änderung (mit Schreibrecht) nach 4 s von selbst an alle (`Konfig.AutoSenden`, Szenario 58); gelöschte Gruppen lassen Zugewiesene als frei zählen (`Fenster.lua`). Pfeil der Ausklappliste wird selbst gezeichnet (committet `5eed540`).
- **Im Spiel prüfen lassen:** (1) das Zeichen ▾ im Ausklappknopf (fehlt die Glyph in Inter, erscheint ein Kästchen), (2) Zeilenaufteilung der zwei Listen bei 880 px Breite, (3) Werkzeugleiste der Einteilung (Einteilung senden · Raid-ID · Raidkader synchronisieren · Gruppe) auf Überlappung, (4) Reiter bei einem Spieler ohne Schreibrecht, (5) das Auto-Einlesen des Raidkaders nach dem Anmelden.
- Frühere ungetestete Änderungen vom 18.10. (Schrift-Vorladen gegen das leere erste Öffnen; Spieler anderer Gruppen ausblenden) sind erledigt bzw. ersetzt; das Ausblenden über „Tage derselben ID“ ist durch die Raid-ID-Einteilung überflüssig.
- **Gepusht ist nur bis `7546594`**; lokal liegen `0155fc7`, `e3de7ec`, `f2c45c6` und der Commit zum Umbau der Bedienung. Zusatzentscheid 22.10.2026: Wer irgendwo zugewiesen ist (Gruppe, Bench, Keine Meldung), erscheint in den anderen Rubriken nicht mehr.

## Übergabe (Stand 18.10.2026 abends)

**Commits seit dem Regelwerk auf `main` (`7546594` ist gepusht, die folgenden nicht):**

| Commit | Inhalt |
|---|---|
| `7546594` | Loot-Regelwerk Resurrected (Wertung, Zuschläge, Anhebung, Datenbuch, Würfel-Fixes) |
| `0155fc7` | Mehrere Gruppen (Raidkader, Einteilung, Bench), Abgemeldet/Offen, geteilte Einstellungen mit Vertrauenswurzel |
| `e3de7ec` | Raidtage je Gruppe, „Keine Meldung“, Wochenabschluss, schlanke Abwesenheit, Farben, Gruppen blenden andere aus |
| (nächster) | Dokumentation (WORKBOARD, AGENTS, REGELWERK-ENTWURF) |

**Tests (immer vor dem Commit laufen lassen):**
`python luacheck.py Fairshare/*.lua` · `python tests/rechenkern.py` (447) · `python tests/szenarien.py` (57 Szenarien) ·
`python tests/texte.py --streng` (720 Schlüssel) · danach `.\deploy.ps1` (rollt in `_classic_beta_` aus; Änderungen: `/reload`, neue Dateien: WoW-Neustart).
Patches bisher als Python-Skripte im Scratchpad (CRLF erhalten, `python -X utf8 -I`); Lua-Text nie per Heredoc, sondern per Write-Werkzeug.

**Im Spiel vom Nutzer bestätigt:** Regelwerk (Wertung, Zuschläge, Anhebung, Neuling, Gast, Rückgabe), Würfelfenster inkl. Passen und frühem
Ende, „Fairshare nutzen?“ nur für den Plündermeister, geteilte Einstellungen mit Sperre/Selbstheilung, Raidkader per Rangsync, Einteilung
(hinzufügen, verschieben, Rechtsklick entfernt), Raidtage je Gruppe, Bench (Absence, Einspringen), „Keine Meldung“, Reihenfolge in der
Einteilung, Abschluss je Gruppe, Gruppenwechsel = anderer Abend, schlanke Abwesenheit, Wochenabschluss (Buchung funktioniert).

**Gerade gebaut, noch NICHT im Spiel gesehen (zuerst prüfen lassen):**
1. Farben je Gruppe in „Assignment“ (Gruppe 1 hellblau, 2 orange, 3 violett …, Bench teal, Keine Meldung rot).
2. Gruppen als Ziel ausgewählt → Spieler anderer Gruppen sind ausgeblendet (Bench, Keine Meldung, Nicht-Eingeteilte bleiben).
3. **„Neuen Abend beginnen“** in einer abgeschlossenen Abwesenheit (lässt die Wertungen stehen); die abgeschlossene Liste ist jetzt leer.

**Entscheide des Nutzers, die nicht offensichtlich sind (nicht neu aufrollen):**
- Im Raid = wer am **Abendende** in der Gruppe steht (nicht Boss-Quote); wer früher geht und kein Main-Item hatte, gilt als abwesend.
- Abgemeldete werden **nirgends eingeteilt**: Wer im Raidkader steht und in der **Woche (Mo–So)** nirgends eingeteilt war, ist abgemeldet; Buchung per
  „Woche abschließen“, **zwei Zuschläge je Spieler**, Schnitt = Mittel der Gruppen-Schnitte je Abend-Nummer. „Keine Meldung“ ist ein Ziel der Einteilung.
- (seit 22.10.2026) Die Einteilung gilt **einmal je Raid-ID** (eine Woche ab einstellbarem Wechseltag, Standard Mittwoch); Raidleitung baut die Gruppen so, dass an beiden Tagen dieselben Spieler stehen, Teilzeit-Spieler kommen auf die Bank. Die Raidtage je Gruppe stehen nicht mehr in der Oberfläche.
- Abwesenheit und Einteilung sieht nur, wer Schreibrecht hat (Gildenrang); alle anderen nur Spieler und Verlauf. Raidkader automatisch beim Anmelden, Rang geteilt.
- **Stufe 1 und 2 sind die Wurzel des Vertrauens** (dürfen immer senden/einteilen/buchen); die Rangstufe ändern nur sie; andere sehen geteilte Einstellungen nur lesend.
- Verworfen: automatische Umteilung/Warnung, wenn jemand in einer anderen Gruppe raidet als eingeteilt (Raidleitung organisiert vorher).
- Fenster-Mindestbreite 880.

**Offene Punkte / Ideen (alle vom Nutzer so gewollt, nichts davon beauftragt):**
- **Kleineres Fenster ermöglichen** (später, erst wenn alles andere durch ist): Werkzeugleiste umbrechen/Überlaufmenü, kürzere Knöpfe, Spalten einklappen.
- „Anmeldung vergessen“ heißt in manchen Texten noch so, der Knopf/das Ziel heißt „Keine Meldung“ (Vereinheitlichung der Texte offen).
- Eine Übersicht „wer war an den letzten Abenden da“ (Spielerdetail oder Tabelle für alle) gibt es nicht; die Daten liegen je Abend in `abschluss.spieler`.
- Das für die Gildenleitung geteilte Regelwerk (Claude-Doc) ist **nicht** automatisch aktuell: Inhalt = `REGELWERK-ENTWURF.md` (Stand 18.10.2026) dort einfügen.
- Eine Fassung 0.2.1 für alle ist nicht gebaut (Zip nur auf Wunsch; Protokoll/Datenbuch sind seit dem 17./18.10. geändert, **alle brauchen dieselbe Fassung**, neue Dateien gibt es nicht).
- **Umgesetzt 22.10.2026 (Leitungs-Abgleich, nicht committet, im Spiel ungetestet; Beschreibung in `AGENTS.md`, Szenario 59): gildenweiter Abgleich von Historie und Wertungen nur für Spieler mit Schreibrecht, per Flüstern.** Ursprüngliche Überlegung: Anlass: Wer den Wochenabschluss bucht, aber an einem der Gruppenabende nicht im Raid war, hat dessen Daten womöglich nicht (Historie/Datenbuch laufen nur über den Gruppenkanal; Einstellungen `K` und Einteilung `T` laufen schon gildenweit). Kleine Variante: nur Schreibrecht-Spieler, Anfrage beim Anmelden und per Knopf (Stand = Anzahl + Prüfsumme wie im Hallo), Antwort per Addon-Flüstern nur mit den fehlenden Einträgen, Annahme nur von Absendern mit Schreibrecht (wie CLM: Unberechtigte still verwerfen); Spieler ohne Schreibrecht bleiben beim Gruppenweg. **Nicht** als Dauerfunk im Gildenkanal (Drosselung, alle lesen mit, Hallo-Hinweise würden ständig auslösen). Protokollversion hochsetzen, alle brauchen dieselbe Fassung. Erst bauen, wenn die Lücke im Wochenabschluss real auftritt.
- Push steht aus (Nutzer entscheidet).

**Stolperfallen, die uns Zeit gekostet haben:**
- Die Zeilen der Übersicht (`Fenster.lua`) werden von allen Ansichten benutzt: Wer eine Ansicht erweitert, muss die Knöpfe der anderen dort ausdrücklich verstecken.
- Der Prüfstand (`Anwesenheit._SetDB`/Tests) nutzt die Liste des letzten Bosses statt der echten Gruppe; die Simulation hat eine eigene Uhr (`time()`), daher überall `date(…, time())`.
- Ein schlafendes Addon (kein Plündermeister, „Nein“) hört nur `K`, `A`, `T`, `U` (Weiche in `Abgleich.lua`); alles andere ist gesperrt.
- Die Fenster-Mindestbreite stützt sich auf die Knöpfe in der Werkzeugleiste; neue Knöpfe dort zuerst auf Überlappung prüfen.
