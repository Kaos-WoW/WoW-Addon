--[[----------------------------------------------------------------------
    Einstellungen.lua  —  Die Einstellungsansicht

    Baut ein Panel in das vorhandene Fenster statt eines zweiten Fensters.
    Alles, was `/lh filter`, `/lh auto` und `/lh import` koennen, steht
    hier zum Klicken — die Befehle bleiben daneben bestehen.

    ⚠️ Gelesen und geschrieben wird immer direkt in den Einstellungstisch
    von Erfassung.lua. Das Panel haelt keine eigene Kopie; sonst liefe es
    auseinander, sobald jemand doch den Befehl benutzt.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Einstellungen = {}
ns.Einstellungen = Einstellungen

local GRAU = "|cff8E9A94"
local GELB = "|cffffff78"

local panel
local Schalter = {}     -- name -> CheckButton
local OrtKnopf = {}
local QualKnopf = {}
local rueckmeldung

local QUALITAETEN = {
    [0] = "Schlecht", [1] = "Gewöhnlich", [2] = "Ungewöhnlich",
    [3] = "Selten",   [4] = "Episch",     [5] = "Legendär",
}

local ORTE = {
    { "raid",     "Schlachtzug", "Nur in Schlachtzugsinstanzen" },
    { "instanz",  "Instanz",     "Auch Fünfergruppen – zum Erproben" },
    { "ueberall", "Überall",     "Ohne Einschränkung; auch Weltdrops" },
}

local function d()
    return ns.Erfassung.Einstellungen()
end

-- =====================================================================
--  Bausteine
-- =====================================================================

local function beschriftung(eltern, x, y, text, vorlage)
    local t = eltern:CreateFontString(nil, "OVERLAY", vorlage or "GameFontNormal")
    t:SetPoint("TOPLEFT", eltern, "TOPLEFT", x, y)
    t:SetText(text)
    return t
end

local function schalter(eltern, x, y, text, hinweis, beiKlick)
    local k = CreateFrame("CheckButton", nil, eltern, "UICheckButtonTemplate")
    k:SetPoint("TOPLEFT", eltern, "TOPLEFT", x, y)
    k:SetSize(26, 26)

    local t = k:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", k, "RIGHT", 4, 0)
    t:SetText(text)

    if hinweis then
        local h = k:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -2)
        h:SetWidth(420)
        h:SetJustifyH("LEFT")
        h:SetText(GRAU .. hinweis .. "|r")
    end

    k:SetScript("OnClick", function(s)
        beiKlick(s:GetChecked() and true or false)
        Einstellungen.Aktualisieren()
    end)
    return k
end

local function knopf(eltern, x, y, breite, text, beiKlick)
    local b = CreateFrame("Button", nil, eltern, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", eltern, "TOPLEFT", x, y)
    b:SetSize(breite, 22)
    b:SetText(text)
    b:SetScript("OnClick", beiKlick)
    return b
end

-- =====================================================================
--  Aufbau
-- =====================================================================

function Einstellungen.Bauen(eltern, breite)
    if panel then return panel end

    panel = CreateFrame("Frame", nil, eltern)
    panel:SetPoint("TOPLEFT", eltern, "TOPLEFT", 20, -96)
    panel:SetPoint("BOTTOMRIGHT", eltern, "BOTTOMRIGHT", -20, 40)
    panel:Hide()

    local y = 0

    beschriftung(panel, 0, y, "Mitschreiben")
    y = y - 22

    Schalter.erfassen = schalter(panel, 0, y, "Vergaben aufzeichnen",
        "Aus heißt: nichts Neues wird erfasst. Vorhandenes bleibt.",
        function(an) d().erfassen = an end)
    y = y - 44

    Schalter.nurGewuerfelt = schalter(panel, 0, y, "Nur Ausgewürfeltes zählen",
        "⚠ Streng: Ohne Bedarfswurf zugeteilte Stücke fallen dann heraus.",
        function(an) d().nurGewuerfelt = an end)
    y = y - 48

    beschriftung(panel, 0, y, "Fenster")
    y = y - 22

    Schalter.autoOeffnen = schalter(panel, 0, y, "Bei Wurfbeginn selbst öffnen",
        "Die Übersicht springt auf, sobald der erste Bedarfswurf fällt.",
        function(an) ns.Fenster.AutoSetzen(an) end)
    y = y - 48

    beschriftung(panel, 0, y, "Wo wird mitgeschrieben")
    y = y - 24

    local x = 0
    for i, O in ipairs(ORTE) do
        OrtKnopf[i] = knopf(panel, x, y, 104, O[2], function()
            d().ort = O[1]
            Einstellungen.Aktualisieren()
        end)
        OrtKnopf[i].ort = O[1]
        OrtKnopf[i].hinweis = O[3]
        x = x + 108
    end
    y = y - 22

    Einstellungen.ortHinweis = beschriftung(panel, 0, y, "", "GameFontDisableSmall")
    y = y - 34

    beschriftung(panel, 0, y, "Ab welcher Qualität")
    y = y - 24

    x = 0
    for stufe = 1, 5 do
        QualKnopf[stufe] = knopf(panel, x, y, 100, QUALITAETEN[stufe], function()
            d().mindestQualitaet = stufe
            Einstellungen.Aktualisieren()
        end)
        QualKnopf[stufe].stufe = stufe
        x = x + 104
    end
    y = y - 24

    beschriftung(panel, 0, y,
        GRAU .. "Auf Stufe 60 fällt in manchen Raids überwiegend Blaues – " ..
        "lieber zu viel erfassen als einen Drop verlieren.|r", "GameFontDisableSmall")
    y = y - 40

    beschriftung(panel, 0, y, "Sonstiges")
    y = y - 24

    knopf(panel, 0, y, 200, "Aus Gargul übernehmen", function()
        local neu, doppelt = ns.Quelle.GargulImport()
        if not neu then
            rueckmeldung:SetText("|cffff5555" .. tostring(doppelt) .. "|r")
        else
            rueckmeldung:SetText(string.format(
                "|cff55ff55%d übernommen|r" .. GRAU .. "%s|r", neu,
                doppelt > 0 and (", " .. doppelt .. " schon vorhanden") or ""))
        end
        if ns.Fenster then ns.Fenster.Aktualisieren() end
    end)

    knopf(panel, 208, y, 140, "Selbsttests", function()
        if ns.Tests then ns.Tests.Alle() end
        rueckmeldung:SetText(GRAU .. "Ergebnis steht im Chat.|r")
    end)
    y = y - 26

    rueckmeldung = beschriftung(panel, 0, y, "", "GameFontDisableSmall")

    return panel
end

-- =====================================================================
--  Anzeige
-- =====================================================================

function Einstellungen.Aktualisieren()
    if not panel then return end
    local e = d()

    Schalter.erfassen:SetChecked(e.erfassen)
    Schalter.nurGewuerfelt:SetChecked(e.nurGewuerfelt)
    Schalter.autoOeffnen:SetChecked(ns.Fenster.AutoOeffnen())

    for _, b in ipairs(OrtKnopf) do
        -- Der gewaehlte Knopf ist ausgegraut: er ist bereits aktiv.
        b:SetEnabled(b.ort ~= e.ort)
        if b.ort == e.ort then
            Einstellungen.ortHinweis:SetText(GRAU .. b.hinweis .. "|r")
        end
    end

    for stufe, b in pairs(QualKnopf) do
        b:SetEnabled(stufe ~= e.mindestQualitaet)
    end
end

function Einstellungen.Zeigen()
    if panel then panel:Show() Einstellungen.Aktualisieren() end
end

function Einstellungen.Verstecken()
    if panel then panel:Hide() end
end

return ns
