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
local AKZENT = S.Code(C.ac)
local GRUEN  = S.Code(C.ok)

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

local ergebnisZeigen, ergebnisVerstecken

local function beginnen(rid, link, dauer, selbst)
    aktiv = { rid = rid, link = link, dauer = dauer, ende = time() + dauer, selbst = selbst and true or false }
    nachlauf = nil
    ergebnisVerstecken()

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
    local link, selbst = aktiv.link, aktiv.selbst
    nachlauf = { link = link, bis = time() + NACHLAUF }
    aktiv = nil
    if popup then popup:Hide() end
    if ns.Fenster then ns.Fenster.Aktualisieren() end

    -- Wer den Wurf gestartet hat, bekommt das Ergebnis mit den Zuteilen-Knoepfen.
    -- Kurz warten: der letzte Wurf kann noch unterwegs sein.
    if selbst and C_Timer then
        C_Timer.After(1.5, function() if not aktiv then ergebnisZeigen(link) end end)
    end
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
    beginnen(rid, link, dauer, true)
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
        beginnen(rid, link, math.max(5, math.min(120, d)), false)
    elseif typ == "X" then
        local rid = rest:match("^([^;]*)")
        if aktiv and rid == aktiv.rid then Wurf.Ende() end
    end
end

-- =====================================================================
--  Wurf starten: Dialog
-- =====================================================================

