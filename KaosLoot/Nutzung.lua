--[[----------------------------------------------------------------------
    Nutzung.lua  —  „KaosLoot nutzen?"

    ⭐ Entscheid des Gildenleiters (15.10.2026): KaosLoot ist nur im Dienst,
    wenn die Beutemethode der Gruppe **Plündermeister** ist UND der Spieler
    ausdrücklich zugestimmt hat. Sonst schläft das Addon: keine Fenster,
    keine Aufzeichnung, keine Verwaltung der Vergabe, kein Abgleich.

      * Wird die Beutemethode auf Plündermeister gestellt (oder man tritt
        einer solchen Gruppe bei), fragt ein Dialog einmal: *KaosLoot nutzen?*
      * **Ja**   → alles läuft wie gewohnt (Rolle.Aktiv() = true).
      * **Nein** → das Addon schläft, bis die Beutemethode wechselt oder man
                   die Gruppe verlässt.
      * Das Kreuz/Esc schließt den Dialog ohne Antwort: das Addon schläft
        weiter, gefragt wird nicht noch einmal (`/fs nutzung` fragt neu).
      * Jede andere Beutemethode (Gruppenbeute, Bedarf vor Gier, Reihum,
        Jeder gegen Jeden, persönliche Beute) oder keine Gruppe: Die Antwort
        wird vergessen, das Addon schläft.

    Die Antwort liegt in `FairshareDB.nutzung` ("ja" | "nein" | nil) und
    überlebt /reload und Abmelden, solange man in derselben Gruppe mit
    Plündermeister bleibt. Gelesen wird sie über `Rolle.Nutzung()`.
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L
local S = ns.Stil
local C = S.C

local Nutzung = {}
ns.Nutzung = Nutzung

local dialog
local gefragt = false      -- in dieser Gruppe schon gefragt (nicht nochmal aufdrängen)

-- =====================================================================
--  Der Dialog
-- =====================================================================

local function dialogBauen()
    if dialog then return dialog end
    local p = CreateFrame("Frame", "FairshareNutzung", UIParent)
    dialog = p
    p:SetSize(390, 230)
    p:SetPoint("TOP", UIParent, "TOP", 0, -150)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel(80)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    S.Kasten(p, 10, C.bg, C.ln)

    -- Kopfleiste: Logo, Titel, Kreuz
    local k = CreateFrame("Frame", nil, p)
    k:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
    k:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -1)
    k:SetHeight(32)
    S.Form(k, 9, C.p1, nil, "BACKGROUND", 0, 0, { tl = true, tr = true })
    local linie = S.Tex(k, "BORDER", C.ln)
    linie:SetHeight(1)
    linie:SetPoint("BOTTOMLEFT")
    linie:SetPoint("BOTTOMRIGHT")

    local logo = CreateFrame("Frame", nil, k)
    logo:SetSize(18, 18)
    logo:SetPoint("LEFT", k, "LEFT", 12, 0)
    S.Form(logo, 4, C.ac)
    local l = S.Text(logo, 11, C.white, "CENTER")
    l:SetPoint("CENTER", 1, 0)
    l:SetText("F")

    local titel = S.Text(k, 13, C.tx, "LEFT")
    titel:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    titel:SetText(L["KaosLoot nutzen?"])

    local zu = CreateFrame("Button", nil, k)
    zu:SetSize(20, 20)
    zu:SetPoint("RIGHT", k, "RIGHT", -10, 0)
    local x = S.Symbol(zu, "x.tga", 16, C.mu)
    x:SetPoint("CENTER")
    zu:SetScript("OnEnter", function() S.Faerbe(x, C.tx) end)
    zu:SetScript("OnLeave", function() S.Faerbe(x, C.mu) end)
    zu:SetScript("OnClick", function() p:Hide() end)   -- ohne Antwort: das Addon schläft weiter

    -- Text
    p.frage = S.Text(p, 14, C.tx, "LEFT", true)
    p.frage:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -46)
    p.frage:SetWidth(354)
    p.frage:SetText(L["Die Beutemethode dieser Gruppe ist Plündermeister. Soll KaosLoot die Beuteverteilung verwalten?"]
        .. " " .. L["Deine Antwort gilt für alle in der Gruppe, die das Addon haben."])

    p.ja = S.Text(p, 12, C.mu, "LEFT", true)
    p.ja:SetPoint("TOPLEFT", p.frage, "BOTTOMLEFT", 0, -12)
    p.ja:SetWidth(354)
    p.ja:SetText(S.Code(C.ok) .. L["Ja:"] .. "|r " .. L["Würfelfenster, Aufzeichnung und Zuteilen laufen über das Addon."])

    p.nein = S.Text(p, 12, C.mu, "LEFT", true)
    p.nein:SetPoint("TOPLEFT", p.ja, "BOTTOMLEFT", 0, -8)
    p.nein:SetWidth(354)
    p.nein:SetText(S.Code(C.warn) .. L["Nein:"] .. "|r " ..
        L["KaosLoot schläft: keine Fenster, keine Aufzeichnung, keine Verwaltung – bis die Beutemethode wechselt oder du die Gruppe verlässt."])

    -- Knöpfe
    local jaK = S.Knopf(p, L["Ja, KaosLoot nutzen"], "primary", 30)
    jaK:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 18, 16)
    jaK:SetScript("OnClick", function() ns.Rolle.NutzungSetzen("ja") end)
    local neinK = S.Knopf(p, L["Nein"], "secondary", 30)
    neinK:SetPoint("LEFT", jaK, "RIGHT", 10, 0)
    neinK:SetScript("OnClick", function() ns.Rolle.NutzungSetzen("nein") end)
    p.jaKnopf, p.neinKnopf = jaK, neinK

    if UISpecialFrames then table.insert(UISpecialFrames, "FairshareNutzung") end
    p:Hide()
    return p
