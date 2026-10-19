--[[----------------------------------------------------------------------
    Fenster.lua  —  Die Uebersicht (Look wie KaosUI)

    Ansichten im selben Fenster:
      * die Liste aller Spieler
      * der Verlauf: wer bekam was, wann (neueste zuerst)
      * nach einem Klick die Einzelvergaben eines Spielers
      * waehrend eines Wurfs: die Wuerfelnden oben, hervorgehoben,
        **der mit den wenigsten Stuecken zuerst**
    (Die Einstellungen sind ein eigenes Fenster, Einstellungen.lua.)

    ⚠️ Bewusst ohne Bildlaufleiste: ein fester Satz Zeilen plus
    Mausrad-Versatz. Es gibt nichts, was beim naechsten Patch bricht, und
    das Fenster liest bei jedem Aufbau frisch — es kann nie etwas
    Veraltetes zeigen.

    Gestaltet mit den Bausteinen aus Stil.lua (dieselben wie im
    Einstellungsfenster): dunkle Flaechen, Petrol als Akzent, Inter.
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Fenster = {}
ns.Fenster = Fenster

local Kern, Quelle = ns.Kern, ns.Quelle
local S = ns.Stil
local C = S.C

local BREITE, HOEHE = 880, 600
local KOPF, FUSS = 44, 40
local MAXZEILEN, ZEILENHOEHE = 40, 24
local TAFEL_X = 16
local TAFEL_OBEN = KOPF + 84      -- Abstand der Tafel vom oberen Fensterrand
local zeilenSicht = 16            -- wie viele Zeilen gerade hineinpassen

-- Farben als Textcodes fuer einzelne Woerter
local HELL  = S.Code(C.white)
local GRAU  = S.Code(C.mu)
local GELB  = S.Code(C.warn)
local ROT   = S.Code(C.bad)
local GRUEN = S.Code(C.ok)
local AKZENT = S.Code(C.ac)

local rahmen, kopfZeile, tafel, fuss, unterzeile, kopfTag
local zeilen = {}
local ansichtSeg, zeitSeg, abgleichBtn, einstellBtn, gruppeBtn, zurueckBtn, beispielBtn, probeBtn, nurBtn, wurfBtn, abschlussBtn, offeneBtn
local syncBtn, tagBtn, sendenBtn      -- Ansicht „Einteilung“
local probeLeiste, probeSpielerDropdown, probeRaidBtn, probeHauptBtn, probeOSBtn, probeBankBtn, probeAbmeldBtn, probeUnentBtn, probeScriptBtn, probeResetBtn
local zustand = { wochen = 0, beispiel = false, probe = false, probeSpieler = "Anna", spieler = nil, versatz = 0, maxVersatz = 0,
                  ansicht = "liste", gruppe = nil, alleSpieler = false }

-- Spaltenlagen je Ansicht, abhaengig von der Zeilenbreite w:
-- { x, Breite, Ausrichtung }. Von rechts gerechnet, die erste Spalte
-- nimmt den Rest — dadurch waechst eine Spalte mit dem Fenster.
local function layout(name, w)
    local L6 = 6
    if name == "verlauf" then
        local a, b, c = 120, 190, 70
        local dx = a + L6 + b + L6 + c + L6
        return { { 0, a, "LEFT" }, { a + L6, b, "LEFT" }, { a + L6 + b + L6, c, "LEFT" },
                 { dx, math.max(80, w - dx - 96), "LEFT" }, { 0, 1, "LEFT" } }
    elseif name == "bank" then
        local a, b, c, d, e = 140, 90, 80, 84, 84
        local xB = a + L6
        local xC = xB + b + L6
        local xD = xC + c + L6
        local xE = xD + d + L6
        return { { 0, a, "LEFT" }, { xB, b, "LEFT" }, { xC, c, "CENTER" },
                 { xD, d, "CENTER" }, { xE, e, "CENTER" } }
    elseif name == "einteilung" then
        -- ⭐ Zwei Listen (Entscheid 22.10.2026): links verfügbar (Name | Hinweis | Knopf), rechts in der Gruppe
        -- (Name | Rang | Knopf). Die Knöpfe setzt zeigeEinteilung ans Ende ihrer Hälfte.
        local hw = math.floor((w - 16) / 2)
        local an = math.max(60, hw - 104 - 8 - 96 - L6)
        local cn = math.max(60, hw - 96 - 8 - 90 - L6)
        return { { 0, an, "LEFT" }, { an + L6, 96, "LEFT" }, { hw + 16, cn, "LEFT" },
                 { hw + 16 + cn + L6, 90, "LEFT" }, { 0, 1, "LEFT" } }
    elseif name == "spieler" then
        local a, b, c = 100, 105, 65
        local dx = a + L6 + b + L6 + c + L6
        return { { 0, a, "LEFT" }, { a + L6, b, "LEFT" }, { a + L6 + b + L6, c, "RIGHT" },
                 { dx, math.max(80, w - dx - 96), "LEFT" }, { 0, 1, "LEFT" } }
    end
    -- liste: Spieler | Wertung | Zweit | Zuletzt | Wurf
    local ew, dw, cw, bw = 120, 160, 60, 64
    local ex = w - ew
    local dx = ex - L6 - dw
    local cx = dx - L6 - cw
    local bx = cx - L6 - bw
    return { { 0, math.max(80, bx - L6), "LEFT" }, { bx, bw, "RIGHT" }, { cx, cw, "RIGHT" },
             { dx, dw, "LEFT" }, { ex, ew, "RIGHT" } }
end
local SPALTEN = { "a", "b", "c", "d", "e" }

-- =====================================================================
--  Einstellungen
-- =====================================================================

local function db()
    FairshareDB = FairshareDB or {}
    if FairshareDB.autoOeffnen == nil then FairshareDB.autoOeffnen = true end
    return FairshareDB
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
    if zustand.probe then return (ns.Probe and ns.Probe.Historie and ns.Probe.Historie()) or {} end
    if zustand.beispiel then return Quelle.Beispiel() end
    local H, grund = Quelle.Historie()
    if not H then return nil, grund end
    return Kern.NachGruppe(H, zustand.gruppe)
end

local function wurf()
    if zustand.probe then return nil end
    if zustand.beispiel then return Quelle.BeispielWurf() end
    return Quelle.Wurf()
end

--- ⭐ In einer Gruppe zeigt die Liste nur die Spieler, die gerade dabei sind.
--  Ohne Gruppe (oder auf Wunsch, oder bei Beispieldaten) gilt alles.
--  @return Liste der Namen, oder nil fuer „alle"
local function nurGruppe()
    if zustand.beispiel or zustand.probe or zustand.alleSpieler or not ns.Rolle then return nil end
    if not (IsInGroup and IsInGroup()) then return nil end
    return ns.Rolle.Namen()
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

local function version()
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
    if not f then return "?" end
    local ok, v = pcall(f, ADDON, "Version")
    return (ok and v) or "?"
end

local function spalte(eltern, groesse, farbe)
    local t = S.Text(eltern, groesse or 13, farbe or C.tx, "LEFT")
    return t
end

local function baueZeile(index)
    local z = CreateFrame("Button", nil, tafel)
    z:SetHeight(ZEILENHOEHE)
    z:SetPoint("TOPLEFT", tafel, "TOPLEFT", 12, -(32 + (index - 1) * ZEILENHOEHE))
    z:SetPoint("TOPRIGHT", tafel, "TOPRIGHT", -12, -(32 + (index - 1) * ZEILENHOEHE))

    z.hover = S.Form(z, 5, C.hover)
    z.hover:SetShown(false)
    z.markiert = S.Form(z, 5, C.acb, nil, "BACKGROUND", 1)
    z.markiert:SetShown(false)

    for _, k in ipairs(SPALTEN) do z[k] = spalte(z) end

    z:SetScript("OnEnter", function(s) if s.spielername then s.hover:SetShown(true) end end)
    z:SetScript("OnLeave", function(s) s.hover:SetShown(false) end)
    if z.RegisterForClicks then z:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    z:SetScript("OnClick", function(s, taste)
        if zustand.ansicht == "einteilung" then return end      -- dort arbeiten nur die Knöpfe
        if taste == "RightButton" then return end
        if zustand.ansicht == "bank" then return end
        if zustand.spieler or not s.spielername then return end
        zustand.spieler = s.spielername
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    -- Vergabe zurücknehmen (nur in Verlauf und Spielerdetail sichtbar)
    z.undo = S.Knopf(z, L["Rückgängig"], "link", 20)
    z.undo:SetPoint("RIGHT", z, "RIGHT", 0, 0)
    z.undo:SetFrameLevel(z:GetFrameLevel() + 3)
    z.undo:Hide()
    z.undo:SetScript("OnClick", function() Fenster.RueckgaengigKlick(z.eintragId) end)

    -- Bank & Unentschuldigt (nur in Bank-Ansicht sichtbar)
    z.bankBtn = S.Knopf(z, L["Bank"], "secondary", 20)
    z.bankBtn:SetFest(76)
    z.bankBtn:SetFrameLevel(z:GetFrameLevel() + 3)
    z.bankBtn:Hide()

    z.unentBtn = S.Knopf(z, L["Unent."], "secondary", 20)
    z.unentBtn:SetFest(88)
    z.unentBtn:SetFrameLevel(z:GetFrameLevel() + 3)
    z.unentBtn:Hide()

    z.vergessenBtn = S.Knopf(z, L["Keine Meldung"], "secondary", 20)
    z.vergessenBtn:SetFest(112)
    z.vergessenBtn:SetFrameLevel(z:GetFrameLevel() + 3)
    z.vergessenBtn:Hide()

    z.abmeldBtn = S.Knopf(z, L["Abwesend"], "secondary", 20)
    z.abmeldBtn:SetFest(100)
    z.abmeldBtn:SetFrameLevel(z:GetFrameLevel() + 3)
    z.abmeldBtn:Hide()

    -- Einteilung: links in die gewaehlte Gruppe setzen, rechts wieder herausnehmen
    z.teilBtn = S.Knopf(z, L["Hinzufügen"], "secondary", 20)
    z.teilBtn:SetFest(104)
    z.teilBtn:SetFrameLevel(z:GetFrameLevel() + 3)
    z.teilBtn:Hide()
    z.entfBtn = S.Knopf(z, L["Entfernen"], "secondary", 20)
    z.entfBtn:SetFest(96)
    z.entfBtn:SetFrameLevel(z:GetFrameLevel() + 3)
    z.entfBtn:Hide()

    -- Probe-Modus: in den Raid / aus dem Raid
    z.probeRaidBtn = S.Knopf(z, "", "secondary", 20)
    z.probeRaidBtn:SetFest(76)
    z.probeRaidBtn:SetFrameLevel(z:GetFrameLevel() + 3)
    z.probeRaidBtn:Hide()
    return z
end

local function kopfBauen()
    local k = CreateFrame("Frame", nil, rahmen)
    k:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 1, -1)
    k:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -1, -1)
    k:SetHeight(KOPF)
    S.Form(k, 9, C.p1, nil, "BACKGROUND", 0, 0, { tl = true, tr = true })
    local linie = S.Tex(k, "BORDER", C.ln)
    linie:SetHeight(1)
    linie:SetPoint("BOTTOMLEFT")
    linie:SetPoint("BOTTOMRIGHT")

    k:EnableMouse(true)
    k:RegisterForDrag("LeftButton")
    k:SetScript("OnDragStart", function() rahmen:StartMoving() end)
    k:SetScript("OnDragStop", function()
        rahmen:StopMovingOrSizing()
        if rahmen.speichern then rahmen.speichern() end
    end)

    local logo = CreateFrame("Frame", nil, k)
    logo:SetSize(22, 22)
    logo:SetPoint("LEFT", k, "LEFT", 12, 0)
    S.Form(logo, 5, C.ac)
    local l = S.Text(logo, 13, C.white, "CENTER")
    l:SetPoint("CENTER", 1, 0)
    l:SetText("F")

    local name = S.Text(k, 14, C.tx, "LEFT")
    name:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    name:SetText("Fairshare")

    local tag = CreateFrame("Frame", nil, k)
    tag:SetHeight(17)
    tag:SetPoint("LEFT", name, "RIGHT", 10, 0)
    tag.kasten = S.Kasten(tag, 4, C.p1, C.ln)
    tag.text = S.Text(tag, 11, C.mu, "CENTER")
    tag.text:SetPoint("CENTER", 0, 0)
    kopfTag = tag

    local zu = CreateFrame("Button", nil, k)
    zu:SetSize(20, 20)
    zu:SetPoint("RIGHT", k, "RIGHT", -12, 0)
    local x = S.Symbol(zu, "x.tga", 16, C.mu)
    x:SetPoint("CENTER")
    zu:SetScript("OnEnter", function() S.Faerbe(x, C.tx) end)
    zu:SetScript("OnLeave", function() S.Faerbe(x, C.mu) end)
    zu:SetScript("OnClick", function() rahmen:Hide() end)
end

--- ⭐ Die Raid-ID der Einteilung: diese oder die nächste (Entscheid 22.10.2026, einmal je Raid-ID).
--  @return Schlüsseldatum, Beschriftung, Liste
local function einteilungsTag()
    local liste = ns.Gruppen.IdListe()
    local wahl = liste[1]
    for _, t in ipairs(liste) do
        if t.datum == zustand.einteilungTag then wahl = t end
    end
    return wahl.datum, wahl.label, liste
end

local function baueFenster()
    if rahmen then return end

    rahmen = CreateFrame("Frame", "FairshareFenster", UIParent)
    -- Stufe fest und niedriger als beim Einstellungsfenster (das liegt auf
    -- FULLSCREEN_DIALOG, Ebene 200): So liegt es nie darunter.
    rahmen:SetFrameStrata("DIALOG")
    rahmen:SetFrameLevel(20)
    rahmen:SetClampedToScreen(true)
    rahmen:SetMovable(true)
    rahmen:EnableMouse(true)
    S.Kasten(rahmen, 10, C.bg, C.ln)
    tinsert(UISpecialFrames, "FairshareFenster")   -- ESC schliesst

    kopfBauen()

    -- Werkzeugleiste, Zeile 1: Ansicht und Zeitraum links, Aktionen rechts
    ansichtSeg = S.Segment(rahmen, function(wert)
        zustand.ansicht = wert
        zustand.spieler = nil
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)
    ansichtSeg:SetWerte({
        { wert = "liste", label = L["Spieler"] },
        { wert = "verlauf", label = L["Verlauf"] },
        { wert = "bank", label = L["Anwesenheit"] },
        { wert = "einteilung", label = L["Einteilung"] },
    })
    ansichtSeg:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 16, -(KOPF + 12))

    zeitSeg = S.Segment(rahmen, function(wert)
        zustand.wochen = wert
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)
    zeitSeg:SetWerte({ { wert = 0, label = L["Alles"] }, { wert = 8, label = L["8 Wochen"] },
                       { wert = 4, label = L["4 Wochen"] } })
    zeitSeg:SetPoint("LEFT", ansichtSeg, "RIGHT", 10, 0)

    einstellBtn = S.Knopf(rahmen, L["Einstellungen"], "secondary", 26)
    einstellBtn:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -16, -(KOPF + 12))
    einstellBtn:SetScript("OnClick", function()
        if ns.Einstellungen then ns.Einstellungen.Umschalten() end
    end)

    abgleichBtn = S.Knopf(rahmen, L["Abgleichen"], "secondary", 26)
    abgleichBtn:SetPoint("RIGHT", einstellBtn, "LEFT", -8, 0)
    abgleichBtn:SetScript("OnClick", function()
        local ok, grund = ns.Abgleich.Starten()
        if not ok then print("|cff1B6B57Fairshare|r: |cffff5555" .. tostring(grund) .. "|r") end
    end)

    -- Eigenes Wuerfelfenster starten (Wurf.lua): nur fuer Leiter, Assistenten, Plündermeister
    wurfBtn = S.Knopf(rahmen, L["Wurf starten"], "primary", 26)
    wurfBtn:SetPoint("RIGHT", abgleichBtn, "LEFT", -8, 0)
    wurfBtn:SetScript("OnClick", function()
        if ns.Wurf then ns.Wurf.Dialog() end
    end)

    -- Zeile 2: Hinweis oder Zurueck links, Gruppe rechts
    zurueckBtn = S.Knopf(rahmen, L["‹ Zurück"], "link", 22)
    zurueckBtn:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 16, -(KOPF + 50))
    zurueckBtn:SetScript("OnClick", function()
        zustand.spieler = nil
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)
    zurueckBtn:Hide()

    unterzeile = S.Text(rahmen, 12, C.mu, "LEFT")

    -- ⭐ Gruppe wählen: Ausklappliste (Entscheid 22.10.2026). Was sie bedeutet, hängt von der Ansicht ab:
    -- Spieler/Verlauf = Filter, Abwesenheit = die Gruppe, deren Abend du führst, Einteilung = das Ziel.
    gruppeBtn = S.Dropdown(rahmen, 24)
    gruppeBtn:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -16, -(KOPF + 50))

    -- Abend abschließen (nur in Abwesenheit-Ansicht sichtbar)
    abschlussBtn = S.Knopf(rahmen, L["Abend abschließen"], "secondary", 24)
    abschlussBtn:SetPoint("RIGHT", gruppeBtn, "LEFT", -8, 0)
    abschlussBtn:Hide()

    -- ⭐ Neuen Abend beginnen: den abgeschlossenen Abend verlassen, ohne ihn zurückzunehmen (die Wertungen bleiben)
    offeneBtn = S.Knopf(rahmen, L["Neuen Abend beginnen"], "secondary", 24)
    offeneBtn:SetPoint("RIGHT", abschlussBtn, "LEFT", -8, 0)
    offeneBtn:Hide()
    offeneBtn:SetScript("OnClick", function()
        if zustand.beispiel or not (ns.Anwesenheit and ns.Anwesenheit.AbendNeuBeginnen) then return end
        local ok, grund = ns.Anwesenheit.AbendNeuBeginnen()
        if ok then
            print("|cff1B6B57Fairshare|r: " .. L["Neuer Abend begonnen. Die Wertungen des abgeschlossenen Abends bleiben bestehen."])
        else
            print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(grund) .. "|r")
        end
        Fenster.Aktualisieren()
    end)

    -- ⭐ Ansicht „Einteilung": Raidkader einlesen, Raid-ID wählen, Einteilung senden (der Rang ist in den Einstellungen)
    syncBtn = S.Knopf(rahmen, L["Raidkader synchronisieren"], "primary", 24)
    syncBtn:SetPoint("RIGHT", gruppeBtn, "LEFT", -8, 0)
    syncBtn:Hide()
    syncBtn:SetScript("OnClick", function()
        local n, grund = ns.Gruppen.RaidkaderSync()
        if n then
            print("|cff1B6B57Fairshare|r: " .. string.format(L["Raidkader eingelesen: %d Mitglieder."], n))
        else
            print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(grund) .. "|r")
        end
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    tagBtn = S.Knopf(rahmen, "", "secondary", 24)
    tagBtn:SetPoint("RIGHT", syncBtn, "LEFT", -8, 0)
    tagBtn:Hide()
    tagBtn:SetScript("OnClick", function()
        -- die nächste Raid-ID der Reihe
        local datum, _, liste = einteilungsTag()
        local nach = liste[1]
        for i, t in ipairs(liste) do
            if t.datum == datum then nach = liste[i + 1] or liste[1] break end
        end
        zustand.einteilungTag = nach.datum
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    sendenBtn = S.Knopf(rahmen, L["Einteilung senden"], "secondary", 24)
    sendenBtn:SetPoint("RIGHT", tagBtn, "LEFT", -8, 0)
    sendenBtn:Hide()
    sendenBtn:SetScript("OnClick", function()
        local datum = einteilungsTag()
        if ns.Gruppen.EinteilungSenden(datum) then
            print("|cff1B6B57Fairshare|r: " .. string.format(L["Einteilung für %s gesendet."], datum))
        else
            print("|cff1B6B57Fairshare|r: " .. ROT .. L["Es gibt noch keine Einteilung zum Senden."] .. "|r")
        end
    end)

    -- Probe-Modus Bedienleiste
    probeLeiste = CreateFrame("Frame", nil, rahmen)
    probeLeiste:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 16, -(KOPF + 80))
    probeLeiste:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -16, -(KOPF + 80))
    probeLeiste:SetHeight(28)
    probeLeiste:Hide()

    probeSpielerDropdown = S.Dropdown(probeLeiste, 24)
    probeSpielerDropdown:SetPoint("LEFT", probeLeiste, "LEFT", 0, 0)

    probeRaidBtn = S.Knopf(probeLeiste, L["In den Raid"], "secondary", 24)
    probeRaidBtn:SetFest(96)
    probeRaidBtn:SetPoint("LEFT", probeSpielerDropdown, "RIGHT", 6, 0)
    probeRaidBtn:SetScript("OnClick", function()
        local sp = zustand.probeSpieler or "Anna"
        if ns.Probe and ns.Probe.ToggleRaid then ns.Probe.ToggleRaid(sp) end
        Fenster.Aktualisieren()
    end)

    probeHauptBtn = S.Knopf(probeLeiste, L["+ Main-Item"], "secondary", 24)
    probeHauptBtn:SetFest(90)
    probeHauptBtn:SetPoint("LEFT", probeRaidBtn, "RIGHT", 6, 0)
    probeHauptBtn:SetScript("OnClick", function()
        local sp = zustand.probeSpieler or "Anna"
        if ns.Probe and ns.Probe.VergebeItem then ns.Probe.VergebeItem(sp, false) end
        Fenster.Aktualisieren()
    end)

    probeOSBtn = S.Knopf(probeLeiste, L["+ OS-Item"], "secondary", 24)
    probeOSBtn:SetFest(78)
    probeOSBtn:SetPoint("LEFT", probeHauptBtn, "RIGHT", 6, 0)
    probeOSBtn:SetScript("OnClick", function()
        local sp = zustand.probeSpieler or "Anna"
        if ns.Probe and ns.Probe.VergebeItem then ns.Probe.VergebeItem(sp, true) end
        Fenster.Aktualisieren()
    end)

    probeBankBtn = S.Knopf(probeLeiste, L["Bench"], "secondary", 24)
    probeBankBtn:SetFest(62)
    probeBankBtn:SetPoint("LEFT", probeOSBtn, "RIGHT", 6, 0)
    probeBankBtn:SetScript("OnClick", function()
        local sp = zustand.probeSpieler or "Anna"
        local istB = ns.Anwesenheit and ns.Anwesenheit.IstBank and ns.Anwesenheit.IstBank(sp)
        if ns.Probe and ns.Probe.SetzeBank then ns.Probe.SetzeBank(sp, not istB) end
        Fenster.Aktualisieren()
    end)

    probeAbmeldBtn = S.Knopf(probeLeiste, L["Abwesend"], "secondary", 24)
    probeAbmeldBtn:SetFest(72)
    probeAbmeldBtn:SetPoint("LEFT", probeBankBtn, "RIGHT", 6, 0)
    probeAbmeldBtn:SetScript("OnClick", function()
        local sp = zustand.probeSpieler or "Anna"
        local istA = ns.Anwesenheit and ns.Anwesenheit.IstAbgemeldet and ns.Anwesenheit.IstAbgemeldet(sp)
        if ns.Probe and ns.Probe.SetzeAbgemeldet then ns.Probe.SetzeAbgemeldet(sp, not istA) end
        Fenster.Aktualisieren()
    end)

    probeUnentBtn = S.Knopf(probeLeiste, L["Unent."], "secondary", 24)
    probeUnentBtn:SetFest(64)
    probeUnentBtn:SetPoint("LEFT", probeAbmeldBtn, "RIGHT", 6, 0)
    probeUnentBtn:SetScript("OnClick", function()
        local sp = zustand.probeSpieler or "Anna"
        local istU = ns.Anwesenheit and ns.Anwesenheit.IstUnentschuldigt and ns.Anwesenheit.IstUnentschuldigt(sp)
        if ns.Probe and ns.Probe.SetzeUnentschuldigt then ns.Probe.SetzeUnentschuldigt(sp, not istU) end
        Fenster.Aktualisieren()
    end)

    probeScriptBtn = S.Knopf(probeLeiste, L["Fertiger Ablauf"], "primary", 24)
    probeScriptBtn:SetFest(106)
    probeScriptBtn:SetPoint("LEFT", probeUnentBtn, "RIGHT", 12, 0)
    probeScriptBtn:SetScript("OnClick", function()
        if ns.Probe and ns.Probe.FertigerAblauf then ns.Probe.FertigerAblauf() end
        Fenster.Aktualisieren()
    end)

    probeResetBtn = S.Knopf(probeLeiste, L["Zurücksetzen"], "secondary", 24)
    probeResetBtn:SetFest(88)
    probeResetBtn:SetPoint("LEFT", probeScriptBtn, "RIGHT", 6, 0)
    probeResetBtn:SetScript("OnClick", function()
        if ns.Probe and ns.Probe.Zuruecksetzen then ns.Probe.Zuruecksetzen() end
        Fenster.Aktualisieren()
    end)

    -- Die Tafel: Kopfzeile und Zeilen auf einer Karte
    tafel = CreateFrame("Frame", nil, rahmen)
    tafel:SetPoint("TOPLEFT", rahmen, "TOPLEFT", TAFEL_X, -TAFEL_OBEN)
    tafel:SetPoint("BOTTOMRIGHT", rahmen, "BOTTOMRIGHT", -TAFEL_X, FUSS + 10)
    S.Kasten(tafel, 8, C.p1, C.ln)

    kopfZeile = CreateFrame("Frame", nil, tafel)
    kopfZeile:SetHeight(18)
    kopfZeile:SetPoint("TOPLEFT", tafel, "TOPLEFT", 12, -10)
    kopfZeile:SetPoint("TOPRIGHT", tafel, "TOPRIGHT", -12, -10)
    for _, k in ipairs(SPALTEN) do kopfZeile[k] = spalte(kopfZeile, 11, C.mu) end
    local trenner = S.Tex(tafel, "BORDER", C.ln)
    trenner:SetHeight(1)
    trenner:SetPoint("TOPLEFT", tafel, "TOPLEFT", 12, -30)
    trenner:SetPoint("TOPRIGHT", tafel, "TOPRIGHT", -12, -30)

    for i = 1, MAXZEILEN do zeilen[i] = baueZeile(i) end

    -- Fuss
    local f = CreateFrame("Frame", nil, rahmen)
    f:SetPoint("BOTTOMLEFT", rahmen, "BOTTOMLEFT", 1, 1)
    f:SetPoint("BOTTOMRIGHT", rahmen, "BOTTOMRIGHT", -1, 1)
    f:SetHeight(FUSS)
    S.Form(f, 9, C.p1, nil, "BACKGROUND", 0, 0, { bl = true, br = true })
    local fl = S.Tex(f, "BORDER", C.ln)
    fl:SetHeight(1)
    fl:SetPoint("TOPLEFT")
    fl:SetPoint("TOPRIGHT")

    probeBtn = S.Knopf(f, L["Probe"], "link", 22)
    probeBtn:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    probeBtn:SetScript("OnClick", function()
        Fenster.ProbeUmschalten()
    end)

    beispielBtn = S.Knopf(f, L["Beispiel"], "link", 22)
    beispielBtn:SetPoint("RIGHT", probeBtn, "LEFT", -16, 0)

    -- Nur die Gruppe / alle Spieler (nur sichtbar, solange man in einer Gruppe ist)
    nurBtn = S.Knopf(f, L["Alle Spieler zeigen"], "link", 22)
    nurBtn:SetPoint("RIGHT", beispielBtn, "LEFT", -16, 0)
    nurBtn:SetScript("OnClick", function()
        if zustand.ansicht == "einteilung" then
            -- ⭐ Wochenabschluss: erster Klick zeigt die Vorschau im Chat, zweiter (binnen 8 s) bucht
            local datum = einteilungsTag()
            local jetzt = time()
            if zustand.wocheBestaetigung and (jetzt - zustand.wocheBestaetigung) <= 8 then
                zustand.wocheBestaetigung = nil
                local v, grund = ns.Anwesenheit.WocheBuchen(datum)
                if v then
                    print("|cff1B6B57Fairshare|r: " .. string.format(L["Woche gebucht: %d Zuschläge."], v.gebucht or 0))
                else
                    print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(grund) .. "|r")
                end
            else
                local v, grund = ns.Anwesenheit.WocheVorschau(datum)
                if v then
                    zustand.wocheBestaetigung = jetzt
                    print("|cff1B6B57Fairshare|r: " .. string.format(L["Woche ab %s: %d Abende je Spieler, %d abgemeldet, %d Keine Meldung. Nochmal klicken zum Buchen."],
                        v.montag, v.n, #v.abgemeldet, #v.keineMeldung))
                else
                    print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(grund) .. "|r")
                end
            end
            Fenster.Aktualisieren()
            return
        end
        zustand.alleSpieler = not zustand.alleSpieler
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    fuss = S.Text(f, 11, C.mu, "LEFT")
    fuss:SetPoint("LEFT", f, "LEFT", 16, 0)
    fuss:SetPoint("RIGHT", nurBtn, "LEFT", -12, 0)
    beispielBtn:SetScript("OnClick", function()
        if zustand.probe then
            Fenster.ProbeModus(false)
        end
        zustand.beispiel = not zustand.beispiel
        zustand.beispielAbgeschlossen = false
        if ns.Anwesenheit and ns.Anwesenheit.BeispielKandidatenWiederherstellen then
            ns.Anwesenheit.BeispielKandidatenWiederherstellen()
        end
        zustand.spieler = nil
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    rahmen:SetScript("OnHide", function()
        if zustand.probe then
            Fenster.ProbeModus(false)
        end
    end)

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

    S.Verstellbar(rahmen, "uebersicht", { b = BREITE, h = HOEHE, minB = 880, minH = 420,
        maxB = 1300, maxH = 1100 }, function() Fenster.Aktualisieren() end)

    rahmen:SetScript("OnShow", function()
        Fenster.Aktualisieren()
        -- Die Schrift beim ersten Zeigen nachziehen (siehe Stil.Auffrischen).
        if C_Timer then
            C_Timer.After(0.1, function() S.Auffrischen() end)
            C_Timer.After(0.6, function() S.Auffrischen() end)
        end
        S.AuffrischenBisFertig()           -- ⭐ beim ersten Öffnen länger nachziehen (Schrift lädt spät)
    end)
end

-- =====================================================================
--  Anzeige
-- =====================================================================

--- Stellt die Spalten fuer eine Ansicht ein.
local function ordneSpalten(name)
    local w = math.max(300, rahmen:GetWidth() - 2 * TAFEL_X - 24)
    local Lay = layout(name, w)
    local function setze(eltern, fs, def)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", eltern, "LEFT", def[1], 0)
        fs:SetWidth(def[2])
        fs:SetJustifyH(def[3])
    end
    for i, k in ipairs(SPALTEN) do
        setze(kopfZeile, kopfZeile[k], Lay[i])
        for j = 1, MAXZEILEN do setze(zeilen[j], zeilen[j][k], Lay[i]) end
    end
end

local function leereZeilen(ab)
    for i = math.max(ab, 1), MAXZEILEN do
        local z = zeilen[i]
        z.spielername = nil
        z.linksName, z.rechtsName = nil, nil
        z.eintragId = nil
        z.undo:Hide()
        if z.bankBtn then z.bankBtn:Hide() end
        if z.unentBtn then z.unentBtn:Hide() end
        if z.vergessenBtn then z.vergessenBtn:Hide() end
        if z.abmeldBtn then z.abmeldBtn:Hide() end
        if z.teilBtn then z.teilBtn:Hide() end; if z.entfBtn then z.entfBtn:Hide() end
        if z.probeRaidBtn then z.probeRaidBtn:Hide() end
        z.hover:SetShown(false)
        z.markiert:SetShown(false)
        z.a:SetText(""); z.b:SetText(""); z.c:SetText(""); z.d:SetText(""); z.e:SetText("")
    end
end

local function setzeKopf(a, b, c, d, e)
    kopfZeile.a:SetText(a or "")
    kopfZeile.b:SetText(b or "")
    kopfZeile.c:SetText(c or "")
    kopfZeile.d:SetText(d or "")
    kopfZeile.e:SetText(e or "")
end

local function zuletztText(letzte)
    local tage = tageHer(letzte)
    if not tage then return GRAU .. L["noch nichts"] .. "|r" end
    if tage == 0 then return L["heute"] end
    if tage == 1 then return L["gestern"] end
    return string.format(L["vor %d Tagen"], tage)
end

--- Der Schluessel dieses Spielers in den Wuerfen, oder nil.
--  ⚠️ Die Namen aus dem Chat und aus der Liste muessen nicht gleich
--  geschrieben sein (Nachname fehlt auf einer Seite): erst genau, dann
--  ueber Kern.GleicherSpieler.
local function wurfSchluessel(W, name)
    local k = Kern.Schluessel(name)
    if k and W.Wuerfe[k] ~= nil then return k end
    for _, n in ipairs(W.namen or {}) do
        if Kern.GleicherSpieler(n, name) then return Kern.Schluessel(n) end
    end
    return nil
end

--- „87  Haupt" / „41  Zweit" — der Wurf und wofuer er galt.
--  Ohne Zahl (Spieler hat gewaehlt, aber noch nicht gewuerfelt): nur die Art.
local function wurfText(W, name)
    local k = wurfSchluessel(W, name)
    if not k then return "" end
    local wert, art = W.Wuerfe[k], W.Arten and W.Arten[k]

    local zahl = (wert and wert > 0) and (HELL .. wert .. "|r") or ""
    local label = ""
    if art == "haupt" then
        label = AKZENT .. L["Haupt"] .. "|r"
    elseif art == "zweit" then
        label = GRAU .. L["Zweit"] .. "|r"
    elseif art == "pass" then
        return GRAU .. L["passt"] .. "|r"
    end
    if zahl ~= "" and label ~= "" then return zahl .. "  " .. label end
    return zahl .. label
end

local function zeigeListe(H)
    local W = wurf()

    -- In einer Gruppe: genau die Spieler, die dabei sind (auch mit null
    -- Vergaben). Sonst: die Wuerfelnden und der Kader der gewaehlten
    -- (sonst aktiven) Gruppe stehen in jedem Fall drin.
    local nur = nurGruppe()
    local pflicht = {}
    if nur then
        for _, n in ipairs(nur) do pflicht[#pflicht + 1] = n end
    else
        if W and W.namen then for _, n in ipairs(W.namen) do pflicht[#pflicht + 1] = n end end
        if not zustand.beispiel and ns.Gruppen then
            for _, n in ipairs(ns.Gruppen.Pflicht(zustand.gruppe)) do pflicht[#pflicht + 1] = n end
        end
    end

    local daten = (zustand.beispiel and Quelle.BeispielDaten and Quelle.BeispielDaten())
                  or (ns.Anwesenheit and ns.Anwesenheit.ZuschlaegeDaten and ns.Anwesenheit.ZuschlaegeDaten())
                  or nil
    local liste, gesamt, aeltester = Kern.Bilanz(H, seit(), pflicht, nur, daten)

    local istWuerfler
    if W then
        -- false = kein Wurf, sonst die Art ("haupt"/"zweit") oder true
        istWuerfler = function(name)
            local k = wurfSchluessel(W, name)
            if not k then return false end
            if W.Arten and W.Arten[k] == "pass" then return false end      -- wer passt, würfelt nicht
            return (W.Arten and W.Arten[k]) or true
        end
        -- Proberaid, Neulinge und Gaeste (Regelwerk § 4): nur Anzeige, festgeschrieben
        -- wird beim Zuteilen (Wurf.lua).
        if not zustand.beispiel and ns.Anwesenheit and ns.Anwesenheit.Rollen then
            ns.Anwesenheit.Rollen(liste, false)
        end
        Kern.WurfReihenfolge(liste, istWuerfler, function(name)
            local k = wurfSchluessel(W, name)
            return k and W.Wuerfe[k] or 0
        end)
    end

    setzeKopf(L["Spieler"], L["Haupt"], L["Zweit"], L["Zuletzt"], W and L["Wurf"] or nil)

    zustand.maxVersatz = math.max(0, #liste - zeilenSicht)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    local gezeigt = 0
    for i = 1, zeilenSicht do
        local z = zeilen[i]
        local e = liste[i + zustand.versatz]
        if not e then break end
        gezeigt = i

        local wuerfelt = istWuerfler and istWuerfler(e.name)
        z.spielername = e.name
        -- ⚠️ Die Zeilen werden von Verlauf und Spielerdetail mitbenutzt: Ein Knopf
        -- „Rückgängig" aus dem vorigen Reiter darf hier nicht stehen bleiben
        -- (Screenshot 14.10.2026: er lag ueber der Wurfspalte).
        z.eintragId = nil
        z.undo:Hide()
        if z.bankBtn then z.bankBtn:Hide() end
        if z.unentBtn then z.unentBtn:Hide() end
        if z.vergessenBtn then z.vergessenBtn:Hide() end
        if z.abmeldBtn then z.abmeldBtn:Hide() end
        if z.teilBtn then z.teilBtn:Hide() end; if z.entfBtn then z.entfBtn:Hide() end
        if z.probeRaidBtn then z.probeRaidBtn:Hide() end
        z.hover:SetShown(false)
        z.markiert:SetShown(wuerfelt and true or false)

        z.a:SetText((wuerfelt and HELL or "") .. e.name .. (wuerfelt and "|r" or ""))
        local w = (wuerfelt and e.effektiveWertung) or e.wertung or e.haupt or 0
        local wStr = (w == math.floor(w)) and tostring(w) or string.format("%.1f", w)
        if wuerfelt and e.dynamischeAnhebung and e.dynamischeAnhebung > 0 then
            local aStr = (e.dynamischeAnhebung == math.floor(e.dynamischeAnhebung)) and tostring(e.dynamischeAnhebung) or string.format("%.1f", e.dynamischeAnhebung)
            wStr = wStr .. " (+" .. aStr .. ")"
        end
        z.b:SetText(w > 0 and (GELB .. wStr .. "|r") or (GRAU .. "0|r"))
        z.c:SetText(e.zweit > 0 and (GRAU .. e.zweit .. "|r") or "")
        z.d:SetText(zuletztText(e.letzte))

        z.e:SetText(W and wurfText(W, e.name) or "")
    end
    leereZeilen(gezeigt + 1)

    local text = string.format(L["%d Vergaben · %d Spieler · %d Raidtage"],
        gesamt, #liste, Kern.Raidtage(H, seit(), Quelle.Tag))
    if aeltester then
        text = text .. "   |   " .. string.format(L["älteste Aufzeichnung %s"], date(L["%d.%m.%Y"], aeltester))
    end
    if #liste > zeilenSicht then text = text .. "   |   " .. L["Mausrad blättert"] end
    if nur then text = text .. "   |   " .. L["nur Spieler aus deiner Gruppe"] end
    fuss:SetText(text)

    if W then
        local was = W.link or W.name
        local haupt, zweit, passt = 0, 0, 0
        for _, art in pairs(W.Arten or {}) do
            if art == "haupt" then haupt = haupt + 1 elseif art == "zweit" then zweit = zweit + 1
            elseif art == "pass" then passt = passt + 1 end
        end
        unterzeile:SetText(GELB .. L["Wurf läuft"] .. "|r  " .. (was and (was .. "  ") or "") ..
            GRAU .. "—  " .. string.format(L["%d Haupt · %d Zweit · %d passt · niedrigste Wertung, dann höchster Wurf"], haupt, zweit, passt) .. "|r")
    else
        unterzeile:SetText("")
    end
end

--- Der Knopf „Rückgängig" einer Zeile: nur wer zurücknehmen darf, sieht ihn.
--  Zweistufig: Der erste Klick fragt („Wirklich?"), der zweite nimmt zurück.
local function undoZeile(z, id)
    z.eintragId = id
    if not (zustand.darfUndo and id) then z.undo:Hide() return end
    local frage = zustand.rueckfrage
    if frage and frage.id == id and (time() - frage.zeit) <= 8 then
        z.undo:SetLabel(GELB .. L["Wirklich?"] .. "|r")
    else
        z.undo:SetLabel(L["Rückgängig"])
    end
    z.undo:Show()
end

--- Klick auf „Rückgängig".
function Fenster.RueckgaengigKlick(id)
    if not id then return end
    local frage = zustand.rueckfrage
    if frage and frage.id == id and (time() - frage.zeit) <= 8 then
        zustand.rueckfrage = nil
        local ok, e = ns.Erfassung.Zuruecknehmen(id)
        if ok then
            print("|cff1B6B57Fairshare|r: " .. string.format(L["Rückgabe vermerkt: %s von %s. Der Punkt wird abgezogen, sobald das Item neu vergeben ist."],
                Quelle.Gegenstandstext(e), Kern.Anzeigename(e.awardedTo)))
        else
            print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(e) .. "|r")
        end
    else
        zustand.rueckfrage = { id = id, zeit = time() }
    end
    Fenster.Aktualisieren()
end

local function zeigeSpieler(H)
    setzeKopf(L["Datum"], L["Art"], L["Punkte"], L["Gegenstand / Details"], nil)

    local liste, haupt, zweit, zuschlaege, anhebungen, wertung
    if ns.Anwesenheit and ns.Anwesenheit.SpielerEreignisse then
        liste, haupt, zweit, zuschlaege, anhebungen, wertung =
            ns.Anwesenheit.SpielerEreignisse(zustand.spieler, nil, H, seit(), zustand.beispiel)
    else
        local items = Kern.Spieler(H, zustand.spieler, seit())
        liste = {}
        haupt, zweit = 0, 0
        for _, it in ipairs(items) do
            if it.zweit then zweit = zweit + 1 else haupt = haupt + 1 end
            liste[#liste + 1] = {
                id = it.id, zeit = it.zeit, art = it.zweit and "zweit" or "haupt",
                punkte = it.zweit and 0 or 1.0,
                text = Quelle.Gegenstandstext(it.eintrag), eintrag = it.eintrag, isItem = true
            }
        end
        zuschlaege, anhebungen = 0, 0
        wertung = haupt
    end

    zustand.maxVersatz = math.max(0, #liste - zeilenSicht)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    local gezeigt = 0
    for i = 1, zeilenSicht do
        local z = zeilen[i]
        local e = liste[i + zustand.versatz]
        if not e then break end
        gezeigt = i

        z.spielername = nil
        z.hover:SetShown(false)
        z.markiert:SetShown(false)
        if z.bankBtn then z.bankBtn:Hide() end
        if z.unentBtn then z.unentBtn:Hide() end
        if z.vergessenBtn then z.vergessenBtn:Hide() end
        if z.abmeldBtn then z.abmeldBtn:Hide() end
        if z.teilBtn then z.teilBtn:Hide() end; if z.entfBtn then z.entfBtn:Hide() end
        if z.probeRaidBtn then z.probeRaidBtn:Hide() end

        z.a:SetText(date(L["%d.%m.%Y"], e.zeit))

        local artText
        if e.art == "haupt" then
            artText = HELL .. L["Haupt"] .. "|r"
        elseif e.art == "zweit" then
            artText = GRAU .. L["Zweit"] .. "|r"
        elseif e.art == "abgemeldet" then
            artText = GELB .. L["Abgemeldet"] .. "|r"
        elseif e.art == "unentschuldigt" then
            artText = ROT .. L["Unentschuldigt"] .. "|r"
        elseif e.art == "vergessenStrafe" then
            artText = ROT .. L["Anmeldung vergessen"] .. "|r"
        elseif e.art == "vergessen" then
            artText = GELB .. L["Anmeldung vergessen"] .. "|r"
        elseif e.art == "bank" then
            artText = GRUEN .. L["Bank"] .. "|r"
        elseif e.art == "anhebung" then
            artText = AKZENT .. L["Anhebung"] .. "|r"
        else
            artText = tostring(e.art)
        end
        z.b:SetText(artText)

        local p = e.punkte or 0
        if p > 0 then
            local valStr = (p == math.floor(p)) and tostring(p) or string.format("%.1f", p)
            z.c:SetText(GELB .. "+" .. valStr .. "|r")
        else
            z.c:SetText(GRAU .. "0,0|r")
        end

        z.d:SetText(e.text or "")
        z.e:SetText("")

        if e.isItem then
            undoZeile(z, e.id)
        else
            z.undo:Hide()
        end
    end
    leereZeilen(gezeigt + 1)

    local wStr = (wertung == math.floor(wertung)) and tostring(wertung) or string.format("%.1f", wertung)
    local zStr = (zuschlaege == math.floor(zuschlaege)) and tostring(zuschlaege) or string.format("%.1f", zuschlaege)
    local aStr = (anhebungen == math.floor(anhebungen)) and tostring(anhebungen) or string.format("%.1f", anhebungen)

    local fussText = string.format(L["Wertung: %s · %d Main-Items (+%d)"], wStr, haupt, haupt)
    if zuschlaege > 0 then
        fussText = fussText .. " · " .. string.format(L["Zuschläge (+%s)"], zStr)
    end
    if anhebungen > 0 then
        fussText = fussText .. " · " .. string.format(L["Anhebung (+%s)"], aStr)
    end
    fussText = fussText .. " · " .. string.format(L["%d Zweitbedarf (OS)"], zweit)
    fuss:SetText(fussText)

    local info
    if zustand.beispiel and ns.Anwesenheit and ns.Anwesenheit.BeispielInfo then
        info = ns.Anwesenheit.BeispielInfo(zustand.spieler)
    elseif ns.Anwesenheit and ns.Anwesenheit.SpielerInfo then
        info = ns.Anwesenheit.SpielerInfo(zustand.spieler)
    end

    local statusText = ""
    local anwText = ""
    if info then
        if info.status == "kader" then
            statusText = GRUEN .. L["Kader"] .. "|r"
        elseif info.status == "proberaid" then
            statusText = GELB .. L["Proberaid"] .. "|r"
        elseif info.status == "neuling" then
            statusText = GELB .. L["Neuling (2. Abend)"] .. "|r"
        elseif info.status == "gast" then
            statusText = GRAU .. L["Gast"] .. "|r"
        end

        if info.bank then
            anwText = GRUEN .. L["Bank (Faktor 0)"] .. "|r"
        elseif info.unentschuldigt then
            anwText = ROT .. L["Unentschuldigt (Faktor 1,5, mindestens 2)"] .. "|r"
        elseif info.gesamt > 0 then
            local quoteText = info.imRaid and (GRUEN .. L["Im Raid (≥ 50 %)"] .. "|r") or (ROT .. L["Unter Quote (< 50 %)"] .. "|r")
            anwText = string.format(L["Anwesenheit heute: %d/%d Bosse (%d %%) · %s"], info.bosse, info.gesamt, info.prozent, quoteText)
        else
            anwText = L["Heute noch keine Bosskämpfe erfasst"]
        end
    end

    local zusatz = ""
    if statusText ~= "" then zusatz = "  " .. statusText end
    if anwText ~= "" then zusatz = zusatz .. "  " .. GRAU .. "—  " .. anwText .. "|r" end
    unterzeile:SetText(HELL .. Kern.Anzeigename(zustand.spieler) .. "|r" .. zusatz)
end

local function zeigeVerlauf(H)
    setzeKopf(L["Wann"], L["Spieler"], L["Art"], L["Gegenstand"], nil)

    local liste = Kern.Verlauf(H, seit(), nil)
    zustand.maxVersatz = math.max(0, #liste - zeilenSicht)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    local gezeigt = 0
    for i = 1, zeilenSicht do
        local z = zeilen[i]
        local e = liste[i + zustand.versatz]
        if not e then break end
        gezeigt = i

        z.spielername = e.name
        z.hover:SetShown(false)
        z.markiert:SetShown(false)
        if z.bankBtn then z.bankBtn:Hide() end
        if z.unentBtn then z.unentBtn:Hide() end
        if z.vergessenBtn then z.vergessenBtn:Hide() end
        if z.abmeldBtn then z.abmeldBtn:Hide() end
        if z.teilBtn then z.teilBtn:Hide() end; if z.entfBtn then z.entfBtn:Hide() end
        if z.probeRaidBtn then z.probeRaidBtn:Hide() end
        z.a:SetText(GRAU .. date(L["%d.%m. %H:%M"], e.zeit) .. "|r")
        z.b:SetText(e.name)
        z.c:SetText(e.zweit and (GRAU .. L["Zweit"] .. "|r") or L["Haupt"])
        z.d:SetText(Quelle.Gegenstandstext(e.eintrag))
        z.e:SetText("")
        undoZeile(z, e.id)
    end
    leereZeilen(gezeigt + 1)

    local text = string.format(L["%d Vergaben, neueste zuerst"], #liste)
    if #liste > zeilenSicht then text = text .. "   |   " .. L["Mausrad blättert"] end
    fuss:SetText(text)
    unterzeile:SetText("")
end

local function zeigeBank(H)
    setzeKopf(L["Spieler"], L["Status"], L["Bank"], L["Abwesend"], L["Unentschuldigt"])

    local istGeschlossen = false
    if zustand.beispiel then
        istGeschlossen = zustand.beispielAbgeschlossen and true or false
    else
        istGeschlossen = ns.Anwesenheit and ns.Anwesenheit.AbendIstAbgeschlossen and ns.Anwesenheit.AbendIstAbgeschlossen()
    end

    local abend = not istGeschlossen and ns.Anwesenheit and ns.Anwesenheit.AktiverAbend and ns.Anwesenheit.AktiverAbend(false) or nil
    local liste
    if zustand.beispiel and ns.Anwesenheit and ns.Anwesenheit.BeispielKandidaten then
        liste = ns.Anwesenheit.BeispielKandidaten()
    elseif ns.Anwesenheit and ns.Anwesenheit.KandidatenListe then
        liste = ns.Anwesenheit.KandidatenListe(abend, true)
    else
        liste = {}
    end

    -- ⭐ Ist der Abend abgeschlossen, zeigt die Liste nichts mehr (nur der Hinweis); „Neuen Abend beginnen“ macht sie frei
    if istGeschlossen and not zustand.beispiel then liste = {} end
    zustand.maxVersatz = math.max(0, #liste - zeilenSicht)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    local darfBank = not istGeschlossen and (zustand.beispiel or (ns.Anwesenheit and ns.Anwesenheit.DarfBankVerwalten and ns.Anwesenheit.DarfBankVerwalten()))
    local darfUnent = not istGeschlossen and (zustand.beispiel or (ns.Anwesenheit and ns.Anwesenheit.DarfUnentschuldigtVerwalten and ns.Anwesenheit.DarfUnentschuldigtVerwalten()))

    local gezeigt = 0
    for i = 1, zeilenSicht do
        local z = zeilen[i]
        local e = liste[i + zustand.versatz]
        if not e then break end
        gezeigt = i

        z.spielername = e.name
        z.hover:SetShown(false)
        z.markiert:SetShown(false)
        z.undo:Hide()
        if z.teilBtn then z.teilBtn:Hide() end; if z.entfBtn then z.entfBtn:Hide() end        -- ⭐ die Zeilen werden von allen Ansichten mitbenutzt

        z.a:SetText(HELL .. Kern.Anzeigename(e.name) .. "|r")
        if z.probeRaidBtn then z.probeRaidBtn:Hide() end

        if e.unentschuldigt then
            z.b:SetText(ROT .. L["Unentschuldigt"] .. "|r")
        elseif e.abgemeldet then
            z.b:SetText(GELB .. L["Abwesend"] .. "|r")
        elseif e.vergessen then
            z.b:SetText(ROT .. L["Keine Meldung"] .. "|r")
        elseif e.bank or e.benchEinteilung then
            z.b:SetText(AKZENT .. L["Bench"] .. "|r")
        else
            z.b:SetText(GRUEN .. L["Anwesend"] .. "|r")
        end

        z.c:SetText("")
        z.bankBtn:ClearAllPoints()
        z.bankBtn:SetPoint("CENTER", z.c, "CENTER", 0, 0)
        z.bankBtn:SetFest(76)
        z.bankBtn:Show()
        local istB = (e.bank ~= nil) or e.benchEinteilung
        z.bankBtn:SetArt(istB and "primary" or "secondary")
        z.bankBtn:SetLabel(istB and (e.benchEinteilung and L["✓ Bench"] or L["✓ Bank"]) or L["Bank"])
        z.bankBtn:SetAktiv(zustand.probe or darfBank)
        z.bankBtn:SetScript("OnClick", function()
            if zustand.probe then
                if ns.Probe and ns.Probe.SetzeBank then
                    ns.Probe.SetzeBank(e.name, not istB)
                end
                Fenster.Aktualisieren()
                return
            end
            if e.benchEinteilung and not zustand.beispiel then
                -- ⭐ Bench laut Einteilung: Klick holt ihn in die aktive Gruppe (er springt ein)
                local ok, grund = ns.Anwesenheit.BenchEinspringen(e.name)
                if not ok then print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(grund) .. "|r") end
                Fenster.Aktualisieren()
                return
            end
            if zustand.beispiel then
                if ns.Anwesenheit and ns.Anwesenheit.BeispielBankToggle then
                    ns.Anwesenheit.BeispielBankToggle(e.name)
                end
            elseif ns.Anwesenheit and ns.Anwesenheit.BankSetzen then
                ns.Anwesenheit.BankSetzen(e.name, not (e.bank ~= nil))
            end
            Fenster.Aktualisieren()
        end)

        z.d:SetText("")
        z.abmeldBtn:ClearAllPoints()
        z.abmeldBtn:SetPoint("CENTER", z.d, "CENTER", 0, 0)
        z.abmeldBtn:SetFest(80)
        z.abmeldBtn:Show()
        local istA = (e.abgemeldet ~= nil)
        z.abmeldBtn:SetArt(istA and "primary" or "secondary")
        z.abmeldBtn:SetLabel(istA and L["✓ Abwesend"] or L["Abwesend"])
        z.abmeldBtn:SetAktiv(zustand.probe or darfBank)
        z.abmeldBtn:SetScript("OnClick", function()
            if zustand.probe then
                if ns.Probe and ns.Probe.SetzeAbgemeldet then
                    ns.Probe.SetzeAbgemeldet(e.name, not istA)
                end
                Fenster.Aktualisieren()
                return
            end
            if zustand.beispiel then
                if ns.Anwesenheit and ns.Anwesenheit.BeispielAbmeldToggle then
                    ns.Anwesenheit.BeispielAbmeldToggle(e.name)
                end
            elseif ns.Anwesenheit and ns.Anwesenheit.AbmeldungSetzen then
                ns.Anwesenheit.AbmeldungSetzen(e.name, not istA)
            end
            Fenster.Aktualisieren()
        end)

        z.e:SetText("")
        z.unentBtn:ClearAllPoints()
        z.unentBtn:SetPoint("CENTER", z.e, "CENTER", 0, 0)
        z.unentBtn:SetFest(80)
        z.unentBtn:Show()
        local istU = (e.unentschuldigt ~= nil)
        z.unentBtn:SetArt(istU and "primary" or "secondary")
        z.unentBtn:SetLabel(istU and L["✓ Unent."] or L["Unent."])
        z.unentBtn:SetAktiv(zustand.probe or darfUnent)
        z.unentBtn:SetScript("OnClick", function()
            if zustand.probe then
                if ns.Probe and ns.Probe.SetzeUnentschuldigt then
                    ns.Probe.SetzeUnentschuldigt(e.name, not istU)
                end
                Fenster.Aktualisieren()
                return
            end
            if zustand.beispiel then
                if ns.Anwesenheit and ns.Anwesenheit.BeispielUnentToggle then
                    ns.Anwesenheit.BeispielUnentToggle(e.name)
                end
            elseif ns.Anwesenheit and ns.Anwesenheit.UnentschuldigtSetzen then
                ns.Anwesenheit.UnentschuldigtSetzen(e.name, not istU)
            end
            Fenster.Aktualisieren()
        end)

        z.vergessenBtn:Hide()
    end
    leereZeilen(gezeigt + 1)

    local anzahlAnwesend, anzahlBank, anzahlAbgem, anzahlUnent = 0, 0, 0, 0
    for _, e in ipairs(liste) do
        if e.unentschuldigt then
            anzahlUnent = anzahlUnent + 1
        elseif e.abgemeldet then
            anzahlAbgem = anzahlAbgem + 1
        elseif e.bank or e.benchEinteilung then
            anzahlBank = anzahlBank + 1
        else
            anzahlAnwesend = anzahlAnwesend + 1
        end
    end

    if istGeschlossen then
        fuss:SetText(L["Raidabend abgeschlossen · Bereit für nächsten Raid"])
        unterzeile:SetText(GRUEN .. L["Raidabend abgeschlossen. Die Wertungen sind gebucht; „Neuen Abend beginnen“ macht die Liste frei."] .. "|r")
    else
        fuss:SetText(string.format(L["%d anwesend, %d Bench, %d abwesend, %d unentschuldigt"],
            anzahlAnwesend, anzahlBank, anzahlAbgem, anzahlUnent))
        unterzeile:SetText(GRAU .. L["Wer eingeteilt ist und nicht als abwesend markiert wurde, gilt als anwesend · Bench: Faktor 0 · Unentschuldigt: Faktor 1,5, mindestens 2."] .. "|r")
        -- ⭐ Woher kommt die Liste? Hinweise, wenn die Einteilung von heute fehlt oder leer ist
        if not zustand.beispiel then
            local G = ns.Gruppen
            local heute = G.EinteilungTag(0)
            local aktiv = G.AktivName()
            if G.EinteilungVorhanden(heute) and not aktiv then
                unterzeile:SetText(GELB .. L["Für heute gibt es eine Einteilung: oben rechts die Gruppe wählen, deren Anwesenheit du führst."] .. "|r")
            elseif aktiv and not G.EinteilungVorhanden(heute) then
                unterzeile:SetText(GELB .. L["Für heute gibt es keine Einteilung: es gilt der ganze Kader der Gruppe. Unter „Einteilung“ den Tag „Heute“ einteilen."] .. "|r")
            elseif aktiv and #G.EinteilungListe(heute, aktiv) == 0 then
                unterzeile:SetText(GELB .. L["In dieser Gruppe ist heute niemand eingeteilt."] .. "|r")
            end
        end
    end
end

-- ⭐ Jede Gruppe hat in der Einteilung ihre eigene Farbe (nach ihrer Stelle in der Liste der Gruppen).
local GRUPPENFARBEN = { "|cff6cb4ff", "|cffffa94d", "|cffc792ff", "|cff6fdc6f", "|cffff7fb0", "|cfff0e060" }

local function gruppenFarbe(G, gruppe)
    for i, n in ipairs(G.Namen()) do
        if n == gruppe then return GRUPPENFARBEN[((i - 1) % #GRUPPENFARBEN) + 1] end
    end
    return GELB
end

--- Das Ziel der Einteilung: die gewählte Gruppe, die Bench oder „Keine Meldung“; sonst die erste Gruppe.
local function einteilungsZiel()
    local G = ns.Gruppen
    local z = zustand.einteilungZiel
    if z == G.KEINEMELDUNG or G.IstBench(z) or (z and G.Holen(z)) then return z end
    return G.Namen()[1] or G.BenchName(40)
end

local function zielBeschriftung(ziel)
    local G = ns.Gruppen
    if G.IstBench(ziel) then
        local gr = G.Groesse(ziel)
        return string.format(L["[%der] %s"], gr, L["Bench"])
    end
    if ziel == G.KEINEMELDUNG then return L["Keine Meldung"] end
    if ziel and G.Holen(ziel) then
        return string.format(L["[%der] %s"], G.Groesse(ziel), ziel)
    end
    return ziel or ""
end

--- ⭐ Ansicht „Einteilung“ (Entscheid 22.10.2026): Ziel oben in der Ausklappliste wählen, links stehen die Spieler,
--  die dorthin können (frei, Bench, „Keine Meldung“), rechts die, die schon drin sind. Einmal je Raid-ID, und ein
--  Spieler steht immer nur in EINER Gruppe: Wer schon irgendwo zugewiesen ist (Gruppe, Bench, Keine Meldung), ist für kein anderes Ziel verfügbar; erst dort entfernen.
local function zeigeEinteilung()
    local G = ns.Gruppen
    local datum, idLabel = einteilungsTag()
    zustand.einteilungDatum = datum
    local darf = not zustand.beispiel and G.EinteilungDarf()
    local ziel = einteilungsZiel()
    local zielIstGruppe = ziel ~= nil and ziel ~= G.BENCH and ziel ~= G.KEINEMELDUNG
    local w = math.max(300, rahmen:GetWidth() - 2 * TAFEL_X - 24)
    local hw = math.floor((w - 16) / 2)

    if not ziel then
        setzeKopf(L["Verfügbar"], "", "", "", "")
    elseif zielIstGruppe then
        setzeKopf(L["Verfügbar"], "", string.format(L["In der Gruppe %s"], ziel), "", "")
    else
        setzeKopf(L["Verfügbar"], "", zielBeschriftung(ziel), "", "")
    end

    -- Pool: der Raidkader, dazu alle, die in dieser Raid-ID eingeteilt sind, aber nicht im Raidkader stehen
    local pool, gesehen = {}, {}
    local kader = G.Raidkader()
    for _, m in ipairs(kader) do
        local k = Kern.Schluessel(m.name)
        if k and not gesehen[k] then
            gesehen[k] = true
            pool[#pool + 1] = { name = m.name, rang = m.rang }
        end
    end
    local alleZiele = {}
    for _, gn in ipairs(G.Namen()) do alleZiele[#alleZiele + 1] = gn end
    alleZiele[#alleZiele + 1] = G.BENCH
    alleZiele[#alleZiele + 1] = G.BenchName(10)
    alleZiele[#alleZiele + 1] = G.BenchName(20)
    alleZiele[#alleZiele + 1] = G.BenchName(40)
    alleZiele[#alleZiele + 1] = G.KEINEMELDUNG
    for _, gn in ipairs(alleZiele) do
        for _, n in ipairs(G.EinteilungListe(datum, gn)) do
            local k = Kern.Schluessel(n)
            if k and not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = { name = n, rang = "—" }
            end
        end
    end
    local zielKat = ziel and (ziel ~= G.KEINEMELDUNG and G.Groesse(ziel) or nil)
    for _, e in ipairs(pool) do
        if ziel == G.KEINEMELDUNG then
            local g = G.EinteilungVon(datum, e.name)
            e.gruppe = (g == G.KEINEMELDUNG) and G.KEINEMELDUNG or g
        else
            e.gruppe = G.EinteilungVon(datum, e.name, zielKat)
            if e.gruppe and not G.IstBench(e.gruppe) and e.gruppe ~= G.KEINEMELDUNG and not G.Holen(e.gruppe) then
                e.gruppe = nil
            end
        end
    end

    local rang = {}
    for i, gn in ipairs(alleZiele) do rang[gn] = i end
    -- links: Bench zuerst (sie springen ein), dann wer nirgends steht, dann „Keine Meldung“, zuletzt andere Gruppen
    local function ordnung(e)
        if G.IstBench(e.gruppe) then return 1 end
        if e.gruppe == nil then return 2 end
        if e.gruppe == G.KEINEMELDUNG then return 3 end
        return 3 + (rang[e.gruppe] or 0)
    end
    local drin, verfuegbar, andere = {}, {}, 0
    for _, e in ipairs(pool) do
        if ziel ~= nil and (e.gruppe == ziel or (G.IstBench(ziel) and G.IstBench(e.gruppe) and G.Groesse(e.gruppe) == zielKat)) then
            drin[#drin + 1] = e
        else
            if e.gruppe ~= nil then
                andere = andere + 1                -- schon in einer anderen Gruppe dieser Größe: hier nicht verfügbar
            else
                verfuegbar[#verfuegbar + 1] = e
            end
        end
    end
    table.sort(drin, function(a, b) return a.name:lower() < b.name:lower() end)
    table.sort(verfuegbar, function(a, b)
        local oa, ob = ordnung(a), ordnung(b)
        if oa ~= ob then return oa < ob end
        return a.name:lower() < b.name:lower()
    end)
    zustand.einteilungListe, zustand.einteilungDrin = verfuegbar, drin
    zustand.maxVersatz = math.max(0, math.max(#verfuegbar, #drin) - zeilenSicht)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    local gezeigt = 0
    for i = 1, zeilenSicht do
        local z = zeilen[i]
        local l, r = verfuegbar[i + zustand.versatz], drin[i + zustand.versatz]
        if not l and not r then break end
        gezeigt = i

        z.spielername = nil
        z.linksName, z.rechtsName = l and l.name or nil, r and r.name or nil
        z.hover:SetShown(false)
        z.markiert:SetShown(false)
        z.undo:Hide()
        -- ⭐ die Zeilen werden von allen Ansichten mitbenutzt: Knöpfe der Abwesenheit dürfen nicht stehen bleiben
        if z.bankBtn then z.bankBtn:Hide() end
        if z.unentBtn then z.unentBtn:Hide() end
        if z.vergessenBtn then z.vergessenBtn:Hide() end
        if z.abmeldBtn then z.abmeldBtn:Hide() end
        if z.probeRaidBtn then z.probeRaidBtn:Hide() end
        z.d:SetText("")
        z.e:SetText("")

        if l then
            if l.gruppe == nil then
                z.a:SetText(HELL .. Kern.Anzeigename(l.name) .. "|r")
                z.b:SetText(GRAU .. tostring(l.rang or "") .. "|r")
            elseif l.gruppe == G.BENCH then
                z.a:SetText(AKZENT .. Kern.Anzeigename(l.name) .. "|r")
                z.b:SetText(AKZENT .. L["Bench"] .. "|r")           -- die Bench fällt auf: sie springt ein
            elseif l.gruppe == G.KEINEMELDUNG then
                z.a:SetText(ROT .. Kern.Anzeigename(l.name) .. "|r")
                z.b:SetText(ROT .. L["Keine Meldung"] .. "|r")
            else
                local farbe = gruppenFarbe(G, l.gruppe)
                z.a:SetText(farbe .. Kern.Anzeigename(l.name) .. "|r")
                z.b:SetText(farbe .. l.gruppe .. "|r")
            end
            local verschieben = l.gruppe ~= nil and not G.IstBench(l.gruppe) and l.gruppe ~= G.KEINEMELDUNG
            z.teilBtn:ClearAllPoints()
            z.teilBtn:SetPoint("RIGHT", z, "LEFT", hw, 0)
            z.teilBtn:Show()
            z.teilBtn:SetArt("secondary")
            z.teilBtn:SetLabel(verschieben and L["Verschieben"] or L["Hinzufügen"])
            z.teilBtn:SetAktiv(darf and ziel ~= nil)
            z.teilBtn:SetScript("OnClick", function()
                local ok, grund = G.EinteilungSetzen(datum, l.name, ziel, nil, zielKat)
                if not ok then print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(grund) .. "|r") end
                Fenster.Aktualisieren()
            end)
        else
            z.a:SetText("")
            z.b:SetText("")
            z.teilBtn:Hide()
        end

        if r then
            local farbe = zielIstGruppe and gruppenFarbe(G, ziel) or (ziel == G.BENCH and AKZENT or ROT)
            z.c:SetText(farbe .. Kern.Anzeigename(r.name) .. "|r")
            z.d:SetText(GRAU .. tostring(r.rang or "") .. "|r")
            z.entfBtn:ClearAllPoints()
            z.entfBtn:SetPoint("RIGHT", z, "RIGHT", 0, 0)
            z.entfBtn:Show()
            z.entfBtn:SetAktiv(darf)
            z.entfBtn:SetScript("OnClick", function()
                local ok, grund = G.EinteilungSetzen(datum, r.name, "", nil, zielKat)
                if not ok then print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(grund) .. "|r") end
                Fenster.Aktualisieren()
            end)
        else
            z.c:SetText("")
            z.entfBtn:Hide()
        end
    end
    leereZeilen(gezeigt + 1)

    tagBtn:SetLabel(idLabel)
    syncBtn:SetAktiv(G.RaidkaderRang() ~= nil and not zustand.beispiel)
    fuss:SetText(string.format(L["%d im Raidkader · %d in der gewählten Gruppe · %d in anderen Gruppen"],
        #kader, #drin, andere))

    local hinweis
    if #G.Namen() == 0 then
        hinweis = L["Lege zuerst unter Einstellungen → Gruppen eine Gruppe an."]
    elseif #kader == 0 and #pool == 0 then
        hinweis = L["Der Raidkader ist leer: Rang in den Einstellungen wählen, dann „Raidkader synchronisieren“."]
    elseif not darf then
        hinweis = L["Einteilen dürfen nur Gildenränge mit Schreibrecht (Einstellungen → Würfeln & Abgleich → Einstellungen teilen)."]
    else
        hinweis = L["Links Hinzufügen, rechts Entfernen. Jeder Spieler steht nur in einer Gruppe."]
        if andere > 0 then
            hinweis = hinweis .. " " .. string.format(L["%d bereits zugewiesene Spieler sind ausgeblendet."], andere)
        end
    end
    unterzeile:SetText(GRAU .. hinweis .. "|r")
end

--- Die Einträge der Ausklappliste für die aktuelle Ansicht und die gewählte.
local function gruppenOptionen()
    local G = ns.Gruppen
    local opt = {}
    if zustand.beispiel then return opt, nil end
    local Namen = G.Namen()
    local sortierteNamen = {}
    for _, n in ipairs(Namen) do sortierteNamen[#sortierteNamen + 1] = n end
    table.sort(sortierteNamen, function(a, b)
        local ga, gb = G.Groesse(a), G.Groesse(b)
        if ga ~= gb then return ga < gb end
        return a:lower() < b:lower()
    end)

    if (zustand.ansicht == "einteilung" or zustand.ansicht == "bank") and not zustand.spieler then
        for _, n in ipairs(sortierteNamen) do
            opt[#opt + 1] = { wert = n, label = string.format(L["[%der] %s"], G.Groesse(n), n), farbe = gruppenFarbe(G, n) }
        end
        if zustand.ansicht == "einteilung" then
            opt[#opt + 1] = { wert = G.BenchName(10), label = L["[10er] Bench"], farbe = AKZENT }
            opt[#opt + 1] = { wert = G.BenchName(20), label = L["[20er] Bench"], farbe = AKZENT }
            opt[#opt + 1] = { wert = G.BenchName(40), label = L["[40er] Bench"], farbe = AKZENT }
            opt[#opt + 1] = { wert = G.KEINEMELDUNG, label = L["Keine Meldung"], farbe = ROT }
            return opt, einteilungsZiel()
        end
        return opt, G.AktivName()
    end
    opt[1] = { wert = "", label = L["Alle"] }
    for _, n in ipairs(sortierteNamen) do
        opt[#opt + 1] = { wert = n, label = string.format(L["[%der] %s"], G.Groesse(n), n), farbe = gruppenFarbe(G, n) }
    end
    return opt, zustand.gruppe or ""
end

--- Eine Gruppe in der Ausklappliste wählen (auch als Prüfstand-Zugang). Was sie bedeutet, hängt von der Ansicht ab:
--  Einteilung = Ziel, Abwesenheit = aktive Gruppe (ein Wechsel ist ein anderer Abend), sonst Filter („“ = alle).
function Fenster.GruppeWaehlen(wert)
    local G = ns.Gruppen
    if zustand.ansicht == "einteilung" and not zustand.spieler then
        zustand.einteilungZiel = wert
    elseif zustand.ansicht == "bank" and not zustand.spieler and not zustand.beispiel then
        G.Aktivieren(wert)
    else
        zustand.gruppe = (wert ~= nil and wert ~= "") and wert or nil
    end
    zustand.versatz = 0
    Fenster.Aktualisieren()
end

function Fenster.Aktualisieren()
    if not rahmen then return end

    -- Kopf: Version, bei Beispieldaten eine Warnfarbe
    if zustand.probe then
        kopfTag.text:SetText(L["PROBE – keine echten Daten"])
        S.TextFarbe(kopfTag.text, C.warn)
    elseif zustand.beispiel then
        kopfTag.text:SetText(L["Beispieldaten"])
        S.TextFarbe(kopfTag.text, C.warn)
    else
        kopfTag.text:SetText(version() .. " · Forever")
        S.TextFarbe(kopfTag.text, C.mu)
    end
    kopfTag:SetWidth(math.ceil(kopfTag.text:GetStringWidth()) + 12)

    -- ⭐ Abwesenheit und Einteilung sehen nur Spieler mit Schreibrecht (Gildenrang, Entscheid 22.10.2026);
    -- alle anderen haben nur Spieler und Verlauf. Beispieldaten zeigt jeder.
    -- Ist der eigene Rang noch unbekannt (Gildenliste lädt), bleiben sie offen — wie bei den gesperrten Einstellungen;
    -- die Knöpfe selbst prüfen das Recht streng (`Gruppen.EinteilungDarf`).
    local reiter = zustand.beispiel or zustand.probe
        or (ns.Gruppen.EinteilungDarf() or (IsInGuild and IsInGuild() and not ns.Konfig.Gesperrt())) and true or false
    if not reiter and (zustand.ansicht == "bank" or zustand.ansicht == "einteilung") then
        zustand.ansicht = "liste"
        zustand.spieler = nil
    end
    if zustand.reiterSichtbar ~= reiter then
        zustand.reiterSichtbar = reiter
        local werte = { { wert = "liste", label = L["Spieler"] }, { wert = "verlauf", label = L["Verlauf"] } }
        if reiter then
            werte[#werte + 1] = { wert = "bank", label = L["Anwesenheit"] }
            werte[#werte + 1] = { wert = "einteilung", label = L["Einteilung"] }
        end
        ansichtSeg:SetWerte(werte)
    end

    -- Werkzeugleiste
    ansichtSeg:SetWahl(zustand.spieler and "liste" or zustand.ansicht)
    zeitSeg:SetWahl(zustand.wochen)
    beispielBtn:SetLabel(zustand.beispiel and L["Beispiel aus"] or L["Beispiel"])
    probeBtn:SetLabel(zustand.probe and L["Probe beenden"] or L["Probe"])

    local Namen = ns.Gruppen and ns.Gruppen.Namen() or {}
    if zustand.gruppe == ns.Gruppen.BENCH or zustand.gruppe == ns.Gruppen.KEINEMELDUNG then
        zustand.gruppe = nil
    elseif zustand.gruppe and not (ns.Gruppen and ns.Gruppen.Holen(zustand.gruppe)) then
        zustand.gruppe = nil     -- die Gruppe wurde inzwischen geloescht
    end
    -- ⭐ Ausklappliste: je nach Ansicht Filter (Spieler/Verlauf), aktive Gruppe (Abwesenheit) oder Ziel (Einteilung)
    local optionen, wahl = gruppenOptionen()
    local gruppenName
    if zustand.ansicht == "einteilung" and not zustand.spieler and not zustand.beispiel then
        gruppenName = zielBeschriftung(wahl) or L["keine"]
    elseif zustand.ansicht == "bank" and not zustand.spieler and not zustand.beispiel then
        gruppenName = ns.Gruppen.AktivName() or L["keine"]
    else
        gruppenName = zustand.gruppe or (#Namen > 0 and L["Alle"] or L["keine"])
    end
    gruppeBtn:SetLabel(string.format(L["Gruppe: %s"], gruppenName))
    gruppeBtn:SetOptionen(optionen, wahl, Fenster.GruppeWaehlen)
    gruppeBtn:SetAktiv(#Namen > 0 and not zustand.beispiel and not zustand.probe)

    -- Abgleich: auffaellig, wenn Mitspieler abweichen
    local abw = ns.Abgleich and ns.Abgleich.Abweichend or {}
    if #abw > 0 then
        abgleichBtn:SetArt("primary")
        abgleichBtn:SetLabel(string.format(L["Abgleichen (%d)"], #abw))
    else
        abgleichBtn:SetArt("secondary")
        abgleichBtn:SetLabel(L["Abgleichen"])
    end
    abgleichBtn:SetAktiv(not zustand.beispiel and not zustand.probe)

    zustand.darfUndo = not zustand.beispiel and not zustand.probe and ns.Erfassung.DarfZuruecknehmen()
    local imGruppe = IsInGroup and IsInGroup() and true or false
    wurfBtn:SetShown(not zustand.beispiel and not zustand.probe and ns.Wurf ~= nil and ns.Wurf.DarfStarten())
    -- ⭐ Platz in Zeile 1: Passt die Zeitraum-Auswahl neben die Knöpfe rechts? Sonst entfällt sie (bei schmalem
    -- Fenster wuchsen Auswahl und Knöpfe ineinander, Nutzerfund 17.10.2026).
    do
        local breite = rahmen:GetWidth() or BREITE
        local links = 16 + (ansichtSeg:GetWidth() or 0)
        local rechts = 16 + (einstellBtn:GetWidth() or 0) + 8 + (abgleichBtn:GetWidth() or 0)
                       + (wurfBtn:IsShown() and (8 + (wurfBtn:GetWidth() or 0)) or 0)
        local zeigen = zustand.ansicht ~= "bank" and zustand.ansicht ~= "einteilung"
        if links + 10 + (zeitSeg:GetWidth() or 0) + rechts + 16 > breite then zeigen = false end
        zeitSeg:SetShown(zeigen)
    end
    nurBtn:SetShown((imGruppe and not zustand.beispiel and not zustand.probe and zustand.ansicht == "liste" and zustand.spieler == nil)
                    or (not zustand.beispiel and not zustand.probe and zustand.ansicht == "einteilung" and zustand.spieler == nil))
    if zustand.ansicht == "einteilung" then
        local bestaetigen = zustand.wocheBestaetigung and (time() - zustand.wocheBestaetigung) <= 8
        nurBtn:SetLabel(bestaetigen and (GELB .. L["Wirklich buchen?"] .. "|r") or L["Woche abschließen"])
        nurBtn:SetAktiv(ns.Gruppen.EinteilungDarf())
    else
        nurBtn:SetLabel(zustand.alleSpieler and L["Nur Gruppe zeigen"] or L["Alle Spieler zeigen"])
    end

    zurueckBtn:SetShown(zustand.spieler ~= nil)
    unterzeile:ClearAllPoints()
    if zustand.spieler then
        unterzeile:SetPoint("LEFT", zurueckBtn, "RIGHT", 10, 0)
    else
        unterzeile:SetPoint("LEFT", rahmen, "TOPLEFT", 16, -(KOPF + 61))
    end

    for _, b in ipairs({ syncBtn, tagBtn, sendenBtn }) do b:Hide() end
    if zustand.ansicht == "einteilung" and not zustand.spieler then
        zustand.abschlussBestaetigung = nil
        abschlussBtn:Hide()
        offeneBtn:Hide()
        for _, b in ipairs({ syncBtn, tagBtn, sendenBtn }) do b:Show() end
        unterzeile:SetPoint("RIGHT", sendenBtn, "LEFT", -10, 0)
    elseif zustand.ansicht == "bank" and not zustand.spieler then
        abschlussBtn:Show()
        local istGeschlossen = false
        if zustand.beispiel then
            istGeschlossen = zustand.beispielAbgeschlossen and true or false
        else
            istGeschlossen = ns.Anwesenheit and ns.Anwesenheit.AbendIstAbgeschlossen and ns.Anwesenheit.AbendIstAbgeschlossen()
        end
        local darfSchliessen = zustand.beispiel or zustand.probe or (ns.Anwesenheit and ns.Anwesenheit.DarfBankVerwalten and ns.Anwesenheit.DarfBankVerwalten())
        abschlussBtn:SetAktiv(darfSchliessen)

        if zustand.abschlussBestaetigung and (time() - zustand.abschlussBestaetigung <= 8) then
            abschlussBtn:SetLabel(GELB .. (istGeschlossen and L["Wirklich wiedereröffnen?"] or L["Wirklich abschließen?"]) .. "|r")
        elseif istGeschlossen then
            abschlussBtn:SetLabel(L["Abend wiedereröffnen"])
        else
            abschlussBtn:SetLabel(L["Abend abschließen"])
        end

        abschlussBtn:SetScript("OnClick", function()
            if not darfSchliessen then return end
            local t = time()
            if zustand.abschlussBestaetigung and (t - zustand.abschlussBestaetigung <= 8) then
                zustand.abschlussBestaetigung = nil
                if istGeschlossen then
                    if zustand.beispiel then
                        zustand.beispielAbgeschlossen = false
                        if ns.Anwesenheit and ns.Anwesenheit.BeispielKandidatenWiederherstellen then
                            ns.Anwesenheit.BeispielKandidatenWiederherstellen()
                        end
                        print("|cff1B6B57Fairshare|r: " .. string.format(L["Raidabend %s wiedereröffnet, Zuschläge zurückgenommen."], date("%d.%m.%Y", t)))
                    else
                        local ok, ab = ns.Anwesenheit.AbendWiedereroeffnen()
                        if ok then
                            print("|cff1B6B57Fairshare|r: " .. string.format(L["Raidabend %s wiedereröffnet, Zuschläge zurückgenommen."], tostring(ab.datum or ab.id)))
                        else
                            print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(ab) .. "|r")
                        end
                    end
                else
                    if zustand.beispiel then
                        zustand.beispielAbgeschlossen = true
                        if ns.Anwesenheit and ns.Anwesenheit.BeispielKandidatenReset then
                            ns.Anwesenheit.BeispielKandidatenReset()
                        end
                        print("|cff1B6B57Fairshare|r: " .. string.format(L["Raidabend %s erfolgreich abgeschlossen!"], date("%d.%m.%Y", t)))
                        print(string.format(L["  Schnitt: %.2f (%d Main-Items / %d Spieler). %d Zuschläge festgeschrieben."], 1.0, 10, 10, 2))
                    else
                        local ok, v, zZaehler = ns.Anwesenheit.AbendAbschliessen()
                        if ok then
                            print("|cff1B6B57Fairshare|r: " .. string.format(L["Raidabend %s erfolgreich abgeschlossen!"], tostring(v.datum)))
                            print(string.format(L["  Schnitt: %.2f (%d Main-Items / %d Spieler). %d Zuschläge festgeschrieben."], v.schnitt, v.mainItems, v.raidSpieler, zZaehler or 0))
                        else
                            print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(v) .. "|r")
                        end
                    end
                end
                Fenster.Aktualisieren()
            else
                zustand.abschlussBestaetigung = t
                Fenster.Aktualisieren()
            end
        end)
        offeneBtn:SetShown(istGeschlossen and not zustand.beispiel and darfSchliessen and true or false)
        if offeneBtn:IsShown() then
            unterzeile:SetPoint("RIGHT", offeneBtn, "LEFT", -10, 0)
        else
            unterzeile:SetPoint("RIGHT", abschlussBtn, "LEFT", -10, 0)
        end
    else
        zustand.abschlussBestaetigung = nil
        abschlussBtn:Hide()
        offeneBtn:Hide()
        unterzeile:SetPoint("RIGHT", gruppeBtn, "LEFT", -10, 0)
    end

    if probeLeiste then
        probeLeiste:SetShown(zustand.probe and true or false)
    end
    tafel:ClearAllPoints()
    tafel:SetPoint("TOPLEFT", rahmen, "TOPLEFT", TAFEL_X, -(zustand.probe and (TAFEL_OBEN + 32) or TAFEL_OBEN))
    tafel:SetPoint("BOTTOMRIGHT", rahmen, "BOTTOMRIGHT", -TAFEL_X, FUSS + 10)

    if zustand.probe and probeLeiste then
        local roster = ns.Probe and ns.Probe.Roster and ns.Probe.Roster() or { "Anna", "Ben", "Chris", "Dora", "Emil", "Felix" }
        local spielerOpt = {}
        for _, n in ipairs(roster) do
            spielerOpt[#spielerOpt + 1] = { wert = n, label = n }
        end
        local sp = zustand.probeSpieler or "Anna"
        probeSpielerDropdown:SetOptionen(spielerOpt, sp, function(wert)
            zustand.probeSpieler = wert
            if zustand.spieler then zustand.spieler = wert end
            Fenster.Aktualisieren()
        end)
        probeSpielerDropdown:SetLabel(sp)

        local imRaid = ns.Probe and ns.Probe.IstImRaid and ns.Probe.IstImRaid(sp)
        probeRaidBtn:SetArt(imRaid and "primary" or "secondary")
        probeRaidBtn:SetLabel(imRaid and L["Aus dem Raid"] or L["In den Raid"])

        local istB = ns.Anwesenheit and ns.Anwesenheit.IstBank and ns.Anwesenheit.IstBank(sp)
        probeBankBtn:SetArt(istB and "primary" or "secondary")
        probeBankBtn:SetAktiv(not imRaid)

        local istA = ns.Anwesenheit and ns.Anwesenheit.IstAbgemeldet and ns.Anwesenheit.IstAbgemeldet(sp)
        probeAbmeldBtn:SetArt(istA and "primary" or "secondary")
        probeAbmeldBtn:SetAktiv(not imRaid)

        local istU = ns.Anwesenheit and ns.Anwesenheit.IstUnentschuldigt and ns.Anwesenheit.IstUnentschuldigt(sp)
        probeUnentBtn:SetArt(istU and "primary" or "secondary")
        probeUnentBtn:SetAktiv(not imRaid)
    end

    -- Wie viele Zeilen passen in das Fenster? Aus der Fensterhoehe gerechnet,
    -- nicht aus der Tafel: deren Ausmasse stehen erst nach dem Zeichnen fest.
    local platz = rahmen:GetHeight() - (zustand.probe and (TAFEL_OBEN + 32) or TAFEL_OBEN) - (FUSS + 10) - 40
    zeilenSicht = math.max(4, math.min(MAXZEILEN, math.floor(platz / ZEILENHOEHE)))
    for i = 1, MAXZEILEN do zeilen[i]:SetShown(i <= zeilenSicht) end

    local H, grund = historie()
    if not H then
        leereZeilen(1)
        setzeKopf(nil, nil, nil, nil, nil)
        ordneSpalten("liste")
        zeilen[1].a:SetWidth(BREITE - 80)
        zeilen[1].a:SetText(ROT .. tostring(grund) .. "|r")
        zeilen[2].a:SetWidth(BREITE - 80)
        zeilen[2].a:SetText(GRAU .. L["Der Knopf Beispiel zeigt, wie die Anzeige aussieht."] .. "|r")
        fuss:SetText("")
        unterzeile:SetText("")
        return
    end

    if zustand.spieler then
        ordneSpalten("spieler")
        zeigeSpieler(H)
    elseif zustand.ansicht == "verlauf" then
        ordneSpalten("verlauf")
        zeigeVerlauf(H)
    elseif zustand.ansicht == "bank" then
        ordneSpalten("bank")
        zeigeBank(H)
    elseif zustand.ansicht == "einteilung" then
        ordneSpalten("einteilung")
        zeigeEinteilung()
    else
        ordneSpalten("liste")
        zeigeListe(H)
    end

    -- Wer schreibt gerade mit?
    if ns.Rolle and not zustand.beispiel and not zustand.probe then
        local darf, warum = ns.Rolle.IchSchreibe()
        local text = fuss:GetText() or ""
        local zusatz = darf and (L["Du zeichnest auf"] .. " (" .. tostring(warum) .. ")") or tostring(warum)
        fuss:SetText(text .. "   |   " .. zusatz)
    end
end

-- =====================================================================
--  Steuerung
-- =====================================================================

function Fenster.Zeigen(beispiel)
    baueFenster()
    if zustand.probe then
        Fenster.ProbeModus(false)
    end
    if beispiel ~= nil then zustand.beispiel = beispiel and true or false end
    zustand.spieler = nil
    zustand.versatz = 0
    zustand.ansicht = "liste"
    rahmen:Show()
    Fenster.Aktualisieren()
end

--- Fenster in einer bestimmten Ansicht oeffnen ("liste", "verlauf", "bank" oder "einteilung").
function Fenster.ZeigenAnsicht(ansicht)
    Fenster.Zeigen(false)
    zustand.ansicht = (ansicht == "verlauf" or ansicht == "bank" or ansicht == "einteilung") and ansicht or "liste"
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

--- Schaltet den Probe-Modus (Übungsmodus) ein oder aus.
function Fenster.ProbeModus(an)
    baueFenster()
    if an then
        if zustand.beispiel then zustand.beispiel = false end
        zustand.probe = true
        zustand.probeSpieler = "Anna"
        zustand.spieler = nil
        zustand.versatz = 0
        zustand.ansicht = "liste"
        if ns.Probe and ns.Probe.Starten then ns.Probe.Starten() end
        rahmen:Show()
        Fenster.Aktualisieren()
    else
        if zustand.probe then
            zustand.probe = false
            zustand.spieler = nil
            zustand.versatz = 0
            if ns.Probe and ns.Probe.Beenden then ns.Probe.Beenden() end
            Fenster.Aktualisieren()
        end
    end
end

function Fenster.ProbeUmschalten()
    if zustand.probe and rahmen and rahmen:IsShown() then
        Fenster.ProbeModus(false)
        Fenster.Verstecken()
    else
        Fenster.ProbeModus(true)
    end
end

function Fenster.IstProbe()
    return zustand and zustand.probe and true or false
end

--- Wählt den Tag der Einteilung (Datum JJJJ-MM-TT aus der Tagesliste).
function Fenster.TagWaehlen(datum)
    zustand.einteilungTag = datum
    zustand.versatz = 0
    if rahmen then Fenster.Aktualisieren() end
end

--- Prüfstand: Die beiden Listen der Ansicht „Einteilung“ nach dem letzten Zeichnen:
--  { verfuegbar = { { name, gruppe }, … }, drin = { … }, ziel = Gruppenname/Bench/Keine Meldung }.
function Fenster.EinteilungReihenfolge()
    local aus = { verfuegbar = {}, drin = {}, ziel = zustand.einteilungZiel }
    for _, e in ipairs(zustand.einteilungListe or {}) do aus.verfuegbar[#aus.verfuegbar + 1] = { name = e.name, gruppe = e.gruppe } end
    for _, e in ipairs(zustand.einteilungDrin or {}) do aus.drin[#aus.drin + 1] = { name = e.name, gruppe = e.gruppe } end
    return aus
end

--- Prüfstand: Klick auf den Knopf des Spielers in der Einteilung (links „Hinzufügen/Verschieben“, rechts „Entfernen“).
--  @return "hinzu", "entf" oder nil (nicht zu sehen oder der Knopf ist gesperrt)
function Fenster.EinteilungKlick(name)
    for i = 1, zeilenSicht or 0 do
        local r = zeilen[i]
        if r and r:IsShown() then
            local b, was
            if r.linksName == name then b, was = r.teilBtn, "hinzu"
            elseif r.rechtsName == name then b, was = r.entfBtn, "entf" end
            if b and b:IsShown() and b:IsEnabled() then
                b:GetScript("OnClick")(b)
                return was
            end
        end
    end
    return nil
end

--- Prüfstand: Ist dieser Reiter sichtbar? Abwesenheit und Einteilung nur mit Schreibrecht (nach dem letzten Zeichnen).
function Fenster.ReiterSichtbar(ansicht)
    if ansicht == "bank" or ansicht == "einteilung" then return zustand.reiterSichtbar and true or false end
    return true
end

--- Prüfstand: Die gerade gewählte Ansicht.
function Fenster.AktuelleAnsicht()
    return zustand.ansicht
end

--- Diagnose/Prüfstand: Wie viele Zeilenknöpfe jeder Art sind in den sichtbaren Zeilen gerade da? Die Zeilen werden
--  von allen Ansichten mitbenutzt; ein Knopf einer anderen Ansicht darf nicht stehen bleiben.
function Fenster.ZeilenKnoepfe()
    local z = { bank = 0, unent = 0, vergessen = 0, abmeld = 0, teil = 0, entf = 0 }
    local feld = { bank = "bankBtn", unent = "unentBtn", vergessen = "vergessenBtn", abmeld = "abmeldBtn", teil = "teilBtn",
                   entf = "entfBtn" }
    for i = 1, zeilenSicht or 0 do
        local r = zeilen[i]
        if r and r:IsShown() then
            for k, f in pairs(feld) do
                if r[f] and r[f]:IsShown() then z[k] = z[k] + 1 end
            end
        end
    end
    return z
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
    if not GL then return false, L["Gargul ist nicht geladen"] end
    if not (GL.Events and GL.Events.register) then
        return false, L["Gargul hat keine Ereignis-Schnittstelle"]
    end

    GL.Events:register("FairshareWurfStart", "GL.ROLLOFF_STARTED", function()
        if not ns.Rolle.Aktiv() then return end   -- ohne Plündermeister ruht das Addon
        if Fenster.AutoOeffnen() then
            Fenster.Zeigen(false)
        else
            Fenster.Aktualisieren()
        end
    end)

    -- Jeder eingehende Wurf aendert die Reihenfolge.
    GL.Events:register("FairshareWurf", "GL.ROLLOFF_ROLL_ACCEPTED", function()
        Fenster.Aktualisieren()
    end)

    GL.Events:register("FairshareWurfEnde", "GL.ROLLOFF_STOPPED", function()
        Fenster.Aktualisieren()
    end)

    -- ⭐ Eine Vergabe in Gargul landet auch in unserer Historie — mit
    -- Haupt/Zweitbedarf und Wurf, die der Chat nie liefert. Ob wir sie
    -- eintragen duerfen, entscheidet die Rolle (nur der Schreiber).
    GL.Events:register("FairshareVergabe", "GL.ITEM_AWARDED", function(_, Eintrag)
        pcall(ns.Erfassung.GargulVergabe, Eintrag)
        Fenster.Aktualisieren()
    end)
    GL.Events:register("FairshareVergabeGeaendert", "GL.ITEM_AWARD_EDITED", function(_, Eintrag)
        pcall(ns.Erfassung.GargulAenderung, Eintrag)
        Fenster.Aktualisieren()
    end)
    GL.Events:register("FairshareVergabeZurueck", "GL.ITEM_UNAWARDED", function(_, Eintrag)
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
