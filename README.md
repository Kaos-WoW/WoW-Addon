# Fairshare

WoW-Addon für die Gilde **Resurrected**. Es zeigt, **wer über die Wochen wie
viele Gegenstände bekommen hat** — und wer wann was bekam. Damit der
Plündermeister im Moment der Vergabe schnell und fair entscheiden kann.

Nur für **WoW Forever** (Beta). Für TBC wird es nicht gebraucht.

Das Addon spricht die **Sprache des Clients**: deutscher Client Deutsch, jeder andere Englisch.

## Wie es arbeitet

* **Es führt eine eigene Historie** und braucht kein anderes Addon.
* **Nur in einer Gruppe:** Allein unterwegs wird nichts aufgezeichnet.
* **Nur einer zeichnet auf:** der **Plündermeister**; gibt es keinen, der
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
* **Gruppen** (z. B. „40er", „10er") sind eine Beschriftung mit einem Kader. **In einer Gruppe zeigt die
  Übersicht nur die Spieler, die bei dir sind**; ohne Gruppe den Kader. Der **Member sync** gleicht den Kader mit den
  gewählten **Gildenrängen** ab: Neue kommen dazu, Ausgetretene fallen weg, von Hand ergänzte Namen bleiben. Jede Vergabe merkt sich ihre
  Gruppe, die Ansicht lässt sich umschalten.
* **Der Abgleich läuft von selbst**: Wer mit dir in einer Gruppe steht, bekommt deine Daten, und du bekommst
  seine — nur Hinzufügen, nichts wird überschrieben.

## Benutzen

`/fs` öffnet das Fenster. Oben: **Spieler** (Liste), **Verlauf** (wer bekam
was, wann), **Gruppe**, **Abgleichen**, **Einstellungen** (eigenes Fenster im Look von
KaosUI).

| Befehl | Zweck |
|---|---|
| `/fs` | Fenster öffnen und schließen |
| `/fs verlauf` | wer bekam was, wann |
| `/fs einstellungen` | das Einstellungsfenster |
| `/fs demo` | Beispieldaten ansehen — nichts wird gespeichert |
| `/fs liste` | dieselbe Auswertung im Chat, `liste 4` für vier Wochen |
| `/fs <Name>` | Einzelvergaben eines Spielers |
| `/fs abgleich` | Historien der Gruppe zusammenführen (`abgleich status`: Stand) |
| `/fs rolle` | wer zeichnet gerade auf, und warum |
| `/fs gruppe` | Kader und Raidgruppen (`gruppe hilfe`) |
| `/fs bereiche` | Garguls Würfelbereiche prüfen (`bereiche setzen`) |
| `/fs filter` | ab welcher Qualität und wo aufgezeichnet wird |
| `/fs stand` | Diagnose |
| `/fs test` | Selbsttests |

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
python luacheck.py Fairshare/*.lua       # Blockstruktur
pip install lupa                            # einmalig: Lua 5.1 für Python
python tests/rechenkern.py                  # Selbsttests ohne Spiel
python tests/szenarien.py                   # mehrere virtuelle Clients, Abgleich, Oberfläche, englischer Client
python tests/texte.py --streng              # Übersetzung vollständig?
```
