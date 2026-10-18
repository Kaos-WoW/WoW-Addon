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
local ansichtSeg, zeitSeg, abgleichBtn, einstellBtn, gruppeBtn, zurueckBtn, beispielBtn, nurBtn, wurfBtn, abschlussBtn, offeneBtn
local rangBtn, syncBtn, tagBtn, sendenBtn      -- Ansicht „Einteilung“
local zustand = { wochen = 0, beispiel = false, spieler = nil, versatz = 0, maxVersatz = 0,
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
        local a, b, c, d = 140, 80, 84, 96
        -- Abwesenheit (Entscheid 18.10.2026): nur noch Bank/Bench und Unentschuldigt; Abgemeldet und Keine Meldung
        -- werden in der Einteilung gesetzt. Danach das Protokoll.
        local dx = a + L6 + b + L6 + c + L6 + d + L6
        return { { 0, a, "LEFT" }, { a + L6, b, "LEFT" }, { a + L6 + b + L6, c, "CENTER" },
                 { a + L6 + b + L6 + c + L6, d, "CENTER" }, { dx, math.max(100, w - dx - 10), "LEFT" } }
    elseif name == "einteilung" then
        -- Spieler | Rang | Eingeteilt in | Knopf | Hinweis
        local a, b, c, d = 170, 120, 170, 110
        local dx = a + L6 + b + L6 + c + L6 + d + L6
        return { { 0, a, "LEFT" }, { a + L6, b, "LEFT" }, { a + L6 + b + L6, c, "LEFT" },
                 { a + L6 + b + L6 + c + L6, d, "CENTER" }, { dx, math.max(80, w - dx - 10), "LEFT" } }
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
    if zustand.beispiel then return Quelle.Beispiel() end
    local H, grund = Quelle.Historie()
    if not H then return nil, grund end
    return Kern.NachGruppe(H, zustand.gruppe)
end

local function wurf()
    if zustand.beispiel then return Quelle.BeispielWurf() end
    return Quelle.Wurf()
end

--- ⭐ In einer Gruppe zeigt die Liste nur die Spieler, die gerade dabei sind.
--  Ohne Gruppe (oder auf Wunsch, oder bei Beispieldaten) gilt alles.
--  @return Liste der Namen, oder nil fuer „alle"
local function nurGruppe()
    if zustand.beispiel or zustand.alleSpieler or not ns.Rolle then return nil end
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
        -- ⭐ Einteilung: Rechtsklick auf den Namen nimmt den Spieler aus seiner Gruppe (egal in welcher er steht)
        if zustand.ansicht == "einteilung" then
            if taste == "RightButton" and s.spielername and zustand.einteilungDatum then
                local ok, grund = ns.Gruppen.EinteilungSetzen(zustand.einteilungDatum, s.spielername, "")
                if not ok then print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(grund) .. "|r") end
                Fenster.Aktualisieren()
            end
            return
        end
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

    z.abmeldBtn = S.Knopf(z, L["Abgemeldet"], "secondary", 20)
    z.abmeldBtn:SetFest(100)
    z.abmeldBtn:SetFrameLevel(z:GetFrameLevel() + 3)
    z.abmeldBtn:Hide()

    -- Einteilung: in die gewaehlte Gruppe setzen / herausnehmen
    z.teilBtn = S.Knopf(z, L["Hinzufügen"], "secondary", 20)
    z.teilBtn:SetFest(104)
    z.teilBtn:SetFrameLevel(z:GetFrameLevel() + 3)
    z.teilBtn:Hide()
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

