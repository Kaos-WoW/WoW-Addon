--[[----------------------------------------------------------------------
    Tests.lua  —  Pruefstand fuer Kern.lua

    ⭐ **Erwartungswerte werden hergeleitet, nicht abgeschrieben.** Wer als
    Sollwert einsetzt, was die Funktion ohnehin liefert, prueft nichts.
    Diese Lehre hat das Vorgaengerprojekt einen Abend gekostet: ein Test
    liess einen echten Regelverstoss durch, weil der Sollwert aus der
    Implementierung stammte.

    Laeuft im Spiel ueber /lh test und ohne Client in jedem Lua.
------------------------------------------------------------------------]]

local _, ns = ...
ns = ns or {}

local Tests = {}
ns.Tests = Tests

local Kern = ns.Kern

local gut, schlecht, meldungen

local function gleich(was, ist, soll)
    if ist == soll then
        gut = gut + 1
    else
        schlecht = schlecht + 1
        meldungen[#meldungen + 1] = string.format(
            "|cffff5555FEHLT|r %s: %s statt %s", was, tostring(ist), tostring(soll))
    end
end

-- =====================================================================

local function testZaehlt()
    gleich("vollstaendiger Eintrag zaehlt",
        Kern.Zaehlt({ awardedTo = "Kaos", timestamp = 100 }), true)

    -- Entzaubertes ging an niemanden
    gleich("entzaubert zaehlt nicht",
        Kern.Zaehlt({ awardedTo = Kern.ENTZAUBERT, timestamp = 100 }), false)

    gleich("Bonus-Beute zaehlt nicht",
        Kern.Zaehlt({ awardedTo = "Kaos", timestamp = 100, isBonusLoot = true }), false)

    gleich("ohne Gewinner zaehlt nicht",
        Kern.Zaehlt({ timestamp = 100 }), false)

    gleich("ohne Zeitstempel zaehlt nicht",
        Kern.Zaehlt({ awardedTo = "Kaos" }), false)

    gleich("Unfug zaehlt nicht", Kern.Zaehlt("nein"), false)
end

local function testNamen()
    -- Gargul schreibt mal mit, mal ohne Realm. Beides muss derselbe
    -- Spieler sein, sonst steht er zweimal in der Liste.
    gleich("mit Realm", Kern.Schluessel("Kaos-Thunderstrike"), "kaos")
    gleich("ohne Realm", Kern.Schluessel("Kaos"), "kaos")
    gleich("Grossschreibung egal", Kern.Schluessel("KAOS"), "kaos")
    gleich("leer ergibt nichts", Kern.Schluessel(""), nil)

    gleich("Anzeigename ohne Realm", Kern.Anzeigename("kaos-Thunderstrike"), "Kaos")
    gleich("Anzeigename gross", Kern.Anzeigename("timo"), "Timo")

    -- ⚠️ Forever kennt Nachnamen: „Yondaime Kaos" ist EIN Charakter. Der
    -- Realm haengt weiterhin mit Bindestrich an, das Leerzeichen gehoert
    -- zum Namen und darf nicht abgeschnitten werden.
    gleich("Nachname bleibt erhalten",
           Kern.Schluessel("Yondaime Kaos"), "yondaime kaos")
    gleich("Nachname mit Realm",
           Kern.Schluessel("Yondaime Kaos-ClassicBetaPvE2"), "yondaime kaos")
    gleich("Nachname wird angezeigt",
           Kern.Anzeigename("yondaime Kaos-ClassicBetaPvE2"), "Yondaime Kaos")

    -- Und zwei Charaktere mit gleichem Vornamen bleiben getrennt
    gleich("Vorname allein ist ein anderer Spieler",
           Kern.Schluessel("Yondaime") == Kern.Schluessel("Yondaime Kaos"), false)
end

