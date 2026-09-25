--[[----------------------------------------------------------------------
    Fenster.lua  —  UI-Fenster & Notiz-Assistent (Option 1)

    Liest Offiziersnotizen vollautomatisch aus.
    Für das Schreiben auf WoW Forever generiert das Addon den Notiztext
    (z. B. LO:50,100,2960,0,0,0) und stellt ihn im Notiz-Assistenten bereit,
    sodass die Raidleitung den Text per Strg+C ins Gildenfenster übernimmt.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Fenster = {}
ns.Fenster = Fenster

local Kern, Notiz, Gilde, Raid = ns.Kern, ns.Notiz, ns.Gilde, ns.Raid

local rahmen = nil
local assistentIndex = 1

local function erzeugeFenster()
    if rahmen then return rahmen end

    -- Hauptfenster
    rahmen = CreateFrame("Frame", "LootOrdnungFenster", UIParent, "BackdropTemplate")
    rahmen:SetSize(440, 320)
    rahmen:SetPoint("CENTER")
    rahmen:SetMovable(true)
    rahmen:EnableMouse(true)
    rahmen:RegisterForDrag("LeftButton")
    rahmen:SetScript("OnDragStart", function(self) self:StartMoving() end)
    rahmen:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    rahmen:SetFrameStrata("HIGH")

    -- Hintergrund & Styling
    rahmen:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    -- Titel
    local titel = rahmen:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    titel:SetPoint("TOPLEFT", 20, -18)
    titel:SetText("Loot-Ordnung |cff1B6B57(Resurrected)|r")

    -- Schließen-Button (X)
    local schliessenBtn = CreateFrame("Button", nil, rahmen, "UIPanelCloseButton")
    schliessenBtn:SetPoint("TOPRIGHT", -6, -6)
    schliessenBtn:SetScript("OnClick", function() rahmen:Hide() end)

    -- Statuspanel Container
    local statusPanel = CreateFrame("Frame", nil, rahmen)
    statusPanel:SetPoint("TOPLEFT", 15, -45)
    statusPanel:SetPoint("BOTTOMRIGHT", -15, 60)
    rahmen.statusPanel = statusPanel

    local statusText = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", 10, -10)
    statusText:SetPoint("BOTTOMRIGHT", -10, 10)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("TOP")
    statusPanel.text = statusText

    -- Notiz-Assistent Panel Container
    local assistentPanel = CreateFrame("Frame", nil, rahmen)
    assistentPanel:SetPoint("TOPLEFT", 15, -45)
    assistentPanel:SetPoint("BOTTOMRIGHT", -15, 60)
    assistentPanel:Hide()
    rahmen.assistentPanel = assistentPanel

    local assTitel = assistentPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    assTitel:SetPoint("TOPLEFT", 10, -5)
    assistentPanel.titel = assTitel

    local assInfo = assistentPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    assInfo:SetPoint("TOPLEFT", 10, -25)
    assInfo:SetPoint("TOPRIGHT", -10, -25)
    assInfo:SetJustifyH("LEFT")
    assInfo:SetText("|cff8E9A94Notiz markieren & mit Strg+C kopieren, dann ins Gildenfenster einfügen:|r")

    -- EditBox für Notiztext
    local notizBox = CreateFrame("EditBox", nil, assistentPanel, "InputBoxTemplate")
    notizBox:SetSize(280, 24)
    notizBox:SetPoint("TOPLEFT", 15, -55)
    notizBox:SetAutoFocus(false)
    notizBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    notizBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    assistentPanel.notizBox = notizBox

    -- Button Gildenfenster öffnen
    local gildenBtn = CreateFrame("Button", nil, assistentPanel, "UIPanelButtonTemplate")
    gildenBtn:SetSize(110, 24)
    gildenBtn:SetPoint("LEFT", notizBox, "RIGHT", 10, 0)
    gildenBtn:SetText("Gildenfenster")
    gildenBtn:SetScript("OnClick", function()
        if ToggleCommunitiesFrame then
            ToggleCommunitiesFrame()
        elseif ToggleGuildFrame then
            ToggleGuildFrame()
        end
    end)

    -- Assistent Navigation: Vorheriger
    local prevBtn = CreateFrame("Button", nil, assistentPanel, "UIPanelButtonTemplate")
    prevBtn:SetSize(100, 24)
    prevBtn:SetPoint("BOTTOMLEFT", 10, 10)
    prevBtn:SetText(" Zurück")
    prevBtn:SetScript("OnClick", function()
        if assistentIndex > 1 then
            assistentIndex = assistentIndex - 1
            Fenster.Aktualisieren()
        end
    end)
    assistentPanel.prevBtn = prevBtn

    -- Assistent Navigation: Nächster
    local nextBtn = CreateFrame("Button", nil, assistentPanel, "UIPanelButtonTemplate")
    nextBtn:SetSize(120, 24)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 10, 0)
    nextBtn:SetText("Nächster ")
    nextBtn:SetScript("OnClick", function()
        local gesamt = #Gilde.offeneNotizen
        if assistentIndex < gesamt then
            assistentIndex = assistentIndex + 1
            Fenster.Aktualisieren()
        else
            Gilde.offeneNotizen = {}
            Fenster.Aktualisieren()
        end
    end)
    assistentPanel.nextBtn = nextBtn

    -- Assistent Fertig Button
    local fertigBtn = CreateFrame("Button", nil, assistentPanel, "UIPanelButtonTemplate")
    fertigBtn:SetSize(90, 24)
    fertigBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    fertigBtn:SetText("Fertig")
    fertigBtn:SetScript("OnClick", function()
        Gilde.offeneNotizen = {}
        Fenster.Aktualisieren()
    end)

    -- Untere Button-Leiste (Hauptansicht)
    local buchenBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    buchenBtn:SetSize(170, 24)
    buchenBtn:SetPoint("BOTTOMLEFT", 20, 20)
    buchenBtn:SetText("Abend buchen")
    buchenBtn:SetScript("OnClick", function()
        if not IsInGuild() then print("|cff1B6B57Loot-Ordnung|r: Du bist in keiner Gilde.") return end
        Gilde.RosterAnfordern()
        local abend = Raid.Abend()
        if abend.bosse == 0 then
            print("|cff1B6B57Loot-Ordnung|r: Noch kein Boss im Raidabend erfasst.")
            return
        end
        local n = Raid.Buchen(function()
            print("|cff1B6B57Loot-Ordnung|r: Abend im Notiz-Assistenten bereitgestellt.")
        end, "zwingend")
        assistentIndex = 1
        Fenster.Aktualisieren()
    end)
    rahmen.buchenBtn = buchenBtn

    local testBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    testBtn:SetSize(130, 24)
    testBtn:SetPoint("LEFT", buchenBtn, "RIGHT", 10, 0)
    testBtn:SetText("Testkonto buchen")
    testBtn:SetScript("OnClick", function()
        if not IsInGuild() then print("|cff1B6B57Loot-Ordnung|r: Du bist in keiner Gilde.") return end
        Gilde.RosterAnfordern()
        local ich = UnitName("player")
        local meinEintrag = nil
        for _, e in ipairs(Gilde.Lesen()) do
            if e.kurz == ich or e.name:match("^[^%-]+") == ich then meinEintrag = e; break end
        end
        if not meinEintrag then print("|cff1B6B57Loot-Ordnung|r: Eigenen Gildeneintrag nicht gefunden.") return end

        local woche = Kern.WocheAus(time())
        local konto = meinEintrag.konto or Kern.NeuesKonto(woche)
        Kern.VerfallNachholen(konto, woche)
        konto.einsatz = konto.einsatz + Kern.Abendsatz(8)

        Gilde.Schreiben(meinEintrag.guid, konto, meinEintrag.name, meinEintrag.kurz)
        assistentIndex = 1
        Fenster.Aktualisieren()
    end)
    rahmen.testBtn = testBtn

    local zuBtn = CreateFrame("Button", nil, rahmen, "UIPanelButtonTemplate")
    zuBtn:SetSize(80, 24)
    zuBtn:SetPoint("BOTTOMRIGHT", -20, 20)
    zuBtn:SetText("Schließen")
    zuBtn:SetScript("OnClick", function() rahmen:Hide() end)

    rahmen:Hide()
    return rahmen
end

function Fenster.Aktualisieren()
    if not rahmen or not rahmen:IsShown() then return end

    local offene = Gilde.offeneNotizen
    if #offene > 0 then
        -- Assistenten-Modus
        rahmen.statusPanel:Hide()
        rahmen.buchenBtn:Hide()
        rahmen.testBtn:Hide()
        rahmen.assistentPanel:Show()

        if assistentIndex > #offene then assistentIndex = #offene end
        if assistentIndex < 1 then assistentIndex = 1 end

        local eintrag = offene[assistentIndex]
        rahmen.assistentPanel.titel:SetText(string.format("Notiz-Assistent |cff55ff55(%d von %d)|r — %s",
            assistentIndex, #offene, eintrag.kurz))
        rahmen.assistentPanel.notizBox:SetText(eintrag.text)
        rahmen.assistentPanel.notizBox:SetFocus()
        rahmen.assistentPanel.notizBox:HighlightText()

        rahmen.assistentPanel.prevBtn:SetEnabled(assistentIndex > 1)
        if assistentIndex < #offene then
            rahmen.assistentPanel.nextBtn:SetText("Nächster ")
        else
            rahmen.assistentPanel.nextBtn:SetText("Fertig")
        end
    else
        -- Hauptstatus-Modus
        rahmen.assistentPanel:Hide()
        rahmen.statusPanel:Show()
        rahmen.buchenBtn:Show()
        rahmen.testBtn:Show()

        local text = {}
        text[#text + 1] = "Berechtigungen: " .. (Gilde.DarfSchreiben() and "|cff55ff55Schreiben OK|r" or "|cffff5555Kein Schreibrecht|r")

        local abend = LootOrdnungDB and LootOrdnungDB.abend
        if abend and abend.bosse and abend.bosse > 0 then
            text[#text + 1] = string.format("Laufender Abend: |cff55ff55%d Bosse|r erfasst.", abend.bosse)
        else
            text[#text + 1] = "Laufender Abend: Kein Boss gebucht."
        end

        local ich = UnitName("player")
        local meinEintrag = nil
        if IsInGuild() then
            for _, e in ipairs(Gilde.Lesen()) do
                if e.kurz == ich or e.name:match("^[^%-]+") == ich then meinEintrag = e; break end
            end
        end

        if meinEintrag then
            text[#text + 1] = string.format("Eigenes Konto (%s):", meinEintrag.kurz)
            if meinEintrag.konto then
                local k = meinEintrag.konto
                text[#text + 1] = string.format("  Prio: |cff55ff55%.2f|r (E %d, R %d)", Kern.Prio(k), k.einsatz, k.ruestwert)
                text[#text + 1] = string.format("  Notiz auf Server: |cffffff78%s|r", meinEintrag.notiz ~= "" and meinEintrag.notiz or "(leer)")
            else
                text[#text + 1] = "  |cffff5555Kein Konto in der Notiz.|r"
            end
        else
            text[#text + 1] = "|cff8E9A94Gilden-Roster wird geladen...|r"
        end

        rahmen.statusPanel.text:SetText(table.concat(text, "\n"))
    end
end

function Fenster.Zeigen()
    local f = erzeugeFenster()
    f:Show()
    Gilde.RosterAnfordern()
    Fenster.Aktualisieren()
end

function Fenster.Verstecken()
    if rahmen then rahmen:Hide() end
end

function Fenster.Umschalten()
    local f = erzeugeFenster()
    if f:IsShown() then
        f:Hide()
    else
        Fenster.Zeigen()
    end
end

return ns
