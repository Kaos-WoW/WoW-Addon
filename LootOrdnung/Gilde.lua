--[[----------------------------------------------------------------------
    Gilde.lua  —  Konten aus der Offiziersnotiz lesen und zurueckschreiben

    Hier liegt die einzige Verbindung zwischen Rechenkern und Client.
    Der Server synchronisiert die Notizen von selbst, deshalb braucht es
    kein eigenes Sync-Protokoll und keine Absprache zwischen den
    Raidleitern der einzelnen Gruppen.

    Gemessen am Anniversary-Client (13.09.2026):
      * die alten Globals GuildRosterSetOfficerNote und CanEditOfficerNote
        sind nil — alles liegt in C_GuildInfo
      * gelesen wird weiter ueber GetGuildRosterInfo / GetNumGuildMembers
      * SetNote nimmt eine GUID, keinen Roster-Index
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Gilde = {}
ns.Gilde = Gilde

local Kern, Notiz = ns.Kern, ns.Notiz

Gilde.SCHREIBPAUSE = 0.35   -- Sekunden zwischen zwei Schreibvorgaengen

-- =====================================================================
--  Client-Zugriff, versionsbewusst
-- =====================================================================

local function gildenAPI()
    return rawget(_G, "C_GuildInfo")
end

--- Roster beim Server anfordern. Die Antwort kommt asynchron als
--  GUILD_ROSTER_UPDATE — nicht pollen, sonst liest man einen veralteten
--  Stand und schreibt ihn zurueck.
function Gilde.RosterAnfordern()
    local G = gildenAPI()
    if G and G.GuildRoster then
        G.GuildRoster()
    elseif rawget(_G, "GuildRoster") then
        GuildRoster()
    end
end

function Gilde.DarfLesen()
    local G = gildenAPI()
    if G and G.CanViewOfficerNote then return G.CanViewOfficerNote() and true or false end
    return nil   -- unbekannt, nicht false
end

function Gilde.DarfSchreiben()
    local G = gildenAPI()
    if G and G.CanEditOfficerNote then return G.CanEditOfficerNote() and true or false end
    return nil
end

local function notizSetzen(guid, text)
    local G = gildenAPI()
    if G and G.SetNote then
        G.SetNote(guid, text, false)   -- false = Offiziersnotiz
        return true
    end
    return false
end

-- =====================================================================
--  Lesen
-- =====================================================================

--- Liest alle Mitglieder samt Konto.
--  @return eintraege  Liste aus { name, kurz, guid, rang, rangIndex,
--                                 notiz, konto, grund }
--          fremd      Liste der Namen mit nicht-eigenem Notizinhalt
function Gilde.Lesen()
    local eintraege, fremd = {}, {}
    local anzahl = GetNumGuildMembers and GetNumGuildMembers() or 0

    for i = 1, anzahl do
        local name, rang, rangIndex, _, _, _, _, offiziersnotiz,
              _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)

        if name then
            local konto, grund = Notiz.Lesen(offiziersnotiz)
            local eintrag = {
                name      = name,
                kurz      = name:match("^([^%-]+)") or name,
                guid      = guid,
                rang      = rang,
                rangIndex = rangIndex,
                notiz     = offiziersnotiz or "",
                konto     = konto,
                grund     = grund,
            }
            eintraege[#eintraege + 1] = eintrag
            if Notiz.IstFremd(offiziersnotiz) then
                fremd[#fremd + 1] = eintrag
            end
        end
    end

    return eintraege, fremd
end

--- Konten als Tabelle name -> konto, mit nachgeholtem Verfall.
--  @param woche  aktuelle fortlaufende Wochennummer
function Gilde.Konten(woche)
    local konten = {}
    for _, e in ipairs((Gilde.Lesen())) do
        if e.konto then
            if woche then Kern.VerfallNachholen(e.konto, woche) end
            e.konto.guid = e.guid
            konten[e.name] = e.konto
        end
    end
    return konten
end

-- =====================================================================
--  Sicherung
-- =====================================================================

--- Sichert alle vorhandenen Notizen, bevor je etwas ueberschrieben wird.
--  Kostet nichts und macht Eintraege wiederherstellbar, die jemand von
--  Hand gepflegt hat — bei Resurrected standen dort Dinge wie
--  "von Patric".
function Gilde.Sichern()
    LootOrdnungDB = LootOrdnungDB or {}
    if LootOrdnungDB.sicherung then
        return false, LootOrdnungDB.sicherung.zeit
    end

    local kopie, anzahl = {}, 0
    for _, e in ipairs((Gilde.Lesen())) do
        if e.notiz ~= "" then
            kopie[e.name] = e.notiz
            anzahl = anzahl + 1
        end
    end

    LootOrdnungDB.sicherung = { zeit = time(), notizen = kopie, anzahl = anzahl }
    return true, nil, anzahl
end

-- =====================================================================
--  Schreiben
-- =====================================================================

local warteschlange, laeuft = {}, false

local function naechsterSchreibvorgang()
    local auftrag = table.remove(warteschlange, 1)
    if not auftrag then
        laeuft = false
        if Gilde.beiFertig then
            local fn = Gilde.beiFertig
            Gilde.beiFertig = nil
            fn()
        end
        return
    end

    notizSetzen(auftrag.guid, auftrag.text)
    C_Timer.After(Gilde.SCHREIBPAUSE, naechsterSchreibvorgang)
end

--- Stellt ein Konto zum Schreiben in die Warteschlange.
--  Gedrosselt, weil zwanzig Aufrufe in einem Frame der Server nicht
--  freundlich quittiert.
--  @return true, oder false und ein Grund
function Gilde.Schreiben(guid, konto)
    if not guid then return false, "keine GUID" end
    if Gilde.DarfSchreiben() == false then return false, "kein Schreibrecht" end

    local text, grund = Notiz.Schreiben(konto)
    if not text then return false, grund end

    warteschlange[#warteschlange + 1] = { guid = guid, text = text }
    if not laeuft then
        laeuft = true
        C_Timer.After(0, naechsterSchreibvorgang)
    end
    return true
end

--- Schreibt mehrere Konten.
--  ⚠️ Nur Raidteilnehmer uebergeben, nicht die ganze Gilde: Wer nicht
--  dabei war, aendert sich ausschliesslich durch Verfall — und der wird
--  beim naechsten Lesen ueber den Wochenstempel nachgeholt.
--  @param aenderungen  Liste aus { guid=, konto= }
function Gilde.SchreibenViele(aenderungen, beiFertig)
    local n, fehler = 0, {}
    Gilde.beiFertig = beiFertig
    for _, a in ipairs(aenderungen) do
        local ok, grund = Gilde.Schreiben(a.guid, a.konto)
        if ok then n = n + 1 else fehler[#fehler + 1] = grund end
    end
    return n, fehler
end

function Gilde.Wartend()
    return #warteschlange
end

-- =====================================================================
--  Ereignisse
-- =====================================================================

local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("ADDON_LOADED")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:RegisterEvent("GUILD_ROSTER_UPDATE")

rahmen:SetScript("OnEvent", function(_, ereignis, arg1)
    if ereignis == "ADDON_LOADED" and arg1 == ADDON then
        LootOrdnungDB = LootOrdnungDB or {}
    elseif ereignis == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, Gilde.RosterAnfordern)
    elseif ereignis == "GUILD_ROSTER_UPDATE" then
        Gilde.rosterGeladen = true
    end
end)
