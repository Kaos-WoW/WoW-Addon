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
    print(L["  |cffffff78/fs invite|r       – Anwesende Spieler der Gruppe in den Raid einladen"])
    print(L["  |cffffff78/fs nutzung|r      – Fairshare für diese Gruppe nutzen? (|cffffff78nutzung ja|r, |cffffff78nutzung nein|r, |cffffff78nutzung fragen|r)"])
    print(L["  |cffffff78/fs rolle|r        – wer zeichnet gerade auf, und warum"])
    print(L["  |cffffff78/fs rueckgaengig|r – die letzte Vergabe zurücknehmen (mit Rückfrage; einzelne Vergaben im Verlauf)"])
    print(L["  |cffffff78/fs wurf|r         – eigenes Würfelfenster starten (|cffffff78wurf [Sekunden] <Link>|r, |cffffff78wurf ende|r, |cffffff78wurf abbrechen|r, |cffffff78wurf entzaubern|r, |cffffff78wurf ergebnis|r, |cffffff78wurf offen|r, |cffffff78wurf status|r)"])
    print(L["  |cffffff78/fs konfig|r       – Einstellungen teilen (|cffffff78konfig senden|r, |cffffff78nachfragen|r, |cffffff78zurueck|r)"])
    print(L["  |cffffff78/fs verzauberer|r  – Verzauberer fürs Entzaubern (|cffffff78verzauberer add Name, Name|r, |cffffff78verzauberer del Name|r)"])
    print(L["  |cffffff78/fs beutetest|r    – Diagnose: Beutefenster und Zuteilung durch den Plündermeister"])
    print(L["  |cffffff78/fs kompakt|r      – kleines Fenster für den Raid (|cffffff78kompakt test|r = Vorschau)"])
    print(L["  |cffffff78/fs gruppe|r       – Kader und Raidgruppen (|cffffff78gruppe hilfe|r)"])
    print(L["  |cffffff78/fs anwesenheit|r  – Anwesenheit und Bosskämpfe des heutigen Abends"])
    print(L["  |cffffff78/fs abschluss|r     – Raidabend abschließen und Zuschläge festschreiben"])
    print(L["  |cffffff78/fs bank|r         – Bank- und Abwesenheitsliste (|cffffff78/fs bank <Name>|r)"])
    print(L["  |cffffff78/fs unentschuldigt|r – Unentschuldigte Spieler (|cffffff78/fs unent <Name>|r)"])
    print(L["  |cffffff78/fs vergessen|r    – Anmeldung vergessen (|cffffff78/fs vergessen <Name>|r)"])
    print(L["  |cffffff78/fs abmeldung|r    – ausdrücklich abgemeldet (|cffffff78/fs abmeldung <Name>|r, |cffffff78alle|r = alle Offenen)"])
    print(L["  |cffffff78/fs einteilung|r   – Raidkader und Einteilung je Raid-ID und Gruppe (|cffffff78/fs raidkader <Rang>|r liest den Raidkader ein)"])
    print(L["  |cffffff78/fs rueckgabe|r    – zurückgegebene Items, noch nicht neu vergeben (|cffffff78/fs rueckgabe <Nr>|r schließt ab)"])
    print(L["  |cffffff78/fs bereiche|r     – Würfelbereiche (|cffffff78bereiche haupt 1 100|r, |cffffff78zweit 1 99|r)"])
    print(L["  |cffffff78/fs auto|r         – Fenster bei Wurfbeginn automatisch öffnen (an/aus)"])
    print(L["  |cffffff78/fs anhebung <Name>|r – Spieler manuell auf Niedrigster + 2 anheben (Raid- oder Gildenleitung)"])
    print(L["  |cffffff78/fs einladewort [Wort|an|aus]|r – wer dir das Stichwort flüstert, wird eingeladen"])
    print(L["  |cffffff78/fs reset|r        – Historie auf diesem Rechner leeren (mit Rückfrage und Sicherung)"])
    print(L["  |cffffff78/fs reset gilde|r  – Daten bei ALLEN Gildenmitgliedern zurücksetzen (nur Stufe 1 und 2, mit Rückfrage)"])
    print(L["  |cffffff78/fs filter|r       – ab welcher Qualität und wo aufgezeichnet wird"])
    print(L["  |cffffff78/fs gilde|r        – Diagnose: was die Gildenliste liefert (Namen, Ränge)"])
    print(L["  |cffffff78/fs stand|r        – Diagnose: eigene Historie und Aufzeichnung"])
    print(L["  |cffffff78/fs muster|r       – Diagnose: Textvorlagen für eigene Erkennung"])
    print(L["  |cffffff78/fs darstellung|r  – Diagnose: Einstellungsfenster zeichnet nicht richtig"])
    print(L["  |cffffff78/fs test|r         – Selbsttests der Auswertung"])
    print(L["  |cffffff78/fs probe|r        – Übungsmodus (Standardabend testen, keine echten Daten)"])
end

-- =====================================================================

--- ⭐ Historie leeren: erst fragen, dann tun, vorher sichern.
local resetBereit, resetGildeBereit = nil, nil

