# Loot-Ordnung — Arbeitsnotizen

Regelwerk für ein neues Lootsystem der Gilde **Resurrected**, gedacht für
**World of Warcraft Forever** (Classic+, Beta ab 17.09.2026).
Stand: **Entwurf, noch nicht beschlossen** — 13.09.2026.
**Alle §§ 1–10 sind mit dem Nutzer durchgearbeitet und abgenommen.** Offen sind
nur noch die sieben Punkte im Kasten am Dokumentende sowie zwei zurückgestellte
Fragen (siehe unten).

| | |
|---|---|
| Regelwerk (Quelle) | `loot-ordnung.html` |
| Veröffentlicht als | https://claude.ai/code/artifact/82f64d38-0b63-4c4f-9fd7-1208bdb8bb97 |
| Rechenmodell | `berechnungen.py` — erzeugt **alle** Zahlen im Dokument |

⚠️ **Beim Ändern einer Stellschraube immer beide Dateien anfassen.** Verfallsrate,
Punkte je Boss, Platzfaktoren und der Deckel stehen oben in `berechnungen.py`;
das Skript laufen lassen und die Werte im HTML nachziehen. Auch die Kurven im
Diagramm von § 4 kommen von dort (Abschnitt 4 der Ausgabe liefert die
SVG-Koordinaten-Grundlage) — nie von Hand hinschreiben, das Dokument lebt davon,
nachrechenbar zu sein.

Zum Aktualisieren des veröffentlichten Dokuments die **URL mitgeben**, sonst
entsteht ein zweites Artifact statt einer neuen Fassung.

---

## Warum überhaupt ein neues System

Bisher: **Loot Council über RCLootCouncil**, Auswertung im Google-Sheet
(siehe `../Loostliste/`). Vom Nutzer genannte Schmerzpunkte:

1. Unzufriedenheit einiger Mitglieder
2. Aufwand für die Raidleitung
3. Diskussionen und Intransparenz

**Diagnose:** Das liegt an der Konstruktion von Loot Council, nicht an schlechten
Entscheidungen. Wenn Menschen wiederholt über Menschen entscheiden, ohne
verbindlichen Maßstab, entsteht genau dieses Muster. Ein besser informierter Rat
ändert daran nichts — deshalb wurde die ursprünglich vorgeschlagene
„Berater-Stufe" (LC bleibt, Addon liefert Daten) **verworfen**.

## Der Systemkern

    Prio = Einsatz ÷ Rüstwert

EPGP-Erbe, aber ohne Pflegearbeit. Entscheidend für Classic+: **Der Rüstwert
kommt aus Gegenstandsstufe × Platzfaktor**, also aus dem, was der Client selbst
liefert. Keine BIS-Liste, keine externe Datenbank, keine gepflegte
GP-Tabelle — das System funktioniert am Tag 1 einer Erweiterung, über die
niemand etwas weiß. Das ist der Grund für diesen Aufbau und sollte nicht
aufgeweicht werden.

Der wöchentliche Verfall von 10 % trifft **beide** Größen gleichzeitig. Daraus
folgt die wichtigste und unintuitivste Eigenschaft des Systems:

> **Abwesenheit kostet keine Prio.** Das Verhältnis bleibt stehen. Wer zwei
> Wochen aussetzt, steht danach *vor* dem, der da war und ein Item mitnahm.

Das ist mehrfach nachgerechnet (Abschnitt 2 in `berechnungen.py`) und der
Grund, warum mehrere naheliegende „Fairness-Korrekturen" unnötig sind. **Wer
argumentiert, jemand baue durch Fehlzeit einen Rückstand auf, denkt in
DKP-Logik und irrt.**

## Getroffene Entscheidungen

Alle vom Nutzer beschlossen, mit Begründung — nicht ohne Anlass wieder aufmachen.

### Einsatz (§ 2)

