--[[----------------------------------------------------------------------
    Anwesenheit.lua  —  Raidabend-Erkennung und Anwesenheitstracking

    Erfasst Bosskämpfe und die Anwesenheit der Spieler (§ 2, § 4, § 6):
      * Automatische Momentaufnahme nach jedem Bosskampf (Aufzeichner)
      * Schutz vor Doppelzählung bei Wipes und Wiederholungen
      * Erkennung von Kader, Gast und Proberaid (§ 4)
      * Erfüllung der Anwesenheitsquote (≥ 50 % = im Raid, kein Zuschlag)
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Anwesenheit = {}
ns.Anwesenheit = Anwesenheit

local Kern = ns.Kern

-- =====================================================================
--  Datenbank
-- =====================================================================

local dbOverride = nil

local function db()
    if dbOverride then
        dbOverride.abende = dbOverride.abende or {}
        dbOverride.zuschlaege = dbOverride.zuschlaege or {}
        dbOverride.anhebungen = dbOverride.anhebungen or {}
        dbOverride.anhebungsliste = dbOverride.anhebungsliste or {}
        return dbOverride
    end
    FairshareDB = FairshareDB or {}
    FairshareDB.abende = FairshareDB.abende or {}
    FairshareDB.zuschlaege = FairshareDB.zuschlaege or {}
    FairshareDB.anhebungen = FairshareDB.anhebungen or {}
    -- Anhebungen als einzelne Saetze (seit dem Datenbuch): lassen sich zwischen
    -- Spielern verteilen. `anhebungen` (Summe je Spieler) bleibt fuer aeltere Staende.
    FairshareDB.anhebungsliste = FairshareDB.anhebungsliste or {}
    return FairshareDB
end

--- Die Daten, die verteilt werden (Abende, Zuschlaege, Anhebungen).
function Anwesenheit.Daten()
    return db()
end

function Anwesenheit._SetDB(mockDB)
    dbOverride = mockDB
end

--- ⭐ Die Kennung einer Gruppe fuer Abendkennungen und Datenbuch: nur `[%w_.-]`, hoechstens 24 Zeichen.
--  @return Text, oder nil ohne Gruppe
function Anwesenheit.GruppenKennung(gruppe)
    if type(gruppe) ~= "string" or gruppe == "" then return nil end
    local s = gruppe:gsub("[^%w_%.%-]", "-")
    s = s:gsub("%-+", "-")
    s = s:gsub("^%-", "")
    s = s:gsub("%-$", "")
    if s == "" then s = "g" end
    return s:sub(1, 24)
end

--- ⭐ Die Kennung eines Abends: Datum und Gruppe (zwei Gruppen am selben Tag ueberschreiben sich nicht).
--  Ohne Gruppe nur das Datum, wie bisher.
function Anwesenheit.AbendId(datum, gruppe)
    local g = Anwesenheit.GruppenKennung(gruppe)
    return g and (tostring(datum) .. "_" .. g) or tostring(datum)
end

--- ⭐ Die Gruppenkennung eines Abends: aus seinem Feld `gruppe`, sonst aus der Kennung (`Datum_Gruppe`; so sehen
--  Abende aus, die per Datenbuch von anderen kamen). nil = Abend ohne Gruppe.
local function abendGruppenKennung(ab)
    if ab.gruppe and ab.gruppe ~= "" then return Anwesenheit.GruppenKennung(ab.gruppe) end
    return tostring(ab.id or ""):match("^%d%d%d%d%-%d%d%-%d%d_(.+)$")
end

--- Liefert den aktiven Raidabend oder erstellt einen frischen.
--  Alte Abende (älter als 14 Stunden oder von einem anderen Kalendertag)
--  werden automatisch in die Historie (FairshareDB.abende) archiviert.
function Anwesenheit.AktiverAbend(erstellen)
    local d = db()
    local jetzt = time()
    local heute = date("%Y-%m-%d", jetzt)

    local akt = d.aktiverAbend
    local aktiveGruppe = ns.Gruppen and ns.Gruppen.AktivName and ns.Gruppen.AktivName() or nil
    if akt then
        -- ⭐ Ein Gruppenwechsel ist ein ANDERER Abend (Entscheid 17.10.2026: mehrere Gruppen). Der alte wird
        -- archiviert, wenn er schon Bosskaempfe hatte, sonst verworfen. Ein abgeschlossener Abend bleibt
        -- unberuehrt stehen (er gehoert zu seiner Gruppe).
        local gruppeAnders = (not akt.abgeschlossen) and (akt.gruppe or "") ~= (aktiveGruppe or "")
        local alt = (akt.start and (jetzt - akt.start > 14 * 3600))
                 or (akt.datum and akt.datum ~= heute)
                 or gruppeAnders
        if alt then
            if (akt.bosse or 0) > 0 then
                local id = akt.id or (akt.datum or heute)
                d.abende[id] = akt
            end
            d.aktiverAbend = nil
            akt = nil
        else
            akt.bank = akt.bank or {}
            akt.unentschuldigt = akt.unentschuldigt or {}
            akt.abgemeldet = akt.abgemeldet or {}
            akt.vergessen = akt.vergessen or {}
            akt.protokoll = akt.protokoll or {}
        end
    end

    if not akt and erstellen then
        akt = {
            id          = Anwesenheit.AbendId(heute, aktiveGruppe),
            datum       = heute,
            start       = jetzt,
            bosse       = 0,
            gesehen     = {},    -- encounterID -> true
            bossListe   = {},    -- { id, name, zeit, anwesende = { ... } }
            anwesenheit = {},    -- schluessel -> anzahlBosse
            teilnehmer  = {},    -- schluessel -> { name = vollerName, bosse = n, status = "kader"|"gast"|"proberaid" }
            bank        = {},    -- schluessel -> { name = vollerName, von = autorName, zeit = timestamp }
            unentschuldigt = {}, -- schluessel -> { name = vollerName, von = autorName, zeit = timestamp }
            vergessen   = {},    -- Keine Meldung (weder an- noch abgemeldet, nicht erschienen)
            abgemeldet  = {},    -- ausdruecklich abgemeldet (vom Leiter eingetragen)
            protokoll   = {},    -- { { typ = "bank"|"unentschuldigt", an = bool, spieler = name, von = autor, zeit = timestamp } }
            gruppe      = aktiveGruppe,
        }
        d.aktiverAbend = akt
    end

    return akt
end

--- Setzt den aktuellen Abend zurück.
function Anwesenheit.AbendZuruecksetzen()
    local d = db()
    d.aktiverAbend = nil
end

-- =====================================================================
--  Teilnehmer-Erkennung
-- =====================================================================

local anwesendeOverride = nil

function Anwesenheit._SetAnwesende(mockListe)
    anwesendeOverride = mockListe
end

--- Liest die Namen aller aktuell anwesenden Spieler in der Gruppe/Raid.
local function anwesendeNamen()
    if anwesendeOverride then return anwesendeOverride end
    local liste = {}
    local einheiten = ns.Rolle and ns.Rolle.Einheiten and ns.Rolle.Einheiten() or {}
    for _, e in ipairs(einheiten) do
        local n
        if GetUnitName then n = GetUnitName(e.unit, true) end
        if not n or n == "" then n = UnitName(e.unit) end
        if n and n ~= "" and n ~= "Unknown" then
            liste[#liste + 1] = n
        end
    end
    if #liste == 0 and UnitName then
        local me = (GetUnitName and GetUnitName("player", true)) or UnitName("player")
        if me then liste[1] = me end
    end
    return liste
end

Anwesenheit.AnwesendeNamen = anwesendeNamen

--- Die Spieler im Abschluss des ersten abgeschlossenen Abends (Schluessel -> Eintrag),
--  oder nil, solange noch kein Abend abgeschlossen ist. Das ist der Kader der Gruendungszeit.
function Anwesenheit.Gruender()
    local erster, erstZeit
    for _, ab in pairs(db().abende or {}) do
        if ab.abgeschlossen and ab.abschluss and ab.abschluss.spieler then
            local z = ab.abschluss.zeit or ab.start or 0
            if not erstZeit or z < erstZeit then erster, erstZeit = ab, z end
        end
    end
    return erster and erster.abschluss.spieler or nil
end

--- Prüft den Status eines Spielers (§ 4):
--  @return "kader", "gast", "proberaid" (1. Abend) oder "neuling" (2. Abend)
function Anwesenheit.StatusVon(name)
    if not name then return "gast" end

    -- 1. Gehört der Spieler zum Kader?
    local inKader = false
    if ns.Gruppen then
        local aktGruppe = ns.Gruppen.AktivName and ns.Gruppen.AktivName()
        local pflicht = ns.Gruppen.Pflicht and ns.Gruppen.Pflicht(aktGruppe)
        for _, n in ipairs(pflicht or {}) do
            if Kern.GleicherSpieler(n, name) then
                inKader = true
                break
            end
        end

        if not inKader and ns.Gruppen.GildenMitglieder then
            local gm = ns.Gruppen.GildenMitglieder()
            local k = Kern.Schluessel(name)
            if gm and (gm[name] or (k and gm[k])) then
                inKader = true
            end
        end
    end

    if not inKader then
        return "gast"
    end

    -- ⭐ Die Gruender des Systems sind keine Neulinge: Am ersten Abend mit der neuen Regel hat noch
    -- niemand eine Vorgeschichte — wuerde man danach gehen, waere der ganze Kader im Proberaid und
    -- niemand duerfte wuerfeln (so im Spiel aufgefallen, 17.10.2026). Darum gilt:
    --   * Solange noch kein Abend abgeschlossen ist: alle im Kader sind Kaderspieler.
    --   * Wer im Abschluss des ERSTEN abgeschlossenen Abends stand (der Kader zu dem Zeitpunkt, auch
    --     die, die gefehlt haben), ist Kaderspieler. Proberaid und Neuling gibt es nur fuer die, die
    --     spaeter zum Kader dazukamen.
    local gruender = Anwesenheit.Gruender()
    if gruender == nil then return "kader" end
    local gk = Kern.Schluessel(name)
    if gk and gruender[gk] then return "kader" end

    -- 2. Wenn Kader: Ist es das Proberaid (§ 4)?
    --    Erster Raidabend im Kader = Proberaid (kein Würfeln auf Main, kein Zuschlag).
    local d = db()
    local fruehereAbende = 0
    if d.abende then
        local k = Kern.Schluessel(name)
        for _, alt in pairs(d.abende) do
            local sp = k and alt.abschluss and alt.abschluss.spieler and alt.abschluss.spieler[k]
            if k and ((alt.anwesenheit and (alt.anwesenheit[k] or 0) > 0) or (sp and sp.status == "imRaid")) then
                fruehereAbende = fruehereAbende + 1
            end
        end
    end

    local fruehereItems = 0
    local hist = ns.Erfassung and ns.Erfassung.Historie and ns.Erfassung.Historie()
    if hist then
        local k = Kern.Schluessel(name)
        for _, e in pairs(hist) do
            if Kern.Zaehlt(e) and Kern.Schluessel(e.awardedTo) == k then
                fruehereItems = fruehereItems + 1
            end
        end
    end

    if fruehereAbende == 0 and fruehereItems == 0 then
        return "proberaid"
    end

    -- ⭐ 2. Raidabend eines neuen Kaderspielers (§ 4): Er kommt auf die Wertung des
    -- Niedrigsten, damit er gute Chancen hat, ohne die anderen zu benachteiligen.
    if fruehereAbende == 1 and fruehereItems == 0 then
        return "neuling"
    end

    return "kader"
end

-- =====================================================================
--  Bosskampf buchen
-- =====================================================================

--- Bucht einen erfolgreichen Bosskampf für alle anwesenden Spieler.
--  @param encounterName    Name des Bosses
--  @param encounterID      Eindeutige ID (Schutz vor Wipes / Doppelzählung)
--  @param erfolg           true / 1 = Kill, false / 0 = Wipe
--  @param anwesendeManuell Optional: Vorgabe von Spielernamen (für Tests/Befehle)
--  @return ok, anzahlTeilnehmer, bossName (oder nil und Fehlergrund)
function Anwesenheit.BossBuchen(encounterName, encounterID, erfolg, anwesendeManuell)
    if erfolg == false or erfolg == 0 then
        return nil, L["Kein erfolgreicher Kill (Wipe)"]
    end

    local abend = Anwesenheit.AktiverAbend(true)

    -- Schutz vor Doppelzählung desselben Encounters am selben Abend
    if encounterID and abend.gesehen[encounterID] then
        return nil, L["Bosskampf wurde an diesem Abend bereits gebucht"]
    end
    if encounterID then abend.gesehen[encounterID] = true end

    local anwesende = anwesendeManuell or anwesendeNamen()
    if #anwesende == 0 then
        return nil, L["Keine Spieler in der Gruppe"]
    end

    abend.bosse = abend.bosse + 1
    local bName = encounterName or string.format(L["Boss %d"], abend.bosse)

    local eintrag = {
        id        = encounterID,
        name      = bName,
        zeit      = time(),
        anwesende = anwesende,
    }
    abend.bossListe[#abend.bossListe + 1] = eintrag

    for _, name in ipairs(anwesende) do
        local k = Kern.Schluessel(name)
        if k then
            abend.anwesenheit[k] = (abend.anwesenheit[k] or 0) + 1
            local status = Anwesenheit.StatusVon(name)
            abend.teilnehmer[k] = {
                name   = Kern.Anzeigename(name),
                bosse  = abend.anwesenheit[k],
                status = status,
            }
        end
    end

    -- ⭐ Anhebung (§ 3): zu Beginn des Abends, einmal, fuer alle Kaderspieler im Raid
    if abend.bosse == 1 and Anwesenheit.AnhebungenAuswerten then
        pcall(Anwesenheit.AnhebungenAuswerten, anwesende)
    end

    return true, #anwesende, bName
end

-- =====================================================================
--  Auswertung & Spielerinfo
-- =====================================================================

--- Ermittelt Anwesenheitsdaten für einen Spieler (§ 2: ≥ 50 % = im Raid).
--  @param name   Spielername
--  @param abend  Optional: bestimmter Abend (Standard: aktiver Abend)
--  @return Tabelle { bosse, gesamt, quote, prozent, imRaid, status }
function Anwesenheit.SpielerInfo(name, abend)
    abend = abend or Anwesenheit.AktiverAbend(false)
    local status = Anwesenheit.StatusVon(name)

    if not abend or (abend.bosse or 0) == 0 then
        return {
            bosse   = 0,
            gesamt  = 0,
            quote   = 0,
            prozent = 0,
            imRaid  = false,
            status  = status,
        }
    end

    local k = Kern.Schluessel(name)
    local bosse = (k and abend.anwesenheit and abend.anwesenheit[k]) or 0
    local gesamt = abend.bosse or 0
    local quote = (gesamt > 0) and (bosse / gesamt) or 0
    local imRaid = (gesamt > 0) and (bosse >= math.ceil(gesamt / 2))

    local gespeicherterStatus = k and abend.teilnehmer and abend.teilnehmer[k] and abend.teilnehmer[k].status
    if gespeicherterStatus then status = gespeicherterStatus end

    local bEintrag = k and abend and abend.bank and abend.bank[k]
    local uEintrag = k and abend and abend.unentschuldigt and abend.unentschuldigt[k]

    return {
        bosse          = bosse,
        gesamt         = gesamt,
        quote          = quote,
        prozent        = math.floor(quote * 100 + 0.5),
        imRaid         = imRaid,
        status         = status,
        bank           = bEintrag ~= nil,
        bankEintrag    = bEintrag,
        unentschuldigt = uEintrag ~= nil,
        unentEintrag   = uEintrag,
    }
end

--- Liefert eine sortierte Teilnehmerliste des Abends.
function Anwesenheit.Uebersicht(abend)
    abend = abend or Anwesenheit.AktiverAbend(false)
    if not abend then return {} end

    local liste = {}
    local gesamt = abend.bosse or 0

    for k, t in pairs(abend.teilnehmer or {}) do
        local bosse = t.bosse or 0
        local quote = (gesamt > 0) and (bosse / gesamt) or 0
        liste[#liste + 1] = {
            name    = t.name or k,
            bosse   = bosse,
            gesamt  = gesamt,
            quote   = quote,
            prozent = math.floor(quote * 100 + 0.5),
            imRaid  = (gesamt > 0) and (bosse >= math.ceil(gesamt / 2)),
            status  = t.status or "kader",
        }
    end

    local rang = { kader = 3, neuling = 3, proberaid = 2, gast = 1 }
    table.sort(liste, function(a, b)
        local ra, rb = rang[a.status] or 0, rang[b.status] or 0
        if ra ~= rb then return ra > rb end
        if a.bosse ~= b.bosse then return a.bosse > b.bosse end
        return a.name < b.name
    end)

    return liste
end

-- =====================================================================
--  Bank und Unentschuldigt (§ 2, § 6)
-- =====================================================================

local function ichName()
    if GetUnitName then
        local n = GetUnitName("player", true)
        if n and n ~= "" then return n end
    end
    return (UnitName and UnitName("player")) or "Spieler"
end

--- Prüft, ob dieser Spieler die Bank verwalten darf (Raidleiter oder Gildenleitung, § 6).
function Anwesenheit.DarfBankVerwalten(spieler)
    local name = spieler or ichName()
    if ns.Konfig and ns.Konfig.Darf and ns.Konfig.Darf(name) then return true end
    if ns.Rolle and ns.Rolle.Berechtigt and ns.Rolle.Berechtigt(name) then return true end
    if not spieler and UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
    return false
end

--- Prüft, ob dieser Spieler unentschuldigtes Fehlen verwalten darf (nur Gildenleitung, § 6).
function Anwesenheit.DarfUnentschuldigtVerwalten(spieler)
    local name = spieler or ichName()
    if ns.Konfig and ns.Konfig.Darf and ns.Konfig.Darf(name) then return true end
    return false
end

--- ⭐ Die Spieler, die an diesem Abend erwartet werden: die **Einteilung** dieser Gruppe an diesem Tag, wenn es fuer
--  den Tag eine gibt (Entscheid 17.10.2026: mehrere Gruppen, Spieler der anderen Gruppe sind nie „abwesend“);
--  sonst wie bisher der Kader der Gruppe.
--  @return Liste der Namen, nurEinteilung (true: der Gilden-Rueckfall darf nicht greifen), Bench-Namen
--          (die Bench des Tages steht in der Abwesenheit jeder Gruppe, mit Bank-Faktor 0)
local function erwarteteNamen(abend)
    local datum = (abend and abend.datum) or date("%Y-%m-%d", time())
    local gruppe = (abend and abend.gruppe) or (ns.Gruppen and ns.Gruppen.AktivName and ns.Gruppen.AktivName()) or nil
    if ns.Gruppen and ns.Gruppen.EinteilungVorhanden and ns.Gruppen.EinteilungVorhanden(datum) then
        local bench = ns.Gruppen.BenchListe(datum)
        -- Gibt es für den Tag eine Einteilung, aber keine Gruppe ist gewählt: niemand wird erwartet
        -- (nie die ganze Gilde; Fund im Spiel 18.10.2026: alle 32 standen in der Liste)
        if not gruppe then return {}, true, bench end
        return ns.Gruppen.EinteilungListe(datum, gruppe), true, bench
    end
    if ns.Gruppen and ns.Gruppen.Pflicht then return ns.Gruppen.Pflicht(gruppe) or {}, false, {} end
    return {}, false, {}
end

Anwesenheit.ErwarteteNamen = erwarteteNamen

--- ⭐ Ein Spieler von der Bench springt ein: Er kommt in die aktive Gruppe (Einteilung von heute) und wird damit
--  erwartet; erscheint er nicht im Raid, ist er offen und muss eingetragen werden.
--  @return true, oder nil und ein Grund
function Anwesenheit.BenchEinspringen(spielerName, vonName)
    local gruppe = ns.Gruppen and ns.Gruppen.AktivName and ns.Gruppen.AktivName()
    if not gruppe then return nil, L["Keine Gruppe aktiv."] end
    local abend = Anwesenheit.AktiverAbend(false)
    local datum = (abend and abend.datum) or date("%Y-%m-%d", time())
    return ns.Gruppen.EinteilungSetzen(datum, spielerName, gruppe, vonName)
end

--- Setzt oder hebt den Bank-Status für einen Spieler auf (§ 2: Faktor 0).
function Anwesenheit.BankSetzen(spielerName, an, vonName)
    local autor = vonName or ichName()
    if not Anwesenheit.DarfBankVerwalten(autor) then
        return nil, L["Keine Berechtigung (nur Raidleiter oder Gildenleitung)."]
    end
    if not spielerName or spielerName == "" then
        return nil, L["Kein Spielername angegeben."]
    end

    local k = Kern.Schluessel(spielerName)
    if not k then return nil, L["Ungültiger Spielername."] end

    local abend = Anwesenheit.AktiverAbend(true)
    abend.bank = abend.bank or {}
    abend.unentschuldigt = abend.unentschuldigt or {}
    abend.protokoll = abend.protokoll or {}

    local anzeigename = Kern.Anzeigename(spielerName)
    local jetzt = time()

    if an then
        if abend.unentschuldigt[k] then
            abend.unentschuldigt[k] = nil
        end
        abend.bank[k] = { name = anzeigename, von = autor, zeit = jetzt }
        if abend.vergessen then abend.vergessen[k] = nil end
        if abend.abgemeldet then abend.abgemeldet[k] = nil end
        abend.protokoll[#abend.protokoll + 1] = {
            typ     = "bank",
            an      = true,
            spieler = anzeigename,
            von     = autor,
            zeit    = jetzt,
        }
    else
        abend.bank[k] = nil
        abend.protokoll[#abend.protokoll + 1] = {
            typ     = "bank",
            an      = false,
            spieler = anzeigename,
            von     = autor,
            zeit    = jetzt,
        }
    end

    return true
end

--- Setzt oder hebt den unentschuldigten Status für einen Spieler auf (§ 2: sofort Faktor 1,5, mindestens 2 Punkte).
function Anwesenheit.UnentschuldigtSetzen(spielerName, an, vonName)
    local autor = vonName or ichName()
    if not Anwesenheit.DarfUnentschuldigtVerwalten(autor) then
        return nil, L["Keine Berechtigung (nur Gildenleitung)."]
    end
    if not spielerName or spielerName == "" then
        return nil, L["Kein Spielername angegeben."]
    end

    local k = Kern.Schluessel(spielerName)
    if not k then return nil, L["Ungültiger Spielername."] end

    local abend = Anwesenheit.AktiverAbend(true)
    abend.bank = abend.bank or {}
    abend.unentschuldigt = abend.unentschuldigt or {}
    abend.protokoll = abend.protokoll or {}

    local anzeigename = Kern.Anzeigename(spielerName)
    local jetzt = time()

    if an then
        if abend.bank[k] then
            abend.bank[k] = nil
        end
        abend.unentschuldigt[k] = { name = anzeigename, von = autor, zeit = jetzt }
        if abend.vergessen then abend.vergessen[k] = nil end
        if abend.abgemeldet then abend.abgemeldet[k] = nil end
        abend.protokoll[#abend.protokoll + 1] = {
            typ     = "unentschuldigt",
            an      = true,
            spieler = anzeigename,
            von     = autor,
            zeit    = jetzt,
        }
    else
        abend.unentschuldigt[k] = nil
        abend.protokoll[#abend.protokoll + 1] = {
            typ     = "unentschuldigt",
            an      = false,
            spieler = anzeigename,
            von     = autor,
            zeit    = jetzt,
        }
    end

    return true
end

--- ⭐ Setzt oder hebt „Anmeldung vergessen" auf (nur Gildenleitung): Der Spieler war weder
--  an- noch abgemeldet und ist nicht erschienen. Beim 1. und 2. Mal innerhalb von
--  `Kern.VERGESSEN_FENSTER` Raidabenden gilt der Abend wie eine normale Abmeldung, ab dem 3. Mal
--  wie unentschuldigt (Faktor 1,5, mindestens 2 Punkte). Rücknahme wie bei „unentschuldigt".
function Anwesenheit.VergessenSetzen(spielerName, an, vonName)
    local autor = vonName or ichName()
    if autor ~= "System" and not Anwesenheit.DarfUnentschuldigtVerwalten(autor) then
        return nil, L["Keine Berechtigung (nur Gildenleitung)."]
    end
    if not spielerName or spielerName == "" then
        return nil, L["Kein Spielername angegeben."]
    end

    local k = Kern.Schluessel(spielerName)
    if not k then return nil, L["Ungültiger Spielername."] end

    local abend = Anwesenheit.AktiverAbend(true)
    abend.bank = abend.bank or {}
    abend.unentschuldigt = abend.unentschuldigt or {}
    abend.vergessen = abend.vergessen or {}
    abend.protokoll = abend.protokoll or {}

    local anzeigename = Kern.Anzeigename(spielerName)
    local jetzt = time()

    if an then
        abend.bank[k] = nil
        abend.unentschuldigt[k] = nil
        if abend.abgemeldet then abend.abgemeldet[k] = nil end
        abend.vergessen[k] = { name = anzeigename, von = autor, zeit = jetzt }
    else
        abend.vergessen[k] = nil
    end
    abend.protokoll[#abend.protokoll + 1] = {
        typ = "vergessen", an = an and true or false, spieler = anzeigename, von = autor, zeit = jetzt,
    }
    return true
end

--- ⭐ Trägt eine ausdrückliche **Abmeldung** ein oder hebt sie auf (Raidleiter oder Gildenleitung).
--  Abgemeldet heißt: Der Spieler hat sich vorher abgemeldet. Das ist etwas anderes als „Keine Meldung“
--  (weder an- noch abgemeldet) und als „Unentschuldigt“. Wer nicht im Raid steht und nichts davon
--  eingetragen hat, ist **offen** und verhindert den Abschluss des Abends.
function Anwesenheit.AbmeldungSetzen(spielerName, an, vonName)
    local autor = vonName or ichName()
    if autor ~= "System" and not Anwesenheit.DarfBankVerwalten(autor) then
        return nil, L["Keine Berechtigung (nur Raidleiter oder Gildenleitung)."]
    end
    if not spielerName or spielerName == "" then
        return nil, L["Kein Spielername angegeben."]
    end

    local k = Kern.Schluessel(spielerName)
    if not k then return nil, L["Ungültiger Spielername."] end

    local abend = Anwesenheit.AktiverAbend(true)
    abend.bank = abend.bank or {}
    abend.unentschuldigt = abend.unentschuldigt or {}
    abend.vergessen = abend.vergessen or {}
    abend.abgemeldet = abend.abgemeldet or {}
    abend.protokoll = abend.protokoll or {}

    local anzeigename = Kern.Anzeigename(spielerName)
    local jetzt = time()

    if an then
        abend.bank[k] = nil
        abend.unentschuldigt[k] = nil
        abend.vergessen[k] = nil
        abend.abgemeldet[k] = { name = anzeigename, von = autor, zeit = jetzt }
    else
        abend.abgemeldet[k] = nil
    end
    abend.protokoll[#abend.protokoll + 1] = {
        typ = "abgemeldet", an = an and true or false, spieler = anzeigename, von = autor, zeit = jetzt,
    }
    return true
end

--- Steht der Spieler heute als ausdrücklich abgemeldet in der Liste?
function Anwesenheit.IstAbgemeldet(spielerName, abend)
    abend = abend or Anwesenheit.AktiverAbend(false)
    if not abend or not abend.abgemeldet then return false end
    local k = Kern.Schluessel(spielerName)
    local eintrag = k and abend.abgemeldet[k]
    return (eintrag ~= nil) and true or false, eintrag
end

--- Die Spieler, über die noch niemand entschieden hat: nicht im Raid und weder Bank, Abgemeldet,
--  Keine Meldung noch Unentschuldigt.
--  @return Liste der Anzeigenamen
function Anwesenheit.OffeneSpieler(abend)
    abend = abend or Anwesenheit.AktiverAbend(false)
    local namen = {}
    for _, e in ipairs(Anwesenheit.KandidatenListe(abend)) do
        if e.offen then namen[#namen + 1] = e.name end
    end
    return namen
end

--- Setzt alle offenen Spieler auf einmal als abgemeldet (danach lassen sich einzelne korrigieren).
--  @return Zahl der Gesetzten, oder nil und ein Grund
function Anwesenheit.AlleOffenenAbmelden(vonName)
    local autor = vonName or ichName()
    if autor ~= "System" and not Anwesenheit.DarfBankVerwalten(autor) then
        return nil, L["Keine Berechtigung (nur Raidleiter oder Gildenleitung)."]
    end
    local abend = Anwesenheit.AktiverAbend(true)
    local zahl = 0
    for _, name in ipairs(Anwesenheit.OffeneSpieler(abend)) do
        if Anwesenheit.AbmeldungSetzen(name, true, autor) then zahl = zahl + 1 end
    end
    return zahl
end

--- Steht der Spieler heute als „Keine Meldung“ (früher „Anmeldung vergessen“) in der Liste?
function Anwesenheit.IstVergessen(spielerName, abend)
    abend = abend or Anwesenheit.AktiverAbend(false)
    if not abend or not abend.vergessen then return false end
    local k = Kern.Schluessel(spielerName)
    local eintrag = k and abend.vergessen[k]
    return (eintrag ~= nil) and true or false, eintrag
end

--- Prüft, ob ein Spieler heute auf der Bank sitzt (§ 2: Faktor 0).
function Anwesenheit.IstBank(spielerName, abend)
    abend = abend or Anwesenheit.AktiverAbend(false)
    if not abend or not abend.bank then return false end
    local k = Kern.Schluessel(spielerName)
    local eintrag = k and abend.bank[k]
    return (eintrag ~= nil) and true or false, eintrag
end

--- Prüft, ob ein Spieler heute unentschuldigt fehlt (§ 2: sofort Faktor 1,5, mindestens 2 Punkte).
function Anwesenheit.IstUnentschuldigt(spielerName, abend)
    abend = abend or Anwesenheit.AktiverAbend(false)
    if not abend or not abend.unentschuldigt then return false end
    local k = Kern.Schluessel(spielerName)
    local eintrag = k and abend.unentschuldigt[k]
    return (eintrag ~= nil) and true or false, eintrag
end

--- Liefert Kandidaten für die Liste „online, nicht im Raid" (§ 6).
--  @param mitRaid  true: auch die Spieler zeigen, die gerade im Raid sind (zum Ausprobieren; `imRaid`)
function Anwesenheit.KandidatenListe(abend, mitRaid)
    abend = abend or Anwesenheit.AktiverAbend(false)

    local inRaid = {}
    for _, n in ipairs(Anwesenheit.AnwesendeNamen()) do
        local k = Kern.Schluessel(n)
        if k then inRaid[k] = true end
    end

    local onlineMap = {}
    if ns.Gruppen and ns.Gruppen.GildenMitglieder then
        local GM = ns.Gruppen.GildenMitglieder()
        for _, m in ipairs(GM or {}) do
            local k = Kern.Schluessel(m.name)
            if k then onlineMap[k] = m.online and true or false end
        end
    end

    local pool = {}
    local gesehen = {}

    -- 1. Die erwarteten Spieler dieser Gruppe (Einteilung des Tages, sonst Kader)
    local pflicht, nurEinteilung, bench = erwarteteNamen(abend)
    local pflichtSet = {}
    for _, n in ipairs(pflicht or {}) do
        local k = Kern.Schluessel(n)
        if k then
            pflichtSet[k] = true
            if not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = n
            end
        end
    end
    -- ⭐ Die Bench des Tages steht in jeder Gruppe in der Liste (springt einer ein, stellt man ihn hier um)
    local benchSet = {}
    for _, n in ipairs(bench or {}) do
        local k = Kern.Schluessel(n)
        if k then
            benchSet[k] = true
            if not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = n
            end
        end
    end

    -- Falls kein Gruppenkader vorhanden: Gildenmitglieder als Pool (nie bei einer Einteilung)
    if #pool == 0 and not nurEinteilung and ns.Gruppen and ns.Gruppen.GildenMitglieder then
        local GM = ns.Gruppen.GildenMitglieder()
        for _, m in ipairs(GM or {}) do
            local k = Kern.Schluessel(m.name)
            if k and not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = m.name
            end
        end
    end

    -- Bereits gesetzte Bank- und Unentschuldigt-Einträge hinzunehmen
    if abend then
        for k, b in pairs(abend.bank or {}) do
            if not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = b.name or k
            end
        end
        for k, u in pairs(abend.unentschuldigt or {}) do
            if not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = u.name or k
            end
        end
        for k, a in pairs(abend.abgemeldet or {}) do
            if not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = a.name or k
            end
        end
    end

    if abend then
        for k, v in pairs(abend.vergessen or {}) do
            if not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = v.name or k
            end
        end
    end

    -- Nur Spieler aufnehmen, die NICHT im Raid sind
    local kandidaten = {}
    for _, n in ipairs(pool) do
        local k = Kern.Schluessel(n)
        if k and (mitRaid or not inRaid[k]) then
            local bEintrag = abend and abend.bank and abend.bank[k]
            local uEintrag = abend and abend.unentschuldigt and abend.unentschuldigt[k]
            local vEintrag = abend and abend.vergessen and abend.vergessen[k]
            local aEintrag = abend and abend.abgemeldet and abend.abgemeldet[k]
            -- Bench laut Einteilung gilt wie Bank (Faktor 0), solange nichts anderes eingetragen ist
            local benchE = benchSet[k] and not bEintrag and not uEintrag and not vEintrag and not aEintrag
            local istOnline = onlineMap[k] or false
            local protokollText = ""
            if benchE then
                protokollText = L["Bench laut Einteilung – Klick auf Bank holt ihn in die Gruppe."]
            elseif aEintrag then
                protokollText = string.format(L["Abgemeldet: %s, %s"], aEintrag.von or "?", date(L["%d.%m. %H:%M"], aEintrag.zeit or time()))
            elseif bEintrag then
                protokollText = string.format(L["Bank: %s, %s"], bEintrag.von or "?", date(L["%d.%m. %H:%M"], bEintrag.zeit or time()))
            elseif uEintrag then
                protokollText = string.format(L["Unentschuldigt: %s, %s"], uEintrag.von or "?", date(L["%d.%m. %H:%M"], uEintrag.zeit or time()))
            elseif vEintrag then
                protokollText = string.format(L["Vergessen: %s, %s"], vEintrag.von or "?", date(L["%d.%m. %H:%M"], vEintrag.zeit or time()))
            end

            local istImRaid = inRaid[k] or (nurEinteilung and pflichtSet[k] and not bEintrag and not benchE and not uEintrag and not vEintrag and not aEintrag)
            local istOffen = not inRaid[k] and not bEintrag and not benchE and not uEintrag and not vEintrag and not aEintrag and not (nurEinteilung and pflichtSet[k])
            kandidaten[#kandidaten + 1] = {
                name            = Kern.Anzeigename(n),
                online          = istOnline,
                bank            = bEintrag or (benchE and { name = Kern.Anzeigename(n), von = "Einteilung", zeit = 0 }) or nil,
                benchEinteilung = benchE and true or false,
                unentschuldigt  = uEintrag,
                vergessen       = vEintrag,
                abgemeldet      = aEintrag,
                offen           = istOffen and true or false,
                imRaid          = istImRaid and true or false,
                protokoll       = protokollText,
            }
        end
    end

    table.sort(kandidaten, function(a, b)
        local aAktiv = (a.bank ~= nil or a.unentschuldigt ~= nil or a.vergessen ~= nil or a.abgemeldet ~= nil) and 1 or 0
        local bAktiv = (b.bank ~= nil or b.unentschuldigt ~= nil or b.vergessen ~= nil or b.abgemeldet ~= nil) and 1 or 0
        if a.imRaid ~= b.imRaid then return b.imRaid and true or false end     -- wer im Raid steht, zuletzt
        if a.offen ~= b.offen then return a.offen and true or false end       -- wer noch offen ist, zuerst
        if a.benchEinteilung ~= b.benchEinteilung then return a.benchEinteilung and true or false end   -- dann die Bench
        if aAktiv ~= bAktiv then return aAktiv > bAktiv end
        if a.online ~= b.online then return a.online and not b.online end
        return a.name < b.name
    end)

    return kandidaten
end

-- =====================================================================
--  Automatik über Encounter-Ereignisse & Gruppen-Konvertierung
-- =====================================================================

local anwesenheitAutoRaid = false
local autoRaidBis = 0              -- Ablauf der Einladungsrunde (3 Minuten), danach macht das Addon keinen Raid mehr von selbst

local function konvertiereZuRaid()
    if C_PartyInfo and C_PartyInfo.ConvertToRaid then
        pcall(C_PartyInfo.ConvertToRaid)
    elseif ConvertToRaid then
        pcall(ConvertToRaid)
    end
end

-- ⭐ Aus einer normalen Gruppe wird nur dann ein Raid, wenn sie schon 5 Mitglieder hat und noch jemand dazukommen
-- soll (Nutzerwunsch 23.10.2026). Vorher machte das Addon schon beim ersten Eingeladenen einen Raid daraus.
local function istNormaleGruppe()
    return (IsInGroup and IsInGroup()) and not (IsInRaid and IsInRaid()) and true or false
end

local function gruppenGroesse()
    if not (IsInGroup and IsInGroup()) then return 0 end
    return (GetNumGroupMembers and GetNumGroupMembers()) or 1
end

--- Ist die normale Gruppe voll (5) und muss darum für den nächsten zum Raid werden?
local function raidNoetig()
    return istNormaleGruppe() and gruppenGroesse() >= 5
end

local eigeneEinladung = false        -- die Einladung stammt vom Addon selbst (nicht doppelt behandeln)

--- Eine Einladung von Hand (oder über ein anderes Addon): Ist die normale Gruppe voll, erst zum Raid machen und die
--  Einladung gleich danach wiederholen, sonst scheitert sie mit „Gruppe voll“.
local function beiEinladung(name)
    if eigeneEinladung or type(name) ~= "string" or name == "" then return end
    if not (ns.Rolle and ns.Rolle.Aktiv and ns.Rolle.Aktiv()) then return end        -- das Addon schläft
    if not raidNoetig() then return end
    if UnitIsGroupLeader and not UnitIsGroupLeader("player") then return end
    konvertiereZuRaid()
    if C_Timer then
        C_Timer.After(0.7, function()
            eigeneEinladung = true
            if C_PartyInfo and C_PartyInfo.InviteUnit then
                pcall(C_PartyInfo.InviteUnit, name)
            elseif InviteUnit then
                pcall(InviteUnit, name)
            end
            eigeneEinladung = false
        end)
    end
end
Anwesenheit.BeiEinladung = beiEinladung

if hooksecurefunc then
    if rawget(_G, "InviteUnit") then pcall(hooksecurefunc, "InviteUnit", beiEinladung) end
    if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(hooksecurefunc, C_PartyInfo, "InviteUnit", beiEinladung) end
end

-- =====================================================================
--  ⭐ Einladen per Flüstern (Nutzerwunsch 23.10.2026): Wer dir dein Stichwort flüstert, wird in deine Gruppe
--  eingeladen. Eine persönliche Einstellung (nicht geteilt), standardmäßig aus.
-- =====================================================================

local EINLADE_STANDARD = "invite"
local einladePause = {}              -- Schlüssel des Absenders -> Zeitpunkt der letzten Einladung

local function einladeDb()
    FairshareDB = FairshareDB or {}
    local d = FairshareDB.einladen
    if type(d) ~= "table" then
        d = { an = false, wort = EINLADE_STANDARD }
        FairshareDB.einladen = d
    end
    if type(d.wort) ~= "string" or d.wort == "" then d.wort = EINLADE_STANDARD end
    return d
end

--- Das Stichwort und ob die Funktion an ist.
function Anwesenheit.EinladeWort()
    local d = einladeDb()
    return d.wort, d.an and true or false
end

function Anwesenheit.EinladeAn(an)
    einladeDb().an = an and true or false
end

--- Setzt das Stichwort (2 bis 30 Zeichen, ohne Farbcodes oder Schrägstrich am Anfang).
--  @return true oder false und ein Grund
function Anwesenheit.EinladeWortSetzen(wort)
    wort = tostring(wort or ""):match("^%s*(.-)%s*$")
    if #wort < 2 then return false, L["Das Stichwort braucht mindestens 2 Zeichen."] end
    if #wort > 30 then return false, L["Das Stichwort darf höchstens 30 Zeichen haben."] end
    if wort:find("|", 1, true) or wort:sub(1, 1) == "/" then
        return false, L["Das Stichwort darf nicht mit / beginnen und keine Sonderzeichen mit | enthalten."]
    end
    einladeDb().wort = wort
    return true
end

--- Lädt einen Spieler ein. Ist die normale Gruppe voll (5), wird sie vorher zum Raid, die Einladung folgt danach.
function Anwesenheit.Einladen(name)
    local function laden()
        eigeneEinladung = true
        if C_PartyInfo and C_PartyInfo.InviteUnit then
            pcall(C_PartyInfo.InviteUnit, name)
        elseif InviteUnit then
            pcall(InviteUnit, name)
        end
        eigeneEinladung = false
    end
    if raidNoetig() and (not UnitIsGroupLeader or UnitIsGroupLeader("player")) then
        konvertiereZuRaid()
        if C_Timer then C_Timer.After(0.7, laden) else laden() end
    else
        laden()
    end
end

--- Eine Flüsternachricht: Entspricht sie dem Stichwort, wird der Absender eingeladen.
--  @return true, wenn eingeladen wurde
function Anwesenheit.Fluestern(text, absender)
    local d = einladeDb()
    if not d.an or type(text) ~= "string" or type(absender) ~= "string" or absender == "" then return false end
    if text:match("^%s*(.-)%s*$"):lower() ~= d.wort:lower() then return false end
    if Kern.GleicherSpieler(absender, ichName()) then return false end

    local k = Kern.Schluessel(absender)
    local jetzt = (GetTime and GetTime()) or time()
    if k and einladePause[k] and (jetzt - einladePause[k]) < 15 then return false end      -- nicht mehrfach hintereinander

    if (UnitInRaid and UnitInRaid(absender)) or (UnitInParty and UnitInParty(absender)) then return false end
    if ns.Rolle and ns.Rolle.Namen then
        for _, n in ipairs(ns.Rolle.Namen()) do
            if Kern.GleicherSpieler(n, absender) then return false end        -- schon in der Gruppe
        end
    end
    local imRaid = IsInRaid and IsInRaid()
    if imRaid and UnitIsGroupLeader and not (UnitIsGroupLeader("player") or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))) then
        return false                -- im Raid dürfen nur Leiter und Assistenten einladen
    end
    if imRaid and gruppenGroesse() >= 40 then
        print(string.format(L["|cff1B6B57KaosLoot|r: %s hat dir das Stichwort geflüstert, aber der Raid ist voll."], Kern.Anzeigename(absender)))
        return false
    end

    if k then einladePause[k] = jetzt end
    Anwesenheit.Einladen(absender)
    print(string.format(L["|cff1B6B57KaosLoot|r: %s per Flüstern eingeladen (Stichwort „%s“)."], Kern.Anzeigename(absender), d.wort))
    return true
end

local frame = CreateFrame and CreateFrame("Frame")
if frame then
    pcall(function() frame:RegisterEvent("CHAT_MSG_WHISPER") end)
    pcall(function() frame:RegisterEvent("ENCOUNTER_END") end)
    pcall(function() frame:RegisterEvent("BOSS_KILL") end)
    pcall(function() frame:RegisterEvent("GROUP_ROSTER_UPDATE") end)

    frame:SetScript("OnEvent", function(_, ereignis, a1, a2, _, _, a5)
        if ereignis == "CHAT_MSG_WHISPER" then
            pcall(Anwesenheit.Fluestern, a1, a2)
            return
        end
        if ereignis == "GROUP_ROSTER_UPDATE" then
            if istNormaleGruppe() then
                local istLeiter = not UnitIsGroupLeader or UnitIsGroupLeader("player")
                -- Nur mit der Einladungsliste im Gang (Knopf Gruppe einladen) und erst bei 5 Mitgliedern
                if istLeiter and anwesenheitAutoRaid and (time() <= autoRaidBis or autoRaidBis == 0) and gruppenGroesse() >= 5 then
                    konvertiereZuRaid()
                    local timer = C_Timer and C_Timer.After
                    if timer then
                        timer(0.5, function()
                            if anwesenheitAutoRaid then
                                Anwesenheit.GruppeEinladen(true)
                            end
                        end)
                    else
                        Anwesenheit.GruppeEinladen(true)
                    end
                end
            elseif not IsInGroup or not IsInGroup() then
                anwesenheitAutoRaid = false
            end
            return
        end

        -- Nur aufzeichnen, wenn in einer Gruppe und Aufzeichner
        if not (IsInGroup and IsInGroup()) then return end
        if ns.Rolle and ns.Rolle.IchSchreibe and not ns.Rolle.IchSchreibe() then return end

        if ereignis == "ENCOUNTER_END" then
            -- a1 = encounterID, a2 = encounterName, a5 = success (1 = kill, 0 = wipe)
            local success = (a5 == 1 or a5 == true)
            if success then
                local ok, anzahl, bName = Anwesenheit.BossBuchen(a2, a1, true)
                if ok then
                    print(string.format(L["|cff1B6B57KaosLoot|r: Bosskampf %s erfasst (%d Spieler anwesend)."],
                        tostring(bName), anzahl))
                end
            end
        elseif ereignis == "BOSS_KILL" then
            -- a1 = encounterID, a2 = encounterName
            local ok, anzahl, bName = Anwesenheit.BossBuchen(a2, a1, true)
            if ok then
                print(string.format(L["|cff1B6B57KaosLoot|r: Bosskampf %s erfasst (%d Spieler anwesend)."],
                    tostring(bName), anzahl))
            end
        end
    end)
end

-- =====================================================================
--  Abendende & Festschreibung der Zuschläge (§ 2, § 6)
-- =====================================================================

--- Ermittelt die an diesem Abend vergebenen Main-Items (§ 2).
function Anwesenheit.AbendMainItems(abend)
    abend = abend or Anwesenheit.AktiverAbend(false)
    if not abend then return 0, {} end

    local d = db()
    local hist = (ns.Erfassung and ns.Erfassung.Historie and ns.Erfassung.Historie()) or d.historie or {}
    local anzahl, items = 0, {}

    local abendDatum = abend.datum
    local abendStart = abend.start or (time() - 14 * 3600)
    local abendEnde = abend.ende or (time() + 3600)

    for id, e in pairs(hist) do
        if Kern.Zaehlt(e) and not e.OS then
            local tag = date("%Y-%m-%d", e.timestamp)
            local passtZeit = (e.timestamp >= abendStart - 3600 and e.timestamp <= abendEnde)
            local passtGruppe = (not abend.gruppe or not e.gruppe or e.gruppe == abend.gruppe)
            if (tag == abendDatum or passtZeit) and passtGruppe then
                anzahl = anzahl + 1
                items[#items + 1] = { id = id, eintrag = e }
            end
        end
    end

    return anzahl, items
end

--- ⭐ Wer zählt an diesem Abend als „im Raid“ (Entscheid 17.10.2026)? Nicht die Bosskämpfe entscheiden,
--  sondern der Raid am Abendende: Wer dann in der Gruppe steht, ist anwesend. Wer im Lauf des Abends
--  gegangen ist, gilt als abwesend (und kann als unentschuldigt markiert werden) — es sei denn, er hat
--  vorher ein Main-Item bekommen: Das Item steht im Schnitt, also zählt er mit.
--  Ohne WoW-Gruppe (Prüfstand) gilt die Liste des letzten gebuchten Bosskampfs.
--  @return Menge Schlüssel -> Name, Anzahl
function Anwesenheit.RaidMenge(abend, items)
    local menge = {}
    local pflichtListe, nurEinteilung, benchListe = erwarteteNamen(abend)
    local benchSet = {}
    for _, n in ipairs(benchListe or {}) do
        local k = Kern.Schluessel(n)
        if k then benchSet[k] = true end
    end

    local function istAusgeschlossen(k)
        if not abend then return false end
        if abend.bank and abend.bank[k] then return true end
        if abend.unentschuldigt and abend.unentschuldigt[k] then return true end
        if abend.abgemeldet and abend.abgemeldet[k] then return true end
        if abend.vergessen and abend.vergessen[k] then return true end
        if benchSet[k] then return true end
        return false
    end

    -- 1. Eingeteilte Spieler (nur bei echter Einteilung des Tages: Standard ist Anwesend)
    if nurEinteilung then
        for _, n in ipairs(pflichtListe or {}) do
            local k = Kern.Schluessel(n)
            if k and not istAusgeschlossen(k) then
                menge[k] = n
            end
        end
    end

    -- 2. Aktuell im Raid oder aus Bossliste (z.B. Gäste/Pugs)
    local namen
    if anwesendeOverride then
        namen = anwesendeOverride
    elseif ns.Rolle and ns.Rolle.Einheiten and not dbOverride then      -- im Prüfstand (Mock-DB): Liste des letzten Bosses
        namen = anwesendeNamen()
    else
        local b = abend.bossListe and abend.bossListe[#abend.bossListe]
        namen = (b and b.anwesende) or {}
    end
    for _, n in ipairs(namen or {}) do
        local k = Kern.Schluessel(n)
        if k and not istAusgeschlossen(k) then
            menge[k] = n
        end
    end

    -- 3. Spieler, die ein Main-Item bekommen haben
    for _, it in ipairs(items or {}) do
        local k = Kern.Schluessel(it.eintrag.awardedTo)
        if k and not menge[k] then menge[k] = it.eintrag.awardedTo end
    end
    local anzahl = 0
    for _ in pairs(menge) do anzahl = anzahl + 1 end
    return menge, anzahl
end

--- Berechnet den Schnitt des Abends (§ 2: vergebene Main-Items / Spieler im Raid).
--  @return schnitt, mainItems, anzahlRaidSpieler, raidMenge
function Anwesenheit.AbendSchnitt(abend)
    abend = abend or Anwesenheit.AktiverAbend(false)
    if not abend then return 0, 0, 0, {} end

    local mainItems, items = Anwesenheit.AbendMainItems(abend)
    local menge, anzahlRaidSpieler = Anwesenheit.RaidMenge(abend, items)

    local schnitt = Kern.AbendSchnitt(mainItems, anzahlRaidSpieler)
    return schnitt, mainItems, anzahlRaidSpieler, menge
end

--- Zählt die Fehlabende (abgemeldet und unentschuldigt) eines Spielers
--  in den letzten X archivierten Raidabenden (§ 2).
--  Bank und ImRaid zählen nicht als Fehlen.
function Anwesenheit.Fehlhistorie(spielerName, maxAbende)
    if not spielerName then return 0, 0 end
    local k = Kern.Schluessel(spielerName)
    if not k then return 0, 0 end
    maxAbende = maxAbende or 5

    local d = db()
    local archiv = {}
    for _, ab in pairs(d.abende or {}) do
        if ab.abgeschlossen or ab.abschluss then
            -- ⭐ Nur die EIGENEN Abende des Spielers zählen (Entscheid 18.10.2026: mehrere Gruppen): Ein Abend einer
            -- anderen Gruppe, in dem er nicht vorkommt, schiebt sein Fenster nicht weiter.
            local sp = ab.abschluss and ab.abschluss.spieler
            if sp == nil or sp[k] ~= nil then archiv[#archiv + 1] = ab end
        end
    end

    table.sort(archiv, function(a, b)
        local ta = (a.abschluss and a.abschluss.zeit) or a.start or 0
        local tb = (b.abschluss and b.abschluss.zeit) or b.start or 0
        return ta > tb
    end)

    local fehlen = 0
    local geprueft = 0
    for i = 1, math.min(#archiv, maxAbende) do
        local ab = archiv[i]
        geprueft = geprueft + 1
        if ab.abschluss and ab.abschluss.spieler then
            local sp = ab.abschluss.spieler[k]
            if sp then
                local st = sp.status
                if st == "abgemeldet" or st == "unentschuldigt" or st == "vergessen" or st == "vergessenStrafe" then
                    fehlen = fehlen + 1
                end
            end
        else
            local imRaid = false
            if ab.bosse and ab.bosse > 0 and ab.anwesenheit and ab.anwesenheit[k] then
                imRaid = (ab.anwesenheit[k] >= math.ceil(ab.bosse / 2))
            end
            local bank = ab.bank and ab.bank[k]
            if not imRaid and not bank then
                fehlen = fehlen + 1
            end
        end
    end

    return fehlen, geprueft
end

--- Wie oft stand der Spieler in den letzten `maxAbende` abgeschlossenen Raidabenden als
--  „Anmeldung vergessen"? (Der aktuelle Abend zählt nicht mit.)
function Anwesenheit.VergessenHistorie(spielerName, maxAbende)
    local k = Kern.Schluessel(spielerName)
    if not k then return 0 end
    maxAbende = maxAbende or (Kern.VERGESSEN_FENSTER - 1)

    local archiv = {}
    for _, ab in pairs(db().abende or {}) do
        if ab.abgeschlossen and ab.abschluss then
            local sp = ab.abschluss.spieler
            if sp == nil or sp[k] ~= nil then archiv[#archiv + 1] = ab end      -- nur eigene Abende
        end
    end
    table.sort(archiv, function(a, b)
        return ((a.abschluss and a.abschluss.zeit) or 0) > ((b.abschluss and b.abschluss.zeit) or 0)
    end)

    local n = 0
    for i = 1, math.min(#archiv, maxAbende) do
        local sp = archiv[i].abschluss.spieler and archiv[i].abschluss.spieler[k]
        if sp and (sp.status == "vergessen" or sp.status == "vergessenStrafe") then n = n + 1 end
    end
    return n
end

--- Erstellt eine Vorschau auf den Abschluss des aktuellen Raidabends (§ 2, § 6).
--  @param offeneAlsAbgemeldet  true: wer noch offen ist, gilt wie abgemeldet (nur Prüfstand/System)
function Anwesenheit.AbendVorschau(abend, offeneAlsAbgemeldet)
    abend = abend or Anwesenheit.AktiverAbend(false)
    if not abend then return nil, L["Kein aktiver Abend vorhanden."] end

    local schnitt, mainItems, anzahlRaid, raidSpieler = Anwesenheit.AbendSchnitt(abend)
    local gesamtBosse = abend.bosse or 0

    -- Pool aller relevanten Kaderspieler
    local pool = {}
    local gesehen = {}

    -- 1. Die erwarteten Spieler (Einteilung des Tages, sonst Kader der Gruppe)
    local pflichtListe, nurEinteilung, benchListe = erwarteteNamen(abend)
    local pflichtSet = {}
    for _, n in ipairs(pflichtListe or {}) do
        local k = Kern.Schluessel(n)
        if k then
            pflichtSet[k] = true
            if not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = n
            end
        end
    end
    -- ⭐ Bench laut Einteilung: Bank-Faktor 0 (jeder Gruppenabend führt sie mit)
    local benchSet = {}
    for _, n in ipairs(benchListe or {}) do
        local k = Kern.Schluessel(n)
        if k then
            benchSet[k] = true
            if not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = n
            end
        end
    end

    -- 2. Aus Gildenmitgliedern (nie bei einer Einteilung)
    if #pool == 0 and not nurEinteilung and ns.Gruppen and ns.Gruppen.GildenMitglieder then
        for _, m in ipairs(ns.Gruppen.GildenMitglieder() or {}) do
            local k = Kern.Schluessel(m.name)
            if k and not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = m.name
            end
        end
    end

    -- 2b. Wer im Raid steht oder ein Main-Item bekam, gehört immer in die Liste
    for k, n in pairs(raidSpieler) do
        if not gesehen[k] then
            gesehen[k] = true
            pool[#pool + 1] = n
        end
    end

    -- 3. Aus Teilnehmern des Abends (Kader)
    for k, t in pairs(abend.teilnehmer or {}) do
        if not gesehen[k] and (t.status == "kader" or t.status == "neuling") then
            gesehen[k] = true
            pool[#pool + 1] = t.name or k
        end
    end

    -- 4. Bereits gesetzte Bank und Unentschuldigt
    for k, b in pairs(abend.bank or {}) do
        if not gesehen[k] then
            gesehen[k] = true
            pool[#pool + 1] = b.name or k
        end
    end
    for k, u in pairs(abend.unentschuldigt or {}) do
        if not gesehen[k] then
            gesehen[k] = true
            pool[#pool + 1] = u.name or k
        end
    end

    for k, v in pairs(abend.vergessen or {}) do
        if not gesehen[k] then
            gesehen[k] = true
            pool[#pool + 1] = v.name or k
        end
    end
    for k, a in pairs(abend.abgemeldet or {}) do
        if not gesehen[k] then
            gesehen[k] = true
            pool[#pool + 1] = a.name or k
        end
    end

    local ergebnisse = {}
    for _, n in ipairs(pool) do
        local k = Kern.Schluessel(n)
        local anzeigename = Kern.Anzeigename(n)
        local bEintrag = abend.bank and abend.bank[k]
        local uEintrag = abend.unentschuldigt and abend.unentschuldigt[k]
        local vEintrag = abend.vergessen and abend.vergessen[k]
        local aEintrag = abend.abgemeldet and abend.abgemeldet[k]
        local bosse = (abend.anwesenheit and abend.anwesenheit[k]) or 0
        local imRaid = raidSpieler[k] or false

        local status, faktor, zuschlag, fehlAnzahl
        if imRaid then
            status = "imRaid"
            faktor = 0
            zuschlag = 0
            fehlAnzahl = 0
        elseif bEintrag then
            status = "bank"
            faktor = Kern.FAKTOR_BANK
            zuschlag = 0
            fehlAnzahl = 0
        elseif uEintrag then
            status = "unentschuldigt"
            fehlAnzahl = Anwesenheit.Fehlhistorie(n, 5) + 1
            faktor = Kern.FAKTOR_UNENTSCHULDIGT
            -- Faktor 1,5, aber mindestens 2 Wertungspunkte (Gildenleitung 17.10.2026)
            zuschlag = Kern.ZuschlagUnentschuldigt(schnitt)
        elseif vEintrag then
            -- ⭐ Anmeldung vergessen: das 1. und 2. Mal in den letzten 8 Abenden wie eine Abmeldung,
            -- ab dem 3. Mal wie unentschuldigt (Faktor 1,5, mindestens 2 Punkte)
            local anzahl = Anwesenheit.VergessenHistorie(n, Kern.VERGESSEN_FENSTER - 1) + 1
            if anzahl > Kern.VERGESSEN_SCHWELLE then
                status = "vergessenStrafe"
                fehlAnzahl = anzahl           -- hier: das wievielte Mal (die Staffel gilt nicht)
                faktor = Kern.FAKTOR_UNENTSCHULDIGT
                zuschlag = Kern.ZuschlagUnentschuldigt(schnitt)
            else
                status = "vergessen"
                fehlAnzahl = Anwesenheit.Fehlhistorie(n, 5) + 1
                faktor = Kern.FehlFaktor(fehlAnzahl, "abgemeldet")
                zuschlag = Kern.Zuschlag(faktor, schnitt)
            end
        elseif benchSet[k] and not aEintrag then
            -- Bench laut Einteilung, nichts anderes eingetragen: wie Bank
            status = "bank"
            faktor = Kern.FAKTOR_BANK
            zuschlag = 0
            fehlAnzahl = 0
        elseif nurEinteilung and pflichtSet[k] and not aEintrag then
            -- ⭐ Eingeteilt und nichts gewählt: Standard ist Anwesend (Faktor 0, 0 Zuschlag)
            status = "imRaid"
            fehlAnzahl = 0
            faktor = 0
            zuschlag = 0
        elseif aEintrag or offeneAlsAbgemeldet then
            status = "abgemeldet"
            fehlAnzahl = Anwesenheit.Fehlhistorie(n, 5) + 1
            faktor = Kern.FehlFaktor(fehlAnzahl, "abgemeldet")
            zuschlag = Kern.Zuschlag(faktor, schnitt)
        else
            -- ⭐ Niemand hat entschieden: offen.
            status = "offen"
            fehlAnzahl = 0
            faktor = 0
            zuschlag = 0
        end

        ergebnisse[#ergebnisse + 1] = {
            name        = anzeigename,
            schluessel  = k,
            status      = status,
            faktor      = faktor,
            zuschlag    = zuschlag,
            fehlAnzahl  = fehlAnzahl,
            bosse       = bosse,
            gesamtBosse = gesamtBosse,
            imRaid      = imRaid,
            bank        = bEintrag,
            unent       = uEintrag,
            vergessen   = vEintrag,
        }
    end

    local rang = { offen = 6, vergessenStrafe = 5, unentschuldigt = 4, vergessen = 3.5, abgemeldet = 3, bank = 2, imRaid = 1 }
    table.sort(ergebnisse, function(a, b)
        local ra, rb = rang[a.status] or 0, rang[b.status] or 0
        if ra ~= rb then return ra > rb end
        return a.name < b.name
    end)

    return {
        abendId     = abend.id,
        datum       = abend.datum,
        schnitt     = schnitt,
        mainItems   = mainItems,
        raidSpieler = anzahlRaid,
        gesamtBosse = gesamtBosse,
        spieler     = ergebnisse,
    }
end

--- Schließt den Raidabend ab und schreibt alle Zuschläge fest (§ 2, § 6).
--  @param abend      Optionaler Abend (Standard: aktiver Abend)
--  @param autorName  Optionaler Name des Schreibers / Leiters
--  @return ok, vorschau, anzahlZuschlaege (oder nil und Fehlergrund)
--  @param streng      true: auch als „System“ keine offenen Spieler zulassen (Prüfstand)
function Anwesenheit.AbendAbschliessen(abend, autorName, streng)
    local autor = autorName or ichName()
    if autor ~= "System" and not Anwesenheit.DarfBankVerwalten(autor) and not Anwesenheit.DarfUnentschuldigtVerwalten(autor) then
        return nil, L["Keine Berechtigung (nur Raidleiter oder Gildenleitung)."]
    end

    abend = abend or Anwesenheit.AktiverAbend(false)
    if not abend then return nil, L["Kein aktiver Abend vorhanden."] end
    if abend.abgeschlossen then return nil, L["Abend ist bereits abgeschlossen."] end

    -- ⭐ Wer weder im Raid noch zugeordnet ist, verhindert den Abschluss. Nur der Prüfstand („System“) darf
    -- offene wie Abgemeldete behandeln.
    local lax = (autor == "System") and not streng
    local vorschau, grund = Anwesenheit.AbendVorschau(abend, lax)
    if not vorschau then return nil, grund end
    local offene = {}
    for _, p in ipairs(vorschau.spieler) do
        if p.status == "offen" then offene[#offene + 1] = p.name end
    end
    if #offene > 0 then
        local zeigen = {}
        for i = 1, math.min(5, #offene) do zeigen[i] = offene[i] end
        local liste = table.concat(zeigen, ", ") .. ((#offene > 5) and ", …" or "")
        return nil, string.format(L["Der Abend lässt sich nicht abschließen: %d Spieler sind noch offen (%s). Bitte jeden als Bank, Abgemeldet, Keine Meldung oder Unentschuldigt eintragen."], #offene, liste)
    end

    local jetzt = time()
    local d = db()
    d.zuschlaege = d.zuschlaege or {}

    abend.buchRev = Kern.BuchRev(abend) + 1
    abend.abgeschlossen = true
    abend.ende = jetzt
    abend.abschluss = {
        zeit        = jetzt,
        datum       = abend.datum,
        autor       = autor,
        schnitt     = vorschau.schnitt,
        mainItems   = vorschau.mainItems,
        raidSpieler = vorschau.raidSpieler,
        gesamtBosse = vorschau.gesamtBosse,
        spieler     = {},
    }

    local zuschlagZaehler = 0
    for _, p in ipairs(vorschau.spieler) do
        abend.abschluss.spieler[p.schluessel] = {
            name       = p.name,
            status     = p.status,
            faktor     = p.faktor,
            schnitt    = vorschau.schnitt,
            zuschlag   = p.zuschlag,
            fehlAnzahl = p.fehlAnzahl,
            bosse      = p.bosse,
            gesamt     = p.gesamtBosse,
            zeit       = jetzt,
            von        = autor,
        }

        if p.zuschlag > 0 then
            local zId = string.format("z_%s_%s", abend.id, p.schluessel)
            d.zuschlaege[zId] = {
                id         = zId,
                abendId    = abend.id,
                datum      = abend.datum,
                zeit       = jetzt,
                spieler    = p.name,
                schluessel = p.schluessel,
                status     = p.status,
                faktor     = p.faktor,
                schnitt    = vorschau.schnitt,
                zuschlag   = p.zuschlag,
                fehlAnzahl = p.fehlAnzahl,
                autor      = autor,
            }
            zuschlagZaehler = zuschlagZaehler + 1
        end
    end

    d.abende[abend.id] = abend
    d.aktiverAbend = nil

    Anwesenheit.BuchVerteilen({ "a:" .. tostring(abend.id) .. "@" .. abend.buchRev })

    return true, vorschau, zuschlagZaehler
end

--- Meldet geaenderte Saetze des Datenbuchs an die Gruppe (live), damit jeder
--  dieselbe Wertung rechnet. Ohne Gruppe oder Abgleich passiert nichts.
--  @param liste  z. B. { "a:2026-10-16@2", "h:h_kaos_123" }
function Anwesenheit.BuchVerteilen(liste)
    if ns.Abgleich and ns.Abgleich.BuchVerteilen then
        pcall(ns.Abgleich.BuchVerteilen, liste)
    end
end

--- Hebt den Abschluss eines Raidabends auf und entfernt die generierten Zuschläge (§ 6).
function Anwesenheit.AbendWiedereroeffnen(abendId, autorName)
    local autor = autorName or ichName()
    if autor ~= "System" and not Anwesenheit.DarfBankVerwalten(autor) and not Anwesenheit.DarfUnentschuldigtVerwalten(autor) then
        return nil, L["Keine Berechtigung (nur Raidleiter oder Gildenleitung)."]
    end

    local d = db()
    local abend
    if abendId then
        abend = d.abende[abendId]
    else
        -- ⭐ der jüngste Abend der AKTIVEN Gruppe (nicht irgendeiner)
        local kennung = Anwesenheit.GruppenKennung(ns.Gruppen and ns.Gruppen.AktivName and ns.Gruppen.AktivName())
        local neuesteZeit = 0
        for _, ab in pairs(d.abende or {}) do
            local tz = (ab.abschluss and ab.abschluss.zeit) or ab.start or 0
            if tz > neuesteZeit and abendGruppenKennung(ab) == kennung then
                neuesteZeit = tz
                abend = ab
            end
        end
    end

    if not abend then return nil, L["Kein passender Abend gefunden."] end

    -- Festgeschriebene Zuschläge dieses Abends entfernen
    if d.zuschlaege then
        local zuLoeschen = {}
        for zId, z in pairs(d.zuschlaege) do
            if z.abendId == abend.id then
                zuLoeschen[#zuLoeschen + 1] = zId
            end
        end
        for _, zId in ipairs(zuLoeschen) do
            d.zuschlaege[zId] = nil
        end
    end

    abend.buchRev = Kern.BuchRev(abend) + 1
    abend.abgeschlossen = nil
    abend.abschluss = nil
    abend.ausgeblendet = nil
    d.aktiverAbend = abend

    Anwesenheit.BuchVerteilen({ "a:" .. tostring(abend.id) .. "@" .. abend.buchRev })

    return true, abend
end

-- =====================================================================
--  ⭐ Wochenabschluss: Abgemeldete und „Keine Meldung“ (Entscheid 18.10.2026)
--
--  Wer in einer Woche (Montag bis Sonntag) an keinem Tag in einer Gruppe, auf der Bench oder bei „Keine Meldung“
--  eingeteilt war (und auch an keinem Gruppenabend dabei), gilt als ABGEMELDET; wer nur bei „Keine Meldung“ stand,
--  als „Keine Meldung“. Beide bekommen einen Zuschlag **für zwei Abende** (so viele Abende hat eine Raid-ID): je Abend
--  Staffel × Schnitt, und der Schnitt ist das **Mittel der Schnitte der Gruppen** für diese Abend-Nummer. Gebucht wird
--  bewusst mit einem Knopf, nachdem alle Gruppenabende der Woche abgeschlossen sind (`/kl woche`).
-- =====================================================================

--- Die sieben Tage (JJJJ-MM-TT) der **Raid-ID**, in der `datum` liegt (vom Wechseltag an, Entscheid 22.10.2026).
function Anwesenheit.WochenTage(datum)
    local start = ns.Gruppen.IdStart(datum)
    local y, m, d = tostring(start):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return {} end
    local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    local tage = {}
    for i = 0, 6 do tage[#tage + 1] = date("%Y-%m-%d", t + i * 86400) end
    return tage
end

local function wochenId(montag, k) return string.format("%s_wb%d", montag, k) end

--- Ist das eine Wochenbuchung (und kein Gruppenabend)? Auch bei Abenden, die per Datenbuch von anderen kamen.
local function istWochenbuchung(ab)
    return (ab.woche or tostring(ab.id or ""):match("_wb%d+$") ~= nil) and true or false
end

--- Die Vorschau der Woche: wer wird gebucht, mit welchem Schnitt. Nichts wird verändert.
--  @return Tabelle { montag, n, schnitte = {…}, abgemeldet = { Namen }, keineMeldung = { Namen } } oder nil und ein Grund
function Anwesenheit.WocheVorschau(datum)
    if not (ns.Gruppen and ns.Gruppen.Raidkader) then return nil, L["Erst den Raidkader synchronisieren."] end
    local kader = ns.Gruppen.Raidkader()
    if #kader == 0 then return nil, L["Erst den Raidkader synchronisieren."] end

    local tage = Anwesenheit.WochenTage(datum)
    if #tage == 0 then return nil, L["Ungültiges Datum."] end
    local imTag = {}
    for _, tg in ipairs(tage) do imTag[tg] = true end

    -- Die abgeschlossenen Gruppenabende der Woche (ohne die Wochenbuchungen selbst), je Gruppe nach Datum
    local gruppen = {}
    local raus = {}                              -- Spieler, die an einem Gruppenabend der Woche dabei waren
    for _, ab in pairs(db().abende or {}) do
        if ab.abgeschlossen and ab.abschluss and not istWochenbuchung(ab) and imTag[ab.datum or ""] then
            local g = abendGruppenKennung(ab) or "-"
            gruppen[g] = gruppen[g] or {}
            table.insert(gruppen[g], ab)
            for k, sp in pairs(ab.abschluss.spieler or {}) do
                if sp.status == "imRaid" then raus[k] = true end
            end
        end
    end
    local n = 0
    for _, liste in pairs(gruppen) do
        table.sort(liste, function(a, b) return (a.datum or "") < (b.datum or "") end)
        if #liste > n then n = #liste end
    end
    if n == 0 then return nil, L["In dieser Woche ist noch kein Gruppenabend abgeschlossen."] end
    local schnitte = {}
    for i = 1, n do
        local summe, anzahl = 0, 0
        for _, liste in pairs(gruppen) do
            if liste[i] then
                summe = summe + (tonumber(liste[i].abschluss.schnitt) or 0)
                anzahl = anzahl + 1
            end
        end
        schnitte[i] = Kern.Runde3(anzahl > 0 and (summe / anzahl) or 0)
    end

    local v = { montag = tage[1], n = n, schnitte = schnitte, abgemeldet = {}, keineMeldung = {} }
    for _, m in ipairs(kader) do
        local k = Kern.Schluessel(m.name)
        if k and not raus[k] then
            local untergebracht, keine = false, false
            for _, tg in ipairs(tage) do
                local g = ns.Gruppen.EinteilungVon(tg, m.name)
                if g == ns.Gruppen.KEINEMELDUNG then
                    keine = true
                elseif g ~= nil then
                    untergebracht = true             -- Gruppe oder Bench
                end
            end
            if not untergebracht then
                if keine then v.keineMeldung[#v.keineMeldung + 1] = m.name
                else v.abgemeldet[#v.abgemeldet + 1] = m.name end
            end
        end
    end
    table.sort(v.abgemeldet, function(a, b) return a:lower() < b:lower() end)
    table.sort(v.keineMeldung, function(a, b) return a:lower() < b:lower() end)
    return v
end

--- Nimmt die Wochenbuchung zurück (Zuschläge weg, bei allen). @return Zahl der zurückgenommenen Abende
function Anwesenheit.WocheZuruecknehmen(datum, autorName)
    local autor = autorName or ichName()
    if not (ns.Gruppen and ns.Gruppen.EinteilungDarf(autor)) then
        return nil, L["Keine Berechtigung (nur Gildenränge mit Schreibrecht)."]
    end
    local d = db()
    local montag = Anwesenheit.WochenTage(datum)[1]
    if not montag then return nil, L["Ungültiges Datum."] end
    local zahl, liste = 0, {}
    for k = 1, 7 do
        local id = wochenId(montag, k)
        local ab = d.abende and d.abende[id]
        if ab and istWochenbuchung(ab) then
            for zId, z in pairs(d.zuschlaege or {}) do
                if z.abendId == id then d.zuschlaege[zId] = nil end
            end
            ab.buchRev = Kern.BuchRev(ab) + 1
            ab.abgeschlossen = nil
            ab.abschluss = nil
            liste[#liste + 1] = "a:" .. id .. "@" .. ab.buchRev
            zahl = zahl + 1
        end
    end
    if d.wochenGruppen and d.wochenGruppen[montag] then
        d.wochenGruppen[montag] = nil
    end
    if #liste > 0 then Anwesenheit.BuchVerteilen(liste) end
    return zahl
end

--- ⭐ Bucht die Abmeldungen und „Keine Meldung“ der Woche (für zwei Abende je Spieler, siehe oben) und verteilt sie.
--  Eine frühere Buchung derselben Woche wird zuerst zurückgenommen (so lässt sich neu buchen).
--  @return Vorschau-Tabelle (mit `gebucht`), oder nil und ein Grund
function Anwesenheit.WocheBuchen(datum, autorName)
    local autor = autorName or ichName()
    if not (ns.Gruppen and ns.Gruppen.EinteilungDarf(autor)) then
        return nil, L["Keine Berechtigung (nur Gildenränge mit Schreibrecht)."]
    end
    Anwesenheit.WocheZuruecknehmen(datum, autor)
    local v, grund = Anwesenheit.WocheVorschau(datum)
    if not v then return nil, grund end

    local d = db()
    d.zuschlaege = d.zuschlaege or {}
    local jetzt = time()

    -- Die Vorgeschichte der Spieler (ohne diese Woche, die eben zurückgenommen wurde)
    local namen = {}
    for _, n in ipairs(v.abgemeldet) do namen[#namen + 1] = { name = n, keine = false } end
    for _, n in ipairs(v.keineMeldung) do namen[#namen + 1] = { name = n, keine = true } end
    local fehl0, verg0 = {}, {}
    for _, e in ipairs(namen) do
        fehl0[e.name] = Anwesenheit.Fehlhistorie(e.name, 5)
        verg0[e.name] = Anwesenheit.VergessenHistorie(e.name, Kern.VERGESSEN_FENSTER - 1)
    end

    local ids, gebucht = {}, 0
    for i = 1, v.n do
        local id = wochenId(v.montag, i)
        local ab = d.abende[id] or {
            id = id, datum = v.montag, start = jetzt, bosse = 0, gesehen = {}, bossListe = {}, anwesenheit = {},
            teilnehmer = {}, bank = {}, unentschuldigt = {}, vergessen = {}, abgemeldet = {}, protokoll = {},
            woche = true,
        }
        ab.woche = true
        ab.buchRev = Kern.BuchRev(ab) + 1
        ab.abgeschlossen = true
        ab.ende = jetzt
        ab.abschluss = {
            zeit = jetzt, datum = v.montag, autor = autor, schnitt = v.schnitte[i], mainItems = 0,
            raidSpieler = 0, gesamtBosse = 0, spieler = {},
        }
        for _, e in ipairs(namen) do
            local k = Kern.Schluessel(e.name)
            local status, faktor, zuschlag, fehlAnzahl
            if e.keine then
                local anzahl = verg0[e.name] + i
                if anzahl > Kern.VERGESSEN_SCHWELLE then
                    status, fehlAnzahl = "vergessenStrafe", anzahl
                    faktor = Kern.FAKTOR_UNENTSCHULDIGT
                    zuschlag = Kern.ZuschlagUnentschuldigt(v.schnitte[i])
                else
                    status, fehlAnzahl = "vergessen", fehl0[e.name] + i
                    faktor = Kern.FehlFaktor(fehlAnzahl, "abgemeldet")
                    zuschlag = Kern.Zuschlag(faktor, v.schnitte[i])
                end
            else
                status, fehlAnzahl = "abgemeldet", fehl0[e.name] + i
                faktor = Kern.FehlFaktor(fehlAnzahl, "abgemeldet")
                zuschlag = Kern.Zuschlag(faktor, v.schnitte[i])
            end
            ab.abschluss.spieler[k] = {
                name = Kern.Anzeigename(e.name), status = status, faktor = faktor, schnitt = v.schnitte[i],
                zuschlag = zuschlag, fehlAnzahl = fehlAnzahl, bosse = 0, gesamt = 0, zeit = jetzt, von = autor,
            }
            if zuschlag > 0 then
                local zId = string.format("z_%s_%s", id, k)
                d.zuschlaege[zId] = {
                    id = zId, abendId = id, datum = v.montag, zeit = jetzt, spieler = Kern.Anzeigename(e.name),
                    schluessel = k, status = status, faktor = faktor, schnitt = v.schnitte[i], zuschlag = zuschlag,
                    fehlAnzahl = fehlAnzahl, autor = autor,
                }
                gebucht = gebucht + 1
            end
        end
        d.abende[id] = ab
        ids[#ids + 1] = "a:" .. id .. "@" .. ab.buchRev
    end
    Anwesenheit.BuchVerteilen(ids)
    v.gebucht = gebucht
    return v
end

--- Ist die Woche (die Pseudo-Abende <Montag>_wb1...) bereits verbindlich gebucht?
function Anwesenheit.WocheIstGebucht(datum)
    local montag = Anwesenheit.WochenTage(datum)[1]
    if not montag then return false end
    local id = wochenId(montag, 1)
    local ab = db().abende and db().abende[id]
    return (ab and ab.abgeschlossen and istWochenbuchung(ab)) and true or false
end

--- Liefert alle Gruppen, die in dieser Woche relevant sind (aktiv/eingeteilt/Raidtage/Abende).
function Anwesenheit.WochenGruppen(datum)
    local tage = Anwesenheit.WochenTage(datum)
    if #tage == 0 then return {} end
    local imTag = {}
    for _, tg in ipairs(tage) do imTag[tg] = true end
    local alleNamen = (ns.Gruppen and ns.Gruppen.Namen) and ns.Gruppen.Namen() or {}
    if #alleNamen <= 1 then
        return alleNamen
    end

    local relevant = {}
    local gefunden = false
    for _, gName in ipairs(alleNamen) do
        local hatAktivitaet = false
        local G = ns.Gruppen.Holen(gName)
        if G and G.raidtage then
            for tg, aktiv in pairs(G.raidtage) do
                if aktiv and imTag[tg] then hatAktivitaet = true; break end
            end
        end
        if not hatAktivitaet and ns.Gruppen.EinteilungListe then
            for _, tg in ipairs(tage) do
                local liste = ns.Gruppen.EinteilungListe(tg, gName)
                if liste and next(liste) then hatAktivitaet = true; break end
            end
        end
        if not hatAktivitaet then
            local gKennung = Anwesenheit.GruppenKennung(gName)
            for _, ab in pairs(db().abende or {}) do
                if ab.datum and imTag[ab.datum] and abendGruppenKennung(ab) == gKennung and not istWochenbuchung(ab) then
                    hatAktivitaet = true
                    break
                end
            end
        end
        if hatAktivitaet then
            relevant[#relevant + 1] = gName
            gefunden = true
        end
    end

    if not gefunden then
        return alleNamen
    end
    table.sort(relevant, function(a, b) return a:lower() < b:lower() end)
    return relevant
end

--- Status-Uebersicht aller relevanten Gruppen einer Woche.
function Anwesenheit.WochenGruppenUebersicht(datum)
    local montag = Anwesenheit.WochenTage(datum)[1]
    if not montag then return { gruppen = {}, gesamt = 0, bereit = 0, alleBereit = false, ausstehend = {} } end
    local gruppen = Anwesenheit.WochenGruppen(datum)
    local d = db()
    d.wochenGruppen = d.wochenGruppen or {}
    local sWoche = d.wochenGruppen[montag] or {}

    local res = { gruppen = {}, gesamt = #gruppen, bereit = 0, alleBereit = false, montag = montag, ausstehend = {} }
    for _, gName in ipairs(gruppen) do
        local info = sWoche[gName]
        local status = info and info.status or "offen"
        local istBereit = (status == "abgeschlossen" or status == "pausiert")
        if istBereit then
            res.bereit = res.bereit + 1
        else
            res.ausstehend[#res.ausstehend + 1] = gName
        end
        res.gruppen[gName] = {
            name = gName,
            status = status,
            istBereit = istBereit,
            zeit = info and info.zeit,
            autor = info and info.autor,
        }
    end
    res.alleBereit = (res.gesamt > 0 and res.bereit >= res.gesamt)
    return res
end

--- Setzt den Wochen-Status einer Gruppe ("abgeschlossen", "pausiert" oder "offen").
--  Wenn danach alle Gruppen bereit sind, wird der Wochenabschluss automatisch gebucht!
function Anwesenheit.WocheGruppeSetzen(datum, gruppe, status, autorName)
    local autor = autorName or ichName()
    if not (ns.Gruppen and ns.Gruppen.EinteilungDarf and ns.Gruppen.EinteilungDarf(autor)) then
        return nil, L["Keine Berechtigung (nur Gildenränge mit Schreibrecht)."]
    end
    local montag = Anwesenheit.WochenTage(datum)[1]
    if not montag then return nil, L["Ungültiges Datum."] end
    if not gruppe or gruppe == "" then return nil, L["Diese Gruppe gibt es nicht."] end

    local d = db()
    d.wochenGruppen = d.wochenGruppen or {}
    d.wochenGruppen[montag] = d.wochenGruppen[montag] or {}
    local jetzt = time()

    if status == "offen" then
        d.wochenGruppen[montag][gruppe] = nil
        if Anwesenheit.WocheIstGebucht(montag) then
            Anwesenheit.WocheZuruecknehmen(datum, autor)
        end
    else
        d.wochenGruppen[montag][gruppe] = { status = status, zeit = jetzt, autor = autor }
    end

    if ns.Abgleich and ns.Abgleich.Senden then
        local msg = string.format("W;%s;%s;%s;%d;%s", montag, gruppe, status, jetzt, autor)
        ns.Abgleich.Senden(msg, false, "GUILD")
    end

    local ue = Anwesenheit.WochenGruppenUebersicht(datum)
    if status == "offen" then
        print("|cff1B6B57KaosLoot|r: " .. string.format(L["Wochenabschluss für Gruppe '%s' wiedereröffnet."], gruppe))
        return true, "offen"
    end

    if ue.alleBereit then
        local v, grund = Anwesenheit.WocheBuchen(datum, autor)
        if v then
            print("|cff1B6B57KaosLoot|r: " .. string.format(L["Alle Gruppen bereit (%d/%d)! Wochenabschluss für Woche ab %s gebucht: %d Zuschläge."],
                ue.bereit, ue.gesamt, montag, v.gebucht or 0))
            return true, "gebucht", v
        else
            print("|cff1B6B57KaosLoot|r: " .. string.format(L["Alle Gruppen bereit (%d/%d), aber Buchung fehlgeschlagen: %s"],
                ue.bereit, ue.gesamt, L[grund] or tostring(grund)))
            return false, grund
        end
    else
        local ausstTxt = table.concat(ue.ausstehend, ", ")
        if status == "pausiert" then
            print("|cff1B6B57KaosLoot|r: " .. string.format(L["Gruppe '%s' pausiert diese Woche (%d von %d Gruppen bereit)."],
                gruppe, ue.bereit, ue.gesamt))
        else
            if #ue.ausstehend > 0 then
                print("|cff1B6B57KaosLoot|r: " .. string.format(L["Woche für Gruppe '%s' abgeschlossen (%d von %d Gruppen bereit). Ausstehend: %s."],
                    gruppe, ue.bereit, ue.gesamt, ausstTxt))
            else
                print("|cff1B6B57KaosLoot|r: " .. string.format(L["Woche für Gruppe '%s' abgeschlossen (%d von %d Gruppen bereit)."],
                    gruppe, ue.bereit, ue.gesamt))
            end
        end
        return true, status
    end
end

--- Empfängt die Wochenstatus-Meldung einer Gruppe über die Gilde (W;<Montag>;<Gruppe>;<Status>;<Zeit>;<Autor>).
function Anwesenheit.WochenGruppeEmpfangen(rest, sender, kanalName)
    if type(rest) ~= "string" or Kern.GleicherSpieler(sender, ichName()) then return end
    local montag, gruppe, status, zeit, autor = rest:match("^([^;]+);([^;]+);([^;]+);(%d+);([^;]*)$")
    if not montag or not gruppe or not status then return end
    if not (ns.Gruppen and ns.Gruppen.EinteilungDarf and ns.Gruppen.EinteilungDarf(sender)) then return end

    local d = db()
    d.wochenGruppen = d.wochenGruppen or {}
    d.wochenGruppen[montag] = d.wochenGruppen[montag] or {}
    if status == "offen" then
        d.wochenGruppen[montag][gruppe] = nil
    else
        d.wochenGruppen[montag][gruppe] = { status = status, zeit = tonumber(zeit) or time(), autor = autor or sender }
    end

    if ns.Fenster and ns.Fenster.Aktualisieren and ns.Fenster.Sichtbar and ns.Fenster.Sichtbar() then
        ns.Fenster.Aktualisieren()
    end
end

--- Prüft, ob der heutige (oder ein angegebener) Raidabend bereits abgeschlossen ist.
--- ⭐ Ist der Abend der AKTIVEN Gruppe abgeschlossen? Ein Abschluss einer anderen Gruppe zählt nicht (Fund
--  17.10.2026 beim Durchdenken: Nach dem Abschluss von Gruppe 1 hätte die Abwesenheit von Gruppe 2 „abgeschlossen“
--  gezeigt und nichts mehr zugelassen).
function Anwesenheit.AbendIstAbgeschlossen(datum)
    local d = db()
    local jetzt = time()
    local heute = datum or date("%Y-%m-%d", jetzt)
    local kennung = Anwesenheit.GruppenKennung(ns.Gruppen and ns.Gruppen.AktivName and ns.Gruppen.AktivName())
    local akt = d.aktiverAbend
    if akt and akt.abgeschlossen and not akt.ausgeblendet and (akt.datum == heute or akt.id == heute)
       and abendGruppenKennung(akt) == kennung then
        return true, akt
    end
    local abend = d.abende and d.abende[Anwesenheit.AbendId(heute, ns.Gruppen and ns.Gruppen.AktivName and ns.Gruppen.AktivName())]
    if abend and abend.abgeschlossen and not abend.ausgeblendet then
        return true, abend
    end
    for _, ab in pairs(d.abende or {}) do
        if ab.abgeschlossen and ab.abschluss and not ab.ausgeblendet and (jetzt - (ab.abschluss.zeit or 0) < 14 * 3600)
           and abendGruppenKennung(ab) == kennung then
            return true, ab
        end
    end
    return false, nil
end

--- ⭐ Beginnt einen neuen Abend, ohne den abgeschlossenen zurückzunehmen: Die Liste der Abwesenheit ist wieder
--  frei, die gebuchten Zuschläge und Wertungen bleiben (Wunsch 18.10.2026). Nur lokal ausgeblendet; der Abschluss
--  bleibt bei allen bestehen. „Abend wiedereröffnen“ hebt das auf.
--  @return true und der Abend, oder nil und ein Grund
function Anwesenheit.AbendNeuBeginnen(vonName)
    local autor = vonName or ichName()
    if autor ~= "System" and not Anwesenheit.DarfBankVerwalten(autor) and not Anwesenheit.DarfUnentschuldigtVerwalten(autor) then
        return nil, L["Keine Berechtigung (nur Raidleiter oder Gildenleitung)."]
    end
    local ok, ab = Anwesenheit.AbendIstAbgeschlossen()
    if not ok or not ab then return nil, L["Es gibt keinen abgeschlossenen Abend."] end
    ab.ausgeblendet = true
    local d = db()
    if d.aktiverAbend == ab then
        d.abende[ab.id] = ab
        d.aktiverAbend = nil
    end
    return true, ab
end

--- Liefert aggregierte Zuschlags- und Anhebungssummen je Spieler für Kern.Bilanz.
function Anwesenheit.ZuschlaegeDaten()
    local d = db()
    local zMap = {}
    for _, z in pairs(d.zuschlaege or {}) do
        local k = z.schluessel or Kern.Schluessel(z.spieler)
        if k then
            zMap[k] = (zMap[k] or 0) + (tonumber(z.zuschlag) or 0)
        end
    end

    local aMap = {}
    for k, a in pairs(d.anhebungen or {}) do
        local wert = (type(a) == "table" and a.wert) or tonumber(a) or 0
        aMap[k] = (aMap[k] or 0) + wert
    end
    -- Anhebungen als einzelne Saetze (verteilt zwischen den Spielern)
    for _, h in pairs(d.anhebungsliste or {}) do
        local k = h.schluessel or Kern.Schluessel(h.name)
        if k then aMap[k] = (aMap[k] or 0) + (tonumber(h.wert) or 0) end
    end

    -- Summen auf drei Stellen runden: gleiche Reihenfolge-unabhaengige Zahl auf allen Clients
    for k, v in pairs(zMap) do zMap[k] = Kern.Runde3(v) end
    for k, v in pairs(aMap) do aMap[k] = Kern.Runde3(v) end

    return { zuschlaege = zMap, anhebungen = aMap }
end

--- ⭐ Schreibt eine Anhebung als einzelnen Satz fest (§ 3, § 4) und verteilt sie.
--  @param spielerName  voller Name
--  @param wert         Punkte, um die die Wertung dauerhaft steigt (> 0)
--  @param grund        kurzer Text fuer das Spielerdetail
--  @param autor        Name dessen, der sie festschreibt
--  @param kennung      optional: feste Kennung (dann nur einmal je Kennung)
--  @return Kennung, oder nil (nichts geschrieben)
function Anwesenheit.AnhebungBuchen(spielerName, wert, grund, autor, kennung)
    local k = Kern.Schluessel(spielerName)
    wert = Kern.Runde3(wert)
    if not k or wert <= 0 then return nil end

    local d = db()
    d.anhebungsliste = d.anhebungsliste or {}
    local sauber = (k:gsub("[^%w]", "_"))
    local id = kennung or string.format("h_%s_%d_%d", sauber, time(), math.random(100, 999))
    if d.anhebungsliste[id] then return nil end

    d.anhebungsliste[id] = {
        id = id, schluessel = k, name = Kern.Anzeigename(spielerName), wert = wert,
        zeit = time(), datum = date("%Y-%m-%d"), autor = autor or ichName(),
        grund = grund or "",
    }
    Anwesenheit.BuchVerteilen({ "h:" .. id })
    return id
end

--- Niedrigste Wertung unter den Kaderspielern, die gerade im Raid sind (§ 4):
--  Gaeste und Neulinge werden darauf gesetzt. Proberaid-Spieler und Gaeste zaehlen nicht mit.
--  @param ausser  optional: dieser Spieler wird nicht mitgezaehlt
--  @return Zahl, oder nil (keine Kaderspieler im Raid)
function Anwesenheit.KaderNiedrigste(ausser)
    local namen = {}
    for _, n in ipairs(anwesendeNamen()) do
        if not (ausser and Kern.GleicherSpieler(n, ausser)) and Anwesenheit.StatusVon(n) == "kader" then
            namen[#namen + 1] = n
        end
    end
    if #namen == 0 then return nil end

    local H = (ns.Erfassung and ns.Erfassung.Historie and ns.Erfassung.Historie()) or {}
    local liste = Kern.Bilanz(H, 0, namen, namen, Anwesenheit.ZuschlaegeDaten())
    local niedrigste
    for _, e in ipairs(liste) do
        if not niedrigste or e.wertung < niedrigste then niedrigste = e.wertung end
    end
    return niedrigste
end

--- ⭐ Manuelle Anhebung (Entscheid 19.10.2026): Die Raid- oder Gildenleitung setzt einen Spieler auf den Niedrigsten
--  der ANDEREN Kaderspieler im Raid plus `Kern.ANHEBUNG_ABSTAND` (2). Nie nach unten: Liegt er schon dort oder höher,
--  passiert nichts. Wird als Satz im Datenbuch festgeschrieben und an alle verteilt.
--  @param spielerName  Name (Nachname und Realm dürfen fehlen, wenn der Spieler im Raid ist)
--  @return Kennung, Zielwertung, Anhebung — oder nil und ein Grund
function Anwesenheit.AnhebungSetzen(spielerName, vonName)
    if not Anwesenheit.DarfBankVerwalten(vonName) then
        return nil, L["Keine Berechtigung (nur Raidleiter oder Gildenleitung)."]
    end
    local name = tostring(spielerName or ""):match("^%s*(.-)%s*$")
    if name == "" then return nil, L["Kein Spielername angegeben."] end
    for _, n in ipairs(anwesendeNamen()) do
        if Kern.GleicherSpieler(n, name) then name = n break end      -- der volle Name aus dem Raid
    end
    if not Kern.Schluessel(name) then return nil, L["Ungültiger Spielername."] end

    local ref = Anwesenheit.KaderNiedrigste(name)
    if not ref then return nil, L["Zum Vergleichen fehlen andere Kaderspieler im Raid."] end

    local H = (ns.Erfassung and ns.Erfassung.Historie and ns.Erfassung.Historie()) or {}
    local liste = Kern.Bilanz(H, 0, { name }, { name }, Anwesenheit.ZuschlaegeDaten())
    local wertung = (liste[1] and liste[1].wertung) or 0
    local ziel = Kern.Runde3(ref + Kern.ANHEBUNG_ABSTAND)
    local diff = Kern.Runde3(ziel - wertung)
    if diff <= 0 then
        return nil, string.format(L["%s liegt mit %.1f schon bei oder über %.1f: keine Anhebung nötig."],
            Kern.Anzeigename(name), wertung, ziel)
    end
    local id = Anwesenheit.AnhebungBuchen(name, diff,
        string.format(L["Manuelle Anhebung auf %.1f (Niedrigster im Raid + 2)"], ziel), vonName)
    if not id then return nil, L["Die Anhebung konnte nicht gespeichert werden."] end
    return id, ziel, diff
end

--- Kennung der Auswertung eines Tages (Marker, damit sie nur einmal stattfindet).
local function auswertungsKennung(tag)
    -- ⭐ je Gruppe und Tag (zwei Gruppen am selben Tag werten ihre Anhebung getrennt aus)
    local g = Anwesenheit.GruppenKennung(ns.Gruppen and ns.Gruppen.AktivName and ns.Gruppen.AktivName())
    return g and ("hm_" .. tag .. "_" .. g) or ("hm_" .. tag)
end

--- ⭐ Anhebung (§ 3), einmal je Abend: Wer mehr als 1 Punkt unter dem Niedrigsten der ANDEREN
--  Kaderspieler im Raid liegt, wird auf deren Niedrigsten PLUS `Kern.ANHEBUNG_ABSTAND` gesetzt —
--  hinter sie, ohne sicheres Item. Das geschieht **zu Beginn des Abends** (erster Bosskampf)
--  fuer alle Kaderspieler im Raid gleichzeitig, nicht erst im Lauf der Wuerfe: Sonst muesste
--  jemand, der an diesem Abend einfach noch kein Item hatte, irgendwann nach hinten rutschen.
--  Jede Anhebung ist ein einzelner, verteilter Satz (`ha_<Spieler>_<Tag>`); `hm_<Tag>` vermerkt,
--  dass die Auswertung gelaufen ist (auch ohne Anhebung).
--  @param anwesende  optional: die Namen der Anwesenden (sonst die Gruppe)
--  @return Zahl der Angehobenen, oder nil wenn schon ausgewertet / zu wenige Kaderspieler
function Anwesenheit.AnhebungenAuswerten(anwesende)
    if not Kern.AUTO_ANHEBUNG then return nil end        -- automatische Anhebung aus (siehe Kern.AUTO_ANHEBUNG)
    local d = db()
    d.anhebungsliste = d.anhebungsliste or {}
    local tag = date("%Y%m%d")
    local marker = auswertungsKennung(tag)
    if d.anhebungsliste[marker] then return nil end

    local namen = {}
    for _, n in ipairs(anwesende or anwesendeNamen()) do
        if Anwesenheit.StatusVon(n) == "kader" then namen[#namen + 1] = n end
    end
    if #namen < 2 then return nil end      -- ohne die anderen gibt es nichts zu vergleichen

    local H = (ns.Erfassung and ns.Erfassung.Historie and ns.Erfassung.Historie()) or {}
    local liste = Kern.Bilanz(H, 0, namen, namen, Anwesenheit.ZuschlaegeDaten())

    -- Zuerst alles aus dem Stand VOR jeder Anhebung rechnen (gleichzeitig), dann buchen.
    local anheben = {}
    for _, e in ipairs(liste) do
        local ref
        for _, f in ipairs(liste) do
            if f ~= e and (not ref or f.wertung < ref) then ref = f.wertung end
        end
        if ref and (ref - e.wertung) > 1 + 1e-9 then
            anheben[#anheben + 1] = { name = e.name, ziel = Kern.Runde3(ref + Kern.ANHEBUNG_ABSTAND),
                                      diff = Kern.Runde3(ref + Kern.ANHEBUNG_ABSTAND - e.wertung) }
        end
    end

    for _, a in ipairs(anheben) do
        local k = Kern.Schluessel(a.name)
        if k then
            Anwesenheit.AnhebungBuchen(a.name, a.diff,
                string.format(L["Anhebung auf %.1f (Niedrigster im Kader + 2, § 3)"], a.ziel), nil,
                "ha_" .. (k:gsub("[^%w]", "_")) .. "_" .. tag)
        end
    end

    d.anhebungsliste[marker] = {
        id = marker, schluessel = "auswertung", name = "Auswertung", wert = 0,
        zeit = time(), datum = date("%Y-%m-%d"), autor = ichName(), grund = "",
    }
    Anwesenheit.BuchVerteilen({ "h:" .. marker })
    return #anheben
end

--- ⭐ Ordnet die Wuerfler einer Liste (Kern.Bilanz) den Regeln fuer Proberaid, Neulinge,
--  Gaeste und die Anhebung zu (§ 3, § 4):
--    * Proberaid (1. Abend):   keine Lootberechtigung  -> `proberaid`
--    * Neuling (2. Abend):     Wertung = Niedrigster der Kaderspieler im Raid + 2 -> `neuling`
--                              (wie die Anhebung, Gildenleitung 17.10.2026); mit `festschreiben`
--                              wird das einmalig als Anhebung gebucht
--    * Gast:                   Wertung fuer den Abend = Niedrigster der Kaderspieler -> `gast`
--    * Kaderspieler:           ist die Anhebung des Tages schon ausgewertet, steht sie in der
--                              Wertung und es gibt keine weitere (`keineAnhebung`, `hebung` = heutiger
--                              Zuschlag zur Anzeige). Sonst gilt `referenz` = Niedrigster der
--                              ANDEREN Kaderspieler im Raid; Kern.WurfReihenfolge zeigt die Anhebung
--                              dann vorab. Mit `festschreiben` wird die Auswertung jetzt nachgeholt.
--  @param festschreiben  true nur beim Starter eines Wurfs (er verteilt, was zu verteilen ist)
function Anwesenheit.Rollen(liste, festschreiben)
    local d = db()
    local tag = date("%Y%m%d")
    local ausgewertet = d.anhebungsliste and d.anhebungsliste[auswertungsKennung(tag)]

    -- Hat der Aufzeichner die Auswertung zu Abendbeginn verpasst, holt sie der Starter nach.
    local frisch = false
    if festschreiben and not ausgewertet then
        Anwesenheit.AnhebungenAuswerten()
        ausgewertet = d.anhebungsliste and d.anhebungsliste[auswertungsKennung(tag)]
        frisch = ausgewertet and true or false   -- die uebergebene Liste kennt die neuen Anhebungen noch nicht
    end

    -- Die Kaderspieler im Raid: niedrigste und zweitniedrigste Wertung (zweitniedrigste = „ohne ihn selbst")
    local kader = {}
    for _, n in ipairs(anwesendeNamen()) do
        if Anwesenheit.StatusVon(n) == "kader" then kader[#kader + 1] = n end
    end
    local min1, name1, min2
    if #kader > 0 then
        local H = (ns.Erfassung and ns.Erfassung.Historie and ns.Erfassung.Historie()) or {}
        for _, e in ipairs(Kern.Bilanz(H, 0, kader, kader, Anwesenheit.ZuschlaegeDaten())) do
            if not min1 or e.wertung < min1 then
                min2 = min1
                min1, name1 = e.wertung, e.name
            elseif not min2 or e.wertung < min2 then
                min2 = e.wertung
            end
        end
    end

    for _, e in ipairs(liste or {}) do
        local status = Anwesenheit.StatusVon(e.name)
        local k = Kern.Schluessel(e.name)
        if status == "proberaid" then
            e.proberaid = true
        elseif status == "gast" then
            if min1 then e.gast = true; e.wertung = min1 end
        elseif status == "neuling" then
            -- Der Start wird nur EINMAL gesetzt (feste Kennung je Spieler). Danach gilt er
            -- als ganz normaler Kaderspieler mit seiner Wertung.
            local kennung = k and ("hn_" .. (k:gsub("[^%w]", "_")))
            local schonDa = kennung and d.anhebungsliste and d.anhebungsliste[kennung]
            if min1 and not schonDa then
                local ziel = Kern.Runde3(min1 + Kern.ANHEBUNG_ABSTAND)
                e.neuling = true
                e.neulingZiel = ziel
                if festschreiben and (ziel - e.wertung) > 1e-9 then
                    local diff = Kern.Runde3(ziel - e.wertung)
                    local id = Anwesenheit.AnhebungBuchen(e.name, diff,
                        L["2. Raidabend: Niedrigster im Kader + 2 (§ 4)"], nil, kennung)
                    if id then
                        e.anhebung = (e.anhebung or 0) + diff
                        e.wertung = Kern.Wertung(e.haupt, e.zuschlag, e.anhebung)
                        e.neuling = nil
                        e.neulingZiel = nil
                    end
                end
            end
        elseif status == "kader" then
            if ausgewertet then
                e.keineAnhebung = true
                local h = k and d.anhebungsliste and d.anhebungsliste["ha_" .. (k:gsub("[^%w]", "_")) .. "_" .. tag]
                if h then
                    e.hebung = tonumber(h.wert) or 0
                    if frisch then
                        e.anhebung = (e.anhebung or 0) + e.hebung
                        e.wertung = Kern.Wertung(e.haupt, e.zuschlag, e.anhebung)
                    end
                end
            else
                local ref = (name1 and Kern.GleicherSpieler(name1, e.name)) and min2 or min1
                if ref then e.referenz = ref end
            end
        end
    end
    return liste
end

--- Liefert die chronologische Aufschlüsselung aller Ereignisse eines Spielers (§ 1, § 2, § 3).
--  Kombiniert Items, Zuschläge, Bank-Teilnahmen und Anhebungen.
--  @return ereignisse, summeHaupt, summeZweit, summeZuschlaege, summeAnhebung, wertung
function Anwesenheit.SpielerEreignisse(spielerName, abend, historie, seit, istBeispiel)
    if not spielerName then return {}, 0, 0, 0, 0, 0 end
    local k = Kern.Schluessel(spielerName)
    if not k then return {}, 0, 0, 0, 0, 0 end

    local liste = {}
    local haupt, zweit, sumZuschlaege, sumAnhebungen = 0, 0, 0, 0

    if istBeispiel then
        local t = time()
        local TAG = Kern.TAG

        -- Beispiel-Ereignisse je nach Spieler
        if k == "deters" then
            liste[#liste + 1] = {
                zeit     = t - 2 * TAG,
                art      = "abgemeldet",
                punkte   = 1.0,
                text     = string.format(L["Zuschlag +1,0 (2. Fehlen, Faktor 1,0 × Schnitt 1,0)"]),
                isItem   = false,
            }
            liste[#liste + 1] = {
                zeit     = t - 9 * TAG,
                art      = "abgemeldet",
                punkte   = 0.7,
                text     = string.format(L["Zuschlag +0,7 (1. Fehlen, Faktor 0,7 × Schnitt 1,0)"]),
                isItem   = false,
            }
            sumZuschlaege = 1.7
        elseif k == "lupitus" then
            liste[#liste + 1] = {
                zeit     = t - 3 * TAG,
                art      = "unentschuldigt",
                punkte   = 2.0,
                text     = string.format(L["Zuschlag +2,0 (Unentschuldigt, mindestens 2 Punkte; Faktor 1,5 × Schnitt 1,0)"]),
                isItem   = false,
            }
            sumZuschlaege = 2.0
        elseif k == "canu" then
            liste[#liste + 1] = {
                zeit     = t - 4 * TAG,
                art      = "bank",
                punkte   = 0.0,
                text     = string.format(L["Bank (Faktor 0, von Kaos)"]),
                isItem   = false,
            }
        elseif k == "nuhkomm" then
            liste[#liste + 1] = {
                zeit     = t - 5 * TAG,
                art      = "anhebung",
                punkte   = 1.0,
                text     = string.format(L["Anhebung auf 1,0 (1 Punkt unter dem Niedrigsten, § 3)"]),
                isItem   = false,
            }
            sumAnhebungen = 1.0
        end

        local items = Kern.Spieler(historie, spielerName, seit)
        for _, it in ipairs(items) do
            if it.zweit then
                zweit = zweit + 1
            else
                haupt = haupt + 1
            end
            liste[#liste + 1] = {
                id       = it.id,
                zeit     = it.zeit,
                art      = it.zweit and "zweit" or "haupt",
                punkte   = it.zweit and 0 or 1.0,
                text     = (ns.Quelle and ns.Quelle.Gegenstandstext) and ns.Quelle.Gegenstandstext(it.eintrag) or L["Gegenstand"],
                eintrag  = it.eintrag,
                isItem   = true,
            }
        end
    else
        -- 1. Vergebene Gegenstände
        local items = Kern.Spieler(historie, spielerName, seit)
        for _, it in ipairs(items) do
            if it.zweit then
                zweit = zweit + 1
            else
                haupt = haupt + 1
            end
            liste[#liste + 1] = {
                id       = it.id,
                zeit     = it.zeit,
                art      = it.zweit and "zweit" or "haupt",
                punkte   = it.zweit and 0 or 1.0,
                text     = (ns.Quelle and ns.Quelle.Gegenstandstext) and ns.Quelle.Gegenstandstext(it.eintrag) or L["Gegenstand"],
                eintrag  = it.eintrag,
                isItem   = true,
            }
        end

        -- 2. Festgeschriebene Zuschläge
        local d = db()
        for _, z in pairs(d.zuschlaege or {}) do
            if Kern.Schluessel(z.spieler) == k and (not seit or z.zeit >= seit) then
                sumZuschlaege = sumZuschlaege + (z.zuschlag or 0)
                local txt
                if z.status == "vergessenStrafe" then
                    txt = string.format(L["Zuschlag +%.1f (Anmeldung vergessen, %d. Mal in 8 Abenden: wie unentschuldigt, Faktor %.1f, mindestens 2 Punkte)"],
                        z.zuschlag, z.fehlAnzahl or 3, z.faktor)
                elseif z.status == "vergessen" then
                    txt = string.format(L["Zuschlag +%.1f (Anmeldung vergessen, %d. Fehlen, Faktor %.1f × Schnitt %.1f)"],
                        z.zuschlag, z.fehlAnzahl or 1, z.faktor, z.schnitt)
                elseif z.status == "unentschuldigt" then
                    -- Hat das Minimum (2 Punkte) gegriffen, steht es dabei; sonst die einfache Rechnung
                    if (tonumber(z.zuschlag) or 0) > Kern.Runde3((tonumber(z.faktor) or 0) * (tonumber(z.schnitt) or 0)) + 1e-9 then
                        txt = string.format(L["Zuschlag +%.1f (Unentschuldigt, mindestens 2 Punkte; Faktor %.1f × Schnitt %.1f)"],
                            z.zuschlag, z.faktor, z.schnitt)
                    else
                        txt = string.format(L["Zuschlag +%.1f (Unentschuldigt, Faktor %.1f × Schnitt %.1f)"],
                            z.zuschlag, z.faktor, z.schnitt)
                    end
                else
                    txt = string.format(L["Zuschlag +%.1f (%d. Fehlen, Faktor %.1f × Schnitt %.1f)"],
                        z.zuschlag, z.fehlAnzahl or 1, z.faktor, z.schnitt)
                end
                liste[#liste + 1] = {
                    id       = z.id,
                    zeit     = z.zeit,
                    art      = z.status or "abgemeldet",
                    punkte   = z.zuschlag or 0,
                    text     = txt,
                    isItem   = false,
                }
            end
        end

        -- 3. Anhebungen
        for ak, an in pairs(d.anhebungen or {}) do
            if ak == k then
                local wert = (type(an) == "table" and an.wert) or tonumber(an) or 0
                local zt = (type(an) == "table" and an.zeit) or time()
                local gr = (type(an) == "table" and an.grund) or string.format(L["Anhebung auf 1 Punkt unter dem Niedrigsten (§ 3)"])
                if not seit or zt >= seit then
                    sumAnhebungen = sumAnhebungen + wert
                    liste[#liste + 1] = {
                        id       = "anhebung_" .. k,
                        zeit     = zt,
                        art      = "anhebung",
                        punkte   = wert,
                        text     = gr,
                        isItem   = false,
                    }
                end
            end
        end

        for _, h in pairs(d.anhebungsliste or {}) do
            if (h.schluessel or Kern.Schluessel(h.name)) == k and (not seit or (h.zeit or 0) >= seit) then
                sumAnhebungen = sumAnhebungen + (tonumber(h.wert) or 0)
                liste[#liste + 1] = {
                    id       = h.id,
                    zeit     = h.zeit or time(),
                    art      = "anhebung",
                    punkte   = tonumber(h.wert) or 0,
                    text     = (h.grund and h.grund ~= "") and h.grund or L["Anhebung auf 1 Punkt unter dem Niedrigsten (§ 3)"],
                    isItem   = false,
                }
            end
        end

        -- 4. Archivierte Bank-Einträge (Faktor 0)
        for _, ab in pairs(d.abende or {}) do
            if ab.abschluss and ab.abschluss.spieler and ab.abschluss.spieler[k] then
                local sp = ab.abschluss.spieler[k]
                if sp.status == "bank" and (not seit or ab.abschluss.zeit >= seit) then
                    liste[#liste + 1] = {
                        id       = "bank_" .. ab.id .. "_" .. k,
                        zeit     = ab.abschluss.zeit,
                        art      = "bank",
                        punkte   = 0.0,
                        text     = string.format(L["Bank (Faktor 0, von %s)"], sp.von or "?"),
                        isItem   = false,
                    }
                end
            end
        end
    end

    table.sort(liste, function(a, b)
        if a.zeit ~= b.zeit then return a.zeit > b.zeit end
        return (a.id or "") < (b.id or "")
    end)

    local wertung = Kern.Wertung(haupt, sumZuschlaege, sumAnhebungen)
    return liste, haupt, zweit, sumZuschlaege, sumAnhebungen, wertung
end

-- =====================================================================
--  Demo-Daten (fuer /kl demo)
-- =====================================================================

local beispielBankState = nil

--- Liefert interaktive Beispiel-Kandidaten für /kl demo.
function Anwesenheit.BeispielKandidaten()
    if not beispielBankState then
        local t = time()
        beispielBankState = {
            canu     = { name = "Canu", online = true, bank = { name = "Canu", von = "Kaos", zeit = t - 1800 }, unentschuldigt = nil, protokoll = string.format(L["Bank: %s, %s"], "Kaos", date(L["%d.%m. %H:%M"], t - 1800)) },
            shadow   = { name = "Shadow", online = true, bank = nil, unentschuldigt = nil, protokoll = "" },
            deters   = { name = "Deters", online = false, bank = nil, unentschuldigt = { name = "Deters", von = "Kaos", zeit = t - 900 }, protokoll = string.format(L["Unentschuldigt: %s, %s"], "Kaos", date(L["%d.%m. %H:%M"], t - 900)) },
            simondan = { name = "Simondan", online = false, bank = nil, unentschuldigt = nil, protokoll = "" },
            protti   = { name = "Protti", online = true, bank = nil, unentschuldigt = nil, protokoll = "" },
        }
    end

    local liste = {}
    for _, k in ipairs({ "canu", "shadow", "deters", "simondan", "protti" }) do
        liste[#liste + 1] = beispielBankState[k]
    end
    return liste
end

--- Toggelt Bank im Demo-Modus.
function Anwesenheit.BeispielBankToggle(name)
    local k = Kern.Schluessel(name)
    Anwesenheit.BeispielKandidaten()
    local e = beispielBankState and beispielBankState[k]
    if not e then return end
    local t = time()
    if e.bank then
        e.bank = nil
        e.protokoll = ""
    else
        e.bank = { name = e.name, von = "Kaos", zeit = t }
        e.unentschuldigt = nil
        e.protokoll = string.format(L["Bank: %s, %s"], "Kaos", date(L["%d.%m. %H:%M"], t))
    end
end

--- Toggelt Unentschuldigt im Demo-Modus.
function Anwesenheit.BeispielUnentToggle(name)
    local k = Kern.Schluessel(name)
    Anwesenheit.BeispielKandidaten()
    local e = beispielBankState and beispielBankState[k]
    if not e then return end
    local t = time()
    if e.unentschuldigt then
        e.unentschuldigt = nil
        e.protokoll = ""
    else
        e.unentschuldigt = { name = e.name, von = "Kaos", zeit = t }
        e.bank = nil
        e.protokoll = string.format(L["Unentschuldigt: %s, %s"], "Kaos", date(L["%d.%m. %H:%M"], t))
    end
end

--- Toggelt Abgemeldet im Demo-Modus.
function Anwesenheit.BeispielAbmeldToggle(name)
    local k = Kern.Schluessel(name)
    Anwesenheit.BeispielKandidaten()
    local e = beispielBankState and beispielBankState[k]
    if not e then return end
    local t = time()
    if e.abgemeldet then
        e.abgemeldet = nil
        e.protokoll = ""
    else
        e.abgemeldet = { name = e.name, von = "Kaos", zeit = t }
        e.bank = nil
        e.unentschuldigt = nil
        e.protokoll = string.format(L["Abgemeldet: %s, %s"], "Kaos", date(L["%d.%m. %H:%M"], t))
    end
end

--- Setzt die interaktiven Demo-Kandidaten zurück (alle Haken entfernt).
function Anwesenheit.BeispielKandidatenReset()
    beispielBankState = {
        canu     = { name = "Canu", online = true, bank = nil, unentschuldigt = nil, protokoll = "" },
        shadow   = { name = "Shadow", online = true, bank = nil, unentschuldigt = nil, protokoll = "" },
        deters   = { name = "Deters", online = false, bank = nil, unentschuldigt = nil, protokoll = "" },
        simondan = { name = "Simondan", online = false, bank = nil, unentschuldigt = nil, protokoll = "" },
        protti   = { name = "Protti", online = true, bank = nil, unentschuldigt = nil, protokoll = "" },
    }
end

--- Stellt die ursprünglichen Demo-Kandidaten wieder her (Canu Bank, Deters Unent).
function Anwesenheit.BeispielKandidatenWiederherstellen()
    local t = time()
    beispielBankState = {
        canu     = { name = "Canu", online = true, bank = { name = "Canu", von = "Kaos", zeit = t - 1800 }, unentschuldigt = nil, protokoll = string.format(L["Bank: %s, %s"], "Kaos", date(L["%d.%m. %H:%M"], t - 1800)) },
        shadow   = { name = "Shadow", online = true, bank = nil, unentschuldigt = nil, protokoll = "" },
        deters   = { name = "Deters", online = false, bank = nil, unentschuldigt = { name = "Deters", von = "Kaos", zeit = t - 900 }, protokoll = string.format(L["Unentschuldigt: %s, %s"], "Kaos", date(L["%d.%m. %H:%M"], t - 900)) },
        simondan = { name = "Simondan", online = false, bank = nil, unentschuldigt = nil, protokoll = "" },
        protti   = { name = "Protti", online = true, bank = nil, unentschuldigt = nil, protokoll = "" },
    }
end

--- Liefert Beispiel-Anwesenheitsdaten fuer die Demo.
function Anwesenheit.BeispielInfo(name)
    local k = Kern.Schluessel(name)
    local t = time()
    if k == "kaosx" then
        return { bosse = 10, gesamt = 10, quote = 1.0, prozent = 100, imRaid = true, status = "kader" }
    elseif k == "nuhkomm" then
        return { bosse = 10, gesamt = 10, quote = 1.0, prozent = 100, imRaid = true, status = "proberaid" }
    elseif k == "deters" then
        return { bosse = 5, gesamt = 10, quote = 0.5, prozent = 50, imRaid = true, status = "kader", unentschuldigt = true, unentEintrag = { name = "Deters", von = "Kaos", zeit = t - 900 } }
    elseif k == "canu" then
        return { bosse = 0, gesamt = 10, quote = 0.0, prozent = 0, imRaid = false, status = "kader", bank = true, bankEintrag = { name = "Canu", von = "Kaos", zeit = t - 1800 } }
    elseif k == "velera" then
        return { bosse = 8, gesamt = 10, quote = 0.8, prozent = 80, imRaid = true, status = "gast" }
    elseif k == "pflasterelfe" then
        return { bosse = 10, gesamt = 10, quote = 1.0, prozent = 100, imRaid = true, status = "kader" }
    end
    return { bosse = 10, gesamt = 10, quote = 1.0, prozent = 100, imRaid = true, status = "kader" }
end

-- =====================================================================
--  Probe-Modus (Übungsmodus)
-- =====================================================================

local Probe = {}
ns.Probe = Probe

local probeAktiv = false
local probeDB = nil
local probeHist = nil
local probeHistList = nil
local probeRaidList = nil
local probeBackups = nil
local probeGesendet = 0

local PROBE_ROSTER = {
    "Anna", "Ben", "Chris", "David", "Elena", "Frank", "Greta", "Hanna",
    "Igor", "Jonas", "Kevin", "Lisa", "Max", "Nora"
}

local function baueProbeDB()
    local t = time()
    local raid10 = { "Anna", "Ben", "Chris", "David", "Elena", "Frank", "Greta", "Hanna", "Igor", "Jonas" }
    local d = {
        abende = {},
        zuschlaege = {},
        anhebungen = {},
        anhebungsliste = {},
        aktiverAbend = {
            id = "probe_abend",
            datum = date("%Y-%m-%d", t),
            gruppe = "Probe",
            start = t - 3600,
            ende = t + 7200,
            bosse = 1,
            bossListe = {
                { name = "Probeboss", nummer = 9991, sieg = true, anwesende = raid10 }
            },
            teilnehmer = {
                anna  = { name = "Anna", status = "kader", bosse = 1 },
                ben   = { name = "Ben", status = "kader", bosse = 1 },
                chris = { name = "Chris", status = "kader", bosse = 1 },
                david = { name = "David", status = "kader", bosse = 1 },
                elena = { name = "Elena", status = "kader", bosse = 1 },
                frank = { name = "Frank", status = "kader", bosse = 1 },
                greta = { name = "Greta", status = "kader", bosse = 1 },
                hanna = { name = "Hanna", status = "kader", bosse = 1 },
                igor  = { name = "Igor", status = "proberaid", bosse = 1 },
                jonas = { name = "Jonas", status = "neuling", bosse = 1 },
                kevin = { name = "Kevin", status = "kader", bosse = 0 },
                lisa  = { name = "Lisa", status = "kader", bosse = 0 },
                max   = { name = "Max", status = "kader", bosse = 0 },
                nora  = { name = "Nora", status = "kader", bosse = 0 },
            },
            anwesenheit = {
                anna = 1, ben = 1, chris = 1, david = 1, elena = 1,
                frank = 1, greta = 1, hanna = 1, igor = 1, jonas = 1,
            },
            bank = {
                nora = { name = "Nora", von = "ProbeLeiter" },
            },
            unentschuldigt = {},
            abgemeldet = {
                kevin = { name = "Kevin", von = "ProbeLeiter", zeit = t },
                lisa  = { name = "Lisa", von = "ProbeLeiter", zeit = t },
            },
            vergessen = {
                max = { name = "Max", von = "ProbeLeiter", zeit = t },
            },
            protokoll = {},
        }
    }

    -- Historischer Abend 1: Die 12 Gruender (Anna..Hanna, Kevin, Lisa, Max, Nora)
    d.abende["archiv_1"] = {
        id = "archiv_1",
        datum = date("%Y-%m-%d", t - 14 * 86400),
        abgeschlossen = true,
        buchRev = 1,
        abschluss = {
            zeit = t - 14 * 86400,
            datum = date("%Y-%m-%d", t - 14 * 86400),
            autor = "Kaos",
            schnitt = 1.0,
            mainItems = 10,
            raidSpieler = 10,
            gesamtBosse = 1,
            spieler = {
                anna  = { name = "Anna", status = "imRaid", zuschlag = 0 },
                ben   = { name = "Ben", status = "imRaid", zuschlag = 0 },
                chris = { name = "Chris", status = "imRaid", zuschlag = 0 },
                david = { name = "David", status = "imRaid", zuschlag = 0 },
                elena = { name = "Elena", status = "imRaid", zuschlag = 0 },
                frank = { name = "Frank", status = "imRaid", zuschlag = 0 },
                greta = { name = "Greta", status = "imRaid", zuschlag = 0 },
                hanna = { name = "Hanna", status = "imRaid", zuschlag = 0 },
                kevin = { name = "Kevin", status = "imRaid", zuschlag = 0 },
                lisa  = { name = "Lisa", status = "imRaid", zuschlag = 0 },
                max   = { name = "Max", status = "imRaid", zuschlag = 0 },
                nora  = { name = "Nora", status = "imRaid", zuschlag = 0 },
            }
        }
    }

    -- Historischer Abend 2: Jonas kam vor 7 Tagen neu zum Kader (1. Abend = Proberaid)
    d.abende["archiv_2"] = {
        id = "archiv_2",
        datum = date("%Y-%m-%d", t - 7 * 86400),
        abgeschlossen = true,
        buchRev = 1,
        abschluss = {
            zeit = t - 7 * 86400,
            datum = date("%Y-%m-%d", t - 7 * 86400),
            autor = "Kaos",
            schnitt = 1.0,
            mainItems = 5,
            raidSpieler = 5,
            gesamtBosse = 1,
            spieler = {
                anna  = { name = "Anna", status = "imRaid", zuschlag = 0 },
                ben   = { name = "Ben", status = "imRaid", zuschlag = 0 },
                chris = { name = "Chris", status = "imRaid", zuschlag = 0 },
                david = { name = "David", status = "imRaid", zuschlag = 0 },
                jonas = { name = "Jonas", status = "imRaid", zuschlag = 0 },
            }
        }
    }

    return d
end

function Probe.Aktiv()
    return probeAktiv and true or false
end

function Probe.Roster()
    return PROBE_ROSTER
end

function Probe.Historie()
    return probeHist or {}
end

function Probe.Starten()
    if probeAktiv then return true end

    probeBackups = {
        dbOverride = dbOverride,
        anwesendeOverride = anwesendeOverride,

        konfigDarf = ns.Konfig and ns.Konfig.Darf,
        konfigSenden = ns.Konfig and ns.Konfig.Senden,
        konfigAutoSenden = ns.Konfig and ns.Konfig.AutoSenden,

        rolleBerechtigt = ns.Rolle and ns.Rolle.Berechtigt,
        rolleIchSchreibe = ns.Rolle and ns.Rolle.IchSchreibe,

        erfassungHistorie = ns.Erfassung and ns.Erfassung.Historie,
        erfassungDarf = ns.Erfassung and ns.Erfassung.DarfZuruecknehmen,

        gruppenPflicht = ns.Gruppen and ns.Gruppen.Pflicht,
        gruppenEinteilungVorhanden = ns.Gruppen and ns.Gruppen.EinteilungVorhanden,
        gruppenEinteilungListe = ns.Gruppen and ns.Gruppen.EinteilungListe,
        gruppenBenchListe = ns.Gruppen and ns.Gruppen.BenchListe,
        gruppenAktivName = ns.Gruppen and ns.Gruppen.AktivName,
        gruppenGildenMitglieder = ns.Gruppen and ns.Gruppen.GildenMitglieder,
        gruppenEinteilungDarf = ns.Gruppen and ns.Gruppen.EinteilungDarf,

        abgleichSenden = ns.Abgleich and ns.Abgleich.Senden,
        abgleichBuchVerteilen = ns.Abgleich and ns.Abgleich.BuchVerteilen,
        abgleichVerteilen = ns.Abgleich and ns.Abgleich.Verteilen,
        abgleichLeitungBeacon = ns.Abgleich and ns.Abgleich.LeitungBeacon,
        abgleichLeitungBeaconSpaeter = ns.Abgleich and ns.Abgleich.LeitungBeaconSpaeter,
        anwBuchVerteilen = Anwesenheit.BuchVerteilen,
    }

    probeGesendet = 0
    local blockFn = function() probeGesendet = probeGesendet + 1 end

    if ns.Abgleich then
        ns.Abgleich.Senden = blockFn
        ns.Abgleich.BuchVerteilen = blockFn
        ns.Abgleich.Verteilen = blockFn
        ns.Abgleich.LeitungBeacon = blockFn
        ns.Abgleich.LeitungBeaconSpaeter = blockFn
        if ns.Abgleich.WarteschlangeLeeren then ns.Abgleich.WarteschlangeLeeren() end
    end
    Anwesenheit.BuchVerteilen = blockFn
    if ns.Konfig then
        ns.Konfig.Senden = blockFn
        ns.Konfig.AutoSenden = blockFn
    end

    ns.Konfig = ns.Konfig or {}
    ns.Konfig.Darf = function() return true end
    ns.Rolle = ns.Rolle or {}
    ns.Rolle.Berechtigt = function() return true end
    ns.Rolle.IchSchreibe = function() return true, "probe" end

    ns.Gruppen = ns.Gruppen or {}
    ns.Gruppen.AktivName = function() return "Probe" end
    ns.Gruppen.EinteilungVorhanden = function() return true end
    ns.Gruppen.EinteilungListe = function() return PROBE_ROSTER end
    ns.Gruppen.BenchListe = function()
        local abend = Anwesenheit.AktiverAbend(false)
        local bench = {}
        for k, b in pairs((abend and abend.bank) or {}) do
            bench[#bench + 1] = b.name or k
        end
        return bench
    end
    ns.Gruppen.Pflicht = function() return PROBE_ROSTER end
    ns.Gruppen.GildenMitglieder = function()
        return {
            anna  = { name = "Anna", online = true },
            ben   = { name = "Ben", online = true },
            chris = { name = "Chris", online = true },
            david = { name = "David", online = true },
            elena = { name = "Elena", online = true },
            frank = { name = "Frank", online = true },
            greta = { name = "Greta", online = true },
            hanna = { name = "Hanna", online = true },
            igor  = { name = "Igor", online = true },
            jonas = { name = "Jonas", online = true },
            kevin = { name = "Kevin", online = false },
            lisa  = { name = "Lisa", online = false },
            max   = { name = "Max", online = false },
            nora  = { name = "Nora", online = true },
        }
    end
    ns.Gruppen.EinteilungDarf = function() return true end

    probeDB = baueProbeDB()
    probeHist = {}
    probeHistList = {}
    probeRaidList = { "Anna", "Ben", "Chris", "David", "Elena", "Frank", "Greta", "Hanna", "Igor", "Jonas" }

    ns.Erfassung = ns.Erfassung or {}
    ns.Erfassung.Historie = function() return probeHist end
    ns.Erfassung.DarfZuruecknehmen = function() return true end

    Anwesenheit._SetDB(probeDB)
    Anwesenheit._SetAnwesende(probeRaidList)

    probeAktiv = true
    return true
end

function Probe.Beenden()
    if not probeAktiv then return end

    Anwesenheit.AbendZuruecksetzen()
    Anwesenheit._SetAnwesende(probeBackups and probeBackups.anwesendeOverride)
    Anwesenheit._SetDB(probeBackups and probeBackups.dbOverride)

    if probeBackups then
        if ns.Konfig then
            ns.Konfig.Darf = probeBackups.konfigDarf
            ns.Konfig.Senden = probeBackups.konfigSenden
            ns.Konfig.AutoSenden = probeBackups.konfigAutoSenden
        end
        if ns.Rolle then
            ns.Rolle.Berechtigt = probeBackups.rolleBerechtigt
            ns.Rolle.IchSchreibe = probeBackups.rolleIchSchreibe
        end
        if ns.Erfassung then
            ns.Erfassung.Historie = probeBackups.erfassungHistorie
            ns.Erfassung.DarfZuruecknehmen = probeBackups.erfassungDarf
        end
        if ns.Gruppen then
            ns.Gruppen.Pflicht = probeBackups.gruppenPflicht
            ns.Gruppen.EinteilungVorhanden = probeBackups.gruppenEinteilungVorhanden
            ns.Gruppen.EinteilungListe = probeBackups.gruppenEinteilungListe
            ns.Gruppen.BenchListe = probeBackups.gruppenBenchListe
            ns.Gruppen.AktivName = probeBackups.gruppenAktivName
            ns.Gruppen.GildenMitglieder = probeBackups.gruppenGildenMitglieder
            ns.Gruppen.EinteilungDarf = probeBackups.gruppenEinteilungDarf
        end
        if ns.Abgleich then
            ns.Abgleich.Senden = probeBackups.abgleichSenden
            ns.Abgleich.BuchVerteilen = probeBackups.abgleichBuchVerteilen
            ns.Abgleich.Verteilen = probeBackups.abgleichVerteilen
            ns.Abgleich.LeitungBeacon = probeBackups.abgleichLeitungBeacon
            ns.Abgleich.LeitungBeaconSpaeter = probeBackups.abgleichLeitungBeaconSpaeter
        end
        if ns.Abgleich and ns.Abgleich.WarteschlangeLeeren then
            ns.Abgleich.WarteschlangeLeeren()
        end
        Anwesenheit.BuchVerteilen = probeBackups.anwBuchVerteilen
    end

    probeDB = nil
    probeHist = nil
    probeHistList = nil
    probeRaidList = nil
    probeBackups = nil
    probeAktiv = false
end

function Probe.Zuruecksetzen()
    if not probeAktiv then return end
    probeDB = baueProbeDB()
    probeHist = {}
    probeHistList = {}
    probeRaidList = { "Anna", "Ben", "Chris", "David", "Elena", "Frank", "Greta", "Hanna", "Igor", "Jonas" }
    Anwesenheit._SetDB(probeDB)
    Anwesenheit._SetAnwesende(probeRaidList)
    local abend = Anwesenheit.AktiverAbend(true)
    abend.gruppe = "Probe"
    abend.bosse = 1
    abend.bossListe = {
        { name = "Probeboss", nummer = 9991, sieg = true, anwesende = probeRaidList }
    }
end

function Probe.IstImRaid(name)
    local kTarget = Kern.Schluessel(name)
    for _, n in ipairs(probeRaidList or {}) do
        if Kern.Schluessel(n) == kTarget then return true end
    end
    return false
end

function Probe.SetzeRaid(name, imRaid)
    if not probeAktiv then return false end
    local kTarget = Kern.Schluessel(name)
    if not kTarget then return false end
    local gefunden = false
    for i, n in ipairs(probeRaidList) do
        if Kern.Schluessel(n) == kTarget then
            gefunden = true
            if not imRaid then
                table.remove(probeRaidList, i)
            end
            break
        end
    end
    if imRaid and not gefunden then
        table.insert(probeRaidList, Kern.Anzeigename(name))
    end
    Anwesenheit._SetAnwesende(probeRaidList)

    local abend = Anwesenheit.AktiverAbend(false)
    if abend then
        if imRaid then
            if abend.bank then abend.bank[kTarget] = nil end
            if abend.unentschuldigt then abend.unentschuldigt[kTarget] = nil end
            if abend.abgemeldet then abend.abgemeldet[kTarget] = nil end
            if abend.vergessen then abend.vergessen[kTarget] = nil end
        end
        if abend.bossListe and #abend.bossListe > 0 then
            abend.bossListe[#abend.bossListe].anwesende = probeRaidList
        end
    end
    return true
end

function Probe.ToggleRaid(name)
    local ist = Probe.IstImRaid(name)
    return Probe.SetzeRaid(name, not ist)
end

function Probe.SetzeBank(name, an)
    if not probeAktiv then return false end
    if an then
        Probe.SetzeRaid(name, false)
        return Anwesenheit.BankSetzen(name, true, "ProbeLeiter")
    else
        Anwesenheit.BankSetzen(name, false, "ProbeLeiter")
        return Probe.SetzeRaid(name, true)
    end
end

function Probe.SetzeUnentschuldigt(name, an)
    if not probeAktiv then return false end
    if an then
        Probe.SetzeRaid(name, false)
        return Anwesenheit.UnentschuldigtSetzen(name, true, "ProbeLeiter")
    else
        Anwesenheit.UnentschuldigtSetzen(name, false, "ProbeLeiter")
        return Probe.SetzeRaid(name, true)
    end
end

function Probe.SetzeAbgemeldet(name, an)
    if not probeAktiv then return false end
    if an then
        Probe.SetzeRaid(name, false)
        return Anwesenheit.AbmeldungSetzen(name, true, "ProbeLeiter")
    else
        Anwesenheit.AbmeldungSetzen(name, false, "ProbeLeiter")
        return Probe.SetzeRaid(name, true)
    end
end

function Probe.SetzeKeineMeldung(name, an)
    if not probeAktiv then return false end
    if an then Probe.SetzeRaid(name, false) end
    return Anwesenheit.VergessenSetzen(name, an, "ProbeLeiter")
end

function Probe.VergebeItem(name, istOS, itemID, itemLink)
    if not probeAktiv then return false end
    name = Kern.Anzeigename(name)
    local t = time()
    local nr = #probeHistList + 1
    local id = "probe_item_" .. tostring(nr)
    local item = {
        id        = id,
        awardedTo = name,
        itemID    = itemID or (istOS and 32235 or 32505),
        itemLink  = itemLink or nil,
        timestamp = t,
        OS        = istOS and true or false,
        herkunft  = "probe",
        gruppe    = "Probe",
    }
    probeHist[id] = item
    table.insert(probeHistList, item)

    local abend = Anwesenheit.AktiverAbend(true)
    abend.gruppe = "Probe"
    local k = Kern.Schluessel(name)
    if k and abend.teilnehmer and not abend.teilnehmer[k] then
        abend.teilnehmer[k] = { name = name, status = Anwesenheit.StatusVon(name), bosse = 1 }
    end
    return true, item
end

function Probe.FertigerAblauf(ausgeben)
    if ausgeben == nil then ausgeben = true end
    if not probeAktiv then Probe.Starten() end
    Probe.Zuruecksetzen()

    local abend = Anwesenheit.AktiverAbend(true)
    abend.gruppe = "Probe"
    abend.bosse = 1
    abend.bossListe = {
        { name = "Lucifron", nummer = 9901, sieg = true, anwesende = probeRaidList }
    }

    -- 10 Main-Items an die Kaderspieler im Raid:
    -- Anna (2), Ben (2), Chris (1), David (1), Elena (1), Frank (1), Greta (1), Hanna (1) = 10 Items
    -- Igor (Proberaid 1. Abend: 0 Items), Jonas (Neuling 2. Abend: 0 Items)
    -- Abendschnitt = 10 Main-Items / 10 Raidspieler = 1.00
    Probe.VergebeItem("Anna", false, 1001)
    Probe.VergebeItem("Anna", false, 1002)
    Probe.VergebeItem("Ben", false, 1003)
    Probe.VergebeItem("Ben", false, 1004)
    Probe.VergebeItem("Chris", false, 1005)
    Probe.VergebeItem("David", false, 1006)
    Probe.VergebeItem("Elena", false, 1007)
    Probe.VergebeItem("Frank", false, 1008)
    Probe.VergebeItem("Greta", false, 1009)
    Probe.VergebeItem("Hanna", false, 1010)

    -- Status außerhalb des Raids (4 Spieler):
    Anwesenheit.BankSetzen("Nora", true, "ProbeLeiter")
    Anwesenheit.VergessenSetzen("Max", true, "ProbeLeiter")
    Anwesenheit.AbmeldungSetzen("Kevin", true, "ProbeLeiter")
    Anwesenheit.AbmeldungSetzen("Lisa", true, "ProbeLeiter")

    local igorStatus = Anwesenheit.StatusVon("Igor")
    local jonasStatus = Anwesenheit.StatusVon("Jonas")
    local rollenListe = {
        { name = "Anna", haupt = 2, wertung = 2 },
        { name = "Ben", haupt = 2, wertung = 2 },
        { name = "Chris", haupt = 1, wertung = 1 },
        { name = "David", haupt = 1, wertung = 1 },
        { name = "Elena", haupt = 1, wertung = 1 },
        { name = "Frank", haupt = 1, wertung = 1 },
        { name = "Greta", haupt = 1, wertung = 1 },
        { name = "Hanna", haupt = 1, wertung = 1 },
        { name = "Igor", haupt = 0, wertung = 0 },
        { name = "Jonas", haupt = 0, wertung = 0 },
    }
    Anwesenheit.Rollen(rollenListe, true)
    local jonasWertung = 0
    for _, e in ipairs(rollenListe) do
        if e.name == "Jonas" then
            jonasWertung = (e.neulingZiel and e.neulingZiel > 0) and e.neulingZiel or (e.wertung or 0)
        end
    end

    local vorschau = Anwesenheit.AbendVorschau(abend)
    local vMap = {}
    for _, p in ipairs((vorschau and vorschau.spieler) or {}) do
        vMap[p.schluessel] = p
    end

    local okAbschluss, _, zCount = Anwesenheit.AbendAbschliessen(abend, "ProbeLeiter")
    local zDaten = Anwesenheit.ZuschlaegeDaten()

    local annaZuschlag  = (zDaten.zuschlaege and zDaten.zuschlaege["anna"]) or 0
    local noraZuschlag  = (zDaten.zuschlaege and zDaten.zuschlaege["nora"]) or 0
    local maxZuschlag   = (zDaten.zuschlaege and zDaten.zuschlaege["max"]) or 0
    local kevinZuschlag = (zDaten.zuschlaege and zDaten.zuschlaege["kevin"]) or 0
    local lisaZuschlag  = (zDaten.zuschlaege and zDaten.zuschlaege["lisa"]) or 0

    local pruefungen = {
        raid = {
            name = "Anna",
            soll = 0.0,
            ist = annaZuschlag,
            ok = (vMap["anna"] and vMap["anna"].status == "imRaid") and annaZuschlag == 0,
        },
        bench = {
            name = "Nora",
            soll = 0.0,
            ist = noraZuschlag,
            ok = (vMap["nora"] and vMap["nora"].status == "bank") and noraZuschlag == 0,
        },
        keineMeldung = {
            name = "Max",
            soll = 0.7,
            ist = maxZuschlag,
            ok = (vMap["max"] and vMap["max"].status == "vergessen") and math.abs(maxZuschlag - 0.7) < 1e-6,
        },
        abgemeldet = {
            name = "Kevin, Lisa",
            soll = 0.7,
            ist = kevinZuschlag,
            ok = (vMap["kevin"] and vMap["kevin"].status == "abgemeldet")
                and (vMap["lisa"] and vMap["lisa"].status == "abgemeldet")
                and math.abs(kevinZuschlag - 0.7) < 1e-6
                and math.abs(lisaZuschlag - 0.7) < 1e-6,
        },
        proberaid = {
            name = "Igor",
            soll = "proberaid",
            ist = igorStatus,
            ok = (igorStatus == "proberaid") and (vMap["igor"] and vMap["igor"].status == "imRaid"),
        },
        neuling = {
            name = "Jonas",
            soll = 3.0,
            ist = jonasWertung,
            ok = (jonasStatus == "neuling") and math.abs(jonasWertung - 3.0) < 1e-6,
        },
    }

    local alleOk = pruefungen.raid.ok and pruefungen.bench.ok and pruefungen.keineMeldung.ok
                   and pruefungen.abgemeldet.ok and pruefungen.proberaid.ok and pruefungen.neuling.ok
                   and okAbschluss and (probeGesendet > 0)

    if ausgeben then
        local OK_TAG = "|cff55ff55[OK]|r"
        local ERR_TAG = "|cffff5555" .. L["[FEHLER]"] .. "|r"
        print("|cff1B6B57KaosLoot|r: |cffffff78" .. L["Probe-Abend (Wegwerf-Datenbank, keine echten Daten):"] .. "|r")
        print(string.format(L["  Abendschnitt: %.2f (%d Main-Items / %d Spieler im Raid)"],
            vorschau and vorschau.schnitt or 0, 10, 10))

        print(string.format(L["  Raid (%s): Erwartet Zuschlag %.1f  /  Ist %.1f %s"],
            "Anna", pruefungen.raid.soll, pruefungen.raid.ist, pruefungen.raid.ok and OK_TAG or ERR_TAG))
        print(string.format(L["  Bench (%s): Erwartet Zuschlag %.1f  /  Ist %.1f %s"],
            "Nora", pruefungen.bench.soll, pruefungen.bench.ist, pruefungen.bench.ok and OK_TAG or ERR_TAG))
        print(string.format(L["  Weder an- noch abgemeldet (%s): Erwartet Zuschlag %.1f (wie abgemeldet)  /  Ist %.1f %s"],
            "Max", pruefungen.keineMeldung.soll, pruefungen.keineMeldung.ist, pruefungen.keineMeldung.ok and OK_TAG or ERR_TAG))
        print(string.format(L["  Abgemeldet (%s): Erwartet Zuschlag %.1f  /  Ist %.1f %s"],
            "Kevin, Lisa", pruefungen.abgemeldet.soll, pruefungen.abgemeldet.ist, pruefungen.abgemeldet.ok and OK_TAG or ERR_TAG))
        print(string.format(L["  Proberaid 1. Abend (%s): Erwartet Status %s  /  Ist %s %s"],
            "Igor", pruefungen.proberaid.soll, pruefungen.proberaid.ist, pruefungen.proberaid.ok and OK_TAG or ERR_TAG))
        print(string.format(L["  Neuling 2. Abend (%s): Erwartet Einstieg %.1f (Niedrigster + 2)  /  Ist %.1f %s"],
            "Jonas", pruefungen.neuling.soll, pruefungen.neuling.ist, pruefungen.neuling.ok and OK_TAG or ERR_TAG))

        if alleOk then
            print("|cff1B6B57KaosLoot|r: |cff55ff55" .. L["Probe-Abend erfolgreich: 6/6 Prüfungen bestanden."] .. "|r")
            print("  |cff8E9A94" .. L["FairshareDB unverändert, nichts gesendet."] .. "|r")
        else
            local fehlerAnz = 0
            for _, p in pairs(pruefungen) do if not p.ok then fehlerAnz = fehlerAnz + 1 end end
            print("|cff1B6B57KaosLoot|r: |cffff5555" .. string.format(L["Probe-Abend fehlgeschlagen (%d Fehler)."], fehlerAnz) .. "|r")
        end
    end

    return alleOk, {
        ok = alleOk,
        schnitt = vorschau and vorschau.schnitt or 0,
        pruefungen = pruefungen,
        okAbschluss = okAbschluss,
        zCount = zCount,
        gesendet = probeGesendet,
    }
end

function Anwesenheit.ProbeStandardAbend(ausgeben)
    if ausgeben == nil then ausgeben = true end
    Probe.Starten()
    local ok, res = Probe.FertigerAblauf(ausgeben)
    Probe.Beenden()
    return ok, res
end

--- Lädt alle anwesenden Spieler der aktuellen/aktiven Gruppe in den Raid ein.
function Anwesenheit.GruppeEinladen(leise)
    local abend = ns.Anwesenheit.AktiverAbend and ns.Anwesenheit.AktiverAbend(false) or nil
    local gruppe = (abend and abend.gruppe) or (ns.Gruppen and ns.Gruppen.AktivName and ns.Gruppen.AktivName())
    local datum = (abend and abend.datum) or (ns.Gruppen and ns.Gruppen.EinteilungTag and ns.Gruppen.EinteilungTag(0)) or (date and date("%Y-%m-%d", time()))

    local pool = {}
    local gesehen = {}
    if gruppe and ns.Gruppen and ns.Gruppen.EinteilungListe then
        local namen = ns.Gruppen.EinteilungListe(datum, gruppe)
        for _, n in ipairs(namen or {}) do
            local k = Kern.Schluessel(n)
            if k and not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = n
            end
        end
    end
    if #pool == 0 and gruppe and ns.Gruppen and ns.Gruppen.Pflicht then
        local pflicht = ns.Gruppen.Pflicht(gruppe)
        for _, n in ipairs(pflicht or {}) do
            local k = Kern.Schluessel(n)
            if k and not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = n
            end
        end
    end
    if #pool == 0 then
        local kand = ns.Anwesenheit.KandidatenListe and ns.Anwesenheit.KandidatenListe(abend, true) or {}
        for _, e in ipairs(kand) do
            local k = Kern.Schluessel(e.name)
            if k and not gesehen[k] then
                gesehen[k] = true
                pool[#pool + 1] = e.name
            end
        end
    end

    if #pool == 0 then
        return false, L["Keine Spieler in der Gruppe gefunden."]
    end

    -- Online-Status der Gildenmitglieder ermitteln
    local onlineMap = {}
    local gildeGeladen = false
    if ns.Gruppen and ns.Gruppen.GildenMitglieder then
        local GM = ns.Gruppen.GildenMitglieder()
        if GM and #GM > 0 then
            gildeGeladen = true
            for _, m in ipairs(GM) do
                local k = Kern.Schluessel(m.name)
                if k then onlineMap[k] = m.online and true or false end
            end
        end
    end

    local drinnen = {}
    if Anwesenheit.AnwesendeNamen then
        for _, n in ipairs(Anwesenheit.AnwesendeNamen()) do
            local k = Kern.Schluessel(n)
            if k then drinnen[k] = true end
        end
    end

    local ich = ichName()
    local eingeladen = 0
    local bereitsDrin = 0
    local offline = 0

    -- ⭐ Ein Raid ist nur nötig, wenn mehr als 5 Spieler (mit dir) zusammenkommen sollen, und er wird erst gebildet,
    -- wenn die normale Gruppe 5 Mitglieder hat (Roster-Ereignis unten, oder gleich, wenn sie schon voll ist).
    local gesamt = 1
    for _, n in ipairs(pool) do
        if not Kern.GleicherSpieler(n, ich) then gesamt = gesamt + 1 end
    end
    local brauchtRaid = gesamt > 5
    if brauchtRaid and raidNoetig() then
        konvertiereZuRaid()
    end
    if brauchtRaid and not (IsInRaid and IsInRaid()) then
        anwesenheitAutoRaid = true
        autoRaidBis = time() + 180
    end

    for _, name in ipairs(pool) do
        local k = Kern.Schluessel(name)
        local ausgeschlossen = false
        if abend then
            if (abend.bank and abend.bank[k]) or
               (abend.abgemeldet and abend.abgemeldet[k]) or
               (abend.unentschuldigt and abend.unentschuldigt[k]) or
               (abend.vergessen and abend.vergessen[k]) then
                ausgeschlossen = true
            end
        end
        if not ausgeschlossen and ns.Gruppen and ns.Gruppen.BenchListe then
            local bench = ns.Gruppen.BenchListe(datum)
            for _, bn in ipairs(bench or {}) do
                if Kern.GleicherSpieler(bn, name) then
                    ausgeschlossen = true
                    break
                end
            end
        end

        if not ausgeschlossen and not Kern.GleicherSpieler(name, ich) then
            local schonDa = drinnen[k]
            if not schonDa and UnitInRaid and UnitInRaid(name) then schonDa = true end
            if not schonDa and UnitInParty and UnitInParty(name) then schonDa = true end
            if not schonDa and ns.Rolle and ns.Rolle.IstDabei and ns.Rolle.IstDabei(name) then schonDa = true end

            if schonDa then
                bereitsDrin = bereitsDrin + 1
            else
                local istOnline = true
                if gildeGeladen then
                    local st = onlineMap[k]
                    if st ~= nil then
                        istOnline = (st == true)
                    end
                end

                if not istOnline then
                    offline = offline + 1
                else
                    local ok = false
                    if brauchtRaid and raidNoetig() then konvertiereZuRaid() end        -- voll: erst Raid, dann einladen
                    eigeneEinladung = true
                    if C_PartyInfo and C_PartyInfo.InviteUnit then
                        ok = pcall(C_PartyInfo.InviteUnit, name)
                    elseif InviteUnit then
                        ok = pcall(InviteUnit, name)
                    end
                    eigeneEinladung = false
                    if ok then
                        eingeladen = eingeladen + 1
                    end
                end
            end
        end
    end

    -- ⭐ Die Einladungsrunde bleibt offen, bis ein Raid daraus geworden ist: Die Gruppe wächst erst, wenn die
    -- Eingeladenen annehmen, und erst bei 5 Mitgliedern wird sie zum Raid (Roster-Ereignis oben).
    if not brauchtRaid or (IsInRaid and IsInRaid()) then
        anwesenheitAutoRaid = false
    end

    return true, eingeladen, bereitsDrin, offline
end

Probe.StandardAbend = Anwesenheit.ProbeStandardAbend
Probe.KonvertiereZuRaid = konvertiereZuRaid
Probe.GetAutoRaid = function() return anwesenheitAutoRaid end
Probe.SetAutoRaid = function(an) anwesenheitAutoRaid = an end

return Anwesenheit
