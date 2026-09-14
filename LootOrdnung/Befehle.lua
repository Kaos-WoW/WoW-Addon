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
    print("  |cffffff78/lo test|r   – Selbsttests des Rechenkerns")
    print("  |cffffff78/lo rechte|r – prüfen, ob ich Notizen schreiben darf")
    print("  |cffffff78/lo notiz|r   – meine eigene Offiziersnotiz anzeigen")
    print("  |cffffff78/lo liste|r   – alle Konten nach Prio")
    print("  |cffffff78/lo fremd|r   – wer hat noch Fremdinhalt in der Notiz")
    print("  |cffffff78/lo sichern|r – alle Notizen sichern, bevor geschrieben wird")
end

--- Eigenen Roster-Eintrag suchen.
--  ⚠️ NIE über den Index adressieren — der verschiebt sich, sobald
--  jemand online geht. Immer über den Namen suchen und die GUID nehmen.
local function meinEintrag()
    local ich = UnitName("player")
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, _, _, _, _, _, _, offiziersnotiz,
              _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if name and name:match("^[^%-]+") == ich then
            return name, offiziersnotiz, guid
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
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end

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


SLASH_LOOTORDNUNG1 = "/lo"
SLASH_LOOTORDNUNG2 = "/lootordnung"
SlashCmdList["LOOTORDNUNG"] = function(eingabe)
    local wort = (eingabe or ""):match("^%s*(%S*)"):lower()
    local fn = befehle[wort]
    if fn then fn() else hilfe() end
end
