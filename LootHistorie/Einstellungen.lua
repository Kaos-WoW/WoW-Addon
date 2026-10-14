--[[----------------------------------------------------------------------
    Einstellungen.lua  —  Das Einstellungsfenster (Look wie KaosUI)

    Ein eigenes Fenster neben der Uebersicht: Kopf mit Logo und Version,
    Seitenleiste, Karten mit Zeilen (Text und Erklaerung links, Schalter,
    Segmentwahl oder Knopf rechts), Fussleiste.

    Drei Seiten:
      * Erfassung          was, wo und von wem mitgeschrieben wird
      * Gargul & Abgleich  Wuerfelbereiche, Import, Fenster, Abgleich
      * Gruppen            Kader und Raidgruppen

    ⚠️ Gelesen und geschrieben wird immer direkt in den Einstellungstisch
    von Erfassung.lua und in Gruppen.lua. Das Fenster haelt keine eigene
    Kopie; sonst liefe es auseinander, sobald jemand den Befehl benutzt.

    ⚠️ Jede Zeile hat `update()`. Aenderungen laufen immer ueber
    `Einstellungen.Aktualisieren()`, das Texte, Zustand und Hoehen neu setzt.
    So gibt es keine Anker zwischen den Zeilen, die sich verschieben koennten.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Einstellungen = {}
ns.Einstellungen = Einstellungen

local S = ns.Stil
local C = S.C

local BREITE, HOEHE = 780, 580
local KOPF, FUSS, SEITE = 44, 40, 190
local KARTE_X, KARTE_Y, KARTE_LUECKE = 14, 12, 10

local win, body, scroll
local Seiten = {}        -- id -> { karten, nav }
local NavKnoepfe = {}
local aktuelleSeite = "erfassung"
local Meldung = {}       -- kurze Rueckmeldungen je Schluessel
local loeschenBereit

local function d() return ns.Erfassung.Einstellungen() end

local function farbig(c, text) return S.Code(c) .. text .. "|r" end

-- =====================================================================
--  Zeilen
-- =====================================================================

local function zeile(karte, def)
    local r = CreateFrame("Frame", nil, karte)
    r.def = def
    r.label  = S.Text(r, 13, C.tx, "LEFT", true)
    r.beschr = S.Text(r, 11, C.mu, "LEFT", true)
    r.trenner = S.Tex(r, "BORDER", C.ln)
    r.trenner:SetHeight(1)
    r.trenner:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.trenner:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)

    local art = def.art

    if art == "schalter" then
        local sw = S.Schalter(r)
        r.ctrl, r.ctrlB, r.ctrlH = sw, 32, 18
        local function kippen()
            def.set(not sw.an)
            Einstellungen.Aktualisieren()
        end
        sw:SetScript("OnClick", kippen)
        r:EnableMouse(true)
        r:SetScript("OnMouseUp", function(s, taste)
            if taste == "LeftButton" and s:IsMouseOver() then kippen() end
        end)
        function r.bedienen() sw:SetAn(def.get()) end

    elseif art == "segment" then
        local seg = S.Segment(r, function(wert)
            def.set(wert)
            Einstellungen.Aktualisieren()
        end)
        local b = seg:SetWerte(def.werte)
        r.ctrl, r.ctrlB, r.ctrlH = seg, b, 26
        r.stapel = def.gestapelt
        function r.bedienen() seg:SetWahl(def.get()) end

    elseif art == "knopf" then
        local k = def.knopf
        local b = S.Knopf(r, "", k.art or "secondary")
        b:SetScript("OnClick", function()
            k.klick()
            Einstellungen.Aktualisieren()
        end)
        r.ctrl, r.ctrlH = b, 24
        function r.bedienen()
            local t = type(k.text) == "function" and k.text() or k.text
            b:SetLabel(t)
            b:SetAktiv(k.aktiv == nil or k.aktiv() ~= false)
            r.ctrlB = math.ceil(b:GetWidth())
        end

    elseif art == "eingabe" then
        local k = def.knopf
        local f = CreateFrame("Frame", nil, r)
        local eb = S.Eingabe(f, 190, 26)
        eb:SetPoint("LEFT", f, "LEFT", 0, 0)
        local b = S.Knopf(f, k.text, "secondary")
        b:SetPoint("LEFT", eb, "RIGHT", 8, 0)
        local function abschicken()
            local t = eb:GetText()
            k.klick(t)
            eb:SetText("")
            eb:ClearFocus()
            Einstellungen.Aktualisieren()
        end
        eb:SetScript("OnEnterPressed", abschicken)
        b:SetScript("OnClick", abschicken)
        r.ctrl, r.ctrlH = f, 26
        r.ctrlB = 190 + 8 + math.ceil(b:GetWidth())
        f:SetSize(r.ctrlB, 26)
        function r.bedienen() end
    end

    function r.update()
        local lab = type(def.label) == "function" and def.label() or def.label or ""
        local bes = type(def.beschr) == "function" and def.beschr() or def.beschr or ""
        r.label:SetText(lab)
        r.beschr:SetText(bes)
        r.label:SetShown(lab ~= "")
        r.beschr:SetShown(bes ~= "")
        if r.bedienen then r.bedienen() end
    end

    karte.zeilen[#karte.zeilen + 1] = r
    return r
end

--- Hoehe einer Zeile bei Breite w; setzt die Lage der Teile.
local function zeileMessen(r, w)
    r:SetWidth(w)
    local lh = r.label:IsShown() and r.label:GetStringHeight() or 0
    local bh = r.beschr:IsShown() and (r.beschr:GetStringHeight() + (lh > 0 and 2 or 0)) or 0

    local seitlich = r.ctrl and not r.stapel
    local cb = (seitlich and (r.ctrlB or 0)) or 0
    local tb = w - (cb > 0 and (cb + 14) or 0)
    if tb < 80 then tb = 80 end
    r.label:SetWidth(tb)
    r.beschr:SetWidth(tb)

    lh = r.label:IsShown() and r.label:GetStringHeight() or 0
    bh = r.beschr:IsShown() and (r.beschr:GetStringHeight() + (lh > 0 and 2 or 0)) or 0

    local h
    if r.ctrl and r.stapel then
        h = math.ceil(lh + bh) + 8 + (r.ctrlH or 0) + 14
    else
        h = math.ceil(math.max(lh + bh, seitlich and (r.ctrlH or 0) or 0)) + 14
    end
    r:SetHeight(h)

    local oben = math.floor((h - (lh + bh) - ((r.ctrl and r.stapel) and (8 + (r.ctrlH or 0)) or 0)) / 2 + 0.5)
    r.label:ClearAllPoints()
    r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -oben)
    r.beschr:ClearAllPoints()
    if lh > 0 then
        r.beschr:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -2)
    else
        r.beschr:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -oben)
    end

    if r.ctrl then
        r.ctrl:ClearAllPoints()
        if r.stapel then
            r.ctrl:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -(oben + math.ceil(lh + bh) + 8))
        else
            r.ctrl:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        end
    end
    return h
