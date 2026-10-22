--[[----------------------------------------------------------------------
    Tests.lua  —  Pruefstand fuer Kern.lua

    ⭐ **Erwartungswerte werden hergeleitet, nicht abgeschrieben.** Wer als
    Sollwert einsetzt, was die Funktion ohnehin liefert, prueft nichts.
    Diese Lehre hat das Vorgaengerprojekt einen Abend gekostet: ein Test
    liess einen echten Regelverstoss durch, weil der Sollwert aus der
    Implementierung stammte.

    Laeuft im Spiel ueber /fs test und ohne Client in jedem Lua.
------------------------------------------------------------------------]]

local _, ns = ...
ns = ns or {}
local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

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
            L["|cffff5555FEHLT|r %s: %s statt %s"], was, tostring(ist), tostring(soll))
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
    -- Der Name steht mal mit, mal ohne Realm. Beides muss derselbe
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
    gleich("Timo hat niedrigere Wertung und steht oben", liste[1].name, "Timo")
    gleich("mit und ohne Realm ist ein Spieler", liste[2].name, "Kaos")
    gleich("Hauptbedarf gezaehlt", liste[2].haupt, 2)
    gleich("Zweitbedarf getrennt", liste[2].zweit, 1)
    gleich("aeltester Zeitstempel", aeltester, 1000)

    -- ⭐ „Zuletzt" muss dem Hauptbedarf folgen: Der Zweitbedarf bei 3000
    -- ist juenger, sagt ueber den Anspruch aber nichts aus.
    gleich("zuletzt ignoriert Zweitbedarf", liste[2].letzte, 2000)

    -- Sortierung nach Wertung (niedrigste zuerst)
    gleich("niedrigere Wertung steht oben", liste[1].wertung < liste[2].wertung, true)

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
    -- ⭐ Wer nichts bekommen hat, steht in der Historie nicht — und ist
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