local function testBilanz()
    local H = {
        a = { awardedTo = "Kaos",              timestamp = 1000 },
        b = { awardedTo = "Kaos-Thunderstrike", timestamp = 2000 },
        c = { awardedTo = "Kaos",              timestamp = 3000, OS = true },
        d = { awardedTo = "Timo",              timestamp = 1500 },
        e = { awardedTo = Kern.ENTZAUBERT,     timestamp = 4000 },
    }

    local liste, gesamt, aeltester = Kern.Bilanz(H, 0)

    gleich("Entzaubertes faellt raus", gesamt, 4)
    gleich("zwei Spieler", #liste, 2)
    gleich("mit und ohne Realm ist ein Spieler", liste[1].name, "Kaos")
    gleich("Hauptbedarf gezaehlt", liste[1].haupt, 2)
    gleich("Zweitbedarf getrennt", liste[1].zweit, 1)
    gleich("aeltester Zeitstempel", aeltester, 1000)

    -- ⭐ „Zuletzt" muss dem Hauptbedarf folgen: Der Zweitbedarf bei 3000
    -- ist juenger, sagt ueber den Anspruch aber nichts aus.
    gleich("zuletzt ignoriert Zweitbedarf", liste[1].letzte, 2000)

    -- Sortierung nach Hauptbedarf
    gleich("mehr Hauptbedarf steht oben", liste[1].haupt > liste[2].haupt, true)

    -- Zeitfenster
    local nurNeu = Kern.Bilanz(H, 1600)
    gleich("Zeitfenster schneidet ab", #nurNeu, 1)
    gleich("im Fenster nur ein Hauptstueck", nurNeu[1].haupt, 1)

    -- Wer ausschliesslich Zweitbedarf hat, darf kein „zuletzt" bekommen
    local nurZweit = Kern.Bilanz({ x = { awardedTo = "Lina", timestamp = 50, OS = true } }, 0)
    gleich("nur Zweitbedarf: kein Hauptbedarf", nurZweit[1].haupt, 0)
    gleich("nur Zweitbedarf: kein zuletzt",     nurZweit[1].letzte, 0)

    gleich("leere Historie", #Kern.Bilanz({}, 0), 0)
    gleich("Unfug ergibt leere Liste", #Kern.Bilanz("nein", 0), 0)
end

local function testPflichtnamen()
    -- ⭐ Wer nichts bekommen hat, steht in Garguls Historie nicht — und ist
    -- beim Wurf der Interessanteste. Er muss trotzdem erscheinen.
    local H = { a = { awardedTo = "Kaos", timestamp = 1000 } }

    local liste = Kern.Bilanz(H, 0, { "Timo", "Kaos" })
    gleich("Unbeschenkter taucht auf", #liste, 2)

    local timo
    for _, z in ipairs(liste) do if z.name == "Timo" then timo = z end end
    gleich("Unbeschenkter hat null", timo and timo.haupt, 0)
    gleich("Unbeschenkter hat kein zuletzt", timo and timo.letzte, 0)

    -- Wer schon drin ist, darf nicht doppelt erscheinen
    local n = 0
    for _, z in ipairs(liste) do if z.name == "Kaos" then n = n + 1 end end
    gleich("kein Doppeleintrag", n, 1)

    -- Pflichtnamen aendern die Zahl der Vergaben nicht
    local _, gesamt = Kern.Bilanz(H, 0, { "Timo" })
    gleich("Pflichtnamen zaehlen keine Vergabe", gesamt, 1)
end

local function testWurfReihenfolge()
    local liste = {
        { name = "Viel",   haupt = 9, zweit = 0, letzte = 500 },
        { name = "Wenig",  haupt = 1, zweit = 0, letzte = 400 },
        { name = "Nichts", haupt = 0, zweit = 0, letzte = 0   },
        { name = "Aussen", haupt = 4, zweit = 0, letzte = 300 },
    }
    local wuerfelt = { Viel = true, Wenig = true, Nichts = true }
    Kern.WurfReihenfolge(liste, function(n) return wuerfelt[n] == true end)

    -- Wuerfelnde oben, davon die mit den wenigsten Stuecken zuerst
    gleich("ohne Stueck ganz oben", liste[1].name, "Nichts")
    gleich("dann der mit einem",     liste[2].name, "Wenig")
    gleich("dann der mit neun",      liste[3].name, "Viel")
    gleich("Nichtwuerfler unten",    liste[4].name, "Aussen")

    -- Ohne laufenden Wurf bleibt die Liste, wie sie ist
    local unveraendert = { { name = "A" }, { name = "B" } }
    gleich("ohne Wurf unveraendert", Kern.WurfReihenfolge(unveraendert, nil)[1].name, "A")
end

local function testSpieler()
    local H = {
        a = { awardedTo = "Kaos", timestamp = 1000 },
        b = { awardedTo = "Kaos", timestamp = 3000, OS = true },
        c = { awardedTo = "Timo", timestamp = 2000 },
    }

    local liste = Kern.Spieler(H, "kaos-Thunderstrike", 0)
    gleich("nur dieser Spieler", #liste, 2)
    gleich("neueste zuerst", liste[1].zeit, 3000)
    gleich("Zweitbedarf gekennzeichnet", liste[1].zweit, true)
    gleich("Hauptbedarf nicht gekennzeichnet", liste[2].zweit, false)

    gleich("unbekannter Spieler", #Kern.Spieler(H, "Niemand", 0), 0)
end

local function testMuster()
    -- Die echten Vorlagen aus dem Forever-Client (gemessen 25.09.2026).
    local rollen = Kern.Muster("%s rolls %d (%d-%d)")
    local name, wurf, min, max = ("Yondaime Kaos rolls 42 (1-100)"):match(rollen)

    -- ⭐ Der entscheidende Fall: Nachnamen enthalten ein Leerzeichen.
    gleich("Wurf: voller Name", name, "Yondaime Kaos")
    gleich("Wurf: Zahl",        wurf, "42")
    gleich("Wurf: Untergrenze", min, "1")
    gleich("Wurf: Obergrenze",  max, "100")

    local beute = Kern.Muster("%s receives loot: %s.")
    local wer, was = ("Yondaime Kaos receives loot: [Warglaive]."):match(beute)
    gleich("Beute: Empfaenger", wer, "Yondaime Kaos")
    gleich("Beute: Gegenstand", was, "[Warglaive]")

    -- Ein Punkt im Gegenstandsnamen darf das Muster nicht zerlegen
    local _, punkt = ("Kaos receives loot: [Dr. Boom]."):match(beute)
    gleich("Punkt im Namen", punkt, "[Dr. Boom]")

    -- Mehrfach-Beute traegt zusaetzlich die Anzahl
    local viele = Kern.Muster("%s receives loot: %sx%d.")
    local w2, g2, anzahl = ("Kaos receives loot: [Stoff]x5."):match(viele)
    gleich("Mehrfach: Empfaenger", w2, "Kaos")
    gleich("Mehrfach: Gegenstand", g2, "[Stoff]")
    gleich("Mehrfach: Anzahl",     anzahl, "5")

    -- Eigene Beute nennt keinen Namen
    local selbst = Kern.Muster("You receive loot: %s")
    gleich("Eigene Beute", ("You receive loot: [Madness]"):match(selbst), "[Madness]")

    gleich("Unfug ergibt kein Muster", Kern.Muster(nil), nil)
end

local function testBedarfsart()
    -- Die Gilde wuerfelt 100 fuer Haupt-, 50 fuer Zweitbedarf.
    gleich("1-100 ist Hauptbedarf", Kern.Bedarfsart(1, 100), "haupt")
    gleich("1-50 ist Zweitbedarf",  Kern.Bedarfsart(1, 50), "zweit")

    -- ⚠️ Alles andere ist kein Bedarfswurf. Lieber nichts erfassen als
    -- etwas Falsches erfassen.
    gleich("normaler Wurf zaehlt nicht", Kern.Bedarfsart(1, 1000), nil)
    gleich("Spasswurf zaehlt nicht",     Kern.Bedarfsart(1, 20), nil)
    gleich("verschobener Bereich",       Kern.Bedarfsart(50, 100), nil)
    gleich("Text statt Zahl",            Kern.Bedarfsart("eins", "hundert"), nil)
end

local function testRaidtage()
    -- Zwei Vergaben am selben Tag sind ein Raidtag.
    local tagOf = function(t) return math.floor(t / Kern.TAG) end
    local H = {
        a = { awardedTo = "Kaos", timestamp = 1 * Kern.TAG + 100 },
        b = { awardedTo = "Timo", timestamp = 1 * Kern.TAG + 200 },
        c = { awardedTo = "Kaos", timestamp = 5 * Kern.TAG },
    }
    gleich("zwei verschiedene Tage", Kern.Raidtage(H, 0, tagOf), 2)
    gleich("ohne Tagesfunktion nichts", Kern.Raidtage(H, 0, nil), 0)
end

local function testSeit()
    gleich("ohne Wochen ab null", Kern.Seit(1000000, nil), 0)
    gleich("null Wochen ab null",  Kern.Seit(1000000, 0), 0)
    gleich("vier Wochen zurueck",  Kern.Seit(1000000, 4), 1000000 - 4 * Kern.WOCHE)
end

-- =====================================================================

function Tests.Alle(ausgeben)
    gut, schlecht, meldungen = 0, 0, {}

    testZaehlt()
    testNamen()
    testBilanz()
    testPflichtnamen()
    testWurfReihenfolge()
    testSpieler()
    testMuster()
    testBedarfsart()
    testRaidtage()
    testSeit()

    if ausgeben ~= false then
        for _, m in ipairs(meldungen) do print(m) end
        print(string.format("|cff1B6B57Loot-Historie|r: %d Prüfungen, %d bestanden, %d fehlgeschlagen",
            gut + schlecht, gut, schlecht))
    end
    return gut, schlecht
end

return ns
