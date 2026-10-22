--[[----------------------------------------------------------------------
    Quelle.lua  —  Woher die Vergaben kommen

    Die Historie ist die EIGENE (Erfassung.lua). Hier stehen die Zugriffe
    darauf, der laufende Wurf, die Anzeige der Gegenstaende und die
    Beispieldaten.
------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local Quelle = {}
ns.Quelle = Quelle

-- =====================================================================
--  Die Historie
-- =====================================================================

--- Die Historie, aus der ausgewertet wird: die EIGENE.
function Quelle.Historie()
    if not ns.Erfassung then return nil, L["Erfassung nicht geladen"] end
    return ns.Erfassung.Historie()
end

-- =====================================================================
--  Der laufende Wurf
-- =====================================================================

--- Wird gerade um einen Gegenstand gewuerfelt?
--
--  Die eigene Mitschrift (Erfassung.lua) kennt, wer gewuerfelt hat und mit
--  welchem Bereich (Haupt oder Zweit) — und genau das ordnet die Liste.
--  Ein Spieler kann mehrfach wuerfeln; gezaehlt wird der ERSTE Wurf.
--
--  @return { link, name, Wuerfe = { Schluessel -> Wurf }, Arten, namen = { Name, ... } }  oder nil
function Quelle.Wurf()
    return ns.Erfassung and ns.Erfassung.AktuelleWuerfe() or nil
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

--- Der Verweis fuer den Tooltip eines Gegenstands (Link oder "item:<Nummer>"), oder nil.
function Quelle.Gegenstandslink(eintrag)
    if type(eintrag) ~= "table" then return nil end
    if eintrag.itemLink then return eintrag.itemLink end
    if eintrag.itemID then return "item:" .. tostring(eintrag.itemID) end
    return nil
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
--  ⚠️ Schreibt NICHTS in die SavedVariables.
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
