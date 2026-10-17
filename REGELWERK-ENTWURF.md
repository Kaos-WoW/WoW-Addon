# Fairshare – Regelwerk-Entwurf: Wertung und Vorrang

Stand 16.10.2026 · **Alle Punkte geklärt, noch nichts gebaut.**
Wie beim Golf: **Wer die niedrigste Wertung hat, hat Vorrang.** Gleichstand wird gewürfelt (höchster Wurf gewinnt).

## 0. Die Begriffe in einem Blick

| Begriff | Bedeutung |
|---|---|
| **Wertung** | die Zahl, nach der sortiert wird: erhaltene Main-Items + Zuschläge. Niedrig = zuerst |
| **Zuschlag** | Zahl, die für einen verpassten Abend auf die Wertung draufgerechnet wird |
| **Faktor** | bestimmt die Höhe des Zuschlags (Faktor × Schnitt des Abends) |
| **Schnitt des Abends** | vergebene Main-Items ÷ Spieler im Raid, meist etwa 1 |
| **Anhebung** | Wer weit unter allen anderen liegt, wird zu Beginn des Abends einmal auf den Niedrigsten plus 2 gesetzt (§ 3) |
| **Kader** | die Spieler der Gildenränge, die zum Raid gehören; wer nicht dazugehört, ist **Gast** |

## 1. Die Wertung

> **Wertung = erhaltene Main-Items + Zuschläge für verpasste Abende**

- Jedes erhaltene Main-Item erhöht die Wertung um **1 Punkt**, **von Anfang an**, über alle Contentphasen. Wer immer im Raid dabei ist, bekommt keine künstliche Erhöhung: Seine Wertung wächst allein durch die Menge der erhaltenen Main-Items.
- **Kein Punkt** gibt es für ein entzaubertes Item und für unvollständige Einträge (ohne Gewinner oder Zeitstempel).
- **Rückgabe eines Items** (auch nach Abschluss des Abends): Der Punkt des ersten Empfängers wird wieder abgezogen, **sobald der Plündermeister das Item neu vergeben hat**; der neue Empfänger bekommt den Punkt. Kann das Item nicht mehr vergeben werden (zum Beispiel nicht mehr handelbar oder verloren), ist es ein **verlorenes Item**, und der erste Empfänger **behält den Punkt.**
- Der **Schnitt des Abends ändert sich dadurch nie**, weil das Item in beiden Fällen weiter als vergeben zählt. Schon festgeschriebene Zuschläge für verpasste Abende müssen deshalb nie neu berechnet werden.
- **Alle starten bei 0**, sobald der erste Raidabend mit der neuen Regel beginnt. Keine Startwerte, keine alte Anwesenheit. Einträge aus den Testtagen zählen nicht.
- Ein Raidabend zählt nur, wenn er aufgezeichnet wurde (Aufzeichner war dabei, Addon aktiv).
- Reihenfolge je Item: **Main vor OS → niedrigste Wertung → bei Gleichstand höchster Wurf.** Für OS gilt § 5.

## 2. Zuschläge für verpasste Abende

Nur für Kaderspieler. Jeder Zuschlag = **Faktor × Schnitt des Abends** und wird auf die Wertung draufgerechnet.
Gegenüber dem Schnitt der Anwesenden gilt: **Faktor unter 1 = Vorteil, 1,0 = neutral, über 1 = Malus.**

| Situation am Abend | Zuschlag |
|---|---|
| **Im Raid** (am Abendende in der Gruppe, oder vorher ein Main-Item bekommen) | keiner, es zählen nur die erhaltenen Main-Items |
| **Bank** (von Raidleiter, Gildenleiter oder Offizier eingetragen, nachweislich online) | **Faktor 0** |
| **Abgemeldet** (Kader, nicht im Raid, nicht Bank – die Standardannahme) | **1. Fehlen 0,7 · 2. bis 4. Fehlen 1,0 · 5. Fehlen 1,3 · ab 6. Fehlen 1,5** |
| **Unentschuldigt** (Gildenleiter oder Offizier trägt ein) | **sofort Faktor 1,5, mindestens 2 Wertungspunkte** |
| **Anmeldung vergessen** (Gildenleitung trägt ein) | **1. und 2. Mal in 8 Abenden wie abgemeldet, ab dem 3. Mal Faktor 1,5, mindestens 2 Wertungspunkte** |

