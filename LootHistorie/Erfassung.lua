--[[----------------------------------------------------------------------
    Erfassung.lua  —  Vergaben selbst mitschreiben

    Das Addon braucht kein anderes Addon mehr: Es liest die Beutemeldungen
    aus dem Chat und fuehrt eine eigene Historie.

    ⭐ **Haupt- und Zweitbedarf kommen aus dem Wurfbereich.** Eine
    Beutemeldung allein sagt nur, wer etwas bekommen hat — nicht wofuer.
    Die Gilde wuerfelt `/rnd 100` fuer Haupt- und `/rnd 50` fuer
    Zweitbedarf, und `RANDOM_ROLL_RESULT` traegt den Bereich mit:

        %s rolls %d (%d-%d)

    Also merken wir uns die Wuerfe kurz und schlagen beim Beutefund nach.

    ⚠️ **Die Muster kommen aus Blizzards eigenen Textvorlagen**, nie aus
    hartkodiertem Deutsch oder Englisch. Sonst laeuft es in genau einer
    Sprachfassung.

    ⚠️ Gespeichert wird in **derselben Form wie Garguls Eintraege**
    (`awardedTo`, `itemID`, `timestamp`, `OS`). Dadurch liest `Kern` beide
    ohne Unterschied, und ein Import aus Gargul passt ohne Umrechnen.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Erfassung = {}
ns.Erfassung = Erfassung

local Kern = ns.Kern

local PRAEFIX = "|cff1B6B57Loot-Historie|r: "

-- Wie lange ein Wurf einer spaeteren Beutemeldung zugeordnet wird.
local WURFGEDAECHTNIS = 600   -- Sekunden

-- =====================================================================
--  Speicher und Einstellungen
-- =====================================================================

local function db()
    LootHistorieDB = LootHistorieDB or {}
    local d = LootHistorieDB
    d.vergaben = d.vergaben or {}
    if d.erfassen         == nil then d.erfassen = true end
    if d.nurRaid          == nil then d.nurRaid = true end
    if d.nurGewuerfelt    == nil then d.nurGewuerfelt = false end
    -- ⭐ Standard ist SELTEN, nicht Episch. Auf Stufe 60 ist unklar, ob in
    -- den Raids ueberhaupt episch faellt — in Zul'Gurub etwa ist das meiste
    -- blau. Und die Asymmetrie ist eindeutig: ein verpasster Drop ist
    -- unwiederbringlich, eine Zeile zu viel nur laestig.
    if d.mindestQualitaet == nil then d.mindestQualitaet = 3 end
    return d
end

Erfassung.Einstellungen = db

--- Die eigene Historie.
function Erfassung.Historie()
    return db().vergaben
end

-- =====================================================================
--  Muster aus den Textvorlagen
-- =====================================================================

local Muster = { beute = {}, wurf = nil }

--- Baut die Suchmuster aus den GlobalStrings.
--  ⚠️ Jede Vorlage einzeln pruefen: Fehlt eine, faellt nur sie aus.
function Erfassung.MusterBauen()
    Muster.beute = {}

    -- { Vorlagenname, hat einen Empfaengernamen, hat eine Anzahl }
    local Vorlagen = {
        { "LOOT_ITEM",               true,  false },
        { "LOOT_ITEM_MULTIPLE",      true,  true  },
        { "LOOT_ITEM_SELF",          false, false },
        { "LOOT_ITEM_SELF_MULTIPLE", false, true  },
    }

    for _, V in ipairs(Vorlagen) do
        local vorlage = rawget(_G, V[1])
        if type(vorlage) == "string" then
            local muster = Kern.Muster(vorlage)
            if muster then
                Muster.beute[#Muster.beute + 1] =
                    { muster = muster, mitName = V[2], mitAnzahl = V[3], quelle = V[1] }
            end
        end
    end

    -- Die laengeren Vorlagen zuerst: „…x5." wuerde sonst von der
    -- kuerzeren Fassung mitgefressen und die Anzahl ginge verloren.
    table.sort(Muster.beute, function(a, b) return #a.muster > #b.muster end)

    local wurfVorlage = rawget(_G, "RANDOM_ROLL_RESULT")
    Muster.wurf = type(wurfVorlage) == "string" and Kern.Muster(wurfVorlage) or nil

    return #Muster.beute, Muster.wurf ~= nil
end

function Erfassung.Muster()
    return Muster
end

-- =====================================================================
--  Wuerfe merken
-- =====================================================================

local Wuerfe = {}   -- Schluessel -> { art, zeit, wert }

--- Merkt sich einen Bedarfswurf.
function Erfassung.WurfMerken(name, wert, min, max)
    local art = Kern.Bedarfsart(min, max)
    if not art then return false end

    local k = Kern.Schluessel(name)
    if not k then return false end

    -- Der juengste Wurf gilt: Wer nachtraeglich fuer Zweitbedarf wuerfelt,
    -- meint das auch so.
    Wuerfe[k] = { art = art, zeit = time(), wert = tonumber(wert) or 0, name = name }
    return true, art
end

--- Wofuer hat dieser Spieler zuletzt gewuerfelt?
--  @return "haupt" | "zweit" | nil
function Erfassung.BedarfVon(name)
    local k = Kern.Schluessel(name)
    local W = k and Wuerfe[k]
    if not W then return nil end
    if (time() - W.zeit) > WURFGEDAECHTNIS then return nil end
    return W.art
end

function Erfassung.OffeneWuerfe()
    local n = 0
    for _, W in pairs(Wuerfe) do
        if (time() - W.zeit) <= WURFGEDAECHTNIS then n = n + 1 end
    end
    return n
end

function Erfassung.WuerfeVergessen()
    Wuerfe = {}
end

-- =====================================================================
--  Beute bewerten
-- =====================================================================

--- Soll dieser Gegenstand in die Historie?
--  @param name  Empfaenger, fuer die Pruefung auf einen Bedarfswurf
--  @return true, oder false und der Grund
function Erfassung.Zaehlenswert(link, name)
    local d = db()

    -- Strengste Einstellung: nur, was auch ausgewuerfelt wurde. Damit
    -- faellt jeder Trash-Aufsammler heraus, unabhaengig von der Qualitaet.
    -- ⚠️ Aus gutem Grund nicht Standard: Teilt die Leitung ohne Wurf zu,
    -- ginge die Vergabe verloren.
    if d.nurGewuerfelt and name and not Erfassung.BedarfVon(name) then
        return false, "kein Bedarfswurf"
    end

    if d.nurRaid then
        local _, typ = IsInInstance()
        if typ ~= "raid" then return false, "kein Schlachtzug" end
    end

    local CI = rawget(_G, "C_Item")
    local voll = (CI and CI.GetItemInfo) or rawget(_G, "GetItemInfo")
    if not voll then return true end   -- ohne Auskunft lieber erfassen

    local ok, _, _, qualitaet = pcall(voll, link)
    if not ok or not qualitaet then
        -- ⚠️ Kennt der Client den Gegenstand noch nicht, wird erfasst.
        -- Eine verlorene Vergabe waere schlimmer als eine Zeile zu viel.
        return true
    end

    if qualitaet < d.mindestQualitaet then
        return false, "Qualität zu niedrig"
    end
    return true
end

-- =====================================================================
--  Eintragen
-- =====================================================================

--- Kennung einer Vergabe.
--  ⚠️ Bewusst aus Serverzeit, Spieler und Gegenstand gebildet: Zwei
--  Raidleiter sehen dieselbe Beutemeldung und errechnen dieselbe
--  Kennung. Damit doppelt sich beim spaeteren Abgleich nichts.
function Erfassung.Kennung(name, gegenstand, zeit)
    return string.format("%s:%s:%d",
        Kern.Schluessel(name) or "?", tostring(gegenstand or "?"), zeit or 0)
end

--- Traegt eine Vergabe ein.
--  @return true wenn neu
function Erfassung.Eintragen(name, link, zeit)
    if not name or not link then return false end

    local id = tonumber(link:match("item:(%d+)"))
    local jetzt = zeit or (GetServerTime and GetServerTime()) or time()
    local kennung = Erfassung.Kennung(name, id or link, jetzt)

    local V = Erfassung.Historie()
    if V[kennung] then return false end

    local art = Erfassung.BedarfVon(name)

    V[kennung] = {
        awardedTo = name,
        itemID    = id,
        itemLink  = link,
        timestamp = jetzt,
        -- Ohne erkannten Wurf gilt Hauptbedarf. Das ist die Annahme, die
        -- zulasten des Empfaengers geht — und damit die sichere.
        OS        = (art == "zweit") or nil,
        selbstErfasst = true,
    }
    return true, art
end

-- =====================================================================
--  Chat auswerten
-- =====================================================================

local function eigenerName()
    if GetUnitName then
        -- ⚠️ In Forever hat ein Charakter einen Nachnamen. UnitName gibt
        -- ihn als ZWEITEN Wert zurueck (nicht den Realm!); GetUnitName
        -- mit showSurname setzt ihn richtig zusammen.
        local n = GetUnitName("player", true)
        if n and n ~= "" then return n end
    end
    return (UnitName("player"))
end

--- Eine Beutemeldung auswerten.
function Erfassung.Beutemeldung(text)
    if not db().erfassen or type(text) ~= "string" then return end

    for _, M in ipairs(Muster.beute) do
        if M.mitName then
            local wer, was = text:match(M.muster)
            if wer and was then
                if Erfassung.Zaehlenswert(was, wer) then
                    Erfassung.Eintragen(wer, was)
                end
                return
            end
        else
            local was = text:match(M.muster)
            if was then
                local ich = eigenerName()
                if Erfassung.Zaehlenswert(was, ich) then
                    Erfassung.Eintragen(ich, was)
                end
                return
            end
        end
    end
end

--- Eine Systemmeldung auf einen Wurf pruefen.
function Erfassung.Systemmeldung(text)
    if not Muster.wurf or type(text) ~= "string" then return end
    local wer, wert, min, max = text:match(Muster.wurf)
    if wer then Erfassung.WurfMerken(wer, wert, min, max) end
end

-- =====================================================================
--  Ereignisse
-- =====================================================================

local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:RegisterEvent("CHAT_MSG_LOOT")
rahmen:RegisterEvent("CHAT_MSG_SYSTEM")
rahmen:SetScript("OnEvent", function(_, ereignis, a1)
    if ereignis == "PLAYER_ENTERING_WORLD" then
        Erfassung.MusterBauen()
        return
    end

    -- ⚠️ Ein Fehler hier darf nicht den Chat mitreissen.
    local ok, fehler = pcall(function()
        if ereignis == "CHAT_MSG_LOOT" then
            Erfassung.Beutemeldung(a1)
        else
            Erfassung.Systemmeldung(a1)
        end
    end)
    if not ok then
        print(PRAEFIX .. "|cffff5555Fehler beim Mitschreiben: " .. tostring(fehler) .. "|r")
    end
end)

-- Beim Laden schon einmal bauen, falls das Ereignis spaeter kommt.
Erfassung.MusterBauen()

return ns
