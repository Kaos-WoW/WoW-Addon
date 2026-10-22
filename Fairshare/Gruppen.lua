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

--- Liefert den Namen der Bench für eine Raid-Größe (z. B. „Bench (10er)“).
function Gruppen.BenchName(groesse)
    groesse = tonumber(groesse) or 40
    return string.format(L["Bench (%der)"], groesse)
end

--- Ist das eine Bench (allgemein oder für eine bestimmte Größe)?
function Gruppen.IstBench(name)
    local n = tostring(name or ""):lower()
    return n == "bench" or n:find("^bench") ~= nil
end

--- Liefert die Raid-Größe einer Gruppe (10, 20 oder 40).
function Gruppen.Groesse(name)
    if not name or name == "" then return 40 end
    local n = tostring(name):lower()
    if n:find("10") then
        local G = db().gruppen and db().gruppen[name]
        if G and G.groesse then return tonumber(G.groesse) or 10 end
        return 10
    end
    if n:find("20") then
        local G = db().gruppen and db().gruppen[name]
        if G and G.groesse then return tonumber(G.groesse) or 20 end
        return 20
    end
    local G = db().gruppen and db().gruppen[name]
    if G and G.groesse then return tonumber(G.groesse) or 40 end
    if n:find("40") then return 40 end
    return 40
end

--- Setzt die Raid-Größe einer Gruppe (10, 20 oder 40).
function Gruppen.GroesseSetzen(name, groesse)
    groesse = tonumber(groesse)
    if not (groesse == 10 or groesse == 20 or groesse == 40) then return false end
    local G = Gruppen.Holen(name)
    if not G then return false end
    G.groesse = groesse
    return true
end

--- Ist das ein reservierter Name (Bench oder Keine Meldung)?
function Gruppen.Reserviert(name)
    local n = tostring(name or ""):lower()
    return Gruppen.IstBench(n) or n == Gruppen.KEINEMELDUNG:lower()
end

function Gruppen.Anlegen(name, groesse)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return false, L["kein Name"] end
    if Gruppen.Reserviert(name) then return false, L["Dieser Name ist reserviert."] end
    if #name > 40 then return false, L["Name zu lang (höchstens 40 Zeichen)"] end
    -- ⚠️ Kein Semikolon und keine Steuerzeichen: Der Name geht beim Abgleich
    -- mit auf die Reise. Kodieren schuetzt zwar, aber Ruhe ist besser.
    if name:find("[;~|%c]") then return false, L["Zeichen nicht erlaubt"] end

    local d = db()
    if d.gruppen[name] then return false, L["gibt es schon"] end
    groesse = tonumber(groesse)
    if not (groesse == 10 or groesse == 20 or groesse == 40) then
        groesse = Gruppen.Groesse(name)
    end
    d.gruppen[name] = { name = name, kader = {}, extra = {}, raenge = {}, auto = true, groesse = groesse }
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

--- Der Klassenschluessel (z. B. "WARRIOR") zu einer Klassen-ID, oder nil.
function Gruppen.KlasseAusId(id)
    local CI = rawget(_G, "C_CreatureInfo")
    if not id or not CI or not CI.GetClassInfo then return nil end
    local ok, info = pcall(CI.GetClassInfo, id)
    if ok and type(info) == "table" and type(info.classFile) == "string" then return info.classFile end
    return nil
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
                            klasse = Gruppen.KlasseAusId(info.classID),
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
                local name, rang, rangIndex, _, _, _, _, _, isOnline, _, klasse = info(i)
                if name then
                    liste[#liste + 1] = {
                        name = name,
                        rang = rang,
                        rangIndex = rangIndex,
                        klasse = type(klasse) == "string" and klasse ~= "" and klasse or nil,
                        online = isOnline and true or false,
                    }
                end
            end
        end
    end

    if #liste == 0 then return nil, L["Die Gildenliste ist noch nicht geladen."] end
    return liste
end

-- ---------------------------------------------------------------------
--  Rang und Klasse eines Spielers (Sortierung und Klassenfarbe in den Listen)
-- ---------------------------------------------------------------------

local infoCache = { t = -100, nach = {} }

