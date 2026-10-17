# -*- coding: utf-8 -*-
"""
Prueft die Uebersetzung:

  1. Jeder Schluessel, der im Code als L["..."] steht, hat eine englische
     Uebersetzung in Locale.lua (sonst saehe ein englischer Client Deutsch).
  2. Jede Uebersetzung wird irgendwo benutzt (keine Altlasten).
  3. Platzhalter (%d, %s, %1$s) stimmen zwischen Schluessel und Uebersetzung
     ueberein.
  4. Eine Liste der verbliebenen Zeichenketten, die nach deutschem Text
     aussehen und NICHT durch L[] laufen. Mit --streng wird die Liste zum
     Fehler.

Aufruf:  python tests/texte.py [--streng] [--liste]
"""
import io
import sys
sys.stdout.reconfigure(encoding="utf-8")
import os
import re
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
QUELLE = os.path.join(HIER, "..", "Fairshare")

# Dateien, deren Texte nicht uebersetzt werden (Entwicklerwerkzeug)
# Kern.lua: reine Rechnerei, die Gruende (z. B. "entzaubert") sind intern.
AUSNAHMEN = {"Tests.lua", "Locale.lua", "Kern.lua"}

# Zeichenketten, die bewusst nicht uebersetzt werden: Befehlsworte,
# interne Gruende, Beispieldaten, Entwicklerdiagnose.
ERLAUBT = {
    "überall", "löschen", "zurück", "wiedereröffnen", " · Forever",
    "kein Bedarfswurf", "kein Schlachtzug", "keine Instanz", "Qualität zu niedrig",
    "unvollständig", "ohne Gegenstand", "schon gewürfelt", "übernehmen",
    "Järgerlie", "Zorn des Verräters", "Fairshare äöü",
    "keine Seite", "alle",
    "  %s  |cff8E9A94(%s, %s)|r",
}
ERLAUBT_TEIL = ("GetUnitName(player", "Karte %d:", "Zeile %d:")

LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def lies(name):
    return io.open(os.path.join(QUELLE, name), encoding="utf-8").read()


def ohne_kommentare(zeile):
    """Entfernt -- Kommentare, beachtet Zeichenketten grob."""
    aus, i, in_str = [], 0, False
    while i < len(zeile):
        c = zeile[i]
        if in_str:
            aus.append(c)
            if c == "\\":
                i += 1
                if i < len(zeile):
                    aus.append(zeile[i])
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
                aus.append(c)
            elif zeile.startswith("--", i):
                break
            else:
                aus.append(c)
        i += 1
    return "".join(aus)


def codezeilen(text):
    """Liefert (nr, zeile) ohne Kommentare, auch ohne --[[ ... ]]-Bloecke."""
    aus, im_block = [], False
    for nr, z in enumerate(text.split("\n"), 1):
        if im_block:
            if "]]" in z:
                im_block = False
            continue
        if z.lstrip().startswith("--[["):
            if "]]" not in z:
                im_block = True
            continue
        aus.append((nr, ohne_kommentare(z)))
    return aus


def schluessel_im_code():
    """Alle L["..."] im Quelltext -> {text: [(datei, zeile)]}"""
    ergebnis = {}
    for name in sorted(os.listdir(QUELLE)):
        if not name.endswith(".lua") or name == "Locale.lua":
            continue
        for nr, z in codezeilen(lies(name)):
            for m in re.finditer(r'\bL\[("(?:[^"\\\n]|\\.)*")\]', z):
                k = m.group(1)[1:-1]
                ergebnis.setdefault(k, []).append((name, nr))
    return ergebnis


def uebersetzungen():
    """Locale.lua: EN["..."] = "..." oder ["..."] = "..." -> {de: en}"""
    pfad = os.path.join(QUELLE, "Locale.lua")
    if not os.path.exists(pfad):
        return {}
    text = lies("Locale.lua")
    ergebnis = {}
    for m in re.finditer(r'^\s*\[("(?:[^"\\\n]|\\.)*")\]\s*=\s*("(?:[^"\\\n]|\\.)*")\s*,?\s*$',
                         text, re.M):
        ergebnis[m.group(1)[1:-1]] = m.group(2)[1:-1]
    return ergebnis


def platzhalter(s):
    # ⚠️ Reihenfolge, nicht Menge: Lua kennt kein %2$d, eine vertauschte Uebersetzung
    # liefe auf einem englischen Client in einen Fehler.
    return re.findall(r"%(?:\d+\$)?[sd]", s)


DEUTSCH = re.compile(
    r"[äöüßÄÖÜ]|\b(?:der|die|das|und|nicht|kein|keine|wird|werden|für|mit|ohne|ist|sind|"
    r"Du|Dein|deiner|eine|einen|oder|beim|bei|noch|nur|alle|dein)\b"
)


def verbleibend():
    """Zeichenketten, die nach Deutsch aussehen und nicht in L[] stehen."""
    liste = []
    for name in sorted(os.listdir(QUELLE)):
        if not name.endswith(".lua") or name in AUSNAHMEN:
            continue
        for nr, z in codezeilen(lies(name)):
            # L["..."] herausnehmen
            rest = re.sub(r'\bL\[("(?:[^"\\\n]|\\.)*")\]', "", z)
            for m in LIT.finditer(rest):
                t = m.group(1)
                if len(t) < 4 or t in ERLAUBT or t.strip().startswith(ERLAUBT_TEIL):
                    continue
                if re.fullmatch(r"[\w%.:;,|\-\\/ ]*", t) and not DEUTSCH.search(t):
                    continue
                if DEUTSCH.search(t) or " " in t.strip():
                    liste.append((name, nr, t))
    return liste


def main():
    streng = "--streng" in sys.argv
    zeige = "--liste" in sys.argv

    code = schluessel_im_code()
    uebs = uebersetzungen()
    fehler = 0

    fehlend = [k for k in code if k not in uebs]
    for k in sorted(fehlend):
        d, n = code[k][0]
        print("FEHLT EN:  %s:%d  %s" % (d, n, k))
        fehler += 1

    ungenutzt = [k for k in uebs if k not in code]
    for k in sorted(ungenutzt):
        print("UNGENUTZT: %s" % k)
        fehler += 1

    for k, v in sorted(uebs.items()):
        if k in code and platzhalter(k) != platzhalter(v):
            print("PLATZHALTER: %s  ->  %s" % (k, v))
            fehler += 1

    rest = verbleibend()
    if zeige or streng:
        for d, n, t in rest:
            print("OHNE L[]:  %s:%d  %s" % (d, n, t[:90]))
    if streng:
        fehler += len(rest)

    print("%d Schluessel im Code, %d Uebersetzungen, %d Zeichenketten ohne L[]%s"
          % (len(code), len(uebs), len(rest), "" if (zeige or streng) else " (--liste zeigt sie)"))
    print("ALLES GUT" if fehler == 0 else "ES GIBT FEHLER (%d)" % fehler)
    sys.exit(0 if fehler == 0 else 1)


if __name__ == "__main__":
    main()
