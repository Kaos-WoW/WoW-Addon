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

return ns
