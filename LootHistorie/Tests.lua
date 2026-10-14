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

    -- ⭐ Genau sieben Feldtrenner: alles andere muss geschuetzt sein
    local trenner = select(2, zeile:gsub(";", ""))
    gleich("sieben Feldtrenner", trenner, 7)
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

local function testPflichtnamen2()
    local kader = { modus = "kader", kader = { "A", "B", "C" } }
    local raid  = { modus = "raid",  kader = { "A" } }

    gleich("Kader: die Liste", #Kern.Pflichtnamen(kader, { "X" }), 3)
    gleich("Raidgruppe: wer gerade da ist", Kern.Pflichtnamen(raid, { "X", "Y" })[2], "Y")
    gleich("Raidgruppe ohne Gruppe", #Kern.Pflichtnamen(raid, nil), 0)
    gleich("keine Gruppe", #Kern.Pflichtnamen(nil, { "X" }), 0)
end

-- =====================================================================

function Tests.Alle(ausgeben)
    gut, schlecht, meldungen = 0, 0, {}

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
    testPflichtnamen2()

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
        print(string.format(L["|cff1B6B57Loot-Historie|r: %d Prüfungen, %d bestanden, %d fehlgeschlagen"],
            gut + schlecht, gut, schlecht))
    end
    return gut, schlecht
end

return ns
