--[[----------------------------------------------------------------------
    Wurf.lua  —  Eigenes Wuerfelfenster: Haupt (1-100) oder Zweit (1-50)

    ⭐ Warum es das gibt (Nutzer, 14.10.2026): Gargul ist in der Beta noch
    verbuggt. Fairshare bietet deshalb selbst an, was die Gilde braucht:

      1. Der Pluendermeister (Leiter, Assistent) startet einen Wurf fuer einen
         Gegenstand: `/fs wurf <Link>`, der Knopf *Wurf starten* oder
         die Beute im offenen Beutefenster anklicken.
      2. Bei ALLEN in der Gruppe mit Fairshare geht ein kleines Fenster auf:
         Gegenstand, Restzeit, Knoepfe **Haupt (1-100)**, **Zweit (1-50)**,
         **Passen**.
      3. Ein Klick wuerfelt (`RandomRoll`) im richtigen Bereich. Die Zahl
         wuerfelt der Server; sie kommt wie jeder Wurf als Systemmeldung
         an und wird in Erfassung.lua gelesen. Das Addon sendet also keine
         Wurfergebnisse — dadurch laesst sich nichts faelschen.
      4. Die Uebersicht (Fenster.lua) zeigt die Wuerfe: Haupt vor Zweit,
         dann die wenigsten Stuecke zuerst. Es zaehlt der ERSTE Wurf.

    Nachrichten (Praefix FSHARE, ueber Abgleich.Senden):
        S;<Kennung>;<Sekunden>;<Gegenstandslink>   Wurf beginnt
        X;<Kennung>                                Wurf endet (vorzeitig)
    Beide nur von Pluendermeister/Leiter/Assistent, nur aus der eigenen
    Gruppe und Gilde (Abgleich.Empfangen prueft das vorher).

    ⚠️ Die Wuerfe selbst ordnet Erfassung.Systemmeldung dem Gegenstand zu:
    Solange ein Wurf aktiv ist (und kurz danach), gilt jeder Bedarfswurf
    in der Gruppe diesem Gegenstand — auch der von Spielern ohne Addon,
    die einfach `/roll 1-100` tippen.
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Wurf = {}
ns.Wurf = Wurf

local Kern = ns.Kern
local S = ns.Stil
local C = S.C

local GELB   = S.Code(C.warn)
local GRAU   = S.Code(C.mu)
local HELL   = S.Code(C.white)
local ROT    = S.Code(C.bad)

local PRAEFIX = "|cff1B6B57Fairshare|r: "
local STANDARDDAUER = 30
local NACHLAUF = 6        -- Sekunden nach dem Ende, in denen ein spaeter Wurf noch zaehlt
local BAHN = 288          -- Breite des Zeitbalkens

local aktiv = nil         -- { rid, link, dauer, ende, meine, wert }
local nachlauf = nil      -- { link, bis }
local popup, starter

-- =====================================================================
--  Hilfen
-- =====================================================================

local function db() return ns.Erfassung.Einstellungen() end

local function ichName()
    if GetUnitName then
        local n = GetUnitName("player", true)
        if n and n ~= "" then return n end
    end
    return (UnitName("player"))
end

local function sag(text) print(PRAEFIX .. text) end

--- Den ersten Gegenstandslink aus einem Text holen.
local function linkAus(text)
    if type(text) ~= "string" then return nil end
    return text:match("(|c%x+|Hitem:[^|]+|h%[[^%]]*%]|h|r)")
end

--- Wie lange ein Wurf dauert (Einstellung, 10 bis 120 Sekunden).
function Wurf.Dauer()
    local d = tonumber(db().wurfDauer) or STANDARDDAUER
    return math.max(10, math.min(120, d))
end

--- Darf dieser Spieler einen Wurf starten?
function Wurf.DarfStarten()
    if not (IsInGroup and IsInGroup()) then return false end
    return ns.Rolle.Berechtigt(ichName()) and true or false
end

--- Zu welchem Gegenstand gehoert ein Wurf, der jetzt eintrifft?
--  @return Link oder nil (kein Wurf aktiv)
function Wurf.AktuellerLink()
    if aktiv then return aktiv.link end
    if nachlauf and time() <= nachlauf.bis then return nachlauf.link end
    return nil
end

function Wurf.Aktiv()
    return aktiv ~= nil
end

-- =====================================================================
--  Kopfleiste (fuer beide Fenster)
-- =====================================================================

--- Dunkle Kopfleiste mit Logo, Titel, Ziehen und Schliessen-Kreuz.
local function kopfLeiste(f, titel, speichernSchluessel, beiZu)
    local k = CreateFrame("Frame", nil, f)
    k:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    k:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    k:SetHeight(32)
    S.Form(k, 9, C.p1, nil, "BACKGROUND", 0, 0, { tl = true, tr = true })
    local linie = S.Tex(k, "BORDER", C.ln)
    linie:SetHeight(1)
    linie:SetPoint("BOTTOMLEFT")
    linie:SetPoint("BOTTOMRIGHT")

    k:EnableMouse(true)
    k:RegisterForDrag("LeftButton")
    k:SetScript("OnDragStart", function() f:StartMoving() end)
    k:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local l, t = f:GetLeft(), f:GetTop()
        if type(l) == "number" and type(t) == "number" then
            FairshareDB.fenster = FairshareDB.fenster or {}
            FairshareDB.fenster[speichernSchluessel] = { x = l, y = t }
        end
    end)

    local logo = CreateFrame("Frame", nil, k)
    logo:SetSize(18, 18)
    logo:SetPoint("LEFT", k, "LEFT", 12, 0)
    S.Form(logo, 4, C.ac)
    local l = S.Text(logo, 11, C.white, "CENTER")
    l:SetPoint("CENTER", 1, 0)
    l:SetText("F")

    local t = S.Text(k, 13, C.tx, "LEFT")
    t:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    t:SetText(titel)

    local zu = CreateFrame("Button", nil, k)
    zu:SetSize(20, 20)
    zu:SetPoint("RIGHT", k, "RIGHT", -10, 0)
    local x = S.Symbol(zu, "x.tga", 16, C.mu)
    x:SetPoint("CENTER")
    zu:SetScript("OnEnter", function() S.Faerbe(x, C.tx) end)
    zu:SetScript("OnLeave", function() S.Faerbe(x, C.mu) end)
    zu:SetScript("OnClick", beiZu)
    return k, zu
end

--- Lage aus den Einstellungen, sonst ein Standard.
local function lageSetzen(f, schluessel, standard)
    FairshareDB.fenster = FairshareDB.fenster or {}
    local st = FairshareDB.fenster[schluessel]
    f:ClearAllPoints()
    if st and st.x and st.y then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", st.x, st.y)
    else
        f:SetPoint(standard[1], UIParent, standard[1], standard[2], standard[3])
    end
end

-- =====================================================================
--  Das Wuerfelfenster der Spieler
-- =====================================================================

local popupAktualisieren

--- Ein Spieler waehlt. „pass" wuerfelt nicht.
local function waehlen(art)
    if not aktiv or aktiv.meine then return end
    aktiv.meine = art

    if art ~= "pass" then
        local max = (art == "haupt") and 100 or 50
        local f = rawget(_G, "RandomRoll")
        local ok = false
        if type(f) == "function" then ok = pcall(f, 1, max) end
        if not ok then
            -- Ohne RandomRoll bleibt nur der Handgriff.
            aktiv.meine = nil
            sag(ROT .. string.format(L["Würfeln nicht möglich – bitte |cffffff78/roll 1-%d|r eingeben."], max) .. "|r")
        end
    end
    popupAktualisieren()
end

local function popupBauen()
    if popup then return end
    local p = CreateFrame("Frame", "FairshareWurf", UIParent)
    popup = p
    p:SetSize(320, 168)
    p:SetFrameStrata("DIALOG")
    p:SetFrameLevel(60)
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    S.Kasten(p, 10, C.bg, C.ln)

    local _, zu = kopfLeiste(p, "Fairshare  " .. GRAU .. L["Wurf"] .. "|r", "wurf", function()
        -- Das Kreuz heisst: nicht mitwuerfeln.
        if aktiv and not aktiv.meine then aktiv.meine = "pass" end
        p:Hide()
    end)

    p.beenden = S.Knopf(p, L["Beenden"], "link", 22)
    p.beenden:SetPoint("RIGHT", zu, "LEFT", -6, 0)
    p.beenden:SetFrameLevel(p:GetFrameLevel() + 5)
    p.beenden:SetScript("OnClick", function() Wurf.BeendenAlle() end)

    -- Gegenstand (mit Tooltip)
    local item = CreateFrame("Button", nil, p)
    item:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -44)
    item:SetSize(BAHN, 22)
    p.itemText = S.Text(item, 14, C.tx, "LEFT")
    p.itemText:SetPoint("LEFT", item, "LEFT", 0, 0)
    p.itemText:SetWidth(BAHN)
    item:SetScript("OnEnter", function(s)
        if aktiv and GameTooltip and GameTooltip.SetHyperlink then
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            pcall(GameTooltip.SetHyperlink, GameTooltip, aktiv.link)
            GameTooltip:Show()
        end
    end)
    item:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    -- Zeitbalken
    p.bahn = S.Tex(p, "ARTWORK", C.track)
    p.bahn:SetSize(BAHN, 6)
    p.bahn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -76)
    p.balken = S.Tex(p, "OVERLAY", C.ac)
    p.balken:SetHeight(6)
    p.balken:SetPoint("TOPLEFT", p.bahn, "TOPLEFT", 0, 0)
    p.balken:SetWidth(BAHN)

    p.status = S.Text(p, 12, C.mu, "LEFT")
    p.status:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -90)
    p.status:SetWidth(BAHN - 50)
    p.rest = S.Text(p, 12, C.mu, "RIGHT")
    p.rest:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -90)
    p.rest:SetWidth(48)

    -- Die drei Knoepfe
    p.haupt = S.Knopf(p, L["Haupt (1-100)"], "primary", 30)
    p.haupt:SetFest(124)
    p.haupt:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 16, 16)
    p.haupt:SetScript("OnClick", function() waehlen("haupt") end)

    p.zweit = S.Knopf(p, L["Zweit (1-50)"], "secondary", 30)
    p.zweit:SetFest(104)
    p.zweit:SetPoint("LEFT", p.haupt, "RIGHT", 6, 0)
    p.zweit:SetScript("OnClick", function() waehlen("zweit") end)

    p.passen = S.Knopf(p, L["Passen"], "secondary", 30)
    p.passen:SetFest(46 + 6)
    p.passen:SetPoint("LEFT", p.zweit, "RIGHT", 6, 0)
    p.passen:SetScript("OnClick", function() waehlen("pass") end)

    p:SetScript("OnUpdate", function(s, dt)
        s.t = (s.t or 0) + dt
        if s.t < 0.2 then return end
        s.t = 0
        if not aktiv then return end
        if time() >= aktiv.ende then
            Wurf.Ende()
        else
            popupAktualisieren()
        end
    end)
    p:Hide()
