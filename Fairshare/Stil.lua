--[[----------------------------------------------------------------------
    Stil.lua  —  Bausteine im Look von KaosUI

    Dunkle, flache Flaechen, Petrol als Akzent, Inter als Schrift, runde
    Ecken ohne Grafikdatei. Dasselbe Aussehen wie das Optionsfenster von
    KaosUI, aber **ohne Abhaengigkeit zu KaosUI**: Die Bausteine sind hier
    neu geschrieben, damit Fairshare allein funktioniert.

    ⚠️ Nur eigene Frames, keine Blizzard-Vorlagen (kein UIDropDownMenu,
    kein UIPanelButtonTemplate) — ein Teil weniger, das beim naechsten
    Patch bricht, und es sieht ueberall gleich aus.

    ⚠️ Runde Ecken: drei Streifen plus vier Viertelkreise, die eine
    Kreis-Maske bekommen. Fehlt `CreateMaskTexture`, bleiben die Ecken eckig
    — es sieht dann schlichter aus, funktioniert aber.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Stil = {}
ns.Stil = Stil

local WHITE  = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\Masks\\CircleMaskScalable"
local MEDIA  = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local SCHRIFT = MEDIA .. "Fonts\\Inter-Medium.ttf"

-- WoW rendert Schrift ohne die Kantenschaerfung eines Browsers; Inter wirkt
-- im Spiel duenn. Darum Medium und einen Punkt groesser (Erfahrung KaosUI).
local GROESSE_PLUS = 1

-- Die Schrift beim Laden einmal anfassen: eine Schriftdatei, die der
-- Client noch nie geladen hat, zeigt beim ersten SetFont sonst leeren Text.
do
    local halter = CreateFrame("Frame")
    halter:Hide()
    local fs = halter:CreateFontString(nil, "OVERLAY")
    fs:SetFont(SCHRIFT, 13, "")
    fs:SetText("Fairshare äöü")
end

-- =====================================================================
--  Farben (wie KaosUI; Petrol #1f8f80 ist der Akzent)
-- =====================================================================

local function hex(h, a)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255,
             tonumber(h:sub(5, 6), 16) / 255, a or 1 }
end

local C = {
    bg      = hex("101314"),   -- Fenster, Seitenleiste, Inhalt
    p1      = hex("161a1c"),   -- Kopf, Fuss, Karten
    p2      = hex("1c2123"),   -- Felder, Segmentwahl
    ln      = hex("2a3235"),   -- Linien und Raender
    hover   = hex("232a2c"),
    tx      = hex("e4ebe8"),
    mu      = hex("a3aeaa"),   -- Erklaertexte
    dim     = hex("5c6764"),
    ac      = hex("1f8f80"),
    ach     = hex("26a896"),
    acb     = hex("122725"),   -- Petrol, 16 % ueber bg
    badge   = hex("7fd6c8"),
    tgOff   = hex("333b3e"),
    knobOff = hex("cfd8d5"),
    track   = hex("2d3133"),
    white   = hex("ffffff"),
    warn    = hex("e6a633"),
    warnBg  = hex("2a2418"),
    ok      = hex("7fd69a"),
    bad     = hex("e67e7e"),
}
Stil.C = C

--- Farbe als Textcode, fuer |cff...|r in Zeichenketten.
function Stil.Code(c)
    return string.format("|cff%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- =====================================================================
--  Grundbausteine
-- =====================================================================

local function Tex(eltern, ebene, c, a, unter)
    local t = eltern:CreateTexture(nil, ebene or "BACKGROUND", nil, unter or 0)
    t:SetTexture(WHITE)
    t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
    return t
end
Stil.Tex = Tex

local function Faerbe(t, c, a)
    t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
end
Stil.Faerbe = Faerbe

local function Schrift(fs, groesse)
    local px = (groesse or 12) + GROESSE_PLUS
    local ok = fs:SetFont(SCHRIFT, px, "")
    -- Fehlt die Datei oder laedt sie (noch) nicht, bleibt Blizzards Schrift
    -- in derselben Groesse. `false` ausdruecklich: aeltere Clients liefern nil.
    if ok == false or not fs:GetFont() then
        local pfad = rawget(_G, "STANDARD_TEXT_FONT")
            or (GameFontNormal and GameFontNormal:GetFont())
        if pfad then fs:SetFont(pfad, px, "") end
    end
end
Stil.Schrift = Schrift

-- Alle Textfelder, die dieser Baukasten erzeugt hat (schwach, damit nichts
-- am Leben gehalten wird).
local Texte = setmetatable({}, { __mode = "k" })

local function Text(eltern, groesse, c, ausrichtung, umbruch)
    -- ⭐ Mit Schriftvorlage anlegen, DANN die eigene Schrift setzen (so macht
    -- es KaosUI): Das Feld hat von Anfang an eine geladene Grundschrift,
    -- und der Wechsel auf Inter zeigt nie leeren Text.
    local fs = eltern:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Schrift(fs, groesse)
    Texte[fs] = groesse or 12
    fs:SetJustifyH(ausrichtung or "LEFT")
    fs:SetShadowOffset(0, 0)
    c = c or C.tx
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetWordWrap(umbruch and true or false)
    -- ⚠️ Ein umbrechender Text ohne Breite wird mit Breite 0 gesetzt und
    -- zeichnet dann unter Umstaenden nichts. Darum von Anfang an eine
    -- vernuenftige Breite; das Layout setzt spaeter die richtige.
    if umbruch then fs:SetWidth(300) end
    return fs
end
Stil.Text = Text

--- ⭐ Setzt Schrift und Text aller Textfelder neu.
--
--  Hintergrund (KaosUI, OptionsKit.lua): Eine Schriftdatei, die der Client
--  noch nie geladen hat, zeigt beim ersten Setzen leeren Text, bis der Text
--  NEU gesetzt wird. Gleicher Text allein genuegt nicht — erst leer, dann
--  wieder der Text. Das Layout (Hoehen) bleibt davon unberuehrt.
function Stil.Auffrischen()
    for fs, groesse in pairs(Texte) do
        local t = fs:GetText()
        Schrift(fs, groesse)
        if t and t ~= "" then
            fs:SetText("")
            fs:SetText(t)
        end
    end
end

--- ⭐ Schriftdatei früh laden lassen: Ein unsichtbares Textfeld mit der Schrift in den gebräuchlichen Größen, sobald
--  man angemeldet ist. Der Client lädt eine Schriftdatei erst beim ersten Gebrauch; öffnet man das Fenster zum
--  ersten Mal, ist sie sonst noch nicht da und die Texte bleiben leer (Nutzerfund 18.10.2026: „alles leer, beim
--  zweiten Öffnen kommen die Daten“).
function Stil.SchriftVorladen()
    if Stil.vorgeladen then return end
    Stil.vorgeladen = true
    local eltern = rawget(_G, "UIParent")
    if not (eltern and eltern.CreateFontString) then return end
    local f = CreateFrame("Frame", nil, eltern)
    f:SetSize(1, 1)
    f:SetPoint("BOTTOMLEFT", eltern, "BOTTOMLEFT", 0, 0)
    f:SetAlpha(0.01)
    for _, groesse in ipairs({ 11, 12, 13, 14, 16 }) do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        pcall(function() fs:SetFont(SCHRIFT, groesse + GROESSE_PLUS, "") end)
        fs:SetText("AaBbCc 0123")
        fs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    end
    f:Show()
    Stil.vorladeRahmen = f
end

--- ⭐ Frischt die Texte in einem festen Zeitplan auf (länger als zweimal): Die Schriftdatei lädt beim ersten Öffnen
--  nach dem Anmelden manchmal erst nach Sekunden. Eine Prüfung „wird gezeichnet?“ gibt es nicht — die Breite
--  eines Textes stimmt auch dann, wenn er nicht gezeichnet wird. Nur beim ersten Öffnen je Sitzung.
function Stil.AuffrischenBisFertig()
    if Stil.SchriftFertig then return end
    Stil.SchriftFertig = true
    if not C_Timer then return end
    for _, s in ipairs({ 0.3, 0.8, 1.5, 2.5, 4, 6, 9 }) do
        C_Timer.After(s, function() Stil.Auffrischen() end)
    end
end

function Stil.AnzahlTexte()
    local n = 0
    for _ in pairs(Texte) do n = n + 1 end
    return n
end

function Stil.TextFarbe(fs, c)
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

--- Symbol aus Media/Icons (Tabler Icons, MIT; weiss, wird getoent).
local function Symbol(eltern, name, groesse, c, ebene)
    local t = eltern:CreateTexture(nil, ebene or "ARTWORK")
    t:SetTexture(MEDIA .. "Icons\\" .. name)
    t:SetSize(groesse, groesse)
    Faerbe(t, c or C.mu)
    return t
end
Stil.Symbol = Symbol

local function Maske(rahmen, tex, bezug, groesse)
    if not rahmen.CreateMaskTexture then return end
    local m = rahmen:CreateMaskTexture()
    m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    if groesse then m:SetSize(groesse, groesse) else m:SetAllPoints(bezug or tex) end
    tex:AddMaskTexture(m)
    return m
end

--- Kreisflaeche (Schalterknopf).
function Stil.Rund(rahmen, tex)
    Maske(rahmen, tex)
end

--- Abgerundetes Rechteck ohne Grafikdatei.
--  r = Radius, ecken = nil (alle rund) oder { tl, tr, bl, br }
local function Form(rahmen, r, c, a, ebene, unter, einzug, ecken, bezug)
    einzug, bezug = einzug or 0, bezug or rahmen
    local s = { teile = {} }
    local function add(t) s.teile[#s.teile + 1] = t; return t end
    local function hat(k) return ecken == nil or (ecken[k] and true or false) end

    if r <= 0 then
        local t = add(Tex(rahmen, ebene, c, a, unter))
        t:SetPoint("TOPLEFT", bezug, "TOPLEFT", einzug, -einzug)
        t:SetPoint("BOTTOMRIGHT", bezug, "BOTTOMRIGHT", -einzug, einzug)
    else
        local tl, tr, bl, br = hat("tl"), hat("tr"), hat("bl"), hat("br")

        local mitte = add(Tex(rahmen, ebene, c, a, unter))
        mitte:SetPoint("TOPLEFT", bezug, "TOPLEFT", einzug + r, -einzug)
        mitte:SetPoint("BOTTOMRIGHT", bezug, "BOTTOMRIGHT", -einzug - r, einzug)

        local links = add(Tex(rahmen, ebene, c, a, unter))
        links:SetWidth(r)
        links:SetPoint("TOPLEFT", bezug, "TOPLEFT", einzug, -einzug - (tl and r or 0))
        links:SetPoint("BOTTOMLEFT", bezug, "BOTTOMLEFT", einzug, einzug + (bl and r or 0))

        local rechts = add(Tex(rahmen, ebene, c, a, unter))
        rechts:SetWidth(r)
        rechts:SetPoint("TOPRIGHT", bezug, "TOPRIGHT", -einzug, -einzug - (tr and r or 0))
        rechts:SetPoint("BOTTOMRIGHT", bezug, "BOTTOMRIGHT", -einzug, einzug + (br and r or 0))

        local function ecke(punkt, x, y)
            local t = add(Tex(rahmen, ebene, c, a, unter))
            t:SetSize(r, r)
            t:SetPoint(punkt, bezug, punkt, x, y)
            local m = Maske(rahmen, t, nil, r * 2)
            if m then m:SetPoint(punkt, bezug, punkt, x, y) end
        end
        if tl then ecke("TOPLEFT", einzug, -einzug) end
        if tr then ecke("TOPRIGHT", -einzug, -einzug) end
        if bl then ecke("BOTTOMLEFT", einzug, einzug) end
        if br then ecke("BOTTOMRIGHT", -einzug, einzug) end
    end

    function s:SetColor(c2, a2) for _, t in ipairs(self.teile) do Faerbe(t, c2, a2) end end
    function s:SetShown(an) for _, t in ipairs(self.teile) do t:SetShown(an and true or false) end end
    return s
end
Stil.Form = Form

--- Abgerundete Flaeche mit 1px-Rand.
local function Kasten(rahmen, r, fuell, rand, ebene, unter, ecken)
    ebene, unter = ebene or "BACKGROUND", unter or 0
    local k = {
        rand  = Form(rahmen, r, rand or fuell, nil, ebene, unter, 0, ecken),
        fuell = Form(rahmen, math.max(0, r - 1), fuell, nil, ebene, unter + 1, 1, ecken),
    }
    function k:SetFill(c, a) self.fuell:SetColor(c, a) end
    function k:SetEdge(c, a) self.rand:SetColor(c, a) end
    function k:SetShown(an) self.rand:SetShown(an); self.fuell:SetShown(an) end
    return k
end
Stil.Kasten = Kasten

-- =====================================================================
--  Knoepfe, Eingabe, Auswahl
-- =====================================================================

local function KnopfFarbe(b)
    local an = b:IsEnabled()
    local heiss = b._hover and an
    if b.art == "primary" then
        local c = heiss and C.ach or C.ac
        b.kasten:SetFill(c); b.kasten:SetEdge(c)
        Stil.TextFarbe(b.text, C.white)
    elseif b.art == "link" then
        Stil.TextFarbe(b.text, heiss and C.tx or C.mu)
    else
        b.kasten:SetFill(heiss and C.hover or C.p2)
        b.kasten:SetEdge(C.ln)
        Stil.TextFarbe(b.text, C.tx)
    end
    b:SetAlpha(an and 1 or 0.4)
end

local function KnopfMasse(b)
    local tb = math.ceil(b.text:GetStringWidth())
    local rand = (b.art == "link") and 0 or 12
    local w = b.festeBreite or (tb + rand * 2)
    b:SetWidth(w)
    b.text:ClearAllPoints()
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
end

--- art: "secondary" (Standard) | "primary" (Petrol) | "link" (nur Text)
function Stil.Knopf(eltern, text, art, hoehe)
    local b = CreateFrame("Button", nil, eltern)
    b.art = art or "secondary"
    b:SetHeight(hoehe or 24)
    if b.art ~= "link" then
        local c = (b.art == "primary") and C.ac or C.p2
        b.kasten = Kasten(b, 5, c, (b.art == "primary") and C.ac or C.ln)
    end
    b.text = Text(b, b.art == "link" and 12 or 13, C.tx, "CENTER")
    b:SetScript("OnEnter", function(s) s._hover = true; KnopfFarbe(s) end)
    b:SetScript("OnLeave", function(s) s._hover = false; KnopfFarbe(s) end)

    function b:SetLabel(t)
        self.text:SetText(t or "")
        KnopfMasse(self)
    end
    function b:SetFest(w)
        self.festeBreite = w
        KnopfMasse(self)
    end
    function b:SetAktiv(an)
        self:SetEnabled(an and true or false)
        KnopfFarbe(self)
    end
    --- Aussehen wechseln, z. B. normal -> petrol, wenn etwas auffaellt.
    function b:SetArt(art2)
        if self.art == art2 or not self.kasten then return end
        self.art = art2
        KnopfFarbe(self)
        KnopfMasse(self)
    end

    b:SetLabel(text)
    KnopfFarbe(b)
    return b
end

--- Eingabefeld mit Rand, der beim Tippen petrol wird.
function Stil.Eingabe(eltern, breite, hoehe, groesse)
    local e = CreateFrame("EditBox", nil, eltern)
    e:SetSize(breite, hoehe or 26)
    e:SetAutoFocus(false)
    Schrift(e, groesse or 13)
    e:SetTextColor(C.tx[1], C.tx[2], C.tx[3])
    e:SetTextInsets(8, 8, 0, 0)
    e.kasten = Kasten(e, 5, C.p2, C.ln)
    e:SetScript("OnEditFocusGained", function(s) s.kasten:SetEdge(C.ac) end)
    e:SetScript("OnEditFocusLost", function(s) s.kasten:SetEdge(C.ln) end)
    e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    return e
end

--- Segmentwahl: ein paar Werte nebeneinander, der gewaehlte in Petrol.
function Stil.Segment(eltern, beiWahl)
    local f = CreateFrame("Frame", nil, eltern)
    f:SetHeight(26)
    f.kasten = Kasten(f, 6, C.p2, C.ln)
    f.knoepfe = {}

    function f:SetWerte(werte)
        local x = 3
        for i, w in ipairs(werte or {}) do
            local b = self.knoepfe[i]
            if not b then
                b = CreateFrame("Button", nil, self)
                b:SetHeight(20)
                b.bg = Form(b, 4, C.ac)
                b.text = Text(b, 13, C.mu, "CENTER")
                b.text:SetPoint("CENTER", 0, 0)
                b:SetScript("OnClick", function(s) if beiWahl then beiWahl(s.wert) end end)
                b:SetScript("OnEnter", function(s) if not s.an then Stil.TextFarbe(s.text, C.tx) end end)
                b:SetScript("OnLeave", function(s) if not s.an then Stil.TextFarbe(s.text, C.mu) end end)
                self.knoepfe[i] = b
            end
            b.wert = w.wert
            b.text:SetText(w.label or tostring(w.wert))
            local breite = math.ceil(b.text:GetStringWidth()) + 20
            b:SetWidth(breite)
            b:ClearAllPoints()
            b:SetPoint("LEFT", self, "LEFT", x, 0)
            x = x + breite
            b:Show()
        end
        for i = #(werte or {}) + 1, #self.knoepfe do self.knoepfe[i]:Hide() end
        self:SetWidth(x + 3)
        return x + 3
    end

    function f:SetWahl(wert)
        for _, b in ipairs(self.knoepfe) do
            b.an = b:IsShown() and b.wert == wert
            b.bg:SetShown(b.an)
            Stil.TextFarbe(b.text, b.an and C.white or C.mu)
        end
    end
    return f
end

--- ⭐ Ausklappliste (Entscheid 22.10.2026): ein Knopf zeigt die Wahl, ein Klick klappt die Liste darunter auf.
--  `b:SetOptionen(liste, wahl, beiWahl)`: liste = { { wert, label, farbe }, … }; `b:SetLabel(text)` beschriftet den Knopf.
--  Ein Klick neben die Liste schließt sie.
function Stil.Dropdown(eltern, hoehe)
    local b = Stil.Knopf(eltern, "", "secondary", hoehe or 24)
    local rohLabel = b.SetLabel
    -- Das Pfeilzeichen ▾ fehlt in Inter (im Spiel ein Kästchen): ein kleines „v“ aus zwei gedrehten Strichen zeichnen
    -- und im Text Platz dafür lassen.
    b.SetLabel = function(self, text) rohLabel(self, (text or "") .. "      ") end
    b.pfeil = {}
    for i, grad in ipairs({ -45, 45 }) do
        local arm = Tex(b, "OVERLAY", C.mu)
        arm:SetSize(7, 2)
        arm:SetPoint("RIGHT", b, "RIGHT", i == 1 and -15 or -10, -1)
        if arm.SetRotation then arm:SetRotation(math.rad(grad)) end
        b.pfeil[i] = arm
    end
    b.optionen = {}

    local fang = CreateFrame("Button", nil, UIParent)
    fang:SetFrameStrata("FULLSCREEN_DIALOG")
    fang:SetFrameLevel(290)
    fang:SetAllPoints(UIParent)
    fang:Hide()

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(300)
    menu:Hide()
    menu.kasten = Kasten(menu, 6, C.p1, C.ln)
    menu.eintraege = {}

    local function zu()
        menu:Hide()
        fang:Hide()
    end
    fang:SetScript("OnClick", zu)
    b:SetScript("OnHide", zu)

    function b:SetOptionen(liste, wahl, beiWahl)
        self.optionen = liste or {}
        local breite = math.max(self:GetWidth() or 100, 120)
        for i, o in ipairs(self.optionen) do
            local e = menu.eintraege[i]
            if not e then
                e = CreateFrame("Button", nil, menu)
                e:SetHeight(24)
                e.bg = Form(e, 4, C.hover)
                e.bg:SetShown(false)
                e.text = Text(e, 13, C.tx, "LEFT")
                e.text:SetPoint("LEFT", e, "LEFT", 10, 0)
                e:SetScript("OnEnter", function(s) s.bg:SetShown(true) end)
                e:SetScript("OnLeave", function(s) s.bg:SetShown(s.gewaehlt and true or false) end)
                menu.eintraege[i] = e
            end
            e.wert = o.wert
            e.gewaehlt = (o.wert == wahl)
            e.bg:SetShown(e.gewaehlt)
            e.text:SetText((o.farbe or "") .. (o.label or tostring(o.wert)) .. (o.farbe and "|r" or ""))
            breite = math.max(breite, math.ceil(e.text:GetStringWidth()) + 28)
            e:SetScript("OnClick", function(s)
                zu()
                if beiWahl then beiWahl(s.wert) end
            end)
        end
        for i = #self.optionen + 1, #menu.eintraege do menu.eintraege[i]:Hide() end
        for i = 1, #self.optionen do
            local e = menu.eintraege[i]
            e:SetWidth(breite - 8)
            e:ClearAllPoints()
            e:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 24)
            e:Show()
        end
        menu:SetSize(breite, 8 + #self.optionen * 24)
    end

    b:SetScript("OnClick", function(self)
        if menu:IsShown() then zu() return end
        if #self.optionen == 0 then return end
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
        fang:Show()
        menu:Show()
    end)
    b.Schliessen = zu
    return b
end

--- Schalter 32x18 (statt Kontrollkaestchen).
function Stil.Schalter(eltern)
    local b = CreateFrame("Button", nil, eltern)
    b:SetSize(32, 18)
    local bahn = Form(b, 9, C.tgOff, nil, "ARTWORK")
    local knopf = Tex(b, "OVERLAY", C.knobOff)
    knopf:SetSize(14, 14)
    Stil.Rund(b, knopf)

    function b:SetAn(an)
        self.an = an and true or false
        bahn:SetColor(self.an and C.ac or C.tgOff)
        Faerbe(knopf, self.an and C.white or C.knobOff)
        knopf:ClearAllPoints()
        knopf:SetPoint("LEFT", b, "LEFT", self.an and 16 or 2, 0)
    end
    b:SetAn(false)
    return b
end

-- =====================================================================
--  Verstellbare Fenster: Groesse und Lage merken, Griff unten rechts
-- =====================================================================

local function begrenze(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Macht ein Fenster in der Groesse verstellbar und merkt Groesse und Lage.
--
--  ⭐ Der Anker ist OBEN LINKS an UIParent, nie die Mitte: Bei einem
--  Mittenanker waechst ein Fenster beim Ziehen nach beiden Seiten und
--  springt. (Erfahrung KaosUI.)
--
--  @param schluessel  Name der Ablage in FairshareDB.fenster
--  @param m           { b, h, minB, minH, maxB, maxH, dx, dy }  Vorgabe und Grenzen
--  @param beiAenderung  wird bei jeder Groessenaenderung gerufen
function Stil.Verstellbar(win, schluessel, m, beiAenderung)
    FairshareDB = FairshareDB or {}
    FairshareDB.fenster = FairshareDB.fenster or {}
    local st = FairshareDB.fenster[schluessel] or {}
    FairshareDB.fenster[schluessel] = st

    local b = begrenze(st.b or m.b, m.minB, m.maxB)
    local h = begrenze(st.h or m.h, m.minH, m.maxH)
    win:SetSize(b, h)

    win:ClearAllPoints()
    if st.x and st.y then
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", st.x, st.y)
    else
        local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            math.floor((uw - b) / 2 + (m.dx or 0) + 0.5), math.floor((uh + h) / 2 + (m.dy or 0) + 0.5))
    end

    win:SetResizable(true)
    if win.SetResizeBounds then
        win:SetResizeBounds(m.minB, m.minH, m.maxB, m.maxH)
    elseif win.SetMinResize then
        win:SetMinResize(m.minB, m.minH)
        if win.SetMaxResize then win:SetMaxResize(m.maxB, m.maxH) end
    end

    function win.speichern()
        local l, t = win:GetLeft(), win:GetTop()
        st.b, st.h = math.floor(win:GetWidth() + 0.5), math.floor(win:GetHeight() + 0.5)
        if type(l) == "number" and type(t) == "number" then st.x, st.y = l, t end
    end

    -- Der Griff: drei Reihen kleiner Punkte in der Ecke
    local griff = CreateFrame("Button", nil, win)
    griff:SetSize(16, 16)
    griff:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -3, 3)
    griff:SetFrameLevel(win:GetFrameLevel() + 20)
    griff.punkte = {}
    for reihe = 0, 2 do
        for spalte = 0, 2 - reihe do
            local p = Tex(griff, "OVERLAY", C.dim)
            p:SetSize(2, 2)
            p:SetPoint("BOTTOMRIGHT", griff, "BOTTOMRIGHT", -(spalte * 4) - 2, reihe * 4 + 2)
            griff.punkte[#griff.punkte + 1] = p
        end
    end
    local function farbe(c) for _, p in ipairs(griff.punkte) do Stil.Faerbe(p, c) end end
    griff:SetScript("OnEnter", function() farbe(C.mu) end)
    griff:SetScript("OnLeave", function() farbe(C.dim) end)
    griff:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    griff:SetScript("OnMouseUp", function()
        win:StopMovingOrSizing()
        win.speichern()
    end)

    win:SetScript("OnSizeChanged", function()
        if beiAenderung then beiAenderung() end
    end)
    return griff
end

-- =====================================================================
--  Bildlauf: Mausrad plus ein schmaler Balken, keine Blizzard-Vorlage
-- =====================================================================

function Stil.Bildlauf(eltern, schritt)
    schritt = schritt or 40
    local sf = CreateFrame("ScrollFrame", nil, eltern)
    local kind = CreateFrame("Frame", nil, sf)
    kind:SetSize(1, 1)
    sf:SetScrollChild(kind)
    sf.kind = kind

    local balken = CreateFrame("Frame", nil, eltern)
    balken:SetWidth(4)
    balken:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0)
    balken:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
    balken:Hide()

    local function balkenZeichnen()
        local max = sf:GetVerticalScrollRange() or 0
        if max <= 1 then balken:Hide() return end
        balken:Show()
        local h = balken:GetHeight()
        local sicht = sf:GetHeight()
        local gesamt = sicht + max
        local dh = math.max(24, h * sicht / gesamt)
        local oben = (h - dh) * (sf:GetVerticalScroll() / max)
        if not balken.streifen then
            balken.streifen = Tex(balken, "ARTWORK", C.ln)
            balken.streifen:SetWidth(4)
        end
        balken.streifen:ClearAllPoints()
        balken.streifen:SetPoint("TOPLEFT", balken, "TOPLEFT", 0, -oben)
        balken.streifen:SetHeight(dh)
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(s, richtung)
        local max = s:GetVerticalScrollRange() or 0
        local neu = math.max(0, math.min(max, s:GetVerticalScroll() - richtung * schritt))
        s:SetVerticalScroll(neu)
        balkenZeichnen()
    end)
    sf:SetScript("OnSizeChanged", function(s, w)
        if w and w > 0 then kind:SetWidth(w - 10) end
        balkenZeichnen()
        if s.beiGroesse then s.beiGroesse() end
    end)
    sf:SetScript("OnScrollRangeChanged", balkenZeichnen)

    function sf:SetInhaltHoehe(h)
        kind:SetHeight(math.max(1, h))
        balkenZeichnen()
    end
    function sf:Zurueck()
        self:SetVerticalScroll(0)
        balkenZeichnen()
    end
    return sf
end

-- Beim Anmelden die Schrift schon laden lassen (siehe Stil.SchriftVorladen)
local vorlader = CreateFrame("Frame")
vorlader:RegisterEvent("PLAYER_ENTERING_WORLD")
vorlader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    pcall(Stil.SchriftVorladen)
end)

return ns