--- Rang (kleiner = hoeher) und Klasse eines Gildenmitglieds, oder nil.
--  ⚠️ Fuenf Sekunden gemerkt: Die Listen fragen es je Zeile und je Vergleich.
--  @return { rangIndex, klasse } oder nil
function Gruppen.MitgliedInfo(name)
    local k = Kern.Schluessel(name)
    if not k then return nil end
    local jetzt = (GetTime and GetTime()) or time()
    if (jetzt - infoCache.t) >= 5 then
        local nach = {}
        local M = Gruppen.GildenMitglieder()
        for _, m in ipairs(M or {}) do
            local mk = Kern.Schluessel(m.name)
            if mk then nach[mk] = { rangIndex = m.rangIndex, klasse = m.klasse } end
        end
        infoCache = { t = jetzt, nach = nach }
    end
    return infoCache.nach[k]
end

--- Der Rang als Zahl fuer die Sortierung (0 = Gildenmeister); unbekannte Spieler kommen zuletzt.
function Gruppen.RangZahl(name)
    local i = Gruppen.MitgliedInfo(name)
    return (i and tonumber(i.rangIndex)) or 999
end

--- Sortierung: hoechster Gildenrang oben, bei gleichem Rang nach Name.
function Gruppen.RangVor(a, b)
    local ra, rb = Gruppen.RangZahl(a), Gruppen.RangZahl(b)
    if ra ~= rb then return ra < rb end
    return Kern.Anzeigename(a):lower() < Kern.Anzeigename(b):lower()
end

--- Der Farbcode "|cffRRGGBB" einer Klasse (Schluessel wie "WARRIOR"), oder nil.
function Gruppen.KlasseFarbcode(klasse)
    local tab = klasse and (rawget(_G, "CUSTOM_CLASS_COLORS") or rawget(_G, "RAID_CLASS_COLORS"))
    local c = tab and tab[klasse]
    if type(c) ~= "table" or not c.r then return nil end
    return string.format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

--- Die Klassenfarbe eines Spielers als Farbcode "|cffRRGGBB", oder nil, wenn die Klasse unbekannt ist.
--  Gildenmitglieder kommen aus der Gildenliste, alle anderen aus der Gruppe.
function Gruppen.KlassenFarbe(name)
    local i = Gruppen.MitgliedInfo(name)
    local klasse = i and i.klasse
    if not klasse and UnitClass and name then
        local ok, _, datei = pcall(UnitClass, name)
        if ok and type(datei) == "string" then klasse = datei end
    end
    return Gruppen.KlasseFarbcode(klasse)
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

local function tabelleKopie(t)
    local k = {}
    for a, b in pairs(t or {}) do k[a] = b end
    return k
end

--- Die gewählten Ränge für den Raidkader als Set-Tabelle: { [rangIndex] = true }.
function Gruppen.RaidkaderRaenge()
    local d = db()
    if d.raidkaderRaenge then
        return d.raidkaderRaenge
    end
    if d.raidkaderRang ~= nil then
        local t = {}
        for i = 0, d.raidkaderRang do
            t[i] = true
        end
        return t
    end
    return {}
end

--- Prüft, ob ein bestimmter Gildenrang (nach Index) im Raidkader gewählt ist.
function Gruppen.RaidkaderRangGewaehlt(index)
    index = tonumber(index)
    if index == nil then return false end
    local raenge = Gruppen.RaidkaderRaenge()
    return raenge[index] and true or false
end

--- Setzt alle gewählten Ränge auf einmal aus einer Set- oder Array-Tabelle.
function Gruppen.RaidkaderRaengeSetzen(tabelle)
    local d = db()
    d.raidkaderRaenge = {}
    if type(tabelle) == "table" then
        for k, v in pairs(tabelle) do
            if type(k) == "number" and v then
                d.raidkaderRaenge[k] = true
            elseif tonumber(v) then
                d.raidkaderRaenge[tonumber(v)] = true
            end
        end
    end
    local maxRang = nil
    for idx in pairs(d.raidkaderRaenge) do
        if maxRang == nil or idx > maxRang then maxRang = idx end
    end
    d.raidkaderRang = maxRang
end

