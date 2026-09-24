# Loot-Ordnung → WoW Forever: Übergabe

**Stand 24.09.2026.** Diese Datei ist der Einstieg für einen Agenten, der das
Addon von TBC Anniversary nach Forever bringt. Sie ergänzt `AGENTS.md` (dort
stehen alle Regel-Entscheidungen mit Begründung) und ersetzt sie nicht.

> ⚠️ **Das Addon hat noch nie auf Forever gelaufen.** Es ist gegen TBC
> Anniversary gebaut (`## Interface: 20504`) und dort erprobt. Forever läuft im
> Mainline-Codebaum — Classic-Addons starten dort nicht.

---

## 1. Was das Addon ist, in fünf Sätzen

Die Gilde **Resurrected** (Thunderstrike EU) ersetzt ihr Loot Council durch ein
Rechensystem: **`Prio = Einsatz ÷ Rüstwert`** (EPGP-Erbe, aber ein Verhältnis,
keine Währung). **Einsatz** wächst durch Mitraiden, **Rüstwert** durch erhaltene
Gegenstände — berechnet aus *Gegenstandsstufe × Platzfaktor*, also **ohne
BIS-Liste und ohne gepflegte Tabelle**, damit es am Tag 1 einer unbekannten
Erweiterung funktioniert. Beide Größen verfallen 10 % pro Woche.

**Nur die Raidleitung braucht das Addon** — Forever fährt 10er und 20er, also
mehrere Gruppen; ein Addon für alle wäre ein Dauerproblem. Möglich durch drei
zusammenhängende Entscheidungen:

1. **Bedarf wird gewürfelt** (`/rnd 100` Haupt-, `/rnd 50` Zweitbedarf) statt
   geklickt — das kann jeder Client, auch Fremde. *Noch nicht gebaut.*
2. **Keine Ausrüstung auslesen, kein Inspect.** Der Rüstwert ist ein **Konto,
   keine Messung**.
3. **Die Konten liegen in der Offiziersnotiz.** Der Server synchronisiert sie von
   selbst → **kein Sync-Protokoll, keine Absprache zwischen den Raidleitern.**
   Dasselbe Verfahren nutzen EPGP und CEPGP seit Jahren.

Das Regelwerk ist fertig und abgenommen: `loot-ordnung.html` (§§ 1–10 + Anhänge).
⚠️ Diese Datei ist zugleich die Quelle eines veröffentlichten Artifacts —
wer sie ändert, muss neu publizieren, **mit der bestehenden URL**.
Alle Zahlen im Dokument kommen aus `berechnungen.py`; ändert sich eine
Stellschraube, muss sie in `Kern.lua` **und** dort nachgezogen werden.

---

## 2. Stand des Codes

`LootOrdnung/` — sechs Dateien, Ladereihenfolge laut TOC:

| Datei | Zweck | WoW-API? |
|---|---|---|
| `Kern.lua` | reines Rechnen: Prio, Verfall, Einsatz, Rüstwert, Rangfolge | **nein** |
| `Notiz.lua` | Notizformat `LO:Einsatz,Rüstwert,Woche,Deckel,Stücke,Gebucht` | **nein** |
| `Gilde.lua` | Notizen lesen + gedrosselt schreiben, Rangauswahl | ja |
| `Raid.lua` | Abend erfassen (`ENCOUNTER_END`), Anwesenheit, Buchen | ja |
| `Tests.lua` | ~95 Prüfungen, läuft per `/lo test` und offline | **nein** |
| `Befehle.lua` | `/lo`-Dispatcher | ja |

**Läuft und ist im Anniversary-Client erprobt:** Rechenkern, Konten in der
Offiziersnotiz (Lesen *und* Schreiben in voller Länge), Rangauswahl,
Raidabend-Erfassung über `ENCOUNTER_END`, Buchung mit Sperre gegen mehrere
Raidleiter, Sicherung + Wiederherstellung.

