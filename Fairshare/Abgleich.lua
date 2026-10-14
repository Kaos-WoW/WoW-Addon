--[[----------------------------------------------------------------------
    Abgleich.lua  —  Historien innerhalb einer Gruppe zusammenfuehren

    ⭐ Ziel (Gildenleiter, 14.10.2026): Jeder im Raid kann die Historie
    einsehen, und wo Staende auseinanderlaufen, fuehrt ein Knopfdruck des
    Leiters oder Pluendermeisters sie zusammen — **ohne je etwas zu
    ueberschreiben**. Merge, kein Ersetzen.

    Vorbilder (CurseForge-Auswertung 14.10.2026):
      * Pruefsumme zuerst, Daten nur wo sie abweichen (RCLootCouncil
        Improved History, CLM)
      * Empfaenger verwirft Unberechtigte still (CLM)
      * jeder Eintrag hat eine feste Kennung; Einfuegen ist idempotent
        (Gargul, Sync-Erweiterungen)

    Ablauf eines Abgleichs:
      1. Hallo   jeder meldet Anzahl und Pruefsumme seiner Historie.
                 Weicht jemand ab, bekommt der Leiter einen Hinweis.
      2. Q       der Leiter schickt seinen Tagesstand (Pruefsumme je Tag).
      3. N, E    jeder vergleicht. Wo ein Tag abweicht, meldet er den Tag
                 (N) und schickt seine Eintraege dazu (E). Der Leiter
                 schickt dann die Tage, die andere gemeldet haben.
      4. Jeder fuehrt ein, was er bekommt (Kern.Zusammenfuehren).

    ⚠️ Doppelte Sendungen werden unterdrueckt: Wer waehrend seiner
    zufaelligen Wartezeit hoert, dass ein anderer dieselben Eintraege
    schon geschickt hat, schweigt.

    ⚠️ Zusaetzlich meldet der Schreiber (Rolle.lua) jede neue Vergabe
    sofort an die Gruppe (L), damit der Abgleich selten noetig ist.

    ⚠️ Eintraege nimmt nur an, wer in unserer Gruppe UND unserer Gilde ist.
    Bei einer Gruppe mit Fremden schleust so niemand Daten ein.
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Abgleich = {}
ns.Abgleich = Abgleich

local Kern = ns.Kern

local PRAEFIX    = "FSHARE"
local VERSION    = 1
local PAKETLAENGE = 215      -- Nutzlast je Nachricht; der Kopf kommt dazu
local TAKT       = 0.25      -- Sekunden zwischen zwei Nachrichten
local MAXEINTRAEGE = 600     -- je Abgleich und Spieler
local SITZUNGSDAUER = 900    -- so lange gilt ein Abgleich als offen

local MELDUNG = "|cff1B6B57Fairshare|r: "

-- =====================================================================
--  Zugriff
-- =====================================================================

local function db() return ns.Erfassung.Einstellungen() end
local function hist() return ns.Erfassung.Historie() end
local function alias() return db().alias end

local function utcTag(t)
    return date("!%Y%m%d", t)
end

local function jetzt()
    return (GetServerTime and GetServerTime()) or time()
end

local function eigenerName()
    if GetUnitName then
        local n = GetUnitName("player", true)
        if n and n ~= "" then return n end
    end
    return (UnitName("player"))
end

local function kanal()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

function Abgleich.Stand()
    return Kern.Pruefsumme(hist(), alias())
end

-- =====================================================================
--  Senden — mit Takt, damit Blizzards Drosselung uns nicht abwuergt
-- =====================================================================

local Warteschlange = {}
local wartezeit = 0

local function senden(text)
    if #text > 250 then return false end

    local f = C_ChatInfo and C_ChatInfo.SendAddonMessage or rawget(_G, "SendAddonMessage")
    local k = kanal()
    if not f or not k then return false end

    local ok, ergebnis = pcall(f, PRAEFIX, text, k)
    if not ok then return false end

    -- Neuere Clients liefern einen Ergebniscode, aeltere nichts oder true.
    -- 0 = Erfolg; 3, 8, 10, 11 = gedrosselt bzw. gesperrt -> spaeter nochmal.
    if ergebnis == nil or ergebnis == true or ergebnis == 0 then return true end
    if ergebnis == 3 or ergebnis == 8 or ergebnis == 10 or ergebnis == 11 then
        return nil
    end
    return false
end

local Takter = CreateFrame("Frame")
Takter:SetScript("OnUpdate", function(_, dt)
    if #Warteschlange == 0 then return end
    wartezeit = wartezeit - dt
    if wartezeit > 0 then return end

    local Eintrag = Warteschlange[1]
    local r = senden(Eintrag.text)
    if r == nil then
        -- gedrosselt: spaeter erneut, aber nicht endlos
        Eintrag.versuche = (Eintrag.versuche or 0) + 1
        if Eintrag.versuche > 6 then table.remove(Warteschlange, 1) end
        wartezeit = 3
        return
    end
    table.remove(Warteschlange, 1)
    wartezeit = TAKT
end)

local function einreihen(text)
    Warteschlange[#Warteschlange + 1] = { text = text }
end

--- Eine Liste durch Kommas teilen, so dass jedes Stueck passt.
local function teilen(text, laenge)
    local stuecke, aktuell = {}, ""
    for teil in (text .. ","):gmatch("(.-),") do
        if teil ~= "" then
            if aktuell ~= "" and #aktuell + 1 + #teil > laenge then
                stuecke[#stuecke + 1] = aktuell
                aktuell = teil
            else
                aktuell = (aktuell == "") and teil or (aktuell .. "," .. teil)
            end
        end
    end
    if aktuell ~= "" then stuecke[#stuecke + 1] = aktuell end
    return stuecke
end

-- =====================================================================
--  Zustand
-- =====================================================================

local Bekannt = {}      -- Spielerschluessel -> { name, n, summe, zeit, version, gilde }
local Sitzungen = {}    -- sid -> { von, zeit, teile, erwartet, tage, gemeldet, gesehen }
local Zaehler = { neu = 0, doppelt = 0, vorhanden = 0, abgelehnt = 0 }
local letzterAbsender = nil
local letzteSignatur = nil

Abgleich.Abweichend = {}

--- Mitspieler, von denen wir wissen, dass sie das Addon haben.
--  @return Menge: Schluessel -> true
function Abgleich.Bekannte()
    local menge, grenze = {}, time() - 3600
    for schluessel, P in pairs(Bekannt) do
        if P.zeit >= grenze then menge[schluessel] = true end
    end
    return menge
end

local function neueSitzung()
    return string.format("%x", (math.random(0x1000000, 0xFFFFFFF) + time()) % 0xFFFFFFF)
end

-- =====================================================================
--  Anzeige
-- =====================================================================

local popup

local function popupVerstecken()
    if popup then popup:Hide() end
end

local function popupZeigen(anzahl, namen)
    if not popup then
        popup = CreateFrame("Frame", "FairshareAbgleich", UIParent, "BackdropTemplate")
        popup:SetSize(380, 150)
        popup:SetPoint("TOP", UIParent, "TOP", 0, -140)
        popup:SetFrameStrata("DIALOG")
        popup:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })

        local kopf = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        kopf:SetPoint("TOP", popup, "TOP", 0, -18)
        kopf:SetText("Fairshare")

        popup.text = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        popup.text:SetPoint("TOPLEFT", popup, "TOPLEFT", 22, -46)
        popup.text:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -22, -46)
        popup.text:SetJustifyH("CENTER")
        popup.text:SetWordWrap(true)

        local ja = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        ja:SetSize(150, 24)
        ja:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 24, 20)
        ja:SetText(L["Jetzt abgleichen"])
        ja:SetScript("OnClick", function()
            popup:Hide()
            local ok, grund = Abgleich.Starten()
            if not ok then print(MELDUNG .. "|cffff5555" .. tostring(grund) .. "|r") end
        end)

        local spaeter = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        spaeter:SetSize(150, 24)
        spaeter:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -24, 20)
        spaeter:SetText(L["Später"])
        spaeter:SetScript("OnClick", function() popup:Hide() end)
    end

    popup.text:SetText(string.format(
        L["Die Loot-Historien in dieser Gruppe sind nicht gleich.\n|cffffff78%d Spieler|r weichen ab.\nEinmal abgleichen führt sie zusammen."],
        anzahl))
    popup:Show()
