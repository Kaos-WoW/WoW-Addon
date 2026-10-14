# Fairshare — Projektnotizen

Addon für die Gilde **Resurrected** (Thunderstrike EU). Es beantwortet:
**Wer hat über die Wochen wie viele Gegenstände bekommen — und wer bekam
wann was?** Damit der Plündermeister im Moment der Vergabe schnell und
begründet entscheiden kann.

**Name:** Fairshare, Befehl `/fs` (bis 14.10.2026 „Loot-Historie“, `/lh`; der Name sagte zu wenig, das Addon schreibt
mit, gleicht ab, verwaltet Gruppen). Ordner `Fairshare/`, SavedVariables `FairshareDB`, Nachrichtenpräfix
`FSHARE`. ⚠️ **Der Umzug der gespeicherten Daten** (`LootHistorie.lua` → `Fairshare.lua`, Variable umbenannt)
macht `deploy.ps1` einmalig und **nur bei beendetem WoW** (sonst bricht es ab, ohne etwas zu ändern); die alte
Datei bleibt als Sicherung. Spätere Umbenennungen brauchen denselben Weg.

Stand 14.10.2026, Version 0.1.0 (noch nicht veröffentlicht). Nur für Forever.

---

## Das Prinzip (seit 14.10.2026)

⭐ **Eigene Historie, ein Schreiber, Abgleich ohne Überschreiben.**

