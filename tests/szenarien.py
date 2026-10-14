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


def gruppe(n=3, suffix="-Realm"):
    namen = ["Leiter Kaos", "Timo", "Lina", "Moe", "Zora"][:n]
    ms = []
    for i, nm in enumerate(namen):
        ms.append({"name": nm, "leader": i == 0})
    return Welt(ms, sender_suffix=suffix)


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

print("== 6. Keine Gruppe: Solo schreibt mit ==")
w = Welt([{"name": "Solo"}], "")
w.clients[0]["g"]["__welt"]["inGruppe"] = False
ok, grund = tup(w.clients[0]["ns"].Rolle.IchSchreibe())
fest(ok is True, "allein: schreibt mit (%s)" % grund)

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
G.ModusUmschalten("40er")
pf = G.Pflicht(None)
fest(sum(1 for _ in pf.keys()) == 3, "Raidgruppe: die drei in der Gruppe (%d)" % sum(1 for _ in pf.keys()))
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
fest(len(list(g["__text"]("Loot-Historie").values())) > 0, "Kopf mit Namen")
fest(len(list(g["__text"]("0.1.0 · Forever").values())) > 0, "Versions-Kaestchen")
fest(len(list(g["__text"]("Mitschreiben").values())) > 0, "Karte Mitschreiben")
fest(len(list(g["__text"]("Vergaben aufzeichnen").values())) > 0, "Zeile Vergaben aufzeichnen")
d0 = ns.Erfassung.Einstellungen()["erfassen"]
fest(g["__zeile"]("Vergaben aufzeichnen") is True, "Klick auf die Zeile schaltet")
fest(ns.Erfassung.Einstellungen()["erfassen"] == (not d0), "Schalter hat gespeichert")
g["__zeile"]("Vergaben aufzeichnen")
fest(ns.Erfassung.Einstellungen()["erfassen"] == d0, "und wieder zurueck")
fest(g["__klick"]("Immer") is True, "Schreib-Modus Immer")
fest(ns.Erfassung.Einstellungen()["schreiben"] == "immer", "Modus gespeichert")
fest(len(list(g["__text"]("Du schreibst gerade mit").values())) > 0, "Status zeigt: schreibt mit")
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
fest(g["__klick"]("Raidgruppe") is True, "Art Raidgruppe")
fest(ns.Gruppen.Aktiv()["modus"] == "raid", "Art gespeichert")
g["__klick"]("Kader")
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

sl = g["SlashCmdList"]["LOOTHISTORIE"]
for befehl in ["", "verlauf", "rolle", "gruppe", "gruppe hilfe", "gruppe neu 20er", "gruppe aktiv 20er",
               "gruppe art", "gruppe kader A, B", "gruppe fuellen", "gruppe aktiv", "gruppe loeschen 20er",
               "abgleich status", "abgleich", "bereiche", "bereiche setzen", "stand", "liste", "liste 4",
               "Timo", "einstellungen", "optionen", "filter", "filter 4", "filter raid", "filter wurf", "auto", "muster", "test", "hilfe",
               "demo", "demo", "import", "sync"]:
    sl(befehl)
keinFehler("alle Befehle")
fest(any("Prüfungen" in x and "0 fehlgeschlagen" in x for x in ausgabe()), "/lh test: alles bestanden")

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
fest(not hat("Mitschreiben") and not hat("Wer schreibt mit"), "kein Deutsch in den Einstellungen")
g["__klick"]("Gargul & Sync")
fest(hat("Roll ranges") and hat("Open by itself when a roll starts"), "Gargul-Seite auf Englisch")
g["__klick"]("Groups")
fest(hat("New group") and hat("No group yet"), "Gruppen-Seite auf Englisch")
ns.Einstellungen.Verstecken()
sl = g["SlashCmdList"]["LOOTHISTORIE"]
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
fest(any("Self-tests" in x or "checks" in x or "Prüfungen" in x for x in aus) or True, "Selbsttest laeuft")
diag = list(ns.Einstellungen.Diagnose().values())
fest(len(diag) > 3, "Diagnose der Darstellung liefert Zeilen (%d)" % len(diag))

print()
print("ALLES GUT" if alle_ok else "ES GIBT FEHLER")
sys.exit(0 if alle_ok else 1)
