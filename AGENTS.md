# Loot-Historie — Projektnotizen

Addon für die Gilde **Resurrected** (Thunderstrike EU). Es beantwortet:
**Wer hat über die Wochen wie viele Gegenstände bekommen — und wer bekam
wann was?** Damit der Plündermeister im Moment der Vergabe schnell und
begründet entscheiden kann.

Stand 14.10.2026, Version 0.1.0 (noch nicht veröffentlicht).

---

## Das Prinzip (seit 14.10.2026)

⭐ **Eigene Historie, ein Schreiber, Abgleich ohne Überschreiben.**

* **Das Addon führt eine eigene Historie** (`LootHistorieDB.vergaben`,
  Eintrag je Kennung). Es braucht kein anderes Addon.
* **Nur einer schreibt mit** — Entscheid des Gildenleiters: der
  **Plündermeister**, und gibt es keinen, der **Raidleiter** (Rückfall).
  Alle anderen empfangen. Grund: Sähe jeder dieselbe Beutemeldung und
  schriebe sie auf, gäbe es je Drop so viele Einträge wie Spieler im Raid.
* **Gargul ist der Würfler, wir hören zu.** `GL.ITEM_AWARDED` bringt Kennung,
  Haupt/Zweit (`OS`) und Wurf mit — das liefert der Chat nie. Ohne Gargul
  liest das Addon Würfe und Beute selbst aus dem Chat.
* **Jeder Eintrag hat eine feste Kennung**, Einfügen ist idempotent. So
  lassen sich Historien zusammenführen, ohne etwas zu überschreiben.

Vorbilder (CurseForge-Auswertung 14.10.2026, nur Funktionsweise, kein Code):
RCLootCouncil „Improved History" und CLM gleichen per Prüfsumme ab und
tauschen nur Abweichendes; CLM verwirft Nachrichten Unberechtigter still;
Gargul vergibt je Vergabe eine Kennung und sendet sie live an die Gruppe.

Davor (25.09.–13.10.): „Das Addon liest nur Garguls Historie". Das wurde
verworfen, weil Gargul in Forever Nachnamen nicht kennt und weil ein Addon,
das nur liest, weder Haupt/Zweit noch Gruppen noch Abgleich leisten kann.

---

## Dateien (Ladereihenfolge der TOC)

| Datei | Zweck | WoW-API? |
|---|---|---|
| `Kern.lua` | Zählen, Sortieren, Zusammenführen, Prüfsummen, Kodierung, Schreiberwahl | **nein** |
| `Quelle.lua` | Garguls Historie, Würfelbereiche, Gegenstandstexte, Beispieldaten | ja |
| `Rolle.lua` | Gruppe lesen: wer ist Plündermeister/Leiter, schreibe ich mit | ja |
| `Gruppen.lua` | Kader und Raidgruppen | ja |
| `Erfassung.lua` | Chat, Würfe, Einstellungen, Eintragen, Gargul-Vergaben | ja |
| `Abgleich.lua` | Hallo, Live-Meldung, Abgleich, Hinweis-Fenster | ja |
| `Blizzbeute.lua` | Blizzards `C_LootHistory` als zweite Quelle | ja |
| `Einstellungen.lua` | Einstellungsseiten im Fenster | ja |
| `Fenster.lua` | Liste, Verlauf, Spielerdetail, Wurf-Modus | ja |
| `Befehle.lua` | `/lh` | ja |
| `Tests.lua` | Prüfstand für `Kern.lua` | **nein** |

Alles Rechnerische steht in `Kern.lua` und wird dort getestet. Jede
Auswertung nimmt die Historie **als Parameter**, dadurch laufen Beispieldaten
durch dieselbe Anzeige, ohne dass irgendwo etwas abgelegt wird.

### Eintragsform

```
awardedTo, itemID, itemLink, timestamp, OS (Zweitbedarf), gruppe, wurf,
herkunft ("chat" | "blizzard" | "gargul" | "gargul-import" | "abgleich" | "gruppe"),
zurueck (zurückgenommen)
```

