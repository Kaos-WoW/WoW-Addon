--[[----------------------------------------------------------------------
    Einstellungen.lua  —  Die Einstellungsansicht

    Baut ein Panel in das vorhandene Fenster statt eines zweiten Fensters.
    Drei Seiten:
      * Erfassung     was, wo und von wem mitgeschrieben wird
      * Gargul        Wuerfelbereiche, Import, Abgleich, Selbsttests
      * Gruppen       Kader und Raidgruppen

    Alles, was die Befehle koennen, steht hier zum Klicken — die Befehle
    bleiben daneben bestehen.

    ⚠️ Gelesen und geschrieben wird immer direkt in den Einstellungstisch
    von Erfassung.lua. Das Panel haelt keine eigene Kopie; sonst liefe es
    auseinander, sobald jemand doch den Befehl benutzt.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Einstellungen = {}
ns.Einstellungen = Einstellungen

local GRAU  = "|cff8E9A94"
local GELB  = "|cffffff78"
local GRUEN = "|cff55ff55"
local ROT   = "|cffff5555"

local panel
local Seiten, SeitenKnopf = {}, {}
local Schalter = {}     -- name -> CheckButton
local OrtKnopf, QualKnopf, ModusKnopf = {}, {}, {}
local GruppenKnopf = {}
local Text = {}         -- benannte Textfelder, die Aktualisieren beschreibt
local aktuelleSeite = 1
local loeschenBereit

local QUALITAETEN = {
    [0] = "Schlecht", [1] = "Gewöhnlich", [2] = "Ungewöhnlich",
    [3] = "Selten",   [4] = "Episch",     [5] = "Legendär",
}

local ORTE = {
    { "raid",     "Schlachtzug", "Nur in Schlachtzugsinstanzen" },
    { "instanz",  "Instanz",     "Auch Fünfergruppen – zum Erproben" },
    { "ueberall", "Überall",     "Ohne Einschränkung; auch Weltdrops" },
}

local MODI = {
    { "auto",  "Automatisch", "Der Plündermeister schreibt; gibt es keinen, der Raidleiter." },
    { "immer", "Immer",       "Dieser Spieler schreibt mit – egal, wer sonst." },
    { "nie",   "Nie",         "Dieser Spieler schreibt nicht mit, empfängt nur." },
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

local function absatz(eltern, x, y, breite, vorlage)
    local t = beschriftung(eltern, x, y, "", vorlage or "GameFontDisableSmall")
    t:SetWidth(breite)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(true)
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

local function eingabe(eltern, x, y, breite, beiEnter)
    local e = CreateFrame("EditBox", nil, eltern, "InputBoxTemplate")
    e:SetPoint("TOPLEFT", eltern, "TOPLEFT", x + 6, y)
    e:SetSize(breite, 22)
    e:SetAutoFocus(false)
    e:SetMaxLetters(400)
    e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(s)
        beiEnter(s:GetText())
        s:ClearFocus()
    end)
    return e
end

-- =====================================================================
--  Seite 1: Erfassung
-- =====================================================================

local function baueErfassung(S)
    local y = 0

    beschriftung(S, 0, y, "Mitschreiben")
    y = y - 22

    Schalter.erfassen = schalter(S, 0, y, "Vergaben aufzeichnen",
        "Aus heißt: nichts Neues wird erfasst. Vorhandenes bleibt.",
        function(an) d().erfassen = an end)
    y = y - 44

    Schalter.nurGewuerfelt = schalter(S, 0, y, "Nur Ausgewürfeltes zählen",
        "⚠ Streng: Ohne Bedarfswurf zugeteilte Stücke fallen dann heraus.",
        function(an) d().nurGewuerfelt = an end)
    y = y - 48

    beschriftung(S, 0, y, "Wo wird mitgeschrieben")
    y = y - 24

    local x = 0
    for i, O in ipairs(ORTE) do
        OrtKnopf[i] = knopf(S, x, y, 104, O[2], function()
            d().ort = O[1]
            Einstellungen.Aktualisieren()
        end)
        OrtKnopf[i].ort = O[1]
        OrtKnopf[i].hinweis = O[3]
        x = x + 108
    end
    y = y - 22

    Text.ortHinweis = beschriftung(S, 0, y, "", "GameFontDisableSmall")
    y = y - 30

    beschriftung(S, 0, y, "Ab welcher Qualität")
    y = y - 24

    x = 0
    for stufe = 1, 5 do
        QualKnopf[stufe] = knopf(S, x, y, 100, QUALITAETEN[stufe], function()
            d().mindestQualitaet = stufe
            Einstellungen.Aktualisieren()
        end)
        QualKnopf[stufe].stufe = stufe
        x = x + 104
    end
    y = y - 24

    beschriftung(S, 0, y,
        GRAU .. "Auf Stufe 60 fällt in manchen Raids überwiegend Blaues – " ..
        "lieber zu viel erfassen als einen Drop verlieren.|r", "GameFontDisableSmall")
    y = y - 34

    beschriftung(S, 0, y, "Wer schreibt mit")
    y = y - 24

    x = 0
    for i, M in ipairs(MODI) do
        ModusKnopf[i] = knopf(S, x, y, 120, M[2], function()
            d().schreiben = M[1]
            Einstellungen.Aktualisieren()
        end)
        ModusKnopf[i].modus = M[1]
        ModusKnopf[i].hinweis = M[3]
        x = x + 124
    end
    y = y - 24

    Text.modusHinweis = absatz(S, 0, y, 500)
    y = y - 30
    Text.schreiber = absatz(S, 0, y, 500)
end

-- =====================================================================
--  Seite 2: Gargul und Abgleich
-- =====================================================================

local function baueGargul(S)
    local y = 0

    beschriftung(S, 0, y, "Gargul")
    y = y - 22

    Text.bereiche = absatz(S, 0, y, 500, "GameFontHighlightSmall")
    y = y - 34

    knopf(S, 0, y, 200, "Würfelbereiche auf 100/50", function()
        local ok, grund = ns.Quelle.GargulBereicheSetzen()
        Text.rueck:SetText(ok and (GRUEN .. "Bei Gargul eingestellt: MS 1-100, OS 1-50|r")
                               or (ROT .. tostring(grund) .. "|r"))
        Einstellungen.Aktualisieren()
    end)

    knopf(S, 208, y, 200, "Aus Gargul übernehmen", function()
        local neu, doppelt = ns.Quelle.GargulImport()
        if not neu then
            Text.rueck:SetText(ROT .. tostring(doppelt) .. "|r")
        else
            Text.rueck:SetText(string.format(
                GRUEN .. "%d übernommen|r" .. GRAU .. "%s|r", neu,
                doppelt > 0 and (", " .. doppelt .. " schon vorhanden") or ""))
        end
        if ns.Fenster then ns.Fenster.Aktualisieren() end
    end)
    y = y - 34

    Schalter.autoOeffnen = schalter(S, 0, y, "Bei Wurfbeginn selbst öffnen",
        "Die Übersicht springt auf, sobald der erste Bedarfswurf fällt.",
        function(an) ns.Fenster.AutoSetzen(an) end)
    y = y - 54

    beschriftung(S, 0, y, "Abgleich")
    y = y - 22

    Text.abgleich = absatz(S, 0, y, 500, "GameFontHighlightSmall")
    y = y - 44

    knopf(S, 0, y, 200, "Jetzt abgleichen", function()
        local ok, grund = ns.Abgleich.Starten()
        Text.rueck:SetText(ok and (GRUEN .. "Abgleich gestartet – das Ergebnis steht im Chat.|r")
                               or (ROT .. tostring(grund) .. "|r"))
    end)

    knopf(S, 208, y, 140, "Selbsttests", function()
        if ns.Tests then ns.Tests.Alle() end
        Text.rueck:SetText(GRAU .. "Ergebnis steht im Chat.|r")
    end)
    y = y - 30

    Text.rueck = absatz(S, 0, y, 500)
end

-- =====================================================================
--  Seite 3: Gruppen
-- =====================================================================

local function gewaehlteGruppe()
    return ns.Gruppen.AktivName()
end

local function baueGruppen(S)
    local y = 0

    beschriftung(S, 0, y, "Gruppen")
    y = y - 22

    absatz(S, 0, y, 520):SetText(GRAU ..
        "Eine Gruppe bestimmt, wer in der Liste steht – auch ohne Vergabe. " ..
        "Vergaben merken sich die Gruppe, die beim Eintragen aktiv war.|r")
    y = y - 40

    -- Bis zu zwei Reihen mit je vier Gruppen
    for i = 1, 8 do
        local reihe, spalte = math.floor((i - 1) / 4), (i - 1) % 4
        local b = knopf(S, spalte * 128, y - reihe * 26, 124, "", function(s)
            if s.gruppe then ns.Gruppen.Aktivieren(s.gruppe) end
            loeschenBereit = nil
            Einstellungen.Aktualisieren()
        end)
        b:Hide()
        GruppenKnopf[i] = b
    end
    y = y - 58

    Text.gruppeInfo = absatz(S, 0, y, 520, "GameFontHighlightSmall")
    y = y - 40

    Text.modusKnopf = knopf(S, 0, y, 150, "Art wechseln", function()
        local g = gewaehlteGruppe()
        if g then ns.Gruppen.ModusUmschalten(g) end
        Einstellungen.Aktualisieren()
    end)

    Text.ausGruppe = knopf(S, 156, y, 190, "Kader aus Gruppe füllen", function()
        local g = gewaehlteGruppe()
        local n = g and ns.Gruppen.KaderAusGruppe(g)
        Text.rueck3:SetText(n and (GRUEN .. n .. " Namen übernommen|r") or (ROT .. "keine Gruppe gewählt|r"))
        Einstellungen.Aktualisieren()
    end)

    Text.loeschen = knopf(S, 352, y, 150, "Löschen", function()
        local g = gewaehlteGruppe()
        if not g then return end
        if loeschenBereit == g then
            ns.Gruppen.Loeschen(g)
            loeschenBereit = nil
            Text.rueck3:SetText(GRAU .. "Gruppe gelöscht.|r")
        else
            loeschenBereit = g
            Text.rueck3:SetText(GELB .. "Nochmal klicken, um „" .. g .. "“ zu löschen.|r")
        end
        Einstellungen.Aktualisieren()
    end)
    y = y - 34

    beschriftung(S, 0, y, "Neue Gruppe", "GameFontNormalSmall")
    Text.neu = eingabe(S, 0, y - 16, 300, function(name)
        local ok, grund = ns.Gruppen.Anlegen(name)
        Text.rueck3:SetText(ok and (GRUEN .. "Angelegt.|r") or (ROT .. tostring(grund) .. "|r"))
        Text.neu:SetText("")
        Einstellungen.Aktualisieren()
    end)
    knopf(S, 316, y - 16, 120, "Anlegen", function()
        Text.neu:GetScript("OnEnterPressed")(Text.neu)
    end)
    y = y - 46

    beschriftung(S, 0, y, "Namen zum Kader (mit Komma trennen)", "GameFontNormalSmall")
    Text.namen = eingabe(S, 0, y - 16, 300, function(text)
        local g = gewaehlteGruppe()
        local n = g and ns.Gruppen.KaderErgaenzen(g, text)
        Text.rueck3:SetText(n and (GRUEN .. n .. " ergänzt|r") or (ROT .. "keine Gruppe gewählt|r"))
        Text.namen:SetText("")
        Einstellungen.Aktualisieren()
    end)
    knopf(S, 316, y - 16, 120, "Hinzufügen", function()
        Text.namen:GetScript("OnEnterPressed")(Text.namen)
    end)
    y = y - 46

    Text.rueck3 = absatz(S, 0, y, 520)
end

-- =====================================================================
--  Aufbau
-- =====================================================================

local function zeigeSeite(nr)
    aktuelleSeite = nr
    for i, S in ipairs(Seiten) do S:SetShown(i == nr) end
    for i, b in ipairs(SeitenKnopf) do b:SetEnabled(i ~= nr) end
    Einstellungen.Aktualisieren()
end

function Einstellungen.Bauen(eltern, breite)
    if panel then return panel end

    panel = CreateFrame("Frame", nil, eltern)
    panel:SetPoint("TOPLEFT", eltern, "TOPLEFT", 20, -72)
    panel:SetPoint("BOTTOMRIGHT", eltern, "BOTTOMRIGHT", -20, 40)
    panel:Hide()

    local namen = { "Erfassung", "Gargul & Abgleich", "Gruppen" }
    local breiten = { 120, 160, 120 }
    local x = 0
    for i, n in ipairs(namen) do
        SeitenKnopf[i] = knopf(panel, x, 0, breiten[i], n, function() zeigeSeite(i) end)
        x = x + breiten[i] + 4
    end

    for i = 1, 3 do
        local S = CreateFrame("Frame", nil, panel)
        S:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -34)
        S:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
        S:Hide()
        Seiten[i] = S
    end

    baueErfassung(Seiten[1])
    baueGargul(Seiten[2])
    baueGruppen(Seiten[3])

    return panel
end

-- =====================================================================
--  Anzeige
-- =====================================================================

local function aktualisiereErfassung(e)
    Schalter.erfassen:SetChecked(e.erfassen)
    Schalter.nurGewuerfelt:SetChecked(e.nurGewuerfelt)

    for _, b in ipairs(OrtKnopf) do
        -- Der gewaehlte Knopf ist ausgegraut: er ist bereits aktiv.
        b:SetEnabled(b.ort ~= e.ort)
        if b.ort == e.ort then Text.ortHinweis:SetText(GRAU .. b.hinweis .. "|r") end
    end
    for stufe, b in pairs(QualKnopf) do b:SetEnabled(stufe ~= e.mindestQualitaet) end

    for _, b in ipairs(ModusKnopf) do
        b:SetEnabled(b.modus ~= (e.schreiben or "auto"))
        if b.modus == (e.schreiben or "auto") then Text.modusHinweis:SetText(GRAU .. b.hinweis .. "|r") end
    end

    if ns.Rolle then
        local darf, grund = ns.Rolle.IchSchreibe()
        local wer = ns.Rolle.AktuellerSchreiber()
        local zeile = darf and (GRUEN .. "Du schreibst gerade mit|r " .. GRAU .. "(" .. tostring(grund) .. ")|r")
                           or (GELB .. "Du schreibst gerade nicht mit|r " .. GRAU .. "(" .. tostring(grund) .. ")|r")
        if wer and not darf then zeile = zeile .. GRAU .. " – Schreiber: " .. wer .. "|r" end
        Text.schreiber:SetText(zeile)
    end
end

local function aktualisiereGargul()
    Schalter.autoOeffnen:SetChecked(ns.Fenster.AutoOeffnen())

    local B, grund = ns.Quelle.GargulBereiche()
    if not B then
        Text.bereiche:SetText(GRAU .. "Würfelbereiche: " .. tostring(grund) ..
            ". Ohne Gargul liest das Addon die Würfe selbst aus dem Chat.|r")
    elseif B.ok then
        Text.bereiche:SetText(GRUEN .. "Würfelbereiche stimmen|r " .. GRAU ..
            "(100 = Hauptbedarf, 50 = Zweitbedarf) – " .. table.concat(B.bereiche, ", ") .. "|r")
    else
        Text.bereiche:SetText(ROT .. "Würfelbereiche passen nicht|r " .. GRAU ..
            "Gargul kennt: " .. table.concat(B.bereiche, ", ") ..
            ". Erwartet 1-100 und 1-50, sonst wird Haupt-/Zweitbedarf nicht erkannt.|r")
    end

    local ab = ns.Abgleich
    local n, summe = ab.Stand()
    local bekannte = 0
    for _ in pairs(ab.Bekannte()) do bekannte = bekannte + 1 end
    Text.abgleich:SetText(string.format(
        "%d Einträge bei dir. %d Mitspieler mit dem Addon erkannt, %s",
        n, bekannte,
        #ab.Abweichend > 0 and (GELB .. #ab.Abweichend .. " davon weichen ab.|r")
                             or (GRAU .. "keine Abweichung bekannt.|r")))
end

local function aktualisiereGruppen()
    local Namen = ns.Gruppen.Namen()
    local aktiv = ns.Gruppen.AktivName()

    for i, b in ipairs(GruppenKnopf) do
        local n = Namen[i]
        if n then
            b.gruppe = n
            b:SetText(n == aktiv and (GELB .. n .. "|r") or n)
            b:SetEnabled(n ~= aktiv)
            b:Show()
        else
            b.gruppe = nil
            b:Hide()
        end
    end

    local G = ns.Gruppen.Holen(aktiv)
    if not G then
        Text.gruppeInfo:SetText(GRAU .. (#Namen == 0
            and "Noch keine Gruppe. Unten eine anlegen, z. B. „40er“ oder „10er“."
            or "Keine Gruppe aktiv.") .. "|r")
    else
        local art = (G.modus == "raid")
            and "Raidgruppe: In der Liste stehen alle, die gerade in deiner Gruppe sind."
            or  string.format("Kader: %d Namen stehen immer in der Liste.", #(G.kader or {}))
        local vorschau = ""
        if G.modus ~= "raid" and #(G.kader or {}) > 0 then
            local teile = {}
            for i, n in ipairs(G.kader) do
                if i > 12 then teile[#teile + 1] = "…" break end
                teile[#teile + 1] = n
            end
            vorschau = "\n" .. GRAU .. table.concat(teile, ", ") .. "|r"
        end
        Text.gruppeInfo:SetText(GELB .. "Aktiv: " .. G.name .. "|r  " .. art .. vorschau)
    end

    Text.modusKnopf:SetEnabled(G ~= nil)
    Text.ausGruppe:SetEnabled(G ~= nil and G.modus ~= "raid")
    Text.loeschen:SetEnabled(G ~= nil)
    Text.loeschen:SetText(loeschenBereit and loeschenBereit == aktiv and "Wirklich löschen?" or "Löschen")
    if G then
        Text.modusKnopf:SetText(G.modus == "raid" and "Auf Kader stellen" or "Auf Raidgruppe stellen")
    end
end

function Einstellungen.Aktualisieren()
    if not panel then return end
    local ok, fehler = pcall(function()
        if aktuelleSeite == 1 then aktualisiereErfassung(d())
        elseif aktuelleSeite == 2 then aktualisiereGargul()
        else aktualisiereGruppen() end
    end)
    if not ok then
        print("|cff1B6B57Loot-Historie|r: |cffff5555Fehler in den Einstellungen: " .. tostring(fehler) .. "|r")
    end
end

function Einstellungen.Zeigen()
    if not panel then return end
    panel:Show()
    zeigeSeite(aktuelleSeite)
end

function Einstellungen.Verstecken()
    if panel then panel:Hide() end
end

return ns
