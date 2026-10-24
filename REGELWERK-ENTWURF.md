# KaosLoot – Regelwerk-Entwurf: Wertung und Vorrang

Stand 22.10.2026 (Bedienung der Gruppen vereinfacht: Raid-ID, zwei Listen) · **Alles umgesetzt** (Addon 1.1.0 auf WoW Forever). Seit dem 16.10. dazugekommen: mehrere Gruppen mit Einteilung, Bench und Wochenabschluss (§ 2 und § 6a).
Wie beim Golf: **Wer die niedrigste Wertung hat, hat Vorrang.** Gleichstand wird gewürfelt (höchster Wurf gewinnt).

## 0. Die Begriffe in einem Blick

| Begriff | Bedeutung |
|---|---|
| **Wertung** | die Zahl, nach der sortiert wird: erhaltene Main-Items + Zuschläge. Niedrig = zuerst |
| **Zuschlag** | Zahl, die für einen verpassten Abend auf die Wertung draufgerechnet wird |
| **Faktor** | bestimmt die Höhe des Zuschlags (Faktor × Schnitt des Abends) |
| **Schnitt des Abends** | vergebene Main-Items ÷ Spieler im Raid, meist etwa 1 |
| **Anhebung** | wird nur noch von Hand gesetzt: Niedrigster der anderen im Raid plus 2 (§ 3) |
| **Kader** | die Spieler der Gildenränge, die zum Raid gehören; wer nicht dazugehört, ist **Gast** |
| **Raidkader** | der Pool, den man per Knopf bis zu einem Gildenrang einliest und aus dem man die Gruppen zusammenklickt |
| **Einteilung** | wer an einem Raidtag in welcher Gruppe ist (**Gruppe 1, Gruppe 2 …**, **Bench** oder **Keine Meldung**); wer nirgends steht, gilt als abgemeldet |

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
| **Anwesend** (in der Einteilung der Gruppe und nicht anders markiert; das ist der Standard, auch wer die Gruppe vor dem Abschluss verlässt) | keiner, es zählen nur die erhaltenen Main-Items |
| **Bench** (in der Einteilung gesetzt; steht in der Abwesenheit jeder Gruppe, kann einspringen) | **Faktor 0** |
| **Abgemeldet** (im Raidkader, aber **in der Woche nirgends eingeteilt** – das Addon erkennt es von selbst, gebucht wird mit „Woche abschließen“, für **zwei Abende**) | **1. Fehlen 0,7 · 2. bis 4. Fehlen 1,0 · 5. Fehlen 1,3 · ab 6. Fehlen 1,5** |
| **Unentschuldigt** (eingeteilt, ohne Info nicht gekommen; Raidleiter oder Gildenleitung markiert in der Abwesenheit) | **sofort Faktor 1,5, mindestens 2 Wertungspunkte** |
| **Keine Meldung** (weder an- noch abgemeldet; in der Einteilung als Ziel „Keine Meldung“ gesetzt, früher „Anmeldung vergessen“) | **1. und 2. Mal in 8 Abenden wie abgemeldet, ab dem 3. Mal Faktor 1,5, mindestens 2 Wertungspunkte** |

- „n-tes Fehlen“ = Zahl der Fehlabende (abgemeldet, unentschuldigt, Keine Meldung) **innerhalb der letzten 6 Raidabende des Spielers**, den aktuellen mitgezählt. Es zählen nur **die eigenen Abende** eines Spielers; Abende einer anderen Gruppe, in denen er nicht vorkommt, schieben sein Fenster nicht weiter. Die Bench ist kein Fehlen.
- Der Zuschlag wird **am Abend selbst festgeschrieben** und bleibt danach bestehen. Das Fenster zählt nur, welche Stufe der *nächste* verpasste Abend bekommt. Wer abwechselnd fehlt und kommt, rutscht trotzdem hoch.
- Jeder Zuschlag ist im Spielerdetail sichtbar (Abend, Faktor, Grund).
- **Keine Meldung** (weder an- noch abgemeldet): Wer so eingeteilt ist, bekommt beim Wochenabschluss das 1. und 2. Mal innerhalb von 8 Raidabenden die Wertung einer normalen Abmeldung, ab dem 3. Mal wie unentschuldigt. Das lässt sich mit „Woche zurücknehmen“ korrigieren.
- „Unentschuldigt“ kann zurückgenommen werden, wenn es einen guten Grund gab (zum Beispiel ein Unfall): vor dem Abschluss durch Entfernen der Markierung, danach über „Abend wiedereröffnen“.

