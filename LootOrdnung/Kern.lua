--[[----------------------------------------------------------------------
    Kern.lua  —  Rechenkern der Loot-Ordnung

    Enthaelt ausschliesslich Rechnerei: keine WoW-API, keine Frames, keine
    Events. Dadurch laeuft diese Datei im Spiel UND in einem gewoehnlichen
    Lua-Interpreter, und der Pruefstand kann sie ohne Client testen.

    Massgeblich ist das Regelwerk (loot-ordnung.html); die Paragrafen sind
    an den betroffenen Stellen vermerkt. Aendert sich eine Stellschraube,
    muss sie hier UND in berechnungen.py nachgezogen werden.
------------------------------------------------------------------------]]

local _, ns = ...
ns = ns or {}

local Kern = {}
ns.Kern = Kern

local floor, max, min = math.floor, math.max, math.min

-- =====================================================================
--  Stellschrauben
-- =====================================================================

Kern.regeln = {
    verfall           = 0.10,   -- je Woche, auf BEIDE Groessen (§ 4)
    einsatzProBoss    = 5,      -- auch bei Wipes (§ 2)
    bonusVollDabei    = 10,     -- vom ersten bis zum letzten Kampf
    mindestRuestwert  = 100,    -- Untergrenze, mit K zu eichen (§ 5)
    eichwertK         = 26,     -- Verdopplung je K Gegenstandsstufen (§ 3)
    grundstufe        = 0,      -- Bezugspunkt der Gegenstandsstufe
    deckelRaidtage    = 4,      -- Abmelde-Deckel in Folge (§ 2)
}

-- Anteil des Abendsatzes je Meldestatus (§ 2, Rangfolge)
Kern.saetze = {
    mitgegangen  = 1.00,   -- wird ueber Bosskaempfe gerechnet, nicht hier
    bank         = 1.00,   -- zugesagt, online, nicht gebraucht
    abgesagt     = 0.50,   -- direkt abgesagt, bis 24 h vorher
    zurueckgezogen = 0.25, -- Zusage zurueckgezogen oder spaet abgesagt
    nichts       = 0.00,   -- alles andere
}

-- Platzfaktoren (§ 3). Schluessel sind WoW-Ausruestungsplaetze.
Kern.platzfaktoren = {
    INVTYPE_2HWEAPON      = 3.0,

    INVTYPE_TRINKET       = 2.0,

    INVTYPE_WEAPON        = 1.5,
    INVTYPE_WEAPONMAINHAND= 1.5,
    INVTYPE_WEAPONOFFHAND = 1.5,
    INVTYPE_SHIELD        = 1.5,
    INVTYPE_HOLDABLE      = 1.5,
    INVTYPE_RANGED        = 1.5,
    INVTYPE_RANGEDRIGHT   = 1.5,
    INVTYPE_THROWN        = 1.5,
    INVTYPE_HEAD          = 1.5,
    INVTYPE_SHOULDER      = 1.5,
    INVTYPE_CHEST         = 1.5,
    INVTYPE_ROBE          = 1.5,
    INVTYPE_HAND          = 1.5,
    INVTYPE_WAIST         = 1.5,
    INVTYPE_LEGS          = 1.5,
    INVTYPE_FEET          = 1.5,

    INVTYPE_NECK          = 1.0,
    INVTYPE_CLOAK         = 1.0,
    INVTYPE_WRIST         = 1.0,
    INVTYPE_FINGER        = 1.0,
    INVTYPE_RELIC         = 1.0,
}

-- =====================================================================
--  Konten
-- =====================================================================

--- Ein leeres Konto. Ruestwert startet an der Untergrenze (§ 5).
function Kern.NeuesKonto(woche)
    return {
        einsatz    = 0,
        ruestwert  = Kern.regeln.mindestRuestwert,
        woche      = woche,   -- Woche des letzten Verfalls
        deckel     = 0,       -- abgemeldete Raidtage in Folge
        gegenstaende = 0,     -- Stueck in dieser Raidstufe (§ 8)
    }
end

--- Prio = Einsatz / Ruestwert (§ 1).
--  Der Ruestwert kann nie null sein, deshalb keine Sonderbehandlung.
function Kern.Prio(konto)
    if not konto then return 0 end
    local r = max(konto.ruestwert, Kern.regeln.mindestRuestwert)
    return konto.einsatz / r
