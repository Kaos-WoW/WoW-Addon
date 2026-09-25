# Loot-Historie — Projektnotizen

Addon für die Gilde **Resurrected** (Thunderstrike EU). Es beantwortet eine
einzige Frage: **Wer hat über die letzten Wochen wie viele Gegenstände
bekommen?** Damit der Plündermeister im Moment der Vergabe schnell und
begründet entscheiden kann.

Stand 25.09.2026, Version 0.1.0.

---

## Das Prinzip

⭐ **Das Addon führt keine eigene Datenbank.** Es liest [Gargul](https://www.curseforge.com/wow/addons/gargul),
wertet aus und zeigt an. Geschrieben wird nie.

Das ist keine Bequemlichkeit, sondern die tragende Entscheidung:

* Gargul hält die Vergaben in `Gargul.DB.AwardHistory`, dauerhaft, nach
  Prüfsumme abgelegt, und **beschneidet sie nie**.
* Gargul **verteilt jede Vergabe an die Gruppe** — beim Empfänger landet sie
  über `storeReceivedAward` in dessen eigener Historie. Bei allen
  Raidleitern wächst also dieselbe Liste.
* Also braucht es **keinen Abgleich, keinen Import, keinen Export-String**.
  Was es nicht gibt, kann nicht auseinanderlaufen.

Gargul öffnet sich dafür ausdrücklich, in seiner `bootstrap.lua`:

```lua
_G.Gargul = GL; -- Open Gargul up to other developer integrations
```

⚠️ Fremde Innereien sind trotzdem ein Vertrag, den niemand unterschrieben
hat. Ändert Gargul die Struktur, muss das **hier** auffallen und nicht in
der Anzeige — darum liefert `Quelle.Gargul()` immer einen benennbaren
Grund, und `/lh stand` macht ihn sichtbar.

---

## Dateien

| Datei | Zweck | WoW-API? |
|---|---|---|
| `Kern.lua` | Filtern, Zählen, Sortieren | **nein** |
| `Quelle.lua` | Garguls Historie, Gegenstandstexte, Beispieldaten | ja |
| `Fenster.lua` | die Anzeige | ja |
| `Befehle.lua` | `/lh` | ja |
| `Tests.lua` | Prüfstand für `Kern.lua` | **nein** |

`Kern.lua` und `Tests.lua` sind API-frei und laufen auch ohne Client.
Jede Auswertung nimmt die Historie **als Parameter** — dadurch lassen sich
Beispieldaten durch dieselbe Anzeige schicken, ohne irgendwo etwas
abzulegen.

---

## Befehle

| Befehl | Zweck |
|---|---|
| `/lh` | Fenster öffnen und schließen |
| `/lh demo` | Fenster mit Beispieldaten — **nichts wird gespeichert** |
| `/lh liste` | dieselbe Auswertung im Chat, `liste 4` für vier Wochen |
| `/lh <Name>` | Einzelvergaben eines Spielers im Chat |
| `/lh stand` | Diagnose: liegt Garguls Historie vor, wie viel ist auswertbar |
| `/lh test` | Selbsttests der Auswertung |

---

## Entscheidungen, die nicht offensichtlich sind

### Zweitbedarf zählt getrennt und sortiert nicht mit

Wer ein Stück für die Zweitrolle bekommt, hat damit keinen Anspruch
verbraucht. Es steht trotzdem in der Liste, weil die Leitung es sehen will —
aber die Reihenfolge richtet sich allein nach Hauptbedarf. Aus demselben
Grund folgt **„Zuletzt" nur dem Hauptbedarf**: ein Zweitbedarfsstück von
gestern sagt über den Anspruch nichts aus.

### Drei Arten von Einträgen fallen heraus

`Kern.Zaehlt` siebt aus, jeweils aus eigenem Grund: **entzaubert** (ging an
niemanden, Gargul trägt `||de||` als Gewinner ein), **Bonus-Beute**
(zusätzliche Beute außerhalb der Vergabe) und **unvollständig** (ohne
Gewinner oder Zeitstempel nicht auswertbar).

### ⚠️ Der Realm wird abgeschnitten

Gargul schreibt den Gewinner mal mit, mal ohne Realm — je nachdem, ob die
Vergabe lokal entstand oder über die Gruppe hereinkam. Ohne
Vereinheitlichung stünde derselbe Spieler zweimal in der Liste. Das setzt
**eine Gilde auf einem Realm** voraus; zwei Gleichnamige von verschiedenen
Realms liefen zusammen.

### ⚠️ „Raidtage" ist keine Anwesenheit

Gezählt werden Kalendertage mit mindestens einer Vergabe. Wer da war und
nichts bekam, steht in Garguls Daten **nirgends**. Die Zahl taugt als
Bezugsgröße für „viel" und „wenig", nicht als Teilnahmenachweis.

Damit hat das Addon eine bewusste Lücke: **eine reine Gegenstandszahl misst
nicht, wer erscheint.** Wer jede Woche mitgeht und fünf Stücke gewonnen hat,
steht unter jemandem, der zweimal da war und nichts bekam. Für ein Werkzeug,
das einem *Menschen* zuarbeitet, ist das in Ordnung — die Leitung weiß, wer
da ist. Als automatische Rangfolge wäre es das nicht.

### Das Fenster kommt ohne Bibliotheken aus

Fester Satz Zeilen plus Mausrad-Versatz statt Bildlaufleiste. Ein Teil
weniger, das beim nächsten Patch bricht. Es hält keinen Zustand über die
Sitzung hinaus und liest bei jedem Aufbau frisch — dadurch kann es nie
etwas Veraltetes zeigen.

---

## Arbeitsweise

```
python luacheck.py LootHistorie/*.lua     # Blockstruktur, echter Tokenizer
.\deploy.ps1                               # in alle vorhandenen Clients
```

⚠️ **Es gibt kein Lua auf dem Rechner** — die Tests laufen nur im Spiel über
`/lh test`. `luacheck.py` prüft **Struktur, keine Semantik**; ein
`nil`-Zugriff findet er nicht.

### Die Lehren aus dem Vorgängerprojekt

* ⭐ **Kein Befehl darf still scheitern.** WoW verschluckt Laufzeitfehler,
  solange `scriptErrors` aus ist — und das ist die Voreinstellung. Der
  Slash-Dispatcher läuft deshalb über `pcall` und druckt die Meldung in den
  Chat. **Nicht zurückbauen.**
* ⭐ **Erwartungswerte aus der Regel herleiten, nie aus der Funktion
  daneben.** Ein Test, dessen Sollwert aus der Implementierung stammt, prüft
  nichts. Das hat einmal einen echten Verstoß durchgelassen.
* ⚠️ **Version an Fähigkeiten erkennen, nie an der Nummer.** In Forever
  fehlen `GetItemInfo` und Verwandte als Globals, es gibt nur `C_Item.*`.
  Also `if C_Item and C_Item.GetItemInfo`, nicht `if isTBC`.
* Deutsche Sprache in Kommentaren, Ausgaben und Bezeichnern. Das ist
  gewollt, nicht Zufall.

---

## Clients

Eine Quelle, eine TOC, beide Clients:

```
## Interface: 16001, 120100, 120105, 20506
```

* **TBC Anniversary** (`_anniversary_`) — hier raidet die Gilde, hier läuft
  Gargul aus CurseForge.
* **WoW Forever Beta** (`_classic_beta_`) — Mainline-Unterbau 12.1.5.
  ⚠️ Gargul gibt es dort **nicht offiziell**; es liegt nur als lokale
  Testkopie mit angepasster Interface-Nummer. Siehe unten.

### ⚠️ Gargul auf Forever

Gargul steht unter **All Rights Reserved** (`## X-License: ARR`) und
untersagt Änderungen ohne schriftliche Erlaubnis. Die Kopie im Beta-Client
ist eine **rein lokale Testkopie**: kopiert, eine Interface-Zeile je TOC
geändert, Lua unangetastet. **Nicht weitergeben, nicht hochladen, nicht ins
Repo.** Für den Dauerbetrieb muss der Autor gefragt werden — sein Discord
steht in Garguls README.

Dass so wenig nötig war, liegt an Gargul selbst: `Utils/Shims.lua` deckt die
Mainline-Umstellungen bereits ab (`C_Item`, `C_Container`, `C_AddOns`,
`C_CurrencyInfo`, `C_PartyInfo` samt Enum→Zeichenkette für `GetLootMethod`).
**Deshalb darf dieses Addon keine fehlenden Globals selbst definieren** —
Garguls Weichen prüfen `Global or C_Namespace.Name` und nähmen sonst den
falschen Weg.

Drei Aufrufe führt Gargul **nicht** über seine Weichen, alle in
Randfunktionen: `GetItemCount` (`BagInspector.lua:76`),
`GetDetailedItemLevelInfo` (`GDKP.lua:39`), `GetGuildRosterInfo`
(`User.lua:247`). Sie fallen erst auf, wenn genau diese Funktionen laufen.

---

## Vorgeschichte

Davor stand ein deutlich größeres System: **`Prio = Einsatz ÷ Rüstwert`**,
Konten in der Offiziersnotiz, Verfall, Regelwerk mit zehn Paragrafen. Der
Gildenleiter hat es am 25.09.2026 als zu komplex verworfen.

Der vollständige Stand liegt im Tag **`prio-system-stand`** (Commit
`0727bf7`) und ist jederzeit zurückholbar:

```
git checkout prio-system-stand -- .
```

Was davon gültig bleibt, steht oben unter „Die Lehren". Zwei Befunde aus
dieser Zeit sind weiterhin wichtig:

* **Offiziersnotizen sind in Forever für Addons nicht beschreibbar.**
  `C_GuildInfo.SetNote` ist geschützt; ein Aufruf aus Addon-Code endet als
  `ADDON_ACTION_BLOCKED`. Lesen geht.
* **SavedVariables laden seit Build 70009 (25.09.2026) wieder zurück.**
  Davor wurden sie geschrieben, aber beim Start nicht gelesen.