befehle["reset"] = function(arg)
    arg = (arg or ""):lower()

    -- ⭐ Gildenweit: leert die Daten bei allen (Reset-Marke, siehe Erfassung.GildenReset)
    local gilde = arg:match("^gilde%s*(.*)$") or arg:match("^guild%s*(.*)$")
    if gilde then
        if not (ns.Konfig.DarfWurzel and ns.Konfig.DarfWurzel()) then
            sag(ROT .. L["Nur Gildenmeister und Offiziere (Stufe 1 und 2) dürfen die Daten gildenweit zurücksetzen."] .. "|r")
            return
        end
        if gilde == "ja" or gilde == "yes" then
            if not resetGildeBereit or (time() - resetGildeBereit) > 60 then
                sag(ROT .. L["Erst |cffffff78/fs reset gilde|r eingeben, dann innerhalb einer Minute bestätigen."] .. "|r")
                return
            end
            resetGildeBereit = nil
            local n, grund = ns.Erfassung.GildenReset()
            if not n then sag(ROT .. tostring(grund) .. "|r") return end
            sag(string.format(L["|cff55ff55%d Einträge|r entfernt, die Reset-Marke geht an alle Gildenmitglieder mit dem Addon."], n))
            if grund then sag(ROT .. tostring(grund) .. "|r") end
            return
        end
        local n = 0
        for _ in pairs(ns.Erfassung.Historie()) do n = n + 1 end
        resetGildeBereit = time()
        sag(string.format(L["Das entfernt |cffffff78%d Einträge|r der Historie samt allen Abschlüssen, Zuschlägen und Anhebungen bei |cffff5555ALLEN|r Gildenmitgliedern mit dem Addon. Einstellungen, Gruppen und Einteilung bleiben. Das lässt sich nicht zurücknehmen."], n))
        print(L["  Zum Bestätigen innerhalb einer Minute: |cffffff78/fs reset gilde ja|r"])
        return
    end

    if arg == "undo" or arg == "zurueck" or arg == "zurück" then
        local n, grund = ns.Erfassung.Wiederherstellen()
        if not n then sag(GRAU .. (grund or L["Es gibt keine Sicherung."]) .. "|r") return end
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
        print(L["  |cff8E9A94Nur auf diesem Rechner: Haben andere in der Gruppe die Einträge noch, bringt sie der nächste Abgleich zurück. Für alle in der Gilde: |cffffff78/fs reset gilde|r.|r"])
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
        local h = e.herkunft or L["unbekannt"]
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

--- Das kleine Fenster fuer den Raid ein- oder ausschalten.
befehle["kompakt"] = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    if arg == "test" or arg == "vorschau" or arg == "preview" then
        ns.Kompakt.Vorschau()
    else
        ns.Kompakt.Umschalten()
    end
end
befehle["compact"] = befehle["kompakt"]

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

befehle["probe"] = function(arg)
    arg = (arg or ""):lower():match("^%s*(.-)%s*$")
    local unter = arg:match("^(%S+)") or ""
    if unter == "abend" or unter == "night" then
        if ns.Probe and ns.Probe.StandardAbend then
            ns.Probe.StandardAbend(true)
        else
            sag(L["Probe-Modus nicht verfügbar."])
        end
    else
        if ns.Fenster and ns.Fenster.ProbeUmschalten then
            ns.Fenster.ProbeUmschalten()
        else
            sag(L["Probe-Modus nicht verfügbar."])
        end
        sag(L["Probe-Modus (Übungsmodus):"])
        print(L["  |cffffff78/fs probe abend|r  – Standardabend im Chat ausgeben (Erwartet / Ist)"])
    end
end
befehle["practice"] = befehle["probe"]

--- Diagnose fuer das Einstellungsfenster: Zeichnet es Text nicht, steht hier warum.
befehle["darstellung"] = function()
    ns.Einstellungen.Zeigen()
    sag(L["Darstellung der Einstellungen:"])
    for _, z in ipairs(ns.Einstellungen.Diagnose()) do print("  " .. z) end
end
befehle["appearance"] = befehle["darstellung"]

-- ---------------------------------------------------------------------
--  Anwesenheit & Bosskämpfe
-- ---------------------------------------------------------------------

