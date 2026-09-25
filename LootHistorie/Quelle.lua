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
        return nil, "Gargul ist nicht geladen"
    end
    if type(GL.DB) ~= "table" then
        return nil, "Gargul ist noch nicht bereit"
    end
    local H = GL.DB.AwardHistory
    if type(H) ~= "table" then
        return nil, "Gargul hat noch keine Vergabe aufgezeichnet"
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
    if not ns.Erfassung then return nil, "Erfassung nicht geladen" end
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
    if not ns.Erfassung then return nil, "Erfassung nicht geladen" end

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
    if not GL then return nil end

    local R = GL.RollOff
    if type(R) ~= "table" or not R.inProgress then return nil end

    local Aktuell = R.CurrentRollOff
    if type(Aktuell) ~= "table" then return nil end

    local Wuerfe, namen = {}, {}
    for _, W in pairs(Aktuell.Rolls or {}) do
        local k = W and W.player and ns.Kern.Schluessel(W.player)
        if k then
            local wert = tonumber(W.amount) or 0
            if Wuerfe[k] == nil then
                namen[#namen + 1] = W.player
                Wuerfe[k] = wert
            elseif wert > Wuerfe[k] then
                Wuerfe[k] = wert
            end
        end
    end

    return {
        link  = Aktuell.itemLink,
        name  = Aktuell.itemName,
        Wuerfe = Wuerfe,
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
function Quelle.Gegenstandstext(eintrag)
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
    return "Gegenstand " .. tostring(id)
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
    { "Deters",       3, 2 },
    { "Chilini",      3, 0 },
    { "Kaosx",        2, 1 },
    { "Simondan",     2, 0 },
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

--- Ein Beispiel-Wurf zum Ansehen der Hervorhebung.
--  Bewusst gemischt: zwei mit vielen Stuecken, zwei mit wenigen, und
--  einer, der in der Historie gar nicht vorkommt — der Fall, der sonst
--  durchs Raster fiele.
function Quelle.BeispielWurf()
    local Wuerfe, namen = {}, {}
    local gewuerfelt = {
        { "Xalessa", 87 },
        { "Renbi",   64 },
        { "Deters",  41 },
        { "Nuhkomm", 93 },   -- taucht in der Beispiel-Historie nicht auf
        { "Velera",  12 },
    }
    for _, W in ipairs(gewuerfelt) do
        namen[#namen + 1] = W[1]
        Wuerfe[ns.Kern.Schluessel(W[1])] = W[2]
    end
    return { link = nil, name = "Zorn des Verräters", Wuerfe = Wuerfe, namen = namen }
end

return ns
