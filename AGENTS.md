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

Stand 22.10.2026, Version 0.2.0 (Loot-Regelsystem Resurrected integriert, Datenbuch verteilt, Protokollversion 3; seit dem 17./18.10. mehrere Gruppen mit Raidkader, Einteilung je Tag, Bench, „Keine Meldung“, Wochenabschluss, geteilte Einstellungen mit Vertrauenswurzel; seit dem 22.10. Probe-Modus und Anwesenheits-Reiter mit Default = Anwesend). Nur für Forever. **Übergabe-Stand und offene Punkte: `WORKBOARD.md`.**

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
| `Kern.lua` | Zählen, Sortieren, Zusammenführen, Prüfsummen, Kodierung, Schreiberwahl, Rechenregeln (§ 1–5) | **nein** |
| `Locale.lua` | Sprache: deutscher Client Deutsch, sonst Englisch (`L["deutscher Satz"]`) | ja |
| `Quelle.lua` | Garguls Historie, Würfelbereiche, Gegenstandstexte, Beispieldaten | ja |
| `Rolle.lua` | Gruppe lesen: wer ist Plündermeister/Leiter, zeichne ich auf | ja |
| `Gruppen.lua` | Kader und Raidgruppen | ja |
| `Anwesenheit.lua` | Bosskämpfe, Anwesenheitstracking (§ 2), Bank & Unentschuldigt (§ 6), Abendabschluss & Zuschläge, Spielerdetails | ja |
| `Erfassung.lua` | Chat, Würfe, Einstellungen, Eintragen, Gargul-Vergaben | ja |
| `Abgleich.lua` | Hallo, Live-Meldung, Abgleich, Hinweis-Fenster | ja |
| `Blizzbeute.lua` | Blizzards `C_LootHistory` als zweite Quelle | ja |
| `Stil.lua` | Bausteine im KaosUI-Look (Farben, runde Ecken, Knopf, Schalter, Segmentwahl, Bildlauf) | ja |
| `Wurf.lua` | eigenes Würfelfenster: Haupt (1-100) / OS (1-99) / Passen, Startdialog, Rangliste mit Anhebung | ja |
| `Konfig.lua` | Einstellungen teilen: einer stellt ein, alle bekommen es (Gilde, Rangprüfung, Nachfragen) | ja |
| `Nutzung.lua` | Dialog „Fairshare nutzen?": Antwort ja/nein je Gruppe mit Plündermeister, sonst schläft das Addon | ja |
| `Einstellungen.lua` | das Einstellungsfenster (Karten und Zeilen, drei Seiten) | ja |
| `Fenster.lua` | die Übersicht im KaosUI-Look: Liste, Verlauf, Anwesenheit, Spielerdetail, Wurf-Modus, Probe-Leiste | ja |
| `Befehle.lua` | `/fs` | ja |
| `Tests.lua` | Prüfstand für `Kern.lua` und `Anwesenheit.lua` (478 Prüfungen); dazu `tests/szenarien.py` (65 Szenarien) | **nein** |

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

## Das Loot-Regelwerk Resurrected (Version 0.2.0, 16.10.2026)

Speziell für die Gilde **Resurrected** (Thunderstrike EU) entwickeltes Regelwerk gemäß Entwurf vom 16.10.2026. Es löst das alte Prio-System ab und kombiniert das bewährte Golf-Prinzip mit Anwesenheitstracking, gerechten Fehl-Zuschlägen und einem dynamischen Aufholmechanismus.

### Die Regeln im Überblick

* **§ 1 Grundprinzip & Wertung (Golf-Prinzip):**
  - Formel: `Wertung = Main-Items + Zuschläge + dauerhafte Anhebungen`
  - Spieler mit der **niedrigsten Wertung** haben absoluten Vorrang vor dem Würfelwurf.
  - Nur bei gleicher Wertung entscheidet der höhere Wurf. Bei Würfelgleichstand: wer länger kein Main-Item hatte.
* **§ 2 Anwesenheit, Fehl-Zuschläge & Abendschnitt:**
  - Automatische Erfassung bei Bosskämpfen (`ENCOUNTER_END` / `BOSS_KILL`).
  - ⭐ **Im Raid = bei vorhandener Einteilung: alle eingeteilten Spieler der Gruppe (Standard = Anwesend)**, sofern nicht als Bank, Abgemeldet, Unentschuldigt oder Keine Meldung markiert (Entscheid 22.10.2026, `Anwesenheit.RaidMenge`); ohne Einteilung wer am Abendende in der Gruppe steht (bzw. Boss-Liste im Prüfstand). Wer früher geht oder vor dem Abschluss die Gruppe verlässt, verfälscht den Schnitt nicht mehr.
  - Gleitendes 6-Abende-Fenster (die letzten 5 archivierten Abende + der aktuelle Abend).
  - Fehlfaktoren:
    - 1. Fehlen: Faktor **0,7**
    - 2., 3., 4. Fehlen: Faktor **1,0**
    - 5. Fehlen: Faktor **1,3**
    - ab 6. Fehlen: Faktor **1,5**
    - Anmeldung vergessen (`Anwesenheit.VergessenSetzen`, nur Gildenleitung, Knopf „Vergessen“ in der Abwesenheit-Ansicht, `/fs vergessen <Name>`): das 1. und 2. Mal in den letzten `Kern.VERGESSEN_FENSTER` (8) Abenden Status `vergessen` mit der normalen Staffel; ab dem 3. Mal (`> Kern.VERGESSEN_SCHWELLE`) Status `vergessenStrafe` mit Faktor 1,5, mindestens 2 Punkte (`Anwesenheit.VergessenHistorie` zählt die früheren Abende; bei `vergessenStrafe` steht in `fehlAnzahl` das wievielte Mal). Beide zählen als Fehlen im 6-Abende-Fenster.
  - ⭐ **Vier Zustände in der Anwesenheit** (Entscheid 22.10.2026): **Anwesend** (grün, Standard für alle Eingeteilten), **Bank** (Faktor 0, Klick auf Knopf holt in die Gruppe), **Abwesend** (= abgemeldet, Staffel), **Unentschuldigt** (sofort Faktor 1,5, mind. 2 Punkte). Keine Meldung wird in der Einteilung gesetzt. Eingeteilte Spieler sind nie „offen“ — der Abschluss kann jederzeit ohne Sperre erfolgen. Unentschuldigt: sofort Faktor **1,5, mindestens 2 Wertungspunkte** (ab dem 1. Mal; Gildenleitung 17.10.2026: `Kern.ZuschlagUnentschuldigt`, `Kern.MIN_ZUSCHLAG_UNENTSCHULDIGT`). Rücknahme bei gutem Grund (Unfall): Markierung vor dem Abschluss entfernen, danach „Abend wiedereröffnen“. Bank: Faktor **0** (zählt voll wie Raid-Anwesenheit).
  - Abendschnitt: $\text{Schnitt} = \frac{\text{vergebene Main-Items an diesem Abend}}{\text{Spieler im Raid}}$.
  - Zuschlag: $\text{Zuschlag} = \text{Faktor} \times \text{Schnitt}$.
