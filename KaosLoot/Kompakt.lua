--[[----------------------------------------------------------------------
    Kompakt.lua  —  Das kleine Fenster fuer den Raid

    Ein schmales Fenster statt der grossen Uebersicht: Es zeigt nur die
    Wertung (wer als Naechster dran ist) und waehrend eines Wurfs den Wurf.
    Alles hier ist nur Anzeige; gerechnet wird in Kern.lua.

      Wertung   Spieler nach Wertung, niedrigste oben, eigene Zeile markiert
      Wurf      automatisch, solange ein Wurf laeuft (Gegenstand, Zeit, Wuerfe)
      Leiste    eine Zeile: wer dran ist, im Wurf der Gegenstand

      /kl kompakt         schaltet das Fenster
      /kl kompakt test    Vorschau mit Beispieldaten (Wertung, dann Wurf, dann aus),
                          damit man es auch allein ansehen kann

    Gross und klein schliessen sich gegenseitig: Wer das eine oeffnet, schliesst
    das andere. Offen/zu, Leiste und Lage werden gemerkt; nach dem Anmelden
    kommt es wieder, wenn es offen war.

    ⚠️ Eigene Datei, weil Fenster.lua an der Grenze von 60 Upvalues je
    Funktion steht (Lua 5.1).
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Kompakt = {}
ns.Kompakt = Kompakt

local Kern, Quelle = ns.Kern, ns.Quelle
local S = ns.Stil
local C = S.C

local GELB  = S.Code(C.warn)
local GRAU  = S.Code(C.mu)
local HELL  = S.Code(C.white)

local BREITE = 232
local KOPF = 28
local ZEILE = 18
local MAXZEILEN = 10
local WERTUNG_OBEN = KOPF + 6           -- Beginn der Zeilen unter dem Kopf
local WURF_OBEN = KOPF + 34             -- ... unter Gegenstand und Zeitbalken
local TAKT = 0.5                        -- Sekunden zwischen zwei Aktualisierungen

local rahmen, titel, leisteBtn, startBtn, zeilen, fuss, itemText, balken, balkenBahn
local versatz = 0                       -- Blaettern in der Wertung
local basis = nil                       -- aktuelle Ankerhoehe der Zeilen
local vorschau = nil                    -- nil | "wertung" | "wurf": Beispieldaten
local vorschauStart = 0

-- Beispieldaten fuer die Vorschau (Klassen als Schluessel, wie im Spiel)
local DEMO_WERTUNG = {
    { "Vanity Zerath", "HUNTER", 0 }, { "Golden Bone", "PALADIN", 0 }, { "Gaz Mog", "WARLOCK", 1 },
    { "Kaos", "WARRIOR", 2, true }, { "Umbra Drakonis", "SHAMAN", 2 }, { "Exfreya Greenleaf", "DRUID", 3 },
    { "Golschi Feuer", "MAGE", 3 }, { "Chivi Test", "PRIEST", 3 },
}
local DEMO_WURF = {
    { "Vanity Zerath", "HUNTER", "haupt", 87 }, { "Golden Bone", "PALADIN", "haupt", 64 },
    { "Kaos", "WARRIOR", "zweit", 91, true }, { "Umbra Drakonis", "SHAMAN", "zweit", 38 },
}

-- =====================================================================
--  Gemerktes
-- =====================================================================

local function db()
    FairshareDB = FairshareDB or {}
    FairshareDB.kompakt = FairshareDB.kompakt or {}
    return FairshareDB.kompakt
end

local function lageSpeichern()
    local l, t = rahmen:GetLeft(), rahmen:GetTop()
    if type(l) == "number" and type(t) == "number" then
        FairshareDB.fenster = FairshareDB.fenster or {}
        FairshareDB.fenster.kompakt = { x = l, y = t }
    end
end

-- =====================================================================
--  Daten
-- =====================================================================

local function ichName()
    if GetUnitName then
        local n = GetUnitName("player", true)
        if n and n ~= "" then return n end
    end
    return (UnitName("player"))
end

local function zahlText(w)
    return Kern.WertText(w, ns.Verteilung and ns.Verteilung.ProAbend())
end

--- Der Name in Klassenfarbe; `klasse` nur in der Vorschau (sonst wird sie nachgeschlagen).
local function farbName(name, klasse)
    local G = ns.Gruppen
    local f = klasse and G and G.KlasseFarbcode and G.KlasseFarbcode(klasse)
    if not f and not klasse then f = G and G.KlassenFarbe and G.KlassenFarbe(name) end
    return (f or HELL) .. Kern.Anzeigename(name) .. "|r"
end

--- Die Spieler nach Wertung, niedrigste zuerst (wie die Uebersicht, ohne Wurf).
--  In einer Gruppe nur wer dabei ist, sonst der Kader der aktiven Gruppe.
local function wertungListe()
    local H = Quelle.Historie()
    if not H then return {} end
    local nur, pflicht = nil, {}
    if IsInGroup and IsInGroup() and ns.Rolle and ns.Rolle.Namen then
        nur = ns.Rolle.Namen()
        for _, n in ipairs(nur) do pflicht[#pflicht + 1] = n end
    elseif ns.Gruppen and ns.Gruppen.Pflicht then
        pflicht = ns.Gruppen.Pflicht(nil)
    end
    local daten = ns.Anwesenheit and ns.Anwesenheit.ZuschlaegeDaten and ns.Anwesenheit.ZuschlaegeDaten() or nil
    local liste = Kern.Bilanz(H, 0, pflicht, nur, daten)
    if ns.Anwesenheit and ns.Anwesenheit.Rollen then ns.Anwesenheit.Rollen(liste, false) end
    -- ⭐ Die Reihenfolge wie beim Wurf (Regel „Heute schon ein Item“): oben steht, wer als Naechster dran waere
    Kern.WurfReihenfolge(liste, function() return "haupt" end)
    return liste
end

-- =====================================================================
--  Anzeige
-- =====================================================================

--- Die Zeilen unter dem Kopf neu verankern (nur wenn sich die Hoehe aendert).
local function setzeBasis(oben)
    if basis == oben then return end
    basis = oben
    for i = 1, MAXZEILEN do
        local z = zeilen[i]
        z:ClearAllPoints()
        z:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 6, -(oben + (i - 1) * ZEILE))
        z:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -6, -(oben + (i - 1) * ZEILE))
    end
end

local function zeile(i, links, mitte, rechts, markiert)
    local z = zeilen[i]
    z.a:SetText(links or "")
    z.b:SetText(mitte or "")
    z.c:SetText(rechts or "")
    z.markiert:SetShown(markiert == "ich")
    z.dran:SetShown(markiert == "dran")
    z:Show()
end

--- Platz unter den Zeilen: Fusszeile, dazu der Knopf Wurf starten, wenn er da ist.
local function unten()
    return 24 + ((startBtn and startBtn:IsShown()) and 30 or 0)
end

local function zeilenAus(ab)
    for i = ab, MAXZEILEN do zeilen[i]:Hide() end
end

local function zeigeWertung()
    setzeBasis(WERTUNG_OBEN)
    local ich = ichName()
    local liste = {}
    if vorschau then
        for _, d in ipairs(DEMO_WERTUNG) do
            liste[#liste + 1] = { name = d[1], klasse = d[2], wertung = d[3], ich = d[4] }
        end
    else
        liste = wertungListe()
    end

    local platz
    for i, e in ipairs(liste) do
        if e.ich or (not vorschau and Kern.GleicherSpieler(e.name, ich)) then platz = i end
    end
    local n = math.min(#liste, MAXZEILEN)
    versatz = math.max(0, math.min(versatz, math.max(0, #liste - MAXZEILEN)))
    for i = 1, n do
        local e = liste[i + versatz]
        local istIch = e.ich or (not vorschau and Kern.GleicherSpieler(e.name, ich))
        zeile(i, farbName(e.name, e.klasse), nil, GELB .. zahlText(e.wertung or e.haupt or 0) .. "|r",
            istIch and "ich" or ((i + versatz) == 1 and "dran" or nil))
    end
    zeilenAus(n + 1)

    local text
    if vorschau then
        text = L["Vorschau mit Beispieldaten"]
    elseif #liste == 0 then
        text = L["Niemand in der Liste"]
    elseif platz then
        text = string.format(L["Du: Wertung %s · Platz %d von %d"],
            zahlText(liste[platz].wertung or liste[platz].haupt or 0), platz, #liste)
    else
        text = string.format(L["%d Spieler"], #liste)
    end
    fuss:SetText(GRAU .. text .. "|r")
    rahmen:SetHeight(WERTUNG_OBEN + math.max(n, 1) * ZEILE + unten())

    local erster = liste[1]
    if not erster then return nil end
    return farbName(erster.name, erster.klasse) .. " " .. GELB .. zahlText(erster.wertung or erster.haupt or 0) .. "|r"
end

--- Der Wurf: Gegenstand, Restzeit, die Wuerfe in der Reihenfolge der Uebersicht.
local function zeigeWurf(W, liste)
    setzeBasis(WURF_OBEN)
    itemText:SetText(W.link)
    local rest = math.max(0, W.ende - time())
    local anteil = W.dauer > 0 and (rest / W.dauer) or 0
    balken:SetWidth(math.max(1, (BREITE - 24) * anteil))

    local n = math.min(#liste, MAXZEILEN)
    for i = 1, n do
        local e = liste[i]
        local art = (e.art == "haupt") and L["Haupt"] or L["Zweit"]
        zeile(i, farbName(e.name, e.klasse), GRAU .. art .. "|r", HELL .. e.wert .. "|r",
            i == 1 and "dran" or ((e.ich or (not vorschau and Kern.GleicherSpieler(e.name, ichName()))) and "ich" or nil))
    end
    zeilenAus(n + 1)
    local text = string.format(L["Gewählt %d von %d · Passt %d"], W.gewaehlt, W.gesamt, W.gepasst) .. " · " .. math.ceil(rest) .. " s"
    if vorschau then text = L["Vorschau mit Beispieldaten"] .. " · " .. math.ceil(rest) .. " s" end
    fuss:SetText(GRAU .. text .. "|r")
    rahmen:SetHeight(WURF_OBEN + math.max(n, 1) * ZEILE + unten())
    return W.link .. " " .. GRAU .. math.ceil(rest) .. " s|r"
end

--- Der Wurf der Vorschau: laeuft 30 Sekunden und beginnt dann von vorn.
local function demoWurf()
    local dauer = 30
    local verstrichen = (time() - vorschauStart) % dauer
    local W = { link = "|cffa335ee[" .. L["Klinge der Verdammnis"] .. "]|r", dauer = dauer, ende = time() + (dauer - verstrichen),
                gewaehlt = 6, gesamt = 10, gepasst = 1 }
    local liste = {}
    for _, d in ipairs(DEMO_WURF) do
        liste[#liste + 1] = { name = d[1], klasse = d[2], art = d[3], wert = d[4], ich = d[5] }
    end
    return W, liste
end

function Kompakt.Aktualisieren()
    if not rahmen or not rahmen:IsShown() then return end
    local leiste = db().leiste and true or false

    local W, liste
    if vorschau == "wurf" then
        W, liste = demoWurf()
    elseif not vorschau and ns.Wurf and ns.Wurf.Laufend then
        W = ns.Wurf.Laufend()
        if W then liste = ns.Wurf.RangListe(W.link) or {} end
    end

    -- ⭐ Wurf starten: wer starten darf (Plündermeister, Leiter, Assistent), ohne das grosse Fenster zu brauchen
    local darfStarten = vorschau ~= nil or (ns.Wurf and ns.Wurf.DarfStarten and ns.Wurf.DarfStarten()) and true or false
    startBtn:SetShown(not leiste and W == nil and darfStarten)

    itemText:SetShown(W ~= nil and not leiste)
    balkenBahn:SetShown(W ~= nil and not leiste)
    fuss:SetShown(not leiste)
    leisteBtn:SetLabel(leiste and "+" or "–")

    local kopfText
    if W then
        kopfText = zeigeWurf(W, liste)
    else
        kopfText = zeigeWertung()
    end

    if leiste then
        zeilenAus(1)
        rahmen:SetHeight(KOPF)
        titel:SetText(kopfText and ((W and "" or (GRAU .. L["Dran:"] .. "|r ")) .. kopfText) or "KaosLoot")
    else
        titel:SetText("KaosLoot")
    end
end

-- =====================================================================
--  Aufbau
-- =====================================================================

local function bauen()
    if rahmen then return end

    rahmen = CreateFrame("Frame", "FairshareKompakt", UIParent)
    rahmen:SetSize(BREITE, 140)
    rahmen:SetFrameStrata("DIALOG")
    rahmen:SetFrameLevel(10)
    rahmen:SetClampedToScreen(true)
    rahmen:SetMovable(true)
    rahmen:EnableMouse(true)
    S.Kasten(rahmen, 8, C.bg, C.ln)

    FairshareDB = FairshareDB or {}
    FairshareDB.fenster = FairshareDB.fenster or {}
    local st = FairshareDB.fenster.kompakt
    rahmen:ClearAllPoints()
    if st and st.x and st.y then
        rahmen:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", st.x, st.y)
    else
        rahmen:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -220)
    end

    -- Kopf: ziehen, Titel, Gross / Klein / Zu
    local k = CreateFrame("Frame", nil, rahmen)
    k:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 1, -1)
    k:SetPoint("TOPRIGHT", rahmen, "TOPRIGHT", -1, -1)
    k:SetHeight(KOPF - 2)
    k:EnableMouse(true)
    k:RegisterForDrag("LeftButton")
    k:SetScript("OnDragStart", function() rahmen:StartMoving() end)
    k:SetScript("OnDragStop", function()
        rahmen:StopMovingOrSizing()
        lageSpeichern()
    end)

    local logo = CreateFrame("Frame", nil, k)
    logo:SetSize(16, 16)
    logo:SetPoint("LEFT", k, "LEFT", 8, 0)
    S.Form(logo, 4, C.ac)
    local lt = S.Text(logo, 10, C.white, "CENTER")
    lt:SetPoint("CENTER", 1, 0)
    lt:SetText("F")

    local zu = CreateFrame("Button", nil, k)
    zu:SetSize(18, 18)
    zu:SetPoint("RIGHT", k, "RIGHT", -6, 0)
    local x = S.Symbol(zu, "x.tga", 14, C.mu)
    x:SetPoint("CENTER")
    zu:SetScript("OnEnter", function() S.Faerbe(x, C.tx) end)
    zu:SetScript("OnLeave", function() S.Faerbe(x, C.mu) end)
    zu:SetScript("OnClick", function() Kompakt.Verstecken() end)

    local gross = S.Knopf(k, L["Groß"], "link", 18)
    gross:SetPoint("RIGHT", zu, "LEFT", -4, 0)
    gross:SetScript("OnClick", function()
        if ns.Fenster then ns.Fenster.Zeigen(false) end        -- schliesst dieses Fenster
    end)

    leisteBtn = S.Knopf(k, "–", "link", 18)
    leisteBtn:SetFest(18)
    leisteBtn:SetPoint("RIGHT", gross, "LEFT", 0, 0)
    leisteBtn:SetScript("OnClick", function()
        db().leiste = not db().leiste
        Kompakt.Aktualisieren()
    end)

    titel = S.Text(k, 12, C.tx, "LEFT")
    titel:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    titel:SetPoint("RIGHT", leisteBtn, "LEFT", -4, 0)
    titel:SetWordWrap(false)

    -- Wurf starten (nur wer darf): unter den Zeilen, ueber der Fusszeile
    startBtn = S.Knopf(rahmen, L["Wurf starten"], "primary", 24)
    startBtn:SetPoint("BOTTOMLEFT", rahmen, "BOTTOMLEFT", 10, 28)
    startBtn:SetPoint("BOTTOMRIGHT", rahmen, "BOTTOMRIGHT", -10, 28)
    startBtn:SetScript("OnClick", function()
        if ns.Wurf then ns.Wurf.Dialog() end
    end)
    startBtn:Hide()

    -- Wurf: Gegenstand und Zeitbalken oberhalb der Zeilen
    itemText = S.Text(rahmen, 12, C.tx, "LEFT")
    itemText:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 12, -(KOPF + 6))
    itemText:SetPoint("RIGHT", rahmen, "RIGHT", -12, 0)
    itemText:SetWordWrap(false)
    balkenBahn = CreateFrame("Frame", nil, rahmen)
    balkenBahn:SetSize(BREITE - 24, 4)
    balkenBahn:SetPoint("TOPLEFT", rahmen, "TOPLEFT", 12, -(KOPF + 24))
    S.Form(balkenBahn, 2, C.p2)
    balken = CreateFrame("Frame", nil, balkenBahn)
    balken:SetHeight(4)
    balken:SetPoint("LEFT", balkenBahn, "LEFT", 0, 0)
    S.Form(balken, 2, C.ac)

    -- Zeilen
    zeilen = {}
    for i = 1, MAXZEILEN do
        local z = CreateFrame("Frame", nil, rahmen)
        z:SetHeight(ZEILE)
        z.dran = S.Form(z, 4, C.acb)
        z.markiert = S.Form(z, 4, C.hover)
        z.a = S.Text(z, 12, C.tx, "LEFT")
        z.a:SetPoint("LEFT", z, "LEFT", 6, 0)
        z.a:SetWidth(112)
        z.a:SetWordWrap(false)
        z.b = S.Text(z, 11, C.mu, "LEFT")
        z.b:SetPoint("LEFT", z.a, "RIGHT", 2, 0)
        z.b:SetWidth(40)
        z.c = S.Text(z, 12, C.tx, "RIGHT")
        z.c:SetPoint("RIGHT", z, "RIGHT", -6, 0)
        z.c:SetPoint("LEFT", z.b, "RIGHT", 2, 0)
        z.c:SetWordWrap(false)
        z:Hide()
        zeilen[i] = z
    end
    setzeBasis(WERTUNG_OBEN)

    fuss = S.Text(rahmen, 11, C.mu, "LEFT")
    fuss:SetPoint("BOTTOMLEFT", rahmen, "BOTTOMLEFT", 12, 8)
    fuss:SetPoint("BOTTOMRIGHT", rahmen, "BOTTOMRIGHT", -12, 8)
    fuss:SetWordWrap(false)

    rahmen:EnableMouseWheel(true)
    rahmen:SetScript("OnMouseWheel", function(_, richtung)
        versatz = math.max(0, versatz - richtung)
        Kompakt.Aktualisieren()
    end)

    -- Ein ruhiger Takt genuegt: Restzeit, neue Wuerfe, Wertungen
    local zeit = 0
    rahmen:SetScript("OnUpdate", function(_, dt)
        zeit = zeit + dt
        if zeit < TAKT then return end
        zeit = 0
        local ok = pcall(Kompakt.Aktualisieren)
        if not ok then rahmen:SetScript("OnUpdate", nil) end      -- bei einem Fehler nicht jeden Takt wiederholen
    end)

    rahmen:SetScript("OnShow", function() Kompakt.Aktualisieren() end)
    rahmen:Hide()
end

-- =====================================================================
--  Zugriff
-- =====================================================================

--- Zeigt das kleine Fenster und schliesst dafuer das grosse.
function Kompakt.Zeigen()
    bauen()
    if ns.Fenster and ns.Fenster.Sichtbar() then ns.Fenster.Verstecken() end
    db().offen = true
    rahmen:Show()
    Kompakt.Aktualisieren()
end

function Kompakt.Verstecken()
    db().offen = false
    vorschau = nil
    if rahmen then rahmen:Hide() end
end

function Kompakt.Umschalten()
    if rahmen and rahmen:IsShown() then
        Kompakt.Verstecken()
    else
        Kompakt.Zeigen()
    end
end

function Kompakt.Sichtbar()
    return rahmen and rahmen:IsShown() and true or false
end

--- Die Vorschau mit Beispieldaten: aus -> Wertung -> Wurf -> aus. Ohne Gruppe und ohne Wurf pruefbar.
--  @return der neue Zustand: "wertung", "wurf" oder nil
function Kompakt.Vorschau()
    if vorschau == nil then
        vorschau = "wertung"
        vorschauStart = time()
        Kompakt.Zeigen()
    elseif vorschau == "wertung" then
        vorschau = "wurf"
        vorschauStart = time()
        Kompakt.Aktualisieren()
    else
        vorschau = nil
        Kompakt.Aktualisieren()
    end
    return vorschau
end

-- Nach dem Anmelden wieder zeigen, wenn es offen war.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if C_Timer then
            C_Timer.After(3, function()
                if FairshareDB and FairshareDB.kompakt and FairshareDB.kompakt.offen then pcall(Kompakt.Zeigen) end
            end)
        end
    end)
end

return ns
