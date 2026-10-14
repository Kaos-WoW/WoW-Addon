# Loot-Historie

WoW-Addon für die Gilde **Resurrected**. Es zeigt, **wer über die Wochen wie
viele Gegenstände bekommen hat** — und wer wann was bekam. Damit der
Plündermeister im Moment der Vergabe schnell und fair entscheiden kann.

Nur für **WoW Forever** (Beta). Für TBC wird es nicht gebraucht.

## Wie es arbeitet

* **Es führt eine eigene Historie** und braucht kein anderes Addon.
* **Nur einer schreibt mit:** der **Plündermeister**; gibt es keinen, der
  **Raidleiter** (Rückfall). Alle anderen empfangen und können die Historie
  einsehen. Jeder im Raid sollte das Addon haben.
* **Gargul** (für die Forever-Beta offiziell veröffentlicht) ist das Würfel-Addon: Seine Vergaben landen mit
  Haupt-/Zweitbedarf und Wurf in der Historie. Gewürfelt wird
  **100 = Hauptbedarf, 50 = Zweitbedarf** — das Addon prüft Garguls
  Würfelbereiche und stellt sie auf Wunsch um.
* **Abgleich ohne Überschreiben:** Weichen die Historien in einer Gruppe
  voneinander ab, bekommen Leiter und Plündermeister einen Hinweis. Ein
  Klick auf *Abgleichen* führt sie zusammen — es kommt nur hinzu, nichts wird
  ersetzt.
* **Gruppen** (z. B. „40er", „10er"): Ein Kader steht in der Liste, auch
  ohne Vergabe; eine Raidgruppe zeigt, wer gerade im Schlachtzug steht.
  Jede Vergabe merkt sich ihre Gruppe, die Ansicht lässt sich umschalten.

## Benutzen

`/lh` öffnet das Fenster. Oben: **Spieler** (Liste), **Verlauf** (wer bekam
was, wann), **Gruppe**, **Abgleichen**, **Einstellungen**.

| Befehl | Zweck |
|---|---|
| `/lh` | Fenster öffnen und schließen |
| `/lh verlauf` | wer bekam was, wann |
| `/lh demo` | Beispieldaten ansehen — nichts wird gespeichert |
| `/lh liste` | dieselbe Auswertung im Chat, `liste 4` für vier Wochen |
| `/lh <Name>` | Einzelvergaben eines Spielers |
| `/lh abgleich` | Historien der Gruppe zusammenführen (`abgleich status`: Stand) |
| `/lh rolle` | wer schreibt gerade mit, und warum |
| `/lh gruppe` | Kader und Raidgruppen (`gruppe hilfe`) |
| `/lh bereiche` | Garguls Würfelbereiche prüfen (`bereiche setzen`) |
| `/lh filter` | ab welcher Qualität und wo mitgeschrieben wird |
| `/lh stand` | Diagnose |
| `/lh test` | Selbsttests |

**Hauptbedarf** bestimmt die Reihenfolge, **Zweitbedarf** steht daneben und
zählt nicht mit — wer ein Stück für die Zweitrolle bekommt, hat keinen
Anspruch verbraucht.

## Einbauen

```powershell
.\deploy.ps1
```

Rollt in die Forever-Beta aus. Danach im Spiel `/reload`.

## Mitarbeiten

Entwicklungsnotizen, Begründungen und Fallstricke stehen in
[`AGENTS.md`](AGENTS.md). Vor dem Ausrollen:

```
python luacheck.py LootHistorie/*.lua       # Blockstruktur
pip install lupa                            # einmalig: Lua 5.1 für Python
python tests/rechenkern.py                  # Selbsttests ohne Spiel
python tests/szenarien.py                   # mehrere virtuelle Clients, Abgleich, Oberfläche
```