--- Wählt einen Rang aus (an=true/false) oder setzt alle bis zu diesem Rang (wenn an==nil).
function Gruppen.RaidkaderRangSetzen(index, an)
    local d = db()
    if not d.raidkaderRaenge then
        d.raidkaderRaenge = {}
        if d.raidkaderRang ~= nil then
            for i = 0, d.raidkaderRang do d.raidkaderRaenge[i] = true end
        end
    end

    if an ~= nil then
        index = tonumber(index)
        if index ~= nil then
            d.raidkaderRaenge[index] = an and true or nil
        end
    else
        -- 1 Parameter: "bis zu diesem Rang" (wie bisher) oder nil zum Leeren
        if index == nil then
            d.raidkaderRaenge = {}
            d.raidkaderRang = nil
            return
        end
        local bis = tonumber(index)
        if bis ~= nil then
            d.raidkaderRaenge = {}
            for i = 0, bis do
                d.raidkaderRaenge[i] = true
            end
        end
    end

    local maxRang = nil
    for idx in pairs(d.raidkaderRaenge) do
        if maxRang == nil or idx > maxRang then maxRang = idx end
    end
    d.raidkaderRang = maxRang
end

--- Gibt true zurück, wenn mindestens ein Gildenrang für den Raidkader gewählt ist.
function Gruppen.RaidkaderHatRaenge()
    local raenge = Gruppen.RaidkaderRaenge()
    return next(raenge) ~= nil
end

--- Der Gildenrang, bis zu dem der Raidkader eingelesen wird (bzw. höchster gewählter Rang; kleiner = höher).
function Gruppen.RaidkaderRang()
    local d = db()
    if d.raidkaderRaenge and next(d.raidkaderRaenge) then
        local maxRang = nil
        for idx in pairs(d.raidkaderRaenge) do
            if maxRang == nil or idx > maxRang then maxRang = idx end
        end
        return maxRang
    end
    return d.raidkaderRang
end

