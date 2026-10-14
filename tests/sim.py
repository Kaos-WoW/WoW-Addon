# -*- coding: utf-8 -*-
"""
Simulation des Abgleichs: mehrere virtuelle Clients, je ein eigener Lua-5.1-Zustand,
ein gemeinsamer Nachrichtenkanal und eine gemeinsame Uhr.

Geladen wird in TOC-Reihenfolge: Kern, Quelle, Rolle, Gruppen, Erfassung, Abgleich.
Fenster/Einstellungen/Befehle werden nicht geladen (sie brauchen echte Frames).
"""
import io
import os
import sys

from lupa import lua51

A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "LootHistorie")
DATEIEN = ["Kern.lua", "Locale.lua", "Quelle.lua", "Rolle.lua", "Gruppen.lua", "Erfassung.lua", "Abgleich.lua",
          "Blizzbeute.lua", "Stil.lua", "Einstellungen.lua", "Fenster.lua", "Befehle.lua", "Tests.lua"]

STUBS = r'''
local welt = __welt

local function mock()
    local o = { _scripts = {}, _events = {}, _text = "", _enabled = true, _shown = true, _checked = false }
    return setmetatable(o, { __index = function(t, k)
        -- Wie im echten Client: nur API-Methoden (GrossBuchstabe) gibt es, unbekannte Felder sind nil.
        if type(k) ~= "string" or not k:find("^%u") then return nil end
        if k == "SetScript" then return function(self, n, f) self._scripts[n] = f end end
        if k == "GetScript" then return function(self, n) return self._scripts[n] end end
        if k == "RegisterEvent" then return function(self, e) self._events[e] = true end end
        if k == "SetText" then return function(self, x) self._text = x end end
        if k == "GetText" then return function(self) return self._text end end
        if k == "SetEnabled" then return function(self, x) self._enabled = x and true or false end end
        if k == "IsEnabled" then return function(self) return self._enabled end end
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "SetShown" then return function(self, x) self._shown = x and true or false end end
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "SetChecked" then return function(self, x) self._checked = x and true or false end end
        if k == "GetChecked" then return function(self) return self._checked end end
        if k == "CreateFontString" or k == "CreateTexture" then
            return function(self, ...)
                local f = mock()
                f._eltern = self
                __frames[#__frames + 1] = f
                return f
            end
        end
        if k == "GetFont" then return function() return nil end end
        if k == "GetTextColor" then return function() return 1, 1, 1, 1 end end
        if k == "GetEffectiveAlpha" then return function() return 1 end end
        if k == "IsVisible" then return function(self) return self._shown ~= false end end
        if k == "GetStringWidth" then return function(self) return #tostring(self._text or "") * 7 end end
        if k == "GetStringHeight" then
            return function(self)
                local n = #tostring(self._text or "")
                if n == 0 then return 0 end
                return 14 * (1 + math.floor(n * 7 / (self._w or 500)))
            end
        end
        if k == "SetWidth" then return function(self, w) self._w = w end end
        if k == "SetHeight" then return function(self, h) self._h = h end end
        if k == "SetSize" then return function(self, w, h) self._w = w; self._h = h end end
        if k == "GetWidth" then return function(self) return self._w or 100 end end
        if k == "SetFrameLevel" then return function(self, n) self._level = n end end
        if k == "GetFrameLevel" then return function(self) return self._level or 5 end end
        if k == "SetFrameStrata" then return function(self, n) self._strata = n end end
        if k == "GetFrameStrata" then return function(self) return self._strata or "MEDIUM" end end
        if k == "GetLeft" then return function(self) return 100 end end
        if k == "GetTop" then return function(self) return 500 end end
        if k == "GetHeight" then return function(self) return self._h or 20 end end
        if k == "GetVerticalScrollRange" then return function() return 0 end end
        if k == "GetVerticalScroll" then return function() return 0 end end
        if k == "IsMouseOver" then return function() return true end end
        if k == "GetHighlightTexture" then return function(self) return self end end
        return function(self, ...) return self end
    end })
end

-- Knopf anhand seines Textes suchen und anklicken
__klick = function(text)
    for _, f in ipairs(__frames) do
        local t = f._text
        if type(t) == "string" then
            t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if t == text then
                -- Der Text steht entweder am Knopf selbst oder in einem Kind-Textfeld.
                local k = f
                if not k._scripts.OnClick and f._eltern then k = f._eltern end
                if k._scripts.OnClick and k._enabled and k._shown ~= false then
                    k._scripts.OnClick(k)
                    return true
                end
            end
        end
    end
    return false
end

-- Zeile anklicken, deren Beschriftung 'text' ist (Schalter-Zeilen: Klick auf die ganze Zeile)
__zeile = function(text)
    for _, f in ipairs(__frames) do
        if f._text == text and f._eltern and f._eltern._scripts.OnMouseUp then
            f._eltern._scripts.OnMouseUp(f._eltern, "LeftButton")
            return true
        end
    end
    return false
end

__text = function(teil)
    local gefunden = {}
    for _, f in ipairs(__frames) do
        local t = f._text
        if type(t) == "string" and t ~= "" and t:find(teil, 1, true) then
            gefunden[#gefunden + 1] = t
        end
    end
    return gefunden
end

__sichtbar = function(text)
    for _, f in ipairs(__frames) do
        local t = f._text
        if type(t) == "string" then
            t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if t == text then return f._shown and true or false end
        end
    end
    return nil
end
SlashCmdList = {}
GetAddOnMetadata = function() return "0.1.0" end
__ausgabe = {}
print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    __ausgabe[#__ausgabe + 1] = table.concat(t, " ")
end

__frames = {}
function CreateFrame(typ, name, ...)
    local f = mock()
    __frames[#__frames + 1] = f
    if type(name) == "string" then _G[name] = f end
    return f
end
UIParent = mock()
UISpecialFrames = {}
tinsert = table.insert
UNKNOWN = "Unbekannt"

date = os.date
time = function() return __jetzt() end
GetServerTime = time
InCombatLockdown = function() return false end

local function einheit(unit)
    if unit == "player" then return welt.members[welt.me] end
    local n = tonumber(unit:match("^party(%d)$"))
    if n then
        local k = 0
        for i, m in ipairs(welt.members) do
            if i ~= welt.me then
                k = k + 1
                if k == n then return m end
            end
        end
    end
end

UnitExists = function(u) return einheit(u) ~= nil end
GetUnitName = function(u) local m = einheit(u); return m and m.name end
UnitName = GetUnitName
UnitIsUnit = function(a, b) local x = einheit(a); return x ~= nil and x == einheit(b) end
UnitIsGroupLeader = function(u) local m = einheit(u); return m and m.leader and true or false end
UnitIsGroupAssistant = function(u) local m = einheit(u); return m and m.assist and true or false end
UnitIsInMyGuild = function(u) local m = einheit(u); return m ~= nil and m.gilde ~= false end
IsInRaid = function() return false end
IsInGroup = function() return welt.inGruppe ~= false end
GetNumGroupMembers = function() return #welt.members end
GetLootMethod = function()
    if welt.ml then
        if welt.ml == welt.me then return "master", 0 end
        local k = 0
        for i = 1, #welt.members do
            if i ~= welt.me then
                k = k + 1
                if i == welt.ml then return "master", k end
            end
        end
    end
    return "group"
end
IsMasterLooter = function() return welt.ml == welt.me end
IsInInstance = function() return true, "raid" end

GetLocale = function() return __locale or "deDE" end
C_Timer = { After = function(d, fn) __nachher(d, fn) end }
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(praefix, text, kanal) return __senden(praefix, text, kanal) end,
}

__pump = function(dt)
    for _, f in ipairs(__frames) do
        local h = f._scripts.OnUpdate
        if h then h(f, dt) end
    end
end

__liefern = function(praefix, text, kanal, sender)
    for _, f in ipairs(__frames) do
        if f._events.CHAT_MSG_ADDON and f._scripts.OnEvent then
            f._scripts.OnEvent(f, "CHAT_MSG_ADDON", praefix, text, kanal, sender)
        end
    end
end

__ereignis = function(name, ...)
    for _, f in ipairs(__frames) do
        if f._events[name] and f._scripts.OnEvent then
            f._scripts.OnEvent(f, name, ...)
        end
    end
end
'''


