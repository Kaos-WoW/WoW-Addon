# Loot-Ordnung

Entwurf eines neuen Lootsystems für die Gilde **Resurrected**, gedacht für
**World of Warcraft Forever** (Classic+).

Statt eines Loot Councils entscheidet eine Regel:

    Prio = Einsatz ÷ Rüstwert

**Einsatz** sammelt man durch Mitraiden, **Rüstwert** durch erhaltene
Gegenstände, und beides verliert jede Woche 10 %. Wer gerade etwas bekommen hat,
rückt nach hinten; wer lange leer ausging, nach vorn. Es wird nicht geboten und
nichts gespart.

Der Rüstwert eines Gegenstands ergibt sich aus **Gegenstandsstufe und
Ausrüstungsplatz** — beides liefert das Spiel selbst. Das System braucht keine
BIS-Listen und keine gepflegte Wertetabelle und funktioniert deshalb ab dem
ersten Raidtag einer Erweiterung, über die noch niemand etwas weiß.

## Dateien

| Datei | Inhalt |
|---|---|
| `loot-ordnung.html` | Das Regelwerk. Zehn Paragrafen, zwei Anhänge, offene Punkte |
| `berechnungen.py` | Das Rechenmodell. Erzeugt alle Zahlen im Regelwerk |
| `AGENTS.md` | Projektstand, Entscheidungen mit Begründung, verworfene Alternativen |
| `deploy-tbc.ps1` | Rollt das Addon in den Anniversary-Client aus |
| `luacheck.py` | Grobe Strukturprüfung für Lua (Blöcke, Klammern, BOM) |

### Das Addon — `LootOrdnung/`

| Datei | Inhalt | braucht WoW |
|---|---|---|
| `Kern.lua` | Verfall, Prio, Platzfaktoren, Einsatz, Rangfolge | nein |
| `Notiz.lua` | Kontenformat `LO:…` lesen und schreiben | nein |
| `Tests.lua` | 72 Selbsttests, auch offline lauffähig | nein |
| `Gilde.lua` | Offiziersnotizen lesen und gedrosselt schreiben | ja |
| `Raid.lua` | Den Raidabend erfassen | ja |
| `Befehle.lua` | Slash-Befehle unter `/lo` | ja |

**Kern, Notiz und Tests fassen keine WoW-API an** — deshalb laufen sie auch in
einem gewöhnlichen Lua-Interpreter, und der Prüfstand braucht keinen Client.

Das Regelwerk ist als Seite veröffentlicht:
https://claude.ai/code/artifact/82f64d38-0b63-4c4f-9fd7-1208bdb8bb97

## Ausrollen und prüfen

```
powershell -ExecutionPolicy Bypass -File .\deploy-tbc.ps1
```

Danach im Spiel `/reload`, dann `/lo test` — erwartet werden 72 grüne Prüfungen.
`/lo` allein listet alle Befehle.

## Modell nachrechnen

```
python berechnungen.py
```

Gibt vier Auswertungen aus: warum Abmelde-Punkte einen Deckel brauchen, warum
Fehlzeit an sich keine Prio kostet, was ein Platzfaktor praktisch kostet, und
wie sich zwei Spieler über acht Wochen von selbst abwechseln.

Die Stellschrauben stehen oben in der Datei. Wer eine ändert, muss die Werte im
Regelwerk nachziehen — einschließlich der Kurven im Diagramm.

## Stand

**Entwurf, noch nicht beschlossen — inhaltlich aber vollständig.** Alle zehn
Paragrafen sind durchgearbeitet und abgenommen:

| | |
|---|---|
| § 1 | Die Regel |
| § 2 | Einsatz — Punkte, Abmeldung in drei Stufen, Bank, „vielleicht“ |
| § 3 | Rüstwert — Platzfaktoren und was sie praktisch kosten |
| § 4 | Der Verfall — 10 % je Woche auf beide Größen |
| § 5 | Neue Mitglieder — Probezeit, dann vorne einsteigen |
| § 6 | Hauptrolle — Rolle *und* Spezialisierung, Zweitbedarf |
| § 7 | Was der Rat noch tut — und wann überschrieben werden darf |
| § 8 | Sonderfälle — legendäre Gegenstände stehen außerhalb |
| § 9 | Pflichten vor dem Raid |
| § 10 | Offenlegung |
| Anhang A | Woher die Zahlen kommen — die drei Größen in Alltagssprache |
| Anhang B | Ein Durchgang zum Mitrechnen |

**Sieben offene Punkte** sind im Regelwerk selbst markiert, darunter zwei, die
sich erst am laufenden Client entscheiden lassen (Eichwert K und
Mindest-Rüstwert). Dazu zwei zurückgestellte Fragen in `AGENTS.md`: wie das
Addon die getragene Ausrüstung erkennt, und wie Raids mit fremden Spielern
laufen sollen.

## Stand des Addons

**Version 0.1.0, im Anniversary-Client erprobt.** Was läuft:

- Rechenkern mit 72 Selbsttests, deckungsgleich mit `berechnungen.py`
- Konten in den Offiziersnotizen: lesen, schreiben, sichern, wiederherstellen
- Rangauswahl, damit Twinks und Anwärter draußen bleiben
- Raidabend erfassen — `ENCOUNTER_END` funktioniert, Bosse werden automatisch
  gebucht, sobald Raidinstanz **und** Gildenmehrheit stimmen

Was noch fehlt: die Vergabe. Würfe im Chat mitlesen, nach Kategorie und Prio
sortieren, Rüstwert buchen. Das hängt an der Frage, ob es in Forever Master Loot
gibt — ohne ihn läuft die Vergabe über Gruppenloot und Handeln.
