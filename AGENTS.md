# Fairshare — Projektnotizen

Addon für die Gilde **Resurrected** (Thunderstrike EU). Es beantwortet:
**Wer hat über die Wochen wie viele Gegenstände bekommen — und wer bekam
wann was?** Damit der Plündermeister im Moment der Vergabe schnell und
begründet entscheiden kann.

**Name:** Fairshare, Befehl `/fs` (bis 14.10.2026 „Loot-Historie“, `/lh`; der Name sagte zu wenig, das Addon zeichnet
auf, gleicht ab, verwaltet Gruppen). Ordner `Fairshare/`, SavedVariables `FairshareDB`, Nachrichtenpräfix
`FSHARE`. ⚠️ **Der Umzug der gespeicherten Daten** (`LootHistorie.lua` → `Fairshare.lua`, Variable umbenannt)
macht `deploy.ps1` einmalig und **nur bei beendetem WoW** (sonst bricht es ab, ohne etwas zu ändern); die alte
Datei bleibt als Sicherung. Spätere Umbenennungen brauchen denselben Weg.

Stand 14.10.2026, Version 0.1.3 (Testfassung für die Gildenleitung, nicht veröffentlicht). Nur für Forever.

---

## Das Prinzip (seit 14.10.2026)

⭐ **Eigene Historie, ein Schreiber, Abgleich ohne Überschreiben.**

* **Das Addon führt eine eigene Historie** (`FairshareDB.vergaben`,
  Eintrag je Kennung). Es braucht kein anderes Addon.
* **Nur einer zeichnet auf** — Entscheid des Gildenleiters: der
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
| `Rolle.lua` | Gruppe lesen: wer ist Plündermeister/Leiter, zeichne ich auf | ja |
| `Gruppen.lua` | Kader und Raidgruppen | ja |
| `Erfassung.lua` | Chat, Würfe, Einstellungen, Eintragen, Gargul-Vergaben | ja |
| `Abgleich.lua` | Hallo, Live-Meldung, Abgleich, Hinweis-Fenster | ja |
| `Blizzbeute.lua` | Blizzards `C_LootHistory` als zweite Quelle | ja |
| `Wurf.lua` | eigenes Würfelfenster: Haupt (1-100) / OS (1-50) / Passen, Startdialog, `/fs beutetest` | ja |
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

* ⭐ **Ohne Gruppe wird nie aufgezeichnet** (auch nicht bei „immer“; Entscheid 14.10.2026): Das Addon ist für
  Gruppeninhalt da, ein Solo-Fund gehört nicht in die Historie, Fünfer-Instanzen dienen nur dem Erproben des
  Raid-Ablaufs *mit* einer Gruppe. Zentral in `Rolle.IchSchreibe`, daran hängen Chat, Blizzard-Historie und Gargul.