## 3. Die Anhebung – nur noch von Hand

**Seit dem 19.10.2026 gibt es keine automatische Anhebung mehr.** Die Zuschläge für verpasste Abende (§ 2) reichen aus. Die frühere Regel (wer mehr als 1 Punkt unter dem Niedrigsten liegt, kommt zu Beginn des Abends auf *Niedrigster plus 2*) hat auch Spieler getroffen, die jeden Abend dabei waren und nur Pech beim Würfeln hatten. Das war als Strafe nicht gewollt.

**Manuelle Anhebung:** Die Raid- oder Gildenleitung kann einen Spieler anheben, zum Beispiel nach einer sehr langen Pause. Das geht unter **Einstellungen → Gruppen → Anhebung** (Namen eintragen, „Anheben“) oder mit **`/kl anhebung <Name>`**. Der Spieler kommt auf *den Niedrigsten der anderen Kaderspieler im Raid plus 2*, nie nach unten (liegt er schon dort oder höher, passiert nichts). Die Anhebung steht im Spielerdetail und geht an alle.

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
| Anwesenheit | automatisch | **Standard = anwesend:** Wer in der Einteilung der Gruppe steht und nicht als Bank, Abwesend oder Unentschuldigt markiert ist, gilt als anwesend und zählt im Schnitt mit. Die Raidleitung muss nur die Ausnahmen markieren (Entscheid des Nutzers 22.10.2026: weniger zu verwalten, kein Zeitdruck beim Abschluss); es gibt keine „offenen“ Spieler mehr, der Abend lässt sich jederzeit abschließen |
| **Bench** | wer einteilen darf | Ziel „Bench“ in der **Einteilung**; in der Abwesenheit holt ein Klick den Spieler in die Gruppe |
| **Einteilen, Woche abschließen** | Stufe 1 und 2 (Gildenmeister, Offiziere) und die weiteren Ränge bis zur eingestellten Grenze | Ansicht „Einteilung“ |
| **Unentschuldigt** | Gildenleitung | Eintrag mit Name und Zeit in der Abwesenheit, für alle sichtbar; zurücknehmen darf die Gildenleitung |
| **Keine Meldung** | wer einteilen darf | Ziel „Keine Meldung“ in der **Einteilung**; gebucht beim Wochenabschluss |
| **Stammgast aufnehmen** | Gildenleitung | von Hand im Addon in den Kader |
| **Einstellungen setzen und teilen** | Stufe 1 und 2 immer; weitere Ränge bis zur Grenze | wie bei „Einstellungen teilen“. Die Grenze selbst ändern nur Stufe 1 und 2. Alle anderen sehen die geteilten Einstellungen nur zum Lesen und werden beim Anmelden auf den offiziellen Stand zurückgesetzt |
| Abweichende Vergabe | wer zuteilt | wird im **Raidchat** und in der **Historie** als „abweichend vom Ergebnis“ gekennzeichnet |

Der Plündermeister trägt nichts ein, was die Wertung verändert.

## 6a. Mehrere Gruppen: Einteilung, Bench, Wochenabschluss

Die Gruppen setzen sich Woche für Woche neu zusammen. Darum gibt es keine festen Kader je Gruppe, sondern eine **Einteilung**.

