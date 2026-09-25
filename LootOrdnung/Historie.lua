--[[----------------------------------------------------------------------
    Historie.lua  —  Wer hat über Wochen wie viele Gegenstände bekommen

    ⭐ **Das hier ist ein Leser, keine zweite Datenbank.** Gargul fuehrt
    die Vergaben ohnehin dauerhaft in `Gargul.DB.AwardHistory`, nach
    Pruefsumme abgelegt, und beschneidet sie nie. Und weil Gargul jede
    Vergabe an die Gruppe verteilt (`storeReceivedAward` beim Empfaenger),
    waechst bei allen Raidleitern dieselbe Liste.

    Daraus folgt: kein eigener Speicher, kein Abgleich, kein
    Zusammenfuehren, kein Export-String. Nichts davon kann auseinander-
    laufen, weil es nur eine Quelle gibt.

    ⚠️ Gargul oeffnet sich selbst fuer Fremdzugriff (`_G.Gargul = GL;
    -- Open Gargul up to other developer integrations`). Wir lesen nur
    und schreiben nie hinein.

    Jede Auswertung nimmt die Quelle als Parameter. Dadurch laesst sich
    dieselbe Anzeige mit Beispieldaten fuettern, ohne irgendwo etwas
    abzulegen — siehe Historie.Beispiel.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Historie = {}
ns.Historie = Historie

-- Gargul setzt diesen Namen fuer entzauberte Gegenstaende als Gewinner ein.
local ENTZAUBERT = "||de||"

local WOCHE = 604800
local TAG   = 86400

-- =====================================================================
--  Quelle
-- =====================================================================

--- Garguls Vergabe-Historie, oder nil.
--  @return tabelle (Pruefsumme -> Eintrag), oder nil und ein Grund
function Historie.Quelle()
    local GL = rawget(_G, "Gargul")
    if not GL then return nil, "Gargul ist nicht geladen" end
    local DB = GL.DB
    if not DB then return nil, "Gargul ist noch nicht bereit" end
    local H = DB.AwardHistory
    if type(H) ~= "table" then return nil, "Gargul hat noch keine Vergaben aufgezeichnet" end
    return H
end

--- Zaehlt einer Vergabe ueberhaupt?
--  Bonus-Beute und entzauberte Gegenstaende sind keine Zuteilung an
--  einen Spieler. Ohne Gewinner oder Zeit ist ein Eintrag unbrauchbar.
local function zaehlt(e)
    if type(e) ~= "table" then return false end
    if not e.awardedTo or e.awardedTo == "" then return false end
    if e.awardedTo == ENTZAUBERT then return false end
    if e.isBonusLoot then return false end
    if not tonumber(e.timestamp) then return false end
    return true
end

--- Schluessel je Spieler.
--  ⚠️ Gargul schreibt den Gewinner mal mit, mal ohne Realm — je nachdem,
--  ob die Vergabe lokal entstand oder ueber die Gruppe hereinkam.
--  Ohne Vereinheitlichung taucht derselbe Spieler zweimal auf.
--  Das setzt eine Gilde auf einem Realm voraus; bei Fremdrealmern
--  liefen zwei Gleichnamige zusammen.
local function schluessel(name)
    return (name:match("^([^%-]+)") or name):lower()
end

local function anzeigename(name)
    local kurz = name:match("^([^%-]+)") or name
    return kurz:sub(1, 1):upper() .. kurz:sub(2)
end

--- Wie ein Gegenstand angezeigt wird.
--  Echte Eintraege tragen den Verweis mit; sonst wird er nachgeschlagen.
--  Kennt der Client den Gegenstand nicht, bleibt die Nummer stehen.
function Historie.Gegenstandstext(eintrag)
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

-- =====================================================================
--  Auswertung
-- =====================================================================

--- Wer hat wie viel bekommen.
--  @param wochen  Zeitraum in Wochen; nil oder 0 = alles
--  @param quelle  optionale Ersatzquelle (Beispieldaten)
--  @return Liste aus { name, haupt, zweit, letzte, letztesStueck },
--          Zahl der ausgewerteten Vergaben, aeltester Zeitstempel
function Historie.Bilanz(wochen, quelle)
    local H, grund = quelle, nil
    if not H then H, grund = Historie.Quelle() end
    if not H then return nil, grund end

    local grenze = 0
    if wochen and wochen > 0 then grenze = time() - wochen * WOCHE end

    local nach, gesamt, aeltester = {}, 0, nil

    for _, e in pairs(H) do
        if zaehlt(e) and e.timestamp >= grenze then
            local k = schluessel(e.awardedTo)
            local z = nach[k]
            if not z then
                z = { name = anzeigename(e.awardedTo), haupt = 0, zweit = 0, letzte = 0 }
                nach[k] = z
            end

            if e.OS then
                z.zweit = z.zweit + 1
            else
                z.haupt = z.haupt + 1
                -- „Zuletzt" meint Hauptbedarf: Zweitbedarf sagt ueber den
                -- Anspruch nichts aus.
                if e.timestamp > z.letzte then
                    z.letzte = e.timestamp
                    z.letztesStueck = Historie.Gegenstandstext(e)
                end
            end

            gesamt = gesamt + 1
            if not aeltester or e.timestamp < aeltester then aeltester = e.timestamp end
        end
    end

    local liste = {}
    for _, z in pairs(nach) do liste[#liste + 1] = z end

    table.sort(liste, function(a, b)
        if a.haupt ~= b.haupt then return a.haupt > b.haupt end
        if a.zweit ~= b.zweit then return a.zweit > b.zweit end
        return a.name < b.name
    end)

    return liste, gesamt, aeltester
end

--- Alle Vergaben eines Spielers, neueste zuerst.
function Historie.Spieler(name, wochen, quelle)
    local H, grund = quelle, nil
    if not H then H, grund = Historie.Quelle() end
    if not H then return nil, grund end

    local gesucht = schluessel(name)
    local grenze = 0
    if wochen and wochen > 0 then grenze = time() - wochen * WOCHE end

    local liste = {}
    for _, e in pairs(H) do
        if zaehlt(e) and e.timestamp >= grenze and schluessel(e.awardedTo) == gesucht then
            liste[#liste + 1] = {
                zeit   = e.timestamp,
                stueck = Historie.Gegenstandstext(e),
                zweit  = e.OS and true or false,
            }
        end
    end

    table.sort(liste, function(a, b) return a.zeit > b.zeit end)
    return liste
end

--- Wie viele Raidtage stecken im Zeitraum?
--  Zaehlt verschiedene Kalendertage mit mindestens einer Vergabe — eine
--  grobe, aber ehrliche Bezugsgroesse fuer „viel" und „wenig".
--  ⚠️ Das ist NICHT Anwesenheit: Wer da war und nichts bekam, steht in
--  Garguls Daten nirgends.
function Historie.Raidtage(wochen, quelle)
    local H = quelle or Historie.Quelle()
    if not H then return 0 end

    local grenze = 0
    if wochen and wochen > 0 then grenze = time() - wochen * WOCHE end

    local tage, n = {}, 0
    for _, e in pairs(H) do
        if zaehlt(e) and e.timestamp >= grenze then
            local tag = date("%Y-%m-%d", e.timestamp)
            if not tage[tag] then tage[tag] = true; n = n + 1 end
        end
    end
    return n
end

-- =====================================================================
--  Beispieldaten
-- =====================================================================

-- Verteilung je Spieler: Hauptbedarf, Zweitbedarf. Bewusst ungleich,
-- damit die Anzeige zeigt, wofuer sie gedacht ist.
local BEISPIEL_SPIELER = {
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

-- Ein paar echte Gegenstands-IDs. Kennt der Client sie nicht — in
-- Forever gibt es TBC-Gegenstaende moeglicherweise nicht — steht die
-- Nummer da. Fuer die Darstellung reicht das.
local BEISPIEL_ITEMS = { 32235, 32505, 32837, 30883, 29434, 32369, 32256, 32332 }

--- Baut eine Beispiel-Historie im Speicher.
--  ⚠️ Schreibt NICHTS — weder in Gargul noch in die SavedVariables.
--  Der Aufrufer reicht das Ergebnis als Quelle in die Auswertung.
function Historie.Beispiel()
    local jetzt = time()
    local H, n = {}, 0

    -- Zehn Raidabende, grob woechentlich, jeweils abends.
    local abende = {}
    for i = 1, 10 do
        abende[i] = jetzt - (i * 7 - 4) * TAG
    end

    for _, Eintrag in ipairs(BEISPIEL_SPIELER) do
        local name, haupt, zweit = Eintrag[1], Eintrag[2], Eintrag[3]

        for k = 1, haupt + zweit do
            n = n + 1
            -- Die zuletzt Bedachten weiter vorn, damit „zuletzt vor N
            -- Tagen" auseinandergeht.
            local abend = abende[((n * 3) % #abende) + 1]
            H["beispiel" .. n] = {
                awardedTo = name,
                itemID    = BEISPIEL_ITEMS[(n % #BEISPIEL_ITEMS) + 1],
                timestamp = abend + (n % 4) * 900,
                OS        = k > haupt,
            }
        end
    end

    return H
end

return ns