end

popupAktualisieren = function()
    if not popup or not aktiv then return end
    popup.itemText:SetText(aktiv.link)

    local rest = math.max(0, aktiv.ende - time())
    popup.rest:SetText(math.ceil(rest) .. " s")
    local anteil = aktiv.dauer > 0 and (rest / aktiv.dauer) or 0
    popup.balken:SetWidth(math.max(1, BAHN * anteil))

    -- Hat man schon gewuerfelt (hier oder per /roll), steht es im Fenster.
    local wert, art = ns.Erfassung.WurfVon(ichName(), aktiv.link)
    if wert and wert > 0 then
        aktiv.meine = aktiv.meine or art
        aktiv.wert = wert
    end

    local m = aktiv.meine
    local text
    if not m then
        text = GELB .. L["Wähle deinen Bedarf"] .. "|r"
    elseif m == "pass" then
        text = GRAU .. L["Du passt."] .. "|r"
    elseif aktiv.wert then
        text = string.format(L["Du hast %s gewürfelt (%s)"], HELL .. aktiv.wert .. "|r",
            m == "haupt" and L["Haupt"] or L["Zweit"])
    else
        text = GRAU .. L["Würfelt …"] .. "|r"
    end
    popup.status:SetText(text)

    local frei = not m
    popup.haupt:SetAktiv(frei)
    popup.zweit:SetAktiv(frei)
    popup.passen:SetAktiv(frei)
    popup.beenden:SetShown(Wurf.DarfStarten())
