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

*Nichts belegt.* Claude hat am 22.10.2026 abgegeben (alles committet und gepusht). Wer als Nächstes arbeitet,
trägt sich hier ein.

| Agent | Bereich | Dateien | Seit | Stand |
|---|---|---|---|---|

## Erledigt (alles committet und gepusht, `origin/main` = `81eb59c`)

Claude, 22.10.2026: **Bedienung der Gruppen vereinfacht** („viel zu kompliziert“, vom Nutzer im Spiel als „viel einfacher und sauberer“ bestätigt). Wertung und Zuteilung sind unverändert. Alle Einzelheiten stehen in `AGENTS.md` (Abschnitt „Mehrere Gruppen“, „Einstellungen teilen“, „Abgleich“, „Leitungs-Abgleich“); hier nur die Landkarte:
- **Raid-ID:** Einteilung einmal je Raid-ID (`Gruppen.IdStart/IdWechsel/IdListe`, Wechseltag geteilt, Standard Mittwoch, Konfigzeile `I|`). `Anwesenheit.WochenTage` = die sieben Tage der Raid-ID.
- **Raidkader:** liest sich beim Anmelden von selbst ein (`Gruppen.RaidkaderAuto`), Rang geteilt (`N|`). Raidtage je Gruppe und der Gruppen-Mitgliederabgleich sind nur noch Altcode, nicht mehr in der Oberfläche.
- **Fenster (`Fenster.lua`, `Stil.lua`):** Reiter „Abwesenheit“/„Einteilung“ nur mit Schreibrecht; Gruppenwahl per Ausklappliste (`Stil.Dropdown`, Pfeil selbst gezeichnet, weil die Glyph ▾ in Inter fehlt); Einteilung mit zwei Listen (links nur nirgends Zugewiesene, rechts im Ziel); Prüfstand-Haken `Fenster.GruppeWaehlen/EinteilungKlick/EinteilungReihenfolge/ReiterSichtbar/AktuelleAnsicht`.
- **Einstellungen → Gruppen:** Gruppen, Raidkader (kumulative Rang-Schalter + Synchronisieren), Raid-ID (Wechsel-Wochentag).
- **Auto-Senden:** geteilte Einstellungen gehen nach einer Änderung (mit Schreibrecht) nach 4 s von selbst an alle (`Konfig.AutoSenden`, Szenario 58).
- **Abgleich:** Chat-Meldungen für die Empfänger beim Start eines Gruppen-Abgleichs (`Abgleich.AbschlussMelden` meldet das Ende). **Leitungs-Abgleich** (Szenario 59): Spieler mit Schreibrecht gleichen Historie und Datenbuch gildenweit per Flüstern ab (`V`-Meldung in der Gilde, dann `Q/Y/N/M/D/E` als `WHISPER:<Name>`), auch ohne Gruppe und ohne Plündermeister; Schalter `leitungSync`.
- **Fix:** Zugewiesene einer gelöschten Gruppe zählen in der Einteilung als frei.
- **Zip:** `..\Fairshare-releases\Fairshare-0.2.0.zip` (`python release/bauen.py`, aus dem letzten Commit; `release/LIESMICH.txt` ist die Anleitung für die Gildenleitung). **Alle brauchen dieselbe Fassung** (Protokoll geändert).

## Übergabe (Stand 22.10.2026 abends)

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

**Tests (immer vor dem Commit laufen lassen):**
`python luacheck.py` · `python tests/rechenkern.py` (447) · `python tests/szenarien.py` (59 Szenarien; **ohne `-I`**, sonst findet Python `lupa` nicht) ·
`python tests/texte.py --streng` (728 Schlüssel; ungenutzte Schlüssel aus `Locale.lua` entfernen) · danach `.\deploy.ps1` (rollt in `_classic_beta_` aus; Änderungen: `/reload`, neue Dateien: WoW-Neustart).
Patches bisher als Python-Skripte im Scratchpad (CRLF erhalten, `python -X utf8`); Lua-Text nie per Heredoc, sondern per Write-Werkzeug. Die Simulation (`tests/sim.py`) hat eine eigene Uhr, rechnet `time({Tabelle})` wie im Spiel und kennt Flüstern (`WHISPER`, nur der Empfänger bekommt es).

