--[[----------------------------------------------------------------------
    Befehle.lua  —  /fs

    ⭐ **Kein Befehl darf still scheitern.** WoW verschluckt Laufzeitfehler
    in Addons, solange scriptErrors aus ist — und das ist die
    Voreinstellung. Der Befehl tut dann scheinbar ueberhaupt nichts, und
    man sucht an der falschen Stelle. Darum laeuft jeder Unterbefehl
    ueber pcall und die Meldung landet im Chat.

    Alle Ausgaben laufen ueber L[] (Locale.lua): deutscher Client Deutsch,
    jeder andere Englisch. Die Befehlsworte selbst bleiben deutsch UND
    englisch gueltig, damit man nichts umlernen muss.
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Kern, Quelle, Fenster = ns.Kern, ns.Quelle, ns.Fenster

local PRAEFIX = "|cff1B6B57Fairshare|r: "
local GELB = "|cffffff78"
local GRAU = "|cff8E9A94"
local ROT  = "|cffff5555"
local GRUEN = "|cff55ff55"

local function sag(text) print(PRAEFIX .. text) end

local befehle = {}

local function hilfe()
    sag(L["Befehle:"])
    print(L["  |cffffff78/fs|r              – Fenster öffnen und schließen"])
    print(L["  |cffffff78/fs verlauf|r      – wer bekam was, wann"])
    print(L["  |cffffff78/fs einstellungen|r – das Einstellungsfenster"])
    print(L["  |cffffff78/fs demo|r         – Fenster mit Beispieldaten (nichts wird gespeichert)"])
    print(L["  |cffffff78/fs liste|r        – dieselbe Auswertung im Chat, |cffffff78liste 4|r für 4 Wochen"])
    print(L["  |cffffff78/fs <Name>|r       – Einzelvergaben eines Spielers im Chat"])
    print(L["  |cffffff78/fs abgleich|r     – Historien der Gruppe zusammenführen (|cffffff78abgleich status|r zeigt den Stand)"])
    print(L["  |cffffff78/fs rolle|r        – wer zeichnet gerade auf, und warum"])
    print(L["  |cffffff78/fs rueckgaengig|r – die letzte Vergabe zurücknehmen (mit Rückfrage; einzelne Vergaben im Verlauf)"])
    print(L["  |cffffff78/fs wurf|r         – eigenes Würfelfenster starten (|cffffff78wurf <Link>|r, |cffffff78wurf ende|r, |cffffff78wurf ergebnis|r, |cffffff78wurf offen|r, |cffffff78wurf status|r)"])
    print(L["  |cffffff78/fs beutetest|r    – Diagnose: Beutefenster und Zuteilung durch den Plündermeister"])
    print(L["  |cffffff78/fs gruppe|r       – Kader und Raidgruppen (|cffffff78gruppe hilfe|r)"])
    print(L["  |cffffff78/fs bereiche|r     – Garguls Würfelbereiche prüfen (|cffffff78bereiche setzen|r)"])
    print(L["  |cffffff78/fs auto|r         – Fenster bei Wurfbeginn automatisch öffnen (an/aus)"])
    print(L["  |cffffff78/fs import|r       – Garguls bisherige Aufzeichnungen übernehmen"])
    print(L["  |cffffff78/fs reset|r        – Historie auf diesem Rechner leeren (mit Rückfrage und Sicherung)"])
    print(L["  |cffffff78/fs filter|r       – ab welcher Qualität und wo aufgezeichnet wird"])
    print(L["  |cffffff78/fs gilde|r        – Diagnose: was die Gildenliste liefert (Namen, Ränge)"])
    print(L["  |cffffff78/fs stand|r        – Diagnose: eigene Historie und Aufzeichnung"])
    print(L["  |cffffff78/fs muster|r       – Diagnose: Textvorlagen für eigene Erkennung"])
    print(L["  |cffffff78/fs darstellung|r  – Diagnose: Einstellungsfenster zeichnet nicht richtig"])
    print(L["  |cffffff78/fs test|r         – Selbsttests der Auswertung"])
end

-- =====================================================================

befehle["import"] = function()
    local neu, doppelt = Quelle.GargulImport()
    if not neu then
        sag(ROT .. tostring(doppelt) .. "|r")
        return
    end
    sag(string.format(L["|cff55ff55%d Vergaben|r aus Gargul übernommen."], neu))
    if doppelt > 0 then
        print(string.format(L["  |cff8E9A94%d übersprungen – die hatte die Eigenerfassung schon.|r"], doppelt))
    end
    print(L["  |cff8E9A94Wiederholtes Einführen ändert nichts mehr.|r"])
end

--- ⭐ Historie leeren: erst fragen, dann tun, vorher sichern.
local resetBereit = nil

befehle["reset"] = function(arg)
    arg = (arg or ""):lower()

    if arg == "undo" or arg == "zurueck" or arg == "zurück" then
        local n = ns.Erfassung.Wiederherstellen()
        if not n then sag(GRAU .. L["Es gibt keine Sicherung."] .. "|r") return end
        sag(string.format(L["|cff55ff55%d Einträge|r aus der Sicherung zurückgeholt."], n))
        return
    end

    if arg == "ja" or arg == "yes" then
        if not resetBereit or (time() - resetBereit) > 60 then
            sag(ROT .. L["Erst |cffffff78/fs reset|r eingeben, dann innerhalb einer Minute bestätigen."] .. "|r")
            return
        end
        resetBereit = nil
        local n = ns.Erfassung.Zuruecksetzen()
        sag(string.format(L["|cff55ff55%d Einträge|r entfernt. Gesichert: |cffffff78/fs reset undo|r holt sie zurück."], n))
        print(L["  |cff8E9A94Nur auf diesem Rechner: Haben andere in der Gruppe die Einträge noch, bringt sie der nächste Abgleich zurück.|r"])
        return
    end

    local n = 0
    for _ in pairs(ns.Erfassung.Historie()) do n = n + 1 end
    resetBereit = time()
    sag(string.format(L["Das entfernt |cffffff78%d Einträge|r der Historie auf diesem Rechner (Einstellungen und Gruppen bleiben, eine Sicherung wird angelegt)."], n))
    print(L["  Zum Bestätigen innerhalb einer Minute: |cffffff78/fs reset ja|r"])
end

befehle["filter"] = function(arg)
    local d = ns.Erfassung.Einstellungen()
    local stufe = tonumber(arg)
    if stufe and stufe >= 0 and stufe <= 5 then
        d.mindestQualitaet = stufe
    elseif arg == "raid" or arg == "instanz" or arg == "instance"
           or arg == "ueberall" or arg == "überall" or arg == "everywhere" then
        if arg == "instance" then arg = "instanz" end
        if arg == "überall" or arg == "everywhere" then arg = "ueberall" end
        d.ort = arg
    elseif arg == "wurf" or arg == "roll" then
        d.nurGewuerfelt = not d.nurGewuerfelt
    elseif arg ~= "" then
        sag(L["Nutzung: |cffffff78/fs filter 0-5|r (Qualität), |cffffff78raid|instanz|überall|r (Ort) oder |cffffff78wurf|r (nur Ausgewürfeltes)"])
        return
    end

    local Namen = { [0] = L["Schlecht"], [1] = L["Gewöhnlich"], [2] = L["Ungewöhnlich"],
                    [3] = L["Selten"], [4] = L["Episch"], [5] = L["Legendär"] }
    local Orte = {
        raid     = L["nur in Schlachtzugsinstanzen"],
        instanz  = L["in Instanzen, auch Fünfergruppen"],
        ueberall = L["überall"],
    }
    sag(string.format(L["Erfasst ab |cffffff78%s|r, %s%s."],
        Namen[d.mindestQualitaet] or d.mindestQualitaet,
        Orte[d.ort] or d.ort,
        d.nurGewuerfelt and (", " .. L["nur Ausgewürfeltes"]) or ""))
    if d.nurGewuerfelt then
        print(L["  |cff8E9A94⚠ Ohne Bedarfswurf zugeteilte Stücke fallen dabei heraus.|r"])
    end
end

befehle["stand"] = function()
    local eigen = ns.Erfassung.Historie()
    local n = 0
    for _ in pairs(eigen) do n = n + 1 end
    local liste, gesamt = Kern.Bilanz(eigen, 0)
    sag(string.format(L["Eigene Historie: |cff55ff55%d Einträge|r, davon %d auswertbar an %d Spieler."],
        n, gesamt, #liste))

    -- Woher stammen die Eintraege?
    local Herkunft = {}
    for _, e in pairs(eigen) do
        local h = e.herkunft or (e.ausGargul and "gargul-import") or L["unbekannt"]
        Herkunft[h] = (Herkunft[h] or 0) + 1
    end
    local teile = {}
    for h, c in pairs(Herkunft) do teile[#teile + 1] = h .. " " .. c end
    table.sort(teile)
    print(string.format(L["  |cff8E9A94Herkunft: %s|r"],
        #teile > 0 and table.concat(teile, ", ") or L["noch nichts"]))

    local kann, grund = ns.Blizzbeute.Verfuegbar()
    print(string.format(L["  |cff8E9A94Beute-Historie des Clients: %s.|r"],
        kann and L["nutzbar"] or ("|cffff5555" .. tostring(grund) .. "|r" .. GRAU)))

    local beute, wurf = ns.Erfassung.MusterBauen()
    print(string.format(L["  |cff8E9A94Aufzeichnen: %d Beutemuster, Wurfmuster %s, %d Würfe gemerkt.|r"],
        beute, wurf and L["da"] or L["FEHLT"], ns.Erfassung.OffeneWuerfe()))

    local darf, warum = ns.Rolle.IchSchreibe()
    print(string.format(L["  Aufzeichner: %s |cff8E9A94(%s)|r"],
        darf and (GRUEN .. L["du zeichnest auf"] .. "|r") or (GELB .. L["du zeichnest nicht auf"] .. "|r"),
        tostring(warum)))

    local ok, wert = Quelle.Stand()
    if not ok then
        print("  " .. GRAU .. tostring(wert) .. " – " .. L["nichts zu übernehmen."] .. "|r")
        return
    end
    print(string.format(L["  |cff8E9A94Garguls Bestand: %d Einträge – |r|cffffff78/fs import|r|cff8E9A94 übernimmt ihn.|r"], wert))
end

befehle["state"] = befehle["stand"]

--- Diagnose: welche Textvorlagen und Namens-APIs gibt es hier?
befehle["muster"] = function()
    sag(L["Textvorlagen für eigene Erkennung:"])
    for _, name in ipairs({
        "RANDOM_ROLL_RESULT",
        "LOOT_ITEM", "LOOT_ITEM_SELF",
        "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_SELF_MULTIPLE",
        "LOOT_ITEM_PUSHED", "LOOT_ITEM_PUSHED_SELF",
    }) do
        local wert = rawget(_G, name)
        if type(wert) == "string" then
            print(string.format("  |cff55ff55%s|r  %s", name, wert))
        else
            print(string.format(L["  |cffff5555%s fehlt|r"], name))
        end
    end

    sag(L["Namens-APIs (Nachnamen in Forever):"])
    local NU = rawget(_G, "NameUtil")
    print("  NameUtil: " .. (NU and ("|cff55ff55" .. L["da"] .. "|r") or (ROT .. L["fehlt"] .. "|r")))
    if NU then
        for _, f in ipairs({ "FormatUnitNameForDisplay", "SplitPlayerNameIntoParts",
                             "GetFullNameWithoutRealm", "GetUnitFirstName" }) do
            print("    " .. f .. ": " .. (type(NU[f]) == "function"
                and ("|cff55ff55" .. L["da"] .. "|r") or (GRAU .. L["fehlt"] .. "|r")))
        end
    end

    local name, zweites = UnitName("player")
    print(string.format(L["  UnitName: |cffffff78%s|r  zweiter Wert: |cffffff78%s|r"],
        tostring(name), tostring(zweites)))
    if GetUnitName then
        print(string.format("  GetUnitName(player, true): |cffffff78%s|r",
            tostring(GetUnitName("player", true))))
    end
end

befehle["patterns"] = befehle["muster"]

befehle["auto"] = function()
    local an = Fenster.AutoUmschalten()
    if an then
        sag(L["Fenster öffnet sich automatisch, sobald ein Wurf startet."])
    else
        sag(L["Automatisches Öffnen aus. |cffffff78/fs|r öffnet es von Hand."])
    end
end

befehle["demo"] = function()
    Fenster.Zeigen(true)
end

befehle["verlauf"] = function()
    Fenster.ZeigenAnsicht("verlauf")
end
befehle["history"] = befehle["verlauf"]

befehle["einstellungen"] = function()
    ns.Einstellungen.Umschalten()
end
befehle["optionen"] = befehle["einstellungen"]
befehle["settings"] = befehle["einstellungen"]
befehle["options"] = befehle["einstellungen"]

befehle["test"] = function()
    if ns.Tests and ns.Tests.Alle then ns.Tests.Alle() else sag(L["Keine Tests geladen."]) end
end

--- Diagnose fuer das Einstellungsfenster: Zeichnet es Text nicht, steht hier warum.
befehle["darstellung"] = function()
    ns.Einstellungen.Zeigen()
    sag(L["Darstellung der Einstellungen:"])
    for _, z in ipairs(ns.Einstellungen.Diagnose()) do print("  " .. z) end
end
befehle["appearance"] = befehle["darstellung"]

-- ---------------------------------------------------------------------
--  Wer zeichnet auf, Abgleich
-- ---------------------------------------------------------------------

befehle["rolle"] = function()
    local darf, grund = ns.Rolle.IchSchreibe()
    sag(darf and (GRUEN .. L["Du zeichnest auf."] .. "|r") or (GELB .. L["Du zeichnest nicht auf."] .. "|r"))
    print(string.format(L["  |cff8E9A94Grund: %s|r"], tostring(grund)))

    local kandidaten, methode = ns.Rolle.Kandidaten()
    print(string.format(L["  |cff8E9A94Beutemethode: %s|r"], tostring(methode)))
    if #kandidaten == 0 then
        print(L["  |cff8E9A94Keine Kandidaten erkannt (keine Gruppe, oder niemand ist Leiter).|r"])
    end
    local hat = ns.Abgleich.Bekannte()
    for i, k in ipairs(kandidaten) do
        local addon = k.ich and (GRUEN .. L["du"] .. "|r")
            or (hat[Kern.Schluessel(k.name) or "?"] and (GRUEN .. L["ja"] .. "|r") or (GRAU .. L["unbekannt"] .. "|r"))
        print(string.format(L["  %d. %s (%s) – Addon: %s"], i, tostring(k.name), tostring(k.rolle), addon))
    end
end

befehle["role"] = befehle["rolle"]

--- Diagnose: was liefert die Gildenliste (Namen, Raenge)?
befehle["gilde"] = function()
    local M, grund = ns.Gruppen.GildenMitglieder()
    if not M then sag(ROT .. tostring(grund) .. "|r") return end
    sag(string.format(L["Gildenliste: %d Mitglieder. Die ersten:"], #M))
    for i = 1, math.min(6, #M) do
        print(string.format("  %s  |cff8E9A94(%s, %s)|r", tostring(M[i].name), tostring(M[i].rang), tostring(M[i].rangIndex)))
    end
end
befehle["guild"] = befehle["gilde"]

--- ⭐ Eigenes Wuerfelfenster: `/fs wurf <Link>` startet, `/fs wurf` oeffnet den Dialog,
--  `/fs wurf ende` beendet.
befehle["wurf"] = function(arg)
    arg = arg or ""
    local kleinn = arg:lower()
    if kleinn == "ende" or kleinn == "end" or kleinn == "stop" then
        local ok, grund = ns.Wurf.BeendenAlle()
        if not ok then sag(ROT .. tostring(grund) .. "|r") end
        return
    end
    if kleinn == "status" then
        sag(L["Wurf-Status:"])
        for _, z in ipairs(ns.Wurf.Status()) do print("  " .. z) end
        return
    end
    if kleinn == "offen" or kleinn == "pending" or kleinn == "offen leeren" or kleinn == "pending clear" then
        if kleinn:find("leeren", 1, true) or kleinn:find("clear", 1, true) then
            sag(string.format(L["%d Vormerkungen gelöscht."], ns.Wurf.OffeneLeeren()))
            return
        end
        local liste = ns.Wurf.Offene()
        if #liste == 0 then
            sag(GRAU .. L["Keine Zuteilung vorgemerkt."] .. "|r")
            return
        end
        sag(L["Vorgemerkte Zuteilungen:"])
        for _, e in ipairs(liste) do
            print(string.format(L["  %s an %s (vor %d Min.)"], e.link, e.name, math.floor((time() - (e.zeit or 0)) / 60)))
        end
        print(L["  |cff8E9A94Beim nächsten Handel mit dem Spieler wird der Gegenstand eingelegt. |r|cffffff78/fs wurf offen leeren|r|cff8E9A94 löscht alle.|r"])
        return
    end
    if kleinn == "ergebnis" or kleinn == "result" then
        local ok, grund = ns.Wurf.ErgebnisOeffnen()
        if not ok then sag(ROT .. tostring(grund) .. "|r") end
        return
    end
    if arg == "" then
        ns.Wurf.Dialog()
        return
    end
    local ok, grund = ns.Wurf.Starten(arg)
    if not ok then
        sag(ROT .. tostring(grund) .. "|r")
        return
    end
    sag(string.format(L["Wurf gestartet – %d Sekunden."], ns.Wurf.Dauer()))
end
befehle["roll"] = befehle["wurf"]

--- Diagnose fuer die Zuteilung durch den Pluendermeister (nur lesen).
befehle["beutetest"] = function()
    sag(L["Beutetest:"])
    for _, z in ipairs(ns.Wurf.Beutetest()) do print(z) end
end
befehle["lootcheck"] = befehle["beutetest"]

--- ⭐ Die letzte Vergabe zuruecknehmen: erst zeigen, dann (binnen einer Minute) bestaetigen.
--  Einzelne Vergaben nimmt man im Verlauf oder im Spielerdetail zurueck (Knopf „Rückgängig").
local undoBereit = nil

befehle["rueckgaengig"] = function(arg)
    arg = (arg or ""):lower()
    local liste = Kern.Verlauf(ns.Erfassung.Historie(), 0, nil)
    local e = liste[1]
    if not e then sag(GRAU .. L["Keine Vergabe vorhanden."] .. "|r") return end

    if arg == "ja" or arg == "yes" then
        if not undoBereit or undoBereit.id ~= e.id or (time() - undoBereit.zeit) > 60 then
            sag(ROT .. L["Erst |cffffff78/fs rueckgaengig|r eingeben, dann innerhalb einer Minute bestätigen."] .. "|r")
            return
        end
        undoBereit = nil
        local ok, grund = ns.Erfassung.Zuruecknehmen(e.id)
        if ok then
            sag(GRUEN .. string.format(L["Zurückgenommen: %s an %s."], Quelle.Gegenstandstext(e.eintrag), e.name) .. "|r")
        else
            sag(ROT .. tostring(grund) .. "|r")
        end
        return
    end

    undoBereit = { id = e.id, zeit = time() }
    sag(string.format(L["Zurücknehmen: %s an %s (%s)?"], Quelle.Gegenstandstext(e.eintrag), e.name, date(L["%d.%m. %H:%M"], e.zeit)))
    print(L["  Zum Bestätigen innerhalb einer Minute: |cffffff78/fs rueckgaengig ja|r"])
end
befehle["undo"] = befehle["rueckgaengig"]
befehle["revert"] = befehle["rueckgaengig"]

befehle["abgleich"] = function(arg)
    if arg == "status" or arg == "stand" then
        sag(L["Abgleich:"])
        for _, z in ipairs(ns.Abgleich.Diagnose()) do print("  " .. z) end
        return
    end
    local ok, grund = ns.Abgleich.Starten()
    if not ok then sag(ROT .. tostring(grund) .. "|r") end
end
befehle["sync"] = befehle["abgleich"]

befehle["bereiche"] = function(arg)
    if arg == "setzen" or arg == "set" then
        local ok, grund = Quelle.GargulBereicheSetzen()
        if not ok then sag(ROT .. tostring(grund) .. "|r") return end
        sag(GRUEN .. L["Bei Gargul eingestellt: MS 1-100, OS 1-50."] .. "|r")
        return
    end
    local B, grund = Quelle.GargulBereiche()
    if not B then sag(GRAU .. tostring(grund) .. "|r") return end
    sag(B.ok and (GRUEN .. L["Würfelbereiche stimmen."] .. "|r") or (ROT .. L["Würfelbereiche passen nicht."] .. "|r"))
    print(string.format(L["  |cff8E9A94Gargul kennt: %s|r"], table.concat(B.bereiche, ", ")))
    if not B.ok then
        print(L["  |cffffff78/fs bereiche setzen|r|cff8E9A94 stellt 1-100 (Haupt) und 1-50 (Zweit) ein.|r"])
    end
end
befehle["brackets"] = befehle["bereiche"]

-- ---------------------------------------------------------------------
--  Gruppen
-- ---------------------------------------------------------------------

befehle["gruppe"] = function(arg)
    local G = ns.Gruppen
    local was, rest = (arg or ""):match("^(%S*)%s*(.-)%s*$")
    was = (was or ""):lower()

    if was == "hilfe" or was == "help" or was == "?" then
        sag(L["Gruppen:"])
        print(L["  |cffffff78/fs gruppe|r                   – alle Gruppen"])
        print(L["  |cffffff78/fs gruppe neu <Name>|r        – Gruppe anlegen (Kader)"])
        print(L["  |cffffff78/fs gruppe aktiv <Name>|r      – aktive Gruppe; ohne Namen: keine"])
        print(L["  |cffffff78/fs gruppe kader A, B, C|r     – Namen zum Kader (Komma!)"])
        print(L["  |cffffff78/fs gruppe sync|r              – Kader mit den Gildenrängen abgleichen (hinzufügen und entfernen)"])
        print(L["  |cffffff78/fs gruppe raenge|r            – Gildenränge anzeigen; |cffffff78raenge <Nr>|r wählt oder streicht einen"])
        print(L["  |cffffff78/fs gruppe entfernen <Name>|r  – Name aus dem Kader"])
        print(L["  |cffffff78/fs gruppe loeschen <Name>|r   – Gruppe löschen"])
        return
    end

    if was == "neu" or was == "new" then
        local ok, grund = G.Anlegen(rest)
        sag(ok and (GRUEN .. string.format(L["Gruppe „%s“ angelegt."], rest) .. "|r") or (ROT .. tostring(grund) .. "|r"))
    elseif was == "aktiv" or was == "active" then
        local name = rest ~= "" and rest or nil
        if G.Aktivieren(name) then
            sag(name and string.format(L["Aktiv: |cffffff78%s|r"], name) or L["Keine Gruppe aktiv."])
        else
            sag(ROT .. L["Die Gruppe gibt es nicht."] .. "|r")
        end
    elseif was == "raenge" or was == "ranks" then
        local name = G.AktivName()
        if not name then sag(ROT .. L["Keine Gruppe aktiv."] .. "|r") return end
        local R, grund = G.Raenge()
        if not R then sag(ROT .. tostring(grund) .. "|r") return end
        local nr = tonumber(rest)
        if nr and R[nr] then
            G.RangSetzen(name, R[nr].index, not G.RangGewaehlt(name, R[nr].index))
        end
        sag(string.format(L["Gildenränge für den Kader von %s:"], name))
        for i, r in ipairs(R) do
            print(string.format("  %d. %s  %s", i, r.name,
                G.RangGewaehlt(name, r.index) and (GRUEN .. L["gewählt"] .. "|r") or (GRAU .. "–|r")))
        end
    elseif was == "kader" or was == "roster" then
        local name = G.AktivName()
        if not name then sag(ROT .. L["Keine Gruppe aktiv."] .. "|r") return end
        local n = G.KaderErgaenzen(name, rest)
        sag(string.format(L["%d Namen ergänzt."], n or 0))
    elseif was == "sync" or was == "synchronisieren" or was == "fuellen" or was == "fill" then
        local name = G.AktivName()
        if not name then sag(ROT .. L["Keine Gruppe aktiv."] .. "|r") return end
        local neu, weg = G.Synchronisieren(name)
        if not neu then sag(ROT .. tostring(weg) .. "|r") return end
        sag(string.format(L["Kader „%s“: %d neu, %d entfernt."], name, neu, weg or 0))
    elseif was == "entfernen" or was == "remove" then
        local name = G.AktivName()
        if not name then sag(ROT .. L["Keine Gruppe aktiv."] .. "|r") return end
        sag(G.KaderEntfernen(name, rest) and L["Entfernt."] or (ROT .. L["Den Namen gibt es nicht im Kader."] .. "|r"))
    elseif was == "loeschen" or was == "löschen" or was == "delete" then
        sag(G.Loeschen(rest) and L["Gelöscht."] or (ROT .. L["Die Gruppe gibt es nicht."] .. "|r"))
    else
        local Namen = G.Namen()
        if #Namen == 0 then
            sag(L["Noch keine Gruppe. |cffffff78/fs gruppe neu 40er|r legt eine an, |cffffff78/fs gruppe hilfe|r zeigt alles."])
            return
        end
        local aktiv = G.AktivName()
        sag(L["Gruppen:"])
        for _, n in ipairs(Namen) do
            local g = G.Holen(n)
            print(string.format("  %s%s|r  %s%s|r", n == aktiv and GELB or "", n, GRAU,
                string.format(L["%d im Kader"], #G.Namensliste(g))))
        end
    end
end
befehle["group"] = befehle["gruppe"]

-- ---------------------------------------------------------------------
--  Auswertung im Chat
-- ---------------------------------------------------------------------

befehle["liste"] = function(arg)
    local wochen = tonumber(arg) or 0
    local H, grund = Quelle.Historie()
    if not H then sag(ROT .. tostring(grund) .. "|r") return end

    local seit = Kern.Seit(time(), wochen)
    local liste, gesamt, aeltester = Kern.Bilanz(H, seit, ns.Gruppen.Pflicht(nil))

    if #liste == 0 then sag(L["Keine Vergabe im Zeitraum."]) return end

    sag(string.format(L["%s: |cff55ff55%d Vergaben|r an %d Spieler, %d Raidtage"],
        wochen > 0 and string.format(L["%d Wochen"], wochen) or L["Gesamte Historie"],
        gesamt, #liste, Kern.Raidtage(H, seit, Quelle.Tag)))
    if aeltester then
        print(string.format(L["  |cff8E9A94Älteste Aufzeichnung: %s|r"], date(L["%d.%m.%Y"], aeltester)))
    end

    for i, z in ipairs(liste) do
        if i > 30 then
            print(string.format(L["  |cff8E9A94… und %d weitere|r"], #liste - 30))
            break
        end
        local seitText = ""
        if z.letzte > 0 then
            seitText = "  " .. GRAU .. string.format(L["vor %d Tagen"],
                math.floor((time() - z.letzte) / Kern.TAG)) .. "|r"
        end
        print(string.format("  %-14s " .. GELB .. "%2d|r %s%s%s", z.name, z.haupt, L["Haupt"],
            z.zweit > 0 and ("  " .. GRAU .. string.format(L["%d Zweit"], z.zweit) .. "|r") or "        ",
            seitText))
    end
end
befehle["list"] = befehle["liste"]

--- Einzelner Spieler, sonst Hilfe.
local function spielerOderHilfe(name)
    local H, grund = Quelle.Historie()
    if not H then sag(ROT .. tostring(grund) .. "|r") return end

    local liste = Kern.Spieler(H, name, 0)
    if #liste == 0 then
        sag(string.format(L["Für |cffffff78%s|r ist keine Vergabe verzeichnet."], name))
        return
    end

    local haupt = 0
    for _, e in ipairs(liste) do if not e.zweit then haupt = haupt + 1 end end
    sag(string.format(L["%s: |cff55ff55%d Vergaben|r, davon %d Hauptbedarf"],
        Kern.Anzeigename(name), #liste, haupt))

    for i, e in ipairs(liste) do
        if i > 25 then
            print(string.format(L["  |cff8E9A94… und %d weitere|r"], #liste - 25))
            break
        end
        print(string.format("  %s  %s%s", date(L["%d.%m.%y"], e.zeit),
            Quelle.Gegenstandstext(e.eintrag),
            e.zweit and ("  " .. GRAU .. L["Zweitbedarf"] .. "|r") or ""))
    end
end

-- =====================================================================

SLASH_FAIRSHARE1 = "/fs"
SLASH_FAIRSHARE2 = "/fairshare"
SlashCmdList["FAIRSHARE"] = function(eingabe)
    local wort, rest = (eingabe or ""):match("^%s*(%S*)%s*(.-)%s*$")
    wort = wort or ""

    local fn = befehle[wort:lower()]
    local ok, fehler

    if wort == "" then
        ok, fehler = pcall(Fenster.Umschalten, false)
    elseif fn then
        ok, fehler = pcall(fn, (rest or ""))
    elseif wort:lower() == "hilfe" or wort:lower() == "help" or wort == "?" then
        ok, fehler = pcall(hilfe)
    else
        -- Alles andere wird als Spielername verstanden
        ok, fehler = pcall(spielerOderHilfe, (eingabe or ""):match("^%s*(.-)%s*$"))
    end

    if not ok then
        print(PRAEFIX .. ROT .. string.format(L["Fehler in /fs %s"], wort) .. "|r")
        print(ROT .. tostring(fehler) .. "|r")
        print(GRAU .. L["Bitte diese zwei Zeilen weitergeben."] .. "|r")
    end
end

-- Eine Zeile beim Laden, damit man sieht, dass es da ist.
local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(4, function()
        local n = 0
        for _ in pairs(ns.Erfassung.Historie()) do n = n + 1 end
        if n > 0 then
            sag(string.format(L["%d Vergaben aufgezeichnet. |cffffff78/fs|r öffnet die Übersicht."], n))
        else
            sag(L["|cff8E9A94Noch keine Vergabe aufgezeichnet – |r|cffffff78/fs demo|r|cff8E9A94 zeigt die Anzeige trotzdem.|r"])
        end
    end)
end)

ns.geladen = true

return ns
