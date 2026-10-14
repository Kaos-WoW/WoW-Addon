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

local BREITE, HOEHE = 760, 600
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
local AKZENT = S.Code(C.ac)

local rahmen, kopfZeile, tafel, fuss, unterzeile, kopfTag
local zeilen = {}
local ansichtSeg, zeitSeg, abgleichBtn, einstellBtn, gruppeBtn, zurueckBtn, beispielBtn, nurBtn, wurfBtn

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
                 { dx, math.max(80, w - dx), "LEFT" }, { 0, 1, "LEFT" } }
    elseif name == "spieler" then
        return { { 0, 120, "LEFT" }, { 126, 80, "LEFT" }, { 0, 1, "LEFT" },
                 { 214, math.max(80, w - 214), "LEFT" }, { 0, 1, "LEFT" } }
    end
    -- liste: Spieler | Haupt | Zweit | Zuletzt | Wurf
    local ew, dw, cw, bw = 120, 160, 60, 60
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
    z:SetScript("OnClick", function(s)
        if zustand.spieler or not s.spielername then return end
        zustand.spieler = s.spielername
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)
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
    ansichtSeg:SetWerte({ { wert = "liste", label = L["Spieler"] }, { wert = "verlauf", label = L["Verlauf"] } })
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
        zustand.alleSpieler = not zustand.alleSpieler
        zustand.versatz = 0
        Fenster.Aktualisieren()
    end)

    fuss = S.Text(f, 11, C.mu, "LEFT")
    fuss:SetPoint("LEFT", f, "LEFT", 16, 0)
    fuss:SetPoint("RIGHT", nurBtn, "LEFT", -12, 0)
    beispielBtn:SetScript("OnClick", function()
        zustand.beispiel = not zustand.beispiel
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

    S.Verstellbar(rahmen, "uebersicht", { b = BREITE, h = HOEHE, minB = 760, minH = 420,
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

    local liste, gesamt, aeltester = Kern.Bilanz(H, seit(), pflicht, nur)

    local istWuerfler
    if W then
        -- false = kein Wurf, sonst die Art ("haupt"/"zweit") oder true
        istWuerfler = function(name)
            local k = wurfSchluessel(W, name)
            if not k then return false end
            return (W.Arten and W.Arten[k]) or true
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
        z.hover:SetShown(false)
        z.markiert:SetShown(wuerfelt and true or false)

        z.a:SetText((wuerfelt and HELL or "") .. e.name .. (wuerfelt and "|r" or ""))
        z.b:SetText(e.haupt > 0 and (GELB .. e.haupt .. "|r") or (GRAU .. "0|r"))
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
        local haupt, zweit = 0, 0
        for _, art in pairs(W.Arten or {}) do
            if art == "haupt" then haupt = haupt + 1 elseif art == "zweit" then zweit = zweit + 1 end
        end
        unterzeile:SetText(GELB .. L["Wurf läuft"] .. "|r  " .. (was and (was .. "  ") or "") ..
            GRAU .. "—  " .. string.format(L["%d Haupt · %d Zweit · wenigste Stücke, dann höchster Wurf"], haupt, zweit) .. "|r")
    else
        unterzeile:SetText("")
    end
end

local function zeigeSpieler(H)
    setzeKopf(L["Datum"], L["Art"], nil, L["Gegenstand"], nil)

    local liste = Kern.Spieler(H, zustand.spieler, seit())
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
        z.a:SetText(date(L["%d.%m.%Y"], e.zeit))
        z.b:SetText(e.zweit and (GRAU .. L["Zweit"] .. "|r") or L["Haupt"])
        z.c:SetText("")
        z.d:SetText(Quelle.Gegenstandstext(e.eintrag))
        z.e:SetText("")
    end
    leereZeilen(gezeigt + 1)

    local haupt = 0
    for _, e in ipairs(liste) do if not e.zweit then haupt = haupt + 1 end end
    fuss:SetText(string.format(L["%s: %d Vergaben, davon %d Hauptbedarf"],
        Kern.Anzeigename(zustand.spieler), #liste, haupt))
    unterzeile:SetText(HELL .. Kern.Anzeigename(zustand.spieler) .. "|r")
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
        z.a:SetText(GRAU .. date(L["%d.%m. %H:%M"], e.zeit) .. "|r")
        z.b:SetText(e.name)
        z.c:SetText(e.zweit and (GRAU .. L["Zweit"] .. "|r") or L["Haupt"])
        z.d:SetText(Quelle.Gegenstandstext(e.eintrag))
        z.e:SetText("")
    end
    leereZeilen(gezeigt + 1)

    local text = string.format(L["%d Vergaben, neueste zuerst"], #liste)
    if #liste > zeilenSicht then text = text .. "   |   " .. L["Mausrad blättert"] end
    fuss:SetText(text)
    unterzeile:SetText("")
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
    if zustand.gruppe and not (ns.Gruppen and ns.Gruppen.Holen(zustand.gruppe)) then
        zustand.gruppe = nil     -- die Gruppe wurde inzwischen geloescht
    end
    gruppeBtn:SetLabel(string.format(L["Gruppe: %s"],
        zustand.gruppe or (#Namen > 0 and L["Alle"] or L["keine"])))
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

    local imGruppe = IsInGroup and IsInGroup() and true or false
    wurfBtn:SetShown(not zustand.beispiel and ns.Wurf ~= nil and ns.Wurf.DarfStarten())
    nurBtn:SetShown(imGruppe and not zustand.beispiel and zustand.ansicht == "liste" and zustand.spieler == nil)
    nurBtn:SetLabel(zustand.alleSpieler and L["Nur Gruppe zeigen"] or L["Alle Spieler zeigen"])

    zurueckBtn:SetShown(zustand.spieler ~= nil)
    unterzeile:ClearAllPoints()
    if zustand.spieler then
        unterzeile:SetPoint("LEFT", zurueckBtn, "RIGHT", 10, 0)
    else
        unterzeile:SetPoint("LEFT", rahmen, "TOPLEFT", 16, -(KOPF + 61))
    end
    unterzeile:SetPoint("RIGHT", gruppeBtn, "LEFT", -10, 0)

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
    if not GL then return false, L["Gargul ist nicht geladen"] end
    if not (GL.Events and GL.Events.register) then
        return false, L["Gargul hat keine Ereignis-Schnittstelle"]
    end

    GL.Events:register("FairshareWurfStart", "GL.ROLLOFF_STARTED", function()
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