end

-- =====================================================================
--  Ablauf
-- =====================================================================

local function beginnen(rid, link, dauer)
    aktiv = { rid = rid, link = link, dauer = dauer, ende = time() + dauer }
    nachlauf = nil

    -- Die Uebersicht oeffnet sich nur bei dem, der den Wurf leitet.
    ns.Erfassung.WurfBeginnt(link, Wurf.DarfStarten())

    popupBauen()
    lageSetzen(popup, "wurf", { "TOP", 0, -180 })
    popup:Show()
    popupAktualisieren()
end

--- Der Wurf ist vorbei (Zeit, Abbruch oder Meldung des Leiters).
function Wurf.Ende()
    if not aktiv then return end
    nachlauf = { link = aktiv.link, bis = time() + NACHLAUF }
    aktiv = nil
    if popup then popup:Hide() end
    if ns.Fenster then ns.Fenster.Aktualisieren() end
end

--- Startet einen Wurf fuer den Gegenstand im Text.
--  @return true, oder false und ein Grund
function Wurf.Starten(eingabe)
    if not (IsInGroup and IsInGroup()) then return false, L["Du bist in keiner Gruppe."] end
    if not ns.Rolle.Berechtigt(ichName()) then
        return false, L["Nur Leiter, Assistenten und der Plündermeister dürfen einen Wurf starten."]
    end
    local link = linkAus(eingabe)
    if not link then
        return false, L["Kein Gegenstand erkannt – den Link mit Shift-Klick einfügen."]
    end

    local dauer = Wurf.Dauer()
    local rid = string.format("%x", (math.random(0x1000, 0xFFFFF) + time()) % 0xFFFFFF)
    if not ns.Abgleich.Senden(string.format("S;%s;%d;%s", rid, dauer, link), true) then
        return false, L["Senden nicht möglich."]
    end
    beginnen(rid, link, dauer)
    return true
