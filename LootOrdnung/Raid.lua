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
            protokoll = {},   -- bossNr -> Name
            teilnahme = {},   -- bossNr -> { name -> true }
            kennungen = {},   -- encounterID -> bossNr
            versuche  = {},   -- bossNr -> Anzahl Anlaeufe
            erfolg    = {},   -- bossNr -> true, sobald gelegt
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

--- Wer steht gerade in der Gruppe?
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
--  Wann darf automatisch gebucht werden
-- =====================================================================

local function gildenanteil()
    local anwesende = Raid.Anwesende()
    local gilde = {}
    for _, e in ipairs((ns.Gilde.Lesen())) do
        gilde[e.name] = true
    end

    local drin = 0
    for _, name in ipairs(anwesende) do
        if gilde[vollerName(name)] then drin = drin + 1 end
    end
    return drin, #anwesende
end

--- Ist das hier ein Gildenraid?
--  Zwei Bedingungen, damit weder beim Questen noch im Pug gebucht wird:
--  eine Raidinstanz UND mehr als die Haelfte der Gruppe aus der Gilde.
function Raid.IstGildenraid()
    local _, typ = IsInInstance()
    if typ ~= "raid" then return false, "keine Raidinstanz" end
    if not (IsInRaid and IsInRaid()) then return false, "keine Schlachtzugsgruppe" end

    local drin, gesamt = gildenanteil()
    if gesamt == 0 then return false, "keine Gruppe" end
    if drin * 2 <= gesamt then
        return false, string.format("nur %d von %d aus der Gilde", drin, gesamt)
    end
    return true, drin, gesamt
end

-- =====================================================================
--  Bosskaempfe
-- =====================================================================

--- Bucht einen Bosskampf.
--
--  Paragraf 2: "Je Bosskampf, an dem du teilnimmst — auch bei Wipes."
--  Jeder gepullte Boss zaehlt also, ob er faellt oder nicht.
--
--  ⚠️ Drei Dinge, die leicht durcheinandergehen:
--  1. **Pro Boss, nicht pro Versuch.** Zehn Anlaeufe an einem
--     Progress-Boss zaehlen einmal — sonst braechte ein Wipe-Abend mehr
--     als eine ganze Farmwoche. Steht so noch nicht im Regelwerk.
--  2. **Teilnehmer ueber ALLE Anlaeufe vereinigt.** Wer erst nach dem
--     zweiten Wipe nachrueckt und den Kill mitmacht, bekommt den Boss
--     angerechnet; sonst entschiede allein der erste Pull.
--  3. **Einmal gelegt bleibt gelegt** — ein spaeterer Anlauf macht aus
--     einem Kill keinen Wipe. Der Erfolg dient nur der Anzeige, auf den
--     Einsatz wirkt er nicht.
--
--  @param bezeichnung  Name des Bosses, nur fuers Protokoll
--  @param kennung      encounterID; ohne sie zaehlt jeder Aufruf neu
--  @param erfolg       true, wenn der Boss gefallen ist
--  @return true, Zahl (Teilnehmer bzw. neu hinzugekommene), bossNr, schonDa
--- Sucht einen schon gebuchten Boss anhand des Namens.
--  Noetig fuer /lo boss von Hand: Ohne encounterID zaehlte sonst jeder
--  Aufruf als neuer Boss, und ein automatisch erfasster Kampf waere beim
--  Nachbuchen doppelt gelandet.
function Raid.BossNachName(bezeichnung)
    if not bezeichnung or bezeichnung == "" then return nil end
    local abend = Raid.Abend()
    local suche = bezeichnung:lower()
    for nr = 1, abend.bosse do
        local vorhanden = (abend.protokoll[nr] or ""):lower()
        if vorhanden ~= "" then
            if vorhanden == suche
               or vorhanden:find(suche, 1, true)
               or suche:find(vorhanden, 1, true) then
                return nr
            end
        end
    end
end