class Welt:
    def __init__(self, mitglieder, sender_suffix="", ml=None, locale="deDE"):
        self.ml = ml
        self.locale = locale
        """mitglieder: Liste von dicts {name, leader, assist, gilde, addon}"""
        self.t = 1700000000.0
        self.zeitgeber = []   # (faellig, nr, client, fn)
        self.nr = 0
        self.mitglieder = mitglieder
        self.sender_suffix = sender_suffix
        self.protokoll = []   # (von, text)
        self.clients = []
        for i, m in enumerate(mitglieder):
            self.clients.append(self._baue(i))

    def _baue(self, idx):
        m = self.mitglieder[idx]
        lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        g = lua.globals()

        welt = lua.table()
        mem = lua.table()
        for j, x in enumerate(self.mitglieder):
            t = lua.table()
            t["name"] = x["name"]
            t["leader"] = x.get("leader", False)
            t["assist"] = x.get("assist", False)
            t["gilde"] = x.get("gilde", True)
            mem[j + 1] = t
        welt["members"] = mem
        welt["me"] = idx + 1
        if self.ml is not None:
            welt["ml"] = self.ml + 1
        g["__welt"] = welt
        g["__locale"] = self.locale

        g["__jetzt"] = lambda: int(self.t)
        g["__nachher"] = lambda d, fn, c=idx: self._nachher(c, d, fn)
        g["__senden"] = lambda praefix, text, kanal, c=idx: self._senden(c, praefix, text, kanal)

        lua.execute(STUBS)

        lade = lua.eval("function(code, name) return loadstring(code, name) end")
        ns = lua.table()
        for datei in DATEIEN:
            code = io.open(os.path.join(A, datei), encoding="utf-8").read()
            r = lade(code, "@" + datei)
            if isinstance(r, tuple):
                raise RuntimeError("Syntaxfehler %s: %s" % (datei, r[1]))
            r("LootHistorie", ns)
        return {"lua": lua, "ns": ns, "g": g, "name": m["name"], "idx": idx}

    # --- Uhr -------------------------------------------------------------
    def _nachher(self, c, d, fn):
        self.nr += 1
        self.zeitgeber.append((self.t + float(d), self.nr, c, fn))

    def _senden(self, c, praefix, text, kanal):
        if len(text) > 255:
            raise RuntimeError("Nachricht zu lang: %d" % len(text))
        absender = self.mitglieder[c]["name"] + self.sender_suffix
        self.protokoll.append((self.mitglieder[c]["name"], text))
        for k, cl in enumerate(self.clients):
            if k == c:
                # auch die eigene Nachricht kommt zurueck, wie im Spiel
                pass
            if self.mitglieder[k].get("addon", True):
                cl["g"]["__liefern"](praefix, text, kanal, absender)
        return 0

    def weiter(self, sekunden, schritt=0.1):
        ende = self.t + sekunden
        while self.t < ende:
            self.t += schritt
            faellig = sorted([z for z in self.zeitgeber if z[0] <= self.t])
            self.zeitgeber = [z for z in self.zeitgeber if z[0] > self.t]
            for _, _, c, fn in faellig:
                fn()
            for k, cl in enumerate(self.clients):
                if self.mitglieder[k].get("addon", True):
                    cl["g"]["__pump"](schritt)

    # --- Hilfen ----------------------------------------------------------
    def ereignis(self, name):
        for k, cl in enumerate(self.clients):
            if self.mitglieder[k].get("addon", True):
                cl["g"]["__ereignis"](name)

    def hist(self, k):
        cl = self.clients[k]
        return cl["ns"].Erfassung.Historie()

    def stand(self, k):
        cl = self.clients[k]
        n, summe = cl["ns"].Abgleich.Stand()
        return n, summe

    def setze(self, k, id, eintrag):
        """Schreibt direkt in die Historie (Lua-Tabelle, nicht Python-dict)."""
        self.hist(k)[id] = self.clients[k]["lua"].table_from(eintrag)

    def ids(self, k):
        return sorted(str(i) for i in self.hist(k).keys())

    def eintragen(self, k, name, itemid, zeit=None, art=None, kennung=None):
        cl = self.clients[k]
        link = "|cff0070dd|Hitem:%d::::::::60:::::|h[Ding %d]|h|r" % (itemid, itemid)
        return cl["ns"].Erfassung.Eintragen(name, link, zeit or int(self.t), art, kennung)


def pruefe(bed, text):
    print(("  ok    " if bed else "  FEHLT ") + text)
    return bool(bed)