* **§ 3 Anhebung (seit 19.10.2026 nur von Hand):** Die automatische Anhebung ist aus (`Kern.AUTO_ANHEBUNG = false`; Entscheid der Gildenleitung: die Zuschläge reichen, die Anhebung traf auch Spieler, die immer dabei waren). Der Code der Rechnung bleibt (`Kern.Anhebung`, der Zweig in `Kern.WurfReihenfolge`, `Anwesenheit.AnhebungenAuswerten` kehrt sofort zurück) und wird in `Tests.lua` mit eingeschaltetem Schalter geprüft; `testKeineAutomatischeAnhebung` prüft das Betriebsverhalten. **Manuell:** `Anwesenheit.AnhebungSetzen(Name)` (Raid- oder Gildenleitung, `DarfBankVerwalten`): setzt auf den Niedrigsten der ANDEREN Kaderspieler im Raid (`KaderNiedrigste`) plus `Kern.ANHEBUNG_ABSTAND` (2), nie nach unten; bucht einen Satz `h_…` im Datenbuch (`AnhebungBuchen`, geht live an alle). Bedienung: Einstellungen → Gruppen → Karte „Anhebung“ (Feld Name, Knopf „Anheben“) und `/fs anhebung <Name>`. Der Neuling-Einstieg am 2. Abend (Niedrigster + 2, § 4) bleibt automatisch. Szenario 36 (Block „Keine automatische Anhebung mehr“).
* **§ 4 Neulinge & Gäste:**
  - ⭐ **Gründer sind keine Neulinge** (Fund im Spiel 17.10.2026: Am ersten Abend mit der Regel galt der ganze Kader als Proberaid, die Würfe wurden ausgeblendet, „Niemand hat gewürfelt“): `Anwesenheit.Gruender()` = die Spieler im Abschluss des **ersten abgeschlossenen Abends** (der Kader zu dem Zeitpunkt, auch die Fehlenden). Solange noch kein Abend abgeschlossen ist, und für jeden Gründer, ist der Status `kader`. Proberaid und Neuling gibt es nur für Spieler, die später zum Kader kamen. Szenario 38 sichert das.
  - **Neulinge (Proberaid):** Am 1. Raidabend im Kader kein Würfeln auf Main-Bedarf (`Anwesenheit.StatusVon` = `proberaid`, in `Kern.WurfReihenfolge` nie Würfler, nicht in der Ergebnisliste) und kein Fehl-Zuschlag.
    **Am 2. Abend** (`neuling`: genau ein früherer Abend, noch kein Item) wird die Wertung **einmalig auf den Niedrigsten der Kaderspieler im Raid plus 2** gesetzt (Entscheid 17.10.2026, wie die Anhebung; am 16.10. war es noch „gleichauf“). Er bekommt nicht sofort das erste Item, aber im Lauf des Abends eines, sobald die anderen über ihm liegen. Das schreibt `Anwesenheit.Rollen(liste, true)` beim Starter des Wurfs als Anhebung mit fester Kennung `hn_<Spieler>` fest (nur einmal) und verteilt sie. Danach ist er ein normaler Kaderspieler.
  - **Gäste** (nicht im Kader): Erhalten für den Abend dieselbe Wertung wie der Kaderspieler mit der niedrigsten Wertung (`gast` in `Anwesenheit.Rollen`, nie angehoben, nichts gespeichert). Die Items bleiben in der Historie. **Stammgäste** nimmt die Gildenleitung von Hand in den Kader auf (`Gruppen.KaderErgaenzen`, Liste `extra`): kein Proberaid, ihre Items zählen weiter, die Wertung bleibt beim Gildeneintritt erhalten (Schlüssel ist der Name).
* **Rückgabe (§ 1, 16.10.2026):** „Rückgängig" setzt `rueckgabe` (Zeitstempel), der Punkt bleibt. Erst die **Neuvergabe** desselben Gegenstands löst es auf (`Erfassung.RueckgabeAufloesen`, ruft `zurueck = true` beim ersten Empfänger, `ersetztDurch` = neue Kennung). Als Neuvergabe zählt auch das **Entzaubern** (`Wurf.Entzaubern` ruft `RueckgabeAufloesen`, beim Handel erst nach dem Handel). Wird es nie neu vergeben (verlorenes Item), behält der erste Empfänger den Punkt; ist es außerhalb des Addons weitergegeben worden, schließt `/fs rueckgabe` (Liste) und `/fs rueckgabe <Nr>` es von Hand ab (`Erfassung.OffeneRueckgaben`, `RueckgabeAbschliessen`). Der Schnitt des Abends ändert sich dadurch nie.
* **Kennzeichen (§ 5/§ 6):** Wer nicht die oberste Zeile im Ergebnisfenster zuteilt, kennzeichnet die Vergabe: Main `A` = „abweichend vom Ergebnis", OS `S` = „OS nach Absprache". Das Feld `kennzeichen` geht als 9. Feld in `Kern.Kodieren` mit (alte Zeilen mit 8 Feldern werden weiter gelesen), steht im Raidchat und in Verlauf/Spielerdetail (`Quelle.Kennzeichen`). Beim Zuteilen aus dem Beutefenster merkt `Erfassung.ZusatzMerken` Kennzeichen und Anhebung bis zur Beutemeldung.
* **Rundung:** Zuschläge und Wertungen auf drei Stellen (`Kern.Runde3`), damit alle Clients dieselbe Zahl rechnen (Gleichstand wird exakt verglichen).
* **§ 5 Zweitbedarf / Offspec (OS):**
  - Hauptbedarf schlägt immer Zweitbedarf.
  - Bei Zweitbedarf hat der Spieler mit weniger Vor-OS-Items Vorrang. Nur bei gleicher Stückzahl entscheidet der Wurf.
* **§ 6 Rollen & Berechtigungen:**
  - **Bank verwalten:** Raidleiter und Gildenleitung (`Konfig.Darf` / `Rolle.Berechtigt`).
  - **Unentschuldigt verwalten:** nur Gildenleitung (`Konfig.Darf`).
  - **Raidabend abschließen:** Raidleiter und Gildenleitung.
  - **Raider:** Reine Ansicht.

### Technischer Ablauf & UI-Architektur

