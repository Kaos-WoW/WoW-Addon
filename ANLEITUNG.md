# KaosLoot – Kurzanleitung

KaosLoot hält fest, **wer welches Item bekommen hat**, und sortiert daraus die **faire Reihenfolge** fürs Würfeln. Alle in der Gruppe sehen denselben Stand.

## Fenster öffnen

Im Chat **`/kl`** eingeben. Alle Befehle: `/kl hilfe`.

## Was du im Fenster siehst

- **Spieler**: Liste aller Spieler mit ihrer **Wertung** (je niedriger, desto früher bist du dran), den Zweitbedarf-Items und wann sie zuletzt etwas bekommen haben. Ein Klick auf einen Namen zeigt jede einzelne Vergabe und die Zuschläge.
- **Verlauf**: wer was wann bekommen hat, neueste zuerst.
- **Gruppe: …** (oben): filtert die angezeigten Spieler nach Gruppe (z. B. 10er oder 40er). Die Wertung jedes Spielers ist dabei immer global und raidübergreifend.
- **Anwesenheit** und **Einteilung**: nur für die Gildenleitung (Schreibrecht), sie stellt hier die Gruppen ein, lädt mit 1 Klick ein und schließt Raidabende sowie die Woche ab.

## Würfeln

Startet der Plündermeister einen Wurf, geht ein kleines Fenster auf: **Haupt (1-100)**, **OS (1-99)** oder **Passen**. Ein Klick genügt, **der erste Wurf zählt**. Wer die niedrigste Wertung hat, bekommt das Item, bei Gleichstand der höhere Wurf. Haupt geht vor OS.

## So wird die Wertung gerechnet

**Wertung = erhaltene Main-Items + Zuschläge für verpasste Abende.** Wer die niedrigste hat, hat Vorrang.

| Situation | Zuschlag |
|---|---|
| Anwesend (eingeteilt, nicht anders markiert) | keiner |
| Bench (von der Leitung eingeteilt) | 0 |
| Abgemeldet | klein (0,7 beim ersten Mal, später bis 1,5 × Schnitt des Abends) |
| Unentschuldigt gefehlt | mindestens 2 Punkte |
| Weder an- noch abgemeldet | erst wie abgemeldet, ab dem 3. Mal wie unentschuldigt |

- Gezählt werden deine **letzten 6 Raidabende**.
- **Anhebung:** gibt es nur noch von Hand: Die Raid- oder Gildenleitung kann einen Spieler anheben (`/kl anhebung <Name>`).
- **Neu im Kader:** 1. Abend Proberaid (kein Würfeln), am 2. Abend Einstieg bei *Niedrigster + 2*.

## Für den Plündermeister

- Beutemethode „Plündermeister“ einstellen und **„KaosLoot nutzen?“ mit Ja** beantworten.
- Wurf starten: Knopf **„Wurf starten“** oder **`/kl wurf`**, danach im Ergebnis **„Zuteilen“**.
- Falsch zugeteilt: im Verlauf **„Rückgängig“**.

## Hilft bei Problemen

`/kl test` prüft das Addon, `/kl rolle` zeigt, ob es im Dienst ist, `/kl abgleich status` den Datenstand.

## Wie die Wertung zustande kommt

Die Leitung stellt in den Einstellungen unter **Verteilung** ein, nach welchem Verfahren gerechnet wird:

- **Punkte mit Zuschlägen:** Items plus Zuschläge für verpasste Abende (wie bisher).
- **Items pro Abend:** Wie viele Items du pro besuchtem Abend der letzten 8 Raid-IDs bekommen hast. Wer pro Abend am wenigsten hat, ist zuerst dran. Fehlen kostet nichts, und wer oft da ist, wird nicht schlechter gestellt.

Dazu gilt **Heute schon ein Item**: Wer an diesem Abend schon eins hat, steht bei den weiteren Items hinter allen, die noch keins haben. Die Leitung kann außerdem eine **Korrektur** mit Kommentar eintragen, zum Beispiel für unangekündigtes Fehlen. Du siehst sie im Spielerdetail.