end

--- Beendet den laufenden Wurf bei allen.
function Wurf.BeendenAlle()
    if not aktiv then return false, L["Es läuft kein Wurf."] end
    if Wurf.DarfStarten() then
        ns.Abgleich.Senden("X;" .. aktiv.rid, true)
    end
    Wurf.Ende()
    return true
end

--- Eine Nachricht der Gruppe (Abgleich.Empfangen hat Gruppe und Gilde geprueft).
function Wurf.Empfangen(typ, rest, name)
    if type(rest) ~= "string" or not ns.Rolle.Berechtigt(name) then return end

    if typ == "S" then
        local rid, d, text = rest:match("^([^;]*);(%d+);(.*)$")
        local link = linkAus(text)
        d = tonumber(d)
        if not rid or #rid > 12 or not d or not link then return end
        beginnen(rid, link, math.max(5, math.min(120, d)))
    elseif typ == "X" then
        local rid = rest:match("^([^;]*)")
        if aktiv and rid == aktiv.rid then Wurf.Ende() end
    end
end

-- =====================================================================
--  Wurf starten: Dialog
-- =====================================================================

local ZEILEN = 8

--- Die Beute im offenen Beutefenster (nur Gegenstaende mit Link).
local function beuteListe()
    local liste = {}
    local anzahl = rawget(_G, "GetNumLootItems")
    local link = rawget(_G, "GetLootSlotLink")
    if type(anzahl) ~= "function" or type(link) ~= "function" then return liste end
    local ok, n = pcall(anzahl)
    if not ok or type(n) ~= "number" then return liste end
    for i = 1, n do
        local ok2, l = pcall(link, i)
        if ok2 and type(l) == "string" and l ~= "" then liste[#liste + 1] = { platz = i, link = l } end
    end
    return liste
end

local function starterBeute()
    if not starter then return end
    local liste = beuteListe()
    for i = 1, ZEILEN do
        local z = starter.zeilen[i]
        local e = liste[i]
        if e then
            z.link = e.link
            z.text:SetText(e.link)
            z:Show()
        else
            z.link = nil
            z:Hide()
        end
    end
    starter.leer:SetShown(#liste == 0)
end

--- Dauer und Beuteliste neu schreiben (beim Oeffnen und bei Beute-Ereignissen).
local function starterAuffrischen()
    if not starter then return end
    starter.dauer:SetText(string.format(L["Dauer: %d s (Einstellungen)"], Wurf.Dauer()))
    starterBeute()
end

local function starterStarten()
    local ok, grund = Wurf.Starten(starter.eingabe:GetText())
    if ok then
        starter.eingabe:SetText("")
        starter.fehler:SetText("")
        starter:Hide()
    else
        starter.fehler:SetText(ROT .. tostring(grund) .. "|r")
    end
end

local function starterBauen()
    if starter then return end
    local s = CreateFrame("Frame", "FairshareWurfStart", UIParent)
    starter = s
    s:SetSize(360, 342)
    s:SetFrameStrata("DIALOG")
    s:SetFrameLevel(50)
    s:SetClampedToScreen(true)
    s:SetMovable(true)
    s:EnableMouse(true)
    S.Kasten(s, 10, C.bg, C.ln)
    tinsert(UISpecialFrames, "FairshareWurfStart")

    kopfLeiste(s, "Fairshare  " .. GRAU .. L["Wurf starten"] .. "|r", "wurfStart", function() s:Hide() end)

    local t1 = S.Text(s, 12, C.mu, "LEFT")
    t1:SetPoint("TOPLEFT", s, "TOPLEFT", 16, -46)
    t1:SetText(L["Gegenstand"])

    s.eingabe = S.Eingabe(s, 328, 28)
    s.eingabe:SetPoint("TOPLEFT", s, "TOPLEFT", 16, -64)
    s.eingabe:SetMaxLetters(300)
    s.eingabe:SetScript("OnEnterPressed", function(e) e:ClearFocus(); starterStarten() end)

    local hinweis = S.Text(s, 11, C.dim, "LEFT")
    hinweis:SetPoint("TOPLEFT", s, "TOPLEFT", 16, -96)
    hinweis:SetText(L["Shift-Klick auf einen Gegenstand fügt den Link ein."])

    local t2 = S.Text(s, 12, C.mu, "LEFT")
    t2:SetPoint("TOPLEFT", s, "TOPLEFT", 16, -122)
    t2:SetText(L["Beute im Fenster"])

    s.zeilen = {}
    for i = 1, ZEILEN do
        local z = CreateFrame("Button", nil, s)
        z:SetSize(328, 22)
        z:SetPoint("TOPLEFT", s, "TOPLEFT", 16, -142 - (i - 1) * 22)
        z.hover = S.Form(z, 4, C.hover)
        z.hover:SetShown(false)
        z.text = S.Text(z, 13, C.tx, "LEFT")
        z.text:SetPoint("LEFT", z, "LEFT", 6, 0)
        z.text:SetWidth(316)
        z:SetScript("OnEnter", function(x) x.hover:SetShown(true) end)
        z:SetScript("OnLeave", function(x) x.hover:SetShown(false) end)
        z:SetScript("OnClick", function(x)
            if x.link then s.eingabe:SetText(x.link) end
        end)
        z:Hide()
        s.zeilen[i] = z
    end
    s.leer = S.Text(s, 12, C.dim, "LEFT")
    s.leer:SetPoint("TOPLEFT", s, "TOPLEFT", 22, -146)
    s.leer:SetText(L["Kein Beutefenster offen."])

    s.fehler = S.Text(s, 12, C.bad, "LEFT")
    s.fehler:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 16, 52)
    s.fehler:SetWidth(328)

    s.dauer = S.Text(s, 12, C.mu, "LEFT")
    s.dauer:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 16, 24)

    local los = S.Knopf(s, L["Wurf starten"], "primary", 30)
    los:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -16, 16)
    los:SetScript("OnClick", starterStarten)

    s:SetScript("OnShow", function() starterAuffrischen() end)
    s:Hide()
