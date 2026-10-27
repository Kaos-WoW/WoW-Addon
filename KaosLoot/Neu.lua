--[[----------------------------------------------------------------------
    Neu.lua  —  „Neu in KaosLoot“ (wie bei KaosUI)

    Zeigt, was sich im Release geändert hat:
      * ein Fenster mit der Änderungsliste (`/kl neu`, Knopf „Neu“ im Kopf des Fensters),
      * ein „!“ am Knopf, bis das Fenster einmal geöffnet wurde,
      * ein „!“ an Einstellungsseiten, auf denen etwas Neues steht, bis die Seite besucht wurde,
      * einmal nach dem Anmelden ein Hinweis im Chat.
    Gemerkt wird je Version (`FairshareDB.neu`): Mit der nächsten Version ist alles wieder „neu“.

    ⭐ Bei jedem Release: oben in `LISTE` einen Abschnitt für die neue Version ergänzen (neueste zuerst). Die
    Einträge brauchen einen Text in Locale.lua; `seite` ist die Einstellungsseite für das „!“ (optional).
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Neu = {}
ns.Neu = Neu

local S = ns.Stil
local C = S.C

local AKZENT = S.Code(C.ac)
local GRAU   = S.Code(C.mu)

local MARKE = "Interface\\GossipFrame\\AvailableQuestIcon"

-- Neueste Version zuerst. Gezeigt werden alle Abschnitte, das „!“ gilt nur für den ersten.
Neu.LISTE = {
    { version = "1.1.1", eintraege = {
        { text = L["Neu: In der Spielerliste stehen die erhaltenen Main-Items und die Wertung jetzt in getrennten Spalten, auch im Kompaktfenster."] },
    } },
    { version = "1.1.0", eintraege = {
        { text = L["Neu: Zwei Verfahren für die Wertung, die Leitung wählt in den Einstellungen unter Verteilung: Punkte mit Zuschlägen (wie bisher) und Items pro Abend."], seite = "verteilung" },
        { text = L["Neu: Items pro Abend zählt die Items pro besuchtem Abend der letzten 8 Raid-IDs, gleitend und ohne Reset. Fehlen kostet nichts, Anwesenheit schadet nicht."] },
        { text = L["Neu: Heute schon ein Item: Wer an diesem Abend schon eins bekommen hat, steht hinter allen ohne Item (aus, leicht oder streng, Standard streng)."] },
        { text = L["Neu: Korrektur der Leitung mit Pflichtkommentar, Plus oder Minus (/kl korrektur oder Knopf im Spielerdetail), für alle sichtbar."] },
        { text = L["Neu: /kl vergleich zeigt beide Verfahren nebeneinander."] },
        { text = L["Wichtig: Wer das Addon in einer Gruppe nutzt, braucht 1.1.0, sonst ordnen die Addons unterschiedlich."] },
    } },
    { version = "1.0.1", eintraege = {
        { text = L["Geändert: Der Befehl heißt jetzt /kl (vorher /fs; /fs geht vorerst weiter)."] },
        { text = L["Geändert: Der Ordner heißt jetzt KaosLoot. Den alten Ordner Fairshare im AddOns-Ordner bitte löschen; Daten der Version 1.0.0 holt der Abgleich von den Mitspielern."] },
    } },
    { version = "1.0.0", eintraege = {
        { text = L["KaosLoot ist Version 1.0.0: Die Beta ist vorbei."] },
        { text = L["Geändert: Aus Fairshare wird KaosLoot. Der Befehl /kl und deine Daten bleiben."] },
        { text = L["Neu: „Neu in KaosLoot“ (/kl neu) zeigt die Änderungen jeder Version, ein „!“ markiert Neues."] },
    } },
    { version = "0.9.2", eintraege = {
        { text = L["Neu: Einladen per Flüstern – lege ein Stichwort fest, wer es dir flüstert, wird in deine Gruppe eingeladen (Einstellungen → Gruppen)."], seite = "gruppen" },
        { text = L["Geändert: Eine normale Gruppe wird erst zum Raid, wenn sie 5 Mitglieder hat und noch jemand eingeladen wird."] },
        { text = L["Behoben: Die Einteilung listet links nur noch die Spieler des Raidkaders."] },
    } },
    { version = "0.9.1", eintraege = {
        { text = L["Neu: Kompaktfenster für den Raid (/kl kompakt) mit Wertung, laufendem Wurf und Knopf Wurf starten; Vorschau mit /kl kompakt test."] },
        { text = L["Neu: Einteilung und Anwesenheit nach Gildenrang sortiert, Namen in Klassenfarben (auch bei Spieler und Verlauf)."] },
        { text = L["Neu: Item-Tooltip beim Überfahren eines Items im Verlauf."] },
        { text = L["Behoben: Knöpfe ragten bei schmalem Fenster über den Rand."] },
    } },
}

local marker = {}            -- { tex, seite } für die „!“-Zeichen
local fenster

-- =====================================================================
--  Gemerktes
-- =====================================================================

local function db()
    FairshareDB = FairshareDB or {}
    FairshareDB.neu = FairshareDB.neu or {}
    FairshareDB.neu.seiten = FairshareDB.neu.seiten or {}
    return FairshareDB.neu
end

--- Die aktuelle Version der Liste (Schlüssel für das Gemerkte).
function Neu.Version()
    return Neu.LISTE[1] and Neu.LISTE[1].version or "?"
end

function Neu.FensterNeu()
    return db().fenster ~= Neu.Version()
end

--- Steht auf dieser Einstellungsseite etwas Neues, das noch nicht gesehen wurde?
function Neu.SeiteNeu(id)
    if not id or db().seiten[id] == Neu.Version() then return false end
    -- Einträge mit `seite` gelten, solange sie in der Liste stehen (nicht nur im neuesten Abschnitt): Wer von einer
    -- älteren Version kommt, soll sie auch sehen.
    for _, rel in ipairs(Neu.LISTE) do
        for _, e in ipairs(rel.eintraege) do
            if e.seite == id then return true end
        end
    end
    return false
end

function Neu.Auffrischen()
    for _, m in ipairs(marker) do
        m.tex:SetShown(m.seite and Neu.SeiteNeu(m.seite) or (not m.seite and Neu.FensterNeu()) or false)
    end
end

function Neu.SeiteGesehen(id)
    if id and db().seiten[id] ~= Neu.Version() then
        db().seiten[id] = Neu.Version()
        Neu.Auffrischen()
    end
end

--- Hängt ein „!“ an einen Knopf: `seite` = Einstellungsseite, ohne Angabe gilt es für das Fenster „Neu“.
function Neu.Marker(knopf, seite, dx)
    local t = knopf:CreateTexture(nil, "OVERLAY")
    t:SetTexture(MARKE)
    t:SetSize(16, 16)
    t:SetPoint("RIGHT", knopf, "RIGHT", dx or 4, 0)
    marker[#marker + 1] = { tex = t, seite = seite }
    t:SetShown(seite and Neu.SeiteNeu(seite) or (not seite and Neu.FensterNeu()) or false)
    return t
end

-- =====================================================================
--  Das Fenster
-- =====================================================================

local function text()
    local zeilen = {}
    for i, rel in ipairs(Neu.LISTE) do
        if i > 1 then zeilen[#zeilen + 1] = "" end
        zeilen[#zeilen + 1] = AKZENT .. rel.version .. "|r"
        for _, e in ipairs(rel.eintraege) do
            zeilen[#zeilen + 1] = AKZENT .. "·|r " .. e.text
        end
    end
    return table.concat(zeilen, "\n")
end

local function bauen()
    if fenster then return end
    local f = CreateFrame("Frame", "FairshareNeu", UIParent)
    f:SetSize(400, 300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(30)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    S.Kasten(f, 10, C.bg, C.ln)
    f:Hide()
    tinsert(UISpecialFrames, "FairshareNeu")      -- ESC schliesst

    local k = CreateFrame("Frame", nil, f)
    k:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    k:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    k:SetHeight(34)
    k:EnableMouse(true)
    k:RegisterForDrag("LeftButton")
    k:SetScript("OnDragStart", function() f:StartMoving() end)
    k:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local logo = CreateFrame("Frame", nil, k)
    logo:SetSize(18, 18)
    logo:SetPoint("LEFT", k, "LEFT", 12, 0)
    S.Form(logo, 4, C.ac)
    local lt = S.Text(logo, 11, C.white, "CENTER")
    lt:SetPoint("CENTER", 1, 0)
    lt:SetText("F")

    f.titel = S.Text(k, 14, C.tx, "LEFT")
    f.titel:SetPoint("LEFT", logo, "RIGHT", 8, 0)

    local zu = CreateFrame("Button", nil, k)
    zu:SetSize(20, 20)
    zu:SetPoint("RIGHT", k, "RIGHT", -10, 0)
    local x = S.Symbol(zu, "x.tga", 16, C.mu)
    x:SetPoint("CENTER")
    zu:SetScript("OnEnter", function() S.Faerbe(x, C.tx) end)
    zu:SetScript("OnLeave", function() S.Faerbe(x, C.mu) end)
    zu:SetScript("OnClick", function() f:Hide() end)

    f.scroll = S.Bildlauf(f, 40)
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -46)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 16)
    f.text = S.Text(f.scroll.kind, 12, C.tx, "LEFT", true)
    f.text:SetPoint("TOPLEFT", f.scroll.kind, "TOPLEFT", 0, 0)
    f.text:SetWidth(340)
    f.text:SetSpacing(4)

    fenster = f
end

function Neu.Zeigen()
    bauen()
    local f = fenster
    f.titel:SetText(L["Neu in KaosLoot"] .. " " .. Neu.Version())
    f.text:SetText(text())
    local h = math.ceil(f.text:GetStringHeight() or 0)
    f.scroll:SetInhaltHoehe(h + 6)
    f:SetHeight(math.min(480, math.max(200, h + 76)))
    f.scroll:Zurueck()
    f:Show()
    db().fenster = Neu.Version()
    Neu.Auffrischen()
end

function Neu.Umschalten()
    if fenster and fenster:IsShown() then fenster:Hide() else Neu.Zeigen() end
end

function Neu.Sichtbar()
    return fenster and fenster:IsShown() and true or false
end

-- =====================================================================
--  Hinweis im Chat, einmal je Version
-- =====================================================================

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if not C_Timer then return end
        C_Timer.After(8, function()
            if db().gemeldet == Neu.Version() then return end
            db().gemeldet = Neu.Version()
            print(string.format(L["|cff1B6B57KaosLoot|r %s: Was ist neu? |cffffff78/kl neu|r zeigt es."], Neu.Version()))
        end)
    end)
end

return ns
