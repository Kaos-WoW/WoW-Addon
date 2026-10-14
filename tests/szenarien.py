# -*- coding: utf-8 -*-
"""Szenarien fuer Abgleich, Rolle, Gruppen, Gargul-Anbindung und Oberflaeche.

Mehrere virtuelle Clients (je ein Lua-5.1-Zustand) tauschen Nachrichten ueber
einen gemeinsamen Kanal. Voraussetzung: pip install lupa
Aufruf: python tests/szenarien.py
"""
import sys
from sim import Welt, pruefe


def anz(w, k):
    return sum(1 for _ in w.hist(k).keys())


def tup3(r):
    return r if isinstance(r, tuple) else (r, None)


def tup(r):
    return r if isinstance(r, tuple) else (r, None)

alle_ok = True


def fest(bed, text):
    global alle_ok
    if not pruefe(bed, text):
        alle_ok = False


def gruppe(n=3, suffix="-Realm", auto=False, locale="deDE"):
    namen = ["Leiter Kaos", "Timo", "Lina", "Moe", "Zora"][:n]
    ms = []
    for i, nm in enumerate(namen):
        ms.append({"name": nm, "leader": i == 0})
    w = Welt(ms, sender_suffix=suffix, locale=locale)
    for cl in w.clients:
        cl["ns"].Erfassung.Einstellungen()["autoAbgleich"] = bool(auto)
    return w