- **Raidkader:** Alle Gildenmitglieder bis zu einem gewählten Gildenrang. Das Addon liest ihn beim Anmelden von selbst ein (und auf Knopfdruck); der Rang ist eine **geteilte Einstellung**. Die Gruppen selbst brauchen keinen eigenen Abgleich.
- **Raid-ID:** Eine Raid-ID ist eine Woche und beginnt an einem einstellbaren Wochentag (Standard **Mittwoch**, geteilte Einstellung). Die Einteilung gilt **einmal je Raid-ID**, nicht je Tag.
- **Einteilung:** Je Raid-ID steht jeder Spieler in **genau einer** Gruppe, auf der **Bench** oder bei **Keine Meldung**; er kann nie gleichzeitig in Gruppe 1 und Gruppe 2 stehen. In der Ansicht „Einteilung“ wählt man das Ziel in einer **Ausklappliste**; links stehen die Spieler, die noch nirgends zugewiesen sind, rechts die, die schon im Ziel stehen. Wer schon irgendwo zugewiesen ist (Gruppe, Bench, Keine Meldung), erscheint in den anderen Rubriken nicht mehr. Wer nur an einem Tag kann, kommt auf die Bench, wenn kein Platz ist. Die Einteilung geht an alle mit dem Addon. **Abwesenheit und Einteilung sehen nur Spieler mit Schreibrecht** (Gildenrang laut Einstellungen, § 6); alle anderen haben nur „Spieler“ und „Verlauf“.
- **Bench:** Spieler auf der Bench haben **Faktor 0** und stehen in der Abwesenheit jeder Gruppe, damit man sie einspringen lassen kann. Ein Klick holt sie in die aktive Gruppe; in der Einteilung nimmt man sie bei der Bench heraus und weist sie dann einer Gruppe zu.
- **Abgemeldet:** Wer in der Woche nirgends eingeteilt ist, braucht keinen Eintrag: Das Addon erkennt ihn als abgemeldet.
- **Wochenabschluss:** Nach dem letzten Gruppenabend der Woche bucht die Gildenleitung mit **„Woche abschließen“** (zweimal klicken, die Vorschau steht im Chat) die Abmeldungen und die „Keine Meldung“ der Woche. **Jeder dieser Spieler bekommt Zuschläge für zwei Abende.** Der Schnitt je Abend ist das **Mittel der Schnitte der Gruppen** für diese Abend-Nummer: der erste Abend jeder Gruppe zusammen, dann der zweite. Wer an einem Gruppenabend dabei war oder irgendwo (Gruppe, Bench) eingeteilt war, bekommt nichts.
- **Anwesenheit einer Gruppe:** Man wählt die Gruppe in der Ausklappliste. Sie zeigt die Eingeteilten dieser Gruppe und die Bench, mit ihrem Status (anwesend, Bench, abwesend, unentschuldigt). Jede Zeile hat drei Knöpfe: **Bank/Bench**, **Abwesend** und **Unentschuldigt**. Wer nicht markiert ist, gilt als anwesend. Eingeteilte sind nie „offen“, der Abschluss geht jederzeit.
- **Neuen Abend beginnen:** Nach dem Abschluss macht dieser Knopf die Liste frei, ohne die gebuchten Wertungen anzutasten. „Abend wiedereröffnen“ nimmt dagegen den Abschluss samt Zuschlägen zurück.

## 7. Einstellungen (setzt eine Person der Gildenleitung, werden an alle geteilt)

Faktoren je Fehlen 0,7 / 1,0 / 1,0 / 1,0 / 1,3 / 1,5 · Fenster 6 Abende (eigene Abende des Spielers) · Unentschuldigt Faktor 1,5, mindestens 2 Punkte · Bench 0 · Anhebung (Niedrigster der Kaderspieler im Raid + 2) · Keine Meldung (ab dem 3. Mal in 8 Abenden wie unentschuldigt) · Raidtage je Gruppe · Rangstufe (Stufe 1 und 2 immer, weitere Ränge einstellbar).
Die Rangstufe selbst können nur Stufe 1 und 2 ändern.

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