local ZEILEN = 10

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
        if ok2 and type(l) == "string" and l ~= "" then
            liste[#liste + 1] = { platz = i, link = l, typ = "beute", id = tonumber(l:match("item:(%d+)")) }
        end
    end
    return liste
end

-- =====================================================================
--  Rucksack: Beute, die der Pluendermeister eingesteckt hat
-- =====================================================================

--- ⭐ Haeufigster Ablauf: Der Pluendermeister steckt die Beute selbst ein,
--  damit er auf dem Weg zum naechsten Boss verrollen kann. Solche Stuecke
--  tragen eine Handelsfrist („Du kannst diesen Gegenstand noch … mit
--  Spielern handeln, die ihn auch plündern durften").
local function idVon(link)
    return tonumber(tostring(link):match("item:(%d+)"))
end

--- Link und Qualitaet eines Rucksackplatzes (neue und alte Schnittstelle).
local function platzInfo(f, bag, slot)
    local ok, a, _, _, q, _, _, l = pcall(f, bag, slot)
    if not ok or a == nil then return nil end
    if type(a) == "table" then return a.hyperlink, a.quality end
    return l, q
end

--- Traegt der Gegenstand noch eine Handelsfrist?
--  @return true / false, oder nil wenn der Client das nicht verraet
local function handelbar(bag, slot)
    local TI = rawget(_G, "C_TooltipInfo")
    if not (TI and TI.GetBagItem) then return nil end
    local vorlage = rawget(_G, "BIND_TRADE_TIME_REMAINING")
    local teil = type(vorlage) == "string" and vorlage:match("^(.-)%%s") or nil
    if not teil or teil == "" then return nil end

    local ok, daten = pcall(TI.GetBagItem, bag, slot)
    if not ok or type(daten) ~= "table" then return nil end
    local TU = rawget(_G, "TooltipUtil")
    if TU and TU.SurfaceArgs then pcall(TU.SurfaceArgs, daten) end
    for _, z in ipairs(daten.lines or {}) do
        if TU and TU.SurfaceArgs then pcall(TU.SurfaceArgs, z) end
        -- ⚠️ Texte koennen „geheim" sein: nur im pcall vergleichen.
        local ok2, treffer = pcall(function()
            return type(z.leftText) == "string" and z.leftText:find(teil, 1, true) ~= nil
        end)
        if ok2 and treffer then return true end
    end
    return false
end

--- Gegenstaende im Rucksack ab der eingestellten Qualitaet.
--  Kann der Client die Handelsfrist lesen, zaehlen nur Stuecke mit Frist.
--  @return Liste { link, id, bag, slot, typ = "tasche" }
local function taschenListe()
    local liste = {}
    local CC = rawget(_G, "C_Container")
    local zahl = (CC and CC.GetContainerNumSlots) or rawget(_G, "GetContainerNumSlots")
    local info = (CC and CC.GetContainerItemInfo) or rawget(_G, "GetContainerItemInfo")
    if type(zahl) ~= "function" or type(info) ~= "function" then return liste end

    local mind = db().mindestQualitaet or 3
    local fristBekannt = false
    for bag = 0, 5 do
        local ok, n = pcall(zahl, bag)
        if ok and type(n) == "number" then
            for slot = 1, n do
                local l, q = platzInfo(info, bag, slot)
                if l and (q or 0) >= mind then
                    local h = handelbar(bag, slot)
                    if h ~= nil then fristBekannt = true end
                    liste[#liste + 1] = { link = l, id = idVon(l), bag = bag, slot = slot, typ = "tasche", frist = h }
                end
            end
        end
    end

    if fristBekannt then
        local nur = {}
        for _, e in ipairs(liste) do if e.frist then nur[#nur + 1] = e end end
        return nur
    end
    return liste
end

--- Alles, was sich verteilen laesst: offenes Beutefenster, dann Rucksack.
local function sammlung()
    local liste = beuteListe()
    for _, e in ipairs(taschenListe()) do liste[#liste + 1] = e end
    return liste
end

--- Wo liegt dieser Gegenstand gerade?
local function findeGegenstand(link)
    local id = idVon(link)
    if not id then return nil end
    for _, e in ipairs(sammlung()) do
        if e.id == id then return e end
    end
    return nil
end

local function starterBeute()
    if not starter then return end
    local liste = sammlung()
    for i = 1, ZEILEN do
        local z = starter.zeilen[i]
        local e = liste[i]
        if e then
            z.link = e.link
            z.text:SetText(e.link .. (e.typ == "tasche" and ("  " .. GRAU .. L["Rucksack"] .. "|r") or ""))
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
    -- ⚠️ Das Feld zeigt einen Link nur als farbigen Namen („[Schwert]"); was
    -- GetText() dann liefert, ist nicht verlaesslich der volle Link (so gesehen
    -- am 14.10.2026: „Kein Gegenstand erkannt"). Darum merkt sich der Dialog
    -- den gewaehlten Link selbst. Ein von Hand eingefuegter Link im Feld gilt.
    local text = starter.eingabe:GetText()
    local quelle = (linkAus(text) and text) or starter.gewaehlt or text
    local ok, grund = Wurf.Starten(quelle)
    if ok then
        starter.gewaehlt = nil
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
    s:SetSize(360, 430)
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
    s.eingabe:SetScript("OnTextChanged", function(e)
        if (e:GetText() or "") == "" then s.gewaehlt = nil end
    end)

    local hinweis = S.Text(s, 11, C.dim, "LEFT")
    hinweis:SetPoint("TOPLEFT", s, "TOPLEFT", 16, -96)
    hinweis:SetText(L["Shift-Klick auf einen Gegenstand fügt den Link ein."])

    local t2 = S.Text(s, 12, C.mu, "LEFT")
    t2:SetPoint("TOPLEFT", s, "TOPLEFT", 16, -122)
    t2:SetText(L["Beute und Rucksack"])

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
            if x.link then
                s.eingabe:SetText(x.link)
                s.gewaehlt = x.link
            end
        end)
        z:Hide()
        s.zeilen[i] = z
    end
    s.leer = S.Text(s, 12, C.dim, "LEFT", true)
    s.leer:SetPoint("TOPLEFT", s, "TOPLEFT", 22, -146)
    s.leer:SetWidth(316)
    s.leer:SetText(L["Nichts zum Verteilen gefunden: kein Beutefenster offen und nichts im Rucksack, das noch tauschbar ist."])

    s.fehler = S.Text(s, 12, C.bad, "LEFT", true)
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

-- =====================================================================
--  Ergebnis und Zuteilen
-- =====================================================================

local ERG_ZEILEN = 6
local ergebnis            -- das Fenster
local ergebnisDaten       -- { link, zeilen = { { name, wert, art, haupt, zweit } } }
local pending             -- ein laufender Handel

local function anzahlImRucksack(id)
    local CI = rawget(_G, "C_Item")
    local f = (CI and CI.GetItemCount) or rawget(_G, "GetItemCount")
    if type(f) ~= "function" or not id then return 0 end
    local ok, n = pcall(f, id)
    return (ok and tonumber(n)) or 0
end

--- Die Reihenfolge wie in der Uebersicht: Haupt vor OS, wenigste Stuecke,
--  dann der hoechste Wurf. Nur wer gewuerfelt hat.
local function rangliste(link)
    local R = ns.Erfassung.AktuelleWuerfe()
    if not R or R.link ~= link then return {} end

    local function schluessel(name)
        for _, n in ipairs(R.namen) do
            if Kern.GleicherSpieler(n, name) then return Kern.Schluessel(n), n end
        end
    end

    local liste = Kern.Bilanz(ns.Erfassung.Historie(), 0, R.namen, R.namen)
    Kern.WurfReihenfolge(liste,
        function(name)
            local k = schluessel(name)
            return (k and (R.Arten[k] or true)) or false
        end,
        function(name)
            local k = schluessel(name)
            return k and R.Wuerfe[k] or 0
        end)

    local zeilen = {}
    for _, e in ipairs(liste) do
        local k, voll = schluessel(e.name)
        if k and (R.Wuerfe[k] or 0) > 0 then
            zeilen[#zeilen + 1] = { name = voll, wert = R.Wuerfe[k], art = R.Arten[k], haupt = e.haupt, zweit = e.zweit }
        end
    end
    return zeilen
end

--- Eine Vergabe in die Historie schreiben (nur der Aufzeichner darf).
local function eintragen(name, link, z)
    local _, unit = ns.Rolle.Absender(name)
    local voll = (unit and GetUnitName and GetUnitName(unit, true)) or name
    local ok, grund = ns.Erfassung.Eintragen(voll, link, nil, z.art, nil, { wurf = z.wert, herkunft = "wurf" })
    if ok then
        sag(GRUEN .. string.format(L["Eingetragen: %s für %s"], link, voll) .. "|r")
    else
        sag(ROT .. string.format(L["Nicht eingetragen: %s"], tostring(grund)) .. "|r")
    end
    return ok
end

-- ---------------------------------------------------------------------
--  Aus dem Beutefenster (Plündermeister-Zuteilung)
-- ---------------------------------------------------------------------

local function ausBeutefenster(name, ort, link)
    local kand = rawget(_G, "GetMasterLootCandidate")
    local geben = rawget(_G, "GiveMasterLoot")
    if type(kand) ~= "function" or type(geben) ~= "function" then
        return false, L["Zuteilen über das Beutefenster ist hier nicht möglich."]
    end
    for i = 1, 40 do
        local ok, n = pcall(kand, ort.platz, i)
        if ok and n and Kern.GleicherSpieler(n, name) then
            if not pcall(geben, ort.platz, i) then return false, L["Zuteilen fehlgeschlagen."] end
            -- Eingetragen wird ueber die Beutemeldung („X erhält Beute").
            sag(string.format(L["Zugeteilt: %s an %s"], link, n))
            return true
        end
    end
    return false, L["Der Spieler steht nicht in der Empfängerliste (zu weit weg?)."]
end

-- ---------------------------------------------------------------------
--  Aus dem Rucksack (Handel)
-- ---------------------------------------------------------------------

local function handelStarten(name, link, ort, z)
    local _, unit = ns.Rolle.Absender(name)
    local initiate = rawget(_G, "InitiateTrade")
    if not unit or type(initiate) ~= "function" then
        sag(ROT .. L["Handel nicht möglich."] .. "|r")
        return false
    end
    pending = { name = name, link = link, id = ort.id, art = z.art, wert = z.wert,
                vorher = anzahlImRucksack(ort.id), bis = time() + 120 }
    if not pcall(initiate, unit) then
        pending = nil
        sag(ROT .. L["Handel nicht möglich."] .. "|r")
        return false
    end
    sag(string.format(L["Handel mit %s angefragt – der Gegenstand wird eingelegt, sobald das Fenster offen ist."], name))
    return true
end

--- Das Handelsfenster ist offen: den Gegenstand einlegen.
--  ⚠️ Nur, wenn der Handelspartner der Gewinner ist. Bestaetigen muss der
--  Plündermeister selbst; das Addon drueckt nie „Handeln".
local function handelOffen()
    local P = pending
    if not P then return end
    if time() > P.bis then pending = nil return end

    local ok, partner = pcall(function() return GetUnitName("NPC", true) end)
    if not ok or not partner or not Kern.GleicherSpieler(partner, P.name) then return end

    local gefunden
    for _, e in ipairs(taschenListe()) do
        if e.id == P.id then gefunden = e break end
    end
    local CC = rawget(_G, "C_Container")
    local nimm = (CC and CC.PickupContainerItem) or rawget(_G, "PickupContainerItem")
    local lege = rawget(_G, "ClickTradeButton")
    if not gefunden or type(nimm) ~= "function" or type(lege) ~= "function" then
        sag(ROT .. L["Gegenstand konnte nicht eingelegt werden – bitte von Hand ins Handelsfenster ziehen."] .. "|r")
        return
    end
    pcall(nimm, gefunden.bag, gefunden.slot)
    pcall(lege, 1)
    local leeren = rawget(_G, "ClearCursor")
    if type(leeren) == "function" then pcall(leeren) end
    P.eingelegt = true
    sag(L["Gegenstand liegt im Handelsfenster – bitte prüfen und bestätigen."])
end

--- Das Handelsfenster ist zu: war es erfolgreich, wird eingetragen.
local function handelZu()
    local P = pending
    if not P then return end
    if not P.eingelegt or not C_Timer then pending = nil return end
    C_Timer.After(1.5, function()
        local p = pending
        pending = nil
        if p ~= P then return end
        -- Der Gegenstand ist weg? Dann ist der Handel gelungen.
        if anzahlImRucksack(P.id) < P.vorher then
            eintragen(P.name, P.link, P)
        else
            sag(GRAU .. L["Handel nicht abgeschlossen – nichts eingetragen."] .. "|r")
        end
    end)
end

-- ---------------------------------------------------------------------
--  Zuteilen
-- ---------------------------------------------------------------------

--- Teilt den Gegenstand dieser Zeile zu (Beutefenster oder Handel) oder traegt
--  nur ein, wenn er nicht auffindbar ist oder beim Pluendermeister bleibt.
function Wurf.Zuteilen(z)
    local D = ergebnisDaten
    if not D or not z then return end
    local link, name = D.link, z.name
    local ort = findeGegenstand(link)

    if not ort or Kern.GleicherSpieler(name, ichName()) then
        eintragen(name, link, z)
    elseif ort.typ == "beute" then
        local ok, grund = ausBeutefenster(name, ort, link)
        if not ok then sag(ROT .. tostring(grund) .. "|r") return end
    else
        if not handelStarten(name, link, ort, z) then return end
    end
    if ergebnis then ergebnis:Hide() end
end

local function ergebnisAktualisieren()
    local e, D = ergebnis, ergebnisDaten
    if not e or not D then return end
    e.item:SetText(D.link)

    local ort = findeGegenstand(D.link)
    if not ort then
        e.ort:SetText(GELB .. L["Gegenstand nicht gefunden – es kann nur eingetragen werden."] .. "|r")
    elseif ort.typ == "beute" then
        e.ort:SetText(GRAU .. L["Gegenstand liegt im Beutefenster."] .. "|r")
    else
        e.ort:SetText(GRAU .. L["Gegenstand liegt im Rucksack."] .. "|r")
    end

    for i = 1, ERG_ZEILEN do
        local zeile, z = e.zeilen[i], D.zeilen[i]
        if z then
            zeile.daten = z
            zeile.name:SetText(z.name)
            zeile.wert:SetText(HELL .. z.wert .. "|r  " ..
                (z.art == "haupt" and (AKZENT .. L["Haupt"] .. "|r") or (GRAU .. L["Zweit"] .. "|r")))
            zeile.knopf:SetLabel(ort and L["Zuteilen"] or L["Nur eintragen"])
            zeile.knopf:SetFest(96)
            zeile.bg:SetShown(i == 1)
            zeile:Show()
        else
            zeile.daten = nil
            zeile:Hide()
        end
    end
end

local function ergebnisBauen()
    if ergebnis then return end
    local e = CreateFrame("Frame", "FairshareWurfErgebnis", UIParent)
    ergebnis = e
    e:SetSize(380, 330)
    e:SetFrameStrata("DIALOG")
    e:SetFrameLevel(55)
    e:SetClampedToScreen(true)
    e:SetMovable(true)
    e:EnableMouse(true)
    S.Kasten(e, 10, C.bg, C.ln)

    kopfLeiste(e, "Fairshare  " .. GRAU .. L["Ergebnis"] .. "|r", "wurfErgebnis", function() e:Hide() end)

    local item = CreateFrame("Button", nil, e)
    item:SetPoint("TOPLEFT", e, "TOPLEFT", 16, -44)
    item:SetSize(348, 22)
    e.item = S.Text(item, 14, C.tx, "LEFT")
    e.item:SetPoint("LEFT", item, "LEFT", 0, 0)
    e.item:SetWidth(348)
    item:SetScript("OnEnter", function(s)
        if ergebnisDaten and GameTooltip and GameTooltip.SetHyperlink then
            GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
            pcall(GameTooltip.SetHyperlink, GameTooltip, ergebnisDaten.link)
            GameTooltip:Show()
        end
    end)
    item:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    e.ort = S.Text(e, 12, C.mu, "LEFT")
    e.ort:SetPoint("TOPLEFT", e, "TOPLEFT", 16, -68)
    e.ort:SetWidth(348)

    e.zeilen = {}
    for i = 1, ERG_ZEILEN do
        local z = CreateFrame("Frame", nil, e)
        z:SetSize(348, 30)
        z:SetPoint("TOPLEFT", e, "TOPLEFT", 16, -94 - (i - 1) * 32)
        z.bg = S.Form(z, 5, C.acb)
        z.name = S.Text(z, 13, C.tx, "LEFT")
        z.name:SetPoint("LEFT", z, "LEFT", 8, 0)
        z.name:SetWidth(140)
        z.wert = S.Text(z, 13, C.tx, "LEFT")
        z.wert:SetPoint("LEFT", z, "LEFT", 152, 0)
        z.wert:SetWidth(80)
        z.knopf = S.Knopf(z, L["Zuteilen"], i == 1 and "primary" or "secondary", 24)
        z.knopf:SetPoint("RIGHT", z, "RIGHT", -4, 0)
        z.knopf:SetScript("OnClick", function() Wurf.Zuteilen(z.daten) end)
        z:Hide()
        e.zeilen[i] = z
    end

    e.fuss = S.Text(e, 11, C.dim, "LEFT", true)
    e.fuss:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", 16, 14)
    e.fuss:SetWidth(348)
    e.fuss:SetText(L["Beim Handel wird erst eingetragen, wenn er abgeschlossen ist. Bestätigen musst du selbst."])
    e:Hide()
end

ergebnisZeigen = function(link)
    local zeilen = rangliste(link)
    if #zeilen == 0 then
        sag(GRAU .. L["Niemand hat gewürfelt."] .. "|r")
        return
    end
    ergebnisBauen()
    ergebnisDaten = { link = link, zeilen = zeilen }
    lageSetzen(ergebnis, "wurfErgebnis", { "CENTER", 0, 100 })
    ergebnis:Show()
    ergebnisAktualisieren()
end

ergebnisVerstecken = function()
    if ergebnis then ergebnis:Hide() end
    ergebnisDaten = nil
end

--- Das Ergebnis des letzten Wurfs noch einmal oeffnen (`/fs wurf ergebnis`).
function Wurf.ErgebnisOeffnen()
    if not ergebnisDaten then return false, L["Es gibt kein Ergebnis."] end
    ergebnisBauen()
    lageSetzen(ergebnis, "wurfErgebnis", { "CENTER", 0, 100 })
    ergebnis:Show()
    ergebnisAktualisieren()
    return true
end

-- Shift-Klick auf einen Gegenstand fuegt den Link ein, solange das Feld den Fokus hat.
local function linkEinfuegen(text)
    if starter and starter:IsShown() and starter.eingabe:HasFocus() and type(text) == "string" then
        local link = linkAus(text)
        if link then
            starter.eingabe:SetText(link)
            starter.gewaehlt = link
        else
            starter.eingabe:Insert(text)
        end
    end
end
if hooksecurefunc then
    pcall(hooksecurefunc, "ChatEdit_InsertLink", linkEinfuegen)
    local CFU = rawget(_G, "ChatFrameUtil")
    if CFU and CFU.InsertLink then pcall(hooksecurefunc, CFU, "InsertLink", linkEinfuegen) end
end

local ereignisse = CreateFrame("Frame")
for _, e in ipairs({ "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "BAG_UPDATE_DELAYED",
                     "TRADE_SHOW", "TRADE_CLOSED" }) do
    pcall(function() ereignisse:RegisterEvent(e) end)
end
ereignisse:SetScript("OnEvent", function(_, ereignis)
    if ereignis == "TRADE_SHOW" then
        pcall(handelOffen)
    elseif ereignis == "TRADE_CLOSED" then
        pcall(handelZu)
    elseif starter and starter:IsShown() then
        pcall(starterBeute)
    end
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
