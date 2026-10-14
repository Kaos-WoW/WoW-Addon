# -*- coding: utf-8 -*-
"""Fuehrt Kern.lua und Tests.lua in einem echten Lua 5.1 aus (lupa).

Voraussetzung: pip install lupa
Aufruf:        python tests/rechenkern.py
"""
import io
import os
import sys

from lupa import lua51

A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "LootHistorie")

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lade = lua.eval("function(code, name) return loadstring(code, name) end")
ns = lua.table()

for datei in ["Kern.lua", "Tests.lua"]:
    code = io.open(os.path.join(A, datei), encoding="utf-8").read()
    r = lade(code, "@" + datei)
    if isinstance(r, tuple):
        print("SYNTAXFEHLER in", datei, r[1])
        sys.exit(1)
    r("LootHistorie", ns)

gut, schlecht = ns.Tests.Alle(lua.eval("false"))
print("bestanden:", gut, " fehlgeschlagen:", schlecht)
sys.exit(0 if schlecht == 0 else 1)
