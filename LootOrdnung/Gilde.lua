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

--- Stellt rohen Text zum Schreiben in die Warteschlange.
--  Gedrosselt, weil zwanzig Aufrufe in einem Frame der Server nicht
--  freundlich quittiert.
--  @return true, oder false und ein Grund
function Gilde.TextSchreiben(guid, text)
    if not guid then return false, "keine GUID" end
    if Gilde.DarfSchreiben() == false then return false, "kein Schreibrecht" end

    warteschlange[#warteschlange + 1] = { guid = guid, text = text or "" }
    if not laeuft then
        laeuft = true
        C_Timer.After(0, naechsterSchreibvorgang)
    end
    return true
end

--- Stellt ein Konto zum Schreiben in die Warteschlange.
function Gilde.Schreiben(guid, konto)
    local text, grund = Notiz.Schreiben(konto)
    if not text then return false, grund end
    return Gilde.TextSchreiben(guid, text)
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
--  Rangauswahl
-- =====================================================================

--  Welche Gildenraenge am System teilnehmen. Ein blosser Schwellenwert
--  reicht nicht: Offizierstwinks tragen einen hohen Rang, wuerden also
--  bei "alle bis Index 3" mitgezogen. Deshalb eine echte Auswahl.
--
--  ⚠️ Liegt in den SavedVariables und ist damit PRO RAIDLEITER. Bei
--  mehreren Raidgruppen muss jeder sie einmal setzen. Das ist
--  Konfiguration, keine Kontodaten — die stehen weiter in der Notiz.

function Gilde.Rangauswahl()
    LootOrdnungDB = LootOrdnungDB or {}
    LootOrdnungDB.raenge = LootOrdnungDB.raenge or {}
    return LootOrdnungDB.raenge
end

function Gilde.RangAktiv(index)
    return Gilde.Rangauswahl()[index] == true
end

--- Schaltet einen Rang um. @return neuer Zustand
function Gilde.RangUmschalten(index)
    local auswahl = Gilde.Rangauswahl()
    if auswahl[index] then
        auswahl[index] = nil
    else
        auswahl[index] = true
    end
    return auswahl[index] == true
end

function Gilde.AnzahlGewaehlt()
    local n = 0
    for _, an in pairs(Gilde.Rangauswahl()) do
        if an then n = n + 1 end
    end
    return n
end

--- Alle Mitglieder der gewaehlten Raenge.
function Gilde.Teilnehmer()
    local liste = {}
    for _, e in ipairs((Gilde.Lesen())) do
        if Gilde.RangAktiv(e.rangIndex) then
            liste[#liste + 1] = e
        end
    end
    return liste
end

--- Raenge des Rosters mit Namen, Anzahl und Auswahlstatus.
function Gilde.Rangliste()
    local zaehler, namen = {}, {}
    for _, e in ipairs((Gilde.Lesen())) do
        local i = e.rangIndex or 99
        zaehler[i] = (zaehler[i] or 0) + 1
        namen[i] = e.rang
    end
    local liste = {}
    for i = 0, 20 do
        if zaehler[i] then
            liste[#liste + 1] = {
                index = i, name = namen[i], anzahl = zaehler[i],
                aktiv = Gilde.RangAktiv(i),
            }
        end
    end
    return liste
end

-- =====================================================================
--  Altbestand raeumen
-- =====================================================================

--- Leert Notizen, die NICHT dem System gehoeren.
--  Eigene Konten (LO:...) bleiben unangetastet, damit der Befehl auch
--  spaeter gefahrlos ist. Ohne Sicherung passiert gar nichts.
--  @param wirklich  false/nil = nur anzeigen, was betroffen waere
--  @return liste der betroffenen Eintraege, oder nil und ein Grund
function Gilde.FremdeLeeren(wirklich)
    local _, fremd = Gilde.Lesen()
    if #fremd == 0 then return fremd end

    if wirklich then
        if Gilde.DarfSchreiben() == false then
            return nil, "kein Schreibrecht"
        end
        -- Sicherung ist Pflicht: erst sichern, dann loeschen.
        Gilde.Sichern()
        if not (LootOrdnungDB and LootOrdnungDB.sicherung) then
            return nil, "Sicherung fehlgeschlagen"
        end
        for _, e in ipairs(fremd) do
            Gilde.TextSchreiben(e.guid, "")
        end
    end

    return fremd
end

--- Stellt die gesicherten Notizen wieder her.
--  @return Anzahl, oder nil und ein Grund
function Gilde.Wiederherstellen()
    local sicherung = LootOrdnungDB and LootOrdnungDB.sicherung
    if not sicherung or not sicherung.notizen then
        return nil, "keine Sicherung vorhanden"
    end
    if Gilde.DarfSchreiben() == false then
        return nil, "kein Schreibrecht"
    end

    local n = 0
    for _, e in ipairs((Gilde.Lesen())) do
        local alt = sicherung.notizen[e.name]
        if alt and alt ~= e.notiz then
            Gilde.TextSchreiben(e.guid, alt)
            n = n + 1
        end
    end
    return n
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