- „n-tes Fehlen“ = Zahl der Fehlabende (abgemeldet **und** unentschuldigt) **innerhalb der letzten 6 Raidabende**, den aktuellen mitgezählt. Die Bank ist kein Fehlen.
- Der Zuschlag wird **am Abend selbst festgeschrieben** und bleibt danach bestehen. Das Fenster zählt nur, welche Stufe der *nächste* verpasste Abend bekommt. Wer abwechselnd fehlt und kommt, rutscht trotzdem hoch.
- Jeder Zuschlag ist im Spielerdetail sichtbar (Abend, Faktor, Grund).
- **Anmeldung vergessen** (weder an- noch abgemeldet und nicht erschienen): Die Gildenleitung trägt „Vergessen“ ein. Das 1. und 2. Mal innerhalb von 8 Raidabenden gilt der Abend wie eine normale Abmeldung, ab dem 3. Mal wie unentschuldigt. Auch das lässt sich zurücknehmen.
- „Unentschuldigt“ kann zurückgenommen werden, wenn es einen guten Grund gab (zum Beispiel ein Unfall): vor dem Abschluss durch Entfernen der Markierung, danach über „Abend wiedereröffnen“.

## 3. Die Anhebung – wer weit zurückliegt, kommt hinter die anderen

**Warum:** Wer nach langer Abwesenheit weit hinter allen anderen liegt, soll nicht sofort das erste Item sicher bekommen. Im Lauf des Abends kann er trotzdem ein Item bekommen, wenn eines droppt, das er braucht, und seine Berechtigung die oberste ist.

**Regel:** Zu Beginn des Abends (beim ersten Bosskampf) schaut das Addon auf alle Kaderspieler im Raid. Liegt jemand **mehr als 1 Punkt unter dem Niedrigsten der anderen Kaderspieler**, wird seine Wertung einmalig auf *deren Niedrigsten plus 2* gesetzt. Dieser Wert gilt von da an dauerhaft und ist im Spielerdetail als „Anhebung“ sichtbar.

**Folge:** Der angehobene Spieler steht 2 Punkte hinter den Niedrigsten und gewinnt nicht als Erster. Sobald die anderen Items bekommen haben und über ihm liegen (das kann nach ein bis zwei Bossen schon so sein), ist er an der Reihe. Die Anhebung gibt es **nur einmal je Abend**, sie hebt nur an und senkt nie. Wer schon mehr Items hat, liegt höher und wird nicht angehoben.

## 4. Neue Spieler und Gäste

**Neuer Kaderspieler** (wer nach dem ersten Abend mit der neuen Regel zum Kader kommt; der Kader, der am **ersten Abend** steht, gilt als eingespielt und hat weder Proberaid noch einen Neuling-Start)
- **1. Raidabend = Proberaid:** Er raidet mit, hat aber **keine Lootberechtigung** (kein Würfeln auf Items) und bekommt noch keinen Zuschlag.
- **2. Raidabend:** Er wird auf die Wertung des Niedrigsten der Kaderspieler im Raid **plus 2** gesetzt (wie bei der Anhebung, § 3). Er bekommt also nicht sofort das erste Item, kann aber im Lauf des Abends eines bekommen, sobald die anderen über ihm liegen. Die bestehenden Spieler werden nicht benachteiligt, nur weil ein Neuer dabei ist. Danach gilt für ihn alles wie für jeden anderen.

**Gast** (nicht im Kader)
- Gäste werden **nur mitgenommen, wenn wir intern einen Raid nicht vollständig besetzen können.**
- Für den Abend bekommt er **dieselbe Wertung wie der Spieler mit der niedrigsten Wertung**, damit er die Chance auf ein Item hat.
- **Nach dem Abend wird er aus der Wertungsliste entfernt.** Die Items, die er bekam, bleiben in der Historie.
- **Stammgast:** Wer öfter mitraidet, wird von der Gildenleitung **von Hand im Addon in den Kader aufgenommen** und zählt dann im normalen System mit. **Für ihn entfällt das Proberaid.** Die Main-Items, die er als Gast bekommen hat, bleiben in der Historie und zählen weiter.
- **Wird ein Stammgast Gildenmitglied**, wird seine Wertung, die er zu diesem Zeitpunkt hat, **nahtlos übernommen.** Er bekommt weder ein neues Proberaid noch einen Neustart bei 0.

## 5. OS (Zweitrolle)

- OS wird **nur vergeben, wenn niemand auf Main würfelt.**
- Würfelt jemand auf OS, der **im Raid öfter in seiner Zweitrolle aushilft**, wird das **im Moment im Raid besprochen.** Das Addon beurteilt und erkennt das nicht.
- Hat niemand mitgewürfelt, der öfter in der Zweitrolle dabei ist, geht das Item an den mit den **weniger OS-Items**, bei Gleichstand an den **höheren Wurf.**
- OS-Items zählen getrennt und verändern die Main-Wertung nicht. Zuschläge gibt es für OS nicht.