Dieselben Feldnamen wie bei Gargul, damit beide ohne Umrechnen lesbar sind.

---

## Schreiber (`Rolle.lua`, `Kern.Schreiber`)

Rangfolge: **Plündermeister → Leiter → Assistenten**. Gewählt wird der erste,
der das Addon nachweislich hat (Hallo-Meldung) oder man selbst ist.

* Ohne Gruppe schreibt man selbst mit (Test, Solo-Instanz).
* Bis die Hallo-Meldungen da sind (wenige Sekunden nach dem Beitritt),
  schreibt zur Not auch der Leiter mit. **Doppelt ist besser als gar nicht**;
  der Abgleich fängt Doppelte ab, eine fehlende Vergabe nicht.
* `/lh rolle` zeigt Kandidaten und Grund; Einstellung `schreiben`:
  `auto` | `immer` | `nie`.
* Die Beutemethode kommt versionsbewusst aus `GetLootMethod()` oder
  `C_PartyInfo.GetLootMethod()` (Zahl, 2 = Plündermeister).
  ⚠️ **Ob Forever überhaupt Plündermeister kennt, ist ungemessen.**

---

## Abgleich (`Abgleich.lua`)

Addon-Nachrichten, Präfix `LHIST`, Takt 0,25 s (Blizzards Drosselung).

| Typ | Inhalt | Wer darf senden |
|---|---|---|
| `H` | Hallo: Version, Anzahl, Prüfsumme | jeder in der Gruppe |
| `L` | eine neue Vergabe live | Plündermeister, Leiter, Assistent |
| `Q` | Tagesstand des Leiters (Prüfsumme je Tag, UTC) | Plündermeister, Leiter, Assistent |
| `N` | „diese Tage weichen bei mir ab" | jeder in der Gruppe |
| `E` | Einträge dieser Tage | jeder in Gruppe **und Gilde** |

Ablauf: Weicht beim Hallo jemand ab, bekommt der Leiter ein Hinweis-Fenster
(einmal je Zusammensetzung der Abweichler). **Abgleichen** → `Q`; jeder
vergleicht, meldet abweichende Tage (`N`) und schickt seine Einträge dazu
(`E`); der Leiter schickt die gemeldeten Tage nach. Wer in seiner zufälligen
Wartezeit hört, dass es schon da ist, schweigt.

### Warum das konvergiert

* **Einfügen ist idempotent** (`Kern.Zusammenfuehren`): Kennung bekannt →
  nichts. Überschrieben wird nie.
* **Doppelgänger** (gleicher Spieler, gleicher Gegenstand, ≤ 180 s,
  verschiedene Kennung, z. B. Chat gegen Gargul) werden nicht eingefügt, ihre
  Kennung wandert in `alias`. **Die Prüfsumme zählt Alias-Kennungen mit** —
  ohne das wären A {X, Alias Y} und B {Y, Alias X} ewig „verschieden".
* Der einzige veränderliche Wert ist `zurueck`: Er wechselt nur von nein auf
  ja (monoton) und wird deshalb mitgeführt. Andere Änderungen (anderer
  Gewinner nach einer Gargul-Bearbeitung) wandern **nicht** — der Abgleich
  fügt nur hinzu.

### Sicherheit

Eingehendes wird in `Kern.Dekodieren` geprüft (Länge, Zahlen, Zeitraum, Art).
`E` kommt nur von Gildenmitgliedern in der Gruppe, `L` und `Q` zusätzlich nur
von Plündermeister/Leiter/Assistent. Kann ein Absender nicht einer Einheit
zugeordnet werden, wird er verworfen: lieber einen Abgleich verpassen als
fremde Daten annehmen. `/lh abgleich status` zeigt den Rohnamen des letzten
Absenders und seine Zuordnung.

### ⚠️ Ungemessen im Spiel

* **Absendername** in `CHAT_MSG_ADDON` bei Nachnamen: `Kern.GleicherSpieler`
  fängt „mit/ohne Nachname" und „mit/ohne Realm" ab; ob Forever noch anders
  formatiert, zeigt erst `/lh abgleich status`.