end

--- Den Startdialog oeffnen (ohne Gegenstand).
function Wurf.Dialog()
    if not (IsInGroup and IsInGroup()) then
        sag(ROT .. L["Du bist in keiner Gruppe."] .. "|r")
        return false
    end
    if not Wurf.DarfStarten() then
        sag(ROT .. L["Nur Leiter, Assistenten und der Plündermeister dürfen einen Wurf starten."] .. "|r")
        return false
    end
    starterBauen()
    lageSetzen(starter, "wurfStart", { "CENTER", 0, 60 })
    starter:Show()
    starterAuffrischen()
    return true
end

-- Shift-Klick auf einen Gegenstand fuegt den Link ein, solange das Feld den Fokus hat.
local function linkEinfuegen(text)
    if starter and starter:IsShown() and starter.eingabe:HasFocus() and type(text) == "string" then
        starter.eingabe:Insert(text)
    end
end
if hooksecurefunc then
    pcall(hooksecurefunc, "ChatEdit_InsertLink", linkEinfuegen)
    local CFU = rawget(_G, "ChatFrameUtil")
    if CFU and CFU.InsertLink then pcall(hooksecurefunc, CFU, "InsertLink", linkEinfuegen) end
end

local ereignisse = CreateFrame("Frame")
for _, e in ipairs({ "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED" }) do
    pcall(function() ereignisse:RegisterEvent(e) end)
