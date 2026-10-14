--[[----------------------------------------------------------------------
    Rolle.lua  —  Wer in der Gruppe schreibt mit?

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
            k.rolle = "Plündermeister"
            ml = k
        elseif istLeiter(E) then
            k.rolle = "Leiter"
            leiter = k
        elseif istAssistent(E) then
            k.rolle = "Assistent"
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

--- Schreibt DIESER Spieler gerade mit?
--  @return true/false, Grund als Text
function Rolle.IchSchreibe()
    local d = ns.Erfassung.Einstellungen()
    local modus = d.schreiben or "auto"

    if modus == "immer" then return true, "eingestellt: immer" end
    if modus == "nie"   then return false, "eingestellt: nie" end

    -- Allein unterwegs (Test, Solo-Instanz): niemand sonst kann es tun.
    if not (IsInGroup and IsInGroup()) then
        return true, "keine Gruppe"
    end

    local kandidaten, methode = Rolle.Kandidaten()
    if #kandidaten == 0 then
        -- Weder Leiter noch Plündermeister auszumachen: lieber doppelt als gar nicht.
        return true, "kein Leiter erkennbar"
    end

    local hat = ns.Abgleich and ns.Abgleich.Bekannte() or {}
    local wahl = Kern.Schreiber(kandidaten, hat)

    if not wahl then
        -- Keiner der Kandidaten hat das Addon.
        return false, "weder Plündermeister noch Leiter haben das Addon"
    end
    if wahl.ich then
        return true, (wahl.rolle or "Kandidat") .. (methode == "master" and "" or " (kein Plündermeister)")
    end
    return false, (wahl.name or "?") .. " schreibt mit"
end

--- Wer ist der Schreiber gerade? Fuer die Anzeige.
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

--- Namen der aktuellen Gruppe.
function Rolle.Namen()
    local liste = {}
    for _, E in ipairs(einheiten()) do
        local n = nameVon(E.unit)
        if n and n ~= "" and n ~= UNKNOWN then liste[#liste + 1] = n end
    end
    return liste
end

return ns