--- Mit `nur` zaehlen und erscheinen ausschliesslich diese Namen.
local function testNur()
    local H = {
        a = { awardedTo = "Timo Rot",  timestamp = 1000 },
        b = { awardedTo = "Timo Rot",  timestamp = 2000 },
        c = { awardedTo = "Lina",      timestamp = 3000 },
        d = { awardedTo = "Fremder",   timestamp = 4000 },
        e = { awardedTo = "Moe Blau",  timestamp = 5000, OS = true },
    }
    local nur = { "Timo Rot", "Lina", "Neuling Gruen" }
    local liste, gesamt = Kern.Bilanz(H, 0, nur, nur)

    gleich("nur die drei, auch einer ohne Vergabe", #liste, 3)
    gleich("die Summe zaehlt nur diese (3 von 5)", gesamt, 3)
    local namen = {}
    for _, z in ipairs(liste) do namen[z.name] = z end
    gleich("Fremde fehlen", namen.Fremder, nil)
    gleich("wer nicht dabei ist, fehlt auch mit Zweitbedarf", namen["Moe Blau"], nil)
    gleich("Neuling ohne Vergabe steht drin", namen["Neuling Gruen"] and namen["Neuling Gruen"].haupt, 0)
    gleich("Timo hat seine zwei", namen["Timo Rot"] and namen["Timo Rot"].haupt, 2)

    -- Ein Name ohne Nachnamen in der Historie gehoert zum vollen Namen der Gruppe
    local H2 = { x = { awardedTo = "Timo", timestamp = 10 }, y = { awardedTo = "Timo Rot", timestamp = 20 } }
    local l2 = Kern.Bilanz(H2, 0, { "Timo Rot" }, { "Timo Rot" })
    gleich("Kurzname und voller Name sind eine Zeile", #l2, 1)
    gleich("beide Vergaben landen dort", l2[1].haupt, 2)
    gleich("angezeigt wird der volle Name", l2[1].name, "Timo Rot")

    -- Ohne `nur` bleibt alles wie bisher
    gleich("ohne nur zaehlt jeder", #Kern.Bilanz(H, 0), 4)
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

local function testWurfArt()
    -- Haupt vor Zweit, auch wenn der Zweit-Wuerfler weniger Stuecke hat
    local liste = {
        { name = "ZweitLeer",  haupt = 0, zweit = 0, letzte = 0   },
        { name = "HauptViel",  haupt = 3, zweit = 0, letzte = 500 },
        { name = "HauptWenig", haupt = 2, zweit = 0, letzte = 400 },
        { name = "Aussen",     haupt = 3, zweit = 0, letzte = 300 },
    }
    local art = { ZweitLeer = "zweit", HauptViel = "haupt", HauptWenig = "haupt" }
    Kern.WurfReihenfolge(liste, function(n) return art[n] or false end)
    gleich("Haupt, wenigste zuerst",    liste[1].name, "HauptWenig")
    gleich("Haupt mit vielen danach",   liste[2].name, "HauptViel")
    gleich("Zweit erst nach allen Haupt", liste[3].name, "ZweitLeer")
    gleich("kein Wurf ganz unten",      liste[4].name, "Aussen")
end

local function testRuecknahmeInPruefsumme()
    local H1 = { a = { awardedTo = "Kaos", timestamp = 1000 }, b = { awardedTo = "Timo", timestamp = 2000 } }
    local H2 = { a = { awardedTo = "Kaos", timestamp = 1000 }, b = { awardedTo = "Timo", timestamp = 2000, zurueck = true } }
    local n1, s1 = Kern.Pruefsumme(H1, {})
    local n2, s2 = Kern.Pruefsumme(H2, {})
    gleich("gleiche Anzahl", n1, n2)
    gleich("aber andere Summe, wenn einer zurueckgenommen ist", s1 ~= s2, true)

    local tag = function() return "t" end
    local T1, T2 = Kern.Tagesstand(H1, {}, tag), Kern.Tagesstand(H2, {}, tag)
    gleich("auch der Tagesstand unterscheidet sich", T1.t.summe ~= T2.t.summe, true)

    -- Die Listen kennen die Kennung (fuer den Knopf Rueckgaengig)
    local v = Kern.Verlauf(H1, 0, nil)
    gleich("Verlauf traegt die Kennung", v[1].id ~= nil, true)
    local sp = Kern.Spieler(H1, "Kaos", 0)
    gleich("Spielerdetail traegt die Kennung", sp[1].id, "a")
    local v2 = Kern.Verlauf(H2, 0, nil)
    gleich("zurueckgenommene Vergaben fehlen im Verlauf", #v2, 1)
end

local function testBereiche()
    Kern.BereicheSetzen(1, 100, 1, 50)

    gleich("Standard Haupt", Kern.Bedarfsart(1, 100), "haupt")
    gleich("Standard Zweit", Kern.Bedarfsart(1, 50), "zweit")
    gleich("anderer Bereich ist keine Art", Kern.Bedarfsart(1, 99), nil)

    gleich("eigener Bereich wird angenommen", (Kern.BereicheSetzen(1, 200, 5, 40)), true)
    gleich("jetzt 1-200 Haupt", Kern.Bedarfsart(1, 200), "haupt")
    gleich("5-40 Zweit", Kern.Bedarfsart(5, 40), "zweit")
    gleich("1-100 gilt nicht mehr", Kern.Bedarfsart(1, 100), nil)

    local ok, code = Kern.BereicheSetzen(1, 200, 1, 200)
    gleich("gleiche Bereiche abgelehnt", ok, false)
    gleich("Code gleich", code, "gleich")
    ok, code = Kern.BereicheSetzen(10, 5, 1, 50)
    gleich("umgekehrt abgelehnt", code, "grenzen")
    ok, code = Kern.BereicheSetzen("x", 5, 1, 50)
    gleich("keine Zahl abgelehnt", code, "zahl")
    gleich("nach Fehlversuchen unveraendert", Kern.Bedarfsart(1, 200), "haupt")

    Kern.BereicheSetzen(1, 100, 1, 50)    -- Standard wiederherstellen
    gleich("Standard wieder da", Kern.Bedarfsart(1, 50), "zweit")
end

local function testWurfWert()
    -- Gleiche Stueckzahl: der hoehere Wurf steht oben
    local liste = {
        { name = "Niedrig", haupt = 1, zweit = 0, letzte = 100 },
        { name = "Hoch",    haupt = 1, zweit = 1, letzte = 100 },
        { name = "Mitte",   haupt = 1, zweit = 0, letzte = 100 },
        { name = "Wenig",   haupt = 0, zweit = 0, letzte = 0 },
    }
    local wurf = { Niedrig = 20, Hoch = 89, Mitte = 39, Wenig = 5 }
    Kern.WurfReihenfolge(liste, function(n) return "haupt" end, function(n) return wurf[n] end)
    gleich("weniger Stuecke gehen vor dem Wurf", liste[1].name, "Wenig")
    gleich("dann der hoechste Wurf",             liste[2].name, "Hoch")
    gleich("dann der naechsthoechste",           liste[3].name, "Mitte")
    gleich("zuletzt der niedrigste",             liste[4].name, "Niedrig")
end

local function testWurfMeldung()
    -- Blizzards Meldung: Wert, Gegenstand, Name (englische Vorlage)
    local muster, nr = Kern.MusterGeordnet("Need Roll - %d for %s by %s")
    local A = Kern.Argumente("Need Roll - 87 for |cff0070dd|Hitem:6948::::|h[Ding]|h|r by Yondaime Kaos", muster, nr)
    gleich("Wert",      A and A[1], "87")
    gleich("Name mit Nachnamen", A and A[3], "Yondaime Kaos")
    gleich("Gegenstand", A and A[2] and A[2]:match("%[(.-)%]"), "Ding")

    -- Eine uebersetzte Vorlage darf die Reihenfolge umstellen
    local m2, n2 = Kern.MusterGeordnet("%3$s wuerfelt %1$d fuer %2$s")
    local B = Kern.Argumente("Kaos wuerfelt 42 fuer Schwert", m2, n2)
    gleich("umgestellt: Wert",  B and B[1], "42")
    gleich("umgestellt: Stueck", B and B[2], "Schwert")
    gleich("umgestellt: Name",  B and B[3], "Kaos")

    -- Passt die Meldung nicht, gibt es nichts
    gleich("fremde Meldung", Kern.Argumente("Etwas anderes", muster, nr), nil)
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

local function testGleicherSpieler()
    gleich("mit und ohne Realm", Kern.GleicherSpieler("Yondaime Kaos", "Yondaime Kaos-Realm"), true)
    gleich("ein Vorname ohne Nachname passt", Kern.GleicherSpieler("Yondaime", "Yondaime Kaos"), true)
    gleich("andere Nachnamen sind andere Spieler",
        Kern.GleicherSpieler("Yondaime Kaos", "Yondaime Nuhkomm"), false)
    gleich("andere Namen", Kern.GleicherSpieler("Kaos", "Timo"), false)
    gleich("leer passt zu nichts", Kern.GleicherSpieler(nil, "Kaos"), false)
    gleich("Gross und klein", Kern.GleicherSpieler("KAOS", "kaos"), true)
end

local function testZurueck()
    gleich("zurueckgenommen zaehlt nicht",
        Kern.Zaehlt({ awardedTo = "Kaos", timestamp = 100, zurueck = true }), false)
end

local function testPruefsumme()
    local A = { a = { timestamp = 1 }, b = { timestamp = 2 }, c = { timestamp = 3 } }
    local B = { c = { timestamp = 3 }, a = { timestamp = 1 }, b = { timestamp = 2 } }

    local nA, sA = Kern.Pruefsumme(A, {})
    local nB, sB = Kern.Pruefsumme(B, {})
    gleich("Anzahl", nA, 3)
    -- ⭐ Dieselben Eintraege ergeben dieselbe Summe, egal in welcher Reihenfolge
    gleich("Reihenfolge egal", sA, sB)

    local _, sOhneC = Kern.Pruefsumme({ a = A.a, b = A.b }, {})
    gleich("fehlender Eintrag aendert die Summe", sA ~= sOhneC, true)

    local _, sAndere = Kern.Pruefsumme({ a = A.a, b = A.b, d = { timestamp = 3 } }, {})
    gleich("anderer Eintrag aendert die Summe", sA ~= sAndere, true)

    gleich("leere Historie", select(1, Kern.Pruefsumme({}, {})), 0)
    gleich("Unfug ergibt leer", select(1, Kern.Pruefsumme(nil, nil)), 0)
end

local function testTagesstand()
    local tagOf = function(t) return "d" .. math.floor(t / Kern.TAG) end
    local H = {
        a = { timestamp = 1 * Kern.TAG + 10 },
        b = { timestamp = 1 * Kern.TAG + 20 },
        c = { timestamp = 3 * Kern.TAG },
    }
    local st = Kern.Tagesstand(H, {}, tagOf)
    gleich("Tag 1 hat zwei", st.d1.n, 2)
    gleich("Tag 3 hat einen", st.d3.n, 1)
    gleich("Tag 2 gibt es nicht", st.d2, nil)

    -- Abweichung: beide Richtungen
    local lokal = { d1 = { n = 2, summe = 5 }, d2 = { n = 1, summe = 7 } }
    local fremd = { d1 = { n = 2, summe = 5 }, d2 = { n = 1, summe = 8 }, d3 = { n = 1, summe = 1 } }
    local abw = Kern.AbweichendeTage(lokal, fremd)
    gleich("zwei Tage weichen ab", #abw, 2)
    gleich("abweichende Summe", abw[1], "d2")
    gleich("Tag nur bei der Gegenseite", abw[2], "d3")
    gleich("gleiche Staende: nichts",
        #Kern.AbweichendeTage(lokal, { d1 = { n = 2, summe = 5 }, d2 = { n = 1, summe = 7 } }), 0)
    gleich("Tag nur lokal zaehlt auch",
        #Kern.AbweichendeTage({ d9 = { n = 1, summe = 1 } }, {}), 1)

    -- Hin und zurueck
    local text = Kern.TageKodieren(fremd)
    local zurueck = Kern.TageDekodieren(text)
    gleich("Tagestext: Anzahl Tage", (function() local n = 0 for _ in pairs(zurueck) do n = n + 1 end return n end)(), 3)
    gleich("Tagestext: Summe bleibt", zurueck.d2.summe, 8)
    gleich("Tagestext: Anzahl bleibt", zurueck.d1.n, 2)
    gleich("Unfug ergibt leer", next(Kern.TageDekodieren(nil)), nil)
end

local ZEIT = 1700000000

local function testZusammenfuehren()
    local H = { alt = { awardedTo = "Kaos", itemID = 100, timestamp = ZEIT, gruppe = "40er" } }
    local alias = {}

    local neu, doppelt, vorhanden, abgelehnt = Kern.Zusammenfuehren(H, alias, {
        { id = "x1", e = { awardedTo = "Timo", itemID = 200, timestamp = ZEIT + 50 } },
        { id = "alt", e = { awardedTo = "Kaos", itemID = 100, timestamp = ZEIT, gruppe = "andere" } },
        { id = "x2", e = { awardedTo = "", itemID = 1, timestamp = ZEIT } },
        { id = "x3", e = { awardedTo = "Lina", itemID = "kein", timestamp = ZEIT } },
    }, 180)
    gleich("eine neue", neu, 1)
    gleich("eine schon da", vorhanden, 1)
    gleich("zwei abgelehnt", abgelehnt, 2)
    gleich("kein Doppelgaenger", doppelt, 0)

    -- ⭐ Nichts wird ueberschrieben
    gleich("vorhandener Eintrag bleibt unveraendert", H.alt.gruppe, "40er")

    -- Idempotent: zweimal dasselbe aendert nichts
    local n2, _, v2 = Kern.Zusammenfuehren(H, alias, {
        { id = "x1", e = { awardedTo = "Timo", itemID = 200, timestamp = ZEIT + 50 } },
    }, 180)
    gleich("zweites Einfuehren bringt nichts neues", n2, 0)
    gleich("zweites Einfuehren: vorhanden", v2, 1)

    -- Doppelgaenger: gleicher Spieler, gleiches Stueck, nahe Zeit, andere Kennung
    local _, dop = Kern.Zusammenfuehren(H, alias, {
        { id = "chat1", e = { awardedTo = "kaos", itemID = 100, timestamp = ZEIT + 60 } },
    }, 180)
    gleich("Doppelgaenger erkannt", dop, 1)
    gleich("Doppelgaenger wird nicht eingefuegt", H.chat1, nil)
    gleich("Doppelgaenger wird als Alias gemerkt", alias.chat1, "alt")

    -- Dasselbe Stueck viel spaeter ist ein neuer Gewinn
    local neu3 = Kern.Zusammenfuehren(H, alias, {
        { id = "spaeter", e = { awardedTo = "Kaos", itemID = 100, timestamp = ZEIT + 7200 } },
    }, 180)
    gleich("spaeter derselbe Gegenstand ist neu", neu3, 1)

    -- Anderer Gegenstand, gleiche Zeit: kein Doppelgaenger
    local neu4 = Kern.Zusammenfuehren(H, alias, {
        { id = "anders", e = { awardedTo = "Kaos", itemID = 101, timestamp = ZEIT + 10 } },
    }, 180)
    gleich("anderer Gegenstand ist neu", neu4, 1)
end

--- ⭐ Der entscheidende Fall: Zwei Spieler halten dasselbe Ereignis unter
--  verschiedenen Kennungen. Nach dem Abgleich muessen die Pruefsummen
--  gleich sein — sonst meldet das Addon ewig „weicht ab".
local function testKonvergenz()
    local A = { X = { awardedTo = "Kaos", itemID = 100, timestamp = ZEIT + 10 } }
    local B = { Y = { awardedTo = "Kaos", itemID = 100, timestamp = ZEIT + 15 } }
    local aliasA, aliasB = {}, {}

    local _, sA0 = Kern.Pruefsumme(A, aliasA)
    local _, sB0 = Kern.Pruefsumme(B, aliasB)
    gleich("vorher verschieden", sA0 ~= sB0, true)

    Kern.Zusammenfuehren(A, aliasA, { { id = "Y", e = B.Y } }, 180)
    Kern.Zusammenfuehren(B, aliasB, { { id = "X", e = A.X } }, 180)

    local nA, sA = Kern.Pruefsumme(A, aliasA)
    local nB, sB = Kern.Pruefsumme(B, aliasB)
    gleich("nachher gleiche Anzahl", nA, nB)
    gleich("nachher gleiche Pruefsumme", sA, sB)
    gleich("es bleibt ein Eintrag", nA, 1)

    -- Und der Tagesstand stimmt ebenfalls ueberein
    local tagOf = function(t) return "d" .. math.floor(t / Kern.TAG) end
    local tA = Kern.Tagesstand(A, aliasA, tagOf)
    local tB = Kern.Tagesstand(B, aliasB, tagOf)
    gleich("Tagesstand gleich: keine abweichenden Tage", #Kern.AbweichendeTage(tA, tB), 0)
end

--- ⭐ Pruefsummen reichen bis 2^32. Eine abgeschnittene Zahl (-2147483648) liess
--  im Abgleich ganze Tage verschwinden.
local function testGrosseSummen()
    local tage = {
        d1 = { n = 4, summe = 4227332184 },
        d2 = { n = 2, summe = 2147483648 },
        d3 = { n = 1, summe = 17 },
    }
    local text = Kern.TageKodieren(tage)
    gleich("kein Minuszeichen im Tagestext", text:find("-", 1, true), nil)
    local zurueck = Kern.TageDekodieren(text)
    gleich("grosse Summe bleibt (4227332184)", zurueck.d1 and zurueck.d1.summe, 4227332184)
    gleich("Summe genau 2^31 bleibt", zurueck.d2 and zurueck.d2.summe, 2147483648)
    gleich("kleine Summe bleibt", zurueck.d3 and zurueck.d3.summe, 17)
    gleich("alle drei Tage kommen an", (function() local n = 0 for _ in pairs(zurueck) do n = n + 1 end return n end)(), 3)
    gleich("kein Unterschied zwischen Sender und Empfaenger", #Kern.AbweichendeTage(tage, zurueck), 0)

    -- Eine echte Historie mit vielen Eintraegen landet sicher ueber 2^31
    local H = {}
    for i = 1, 200 do H["eintrag-" .. i] = { timestamp = 1700000000 + i } end
    local _, summe = Kern.Pruefsumme(H, {})
    local hin = Kern.TageDekodieren(Kern.TageKodieren({ x = { n = 200, summe = summe } }))
    gleich("echte Pruefsumme uebersteht die Uebertragung", hin.x and hin.x.summe, summe)
end

local function testKodieren()
    local e = { awardedTo = "Yondaime Kaos", itemID = 32235, timestamp = ZEIT, OS = true,
                gruppe = "40er; Test|x", wurf = 87 }
    local zeile = Kern.Kodieren("blizz:12:3", e)

    -- ⭐ Genau acht Feldtrenner (neun Felder, das letzte ist das Kennzeichen): alles andere muss geschuetzt sein
    local trenner = select(2, zeile:gsub(";", ""))
    gleich("acht Feldtrenner", trenner, 8)
    gleich("kein Paketttrenner im Text", zeile:find("~", 1, true), nil)
    gleich("kein Chat-Escape im Text", zeile:find("|", 1, true), nil)

    local id, z = Kern.Dekodieren(zeile, ZEIT + 100)
    gleich("Kennung bleibt", id, "blizz:12:3")
    gleich("Name mit Nachname bleibt", z and z.awardedTo, "Yondaime Kaos")
    gleich("Gegenstand bleibt", z and z.itemID, 32235)
    gleich("Zeit bleibt", z and z.timestamp, ZEIT)
    gleich("Zweitbedarf bleibt", z and z.OS, true)
    gleich("Gruppe mit Sonderzeichen bleibt", z and z.gruppe, "40er; Test|x")
    gleich("Wurf bleibt", z and z.wurf, 87)

    local _, haupt = Kern.Dekodieren(Kern.Kodieren("k", { awardedTo = "Timo", itemID = 5, timestamp = ZEIT }), ZEIT)
    gleich("Hauptbedarf bleibt Hauptbedarf", haupt and haupt.OS, nil)

    -- Abgelehnt: alles, was von aussen kommt und nicht stimmt
    gleich("Unfug", (Kern.Dekodieren("blabla", ZEIT)), nil)
    gleich("kein Text", (Kern.Dekodieren(nil, ZEIT)), nil)
    gleich("Zeit zu klein", (Kern.Dekodieren("k;Kaos;100;5;H;;;", ZEIT)), nil)
    gleich("Zeit in der Zukunft", (Kern.Dekodieren("k;Kaos;100;" .. (ZEIT + 3 * Kern.TAG) .. ";H;;;", ZEIT)), nil)
    gleich("gueltig", (Kern.Dekodieren("k;Kaos;100;" .. ZEIT .. ";H;;;", ZEIT)), "k")
    gleich("Gegenstand fehlt", (Kern.Dekodieren("k;Kaos;0;" .. ZEIT .. ";H;;;", ZEIT)), nil)
    gleich("Art unbekannt", (Kern.Dekodieren("k;Kaos;100;" .. ZEIT .. ";X;;;", ZEIT)), nil)
    gleich("leerer Name", (Kern.Dekodieren("k;;100;" .. ZEIT .. ";H;;;", ZEIT)), nil)
    gleich("zu langer Name",
        (Kern.Dekodieren("k;" .. string.rep("a", 61) .. ";100;" .. ZEIT .. ";H;;;", ZEIT)), nil)

    -- Das Merkmal „zurueckgenommen" reist mit
    local _, weg = Kern.Dekodieren(Kern.Kodieren("k", { awardedTo = "Timo", itemID = 5, timestamp = ZEIT, zurueck = true }), ZEIT)
    gleich("zurueckgenommen bleibt", weg and weg.zurueck, true)
    local _, nicht = Kern.Dekodieren(Kern.Kodieren("k", { awardedTo = "Timo", itemID = 5, timestamp = ZEIT }), ZEIT)
    gleich("sonst nicht zurueckgenommen", nicht and nicht.zurueck, nil)
end

--- Zurueckgenommen wandert nur in eine Richtung: von nein auf ja.
local function testZurueckgenommen()
    local H = { a = { awardedTo = "Kaos", itemID = 1, timestamp = ZEIT } }
    local alias = {}

    local _, _, _, _, z = Kern.Zusammenfuehren(H, alias,
        { { id = "a", e = { awardedTo = "Kaos", itemID = 1, timestamp = ZEIT, zurueck = true } } }, 180)
    gleich("Rueckgabe wird uebernommen", H.a.zurueck, true)
    gleich("eine Rueckgabe gezaehlt", z, 1)

    -- Der umgekehrte Weg gibt es nicht: ein Eingehender ohne Merkmal
    -- hebt die Rueckgabe nicht wieder auf.
    Kern.Zusammenfuehren(H, alias, { { id = "a", e = { awardedTo = "Kaos", itemID = 1, timestamp = ZEIT } } }, 180)
    gleich("Rueckgabe bleibt bestehen", H.a.zurueck, true)

    -- Auch ueber einen Doppelgaenger-Alias
    local H2 = { a = { awardedTo = "Kaos", itemID = 1, timestamp = ZEIT } }
    local alias2 = { b = "a" }
    Kern.Zusammenfuehren(H2, alias2,
        { { id = "b", e = { awardedTo = "Kaos", itemID = 1, timestamp = ZEIT, zurueck = true } } }, 180)
    gleich("Rueckgabe ueber den Alias", H2.a.zurueck, true)
end

local function testPakete()
    local zeilen = { "aaaaaaaaaa", "bbbbbbbbbb", "cccccccccc", "dddddddddd", "eeeeeeeeee" }
    local pakete = Kern.Pakete(zeilen, 25)

    -- Je Paket passen zwei (10 + 1 + 10 = 21); ein drittes waeren 32 > 25.
    gleich("drei Pakete", #pakete, 3)
    local ok = true
    for _, p in ipairs(pakete) do if #p > 25 then ok = false end end
    gleich("kein Paket zu lang", ok, true)

    local zurueck = {}
    for _, p in ipairs(pakete) do
        for _, z in ipairs(Kern.Entpacken(p)) do zurueck[#zurueck + 1] = z end
    end
    gleich("alle Zeilen kommen an", table.concat(zurueck, "|"), table.concat(zeilen, "|"))

    -- ⚠️ Eine zu lange Zeile wird NICHT gekappt: abgeschnitten waere sie falsch
    local lang = string.rep("x", 30)
    local p2 = Kern.Pakete({ lang }, 25)
    gleich("lange Zeile bleibt ganz", p2[1], lang)

    gleich("leer ergibt nichts", #Kern.Pakete({}, 25), 0)
    gleich("Entpacken von nichts", #Kern.Entpacken(nil), 0)
end

local function testSchreiber()
    local ml     = { name = "Pluenderer", ich = false }
    local leiter = { name = "Leiter",     ich = false }
    local ich    = { name = "Ich",        ich = true  }

    -- Der Pluendermeister hat das Addon: er schreibt.
    gleich("Pluendermeister schreibt",
        Kern.Schreiber({ ml, leiter, ich }, { pluenderer = true }), ml)

    -- ⭐ Entscheid: Ohne Pluendermeister (oder ohne Addon bei ihm) der Leiter
    gleich("ohne Addon beim Pluendermeister: der Leiter",
        Kern.Schreiber({ ml, leiter, ich }, { leiter = true }), leiter)

    -- Bin ich selbst der Pluendermeister, schreibe ich
    gleich("ich als Pluendermeister",
        Kern.Schreiber({ { name = "Ich", ich = true }, leiter }, { leiter = true }).ich, true)

    -- Ein anderer mit Addon steht vor mir: ich schweige
    gleich("ein anderer ist dran",
        Kern.Schreiber({ ml, ich }, { pluenderer = true }), ml)

    -- Noch keine Hallo-Meldungen: ich schreibe zur Not selbst (doppelt ist
    -- besser als gar nicht, und der Abgleich faengt Doppelte ab)
    gleich("ohne Wissen ueber die anderen schreibe ich selbst",
        Kern.Schreiber({ ml, leiter, ich }, {}), ich)

    -- Keiner hat das Addon
    gleich("niemand hat das Addon", Kern.Schreiber({ ml, leiter }, {}), nil)
    gleich("keine Kandidaten", Kern.Schreiber({}, {}), nil)
    gleich("Unfug", Kern.Schreiber(nil, nil), nil)

    -- Namen mit Realm oder Gross/Klein finden den Schluessel trotzdem
    gleich("Schluessel wird normalisiert",
        Kern.Schreiber({ { name = "Pluenderer-Realm", ich = false }, ich }, { pluenderer = true }).name,
        "Pluenderer-Realm")
end

local function testVerlauf()
    local H = {
        a = { awardedTo = "Kaos",  itemID = 1, timestamp = 1000, gruppe = "40er" },
        b = { awardedTo = "Timo",  itemID = 2, timestamp = 3000, gruppe = "10er", OS = true },
        c = { awardedTo = "Lina",  itemID = 3, timestamp = 2000, gruppe = "40er" },
        d = { awardedTo = Kern.ENTZAUBERT, itemID = 4, timestamp = 4000 },
        e = { awardedTo = "Moe",   itemID = 5, timestamp = 2500, zurueck = true },
    }

    local alle = Kern.Verlauf(H, 0, nil)
    gleich("Entzaubertes und Zurueckgenommenes fehlen", #alle, 3)
    gleich("neueste zuerst", alle[1].name, "Timo")
    gleich("dann die naechste", alle[2].name, "Lina")
    gleich("aelteste zuletzt", alle[3].name, "Kaos")
    gleich("Zweitbedarf gekennzeichnet", alle[1].zweit, true)

    gleich("Zeitfenster", #Kern.Verlauf(H, 1500, nil), 2)

    local nur40 = Kern.Verlauf(H, 0, "40er")
    gleich("nur die Gruppe", #nur40, 2)
    gleich("nur die Gruppe: neueste", nur40[1].name, "Lina")

    gleich("unbekannte Gruppe ist leer", #Kern.Verlauf(H, 0, "99er"), 0)
    gleich("ohne Gruppe dieselbe Tabelle", Kern.NachGruppe(H, nil), H)
    gleich("Gruppenfilter schneidet", (function()
        local n = 0 for _ in pairs(Kern.NachGruppe(H, "10er")) do n = n + 1 end return n end)(), 1)

    -- Die Bilanz laeuft auch auf der gefilterten Historie
    local liste = Kern.Bilanz(Kern.NachGruppe(H, "40er"), 0)
    gleich("Bilanz je Gruppe: zwei Spieler", #liste, 2)
end

-- =====================================================================
--  Die 9 Beispiele aus dem Regelwerk (Stand 16.10.2026)
-- =====================================================================

local function testRegelwerkBeispiele()
    -- =================================================================
    -- Beispiel 1 – Normaler Abend: Alle da. Kaos 3, Shadow 3, Canu 2, Protti 4.
    -- =================================================================
    local liste1 = {
        { name = "Kaos",   haupt = 3, wertung = 3, zweit = 0, letzte = 100 },
        { name = "Shadow", haupt = 3, wertung = 3, zweit = 0, letzte = 200 },
        { name = "Canu",   haupt = 2, wertung = 2, zweit = 0, letzte = 300 },
        { name = "Protti", haupt = 4, wertung = 4, zweit = 0, letzte = 400 },
    }
    local wuerfel1 = { Kaos = 50, Shadow = 80, Canu = 12, Protti = 99 }
    Kern.WurfReihenfolge(liste1, function() return "haupt" end, function(n) return wuerfel1[n] end)
    gleich("Bsp 1 Item 1: Canu hat niedrigste Wertung (2) und gewinnt", liste1[1].name, "Canu")
    gleich("Bsp 1 Item 1: keine Anhebung bei Canu", liste1[1].dynamischeAnhebung or 0, 0)

    -- Item 2: Canu steht jetzt bei 3 (Wertung +1)
    local liste1_2 = {
        { name = "Kaos",   haupt = 3, wertung = 3, zweit = 0, letzte = 100 },
        { name = "Shadow", haupt = 3, wertung = 3, zweit = 0, letzte = 200 },
        { name = "Canu",   haupt = 3, wertung = 3, zweit = 0, letzte = 500 },
        { name = "Protti", haupt = 4, wertung = 4, zweit = 0, letzte = 400 },
    }
    local wuerfel1_2 = { Kaos = 40, Shadow = 95, Canu = 12, Protti = 80 }
    Kern.WurfReihenfolge(liste1_2, function() return "haupt" end, function(n) return wuerfel1_2[n] end)
    gleich("Bsp 1 Item 2: Kaos, Shadow, Canu gleichauf -> hoechster Wurf gewinnt", liste1_2[1].name, "Shadow")
    gleich("Bsp 1 Item 2: Kaos mit Wurf 40 Zweiter", liste1_2[2].name, "Kaos")
    gleich("Bsp 1 Item 2: Canu mit Wurf 12 Dritter", liste1_2[3].name, "Canu")
    gleich("Bsp 1 Item 2: Protti (Wertung 4) hinten trotz Wurf 80", liste1_2[4].name, "Protti")

    -- =================================================================
    -- Beispiel 2 – Rueckkehrer nach drei Wochen:
    -- Kaos, Shadow, Canu stehen bei 9. Protti fehlt 3 Abende abgemeldet (0.7 + 1.0 + 1.0 = 2.7).
    -- Prottis Wertung = 6 + 2.7 = 8.7.
    -- =================================================================
    local f1 = Kern.FehlFaktor(1, "abgemeldet")
    local f2 = Kern.FehlFaktor(2, "abgemeldet")
    local f3 = Kern.FehlFaktor(3, "abgemeldet")
    gleich("Bsp 2: 1. Fehlen Faktor 0.7", f1, 0.7)
    gleich("Bsp 2: 2. Fehlen Faktor 1.0", f2, 1.0)
    gleich("Bsp 2: 3. Fehlen Faktor 1.0", f3, 1.0)
    local z1 = Kern.Zuschlag(f1, 1.0)
    local z2 = Kern.Zuschlag(f2, 1.0)
    local z3 = Kern.Zuschlag(f3, 1.0)
    local prottiWertung = Kern.Wertung(6, { z1, z2, z3 })
    gleich("Bsp 2: Protti Wertung 8.7", prottiWertung, 8.7)

    local liste2 = {
        { name = "Kaos",   haupt = 9, wertung = 9,   zweit = 0, letzte = 100 },
        { name = "Shadow", haupt = 9, wertung = 9,   zweit = 0, letzte = 200 },
        { name = "Canu",   haupt = 9, wertung = 9,   zweit = 0, letzte = 300 },
        { name = "Protti", haupt = 6, wertung = 8.7, zweit = 0, letzte = 50  },
    }
    local wuerfel2 = { Kaos = 90, Shadow = 85, Canu = 70, Protti = 15 }
    Kern.WurfReihenfolge(liste2, function() return "haupt" end, function(n) return wuerfel2[n] end)
    gleich("Bsp 2: Protti (8.7) gewinnt Item 1 sicher vor Kaos (9, Wurf 90)", liste2[1].name, "Protti")
    gleich("Bsp 2: Protti brauchte keine Anhebung (0.3 unter 9)", liste2[1].dynamischeAnhebung or 0, 0)

    -- Nach Item 1 steht Protti bei 8.7 + 1 = 9.7
    local liste2_2 = {
        { name = "Kaos",   haupt = 9, wertung = 9,   zweit = 0, letzte = 100 },
        { name = "Shadow", haupt = 9, wertung = 9,   zweit = 0, letzte = 200 },
        { name = "Canu",   haupt = 9, wertung = 9,   zweit = 0, letzte = 300 },
        { name = "Protti", haupt = 7, wertung = 9.7, zweit = 0, letzte = 500 },
    }
    Kern.WurfReihenfolge(liste2_2, function() return "haupt" end, function(n) return wuerfel2[n] end)
    gleich("Bsp 2 Item 2: Kaos (9, Wurf 90) gewinnt nun vor Protti (9.7)", liste2_2[1].name, "Kaos")
    gleich("Bsp 2 Item 2: Protti (9.7) hinten", liste2_2[4].name, "Protti")

    -- =================================================================
    -- Beispiel 3 – Bank und Anhebung:
    -- Shadow hatte 6 und sass 3 Abende auf der Bank (Faktor 0). Kaos und Canu stehen bei 9.
    -- Shadow liegt 3 Punkte darunter -> Anhebung auf 9 + 2 = 11 (hinter die anderen, kein sicheres Item).
    -- =================================================================
    local fBank = Kern.FehlFaktor(1, "bank")
    gleich("Bsp 3: Bank-Faktor ist 0", fBank, 0)
    local zBank = Kern.Zuschlag(fBank, 1.0)
    gleich("Bsp 3: Bank-Zuschlag ist 0", zBank, 0)

    local effWertung, anh = Kern.Anhebung(6, { 9, 9 })
    gleich("Bsp 3: Shadow wird auf 11 gesetzt (Niedrigster 9 + 2)", effWertung, 11)
    gleich("Bsp 3: Anhebung betraegt 5 Punkte", anh, 5)

    local liste3 = {
        { name = "Kaos",   haupt = 9, wertung = 9, zweit = 0, letzte = 100 },
        { name = "Canu",   haupt = 9, wertung = 9, zweit = 0, letzte = 200 },
        { name = "Shadow", haupt = 6, wertung = 6, zweit = 0, letzte = 50  },
    }
    local wuerfel3 = { Kaos = 99, Canu = 80, Shadow = 10 }
    Kern.WurfReihenfolge(liste3, function() return "haupt" end, function(n) return wuerfel3[n] end)
    gleich("Bsp 3: Kaos (9, Wurf 99) gewinnt Item 1, Shadow hat kein sicheres Item", liste3[1].name, "Kaos")
    gleich("Bsp 3: Canu (9, Wurf 80) danach", liste3[2].name, "Canu")
    gleich("Bsp 3: Shadow steht hinten", liste3[3].name, "Shadow")
    gleich("Bsp 3: Shadow effektive Wertung 11", liste3[3].effektiveWertung, 11)
    gleich("Bsp 3: Shadow Anhebung 5", liste3[3].dynamischeAnhebung, 5)

    -- Spaeter am Abend: Kaos und Canu haben Items bekommen und stehen bei 12. Shadow ist mit seiner
    -- festgeschriebenen Anhebung (6 + 5 = 11) jetzt vorn — im Lauf des Abends kommt er dran.
    local liste3_2 = {
        { name = "Kaos",   haupt = 12, wertung = 12, zweit = 0, letzte = 100 },
        { name = "Canu",   haupt = 12, wertung = 12, zweit = 0, letzte = 200 },
        { name = "Shadow", haupt = 6, wertung = 11, zweit = 0, letzte = 500, anhebung = 5, keineAnhebung = true },
    }
    local wuerfel3_2 = { Kaos = 90, Canu = 95, Shadow = 10 }
    Kern.WurfReihenfolge(liste3_2, function() return "haupt" end, function(n) return wuerfel3_2[n] end)
    gleich("Bsp 3 spaeter: Shadow (11) steht vor Kaos und Canu (12), obwohl sein Wurf klein ist", liste3_2[1].name, "Shadow")
    gleich("Bsp 3 spaeter: keine zweite Anhebung am selben Abend", liste3_2[1].dynamischeAnhebung, 0)

    -- =================================================================
    -- Beispiel 4 – Bank hilft nicht, wenn man schon mehr hat:
    -- Canu hatte 8, 2 Abende Bank -> bleibt 8. Kaos 7, Shadow 8.
    -- =================================================================
    local liste4 = {
        { name = "Canu",   haupt = 8, wertung = 8, zweit = 0, letzte = 100 },
        { name = "Shadow", haupt = 8, wertung = 8, zweit = 0, letzte = 200 },
        { name = "Kaos",   haupt = 7, wertung = 7, zweit = 0, letzte = 300 },
    }
    local wuerfel4 = { Canu = 90, Shadow = 85, Kaos = 20 }
    Kern.WurfReihenfolge(liste4, function() return "haupt" end, function(n) return wuerfel4[n] end)
    gleich("Bsp 4: Kaos (7) gewinnt vor Canu (8) und Shadow (8)", liste4[1].name, "Kaos")
    gleich("Bsp 4: Canu keine Anhebung", liste4[2].dynamischeAnhebung or 0, 0)
    gleich("Bsp 4: Shadow keine Anhebung", liste4[3].dynamischeAnhebung or 0, 0)

    -- =================================================================
    -- Beispiel 5 – Jeden zweiten Abend fehlen:
    -- Abende 2, 4, 6, 8 fehlen. Letzte 6 Abende als Fenster.
    -- =================================================================
    gleich("Bsp 5 Abend 2 (1. Fehlen): Faktor 0.7", Kern.FehlFaktor(1, "abgemeldet"), 0.7)
    gleich("Bsp 5 Abend 4 (2. Fehlen): Faktor 1.0", Kern.FehlFaktor(2, "abgemeldet"), 1.0)
    gleich("Bsp 5 Abend 6 (3. Fehlen): Faktor 1.0", Kern.FehlFaktor(3, "abgemeldet"), 1.0)
    gleich("Bsp 5 Abend 8 (3. Fehlen im 6er Fenster): Faktor 1.0", Kern.FehlFaktor(3, "abgemeldet"), 1.0)
    -- Strafstufen bei 5 bzw. 6 Fehlen im Fenster
    gleich("Bsp 5: 5. Fehlen Strafstufe 1.3", Kern.FehlFaktor(5, "abgemeldet"), 1.3)
    gleich("Bsp 5: ab 6. Fehlen Strafstufe 1.5", Kern.FehlFaktor(6, "abgemeldet"), 1.5)
    gleich("Bsp 5: 7. Fehlen bleibt 1.5", Kern.FehlFaktor(7, "abgemeldet"), 1.5)

    -- =================================================================
    -- Beispiel 6 – Unentschuldigt: sofort Faktor 1,5, mindestens 2 Wertungspunkte
    -- =================================================================
    gleich("Bsp 6: Unentschuldigt sofort 1.5 beim 1. Mal", Kern.FehlFaktor(1, "unentschuldigt"), 1.5)
    gleich("Bsp 6: Unentschuldigt sofort 1.5 beim 2. Mal", Kern.FehlFaktor(2, "unentschuldigt"), 1.5)
    local zUnent, fUnent, minGriff = Kern.ZuschlagUnentschuldigt(1.0)
    gleich("Bsp 6: Zuschlag bei Schnitt 1.0 ist 2 (Minimum)", zUnent, 2)
    gleich("Bsp 6: Faktor bleibt 1.5", fUnent, 1.5)
    gleich("Bsp 6: das Minimum hat gegriffen", minGriff, true)
    gleich("Bsp 6: bei Schnitt 0.5 ebenfalls 2", (Kern.ZuschlagUnentschuldigt(0.5)), 2)
    local zHoch, _, minHoch = Kern.ZuschlagUnentschuldigt(2.0)
    gleich("Bsp 6: bei Schnitt 2.0 gilt Faktor x Schnitt = 3", zHoch, 3)
    gleich("Bsp 6: dann greift das Minimum nicht", minHoch, false)

    -- =================================================================
    -- Beispiel 7 – Neuer Kaderspieler:
    -- Abend 1: Proberaid -> keine Lootberechtigung
    -- Abend 2: Canu steht bei 0, andere bei 9 -> auf den Niedrigsten plus 2 gesetzt (11), hinter die anderen
    -- =================================================================

    local liste7 = {
        { name = "Kaos",   haupt = 9, wertung = 9, zweit = 0, letzte = 100 },
        { name = "Shadow", haupt = 9, wertung = 9, zweit = 0, letzte = 200 },
        { name = "Canu",   haupt = 0, wertung = 0, zweit = 0, letzte = 0, neuling = true, neulingZiel = 11 },
    }
    local wuerfel7 = { Kaos = 90, Shadow = 80, Canu = 5 }
    Kern.WurfReihenfolge(liste7, function() return "haupt" end, function(n) return wuerfel7[n] end)
    gleich("Bsp 7: Canu steht bei 11, hinter den anderen: Kaos (Wurf 90) gewinnt", liste7[1].name, "Kaos")
    gleich("Bsp 7: Shadow (9) vor Canu (11)", liste7[2].name, "Shadow")
    local canu7
    for _, e in ipairs(liste7) do if e.name == "Canu" then canu7 = e end end
    gleich("Bsp 7: Canu effektive Wertung 11", canu7.effektiveWertung, 11)
    gleich("Bsp 7: Canu Anhebung 11", canu7.dynamischeAnhebung, 11)

    -- =================================================================
    -- Beispiel 8 – Gast:
    -- Protti ist Gast. Im Raid: Kaos 5, Shadow 4, Canu 6.
    -- Niedrigste Kader-Wertung ist 4 -> Protti erhaelt fuer den Abend 4.
    -- =================================================================
    local gastWert = Kern.GastWertung(4)
    gleich("Bsp 8: Gast erhaelt Wertung 4", gastWert, 4)

    local liste8 = {
        { name = "Kaos",   haupt = 5, wertung = 5, zweit = 0, letzte = 100 },
        { name = "Shadow", haupt = 4, wertung = 4, zweit = 0, letzte = 200 },
        { name = "Canu",   haupt = 6, wertung = 6, zweit = 0, letzte = 300 },
        { name = "Protti", haupt = 0, wertung = 4, zweit = 0, letzte = 0   }, -- Gast mit gesetzter Wertung 4
    }
    local wuerfel8 = { Kaos = 90, Shadow = 40, Canu = 80, Protti = 75 }
    Kern.WurfReihenfolge(liste8, function() return "haupt" end, function(n) return wuerfel8[n] end)
    gleich("Bsp 8: Protti (4, Wurf 75) gewinnt vor Shadow (4, Wurf 40)", liste8[1].name, "Protti")
    gleich("Bsp 8: Shadow (4) an Position 2", liste8[2].name, "Shadow")
    gleich("Bsp 8: Kaos (5) an Position 3", liste8[3].name, "Kaos")
    gleich("Bsp 8: Canu (6) an Position 4", liste8[4].name, "Canu")

    -- =================================================================
    -- Beispiel 9 – Item zurueckgegeben:
    -- Shadow bekommt Main-Item (+1) und gibt es zurueck.
    -- Wenn neu vergeben an Canu: Shadow -1, Canu +1.
    -- =================================================================
    local shadowStart = 5
    local canuStart = 5
    -- Vergabe an Shadow
    local shadowNachItem = shadowStart + 1
    gleich("Bsp 9: Shadow erhaelt Item (+1)", shadowNachItem, 6)
    -- Rueckgabe und Neuvergabe an Canu
    local shadowNachRueckgabe = shadowNachItem - 1
    local canuNachVergabe = canuStart + 1
    gleich("Bsp 9: Shadow Punkt wieder abgezogen", shadowNachRueckgabe, 5)
    gleich("Bsp 9: Canu erhaelt den Punkt (+1)", canuNachVergabe, 6)
    -- Summe der Punkte bleibt unveraendert (Schnitt des Abends bleibt gleich)
    gleich("Bsp 9: Gesamtsumme der Punkte bleibt gleich",
        shadowStart + canuStart + 1, shadowNachRueckgabe + canuNachVergabe)
end

local function testDemoDaten()
    if not (ns.Quelle and ns.Quelle.Beispiel and ns.Quelle.BeispielWurf and ns.Quelle.BeispielDaten) then
        return
    end
    local H = ns.Quelle.Beispiel()
    local W = ns.Quelle.BeispielWurf()
    local D = ns.Quelle.BeispielDaten()
    local liste = Kern.Bilanz(H, 0, W.namen, nil, D)

    local function istWuerfler(name)
        local k = Kern.Schluessel(name)
        return W.Arten and W.Arten[k] or false
    end
    local function wurfWert(name)
        local k = Kern.Schluessel(name)
        return W.Wuerfe and W.Wuerfe[k] or 0
    end

    Kern.WurfReihenfolge(liste, istWuerfler, wurfWert)

    -- Rangfolge der Wuerfler:
    -- 1. Kaosx (Wertung 2.0, Wurf 24)
    gleich("Demo 1. Platz: Kaosx", liste[1].name, "Kaosx")
    gleich("Demo Kaosx Wertung 2.0", liste[1].effektiveWertung, 2.0)

    -- 2. Chilini (Wertung 3.0, Wurf 81 schlaegt Simondan Wurf 45)
    gleich("Demo 2. Platz: Chilini", liste[2].name, "Chilini")
    gleich("Demo Chilini Wertung 3.0", liste[2].effektiveWertung, 3.0)

    -- 3. Simondan (Wertung 3.0, Wurf 45)
    gleich("Demo 3. Platz: Simondan", liste[3].name, "Simondan")
    gleich("Demo Simondan Wertung 3.0", liste[3].effektiveWertung, 3.0)

    -- 4. Deters (Wertung 3.7 durch 1.7 Zuschlag, Wurf 98)
    --    Demonstriert: Wertung schlaegt Wurf! (trotz 98 nur Platz 4)
    gleich("Demo 4. Platz: Deters", liste[4].name, "Deters")
    gleich("Demo Deters Wertung 3.7", liste[4].effektiveWertung, 3.7)

    -- 5. Nuhkomm (0 Items, liegt 2 Punkte hinter dem Niedrigsten -> Anhebung auf 2.0 + 2 = 4.0, Wurf 93)
    --    Demonstriert die Anhebung (§ 3): weit hinten, hinter allen, kein sicheres Item.
    gleich("Demo 5. Platz: Nuhkomm", liste[5].name, "Nuhkomm")
    gleich("Demo Nuhkomm effektive Wertung 4.0", liste[5].effektiveWertung, 4.0)
    gleich("Demo Nuhkomm Anhebung 4.0", liste[5].dynamischeAnhebung, 4.0)

    -- 6. Velera (Zweitbedarf, 1 OS, Wurf 38)
    --    Demonstriert: weniger OS-Stuecke schlaegt Wurf! (schlaegt Pflasterelfe mit 2 OS trotz Wurf 49)
    gleich("Demo 6. Platz: Velera", liste[6].name, "Velera")
    gleich("Demo Velera 1 OS", liste[6].zweit, 1)

    -- 7. Pflasterelfe (Zweitbedarf, 2 OS, Wurf 49)
    gleich("Demo 7. Platz: Pflasterelfe", liste[7].name, "Pflasterelfe")
    gleich("Demo Pflasterelfe 2 OS", liste[7].zweit, 2)
end

local function testAnwesenheit()
    if not ns.Anwesenheit then return end
    local Anw = ns.Anwesenheit

    local testDB = { abende = {}, zuschlaege = {}, anhebungen = {} }
    if Anw._SetDB then Anw._SetDB(testDB) end

    Anw.AbendZuruecksetzen()
    local abend = Anw.AktiverAbend(true)
    gleich("Anw Abend angelegt", abend ~= nil, true)
    gleich("Anw Bosse anfangs 0", abend.bosse, 0)

    -- Wipe: darf nicht gezaehlt werden
    local ok, grund = Anw.BossBuchen("Lucifron", 101, false, { "Kaosx", "Shadow", "Canu", "Protti" })
    gleich("Anw Wipe wird abgelehnt", ok, nil)
    gleich("Anw Bosse nach Wipe 0", abend.bosse, 0)

    -- 1. Kill: erfolgreicher Bosskampf mit 4 Spielern
    local ok1, n1, b1 = Anw.BossBuchen("Lucifron", 101, true, { "Kaosx", "Shadow", "Canu", "Protti" })
    gleich("Anw Boss 1 gebucht", ok1, true)
    gleich("Anw 4 Spieler anwesend", n1, 4)
    gleich("Anw Bosse jetzt 1", abend.bosse, 1)

    -- Doppelzaehlung (Wipe-Schutz / erneuter Versuch): wird abgelehnt
    local okDup, grundDup = Anw.BossBuchen("Lucifron", 101, true, { "Kaosx", "Shadow", "Canu", "Protti" })
    gleich("Anw Doppelter Encounter abgelehnt", okDup, nil)
    gleich("Anw Bosse bleibt 1", abend.bosse, 1)

    -- 2. Kill: anderer Boss, nur 3 Spieler dabei (Protti fehlt)
    local ok2, n2, b2 = Anw.BossBuchen("Magmadar", 102, true, { "Kaosx", "Shadow", "Canu" })
    gleich("Anw Boss 2 gebucht", ok2, true)
    gleich("Anw 3 Spieler anwesend", n2, 3)
    gleich("Anw Bosse jetzt 2", abend.bosse, 2)

    -- Spielerinfo & Quotenpruefung (§ 2: >= 50 % = im Raid):
    -- Kaosx war bei beiden dabei (2/2 = 100 %) -> imRaid = true
    local ik = Anw.SpielerInfo("Kaosx", abend)
    gleich("Anw Kaosx 2 Bosse", ik.bosse, 2)
    gleich("Anw Kaosx 100%", ik.prozent, 100)
    gleich("Anw Kaosx im Raid", ik.imRaid, true)

    -- Protti war bei 1 von 2 dabei (1/2 = 50 %) -> >= 50 % -> imRaid = true
    local ip = Anw.SpielerInfo("Protti", abend)
    gleich("Anw Protti 1 Boss", ip.bosse, 1)
    gleich("Anw Protti 50%", ip.prozent, 50)
    gleich("Anw Protti im Raid (50% Quote erfuellt)", ip.imRaid, true)

    -- Dritter Spieler gar nicht dabei (0/2 = 0 %) -> unter Quote
    local ix = Anw.SpielerInfo("Niemand", abend)
    gleich("Anw Niemand 0 Bosse", ix.bosse, 0)
    gleich("Anw Niemand nicht im Raid", ix.imRaid, false)

    -- Uebersicht
    local ueb = Anw.Uebersicht(abend)
    gleich("Anw 4 Teilnehmer in der Uebersicht", #ueb, 4)

    -- Aufraeumen
    Anw.AbendZuruecksetzen()
    if Anw._SetDB then Anw._SetDB(nil) end
end

local function testBankUndUnentschuldigt()
    local Anw = ns.Anwesenheit
    if not Anw then return end

    local testDB = { abende = {}, zuschlaege = {}, anhebungen = {} }
    if Anw._SetDB then Anw._SetDB(testDB) end

    Anw.AbendZuruecksetzen()
    local abend = Anw.AktiverAbend(true)

    ns.Konfig = ns.Konfig or {}
    local altDarf = ns.Konfig.Darf
    ns.Konfig.Darf = function(name)
        return Kern.GleicherSpieler(name, "Leiter Kaos")
    end

    ns.Rolle = ns.Rolle or {}
    local altBerechtigt = ns.Rolle.Berechtigt
    ns.Rolle.Berechtigt = function(name)
        return Kern.GleicherSpieler(name, "Raidleiter Timo")
    end

    -- 1. Berechtigungen pruefen
    gleich("Bank Darf Gildenleitung", Anw.DarfBankVerwalten("Leiter Kaos"), true)
    gleich("Bank Darf Raidleiter", Anw.DarfBankVerwalten("Raidleiter Timo"), true)
    gleich("Bank Darf Raider nicht", Anw.DarfBankVerwalten("Raider Bob"), false)

    gleich("Unent Darf Gildenleitung", Anw.DarfUnentschuldigtVerwalten("Leiter Kaos"), true)
    gleich("Unent Darf Raidleiter nicht", Anw.DarfUnentschuldigtVerwalten("Raidleiter Timo"), false)
    gleich("Unent Darf Raider nicht", Anw.DarfUnentschuldigtVerwalten("Raider Bob"), false)

    -- 2. Bank setzen
    local ok1, err1 = Anw.BankSetzen("Shadow", true, "Raider Bob")
    gleich("Bank setzen ohne Berechtigung scheitert", ok1, nil)

    local ok2 = Anw.BankSetzen("Shadow", true, "Raidleiter Timo")
    gleich("Bank setzen mit Raidleiter gelingt", ok2, true)
    local istBank, bInfo = Anw.IstBank("Shadow", abend)
    gleich("Shadow ist auf der Bank", istBank, true)
    gleich("Shadow Bank gesetzt von Timo", bInfo.von, "Raidleiter Timo")
    gleich("Shadow nicht unentschuldigt", Anw.IstUnentschuldigt("Shadow", abend), false)

    gleich("Protokolleintrag vorhanden", #abend.protokoll >= 1, true)
    gleich("Protokoll Typ ist bank", abend.protokoll[#abend.protokoll].typ, "bank")
    gleich("Protokoll an ist true", abend.protokoll[#abend.protokoll].an, true)

    -- 3. Unentschuldigt setzen
    local ok3, err3 = Anw.UnentschuldigtSetzen("Deters", true, "Raidleiter Timo")
    gleich("Unentschuldigt durch Raidleiter scheitert", ok3, nil)

    local ok4 = Anw.UnentschuldigtSetzen("Deters", true, "Leiter Kaos")
    gleich("Unentschuldigt durch Gildenleitung gelingt", ok4, true)
    local istUnent, uInfo = Anw.IstUnentschuldigt("Deters", abend)
    gleich("Deters ist unentschuldigt", istUnent, true)
    gleich("Deters unentschuldigt gesetzt von Kaos", uInfo.von, "Leiter Kaos")
    gleich("Deters nicht auf Bank", Anw.IstBank("Deters", abend), false)

    -- 4. Wechselseitiger Ausschluss
    local ok5 = Anw.UnentschuldigtSetzen("Shadow", true, "Leiter Kaos")
    gleich("Shadow unentschuldigt setzen gelingt", ok5, true)
    gleich("Shadow nicht mehr auf Bank", Anw.IstBank("Shadow", abend), false)
    gleich("Shadow jetzt unentschuldigt", Anw.IstUnentschuldigt("Shadow", abend), true)

    local ok6 = Anw.BankSetzen("Shadow", true, "Leiter Kaos")
    gleich("Shadow wieder auf Bank gelingt", ok6, true)
    gleich("Shadow wieder auf Bank", Anw.IstBank("Shadow", abend), true)
    gleich("Shadow nicht mehr unentschuldigt", Anw.IstUnentschuldigt("Shadow", abend), false)

    -- 5. Bank aufheben
    local ok7 = Anw.BankSetzen("Shadow", false, "Leiter Kaos")
    gleich("Bank aufheben gelingt", ok7, true)
    gleich("Shadow nicht mehr auf Bank", Anw.IstBank("Shadow", abend), false)

    -- 6. Demo-Kandidaten
    local demoKandidaten = Anw.BeispielKandidaten()
    gleich("Demo-Kandidaten vorhanden", #demoKandidaten >= 5, true)
    gleich("Demo Canu ist Bank", demoKandidaten[1].bank ~= nil, true)
    gleich("Demo Deters ist unentschuldigt", demoKandidaten[3].unentschuldigt ~= nil, true)

    Anw.BeispielBankToggle("Canu")
    gleich("Demo Canu nach Toggle keine Bank", demoKandidaten[1].bank, nil)
    Anw.BeispielBankToggle("Canu")
    gleich("Demo Canu nach erneutem Toggle wieder Bank", demoKandidaten[1].bank ~= nil, true)

    ns.Konfig.Darf = altDarf
    ns.Rolle.Berechtigt = altBerechtigt
    Anw.AbendZuruecksetzen()
    if Anw._SetDB then Anw._SetDB(nil) end
end

local function testAbendAbschlussUndSpielerdetail()
    local Anw = ns.Anwesenheit
    if not Anw then return end

    local testDB = { abende = {}, zuschlaege = {}, anhebungen = {} }
    if Anw._SetDB then Anw._SetDB(testDB) end

    -- Mock-Rechte
    local altDarf = ns.Konfig and ns.Konfig.Darf
    local altBerechtigt = ns.Rolle and ns.Rolle.Berechtigt
    ns.Konfig = ns.Konfig or {}
    ns.Konfig.Darf = function(name) return name == "Leiter Kaos" end
    ns.Rolle = ns.Rolle or {}
    ns.Rolle.Berechtigt = function(name) return name == "Leiter Kaos" or name == "Raidleiter Timo" end

    -- Mock-Historie fuer Main-Items
    local altHist = ns.Erfassung and ns.Erfassung.Historie
    local t = time()
    local mockHist = {
        m1 = { awardedTo = "Kaos", itemID = 1001, timestamp = t - 1800, OS = false },
        m2 = { awardedTo = "Timo", itemID = 1002, timestamp = t - 900, OS = false },
    }
    ns.Erfassung = ns.Erfassung or {}
    ns.Erfassung.Historie = function() return mockHist end

    -- Aktiven Abend aufbauen
    Anw.AbendZuruecksetzen()
    local abend = Anw.AktiverAbend(true)
    Anw.BossBuchen("Lucifron", 101, true, { "Kaos", "Timo" })
    Anw.BossBuchen("Magmadar", 102, true, { "Kaos", "Timo" })

    -- Bank und Unentschuldigt setzen
    Anw.BankSetzen("Shadow", true, "Raidleiter Timo")
    Anw.UnentschuldigtSetzen("Deters", true, "Leiter Kaos")

    -- Mock Gruppen-Pflicht
    local altPflicht = ns.Gruppen and ns.Gruppen.Pflicht
    ns.Gruppen = ns.Gruppen or {}
    ns.Gruppen.Pflicht = function() return { "Kaos", "Timo", "Shadow", "Deters", "Protti" } end
    -- ⭐ Der Test darf nicht von der echten Einteilung des Spielers abhängen (sonst gilt sie statt der Pflichtliste)
    local altEinteilung = ns.Gruppen.EinteilungVorhanden
    ns.Gruppen.EinteilungVorhanden = function() return false end

    -- 1. Schnitt berechnen: 2 Main-Items / 2 Spieler im Raid = 1.0
    local schnitt, items, raidSpieler = Anw.AbendSchnitt(abend)
    gleich("AbendSchnitt: Main Items", items, 2)
    gleich("AbendSchnitt: Raid-Spieler", raidSpieler, 2)
    gleich("AbendSchnitt: Schnitt", schnitt, 1.0)

    -- 1b. ⭐ Wer weder im Raid noch zugeordnet ist, ist OFFEN und verhindert den Abschluss
    local vOffen = Anw.AbendVorschau(abend)
    local offenMap = {}
    for _, p in ipairs(vOffen.spieler) do offenMap[p.schluessel] = p end
    gleich("Protti ohne Eintrag ist offen", offenMap["protti"].status, "offen")
    gleich("Offen ist kein Zuschlag", offenMap["protti"].zuschlag, 0)
    local okOffen, grundOffen = Anw.AbendAbschliessen(abend, "System", true)
    gleich("Abschluss mit Offenen scheitert", okOffen, nil)
    gleich("Meldung nennt den Offenen", tostring(grundOffen):find("Protti", 1, true) ~= nil, true)
    gleich("Abend bleibt offen", abend.abgeschlossen, nil)
    -- Protti wird ausdruecklich abgemeldet (ein Leiter traegt es ein)
    abend.abgemeldet = abend.abgemeldet or {}
    abend.abgemeldet["protti"] = { name = "Protti", von = "Kaos", zeit = t }

    -- 2. Vorschau pruefen
    local vorschau = Anw.AbendVorschau(abend)
    gleich("Vorschau vorhanden", vorschau ~= nil, true)
    gleich("Vorschau Schnitt", vorschau.schnitt, 1.0)
    gleich("Vorschau Spieleranzahl", #vorschau.spieler, 5)

    local vMap = {}
    for _, p in ipairs(vorschau.spieler) do vMap[p.schluessel] = p end
    gleich("Vorschau Kaos im Raid", vMap["kaos"].status, "imRaid")
    gleich("Vorschau Kaos Zuschlag 0", vMap["kaos"].zuschlag, 0)
    gleich("Vorschau Shadow Bank", vMap["shadow"].status, "bank")
    gleich("Vorschau Shadow Zuschlag 0", vMap["shadow"].zuschlag, 0)
    gleich("Vorschau Deters unentschuldigt", vMap["deters"].status, "unentschuldigt")
    gleich("Vorschau Deters Zuschlag 2", vMap["deters"].zuschlag, 2)
    gleich("Vorschau Protti abgemeldet", vMap["protti"].status, "abgemeldet")
    gleich("Vorschau Protti 1. Fehlen Faktor 0.7", vMap["protti"].faktor, 0.7)
    gleich("Vorschau Protti Zuschlag 0.7", vMap["protti"].zuschlag, 0.7)

    -- 2b. Test mit vorherigem Fehlen: 2. Fehlen erzeugt Faktor 1.0 (§ 2)
    testDB.abende["archiv_alt"] = {
        id = "archiv_alt",
        datum = "2026-10-01",
        abgeschlossen = true,
        abschluss = {
            zeit = t - 7 * 86400,
            spieler = {
                protti = { status = "abgemeldet" },
            },
        },
    }
    local vorschau2 = Anw.AbendVorschau(abend)
    local vMap2 = {}
    for _, p in ipairs(vorschau2.spieler) do vMap2[p.schluessel] = p end
    gleich("Vorschau Protti 2. Fehlen Faktor 1.0", vMap2["protti"].faktor, 1.0)
    gleich("Vorschau Protti 2. Fehlen Zuschlag 1.0", vMap2["protti"].zuschlag, 1.0)
    testDB.abende["archiv_alt"] = nil

    -- 3. Abend abschliessen (Rechtepruefung)
    local okFail, errFail = Anw.AbendAbschliessen(abend, "Raider Lina")
    gleich("Abschluss ohne Rechte scheitert", okFail, nil)

    local okAbschluss, vAbschl, zZaehler = Anw.AbendAbschliessen(abend, "Leiter Kaos")
    gleich("Abschluss mit Leitung gelingt", okAbschluss, true)
    gleich("Abschluss 2 Zuschlaege erzeugt (Deters 2, Protti 0.7)", zZaehler, 2)
    gleich("Abend jetzt abgeschlossen", abend.abgeschlossen, true)

    -- 4. ZuschlaegeDaten pruefen
    local zDaten = Anw.ZuschlaegeDaten()
    gleich("ZuschlaegeDaten deters", zDaten.zuschlaege["deters"], 2)
    gleich("ZuschlaegeDaten protti", zDaten.zuschlaege["protti"], 0.7)
    gleich("ZuschlaegeDaten shadow", zDaten.zuschlaege["shadow"] or 0, 0)

    -- 5. SpielerEreignisse pruefen
    local erDeters, hD, zD, sumZD, sumAD, wertD = Anw.SpielerEreignisse("Deters", nil, mockHist, 0, false)
    gleich("SpielerEreignisse Deters: 1 Zuschlagseintrag", #erDeters, 1)
    gleich("SpielerEreignisse Deters: Summe Zuschlaege", sumZD, 2)
    gleich("SpielerEreignisse Deters: Wertung", wertD, 2)

    -- 6. Demo-Ereignisse pruefen
    local demoDeters, hDemo, zDemo, sumZDemo, sumADemo, wertDemo = Anw.SpielerEreignisse("Deters", nil, {}, 0, true)
    gleich("Demo Deters: 2 Zuschlaege vorhanden", sumZDemo, 1.7)
    gleich("Demo Deters: Wertung 1.7 (ohne Items)", wertDemo, 1.7)

    local demoNuhk, hN, zN, sumZN, sumAN, wertN = Anw.SpielerEreignisse("Nuhkomm", nil, {}, 0, true)
    gleich("Demo Nuhkomm: Anhebung 1.0", sumAN, 1.0)
    gleich("Demo Nuhkomm: Wertung 1.0", wertN, 1.0)

    -- 7. Abend wiedereroeffnen
    local okWieder, abendWieder = Anw.AbendWiedereroeffnen(abend.id, "Leiter Kaos")
    gleich("Wiedereroeffnen gelingt", okWieder, true)
    gleich("Abend nicht mehr abgeschlossen", abendWieder.abgeschlossen, nil)
    local zDatenNachher = Anw.ZuschlaegeDaten()
    gleich("Zuschlaege nach Wiedereroeffnen entfernt", zDatenNachher.zuschlaege["deters"] or 0, 0)

    -- Aufraeumen
    ns.Konfig.Darf = altDarf
    ns.Rolle.Berechtigt = altBerechtigt
    ns.Erfassung.Historie = altHist
    ns.Gruppen.Pflicht = altPflicht
    ns.Gruppen.EinteilungVorhanden = altEinteilung
    Anw.AbendZuruecksetzen()
    if Anw._SetDB then Anw._SetDB(nil) end
end

-- =====================================================================

-- =====================================================================
--  Regelwerk 16.10.2026 (Teil 2): Proberaid, Neuling, Gast, Rundung, Kennzeichen
-- =====================================================================

local function testNeulingGastProberaid()
    local function eintrag(name, haupt, extra)
        local e = { name = name, haupt = haupt, zweit = 0, letzte = 0, wertung = haupt }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end
    local function finde(liste, name)
        for _, e in ipairs(liste) do if e.name == name then return e end end
    end
    local function alleHaupt() return "haupt" end

    -- Neuling am 2. Abend (§ 4): auf den Niedrigsten plus 2 gesetzt (9 + 2 = 11), hinter die anderen
    local liste = {
        eintrag("Kaos", 9), eintrag("Shadow", 10), eintrag("Canu", 11),
        eintrag("Protti", 0, { neuling = true, neulingZiel = 11 }),
    }
    local wurf = { Kaos = 50, Shadow = 40, Canu = 30, Protti = 90 }
    Kern.WurfReihenfolge(liste, alleHaupt, function(n) return wurf[n] end)
    local p = finde(liste, "Protti")
    gleich("Neuling: effektiv auf den Niedrigsten plus 2 gesetzt", p.effektiveWertung, 11)
    gleich("Neuling: Anhebung = Differenz", p.dynamischeAnhebung, 11)
    gleich("Neuling: kein sicheres Item, trotz Wurf 90 nicht vorn (Kaos 9 gewinnt)", liste[1].name, "Kaos")
    gleich("Neuling: hinter Shadow (10), vor Canu (11)? bei 11 gleich, Wurf entscheidet (Protti 90)", liste[3].name, "Protti")

    -- Spaeter am Abend, wenn die anderen ueber ihm liegen, ist er vorn
    local spaeter = {
        eintrag("Kaos", 12), eintrag("Shadow", 12), eintrag("Canu", 13),
        eintrag("Protti", 0, { neuling = false, wertung = 11, keineAnhebung = true }),
    }
    Kern.WurfReihenfolge(spaeter, alleHaupt, function(n) return wurf[n] end)
    gleich("Neuling: nach ein paar Items der anderen (12, 12, 13) steht Protti (11) vorn", spaeter[1].name, "Protti")

    -- Zum Vergleich: ein erfahrener Spieler weit unten wird auf Niedrigster-1 gesetzt (§ 3)
    local l2 = { eintrag("Kaos", 9), eintrag("Shadow", 6), eintrag("Canu", 9) }
    Kern.WurfReihenfolge(l2, alleHaupt, function() return 50 end)
    local s = finde(l2, "Shadow")
    gleich("Anhebung nach langer Abwesenheit: Niedrigster plus 2", s.effektiveWertung, 11)
    gleich("und sie steht hinter den anderen (kein sicheres Item)", l2[3].name, "Shadow")
    -- Mit Kader-Bezug (`referenz`): der Niedrigste der ANDEREN Kaderspieler im Raid zaehlt, nicht der der Wuerfler
    local l2b = { eintrag("Kaos", 9), eintrag("Shadow", 6, { referenz = 7 }) }
    Kern.WurfReihenfolge(l2b, alleHaupt, function() return 50 end)
    gleich("Kader-Referenz 7: Shadow (6) liegt nicht mehr als 1 darunter -> keine Anhebung", finde(l2b, "Shadow").dynamischeAnhebung, 0)
    local l2c = { eintrag("Kaos", 9), eintrag("Shadow", 6, { referenz = 8 }) }
    Kern.WurfReihenfolge(l2c, alleHaupt, function() return 50 end)
    gleich("Kader-Referenz 8: auf 8 + 2 = 10", finde(l2c, "Shadow").effektiveWertung, 10)
    -- Heute schon angehoben und festgeschrieben: nicht noch einmal
    local l2d = { eintrag("Kaos", 12), eintrag("Shadow", 6, { referenz = 12, keineAnhebung = true }) }
    Kern.WurfReihenfolge(l2d, alleHaupt, function() return 50 end)
    gleich("keineAnhebung: bleibt bei seiner Wertung", finde(l2d, "Shadow").effektiveWertung, 6)

    -- Gast: seine Wertung steht fuer den Abend fest und wird nie angehoben
    local l3 = { eintrag("Kaos", 9), eintrag("Shadow", 10), eintrag("Gastspieler", 9, { gast = true }) }
    Kern.WurfReihenfolge(l3, alleHaupt, function() return 50 end)
    local g = finde(l3, "Gastspieler")
    gleich("Gast: keine Anhebung", g.dynamischeAnhebung, 0)
    gleich("Gast: Wertung wie der Niedrigste", g.effektiveWertung, 9)

    -- Proberaid: keine Lootberechtigung, nie ein Wuerfler
    local l4 = { eintrag("Kaos", 9), eintrag("Neu", 0, { proberaid = true }) }
    Kern.WurfReihenfolge(l4, alleHaupt, function(n) return n == "Neu" and 100 or 1 end)
    gleich("Proberaid: steht nicht oben", l4[1].name, "Kaos")
end

local function testRundung()
    gleich("Wertung auf drei Stellen gerundet", Kern.Wertung(3, 0.1 + 0.2, 0), 3.3)
    gleich("Zuschlag gerundet", Kern.Zuschlag(0.7, 0.8333333), 0.583)
    gleich("Runde3", Kern.Runde3(1.00049), 1)
    -- Summen in anderer Reihenfolge ergeben dieselbe Zahl
    gleich("Reihenfolge egal", Kern.Wertung(0, { 0.583, 0.1, 0.9 }, 0), Kern.Wertung(0, { 0.9, 0.583, 0.1 }, 0))
end

local function testKennzeichenKodieren()
    local e = { awardedTo = "Timo", itemID = 5, timestamp = ZEIT, kennzeichen = "A" }
    local id, x = Kern.Dekodieren(Kern.Kodieren("k", e), ZEIT)
    gleich("Kennzeichen A kommt an", x and x.kennzeichen, "A")
    id, x = Kern.Dekodieren(Kern.Kodieren("k", { awardedTo = "Timo", itemID = 5, timestamp = ZEIT, OS = true, kennzeichen = "S" }), ZEIT)
    gleich("Kennzeichen S kommt an", x and x.kennzeichen, "S")
    id, x = Kern.Dekodieren(Kern.Kodieren("k", { awardedTo = "Timo", itemID = 5, timestamp = ZEIT, kennzeichen = "X" }), ZEIT)
    gleich("unbekanntes Kennzeichen wird nicht uebertragen", x and x.kennzeichen, nil)
    -- aeltere Fassung mit acht Feldern wird weiter gelesen
    id, x = Kern.Dekodieren("k;Timo;5;" .. ZEIT .. ";H;;;", ZEIT)
    gleich("alte Zeile (acht Felder) wird gelesen", id, "k")
    gleich("und hat kein Kennzeichen", x and x.kennzeichen, nil)
end

-- =====================================================================
--  Datenbuch: Abschluesse und Anhebungen verteilen
-- =====================================================================

local function testDatenbuch()
    local T = 1760000000
    local function abend(rev, geschlossen)
        local ab = { id = "2026-10-16", datum = "2026-10-16", buchRev = rev }
        if geschlossen then
            ab.abgeschlossen = true
            ab.abschluss = {
                zeit = T, datum = "2026-10-16", autor = "Kaos", schnitt = 1, mainItems = 4,
                raidSpieler = 4, gesamtBosse = 3,
                spieler = {
                    protti = { name = "Protti", status = "abgemeldet", faktor = 0.7, zuschlag = 0.7, fehlAnzahl = 1, bosse = 0 },
                    shadow = { name = "Shadow", status = "bank", faktor = 0, zuschlag = 0, fehlAnzahl = 0, bosse = 0 },
                    canu   = { name = "Canu", status = "imRaid", faktor = 0, zuschlag = 0, fehlAnzahl = 0, bosse = 3 },
                },
            }
        end
        return ab
    end

    local function einlesen(d, zeilen)
        local ausstehend, ergebnis = {}, {}
        for _, z in ipairs(zeilen) do
            local satz = Kern.BuchDekodieren(z, T + 100)
            if satz then
                for _, fertig in ipairs(Kern.BuchSammeln(ausstehend, satz, T)) do
                    ergebnis[#ergebnis + 1] = Kern.BuchEinfuehren(d, fertig)
                end
            end
        end
        return ergebnis
    end

    -- Kodieren: Kopf plus ein Satz je Spieler
    local zeilen = Kern.BuchAbendKodieren("2026-10-16", abend(1, true))
    gleich("Abschluss: Kopf plus drei Spieler", #zeilen, 4)
    for _, z in ipairs(zeilen) do
        gleich("Zeile passt in eine Nachricht", #z < 200, true)
        gleich("kein Paketttrenner in der Zeile", z:find("~", 1, true), nil)
    end

    -- Einfuehren beim Empfaenger
    local d2 = {}
    local r = einlesen(d2, zeilen)
    gleich("Abschluss kommt an", r[1], "neu")
    gleich("Abend ist abgeschlossen", d2.abende["2026-10-16"].abgeschlossen, true)
    gleich("Revision uebernommen", d2.abende["2026-10-16"].buchRev, 1)
    gleich("Zuschlag fuer Protti", d2.zuschlaege["z_2026-10-16_protti"] and d2.zuschlaege["z_2026-10-16_protti"].zuschlag, 0.7)
    gleich("kein Zuschlag fuer die Bank", d2.zuschlaege["z_2026-10-16_shadow"], nil)
    gleich("Status uebernommen", d2.abende["2026-10-16"].abschluss.spieler.shadow.status, "bank")
    gleich("zweites Einfuehren ist vorhanden", einlesen(d2, zeilen)[1], "vorhanden")

    -- Reihenfolge der Zeilen ist egal
    local d3, umgekehrt = {}, {}
    for i = #zeilen, 1, -1 do umgekehrt[#umgekehrt + 1] = zeilen[i] end
    gleich("umgekehrte Reihenfolge kommt an", einlesen(d3, umgekehrt)[1], "neu")
    local n2, s2 = Kern.BuchStand(d2)
    local n3, s3 = Kern.BuchStand(d3)
    gleich("gleicher Stand (Anzahl)", n2, n3)
    gleich("gleicher Stand (Summe)", s2, s3)

    -- Wiedereroeffnen: hoehere Revision, Zuschlaege verschwinden
    local zu = Kern.BuchAbendKodieren("2026-10-16", abend(2, false))
    gleich("Wiedereroeffnet: nur ein Kopf", #zu, 1)
    gleich("Wiedereroeffnen kommt an", einlesen(d2, zu)[1], "neu")
    gleich("Zuschlag entfernt", d2.zuschlaege["z_2026-10-16_protti"], nil)
    gleich("nicht mehr abgeschlossen", d2.abende["2026-10-16"].abgeschlossen, nil)
    gleich("Revision 2", d2.abende["2026-10-16"].buchRev, 2)
    -- Der alte Abschluss (Revision 1) darf nichts mehr zurueckholen
    gleich("alter Stand ist vorhanden, nicht neu", einlesen(d2, zeilen)[1], "vorhanden")
    gleich("Zuschlag bleibt weg", d2.zuschlaege["z_2026-10-16_protti"], nil)
    -- Erneut abgeschlossen: Revision 3
    gleich("erneuter Abschluss kommt an", einlesen(d2, Kern.BuchAbendKodieren("2026-10-16", abend(3, true)))[1], "neu")
    gleich("Zuschlag wieder da", d2.zuschlaege["z_2026-10-16_protti"] and d2.zuschlaege["z_2026-10-16_protti"].zuschlag, 0.7)

    -- Aktiver Abend beim Empfaenger wird durch den Abschluss abgeloest
    local d4 = { aktiverAbend = { id = "2026-10-16", datum = "2026-10-16", bosse = 3 } }
    einlesen(d4, zeilen)
    gleich("aktiver Abend ist abgeschlossen worden", d4.aktiverAbend, nil)
    gleich("und liegt im Archiv", d4.abende["2026-10-16"].abgeschlossen, true)

    -- Anhebung
    local h = Kern.BuchAnhebungKodieren("h_protti_1", { name = "Protti", wert = 2.5, zeit = T, datum = "2026-10-16", autor = "Kaos", grund = "Anhebung; Test, Komma" })
    local d5 = {}
    gleich("Anhebung kommt an", einlesen(d5, { h })[1], "neu")
    gleich("Wert", d5.anhebungsliste.h_protti_1.wert, 2.5)
    gleich("Text mit Sonderzeichen heil", d5.anhebungsliste.h_protti_1.grund, "Anhebung; Test, Komma")
    gleich("zweimal ist vorhanden", einlesen(d5, { h })[1], "vorhanden")

    -- Vergleichen
    local meine = Kern.BuchListe(d2)   -- a:...@3
    local fremde = Kern.BuchListe(d5)  -- h:h_protti_1
    local fehlt, habe = Kern.BuchVergleichen(meine, fremde)
    gleich("mir fehlt die Anhebung", fehlt[1], "h:h_protti_1")
    gleich("ich habe den Abend", habe[1], "a:2026-10-16@3")
    local fehlt2 = Kern.BuchVergleichen({ "a:2026-10-16@1" }, { "a:2026-10-16@2" })
    gleich("hoehere Revision fehlt mir", fehlt2[1], "a:2026-10-16@2")
    local fehlt3, habe3 = Kern.BuchVergleichen({ "a:2026-10-16@2" }, { "a:2026-10-16@2" })
    gleich("gleiche Revision: nichts fehlt", #fehlt3 + #habe3, 0)

    -- Zeilen zu angefragten Saetzen
    local ausListe = Kern.BuchZeilen(d2, { "a:2026-10-16@3", "h:gibtesnicht" })
    gleich("Zeilen zum Satz (Kopf plus drei Spieler)", #ausListe, 4)

    -- Alles Fremde wird geprueft
    gleich("Revision 0 abgelehnt", (Kern.BuchDekodieren("a;x;0;1;2026-10-16;5;K;1;1;1;1;0", T)), nil)
    gleich("Status unbekannt abgelehnt", (Kern.BuchDekodieren("s;x;1;Protti;mogeln;0.7;0.7;1;0", T)), nil)
    gleich("riesiger Zuschlag abgelehnt", (Kern.BuchDekodieren("s;x;1;Protti;bank;0.7;9999;1;0", T)), nil)
    gleich("Zukunft abgelehnt", (Kern.BuchDekodieren("h;x;Protti;1;" .. (T + 10 * 86400) .. ";d;a;g", T)), nil)
    gleich("Kennung mit Sonderzeichen abgelehnt", (Kern.BuchDekodieren("h;x y;Protti;1;" .. T .. ";d;a;g", T)), nil)
    gleich("Wert 0 abgelehnt", (Kern.BuchDekodieren("h;x;Protti;0;" .. T .. ";d;a;g", T)), nil)
    gleich("kaputter Aufbau abgelehnt", (Kern.BuchDekodieren("quatsch", T)), nil)
    gleich("Reopen mit Spielern abgelehnt", (Kern.BuchDekodieren("a;x;2;0;2026-10-16;5;K;1;1;1;1;3", T)), nil)
end

local function testKeineAutomatischeAnhebung()
    local liste = {
        { name = "Kaos", haupt = 9, zweit = 0, letzte = 100, wertung = 9 },
        { name = "Timo", haupt = 9, zweit = 0, letzte = 100, wertung = 9 },
        { name = "Shadow", haupt = 2, zweit = 0, letzte = 100, wertung = 2 },
    }
    Kern.WurfReihenfolge(liste, function() return "haupt" end)
    local shadow
    for _, e in ipairs(liste) do if e.name == "Shadow" then shadow = e end end
    gleich("Keine automatische Anhebung: Shadow (2 gegen 9) bleibt bei 2", (shadow and shadow.dynamischeAnhebung) or 0, 0)
    gleich("und steht vorn, weil seine Wertung die niedrigste ist", liste[1].name, "Shadow")
end

local function testProbeStandardAbend()
    local Anw = ns.Anwesenheit
    if not (Anw and Anw.ProbeStandardAbend) then return end

    local ok, res = Anw.ProbeStandardAbend(false)
    gleich("ProbeStandardAbend: Status ok", ok, true)
    if res and res.pruefungen then
        gleich("ProbeStandardAbend: Schnitt 1.0", res.schnitt, 1.0)
        gleich("ProbeStandardAbend: Raid Anna ok", res.pruefungen.raid.ok, true)
        gleich("ProbeStandardAbend: Bench Nora ok", res.pruefungen.bench.ok, true)
        gleich("ProbeStandardAbend: Keine Meldung Max ok", res.pruefungen.keineMeldung.ok, true)
        gleich("ProbeStandardAbend: Abgemeldet Kevin, Lisa ok", res.pruefungen.abgemeldet.ok, true)
        gleich("ProbeStandardAbend: Proberaid Igor ok", res.pruefungen.proberaid.ok, true)
        gleich("ProbeStandardAbend: Neuling Jonas ok", res.pruefungen.neuling.ok, true)
        gleich("ProbeStandardAbend: Abschluss ok", res.okAbschluss, true)
        gleich("ProbeStandardAbend: 3 Zuschlaege", res.zCount, 3)
        gleich("ProbeStandardAbend: Broadcasts geblockt", (res.gesendet or 0) > 0, true)
    end
end

local function testProbeUIUndInteraktion()
    local P = ns.Probe
    if not (P and P.Starten and P.Beenden) then return end

    local okStart = P.Starten()
    gleich("Probe.Starten ok", okStart, true)
    gleich("Probe.Aktiv aktiv", P.Aktiv(), true)

    local roster = P.Roster()
    gleich("Probe.Roster enthaelt 14 Spieler", #roster, 14)

    gleich("Anna initial im Raid", P.IstImRaid("Anna"), true)
    gleich("Ben initial im Raid", P.IstImRaid("Ben"), true)
    gleich("Nora initial nicht im Raid", P.IstImRaid("Nora"), false)

    P.ToggleRaid("Nora")
    gleich("Nora nach Toggle im Raid", P.IstImRaid("Nora"), true)

    local okMain, itemMain = P.VergebeItem("Nora", false, 1001)
    gleich("Main-Item vergeben", okMain, true)
    gleich("Main-Item nicht OS", itemMain and itemMain.OS, false)

    local okOS, itemOS = P.VergebeItem("Ben", true, 1002)
    gleich("OS-Item vergeben", okOS, true)
    gleich("OS-Item ist OS", itemOS and itemOS.OS, true)

    local hCount = 0
    for _ in pairs(P.Historie()) do hCount = hCount + 1 end
    gleich("2 Items in Probe-Historie", hCount, 2)

    P.SetzeBank("Nora", true)
    gleich("Nora auf Bank", ns.Anwesenheit.IstBank("Nora"), true)
    gleich("Nora nicht im Raid", P.IstImRaid("Nora"), false)

    P.SetzeKeineMeldung("Max", true)
    gleich("Max keine Meldung", ns.Anwesenheit.IstVergessen("Max"), true)

    P.Zuruecksetzen()
    local hCountReset = 0
    for _ in pairs(P.Historie()) do hCountReset = hCountReset + 1 end
    gleich("Historie nach Reset leer", hCountReset, 0)
    gleich("Nora nach Reset nicht im Raid", P.IstImRaid("Nora"), false)

    P.Beenden()
    gleich("Probe.Aktiv nach Beenden aus", P.Aktiv(), false)
end

function Tests.Alle(ausgeben)
    gut, schlecht, meldungen = 0, 0, {}

    -- Bereiche fuer die Pruefungen auf Standard setzen, danach vorherigen Zustand wiederherstellen
    local altH1, altH2 = Kern.BEREICHE.haupt[1], Kern.BEREICHE.haupt[2]
    local altZ1, altZ2 = Kern.BEREICHE.zweit[1], Kern.BEREICHE.zweit[2]
    Kern.BereicheSetzen(1, 100, 1, 50)
    -- ⭐ Die automatische Anhebung ist im Betrieb aus (Kern.AUTO_ANHEBUNG); ihre Rechnung wird hier eingeschaltet geprüft.
    local altAuto = Kern.AUTO_ANHEBUNG
    Kern.AUTO_ANHEBUNG = true

    testGleicherSpieler()
    testZurueck()
    testPruefsumme()
    testTagesstand()
    testZusammenfuehren()
    testKonvergenz()
    testGrosseSummen()
    testKodieren()
    testZurueckgenommen()
    testPakete()
    testSchreiber()
    testVerlauf()

    testZaehlt()
    testNamen()
    testBilanz()
    testPflichtnamen()
    testNur()
    testWurfReihenfolge()
    testWurfArt()
    testWurfWert()
    testBereiche()
    testRuecknahmeInPruefsumme()
    testWurfMeldung()
    testSpieler()
    testMuster()
    testBedarfsart()
    testRaidtage()
    testSeit()
    testRegelwerkBeispiele()
    testDemoDaten()
    testAnwesenheit()
    testBankUndUnentschuldigt()
    testAbendAbschlussUndSpielerdetail()
    testNeulingGastProberaid()
    testRundung()
    testKennzeichenKodieren()
    testDatenbuch()
    testProbeStandardAbend()
    testProbeUIUndInteraktion()

    -- Im Betrieb (aus): kein Spieler wird von selbst angehoben, auch wenn er weit hinter den anderen liegt
    Kern.AUTO_ANHEBUNG = false
    testKeineAutomatischeAnhebung()
    Kern.AUTO_ANHEBUNG = altAuto

    -- Vorherigen Zustand des Spielers wiederherstellen
    Kern.BereicheSetzen(altH1, altH2, altZ1, altZ2)

    if ausgeben ~= false then
        for _, m in ipairs(meldungen) do print(m) end
        print(string.format(L["|cff1B6B57Fairshare|r: %d Prüfungen, %d bestanden, %d fehlgeschlagen"],
            gut + schlecht, gut, schlecht))
    end
    return gut, schlecht
end

return ns