end
ereignisse:SetScript("OnEvent", function()
    if starter and starter:IsShown() then pcall(starterBeute) end
end)

-- =====================================================================
--  Diagnose: geht die Zuteilung ueber das Beutefenster?
-- =====================================================================

--- ⭐ Fuer Stufe 2 (Item ueber das Addon zuteilen): Was sieht das Addon, solange
--  das Beutefenster offen ist? Nur lesen, es wird nichts zugeteilt.
--  @return Liste von Zeilen
function Wurf.Beutetest()
    local z = {}
    local _, methode = ns.Rolle.Kandidaten()
    z[#z + 1] = string.format(L["  |cff8E9A94Beutemethode: %s|r"], tostring(methode))

    local ml = rawget(_G, "IsMasterLooter")
    local istML = "?"
    if type(ml) == "function" then
        local ok, r = pcall(ml)
        istML = ok and (r and L["ja"] or L["nein"]) or "?"
    end
    z[#z + 1] = string.format(L["  Du bist Plündermeister: %s"], istML)
    z[#z + 1] = string.format(L["  Zuteilen möglich (GiveMasterLoot, GetMasterLootCandidate): %s"],
        (type(rawget(_G, "GiveMasterLoot")) == "function" and type(rawget(_G, "GetMasterLootCandidate")) == "function")
            and L["ja"] or L["nein"])

    local liste = beuteListe()
    if #liste == 0 then
        z[#z + 1] = L["  Kein Beutefenster offen – öffne es und gib den Befehl noch einmal ein."]
        return z
    end
    local kand = rawget(_G, "GetMasterLootCandidate")
    for _, e in ipairs(liste) do
        local n = 0
        if type(kand) == "function" then
            for i = 1, 40 do
                local ok, name = pcall(kand, e.platz, i)
                if ok and name then n = n + 1 end
            end
        end
        z[#z + 1] = string.format(L["  Platz %d: %s – %d mögliche Empfänger"], e.platz, e.link, n)
    end
    return z
end

return ns