**Fehlt noch: die Vergabe.** Würfe mitlesen, nach Kategorie und Prio sortieren,
Rüstwert buchen. Sie war bewusst zurückgestellt, weil unklar war, ob Forever
Master Loot hat — **das ist jetzt geklärt, siehe § 4.**

**Bewusst offen:** Raids mit Gästen. Der Gildenleiter hat dafür noch keine faire
Lösung und will sie nicht erzwingen.

### Befehle

`/lo` ohne Argument zeigt alles. Wichtig für den Einstieg:

| Befehl | Zweck |
|---|---|
| `/lo test` | Selbsttests des Rechenkerns |
| `/lo bausteine` | **Diagnose:** welche Dateien sind geladen |
| `/lo wer` | **Diagnose:** wer zählt gerade als anwesend, mit Rohwerten |
| `/lo rechte` | darf ich Offiziersnotizen sehen und schreiben |
| `/lo raenge` / `/lo rang N` | Ränge auswählen, die teilnehmen |
| `/lo sichern` / `/lo zurueck` | Notizen sichern / wiederherstellen |
| `/lo start` | Konten anlegen (zeigt erst an, `jetzt` führt aus) |
| `/lo nullen` | alle Konten auf Anfang (zeigt erst an) |
| `/lo auto` | Bosse automatisch erkennen |
| `/lo boss <name>` | Bosskampf von Hand buchen |
| `/lo abend` | Stand; `jetzt` schreibt, `neu` verwirft |
| `/lo abend nachtragen` | zuletzt übersprungene Konten nachbuchen |
| `/lo abend zwingend` | Doppelbuchungssperre umgehen |

**⭐ Destruktive Befehle zeigen erst an und brauchen `jetzt`.**

### Arbeiten am Code

```
python luacheck.py LootOrdnung/*.lua     # Blockstruktur, echter Tokenizer
.\deploy-tbc.ps1                          # nach _anniversary_ ausrollen
```

⚠️ **Es gibt kein Lua auf dem Rechner** — die Tests laufen nur im Spiel über
`/lo test`. `luacheck.py` prüft **Struktur, keine Semantik**; ein `nil`-Zugriff
findet er nicht.

---

## 3. Die drei Denkfehler, die immer wiederkommen

Diese drei sind im Gespräch mit dem Gildenleiter mehrfach aufgetreten und stehen
ausführlich in `AGENTS.md`:

1. **Abwesenheit kostet keine Prio.** Der Verfall trifft Einsatz *und*
   Rüstwert — das Verhältnis bleibt gleich. Wer pausiert, verliert Vorsprung,
   nicht Anspruch.
2. **Wer nur eine der beiden Größen setzt, setzt in Wahrheit gar nichts.** Bei
   Neulingen wird die **Prio** gesetzt, nicht Einsatz und Rüstwert einzeln
   (`Kern.StartkontoFuerRaider`). Ein Startwert nur für den Einsatz ergab
   versehentlich Prio 4,00 statt 0,25.
3. **Der Rüstwert misst Ausrüstung, nicht Konkurrenz.** Die Regel „was niemand
   will, kostet nichts" ist **verworfen** — eine Nischenwaffe kann das stärkste
   Item im Raid sein.

---

## 4. ✅ Forever-APIs, an Blizzards Quelle belegt

Geprüft am 24.09.2026 gegen **`wow-ui-source`, Zweig `forever`, `70ef1b2`
(1.60.1.69913)** — lokal unter
`Skripte&Codes&Addons\wow-ui-source`.
**Bei jedem Rätsel ZUERST dort nachlesen**, nicht raten.

### Das Fundament hält

`C_GuildInfo.SetNote(guid, note, isPublic)` existiert unverändert
(`GuildInfoDocumentation.lua:389`), ebenso `CanEditOfficerNote` (`:20`) und
`CanViewOfficerNote` (`:38`). **Die Offiziersnotiz als Speicher funktioniert
also weiter** — die tragende Architekturentscheidung überlebt den Umzug.

