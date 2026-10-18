--[[----------------------------------------------------------------------
    Konfig.lua  —  Einstellungen teilen

    ⭐ Wunsch (Nutzer, 15.10.2026): Nur EINER stellt sein Addon ein
    (Würfelbereiche, Verzauberer, Gruppen, …) und schickt das an alle; so
    raiden mehrere 10er- und 20er-Raids mit denselben Einstellungen, und alle
    Verzauberer sind überall gelistet.

    Ablauf:
      * Wer senden darf (Gildenrang, siehe unten), klickt *An alle senden*
        (oder `/fs konfig senden`). Die Einstellungen gehen über die Gilde an
        alle, die gerade online sind (Nachricht `K`).
      * Wer später kommt, fragt beim Anmelden und beim Beitritt zu einer Gruppe
        (`A;<mein Stand>`). Hat jemand einen neueren Stand, schickt er ihn
        nach (zufällig verzögert; wer hört, dass es schon da ist, schweigt).
        Weitergegeben wird immer der **unveränderte** Text des Absenders, nie
        die eigenen (vielleicht geänderten) Einstellungen.

    ⚠️ Vertrauen: Angenommen wird nur, wenn (1) der Absender in der eigenen Gilde
    ist und (2) der URSPRUNGSAUTOR (`von`) einen Rang hat, der senden darf
    (`konfigRang`, Standard: nur der Gildenleiter; gehört selbst zu den geteilten
    Einstellungen, ändern kann es also nur, wer ohnehin senden darf). Der Rang
    kommt aus der Gildenliste; ist sie nicht geladen, wird nichts angenommen.

    ⚠️ Was geteilt wird (Liste unten in `Sammeln`): Würfelbereiche, Würfelzeit,
    Verzauberer, Gruppen (Beschriftung, Ränge, von Hand ergänzte Namen), Qualität,
    Ort, Ansage, Abgleich und die Rangstufe. NICHT geteilt wird, was persönlich
    ist: Fenstergröße und -lage, „selbst öffnen", wer aufzeichnet (`schreiben`),
    die aktive Gruppe. Vor jeder Übernahme wird der alte Stand gesichert
    (`/fs konfig zurueck`).
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Konfig = {}
ns.Konfig = Konfig

local Kern = ns.Kern

local MELDUNG = "|cff1B6B57Fairshare|r: "
local PAKET = 150            -- Nutzlast je Nachricht (der Kopf kommt dazu)
local MAXGRUPPEN = 12
local MAXNAMEN = 60
local SITZUNGSDAUER = 600

local function db() return ns.Erfassung.Einstellungen() end

local function jetzt()
    return (GetServerTime and GetServerTime()) or time()
end

local function ichName()
    if GetUnitName then
        local n = GetUnitName("player", true)
        if n and n ~= "" then return n end
    end
    return (UnitName("player"))
end

local function sag(text) print(MELDUNG .. text) end

local letzteAnfrage = 0          -- wann ICH zuletzt nach neueren Einstellungen gefragt habe

-- Was zuletzt mit Einstellungsnachrichten passiert ist (/fs konfig status)
local protokoll = {}
local function merke(text)
    protokoll[#protokoll + 1] = date("%H:%M:%S", time()) .. "  " .. text
    if #protokoll > 8 then table.remove(protokoll, 1) end
end

-- =====================================================================
--  Wer darf senden?
-- =====================================================================

--- Die Stufe, bis zu der Absender gelten (1 = nur der Gildenleiter).
--- ⭐ Wurzel des Vertrauens (Entscheid 17.10.2026): Stufe 1 (Gildenmeister) und Stufe 2 (Offiziere) dürfen
--  immer senden und einteilen, auf jedem Client, egal was dort eingestellt ist. Sonst käme eine Meldung nie an,
--  solange der Empfänger noch auf einer alten Grenze steht. Die Grenze erweitert das nur nach unten.
Konfig.WURZEL = 2

function Konfig.RangGrenze()
    local r = tonumber(db().konfigRang) or Konfig.WURZEL
    return math.max(Konfig.WURZEL, math.min(6, math.floor(r)))
end

--- Stufe eines Spielers in der Gilde: 1 = hoechster Rang.
--  ⚠️ Forever (C_Club) zaehlt ab 1, die alte Gildenliste ab 0 — darum die
--  Stufe aus der Reihenfolge der vorkommenden Raenge, nicht aus der Rohzahl.
--  @return Stufe, oder nil und ein Grund ("liste" = Gildenliste fehlt, "mitglied" = nicht in der Gilde)
function Konfig.RangStufe(name)
    local M = ns.Gruppen.GildenMitglieder()
    if not M then return nil, "liste" end

    local index, gefunden = {}, nil
    for _, m in ipairs(M) do
        if m.rangIndex ~= nil then index[m.rangIndex] = true end
        if gefunden == nil and Kern.GleicherSpieler(m.name, name) then gefunden = m.rangIndex end
    end
    if gefunden == nil then return nil, "mitglied" end

    local stufe = 0
    for i in pairs(index) do
        if i <= gefunden then stufe = stufe + 1 end
    end
    return stufe
end

--- Gehört dieser Spieler zur Wurzel (Stufe 1 oder 2)? Nur sie ändern, wer überhaupt senden darf.
function Konfig.DarfWurzel(name)
    local stufe = Konfig.RangStufe(name or ichName())
    return stufe ~= nil and stufe <= Konfig.WURZEL
end

--- ⭐ Ist die Bedienung der geteilten Einstellungen für DIESEN Spieler gesperrt? Nur wenn sein Rang bekannt ist
--  und nicht reicht (ohne Gilde oder bei noch nicht geladener Gildenliste bleibt es offen — die Sicherheit liegt
--  bei den Empfängern, das hier ist Bequemlichkeit).
--  @param wurzel  true: gesperrt, wenn er nicht zur Wurzel gehört (die Rangstufe selbst)
function Konfig.Gesperrt(wurzel)
    local stufe = Konfig.RangStufe(ichName())
    if not stufe then return false end
    return stufe > (wurzel and Konfig.WURZEL or Konfig.RangGrenze())
end

--- Darf dieser Spieler Einstellungen senden?
function Konfig.Darf(name)
    local stufe = Konfig.RangStufe(name)
    return stufe ~= nil and stufe <= Konfig.RangGrenze()
end

function Konfig.DarfSenden()
    return Konfig.Darf(ichName())
end

-- =====================================================================
--  Sammeln, Kodieren, Pruefen
-- =====================================================================

local function gueltigerName(n)
    return type(n) == "string" and #n >= 1 and #n <= 40 and not n:find("[;~|,%c]")
end

local function kopie(liste)
    local aus = {}
    for i, x in ipairs(liste or {}) do aus[i] = x end
    return aus
end

--- Die zu teilenden Einstellungen als Tabelle.
function Konfig.Sammeln()
    local d = db()
    local s = {
        bereiche = ns.Erfassung.Bereiche(),
        wurfDauer = ns.Wurf.Dauer(),
        ansagen = d.ansagen ~= false,
        pmEingesteckt = d.pmEingesteckt ~= false,
        nurGewuerfelt = d.nurGewuerfelt and true or false,
        autoAbgleich = d.autoAbgleich ~= false,
        mindestQualitaet = tonumber(d.mindestQualitaet) or 3,
        ort = d.ort or "raid",
        konfigRang = Konfig.RangGrenze(),
        verzauberer = kopie(ns.Wurf.Verzauberer()),
        gruppen = {},
    }
    for _, name in ipairs(ns.Gruppen.Namen()) do
        local G = ns.Gruppen.Holen(name)
        if G and gueltigerName(name) then
            local raenge = {}
            for idx in pairs(G.raenge or {}) do raenge[#raenge + 1] = idx end
            table.sort(raenge)
            local tage = {}
            for wd = 1, 7 do
                if ns.Gruppen.RaidtagGewaehlt(name, wd) then tage[wd] = true end
            end
            s.gruppen[name] = { auto = G.auto ~= false, raenge = raenge, extra = kopie(G.extra), raidtage = tage }
        end
    end
    return s
end

--- Eine Liste so in Zeilen packen, dass keine zu lang wird.
local function listeZeilen(kopf, liste, z)
    local aktuell, laenge = {}, #kopf + 1
    for _, n in ipairs(liste) do
        if #aktuell > 0 and laenge + #n + 1 > 120 then
            z[#z + 1] = kopf .. "|" .. table.concat(aktuell, ",")
            aktuell, laenge = {}, #kopf + 1
        end
        aktuell[#aktuell + 1] = n
        laenge = laenge + #n + 1
    end
    if #aktuell > 0 then z[#z + 1] = kopf .. "|" .. table.concat(aktuell, ",") end
end

--- @return Liste von Zeilen (je hoechstens etwa 150 Zeichen)
function Konfig.Kodieren(s)
    local z = {}
    local B = s.bereiche
    z[#z + 1] = string.format("B|%d|%d|%d|%d", B.haupt[1], B.haupt[2], B.zweit[1], B.zweit[2])
    z[#z + 1] = "W|" .. s.wurfDauer
    z[#z + 1] = "F|" .. (s.ansagen and "1" or "0") .. (s.pmEingesteckt and "1" or "0")
        .. (s.nurGewuerfelt and "1" or "0") .. (s.autoAbgleich and "1" or "0")
    z[#z + 1] = "Q|" .. s.mindestQualitaet
    z[#z + 1] = "O|" .. s.ort
    z[#z + 1] = "R|" .. s.konfigRang

    local v = {}
    for _, n in ipairs(s.verzauberer) do
        if gueltigerName(n) then v[#v + 1] = n end
    end
    listeZeilen("V", v, z)

    local namen = {}
    for name in pairs(s.gruppen) do namen[#namen + 1] = name end
    table.sort(namen)
    for _, name in ipairs(namen) do
        local g = s.gruppen[name]
        z[#z + 1] = string.format("G|%s|%d|%s", name, g.auto and 1 or 0, table.concat(g.raenge, ","))
        local extra = {}
        for _, n in ipairs(g.extra) do
            if gueltigerName(n) then extra[#extra + 1] = n end
        end
        listeZeilen("X|" .. name, extra, z)
        -- Raidtage der Gruppe: sieben Zeichen 0/1, Sonntag bis Samstag
        local tage = {}
        for wd = 1, 7 do tage[wd] = (g.raidtage and g.raidtage[wd]) and "1" or "0" end
        z[#z + 1] = string.format("Y|%s|%s", name, table.concat(tage))
    end
    return z
end

--- ⭐ Prueft und baut aus Zeilen die Einstellungen. Alles Fremde wird begrenzt:
--  Zahlen auf ihren Bereich, Namen auf Laenge und Zeichen, Listen auf eine
--  Obergrenze; Unbekanntes bleibt unbeachtet (spaetere Fassungen duerfen mehr senden).
--  @return Tabelle wie von Sammeln, oder nil und ein Grund
function Konfig.Dekodieren(zeilen)
    local s = { verzauberer = {}, gruppen = {} }
    local gruppenZahl = 0

    for _, z in ipairs(zeilen) do
        local typ, rest = z:match("^(%a)|(.*)$")
        if typ == "B" then
            local a, b, c, d2 = rest:match("^(%d+)|(%d+)|(%d+)|(%d+)$")
            if a then
                s.bereiche = { haupt = { tonumber(a), tonumber(b) }, zweit = { tonumber(c), tonumber(d2) } }
            end
        elseif typ == "W" then
            local w = tonumber(rest)
            if w and w >= 5 and w <= 300 then s.wurfDauer = math.floor(w) end
        elseif typ == "F" then
            if #rest == 4 and rest:match("^[01]+$") then
                s.ansagen, s.pmEingesteckt = rest:sub(1, 1) == "1", rest:sub(2, 2) == "1"
                s.nurGewuerfelt, s.autoAbgleich = rest:sub(3, 3) == "1", rest:sub(4, 4) == "1"
            end
        elseif typ == "Q" then
            local q = tonumber(rest)
            if q and q >= 0 and q <= 5 then s.mindestQualitaet = math.floor(q) end
        elseif typ == "O" then
            if rest == "raid" or rest == "instanz" or rest == "ueberall" then s.ort = rest end
        elseif typ == "R" then
            local r = tonumber(rest)
            if r and r >= 1 and r <= 6 then s.konfigRang = math.max(Konfig.WURZEL, math.floor(r)) end
        elseif typ == "Y" then
            -- Raidtage einer Gruppe (die Gruppe muss vorher gelesen worden sein)
            local name, tage = rest:match("^([^|]*)|([01]+)$")
            local g = name and s.gruppen[name]
            if g and #tage == 7 then
                g.raidtage = {}
                for wd = 1, 7 do
                    if tage:sub(wd, wd) == "1" then g.raidtage[wd] = true end
                end
            end
        elseif typ == "V" then
            for n in rest:gmatch("[^,]+") do
                if gueltigerName(n) and #s.verzauberer < 8 then s.verzauberer[#s.verzauberer + 1] = n end
            end
        elseif typ == "G" then
            local name, auto, raenge = rest:match("^([^|]*)|([01])|(.*)$")
            if name and gueltigerName(name) and not s.gruppen[name] and gruppenZahl < MAXGRUPPEN then
                gruppenZahl = gruppenZahl + 1
                local g = { auto = auto == "1", raenge = {}, extra = {} }
                for r in raenge:gmatch("%d+") do
                    local zahl = tonumber(r)
                    if zahl and zahl <= 50 then g.raenge[#g.raenge + 1] = zahl end
                end
                s.gruppen[name] = g
            end
        elseif typ == "X" then
            local name, liste = rest:match("^([^|]*)|(.*)$")
            local g = name and s.gruppen[name]
            if g then
                for n in liste:gmatch("[^,]+") do
                    if gueltigerName(n) and #g.extra < MAXNAMEN then g.extra[#g.extra + 1] = n end
                end
            end
        end
    end

    if not s.bereiche then return nil, L["Bereiche fehlen"] end
    -- Die Bereiche muessen stimmig sein; geprueft wird an einer Kopie von Kern.
    local alt = ns.Erfassung.Bereiche()
    local ok = Kern.BereicheSetzen(s.bereiche.haupt[1], s.bereiche.haupt[2], s.bereiche.zweit[1], s.bereiche.zweit[2])
    Kern.BereicheSetzen(alt.haupt[1], alt.haupt[2], alt.zweit[1], alt.zweit[2])      -- zurueck
    if not ok then return nil, L["Bereiche unbrauchbar"] end

    s.wurfDauer = s.wurfDauer or ns.Wurf.Dauer()
    if s.ansagen == nil then s.ansagen, s.pmEingesteckt, s.nurGewuerfelt, s.autoAbgleich = true, true, false, true end
    s.mindestQualitaet = s.mindestQualitaet or 3
    s.ort = s.ort or "raid"
    return s
end

-- =====================================================================
--  Anwenden
-- =====================================================================

--- Schreibt geprueftes in die eigenen Einstellungen (und sichert vorher den alten Stand).
--  @param ohneSicherung  true: den alten Stand nicht merken (beim Zurücksetzen eigener Abweichungen)
function Konfig.Anwenden(s, ohneSicherung)
    local d = db()
    if not ohneSicherung then d.konfigAlt = Konfig.Sammeln() end

    local B = s.bereiche
    ns.Erfassung.BereicheSetzen(B.haupt[1], B.haupt[2], B.zweit[1], B.zweit[2])
    d.wurfDauer = s.wurfDauer
    d.ansagen, d.pmEingesteckt = s.ansagen, s.pmEingesteckt
    d.nurGewuerfelt, d.autoAbgleich = s.nurGewuerfelt, s.autoAbgleich
    d.mindestQualitaet, d.ort = s.mindestQualitaet, s.ort
    if s.konfigRang then d.konfigRang = s.konfigRang end      -- nur, wenn ein berechtigter Absender sie mitgeschickt hat
    d.verzauberer = kopie(s.verzauberer)

    -- Gruppen: die der Gildenleitung. Den verwalteten Kader behaelt jeder selbst
    -- (er wird gleich aus den Gildenraengen neu gebildet).
    local alt = d.gruppen or {}
    local neu = {}
    for name, g in pairs(s.gruppen) do
        local vorher = alt[name]
        local raenge = {}
        for _, idx in ipairs(g.raenge) do raenge[idx] = true end
        -- Raidtage: die der Gildenleitung; ältere Absender kennen sie nicht, dann bleiben die eigenen
        local tage = {}
        if g.raidtage then
            for wd, an in pairs(g.raidtage) do
                if an then tage[wd] = true end
            end
        elseif vorher and vorher.raidtage then
            tage = vorher.raidtage
        end
        neu[name] = { name = name, kader = vorher and vorher.kader or {}, extra = kopie(g.extra),
                      raenge = raenge, auto = g.auto, raidtage = tage }
    end
    d.gruppen = neu
    if d.aktiveGruppe and not neu[d.aktiveGruppe] then d.aktiveGruppe = nil end

    if C_Timer then
        C_Timer.After(2, function()
            for name, G in pairs(db().gruppen or {}) do
                local hat = false
                for _ in pairs(G.raenge or {}) do hat = true break end
                if hat then pcall(ns.Gruppen.Synchronisieren, name, true) end
            end
            if ns.Fenster then ns.Fenster.Aktualisieren() end
            if ns.Einstellungen and ns.Einstellungen.Sichtbar and ns.Einstellungen.Sichtbar() then
                ns.Einstellungen.Aktualisieren()
            end
        end)
    end
end

local function zeilenGleich(a, b)
    local x, y = {}, {}
    for _, z in ipairs(a or {}) do x[#x + 1] = z end
    for _, z in ipairs(b or {}) do y[#y + 1] = z end
    table.sort(x)
    table.sort(y)
    return table.concat(x, "\n") == table.concat(y, "\n")
end

--- ⭐ Selbstheilung: Wer nicht schreiben darf, bekommt die geteilten Einstellungen beim Anmelden und beim
--  Gruppenbeitritt auf den letzten offiziellen Stand zurückgesetzt (der steht in `konfigRoh`). Eine heimliche
--  Änderung der Datei hält so nur bis dahin. Bei unbekanntem Rang (Gildenliste noch nicht geladen) passiert nichts.
--  @return true, wenn etwas zurückgesetzt wurde
function Konfig.Heilen()
    local d = db()
    if type(d.konfigRoh) ~= "table" or not d.konfigVon then return false end
    local stufe = Konfig.RangStufe(ichName())
    if not stufe or stufe <= Konfig.RangGrenze() then return false end
    local s = Konfig.Dekodieren(d.konfigRoh)
    if not s then return false end
    if zeilenGleich(Konfig.Kodieren(Konfig.Sammeln()), d.konfigRoh) then return false end
    Konfig.Anwenden(s, true)
    merke(L["Eigene Abweichungen bei den geteilten Einstellungen zurückgesetzt"])
    return true
end

--- Den Stand vor der letzten Uebernahme wiederherstellen.
function Konfig.Zurueck()
    local d = db()
    local alt = d.konfigAlt
    if not alt then return false, L["Es gibt keinen früheren Stand."] end
    local s = Konfig.Dekodieren(Konfig.Kodieren(alt))      -- noch einmal geprueft
    if not s then return false, L["Der frühere Stand ist unbrauchbar."] end
    Konfig.Anwenden(s)
    d.konfigAlt = nil
    d.konfigStand, d.konfigVon, d.konfigRoh = nil, nil, nil     -- gilt als eigener Stand, kein Weitergeben
    return true
end

-- =====================================================================
--  Senden
-- =====================================================================

local function paketeSenden(zeilen, stand, von, kanalName)
    local pakete = Kern.Pakete(zeilen, PAKET)
    for i, p in ipairs(pakete) do
        ns.Abgleich.Senden(string.format("K;%d;%s;%d;%d;%s", stand, von, i, #pakete, p), false, kanalName)
    end
    return #pakete
end

--- ⭐ Die eigenen Einstellungen an alle Gildenmitglieder schicken, die online sind.
--  @return Zahl der Nachrichten, oder nil und ein Grund
function Konfig.Senden()
    if not (IsInGuild and IsInGuild()) then return nil, L["Du bist in keiner Gilde."] end
    local stufe, grund = Konfig.RangStufe(ichName())
    if not stufe then
        return nil, grund == "liste" and L["Die Gildenliste ist noch nicht geladen."] or L["Du stehst nicht in der Gildenliste."]
    end
    if stufe > Konfig.RangGrenze() then
        return nil, string.format(L["Nur die Gildenleitung darf Einstellungen senden (bis Stufe %d, du hast Stufe %d)."],
            Konfig.RangGrenze(), stufe)
    end

    local d = db()
    local zeilen = Konfig.Kodieren(Konfig.Sammeln())
    local stand = math.max(jetzt(), (tonumber(d.konfigStand) or 0) + 1)
    d.konfigStand, d.konfigVon, d.konfigRoh = stand, ichName(), zeilen

    local n = paketeSenden(zeilen, stand, ichName(), "GUILD")
    merke(string.format(L["Gesendet: %d Nachrichten"], n))
    return n
end

--- Beim Anmelden und beim Gruppenbeitritt: Hat jemand neuere Einstellungen?
--  @param kanalName  "GUILD" oder nil (Gruppe)
function Konfig.Anfragen(kanalName)
    if db().konfigAnnehmen == false then return false end
    letzteAnfrage = jetzt()
    return ns.Abgleich.Senden("A;" .. (tonumber(db().konfigStand) or 0), false, kanalName)
end

-- =====================================================================
--  Empfangen
-- =====================================================================

local Sitzungen = {}
local letzteK = 0                  -- wann zuletzt Einstellungen (von irgendwem) ankamen
local letzteAntwort = 0

local function sitzungAbschliessen(S)
    local d = db()
    if (tonumber(d.konfigStand) or 0) >= S.stand then return end      -- schon da

    -- 1. Der Absender muss in unserer Gilde sein.
    local sStufe, sGrund = Konfig.RangStufe(S.sender)
    if not sStufe then
        merke(string.format(L["Einstellungen von %s abgelehnt: %s"], tostring(S.sender),
            sGrund == "liste" and L["Gildenliste nicht geladen"] or L["Absender nicht in der Gilde"]))
        return
    end
    -- ⭐ Wurde es nicht vom Urheber selbst geschickt, sondern weitergereicht, nehme ich
    -- es nur an, wenn ich gerade danach gefragt habe. Sonst koennte sich ein
    -- beliebiges Gildenmitglied in einer Weitergabe als Leiter ausgeben.
    if not Kern.GleicherSpieler(S.sender, S.von) and (jetzt() - letzteAnfrage) > 180 then
        merke(string.format(L["Einstellungen von %s abgelehnt: %s"], tostring(S.von), L["unaufgefordert weitergegeben"]))
        return
    end
    -- 2. Der Urheber muss senden duerfen.
    local vStufe, vGrund = Konfig.RangStufe(S.von)
    if not vStufe or vStufe > Konfig.RangGrenze() then
        merke(string.format(L["Einstellungen von %s abgelehnt: %s"], tostring(S.von),
            (not vStufe) and (vGrund == "liste" and L["Gildenliste nicht geladen"] or L["nicht in der Gilde"])
                          or L["Rang darf nicht senden"]))
        return
    end

    local zeilen = {}
    for i = 1, S.n do
        for _, z in ipairs(Kern.Entpacken(S.teile[i] or "")) do zeilen[#zeilen + 1] = z end
    end
    local s, grund = Konfig.Dekodieren(zeilen)
    if not s then
        merke(string.format(L["Einstellungen von %s abgelehnt: %s"], tostring(S.von), tostring(grund)))
        return
    end
    -- ⭐ Wer überhaupt senden darf, bestimmt nur die Wurzel (Stufe 1 und 2). Von anderen Rängen wird die
    -- Angabe ignoriert, alles andere gilt.
    if vStufe > Konfig.WURZEL and s.konfigRang then
        s.konfigRang = nil
        merke(string.format(L["Rangstufe von %s ignoriert: nur Stufe 1 und 2 dürfen sie ändern"], tostring(S.von)))
    end

    Konfig.Anwenden(s)
    d.konfigStand, d.konfigVon, d.konfigRoh = S.stand, S.von, zeilen
    merke(string.format(L["Einstellungen von %s übernommen"], tostring(S.von)))
    sag(string.format(L["Einstellungen von |cffffff78%s|r übernommen. |cffffff78/fs konfig zurueck|r nimmt sie zurück."],
        tostring(S.von)))
end

--- Eine Nachricht `K` (Einstellungen) oder `A` (Anfrage).
--  @param kanalName  "GUILD", "PARTY", "RAID" …
function Konfig.Empfangen(typ, rest, sender, kanalName)
    if type(rest) ~= "string" then return end
    if Kern.GleicherSpieler(sender, ichName()) then return end        -- das waren wir

    local d = db()

    if typ == "K" then
        local stand, von, k, n, paket = rest:match("^(%d+);([^;]*);(%d+);(%d+);(.*)$")
        stand, k, n = tonumber(stand), tonumber(k), tonumber(n)
        if not stand or not von or not k or not n or n < 1 or n > 60 or k < 1 or k > n or not gueltigerName(von) then
            return
        end
        letzteK = jetzt()
        if d.konfigAnnehmen == false then return end
        if (tonumber(d.konfigStand) or 0) >= stand then return end    -- nichts Neues

        local S = Sitzungen[stand]
        if S and (jetzt() - S.zeit) > SITZUNGSDAUER then S = nil end
        if not S then
            S = { stand = stand, von = von, sender = sender, n = n, teile = {}, erhalten = 0, zeit = jetzt() }
            Sitzungen[stand] = S
        end
        if S.n ~= n or S.von ~= von then return end                    -- passt nicht zusammen
        if not S.teile[k] then
            S.teile[k] = paket
            S.erhalten = S.erhalten + 1
            if S.erhalten == S.n then
                Sitzungen[stand] = nil
                sitzungAbschliessen(S)
            end
        end

    elseif typ == "A" then
        local seinStand = tonumber(rest) or 0
        local meinStand = tonumber(d.konfigStand) or 0
        if meinStand <= seinStand or type(d.konfigRoh) ~= "table" or not d.konfigVon then return end
        if (jetzt() - letzteAntwort) < 20 then return end

        -- Zufaellig verzoegert; wer inzwischen hoert, dass es jemand geschickt hat, schweigt.
        local angefragt = jetzt()
        if C_Timer then
            C_Timer.After(1 + math.random() * 5, function()
                if letzteK >= angefragt then return end
                local dd = db()
                if type(dd.konfigRoh) ~= "table" or not dd.konfigVon then return end
                letzteAntwort = jetzt()
                paketeSenden(dd.konfigRoh, tonumber(dd.konfigStand) or 0, dd.konfigVon, kanalName)
                merke(string.format(L["Einstellungen (Stand von %s) weitergegeben"], tostring(dd.konfigVon)))
            end)
        end
    end
end

-- =====================================================================
--  Anzeige
-- =====================================================================

--- Zeilen fuer /fs konfig status.
function Konfig.Status()
    local d = db()
    local z = {}
    if d.konfigStand then
        z[#z + 1] = string.format(L["Stand: von %s, %s"], tostring(d.konfigVon), date(L["%d.%m. %H:%M"], tonumber(d.konfigStand)))
    else
        z[#z + 1] = L["Noch keine geteilten Einstellungen erhalten oder gesendet."]
    end
    local stufe = Konfig.RangStufe(ichName())
    z[#z + 1] = string.format(L["Dein Rang: Stufe %s – senden erlaubt bis Stufe %d: %s"],
        stufe and tostring(stufe) or "?", Konfig.RangGrenze(), Konfig.DarfSenden() and L["ja"] or L["nein"])
    z[#z + 1] = string.format(L["Einstellungen übernehmen: %s"], d.konfigAnnehmen == false and L["nein"] or L["ja"])
    if #protokoll > 0 then
        z[#z + 1] = L["Letzte Meldungen:"]
        for _, t in ipairs(protokoll) do z[#z + 1] = "  " .. t end
    end
    return z
end

-- =====================================================================
--  Ereignisse: beim Anmelden und beim Gruppenbeitritt nachfragen
-- =====================================================================

local angefragtGilde, letzteGruppenfrage = false, 0

local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:RegisterEvent("GROUP_ROSTER_UPDATE")
pcall(function() rahmen:RegisterEvent("PARTY_LOOT_METHOD_CHANGED") end)
rahmen:SetScript("OnEvent", function(_, ereignis)
    local ok, fehler = pcall(function()
        if not C_Timer then return end
        -- ⭐ Die geteilten Einstellungen sind Sache der Gilde, nicht der Beutemethode: Sie werden auch von einem
        -- Addon abgeglichen, das gerade schläft (Entscheid 17.10.2026; sonst kamen Einstellungen nie an).
        if ereignis == "PLAYER_ENTERING_WORLD" then
            if not angefragtGilde then
                angefragtGilde = true
                -- Die Gildenliste und der Chat brauchen einen Moment.
                C_Timer.After(25, function() pcall(Konfig.Anfragen, "GUILD") end)
                C_Timer.After(45, function() pcall(Konfig.Heilen) end)
            end
        elseif ns.Rolle.Aktiv() and IsInGroup and IsInGroup() and (jetzt() - letzteGruppenfrage) > 300 then
            -- (im Gruppenkanal fragt nur ein Addon, das gerade im Dienst ist; die Gilde fragt beim Anmelden jeder)
            letzteGruppenfrage = jetzt()
            C_Timer.After(10, function() pcall(Konfig.Anfragen, nil) end)
            C_Timer.After(20, function() pcall(Konfig.Heilen) end)
        end
    end)
    if not ok then
        print(MELDUNG .. "|cffff5555" .. string.format(L["Fehler beim Teilen der Einstellungen: %s"], tostring(fehler)) .. "|r")
    end
end)

return ns