* **Reiter „Anwesenheit“ (Stand 22.10.2026; nur mit Schreibrecht sichtbar; früher „Abwesenheit“):**
  - Zeigt **die Eingeteilten der aktiven Gruppe plus die Bench** des Tages (Einteilung von heute; ohne Einteilung der Gruppenkader).
  - 5 Spalten: `Spieler`, `Status`, `Bank`, `Abwesend`, `Unentschuldigt`.
  - 3 Knöpfe je Zeile: `[Bank/Bench]` (bei Bench „✓ Bench“: Klick holt per `BenchEinspringen` in die aktive Gruppe), `[Abwesend]` (bei Abwesenheit „✓ Abwesend“: toggelt `AbmeldungSetzen`), `[Unent.]` (bei Unentschuldigt „✓ Unent.“: toggelt `UnentschuldigtSetzen`). 1 Klick setzt bzw. nimmt den Status zurück.
  - Statusanzeige (Spalte 2): `Anwesend` (grün), `Bench` (Akzent), `Abwesend` (gelb), `Unentschuldigt` (rot), `Keine Meldung` (rot).
  - ⭐ **Default = Anwesend:** Wer in der Einteilung (`nurEinteilung`) steht und keinen Abwesenheitseintrag hat, gilt automatisch als **Anwesend** (`imRaid`, Faktor 0, kein Zuschlag) und zählt in `RaidMenge` für den `AbendSchnitt`. Der Raidleiter muss den Abend nicht mehr vor Gruppenauflösung schließen; vorzeitiges Verlassen der Gruppe nach Raidende verfälscht die Wertungen nicht mehr. Eingeteilte Spieler sind nicht mehr „offen“.
  - Die Ausklappliste wählt die **aktive Gruppe**; ein Wechsel ist ein anderer Abend. Knopf **`[Abend abschließen]`** mit 8-sekündiger Bestätigung (`/fs abschluss [ja]`).
  - Beim Abschluss: Zuschläge in `FairshareDB.zuschlaege`, Archivierung in `FairshareDB.abende`. **`[Neuen Abend beginnen]`** blendet den abgeschlossenen Abend lokal aus (Wertungen bleiben); **`[Abend wiedereröffnen]`** (`/fs abschluss wiedereröffnen`) macht den Abschluss samt Zuschlägen rückgängig.
* **Spielerdetail-Ansicht:**
  - Klick auf einen Spieler in der Liste öffnet die chronologische Aufschlüsselung: Datum, Art (*Haupt*, *Zweit*, *Abgemeldet*, *Unentschuldigt*, *Bank*, *Anhebung*), Punkte ($+1,0$, $+0,7$, $+2,0$, $0,0$), Formel und Detail-Fußzeile.
* **Wurf & Zuteilung (`Wurf.lua`):**
  - Rangliste lädt live `Anwesenheit.ZuschlaegeDaten()`.
  - Bei Zuteilung eines angehobenen Spielers wird die Anhebung in `FairshareDB.anhebungen` festgeschrieben.
* **Test-Isolation (`Anwesenheit._SetDB`, `_SetAnwesende`):**
  - Unit-Tests in `Tests.lua` (478 Prüfungen) laufen in einer isolierten Mock-Datenbank. Dadurch lesen Tests weder die SavedVariables des Spielers noch hinterlassen sie Testdaten.
  - ⭐ **Probe-Modus / Probe-Abend (`/fs probe abend`, `Anwesenheit.ProbeStandardAbend` und `/fs probe` UI-Modus):**
    Simuliert einen vollen Standardabend in einer Wegwerf-Datenbank mit 14 erfundenen Spielern (Anna, Ben, Chris, David, Elena, Frank, Greta, Hanna, Igor [1. Abend Proberaid], Jonas [2. Abend Neuling], Kevin & Lisa [abgemeldet], Max [weder an- noch abgemeldet = Keine Meldung], Nora [Bench]). Prüft die 6 Rechenregeln (Raid, Bench, Keine Meldung, Abgemeldet, Proberaid, Neuling) und gibt Zeile für Zeile „Erwartet / Ist“ im Chat aus (`/fs probe abend`, 6/6 Prüfungen grün).
    Interaktiver Modus (`/fs probe` bzw. Knopf „Probe“): Zeigt die gelbe Hinweisleiste „PROBE – keine echten Daten“ und eine Steuerungsleiste (`probeLeiste`) zum Vergeben von Main-/OS-Items, Status-Toggles und fertigem Ablauf.
    Isolation: `Erfassung.GildenReset`/`ResetAnwenden` sind im Probe-Modus gesperrt (21.10.2026, Szenario 71: sonst würde der gildenweite Reset die ECHTEN Daten löschen, der Probe-Modus lenkt nur Datenbuch und Historie um). Isolation: `Anwesenheit._SetDB` und `_SetAnwesende` lenken alle Zugriffe um; `FairshareDB` bleibt unangetastet; jedes Senden (`Abgleich.Senden`, `BuchVerteilen`, `Konfig.Senden` etc.) ist gesperrt. Szenarien 63 und 64.

---

### ⭐ „Fairshare nutzen?": nur der Plündermeister wird gefragt (17.10.2026)

Der Plündermeister beantwortet den Dialog; seine Antwort geht als Nachricht `U;ja|nein` an die Gruppe (`Nutzung.Verkuenden`, bei jeder Änderung der Gruppe wiederholt, damit Nachzügler sie bekommen). Alle anderen werden **nicht** gefragt und übernehmen sie (`Nutzung.Empfangen`: nur vom Plündermeister der eigenen Gruppe, Beutemethode muss Plündermeister sein). Eine **eigene Entscheidung** (`/fs nutzung ja|nein`, `FairshareDB.nutzungQuelle = "selbst"`) bleibt auch bei erneuter Meldung bestehen; wer nur übernommen hat (`"leiter"`), folgt später dem Plündermeister. ⚠️ `U` wird auch von einem **schlafenden** Addon angenommen (Weiche vor der `Rolle.Aktiv()`-Sperre in `Abgleich.lua`). Hat der Plündermeister das Addon nicht, bleibt nur `/fs nutzung ja`. Szenario 49.

### ⭐ Mehrere Gruppen: Raidkader, Einteilung, Abendkennung (Schritt 1, 17.10.2026)