* **Einschränkung von Addon-Nachrichten in Instanzen/Kampf** (Mainline-Linie
  seit 12.0). Gedrosselte oder gesperrte Nachrichten werden bis zu sechsmal
  später wiederholt.
* `UnitIsInMyGuild`: fehlt es, gilt der Absender als Mitglied.

---

## Gargul

* **Würfelbereiche:** Gargul bringt MS 1–100 und OS 1–99 mit. Die Gilde
  würfelt **100 / 50**. `Quelle.GargulBereiche()` prüft, `…Setzen()` stellt
  `RollTracking.Brackets` um (Einstellung, kein Eingriff in den Code);
  `/lh bereiche`. Sonst ordnet Gargul die 50er-Würfe nicht ein.
* **Ereignisse:** `GL.ITEM_AWARDED` → eintragen; `GL.ITEM_AWARD_EDITED` →
  Gewinner/Haupt-Zweit nachziehen; `GL.ITEM_UNAWARDED` → `zurueck` setzen
  (nicht löschen, sonst brächte der Abgleich es zurück) und verteilen.
* Kam die Beutemeldung vor Gargul, wird der Eintrag **berichtigt**, nicht
  verdoppelt (`herkunft = "gargul"`).
* **Gargul 8.0.1 (03.10.2026) hat offiziellen Forever-Support**, kennt aber
  weiterhin keine Nachnamen (kein Treffer für „surname"). Lizenz bleibt
  **All Rights Reserved**: nur Ereignisse und die Historie lesen,
  **keinen Code übernehmen**, nichts davon ins Repo.

---

## Gruppen (`Gruppen.lua`)

* **Kader**: feste Namensliste (der ganze 40er-Kader) — steht in der Liste,
  auch ohne Vergabe.
* **Raidgruppe**: wer gerade im Schlachtzug steht (kleinere Raids).
* Jede Vergabe trägt die beim Eintragen aktive Gruppe. Gezählt wird über
  alles; die Ansicht schaltet auf eine Gruppe oder alle um. **Ob ein 10er
  für die 40er-Statistik zählt, ist damit eine Frage der Ansicht**, nicht der
  Aufzeichnung.
* Namen mit Nachnamen: Kader-Einträge werden nur an Kommas/Zeilenumbrüchen
  getrennt, nie an Leerzeichen.

---

## Entscheidungen, die nicht offensichtlich sind

### Zweitbedarf zählt getrennt und sortiert nicht mit

Wer ein Stück für die Zweitrolle bekommt, hat damit keinen Anspruch
verbraucht. Es steht trotzdem in der Liste, weil die Leitung es sehen will —
aber die Reihenfolge richtet sich allein nach Hauptbedarf. Aus demselben
Grund folgt **„Zuletzt" nur dem Hauptbedarf**.

### Vier Arten von Einträgen fallen heraus

`Kern.Zaehlt`: **entzaubert**, **Bonus-Beute**, **zurückgenommen**,
**unvollständig** (ohne Gewinner oder Zeitstempel).

### Nachnamen in Forever

`UnitName` liefert `name, surname` (nicht den Realm). Der volle Name ist
`GetUnitName(unit, true)` („Yondaime Kaos"). Muster aus Textvorlagen bauen
`%s` zu `(.-)`, nie zu `(%S+)`. `Kern.Schluessel` schneidet nur am `-` ab;
`Kern.GleicherSpieler` lässt den Nachnamen auf **einer** Seite fehlen.

### ⚠️ „Raidtage" ist keine Anwesenheit

Gezählt werden Kalendertage mit mindestens einer Vergabe. Wer da war und
nichts bekam, steht nirgends — außer in Kader oder Raidgruppe.

### Erfasst wird ab Selten, nicht ab Episch

Auf Stufe 60 ist offen, ob in den Raids überhaupt Episches fällt (in
Zul'Gurub ist das meiste blau). **Ein verpasster Drop ist unwiederbringlich,
eine Zeile zu viel nur lästig.** `/lh filter 4` hebt die Schwelle. Dazu der
**Ort** (`raid` | `instanz` | `überall`) und `filter wurf` (nur
Ausgewürfeltes, Standard aus).

### Das Fenster kommt ohne Bibliotheken aus

Fester Satz Zeilen plus Mausrad-Versatz. Ein Teil weniger, das beim nächsten
Patch bricht. Es hält keinen Zustand über die Sitzung hinaus und liest bei
jedem Aufbau frisch.

---

## Arbeitsweise

```
python luacheck.py LootHistorie/*.lua     # Blockstruktur, echter Tokenizer
pip install lupa                          # einmalig
python tests/rechenkern.py                # Kern + Tests.lua in echtem Lua 5.1
python tests/szenarien.py                 # mehrere virtuelle Clients
.\deploy.ps1                              # in alle vorhandenen Clients
```

⭐ **`tests/szenarien.py` ersetzt „kein Lua auf dem Rechner".** Es lädt das
komplette Addon (auch Fenster und Einstellungen, mit Attrappen für Frames)
mehrfach in getrennten Lua-Zuständen, verbindet sie über einen simulierten
Nachrichtenkanal samt Uhr und prüft: Schreiberwahl, Live-Meldung, vollen
Abgleich in beide Richtungen, Doppelgänger, Sicherheitsregeln, Gargul-
Ereignisse, Gruppen, jeden Knopf und jeden Befehl. Es prüft **nicht**, wie
etwas aussieht und wie sich der echte Client verhält (Nachrichtenformat der
Absendernamen, Drosselung, Plündermeister in Forever).

⚠️ In der Attrappe lässt sich nur testen, was die Attrappe nachbildet.
Neue WoW-API-Aufrufe brauchen eine Zeile in `STUBS` (`tests/sim.py`), sonst
fehlen sie dort — und im Spiel nicht.

### Lehren

* ⭐ **Kein Befehl darf still scheitern.** WoW verschluckt Laufzeitfehler,
  solange `scriptErrors` aus ist. Der Slash-Dispatcher läuft über `pcall`.
  **Nicht zurückbauen.**
* ⭐ **Erwartungswerte aus der Regel herleiten, nie aus der Funktion
  daneben.**
* ⚠️ **Version an Fähigkeiten erkennen, nie an der Nummer** (`C_Item` gegen
  Global).
* ⚠️ **SavedVariables sind eine Versionsgrenze**: umbenannte Felder brauchen
  einen Nachziehpfad (`db()` in `Erfassung.lua`).
* **Fremde Daten nie vertrauen**: alles Eingehende prüfen und im Zweifel
  verwerfen.
* Deutsche Sprache in Kommentaren, Ausgaben und Bezeichnern. Gewollt.

---

## Clients

Eine Quelle, eine TOC, beide Clients:

```
## Interface: 16001, 120100, 120105, 20506
```

* **TBC Anniversary** (`_anniversary_`) — hier raidet die Gilde.
* **WoW Forever Beta** (`_classic_beta_`) — Mainline-Unterbau 12.1.5.

Gargul läuft in beiden (in Forever seit 8.0.1 offiziell). **Dieses Addon darf
keine fehlenden Globals selbst definieren** — Garguls Weichen prüfen
`Global or C_Namespace.Name` und nähmen sonst den falschen Weg.

---

## Vorgeschichte

Davor stand ein größeres System: **`Prio = Einsatz ÷ Rüstwert`**, Konten in
der Offiziersnotiz, Verfall, Regelwerk mit zehn Paragrafen. Der Gildenleiter
hat es am 25.09.2026 als zu komplex verworfen. Stand im Tag
**`prio-system-stand`** (Commit `0727bf7`):

```
git checkout prio-system-stand -- .
```

* **Offiziersnotizen sind in Forever für Addons nicht beschreibbar.**
  `C_GuildInfo.SetNote` ist geschützt.
* **SavedVariables laden seit Build 70009 (25.09.2026) wieder zurück.**
