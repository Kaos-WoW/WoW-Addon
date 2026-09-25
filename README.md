# Loot-Historie

WoW-Addon für die Gilde **Resurrected**. Es zeigt, **wer über die letzten
Wochen wie viele Gegenstände bekommen hat** — damit der Plündermeister im
Moment der Vergabe schnell entscheiden kann.

Läuft im **TBC-Anniversary-Client** und in der **WoW-Forever-Beta**.

## Voraussetzung

[**Gargul**](https://www.curseforge.com/wow/addons/gargul). Das Addon führt
keine eigene Datenbank, sondern liest Garguls Vergabe-Historie — und
schreibt nie hinein. Weil Gargul jede Vergabe an die Gruppe verteilt, wächst
bei allen Raidleitern dieselbe Liste; abgeglichen werden muss nichts.

Ohne Gargul sagt das Addon das klar und zeigt auf Wunsch Beispieldaten.

## Benutzen

| Befehl | Zweck |
|---|---|
| `/lh` | Fenster öffnen und schließen |
| `/lh demo` | Beispieldaten ansehen — nichts wird gespeichert |
| `/lh liste` | dieselbe Auswertung im Chat, `liste 4` für vier Wochen |
| `/lh <Name>` | Einzelvergaben eines Spielers |
| `/lh stand` | Diagnose: liegt Garguls Historie vor |
| `/lh test` | Selbsttests |

Im Fenster: Zeitraum oben umschalten, Zeile anklicken für die Einzelvergaben
eines Spielers, Mausrad blättert.

**Hauptbedarf** bestimmt die Reihenfolge, **Zweitbedarf** steht daneben und
zählt nicht mit — wer ein Stück für die Zweitrolle bekommt, hat keinen
Anspruch verbraucht.

## Einbauen

```powershell
.\deploy.ps1
```

Rollt in alle vorhandenen Clients aus. Danach im Spiel `/reload`.

## Mitarbeiten

Entwicklungsnotizen, Begründungen und Fallstricke stehen in
[`AGENTS.md`](AGENTS.md). Vor dem Ausrollen:

```
python luacheck.py LootHistorie/*.lua
```
