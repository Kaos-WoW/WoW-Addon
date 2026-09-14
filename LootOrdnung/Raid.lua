--[[----------------------------------------------------------------------
    Raid.lua  —  Den Raidabend erfassen

    Sammelt waehrend des Abends nur mit; geschrieben wird erst am Ende
    ueber /lo abend jetzt. Das entspricht dem Rhythmus aus AGENTS.md:
    Vergaben sofort, Einsatz gesammelt.

    ⚠️ Der Abend liegt in den SavedVariables und ueberlebt /reload und
    Disconnect — aber nicht den Absturz vor dem naechsten Ausloggen,
    weil WoW SavedVariables erst dann auf die Platte schreibt.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Raid = {}
ns.Raid = Raid

local Kern = ns.Kern

-- =====================================================================
--  Abend
-- =====================================================================

local function db()
    LootOrdnungDB = LootOrdnungDB or {}
    return LootOrdnungDB
end

--- Der laufende Abend, oder ein frischer.
function Raid.Abend(neu)
    local d = db()
    if neu or not d.abend then
        d.abend = {
            start     = time(),
            bosse     = 0,
            namen     = {},   -- name -> Anzahl Bosskaempfe
            gesehen   = {},   -- encounterID -> true, gegen Doppelzaehlung
            protokoll = {},   -- Liste der Bossnamen in Reihenfolge
        }
    end
    return d.abend
end

function Raid.AbendVerwerfen()
    db().abend = nil
end

-- =====================================================================
--  Teilnehmer
-- =====================================================================

--- Wer steht gerade in der Gruppe? Voller Name inklusive Realm, damit
--  der Schluessel zum Gildenroster passt.
function Raid.Anwesende()
    local liste = {}
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0

    if IsInRaid and IsInRaid() then
        for i = 1, n do
            local name = GetRaidRosterInfo(i)
            if name then liste[#liste + 1] = name end
        end
    elseif n > 0 then
        liste[#liste + 1] = UnitName("player")
        for i = 1, n - 1 do
            local name = UnitName("party" .. i)
            if name then liste[#liste + 1] = name end
        end
    else
        liste[#liste + 1] = UnitName("player")
    end

    return liste
end

--- Namen wie im Gildenroster schreiben (mit Realm), damit beide Seiten
--  denselben Schluessel benutzen.
local function vollerName(name)
    if name:find("%-") then return name end
    local realm = GetRealmName and GetRealmName() or ""
    realm = realm:gsub("%s+", "")
    if realm == "" then return name end
    return name .. "-" .. realm
end

-- =====================================================================
--  Bosskaempfe
-- =====================================================================

--- Bucht einen Bosskampf fuer alle gerade Anwesenden.
--  @param bezeichnung  Name des Bosses, nur fuers Protokoll
--  @param kennung      encounterID; verhindert Doppelzaehlung bei Wipes
--  @return true und die Anzahl Teilnehmer, oder false und ein Grund
function Raid.BossBuchen(bezeichnung, kennung)
    local abend = Raid.Abend()

    -- ⚠️ Mehrere Versuche an demselben Boss zaehlen EINMAL. Sonst
    -- braechte ein Progress-Abend mit zehn Wipes das Zehnfache.
    if kennung and abend.gesehen[kennung] then
        return false, "schon gezaehlt"
    end
    if kennung then abend.gesehen[kennung] = true end

    local anwesende = Raid.Anwesende()
    abend.bosse = abend.bosse + 1
    abend.protokoll[#abend.protokoll + 1] = bezeichnung or ("Boss " .. abend.bosse)

    for _, name in ipairs(anwesende) do
        local schluessel = vollerName(name)
        abend.namen[schluessel] = (abend.namen[schluessel] or 0) + 1
    end

    return true, #anwesende
end

-- =====================================================================
--  Auswertung
-- =====================================================================

--- Was der Abend jedem einbringt.
--  @return Liste aus { name, kurz, bosse, vollDabei, einsatz }, sortiert
function Raid.Auswertung()
    local abend = Raid.Abend()
    local liste = {}

    for name, anzahl in pairs(abend.namen) do
        local vollDabei = (anzahl >= abend.bosse and abend.bosse > 0)
        liste[#liste + 1] = {
            name      = name,
            kurz      = name:match("^([^%-]+)") or name,
            bosse     = anzahl,
            vollDabei = vollDabei,
            einsatz   = Kern.EinsatzFuerTeilnahme(anzahl, vollDabei),
        }
    end

    table.sort(liste, function(a, b)
        if a.bosse ~= b.bosse then return a.bosse > b.bosse end
        return a.kurz < b.kurz
    end)
    return liste
end

--- Schreibt den Abend in die Konten.
--  ⚠️ Nur Teilnehmer, nicht die ganze Gilde: Wer nicht dabei war,
--  aendert sich allein durch Verfall, und der wird beim naechsten Lesen
--  ueber den Wochenstempel nachgeholt.
--  @return Anzahl gebuchter Spieler, Liste der nicht gefundenen
function Raid.Buchen(beiFertig)
    local woche = Kern.WocheAus(time())
    local auswertung = Raid.Auswertung()

    -- Gildeneintraege einmal einsammeln, damit wir GUIDs haben
    local nachName = {}
    for _, e in ipairs((ns.Gilde.Lesen())) do
        nachName[e.name] = e
    end

    local auftraege, fehlend = {}, {}
    for _, a in ipairs(auswertung) do
        local e = nachName[a.name]
        if e and e.konto then
            Kern.VerfallNachholen(e.konto, woche)
            Kern.TeilnahmeBuchen(e.konto, a.bosse, a.vollDabei)
            auftraege[#auftraege + 1] = { guid = e.guid, konto = e.konto }
        else
            fehlend[#fehlend + 1] = a.kurz
        end
    end

    local n = ns.Gilde.SchreibenViele(auftraege, beiFertig)
    return n, fehlend
end

-- =====================================================================
--  Automatik
-- =====================================================================

local rahmen = CreateFrame("Frame")

-- ENCOUNTER_END gibt es nicht in jedem Client; die Registrierung darf
-- deshalb nicht hart scheitern.
pcall(function() rahmen:RegisterEvent("ENCOUNTER_END") end)
pcall(function() rahmen:RegisterEvent("BOSS_KILL") end)

rahmen:SetScript("OnEvent", function(_, ereignis, a1, a2)
    if not (db().automatik) then return end

    if ereignis == "ENCOUNTER_END" then
        -- a1 = encounterID, a2 = encounterName
        local ok, anzahl = Raid.BossBuchen(a2, a1)
        if ok then
            print(string.format("|cff1B6B57Loot-Ordnung|r: %s gebucht (%d Teilnehmer).",
                tostring(a2), anzahl))
        end
    elseif ereignis == "BOSS_KILL" then
        local ok, anzahl = Raid.BossBuchen(a2, a1)
        if ok then
            print(string.format("|cff1B6B57Loot-Ordnung|r: %s gebucht (%d Teilnehmer).",
                tostring(a2), anzahl))
        end
    end
end)

function Raid.AutomatikUmschalten()
    local d = db()
    d.automatik = not d.automatik
    return d.automatik
end

function Raid.AutomatikAn()
    return db().automatik and true or false
end