⚠️ `SetNote` trägt `HasRestrictions = true` und
`SecretArguments = "AllowedWhenUntainted"`: aufrufbar, solange der eigene
Codepfad nicht tainted ist. Nie über einen Blizzard-Frame aufrufen.

### Der Rüstwert ist berechenbar

Die **Globals** `GetItemInfo` und `GetItemInfoInstant` fehlen in Forever — die
**namespaced Fassungen sind da** (`ItemDocumentation.lua`, `Namespace = "C_Item"`):

* `C_Item.GetItemInfoInstant(link)` → u. a. **`itemEquipLoc`** (`:659`), also der
  `INVTYPE_*`-String für `Kern.platzfaktoren`.
* `C_Item.GetDetailedItemLevelInfo(link)` → Gegenstandsstufe (`:354`).
* `C_Item.GetItemInventoryTypeByID` (`:726`) als Alternative.

Damit läuft `Kern.RuestwertVon(platz, stufe)` in Forever ohne inhaltliche
Änderung — **nur der Aufruf muss über einen Wrapper.**

### Master Loot gibt es

`Enum.LootMethod` hat **`Masterlooter = 2`**
(`LootConstantsDocumentation.lua:15`), und `C_PartyInfo.GetLootMethod()` liefert
`method, masterLootPartyID, masterLooterRaidID`
(`PartyInfoDocumentation.lua:287`). ⭐ **Damit ist die zurückgestellte Frage
beantwortbar** — ob die Server ML in Raids *erlauben*, ist im Spiel zu messen,
die API ist jedenfalls da. Neu und für die Vergabe interessant: `C_LootFrame`,
`C_AutoLoot`.

### Die Schlachtzugsliste stimmt wie angenommen

`GetRaidRosterInfo(i)` liefert in Forever dieselben elf Werte, belegt durch
Blizzards eigenen Aufruf in
`Blizzard_CompactRaidFrames/Blizzard_CompactRaidFrameContainer.lua:395`:

```lua
local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i);
```

⭐ **Das bestätigt den Anwesenheitsfilter** (`Kern.IstDabei` liest Feld 7 `zone`
und Feld 8 `online`) — die offene Annahme aus der TBC-Entwicklung ist damit an
der Quelle belegt. `GetNumGuildMembers` benutzt Blizzard selbst
(`MailFrame.lua:115`). `ENCOUNTER_END` ist dokumentiert
(`EncounterInfoDocumentation.lua:40`).

### Ein moderner Ersatzweg zum Roster

`GetGuildRosterInfo` taucht in Blizzards eigenem Forever-Code **nicht mehr auf**
(das beweist nicht, dass es fehlt — Legacy-Globals werden oft nicht benutzt und
existieren doch). Falls es weg ist, gibt es einen vollständigen Ersatz:

```lua
local clubId = C_Club.GetGuildClubId()                -- ClubDocumentation.lua:500
local ids    = C_Club.GetClubMembers(clubId)          -- :433
local info   = C_Club.GetMemberInfo(clubId, ids[i])   -- :611
-- info.guid, info.name, info.officerNote, info.memberNote, info.role, info.level
```

`ClubMemberInfo` führt **`officerNote`** und **`guid`** (`:1818`, `:1821`) — genau
die beiden Felder, die `Gilde.lua` braucht.

⚠️ `C_Club.GetMemberInfo` trägt **`SecretInChatMessagingLockdown = true`**: im
Lockdown kommen die Felder als *Secret* zurück und sind in Lua nicht parsbar.
`officerNote` hat **kein** `NeverSecret`. **Das ist das größte Restrisiko** —
siehe Messplan.

---

## 5. ⚠️ Forever-Regeln, die dieses Addon direkt treffen

Vollständig in der Nutzer-Memory `wow-forever-classic-plus`; hier nur, was
Loot-Ordnung betrifft.

### 🔴 Blocker: SavedVariables werden nicht zurückgelesen

