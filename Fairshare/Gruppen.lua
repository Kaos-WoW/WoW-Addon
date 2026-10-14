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

    ⭐ **Mitgliederabgleich** (frueher „Auffuellen"): Sind Gildenraenge
    gewaehlt, ist der Kader GENAU die Mitglieder dieser Raenge — wer neu
    hinzukommt, wird aufgenommen, wer die Gilde oder den Rang verlaesst,
    faellt weg. Das ist sicher, weil die Raenge die Quelle sind und nicht
    Handarbeit. (Entscheid des Gildenleiters, 14.10.2026.)

    Zwei Listen je Gruppe:
      * `kader`  vom Mitgliederabgleich verwaltet, wird ersetzt
      * `extra`  von Hand ergaenzt, bleibt immer erhalten
    Die Liste, die man sieht, ist beides zusammen.

    ⚠️ Schutz vor einer halb geladenen Gildenliste: Wuerde der Abgleich
    ploetzlich auffaellig viele entfernen, fragt er erst nach (Antwort:
    gleiche Taste nochmal innerhalb von zwei Minuten). Das automatische
    Abgleichen beim Anmelden entfernt in dem Fall gar nichts.
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

--- ⚠️ Alte Staende (vor dem Mitgliederabgleich) hatten nur `kader`, von Hand
--  gepflegt oder gefuellt. Das alles gilt jetzt als Handarbeit (`extra`),
--  damit der erste Abgleich nichts davon loescht.
local function migriere(G)
    if G and G.extra == nil then
        G.extra = G.kader or {}
        G.kader = {}
    end
    if G then
        G.kader = G.kader or {}
        G.raenge = G.raenge or {}
    end
    return G
end

--- Namen aller Gruppen, alphabetisch.
function Gruppen.Namen()
    local liste = {}
    for name in pairs(db().gruppen) do liste[#liste + 1] = name end
    table.sort(liste, function(a, b) return a:lower() < b:lower() end)
    return liste
end

function Gruppen.Holen(name)
    return name and migriere(db().gruppen[name]) or nil
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
    d.gruppen[name] = { name = name, kader = {}, extra = {}, raenge = {}, auto = true }
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

local function enthalten(liste, name)
    for _, e in ipairs(liste or {}) do
        if Kern.GleicherSpieler(e, name) then return true end
    end
    return false
end

--- Fuegt Namen hinzu, die noch nicht in `ziel` stehen.
--  @return Zahl der neu aufgenommenen
local function hinzufuegen(ziel, liste)
    local n = 0
    for _, roh in ipairs(liste) do
        local eintrag = type(roh) == "string" and roh:match("^%s*(.-)%s*$") or ""
        if eintrag ~= "" and not enthalten(ziel, eintrag) then
            ziel[#ziel + 1] = eintrag
            n = n + 1
        end
    end
    return n
end

--- Der ganze Kader: verwaltete und von Hand ergaenzte Namen, ohne Doppelte.
function Gruppen.Namensliste(G)
    local liste = {}
    if not G then return liste end
    for _, n in ipairs(G.kader or {}) do liste[#liste + 1] = n end
    for _, n in ipairs(G.extra or {}) do
        if not enthalten(liste, n) then liste[#liste + 1] = n end
    end
    return liste
end

--- Namen von Hand ergaenzen, durch Komma oder Zeilenumbruch getrennt.
--  Nicht an Leerzeichen: Nachnamen enthalten welche.
--  Diese Namen bleiben beim Mitgliederabgleich immer erhalten.
function Gruppen.KaderErgaenzen(name, text)
    local G = Gruppen.Holen(name)
    if not G then return nil end
    local liste = {}
    for roh in (text or ""):gmatch("[^,\n]+") do liste[#liste + 1] = roh end
    return hinzufuegen(G.extra, liste)
end

--- Entfernt einen Namen. Steht er nur durch einen gewaehlten Rang im Kader,
--  kommt er beim naechsten Abgleich zurueck — dafuer den Rang abwaehlen.
function Gruppen.KaderEntfernen(name, wer)
    local G = Gruppen.Holen(name)
    if not G then return false end
    local gefunden = false
    for _, liste in ipairs({ G.extra, G.kader }) do
        for i = #liste, 1, -1 do
            if Kern.GleicherSpieler(liste[i], wer) then
                table.remove(liste, i)
                gefunden = true
            end
        end
    end
    return gefunden
end

--- Namen, die ohne Gruppe in der Liste stehen muessen.
function Gruppen.Pflicht(gewaehlt)
    return Gruppen.Namensliste(Gruppen.Holen(gewaehlt) or Gruppen.Aktiv())
end

-- =====================================================================
--  Gilde lesen
-- =====================================================================

--- Alle Gildenmitglieder.
--  Forever liest ueber C_Club, Anniversary/Classic ueber GetGuildRosterInfo
--  (so hat es schon die erste Fassung dieses Projekts gemessen).
--  Gemessen mit `/fs gilde` (14.10.2026): Forever liefert Vor- UND Nachname
--  plus Gildenrang.
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
    return G and G.raenge[index] and true or false
end

function Gruppen.RangSetzen(gruppe, index, an)
    local G = Gruppen.Holen(gruppe)
    if not G then return false end
    G.raenge[index] = an and true or nil
    return true
end

-- =====================================================================
--  Mitgliederabgleich
-- =====================================================================

--- ⭐ Gleicht den Kader mit den Gildenraengen ab.
--
--  Mit gewaehlten Raengen: Kader = genau deren Mitglieder (hinzufuegen UND
--  entfernen). Ohne Raenge: nichts, was sich sicher entfernen liesse — dann
--  nimmt er nur Gildenmitglieder der aktuellen Gruppe zusaetzlich auf.
--
--  @param still  nur beim automatischen Lauf: kein Nachfragen, bei
--                Auffaelligkeiten wird gar nichts entfernt
--  @return neu, entfernt  oder  nil und ein Grund
function Gruppen.Synchronisieren(name, still)
    local G = Gruppen.Holen(name)
    if not G then return nil, L["Keine Gruppe aktiv."] end

    local gewaehlt = false
    for _ in pairs(G.raenge) do gewaehlt = true break end

    if not gewaehlt then
        -- ⚠️ Nur in einer Gruppe: Ohne Gruppe liefert Rolle.Namen den Spieler
        -- selbst, und der wuerde ungefragt aufgenommen.
        if not (IsInGroup and IsInGroup()) then
            return nil, L["Keine Gruppe und keine Gildenränge gewählt – nichts zum Synchronisieren."]
        end
        return hinzufuegen(G.extra, ns.Rolle.Namen(true)), 0
    end

    local M, grund = Gruppen.GildenMitglieder()
    if not M then return nil, grund end

    local neueListe = {}
    for _, m in ipairs(M) do
        if G.raenge[m.rangIndex] then neueListe[#neueListe + 1] = m.name end
    end
    -- Niemand in den gewaehlten Raengen: eher ein Zeichen fuer eine unvollstaendige
    -- oder veraenderte Gilde als fuer einen leeren Kader. Nichts anfassen.
    if #neueListe == 0 then
        return nil, L["In den gewählten Rängen ist niemand – nichts geändert."]
    end
    table.sort(neueListe, function(a, b) return a:lower() < b:lower() end)

    local hinzu, weg = 0, 0
    for _, n in ipairs(neueListe) do
        if not enthalten(G.kader, n) then hinzu = hinzu + 1 end
    end
    for _, n in ipairs(G.kader) do
        if not enthalten(neueListe, n) then weg = weg + 1 end
    end

    -- Schutz: auffaellig viele Abgaenge auf einmal -> erst bestaetigen lassen
    if weg > 0 and #G.kader >= 10 and weg > math.max(4, #G.kader * 0.4) then
        if still then
            hinzufuegen(G.kader, neueListe)   -- nur die Neuen, entfernt wird nichts
            return hinzu, 0, true
        end
        local jetzt = time()
        if not (G.warnung and (jetzt - G.warnung) < 120) then
            G.warnung = jetzt
            return nil, string.format(
                L["Auffällig viele würden entfernt (%d von %d). Die Gildenliste ist vielleicht noch nicht vollständig geladen. Nochmal klicken, um es trotzdem zu tun."],
                weg, #G.kader)
        end
    end
    G.warnung = nil

    G.kader = neueListe
    return hinzu, weg
end

--- Beim Anmelden einmal still abgleichen, wenn die Gruppe es will und
--  Raenge gewaehlt sind. Meldet nur, wenn sich etwas geaendert hat.
function Gruppen.AutoSynchronisieren()
    local name = Gruppen.AktivName()
    local G = Gruppen.Holen(name)
    if not G or G.auto == false then return end
    local gewaehlt = false
    for _ in pairs(G.raenge) do gewaehlt = true break end
    if not gewaehlt then return end

    local hinzu, weg, uebersprungen = Gruppen.Synchronisieren(name, true)
    if hinzu and (hinzu > 0 or (weg or 0) > 0) then
        print("|cff1B6B57Fairshare|r: " ..
            string.format(L["Kader „%s“: %d neu, %d entfernt."], name, hinzu, weg or 0))
    end
    if uebersprungen then
        print("|cff1B6B57Fairshare|r: " ..
            string.format(L["Kader „%s“: Entfernen übersprungen (zu viele auf einmal) – bitte in den Einstellungen prüfen."], name))
    end
end

local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- Die Gildenliste braucht einen Moment.
    if C_Timer then
        C_Timer.After(20, function() pcall(Gruppen.AutoSynchronisieren) end)
    end
end)

return ns
