--[[----------------------------------------------------------------------
    Raid.lua  —  Den Raidabend erfassen

    Sammelt waehrend des Abends nur mit; geschrieben wird erst am Ende
    ueber /lo abend jetzt. Das entspricht dem Rhythmus aus AGENTS.md:
    Vergaben sofort, Einsatz gesammelt.

    ⚠️ Der Abend liegt in den SavedVariables und ueberlebt /reload und
    Disconnect — aber nicht den Absturz vor dem naechsten Ausloggen,
    weil WoW SavedVariables erst dann auf die Platte schreibt.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Raid = {}
ns.Raid = Raid

local Kern = ns.Kern

-- =====================================================================
--  Abend
-- =====================================================================

local function db()
    LootOrdnungDB = LootOrdnungDB or {}
    return LootOrdnungDB
end

--- Zieht einen Abend aus einer aelteren Addon-Fassung nach.
--
--  ⭐ **SavedVariables sind eine Versionsgrenze, genau wie die Notiz.**
--  Was dort liegt, hat eine fruehere Fassung geschrieben und kennt deren
--  Felder, nicht meine. Die erste Fassung fuehrte `namen`
--  (Name -> Zahl der Bosse), die Neufassung `teilnahme`
--  (BossNr -> Menge der Namen). Der alte Abend ueberlebte den Umbau, und
--  /lo abend lief auf ein nil. In Notiz.lua lese ich drei Fassungen —
--  hier habe ich dieselbe Sorgfalt vergessen.
--
--  ⚠️ Beim Nachziehen bleibt die ANZAHL der Bosse je Spieler erhalten,
--  die Zuordnung zu einzelnen Bossen ist erfunden. Auswertung() zaehlt
--  ohnehin nur, das Ergebnis ist dasselbe — das Protokoll waere es nicht.
--
--  Ohne WoW-API, damit der Pruefstand sie testen kann.
--  @return abend, true wenn etwas nachgezogen wurde
function Raid.Nachziehen(a, jetzt)
    if type(a) ~= "table" then return a, false end
    local umgezogen = false

    if a.namen and not a.teilnahme then
        local bosse = a.bosse or 0
        a.teilnahme = {}
        for nr = 1, bosse do a.teilnahme[nr] = {} end
        for name, anzahl in pairs(a.namen) do
            local bis = anzahl or 0
            if bis > bosse then bis = bosse end
            for nr = 1, bis do a.teilnahme[nr][name] = true end
        end
        a.namen = nil
        umgezogen = true
    end

    -- Fehlendes ergaenzen statt darauf vertrauen, dass es da ist.
    a.start     = a.start     or jetzt or 0
    a.bosse     = a.bosse     or 0
    a.protokoll = a.protokoll or {}
    a.teilnahme = a.teilnahme or {}
    a.kennungen = a.kennungen or {}
    a.versuche  = a.versuche  or {}
    a.erfolg    = a.erfolg    or {}
    return a, umgezogen
end

--- Der laufende Abend, oder ein frischer.
function Raid.Abend(neu)
    local d = db()
    if neu or not d.abend then
        d.abend = {
            start     = time(),
            bosse     = 0,
            protokoll = {},   -- bossNr -> Name
            teilnahme = {},   -- bossNr -> { name -> true }
            kennungen = {},   -- encounterID -> bossNr
            versuche  = {},   -- bossNr -> Anzahl Anlaeufe
            erfolg    = {},   -- bossNr -> true, sobald gelegt
        }
        return d.abend
    end

    local abend, umgezogen = Raid.Nachziehen(d.abend, time())
    if umgezogen then
        print("|cff1B6B57Loot-Ordnung|r: |cffffff78Abend aus einer älteren Fassung übernommen.|r")
        print("  |cff8E9A94Die Bosszahl je Spieler stimmt, das Protokoll ist lückenhaft.|r")
    end
    return abend
end

function Raid.AbendVerwerfen()
    db().abend = nil
end

-- =====================================================================
--  Teilnehmer
-- =====================================================================

--- Wer ist gerade dabei?
--
--  ⭐ **Im Schlachtzug zu stehen reicht nicht.** Gefiltert wird ueber
--  Kern.IstDabei: offline faellt raus, und in einer Instanz auch, wer in
--  einer anderen Zone steht. Sonst kassiert der Twink, der in Shattrath
--  parkt, denselben Einsatz wie die Gruppe im Kampf.
--
--  Damit erledigt sich auch die Trennung zweier paralleler Gruppen von
--  selbst: Jeder Raidleiter liest nur SEINE Schlachtzugsliste, und in der
--  steht die andere Gruppe gar nicht erst.
--
--  ⚠️ **Notbremse:** Siebt der Filter ALLE aus, stimmt nicht der Raid,
--  sondern meine Annahme ueber die Felder von GetRaidRosterInfo. Dann
--  zaehlt die ungefilterte Liste. Ein Filter darf einen Abend verkleinern,
--  niemals ausloeschen.
--
--  @return Liste der Namen, Zahl der ausgesiebten, Notbremse gezogen?
function Raid.Anwesende()
    local alle, dabei = {}, {}
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0

    if IsInRaid and IsInRaid() then
        local _, typ = IsInInstance()
        local hier = (typ == "raid" or typ == "party") and GetRealZoneText() or nil
        for i = 1, n do
            local name, _, _, _, _, _, zone, online = GetRaidRosterInfo(i)
            if name then
                alle[#alle + 1] = name
                if ns.Kern.IstDabei(online, zone, hier) then
                    dabei[#dabei + 1] = name
                end
            end
        end
        if #dabei == 0 and #alle > 0 then
            return alle, 0, true
        end
        return dabei, #alle - #dabei, false
    end

    local liste = {}
    if n > 0 then
        liste[#liste + 1] = UnitName("player")
        for i = 1, n - 1 do
            local name = UnitName("party" .. i)
            if name then liste[#liste + 1] = name end
        end
    else
        liste[#liste + 1] = UnitName("player")
    end

    return liste, 0, false
end

--- Namen wie im Gildenroster schreiben (mit Realm), damit beide Seiten
--  denselben Schluessel benutzen.
local function vollerName(name)
    if name:find("%-") then return name end
    local realm = GetRealmName and GetRealmName() or ""
    realm = realm:gsub("%s+", "")
    if realm == "" then return name end
    return name .. "-" .. realm
end

-- =====================================================================
--  Wann darf automatisch gebucht werden
-- =====================================================================

local function gildenanteil()
    local anwesende = Raid.Anwesende()
    local gilde = {}
    for _, e in ipairs((ns.Gilde.Lesen())) do
        gilde[e.name] = true
    end

    local drin = 0
    for _, name in ipairs(anwesende) do
        if gilde[vollerName(name)] then drin = drin + 1 end
    end
    return drin, #anwesende
end

--- Ist das hier ein Gildenraid?
--  Zwei Bedingungen, damit weder beim Questen noch im Pug gebucht wird:
--  eine Raidinstanz UND mehr als die Haelfte der Gruppe aus der Gilde.
function Raid.IstGildenraid()
    local _, typ = IsInInstance()
    if typ ~= "raid" then return false, "keine Raidinstanz" end
    if not (IsInRaid and IsInRaid()) then return false, "keine Schlachtzugsgruppe" end

    local drin, gesamt = gildenanteil()
    if gesamt == 0 then return false, "keine Gruppe" end
    if drin * 2 <= gesamt then
        return false, string.format("nur %d von %d aus der Gilde", drin, gesamt)
    end
    return true, drin, gesamt
end

-- =====================================================================
--  Bosskaempfe
-- =====================================================================

--- Bucht einen Bosskampf.
--
--  Paragraf 2: "Je Bosskampf, an dem du teilnimmst — auch bei Wipes."
--  Jeder gepullte Boss zaehlt also, ob er faellt oder nicht.
--
--  ⚠️ Drei Dinge, die leicht durcheinandergehen:
--  1. **Pro Boss, nicht pro Versuch.** Zehn Anlaeufe an einem
--     Progress-Boss zaehlen einmal — sonst braechte ein Wipe-Abend mehr
--     als eine ganze Farmwoche. Steht so noch nicht im Regelwerk.
--  2. **Teilnehmer ueber ALLE Anlaeufe vereinigt.** Wer erst nach dem
--     zweiten Wipe nachrueckt und den Kill mitmacht, bekommt den Boss
--     angerechnet; sonst entschiede allein der erste Pull.
--  3. **Einmal gelegt bleibt gelegt** — ein spaeterer Anlauf macht aus
--     einem Kill keinen Wipe. Der Erfolg dient nur der Anzeige, auf den
--     Einsatz wirkt er nicht.
--
--  @param bezeichnung  Name des Bosses, nur fuers Protokoll
--  @param kennung      encounterID; ohne sie zaehlt jeder Aufruf neu
--  @param erfolg       true, wenn der Boss gefallen ist
--  @return true, Zahl (Teilnehmer bzw. neu hinzugekommene), bossNr, schonDa
--- Sucht einen schon gebuchten Boss anhand des Namens.
--  Noetig fuer /lo boss von Hand: Ohne encounterID zaehlte sonst jeder
--  Aufruf als neuer Boss, und ein automatisch erfasster Kampf waere beim
--  Nachbuchen doppelt gelandet.
function Raid.BossNachName(bezeichnung)
    if not bezeichnung or bezeichnung == "" then return nil end
    local abend = Raid.Abend()
    local suche = bezeichnung:lower()
    for nr = 1, abend.bosse do
        local vorhanden = (abend.protokoll[nr] or ""):lower()
        if vorhanden ~= "" then
            if vorhanden == suche
               or vorhanden:find(suche, 1, true)
               or suche:find(vorhanden, 1, true) then
                return nr
            end
        end
    end
end

function Raid.BossBuchen(bezeichnung, kennung, erfolg)
    local abend = Raid.Abend()
    local nr = kennung and abend.kennungen[kennung]
    -- Ohne Kennung ueber den Namen suchen, damit /lo boss nicht doppelt zaehlt
    if not nr then nr = Raid.BossNachName(bezeichnung) end
    local schonDa = nr ~= nil

    if not nr then
        abend.bosse = abend.bosse + 1
        nr = abend.bosse
        abend.protokoll[nr] = bezeichnung or ("Boss " .. nr)
        abend.teilnahme[nr] = {}
        abend.versuche[nr]  = 0
        if kennung then abend.kennungen[kennung] = nr end
    end

    abend.versuche[nr] = (abend.versuche[nr] or 0) + 1
    if erfolg then abend.erfolg[nr] = true end

    local menge = abend.teilnahme[nr]
    local anwesende, aussen, notbremse = Raid.Anwesende()
    local neu = 0
    for _, name in ipairs(anwesende) do
        local schluessel = vollerName(name)
        if not menge[schluessel] then
            menge[schluessel] = true
            neu = neu + 1
        end
    end

    return true, (schonDa and neu or #anwesende), nr, schonDa, aussen, notbremse
end

--- Wie viele Bosse fielen, wie viele stehen noch.
function Raid.Bilanz()
    local abend = Raid.Abend()
    local gelegt, offen = 0, 0
    for nr = 1, abend.bosse do
        if abend.erfolg[nr] then gelegt = gelegt + 1 else offen = offen + 1 end
    end
    return gelegt, offen
end

--- Einheitliche Meldung fuer gebuchte Kaempfe.
function Raid.Melden(ok, zahl, nr, schonDa, aussen, notbremse)
    if not ok or not nr then return end
    local abend = Raid.Abend()
    local name     = tostring(abend.protokoll[nr])
    local stand    = abend.erfolg[nr] and "|cff55ff55gelegt|r" or "|cffffff78steht noch|r"
    local anlaeufe = abend.versuche[nr] or 1

    if schonDa then
        local zusatz = (zahl > 0) and string.format(", %d neue Teilnehmer", zahl) or ""
        print(string.format("|cff1B6B57Loot-Ordnung|r: %s, %d. Anlauf – %s|cff8E9A94%s. Zählt nicht doppelt.|r",
            name, anlaeufe, stand, zusatz))
    else
        print(string.format("|cff1B6B57Loot-Ordnung|r: %s gebucht – %s |cff8E9A94(%d Teilnehmer, Boss %d).|r",
            name, stand, zahl, nr))
    end
    if aussen and aussen > 0 then
        print(string.format("  |cff8E9A94%d nicht mitgezählt – offline oder in einer anderen Zone.|r",
            aussen))
    end
    if notbremse then
        print("  |cffff5555Zonenfilter aus – er hätte den ganzen Raid ausgesiebt. /lo wer zeigt warum.|r")
    end
end

-- =====================================================================
--  Auswertung
-- =====================================================================

--- Was der Abend jedem einbringt.
function Raid.Auswertung()
    local abend = Raid.Abend()
    local liste, zaehler = {}, {}

    for nr = 1, abend.bosse do
        for name in pairs(abend.teilnahme[nr] or {}) do
            zaehler[name] = (zaehler[name] or 0) + 1
        end
    end

    for name, anzahl in pairs(zaehler) do
        local vollDabei = (anzahl >= abend.bosse and abend.bosse > 0)
        liste[#liste + 1] = {
            name      = name,
            kurz      = name:match("^([^%-]+)") or name,
            bosse     = anzahl,
            vollDabei = vollDabei,
            einsatz   = Kern.EinsatzFuerTeilnahme(anzahl, vollDabei),
        }
    end

    table.sort(liste, function(a, b)
        if a.bosse ~= b.bosse then return a.bosse > b.bosse end
        return a.kurz < b.kurz
    end)
    return liste
end

--- Schreibt den Abend in die Konten.
--
--  ⭐ **Idempotent gegen mehrere Raidleiter.** Haben zwei oder drei Leute
--  das Addon, feuert ENCOUNTER_END bei allen, und jeder fuehrt seinen
--  eigenen Abend — das ist harmlos. Buchen aber alle, addiert jeder auf
--  das Ergebnis des Vorherigen, und der Einsatz verdoppelt sich. Deshalb
--  traegt jedes Konto die Stunde seiner letzten Buchung.
--
--  ⚠️ **Bei zwei parallelen Gruppen ist die Sperre zu grob.** Sie sieht
--  nur, DASS heute gebucht wurde, nicht von wem. Wer erst im Zehner und
--  danach im Zwanziger mitgeht, wird beim zweiten Mal faelschlich
--  uebersprungen. Eine Gruppenkennung waere die naheliegende Loesung —
--  aber jede (Anfuehrer, Teilnehmerpruefsumme, Instanz) hat eine Luecke,
--  und ihr Fehlerfall ist die STILLE Doppelbuchung. Die Zeitsperre irrt in
--  die harmlose Richtung: Sie meldet die Uebersprungenen namentlich, und
--  die Leitung traegt sie mit /lo abend nachtragen nach. Falsch gesperrt
--  faellt auf, falsch gebucht nicht.
--
--  ⚠️ Nur Teilnehmer, nicht die ganze Gilde: Wer nicht dabei war,
--  aendert sich allein durch Verfall, und der wird beim naechsten Lesen
--  ueber den Wochenstempel nachgeholt.
--
--  @param modus  nil = normal · "zwingend" = Sperre ganz aus ·
--                "nachtragen" = NUR die zuletzt Uebersprungenen
--  @return Anzahl gebuchter, Liste ohne Konto, Liste der Uebersprungenen
function Raid.Buchen(beiFertig, modus)
    local jetzt  = time()
    local woche  = Kern.WocheAus(jetzt)
    local stunde = Kern.StundeAus(jetzt)
    local abend  = Raid.Abend()
    local auswertung = Raid.Auswertung()

    local nachtragen = (modus == "nachtragen") and (abend.uebersprungen or {}) or nil
    local erzwingen  = (modus == "zwingend")

    local nachName = {}
    for _, e in ipairs((ns.Gilde.Lesen())) do
        nachName[e.name] = e
    end

    local auftraege, fehlend, spaeter = {}, {}, {}
    for _, a in ipairs(auswertung) do
        local e = nachName[a.name]

        local dran
        if nachtragen then
            dran = nachtragen[a.name] and true or false
        elseif erzwingen then
            dran = true
        else
            dran = not Kern.SchonGebucht(e and e.konto, stunde)
        end

        if not (e and e.konto) then
            fehlend[#fehlend + 1] = a.kurz
        elseif not dran then
            -- Beim Nachtragen ist "nicht dran" kein Ueberspringen, sondern
            -- der Normalfall: die wurden eben gerade gebucht.
            if not nachtragen then spaeter[a.name] = a.kurz end
        else
            Kern.VerfallNachholen(e.konto, woche)
            Kern.TeilnahmeBuchen(e.konto, a.bosse, a.vollDabei)
            e.konto.gebucht = stunde
            auftraege[#auftraege + 1] = { guid = e.guid, konto = e.konto }
        end
    end

    local liste = {}
    for _, kurz in pairs(spaeter) do liste[#liste + 1] = kurz end
    table.sort(liste)

    -- Fuer /lo abend nachtragen merken. Der Abend darf dafuer nicht
    -- verworfen werden — darum kuemmert sich Befehle.lua.
    abend.uebersprungen = (not nachtragen) and next(spaeter) and spaeter or nil

    local n = ns.Gilde.SchreibenViele(auftraege, beiFertig)
    return n, fehlend, liste
end

--- Tragen noch Konten einen Nachtrag offen?
function Raid.OffeneNachtraege()
    local u = Raid.Abend().uebersprungen
    return u and next(u) ~= nil
end

-- =====================================================================
--  Automatik
-- =====================================================================

local rahmen = CreateFrame("Frame")

-- Nicht jeder Client kennt beide Ereignisse; die Registrierung darf
-- deshalb nicht hart scheitern.
pcall(function() rahmen:RegisterEvent("ENCOUNTER_END") end)
pcall(function() rahmen:RegisterEvent("BOSS_KILL") end)

rahmen:SetScript("OnEvent", function(_, ereignis, a1, a2, a3, a4, a5)
    if not (db().automatik) then return end

    local erlaubt, grund = Raid.IstGildenraid()
    if not erlaubt then
        print(string.format("|cff1B6B57Loot-Ordnung|r: |cff8E9A94nicht gebucht (%s). Von Hand: /lo boss|r",
            tostring(grund)))
        return
    end

    if ereignis == "ENCOUNTER_END" then
        -- a1 encounterID, a2 Name, a3 Schwierigkeit, a4 Gruppe, a5 Erfolg
        Raid.Melden(Raid.BossBuchen(a2, a1, a5 == 1 or a5 == true))
    elseif ereignis == "BOSS_KILL" then
        Raid.Melden(Raid.BossBuchen(a2, a1, true))
    end
end)

function Raid.AutomatikUmschalten()
    local d = db()
    d.automatik = not d.automatik
    return d.automatik
end

function Raid.AutomatikAn()
    return db().automatik and true or false
end
