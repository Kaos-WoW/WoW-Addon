--[[----------------------------------------------------------------------
    Quelle.lua  —  Woher die Vergaben kommen

    Die einzige Datei, die Gargul anfasst. Wir lesen ausschliesslich.

    ⭐ Gargul oeffnet sich selbst fuer Fremdzugriff — in seiner
    `bootstrap.lua` steht woertlich:

        _G.Gargul = GL; -- Open Gargul up to other developer integrations

    Und weil Gargul jede Vergabe an die Gruppe verteilt (beim Empfaenger
    landet sie ueber `storeReceivedAward` in dessen eigener Historie),
    waechst bei allen Raidleitern dieselbe Liste. Deshalb braucht dieses
    Addon weder Abgleich noch Import.

    ⚠️ Fremde Innereien sind ein Vertrag, den niemand unterschrieben hat:
    Aendert Gargul die Struktur, faellt das hier auf — nicht in der
    Anzeige. Darum liefert Vorhanden() einen benennbaren Grund.
------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local Quelle = {}
ns.Quelle = Quelle

-- =====================================================================
--  Garguls Historie
-- =====================================================================

--- Garguls Vergabe-Historie.
--  @return tabelle (Pruefsumme -> Eintrag), oder nil und ein Grund
function Quelle.Gargul()
    local GL = rawget(_G, "Gargul")
    if not GL then
        return nil, L["Gargul ist nicht geladen"]
    end
    if type(GL.DB) ~= "table" then
        return nil, L["Gargul ist noch nicht bereit"]
    end
    local H = GL.DB.AwardHistory
    if type(H) ~= "table" then
        return nil, L["Gargul hat noch keine Vergabe aufgezeichnet"]
    end
    return H
end

--- Laeuft Gargul, und wie viele Eintraege liegen vor?
function Quelle.Stand()
    local H, grund = Quelle.Gargul()
    if not H then return false, grund end
    local n = 0
    for _ in pairs(H) do n = n + 1 end
    return true, n
end

--- Die Historie, aus der ausgewertet wird: die EIGENE.
--  Gargul ist nur noch Einfuhrquelle, nicht Datenhalter.
function Quelle.Historie()
    if not ns.Erfassung then return nil, L["Erfassung nicht geladen"] end
    return ns.Erfassung.Historie()
end

--- Uebernimmt Garguls Aufzeichnungen einmalig in die eigene Historie.
--
--  Schluessel bleibt Garguls Pruefsumme — dadurch ist der Import
--  beliebig oft wiederholbar, ohne dass sich etwas doppelt.
--
--  ⚠️ **Der eigentliche Doppelgaenger sind aber unsere eigenen
--  Eintraege:** Lief die Eigenerfassung mit, waehrend Gargul dieselbe
--  Vergabe aufzeichnete, liegen zwei Eintraege mit verschiedenen
--  Schluesseln fuer dasselbe Stueck vor. Darum wird jeder Gargul-Eintrag
--  gegen die eigenen geprueft: gleicher Spieler, gleicher Gegenstand,
--  nah beieinander in der Zeit — dann uebersprungen.
--
--  @return uebernommen, uebersprungen  oder nil und ein Grund
function Quelle.GargulImport(fenster)
    fenster = fenster or 300

    local G, grund = Quelle.Gargul()
    if not G then return nil, grund end
    if not ns.Erfassung then return nil, L["Erfassung nicht geladen"] end

    local eigen = ns.Erfassung.Historie()
    local Kern = ns.Kern

    -- Eigene Eintraege nach Spieler und Gegenstand vorsortieren
    local Bekannt = {}
    for _, e in pairs(eigen) do
        if e.awardedTo and e.itemID then
            local k = (Kern.Schluessel(e.awardedTo) or "?") .. ":" .. tostring(e.itemID)
            Bekannt[k] = Bekannt[k] or {}
            table.insert(Bekannt[k], e.timestamp or 0)
        end
    end

    local neu, doppelt = 0, 0
    for pruefsumme, e in pairs(G) do
        if eigen[pruefsumme] then
            -- schon eingefuehrt
        elseif not Kern.Zaehlt(e) then
            -- entzaubert, Bonus oder unvollstaendig: nicht uebernehmen
        else
            local k = (Kern.Schluessel(e.awardedTo) or "?") .. ":" .. tostring(e.itemID)
            local schonDa = false
            for _, zeit in ipairs(Bekannt[k] or {}) do
                if math.abs(zeit - e.timestamp) <= fenster then schonDa = true break end
            end

            if schonDa then
                doppelt = doppelt + 1
            else
                eigen[pruefsumme] = {
                    awardedTo = e.awardedTo,
                    itemID    = e.itemID,
                    itemLink  = e.itemLink,
                    timestamp = e.timestamp,
                    OS        = e.OS or nil,
                    ausGargul = true,
                }
                neu = neu + 1
            end
        end
    end

    return neu, doppelt
end

-- =====================================================================
--  Garguls Wuerfelbereiche
-- =====================================================================

--- ⭐ Die Gilde wuerfelt 100 fuer Haupt- und 50 fuer Zweitbedarf. Gargul
--  bringt 100 und 99 mit. Weicht der Bereich ab, erkennt Gargul die Wuerfe
--  der Raider nicht (oder ordnet sie falsch ein), und unsere Erfassung
--  wuerde sich darauf verlassen.
--
--  Jeder Bereich bei Gargul: { Name, min, max, Rang, istZweitbedarf, +1 }

--- @return { ok = bool, haupt = bool, zweit = bool, bereiche = { ... } }
--          oder nil und ein Grund
function Quelle.GargulBereiche()
    local GL = rawget(_G, "Gargul")
    if not (GL and GL.Settings and GL.Settings.get) then
        return nil, L["Gargul ist nicht bereit"]
    end

    local ok, B = pcall(GL.Settings.get, GL.Settings, "RollTracking.Brackets", {})
    if not ok or type(B) ~= "table" then return nil, L["Einstellung nicht lesbar"] end

    local haupt, zweit, alle = false, false, {}
    for _, b in ipairs(B) do
        if type(b) == "table" then
            alle[#alle + 1] = string.format("%s %s-%s", tostring(b[1]), tostring(b[2]), tostring(b[3]))
            local art = ns.Kern.Bedarfsart(b[2], b[3])
            if art == "haupt" then haupt = true end
            if art == "zweit" then zweit = true end
        end
    end
    return { ok = haupt and zweit, haupt = haupt, zweit = zweit, bereiche = alle }
end

--- Stellt Garguls Bereiche auf die von Fairshare (Standard 1-100 und 1-99).
--  ⚠️ Das ist eine Einstellung bei Gargul, kein Eingriff in seinen Code.
--  Eigene weitere Bereiche gehen dabei verloren.
function Quelle.GargulBereicheSetzen()
    local GL = rawget(_G, "Gargul")
    if not (GL and GL.Settings and GL.Settings.set) then return false, L["Gargul ist nicht bereit"] end

    -- { Name, min, max, Rang, istZweitbedarf, +1 }
    local H, Z = ns.Kern.BEREICHE.haupt, ns.Kern.BEREICHE.zweit
    local kopie = {
        { "MS", H[1], H[2], 2, false, false },
        { "OS", Z[1], Z[2], 3, true,  false },
    }
    local ok, fehler = pcall(GL.Settings.set, GL.Settings, "RollTracking.Brackets", kopie)
    if not ok then return false, tostring(fehler) end
    return true
end

--- ⭐ Der umgekehrte Weg: Garguls Bereiche fuer Hauptbedarf (MS) und
--  Zweitbedarf (OS) werden die von Fairshare. Massgeblich ist der erste
--  Bereich, der nicht als Zweitbedarf gilt, und der erste, der es tut.
--  @return true, oder false und ein Grund
function Quelle.GargulBereicheUebernehmen()
    local GL = rawget(_G, "Gargul")
    if not (GL and GL.Settings and GL.Settings.get) then return false, L["Gargul ist nicht bereit"] end
    local ok, B = pcall(GL.Settings.get, GL.Settings, "RollTracking.Brackets", {})
    if not ok or type(B) ~= "table" then return false, L["Einstellung nicht lesbar"] end

    local haupt, zweit
    for _, b in ipairs(B) do
        if type(b) == "table" and tonumber(b[2]) and tonumber(b[3]) then
            if b[5] == true then zweit = zweit or b else haupt = haupt or b end
        end
    end
    if not (haupt and zweit) then
        return false, L["Gargul kennt keinen Bereich für Hauptbedarf und Zweitbedarf."]
    end
    return ns.Erfassung.BereicheSetzen(haupt[2], haupt[3], zweit[2], zweit[3])
end

-- =====================================================================
--  Der laufende Wurf
-- =====================================================================

--- Wird gerade um einen Gegenstand gewuerfelt?
--
--  Gargul fuehrt den laufenden Wurf in `RollOff.CurrentRollOff` und setzt
--  `RollOff.inProgress`. Ein Wurf ist { player, class, amount, min, max,
--  time, classification, priority }.
--
--  ⚠️ Ein Spieler kann mehrfach wuerfeln (Haupt- und Zweitbedarf, oder
--  versehentlich). Gezaehlt wird der HOECHSTE Wurf — alles andere waere
--  willkuerlich.
--
--  @return { link, name, Wuerfe = { Schluessel -> hoechster Wurf },
--            namen = { Name, ... } }  oder nil
function Quelle.Wurf()
    local GL = rawget(_G, "Gargul")
    local R = GL and GL.RollOff
    local Aktuell = (type(R) == "table" and R.inProgress) and R.CurrentRollOff or nil

    -- Ohne Gargul: die eigene Mitschrift. Sie kennt den Gegenstand nicht,
    -- aber wer gewuerfelt hat — und genau das ordnet die Liste.
    if type(Aktuell) ~= "table" then
        return ns.Erfassung and ns.Erfassung.AktuelleWuerfe() or nil
    end

    -- ⭐ Je Spieler zaehlt der ERSTE Wurf (nach Zeit, sonst nach Reihenfolge).
    -- Die Art kommt aus dem Bereich des Wurfs (1-100 Haupt, 1-99 Zweit),
    -- hilfsweise aus dem Namen des Bereichs bei Gargul („MS"/„OS").
    local Alle = {}
    for schluessel, W in pairs(Aktuell.Rolls or {}) do
        if type(W) == "table" then
            Alle[#Alle + 1] = { W = W, zeit = tonumber(W.time) or 0, nr = tonumber(schluessel) or 0 }
        end
    end
    table.sort(Alle, function(a, b)
        if a.zeit ~= b.zeit then return a.zeit < b.zeit end
        return a.nr < b.nr
    end)

    local Wuerfe, Arten, namen = {}, {}, {}
    for _, eintrag in ipairs(Alle) do
        local W = eintrag.W
        local k = W.player and ns.Kern.Schluessel(W.player)
        if k and Wuerfe[k] == nil then
            local art = ns.Kern.Bedarfsart(W.min, W.max)
            if not art and type(W.classification) == "string" then
                local c = W.classification:upper()
                if c == "MS" then art = "haupt" elseif c == "OS" then art = "zweit" end
            end
            namen[#namen + 1] = W.player
            Wuerfe[k], Arten[k] = tonumber(W.amount) or 0, art
        end
    end

    return {
        link  = Aktuell.itemLink,
        name  = Aktuell.itemName,
        Wuerfe = Wuerfe,
        Arten = Arten,
        namen = namen,
    }
end

-- =====================================================================
--  Gegenstaende
-- =====================================================================

--- Wie ein Gegenstand angezeigt wird.
--  Echte Eintraege tragen den Verweis mit. Fehlt er, wird er ueber die
--  Nummer nachgeschlagen — versionsbewusst, weil in Forever die Globals
--  fehlen und nur C_Item existiert.
--  ⚠️ Kennt der Client den Gegenstand nicht, bleibt die Nummer stehen.
--  Das ist richtig so: lieber eine Nummer als ein erfundener Name.
local function grundtext(eintrag)
    if type(eintrag) ~= "table" then return "?" end
    if eintrag.itemLink then return eintrag.itemLink end

    local id = eintrag.itemID
    if not id then return "?" end

    local CI = rawget(_G, "C_Item")
    local voll = (CI and CI.GetItemInfo) or rawget(_G, "GetItemInfo")
    if voll then
        local ok, _, link = pcall(voll, id)
        if ok and link then return link end
    end
    return string.format(L["Gegenstand %s"], tostring(id))
end

--- ⭐ Kennzeichen einer Vergabe (Regelwerk § 1, § 5, § 6):
--    abweichend vom Ergebnis (Main) | OS nach Absprache | zurueckgegeben, noch nicht neu vergeben.
--  @return Text mit Farbcode, oder ""
function Quelle.Kennzeichen(eintrag)
    if type(eintrag) ~= "table" then return "" end
    local teile = {}
    if eintrag.kennzeichen == "A" then
        teile[#teile + 1] = "|cffffaa55" .. L["abweichend vom Ergebnis"] .. "|r"
    elseif eintrag.kennzeichen == "S" then
        teile[#teile + 1] = "|cff7fbfff" .. L["OS nach Absprache"] .. "|r"
    end
    if eintrag.rueckgabe and not eintrag.zurueck then
        teile[#teile + 1] = "|cffffff78" .. L["zurückgegeben"] .. "|r"
    end
    if #teile == 0 then return "" end
    return "(" .. table.concat(teile, ", ") .. ")"
end

function Quelle.Gegenstandstext(eintrag)
    local text = grundtext(eintrag)
    local zusatz = Quelle.Kennzeichen(eintrag)
    if zusatz ~= "" then text = text .. " " .. zusatz end
    return text
end

--- Tagesschluessel fuer Kern.Raidtage.
function Quelle.Tag(zeitstempel)
    return date("%Y-%m-%d", zeitstempel)
end

-- =====================================================================
--  Beispieldaten
-- =====================================================================

-- Verteilung je Spieler: Hauptbedarf, Zweitbedarf. Bewusst ungleich,
-- damit die Anzeige zeigt, wofuer sie gedacht ist — jemand mit vielen
-- Stuecken, jemand mit einem vor Monaten, jemand nur mit Zweitbedarf.
local VERTEILUNG = {
    { "Xalessa",      9, 2 },
    { "Grotschak",    7, 0 },
    { "Kroenix",      6, 1 },
    { "Exotica",      5, 3 },
    { "Moonspell",    5, 0 },
    { "Lupitus",      4, 1 },
    { "Järgerlie",    4, 0 },
    { "Deters",       2, 2 },
    { "Chilini",      3, 0 },
    { "Kaosx",        2, 1 },
    { "Simondan",     3, 0 },
    { "Velera",       1, 1 },
    { "Renbi",        1, 0 },
    { "Pflasterelfe", 0, 2 },
}

-- Echte Gegenstands-IDs. Kennt der Client sie nicht, steht die Nummer da.
local GEGENSTAENDE = { 32235, 32505, 32837, 30883, 29434, 32369, 32256, 32332 }

--- Baut eine Beispiel-Historie im Speicher.
--  ⚠️ Schreibt NICHTS — weder in Gargul noch in die SavedVariables.
--  Der Aufrufer reicht das Ergebnis in die Auswertung wie eine echte
--  Historie; die Anzeige merkt keinen Unterschied.
function Quelle.Beispiel()
    local jetzt = time()
    local TAG = ns.Kern.TAG
    local H, n = {}, 0

    -- Zehn Raidabende, grob woechentlich.
    local abende = {}
    for i = 1, 10 do abende[i] = jetzt - (i * 7 - 4) * TAG end

    for _, Zeile in ipairs(VERTEILUNG) do
        local name, haupt, zweit = Zeile[1], Zeile[2], Zeile[3]
        for k = 1, haupt + zweit do
            n = n + 1
            H["beispiel" .. n] = {
                awardedTo = name,
                itemID    = GEGENSTAENDE[(n % #GEGENSTAENDE) + 1],
                timestamp = abende[((n * 3) % #abende) + 1] + (n % 4) * 900,
                OS        = k > haupt,
            }
        end
    end

    return H
end

--- Fiktive Zuschlaege und Anhebungen fuer die Demo (§ 2 und § 3).
--  Zeigt u. a. Deters mit 1.7 Zuschlag aus verpassten Raids und Lupitus mit 2.0 (unentschuldigt).
function Quelle.BeispielDaten()
    return {
        zuschlaege = {
            ["deters"]  = 1.7,
            ["lupitus"] = 2.0,
        },
        anhebungen = {},
    }
end

--- Ein Beispiel-Wurf zum Ansehen der Hervorhebung und Rangfolge.
--  Demonstriert alle Kernregeln des Regelwerks:
--  - Nuhkomm (0 Items) liegt weit hinten und wird auf Niedrigster + 2 = 4.0 gesetzt (§ 3) -> 5. Platz
--  - Kaosx (Wertung 2.0, Wurf 24) schlaegt Deters (Wertung 3.7, Wurf 98) -> Wertung vor Wurf!
--  - Chilini (Wurf 81) schlaegt Simondan (Wurf 45) bei gleicher Wertung 3.0 -> Wurf entscheidet
--  - Velera (1 OS, Wurf 38) schlaegt Pflasterelfe (2 OS, Wurf 49) -> weniger OS vor Wurf
function Quelle.BeispielWurf()
    local Wuerfe, Arten, namen = {}, {}, {}
    local gewuerfelt = {
        { "Deters",       98, "haupt" },
        { "Simondan",     45, "haupt" },
        { "Nuhkomm",      93, "haupt" },
        { "Kaosx",        24, "haupt" },
        { "Velera",       38, "zweit" },
        { "Chilini",      81, "haupt" },
        { "Pflasterelfe", 49, "zweit" },
    }
    for _, W in ipairs(gewuerfelt) do
        namen[#namen + 1] = W[1]
        Wuerfe[ns.Kern.Schluessel(W[1])] = W[2]
        Arten[ns.Kern.Schluessel(W[1])] = W[3]
    end
    return { link = nil, name = "Zorn des Verräters", Wuerfe = Wuerfe, Arten = Arten, namen = namen }
end

return ns
