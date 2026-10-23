--[[----------------------------------------------------------------------
    Blizzbeute.lua  —  Blizzards eigenes Würfelfenster auslesen

    ⭐ **Die beste Quelle, die es gibt.** Der Mainline-Client fuehrt selbst
    Buch ueber Gruppenbeute: `C_LootHistory` kennt je Gegenstand den
    Gewinner, alle Wuerfe und — entscheidend — die **Bedarfsart**:

        Enum.EncounterLootDropRollState
          NeedMainSpec = 0   NeedOffSpec = 1   Transmog = 2
          Greed        = 3   NoRoll      = 4   Pass     = 5

    Damit braucht es weder eine Wuerfel-Absprache (`/rnd 100` gegen `/rnd 50`)
    noch das Zerlegen von Chattexten. Und die Namen kommen aus der API —
    das umgeht die Nachnamen-Falle in Forever vollstaendig.

    ⚠️ Deckt nur ab, was ueber Blizzards Wuerfelfenster laeuft. Zuteilungen
    per Meisterpluenderer oder Freie-Beute bleiben Sache der Chat-Mitschrift
    in Erfassung.lua. Beide Wege schreiben in dieselbe Historie; die
    Dublettenpruefung dort verhindert doppelte Zeilen.

    ⚠️ Gibt es nicht in jeder Client-Fassung. Alles feature-geprueft.
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Blizzbeute = {}
ns.Blizzbeute = Blizzbeute

local Kern = ns.Kern

local PRAEFIX = "|cff1B6B57KaosLoot|r: "

-- =====================================================================
--  Verfuegbarkeit
-- =====================================================================

--- Kann dieser Client Blizzards Beute-Historie?
--  @return true, oder false und ein Grund
function Blizzbeute.Verfuegbar()
    local LH = rawget(_G, "C_LootHistory")
    if type(LH) ~= "table" then
        return false, L["C_LootHistory gibt es hier nicht"]
    end
    if type(LH.GetSortedInfoForDrop) ~= "function" then
        return false, L["C_LootHistory ist zu alt"]
    end
    return true
end

--- Uebersetzt Blizzards Wurfzustand in unsere Bedarfsart.
--  ⚠️ Transmog und Gier sind kein Hauptbedarf — sie kosten den Anspruch
--  nicht. Pass und NoRoll gewinnen nichts und tauchen hier nie als
--  Gewinner auf.
--  @return "haupt", "zweit" oder nil
function Blizzbeute.Bedarfsart(zustand)
    local E = rawget(_G, "Enum")
    local Z = E and E.EncounterLootDropRollState
    if not Z then return nil end

    if zustand == Z.NeedMainSpec then return "haupt" end
    if zustand == Z.NeedOffSpec then return "zweit" end
    if zustand == Z.Greed       then return "zweit" end
    if zustand == Z.Transmog    then return "zweit" end
    return nil
end

-- =====================================================================
--  Auslesen
-- =====================================================================

--- Wertet einen einzelnen Gegenstand aus.
--  @return true, wenn eine Vergabe eingetragen wurde
function Blizzbeute.Gegenstand(encounterID, lootListKey)
    if not Blizzbeute.Verfuegbar() then return false end

    local ok, Drop = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, lootListKey)
    if not ok or type(Drop) ~= "table" then return false end

    -- Wuerfe laufen noch: nur die Ansicht auffrischen, nichts eintragen.
    local Gewinner = Drop.winner
    if type(Gewinner) ~= "table" or not Gewinner.playerName then
        Blizzbeute.WuerfeMerken(Drop)
        return false
    end

    local art = Blizzbeute.Bedarfsart(Gewinner.state)
    local zeit = (GetServerTime and GetServerTime()) or time()

    -- ⚠️ Der Schluessel muss bei allen Beteiligten gleich herauskommen,
    -- sonst haelt ein spaeterer Abgleich dieselbe Vergabe fuer zwei.
    -- Begegnung und Beuteplatz leisten das; die Zeit taete es nicht.
    local kennung = string.format("blizz:%s:%s", tostring(encounterID), tostring(lootListKey))

    local ok = ns.Erfassung.Eintragen(Gewinner.playerName, Drop.itemHyperlink, zeit, art, kennung)
    ns.Erfassung.RundeBeenden(Drop.itemHyperlink)   -- vergeben: die Wurfanzeige endet
    return ok
end

--- Merkt sich die laufenden Wuerfe fuer die Anzeige.
function Blizzbeute.WuerfeMerken(Drop)
    if type(Drop) ~= "table" or type(Drop.rollInfos) ~= "table" then return 0 end

    local n = 0
    for _, W in ipairs(Drop.rollInfos) do
        if W.playerName then
            local art = Blizzbeute.Bedarfsart(W.state)
            if art then
                ns.Erfassung.WurfMerken(W.playerName, W.roll, nil, nil, art, Drop.itemHyperlink)
                n = n + 1
            end
        end
    end
    return n
end

--- Holt alles nach, was gerade offen ist.
--  Nuetzlich nach einem /reload mitten im Raid.
function Blizzbeute.Nachholen()
    if not Blizzbeute.Verfuegbar() then return 0 end

    local ok, Infos = pcall(C_LootHistory.GetAllEncounterInfos)
    if not ok or type(Infos) ~= "table" then return 0 end

    local n = 0
    for _, Begegnung in ipairs(Infos) do
        local id = Begegnung.encounterID
        local ok2, Drops = pcall(C_LootHistory.GetSortedDropsForEncounter, id)
        if ok2 and type(Drops) == "table" then
            for _, D in ipairs(Drops) do
                if Blizzbeute.Gegenstand(id, D.lootListKey) then n = n + 1 end
            end
        end
    end
    return n
end

-- =====================================================================
--  Ereignisse
-- =====================================================================

local rahmen = CreateFrame("Frame")
pcall(function() rahmen:RegisterEvent("LOOT_HISTORY_UPDATE_DROP") end)
pcall(function() rahmen:RegisterEvent("LOOT_HISTORY_UPDATE_ENCOUNTER") end)

rahmen:SetScript("OnEvent", function(_, ereignis, a1, a2)
    -- Ohne Plündermeister als Beutemethode ruht das Addon (Rolle.Aktiv).
    if not (ns.Rolle and ns.Rolle.Aktiv()) then return end
    local ok, fehler = pcall(function()
        if ereignis == "LOOT_HISTORY_UPDATE_DROP" then
            -- a1 encounterID, a2 lootListKey
            Blizzbeute.Gegenstand(a1, a2)
        else
            -- Eine ganze Begegnung hat sich geaendert
            local ok2, Drops = pcall(C_LootHistory.GetSortedDropsForEncounter, a1)
            if ok2 and type(Drops) == "table" then
                for _, D in ipairs(Drops) do Blizzbeute.Gegenstand(a1, D.lootListKey) end
            end
        end
    end)
    if not ok then
        print(PRAEFIX .. "|cffff5555" .. string.format(L["Fehler beim Lesen der Beute-Historie: %s"], tostring(fehler)) .. "|r")
    end
end)

return ns