**Bekannter Client-Fehler in der Beta** (gemeldet, extern bestätigt durch
`github.com/Thunderz96/forever-addon-kit`): SavedVariables werden *geschrieben*,
beim Start aber **nicht geladen**.

Für dieses Addon ist das schwerwiegend: `LootOrdnungDB` hält den **laufenden
Raidabend**, die **Rangauswahl**, die **Automatik-Einstellung** und die
**Sicherung der Notizen**. Ohne Rücklesen ist nach jedem `/reload` alles weg —
und `/reload` passiert bei jedem Addon-Test.

Zwei erprobte Umgehungen aus KaosUI-Forever, beide übernehmbar:

1. **CVar-Speicher** (`kuiDB_*` in `KaosUI/Profiles.lua`) — übersteht `/reload`,
   keinen Neustart. Für Rangauswahl und Automatik ausreichend.
2. **`sv-bridge-forever.ps1`** — kopiert die gespeicherte Datei als
   `SavedSeed.lua` in den Addon-Ordner, die TOC lädt sie als erstes.

⭐ **Der Abend ist der kritische Teil.** Ein Ansatz, der zum Systemdesign passt:
Die Konten liegen ohnehin schon serverseitig in der Notiz — der Abend könnte
**nach jedem Boss** geschrieben werden statt gesammelt am Ende. Das kostet
Schreibvorgänge (Drossel `SCHREIBPAUSE = 0.35`), macht aber den lokalen Speicher
entbehrlich. **Diese Entscheidung gehört dem Gildenleiter, nicht dem Agenten** —
sie ändert den Schreibrhythmus, der in `AGENTS.md` begründet ist.

### Weitere harte Regeln

* **Version an APIs erkennen, nie an der Nummer.** 1.60.1 → Interface 16001
  *sieht* classic-artig aus, der Unterbau ist Mainline 12.1.5. Nie nach dem SPIEL
  fragen, sondern nach der FÄHIGKEIT (`if C_Item and C_Item.GetItemInfoInstant`,
  nicht `if isTBC`).
* **`COMBAT_LOG_EVENT_UNFILTERED` ist gesperrt.** Trifft uns nicht — wir lesen
  `ENCOUNTER_END`. Aber: kein Umweg über das Kampflog planen.
* **`RegisterEvent` auf Blizzard-Frames ist verboten** (`ADDON_ACTION_FORBIDDEN`).
  Eigene Frames sind frei; das Addon benutzt schon ausschließlich eigene.
* **Eigene Secure-Snippets sind tot** (`loadstring_untainted = nil`, TOC-Fehler
  bei Blizzard). Betrifft uns nicht — kein Secure-Code im Addon.
* **Secrets:** geheim sind u. a. `UnitHealth`, Bedrohung, `UnitStat`,
  `UnitIsPlayer`/`UnitExists` im Kampf, **Chat-Texte unter Taint** — und jede
  Ableitung davon. In Lua verboten: testen, vergleichen, rechnen,
  `string.format`, verketten. `== nil` geht. Beim **Holen** entschärfen, nicht
  beim Benutzen: falsch ist `if v <= 0 or issecretvalue(v)`, weil der Vergleich
  links zuerst stirbt.
* **Taint:** nie eine Blizzard-Funktion ersetzen, nur `hooksecurefunc`.
* **Fehlende Globals** (in KaosUI in `Compat.lua` gekapselt):
  `GetItemInfo`, `GetItemInfoInstant`, `GetItemCount`, `GetCoinTextureString`,
  `GetTalentInfo`, `SecureAuraHeaderTemplate`, `OnTooltipSet*`.

### TOC und Ausrollen

Vorlage ist `KaosUI-Forever` — **eigener Addon-Ordner**, nicht die TBC-Fassung
umbiegen:

```
## Interface: 16001, 120100, 120105
```

