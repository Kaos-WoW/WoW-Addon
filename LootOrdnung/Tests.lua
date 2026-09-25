--[[----------------------------------------------------------------------
    Tests.lua  —  Selbsttests des Rechenkerns

    Laeuft in beiden Welten:
      * im Spiel ueber  /lo test
      * offline ueber   lua Tests.lua   (im Ordner LootOrdnung/)

    Die Erwartungswerte in "Gegen das Rechenmodell" stammen aus
    berechnungen.py. Weichen sie ab, rechnen Addon und Regelwerk
    verschieden — das darf nie passieren, weil im Regelwerk die Zahlen
    stehen, an denen die Gilde das System nachrechnet.
------------------------------------------------------------------------]]

local _, ns = ...

if not ns then
    -- Offline: Kern und Notiz selbst laden, so wie WoW es tun wuerde.
    ns = {}
    local hier = (arg and arg[0] or ""):match("^(.*[/\\])") or ""
    for _, datei in ipairs({ "Kern.lua", "Notiz.lua" }) do
        local chunk = assert(loadfile(hier .. datei))
        chunk("LootOrdnung", ns)
    end
end

local Kern, Notiz = ns.Kern, ns.Notiz
local Tests = {}
ns.Tests = Tests

-- =====================================================================
--  Geruest
-- =====================================================================

local gut, schlecht, meldungen

