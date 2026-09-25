--[[----------------------------------------------------------------------
    Fenster.lua  —  Die Anzeige

    Zwei Ansichten im selben Fenster: die Liste aller Spieler, und nach
    einem Klick die Einzelvergaben eines Spielers.

    ⚠️ Bewusst ohne Bibliotheken und ohne Bildlaufleiste: ein fester
    Satz Zeilen plus Mausrad-Versatz. Das laeuft in jeder Client-Fassung
    gleich, und es gibt nichts, was beim naechsten Patch bricht.

    ⚠️ Das Fenster haelt keinen Zustand ueber die Sitzung hinaus. Es
    liest bei jedem Aufbau frisch aus Garguls Historie — dadurch kann es
    nie etwas Veraltetes zeigen.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Fenster = {}
ns.Fenster = Fenster

local Kern, Quelle = ns.Kern, ns.Quelle

local BREITE, HOEHE = 540, 520
local ZEILEN = 16
local ZEILENHOEHE = 20

-- Farben des Projekts
local GRUEN = "|cff1B6B57"
local GELB  = "|cffffff78"
local GRAU  = "|cff8E9A94"
local ROT   = "|cffff5555"

local rahmen, Zeile, kopf, fuss, titel, zurueckBtn, demoBtn
local Zeitraum = {}

local zustand = { wochen = 0, beispiel = false, spieler = nil, versatz = 0 }

-- =====================================================================
--  Daten
-- =====================================================================

local function historie()
    if zustand.beispiel then return Quelle.Beispiel() end
    return Quelle.Gargul()
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

local function spalte(eltern, x, breite, ausrichtung)
    local t = eltern:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", eltern, "LEFT", x, 0)
    t:SetWidth(breite)
    t:SetJustifyH(ausrichtung or "LEFT")
    t:SetWordWrap(false)
    return t
end

local function baueZeile(index)
    local z = CreateFrame("Button", nil, rahmen)
    z:SetSize(BREITE - 32, ZEILENHOEHE)
    z:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 16, -(112 + (index - 1) * ZEILENHOEHE))

    z:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local h = z:GetHighlightTexture()
    if h then h:SetVertexColor(1, 1, 1, 0.08) end

    z.a = spalte(z, 0,   150)
    z.b = spalte(z, 156,  60, "RIGHT")
    z.c = spalte(z, 224,  60, "RIGHT")
    z.d = spalte(z, 296, 200)

    z:SetScript("OnClick", function()
        if zustand.spieler then return end
        if z.spielername then
            zustand.spieler = z.spielername
            zustand.versatz = 0
            Fenster.Aktualisieren()
        end
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

    -- Mit Escape schliessbar wie jedes andere Fenster
    tinsert(UISpecialFrames, "LootHistorieFenster")

    titel = rahmen:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titel:SetPoint("TOP", rahmen, "TOP", 0, -16)

    local schliessen = CreateFrame("Button", nil, rahmen, "UIPanelCloseButton")
    schliessen:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -6, -6)

    -- Zeitraum
    local auswahl = { { "Alles", 0 }, { "8 Wochen", 8 }, { "4 Wochen", 4 } }
    local x = 16
    for i, Eintrag in ipairs(auswahl) do
        local b = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
        b:SetSize(80, 20)
        b:SetPoint("TOPLEFT", rahmen, "TOPLEFT", x, -48)
        b:SetText(Eintrag[1])
        b.wochen = Eintrag[2]
        b:SetScript("OnClick", function()
            zustand.wochen = Eintrag[2]
            zustand.versatz = 0
            Fenster.Aktualisieren()
        end)
        Zeitraum[i] = b
        x = x + 84
    end

    demoBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    demoBtn:SetSize(100, 20)
    demoBtn:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -16, -48)
    demoBtn:SetText("Beispiel")
    demoBtn:SetScript("OnClick", function()
        zustand.beispiel = not zustand.beispiel
        zustand.spieler = nil
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    zurueckBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    zurueckBtn:SetSize(80, 20)
    zurueckBtn:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 16, -74)
    zurueckBtn:SetText("Zurück")
    zurueckBtn:SetScript("OnClick", function()
        zustand.spieler = nil
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)
    zurueckBtn:Hide()

    kopf = CreateFrame("Frame", nil, rahmen)
    kopf:SetSize(BREITE - 32, 16)
    kopf:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 16, -94)
    kopf.a = spalte(kopf, 0,   150)
    kopf.b = spalte(kopf, 156,  60, "RIGHT")
    kopf.c = spalte(kopf, 224,  60, "RIGHT")
    kopf.d = spalte(kopf, 296, 200)

    Zeile = {}
    for i = 1, ZEILEN do Zeile[i] = baueZeile(i) end

    fuss = rahmen:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fuss:SetPoint("BOTTOMLEFT", rahmen, "BOTTOMLEFT", 16, 18)
    fuss:SetPoint("BOTTOMRIGHT", rahmen, "BOTTOMRIGHT", -16, 18)
    fuss:SetJustifyH("LEFT")

    -- Mausrad statt Bildlaufleiste: ein Teil weniger, der brechen kann.
    rahmen:EnableMouseWheel(true)
    rahmen:SetScript("OnMouseWheel", function(_, richtung)
        local neu = zustand.versatz - richtung
        if neu < 0 then neu = 0 end
        if neu > zustand.maxVersatz then neu = zustand.maxVersatz or 0 end
        if neu ~= zustand.versatz then
            zustand.versatz = neu
            Fenster.Aktualisieren()
        end
    end)
