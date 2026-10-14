--[[----------------------------------------------------------------------
    Wurf.lua  —  Eigenes Wuerfelfenster: Hauptbedarf oder Zweitbedarf (OS)

    ⭐ Warum es das gibt (Nutzer, 14.10.2026): Gargul ist in der Beta noch
    verbuggt. Fairshare bietet deshalb selbst an, was die Gilde braucht:

      1. Der Pluendermeister (Leiter, Assistent) startet einen Wurf fuer einen
         Gegenstand: `/fs wurf <Link>`, der Knopf *Wurf starten* oder
         die Beute im offenen Beutefenster anklicken.
      2. Bei ALLEN in der Gruppe mit Fairshare geht ein kleines Fenster auf:
         Gegenstand, Restzeit, Knoepfe **Haupt**, **Zweit (OS)**, **Passen**.
         Die Bereiche (Standard 1-100 und 1-50) sind einstellbar; der Leiter
         schickt seine mit jedem Wurf mit, damit alle gleich wuerfeln.
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
local BAHN = 308          -- Breite des Zeitbalkens

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
--  ⚠️ Das Farbstueck ist nicht immer „|cffRRGGBB": Neuere Clients schreiben
--  „|cnIQ4:" (Qualitaetsfarbe als Name). Im Spiel gesehen am 14.10.2026:
--  mit dem alten Muster fand der Start keinen Gegenstand. Darum: alles bis
--  zum naechsten „|" als Farbe, und die Farbe darf ganz fehlen.
local function linkAus(text)
    if type(text) ~= "string" then return nil end
    return text:match("(|c[^|]*|Hitem:[^|]+|h%[[^%]]*%]|h|r)")
        or text:match("(|Hitem:[^|]+|h%[[^%]]*%]|h)")
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
        -- Der Bereich dieses Wurfs (vom Leiter mitgeschickt), sonst der eigene.
        local B = aktiv.bereiche or Kern.BEREICHE
        local r = (art == "haupt") and B.haupt or B.zweit
        local f = rawget(_G, "RandomRoll")
        local ok = false
        if type(f) == "function" then ok = pcall(f, r[1], r[2]) end
        if not ok then
            -- Ohne RandomRoll bleibt nur der Handgriff.
            aktiv.meine = nil
            sag(ROT .. string.format(L["Würfeln nicht möglich – bitte |cffffff78/roll %d-%d|r eingeben."], r[1], r[2]) .. "|r")
        end
    end
    popupAktualisieren()
end

local function popupBauen()
    if popup then return end
    local p = CreateFrame("Frame", "FairshareWurf", UIParent)
    popup = p
    p:SetSize(340, 168)
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

    -- Falscher Gegenstand verrollt: abbrechen, ohne Ergebnis, bei allen
    p.abbrechen = S.Knopf(p, L["Abbrechen"], "link", 22)
    p.abbrechen:SetPoint("RIGHT", p.beenden, "LEFT", -6, 0)
    p.abbrechen:SetFrameLevel(p:GetFrameLevel() + 5)
    p.abbrechen:SetScript("OnClick", function() Wurf.Abbrechen() end)

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
    p.haupt = S.Knopf(p, string.format(L["Haupt (%d-%d)"], Kern.BEREICHE.haupt[1], Kern.BEREICHE.haupt[2]), "primary", 30)
    p.haupt:SetFest(130)
    p.haupt:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 16, 16)
    p.haupt:SetScript("OnClick", function() waehlen("haupt") end)

    p.zweit = S.Knopf(p, string.format(L["Zweit (%d-%d)"], Kern.BEREICHE.zweit[1], Kern.BEREICHE.zweit[2]), "secondary", 30)
    p.zweit:SetFest(110)
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

    -- Beschriftung mit den Bereichen DIESES Wurfs
    local B = aktiv.bereiche or Kern.BEREICHE
    popup.haupt:SetLabel(string.format(L["Haupt (%d-%d)"], B.haupt[1], B.haupt[2]))
    popup.zweit:SetLabel(string.format(L["Zweit (%d-%d)"], B.zweit[1], B.zweit[2]))

    local frei = not m
    popup.haupt:SetAktiv(frei)
    popup.zweit:SetAktiv(frei)
    popup.passen:SetAktiv(frei)
    popup.beenden:SetShown(Wurf.DarfStarten())
    popup.abbrechen:SetShown(Wurf.DarfStarten())
end

-- =====================================================================
--  Ablauf
-- =====================================================================

local ergebnisZeigen, ergebnisVerstecken
local ergebnis            -- das Ergebnisfenster
local ergebnisDaten       -- { link, zeilen = { { name, wert, art, haupt, zweit } } }

local function kopie(B)
    return { haupt = { B.haupt[1], B.haupt[2] }, zweit = { B.zweit[1], B.zweit[2] } }
end

--  @param bereiche  { h1, h2, z1, z2 } des Leiters, oder nil (alte Fassung)
local function beginnen(rid, link, dauer, selbst, bereiche)
    -- Ein noch laufender Wurf mit fremden Bereichen: erst die eigenen zurueck.
    if aktiv and aktiv.tauschen then ns.Erfassung.BereicheAnwenden() end

    aktiv = { rid = rid, link = link, dauer = dauer, ende = time() + dauer, selbst = selbst and true or false,
              bereiche = kopie(Kern.BEREICHE) }
    nachlauf = nil
    ergebnisVerstecken()

    -- ⭐ Alle wuerfeln und erkennen mit den Bereichen des Leiters, solange der Wurf
    -- laeuft (nicht gespeichert; danach gelten wieder die eigenen).
    if bereiche and not selbst then
        local eigene = kopie(Kern.BEREICHE)
        if Kern.BereicheSetzen(bereiche[1], bereiche[2], bereiche[3], bereiche[4]) then
            aktiv.bereiche = kopie(Kern.BEREICHE)
            aktiv.tauschen = (eigene.haupt[1] ~= bereiche[1] or eigene.haupt[2] ~= bereiche[2]
                              or eigene.zweit[1] ~= bereiche[3] or eigene.zweit[2] ~= bereiche[4])
            if not aktiv.tauschen then aktiv.tauschen = nil end
        else
            Kern.BereicheSetzen(eigene.haupt[1], eigene.haupt[2], eigene.zweit[1], eigene.zweit[2])
        end
    end

    -- Die Uebersicht oeffnet sich nur bei dem, der den Wurf leitet.
    ns.Erfassung.WurfBeginnt(link, Wurf.DarfStarten())

    popupBauen()
    lageSetzen(popup, "wurf", { "TOP", 0, -180 })
    popup:Show()
    popupAktualisieren()
end

--- Der Wurf ist vorbei (Zeit, Abbruch oder Meldung des Leiters).
--  @param ohneErgebnis  true: das Ergebnisfenster nicht zeigen (der Gegenstand ist schon vergeben)
function Wurf.Ende(ohneErgebnis)
    if not aktiv then return end
    local link, selbst, tauschen = aktiv.link, aktiv.selbst, aktiv.tauschen
    nachlauf = { link = link, bis = time() + NACHLAUF }
    aktiv = nil
    if tauschen then ns.Erfassung.BereicheAnwenden() end
    if popup then popup:Hide() end
    if ns.Fenster then ns.Fenster.Aktualisieren() end

    -- Wer den Wurf gestartet hat, bekommt das Ergebnis mit den Zuteilen-Knoepfen.
    -- Kurz warten: der letzte Wurf kann noch unterwegs sein.
    if selbst and not ohneErgebnis and C_Timer then
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
    -- Format: S;<Kennung>;<Sekunden>;<h1>,<h2>,<z1>,<z2>;<Link>. Aeltere Fassungen
    -- lesen nur den Link heraus und ignorieren die Bereiche.
    local B = Kern.BEREICHE
    local bereiche = string.format("%d,%d,%d,%d", B.haupt[1], B.haupt[2], B.zweit[1], B.zweit[2])
    if not ns.Abgleich.Senden(string.format("S;%s;%d;%s;%s", rid, dauer, bereiche, link), true) then
        return false, L["Senden nicht möglich."]
    end
    beginnen(rid, link, dauer, true)
    return true
end

--- Beendet den laufenden Wurf bei allen.
function Wurf.BeendenAlle(ohneErgebnis)
    if not aktiv then return false, L["Es läuft kein Wurf."] end
    if Wurf.DarfStarten() then
        ns.Abgleich.Senden("X;" .. aktiv.rid, true)
    end
    Wurf.Ende(ohneErgebnis)
    return true
end

--- ⭐ Wurf abbrechen (falscher Gegenstand verrollt): bei allen schliessen sich die
--  Fenster, es gibt kein Ergebnis, und die bisherigen Wuerfe zaehlen nirgends.
--  Auch nach dem Ende eines Wurfs, solange das Ergebnis noch offen ist.
function Wurf.Abbrechen()
    if aktiv then
        local link = aktiv.link
        if Wurf.DarfStarten() then ns.Abgleich.Senden("X;" .. aktiv.rid .. ";a", true) end
        Wurf.Ende(true)
        nachlauf = nil
        ns.Erfassung.RundeVerwerfen(link)
        sag(L["Wurf abgebrochen."])
        return true
    end
    if ergebnisDaten then
        ns.Erfassung.RundeVerwerfen(ergebnisDaten.link)
        ergebnisVerstecken()
        sag(L["Wurf abgebrochen."])
        return true
    end
    return false, L["Es läuft kein Wurf."]
end

--- ⭐ Der Gegenstand ist vergeben (egal auf welchem Weg: Handel, Beutefenster,
--  Gargul, Chat): Der laufende Wurf dafuer endet, das Ergebnisfenster geht zu.
--  Sonst blieb „Wurf laeuft" stehen (Nutzerfund 14.10.2026).
function Wurf.Vergeben(link)
    local id = link and tonumber(tostring(link):match("item:(%d+)"))
    if not id then return end
    if aktiv and tonumber(tostring(aktiv.link):match("item:(%d+)")) == id then
        Wurf.BeendenAlle(true)
    end
    if ergebnis and ergebnisDaten and tonumber(tostring(ergebnisDaten.link):match("item:(%d+)")) == id then
        ergebnis:Hide()
    end
end

-- Die letzten Wurfmeldungen und was daraus wurde — damit sich bei einem Spieler,
-- bei dem „nichts aufgeht", nachlesen laesst, WARUM (/fs wurf status).
local protokoll = {}

local function merke(text)
    protokoll[#protokoll + 1] = date("%H:%M:%S", time()) .. "  " .. text
    if #protokoll > 8 then table.remove(protokoll, 1) end
end

--- Eine Nachricht der Gruppe. `unit` ist der Absender in unserer Gruppe (oder nil).
--  Die Gilde wird hier NICHT verlangt (siehe Abgleich.Empfangen).
function Wurf.Empfangen(typ, rest, sender, unit)
    if not unit then
        merke(string.format(L["%s von %s: Absender nicht in der Gruppe erkannt"], typ, tostring(sender)))
        return
    end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return end    -- das waren wir selbst

    local name = (GetUnitName and GetUnitName(unit, true)) or sender
    if type(rest) ~= "string" or not ns.Rolle.Berechtigt(name) then
        merke(string.format(L["%s von %s: Absender ist weder Plündermeister noch Leiter noch Assistent"], typ, tostring(name)))
        return
    end

    if typ == "S" then
        local rid, d, text = rest:match("^([^;]*);(%d+);(.*)$")
        local bereiche
        local h1, h2, z1, z2, danach = (text or ""):match("^(%d+),(%d+),(%d+),(%d+);(.*)$")
        if h1 then
            bereiche = { tonumber(h1), tonumber(h2), tonumber(z1), tonumber(z2) }
            text = danach
        end
        local link = linkAus(text)
        d = tonumber(d)
        if not rid or #rid > 12 or not d or not link then
            merke(string.format(L["%s von %s: Nachricht ungültig"], typ, tostring(name)))
            return
        end
        merke(string.format(L["Wurf von %s angenommen: %s"], tostring(name), link))
        beginnen(rid, link, math.max(5, math.min(120, d)), false, bereiche)
    elseif typ == "X" then
        local rid, flag = rest:match("^([^;]*);?(%a?)")
        if aktiv and rid == aktiv.rid then
            if flag == "a" then
                -- abgebrochen: kein Ergebnis, die Wuerfe zaehlen nirgends
                local link = aktiv.link
                merke(string.format(L["Wurf beendet von %s"], tostring(name)))
                Wurf.Ende(true)
                nachlauf = nil
                ns.Erfassung.RundeVerwerfen(link)
                sag(string.format(L["Wurf abgebrochen von %s."], tostring(name)))
            else
                merke(string.format(L["Wurf beendet von %s"], tostring(name)))
                Wurf.Ende()
            end
        end
    end
end

--- Diagnose: laeuft ein Wurf, und was kam zuletzt an?
--  @return Liste von Zeilen
function Wurf.Status()
    local z = {}
    if aktiv then
        z[#z + 1] = string.format(L["Es läuft ein Wurf: %s (noch %d s)"], aktiv.link, math.max(0, aktiv.ende - time()))
    else
        z[#z + 1] = L["Es läuft kein Wurf."]
    end
    z[#z + 1] = string.format(L["Du darfst einen Wurf starten: %s"], Wurf.DarfStarten() and L["ja"] or L["nein"])
    if #protokoll == 0 then
        z[#z + 1] = L["Noch keine Wurfmeldung empfangen – kein Wurf gestartet, oder die Nachricht kam nicht an."]
    else
        z[#z + 1] = L["Letzte Wurfmeldungen:"]
        for _, t in ipairs(protokoll) do z[#z + 1] = "  " .. t end
    end
    return z
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
        return nur, true
    end
    return liste, false
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

-- ⭐ Eine Zuteilung aus dem Rucksack ist erst fertig, wenn der Handel
-- stattgefunden hat — und der kann spaeter sein: Der Gewinner ist zu weit weg,
-- schon offline, man trifft sich erst am naechsten Boss. Darum wird jede
-- Zuteilung VORGEMERKT (gespeichert, ueberlebt /reload und Abmelden) und beim
-- naechsten Handel mit genau diesem Spieler automatisch eingelegt. Zusaetzlich
-- erkennt das Addon einen Handel, den man ganz von Hand macht, solange der
-- Gegenstand noch eine Handelsfrist hat oder ein Wurf bekannt ist.
local VORMERKDAUER = 3 * 3600   -- die Handelsfrist selbst endet nach zwei Stunden

local function offenListe()
    local d = db()
    d.offen = d.offen or {}
    local jetzt = time()
    for i = #d.offen, 1, -1 do
        if (jetzt - (d.offen[i].zeit or 0)) > VORMERKDAUER then table.remove(d.offen, i) end
    end
    return d.offen
end

local function vormerken(name, link, id, z)
    local liste = offenListe()
    for _, e in ipairs(liste) do
        if e.id == id and Kern.GleicherSpieler(e.name, name) then return e end
    end
    local e = { name = name, link = link, id = id, art = z.art, wert = z.wert, zeit = time() }
    liste[#liste + 1] = e
    return e
end

local function vormerkungLoeschen(e)
    local liste = offenListe()
    for i, x in ipairs(liste) do
        if x == e then table.remove(liste, i) return end
    end
end

--- Die vorgemerkten Zuteilungen (Kopie, fuer die Anzeige).
function Wurf.Offene()
    local aus = {}
    for _, e in ipairs(offenListe()) do aus[#aus + 1] = e end
    return aus
end

function Wurf.OffeneLeeren()
    local n = #offenListe()
    db().offen = {}
    return n
end

--- Der gerade offene Handel:
--  { partner, vorher = { Nummer -> Anzahl im Rucksack }, tauschbar = { Nummer -> true },
--    angeboten = { Link, ... } }
local handel

--- Was liegt in den eigenen Handelsplaetzen?
--  Beim Schliessen ist die Anzeige schon leer: dann bleibt der letzte Stand.
local function angebotLesen(H, leerErlaubt)
    if not H then return end
    local f = rawget(_G, "GetTradePlayerItemLink")
    if type(f) ~= "function" then return end
    local liste = {}
    for i = 1, 6 do
        local ok, l = pcall(f, i)
        if ok and type(l) == "string" and l ~= "" then liste[#liste + 1] = l end
    end
    if #liste > 0 or leerErlaubt then H.angeboten = liste end
end

--- Einen Handel mit dem Spieler anfragen (er muss in der Gruppe und in Reichweite sein).
local function handelAnfragen(name)
    local _, unit = ns.Rolle.Absender(name)
    local initiate = rawget(_G, "InitiateTrade")
    if not unit or type(initiate) ~= "function" then return false end
    return pcall(initiate, unit) and true or false
end

--- Das Handelsfenster ist offen.
--  Vorgemerktes fuer genau diesen Partner wird eingelegt; sonst nur gemerkt,
--  was im Rucksack liegt, um einen Handel von Hand spaeter zu erkennen.
--  ⚠️ Bestaetigen muss der Plündermeister selbst; das Addon drueckt nie „Handeln".
local function handelOffen()
    local ok, partner = pcall(function() return GetUnitName("NPC", true) end)
    if not ok or type(partner) ~= "string" or partner == "" then handel = nil return end

    local liste, fristBekannt = taschenListe()
    handel = { partner = partner, vorher = {}, tauschbar = {}, angeboten = {} }
    for _, e in ipairs(liste) do
        if e.id then
            handel.vorher[e.id] = anzahlImRucksack(e.id)
            if fristBekannt then handel.tauschbar[e.id] = true end
        end
    end
    -- auch der Gegenstand des letzten Wurfs, falls die Liste ihn nicht kennt
    local rid = ergebnisDaten and idVon(ergebnisDaten.link)
    if rid and handel.vorher[rid] == nil then handel.vorher[rid] = anzahlImRucksack(rid) end

    local CC = rawget(_G, "C_Container")
    local nimm = (CC and CC.PickupContainerItem) or rawget(_G, "PickupContainerItem")
    local lege = rawget(_G, "ClickTradeButton")
    if type(nimm) ~= "function" or type(lege) ~= "function" then return end

    local k, benutzt = 0, {}
    for _, v in ipairs(offenListe()) do
        if k >= 6 then break end
        if Kern.GleicherSpieler(v.name, partner) then
            for _, e in ipairs(liste) do
                local platz = e.bag .. ":" .. e.slot
                if e.id == v.id and not benutzt[platz] then
                    benutzt[platz] = true
                    k = k + 1
                    if handel.vorher[v.id] == nil then handel.vorher[v.id] = anzahlImRucksack(v.id) end
                    pcall(nimm, e.bag, e.slot)
                    pcall(lege, k)
                    break
                end
            end
        end
    end
    local leeren = rawget(_G, "ClearCursor")
    if type(leeren) == "function" then pcall(leeren) end

    if k > 0 then
        angebotLesen(handel, true)
        sag(string.format(L["Für %s liegen %d vorgemerkte Gegenstände im Handelsfenster – bitte prüfen und bestätigen."], partner, k))
    end
end

--- Ein Gegenstand ging an den Handelspartner: eintragen, wenn es eine Vergabe war.
local function handelVerbuchen(H, id, link)
    local V
    for _, v in ipairs(offenListe()) do
        if v.id == id and Kern.GleicherSpieler(v.name, H.partner) then V = v break end
    end

    local z
    if V then
        z = V
    else
        -- Von Hand gehandelt: war ein Wurf bekannt, gilt dessen Art und Zahl.
        local wert, art = ns.Erfassung.WurfVon(H.partner, link)
        if wert and wert > 0 then
            z = { art = art, wert = wert }
        elseif H.tauschbar[id] then
            -- Ein Stueck mit Handelsfrist, ohne bekannten Wurf: sicherer Hauptbedarf.
            z = { ohneWurf = true }
        else
            return
        end
    end

    eintragen(H.partner, link, z)
    if z.ohneWurf then sag(GRAU .. L["Kein Wurf bekannt – als Hauptbedarf eingetragen."] .. "|r") end
    if V then vormerkungLoeschen(V) end
end

--- Das Handelsfenster ist zu: war etwas aus dem Rucksack weg, ist es gehandelt.
local function handelZu()
    local H = handel
    handel = nil
    if not H or not C_Timer then return end
    angebotLesen(H, false)
    if #H.angeboten == 0 then return end

    C_Timer.After(1.5, function()
        local zaehler = {}
        for _, l in ipairs(H.angeboten) do
            local id = idVon(l)
            if id then
                local z = zaehler[id]
                if not z then z = { n = 0, link = l }; zaehler[id] = z end
                z.n = z.n + 1
            end
        end
        for id, z in pairs(zaehler) do
            local vor = H.vorher[id]
            -- Weg aus dem Rucksack = gehandelt (ein abgebrochener Handel laesst alles liegen).
            if vor and anzahlImRucksack(id) <= vor - z.n then
                handelVerbuchen(H, id, z.link)
            end
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
        vormerken(name, link, ort.id, z)
        if handelAnfragen(name) then
            sag(string.format(L["Handel mit %s angefragt – der Gegenstand wird eingelegt, sobald das Fenster offen ist."], name))
        end
        -- ⭐ Auch wenn der Handel jetzt nicht klappt (zu weit weg, offline): Die
        -- Zuteilung bleibt vorgemerkt und wird beim naechsten Handel eingelegt.
        sag(GRAU .. string.format(L["Vorgemerkt: %s für %s. Ist der Spieler zu weit weg, wird der Gegenstand beim nächsten Handel mit ihm automatisch eingelegt. |cffffff78/fs wurf offen|r zeigt alle."], link, name) .. "|r")
    end
    -- Der Wurf ist entschieden; was jetzt noch aussteht, ist nur der Handel.
    ns.Erfassung.RundeBeenden(link)
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
    e.fuss:SetWidth(230)
    e.verwerfen = S.Knopf(e, L["Wurf verwerfen"], "link", 22)
    e.verwerfen:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -16, 12)
    e.verwerfen:SetScript("OnClick", function() Wurf.Abbrechen() end)
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
                     "TRADE_SHOW", "TRADE_CLOSED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE" }) do
    pcall(function() ereignisse:RegisterEvent(e) end)
end
ereignisse:SetScript("OnEvent", function(_, ereignis)
    if ereignis == "TRADE_SHOW" then
        pcall(handelOffen)
    elseif ereignis == "TRADE_CLOSED" then
        pcall(handelZu)
    elseif ereignis == "TRADE_PLAYER_ITEM_CHANGED" or ereignis == "TRADE_ACCEPT_UPDATE" then
        pcall(angebotLesen, handel, true)
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

-- ⭐ Das Ende eines Wurfs darf nicht am Fenster haengen: Wer das Wuerfelfenster
-- mit dem Kreuz schliesst, hat keinen OnUpdate mehr — der Wurf liefe ewig weiter
-- (und jeder spaetere /roll gehoerte noch zum alten Gegenstand).
local ticker = CreateFrame("Frame")
ticker.t = 0
ticker:SetScript("OnUpdate", function(s, dt)
    s.t = s.t + dt
    if s.t < 0.5 then return end
    s.t = 0
    if aktiv and time() >= aktiv.ende then pcall(Wurf.Ende) end
end)

return ns