Nichts mehr offen (alle Punkte bis 18.10.2026 beantwortet). Festlegungen zum Schluss:
1. **OS nach Absprache:** Vergibt der Plündermeister ein OS-Item nach der Absprache im Raid, steht im Raidchat und in der Historie neutral „OS nach Absprache“ statt „abweichend vom Ergebnis“.
2. **Rückgabe:** Mit „Zuschlag“ bei der Rückgabe war der **Punkt des Items** gemeint, nicht der Zuschlag für verpasste Abende.
3. **Raidet jemand in einer anderen Gruppe, als er eingeteilt ist,** ist das Sache der Raidleitung: Sie baut die Gruppen vorher so, dass es nicht vorkommt. Das Addon macht dafür keine Sonderregel.

---

## § 9 Verteilung: zwei Verfahren (Version 1.1.0, 24.10.2026)

Die Leitung wählt in den Einstellungen unter **Verteilung**, wie die Wertung zustande kommt. Die Wahl gilt für alle. Beide Verfahren rechnen aus derselben Historie, man kann jederzeit wechseln.

**Punkte mit Zuschlägen** ist das Verfahren aus den Paragraphen 1 bis 8 (Items plus Zuschläge für verpasste Abende, dazu Anhebungen).

**Items pro Abend**
- Wertung = Items pro besuchtem Abend der letzten **8 Raid-IDs** (einstellbar), **gleitend**: Jede Woche fällt die älteste ID heraus, es gibt keinen Reset zur neuen Phase.
- Besucht heißt: im Abschluss des Abends als *im Raid* geführt. Bank und Abgemeldet zählen nicht als besucht. Fehlen kostet nichts.
- Neue Spieler und Rückkehrer starten am Gildenschnitt: Die Rechnung mischt *k* Pseudo-Abende (Standard 4) mit dem Schnitt der Gilde bei. Proberaid, Anhebung und der Wochenabschluss entfallen in diesem Verfahren.
- Rechnung: *(Items im Fenster + Korrektur + Gildenschnitt × k) ÷ (besuchte Abende + k)*. Der heutige Abend zählt mit, wenn der Spieler im Raid ist. Beispiel: 5 Items in 10 Abenden bei einem Gildenschnitt von 0,55 ergibt (5 + 0,55 × 4) ÷ (10 + 4) = 0,51.
- OS-Items und Entzaubern zählen wie bisher nicht.

**Heute schon ein Item** (beide Verfahren, Standard *streng*)
- *Streng:* Wer an diesem Abend schon ein Main-Item bekommen hat, steht bei den weiteren Items hinter allen, die noch keins haben. Die Wertung ordnet nur noch unter denen mit gleich vielen Items heute. Würfeln nur Spieler, die alle schon eins haben, entscheidet wieder die Wertung.
- *Leicht:* Jedes Item von heute zählt für den Rest des Abends etwas extra (0,5 Punkte bzw. 0,15 Items pro Abend).
- *Aus:* Nur die Wertung entscheidet.
- „Heute“ sind die letzten 12 Stunden.

**Korrektur der Leitung** (beide Verfahren)
- Ein Wert zwischen -20 und +20 (nicht 0) mit **Pflichtkommentar**, eingetragen von Gildenmeister, Offizieren oder der Leitung mit Schreibrecht: `/kl korrektur <Name> <Wert> <Kommentar>`, im Spielerdetail der Knopf *Korrektur* oder in den Einstellungen unter Verteilung.
- Plus zählt wie ein erhaltenes Item (zum Beispiel unangekündigt nicht erschienen, Legendary außerhalb des Systems), Minus wie ein verrechnetes (besondere Leistung).
- Alle sehen sie im Spielerdetail mit Datum, Kommentar und Name der Leitung. Sie zählt in der Raid-ID, in der sie eingetragen wurde, und fällt nach 8 IDs mit allem anderen aus dem Fenster. Zurücknehmen ist eine Gegenbuchung.

**Keine Item-Gewichte:** Alle Main-Items zählen gleich (Entscheid der Leitung, 24.10.2026). Für Sonderfälle gibt es die Korrektur.

**Alle in der Gruppe brauchen dieselbe Version (1.1.0):** Sonst ordnen die Addons unterschiedlich.