end

-- =====================================================================
--  Verfall (§ 4)
-- =====================================================================

--- Holt den Verfall bis zur angegebenen Woche nach.
--  IDEMPOTENT: Mehrfaches Aufrufen aendert nichts. Das ist zwingend —
--  bei mehreren Raidgruppen laesst sonst jeder Raidleiter den Verfall
--  erneut laufen und zieht doppelt ab.
--  @return konto, Anzahl nachgeholter Wochen
function Kern.VerfallNachholen(konto, woche)
    if not konto.woche then
        konto.woche = woche
        return konto, 0
    end

    local wochen = woche - konto.woche
    if wochen <= 0 then return konto, 0 end

    local faktor = (1 - Kern.regeln.verfall) ^ wochen
    konto.einsatz   = konto.einsatz * faktor
    konto.ruestwert = max(konto.ruestwert * faktor, Kern.regeln.mindestRuestwert)
    konto.woche     = woche
    return konto, wochen
end

--- Fortlaufende Wochennummer aus einem Unix-Zeitstempel.
--  ACHTUNG: bewusst NICHT die Kalenderwoche — die springt zum
--  Jahreswechsel von 52 auf 1 zurueck und macht die Differenz negativ.
--  @param versatz Stunden, um die der Wochenwechsel verschoben wird,
--                 damit er auf den Raid-Reset faellt statt auf
--                 Donnerstag 0 Uhr UTC (dort liegt die Unix-Epoche).
function Kern.WocheAus(zeitstempel, versatz)
    versatz = versatz or 0
    return floor((zeitstempel - versatz * 3600) / 604800)
end

-- =====================================================================
--  Einsatz (§ 2)
-- =====================================================================

--- Voller Satz eines Abends: je Boss plus Bonus fuer volle Anwesenheit.
function Kern.Abendsatz(bosse)
    local r = Kern.regeln
    return (bosse or 0) * r.einsatzProBoss + r.bonusVollDabei
end

--- Einsatz fuer einen Abend nach Meldestatus.
--  Bezugsgroesse ist immer der TATSAECHLICH gelaufene Abend (§ 2) —
--  faellt der Raid aus, bekommt auch niemand etwas.
--  @param status  "bank" | "abgesagt" | "zurueckgezogen" | "nichts"
function Kern.EinsatzFuerStatus(status, bosse)
    local anteil = Kern.saetze[status]
    if not anteil then return 0 end
    return Kern.Abendsatz(bosse) * anteil
end

--- Einsatz fuer jemanden, der mitgegangen ist.
--  @param bosseTeilgenommen  an wie vielen Kaempfen er dabei war
--  @param vollDabei          vom ersten bis zum letzten Kampf
function Kern.EinsatzFuerTeilnahme(bosseTeilgenommen, vollDabei)
    local r = Kern.regeln
    local e = (bosseTeilgenommen or 0) * r.einsatzProBoss
    if vollDabei then e = e + r.bonusVollDabei end
    return e
end

--- Bucht eine Abmeldung und fuehrt den Deckel mit (§ 2).
--  Nach vier abgemeldeten Raidtagen in Folge bringt eine Absage nichts
--  mehr, bis wieder einmal mitgeraidet wurde.
--  @return gutgeschriebener Einsatz
function Kern.AbmeldungBuchen(konto, status, bosse)
    if konto.deckel >= Kern.regeln.deckelRaidtage then
        konto.deckel = konto.deckel + 1
        return 0
    end
    local e = Kern.EinsatzFuerStatus(status, bosse)
    konto.einsatz = konto.einsatz + e
    konto.deckel  = konto.deckel + 1
    return e
end

--- Bucht eine Teilnahme. Setzt den Abmelde-Deckel zurueck.
function Kern.TeilnahmeBuchen(konto, bosseTeilgenommen, vollDabei)
    local e = Kern.EinsatzFuerTeilnahme(bosseTeilgenommen, vollDabei)
    konto.einsatz = konto.einsatz + e
    konto.deckel  = 0
    return e
end

-- =====================================================================
--  Ruestwert (§ 3)
-- =====================================================================

