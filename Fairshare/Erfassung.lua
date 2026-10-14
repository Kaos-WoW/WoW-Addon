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
    -- ⭐ Der Pluendermeister steckt die Beute oft selbst ein und verteilt sie
    -- spaeter per Handel. Was er dabei aufnimmt, ist noch keine Vergabe.
    if d.pmEingesteckt    == nil then d.pmEingesteckt = true end
    -- Jede eingetragene Vergabe im Raid-/Gruppenchat ansagen (nur der Aufzeichner)
    if d.ansagen          == nil then d.ansagen = true end
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

-- =====================================================================
--  Wuerfelbereiche (einstellbar)
-- =====================================================================

--- Die eingestellten Bereiche (Kopie).
--  @return { haupt = { min, max }, zweit = { min, max } }
function Erfassung.Bereiche()
    local b = db().bereiche
    local h = (type(b) == "table" and type(b.haupt) == "table") and b.haupt or { 1, 100 }
    local z = (type(b) == "table" and type(b.zweit) == "table") and b.zweit or { 1, 50 }
    return { haupt = { h[1], h[2] }, zweit = { z[1], z[2] } }
end

--- Bringt die gespeicherten Bereiche in Kern. Ohne Einstellung (oder bei
--  unbrauchbaren Werten) gilt 1-100 und 1-50.
function Erfassung.BereicheAnwenden()
    local b = Erfassung.Bereiche()
    if not Kern.BereicheSetzen(b.haupt[1], b.haupt[2], b.zweit[1], b.zweit[2]) then
        Kern.BereicheSetzen(1, 100, 1, 50)
    end
end

--- Stellt beide Bereiche ein und speichert sie.
--  @return true, oder false und ein Text fuer den Spieler
function Erfassung.BereicheSetzen(h1, h2, z1, z2)
    local ok, code = Kern.BereicheSetzen(h1, h2, z1, z2)
    if not ok then
        if code == "zahl" then return false, L["Bitte ganze Zahlen eingeben."] end
        if code == "gleich" then return false, L["Haupt- und Zweitbedarf dürfen nicht denselben Bereich haben."] end
        return false, L["Erlaubt sind ganze Zahlen von 1 bis 10000; die obere muss größer sein als die untere."]
    end
    local B = Kern.BEREICHE
    db().bereiche = { haupt = { B.haupt[1], B.haupt[2] }, zweit = { B.zweit[1], B.zweit[2] } }
    return true
end

--- Einen der beiden Bereiche aendern.
--  @param art  "haupt" | "zweit"
function Erfassung.BereichSetzen(art, min, max)
    local b = Erfassung.Bereiche()
    if art == "haupt" then
        return Erfassung.BereicheSetzen(min, max, b.zweit[1], b.zweit[2])
    end
    return Erfassung.BereicheSetzen(b.haupt[1], b.haupt[2], min, max)
end

--- Die eigene Historie.
function Erfassung.Historie()
    return db().vergaben
end

-- =====================================================================
--  Muster aus den Textvorlagen
-- =====================================================================

