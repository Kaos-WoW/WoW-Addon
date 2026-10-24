# KaosLoot

WoW-Addon für die Gilde **Resurrected** (WoW Forever). Faire Beuteverteilung: Es hält fest, **wer welches Item bekommen hat**, rechnet für jeden Wurf eine **faire Reihenfolge** und bringt ein eigenes **Würfelfenster** mit. Wer die niedrigste Wertung hat, bekommt das Item zuerst; nur bei Gleichstand entscheidet der Wurf.

Version **1.1.0**. Sprache: Deutsch und Englisch (nach dem Client).

## Kurz erklärt

* **Wertung** = erhaltene Main-Items + Zuschläge für verpasste Abende. Bank/Bench kostet nichts, Unentschuldigt mindestens 2 Punkte. Die Anhebung gibt es nur von Hand (`/kl anhebung <Name>`).
* **Eigenes Würfelfenster:** Haupt (1-100), OS (1-99), Passen. Der erste Wurf zählt.
* **Zuteilen** aus dem Beutefenster oder per Handel, Entzaubern, Rückgängig.
* **Historie** für alle in der Gruppe, automatischer Abgleich (es kommt nur hinzu). Offiziere gleichen gildenweit ab.
* **Gruppen** für 10, 20 und 40: Raidkader aus Gildenrängen, Einteilung einmal je Raid-ID, Reiter *Anwesenheit*, Wochenabschluss, Gruppe mit einem Klick einladen.
* **Kompaktfenster** für den Raid (`/kl kompakt`): nur die Wertung und der laufende Wurf, mit Knopf *Wurf starten*; Vorschau mit `/kl kompakt test`.
* **Einladen per Flüstern** (persönlich, standardmäßig aus): Wer dir dein Stichwort flüstert (`/kl einladewort`, Einstellungen → Gruppen), wird in deine Gruppe eingeladen; eine volle normale Gruppe wird dafür zum Raid.
* **Zwei Verfahren für die Wertung** (Einstellungen → Verteilung): *Punkte mit Zuschlägen* (wie bisher) und *Items pro Abend* (die letzten 8 Raid-IDs, gleitend, Fehlen kostet nichts). Dazu die Regel *Heute schon ein Item* und die *Korrektur der Leitung* (Plus oder Minus mit Kommentar, `/kl korrektur`). `/kl vergleich` zeigt beide nebeneinander.
* **Neu in KaosLoot** (`/kl neu`): Änderungsliste je Version, mit „!“ am Knopf und an Einstellungsseiten mit Neuem.
* **Geteilte Einstellungen** (Gildenmeister und Offiziere), gildenweiter Reset (`/kl reset gilde`), Übungsmodus (`/kl probe`).

Nur in einer Gruppe wird aufgezeichnet; **nur der Plündermeister braucht das Addon** (ohne ihn der Raidleiter). Alle anderen würfeln wie gewohnt mit `/roll`; wer das Addon hat, bekommt das Würfelfenster und kann Historie und Wertungen einsehen. KaosLoot fragt erst, wenn die Beutemethode auf Plündermeister steht, ob es genutzt werden soll („KaosLoot nutzen?“); mit Ja übernimmt es, bei jeder anderen Beutemethode bleibt es still.

## Benutzen

`/kl` öffnet das Fenster, `/kl hilfe` zeigt alle Befehle. Eine kurze Anleitung für Spieler steht in [`ANLEITUNG.md`](ANLEITUNG.md), die Regeln in [`REGELWERK-ENTWURF.md`](REGELWERK-ENTWURF.md).

## Für Entwickler

Architektur, Protokoll und Entscheidungen: [`AGENTS.md`](AGENTS.md). Wer woran arbeitet: [`WORKBOARD.md`](WORKBOARD.md).

```
python luacheck.py                  # Blockstruktur
python tests/rechenkern.py          # Kern + Tests.lua in echtem Lua 5.1 (pip install lupa)
python tests/szenarien.py           # mehrere virtuelle Clients (ohne -I starten)
python tests/texte.py --streng      # Übersetzungen vollständig?
.\deploy.ps1                        # in WoW Forever ausrollen
python release/bauen.py --cf        # CurseForge-Zip aus dem letzten Commit
```

## Lizenz

All Rights Reserved. Schrift Inter (SIL OFL) und Symbole Tabler Icons (MIT), Lizenzen im Ordner `KaosLoot/Media`.
