--[[----------------------------------------------------------------------
    Gruppen.lua  —  Beschriftung und Kader

    Eine Gruppe ist zweierlei:
      * eine **Beschriftung** (z. B. „40er", „10er"): Jede Vergabe merkt
        sich die beim Eintragen aktive Gruppe, die Ansicht laesst sich
        auf eine Gruppe einschraenken;
      * ein **Kader**: eine Namensliste, die ohne Gruppe in der Liste
        steht — auch fuer Spieler ohne Vergabe.

    ⭐ In einer Gruppe zeigt die Uebersicht nur die Spieler, die gerade bei
    dir sind (Fenster.lua, Kern.Bilanz mit `nur`). Der Kader zaehlt dann
    nicht; er ist die Grundlage, wenn man ausserhalb einer Gruppe nachsieht.

    ⭐ **Auffuellen erweitert nur.** Es nimmt die Mitglieder der gewaehlten
    Gildenraenge und die Gildenmitglieder der aktuellen Gruppe auf — aber
    es entfernt nie jemanden. Wer die Gilde verlaesst, wird von Hand
    entfernt (das war die ausdrueckliche Entscheidung des Gildenleiters).

    Frueher gab es zwei Arten (Kader und Raidgruppe). Die Raidgruppe ist
    entfallen, weil „nur wer in der Gruppe steht" jetzt fuer jede Gruppe
    gilt. Alte Eintraege mit `modus` werden wie ein Kader gelesen.
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Gruppen = {}
ns.Gruppen = Gruppen

local Kern = ns.Kern

local function db()
    local d = ns.Erfassung.Einstellungen()
    d.gruppen = d.gruppen or {}
    return d
end

--- Namen aller Gruppen, alphabetisch.
function Gruppen.Namen()
    local liste = {}
    for name in pairs(db().gruppen) do liste[#liste + 1] = name end
    table.sort(liste, function(a, b) return a:lower() < b:lower() end)
    return liste
end

function Gruppen.Holen(name)
    return name and db().gruppen[name] or nil
end

--- Die aktive Gruppe (die neue Vergaben bekommen).
function Gruppen.AktivName()
    local d = db()
    if d.aktiveGruppe and d.gruppen[d.aktiveGruppe] then return d.aktiveGruppe end
    return nil
end

function Gruppen.Aktiv()
    return Gruppen.Holen(Gruppen.AktivName())
end

--- @return true, oder false und ein Grund
function Gruppen.Anlegen(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return false, L["kein Name"] end
    if #name > 40 then return false, L["Name zu lang (höchstens 40 Zeichen)"] end
    -- ⚠️ Kein Semikolon und keine Steuerzeichen: Der Name geht beim Abgleich
    -- mit auf die Reise. Kodieren schuetzt zwar, aber Ruhe ist besser.
    if name:find("[;~|%c]") then return false, L["Zeichen nicht erlaubt"] end

    local d = db()
    if d.gruppen[name] then return false, L["gibt es schon"] end
    d.gruppen[name] = { name = name, kader = {}, raenge = {}, auto = true }
    if not d.aktiveGruppe then d.aktiveGruppe = name end
    return true
end

function Gruppen.Loeschen(name)
    local d = db()
    if not d.gruppen[name] then return false end
    d.gruppen[name] = nil
    if d.aktiveGruppe == name then d.aktiveGruppe = nil end
    return true
end

function Gruppen.Aktivieren(name)
    local d = db()
    if name ~= nil and not d.gruppen[name] then return false end
    d.aktiveGruppe = name
    return true
end

-- =====================================================================
--  Kader
-- =====================================================================

--- Fuegt Namen hinzu, die noch nicht im Kader stehen.
--  @param liste  Liste von Namen
--  @return Zahl der neu aufgenommenen
local function hinzufuegen(G, liste)
    G.kader = G.kader or {}
    local n = 0
    for _, roh in ipairs(liste) do
        local eintrag = type(roh) == "string" and roh:match("^%s*(.-)%s*$") or ""
        if eintrag ~= "" then
            local da = false
            for _, e in ipairs(G.kader) do
                if Kern.GleicherSpieler(e, eintrag) then da = true break end
            end
            if not da then
                G.kader[#G.kader + 1] = eintrag
                n = n + 1
            end
        end
    end
    return n
end

--- Namen zum Kader hinzufuegen, durch Komma oder Zeilenumbruch getrennt.
--  Nicht an Leerzeichen: Nachnamen enthalten welche.
function Gruppen.KaderErgaenzen(name, text)
    local G = Gruppen.Holen(name)
    if not G then return nil end
    local liste = {}
    for roh in (text or ""):gmatch("[^,\n]+") do liste[#liste + 1] = roh end
    return hinzufuegen(G, liste)
end

function Gruppen.KaderEntfernen(name, wer)
    local G = Gruppen.Holen(name)
    if not G then return false end
    for i, e in ipairs(G.kader or {}) do
        if Kern.GleicherSpieler(e, wer) then
            table.remove(G.kader, i)
            return true
        end
    end
    return false
end

--- Namen, die ohne Gruppe in der Liste stehen muessen.
function Gruppen.Pflicht(gewaehlt)
    local G = Gruppen.Holen(gewaehlt) or Gruppen.Aktiv()
    return G and G.kader or {}
end

-- =====================================================================
--  Gilde lesen
-- =====================================================================

--- Alle Gildenmitglieder.
--  Forever liest ueber C_Club, Anniversary/Classic ueber GetGuildRosterInfo
--  (so hat es schon die erste Fassung dieses Projekts gemessen).
--  ⚠️ Das Format der Namen in Forever (Nachname, Realm) ist nicht gemessen —
--  `Kern.GleicherSpieler` faengt beides ab; `/lh gilde` zeigt, was ankommt.
--  @return Liste aus { name, rang, rangIndex } oder nil und ein Grund
function Gruppen.GildenMitglieder()
    local liste = {}

    local CC = rawget(_G, "C_Club")
    if CC and CC.GetGuildClubId and CC.GetClubMembers and CC.GetMemberInfo then
        local ok, clubId = pcall(CC.GetGuildClubId)
        if ok and clubId then
            local ok2, ids = pcall(CC.GetClubMembers, clubId)
            if ok2 and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    local ok3, info = pcall(CC.GetMemberInfo, clubId, id)
                    if ok3 and type(info) == "table" and info.name then
                        liste[#liste + 1] = {
                            name = info.name,
                            rang = info.guildRank,
                            rangIndex = info.guildRankOrder,
                        }
                    end
                end
            end
        end
    end

    if #liste == 0 then
        local anzahl = rawget(_G, "GetNumGuildMembers")
        local info = rawget(_G, "GetGuildRosterInfo")
        if anzahl and info then
            for i = 1, (anzahl() or 0) do
                local name, rang, rangIndex = info(i)
                if name then
                    liste[#liste + 1] = { name = name, rang = rang, rangIndex = rangIndex }
                end
            end
        end
    end

    if #liste == 0 then return nil, L["Die Gildenliste ist noch nicht geladen."] end
    return liste
end

local rangCache = { t = -100 }

--- Die Raenge der Gilde, vom hoechsten zum niedrigsten.
--  ⚠️ Fuenf Sekunden gemerkt: Das Einstellungsfenster fragt sie je Zeile
--  mehrfach, und die Gildenliste durchzugehen ist nicht billig.
--  @return Liste aus { index, name } oder nil und ein Grund
function Gruppen.Raenge()
    local jetzt = (GetTime and GetTime()) or time()
    if (jetzt - rangCache.t) < 5 then return rangCache.r, rangCache.grund end
    local r, g = Gruppen.RaengeNeu()
    rangCache = { t = jetzt, r = r, grund = g }
    return r, g
end

function Gruppen.RaengeNeu()
    local M, grund = Gruppen.GildenMitglieder()
    if not M then return nil, grund end

    local gesehen, raenge = {}, {}
    for _, m in ipairs(M) do
        local i = m.rangIndex
        if i ~= nil and not gesehen[i] then
            gesehen[i] = true
            raenge[#raenge + 1] = { index = i, name = tostring(m.rang or i) }
        end
    end
    table.sort(raenge, function(a, b) return a.index < b.index end)
    return raenge
end

function Gruppen.RangGewaehlt(gruppe, index)
    local G = Gruppen.Holen(gruppe)
    return G and G.raenge and G.raenge[index] and true or false
end

function Gruppen.RangSetzen(gruppe, index, an)
    local G = Gruppen.Holen(gruppe)
    if not G then return false end
    G.raenge = G.raenge or {}
    G.raenge[index] = an and true or nil
    return true
end

-- =====================================================================
--  Auffuellen
-- =====================================================================

--- ⭐ Nimmt neue Spieler in den Kader auf — entfernt nie jemanden.
--  Quellen: die Mitglieder der gewaehlten Gildenraenge, und die
--  Gildenmitglieder in der aktuellen Gruppe (Gaeste nicht).
--  @return Zahl der neu aufgenommenen, oder nil und ein Grund
function Gruppen.Auffuellen(name)
    local G = Gruppen.Holen(name)
    if not G then return nil, L["Keine Gruppe aktiv."] end

    local neu = {}

    local gewaehlt = false
    for _ in pairs(G.raenge or {}) do gewaehlt = true break end
    if gewaehlt then
        local M, grund = Gruppen.GildenMitglieder()
        if not M then
            -- Ohne Gildenliste bleibt immerhin die Gruppe
            if not (IsInGroup and IsInGroup()) then return nil, grund end
        else
            for _, m in ipairs(M) do
                if G.raenge[m.rangIndex] then neu[#neu + 1] = m.name end
            end
        end
    end

    -- ⚠️ Nur in einer Gruppe: Ohne Gruppe liefert Rolle.Namen den Spieler
    -- selbst, und der wuerde ungefragt in den Kader wandern.
    if IsInGroup and IsInGroup() then
        for _, n in ipairs(ns.Rolle.Namen(true)) do neu[#neu + 1] = n end
    end

    if #neu == 0 and not gewaehlt and not (IsInGroup and IsInGroup()) then
        return nil, L["Keine Gruppe und keine Gildenränge gewählt – nichts zum Auffüllen."]
    end
    return hinzufuegen(G, neu)
end

--- Beim Anmelden einmal still auffuellen, wenn die Gruppe es will und
--  Raenge gewaehlt sind. Meldet nur, wenn etwas dazukam.
function Gruppen.AutoAuffuellen()
    local name = Gruppen.AktivName()
    local G = Gruppen.Holen(name)
    if not G or G.auto == false then return end
    local gewaehlt = false
    for _ in pairs(G.raenge or {}) do gewaehlt = true break end
    if not gewaehlt then return end

    local n = Gruppen.Auffuellen(name)
    if n and n > 0 then
        print("|cff1B6B57Loot-Historie|r: " ..
            string.format(L["Kader „%s“: %d neue Spieler aus der Gilde aufgenommen."], name, n))
    end
end

local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- Die Gildenliste braucht einen Moment.
    if C_Timer then
        C_Timer.After(20, function() pcall(Gruppen.AutoAuffuellen) end)
    end
end)

return ns
