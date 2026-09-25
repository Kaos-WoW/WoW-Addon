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
    print("  " .. GELB .. "/lh auto|r   – Fenster bei Wurfbeginn automatisch öffnen (an/aus)")
    print("  " .. GELB .. "/lh import|r – Garguls bisherige Aufzeichnungen übernehmen")
    print("  " .. GELB .. "/lh filter|r – ab welcher Qualität mitgeschrieben wird")
    print("  " .. GELB .. "/lh stand|r  – Diagnose: eigene Historie und Mitschrift")
    print("  " .. GELB .. "/lh muster|r – Diagnose: Textvorlagen für eigene Erkennung")
    print("  " .. GELB .. "/lh test|r   – Selbsttests der Auswertung")
end

-- =====================================================================

befehle["import"] = function()
    local neu, doppelt = Quelle.GargulImport()
    if not neu then
        sag(ROT .. tostring(doppelt) .. "|r")
        return
    end
    sag(string.format("|cff55ff55%d Vergaben|r aus Gargul übernommen.", neu))
    if doppelt > 0 then
        print(string.format("  " .. GRAU .. "%d übersprungen – die hatte die Eigenerfassung schon.|r", doppelt))
    end
    print("  " .. GRAU .. "Wiederholtes Einführen ändert nichts mehr.|r")
end

befehle["filter"] = function(arg)
    local d = ns.Erfassung.Einstellungen()
    local stufe = tonumber(arg)
    if stufe and stufe >= 0 and stufe <= 5 then
        d.mindestQualitaet = stufe
    elseif arg == "raid" or arg == "instanz" or arg == "ueberall" or arg == "überall" then
        d.ort = (arg == "überall") and "ueberall" or arg
    elseif arg == "wurf" then
        d.nurGewuerfelt = not d.nurGewuerfelt
    elseif arg ~= "" then
        sag("Nutzung: " .. GELB .. "/lh filter 0-5|r (Qualität), " ..
            GELB .. "raid|instanz|überall|r (Ort) oder " .. GELB .. "wurf|r (nur Ausgewürfeltes)")
        return
    end

    local Namen = { [0]="Schlecht", [1]="Gewöhnlich", [2]="Ungewöhnlich",
                    [3]="Selten", [4]="Episch", [5]="Legendär" }
    local Orte = {
        raid     = "nur in Schlachtzugsinstanzen",
        instanz  = "in Instanzen, auch Fünfergruppen",
        ueberall = "überall",
    }
    sag(string.format("Erfasst ab |cffffff78%s|r, %s%s.",
        Namen[d.mindestQualitaet] or d.mindestQualitaet,
        Orte[d.ort] or d.ort,
        d.nurGewuerfelt and ", nur Ausgewürfeltes" or ""))
    if d.nurGewuerfelt then
        print("  " .. GRAU .. "⚠ Ohne Bedarfswurf zugeteilte Stücke fallen dabei heraus.|r")
    end
end

befehle["stand"] = function()
    local eigen = ns.Erfassung.Historie()
    local n = 0
    for _ in pairs(eigen) do n = n + 1 end
    local liste, gesamt = Kern.Bilanz(eigen, 0)
    sag(string.format("Eigene Historie: |cff55ff55%d Einträge|r, davon %d auswertbar an %d Spieler.",
        n, gesamt, #liste))

    local beute, wurf = ns.Erfassung.MusterBauen()
    print(string.format("  " .. GRAU .. "Mitschreiben: %d Beutemuster, Wurfmuster %s, %d Würfe gemerkt.|r",
        beute, wurf and "da" or "FEHLT", ns.Erfassung.OffeneWuerfe()))

    local ok, wert = Quelle.Stand()
    if not ok then
        print("  " .. GRAU .. tostring(wert) .. " – nichts zu übernehmen. Das Addon schreibt selbst mit.|r")
        return
    end
    sag(string.format("Garguls Historie liegt vor: |cff55ff55%d Einträge|r.", wert))

    print("  " .. GRAU .. "Das ist Garguls Bestand – " .. GELB .. "/lh import|r" ..
          GRAU .. " übernimmt ihn in die eigene Historie.|r")
end

--- Diagnose: welche Textvorlagen und Namens-APIs gibt es hier?
--  Gebraucht fuer die Frage, ob das Addon Wuerfe und Vergaben SELBST
--  erkennen kann, ohne Gargul. Die Vorlagen sind GlobalStrings — sie
--  stehen nicht im Quellbaum, nur zur Laufzeit.
befehle["muster"] = function()
    sag("Textvorlagen für eigene Erkennung:")
    for _, name in ipairs({
        "RANDOM_ROLL_RESULT",
        "LOOT_ITEM", "LOOT_ITEM_SELF",
        "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_SELF_MULTIPLE",
        "LOOT_ITEM_PUSHED", "LOOT_ITEM_PUSHED_SELF",
    }) do
        local wert = rawget(_G, name)
        if type(wert) == "string" then
            print(string.format("  |cff55ff55%s|r  %s", name, wert))
        else
            print(string.format("  " .. ROT .. "%s fehlt|r", name))
        end
    end

    sag("Namens-APIs (Nachnamen in Forever):")
    local NU = rawget(_G, "NameUtil")
    print("  NameUtil: " .. (NU and "|cff55ff55da|r" or ROT .. "fehlt|r"))
    if NU then
        for _, f in ipairs({ "FormatUnitNameForDisplay", "SplitPlayerNameIntoParts",
                             "GetFullNameWithoutRealm", "GetUnitFirstName" }) do
            print("    " .. f .. ": " .. (type(NU[f]) == "function" and "|cff55ff55da|r" or GRAU .. "fehlt|r"))
        end
    end

    local name, zweites = UnitName("player")
    print(string.format("  UnitName: |cffffff78%s|r  zweiter Wert: |cffffff78%s|r",
        tostring(name), tostring(zweites)))
    if GetUnitName then
        print(string.format("  GetUnitName(player, true): |cffffff78%s|r",
            tostring(GetUnitName("player", true))))
    end
end

befehle["auto"] = function()
    local an = Fenster.AutoUmschalten()
    if an then
        sag("Fenster öffnet sich automatisch, sobald ein Wurf startet.")
    else
        sag("Automatisches Öffnen aus. " .. GELB .. "/lh|r öffnet es von Hand.")
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