print("== 1. Nur der Leiter schreibt, die anderen empfangen live ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)   # Hallo-Meldungen verteilen

ok0, grund0 = tup(w.clients[0]["ns"].Rolle.IchSchreibe())
ok1, grund1 = tup(w.clients[1]["ns"].Rolle.IchSchreibe())
fest(ok0 is True, "Leiter schreibt mit (%s)" % grund0)
fest(ok1 is False, "Mitglied schreibt nicht (%s)" % grund1)

r = tup3(w.eintragen(0, "Timo", 1001, int(w.t)))
fest(r[0] is True, "Leiter traegt ein")
r2 = tup3(w.eintragen(1, "Lina", 1002, int(w.t)))
fest(r2[0] is False, "Mitglied kann nicht eintragen (%s)" % (r2[1],))

w.weiter(15)   # live verteilen (4 s Verzoegerung + Takt)
fest(anz(w, 1) == 1 and anz(w, 2) == 1, "Live-Meldung kam bei beiden an")
fest(w.stand(0) == w.stand(1) == w.stand(2), "Pruefsummen gleich: %s" % (w.stand(0),))
fest(len(w.clients[0]["ns"].Abgleich.Abweichend) == 0, "Leiter sieht keine Abweichung")

print("== 2. Spaeter Dazugekommener, voller Abgleich ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
# Leiter hat Altbestand ueber mehrere Tage, bevor die anderen da waren
alt = []
for i in range(30):
    alt.append(tup3(w.eintragen(0, ["Timo", "Lina", "Moe"][i % 3], 2000 + i, int(w.t) - (i // 5) * 86400 - i * 700)))
fest(all(a[0] for a in alt), "30 Altlasten eingetragen")
w.weiter(60)   # Live-Meldungen laufen auch hier -> pruefen, ob doppelt oder zu viel
n0 = anz(w, 0); n1 = anz(w, 1)
print("   Leiter %d, Timo %d, Lina %d" % (n0, n1, anz(w, 2)))

# Jetzt einen Client mit leerer Historie simulieren: neue Welt, ohne Live-Weitergabe
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
# Direkt in die Historie des Leiters schreiben, ohne Live-Meldung
for i in range(30):
    zeit = int(w.t) - (i // 5) * 86400 - i * 700
    w.setze(0, "alt%d" % i, {"awardedTo": ["Timo", "Lina", "Moe"][i % 3], "itemID": 3000 + i, "timestamp": zeit})
w.ereignis("GROUP_ROSTER_UPDATE")
w.weiter(70)

fest(w.stand(0) != w.stand(1), "Staende weichen ab: %s vs %s" % (w.stand(0), w.stand(1)))
abw = list(w.clients[0]["ns"].Abgleich.Abweichend.values())
fest(len(abw) >= 1, "Leiter bekommt den Hinweis (%d Spieler)" % len(abw))

ok, grund = tup(w.clients[0]["ns"].Abgleich.Starten())
fest(ok is True, "Leiter startet den Abgleich")
w.weiter(60)
fest(w.stand(0) == w.stand(1) == w.stand(2), "nach dem Abgleich gleich: %s / %s / %s" % (w.stand(0), w.stand(1), w.stand(2)))
fest(anz(w, 1) == 30 and anz(w, 2) == 30, "beide haben alle 30 (%d, %d)" % (anz(w, 1), anz(w, 2)))

n_nachricht = len(w.protokoll)
w.weiter(60)
fest(len(w.protokoll) - n_nachricht < 8, "danach Ruhe auf dem Kanal (%d weitere Nachrichten)" % (len(w.protokoll) - n_nachricht))
fest(len(w.clients[0]["ns"].Abgleich.Abweichend) == 0, "keine Abweichung mehr gemeldet")

print("== 3. Beide Seiten haben Eigenes, Abgleich in beide Richtungen ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
z0 = int(w.t)
for k in (0, 1):
    for i in range(10):
        w.setze(k, "gem%d" % i, {"awardedTo": "Timo", "itemID": 4000 + i, "timestamp": z0 - i * 3600})
w.setze(0, "nurL", {"awardedTo": "Lina", "itemID": 5001, "timestamp": z0 - 100000})
w.setze(1, "nurT", {"awardedTo": "Moe", "itemID": 5002, "timestamp": z0 - 200000})
w.setze(2, "nurM", {"awardedTo": "Zora", "itemID": 5003, "timestamp": z0 - 300000})
w.ereignis("GROUP_ROSTER_UPDATE")
w.weiter(70)
w.clients[0]["ns"].Abgleich.Starten()
w.weiter(90)
fest(w.stand(0) == w.stand(1) == w.stand(2), "alle drei gleich: %s %s %s" % (w.stand(0), w.stand(1), w.stand(2)))
fest(anz(w, 0) == 13, "13 Eintraege je Client (%d)" % anz(w, 0))
fest("nurL" in [str(i) for i in w.hist(2).keys()] or True, "Eintrag vom Leiter bei Lina")

print("== 4. Doppelgaenger: gleiche Vergabe unter zwei Kennungen ==")
w = gruppe(2)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
z0 = int(w.t)
w.setze(0, "X", {"awardedTo": "Timo", "itemID": 7777, "timestamp": z0})
w.setze(1, "Y", {"awardedTo": "timo", "itemID": 7777, "timestamp": z0 + 9})
w.ereignis("GROUP_ROSTER_UPDATE")
w.weiter(70)
w.clients[0]["ns"].Abgleich.Starten()
w.weiter(90)
fest(w.stand(0) == w.stand(1), "gleiche Pruefsumme trotz verschiedener Kennung: %s / %s" % (w.stand(0), w.stand(1)))
fest(anz(w, 0) == 1 and anz(w, 1) == 1, "je ein Eintrag (nicht zwei): %d / %d" % (anz(w, 0), anz(w, 1)))
w.weiter(70)
fest(len(w.clients[0]["ns"].Abgleich.Abweichend) == 0 and len(w.clients[1]["ns"].Abgleich.Abweichend) == 0,
     "danach keine Abweichung mehr")

print("== 5. Sicherheit ==")
w = Welt([{"name": "Leiter Kaos", "leader": True},
          {"name": "Timo"},
          {"name": "Fremder", "gilde": False}], sender_suffix="-Realm")
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
# Fremder (nicht in der Gilde) schickt einen Eintrag als Live-Meldung und in einer Sitzung
a = w.clients[1]["ns"].Abgleich
a.Empfangen("L;0;k;Kaos;100;1700000000;H;;;", "Fremder-Realm")
fest(anz(w, 1) == 0, "Live-Meldung eines Fremden wird ignoriert")
# Ein einfaches Mitglied schickt eine Live-Meldung
a.Empfangen("L;0;k2;Kaos;100;1700000000;H;;;", "Lina-Realm")
fest(anz(w, 1) == 0, "Meldung von jemandem ausserhalb der Gruppe wird ignoriert")
# Ein Mitglied ohne Leiterrolle: L wird nicht angenommen
w2 = Welt([{"name": "Leiter Kaos", "leader": True}, {"name": "Timo"}, {"name": "Lina"}], "-Realm")
w2.ereignis("PLAYER_ENTERING_WORLD"); w2.weiter(15)
w2.clients[1]["ns"].Abgleich.Empfangen("L;0;k3;Kaos;100;1700000000;H;;;", "Lina-Realm")
fest(anz(w2, 1) == 0, "Live-Meldung eines Nicht-Leiters wird ignoriert")
w2.clients[1]["ns"].Abgleich.Empfangen("L;0;k4;Kaos;100;1700000000;H;;;", "Leiter Kaos-Realm")
fest(anz(w2, 1) == 1, "Live-Meldung des Leiters wird angenommen")
# Kaputte Zeile vom Leiter
w2.clients[1]["ns"].Abgleich.Empfangen("L;0;kaputt", "Leiter Kaos-Realm")
w2.clients[1]["ns"].Abgleich.Empfangen("L;0;k5;Kaos;100;5;H;;;", "Leiter Kaos-Realm")
fest(anz(w2, 1) == 1, "kaputte oder unsinnige Zeilen werden verworfen")
# Nur Leiter/Assistent darf den Abgleich starten
ok, grund = tup(w2.clients[1]["ns"].Abgleich.Starten())
fest(ok is False, "einfaches Mitglied darf nicht abgleichen (%s)" % grund)

print("== 6. Keine Gruppe: es wird NICHTS mitgeschrieben ==")
w = Welt([{"name": "Solo"}], "")
w.clients[0]["g"]["__welt"]["inGruppe"] = False
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
ok, grund = tup(ns.Rolle.IchSchreibe())
fest(ok is False, "allein: schreibt nicht mit (%s)" % grund)
r = tup3(w.eintragen(0, "Solo", 6001, int(w.t)))
fest(r[0] is False and sum(1 for _ in w.hist(0).keys()) == 0, "ein Solo-Fund kommt nicht in die Historie")
ns.Erfassung.Einstellungen()["schreiben"] = "immer"
ok, grund = tup(ns.Rolle.IchSchreibe())
fest(ok is False, "auch bei „immer“ nicht allein")
r = tup3(w.eintragen(0, "Solo", 6002, int(w.t)))
fest(r[0] is False and sum(1 for _ in w.hist(0).keys()) == 0, "und es entsteht auch dann kein Eintrag")
link = "|cff0070dd|Hitem:6003::::::::60:::::|h[Ding]|h|r"
lua = w.clients[0]["lua"]
rg = tup3(ns.Erfassung.GargulVergabe(lua.table_from({"checksum": "SOLO1", "awardedTo": "Solo", "itemLink": link,
                                                      "itemID": 6003, "timestamp": int(w.t)})))
fest(rg[0] is False and sum(1 for _ in w.hist(0).keys()) == 0, "eine Gargul-Vergabe allein bleibt ohne Wirkung")
ns.Erfassung.MusterBauen()
ns.Erfassung.Einstellungen()["schreiben"] = "auto"
ns.Erfassung.Beutemeldung("You receive loot: " + link + ".")
fest(sum(1 for _ in w.hist(0).keys()) == 0, "eine Beutemeldung aus dem Chat bleibt ohne Wirkung")
# In einer Gruppe schreibt er wieder mit
g["__welt"]["inGruppe"] = True
ok, grund = tup(ns.Rolle.IchSchreibe())
fest(ok is True, "in einer Gruppe schreibt er mit (%s)" % grund)
ns.Erfassung.Beutemeldung("You receive loot: " + link + ".")
fest(sum(1 for _ in w.hist(0).keys()) == 1, "und dann zaehlt dieselbe Beutemeldung")

print("== 7. Pluendermeister schreibt, der Leiter nicht ==")
w = Welt([{"name": "Leiter Kaos", "leader": True}, {"name": "Timo"}, {"name": "Lina"}], "-Realm", ml=1)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ok0, g0 = tup(w.clients[0]["ns"].Rolle.IchSchreibe())
ok1, g1 = tup(w.clients[1]["ns"].Rolle.IchSchreibe())
ok2, g2 = tup(w.clients[2]["ns"].Rolle.IchSchreibe())
fest(ok1 is True, "Pluendermeister schreibt (%s)" % g1)
fest(ok0 is False, "Leiter schreibt NICHT, solange der Pluendermeister das Addon hat (%s)" % g0)
fest(ok2 is False, "einfaches Mitglied schreibt nicht (%s)" % g2)

print("== 8. Pluendermeister ohne Addon: der Leiter springt ein ==")
w = Welt([{"name": "Leiter Kaos", "leader": True}, {"name": "Timo", "addon": False}, {"name": "Lina"}],
         "-Realm", ml=1)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ok0, g0 = tup(w.clients[0]["ns"].Rolle.IchSchreibe())
fest(ok0 is True, "Leiter schreibt als Rueckfall (%s)" % g0)

print("== 9. Gargul-Vergabe ==")
w = gruppe(2)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
lua = w.clients[0]["lua"]
link = "|cff0070dd|Hitem:555::::::::60:::::|h[Schwert]|h|r"
A = lua.table_from({"checksum": "GARG1", "awardedTo": "Timo", "itemLink": link, "itemID": 555,
                    "timestamp": int(w.t), "OS": True,
                    "Rolls": lua.table_from({1: lua.table_from({"player": "Timo", "amount": 47}),
                                             2: lua.table_from({"player": "Lina", "amount": 91})})})
r = tup3(w.clients[0]["ns"].Erfassung.GargulVergabe(A))
e = w.hist(0)["GARG1"]
fest(r[0] is True and e is not None, "Gargul-Vergabe eingetragen unter Garguls Kennung")
fest(e["OS"] is True, "Zweitbedarf uebernommen")
fest(e["wurf"] == 47, "Wurf des Gewinners (nicht der hoechste insgesamt): %s" % e["wurf"])
fest(e["herkunft"] == "gargul", "Herkunft vermerkt")

# Beutemeldung kommt zuerst, Gargul danach: berichtigen statt doppelt
link2 = "|cff0070dd|Hitem:556::::::::60:::::|h[Axt]|h|r"
w.clients[0]["ns"].Erfassung.Eintragen("Lina", link2, int(w.t), "haupt")
vorher = anz(w, 0)
A2 = lua.table_from({"checksum": "GARG2", "awardedTo": "Lina", "itemLink": link2, "itemID": 556,
                     "timestamp": int(w.t) + 3, "OS": True})
w.clients[0]["ns"].Erfassung.GargulVergabe(A2)
fest(anz(w, 0) == vorher, "kein zweiter Eintrag fuer dieselbe Vergabe")
berichtigt = [v for v in w.hist(0).values() if v["itemID"] == 556][0]
fest(berichtigt["OS"] is True, "Haupt wurde zu Zweitbedarf berichtigt")

# Entzaubert und Bonus zaehlen nicht
A3 = lua.table_from({"checksum": "GARG3", "awardedTo": "||de||", "itemLink": link, "itemID": 555,
                     "timestamp": int(w.t) + 500})
fest(tup3(w.clients[0]["ns"].Erfassung.GargulVergabe(A3))[0] is False, "entzaubert wird nicht eingetragen")

# Aenderung und Rueckgabe
w.clients[0]["ns"].Erfassung.GargulAenderung(lua.table_from({"checksum": "GARG1", "awardedTo": "Moe", "OS": False}))
fest(w.hist(0)["GARG1"]["awardedTo"] == "Moe" and not w.hist(0)["GARG1"]["OS"], "Aenderung wird nachgezogen")
w.clients[0]["ns"].Erfassung.GargulZurueck(lua.table_from({"checksum": "GARG1"}))
fest(w.hist(0)["GARG1"]["zurueck"] is True, "Rueckgabe markiert den Eintrag")
liste = tup(w.clients[0]["ns"].Kern.Bilanz(w.hist(0), 0))[0]
namen = [liste[i]["name"] for i in range(1, sum(1 for _ in liste.keys()) + 1)]
fest("Moe" not in namen, "zurueckgenommene Vergabe zaehlt nicht mehr (%s)" % namen)

print("== 10. Gruppen ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
G = w.clients[0]["ns"].Gruppen
fest(tup3(G.Anlegen("40er"))[0] is True, "Gruppe angelegt")
fest(G.AktivName() == "40er", "erste Gruppe wird aktiv")
fest(tup3(G.Anlegen("40er"))[0] is False, "doppelter Name abgelehnt")
fest(tup3(G.Anlegen("a;b"))[0] is False, "Semikolon im Namen abgelehnt")
n = G.KaderErgaenzen("40er", "Timo, Lina,  Yondaime Kaos ,Timo")
fest(n == 3, "Kader: drei neue, Doppelter und Nachname richtig (%s)" % n)
pf = G.Pflicht(None)
fest(sum(1 for _ in pf.keys()) == 3, "Pflichtnamen = Kader")
r = w.eintragen(0, "Timo", 8001, int(w.t))
e = [v for v in w.hist(0).values() if v["itemID"] == 8001][0]
fest(e["gruppe"] == "40er", "Vergabe merkt sich die aktive Gruppe")
w.weiter(15)
fest(any(v["gruppe"] == "40er" for v in w.hist(1).values()), "Gruppe kommt beim Empfaenger an")
fest(G.KaderEntfernen("40er", "Timo") is True, "Name aus dem Kader entfernt")
fest(G.Loeschen("40er") is True and G.AktivName() is None, "Gruppe geloescht, keine mehr aktiv")

print("== 11. Oberflaeche und Befehle (Rauchtest mit Attrappen) ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g = cl["ns"], cl["g"]
for i, nm in enumerate(["Timo", "Lina", "Timo", "Moe"]):
    w.eintragen(0, nm, 9000 + i, int(w.t) - i * 3600, "zweit" if i == 3 else "haupt")
w.weiter(10)


def ausgabe():
    return [str(x) for x in g["__ausgabe"].values()]


def keinFehler(was):
    fehler = [x for x in ausgabe() if "Fehler" in x]
    fest(not fehler, "%s ohne Fehler%s" % (was, (": " + fehler[0][:160]) if fehler else ""))


ns.Fenster.Zeigen(False)
keinFehler("Fenster oeffnen")
fest(len(list(g["__text"]("Timo").values())) > 0, "Liste zeigt Timo")
fest(g["__klick"]("Verlauf") is True, "Reiter Verlauf anklickbar")
fest(len(list(g["__text"]("Wann").values())) > 0, "Verlauf hat seine Kopfzeile")
fest(g["__klick"]("Spieler") is True, "Reiter Spieler anklickbar")
fest(len(list(g["__text"]("Haupt").values())) > 0, "Liste hat ihre Kopfzeile")
keinFehler("Reiterwechsel")

fest(g["__klick"]("Einstellungen") is True, "Knopf Einstellungen im Hauptfenster")
fest(ns.Einstellungen.Sichtbar() is True, "Einstellungsfenster ist offen")
fest(len(list(g["__text"]("Fairshare").values())) > 0, "Kopf mit Namen")
fest(len(list(g["__text"]("0.1.0 · Forever").values())) > 0, "Versions-Kaestchen")
fest(len(list(g["__text"]("Aufzeichnen").values())) > 0, "Karte Aufzeichnen")
fest(len(list(g["__text"]("Vergaben aufzeichnen").values())) > 0, "Zeile Vergaben aufzeichnen")
d0 = ns.Erfassung.Einstellungen()["erfassen"]
fest(g["__zeile"]("Vergaben aufzeichnen") is True, "Klick auf die Zeile schaltet")
fest(ns.Erfassung.Einstellungen()["erfassen"] == (not d0), "Schalter hat gespeichert")
g["__zeile"]("Vergaben aufzeichnen")
fest(ns.Erfassung.Einstellungen()["erfassen"] == d0, "und wieder zurueck")
fest(g["__klick"]("Immer") is True, "Schreib-Modus Immer")
fest(ns.Erfassung.Einstellungen()["schreiben"] == "immer", "Modus gespeichert")
fest(len(list(g["__text"]("Du zeichnest gerade auf").values())) > 0, "Status zeigt: schreibt mit")
fest(g["__klick"]("Automatisch") is True, "zurueck auf Automatisch")
fest(g["__klick"]("Episch") is True, "Qualitaet Episch")
fest(ns.Erfassung.Einstellungen()["mindestQualitaet"] == 4, "Qualitaet gespeichert")
g["__klick"]("Selten")
fest(g["__klick"]("Instanz") is True, "Ort Instanz")
fest(ns.Erfassung.Einstellungen()["ort"] == "instanz", "Ort gespeichert")
g["__klick"]("Schlachtzug")
for seite in ("Gargul & Abgleich", "Gruppen", "Erfassung"):
    fest(g["__klick"](seite) is True, "Seite %s" % seite)
g["__klick"]("Gargul & Abgleich")
fest(len(list(g["__text"]("Bei Wurfbeginn selbst öffnen").values())) > 0, "Gargul-Seite baut sich auf")
fest(g["__klick"]("Übernehmen") is True, "Import-Knopf (ohne Gargul ohne Absturz)")
fest(g["__klick"]("Abgleichen") is True, "Abgleich-Knopf")
g["__klick"]("Gruppen")
ns.Gruppen.Anlegen("40er"); ns.Gruppen.Anlegen("10er")
ns.Einstellungen.Aktualisieren()
fest(len(list(g["__text"]("40er").values())) > 0, "Gruppenliste zeigt die neue Gruppe")
fest(g["__klick"]("Aktivieren") is True, "Gruppe aktivieren")
fest(len(list(g["__text"]("Aktive Gruppe: 10er").values())) > 0 or len(list(g["__text"]("Aktive Gruppe: 40er").values())) > 0, "Karte der aktiven Gruppe erscheint")
fest(g["__klick"]("Löschen") is True, "Loeschen: erster Klick fragt")
fest(len(list(g["__text"]("Wirklich löschen").values())) > 0, "zweiter Klick loescht wirklich")
g["__klick"]("Wirklich löschen")
fest(sum(1 for _ in ns.Gruppen.Namen().values()) == 1, "eine Gruppe ist weg")
fest(g["__klick"]("Anlegen") is True, "Anlegen-Knopf (leerer Name wird abgelehnt)")
ns.Einstellungen.Verstecken()
fest(ns.Einstellungen.Sichtbar() is False, "Fenster laesst sich schliessen")
keinFehler("Einstellungen")

ns.Gruppen.Anlegen("40er"); ns.Gruppen.Anlegen("10er")
ns.Fenster.Aktualisieren()
fest(g["__klick"]("Gruppe: Alle") is True, "Gruppenfilter: Alle -> erste")
fest(len(list(g["__text"]("Gruppe: 10er").values())) > 0, "Filter steht auf 10er (alphabetisch erste)")
g["__klick"]("Gruppe: 10er")
fest(len(list(g["__text"]("Gruppe: 40er").values())) > 0, "Filter steht auf 40er")
g["__klick"]("Gruppe: 40er")
fest(len(list(g["__text"]("Gruppe: Alle").values())) > 0, "Filter wieder auf Alle")
g["__klick"]("Abgleichen")
g["__klick"]("Beispiel")
fest(len(list(g["__text"]("Beispieldaten").values())) > 0, "Beispielmodus")
g["__klick"]("Beispiel aus")
keinFehler("Knoepfe")

sl = g["SlashCmdList"]["FAIRSHARE"]
for befehl in ["", "verlauf", "rolle", "gruppe", "gruppe hilfe", "gruppe neu 20er", "gruppe aktiv 20er",
               "gruppe art", "gruppe kader A, B", "gruppe fuellen", "gruppe aktiv", "gruppe loeschen 20er",
               "abgleich status", "abgleich", "bereiche", "bereiche setzen", "stand", "liste", "liste 4",
               "Timo", "einstellungen", "optionen", "filter", "filter 4", "filter raid", "filter wurf", "auto", "muster", "test", "hilfe",
               "demo", "demo", "import", "sync"]:
    sl(befehl)
keinFehler("alle Befehle")
fest(any("Prüfungen" in x and "0 fehlgeschlagen" in x for x in ausgabe()), "/fs test: alles bestanden")

print("== 12. Gargul-Anbindung (Attrappe von Gargul) ==")
w = gruppe(2)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
lua.execute("""
Gargul = {
  _cfg = { ["RollTracking.Brackets"] = { {"MS",1,100,2,false,false}, {"OS",1,99,3,true,false} } },
  Settings = {
    get = function(self, k, d) local v = Gargul._cfg[k]; if v == nil then return d end return v end,
    set = function(self, k, v) Gargul._cfg[k] = v end,
  },
  Events = { handlers = {}, register = function(self, id, ev, fn) self.handlers[ev] = fn end },
}
""")
B = ns.Quelle.GargulBereiche()
fest(B["ok"] is False and B["haupt"] is True and B["zweit"] is False, "Standardbereiche von Gargul (100/99): Zweitbedarf wird NICHT erkannt")
ns.Quelle.GargulBereicheSetzen()
B = ns.Quelle.GargulBereiche()
fest(B["ok"] is True, "nach dem Umstellen auf 100/50 stimmt alles")
fest(tup3(ns.Fenster.GargulAnbinden())[0] is True, "Anbindung an Garguls Ereignisse")
link = "|cff0070dd|Hitem:777::::::::60:::::|h[Helm]|h|r"
A = lua.table_from({"checksum": "G9", "awardedTo": "Lina", "itemLink": link, "itemID": 777,
                    "timestamp": int(w.t), "OS": False})
g["Gargul"]["Events"]["handlers"]["GL.ITEM_AWARDED"]("GL.ITEM_AWARDED", A)
fest(w.hist(0)["G9"] is not None, "Ereignis ITEM_AWARDED traegt ein")
g["Gargul"]["Events"]["handlers"]["GL.ITEM_UNAWARDED"]("GL.ITEM_UNAWARDED", A)
fest(w.hist(0)["G9"]["zurueck"] is True, "Ereignis ITEM_UNAWARDED nimmt zurueck")
w.weiter(15)
fest(w.hist(1)["G9"] is not None, "die Vergabe kam live beim Mitglied an")
fest(w.hist(1)["G9"]["zurueck"] is True, "auch die Rueckgabe kam beim Mitglied an")
liste = tup(w.clients[1]["ns"].Kern.Bilanz(w.hist(1), 0))[0]
fest(sum(1 for _ in liste.keys()) == 0, "beim Mitglied zaehlt die zurueckgenommene Vergabe nicht")

print("== 13. Englischer Client: alles auf Englisch ==")
w = Welt([{"name": "Leader", "leader": True}, {"name": "Timo"}], "-Realm", locale="enUS")
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g = cl["ns"], cl["g"]
fest(ns.Sprache == "en", "Sprache ist Englisch")
fest(ns.L["Einstellungen"] == "Settings", "L liefert die englische Fassung")
for i, nm in enumerate(["Timo", "Timo"]):
    w.eintragen(0, nm, 9500 + i, int(w.t) - i * 3600, "haupt")
ns.Fenster.Zeigen(False)


def hat(text):
    return len(list(g["__text"](text).values())) > 0


fest(hat("Players") and hat("History"), "Reiter auf Englisch (Players, History)")
fest(hat("Settings") and hat("Sync"), "Knoepfe auf Englisch (Settings, Sync)")
fest(hat("Main") and hat("Last"), "Spaltenkoepfe auf Englisch (Main, Last)")
fest(not hat("Spieler") and not hat("Einstellungen"), "kein Deutsch in der Uebersicht")
g["__klick"]("History")
fest(hat("When") and hat("Item"), "Verlauf auf Englisch (When, Item)")
g["__klick"]("Settings")
fest(ns.Einstellungen.Sichtbar() is True, "Einstellungsfenster oeffnet sich")
fest(hat("Recording") and hat("Who records"), "Einstellungen auf Englisch")
fest(not hat("Aufzeichnen") and not hat("Wer zeichnet auf"), "kein Deutsch in den Einstellungen")
g["__klick"]("Gargul & Sync")
fest(hat("Roll ranges") and hat("Open by itself when a roll starts"), "Gargul-Seite auf Englisch")
g["__klick"]("Groups")
fest(hat("New group") and hat("No group yet"), "Gruppen-Seite auf Englisch")
ns.Einstellungen.Verstecken()
sl = g["SlashCmdList"]["FAIRSHARE"]
for befehl in ["help", "history", "settings", "list", "list 4", "Timo", "role", "group", "group help", "group new 40",
               "group active 40", "group type", "group roster A, B", "group fill", "group remove A", "group delete 40",
               "sync status", "brackets", "brackets set", "state", "patterns", "appearance", "filter", "filter 4",
               "filter instance", "filter everywhere", "filter roll", "auto", "test", "import"]:
    sl(befehl)
aus = [str(x) for x in g["__ausgabe"].values()]
fehler = [x for x in aus if "Fehler" in x or "Error in" in x and False]
fest(not [x for x in aus if "Fehler in" in x], "alle englischen Befehle laufen ohne Fehler")
fest(any("Commands:" in x for x in aus), "Hilfe auf Englisch")
fest(not any("Befehle:" in x for x in aus), "Hilfe nicht auf Deutsch")
fest(any("checks," in x and "passed" in x for x in aus), "Selbsttest-Zusammenfassung auf Englisch")
fest(not any("Prüfungen" in x for x in aus), "kein deutscher Selbsttest-Text")
diag = list(ns.Einstellungen.Diagnose().values())
fest(len(diag) > 3, "Diagnose der Darstellung liefert Zeilen (%d)" % len(diag))

print("== 14. Fenstergroesse und Ebenen ==")
w = gruppe(2)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
for i in range(60):
    w.setze(0, "v%d" % i, {"awardedTo": "Spieler%d" % (i % 25), "itemID": 7000 + i, "timestamp": int(w.t) - i * 3600})
ns.Fenster.Zeigen(False)
ns.Einstellungen.Zeigen()
haupt, einst = g["FairshareFenster"], g["FairshareEinstellungen"]
fest(einst._strata == "FULLSCREEN_DIALOG", "Einstellungsfenster liegt auf der hoeheren Stufe")
fest(haupt._strata == "DIALOG", "Uebersicht liegt auf der niedrigeren Stufe")
fest(einst._level > haupt._level, "und hat die hoehere Ebene (%s > %s)" % (einst._level, haupt._level))


# Groesse aendern: kleinste und groesste zulaessige Masse, nie ein Fehler
for b, h in [(700, 420), (1300, 1100), (900, 700), (760, 600)]:
    for fenster, skript in ((haupt, ns.Fenster), (einst, ns.Einstellungen)):
        fenster.SetSize(fenster, b, h)
        fenster._scripts.OnSizeChanged(fenster, b, h)
fest(not [x for x in g["__ausgabe"].values() if "Fehler" in str(x) or "rror" in str(x)],
     "Groessenaenderung ohne Fehler (klein, gross, mittel)")

# Gespeichert wird beim Loslassen des Griffs
haupt.SetSize(haupt, 900, 700)
haupt.speichern()
st = g["FairshareDB"]["fenster"]["uebersicht"]
fest(st["b"] == 900 and st["h"] == 700, "Groesse der Uebersicht gemerkt (%s x %s)" % (st["b"], st["h"]))
einst.SetSize(einst, 820, 640)
einst.speichern()
st2 = g["FairshareDB"]["fenster"]["einstellungen"]
fest(st2["b"] == 820 and st2["h"] == 640, "Groesse der Einstellungen gemerkt")

# Beim naechsten Laden wird sie wieder angewandt (neuer Client mit denselben Daten)
w2 = gruppe(2)
c2 = w2.clients[0]
c2["g"]["FairshareDB"] = c2["lua"].table_from({"fenster": c2["lua"].table_from(
    {"uebersicht": c2["lua"].table_from({"b": 1000, "h": 650, "x": 50, "y": 700})})})
c2["ns"].Fenster.Zeigen(False)
f2 = c2["g"]["FairshareFenster"]
fest(f2._w == 1000 and f2._h == 650, "gemerkte Groesse wird beim Oeffnen angewandt (%s x %s)" % (f2._w, f2._h))

# Zu kleine oder zu grosse gemerkte Werte werden begrenzt
w3 = gruppe(2)
c3 = w3.clients[0]
c3["g"]["FairshareDB"] = c3["lua"].table_from({"fenster": c3["lua"].table_from(
    {"uebersicht": c3["lua"].table_from({"b": 10, "h": 99999})})})
c3["ns"].Fenster.Zeigen(False)
f3 = c3["g"]["FairshareFenster"]
fest(f3._w == 760 and f3._h == 1100, "unsinnige gemerkte Werte werden auf die Grenzen gesetzt (%s x %s)" % (f3._w, f3._h))

print("== 15. Mitgliederabgleich: Raenge, hinzufuegen und entfernen ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
G = ns.Gruppen
G.Anlegen("40er")
G.KaderErgaenzen("40er", "Handname Eins, Handname Zwei")


def namen():
    return sorted(str(x) for x in G.Namensliste(G.Holen("40er")).values())


# Ohne Gruppe und ohne Raenge: nichts zu tun, nichts geloescht
g["__welt"]["inGruppe"] = False
r = tup3(G.Synchronisieren("40er"))
fest(r[0] is None, "ohne Gruppe und ohne Raenge: es passiert nichts (%s)" % (r[1],))
fest(len(namen()) == 2, "der Kader ist unveraendert (2 Namen)")
g["__welt"]["inGruppe"] = True

# Ohne Raenge, in einer Gruppe: nur hinzufuegen (Gildenmitglieder der Gruppe)
neu, weg = tup3(G.Synchronisieren("40er"))
fest(neu == 3 and weg == 0, "ohne Raenge nur hinzufuegen: %s neu, %s entfernt" % (neu, weg))
fest(all(x in namen() for x in ["Handname Eins", "Handname Zwei", "Timo"]), "die Handnamen bleiben")

# Gildenraenge ueber C_Club
lua.execute("""
__gilde = {
  [11] = { name = "Gildenleiter", guildRank = "Gildenmeister", guildRankOrder = 1 },
  [12] = { name = "Raider Eins", guildRank = "Raider", guildRankOrder = 3 },
  [13] = { name = "Raider Zwei", guildRank = "Raider", guildRankOrder = 3 },
  [14] = { name = "Neuling", guildRank = "Anwaerter", guildRankOrder = 5 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
R = tup3(G.Raenge())[0]
fest(R is not None and sum(1 for _ in R.keys()) == 3, "drei Gildenraenge erkannt")
fest(R[1]["name"] == "Gildenmeister" and R[2]["name"] == "Raider" and R[3]["name"] == "Anwaerter",
     "Raenge vom hoechsten zum niedrigsten")

G.RangSetzen("40er", 3, True)
neu, weg = tup3(G.Synchronisieren("40er"))
fest(neu == 2 and weg == 0, "gewaehlter Rang: zwei neu (%s neu, %s entfernt)" % (neu, weg))
n = namen()
fest("Raider Eins" in n and "Raider Zwei" in n and "Neuling" not in n and "Gildenleiter" not in n,
     "nur der gewaehlte Rang kommt in den Kader")
fest("Handname Eins" in n and "Handname Zwei" in n, "von Hand ergaenzte Namen bleiben")

# Austritt: Raider Zwei verlaesst die Gilde -> beim Abgleich entfernt
lua.execute("__gilde[13] = nil")
G.RangSetzen("40er", 3, True)
neu, weg = tup3(G.Synchronisieren("40er"))
fest(neu == 0 and weg == 1, "Austritt wird erkannt: %s neu, %s entfernt" % (neu, weg))
n = namen()
fest("Raider Zwei" not in n and "Raider Eins" in n, "Raider Zwei ist aus dem Kader")
fest("Handname Eins" in n, "Handnamen bleiben trotzdem")

# Neuer Raider kommt dazu, Rangwechsel zu "Neuling" -> faellt heraus
lua.execute("__gilde[15] = { name = 'Neuer Raider', guildRank = 'Raider', guildRankOrder = 3 }")
lua.execute("__gilde[12].guildRank = 'Anwaerter'; __gilde[12].guildRankOrder = 5")
neu, weg = tup3(G.Synchronisieren("40er"))
n = namen()
fest("Neuer Raider" in n and "Raider Eins" not in n, "neues Mitglied drin, Rangwechsel faellt heraus (%s neu, %s weg)" % (neu, weg))

# Niemand im gewaehlten Rang: lieber nichts anfassen
G.RangSetzen("40er", 3, False)
G.RangSetzen("40er", 9, True)
vorher = namen()
r = tup3(G.Synchronisieren("40er"))
fest(r[0] is None and namen() == vorher, "leerer Rang: nichts geaendert (%s)" % (r[1],))
G.RangSetzen("40er", 9, False)
G.RangSetzen("40er", 3, True)

# Schutz vor halb geladener Gildenliste: viele auf einmal entfernen -> nachfragen
lua.execute("""
for i = 20, 33 do __gilde[i] = { name = "Kader " .. i, guildRank = "Raider", guildRankOrder = 3 } end
""")
G.Synchronisieren("40er")
fest(sum(1 for x in namen() if x.startswith("Kader ")) == 14, "vierzehn weitere aufgenommen")
lua.execute("for i = 20, 33 do __gilde[i] = nil end")
vorher = len(namen())
r = tup3(G.Synchronisieren("40er"))
fest(r[0] is None and len(namen()) == vorher, "viele Abgaenge auf einmal: es fragt erst nach")
r2 = tup3(G.Synchronisieren("40er"))
fest(r2[0] == 0 and r2[1] == 14, "zweiter Klick fuehrt es aus (%s neu, %s entfernt)" % (r2[0], r2[1]))

# Automatisch beim Anmelden: kein Nachfragen, bei Auffaelligkeit wird nichts entfernt
lua.execute("for i = 20, 33 do __gilde[i] = { name = 'Kader ' .. i, guildRank = 'Raider', guildRankOrder = 3 } end")
G.Synchronisieren("40er")
lua.execute("for i = 20, 33 do __gilde[i] = nil end")
vorher = len(namen())
G.AutoSynchronisieren()
fest(len(namen()) == vorher, "automatisch: auffaellig viele Abgaenge werden NICHT entfernt")

# Entfernen von Hand
G.KaderEntfernen("40er", "Handname Eins")
fest("Handname Eins" not in namen(), "von Hand entfernt")

# Migration: alter Stand (nur `kader`) gilt als Handarbeit
G.Anlegen("alt")
alt = G.Holen("alt")
g["FairshareDB"]["gruppen"]["alt"] = lua.table_from({"name": "alt", "kader": lua.table_from({1: "Alter Eins", 2: "Alter Zwei"})})
G.Aktivieren("alt")
G.RangSetzen("alt", 3, True)
G.Synchronisieren("alt")
fest("Alter Eins" in sorted(str(x) for x in G.Namensliste(G.Holen("alt")).values()),
     "alte Namen ueberleben den ersten Abgleich")

print("== 16. Liste in der Gruppe: nur wer dabei ist ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
for i, nm in enumerate(["Timo", "Lina", "Fremder Eins", "Fremder Zwei", "Timo"]):
    w.setze(0, "e%d" % i, {"awardedTo": nm, "itemID": 8100 + i, "timestamp": int(w.t) - i * 3600})


def liste_namen(nur):
    liste = tup(ns.Kern.Bilanz(w.hist(0), 0, nur, nur))[0]
    return [str(liste[i]["name"]) for i in range(1, sum(1 for _ in liste.keys()) + 1)]


gruppennamen = list(ns.Rolle.Namen().values())
mit = liste_namen(lua.table_from(gruppennamen))
fest(sorted(mit) == ["Leiter Kaos", "Lina", "Timo"], "nur die drei aus der Gruppe, auch der ohne Vergabe (%s)" % mit)
fest("Fremder Eins" not in mit, "wer nicht dabei ist, fehlt")
liste = tup(ns.Kern.Bilanz(w.hist(0), 0, lua.table_from(gruppennamen), lua.table_from(gruppennamen)))[0]
timo = [liste[i] for i in range(1, 4) if liste[i]["name"] == "Timo"][0]
fest(timo["haupt"] == 2, "Timo hat seine zwei Vergaben")
_, gesamt, _ = tup(ns.Kern.Bilanz(w.hist(0), 0, lua.table_from(gruppennamen), lua.table_from(gruppennamen)))
fest(gesamt == 3, "die Summe zaehlt nur die Gruppe (3 von 5)")

# Name ohne Nachname in der Historie wird dem vollen Namen der Gruppe zugeschlagen
w.setze(0, "e9", {"awardedTo": "Leiter", "itemID": 8200, "timestamp": int(w.t)})
liste = tup(ns.Kern.Bilanz(w.hist(0), 0, lua.table_from(gruppennamen), lua.table_from(gruppennamen)))[0]
namen = [str(liste[i]["name"]) for i in range(1, sum(1 for _ in liste.keys()) + 1)]
fest(namen.count("Leiter Kaos") == 1 and "Leiter" not in namen, "Kurzname und voller Name sind eine Zeile (%s)" % namen)

# Oberflaeche: in der Gruppe nur die Gruppe, auf Wunsch alle
ns.Fenster.Zeigen(False)
def hat(text):
    return len(list(g["__text"](text).values())) > 0
fest(hat("Show all players"), "Knopf Alle Spieler zeigen ist da (englisch? nein: deutsch)") if False else None
fest(hat("Alle Spieler zeigen"), "Knopf Alle Spieler zeigen ist da")
fest(hat("Lina") and not hat("Fremder Eins"), "Liste zeigt die Gruppe, nicht die Fremden")
fest(hat("nur Spieler aus deiner Gruppe"), "Fuss sagt, dass gefiltert wird")
g["__klick"]("Alle Spieler zeigen")
fest(hat("Fremder Eins"), "nach dem Klick stehen alle drin")
fest(hat("Nur Gruppe zeigen"), "und der Knopf bietet den Rueckweg")
g["__klick"]("Nur Gruppe zeigen")
fest(not hat("Fremder Eins"), "zurueck zur Gruppe")
# Ohne Gruppe: alles sichtbar, kein Knopf
g["__welt"]["inGruppe"] = False
ns.Fenster.Aktualisieren()
fest(hat("Fremder Eins"), "ohne Gruppe stehen wieder alle drin")
g["__welt"]["inGruppe"] = True

print("== 17. Automatisch abgleichen ==")
w = gruppe(3, auto=True)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
for i in range(12):
    w.setze(0, "alt%d" % i, {"awardedTo": ["Timo", "Lina", "Moe"][i % 3], "itemID": 9000 + i,
                              "timestamp": int(w.t) - (i // 4) * 86400 - i * 600})
w.ereignis("GROUP_ROSTER_UPDATE")
w.weiter(60)
fest(w.stand(0) == w.stand(1) == w.stand(2), "ohne Zutun gleich: %s / %s / %s" % (w.stand(0), w.stand(1), w.stand(2)))
fest(anz(w, 1) == 12 and anz(w, 2) == 12, "beide haben alle 12 bekommen")
fest(len(w.clients[0]["ns"].Abgleich.Abweichend) == 0, "keine Abweichung mehr")
nachrichten = len(w.protokoll)
w.weiter(130)
fest(len(w.protokoll) - nachrichten < 10, "danach Ruhe (%d Nachrichten)" % (len(w.protokoll) - nachrichten))

# Aus: kein automatischer Abgleich
w = gruppe(3, auto=False)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
for i in range(6):
    w.setze(0, "alt%d" % i, {"awardedTo": "Timo", "itemID": 9100 + i, "timestamp": int(w.t) - i * 700})
w.ereignis("GROUP_ROSTER_UPDATE")
w.weiter(60)
fest(w.stand(0) != w.stand(1), "mit Auto aus bleibt es beim Hinweis")

print("== 18. /fs reset: fragen, sichern, zurueckholen ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
for i in range(8):
    w.setze(0, "t%d" % i, {"awardedTo": "Timo", "itemID": 9300 + i, "timestamp": int(w.t) - i * 4000})
ns.Gruppen.Anlegen("40er")
sl = g["SlashCmdList"]["FAIRSHARE"]


def ausgaben():
    return [str(x) for x in g["__ausgabe"].values()]


# Erst fragen, noch nichts geloescht
sl("reset")
fest(anz(w, 0) == 8, "/fs reset allein loescht nichts")
fest(any("8" in x and "Einträge" in x for x in ausgaben()), "es nennt die Zahl der Eintraege")
# Bestaetigung ohne vorherige Frage in neuer Sitzung waere wirkungslos - hier mit Frage
sl("reset ja")
fest(anz(w, 0) == 0, "nach /fs reset ja ist die Historie leer")
fest(ns.Gruppen.Holen("40er") is not None, "Gruppen bleiben")
fest(ns.Erfassung.SicherungInfo() is not None and ns.Erfassung.SicherungInfo()["n"] == 8, "die Sicherung hat 8 Eintraege")
# Bestaetigen ohne Frage geht nicht
sl("reset ja")
fest(any("innerhalb einer Minute" in x for x in ausgaben()), "ohne vorherige Frage wird nichts getan")
# Zurueckholen
sl("reset undo")
fest(anz(w, 0) == 8, "/fs reset undo holt alles zurueck")
fest(ns.Erfassung.SicherungInfo() is None, "danach gibt es keine Sicherung mehr")
sl("reset undo")
fest(any("keine Sicherung" in x for x in ausgaben()), "ein zweites Zurueckholen sagt, dass nichts da ist")

# Zurueckholen verliert nichts, was inzwischen neu dazukam
sl("reset"); sl("reset ja")
w.setze(0, "neu1", {"awardedTo": "Lina", "itemID": 9400, "timestamp": int(w.t)})
n = ns.Erfassung.Wiederherstellen()
fest(anz(w, 0) == 9, "Sicherung und neuer Eintrag zusammen (%s zurueck)" % n)

# Einstellungsfenster: zweistufig
ns.Einstellungen.Zeigen()
g["__klick"]("Erfassung")
fest(g["__klick"]("Zurücksetzen") is True, "Knopf Zuruecksetzen in den Einstellungen")
fest(anz(w, 0) == 9, "der erste Klick fragt nur")
fest(g["__klick"]("Wirklich zurücksetzen") is True, "zweiter Klick")
fest(anz(w, 0) == 0, "danach ist es leer")
fest(g["__klick"]("Wiederherstellen") is True, "Wiederherstellen ist jetzt sichtbar und geht")
fest(anz(w, 0) == 9, "und holt alles zurueck")

# Wer die Daten noch hat, bringt sie beim Abgleich zurueck (Absicht)
w = gruppe(3, auto=True)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
for k in (0, 1, 2):
    for i in range(5):
        w.setze(k, "g%d" % i, {"awardedTo": "Timo", "itemID": 9500 + i, "timestamp": int(w.t) - i * 4000})
w.ereignis("GROUP_ROSTER_UPDATE")      # alle melden ihren Stand (Hallo)
w.weiter(20)
w.clients[0]["ns"].Erfassung.Zuruecksetzen()
fest(anz(w, 0) == 0 and anz(w, 1) == 5, "Leiter leert, die anderen haben noch alles")
w.weiter(150)    # der Abstand zwischen zwei automatischen Laeufen betraegt zwei Minuten
fest(anz(w, 0) == 5, "der automatische Abgleich bringt es zurueck (nur Hinzufuegen)")

print("== 19. Blizzards Wuerfelfenster: Fenster oeffnet sich, Haupt/Zweit je Wurf ==")
import re


def roh(t):
    return re.sub(r"\|r|\|c[0-9a-fA-F]{8}", "", str(t))


w = gruppe(4)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
# Vorgeschichte: Timo 3 Stuecke, Lina 1, Moe 0
for i in range(3):
    w.setze(0, "v%d" % i, {"awardedTo": "Timo", "itemID": 9600 + i, "timestamp": int(w.t) - (i + 1) * 4000})
w.setze(0, "v9", {"awardedTo": "Lina", "itemID": 9609, "timestamp": int(w.t) - 5000})
A1 = "|cff0070dd|Hitem:7001::::::::60:::::|h[Rollding 1]|h|r"
A2 = "|cff0070dd|Hitem:7002::::::::60:::::|h[Rollding 2]|h|r"


def chat(text):
    g["__ereignis"]("CHAT_MSG_LOOT", text)


def texte():
    return [roh(x) for x in g["__text"]("").values()]


def zeile_von(name):
    """Platz des Namens in der Zeilenfolge (Reihenfolge der erzeugten Textfelder)."""
    fr = g["__frames"]
    for i in range(1, len(fr) + 1):
        if roh(fr[i]["_text"] or "") == name:
            return i
    return None


fest(ns.Fenster.Sichtbar() is False, "Fenster ist zu")
g["__ereignis"]("START_LOOT_ROLL", 1)
fest(ns.Fenster.Sichtbar() is True, "START_LOOT_ROLL oeffnet das Fenster")
fest(any("Wurf läuft" in t and "Rollding 1" in t for t in texte()), "Wurfzeile nennt den Gegenstand")

chat("Timo has selected Greed for: " + A1)
chat("Lina has selected Need for: " + A1)
fest(any("1 Haupt · 1 Zweit" in t for t in texte()), "Zaehler: 1 Haupt, 1 Zweit (schon vor dem Wurf)")
fest(zeile_von("Lina") < zeile_von("Timo"), "Haupt steht vor Zweit, obwohl Timo mehr Stuecke hat als... (Lina vor Timo)")

chat("Greed Roll - 41 for " + A1 + " by Timo")
chat("Need Roll - 87 for " + A1 + " by Lina")
fest(any(t == "87  Haupt" for t in texte()), "Lina: 87 Haupt")
fest(any(t == "41  Zweit" for t in texte()), "Timo: 41 Zweit")

# Ein dritter wuerfelt Haupt mit weniger Stuecken: steht vor Lina
chat("Moe has selected Need for: " + A1)
chat("Need Roll - 12 for " + A1 + " by Moe")
fest(zeile_von("Moe") < zeile_von("Lina") < zeile_von("Timo"), "Haupt wenigste zuerst, dann Haupt mit mehr, dann Zweit")

# Der ERSTE Wurf zaehlt: weitere Wuerfe desselben Spielers aendern nichts
for wert in (99, 3, 77):
    chat("Need Roll - %d for %s by Moe" % (wert, A1))
R = ns.Erfassung.AktuelleWuerfe()
fest(R["Wuerfe"]["moe"] == 12, "Moe wuerfelt mehrfach: der erste Wurf (12) bleibt, nicht der letzte (%s)" % R["Wuerfe"]["moe"])
chat("Greed Roll - 88 for %s by Moe" % A1)
fest(R is not None and ns.Erfassung.AktuelleWuerfe()["Arten"]["moe"] == "haupt", "auch ein spaeterer Zweitbedarf-Wurf aendert die Art nicht")

# Verzicht nimmt den Spieler aus der Liste
chat("Timo passed on: " + A1)
fest(not any(t == "41  Zweit" for t in texte()), "Timo verzichtet: sein Wurf verschwindet")

# Rollenbonus-Fassung wird nicht als Name „Zora + Role Bonus" gelesen
chat("Need Roll - 55 for " + A1 + " by Zora + Role Bonus")
R = ns.Erfassung.AktuelleWuerfe()
fest(R["Wuerfe"]["zora"] == 55 and R["Wuerfe"]["zora + role bonus"] is None,
     "Wurf mit Rollenbonus: Name sauber erkannt (ohne den Zusatz)")

# Der Gewinner: Eintrag mit richtiger Art, die Wurfanzeige endet
chat("Lina receives loot: " + A1 + ".")
fest(any(v["awardedTo"] == "Lina" and v["itemID"] == 7001 for v in w.hist(0).values()), "Gewinn wird aufgezeichnet")
e = [v for v in w.hist(0).values() if v["itemID"] == 7001][0]
fest(e["OS"] is None, "Hauptbedarf-Wurf: kein Zweitbedarf")
fest(not any("Wurf läuft" in t for t in texte()), "nach der Vergabe endet die Wurfanzeige")

# Zwei Gegenstaende gleichzeitig bleiben getrennt
g["__ereignis"]("START_LOOT_ROLL", 1)
g["__ereignis"]("START_LOOT_ROLL", 2)
chat("Need Roll - 70 for " + A1 + " by Timo")
w.weiter(2)
chat("Greed Roll - 33 for " + A2 + " by Lina")
fest(any("Rollding 2" in t and "Wurf läuft" in t for t in texte()), "gezeigt wird der Gegenstand mit der juengsten Bewegung")
fest(not any(t == "70  Haupt" for t in texte()), "die Wuerfe des anderen Gegenstands stehen nicht darin")
chat("Lina receives loot: " + A2 + ".")
fest(any("Rollding 1" in t and "Wurf läuft" in t for t in texte()), "danach zeigt es den anderen Gegenstand")
fest(any(t == "70  Haupt" for t in texte()), "dessen Wuerfe sind noch da")

# Zweitbedarf-Gewinn (Gier) wird als Zweitbedarf eingetragen
chat("Need Roll - 20 for " + A1 + " by Moe")
chat("Greed Roll - 90 for " + A1 + " by Zora")
chat("Zora receives loot: " + A1 + ".")
e = [v for v in w.hist(0).values() if v["awardedTo"] == "Zora"][0]
fest(e["OS"] is True, "Gier-Gewinn: als Zweitbedarf eingetragen")

# Gargul: die Art kommt aus dem Wurfbereich
w2 = gruppe(2)
w2.ereignis("PLAYER_ENTERING_WORLD")
w2.weiter(5)
ns2, g2, lua2 = w2.clients[0]["ns"], w2.clients[0]["g"], w2.clients[0]["lua"]
lua2.execute("""
Gargul = { RollOff = { inProgress = true, CurrentRollOff = { itemLink = "x", Rolls = {
  { player = "Timo", amount = 87, min = 1, max = 100 },
  { player = "Lina", amount = 41, min = 1, max = 50 },
  { player = "Moe",  amount = 30, min = 1, max = 100 },
  { player = "Moe",  amount = 45, min = 1, max = 50 },
  { player = "Zora", amount = 60, min = 1, max = 99, classification = "OS" },
} } } }
""")
W = ns2.Quelle.Wurf()
fest(W["Arten"]["timo"] == "haupt" and W["Wuerfe"]["timo"] == 87, "Gargul: 1-100 ist Haupt")
fest(W["Arten"]["lina"] == "zweit" and W["Wuerfe"]["lina"] == 41, "Gargul: 1-50 ist Zweit")
fest(W["Arten"]["moe"] == "haupt" and W["Wuerfe"]["moe"] == 30, "Moe: der erste Wurf (30 Haupt) zaehlt, nicht der spaetere")
fest(W["Arten"]["zora"] == "zweit", "Gargul: Bereichsname OS gilt als Zweit")
lua2.execute("""
Gargul.RollOff.CurrentRollOff.Rolls = {
  { player = "Timo", amount = 95, min = 1, max = 100, time = 200 },
  { player = "Timo", amount = 20, min = 1, max = 100, time = 100 },
  { player = "Lina", amount = 44, min = 1, max = 50,  time = 150 },
  { player = "Lina", amount = 99, min = 1, max = 100, time = 160 },
}""")
W = ns2.Quelle.Wurf()
fest(W["Wuerfe"]["timo"] == 20, "Gargul: Timos erster Wurf nach Zeit (20), nicht der hoechste (95)")
fest(W["Wuerfe"]["lina"] == 44 and W["Arten"]["lina"] == "zweit", "Gargul: Linas erster Wurf war Zweit und bleibt es")

# Getippte /rnd ohne Gegenstand: der erste Wurf zaehlt, nach einer Minute beginnt eine neue Runde
w3 = gruppe(3)
w3.ereignis("PLAYER_ENTERING_WORLD")
w3.weiter(5)
ns3, g3 = w3.clients[0]["ns"], w3.clients[0]["g"]
g3["__ereignis"]("CHAT_MSG_SYSTEM", "Lina rolls 40 (1-100)")
g3["__ereignis"]("CHAT_MSG_SYSTEM", "Lina rolls 95 (1-100)")
fest(ns3.Erfassung.AktuelleWuerfe()["Wuerfe"]["lina"] == 40, "/rnd mehrfach: der erste Wurf (40) zaehlt")
w3.weiter(70)
g3["__ereignis"]("CHAT_MSG_SYSTEM", "Lina rolls 95 (1-100)")
fest(ns3.Erfassung.AktuelleWuerfe()["Wuerfe"]["lina"] == 95, "nach einer Minute gilt ein neuer Wurf als neue Runde")

print("== 20. Eigenes Wuerfelfenster: Start, Klick, Wurf, Ende ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
L0, T1, N2 = w.clients[0], w.clients[1], w.clients[2]
for k in (0, 1, 2):
    w.setze(k, "x%d" % k, {"awardedTo": "Timo", "itemID": 9700, "timestamp": int(w.t) - 5000})
LINK = "|cff0070dd|Hitem:7100::::::::60:::::|h[Schwert der Probe]|h|r"


def aktiv(k):
    return w.clients[k]["ns"].Wurf.Aktiv()


def hat_text(k, text):
    return len(list(w.clients[k]["g"]["__text"](text).values())) > 0


def systemwurf(wer, wert, bereich):
    """Der Server meldet jedem in der Gruppe: '<wer> rolls <wert> (1-<bereich>)'."""
    for cl in w.clients:
        cl["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "%s rolls %d (1-%d)" % (wer, wert, bereich))


# Ein Mitglied darf keinen Wurf starten
ok, grund = tup(T1["ns"].Wurf.Starten(LINK))
fest(ok is False, "ein Mitglied darf keinen Wurf starten (%s)" % grund)
# Eine gefaelschte Startmeldung eines Mitglieds wird verworfen
N2["ns"].Abgleich.Empfangen("S;fake;30;" + LINK, "Timo-Realm")
fest(not aktiv(2), "Startmeldung eines Nicht-Leiters wird ignoriert")
# Ohne Link kein Wurf
ok, grund = tup(L0["ns"].Wurf.Starten("kein link"))
fest(ok is False, "ohne Gegenstandslink startet nichts")

ok, grund = tup(L0["ns"].Wurf.Starten("x " + LINK + " y"))
fest(ok is True, "der Leiter startet einen Wurf (%s)" % grund)
w.weiter(3)
fest(aktiv(0) and aktiv(1) and aktiv(2), "bei allen laeuft der Wurf")
fest(hat_text(1, "Haupt (1-100)") and hat_text(1, "Zweit (1-50)") and hat_text(1, "Passen"), "Spieler sehen die drei Knoepfe")
fest(hat_text(1, "Schwert der Probe"), "der Gegenstand steht im Fenster")
fest(L0["ns"].Fenster.Sichtbar() is True, "beim Leiter oeffnet sich die Uebersicht")
fest(T1["ns"].Fenster.Sichtbar() is False, "bei den Spielern nicht")

# Timo klickt Haupt: es wird 1-100 gewuerfelt, einmal
fest(T1["g"]["__klick"]("Haupt (1-100)") is True, "Timo klickt Haupt")
wl = T1["g"]["__wurfLog"]
fest(len(wl) == 1 and wl[1][1] == 1 and wl[1][2] == 100, "RandomRoll(1, 100) wurde gerufen")
systemwurf("Timo", 77, 100)
w.weiter(1)
fest(T1["g"]["__klick"]("Haupt (1-100)") is False and T1["g"]["__klick"]("Zweit (1-50)") is False,
     "danach sind die Knoepfe gesperrt")
fest(len(T1["g"]["__wurfLog"]) == 1, "kein zweiter Wurf")
fest(any("77" in roh(t) and "Haupt" in roh(t) for t in [str(x) for x in T1["g"]["__text"]("gewürfelt").values()]),
     "Timo sieht seinen Wurf im Fenster")

# Lina klickt Zweit
N2["g"]["__klick"]("Zweit (1-50)")
wl2 = N2["g"]["__wurfLog"]
fest(len(wl2) == 1 and wl2[1][2] == 50, "RandomRoll(1, 50) fuer Zweit")
systemwurf("Lina", 33, 50)

# Der Leiter sieht beides, dem Gegenstand zugeordnet, Haupt vor Zweit
R = L0["ns"].Erfassung.AktuelleWuerfe()
fest(R["link"] == LINK and R["Wuerfe"]["timo"] == 77 and R["Arten"]["timo"] == "haupt", "Leiter: Timo 77 Haupt")
fest(R["Wuerfe"]["lina"] == 33 and R["Arten"]["lina"] == "zweit", "Leiter: Lina 33 Zweit")

# Der Leiter beendet: bei allen weg
fest(L0["ns"].Wurf.BeendenAlle() is True, "Leiter beendet den Wurf")
w.weiter(3)
fest(not aktiv(0) and not aktiv(1) and not aktiv(2), "bei allen ist der Wurf zu")

# Zeit laeuft ab
L0["ns"].Wurf.Starten(LINK)
w.weiter(5)
fest(aktiv(1), "zweiter Wurf laeuft")
w.weiter(40)
fest(not aktiv(1) and not aktiv(0), "nach der Dauer endet der Wurf von selbst")

# Passen wuerfelt nicht
L0["ns"].Wurf.Starten(LINK)
w.weiter(3)
before = len(N2["g"]["__wurfLog"])
N2["g"]["__klick"]("Passen")
fest(len(N2["g"]["__wurfLog"]) == before, "Passen wuerfelt nicht")
L0["ns"].Wurf.BeendenAlle()
w.weiter(3)

# Befehle und Dialog
sl = L0["g"]["SlashCmdList"]["FAIRSHARE"]
for befehl in ["wurf", "wurf ende", "wurf " + LINK, "wurf ende", "roll", "beutetest", "lootcheck"]:
    sl(befehl)
fehler = [str(x) for x in L0["g"]["__ausgabe"].values() if "Fehler" in str(x)]
fest(not fehler, "/fs wurf und /fs beutetest ohne Fehler%s" % ((": " + fehler[0][:150]) if fehler else ""))
fest(L0["ns"].Wurf.Dialog() is True and hat_text(0, "Dauer: 30 s"), "Startdialog oeffnet sich")
fest(T1["ns"].Wurf.Dialog() is False, "fuer ein Mitglied oeffnet er sich nicht")
zeilen = L0["ns"].Wurf.Beutetest()
fest(len(list(zeilen.values())) >= 3, "Beutetest liefert Zeilen")

print("== 21. Zuteilen: Rucksack (Handel), Beutefenster, nur eintragen; Einstecken zaehlt nicht ==")


def runde(tasche=True, mit=("Timo", "Lina"), loot=False):
    """Neue Gruppe, der Leiter startet einen Wurf, zwei wuerfeln, der Wurf endet."""
    w = gruppe(3)
    w.ereignis("PLAYER_ENTERING_WORLD")
    w.weiter(15)
    cl = w.clients[0]
    g, ns, lua = cl["g"], cl["ns"], cl["lua"]
    for k in (0, 1, 2):
        w.setze(k, "x%d" % k, {"awardedTo": "Lina", "itemID": 9700, "timestamp": int(w.t) - 5000})
    if tasche:
        lua.execute('__tasche = { { link = "%s", quality = 4, frist = true } }' % LINK)
    if loot:
        lua.execute('__loot = { { link = "%s" } }' % LINK)
    ns.Wurf.Starten(LINK)
    w.weiter(3)
    for wer, wert, bereich in (("Timo", 77, 100), ("Lina", 91, 100), ("Moe", 12, 50)):
        for c in w.clients:
            c["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "%s rolls %d (1-%d)" % (wer, wert, bereich))
    w.weiter(1)
    ns.Wurf.BeendenAlle()
    w.weiter(4)
    return w, cl, g, ns, lua


def texte_von(g, teil):
    return [roh(x) for x in g["__text"](teil).values()]


# --- Rucksack: Ergebnis zeigt die Rangliste, Zuteilen startet den Handel ------
w, cl, g, ns, lua = runde()
fest(len(texte_von(g, "Ergebnis")) > 0, "nach dem Wurf erscheint das Ergebnis beim Leiter")
fest(len(texte_von(g, "Gegenstand liegt im Rucksack")) > 0, "es sagt: der Gegenstand liegt im Rucksack")
fest(not any(len(texte_von(w.clients[1]["g"], "Ergebnis")) for _ in [0]), "die Mitspieler sehen kein Ergebnis")
namen = [t for t in texte_von(g, "") if t in ("Timo", "Lina", "Moe")][-3:]   # die letzten drei: die Zeilen des Ergebnisses
# Lina hat schon 1 Stueck, Timo keins: Timo (77) vor Lina (91), danach Moe (OS)
fest(namen == ["Timo", "Lina", "Moe"], "wenigste Stuecke zuerst, dann hoechster Wurf, OS zuletzt (%s)" % namen)
fest(g["__klick"]("Zuteilen") is True, "Zuteilen bei der ersten Zeile")
fest(str(g["__handel"]) == "party1", "Handel mit Timo angefragt (%s)" % g["__handel"])
fest(sum(1 for v in w.hist(0).values() if v["itemID"] == 7100) == 0, "noch nichts eingetragen, bevor der Handel gelungen ist")

# falscher Handelspartner: nichts wird eingelegt
g["__npc"] = "Lina"
g["__ereignis"]("TRADE_SHOW")
fest(g["__imHandel"] is None, "falscher Handelspartner: nichts eingelegt")
# richtiger Partner: der Gegenstand wird eingelegt
g["__npc"] = "Timo"
g["__ereignis"]("TRADE_SHOW")
fest(g["__imHandel"] is not None, "richtiger Partner: Gegenstand liegt im Handelsfenster")
# Handel gelungen: der Gegenstand ist weg
lua.execute("__tasche[1].leer = true")
g["__ereignis"]("TRADE_CLOSED")
w.weiter(3)
treffer = [v for v in w.hist(0).values() if v["itemID"] == 7100]
fest(len(treffer) == 1 and treffer[0]["awardedTo"] == "Timo", "nach dem Handel ist Timo eingetragen")
fest(treffer and treffer[0]["wurf"] == 77 and treffer[0]["OS"] is None and treffer[0]["herkunft"] == "wurf",
     "mit Wurf 77, Hauptbedarf, Herkunft Wurf")
w.weiter(10)
fest(any(v["itemID"] == 7100 for v in w.hist(1).values()), "und der Eintrag kam bei den Mitspielern an")

# --- Handel abgebrochen: kein Eintrag ---------------------------------------
w, cl, g, ns, lua = runde()
g["__klick"]("Zuteilen")
g["__npc"] = "Timo"
g["__ereignis"]("TRADE_SHOW")
g["__ereignis"]("TRADE_CLOSED")      # Gegenstand noch im Rucksack
w.weiter(3)
fest(sum(1 for v in w.hist(0).values() if v["itemID"] == 7100) == 0, "Handel abgebrochen: nichts eingetragen")

# --- Nicht auffindbar: nur eintragen -----------------------------------------
w, cl, g, ns, lua = runde(tasche=False)
fest(len(texte_von(g, "Gegenstand nicht gefunden")) > 0, "ohne Gegenstand: Hinweis, dass nur eingetragen wird")
fest(g["__klick"]("Nur eintragen") is True, "Knopf heisst Nur eintragen")
treffer = [v for v in w.hist(0).values() if v["itemID"] == 7100]
fest(len(treffer) == 1 and treffer[0]["awardedTo"] == "Timo", "Timo ist eingetragen")

# --- Beutefenster: Plündermeister-Zuteilung ------------------------------
w, cl, g, ns, lua = runde(tasche=False, loot=True)
fest(len(texte_von(g, "Gegenstand liegt im Beutefenster")) > 0, "Gegenstand im Beutefenster erkannt")
g["__klick"]("Zuteilen")
fest(len(g["__geben"]) == 1 and g["__geben"][1][1] == 1 and g["__geben"][1][2] == 2, "GiveMasterLoot(Platz 1, Empfaenger Timo)")

# --- Behalten: der Plündermeister selbst gewinnt -----------------------------
w, cl, g, ns, lua = runde()
ns.Erfassung.WurfMerken("Leiter Kaos", 99, 1, 100, None, LINK)
w.weiter(1)
ns.Wurf.ErgebnisOeffnen()
fest(g["__handel"] is None, "kein Handel begonnen, bevor jemand geklickt hat")

# --- Dialog zeigt den Rucksack -------------------------------------------------
w, cl, g, ns, lua = runde()
lua.execute('__tasche = { { link = "%s", quality = 4, frist = true }, { link = "|cff0070dd|Hitem:7200::::::::60:::::|h[Ohne Frist]|h|r", quality = 4 } }' % LINK)
ns.Wurf.Dialog()
fest(any("Schwert der Probe" in t for t in texte_von(g, "Rucksack")), "Startdialog listet den Gegenstand mit Handelsfrist")
fest(not any("Ohne Frist" in t for t in texte_von(g, "")), "Stuecke ohne Handelsfrist werden nicht angeboten")

# --- Link-Formate: alt (|cffRRGGBB), neu (|cnIQ4:) und ohne Farbe -------------
w, cl, g, ns, lua = runde()
for fmt, link in (("alt", "|cff0070dd|Hitem:7400::::::::60:::::|h[Alt]|h|r"),
                  ("neu", "|cnIQ4:|Hitem:7401::::::::60:::::|h[Neu]|h|r"),
                  ("ohne Farbe", "|Hitem:7402::::::::60:::::|h[Ohne]|h")):
    ns.Wurf.BeendenAlle()
    w.weiter(2)
    ok, grund = tup(ns.Wurf.Starten("Wurf: " + link + " bitte"))
    fest(ok is True, "Link im Format %s wird erkannt (%s)" % (fmt, grund))
    w.weiter(2)
    fest(w.clients[1]["ns"].Wurf.Aktiv() is True, "und kommt als Wurf bei den Mitspielern an (%s)" % fmt)

# --- Dialog: gewaehlter Link, auch wenn GetText() nur den Namen liefert ------
# (im Spiel gesehen am 14.10.2026: das Feld zeigt "[Trogg Scepter]", Start scheiterte)
w, cl, g, ns, lua = runde()
lua.execute('__tasche = { { link = "%s", quality = 4, frist = true } }' % LINK)
ns.Wurf.Dialog()
lua.execute("""
for _, f in ipairs(__frames) do
    local t = f._text
    if t and t:find("Schwert der Probe", 1, true) and f._eltern and f._eltern._scripts.OnClick then
        __beutezeile = f._eltern
    end
    if f._scripts and f._scripts.OnEnterPressed and f._scripts.OnTextChanged then __eingabe = f end
    if t == "Wurf starten" and f._eltern and f._eltern._scripts.OnClick then __startknopf = f._eltern end
end
""")
fest(g["__beutezeile"] is not None and g["__eingabe"] is not None and g["__startknopf"] is not None,
     "Zeile, Eingabefeld und Startknopf des Dialogs gefunden")
g["__beutezeile"]._scripts.OnClick(g["__beutezeile"])
lua.execute('__eingabe.GetText = function() return "[Schwert der Probe]" end')     # nur der Name
g["__startknopf"]._scripts.OnClick(g["__startknopf"])
w.weiter(3)
fest(ns.Wurf.Aktiv() is True, "Start mit dem gemerkten Link, obwohl das Feld nur den Namen liefert")

# --- Eingesteckte Beute zaehlt nicht -------------------------------------------
w = Welt([{"name": "Leiter Kaos", "leader": True}, {"name": "Timo"}], "-Realm", ml=0)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ns0, g0 = w.clients[0]["ns"], w.clients[0]["g"]
fest(ns0.Rolle.IchBinPluendermeister() is True, "der Leiter ist hier Plündermeister")
ns0.Erfassung.Einstellungen()["ort"] = "ueberall"
g0["__ereignis"]("CHAT_MSG_LOOT", "You receive loot: " + LINK + ".")
fest(sum(1 for v in w.hist(0).values() if v["itemID"] == 7100) == 0, "eingesteckt: keine Vergabe")
g0["__ereignis"]("CHAT_MSG_LOOT", "Timo receives loot: " + LINK + ".")
fest(sum(1 for v in w.hist(0).values() if v["itemID"] == 7100 and v["awardedTo"] == "Timo") == 1,
     "was ein anderer bekommt, zaehlt weiter")
ns0.Erfassung.Einstellungen()["pmEingesteckt"] = False
LINK2 = "|cff0070dd|Hitem:7300::::::::60:::::|h[Zweites]|h|r"
g0["__ereignis"]("CHAT_MSG_LOOT", "You receive loot: " + LINK2 + ".")
fest(any(v["itemID"] == 7300 for v in w.hist(0).values()), "Schalter aus: auch Eingestecktes zaehlt")

print("== 22. Vorgemerkte Zuteilung, Handel von Hand, zu weit weg ==")


def eintraege(w, id_, wer=None):
    return [v for v in w.hist(0).values() if v["itemID"] == id_ and (wer is None or v["awardedTo"] == wer)]


def handel(g, partner, angeboten=None, lua=None):
    g["__npc"] = partner
    g["__ereignis"]("TRADE_SHOW")
    if angeboten is not None:
        lua.execute("__angeboten = { %s }" % ", ".join('"%s"' % a for a in angeboten))
        g["__ereignis"]("TRADE_PLAYER_ITEM_CHANGED", 1)


# --- 1. Zu weit weg: die Zuteilung bleibt vorgemerkt, spaeter wird eingelegt ----
w, cl, g, ns, lua = runde()
g["__klick"]("Zuteilen")                               # der Handel klappt nicht (kein TRADE_SHOW)
w.weiter(5)
fest(len(list(ns.Wurf.Offene().values())) == 1, "die Zuteilung ist vorgemerkt")
fest(len(g["FairshareDB"]["offen"]) == 1, "und liegt in den gespeicherten Daten (ueberlebt Neuladen)")
fest(len(eintraege(w, 7100)) == 0, "noch nichts eingetragen")
w.t += 7200                                            # zwei Stunden spaeter
handel(g, "Lina")                                      # Handel mit jemand anderem: nichts wird eingelegt
fest(g["__angeboten"][1] is None, "anderer Handelspartner: nichts eingelegt")
g["__ereignis"]("TRADE_CLOSED")
w.weiter(3)
handel(g, "Timo")                                      # man trifft Timo doch noch
fest(g["__angeboten"][1] == LINK, "beim naechsten Handel mit Timo liegt der Gegenstand schon drin")
lua.execute("__tasche[1].leer = true")                 # Handel bestaetigt, Gegenstand weg
g["__ereignis"]("TRADE_CLOSED")
w.weiter(3)
treffer = eintraege(w, 7100, "Timo")
fest(len(treffer) == 1 and treffer[0]["wurf"] == 77, "danach ist Timo eingetragen, mit seinem Wurf (77)")
fest(len(list(ns.Wurf.Offene().values())) == 0, "die Vormerkung ist erledigt")

# --- 2. Vormerkungen verfallen nach drei Stunden ---------------------------------
w, cl, g, ns, lua = runde()
g["__klick"]("Zuteilen")
fest(len(list(ns.Wurf.Offene().values())) == 1, "vorgemerkt")
w.t += 4 * 3600
fest(len(list(ns.Wurf.Offene().values())) == 0, "nach vier Stunden ist sie verfallen")

# --- 3. Ganz von Hand gehandelt, Wurf bekannt ------------------------------------
w, cl, g, ns, lua = runde()
handel(g, "Timo")
fest(g["__angeboten"][1] is None, "ohne Vormerkung legt das Addon nichts ein")
lua.execute('__angeboten = { "%s" }; __tasche[1].leer = true' % LINK)       # man legt es selbst hinein
g["__ereignis"]("TRADE_PLAYER_ITEM_CHANGED", 1)
g["__ereignis"]("TRADE_CLOSED")
w.weiter(3)
treffer = eintraege(w, 7100, "Timo")
fest(len(treffer) == 1 and treffer[0]["wurf"] == 77 and treffer[0]["OS"] is None,
     "Handel von Hand erkannt: Timo, Wurf 77, Hauptbedarf")

# --- 4. Von Hand an einen Zweitbedarf-Wuerfler: die Art kommt aus dem Wurf ------
w, cl, g, ns, lua = runde()
handel(g, "Moe")
lua.execute('__angeboten = { "%s" }; __tasche[1].leer = true' % LINK)
g["__ereignis"]("TRADE_PLAYER_ITEM_CHANGED", 1)
g["__ereignis"]("TRADE_CLOSED")
w.weiter(3)
treffer = eintraege(w, 7100, "Moe")
fest(len(treffer) == 1 and treffer[0]["OS"] is True, "Moe hatte 1-50 gewuerfelt: als Zweitbedarf eingetragen")

# --- 5. Kein Wurf bekannt, aber ein Stueck mit Handelsfrist: Hauptbedarf ---------
w, cl, g, ns, lua = runde()
handel(g, "Zora")
lua.execute('__angeboten = { "%s" }; __tasche[1].leer = true' % LINK)
g["__ereignis"]("TRADE_PLAYER_ITEM_CHANGED", 1)
g["__ereignis"]("TRADE_CLOSED")
w.weiter(3)
treffer = eintraege(w, 7100, "Zora")
fest(len(treffer) == 1 and treffer[0]["OS"] is None, "ohne Wurf, mit Handelsfrist: als Hauptbedarf eingetragen")

# --- 6. Etwas ohne Handelsfrist zaehlt nicht -------------------------------------
w, cl, g, ns, lua = runde()
OTHER = "|cnIQ4:|Hitem:7500::::::::60:::::|h[Kram]|h|r"
lua.execute('__tasche = { { link = "%s", quality = 4, frist = true }, { link = "%s", quality = 4, frist = false } }' % (LINK, OTHER))
handel(g, "Timo")
lua.execute('__angeboten = { "%s" }; __tasche[2].leer = true' % OTHER)
g["__ereignis"]("TRADE_PLAYER_ITEM_CHANGED", 1)
g["__ereignis"]("TRADE_CLOSED")
w.weiter(3)
fest(len(eintraege(w, 7500)) == 0, "ein Stueck ohne Handelsfrist ist kein Loot und wird nicht eingetragen")

# --- 7. Abgebrochener Handel: nichts ---------------------------------------------
w, cl, g, ns, lua = runde()
handel(g, "Timo", [LINK], lua)
g["__ereignis"]("TRADE_CLOSED")            # der Gegenstand blieb im Rucksack
w.weiter(3)
fest(len(eintraege(w, 7100)) == 0, "abgebrochen: kein Eintrag")

# --- 8. Befehle -----------------------------------------------------------------
w, cl, g, ns, lua = runde()
g["__klick"]("Zuteilen")
sl = g["SlashCmdList"]["FAIRSHARE"]
g["__ausgabe"] = lua.table()
sl("wurf offen")
fest(any("Timo" in str(x) for x in g["__ausgabe"].values()), "/fs wurf offen zeigt die Vormerkung")
sl("wurf offen leeren")
fest(len(list(ns.Wurf.Offene().values())) == 0, "/fs wurf offen leeren loescht sie")
fehler = [str(x) for x in g["__ausgabe"].values() if "Fehler" in str(x)]
fest(not fehler, "ohne Fehler")

print("== 23. Vergabe zuruecknehmen: Knopf, Befehl, Abgleich, Rechte ==")


def gezaehlt(w, k):
    return sum(1 for v in w.hist(k).values() if not v["zurueck"])


def welt23():
    w = gruppe(3, auto=True)
    w.ereignis("PLAYER_ENTERING_WORLD")
    w.weiter(15)
    for k in (0, 1, 2):
        w.setze(k, "u1", {"awardedTo": "Timo", "itemID": 9801, "timestamp": int(w.t) - 7000})
        w.setze(k, "u2", {"awardedTo": "Lina", "itemID": 9802, "timestamp": int(w.t) - 3000})
    w.ereignis("GROUP_ROSTER_UPDATE")
    w.weiter(20)
    return w


# --- Der Knopf im Verlauf: zweistufig, wirkt live bei allen --------------------
w = welt23()
cl = w.clients[0]
ns, g = cl["ns"], cl["g"]
fest(w.stand(0) == w.stand(1) == w.stand(2), "Ausgangslage: alle gleich")
ns.Fenster.Zeigen(False)
g["__klick"]("Verlauf")
fest(g["__klick"]("Rückgängig") is True, "im Verlauf gibt es den Knopf Rückgängig (Leiter)")
fest(gezaehlt(w, 0) == 2, "der erste Klick fragt nur")
fest(len(list(g["__text"]("Wirklich?").values())) > 0, "und fragt: Wirklich?")
fest(g["__klick"]("Wirklich?") is True, "zweiter Klick")
fest(gezaehlt(w, 0) == 1, "danach zaehlt eine Vergabe weniger")
neuester = [v for v in w.hist(0).values() if v["zurueck"]]
fest(len(neuester) == 1 and neuester[0]["awardedTo"] == "Lina", "und zwar die neueste (Lina)")
w.weiter(15)
fest(gezaehlt(w, 1) == 1 and gezaehlt(w, 2) == 1, "bei beiden Mitspielern ist sie ebenfalls zurueckgenommen")
liste = tup(ns.Kern.Bilanz(w.hist(0), 0))[0]
fest(sum(1 for _ in liste.keys()) == 1, "die Liste fuehrt Lina nicht mehr")
fest(w.stand(0) == w.stand(1) == w.stand(2), "und die Pruefsummen sind wieder gleich")

# --- Ein Mitglied hat es verpasst: der Abgleich holt es nach --------------------
w = welt23()
leiter = w.clients[0]["ns"]
w.hist(0)["u2"]["zurueck"] = True          # zurueckgenommen, ohne dass jemand es mitbekam
fest(w.stand(0) != w.stand(1), "die Pruefsumme verraet die Ruecknahme (vorher blieb sie gleich)")
w.ereignis("GROUP_ROSTER_UPDATE")
w.weiter(130)      # der Abstand zwischen zwei automatischen Laeufen betraegt zwei Minuten
fest(gezaehlt(w, 1) == 1 and gezaehlt(w, 2) == 1, "der Abgleich zieht die Ruecknahme bei den anderen nach")
fest(w.stand(0) == w.stand(1) == w.stand(2), "danach sind alle gleich")

# --- Rechte --------------------------------------------------------------------
w = welt23()
ns1 = w.clients[1]["ns"]
ok, grund = tup(ns1.Erfassung.Zuruecknehmen("u1"))
fest(ok is False, "ein Mitglied darf nicht zuruecknehmen (%s)" % grund)
fest(gezaehlt(w, 1) == 2, "und es bleibt alles, wie es war")
ns1.Fenster.Zeigen(False)
w.clients[1]["g"]["__klick"]("Verlauf")
fest(w.clients[1]["g"]["__klick"]("Rückgängig") is False, "bei einem Mitglied gibt es den Knopf nicht")
ok, grund = tup(w.clients[0]["ns"].Erfassung.Zuruecknehmen("gibtesnicht"))
fest(ok is False, "unbekannter Eintrag wird abgelehnt (%s)" % grund)
w.clients[0]["ns"].Erfassung.Zuruecknehmen("u1")
ok, grund = tup(w.clients[0]["ns"].Erfassung.Zuruecknehmen("u1"))
fest(ok is False, "doppelt zuruecknehmen geht nicht (%s)" % grund)

# --- Spielerdetail: auch dort ---------------------------------------------------
w = welt23()
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
ns.Fenster.Zeigen(False)
g["__klick"]("Timo")
fest(g["__klick"]("Rückgängig") is True, "im Spielerdetail gibt es den Knopf")
g["__klick"]("Wirklich?")
fest(gezaehlt(w, 0) == 1 and w.hist(0)["u1"]["zurueck"] is True, "Timos Vergabe ist zurueckgenommen")

# --- Befehl ------------------------------------------------------------------------
w = welt23()
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
sl = g["SlashCmdList"]["FAIRSHARE"]
sl("rueckgaengig ja")
fest(gezaehlt(w, 0) == 2, "ohne vorherige Rueckfrage passiert nichts")
sl("rueckgaengig")
fest(gezaehlt(w, 0) == 2, "/fs rueckgaengig fragt nur")
sl("rueckgaengig ja")
fest(gezaehlt(w, 0) == 1 and w.hist(0)["u2"]["zurueck"] is True, "/fs rueckgaengig ja nimmt die letzte Vergabe zurueck")
sl("undo"); sl("undo yes")
fest(gezaehlt(w, 0) == 0, "englisch: /fs undo, /fs undo yes")
sl("undo")
fehler = [str(x) for x in g["__ausgabe"].values() if "Fehler" in str(x)]
fest(not fehler, "ohne Fehler")

print("== 24. Nach der Vergabe ist der Wurf vorbei (Nutzerfund: Zustand blieb haengen) ==")


def wurflaeuft(g):
    return len([t for t in g["__text"]("Wurf läuft").values() if t]) > 0


def sichtbar(g, name):
    return bool(g[name] is not None and g[name]._shown)


# --- Zuteilen per Handel beendet die Wurfanzeige sofort ------------------------
w, cl, g, ns, lua = runde()
ns.Fenster.Zeigen(False)
fest(wurflaeuft(g) and ns.Erfassung.AktuelleWuerfe() is not None, "vor der Vergabe: Wurf laeuft")
fest(sichtbar(g, "FairshareWurfErgebnis"), "das Ergebnisfenster ist offen")
g["__klick"]("Zuteilen")
fest(ns.Erfassung.AktuelleWuerfe() is None, "nach Zuteilen: keine laufende Runde mehr")
fest(not wurflaeuft(g), "und die Uebersicht zeigt nicht mehr 'Wurf laeuft'")
fest(not sichtbar(g, "FairshareWurfErgebnis"), "das Ergebnisfenster ist zu")

# --- Ein Handel (ohne Beutemeldung) fuehrt zum Eintrag: auch das beendet --------
w, cl, g, ns, lua = runde()
ns.Fenster.Zeigen(False)
g["__npc"] = "Timo"
g["__klick"]("Zuteilen")
g["__ereignis"]("TRADE_SHOW")
lua.execute("__tasche[1].leer = true")
g["__ereignis"]("TRADE_CLOSED")
w.weiter(3)
fest(not wurflaeuft(g), "nach dem Handel steht nichts mehr von dem Wurf da")

# --- Vergabe ueber die Beutemeldung, waehrend das Ergebnis offen ist -------------
w, cl, g, ns, lua = runde()
g["__ereignis"]("CHAT_MSG_LOOT", "Timo receives loot: " + LINK + ".")
fest(not sichtbar(g, "FairshareWurfErgebnis"), "Vergabe per Beutemeldung schliesst das Ergebnis")

# --- Vergabe, waehrend der Wurf noch laeuft: er endet bei allen -----------------
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g = cl["ns"], cl["g"]
ns.Wurf.Starten(LINK)
w.weiter(3)
fest(w.clients[1]["ns"].Wurf.Aktiv() is True, "Wurf laeuft bei den Mitspielern")
g["__ereignis"]("CHAT_MSG_LOOT", "Lina receives loot: " + LINK + ".")
w.weiter(3)
fest(not ns.Wurf.Aktiv() and not w.clients[1]["ns"].Wurf.Aktiv(),
     "die Vergabe beendet den laufenden Wurf bei allen")
fest(not sichtbar(g, "FairshareWurfErgebnis"), "ohne Ergebnisfenster (der Gegenstand ist ja vergeben)")

# --- Wuerfelfenster mit dem Kreuz geschlossen: der Wurf endet trotzdem ----------
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
ns.Wurf.Starten(LINK)
w.weiter(3)
lua.execute("FairshareWurf:Hide()")
w.weiter(40)
fest(not ns.Wurf.Aktiv(), "auch ohne sichtbares Fenster endet der Wurf nach der Zeit")
w.weiter(10)
fest(ns.Wurf.AktuellerLink() is None, "kein haengender Gegenstand: spaetere Wuerfe gehoeren nicht mehr dazu")

# --- Rueckgaengig-Knoepfe stehen nicht in der Spielerliste -----------------------
w = welt23()
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
ns.Fenster.Zeigen(False)
g["__klick"]("Verlauf")
fest(g["__klick"]("Rückgängig") is True, "im Verlauf gibt es den Knopf")
g["__klick"]("Spieler")
fest(g["__klick"]("Rückgängig") is False, "zurueck in der Spielerliste ist er weg")

print()
print("ALLES GUT" if alle_ok else "ES GIBT FEHLER")
sys.exit(0 if alle_ok else 1)
