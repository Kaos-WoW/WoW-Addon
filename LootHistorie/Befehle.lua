--[[----------------------------------------------------------------------
    Befehle.lua  —  /lh

    ⭐ **Kein Befehl darf still scheitern.** WoW verschluckt Laufzeitfehler
    in Addons, solange scriptErrors aus ist — und das ist die
    Voreinstellung. Der Befehl tut dann scheinbar ueberhaupt nichts, und
    man sucht an der falschen Stelle. Darum laeuft jeder Unterbefehl
    ueber pcall und die Meldung landet im Chat.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Kern, Quelle, Fenster = ns.Kern, ns.Quelle, ns.Fenster

local PRAEFIX = "|cff1B6B57Loot-Historie|r: "
local GELB = "|cffffff78"
local GRAU = "|cff8E9A94"
local ROT  = "|cffff5555"

local function sag(text) print(PRAEFIX .. text) end

local befehle = {}

local function hilfe()
    sag("Befehle:")
    print("  " .. GELB .. "/lh|r        – Fenster öffnen und schließen")
    print("  " .. GELB .. "/lh demo|r   – Fenster mit Beispieldaten (nichts wird gespeichert)")
    print("  " .. GELB .. "/lh liste|r  – dieselbe Auswertung im Chat, " .. GELB .. "liste 4|r für 4 Wochen")
    print("  " .. GELB .. "/lh <Name>|r – Einzelvergaben eines Spielers im Chat")
    print("  " .. GELB .. "/lh stand|r  – Diagnose: liegt Garguls Historie vor")
    print("  " .. GELB .. "/lh test|r   – Selbsttests der Auswertung")
end

-- =====================================================================

befehle["stand"] = function()
    local ok, wert = Quelle.Stand()
    if not ok then
        sag(ROT .. tostring(wert) .. "|r")
        print("  " .. GRAU .. "Ohne Gargul gibt es nichts zu lesen. " .. GELB .. "/lh demo|r " ..
              GRAU .. "zeigt die Anzeige mit Beispieldaten.|r")
        return
    end
    sag(string.format("Garguls Historie liegt vor: |cff55ff55%d Einträge|r.", wert))

    local H = Quelle.Gargul()
    local liste, gesamt = Kern.Bilanz(H, 0)
    print(string.format("  " .. GRAU .. "Davon auswertbar: %d Vergaben an %d Spieler.|r",
        gesamt, #liste))
    if wert > gesamt then
        print(string.format("  " .. GRAU .. "%d fallen heraus – entzaubert, Bonus-Beute oder unvollständig.|r",
            wert - gesamt))
    end
end

befehle["demo"] = function()
    Fenster.Zeigen(true)
end

befehle["test"] = function()
    if ns.Tests and ns.Tests.Alle then ns.Tests.Alle() else sag("Keine Tests geladen.") end
end

befehle["liste"] = function(arg)
    local wochen = tonumber(arg) or 0
    local H, grund = Quelle.Gargul()
    if not H then sag(ROT .. tostring(grund) .. "|r") return end

    local seit = Kern.Seit(time(), wochen)
    local liste, gesamt, aeltester = Kern.Bilanz(H, seit)

    if #liste == 0 then sag("Keine Vergabe im Zeitraum.") return end

    sag(string.format("%s: |cff55ff55%d Vergaben|r an %d Spieler, %d Raidtage",
        wochen > 0 and (wochen .. " Wochen") or "Gesamte Historie",
        gesamt, #liste, Kern.Raidtage(H, seit, Quelle.Tag)))
    if aeltester then
        print("  " .. GRAU .. "Älteste Aufzeichnung: " .. date("%d.%m.%Y", aeltester) .. "|r")
    end

    for i, z in ipairs(liste) do
        if i > 30 then
            print("  " .. GRAU .. "… und " .. (#liste - 30) .. " weitere|r")
            break
        end
        local seitText = ""
        if z.letzte > 0 then
            seitText = string.format("  " .. GRAU .. "vor %d Tagen|r",
                math.floor((time() - z.letzte) / Kern.TAG))
        end
        print(string.format("  %-14s " .. GELB .. "%2d|r Haupt%s%s", z.name, z.haupt,
            z.zweit > 0 and string.format("  " .. GRAU .. "%d Zweit|r", z.zweit) or "        ",
            seitText))
    end
end

--- Einzelner Spieler, sonst Hilfe.
local function spielerOderHilfe(name)
    local H, grund = Quelle.Gargul()
    if not H then sag(ROT .. tostring(grund) .. "|r") return end

    local liste = Kern.Spieler(H, name, 0)
    if #liste == 0 then
        sag(string.format("Für " .. GELB .. "%s|r ist keine Vergabe verzeichnet.", name))
        return
    end

    local haupt = 0
    for _, e in ipairs(liste) do if not e.zweit then haupt = haupt + 1 end end
    sag(string.format("%s: |cff55ff55%d Vergaben|r, davon %d Hauptbedarf",
        Kern.Anzeigename(name), #liste, haupt))

    for i, e in ipairs(liste) do
        if i > 25 then
            print("  " .. GRAU .. "… und " .. (#liste - 25) .. " weitere|r")
            break
        end
        print(string.format("  %s  %s%s", date("%d.%m.%y", e.zeit),
            Quelle.Gegenstandstext(e.eintrag),
            e.zweit and ("  " .. GRAU .. "Zweitbedarf|r") or ""))
    end
end

-- =====================================================================

SLASH_LOOTHISTORIE1 = "/lh"
SLASH_LOOTHISTORIE2 = "/loothistorie"
SlashCmdList["LOOTHISTORIE"] = function(eingabe)
    local wort, rest = (eingabe or ""):match("^%s*(%S*)%s*(.-)%s*$")
    wort = wort or ""

    local fn = befehle[wort:lower()]
    local ok, fehler

    if wort == "" then
        ok, fehler = pcall(Fenster.Umschalten, false)
    elseif fn then
        ok, fehler = pcall(fn, (rest or ""))
    elseif wort:lower() == "hilfe" or wort == "?" then
        ok, fehler = pcall(hilfe)
    else
        -- Alles andere wird als Spielername verstanden
        ok, fehler = pcall(spielerOderHilfe, wort)
    end

    if not ok then
        print(PRAEFIX .. ROT .. "Fehler in /lh " .. wort .. "|r")
        print(ROT .. tostring(fehler) .. "|r")
        print(GRAU .. "Bitte diese zwei Zeilen weitergeben.|r")
    end
end

-- Eine Zeile beim Laden, damit man sieht, dass es da ist.
local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(4, function()
        local ok, anzahl = Quelle.Stand()
        if ok then
            sag(string.format("%d Vergaben aufgezeichnet. " .. GELB .. "/lh|r öffnet die Übersicht.", anzahl))
        else
            sag(GRAU .. tostring(anzahl) .. " – " .. GELB .. "/lh demo|r" .. GRAU .. " zeigt die Anzeige trotzdem.|r")
        end
    end)
end)

ns.geladen = true

return ns
