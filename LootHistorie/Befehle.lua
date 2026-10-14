--[[----------------------------------------------------------------------
    Befehle.lua  —  /lh

    ⭐ **Kein Befehl darf still scheitern.** WoW verschluckt Laufzeitfehler
    in Addons, solange scriptErrors aus ist — und das ist die
    Voreinstellung. Der Befehl tut dann scheinbar ueberhaupt nichts, und
    man sucht an der falschen Stelle. Darum laeuft jeder Unterbefehl
    ueber pcall und die Meldung landet im Chat.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Kern, Quelle, Fenster = ns.Kern, ns.Quelle, ns.Fenster

local PRAEFIX = "|cff1B6B57Loot-Historie|r: "
local GELB = "|cffffff78"
local GRAU = "|cff8E9A94"
local ROT  = "|cffff5555"
local GRUEN = "|cff55ff55"

local function sag(text) print(PRAEFIX .. text) end

local befehle = {}

local function hilfe()
    sag("Befehle:")
    print("  " .. GELB .. "/lh|r          – Fenster öffnen und schließen")
    print("  " .. GELB .. "/lh verlauf|r  – wer bekam was, wann")
    print("  " .. GELB .. "/lh demo|r     – Fenster mit Beispieldaten (nichts wird gespeichert)")
    print("  " .. GELB .. "/lh liste|r    – dieselbe Auswertung im Chat, " .. GELB .. "liste 4|r für 4 Wochen")
    print("  " .. GELB .. "/lh <Name>|r   – Einzelvergaben eines Spielers im Chat")
    print("  " .. GELB .. "/lh abgleich|r – Historien der Gruppe zusammenführen (" .. GELB .. "abgleich status|r zeigt den Stand)")
    print("  " .. GELB .. "/lh rolle|r    – wer schreibt gerade mit, und warum")
    print("  " .. GELB .. "/lh gruppe|r   – Kader und Raidgruppen (" .. GELB .. "gruppe hilfe|r)")
    print("  " .. GELB .. "/lh bereiche|r – Garguls Würfelbereiche prüfen (" .. GELB .. "bereiche setzen|r)")
    print("  " .. GELB .. "/lh auto|r     – Fenster bei Wurfbeginn automatisch öffnen (an/aus)")
    print("  " .. GELB .. "/lh import|r   – Garguls bisherige Aufzeichnungen übernehmen")
    print("  " .. GELB .. "/lh filter|r   – ab welcher Qualität und wo mitgeschrieben wird")
    print("  " .. GELB .. "/lh stand|r    – Diagnose: eigene Historie und Mitschrift")
    print("  " .. GELB .. "/lh muster|r   – Diagnose: Textvorlagen für eigene Erkennung")
    print("  " .. GELB .. "/lh test|r     – Selbsttests der Auswertung")
end

-- =====================================================================

befehle["import"] = function()
    local neu, doppelt = Quelle.GargulImport()
    if not neu then
        sag(ROT .. tostring(doppelt) .. "|r")
        return
    end
    sag(string.format("|cff55ff55%d Vergaben|r aus Gargul übernommen.", neu))
    if doppelt > 0 then
        print(string.format("  " .. GRAU .. "%d übersprungen – die hatte die Eigenerfassung schon.|r", doppelt))
    end
    print("  " .. GRAU .. "Wiederholtes Einführen ändert nichts mehr.|r")
end

befehle["filter"] = function(arg)
    local d = ns.Erfassung.Einstellungen()
    local stufe = tonumber(arg)
    if stufe and stufe >= 0 and stufe <= 5 then
        d.mindestQualitaet = stufe
    elseif arg == "raid" or arg == "instanz" or arg == "ueberall" or arg == "überall" then
        d.ort = (arg == "überall") and "ueberall" or arg
    elseif arg == "wurf" then
        d.nurGewuerfelt = not d.nurGewuerfelt
    elseif arg ~= "" then
        sag("Nutzung: " .. GELB .. "/lh filter 0-5|r (Qualität), " ..
            GELB .. "raid|instanz|überall|r (Ort) oder " .. GELB .. "wurf|r (nur Ausgewürfeltes)")
        return
    end

    local Namen = { [0]="Schlecht", [1]="Gewöhnlich", [2]="Ungewöhnlich",
                    [3]="Selten", [4]="Episch", [5]="Legendär" }
    local Orte = {
        raid     = "nur in Schlachtzugsinstanzen",
        instanz  = "in Instanzen, auch Fünfergruppen",
        ueberall = "überall",
    }
    sag(string.format("Erfasst ab |cffffff78%s|r, %s%s.",
        Namen[d.mindestQualitaet] or d.mindestQualitaet,
        Orte[d.ort] or d.ort,
        d.nurGewuerfelt and ", nur Ausgewürfeltes" or ""))
    if d.nurGewuerfelt then
        print("  " .. GRAU .. "⚠ Ohne Bedarfswurf zugeteilte Stücke fallen dabei heraus.|r")
    end
end

befehle["stand"] = function()
    local eigen = ns.Erfassung.Historie()
    local n = 0
    for _ in pairs(eigen) do n = n + 1 end
    local liste, gesamt = Kern.Bilanz(eigen, 0)
    sag(string.format("Eigene Historie: |cff55ff55%d Einträge|r, davon %d auswertbar an %d Spieler.",
        n, gesamt, #liste))

    -- Woher stammen die Eintraege?
    local Herkunft = {}
    for _, e in pairs(eigen) do
        local h = e.herkunft or (e.ausGargul and "gargul-import") or "unbekannt"
        Herkunft[h] = (Herkunft[h] or 0) + 1
    end
    local teile = {}
    for h, c in pairs(Herkunft) do teile[#teile + 1] = h .. " " .. c end
    table.sort(teile)
    print("  " .. GRAU .. "Herkunft: " .. (#teile > 0 and table.concat(teile, ", ") or "noch nichts") .. "|r")

    local kann, grund = ns.Blizzbeute.Verfuegbar()
    print(string.format("  " .. GRAU .. "Beute-Historie des Clients: %s.|r",
        kann and "nutzbar" or ("|cffff5555" .. tostring(grund) .. "|r" .. GRAU)))

    local beute, wurf = ns.Erfassung.MusterBauen()
    print(string.format("  " .. GRAU .. "Mitschreiben: %d Beutemuster, Wurfmuster %s, %d Würfe gemerkt.|r",
        beute, wurf and "da" or "FEHLT", ns.Erfassung.OffeneWuerfe()))

    local darf, warum = ns.Rolle.IchSchreibe()
    print(string.format("  Schreiber: %s %s(%s)|r",
        darf and (GRUEN .. "du schreibst mit|r") or (GELB .. "du schreibst nicht mit|r"), GRAU, tostring(warum)))

    local ok, wert = Quelle.Stand()
    if not ok then
        print("  " .. GRAU .. tostring(wert) .. " – nichts zu übernehmen.|r")
        return
    end
    print(string.format("  " .. GRAU .. "Garguls Bestand: %d Einträge – |r" .. GELB .. "/lh import|r" ..
        GRAU .. " übernimmt ihn.|r", wert))
end

--- Diagnose: welche Textvorlagen und Namens-APIs gibt es hier?
befehle["muster"] = function()
    sag("Textvorlagen für eigene Erkennung:")
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
            print(string.format("  " .. ROT .. "%s fehlt|r", name))
        end
    end

    sag("Namens-APIs (Nachnamen in Forever):")
    local NU = rawget(_G, "NameUtil")
    print("  NameUtil: " .. (NU and "|cff55ff55da|r" or ROT .. "fehlt|r"))
    if NU then
        for _, f in ipairs({ "FormatUnitNameForDisplay", "SplitPlayerNameIntoParts",
                             "GetFullNameWithoutRealm", "GetUnitFirstName" }) do
            print("    " .. f .. ": " .. (type(NU[f]) == "function" and "|cff55ff55da|r" or GRAU .. "fehlt|r"))
        end
    end

    local name, zweites = UnitName("player")
    print(string.format("  UnitName: |cffffff78%s|r  zweiter Wert: |cffffff78%s|r",
        tostring(name), tostring(zweites)))
    if GetUnitName then
        print(string.format("  GetUnitName(player, true): |cffffff78%s|r",
            tostring(GetUnitName("player", true))))
    end
end

befehle["auto"] = function()
    local an = Fenster.AutoUmschalten()
    if an then
        sag("Fenster öffnet sich automatisch, sobald ein Wurf startet.")
    else
        sag("Automatisches Öffnen aus. " .. GELB .. "/lh|r öffnet es von Hand.")
    end
end

befehle["demo"] = function()
    Fenster.Zeigen(true)
end

befehle["verlauf"] = function()
    Fenster.ZeigenAnsicht("verlauf")
end

befehle["test"] = function()
    if ns.Tests and ns.Tests.Alle then ns.Tests.Alle() else sag("Keine Tests geladen.") end
end

-- ---------------------------------------------------------------------
--  Wer schreibt mit, Abgleich
-- ---------------------------------------------------------------------

befehle["rolle"] = function()
    local darf, grund = ns.Rolle.IchSchreibe()
    sag(darf and (GRUEN .. "Du schreibst mit.|r") or (GELB .. "Du schreibst nicht mit.|r"))
    print("  " .. GRAU .. "Grund: " .. tostring(grund) .. "|r")

    local kandidaten, methode = ns.Rolle.Kandidaten()
    print("  " .. GRAU .. "Beutemethode: " .. tostring(methode) .. "|r")
    if #kandidaten == 0 then
        print("  " .. GRAU .. "Keine Kandidaten erkannt (keine Gruppe, oder niemand ist Leiter).|r")
    end
    local hat = ns.Abgleich.Bekannte()
    for i, k in ipairs(kandidaten) do
        print(string.format("  %d. %s (%s) – Addon: %s", i, tostring(k.name), tostring(k.rolle),
            k.ich and (GRUEN .. "du|r") or (hat[Kern.Schluessel(k.name) or "?"] and (GRUEN .. "ja|r") or (GRAU .. "unbekannt|r"))))
    end
end

befehle["abgleich"] = function(arg)
    if arg == "status" or arg == "stand" then
        sag("Abgleich:")
        for _, z in ipairs(ns.Abgleich.Diagnose()) do print("  " .. z) end
        return
    end
    local ok, grund = ns.Abgleich.Starten()
    if not ok then sag(ROT .. tostring(grund) .. "|r") end
end
befehle["sync"] = befehle["abgleich"]

befehle["bereiche"] = function(arg)
    if arg == "setzen" then
        local ok, grund = Quelle.GargulBereicheSetzen()
        if not ok then sag(ROT .. tostring(grund) .. "|r") return end
        sag(GRUEN .. "Bei Gargul eingestellt: MS 1-100, OS 1-50.|r")
        return
    end
    local B, grund = Quelle.GargulBereiche()
    if not B then sag(GRAU .. tostring(grund) .. "|r") return end
    sag(B.ok and (GRUEN .. "Würfelbereiche stimmen.|r") or (ROT .. "Würfelbereiche passen nicht.|r"))
    print("  " .. GRAU .. "Gargul kennt: " .. table.concat(B.bereiche, ", ") .. "|r")
    if not B.ok then
        print("  " .. GELB .. "/lh bereiche setzen|r" .. GRAU .. " stellt 1-100 (Haupt) und 1-50 (Zweit) ein.|r")
    end
end

-- ---------------------------------------------------------------------
--  Gruppen
-- ---------------------------------------------------------------------

befehle["gruppe"] = function(arg)
    local G = ns.Gruppen
    local was, rest = (arg or ""):match("^(%S*)%s*(.-)%s*$")
    was = (was or ""):lower()

    if was == "hilfe" or was == "?" then
        sag("Gruppen:")
        print("  " .. GELB .. "/lh gruppe|r                  – alle Gruppen")
        print("  " .. GELB .. "/lh gruppe neu <Name>|r       – Gruppe anlegen (Kader)")
        print("  " .. GELB .. "/lh gruppe aktiv <Name>|r     – aktive Gruppe; ohne Namen: keine")
        print("  " .. GELB .. "/lh gruppe art|r              – aktive Gruppe: Kader oder Raidgruppe")
        print("  " .. GELB .. "/lh gruppe kader A, B, C|r    – Namen zum Kader (Komma!)")
        print("  " .. GELB .. "/lh gruppe fuellen|r          – Kader aus der aktuellen Gruppe")
        print("  " .. GELB .. "/lh gruppe entfernen <Name>|r – Name aus dem Kader")
        print("  " .. GELB .. "/lh gruppe loeschen <Name>|r  – Gruppe löschen")
        return
    end

    if was == "neu" then
        local ok, grund = G.Anlegen(rest)
        sag(ok and (GRUEN .. "Gruppe „" .. rest .. "“ angelegt.|r") or (ROT .. tostring(grund) .. "|r"))
    elseif was == "aktiv" then
        local name = rest ~= "" and rest or nil
        if G.Aktivieren(name) then
            sag(name and ("Aktiv: " .. GELB .. name .. "|r") or "Keine Gruppe aktiv.")
        else
            sag(ROT .. "Die Gruppe gibt es nicht.|r")
        end
    elseif was == "art" then
        local name = G.AktivName()
        if not name then sag(ROT .. "Keine Gruppe aktiv.|r") return end
        local modus = G.ModusUmschalten(name)
        sag(name .. ": " .. GELB .. (modus == "raid" and "Raidgruppe" or "Kader") .. "|r")
    elseif was == "kader" then
        local name = G.AktivName()
        if not name then sag(ROT .. "Keine Gruppe aktiv.|r") return end
        local n = G.KaderErgaenzen(name, rest)
        sag(string.format("%d Namen ergänzt.", n or 0))
    elseif was == "fuellen" then
        local name = G.AktivName()
        if not name then sag(ROT .. "Keine Gruppe aktiv.|r") return end
        sag(string.format("Kader von %s: %d Namen aus der aktuellen Gruppe.", name, G.KaderAusGruppe(name) or 0))
    elseif was == "entfernen" then
        local name = G.AktivName()
        if not name then sag(ROT .. "Keine Gruppe aktiv.|r") return end
        sag(G.KaderEntfernen(name, rest) and "Entfernt." or (ROT .. "Den Namen gibt es nicht im Kader.|r"))
    elseif was == "loeschen" or was == "löschen" then
        sag(G.Loeschen(rest) and "Gelöscht." or (ROT .. "Die Gruppe gibt es nicht.|r"))
    else
        local Namen = G.Namen()
        if #Namen == 0 then
            sag("Noch keine Gruppe. " .. GELB .. "/lh gruppe neu 40er|r legt eine an, " ..
                GELB .. "/lh gruppe hilfe|r zeigt alles.")
            return
        end
        local aktiv = G.AktivName()
        sag("Gruppen:")
        for _, n in ipairs(Namen) do
            local g = G.Holen(n)
            print(string.format("  %s%s|r  %s%s|r", n == aktiv and GELB or "", n,
                GRAU, g.modus == "raid" and "Raidgruppe" or (#(g.kader or {}) .. " im Kader")))
        end
    end
end

-- ---------------------------------------------------------------------
--  Auswertung im Chat
-- ---------------------------------------------------------------------

befehle["liste"] = function(arg)
    local wochen = tonumber(arg) or 0
    local H, grund = Quelle.Historie()
    if not H then sag(ROT .. tostring(grund) .. "|r") return end

    local seit = Kern.Seit(time(), wochen)
    local liste, gesamt, aeltester = Kern.Bilanz(H, seit, ns.Gruppen.Pflicht(nil))

    if #liste == 0 then sag("Keine Vergabe im Zeitraum.") return end

    sag(string.format("%s: |cff55ff55%d Vergaben|r an %d Spieler, %d Raidtage",
        wochen > 0 and (wochen .. " Wochen") or "Gesamte Historie",
        gesamt, #liste, Kern.Raidtage(H, seit, Quelle.Tag)))
    if aeltester then
        print("  " .. GRAU .. "Älteste Aufzeichnung: " .. date("%d.%m.%Y", aeltester) .. "|r")
    end

    for i, z in ipairs(liste) do
        if i > 30 then
            print("  " .. GRAU .. "… und " .. (#liste - 30) .. " weitere|r")
            break
        end
        local seitText = ""
        if z.letzte > 0 then
            seitText = string.format("  " .. GRAU .. "vor %d Tagen|r",
                math.floor((time() - z.letzte) / Kern.TAG))
        end
        print(string.format("  %-14s " .. GELB .. "%2d|r Haupt%s%s", z.name, z.haupt,
            z.zweit > 0 and string.format("  " .. GRAU .. "%d Zweit|r", z.zweit) or "        ",
            seitText))
    end
end

--- Einzelner Spieler, sonst Hilfe.
local function spielerOderHilfe(name)
    local H, grund = Quelle.Historie()
    if not H then sag(ROT .. tostring(grund) .. "|r") return end

    local liste = Kern.Spieler(H, name, 0)
    if #liste == 0 then
        sag(string.format("Für " .. GELB .. "%s|r ist keine Vergabe verzeichnet.", name))
        return
    end

    local haupt = 0
    for _, e in ipairs(liste) do if not e.zweit then haupt = haupt + 1 end end
    sag(string.format("%s: |cff55ff55%d Vergaben|r, davon %d Hauptbedarf",
        Kern.Anzeigename(name), #liste, haupt))

    for i, e in ipairs(liste) do
        if i > 25 then
            print("  " .. GRAU .. "… und " .. (#liste - 25) .. " weitere|r")
            break
        end
        print(string.format("  %s  %s%s", date("%d.%m.%y", e.zeit),
            Quelle.Gegenstandstext(e.eintrag),
            e.zweit and ("  " .. GRAU .. "Zweitbedarf|r") or ""))
    end
end

-- =====================================================================

SLASH_LOOTHISTORIE1 = "/lh"
SLASH_LOOTHISTORIE2 = "/loothistorie"
SlashCmdList["LOOTHISTORIE"] = function(eingabe)
    local wort, rest = (eingabe or ""):match("^%s*(%S*)%s*(.-)%s*$")
    wort = wort or ""

    local fn = befehle[wort:lower()]
    local ok, fehler

    if wort == "" then
        ok, fehler = pcall(Fenster.Umschalten, false)
    elseif fn then
        ok, fehler = pcall(fn, (rest or ""))
    elseif wort:lower() == "hilfe" or wort == "?" then
        ok, fehler = pcall(hilfe)
    else
        -- Alles andere wird als Spielername verstanden
        ok, fehler = pcall(spielerOderHilfe, (eingabe or ""):match("^%s*(.-)%s*$"))
    end

    if not ok then
        print(PRAEFIX .. ROT .. "Fehler in /lh " .. wort .. "|r")
        print(ROT .. tostring(fehler) .. "|r")
        print(GRAU .. "Bitte diese zwei Zeilen weitergeben.|r")
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
            sag(string.format("%d Vergaben aufgezeichnet. " .. GELB .. "/lh|r öffnet die Übersicht.", n))
        else
            sag(GRAU .. "Noch keine Vergabe aufgezeichnet – " .. GELB .. "/lh demo|r" ..
                GRAU .. " zeigt die Anzeige trotzdem.|r")
        end
    end)
end)

ns.geladen = true

return ns