**Im Spiel vom Nutzer bestätigt:** Regelwerk (Wertung, Zuschläge, Anhebung, Neuling, Gast, Rückgabe), Würfelfenster inkl. Passen und frühem Ende, „Fairshare nutzen?“ nur für den Plündermeister, geteilte Einstellungen mit Sperre/Selbstheilung, Raidkader per Rangsync, Einteilung, Bench, „Keine Meldung“, Abschluss je Gruppe, Gruppenwechsel = anderer Abend, schlanke Abwesenheit, Wochenabschluss (Buchung); **neu 22.10.:** die vereinfachte Bedienung (Ausklappliste mit gezeichnetem Pfeil, zwei Listen, Reiter nur mit Schreibrecht – ein Spieler ohne Recht sah nur „Spieler“/„Verlauf“), Gruppen kommen per „An alle senden“ bei den anderen an.

**NOCH NICHT im Spiel gesehen (zuerst prüfen lassen):**
1. **Leitungs-Abgleich** (Nutzer testet am 23.10.2026): zwei Spieler mit Schreibrecht, nicht in einer Gruppe, auf unterschiedlichem Stand; nach 1–2 Minuten muss der andere „Mit der Leitung abgeglichen: …“ im Chat sehen. Falls nichts passiert: `/fs abgleich status` (Zeile „Leitungs-Abgleich: aktiv“), `Konfig.Darf` (Gildenliste geladen? Rang im Bereich?), ob Flüstern in Forever Addon-Nachrichten durchlässt (ungemessen).
2. **Auto-Senden** der Einstellungen nach einer Änderung (Chat: „Geänderte Einstellungen wurden an alle gesendet.“).
3. **Raidkader liest sich beim Anmelden von selbst ein** (25 s; nur wenn ein Rang gewählt ist und die Gildenliste da ist).
4. Chat-Meldung beim Start eines Gruppen-Abgleichs bei den Empfängern.
5. Farben je Gruppe in der Einteilung, „Neuen Abend beginnen“ in einer abgeschlossenen Abwesenheit.
6. Das leere erste Öffnen nach dem Anmelden (Schrift vorladen, `Stil.SchriftVorladen`/`AuffrischenBisFertig`). Bleibt es leer: `/fs darstellung` ausgeben lassen.

**Entscheide des Nutzers, die nicht offensichtlich sind (nicht neu aufrollen):**
- Im Raid = wer am **Abendende** in der Gruppe steht (nicht Boss-Quote); wer früher geht und kein Main-Item hatte, gilt als abwesend.
- Abgemeldete werden **nirgends eingeteilt**: Wer im Raidkader steht und in der **Raid-ID (Woche ab dem Wechseltag, Standard Mittwoch)** nirgends eingeteilt war, ist abgemeldet; Buchung per
  „Woche abschließen“, **zwei Zuschläge je Spieler**, Schnitt = Mittel der Gruppen-Schnitte je Abend-Nummer. „Keine Meldung“ ist ein Ziel der Einteilung.
- (seit 22.10.2026) Die Einteilung gilt **einmal je Raid-ID** (eine Woche ab einstellbarem Wechseltag, Standard Mittwoch); Raidleitung baut die Gruppen so, dass an beiden Tagen dieselben Spieler stehen, Teilzeit-Spieler kommen auf die Bank. Die Raidtage je Gruppe stehen nicht mehr in der Oberfläche.
- Abwesenheit und Einteilung sieht nur, wer Schreibrecht hat (Gildenrang); alle anderen nur Spieler und Verlauf. Raidkader automatisch beim Anmelden, Rang geteilt.
- **Stufe 1 und 2 sind die Wurzel des Vertrauens** (dürfen immer senden/einteilen/buchen); die Rangstufe ändern nur sie; andere sehen geteilte Einstellungen nur lesend.
- Verworfen: automatische Umteilung/Warnung, wenn jemand in einer anderen Gruppe raidet als eingeteilt (Raidleitung organisiert vorher).
- Fenster-Mindestbreite 880.

## ⭐ Nächste Aufgabe (Auftrag des Nutzers, 19.10.2026): Übungsmodus „Probe-Abend“ zum einfachen Testen

**Warum:** Die Testläufe im Spiel sind zu kompliziert (zwei echte Spieler, Gruppe verlassen, Einteilung, Würfe, Handel, Abschluss; Fehler wie „Xalessa war noch im Raid, darum kein Zuschlag“ entstehen durch die Testbedingungen, nicht durch das Addon). Der Nutzer will **einen vollen Raidabend testen können, ohne echte Daten zu erzeugen und ohne zweiten Spieler.** Die Auftraggeber-Wünsche: „super einfach“, „keine echten Daten“.