end

-- =====================================================================
--  Anzeige
-- =====================================================================

local function leereZeilen(ab)
    for i = ab, ZEILEN do
        local z = Zeile[i]
        z.spielername = nil
        z.a:SetText("")
        z.b:SetText("")
        z.c:SetText("")
        z.d:SetText("")
    end
end

local function zeigeListe(H)
    kopf.a:SetText(GRAU .. "Spieler|r")
    kopf.b:SetText(GRAU .. "Haupt|r")
    kopf.c:SetText(GRAU .. "Zweit|r")
    kopf.d:SetText(GRAU .. "Zuletzt|r")

    local liste, gesamt, aeltester = Kern.Bilanz(H, seit())
    zustand.maxVersatz = math.max(0, #liste - ZEILEN)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    for i = 1, ZEILEN do
        local z = Zeile[i]
        local e = liste[i + zustand.versatz]
        if not e then break end

        z.spielername = e.name
        z.a:SetText(e.name)
        z.b:SetText(e.haupt > 0 and (GELB .. e.haupt .. "|r") or (GRAU .. "0|r"))
        z.c:SetText(e.zweit > 0 and (GRAU .. e.zweit .. "|r") or "")

        local tage = tageHer(e.letzte)
        if not tage then
            z.d:SetText(GRAU .. "nur Zweitbedarf|r")
        elseif tage == 0 then
            z.d:SetText("heute")
        elseif tage == 1 then
            z.d:SetText("gestern")
        else
            z.d:SetText(string.format("vor %d Tagen", tage))
        end
    end
    leereZeilen(math.min(#liste - zustand.versatz, ZEILEN) + 1)

    local tage = Kern.Raidtage(H, seit(), Quelle.Tag)
    local text = string.format("%d Vergaben · %d Spieler · %d Raidtage", gesamt, #liste, tage)
    if aeltester then
        text = text .. "   |   älteste Aufzeichnung " .. date("%d.%m.%Y", aeltester)
    end
    if #liste > ZEILEN then
        text = text .. "   |   Mausrad blättert"
    end
    fuss:SetText(text)
end

local function zeigeSpieler(H)
    kopf.a:SetText(GRAU .. "Datum|r")
    kopf.b:SetText("")
    kopf.c:SetText("")
    kopf.d:SetText(GRAU .. "Gegenstand|r")

    local liste = Kern.Spieler(H, zustand.spieler, seit())
    zustand.maxVersatz = math.max(0, #liste - ZEILEN)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    for i = 1, ZEILEN do
        local z = Zeile[i]
        local e = liste[i + zustand.versatz]
        if not e then break end

        z.spielername = nil
        z.a:SetText(date("%d.%m.%Y", e.zeit))
        z.b:SetText(e.zweit and (GRAU .. "Zweit|r") or "")
        z.c:SetText("")
        z.d:SetText(Quelle.Gegenstandstext(e.eintrag))
    end
    leereZeilen(math.min(#liste - zustand.versatz, ZEILEN) + 1)

    local haupt = 0
    for _, e in ipairs(liste) do if not e.zweit then haupt = haupt + 1 end end
    fuss:SetText(string.format("%s: %d Vergaben, davon %d Hauptbedarf",
        zustand.spieler, #liste, haupt))
end

function Fenster.Aktualisieren()
    if not rahmen then return end

    -- Zeitraum-Knopf hervorheben
    for _, b in ipairs(Zeitraum) do
        b:SetEnabled(b.wochen ~= zustand.wochen)
    end
    demoBtn:SetText(zustand.beispiel and "Beispiel aus" or "Beispiel")

    local H, grund = historie()

    titel:SetText(GRUEN .. "Loot-Historie|r" ..
        (zustand.beispiel and ("  " .. GELB .. "Beispieldaten|r") or ""))

    if zustand.spieler then
        zurueckBtn:Show()
    else
        zurueckBtn:Hide()
    end

    if not H then
        leereZeilen(1)
        kopf.a:SetText(""); kopf.b:SetText(""); kopf.c:SetText(""); kopf.d:SetText("")
        Zeile[1].a:SetWidth(BREITE - 60)
        Zeile[1].a:SetText(ROT .. tostring(grund) .. "|r")
        Zeile[2].a:SetWidth(BREITE - 60)
        Zeile[2].a:SetText(GRAU .. "Mit „Beispiel\" siehst du, wie die Anzeige aussieht.|r")
        fuss:SetText("")
        return
    end

    Zeile[1].a:SetWidth(150)
    Zeile[2].a:SetWidth(150)

    if zustand.spieler then zeigeSpieler(H) else zeigeListe(H) end
end

-- =====================================================================
--  Steuerung
-- =====================================================================

function Fenster.Zeigen(beispiel)
    baueFenster()
    if beispiel ~= nil then zustand.beispiel = beispiel and true or false end
    zustand.spieler = nil
    zustand.versatz = 0
    rahmen:Show()
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

return ns