| Fall | Punkte |
|---|---|
| Je Bosskampf, auch Wipes | +5 |
| Voll dabei | +10 |
| Zugesagt, online, nicht gebraucht (Bank) | voller Satz |
| Abgemeldet bis 24 h vor Raidstart | halber Satz |
| Später abgemeldet, vor Raidstart | Viertelsatz |
| Alles andere | 0 |

- **Absagen bringen Punkte**, damit sich alle von selbst melden und die
  Raidleitung niemandem hinterherläuft. Der Anreiz entsteht aus der **Differenz
  zu null**, nicht aus einer Strafe für No-Shows — sozial deutlich verträglicher.
- **Gedeckelt auf drei Raidtage in Folge**, Zähler wird bei jeder Teilnahme
  zurückgesetzt. Grund: Ein Abwesender baut keinen Rüstwert auf, seine Prio
  steigt also ungebremst. Bei drei Tagen sind es +15 % (Rauschen), bei acht
  +55 %, im Dauerzustand Prio 2,50 gegen 1,11 eines aktiven Raiders.
- **Bezugsgröße ist der tatsächlich gelaufene Abend**, nicht eine Pauschale.
  Schöner Nebeneffekt: Fällt der Raid aus, bekommt niemand etwas — sonst hätten
  ausgerechnet die Absagen Punkte gebracht, die ihn platzen ließen.
- **Kurzfristige Absage nur Viertelsatz** (Nutzer-Argument): Bei gleichem Satz
  wäre die frühe Absage die dümmere Wahl, man hielte sich alles offen.
- **„Vielleicht" ist kein Status, sondern ein Zwischenstand.** Wer zur Frist noch
  dort steht, zählt wie nicht gemeldet. Es wird nur dann vergessen, wenn der
  Spieler **mitgeht** — online sein und zuschauen bringt nichts, sonst wäre
  „vielleicht" die bequemste Wahl für alle.
- **Bank setzt eine Zusage voraus** und ist kein Status, den man sich durch
  Einloggen selbst gibt.

### Rüstwert (§ 3)

    Rüstwert = Platzfaktor × 2^(Gegenstandsstufe ÷ K)

| Platz | Faktor |
|---|---|
| Zweihandwaffe | 3,0 |
| Schmuckstück | 2,0 |
| Einhandwaffe, Schildhand, Distanzwaffe, alle Rüstungsteile | 1,5 |
| Hals, Umhang, Handgelenke, Ringe, Relikt | 1,0 |

- **Zweihandwaffe 3,0 statt 2,0**, damit zwei Einhandplätze (2 × 1,5) genau so
  viel kosten. Der Nutzer wollte ursprünglich 1H auf 1,0 senken — abgelehnt,
  weil eine Waffe dann weniger gekostet hätte als ein Brustteil.
- **Schmuckstücke 2,0**: in jeder Classic-Fassung überproportional stark und
  knapp, und am Tag 1 weiß niemand welche. Zwei Spitzenstücke summieren sich auf
  4,0 und kosten damit mehr als jede Waffenkonfiguration — genau das verhindert
  das Absahnen bei den umkämpftesten Gegenständen.
- **Distanzwaffe hoch auf 1,5**: Für Jäger das wichtigste Item überhaupt, lag im
  ersten Entwurf fälschlich bei den Relikten.
- **Kleine Slots auf 1,0 statt 0,5**: 7 % Prio-Kosten steuern zu wenig, wenn
  jemand systematisch die billigen Plätze abräumt. Kosten: Die Spreizung sinkt
  von 1:6 auf 1:3, das System bewegt sich Richtung „verbrauchte Vergaben"
  statt „Nutzen". Bewusst so entschieden.
- **Grobe Faktoren sind Absicht.** Jede Rüstwert-Korrektur von Hand ist eine
  Ermessensentscheidung — also das, was das System loswerden soll. Schultern und
  Hände liegen schon deshalb bei 1,5, weil dort die Tier-Teile sitzen.

