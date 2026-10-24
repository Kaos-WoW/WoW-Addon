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
        (Sync-Erweiterungen)

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
-- 2: die Pruefsumme zaehlt „zurueckgenommen" mit (14.10.2026). Staende mit 1
-- werden nicht verglichen, sonst wuerden sie ewig als „abweichend" gelten.
-- 3: das Datenbuch (Abschluesse, Zuschlaege, Anhebungen) wird mitverteilt (16.10.2026);
-- Hallo traegt dessen Stand, Eintraege ein Kennzeichen. Staende mit 2 werden nicht verglichen.
local VERSION    = 3
local PAKETLAENGE = 215      -- Nutzlast je Nachricht; der Kopf kommt dazu
local TAKT       = 0.25      -- Sekunden zwischen zwei Nachrichten
local MAXEINTRAEGE = 600     -- je Abgleich und Spieler
local SITZUNGSDAUER = 900    -- so lange gilt ein Abgleich als offen

local MELDUNG = "|cff1B6B57KaosLoot|r: "

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

--- Das Datenbuch (Abende, Zuschlaege, Anhebungen) — siehe Kern.Buch*.
local function buchDaten()
    return ns.Anwesenheit and ns.Anwesenheit.Daten and ns.Anwesenheit.Daten() or nil
end

function Abgleich.BuchStand()
    local d = buchDaten()
    if not d then return 0, 0 end
    return Kern.BuchStand(d)
end

-- =====================================================================
--  Senden — mit Takt, damit Blizzards Drosselung uns nicht abwuergt
-- =====================================================================

local Warteschlange = {}
local wartezeit = 0

--  @param kanalName  nil = die Gruppe, sonst z. B. "GUILD" (Einstellungen teilen, Konfig.lua)
local function senden(text, kanalName)
    if ns.Probe and ns.Probe.Aktiv and ns.Probe.Aktiv() then return false end
    if #text > 250 then return false end

    local f = C_ChatInfo and C_ChatInfo.SendAddonMessage or rawget(_G, "SendAddonMessage")
    local k = kanalName or kanal()
    -- "WHISPER:<Name>": eine Nachricht nur an diesen Spieler (Leitungs-Abgleich)
    local ziel
    if type(k) == "string" and k:sub(1, 8) == "WHISPER:" then ziel, k = k:sub(9), "WHISPER" end
    if kanalName == "GUILD" and not (IsInGuild and IsInGuild()) then return false end
    if not f or not k then return false end

    local ok, ergebnis = pcall(f, PRAEFIX, text, k, ziel)
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
    local r = senden(Eintrag.text, Eintrag.kanal)
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