end

-- =====================================================================
--  Karten und Seiten
-- =====================================================================

local function karte(seite, titel, beschr, sichtbar)
    local c = CreateFrame("Frame", nil, seite.kind)
    S.Kasten(c, 8, C.p1, C.ln)
    c.titel = S.Text(c, 13, C.tx, "LEFT")
    c.beschr = S.Text(c, 11, C.mu, "LEFT", true)
    c.titelQuelle, c.beschrQuelle = titel, beschr
    c.sichtbar = sichtbar
    c.zeilen = {}
    seite.karten[#seite.karten + 1] = c
    return c
end

local function kartenMessen(c, w)
    c:SetWidth(w)
    local innen = w - KARTE_X * 2
    local y = KARTE_Y

    local titel = type(c.titelQuelle) == "function" and c.titelQuelle() or c.titelQuelle or ""
    local bes   = type(c.beschrQuelle) == "function" and c.beschrQuelle() or c.beschrQuelle or ""
    c.titel:SetText(titel)
    c.beschr:SetText(bes)
    c.titel:SetShown(titel ~= "")
    c.beschr:SetShown(bes ~= "")

    if titel ~= "" then
        c.titel:SetWidth(innen)
        c.titel:ClearAllPoints()
        c.titel:SetPoint("TOPLEFT", c, "TOPLEFT", KARTE_X, -y)
        y = y + c.titel:GetStringHeight()
        if bes ~= "" then
            c.beschr:SetWidth(innen)
            c.beschr:ClearAllPoints()
            c.beschr:SetPoint("TOPLEFT", c.titel, "BOTTOMLEFT", 0, -2)
            y = y + 2 + c.beschr:GetStringHeight()
        end
        y = y + 4
    end

    local erste = true
    for _, r in ipairs(c.zeilen) do
        local da = r.def.sichtbar == nil or r.def.sichtbar()
        if da then
            r:Show()
            r.update()
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", c, "TOPLEFT", KARTE_X, -y)
            r.trenner:SetShown(not erste)
            erste = false
            y = y + zeileMessen(r, innen)
        else
            r:Hide()
        end
    end

    y = math.ceil(y + KARTE_Y - 2)
    c:SetHeight(y)
    return y
end

local function seiteMessen(id)
    local P = Seiten[id]
    -- Breite des Bildlaufs abzueglich Balken; vor dem ersten Zeichnen ist
    -- sie noch nicht bekannt, dann gilt das Sollmass.
    local w = (scroll:GetWidth() or 0) - 10
    if w < 100 then w = BREITE - 2 - SEITE - 20 - 16 - 10 end
    P.kind:SetWidth(w)

    local y = 0
    for _, c in ipairs(P.karten) do
        local da = c.sichtbar == nil or c.sichtbar()
        if da then
            c:Show()
            local h = kartenMessen(c, w)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", P.kind, "TOPLEFT", 0, -y)
            y = y + h + KARTE_LUECKE
        else
            c:Hide()
        end
    end
    scroll:SetInhaltHoehe(y)
end

-- =====================================================================
--  Inhalt der Seiten
-- =====================================================================

local ORTE = {
    { wert = "raid",     label = "Schlachtzug" },
    { wert = "instanz",  label = "Instanz" },
    { wert = "ueberall", label = "Überall" },
}
local ORT_TEXT = {
    raid     = "Nur in Schlachtzugsinstanzen.",
    instanz  = "Auch Fünfergruppen – zum Erproben des Ablaufs.",
    ueberall = "Ohne Einschränkung; auch Weltdrops und Questbelohnungen zählen.",
}
local QUALITAETEN = {
    { wert = 1, label = "Gewöhnlich" }, { wert = 2, label = "Ungewöhnlich" },
    { wert = 3, label = "Selten" },     { wert = 4, label = "Episch" },
    { wert = 5, label = "Legendär" },
}
local MODI = {
    { wert = "auto",  label = "Automatisch" },
    { wert = "immer", label = "Immer" },
    { wert = "nie",   label = "Nie" },
}
local MODUS_TEXT = {
    auto  = "Der Plündermeister schreibt; gibt es keinen, der Raidleiter.",
    immer = "Dieser Spieler schreibt mit – egal, wer sonst.",
    nie   = "Dieser Spieler schreibt nicht mit, er empfängt nur.",
}

local function seiteErfassung(P)
    local k1 = karte(P, "Mitschreiben", "Was das Addon in die Historie aufnimmt.")
    zeile(k1, { art = "schalter", label = "Vergaben aufzeichnen",
        beschr = "Aus heißt: nichts Neues wird erfasst. Vorhandenes bleibt.",
        get = function() return d().erfassen end,
        set = function(v) d().erfassen = v end })
    zeile(k1, { art = "schalter", label = "Nur Ausgewürfeltes zählen",
        beschr = "Streng: Ohne Bedarfswurf zugeteilte Stücke fallen heraus.",
        get = function() return d().nurGewuerfelt end,
        set = function(v) d().nurGewuerfelt = v end })

    local k2 = karte(P, "Wer schreibt mit",
        "Nur einer pro Gruppe führt die Historie, damit nichts doppelt entsteht.")
    zeile(k2, { art = "segment", label = "Schreiber", werte = MODI,
        beschr = function() return MODUS_TEXT[d().schreiben or "auto"] end,
        get = function() return d().schreiben or "auto" end,
        set = function(v) d().schreiben = v end })
    zeile(k2, { art = "info",
        label = function()
            local darf = ns.Rolle.IchSchreibe()
            return darf and farbig(C.ok, "Du schreibst gerade mit")
                         or farbig(C.warn, "Du schreibst gerade nicht mit")
        end,
        beschr = function()
            local _, grund = ns.Rolle.IchSchreibe()
            local wer = ns.Rolle.AktuellerSchreiber()
            return tostring(grund) .. ((wer and ("  ·  Schreiber: " .. wer)) or "")
        end })

    local k3 = karte(P, "Was wird erfasst")
    zeile(k3, { art = "segment", label = "Ort", werte = ORTE,
        beschr = function() return ORT_TEXT[d().ort] or "" end,
        get = function() return d().ort end,
        set = function(v) d().ort = v end })
    zeile(k3, { art = "segment", label = "Ab welcher Qualität", werte = QUALITAETEN, gestapelt = true,
        beschr = "Auf Stufe 60 fällt in manchen Raids überwiegend Blaues – lieber zu viel erfassen als einen Drop verlieren.",
        get = function() return d().mindestQualitaet end,
        set = function(v) d().mindestQualitaet = v end })
end

local function seiteGargul(P)
    local k1 = karte(P, "Gargul", "Gewürfelt wird 100 für Hauptbedarf und 50 für Zweitbedarf.")
    zeile(k1, { art = "knopf", label = "Würfelbereiche",
        beschr = function()
            local B, grund = ns.Quelle.GargulBereiche()
            if not B then return "Gargul ist nicht bereit (" .. tostring(grund) .. "). Ohne Gargul liest das Addon die Würfe selbst aus dem Chat." end
            local liste = table.concat(B.bereiche, ", ")
            if B.ok then return farbig(C.ok, "Stimmen.") .. "  Gargul kennt: " .. liste end
            return farbig(C.bad, "Passen nicht.") .. "  Gargul kennt: " .. liste ..
                ". Erwartet werden 1-100 und 1-50, sonst wird der Zweitbedarf nicht erkannt."
        end,
        knopf = { text = "Auf 100/50 stellen", art = "primary",
            aktiv = function()
                local B = ns.Quelle.GargulBereiche()
                return B ~= nil and not B.ok
            end,
            klick = function() ns.Quelle.GargulBereicheSetzen() end } })
    zeile(k1, { art = "knopf", label = "Bisherige Vergaben übernehmen",
        beschr = function()
            return Meldung.import or "Holt Garguls bisherige Aufzeichnungen in die eigene Historie. Mehrfaches Übernehmen ändert nichts."
        end,
        knopf = { text = "Übernehmen",
            klick = function()
                local neu, doppelt = ns.Quelle.GargulImport()
                if not neu then
                    Meldung.import = farbig(C.bad, tostring(doppelt))
                else
                    Meldung.import = farbig(C.ok, neu .. " übernommen") ..
                        (doppelt > 0 and (", " .. doppelt .. " schon vorhanden") or "")
                end
                if ns.Fenster then ns.Fenster.Aktualisieren() end
            end } })

    local k2 = karte(P, "Fenster")
    zeile(k2, { art = "schalter", label = "Bei Wurfbeginn selbst öffnen",
        beschr = "Die Übersicht springt auf, sobald der erste Bedarfswurf fällt.",
        get = function() return ns.Fenster.AutoOeffnen() end,
        set = function(v) ns.Fenster.AutoSetzen(v) end })

    local k3 = karte(P, "Abgleich",
        "Führt die Historien einer Gruppe zusammen – es kommt nur hinzu, nichts wird überschrieben.")
    zeile(k3, { art = "info",
        label = function()
            local n = ns.Abgleich.Stand()
            return n .. " Einträge bei dir"
        end,
        beschr = function()
            local bekannte = 0
            for _ in pairs(ns.Abgleich.Bekannte()) do bekannte = bekannte + 1 end
            local abw = #ns.Abgleich.Abweichend
            return bekannte .. " Mitspieler mit dem Addon erkannt  ·  " ..
                (abw > 0 and farbig(C.warn, abw .. " weichen ab") or "keine Abweichung bekannt")
        end })
    zeile(k3, { art = "knopf", label = "Jetzt abgleichen",
        beschr = function()
            return Meldung.abgleich or "Nur Leiter, Assistenten und der Plündermeister dürfen abgleichen."
        end,
        knopf = { text = "Abgleichen", art = "primary",
            klick = function()
                local ok, grund = ns.Abgleich.Starten()
                Meldung.abgleich = ok and farbig(C.ok, "Gestartet – das Ergebnis steht im Chat.")
                                       or farbig(C.bad, tostring(grund))
            end } })
end

local function seiteGruppen(P)
    local G = ns.Gruppen

    local k1 = karte(P, "Gruppen",
        "Eine Gruppe bestimmt, wer in der Liste steht – auch ohne Vergabe. Vergaben merken sich die Gruppe, die beim Eintragen aktiv war.")
    for i = 1, 8 do
        zeile(k1, { art = "knopf",
            sichtbar = function() return G.Namen()[i] ~= nil end,
            label = function() return G.Namen()[i] or "" end,
            beschr = function()
                local g = G.Holen(G.Namen()[i])
                if not g then return "" end
                return g.modus == "raid" and "Raidgruppe – wer gerade in deiner Gruppe steht"
                                         or (#(g.kader or {}) .. " Namen im Kader")
            end,
            knopf = { text = function() return G.Namen()[i] == G.AktivName() and "Aktiv" or "Aktivieren" end,
                art = "primary",
                aktiv = function() return G.Namen()[i] ~= G.AktivName() end,
                klick = function()
                    loeschenBereit = nil
                    G.Aktivieren(G.Namen()[i])
                end } })
    end
    zeile(k1, { art = "info", sichtbar = function() return #G.Namen() == 0 end,
        label = "Noch keine Gruppe",
        beschr = "Unten eine anlegen, zum Beispiel „40er“ oder „10er“." })
    zeile(k1, { art = "knopf", sichtbar = function() return G.AktivName() ~= nil end,
        label = "Keine Gruppe verwenden",
        beschr = "Neue Vergaben bekommen dann keine Gruppe, die Liste keine Pflichtnamen.",
        knopf = { text = "Abwählen", klick = function() G.Aktivieren(nil) end } })

    local aktiv = function() return G.AktivName() ~= nil end
    local k2 = karte(P, function() return "Aktive Gruppe: " .. tostring(G.AktivName() or "") end,
        nil, aktiv)
    zeile(k2, { art = "segment", label = "Art",
        werte = { { wert = "kader", label = "Kader" }, { wert = "raid", label = "Raidgruppe" } },
        beschr = function()
            local g = G.Aktiv()
            return (g and g.modus == "raid")
                and "In der Liste stehen alle, die gerade in deiner Gruppe sind – für kleinere Schlachtzüge."
                or  "In der Liste steht immer der ganze Kader – zum Beispiel für den 40er."
        end,
        get = function() local g = G.Aktiv() return g and g.modus or "kader" end,
        set = function(v)
            local g = G.Aktiv()
            if g and g.modus ~= v then G.ModusUmschalten(G.AktivName()) end
        end })
    local istKader = function() local g = G.Aktiv() return g and g.modus ~= "raid" end
    zeile(k2, { art = "knopf", sichtbar = istKader, label = "Kader aus der aktuellen Gruppe füllen",
        beschr = function()
            return Meldung.kader or "Ersetzt den Kader durch alle, die jetzt in deiner Gruppe stehen."
        end,
        knopf = { text = "Füllen",
            klick = function()
                local n = G.KaderAusGruppe(G.AktivName())
                Meldung.kader = farbig(C.ok, (n or 0) .. " Namen übernommen")
            end } })
    zeile(k2, { art = "eingabe", sichtbar = istKader, label = "Namen hinzufügen",
        beschr = function()
            return Meldung.namen or "Mit Komma trennen – Nachnamen enthalten Leerzeichen."
        end,
        knopf = { text = "Hinzufügen",
            klick = function(text)
                local n = G.KaderErgaenzen(G.AktivName(), text)
                Meldung.namen = farbig(C.ok, (n or 0) .. " ergänzt")
            end } })
    zeile(k2, { art = "info", sichtbar = istKader, label = "Kader",
        beschr = function()
            local g = G.Aktiv()
            if not g or #(g.kader or {}) == 0 then return "Noch leer." end
            local teile = {}
            for i, n in ipairs(g.kader) do
                if i > 16 then teile[#teile + 1] = "…" break end
                teile[#teile + 1] = n
            end
            return table.concat(teile, ", ")
        end })
    zeile(k2, { art = "knopf", label = "Gruppe löschen",
        beschr = function()
            return loeschenBereit and farbig(C.warn, "Nochmal klicken, um die Gruppe wirklich zu löschen.")
                   or "Die Vergaben bleiben erhalten, sie verlieren nur ihre Gruppe nicht."
        end,
        knopf = { text = function() return loeschenBereit and "Wirklich löschen" or "Löschen" end,
            klick = function()
                local name = G.AktivName()
                if loeschenBereit == name then
                    G.Loeschen(name)
                    loeschenBereit = nil
                else
                    loeschenBereit = name
                end
            end } })

    local k3 = karte(P, "Neue Gruppe")
    zeile(k3, { art = "eingabe", label = "Name",
        beschr = function()
            return Meldung.neu or "Höchstens 40 Zeichen, ohne Semikolon."
        end,
        knopf = { text = "Anlegen",
            klick = function(text)
                local ok, grund = G.Anlegen(text)
                Meldung.neu = ok and farbig(C.ok, "Angelegt.") or farbig(C.bad, tostring(grund))
            end } })
end

local NAV = {
    { id = "erfassung", label = "Erfassung",         icon = "settings.tga",
      titel = "Erfassung", beschr = "Was, wo und von wem mitgeschrieben wird.", bauen = seiteErfassung },
    { id = "gargul",    label = "Gargul & Abgleich", icon = "rotate.tga",
      titel = "Gargul & Abgleich", beschr = "Würfelbereiche, Import und der Abgleich zwischen den Spielern.", bauen = seiteGargul },
    { id = "gruppen",   label = "Gruppen",           icon = "users-group.tga",
      titel = "Gruppen", beschr = "Kader und Raidgruppen für verschiedene Raidgrößen.", bauen = seiteGruppen },
}

-- =====================================================================
--  Fenster
-- =====================================================================

local function version()
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
    local ok, v = pcall(f, ADDON, "Version")
    return (ok and v) or "?"
end

local function kopfBauen()
    local kopf = CreateFrame("Frame", nil, win)
    kopf:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -1)
    kopf:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -1)
    kopf:SetHeight(KOPF)
    S.Form(kopf, 9, C.p1, nil, "BACKGROUND", 0, 0, { tl = true, tr = true })
    local linie = S.Tex(kopf, "BORDER", C.ln)
    linie:SetHeight(1)
    linie:SetPoint("BOTTOMLEFT")
    linie:SetPoint("BOTTOMRIGHT")

    kopf:EnableMouse(true)
    kopf:RegisterForDrag("LeftButton")
    kopf:SetScript("OnDragStart", function() win:StartMoving() end)
    kopf:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)

    local logo = CreateFrame("Frame", nil, kopf)
    logo:SetSize(22, 22)
    logo:SetPoint("LEFT", kopf, "LEFT", 12, 0)
    S.Form(logo, 5, C.ac)
    local l = S.Text(logo, 13, C.white, "CENTER")
    l:SetPoint("CENTER", 1, 0)
    l:SetText("L")

    local name = S.Text(kopf, 14, C.tx, "LEFT")
    name:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    name:SetText("Loot-Historie")

    local tag = CreateFrame("Frame", nil, kopf)
    tag:SetHeight(17)
    tag:SetPoint("LEFT", name, "RIGHT", 10, 0)
    S.Kasten(tag, 4, C.p1, C.ln)
    local tt = S.Text(tag, 11, C.mu, "CENTER")
    tt:SetPoint("CENTER", 0, 0)
    tt:SetText(version() .. " · Forever")
    tag:SetWidth(math.ceil(tt:GetStringWidth()) + 12)

    local zu = CreateFrame("Button", nil, kopf)
    zu:SetSize(20, 20)
    zu:SetPoint("RIGHT", kopf, "RIGHT", -12, 0)
    local x = S.Symbol(zu, "x.tga", 16, C.mu)
    x:SetPoint("CENTER")
    zu:SetScript("OnEnter", function() S.Faerbe(x, C.tx) end)
    zu:SetScript("OnLeave", function() S.Faerbe(x, C.mu) end)
    zu:SetScript("OnClick", function() win:Hide() end)
end

local function navKnopf(eltern, nav)
    local b = CreateFrame("Button", nil, eltern)
    b:SetHeight(28)
    b.nav = nav
    b.hover = S.Form(b, 6, C.p2)
    b.hover:SetShown(false)
    b.randSel = S.Form(b, 6, C.ac, nil, "BACKGROUND", 1)
    -- Fuellung 2px nach rechts versetzt -> links bleibt eine Petrol-Kante
    local bezug = b:CreateTexture(nil, "BACKGROUND")
    bezug:SetPoint("TOPLEFT", b, "TOPLEFT", 2, 0)
    bezug:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.fuellSel = S.Form(b, 6, C.acb, nil, "BACKGROUND", 2, 0, nil, bezug)
    b.randSel:SetShown(false)
    b.fuellSel:SetShown(false)

    b.icon = S.Symbol(b, nav.icon, 14, C.mu, "OVERLAY")
    b.icon:SetPoint("LEFT", b, "LEFT", 10, 0)
    b.text = S.Text(b, 13, C.mu)
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.text:SetText(nav.label)

    b:SetScript("OnEnter", function(s)
        if s.sel then return end
        s.hover:SetShown(true)
        S.TextFarbe(s.text, C.tx)
        S.Faerbe(s.icon, C.tx)
    end)
    b:SetScript("OnLeave", function(s)
        if s.sel then return end
        s.hover:SetShown(false)
        S.TextFarbe(s.text, C.mu)
        S.Faerbe(s.icon, C.mu)
    end)
    b:SetScript("OnClick", function(s) Einstellungen.Waehle(s.nav.id) end)
    return b
end

local function setzeNav(id)
    for _, b in ipairs(NavKnoepfe) do
        local sel = b.nav.id == id
        b.sel = sel
        b.hover:SetShown(false)
        b.randSel:SetShown(sel)
        b.fuellSel:SetShown(sel)
        S.TextFarbe(b.text, sel and C.tx or C.mu)
        S.Faerbe(b.icon, sel and C.ach or C.mu)
    end
end

local kruemel, titel, beschr, fussText

local function fensterBauen()
    win = CreateFrame("Frame", "LootHistorieEinstellungen", UIParent)
    win:SetSize(BREITE, HOEHE)
    win:SetPoint("CENTER", UIParent, "CENTER", 40, 0)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    S.Kasten(win, 10, C.bg, C.ln)
    win:Hide()
    tinsert(UISpecialFrames, "LootHistorieEinstellungen")   -- ESC schliesst

    kopfBauen()

    -- Seitenleiste
    local seite = CreateFrame("Frame", nil, win)
    seite:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -1 - KOPF)
    seite:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 1, FUSS + 1)
    seite:SetWidth(SEITE)
    local sl = S.Tex(seite, "BORDER", C.ln)
    sl:SetWidth(1)
    sl:SetPoint("TOPRIGHT")
    sl:SetPoint("BOTTOMRIGHT")

    local gl = S.Text(seite, 11, C.mu)
    gl:SetPoint("TOPLEFT", seite, "TOPLEFT", 16, -16)
    gl:SetText("Einstellungen")
    local y = 36
    for _, nav in ipairs(NAV) do
        local b = navKnopf(seite, nav)
        b:SetPoint("TOPLEFT", seite, "TOPLEFT", 8, -y)
        b:SetPoint("TOPRIGHT", seite, "TOPRIGHT", -8, -y)
        NavKnoepfe[#NavKnoepfe + 1] = b
        y = y + 30
    end

    -- Inhalt
    body = CreateFrame("Frame", nil, win)
    body:SetPoint("TOPLEFT", seite, "TOPRIGHT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, FUSS + 1)

    kruemel = S.Text(body, 11, C.mu)
    kruemel:SetPoint("TOPLEFT", body, "TOPLEFT", 20, -16)
    titel = S.Text(body, 17, C.tx, "LEFT")
    titel:SetPoint("TOPLEFT", body, "TOPLEFT", 20, -34)
    beschr = S.Text(body, 12, C.mu, "LEFT", true)
    beschr:SetPoint("TOPLEFT", body, "TOPLEFT", 20, -62)
    beschr:SetPoint("TOPRIGHT", body, "TOPRIGHT", -20, -62)

    scroll = S.Bildlauf(body, 48)
    scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 20, -96)
    scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -16, 12)

    -- Fuss
    local fuss = CreateFrame("Frame", nil, win)
    fuss:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 1, 1)
    fuss:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 1)
    fuss:SetHeight(FUSS)
    S.Form(fuss, 9, C.p1, nil, "BACKGROUND", 0, 0, { bl = true, br = true })
    local fl = S.Tex(fuss, "BORDER", C.ln)
    fl:SetHeight(1)
    fl:SetPoint("TOPLEFT")
    fl:SetPoint("TOPRIGHT")

    fussText = S.Text(fuss, 11, C.mu)
    fussText:SetPoint("LEFT", fuss, "LEFT", 16, 0)

    local tests = S.Knopf(fuss, "Selbsttests", "secondary", 24)
    tests:SetPoint("RIGHT", fuss, "RIGHT", -12, 0)
    tests:SetScript("OnClick", function()
        if ns.Tests then ns.Tests.Alle() end
    end)

    -- Seiten bauen: je ein Kind-Frame im Bildlauf, nur die aktuelle sichtbar
    for _, nav in ipairs(NAV) do
        local P = { karten = {}, kind = CreateFrame("Frame", nil, scroll.kind), nav = nav }
        P.kind:SetPoint("TOPLEFT", scroll.kind, "TOPLEFT", 0, 0)
        P.kind:SetSize(BREITE - 2 - SEITE - 20 - 16 - 10, 1)
        P.kind:Hide()
        nav.bauen(P)
        Seiten[nav.id] = P
    end

    win:SetScript("OnShow", function() Einstellungen.Aktualisieren() end)
