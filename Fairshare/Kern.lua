--[[----------------------------------------------------------------------
    Kern.lua  —  Auswertung der Vergabe-Historie

    Enthaelt ausschliesslich Rechnerei: keine WoW-API, keine Frames, keine
    Events. Dadurch laeuft diese Datei im Spiel UND in einem gewoehnlichen
    Lua-Interpreter, und der Pruefstand kann sie ohne Client testen.

    ⭐ **Alles Rechnerische liegt hier**, auch das Zusammenfuehren zweier
    Historien, die Pruefsummen fuer den Abgleich und die Wahl des
    Schreibers. Dadurch ist es ohne Client pruefbar — und genau die Teile,
    bei denen ein Fehler still Daten verfaelscht, haben ihre Tests.

    Jede Funktion bekommt die Historie als Parameter. Dadurch laesst sich
    dieselbe Auswertung mit Beispieldaten fuettern, ohne irgendwo etwas
    abzulegen.
------------------------------------------------------------------------]]

local _, ns = ...
ns = ns or {}

local Kern = {}
ns.Kern = Kern

Kern.WOCHE = 604800
Kern.TAG   = 86400

-- Gargul traegt diesen Namen als Gewinner ein, wenn entzaubert wurde.
Kern.ENTZAUBERT = "||de||"

-- =====================================================================
--  Einzelne Eintraege
-- =====================================================================

--- Zaehlt diese Vergabe als Zuteilung an einen Spieler?
--
--  ⚠️ Drei Faelle fallen heraus, und jeder aus einem eigenen Grund:
--  * **Entzaubert** — der Gegenstand ging an niemanden.
--  * **Bonus-Beute** — zusaetzliche Beute ausserhalb der Vergabe.
--  * **Unvollstaendig** — ohne Gewinner oder Zeitstempel nicht auswertbar.
--
--  @return true, oder false und der Grund
function Kern.Zaehlt(e)
    if type(e) ~= "table" then return false, "kein Eintrag" end
    if not e.awardedTo or e.awardedTo == "" then return false, "ohne Gewinner" end
    if e.awardedTo == Kern.ENTZAUBERT then return false, "entzaubert" end
    if e.isBonusLoot then return false, "Bonus-Beute" end
    if e.zurueck then return false, "zurückgenommen" end
    if not tonumber(e.timestamp) then return false, "ohne Zeitstempel" end
    return true
end

--- Schluessel, unter dem ein Spieler gefuehrt wird.
--
--  ⚠️ Gargul schreibt den Gewinner mal mit, mal ohne Realm — je nachdem,
--  ob die Vergabe lokal entstand oder ueber die Gruppe hereinkam. Ohne
--  Vereinheitlichung steht derselbe Spieler zweimal in der Liste.
--  Das setzt eine Gilde auf einem Realm voraus; zwei Gleichnamige von
--  verschiedenen Realms liefen zusammen.
function Kern.Schluessel(name)
    if type(name) ~= "string" or name == "" then return nil end
    return (name:match("^([^%-]+)") or name):lower()
end

--- Wie der Name angezeigt wird: ohne Realm, erster Buchstabe gross.
function Kern.Anzeigename(name)
    if type(name) ~= "string" or name == "" then return "?" end
    local kurz = name:match("^([^%-]+)") or name
    return kurz:sub(1, 1):upper() .. kurz:sub(2)
end

-- =====================================================================
--  Auswertung
-- =====================================================================

