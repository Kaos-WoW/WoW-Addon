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
| `loot-ordnung.html` | Das Regelwerk. Zehn Paragrafen, Rechenbeispiel, offene Punkte |
| `berechnungen.py` | Das Rechenmodell. Erzeugt alle Zahlen im Regelwerk |
| `AGENTS.md` | Projektstand, getroffene Entscheidungen mit Begründung, Addon-Ausblick |

Das Regelwerk ist als Seite veröffentlicht:
https://claude.ai/code/artifact/82f64d38-0b63-4c4f-9fd7-1208bdb8bb97

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

**Sieben offene Punkte** sind im Regelwerk selbst markiert, darunter zwei, die
sich erst am laufenden Client entscheiden lassen (Eichwert K und
Mindest-Rüstwert). Dazu zwei zurückgestellte Fragen in `AGENTS.md`: wie das
Addon die getragene Ausrüstung erkennt, und wie Raids mit fremden Spielern
laufen sollen.

Ein Addon ist geplant, aber nicht begonnen. Die Ordnung ist so geschrieben, dass
sie auch von Hand anwendbar ist — wenn auch mühsam.
