# -*- coding: utf-8 -*-
"""Grobe Strukturpruefung fuer Lua-Dateien.

Kein Ersatz fuer einen Interpreter - findet aber unbalancierte Bloecke
und Klammern, also die Fehler, die eine Datei komplett unbrauchbar machen.
"""
import io, re, sys

BLOCK_AUF = re.compile(r"\b(function|if|for|while|do|repeat)\b")
BLOCK_ZU = re.compile(r"\b(end|until)\b")
# 'for ... do' und 'while ... do' oeffnen nur EINEN Block, zaehlen aber zweimal
DOPPELT = re.compile(r"\b(for|while)\b[^\n]*?\bdo\b")
# 'elseif ... then' ist kein neuer Block
ELSEIF = re.compile(r"\belseif\b")


def entkleide(src):
    """Kommentare und Strings entfernen, damit sie nicht mitzaehlen."""
    src = re.sub(r"--\[\[.*?\]\]", " ", src, flags=re.S)
    src = re.sub(r"--[^\n]*", " ", src)
    src = re.sub(r'"[^"\n]*"', '""', src)
    src = re.sub(r"'[^'\n]*'", "''", src)
    return src


def pruefe(datei):
    roh = io.open(datei, encoding="utf-8").read()
    src = entkleide(roh)

    auf = len(BLOCK_AUF.findall(src)) - len(DOPPELT.findall(src))
    zu = len(BLOCK_ZU.findall(src))
    runde = src.count("(") - src.count(")")
    geschweift = src.count("{") - src.count("}")
    eckig = src.count("[") - src.count("]")

    fehler = []
    if auf != zu:
        fehler.append("Bloecke: %d geoeffnet, %d geschlossen" % (auf, zu))
    if runde:
        fehler.append("runde Klammern %+d" % runde)
    if geschweift:
        fehler.append("geschweifte Klammern %+d" % geschweift)
    if eckig:
        fehler.append("eckige Klammern %+d" % eckig)

    # BOM waere fatal - WoW verschluckt sich daran
    if roh.startswith("﻿"):
        fehler.append("BOM am Dateianfang")

    status = "OK" if not fehler else "PROBLEM"
    print("%-14s %-8s %s" % (datei, status, "; ".join(fehler)))
    return not fehler


if __name__ == "__main__":
    alles_gut = True
    for f in sys.argv[1:]:
        alles_gut = pruefe(f) and alles_gut
    sys.exit(0 if alles_gut else 1)