end

--- Höhe an den Text anpassen (Übersetzungen sind unterschiedlich lang).
local function dialogMessen(p)
    local h = 46 + 12 + 8 + 30 + 16 + 14
    for _, fs in ipairs({ p.frage, p.ja, p.nein }) do
        local fh = fs.GetStringHeight and fs:GetStringHeight()
        h = h + ((type(fh) == "number" and fh > 0) and fh or 34)
    end
    p:SetHeight(math.max(190, math.ceil(h)))
end

--- Den Dialog zeigen (auch von Hand: `/fs nutzung`).
function Nutzung.Fragen()
    local p = dialogBauen()
    gefragt = true
    p:Show()
    dialogMessen(p)
    return true
end

--- Der Dialog (für Tests), nil solange noch nie gefragt wurde.
function Nutzung.Dialog()
    return dialog
end

function Nutzung.Sichtbar()
    return dialog ~= nil and dialog:IsShown() and true or false
end

-- =====================================================================
--  Auswerten: wann wird gefragt, wann vergessen?
-- =====================================================================

local function fensterAuffrischen()
    pcall(function()
        if ns.Fenster and ns.Fenster.Sichtbar and ns.Fenster.Sichtbar() then ns.Fenster.Aktualisieren() end
        if ns.Einstellungen and ns.Einstellungen.Sichtbar and ns.Einstellungen.Sichtbar() then
            ns.Einstellungen.Aktualisieren()
        end
    end)
end

--- Eine Antwort ist gefallen (oder zurückgenommen).
--  Von Rolle.NutzungSetzen aufgerufen.
function Nutzung.Entschieden(wert)
    if dialog then dialog:Hide() end
    if wert == "ja" then
        gefragt = true
        if C_Timer then
            -- Wie bei einem Beitritt: melden, Abweichungen suchen, geteilte Einstellungen holen.
            pcall(ns.Abgleich.HalloSpaeter, 2)
            C_Timer.After(6, function()
                if ns.Rolle.Aktiv() and ns.Konfig then pcall(ns.Konfig.Anfragen, nil) end
            end)
        end
    elseif wert == "nein" then
        gefragt = true
        pcall(ns.Abgleich.Pruefen)     -- räumt Hinweis und Liste weg
    else
        gefragt = false
    end
    fensterAuffrischen()
end

local letzteVerkuendung = 0
local protokoll = {}