--- ⭐ Liest die Gildenliste für die gewählten Ränge ein: das ist der Raidkader.
--  @param param  Optional: Zahl (bis zu diesem Rang), Tabelle (Ränge), oder nil (die gemerkten)
--  @return Zahl der Mitglieder, oder nil und ein Grund
function Gruppen.RaidkaderSync(param)
    local d = db()
    if type(param) == "number" or (type(param) == "string" and tonumber(param)) then
        Gruppen.RaidkaderRangSetzen(tonumber(param))
    elseif type(param) == "table" then
        Gruppen.RaidkaderRaengeSetzen(param)
    end

    local raenge = Gruppen.RaidkaderRaenge()
    if not next(raenge) then return nil, L["Bitte erst einen Gildenrang wählen."] end
    local M, grund = Gruppen.GildenMitglieder()
    if not M then return nil, grund end

    local liste = {}
    for _, m in ipairs(M) do
        if m.rangIndex ~= nil and raenge[m.rangIndex] then
            liste[#liste + 1] = { name = m.name, rang = tostring(m.rang or m.rangIndex), rangIndex = m.rangIndex }
        end
    end
    -- Niemand in den Rängen: eher eine unvollständig geladene Gildenliste als ein leerer Kader.
    if #liste == 0 then return nil, L["In den gewählten Rängen ist niemand – nichts geändert."] end
    table.sort(liste, function(a, b) return a.name:lower() < b.name:lower() end)

    local rliste = {}
    for r in pairs(raenge) do rliste[#rliste + 1] = r end
    table.sort(rliste)

    d.raidkader = { stand = time(), raenge = rliste, bisRang = d.raidkaderRang, namen = liste }
    return #liste
end

--- Liest den Raidkader still ein, wenn ein Rang gewählt ist (beim Anmelden und nach neuen geteilten Einstellungen).
function Gruppen.RaidkaderAuto()
    if not Gruppen.RaidkaderHatRaenge() then return false end
    local n = Gruppen.RaidkaderSync()
    if n and ns.Fenster and ns.Fenster.Sichtbar and ns.Fenster.Sichtbar() then ns.Fenster.Aktualisieren() end
    return n and true or false
end

--- Der eingelesene Raidkader: Liste aus { name, rang, rangIndex } (leer, wenn noch nicht eingelesen).
function Gruppen.Raidkader()
    local r = db().raidkader
    return (r and r.namen) or {}, r and r.stand
end

local TAG = 86400

-- ---------------------------------------------------------------------
--  ⭐ Raid-ID (Entscheid 22.10.2026): Die Einteilung gilt einmal je Raid-ID statt je Tag. Die ID wechselt an einem
--  einstellbaren Wochentag (Standard Mittwoch, geteilte Einstellung); ihr Schlüssel ist das Datum ihres ersten Tages.
-- ---------------------------------------------------------------------

--- Der Wochentag (Lua: 1 = Sonntag … 7 = Samstag), an dem eine neue Raid-ID beginnt. Standard: Mittwoch.
function Gruppen.IdWechsel()
    local w = tonumber(db().idWechsel)
    return (w and w >= 1 and w <= 7) and math.floor(w) or 4
end

function Gruppen.IdWechselSetzen(wday)
    wday = tonumber(wday)
    if not wday or wday < 1 or wday > 7 then return false end
    db().idWechsel = math.floor(wday)
    return true
end

--- Das Datum (JJJJ-MM-TT) des ersten Tages der Raid-ID, in der `datum` liegt.
function Gruppen.IdStart(datum)
    datum = datum or date("%Y-%m-%d", time())
    local y, m, d = tostring(datum):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return datum end
    local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    local wd = date("*t", t).wday
    local zurueck = (wd - Gruppen.IdWechsel()) % 7
    return date("%Y-%m-%d", t - zurueck * TAG)
end

--- Die Raid-IDs, an denen man arbeitet: diese und die nächste. @return Liste aus { datum (Schlüssel), label }
function Gruppen.IdListe()
    local jetzt = time()
    local liste = {}
    for i = 0, 1 do
        local start = Gruppen.IdStart(date("%Y-%m-%d", jetzt + i * 7 * TAG))
        local y, m, d = start:match("^(%d+)-(%d+)-(%d+)$")
        local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
        liste[#liste + 1] = {
            datum = start,
            label = string.format(i == 0 and L["Diese ID (ab %s)"] or L["Nächste ID (ab %s)"],
                Gruppen.RaidtagName(date("*t", t).wday) .. " " .. date(L["%d.%m."], t)),
        }
    end
    return liste
end

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
--  @param kat  Optionale Raid-Größe (10, 20 oder 40). Wenn angegeben, wird die Gruppe dieser Größe geliefert.
--- Liefert die Einteilungen eines Spielers als Tabelle { [10] = gruppe, [20] = gruppe, [40] = gruppe }
function Gruppen.MeineEinteilung(name, datum)
    name = name or ichName()
    local res = {}
    for _, kat in ipairs({ 10, 20, 40 }) do
        local g = Gruppen.EinteilungVon(datum, name, kat)
        if g and g ~= "" then res[kat] = g end
    end
    return res
end

--- Formatierter Text der eigenen Einteilungen für die Anzeige (z. B. "[10er] Kara 1  ·  [40er] MC").
function Gruppen.MeineEinteilungText(name, datum)
    name = name or ichName()
    local res = Gruppen.MeineEinteilung(name, datum)
    local teile = {}
    for _, kat in ipairs({ 10, 20, 40 }) do
        if res[kat] then
            local label = Gruppen.IstBench(res[kat]) and L["Bench"] or res[kat]
            teile[#teile + 1] = string.format(L["[%der] %s"], kat, label)
        end
    end
    if #teile > 0 then
        return table.concat(teile, "  ·  ")
    end
    return nil
end

--- Fragt die aktuelle Einteilung über den Kanal an (z. B. beim Fenster öffnen).
function Gruppen.EinteilungAnfragen(kanalName)
    if not ns.Abgleich or not ns.Abgleich.Senden then return false end
    return ns.Abgleich.Senden("T;?", false, kanalName or "GUILD")
end

--  @return Gruppenname, Eintrag  oder nil (nicht eingeteilt)
function Gruppen.EinteilungVon(datum, name, kat)
    local T = einteilungen()[Gruppen.IdStart(datum)]
    local k = Kern.Schluessel(name)
    local e = T and k and T[k]
    if not e then return nil end
    if kat then
        kat = tonumber(kat)
        if e.gruppen and e.gruppen[kat] and e.gruppen[kat] ~= "" then
            return e.gruppen[kat], e
        end
        if e.gruppe and e.gruppe ~= "" and Gruppen.Groesse(e.gruppe) == kat then
            return e.gruppe, e
        end
        return nil
    end
    -- Ohne Kategorie: wenn e.gruppe vorhanden ist und noch stimmt
    if e.gruppe and e.gruppe ~= "" then
        if not e.gruppen or e.gruppen[Gruppen.Groesse(e.gruppe)] == e.gruppe then
            return e.gruppe, e
        end
    end
    if e.gruppen then
        for _, gr in ipairs({ 40, 20, 10 }) do
            if e.gruppen[gr] and e.gruppen[gr] ~= "" then
                return e.gruppen[gr], e
            end
        end
    end
    if e.gruppe and e.gruppe ~= "" then return e.gruppe, e end
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
    local kat = Gruppen.Groesse(gruppe)
    for _, e in pairs(einteilungen()[Gruppen.IdStart(datum)] or {}) do
        local treffer = false
        if e.gruppen and e.gruppen[kat] == gruppe then
            treffer = true
        elseif e.gruppe == gruppe and (not e.gruppen or e.gruppen[kat] == gruppe) then
            treffer = true
        end
        if treffer then liste[#liste + 1] = e.name end
    end
    table.sort(liste, function(a, b) return a:lower() < b:lower() end)
    return liste
end

--- Die Spieler auf der Bench an diesem Tag (optional gefiltert nach Gruppe / Raid-Größe).
function Gruppen.BenchListe(datum, gruppe)
    local kat = gruppe and Gruppen.Groesse(gruppe)
    local liste = {}
    local gesehen = {}
    for _, e in pairs(einteilungen()[Gruppen.IdStart(datum)] or {}) do
        local istB = false
        if kat then
            local g = e.gruppen and e.gruppen[kat] or (e.gruppe and Gruppen.Groesse(e.gruppe) == kat and e.gruppe)
            if g and Gruppen.IstBench(g) then istB = true end
        else
            if e.gruppen then
                for _, g in pairs(e.gruppen) do
                    if Gruppen.IstBench(g) then istB = true break end
                end
            elseif e.gruppe and Gruppen.IstBench(e.gruppe) then
                istB = true
            end
        end
        if istB and not gesehen[e.name] then
            gesehen[e.name] = true
            liste[#liste + 1] = e.name
        end
    end
    table.sort(liste, function(a, b) return a:lower() < b:lower() end)
    return liste
end

--- Gibt es fuer diesen Tag ueberhaupt eine Einteilung (in irgendeiner Gruppe)?
function Gruppen.EinteilungVorhanden(datum)
    for _, e in pairs(einteilungen()[Gruppen.IdStart(datum)] or {}) do
        if e.gruppen then
            for _, g in pairs(e.gruppen) do
                if g and g ~= "" then return true end
            end
        elseif e.gruppe and e.gruppe ~= "" then
            return true
        end
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
    return datum >= date("%Y-%m-%d", time() - 10 * TAG) and datum <= date("%Y-%m-%d", time() + 35 * TAG)
end

local function gruppeOk(g)
    return type(g) == "string" and #g <= 40 and not g:find("[;~|%c]")
end

local function nameOk(n)
    return type(n) == "string" and #n >= 1 and #n <= 40 and not n:find("[;~|,%c]")
end

--- Traegt einen Spieler ein (der juengere Eintrag gewinnt). @return true, wenn sich etwas geaendert hat
local function einteilungEinsetzen(datum, name, gruppe, zeit, von, zielKat)
    local k = Kern.Schluessel(name)
    if not k then return false end
    datum = Gruppen.IdStart(datum)
    local T = einteilungen()
    T[datum] = T[datum] or {}
    local e = T[datum][k]
    if not e then
        e = { name = Kern.Anzeigename(name), gruppe = "", gruppen = {}, zeiten = {}, von = von }
        T[datum][k] = e
    end
    if not e.gruppen then
        e.gruppen = {}
        e.zeiten = {}
        if e.gruppe and e.gruppe ~= "" then
            local k0 = Gruppen.Groesse(e.gruppe)
            e.gruppen[k0] = e.gruppe
            e.zeiten[k0] = e.zeit or 0
        end
    end

    -- Ziel-Kategorie ermitteln
    local kat = zielKat
    if gruppe and gruppe:match("^:(%d+)$") then
        kat = tonumber(gruppe:match("^:(%d+)$"))
        gruppe = ""
    elseif gruppe and gruppe ~= "" then
        kat = kat or Gruppen.Groesse(gruppe)
    end

    if kat then
        kat = tonumber(kat)
        local altZeit = math.max((e.zeiten and e.zeiten[kat]) or 0, e.zeit or 0)
        if altZeit > zeit or (altZeit == zeit and tostring(e.von or "") >= tostring(von)) then
            return false
        end
        e.zeiten = e.zeiten or {}
        e.zeiten[kat] = zeit
        if gruppe and gruppe ~= "" then
            e.gruppen[kat] = gruppe
        else
            e.gruppen[kat] = nil
        end
    else
        -- gruppe == "" ohne Kategorie: alle Kategorien leeren
        if (e.zeit or 0) > zeit or ((e.zeit or 0) == zeit and tostring(e.von or "") >= tostring(von)) then
            return false
        end
        e.gruppen = {}
        e.zeiten = {}
    end

    e.zeit = zeit
    e.von = von
    -- Letzte oder verbleibende Gruppe pflegen
    if gruppe and gruppe ~= "" then
        e.gruppe = gruppe
    else
        e.gruppe = e.gruppen[40] or e.gruppen[20] or e.gruppen[10] or ""
    end
    return true
end

--- Eine Meldung `T;<Datum>;<Urheber>;<Name>|<Gruppe>|<Zeit>~<Name>|<Gruppe>|<Zeit>…` an die Gilde und die Gruppe.
--  @param schluessel  Liste der Spielerschluessel dieses Tages (nil = alle)
function Gruppen.EinteilungSenden(datum, schluessel, sendeKat, sendeGruppe)
    datum = Gruppen.IdStart(datum)
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
        if e and nameOk(e.name) then
            if schluessel and #schluessel == 1 and sendeKat and (sendeGruppe == "" or sendeGruppe == nil) then
                local zt = (e.zeiten and e.zeiten[sendeKat]) or e.zeit or time()
                anhaengen(string.format("%s|:%d|%d", e.name, sendeKat, zt))
            elseif e.gruppen and next(e.gruppen) then
                for gr, grp in pairs(e.gruppen) do
                    if gruppeOk(grp) then
                        local zt = (e.zeiten and e.zeiten[gr]) or e.zeit or 0
                        anhaengen(string.format("%s|%s|%d", e.name, grp, zt))
                    end
                end
            elseif gruppeOk(e.gruppe or "") then
                anhaengen(string.format("%s|%s|%d", e.name, e.gruppe or "", e.zeit or 0))
            end
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

--- ⭐ Teilt einen Spieler fuer einen Tag einer Gruppe zu (leer/nil = nicht eingeteilt).
--  Spieler können je Raid-Größe (10er, 20er, 40er) in einer Gruppe eingeteilt sein.
--  @return true, oder nil und ein Grund
function Gruppen.EinteilungSetzen(datum, name, gruppe, von, zielKat)
    von = von or ichName()
    if not Gruppen.EinteilungDarf(von) then
        return nil, L["Keine Berechtigung (nur Gildenränge mit Schreibrecht)."]
    end
    if not tagOk(datum) then return nil, L["Ungültiges Datum."] end
    if not nameOk(name) then return nil, L["Ungültiger Spielername."] end
    gruppe = gruppe or ""
    if gruppe ~= "" and not (gruppeOk(gruppe) and (Gruppen.IstBench(gruppe) or gruppe == Gruppen.KEINEMELDUNG or Gruppen.Holen(gruppe))) then
        return nil, L["Diese Gruppe gibt es nicht."]
    end

    local kat = zielKat
    if gruppe ~= "" then
        kat = kat or Gruppen.Groesse(gruppe)
    end

    local k = Kern.Schluessel(name)
    datum = Gruppen.IdStart(datum)
    local alt = einteilungen()[datum] and einteilungen()[datum][k]
    local zeit = time()
    local altZeit = (alt and alt.zeiten and kat and alt.zeiten[kat]) or (alt and alt.zeit) or 0
    if altZeit >= zeit then zeit = altZeit + 1 end     -- immer juenger als der eigene alte Eintrag
    einteilungEinsetzen(datum, name, gruppe, zeit, von, kat)
    einteilungAufraeumen()
    Gruppen.EinteilungSenden(datum, { k }, kat, gruppe)
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

    -- ⭐ Frage nach aktueller Einteilung (z. B. wenn jemand das Addon frisch öffnet)
    if rest:find("^%?") then
        if Gruppen.EinteilungDarf() then
            local datum = Gruppen.IdStart()
            if Gruppen.EinteilungVorhanden(datum) then
                Gruppen.EinteilungSenden(datum)
            end
        end
        return
    end
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
        -- ⭐ Der Raidkader wird beim Anmelden von selbst eingelesen (Rang als geteilte Einstellung, Entscheid 22.10.2026)
        C_Timer.After(25, function() pcall(Gruppen.RaidkaderAuto) end)
    end
end)

return ns