local function melde(text)
    meldungen[#meldungen + 1] = text
end

local function nahe(name, ist, soll, toleranz)
    toleranz = toleranz or 0.005
    if type(ist) == "number" and math.abs(ist - soll) <= toleranz then
        gut = gut + 1
    else
        schlecht = schlecht + 1
        melde(string.format("  FEHLER  %s: ist %s, soll %.4f",
            name, tostring(ist), soll))
    end
end

local function gleich(name, ist, soll)
    if ist == soll then
        gut = gut + 1
    else
        schlecht = schlecht + 1
        melde(string.format("  FEHLER  %s: ist %s, soll %s",
            name, tostring(ist), tostring(soll)))
    end
end

--- Eine Raidwoche wie in berechnungen.py: erst Verfall, dann Zuwachs.
local function simWoche(konto, woche, ep, rp)
    Kern.VerfallNachholen(konto, woche)
    konto.einsatz   = konto.einsatz + (ep or 0)
    konto.ruestwert = konto.ruestwert + (rp or 0)
end

local function testkonto(einsatz, ruestwert, woche)
    local k = Kern.NeuesKonto(woche or 0)
    k.einsatz   = einsatz
    k.ruestwert = ruestwert
    return k
end

-- =====================================================================
--  Die Tests
-- =====================================================================

local function testVerfall()
    -- Idempotenz: derselbe Aufruf zweimal darf nicht doppelt abziehen.
    -- Das ist der wichtigste Test ueberhaupt — bei mehreren Raidgruppen
    -- laesst sonst jeder Raidleiter den Verfall erneut laufen.
    local a = testkonto(600, 400, 10)
    Kern.VerfallNachholen(a, 11)
    local nachEinmal = a.einsatz
    Kern.VerfallNachholen(a, 11)
    nahe("Verfall ist idempotent", a.einsatz, nachEinmal, 0.0001)

    -- Mehrere Wochen auf einmal = dieselbe Potenz
    local b = testkonto(600, 400, 10)
    Kern.VerfallNachholen(b, 13)
    nahe("drei Wochen am Stueck", b.einsatz, 600 * 0.9 ^ 3, 0.0001)

    -- Rueckwaerts darf nichts passieren
    local c = testkonto(600, 400, 10)
    Kern.VerfallNachholen(c, 8)
    nahe("Vergangenheit aendert nichts", c.einsatz, 600, 0.0001)

    -- Untergrenze des Ruestwerts
    local d = testkonto(600, 120, 0)
    Kern.VerfallNachholen(d, 20)
    nahe("Ruestwert faellt nicht unter das Minimum",
         d.ruestwert, Kern.regeln.mindestRuestwert, 0.0001)

    -- Wochennummer springt nicht am Jahreswechsel
    local w1 = Kern.WocheAus(1767225600)        -- irgendwann Ende Dezember
    local w2 = Kern.WocheAus(1767225600 + 604800)
    gleich("Wochennummer laeuft durch", w2 - w1, 1)
end

local function testAbwesenheit()
    -- DER Kernbefund: Der Verfall trifft beide Groessen, also bleibt das
    -- Verhaeltnis stehen. Wer aussetzt, verliert keine Prio.
    local k = testkonto(600, 400, 0)
    local vorher = Kern.Prio(k)
    for w = 1, 8 do simWoche(k, w, 0, 0) end
    nahe("Abwesenheit kostet keine Prio", Kern.Prio(k), vorher, 0.0001)
end

local function testEinsatz()
    gleich("Abendsatz bei 8 Bossen", Kern.Abendsatz(8), 50)
    nahe("halber Satz",   Kern.EinsatzFuerStatus("abgesagt", 8), 25)
    nahe("Viertelsatz",   Kern.EinsatzFuerStatus("zurueckgezogen", 8), 12.5)
    nahe("nichts gemeldet", Kern.EinsatzFuerStatus("nichts", 8), 0)
    nahe("Bank zaehlt voll", Kern.EinsatzFuerStatus("bank", 8), 50)

    -- Faellt der Raid aus, bekommt niemand etwas (§ 2).
    -- Dieser Test war zuerst gegen die Implementierung geschrieben statt
    -- gegen die Regel und hat den Fehler deshalb durchgelassen.
    nahe("Raid ausgefallen, Absage", Kern.EinsatzFuerStatus("abgesagt", 0), 0)
    nahe("Raid ausgefallen, Bank",   Kern.EinsatzFuerStatus("bank", 0), 0)
    gleich("Abendsatz ohne Boss",    Kern.Abendsatz(0), 0)

    nahe("Teilnahme an 6 von 8 Bossen",
         Kern.EinsatzFuerTeilnahme(6, false), 30)
    nahe("voll dabei", Kern.EinsatzFuerTeilnahme(8, true), 50)

    -- Deckel: nach vier Abmeldungen in Folge bringt die fuenfte nichts
    local k = Kern.NeuesKonto(0)
    for i = 1, Kern.regeln.deckelRaidtage do
        local e = Kern.AbmeldungBuchen(k, "abgesagt", 8)
        nahe("Abmeldung " .. i .. " zaehlt", e, 25)
    end
    nahe("Abmeldung ueber dem Deckel bringt nichts",
         Kern.AbmeldungBuchen(k, "abgesagt", 8), 0)

    -- Teilnahme setzt den Zaehler zurueck
    Kern.TeilnahmeBuchen(k, 8, true)
    gleich("Teilnahme setzt den Deckel zurueck", k.deckel, 0)
    nahe("danach zaehlt eine Abmeldung wieder",
         Kern.AbmeldungBuchen(k, "abgesagt", 8), 25)
end

local function testRuestwert()
    local K = Kern.regeln.eichwertK
    nahe("Grundwert an der Grundstufe", Kern.Grundwert(Kern.regeln.grundstufe), 1)
    nahe("Verdopplung nach K Stufen",
         Kern.Grundwert(Kern.regeln.grundstufe + K), 2)

    -- Platzfaktoren (§ 3)
    local basis = Kern.Grundwert(Kern.regeln.grundstufe)
    nahe("Zweihandwaffe",  Kern.RuestwertVon("INVTYPE_2HWEAPON", 0), 3.0 * basis)
    nahe("Schmuckstueck",  Kern.RuestwertVon("INVTYPE_TRINKET",  0), 2.0 * basis)
    nahe("Einhandwaffe",   Kern.RuestwertVon("INVTYPE_WEAPON",   0), 1.5 * basis)
    nahe("Distanzwaffe",   Kern.RuestwertVon("INVTYPE_RANGED",   0), 1.5 * basis)
    nahe("Ring",           Kern.RuestwertVon("INVTYPE_FINGER",   0), 1.0 * basis)
    gleich("unbekannter Platz", Kern.RuestwertVon("INVTYPE_QUATSCH", 0), nil)

    -- Zwei Einhandplaetze kosten so viel wie ein Zweihaender
    nahe("2 x Einhand = 1 x Zweihand",
         2 * Kern.RuestwertVon("INVTYPE_WEAPON", 0),
         Kern.RuestwertVon("INVTYPE_2HWEAPON", 0))

    -- Zweitbedarf kostet keinen Ruestwert (§ 6)
    local k = Kern.NeuesKonto(0)
    local vorher = k.ruestwert
    Kern.VergabeBuchen(k, 90, true)
    nahe("Zweitbedarf kostet nichts", k.ruestwert, vorher)
    gleich("wird aber gezaehlt", k.gegenstaende, 1)
    Kern.VergabeBuchen(k, 90, false)
    nahe("Hauptbedarf kostet", k.ruestwert, vorher + 90)
end

local function testNeulinge()
    -- Wer nur EINE der beiden Groessen setzt, setzt in Wahrheit gar
    -- nichts — deshalb wird die Prio gesetzt, nicht die Einzelwerte.
    local konten = {
        a = testkonto(600, 400, 0),   -- Prio 1.50
        b = testkonto(500, 250, 0),   -- Prio 2.00  <- hoechste
        c = testkonto(400, 500, 0),   -- Prio 0.80
    }
    local hoechste, median = Kern.Kennzahlen(konten)
    nahe("hoechste Prio der Gruppe", hoechste, 2.00)
    nahe("Median-Einsatz", median, 500)

    local neu = Kern.StartkontoFuerRaider(hoechste, median, 0)
    nahe("Neuling startet auf der hoechsten Prio", Kern.Prio(neu), hoechste)

    -- Nach dem ersten Gegenstand faellt er zurueck
    Kern.VergabeBuchen(neu, 180, false)
    local fiel = Kern.Prio(neu) < hoechste
    gleich("und faellt nach dem ersten Stueck zurueck", fiel, true)
end

local function testRangfolge()
    local hoch = testkonto(900, 300, 0)   -- 3.00
    local mittel = testkonto(600, 400, 0) -- 1.50
    local tief = testkonto(300, 500, 0)   -- 0.60

    -- Hauptbedarf schlaegt Zweitbedarf immer, egal wie hoch die Prio ist
    local r = Kern.Rangfolge({
        { name = "Zweit", konto = hoch,   zweitbedarf = true  },
        { name = "Haupt", konto = tief,   zweitbedarf = false },
    })
    gleich("Hauptbedarf vor Zweitbedarf", r[1].name, "Haupt")

    -- Innerhalb einer Gruppe entscheidet die Prio
    local r2 = Kern.Rangfolge({
        { name = "tief",   konto = tief },
        { name = "hoch",   konto = hoch },
        { name = "mittel", konto = mittel },
    })
    gleich("hoechste Prio zuerst", r2[1].name, "hoch")
    gleich("dann die mittlere",    r2[2].name, "mittel")
    gleich("dann die tiefste",     r2[3].name, "tief")

    -- Gleichstand unter 5 %: wer weniger bekommen hat (§ 8)
    local a = testkonto(600, 400, 0)          -- 1.500
    local b = testkonto(602, 400, 0)          -- 1.505, nur 0.3 % Unterschied
    a.gegenstaende, b.gegenstaende = 3, 1
    local r3 = Kern.Rangfolge({
        { name = "vieleStuecke",  konto = a },
        { name = "wenigStuecke",  konto = b },
    })
    gleich("bei Gleichstand zaehlt, wer weniger hat",
           r3[1].name, "wenigStuecke")
end

local function testNotiz()
    local k = Kern.NeuesKonto(2953)
    k.einsatz, k.ruestwert = 4500.4, 3800.6
    k.deckel, k.gegenstaende = 2, 7
    k.gebucht = 87234

    local text = Notiz.Schreiben(k)
    gleich("Notiztext", text, "LO:4500,3801,2953,2,7,87234")
    gleich("passt in die Notiz", #text <= Notiz.MAXLAENGE, true)

    local zurueck = Notiz.Rundlauf(k)
    gleich("Rundlauf Einsatz",   zurueck.einsatz, 4500)
    gleich("Rundlauf Ruestwert", zurueck.ruestwert, 3801)
    gleich("Rundlauf Woche",     zurueck.woche, 2953)
    gleich("Rundlauf Deckel",    zurueck.deckel, 2)
    gleich("Rundlauf Stuecke",   zurueck.gegenstaende, 7)
    gleich("Rundlauf Buchung",   zurueck.gebucht, 87234)

    -- Fremdinhalt erkennen, damit das Addon nichts ueberschreibt, was
    -- die Gilde von Hand gepflegt hat ("von Patric")
    gleich("leer ist nicht fremd",  Notiz.IstFremd(""), false)
    gleich("eigenes Format",        Notiz.IstFremd("LO:1,2,3,0,0"), false)
    gleich("Fremdinhalt erkannt",   Notiz.IstFremd("von Patric"), true)

    local _, grund = Notiz.Lesen("von Patric")
    gleich("Grund bei Fremdinhalt", grund, "fremd")
    local _, grund2 = Notiz.Lesen("")
    gleich("Grund bei leer", grund2, "leer")
    local _, grund3 = Notiz.Lesen("LO:kaputt")
    gleich("Grund bei Schrott", grund3, "unlesbar")

    -- Aeltere Fassungen muessen lesbar bleiben
    local kurz = Notiz.Lesen("LO:100,200,300")
    gleich("Kurzfassung Einsatz", kurz and kurz.einsatz, 100)
    gleich("Kurzfassung Deckel",  kurz and kurz.deckel, 0)
    gleich("Kurzfassung Buchung", kurz and kurz.gebucht, 0)

    local fuenf = Notiz.Lesen("LO:100,200,300,1,2")
    gleich("Fassung ohne Buchung: Stuecke", fuenf and fuenf.gegenstaende, 2)
    gleich("Fassung ohne Buchung: Stempel", fuenf and fuenf.gebucht, 0)

    -- Grenze: sehr grosse Werte duerfen nicht still abgeschnitten werden
    local gross = Kern.NeuesKonto(99999)
    gross.einsatz, gross.ruestwert = 99999, 99999
    gross.deckel, gross.gegenstaende = 99999, 99999
    gross.gebucht = 99999
    local zuLang, grundLang = Notiz.Schreiben(gross)
    gleich("zu langer Text wird abgelehnt", zuLang, nil)
    gleich("mit Grund", grundLang, "zu lang")
end

local function testVergabe()
    -- Vergabe.lua und Abgleich.lua sind nicht API-frei; offline fehlen sie.
    if not (ns.Vergabe and ns.Abgleich) then return end
    local V, A = ns.Vergabe, ns.Abgleich

    -- Zusammenfuehren: aus Einzelvergaben, nicht aus Summen
    local eigen = { a = { spieler = "Kaos", gegenstand = 1, zeit = 10 } }
    local fremd = {
        a = { spieler = "Kaos", gegenstand = 1, zeit = 10 },
        b = { spieler = "Timo", gegenstand = 2, zeit = 20 },
    }

    local neu, weg = V.Vereinen(eigen, fremd)
    gleich("nur das Unbekannte kommt dazu", neu, 1)
    gleich("nichts zurueckgenommen", weg, 0)
    gleich("fremde Vergabe ist da", eigen.b and eigen.b.spieler, "Timo")

    -- Nochmal dasselbe darf nichts mehr aendern
    local neu2 = V.Vereinen(eigen, fremd)
    gleich("zweiter Durchlauf ist wirkungslos", neu2, 0)

    -- Ein Grabstein gewinnt, egal von welcher Seite
    local mitGrab = { b = { weg = true, zeit = 30 } }
    local _, weg2 = V.Vereinen(eigen, mitGrab)
    gleich("Ruecknahme setzt sich durch", weg2, 1)
    gleich("Eintrag ist als weg markiert", eigen.b.weg, true)

    -- und sie darf nicht wieder auferstehen
    local _, weg3 = V.Vereinen(eigen, fremd)
    gleich("zurueckgenommen bleibt zurueckgenommen", eigen.b.weg, true)
    gleich("keine neue Ruecknahme gezaehlt", weg3, 0)

    -- Grabstein zuerst, Angaben spaeter: die Angaben werden ergaenzt
    local nurGrab = { c = { weg = true, zeit = 5 } }
    V.Vereinen(nurGrab, { c = { spieler = "Lina", gegenstand = 7, zeit = 5 } })
    gleich("Grabstein bekommt den Spieler nachgereicht", nurGrab.c.spieler, "Lina")
    gleich("Grabstein bleibt ein Grabstein", nurGrab.c.weg, true)

    -- Packen und Auspacken muessen sich aufheben
    local register = {
        x = { spieler = "Kaos-Thunderstrike", gegenstand = 12345, zeit = 99 },
        y = { spieler = "Timo-Thunderstrike", gegenstand = 222, zeit = 100, weg = true },
    }
    local zurueck = A.Auspacken(A.Packen(register))
    gleich("Rundlauf Spieler",    zurueck.x and zurueck.x.spieler, "Kaos-Thunderstrike")
    gleich("Rundlauf Gegenstand", zurueck.x and zurueck.x.gegenstand, 12345)
    gleich("Rundlauf Zeit",       zurueck.x and zurueck.x.zeit, 99)
    gleich("Rundlauf Grabstein",  zurueck.y and zurueck.y.weg, true)
    gleich("kein Grabstein erfunden", zurueck.x and zurueck.x.weg, nil)

    -- Zerlegen: nichts darf verlorengehen, auch nicht am Rand
    local lang = string.rep("z", 501)
    local stuecke = A.Stuecke(lang, 100)
    gleich("Zahl der Stuecke", #stuecke, 6)
    gleich("wieder zusammengesetzt", table.concat(stuecke), lang)
    gleich("leerer Text ergibt kein Stueck", #A.Stuecke("", 100), 0)

    -- Ein genau passender Text darf kein leeres Reststueck erzeugen
    gleich("glatte Teilung", #A.Stuecke(string.rep("z", 200), 100), 2)
end

local function testNachziehen()
    -- Raid.lua ist nicht API-frei; offline gibt es sie nicht.
    if not (ns.Raid and ns.Raid.Nachziehen) then return end
    local Raid = ns.Raid

    -- Fassung 1: namen = Name -> Zahl der Bosse
    local alt = { start = 1, bosse = 3, namen = { Kaos = 3, Timo = 1 } }
    local neu, umgezogen = Raid.Nachziehen(alt, 99)

    gleich("alter Abend wird nachgezogen", umgezogen, true)
    gleich("namen ist danach weg", neu.namen, nil)
    gleich("voll Dabeier steht an Boss 3", neu.teilnahme[3].Kaos, true)
    gleich("Nachrücker steht nur an Boss 1", neu.teilnahme[1].Timo, true)
    gleich("Nachrücker steht nicht an Boss 2", neu.teilnahme[2].Timo, nil)

    -- Mehr Bosse gemeldet als der Abend hat: darf nicht ueberlaufen
    local krumm = Raid.Nachziehen({ bosse = 2, namen = { Kaos = 5 } }, 99)
    gleich("Zahl wird auf die Bosse gedeckelt", krumm.teilnahme[2].Kaos, true)
    gleich("kein Boss 3 erfunden", krumm.teilnahme[3], nil)

    -- Ein neuer Abend darf nicht angefasst werden
    local frisch = { start = 5, bosse = 0, teilnahme = {}, protokoll = {} }
    local _, nochmal = Raid.Nachziehen(frisch, 99)
    gleich("neuer Abend bleibt unberuehrt", nochmal, false)

    -- Fehlende Felder werden ergaenzt, damit nichts auf nil laeuft
    local nackt = Raid.Nachziehen({}, 99)
    gleich("start ergänzt",     nackt.start, 99)
    gleich("bosse ergänzt",     nackt.bosse, 0)
    gleich("teilnahme ergänzt", type(nackt.teilnahme), "table")
    gleich("erfolg ergänzt",    type(nackt.erfolg), "table")
end

local function testAnwesenheit()
    -- Im Schlachtzug stehen und dabei sein ist nicht dasselbe.
    local BT = "Der Schwarze Tempel"

    gleich("in derselben Zone zählt",
           Kern.IstDabei(true, BT, BT), true)
    gleich("andere Zone zählt nicht",
           Kern.IstDabei(true, "Shattrath", BT), false)
    gleich("offline zählt nicht",
           Kern.IstDabei(false, BT, BT), false)

    -- Unbekanntes darf nicht ausschliessen: lieber einer zu viel als
    -- einem Teilnehmer den Abend nehmen.
    gleich("unbekannte Zone zählt",
           Kern.IstDabei(true, nil, BT), true)
    gleich("leere Zone zählt",
           Kern.IstDabei(true, "", BT), true)
    gleich("ausserhalb einer Instanz wird nicht gefiltert",
           Kern.IstDabei(true, "Shattrath", nil), true)
    gleich("unbekannter Onlinestatus zählt",
           Kern.IstDabei(nil, BT, BT), true)
end

local function testDoppelbuchung()
    -- Haben mehrere Raidleiter das Addon, wuerde jede weitere Buchung auf
    -- das Ergebnis der vorherigen addieren. Der Stempel verhindert das.
    local jetzt = 1789000000
    local stunde = Kern.StundeAus(jetzt)

    local frisch = Kern.NeuesKonto(0)
    gleich("frisches Konto gilt als ungebucht",
           Kern.SchonGebucht(frisch, stunde), false)

    local eben = Kern.NeuesKonto(0)
    eben.gebucht = stunde
    gleich("gerade gebucht wird gesperrt",
           Kern.SchonGebucht(eben, stunde), true)

    local vorhin = Kern.NeuesKonto(0)
    vorhin.gebucht = stunde - 3
    gleich("vor drei Stunden gilt als derselbe Abend",
           Kern.SchonGebucht(vorhin, stunde), true)

    local gestern = Kern.NeuesKonto(0)
    gestern.gebucht = stunde - 24
    gleich("gestern ist ein anderer Abend",
           Kern.SchonGebucht(gestern, stunde), false)

    -- Der gekuerzte Stempel laeuft irgendwann ueber; das darf nicht
    -- faelschlich sperren oder freigeben.
    local ueberlauf = Kern.NeuesKonto(0)
    ueberlauf.gebucht = 99999
    gleich("Ueberlauf sperrt kurz danach",
           Kern.SchonGebucht(ueberlauf, 2), true)
    gleich("Ueberlauf gibt spaeter frei",
           Kern.SchonGebucht(ueberlauf, 50), false)

    gleich("Stunde ist fuenfstellig", Kern.StundeAus(jetzt) < 100000, true)
end

local function testGegenModell()
    -- Diese Erwartungswerte stehen so in berechnungen.py und im
    -- Regelwerk. Weichen sie ab, rechnet das Addon anders als das
    -- Dokument, an dem die Gilde nachrechnet.
    local VOLL, HALB, LOOT = 50, 25, 45

    local a = testkonto(600, 400, 0)
    for w = 1, 8 do simWoche(a, w, 0, 0) end
    nahe("abwesend, 8 Wochen", Kern.Prio(a), 1.50)

    local b = testkonto(600, 400, 0)
    for w = 1, 8 do simWoche(b, w, VOLL, LOOT) end
    nahe("dabei mit Loot, 8 Wochen", Kern.Prio(b), 1.27)

    local c = testkonto(600, 400, 0)
    for w = 1, 8 do simWoche(c, w, VOLL, 0) end
    nahe("dabei ohne Loot, 8 Wochen", Kern.Prio(c), 3.15)

    -- Abmeldung mit halbem Satz, Woche fuer Woche (§ 2, Deckel-Tabelle)
    local soll = { 1.57, 1.65, 1.73, 1.83 }
    local d = testkonto(600, 400, 0)
    for w = 1, 4 do
        simWoche(d, w, HALB, 0)
        nahe("abgemeldet nach Woche " .. w, Kern.Prio(d), soll[w])
    end

    -- Was ein Platzfaktor kostet, ausgehend von Prio 1.50 (§ 3)
    local basis = 60
    local faelle = {
        { "Zweihandwaffe", 3.0, 1.03 },
        { "Schmuckstueck", 2.0, 1.15 },
        { "Ruestungsteil", 1.5, 1.22 },
        { "Ring",          1.0, 1.30 },
    }
    for _, f in ipairs(faelle) do
        local k = testkonto(600, 400, 0)
        Kern.VergabeBuchen(k, f[2] * basis, false)
        nahe("Prio nach " .. f[1], Kern.Prio(k), f[3])
    end
end

-- =====================================================================
--  Lauf
-- =====================================================================

function Tests.Alle(ausgeben)
    gut, schlecht, meldungen = 0, 0, {}

    testVerfall()
    testAbwesenheit()
    testEinsatz()
    testRuestwert()
    testNeulinge()
    testRangfolge()
    testNotiz()
    testVergabe()
    testNachziehen()
    testAnwesenheit()
    testDoppelbuchung()
    testGegenModell()

    if ausgeben ~= false then
        for _, m in ipairs(meldungen) do print(m) end
        print(string.format("Loot-Ordnung: %d Prüfungen, %d bestanden, %d fehlgeschlagen",
            gut + schlecht, gut, schlecht))
    end
    return gut, schlecht, meldungen
end

-- Offline direkt loslaufen; im Spiel wartet es auf /lo test.
if not rawget(_G, "CreateFrame") then
    local _, fehler = Tests.Alle()
    os.exit(fehler == 0 and 0 or 1)
end

return ns