--- Wer hat wie viel bekommen.
--
--  Sortiert nach Hauptbedarf. ⚠️ Zweitbedarf wird getrennt gefuehrt und
--  fliesst NICHT in die Reihenfolge ein: Wer einen Gegenstand fuer die
--  Zweitrolle bekommt, hat damit keinen Anspruch verbraucht. Er steht
--  trotzdem da, weil die Leitung ihn sehen will.
--
--  ⚠️ **Wer nichts bekommen hat, steht in Garguls Historie nicht.**
--  Ausgerechnet der ist aber der Interessanteste, wenn gerade gewuerfelt
--  wird. Darum nimmt `pflicht` Namen entgegen, die auch mit null
--  Vergaben in der Liste auftauchen muessen.
--
--  @param historie  Tabelle: Pruefsumme -> Eintrag
--  @param seit      Zeitstempel, ab dem gezaehlt wird; nil = alles
--  ⭐ `nur` ist das Gegenstueck: Dann zaehlen und erscheinen AUSSCHLIESSLICH
--  diese Namen (die Spieler, die gerade in der Gruppe stehen). Wer nicht
--  dazugehoert, fehlt in Liste und Summe. Ein Name der Historie ohne
--  Nachnamen wird dem Namen MIT Nachnamen aus `nur` zugeschlagen, damit
--  niemand doppelt in der Liste steht.
--
--  @param historie  Tabelle: Pruefsumme -> Eintrag
--  @param seit      Zeitstempel, ab dem gezaehlt wird; nil = alles
--  @param pflicht   Liste von Namen, die in jedem Fall erscheinen
--  @param nur       Liste von Namen; wenn gegeben, nur diese
--  @return Liste aus { name, haupt, zweit, letzte, letzterEintrag },
--          Zahl der gezaehlten Vergaben, aeltester Zeitstempel
function Kern.Bilanz(historie, seit, pflicht, nur, daten)
    if type(historie) ~= "table" then historie = {} end
    seit = seit or 0

    local nach, gesamt, aeltester = {}, 0, nil
    local gemerkt = {}

    -- Mit `nur`: der passende Name aus der Liste oder nil
    local function zugelassen(name)
        if not nur then return name end
        local k = Kern.Schluessel(name)
        if not k then return nil end
        if gemerkt[k] ~= nil then return gemerkt[k] or nil end
        local treffer = false
        for _, n in ipairs(nur) do
            if Kern.GleicherSpieler(n, name) then treffer = n break end
        end
        gemerkt[k] = treffer
        return treffer or nil
    end

    local function eintragFuer(name)
        name = zugelassen(name)
        if not name then return nil end
        local k = Kern.Schluessel(name)
        if not k then return nil end
        local z = nach[k]
        if not z then
            local zuschlag = (daten and daten.zuschlaege and (daten.zuschlaege[k] or daten.zuschlaege[name])) or 0
            local anhebung = (daten and daten.anhebungen and (daten.anhebungen[k] or daten.anhebungen[name])) or 0
            z = {
                name = Kern.Anzeigename(name),
                haupt = 0,
                zweit = 0,
                letzte = 0,
                zuschlag = zuschlag,
                anhebung = anhebung,
                wertung = Kern.Wertung(0, zuschlag, anhebung),
            }
            nach[k] = z
        end
        return z
    end

    for _, name in ipairs(pflicht or {}) do eintragFuer(name) end

    for _, e in pairs(historie) do
        local z
        if Kern.Zaehlt(e) and e.timestamp >= seit then z = eintragFuer(e.awardedTo) end
        if z then
            if e.OS then
                z.zweit = z.zweit + 1
            else
                z.haupt = z.haupt + 1
                z.wertung = Kern.Wertung(z.haupt, z.zuschlag, z.anhebung)
                -- „Zuletzt" meint Hauptbedarf. Ein Zweitbedarfs-Stueck
                -- sagt ueber den Anspruch nichts aus.
                if e.timestamp > z.letzte then
                    z.letzte = e.timestamp
                    z.letzterEintrag = e
                end
            end

            gesamt = gesamt + 1
            if not aeltester or e.timestamp < aeltester then aeltester = e.timestamp end
        end
    end

    local liste = {}
    for _, z in pairs(nach) do liste[#liste + 1] = z end

    -- ⭐ Wertung und Vorrang (Golf-Prinzip):
    -- Wer die niedrigste Wertung hat, hat Vorrang (Niedrig = zuerst).
    table.sort(liste, function(a, b)
        if a.wertung ~= b.wertung then return a.wertung < b.wertung end
        if a.zweit ~= b.zweit then return a.zweit < b.zweit end
        if a.letzte ~= b.letzte then return a.letzte < b.letzte end
        return a.name < b.name
    end)

    return liste, gesamt, aeltester
end

--- Alle Vergaben eines Spielers, neueste zuerst.
--  @return Liste aus { zeit, eintrag, zweit }
function Kern.Spieler(historie, name, seit)
    if type(historie) ~= "table" then return {} end
    local gesucht = Kern.Schluessel(name)
    if not gesucht then return {} end
    seit = seit or 0

    local liste = {}
    for id, e in pairs(historie) do
        if Kern.Zaehlt(e) and e.timestamp >= seit
           and Kern.Schluessel(e.awardedTo) == gesucht then
            liste[#liste + 1] = {
                id      = id,
                zeit    = e.timestamp,
                eintrag = e,
                zweit   = e.OS and true or false,
            }
        end
    end

    table.sort(liste, function(a, b) return a.zeit > b.zeit end)
    return liste
end

--- Verschiedene Kalendertage mit mindestens einer Vergabe.
--
--  ⚠️ Das ist NICHT Anwesenheit. Wer da war und nichts bekam, steht in
--  Garguls Daten nirgends. Die Zahl taugt als Bezugsgroesse fuer „viel"
--  und „wenig", nicht als Teilnahmenachweis.
--
--  @param tagOf  Funktion Zeitstempel -> Tagesschluessel (wegen date())
function Kern.Raidtage(historie, seit, tagOf)
    if type(historie) ~= "table" or not tagOf then return 0 end
    seit = seit or 0

    local tage, n = {}, 0
    for _, e in pairs(historie) do
        if Kern.Zaehlt(e) and e.timestamp >= seit then
            local tag = tagOf(e.timestamp)
            if not tage[tag] then tage[tag] = true; n = n + 1 end
        end
    end
    return n
end

--- Reihenfolge waehrend eines Wurfs.
--
--  ⭐ Wer gewuerfelt hat, steht oben — und dort **der mit den wenigsten
--  Stuecken zuerst**, bei gleicher Stueckzahl der mit dem hoechsten Wurf.
--  Genau diese Frage stellt sich der Pluendermeister in dem Moment. Alle uebrigen folgen in der gewohnten Reihenfolge,
--  damit der Ueberblick nicht verlorengeht.
--
--  @param liste        Ergebnis von Kern.Bilanz
--  @param istWuerfler  Funktion Name -> false/nil (kein Wurf), true (Wurf,
--                      Art unbekannt), "haupt" oder "zweit"
--  @param wurfWert     Funktion Name -> Zahl (optional): bei gleicher Stueckzahl
--                      steht der hoehere Wurf oben
function Kern.WurfReihenfolge(liste, istWuerfler, wurfWert)
    if not istWuerfler then return liste end

    local function rang(x)
        if not x then return 0 end
        if x == "haupt" then return 3 end
        if x == "zweit" then return 1 end
        return 2
    end

    -- ⭐ Proberaid (§ 4): Wer am ersten Abend im Kader ist, hat keine Lootberechtigung
    -- und gilt hier nie als Wuerfler.
    local function wuerfelt(e)
        if e.proberaid then return false end
        return istWuerfler(e.name)
    end

    -- Dynamische Anhebung fuer Hauptbedarf-Wuerfler (§ 3):
    -- Wer mehr als 1 Punkt unter dem Niedrigsten der anderen (`referenz`: Kader im Raid,
    -- sonst die Wuerfler) liegt, wird auf dessen Wertung PLUS `ANHEBUNG_ABSTAND` gesetzt —
    -- hinter die anderen, ohne sicheres Item. Festgeschrieben wird das einmal je Abend
    -- (Anwesenheit.Rollen); bis dahin zeigt es die Rangliste nur an.
    -- Ausnahmen: Ein Neuling am 2. Abend (§ 4) kommt auf den Niedrigsten der
    -- Kaderspieler im Raid plus 2 (`neulingZiel`, wie die Anhebung); ein Gast hat seine
    -- Wertung fuer den Abend schon bekommen (`gast`) und wird nie angehoben.
    local hauptWuerfler = {}
    for _, e in ipairs(liste) do
        local r = rang(wuerfelt(e))
        if r >= 2 then
            hauptWuerfler[#hauptWuerfler + 1] = {
                eintrag = e,
                wertung = e.wertung or e.haupt or 0,
            }
        end
    end

    if #hauptWuerfler >= 2 then
        for i, item in ipairs(hauptWuerfler) do
            local minAndere = nil
            for j, anderer in ipairs(hauptWuerfler) do
                if i ~= j then
                    if not minAndere or anderer.wertung < minAndere then
                        minAndere = anderer.wertung
                    end
                end
            end
            local x = item.eintrag
            -- Bezugspunkt: der Niedrigste der Kaderspieler im Raid (ohne ihn selbst), sonst der Niedrigste der Wuerfler
            local ref = x.referenz or minAndere
            local ziel = x.neuling and (x.neulingZiel or (minAndere and minAndere + Kern.ANHEBUNG_ABSTAND)) or nil
            if x.gast then
                x.effektiveWertung = item.wertung
                x.dynamischeAnhebung = 0
            elseif ziel and (ziel - item.wertung) > 1e-9 then
                x.effektiveWertung = ziel
                x.dynamischeAnhebung = Kern.Runde3(ziel - item.wertung)
            elseif x.keineAnhebung then
                -- an diesem Abend schon angehoben und festgeschrieben: nicht noch einmal
                x.effektiveWertung = item.wertung
                x.dynamischeAnhebung = 0
            elseif ref and (ref - item.wertung) > 1 + 1e-9 then
                x.effektiveWertung = Kern.Runde3(ref + Kern.ANHEBUNG_ABSTAND)
                x.dynamischeAnhebung = Kern.Runde3(x.effektiveWertung - item.wertung)
            else
                item.eintrag.effektiveWertung = item.wertung
                item.eintrag.dynamischeAnhebung = 0
            end
        end
    elseif #hauptWuerfler == 1 then
        hauptWuerfler[1].eintrag.effektiveWertung = hauptWuerfler[1].wertung
        hauptWuerfler[1].eintrag.dynamischeAnhebung = 0
    end

    table.sort(liste, function(a, b)
        local ra, rb = rang(wuerfelt(a)), rang(wuerfelt(b))
        if ra ~= rb then return ra > rb end

        if ra >= 2 then
            -- Hauptbedarf:
            -- 1. Niedrigste Wertung zuerst (Golf-Prinzip)
            local wa = a.effektiveWertung or a.wertung or a.haupt or 0
            local wb = b.effektiveWertung or b.wertung or b.haupt or 0
            if wa ~= wb then return wa < wb end

            -- 2. Bei gleicher Wertung entscheidet der hoehere Wurf
            if wurfWert then
                local rwa = tonumber(wurfWert(a.name)) or 0
                local rwb = tonumber(wurfWert(b.name)) or 0
                if rwa ~= rwb then return rwa > rwb end
            end

            -- 3. Bei Gleichstand wer laenger kein Hauptstueck hatte
            if a.letzte ~= b.letzte then return a.letzte < b.letzte end
            return a.name < b.name
        elseif ra == 1 then
            -- Zweitbedarf:
            -- 1. Weniger Zweitbedarfs-Stuecke zuerst
            if a.zweit ~= b.zweit then return a.zweit < b.zweit end

            -- 2. Hoeherer Wurf
            if wurfWert then
                local rwa = tonumber(wurfWert(a.name)) or 0
                local rwb = tonumber(wurfWert(b.name)) or 0
                if rwa ~= rwb then return rwa > rwb end
            end

            if a.letzte ~= b.letzte then return a.letzte < b.letzte end
            return a.name < b.name
        else
            -- Nicht-Wuerfler: nach Wertung
            local wa = a.wertung or a.haupt or 0
            local wb = b.wertung or b.haupt or 0
            if wa ~= wb then return wa < wb end
            if a.zweit ~= b.zweit then return a.zweit < b.zweit end
            if a.letzte ~= b.letzte then return a.letzte < b.letzte end
            return a.name < b.name
        end
    end)

    return liste
end

-- =====================================================================
--  Wertung und Vorrang (Regelwerk 16.10.2026)
-- =====================================================================

Kern.FENSTER_ABENDE = 6
Kern.FAKTOR_UNENTSCHULDIGT = 1.5
-- ⭐ Wer angemeldet war und nicht erschien, bekommt mindestens so viele Wertungspunkte
-- (Gildenleitung 17.10.2026): Faktor 1,5, aber nie weniger als 2 Punkte.
Kern.MIN_ZUSCHLAG_UNENTSCHULDIGT = 2.0
-- ⭐ Anhebung (§ 3, Gildenleitung 17.10.2026): Wer weit hinter allen liegt, wird auf den Niedrigsten
-- der Kaderspieler im Raid PLUS diesen Abstand gesetzt — hinter sie, ohne sicheres Item.
Kern.ANHEBUNG_ABSTAND = 2
-- ⭐ „Anmeldung vergessen" (Gildenleitung 17.10.2026): Wer innerhalb von `VERGESSEN_FENSTER` Raidabenden
-- MEHR als `VERGESSEN_SCHWELLE` Mal weder an- noch abgemeldet war und nicht kam, wird wie unentschuldigt
-- behandelt (Faktor 1,5, mindestens 2 Punkte). Davor gilt der Abend wie eine normale Abmeldung.
Kern.VERGESSEN_SCHWELLE = 2
Kern.VERGESSEN_FENSTER = 8      -- 4 Raid-IDs zu je 2 Abenden
Kern.FAKTOR_BANK = 0
Kern.FEHL_FAKTOREN = {
    [1] = 0.7,
    [2] = 1.0,
    [3] = 1.0,
    [4] = 1.0,
    [5] = 1.3,
}
Kern.FAKTOR_AB_SECHS = 1.5

--- Ermittelt den Faktor fuer einen verpassten Abend (§ 2).
--  @param fehlAnzahl  Zahl der Fehlabende im Fenster (inklusive des aktuellen)
--  @param grund       "abgemeldet" | "unentschuldigt" | "bank"
--  @return Faktor (Zahl)
function Kern.FehlFaktor(fehlAnzahl, grund)
    if grund == "bank" then return Kern.FAKTOR_BANK end
    if grund == "unentschuldigt" then return Kern.FAKTOR_UNENTSCHULDIGT end
    local n = math.max(1, tonumber(fehlAnzahl) or 1)
    if n >= 6 then return Kern.FAKTOR_AB_SECHS end
    return Kern.FEHL_FAKTOREN[n] or 1.0
end

--- Schnitt des Abends: vergebene Main-Items / Spieler im Raid (§ 2).
--  @param mainItems      Zahl der an diesem Abend vergebenen Main-Items
--  @param spielerAnzahl  Zahl der Spieler im Raid
--  @return Schnitt (Zahl, 0 wenn keine Spieler)
function Kern.AbendSchnitt(mainItems, spielerAnzahl)
    mainItems = tonumber(mainItems) or 0
    spielerAnzahl = tonumber(spielerAnzahl) or 0
    if spielerAnzahl <= 0 then return 0 end
    return mainItems / spielerAnzahl
end

--- Zuschlag fuer einen verpassten Abend (§ 2): Faktor * Schnitt des Abends.
--  @param faktor   Faktor des Abends (z. B. 0.7, 1.0, 1.3, 1.5, 0)
--  @param schnitt  Schnitt des Abends
--  @return Zuschlag (Zahl)
function Kern.Zuschlag(faktor, schnitt)
    return Kern.Runde3((tonumber(faktor) or 0) * (tonumber(schnitt) or 0))
end

--- Zuschlag fuer einen unentschuldigten Abend: Faktor x Schnitt, mindestens `MIN_ZUSCHLAG_UNENTSCHULDIGT`.
--  @return Zuschlag, Faktor, ob das Minimum gegriffen hat
function Kern.ZuschlagUnentschuldigt(schnitt)
    local roh = Kern.Zuschlag(Kern.FAKTOR_UNENTSCHULDIGT, schnitt)
    if roh < Kern.MIN_ZUSCHLAG_UNENTSCHULDIGT then
        return Kern.MIN_ZUSCHLAG_UNENTSCHULDIGT, Kern.FAKTOR_UNENTSCHULDIGT, true
    end
    return roh, Kern.FAKTOR_UNENTSCHULDIGT, false
end

--- Auf drei Nachkommastellen runden.
--  ⭐ Alle Clients muessen dieselbe Wertung ausrechnen: Zuschlaege werden mit drei
--  Stellen uebertragen, und Summen in verschiedener Reihenfolge duerfen sich nicht
--  in der letzten Gleitkommastelle unterscheiden (Gleichstand wird exakt verglichen).
function Kern.Runde3(x)
    x = tonumber(x) or 0
    return math.floor(x * 1000 + 0.5) / 1000
end

--- Gesamtwertung eines Spielers (§ 1):
--  Wertung = erhaltene Main-Items + Zuschlaege + dauerhafte Anhebung.
--  @param haupt       Zahl der erhaltenen Main-Items
--  @param zuschlaege  Zahl oder Tabelle/Liste von Zuschlaegen
--  @param anhebung    Zahl (bereits festgeschriebene dauerhafte Anhebung)
--  @return Wertung (Zahl)
function Kern.Wertung(haupt, zuschlaege, anhebung)
    local w = tonumber(haupt) or 0
    if type(zuschlaege) == "table" then
        for _, z in ipairs(zuschlaege) do
            w = w + (tonumber(z) or (type(z) == "table" and tonumber(z.zuschlag)) or 0)
        end
    elseif tonumber(zuschlaege) then
        w = w + tonumber(zuschlaege)
    end
    w = w + (tonumber(anhebung) or 0)
    return Kern.Runde3(w)
end

--- Anhebung berechnen (§ 3):
--  Liegt ein Spieler mehr als 1 Punkt unter dem Niedrigsten der anderen
--  Hauptbedarf-Wuerfler, wird seine Wertung auf dessen Wertung minus 1 hochgesetzt.
--  @param spielerWertung   Basiswertung des Spielers
--  @param andereWertungen  Tabelle der Wertungen der anderen Wuerfler
--  @return effektiveWertung, anhebung (Differenz >= 0)
function Kern.Anhebung(spielerWertung, andereWertungen)
    spielerWertung = tonumber(spielerWertung) or 0
    if type(andereWertungen) ~= "table" then
        return spielerWertung, 0
    end
    local minAndere = nil
    for _, w in pairs(andereWertungen) do
        local n = tonumber(w)
        if n and (not minAndere or n < minAndere) then
            minAndere = n
        end
    end
    if minAndere and (minAndere - spielerWertung) > 1 + 1e-9 then
        local neu = Kern.Runde3(minAndere + Kern.ANHEBUNG_ABSTAND)
        return neu, Kern.Runde3(neu - spielerWertung)
    end
    return spielerWertung, 0
end

--- Gast-Wertung fuer den Abend (§ 4):
--  Fuer den Abend bekommt der Gast dieselbe Wertung wie der Spieler mit der
--  niedrigsten Wertung im Kader.
--  @param niedrigsteKaderWertung  Zahl
--  @return Gast-Wertung (Zahl)
function Kern.GastWertung(niedrigsteKaderWertung)
    return tonumber(niedrigsteKaderWertung) or 0
end

-- =====================================================================
--  Textvorlagen
-- =====================================================================

--- Baut aus einer Blizzard-Textvorlage ein Lua-Suchmuster.
--
--  Aus `"%s receives loot: %s."` wird `"^(.-) receives loot: (.-)%.$"`.
--
--  ⭐ **`%s` wird zu `(.-)`, nicht zu `(%S+)`.** Das ist der Unterschied,
--  an dem Gargul in Forever scheitert: Charakternamen duerfen dort ein
--  Leerzeichen enthalten („Yondaime Kaos"). Ein Muster, das am ersten
--  Leerzeichen abbricht, verliert den Nachnamen.
--
--  ⚠️ Verankert mit ^ und $. Dadurch funktioniert auch das traege `(.-)`
--  am Ende: es muss bis zum Zeilenende reichen.
--
--  @return Muster, Zahl der Fundstellen
function Kern.Muster(vorlage)
    if type(vorlage) ~= "string" then return nil, 0 end

    -- 1. Platzhalter sichern, damit das Escapen sie nicht zerlegt
    local Platzhalter, n = {}, 0
    local roh = vorlage:gsub("%%%d?%$?[sd]", function(p)
        n = n + 1
        Platzhalter[n] = p
        return "\1" .. n .. "\2"
    end)

    -- 2. Alles Magische entschaerfen
    roh = roh:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")

    -- 3. Platzhalter durch Fundstellen ersetzen
    roh = roh:gsub("\1(%d+)\2", function(i)
        local p = Platzhalter[tonumber(i)]
        -- ⚠️ Der Rueckgabewert einer gsub-Funktion wird WOERTLICH eingesetzt;
        -- Lua verarbeitet darin keine %-Escapes. Also einfaches %, nicht %%.
        if p:sub(-1) == "d" then return "(%d+)" end
        return "(.-)"
    end)

    return "^" .. roh .. "$", n
end

--- Wie Kern.Muster, sagt aber zusaetzlich, welches ARGUMENT der Vorlage jede
--  Fundstelle ist.
--
--  ⚠️ Uebersetzte Vorlagen duerfen die Reihenfolge umstellen
--  (`%2$s ... %1$d`). Ohne diese Zuordnung landete der Gegenstand im
--  Namensfeld. Die Wuerfelmeldungen von Blizzards Fenster
--  (`Need Roll - %d for %s by %s`) brauchen das.
--
--  @return Muster, { Argumentnummer je Fundstelle }
function Kern.MusterGeordnet(vorlage)
    local muster = Kern.Muster(vorlage)
    if not muster then return nil end

    local nummern, lauf = {}, 0
    vorlage:gsub("%%(%d?)%$?[sd]", function(num)
        lauf = lauf + 1
        nummern[lauf] = (num ~= "" and tonumber(num)) or lauf
    end)
    return muster, nummern
end

--- Wertet eine Meldung mit einer Vorlage aus Kern.MusterGeordnet aus.
--  @return { [Argumentnummer] = Text } oder nil, wenn sie nicht passt
function Kern.Argumente(text, muster, nummern)
    if type(text) ~= "string" or not muster then return nil end
    local T = { text:match(muster) }
    if #T == 0 then return nil end
    local A = {}
    for i, wert in ipairs(T) do A[nummern[i] or i] = wert end
    return A
end

-- ⭐ Die Bereiche, die als Haupt- und als Zweitbedarf gelten (einstellbar,
-- Standard 1-100 und 1-50). Erfassung.lua haelt sie in den gespeicherten Daten
-- und setzt sie hier; Wurf.lua uebernimmt waehrend eines Wurfs die des Leiters.
Kern.BEREICHE = { haupt = { 1, 100 }, zweit = { 1, 50 } }

--- Setzt beide Bereiche, wenn sie stimmig sind.
--  @return true, oder false und ein Code: "zahl" | "grenzen" | "gleich"
function Kern.BereicheSetzen(h1, h2, z1, z2)
    local function ganz(x)
        x = tonumber(x)
        if x and x == math.floor(x) then return x end
        return nil
    end
    h1, h2, z1, z2 = ganz(h1), ganz(h2), ganz(z1), ganz(z2)
    if not (h1 and h2 and z1 and z2) then return false, "zahl" end
    for _, p in ipairs({ { h1, h2 }, { z1, z2 } }) do
        if p[1] < 1 or p[2] <= p[1] or p[2] > 10000 then return false, "grenzen" end
    end
    -- Gleicher Bereich fuer beide: Die Art liesse sich nicht mehr erkennen.
    if h1 == z1 and h2 == z2 then return false, "gleich" end

    Kern.BEREICHE.haupt[1], Kern.BEREICHE.haupt[2] = h1, h2
    Kern.BEREICHE.zweit[1], Kern.BEREICHE.zweit[2] = z1, z2
    return true
end

--- Der Wurfbereich sagt, wofuer gewuerfelt wurde.
--  Die Gilde wuerfelt `/rnd 100` fuer Hauptbedarf und `/rnd 50` fuer
--  Zweitbedarf. ⚠️ Alles andere ist kein Bedarfswurf und zaehlt nicht —
--  lieber nichts erfassen als etwas Falsches.
--  @return "haupt", "zweit" oder nil
function Kern.Bedarfsart(min, max)
    min, max = tonumber(min), tonumber(max)
    if not min or not max then return nil end
    local h, z = Kern.BEREICHE.haupt, Kern.BEREICHE.zweit
    if min == h[1] and max == h[2] then return "haupt" end
    if min == z[1] and max == z[2] then return "zweit" end
    return nil
end

--- Zeitstempel, ab dem gezaehlt wird.
--  @param wochen  nil oder 0 = alles
function Kern.Seit(jetzt, wochen)
    if not wochen or wochen <= 0 then return 0 end
    return jetzt - wochen * Kern.WOCHE
end

-- =====================================================================
--  Spieler vergleichen
-- =====================================================================

--- Sind das derselbe Spieler?
--
--  ⚠️ Forever kennt Nachnamen („Yondaime Kaos"). Manche Quellen nennen sie,
--  andere nur den Vornamen. Fehlt auf EINER Seite der Nachname, genuegt der
--  gleiche Vorname. Haben beide einen, muessen sie ganz uebereinstimmen —
--  sonst waeren „Yondaime Kaos" und „Yondaime Nuhkomm" derselbe.
--  Der Preis: Fehlt der Nachname, treffen zwei Gleichvornamige aufeinander.
function Kern.GleicherSpieler(a, b)
    local ka, kb = Kern.Schluessel(a), Kern.Schluessel(b)
    if not ka or not kb then return false end
    if ka == kb then return true end

    local la, lb = ka:find(" ", 1, true), kb:find(" ", 1, true)
    if (la and lb) or (not la and not lb) then return false end
    return ka:match("^(%S+)") == kb:match("^(%S+)")
end

-- =====================================================================
--  Kennungen und Pruefsummen
-- =====================================================================

local MODUL = 4294967296   -- 2^32

--- Einfacher Textwert, 32 Bit. Kein Schutz, nur zum Vergleichen.
function Kern.Hash(text)
    local h = 5381
    text = tostring(text)
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % MODUL
    end
    return h
end

--- Pruefsumme einer Historie.
--
--  ⭐ Reihenfolgeunabhaengig (Summe), damit zwei Spieler mit denselben
--  Eintraegen dieselbe Zahl bekommen, egal wie ihre Tabelle gewachsen ist.
--
--  ⚠️ `alias` sind Kennungen, die als Doppelgaenger verworfen wurden. Sie
--  zaehlen MIT: Hat A „X" und kennt „Y" als Alias, B umgekehrt, kommt bei
--  beiden dieselbe Summe heraus. Ohne das waeren sie fuer immer
--  „verschieden", und der Abgleich liefe endlos.
--
--  @return Anzahl der Eintraege, Summe
function Kern.Pruefsumme(historie, alias)
    local n, summe = 0, 0
    for id, e in pairs(historie or {}) do
        n = n + 1
        -- ⭐ Der Zustand „zurueckgenommen" gehoert in die Summe: Sonst saehe fuer
        -- jemanden, der bei der Ruecknahme nicht dabei war, alles „gleich" aus
        -- und er erfuehre es nie.
        summe = (summe + Kern.Hash(e.zurueck and (id .. "!") or id)) % MODUL
    end
    for id in pairs(alias or {}) do
        summe = (summe + Kern.Hash(id)) % MODUL
    end
    return n, summe
end

--- Pruefsumme je Tag (Tagesschluessel kommt von `tagOf`).
--  ⚠️ Der Aufrufer nimmt UTC, nicht die Ortszeit: Wer in einer anderen
--  Zeitzone spielt, haette sonst andere Tage und damit nie dieselbe Summe.
--  @return Tabelle Tag -> { n, summe }
function Kern.Tagesstand(historie, alias, tagOf)
    local tage = {}

    for id, e in pairs(historie or {}) do
        local t = tagOf(e.timestamp or 0)
        local d = tage[t] or { n = 0, summe = 0 }
        d.n = d.n + 1
        d.summe = (d.summe + Kern.Hash(e.zurueck and (id .. "!") or id)) % MODUL
        tage[t] = d
    end
    for id, ziel in pairs(alias or {}) do
        local e = (historie or {})[ziel]
        if e then
            local d = tage[tagOf(e.timestamp or 0)]
            if d then d.summe = (d.summe + Kern.Hash(id)) % MODUL end
        end
    end
    return tage
end

--- Welche Tage unterscheiden sich?  Beide Richtungen: ein Tag, den nur
--  eine Seite kennt, zaehlt auch.
--  @return sortierte Liste von Tagesschluesseln
function Kern.AbweichendeTage(lokal, fremd)
    local aus, liste = {}, {}
    local function pruefe(t)
        if aus[t] then return end
        local a, b = lokal[t], fremd[t]
        if not a or not b or a.n ~= b.n or a.summe ~= b.summe then
            aus[t] = true
            liste[#liste + 1] = t
        end
    end
    for t in pairs(lokal) do pruefe(t) end
    for t in pairs(fremd) do pruefe(t) end
    table.sort(liste)
    return liste
end

--- Tagesstand als Text:  "20261013:3:12345,20261014:1:99"
function Kern.TageKodieren(tage)
    local schluessel = {}
    for t in pairs(tage) do schluessel[#schluessel + 1] = t end
    table.sort(schluessel)
    local teile = {}
    for _, t in ipairs(schluessel) do
        -- ⚠️ `%.0f`, nie `%d`: Summen reichen bis 2^32. `%d` schneidet in
        -- manchen Lua-Fassungen bei 2^31 ab (-2147483648), und die Gegenseite
        -- wuerde den Tag mit dem Minuszeichen verwerfen.
        teile[#teile + 1] = string.format("%s:%d:%.0f", t, tage[t].n, tage[t].summe)
    end
    return table.concat(teile, ",")
end

function Kern.TageDekodieren(text)
    local tage = {}
    if type(text) ~= "string" then return tage end
    for t, n, summe in text:gmatch("([^,:]+):(%d+):(%d+)") do
        tage[t] = { n = tonumber(n), summe = tonumber(summe) }
    end
    return tage
end

-- =====================================================================
--  Zusammenfuehren
-- =====================================================================

--- ⭐ Fuehrt eingehende Eintraege in eine Historie ein — ohne je etwas zu
--  ueberschreiben oder zu loeschen.
--
--  Drei Wege fuer einen eingehenden Eintrag:
--    * Kennung schon bekannt (als Eintrag oder Alias)   -> vorhanden
--    * gleicher Spieler und Gegenstand nahe beieinander -> Doppelgaenger;
--      die Kennung wandert in `alias`, damit die Pruefsummen uebereinstimmen
--    * sonst                                            -> neu
--
--  ⚠️ Der Doppelgaenger-Weg ist eine Annaeherung: Gewinnt jemand denselben
--  Gegenstand zweimal binnen `fenster` Sekunden, geht der zweite verloren.
--  Das ist selten; systematisches Doppelzaehlen waere schlimmer.
--
--  Eine Ausnahme von „nichts aendern": Meldet der Eingehende einen Eintrag
--  als **zurueckgenommen**, wird das uebernommen. Das Merkmal kann nur von
--  „nein" auf „ja" wechseln und nie zurueck — so ist es ein Zusammenfuehren
--  und kein Ueberschreiben, und alle Seiten kommen zum selben Ergebnis.
--
--  @param eingehend  Liste aus { id =, e = }
--  @return neu, doppelt, vorhanden, abgelehnt, zurueckgenommen
function Kern.Zusammenfuehren(historie, alias, eingehend, fenster)
    fenster = fenster or 180
    local neu, doppelt, vorhanden, abgelehnt, zurueckgenommen = 0, 0, 0, 0, 0

    -- Index Spieler:Gegenstand -> { { id, zeit }, ... }
    local Index = {}
    local function schluessel(e)
        return (Kern.Schluessel(e.awardedTo) or "?") .. ":" .. tostring(e.itemID)
    end
    local function merke(id, e)
        local k = schluessel(e)
        Index[k] = Index[k] or {}
        Index[k][#Index[k] + 1] = { id = id, zeit = e.timestamp }
    end
    for id, e in pairs(historie) do
        if e.awardedTo and e.itemID then merke(id, e) end
    end

    for _, X in ipairs(eingehend or {}) do
        local id, e = X.id, X.e
        if type(id) ~= "string" or type(e) ~= "table"
           or not e.awardedTo or e.awardedTo == ""
           or not tonumber(e.itemID) or not tonumber(e.timestamp) then
            abgelehnt = abgelehnt + 1
        elseif historie[id] or alias[id] then
            vorhanden = vorhanden + 1
            local ziel = historie[id] or historie[alias[id]]
            if e.zurueck and ziel and not ziel.zurueck then
                ziel.zurueck = true
                zurueckgenommen = zurueckgenommen + 1
            end
        else
            local treffer
            for _, B in ipairs(Index[schluessel(e)] or {}) do
                if math.abs((B.zeit or 0) - e.timestamp) <= fenster then
                    treffer = B.id
                    break
                end
            end

            if treffer then
                alias[id] = treffer
                doppelt = doppelt + 1
            else
                historie[id] = e
                merke(id, e)
                neu = neu + 1
            end
        end
    end

    return neu, doppelt, vorhanden, abgelehnt, zurueckgenommen
end

-- =====================================================================
--  Uebertragung
-- =====================================================================

-- Zeichen, die in Feldern nicht roh vorkommen duerfen: Feldtrenner `;`,
-- Listentrenner `,` und `:`, Paketttrenner `~`, der Escape `%` selbst,
-- `|` (Blizzards Escape im Chat) und Steuerzeichen.
local function schuetze(s)
    return (tostring(s or ""):gsub("[%%;,:~|%c]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function entschuetze(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

--- Ein Eintrag als Zeile.
--  Felder: Kennung ; Name ; Gegenstand ; Zeit ; Art ; Gruppe ; Wurf ; Zurueck
--  ⚠️ Der Verweis (itemLink) wird NICHT mitgeschickt: Er ist lang und
--  enthaelt `|`. Der Empfaenger holt ihn ueber die Gegenstandsnummer.
function Kern.Kodieren(id, e)
    return table.concat({
        schuetze(id),
        schuetze(e.awardedTo),
        tostring(tonumber(e.itemID) or 0),
        tostring(tonumber(e.timestamp) or 0),
        e.OS and "Z" or "H",
        schuetze(e.gruppe),
        e.wurf and tostring(tonumber(e.wurf) or "") or "",
        e.zurueck and "1" or "",
        -- Kennzeichen (Regelwerk § 5/§ 6): "A" = abweichend vom Ergebnis, "S" = OS nach Absprache
        (e.kennzeichen == "A" or e.kennzeichen == "S") and e.kennzeichen or "",
    }, ";")
end

--- Zeile -> id, Eintrag; oder nil und ein Grund.
--  ⚠️ Alles, was von aussen kommt, wird geprueft: Namenslaenge, Zahlen,
--  ein vernuenftiger Zeitraum. Eine kaputte oder boesartige Zeile darf
--  hoechstens abgelehnt werden, nie die Historie verfaelschen.
function Kern.Dekodieren(zeile, jetzt)
    if type(zeile) ~= "string" then return nil, "kein Text" end
    local id, name, item, zeit, art, gruppe, wurf, zurueck, kennzeichen =
        zeile:match("^([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*)$")
    if not id then
        -- Aeltere Fassung ohne Kennzeichen: acht Felder
        id, name, item, zeit, art, gruppe, wurf, zurueck =
            zeile:match("^([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*)$")
        kennzeichen = ""
    end
    if not id then return nil, "Aufbau" end

    id, name, gruppe = entschuetze(id), entschuetze(name), entschuetze(gruppe)
    item, zeit = tonumber(item), tonumber(zeit)

    if id == "" or #id > 80 then return nil, "Kennung" end
    if name == "" or #name > 60 then return nil, "Name" end
    if not item or item <= 0 or item > 10000000 then return nil, "Gegenstand" end
    if not zeit or zeit < 1000000000 then return nil, "Zeit" end
    if jetzt and zeit > jetzt + 2 * Kern.TAG then return nil, "Zeit in der Zukunft" end
    if art ~= "H" and art ~= "Z" then return nil, "Art" end
    if #gruppe > 40 then return nil, "Gruppe" end

    return id, {
        awardedTo = name,
        itemID    = item,
        timestamp = zeit,
        OS        = (art == "Z") or nil,
        gruppe    = gruppe ~= "" and gruppe or nil,
        wurf      = tonumber(wurf),
        zurueck   = (zurueck == "1") or nil,
        kennzeichen = (kennzeichen == "A" or kennzeichen == "S") and kennzeichen or nil,
        empfangen = true,
    }
end

--- Packt Zeilen in Nachrichten bis `grenze` Zeichen.
--  Trenner ist `~` (innerhalb der Zeilen immer geschuetzt).
--  ⚠️ Eine einzelne Zeile, die allein schon zu lang ist, bekommt eine
--  eigene Nachricht und wird vom Sender abgelehnt — nicht gekappt: eine
--  abgeschnittene Zeile waere ein falscher Eintrag.
function Kern.Pakete(zeilen, grenze)
    local pakete, aktuell = {}, nil
    for _, z in ipairs(zeilen) do
        if aktuell and (#aktuell + 1 + #z) <= grenze then
            aktuell = aktuell .. "~" .. z
        else
            if aktuell then pakete[#pakete + 1] = aktuell end
            aktuell = z
        end
    end
    if aktuell then pakete[#pakete + 1] = aktuell end
    return pakete
end

--- Gegenstueck zu Pakete.
function Kern.Entpacken(paket)
    local zeilen = {}
    if type(paket) ~= "string" or paket == "" then return zeilen end
    for z in (paket .. "~"):gmatch("(.-)~") do
        if z ~= "" then zeilen[#zeilen + 1] = z end
    end
    return zeilen
end

-- =====================================================================
--  Datenbuch: Abschluesse und Anhebungen verteilen (Regelwerk 16.10.2026)
-- =====================================================================
--
--  Zuschlaege (aus dem Abendabschluss) und Anhebungen gehoeren zur Wertung.
--  Damit jeder Client dieselbe Wertung ausrechnet — auch wenn naechste Woche ein
--  anderer den Raid leitet —, werden sie wie die Vergaben verteilt, aber als
--  eigene Saetze:
--
--    a  Kopf eines Abschlusses  + je Spieler eine Zeile s.
--       `rev` zaehlt bei jedem Abschliessen und Wiedereroeffnen hoch; der hoehere
--       Stand gewinnt (monoton, damit alle Seiten zum selben Ergebnis kommen).
--    h  eine Anhebung (unveraenderlich, Kennung einmalig)
--
--  Listenform eines Satzes (zum Vergleichen): "a:<Abend>@<rev>" bzw. "h:<Kennung>".

Kern.BUCH_STATUS = { imRaid = true, bank = true, abgemeldet = true, unentschuldigt = true,
                     vergessen = true, vergessenStrafe = true }

local function buchZahl(s, lo, hi)
    local n = tonumber(s)
    if not n or n ~= n or n < lo or n > hi then return nil end
    return n
end

local function buchKennung(s)
    return type(s) == "string" and #s >= 1 and #s <= 60 and s:match("^[%w_%-%.]+$") ~= nil
end

local function f3(x) return string.format("%.3f", tonumber(x) or 0) end
local function f0(x) return string.format("%.0f", tonumber(x) or 0) end

--- Revision eines Abends: wie oft er abgeschlossen oder wiedereroeffnet wurde.
--  Abende aus aelteren Staenden ohne Zaehler gelten als abgeschlossen (1).
function Kern.BuchRev(ab)
    if type(ab) ~= "table" then return 0 end
    local r = tonumber(ab.buchRev)
    if r and r > 0 then return math.floor(r) end
    return (ab.abgeschlossen and ab.abschluss) and 1 or 0
end

--- Der Stand eines Abends als Zeilen (Kopf, dann je Spieler), oder {}.
function Kern.BuchAbendKodieren(id, ab)
    local rev = Kern.BuchRev(ab)
    if rev <= 0 or not buchKennung(id) then return {} end

    local a = ab.abschluss
    local geschlossen = (ab.abgeschlossen and a) and true or false
    local spieler = {}
    if geschlossen then
        for _, p in pairs(a.spieler or {}) do
            if Kern.BUCH_STATUS[p.status] and p.name and p.name ~= "" then spieler[#spieler + 1] = p end
        end
        table.sort(spieler, function(x, y) return x.name < y.name end)
    end

    local zeilen = {
        table.concat({
            "a", id, f0(rev), geschlossen and "1" or "0",
            schuetze(a and a.datum or ab.datum or ""), f0(a and a.zeit or 0), schuetze(a and a.autor or ""),
            f3(a and a.schnitt), f0(a and a.mainItems), f0(a and a.raidSpieler), f0(a and a.gesamtBosse),
            f0(#spieler),
        }, ";"),
    }
    for _, p in ipairs(spieler) do
        zeilen[#zeilen + 1] = table.concat({
            "s", id, f0(rev), schuetze(p.name), p.status,
            f3(p.faktor), f3(p.zuschlag), f0(p.fehlAnzahl), f0(p.bosse),
        }, ";")
    end
    return zeilen
end

--- Eine Anhebung als Zeile.
function Kern.BuchAnhebungKodieren(id, h)
    if not buchKennung(id) or type(h) ~= "table" then return nil end
    return table.concat({
        "h", id, schuetze(h.name), f3(h.wert), f0(h.zeit), schuetze(h.datum or ""),
        schuetze(h.autor or ""), schuetze(h.grund or ""),
    }, ";")
end

--- Zeile -> Satz (Tabelle mit `typ`), oder nil und ein Grund.
--  ⚠️ Alles von aussen wird geprueft und begrenzt; eine kaputte Zeile darf
--  hoechstens abgelehnt werden, nie die Wertung verfaelschen.
function Kern.BuchDekodieren(zeile, jetzt)
    if type(zeile) ~= "string" or #zeile > 250 then return nil, "kein Text" end
    local f = {}
    for teil in (zeile .. ";"):gmatch("([^;]*);") do f[#f + 1] = teil end
    local typ = f[1]

    local function nameOk(n) return n and n ~= "" and #n <= 60 end

    if typ == "a" and #f == 12 then
        local id, rev = f[2], buchZahl(f[3], 1, 100000)
        local zeit = buchZahl(f[6], 0, 4000000000)
        if not buchKennung(id) or not rev or (f[4] ~= "0" and f[4] ~= "1") then return nil, "Kopf" end
        if not zeit or (jetzt and zeit > jetzt + 2 * Kern.TAG) then return nil, "Zeit" end
        local datum = entschuetze(f[5])
        if #datum > 20 then return nil, "Datum" end
        local autor = entschuetze(f[7])
        if #autor > 60 then return nil, "Autor" end
        local schnitt, items, raid, bosse, n =
            buchZahl(f[8], 0, 10), buchZahl(f[9], 0, 1000), buchZahl(f[10], 0, 100),
            buchZahl(f[11], 0, 100), buchZahl(f[12], 0, 120)
        if not (schnitt and items and raid and bosse and n) then return nil, "Zahlen" end
        if f[4] == "0" and n ~= 0 then return nil, "Anzahl" end
        return { typ = "a", id = id, rev = math.floor(rev), zu = (f[4] == "1"), datum = datum, zeit = zeit,
                 autor = autor, schnitt = schnitt, items = items, raid = raid, bosse = bosse, n = n }

    elseif typ == "s" and #f == 9 then
        local id, rev = f[2], buchZahl(f[3], 1, 100000)
        local name = entschuetze(f[4])
        local faktor, zuschlag, fehl, bosse =
            buchZahl(f[6], 0, 3), buchZahl(f[7], 0, 30), buchZahl(f[8], 0, 1000), buchZahl(f[9], 0, 100)
        if not buchKennung(id) or not rev or not nameOk(name) then return nil, "Spieler" end
        if not Kern.BUCH_STATUS[f[5]] then return nil, "Status" end
        if not (faktor and zuschlag and fehl and bosse) then return nil, "Zahlen" end
        return { typ = "s", id = id, rev = math.floor(rev), name = name, status = f[5],
                 faktor = faktor, zuschlag = zuschlag, fehl = fehl, bosse = bosse }

    elseif typ == "h" and #f == 8 then
        local id = f[2]
        local name = entschuetze(f[3])
        -- „hm_…" vermerkt nur, dass die Anhebung eines Tages ausgewertet wurde (Wert 0)
        local wert, zeit = buchZahl(f[4], id:match("^hm_") and 0 or 0.001, 100), buchZahl(f[5], 1000000000, 4000000000)
        if not buchKennung(id) or not nameOk(name) or not wert or not zeit then return nil, "Anhebung" end
        if jetzt and zeit > jetzt + 2 * Kern.TAG then return nil, "Zeit" end
        local datum, autor, grund = entschuetze(f[6]), entschuetze(f[7]), entschuetze(f[8])
        if #datum > 20 or #autor > 60 or #grund > 160 then return nil, "Text" end
        return { typ = "h", id = id, name = name, wert = wert, zeit = zeit, datum = datum, autor = autor, grund = grund }
    end

    return nil, "Aufbau"
end

--- Sammelt Zeilen, bis ein Abschluss vollstaendig ist (Kopf plus alle Spieler).
--  Eine Anhebung ist sofort fertig.
--  @param ausstehend  Tabelle des Aufrufers (Zustand zwischen den Aufrufen)
--  @return Liste fertiger Saetze (hoechstens einer)
function Kern.BuchSammeln(ausstehend, satz, jetzt)
    local fertig = {}
    if type(satz) ~= "table" then return fertig end
    if satz.typ == "h" then fertig[1] = satz return fertig end

    jetzt = jetzt or 0
    for schluessel, p in pairs(ausstehend) do
        if jetzt - p.zeit > 900 then ausstehend[schluessel] = nil end
    end

    local schluessel = satz.id .. "@" .. satz.rev
    local p = ausstehend[schluessel]
    if not p then
        p = { zeit = jetzt, spieler = {}, anzahl = 0 }
        ausstehend[schluessel] = p
    end

    if satz.typ == "a" then
        p.kopf = satz
    else
        local k = Kern.Schluessel(satz.name)
        if k and not p.spieler[k] and p.anzahl < 120 then
            p.spieler[k] = satz
            p.anzahl = p.anzahl + 1
        end
    end

    if p.kopf and p.anzahl >= p.kopf.n then
        ausstehend[schluessel] = nil
        local fertigerSatz = p.kopf
        fertigerSatz.spieler = p.spieler
        fertig[1] = fertigerSatz
    end
    return fertig
end

--- Fuehrt einen vollstaendigen Satz in die Daten ein.
--  @param d  Tabelle mit `abende`, `zuschlaege`, `anhebungsliste` (und `aktiverAbend`)
--  @return "neu", "vorhanden" oder "abgelehnt"
function Kern.BuchEinfuehren(d, satz)
    if type(d) ~= "table" or type(satz) ~= "table" then return "abgelehnt" end
    d.abende = d.abende or {}
    d.zuschlaege = d.zuschlaege or {}
    d.anhebungsliste = d.anhebungsliste or {}

    if satz.typ == "h" then
        if d.anhebungsliste[satz.id] then return "vorhanden" end
        d.anhebungsliste[satz.id] = {
            id = satz.id, schluessel = Kern.Schluessel(satz.name), name = satz.name,
            wert = satz.wert, zeit = satz.zeit, datum = satz.datum, autor = satz.autor,
            grund = satz.grund, empfangen = true,
        }
        return "neu"
    end

    if satz.typ ~= "a" then return "abgelehnt" end

    local ab = d.abende[satz.id]
    if not ab and d.aktiverAbend and d.aktiverAbend.id == satz.id then ab = d.aktiverAbend end
    if Kern.BuchRev(ab) >= satz.rev then return "vorhanden" end

    if not ab then
        ab = {
            id = satz.id, datum = satz.datum, start = satz.zeit, bosse = satz.bosse,
            gesehen = {}, bossListe = {}, anwesenheit = {}, teilnehmer = {},
            bank = {}, unentschuldigt = {}, protokoll = {}, empfangen = true,
        }
    end

    -- Die Zuschlaege dieses Abends neu aufbauen
    for zId, z in pairs(d.zuschlaege) do
        if z.abendId == satz.id then d.zuschlaege[zId] = nil end
    end

    ab.buchRev = satz.rev
    if satz.zu then
        ab.abgeschlossen = true
        ab.ende = satz.zeit
        ab.abschluss = {
            zeit = satz.zeit, datum = satz.datum, autor = satz.autor, schnitt = satz.schnitt,
            mainItems = satz.items, raidSpieler = satz.raid, gesamtBosse = satz.bosse, spieler = {},
        }
        for k, p in pairs(satz.spieler or {}) do
            ab.abschluss.spieler[k] = {
                name = Kern.Anzeigename(p.name), status = p.status, faktor = p.faktor,
                schnitt = satz.schnitt, zuschlag = p.zuschlag, fehlAnzahl = p.fehl,
                bosse = p.bosse, gesamt = satz.bosse, zeit = satz.zeit, von = satz.autor,
            }
            if p.zuschlag > 0 then
                local zId = string.format("z_%s_%s", satz.id, k)
                d.zuschlaege[zId] = {
                    id = zId, abendId = satz.id, datum = satz.datum, zeit = satz.zeit,
                    spieler = Kern.Anzeigename(p.name), schluessel = k, status = p.status,
                    faktor = p.faktor, schnitt = satz.schnitt, zuschlag = p.zuschlag,
                    fehlAnzahl = p.fehl, autor = satz.autor,
                }
            end
        end
        if d.aktiverAbend == ab then d.aktiverAbend = nil end
    else
        ab.abgeschlossen = nil
        ab.abschluss = nil
    end
    d.abende[satz.id] = ab
    return "neu"
end

--- Alle Saetze der eigenen Daten als sortierte Liste ("a:Abend@rev", "h:Kennung").
function Kern.BuchListe(d)
    local liste = {}
    for id, ab in pairs((d and d.abende) or {}) do
        local rev = Kern.BuchRev(ab)
        if rev > 0 and buchKennung(id) then liste[#liste + 1] = "a:" .. id .. "@" .. rev end
    end
    for id in pairs((d and d.anhebungsliste) or {}) do
        if buchKennung(id) then liste[#liste + 1] = "h:" .. id end
    end
    table.sort(liste)
    return liste
end

--- Anzahl und Pruefsumme der Saetze (reihenfolgeunabhaengig).
function Kern.BuchStand(d)
    local liste = Kern.BuchListe(d)
    local summe = 0
    for _, t in ipairs(liste) do summe = (summe + Kern.Hash(t)) % MODUL end
    return #liste, summe
end

--- Listenform -> Tabelle Kennung -> rev (Abende) bzw. true (Anhebungen).
local function buchKarte(liste)
    local abende, anhebungen = {}, {}
    for _, t in ipairs(liste or {}) do
        local a, rev = t:match("^a:([^@]+)@(%d+)$")
        if a then abende[a] = tonumber(rev)
        else
            local h = t:match("^h:(.+)$")
            if h then anhebungen[h] = true end
        end
    end
    return abende, anhebungen
end

--- Vergleicht meine Liste mit einer fremden.
--  @return fehlt (was ich von dort brauche), habe (was ich dorthin schicken kann)
function Kern.BuchVergleichen(meine, fremde)
    local ma, mh = buchKarte(meine)
    local fa, fh = buchKarte(fremde)
    local fehlt, habe = {}, {}
    for id, rev in pairs(fa) do
        if (ma[id] or 0) < rev then fehlt[#fehlt + 1] = "a:" .. id .. "@" .. rev end
    end
    for id in pairs(fh) do
        if not mh[id] then fehlt[#fehlt + 1] = "h:" .. id end
    end
    for id, rev in pairs(ma) do
        if (fa[id] or 0) < rev then habe[#habe + 1] = "a:" .. id .. "@" .. rev end
    end
    for id in pairs(mh) do
        if not fh[id] then habe[#habe + 1] = "h:" .. id end
    end
    table.sort(fehlt)
    table.sort(habe)
    return fehlt, habe
end

--- Die Zeilen zu den genannten Saetzen (aktueller eigener Stand).
function Kern.BuchZeilen(d, liste)
    local zeilen = {}
    for _, t in ipairs(liste or {}) do
        local a = t:match("^a:([^@]+)@%d+$")
        if a then
            local ab = d and d.abende and d.abende[a]
            if ab then
                for _, z in ipairs(Kern.BuchAbendKodieren(a, ab)) do zeilen[#zeilen + 1] = z end
            end
        else
            local h = t:match("^h:(.+)$")
            local x = h and d and d.anhebungsliste and d.anhebungsliste[h]
            local z = x and Kern.BuchAnhebungKodieren(h, x)
            if z then zeilen[#zeilen + 1] = z end
        end
    end
    return zeilen
end

-- =====================================================================
--  Wer zeichnet auf?
-- =====================================================================

--- ⭐ Wer in der Gruppe fuehrt die Historie?
--
--  Nur EINER soll mitschreiben. Sonst entstuende fuer jeden Drop ein
--  Eintrag je Teilnehmer, und der Abgleich muesste sie wieder
--  zusammenfuehren. Entscheid des Gildenleiters (14.10.2026): der
--  Pluendermeister, und gibt es keinen, der Schlachtzugsleiter.
--
--  ⚠️ Die Wahl haengt daran, WER das Addon hat. Hat der Pluendermeister es
--  nicht, springt die Reihenfolge weiter (Leiter, dann Assistenten) —
--  sonst ginge der ganze Abend verloren.
--
--  @param kandidaten  geordnet: { { name =, ich = true/false }, ... }
--  @param hat         Menge der Schluessel von Mitspielern MIT Addon
--  @return der gewaehlte Kandidat, oder nil
function Kern.Schreiber(kandidaten, hat)
    hat = hat or {}
    for _, k in ipairs(kandidaten or {}) do
        if k.ich then return k end
        local s = Kern.Schluessel(k.name)
        if s and hat[s] then return k end
    end
    return nil
end

-- =====================================================================
--  Ansichten
-- =====================================================================

--- Nur die Eintraege einer Gruppe. nil = alle (dieselbe Tabelle).
function Kern.NachGruppe(historie, gruppe)
    if not gruppe then return historie end
    local aus = {}
    for id, e in pairs(historie or {}) do
        if e.gruppe == gruppe then aus[id] = e end
    end
    return aus
end

--- Der Verlauf: wer bekam was, wann. Neueste zuerst.
--  @return Liste aus { id, zeit, name, zweit, eintrag }
function Kern.Verlauf(historie, seit, gruppe)
    local liste = {}
    seit = seit or 0
    for id, e in pairs(Kern.NachGruppe(historie, gruppe) or {}) do
        if Kern.Zaehlt(e) and e.timestamp >= seit then
            liste[#liste + 1] = {
                id      = id,
                zeit    = e.timestamp,
                name    = Kern.Anzeigename(e.awardedTo),
                zweit   = e.OS and true or false,
                eintrag = e,
            }
        end
    end
    table.sort(liste, function(a, b)
        if a.zeit ~= b.zeit then return a.zeit > b.zeit end
        return a.name < b.name
    end)
    return liste
end

return ns