### Verfall (§ 4)

- **10 % je Woche, beschlossen** (Nutzer: „erstmal“ — nach der ersten Raidstufe
  erneut prüfen). Halbwertszeit rund 6,6 Wochen. 15 % wären 4,3 Wochen.
- Auf die Erholung nach einem großen Gegenstand wirkt die Rate kaum (5 statt
  4 Wochen). Sie steuert die **Gedächtnislänge**, nicht die Erholung.
- Verfallstag hängt am **Raid-Reset**, nicht an einem festen Wochentag — so
  fällt er nicht zwischen die beiden Raidtage (Montag und Donnerstag).

### Neue Mitglieder (§ 5)

**Erst bewähren, dann vorne einsteigen.** Zwei Stufen über die **Gildenränge**
(Vorschlag des Nutzers, besser als die erste Fassung):

1. **Probe** (2–3 Wochen): nimmt an der Prio **nicht** teil, bekommt Ausrüstung wie
   ein Zweitchar — nur was sonst niemand will. **Kein Konto in dieser Zeit**,
   sonst sammelt er Einsatz ohne Rüstwert und hätte bei der Beförderung genau die
   absurde Prio, die unten beschrieben ist. Die Probezeit wird dadurch vergütet,
   dass er danach vorne einsteigt.
2. **Raider**: bekommt die **höchste Prio der Stammgruppe** als Startwert;
   praktisch Einsatz auf den Median, Rüstwert so gewählt, dass die Zielprio
   herauskommt. Nach dem ersten Gegenstand fällt er zurück und reiht sich ein.

💡 **Technischer Glücksfall:** `GetGuildRosterInfo` liefert den Gildenrang mit —
das Addon kann den Status direkt aus der Gilde lesen, statt eine eigene Liste zu
pflegen. Die Regel hängt an etwas, das die Gilde ohnehin führt.

⚠️ **Das war im ersten Entwurf falsch und ist ein lehrreicher Fehler.** Dort stand
nur ein Startwert für den *Einsatz* plus ein Mindest-Rüstwert von 100. Weil die
Prio ein Verhältnis ist, ergab das für einen Neuling **Prio 4,00** gegen 1,10 der
Stammgruppe — er hätte drei Gegenstände in Folge abgeräumt, die ersten drei die
fallen. **Wer nur eine der beiden Größen setzt, setzt in Wahrheit gar nichts.**
Gilt für jede künftige Sonderregel genauso.

Der Mindest-Rüstwert bleibt, aber nur noch als Untergrenze gegen Division durch
null.

**Systemstart ist ein Sonderfall ohne Regelbedarf:** Am ersten Raidtag der
Erweiterung stehen alle bei Einsatz null und Rüstwert am Minimum, haben also
dieselbe Prio — der erste Gegenstand wird ausgelost, ab dem zweiten trägt sich
das System selbst.

### Hauptrolle (§ 6)

Hieß im ersten Entwurf „Erst- und Zweitspec“. Der Nutzer hat den Begriff
korrigiert: Es ist **Raidrolle + Spezialisierung kombiniert**, weil keiner der
beiden Teile allein trägt — ein Feral-Druide kann Tank oder Schaden sein
(Rolle nötig), und ein Arkan-Magier braucht anderes als ein Feuer-Magier
(Spezialisierung nötig). Format: `Tank – Schutz-Paladin`, `Schaden – Arkan-Magier`.

- **Die Hauptrolle ist fest**, kein wöchentlicher Wechsel. ⚠️ Beim Wechsel bleibt
  der Rüstwert stehen — sonst wäre ein Rollenwechsel der bequemste Prio-Reset.
  Ausnahme, wenn die Gilde den Wechsel wünscht.