end

-- =====================================================================
--  Steuerung
-- =====================================================================

function Einstellungen.Aktualisieren()
    if not win or not win:IsShown() then return end
    local ok, fehler = pcall(function()
        local P = Seiten[aktuelleSeite]
        if not P then return end

        for id, Q in pairs(Seiten) do Q.kind:SetShown(id == aktuelleSeite) end
        setzeNav(aktuelleSeite)

        kruemel:SetText("Einstellungen  ›  " .. P.nav.label)
        titel:SetText(P.nav.titel)
        beschr:SetText(P.nav.beschr)

        seiteMessen(aktuelleSeite)

        local darf, grund = ns.Rolle.IchSchreibe()
        fussText:SetText((darf and "Du schreibst mit" or "Du schreibst nicht mit") ..
            "  ·  " .. tostring(grund))
    end)
    if not ok then
        print("|cff1B6B57Loot-Historie|r: |cffff5555Fehler in den Einstellungen: " .. tostring(fehler) .. "|r")
    end
end

function Einstellungen.Waehle(id)
    if not Seiten[id] then return end
    aktuelleSeite = id
    loeschenBereit = nil
    scroll:Zurueck()
    Einstellungen.Aktualisieren()
end

function Einstellungen.Zeigen(id)
    if not win then fensterBauen() end
    if id and Seiten[id] then aktuelleSeite = id end
    win:Show()
    Einstellungen.Aktualisieren()
end

function Einstellungen.Verstecken()
    if win then win:Hide() end
end

function Einstellungen.Umschalten()
    if win and win:IsShown() then win:Hide() else Einstellungen.Zeigen() end
end

function Einstellungen.Sichtbar()
    return win and win:IsShown() and true or false
end

return ns