**Was es schon gibt (nutzen, nicht neu bauen):**
- Der **Beispiel-Modus** (`zustand.beispiel` in `Fenster.lua`, Knopf „Beispiel“ im Fuß; `Quelle.Beispiel/BeispielWurf`, `Anwesenheit.BeispielKandidaten*`): zeigt feste Demodaten, ändert nichts, **simuliert aber keinen Abend** (Abschließen nur als Chat-Text).
- **`Anwesenheit._SetDB(mockDB)`**: leitet die Datenbuch-Zugriffe (`abende`, `zuschlaege`, `anhebungen`, `anhebungsliste`) auf eine Wegwerf-Tabelle um; die Tests in `Tests.lua` (`/fs test`) benutzen es und mocken zusätzlich `Konfig.Darf`, `Rolle.Berechtigt`, `Erfassung.Historie`, `Gruppen.Pflicht/EinteilungVorhanden` (siehe `testAbendAbschlussUndSpielerdetail`).
- `tests/szenarien.py` und `tests/sim.py` spielen ganze Abende offline mit mehreren virtuellen Clients durch (Szenarien 36, 42-47, 53-55 u. a.). Das ist die Vorlage für die Abläufe, die der Probe-Abend im Spiel nachbilden soll.

**Vorschlag (Erster Entwurf, bitte prüfen und verbessern):** Ein **Übungsmodus** (`/fs probe` oder Knopf im Fuß neben „Beispiel“), der
1. **alle Datenzugriffe auf eine reine Speicher-Tabelle umlenkt** (Historie, Datenbuch, Zuschläge, aktiver Abend; nichts davon wird in `FairshareDB` geschrieben, nach dem Schließen ist alles weg) und **jedes Senden sperrt** (`Abgleich.Senden/einreihen`, `Konfig.Senden/AutoSenden`, `BuchVerteilen`, `Verteilen`, `Leitung`-Beacon), damit nichts bei anderen ankommt;
2. mit **erfundenen Spielern** arbeitet (z. B. „Anna, Ben, Chris, Dora“, alle im Kader, mit Anfangswerten), die man per Knopf **„in den Raid / aus dem Raid“** setzt (ersetzt `Rolle.Einheiten`/`anwesendeNamen` im Übungsmodus);
3. eine **kleine Bedienleiste** zeigt: *„Item an <Spieler> vergeben“* (Haupt/OS), *„Spieler geht“*, *„Bench“*, *„Unentschuldigt“*, *„Abend abschließen“*, *„Neuer Abend“*, *„Zurücksetzen“*; die normalen Reiter (Spieler, Verlauf, Abwesenheit, Spielerdetail) zeigen dabei das Ergebnis mit der **echten Rechnung** (`Kern.*`, `Anwesenheit.AbendVorschau/-Abschliessen`), damit Zuschläge, Schnitt, Wertung und Spielerdetail genau so aussehen wie im Betrieb;
4. oben einen **auffälligen Hinweis „PROBE – keine echten Daten“** (Warnfarbe wie beim Beispiel-Modus) und beim Schließen nichts hinterlässt.
5. **Optional, sehr nützlich:** eine Schaltfläche **„Fertiger Probe-Abend“**, die ein Skript abspielt (Abend A: Kaos 4 Items, Anna 2; Abend B …) und die erwarteten Zahlen daneben schreibt („Soll: Zuschlag 2,0“), damit man nur noch vergleicht.

**Alternative, kleiner:** Nur `/fs probe abend` als **Textausgabe** (wie `/fs test`): läuft in einer Wegwerf-Datenbank einen Standardabend durch (Raid, Bench, Unentschuldigt, Abgemeldet, Neuling) und schreibt Zeile für Zeile „Erwartet / Ist“ in den Chat. Weniger Bedienung, schneller gebaut, deckt die Rechenregeln ab, aber nicht die Oberfläche.

**Abnahme (der Nutzer entscheidet im Spiel):** In unter 2 Minuten, allein, ohne zweiten Spieler und ohne Gruppe: Spieler in den Raid setzen, Items vergeben, einen Spieler gehen lassen, unentschuldigt markieren, Abend abschließen, Zuschlag im Spielerdetail sehen. Danach `/fs` im Normalbetrieb zeigt unverändert die echten Daten.

**Beachten:** ⚠️ Nichts aus dem Probe-Modus darf in `FairshareDB` oder über das Netz gehen (Test: Szenario mit zwei Clients, einer im Probe-Modus, der andere darf nichts empfangen, und `FairshareDB` bleibt gleich). Die Zeilen der Übersicht (`Fenster.lua`) werden von allen Ansichten benutzt: Knöpfe der Bedienleiste außerhalb des Probe-Modus verstecken. Neue Texte durch `L[]` (und `tests/texte.py --streng`). Jede Änderung wie üblich mit `luacheck.py`, `rechenkern.py`, `szenarien.py`, `deploy.ps1`.