- **Zweitbedarf kostet gar keinen Rüstwert** (Nutzer-Entscheidung; mein Vorschlag
  war der halbe). Begründung: **er macht die Hauptrolle nicht stärker** — und man
  bekommt ihn ohnehin nur, wenn kein Hauptbedarf im Raum steht.

⚠️ **Nicht verwechseln — hier lag ich falsch und der Nutzer hat korrigiert.** Ich
hatte vorgeschlagen, „was sonst niemand will, kostet nichts“ sei derselbe
Gedanke. Ist es nicht. Zwei verschiedene Dinge:

  - **Wettbewerbslage** (wollen es mehrere?) entscheidet nur, *wer* es bekommt.
  - **Bedarfsart** (Haupt- oder Zweitbedarf?) entscheidet allein über den *Preis*.

  Gegenbeispiel des Nutzers: eine Nischenwaffe mit Stärke und Zaubermacht, die in
  der ganzen Gruppe nur zum Vergelter-Paladin passt. Alleiniger Interessent —
  aber für ihn ein volles Upgrade, also **voller Rüstwert**. Der Grundsatz:
  *Der Rüstwert misst, wie gut jemand ausgerüstet ist, nicht wie viele
  Mitbewerber er hatte.* Die Regel „was sonst niemand will, kostet nichts“ ist
  damit **verworfen** und nicht erneut vorzuschlagen.
- Das **Konto gehört dem Spieler, nicht dem Charakter**: Wer mit dem Zweitchar
  mitgeht, weil die Gruppe einen Heiler braucht, sammelt Einsatz normal. Gilt
  auch für die Präsenzerkennung (Twink online = anwesend).

**Noch nicht gelöst — steht jetzt als offener Punkt im Dokument:** Ein *kleines*
Upgrade für die Hauptrolle kostet weiterhin den vollen Rüstwert, also lehnen
Leute marginale Verbesserungen ab und das Teil landet in der Bank. Die einzige
saubere Lösung ist, den Rüstwert nach dem **Zuwachs** statt dem Vollwert zu
berechnen (Platzfaktor × Differenz zum ersetzten Teil) — braucht aber das Addon,
von Hand nicht praktikabel.

### Rolle des Rats (§ 7) und Sonderfälle (§ 8)

- **Rüstwert-Korrekturen** legt zunächst die **Raid- oder Gildenleitung** fest.
  Ein benannter Kreis zuverlässiger Spieler ist möglich, wird aber erst
  entschieden, wenn absehbar ist, wie viel Arbeit anfällt (Nutzer).
- **Überschreibungen: „Ausnahmen werden vor dem Raid angekündigt, nie im Moment
  der Vergabe entschieden.“** Ohne diese harte Kante wäre § 7 die Hintertür, durch
  die Loot Council zurückkommt — jede Vergabe lässt sich zur Ausnahme erklären.
  Der Unterschied liegt nicht im Inhalt, sondern im **Zeitpunkt**. Zulässig sind
  genau drei Anlässe: angekündigter Progress-Vorrang, erkennbarer Systemfehler,
  Regelverstoß.

**⭐ Legendäre Gegenstände stehen außerhalb der Ordnung** (Nutzer-Entscheidung,
Haltungsfrage): kein Rüstwert, keine Prio, die **Gildenleitung** entscheidet in
Ruhe. Begründung des Nutzers: *„Wer ein Legendäres Item bekommen soll, ist ein
Zeichen der Wertschätzung seitens der Gilde. Da sollen keine Zahlen etwas
vorgeben.“* Gilt auch für die Bestandteile.

⚠️ **Zwei Punkte, die daran hängen und leicht falsch gemacht werden:**

1. **Kein Rüstwert.** Würde eine Legendäre den vollen Preis kosten, stünde der
   Ausgezeichnete monatelang hinten — die Auszeichnung wäre faktisch eine Strafe.