## 6. Wer was darf

„**Gildenleitung**“ = Spieler ab einer **Rangstufe**, die einstellbar ist (Gildenleiter und Offiziere). Technisch nutzt das die bestehende Rangprüfung von „Einstellungen teilen“.

| Was | Wer | Wie |
|---|---|---|
| Anwesenheit | automatisch | Am Abendende: wer dann im Raid steht, ist anwesend; Bosskämpfe zählen nicht. Wer früher geht, gilt als abwesend (außer er hat vorher ein Main-Item bekommen) und kann als unentschuldigt markiert werden |
| **Bank** | **Raidleiter oder Gildenleitung** | Haken in der Liste „online, nicht im Raid“; Addon prüft, dass der Spieler online war. Nachträglich änderbar bis zum nächsten Raid, jede Änderung mit Name und Zeit protokolliert |
| **Unentschuldigt** | Gildenleitung | Eintrag mit Name und Zeit, für alle sichtbar; zurücknehmen darf die Gildenleitung |
| **Anmeldung vergessen** | Gildenleitung | Knopf „Vergessen“ in der Liste, wie bei Unentschuldigt; zurücknehmbar |
| **Stammgast aufnehmen** | Gildenleitung | von Hand im Addon in den Kader |
| **Einstellungen setzen und teilen** | Gildenleitung | wie bei „Einstellungen teilen“ |
| Abweichende Vergabe | wer zuteilt | wird im **Raidchat** und in der **Historie** als „abweichend vom Ergebnis“ gekennzeichnet |

Der Plündermeister trägt nichts ein, was die Wertung verändert.

## 7. Einstellungen (setzt eine Person der Gildenleitung, werden an alle geteilt)

Faktoren je Fehlen 0,7 / 1,0 / 1,0 / 1,0 / 1,3 / 1,5 · Fenster 6 Abende · Unentschuldigt Faktor 1,5, mindestens 2 Punkte · Bank 0 · Anhebung (Niedrigster der Kaderspieler im Raid + 2) · Anmeldung vergessen (ab dem 3. Mal in 8 Abenden wie unentschuldigt) · Rangstufe der Gildenleitung.
Wer die Rangstufe ändern darf, bestimmt dieselbe Rangprüfung: nur wer ohnehin senden darf.

## 8. Beispiele

Immer dieselben vier Spieler: **Kaos, Shadow, Canu, Protti.** Zahlen sind Wertungen.

**Beispiel 1 – Normaler Abend.** Alle sind da. Wertungen: Kaos 3, Shadow 3, Canu 2, Protti 4.
- Item 1: Canu hat die niedrigste Wertung (2) und gewinnt. Er steht danach bei 3.
- Item 2: Kaos, Shadow und Canu stehen alle bei 3 → der höchste Wurf entscheidet. Protti (4) ist hinten.

**Beispiel 2 – Rückkehrer nach drei Wochen.** Protti fehlt 3 Abende hintereinander (abgemeldet). Davor hatten alle 6. Kaos, Shadow und Canu spielen weiter und bekommen im Schnitt je 1 Item pro Abend, stehen also jetzt bei **9**.
- Protti: 6 Items + Zuschläge (0,7 + 1,0 + 1,0 = 2,7) = **8,7**.
- Protti liegt 0,3 unter den anderen und gewinnt **Item 1 sicher** (8,7 → 9,7). Danach steht er hinter den anderen, und Item 2 und 3 werden unter Kaos, Shadow und Canu ausgewürfelt. Ohne die Regel hätte Protti (6) alle neuen Items gewonnen, bis er bei 9 gewesen wäre.

**Beispiel 3 – Bank und Anhebung.** Shadow hatte 6 und saß 3 Abende auf der Bank (kein Zuschlag). Die anderen stehen bei 9.
- Shadow liegt 3 Punkte darunter. Das ist zu weit: Er wird zu Beginn des Abends einmal auf **11** gesetzt (9 plus 2).
- Item 1 bis 3: Die drei Spieler bei 9 würfeln untereinander, Shadow wartet. Erst wenn sie über 11 liegen, ist er an der Reihe.
- Ohne Anhebung hätte Shadow alle drei Items gewonnen (6 → 9).

