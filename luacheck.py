# -*- coding: utf-8 -*-
"""Blockpruefung mit echtem Tokenizer.

Der alte luacheck.py zaehlte Schluesselwoerter mit regulaeren Ausdruecken
und uebersah dabei alles, was in Zeichenketten oder Kommentaren steht.
Hier wird richtig zerlegt: lange Klammern, Escapes, Kommentare.
"""
import io, sys, re

WORT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def tokens(s):
    """Liefert (zeile, wort) fuer jedes Schluesselwort ausserhalb von
    Zeichenketten und Kommentaren."""
    i, n, zeile = 0, len(s), 1
    raus = []
    while i < n:
        c = s[i]
        if c == "\n":
            zeile += 1; i += 1; continue

        # Kommentar
        if s.startswith("--", i):
            i += 2
            lang = re.match(r"\[(=*)\[", s[i:])
            if lang:
                ende = "]" + lang.group(1) + "]"
                j = s.find(ende, i)
                if j < 0: return raus, ("offener Langkommentar", zeile)
                zeile += s.count("\n", i, j); i = j + len(ende)
            else:
                j = s.find("\n", i)
                i = n if j < 0 else j
            continue

        # Lange Zeichenkette
        lang = re.match(r"\[(=*)\[", s[i:])
        if lang:
            ende = "]" + lang.group(1) + "]"
            j = s.find(ende, i)
            if j < 0: return raus, ("offene lange Zeichenkette", zeile)
            zeile += s.count("\n", i, j); i = j + len(ende)
            continue

        # Normale Zeichenkette
        if c in "\"'":
            i += 1
            while i < n and s[i] != c:
                if s[i] == "\\": i += 1
                elif s[i] == "\n": return raus, ("Zeilenumbruch in Zeichenkette", zeile)
                i += 1
            if i >= n: return raus, ("offene Zeichenkette", zeile)
            i += 1
            continue

        m = WORT.match(s, i)
        if m:
            raus.append((zeile, m.group(0)))
            i = m.end()
            continue

        i += 1
    return raus, None


OEFFNER = {"function", "if", "for", "while", "do", "repeat"}


def pruefe(pfad):
    s = io.open(pfad, encoding="utf-8").read()
    if s.startswith("\ufeff"):
        return "BOM am Dateianfang"

    toks, fehler = tokens(s)
    if fehler:
        return "%s (Zeile %d)" % fehler

    stapel = []          # (art, zeile)
    warte_do = False     # for/while offen, 'do' steht noch aus
    for zeile, w in toks:
        if w in ("for", "while"):
            stapel.append(("schleife", zeile)); warte_do = True
        elif w == "do":
            if warte_do: warte_do = False
            else: stapel.append(("do", zeile))
        elif w == "function":
            stapel.append(("function", zeile))
        elif w == "if":
            stapel.append(("if", zeile))
        elif w == "repeat":
            stapel.append(("repeat", zeile))
        elif w in ("else", "elseif"):
            if not stapel or stapel[-1][0] != "if":
                return "'%s' ohne passendes if (Zeile %d)" % (w, zeile)
        elif w == "end":
            if not stapel:
                return "'end' zu viel (Zeile %d)" % zeile
            if stapel[-1][0] == "repeat":
                return "'end' schliesst ein repeat (Zeile %d)" % zeile
            stapel.pop()
        elif w == "until":
            if not stapel or stapel[-1][0] != "repeat":
                return "'until' ohne repeat (Zeile %d)" % zeile
            stapel.pop()

    if stapel:
        art, zeile = stapel[-1]
        return "%d Block(e) offen, zuletzt '%s' ab Zeile %d" % (len(stapel), art, zeile)

    for auf, zu, name in (("(", ")", "Klammern"), ("{", "}", "geschweifte")):
        pass
    return None


schlecht = 0
for f in sys.argv[1:]:
    p = pruefe(f)
    if p:
        print("%s  FEHLER: %s" % (f, p)); schlecht += 1
    else:
        print("%s  OK" % f)
sys.exit(1 if schlecht else 0)