2. **Gehört in § 8, nicht § 7.** § 7 heißt: Der Rat setzt sich über die Regel
   hinweg (wird gezählt und protokolliert). § 8 heißt: Die Regel gilt gar nicht
   erst. Sonst wäre die größte Auszeichnung der Gilde formal ein Regelbruch und
   tauchte in der Überschreibungs-Statistik auf.

### Pflichten und Offenlegung (§§ 9–10)

Vom Nutzer unverändert abgenommen („sind meiner Meinung nach okay so“).

- **§ 9:** Fläschchen, Verzauberungen, Verbrauchsgüter und ein reparierter
  Charakter sind **Voraussetzung, keine Punktequelle**. Als Pflicht formuliert,
  weil Bonuspunkte aus einer Selbstverständlichkeit eine Verhandlungssache machen
  würden.
- **§ 10:** Prio-Tabelle jederzeit einsehbar, jede Vergabe protokolliert,
  Auswertung am Ende jeder Raidstufe.

## Offene Punkte

Stehen auch im Dokument selbst, im Kasten am Ende:

1. **Eichwert K und Mindest-Rüstwert** — erst messbar, wenn die Gegenstandsstufen
   der ersten Raidstufe bekannt sind. Gehören zusammen gesetzt.
2. Verfallsrate nach der ersten Raidstufe erneut prüfen (10 % läuft)
3. Kleine Verbesserungen kosten vollen Preis — damit leben, bis das Addon den Zuwachs rechnet?
4. Rüstwert-Korrekturen später an einen benannten Kreis übergeben?
5. Deckel bei drei oder vier Raidtagen
6. Trägt die Gilde mit, dass niemand mehr entscheidet

## Nächste Schritte

1. **Anhang ergänzen** (noch nicht im Dokument, steht nur im Sitzungsverlauf):
   die drei Größen in Alltagssprache, die Fünf-Wochen-Tabelle **mit sichtbarer
   Mindestgrenze** und der Abend-für-Abend-Ablauf. Der Nutzer hat beides
   nachgefragt — wenn er als Autor danach fragt, braucht es die Gilde erst recht.
   ⚠️ Die erste Fassung der Tabelle war irreführend: Sie zeigte
   „100 × 0,9 + 90 = 190“, ohne dass der Mindest-Rüstwert dazwischen sichtbar war.
   Verfall und Zuwachs als **getrennte Schritte** darstellen.
2. **Der Gilde vorlegen** — der Entwurf ist vollständig genug.
3. **Am 17.09. messen** (Master Loot, Gildenlisten-API, Interface-Nummer), dann
   das Addon planen.

## Wie die Prio tatsächlich läuft

⚠️ **Die Prio wird laufend gerechnet — Boss für Boss, Gegenstand für Gegenstand.**
Nur der Verfall ist wöchentlich; Einsatz und Rüstwert werden fortlaufend gebucht.
Das Wochenmodell in `berechnungen.py` ist eine Vereinfachung für die Simulation
und hat den Nutzer beim Lesen verwirrt — im Regelwerk muss der laufende Ablauf
stehen.

Am ersten Abend haben alle dieselbe Prio, **der erste Gegenstand wird ausgelost**;
ab dem zweiten entscheidet die Prio von selbst, und nach je einem Stück sind zwei
Spieler exakt wieder gleichauf.

⭐ **Nebeneffekt für die Eichung:** Am Start liegt der Rüstwert bei der
Mindestgrenze, ein Gegenstand verdoppelt ihn also fast — die ersten Gegenstände
schlagen viel härter durch als spätere. Der Mindest-Rüstwert ist damit **nicht nur
eine Untergrenze, sondern der Startwert für alle** und bestimmt, wie ruckartig die
ersten Wochen laufen. Guter Grund, ihn nicht zu niedrig zu wählen.

## Ist das nicht nur eine komplizierte Strichliste?

Frage des Nutzers, und die Antwort ist: **im Kern ja.** Drei Zusätze kommen dazu,
jeder löst ein konkretes Problem einer reinen Strichliste:

| Zusatz | Was er verhindert |
|---|---|
| Gewichtung nach Platz | Dass ein Ring so viel zählt wie eine Zweihandwaffe |
| Teilen statt Abziehen | Dass Veteranen uneinholbar vorn stehen |
| Verfall | Dass ein Raid von vor einem Jahr so viel wiegt wie letzte Woche |

Das Teilen hat einen zweiten Grund: Beim Abziehen müsste festgelegt werden, wie
viele Einsatzpunkte ein Rüstwertpunkt wert ist — eine zusätzliche willkürliche
Konstante. Beim Teilen kürzt sich das weg.

⚠️ **Der praktische Knackpunkt, falls das System je zu schwer wirkt:** Für den
einzelnen Spieler ist es *nicht* komplex — er sieht eine Zahl und eine Reihenfolge.
Aber **von Hand ist es kaum führbar** (Verfall auf zwei Größen, Platzfaktoren,
laufende Buchung), und zum Beta-Start gibt es kein Addon. Der Fallback wäre ein
Tabellenblatt, das die Formel rechnet. Die diskutierte Sparversion — gewichtete
Strichliste ohne Verfall und ohne Teilen — liegt als Notausgang bereit, ist aber
nicht gewählt worden.

## Addon — noch nicht gebaut

Der Nutzer wollte zuerst das Regelwerk. Was feststeht:

- **Präsenzprüfung** ist der Grund, warum es ein Addon braucht:
  `GetGuildRosterInfo` liefert je Gildenmitglied ein `online`-Flag,
  `GetRaidRosterInfo` sagt, wer in der Gruppe ist. Momentaufnahme je Bosskampf →
  Bank wird nachgewiesen statt behauptet, und die Raidleitung bekommt eine
  Liste „online, nicht im Raid" als Einladungsvorschlag.
- **Anmeldedaten** könnten aus dem RaidPoster kommen (`../RaidPoster/`), der die
  Raid-Helper-Aufstellung schon per Discord-Bot holt und parst — Export-String
  ins Addon, Muster wie bei BT4ProfileShare.
- **Ledger** in SavedVariables, Sync über AddonMessage mit
  LibSerialize + LibDeflate.

### ❗ OFFENE FRAGE — zurückgestellt, nach den §§ zu klären

**Wie erkennt das Addon die ausgerüstete Rüstung?** Vom Nutzer aufgeworfen
(13.09.2026), bewusst vertagt, bis das Regelwerk fertig ist. Sein Hinweis auf
einen vorhandenen Ansatz: **Method Raid Tools** bietet eine *Raid-Inspection* an
— einmal ausgelöst, zieht das Addon die Ausrüstungsdaten aller Raidmitglieder.

Betrifft gleich mehrere Stellen: den Rüstwert eines Neulings (§ 5), den
Zuwachs-Ansatz gegen abgelehnte Kleinverbesserungen (§ 6) und die Warnung des
Bedarfsfensters bei falsch angemeldetem Zweitbedarf.

### ❗ OFFEN — Raids mit fremden Spielern („offener Modus“)

**Lücke im Regelwerk:** Fremde sind nirgends geregelt. Nach jetzigem Stand bekämen
sie nur, was kein Gildenmitglied für die Hauptrolle braucht (wie ein Zweitchar) —
wer das einmal mitmacht, füllt nie wieder auf.

**Idee des Nutzers (13.09.2026), noch nicht beschlossen:** Ein zweiter Betriebsmodus
mit **Würfeln als gemeinsamer Schnittstelle**, weil Fremde das Addon nicht haben:

- Addon-Nutzer klicken im Bedarfsfenster „Hauptrolle“ oder „Zweitbedarf“, das
  Addon löst daraufhin einen Wurf aus: **Hauptrolle = 1–100, Zweitbedarf = 1–50**.