befehle["anwesenheit"] = function(rest)
    rest = rest and rest:match("^%s*(.-)%s*$") or ""
    local unter = rest:match("^(%S+)")
    unter = unter and unter:lower() or ""

    if unter == "reset" or unter == "neu" then
        if ns.Anwesenheit then ns.Anwesenheit.AbendZuruecksetzen() end
        sag(L["Neuer Raidabend begonnen (vorheriger Stand zurückgesetzt)."])
        return
    end

    if unter == "boss" then
        local bossName = rest:match("^%S+%s+(.+)$")
        if not bossName or bossName == "" then
            sag(L["Bitte einen Bossnamen angeben: /fs anwesenheit boss <Name>"])
            return
        end
        if not ns.Anwesenheit then return end
        local ok, anzahl, bName = ns.Anwesenheit.BossBuchen(bossName, nil, true)
        if ok then
            sag(string.format(L["Bosskampf %s von Hand gebucht (%d Spieler erfasst)."], bName, anzahl))
        else
            sag(ROT .. tostring(anzahl) .. "|r")
        end
        return
    end

    -- Übersicht ausgeben
    if not ns.Anwesenheit then return end
    local abend = ns.Anwesenheit.AktiverAbend(false)
    if not abend or (abend.bosse or 0) == 0 then
        sag(L["Noch keine Bosskämpfe an diesem Abend aufgezeichnet."])
        return
    end

    local teilnehmer = ns.Anwesenheit.Uebersicht(abend)
    sag(string.format(L["Heutiger Raidabend: %d Bosskämpfe erfasst (%d Teilnehmer)"], abend.bosse, #teilnehmer))

    for _, t in ipairs(teilnehmer) do
        local tag = (t.status == "kader" and GRUEN .. L["Kader"] .. "|r")
                 or (t.status == "proberaid" and GELB .. L["Proberaid"] .. "|r")
                 or (t.status == "neuling" and GELB .. L["Neuling (2. Abend)"] .. "|r")
                 or (GRAU .. L["Gast"] .. "|r")

        local quoteStr = t.imRaid and (GRUEN .. L["Im Raid (≥ 50 %)"] .. "|r") or (ROT .. L["Unter Quote (< 50 %)"] .. "|r")
        print(string.format(L["  %s [%s]: %d/%d (%d %%) — %s"],
            t.name, tag, t.bosse, t.gesamt, t.prozent, quoteStr))
    end
    print(GRAU .. L["Regel § 2: Ab 50 % der Bosskämpfe gilt man als im Raid (kein Fehl-Zuschlag)."] .. "|r")
end
befehle["anw"] = befehle["anwesenheit"]
befehle["attendance"] = befehle["anwesenheit"]

-- ---------------------------------------------------------------------
--  Bank und Unentschuldigt (§ 2, § 6)
-- ---------------------------------------------------------------------

befehle["bank"] = function(rest)
    rest = rest and rest:match("^%s*(.-)%s*$") or ""
    if rest == "" then
        Fenster.ZeigenAnsicht("bank")
        return
    end

    local unter = rest:lower()
    if unter == "status" or unter == "liste" then
        if not ns.Anwesenheit then return end
        local abend = ns.Anwesenheit.AktiverAbend(false)
        local kandidaten = ns.Anwesenheit.KandidatenListe(abend)
        sag(string.format(L["Bank- und Abwesenheitsliste (%d Kandidaten):"], #kandidaten))
        for _, k in ipairs(kandidaten) do
            local status = k.bank and (GRUEN .. L["Bank (Faktor 0)"] .. "|r")
                        or (k.unentschuldigt and (ROT .. L["Unentschuldigt (Faktor 1,5, mindestens 2)"] .. "|r")
                        or (k.vergessen and (GELB .. L["Anmeldung vergessen"] .. "|r")
                        or (k.abgemeldet and (HELL .. L["Abgemeldet"] .. "|r")
                        or (k.offen and (GELB .. L["Offen"] .. "|r")
                        or (k.online and (HELL .. L["Online, nicht im Raid"] .. "|r") or (GRAU .. L["Offline"] .. "|r"))))))
            local proto = k.protokoll ~= "" and ("  " .. GRAU .. "(" .. k.protokoll .. ")|r") or ""
            print(string.format(L["  %s — %s%s"], k.name, status, proto))
        end
        return
    end

    local name = rest
    if not ns.Anwesenheit then return end
    local istBank = ns.Anwesenheit.IstBank(name)
    local ok, err = ns.Anwesenheit.BankSetzen(name, not istBank)
    if ok then
        if not istBank then
            sag(string.format(L["%s als Bank eingetragen (Faktor 0)."], Kern.Anzeigename(name)))
        else
            sag(string.format(L["Bank für %s aufgehoben."], Kern.Anzeigename(name)))
        end
        if Fenster.Sichtbar() then Fenster.Aktualisieren() end
    else
        sag(ROT .. tostring(err) .. "|r")
    end
end
befehle["bench"] = befehle["bank"]
befehle["abwesenheit"] = befehle["bank"]
befehle["absence"] = befehle["bank"]

--- ⭐ Ausdrückliche Abmeldung: `/fs abmeldung <Name>` setzt oder hebt sie auf, `/fs abmeldung alle`
--  setzt alle noch offenen Spieler als abgemeldet.
--- ⭐ Einteilung je Tag und Gruppe: `/fs einteilung` oeffnet die Ansicht, `/fs einteilung status` zeigt die
--  letzten Meldungen, `/fs raidkader [Rangnummer]` liest den Raidkader bis zum Rang ein.
befehle["invite"] = function(rest)
    if not ns.Anwesenheit or not ns.Anwesenheit.GruppeEinladen then
        print("|cff1B6B57Fairshare|r: " .. ROT .. L["Anwesenheit nicht verfügbar."] .. "|r")
        return
    end
    local ok, n, drin, offline = ns.Anwesenheit.GruppeEinladen()
    if not ok then
        print("|cff1B6B57Fairshare|r: " .. ROT .. tostring(n) .. "|r")
    elseif n == 0 and drin > 0 and (not offline or offline == 0) then
        print("|cff1B6B57Fairshare|r: " .. L["Alle anwesenden Spieler sind bereits in der Gruppe."])
    elseif n == 0 and (offline and offline > 0) and drin == 0 then
        print(string.format("|cff1B6B57Fairshare|r: " .. L["Keine Spieler eingeladen (%d offline)."], offline))
    elseif offline and offline > 0 then
        print(string.format("|cff1B6B57Fairshare|r: " .. L["%d Spieler eingeladen (%d bereits in der Gruppe, %d offline übersprungen)."], n, drin, offline))
    else
        print(string.format("|cff1B6B57Fairshare|r: " .. L["%d Spieler eingeladen (%d bereits in der Gruppe)."], n, drin))
    end
end
befehle["einladen"] = befehle["invite"]

befehle["einteilung"] = function(rest)
    rest = rest and rest:match("^%s*(.-)%s*$") or ""
    if rest:lower() == "status" then
        sag(L["Letzte Einteilungsmeldungen:"])
        local S = ns.Gruppen.EinteilungStatus()
        if #S == 0 then print(L["  Noch keine empfangen."]) end
        for _, z in ipairs(S) do print("  " .. z) end
        return
    end
    Fenster.ZeigenAnsicht("einteilung")
end
befehle["assignment"] = befehle["einteilung"]

--- ⭐ Wochenabschluss: `/fs woche` zeigt, wer als abgemeldet oder „Keine Meldung“ gebucht würde, `/fs woche ja` bucht,
--  `/fs woche zurueck` nimmt zurück.
local function wocheAusgeben(v)
    sag(string.format(L["Woche ab %s: %d Abende je Spieler, Schnitt je Abend %s"], v.montag, v.n,
        (function()
            local t = {}
            for i, s in ipairs(v.schnitte) do t[i] = string.format("%.2f", s) end
            return table.concat(t, " / ")
        end)()))
    print(string.format(L["  %d abgemeldet: %s"], #v.abgemeldet, #v.abgemeldet > 0 and table.concat(v.abgemeldet, ", ") or "—"))
    print(string.format(L["  %d Keine Meldung: %s"], #v.keineMeldung, #v.keineMeldung > 0 and table.concat(v.keineMeldung, ", ") or "—"))
end

befehle["woche"] = function(rest)
    rest = rest and rest:match("^%s*(.-)%s*$") or ""
    local datum = ns.Gruppen.EinteilungTag(0)
    local unter = rest:lower()
    if unter == "zurueck" or unter == "zurück" or unter == "undo" then
        local n, grund = ns.Anwesenheit.WocheZuruecknehmen(datum)
        if n then sag(string.format(L["%d Wochenbuchungen zurückgenommen."], n)) else sag(ROT .. tostring(grund) .. "|r") end
        if Fenster.Sichtbar() then Fenster.Aktualisieren() end
        return
    end
    if unter == "ja" or unter == "yes" then
        local v, grund = ns.Anwesenheit.WocheBuchen(datum)
        if not v then sag(ROT .. tostring(grund) .. "|r") return end
        wocheAusgeben(v)
        sag(GRUEN .. string.format(L["Woche gebucht: %d Zuschläge."], v.gebucht or 0) .. "|r")
        if Fenster.Sichtbar() then Fenster.Aktualisieren() end
        return
    end
    local v, grund = ns.Anwesenheit.WocheVorschau(datum)
    if not v then sag(ROT .. tostring(grund) .. "|r") return end
    wocheAusgeben(v)
    print(GRAU .. L["Zum Buchen: /fs woche ja"] .. "|r")
end
befehle["week"] = befehle["woche"]

befehle["raidkader"] = function(rest)
    rest = rest and rest:match("^%s*(.-)%s*$") or ""
    local param
    if rest:find("[,%s]") then
        local t = {}
        for r in rest:gmatch("%d+") do
            local z = tonumber(r)
            if z then t[z] = true end
        end
        if next(t) then param = t end
    elseif tonumber(rest) then
        param = tonumber(rest)
    end
    local n, grund = ns.Gruppen.RaidkaderSync(param)
    if n then
        sag(string.format(L["Raidkader eingelesen: %d Mitglieder."], n))
        if Fenster.Sichtbar() then Fenster.Aktualisieren() end
    else
        sag(ROT .. tostring(grund) .. "|r")
    end
end
befehle["raidroster"] = befehle["raidkader"]

befehle["abmeldung"] = function(rest)
    rest = rest and rest:match("^%s*(.-)%s*$") or ""
    if not ns.Anwesenheit then return end
    if rest == "" then
        local offene = ns.Anwesenheit.OffeneSpieler()
        sag(string.format(L["Offene Spieler heute: %d"], #offene))
        for _, n in ipairs(offene) do print("  " .. n) end
        print(GRAU .. L["Abmelden / aufheben mit: /fs abmeldung <Name>, alle Offenen mit: /fs abmeldung alle"] .. "|r")
        return
    end
    if rest:lower() == "alle" or rest:lower() == "all" then
        local zahl, err = ns.Anwesenheit.AlleOffenenAbmelden()
        if zahl then
            sag(string.format(L["%d offene Spieler als abgemeldet eingetragen."], zahl))
            if Fenster.Sichtbar() then Fenster.Aktualisieren() end
        else
            sag(ROT .. tostring(err) .. "|r")
        end
        return
    end
    local ist = ns.Anwesenheit.IstAbgemeldet(rest)
    local ok, err = ns.Anwesenheit.AbmeldungSetzen(rest, not ist)
    if ok then
        if not ist then
            sag(string.format(L["%s als abgemeldet eingetragen."], Kern.Anzeigename(rest)))
        else
            sag(string.format(L["Abmeldung für %s aufgehoben."], Kern.Anzeigename(rest)))
        end
        if Fenster.Sichtbar() then Fenster.Aktualisieren() end
    else
        sag(ROT .. tostring(err) .. "|r")
    end
end
befehle["abgemeldet"] = befehle["abmeldung"]
befehle["signoff"] = befehle["abmeldung"]

befehle["unentschuldigt"] = function(rest)
    rest = rest and rest:match("^%s*(.-)%s*$") or ""
    if rest == "" then
        if not ns.Anwesenheit then return end
        local abend = ns.Anwesenheit.AktiverAbend(false)
        local anzahl = 0
        sag(L["Unentschuldigte Spieler heute:"])
        for k, u in pairs((abend and abend.unentschuldigt) or {}) do
            anzahl = anzahl + 1
            print(string.format(L["  %s — eingetragen von %s um %s"],
                u.name or k, u.von or "?", date(L["%d.%m. %H:%M"], u.zeit or time())))
        end
        if anzahl == 0 then
            print(L["  Keine unentschuldigten Spieler eingetragen."])
        end
        print(GRAU .. L["Eintragen / aufheben mit: /fs unentschuldigt <Name>"] .. "|r")
        return
    end

    local name = rest
    if not ns.Anwesenheit then return end
    local istUnent = ns.Anwesenheit.IstUnentschuldigt(name)
    local ok, err = ns.Anwesenheit.UnentschuldigtSetzen(name, not istUnent)
    if ok then
        if not istUnent then
            sag(string.format(L["%s als unentschuldigt eingetragen (Faktor 1,5, mindestens 2)."], Kern.Anzeigename(name)))
        else
            sag(string.format(L["Unentschuldigt für %s aufgehoben."], Kern.Anzeigename(name)))
        end
        if Fenster.Sichtbar() then Fenster.Aktualisieren() end
    else
        sag(ROT .. tostring(err) .. "|r")
    end
end
befehle["unent"] = befehle["unentschuldigt"]

--- ⭐ Anmeldung vergessen (Gildenleitung): weder an- noch abgemeldet und nicht erschienen.
befehle["vergessen"] = function(rest)
    rest = rest and rest:match("^%s*(.-)%s*$") or ""
    if rest == "" then
        if not ns.Anwesenheit then return end
        local abend = ns.Anwesenheit.AktiverAbend(false)
        local anzahl = 0
        sag(L["Spieler heute ohne Anmeldung (vergessen):"])
        for k, v in pairs((abend and abend.vergessen) or {}) do
            anzahl = anzahl + 1
            print(string.format(L["  %s — eingetragen von %s um %s"],
                v.name or k, v.von or "?", date(L["%d.%m. %H:%M"], v.zeit or time())))
        end
        if anzahl == 0 then
            print(L["  Keine Spieler als vergessen eingetragen."])
        end
        print(GRAU .. L["Eintragen / aufheben mit: /fs vergessen <Name>"] .. "|r")
        return
    end

    local name = rest
    if not ns.Anwesenheit then return end
    local istVerg = ns.Anwesenheit.IstVergessen(name)
    local ok, err = ns.Anwesenheit.VergessenSetzen(name, not istVerg)
    if ok then
        if not istVerg then
            sag(string.format(L["%s als „Anmeldung vergessen“ eingetragen."], Kern.Anzeigename(name)))
        else
            sag(string.format(L["„Anmeldung vergessen“ für %s aufgehoben."], Kern.Anzeigename(name)))
        end
        if Fenster.Sichtbar() then Fenster.Aktualisieren() end
    else
        sag(ROT .. tostring(err) .. "|r")
    end
end
befehle["forgot"] = befehle["vergessen"]

-- ---------------------------------------------------------------------
--  Abendende & Zuschläge abschließen (§ 2, § 6)
-- ---------------------------------------------------------------------

befehle["abschluss"] = function(rest)
    rest = (rest or ""):match("^%s*(.-)%s*$")
    local sub = rest:lower()

    if sub == "ja" or sub == "yes" then
        local ok, vorschau, zZaehler = ns.Anwesenheit.AbendAbschliessen()
        if ok then
            sag(string.format(L["Raidabend %s erfolgreich abgeschlossen!"], tostring(vorschau.datum)))
            print(string.format(L["  Schnitt: %.2f (%d Main-Items / %d Spieler). %d Zuschläge festgeschrieben."],
                vorschau.schnitt, vorschau.mainItems, vorschau.raidSpieler, zZaehler or 0))
            if Fenster.Sichtbar() then Fenster.Aktualisieren() end
        else
            sag(ROT .. tostring(vorschau) .. "|r")
        end
        return
    end

    if sub == "wiedereroeffnen" or sub == "wiedereröffnen" or sub == "reopen" or sub == "zurueck" or sub == "zurück" then
        local ok, ab = ns.Anwesenheit.AbendWiedereroeffnen()
        if ok then
            sag(string.format(L["Raidabend %s wiedereröffnet, Zuschläge zurückgenommen."], tostring(ab.datum or ab.id)))
            if Fenster.Sichtbar() then Fenster.Aktualisieren() end
        else
            sag(ROT .. tostring(ab) .. "|r")
        end
        return
    end

    -- Vorschau
    local vorschau, err = ns.Anwesenheit.AbendVorschau()
    if not vorschau then
        sag(ROT .. tostring(err) .. "|r")
        return
    end

    sag(string.format(L["Vorschau Raidabend-Abschluss (%s):"], tostring(vorschau.datum)))
    print(string.format(L["  Schnitt: %.2f (%d Main-Items / %d Spieler im Raid, %d Bosse)"],
        vorschau.schnitt, vorschau.mainItems, vorschau.raidSpieler, vorschau.gesamtBosse))

    for _, p in ipairs(vorschau.spieler) do
        if p.status == "unentschuldigt" then
            print(string.format(L["  %s: %s — %s → Zuschlag +%.1f"],
                p.name, L["Unentschuldigt"], L["Faktor 1,5, mindestens 2"], p.zuschlag))
        elseif p.status == "vergessenStrafe" then
            print(string.format(L["  %s: %s (%d. Mal in 8 Abenden) — wie unentschuldigt → Zuschlag +%.1f"],
                p.name, L["Anmeldung vergessen"], p.fehlAnzahl, p.zuschlag))
        elseif p.status == "vergessen" then
            print(string.format(L["  %s: %s (%d. Fehlen) — Faktor %.1f → Zuschlag +%.1f"],
                p.name, L["Anmeldung vergessen"], p.fehlAnzahl, p.faktor, p.zuschlag))
        elseif p.status == "abgemeldet" then
            print(string.format(L["  %s: %s (%d. Fehlen) — Faktor %.1f → Zuschlag +%.1f"],
                p.name, L["Abgemeldet"], p.fehlAnzahl, p.faktor, p.zuschlag))
        elseif p.status == "offen" then
            print(string.format(L["  %s: Offen — noch nicht zugeordnet"], p.name))
        elseif p.status == "bank" then
            print(string.format(L["  %s: %s — %s (kein Zuschlag)"],
                p.name, L["Bank"], L["Faktor 0"]))
        elseif p.status == "imRaid" then
            local prozent = (vorschau.gesamtBosse > 0) and math.floor(p.bosse / vorschau.gesamtBosse * 100 + 0.5) or 100
            print(string.format(L["  %s: Im Raid (%d/%d Bosse, %d %%) — kein Zuschlag"],
                p.name, p.bosse, vorschau.gesamtBosse, prozent))
        end
    end

    print(L["Zum Festschreiben: /fs abschluss ja"])
end
befehle["close"] = befehle["abschluss"]

befehle["abend"] = function(rest)
    local sub, arg = (rest or ""):match("^(%S+)%s*(.*)$")
    sub = sub and sub:lower() or ""
    if sub == "abschluss" or sub == "close" then
        befehle["abschluss"](arg)
    elseif sub == "wiedereroeffnen" or sub == "wiedereröffnen" or sub == "reopen" then
        befehle["abschluss"]("wiedereroeffnen " .. (arg or ""))
    else
        befehle["anwesenheit"](rest)
    end
end

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

--- ⭐ Fairshare nur mit Plündermeister und Zustimmung (Nutzung.lua).
befehle["nutzung"] = function(arg)
    local wort = (arg or ""):lower():match("^%s*(%S*)")
    local methode = ns.Rolle.Methode()
    local aufMaster = (IsInGroup and IsInGroup()) and methode == "master"

    if wort == "ja" or wort == "yes" or wort == "nein" or wort == "no" then
        if not aufMaster then
            sag(GELB .. L["Die Beutemethode ist nicht Plündermeister."] .. "|r")
            return
        end
        ns.Rolle.NutzungSetzen((wort == "ja" or wort == "yes") and "ja" or "nein")
    elseif wort == "fragen" or wort == "ask" then
        if not aufMaster then
            sag(GELB .. L["Die Beutemethode ist nicht Plündermeister."] .. "|r")
            return
        end
        ns.Rolle.NutzungSetzen(nil)
        ns.Nutzung.Fragen()
        return
    end

    local nutzung = ns.Rolle.Nutzung()
    if not aufMaster then
        sag(GELB .. L["Die Beutemethode ist nicht Plündermeister."] .. "|r")
    elseif nutzung == "ja" then
        sag(GRUEN .. L["Fairshare ist aktiv: Es verwaltet die Beuteverteilung."] .. "|r")
    elseif nutzung == "nein" then
        sag(GELB .. L["Fairshare schläft, weil du abgelehnt hast."] .. "|r")
    else
        sag(GELB .. L["Noch keine Antwort – der Dialog fragt, sobald Plündermeister aktiv ist."] .. "|r")
        ns.Nutzung.Fragen()
    end
end
befehle["use"] = befehle["nutzung"]

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
    if kleinn:find("^entzaubern") or kleinn:find("^disenchant") then
        local ok, grund = ns.Wurf.EntzauberOeffnen(arg:match("(|c[^|]*|Hitem:[^|]+|h%[[^%]]*%]|h|r)"))
        if not ok then sag(ROT .. tostring(grund or L["Es gibt kein Ergebnis."]) .. "|r") end
        return
    end
    if kleinn == "abbrechen" or kleinn == "cancel" then
        local ok, grund = ns.Wurf.Abbrechen()
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
            print(string.format(L["  %s an %s (vor %d Min.)"], e.link, e.name, math.floor((time() - (e.zeit or 0)) / 60)) ..
                (e.entzaubern and (" " .. L["(Entzaubern)"]) or ""))
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
    -- „/fs wurf 45 <Link>": die Dauer fuer diesen Wurf vorweg
    local sek, rest = arg:match("^(%d+)%s+(.+)$")
    local ok, grund = ns.Wurf.Starten(rest or arg, sek)
    if not ok then
        sag(ROT .. tostring(grund) .. "|r")
        return
    end
    sag(string.format(L["Wurf gestartet – %d Sekunden."], tonumber(sek) or ns.Wurf.Dauer()))
end
befehle["roll"] = befehle["wurf"]

--- ⭐ Verzauberer fuers Entzaubern: anzeigen, eintragen, entfernen.
--    /fs verzauberer                    zeigt die Liste
--    /fs verzauberer add Name, Name     tragen ein (Komma trennt)
--    /fs verzauberer del Name|Nummer    entfernt
befehle["verzauberer"] = function(arg)
    arg = arg or ""
    local was, rest = arg:match("^(%S*)%s*(.-)%s*$")
    was = (was or ""):lower()

    if was == "add" or was == "neu" or was == "hinzu" or was == "+" then
        local n = ns.Wurf.VerzaubererHinzufuegen(rest)
        sag(string.format(L["%d ergänzt"], n))
    elseif was == "del" or was == "weg" or was == "entfernen" or was == "-" then
        local name = ns.Wurf.VerzaubererEntfernen(rest)
        sag(name and string.format(L["Verzauberer entfernt: %s."], name) or (ROT .. string.format(L["Nicht gefunden: %s"], rest) .. "|r"))
    end

    local liste = ns.Wurf.Verzauberer()
    if #liste == 0 then
        sag(GRAU .. L["Noch keine Verzauberer. |cffffff78/fs verzauberer add Name|r trägt einen ein."] .. "|r")
        return
    end
    sag(L["Verzauberer:"])
    local gruppe = (IsInGroup and IsInGroup()) and ns.Rolle.Namen() or {}
    for i, n in ipairs(liste) do
        local da = false
        for _, g in ipairs(gruppe) do
            if Kern.GleicherSpieler(g, n) then da = true break end
        end
        print(string.format("  %d. %s  %s%s|r", i, n, da and GRUEN or GRAU, da and L["in der Gruppe"] or L["nicht in der Gruppe"]))
    end
end
befehle["enchanters"] = befehle["verzauberer"]

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
            sag(GRUEN .. string.format(L["Rückgabe vermerkt: %s von %s. Der Punkt wird abgezogen, sobald das Item neu vergeben ist."], Quelle.Gegenstandstext(e.eintrag), e.name) .. "|r")
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

--- ⭐ Zurueckgegebene Items, die noch niemand bekommen hat (Regelwerk § 1): Der Punkt bleibt, bis das Item
--  neu vergeben oder entzaubert ist. Ist es anderweitig weitergegeben worden, schliesst man es hier ab.
befehle["rueckgabe"] = function(rest)
    local liste = ns.Erfassung.OffeneRueckgaben()
    local nr = tonumber((rest or ""):match("^%s*(%d+)"))
    if not nr then
        sag(L["Zurückgegebene Items, noch nicht neu vergeben:"])
        if #liste == 0 then print(L["  Keine."]) end
        for i, x in ipairs(liste) do
            print(string.format(L["  %d: %s, vorher bei %s"], i, Quelle.Gegenstandstext(x.e), Kern.Anzeigename(x.e.awardedTo)))
        end
        if #liste > 0 then
            print(GRAU .. L["Mit /fs rueckgabe <Nr> bestätigst du: das Item ist weitergegeben, der Punkt wird abgezogen."] .. "|r")
        end
        return
    end
    local x = liste[nr]
    if not x then sag(ROT .. L["Diese Nummer gibt es nicht."] .. "|r") return end
    local ok, grund = ns.Erfassung.RueckgabeAbschliessen(x.id)
    if ok then
        sag(GRUEN .. string.format(L["Rückgabe abgeschlossen: %s – der Punkt von %s wurde abgezogen."],
            Quelle.Gegenstandstext(x.e), Kern.Anzeigename(x.e.awardedTo)) .. "|r")
        if Fenster.Sichtbar() then Fenster.Aktualisieren() end
    else
        sag(ROT .. tostring(grund) .. "|r")
    end
end
befehle["returned"] = befehle["rueckgabe"]
befehle["revert"] = befehle["rueckgaengig"]

--- ⭐ Einstellungen teilen (Konfig.lua)
befehle["anhebung"] = function(arg)
    local name = tostring(arg or ""):match("^%s*(.-)%s*$")
    if name == "" then
        sag(L["Anhebung: |cffffff78/fs anhebung <Name>|r setzt den Spieler auf den Niedrigsten der anderen Kaderspieler im Raid plus 2 (nur Raid- oder Gildenleitung)."])
        return
    end
    local id, ziel, diff = ns.Anwesenheit.AnhebungSetzen(name)
    if not id then sag(ROT .. tostring(ziel) .. "|r") return end
    sag(string.format(L["|cff55ff55%s|r angehoben: +%.1f auf %.1f."], name, diff, ziel))
    if Fenster.Sichtbar() then Fenster.Aktualisieren() end
end
befehle["raise"] = befehle["anhebung"]

--- Einladen per Flüstern: `/fs einladewort` zeigt, `an`/`aus` schaltet, ein Wort setzt es und schaltet ein.
befehle["einladewort"] = function(arg)
    local A = ns.Anwesenheit
    local was = tostring(arg or ""):match("^%s*(.-)%s*$")
    local kl = was:lower()
    if kl == "an" or kl == "on" then
        A.EinladeAn(true)
    elseif kl == "aus" or kl == "off" then
        A.EinladeAn(false)
    elseif was ~= "" then
        local ok, grund = A.EinladeWortSetzen(was)
        if not ok then sag(ROT .. tostring(grund) .. "|r") return end
        A.EinladeAn(true)
    end
    local wort, an = A.EinladeWort()
    sag(string.format(L["Einladen per Flüstern ist %s, Stichwort „%s“. Wer dir genau dieses Wort flüstert, wird in deine Gruppe eingeladen."],
        an and (GRUEN .. L["an"] .. "|r") or (GRAU .. L["aus"] .. "|r"), wort))
    if ns.Einstellungen and ns.Einstellungen.Aktualisieren then pcall(ns.Einstellungen.Aktualisieren) end
end
befehle["invitekeyword"] = befehle["einladewort"]

befehle["konfig"] = function(arg)
    local was = (arg or ""):lower():match("^(%S*)") or ""
    if was == "senden" or was == "send" then
        local n, grund = ns.Konfig.Senden()
        if not n then sag(ROT .. tostring(grund) .. "|r") return end
        sag(string.format(L["Einstellungen an die Gilde gesendet (%d Nachrichten)."], n))
        return
    elseif was == "nachfragen" or was == "holen" or was == "get" then
        ns.Konfig.Anfragen("GUILD")
        sag(L["Angefragt – hat jemand neuere Einstellungen, kommen sie gleich."])
        return
    elseif was == "zurueck" or was == "zurück" or was == "undo" then
        local ok, grund = ns.Konfig.Zurueck()
        sag(ok and (GRUEN .. L["Frühere Einstellungen wiederhergestellt."] .. "|r") or (ROT .. tostring(grund) .. "|r"))
        return
    end
    sag(L["Einstellungen teilen:"])
    for _, z in ipairs(ns.Konfig.Status()) do print("  " .. z) end
end
befehle["config"] = befehle["konfig"]

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

--- Die Wuerfelbereiche: anzeigen und aendern.
--    /fs bereiche                 zeigt die Bereiche
--    /fs bereiche haupt 1 100     Bereich fuer Hauptbedarf
--    /fs bereiche zweit 1 99      Bereich fuer Zweitbedarf (OS)
befehle["bereiche"] = function(arg)
    local was, a, z = (arg or ""):lower():match("^(%S*)%s*(%d*)%s*(%d*)")
    was = was or ""

    local function eigene()
        local B = ns.Erfassung.Bereiche()
        sag(string.format(L["Bei Fairshare gelten: Hauptbedarf %d-%d, Zweitbedarf %d-%d."],
            B.haupt[1], B.haupt[2], B.zweit[1], B.zweit[2]))
    end

    if was == "haupt" or was == "main" or was == "zweit" or was == "os" then
        local ok, grund = ns.Erfassung.BereichSetzen((was == "haupt" or was == "main") and "haupt" or "zweit", a, z)
        if not ok then sag(ROT .. tostring(grund) .. "|r") return end
        eigene()
        return
    end

    eigene()
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
