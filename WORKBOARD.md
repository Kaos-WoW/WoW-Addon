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

> 16.10.2026: **Release 0.2.0 (Regelwerk Resurrected)** im Spiel bestätigt und verifiziert:
> - Vollständige Integration des neuen Regelwerks von Resurrected (Thunderstrike EU):
>   - § 1: Golf-Prinzip (niedrigste Wertung hat Vorrang vor Wurf; Wertung = Main-Items + Zuschläge + Anhebungen)
>   - § 2: Anwesenheitserfassung (≥ 50 % Bosse = im Raid), gleitendes 6-Abende-Fenster, Fehlfaktoren (0.7, 1.0, 1.0, 1.0, 1.3, 1.5; unentschuldigt sofort 1.5, mindestens 2 Wertungspunkte (seit 17.10.2026); Bank Faktor 0), Abendschnitt (Main-Items / Raidteilnehmer), automatische Zuschlagsberechnung
>   - § 3: Dynamische Anhebung (Liegt Hauptbedarf-Würfler > 1 unter Niedrigstem der anderen, Anhebung auf Niedrigster - 1; dauerhafte Speicherung bei Itemgewinn)
>   - § 4: Neulinge / Proberaid (Raid 1 ohne Main-Bedarf/Zuschläge; ab Raid 2 normales Mitglied) & Gäste (Wertung des niedrigsten Kaderspielers)
>   - § 5: Zweitbedarf / Offspec (Haupt vor OS; bei OS weniger Stücke vor Wurf)
>   - § 6: Rollen & Berechtigungen (Gildenleitung für Bank + Unentschuldigt, Raidleiter für Bank, Raider reine Ansicht)
> - Neuer UI-Reiter **Abwesenheit** mit Live-Toggles und Berechtigungsprüfung
> - Raidabend-Abschluss (`[Abend abschließen]` mit 8s-Bestätigung & `/fs abschluss`), automatische Festschreibung der Zuschläge, Reset des Abwesenheit-Reiters für den Folgeraid, Wiedereröffnen-Funktion (`[Abend wiedereröffnen]`)
> - Chronologische Spielerdetail-Ansicht (Datum, Art, Punkte +1,0 / +0,7 / +1,5 / 0,0, Formel & Status)
> - Vollständige Test-Isolation (`Anwesenheit._SetDB`), 365/365 Unit-Tests bestanden.

## Belegt

| Agent | Bereich | Dateien | Seit | Stand |
|---|---|---|---|---|
| Claude | Regelwerk-Angleichung 16.10.2026 abends: Neuling 2. Abend = Niedrigster, Gast-Wertung im Wurf, Rückgabe (Punkt erst bei Neuvergabe), Kennzeichnung „abweichend“/„OS nach Absprache“, Stammgast nahtlos, Standard-Rangstufe | `Fairshare/Kern.lua`, `Fairshare/Anwesenheit.lua`, `Fairshare/Wurf.lua`, `Fairshare/Erfassung.lua`, `Fairshare/Konfig.lua`, `Fairshare/Locale.lua`, `Fairshare/Tests.lua`, `tests/*.py`, `AGENTS.md`, `REGELWERK-ENTWURF.md` | 16.10.2026 | Code fertig, alle Tests grün (442 Kern, 47 Szenarien, 675 Texte); wartet auf Test im Spiel. Seit 17.10.2026: unentschuldigt 1,5 (mindestens 2), Anhebung = Niedrigster im Kader + 2 (einmal je Abend), „Anmeldung vergessen“; 17.10. Abwesenheits-Reiter: Online-Anzeige korrigiert, Schalter „Raid mitzeigen“; 17.10. abends: „Im Raid“ = am Abendende in der Gruppe statt Boss-Quote; offener Abend folgt der aktiven Gruppe (Schnitt war 0, weil Abend- und Vergabegruppe verschieden waren); Abgemeldet ausdrücklich, „Offen“ sperrt den Abschluss (447 Kern); Passen wird gemeldet, Wurf endet früh, wenn alle gewählt haben. Zusätzlich verändert: `Fenster.lua`, `Befehle.lua`, `Abgleich.lua`, `Quelle.lua`, `tests/szenarien.py` |

## Erledigt, nicht committet

| Agent | Was | Dateien |
|---|---|---|
| Antigravity | Regelwerk Resurrected v0.2.0: Anwesenheit, Bank/Abwesenheit, dynamische Anhebung, Raidabschluss, Spielerdetails, Testisolation | `Fairshare/Anwesenheit.lua`, `Fairshare/Befehle.lua`, `Fairshare/Fairshare.toc`, `Fairshare/Fenster.lua`, `Fairshare/Gruppen.lua`, `Fairshare/Kern.lua`, `Fairshare/Locale.lua`, `Fairshare/Quelle.lua`, `Fairshare/Tests.lua`, `Fairshare/Wurf.lua`, `REGELWERK-ENTWURF.md`, `tests/rechenkern.py`, `tests/sim.py`, `tests/texte.py` |