local function einreihen(text, kanalName)
    if ns.Probe and ns.Probe.Aktiv and ns.Probe.Aktiv() then return end
    Warteschlange[#Warteschlange + 1] = { text = text, kanal = kanalName }
end

--- Leert die Warteschlange (z. B. beim Start oder Ende des Probe-Modus).
function Abgleich.WarteschlangeLeeren()
    for i = #Warteschlange, 1, -1 do Warteschlange[i] = nil end
    wartezeit = 0
end

--- Fuer andere Dateien (Wurf.lua): eine Nachricht an die Gruppe.
--  @param vorn  vor allen wartenden Abgleich-Nachrichten senden
--  @param kanalName  nil = die Gruppe, "GUILD" = die Gilde
--  @return true, oder false ohne Gruppe (bzw. Gilde)
function Abgleich.Senden(text, vorn, kanalName)
    if not (kanalName or kanal()) then return false end
    if kanalName == "GUILD" and not (IsInGuild and IsInGuild()) then return false end
    if vorn then
        table.insert(Warteschlange, 1, { text = text, kanal = kanalName })
        wartezeit = 0
    else
        einreihen(text, kanalName)
    end
    return true
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
        kopf:SetText("KaosLoot")

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
    -- Ohne Plündermeister als Beutemethode ruht das Addon: kein Hinweis, kein Abgleich.
    if not ns.Rolle.Aktiv() then
        Abgleich.Abweichend = {}
        letzteSignatur = nil
        popupVerstecken()
        return
    end
    local n, summe = Abgleich.Stand()
    local bn, bsumme = Abgleich.BuchStand()
    local liste = {}

    for schluessel, P in pairs(Bekannt) do
        -- Wer nicht mehr in der Gruppe steht, zaehlt nicht.
        local gilde, unit = ns.Rolle.Absender(P.name)
        if not unit then
            Bekannt[schluessel] = nil
        elseif P.version == VERSION and gilde
               and (P.n ~= n or P.summe ~= summe or P.bn ~= bn or P.bsumme ~= bsumme) then
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
            local versuche
            versuche = function()
                if #Abgleich.Abweichend == 0 then return end
                -- Zu frueh nach dem letzten Lauf: spaeter nochmal pruefen, statt
                -- die Abweichung bis zur naechsten Aenderung liegenzulassen.
                local rest = 120 - (time() - (Abgleich.letzterAuto or 0))
                if rest > 0 then
                    C_Timer.After(rest + 1, versuche)
                    return
                end
                Abgleich.letzterAuto = time()
                local ok, grund = Abgleich.Starten()
                if not ok and grund then print(MELDUNG .. "|cffff5555" .. tostring(grund) .. "|r") end
            end
            C_Timer.After(4, versuche)
        else
            popupZeigen(#liste, liste)
        end
    end
    fensterAktualisieren()
end

-- =====================================================================
--  Hallo
-- =====================================================================

local hallo = { token = 0, zuletzt = 0, n = nil, summe = nil, bn = nil, bsumme = nil }

local function halloSenden()
    if not kanal() or not ns.Rolle.Aktiv() then return end
    local n, summe = Abgleich.Stand()
    local bn, bsumme = Abgleich.BuchStand()

    -- ⚠️ Nicht unnoetig oft: nur bei Aenderung oder nach einer Weile.
    if hallo.n == n and hallo.summe == summe and hallo.bn == bn and hallo.bsumme == bsumme
       and (time() - hallo.zuletzt) < 60 then
        return
    end
    hallo.n, hallo.summe, hallo.bn, hallo.bsumme, hallo.zuletzt = n, summe, bn, bsumme, time()

    -- %.0f: siehe Kern.TageKodieren. Nach den Eintraegen folgt der Stand des Datenbuchs.
    einreihen(string.format("H;%d;%d;%.0f;%d;%.0f", VERSION, n, summe, bn, bsumme))
end

--- Hallo in ein paar Sekunden — mehrere Ausloeser ergeben eines.
function Abgleich.HalloSpaeter(sekunden)
    if not C_Timer then return end
    if Abgleich.LeitungBeaconSpaeter then Abgleich.LeitungBeaconSpaeter((sekunden or 6) + 10) end
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
--  ⚠️ Mit Verzoegerung: Blizzards Historie oder die Beutemeldung koennen den Eintrag
--  in den ersten Sekunden noch berichtigen. Gesendet wird der Stand danach.
function Abgleich.Verteilen(id)
    if Abgleich.LeitungBeaconSpaeter then Abgleich.LeitungBeaconSpaeter(20) end
    if not kanal() or not C_Timer then return end
    C_Timer.After(4, function()
        local e = hist()[id]
        if not e then return end
        einreihen("L;0;" .. Kern.Kodieren(id, e))
        Abgleich.HalloSpaeter(8)
    end)
end

--- ⭐ Datenbuch live: geaenderte Saetze (Abschluss eines Abends, Anhebung) sofort an die
--  Gruppe. Wer nicht dabei war, bekommt sie beim naechsten Abgleich.
--  @param items  z. B. { "a:2026-10-16@2", "h:h_kaos_123" }
function Abgleich.BuchVerteilen(items)
    if Abgleich.LeitungBeaconSpaeter then Abgleich.LeitungBeaconSpaeter(15) end     -- auch ohne Gruppe: die Leitung erfährt es
    if not kanal() or not ns.Rolle.Aktiv() or type(items) ~= "table" then return end
    local d = buchDaten()
    if not d then return end
    for _, paket in ipairs(Kern.Pakete(Kern.BuchZeilen(d, items), PAKETLAENGE)) do
        einreihen("D;0;" .. paket)
    end
    if C_Timer then Abgleich.HalloSpaeter(8) end
end

-- =====================================================================
--  Abgleich starten
-- =====================================================================

--- ⭐ Schluessel fuer „diesen Eintrag hat schon jemand geschickt".
--  Der Zustand gehoert dazu: Hat einer den Eintrag noch als NICHT zurueckgenommen
--  geschickt, darf das die Sendung dessen nicht unterdruecken, der ihn als
--  zurueckgenommen kennt — sonst erfuehre es nie jemand (Fund im Szenario 23).
local function gesehenSchluessel(id, e)
    return id .. ((e and e.zurueck) and "!" or "")
end

--- Sendet die eigenen Eintraege fuer die genannten Tage.
local function eintraegeSenden(sid, tage)
    local S = Sitzungen[sid]
    local H = hist()

    local ids = {}
    for id, e in pairs(H) do
        if tage[utcTag(e.timestamp or 0)] and not (S and S.gesehen[gesehenSchluessel(id, e)]) then
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
        einreihen("E;" .. sid .. ";" .. paket, S and S.kanal)
    end
    return #ids
end

--- Legt eine Sitzung an und sendet Tagesstand (Q) und Liste des Datenbuchs (Y).
--  @param kanalName  nil = die Gruppe, "WHISPER:<Name>" = Leitungs-Abgleich mit diesem Spieler
local function sitzungStarten(kanalName)
    local sid = neueSitzung()
    local tage = Kern.Tagesstand(hist(), alias(), utcTag)
    Sitzungen[sid] = {
        von = "ich", zeit = time(), gemeldet = {}, gesehen = {}, tage = tage, eigene = true, kanal = kanalName,
    }
    Zaehler = { neu = 0, doppelt = 0, vorhanden = 0, abgelehnt = 0 }

    local stuecke = teilen(Kern.TageKodieren(tage), 190)
    if #stuecke == 0 then stuecke = { "" } end
    for i, st in ipairs(stuecke) do
        einreihen(string.format("Q;%s;%d;%d;%s", sid, i, #stuecke, st), kanalName)
    end

    -- Das Datenbuch (Abschluesse, Anhebungen) gleicht in derselben Sitzung ab:
    -- Y = meine Liste, M = „das fehlt mir", D = die Saetze selbst.
    local d = buchDaten()
    if d then
        local buchStuecke = teilen(table.concat(Kern.BuchListe(d), ","), 190)
        if #buchStuecke == 0 then buchStuecke = { "" } end
        for i, st in ipairs(buchStuecke) do
            einreihen(string.format("Y;%s;%d;%d;%s", sid, i, #buchStuecke, st), kanalName)
        end
    end
    return sid
end

--- Startet einen Abgleich. Nur Leiter, Assistenten und Pluendermeister.
--  @return true, oder false und ein Grund
function Abgleich.Starten()
    if not kanal() then return false, L["Du bist in keiner Gruppe."] end
    if not ns.Rolle.Berechtigt(eigenerName()) then
        return false, L["Nur Leiter, Assistenten und der Plündermeister dürfen abgleichen."]
    end
    sitzungStarten(nil)
    print(MELDUNG .. L["Abgleich gestartet – ich warte auf die Antworten der Gruppe."])
    Abgleich.AbschlussMelden()
    return true
end

local abschluss = { token = 0, tokenLeise = 0 }

--- Nach einer Ruhepause sagen, was dabei herauskam.
--  @param leise  Leitungs-Abgleich: nur melden, wenn etwas Neues ankam
function Abgleich.AbschlussMelden(leise)
    if not C_Timer then return end
    local feld = leise and "tokenLeise" or "token"
    abschluss[feld] = abschluss[feld] + 1
    local mein = abschluss[feld]
    C_Timer.After(25, function()
        if mein ~= abschluss[feld] then return end
        local z = Zaehler
        if leise then
            if z.neu + (z.buch or 0) > 0 then
                print(MELDUNG .. string.format(L["Mit der Leitung abgeglichen: %d neue Einträge, %d Sätze im Datenbuch."], z.neu, z.buch or 0))
            end
        elseif z.neu + z.doppelt + z.vorhanden + z.abgelehnt + (z.buch or 0) == 0 then
            print(MELDUNG .. L["Abgleich beendet – es kam nichts Neues an."])
        else
            print(string.format(MELDUNG .. L["Abgleich beendet: |cff55ff55%d neu|r übernommen, %d schon vorhanden, %d als Doppelgänger erkannt%s."],
                z.neu, z.vorhanden, z.doppelt,
                z.abgelehnt > 0 and string.format(L[", |cffff5555%d abgelehnt|r"], z.abgelehnt) or ""))
            if (z.buch or 0) > 0 then
                print(MELDUNG .. string.format(L["Datenbuch: %d Abschlüsse und Anhebungen übernommen."], z.buch))
            end
        end
        fensterAktualisieren()
        Abgleich.HalloSpaeter(2)
        if leise and Abgleich.LeitungBeaconSpaeter then Abgleich.LeitungBeaconSpaeter(10) end
    end)
end

-- =====================================================================
--  Empfangen
-- =====================================================================

local function einfuehren(zeilen, herkunft)
    local liste, abgelehnt = {}, 0
    local resetZeit = ns.Erfassung.ResetZeit()      -- ⭐ was älter ist als der letzte gildenweite Reset, kommt nicht zurück
    for _, z in ipairs(zeilen) do
        local id, e = Kern.Dekodieren(z, jetzt())
        if id then
            if resetZeit > 0 and (tonumber(e.timestamp) or 0) < resetZeit then
                -- älter als der Reset: still verwerfen
            else
                e.herkunft = herkunft
                liste[#liste + 1] = { id = id, e = e }
            end
        else
            abgelehnt = abgelehnt + 1
        end
    end

    local neu, doppelt, vorhanden, abg, zurueck = Kern.Zusammenfuehren(hist(), alias(), liste, 15)
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
            einreihen("N;" .. sid .. ";" .. stueck, S.kanal)
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

-- ---------------------------------------------------------------------
--  Datenbuch empfangen und senden
-- ---------------------------------------------------------------------

local Ausstehend = {}   -- unvollstaendige Abschluesse: Abend@rev -> { kopf, spieler }

--- Zeilen des Datenbuchs pruefen, sammeln und einfuehren.
--  @return Zahl neu eingefuehrter Saetze
local function buchEinfuehren(zeilen, S)
    local d = buchDaten()
    if not d then return 0 end
    local neu = 0
    for _, z in ipairs(zeilen) do
        local satz = Kern.BuchDekodieren(z, jetzt())
        if satz then
            for _, fertig in ipairs(Kern.BuchSammeln(Ausstehend, satz, time())) do
                local resetZeit = ns.Erfassung.ResetZeit()
                if resetZeit > 0 and (tonumber(fertig.zeit) or 0) < resetZeit then
                    -- älter als der letzte gildenweite Reset: nicht übernehmen
                elseif Kern.BuchEinfuehren(d, fertig) == "neu" then
                    neu = neu + 1
                end
                if S then
                    S.buchGesehen = S.buchGesehen or {}
                    local t = (fertig.typ == "a") and ("a:" .. fertig.id .. "@" .. fertig.rev) or ("h:" .. fertig.id)
                    S.buchGesehen[t] = true
                end
            end
        else
            Zaehler.abgelehnt = Zaehler.abgelehnt + 1
        end
    end
    Zaehler.buch = (Zaehler.buch or 0) + neu
    return neu
end

--- Sendet die genannten Saetze (ausser denen, die in dieser Sitzung schon jemand schickte).
local function buchSenden(sid, items)
    local d = buchDaten()
    local S = Sitzungen[sid]
    if not d or not items then return end
    local noetig = {}
    for _, t in ipairs(items) do
        if not (S and S.buchGesehen and S.buchGesehen[t]) then noetig[#noetig + 1] = t end
    end
    for _, paket in ipairs(Kern.Pakete(Kern.BuchZeilen(d, noetig), PAKETLAENGE)) do
        einreihen("D;" .. sid .. ";" .. paket, S and S.kanal)
    end
end

--- Die Liste des Leiters ist vollstaendig da: vergleichen, anfragen, was fehlt, schicken, was ich habe.
local function aufYReagieren(sid, S)
    local d = buchDaten()
    if not d or not C_Timer then return end
    local fremd = {}
    for t in table.concat(S.buchTeile, ","):gmatch("[^,]+") do fremd[#fremd + 1] = t end
    local fehlt, habe = Kern.BuchVergleichen(Kern.BuchListe(d), fremd)
    if #fehlt + #habe == 0 then return end

    S.buchGemeldet = S.buchGemeldet or {}
    S.buchGesehen = S.buchGesehen or {}

    C_Timer.After(0.5 + math.random() * 2.5, function()
        local noetig = {}
        for _, t in ipairs(fehlt) do
            if not S.buchGemeldet[t] then noetig[#noetig + 1] = t end
        end
        if #noetig == 0 then return end
        for _, t in ipairs(noetig) do S.buchGemeldet[t] = true end
        for _, stueck in ipairs(teilen(table.concat(noetig, ","), 200)) do
            einreihen("M;" .. sid .. ";" .. stueck, S.kanal)
        end
    end)

    C_Timer.After(1.5 + math.random() * 4, function()
        buchSenden(sid, habe)
    end)
end

--- Jemand hat Saetze angefragt: nur der, der den Abgleich begonnen hat, schickt nach.
local function aufMReagieren(sid, S, text)
    S.buchGemeldet = S.buchGemeldet or {}
    S.buchAngefragt = S.buchAngefragt or {}
    for t in text:gmatch("[^,]+") do
        S.buchGemeldet[t] = true
        S.buchAngefragt[#S.buchAngefragt + 1] = t
    end
    if not S.eigene or not C_Timer then return end

    S.buchNachToken = (S.buchNachToken or 0) + 1
    local mein = S.buchNachToken
    C_Timer.After(3, function()
        if mein ~= S.buchNachToken then return end
        local liste = S.buchAngefragt
        S.buchAngefragt = {}
        buchSenden(sid, liste)
    end)
end

--- Eine Sitzung des Leiters anlegen, falls sie noch nicht da ist (Q und Y koennen in beliebiger Reihenfolge kommen).
local function sitzungAnlegen(sid, name, kanalName)
    local S = Sitzungen[sid]
    if not S then
        S = { von = name, zeit = time(), teile = {}, gemeldet = {}, gesehen = {}, erhalten = 0, kanal = kanalName }
        Sitzungen[sid] = S
        Zaehler = { neu = 0, doppelt = 0, vorhanden = 0, abgelehnt = 0 }
    end
    return S
end

-- =====================================================================
--  ⭐ Leitungs-Abgleich (Entscheid 22.10.2026): Spieler mit Schreibrecht gleichen Historie und Wertungen gildenweit
--  untereinander ab, auch ohne gemeinsame Gruppe. Danach aktualisieren sie ihre Gruppen wie bisher (Hallo/Abgleich).
--  * Jeder Berechtigte meldet seinen Stand in der Gilde (V, klein): beim Anmelden, nach Änderungen, alle 15 Minuten.
--  * Wer einen anderen Stand eines Berechtigten hört, startet mit ihm einen Abgleich — als Flüstern (Q/Y/N/M/D/E wie
--    in der Gruppe), nicht im Gildenkanal. Angenommen wird nur von Spielern mit Schreibrecht (`Konfig.Darf`).
-- =====================================================================

local Leitung = { partner = {}, beacon = { token = 0, zuletzt = 0 } }

--- Ist der Leitungs-Abgleich für mich aktiv? (Schalter an, in einer Gilde, Schreibrecht)
local function leitungAn()
    if db().leitungSync == false then return false end
    if not (IsInGuild and IsInGuild()) then return false end
    return (ns.Konfig and ns.Konfig.Darf(eigenerName())) and true or false
end
function Abgleich.LeitungAn() return leitungAn() end

local function leitungErlaubt(sender)
    return leitungAn() and ns.Konfig.Darf(sender) and true or false
end

local function beaconSenden()
    if not leitungAn() then return end
    local n, summe = Abgleich.Stand()
    local bn, bsumme = Abgleich.BuchStand()
    local b = Leitung.beacon
    if b.n == n and b.summe == summe and b.bn == bn and b.bsumme == bsumme and (time() - b.zuletzt) < 600 then return end
    b.n, b.summe, b.bn, b.bsumme, b.zuletzt = n, summe, bn, bsumme, time()
    einreihen(string.format("V;%d;%d;%.0f;%d;%.0f", VERSION, n, summe, bn, bsumme), "GUILD")
end

--- Den eigenen Stand in ein paar Sekunden in der Gilde melden (mehrere Auslöser ergeben eine Meldung).
function Abgleich.LeitungBeaconSpaeter(sekunden)
    if not C_Timer then return end
    local b = Leitung.beacon
    b.token = b.token + 1
    local mein = b.token
    C_Timer.After(sekunden or 15, function()
        if mein == b.token then pcall(beaconSenden) end
    end)
end

--- Der Stand eines anderen Berechtigten ist eingetroffen: weicht er ab, gleiche ich mit ihm ab.
function Abgleich.LeitungBeaconEmpfangen(rest, sender)
    if not leitungErlaubt(sender) or Kern.GleicherSpieler(sender, eigenerName()) then return end
    local v, n, summe, bn, bsumme = tostring(rest):match("^(%d+);(%d+);(%d+);?(%d*);?(%d*)")
    if not v or tonumber(v) ~= VERSION then return end
    local mn, msumme = Abgleich.Stand()
    local mbn, mbsumme = Abgleich.BuchStand()
    if tonumber(n) == mn and tonumber(summe) == msumme and (tonumber(bn) or 0) == mbn and (tonumber(bsumme) or 0) == mbsumme then
        return
    end
    -- Nicht noch einmal für denselben gemeldeten Stand innerhalb von 5 Minuten (ein Abgleich, der nicht alles
    -- ausgleicht, soll nicht endlos laufen), und nicht, wenn er gerade selbst einen mit mir begonnen hat.
    -- Meldet er einen neuen Stand, gleiche ich sofort ab.
    local k = Kern.Schluessel(sender)
    local fp = rest
    local P = Leitung.partner[k] or {}
    Leitung.partner[k] = P
    if P.fp == fp and (time() - (P.zeit or 0)) < 300 then return end
    if (time() - (P.ein or 0)) < 60 then return end
    P.fp, P.zeit = fp, time()
    if not C_Timer then return end
    C_Timer.After(1 + math.random() * 4, function()
        if not leitungAn() then return end
        sitzungStarten("WHISPER:" .. sender)
        Abgleich.AbschlussMelden(true)
    end)
end

--- Eine Addon-Nachricht ist eingetroffen.
function Abgleich.Empfangen(text, sender, kanalName)
    if ns.Probe and ns.Probe.Aktiv and ns.Probe.Aktiv() then return end
    if type(text) ~= "string" then return end
    letzterAbsender = sender

    local typ, rest = text:match("^(%a);(.*)$")
    if not typ then return end

    -- ⭐ Einstellungen teilen (Konfig.lua): kommt auch ueber die Gilde, nicht nur aus
    -- der Gruppe; Konfig prueft den Absender selbst (Gilde und Rang).
    if typ == "K" or typ == "A" then
        if ns.Konfig then ns.Konfig.Empfangen(typ, rest, sender, kanalName) end
        return
    end

    -- ⭐ Einteilung je Abend und Gruppe (Gruppen.lua): kommt ueber die Gilde oder die Gruppe;
    -- Gruppen.EinteilungEmpfangen prueft den Absender selbst (Rang oder Rolle).
    if typ == "T" then
        if ns.Gruppen then ns.Gruppen.EinteilungEmpfangen(rest, sender, kanalName) end
        return
    end

    -- ⭐ Gruppenweiser Wochenabschluss: W;<Montag>;<Gruppe>;<Status>;<Zeit>;<Autor>
    if typ == "W" then
        if ns.Anwesenheit and ns.Anwesenheit.WochenGruppeEmpfangen then
            ns.Anwesenheit.WochenGruppeEmpfangen(rest, sender, kanalName)
        end
        return
    end

    -- ⭐ Stand eines Berechtigten in der Gilde (Leitungs-Abgleich)
    if typ == "V" then
        Abgleich.LeitungBeaconEmpfangen(rest, sender)
        return
    end

    -- ⭐ Flüstern gibt es nur im Leitungs-Abgleich: Q/Y/N/M/D/E von Berechtigten an Berechtigte, ohne Gruppe
    local leitung = (kanalName == "WHISPER")
    if leitung then
        if not (typ == "Q" or typ == "Y" or typ == "N" or typ == "M" or typ == "D" or typ == "E") then return end
        if not leitungErlaubt(sender) then return end
    end

    local gilde, unit
    if not leitung then gilde, unit = ns.Rolle.Absender(sender) end

    -- ⭐ Wuerfelfenster (Wurf.lua): Beginn und Ende eines Wurfs. Bewusst VOR der
    -- Gildenpruefung: Wer im Raid in einer anderen Gilde ist, soll mitwuerfeln
    -- koennen; geprueft wird, dass der Absender Pluendermeister, Leiter oder
    -- Assistent der Gruppe ist. Wurf.lua fuehrt Buch, warum etwas abgelehnt wurde
    -- (/kl wurf status).
    if typ == "S" or typ == "X" or typ == "P" then
        if ns.Wurf then ns.Wurf.Empfangen(typ, rest, sender, unit) end
        return
    end

    -- ⭐ „KaosLoot nutzen?": die Antwort des Plündermeisters (Nutzung.lua prüft, dass er es ist)
    if typ == "U" then
        if ns.Nutzung then ns.Nutzung.Empfangen(rest, sender, unit) end
        return
    end

    if not leitung and not unit then return end                         -- nicht in unserer Gruppe
    if not leitung and UnitIsUnit and UnitIsUnit(unit, "player") then return end   -- das waren wir

    local name = leitung and sender or ((GetUnitName and GetUnitName(unit, true)) or sender)
    local wkanal = leitung and ("WHISPER:" .. sender) or nil

    if typ == "H" then
        local v, n, summe, bn, bsumme = rest:match("^(%d+);(%d+);(%d+);?(%d*);?(%d*)")
        if not v then return end
        Bekannt[Kern.Schluessel(name)] = {
            name = name, version = tonumber(v), n = tonumber(n),
            summe = tonumber(summe), bn = tonumber(bn) or 0, bsumme = tonumber(bsumme) or 0,
            zeit = time(), gilde = gilde,
        }
        Abgleich.Pruefen()
        return
    end

    -- Alles Weitere nur von Gildenmitgliedern
    if not leitung and not gilde then return end

    if typ == "L" then
        -- Neue Vergabe vom Schreiber: nur von Leiter, Assistent, Pluendermeister
        local _, zeile = rest:match("^([^;]*);(.*)$")
        if not zeile or not ns.Rolle.Berechtigt(name) then return end
        einfuehren({ zeile }, "gruppe")
        fensterAktualisieren()
        Abgleich.HalloSpaeter(8)

    elseif typ == "Q" then
        if not leitung and not ns.Rolle.Berechtigt(name) then return end
        local sid, k, gesamt, stueck = rest:match("^([^;]*);(%d+);(%d+);(.*)$")
        k, gesamt = tonumber(k), tonumber(gesamt)
        if not sid or not k or not gesamt or gesamt < 1 or gesamt > 60 or k > gesamt then return end

        local S = Sitzungen[sid]
        if not S then
            S = { von = name, zeit = time(), teile = {}, gemeldet = {}, gesehen = {}, erhalten = 0, kanal = wkanal }
            Sitzungen[sid] = S
            Zaehler = { neu = 0, doppelt = 0, vorhanden = 0, abgelehnt = 0 }
            if leitung then
                local k = Kern.Schluessel(sender)
                Leitung.partner[k] = Leitung.partner[k] or {}
                Leitung.partner[k].ein = time()                       -- er hat begonnen: ich beginne nicht noch einmal
            else
                -- ⭐ Wer nicht selbst abgleicht, sieht, dass es läuft (das Ende meldet `AbschlussMelden`)
                print(MELDUNG .. string.format(L["%s gleicht die Daten in der Gruppe ab – deine werden aktualisiert …"], Kern.Anzeigename(name)))
            end
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
                Abgleich.AbschlussMelden(leitung)
            end
        end

    elseif typ == "N" then
        local sid, tage = rest:match("^([^;]*);(.*)$")
        local S = sid and sitzungHolen(sid)
        if S and tage then aufNReagieren(sid, S, tage) end

    elseif typ == "Y" then
        -- Die Liste des Datenbuchs vom Leiter (wie Q)
        if not leitung and not ns.Rolle.Berechtigt(name) then return end
        local sid, k, gesamt, stueck = rest:match("^([^;]*);(%d+);(%d+);(.*)$")
        k, gesamt = tonumber(k), tonumber(gesamt)
        if not sid or not k or not gesamt or gesamt < 1 or gesamt > 60 or k > gesamt then return end

        local S = sitzungAnlegen(sid, name, wkanal)
        S.buchTeile = S.buchTeile or {}
        S.buchErhalten = S.buchErhalten or 0
        if not S.buchTeile[k] then
            S.buchTeile[k] = stueck
            S.buchErhalten = S.buchErhalten + 1
            if S.buchErhalten == gesamt then
                local geordnet = {}
                for i = 1, gesamt do geordnet[i] = S.buchTeile[i] or "" end
                S.buchTeile = geordnet
                aufYReagieren(sid, S)
                Abgleich.AbschlussMelden(leitung)
            end
        end

    elseif typ == "M" then
        local sid, ids = rest:match("^([^;]*);(.*)$")
        local S = sid and sitzungHolen(sid)
        if S and ids then aufMReagieren(sid, S, ids) end

    elseif typ == "D" then
        -- Saetze des Datenbuchs. Sitzung "0" = live vom Leiter/Plündermeister/Gildenleitung,
        -- sonst Teil eines Abgleichs.
        local sid, paket = rest:match("^([^;]*);(.*)$")
        if not sid or not paket then return end
        local S
        if sid == "0" then
            if leitung then return end                       -- live nur über die Gruppe
            local darf = ns.Rolle.Berechtigt(name)
                      or (ns.Konfig and ns.Konfig.Darf and ns.Konfig.Darf(name))
            if not darf then return end
        else
            S = sitzungHolen(sid)
            if not S then return end
        end

        local zeilen = Kern.Entpacken(paket)
        if #zeilen > 60 then return end
        if buchEinfuehren(zeilen, S) > 0 then
            fensterAktualisieren()
            Abgleich.HalloSpaeter(8)
        end
        if S then Abgleich.AbschlussMelden(leitung) end

    elseif typ == "E" then
        local sid, paket = rest:match("^([^;]*);(.*)$")
        local S = sid and sitzungHolen(sid)
        if not S or not paket then return end

        local zeilen = Kern.Entpacken(paket)
        if #zeilen > 40 then return end
        local liste = einfuehren(zeilen, "abgleich")
        for _, X in ipairs(liste) do S.gesehen[gesehenSchluessel(X.id, X.e)] = true end
        Abgleich.AbschlussMelden(leitung)
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
    local bn, bsumme = Abgleich.BuchStand()
    zeilen[#zeilen + 1] = string.format(L["Datenbuch: %d Sätze, Prüfsumme %s"], bn, string.format("%.0f", bsumme))
    zeilen[#zeilen + 1] = string.format(L["Kanal: %s"], tostring(kanal() or L["keiner (nicht in einer Gruppe)"]))
    zeilen[#zeilen + 1] = string.format(L["Leitungs-Abgleich: %s"], leitungAn() and L["aktiv"] or L["aus"])

    local anz = 0
    for _, P in pairs(Bekannt) do
        anz = anz + 1
        zeilen[#zeilen + 1] = string.format(L["  %s: %d Einträge, Prüfsumme %s%s%s"],
            P.name, P.n, string.format("%.0f", P.summe),
            (P.n == n and P.summe == summe and P.bn == bn and P.bsumme == bsumme) and (" " .. L["|cff55ff55gleich|r"]) or (" " .. L["|cffffff78weicht ab|r"]),
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
-- Die Beutemethode wechselt: auf Plündermeister sofort melden, davon weg alles still stellen.
pcall(function() rahmen:RegisterEvent("PARTY_LOOT_METHOD_CHANGED") end)
rahmen:SetScript("OnEvent", function(_, ereignis, praefix, text, kanalName, sender)
    local ok, fehler = pcall(function()
        -- ⭐ Auch ein schlafendes Addon muss die Antwort des Plündermeisters („KaosLoot nutzen?“, Nachricht `U`)
        -- hören können: Präfix anmelden und genau diese Nachricht durchlassen.
        if ereignis == "PLAYER_ENTERING_WORLD" then
            praefixAnmelden()
            -- ⭐ Leitungs-Abgleich: den eigenen Stand melden, sobald die Gildenliste da ist, dann alle 15 Minuten
            if C_Timer and not Leitung.laeuft then
                Leitung.laeuft = true
                C_Timer.After(45, function() pcall(beaconSenden) end)
                if C_Timer.NewTicker then
                    C_Timer.NewTicker(900, function() pcall(beaconSenden) end)
                end
            end
        end
        -- Ebenso die Meldungen der Gilde: geteilte Einstellungen (K, A) und die Einteilung (T) hängen nicht an der
        -- Beutemethode (sonst kämen sie nie bei jemandem an, der gerade nicht im Raid ist).
        if ereignis == "CHAT_MSG_ADDON" and praefix == PRAEFIX and type(text) == "string" and (text:match("^[UKATVW];") or kanalName == "WHISPER") then
            Abgleich.Empfangen(text, sender, kanalName)
            return
        end
        -- ⭐ Nur mit Plündermeister als Beutemethode im Dienst (Entscheid 15.10.2026).
        if not ns.Rolle.Aktiv() then
            Abgleich.Pruefen()   -- räumt Hinweis und Liste weg
            return
        end
        if ereignis == "PARTY_LOOT_METHOD_CHANGED" then
            Abgleich.HalloSpaeter(2)
        elseif ereignis == "CHAT_MSG_ADDON" then
            if praefix == PRAEFIX then Abgleich.Empfangen(text, sender, kanalName) end
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