- Fremde tippen einfach `/rnd 100` bzw. `/rnd 50` — kein Addon nötig.
- Das Addon liest die Würfe aus dem Chat mit und führt daraus die Strichliste;
  intern werden Einsatz und Rüstwert der Gildenmitglieder normal gebucht.

⚠️ **Drei Punkte, die vor der Umsetzung zu klären sind:**

1. **Der Wurfbereich darf nicht der Vergleichswert sein.** § 6 sagt, Hauptbedarf
   schlägt Zweitbedarf *immer*. Eine 48 auf den Fünfziger würde aber eine 30 auf
   den Hunderter schlagen. Die Auswertung muss **erst nach Kategorie, dann nach
   Zahl** sortieren; 100 gegen 50 ist nur ein sichtbarer Marker für Leute ohne
   Addon (alles über 50 ist zwangsläufig Hauptbedarf).
2. **Verhältnis Strichliste ↔ Würfel.** Vorschlag: Die Strichliste *begrenzt*, der
   Würfel *entscheidet* — erst würfeln alle, die an dem Abend noch nichts bekommen
   haben; danach die zweite Runde. Etablierte Pug-Regel, das Addon führt nur Buch.
3. **⭐ Die eigentliche offene Frage (Nutzer will sie vorerst offen halten):** Im
   offenen Modus zählt die aufgebaute Prio an dem Abend nicht. Wer sechs Wochen
   leer ausging und endlich vorn steht, verliert seinen Vorsprung an einen Fremden
   mit Glück. Zielkonflikt: **Entweder Fremde werden fair behandelt, oder die
   Stammgruppe behält ihren Vorrang — beides zugleich geht nicht.** Zwei Auswege
   standen im Raum: ganz oder gar nicht (ein Modus für den ganzen Abend) oder
   gestaffelt nach Anzahl der Gäste. In jedem Fall **vorher ansagen**.

🔧 **Technisch:** Das Würfelergebnis kommt als `CHAT_MSG_SYSTEM`. ⚠️ Den
deutschen Text **nicht hartkodieren** — Suchmuster aus der globalen Konstante
`RANDOM_ROLL_RESULT` bauen, sonst bricht es, sobald jemand mit englischem Client
mitkommt.

### Das Bedarfsfenster (Nutzer-Vorschlag)

Beim Drop öffnet sich bei allen in Frage kommenden Spielern ein Fenster — das
Muster, das die Gilde von **RCLootCouncil** kennt. Die Bedienung bleibt also
vertraut, nur die Entscheidung dahinter fällt anders. Inhalt:

| Zeile | |
|---|---|
| Gegenstand | Symbol, Name, Tooltip |
| **Deine Prio gerade** | z.B. 1,50 |
| **Was es dich kosten würde** | z.B. −18 %, danach 1,22 |
| Knöpfe | Hauptrolle · Zweitbedarf · Verzichten |
| Countdown | 60 s, danach gilt Verzicht (sonst wartet der Raid) |

Die Kostenzeile ist die eigentliche Neuerung: Wer im Moment der Entscheidung
sieht, was ihn der Gegenstand kostet, beschwert sich hinterher nicht über eine
Zahl, die er vorher nicht kannte.

Technisch unkritisch — normales Frame, keine geschützten Aktionen, also kein
Secure-Kram. Antwort per AddonMessage an den Master. Vorfilter nach Klasse und
Rüstungsart spart allen Zeit. ⚠️ Im Kampf nicht aufpoppen lassen.

⚠️ **Lücke, die das Fenster freilegt:** Weil Zweitbedarf nichts kostet, hat jeder
den Anreiz, ihn zu klicken. Beim Nischen-Gegenstand (nur ein Interessent) bekommt
man ihn so oder so — als Zweitbedarf angemeldet aber **gratis**. Damit wäre die
Entscheidung aus § 6 mit einem Klick umgangen. Zwei Gegenmittel, beide nötig:

1. **Das Addon warnt.** Es kennt die hinterlegte Hauptrolle und hält die Werte des
   Gegenstands dagegen (`GetItemStats` — in `../GearScout/` sind die Schlüssel
   bereits verifiziert). Passt der Gegenstand zur Hauptrolle, wird die Anmeldung
   markiert und die Raidleitung sieht es. **Keine harte Sperre**, weil es echte
   Grenzfälle gibt: Ein Zaubermacht-Teil taugt für Heiler und Schattenpriester.
2. **Das Protokoll ist öffentlich.** Wer etwas als Zweitbedarf nimmt und dann in
   der Hauptrolle trägt, fällt auf.

⚠️ **Erst messen, dann bauen** (siehe Memory `wow-forever-classic-plus`):

- Gibt es in WoW Forever noch **Master Loot**? Ohne ML muss die Vergabe über
  Gruppenloot und Handeln laufen — das ändert den halben Addon-Aufbau.
- Heißt es `GuildRoster()` oder `C_GuildInfo.GuildRoster()`? Retail-geprägte
  Kerne haben das verschoben.
- Die Gildenliste ist gedrosselt: nicht pollen, an `GUILD_ROSTER_UPDATE` hängen.
- **Twink-Problem:** Das Addon sieht Charakternamen, keine Spieler. Wer als Bank
  eingeteilt ist und mit dem Zweitchar online sitzt, gilt sonst als offline.
  Zuordnung nötig, Gildennotiz ist die naheliegende Quelle.

**Die Ordnung muss auch ohne Addon funktionieren** — zum Beta-Start wird es
keines geben. Deshalb steht im Dokument ausdrücklich, dass die Raidleitung die
Bank so lange von Hand vermerkt.

## Zusammenarbeit über Git

Repo: **`Kaos-WoW/loot-ordnung`** (privat), Branch `main`. Am Projekt arbeiten
mehrere Personen — der Nutzer, ein zweiter Entwickler und Claude-Sitzungen.

**⭐ Vor jedem Push `git fetch` und den Stand prüfen.** Dasselbe Problem wie bei
[[tbc-loot-prio-p3]]: Mehrere Schreiber auf `main` bedeuten, dass `origin` mitten
in der Arbeit vorausgelaufen sein kann.

⚠️ **Zwei Dinge, die beim Mitarbeiten leicht schiefgehen:**

1. **`loot-ordnung.html` ist zugleich die Quelle des veröffentlichten Artifacts.**
   Wer sie ändert, ändert nur die Datei — die veröffentlichte Seite bleibt auf dem
   alten Stand, bis jemand sie neu publiziert (mit der **URL** im Kopf dieser Datei,
   sonst entsteht ein zweites Artifact).
2. **Zahlen im Regelwerk und `berechnungen.py` müssen zusammenpassen.** Alle Werte
   im HTML stammen aus dem Skript. Wer eine Stellschraube dreht, lässt das Skript
   laufen und zieht die Zahlen im HTML nach — einschließlich der SVG-Koordinaten
   im Diagramm von § 4. Das Dokument lebt davon, nachrechenbar zu sein.

`.gitattributes` normalisiert Zeilenenden auf LF, damit Windows und Linux/Mac
sich nicht gegenseitig ganze Dateien als geändert anzeigen.

## Verwandtes im selben Verzeichnisbaum

- `../Loostliste/` — TBC-Loot-Sheet, Quelle der RCLootCouncil-Exportspalten
- `../Classic-Lootliste/` — Classic-Era-Klon davon
- `../TBC-Lootprio/` — simulierte ΔDPS-Werte je Spieler und Item; wäre die
  Pipeline, falls der Rüstwert später auf echten Zuwachs statt Gegenstandsstufe
  umgestellt wird
- `../RaidPoster/` — Raid-Einteilung mit Discord-Anbindung