Die Gruppen wechseln wöchentlich, darum (Konzept und Entscheide in `memory/fairshare-bewertung-prioritaet.md`):
* ⭐ **Seit 22.10.2026 vereinfacht & Raid-Größen 10er/20er/40er:** Gruppen gehören einer Raid-Größe an (`10`, `20` oder `40`, Schalter beim Anlegen in Einstellungen → Gruppen; `Gruppen.Groesse/-Setzen`, Konfigzeile `S|`). Die Einteilung gilt **einmal je Raid-ID** (eine Woche ab dem Wechseltag, Standard Mittwoch, geteilte Einstellung; `Gruppen.IdWechsel/-Setzen`, `IdStart(datum)`, `IdListe()`, Konfigzeile `I|`). Spieler können **gleichzeitig in einer 10er, 20er und 40er Gruppe** eingeteilt sein (unabhängige Zuweisung je Größe; innerhalb derselben Größe exklusiv). Der **Raidkader** liest sich beim Anmelden von selbst ein (`Gruppen.RaidkaderAuto`, 25 s), die Ränge sind einzeln wählbar und geteilt (`N|`). **Reiter „Anwesenheit“ und „Einteilung“ sehen nur Spieler mit Schreibrecht** (Gildenrang, `EinteilungDarf`). Die Gruppenwahl ist eine **Ausklappliste** (`Stil.Dropdown`, `Fenster.GruppeWaehlen`): Spieler/Verlauf = Filter, Anwesenheit = aktive Gruppe, Einteilung = Ziel (Gruppen nach Größe sortiert, `[10er] Bench`, `[20er] Bench`, `[40er] Bench`, Keine Meldung). Die Einteilung zeigt **zwei Listen**: links verfügbar (wer in der gewählten Raid-Größe noch frei ist), rechts in der Gruppe/Bench; Knöpfe Hinzufügen/Verschieben/Entfernen (`Fenster.EinteilungKlick`). Einstellungen → Gruppen: Gruppen mit Größen-Wahl anlegen/löschen, Raidkader (Ränge einzeln, Sync), Raid-ID (Wechseltag). Szenarien 48, 50, 52, 57, 65, 66.
* ⭐ **Verlauf-Suche, eigene Einteilung & 1-Klick-Gruppeneinladung (neu):**
  - **Ungefilterte Historie & Suchfeld:** Der Reiter „Verlauf“ zeigt immer die vollständige Historie unabhängig von Gruppen-Dropdowns. Oben rechts filtert ein dynamisches Suchfeld (`[Spieler oder Item suchen...]`) in Echtzeit nach Spielername oder Gegenstand.
  - **Eigene Einteilung & Spieler-Filter:** Im Reiter „Spieler“ sieht jeder Spieler (auch ohne Schreibrechte) rechts oben seine eigene Gruppeneinteilung (`Deine Einteilung: [10er] ... | [40er] ...`; `Gruppen.MeineEinteilungText`). Bei Wahl einer Gruppe im Dropdown werden deren zugeteilte Mitglieder links angezeigt (`Gruppen.EinteilungListe`). Fehlende Einteilungen werden beim Öffnen automatisch gildenweit angefragt (`T;?`, `Gruppen.EinteilungAnfragen`).
  - **1-Klick-Gruppeneinladung:** Im Reiter „Anwesenheit“ lädt der Knopf `[Gruppe einladen]` (bzw. `/fs invite` / `/fs einladen`) alle anwesenden/eingeteilten Spieler der aktuellen Gruppe mit 1 Klick ein, ignoriert Bank/Bench/Abgemeldete/Unentschuldigte sowie bereits in der Gruppe befindliche Spieler und wandelt ab 6 Spielern automatisch in einen Raid um (`Anwesenheit.GruppeEinladen`). Szenario 67.
* **Raidkader** (`Gruppen.RaidkaderSync`, `Gruppen.Raidkader()`, `Gruppen.RaidkaderRaenge()`, `Gruppen.RaidkaderRangGewaehlt(index)`): liest die Gildenliste für die gewählten Gildenränge ein. In Einstellungen → Gruppen → Karte „Raidkader“ ist jeder Rang einzeln ein-/ausschaltbar (Zwischenränge können ausgelassen werden, z. B. Mitglied zwischen Offizier und Initiand). Ansicht „Einteilung“ (Segment oben, `/fs einteilung`), Befehl `/fs raidkader [Rang/Ränge]`. Szenarien 48, 50, 52, 57, 65.
* **Einteilung** je Raid-ID (Schlüssel = Datum des ersten Tages der ID) und Spieler **je Raid-Größe eine Gruppe** (`FairshareDB.einteilung[IdStart][Schlüssel] = { name, gruppen = { [10] = ..., [20] = ..., [40] = ... }, gruppe = ..., zeit, von }`, leer = nicht eingeteilt). `Gruppen.EinteilungSetzen/-Von(datum, name, kat)/-Liste/-Vorhanden/-Senden/-Empfangen`. Verteilen ohne Streit: der **jüngere Eintrag gewinnt**, darum konvergieren alle Clients. Nachricht `T;<Datum>;<Urheber>;<Name>|<Gruppe>|<Zeit>~…` (Löschen einer Größe per `:kat`) über Gilde **und** Gruppe; angenommen nur, wenn der **Absender** selbst einteilen darf (`Gruppen.EinteilungDarf`: **nur Gildenränge mit Schreibrecht** laut Einstellungen, `Konfig.Darf`) und der Urheber im Text mit dem Absender übereinstimmt. Datum höchstens 10 Tage zurück und 35 voraus. In der Einteilung gibt es getrennte Bench-Ziele je Größe (`Bench (10er)`, `Bench (20er)`, `Bench (40er)`) und **Keine Meldung** (`Gruppen.KEINEMELDUNG`). **Neuen Abend beginnen** (`Anwesenheit.AbendNeuBeginnen`): blendet den abgeschlossenen Abend lokal aus (`ausgeblendet`), die Wertungen bleiben. Knopf „Einteilung senden“. Szenarien 48, 50, 57, 66.
* **Anwesenheitsliste/Abschluss** einer Gruppe nehmen die Einteilung des Tages als erwartete Spieler (`Anwesenheit.ErwarteteNamen`); gibt es für den Tag keine, gilt wie bisher der Kader. Mit Einteilung greift der Gilden-Rückfall nie (Spieler der anderen Gruppe sind nie „abwesend“). Ist eine Einteilung da, aber **keine Gruppe aktiv**, wird niemand erwartet (Hinweis statt Liste). ⭐ **In der Anwesenheit wählt der Gruppen-Knopf die aktive Gruppe** (Klick = aktivieren, nächste Gruppe der Reihe; ein Wechsel ist ein anderer Abend); in den anderen Ansichten filtert er nur.
* ⭐ **Bench** (Entscheid 18.10.2026): In der Einteilung ist „Bench“ ein weiteres Ziel (reservierter Name `Gruppen.BENCH`, keine Gruppe darf so heißen; in der Ausklappliste der Ansicht nach den Gruppen). Wer dort steht, wird in keiner Gruppe erwartet, steht aber **in der Anwesenheit jeder Gruppe** (Status „Bench“ hervorgehoben, Zeile oben nach den Offenen), gilt als **Bank mit Faktor 0** und blockiert den Abschluss nicht (`benchSet` in `KandidatenListe`/`AbendVorschau`; eine ausdrückliche Markierung geht vor). Der Bank-Knopf zeigt dort „✓ Bench“; ein Klick **holt ihn in die aktive Gruppe** (`Anwesenheit.BenchEinspringen`), er springt ein. Szenario 53.
* ⭐ **Wochenabschluss: Abgemeldete und „Keine Meldung“ (Entscheid 18.10.2026, Update 22.10.2026).** Im Reiter **Anwesenheit** stehen 3 Knöpfe je Zeile: **Bank/Bench**, **Abwesend** und **Unentschuldigt** (Default = Anwesend). **Abgemeldet** ist beim Wochenabschluss, wer in der Woche (Montag bis Sonntag) im Raidkader steht, aber an keinem Tag in einer Gruppe, auf der Bench oder bei „Keine Meldung“ eingeteilt war und an keinem Gruppenabend dabei war; **Keine Meldung**, wer nur dort stand. Beide bekommen einen Zuschlag **für zwei Abende** (`n` = die meisten abgeschlossenen Abende einer Gruppe in der Woche): je Abend Staffel × Schnitt (Keine Meldung: 1. und 2. Mal in 8 Abenden wie Abgemeldet, ab dem 3. wie unentschuldigt); **Schnitt = Mittel der Schnitte der Gruppen** für diese Abend-Nummer. Gebucht per Knopf „Woche abschließen“ in der Einteilung (zweimal klicken, die Vorschau steht im Chat) oder `/fs woche` / `/fs woche ja` / `/fs woche zurueck` (`Anwesenheit.WocheVorschau/-Buchen/-Zuruecknehmen`), nur mit Schreibrecht. Gebucht wird als `a`-Satz je Abend-Nummer mit der Kennung `<Montag>_wb<N>` (Datenbuch, wird mit zurückgenommen und neu gebucht). **Das Fehlen-Fenster zählt nur die eigenen Abende eines Spielers** (`Fehlhistorie`, `VergessenHistorie`: nur Abende, in denen er in `abschluss.spieler` steht). Szenario 55.
* **Abschluss je Gruppe:** `AbendIstAbgeschlossen` und `AbendWiedereroeffnen` gelten für den Abend der **aktiven Gruppe** (Gruppenkennung aus dem Feld oder der Kennung `Datum_Gruppe`); der Abschluss einer anderen Gruppe sperrt nichts. Nach dem Abschluss ist `aktiverAbend` leer; die Anwesenheit zeigt 14 Stunden lang „abgeschlossen“ (Knopf „Abend wiedereröffnen“), danach beginnt der nächste Abend leer mit der ersten Markierung oder dem ersten Boss.
* **Abendkennung** = Datum + Gruppe (`Anwesenheit.AbendId`, `GruppenKennung`: nur `[%w_.-]`, höchstens 24 Zeichen), ohne Gruppe nur das Datum. **Ein Gruppenwechsel ist ein anderer Abend** (der alte wird archiviert, wenn er Bosskämpfe hatte, sonst verworfen; ein abgeschlossener bleibt). Der Anhebungs-Vermerk heißt `hm_<Tag>_<Gruppe>`.
* **Alle drei Schritte des Mehrgruppen-Konzepts sind umgesetzt** (Einteilung/Raidkader/Abendkennung; Bench und „Keine Meldung“ als Ziele; Wochenabschluss und Zählung nur über eigene Abende). Offene Punkte stehen im `WORKBOARD.md` unter „Übergabe“.

