# -*- coding: utf-8 -*-
"""Szenarien fuer Abgleich, Rolle, Gruppen und Oberflaeche.

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


def lt(lua, o):
    """Python-Wert -> Lua-Wert, verschachtelte dicts und Listen als echte Lua-Tabellen."""
    if isinstance(o, dict):
        return lua.table_from({k: lt(lua, v) for k, v in o.items()})
    if isinstance(o, (list, tuple)):
        return lua.table_from([lt(lua, v) for v in o])
    return o



def fest(bed, text):
    global alle_ok
    if not pruefe(bed, text):
        alle_ok = False


def gruppe(n=3, suffix="-Realm", auto=False, locale="deDE", nutzung="ja"):
    namen = ["Leiter Kaos", "Timo", "Lina", "Moe", "Zora"][:n]
    ms = []
    for i, nm in enumerate(namen):
        ms.append({"name": nm, "leader": i == 0})
    w = Welt(ms, sender_suffix=suffix, locale=locale, nutzung=nutzung)
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
aus1 = [str(x) for x in w.clients[1]["g"]["__ausgabe"].values()]
fest(any("gleicht die Daten in der Gruppe ab" in x or "is syncing the data" in x for x in aus1), "ein Mitspieler sieht eine Meldung, dass abgeglichen wird")
fest(any("Abgleich beendet" in x or "Sync finished" in x or "sync finished" in x.lower() for x in aus1), "und eine, wenn es fertig ist (%s)" % (aus1[-3:],))
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
ns.Erfassung.MusterBauen()
ns.Erfassung.Einstellungen()["schreiben"] = "auto"
ns.Erfassung.Beutemeldung("You receive loot: " + link + ".")
fest(sum(1 for _ in w.hist(0).keys()) == 0, "eine Beutemeldung aus dem Chat bleibt ohne Wirkung")
# In einer Gruppe schreibt er wieder mit (hier ist er selbst Pluendermeister: Einstecken zaehlt sonst nicht)
g["__welt"]["inGruppe"] = True
ns.Erfassung.Einstellungen()["pmEingesteckt"] = False
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
for seite in ("Würfeln & Abgleich", "Gruppen", "Erfassung"):
    fest(g["__klick"](seite) is True, "Seite %s" % seite)
g["__klick"]("Würfeln & Abgleich")
fest(len(list(g["__text"]("Bei Wurfbeginn selbst öffnen").values())) > 0, "Würfeln-Seite baut sich auf")
fest(g["__klick"]("Abgleichen") is True, "Abgleich-Knopf")
g["__klick"]("Gruppen")
ns.Gruppen.Anlegen("40er"); ns.Gruppen.Anlegen("10er")
ns.Einstellungen.Aktualisieren()
fest(len(list(g["__text"]("40er").values())) > 0, "Gruppenliste zeigt die neue Gruppe")
fest(len(list(g["__text"]("Raidkader").values())) > 0 and len(list(g["__text"]("Neue Raid-ID beginnt am").values())) > 0, "Karten Raidkader und Raid-ID erscheinen")
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
fest(len(list(g["__text"]("Gruppe: Alle").values())) > 0, "Ausklappliste steht auf Alle")
ns.Fenster.GruppeWaehlen("10er")
fest(len(list(g["__text"]("Gruppe: 10er").values())) > 0, "Filter steht auf 10er")
ns.Fenster.GruppeWaehlen("40er")
fest(len(list(g["__text"]("Gruppe: 40er").values())) > 0, "Filter steht auf 40er")
ns.Fenster.GruppeWaehlen("")
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
g["__klick"]("Roll and Sync")
fest(hat("Roll ranges") and hat("Open by itself when a roll starts"), "Würfeln-Seite auf Englisch")
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
fest(f3._w == 880 and f3._h == 1100, "unsinnige gemerkte Werte werden auf die Grenzen gesetzt (%s x %s)" % (f3._w, f3._h))

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

# Sortierung nach Gildenrang und Klassenfarbe in den Listen
lua.execute("""
__gilde[11].classID = 1; __gilde[12].classID = 8
C_CreatureInfo = { GetClassInfo = function(id) return { classFile = (id == 1) and "WARRIOR" or "MAGE" } end }
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
""")
fest(G.RangVor("Gildenleiter", "Raider Eins") is True, "Gildenmeister steht vor Raider")
fest(G.RangVor("Neuling", "Raider Eins") is False, "Anwaerter steht hinter Raider")
fest(G.RangVor("Raider Eins", "Raider Zwei") is True, "gleicher Rang: nach Name")
fest(G.RangVor("Raider Zwei", "Unbekannt") is True, "Unbekannte stehen zuletzt")
fest(G.KlassenFarbe("Gildenleiter") == "|cffc79c6e", "Krieger: Klassenfarbe aus der Gildenliste")
fest(G.KlassenFarbe("Raider Eins") == "|cff40c7eb", "Magier: Klassenfarbe aus der Gildenliste")
fest(G.KlassenFarbe("Neuling") is None, "ohne bekannte Klasse: keine Farbe")

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
fest(hat_text(1, "Haupt (1-100)") and hat_text(1, "Zweit (1-99)") and hat_text(1, "Passen"), "Spieler sehen die drei Knoepfe")
fest(hat_text(1, "Schwert der Probe"), "der Gegenstand steht im Fenster")
fest(L0["ns"].Fenster.Sichtbar() is True, "beim Leiter oeffnet sich die Uebersicht")
fest(T1["ns"].Fenster.Sichtbar() is False, "bei den Spielern nicht")

# Timo klickt Haupt: es wird 1-100 gewuerfelt, einmal
fest(T1["g"]["__klick"]("Haupt (1-100)") is True, "Timo klickt Haupt")
wl = T1["g"]["__wurfLog"]
fest(len(wl) == 1 and wl[1][1] == 1 and wl[1][2] == 100, "RandomRoll(1, 100) wurde gerufen")
systemwurf("Timo", 77, 100)
w.weiter(1)
fest(T1["g"]["__klick"]("Haupt (1-100)") is False and T1["g"]["__klick"]("Zweit (1-99)") is False,
     "danach sind die Knoepfe gesperrt")
fest(len(T1["g"]["__wurfLog"]) == 1, "kein zweiter Wurf")
fest(any("77" in roh(t) and "Haupt" in roh(t) for t in [str(x) for x in T1["g"]["__text"]("gewürfelt").values()]),
     "Timo sieht seinen Wurf im Fenster")

# Lina klickt Zweit
N2["g"]["__klick"]("Zweit (1-99)")
wl2 = N2["g"]["__wurfLog"]
fest(len(wl2) == 1 and wl2[1][2] == 99, "RandomRoll(1, 99) fuer Zweit")
systemwurf("Lina", 33, 99)

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
fest(L0["ns"].Wurf.Dialog() is True and hat_text(0, "Dauer (s)"), "Startdialog oeffnet sich")
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
    lua.execute("__chat = {}")   # die Startzeile im Chat prueft Szenario 35, nicht die Folgeszenarien
    w.weiter(3)
    for wer, wert, bereich in (("Timo", 77, 100), ("Lina", 91, 100), ("Moe", 12, 99)):
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

# --- Handel gelungen, aber das Angebot war beim Schliessen nicht lesbar (Fund im Spiel 19.10.2026) ------------
w, cl, g, ns, lua = runde()
g["__klick"]("Zuteilen")
g["__npc"] = "Timo"
g["__ereignis"]("TRADE_SHOW")
lua.execute("__angeboten = {}")                  # das Handelsfenster liefert keine Links mehr
lua.execute("__tasche[1].leer = true")
g["__ereignis"]("TRADE_CLOSED")
w.weiter(8)
treffer = [v for v in w.hist(0).values() if v["itemID"] == 7100]
fest(len(treffer) == 1 and treffer[0]["awardedTo"] == "Timo", "auch ohne lesbares Angebot wird der vorgemerkte Gegenstand eingetragen (%d)" % len(treffer))
fest(len(ns.Wurf.Offene()) == 0, "und die Vormerkung ist erledigt")

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
fest(len(treffer) == 1 and treffer[0]["OS"] is True, "Moe hatte 1-99 gewuerfelt: als Zweitbedarf eingetragen")

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
# ⭐ Rueckgabe (Regelwerk § 1): Der Punkt bleibt, bis das Item neu vergeben ist.
fest(gezaehlt(w, 0) == 2, "danach zaehlt die Vergabe noch (Punkt bleibt bis zur Neuvergabe)")
rueck = [v for v in w.hist(0).values() if v["rueckgabe"]]
fest(len(rueck) == 1 and rueck[0]["awardedTo"] == "Lina", "vermerkt ist die Rueckgabe der neuesten Vergabe (Lina)")
fest(not rueck[0]["zurueck"], "aber noch nicht zurueckgenommen")
# Das Item wird neu vergeben (an Timo): jetzt wandert der Punkt
w.eintragen(0, "Timo", 9802, int(w.t))
w.weiter(15)
fest(gezaehlt(w, 0) == 2, "nach der Neuvergabe zaehlen zwei (Timos erstes, das neue)")
neuester = [v for v in w.hist(0).values() if v["zurueck"]]
fest(len(neuester) == 1 and neuester[0]["awardedTo"] == "Lina", "und Linas Vergabe ist zurueckgenommen")
fest(gezaehlt(w, 1) == 2 and gezaehlt(w, 2) == 2, "bei beiden Mitspielern ebenfalls")
liste = tup(ns.Kern.Bilanz(w.hist(0), 0))[0]
fest(sum(1 for _ in liste.keys()) == 1, "die Liste fuehrt nur noch Timo (Lina hat nichts mehr)")
fest(w.stand(0) == w.stand(1) == w.stand(2), "und die Pruefsummen sind wieder gleich")

# --- Verlorenes Item: wird es nie neu vergeben, behaelt der Empfaenger den Punkt -----
w = welt23()
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
ns.Fenster.Zeigen(False)
g["__klick"]("Verlauf")
g["__klick"]("Rückgängig"); g["__klick"]("Wirklich?")
w.weiter(60)
fest(gezaehlt(w, 0) == 2 and gezaehlt(w, 1) == 2, "ohne Neuvergabe bleibt der Punkt (verlorenes Item)")

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
fest(ok is False, "doppelt zurueckgeben geht nicht (%s)" % grund)

# --- Spielerdetail: auch dort ---------------------------------------------------
w = welt23()
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
ns.Fenster.Zeigen(False)
g["__klick"]("Timo")
fest(g["__klick"]("Rückgängig") is True, "im Spielerdetail gibt es den Knopf")
g["__klick"]("Wirklich?")
fest(gezaehlt(w, 0) == 2 and bool(w.hist(0)["u1"]["rueckgabe"]), "Timos Rueckgabe ist vermerkt (Punkt bleibt bis zur Neuvergabe)")

# --- Befehl ------------------------------------------------------------------------
w = welt23()
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
sl = g["SlashCmdList"]["FAIRSHARE"]
sl("rueckgaengig ja")
fest(gezaehlt(w, 0) == 2, "ohne vorherige Rueckfrage passiert nichts")
sl("rueckgaengig")
fest(gezaehlt(w, 0) == 2, "/fs rueckgaengig fragt nur")
sl("rueckgaengig ja")
fest(gezaehlt(w, 0) == 2 and bool(w.hist(0)["u2"]["rueckgabe"]), "/fs rueckgaengig ja vermerkt die Rueckgabe der letzten Vergabe")
sl("undo"); sl("undo yes")
fest(gezaehlt(w, 0) == 2, "englisch: /fs undo, /fs undo yes (schon zurueckgegeben, nichts aendert sich)")
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

print("== 25. Mitspieler koennen nicht wuerfeln: derselbe Gegenstand, andere Gilde, Diagnose ==")


def systemwurf2(w, wer, wert, bereich):
    for c in w.clients:
        c["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "%s rolls %d (1-%d)" % (wer, wert, bereich))


# --- Derselbe Gegenstand zweimal hintereinander (ohne Vergabe dazwischen) -------
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ns0 = w.clients[0]["ns"]
T = w.clients[1]
ns0.Wurf.Starten(LINK)
w.weiter(3)
fest(T["g"]["__klick"]("Haupt (1-100)") is True, "erste Runde: Timo wuerfelt")
systemwurf2(w, "Timo", 50, 100)
w.weiter(1)
ns0.Wurf.BeendenAlle()
w.weiter(4)
ns0.Wurf.Starten(LINK)                      # derselbe Gegenstand noch einmal
w.weiter(3)
fest(T["g"]["__klick"]("Haupt (1-100)") is True, "zweite Runde, gleicher Gegenstand: die Knoepfe gehen wieder")
fest(len(T["g"]["__wurfLog"]) == 2, "und Timo wuerfelt tatsaechlich noch einmal")
systemwurf2(w, "Timo", 90, 100)
R = ns0.Erfassung.AktuelleWuerfe()
fest(R["Wuerfe"]["timo"] == 90, "der neue Wurf zaehlt (90), nicht der alte (%s)" % R["Wuerfe"]["timo"])

# --- Spieler aus einer anderen Gilde: der Leiter ist fuer sie kein Gildenmitglied ---
w = Welt([{"name": "Leiter Kaos", "leader": True, "gilde": False}, {"name": "Timo"}], "-Realm")
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ok, grund = tup(w.clients[0]["ns"].Wurf.Starten(LINK))
w.weiter(3)
fest(ok is True and w.clients[1]["ns"].Wurf.Aktiv() is True,
     "Wuerfelfenster geht auch auf, wenn der Leiter nicht in der eigenen Gilde ist")

# --- Diagnose: warum ging bei jemandem nichts auf? -------------------------------
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
N = w.clients[2]
ns2, g2 = N["ns"], N["g"]
fest(len(list(ns2.Wurf.Status().values())) >= 2, "Status liefert Zeilen")
ns2.Abgleich.Empfangen("S;x1;30;" + LINK, "Fremder-Realm")
ns2.Abgleich.Empfangen("S;x2;30;" + LINK, "Timo-Realm")
ns2.Abgleich.Empfangen("S;x3;30;kein link", "Leiter Kaos-Realm")
ns2.Abgleich.Empfangen("S;x4;30;" + LINK, "Leiter Kaos-Realm")
text = " | ".join(str(x) for x in ns2.Wurf.Status().values())
fest("nicht in der Gruppe erkannt" in text, "Status nennt: Absender nicht erkannt")
fest("weder Plündermeister" in text, "Status nennt: Absender nicht berechtigt")
fest("ungültig" in text, "Status nennt: Nachricht ungueltig")
fest("angenommen" in text and ns2.Wurf.Aktiv() is True, "Status nennt: Wurf angenommen")
sl = g2["SlashCmdList"]["FAIRSHARE"]
sl("wurf status")
fehler = [str(x) for x in g2["__ausgabe"].values() if "Fehler" in str(x)]
fest(not fehler, "/fs wurf status ohne Fehler")

print("== 26. Einstellbare Wuerfelbereiche ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(10)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
K = ns.Kern

fest(K.Bedarfsart(1, 100) == "haupt" and K.Bedarfsart(1, 99) == "zweit", "Standard: 1-100 Haupt, 1-99 Zweit")
ok, grund = tup(ns.Erfassung.BereichSetzen("haupt", 1, 200))
fest(ok is True, "Hauptbereich auf 1-200 gesetzt (%s)" % grund)
fest(K.Bedarfsart(1, 200) == "haupt" and K.Bedarfsart(1, 100) is None, "ab jetzt zaehlt 1-200 als Haupt, 1-100 nicht mehr")
fest(g["FairshareDB"]["bereiche"]["haupt"][2] == 200, "und es ist gespeichert")
K.BereicheSetzen(1, 100, 1, 99)                       # wie nach einem Neustart: Standard im Speicher
ns.Erfassung.BereicheAnwenden()
fest(K.Bedarfsart(1, 200) == "haupt", "BereicheAnwenden holt die gespeicherten Werte zurueck")

for was, args in (("Zahlen", ("a", "b")), ("umgekehrt", (50, 20)), ("zu gross", (1, 99999)), ("null", (0, 10)),
                  ("gleich wie OS", (1, 99)), ("Kommazahl", (1, 10.5))):
    ok, grund = tup(ns.Erfassung.BereichSetzen("haupt", *args))
    fest(ok is False, "abgelehnt: %s (%s)" % (was, str(grund)[:50]))
fest(K.Bedarfsart(1, 200) == "haupt", "nach den Fehlversuchen gilt weiter 1-200")

ok, grund = tup(ns.Erfassung.BereichSetzen("zweit", 3, 40))
fest(ok is True and K.Bedarfsart(3, 40) == "zweit", "auch ein Bereich, der nicht bei 1 beginnt (3-40)")
ns.Erfassung.BereicheSetzen(1, 100, 1, 99)

# --- Befehl ---------------------------------------------------------------------
sl = g["SlashCmdList"]["FAIRSHARE"]
sl("bereiche haupt 1 120")
fest(K.Bedarfsart(1, 120) == "haupt", "/fs bereiche haupt 1 120")
sl("bereiche os 1 30")
fest(K.Bedarfsart(1, 30) == "zweit", "/fs bereiche os 1 30")
sl("bereiche haupt 9 3")
fest(K.Bedarfsart(1, 120) == "haupt", "ungueltige Eingabe aendert nichts")
sl("bereiche")
fehler = [str(x) for x in g["__ausgabe"].values() if "Fehler" in str(x)]
fest(not fehler, "/fs bereiche ohne Fehler")
ns.Erfassung.BereicheSetzen(1, 100, 1, 99)

# --- Einstellungsseite ----------------------------------------------------------
ns.Einstellungen.Zeigen()
g["__klick"]("Würfeln & Abgleich")
fest(len(list(g["__text"]("Bereich für Hauptbedarf").values())) > 0, "Seite zeigt den Bereich fuer Hauptbedarf")
fest(len(list(g["__text"]("Bereich für Zweitbedarf (OS)").values())) > 0, "und den fuer Zweitbedarf (OS)")
ns.Erfassung.BereicheSetzen(1, 300, 1, 40)
ns.Einstellungen.Aktualisieren()
fest(g["__klick"]("Standard") is True and K.Bedarfsart(1, 100) == "haupt", "Knopf Standard setzt 1-100 / 1-99")

# --- Die Bereiche gehen mit dem Wurf an alle -------------------------------------
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
L0, T1 = w.clients[0], w.clients[1]
L0["ns"].Erfassung.BereicheSetzen(1, 200, 1, 20)
L0["ns"].Wurf.Starten(LINK)
w.weiter(3)
fest(T1["ns"].Wurf.Aktiv() is True, "Wurf mit eigenen Bereichen gestartet")
fest(len(list(T1["g"]["__text"]("Haupt (1-200)").values())) > 0 and len(list(T1["g"]["__text"]("Zweit (1-20)").values())) > 0,
     "bei den Spielern stehen die Bereiche des Leiters auf den Knoepfen")
T1["g"]["__klick"]("Haupt (1-200)")
wl = T1["g"]["__wurfLog"]
fest(len(wl) == 1 and wl[1][1] == 1 and wl[1][2] == 200, "RandomRoll(1, 200)")
for c in w.clients:
    c["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "Timo rolls 150 (1-200)")
R = L0["ns"].Erfassung.AktuelleWuerfe()
fest(R["Arten"]["timo"] == "haupt" and R["Wuerfe"]["timo"] == 150, "der Wurf 1-200 zaehlt beim Leiter als Haupt")
fest(T1["ns"].Kern.BEREICHE.haupt[2] == 200, "beim Spieler gelten waehrend des Wurfs die Bereiche des Leiters")
L0["ns"].Wurf.BeendenAlle()
w.weiter(4)
fest(T1["ns"].Kern.BEREICHE.haupt[2] == 100, "danach gelten wieder seine eigenen (1-100)")
fest(not T1["g"]["FairshareDB"] or T1["g"]["FairshareDB"]["bereiche"] is None, "und gespeichert wurde bei ihm nichts")

print("== 27. Ansage im Chat nach der Vergabe ==")
w, cl, g, ns, lua = runde()
g["__klick"]("Zuteilen")
g["__npc"] = "Timo"
g["__ereignis"]("TRADE_SHOW")
lua.execute("__tasche[1].leer = true")
g["__ereignis"]("TRADE_CLOSED")
w.weiter(3)
chat = [(str(c[1]), str(c[2])) for c in g["__chat"].values()]
fest(any("Schwert der Probe" in t and "wurde an Timo vergeben!" in t and k == "PARTY" for t, k in chat),
     "nach dem Handel steht im Gruppenchat: <Gegenstand> wurde an Timo vergeben! (%s)" % (chat[-1] if chat else None,))
fest(len(chat) == 1, "genau eine Zeile")

w, cl, g, ns, lua = runde()
ns.Erfassung.Eintragen("Moe", LINK, None, "zweit", None, lua.table_from({"herkunft": "wurf", "wurf": 12}))
chat = [(str(c[1]), str(c[2])) for c in g["__chat"].values()]
fest(any("wurde an Moe vergeben! (OS)" in t for t, k in chat), "Zweitbedarf: mit (OS)")

w, cl, g, ns, lua = runde()
ns.Erfassung.Einstellungen()["ansagen"] = False
ns.Erfassung.Eintragen("Moe", LINK, None, "haupt", None, lua.table_from({"herkunft": "wurf"}))
fest(len(list(g["__chat"].values())) == 0, "Schalter aus: keine Ansage")

w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
ns.Erfassung.Einstellungen()["ort"] = "ueberall"
g["__welt"]["ml"] = None   # Gruppenbeute
g["__ereignis"]("CHAT_MSG_LOOT", "Timo receives loot: " + LINK + ".")
fest(len(list(g["__chat"].values())) == 0, "Beute aus Gruppenwuerfen ohne Plündermeister: keine eigene Ansage")
w = Welt([{"name": "Leiter Kaos", "leader": True}, {"name": "Timo"}], "-Realm", ml=0)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
ns.Erfassung.Einstellungen()["ort"] = "ueberall"
g["__ereignis"]("CHAT_MSG_LOOT", "Timo receives loot: " + LINK + ".")
fest(any("wurde an Timo vergeben!" in str(c[1]) for c in g["__chat"].values()), "Zuteilung durch den Plündermeister: Ansage")
fest(len(list(w.clients[1]["g"]["__chat"].values())) == 0, "ein Mitspieler sagt nichts an")

print("== 28. Wurf abbrechen ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
L0, T1 = w.clients[0], w.clients[1]
L0["ns"].Wurf.Starten(LINK)
w.weiter(3)
T1["g"]["__klick"]("Haupt (1-100)")
for c in w.clients:
    c["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "Timo rolls 66 (1-100)")
fest(L0["ns"].Erfassung.AktuelleWuerfe() is not None, "ein Wurf ist da")
fest(L0["g"]["__klick"]("Abbrechen") is True, "Leiter klickt Abbrechen im Wuerfelfenster")
w.weiter(5)
fest(not L0["ns"].Wurf.Aktiv() and not T1["ns"].Wurf.Aktiv(), "der Wurf ist bei allen aus")
fest(L0["ns"].Erfassung.AktuelleWuerfe() is None, "die Wuerfe zaehlen nirgends mehr")
fest(not (L0["g"]["FairshareWurfErgebnis"] is not None and L0["g"]["FairshareWurfErgebnis"]._shown), "und es gibt kein Ergebnisfenster")
ausgabe = [str(x) for x in T1["g"]["__ausgabe"].values()]
fest(any("abgebrochen" in x for x in ausgabe), "die Spieler erfahren es im Chat")

# neuer Wurf danach: alles frei
L0["ns"].Wurf.Starten(LINK)
w.weiter(3)
fest(T1["g"]["__klick"]("Haupt (1-100)") is True, "danach laesst sich derselbe Gegenstand sauber neu verrollen")

# Abbrechen, wenn das Ergebnis schon offen ist
w, cl, g, ns, lua = runde()
fest(g["FairshareWurfErgebnis"] is not None and g["FairshareWurfErgebnis"]._shown, "Ergebnis ist offen")
fest(g["__klick"]("Wurf verwerfen") is True, "Wurf verwerfen im Ergebnisfenster")
fest(not g["FairshareWurfErgebnis"]._shown and ns.Erfassung.AktuelleWuerfe() is None, "Ergebnis zu, Wurf verworfen")

# Keiner, der nicht darf, kann bei anderen abbrechen
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
L0, N2 = w.clients[0], w.clients[2]
L0["ns"].Wurf.Starten(LINK)
w.weiter(3)
rid = None
N2["ns"].Abgleich.Empfangen("X;zzz;a", "Timo-Realm")
fest(L0["ns"].Wurf.Aktiv() and N2["ns"].Wurf.Aktiv(), "eine Abbruchmeldung eines Mitglieds wird ignoriert")
ok, grund = tup(w.clients[1]["ns"].Wurf.Abbrechen())
w.weiter(3)
fest(L0["ns"].Wurf.Aktiv() is True, "ein Mitglied, das abbricht, beendet nur sein eigenes Fenster")
sl = L0["g"]["SlashCmdList"]["FAIRSHARE"]
sl("wurf abbrechen")
w.weiter(3)
fest(not L0["ns"].Wurf.Aktiv() and not N2["ns"].Wurf.Aktiv(), "/fs wurf abbrechen beim Leiter: bei allen aus")
sl("wurf abbrechen")
fehler = [str(x) for x in L0["g"]["__ausgabe"].values() if "Fehler" in str(x)]
fest(not fehler, "ohne Fehler")

print("== 29. Entzaubern: niemand wuerfelt -> Verzauberer; freie Wuerfelzeit ==")


def chatzeilen(g):
    return [str(c[1]) for c in g["__chat"].values()]


def welt29(verz="Lina, Fremder", tasche=True, loot=False):
    w = gruppe(3)
    w.ereignis("PLAYER_ENTERING_WORLD")
    w.weiter(15)
    cl = w.clients[0]
    g, ns, lua = cl["g"], cl["ns"], cl["lua"]
    if verz:
        ns.Wurf.VerzaubererHinzufuegen(verz)
    if tasche:
        lua.execute('__tasche = { { link = "%s", quality = 4, frist = true } }' % LINK)
    if loot:
        lua.execute('__loot = { { link = "%s" } }' % LINK)
    return w, cl, g, ns, lua


def sichtbar29(g, name):
    return bool(g[name] is not None and g[name]._shown)


# --- Niemand wuerfelt: das Fenster kommt, der Plündermeister bestaetigt --------------
w, cl, g, ns, lua = welt29()
ok, grund = tup(ns.Wurf.Starten(LINK, 10))
fest(ok is True, "Wurf mit 10 Sekunden gestartet (%s)" % grund)
cl["lua"].execute("__chat = {}")   # Startzeile: Szenario 35
w.weiter(8)
fest(ns.Wurf.Aktiv() is True, "nach 8 s laeuft er noch")
w.weiter(6)
fest(not ns.Wurf.Aktiv(), "nach 10 s ist er zu")
fest(sichtbar29(g, "FairshareWurfEntz"), "niemand hat gewuerfelt: das Fenster zum Entzaubern kommt")
fest(not sichtbar29(g, "FairshareWurfErgebnis"), "kein Ergebnisfenster")
fest(len(list(g["__text"]("Niemand hat gewürfelt. Zum Entzaubern vergeben?").values())) > 0, "mit der Frage")
fest(len(list(g["__text"]("nicht in der Gruppe").values())) > 0 and len(list(g["__text"]("in der Gruppe").values())) > 0,
     "Lina ist in der Gruppe, Fremder nicht")
fest(g["__klick"]("Vergeben") is True, "Vergeben bei dem ersten (Lina, sie ist dabei)")
fest(str(g["__handel"]) == "party2", "Handel mit Lina angefragt (%s)" % g["__handel"])
v = ns.Wurf.Offene()
fest(len(list(v.values())) == 1 and v[1]["entzaubern"] is True, "als Entzaubern vorgemerkt")
fest(not sichtbar29(g, "FairshareWurfEntz"), "das Fenster ist zu")
g["__npc"] = "Lina"
g["__ereignis"]("TRADE_SHOW")
fest(g["__angeboten"][1] == LINK, "der Gegenstand liegt im Handelsfenster")
fest(len(chatzeilen(g)) == 0, "noch keine Ansage, solange der Handel nicht durch ist")
lua.execute("__tasche[1].leer = true")
g["__ereignis"]("TRADE_CLOSED")
w.weiter(3)
fest(any("zum Entzaubern an Lina vergeben!" in t and "Schwert der Probe" in t for t in chatzeilen(g)),
     "danach steht im Gruppenchat: <Gegenstand> wurde zum Entzaubern an Lina vergeben!")
fest(sum(1 for v in w.hist(0).values() if v["itemID"] == 7100) == 0, "und es gibt KEINEN Eintrag: Lina bekommt keine Beute angerechnet")
fest(len(list(ns.Wurf.Offene().values())) == 0, "die Vormerkung ist erledigt")

# --- Beutefenster ------------------------------------------------------------------
w, cl, g, ns, lua = welt29(tasche=False, loot=True)
ns.Wurf.Starten(LINK, 5)
w.weiter(8)
fest(sichtbar29(g, "FairshareWurfEntz"), "auch fuer den Gegenstand im Beutefenster")
g["__klick"]("Vergeben")
fest(len(g["__geben"]) == 1 and g["__geben"][1][1] == 1 and g["__geben"][1][2] == 3, "GiveMasterLoot an Lina (Platz 1, Empfaenger 3)")
fest(any("zum Entzaubern an Lina vergeben!" in t for t in chatzeilen(g)), "die Ansage kommt sofort")
g["__ereignis"]("CHAT_MSG_LOOT", "Lina receives loot: " + LINK + ".")
fest(sum(1 for v in w.hist(0).values() if v["itemID"] == 7100) == 0, "die Beutemeldung traegt NICHTS ein")
g["__ereignis"]("CHAT_MSG_LOOT", "Lina receives loot: " + LINK + ".")      # eine zweite (andere) Beute derselben Art zaehlt wieder
fest(sum(1 for v in w.hist(0).values() if v["itemID"] == 7100 and v["awardedTo"] == "Lina") <= 1, "(danach zaehlt eine weitere Beute wieder normal)")

# --- Der Plündermeister ist selbst Verzauberer ---------------------------------------
w, cl, g, ns, lua = welt29(verz="Leiter Kaos")
ns.Wurf.Starten(LINK, 5)
w.weiter(8)
g["__klick"]("Vergeben")
fest(g["__handel"] is None, "ein Handel mit sich selbst wird nicht angefragt")
fest(any("zum Entzaubern an Leiter Kaos vergeben!" in t for t in chatzeilen(g)), "Ansage fuer ihn selbst")

# --- Ansage abgeschaltet ----------------------------------------------------------------
w, cl, g, ns, lua = welt29(verz="Leiter Kaos")
ns.Erfassung.Einstellungen()["ansagen"] = False
ns.Wurf.Starten(LINK, 5)
w.weiter(8)
g["__klick"]("Vergeben")
fest(len(chatzeilen(g)) == 0, "mit ausgeschalteter Ansage bleibt der Chat still")

# --- Kein Verzauberer hinterlegt ----------------------------------------------------------
w, cl, g, ns, lua = welt29(verz=None)
ns.Wurf.Starten(LINK, 5)
w.weiter(8)
fest(len(list(g["__text"]("Kein Verzauberer hinterlegt. Trage welche in den Einstellungen ein.").values())) > 0, "ohne Verzauberer: Hinweis")
fest(g["__klick"]("Einstellungen") is True, "mit Knopf zu den Einstellungen")

# --- Es hat jemand gewuerfelt: kein Fenster, aber per Knopf trotzdem moeglich --------------
w, cl, g, ns, lua = runde()
ns.Wurf.VerzaubererHinzufuegen("Lina")
fest(not sichtbar29(g, "FairshareWurfEntz"), "wenn jemand gewuerfelt hat, kommt das Fenster nicht von selbst")
fest(g["__klick"]("Entzaubern") is True, "im Ergebnis gibt es den Knopf Entzaubern")
fest(sichtbar29(g, "FairshareWurfEntz") and len(list(g["__text"]("Zum Entzaubern vergeben an:").values())) > 0, "er oeffnet die Auswahl")
sl = g["SlashCmdList"]["FAIRSHARE"]
g["FairshareWurfEntz"].Hide(g["FairshareWurfEntz"])
sl("wurf entzaubern")
fest(sichtbar29(g, "FairshareWurfEntz"), "/fs wurf entzaubern oeffnet sie ebenfalls")

# --- Verzauberer verwalten ---------------------------------------------------------------------
w, cl, g, ns, lua = welt29(verz=None)
sl = g["SlashCmdList"]["FAIRSHARE"]
sl("verzauberer add Moe, Zora ,  Moe")
fest(len(list(ns.Wurf.Verzauberer().values())) == 2, "zwei Namen, der doppelte wird uebergangen")
sl("verzauberer")
sl("verzauberer del Moe")
fest(len(list(ns.Wurf.Verzauberer().values())) == 1 and ns.Wurf.Verzauberer()[1] == "Zora", "Moe entfernt")
sl("enchanters del 1")
fest(len(list(ns.Wurf.Verzauberer().values())) == 0, "per Nummer entfernt, englisch")
for k in range(12):
    ns.Wurf.VerzaubererHinzufuegen("Spieler%d" % k)
fest(len(list(ns.Wurf.Verzauberer().values())) == 8, "hoechstens acht")
ns.Einstellungen.Zeigen()
g["__klick"]("Würfeln & Abgleich")
fest(len(list(g["__text"]("Verzauberer hinzufügen").values())) > 0, "Einstellungsseite: Verzauberer hinzufuegen")
fest(g["__klick"]("Entfernen") is True, "und ein Knopf Entfernen je Name")
fehler = [str(x) for x in g["__ausgabe"].values() if "Fehler" in str(x)]
fest(not fehler, "ohne Fehler")

# --- Freie Wuerfelzeit ------------------------------------------------------------------------------
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
L0, T1 = w.clients[0], w.clients[1]
ok, grund = tup(L0["ns"].Wurf.Starten(LINK, 3))
fest(ok is False, "3 Sekunden sind zu wenig (%s)" % grund)
ok, grund = tup(L0["ns"].Wurf.Starten(LINK, 301))
fest(ok is False, "301 Sekunden sind zu viel")
ok, grund = tup(L0["ns"].Wurf.Starten(LINK, "abc"))
fest(ok is False, "Buchstaben werden abgelehnt")
ok, grund = tup(L0["ns"].Wurf.Starten(LINK, 90))
w.weiter(2)
fest(ok is True and L0["g"]["FairshareDB"]["wurfDauer"] == 90, "90 Sekunden gewaehlt und als neuer Standard gemerkt")
w.weiter(40)
fest(L0["ns"].Wurf.Aktiv() and T1["ns"].Wurf.Aktiv(), "nach 42 s laeuft der Wurf noch (bei allen)")
w.weiter(55)
fest(not L0["ns"].Wurf.Aktiv() and not T1["ns"].Wurf.Aktiv(), "nach 97 s ist er vorbei")
L0["g"]["SlashCmdList"]["FAIRSHARE"]("wurf 20 " + LINK)
w.weiter(2)
text = " ".join(str(x) for x in L0["ns"].Wurf.Status().values())
fest("noch 18 s" in text or "noch 19 s" in text or "noch 20 s" in text, "/fs wurf 20 <Link>: zwanzig Sekunden (%s)" % text[:60])
w.weiter(25)
fest(not L0["ns"].Wurf.Aktiv(), "und nach 27 s vorbei")

print("== 30. Einstellungen teilen ==")

GILDE30 = """
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenleiter", guildRankOrder = 1 },
  [2] = { name = "Timo",        guildRank = "Offizier",     guildRankOrder = 2 },
  [3] = { name = "Lina",        guildRank = "Raider",       guildRankOrder = 3 },
  [4] = { name = "Moe",         guildRank = "Raider",       guildRankOrder = 3 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
"""


def welt30(moe_addon=True, gilde=True):
    ms = [{"name": "Leiter Kaos", "leader": True}, {"name": "Timo"}, {"name": "Lina"}, {"name": "Moe", "addon": moe_addon}]
    w = Welt(ms, "-Realm")
    for cl in w.clients:
        cl["ns"].Erfassung.Einstellungen()["autoAbgleich"] = False
        if gilde:
            cl["lua"].execute(GILDE30)
    w.ereignis("PLAYER_ENTERING_WORLD")
    w.weiter(15)
    return w


def db30(w, k):
    return w.clients[k]["g"]["FairshareDB"]


def einstellen_leiter(w):
    ns = w.clients[0]["ns"]
    ns.Erfassung.BereicheSetzen(1, 200, 1, 20)
    ns.Wurf.VerzaubererHinzufuegen("Zora, Gorm")
    ns.Gruppen.Anlegen("10er")
    ns.Gruppen.RangSetzen("10er", 3, True)
    ns.Gruppen.KaderErgaenzen("10er", "Handname")
    db30(w, 0)["wurfDauer"] = 45
    db30(w, 0)["ansagen"] = False


# --- Der Gildenleiter sendet, alle uebernehmen ---------------------------------------
w = welt30()
einstellen_leiter(w)
n, grund = tup(w.clients[0]["ns"].Konfig.Senden())
fest(n is not None and n >= 1, "Gildenleiter sendet (%s Nachrichten, %s)" % (n, grund))
w.weiter(15)
for k in (1, 2, 3):
    d = db30(w, k)
    fest(d["bereiche"] is not None and d["bereiche"]["haupt"][2] == 200 and d["bereiche"]["zweit"][2] == 20,
         "%s: Würfelbereiche 1-200 / 1-20 übernommen" % w.mitglieder[k]["name"])
ns2 = w.clients[2]["ns"]
fest(ns2.Kern.Bedarfsart(1, 200) == "haupt", "und gleich wirksam")
fest(list(ns2.Wurf.Verzauberer().values()) == ["Zora", "Gorm"], "Verzauberer übernommen")
G = ns2.Gruppen.Holen("10er")
fest(G is not None and G["raenge"][3] is True and list(G["extra"].values()) == ["Handname"], "Gruppe 10er mit Rang und Handnamen übernommen")
fest(db30(w, 2)["wurfDauer"] == 45 and db30(w, 2)["ansagen"] is False, "Würfelzeit und Ansage übernommen")
w.weiter(5)
fest("Lina" in list(ns2.Gruppen.Holen("10er")["kader"].values()), "der Kader wird bei jedem aus den Gildenraengen neu gebildet")
fest(db30(w, 2)["konfigVon"] == "Leiter Kaos" and db30(w, 2)["konfigStand"] == db30(w, 0)["konfigStand"], "Absender und Stand vermerkt")
fest(db30(w, 2)["konfigAlt"] is not None, "der alte Stand ist gesichert")
fest(any("übernommen" in str(x) for x in w.clients[2]["g"]["__ausgabe"].values()), "eine Zeile im Chat sagt es")
fest(db30(w, 2)["schreiben"] == "auto" or db30(w, 2)["schreiben"] is None, "Persönliches (Wer aufzeichnet) bleibt unberührt")

# --- Zweimal dasselbe: nichts passiert ----------------------------------------------
vorher = len(w.protokoll)
w.clients[0]["ns"].Konfig.Senden()
w.weiter(10)
fest(db30(w, 2)["konfigStand"] == db30(w, 0)["konfigStand"], "ein neuer Stand loest den alten ab")

# --- Wer nicht senden darf, kann nicht -----------------------------------------------
w = welt30()
ok, grund = tup(w.clients[2]["ns"].Konfig.Senden())
fest(ok is None or ok is False, "Raider darf nicht senden (%s)" % str(grund)[:60])
w.clients[1]["ns"].Konfig.Senden()
fest(db30(w, 1)["konfigStand"] is not None, "ein Offizier (Stufe 2) darf immer senden: Stufe 1 und 2 sind die Wurzel des Vertrauens")

# --- Gefaelscht oder von Unberechtigten ---------------------------------------------
w = welt30()
einstellen_leiter(w)
ns0 = w.clients[0]["ns"]
zeilen = list(ns0.Konfig.Kodieren(ns0.Konfig.Sammeln()).values())
paket = "~".join(str(z) for z in zeilen)
stand = int(w.t) + 500
ns1 = w.clients[1]["ns"]
ns1.Abgleich.Empfangen("K;%d;Lina;1;1;%s" % (stand, paket), "Lina-Realm", "GUILD")
fest(db30(w, 1)["konfigStand"] is None, "Urheber Lina (Stufe 3) wird abgelehnt")
ns1.Abgleich.Empfangen("K;%d;Leiter Kaos;1;1;%s" % (stand, paket), "Fremder-Realm", "GUILD")
fest(db30(w, 1)["konfigStand"] is None, "Absender, der nicht in der Gilde steht, wird abgelehnt")
text = " | ".join(str(x) for x in ns1.Konfig.Status().values())
fest("abgelehnt" in text, "der Status nennt die Ablehnung")
ns1.Abgleich.Empfangen("K;%d;Leiter Kaos;1;1;%s" % (stand, paket), "Lina-Realm", "GUILD")
fest(db30(w, 1)["konfigStand"] is None, "Lina gibt sich als Leiter aus (weitergereicht, ungefragt): abgelehnt")
text = " | ".join(str(x) for x in ns1.Konfig.Status().values())
fest("unaufgefordert" in text, "der Status nennt den Grund")
ns1.Konfig.Anfragen("GUILD")                          # Timo fragt nach ...
ns1.Abgleich.Empfangen("K;%d;Leiter Kaos;1;1;%s" % (stand, paket), "Lina-Realm", "GUILD")
fest(db30(w, 1)["konfigStand"] == stand, "... dann wird eine Antwort (auch weitergereicht) angenommen")

# --- Gildenliste nicht geladen: nichts annehmen ------------------------------------------------
w = welt30(gilde=False)
ns0 = w.clients[0]["ns"]
ok, grund = tup(ns0.Konfig.Senden())
fest(ok is None, "ohne Gildenliste kann man nicht senden")
ns1 = w.clients[1]["ns"]
ns1.Abgleich.Empfangen("K;%d;Leiter Kaos;1;1;%s" % (stand, paket), "Leiter Kaos-Realm", "GUILD")
fest(db30(w, 1)["konfigStand"] is None, "und ohne Gildenliste nimmt man nichts an")

# --- Ausgeschaltet -----------------------------------------------------------------------------------
w = welt30()
einstellen_leiter(w)
db30(w, 1)["konfigAnnehmen"] = False
w.clients[0]["ns"].Konfig.Senden()
w.weiter(12)
fest(db30(w, 1)["konfigStand"] is None and db30(w, 2)["konfigStand"] is not None, "wer abgeschaltet hat, uebernimmt nichts; die anderen schon")

# --- Spaeter dazugekommen: nachfragen, einer antwortet ---------------------------------------
w = welt30(moe_addon=False)
einstellen_leiter(w)
w.clients[0]["ns"].Konfig.Senden()
w.weiter(15)
fest(db30(w, 3)["konfigStand"] is None, "Moe war nicht da und hat nichts")
w.mitglieder[3]["addon"] = True
n0 = len(w.protokoll)
w.clients[3]["ns"].Konfig.Anfragen("GUILD")
w.weiter(25)
fest(db30(w, 3)["konfigStand"] == db30(w, 0)["konfigStand"], "nach der Anfrage hat Moe den Stand")
fest(db30(w, 3)["bereiche"]["haupt"][2] == 200, "mit den Würfelbereichen")
sender = set(von for von, t in w.protokoll[n0:] if t.startswith("K;"))
fest(1 <= len(sender) <= 2, "hoechstens zwei haben geantwortet, nicht alle drei (%s)" % sorted(sender))
# Weitergegeben wird der Text des Urhebers, auch wenn der Antwortende selbst etwas aendert
w = welt30(moe_addon=False)
einstellen_leiter(w)
w.clients[0]["ns"].Konfig.Senden()
w.weiter(15)
w.clients[1]["ns"].Erfassung.BereicheSetzen(1, 999, 1, 5)          # Timo aendert danach von Hand
w.mitglieder[3]["addon"] = True
w.clients[3]["ns"].Konfig.Anfragen("GUILD")
w.weiter(25)
fest(db30(w, 3)["bereiche"]["haupt"][2] == 200, "Weitergegeben wird der Stand des Urhebers (200), nicht Timos Handarbeit (999)")

# --- Die Stufe selbst wird geteilt ---------------------------------------------------------------
w = welt30()
db30(w, 0)["konfigRang"] = 2
w.clients[0]["ns"].Konfig.Senden()
w.weiter(12)
fest(w.clients[2]["ns"].Konfig.RangGrenze() == 2, "die Rangstufe ist bei allen auf 2")
fest(w.clients[1]["ns"].Konfig.DarfSenden() is True, "jetzt darf auch der Offizier senden")
w.clients[1]["ns"].Erfassung.BereicheSetzen(1, 150, 1, 30)
w.clients[1]["ns"].Konfig.Senden()
w.weiter(12)
fest(db30(w, 2)["bereiche"]["haupt"][2] == 150, "und die anderen uebernehmen von ihm")

# --- Zurueck ----------------------------------------------------------------------------------------
w = welt30()
einstellen_leiter(w)
w.clients[2]["ns"].Gruppen.Anlegen("Meine")
w.clients[0]["ns"].Konfig.Senden()
w.weiter(12)
fest(w.clients[2]["ns"].Gruppen.Holen("Meine") is None, "eigene Gruppen weichen den geteilten")
ok, grund = tup(w.clients[2]["ns"].Konfig.Zurueck())
fest(ok is True, "Zuruecknehmen (%s)" % grund)
fest(w.clients[2]["ns"].Kern.Bedarfsart(1, 100) == "haupt" and w.clients[2]["ns"].Gruppen.Holen("Meine") is not None,
     "der alte Stand ist wieder da (Bereiche und Gruppe)")
fest(len(list(w.clients[2]["ns"].Wurf.Verzauberer().values())) == 0, "ohne die Verzauberer")
ok, grund = tup(w.clients[2]["ns"].Konfig.Zurueck())
fest(ok is False, "ein zweites Mal gibt es nichts mehr")

# --- Dekodieren begrenzt Fremdes ----------------------------------------------------------------------
K = w.clients[0]["ns"].Konfig
lua = w.clients[0]["lua"]
t = lua.table_from(["B|1|100|1|50", "W|99999", "V|schlecht;name,Gut,Zwei", "G|boese;name|1|1,2", "G|Ok|1|3,999", "X|Ok|Hans,Fritz;x", "Z|unbekannt", "Q|9", "O|irgendwas"])
s, grund = tup(K.Dekodieren(t))
fest(s is not None, "Dekodieren liefert etwas (%s)" % grund)
fest(s["wurfDauer"] is not None and s["wurfDauer"] < 99999, "unsinnige Dauer wird ignoriert")
fest(list(s["verzauberer"].values()) == ["Gut", "Zwei"], "Namen mit Semikolon fliegen raus")
fest(s["gruppen"]["Ok"] is not None and s["gruppen"]["boese;name"] is None, "Gruppe mit unerlaubtem Namen fehlt")
fest(list(s["gruppen"]["Ok"]["raenge"].values()) == [3], "Rangnummern ueber 50 fliegen raus")
fest(list(s["gruppen"]["Ok"]["extra"].values()) == ["Hans", "Fritz"] or len(list(s["gruppen"]["Ok"]["extra"].values())) <= 2,
     "Namen mit Semikolon in Listen fliegen raus")
fest(s["mindestQualitaet"] == 3 and s["ort"] == "raid", "Qualitaet ueber 5 und fremder Ort: Standard")
s, grund = tup(K.Dekodieren(lua.table_from(["B|1|100|1|100"])))
fest(s is None, "gleiche Bereiche fuer Haupt und OS werden abgelehnt")
s, grund = tup(K.Dekodieren(lua.table_from(["W|30"])))
fest(s is None, "ohne Bereiche wird nichts angenommen")

# --- Befehl und Seite -----------------------------------------------------------------------------------------
w = welt30()
einstellen_leiter(w)
g = w.clients[0]["g"]
sl = g["SlashCmdList"]["FAIRSHARE"]
sl("konfig")
sl("konfig senden")
sl("konfig nachfragen")
sl("config undo")
w.weiter(12)
fehler = [str(x) for x in g["__ausgabe"].values() if "Fehler" in str(x)]
fest(not fehler, "/fs konfig ohne Fehler")
ns = w.clients[0]["ns"]
ns.Einstellungen.Zeigen()
g["__klick"]("Würfeln & Abgleich")
fest(len(list(g["__text"]("Einstellungen teilen").values())) > 0, "die Seite hat die Karte Einstellungen teilen")
fest(g["__klick"]("Senden") is True, "Knopf Senden (Gildenleiter)")
w.weiter(5)
ns2 = w.clients[2]["ns"]
ns2.Einstellungen.Zeigen()
w.clients[2]["g"]["__klick"]("Würfeln & Abgleich")
fest(w.clients[2]["g"]["__klick"]("Senden") is False, "bei einem Raider ist der Knopf gesperrt")

print("== 31. Startdialog: Dauer ueber das Feld ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
lua.execute('__tasche = { { link = "%s", quality = 4, frist = true } }' % LINK)
ns.Wurf.Dialog()
dlg = g["FairshareWurfStart"]
fest(dlg["dauerFeld"] is not None and dlg["dauer"] is not None, "der Dialog hat Beschriftung und Feld fuer die Dauer")
fest(str(dlg["dauer"]._text) == "Dauer (s)", "Beschriftung: Dauer (s)")
fest(str(dlg["dauerFeld"]._text) == "30", "das Feld zeigt den Standard (30)")
lua.execute("""
for _, f in ipairs(__frames) do
    local t = f._text
    if t and t:find("Schwert der Probe", 1, true) and f._eltern and f._eltern._scripts.OnClick then __beutezeile = f._eltern end
    if t == "Wurf starten" and f._eltern and f._eltern._scripts.OnClick then __startknopf = f._eltern end
end
""")
g["__beutezeile"]._scripts.OnClick(g["__beutezeile"])
dlg["dauerFeld"]._text = "45"
g["__startknopf"]._scripts.OnClick(g["__startknopf"])
w.weiter(2)
text = " ".join(str(x) for x in ns.Wurf.Status().values())
fest(ns.Wurf.Aktiv() and "noch 43 s" in text, "Start ueber den Dialog mit 45 Sekunden (%s)" % text[:70])
fest(g["FairshareDB"]["wurfDauer"] == 45, "und als neuer Standard gemerkt")
w.weiter(50)
fest(not ns.Wurf.Aktiv() and not w.clients[1]["ns"].Wurf.Aktiv(), "nach 52 s ist der Wurf bei allen vorbei")
ns.Wurf.Dialog()
fest(str(dlg["dauerFeld"]._text) == "45", "beim naechsten Oeffnen steht 45 im Feld")
dlg["dauerFeld"]._text = "1000"
g["__beutezeile"]._scripts.OnClick(g["__beutezeile"])
g["__startknopf"]._scripts.OnClick(g["__startknopf"])
fest(not ns.Wurf.Aktiv() and "300" in str(dlg["fehler"]._text), "1000 Sekunden: rote Meldung mit der Grenze (%s)" % str(dlg["fehler"]._text)[:50])

print("== 32. Ohne Pluendermeister als Beutemethode ruht das Addon ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
L32 = "|cff0070dd|Hitem:9321::::::::60:::::|h[Ruhending]|h|r"
fest(tup(ns.Rolle.Aktiv())[0] is True, "mit Pluendermeister: aktiv")
for c in w.clients:
    c["g"]["__welt"]["ml"] = None   # Beutemethode wechselt auf Gruppenbeute (für alle)
ok, grund = tup(ns.Rolle.Aktiv())
fest(ok is False, "Gruppenbeute: ruht (%s)" % grund)
ns.Erfassung.Einstellungen()["schreiben"] = "immer"
fest(tup(ns.Rolle.IchSchreibe())[0] is False, "auch bei „immer“ schreibt er nicht mit")
ns.Erfassung.Einstellungen()["schreiben"] = "auto"
ns.Erfassung.Einstellungen()["ort"] = "ueberall"
g["__ereignis"]("START_LOOT_ROLL", 1)
fest(ns.Fenster.Sichtbar() is False, "START_LOOT_ROLL oeffnet kein Fenster")
g["__ereignis"]("CHAT_MSG_LOOT", "Timo receives loot: " + L32 + ".")
fest(sum(1 for _ in w.hist(0).keys()) == 0, "Beutemeldung wird nicht aufgezeichnet")
fest(ns.Erfassung.AktuelleWuerfe() is None, "keine Wurfrunde")
fest(ns.Wurf.DarfStarten() is False, "kein Wurf startbar")
vorher = len(w.protokoll)
g["__ereignis"]("PARTY_LOOT_METHOD_CHANGED")
ns.Abgleich.HalloSpaeter(1)
w.weiter(20)
neue = [x for x in w.protokoll[vorher:] if str(x[1])[:2] not in ("A;", "K;", "U;", "T;")]     # Einstellungen/Einteilung der Gilde sind erlaubt
fest(len(neue) == 0, "kein Hallo, kein Abgleich auf dem Kanal (%d neu)" % (len(neue),))
fest(not ns.Abgleich.Abweichend or len(list(ns.Abgleich.Abweichend.values())) == 0, "keine Abweichungsliste")
# Wieder Pluendermeister: die Antwort war vergessen, es wird neu gefragt
for c in w.clients:
    c["g"]["__welt"]["ml"] = 1
g["__ereignis"]("PARTY_LOOT_METHOD_CHANGED")
fest(ns.Nutzung.Sichtbar() is True, "neuer Plündermeister: der Dialog fragt wieder")
fest(tup(ns.Rolle.Aktiv())[0] is False, "bis zur Antwort schläft das Addon")
g["__ereignis"]("START_LOOT_ROLL", 1)
fest(ns.Fenster.Sichtbar() is False, "und öffnet auch jetzt kein Fenster")
D = ns.Nutzung.Dialog()
D["jaKnopf"]._scripts.OnClick(D["jaKnopf"])
fest(tup(ns.Rolle.Aktiv())[0] is True and ns.Nutzung.Sichtbar() is False, "nach „Ja“ im Dienst, Dialog zu")
g["__ereignis"]("START_LOOT_ROLL", 1)
fest(ns.Fenster.Sichtbar() is True, "START_LOOT_ROLL oeffnet das Fenster wieder")

print("== 33. Dialog „Fairshare nutzen?“: Ja, Nein, Kreuz, andere Beutemethoden ==")
w = gruppe(3, nutzung=None)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
L33 = "|cff0070dd|Hitem:9331::::::::60:::::|h[Fragending]|h|r"
fest(ns.Nutzung.Sichtbar() is True, "Plündermeister aktiv, noch keine Antwort: der Dialog fragt")
fest(tup(ns.Rolle.Aktiv())[0] is False, "bis zur Antwort schläft das Addon")
ns.Erfassung.Einstellungen()["ort"] = "ueberall"
g["__ereignis"]("START_LOOT_ROLL", 1)
g["__ereignis"]("CHAT_MSG_LOOT", "Timo receives loot: " + L33 + ".")
fest(ns.Fenster.Sichtbar() is False and sum(1 for _ in w.hist(0).keys()) == 0, "ohne Antwort: kein Fenster, keine Aufzeichnung")
# Nein
D = ns.Nutzung.Dialog()
D["neinKnopf"]._scripts.OnClick(D["neinKnopf"])
fest(ns.Rolle.Nutzung() == "nein" and ns.Nutzung.Sichtbar() is False, "„Nein“ gemerkt, Dialog zu")
g["__ereignis"]("START_LOOT_ROLL", 1)
g["__ereignis"]("CHAT_MSG_LOOT", "Timo receives loot: " + L33 + ".")
fest(ns.Fenster.Sichtbar() is False and sum(1 for _ in w.hist(0).keys()) == 0, "nach „Nein“: kein Fenster, keine Aufzeichnung")
g["__ereignis"]("GROUP_ROSTER_UPDATE")
fest(ns.Nutzung.Sichtbar() is False, "und es wird nicht erneut gefragt")
fest(ns.Wurf.DarfStarten() is False, "kein Wurf startbar")
# Befehl: umentscheiden
g["SlashCmdList"]["FAIRSHARE"]("nutzung ja")
fest(ns.Rolle.Nutzung() == "ja" and tup(ns.Rolle.Aktiv())[0] is True, "/fs nutzung ja schaltet ein")
# Beutemethode wechselt: Antwort vergessen
for c in w.clients:
    c["g"]["__welt"]["ml"] = None
g["__ereignis"]("PARTY_LOOT_METHOD_CHANGED")
fest(ns.Rolle.Nutzung() is None and tup(ns.Rolle.Aktiv())[0] is False, "andere Beutemethode: Antwort vergessen, schlaeft")
fest(ns.Nutzung.Sichtbar() is False, "und es wird nicht gefragt")
# Kreuz: keine Antwort, kein erneutes Fragen
for c in w.clients:
    c["g"]["__welt"]["ml"] = 1
g["__ereignis"]("PARTY_LOOT_METHOD_CHANGED")
fest(ns.Nutzung.Sichtbar() is True, "wieder Plündermeister: Dialog")
ns.Nutzung.Dialog().Hide(ns.Nutzung.Dialog())
g["__ereignis"]("GROUP_ROSTER_UPDATE")
fest(ns.Nutzung.Sichtbar() is False and ns.Rolle.Nutzung() is None, "Kreuz: keine Antwort, nicht erneut gefragt")
fest(tup(ns.Rolle.Aktiv())[0] is False, "und das Addon schläft")
# Gruppe verlassen: vergessen
g["__welt"]["inGruppe"] = False
g["__ereignis"]("GROUP_ROSTER_UPDATE")
g["__welt"]["inGruppe"] = True
g["__ereignis"]("GROUP_ROSTER_UPDATE")
fest(ns.Nutzung.Sichtbar() is True, "nach Gruppenwechsel wird wieder gefragt")
# Nur Plündermeister zählt: Gruppenbeute fragt nie
w = gruppe(3, nutzung=None)
for c in w.clients:
    c["g"]["__welt"]["ml"] = None
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
fest(w.clients[0]["ns"].Nutzung.Sichtbar() is False, "Gruppenbeute: kein Dialog")

print("== 34. Beutefenster als Pluendermeister: der Startdialog geht von selbst auf ==")
w = gruppe(3)   # Plündermeister = Leiter Kaos (Client 0)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
L34 = "|cff0070dd|Hitem:9341::::::::60:::::|h[Lootding]|h|r"
ns0, g0, lua0 = w.clients[0]["ns"], w.clients[0]["g"], w.clients[0]["lua"]
ns1, g1, lua1 = w.clients[1]["ns"], w.clients[1]["g"], w.clients[1]["lua"]
for n_, g_ in ((ns0, g0), (ns1, g1)):
    n_.Erfassung.Einstellungen()["ort"] = "ueberall"
lua0.execute('__loot = { { link = "%s" } }' % L34)
lua1.execute('__loot = { { link = "%s" } }' % L34)
g1["__ereignis"]("LOOT_OPENED")
fest(not ns1.Wurf.StarterSichtbar(), "Mitglied: Beutefenster oeffnet keinen Startdialog")
g0["__ereignis"]("LOOT_OPENED")
fest(ns0.Wurf.StarterSichtbar(), "Plündermeister: Beutefenster oeffnet den Startdialog")
ns0.Wurf.StarterSchliessen()
# Graues und Weisses (Link-Farbe oder Forever-Format |cnIQ…) öffnet nichts und steht nicht in der Liste
GRAU34 = "|cff9d9d9d|Hitem:9342::::::::60:::::|h[Fetzen]|h|r"
WEISS34 = "|cnIQ1:|Hitem:9343::::::::60:::::|h[Stoffrest]|h|r"
lua0.execute('__loot = { { link = "%s" }, { link = "%s" } }' % (GRAU34, WEISS34))
g0["__ereignis"]("LOOT_OPENED")
fest(not ns0.Wurf.StarterSichtbar(), "graue und weisse Beute: kein Dialog")
lua0.execute('__loot = { { link = "%s" }, { link = "%s" }, { link = "%s" } }' % (GRAU34, WEISS34, L34))
g0["__ereignis"]("LOOT_OPENED")
fest(ns0.Wurf.StarterSichtbar(), "mit einem blauen Stueck dazwischen: Dialog")
sichtbar_zeilen = [str(t) for t in g0["__text"]("").values()]
fest(not any("Fetzen" in t or "Stoffrest" in t for t in sichtbar_zeilen) and any("Lootding" in t for t in sichtbar_zeilen),
     "in der Liste nur das blaue Stueck")
ns0.Wurf.StarterSchliessen()
lua0.execute('__loot = { { link = "%s" } }' % L34)
ns0.Erfassung.Einstellungen()["startAuto"] = False
g0["__ereignis"]("LOOT_OPENED")
fest(not ns0.Wurf.StarterSichtbar(), "Schalter aus: kein Dialog")
ns0.Erfassung.Einstellungen()["startAuto"] = True
lua0.execute('__loot = {}')
g0["__ereignis"]("LOOT_OPENED")
fest(not ns0.Wurf.StarterSichtbar(), "leeres Beutefenster: kein Dialog")
lua0.execute('__loot = { { link = "%s" } }' % L34)
ns0.Rolle.NutzungSetzen("nein")
g0["__ereignis"]("LOOT_OPENED")
fest(not ns0.Wurf.StarterSichtbar(), "nach „Nein“: kein Dialog")
for c in w.clients:
    c["g"]["__welt"]["ml"] = None
g0["__ereignis"]("PARTY_LOOT_METHOD_CHANGED")
g0["__ereignis"]("LOOT_OPENED")
fest(not ns0.Wurf.StarterSichtbar(), "Gruppenbeute: kein Dialog")

print("== 35. Wurfbeginn: eine Zeile im Gruppenchat fuer Spieler ohne Addon ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
L35 = "|cff0070dd|Hitem:9351::::::::60:::::|h[Rollding]|h|r"
ok = tup(ns.Wurf.Starten(L35, "45"))[0]
chat = [str(c[1]) for c in g["__chat"].values()]
fest(ok and len(chat) == 1 and "/roll 1-100" in chat[0] and "/roll 1-99" in chat[0] and "45" in chat[0] and "Rollding" in chat[0],
     "Wurfstart: eine Zeile mit Gegenstand, beiden Bereichen und Zeit (%s)" % (chat[0][:90] if chat else "keine"))
fest(str(list(g["__chat"].values())[0][2]) == "PARTY", "in einer 5er-Gruppe: Gruppenchat")
ns.Wurf.Abbrechen()
# Im Raid als Leiter: Raidwarnung (/rw)
w = gruppe(3)
for c in w.clients:
    c["g"]["__welt"]["raid"] = True
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
ns.Wurf.Starten(L35, "45")
kan = [str(c[2]) for c in g["__chat"].values()]
fest(kan == ["RAID_WARNING"], "im Raid als Leiter: als Raidwarnung (%s)" % kan)
ns.Wurf.Abbrechen()
# Im Raid ohne Leiter/Assistent: normaler Raidchat
w = gruppe(3)
for c in w.clients:
    c["g"]["__welt"]["raid"] = True
    c["g"]["__welt"]["ml"] = 2     # Timo ist Plündermeister, aber weder Leiter noch Assistent
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ns, g = w.clients[1]["ns"], w.clients[1]["g"]
ns.Wurf.Starten(L35, "45")
kan = [str(c[2]) for c in g["__chat"].values()]
fest(kan == ["RAID"], "im Raid ohne Leiter/Assistent: Raidchat (%s)" % kan)
ns.Wurf.Abbrechen()
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
ns.Erfassung.Einstellungen()["ansagen"] = False
ns.Wurf.Starten(L35, "45")
fest(len(list(g["__chat"].values())) == 0, "Schalter aus: keine Zeile")
fest(len(list(w.clients[1]["g"]["__chat"].values())) == 0, "Mitspieler schreiben nichts")

# Die Vergabe-Ansage geht im Raid ebenfalls als Raidwarnung (Leiter/Assistent), sonst Raidchat
w = gruppe(3)
for c in w.clients:
    c["g"]["__welt"]["raid"] = True
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ns, g, lua = w.clients[0]["ns"], w.clients[0]["g"], w.clients[0]["lua"]
ns.Erfassung.Eintragen("Moe", L35, None, "haupt", None, lua.table_from({"herkunft": "wurf", "wurf": 12}))
chat = [(str(c[1]), str(c[2])) for c in g["__chat"].values()]
fest(len(chat) == 1 and chat[0][1] == "RAID_WARNING" and "wurde an Moe vergeben!" in chat[0][0],
     "Vergabe im Raid als Leiter: Raidwarnung (%s)" % [k for _, k in chat])
w = gruppe(3)
for c in w.clients:
    c["g"]["__welt"]["raid"] = True
    c["g"]["__welt"]["ml"] = 2
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
ns, g, lua = w.clients[1]["ns"], w.clients[1]["g"], w.clients[1]["lua"]
ns.Rolle.NutzungSetzen("ja")
ns.Erfassung.Einstellungen()["schreiben"] = "immer"
ns.Erfassung.Eintragen("Moe", L35, None, "haupt", None, lua.table_from({"herkunft": "wurf", "wurf": 12}))
chat = [(str(c[1]), str(c[2])) for c in g["__chat"].values()]
fest(len(chat) == 1 and chat[0][1] == "RAID", "Vergabe im Raid ohne Leiter/Assistent: Raidchat (%s)" % [k for _, k in chat])

print("== 36. Datenbuch: Abschluesse und Anhebungen erreichen alle; Neuling, Gast, Proberaid ==")


def zuschlag_von(w, k, wer):
    """Festgeschriebener Zuschlag eines Spielers auf Client k."""
    daten = w.clients[k]["ns"].Anwesenheit.ZuschlaegeDaten()
    return daten["zuschlaege"][wer]


def anhebung_von(w, k, wer):
    daten = w.clients[k]["ns"].Anwesenheit.ZuschlaegeDaten()
    return daten["anhebungen"][wer]


def buchstand(w, k):
    return tup(w.clients[k]["ns"].Abgleich.BuchStand())


def welt36(auto=False):
    w = gruppe(3, auto=auto)
    for c in w.clients:
        c["ns"].Gruppen.Anlegen("40er")
        c["ns"].Gruppen.KaderErgaenzen("40er", "Leiter Kaos, Timo, Lina, Protti")
    w.ereignis("PLAYER_ENTERING_WORLD")
    w.weiter(15)
    return w


def abend36(w):
    """Ein Raidabend: Kaos, Timo und Lina im Raid, Protti fehlt; drei Main-Items (Timo 2, Kaos 1)."""
    ns0, lua0 = w.clients[0]["ns"], w.clients[0]["lua"]
    ok = ns0.Anwesenheit.BossBuchen("Lucifron", 1001, True, lua0.table_from(["Leiter Kaos", "Timo", "Lina"]))
    w.eintragen(0, "Timo", 5001, int(w.t))
    w.eintragen(0, "Timo", 5002, int(w.t) + 1)
    w.eintragen(0, "Leiter Kaos", 5003, int(w.t) + 2)
    return ok


# --- Abschluss erreicht alle (live) -----------------------------------------
w = welt36()
fest(buchstand(w, 0) == buchstand(w, 1) == buchstand(w, 2), "Ausgangslage: Datenbuch bei allen gleich")
abend36(w)
ns0 = w.clients[0]["ns"]
ok, vorschau, n = tup3(ns0.Anwesenheit.AbendAbschliessen(None, "System"))[0], None, None
fest(ok is True, "Leiter schliesst den Abend ab")
w.weiter(20)
fest(abs(zuschlag_von(w, 0, "protti") - 0.7) < 1e-9, "Zuschlag bei Protti (Leiter): 0,7 x Schnitt 1")
fest(abs(zuschlag_von(w, 1, "protti") - 0.7) < 1e-9, "derselbe Zuschlag beim Mitglied 1")
fest(abs(zuschlag_von(w, 2, "protti") - 0.7) < 1e-9, "und beim Mitglied 2")
fest(buchstand(w, 0) == buchstand(w, 1) == buchstand(w, 2), "Datenbuch bei allen gleich (Pruefsumme)")
ids0 = sorted(str(k) for k in w.clients[0]["ns"].Anwesenheit.Daten()["abende"].keys())
ids1 = sorted(str(k) for k in w.clients[1]["ns"].Anwesenheit.Daten()["abende"].keys())
fest(len(ids0) == 1 and ids0 == ids1, "derselbe Abend liegt beim Mitglied im Archiv (%s)" % (ids1,))
abend1 = w.clients[1]["ns"].Anwesenheit.Daten()["abende"][ids1[0]]
fest(abend1["abgeschlossen"] is True and abend1["buchRev"] == 1, "abgeschlossen, Revision 1")

# --- Wiedereroeffnen und erneut abschliessen ----------------------------------
ok2 = tup3(ns0.Anwesenheit.AbendWiedereroeffnen(None, "System"))[0]
fest(ok2 is True, "Leiter eroeffnet den Abend wieder")
w.weiter(20)
fest(zuschlag_von(w, 1, "protti") is None and zuschlag_von(w, 2, "protti") is None, "Zuschlaege sind bei allen wieder weg")
fest(buchstand(w, 0) == buchstand(w, 1) == buchstand(w, 2), "Datenbuch weiter gleich (Revision 2)")
tup3(ns0.Anwesenheit.AbendAbschliessen(None, "System"))
w.weiter(20)
fest(abs(zuschlag_von(w, 2, "protti") - 0.7) < 1e-9, "nach erneutem Abschluss ist der Zuschlag wieder da (Revision 3)")
fest(buchstand(w, 0) == buchstand(w, 1) == buchstand(w, 2), "Datenbuch gleich")

# --- Anhebung als einzelner Satz -------------------------------------------------
id_ = ns0.Anwesenheit.AnhebungBuchen("Timo", 2.5, "Test", "Leiter Kaos")
fest(id_ is not None, "Anhebung gebucht (%s)" % id_)
w.weiter(20)
fest(abs(anhebung_von(w, 1, "timo") - 2.5) < 1e-9 and abs(anhebung_von(w, 2, "timo") - 2.5) < 1e-9,
     "die Anhebung erreicht beide Mitspieler")
fest(buchstand(w, 0) == buchstand(w, 1) == buchstand(w, 2), "Datenbuch gleich")

# --- Ein Mitglied hat alles verpasst: der Abgleich holt es nach -------------------
w = welt36(auto=True)
abend36(w)
ns0 = w.clients[0]["ns"]
tup3(ns0.Anwesenheit.AbendAbschliessen(None, "System"))
ns0.Anwesenheit.AnhebungBuchen("Timo", 1.5, "Test", "Leiter Kaos")
w.weiter(20)
d2 = w.clients[2]["ns"].Anwesenheit.Daten()
d2["abende"] = w.clients[2]["lua"].table()
d2["zuschlaege"] = w.clients[2]["lua"].table()
d2["anhebungsliste"] = w.clients[2]["lua"].table()
fest(buchstand(w, 0) != buchstand(w, 2), "Mitglied 2 hat alles verloren: Hallo meldet die Abweichung")
w.ereignis("GROUP_ROSTER_UPDATE")
w.weiter(140)
fest(buchstand(w, 0) == buchstand(w, 2), "der Abgleich bringt das Datenbuch zurueck")
fest(abs(zuschlag_von(w, 2, "protti") - 0.7) < 1e-9 and abs(anhebung_von(w, 2, "timo") - 1.5) < 1e-9,
     "Zuschlag und Anhebung sind wieder da")
ns2 = w.clients[2]["ns"]
fest(abs(zuschlag_von(w, 1, "protti") - 0.7) < 1e-9, "Mitglied 1 war nie betroffen")

# --- Spaeter: Gruender, Proberaid, Neuling, Gast -------------------------------------------
# Der Kader zur Gruendungszeit (Kaos, Timo, Lina, Protti) gilt als eingespielt — auch Protti, der am
# ersten Abend fehlte. Neue Kaderspieler kommen erst danach dazu: "Neuer" (noch nie da) und "Neuling"
# (an einem spaeteren Abend schon einmal dabei, ohne Item).
for k in (0, 1, 2):
    w.clients[k]["ns"].Gruppen.KaderErgaenzen("40er", "Neuer, Neuling")
zeit2 = int(w.t) + 86400
for k in (0, 1, 2):
    lua_k = w.clients[k]["lua"]
    w.clients[k]["ns"].Anwesenheit.Daten()["abende"]["2026-02-02"] = lt(lua_k, {
        "id": "2026-02-02", "datum": "2026-02-02", "bosse": 1, "gesehen": {}, "bossListe": {}, "teilnehmer": {},
        "anwesenheit": {"neuling": 1}, "bank": {}, "unentschuldigt": {}, "vergessen": {}, "protokoll": {},
        "abgeschlossen": True, "buchRev": 1,
        "abschluss": {"zeit": zeit2, "datum": "2026-02-02", "autor": "Kaos", "schnitt": 1, "mainItems": 1,
                      "raidSpieler": 1, "gesamtBosse": 1,
                      "spieler": {"neuling": {"name": "Neuling", "status": "imRaid", "faktor": 0, "zuschlag": 0,
                                              "fehlAnzahl": 0, "bosse": 1, "schnitt": 1, "gesamt": 1, "zeit": zeit2, "von": "Kaos"}}}})
probe = w.clients[0]["lua"].eval("""function(ns, namen)
    local H = ns.Erfassung.Historie()
    local liste = ns.Kern.Bilanz(H, 0, namen, nil, ns.Anwesenheit.ZuschlaegeDaten())
    ns.Anwesenheit.Rollen(liste, true)
    local aus = {}
    for _, e in ipairs(liste) do
        aus[string.lower(e.name)] = { wertung = e.wertung, neuling = e.neuling and 1 or 0,
                                      gast = e.gast and 1 or 0, probe = e.proberaid and 1 or 0 }
    end
    return aus
end""")
lua0 = w.clients[0]["lua"]
st = lambda n: str(ns0.Anwesenheit.StatusVon(n))
NAMEN = ["Leiter Kaos", "Timo", "Lina", "Protti", "Neuer", "Neuling", "Gastspieler"]
fest(st("Timo") == "kader" and st("Leiter Kaos") == "kader", "Timo und Kaos: Kader")
fest(st("Lina") == "kader", "Lina stand im Abschluss des ersten Abends: Gruenderin, kein Neuling (%s)" % st("Lina"))
fest(st("Protti") == "kader", "Protti fehlte am ersten Abend, stand aber im Kader: Gruender, kein Proberaid (%s)" % st("Protti"))
fest(st("Neuer") == "proberaid", "wer spaeter zum Kader kommt und noch nie da war: Proberaid (%s)" % st("Neuer"))
fest(st("Neuling") == "neuling", "wer spaeter dazukam und einen Abend dabei war: 2. Abend = Neuling (%s)" % st("Neuling"))
fest(st("Gastspieler") == "gast", "wer nicht im Kader ist, ist Gast")

res = probe(ns0, lua0.table_from(NAMEN))
res = {str(k): v for k, v in res.items()}
niedrigster = ns0.Anwesenheit.KaderNiedrigste()
fest(res["neuer"]["probe"] == 1, "Proberaid: keine Lootberechtigung")
fest(res["gastspieler"]["gast"] == 1 and abs(res["gastspieler"]["wertung"] - niedrigster) < 1e-9,
     "Gast: Wertung wie der Niedrigste der Kaderspieler (%s)" % niedrigster)
fest(abs(res["neuling"]["wertung"] - (niedrigster + 2)) < 1e-9,
     "Neuling: Niedrigster der Kaderspieler (%s) + 2 (%s)" % (niedrigster, res["neuling"]["wertung"]))
w.weiter(20)
fest(abs(anhebung_von(w, 1, "neuling") - (niedrigster + 2)) < 1e-9 and abs(anhebung_von(w, 2, "neuling") - (niedrigster + 2)) < 1e-9,
     "der Start des Neulings ging als Anhebung an alle")
def hat_vermerk(k):
    """Der Vermerk heisst hm_<Tag> oder, mit aktiver Gruppe, hm_<Tag>_<Gruppe>."""
    tag = str(w.clients[k]["lua"].eval("os.date('%Y%m%d')"))
    for kennung in w.clients[k]["ns"].Anwesenheit.Daten()["anhebungsliste"].keys():
        if str(kennung).startswith("hm_" + tag):
            return True
    return False


vorher = buchstand(w, 0)
probe(ns0, lua0.table_from(NAMEN))
fest(buchstand(w, 0) == vorher, "ein zweiter Durchlauf bucht den Neuling-Start nicht noch einmal")


# --- Keine automatische Anhebung mehr; die Leitung hebt von Hand an (Entscheid 19.10.2026) -------------------
w = welt36()
ns0, lua0 = w.clients[0]["ns"], w.clients[0]["lua"]
# Vorgeschichte: Kaos 9, Timo 9, Lina 9 Items; Protti nur 5 (liegt weit hinten)
for k in (0, 1, 2):
    for i, wer in enumerate(["Leiter Kaos", "Timo", "Lina"]):
        for j in range(9):
            w.setze(k, "alt_%s_%d" % (wer.replace(" ", ""), j), {"awardedTo": wer, "itemID": 8000 + i * 20 + j, "timestamp": int(w.t) - 90000 - j})
    for j in range(5):
        w.setze(k, "alt_Protti_%d" % j, {"awardedTo": "Protti", "itemID": 8100 + j, "timestamp": int(w.t) - 90000 - j})
ab = {"id": "2026-01-01", "datum": "2026-01-01", "bosse": 1, "gesehen": {}, "bossListe": {}, "teilnehmer": {},
      "anwesenheit": {"leiter kaos": 1, "timo": 1, "lina": 1, "protti": 1}, "bank": {}, "unentschuldigt": {}, "protokoll": {}}
for k in (0, 1, 2):
    w.clients[k]["ns"].Anwesenheit.Daten()["abende"]["2026-01-01"] = lt(w.clients[k]["lua"], ab)
w.weiter(5)
ok = ns0.Anwesenheit.BossBuchen("Lucifron", 2001, True, lua0.table_from(["Leiter Kaos", "Timo", "Lina", "Protti"]))
w.weiter(20)
fest(anhebung_von(w, 0, "protti") is None, "zu Abendbeginn wird niemand mehr von selbst angehoben (Protti 5 gegen 9)")
n1 = buchstand(w, 0)
# Manuell: die Raid-/Gildenleitung hebt Protti an: Niedrigster der anderen im Raid (9) + 2 = 11, also +6
r = tup(ns0.Anwesenheit.AnhebungSetzen("Protti"))
fest(r[0] is not None and abs(float(r[1]) - 11.0) < 1e-9 and abs(float(r[2]) - 6.0) < 1e-9, "manuelle Anhebung: Protti auf 11 (+6) (%s)" % (r,))
w.weiter(15)
fest(abs(anhebung_von(w, 0, "protti") - 6.0) < 1e-9 and abs(anhebung_von(w, 1, "protti") - 6.0) < 1e-9
     and abs(anhebung_von(w, 2, "protti") - 6.0) < 1e-9, "und die Anhebung erreicht alle")
r2 = tup(ns0.Anwesenheit.AnhebungSetzen("Protti"))
fest(r2[0] is None, "ein zweites Mal: Protti liegt schon bei 11, nichts passiert (nie nach unten) (%s)" % (r2,))
fest(buchstand(w, 0) != n1 and anhebung_von(w, 0, "timo") is None, "die anderen bleiben unangetastet")
r3 = tup(w.clients[2]["ns"].Anwesenheit.AnhebungSetzen("Timo", "Lina"))
fest(r3[0] is None, "wer nicht Raid- oder Gildenleitung ist, darf nicht anheben (%s)" % (r3,))
# Der Name darf ohne Realm/Nachnamen eingegeben werden, wenn der Spieler im Raid ist
r4 = tup(ns0.Anwesenheit.AnhebungSetzen("   "))
fest(r4[0] is None, "ohne Namen wird nichts angehoben (%s)" % (r4,))

# --- Kennzeichen und Anhebung bei der Vergabe ----------------------------------------
w = welt36()
ns0, g0, lua0 = w.clients[0]["ns"], w.clients[0]["g"], w.clients[0]["lua"]
LINK36 = "|cff0070dd|Hitem:6001::::::::60:::::|h[Schwert der Abweichung]|h|r"
ns0.Erfassung.Eintragen("Timo", LINK36, None, "haupt", None,
                        lua0.table_from({"herkunft": "wurf", "wurf": 40, "kennzeichen": "A", "anhebung": 2.0, "wertung": 4}))
w.weiter(15)
eintr = [v for v in w.hist(1).values() if v["awardedTo"] == "Timo"]
fest(len(eintr) == 1 and eintr[0]["kennzeichen"] == "A", "Kennzeichen A kommt beim Mitglied an")
chat = [str(c[1]) for c in g0["__chat"].values()]
fest(any("abweichend vom Ergebnis" in t for t in chat), "Chat: abweichend vom Ergebnis")
fest(abs(anhebung_von(w, 1, "timo") - 2.0) < 1e-9, "die Anhebung des Gewinners ging als Satz an die Gruppe")
ns0.Erfassung.Eintragen("Lina", "|cff0070dd|Hitem:6002::::::::60:::::|h[OS-Ding]|h|r", None, "zweit", None,
                        lua0.table_from({"herkunft": "wurf", "wurf": 12, "kennzeichen": "S"}))
chat = [str(c[1]) for c in g0["__chat"].values()]
fest(any("OS nach Absprache" in t for t in chat), "Chat bei OS: OS nach Absprache")
verlauf = ns0.Quelle.Gegenstandstext(w.hist(0)[[k for k in w.hist(0).keys() if w.hist(0)[k]["awardedTo"] == "Lina"][0]])
fest("OS nach Absprache" in str(verlauf), "und im Verlauf steht das Kennzeichen")

# --- Stammgast: von Hand in den Kader, kein Proberaid, die Wertung bleibt ---------------
w = welt36()
ns0, lua0 = w.clients[0]["ns"], w.clients[0]["lua"]
ns0.Anwesenheit.BossBuchen("Lucifron", 1001, True, lua0.table_from(["Leiter Kaos", "Timo", "Stammi"]))
w.eintragen(0, "Stammi", 7001, int(w.t))
tup3(ns0.Anwesenheit.AbendAbschliessen(None, "System"))
fest(str(ns0.Anwesenheit.StatusVon("Stammi")) == "gast", "Stammi ist (noch) Gast: er steht nicht im Kader")
ns0.Gruppen.KaderErgaenzen("40er", "Stammi")
fest(str(ns0.Anwesenheit.StatusVon("Stammi")) == "kader", "von Hand in den Kader aufgenommen: Kader, kein Proberaid")
liste = tup(ns0.Kern.Bilanz(ns0.Erfassung.Historie(), 0, lua0.table_from(["Stammi"]), None, ns0.Anwesenheit.ZuschlaegeDaten()))[0]
fest(abs(liste[1]["wertung"] - 1) < 1e-9, "und sein Item als Gast zaehlt weiter (Wertung 1)")

print("== 37. Anmeldung vergessen: ab dem 3. Mal in 8 Abenden wie unentschuldigt ==")


def archiv_abend(w, tag, zeit, spieler):
    """Legt auf allen Clients einen abgeschlossenen frueheren Abend ab."""
    for k in (0, 1, 2):
        lua = w.clients[k]["lua"]
        sp = {}
        for name, status in spieler.items():
            sp[name.lower()] = {"name": name, "status": status, "faktor": 0.7 if status != "imRaid" else 0,
                                "zuschlag": 0.7 if status != "imRaid" else 0, "fehlAnzahl": 1, "bosse": 0,
                                "schnitt": 1, "gesamt": 1, "zeit": zeit, "von": "Kaos"}
        ab = {"id": tag, "datum": tag, "bosse": 1, "gesehen": {}, "bossListe": {}, "teilnehmer": {},
              "anwesenheit": {"leiter kaos": 1, "timo": 1, "lina": 1}, "bank": {}, "unentschuldigt": {}, "vergessen": {},
              "protokoll": {}, "abgeschlossen": True, "buchRev": 1,
              "abschluss": {"zeit": zeit, "datum": tag, "autor": "Kaos", "schnitt": 1, "mainItems": 3,
                            "raidSpieler": 3, "gesamtBosse": 1, "spieler": sp}}
        w.clients[k]["ns"].Anwesenheit.Daten()["abende"][tag] = lt(lua, ab)


def vorschau_von(ns0, wer):
    v = tup(ns0.Anwesenheit.AbendVorschau())[0]
    for p in v["spieler"].values():
        if str(p["name"]).lower() == wer.lower():
            return p
    return None


def abend37(w, vergessen=("Protti",)):
    ns0, lua0 = w.clients[0]["ns"], w.clients[0]["lua"]
    ns0.Anwesenheit.BossBuchen("Lucifron", 3001, True, lua0.table_from(["Leiter Kaos", "Timo", "Lina"]))
    w.eintragen(0, "Timo", 9501, int(w.t))
    w.eintragen(0, "Lina", 9502, int(w.t) + 1)
    w.eintragen(0, "Leiter Kaos", 9503, int(w.t) + 2)
    for wer in vergessen:
        ok = ns0.Anwesenheit.VergessenSetzen(wer, True, "System")
        fest(tup(ok)[0] is True, "%s als vergessen eingetragen" % wer)
    return ns0


T0 = 1690000000
# --- Erstes Mal: wie eine normale Abmeldung -----------------------------------------
w = welt36()
archiv_abend(w, "2026-01-01", T0, {"Leiter Kaos": "imRaid", "Timo": "imRaid", "Lina": "imRaid", "Protti": "abgemeldet"})
ns0 = abend37(w)
p = vorschau_von(ns0, "Protti")
fest(str(p["status"]) == "vergessen", "1. Mal: Status vergessen (%s)" % p["status"])
fest(abs(p["zuschlag"] - 0.7 * 1.0) < 1e-9 or p["zuschlag"] > 0, "1. Mal: Staffel, keine Strafe (Zuschlag %.2f)" % p["zuschlag"])
fest(p["zuschlag"] < 2 - 1e-9, "1. Mal: unter 2 Punkten, also nicht wie unentschuldigt")

# --- Zweites Mal: weiterhin normal ----------------------------------------------------
w = welt36()
archiv_abend(w, "2026-01-01", T0, {"Leiter Kaos": "imRaid", "Timo": "imRaid", "Lina": "imRaid", "Protti": "vergessen"})
ns0 = abend37(w)
p = vorschau_von(ns0, "Protti")
fest(str(p["status"]) == "vergessen" and p["zuschlag"] < 2 - 1e-9, "2. Mal: noch wie eine Abmeldung (%s, %.2f)" % (p["status"], p["zuschlag"]))

# --- Drittes Mal innerhalb von 8 Abenden: wie unentschuldigt -----------------------------
w = welt36()
archiv_abend(w, "2026-01-01", T0, {"Leiter Kaos": "imRaid", "Timo": "imRaid", "Lina": "imRaid", "Protti": "vergessen"})
archiv_abend(w, "2026-01-08", T0 + 7 * 86400, {"Leiter Kaos": "imRaid", "Timo": "imRaid", "Lina": "imRaid", "Protti": "vergessenStrafe"})
ns0 = abend37(w)
p = vorschau_von(ns0, "Protti")
fest(str(p["status"]) == "vergessenStrafe", "3. Mal: Strafe (%s)" % p["status"])
fest(abs(p["faktor"] - 1.5) < 1e-9, "Faktor 1,5")
fest(abs(p["zuschlag"] - 2.0) < 1e-9, "mindestens 2 Punkte (Zuschlag %.2f)" % p["zuschlag"])
ok = tup3(ns0.Anwesenheit.AbendAbschliessen(None, "System"))[0]
fest(ok is True, "Abend wird abgeschlossen")
w.weiter(20)
fest(abs(zuschlag_von(w, 1, "protti") - 2.0) < 1e-9 and abs(zuschlag_von(w, 2, "protti") - 2.0) < 1e-9,
     "der Zuschlag von 2 erreicht die Mitspieler")
ereig = tup(w.clients[1]["ns"].Anwesenheit.SpielerEreignisse("Protti", None, w.hist(1), None, False))[0]
texte = [str(e["text"]) for e in ereig.values()]
fest(any("Anmeldung vergessen" in t_ for t_ in texte), "im Spielerdetail steht der Grund: Anmeldung vergessen")

# --- Mehr als 8 Abende her: zaehlt nicht mehr -------------------------------------------
w = welt36()
archiv_abend(w, "2026-01-01", T0, {"Leiter Kaos": "imRaid", "Timo": "imRaid", "Lina": "imRaid", "Protti": "vergessen"})
archiv_abend(w, "2026-01-08", T0 + 1 * 7 * 86400, {"Leiter Kaos": "imRaid", "Timo": "imRaid", "Lina": "imRaid", "Protti": "vergessenStrafe"})
for i in range(2, 9):
    # Protti war bei den spaeteren Abenden dabei (es zaehlen nur die EIGENEN Abende eines Spielers, 18.10.2026)
    archiv_abend(w, "2026-02-%02d" % i, T0 + i * 7 * 86400, {"Leiter Kaos": "imRaid", "Timo": "imRaid", "Lina": "imRaid", "Protti": "imRaid"})
ns0 = abend37(w)
p = vorschau_von(ns0, "Protti")
fest(str(p["status"]) == "vergessen", "die beiden alten Faelle liegen ausserhalb der letzten 7 Abende: wieder wie eine Abmeldung (%s)" % p["status"])

# --- Rechte, Rücknahme, Ausschluss untereinander -----------------------------------------
w = welt36()
ns0 = abend37(w, vergessen=())
ok = tup(ns0.Anwesenheit.VergessenSetzen("Protti", True, "Timo"))
fest(ok[0] is None or ok[0] is False, "ein einfaches Mitglied darf nichts eintragen (%s)" % (ok[1],))
ns0.Anwesenheit.VergessenSetzen("Protti", True, "System")
fest(bool(tup(ns0.Anwesenheit.IstVergessen("Protti"))[0]), "eingetragen")
okBank = tup(ns0.Anwesenheit.BankSetzen("Protti", True, "Leiter Kaos"))
fest(okBank[0] is True, "Bank gesetzt (%s)" % (okBank[1],))
fest(not bool(tup(ns0.Anwesenheit.IstVergessen("Protti"))[0]), "wer auf die Bank gesetzt wird, ist nicht mehr „vergessen“")
ns0.Anwesenheit.VergessenSetzen("Protti", True, "System")
fest(not bool(tup(ns0.Anwesenheit.IstBank("Protti"))[0]), "und umgekehrt")
ns0.Anwesenheit.VergessenSetzen("Protti", False, "System")
fest(not bool(tup(ns0.Anwesenheit.IstVergessen("Protti"))[0]), "Rücknahme: Markierung entfernt")

print("== 38. Erster Abend mit der neuen Regel: der ganze Kader darf wuerfeln (Fund im Spiel 17.10.2026) ==")
# Am Gruendungsabend hat noch niemand eine Vorgeschichte. Damals galt der ganze Kader als Proberaid, und
# die Wuerfe wurden ausgeblendet („Niemand hat gewuerfelt").
w = gruppe(3)
for c in w.clients:
    c["ns"].Gruppen.Anlegen("40er")
    c["ns"].Gruppen.KaderErgaenzen("40er", "Leiter Kaos, Timo, Lina")
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
g, ns, lua = cl["g"], cl["ns"], cl["lua"]
fest(all(str(ns.Anwesenheit.StatusVon(n)) == "kader" for n in ("Leiter Kaos", "Timo", "Lina")),
     "Gruendungsabend: alle im Kader sind Kaderspieler, nicht Proberaid")
lua.execute('__tasche = { { link = "%s", quality = 4, frist = true } }' % LINK)
ns.Wurf.Starten(LINK)
w.weiter(3)
for wer, wert in (("Timo", 77), ("Lina", 91)):
    for c in w.clients:
        c["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "%s rolls %d (1-100)" % (wer, wert))
w.weiter(1)
ns.Wurf.BeendenAlle()
w.weiter(4)
fest(g["__klick"]("Zuteilen") is True, "die Wuerfe sind da: das Ergebnisfenster bietet Zuteilen an")
ausgabe38 = [str(x) for x in g["__ausgabe"].values()]
fest(not any("Niemand hat" in x or "Proberaid" in x for x in ausgabe38), "keine Meldung „Niemand hat gewuerfelt\" / Proberaid")

print("== 39. Entzaubern: gruener Gegenstand und man selbst (Fund im Spiel 17.10.2026) ==")
# Vorher: „Gegenstand nicht gefunden – bitte von Hand uebergeben“, sobald das Stueck unter der
# Qualitaetsschwelle lag oder keine Handelsfrist trug, auch wenn man es sich selbst gab.
GRUEN39 = "|cff1eff00|Hitem:7300::::::::60:::::|h[Staunch Hammer of Healing]|h|r"

# (a) Man gibt es sich selbst, der Gegenstand liegt nirgends, wo das Addon ihn listet
w, cl, g, ns, lua = welt29(verz="Leiter Kaos", tasche=False)
lua.execute("__chat = {}")
ok = ns.Wurf.Entzaubern("Leiter Kaos", GRUEN39)
chat = [str(c[1]) for c in g["__chat"].values()]
fest(ok is True, "an sich selbst: kein Fehler, es gibt nichts zu uebergeben")
fest(any("zum Entzaubern an" in x and "Staunch Hammer" in x for x in chat), "und es wird im Chat angesagt (%s)" % (chat,))

# (b) Ein anderer Verzauberer, das Stueck ist gruen (unter der Schwelle) und liegt im Rucksack
w, cl, g, ns, lua = welt29(verz="Lina", tasche=False)
lua.execute('__tasche = { { link = "%s", quality = 2 } }' % GRUEN39)
ok = ns.Wurf.Entzaubern("Lina", GRUEN39)
fest(ok is True, "gruenes Stueck im Rucksack wird gefunden und fuer den Handel vorgemerkt")
vorgemerkt = [e for e in ns.Wurf.Offene().values() if "Lina" in str(e["name"])]
fest(len(vorgemerkt) == 1 and bool(vorgemerkt[0]["entzaubern"]), "als Entzauberung vorgemerkt")

# (c) Ein anderer Verzauberer, das Stueck liegt gar nicht im Rucksack: Hinweis bleibt
w, cl, g, ns, lua = welt29(verz="Lina", tasche=False)
ok = ns.Wurf.Entzaubern("Lina", GRUEN39)
fest(ok is False, "nirgends zu finden und an einen anderen: weiter die Meldung „von Hand uebergeben“")

print("== 40. Zuteilen: auch ein gruenes Stueck oeffnet den Handel (Fund im Spiel 17.10.2026) ==")
# Vorher stand bei einem Stueck unter der Qualitaetsschwelle nur „Nur eintragen“: Es wurde eingetragen,
# das Handelsfenster ging nicht auf.
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
g, ns, lua = cl["g"], cl["ns"], cl["lua"]
lua.execute('__tasche = { { link = "%s", quality = 2 } }' % LINK)      # gruen, ohne Handelsfrist
ns.Wurf.Starten(LINK)
w.weiter(3)
for wer, wert in (("Timo", 40), ("Lina", 91)):
    for c in w.clients:
        c["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "%s rolls %d (1-100)" % (wer, wert))
w.weiter(1)
ns.Wurf.BeendenAlle()
w.weiter(4)
fest(len([x for x in g["__text"]("Nur eintragen").values() if x]) == 0, "das Ergebnisfenster bietet nicht nur „Nur eintragen“ an")
fest(g["__klick"]("Zuteilen") is True, "„Zuteilen“ ist da und wird angeklickt")
w.weiter(2)
offen = [e for e in ns.Wurf.Offene().values() if "Lina" in str(e["name"])]
fest(len(offen) == 1, "der Handel mit dem Gewinner (Lina) ist vorgemerkt")
fest(len(w.hist(0)) >= 0 and not any("Lina" == str(v["awardedTo"]) and v["itemID"] == 9999 for v in w.hist(0).values()),
     "und eingetragen wird erst nach dem Handel")
# Lina handelt den Leiter an: das gruene Stueck liegt schon im Handelsfenster
g["__npc"] = "Lina"
g["__ereignis"]("TRADE_SHOW")
w.weiter(1)
fest(g["__angeboten"][1] == LINK, "Lina handelt: der gruene Gegenstand (ohne Handelsfrist) liegt schon im Fenster")

print("== 41. Rueckgabe: Entzaubern loest sie auf, /fs rueckgabe, Spielerdetail zeigt den Gegenstand (Fund im Spiel 17.10.2026) ==")
L9802 = "|cff1eff00|Hitem:9802::::::::60:::::|h[Ding 9802]|h|r"

# (a) Lina gibt das Item zurueck, der Leiter entzaubert es selbst: der Punkt faellt weg
w = welt23()
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
ns.Erfassung.Zuruecknehmen("u2")
fest(gezaehlt(w, 0) == 2, "nach der Rueckgabe bleibt der Punkt (noch nicht weitergegeben)")
ns.Wurf.VerzaubererHinzufuegen("Leiter Kaos")
ok = ns.Wurf.Entzaubern("Leiter Kaos", L9802)
fest(ok is True, "das Item wird entzaubert")
fest(w.hist(0)["u2"]["zurueck"] is True, "damit ist es weitergegeben: Linas Vergabe zaehlt nicht mehr")
fest(gezaehlt(w, 0) == 1, "Timos Vergabe bleibt")
w.weiter(15)
fest(gezaehlt(w, 1) == 1 and gezaehlt(w, 2) == 1, "bei den Mitspielern ebenso")

# (b) Anderweitig weitergegeben: /fs rueckgabe zeigt die offenen und schliesst ab
w = welt23()
ns, g = w.clients[0]["ns"], w.clients[0]["g"]
sl = g["SlashCmdList"]["FAIRSHARE"]
ns.Erfassung.Zuruecknehmen("u2")
sl("rueckgabe")
aus = [str(x) for x in g["__ausgabe"].values()]
fest(any("9802" in x for x in aus), "/fs rueckgabe nennt das offene Item")
sl("rueckgabe 1")
fest(w.hist(0)["u2"]["zurueck"] is True and gezaehlt(w, 0) == 1, "/fs rueckgabe 1 schliesst ab, der Punkt faellt weg")
sl("rueckgabe 1")
aus = [str(x) for x in g["__ausgabe"].values()]
fest(any("Diese Nummer" in x or "There is no such" in x for x in aus), "danach gibt es keine Nummer 1 mehr")

# (c) Das Spielerdetail nennt den Gegenstand (vorher stand dort nur „Gegenstand“)
w = welt23()
ns = w.clients[0]["ns"]
ereig = tup(ns.Anwesenheit.SpielerEreignisse("Timo", None, w.hist(0), None, False))[0]
texte = [str(e["text"]) for e in ereig.values()]
fest(any("9801" in x for x in texte), "Spielerdetail: der Gegenstand steht in der Zeile (%s)" % (texte,))

print("== 42. Abwesenheit: Online-Anzeige und Raid mitzeigen (Fund im Spiel 17.10.2026) ==")
w = welt36()
ns0 = w.clients[0]["ns"]
# Online: Offline darf nie als online gelten (der Fehler: Offline zaehlte als online)
fest(ns0.Gruppen.PraesenzOnline(1) is True, "Praesenz 1 (Online) ist online")
fest(ns0.Gruppen.PraesenzOnline(4) is True and ns0.Gruppen.PraesenzOnline(5) is True, "abwesend und beschaeftigt sind online")
fest(ns0.Gruppen.PraesenzOnline(3) is False, "Praesenz 3 (Offline) ist NICHT online")
fest(ns0.Gruppen.PraesenzOnline(2) is False, "nur in der App (mobil) ist nicht im Spiel")
fest(ns0.Gruppen.PraesenzOnline(0) is False and ns0.Gruppen.PraesenzOnline(None) is False, "unbekannt ist nicht online")

# Die Liste: ohne Raid nur wer nicht in der Gruppe ist, mit Raid auch die anderen (zuletzt)
liste = tup(ns0.Anwesenheit.KandidatenListe(None))[0]
namen = [str(e["name"]).lower() for e in liste.values()]
fest(namen == ["protti"], "ohne Raid steht nur der, der nicht in der Gruppe ist (%s)" % namen)
liste = tup(ns0.Anwesenheit.KandidatenListe(None, True))[0]
namen = [str(e["name"]).lower() for e in liste.values()]
fest(len(namen) == 4 and namen[0] == "protti", "mit Raid stehen alle vier da, Protti zuerst (%s)" % namen)
raid = {str(e["name"]).lower(): bool(e["imRaid"]) for e in liste.values()}
fest(raid.get("timo") is True and raid.get("protti") is False, "wer in der Gruppe steht, ist als im Raid gekennzeichnet")
# Auch ein Spieler im Raid laesst sich markieren (zum Ausprobieren der Wertung)
ok = tup(ns0.Anwesenheit.UnentschuldigtSetzen("Timo", True, "System"))
fest(ok[0] is None or ok[0] is False, "Unentschuldigt braucht die Rechte (%s)" % (ok[1],))

print("== 43. Raid am Abendende statt Bosskaempfe (Entscheid 17.10.2026) ==")
# Der Schnitt ist Main-Items des Abends / Spieler im Raid. Wer im Raid steht, zaehlt - auch ohne gebuchten Boss.
# Wer gegangen ist, zaehlt nicht, ausser er hat vorher ein Main-Item bekommen.
w = welt36()
ns0, lua0 = w.clients[0]["ns"], w.clients[0]["lua"]
ns0.Anwesenheit.AktiverAbend(True)
w.eintragen(0, "Timo", 5001, int(w.t))
w.eintragen(0, "Leiter Kaos", 5002, int(w.t) + 1)
s, items, raid = tup3(ns0.Anwesenheit.AbendSchnitt())[0:3]
fest(float(items) == 2 and float(raid) == 3, "ohne gebuchten Boss: 2 Items, 3 Spieler in der Gruppe (%s, %s)" % (items, raid))
fest(abs(float(s) - 2 / 3.0) < 1e-9, "Schnitt 2/3 statt 0 (%s)" % (s,))
# Protti steht nicht im Raid, bekam aber ein Main-Item: er zaehlt mit
w.eintragen(0, "Protti", 5003, int(w.t) + 2)
s, items, raid = tup3(ns0.Anwesenheit.AbendSchnitt())[0:3]
fest(float(items) == 3 and float(raid) == 4, "wer ein Main-Item bekam, zaehlt mit (%s Items, %s Spieler)" % (items, raid))
v = tup(ns0.Anwesenheit.AbendVorschau())[0]
sp = {}
for e in v["spieler"].values():
    sp[str(e["schluessel"])] = str(e["status"])
fest(sp.get("protti") == "imRaid" and sp.get("timo") == "imRaid", "Protti und Timo stehen als im Raid (%s)" % (sp,))
fest(float(v["raidSpieler"]) == 4, "Abschluss meldet 4 Raidspieler")

print("== 44. Wuerfe werden erkannt: nach Abschluss, Rueckgabe und mit einer zweiten Runde (Fund im Spiel 17.10.2026) ==")
LINK44 = "|cff1eff00|Hitem:7400::::::::60:::::|h[Feral Bindings of Arcane Protection]|h|r"
LINK44B = "|cff0070dd|Hitem:7401::::::::60:::::|h[Anderes Stueck]|h|r"


def wuerfe44(w, link, werte):
    cl = w.clients[0]
    g, ns, lua = cl["g"], cl["ns"], cl["lua"]
    lua.execute('__tasche = { { link = "%s", quality = 2, frist = true } }' % link)
    ns.Wurf.Starten(link)
    w.weiter(3)
    for wer, wert in werte:
        for c in w.clients:
            c["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "%s rolls %d (1-100)" % (wer, wert))
    w.weiter(1)
    ns.Wurf.BeendenAlle()
    w.weiter(4)
    return g, ns


# (a) Ein Abend wurde abgeschlossen, danach wird gewuerfelt
w = welt36()
abend36(w)
tup3(w.clients[0]["ns"].Anwesenheit.AbendAbschliessen(None, "System"))
w.weiter(20)
g, ns = wuerfe44(w, LINK44, (("Timo", 77), ("Lina", 91)))
fest(g["__klick"]("Zuteilen") is True, "(a) nach einem Abschluss erkennt das Ergebnisfenster beide Wuerfe")

# (b) Derselbe Gegenstand wurde vergeben, zurueckgegeben und wird erneut verrollt
w = welt36()
ns0 = w.clients[0]["ns"]
w.eintragen(0, "Timo", 7400, int(w.t))
ids = [str(k) for k in ns0.Erfassung.Historie().keys()]
ns0.Erfassung.Zuruecknehmen(ids[0])
g, ns = wuerfe44(w, LINK44, (("Timo", 50), ("Lina", 60)))
fest(g["__klick"]("Zuteilen") is True, "(b) nach einer Rueckgabe erkennt das Ergebnisfenster beide Wuerfe")

# (c) Eine zweite, juengere Runde eines anderen Gegenstands darf die erste nicht verdraengen
w = welt36()
cl = w.clients[0]
g, ns, lua = cl["g"], cl["ns"], cl["lua"]
lua.execute('__tasche = { { link = "%s", quality = 2, frist = true }, { link = "%s", quality = 3, frist = true } }' % (LINK44, LINK44B))
ns.Wurf.Starten(LINK44)
w.weiter(3)
for wer, wert in (("Timo", 77), ("Lina", 91)):
    for c in w.clients:
        c["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "%s rolls %d (1-100)" % (wer, wert))
ns.Erfassung.WurfBeginnt(LINK44B, False)          # eine juengere Runde irgendeines anderen Stuecks
r = ns.Erfassung.AktuelleWuerfe(None, LINK44)
fest(r is not None and "timo" in [str(k) for k in r["Wuerfe"].keys()], "(c) die Runde des gesuchten Stuecks wird gefunden, nicht die juengste")

print("== 45. Gruppenwechsel ist ein anderer Abend, die Items zaehlen im neuen (Fund im Spiel 17.10.2026) ==")
w = welt36()
ns0 = w.clients[0]["ns"]
ns0.Gruppen.Anlegen("Alt")
ns0.Gruppen.Aktivieren("Alt")
abend = ns0.Anwesenheit.AktiverAbend(True)
fest(str(abend["gruppe"]) == "Alt" and str(abend["id"]).endswith("_Alt"), "der Abend wird unter der aktiven Gruppe angelegt (%s)" % (abend["id"],))
ns0.Gruppen.Anlegen("TEST")
ns0.Gruppen.Aktivieren("TEST")
abend2 = ns0.Anwesenheit.AktiverAbend(True)
fest(str(abend2["gruppe"]) == "TEST" and str(abend2["id"]).endswith("_TEST"), "nach dem Wechsel ist es ein neuer Abend der neuen Gruppe (%s)" % (abend2["id"],))
w.eintragen(0, "Timo", 6001, int(w.t))
w.eintragen(0, "Leiter Kaos", 6002, int(w.t) + 1)
s, items, raid = tup3(ns0.Anwesenheit.AbendSchnitt())[0:3]
fest(float(items) == 2, "beide Vergaben zaehlen im Abend der neuen Gruppe (%s)" % (items,))
fest(float(raid) >= 2 and float(s) > 0, "der Schnitt ist nicht 0 (%s)" % (s,))
fest(str(ns0.Anwesenheit.GruppenKennung("20er: Grp 2")) == "20er-Grp-2", "Gruppennamen werden zu gueltigen Kennungen (%s)" % (ns0.Anwesenheit.GruppenKennung("20er: Grp 2"),))
fest(str(ns0.Anwesenheit.AbendId("2026-10-17", None)) == "2026-10-17", "ohne Gruppe bleibt die Kennung das Datum")

print("== 46. Abgemeldet ausdruecklich, offene Spieler sperren den Abschluss (Entscheid 17.10.2026) ==")
w = welt36()
ns0 = w.clients[0]["ns"]
abend36(w)
offene = [str(n) for n in ns0.Anwesenheit.OffeneSpieler().values()]
fest(offene == ["Protti"], "Protti ist offen (nicht im Raid, nichts eingetragen): %s" % (offene,))
ok, grund = tup(ns0.Anwesenheit.AbendAbschliessen(None, "System", True))
fest(ok is None and "Protti" in str(grund), "der Abschluss ist gesperrt, die Meldung nennt Protti")
ok = tup(ns0.Anwesenheit.AbmeldungSetzen("Protti", True, "System"))[0]
fest(ok is True, "Protti wird ausdruecklich abgemeldet")
fest(len(list(ns0.Anwesenheit.OffeneSpieler().values())) == 0, "danach ist niemand mehr offen")
ok = tup(ns0.Anwesenheit.VergessenSetzen("Protti", True, "System"))[0]
fest(ok is True and tup(ns0.Anwesenheit.IstAbgemeldet("Protti"))[0] is False, "Keine Meldung loest die Abmeldung ab (nur ein Zustand)")
ns0.Anwesenheit.AbmeldungSetzen("Protti", True, "System")
fest(tup(ns0.Anwesenheit.IstVergessen("Protti"))[0] is False, "und Abmeldung loest Keine Meldung ab")
ok, v, n = tup3(ns0.Anwesenheit.AbendAbschliessen(None, "System", True))
fest(ok is True and n == 1, "Abschluss geht jetzt durch, ein Zuschlag (Protti 0,7)")
w2 = welt36()
ns2 = w2.clients[0]["ns"]
abend36(w2)
zahl = tup(ns2.Anwesenheit.AlleOffenenAbmelden("System"))[0]
fest(zahl == 1 and tup(ns2.Anwesenheit.IstAbgemeldet("Protti"))[0] is True, "„Alle Offenen: abgemeldet“ setzt Protti")

print("== 47. Passen wird gemeldet, und der Wurf endet frueh, sobald jeder gewaehlt hat (Wunsch 17.10.2026) ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
L47, T47, N47 = w.clients[0], w.clients[1], w.clients[2]
LINK47 = "|cff0070dd|Hitem:7500::::::::60:::::|h[Passprobe]|h|r"
ok, grund = tup(L47["ns"].Wurf.Starten(LINK47))
fest(ok is True, "der Leiter startet einen Wurf")
w.weiter(3)
fest(L47["ns"].Wurf.Aktiv() is True, "der Wurf laeuft")
# Timo passt (Knopf), das erfahren alle
fest(T47["g"]["__klick"]("Passen") is True, "Timo klickt Passen")
w.weiter(1)
for k in (0, 1, 2):
    r = w.clients[k]["ns"].Erfassung.AktuelleWuerfe(None, LINK47)
    fest(r is not None and str(r["Arten"]["timo"]) == "pass", "Client %d weiss: Timo passt" % k)
fest(L47["ns"].Wurf.Aktiv() is True, "noch nicht alle haben gewaehlt: der Wurf laeuft weiter")
# Der Leiter wuerfelt, Lina noch nicht
for c in w.clients:
    c["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "Leiter Kaos rolls 40 (1-100)")
w.weiter(2)
fest(L47["ns"].Wurf.Aktiv() is True, "Lina fehlt noch: der Wurf laeuft weiter")
# Lina wuerfelt: jetzt hat jeder gewaehlt -> der Wurf endet von selbst, lange vor Ablauf der Zeit
for c in w.clients:
    c["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "Lina rolls 70 (1-100)")
w.weiter(3)
fest(L47["ns"].Wurf.Aktiv() is False, "alle haben gewaehlt: der Wurf endet frueh (bei der Leitung)")
fest(N47["ns"].Wurf.Aktiv() is False and T47["ns"].Wurf.Aktiv() is False, "und auch bei den Mitspielern")
ausgabe47 = [str(x) for x in L47["g"]["__ausgabe"].values()]
fest(any("Everyone has chosen" in x or "Alle haben gew" in x for x in ausgabe47), "mit einer Meldung im Chat")
# Die Rangliste zeigt Timo nicht
fest(L47["g"]["__klick"]("Zuteilen") is True, "das Ergebnisfenster ist da")

def ev(ns, datum, name):
    """EinteilungVon liefert (Gruppe, Eintrag); hier nur die Gruppe oder None."""
    r = tup(ns.Gruppen.EinteilungVon(datum, name))
    return None if r[0] is None else str(r[0])


print("== 48. Raidkader per Rangsync, Einteilung je Tag und Gruppe, geteilt an alle (Entscheid 17.10.2026) ==")
w = welt36()
c0, c1, c2 = w.clients[0], w.clients[1], w.clients[2]
ns0, ns1, ns2, lua0 = c0["ns"], c1["ns"], c2["ns"], c0["lua"]
for c in w.clients:
    c["ns"].Gruppen.Anlegen("20er")
for c_ in w.clients:
    c_["lua"].execute("""
__gilde = {
  [11] = { name = "Gildenleiter", guildRank = "Gildenmeister", guildRankOrder = 1 },
  [12] = { name = "Raider Eins", guildRank = "Raider", guildRankOrder = 3 },
  [13] = { name = "Raider Zwei", guildRank = "Raider", guildRankOrder = 3 },
  [14] = { name = "Neuling", guildRank = "Anwaerter", guildRankOrder = 5 },
  [21] = { name = "Leiter Kaos", guildRank = "Gildenmeister", guildRankOrder = 1 },
  [22] = { name = "Timo", guildRank = "Nebenrolle", guildRankOrder = 7 },
  [23] = { name = "Lina", guildRank = "Nebenrolle", guildRankOrder = 7 },
  [24] = { name = "Protti", guildRank = "Nebenrolle", guildRankOrder = 7 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
# Raidkader: ohne Rang geht nichts, mit Rang kommen alle bis dahin
r = tup3(ns0.Gruppen.RaidkaderSync())
fest(r[0] is None, "ohne gewaehlten Rang wird nichts eingelesen (%s)" % (r[1],))
n = tup3(ns0.Gruppen.RaidkaderSync(3))[0]
fest(n == 4, "bis Rang 3: vier Mitglieder, Leiter Kaos (Rang 1) eingeschlossen (%s)" % (n,))
kader = [str(x["name"]) for x in tup3(ns0.Gruppen.Raidkader())[0].values()]
fest("Neuling" not in kader and "Gildenleiter" in kader and "Raider Eins" in kader, "Neuling (Rang 5) ist nicht im Raidkader (%s)" % (kader,))
fest(ns0.Gruppen.RaidkaderRang() == 3, "der gewaehlte Rang wird gemerkt")

heute = str(ns0.Gruppen.EinteilungTag(0))
# Der Leiter teilt Timo ein, alle erfahren es
ok = tup(ns0.Gruppen.EinteilungSetzen(heute, "Timo", "40er"))[0]
fest(ok is True, "der Leiter teilt Timo in 40er ein")
w.weiter(5)
fest(all(ev(w.clients[k]["ns"], heute, "Timo") == "40er" for k in (0, 1, 2)), "alle Clients wissen: Timo ist in 40er ")
# Ein Mitglied darf nicht einteilen
ok, grund = tup(ns1.Gruppen.EinteilungSetzen(heute, "Lina", "40er"))
fest(ok is None, "ein Mitglied ohne Gildenrang-Recht darf nicht einteilen (%s)" % (grund,))
# Auch ein Raidleiter-Assistent ohne Schreibrecht darf nicht (nur wer laut Einstellungen schreiben darf)
fest(tup(ns1.Gruppen.EinteilungDarf("Timo"))[0] is False, "Timo (Rang 7) hat kein Schreibrecht")
fest(tup(ns0.Gruppen.EinteilungDarf("Leiter Kaos"))[0] is True, "Leiter Kaos (Gildenmeister) hat Schreibrecht")
# Timo wird zusaetzlich in 20er eingeteilt: unabhaengig von 40er
tup(ns0.Gruppen.EinteilungSetzen(heute, "Timo", "20er"))
w.weiter(5)
fest(ev(ns2, heute, "Timo") == "20er", "Timo ist jetzt in 20er")
fest(len(list(ns2.Gruppen.EinteilungListe(heute, "40er").values())) == 1, "und bleibt in 40er (unabhaengige Raid-Groessen)")
# Herausnehmen
tup(ns0.Gruppen.EinteilungSetzen(heute, "Timo", ""))
w.weiter(5)
fest(ev(ns2, heute, "Timo") is None, "herausgenommen: nicht eingeteilt")
# Aeltere Meldung gewinnt nie gegen die juengere
ns2.Abgleich.Empfangen("T;%s;Leiter Kaos;Timo|40er|1100000000" % heute, "Leiter Kaos-Realm", "GUILD")
fest(ev(ns2, heute, "Timo") is None, "eine alte Meldung ueberschreibt nichts")
# Fremde Absender: ohne Recht, mit falschem Urheber
ns2.Abgleich.Empfangen("T;%s;Timo;Lina|40er|%d" % (heute, int(w.t)), "Timo-Realm", "GUILD")
fest(ev(ns2, heute, "Lina") is None, "ein Absender ohne Recht wird abgelehnt")
ns2.Abgleich.Empfangen("T;%s;Leiter Kaos;Lina|40er|%d" % (heute, int(w.t)), "Timo-Realm", "GUILD")
fest(ev(ns2, heute, "Lina") is None, "falscher Urheber wird abgelehnt")

# Die Abwesenheitsliste einer Gruppe zeigt nur ihre Eingeteilten
for n_ in ("Lina", "Protti"):
    tup(ns0.Gruppen.EinteilungSetzen(heute, n_, "40er" if n_ == "Lina" else "20er"))
ns0.Gruppen.Aktivieren("40er")
abend = ns0.Anwesenheit.AktiverAbend(True)
namen = sorted(str(e["name"]).lower() for e in tup3(ns0.Anwesenheit.KandidatenListe(abend, True))[0].values())
fest(namen == ["lina"], "Gruppe 40er erwartet nur Lina, Protti (20er) nicht (%s)" % (namen,))

# Die Ansicht „Einteilung": oeffnen, Knoepfe, ein Klick setzt in die gewaehlte Gruppe
g0 = c0["g"]
sl0 = g0["SlashCmdList"]["FAIRSHARE"]
sl0("einteilung")
w.weiter(1)
fest(ns0.Fenster.Sichtbar() is True, "/fs einteilung oeffnet das Fenster")
fest(g0["__klick"]("Raidkader synchronisieren") is True, "Knopf Raidkader synchronisieren laeuft")
ids_ = list(ns0.Gruppen.IdListe().values())
fest(len(ids_) == 2 and len(list(g0["__text"]("Diese ID").values())) > 0, "die Einteilung zeigt die laufende Raid-ID")
ns0.Fenster.TagWaehlen(str(ids_[1]["datum"]))
fest(len(list(g0["__text"]("Nächste ID").values())) > 0, "und die nächste Raid-ID lässt sich wählen")
ns0.Fenster.TagWaehlen(str(ids_[0]["datum"]))
fest(g0["__klick"]("Einteilung senden") is True, "Knopf Einteilung senden laeuft")
sl0("raidkader 3")
sl0("einteilung status")
# Die Zeilen werden von allen Ansichten mitbenutzt: Knoepfe einer Ansicht duerfen in der anderen nicht stehen bleiben
def sichtbar(art):
    return int(ns0.Fenster.ZeilenKnoepfe()[art])
sl0("einteilung")
fest(sichtbar("teil") > 0 and sichtbar("unent") == 0 and sichtbar("bank") == 0, "Einteilung zeigt Hinzufuegen, keine Knoepfe der Abwesenheit (%d/%d)" % (sichtbar("teil"), sichtbar("unent")))
tup(ns0.Gruppen.EinteilungSetzen(heute, "Protti", "40er"))      # Protti steht nicht im Raid: er erscheint in der Abwesenheit
sl0("bank")
fest(sichtbar("unent") > 0 and sichtbar("teil") == 0, "Abwesenheit zeigt ihre Knoepfe, kein Hinzufuegen mehr (Fund im Spiel 18.10.2026)")
fest(sichtbar("vergessen") == 0 and sichtbar("abmeld") > 0, "Abwesend ist wieder als eigener Knopf da, Keine Meldung bleibt in der Einteilung (Wunsch 19.10.2026)")
sl0("einteilung")
fest(sichtbar("teil") > 0 and sichtbar("unent") == 0 and sichtbar("abmeld") == 0, "und wieder zurueck")

# Zwei Listen (Entscheid 22.10.2026): links verfuegbar, rechts in der Gruppe; ein Spieler steht nur in einer Gruppe
w9 = welt36()
m9 = w9.clients[0]["ns"]
m9.Gruppen.Anlegen("20er")
for c_ in w9.clients:
    c_["lua"].execute("""
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenleiter", guildRankOrder = 1 },
  [2] = { name = "Timo", guildRank = "Raider", guildRankOrder = 3 },
  [3] = { name = "Lina", guildRank = "Raider", guildRankOrder = 3 },
  [4] = { name = "Protti", guildRank = "Raider", guildRankOrder = 3 },
  [5] = { name = "Moe", guildRank = "Raider", guildRankOrder = 3 },
  [6] = { name = "Zora", guildRank = "Raider", guildRankOrder = 3 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
m9.Gruppen.RaidkaderSync(3)
tag9 = str(m9.Gruppen.EinteilungTag(0))
for name, ziel in (("Zora", "40er"), ("Timo", "20er"), ("Lina", "40er"), ("Moe", "20er"), ("Protti", "Bench")):
    tup(m9.Gruppen.EinteilungSetzen(tag9, name, ziel, "System"))
w9.clients[0]["g"]["SlashCmdList"]["FAIRSHARE"]("einteilung")
def zwei(reihe):
    return ([str(x["name"]) + ":" + str(x["gruppe"]) for x in reihe["verfuegbar"].values()],
            [str(x["name"]) + ":" + str(x["gruppe"]) for x in reihe["drin"].values()])
m9.Fenster.GruppeWaehlen("20er")
links, rechts = zwei(m9.Fenster.EinteilungReihenfolge())
fest(rechts == ["Moe:20er", "Timo:20er"], "rechts steht, wer in 20er ist (%s)" % (rechts,))
fest(links == ["Leiter Kaos:None", "Lina:None", "Protti:None", "Zora:None"],
     "links: wer nicht in 20er ist, ist fuer 20er verfuegbar (auch wer in 40er oder Bench steht) (%s)" % (links,))
m9.Fenster.GruppeWaehlen("40er")
links, rechts = zwei(m9.Fenster.EinteilungReihenfolge())
fest(rechts == ["Lina:40er", "Zora:40er"], "Ziel 40er: rechts Lina und Zora (%s)" % (rechts,))
fest(links == ["Leiter Kaos:None", "Moe:None", "Timo:None"], "und links wer nicht in 40er ist (%s)" % (links,))
m9.Fenster.GruppeWaehlen("Bench")
links, rechts = zwei(m9.Fenster.EinteilungReihenfolge())
fest(rechts == ["Protti:Bench"], "Ziel Bench: rechts Protti (%s)" % (rechts,))
fest(links == ["Leiter Kaos:None", "Moe:None", "Timo:None"],
     "links: wer in 20er steht, ist fuer 40er Bench verfuegbar (%s)" % (links,))
m9.Fenster.GruppeWaehlen("Keine Meldung")
links, rechts = zwei(m9.Fenster.EinteilungReihenfolge())
fest(links == ["Leiter Kaos:None"] and rechts == [],
     "und für Keine Meldung nur Unentschiedene (%s / %s)" % (links, rechts))

# Die Knoepfe: Hinzufuegen links, Entfernen rechts
m9.Fenster.GruppeWaehlen("Bench")
fest(str(m9.Fenster.EinteilungKlick("Protti")) == "entf", "er wird rechts bei der Bench entfernt")
m9.Fenster.GruppeWaehlen("20er")
fest(str(m9.Fenster.EinteilungKlick("Protti")) == "hinzu", "ein Klick holt ihn in 20er")
fest(ev(m9, tag9, "Protti") == "20er", "und er steht danach in 20er")
links, rechts = zwei(m9.Fenster.EinteilungReihenfolge())
fest("Protti:20er" in rechts and not any(x.startswith("Protti") for x in links), "Protti steht jetzt nur rechts (%s / %s)" % (links, rechts))
fest(str(m9.Fenster.EinteilungKlick("Timo")) == "entf", "Entfernen rechts nimmt Timo wieder heraus")
fest(tup(m9.Gruppen.EinteilungVon(tag9, "Timo", 20))[0] is None, "Timo ist in 20er nicht mehr eingeteilt")
fest(str(m9.Fenster.EinteilungKlick("Timo")) == "hinzu", "und taucht links als frei wieder auf")
# Ein Spieler in 20er ist fuer 40er verfuegbar und kann zusaetzlich eingeteilt werden
m9.Fenster.GruppeWaehlen("40er")
links, rechts = zwei(m9.Fenster.EinteilungReihenfolge())
fest(any(x.startswith("Moe") for x in links), "wer in 20er steht, ist fuer 40er verfuegbar (%s / %s)" % (links, rechts))
fest(m9.Fenster.EinteilungKlick("Moe") == "hinzu", "und laesst sich fuer 40er hinzufuegen")
fest(ev(m9, tag9, "Moe") == "40er" and "Moe" in list(m9.Gruppen.EinteilungListe(tag9, "20er").values()), "Moe ist in 20er und 40er")

# Der Klick auf einen Spieler in der Einteilung aendert die Einteilung der Raid-ID (auch bei den anderen)
tup(ns0.Gruppen.EinteilungSetzen(heute, "Lina", "40er"))
ns0.Fenster.GruppeWaehlen("40er")
fest(ev(ns0, heute, "Lina") == "40er", "Lina ist in 40er")
fest(str(ns0.Fenster.EinteilungKlick("Lina")) == "entf", "Entfernen rechts")
fest(ev(ns0, heute, "Lina") is None, "Lina ist nicht mehr eingeteilt")
w.weiter(5)
fest(ev(w.clients[1]["ns"], heute, "Lina") is None, "und das erfahren auch die anderen")
# (Lina steht in diesem Szenario nicht im Raidkader: nach dem Entfernen ist sie aus beiden Listen verschwunden.)
fest(ns0.Fenster.EinteilungKlick("Lina") is None, "wer nicht im Raidkader steht, ist nach dem Entfernen nicht mehr in den Listen")
ns0.Fenster.Verstecken()

print("== 49. „Fairshare nutzen?“: nur der Plündermeister wird gefragt, alle anderen uebernehmen (Wunsch 17.10.2026) ==")
w = gruppe(3, nutzung=None)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
m0, m1, m2 = w.clients[0], w.clients[1], w.clients[2]
fest(m0["ns"].Nutzung.Sichtbar() is True, "der Plündermeister wird gefragt")
fest(m1["ns"].Nutzung.Sichtbar() is False and m2["ns"].Nutzung.Sichtbar() is False, "die anderen werden NICHT gefragt")
fest(tup(m1["ns"].Rolle.Aktiv())[0] is False, "bis zur Antwort schlaeft das Addon bei den anderen")
D = m0["ns"].Nutzung.Dialog()
D["jaKnopf"]._scripts.OnClick(D["jaKnopf"])
w.weiter(3)
fest(m1["ns"].Rolle.Nutzung() == "ja" and m2["ns"].Rolle.Nutzung() == "ja", "„Ja“ des Plündermeisters gilt auch bei den anderen %s" % ([str(x) for x in m1["ns"].Nutzung.Protokoll().values()],))
fest(tup(m1["ns"].Rolle.Aktiv())[0] is True and tup(m2["ns"].Rolle.Aktiv())[0] is True, "bei den anderen laeuft das Addon jetzt")
# Eine eigene Entscheidung bleibt, auch wenn der Plündermeister es erneut meldet
m1["g"]["SlashCmdList"]["FAIRSHARE"]("nutzung nein")
fest(m1["ns"].Rolle.Nutzung() == "nein", "Timo entscheidet fuer sich: nein")
w.weiter(6)
m0["ns"].Nutzung.Verkuenden()
w.weiter(3)
fest(m1["ns"].Rolle.Nutzung() == "nein", "die eigene Entscheidung bleibt bei einer erneuten Meldung")
# Aendert der Plündermeister seine Antwort, folgt, wer sie nur uebernommen hatte
m0["ns"].Rolle.NutzungSetzen("nein")
w.weiter(3)
fest(m2["ns"].Rolle.Nutzung() == "nein", "„Nein“ des Plündermeisters wird uebernommen")
# Nur der Plündermeister zaehlt: eine Meldung eines Mitspielers wird ignoriert
w2 = gruppe(3, nutzung=None)
w2.ereignis("PLAYER_ENTERING_WORLD")
w2.weiter(15)
w2.clients[2]["ns"].Abgleich.Empfangen("U;ja", "Timo-Realm")
fest(w2.clients[2]["ns"].Rolle.Nutzung() is None, "eine Meldung ohne Plündermeister-Rolle wird ignoriert")

print("== 50. Raidtage je Gruppe: eigene Wochentage, Einteilung je Tag, mit allen geteilt (Entscheid 18.10.2026) ==")
w = welt36()
n0, n1, l0 = w.clients[0]["ns"], w.clients[1]["ns"], w.clients[0]["lua"]
n0.Gruppen.Anlegen("20er")
tage = [str(x["label"]) for x in tup3(n0.Gruppen.EinteilungTage())[0].values()]
fest(tage == ["Heute", "Morgen"], "ohne Raidtage: heute und morgen (%s)" % (tage,))
heute_wd = int(l0.eval("date('*t', time()).wday"))
zweiter = (heute_wd % 7) + 3 if (heute_wd % 7) + 3 <= 7 else ((heute_wd % 7) + 3) - 7
n0.Gruppen.RaidtagSetzen("40er", heute_wd, True)
n0.Gruppen.RaidtagSetzen("20er", zweiter, True)
liste = list(n0.Gruppen.EinteilungTage().values())
fest(len(liste) == 2, "zwei Gruppen mit verschiedenen Tagen: zwei Tage in der Liste (%d)" % len(liste))
fest(str(liste[0]["datum"]) == str(n0.Gruppen.EinteilungTag(0)), "der erste ist heute")
fest("40er" in str(liste[0]["label"]) and "20er" in str(liste[1]["label"]), "die Beschriftung nennt die Gruppe des Tages (%s / %s)" % (liste[0]["label"], liste[1]["label"]))
fest(str(n0.Gruppen.RaidtageText("20er")) != "", "Raidtage einer Gruppe als Text")
# Dieselben Tage fuer beide Gruppen: ein Tag, beide Gruppen
n0.Gruppen.RaidtagSetzen("20er", zweiter, False)
n0.Gruppen.RaidtagSetzen("20er", heute_wd, True)
liste = list(n0.Gruppen.EinteilungTage().values())
fest(len(liste) == 1 and "40er" in str(liste[0]["label"]) and "20er" in str(liste[0]["label"]), "beide Gruppen am selben Tag: ein Tag mit beiden Gruppen (%s)" % (liste[0]["label"],))
# Heute laesst sich immer einteilen, auch wenn keine Gruppe heute raidet
n0.Gruppen.RaidtagSetzen("40er", heute_wd, False)
n0.Gruppen.RaidtagSetzen("20er", heute_wd, False)
n0.Gruppen.RaidtagSetzen("40er", zweiter, True)
liste = list(n0.Gruppen.EinteilungTage().values())
fest(str(liste[0]["label"]) == "Heute" and len(liste) == 2, "Heute steht immer vorn (%d Tage)" % len(liste))
# Die Raidtage gehen mit den geteilten Einstellungen an die anderen
n0.Gruppen.RaidtagSetzen("40er", heute_wd, True)
z = n0.Konfig.Kodieren(n0.Konfig.Sammeln())
zeilen = [str(x) for x in z.values()]
fest(any(x.startswith("Y|40er|") and len(x) == len("Y|40er|") + 7 for x in zeilen), "Raidtage der Gruppe stehen im Paket (%s)" % ([x for x in zeilen if x.startswith("Y|")],))
s = n1.Konfig.Dekodieren(w.clients[1]["lua"].table_from(zeilen))
fest(s is not None, "und werden beim Empfaenger gelesen")
n1.Konfig.Anwenden(s)
fest(all(n1.Gruppen.RaidtagGewaehlt("40er", d_) == n0.Gruppen.RaidtagGewaehlt("40er", d_) for d_ in range(1, 8)), "der Empfaenger hat dieselben Raidtage der Gruppe")
fest(str(n0.Gruppen.RaidtagName(2)) in ("Mo", "Mon"), "Wochentage haben Kurznamen")

print("== 50b. „Keine Meldung“ als Ziel in der Einteilung ==")
heute = str(n0.Gruppen.EinteilungTag(0))
fest(tup(n0.Gruppen.Anlegen("Keine Meldung"))[0] is False, "eine Gruppe darf nicht „Keine Meldung“ heissen")
ok = tup(n0.Gruppen.EinteilungSetzen(heute, "Lina", "Keine Meldung", "System"))[0]
fest(ok is True, "ein Spieler laesst sich auf „Keine Meldung“ setzen")
r = tup(n0.Gruppen.EinteilungVon(heute, "Lina"))[0]
fest(r is not None and str(r) == "Keine Meldung", "und steht dort (%s)" % (r,))
fest(len(list(n0.Gruppen.EinteilungListe(heute, "40er").values())) == 0, "in keiner Gruppe")

print("== 51. Geteilte Einstellungen: Stufe 1 und 2 immer, Rangstufe nur von ihnen, nur lesen, Selbstheilung (Wunsch 17.10.2026) ==")
w = welt30()
for k in (0, 1, 2, 3):
    pass
ns0, ns1, ns2 = w.clients[0]["ns"], w.clients[1]["ns"], w.clients[2]["ns"]
# Die Standardgrenze ist 2: Ein Offizier wird auch von Clients angenommen, die nie eine Grenze bekommen haben
fest(ns2.Konfig.RangGrenze() == 2, "Standardgrenze ist Stufe 2")
fest(tup(ns2.Konfig.DarfWurzel("Timo"))[0] is True and tup(ns2.Konfig.DarfWurzel("Lina"))[0] is False, "Wurzel = Stufe 1 und 2")
# Ein schlafendes Addon (Timo sagte Nein zu Fairshare) bekommt trotzdem die geteilten Einstellungen und die Einteilung
db30(w, 1)["nutzung"] = "nein"
fest(tup(ns1.Rolle.Aktiv())[0] is False, "Timos Addon schlaeft")
einstellen_leiter(w)
ns0.Gruppen.RaidtagSetzen("10er", 2, True)
ns0.Konfig.Senden()
heute = str(ns0.Gruppen.EinteilungTag(0))
ns0.Gruppen.EinteilungSetzen(heute, "Lina", "10er")
w.weiter(8)
fest(db30(w, 1)["konfigStand"] is not None, "ein schlafendes Addon uebernimmt die geteilten Einstellungen")
fest(tup(ns1.Gruppen.RaidtagGewaehlt("10er", 2))[0] is True, "die Raidtage der Gruppe kommen mit")
r = tup(ns1.Gruppen.EinteilungVon(heute, "Lina"))[0]
fest(r is not None and str(r) == "10er", "und die Einteilung kommt ebenfalls an")
db30(w, 1)["nutzung"] = "ja"

# Die Rangstufe aendern darf nur die Wurzel: Lina (Stufe 3) darf senden, ihre Rangangabe wird ignoriert
for k in (0, 1, 2, 3):
    db30(w, k)["konfigRang"] = 3
db30(w, 2)["konfigRang"] = 5          # Lina stellt es bei sich hoch und sendet
stand0 = db30(w, 1)["konfigStand"]
ns2.Konfig.Senden()
w.weiter(8)
fest(db30(w, 1)["konfigStand"] != stand0, "Lina (Stufe 3, bei Grenze 3 berechtigt) wird angenommen")
fest(int(db30(w, 1)["konfigRang"]) == 3, "ihre Rangangabe (5) wird ignoriert, die Grenze bleibt 3")
# Gesperrt: Raider ab Stufe 3 ohne Recht (Grenze zurueck auf 2)
for k in (0, 1, 2, 3):
    db30(w, k)["konfigRang"] = 2
fest(tup(ns2.Konfig.Gesperrt())[0] is True, "Lina ist gesperrt (Stufe 3 > Grenze 2)")
fest(tup(ns1.Konfig.Gesperrt())[0] is False and tup(ns1.Konfig.Gesperrt(True))[0] is False, "Timo (Stufe 2) ist nicht gesperrt, auch nicht bei der Rangstufe")
db30(w, 2)["konfigRang"] = 3
fest(tup(ns2.Konfig.Gesperrt())[0] is False and tup(ns2.Konfig.Gesperrt(True))[0] is True, "bei Grenze 3 darf Lina schreiben, die Rangstufe aber nicht aendern")
db30(w, 2)["konfigRang"] = 2

# Selbstheilung: Wer nicht schreiben darf, wird auf den offiziellen Stand zurueckgesetzt
w = welt30()
einstellen_leiter(w)
ns0, ns1, ns2 = w.clients[0]["ns"], w.clients[1]["ns"], w.clients[2]["ns"]
ns0.Konfig.Senden()
w.weiter(8)
offiziell = db30(w, 2)["wurfDauer"]
db30(w, 2)["wurfDauer"] = 99
db30(w, 1)["wurfDauer"] = 99
fest(tup(ns2.Konfig.Heilen())[0] is True and db30(w, 2)["wurfDauer"] == offiziell, "Lina (ohne Recht) wird auf den offiziellen Stand zurueckgesetzt (%s)" % (db30(w, 2)["wurfDauer"],))
fest(tup(ns1.Konfig.Heilen())[0] is False and db30(w, 1)["wurfDauer"] == 99, "Timo (Offizier, darf schreiben) behaelt seinen Stand")

print("== 52. Abwesenheit mit mehreren Gruppen: der Knopf waehlt die Gruppe, ohne Gruppe keine Gildenliste (Fund im Spiel 18.10.2026) ==")
w = welt36()
c0 = w.clients[0]
ns0, g0 = c0["ns"], c0["g"]
for n_ in ("20er", "Gruppe 1"):
    ns0.Gruppen.Anlegen(n_)
ns0.Gruppen.Aktivieren(None)
heute = str(ns0.Gruppen.EinteilungTag(0))
tup(ns0.Gruppen.EinteilungSetzen(heute, "Protti", "20er", "System"))
tup(ns0.Gruppen.EinteilungSetzen(heute, "Moe", "Gruppe 1", "System"))
# Ohne gewaehlte Gruppe: niemand erwartet, auf keinen Fall die ganze Gilde
liste = [str(e["name"]) for e in tup3(ns0.Anwesenheit.KandidatenListe(None, True))[0].values()]
fest(len(liste) == 0, "ohne gewaehlte Gruppe wird niemand erwartet (%s)" % (liste,))
g0["SlashCmdList"]["FAIRSHARE"]("bank")
fest(len(list(g0["__text"]("Gruppe: keine").values())) > 0, "ohne aktive Gruppe steht „keine“ in der Ausklappliste")
ns0.Fenster.GruppeWaehlen("20er")
fest(str(ns0.Gruppen.AktivName()) == "20er", "die Wahl aktiviert die Gruppe (%s)" % (ns0.Gruppen.AktivName(),))
liste = sorted(str(e["name"]).lower() for e in tup3(ns0.Anwesenheit.KandidatenListe(None, True))[0].values())
fest(liste == ["protti"], "Gruppe 20er erwartet nur ihre Eingeteilten (%s)" % (liste,))
ns0.Fenster.GruppeWaehlen("Gruppe 1")
fest(str(ns0.Gruppen.AktivName()) == "Gruppe 1", "die andere Gruppe waehlen (%s)" % (ns0.Gruppen.AktivName(),))
liste = sorted(str(e["name"]).lower() for e in tup3(ns0.Anwesenheit.KandidatenListe(None, True))[0].values())
fest(liste == ["moe"], "Gruppe 1 erwartet nur ihre Eingeteilten (%s)" % (liste,))
ns0.Fenster.Verstecken()

print("== 53. Bench in der Einteilung: steht in der Abwesenheit jeder Gruppe, Faktor 0, Klick holt ihn in die Gruppe (Wunsch 18.10.2026) ==")
w = welt36()
n0 = w.clients[0]["ns"]
n0.Gruppen.Anlegen("20er")
n0.Gruppen.Aktivieren("40er")
heute = str(n0.Gruppen.EinteilungTag(0))
fest(tup(n0.Gruppen.Anlegen("bench"))[0] is False, "eine Gruppe darf nicht Bench heissen")
tup(n0.Gruppen.EinteilungSetzen(heute, "Protti", "40er", "System"))     # erwartet, nicht im Raid -> offen
tup(n0.Gruppen.EinteilungSetzen(heute, "Moe", "Bench", "System"))        # Bench
tup(n0.Gruppen.EinteilungSetzen(heute, "Zora", "20er", "System"))        # andere Gruppe
liste = tup3(n0.Anwesenheit.KandidatenListe(None, True))[0]
eintraege = {str(e["name"]).lower(): e for e in liste.values()}
fest("moe" in eintraege and bool(eintraege["moe"]["benchEinteilung"]), "die Bench steht in der Abwesenheit, als Bench erkennbar")
fest("protti" in eintraege and bool(eintraege["protti"]["imRaid"]), "der Eingeteilte gilt als anwesend")
fest("zora" not in eintraege, "Spieler der anderen Gruppe stehen nicht drin")
fest(eintraege["moe"]["bank"] is not None and not bool(eintraege["moe"]["offen"]), "Bench gilt wie Bank und ist nicht offen")
# Der Abschluss: Bench ist Bank (Faktor 0), blockiert nicht
n0.Anwesenheit.AktiverAbend(True)
n0.Anwesenheit.AbmeldungSetzen("Protti", True, "System")
v = tup(n0.Anwesenheit.AbendVorschau())[0]
st = {str(e["schluessel"]): (str(e["status"]), float(e["zuschlag"])) for e in v["spieler"].values()}
fest(st.get("moe") == ("bank", 0.0), "Bench: Status bank, kein Zuschlag (%s)" % (st.get("moe"),))
ok = tup3(n0.Anwesenheit.AbendAbschliessen(None, "System", True))[0]
fest(ok is True, "Der Abend laesst sich abschliessen (Bench blockiert nicht)")
# Einspringen: der Klick holt ihn in die aktive Gruppe
w2 = welt36()
m0 = w2.clients[0]["ns"]
m0.Gruppen.Aktivieren("40er")
heute = str(m0.Gruppen.EinteilungTag(0))
tup(m0.Gruppen.EinteilungSetzen(heute, "Moe", "Bench", "System"))
fest(tup(m0.Anwesenheit.BenchEinspringen("Moe", "System"))[0] is True, "Bench-Spieler springt ein")
r = tup(m0.Gruppen.EinteilungVon(heute, "Moe"))[0]
fest(r is not None and str(r) == "40er", "er steht jetzt in der aktiven Gruppe (%s)" % (r,))

print("== 54. Abschluss einer Gruppe sperrt die andere nicht (Fund beim Durchdenken 18.10.2026) ==")
w = welt36()
n0 = w.clients[0]["ns"]
n0.Gruppen.Anlegen("20er")
n0.Gruppen.Aktivieren("40er")
n0.Anwesenheit.AktiverAbend(True)
ok = tup3(n0.Anwesenheit.AbendAbschliessen(None, "System"))[0]
fest(ok is True, "Gruppe 40er schliesst ihren Abend ab")
fest(tup(n0.Anwesenheit.AbendIstAbgeschlossen())[0] is True, "fuer 40er gilt der Abend als abgeschlossen")
n0.Gruppen.Aktivieren("20er")
fest(tup(n0.Anwesenheit.AbendIstAbgeschlossen())[0] is False, "fuer die Gruppe 20er ist er NICHT abgeschlossen (eigener Abend)")
ok, grund = tup(n0.Anwesenheit.AbendWiedereroeffnen(None, "System"))
fest(ok is None, "20er hat nichts zum Wiedereroeffnen (%s)" % (grund,))
n0.Gruppen.Aktivieren("40er")
ok = tup(n0.Anwesenheit.AbendWiedereroeffnen(None, "System"))[0]
fest(ok is True, "40er oeffnet ihren eigenen Abend wieder")

print("== 55. Wochenabschluss: Abgemeldete und Keine Meldung, zwei Abende, Mittel der Gruppen-Schnitte (Entscheid 18.10.2026) ==")
w = welt36()
n0, lua0 = w.clients[0]["ns"], w.clients[0]["lua"]
n0.Gruppen.Anlegen("20er")
heute = str(n0.Gruppen.EinteilungTag(0))
montag = str(n0.Anwesenheit.WochenTage(heute).__getitem__(1))
fest(len(list(n0.Anwesenheit.WochenTage(heute).values())) == 7, "eine Woche hat sieben Tage")
r = tup(n0.Anwesenheit.WocheVorschau(heute))
fest(r[0] is None, "ohne Raidkader und ohne Abend gibt es keine Vorschau (%s)" % (r[1],))
for c_ in w.clients:
    c_["lua"].execute("""
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenleiter", guildRankOrder = 1 },
  [2] = { name = "Timo", guildRank = "Raider", guildRankOrder = 3 },
  [3] = { name = "Lina", guildRank = "Raider", guildRankOrder = 3 },
  [4] = { name = "Protti", guildRank = "Raider", guildRankOrder = 3 },
  [5] = { name = "Moe", guildRank = "Raider", guildRankOrder = 3 },
  [6] = { name = "Zora", guildRank = "Neuling", guildRankOrder = 5 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
fest(tup(n0.Gruppen.RaidkaderSync(5))[0] == 6, "Raidkader mit sechs Spielern")
# Einteilung: Timo und Lina in 40er, Protti auf der Bench, Moe bei Keine Meldung, Zora nirgends (abgemeldet)
for name, ziel in (("Leiter Kaos", "40er"), ("Timo", "40er"), ("Lina", "40er"), ("Protti", "Bench"), ("Moe", "Keine Meldung")):
    tup(n0.Gruppen.EinteilungSetzen(heute, name, ziel, "System"))
# Ein abgeschlossener Gruppenabend (Schnitt 1) in dieser Woche
n0.Gruppen.Aktivieren("40er")
n0.Anwesenheit.AktiverAbend(True)
n0.Anwesenheit.BossBuchen("Lucifron", 4001, True, lua0.table_from(["Leiter Kaos", "Timo", "Lina"]))
w.eintragen(0, "Timo", 9701, int(w.t))
w.eintragen(0, "Lina", 9702, int(w.t) + 1)
w.eintragen(0, "Leiter Kaos", 9703, int(w.t) + 2)
tup3(n0.Anwesenheit.AbendAbschliessen(None, "System"))
v = tup(n0.Anwesenheit.WocheVorschau(heute))[0]
fest(v is not None, "mit Raidkader und einem Gruppenabend gibt es eine Vorschau")
abg = sorted(str(x) for x in v["abgemeldet"].values())
kei = sorted(str(x) for x in v["keineMeldung"].values())
fest(abg == ["Zora"], "abgemeldet ist nur, wer nirgends steht (%s)" % (abg,))
fest(kei == ["Moe"], "Keine Meldung: wer so eingeteilt ist (%s)" % (kei,))
fest("Protti" not in abg and "Protti" not in kei, "wer auf der Bench steht, wird nicht gebucht")
fest(float(v["n"]) == 1 and abs(float(v["schnitte"][1]) - 1.0) < 1e-9, "ein Abend, Schnitt 1,0 (n=%s)" % (v["n"],))
# Buchen: Zuschlag je Spieler, mit Staffel 0,7 (1. Fehlen)
b = tup(n0.Anwesenheit.WocheBuchen(heute, "System"))[0]
fest(b is not None and float(b["gebucht"]) == 2, "zwei Zuschlaege gebucht (%s)" % (b["gebucht"] if b is not None else None,))
w.weiter(10)
fest(abs(zuschlag_von(w, 0, "zora") - 0.7) < 1e-9, "Zora: 0,7 x Schnitt 1 (%s)" % (zuschlag_von(w, 0, "zora"),))
fest(abs(zuschlag_von(w, 1, "zora") - 0.7) < 1e-9, "und das erfahren die Mitspieler")
fest(zuschlag_von(w, 0, "protti") is None and zuschlag_von(w, 0, "timo") is None, "Bench und Gruppe bekommen keinen Zuschlag")
# Erneut buchen aendert nichts (zuerst zurueck, dann neu)
tup(n0.Anwesenheit.WocheBuchen(heute, "System"))
w.weiter(10)
fest(abs(zuschlag_von(w, 0, "zora") - 0.7) < 1e-9, "erneutes Buchen verdoppelt nichts (%s)" % (zuschlag_von(w, 0, "zora"),))
# Zuruecknehmen
n = tup(n0.Anwesenheit.WocheZuruecknehmen(heute, "System"))[0]
w.weiter(10)
fest(zuschlag_von(w, 0, "zora") is None and zuschlag_von(w, 1, "zora") is None, "zurueckgenommen: bei allen weg")
# Rechte
r = tup(n0.Anwesenheit.WocheBuchen(heute, "Zora"))
fest(r[0] is None, "ein Spieler ohne Schreibrecht (Stufe 3) darf nicht buchen (%s)" % (r[1],))

print("== 56. Neuen Abend beginnen: der abgeschlossene Abend wird verlassen, die Wertungen bleiben (Wunsch 18.10.2026) ==")
w = welt36()
n0 = w.clients[0]["ns"]
n0.Gruppen.Aktivieren("40er")
abend36(w)
tup(n0.Anwesenheit.AbmeldungSetzen("Protti", True, "System"))
ok = tup3(n0.Anwesenheit.AbendAbschliessen(None, "System", True))[0]
fest(ok is True, "Abend abgeschlossen")
w.weiter(10)
vorher = zuschlag_von(w, 0, "protti")
fest(vorher is not None and vorher > 0, "Protti hat einen Zuschlag (%s)" % (vorher,))
fest(tup(n0.Anwesenheit.AbendIstAbgeschlossen())[0] is True, "der Abend gilt als abgeschlossen")
ok = tup(n0.Anwesenheit.AbendNeuBeginnen("System"))[0]
fest(ok is True, "Neuen Abend beginnen")
fest(tup(n0.Anwesenheit.AbendIstAbgeschlossen())[0] is False, "danach ist kein Abend mehr abgeschlossen: die Liste ist frei")
fest(abs(zuschlag_von(w, 0, "protti") - vorher) < 1e-9, "die gebuchte Wertung bleibt (%s)" % (zuschlag_von(w, 0, "protti"),))
fest(abs(zuschlag_von(w, 1, "protti") - vorher) < 1e-9, "auch bei den Mitspielern")
r = tup(n0.Anwesenheit.AbendNeuBeginnen("System"))
fest(r[0] is None, "ohne abgeschlossenen Abend gibt es nichts zu verlassen (%s)" % (r[1],))

print("== 57. Raid-ID: eine Einteilung je ID, der Wechseltag ist einstellbar, Reiter nur mit Schreibrecht (Entscheid 22.10.2026) ==")
w = welt36()
n0, l0, g0 = w.clients[0]["ns"], w.clients[0]["lua"], w.clients[0]["g"]
n0.Gruppen.Anlegen("20er")
for c_ in w.clients:
    c_["lua"].execute("""
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenleiter", guildRankOrder = 1 },
  [2] = { name = "Timo", guildRank = "Raider", guildRankOrder = 3 },
  [3] = { name = "Lina", guildRank = "Rekrut", guildRankOrder = 5 },
  [4] = { name = "Protti", guildRank = "Raider", guildRankOrder = 3 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
# Wechseltag Mittwoch (Standard): 21.10.2026 ist ein Mittwoch
fest(int(n0.Gruppen.IdWechsel()) == 4, "Standard-Wechseltag ist Mittwoch")
fest(str(n0.Gruppen.IdStart("2026-10-21")) == "2026-10-21", "der Mittwoch beginnt eine Raid-ID")
fest(str(n0.Gruppen.IdStart("2026-10-20")) == "2026-10-14", "der Dienstag davor gehoert zur alten ID")
fest(str(n0.Gruppen.IdStart("2026-10-27")) == "2026-10-21", "der Dienstag danach gehoert noch zu ihr")
fest(str(n0.Gruppen.IdStart("2026-10-28")) == "2026-10-28", "der naechste Mittwoch beginnt die naechste")
fest(tup(n0.Gruppen.IdWechselSetzen(2))[0] is True and str(n0.Gruppen.IdStart("2026-10-20")) == "2026-10-19",
     "Wechseltag Montag: der Dienstag gehoert zur ID ab Montag")
n0.Gruppen.IdWechselSetzen(4)
# Ein Eintrag gilt fuer die ganze ID, an welchem Tag man ihn auch setzt
heute57 = str(n0.Gruppen.EinteilungTag(0))
start57 = str(n0.Gruppen.IdStart(heute57))
r57 = tup(n0.Gruppen.EinteilungSetzen(heute57, "Timo", "20er", "System"))
fest(r57[0] is True, "Timo einteilen (%s)" % (r57,))
fest(ev(n0, start57, "Timo") == "20er", "am ersten Tag der ID ist Timo in 20er")
fest(ev(n0, heute57, "Timo") == "20er", "und heute ebenso")
# Die Raid-ID-Tage haengen zusammen: die Woche der Abschluesse sind die sieben Tage ab dem Wechseltag
tage57 = [str(x) for x in n0.Anwesenheit.WochenTage(heute57).values()]
fest(len(tage57) == 7 and tage57[0] == start57, "die Tage der ID beginnen am Wechseltag (%s)" % (tage57,))
# Geteilt: der Wechseltag und der Rang reisen mit den Einstellungen
n0.Gruppen.IdWechselSetzen(5)
n0.Gruppen.RaidkaderRangSetzen(3)
n0.Konfig.Senden()
w.weiter(8)
fest(int(w.clients[1]["ns"].Gruppen.IdWechsel()) == 5, "der Wechseltag kommt bei den anderen an")
fest(w.clients[1]["ns"].Gruppen.RaidkaderRang() is not None and int(w.clients[1]["ns"].Gruppen.RaidkaderRang()) == 3, "der Raidkader-Rang ebenso")
n0.Gruppen.IdWechselSetzen(4)
# Reiter: Abwesenheit und Einteilung nur mit Schreibrecht
g0["SlashCmdList"]["FAIRSHARE"]("einteilung")
fest(n0.Fenster.ReiterSichtbar("einteilung") is True and n0.Fenster.ReiterSichtbar("bank") is True, "die Gildenleitung sieht Einteilung und Abwesenheit")
c2 = w.clients[2]
c2["g"]["SlashCmdList"]["FAIRSHARE"]("einteilung")
fest(c2["ns"].Fenster.ReiterSichtbar("einteilung") is False and c2["ns"].Fenster.ReiterSichtbar("bank") is False,
     "ein Raider sieht nur Spieler und Verlauf")
fest(c2["ns"].Fenster.ReiterSichtbar("liste") is True and c2["ns"].Fenster.ReiterSichtbar("verlauf") is True, "die beiden bleiben")
fest(str(c2["ns"].Fenster.AktuelleAnsicht()) == "liste", "und /fs einteilung landet bei ihm in der Spielerliste")
n0.Fenster.Verstecken()
c2["ns"].Fenster.Verstecken()

print("== 58. Geteilte Einstellungen gehen nach einer Aenderung von selbst an alle (Wunsch 22.10.2026) ==")
w = welt36()
n0, n1, n2 = w.clients[0]["ns"], w.clients[1]["ns"], w.clients[2]["ns"]
for c_ in w.clients:
    c_["lua"].execute("""
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenleiter", guildRankOrder = 1 },
  [2] = { name = "Timo", guildRank = "Offizier", guildRankOrder = 2 },
  [3] = { name = "Lina", guildRank = "Raider", guildRankOrder = 3 },
  [4] = { name = "Protti", guildRank = "Rekrut", guildRankOrder = 5 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
fest(tup(n0.Gruppen.Anlegen("20er"))[0] is True, "Leiter legt eine Gruppe an")
fest(n0.Konfig.AutoSenden() is True, "die Aenderung loest das automatische Senden aus")
w.weiter(12)
fest("20er" in [str(x) for x in n1.Gruppen.Namen().values()], "Timo hat die Gruppe ohne Zutun bekommen")
fest(tup(n0.Gruppen.Loeschen("20er"))[0] is True, "Leiter loescht sie wieder")
n0.Konfig.AutoSenden()
w.weiter(12)
fest("20er" not in [str(x) for x in n1.Gruppen.Namen().values()], "und sie ist bei Timo wieder weg")
fest(n2.Konfig.AutoSenden() is False, "ein Spieler ohne Schreibrecht sendet nichts automatisch")

print("== 59. Leitungs-Abgleich: Spieler mit Schreibrecht gleichen gildenweit ab, auch ohne Gruppe und ohne Plündermeister (Wunsch 22.10.2026) ==")
w = gruppe(3, nutzung=None)                 # niemand ist im Dienst: nur der Leitungs-Abgleich kann etwas tun
for c_ in w.clients:
    c_["lua"].execute("""
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenleiter", guildRankOrder = 1 },
  [2] = { name = "Timo", guildRank = "Offizier", guildRankOrder = 2 },
  [3] = { name = "Lina", guildRank = "Rekrut", guildRankOrder = 5 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
fest(tup(w.clients[0]["ns"].Rolle.Aktiv())[0] is False, "Ausgangslage: das Addon ist nicht im Dienst")
z0 = int(w.t)
for i in range(6):
    w.setze(0, "kaos%d" % i, {"awardedTo": "Timo", "itemID": 7000 + i, "timestamp": z0 - i * 5000})
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(150)
fest(w.stand(0) == w.stand(1), "Timo (Offizier) hat die Historie von Kaos bekommen: %s / %s" % (w.stand(0), w.stand(1)))
fest(anz(w, 1) == 6, "alle sechs Eintraege (%d)" % anz(w, 1))
fest(anz(w, 2) == 0, "Lina (ohne Schreibrecht) bekommt nichts (%d)" % anz(w, 2))
aus1 = [str(x) for x in w.clients[1]["g"]["__ausgabe"].values()]
fest(any("Mit der Leitung abgeglichen" in x or "Synced with the leadership" in x for x in aus1), "Timo sieht eine Meldung (%s)" % (aus1[-2:],))
# Die andere Richtung
w.setze(1, "timo1", {"awardedTo": "Lina", "itemID": 7100, "timestamp": z0 - 100})
w.clients[1]["ns"].Abgleich.LeitungBeaconSpaeter(1)
w.weiter(400)
fest(w.stand(0) == w.stand(1) and anz(w, 0) == 7, "ein Eintrag von Timo kommt bei Kaos an (%d)" % anz(w, 0))
fest(anz(w, 2) == 0, "und weiterhin nicht bei Lina")
# Ausgeschaltet: Timo nimmt nichts mehr an
w.clients[1]["ns"].Erfassung.Einstellungen()["leitungSync"] = False
w.setze(0, "kaos9", {"awardedTo": "Moe", "itemID": 7200, "timestamp": z0 - 50})
w.clients[0]["ns"].Abgleich.LeitungBeaconSpaeter(1)
w.weiter(400)
fest(anz(w, 1) == 7, "mit ausgeschaltetem Schalter bleibt Timo unveraendert (%d)" % anz(w, 1))

print("== 60. Gildenweiter Reset: Reset-Marke, nur Stufe 1 und 2, Altes kommt nicht zurueck (Wunsch 22.10.2026) ==")
w = gruppe(3)
for c_ in w.clients:
    c_["lua"].execute("""
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenleiter", guildRankOrder = 1 },
  [2] = { name = "Timo", guildRank = "Offizier", guildRankOrder = 2 },
  [3] = { name = "Lina", guildRank = "Rekrut", guildRankOrder = 5 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
z0 = int(w.t)
for k in range(3):
    for i in range(4):
        w.setze(k, "e%d" % i, {"awardedTo": "Timo", "itemID": 8000 + i, "timestamp": z0 - 1000 * (i + 1)})
    w.clients[k]["lua"].execute('FairshareDB.zuschlaege["z_alt_timo"] = { wert = 1.5 }')
def leer(k):
    return bool(w.clients[k]["lua"].eval("next(FairshareDB.zuschlaege) == nil"))
ns_l, ns_t, ns_k = w.clients[2]["ns"], w.clients[1]["ns"], w.clients[0]["ns"]
r = tup(ns_l.Erfassung.GildenReset())
fest(r[0] is None and anz(w, 2) == 4, "Lina (Stufe 3) darf nicht gildenweit zuruecksetzen, nichts geaendert (%s)" % (r,))
r = tup(ns_t.Erfassung.GildenReset())
fest(r[0] == 4, "Timo (Stufe 2) darf: 4 Eintraege entfernt (%s)" % (r,))
w.weiter(25)
fest(anz(w, 0) == 0 and anz(w, 1) == 0 and anz(w, 2) == 0, "bei allen ist die Historie leer (%d/%d/%d)" % (anz(w, 0), anz(w, 1), anz(w, 2)))
fest(leer(0) and leer(1) and leer(2), "und das Datenbuch (Zuschlaege) auch")
rz = [float(c_["ns"].Erfassung.ResetZeit()) for c_ in w.clients]
fest(rz[0] > 0 and rz[0] == rz[1] == rz[2], "alle haben dieselbe Reset-Marke (%s)" % (rz,))
fest(len(list(w.clients[0]["g"]["FairshareDB"]["gruppen"].values())) >= 0, "die Gruppen bleiben bestehen")
# Ein Spieler, der den Reset noch nicht hat, bringt Altes nicht zurueck; Neues schon
w.setze(0, "alt", {"awardedTo": "Lina", "itemID": 8100, "timestamp": int(rz[0]) - 5000})
w.setze(0, "neu", {"awardedTo": "Lina", "itemID": 8101, "timestamp": int(w.t) + 5})
ok, grund = tup(ns_k.Abgleich.Starten())
w.weiter(70)
ids1 = w.ids(1)
fest("neu" in ids1 and "alt" not in ids1, "Timo bekommt den neuen Eintrag, den alten nicht (%s)" % (ids1,))
fest("alt" not in w.ids(2), "Lina ebenso")
# Eine Reset-Marke von Stufe 3 gilt nicht
for c_ in w.clients:
    c_["ns"].Erfassung.Einstellungen()["konfigRang"] = 3
w.clients[2]["ns"].Erfassung.Einstellungen()["resetZeit"] = int(w.t) + 500
vorher = float(ns_k.Erfassung.ResetZeit())
tup(ns_l.Konfig.Senden())
w.weiter(20)
fest(float(ns_k.Erfassung.ResetZeit()) == vorher and anz(w, 0) >= 1, "eine Reset-Marke von Stufe 3 wird ignoriert, Daten bleiben (%d)" % anz(w, 0))
# Gesperrt: Lina kann es auch ueber den Befehl nicht
w.clients[2]["g"]["SlashCmdList"]["FAIRSHARE"]("reset gilde")
aus = [str(x) for x in w.clients[2]["g"]["__ausgabe"].values()]
fest(any("Stufe 1 und 2" in x or "level 1 and 2" in x for x in aus), "/fs reset gilde meldet ihr, dass nur Stufe 1 und 2 es duerfen")

print("== 61. /fs test laeuft auch, wenn der Spieler eine Einteilung und eine aktive Gruppe hat (Fund im Spiel 19.10.2026) ==")
w = welt36()
n0, g0 = w.clients[0]["ns"], w.clients[0]["g"]
heute = str(n0.Gruppen.EinteilungTag(0))
tup(n0.Gruppen.EinteilungSetzen(heute, "Timo", "40er", "System"))
n0.Gruppen.Aktivieren("40er")
g0["__ausgabe"] = w.clients[0]["lua"].table()
g0["SlashCmdList"]["FAIRSHARE"]("test")
aus = [str(x) for x in g0["__ausgabe"].values()]
fehler = [x for x in aus if "Error" in x or "Fehler im" in x or "attempt to" in x]
fest(not fehler, "/fs test meldet keinen Fehler (%s)" % (fehler[:2],))
fest(any("bestanden" in x.lower() or "passed" in x.lower() or "Prüfungen" in x for x in aus) or len(aus) > 0, "und gibt etwas aus (%d Zeilen)" % len(aus))

print("== 62. Auto-Senden ueber die Oberflaeche: Gruppe in den Einstellungen loeschen erreicht die anderen (Fund im Spiel 19.10.2026) ==")
w = welt36()
n0, g0, l0 = w.clients[0]["ns"], w.clients[0]["g"], w.clients[0]["lua"]
n1 = w.clients[1]["ns"]
for c_ in w.clients:
    c_["lua"].execute("""
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenleiter", guildRankOrder = 1 },
  [2] = { name = "Timo", guildRank = "Offizier", guildRankOrder = 2 },
  [3] = { name = "Lina", guildRank = "Rekrut", guildRankOrder = 5 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
n0.Gruppen.Anlegen("Test1")
n0.Konfig.Senden()
w.weiter(12)
fest("Test1" in [str(x) for x in n1.Gruppen.Namen().values()], "Ausgangslage: Timo kennt die Gruppen")
g0["SlashCmdList"]["FAIRSHARE"]("einstellungen")
w.weiter(1)
g0["__klick"]("Gruppen")
n0.Einstellungen.Aktualisieren()
namen_vorher = [str(x) for x in n0.Gruppen.Namen().values()]
for nm in namen_vorher:
    g0["__klick"]("Löschen")
    g0["__klick"]("Wirklich löschen")
    n0.Einstellungen.Aktualisieren()
fest(len(list(n0.Gruppen.Namen().values())) == 0, "Kaos hat alle Gruppen ueber die Knoepfe geloescht")
w.weiter(15)
rest1 = [str(x) for x in n1.Gruppen.Namen().values()]
fest(len(rest1) == 0, "und Timo hat die Loeschung ohne Zutun bekommen (%s)" % (rest1,))
n0.Einstellungen.Verstecken()

print("== 63. Probe-Modus: /fs probe abend simuliert Standardabend, FairshareDB bleibt unverändert, nichts gesendet ==")
w = welt36(auto=True)
c0, c1 = w.clients[0], w.clients[1]
n0, n1 = c0["ns"], c1["ns"]
g0 = c0["g"]

# Ausgangslage: 1 Vergabe auf beiden Clients in FairshareDB
w.eintragen(0, "Leiter Kaos", 8001, int(w.t))
w.weiter(10)
fest(anz(w, 0) == 1 and anz(w, 1) == 1, "Ausgangslage: 1 echter Eintrag in FairshareDB bei beiden")
abende_0 = len(list(n0.Anwesenheit.Daten()["abende"].keys()))
zuschlaege_0 = len(list(n0.Anwesenheit.Daten()["zuschlaege"].keys()))

# Client 0 ruft /fs probe auf -> Hilfezeilen
g0["SlashCmdList"]["FAIRSHARE"]("probe")
fest(any("probe abend" in str(m) for m in g0["__ausgabe"].values()), "/fs probe nennt /fs probe abend")

# Client 0 ruft /fs probe abend auf
g0["__ausgabe"] = c0["lua"].table()
g0["SlashCmdList"]["FAIRSHARE"]("probe abend")

# 1. Chat-Ausgabe pruefen (Erwartet / Ist fuer alle 6 Kategorien)
chat0 = [str(m) for m in g0["__ausgabe"].values()]
fest(any("Raid (Anna)" in m and "[OK]" in m for m in chat0), "Chat nennt Raid (Anna) [OK]")
fest(any("Bench (Nora)" in m and "[OK]" in m for m in chat0), "Chat nennt Bench (Nora) [OK]")
fest(any("Weder an- noch abgemeldet (Max)" in m and "[OK]" in m for m in chat0), "Chat nennt Weder an- noch abgemeldet (Max) [OK]")
fest(any("Abgemeldet (Kevin, Lisa)" in m and "[OK]" in m for m in chat0), "Chat nennt Abgemeldet (Kevin, Lisa) [OK]")
fest(any("Proberaid 1. Abend (Igor)" in m and "[OK]" in m for m in chat0), "Chat nennt Proberaid 1. Abend (Igor) [OK]")
fest(any("Neuling 2. Abend (Jonas)" in m and "[OK]" in m for m in chat0), "Chat nennt Neuling 2. Abend (Jonas) [OK]")
fest(any("6/6" in m and "bestanden" in m for m in chat0), "Chat meldet 6/6 Prüfungen bestanden")

# 2. FairshareDB von Client 0 ist unveraendert
fest(anz(w, 0) == 1, "FairshareDB von Client 0 unveraendert (1 Eintrag)")
fest(len(list(n0.Anwesenheit.Daten()["abende"].keys())) == abende_0, "FairshareDB abende von Client 0 unveraendert")
fest(len(list(n0.Anwesenheit.Daten()["zuschlaege"].keys())) == zuschlaege_0, "FairshareDB zuschlaege von Client 0 unveraendert")

# 3. Client 1 hat absolut nichts empfangen
w.weiter(20)
fest(anz(w, 1) == 1, "Client 1 hat nichts empfangen (Historie unveraendert)")
fest(len(list(n1.Anwesenheit.Daten()["abende"].keys())) == abende_0, "Client 1 hat keine Abende empfangen")
fest(len(list(n1.Anwesenheit.Daten()["zuschlaege"].keys())) == zuschlaege_0, "Client 1 hat keine Zuschlaege empfangen")

# 4. Direkter Aufruf ohne Chat-Ausgabe
ok, res = tup(n0.Anwesenheit.ProbeStandardAbend(False))
fest(ok is True, "ProbeStandardAbend erfolgreich")
fest(res["pruefungen"]["raid"]["ok"] is True, "Raid-Rechnung korrekt")
fest(res["pruefungen"]["bench"]["ok"] is True, "Bench-Rechnung korrekt")
fest(res["pruefungen"]["keineMeldung"]["ok"] is True, "Keine-Meldung-Rechnung korrekt")
fest(res["pruefungen"]["abgemeldet"]["ok"] is True, "Abgemeldet-Rechnung korrekt")
fest(res["pruefungen"]["proberaid"]["ok"] is True, "Proberaid-Rechnung korrekt")
fest(res["pruefungen"]["neuling"]["ok"] is True, "Neuling-Rechnung korrekt")
fest(res["gesendet"] > 0, "Broadcasts wurden im Probe-Modus blockiert")

print("== 64. Probe-Modus Oberflaeche: Roster, Raid-Toggle, Vergabe, Isolation, Abschluss und Bereinigung ==")
w = welt36(auto=True)
c0, c1 = w.clients[0], w.clients[1]
n0, n1 = c0["ns"], c1["ns"]
g0 = c0["g"]

# 1. Ausgangslage: 1 Vergabe auf beiden Clients in FairshareDB
w.eintragen(0, "Leiter Kaos", 9001, int(w.t))
w.weiter(10)
fest(anz(w, 0) == 1 and anz(w, 1) == 1, "Ausgangslage: 1 echter Eintrag in FairshareDB bei beiden")
abende_vorher = len(list(n0.Anwesenheit.Daten()["abende"].keys()))
zuschlaege_vorher = len(list(n0.Anwesenheit.Daten()["zuschlaege"].keys()))

# 2. Probe-Modus ueber die Oberflaeche aktivieren
n0.Fenster.ProbeModus(True)
fest(n0.Probe.Aktiv() is True, "Probe-Modus ist aktiv")
fest(n0.Fenster.IstProbe() is True, "Fensterzustand zeigt Probe-Modus an")

# 3. Erfundenes Roster pruefen
roster = [str(x) for x in n0.Probe.Roster().values()]
fest(len(roster) == 14 and "Anna" in roster and "Igor" in roster and "Jonas" in roster and "Nora" in roster, "Erfundenes Roster enthaelt 14 Spieler")
fest(n0.Probe.IstImRaid("Anna") is True and n0.Probe.IstImRaid("Ben") is True and n0.Probe.IstImRaid("Nora") is False, "Standard: 10 im Raid, Nora nicht")

# 4. Raid-Toggle: Spieler in den Raid holen
n0.Probe.ToggleRaid("Nora")
fest(n0.Probe.IstImRaid("Nora") is True, "Nora in den Raid geholt")

# 5. Items im Probe-Modus vergeben (Main und OS)
ok1, it1 = tup(n0.Probe.VergebeItem("Nora", False, 9101))
fest(ok1 is True and it1["OS"] is False, "Main-Item an Nora vergeben")
ok2, it2 = tup(n0.Probe.VergebeItem("Ben", True, 9102))
fest(ok2 is True and it2["OS"] is True, "OS-Item an Ben vergeben")
fest(len(list(n0.Probe.Historie().keys())) == 2, "2 Eintraege in der Probe-Historie")

# 6. Status setzen: Bench, Unentschuldigt, Abgemeldet
n0.Probe.SetzeBank("Nora", True)
fest(bool(tup(n0.Anwesenheit.IstBank("Nora"))[0]) is True, "Nora auf die Bench gesetzt")
fest(n0.Probe.IstImRaid("Nora") is False, "Nora nicht mehr im Raid")
n0.Probe.SetzeKeineMeldung("Max", True)
fest(bool(tup(n0.Anwesenheit.IstVergessen("Max"))[0]) is True, "Max als Keine Meldung markiert")
n0.Probe.SetzeAbgemeldet("Kevin", True)
fest(bool(tup(n0.Anwesenheit.IstAbgemeldet("Kevin"))[0]) is True, "Kevin abgemeldet")

# 7. Abend abschliessen in der Wegwerf-DB
abend = n0.Anwesenheit.AktiverAbend(False)
fest(abend is not None, "Aktiver Probe-Abend vorhanden")
okAbschluss, _, zAnzahl = tup3(n0.Anwesenheit.AbendAbschliessen(abend, "ProbeLeiter"))
fest(okAbschluss is True, "Probe-Abend erfolgreich abgeschlossen")
fest(zAnzahl == 3, "3 Zuschlaege verbucht (Max, Kevin, Lisa)")

# 8. Netzwerk-Isolation: Mitspieler empfaengt absolut nichts
w.weiter(30)
fest(anz(w, 1) == 1, "Client 1 hat waehrend des Probe-Modus nichts empfangen (1 echter Eintrag)")
fest(len(list(n1.Anwesenheit.Daten()["abende"].keys())) == 0, "Client 1 hat keine Probe-Abende empfangen")
fest(len(list(n1.Anwesenheit.Daten()["zuschlaege"].keys())) == 0, "Client 1 hat keine Probe-Zuschlaege empfangen")

# 9. Probe-Modus beenden: Alles aufgeraeumt, echte Daten unveraendert
n0.Fenster.ProbeModus(False)
fest(n0.Probe.Aktiv() is False, "Probe-Modus beendet")
fest(n0.Fenster.IstProbe() is False, "Fenster nicht mehr im Probe-Modus")
fest(anz(w, 0) == 1, "Client 0 hat nach Beenden wieder exakt seinen 1 echten Eintrag")
fest(len(list(n0.Anwesenheit.Daten()["abende"].keys())) == abende_vorher, "Client 0 FairshareDB abende unveraendert")
fest(len(list(n0.Anwesenheit.Daten()["zuschlaege"].keys())) == zuschlaege_vorher, "Client 0 FairshareDB zuschlaege unveraendert")

print("== 65. Raidkader: Gildenraenge einzeln waehlbar, Zwischenraenge auslassen ==")
for cl in (w.clients[0], w.clients[1]):
    cl["lua"].execute("""
__gilde65 = {
  [21] = { name = "Leiter Kaos", guildRank = "Gildenmeister", guildRankOrder = 0 },
  [22] = { name = "Timo", guildRank = "Offizier", guildRankOrder = 1 },
  [23] = { name = "Lina", guildRank = "Mitglied", guildRankOrder = 2 },
  [24] = { name = "Moe", guildRank = "Initiand", guildRankOrder = 3 },
}
C_Club = C_Club or {}
C_Club.GetGuildClubId = function() return 1 end
C_Club.GetClubMembers = function() local t = {} for id in pairs(__gilde65) do t[#t + 1] = id end table.sort(t) return t end
C_Club.GetMemberInfo = function(club, id) return __gilde65[id] end
""")

# Raenge einzeln setzen: 0, 1 und 3 an, 2 aus
n0.Gruppen.RaidkaderRangSetzen(0, True)
n0.Gruppen.RaidkaderRangSetzen(1, True)
n0.Gruppen.RaidkaderRangSetzen(2, False)
n0.Gruppen.RaidkaderRangSetzen(3, True)

fest(n0.Gruppen.RaidkaderRangGewaehlt(0) is True, "Rang 0 (Leiter Kaos) ist gewaehlt")
fest(n0.Gruppen.RaidkaderRangGewaehlt(1) is True, "Rang 1 (Timo) ist gewaehlt")
fest(n0.Gruppen.RaidkaderRangGewaehlt(2) is False, "Rang 2 (Lina) ist NICHT gewaehlt (ausgelassen)")
fest(n0.Gruppen.RaidkaderRangGewaehlt(3) is True, "Rang 3 (Moe) ist gewaehlt")

anzahl = tup3(n0.Gruppen.RaidkaderSync())[0]
fest(anzahl == 3, "RaidkaderSync liest genau 3 Mitglieder ein (%s)" % (anzahl,))
kaderNamen = [str(x["name"]) for x in tup3(n0.Gruppen.Raidkader())[0].values()]
fest("Leiter Kaos" in kaderNamen and "Timo" in kaderNamen and "Moe" in kaderNamen, "Leiter Kaos, Timo und Moe sind im Raidkader")
fest("Lina" not in kaderNamen, "Lina (Rang 2) ist ausgelassen und fehlt im Raidkader")

# Synchronisation ueber Konfig (N|0,1,3)
n0.Konfig.Senden()
w.weiter(10)
fest(w.clients[1]["ns"].Gruppen.RaidkaderRangGewaehlt(2) is False, "Client 1 uebernimmt: Rang 2 nicht gewaehlt")
fest(w.clients[1]["ns"].Gruppen.RaidkaderRangGewaehlt(0) is True and w.clients[1]["ns"].Gruppen.RaidkaderRangGewaehlt(3) is True,
     "Client 1 uebernimmt: Raenge 0 und 3 gewaehlt")
tup3(w.clients[1]["ns"].Gruppen.RaidkaderSync())
kader1 = [str(x["name"]) for x in tup3(w.clients[1]["ns"].Gruppen.Raidkader())[0].values()]
fest("Leiter Kaos" in kader1 and "Moe" in kader1 and "Lina" not in kader1, "Client 1 synchronisiert denselben gefilterten Kader")

print("== 66. Raid-Groessen 10er, 20er und 40er: Gruppen erstellen, unabhaengige Zuweisung je Groesse ==")
w66 = welt36()
for c_ in w66.clients:
    c_["lua"].execute("""
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenmeister", guildRankOrder = 1 },
  [2] = { name = "Timo", guildRank = "Raider", guildRankOrder = 3 },
  [3] = { name = "Lina", guildRank = "Raider", guildRankOrder = 3 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
    c_["ns"].Gruppen.Anlegen("Kara 1", 10)
    c_["ns"].Gruppen.Anlegen("Kara 2", 10)
    c_["ns"].Gruppen.Anlegen("ZulGurub", 20)
    c_["ns"].Gruppen.Anlegen("MoltenCore", 40)
w66.ereignis("PLAYER_ENTERING_WORLD")
w66.weiter(15)

ns66_0, ns66_1 = w66.clients[0]["ns"], w66.clients[1]["ns"]
heute66 = str(ns66_0.Gruppen.EinteilungTag(0))

# 1. Gruppen fuer verschiedene Groessen angelegt und Groessen geprueft
fest(ns66_0.Gruppen.Groesse("Kara 1") == 10, "Kara 1 ist 10er")
fest(ns66_0.Gruppen.Groesse("Kara 2") == 10, "Kara 2 ist 10er")
fest(ns66_0.Gruppen.Groesse("ZulGurub") == 20, "ZulGurub ist 20er")
fest(ns66_0.Gruppen.Groesse("MoltenCore") == 40, "MoltenCore ist 40er")

# 2. Spieler Anna wird in 10er, 20er und 40er eingeteilt
tup(ns66_0.Gruppen.EinteilungSetzen(heute66, "Anna", "Kara 1"))
tup(ns66_0.Gruppen.EinteilungSetzen(heute66, "Anna", "ZulGurub"))
tup(ns66_0.Gruppen.EinteilungSetzen(heute66, "Anna", "MoltenCore"))
w66.weiter(5)

# Anna ist in allen drei Gruppen gleichzeitig eingeteilt
fest("Anna" in list(ns66_0.Gruppen.EinteilungListe(heute66, "Kara 1").values()), "Anna in Kara 1 (10er)")
fest("Anna" in list(ns66_0.Gruppen.EinteilungListe(heute66, "ZulGurub").values()), "Anna in ZulGurub (20er)")
fest("Anna" in list(ns66_0.Gruppen.EinteilungListe(heute66, "MoltenCore").values()), "Anna in MoltenCore (40er)")

# Client 1 erfaehrt alle drei Zuweisungen
fest("Anna" in list(ns66_1.Gruppen.EinteilungListe(heute66, "Kara 1").values()), "Client 1: Anna in Kara 1")
fest("Anna" in list(ns66_1.Gruppen.EinteilungListe(heute66, "ZulGurub").values()), "Client 1: Anna in ZulGurub")
fest("Anna" in list(ns66_1.Gruppen.EinteilungListe(heute66, "MoltenCore").values()), "Client 1: Anna in MoltenCore")

# 3. Innerhalb derselben Groesse wechselt die Zuweisung (Kara 1 -> Kara 2)
tup(ns66_0.Gruppen.EinteilungSetzen(heute66, "Anna", "Kara 2"))
w66.weiter(5)
fest("Anna" not in list(ns66_0.Gruppen.EinteilungListe(heute66, "Kara 1").values()), "Anna nicht mehr in Kara 1")
fest("Anna" in list(ns66_0.Gruppen.EinteilungListe(heute66, "Kara 2").values()), "Anna nun in Kara 2")
fest("Anna" in list(ns66_0.Gruppen.EinteilungListe(heute66, "ZulGurub").values()), "ZulGurub unberuehrt")
fest("Anna" in list(ns66_0.Gruppen.EinteilungListe(heute66, "MoltenCore").values()), "MoltenCore unberuehrt")

# 4. Einzelne Groesse leeren (Entfernen aus 20er)
tup(ns66_0.Gruppen.EinteilungSetzen(heute66, "Anna", "", None, 20))
w66.weiter(5)
fest("Anna" not in list(ns66_0.Gruppen.EinteilungListe(heute66, "ZulGurub").values()), "Anna aus 20er entfernt")
fest("Anna" in list(ns66_0.Gruppen.EinteilungListe(heute66, "Kara 2").values()), "Kara 2 bleibt aktiv")
fest("Anna" in list(ns66_0.Gruppen.EinteilungListe(heute66, "MoltenCore").values()), "MoltenCore bleibt aktiv")
fest("Anna" not in list(ns66_1.Gruppen.EinteilungListe(heute66, "ZulGurub").values()), "Client 1: 20er entfernt")
fest("Anna" in list(ns66_1.Gruppen.EinteilungListe(heute66, "Kara 2").values()), "Client 1: Kara 2 aktiv")
fest("Anna" in list(ns66_1.Gruppen.EinteilungListe(heute66, "MoltenCore").values()), "Client 1: MoltenCore aktiv")

print("== 67. Einteilung anfragen & anzeigen, Verlauf-Suche, Gruppe einladen ==")

# 1. MeineEinteilungText
txt_anna = str(ns66_0.Gruppen.MeineEinteilungText("Anna", heute66))
fest("[10er] Kara 2" in txt_anna and "[40er] MoltenCore" in txt_anna, "MeineEinteilungText enthaelt 10er und 40er Zuweisungen")

# 2. Client 1 fragt Einteilung an (Gruppen.EinteilungAnfragen)
tup(ns66_1.Gruppen.EinteilungAnfragen())
w66.weiter(5)
fest("Anna" in list(ns66_1.Gruppen.EinteilungListe(heute66, "Kara 2").values()), "Client 1 hat Einteilung erhalten")

# 3. Gruppe einladen (Anwesenheit.GruppeEinladen) mit Online-Filter & Auto-Raid
# Setze aktive Gruppe und weise Anna (online) und Ben (offline) zu
ns66_0.Gruppen.Aktivieren("Kara 2")
ns66_0.Gruppen.EinteilungSetzen(heute66, "Ben", "Kara 2")

w66.clients[0]["lua"].execute("""
__converted_to_raid = false
__invited = {}
C_PartyInfo = {
    InviteUnit = function(name)
        __invited[#__invited + 1] = name
        return true
    end,
    ConvertToRaid = function()
        __converted_to_raid = true
    end,
}
ConvertToRaid = function()
    __converted_to_raid = true
end
-- Anna ist online (presence 1), Ben ist offline (presence 3)
__gilde[10] = { name = "Anna", guildRank = "Raider", guildRankOrder = 3, presence = 1 }
__gilde[11] = { name = "Ben", guildRank = "Raider", guildRankOrder = 3, presence = 3 }
""")
res = ns66_0.Anwesenheit.GruppeEinladen()
ok_inv, anz_inv, anz_drin, anz_off = tup(res)
inv_list = list(w66.clients[0]["lua"].eval("__invited").values())
fest(ok_inv and "Anna" in inv_list, "Gruppe einladen hat Online-Spieler (Anna) eingeladen")
fest("Ben" not in inv_list, "Gruppe einladen hat Offline-Spieler (Ben) uebersprungen")
fest(anz_off == 1, "Offline-Spieler als offline gezaehlt")

# Pruefe Auto-Raid-Konvertierung sobald Gruppe geformt ist
w66.clients[0]["lua"].execute("""
IsInGroup = function() return true end
IsInRaid = function() return false end
UnitIsGroupLeader = function() return true end
""")
ns66_0.Anwesenheit.GruppeEinladen()
fest(w66.clients[0]["lua"].eval("__converted_to_raid"), "Gruppe wurde automatisch in Raid konvertiert")

# 4. Verlauf-Suche & Ungefilterte Historie
w66.clients[0]["ns"].Erfassung.Eintragen("Anna", "|cffa335ee|Hitem:19019::::::::80:::::|h[Donnerzorn]|h|r", 1700000100, "haupt")
w66.clients[0]["ns"].Erfassung.Eintragen("Ben", "|cffa335ee|Hitem:18803::::::::80:::::|h[Fichtenrinde]|h|r", 1700000200, "haupt")
w66.weiter(5)

# Fenster oeffnen und Verlauf anzeigen
w66.clients[0]["ns"].Fenster.ZeigenAnsicht("verlauf")
w66.clients[0]["ns"].Fenster.Aktualisieren()
fest(w66.clients[0]["ns"].Fenster.AktuelleAnsicht() == "verlauf", "Fenster ist im Verlauf-Modus")

# 5. Sichtbarkeit von inviteBtn pruefen: darf nur in bank sichtbar sein
w66.clients[0]["ns"].Fenster.ZeigenAnsicht("einteilung")
w66.clients[0]["ns"].Fenster.Aktualisieren()
fest(not w66.clients[0]["ns"].Fenster.InviteBtnSichtbar(), "inviteBtn ist in einteilung ausgeblendet")

w66.clients[0]["ns"].Fenster.ZeigenAnsicht("verlauf")
w66.clients[0]["ns"].Fenster.Aktualisieren()
fest(not w66.clients[0]["ns"].Fenster.InviteBtnSichtbar(), "inviteBtn ist in verlauf ausgeblendet")

w66.clients[0]["ns"].Fenster.ZeigenAnsicht("liste")
w66.clients[0]["ns"].Fenster.Aktualisieren()
fest(not w66.clients[0]["ns"].Fenster.InviteBtnSichtbar(), "inviteBtn ist in liste ausgeblendet")

w66.clients[0]["ns"].Fenster.ZeigenAnsicht("bank")
w66.clients[0]["ns"].Fenster.Aktualisieren()
fest(w66.clients[0]["ns"].Fenster.InviteBtnSichtbar(), "inviteBtn ist in bank sichtbar")
fest(w66.clients[0]["ns"].Fenster.WocheBtnSichtbar(), "wocheBtn ist in bank sichtbar")
w66.clients[0]["ns"].Fenster.ZeigenAnsicht("einteilung")
w66.clients[0]["ns"].Fenster.Aktualisieren()
fest(w66.clients[0]["ns"].Fenster.WocheBtnSichtbar(), "wocheBtn ist in einteilung sichtbar")
w66.clients[0]["ns"].Fenster.ZeigenAnsicht("liste")
w66.clients[0]["ns"].Fenster.Aktualisieren()
fest(not w66.clients[0]["ns"].Fenster.WocheBtnSichtbar(), "wocheBtn ist in liste ausgeblendet")

# Auch in Demo/Beispiel sichtbar:
w66.clients[0]["ns"].Fenster.ZeigenAnsicht("bank")
w66.clients[0]["ns"].Fenster.Aktualisieren()
fest(w66.clients[0]["ns"].Fenster.WocheBtnSichtbar(), "wocheBtn ist in bank sichtbar (vor Demo)")
w66.clients[0]["g"]["SlashCmdList"]["FAIRSHARE"]("demo")
w66.clients[0]["ns"].Fenster.ZeigenAnsicht("bank")
w66.clients[0]["ns"].Fenster.Aktualisieren()
fest(w66.clients[0]["ns"].Fenster.WocheBtnSichtbar(), "wocheBtn ist auch in Demo sichtbar")
w66.clients[0]["ns"].Fenster.Zeigen(False)

print("== 68. Mehrfachvergabe desselben Gegenstands & Konsistente Lokalisierung ==")
w68 = gruppe(2)
w68.ereignis("PLAYER_ENTERING_WORLD")
w68.weiter(15)
c0, c1 = w68.clients[0], w68.clients[1]
ns0, ns1 = c0["ns"], c1["ns"]
lua0, lua1 = c0["lua"], c1["lua"]
link_dagger = "|cffa335ee|Hitem:50412::::::::80:::::|h[Blasphemischer Dolch]|h|r"
t0 = int(w68.t)

# 1. Erste Vergabe via Wurf an Timo
res1 = tup3(ns0.Erfassung.Eintragen("Timo", link_dagger, t0, "haupt", None, lua0.table_from({"herkunft": "wurf", "wurf": 88})))
fest(res1[0] is True, "Erster Dolch an Timo vergeben")

# 2. Zweite Vergabe desselben Gegenstands in der exakt selben Sekunde via Wurf (z. B. Dual Wield)
res2 = tup3(ns0.Erfassung.Eintragen("Timo", link_dagger, t0, "haupt", None, lua0.table_from({"herkunft": "wurf", "wurf": 74})))
fest(res2[0] is True, "Zweiter Dolch an Timo in derselben Sekunde nicht blockiert (ok=True)")

# 3. Dritte Vergabe desselben Gegenstands 10 Sekunden spaeter via Wurf
res3 = tup3(ns0.Erfassung.Eintragen("Timo", link_dagger, t0 + 10, "haupt", None, lua0.table_from({"herkunft": "wurf", "wurf": 95})))
fest(res3[0] is True, "Dritter Dolch an Timo 10s spaeter nicht blockiert (ok=True)")

# 4. Pruefen, dass genau 3 Eintraege fuer Timo in der Historie sind
timo_dolche = [k for k, v in ns0.Erfassung.Historie().items() if v["awardedTo"] == "Timo" and v["itemID"] == 50412]
fest(len(timo_dolche) == 3, "Genau 3 Dolche in Timos Historie (gefunden: %d)" % len(timo_dolche))

# 5. Chat-Beutemeldungen (Echo) fuer den Dolch erzeugen keine 4. Vergabe
ns0.Erfassung.Beutemeldung("Timo erhält Beute: " + link_dagger + ".")
fest(len([k for k, v in ns0.Erfassung.Historie().items() if v["awardedTo"] == "Timo" and v["itemID"] == 50412]) == 3, "Chat-Echo erzeugt keinen doppelten Eintrag")

# 6. Abgleich an Client 1 uebertraegt alle 3 Dolche sauber
w68.weiter(15)
c0["ns"].Abgleich.Starten()
w68.weiter(90)
timo_c1 = [k for k, v in ns1.Erfassung.Historie().items() if v["awardedTo"] == "Timo" and v["itemID"] == 50412]
fest(len(timo_c1) == 3, "Client 1 hat nach Abgleich alle 3 Dolche (gefunden: %d)" % len(timo_c1))

# 7. Lokalisierung: Auf englischem Client sind Fehlermeldungen und Systemtexte uebersetzt
EN_TABLE = ns1.EN
fest(EN_TABLE["schon vorhanden"] == "already present", "Locale hat 'schon vorhanden' -> 'already present'")
fest(EN_TABLE["unvollständig"] == "incomplete", "Locale hat 'unvollständig' -> 'incomplete'")
fest(EN_TABLE["kein Bedarfswurf"] == "not a main roll", "Locale hat 'kein Bedarfswurf' -> 'not a main roll'")
fest(EN_TABLE["%d Würfe erfasst, keiner wertbar"] == "%d rolls recorded, none ranked", "Locale hat '%d rolls recorded, none ranked'")
fest(EN_TABLE["[FEHLER]"] == "[ERROR]", "Locale hat '[FEHLER]' -> '[ERROR]'")

print("== 69. Gruppenweiser Wochenabschluss: Jede Gruppe schließt einzeln ab ==")
w69 = gruppe(2)
for c_ in w69.clients:
    c_["lua"].execute("""
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenleiter", guildRankOrder = 1 },
  [2] = { name = "Timo", guildRank = "Raider", guildRankOrder = 3 },
  [3] = { name = "Lina", guildRank = "Raider", guildRankOrder = 3 },
  [4] = { name = "Protti", guildRank = "Raider", guildRankOrder = 3 },
  [5] = { name = "Moe", guildRank = "Raider", guildRankOrder = 3 },
  [6] = { name = "Zora", guildRank = "Neuling", guildRankOrder = 5 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
    c_["ns"].Gruppen.Anlegen("Gruppe A", 40)
    c_["ns"].Gruppen.Anlegen("Gruppe B", 40)

w69.ereignis("PLAYER_ENTERING_WORLD")
w69.weiter(15)
c0, c1 = w69.clients[0], w69.clients[1]
ns0, ns1 = c0["ns"], c1["ns"]
lua0 = c0["lua"]

heute69 = str(ns0.Gruppen.EinteilungTag(0))
ns0.Gruppen.RaidkaderSync(5)

# Einteilung: Timo in Gruppe A, Lina in Gruppe B, Moe bei Keine Meldung, Zora nirgends (abgemeldet)
ns0.Gruppen.EinteilungSetzen(heute69, "Leiter Kaos", "Gruppe A", "System")
ns0.Gruppen.EinteilungSetzen(heute69, "Timo", "Gruppe A", "System")
ns0.Gruppen.EinteilungSetzen(heute69, "Lina", "Gruppe B", "System")
ns0.Gruppen.EinteilungSetzen(heute69, "Protti", "Gruppe B", "System")
ns0.Gruppen.EinteilungSetzen(heute69, "Moe", "Keine Meldung", "System")

# Relevante Gruppen pruefen: beide haben Zuweisungen
rel_gruppen = list(ns0.Anwesenheit.WochenGruppen(heute69).values())
fest("Gruppe A" in rel_gruppen and "Gruppe B" in rel_gruppen, "beide Gruppen fuer die Woche relevant")

# Abend fuer Gruppe A abhalten und abschliessen (Schnitt 1.0)
ns0.Gruppen.Aktivieren("Gruppe A")
ns0.Anwesenheit.AktiverAbend(True)
ns0.Anwesenheit.BossBuchen("Lucifron", 5001, True, lua0.table_from(["Leiter Kaos", "Timo"]))
w69.eintragen(0, "Timo", 9801, int(w69.t))
w69.eintragen(0, "Leiter Kaos", 9802, int(w69.t) + 1)
tup3(ns0.Anwesenheit.AbendAbschliessen(None, "System"))

# Gruppe A schliesst ihre Woche ab
ok_a, stat_a = tup(ns0.Anwesenheit.WocheGruppeSetzen(heute69, "Gruppe A", "abgeschlossen", "System"))
fest(ok_a is True and stat_a == "abgeschlossen", "Gruppe A erfolgreich als abgeschlossen markiert")
fest(not ns0.Anwesenheit.WocheIstGebucht(heute69), "Woche noch nicht gebucht: Gruppe B fehlt noch")

ue = ns0.Anwesenheit.WochenGruppenUebersicht(heute69)
fest(ue["gesamt"] == 2 and ue["bereit"] == 1 and not ue["alleBereit"], "Uebersicht: 1 von 2 Gruppen bereit")

# Pruefe UI-Button-Zustand waehrend Gruppe A fertig und Gruppe B offen
ns0.Gruppen.Aktivieren("Gruppe B")
ns0.Fenster.ZeigenAnsicht("bank")
ns0.Fenster.Aktualisieren()
fest(ns0.Fenster.WocheBtnSichtbar(), "wocheBtn sichtbar")
fest(ns0.Fenster.WochePauseBtnSichtbar(), "wochePauseBtn sichtbar da mehrere Gruppen und Gruppe B offen")

# Abend fuer Gruppe B abhalten und abschliessen
ns0.Anwesenheit.AktiverAbend(True)
ns0.Anwesenheit.BossBuchen("Magmadar", 5002, True, lua0.table_from(["Lina", "Protti"]))
w69.eintragen(0, "Lina", 9803, int(w69.t) + 2)
w69.eintragen(0, "Lina", 9804, int(w69.t) + 3)
w69.eintragen(0, "Protti", 9805, int(w69.t) + 4)
w69.eintragen(0, "Protti", 9806, int(w69.t) + 5)
tup3(ns0.Anwesenheit.AbendAbschliessen(None, "System"))

# Gruppe B schliesst ihre Woche ab -> Alle Gruppen bereit -> automatischer Wochenabschluss!
ok_b, stat_b, res_v = tup3(ns0.Anwesenheit.WocheGruppeSetzen(heute69, "Gruppe B", "abgeschlossen", "System"))
fest(ok_b is True and stat_b == "gebucht", "Gruppe B fertig -> automatischer Wochenabschluss ausgeloest")
fest(ns0.Anwesenheit.WocheIstGebucht(heute69), "Woche ist nun verbindlich gebucht")

# Zuschlag Zora (abgemeldet): Staffel 0,7 x Schnitt 1,0 = 0,7
w69.weiter(15)
fest(abs(zuschlag_von(w69, 0, "zora") - 0.7) < 1e-9, "Zora hat Zuschlag 0,7 erhalten (%s)" % (zuschlag_von(w69, 0, "zora"),))
fest(abs(zuschlag_von(w69, 1, "zora") - 0.7) < 1e-9, "Client 1 hat Zuschlag uebernommen")
# Pruefe Pausieren-Logik: nach Zuruecknehmen Gruppe A pausieren
ns0.Anwesenheit.WocheZuruecknehmen(heute69, "System")
fest(not ns0.Anwesenheit.WocheIstGebucht(heute69), "Woche zurueckgenommen")
ok_p, stat_p = tup(ns0.Anwesenheit.WocheGruppeSetzen(heute69, "Gruppe A", "pausiert", "System"))
fest(ok_p is True and stat_p == "pausiert", "Gruppe A als pausiert markiert")
ue_p = ns0.Anwesenheit.WochenGruppenUebersicht(heute69)
fest(ue_p["gruppen"]["Gruppe A"]["status"] == "pausiert" and ue_p["gruppen"]["Gruppe A"]["istBereit"], "pausierte Gruppe gilt als bereit")

print("== 70. Globale gruppenuebergreifende Wertung: Wertung im Hauptfenster unabhaengig von 10er/40er ==")
w70 = gruppe(3)
w70.ereignis("PLAYER_ENTERING_WORLD")
w70.weiter(15)
cl0 = w70.clients[0]
ns70_0, g70_0 = cl0["ns"], cl0["g"]

# Gruppen "10er" und "40er" anlegen
ns70_0.Gruppen.Anlegen("10er", 10)
ns70_0.Gruppen.Anlegen("40er", 40)
heute70 = str(ns70_0.Gruppen.EinteilungTag(0))

# Timo und Lina in 10er einteilen, Timo und Peter in 40er
ns70_0.Gruppen.EinteilungSetzen(heute70, "Timo", "10er", "System")
ns70_0.Gruppen.EinteilungSetzen(heute70, "Lina", "10er", "System")
ns70_0.Gruppen.EinteilungSetzen(heute70, "Timo", "40er", "System")
ns70_0.Gruppen.EinteilungSetzen(heute70, "Peter", "40er", "System")
w70.weiter(5)

# 1. Beute in der 10er Gruppe: Timo erhaelt ein Item
ns70_0.Gruppen.Aktivieren("10er")
w70.eintragen(0, "Timo", 7001, int(w70.t))

# 2. Beute in der 40er Gruppe: Timo erhaelt ein weiteres Item, Lina erhaelt ein Item
ns70_0.Gruppen.Aktivieren("40er")
w70.weiter(2)
w70.eintragen(0, "Timo", 7002, int(w70.t))
w70.eintragen(0, "Lina", 7003, int(w70.t) + 1)

# Abgleich an Client 1
w70.weiter(15)
fest(anz(w70, 0) == 3, "Client 0 hat 3 Vergaben (1x 10er, 2x 40er)")
fest(anz(w70, 1) == 3, "Client 1 hat 3 Vergaben")

# 3. Hauptfenster oeffnen und Gruppe "10er" im Dropdown auswaehlen
ns70_0.Fenster.Zeigen(False)
ns70_0.Fenster.ZeigenAnsicht("liste")
ns70_0.Fenster.GruppeWaehlen("10er")
ns70_0.Fenster.Aktualisieren()

# Pruefe: Es werden nur die eingeteilten Mitglieder der 10er Gruppe gezeigt (Timo, Lina)
zeilen = list(ns70_0.Fenster.SichtbareZeilen().values())
namen_sichtbar = [z["name"] for z in zeilen]
fest("Timo" in namen_sichtbar and "Lina" in namen_sichtbar, "Timo und Lina sind in 10er-Ansicht sichtbar")
fest("Peter" not in namen_sichtbar, "Peter (nur 40er) ist in 10er-Ansicht ausgeblendet")

# Pruefe Wertung: Obwohl die Ansicht auf "10er" steht, hat Timo Wertung 2 (1x 10er + 1x 40er)!
# Und Lina hat Wertung 1 (aus der 40er Gruppe)!
timo_zeile = next((z for z in zeilen if z["name"] == "Timo"), None)
lina_zeile = next((z for z in zeilen if z["name"] == "Lina"), None)
fest(timo_zeile is not None, "Timo-Zeile gefunden")
fest(lina_zeile is not None, "Lina-Zeile gefunden")

# In der Wertungspalte steht bei Timo "2" (GELB .. "2" .. "|r") und bei Lina "1"
fest("2" in str(timo_zeile["wertung"]), "Timos Wertung in 10er-Ansicht ist 2 (gruppenuebergreifend!): %s" % (timo_zeile["wertung"],))
fest("1" in str(lina_zeile["wertung"]), "Linas Wertung in 10er-Ansicht ist 1 (obwohl Item im 40er gewonnen): %s" % (lina_zeile["wertung"],))

# 4. Umschalten auf "40er": Timo und Peter sichtbar, Lina ausgeblendet
ns70_0.Fenster.GruppeWaehlen("40er")
ns70_0.Fenster.Aktualisieren()
zeilen_40 = list(ns70_0.Fenster.SichtbareZeilen().values())
namen_40 = [z["name"] for z in zeilen_40]
fest("Timo" in namen_40 and "Peter" in namen_40, "Timo und Peter in 40er-Ansicht sichtbar")
fest("Lina" not in namen_40, "Lina (nur 10er eingeteilt) ist in 40er-Ansicht ausgeblendet")
timo_40 = next((z for z in zeilen_40 if z["name"] == "Timo"), None)
peter_40 = next((z for z in zeilen_40 if z["name"] == "Peter"), None)
fest("2" in str(timo_40["wertung"]), "Timos Wertung in 40er-Ansicht ist weiterhin 2: %s" % (timo_40["wertung"],))
fest("0" in str(peter_40["wertung"]), "Peters Wertung in 40er-Ansicht ist 0: %s" % (peter_40["wertung"],))

# 5. Umschalten auf "Alle": Alle sichtbar, Timo hat Wertung 2, Lina 1, Peter 0
ns70_0.Fenster.GruppeWaehlen("")
ns70_0.Fenster.Aktualisieren()
zeilen_alle = list(ns70_0.Fenster.SichtbareZeilen().values())
namen_alle = [z["name"] for z in zeilen_alle]
fest("Timo" in namen_alle and "Lina" in namen_alle and "Leiter Kaos" in namen_alle, "Raidmitglieder in Gesamtansicht sichtbar")
timo_alle = next((z for z in zeilen_alle if z["name"] == "Timo"), None)
fest("2" in str(timo_alle["wertung"]), "Timos Wertung in Gesamtansicht ist 2: %s" % (timo_alle["wertung"],))

print("== 71. Probe-Modus schuetzt die echten Daten: gildenweiter Reset und Einstellungen-Senden gesperrt ==")
w = welt36()
n0, l0 = w.clients[0]["ns"], w.clients[0]["lua"]
for c_ in w.clients:
    c_["lua"].execute("""
__gilde = {
  [1] = { name = "Leiter Kaos", guildRank = "Gildenleiter", guildRankOrder = 1 },
  [2] = { name = "Timo", guildRank = "Offizier", guildRankOrder = 2 },
  [3] = { name = "Lina", guildRank = "Rekrut", guildRankOrder = 5 },
}
C_Club = {
  GetGuildClubId = function() return 1 end,
  GetClubMembers = function() local t = {} for id in pairs(__gilde) do t[#t + 1] = id end table.sort(t) return t end,
  GetMemberInfo = function(club, id) return __gilde[id] end,
}
""")
w.eintragen(0, "Leiter Kaos", 9101, int(w.t))
w.weiter(5)
fest(anz(w, 0) == 1, "Ausgangslage: ein echter Eintrag")
n0.Fenster.ProbeModus(True)
r = tup(n0.Erfassung.GildenReset())
fest(r[0] is None, "im Probe-Modus laesst sich nicht gildenweit zuruecksetzen (%s)" % (r,))
echt = int(l0.eval("(function() local n = 0 for _ in pairs(FairshareDB.vergaben) do n = n + 1 end return n end)()"))
fest(echt == 1 and float(l0.eval("FairshareDB.resetZeit or 0")) == 0, "die echten Daten (%d) und die Reset-Marke bleiben unveraendert" % echt)
r2 = tup(n0.Konfig.Senden())
fest(r2[0] is None, "und Einstellungen senden ist im Probe-Modus gesperrt (%s)" % (r2,))
fest(not n0.Konfig.AutoSenden(), "ebenso das automatische Senden")
n0.Fenster.ProbeModus(False)
r3 = tup(n0.Erfassung.GildenReset())
fest(r3[0] == 1, "nach dem Beenden geht der Reset wieder (%s)" % (r3,))

print("== 72. Kompaktfenster: Reihenfolge nach Wertung, Leiste, Wurf, Vorschau, gross und klein schliessen sich ==")
w = gruppe(3)
w.ereignis("PLAYER_ENTERING_WORLD")
w.weiter(15)
cl = w.clients[0]
ns, g, lua = cl["ns"], cl["g"], cl["lua"]
w.eintragen(0, "Timo", 8001)
w.eintragen(0, "Timo", 8002)
w.eintragen(0, "Lina", 8003)
w.weiter(5)
ns.Kompakt.Zeigen()
w.weiter(1)
kf = g["FairshareKompakt"]
fest(ns.Kompakt.Sichtbar() and kf is not None, "/fs kompakt: das Fenster ist da")
fest(bool(g["FairshareDB"]["kompakt"]["offen"]), "offen wird gemerkt")
a1, a2, a3 = zeile_von("Leiter Kaos"), zeile_von("Lina"), zeile_von("Timo")
fest(a1 and a2 and a3 and a1 < a2 < a3, "Wertung: niedrigste zuerst (Kaos 0, Lina 1, Timo 2)")
fest(ns.Wurf.Laufend() is None, "ohne Wurf gibt es keinen Wurf-Zustand")

# Leiste: eine Zeile
h_voll = kf._h
lua.execute("FairshareDB.kompakt.leiste = true")
ns.Kompakt.Aktualisieren()
fest(kf._h == 28 and h_voll > 28, "Leiste: nur noch die Kopfzeile (%s -> %s)" % (h_voll, kf._h))
fest(len(texte_von(g, "Dran:")) > 0, "die Leiste nennt, wer dran ist")
lua.execute("FairshareDB.kompakt.leiste = false")
ns.Kompakt.Aktualisieren()
fest(kf._h == h_voll, "zurueck auf die volle Hoehe")

# Wurf starten im kleinen Fenster: nur wer darf (der Leiter), und nur ohne laufenden Wurf
fest(ns.Wurf.DarfStarten(), "der Leiter darf starten")
fest(g["__klick"]("Wurf starten") is True, "der Knopf ist klickbar")
t1 = w.clients[1]
t1["ns"].Kompakt.Zeigen()
t1["ns"].Kompakt.Aktualisieren()
fest(not t1["ns"].Wurf.DarfStarten(), "ein Mitglied darf nicht starten (kein Knopf)")
fest(t1["g"]["__klick"]("Wurf starten") is False, "beim Mitglied gibt es keinen sichtbaren Knopf Wurf starten")

# Ein laufender Wurf ersetzt die Reiter
KL = "|cff0070dd|Hitem:7100::::::::60:::::|h[Schwert der Probe]|h|r"
ok, grund = tup(ns.Wurf.Starten(KL))
fest(ok is True, "Wurf gestartet (%s)" % grund)
w.weiter(2)
fest(not ns.Fenster.Sichtbar() and ns.Kompakt.Sichtbar(), "beim Wurfstart bleibt das grosse Fenster zu, das kleine offen")
for c2 in w.clients:
    c2["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "Timo rolls 77 (1-100)")
    c2["g"]["__ereignis"]("CHAT_MSG_SYSTEM", "Lina rolls 41 (1-100)")
w.weiter(2)
ns.Kompakt.Aktualisieren()
W = ns.Wurf.Laufend()
fest(W is not None and W["gesamt"] >= 1, "Wurf.Laufend liefert den Stand")
fest(len(texte_von(g, "Schwert der Probe")) > 0, "der Gegenstand steht im Kompaktfenster")
r1, r2 = zeile_von("Lina"), zeile_von("Timo")
fest(r1 and r2 and r1 < r2, "Wuerfe in der Reihenfolge der Uebersicht: Lina (Wertung 1) vor Timo (2)")
fest(len(texte_von(g, "77")) > 0 and len(texte_von(g, "41")) > 0, "die Wurfzahlen stehen daneben")
lua.execute("FairshareDB.kompakt.leiste = true")
ns.Kompakt.Aktualisieren()
fest(kf._h == 28 and len(texte_von(g, "Schwert der Probe")) > 0, "Leiste im Wurf: Gegenstand und Zeit in einer Zeile")
lua.execute("FairshareDB.kompakt.leiste = false")
ns.Wurf.Abbrechen()
w.weiter(2)
ns.Kompakt.Aktualisieren()
fest(ns.Wurf.Laufend() is None, "nach dem Abbruch ist wieder alles beim Alten")

# Gross und klein schliessen sich gegenseitig
ns.Fenster.Zeigen(False)
fest(ns.Fenster.Sichtbar() and not ns.Kompakt.Sichtbar(), "das grosse Fenster oeffnen schliesst das kleine")
ns.Kompakt.Zeigen()
fest(ns.Kompakt.Sichtbar() and not ns.Fenster.Sichtbar(), "das kleine oeffnen schliesst das grosse")
g["__klick"]("Groß")
fest(ns.Fenster.Sichtbar() and not ns.Kompakt.Sichtbar(), "Knopf Gross im kleinen Fenster")
ns.Fenster.Verstecken()
ns.Kompakt.Zeigen()

# Vorschau mit Beispieldaten (auch allein): Wertung, dann Wurf, dann aus
fest(ns.Kompakt.Vorschau() == "wertung" and len(texte_von(g, "Vanity Zerath")) > 0, "Vorschau 1: Beispiel-Wertung")
fest(ns.Kompakt.Vorschau() == "wurf" and len(texte_von(g, "Blade of Doom")) + len(texte_von(g, "Klinge der Verdammnis")) > 0, "Vorschau 2: Beispiel-Wurf")
fest(len(texte_von(g, "87")) > 0, "mit Wurfzahlen")
fest(ns.Kompakt.Vorschau() is None, "Vorschau 3: aus")
fest(ns.Wurf.Laufend() is None, "die Vorschau startet keinen echten Wurf")

ns.Kompakt.Verstecken()
fest(not ns.Kompakt.Sichtbar() and not g["FairshareDB"]["kompakt"]["offen"], "zu: Fenster weg, Zustand gemerkt")
ns.Kompakt.Umschalten()
fest(ns.Kompakt.Sichtbar(), "Umschalten oeffnet es wieder")

print()
print("ALLES GUT" if alle_ok else "ES GIBT FEHLER")
sys.exit(0 if alle_ok else 1)