**Offene Punkte / Ideen (alle vom Nutzer so gewollt, nichts davon beauftragt):**
- **Kleineres Fenster ermöglichen** (später, erst wenn alles andere durch ist): Werkzeugleiste umbrechen/Überlaufmenü, kürzere Knöpfe, Spalten einklappen.
- „Anmeldung vergessen“ heißt in manchen Texten noch so, der Knopf/das Ziel heißt „Keine Meldung“ (Vereinheitlichung der Texte offen).
- Eine Übersicht „wer war an den letzten Abenden da“ (Spielerdetail oder Tabelle für alle) gibt es nicht; die Daten liegen je Abend in `abschluss.spieler`.
- Das für die Gildenleitung geteilte Regelwerk (Claude-Doc) ist **nicht** automatisch aktuell: Inhalt = `REGELWERK-ENTWURF.md` (Stand 22.10.2026) dort einfügen.
- Wer **Bench-Spieler einspringen** lassen will: in der Einteilung beim Ziel „Bench“ entfernen, dann der Gruppe zuweisen (links stehen nur nirgends Zugewiesene); in der Abwesenheit springt ein Bench-Spieler mit einem Klick auf „✓ Bench“ in die aktive Gruppe ein. Entscheid des Nutzers 22.10.2026: Wer irgendwo zugewiesen ist, erscheint in den anderen Rubriken nicht mehr.
- Die Einteilung hat kein Nachholen für Spieler, die sie verpasst haben (Einstellungen haben es); sie bekommen sie, wenn jemand mit Schreibrecht „Einteilung senden“ drückt.
- Der Leitungs-Abgleich begrenzt eine Runde auf 600 Einträge je Spieler (`MAXEINTRAEGE`); große Rückstände brauchen mehrere Runden (nächste `V`-Meldung, spätestens nach 15 Minuten).
- **OS-Standard seit 22.10.2026 1-99** (vorher 1-50, jetzt wie Garguls Voreinstellung): `Kern.BEREICHE`, `Erfassung.lua`, `Einstellungen.lua` (Knopf „Standardbereiche“). Bereits **gespeicherte** Bereiche (1-50) bleiben, bis die Gildenleitung „Standardbereiche“ klickt und die Einstellungen teilt (geht jetzt von selbst); alle Würfelfenster und Tests richten sich nach dem Bereich des Leiters.
- **Gildenweiter Reset (22.10.2026, nicht committet, im Spiel ungetestet; Beschreibung und Szenario 60 in `AGENTS.md`):** `/fs reset gilde` / Einstellungen → Erfassung → „Für alle zurücksetzen“, nur Stufe 1 und 2. Reset-Marke `Z|` in den geteilten Einstellungen; Alt-Daten werden danach nicht mehr angenommen. **Im Spiel prüfen:** Reset als Gildenmeister, ein Offizier/Mitglied online sieht die Chatmeldung und eine leere Liste; ein Spieler, der beim Reset offline war, bekommt ihn beim Anmelden; `/fs reset undo` danach verweigert. Alle brauchen dieselbe Fassung.
- **Anhebung (19.10.2026, nicht committet, im Spiel ungetestet):** Auf Entscheid des Nutzers ist die **automatische Anhebung abgeschafft** (`Kern.AUTO_ANHEBUNG = false`), es gibt eine **manuelle** (`Anwesenheit.AnhebungSetzen`, Einstellungen → Gruppen → Anhebung mit Namensfeld, `/fs anhebung <Name>`; nur Raid-/Gildenleitung). Der Neuling-Einstieg am 2. Abend bleibt. Beschreibung in `AGENTS.md`/`REGELWERK-ENTWURF.md` § 3. Das Google Doc „Fairshare Kurzanleitung“ und `ANLEITUNG.md` nennen die Anhebung noch automatisch und müssen angepasst werden.
- Push von `origin/main` vorher mit `git fetch` prüfen (neben dem Nutzer schreibt `xqp`).

**Stolperfallen, die uns Zeit gekostet haben:**
- Die Zeilen der Übersicht (`Fenster.lua`) werden von allen Ansichten benutzt: Wer eine Ansicht erweitert, muss die Knöpfe der anderen dort ausdrücklich verstecken.
- Der Prüfstand (`Anwesenheit._SetDB`/Tests) nutzt die Liste des letzten Bosses statt der echten Gruppe; die Simulation hat eine eigene Uhr (`time()`), daher überall `date(…, time())`.
- Ein schlafendes Addon (kein Plündermeister, „Nein“) hört nur `K`, `A`, `T`, `U` (Weiche in `Abgleich.lua`); alles andere ist gesperrt.
- Die Fenster-Mindestbreite stützt sich auf die Knöpfe in der Werkzeugleiste; neue Knöpfe dort zuerst auf Überlappung prüfen.
