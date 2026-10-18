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

Nichts. Alles bis zum 18.10.2026 ist committet. **Gepusht ist nur bis `7546594`**; die drei Commits danach (`0155fc7`, `e3de7ec`, Dokumentation) liegen nur lokal.

## Übergabe (Stand 18.10.2026 abends)

**Commits seit dem Regelwerk auf `main` (`7546594` ist gepusht, die folgenden nicht):**

| Commit | Inhalt |
|---|---|
| `7546594` | Loot-Regelwerk Resurrected (Wertung, Zuschläge, Anhebung, Datenbuch, Würfel-Fixes) |
| `0155fc7` | Mehrere Gruppen (Raidkader, Einteilung, Bench), Abgemeldet/Offen, geteilte Einstellungen mit Vertrauenswurzel |
| `e3de7ec` | Raidtage je Gruppe, „Keine Meldung“, Wochenabschluss, schlanke Abwesenheit, Farben, Gruppen blenden andere aus |
| (nächster) | Dokumentation (WORKBOARD, AGENTS, REGELWERK-ENTWURF) |

**Tests (immer vor dem Commit laufen lassen):**
`python luacheck.py Fairshare/*.lua` · `python tests/rechenkern.py` (447) · `python tests/szenarien.py` (56 Szenarien) ·
`python tests/texte.py --streng` (740 Schlüssel) · danach `.\deploy.ps1` (rollt in `_classic_beta_` aus; Änderungen: `/reload`, neue Dateien: WoW-Neustart).
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
- Eine Gruppe hat **eigene Raidtage = eigene Raid-ID**; Raidleitung baut die Gruppen so, dass an beiden Tagen dieselben Spieler stehen, Teilzeit-Spieler kommen auf die Bank.
- **Stufe 1 und 2 sind die Wurzel des Vertrauens** (dürfen immer senden/einteilen/buchen); die Rangstufe ändern nur sie; andere sehen geteilte Einstellungen nur lesend.
- Verworfen: automatische Umteilung/Warnung, wenn jemand in einer anderen Gruppe raidet als eingeteilt (Raidleitung organisiert vorher).
- Fenster-Mindestbreite 880.

**Offene Punkte / Ideen (alle vom Nutzer so gewollt, nichts davon beauftragt):**
- **Kleineres Fenster ermöglichen** (später, erst wenn alles andere durch ist): Werkzeugleiste umbrechen/Überlaufmenü, kürzere Knöpfe, Spalten einklappen.
- „Anmeldung vergessen“ heißt in manchen Texten noch so, der Knopf/das Ziel heißt „Keine Meldung“ (Vereinheitlichung der Texte offen).
- Eine Übersicht „wer war an den letzten Abenden da“ (Spielerdetail oder Tabelle für alle) gibt es nicht; die Daten liegen je Abend in `abschluss.spieler`.
- Das für die Gildenleitung geteilte Regelwerk (Claude-Doc) ist **nicht** automatisch aktuell: Inhalt = `REGELWERK-ENTWURF.md` (Stand 18.10.2026) dort einfügen.
- Eine Fassung 0.2.1 für alle ist nicht gebaut (Zip nur auf Wunsch; Protokoll/Datenbuch sind seit dem 17./18.10. geändert, **alle brauchen dieselbe Fassung**, neue Dateien gibt es nicht).
- Push steht aus (Nutzer entscheidet).

**Stolperfallen, die uns Zeit gekostet haben:**
- Die Zeilen der Übersicht (`Fenster.lua`) werden von allen Ansichten benutzt: Wer eine Ansicht erweitert, muss die Knöpfe der anderen dort ausdrücklich verstecken.
- Der Prüfstand (`Anwesenheit._SetDB`/Tests) nutzt die Liste des letzten Bosses statt der echten Gruppe; die Simulation hat eine eigene Uhr (`time()`), daher überall `date(…, time())`.
- Ein schlafendes Addon (kein Plündermeister, „Nein“) hört nur `K`, `A`, `T`, `U` (Weiche in `Abgleich.lua`); alles andere ist gesperrt.
- Die Fenster-Mindestbreite stützt sich auf die Knöpfe in der Werkzeugleiste; neue Knöpfe dort zuerst auf Überlappung prüfen.