--- ⭐ Der Tag der Einteilung: der gewählte Raidtag (sonst der erste), mit Beschriftung und der ganzen Liste.
--  @return datum, label, liste
local function einteilungsTag()
    local liste = ns.Gruppen.EinteilungTage()
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
        { wert = "bank", label = L["Abwesenheit"] },
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

    -- Gruppe wechseln: Alle -> erste -> zweite ... -> Alle
    gruppeBtn = S.Knopf(rahmen, "", "secondary", 24)
    gruppeBtn:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -16, -(KOPF + 50))
    gruppeBtn:SetScript("OnClick", function()
        local Namen = ns.Gruppen and ns.Gruppen.Namen() or {}
        if #Namen == 0 then return end
        -- ⭐ In der Einteilung ist auch die Bench ein Ziel
        if zustand.ansicht == "einteilung" then
            Namen[#Namen + 1] = ns.Gruppen.BENCH
            Namen[#Namen + 1] = ns.Gruppen.KEINEMELDUNG
        end
        -- ⭐ Abwesenheit: die Gruppe wählen (= aktivieren), deren Abend du führst; ein Wechsel ist ein anderer Abend
        if zustand.ansicht == "bank" and not zustand.beispiel then
            local aktuell, nach = ns.Gruppen.AktivName(), Namen[1]
            for i, n in ipairs(Namen) do
                if n == aktuell then nach = Namen[i + 1] or Namen[1] break end
            end
            ns.Gruppen.Aktivieren(nach)
            zustand.versatz = 0
            Fenster.Aktualisieren()
            return
        end
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

    -- ⭐ Ansicht „Einteilung": Rang waehlen, Raidkader einlesen, Tag waehlen, Einteilung senden
    rangBtn = S.Knopf(rahmen, "", "secondary", 24)
    rangBtn:SetPoint("RIGHT", gruppeBtn, "LEFT", -8, 0)
    rangBtn:Hide()
    rangBtn:SetScript("OnClick", function()
        local R = ns.Gruppen.Raenge()
        if not R then return end
        local liste = {}
        for _, r in ipairs(R) do liste[#liste + 1] = r end
        local aktuell = ns.Gruppen.RaidkaderRang()
        local naechster = liste[1]
        for i, r in ipairs(liste) do
            if r.index == aktuell then naechster = liste[i + 1] or liste[1] break end
        end
        if naechster then ns.Gruppen.RaidkaderRangSetzen(naechster.index) end
        Fenster.Aktualisieren()
    end)

    syncBtn = S.Knopf(rahmen, L["Raidkader synchronisieren"], "primary", 24)
    syncBtn:SetPoint("RIGHT", rangBtn, "LEFT", -8, 0)
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
        -- der nächste Raidtag der Reihe
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
    beispielBtn = S.Knopf(f, L["Beispiel"], "link", 22)
    beispielBtn:SetPoint("RIGHT", f, "RIGHT", -16, 0)

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
        if zustand.ansicht == "bank" then
            zustand.bankMitRaid = not zustand.bankMitRaid     -- Abwesenheit: Spieler im Raid mitzeigen
        else
            zustand.alleSpieler = not zustand.alleSpieler
        end
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    fuss = S.Text(f, 11, C.mu, "LEFT")
    fuss:SetPoint("LEFT", f, "LEFT", 16, 0)
    fuss:SetPoint("RIGHT", nurBtn, "LEFT", -12, 0)
    beispielBtn:SetScript("OnClick", function()
        zustand.beispiel = not zustand.beispiel
        zustand.beispielAbgeschlossen = false
        if ns.Anwesenheit and ns.Anwesenheit.BeispielKandidatenWiederherstellen then
            ns.Anwesenheit.BeispielKandidatenWiederherstellen()
        end
        zustand.spieler = nil
        zustand.versatz = 0
        Fenster.Aktualisieren()
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
        z.eintragId = nil
        z.undo:Hide()
        if z.bankBtn then z.bankBtn:Hide() end
        if z.unentBtn then z.unentBtn:Hide() end
        if z.vergessenBtn then z.vergessenBtn:Hide() end
        if z.abmeldBtn then z.abmeldBtn:Hide() end
        if z.teilBtn then z.teilBtn:Hide() end
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
        if z.teilBtn then z.teilBtn:Hide() end
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
        if z.teilBtn then z.teilBtn:Hide() end

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
        if z.teilBtn then z.teilBtn:Hide() end
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
    setzeKopf(L["Spieler"], L["Status"], L["Bank"], L["Unentschuldigt"], L["Protokoll"])

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
        liste = ns.Anwesenheit.KandidatenListe(abend, zustand.bankMitRaid)
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
        if z.teilBtn then z.teilBtn:Hide() end        -- ⭐ die Zeilen werden von allen Ansichten mitbenutzt

        z.a:SetText(HELL .. Kern.Anzeigename(e.name) .. "|r")
        if e.imRaid then
            z.b:SetText(AKZENT .. L["Im Raid"] .. "|r")
        elseif e.benchEinteilung then
            z.b:SetText(AKZENT .. L["Bench"] .. "|r")      -- ⭐ die Bench fällt sofort auf
        else
            z.b:SetText(e.online and (GRUEN .. L["Online"] .. "|r") or (GRAU .. L["Offline"] .. "|r"))
        end

        z.c:SetText("")
        z.bankBtn:ClearAllPoints()
        z.bankBtn:SetPoint("CENTER", z.c, "CENTER", 0, 0)
        z.bankBtn:Show()
        z.bankBtn:SetArt(e.bank and "primary" or "secondary")
        z.bankBtn:SetLabel(e.benchEinteilung and L["✓ Bench"] or (e.bank and L["✓ Bank"] or L["Bank"]))
        z.bankBtn:SetAktiv(darfBank)
        z.bankBtn:SetScript("OnClick", function()
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
        z.unentBtn:ClearAllPoints()
        z.unentBtn:SetPoint("CENTER", z.d, "CENTER", 0, 0)
        z.unentBtn:Show()
        z.unentBtn:SetArt(e.unentschuldigt and "primary" or "secondary")
        z.unentBtn:SetLabel(e.unentschuldigt and L["✓ Unent."] or L["Unent."])
        z.unentBtn:SetAktiv(darfUnent)
        z.unentBtn:SetScript("OnClick", function()
            if zustand.beispiel then
                if ns.Anwesenheit and ns.Anwesenheit.BeispielUnentToggle then
                    ns.Anwesenheit.BeispielUnentToggle(e.name)
                end
            elseif ns.Anwesenheit and ns.Anwesenheit.UnentschuldigtSetzen then
                ns.Anwesenheit.UnentschuldigtSetzen(e.name, not (e.unentschuldigt ~= nil))
            end
            Fenster.Aktualisieren()
        end)

        -- ⭐ „Keine Meldung“ und „Abgemeldet“ gibt es hier nicht mehr (Einteilung, Entscheid 18.10.2026)
        z.vergessenBtn:Hide()
        z.abmeldBtn:Hide()

        if e.offen then
            z.e:SetText(GELB .. L["Offen: noch nicht zugeordnet"] .. "|r")
        else
            z.e:SetText(GRAU .. (e.protokoll ~= "" and e.protokoll or "—") .. "|r")
        end
    end
    leereZeilen(gezeigt + 1)

    local anzahlBank, anzahlUnent, anzahlVerg, anzahlOnline, anzahlOffen, anzahlAbgem = 0, 0, 0, 0, 0, 0
    for _, e in ipairs(liste) do
        if e.offen then anzahlOffen = anzahlOffen + 1 end
        if e.abgemeldet then anzahlAbgem = anzahlAbgem + 1 end
        if e.bank then anzahlBank = anzahlBank + 1 end
        if e.unentschuldigt then anzahlUnent = anzahlUnent + 1 end
        if e.vergessen then anzahlVerg = anzahlVerg + 1 end
        if e.online then anzahlOnline = anzahlOnline + 1 end
    end

    if istGeschlossen then
        fuss:SetText(L["Raidabend abgeschlossen · Bereit für nächsten Raid"])
        unterzeile:SetText(GRUEN .. L["Raidabend abgeschlossen. Die Wertungen sind gebucht; „Neuen Abend beginnen“ macht die Liste frei."] .. "|r")
    else
        fuss:SetText(string.format(L["%d offen, %d Bench, %d unentschuldigt · %d online"],
            anzahlOffen, anzahlBank, anzahlUnent, anzahlOnline))
        if zustand.bankMitRaid then
            unterzeile:SetText(GRAU .. L["Wer am Abendende im Raid steht, gilt als anwesend. Eine Markierung zählt nur für Spieler, die dann nicht mehr im Raid sind."] .. "|r")
        else
            unterzeile:SetText(GRAU .. L["Offene verhindern den Abschluss · Bench: Faktor 0 · Unentschuldigt: Faktor 1,5, mindestens 2 · Abgemeldete und „Keine Meldung“ stellst du in der Einteilung ein."] .. "|r")
        end
        -- ⭐ Woher kommt die Liste? Hinweise, wenn die Einteilung von heute fehlt oder leer ist
        if not zustand.beispiel then
            local G = ns.Gruppen
            local heute = G.EinteilungTag(0)
            local aktiv = G.AktivName()
            if G.EinteilungVorhanden(heute) and not aktiv then
                unterzeile:SetText(GELB .. L["Für heute gibt es eine Einteilung: oben rechts die Gruppe wählen, deren Abwesenheit du führst."] .. "|r")
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

--- ⭐ Ansicht „Einteilung“: der Raidkader als anklickbare Liste. Ein Klick setzt den Spieler in die oben gewählte
--  Gruppe (für den gewählten Tag) oder nimmt ihn wieder heraus. Wer nirgends eingeteilt ist, steht oben.
local function zeigeEinteilung()
    local G = ns.Gruppen
    local datum, tagLabel = einteilungsTag()
    zustand.einteilungDatum = datum
    local ziel = zustand.gruppe
    local darf = not zustand.beispiel and G.EinteilungDarf()

    setzeKopf(L["Spieler"], L["Rang"], L["Eingeteilt in"], "", L["Hinweis"])

    -- Pool: der Raidkader, dazu alle, die an diesem Tag eingeteilt sind, aber nicht im Raidkader stehen
    local pool, gesehen = {}, {}
    local kader, stand = G.Raidkader()
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
    for _, e in ipairs(pool) do
        e.gruppe = G.EinteilungVon(datum, e.name)
    end
    -- ⭐ Wer eingeteilt ist, steht OBEN, nach Gruppen sortiert (erst Gruppe 1 ganz, dann Gruppe 2 …, dann Bench,
    -- dann Keine Meldung); wer nirgends steht, folgt unten. Innerhalb einer Gruppe alphabetisch.
    local rang = {}
    for i, gn in ipairs(alleZiele) do rang[gn] = i end
    local function sortRang(e) return e.gruppe and (rang[e.gruppe] or (#alleZiele + 1)) or (#alleZiele + 2) end
    table.sort(pool, function(a, b)
        local ra, rb = sortRang(a), sortRang(b)
        if ra ~= rb then return ra < rb end
        return a.name:lower() < b.name:lower()
    end)

    -- ⭐ Ist eine Gruppe als Ziel gewählt, stehen Spieler, die schon in einer ANDEREN Gruppe sind, nicht zur Wahl
    -- (Entscheid 18.10.2026); wer sie umziehen will, wählt die alte Gruppe und nimmt sie dort heraus.
    local zielIstGruppe = ziel ~= nil and ziel ~= G.BENCH and ziel ~= G.KEINEMELDUNG
    local anzeige, versteckt = {}, 0
    for _, e in ipairs(pool) do
        local andere = zielIstGruppe and e.gruppe ~= nil and e.gruppe ~= ziel
                       and e.gruppe ~= G.BENCH and e.gruppe ~= G.KEINEMELDUNG
        if andere then versteckt = versteckt + 1 else anzeige[#anzeige + 1] = e end
    end
    zustand.einteilungListe = anzeige
    zustand.maxVersatz = math.max(0, #anzeige - zeilenSicht)
    if zustand.versatz > zustand.maxVersatz then zustand.versatz = zustand.maxVersatz end

    local gezeigt = 0
    for i = 1, zeilenSicht do
        local z = zeilen[i]
        local e = anzeige[i + zustand.versatz]
        if not e then break end
        gezeigt = i

        z.spielername = e.name
        z.hover:SetShown(false)
        z.markiert:SetShown(false)
        z.undo:Hide()
        -- ⭐ die Zeilen werden von allen Ansichten mitbenutzt: Knöpfe der Abwesenheit dürfen nicht stehen bleiben
        if z.bankBtn then z.bankBtn:Hide() end
        if z.unentBtn then z.unentBtn:Hide() end
        if z.vergessenBtn then z.vergessenBtn:Hide() end
        if z.abmeldBtn then z.abmeldBtn:Hide() end
        z.b:SetText(GRAU .. tostring(e.rang or "") .. "|r")
        if e.gruppe == nil then
            z.a:SetText(HELL .. Kern.Anzeigename(e.name) .. "|r")
            z.c:SetText(GRAU .. "—|r")
        elseif e.gruppe == G.BENCH then
            z.a:SetText(AKZENT .. Kern.Anzeigename(e.name) .. "|r")
            z.c:SetText(AKZENT .. L["Bench"] .. "|r")        -- die Bench fällt auf
        elseif e.gruppe == G.KEINEMELDUNG then
            z.a:SetText(ROT .. Kern.Anzeigename(e.name) .. "|r")
            z.c:SetText(ROT .. L["Keine Meldung"] .. "|r")
        else
            local farbe = gruppenFarbe(G, e.gruppe)          -- jede Gruppe in ihrer Farbe
            z.a:SetText(farbe .. Kern.Anzeigename(e.name) .. "|r")
            z.c:SetText(farbe .. e.gruppe .. "|r")
        end
        z.d:SetText("")
        z.e:SetText("")

        local drin = (ziel ~= nil and e.gruppe == ziel)
        z.teilBtn:ClearAllPoints()
        z.teilBtn:SetPoint("CENTER", z.d, "CENTER", 0, 0)
        z.teilBtn:Show()
        z.teilBtn:SetArt(drin and "primary" or "secondary")
        z.teilBtn:SetLabel(drin and L["Entfernen"] or ((e.gruppe ~= nil) and L["Verschieben"] or L["Hinzufügen"]))
        z.teilBtn:SetAktiv(darf and ziel ~= nil)
        z.teilBtn:SetScript("OnClick", function()
            local ok, grund = G.EinteilungSetzen(datum, e.name, drin and "" or ziel)
            if not ok then print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(grund) .. "|r") end
            Fenster.Aktualisieren()
        end)
    end
    leereZeilen(gezeigt + 1)

    -- Kopfzeile der Werkzeugleiste dieser Ansicht
    local R = G.Raenge()
    local rangName = "—"
    for _, r in ipairs(R or {}) do
        if r.index == G.RaidkaderRang() then rangName = r.name end
    end
    rangBtn:SetLabel(string.format(L["Bis Rang: %s"], rangName))
    tagBtn:SetLabel(tagLabel)
    syncBtn:SetAktiv(G.RaidkaderRang() ~= nil and not zustand.beispiel)

    local inZiel, inAnderen = 0, 0
    for _, e in ipairs(pool) do
        if e.gruppe ~= nil then
            if e.gruppe == ziel then inZiel = inZiel + 1 else inAnderen = inAnderen + 1 end
        end
    end
    fuss:SetText(string.format(L["%d im Raidkader · %d in der gewählten Gruppe · %d in anderen Gruppen"], #kader, inZiel, inAnderen))
    local hinweis
    if #kader == 0 then
        hinweis = L["Erst oben den Rang wählen und den Raidkader synchronisieren."]
    elseif not ziel then
        hinweis = L["Oben rechts eine Gruppe wählen, dann Spieler anklicken."]
    elseif not darf then
        hinweis = L["Einteilen dürfen nur Gildenränge mit Schreibrecht (Einstellungen → Würfeln & Abgleich → Einstellungen teilen)."]
    else
        hinweis = string.format(L["Einteilung für %s, Gruppe %s. Rechtsklick auf einen Namen nimmt ihn aus seiner Gruppe."], datum, ziel)
        if versteckt > 0 then
            hinweis = hinweis .. " " .. string.format(L["%d Spieler anderer Gruppen sind ausgeblendet."], versteckt)
        end
    end
    unterzeile:SetText(GRAU .. hinweis .. "|r")
end

function Fenster.Aktualisieren()
    if not rahmen then return end

    -- Kopf: Version, bei Beispieldaten eine Warnfarbe
    if zustand.beispiel then
        kopfTag.text:SetText(L["Beispieldaten"])
        S.TextFarbe(kopfTag.text, C.warn)
    else
        kopfTag.text:SetText(version() .. " · Forever")
        S.TextFarbe(kopfTag.text, C.mu)
    end
    kopfTag:SetWidth(math.ceil(kopfTag.text:GetStringWidth()) + 12)

    -- Werkzeugleiste
    ansichtSeg:SetWahl(zustand.spieler and "liste" or zustand.ansicht)
    zeitSeg:SetWahl(zustand.wochen)
    beispielBtn:SetLabel(zustand.beispiel and L["Beispiel aus"] or L["Beispiel"])

    local Namen = ns.Gruppen and ns.Gruppen.Namen() or {}
    if zustand.gruppe == ns.Gruppen.BENCH or zustand.gruppe == ns.Gruppen.KEINEMELDUNG then
        -- Bench und „Keine Meldung“ sind nur in der Einteilung ein Ziel; sonst gilt „Alle“
        if zustand.ansicht ~= "einteilung" then zustand.gruppe = nil end
    elseif zustand.gruppe and not (ns.Gruppen and ns.Gruppen.Holen(zustand.gruppe)) then
        zustand.gruppe = nil     -- die Gruppe wurde inzwischen geloescht
    end
    -- ⭐ In der Abwesenheit wählt der Knopf die Gruppe, deren Abend du führst (die aktive Gruppe), sonst filtert er
    local gruppenName = (zustand.ansicht == "bank" and not zustand.beispiel)
        and (ns.Gruppen.AktivName() or L["keine"])
        or (zustand.gruppe or (#Namen > 0 and L["Alle"] or L["keine"]))
    if gruppenName == ns.Gruppen.BENCH then gruppenName = L["Bench"] end
    if gruppenName == ns.Gruppen.KEINEMELDUNG then gruppenName = L["Keine Meldung"] end
    gruppeBtn:SetLabel(string.format(L["Gruppe: %s"], gruppenName))
    gruppeBtn:SetAktiv(#Namen > 0 and not zustand.beispiel)

    -- Abgleich: auffaellig, wenn Mitspieler abweichen
    local abw = ns.Abgleich and ns.Abgleich.Abweichend or {}
    if #abw > 0 then
        abgleichBtn:SetArt("primary")
        abgleichBtn:SetLabel(string.format(L["Abgleichen (%d)"], #abw))
    else
        abgleichBtn:SetArt("secondary")
        abgleichBtn:SetLabel(L["Abgleichen"])
    end
    abgleichBtn:SetAktiv(not zustand.beispiel)

    zustand.darfUndo = not zustand.beispiel and ns.Erfassung.DarfZuruecknehmen()
    local imGruppe = IsInGroup and IsInGroup() and true or false
    wurfBtn:SetShown(not zustand.beispiel and ns.Wurf ~= nil and ns.Wurf.DarfStarten())
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
    nurBtn:SetShown((imGruppe and not zustand.beispiel and zustand.ansicht == "liste" and zustand.spieler == nil)
                    or (not zustand.beispiel and zustand.ansicht == "bank" and zustand.spieler == nil)
                    or (not zustand.beispiel and zustand.ansicht == "einteilung" and zustand.spieler == nil))
    if zustand.ansicht == "einteilung" then
        local bestaetigen = zustand.wocheBestaetigung and (time() - zustand.wocheBestaetigung) <= 8
        nurBtn:SetLabel(bestaetigen and (GELB .. L["Wirklich buchen?"] .. "|r") or L["Woche abschließen"])
        nurBtn:SetAktiv(ns.Gruppen.EinteilungDarf())
    elseif zustand.ansicht == "bank" then
        nurBtn:SetLabel(zustand.bankMitRaid and L["Raid ausblenden"] or L["Raid mitzeigen"])
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

    for _, b in ipairs({ rangBtn, syncBtn, tagBtn, sendenBtn }) do b:Hide() end
    if zustand.ansicht == "einteilung" and not zustand.spieler then
        zustand.abschlussBestaetigung = nil
        abschlussBtn:Hide()
        offeneBtn:Hide()
        for _, b in ipairs({ rangBtn, syncBtn, tagBtn, sendenBtn }) do b:Show() end
        unterzeile:SetPoint("RIGHT", sendenBtn, "LEFT", -10, 0)
    elseif zustand.ansicht == "bank" and not zustand.spieler then
        abschlussBtn:Show()
        local istGeschlossen = false
        if zustand.beispiel then
            istGeschlossen = zustand.beispielAbgeschlossen and true or false
        else
            istGeschlossen = ns.Anwesenheit and ns.Anwesenheit.AbendIstAbgeschlossen and ns.Anwesenheit.AbendIstAbgeschlossen()
        end
        local darfSchliessen = zustand.beispiel or (ns.Anwesenheit and ns.Anwesenheit.DarfBankVerwalten and ns.Anwesenheit.DarfBankVerwalten())
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

    -- Wie viele Zeilen passen in das Fenster? Aus der Fensterhoehe gerechnet,
    -- nicht aus der Tafel: deren Ausmasse stehen erst nach dem Zeichnen fest.
    local platz = rahmen:GetHeight() - TAFEL_OBEN - (FUSS + 10) - 40
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
    if ns.Rolle and not zustand.beispiel then
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

--- Prüfstand: Die Reihenfolge der Liste in der Ansicht „Einteilung“ (Name, Gruppe) nach dem letzten Zeichnen.
function Fenster.EinteilungReihenfolge()
    local liste = {}
    for _, e in ipairs(zustand.einteilungListe or {}) do liste[#liste + 1] = { name = e.name, gruppe = e.gruppe } end
    return liste
end

--- Prüfstand: Klick auf die Zeile dieses Spielers ("LeftButton" oder "RightButton").
function Fenster.ZeileKlick(name, taste)
    for i = 1, zeilenSicht or 0 do
        local r = zeilen[i]
        if r and r.spielername == name then
            local f = r:GetScript("OnClick")
            if f then f(r, taste or "LeftButton") end
            return true
        end
    end
    return false
end

--- Diagnose/Prüfstand: Wie viele Zeilenknöpfe jeder Art sind in den sichtbaren Zeilen gerade da? Die Zeilen werden
--  von allen Ansichten mitbenutzt; ein Knopf einer anderen Ansicht darf nicht stehen bleiben.
function Fenster.ZeilenKnoepfe()
    local z = { bank = 0, unent = 0, vergessen = 0, abmeld = 0, teil = 0 }
    local feld = { bank = "bankBtn", unent = "unentBtn", vergessen = "vergessenBtn", abmeld = "abmeldBtn", teil = "teilBtn" }
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