function Raid.BossBuchen(bezeichnung, kennung, erfolg)
    local abend = Raid.Abend()
    local nr = kennung and abend.kennungen[kennung]
    -- Ohne Kennung ueber den Namen suchen, damit /lo boss nicht doppelt zaehlt
    if not nr then nr = Raid.BossNachName(bezeichnung) end
    local schonDa = nr ~= nil

    if not nr then
        abend.bosse = abend.bosse + 1
        nr = abend.bosse
        abend.protokoll[nr] = bezeichnung or ("Boss " .. nr)
        abend.teilnahme[nr] = {}
        abend.versuche[nr]  = 0
        if kennung then abend.kennungen[kennung] = nr end
    end

    abend.versuche[nr] = (abend.versuche[nr] or 0) + 1
    if erfolg then abend.erfolg[nr] = true end

    local menge = abend.teilnahme[nr]
    local anwesende = Raid.Anwesende()
    local neu = 0
    for _, name in ipairs(anwesende) do
        local schluessel = vollerName(name)
        if not menge[schluessel] then
            menge[schluessel] = true
            neu = neu + 1
        end
    end

    return true, (schonDa and neu or #anwesende), nr, schonDa
end

--- Wie viele Bosse fielen, wie viele stehen noch.
function Raid.Bilanz()
    local abend = Raid.Abend()
    local gelegt, offen = 0, 0
    for nr = 1, abend.bosse do
        if abend.erfolg[nr] then gelegt = gelegt + 1 else offen = offen + 1 end
    end
    return gelegt, offen
end

--- Einheitliche Meldung fuer gebuchte Kaempfe.
function Raid.Melden(ok, zahl, nr, schonDa)
    if not ok or not nr then return end
    local abend = Raid.Abend()
    local name     = tostring(abend.protokoll[nr])
    local stand    = abend.erfolg[nr] and "|cff55ff55gelegt|r" or "|cffffff78steht noch|r"
    local anlaeufe = abend.versuche[nr] or 1

    if schonDa then
        local zusatz = (zahl > 0) and string.format(", %d neue Teilnehmer", zahl) or ""
        print(string.format("|cff1B6B57Loot-Ordnung|r: %s, %d. Anlauf – %s|cff8E9A94%s. Zählt nicht doppelt.|r",
            name, anlaeufe, stand, zusatz))
    else
        print(string.format("|cff1B6B57Loot-Ordnung|r: %s gebucht – %s |cff8E9A94(%d Teilnehmer, Boss %d).|r",
            name, stand, zahl, nr))
    end
end

-- =====================================================================
--  Auswertung
-- =====================================================================

--- Was der Abend jedem einbringt.
function Raid.Auswertung()
    local abend = Raid.Abend()
    local liste, zaehler = {}, {}

    for nr = 1, abend.bosse do
        for name in pairs(abend.teilnahme[nr] or {}) do
            zaehler[name] = (zaehler[name] or 0) + 1
        end
    end

    for name, anzahl in pairs(zaehler) do
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
function Raid.Buchen(beiFertig)
    local woche = Kern.WocheAus(time())
    local auswertung = Raid.Auswertung()

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

-- Nicht jeder Client kennt beide Ereignisse; die Registrierung darf
-- deshalb nicht hart scheitern.
pcall(function() rahmen:RegisterEvent("ENCOUNTER_END") end)
pcall(function() rahmen:RegisterEvent("BOSS_KILL") end)

rahmen:SetScript("OnEvent", function(_, ereignis, a1, a2, a3, a4, a5)
    if not (db().automatik) then return end

    local erlaubt, grund = Raid.IstGildenraid()
    if not erlaubt then
        print(string.format("|cff1B6B57Loot-Ordnung|r: |cff8E9A94nicht gebucht (%s). Von Hand: /lo boss|r",
            tostring(grund)))
        return
    end

    if ereignis == "ENCOUNTER_END" then
        -- a1 encounterID, a2 Name, a3 Schwierigkeit, a4 Gruppe, a5 Erfolg
        Raid.Melden(Raid.BossBuchen(a2, a1, a5 == 1 or a5 == true))
    elseif ereignis == "BOSS_KILL" then
        Raid.Melden(Raid.BossBuchen(a2, a1, true))
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