--- Grundwert einer Gegenstandsstufe: verdoppelt sich alle K Stufen.
function Kern.Grundwert(gegenstandsstufe)
    local r = Kern.regeln
    return 2 ^ ((gegenstandsstufe - r.grundstufe) / r.eichwertK)
end

--- Ruestwert eines Gegenstands.
--  @param platz  WoW-Ausruestungsplatz, z.B. "INVTYPE_HEAD"
--  @param korrektur  optionaler Faktor der Raidleitung (§ 3/§ 7)
function Kern.RuestwertVon(platz, gegenstandsstufe, korrektur)
    local faktor = Kern.platzfaktoren[platz]
    if not faktor then return nil end
    return faktor * Kern.Grundwert(gegenstandsstufe) * (korrektur or 1)
end

--- Bucht eine Vergabe. Zweitbedarf kostet nichts (§ 6).
--  @param zweitbedarf  true = kein Ruestwert, nur Zaehler
function Kern.VergabeBuchen(konto, ruestwert, zweitbedarf)
    konto.gegenstaende = konto.gegenstaende + 1
    if zweitbedarf then return 0 end
    konto.ruestwert = konto.ruestwert + (ruestwert or 0)
    return ruestwert or 0
end

-- =====================================================================
--  Neue Mitglieder (§ 5)
-- =====================================================================

--- Startkonto fuer einen frisch befoerderten Raider.
--  Gesetzt wird die PRIO, nicht Einsatz und Ruestwert einzeln — wer nur
--  eine der beiden Groessen setzt, setzt in Wahrheit gar nichts.
--  @param zielPrio   hoechste Prio der Stammgruppe
--  @param medianEinsatz  Median der Gruppe
function Kern.StartkontoFuerRaider(zielPrio, medianEinsatz, woche)
    local konto = Kern.NeuesKonto(woche)
    if not zielPrio or zielPrio <= 0 then return konto end
    konto.einsatz   = medianEinsatz or 0
    konto.ruestwert = max(konto.einsatz / zielPrio, Kern.regeln.mindestRuestwert)
    return konto
end

--- Hoechste Prio und Median-Einsatz einer Kontenmenge.
--  @param konten  Tabelle name -> konto
function Kern.Kennzahlen(konten)
    local prios, einsaetze, n = {}, {}, 0
    for _, k in pairs(konten) do
        n = n + 1
        prios[n]     = Kern.Prio(k)
        einsaetze[n] = k.einsatz
    end
    if n == 0 then return 0, 0 end
    table.sort(prios)
    table.sort(einsaetze)
    local median
    if n % 2 == 1 then
        median = einsaetze[(n + 1) / 2]
    else
        median = (einsaetze[n / 2] + einsaetze[n / 2 + 1]) / 2
    end
    return prios[n], median
end

-- =====================================================================
--  Rangfolge
-- =====================================================================

--- Sortiert Bewerber nach der Vergaberegel.
--  Hauptbedarf schlaegt Zweitbedarf IMMER, unabhaengig von der Prio
--  (§ 6). Innerhalb einer Gruppe entscheidet die Prio, bei Gleichstand
--  unter 5 % wer weniger Gegenstaende dieser Raidstufe hat (§ 8).
--  @param bewerber  Liste aus { name=, konto=, zweitbedarf= }
function Kern.Rangfolge(bewerber)
    local liste = {}
    for i, b in ipairs(bewerber) do
        liste[i] = {
            name         = b.name,
            konto        = b.konto,
            zweitbedarf  = b.zweitbedarf and true or false,
            prio         = Kern.Prio(b.konto),
            gegenstaende = b.konto and b.konto.gegenstaende or 0,
            eingang      = i,   -- stabile Reihenfolge bei voelligem Gleichstand
        }
    end

    table.sort(liste, function(a, b)
        if a.zweitbedarf ~= b.zweitbedarf then
            return not a.zweitbedarf
        end
        local hoch, tief = max(a.prio, b.prio), min(a.prio, b.prio)
        local nah = hoch > 0 and (hoch - tief) / hoch < 0.05
        if nah then
            if a.gegenstaende ~= b.gegenstaende then
                return a.gegenstaende < b.gegenstaende
            end
            return a.eingang < b.eingang
        end
        return a.prio > b.prio
    end)

    return liste
end

return ns