* Bis die Hallo-Meldungen da sind (wenige Sekunden nach dem Beitritt),
  zeichnet zur Not auch der Leiter auf. **Doppelt ist besser als gar nicht**;
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
  würfelt standardmäßig **100 / 50** (jetzt **einstellbar**, siehe „Würfelbereiche einstellbar").
  `Quelle.GargulBereiche()` prüft, `…Setzen()` stellt `RollTracking.Brackets` auf die Bereiche von Fairshare um
  (Einstellung, kein Eingriff in den Code), `…Uebernehmen()` holt MS/OS aus Gargul nach Fairshare; `/fs bereiche`.
  Sonst ordnet Gargul die 50er-Würfe nicht ein.
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

## Eigenes Würfelfenster (`Wurf.lua`, seit 14.10.2026)

Anlass: Gargul ist in der Beta noch verbuggt. Der Plündermeister/Leiter/Assistent startet einen Wurf (`/fs wurf <Link>`,
Knopf *Wurf starten* → Dialog mit Shift-Klick-Feld und der Beute des offenen Beutefensters). Bei **allen** mit Fairshare
geht ein kleines Fenster auf: Gegenstand (Tooltip), Zeitbalken, **Haupt (1-100)**, **OS (1-50)**, **Passen**. Ein Klick
ruft `RandomRoll(1, 100|50)`; die Zahl kommt vom Server als `RANDOM_ROLL_RESULT` und wird wie jeder Wurf in
`Erfassung.Systemmeldung` gelesen (das Addon sendet nie Ergebnisse → nichts zu fälschen). Solange ein Wurf läuft
(+6 s), ordnet `Wurf.AktuellerLink()` jeden Bedarfswurf der Gruppe dem Gegenstand zu — auch von Spielern ohne Addon.
Nachrichten über `Abgleich.Senden(text, vorn)`: `S;<id>;<Sekunden>;<Link>` und `X;<id>`, nur von Leiter/Assistent/
Plündermeister der eigenen Gruppe und Gilde. Dauer: Einstellung `wurfDauer` (Standard 30 s). Die Übersicht öffnet sich
nur beim Leiter (`Erfassung.WurfBeginnt(link, false)` bei den anderen). Der erste Wurf zählt (siehe unten); Haupt vor OS.
Englisch heißt Zweitbedarf **„OS"** (Nutzerwunsch), nicht „Off".

**Offene Wünsche (Nutzer, 14.10.2026, „für die Zukunft"):**
* **Würfelzeit frei wählbar**, länger oder kürzer. Heute: Einstellung `wurfDauer` mit 20/30/45/60 s (Einstellungen →
  Gargul & Abgleich → Würfelfenster, Grenzen 10–120 s in `Wurf.Dauer`). Idee: Feld im Startdialog für diesen einen Wurf.
* **Festlegbar, was ein „Main"- und was ein „OS"-Wurf ist.** Heute fest 1-100 / 1-50 an vier Stellen: `Kern.Bedarfsart`,
  die Knöpfe in `Wurf.lua` (`RandomRoll`, Beschriftung), `Quelle.GargulBereiche`/`SOLL`, Texte. Idee: zwei Einstellungen
  (Obergrenze Haupt, Obergrenze OS), überall daraus lesen; Beschriftungen und Erkennung folgen; Abgleich-Protokoll
  unberührt (die Art steckt im Eintrag, nicht der Bereich).

### Entzaubern und freie Würfelzeit (Nutzerwünsche 14.10.2026)

* ⭐ **Entzaubern** (`Wurf.lua`, Abschnitt „Entzaubern"): Würfelt bis zum Ende der Zeit niemand, öffnet sich beim Starter ein
  Fenster **„Zum Entzaubern vergeben?"** mit den hinterlegten Verzauberern (Einstellungen → *Würfeln & Abgleich* → *Verzauberer*,
  höchstens 8, `FairshareDB.verzauberer`; `/fs verzauberer add Name, Name`, `del Name|Nr`). Wer in der Gruppe ist, steht vorn
  und ist wählbar, der Erste mit hervorgehobenem Knopf. **Vergeben** ist die Bestätigung des Plündermeisters. Dasselbe Fenster
  öffnet sich per Knopf *Entzaubern* im Ergebnis oder `/fs wurf entzaubern [Link]`, auch wenn jemand gewürfelt hat.
* Ausführung wie beim Zuteilen: Beutefenster → `GiveMasterLoot`, Rucksack → vorgemerkter Handel (`vormerken`, Flag
  `entzaubern`), der Plündermeister selbst → nichts zu tun. **Chat-Ansage** „[Gegenstand] wurde zum Entzaubern an X vergeben!"
  (`Erfassung.EntzauberAnsagen`, Schalter `ansagen`): beim Beutefenster sofort, beim Handel erst wenn er durch ist.
* ⚠️ **Keine Beute für den Verzauberer:** Es wird **nichts in die Historie geschrieben** (`handelVerbuchen` übergeht
  Vormerkungen mit `entzaubern`; `Erfassung.EntzauberMerken`/`EntzauberungPruefen` lässt die Beutemeldung „X erhält …" den
  Gegenstand nicht als Vergabe eintragen). Ein Handel, den man **ganz von Hand** an den Verzauberer macht, wird dagegen als
  Vergabe erkannt — dann per *Rückgängig* korrigieren, oder besser den Weg über das Fenster nehmen.
* **Freie Würfelzeit:** Der Startdialog hat ein Feld *Dauer (s)* (5–300). Die gewählte Zeit gilt für diesen Wurf und wird der
  neue Standard (`wurfDauer`); `/fs wurf 45 <Link>` geht auch. Die Voreinstellung 20/30/45/60 bleibt in den Einstellungen.
  Empfänger nehmen bis 300 s an.

### Würfelbereiche einstellbar, Ansage, Abbrechen (Nutzerwünsche 14.10.2026)

* ⭐ **Würfelbereiche einstellbar** (Einstellungen → *Würfeln & Abgleich* → *Würfelbereiche*; `/fs bereiche haupt 1 100`,
  `… zweit 1 50`): `Kern.BEREICHE` (Standard 1-100/1-50) wird von `Erfassung.BereicheAnwenden` aus `FairshareDB.bereiche`
  befüllt (bei `PLAYER_ENTERING_WORLD`, nicht beim Laden der Datei: die gespeicherten Daten sind dann noch nicht da).
  `Kern.Bedarfsart(min, max)` vergleicht damit. Geprüft wird in `Kern.BereicheSetzen` (ganze Zahlen, 1 ≤ min < max ≤ 10000,
  Haupt ≠ Zweit). **Die Bereiche des Leiters gehen mit jedem Wurf mit** (`S;id;Sekunden;h1,h2,z1,z2;Link`; ältere Fassungen
  lesen nur den Link): Alle würfeln und erkennen für die Dauer des Wurfs mit **seinen** Bereichen (nur im Speicher,
  `aktiv.tauschen`), danach gelten wieder die eigenen. Sonst würfelte ein Spieler mit anderer Einstellung falsch.
* ⭐ **Mit Gargul in beide Richtungen**: *In Gargul übernehmen* (`GargulBereicheSetzen`: MS/OS nach den Bereichen von
  Fairshare) und *Aus Gargul übernehmen* (`GargulBereicheUebernehmen`: erster Nicht-OS-Bereich = Haupt, erster OS-Bereich =
  Zweit). Die Seite heißt jetzt **„Würfeln & Abgleich"** (englisch „Roll and Sync").
* **Ansage im Chat** (`Erfassung.Ansagen`, Schalter `ansagen`, Standard an): Nach jeder eingetragenen Vergabe schreibt der
  **Aufzeichner** „[Gegenstand] wurde an X vergeben!" (OS: „… (OS)") in `RAID`/`PARTY`. Nur bei Herkunft `wurf` (Würfelfenster,
  Handel, „Nur eintragen") und bei `chat` **mit Plündermeister** (Zuteilung im Beutefenster); Blizzards Gruppenwürfe und
  Gargul melden selbst.
* **Wurf abbrechen** (`Wurf.Abbrechen`, `/fs wurf abbrechen`, Knopf *Abbrechen* im Würfelfenster, *Wurf verwerfen* im
  Ergebnis): Nachricht `X;id;a`, bei allen schließt das Fenster, **kein Ergebnis**, die Runde wird verworfen
  (`Erfassung.RundeVerwerfen`), die Würfe zählen nirgends. *Beenden* bleibt das normale Ende mit Ergebnis.

### Eine Vergabe beendet den Wurf (Nutzerfund 14.10.2026)

Nach einer Vergabe per **Handel** blieb „Wurf läuft" stehen: Ein Handel liefert keine Beutemeldung, und nur die beendete die
Runde. Jetzt beendet **jedes `Erfassung.Eintragen`** die Runde des Gegenstands und ruft `Wurf.Vergeben(link)` (beendet den
laufenden Wurf bei allen und schließt das Ergebnisfenster); der Klick auf *Zuteilen* beendet die Runde sofort. ⚠️ Das **Ende
eines Wurfs hängt nicht mehr am Fenster** (eigener `ticker`): Wer das Würfelfenster mit dem Kreuz schloss, hatte keinen
`OnUpdate` mehr, der Wurf lief ewig und jeder spätere `/roll` gehörte noch zum alten Gegenstand. Die Zeilen der Übersicht
dienen mehreren Ansichten: der Knopf *Rückgängig* wird in der Spielerliste ausdrücklich versteckt (er überdeckte die Wurfspalte).
⚠️ Lua-Falle: Eine Funktion, die **vor** der `local`-Deklaration einer Variable steht, sieht sie nicht (sie liest dann eine
leere globale); `luacheck.py` meldet das nicht — Variablen, die mehrere Abschnitte teilen, ganz oben deklarieren.

### Mitspieler können nicht würfeln (Nutzerfund 14.10.2026)

„Teilweise können Mitglieder nicht auf Items würfeln, einer konnte einmal, beim zweiten Mal nicht." Gefunden und behoben:

* ⭐ **Neuer Wurf = neue Runde** (`Erfassung.WurfBeginnt` verwirft die alte Runde dieses Gegenstands). Vorher blieb sie stehen,
  wenn derselbe Gegenstand noch einmal verrollt wurde (zwei Stück, oder nach einer Rücknahme): Das Würfelfenster fand den
  alten Wurf des Spielers (`WurfVon`) und sperrte die Knöpfe; der Leiter sah alte Zahlen. Szenario 25 stellt es nach.
* **Gilde wird für Wurfmeldungen nicht mehr verlangt** (`Abgleich.Empfangen` reicht `S`/`X` vor der Gildenprüfung an
  `Wurf.Empfangen`): Spieler aus einer anderen Gilde im Raid bekamen das Fenster nicht, weil der Leiter für sie kein
  Gildenmitglied ist. Geprüft wird weiter, dass der Absender Plündermeister/Leiter/Assistent **ihrer Gruppe** ist.
* ⭐ **Diagnose `/fs wurf status`** (bei dem Spieler, bei dem nichts aufgeht): ob ein Wurf läuft, ob er starten darf, und die
  letzten Wurfmeldungen mit Grund („Absender nicht in der Gruppe erkannt" = Namensproblem mit Nachnamen; „weder Plündermeister
  noch Leiter noch Assistent" = Rollenerkennung; „angenommen"). Kommt gar nichts an: Fassung 0.1.0 (kein Wurffenster) oder die
  Nachricht wurde nicht zugestellt.
* Nicht die Ursache: ob jemand das Item tragen kann. Das Fenster erscheint für alle, `RandomRoll` kennt keine Klassen.

### Vergabe zurücknehmen (Nutzerwunsch 14.10.2026)

Falsch zugeteilt oder der Spieler gibt das Stück zurück: In **Verlauf** und **Spielerdetail** hat jede Zeile den Knopf
**Rückgängig** (zweistufig: „Wirklich?" binnen 8 s); `/fs rueckgaengig` (`undo`) zeigt die letzte Vergabe, `… ja` bestätigt
binnen einer Minute. `Erfassung.Zuruecknehmen(id)` setzt das bestehende Merkmal `zurueck` (der Eintrag bleibt, zählt aber
nicht — Löschen brächte der Abgleich zurück) und verteilt es live. Berechtigt: Plündermeister/Leiter/Assistent; ohne Gruppe
darf man lokal. ⚠️ **Nicht wieder aufhebbar** (das Merkmal wechselt nur von nein auf ja, das macht das Zusammenführen
eindeutig); ein Versehen korrigiert man mit einer neuen Vergabe. Der Gegenstand ist danach wieder frei (neuer Wurf).

⭐ **Zwei Folgen im Abgleich** (beide fand erst Szenario 23): (1) **Die Prüfsumme zählt `zurueck` mit**
(`Kern.Pruefsumme`/`Tagesstand`: Kennung + „!"). Vorher blieb sie bei einer Rücknahme gleich, wer bei der Rücknahme nicht
dabei war, erfuhr sie nie. Darum **Protokollversion 2** (`Abgleich.VERSION`): Stände mit 1 werden nicht verglichen, sonst
gälten sie ewig als abweichend. (2) Die **Unterdrückung doppelter Sendungen** (`S.gesehen`) schlüsselt nach Kennung **und
Zustand** (`gesehenSchluessel`): Die Sendung eines Mitglieds mit dem alten Stand darf die des Leiters mit dem
zurückgenommenen nicht unterdrücken.

### Beute aus dem Rucksack verteilen, Zuteilen (Stufe 2, 14.10.2026)

⭐ **Üblicher Ablauf der Gilde:** Der Plündermeister steckt die Beute selbst ein und lässt sie auf dem Weg zum nächsten Boss
verrollen; verteilt wird per **Handel**. Darum:

* **Startdialog** listet das offene Beutefenster *und* den Rucksack (`taschenListe`): ab der eingestellten Qualität, und
  wenn der Client die Handelsfrist lesen kann (`C_TooltipInfo.GetBagItem` + `BIND_TRADE_TIME_REMAINING`), nur Stücke
  **mit Frist**. Texte können „geheim" sein → nur im `pcall` vergleichen.
* **Eingestecktes zählt nicht** (`Erfassung.Beutemeldung`, Einstellung `pmEingesteckt`, Standard an): Ist man Plündermeister
  (`Rolle.IchBinPluendermeister`) und die Meldung sagt „du erhältst", ist das keine Vergabe. Sonst stünde jedes
  Stück beim Plündermeister.
* **Ergebnisfenster** beim Starter, 1,5 s nach Ende eines Wurfs (`/fs wurf ergebnis` öffnet es wieder): Rangliste wie in der
  Übersicht, je Zeile **Zuteilen**. Je nach Fundort des Gegenstands:
  * *Beutefenster:* `GiveMasterLoot(Platz, Empfänger)` (Empfänger über `GetMasterLootCandidate` nach Namen); eingetragen
    wird über die Beutemeldung „X erhält".
  * *Rucksack:* **Jede Zuteilung wird vorgemerkt** (`FairshareDB.offen`, überlebt Neuladen und Abmelden, verfällt nach
    3 h; `/fs wurf offen`, `… offen leeren`) und `InitiateTrade(unit)` versucht. Klappt der Handel nicht (Gewinner zu
    weit weg, offline, nicht mehr in der Gruppe), bleibt die Vormerkung: Bei **jedem späteren Handel mit genau diesem
    Spieler** (`TRADE_SHOW`, Partner über `GetUnitName("NPC")`) legt das Addon den Gegenstand selbst ein (bis 6 Plätze).
    **Bestätigen tut nie das Addon.**
  * *Handel von Hand* (Nutzerfund 14.10.2026, „trackt den manuellen Handel nicht"): Bei `TRADE_SHOW` merkt sich das Addon,
    wie viele Stücke je Nummer im Rucksack liegen und welche eine Handelsfrist tragen; `TRADE_PLAYER_ITEM_CHANGED`/
    `TRADE_ACCEPT_UPDATE` lesen die eigenen Handelsplätze (`GetTradePlayerItemLink`). Nach `TRADE_CLOSED` (+1,5 s): ist
    die Zahl im Rucksack gesunken, war es ein Handel → eingetragen, wenn (a) eine Vormerkung für Partner und Gegenstand
    besteht (Art und Wurf daraus), (b) ein Wurf des Partners für diesen Gegenstand bekannt ist (`Erfassung.WurfVon`:
    Art aus dem Wurf) oder (c) das Stück eine Handelsfrist hat und kein Wurf bekannt ist (Hauptbedarf, mit Hinweis).
    **Stücke ohne Handelsfrist und abgebrochene Handel werden nie eingetragen.** Ohne lesbare Handelsfrist
    (kein `C_TooltipInfo`) entfällt (c).
  * *Nicht auffindbar oder man behält ihn selbst:* Knopf **Nur eintragen**.
* ⚠️ Ungemessen im Spiel: `InitiateTrade`/`ClickTradeButton` aus dem Addon in Forever, der Tooltip-Text der Handelsfrist,
  `GiveMasterLoot`. `/fs beutetest` (nur lesen) prüft Letzteres bei offenem Beutefenster. `/fs rolle` zeigt in Forever
  einen Plündermeister an (Nutzer, 14.10.2026).

---

## Wurfanzeige (Übersicht während eines Wurfs, seit 14.10.2026)

Drei Quellen füllen dieselbe Anzeige (`Quelle.Wurf()`), jede liefert `Wuerfe`, **`Arten`** (`haupt`/`zweit`), `namen`, `link`:

* **Gargul** (`RollOff.CurrentRollOff.Rolls`): die Art kommt aus dem Wurfbereich (`Kern.Bedarfsart`: 1-100 Haupt, 1-50
  Zweit), hilfsweise aus dem Bereichsnamen („MS"/„OS"). Wer beides wirft, zählt als Haupt.
* **Blizzards Würfelfenster** (Bedarf/Gier, Gruppenbeute) — Ergebnis des ersten Livetests: *öffnete das Fenster nicht*.
  Jetzt: `START_LOOT_ROLL` öffnet es (`Erfassung.WurfBeginnt`, Gegenstand über `GetLootRollItemLink`), die
  Chatmeldungen kommen aus den GlobalStrings `LOOT_ROLL_ROLLED_NEED/_GREED`, `LOOT_ROLL_NEED/_GREED` (Wahl, sofort),
  `LOOT_ROLL_PASSED` (Verzicht) und `LOOT_ROLL_WON/_YOU_WON/_ALL_PASSED` (Ende). **Bedarf = Haupt, Gier = Zweit**
  (wie in `Blizzbeute.lua`). `Kern.MusterGeordnet` ordnet die Fundstellen den Argumenten zu (übersetzte Vorlagen
  dürfen umstellen), die längere Vorlage steht zuerst („… + Role Bonus").
* **`/rnd`** im Chat (ohne Gargul): `RANDOM_ROLL_RESULT`, Art aus dem Bereich.

⭐ **Je Gegenstand eine Runde** (`Erfassung`, `Runden`): mehrere gleichzeitige Gegenstände vermischen sich nicht; gezeigt
wird die Runde mit der jüngsten Bewegung. Eine Runde endet mit der Vergabe (Beutemeldung, Blizzards Historie, „X won")
oder nach 120 s ohne Bewegung. Die Zeile je Spieler zeigt **„87  Haupt"** / **„41  Zweit"**; hat er nur gewählt
und noch nicht gewürfelt, nur die Art. Reihenfolge (`Kern.WurfReihenfolge`): **Haupt vor Zweit**, innerhalb davon
wenigste Hauptstücke zuerst, **bei Gleichstand der höchste Wurf** (Nutzerhinweis 14.10.2026: vorher entschied der Name). Die Namen aus Chat und Liste werden über `Kern.GleicherSpieler` verglichen (Nachname).

⭐ **Der erste Wurf zählt** (Nutzerhinweis 14.10.2026: bisher galt der letzte, wer fünfmal würfelte, bekam den fünften):
je Spieler und Gegenstand wird jeder weitere Wurf ignoriert (`Erfassung.WurfMerken`), auch ein späterer Zweitbedarf-Wurf
ändert die Art nicht; wer erst nur *gewählt* hat, darf noch würfeln. Bei Gargul gilt der erste nach `time`
(`Quelle.Wurf`). Ohne bekannten Gegenstand (getipptes `/rnd`) weiß das Addon nicht, wann eine neue Runde beginnt:
dort gilt ein Wurf nach 60 s als neue Runde.

⚠️ Ungemessen im Spiel: ob Forever `START_LOOT_ROLL` und die `LOOT_ROLL_*`-Meldungen so liefert (Gruppenbeute).
Fehlt etwas, bleibt nur die Anzeige leer, aufgezeichnet wird weiterhin über Beutemeldung und `C_LootHistory`.

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

### Historie zurücksetzen (`/fs reset`, seit 14.10.2026)

`/fs reset` fragt erst (Zahl der Einträge), `/fs reset ja` binnen einer Minute leert die Historie **dieses
Rechners** (Einstellungen und Gruppen bleiben). Vorher wird gesichert (`FairshareDB.sicherung`, eine Sicherung);
`/fs reset undo` und der Knopf *Sicherung wiederherstellen* (Einstellungen → Erfassung → Daten) spielen sie
**zusammenführend** wieder ein. ⚠️ Es löscht nur lokal: Haben andere in der Gruppe die Einträge noch, bringt der
automatische Abgleich sie zurück (nur Hinzufügen). Der automatische Abgleich läuft höchstens alle 2 Minuten und
**versucht es nach Ablauf der Sperre erneut**, statt die Abweichung liegenzulassen (so gefunden vom Szenario 18).

### ⭐ Zahlen über 2^31 nie mit `%d` formatieren

Prüfsummen reichen bis 2^32. `string.format("%d", 3000000000)` lieferte in der Simulation (Lua mit 32-Bit-`long`)
**-2147483648**; der Abgleich verlor dadurch ganze Tage, weil die Gegenseite die Zahl mit Minuszeichen nicht
parste und der Wert zudem für verschiedene Mengen gleich wurde. Wie WoW sich verhält, ist ungemessen — also
überall `%.0f` (Übertragung) oder `tostring`. Test: `testGrosseSummen`. Gefunden hat es erst das Szenario
„Automatisch abgleichen" mit zwölf Einträgen.

### Sprache (seit 14.10.2026)

Das Addon spricht die Sprache des Clients: **deDE = Deutsch, jeder andere Client = Englisch.** Wie bei
KaosUI sind die **deutschen Sätze die Schlüssel** (`L["Wer zeichnet auf"]`); `Locale.lua` hält die englische
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
