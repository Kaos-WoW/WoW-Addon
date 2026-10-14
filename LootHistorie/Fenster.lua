--[[----------------------------------------------------------------------
    Fenster.lua  —  Die Anzeige

    Zustaende im selben Fenster:
      * die Liste aller Spieler
      * der Verlauf: wer bekam was, wann (neueste zuerst)
      * nach einem Klick die Einzelvergaben eines Spielers
      * waehrend eines Wurfs: die Wuerfelnden oben, hervorgehoben,
        **der mit den wenigsten Stuecken zuerst**
      * die Einstellungen

    ⚠️ Bewusst ohne Bibliotheken und ohne Bildlaufleiste: ein fester Satz
    Zeilen plus Mausrad-Versatz. Das laeuft in jeder Client-Fassung gleich,
    und es gibt nichts, was beim naechsten Patch bricht.

    ⚠️ Das Fenster haelt keinen Zustand ueber die Sitzung hinaus (ausser
    dem Schalter fuers automatische Oeffnen). Es liest bei jedem Aufbau
    frisch — dadurch kann es nie etwas Veraltetes zeigen.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Fenster = {}
ns.Fenster = Fenster

local Kern, Quelle = ns.Kern, ns.Quelle

local BREITE, HOEHE = 580, 586
local ZEILEN        = 16
local ZEILENHOEHE   = 24
local SCHRIFT_PLUS  = 3      -- Punkte groesser als die Blizzard-Vorgabe

-- Farben des Projekts
local GRUEN = "|cff1B6B57"
local GELB  = "|cffffff78"
local GRAU  = "|cff8E9A94"
local ROT   = "|cffff5555"
local HELL  = "|cffffffff"

local rahmen, Zeile, kopf, fuss, titel, unterzeile, zurueckBtn, demoBtn, einstellBtn
local listeBtn, verlaufBtn, gruppeBtn, abgleichBtn
local Zeitraum = {}

local zustand = { wochen = 0, beispiel = false, spieler = nil, versatz = 0, maxVersatz = 0,
                  einstellungen = false, ansicht = "liste", gruppe = nil }

-- Spaltenlagen je Ansicht: { x, Breite, Ausrichtung }
local LAYOUT = {
    liste   = { { 0, 160, "LEFT" }, { 166, 55, "RIGHT" }, { 228, 55, "RIGHT" },
                { 294, 150, "LEFT" }, { 452, 60, "RIGHT" } },
    verlauf = { { 0, 104, "LEFT" }, { 110, 150, "LEFT" }, { 266, 52, "LEFT" },
                { 324, 224, "LEFT" }, { 0, 1, "LEFT" } },
}
local SPALTEN = { "a", "b", "c", "d", "e" }

-- =====================================================================
--  Einstellungen
-- =====================================================================

local function db()
    LootHistorieDB = LootHistorieDB or {}
    if LootHistorieDB.autoOeffnen == nil then LootHistorieDB.autoOeffnen = true end
    return LootHistorieDB
end

function Fenster.AutoOeffnen()
    return db().autoOeffnen and true or false
end

function Fenster.AutoUmschalten()
    local d = db()
    d.autoOeffnen = not d.autoOeffnen
    return d.autoOeffnen
end

function Fenster.AutoSetzen(an)
    db().autoOeffnen = an and true or false
end

-- =====================================================================
--  Daten
-- =====================================================================

--- Die Historie, eingeschraenkt auf die gewaehlte Gruppe.
local function historie()
    if zustand.beispiel then return Quelle.Beispiel() end
    local H, grund = Quelle.Historie()
    if not H then return nil, grund end
    return Kern.NachGruppe(H, zustand.gruppe)
end

local function wurf()
    if zustand.beispiel then return Quelle.BeispielWurf() end
    return Quelle.Wurf()
end

local function seit()
    return Kern.Seit(time(), zustand.wochen)
end

local function tageHer(zeitstempel)
    if not zeitstempel or zeitstempel <= 0 then return nil end
    return math.floor((time() - zeitstempel) / Kern.TAG)
end

-- =====================================================================
--  Aufbau
-- =====================================================================

--- Blizzards Schriftgroessen sind fuer diese Tabelle zu klein.
local function groesser(fs)
    local pfad, groesse, flaggen = fs:GetFont()
    if pfad and groesse then fs:SetFont(pfad, groesse + SCHRIFT_PLUS, flaggen) end
    return fs
end

local function spalte(eltern, x, breite, ausrichtung)
    local t = eltern:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", eltern, "LEFT", x, 0)
    t:SetWidth(breite)
    t:SetJustifyH(ausrichtung or "LEFT")
    t:SetWordWrap(false)
    return groesser(t)
end

local function baueZeile(index)
    local z = CreateFrame("Button", nil, rahmen)
    z:SetSize(BREITE - 32, ZEILENHOEHE)
    z:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 16, -(144 + (index - 1) * ZEILENHOEHE))

    z.hintergrund = z:CreateTexture(nil, "BACKGROUND")
    z.hintergrund:SetAllPoints(z)
    z.hintergrund:SetColorTexture(0.11, 0.42, 0.34, 0.35)
    z.hintergrund:Hide()

    z:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local h = z:GetHighlightTexture()
    if h then h:SetVertexColor(1, 1, 1, 0.08) end

    z.a = spalte(z,   0, 160)
    z.b = spalte(z, 166,  55, "RIGHT")
    z.c = spalte(z, 228,  55, "RIGHT")
    z.d = spalte(z, 294, 150)
    z.e = spalte(z, 452,  60, "RIGHT")

    z:SetScript("OnClick", function()
        if zustand.spieler or not z.spielername then return end
        zustand.spieler = z.spielername
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    return z
end

local function baueFenster()
    if rahmen then return end

    rahmen = CreateFrame("Frame", "LootHistorieFenster", UIParent, "BackdropTemplate")
    rahmen:SetSize(BREITE, HOEHE)
    rahmen:SetPoint("CENTER")
    rahmen:SetFrameStrata("DIALOG")
    rahmen:SetMovable(true)
    rahmen:EnableMouse(true)
    rahmen:RegisterForDrag("LeftButton")
    rahmen:SetScript("OnDragStart", function(s) s:StartMoving() end)
    rahmen:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    rahmen:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    tinsert(UISpecialFrames, "LootHistorieFenster")

    titel = groesser(rahmen:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"))
    titel:SetPoint("TOP", rahmen, "TOP", 0, -16)

    local schliessen = CreateFrame("Button", nil, rahmen, "UIPanelCloseButton")
    schliessen:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -6, -6)

    local auswahl = { { "Alles", 0 }, { "8 Wochen", 8 }, { "4 Wochen", 4 } }
    local x = 16
    for i, Eintrag in ipairs(auswahl) do
        local b = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
        b:SetSize(84, 22)
        b:SetPoint("TOPLEFT", rahmen, "TOPLEFT", x, -46)
        b:SetText(Eintrag[1])
        b.wochen = Eintrag[2]
        b:SetScript("OnClick", function()
            zustand.wochen = Eintrag[2]
            zustand.versatz = 0
            Fenster.Aktualisieren()
        end)
        Zeitraum[i] = b
        x = x + 88
    end

    demoBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    demoBtn:SetSize(104, 22)
    demoBtn:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -16, -46)
    demoBtn:SetScript("OnClick", function()
        zustand.beispiel = not zustand.beispiel
        zustand.spieler = nil
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    einstellBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    einstellBtn:SetSize(104, 22)
    einstellBtn:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -124, -46)
    einstellBtn:SetText("Einstellungen")
    einstellBtn:SetScript("OnClick", function()
        zustand.einstellungen = not zustand.einstellungen
        zustand.spieler = nil
        Fenster.Aktualisieren()
    end)

    zurueckBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    zurueckBtn:SetSize(84, 22)
    zurueckBtn:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 16, -98)
    zurueckBtn:SetText("Zurück")
    zurueckBtn:SetScript("OnClick", function()
        zustand.spieler = nil
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)
    zurueckBtn:Hide()

    -- Zeile mit den Ansichten
    listeBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    listeBtn:SetSize(84, 22)
    listeBtn:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 16, -72)
    listeBtn:SetText("Spieler")
    listeBtn:SetScript("OnClick", function()
        zustand.ansicht = "liste"
        zustand.spieler = nil
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    verlaufBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    verlaufBtn:SetSize(84, 22)
    verlaufBtn:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 104, -72)
    verlaufBtn:SetText("Verlauf")
    verlaufBtn:SetScript("OnClick", function()
        zustand.ansicht = "verlauf"
        zustand.spieler = nil
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    -- Gruppe wechseln: Alle -> erste -> zweite ... -> Alle
    gruppeBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    gruppeBtn:SetSize(170, 22)
    gruppeBtn:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 192, -72)
    gruppeBtn:SetScript("OnClick", function()
        local Namen = ns.Gruppen and ns.Gruppen.Namen() or {}
        if #Namen == 0 then return end
        local naechste
        if zustand.gruppe == nil then
            naechste = Namen[1]
        else
            for i, n in ipairs(Namen) do
                if n == zustand.gruppe then naechste = Namen[i + 1] break end
            end
        end
        zustand.gruppe = naechste
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    abgleichBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    abgleichBtn:SetSize(104, 22)
    abgleichBtn:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -16, -72)
    abgleichBtn:SetText("Abgleichen")
    abgleichBtn:SetScript("OnClick", function()
        local ok, grund = ns.Abgleich.Starten()
        if not ok then print("|cff1B6B57Loot-Historie|r: |cffff5555" .. tostring(grund) .. "|r") end
    end)

    unterzeile = groesser(rahmen:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    unterzeile:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 108, -103)
    unterzeile:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -16, -103)
    unterzeile:SetJustifyH("LEFT")

    kopf = CreateFrame("Frame", nil, rahmen)
    kopf:SetSize(BREITE - 32, 18)
    kopf:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 16, -126)
    kopf.a = spalte(kopf,   0, 160)
    kopf.b = spalte(kopf, 166,  55, "RIGHT")
    kopf.c = spalte(kopf, 228,  55, "RIGHT")
    kopf.d = spalte(kopf, 294, 150)
    kopf.e = spalte(kopf, 452,  60, "RIGHT")

    Zeile = {}
    for i = 1, ZEILEN do Zeile[i] = baueZeile(i) end

    if ns.Einstellungen then ns.Einstellungen.Bauen(rahmen, BREITE) end

    fuss = groesser(rahmen:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"))
    fuss:SetPoint("BOTTOMLEFT", rahmen, "BOTTOMLEFT", 16, 18)
    fuss:SetPoint("BOTTOMRIGHT", rahmen, "BOTTOMRIGHT", -16, 18)
    fuss:SetJustifyH("LEFT")

    -- Mausrad statt Bildlaufleiste: ein Teil weniger, das brechen kann.
    rahmen:EnableMouseWheel(true)
    rahmen:SetScript("OnMouseWheel", function(_, richtung)
        local neu = zustand.versatz - richtung
        if neu < 0 then neu = 0 end
        if neu > (zustand.maxVersatz or 0) then neu = zustand.maxVersatz or 0 end
        if neu ~= zustand.versatz then
            zustand.versatz = neu
            Fenster.Aktualisieren()
        end
    end)
end

-- =====================================================================
--  Anzeige
-- =====================================================================

--- Stellt die Spalten fuer eine Ansicht ein.
local function ordneSpalten(name)
    local L = LAYOUT[name] or LAYOUT.liste
    local function setze(eltern, fs, def)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", eltern, "LEFT", def[1], 0)
        fs:SetWidth(def[2])
        fs:SetJustifyH(def[3])
    end
    for i, k in ipairs(SPALTEN) do
        setze(kopf, kopf[k], L[i])
        for j = 1, ZEILEN do setze(Zeile[j], Zeile[j][k], L[i]) end
    end
end

local function leereZeilen(ab)
    for i = math.max(ab, 1), ZEILEN do
        local z = Zeile[i]
        z.spielername = nil
        z.hintergrund:Hide()
        z.a:SetText(""); z.b:SetText(""); z.c:SetText(""); z.d:SetText(""); z.e:SetText("")
    end
end

local function setzeKopf(a, b, c, d, e)
    kopf.a:SetText(a and (GRAU .. a .. "|r") or "")
    kopf.b:SetText(b and (GRAU .. b .. "|r") or "")
    kopf.c:SetText(c and (GRAU .. c .. "|r") or "")
    kopf.d:SetText(d and (GRAU .. d .. "|r") or "")
    kopf.e:SetText(e and (GRAU .. e .. "|r") or "")
end

local function zuletztText(letzte)
    local tage = tageHer(letzte)
    if not tage then return GRAU .. "noch nichts|r" end
    if tage == 0 then return "heute" end
    if tage == 1 then return "gestern" end
    return string.format("vor %d Tagen", tage)
end

local function zeigeListe(H)
    local W = wurf()

    -- Wer in der Liste stehen muss, auch ohne Vergabe: die Wuerfelnden und
    -- der Kader bzw. die Raidgruppe der gewaehlten (sonst aktiven) Gruppe.
    local pflicht = {}
    if W and W.namen then for _, n in ipairs(W.namen) do pflicht[#pflicht + 1] = n end end
    if not zustand.beispiel and ns.Gruppen then
        for _, n in ipairs(ns.Gruppen.Pflicht(zustand.gruppe)) do pflicht[#pflicht + 1] = n end
    end

    local liste, gesamt, aeltester = Kern.Bilanz(H, seit(), pflicht)

    local istWuerfler
    if W then
        istWuerfler = function(name)
            return W.Wuerfe[Kern.Schluessel(name)] ~= nil
        end
        Kern.WurfReihenfolge(liste, istWuerfler)
    end

    setzeKopf("Spieler", "Haupt", "Zweit", "Zuletzt", W and "Wurf" or nil)

    zustand.maxVersatz = math.max(0, #liste - ZEILEN)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    local gezeigt = 0
    for i = 1, ZEILEN do
        local z = Zeile[i]
        local e = liste[i + zustand.versatz]
        if not e then break end
        gezeigt = i

        local wuerfelt = istWuerfler and istWuerfler(e.name)
        z.spielername = e.name
        z.hintergrund:SetShown(wuerfelt and true or false)

        z.a:SetText((wuerfelt and HELL or "") .. e.name .. (wuerfelt and "|r" or ""))
        z.b:SetText(e.haupt > 0 and (GELB .. e.haupt .. "|r") or (GRAU .. "0|r"))
        z.c:SetText(e.zweit > 0 and (GRAU .. e.zweit .. "|r") or "")
        z.d:SetText(zuletztText(e.letzte))

        if W then
            local w = W.Wuerfe[Kern.Schluessel(e.name)]
            z.e:SetText(w and (HELL .. w .. "|r") or "")
        else
            z.e:SetText("")
        end
    end
    leereZeilen(gezeigt + 1)

    local text = string.format("%d Vergaben · %d Spieler · %d Raidtage",
        gesamt, #liste, Kern.Raidtage(H, seit(), Quelle.Tag))
    if aeltester then
        text = text .. "   |   älteste Aufzeichnung " .. date("%d.%m.%Y", aeltester)
    end
    if #liste > ZEILEN then text = text .. "   |   Mausrad blättert" end
    fuss:SetText(text)

    if W then
        local was = W.link or W.name
        unterzeile:SetText(GELB .. "Wurf läuft|r  " ..
            (was and (was .. "  ") or "") ..
            GRAU .. "—   Würfelnde oben, wenigste Stücke zuerst|r")
    else
        unterzeile:SetText("")
    end
end

local function zeigeSpieler(H)
    setzeKopf("Datum", nil, nil, "Gegenstand", nil)

    local liste = Kern.Spieler(H, zustand.spieler, seit())
    zustand.maxVersatz = math.max(0, #liste - ZEILEN)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    local gezeigt = 0
    for i = 1, ZEILEN do
        local z = Zeile[i]
        local e = liste[i + zustand.versatz]
        if not e then break end
        gezeigt = i

        z.spielername = nil
        z.hintergrund:Hide()
        z.a:SetText(date("%d.%m.%Y", e.zeit))
        z.b:SetText(e.zweit and (GRAU .. "Zweit|r") or "")
        z.c:SetText("")
        z.d:SetText(Quelle.Gegenstandstext(e.eintrag))
        z.e:SetText("")
    end
    leereZeilen(gezeigt + 1)

    local haupt = 0
    for _, e in ipairs(liste) do if not e.zweit then haupt = haupt + 1 end end
    fuss:SetText(string.format("%s: %d Vergaben, davon %d Hauptbedarf",
        zustand.spieler, #liste, haupt))
    unterzeile:SetText("")
end

local function zeigeVerlauf(H)
    setzeKopf("Wann", "Spieler", "Art", "Gegenstand", nil)

    local liste = Kern.Verlauf(H, seit(), nil)
    zustand.maxVersatz = math.max(0, #liste - ZEILEN)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    local gezeigt = 0
    for i = 1, ZEILEN do
        local z = Zeile[i]
        local e = liste[i + zustand.versatz]
        if not e then break end
        gezeigt = i

        z.spielername = e.name
        z.hintergrund:Hide()
        z.a:SetText(date("%d.%m. %H:%M", e.zeit))
        z.b:SetText(e.name)
        z.c:SetText(e.zweit and (GRAU .. "Zweit|r") or "")
        z.d:SetText(Quelle.Gegenstandstext(e.eintrag))
        z.e:SetText("")
    end
    leereZeilen(gezeigt + 1)

    local text = string.format("%d Vergaben, neueste zuerst", #liste)
    if #liste > ZEILEN then text = text .. "   |   Mausrad blättert" end
    fuss:SetText(text)
    unterzeile:SetText("")
end

--- Liste samt Kopfzeile zeigen oder verbergen.
local function inhaltZeigen(an)
    kopf:SetShown(an)
    for i = 1, ZEILEN do Zeile[i]:SetShown(an) end
    unterzeile:SetShown(an)
end

function Fenster.Aktualisieren()
    if not rahmen then return end

    einstellBtn:SetText(zustand.einstellungen and "Zur Liste" or "Einstellungen")

    -- Einstellungsansicht: die Liste tritt beiseite
    if zustand.einstellungen then
        titel:SetText(GRUEN .. "Loot-Historie|r   " .. GRAU .. "Einstellungen|r")
        inhaltZeigen(false)
        zurueckBtn:Hide()
        for _, b in ipairs(Zeitraum) do b:Hide() end
        demoBtn:Hide()
        listeBtn:Hide(); verlaufBtn:Hide(); gruppeBtn:Hide(); abgleichBtn:Hide()
        fuss:SetText("")
        if ns.Einstellungen then ns.Einstellungen.Zeigen() end
        return
    end

    if ns.Einstellungen then ns.Einstellungen.Verstecken() end
    inhaltZeigen(true)
    for _, b in ipairs(Zeitraum) do b:Show() end
    demoBtn:Show()
    listeBtn:Show(); verlaufBtn:Show(); gruppeBtn:Show(); abgleichBtn:Show()

    listeBtn:SetEnabled(zustand.ansicht ~= "liste" or zustand.spieler ~= nil)
    verlaufBtn:SetEnabled(zustand.ansicht ~= "verlauf")

    -- Gruppenwahl
    local Namen = ns.Gruppen and ns.Gruppen.Namen() or {}
    if zustand.gruppe and not (ns.Gruppen and ns.Gruppen.Holen(zustand.gruppe)) then
        zustand.gruppe = nil     -- die Gruppe wurde inzwischen geloescht
    end
    gruppeBtn:SetText("Gruppe: " .. (zustand.gruppe or (#Namen > 0 and "Alle" or "keine")))
    gruppeBtn:SetEnabled(#Namen > 0 and not zustand.beispiel)

    -- Abgleich: auffaellig, wenn Mitspieler abweichen
    local abw = ns.Abgleich and ns.Abgleich.Abweichend or {}
    if #abw > 0 then
        abgleichBtn:SetText(GELB .. "Abgleichen (" .. #abw .. ")|r")
    else
        abgleichBtn:SetText("Abgleichen")
    end
    abgleichBtn:SetEnabled(not zustand.beispiel)

    for _, b in ipairs(Zeitraum) do b:SetEnabled(b.wochen ~= zustand.wochen) end
    demoBtn:SetText(zustand.beispiel and "Beispiel aus" or "Beispiel")

    titel:SetText(GRUEN .. "Loot-Historie|r" ..
        (zustand.beispiel and ("   " .. GELB .. "Beispieldaten|r") or ""))

    if zustand.spieler then zurueckBtn:Show() else zurueckBtn:Hide() end

    local H, grund = historie()
    if not H then
        leereZeilen(1)
        setzeKopf(nil, nil, nil, nil, nil)
        Zeile[1].a:SetWidth(BREITE - 60)
        Zeile[1].a:SetText(ROT .. tostring(grund) .. "|r")
        Zeile[2].a:SetWidth(BREITE - 60)
        Zeile[2].a:SetText(GRAU .. "Der Knopf Beispiel zeigt, wie die Anzeige aussieht.|r")
        fuss:SetText("")
        unterzeile:SetText("")
        return
    end

    ordneSpalten("liste")

    if zustand.spieler then
        ordneSpalten("liste")
        zeigeSpieler(H)
    elseif zustand.ansicht == "verlauf" then
        ordneSpalten("verlauf")
        zeigeVerlauf(H)
    else
        ordneSpalten("liste")
        zeigeListe(H)
    end

    -- Wer schreibt gerade mit?
    if ns.Rolle and not zustand.beispiel then
        local darf, grund = ns.Rolle.IchSchreibe()
        local text = fuss:GetText() or ""
        local zusatz = darf and ("Du schreibst mit (" .. tostring(grund) .. ")") or tostring(grund)
        fuss:SetText(text .. "   |   " .. zusatz)
    end
end

-- =====================================================================
--  Steuerung
-- =====================================================================

function Fenster.Zeigen(beispiel)
    baueFenster()
    if beispiel ~= nil then zustand.beispiel = beispiel and true or false end
    zustand.spieler = nil
    zustand.versatz = 0
    zustand.einstellungen = false
    zustand.ansicht = "liste"
    rahmen:Show()
    Fenster.Aktualisieren()
end

--- Fenster in einer bestimmten Ansicht oeffnen ("liste" oder "verlauf").
function Fenster.ZeigenAnsicht(ansicht)
    Fenster.Zeigen(false)
    zustand.ansicht = (ansicht == "verlauf") and "verlauf" or "liste"
    Fenster.Aktualisieren()
end

function Fenster.Verstecken()
    if rahmen then rahmen:Hide() end
end

function Fenster.Umschalten(beispiel)
    if rahmen and rahmen:IsShown() then
        Fenster.Verstecken()
    else
        Fenster.Zeigen(beispiel)
    end
end

function Fenster.Sichtbar()
    return rahmen and rahmen:IsShown() and true or false
end

-- =====================================================================
--  Gargul-Ereignisse
-- =====================================================================

Fenster.angebunden = false

--- Haengt sich an Garguls Wurf-Ereignisse.
--  ⚠️ Gargul ruft seine Zuhoerer in einem pcall auf — ein Fehler hier
--  bliebe vollkommen still. Die Handler bleiben deshalb winzig.
function Fenster.GargulAnbinden()
    if Fenster.angebunden then return true end

    local GL = rawget(_G, "Gargul")
    if not GL then return false, "Gargul ist nicht geladen" end
    if not (GL.Events and GL.Events.register) then
        return false, "Gargul hat keine Ereignis-Schnittstelle"
    end

    GL.Events:register("LootHistorieWurfStart", "GL.ROLLOFF_STARTED", function()
        if Fenster.AutoOeffnen() then
            Fenster.Zeigen(false)
        else
            Fenster.Aktualisieren()
        end
    end)

    -- Jeder eingehende Wurf aendert die Reihenfolge.
    GL.Events:register("LootHistorieWurf", "GL.ROLLOFF_ROLL_ACCEPTED", function()
        Fenster.Aktualisieren()
    end)

    GL.Events:register("LootHistorieWurfEnde", "GL.ROLLOFF_STOPPED", function()
        Fenster.Aktualisieren()
    end)

    -- ⭐ Eine Vergabe in Gargul landet auch in unserer Historie — mit
    -- Haupt/Zweitbedarf und Wurf, die der Chat nie liefert. Ob wir sie
    -- eintragen duerfen, entscheidet die Rolle (nur der Schreiber).
    GL.Events:register("LootHistorieVergabe", "GL.ITEM_AWARDED", function(_, Eintrag)
        pcall(ns.Erfassung.GargulVergabe, Eintrag)
        Fenster.Aktualisieren()
    end)
    GL.Events:register("LootHistorieVergabeGeaendert", "GL.ITEM_AWARD_EDITED", function(_, Eintrag)
        pcall(ns.Erfassung.GargulAenderung, Eintrag)
        Fenster.Aktualisieren()
    end)
    GL.Events:register("LootHistorieVergabeZurueck", "GL.ITEM_UNAWARDED", function(_, Eintrag)
        pcall(ns.Erfassung.GargulZurueck, Eintrag)
        Fenster.Aktualisieren()
    end)

    Fenster.angebunden = true
    return true
end

local anbindeRahmen = CreateFrame("Frame")
anbindeRahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
anbindeRahmen:RegisterEvent("ADDON_LOADED")
anbindeRahmen:SetScript("OnEvent", function()
    if not Fenster.angebunden then pcall(Fenster.GargulAnbinden) end
end)

return ns
