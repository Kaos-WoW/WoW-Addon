--[[----------------------------------------------------------------------
    Erfassung.lua  —  Vergaben selbst aufzeichnen

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
local L = ns.L

local Erfassung = {}
ns.Erfassung = Erfassung

local Kern = ns.Kern

local PRAEFIX = "|cff1B6B57Fairshare|r: "

-- Wie lange ein Wurf einer spaeteren Beutemeldung zugeordnet wird.
local WURFGEDAECHTNIS = 600   -- Sekunden

-- =====================================================================
--  Speicher und Einstellungen
-- =====================================================================

local function db()
    FairshareDB = FairshareDB or {}
    local d = FairshareDB
    d.vergaben = d.vergaben or {}
    -- Kennungen von Doppelgaengern, die verworfen wurden (siehe
    -- Kern.Zusammenfuehren). Sie zaehlen in der Pruefsumme mit.
    d.alias = d.alias or {}
    -- auto = Pluendermeister, sonst Leiter | immer | nie  (Rolle.lua)
    if d.schreiben == nil then d.schreiben = "auto" end
    -- Abweichende Historien in der Gruppe: der Leiter (Plündermeister) gleicht
    -- von selbst ab. Aus = nur ein Hinweis mit Knopf.
    if d.autoAbgleich == nil then d.autoAbgleich = true end
    if d.erfassen         == nil then d.erfassen = true end
    if d.nurGewuerfelt    == nil then d.nurGewuerfelt = false end

    -- ⚠️ SavedVariables sind eine Versionsgrenze. Frueher gab es nur den
    -- Schalter `nurRaid`; wer ihn gesetzt hat, soll seine Wahl behalten.
    if d.ort == nil then
        if d.nurRaid == false then d.ort = "ueberall" else d.ort = "raid" end
        d.nurRaid = nil
    end
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
--  @param art  bereits bekannte Bedarfsart; sonst aus dem Bereich
function Erfassung.WurfMerken(name, wert, min, max, art)
    art = art or Kern.Bedarfsart(min, max)
    if not art then return false end

    local k = Kern.Schluessel(name)
    if not k then return false end

    -- Beginnt hier eine neue Wurfrunde? Dann darf sich das Fenster oeffnen.
    local ersterDerRunde = Erfassung.AktuelleWuerfe() == nil

    -- Der juengste Wurf gilt: Wer nachtraeglich fuer Zweitbedarf wuerfelt,
    -- meint das auch so.
    Wuerfe[k] = { art = art, zeit = time(), wert = tonumber(wert) or 0, name = name }

    -- ⚠️ Ohne Gargul gibt es kein ROLLOFF_STARTED. Der erste Bedarfswurf
    -- einer Runde ist der beste Ersatz dafuer.
    if ns.Fenster then
        if ersterDerRunde and ns.Fenster.AutoOeffnen() then
            ns.Fenster.Zeigen(false)
        else
            ns.Fenster.Aktualisieren()
        end
    end

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

--- Die Wuerfe der letzten Minuten, in der Form, die das Fenster erwartet.
--
--  ⭐ Damit braucht die Wurf-Ansicht kein Gargul mehr. Was Gargul voraus
--  hat, ist der Gegenstand: Es weiss, WOFUER gewuerfelt wird. Aus dem
--  Chat allein laesst sich das nicht ablesen — die Reihenfolge und die
--  Hervorhebung stimmen trotzdem, und darum geht es.
--
--  @param fenster  Sekunden; was aelter ist, gilt als vorbei
--  @return { Wuerfe = { Schluessel -> Wert }, namen = { ... } } oder nil
function Erfassung.AktuelleWuerfe(fenster)
    fenster = fenster or 120
    local jetzt = time()

    local Werte, namen = {}, {}
    for k, W in pairs(Wuerfe) do
        if (jetzt - W.zeit) <= fenster then
            Werte[k] = W.wert
            namen[#namen + 1] = W.name
        end
    end

    if #namen == 0 then return nil end
    return { Wuerfe = Werte, namen = namen }
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

    -- Wo darf aufgezeichnet werden?
    --   raid     nur Schlachtzugsinstanzen (Echtbetrieb)
    --   instanz  auch Fuenfergruppen — zum Erproben des Ablaufs
    --   ueberall keine Einschraenkung; dann landen auch Weltdrops darin
    if d.ort ~= "ueberall" then
        local _, typ = IsInInstance()
        if d.ort == "raid" and typ ~= "raid" then
            return false, "kein Schlachtzug"
        elseif d.ort == "instanz" and typ ~= "raid" and typ ~= "party" then
            return false, "keine Instanz"
        end
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

--- Liegt dieselbe Vergabe schon vor?
--
--  ⚠️ Zwei Wege schreiben in dieselbe Historie: Blizzards Beute-Historie
--  (genau, mit Bedarfsart) und die Chat-Mitschrift (deckt auch
--  Meisterpluenderer ab). Fuer dasselbe Stueck kaemen sonst zwei Zeilen
--  mit verschiedenen Schluesseln heraus.
--
--  ⚠️ Der Preis: Gewinnt jemand zweimal denselben Gegenstand innerhalb
--  des Fensters, faellt der zweite weg. Das ist selten — systematisches
--  Doppelzaehlen waere schlimmer.
function Erfassung.SchonErfasst(name, id, zeit, fenster)
    if not id then return false end
    fenster = fenster or 180
    local k = Kern.Schluessel(name)
    if not k then return false end

    for eid, e in pairs(Erfassung.Historie()) do
        if e.itemID == id and Kern.Schluessel(e.awardedTo or "") == k
           and math.abs((e.timestamp or 0) - zeit) <= fenster then
            return true, eid, e
        end
    end
    return false
end

--- Traegt eine Vergabe ein.
--  @param art      "haupt" | "zweit" | nil (dann aus dem gemerkten Wurf)
--  @param kennung  eigener Schluessel; sonst aus Spieler, Stueck und Zeit
--  @param extra    optional { wurf = Zahl }
--  @return true wenn neu, die Art; oder false und ein Grund
--
--  ⭐ Nur der gewaehlte Schreiber (Rolle.lua) traegt ein. Alle anderen
--  bekommen die Eintraege ueber den Abgleich.
function Erfassung.Eintragen(name, link, zeit, art, kennung, extra)
    if not name or not link then return false, "unvollständig" end

    if ns.Rolle then
        local darf, grund = ns.Rolle.IchSchreibe()
        if not darf then return false, grund end
    end

    local id = tonumber(tostring(link):match("item:(%d+)"))
    local jetzt = zeit or (GetServerTime and GetServerTime()) or time()
    kennung = kennung or Erfassung.Kennung(name, id or link, jetzt)

    local V = Erfassung.Historie()
    if V[kennung] or db().alias[kennung] then return false, "schon vorhanden" end
    if Erfassung.SchonErfasst(name, id, jetzt) then return false, "schon vorhanden" end

    art = art or Erfassung.BedarfVon(name)

    V[kennung] = {
        awardedTo = name,
        itemID    = id,
        itemLink  = link,
        timestamp = jetzt,
        -- Ohne erkannte Bedarfsart gilt Hauptbedarf. Das ist die Annahme,
        -- die zulasten des Empfaengers geht — und damit die sichere.
        OS        = (art == "zweit") or nil,
        selbstErfasst = true,
        herkunft  = (extra and extra.herkunft)
                    or (kennung:find("^blizz:") and "blizzard" or "chat"),
        gruppe    = ns.Gruppen and ns.Gruppen.AktivName() or nil,
        wurf      = extra and extra.wurf or nil,
    }

    if ns.Abgleich then ns.Abgleich.Verteilen(kennung) end
    return true, art, kennung
end

-- =====================================================================
--  Gargul als Quelle
-- =====================================================================

--- ⭐ Eine Vergabe aus Gargul.
--
--  Gargul ist der Wuerfler, wir hoeren nur zu. Der Eintrag bringt mit, was
--  der Chat nie liefert: die Kennung, ob es Haupt- oder Zweitbedarf war
--  (`OS`) und die Wuerfe. Darum schlaegt er die Vermutung aus dem Chat.
--
--  ⚠️ Kam die Beutemeldung schon vorher an, liegt die Vergabe bereits da —
--  dann wird sie berichtigt, nicht doppelt eingetragen.
--
--  @param A  Garguls AwardEntry
function Erfassung.GargulVergabe(A)
    if not db().erfassen or type(A) ~= "table" then return false, "aus" end

    local zaehlt, grund = Kern.Zaehlt(A)
    if not zaehlt then return false, grund end

    local gegenstand = A.itemLink or (A.itemID and ("item:" .. A.itemID))
    if not gegenstand then return false, "ohne Gegenstand" end

    local ok, warum = Erfassung.Zaehlenswert(gegenstand, nil)
    if not ok then return false, warum end

    -- Der Wurf des Gewinners: der hoechste in der gewonnenen Klasse.
    local wurf
    for _, W in ipairs(A.Rolls or {}) do
        if Kern.GleicherSpieler(W.player, A.awardedTo) then
            local betrag = tonumber(W.amount)
            if betrag and (not wurf or betrag > wurf) then wurf = betrag end
        end
    end

    local itemID = A.itemID or tonumber(tostring(gegenstand):match("item:(%d+)"))
    local zeit = tonumber(A.timestamp) or (GetServerTime and GetServerTime()) or time()

    -- Schon durch die Beutemeldung erfasst? Dann berichtigen.
    local da, eid, e = Erfassung.SchonErfasst(A.awardedTo, itemID, zeit)
    if da and e then
        e.OS = A.OS and true or nil
        e.wurf = wurf or e.wurf
        e.herkunft = "gargul"
        return false, "berichtigt"
    end

    return Erfassung.Eintragen(A.awardedTo, gegenstand, zeit,
        A.OS and "zweit" or "haupt", A.checksum, { wurf = wurf, herkunft = "gargul" })
end

--- Gargul hat eine Vergabe geaendert (anderer Gewinner, Haupt/Zweit).
--  Die Kennung bleibt; nur die Felder werden nachgezogen.
--  ⚠️ Das gilt nur hier. Andere Spieler haben den alten Stand und
--  bekommen die Aenderung nicht — der Abgleich fuegt nur hinzu.
function Erfassung.GargulAenderung(A)
    if type(A) ~= "table" or not A.checksum then return false end
    local e = Erfassung.Historie()[A.checksum]
    if not e then return false end
    if A.awardedTo and A.awardedTo ~= "" then e.awardedTo = A.awardedTo end
    e.OS = A.OS and true or nil
    return true
end

--- Gargul hat eine Vergabe zurueckgenommen.
--  Der Eintrag bleibt liegen, zaehlt aber nicht mehr: Loeschen wuerde
--  der Abgleich beim naechsten Mal wieder hereinbringen.
function Erfassung.GargulZurueck(A)
    if type(A) ~= "table" or not A.checksum then return false end
    local e = Erfassung.Historie()[A.checksum]
    if not e then return false end
    e.zurueck = true
    -- Den anderen mitteilen, damit sie ihn ebenfalls nicht mehr zaehlen.
    if ns.Abgleich then ns.Abgleich.Verteilen(A.checksum) end
    return true
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
        print(PRAEFIX .. "|cffff5555" .. string.format(L["Fehler beim Aufzeichnen: %s"], tostring(fehler)) .. "|r")
    end
end)

-- Beim Laden schon einmal bauen, falls das Ereignis spaeter kommt.
Erfassung.MusterBauen()

return ns
