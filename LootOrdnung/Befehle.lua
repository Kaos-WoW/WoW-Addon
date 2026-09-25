--[[----------------------------------------------------------------------
    Befehle.lua  —  Slash-Befehle

    Einzige Datei, die bisher WoW-API anfasst. Kern, Notiz und Tests
    bleiben frei davon, damit sie auch ohne Client laufen.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local PRAEFIX = "|cff1B6B57Loot-Ordnung|r: "

local function sag(text)
    print(PRAEFIX .. text)
end

local function hilfe()
    sag("Befehle:")
    print("  |cffffff78/lo fenster|r– UI-Fenster öffnen (Buchen per Klick)")
    print("  |cffffff78/lo test|r   – Selbsttests des Rechenkerns")
    print("  |cffffff78/lo rechte|r – prüfen, ob ich Notizen schreiben darf")
    print("  |cffffff78/lo notiz|r   – meine eigene Offiziersnotiz anzeigen")
    print("  |cffffff78/lo liste|r   – alle Konten nach Prio")
    print("  |cffffff78/lo historie|r – wer über Wochen wie viel bekommen hat (aus Gargul)")
    print("  |cff8E9A94              demo|r – Beispieldaten zur Ansicht, nichts wird gespeichert")
    print("  |cffffff78/lo vergaben|r – laufendes Register dieser Sitzung")
    print("  |cffffff78/lo abgleich|r – Register mit den anderen Raidleitern abgleichen")
    print("  |cffffff78/lo fremd|r   – wer hat noch Fremdinhalt in der Notiz")
    print("  |cffffff78/lo sichern|r – alle Notizen sichern, bevor geschrieben wird")
    print("  |cffffff78/lo leeren|r  – fremde Notizen leeren (zeigt erst an)")
    print("  |cffffff78/lo zurueck|r – gesicherte Notizen wiederherstellen")
    print("  |cffffff78/lo raenge|r  – Ränge anzeigen und auswählen")
    print("  |cffffff78/lo rang N|r  – Rang N ein-/ausschalten (mehrere möglich)")
    print("  |cffffff78/lo start|r   – Konten anlegen (zeigt erst an)")
    print("  |cffffff78/lo nullen|r  – alle Konten auf Anfang zurücksetzen (zeigt erst an)")
    print("  |cffffff78/lo buchen|r  – Testbuchung auf das eigene Konto")
    print("|cff1B6B57Raidabend:|r")
    print("  |cffffff78/lo boss|r    – Bosskampf buchen (alle Anwesenden)")
    print("  |cffffff78/lo abend|r   – Stand; |cffffff78jetzt|r schreibt, |cffffff78neu|r verwirft")
    print("  |cff8E9A94              nachtragen|r – übersprungene nachbuchen, |cff8E9A94zwingend|r – Sperre aus")
    print("  |cffffff78/lo auto|r    – Bosskills automatisch erkennen")
    print("  |cffffff78/lo wer|r     – wer zählt gerade als anwesend (Diagnose)")
    print("  |cffffff78/lo bausteine|r – welche Dateien geladen sind (Diagnose)")
end

--- Eigenen Roster-Eintrag suchen.
--  ⚠️ NIE über den Index adressieren — der verschiebt sich, sobald
--  jemand online geht. Immer über den Namen suchen und die GUID nehmen.
local function meinEintrag()
    local ich = UnitName("player")
    for _, e in ipairs(ns.Gilde.Lesen()) do
        if e.kurz == ich or e.name:match("^[^%-]+") == ich then
            return e.name, e.notiz, e.guid
        end
    end
end

local befehle = {}

befehle["test"] = function()
    if not ns.Tests then
        sag("|cffff5555Tests.lua ist nicht geladen.|r")
        return
    end
    local gut, schlecht = ns.Tests.Alle()
    if schlecht == 0 then
        sag(string.format("|cff55ff55Alle %d Prüfungen bestanden.|r", gut))
    else
        sag(string.format("|cffff5555%d von %d Prüfungen fehlgeschlagen.|r",
            schlecht, gut + schlecht))
    end
end

befehle["rechte"] = function()
    local G = C_GuildInfo
    if not G then
        sag("|cffff5555C_GuildInfo fehlt in diesem Client.|r")
        return
    end
    if not IsInGuild() then
        sag("Du bist in keiner Gilde.")
        return
    end
    sag(string.format("sehen: %s   schreiben: %s",
        tostring(G.CanViewOfficerNote and G.CanViewOfficerNote()),
        tostring(G.CanEditOfficerNote and G.CanEditOfficerNote())))
    if G.CanEditOfficerNote and not G.CanEditOfficerNote() then
        sag("|cffffff78Ohne Schreibrecht kann dieser Charakter keine Konten führen.|r")
    end
end

befehle["notiz"] = function()
    if not IsInGuild() then
        sag("Du bist in keiner Gilde.")
        return
    end
    ns.Gilde.RosterAnfordern()

    local name, notiz, guid = meinEintrag()
    if not name then
        sag("Eigenen Eintrag nicht gefunden – Gildenliste noch nicht geladen?")
        return
    end
    sag(string.format("%s  |cff8E9A94(%s)|r", name, tostring(guid)))
    print("  Offiziersnotiz: |cffffff78" .. tostring(notiz) .. "|r")

    local konto, grund = ns.Notiz.Lesen(notiz)
    if konto then
        print(string.format("  Einsatz %d · Rüstwert %d · Woche %d · Deckel %d · Stücke %d",
            konto.einsatz, konto.ruestwert, konto.woche, konto.deckel, konto.gegenstaende))
        print(string.format("  Prio: |cff55ff55%.2f|r", ns.Kern.Prio(konto)))
    else
        print("  Kein Konto hinterlegt (" .. tostring(grund) .. ")")
    end
end

--- Aktuelle fortlaufende Wochennummer.
local function jetztWoche()
    return ns.Kern.WocheAus(time())
end

befehle["liste"] = function()
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end
    ns.Gilde.RosterAnfordern()

    local woche = jetztWoche()
    local eintraege = ns.Gilde.Lesen()
    local mit = {}
    for _, e in ipairs(eintraege) do
        if e.konto then
            ns.Kern.VerfallNachholen(e.konto, woche)
            mit[#mit + 1] = e
        end
    end

    if #mit == 0 then
        sag("Noch kein Konto hinterlegt – " .. #eintraege .. " Mitglieder gelesen.")
        return
    end

    table.sort(mit, function(a, b)
        return ns.Kern.Prio(a.konto) > ns.Kern.Prio(b.konto)
    end)

    sag(string.format("%d Konten, Woche %d:", #mit, woche))
    for i, e in ipairs(mit) do
        print(string.format("  %2d. |cffffff78%-14s|r Prio |cff55ff55%5.2f|r   E %-6d R %-6d Stücke %d",
            i, e.kurz, ns.Kern.Prio(e.konto),
            e.konto.einsatz, e.konto.ruestwert, e.konto.gegenstaende))
    end
end

befehle["fremd"] = function()
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end
    ns.Gilde.RosterAnfordern()

    local _, fremd = ns.Gilde.Lesen()
    if #fremd == 0 then
        sag("|cff55ff55Keine fremden Einträge – das Feld gehört dem System.|r")
        return
    end
    sag(string.format("|cffffff78%d Mitglieder haben noch eigene Einträge:|r", #fremd))
    for _, e in ipairs(fremd) do
        print(string.format("  %-14s |cff8E9A94%s|r", e.kurz, e.notiz))
    end
    print("  |cff8E9A94Vor dem ersten Schreiben ansagen oder /lo sichern nutzen.|r")
end

befehle["sichern"] = function()
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end
    ns.Gilde.RosterAnfordern()

    local neu, zeit, anzahl = ns.Gilde.Sichern()
    if neu then
        sag(string.format("|cff55ff55%d Notizen gesichert.|r", anzahl or 0))
    else
        sag("Sicherung besteht bereits vom " .. date("%d.%m.%Y %H:%M", zeit) .. ".")
    end
end


befehle["leeren"] = function(arg)
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end
    ns.Gilde.RosterAnfordern()

    local wirklich = (arg == "jetzt")
    local fremd, grund = ns.Gilde.FremdeLeeren(wirklich)

    if not fremd then
        sag("|cffff5555" .. tostring(grund) .. "|r")
        return
    end
    if #fremd == 0 then
        sag("|cff55ff55Nichts zu leeren – keine fremden Einträge.|r")
        return
    end

    if wirklich then
        sag(string.format("|cff55ff55%d Notizen werden geleert.|r", #fremd))
        print("  |cff8E9A94Gesichert. Mit /lo zurueck wiederherstellbar.|r")
    else
        sag(string.format("|cffffff78%d Notizen würden geleert:|r", #fremd))
        for _, e in ipairs(fremd) do
            print(string.format("  %-14s |cff8E9A94%s|r", e.kurz, e.notiz))
        end
        print("  |cffff5555Zum Ausführen: /lo leeren jetzt|r")
        print("  |cff8E9A94Vorher wird automatisch gesichert.|r")
    end
end

befehle["zurueck"] = function()
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end
    ns.Gilde.RosterAnfordern()

    local n, grund = ns.Gilde.Wiederherstellen()
    if not n then
        sag("|cffff5555" .. tostring(grund) .. "|r")
        return
    end
    if n == 0 then
        sag("Nichts wiederherzustellen – alles steht schon so da.")
    else
        sag(string.format("|cff55ff55%d Notizen werden wiederhergestellt.|r", n))
    end
end
befehle["zurück"] = befehle["zurueck"]

befehle["raenge"] = function()
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end
    ns.Gilde.RosterAnfordern()

    local liste = ns.Gilde.Rangliste()
    local gewaehlt, teilnehmer = 0, 0
    sag("Gildenränge – |cff55ff55[x]|r nimmt am System teil:")
    for _, r in ipairs(liste) do
        local kasten = r.aktiv and "|cff55ff55[x]|r" or "|cff8E9A94[ ]|r"
        print(string.format("  %s |cffffff78%2d|r  %-22s %3d Mitglieder",
            kasten, r.index, tostring(r.name), r.anzahl))
        if r.aktiv then
            gewaehlt = gewaehlt + 1
            teilnehmer = teilnehmer + r.anzahl
        end
    end

    if gewaehlt == 0 then
        print("  |cffff5555Noch kein Rang gewählt – /lo rang <index> schaltet einen ein.|r")
    else
        print(string.format("  |cff8E9A94%d Ränge gewählt, %d Mitglieder. Umschalten: /lo rang <index>|r",
            gewaehlt, teilnehmer))
    end
end

befehle["rang"] = function(arg)
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end

    local indizes = {}
    for zahl in (arg or ""):gmatch("%d+") do
        indizes[#indizes + 1] = tonumber(zahl)
    end
    if #indizes == 0 then
        sag("Welcher Rang? Beispiel: |cffffff78/lo rang 2|r oder |cffffff78/lo rang 1 2 4|r")
        return
    end

    ns.Gilde.RosterAnfordern()
    local namen = {}
    for _, r in ipairs(ns.Gilde.Rangliste()) do namen[r.index] = r.name end

    for _, i in ipairs(indizes) do
        local an = ns.Gilde.RangUmschalten(i)
        sag(string.format("Rang %d (%s): %s", i, tostring(namen[i] or "?"),
            an and "|cff55ff55nimmt teil|r" or "|cff8E9A94außen vor|r"))
    end
end

--- Trennt Zahl und Schlüsselwort aus dem Argument: "3 jetzt" -> 3, true
local function argZahlJetzt(arg)
    local zahl = tonumber((arg or ""):match("%d+"))
    local jetzt = (arg or ""):find("jetzt") ~= nil
    return zahl, jetzt
end

befehle["start"] = function(arg)
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end
    ns.Gilde.RosterAnfordern()

    if ns.Gilde.AnzahlGewaehlt() == 0 then
        sag("|cffff5555Kein Rang ausgewählt.|r Erst |cffffff78/lo raenge|r ansehen, dann |cffffff78/lo rang <index>|r.")
        return
    end

    local _, wirklich = argZahlJetzt(arg)
    local woche = jetztWoche()
    local offen = {}

    for _, e in ipairs(ns.Gilde.Teilnehmer()) do
        if not e.konto then
            offen[#offen + 1] = e
        end
    end

    if #offen == 0 then
        sag("|cff55ff55Alle betroffenen Mitglieder haben bereits ein Konto.|r")
        return
    end

    if not wirklich then
        sag(string.format("|cffffff78%d Mitglieder bekämen ein Konto (Woche %d):|r", #offen, woche))
        for i, e in ipairs(offen) do
            if i <= 12 then
                print(string.format("  %-14s |cff8E9A94Rang %d, %s|r", e.kurz, e.rangIndex or -1, tostring(e.rang)))
            end
        end
        if #offen > 12 then print("  |cff8E9A94… und " .. (#offen - 12) .. " weitere|r") end
        print("  |cffff5555Zum Ausführen: /lo start jetzt|r")
        return
    end

    local auftraege = {}
    for _, e in ipairs(offen) do
        auftraege[#auftraege + 1] = { guid = e.guid, konto = ns.Kern.NeuesKonto(woche) }
    end
    local n, fehler = ns.Gilde.SchreibenViele(auftraege, function()
        sag("|cff55ff55Fertig. /lo liste zeigt den Stand.|r")
    end)
    sag(string.format("%d Konten werden angelegt…", n))
    if #fehler > 0 then
        print("  |cffff5555" .. #fehler .. " abgelehnt: " .. tostring(fehler[1]) .. "|r")
    end
end

--- Setzt alle Konten auf den Anfangswert zurueck.
--
--  Fuer den Uebergang von Erprobung auf Echtbetrieb: Zahlen aus
--  Testraids sollen nicht in die erste echte Woche hineinragen.
--
--  ⚠️ Das ist NICHT /lo zurueck. Die Sicherung der urspruenglichen
--  Notizen bleibt unangetastet — /lo zurueck stellt weiterhin den Stand
--  VOR dem System her, nicht den von eben. Genullt wird nur, was das
--  System selbst geschrieben hat.
befehle["nullen"] = function(arg)
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end
    ns.Gilde.RosterAnfordern()

    local _, wirklich = argZahlJetzt(arg)
    local woche = jetztWoche()

    local betroffen = {}
    for _, e in ipairs(ns.Gilde.Teilnehmer()) do
        if e.konto then betroffen[#betroffen + 1] = e end
    end

    if #betroffen == 0 then
        sag("Keine Konten vorhanden – |cffffff78/lo start|r legt welche an.")
        return
    end

    if not wirklich then
        sag(string.format("|cffffff78%d Konten würden auf Null gesetzt (Woche %d):|r",
            #betroffen, woche))
        for i, e in ipairs(betroffen) do
            if i <= 10 then
                print(string.format("  %-14s |cff8E9A94jetzt E %d, R %d, Stücke %d|r",
                    e.kurz,
                    math.floor((e.konto.einsatz or 0) + 0.5),
                    math.floor((e.konto.ruestwert or 0) + 0.5),
                    math.floor(e.konto.gegenstaende or 0)))
            end
        end
        if #betroffen > 10 then
            print("  |cff8E9A94… und " .. (#betroffen - 10) .. " weitere|r")
        end
        print("  |cffff5555Zum Ausführen: /lo nullen jetzt|r")
        print("  |cff8E9A94Setzt Einsatz, Rüstwert, Stücke und den Buchungsstempel zurück.|r")
        return
    end

    local auftraege = {}
    for _, e in ipairs(betroffen) do
        auftraege[#auftraege + 1] = { guid = e.guid, konto = ns.Kern.NeuesKonto(woche) }
    end

    -- Ein stehengebliebener Abend wuerde die frischen Konten sofort
    -- wieder bebuchen.
    ns.Raid.AbendVerwerfen()

    local n = ns.Gilde.SchreibenViele(auftraege, function()
        sag("|cff55ff55Alle Konten stehen wieder am Anfang.|r")
    end)
    sag(string.format("%d Konten werden genullt…", n))
end

befehle["buchen"] = function(arg)
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end
    ns.Gilde.RosterAnfordern()

    local punkte = tonumber((arg or ""):match("%-?%d+")) or ns.Kern.Abendsatz(8)
    local name, notiz, guid = meinEintrag()
    if not name then sag("Eigenen Eintrag nicht gefunden.") return end

    local woche = jetztWoche()
    local konto = ns.Notiz.Lesen(notiz) or ns.Kern.NeuesKonto(woche)
    ns.Kern.VerfallNachholen(konto, woche)

    local vorher = ns.Kern.Prio(konto)
    konto.einsatz = konto.einsatz + punkte

    local ok, grund = ns.Gilde.Schreiben(guid, konto)
    if not ok then
        sag("|cffff5555Schreiben abgelehnt: " .. tostring(grund) .. "|r")
        return
    end
    sag(string.format("%+d Einsatz gebucht. Prio %.2f → |cff55ff55%.2f|r",
        punkte, vorher, ns.Kern.Prio(konto)))
    print("  |cff8E9A94" .. tostring(ns.Notiz.Schreiben(konto)) .. "|r")
end

befehle["boss"] = function(arg)
    local name = (arg ~= "" and arg) or nil
    if not name then
        sag("Welcher Boss? |cffffff78/lo boss Gurtogg|r")
        print("  |cff8E9A94Der Name verhindert, dass derselbe Kampf doppelt zählt.|r")
        return
    end
    ns.Raid.Melden(ns.Raid.BossBuchen(name, nil, true))
    print("  |cff8E9A94/lo abend zeigt den Stand, /lo abend neu verwirft alles.|r")
end

--- Diagnose: was liefert GetRaidRosterInfo wirklich?
--  Gebaut, weil der Zonenfilter auf einer ungepruefte Annahme sitzt —
--  welches Feld die Zone ist und wie sie geschrieben wird.
befehle["fenster"] = function()
    if ns.Fenster then
        ns.Fenster.Umschalten()
    else
        sag("|cffff5555Fenster.lua ist nicht geladen.|r")
    end
end
befehle["gui"] = befehle["fenster"]

befehle["historie"] = function(arg)
    -- Beispieldaten: leben nur im Speicher, landen nirgends.
    local beispiel, rest = nil, arg
    local ohneDemo = arg:match("^demo%s*(.*)$")
    if ohneDemo then
        beispiel = ns.Historie.Beispiel()
        rest = ohneDemo
        sag("|cffffff78Beispieldaten|r – nichts davon wird gespeichert.")
    end

    local wochen = tonumber(rest)
    local name = (not wochen) and rest ~= "" and rest or nil

    -- Einzelner Spieler
    if name then
        local liste, grund = ns.Historie.Spieler(name, nil, beispiel)
        if not liste then sag("|cffff5555" .. tostring(grund) .. "|r") return end
        if #liste == 0 then
            sag(string.format("Für |cffffff78%s|r ist keine Vergabe verzeichnet.", name))
            return
        end
        sag(string.format("%s: |cff55ff55%d Vergaben|r", name, #liste))
        for i, e in ipairs(liste) do
            if i <= 25 then
                print(string.format("  %s  %s%s", date("%d.%m.%y", e.zeit),
                    tostring(e.stueck), e.zweit and "  |cff8E9A94Zweitbedarf|r" or ""))
            end
        end
        if #liste > 25 then print("  |cff8E9A94… und " .. (#liste - 25) .. " weitere|r") end
        return
    end

    local liste, gesamt, aeltester = ns.Historie.Bilanz(wochen, beispiel)
    if not liste then sag("|cffff5555" .. tostring(gesamt) .. "|r") return end
    if #liste == 0 then
        sag("Keine Vergaben im Zeitraum.")
        return
    end

    local tage = ns.Historie.Raidtage(wochen, beispiel)
    sag(string.format("%s: |cff55ff55%d Vergaben|r an %d Spieler, %d Raidtage",
        wochen and wochen > 0 and (wochen .. " Wochen") or "Gesamte Historie",
        gesamt, #liste, tage))
    if aeltester then
        print(string.format("  |cff8E9A94Älteste Aufzeichnung: %s|r", date("%d.%m.%Y", aeltester)))
    end

    for i, z in ipairs(liste) do
        if i <= 30 then
            local seit = ""
            if z.letzte > 0 then
                local d = math.floor((time() - z.letzte) / 86400)
                seit = string.format("  |cff8E9A94zuletzt vor %d Tagen|r", d)
            end
            print(string.format("  %-14s |cffffff78%2d|r Haupt%s%s",
                z.name, z.haupt,
                z.zweit > 0 and string.format("  |cff8E9A94%d Zweit|r", z.zweit) or "        ",
                seit))
        end
    end
    if #liste > 30 then print("  |cff8E9A94… und " .. (#liste - 30) .. " weitere|r") end
    print("  |cff8E9A94/lo historie 4 begrenzt auf 4 Wochen, /lo historie <Name> zeigt einen Spieler.|r")
    if beispiel then print("  |cff8E9A94/lo historie demo Xalessa zeigt einen Beispielspieler.|r") end
end

befehle["vergaben"] = function()
    local liste = ns.Vergabe.Bilanz()
    local gesamt, weg = ns.Vergabe.Zahlen()

    if gesamt == 0 then
        sag("Noch keine Vergabe erfasst.")
        if not ns.Vergabe.gargulAngebunden then
            local _, grund = ns.Vergabe.GargulAnbinden()
            if grund then
                print("  |cffffff78" .. tostring(grund) .. "|r – ohne Gargul trägt nur /lo abgleich etwas ein.")
            end
        end
        return
    end

    sag(string.format("%d Vergaben auf %d Spieler%s:", gesamt, #liste,
        weg > 0 and string.format(" |cff8E9A94(%d zurückgenommen)|r", weg) or ""))

    local ungeklaert = 0
    for i, z in ipairs(liste) do
        if i <= 20 then
            print(string.format("  %-14s %2d Stück   Rüstwert |cffffff78%d|r%s",
                z.kurz, z.anzahl, math.floor(z.ruestwert + 0.5),
                z.offen > 0 and string.format("  |cffff5555+%d unbekannt|r", z.offen) or ""))
        end
        ungeklaert = ungeklaert + z.offen
    end
    if #liste > 20 then print("  |cff8E9A94… und " .. (#liste - 20) .. " weitere|r") end

    if ungeklaert > 0 then
        print("  |cff8E9A94Unbekannt heißt: der Client kennt den Gegenstand noch nicht.|r")
        print("  |cff8E9A94Nach einem Blick ins Auktionshaus oder einem /reload steht er da.|r")
    end
end

befehle["abgleich"] = function(arg)
    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end

    if ns.Gilde.AnzahlGewaehlt() == 0 then
        sag("|cffff5555Kein Rang ausgewählt.|r Abgeglichen wird nur mit gewählten Rängen – |cffffff78/lo raenge|r.")
        return
    end

    if arg == "senden" then
        local n = ns.Abgleich.Senden()
        sag(string.format("Register verschickt |cff8E9A94(%d Nachrichten).|r", n))
        return
    end

    ns.Abgleich.Anfordern()
    sag("Abgleich angefordert – |cff8E9A94Antworten laufen die nächsten Sekunden ein.|r")
    print("  |cff8E9A94Es antworten nur Spieler mit Addon auf einem gewählten Rang.|r")
end

befehle["bausteine"] = function()
    sag("Geladene Bausteine:")
    for _, name in ipairs({"Kern", "Notiz", "Gilde", "Raid", "Tests", "Fenster"}) do
        local da = ns[name] ~= nil
        print(string.format("  %-8s %s", name,
            da and "|cff55ff55da|r" or "|cffff5555FEHLT – Datei mit Fehler abgebrochen|r"))
    end
end

befehle["wer"] = function()
    local _, typ = IsInInstance()
    local hier = GetRealZoneText()
    sag(string.format("Eigene Zone: |cffffff78%s|r (Instanztyp: %s)",
        tostring(hier), tostring(typ)))

    if not (IsInRaid and IsInRaid()) then
        print("  |cff8E9A94Kein Schlachtzug – nichts zu filtern.|r")
        return
    end

    local n = GetNumGroupMembers()
    local drin, raus = 0, 0
    for i = 1, n do
        local name, _, _, _, _, _, zone, online = GetRaidRosterInfo(i)
        if name then
            local ok = ns.Kern.IstDabei(online, zone, (typ == "raid" or typ == "party") and hier or nil)
            if ok then drin = drin + 1 else raus = raus + 1 end
            if i <= 12 or not ok then
                print(string.format("  %-14s online=%-5s zone=|cffffff78%s|r  %s",
                    name, tostring(online), tostring(zone),
                    ok and "|cff55ff55zählt|r" or "|cffff5555raus|r"))
            end
        end
    end
    sag(string.format("%d von %d zählen. |cff8E9A94Stimmt das nicht, ist das Zonenfeld schuld.|r",
        drin, n))
end

befehle["abend"] = function(arg)
    local abend = ns.Raid.Abend()

    if arg == "neu" then
        ns.Raid.AbendVerwerfen()
        sag("|cffffff78Abend verworfen.|r")
        return
    end

    if abend.bosse == 0 then
        sag("Noch kein Bosskampf gebucht. |cffffff78/lo boss|r oder |cffffff78/lo auto|r.")
        return
    end

    local auswertung = ns.Raid.Auswertung()

    -- Bosse ohne Teilnehmer: Der Abend ist Schrott, meist ein Rest aus
    -- einer aelteren Fassung. Lieber sagen als stumm nichts buchen.
    if #auswertung == 0 then
        sag(string.format("|cffff5555%d Bosse, aber kein Teilnehmer erfasst.|r", abend.bosse))
        print("  |cff8E9A94Der Abend ist unbrauchbar – /lo abend neu, dann /lo boss von Hand.|r")
        return
    end

    if arg ~= "jetzt" and arg ~= "zwingend" and arg ~= "nachtragen" then
        sag(string.format("Abend seit %s: |cff55ff55%d Bosse|r, %d Spieler",
            date("%H:%M", abend.start), abend.bosse, #auswertung))
        print("  |cff8E9A94" .. table.concat(abend.protokoll, ", ") .. "|r")
        for i, a in ipairs(auswertung) do
            if i <= 15 then
                print(string.format("  %-14s %d/%d Bosse%s  → |cff55ff55+%d|r",
                    a.kurz, a.bosse, abend.bosse,
                    a.vollDabei and " |cff55ff55voll|r" or "      ", a.einsatz))
            end
        end
        if #auswertung > 15 then print("  |cff8E9A94… und " .. (#auswertung - 15) .. " weitere|r") end
        print("  |cffff5555Zum Schreiben: /lo abend jetzt|r")
        return
    end

    if not IsInGuild() then sag("Du bist in keiner Gilde.") return end
    ns.Gilde.RosterAnfordern()

    local n, fehlend, spaeter = ns.Raid.Buchen(function()
        sag("|cff55ff55Abend geschrieben. /lo liste zeigt den Stand.|r")
    end, arg ~= "jetzt" and arg or nil)

    -- Mehrere Raidleiter mit Addon. Zwei Faelle, die auseinandergehalten
    -- werden muessen: ALLE gesperrt heisst, jemand hat denselben Abend
    -- schon geschrieben. EINZELNE gesperrt heisst meist, die waren vorher
    -- in der anderen Gruppe — und gehören nachgetragen.
    if n == 0 and #spaeter > 0 then
        sag(string.format("|cffffff78Nichts gebucht – alle %d sind schon bebucht.|r", #spaeter))
        print("  |cff8E9A94Sehr wahrscheinlich hat ein anderer Raidleiter denselben Abend geschrieben.|r")
        print("  |cff8E9A94Stimmt das nicht: /lo abend zwingend|r")
        return
    end

    sag(string.format("%d Konten werden gebucht…", n))
    if #spaeter > 0 then
        print(string.format("  |cffffff78%d übersprungen – heute schon bebucht: %s|r",
            #spaeter, table.concat(spaeter, ", ")))
        print("  |cff8E9A94Waren die vorher in der anderen Gruppe? Dann: /lo abend nachtragen|r")
    end
    if #fehlend > 0 then
        print("  |cffffff78Ohne Konto übersprungen: " .. table.concat(fehlend, ", ") .. "|r")
        print("  |cff8E9A94Das sind Gäste oder Ränge, die nicht teilnehmen.|r")
    end

    -- Der Abend bleibt stehen, solange ein Nachtrag offen ist.
    if #spaeter > 0 then
        print("  |cff8E9A94Der Abend bleibt erhalten – /lo abend neu wirft ihn weg.|r")
        return
    end
    ns.Raid.AbendVerwerfen()
end

befehle["auto"] = function()
    local an = ns.Raid.AutomatikUmschalten()
    if not an then
        sag("|cffffff78Automatik aus – Bosse per /lo boss buchen.|r")
        return
    end

    sag("|cff55ff55Automatik an.|r")
    local erlaubt, grund, gesamt = ns.Raid.IstGildenraid()
    if erlaubt then
        print(string.format("  |cff55ff55Hier wird gebucht: %d von %d aus der Gilde.|r", grund, gesamt))
    else
        print("  |cff8E9A94Hier würde nicht gebucht: " .. tostring(grund) .. ".|r")
        print("  |cff8E9A94Gebucht wird nur in einer Raidinstanz mit Gildenmehrheit.|r")
    end
    print("  |cff8E9A94Mehrere Versuche am selben Boss zählen einmal. Von Hand: /lo boss|r")
end

-- =====================================================================
--  Begruessung beim Laden
-- =====================================================================

local function version()
    local hole = (rawget(_G, "C_AddOns") and C_AddOns.GetAddOnMetadata)
                 or rawget(_G, "GetAddOnMetadata")
    if hole then
        local ok, v = pcall(hole, ADDON, "Version")
        if ok and v then return v end
    end
    return "?"
end

local function begruessung()
    local teile = {}

    -- Automatik und laufender Abend
    if ns.Raid.AutomatikAn() then
        teile[#teile + 1] = "|cff55ff55Automatik an|r"
    else
        teile[#teile + 1] = "|cff8E9A94Automatik aus|r"
    end

    local abend = LootOrdnungDB and LootOrdnungDB.abend
    if abend and abend.bosse and abend.bosse > 0 then
        teile[#teile + 1] = string.format("|cffffff78Abend läuft: %d Bosse seit %s|r",
            abend.bosse, date("%H:%M", abend.start))
    end

    sag(string.format("%s geladen – %s", version(), table.concat(teile, " · ")))

    -- Warnungen nur, wenn sie zutreffen
    if not IsInGuild() then return end

    if ns.Gilde.DarfSchreiben() == false then
        print("  |cffff5555Kein Schreibrecht für Offiziersnotizen – Konten lassen sich nicht führen.|r")
    end
    if ns.Gilde.AnzahlGewaehlt() == 0 then
        print("  |cffffff78Noch kein Rang gewählt – /lo raenge|r")
    end

    local offen = 0
    for _, e in ipairs((ns.Gilde.Lesen())) do
        if ns.Gilde.RangAktiv(e.rangIndex) and not e.konto then offen = offen + 1 end
    end
    if offen > 0 then
        print(string.format("  |cffffff78%d Mitglieder ohne Konto – /lo start|r", offen))
    end
end

local begruessungsRahmen = CreateFrame("Frame")
begruessungsRahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
begruessungsRahmen:SetScript("OnEvent", function(selbst)
    -- ⚠️ PLAYER_ENTERING_WORLD feuert auch bei jedem Instanzwechsel.
    -- Nur einmal je Sitzung gruessen, sonst spammt es beim Raiden.
    selbst:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(4, function()
        local ok, fehler = pcall(begruessung)
        if not ok then
            sag("|cffff5555Fehler beim Start: " .. tostring(fehler) .. "|r")
        end
    end)
end)

SLASH_LOOTORDNUNG1 = "/lo"
SLASH_LOOTORDNUNG2 = "/lootordnung"
--- ⭐ **Kein Befehl darf still scheitern.**
--  WoW verschluckt Laufzeitfehler in Addons, solange scriptErrors aus ist
--  — und das ist die Voreinstellung. Der Befehl tut dann scheinbar
--  ueberhaupt nichts, und man sucht an der falschen Stelle. Mit pcall
--  landet stattdessen die Fehlermeldung im Chat.
SlashCmdList["LOOTORDNUNG"] = function(eingabe)
    local wort, rest = (eingabe or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local fn = befehle[(wort or ""):lower()]
    if not fn then hilfe() return end

    local ok, fehler = pcall(fn, (rest or ""):lower())
    if not ok then
        print(PRAEFIX .. "|cffff5555Fehler in /lo " .. tostring(wort) .. "|r")
        print("|cffff5555" .. tostring(fehler) .. "|r")
        print("|cff8E9A94Bitte diese zwei Zeilen weitergeben.|r")
    end
end

-- Beweis, dass die Datei bis zum Ende durchgelaufen ist. Faellt eine der
-- vorherigen Dateien aus, fehlt hier der Eintrag und /lo laedt gar nicht.
ns.geladen = true
