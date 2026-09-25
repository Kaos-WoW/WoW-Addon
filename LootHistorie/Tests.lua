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
    testSpieler()
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
