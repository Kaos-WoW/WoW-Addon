# -*- coding: utf-8 -*-
"""
Rechenmodell zur Resurrected Loot-Ordnung.

Alle Zahlen, die im Regelwerk (loot-ordnung.html) stehen, stammen aus diesem
Skript. Wenn eine Stellschraube geaendert wird - Verfallsrate, Punkte je Boss,
Platzfaktoren, Deckel - hier neu rechnen und die Werte im Dokument nachziehen.

    python berechnungen.py

Modell
------
    Prio = Einsatz / Ruestwert

Pro Raidwoche: erst Verfall auf beide Groessen, dann Zuwachs.
Der Ruestwert faellt nie unter MIN_R.
"""

# ----------------------------------------------------------------- Parameter

VERFALL       = 0.10   # je Woche, auf Einsatz UND Ruestwert
EP_PRO_BOSS   = 5
BONUS_VOLL    = 10     # vom ersten bis zum letzten Kampf dabei
BOSSE         = 8      # Bosse an einem normalen Abend
MIN_R         = 100    # Mindest-Ruestwert (mit K zu eichen!)
BASIS         = 60.0   # Ruestwert eines Items vor Platzfaktor, bei aktueller ilvl

# Beispielspieler: mittlerer Stand, Prio 1,50
START_E, START_R = 600.0, 400.0

VOLLER_SATZ   = BOSSE * EP_PRO_BOSS + BONUS_VOLL   # 50
LOOT_PRO_WOCHE = 45.0   # Ruestwert-Zuwachs eines aktiven Raiders im Schnitt

PLATZFAKTOREN = [
    ("Zweihandwaffe",                                   3.0),
    ("Schmuckstueck",                                   2.0),
    ("Einhandwaffe, Schildhand, Distanzwaffe, Ruestung", 1.5),
    ("Hals, Umhang, Handgelenke, Ringe, Relikt",        1.0),
]

d = 1.0 - VERFALL


# ------------------------------------------------------------------ Modell

def woche(E, R, ep=0.0, rp=0.0):
    """Eine Raidwoche: Verfall auf beide Groessen, dann Zuwachs."""
    E = E * d + ep
    R = max(R * d, MIN_R) + rp
    return E, max(R, MIN_R)


def lauf(wochen, ep=0.0, rp=0.0, E=START_E, R=START_R):
    """Liefert die Prio nach jeder Woche."""
    out = []
    for _ in range(wochen):
        E, R = woche(E, R, ep, rp)
        out.append(E / R)
    return out


def gleichgewicht(ep, rp):
    """Wohin die Prio auf Dauer laeuft: Zuwachs = Verfall."""
    return (ep / VERFALL) / max(rp / VERFALL, MIN_R)


def erholung(faktor, E=START_E, R=START_R, ep=VOLLER_SATZ):
    """Prio direkt nach dem Erhalt und Wochen zurueck auf den Ausgangswert."""
    p0 = E / R
    R += BASIS * faktor
    p1 = E / R
    w = 0
    while E / R < p0 and w < 30:
        E, R = woche(E, R, ep)
        w += 1
    return p1, (p1 / p0 - 1) * 100.0, w


# ------------------------------------------------------------------ Ausgabe

def kopf(t):
    print("\n" + t)
    print("-" * len(t))


kopf("1. Abwesenheit - warum es einen Deckel braucht")
print("Wer abwesend ist, kann nichts bekommen: der Ruestwert steht still,")
print("waehrend der Einsatz weiterwaechst. Nichts bremst die Prio.\n")
print("%-22s %7s %7s %7s %7s   %s" % ("Abmelde-Punkte", "1 Wo.", "2 Wo.", "3 Wo.", "4 Wo.", "Dauerzustand"))
for name, ep in [("voller Satz (%g)" % VOLLER_SATZ, VOLLER_SATZ),
                 ("halber Satz (%g)" % (VOLLER_SATZ / 2), VOLLER_SATZ / 2),
                 ("Viertelsatz (%g)" % (VOLLER_SATZ / 4), VOLLER_SATZ / 4),
                 ("keine (0)", 0.0)]:
    p = lauf(4, ep)
    print("%-22s %7s %7s %7s %7s   %6.2f" % (
        name, *["%.2f" % v for v in p], gleichgewicht(ep, 0.0)))
print("\nEntschieden: halber Satz, gedeckelt auf 3 Raidtage in Folge (+15 %).")
print("Zum Vergleich - ein aktiver Raider mit Loot landet bei Prio %.2f." %
      gleichgewicht(VOLLER_SATZ, LOOT_PRO_WOCHE))

kopf("2. Fehlzeit ohne Abmelde-Punkte kostet nichts")
print("Der Verfall trifft Einsatz und Ruestwert gleichzeitig, das Verhaeltnis")
print("bleibt stehen. Das ist der Unterschied zu DKP.\n")
print("  abwesend, keine Punkte, nach 8 Wochen:  Prio %.2f  (Start %.2f)" %
      (lauf(8, 0.0)[-1], START_E / START_R))
print("  anwesend, Loot im Schnitt, nach 8 Wo.:  Prio %.2f" %
      (lauf(8, VOLLER_SATZ, LOOT_PRO_WOCHE)[-1]))
print("  anwesend, Pechstraehne ohne Loot:       Prio %.2f" % (lauf(8, VOLLER_SATZ)[-1]))
print("\nWer aussetzt, steht danach VOR dem, der da war und ein Item mitnahm.")

kopf("3. Was ein Platzfaktor praktisch kostet")
print("(ausgehend von Prio %.2f)\n" % (START_E / START_R))
print("%-52s %6s %9s %8s" % ("Platz", "Faktor", "Prio neu", "zurueck"))
for name, f in PLATZFAKTOREN:
    p1, delta, w = erholung(f)
    print("%-52s %6.1f %9.2f %5d Wo.  (%+.0f %%)" % (name, f, p1, w, delta))
print("\nWaffen: 2x 1,5 = 3,0 - eine Zweihandwaffe kostet genau so viel wie")
print("zwei Einhandplaetze. Zwei Schmuckstuecke summieren sich auf 4,0.")

kopf("4. Selbstregulierung - zwei Spieler ueber acht Wochen")
print("Grundlage des Diagramms in Paragraf 4 des Regelwerks.\n")
E1, R1 = START_E, START_R
E2, R2 = 520.0, 250.0
print("%-6s %18s %18s" % ("Woche", "Kaosx", "Jaergerlie"))
for w in range(1, 9):
    # wer die hoehere Prio hat, bekommt das Item dieser Woche
    nimmt1 = (E1 / R1) >= (E2 / R2)
    E1, R1 = woche(E1, R1, VOLLER_SATZ, BASIS * 1.5 if nimmt1 else 0.0)
    E2, R2 = woche(E2, R2, VOLLER_SATZ, 0.0 if nimmt1 else BASIS * 1.5)
    print("%-6d %12.2f %s %12.2f %s" % (
        w, E1 / R1, "<-" if nimmt1 else "  ", E2 / R2, "  " if nimmt1 else "<-"))
print("\n(<- = hat in dieser Woche das Item bekommen)")
print("Beide pendeln um denselben Wert, ohne dass jemand entscheiden muss.")
print()