end

local function fensterAktualisieren()
    if ns.Fenster and ns.Fenster.Sichtbar and ns.Fenster.Sichtbar() then
        ns.Fenster.Aktualisieren()
    end
    if ns.Einstellungen and ns.Einstellungen.Sichtbar and ns.Einstellungen.Sichtbar() then
        ns.Einstellungen.Aktualisieren()
    end
end

--- Vergleicht den eigenen Stand mit dem der Mitspieler.
function Abgleich.Pruefen()
    local n, summe = Abgleich.Stand()
    local liste = {}

    for schluessel, P in pairs(Bekannt) do
        -- Wer nicht mehr in der Gruppe steht, zaehlt nicht.
        local gilde, unit = ns.Rolle.Absender(P.name)
        if not unit then
            Bekannt[schluessel] = nil
        elseif P.version == VERSION and gilde and (P.n ~= n or P.summe ~= summe) then
            liste[#liste + 1] = P.name
        end
    end
    table.sort(liste)
    Abgleich.Abweichend = liste

    if #liste == 0 then
        letzteSignatur = nil
        popupVerstecken()
        fensterAktualisieren()
        return
    end

    local signatur = table.concat(liste, ",")
    if signatur ~= letzteSignatur
       and ns.Rolle.Berechtigt(eigenerName())
       and not (InCombatLockdown and InCombatLockdown()) then
        letzteSignatur = signatur
        if db().autoAbgleich ~= false and C_Timer then
            -- ⭐ Von selbst abgleichen. Kurz warten, bis alle Hallo-Meldungen da
            -- sind, und nur, wenn dann noch jemand abweicht. Hoechstens alle
            -- zwei Minuten: ein Abgleich, der nicht alles ausgleicht, soll
            -- nicht endlos laufen.
            C_Timer.After(4, function()
                if #Abgleich.Abweichend == 0 then return end
                if (time() - (Abgleich.letzterAuto or 0)) < 120 then return end
                Abgleich.letzterAuto = time()
                local ok, grund = Abgleich.Starten()
                if not ok and grund then print(MELDUNG .. "|cffff5555" .. tostring(grund) .. "|r") end
            end)
        else
            popupZeigen(#liste, liste)
        end
    end
    fensterAktualisieren()
end

-- =====================================================================
--  Hallo
-- =====================================================================

local hallo = { token = 0, zuletzt = 0, n = nil, summe = nil }

local function halloSenden()
    if not kanal() then return end
    local n, summe = Abgleich.Stand()

    -- ⚠️ Nicht unnoetig oft: nur bei Aenderung oder nach einer Weile.
    if hallo.n == n and hallo.summe == summe and (time() - hallo.zuletzt) < 60 then
        return
    end
    hallo.n, hallo.summe, hallo.zuletzt = n, summe, time()

    einreihen(string.format("H;%d;%d;%.0f", VERSION, n, summe))   -- %.0f: siehe Kern.TageKodieren
end

--- Hallo in ein paar Sekunden — mehrere Ausloeser ergeben eines.
function Abgleich.HalloSpaeter(sekunden)
    if not C_Timer then return end
    hallo.token = hallo.token + 1
    local mein = hallo.token
    C_Timer.After(sekunden or 6, function()
        if mein == hallo.token then pcall(halloSenden) end
    end)
end

-- =====================================================================
--  Live: jede neue Vergabe sofort
-- =====================================================================

--- Meldet eine frisch eingetragene Vergabe an die Gruppe.
--  ⚠️ Mit Verzoegerung: Gargul oder die Beutemeldung koennen den Eintrag
--  in den ersten Sekunden noch berichtigen. Gesendet wird der Stand danach.
function Abgleich.Verteilen(id)
    if not kanal() or not C_Timer then return end
    C_Timer.After(4, function()
        local e = hist()[id]
        if not e then return end
        einreihen("L;0;" .. Kern.Kodieren(id, e))
        Abgleich.HalloSpaeter(8)
    end)
end

-- =====================================================================
--  Abgleich starten
-- =====================================================================

--- Sendet die eigenen Eintraege fuer die genannten Tage.
local function eintraegeSenden(sid, tage)
    local S = Sitzungen[sid]
    local H = hist()

    local ids = {}
    for id, e in pairs(H) do
        if tage[utcTag(e.timestamp or 0)] and not (S and S.gesehen[id]) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids, function(a, b) return (H[a].timestamp or 0) < (H[b].timestamp or 0) end)

    if #ids > MAXEINTRAEGE then
        for i = #ids, MAXEINTRAEGE + 1, -1 do ids[i] = nil end
    end

    local zeilen = {}
    for _, id in ipairs(ids) do zeilen[#zeilen + 1] = Kern.Kodieren(id, H[id]) end

    for _, paket in ipairs(Kern.Pakete(zeilen, PAKETLAENGE)) do
        einreihen("E;" .. sid .. ";" .. paket)
    end
    return #ids
end

--- Startet einen Abgleich. Nur Leiter, Assistenten und Pluendermeister.
--  @return true, oder false und ein Grund
function Abgleich.Starten()
    if not kanal() then return false, L["Du bist in keiner Gruppe."] end
    if not ns.Rolle.Berechtigt(eigenerName()) then
        return false, L["Nur Leiter, Assistenten und der Plündermeister dürfen abgleichen."]
    end

    local sid = neueSitzung()
    local tage = Kern.Tagesstand(hist(), alias(), utcTag)
    Sitzungen[sid] = {
        von = "ich", zeit = time(), gemeldet = {}, gesehen = {}, tage = tage, eigene = true,
    }
    Zaehler = { neu = 0, doppelt = 0, vorhanden = 0, abgelehnt = 0 }

    local stuecke = teilen(Kern.TageKodieren(tage), 190)
    if #stuecke == 0 then stuecke = { "" } end
    for i, st in ipairs(stuecke) do
        einreihen(string.format("Q;%s;%d;%d;%s", sid, i, #stuecke, st))
    end

    print(MELDUNG .. L["Abgleich gestartet – ich warte auf die Antworten der Gruppe."])
    Abgleich.AbschlussMelden()
    return true
end

local abschluss = { token = 0 }

--- Nach einer Ruhepause sagen, was dabei herauskam.
function Abgleich.AbschlussMelden()
    if not C_Timer then return end
    abschluss.token = abschluss.token + 1
    local mein = abschluss.token
    C_Timer.After(25, function()
        if mein ~= abschluss.token then return end
        local z = Zaehler
        if z.neu + z.doppelt + z.vorhanden + z.abgelehnt == 0 then
            print(MELDUNG .. L["Abgleich beendet – es kam nichts Neues an."])
        else
            print(string.format(MELDUNG .. L["Abgleich beendet: |cff55ff55%d neu|r übernommen, %d schon vorhanden, %d als Doppelgänger erkannt%s."],
                z.neu, z.vorhanden, z.doppelt,
                z.abgelehnt > 0 and string.format(L[", |cffff5555%d abgelehnt|r"], z.abgelehnt) or ""))
        end
        fensterAktualisieren()
        Abgleich.HalloSpaeter(2)
    end)
end

-- =====================================================================
--  Empfangen
-- =====================================================================

local function einfuehren(zeilen, herkunft)
    local liste, abgelehnt = {}, 0
    for _, z in ipairs(zeilen) do
        local id, e = Kern.Dekodieren(z, jetzt())
        if id then
            e.herkunft = herkunft
            liste[#liste + 1] = { id = id, e = e }
        else
            abgelehnt = abgelehnt + 1
        end
    end

    local neu, doppelt, vorhanden, abg, zurueck = Kern.Zusammenfuehren(hist(), alias(), liste, 180)
    Zaehler.neu = Zaehler.neu + neu
    Zaehler.doppelt = Zaehler.doppelt + doppelt
    Zaehler.vorhanden = Zaehler.vorhanden + vorhanden
    Zaehler.abgelehnt = Zaehler.abgelehnt + abg + abgelehnt
    Zaehler.zurueck = (Zaehler.zurueck or 0) + (zurueck or 0)
    return liste
end

local function sitzungHolen(sid)
    local S = Sitzungen[sid]
    if S and (time() - S.zeit) > SITZUNGSDAUER then
        Sitzungen[sid] = nil
        return nil
    end
    return S
end

--- Ein Tagesstand des Leiters ist vollstaendig da: vergleichen und antworten.
local function aufQReagieren(sid, S)
    local fremd = Kern.TageDekodieren(table.concat(S.teile, ","))
    local lokal = Kern.Tagesstand(hist(), alias(), utcTag)
    local abw = Kern.AbweichendeTage(lokal, fremd)
    if #abw == 0 then return end

    local menge = {}
    for _, t in ipairs(abw) do menge[t] = true end

    if not C_Timer then return end

    -- Zufaellig gestaffelt, damit nicht alle gleichzeitig senden — wer
    -- inzwischen gehoert hat, dass es schon da ist, schweigt.
    C_Timer.After(0.5 + math.random() * 2.5, function()
        local noetig = {}
        for _, t in ipairs(abw) do
            if not S.gemeldet[t] then noetig[#noetig + 1] = t end
        end
        if #noetig == 0 then return end
        for _, t in ipairs(noetig) do S.gemeldet[t] = true end
        for _, stueck in ipairs(teilen(table.concat(noetig, ","), 200)) do
            einreihen("N;" .. sid .. ";" .. stueck)
        end
    end)

    C_Timer.After(1.5 + math.random() * 4, function()
        eintraegeSenden(sid, menge)
    end)
end

local function aufNReagieren(sid, S, text)
    -- Nur der Leiter, der den Abgleich begonnen hat, schickt nach.
    for t in text:gmatch("[^,]+") do S.gemeldet[t] = true end
    if not S.eigene or not C_Timer then return end

    S.nachToken = (S.nachToken or 0) + 1
    local mein = S.nachToken
    C_Timer.After(3, function()
        if mein ~= S.nachToken then return end
        local tage = {}
        for t in pairs(S.gemeldet) do tage[t] = true end
        eintraegeSenden(sid, tage)
    end)
end

--- Eine Addon-Nachricht ist eingetroffen.
function Abgleich.Empfangen(text, sender)
    if type(text) ~= "string" then return end
    letzterAbsender = sender

    local typ, rest = text:match("^(%a);(.*)$")
    if not typ then return end

    local gilde, unit = ns.Rolle.Absender(sender)
    if not unit then return end                         -- nicht in unserer Gruppe
    if UnitIsUnit and UnitIsUnit(unit, "player") then return end   -- das waren wir

    local name = (GetUnitName and GetUnitName(unit, true)) or sender

    if typ == "H" then
        local v, n, summe = rest:match("^(%d+);(%d+);(%d+)")
        if not v then return end
        Bekannt[Kern.Schluessel(name)] = {
            name = name, version = tonumber(v), n = tonumber(n),
            summe = tonumber(summe), zeit = time(), gilde = gilde,
        }
        Abgleich.Pruefen()
        return
    end

    -- Alles Weitere nur von Gildenmitgliedern
    if not gilde then return end

    if typ == "L" then
        -- Neue Vergabe vom Schreiber: nur von Leiter, Assistent, Pluendermeister
        local _, zeile = rest:match("^([^;]*);(.*)$")
        if not zeile or not ns.Rolle.Berechtigt(name) then return end
        einfuehren({ zeile }, "gruppe")
        fensterAktualisieren()
        Abgleich.HalloSpaeter(8)

    elseif typ == "Q" then
        if not ns.Rolle.Berechtigt(name) then return end
        local sid, k, gesamt, stueck = rest:match("^([^;]*);(%d+);(%d+);(.*)$")
        k, gesamt = tonumber(k), tonumber(gesamt)
        if not sid or not k or not gesamt or gesamt < 1 or gesamt > 60 or k > gesamt then return end

        local S = Sitzungen[sid]
        if not S then
            S = { von = name, zeit = time(), teile = {}, gemeldet = {}, gesehen = {}, erhalten = 0 }
            Sitzungen[sid] = S
            Zaehler = { neu = 0, doppelt = 0, vorhanden = 0, abgelehnt = 0 }
        end
        if S.teile and not S.teile[k] then
            S.teile[k] = stueck
            S.erhalten = (S.erhalten or 0) + 1
            if S.erhalten == gesamt then
                -- Reihenfolge herstellen
                local geordnet = {}
                for i = 1, gesamt do geordnet[i] = S.teile[i] or "" end
                S.teile = geordnet
                aufQReagieren(sid, S)
                Abgleich.AbschlussMelden()
            end
        end

    elseif typ == "N" then
        local sid, tage = rest:match("^([^;]*);(.*)$")
        local S = sid and sitzungHolen(sid)
        if S and tage then aufNReagieren(sid, S, tage) end

    elseif typ == "E" then
        local sid, paket = rest:match("^([^;]*);(.*)$")
        local S = sid and sitzungHolen(sid)
        if not S or not paket then return end

        local zeilen = Kern.Entpacken(paket)
        if #zeilen > 40 then return end
        local liste = einfuehren(zeilen, "abgleich")
        for _, X in ipairs(liste) do S.gesehen[X.id] = true end
        Abgleich.AbschlussMelden()
        fensterAktualisieren()
    end
end

-- =====================================================================
--  Diagnose
-- =====================================================================

function Abgleich.Diagnose()
    local n, summe = Abgleich.Stand()
    local zeilen = {}
    zeilen[#zeilen + 1] = string.format(L["Eigener Stand: %d Einträge, Prüfsumme %s, %d Doppelgänger vermerkt"],
        n, string.format("%.0f", summe), (function() local c = 0 for _ in pairs(alias()) do c = c + 1 end return c end)())
    zeilen[#zeilen + 1] = string.format(L["Kanal: %s"], tostring(kanal() or L["keiner (nicht in einer Gruppe)"]))

    local anz = 0
    for _, P in pairs(Bekannt) do
        anz = anz + 1
        zeilen[#zeilen + 1] = string.format(L["  %s: %d Einträge, Prüfsumme %s%s%s"],
            P.name, P.n, string.format("%.0f", P.summe),
            (P.n == n and P.summe == summe) and (" " .. L["|cff55ff55gleich|r"]) or (" " .. L["|cffffff78weicht ab|r"]),
            P.gilde and "" or (" " .. L["(nicht in der Gilde)"]))
    end
    zeilen[#zeilen + 1] = string.format(L["Mitspieler mit Addon: %d"], anz)
    zeilen[#zeilen + 1] = string.format(L["Letzter Absender (roh): %s"], tostring(letzterAbsender))
    if letzterAbsender then
        local gilde, unit = ns.Rolle.Absender(letzterAbsender)
        zeilen[#zeilen + 1] = string.format(L["  zugeordnet zu: %s, Gilde: %s"],
            tostring(unit), tostring(gilde))
    end
    zeilen[#zeilen + 1] = string.format(L["Nachrichten in der Warteschlange: %d"], #Warteschlange)
    return zeilen
end

-- =====================================================================
--  Ereignisse
-- =====================================================================

local function praefixAnmelden()
    local f = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix
              or rawget(_G, "RegisterAddonMessagePrefix")
    if f then pcall(f, PRAEFIX) end
end
praefixAnmelden()

local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("CHAT_MSG_ADDON")
rahmen:RegisterEvent("GROUP_ROSTER_UPDATE")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:SetScript("OnEvent", function(_, ereignis, praefix, text, _, sender)
    local ok, fehler = pcall(function()
        if ereignis == "CHAT_MSG_ADDON" then
            if praefix == PRAEFIX then Abgleich.Empfangen(text, sender) end
        elseif ereignis == "GROUP_ROSTER_UPDATE" then
            Abgleich.HalloSpaeter(6)
            Abgleich.Pruefen()
        else
            praefixAnmelden()
            Abgleich.HalloSpaeter(10)
        end
    end)
    if not ok then
        print(MELDUNG .. "|cffff5555" .. string.format(L["Fehler im Abgleich: %s"], tostring(fehler)) .. "|r")
    end
end)

return ns