Dazu ein eigenes `deploy-forever.ps1` nach
`World of Warcraft\_classic_beta_\Interface\AddOns\`.
**Lua-Änderung = `/reload`; TOC-Änderung oder neue Datei = Client-Neustart.**

---

## 6. 🎯 Messplan für den ersten Lauf in Forever

In dieser Reihenfolge, weil jeder Punkt den nächsten voraussetzt. **Belegen statt
vermuten** — Messung im Spiel oder Blizzard-Quelle mit `Datei:Zeile`.

1. **Lädt es überhaupt?** TOC bauen, ausrollen, `/lo bausteine`. Fehlt ein
   Baustein, ist die Datei beim Laden gestorben.
2. **🔴 Ist die Offiziersnotiz lesbar und nicht geheim?** `/lo rechte`, dann
   `/lo notiz`. Kommt der Text als Secret zurück, ist das **die Architekturfrage
   des Projekts** — dann erst klären, ob es außerhalb des Lockdown geht, bevor
   irgendetwas anderes gebaut wird.
3. **Existiert `GetGuildRosterInfo` noch?** Wenn nein, `Gilde.Lesen()` auf den
   `C_Club`-Weg aus § 4 umstellen. Der Rest des Addons merkt davon nichts —
   `Gilde.lua` ist die einzige Brücke zum Client.
4. **Schreiben in voller Länge.** `/lo sichern`, dann eine Testnotiz. Am
   Anniversary-Client kamen 30 Zeichen ungekürzt an (`MAXLAENGE = 31`) — **in
   Forever neu messen**, das Format hat keinen Spielraum.
5. **`ENCOUNTER_END` in einem echten Raid.** Liefert es encounterID, Name und
   Erfolg? `/lo auto`, dann `/lo abend`.
6. **`/lo wer` gegen die Schlachtzugsliste.** Prüft Feld 7/8 und damit den
   Anwesenheitsfilter. Eine Notbremse greift, falls der Filter *alle* aussiebt.
7. **Lootmethode:** `print(C_PartyInfo.GetLootMethod())` in einem Raid. Gibt es
   `Enum.LootMethod.Masterlooter`, wird die Vergabe gebaut — sonst läuft sie über
   Gruppenloot und Handeln.
8. **`RANDOM_ROLL_RESULT`?** Im Forever-Quellbaum **nicht gefunden**. Falls es
   das Ereignis nicht gibt, bleibt `CHAT_MSG_SYSTEM` — ⚠️ dort drohen geheime
   Chat-Texte unter Taint. Nie den deutschen Text hartkodieren, immer ein Muster.
9. **Die offenen Regelgrößen eichen:** Eichwert `K = 26`, Mindest-Rüstwert 100,
   Raidgrößen-Ausgleich 10er/20er. Stehen als offene Punkte in
   `loot-ordnung.html` und sind erst mit echten Gegenstandsstufen entscheidbar.

---

## 7. Die Fallen, die schon Zeit gekostet haben

Jede davon ist real eingetreten. Sie sind in `AGENTS.md` ausführlich begründet.

* **⭐ SavedVariables sind eine Versionsgrenze.** Ein umbenanntes Feld
  (`namen` → `teilnahme`) ließ `/lo abend` auf ein `nil` laufen, weil ein Abend
  aus der alten Fassung dort überlebt hatte. `Raid.Nachziehen()` holt das nach.
  **Wer ein Feld in `LootOrdnungDB` umbenennt, schreibt im selben Zug den
  Nachzieh-Pfad.** In `Notiz.lua` liest das Addon deshalb drei Generationen des
  Notizformats.
* **⭐ WoW verschluckt Addon-Fehler stumm**, solange `scriptErrors` aus ist — und
  das ist die Voreinstellung. Der Befehl tut dann *scheinbar überhaupt nichts*.
  Der Dispatcher läuft darum über `pcall` und druckt die Meldung in den Chat.
  **Das nie rückbauen.** Ein stiller Fehler ist schlimmer als ein lauter.
* **⭐ Nie über den Roster-Index adressieren.** Zwei Lesetests auf
  `GetGuildRosterInfo(1)` lieferten **verschiedene Spieler**, weil sich die
  Sortierung ändert. Immer Name oder GUID; `SetNote` nimmt ohnehin eine GUID.
* **⭐ Erwartungswerte aus dem Regelwerk ableiten, nie aus der Funktion
  daneben.** `Abendsatz(0)` gab den Bonus zurück, obwohl § 2 sagt, dass bei
  ausgefallenem Raid niemand etwas bekommt — **der Test hatte es durchgelassen,
  weil der Sollwert aus der Implementierung stammte.** Die Gruppe
  `testGegenModell` prüft deshalb gegen `berechnungen.py`.
* **Idempotenz ist das Bauprinzip, nicht Absprache.** Der Wochenstempel macht den
  Verfall idempotent, der Buchungsstempel die Abendbuchung. Bei mehreren
  Raidgruppen ließe sonst jeder Leiter den Verfall erneut laufen.
* **Bewusst keine Gruppenkennung.** Anführer, Teilnehmerprüfsumme und Instanz
  haben alle eine Lücke, und **ihr Fehlerfall wäre die stille Doppelbuchung**.
  Die Zeitsperre irrt sichtbar: Sie sperrt zu viel, nennt die Namen, und
  `/lo abend nachtragen` bucht sie nach. *Falsch gesperrt fällt auf, falsch
  gebucht nicht.*
* **Ein Filter darf einen Abend verkleinern, niemals auslöschen.** Siebt
  `Kern.IstDabei` alle aus, stimmt die Annahme über die API nicht — dann zählt
  die ungefilterte Liste.
* **Rangauswahl statt Schwellenwert.** „Alle Ränge bis Index N" zog
  Offizierstwinks mit, weil die einen hohen Rang tragen.
* **Umbauen erst nach Rückfrage.** Zwischendurch war auf „nur besiegte Bosse
  zählen" umgebaut; der Gildenleiter hat zurückgenommen. Es bleibt bei **jedem
  gepullten Boss**, der Erfolg dient nur der Anzeige.

### Werkzeug-Fallen auf diesem Rechner

* **Backslashes nicht über Bash-Heredocs** — Bash halbiert sie. Dateien mit `\`
  über das Datei-Schreibwerkzeug anlegen.
* **Umlaute:** nutzersichtbare Texte mit `ä/ö/ü/ß`, UTF-8 **ohne BOM**.
  Patch-Skripte als Datei mit echten Umlauten schreiben, nicht als Heredoc.
* **Zeilenenden je Datei beibehalten** (vorher `file <datei>`).
* Der PowerShell-Sicherheitsfilter blockt `Remove-Item` in Befehlen mit
  Regex-Text wie `\.md$`.

---

## 8. Zusammenarbeit

**Repo:** `github.com/Kaos-WoW/WoW-Addon`, Branch `main`.
**Mehrere Schreiber** — neben dem Gildenleiter der Entwickler `xqp`. **Vor jedem
Push `git fetch`.** Letzter Commit: `c1ebc11`.

Für den Zwei-Agenten-Betrieb gilt das Muster aus dem KaosUI-Projekt:
Der Antigravity-Agent protokolliert in `CHANGES_LOG.md`, die Dateibelegung läuft
über `WORKBOARD.md`, damit nicht zwei gleichzeitig dieselbe Datei anfassen.
**Beide Dateien gibt es hier noch nicht** — wer anfängt, legt sie an.

**Deutsche Sprache** in Code-Kommentaren, Befehlsausgaben und Dokumentation; die
Funktionsnamen im Addon sind ebenfalls deutsch (`Kern`, `Notiz`, `Gilde`,
`Raid`). Das ist gewollt, nicht Zufall — beibehalten.

**Knapp berichten:** Ergebnisse und Rückfragen, keine Schritt-für-Schritt-Prosa.

**Nicht ohne Rückfrage entscheiden:** alles, was das Regelwerk berührt. Die
§§ sind mit dem Gildenleiter Absatz für Absatz abgestimmt; eine Änderung am Code,
die eine Regel verschiebt, ist eine Änderung am Regelwerk.