* **Das Addon führt eine eigene Historie** (`FairshareDB.vergaben`,
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
| `Locale.lua` | Sprache: deutscher Client Deutsch, sonst Englisch (`L["deutscher Satz"]`) | ja |
| `Quelle.lua` | Garguls Historie, Würfelbereiche, Gegenstandstexte, Beispieldaten | ja |
| `Rolle.lua` | Gruppe lesen: wer ist Plündermeister/Leiter, schreibe ich mit | ja |
| `Gruppen.lua` | Kader und Raidgruppen | ja |
| `Erfassung.lua` | Chat, Würfe, Einstellungen, Eintragen, Gargul-Vergaben | ja |
| `Abgleich.lua` | Hallo, Live-Meldung, Abgleich, Hinweis-Fenster | ja |
| `Blizzbeute.lua` | Blizzards `C_LootHistory` als zweite Quelle | ja |
| `Stil.lua` | Bausteine im KaosUI-Look (Farben, runde Ecken, Knopf, Schalter, Segmentwahl, Bildlauf) | ja |
| `Einstellungen.lua` | das Einstellungsfenster (Karten und Zeilen, drei Seiten) | ja |
| `Fenster.lua` | die Übersicht im KaosUI-Look: Liste, Verlauf, Spielerdetail, Wurf-Modus | ja |
| `Befehle.lua` | `/fs` | ja |
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
* `/fs rolle` zeigt Kandidaten und Grund; Einstellung `schreiben`:
  `auto` | `immer` | `nie`.
* Die Beutemethode kommt versionsbewusst aus `GetLootMethod()` oder
  `C_PartyInfo.GetLootMethod()` (Zahl, 2 = Plündermeister).
  ⚠️ **Ob Forever überhaupt Plündermeister kennt, ist ungemessen.**

---

## Abgleich (`Abgleich.lua`)

Addon-Nachrichten, Präfix `FSHARE`, Takt 0,25 s (Blizzards Drosselung).

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
fremde Daten annehmen. `/fs abgleich status` zeigt den Rohnamen des letzten
Absenders und seine Zuordnung.

### ⚠️ Ungemessen im Spiel

* **Absendername** in `CHAT_MSG_ADDON` bei Nachnamen: `Kern.GleicherSpieler`
  fängt „mit/ohne Nachname" und „mit/ohne Realm" ab; ob Forever noch anders
  formatiert, zeigt erst `/fs abgleich status`.
* **Einschränkung von Addon-Nachrichten in Instanzen/Kampf** (Mainline-Linie
  seit 12.0). Gedrosselte oder gesperrte Nachrichten werden bis zu sechsmal
  später wiederholt.
* `UnitIsInMyGuild`: fehlt es, gilt der Absender als Mitglied.

---

## Gargul

* **Würfelbereiche:** Gargul bringt MS 1–100 und OS 1–99 mit. Die Gilde
  würfelt **100 / 50**. `Quelle.GargulBereiche()` prüft, `…Setzen()` stellt
  `RollTracking.Brackets` um (Einstellung, kein Eingriff in den Code);
  `/fs bereiche`. Sonst ordnet Gargul die 50er-Würfe nicht ein.
* **Ereignisse:** `GL.ITEM_AWARDED` → eintragen; `GL.ITEM_AWARD_EDITED` →
  Gewinner/Haupt-Zweit nachziehen; `GL.ITEM_UNAWARDED` → `zurueck` setzen
  (nicht löschen, sonst brächte der Abgleich es zurück) und verteilen.
* Kam die Beutemeldung vor Gargul, wird der Eintrag **berichtigt**, nicht
  verdoppelt (`herkunft = "gargul"`).
* **Gargul 8.0.1 (03.10.2026) ist für Forever offiziell veröffentlicht**, kennt aber
  weiterhin keine Nachnamen (kein Treffer für „surname"). Lizenz bleibt
  **All Rights Reserved**: nur Ereignisse und die Historie lesen,
  **keinen Code übernehmen**, nichts davon ins Repo.

---

## Gruppen und Kader (`Gruppen.lua`, Modell vom 14.10.2026)

Entscheid des Gildenleiters: **so wenige Handgriffe wie möglich.** Es gibt nur noch **eine** Art Gruppe
(vorher Kader und Raidgruppe).

* Eine Gruppe ist eine **Beschriftung** („40er", „10er") und ein **Kader** (Namensliste). Jede Vergabe trägt
  die beim Eintragen aktive Gruppe; die Ansicht lässt sich auf eine Gruppe einschränken.
* ⭐ **In einer Gruppe zeigt die Übersicht nur die Spieler, die bei dir sind** (`Kern.Bilanz(..., pflicht, nur)`),
  auch mit null Vergaben; die Summe zählt nur sie. Ein Name der Historie ohne Nachnamen wird dem vollen Namen
  der Gruppe zugeschlagen (eine Zeile). Der Knopf *Alle Spieler zeigen* im Fuß hebt das auf. **Ohne Gruppe**
  stehen alle Spieler der Historie plus der Kader der aktiven Gruppe in der Liste.
* ⭐ **Member sync** (`Gruppen.Synchronisieren`, vorher „Fill"; Entscheid 14.10.2026 „es geht nach
  vordefinierten Gildenrängen, also ist Entfernen sicher"): Sind **Gildenränge** gewählt, ist der Kader **genau
  deren Mitglieder** — Neue kommen dazu, Ausgetretene und Rangwechsler fallen weg. Quelle: Forever
  `C_Club.GetClubMembers`/`GetMemberInfo`, sonst `GetGuildRosterInfo`. Zwei Listen je Gruppe: `kader` (vom
  Sync verwaltet) und `extra` (von Hand, **bleibt immer**); sichtbar ist die Vereinigung. Ältere Stände mit nur
  `kader` gelten beim ersten Zugriff als `extra` (nichts geht verloren). **Ohne Ränge** nimmt es nur
  Gildenmitglieder der Gruppe auf (nach `extra`), **ohne Gruppe tut es nichts**.
  ⚠️ Schutz vor halb geladener Gildenliste: niemand in den gewählten Rängen → nichts ändern; auffällig viele
  Abgänge (> 40 % und > 4 bei ≥ 10 im Kader) → erst nachfragen (gleiche Taste nochmal binnen 2 min), beim
  automatischen Lauf (20 s nach dem Anmelden, je Gruppe abschaltbar) wird dann nur hinzugefügt. Von Hand
  entfernen: Feld „Name entfernen"; wer nur durch einen Rang im Kader steht, kommt beim nächsten Sync zurück.
* ✅ **Gemessen** (`/fs gilde`, 14.10.2026): Die Gildenliste liefert **Vor- und Nachname plus Gildenrang**.
  `Kern.GleicherSpieler` fängt trotzdem Kurz- und Langform ab.
* Alte Einträge mit `modus = "raid"` werden wie ein Kader gelesen; das Feld wird ignoriert.
* Der **Abgleich läuft von selbst** (Einstellung `autoAbgleich`, Standard an): Merkt Leiter oder Plündermeister
  eine Abweichung, startet er nach 4 s einen Abgleich, höchstens alle 2 Minuten. Aus: nur Hinweisfenster.
  So bekommen alle, die später wieder mit dir in einer Gruppe stehen, deine Daten und du ihre.

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
eine Zeile zu viel nur lästig.** `/fs filter 4` hebt die Schwelle. Dazu der
**Ort** (`raid` | `instanz` | `überall`) und `filter wurf` (nur
Ausgewürfeltes, Standard aus).

### Das Einstellungsfenster sieht aus wie das von KaosUI

Eigenes Fenster neben der Übersicht (`/fs einstellungen` oder Knopf *Einstellungen*): Kopf mit
Logo und Versionskästchen, Seitenleiste, Karten mit Zeilen, Fußleiste. Petrol `#1f8f80` als Akzent,
Inter Medium als Schrift (**SIL OFL**, `Media/Fonts/LICENSE-Inter.txt`), Symbole aus Tabler Icons
(**MIT**, `Media/Icons/LICENSE-Tabler.txt`). Beides stammt aus KaosUI, **die Bausteine sind aber neu
geschrieben** (`Stil.lua`) — Fairshare hängt nicht von KaosUI ab.

Eine Zeile ist eine Datentabelle (`art` = schalter | segment | knopf | eingabe | info, dazu
`label`, `beschr`, `get`/`set`); Texte und Zustand setzt `update()`, die Höhen rechnet
`kartenMessen`. **Keine Anker zwischen Zeilen** — dieselbe Lehre wie beim KaosUI-Umbau. Neue Option =
eine Zeile in `seiteErfassung`/`seiteGargul`/`seiteGruppen`.

⚠️ Die Optik ist nur im Spiel prüfbar; `tests/szenarien.py` prüft, dass jede Zeile, jeder Knopf und
jede Seite ohne Fehler läuft und speichert.

### ⭐ Zahlen über 2^31 nie mit `%d` formatieren

Prüfsummen reichen bis 2^32. `string.format("%d", 3000000000)` lieferte in der Simulation (Lua mit 32-Bit-`long`)
**-2147483648**; der Abgleich verlor dadurch ganze Tage, weil die Gegenseite die Zahl mit Minuszeichen nicht
parste und der Wert zudem für verschiedene Mengen gleich wurde. Wie WoW sich verhält, ist ungemessen — also
überall `%.0f` (Übertragung) oder `tostring`. Test: `testGrosseSummen`. Gefunden hat es erst das Szenario
„Automatisch abgleichen" mit zwölf Einträgen.

### Sprache (seit 14.10.2026)

Das Addon spricht die Sprache des Clients: **deDE = Deutsch, jeder andere Client = Englisch.** Wie bei
KaosUI sind die **deutschen Sätze die Schlüssel** (`L["Wer schreibt mit"]`); `Locale.lua` hält die englische
Fassung, auf einem deutschen Client liefert `L[]` den Schlüssel selbst. Befehlsworte gelten deutsch **und**
englisch (`/fs history`, `settings`, `list`, `sync`, `group`, `brackets`, `role`, `state`, `patterns`,
`appearance`). Datumsformate sind selbst Schlüssel (`L["%d.%m.%Y"]` → `%m/%d/%Y`).

⚠️ Jeder neue Text braucht einen Eintrag. `python tests/texte.py --streng` prüft, dass kein Schlüssel fehlt,
keiner übrig ist, die Platzhalter (`%d`, `%s`) übereinstimmen und keine deutsche Zeichenkette ohne `L[]` im
Code steht (erlaubte Ausnahmen: Befehlsworte, interne Gründe, Beispieldaten, Entwicklerdiagnose — Liste
`ERLAUBT` im Skript). Satzteile **nicht** aus Bruchstücken zusammensetzen, sondern ganze Sätze mit Platzhaltern
übersetzen. Farbcodes stehen im Schlüssel.

### Texte, die der Client nicht zeichnet (14.10.2026)

Beim ersten Start mit der neuen Schriftdatei zeigten viele Textfelder im Einstellungsfenster **leeren Text,
obwohl Layout und Höhen stimmten** (Screenshots). Gegenmittel, alle zusammen eingebaut, weil die genaue
Ursache nicht belegt ist: (1) Textfelder mit Schriftvorlage `GameFontNormal` anlegen und **dann** Inter setzen,
nie ein nacktes Feld mit der neuen Datei (so macht es KaosUI); (2) `SetFont` auswerten, bei `false` auf
`STANDARD_TEXT_FONT`; (3) umbrechende Texte nie mit Breite 0 setzen; (4) die Seitenframes bekommen die echte
Höhe statt 1; (5) `Stil.Auffrischen()` setzt nach dem ersten Zeigen alle Texte leer und wieder neu
(KaosUI-Lehre: erst ein geänderter Text zeichnet). **Diagnose: `/fs darstellung`** (Schrift, Größe, Farbe,
Sichtbarkeit der ersten Zeilen). Hilft nichts davon, mit dieser Ausgabe weitersuchen.

### Fenstergröße und Ebenen (14.10.2026)

Beide Fenster sind in der Größe verstellbar (Griff unten rechts, `Stil.Verstellbar`); Größe und Lage liegen in
`FairshareDB.fenster.uebersicht` / `.einstellungen` und werden auf die Grenzen gebracht. Der Anker ist **oben
links**, nie die Mitte (sonst springt das Fenster beim Ziehen). Die Übersicht rechnet Zeilenzahl (bis 40) und
Spaltenbreiten aus der Fenstergröße; die Einstellungen legen die Karten bei jeder Breite neu.

⭐ **Das Einstellungsfenster liegt immer über der Übersicht**: Stufe `FULLSCREEN_DIALOG` und Ebene 200 gegen
`DIALOG`/20. Nur eine andere Ebene genügt nicht — die Unterelemente beider Fenster hatten gleiche Stufen und
mischten sich beim Überlappen (Screenshot 14.10.). Die Stufe muss **vor** dem Anlegen der Kinder gesetzt werden.

### Die Übersicht kommt ohne Bibliotheken aus

Fester Satz Zeilen plus Mausrad-Versatz. Ein Teil weniger, das beim nächsten
Patch bricht. Es hält keinen Zustand über die Sitzung hinaus und liest bei
jedem Aufbau frisch.

---

## Arbeitsweise

```
python luacheck.py Fairshare/*.lua     # Blockstruktur, echter Tokenizer
pip install lupa                          # einmalig
python tests/rechenkern.py                # Kern + Tests.lua in echtem Lua 5.1
python tests/szenarien.py                 # mehrere virtuelle Clients, auch ein englischer Client
python tests/texte.py --streng            # Übersetzung vollständig?
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

## Client

**Nur WoW Forever** (Beta, `_classic_beta_`, Mainline-Unterbau 12.1.5) —
Entscheid des Gildenleiters, 14.10.2026. TBC Anniversary braucht das Addon
nicht, `deploy.ps1` rollt dort nicht mehr aus.

```
## Interface: 16001, 120100, 120105
```

Gargul ist für die Forever-Beta vom Entwickler **offiziell veröffentlicht**
(8.0.1, `Gargul_Camelot.toc`). **Dieses Addon darf keine fehlenden Globals
selbst definieren** — Garguls Weichen prüfen `Global or C_Namespace.Name` und
nähmen sonst den falschen Weg.

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
