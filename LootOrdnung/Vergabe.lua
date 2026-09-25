--[[----------------------------------------------------------------------
    Vergabe.lua  —  Vergabe-Register und Gargul-Anbindung

    Haelt fest, wer welchen Gegenstand bekommen hat, und rechnet daraus
    den Ruestwert (§ 3).

    ⭐ **Es werden Ereignisse gespeichert, keine Summen.** Zwei Zaehler
    „Kaos: 3" und „Kaos: 2" lassen sich nicht zusammenfuehren — man weiss
    nicht, ob fuenf Vergaben gemeint sind oder dieselben drei plus zwei.
    Zwei Listen mit Kennungen dagegen vereinigt man verlustfrei. Deshalb
    ist das Register eine Menge von Einzelvergaben, ueber die Kennung
    adressiert.

    ⭐ **Ruecknahmen bekommen einen Grabstein statt geloescht zu werden.**
    Wer einen Eintrag einfach entfernt, bekommt ihn beim naechsten
    Abgleich vom Nachbarn zurueck. Das Feld `weg` gewinnt immer.

    ⚠️ Der Ruestwert wird NICHT beim Eintragen berechnet, sondern bei
    Bedarf. Direkt nach einem Bosskill kennt der Client den Gegenstand
    haeufig noch nicht (`GetItemInfo` gibt nil), und ein einmal falsch
    gespeicherter Wert bliebe falsch. Gespeichert wird nur die
    Gegenstands-ID.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Vergabe = {}
ns.Vergabe = Vergabe

local Kern = ns.Kern

local PRAEFIX = "|cff1B6B57Loot-Ordnung|r: "

-- =====================================================================
--  Speicher
-- =====================================================================

--- Das Register: Kennung -> { spieler, gegenstand, zeit, weg }
function Vergabe.Register()
    LootOrdnungDB = LootOrdnungDB or {}
    LootOrdnungDB.vergaben = LootOrdnungDB.vergaben or {}
    return LootOrdnungDB.vergaben
end

--- Namen so schreiben wie der Gildenroster, damit beide Seiten denselben
--  Schluessel benutzen.
function Vergabe.VollerName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("%-") then return name end
    local realm = GetRealmName and GetRealmName() or ""
    realm = realm:gsub("%s+", "")
    if realm == "" then return name end
    return name .. "-" .. realm
end

-- =====================================================================
--  Ruestwert aus dem Gegenstand (§ 3)
-- =====================================================================

--- Platz und Gegenstandsstufe ermitteln.
--  ⚠️ Versionsbewusst: In Forever fehlen die Globals GetItemInfo und
--  GetItemInfoInstant, es gibt nur die Fassungen unter C_Item. Im
--  Anniversary-Client ist es umgekehrt. Nie nach dem Spiel fragen,
--  immer nach der Faehigkeit.
--  @return platz (INVTYPE_*), stufe  — oder nil, wenn noch unbekannt
function Vergabe.GegenstandsInfo(gegenstand)
    if not gegenstand then return nil end

    local CI = rawget(_G, "C_Item")
    local platz, stufe

    local sofort = (CI and CI.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
    if sofort then
        local ok, _, _, _, ort = pcall(sofort, gegenstand)
        if ok then platz = ort end
    end

    local genau = (CI and CI.GetDetailedItemLevelInfo) or rawget(_G, "GetDetailedItemLevelInfo")
    if genau then
        local ok, wert = pcall(genau, gegenstand)
        if ok then stufe = wert end
    end

    -- Rueckfallweg: die vollstaendige Abfrage kennt beides, braucht den
    -- Gegenstand aber im Zwischenspeicher.
    if not (platz and stufe) then
        local voll = (CI and CI.GetItemInfo) or rawget(_G, "GetItemInfo")
        if voll then
            local ok, _, _, _, ilvl, _, _, _, _, ort = pcall(voll, gegenstand)
            if ok then
                stufe = stufe or ilvl
                platz = platz or ort
            end
        end
    end

    if platz == "" then platz = nil end
    return platz, stufe
end

--- Ruestwert eines Gegenstands nach § 3.
--  @return zahl, oder nil wenn der Gegenstand (noch) unbekannt ist oder
--          keinen Platzfaktor hat — Taschen und Verbrauchsgueter etwa.
function Vergabe.RuestwertVon(gegenstand)
    local platz, stufe = Vergabe.GegenstandsInfo(gegenstand)
    if not platz or not stufe then return nil end
    return Kern.RuestwertVon(platz, stufe)
end

-- =====================================================================
--  Eintragen
-- =====================================================================

--- Traegt eine Vergabe ein.
--  IDEMPOTENT ueber die Kennung: Derselbe Aufruf zweimal aendert nichts.
--  Das ist zwingend, weil Gargul dasselbe Ereignis auch beim Empfaenger
--  feuert und der Abgleich es zusaetzlich mitbringt.
--  @return true wenn neu, sonst false
function Vergabe.Eintragen(kennung, spieler, gegenstand, zeit)
    if not kennung or not spieler or not gegenstand then return false end

    local register = Vergabe.Register()
    if register[kennung] then return false end

    register[kennung] = {
        spieler   = Vergabe.VollerName(spieler),
        gegenstand = tonumber(gegenstand) or gegenstand,
        zeit      = tonumber(zeit) or time(),
    }
    return true
end

--- Nimmt eine Vergabe zurueck — als Grabstein, nicht durch Loeschen.
function Vergabe.Zuruecknehmen(kennung)
    if not kennung then return false end
    local register = Vergabe.Register()
    local eintrag = register[kennung]

    if not eintrag then
        -- Auch unbekannte Ruecknahmen merken: Sonst traegt der naechste
        -- Abgleich die Vergabe nachtraeglich ein.
        register[kennung] = { weg = true, zeit = time() }
        return true
    end

    if eintrag.weg then return false end
    eintrag.weg = true
    return true
end

-- =====================================================================
--  Zusammenfuehren
-- =====================================================================

--- Vereinigt ein fremdes Register in das eigene.
--
--  ⭐ Monoton: Die Reihenfolge ist egal, mehrfaches Anwenden aendert
--  nichts mehr. Dadurch braucht der Abgleich keine Absprache, wer
--  zuerst sendet — dasselbe Prinzip wie beim Verfall und bei der
--  Abendbuchung.
--
--  ⚠️ `weg` gewinnt immer gegen einen vorhandenen Eintrag. Andernfalls
--  holte ein Nachbar, der die Ruecknahme nicht kennt, die Vergabe zurueck.
--
--  Ohne WoW-API, damit der Pruefstand sie testen kann.
--  @return neu, zurueckgenommen
function Vergabe.Vereinen(eigen, fremd)
    if type(eigen) ~= "table" or type(fremd) ~= "table" then return 0, 0 end
    local neu, weg = 0, 0

    for kennung, e in pairs(fremd) do
        local vorhanden = eigen[kennung]
        if not vorhanden then
            eigen[kennung] = {
                spieler    = e.spieler,
                gegenstand = e.gegenstand,
                zeit       = e.zeit,
                weg        = e.weg,
            }
            if e.weg then weg = weg + 1 else neu = neu + 1 end
        elseif e.weg and not vorhanden.weg then
            vorhanden.weg = true
            weg = weg + 1
        elseif not vorhanden.spieler and e.spieler then
            -- Grabstein trifft auf die Vergabe dahinter: Angaben ergaenzen,
            -- damit die Anzeige den Gegenstand benennen kann.
            vorhanden.spieler    = e.spieler
            vorhanden.gegenstand = e.gegenstand
        end
    end

    return neu, weg
end

-- =====================================================================
--  Auswertung
-- =====================================================================

--- Was jeder Spieler bekommen hat.
--  @return Liste aus { name, kurz, anzahl, ruestwert, offen }
--          `offen` = Stuecke, deren Ruestwert der Client noch nicht kennt
function Vergabe.Bilanz()
    local nach = {}

    for _, e in pairs(Vergabe.Register()) do
        if not e.weg and e.spieler then
            local z = nach[e.spieler]
            if not z then
                z = { name = e.spieler, anzahl = 0, ruestwert = 0, offen = 0 }
                nach[e.spieler] = z
            end
            z.anzahl = z.anzahl + 1
            local w = Vergabe.RuestwertVon(e.gegenstand)
            if w then z.ruestwert = z.ruestwert + w else z.offen = z.offen + 1 end
        end
    end

    local liste = {}
    for _, z in pairs(nach) do
        z.kurz = z.name:match("^([^%-]+)") or z.name
        liste[#liste + 1] = z
    end
    table.sort(liste, function(a, b)
        if a.ruestwert ~= b.ruestwert then return a.ruestwert > b.ruestwert end
        return a.kurz < b.kurz
    end)
    return liste
end

--- Zahlen fuer die Kurzanzeige.
function Vergabe.Zahlen()
    local gesamt, weg = 0, 0
    for _, e in pairs(Vergabe.Register()) do
        if e.weg then weg = weg + 1 else gesamt = gesamt + 1 end
    end
    return gesamt, weg
end

-- =====================================================================
--  Gargul
-- =====================================================================

Vergabe.gargulAngebunden = false

--- Uebernimmt einen Gargul-Eintrag.
--  § 6: Nur Hauptbedarf zaehlt auf den Ruestwert. Gargul fuehrt das
--  Kennzeichen `OS` (Offspec) mit; Bonus-Beute und der Entzauberer
--  bleiben ebenfalls draussen.
local function ausGargul(Eintrag)
    if type(Eintrag) ~= "table" then return end
    if Eintrag.OS then return end
    if Eintrag.isBonusLoot then return end

    local kennung = Eintrag.checksum
    local spieler = Eintrag.awardedTo
    local gegenstand = Eintrag.itemID
    if not gegenstand and Eintrag.itemLink then
        gegenstand = tonumber(Eintrag.itemLink:match("item:(%d+)"))
    end
    if not (kennung and spieler and gegenstand) then return end

    if Vergabe.Eintragen(kennung, spieler, gegenstand, Eintrag.timestamp) then
        local wert = Vergabe.RuestwertVon(gegenstand)
        print(string.format("%s%s → |cffffff78%s|r%s", PRAEFIX,
            tostring(Eintrag.itemLink or gegenstand),
            tostring(spieler),
            wert and string.format("  |cff8E9A94Rüstwert +%d|r", wert + 0.5) or ""))
    end
end

--- Bindet sich an Gargul an.
--  ⚠️ Gargul ruft seine Zuhoerer in einem pcall auf — ein Fehler hier
--  bleibt vollkommen still. Der Handler bleibt deshalb winzig und meldet
--  selbst, statt sich auf eine Fehlermeldung zu verlassen.
--  @return true wenn angebunden, sonst false und ein Grund
function Vergabe.GargulAnbinden()
    if Vergabe.gargulAngebunden then return true end

    local GL = rawget(_G, "Gargul")
    if not GL then return false, "Gargul ist nicht geladen" end
    if not (GL.Events and GL.Events.register) then
        return false, "Gargul hat keine Ereignis-Schnittstelle"
    end

    GL.Events:register("LootOrdnungVergabe", "GL.ITEM_AWARDED", function(_, Eintrag)
        ausGargul(Eintrag)
    end)
    GL.Events:register("LootOrdnungVergabeGeaendert", "GL.ITEM_AWARD_EDITED", function(_, Eintrag)
        ausGargul(Eintrag)
    end)
    GL.Events:register("LootOrdnungRuecknahme", "GL.ITEM_UNAWARDED", function(_, Eintrag)
        if type(Eintrag) == "table" and Eintrag.checksum then
            if Vergabe.Zuruecknehmen(Eintrag.checksum) then
                print(PRAEFIX .. "|cffffff78Vergabe zurückgenommen.|r")
            end
        end
    end)

    Vergabe.gargulAngebunden = true
    return true
end

-- Gargul laedt unabhaengig von uns; einmal beim Start versuchen und
-- spaeter erneut, wenn ein Addon nachgeladen wird.
local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:RegisterEvent("ADDON_LOADED")
rahmen:SetScript("OnEvent", function()
    if not Vergabe.gargulAngebunden then pcall(Vergabe.GargulAnbinden) end
end)

return ns