### Das Datenbuch: Zuschläge, Abschlüsse und Anhebungen erreichen alle (16.10.2026, Protokollversion 3)

⭐ Die Wertung besteht aus Items **plus Zuschlägen plus Anhebungen**. Items gehen über den Abgleich der Historie; damit **jeder Client dieselbe Wertung rechnet** — auch wenn nächste Woche ein anderer den Raid leitet —, werden Abschlüsse und Anhebungen als eigene Sätze mitverteilt (`Kern.Buch*`, Speicher in `Anwesenheit.Daten()`):

* **`a` Abschluss eines Abends:** Kopf (`a;Abend;rev;zu;Datum;Zeit;Autor;Schnitt;Items;Raid;Bosse;n`) plus `n` Zeilen `s;Abend;rev;Name;Status;Faktor;Zuschlag;Fehlen;Bosse`. **`rev` zählt bei jedem Abschließen und Wiedereröffnen hoch** (`abend.buchRev`), der höhere Stand gewinnt — monoton, darum konvergiert es. `zu=0` heißt wiedereröffnet (keine Spielerzeilen, Zuschläge verschwinden). Der Empfänger baut `abende[id].abschluss` und `zuschlaege` (`z_<Abend>_<Spieler>`) nach; fehlt ihm der Abend, legt er einen schlanken Archiv-Abend an (genügt für `Fehlhistorie`).
* **`h` Anhebung:** einzelner, unveränderlicher Satz in `anhebungsliste` (Kennung `h_<Spieler>_<Zeit>_<Zahl>`; `hn_<Spieler>` = Neuling-Start, `ha_<Spieler>_<Tag>` = Anhebung des Abends, `hm_<Tag>` = Auswertung des Tages erledigt, Wert 0). Frühere Summen in `anhebungen[k]` zählen weiter mit, werden aber nicht verteilt.
* **Weg:** live als `D;0;…` bei Abschluss, Wiedereröffnung und jeder neuen Anhebung (`Abgleich.BuchVerteilen`); beim Abgleich zusätzlich `Y` (Liste) → `M` (was fehlt) → `D` (Sätze). Das **Hallo** trägt Anzahl und Prüfsumme des Buchs, ein Unterschied löst wie bei den Einträgen den Abgleich aus. Alles Fremde läuft durch `Kern.BuchDekodieren` (Zahlen begrenzt, Status auf eine Liste, Kennungen nur `[%w_.-]`).
* **Vertrauen:** Wie bei den Einträgen nimmt Daten nur an, wer in unserer Gruppe **und** Gilde ist; live nur von Berechtigten. Die Angaben `autor` sind Eigenangaben und nicht geprüft.
* Tests: `Tests.lua` `testDatenbuch` (Kodieren, Reihenfolge, Revisionen, Ablehnung), Szenario 36 (live, Wiedereröffnen, Abgleich nach Totalverlust, Neuling/Gast/Proberaid, Kennzeichen, Stammgast).

---

## Schreiber (`Rolle.lua`, `Kern.Schreiber`)

Rangfolge: **Plündermeister → Leiter → Assistenten**. Gewählt wird der erste,
der das Addon nachweislich hat (Hallo-Meldung) oder man selbst ist.

* ⭐ **Ohne Gruppe wird nie aufgezeichnet** (auch nicht bei „immer“; Entscheid 14.10.2026): Das Addon ist für
  Gruppeninhalt da, ein Solo-Fund gehört nicht in die Historie, Fünfer-Instanzen dienen nur dem Erproben des
  Raid-Ablaufs *mit* einer Gruppe. Zentral in `Rolle.IchSchreibe`, daran hängen Chat, Blizzard-Historie und Gargul.
