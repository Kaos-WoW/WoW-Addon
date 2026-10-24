--[[----------------------------------------------------------------------
    Rolle.lua  —  Wer in der Gruppe zeichnet auf?

    ⭐ Entscheid des Gildenleiters (14.10.2026): **nur der Pluendermeister**
    fuehrt die Historie; gibt es keinen, der Schlachtzugsleiter (als
    Rueckfall). Alle anderen empfangen nur.

    Warum nicht jeder? Sieht jeder Teilnehmer dieselbe Beutemeldung und
    schreibt sie auf, entstehen je Drop so viele Eintraege wie Spieler im
    Raid — und der Abgleich muesste sie wieder zusammenfuehren.

    Die Wahl selbst steht in Kern.Schreiber (ohne WoW-API, getestet). Hier
    wird nur die Gruppe gelesen und in Kandidaten uebersetzt.

    ⚠️ Der Pluendermeister wird nur gewaehlt, wenn er das Addon auch hat.
    Das wissen wir aus den Hallo-Meldungen (Abgleich.lua). Bis sie
    eintreffen, schreibt zur Not auch der Leiter mit — eine doppelte
    Zeile faengt der Abgleich ab, eine fehlende nicht.
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Rolle = {}
ns.Rolle = Rolle

local Kern = ns.Kern

-- =====================================================================
--  Gruppe lesen
-- =====================================================================

local function nameVon(unit)
    if GetUnitName then
        local n = GetUnitName(unit, true)
        if n and n ~= "" then return n end
    end
    return (UnitName(unit))
end

--- Alle Einheiten der Gruppe, den Spieler eingeschlossen.
local function einheiten()
    local liste = {}
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            liste[#liste + 1] = { unit = "raid" .. i, index = i }
        end
    else
        liste[1] = { unit = "player" }
        for i = 1, 4 do
            if UnitExists("party" .. i) then liste[#liste + 1] = { unit = "party" .. i } end
        end
    end
    return liste
end

Rolle.Einheiten = einheiten

--- Die Beutemethode als Text: "master", "group", ...
--  ⚠️ Versionsbewusst: Classic liefert den Text, die Mainline-Fassung eine
--  Zahl (2 = Meisterplünderer). Gemessen wird, was da ist.
local function lootMethode()
    local roh = rawget(_G, "GetLootMethod")
    if roh then
        local ok, m, partei, schlachtzug = pcall(roh)
        if ok then return m, partei, schlachtzug end
    end

    local CP = rawget(_G, "C_PartyInfo")
    if CP and CP.GetLootMethod then
        local ok, m, partei, schlachtzug = pcall(CP.GetLootMethod)
        if ok then
            local Namen = { [0] = "freeforall", [1] = "roundrobin", [2] = "master",
                            [3] = "group", [4] = "needbeforegreed", [5] = "personalloot" }
            return Namen[m] or m, partei, schlachtzug
        end
    end
    return nil
end

--- Ist diese Einheit Pluendermeister?
local function istPluendermeister(E, partei)
    -- Selbst: die Weiche, die es in Classic gibt
    if E.unit == "player" or (UnitIsUnit and UnitIsUnit(E.unit, "player")) then
        local f = rawget(_G, "IsMasterLooter")
        if f then
            local ok, r = pcall(f)
            if ok and r then return true end
        end
    end

    if E.index and GetRaidRosterInfo then
        local ok, _, _, _, _, _, _, _, _, _, _, ml = pcall(GetRaidRosterInfo, E.index)
        if ok and ml then return true end
        return false
    end

    -- Fuenfergruppe: die Nummer 0 ist man selbst, 1-4 sind party1-4.
    if partei ~= nil then
        if partei == 0 then return E.unit == "player" end
        return E.unit == "party" .. tostring(partei)
    end
    return false
end

local function istLeiter(E)
    return UnitIsGroupLeader and UnitIsGroupLeader(E.unit) and true or false
end

local function istAssistent(E)
    return UnitIsGroupAssistant and UnitIsGroupAssistant(E.unit) and true or false
end

--- Die Rangfolge der Schreiber: Pluendermeister, Leiter, Assistenten.
--  @return Liste { name, ich, rolle }, Beutemethode
function Rolle.Kandidaten()
    local methode, partei = lootMethode()
    local Alle = einheiten()

    local ml, leiter, assist = nil, nil, {}
    for _, E in ipairs(Alle) do
        local k = {
            name = nameVon(E.unit),
            ich  = UnitIsUnit and UnitIsUnit(E.unit, "player") and true or false,
            unit = E.unit,
        }
        if methode == "master" and not ml and istPluendermeister(E, partei) then
            k.rolle = L["Plündermeister"]
            k.ml = true
            ml = k
        elseif istLeiter(E) then
            k.rolle = L["Leiter"]
            leiter = k
        elseif istAssistent(E) then
            k.rolle = L["Assistent"]
            assist[#assist + 1] = k
        end
    end

    -- Ist der Pluendermeister zugleich Leiter, gilt er als Pluendermeister.
    local liste = {}
    local gesehen = {}
    local function nimm(k)
        if k and not gesehen[k.unit] then
            gesehen[k.unit] = true
            liste[#liste + 1] = k
        end
    end
    nimm(ml)
    nimm(leiter)
    for _, k in ipairs(assist) do nimm(k) end

    return liste, methode
end

-- =====================================================================
--  Entscheid
-- =====================================================================

--- ⭐ Ist das Addon gerade im Dienst? Nur in einer Gruppe mit Plündermeister
--  als Beutemethode (Entscheid des Gildenleiters, 15.10.2026). Bei Gruppen-
--  beute, Bedarf/Gier & Co. tut es nichts: keine Aufzeichnung, kein
--  aufspringendes Fenster, keine Wurfanzeige. Die Methode wird bei jedem
--  Aufruf frisch gelesen, ein Wechsel gilt also sofort.
--  @return true/false, Grund als Text
function Rolle.Aktiv()
    if not (IsInGroup and IsInGroup()) then
        return false, L["keine Gruppe – allein wird nichts aufgezeichnet"]
    end
    local methode = lootMethode()
    if methode ~= "master" then
        return false, L["Beutemethode ist nicht Plündermeister – das Addon schläft"]
    end
    local nutzung = Rolle.Nutzung()
    if nutzung == "nein" then
        return false, L["Du hast KaosLoot für diese Gruppe abgelehnt – das Addon schläft"]
    elseif nutzung ~= "ja" then
        -- ⭐ Fragen muss nur der Plündermeister; alle anderen warten auf seine Antwort (Nutzung.lua)
        if Rolle.IchBinPluendermeister() then
            return false, L["KaosLoot wartet auf deine Antwort – /kl nutzung"]
        end
        return false, L["KaosLoot wartet auf die Antwort des Plündermeisters – oder /kl nutzung ja"]
    end
    return true
end

--- Die Beutemethode als Text ("master", "group", …) oder nil, wenn sie nicht lesbar ist.
function Rolle.Methode()
    return (lootMethode())
end

--- ⭐ Die Antwort auf „KaosLoot nutzen?" (Nutzung.lua) für die aktuelle Gruppe.
--  @return "ja", "nein" oder nil (noch nicht gefragt/beantwortet)
function Rolle.Nutzung()
    local v = ns.Erfassung.Einstellungen().nutzung
    if v == "ja" or v == "nein" then return v end
    return nil
end

--- @param wert    "ja" | "nein" | nil (zurücknehmen: es wird neu gefragt)
--  @param quelle  "leiter": vom Plündermeister übernommen (Nachricht `U`); sonst die eigene Entscheidung.
--                 Die eigene bleibt, wenn der Plündermeister später etwas anderes meldet.
function Rolle.NutzungSetzen(wert, quelle)
    local d = ns.Erfassung.Einstellungen()
    d.nutzung = (wert == "ja" or wert == "nein") and wert or nil
    d.nutzungQuelle = d.nutzung and (quelle == "leiter" and "leiter" or "selbst") or nil
    if ns.Nutzung then ns.Nutzung.Entschieden(d.nutzung) end
    -- ⭐ Antwortet der Plündermeister, gilt es für alle in der Gruppe mit dem Addon
    if d.nutzung and quelle ~= "leiter" and ns.Nutzung and ns.Nutzung.Verkuenden then
        pcall(ns.Nutzung.Verkuenden)
    end
end

--- Ist dieser (andere) Spieler gerade Plündermeister unserer Gruppe?
function Rolle.IstPluendermeister(name)
    for _, k in ipairs((Rolle.Kandidaten())) do
        if k.ml and Kern.GleicherSpieler(k.name, name) then return true end
    end
    return false
end

--- Zeichnet DIESER Spieler gerade auf?
--  @return true/false, Grund als Text
function Rolle.IchSchreibe()
    local d = ns.Erfassung.Einstellungen()
    local modus = d.schreiben or "auto"

    -- ⭐ Ohne Gruppe wird NIE mitgeschrieben — auch nicht bei „immer"
    -- (Entscheid des Gildenleiters, 14.10.2026): Das Addon ist fuer
    -- Gruppeninhalt gedacht. Wer allein etwas Seltenes bekommt, gehoert
    -- nicht in die Historie, und Fuenfer-Instanzen dienen nur dem Erproben
    -- des Raid-Ablaufs mit einer Gruppe. Ebenso nie ohne Plündermeister als
    -- Beutemethode (15.10.2026).
    local aktiv, warum = Rolle.Aktiv()
    if not aktiv then return false, warum end

    if modus == "immer" then return true, L["eingestellt: immer"] end
    if modus == "nie"   then return false, L["eingestellt: nie"] end

    local kandidaten = Rolle.Kandidaten()
    if #kandidaten == 0 then
        -- Weder Leiter noch Plündermeister auszumachen: lieber doppelt als gar nicht.
        return true, L["kein Leiter erkennbar"]
    end

    local hat = ns.Abgleich and ns.Abgleich.Bekannte() or {}
    local wahl = Kern.Schreiber(kandidaten, hat)

    if not wahl then
        -- Keiner der Kandidaten hat das Addon.
        return false, L["weder Plündermeister noch Leiter haben das Addon"]
    end
    if wahl.ich then
        return true, wahl.rolle or L["Kandidat"]
    end
    return false, string.format(L["%s zeichnet auf"], wahl.name or "?")
end

--- Ist DIESER Spieler gerade Pluendermeister?
function Rolle.IchBinPluendermeister()
    if not (IsInGroup and IsInGroup()) then return false end
    for _, k in ipairs((Rolle.Kandidaten())) do
        if k.ich and k.ml then return true end
    end
    return false
end

--- Wer zeichnet gerade auf? Fuer die Anzeige.
--  @return Name oder nil, Rolle
function Rolle.AktuellerSchreiber()
    if not (IsInGroup and IsInGroup()) then return nil end
    local kandidaten = Rolle.Kandidaten()
    local hat = ns.Abgleich and ns.Abgleich.Bekannte() or {}
    local wahl = Kern.Schreiber(kandidaten, hat)
    if wahl then return wahl.name, wahl.rolle, wahl.ich end
    return nil
end

--- Darf diese Meldung von diesem Absender als Anweisung gelten?
--  Ein Absender gilt als berechtigt, wenn er Pluendermeister, Leiter oder
--  Assistent ist.
function Rolle.Berechtigt(sender)
    for _, k in ipairs((Rolle.Kandidaten())) do
        if Kern.GleicherSpieler(k.name, sender) then return true, k.rolle end
    end
    return false
end

--- Ist der Absender in unserer Gruppe — und in unserer Gilde?
--  ⚠️ Gilde, weil Fremde im Raid (Gaeste) keine Eintraege einschleusen
--  duerfen. Findet sich der Absender nicht, ist die Antwort Nein: lieber
--  einen Abgleich verpassen als fremde Daten annehmen.
--  @return gilde (bool), unit oder nil
function Rolle.Absender(sender)
    for _, E in ipairs(einheiten()) do
        if Kern.GleicherSpieler(nameVon(E.unit), sender) then
            -- ⚠️ Fehlt die Pruefung im Client, laesst sie sich nicht
            -- erzwingen; dann gilt der Absender als Mitglied.
            local gilde = true
            if UnitIsInMyGuild then gilde = UnitIsInMyGuild(E.unit) and true or false end
            return gilde, E.unit
        end
    end
    return false, nil
end

--- Namen der aktuellen Gruppe (ohne Gruppe: nur man selbst).
--  @param nurGilde  nur Mitglieder der eigenen Gilde (keine Gaeste).
--                   ⚠️ Fehlt die Pruefung im Client, gelten alle als Mitglied.
function Rolle.Namen(nurGilde)
    local liste = {}
    for _, E in ipairs(einheiten()) do
        local n = nameVon(E.unit)
        if n and n ~= "" and n ~= UNKNOWN then
            local drin = true
            if nurGilde and UnitIsInMyGuild then drin = UnitIsInMyGuild(E.unit) and true or false end
            if drin then liste[#liste + 1] = n end
        end
    end
    return liste
end

return ns
