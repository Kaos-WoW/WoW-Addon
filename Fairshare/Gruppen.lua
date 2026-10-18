--[[----------------------------------------------------------------------
    Gruppen.lua  —  Beschriftung und Kader

    Eine Gruppe ist zweierlei:
      * eine **Beschriftung** (z. B. „40er", „10er"): Jede Vergabe merkt
        sich die beim Eintragen aktive Gruppe, die Ansicht laesst sich
        auf eine Gruppe einschraenken;
      * ein **Kader**: eine Namensliste, die ohne Gruppe in der Liste
        steht — auch fuer Spieler ohne Vergabe.

    ⭐ In einer Gruppe zeigt die Uebersicht nur die Spieler, die gerade bei
    dir sind (Fenster.lua, Kern.Bilanz mit `nur`). Der Kader zaehlt dann
    nicht; er ist die Grundlage, wenn man ausserhalb einer Gruppe nachsieht.

    ⭐ **Mitgliederabgleich** (frueher „Auffuellen"): Sind Gildenraenge
    gewaehlt, ist der Kader GENAU die Mitglieder dieser Raenge — wer neu
    hinzukommt, wird aufgenommen, wer die Gilde oder den Rang verlaesst,
    faellt weg. Das ist sicher, weil die Raenge die Quelle sind und nicht
    Handarbeit. (Entscheid des Gildenleiters, 14.10.2026.)

    Zwei Listen je Gruppe:
      * `kader`  vom Mitgliederabgleich verwaltet, wird ersetzt
      * `extra`  von Hand ergaenzt, bleibt immer erhalten
    Die Liste, die man sieht, ist beides zusammen.

    ⚠️ Schutz vor einer halb geladenen Gildenliste: Wuerde der Abgleich
    ploetzlich auffaellig viele entfernen, fragt er erst nach (Antwort:
    gleiche Taste nochmal innerhalb von zwei Minuten). Das automatische
    Abgleichen beim Anmelden entfernt in dem Fall gar nichts.
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Gruppen = {}
ns.Gruppen = Gruppen

local Kern = ns.Kern

local function db()
    local d = ns.Erfassung.Einstellungen()
    d.gruppen = d.gruppen or {}
    return d
end

--- ⚠️ Alte Staende (vor dem Mitgliederabgleich) hatten nur `kader`, von Hand
--  gepflegt oder gefuellt. Das alles gilt jetzt als Handarbeit (`extra`),
--  damit der erste Abgleich nichts davon loescht.
local function migriere(G)
    if G and G.extra == nil then
        G.extra = G.kader or {}
        G.kader = {}
    end
    if G then
        G.kader = G.kader or {}
        G.raenge = G.raenge or {}
        G.raidtage = G.raidtage or {}
    end
    return G
end

--- Namen aller Gruppen, alphabetisch.
function Gruppen.Namen()
    local liste = {}
    for name in pairs(db().gruppen) do liste[#liste + 1] = name end
    table.sort(liste, function(a, b) return a:lower() < b:lower() end)
    return liste
end

function Gruppen.Holen(name)
    return name and migriere(db().gruppen[name]) or nil
end

--- Die aktive Gruppe (die neue Vergaben bekommen).
function Gruppen.AktivName()
    local d = db()
    if d.aktiveGruppe and d.gruppen[d.aktiveGruppe] then return d.aktiveGruppe end
    return nil
end

function Gruppen.Aktiv()
    return Gruppen.Holen(Gruppen.AktivName())
end

--- @return true, oder false und ein Grund
--- ⭐ Der reservierte „Gruppenname“ für die Bench in der Einteilung (Entscheid 18.10.2026): Wer dort steht, wird
--  in keiner Gruppe erwartet, erscheint aber in der Abwesenheit jeder Gruppe, falls er einspringen muss.
Gruppen.BENCH = "Bench"

--- ⭐ Zweites reserviertes Ziel in der Einteilung: Spieler, die sich weder an- noch abgemeldet haben („No notice“).
Gruppen.KEINEMELDUNG = "Keine Meldung"

--- Ist das ein reservierter Name (Bench oder Keine Meldung)?
function Gruppen.Reserviert(name)
    local n = tostring(name or ""):lower()
    return n == Gruppen.BENCH:lower() or n == Gruppen.KEINEMELDUNG:lower()
end

function Gruppen.Anlegen(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return false, L["kein Name"] end
    if Gruppen.Reserviert(name) then return false, L["Dieser Name ist reserviert."] end
    if #name > 40 then return false, L["Name zu lang (höchstens 40 Zeichen)"] end
    -- ⚠️ Kein Semikolon und keine Steuerzeichen: Der Name geht beim Abgleich
    -- mit auf die Reise. Kodieren schuetzt zwar, aber Ruhe ist besser.
    if name:find("[;~|%c]") then return false, L["Zeichen nicht erlaubt"] end

    local d = db()
    if d.gruppen[name] then return false, L["gibt es schon"] end
    d.gruppen[name] = { name = name, kader = {}, extra = {}, raenge = {}, auto = true }
    if not d.aktiveGruppe then d.aktiveGruppe = name end
    return true
end

function Gruppen.Loeschen(name)
    local d = db()
    if not d.gruppen[name] then return false end
    d.gruppen[name] = nil
    if d.aktiveGruppe == name then d.aktiveGruppe = nil end
    return true
end

function Gruppen.Aktivieren(name)
    local d = db()
    if name ~= nil and not d.gruppen[name] then return false end
    d.aktiveGruppe = name
    return true
end

-- =====================================================================
--  Kader
-- =====================================================================

local function enthalten(liste, name)
    for _, e in ipairs(liste or {}) do
        if Kern.GleicherSpieler(e, name) then return true end
    end
    return false
end

--- Fuegt Namen hinzu, die noch nicht in `ziel` stehen.
--  @return Zahl der neu aufgenommenen
local function hinzufuegen(ziel, liste)
    local n = 0
    for _, roh in ipairs(liste) do
        local eintrag = type(roh) == "string" and roh:match("^%s*(.-)%s*$") or ""
        if eintrag ~= "" and not enthalten(ziel, eintrag) then
            ziel[#ziel + 1] = eintrag
            n = n + 1
        end
    end
    return n
end

--- Der ganze Kader: verwaltete und von Hand ergaenzte Namen, ohne Doppelte.
function Gruppen.Namensliste(G)
    local liste = {}
    if not G then return liste end
    for _, n in ipairs(G.kader or {}) do liste[#liste + 1] = n end
    for _, n in ipairs(G.extra or {}) do
        if not enthalten(liste, n) then liste[#liste + 1] = n end
    end
    return liste
end

--- Namen von Hand ergaenzen, durch Komma oder Zeilenumbruch getrennt.
--  Nicht an Leerzeichen: Nachnamen enthalten welche.
--  Diese Namen bleiben beim Mitgliederabgleich immer erhalten.
function Gruppen.KaderErgaenzen(name, text)
    local G = Gruppen.Holen(name)
    if not G then return nil end
    local liste = {}
    for roh in (text or ""):gmatch("[^,\n]+") do liste[#liste + 1] = roh end
    return hinzufuegen(G.extra, liste)
end

--- Entfernt einen Namen. Steht er nur durch einen gewaehlten Rang im Kader,
--  kommt er beim naechsten Abgleich zurueck — dafuer den Rang abwaehlen.
function Gruppen.KaderEntfernen(name, wer)
    local G = Gruppen.Holen(name)
    if not G then return false end
    local gefunden = false
    for _, liste in ipairs({ G.extra, G.kader }) do
        for i = #liste, 1, -1 do
            if Kern.GleicherSpieler(liste[i], wer) then
                table.remove(liste, i)
                gefunden = true
            end
        end
    end
    return gefunden
end

--- Namen, die ohne Gruppe in der Liste stehen muessen.
function Gruppen.Pflicht(gewaehlt)
    return Gruppen.Namensliste(Gruppen.Holen(gewaehlt) or Gruppen.Aktiv())
end

-- =====================================================================
--  Gilde lesen
-- =====================================================================

--- ⭐ Ist jemand im Spiel online? Aus `info.presence` der Gildenliste (C_Club).
--  Die Werte sind `Enum.ClubMemberPresence`: Online, OnlineMobile (nur die App, nicht im Spiel), Offline,
--  Away, Busy, Unknown. Frueher zaehlten Offline-Spieler als online (Nutzerfund 17.10.2026: „31 online“,
--  obwohl fast niemand da war). Fehlt die Enum, gelten die bekannten Zahlen (1 Online, 4 Away, 5 Busy).
function Gruppen.PraesenzOnline(p)
    if p == "online" then return true end
    local P = rawget(_G, "Enum") and Enum.ClubMemberPresence
    if type(P) == "table" and P.Online ~= nil then
        return (p == P.Online or p == P.Away or p == P.Busy) and true or false
    end
    return (p == 1 or p == 4 or p == 5) and true or false
end

--- Alle Gildenmitglieder.
--  Forever liest ueber C_Club, Anniversary/Classic ueber GetGuildRosterInfo
--  (so hat es schon die erste Fassung dieses Projekts gemessen).
--  Gemessen mit `/fs gilde` (14.10.2026): Forever liefert Vor- UND Nachname
--  plus Gildenrang.
--  @return Liste aus { name, rang, rangIndex } oder nil und ein Grund
function Gruppen.GildenMitglieder()
    local liste = {}

    local CC = rawget(_G, "C_Club")
    if CC and CC.GetGuildClubId and CC.GetClubMembers and CC.GetMemberInfo then
        local ok, clubId = pcall(CC.GetGuildClubId)
        if ok and clubId then
            local ok2, ids = pcall(CC.GetClubMembers, clubId)
            if ok2 and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    local ok3, info = pcall(CC.GetMemberInfo, clubId, id)
                    if ok3 and type(info) == "table" and info.name then
                        local online = Gruppen.PraesenzOnline(info.presence)
                        liste[#liste + 1] = {
                            name = info.name,
                            rang = info.guildRank,
                            rangIndex = info.guildRankOrder,
                            online = online and true or false,
                        }
                    end
                end
            end
        end
    end

    if #liste == 0 then
        local anzahl = rawget(_G, "GetNumGuildMembers")
        local info = rawget(_G, "GetGuildRosterInfo")
        if anzahl and info then
            for i = 1, (anzahl() or 0) do
                local name, rang, rangIndex, _, _, _, _, _, isOnline = info(i)
                if name then
                    liste[#liste + 1] = {
                        name = name,
                        rang = rang,
                        rangIndex = rangIndex,
                        online = isOnline and true or false,
                    }
                end
            end
        end
    end

    if #liste == 0 then return nil, L["Die Gildenliste ist noch nicht geladen."] end
    return liste
end

local rangCache = { t = -100 }

--- Die Raenge der Gilde, vom hoechsten zum niedrigsten.
--  ⚠️ Fuenf Sekunden gemerkt: Das Einstellungsfenster fragt sie je Zeile
--  mehrfach, und die Gildenliste durchzugehen ist nicht billig.
--  @return Liste aus { index, name } oder nil und ein Grund
function Gruppen.Raenge()
    local jetzt = (GetTime and GetTime()) or time()
    if (jetzt - rangCache.t) < 5 then return rangCache.r, rangCache.grund end
    local r, g = Gruppen.RaengeNeu()
    rangCache = { t = jetzt, r = r, grund = g }
    return r, g
end

function Gruppen.RaengeNeu()
    local M, grund = Gruppen.GildenMitglieder()
    if not M then return nil, grund end

    local gesehen, raenge = {}, {}
    for _, m in ipairs(M) do
        local i = m.rangIndex
        if i ~= nil and not gesehen[i] then
            gesehen[i] = true
            raenge[#raenge + 1] = { index = i, name = tostring(m.rang or i) }
        end
    end
    table.sort(raenge, function(a, b) return a.index < b.index end)
    return raenge
end

function Gruppen.RangGewaehlt(gruppe, index)
    local G = Gruppen.Holen(gruppe)
    return G and G.raenge[index] and true or false
end

function Gruppen.RangSetzen(gruppe, index, an)
    local G = Gruppen.Holen(gruppe)
    if not G then return false end
    G.raenge[index] = an and true or nil
    return true
end

-- =====================================================================
--  Mitgliederabgleich
-- =====================================================================

--- ⭐ Gleicht den Kader mit den Gildenraengen ab.
--
--  Mit gewaehlten Raengen: Kader = genau deren Mitglieder (hinzufuegen UND
--  entfernen). Ohne Raenge: nichts, was sich sicher entfernen liesse — dann
--  nimmt er nur Gildenmitglieder der aktuellen Gruppe zusaetzlich auf.
--
--  @param still  nur beim automatischen Lauf: kein Nachfragen, bei
--                Auffaelligkeiten wird gar nichts entfernt
--  @return neu, entfernt  oder  nil und ein Grund
function Gruppen.Synchronisieren(name, still)
    local G = Gruppen.Holen(name)
    if not G then return nil, L["Keine Gruppe aktiv."] end

    local gewaehlt = false
    for _ in pairs(G.raenge) do gewaehlt = true break end

    if not gewaehlt then
        -- ⚠️ Nur in einer Gruppe: Ohne Gruppe liefert Rolle.Namen den Spieler
        -- selbst, und der wuerde ungefragt aufgenommen.
        if not (IsInGroup and IsInGroup()) then
            return nil, L["Keine Gruppe und keine Gildenränge gewählt – nichts zum Synchronisieren."]
        end
        return hinzufuegen(G.extra, ns.Rolle.Namen(true)), 0
    end

    local M, grund = Gruppen.GildenMitglieder()
    if not M then return nil, grund end

    local neueListe = {}
    for _, m in ipairs(M) do
        if G.raenge[m.rangIndex] then neueListe[#neueListe + 1] = m.name end
    end
    -- Niemand in den gewaehlten Raengen: eher ein Zeichen fuer eine unvollstaendige
    -- oder veraenderte Gilde als fuer einen leeren Kader. Nichts anfassen.
    if #neueListe == 0 then
        return nil, L["In den gewählten Rängen ist niemand – nichts geändert."]
    end
    table.sort(neueListe, function(a, b) return a:lower() < b:lower() end)

    local hinzu, weg = 0, 0
    for _, n in ipairs(neueListe) do
        if not enthalten(G.kader, n) then hinzu = hinzu + 1 end
    end
    for _, n in ipairs(G.kader) do
        if not enthalten(neueListe, n) then weg = weg + 1 end
    end

    -- Schutz: auffaellig viele Abgaenge auf einmal -> erst bestaetigen lassen
    if weg > 0 and #G.kader >= 10 and weg > math.max(4, #G.kader * 0.4) then
        if still then
            hinzufuegen(G.kader, neueListe)   -- nur die Neuen, entfernt wird nichts
            return hinzu, 0, true
        end
        local jetzt = time()
        if not (G.warnung and (jetzt - G.warnung) < 120) then
            G.warnung = jetzt
            return nil, string.format(
                L["Auffällig viele würden entfernt (%d von %d). Die Gildenliste ist vielleicht noch nicht vollständig geladen. Nochmal klicken, um es trotzdem zu tun."],
                weg, #G.kader)
        end
    end
    G.warnung = nil

    G.kader = neueListe
    return hinzu, weg
end

--- Beim Anmelden einmal still abgleichen, wenn die Gruppe es will und
--  Raenge gewaehlt sind. Meldet nur, wenn sich etwas geaendert hat.
function Gruppen.AutoSynchronisieren()
    -- Ohne Plündermeister als Beutemethode ruht das Addon (Entscheid 15.10.2026).
    if not ns.Rolle.Aktiv() then return end
    local name = Gruppen.AktivName()
    local G = Gruppen.Holen(name)
    if not G or G.auto == false then return end
    local gewaehlt = false
    for _ in pairs(G.raenge) do gewaehlt = true break end
    if not gewaehlt then return end

    local hinzu, weg, uebersprungen = Gruppen.Synchronisieren(name, true)
    if hinzu and (hinzu > 0 or (weg or 0) > 0) then
        print("|cff1B6B57Fairshare|r: " ..
            string.format(L["Kader „%s“: %d neu, %d entfernt."], name, hinzu, weg or 0))
    end
    if uebersprungen then
        print("|cff1B6B57Fairshare|r: " ..
            string.format(L["Kader „%s“: Entfernen übersprungen (zu viele auf einmal) – bitte in den Einstellungen prüfen."], name))
    end
end

-- =====================================================================
--  ⭐ Raidkader (Pool) und Einteilung je Abend und Gruppe (Entscheid 17.10.2026)
--
--  Die Gruppen wechseln von Woche zu Woche. Darum gibt es
--    * den **Raidkader**: ein Knopf liest die Gildenliste bis zu einem gewaehlten Gildenrang ein; daraus
--      laesst sich anklicken, wer in eine Gruppe kommt (statt Namen zu tippen), und
--    * die **Einteilung** je Kalendertag: fuer jeden Spieler steht, in welcher Gruppe er an diesem Tag ist
--      (hoechstens in einer). Sie wird an alle mit dem Addon verteilt (Nachricht `T`).
--
--  Verteilen ohne Streit: Je Spieler und Tag gibt es EINEN Eintrag { Gruppe, Zeit, Urheber }; der juengere
--  gewinnt, bei gleicher Zeit der Urheber mit dem groesseren Namen. So konvergieren alle Clients, auch wenn
--  zwei Leiter gleichzeitig aendern. Eine leere Gruppe bedeutet „nicht eingeteilt“.
-- =====================================================================

local function ichName()
    if GetUnitName then
        local n = GetUnitName("player", true)
        if n and n ~= "" then return n end
    end
    return (UnitName and UnitName("player")) or "Spieler"
end

--- Der Gildenrang, bis zu dem der Raidkader eingelesen wird (Rangindex; kleiner = hoeher).
function Gruppen.RaidkaderRang()
    return db().raidkaderRang
end

function Gruppen.RaidkaderRangSetzen(index)
    db().raidkaderRang = tonumber(index)
end

--- ⭐ Liest die Gildenliste bis zum gewaehlten Rang ein: das ist der Raidkader.
--  @param bisRang  Rangindex (alle bis einschliesslich diesem Rang); sonst der gemerkte
--  @return Zahl der Mitglieder, oder nil und ein Grund
function Gruppen.RaidkaderSync(bisRang)
    bisRang = tonumber(bisRang) or db().raidkaderRang
    if bisRang == nil then return nil, L["Bitte erst einen Gildenrang wählen."] end
    local M, grund = Gruppen.GildenMitglieder()
    if not M then return nil, grund end

    local liste = {}
    for _, m in ipairs(M) do
        if m.rangIndex ~= nil and m.rangIndex <= bisRang then
            liste[#liste + 1] = { name = m.name, rang = tostring(m.rang or m.rangIndex), rangIndex = m.rangIndex }
        end
    end
    -- Niemand in den Raengen: eher eine unvollstaendig geladene Gildenliste als ein leerer Kader.
    if #liste == 0 then return nil, L["In den gewählten Rängen ist niemand – nichts geändert."] end
    table.sort(liste, function(a, b) return a.name:lower() < b.name:lower() end)

    local d = db()
    d.raidkader = { stand = time(), bisRang = bisRang, namen = liste }
    d.raidkaderRang = bisRang
    return #liste
end

--- Der eingelesene Raidkader: Liste aus { name, rang, rangIndex } (leer, wenn noch nicht eingelesen).
function Gruppen.Raidkader()
    local r = db().raidkader
    return (r and r.namen) or {}, r and r.stand
end

local TAG = 86400

--- Das Datum (JJJJ-MM-TT) von heute plus `tage`.
function Gruppen.EinteilungTag(tage)
    return date("%Y-%m-%d", time() + (tonumber(tage) or 0) * TAG)
end

local function einteilungen()
    local d = db()
    d.einteilung = d.einteilung or {}
    return d.einteilung
end

--- Alte Tage entfernen (aelter als drei Wochen).
local function einteilungAufraeumen()
    local grenze = date("%Y-%m-%d", time() - 21 * TAG)
    local E = einteilungen()
    for tag in pairs(E) do
        if type(tag) ~= "string" or tag < grenze then E[tag] = nil end
    end
end

--- In welcher Gruppe ist der Spieler an diesem Tag?
--  @return Gruppenname, Eintrag  oder nil (nicht eingeteilt)
function Gruppen.EinteilungVon(datum, name)
    local T = einteilungen()[datum]
    local k = Kern.Schluessel(name)
    local e = T and k and T[k]
    if e and e.gruppe and e.gruppe ~= "" then return e.gruppe, e end
    return nil
end

-- ---------------------------------------------------------------------
--  ⭐ Raidtage JE GRUPPE (Entscheid 18.10.2026): Jede Gruppe hat ihre eigenen Raidtage, das ist ihre Raid-ID.
--  Die Gruppen raiden an verschiedenen oder an denselben Tagen; die Einteilung eines Tages gibt es für jeden Tag,
--  an dem irgendeine Gruppe raidet.
-- ---------------------------------------------------------------------

-- Lua-Wochentag (date("*t").wday): 1 = Sonntag … 7 = Samstag. Angezeigt wird Montag bis Sonntag.
local WOCHENFOLGE = { 2, 3, 4, 5, 6, 7, 1 }

--- Die Wochentage in Anzeigereihenfolge (Montag bis Sonntag), als Lua-Wochentag.
function Gruppen.RaidtageFolge()
    return WOCHENFOLGE
end

function Gruppen.RaidtagName(wday)
    local N = { [1] = L["So"], [2] = L["Mo"], [3] = L["Di"], [4] = L["Mi"], [5] = L["Do"], [6] = L["Fr"], [7] = L["Sa"] }
    return N[wday] or "?"
end

--- Raidet diese Gruppe an diesem Wochentag?
function Gruppen.RaidtagGewaehlt(gruppe, wday)
    local G = Gruppen.Holen(gruppe)
    return (G and G.raidtage and G.raidtage[wday]) and true or false
end

function Gruppen.RaidtagSetzen(gruppe, wday, an)
    wday = tonumber(wday)
    local G = Gruppen.Holen(gruppe)
    if not G or not wday or wday < 1 or wday > 7 then return false end
    G.raidtage = G.raidtage or {}
    G.raidtage[wday] = an and true or nil
    return true
end

--- Die Raidtage einer Gruppe als Text (z. B. „Mo, Do“), leer ohne Raidtage.
function Gruppen.RaidtageText(gruppe)
    local teile = {}
    for _, wd in ipairs(WOCHENFOLGE) do
        if Gruppen.RaidtagGewaehlt(gruppe, wd) then teile[#teile + 1] = Gruppen.RaidtagName(wd) end
    end
    return table.concat(teile, ", ")
end

--- ⭐ Die Tage, für die es eine Einteilung gibt: das nächste Vorkommen (ab heute) jedes Raidtags irgendeiner Gruppe,
--  nach Datum sortiert, mit den Gruppen, die an dem Tag raiden. Hat keine Gruppe Raidtage: heute und morgen.
--  „Heute“ steht immer vorn.
--  @return Liste aus { datum, label }
function Gruppen.EinteilungTage()
    local jetzt = time()
    local heute = date("%Y-%m-%d", jetzt)
    local tage = {}
    local irgendeiner = false
    for _, gn in ipairs(Gruppen.Namen()) do
        for tag = 0, 6 do
            local t = jetzt + tag * TAG
            local wd = date("*t", t).wday
            if Gruppen.RaidtagGewaehlt(gn, wd) then
                irgendeiner = true
                local datum = date("%Y-%m-%d", t)
                tage[datum] = tage[datum] or { t = t, wd = wd, gruppen = {} }
                table.insert(tage[datum].gruppen, gn)
            end
        end
    end
    local liste = {}
    if irgendeiner then
        for datum, e in pairs(tage) do
            local name = Gruppen.RaidtagName(e.wd) .. " " .. date(L["%d.%m."], e.t)
            if #e.gruppen <= 2 then name = name .. " · " .. table.concat(e.gruppen, "/") end
            liste[#liste + 1] = { datum = datum, label = name }
        end
        table.sort(liste, function(a, b) return a.datum < b.datum end)
        if liste[1].datum ~= heute then
            table.insert(liste, 1, { datum = heute, label = L["Heute"] })
        end
    else
        liste = {
            { datum = heute,                          label = L["Heute"] },
            { datum = date("%Y-%m-%d", jetzt + TAG), label = L["Morgen"] },
        }
    end
    return liste
end

--- Die Namen, die an diesem Tag in dieser Gruppe eingeteilt sind (alphabetisch).
function Gruppen.EinteilungListe(datum, gruppe)
    local liste = {}
    for _, e in pairs(einteilungen()[datum] or {}) do
        if e.gruppe == gruppe then liste[#liste + 1] = e.name end
    end
    table.sort(liste, function(a, b) return a:lower() < b:lower() end)
    return liste
end

--- Die Spieler auf der Bench an diesem Tag.
function Gruppen.BenchListe(datum)
    return Gruppen.EinteilungListe(datum, Gruppen.BENCH)
end

--- Gibt es fuer diesen Tag ueberhaupt eine Einteilung (in irgendeiner Gruppe)?
function Gruppen.EinteilungVorhanden(datum)
    for _, e in pairs(einteilungen()[datum] or {}) do
        if e.gruppe and e.gruppe ~= "" then return true end
    end
    return false
end

--- ⭐ Wer darf einteilen? Nur wer laut Einstellungen schreiben darf (Gildenrang wie beim Teilen der
--  Einstellungen, Entscheid 17.10.2026) — Raidleiter und Assistenten allein genügen nicht.
function Gruppen.EinteilungDarf(name)
    name = name or ichName()
    if name == "System" then return true end
    return (ns.Konfig and ns.Konfig.Darf and ns.Konfig.Darf(name)) and true or false
end

local function tagOk(datum)
    if type(datum) ~= "string" or not datum:match("^%d%d%d%d%-%d%d%-%d%d$") then return false end
    return datum >= date("%Y-%m-%d", time() - 3 * TAG) and datum <= date("%Y-%m-%d", time() + 21 * TAG)
end

local function gruppeOk(g)
    return type(g) == "string" and #g <= 40 and not g:find("[;~|%c]")
end

local function nameOk(n)
    return type(n) == "string" and #n >= 1 and #n <= 40 and not n:find("[;~|,%c]")
end

--- Traegt einen Spieler ein (der juengere Eintrag gewinnt). @return true, wenn sich etwas geaendert hat
local function einteilungEinsetzen(datum, name, gruppe, zeit, von)
    local k = Kern.Schluessel(name)
    if not k then return false end
    local T = einteilungen()
    T[datum] = T[datum] or {}
    local alt = T[datum][k]
    if alt and ((alt.zeit or 0) > zeit or ((alt.zeit or 0) == zeit and tostring(alt.von or "") >= tostring(von))) then
        return false
    end
    T[datum][k] = { name = Kern.Anzeigename(name), gruppe = gruppe or "", zeit = zeit, von = von }
    return true
end

--- Eine Meldung `T;<Datum>;<Urheber>;<Name>|<Gruppe>|<Zeit>~<Name>|<Gruppe>|<Zeit>…` an die Gilde und die Gruppe.
--  @param schluessel  Liste der Spielerschluessel dieses Tages (nil = alle)
function Gruppen.EinteilungSenden(datum, schluessel)
    local T = einteilungen()[datum]
    if not T or not ns.Abgleich or not ns.Abgleich.Senden then return false end
    local von = ichName()
    local teile, aktuell = {}, ""
    local function anhaengen(stueck)
        if aktuell ~= "" and #aktuell + 1 + #stueck > 200 then
            teile[#teile + 1] = aktuell
            aktuell = stueck
        else
            aktuell = (aktuell == "") and stueck or (aktuell .. "~" .. stueck)
        end
    end
    local keys = schluessel
    if not keys then
        keys = {}
        for k in pairs(T) do keys[#keys + 1] = k end
        table.sort(keys)
    end
    for _, k in ipairs(keys) do
        local e = T[k]
        if e and nameOk(e.name) and gruppeOk(e.gruppe or "") then
            anhaengen(string.format("%s|%s|%d", e.name, e.gruppe or "", e.zeit or 0))
        end
    end
    if aktuell ~= "" then teile[#teile + 1] = aktuell end
    for _, teil in ipairs(teile) do
        local text = string.format("T;%s;%s;%s", datum, von, teil)
        ns.Abgleich.Senden(text, false, "GUILD")
        ns.Abgleich.Senden(text, false)               -- Gruppenkanal, wenn man in einer Gruppe ist
    end
    return #teile > 0
end

--- ⭐ Teilt einen Spieler fuer einen Tag einer Gruppe zu (leer/nil = nicht eingeteilt). In hoechstens einer Gruppe.
--  @return true, oder nil und ein Grund
function Gruppen.EinteilungSetzen(datum, name, gruppe, von)
    von = von or ichName()
    if not Gruppen.EinteilungDarf(von) then
        return nil, L["Keine Berechtigung (nur Gildenränge mit Schreibrecht)."]
    end
    if not tagOk(datum) then return nil, L["Ungültiges Datum."] end
    if not nameOk(name) then return nil, L["Ungültiger Spielername."] end
    gruppe = gruppe or ""
    if gruppe ~= "" and not (gruppeOk(gruppe) and (gruppe == Gruppen.BENCH or gruppe == Gruppen.KEINEMELDUNG or Gruppen.Holen(gruppe))) then
        return nil, L["Diese Gruppe gibt es nicht."]
    end

    local k = Kern.Schluessel(name)
    local alt = einteilungen()[datum] and einteilungen()[datum][k]
    local zeit = time()
    if alt and (alt.zeit or 0) >= zeit then zeit = alt.zeit + 1 end     -- immer juenger als der eigene alte Eintrag
    einteilungEinsetzen(datum, name, gruppe, zeit, von)
    einteilungAufraeumen()
    Gruppen.EinteilungSenden(datum, { k })
    return true
end

local eMerke = {}

--- Letzte Meldungen zur Einteilung (fuer `/fs einteilung status`).
function Gruppen.EinteilungStatus()
    return eMerke
end

--- Eine Einteilungsmeldung ist eingetroffen (Gilde oder Gruppe).
function Gruppen.EinteilungEmpfangen(rest, sender, kanalName)
    if type(rest) ~= "string" or Kern.GleicherSpieler(sender, ichName()) then return end
    local function merke(text)
        eMerke[#eMerke + 1] = date("%H:%M:%S", time()) .. "  " .. text
        if #eMerke > 8 then table.remove(eMerke, 1) end
    end

    local datum, von, teil = rest:match("^(%d%d%d%d%-%d%d%-%d%d);([^;]*);(.*)$")
    if not datum or not tagOk(datum) or not nameOk(von) then
        merke(string.format(L["Einteilung von %s: Nachricht ungültig"], tostring(sender)))
        return
    end
    -- Es gilt der Absender selbst, nicht die Angabe im Text (kein Weiterreichen).
    if not Kern.GleicherSpieler(sender, von) then
        merke(string.format(L["Einteilung von %s: Urheber stimmt nicht"], tostring(sender)))
        return
    end
    if not Gruppen.EinteilungDarf(sender) then
        merke(string.format(L["Einteilung von %s: Absender darf nicht einteilen"], tostring(sender)))
        return
    end

    local n, neu = 0, 0
    local jetzt = time()
    for eintrag in (teil .. "~"):gmatch("(.-)~") do
        if eintrag ~= "" then
            n = n + 1
            if n > 60 then break end
            local name, gruppe, zeit = eintrag:match("^([^|]+)|([^|]*)|(%d+)$")
            zeit = tonumber(zeit)
            if name and nameOk(name) and gruppeOk(gruppe) and zeit and zeit > 1000000000 and zeit <= jetzt + 2 * TAG then
                if einteilungEinsetzen(datum, name, gruppe, zeit, von) then neu = neu + 1 end
            end
        end
    end
    einteilungAufraeumen()
    merke(string.format(L["Einteilung von %s angenommen: %d Einträge, %d neu"], tostring(sender), n, neu))
    if ns.Fenster and ns.Fenster.Sichtbar and ns.Fenster.Sichtbar() then ns.Fenster.Aktualisieren() end
end

local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- Die Gildenliste braucht einen Moment.
    if C_Timer then
        C_Timer.After(20, function() pcall(Gruppen.AutoSynchronisieren) end)
    end
end)

return ns