* ⭐ **Fairshare ist nur mit Plündermeister UND Zustimmung im Dienst, sonst schläft es** (Entscheid 15.10.2026): `Rolle.Aktiv()` =
  Gruppe **und** Methode „master" (bei jedem Aufruf frisch gelesen) **und** `FairshareDB.nutzung == "ja"`. `Nutzung.lua` fragt in einem
  Dialog „Fairshare nutzen?", sobald Plündermeister aktiv ist (Ja / Nein / Kreuz = keine Antwort, nicht erneut fragen); jede andere
  Beutemethode (Gruppenbeute, Bedarf vor Gier, Reihum, Jeder gegen Jeden, persönliche Beute) oder das Verlassen der Gruppe löscht die
  Antwort (`Nutzung.Auswerten` bei `GROUP_ROSTER_UPDATE`, `PARTY_LOOT_METHOD_CHANGED`, 4 s nach dem Anmelden). Von Hand: `/fs nutzung
  [ja|nein|fragen]`, Einstellungen → Würfeln & Abgleich → Nutzung. Neue Datei → WoW-Neustart.
  Gesperrt sind die Ereigniseingänge (`Erfassung`: `START_LOOT_ROLL`, `CHAT_MSG_LOOT`,
  `CHAT_MSG_SYSTEM`; `Blizzbeute`; Garguls `ROLLOFF_STARTED`), `Wurf.DarfStarten`, `Wurf.Empfangen` und `IchSchreibe` (auch bei „immer").
  Auch Abgleich (Hallo, Hinweis-Fenster, Automatik), Einstellungen teilen (Nachfragen/Empfangen) und der Kader-Sync beim Anmelden ruhen;
  `PARTY_LOOT_METHOD_CHANGED` weckt sie sofort (Hallo, Nachfrage). Slash-Befehle, Übersicht und Einstellungen bleiben benutzbar. Szenario 32.
  Tests: `Welt(..., ml=0)` ist jetzt Standard, `ml=None` = Gruppenbeute.
* **Beutefenster als Plündermeister** (`LOOT_OPENED`, `Wurf.lua` `beuteOeffnet`): Ist etwas Verteilbares darin (Qualität/Ort wie bei
  der Aufzeichnung), öffnet sich der Startdialog von selbst (Schalter `startAuto`, Standard an; Szenario 34).
* **Wurfbeginn im Chat** (`Erfassung.WurfAnsage`, Szenario 35): Der Starter schreibt eine Zeile mit Gegenstand, beiden `/roll`-Bereichen
  und Zeit, damit auch Spieler ohne Addon mitwürfeln — als **Raidwarnung (`RAID_WARNING`)**, wenn er im Raid Leiter oder Assistent ist,
  sonst Raid-/Gruppenchat; Schalter `ansagen`. **Dasselbe gilt für die Vergabe-Ansage** („X wurde an Y vergeben!“, auch fürs Entzaubern).
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
| `H` | Hallo: Version, Anzahl, Prüfsumme der Einträge, **Anzahl und Prüfsumme des Datenbuchs** (`H;3;n;summe;bn;bsumme`) | jeder in der Gruppe |
| `V` | **Leitungs-Abgleich:** derselbe Stand wie im Hallo, aber **über die Gilde**; nur Berechtigte senden und beachten ihn (siehe „Leitungs-Abgleich“ unten). `Q/Y/N/M/D/E` laufen dabei als **Flüstern** zwischen Berechtigten | Spieler mit Schreibrecht |
| `Y` | **Datenbuch:** Liste des Leiters (`a:Abend@rev`, `h:Kennung`), wie `Q` | Plündermeister, Leiter, Assistent |
| `M` | **Datenbuch:** „das fehlt mir" (Liste), wie `N` | jeder in Gruppe und Gilde |
| `D` | **Datenbuch:** Sätze (Zeilen `a`/`s`/`h`). Sitzung `0` = live (nur Berechtigte: Leiter/Assistent/Plündermeister oder `Konfig.Darf`) | jeder in Gruppe und Gilde |
| `L` | eine neue Vergabe live | Plündermeister, Leiter, Assistent |
| `Q` | Tagesstand des Leiters (Prüfsumme je Tag, UTC) | Plündermeister, Leiter, Assistent |
| `N` | „diese Tage weichen bei mir ab" | jeder in der Gruppe |
| `E` | Einträge dieser Tage | jeder in Gruppe **und Gilde** |

Ablauf: Weicht beim Hallo jemand ab, bekommt der Leiter ein Hinweis-Fenster
(einmal je Zusammensetzung der Abweichler). **Abgleichen** → `Q`; jeder
vergleicht, meldet abweichende Tage (`N`) und schickt seine Einträge dazu
(`E`); der Leiter schickt die gemeldeten Tage nach. Wer in seiner zufälligen
Wartezeit hört, dass es schon da ist, schweigt.

⭐ **Chat-Meldungen (22.10.2026):** Wer den Abgleich nicht selbst startet, sieht beim Eintreffen der ersten Q-Meldung „X gleicht die Daten in der Gruppe ab – deine werden aktualisiert …“; nach einer Ruhepause (25 s) folgt „Abgleich beendet: …“ (`Abgleich.AbschlussMelden`). Der Starter sieht „Abgleich gestartet …“.

### ⭐ Leitungs-Abgleich (22.10.2026): Berechtigte gleichen gildenweit ab, auch ohne Gruppe

Spieler mit Schreibrecht (`Konfig.Darf`, Gildenrang) gleichen Historie und Datenbuch (Wertungen) **gildenweit untereinander** ab; danach aktualisieren sie ihre Gruppen wie bisher (Hallo/automatischer Abgleich). Das Addon muss dafür **nicht im Dienst** sein (kein Plündermeister, keine Gruppe nötig); `V` und alle Flüsternachrichten passieren die Sperre in `Abgleich.lua`.
* **`V;<Version>;<n>;<Summe>;<bn>;<bsumme>`** (Gildenkanal, klein): der eigene Stand, 45 s nach dem Anmelden, nach Änderungen (`LeitungBeaconSpaeter` aus `HalloSpaeter`, `Verteilen`, `BuchVerteilen`) und alle 15 Minuten. Nur Berechtigte senden und beachten ihn.
* **Weicht der Stand eines Berechtigten ab,** startet der Empfänger mit ihm einen Abgleich (`sitzungStarten("WHISPER:<Name>")`): dieselben Nachrichten `Q/Y/N/M/D/E` wie in der Gruppe, aber **als Flüstern** (`senden` kennt `"WHISPER:<Name>"`, die Sitzung merkt ihren Kanal in `S.kanal`). Angenommen wird nur von Berechtigten an Berechtigte (`leitungErlaubt`); `D;0` (live) und alle anderen Typen sind per Flüstern nicht erlaubt. Je Partner nicht öfter als alle 5 Minuten für denselben gemeldeten Stand; meldet er einen neuen, gleicht man sofort ab.
* **Meldung:** leise; nur wenn etwas Neues ankam („Mit der Leitung abgeglichen: …“, `AbschlussMelden(true)`). Schalter in den Einstellungen („Mit der Gildenleitung abgleichen“, `leitungSync`, Standard an), Zeile in `/fs abgleich status`. Szenario 59.
* ⚠️ Das Protokoll hat keine neue Versionsnummer, aber alle Berechtigten sollten dieselbe Fassung haben (ältere ignorieren `V` einfach).

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
  würfelt standardmäßig **100 / 99** (seit 22.10.2026, wie Garguls eigene Voreinstellung; vorher 100 / 50; **einstellbar**, siehe „Würfelbereiche einstellbar").
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
geht ein kleines Fenster auf: Gegenstand (Tooltip), Zeitbalken, **Haupt (1-100)**, **OS (1-99)**, **Passen**. Ein Klick
ruft `RandomRoll(1, 100|50)`; die Zahl kommt vom Server als `RANDOM_ROLL_RESULT` und wird wie jeder Wurf in
`Erfassung.Systemmeldung` gelesen (das Addon sendet nie Ergebnisse → nichts zu fälschen). Solange ein Wurf läuft
(+6 s), ordnet `Wurf.AktuellerLink()` jeden Bedarfswurf der Gruppe dem Gegenstand zu — auch von Spielern ohne Addon.
Nachrichten über `Abgleich.Senden(text, vorn)`: `S;<id>;<Sekunden>;<Link>` und `X;<id>`, nur von Leiter/Assistent/
Plündermeister der eigenen Gruppe und Gilde. Dauer: Einstellung `wurfDauer` (Standard 30 s). Die Übersicht öffnet sich
nur beim Leiter (`Erfassung.WurfBeginnt(link, false)` bei den anderen). Der erste Wurf zählt (siehe unten); Haupt vor OS.
Englisch heißt Zweitbedarf **„OS"** (Nutzerwunsch), nicht „Off".

⭐ **Passen und frühes Ende (Wunsch 17.10.2026):** „Passen" geht als Nachricht `P;<Kennung>` an die Gruppe (jeder darf sie senden, gilt nur für den laufenden Wurf mit dieser Kennung); `Erfassung.WurfPasst` vermerkt es in der Runde (`Arten[k] = "pass"`, Wert 0, nie in der Rangliste, ein späterer Wurf ändert es nicht). Das Würfelfenster zeigt „Gewählt x von y · Passt z", die Übersicht „passt" in der Wurfspalte. **Der Wurf endet früh** (Ticker in `Wurf.lua`, nur beim Starter, frühestens 2 s nach dem Start), sobald jeder in der Gruppe gewürfelt oder gepasst hat; Spieler ohne Addon können nur würfeln, halten den Wurf sonst bis zum Zeitende offen. Szenario 47.

**Offene Wünsche (Nutzer, 14.10.2026, „für die Zukunft"):**
* **Würfelzeit frei wählbar**, länger oder kürzer. Heute: Einstellung `wurfDauer` mit 20/30/45/60 s (Einstellungen →
  Gargul & Abgleich → Würfelfenster, Grenzen 10–120 s in `Wurf.Dauer`). Idee: Feld im Startdialog für diesen einen Wurf.
* **Festlegbar, was ein „Main"- und was ein „OS"-Wurf ist.** Früher fest 1-100 / 1-50 (heute Standard 1-100 / 1-99) an vier Stellen: `Kern.Bedarfsart`,
  die Knöpfe in `Wurf.lua` (`RandomRoll`, Beschriftung), `Quelle.GargulBereiche`/`SOLL`, Texte. Idee: zwei Einstellungen
  (Obergrenze Haupt, Obergrenze OS), überall daraus lesen; Beschriftungen und Erkennung folgen; Abgleich-Protokoll
  unberührt (die Art steckt im Eintrag, nicht der Bereich).

### Einstellungen teilen (`Konfig.lua`, Nutzerwunsch 15.10.2026)

Nur einer stellt ein (Würfelbereiche, Verzauberer, Gruppen …), alle bekommen es — wichtig bei mehreren 10er-/20er-Raids.

* **Senden:** *Einstellungen → Würfeln & Abgleich → Einstellungen teilen → An alle senden* oder `/fs konfig senden`. Über den
  **Gildenkanal** (Nachricht `K;<Stand>;<von>;<k>;<n>;<Paket>`, Zeilen wie `B|1|100|1|50`, `V|Name,Name`, `G|Name|auto|Ränge`,
  `X|Name|Namen`) an alle, die online sind. `Abgleich.Senden(text, vorn, kanalName)` kennt jetzt auch `"GUILD"`;
  `Abgleich.Empfangen` reicht `K`/`A` an `Konfig.Empfangen` weiter, **vor** der Gruppenprüfung.
* **Wer darf senden (Entscheid 17.10.2026):** Gildenrang. `Konfig.RangStufe(name)` = Stufe aus der Reihenfolge der vorkommenden Ränge (1 = höchster; Forever
  zählt ab 1, die alte Liste ab 0). ⭐ **Wurzel des Vertrauens: Stufe 1 und 2 (`Konfig.WURZEL`) dürfen immer** — auf jedem Client, auch bei einem
  frischen mit Standardwerten; sonst käme nie eine Meldung an (Henne-Ei: die Grenze reist selbst in einer Meldung). Die Grenze
  `konfigRang` (Standard und Mindestwert **2**) erweitert das nur nach unten (3 bis 6) und ist selbst Teil der geteilten Einstellungen:
  **ändern darf sie nur die Wurzel**; die Rangangabe in einer Meldung von Stufe 3 oder tiefer wird ignoriert. Dasselbe Recht gilt fürs
  Einteilen (`Gruppen.EinteilungDarf`). **Nur lesen:** Die Zeilen mit `geteilt = true` (und `"wurzel"` für die Rangstufe) in
  `Einstellungen.lua` sind für Spieler gesperrt, deren Rang bekannt ist und nicht reicht (`Konfig.Gesperrt`). **Selbstheilung**
  (`Konfig.Heilen`, 45 s nach dem Anmelden und nach Gruppenbeitritt): Wer nicht schreiben darf, wird auf den letzten offiziellen Stand
  (`konfigRoh`) zurückgesetzt; wer schreiben darf oder dessen Rang unbekannt ist, nicht. ⚠️ Echte Sperre gegen jemanden, der an
  seinem eigenen Rechner Dateien ändert, gibt es in WoW nicht; die Sicherheit liegt bei den **Empfängern** (Absender und Rang
  liefert der Server). Szenario 51.
* **Auch ein schlafendes Addon** (kein Plündermeister, Antwort Nein) hört `K`, `A`, `T` und `U` (Weiche vor der `Rolle.Aktiv()`-Sperre
  in `Abgleich.lua`) und fragt beim Anmelden die Gilde nach neueren Einstellungen; im Gruppenkanal fragt nur ein Addon im Dienst.
* **Annehmen** nur wenn: Absender in der eigenen Gilde **und** Urheber (`von`) darf senden (Gildenliste muss geladen sein, sonst
  nichts) **und** der Stand neuer ist. Weitergereichtes (Absender ≠ Urheber) nur, wenn **ich** in den letzten 3 min nachgefragt
  habe — sonst könnte sich jedes Gildenmitglied als Leiter ausgeben. Schalter *Einstellungen der Gildenleitung übernehmen*
  (`konfigAnnehmen`) schaltet es ab. `Konfig.Dekodieren` begrenzt alles Fremde (Zahlen auf ihren Bereich, Namen auf 40 Zeichen
  ohne `; ~ | ,`, höchstens 12 Gruppen/8 Verzauberer/60 Namen je Gruppe, Unbekanntes bleibt unbeachtet).
* ⭐ **Automatisch senden (22.10.2026):** Ändert jemand mit Schreibrecht in den Einstellungen eine geteilte Zeile (`geteilt`), schickt `Konfig.AutoSenden` sie nach 4 s von selbst an alle (mehrere Änderungen = eine Sendung, nur bei echter Änderung gegenüber `konfigRoh`, Meldung im Chat). „An alle senden“ bleibt als Knopf. Szenario 58.
* **Nachholen:** Beim Anmelden (25 s, Gilde) und beim Gruppenbeitritt (höchstens alle 5 min) fragt jeder `A;<mein Stand>`. Wer einen
  **neueren** Stand hat, schickt ihn zufällig verzögert nach (1–6 s; wer inzwischen hört, dass es jemand tat, schweigt) — und zwar
  den **unveränderten Text des Urhebers** (`konfigRoh`), nie die eigenen, vielleicht geänderten Werte.
* **Was geteilt wird:** Würfelbereiche, Würfelzeit, Ansage, Einstecken, nur Ausgewürfeltes, Abgleich automatisch, Qualität, Ort,
  Rangstufe, Verzauberer, Gruppen (Beschriftung, Ränge, von Hand ergänzte Namen). **Nicht:** Fenstergröße/-lage, „selbst
  öffnen", wer aufzeichnet (`schreiben`), die aktive Gruppe, der verwaltete Kader (jeder bildet ihn aus den Gildenrängen neu).
  Gruppen werden **ersetzt**: eigene Gruppen, die es beim Absender nicht gibt, verschwinden.
* **Zurück:** Vor jeder Übernahme wird der alte Stand gesichert (`konfigAlt`); `/fs konfig zurueck` oder der Knopf stellt ihn her.
* Diagnose: `/fs konfig` zeigt Stand, eigene Stufe, ob angenommen wird, und die letzten Meldungen mit Grund einer Ablehnung.

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
* **Freie Würfelzeit:** Der Startdialog hat ein Feld *Dauer (s)* (5–300), **oben rechts neben dem Gegenstandsfeld** (unten neben der Beschriftung war es im Spiel nicht zu sehen: Die englische Beschriftung „Duration (s)" ist länger als das Feld weit rechts begann — Nutzerfund 15.10.2026, Lehre: Elemente nie an feste Abstände neben Text ankern, dessen Länge je Sprache wechselt). Die gewählte Zeit gilt für diesen Wurf und wird der
  neue Standard (`wurfDauer`); `/fs wurf 45 <Link>` geht auch. Die Voreinstellung 20/30/45/60 bleibt in den Einstellungen.
  Empfänger nehmen bis 300 s an.

### Würfelbereiche einstellbar, Ansage, Abbrechen (Nutzerwünsche 14.10.2026)

* ⭐ **Würfelbereiche einstellbar** (Einstellungen → *Würfeln & Abgleich* → *Würfelbereiche*; `/fs bereiche haupt 1 100`,
  `… zweit 1 99`): `Kern.BEREICHE` (Standard 1-100/1-99) wird von `Erfassung.BereicheAnwenden` aus `FairshareDB.bereiche`
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

⚠️ **Seit dem Regelwerk 16.10.2026 ist „Rückgängig" eine Rückgabe** (Abschnitt „Rückgabe" bei den Regeln): Der Eintrag bekommt `rueckgabe`, und `zurueck` setzt erst die Neuvergabe. Die Beschreibung davor gilt für `zurueck` selbst weiter.

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
    Spieler** (`TRADE_SHOW`, Partner über `GetUnitName("NPC")`) legt das Addon den Gegenstand selbst ein (bis 6 Plätze). **Das Einlegen sucht jeden vorgemerkten Gegenstand ohne die Filter der Auswahlliste** (Qualität, Handelsfrist: `taschenPlaetze`), versucht es bis zu dreimal (das Fenster ist gleich nach `TRADE_SHOW` manchmal noch nicht bereit) und **meldet sichtbar, wenn nichts im Fenster liegt** (mit der Fehlermeldung von `PickupContainerItem`/`ClickTradeButton`; Forever-API ungemessen).
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

* **Gargul** (`RollOff.CurrentRollOff.Rolls`): die Art kommt aus dem Wurfbereich (`Kern.Bedarfsart`: 1-100 Haupt, 1-99
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

### ⭐ Gildenweiter Reset (22.10.2026, `/fs reset gilde`, Einstellungen → Erfassung → Daten → „Für alle zurücksetzen“)

Ein lokaler Reset wird vom nächsten Abgleich wieder aufgefüllt (Abgleich ergänzt nur). Darum gibt es eine **Reset-Marke** `FairshareDB.resetZeit` (Serverzeit des Resets): Sie reist als Zeile **`Z|<Zeit>`** in den geteilten Einstellungen (`Konfig.lua`), wird also auch an Spieler nachgereicht, die beim Reset offline waren (Anmelden/Gruppenbeitritt fragt `A`). **Angenommen nur, wenn der Urheber Stufe 1 oder 2 ist** (`Konfig.WURZEL`; Marken von Stufe 3+ werden ignoriert und gemerkt). Wer eine neuere Marke bekommt, ruft `Erfassung.ResetAnwenden`: leert **Historie und Datenbuch** (`vergaben`, `alias`, `abende`, `zuschlaege`, `anhebungen`, `anhebungsliste`, `aktiverAbend`); Einstellungen, Gruppen, Raidkader und Einteilung bleiben. **Alles, was älter ist als die Marke, nimmt der Abgleich nicht mehr an** (`Abgleich.einfuehren`: Eintrag `timestamp`; `buchEinfuehren`: Satz `zeit`), auch nicht von jemandem, der den Reset noch nicht hat. Ausgelöst wird er von `Erfassung.GildenReset()` (nur `Konfig.DarfWurzel`, danach sofort `Konfig.Senden`; die UI und der Befehl fragen zweimal). Die Sicherung (`sicherung.gilde = true`) bleibt in der Datei, `/fs reset undo` und der Wiederherstellen-Knopf verweigern sie (ein gildenweiter Reset ist nicht zurücknehmbar, nur von Hand aus `FairshareDB.sicherung`). Der lokale `/fs reset` bleibt wie er war. Szenario 60. ⚠️ Spieler, die die neue Fassung nicht haben, kennen die Marke nicht und behalten ihre Daten.

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

### Übungsmodus („Probe-Abend“, seit 22.10.2026)

Ermöglicht es der Gildenleitung, einen kompletten Raidabend allein, in unter zwei Minuten und ohne echte Daten durchzuspielen.
* **Aktivierung:** Befehl `/fs probe` (bzw. `/fs practice`) oder Klick auf die Fußschaltfläche *Probe* in `Fenster.lua` (neben *Beispiel*). Beenden über *Probe beenden*, Schließen des Fensters (`OnHide`) oder erneuten Aufruf von `/fs probe`.
* **Chat-Schnellprüfung:** `/fs probe abend` (alias `/fs practice night`) führt den Standardabend in einer flüchtigen Wegwerf-Datenbank aus und gibt Zeile für Zeile Erwartet / Ist für alle 5 Kategorien (Raid, Bench, Unentschuldigt, Abgemeldet, Neuling) im Chat aus.
* **Bedienleiste:** Erfundene Spieler (Anna, Ben, Chris, Dora, Emil, Felix), Raid-Umschaltung (`[In den Raid]`/`[Aus dem Raid]` und Knöpfe in Zeilen), Vergabe (`[+ Main-Item]`, `[+ OS-Item]`), Status (`[Bench]`, `[Unent.]`), vordefinierter Durchlauf (`[Fertiger Ablauf]`) sowie `[Zurücksetzen]`.
* **Vollständige Isolation:** Datenzugriffe laufen über eine reine Speicher-Tabelle (`dbOverride` in `Anwesenheit.lua`). Jedes Senden ist geblockt (`Abgleich.Senden`, `senden`, `einreihen`, `Beacon`, `BuchVerteilen`, `Konfig.Senden`) und eingehende Netzwerknachrichten werden ignoriert. `FairshareDB` bleibt unangetastet; nach dem Schließen ist alles restlos bereinigt.

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