local Muster = { beute = {}, wurf = nil, wuerfe = {} }

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

    -- ⭐ Blizzards Wuerfelfenster (Bedarf / Gier) meldet im Chat:
    --     „Need Roll - 87 for [Item] by Name"   (der Wurf)
    --     „Name has selected Need for: [Item]"  (die Wahl, sofort)
    --     „Name passed on: [Item]"              (Verzicht)
    -- Bedarf = Hauptbedarf, Gier = Zweitbedarf (wie in Blizzbeute.lua).
    -- Je Eintrag: { Vorlagenname, Art, Aktion, Argumentnummern }
    -- ⚠️ Uebersetzte Vorlagen duerfen die Reihenfolge umstellen — darum die
    -- Zuordnung ueber Kern.MusterGeordnet.
    local W3 = { wert = 1, item = 2, name = 3 }
    local WurfVorlagen = {
        { "LOOT_ROLL_ROLLED_NEED",            "haupt", "wurf", W3 },
        { "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "haupt", "wurf", W3 },
        { "LOOT_ROLL_ROLLED_GREED",           "zweit", "wurf", W3 },
        { "LOOT_ROLL_ROLLED_TRANSMOG",        "zweit", "wurf", W3 },
        { "LOOT_ROLL_NEED",        "haupt", "wahl", { name = 1, item = 2 } },
        { "LOOT_ROLL_NEED_SELF",   "haupt", "wahl", { item = 1, ich = true } },
        { "LOOT_ROLL_GREED",       "zweit", "wahl", { name = 1, item = 2 } },
        { "LOOT_ROLL_GREED_SELF",  "zweit", "wahl", { item = 1, ich = true } },
        { "LOOT_ROLL_TRANSMOG",      "zweit", "wahl", { name = 1, item = 2 } },
        { "LOOT_ROLL_TRANSMOG_SELF", "zweit", "wahl", { item = 1, ich = true } },
        { "LOOT_ROLL_PASSED",      nil, "pass", { name = 1, item = 2 } },
        { "LOOT_ROLL_PASSED_SELF", nil, "pass", { item = 1, ich = true } },
        -- Die Runde ist entschieden
        { "LOOT_ROLL_WON",         nil, "ende", { name = 1, item = 2 } },
        { "LOOT_ROLL_YOU_WON",     nil, "ende", { item = 1 } },
        { "LOOT_ROLL_ALL_PASSED",  nil, "ende", { item = 1 } },
    }

    Muster.wuerfe = {}
    for _, V in ipairs(WurfVorlagen) do
        local vorlage = rawget(_G, V[1])
        if type(vorlage) == "string" then
            local muster, nummern = Kern.MusterGeordnet(vorlage)
            if muster then
                Muster.wuerfe[#Muster.wuerfe + 1] =
                    { muster = muster, nummern = nummern, art = V[2], aktion = V[3], arg = V[4], quelle = V[1] }
            end
        end
    end
    -- Die laengere zuerst: „Need Roll - %d for %s by %s" darf die Fassung
    -- „… + Role Bonus" nicht mit einem falschen Namen verschlucken.
    table.sort(Muster.wuerfe, function(a, b) return #a.muster > #b.muster end)

    return #Muster.beute, Muster.wurf ~= nil
end

function Erfassung.Muster()
    return Muster
end

-- =====================================================================
--  Wuerfe merken
-- =====================================================================

local Wuerfe = {}   -- Schluessel -> { art, zeit, wert }: der letzte Wurf je Spieler

-- ⭐ Je Gegenstand eine Wurfrunde. Blizzards Fenster wuerfelt oft mehrere
-- Gegenstaende zugleich; in EINER Liste gemischt waeren sie unlesbar.
-- Gegenstandsnummer -> { link, zeit, Spieler = { Schluessel -> { name, art, wert } } }
-- (Nummer "" = Wuerfe ohne bekannten Gegenstand, z. B. ein getipptes /rnd.)
local Runden = {}

local function gegenstandsKey(link)
    if type(link) ~= "string" or link == "" then return "" end
    return link:match("item:(%d+)") or link
end

local function runde(link, anlegen)
    local key = gegenstandsKey(link)
    local r = Runden[key]
    if not r and anlegen then
        r = { link = (key ~= "") and link or nil, zeit = time(), Spieler = {} }
        Runden[key] = r
    end
    return r
end

--- Fenster auffrischen, bei Bedarf (neue Runde) von selbst oeffnen.
local function fensterAnstossen(oeffnen)
    if not ns.Fenster then return end
    if oeffnen and ns.Fenster.AutoOeffnen() then
        ns.Fenster.Zeigen(false)
    else
        ns.Fenster.Aktualisieren()
    end
end

--- Merkt sich einen Bedarfswurf oder eine Bedarfsmeldung.
--  @param art   bereits bekannte Bedarfsart; sonst aus dem Bereich
--  @param wert  nil = Spieler hat „Bedarf" gewaehlt, der Wurf steht noch aus
--  @param link  der Gegenstand, falls bekannt (trennt gleichzeitige Wuerfe)
function Erfassung.WurfMerken(name, wert, min, max, art, link)
    art = art or Kern.Bedarfsart(min, max)
    if not art then return false end

    local k = Kern.Schluessel(name)
    if not k then return false end

    -- Beginnt hier eine neue Wurfrunde? Dann darf sich das Fenster oeffnen.
    local ersterDerRunde = Erfassung.AktuelleWuerfe() == nil

    -- 0 und nil heissen „noch nicht gewuerfelt" und ueberschreiben nie einen
    -- bekannten Wert.
    local zahl = tonumber(wert)
    if zahl and zahl <= 0 then zahl = nil end

    local r = runde(link, true)
    local S = r.Spieler[k]

    -- ⭐ Der ERSTE Wurf gilt. Wer fuenfmal wuerfelt, bekommt den ersten Wurf
    -- gewertet — sonst wuerfe man so lange, bis es passt (Nutzerhinweis
    -- 14.10.2026). Ein Spieler, der nur gewaehlt hat, darf noch wuerfeln.
    -- ⚠️ Ohne bekannten Gegenstand (getipptes /rnd) weiss das Addon nicht,
    -- wann eine neue Runde beginnt; dort zaehlt ein Wurf nach 60 s als neu.
    if S and S.wert > 0 then
        local neueRunde = (r.link == nil) and S.zeit and (time() - S.zeit) > 60
        if not neueRunde then return false, "schon gewürfelt" end
    end

    r.zeit = time()
    r.Spieler[k] = { name = name, art = art, wert = zahl or 0, zeit = time() }

    local alt = Wuerfe[k]
    Wuerfe[k] = { art = art, zeit = time(), wert = zahl or (alt and alt.wert) or 0, name = name }

    -- ⚠️ Ohne Gargul gibt es kein ROLLOFF_STARTED. Der erste Bedarfswurf
    -- einer Runde ist der beste Ersatz dafuer.
    fensterAnstossen(ersterDerRunde)

    return true, art
end

--- Blizzards Wuerfelfenster geht fuer einen Gegenstand auf (START_LOOT_ROLL).
--  Das Fenster zeigt ab jetzt „Wurf laeuft", auch bevor jemand gewaehlt hat.
--  @param oeffnen  false: die Runde anlegen, die Uebersicht aber nicht aufspringen
--                  lassen (Wurf.lua: nur der Leiter braucht sie)
function Erfassung.WurfBeginnt(link, oeffnen)
    -- ⭐ Ein neuer Wurf ist eine NEUE Runde. Blieb die alte (gleicher Gegenstand,
    -- etwa zweimal dasselbe Stueck oder ein Wurf nach einer Ruecknahme) stehen,
    -- galten die alten Wuerfe weiter: Spieler, die schon gewuerfelt hatten,
    -- waren gesperrt, und der Leiter sah veraltete Zahlen.
    if gegenstandsKey(link) ~= "" then Runden[gegenstandsKey(link)] = nil end
    local r = runde(link, true)
    r.zeit = time()
    fensterAnstossen(oeffnen ~= false)
end

--- Der Wurf eines Spielers in der Runde dieses Gegenstands.
--  @return Wert, Art  oder nil
function Erfassung.WurfVon(name, link)
    local r = runde(link, false)
    if not r then return nil end
    local k = Kern.Schluessel(name)
    local P = k and r.Spieler[k]
    if P then return P.wert, P.art end
    for _, X in pairs(r.Spieler) do
        if Kern.GleicherSpieler(X.name, name) then return X.wert, X.art end
    end
    return nil
end

--- Ein Spieler verzichtet („passt") auf den Gegenstand.
function Erfassung.WurfZurueckziehen(name, link)
    local k = Kern.Schluessel(name)
    if not k then return end
    local r = runde(link, false)
    if r and r.Spieler[k] then
        r.Spieler[k] = nil
        fensterAnstossen(false)
    end
end

--- Der Gegenstand ist vergeben: seine Runde ist vorbei.
function Erfassung.RundeBeenden(link)
    local key = gegenstandsKey(link)
    if key ~= "" and Runden[key] then
        Runden[key] = nil
        fensterAnstossen(false)
    end
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
--  Gezeigt wird die Runde mit der juengsten Bewegung (bei mehreren
--  Gegenstaenden gleichzeitig also der, an dem gerade etwas passiert).
--
--  @param fenster  Sekunden; was aelter ist, gilt als vorbei
--  @return { Wuerfe = { Schluessel -> Wert }, Arten = { Schluessel -> "haupt"|"zweit" },
--            namen = { ... }, link = Gegenstand oder nil } oder nil
function Erfassung.AktuelleWuerfe(fenster)
    fenster = fenster or 120
    local jetzt = time()

    local beste
    for key, r in pairs(Runden) do
        if (jetzt - r.zeit) > fenster then
            Runden[key] = nil
        elseif not beste or r.zeit > beste.zeit then
            beste = r
        end
    end
    if not beste then return nil end

    local Werte, Arten, namen = {}, {}, {}
    for k, S in pairs(beste.Spieler) do
        Werte[k] = S.wert
        Arten[k] = S.art
        namen[#namen + 1] = S.name
    end
    return { Wuerfe = Werte, Arten = Arten, namen = namen, link = beste.link }
end

function Erfassung.OffeneWuerfe()
    local n = 0
    for _, W in pairs(Wuerfe) do
        if (time() - W.zeit) <= WURFGEDAECHTNIS then n = n + 1 end
    end
    return n
end

--- ⭐ Wurf abgebrochen: die Runde dieses Gegenstands verschwindet, ihre Wuerfe
--  zaehlen nirgends (falscher Gegenstand verrollt).
function Erfassung.RundeVerwerfen(link)
    local key = gegenstandsKey(link)
    if key ~= "" and Runden[key] then
        Runden[key] = nil
        fensterAnstossen(false)
    end
end

function Erfassung.WuerfeVergessen()
    Wuerfe = {}
    Runden = {}
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

--- ⭐ Eine Zeile im Raid- oder Gruppenchat: „[Gegenstand] wurde an X vergeben!"
--  Nur der Aufzeichner (hier laeuft nur sein Eintragen), und nur dort, wo
--  sonst niemand etwas sagt: bei Vergaben ueber das Wuerfelfenster und bei
--  Zuteilung durch den Pluendermeister. Blizzards Gruppenwuerfe und Gargul
--  melden selbst.
function Erfassung.Ansagen(name, link, art, herkunft)
    if db().ansagen == false then return end

    local erlaubt = (herkunft == "wurf")
    if herkunft == "chat" and ns.Rolle then
        local _, methode = ns.Rolle.Kandidaten()
        erlaubt = (methode == "master")
    end
    if not erlaubt then return end

    local kanal = (IsInRaid and IsInRaid()) and "RAID" or ((IsInGroup and IsInGroup()) and "PARTY" or nil)
    local senden = (C_ChatInfo and C_ChatInfo.SendChatMessage) or rawget(_G, "SendChatMessage")
    if not kanal or type(senden) ~= "function" then return end

    local text = string.format(art == "zweit" and L["%s wurde an %s vergeben! (OS)"] or L["%s wurde an %s vergeben!"],
        link, Kern.Anzeigename(name))
    pcall(senden, text, kanal)
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

    -- Vergeben: die Wurfanzeige dieses Gegenstands endet, auch ohne Beutemeldung
    -- (ein Handel liefert keine).
    Erfassung.RundeBeenden(link)
    if ns.Wurf and ns.Wurf.Vergeben then ns.Wurf.Vergeben(link) end
    Erfassung.Ansagen(name, link, art, V[kennung].herkunft)
    return true, art, kennung
end

-- =====================================================================
--  Zuruecksetzen
-- =====================================================================

local function zaehle(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

--- ⭐ Leert die Historie DIESES Rechners (Einstellungen und Gruppen bleiben).
--  Vorher wird sie gesichert (eine Sicherung, die naechste ersetzt sie), damit
--  sich ein Versehen zuruecknehmen laesst.
--
--  ⚠️ Es loescht nur hier. Haben andere in der Gruppe die Eintraege noch,
--  bringt der naechste Abgleich sie zurueck — das ist Absicht (nur Hinzufuegen).
--  @return Zahl der entfernten Eintraege
function Erfassung.Zuruecksetzen()
    local d = db()
    local n = zaehle(d.vergaben)
    d.sicherung = { zeit = time(), n = n, vergaben = d.vergaben, alias = d.alias }
    d.vergaben, d.alias = {}, {}
    if ns.Abgleich then
        ns.Abgleich.HalloSpaeter(2)
        ns.Abgleich.Pruefen()
    end
    return n
end

--- Die Sicherung vor dem letzten Zuruecksetzen.
--  @return { n =, zeit = } oder nil
function Erfassung.SicherungInfo()
    local s = db().sicherung
    return s and { n = s.n or zaehle(s.vergaben), zeit = s.zeit } or nil
end

--- Spielt die Sicherung wieder ein. Nichts, was inzwischen neu dazukam,
--  geht verloren (es wird zusammengefuehrt, nicht ersetzt).
--  @return Zahl der zurueckgeholten Eintraege, oder nil wenn es keine gibt
function Erfassung.Wiederherstellen()
    local d = db()
    local s = d.sicherung
    if not s then return nil end
    local n = 0
    for id, e in pairs(s.vergaben or {}) do
        if not d.vergaben[id] then
            d.vergaben[id] = e
            n = n + 1
        end
    end
    for id, ziel in pairs(s.alias or {}) do
        if not d.alias[id] then d.alias[id] = ziel end
    end
    d.sicherung = nil
    if ns.Abgleich then
        ns.Abgleich.HalloSpaeter(2)
        ns.Abgleich.Pruefen()
    end
    return n
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

--- ⭐ Eine Vergabe zuruecknehmen (falsch zugeteilt, jemand gibt sie zurueck).
--  Der Eintrag bleibt liegen, zaehlt aber nicht mehr — Loeschen brachte der
--  Abgleich zurueck. Das Merkmal geht an die Gruppe (live) und wird beim
--  naechsten Abgleich auch bei allen nachgezogen, die nicht dabei waren.
--  ⚠️ Es laesst sich nicht wieder aufheben (das macht das Zusammenfuehren
--  eindeutig): Ein Versehen korrigiert man mit einer neuen Vergabe.
function Erfassung.DarfZuruecknehmen()
    if not (IsInGroup and IsInGroup()) then return true end
    return (ns.Rolle and ns.Rolle.Berechtigt(eigenerName())) and true or false
end

--- @return true und der Eintrag, oder false und ein Grund
function Erfassung.Zuruecknehmen(id)
    local e = Erfassung.Historie()[id]
    if not e then return false, L["Eintrag nicht gefunden."] end
    if e.zurueck then return false, L["Schon zurückgenommen."] end
    if not Erfassung.DarfZuruecknehmen() then
        return false, L["Nur Leiter, Assistenten und der Plündermeister dürfen eine Vergabe zurücknehmen."]
    end
    e.zurueck = true
    if ns.Abgleich then
        ns.Abgleich.Verteilen(id)
        ns.Abgleich.HalloSpaeter(2)
    end
    return true, e
end

--- ⭐ Steckt der Pluendermeister die Beute selbst ein, ist das keine Vergabe:
--  Er verteilt sie spaeter (Wurf.lua traegt dann den Gewinner ein).
local function eingesteckt(name)
    if db().pmEingesteckt == false then return false end
    if not (ns.Rolle and ns.Rolle.IchBinPluendermeister()) then return false end
    return Kern.GleicherSpieler(name, eigenerName()) and true or false
end

--- Eine Beutemeldung auswerten.
function Erfassung.Beutemeldung(text)
    if not db().erfassen or type(text) ~= "string" then return end

    for _, M in ipairs(Muster.beute) do
        if M.mitName then
            local wer, was = text:match(M.muster)
            if wer and was then
                if Erfassung.Zaehlenswert(was, wer) and not eingesteckt(wer) then
                    Erfassung.Eintragen(wer, was)
                end
                Erfassung.RundeBeenden(was)   -- vergeben: die Wurfanzeige endet
                return
            end
        else
            local was = text:match(M.muster)
            if was then
                local ich = eigenerName()
                if Erfassung.Zaehlenswert(was, ich) and not eingesteckt(ich) then
                    Erfassung.Eintragen(ich, was)
                end
                Erfassung.RundeBeenden(was)
                return
            end
        end
    end
end

--- Eine Meldung aus Blizzards Wuerfelfenster auswerten.
--  @return true, wenn es eine solche Meldung war (dann ist es keine Beute)
function Erfassung.Wurfmeldung(text)
    if type(text) ~= "string" then return false end

    for _, M in ipairs(Muster.wuerfe) do
        local A = Kern.Argumente(text, M.muster, M.nummern)
        if A then
            local name = M.arg.ich and eigenerName() or A[M.arg.name]
            local link = A[M.arg.item]
            if M.aktion == "ende" then
                Erfassung.RundeBeenden(link)
            elseif name and name ~= "" then
                if M.aktion == "wurf" then
                    Erfassung.WurfMerken(name, A[M.arg.wert], nil, nil, M.art, link)
                elseif M.aktion == "wahl" then
                    Erfassung.WurfMerken(name, nil, nil, nil, M.art, link)
                else
                    Erfassung.WurfZurueckziehen(name, link)
                end
            end
            return true
        end
    end
    return false
end

--- Eine Systemmeldung auf einen Wurf pruefen.
function Erfassung.Systemmeldung(text)
    if not Muster.wurf or type(text) ~= "string" then return end
    local wer, wert, min, max = text:match(Muster.wurf)
    if wer then
        -- Laeuft ein Wurf aus Wurf.lua, gehoert der Wurf zu dessen Gegenstand.
        local link = ns.Wurf and ns.Wurf.AktuellerLink()
        Erfassung.WurfMerken(wer, wert, min, max, nil, link)
    end
end

-- =====================================================================
--  Ereignisse
-- =====================================================================

local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:RegisterEvent("CHAT_MSG_LOOT")
rahmen:RegisterEvent("CHAT_MSG_SYSTEM")
-- Blizzards Wuerfelfenster geht auf. ⚠️ Nicht jede Fassung kennt das Ereignis.
pcall(function() rahmen:RegisterEvent("START_LOOT_ROLL") end)

--- Der Gegenstand einer Wuerfelrunde (nur lesen, alles geprueft).
local function wurfGegenstand(rollID)
    local f = rawget(_G, "GetLootRollItemLink")
    if type(f) ~= "function" then return nil end
    local ok, link = pcall(f, rollID)
    if ok and type(link) == "string" then return link end
    return nil
end

rahmen:SetScript("OnEvent", function(_, ereignis, a1)
    if ereignis == "PLAYER_ENTERING_WORLD" then
        Erfassung.MusterBauen()
        -- Die gespeicherten Daten sind erst jetzt sicher da.
        pcall(Erfassung.BereicheAnwenden)
        return
    end

    -- ⚠️ Ein Fehler hier darf nicht den Chat mitreissen.
    local ok, fehler = pcall(function()
        if ereignis == "START_LOOT_ROLL" then
            Erfassung.WurfBeginnt(wurfGegenstand(a1))
        elseif ereignis == "CHAT_MSG_LOOT" then
            if not Erfassung.Wurfmeldung(a1) then Erfassung.Beutemeldung(a1) end
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