local function merke(text)
    protokoll[#protokoll + 1] = date("%H:%M:%S", time()) .. "  " .. text
    if #protokoll > 6 then table.remove(protokoll, 1) end
end

--- Die letzten Meldungen zu „KaosLoot nutzen?“ (Diagnose).
function Nutzung.Protokoll()
    return protokoll
end

--- ⭐ Der Plündermeister meldet seine Antwort an die Gruppe (`U;ja` oder `U;nein`): Alle mit dem Addon
--  übernehmen sie, ohne selbst gefragt zu werden. Nur der Plündermeister sendet; wiederholt wird es,
--  wenn sich die Gruppe ändert (damit auch Nachzügler es erfahren).
--  @param spaeter  true: höchstens alle 5 s (bei vielen Gruppenmeldungen hintereinander)
function Nutzung.Verkuenden(spaeter)
    local v = ns.Rolle.Nutzung()
    if not v then return false end
    if not ns.Rolle.IchBinPluendermeister() then return false end
    if spaeter and (time() - letzteVerkuendung) < 5 then return false end
    letzteVerkuendung = time()
    return ns.Abgleich.Senden("U;" .. v, true) and true or false
end

--- Eine Meldung `U` ist eingetroffen. Es zählt nur der Plündermeister der eigenen Gruppe; eine eigene
--  Entscheidung des Spielers bleibt unberührt.
function Nutzung.Empfangen(rest, sender, unit)
    if not unit or type(rest) ~= "string" then merke("U von " .. tostring(sender) .. ": sender not in the group") return end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return end
    if ns.Rolle.Methode() ~= "master" then merke("U: loot method is not master looter") return end
    local name = (GetUnitName and GetUnitName(unit, true)) or sender
    if not ns.Rolle.IstPluendermeister(name) then merke("U von " .. tostring(name) .. ": not the master looter") return end

    local wert = rest:match("^(%a+)")
    if wert ~= "ja" and wert ~= "nein" then return end
    local d = ns.Erfassung.Einstellungen()
    if d.nutzung ~= nil and d.nutzungQuelle ~= "leiter" then merke("U " .. wert .. ": own decision stays") return end
    if d.nutzung == wert then return end                                      -- nichts Neues
    merke("U " .. wert .. " from master looter " .. tostring(name) .. " adopted")
    ns.Rolle.NutzungSetzen(wert, "leiter")
    print("|cff1B6B57KaosLoot|r: " .. string.format(
        wert == "ja" and L["Der Plündermeister %s hat KaosLoot für diese Gruppe eingeschaltet."]
                     or L["Der Plündermeister %s hat KaosLoot für diese Gruppe ausgeschaltet."],
        tostring(name)))
end

--- Gruppe oder Beutemethode haben sich geändert (oder wir sind gerade angemeldet).
function Nutzung.Auswerten()
    local gruppe = IsInGroup and IsInGroup()
    local methode = ns.Rolle.Methode()

    -- Methode nicht lesbar: nichts anfassen (lieber still als falsch).
    if gruppe and methode == nil then return end

    if not gruppe or methode ~= "master" then
        -- Keine Gruppe oder eine andere Beutemethode: Antwort vergessen, schlafen.
        local d = ns.Erfassung.Einstellungen()
        local hatteAntwort = d.nutzung ~= nil
        d.nutzung = nil
        d.nutzungQuelle = nil
        gefragt = false
        if dialog then dialog:Hide() end
        pcall(ns.Abgleich.Pruefen)
        if hatteAntwort then fensterAuffrischen() end
        return
    end

    -- ⭐ Gefragt wird NUR der Plündermeister. Alle anderen übernehmen seine Antwort (Nachricht `U`).
    if ns.Rolle.IchBinPluendermeister() then
        if ns.Rolle.Nutzung() == nil and not gefragt then
            Nutzung.Fragen()
        elseif ns.Rolle.Nutzung() ~= nil and C_Timer then
            -- Gruppe hat sich geändert: Antwort erneut melden, damit Nachzügler sie bekommen
            C_Timer.After(2, function() pcall(Nutzung.Verkuenden, true) end)
        end
    end
end

local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:RegisterEvent("GROUP_ROSTER_UPDATE")
pcall(function() rahmen:RegisterEvent("PARTY_LOOT_METHOD_CHANGED") end)
rahmen:SetScript("OnEvent", function(_, ereignis)
    local ok, fehler = pcall(function()
        if ereignis == "PLAYER_ENTERING_WORLD" then
            -- Gruppe und Beutemethode brauchen nach dem Anmelden einen Moment.
            if C_Timer then C_Timer.After(4, function() pcall(Nutzung.Auswerten) end) end
        else
            Nutzung.Auswerten()
        end
    end)
    if not ok then
        print("|cff1B6B57KaosLoot|r: |cffff5555" .. string.format(L["Fehler bei der Abfrage: %s"], tostring(fehler)) .. "|r")
    end
end)

return ns