**Beispiel 4 – Bank hilft nicht, wenn man schon mehr hat.** Canu hatte 8 Items und saß 2 Abende auf der Bank (kein Zuschlag), er bleibt bei 8. Kaos (vorher 5) und Shadow (vorher 6) spielten und bekamen je 2 Items dazu: Kaos 7, Shadow 8.
- Kaos (7) gewinnt vor Canu (8). Canu und Shadow stehen gleich (8) → es wird gewürfelt.
- Eine Anhebung gibt es nicht, weil Canu nicht darunter liegt, sondern darüber.

**Beispiel 5 – Jeden zweiten Abend fehlen (z. B. wegen Spätschicht).** Protti fehlt (abgemeldet) an Raidabend 2, 4, 6 und 8, an 1, 3, 5 und 7 ist er da.
- Abend 2: 1. Fehlen in den letzten 6 Abenden → Faktor 0,7.
- Abend 4: 2. Fehlen → Faktor 1,0.
- Abend 6: 3. Fehlen → Faktor 1,0.
- Abend 8: wieder höchstens 3 Fehlen im Fenster (Abend 4, 6, 8) → Faktor 1,0.
- Er wird also **nie in die Strafstufe** (ab dem 5. Fehlen) gerutscht und liegt mit Faktor 1,0 genau auf dem Schnitt: kein Malus, aber auch kein dauerhafter Vorteil.
- Fehlt er dagegen 5 der letzten 6 Abende, gilt beim 5. Fehlen Faktor 1,3 und ab dem 6. Faktor 1,5.

**Beispiel 6 – Unentschuldigt.** Kaos fehlt, ohne sich abzumelden, die Gildenleitung trägt es ein. Die anderen bekamen an dem Abend im Schnitt 1 Item, Kaos bekommt **sofort Faktor 1,5, mindestens aber 2 Wertungspunkte**: bei Schnitt 1 sind das 2,0 statt 0,7 bei einer normalen Abmeldung. Er liegt damit 1,0 über dem Schnitt (Malus). Stellt sich später heraus, dass es einen guten Grund gab (zum Beispiel ein Unfall), nimmt die Gildenleitung den Eintrag zurück. Der Abend zählt auch als Fehlen im Fenster der letzten 6 Abende.

**Beispiel 7 – Neuer Kaderspieler.** Canu kommt neu in den Kader.
- Abend 1 (Proberaid): Er raidet mit, darf aber nicht auf Items würfeln. Kein Zuschlag.
- Abend 2: Die anderen stehen bei 9, 10 und 11. Canu wird auf die niedrigste Wertung plus 2 gesetzt, also auf **11**. Er gewinnt nicht als Erster; sobald Kaderspieler Items bekommen haben und über 11 liegen, ist er an der Reihe.

**Beispiel 8 – Gast.** Protti ist nicht im Kader und raidet als Gast mit. Im Raid: Kaos 5, Shadow 4, Canu 6.
- Die niedrigste Wertung ist 4 (Shadow). Protti wird für den Abend ebenfalls auf **4** gesetzt, steht also gleichauf mit Shadow, der Wurf entscheidet.
- Nach dem Abend wird Protti aus der Liste entfernt. Raidet er öfter mit, nimmt die Gildenleitung ihn von Hand in den Kader auf.

**Beispiel 9 – Item zurückgegeben.** Shadow bekommt ein Main-Item (Wertung +1) und gibt es am nächsten Tag zurück.
- Vergibt der Plündermeister es neu an Canu: Shadow −1, Canu +1. Der Schnitt des Abends bleibt gleich.
- Kann es nicht mehr vergeben werden (verloren): Shadow behält den Punkt.

**Beispiel 10 – Anmeldung vergessen.** Protti war an zwei Abenden weder an- noch abgemeldet und fehlte. Beide Male galt das wie eine normale Abmeldung (Zuschlag 0,7 und 1,0). Am dritten Abend innerhalb der letzten 8 Raidabende passiert es wieder.
- Die Gildenleitung trägt „Vergessen“ ein. Weil es jetzt das 3. Mal ist, gilt Faktor 1,5, mindestens aber 2 Wertungspunkte: Zuschlag **2,0**.
- Hätte Protti es erst das 2. Mal vergessen, wäre es bei der normalen Staffel geblieben.

## 9. Noch offen

Nichts mehr offen (alle Punkte am 16.10.2026 beantwortet). Zwei Festlegungen zum Schluss:
1. **OS nach Absprache:** Vergibt der Plündermeister ein OS-Item nach der Absprache im Raid, steht im Raidchat und in der Historie neutral „OS nach Absprache“ statt „abweichend vom Ergebnis“.
2. **Rückgabe:** Mit „Zuschlag“ bei der Rückgabe war der **Punkt des Items** gemeint, nicht der Zuschlag für verpasste Abende.
