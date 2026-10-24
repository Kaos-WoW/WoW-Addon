--[[----------------------------------------------------------------------
    Einstellungen.lua  —  Das Einstellungsfenster (Look wie KaosUI)

    Ein eigenes Fenster neben der Uebersicht: Kopf mit Logo und Version,
    Seitenleiste, Karten mit Zeilen (Text und Erklaerung links, Schalter,
    Segmentwahl oder Knopf rechts), Fussleiste.

    Drei Seiten:
      * Erfassung          was, wo und von wem aufgezeichnet wird
      * Würfeln & Abgleich  Wuerfelbereiche, Wuerfelfenster, Abgleich
      * Gruppen            Kader und Raidgruppen

    ⚠️ Gelesen und geschrieben wird immer direkt in den Einstellungstisch
    von Erfassung.lua und in Gruppen.lua. Das Fenster haelt keine eigene
    Kopie; sonst liefe es auseinander, sobald jemand den Befehl benutzt.

    ⚠️ Jede Zeile hat `update()`. Aenderungen laufen immer ueber
    `Einstellungen.Aktualisieren()`, das Texte, Zustand und Hoehen neu setzt.
    So gibt es keine Anker zwischen den Zeilen, die sich verschieben koennten.

    ⚠️ Beim ersten Zeigen zeichnete der Client einen Teil der Texte nicht
    (neue Schriftdatei). `Stil.Auffrischen` setzt sie kurz danach neu.
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Einstellungen = {}
ns.Einstellungen = Einstellungen

local S = ns.Stil
local C = S.C

local BREITE, HOEHE = 780, 580
local KOPF, FUSS, SEITE = 44, 40, 190
local KARTE_X, KARTE_Y, KARTE_LUECKE = 14, 12, 10
local STANDARDBREITE = BREITE - 2 - SEITE - 20 - 16 - 10

local win, body, scroll
local Seiten = {}        -- id -> { karten, nav }
local NavKnoepfe = {}
local aktuelleSeite = "erfassung"
local Meldung = {}       -- kurze Rueckmeldungen je Schluessel
local loeschenBereit
local verlaufBereit = false
local gildeResetBereit = false
local letzteMasse = {}

local function d() return ns.Erfassung.Einstellungen() end

local function farbig(c, text) return S.Code(c) .. text .. "|r" end

-- =====================================================================
--  Zeilen
-- =====================================================================

--- ⭐ Ist diese Zeile für diesen Spieler gesperrt? Geteilte Einstellungen (`def.geteilt`) darf nur ändern, wer
--  senden darf; die Rangstufe (`def.geteilt == "wurzel"`) nur Stufe 1 und 2.
local function gesperrt(def)
    if not def.geteilt or not ns.Konfig or not ns.Konfig.Gesperrt then return false end
    return ns.Konfig.Gesperrt(def.geteilt == "wurzel")
end

--- Eine geteilte Einstellung wurde geändert: mit Schreibrecht geht sie nach kurzer Zeit von selbst an alle.
local function geaendert(def)
    if def.geteilt and ns.Konfig and ns.Konfig.AutoSenden then ns.Konfig.AutoSenden() end
end

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
            if gesperrt(def) then return end
            def.set(not sw.an)
            geaendert(def)
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
            if not gesperrt(def) then def.set(wert) geaendert(def) end
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
            if gesperrt(def) then return end
            k.klick()
            geaendert(def)
            Einstellungen.Aktualisieren()
        end)
        r.ctrl, r.ctrlH = b, 24
        function r.bedienen()
            local t = type(k.text) == "function" and k.text() or k.text
            b:SetLabel(t)
            b:SetAktiv((k.aktiv == nil or k.aktiv() ~= false) and not gesperrt(def))
            r.ctrlB = math.ceil(b:GetWidth())
        end

    elseif art == "bereich" then
        -- zwei Zahlen („von" und „bis") und ein Knopf; die Felder zeigen den
        -- gespeicherten Stand, solange man nicht gerade tippt
        local f = CreateFrame("Frame", nil, r)
        local e1 = S.Eingabe(f, 56, 26)
        e1:SetPoint("LEFT", f, "LEFT", 0, 0)
        local bis = S.Text(f, 13, C.mu, "CENTER")
        bis:SetPoint("LEFT", e1, "RIGHT", 4, 0)
        bis:SetWidth(12)
        bis:SetText("–")
        local e2 = S.Eingabe(f, 56, 26)
        e2:SetPoint("LEFT", bis, "RIGHT", 4, 0)
        local b = S.Knopf(f, def.knopf.text, "secondary")
        b:SetPoint("LEFT", e2, "RIGHT", 8, 0)
        local function setzen()
            local a, z = e1:GetText(), e2:GetText()
            e1:ClearFocus()
            e2:ClearFocus()
            if not gesperrt(def) then def.set(a, z) geaendert(def) end
            Einstellungen.Aktualisieren()
        end
        e1:SetScript("OnEnterPressed", setzen)
        e2:SetScript("OnEnterPressed", setzen)
        b:SetScript("OnClick", setzen)
        r.ctrl, r.ctrlH = f, 26
        r.ctrlB = 56 + 4 + 12 + 4 + 56 + 8 + math.ceil(b:GetWidth())
        f:SetSize(r.ctrlB, 26)
        function r.bedienen()
            local x, y = def.get()
            if not e1:HasFocus() then e1:SetText(tostring(x)) end
            if not e2:HasFocus() then e2:SetText(tostring(y)) end
        end

    elseif art == "korrektur" then
        -- ⭐ Korrektur der Leitung: Spieler, Wert (Plus oder Minus) und Pflichtkommentar, zwei Zeilen
        local f = CreateFrame("Frame", nil, r)
        local e1 = S.Eingabe(f, 150, 26)
        e1:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        local e2 = S.Eingabe(f, 64, 26)
        e2:SetPoint("LEFT", e1, "RIGHT", 6, 0)
        local b = S.Knopf(f, def.knopf.text, "secondary")
        b:SetPoint("LEFT", e2, "RIGHT", 8, 0)
        local e3 = S.Eingabe(f, 340, 26)
        e3:SetPoint("TOPLEFT", e1, "BOTTOMLEFT", 0, -6)
        local function setzen()
            local ok = def.knopf.klick(e1:GetText(), e2:GetText(), e3:GetText())
            e1:ClearFocus() e2:ClearFocus() e3:ClearFocus()
            if ok then e1:SetText("") e2:SetText("") e3:SetText("") end
            Einstellungen.Aktualisieren()
        end
        e1:SetScript("OnEnterPressed", setzen)
        e2:SetScript("OnEnterPressed", setzen)
        e3:SetScript("OnEnterPressed", setzen)
        b:SetScript("OnClick", setzen)
        r.ctrl, r.ctrlH, r.ctrlB, r.stapel = f, 58, 340, true
        f:SetSize(340, 58)
        function r.bedienen()
            local v = def.vorbelegung and def.vorbelegung()
            if v and v ~= "" and not e1:HasFocus() then
                e1:SetText(v)
                if def.vorbelegungLeeren then def.vorbelegungLeeren() end
            end
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
            if gesperrt(def) then eb:SetText("") eb:ClearFocus() Einstellungen.Aktualisieren() return end
            k.klick(t)
            geaendert(def)
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
        if gesperrt(def) then
            bes = (bes ~= "" and (bes .. " ") or "") .. S.Code(C.warn) ..
                  (def.geteilt == "wurzel" and L["Gesperrt: nur Gildenmeister und Offiziere (Stufe 1 und 2) dürfen das ändern."]
                                           or L["Gesperrt: nur Gildenränge mit Schreibrecht dürfen das ändern."]) .. "|r"
        end
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

    local seitlich = r.ctrl and not r.stapel
    local cb = (seitlich and (r.ctrlB or 0)) or 0
    local tb = w - (cb > 0 and (cb + 14) or 0)
    if tb < 80 then tb = 80 end
    r.label:SetWidth(tb)
    r.beschr:SetWidth(tb)

    local lh = r.label:IsShown() and r.label:GetStringHeight() or 0
    local bh = r.beschr:IsShown() and (r.beschr:GetStringHeight() + (lh > 0 and 2 or 0)) or 0

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
    if w < 100 then w = STANDARDBREITE end
    P.kind:SetWidth(w)
    letzteMasse.breite = w

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
    letzteMasse.hoehe = y
    -- Die Seite selbst bekommt die echte Hoehe: Ihre Kinder ragen sonst weit
    -- ueber ihre Ausmasse hinaus (Hoehe 1), und der Client zeichnet dann
    -- nicht jeden Text.
    P.kind:SetHeight(math.max(1, y))
    scroll:SetInhaltHoehe(y)
end

-- =====================================================================
--  Inhalt der Seiten
-- =====================================================================

local ORTE = {
    { wert = "raid",     label = L["Schlachtzug"] },
    { wert = "instanz",  label = L["Instanz"] },
    { wert = "ueberall", label = L["Überall"] },
}
local ORT_TEXT = {
    raid     = L["Nur in Schlachtzugsinstanzen."],
    instanz  = L["Auch Fünfergruppen – zum Erproben des Ablaufs."],
    ueberall = L["Ohne Einschränkung; auch Weltdrops und Questbelohnungen zählen."],
}
local QUALITAETEN = {
    { wert = 1, label = L["Gewöhnlich"] }, { wert = 2, label = L["Ungewöhnlich"] },
    { wert = 3, label = L["Selten"] },     { wert = 4, label = L["Episch"] },
    { wert = 5, label = L["Legendär"] },
}
local MODI = {
    { wert = "auto",  label = L["Automatisch"] },
    { wert = "immer", label = L["Immer"] },
    { wert = "nie",   label = L["Nie"] },
}
local MODUS_TEXT = {
    auto  = L["Der Plündermeister zeichnet auf; gibt es keinen, der Raidleiter."],
    immer = L["Dieser Spieler zeichnet auf – egal, wer sonst."],
    nie   = L["Dieser Spieler zeichnet nicht auf, er empfängt nur."],
}

local SENDERANG = {
    { wert = 2, label = string.format(L["bis Stufe %d"], 2) },
    { wert = 3, label = string.format(L["bis Stufe %d"], 3) },
    { wert = 4, label = string.format(L["bis Stufe %d"], 4) },
}

local DAUERN = {
    { wert = 20, label = "20 s" }, { wert = 30, label = "30 s" },
    { wert = 45, label = "45 s" }, { wert = 60, label = "60 s" },
}

local function seiteDaten(P, k)
    zeile(k, { art = "knopf", label = L["Verlauf zurücksetzen"],
        beschr = function()
            if verlaufBereit then
                return farbig(C.warn, L["Nochmal klicken, um den Verlauf wirklich zu leeren."])
            end
            return Meldung.reset or L["Leert die Historie auf diesem Rechner. Einstellungen und Gruppen bleiben, eine Sicherung wird angelegt. Haben andere in der Gruppe die Einträge noch, bringt sie der nächste Abgleich zurück."]
        end,
        knopf = { text = function() return verlaufBereit and L["Wirklich zurücksetzen"] or L["Zurücksetzen"] end,
            klick = function()
                if verlaufBereit then
                    local n = ns.Erfassung.Zuruecksetzen()
                    verlaufBereit = false
                    Meldung.reset = farbig(C.ok, string.format(L["%d Einträge entfernt"], n))
                    if ns.Fenster then ns.Fenster.Aktualisieren() end
                else
                    verlaufBereit = true
                    Meldung.reset = nil
                end
            end } })
    -- ⭐ Gildenweit zurücksetzen: nur Stufe 1 und 2 (gesperrt für alle anderen)
    zeile(k, { geteilt = "wurzel", art = "knopf", label = L["Daten gildenweit zurücksetzen"],
        beschr = function()
            if gildeResetBereit then
                return farbig(C.bad, L["Nochmal klicken: Das löscht die Daten bei ALLEN Gildenmitgliedern mit dem Addon."])
            end
            return Meldung.gildeReset or L["Löscht Historie, Wertungen, Abschlüsse und Anhebungen bei allen Gildenmitgliedern mit dem Addon. Einstellungen, Gruppen und Einteilung bleiben. Das lässt sich nicht zurücknehmen."]
        end,
        knopf = { text = function() return gildeResetBereit and L["Wirklich für alle zurücksetzen"] or L["Für alle zurücksetzen"] end,
            klick = function()
                if gildeResetBereit then
                    gildeResetBereit = false
                    local n, grund = ns.Erfassung.GildenReset()
                    if n then
                        Meldung.gildeReset = farbig(C.ok, string.format(L["%d Einträge entfernt, die Reset-Marke geht an alle."], n))
                                             .. (grund and (" " .. farbig(C.bad, tostring(grund))) or "")
                    else
                        Meldung.gildeReset = farbig(C.bad, tostring(grund))
                    end
                else
                    gildeResetBereit = true
                    Meldung.gildeReset = nil
                end
            end } })
    zeile(k, { art = "knopf", label = L["Sicherung wiederherstellen"],
        sichtbar = function() return ns.Erfassung.SicherungInfo() ~= nil end,
        beschr = function()
            local s = ns.Erfassung.SicherungInfo()
            if not s then return "" end
            return string.format(L["%d Einträge vom %s"], s.n, date(L["%d.%m.%Y"], s.zeit))
        end,
        knopf = { text = L["Wiederherstellen"],
            klick = function()
                local n = ns.Erfassung.Wiederherstellen()
                Meldung.reset = farbig(C.ok, string.format(L["%d Einträge zurückgeholt"], n or 0))
                if ns.Fenster then ns.Fenster.Aktualisieren() end
            end } })
end

local function seiteErfassung(P)
    local k1 = karte(P, L["Aufzeichnen"], L["Was das Addon in die Historie aufnimmt."])
    zeile(k1, { art = "schalter", label = L["Vergaben aufzeichnen"],
        beschr = L["Aus heißt: nichts Neues wird erfasst. Vorhandenes bleibt."],
        get = function() return d().erfassen end,
        set = function(v) d().erfassen = v end })
    zeile(k1, { geteilt = true, art = "schalter", label = L["Eingesteckte Beute des Plündermeisters nicht zählen"],
        beschr = L["Nimmt der Plündermeister Beute selbst auf, um sie später zu verteilen, ist das keine Vergabe. Eingetragen wird erst, wer sie bekommt (Wurf starten → Zuteilen)."],
        get = function() return d().pmEingesteckt ~= false end,
        set = function(v) d().pmEingesteckt = v end })
    zeile(k1, { geteilt = true, art = "schalter", label = L["Nur Ausgewürfeltes zählen"],
        beschr = L["Streng: Ohne Bedarfswurf zugeteilte Stücke fallen heraus."],
        get = function() return d().nurGewuerfelt end,
        set = function(v) d().nurGewuerfelt = v end })

    local k1 = karte(P, L["Nutzung"],
        L["KaosLoot ist nur mit der Beutemethode Plündermeister im Dienst und nur, wenn du zustimmst. Sonst schläft das Addon."])
    zeile(k1, { art = "segment", label = L["KaosLoot in dieser Gruppe nutzen"],
        werte = { { wert = "ja", label = L["Ja"] }, { wert = "nein", label = L["Nein"] } },
        beschr = function()
            local _, grund = ns.Rolle.Aktiv()
            return grund or L["KaosLoot ist aktiv: Es verwaltet die Beuteverteilung."]
        end,
        get = function() return ns.Rolle.Nutzung() or "" end,
        set = function(v)
            if ns.Rolle.Methode() == "master" and IsInGroup and IsInGroup() then ns.Rolle.NutzungSetzen(v) end
        end })

    local k2 = karte(P, L["Wer zeichnet auf"],
        L["Nur einer pro Gruppe führt die Historie, damit nichts doppelt entsteht."])
    zeile(k2, { art = "segment", label = L["Aufzeichner"], werte = MODI,
        beschr = function() return MODUS_TEXT[d().schreiben or "auto"] end,
        get = function() return d().schreiben or "auto" end,
        set = function(v) d().schreiben = v end })
    zeile(k2, { art = "info",
        label = function()
            local darf = ns.Rolle.IchSchreibe()
            return darf and farbig(C.ok, L["Du zeichnest gerade auf"])
                         or farbig(C.warn, L["Du zeichnest gerade nicht auf"])
        end,
        beschr = function()
            local _, grund = ns.Rolle.IchSchreibe()
            local wer = ns.Rolle.AktuellerSchreiber()
            return tostring(grund) .. ((wer and ("  ·  " .. string.format(L["Aufzeichner: %s"], wer))) or "")
        end })

    local k3 = karte(P, L["Was wird erfasst"])
    zeile(k3, { geteilt = true, art = "segment", label = L["Ort"], werte = ORTE,
        beschr = function() return ORT_TEXT[d().ort] or "" end,
        get = function() return d().ort end,
        set = function(v) d().ort = v end })
    zeile(k3, { geteilt = true, art = "segment", label = L["Ab welcher Qualität"], werte = QUALITAETEN, gestapelt = true,
        beschr = L["Auf Stufe 60 fällt in manchen Raids überwiegend Blaues – lieber zu viel erfassen als einen Drop verlieren."],
        get = function() return d().mindestQualitaet end,
        set = function(v) d().mindestQualitaet = v end })

    seiteDaten(P, karte(P, L["Daten"]))
end

--- Eine Zeile mit zwei Zahlen (niedrigster und hoechster Wurf).
local function bereichZeile(k, art, label)
    zeile(k, { geteilt = true, art = "bereich", label = label,
        beschr = function()
            return Meldung.bereich or L["Niedrigster und höchster Wurf. Eingabe mit Enter oder dem Knopf."]
        end,
        get = function()
            local x = ns.Erfassung.Bereiche()[art]
            return x[1], x[2]
        end,
        set = function(a, z)
            local ok, grund = ns.Erfassung.BereichSetzen(art, a, z)
            Meldung.bereich = ok and farbig(C.ok, L["Gespeichert."]) or farbig(C.bad, tostring(grund))
        end,
        knopf = { text = L["Setzen"] } })
end

local function seiteWuerfeln(P)
    -- ⭐ Die Bereiche gelten fuer das eigene Wuerfelfenster und fuer die Erkennung aller Wuerfe.
    local kb = karte(P, L["Würfelbereiche"],
        L["Welche Wurfzahlen als Hauptbedarf und als Zweitbedarf (OS) gelten. Beim Start eines Wurfs gehen sie an alle in der Gruppe."])
    bereichZeile(kb, "haupt", L["Bereich für Hauptbedarf"])
    bereichZeile(kb, "zweit", L["Bereich für Zweitbedarf (OS)"])
    zeile(kb, { geteilt = true, art = "knopf", label = L["Standardbereiche"],
        beschr = function() return string.format(L["Setzt %d-%d für Hauptbedarf und %d-%d für Zweitbedarf zurück."], 1, 100, 1, 99) end,
        knopf = { text = L["Standard"],
            klick = function()
                ns.Erfassung.BereicheSetzen(1, 100, 1, 99)
                Meldung.bereich = nil
            end } })

    local kw = karte(P, L["Würfelfenster"],
        L["Der Plündermeister oder Leiter startet einen Wurf; alle in der Gruppe bekommen ein kleines Fenster zum Würfeln für Hauptbedarf oder Zweitbedarf (OS)."])
    zeile(kw, { geteilt = true, art = "segment", label = L["Dauer eines Wurfs"], werte = DAUERN,
        beschr = L["Danach endet der Wurf von selbst. Im Startdialog lässt sich die Zeit für einen einzelnen Wurf frei wählen und wird dann zum neuen Standard."],
        get = function() return ns.Wurf.Dauer() end,
        set = function(v) d().wurfDauer = v end })
    zeile(kw, { geteilt = true, art = "schalter", label = L["Wurf und Vergabe im Gruppenchat ansagen"],
        beschr = L["Beim Wurfbeginn schreibt der Starter eine Zeile in den Raid- oder Gruppenchat (damit auch Spieler ohne Addon mitwürfeln), und der Aufzeichner meldet jede eingetragene Vergabe."],
        get = function() return d().ansagen ~= false end,
        set = function(v) d().ansagen = v end })
    zeile(kw, { art = "schalter", label = L["Startdialog beim Plündern selbst öffnen"],
        beschr = L["Als Plündermeister geht der Dialog zum Wurf starten auf, sobald das Beutefenster etwas Verteilbares zeigt."],
        get = function() return d().startAuto ~= false end,
        set = function(v) d().startAuto = v end })
    zeile(kw, { art = "knopf", label = L["Wurf starten"],
        beschr = L["Öffnet den Dialog: Gegenstand per Shift-Klick einfügen oder aus der Beute wählen. Auch: /kl wurf <Link>."],
        knopf = { text = L["Öffnen"], art = "primary",
            aktiv = function() return ns.Wurf.DarfStarten() end,
            klick = function() ns.Wurf.Dialog() end } })

    -- ⭐ Verzauberer: An sie geht ein Gegenstand, auf den niemand wuerfelt (Entzaubern).
    local function verz() return ns.Wurf.Verzauberer() end
    local kv = karte(P, L["Verzauberer"],
        L["Spieler mit Verzauberkunst. Würfelt niemand auf einen Gegenstand, wird er zum Entzaubern an einen von ihnen vergeben."])
    for i = 1, 8 do
        zeile(kv, { geteilt = true, art = "knopf",
            sichtbar = function() return verz()[i] ~= nil end,
            label = function() return verz()[i] or "" end,
            beschr = function()
                local n = verz()[i]
                if not n then return "" end
                local da = false
                for _, g in ipairs(ns.Rolle.Namen()) do
                    if ns.Kern.GleicherSpieler(g, n) then da = true break end
                end
                return da and L["in der Gruppe"] or L["nicht in der Gruppe"]
            end,
            knopf = { text = L["Entfernen"], klick = function() ns.Wurf.VerzaubererEntfernen(i) end } })
    end
    zeile(kv, { geteilt = true, art = "eingabe", label = L["Verzauberer hinzufügen"],
        beschr = function()
            return Meldung.verz or L["Name eingeben, mit Nachnamen falls vorhanden. Mehrere mit Komma."]
        end,
        knopf = { text = L["Hinzufügen"],
            klick = function(text)
                local n = ns.Wurf.VerzaubererHinzufuegen(text)
                Meldung.verz = farbig(n > 0 and C.ok or C.warn, string.format(L["%d ergänzt"], n))
            end } })

    local kf = karte(P, L["Fenster"])
    zeile(kf, { art = "schalter", label = L["Bei Wurfbeginn selbst öffnen"],
        beschr = L["Die Übersicht springt auf, sobald der erste Bedarfswurf fällt."],
        get = function() return ns.Fenster.AutoOeffnen() end,
        set = function(v) ns.Fenster.AutoSetzen(v) end })

    -- ⭐ Einstellungen teilen (Konfig.lua): nur einer stellt ein, alle bekommen es
    local ks = karte(P, L["Einstellungen teilen"],
        L["Gildenmeister und Offiziere (Stufe 1 und 2) stellen das Addon ein und schicken es an alle: Würfelbereiche, Würfelzeit, Verzauberer, Gruppen samt ihren Raidtagen und die Erfassungs-Einstellungen. Wer nicht schreiben darf, bekommt sie nur zum Lesen und beim Anmelden wieder auf den offiziellen Stand gesetzt. Persönliches (Fenster, wer aufzeichnet) bleibt unberührt."])
    zeile(ks, { art = "info",
        label = function() return ns.Konfig.Status()[1] end,
        beschr = function() return ns.Konfig.Status()[2] end })
    zeile(ks, { art = "schalter", label = L["Einstellungen der Gildenleitung übernehmen"],
        beschr = L["Aus: Nachrichten mit geteilten Einstellungen werden ignoriert."],
        get = function() return d().konfigAnnehmen ~= false end,
        set = function(v) d().konfigAnnehmen = v end })
    zeile(ks, { art = "segment", geteilt = "wurzel", label = L["Wer darf Einstellungen senden"], werte = SENDERANG,
        beschr = function()
            local R = ns.Gruppen.Raenge()
            if not R then return L["Gildenliste nicht geladen"] end
            local namen = {}
            for i = 1, math.min(ns.Konfig.RangGrenze(), #R) do namen[#namen + 1] = R[i].name end
            return string.format(L["Das sind: %s. Gilt für alle, sobald es geteilt wird."], table.concat(namen, ", "))
        end,
        get = function() return ns.Konfig.RangGrenze() end,
        set = function(v) d().konfigRang = v end })
    zeile(ks, { art = "knopf", label = L["An alle senden"],
        beschr = function()
            if Meldung.konfig then return Meldung.konfig end
            if ns.Konfig.DarfSenden() then
                return L["Schickt deine Einstellungen an alle Gildenmitglieder, die online sind. Wer später kommt, fragt beim Anmelden nach."]
            end
            return L["Nur die Gildenleitung darf senden (siehe oben)."]
        end,
        knopf = { text = L["Senden"], art = "primary",
            aktiv = function() return ns.Konfig.DarfSenden() end,
            klick = function()
                local n, grund = ns.Konfig.Senden()
                Meldung.konfig = n and farbig(C.ok, string.format(L["Gesendet (%d Nachrichten)."], n))
                                    or farbig(C.bad, tostring(grund))
            end } })
    zeile(ks, { art = "knopf", label = L["Jetzt nachfragen"],
        beschr = L["Fragt, ob jemand neuere geteilte Einstellungen hat, und übernimmt sie."],
        knopf = { text = L["Nachfragen"],
            klick = function()
                ns.Konfig.Anfragen("GUILD")
                Meldung.konfig = farbig(C.ok, L["Angefragt."])
            end } })
    zeile(ks, { art = "knopf", label = L["Letzte Übernahme zurücknehmen"],
        sichtbar = function() return d().konfigAlt ~= nil end,
        beschr = L["Stellt die Einstellungen vor der letzten Übernahme wieder her."],
        knopf = { text = L["Zurücknehmen"],
            klick = function()
                local ok, grund = ns.Konfig.Zurueck()
                Meldung.konfig = ok and farbig(C.ok, L["Wiederhergestellt."]) or farbig(C.bad, tostring(grund))
            end } })

    local k3 = karte(P, L["Abgleich"],
        L["Führt die Historien einer Gruppe zusammen – es kommt nur hinzu, nichts wird überschrieben."])
    zeile(k3, { art = "info",
        label = function()
            local n = ns.Abgleich.Stand()
            return string.format(L["%d Einträge bei dir"], n)
        end,
        beschr = function()
            local bekannte = 0
            for _ in pairs(ns.Abgleich.Bekannte()) do bekannte = bekannte + 1 end
            local abw = #ns.Abgleich.Abweichend
            return string.format(L["%d Mitspieler mit dem Addon erkannt"], bekannte) .. "  ·  " ..
                (abw > 0 and farbig(C.warn, string.format(L["%d weichen ab"], abw)) or L["keine Abweichung bekannt"])
        end })
    zeile(k3, { geteilt = true, art = "schalter", label = L["Automatisch abgleichen"],
        beschr = L["Weichen die Historien in der Gruppe ab, gleicht der Leiter oder Plündermeister von selbst ab. Aus: es erscheint nur ein Hinweis."],
        get = function() return d().autoAbgleich ~= false end,
        set = function(v) d().autoAbgleich = v end })
    zeile(k3, { art = "schalter", label = L["Mit der Gildenleitung abgleichen"],
        beschr = L["Wer Schreibrecht hat, gleicht Historie und Wertungen gildenweit mit anderen Spielern mit Schreibrecht ab, auch ohne gemeinsame Gruppe. Danach aktualisiert er seine Gruppe wie bisher."],
        get = function() return d().leitungSync ~= false end,
        set = function(v) d().leitungSync = v end })
    zeile(k3, { art = "knopf", label = L["Jetzt abgleichen"],
        beschr = function()
            return Meldung.abgleich or L["Nur Leiter, Assistenten und der Plündermeister dürfen abgleichen."]
        end,
        knopf = { text = L["Abgleichen"], art = "primary",
            klick = function()
                local ok, grund = ns.Abgleich.Starten()
                Meldung.abgleich = ok and farbig(C.ok, L["Gestartet – das Ergebnis steht im Chat."])
                                       or farbig(C.bad, tostring(grund))
            end } })
end

local function seiteGruppen(P)
    local G = ns.Gruppen

    -- ⭐ Seit dem 22.10.2026: Gruppen sind nur noch Namen; wer wann in welcher Gruppe spielt, steht in der Einteilung
    -- (einmal je Raid-ID). Den Raidkader gibt es einmal, unabhängig von den Gruppen.
    local k1 = karte(P, L["Gruppen"],
        L["Eine Gruppe ist ein Raid mit eigenem Namen, zum Beispiel 40er oder 10er. Wer in welcher Gruppe spielt, stellst du unter „Einteilung“ ein, einmal je Raid-ID."])
    for i = 1, 8 do
        zeile(k1, { geteilt = true, art = "knopf",
            sichtbar = function() return G.Namen()[i] ~= nil end,
            label = function()
                local n = G.Namen()[i]
                return n and string.format(L["[%der] %s"], G.Groesse(n), n) or ""
            end,
            beschr = function()
                local name = G.Namen()[i]
                if not name then return "" end
                if loeschenBereit == name then
                    return farbig(C.warn, L["Nochmal klicken, um die Gruppe wirklich zu löschen."])
                end
                return string.format(L["%d in dieser Raid-ID eingeteilt"], #G.EinteilungListe(G.IdStart(G.EinteilungTag(0)), name))
            end,
            knopf = { text = function() return loeschenBereit == G.Namen()[i] and L["Wirklich löschen"] or L["Löschen"] end,
                klick = function()
                    local n = G.Namen()[i]
                    if not n then return end
                    if loeschenBereit == n then
                        G.Loeschen(n)
                        loeschenBereit = nil
                    else
                        loeschenBereit = n
                    end
                end } })
    end
    zeile(k1, { art = "info", sichtbar = function() return #G.Namen() == 0 end,
        label = L["Noch keine Gruppe"],
        beschr = L["Unten eine anlegen, zum Beispiel „40er“ oder „10er“."] })

    local k4 = karte(P, L["Neue Gruppe"])
    local neueGroesse = 40
    zeile(k4, { art = "segment", label = L["Raid-Größe"],
        werte = {
            { wert = 10, label = L["10er"] },
            { wert = 20, label = L["20er"] },
            { wert = 40, label = L["40er"] },
        },
        beschr = L["10er, 20er oder 40er Raid. Spieler können je Größe in einer Gruppe eingeteilt sein."],
        get = function() return neueGroesse end,
        set = function(v) neueGroesse = v end })
    zeile(k4, { geteilt = true, art = "eingabe", label = L["Name"],
        beschr = function()
            return Meldung.neu or L["Höchstens 40 Zeichen, ohne Semikolon."]
        end,
        knopf = { text = L["Anlegen"],
            klick = function(text)
                local ok, grund = G.Anlegen(text, neueGroesse)
                Meldung.neu = ok and farbig(C.ok, L["Angelegt."]) or farbig(C.bad, tostring(grund))
            end } })

    -- ⭐ Manuelle Anhebung (die automatische ist aus, Entscheid 19.10.2026)
    local ka = karte(P, L["Anhebung"],
        L["Die Anhebung gibt es nicht mehr automatisch. Die Raid- oder Gildenleitung kann hier einen Spieler anheben, der im Raid ist: Er kommt auf den Niedrigsten der anderen Kaderspieler im Raid plus 2 (nie nach unten)."])
    zeile(ka, { art = "eingabe", label = L["Spieler anheben"],
        beschr = function()
            return Meldung.anhebung or L["Name des Spielers eintragen und „Anheben“ klicken."]
        end,
        knopf = { text = L["Anheben"],
            klick = function(text)
                local id, ziel, diff = ns.Anwesenheit.AnhebungSetzen(text)
                if id then
                    Meldung.anhebung = farbig(C.ok, string.format(L["%s angehoben: +%.1f auf %.1f."], tostring(text), diff, ziel))
                    if ns.Fenster then ns.Fenster.Aktualisieren() end
                else
                    Meldung.anhebung = farbig(C.bad, tostring(ziel))
                end
            end } })

    -- ⭐ Einladen per Flüstern (persönlich, nicht geteilt)
    local ke = karte(P, L["Einladen per Flüstern"],
        L["Wer dir genau dieses Stichwort flüstert, wird in deine Gruppe eingeladen. Das gilt nur für dich und wird nicht geteilt."])
    zeile(ke, { art = "schalter", label = L["Einladen per Flüstern"],
        get = function() local _, an = ns.Anwesenheit.EinladeWort() return an end,
        set = function(v) ns.Anwesenheit.EinladeAn(v) end })
    zeile(ke, { art = "eingabe", label = L["Stichwort"],
        beschr = function()
            local wort = ns.Anwesenheit.EinladeWort()
            return Meldung.einlade or string.format(L["Aktuell: „%s“. Neues Stichwort eintragen und „Setzen“ klicken."], wort)
        end,
        knopf = { text = L["Setzen"],
            klick = function(text)
                local ok, grund = ns.Anwesenheit.EinladeWortSetzen(text)
                Meldung.einlade = ok and farbig(C.ok, L["Stichwort gespeichert."]) or farbig(C.bad, tostring(grund))
            end } })

    -- ⭐ Der Raidkader: alle Gildenmitglieder der gewählten Ränge; wird beim Anmelden von selbst eingelesen
    local kk = karte(P, L["Raidkader"],
        L["Alle Gildenmitglieder der gewählten Ränge bilden den Raidkader, aus dem du in der Einteilung die Gruppen zusammenstellst. Er wird beim Anmelden von selbst eingelesen; die Ränge gelten für alle, sobald sie geteilt werden."])
    zeile(kk, { art = "info", sichtbar = function() return not G.Raenge() end,
        label = L["Gildenliste nicht geladen"],
        beschr = function() local _, grund = G.Raenge() return tostring(grund or "") end })
    for i = 1, 10 do
        zeile(kk, { geteilt = true, art = "schalter",
            sichtbar = function() local R = G.Raenge() return R ~= nil and R[i] ~= nil end,
            label = function() local R = G.Raenge() return R and R[i] and R[i].name or "" end,
            get = function()
                local R = G.Raenge()
                return R ~= nil and R[i] ~= nil and G.RaidkaderRangGewaehlt(R[i].index)
            end,
            set = function(v)
                local R = G.Raenge()
                if not (R and R[i]) then return end
                G.RaidkaderRangSetzen(R[i].index, v)
                pcall(G.RaidkaderAuto)
            end })
    end
    zeile(kk, { art = "knopf", label = function()
            local liste = G.Raidkader()
            return string.format(L["%d im Raidkader"], #liste)
        end,
        beschr = function()
            return Meldung.kader or L["Liest die Gildenliste neu ein. Wer den Rang oder die Gilde verlassen hat, fällt heraus."]
        end,
        knopf = { text = L["Synchronisieren"], art = "primary",
            aktiv = function() return G.RaidkaderRang() ~= nil end,
            klick = function()
                local n, grund = G.RaidkaderSync()
                Meldung.kader = n and farbig(C.ok, string.format(L["Raidkader eingelesen: %d Mitglieder."], n))
                                  or farbig(C.bad, tostring(grund))
            end } })

    -- ⭐ Die Raid-ID: eine Woche, beginnt an einem einstellbaren Wochentag
    local kw = karte(P, L["Raid-ID"],
        L["Eine Raid-ID umfasst eine Woche; die Einteilung gilt für die ganze ID. Hier steht, an welchem Wochentag eine neue beginnt (Standard Mittwoch). Gilt für alle, sobald es geteilt wird."])
    local tage = {}
    for _, wd in ipairs(G.RaidtageFolge()) do tage[#tage + 1] = { wert = wd, label = G.RaidtagName(wd) } end
    zeile(kw, { geteilt = true, art = "segment", label = L["Neue Raid-ID beginnt am"], werte = tage,
        get = function() return G.IdWechsel() end,
        set = function(v) G.IdWechselSetzen(v) end })
end

local function seiteVerteilung(P)
    local V = ns.Verteilung

    local kv = karte(P, L["Verfahren"], L["Wie die Wertung zustande kommt. Die Leitung stellt es ein, es gilt für alle."])
    zeile(kv, { geteilt = true, art = "segment", gestapelt = true, label = L["Verfahren"],
        werte = { { wert = "zuschlag", label = L["Punkte mit Zuschlägen"] }, { wert = "abend", label = L["Items pro Abend"] } },
        get = function() return V.Verfahren() end,
        set = function(v) V.VerfahrenSetzen(v) if ns.Fenster then ns.Fenster.Aktualisieren() end end })
    zeile(kv, { art = "info", label = "",
        beschr = function()
            if V.ProAbend() then
                return L["Wertung = Items pro besuchtem Abend der letzten Raid-IDs. Wer pro Abend bisher am wenigsten bekommen hat, ist zuerst dran. Fehlen kostet nichts, und wer oft da ist, wird nicht schlechter gestellt. Neue und Rückkehrer starten am Gildenschnitt."]
            end
            return L["Wertung = Main-Items plus Zuschläge für verpasste Abende (plus Anhebungen). Wer die niedrigste Wertung hat, ist zuerst dran."]
        end })
    zeile(kv, { geteilt = true, art = "segment", label = L["Zeitfenster"],
        beschr = L["Wie viele Raid-IDs zurückgeschaut wird. Das Fenster gleitet: Jede Woche fällt die älteste heraus, es gibt keinen Reset."],
        sichtbar = function() return V.ProAbend() end,
        werte = { { wert = 4, label = "4" }, { wert = 6, label = "6" }, { wert = 8, label = "8" }, { wert = 10, label = "10" }, { wert = 12, label = "12" } },
        get = function() return V.Fenster() end, set = function(v) V.FensterSetzen(v) end })
    zeile(kv, { geteilt = true, art = "segment", label = L["Glättung"],
        beschr = L["Neue Spieler und Rückkehrer starten am Gildenschnitt: So viele Pseudo-Abende zählen mit. 0 schaltet es aus."],
        sichtbar = function() return V.ProAbend() end,
        werte = { { wert = 0, label = "0" }, { wert = 2, label = "2" }, { wert = 4, label = "4" }, { wert = 6, label = "6" } },
        get = function() return V.Glaettung() end, set = function(v) V.GlaettungSetzen(v) end })

    local kh = karte(P, L["Heute schon ein Item"],
        L["Gilt in beiden Verfahren. Wer an diesem Abend schon ein Main-Item bekommen hat, steht bei den weiteren Items hinter denen, die noch keins haben."])
    zeile(kh, { geteilt = true, art = "segment", label = L["Regel"], gestapelt = true,
        beschr = function()
            local r = V.Regel()
            if r == "streng" then return L["Streng: Erst bekommt jeder ein Item, bevor jemand ein zweites bekommt. Die Wertung ordnet nur noch die Reihenfolge innerhalb einer Runde."] end
            if r == "leicht" then return L["Leicht: Jedes Item von heute zählt für den Rest des Abends etwas extra, die Wertung bleibt entscheidend."] end
            return L["Aus: Nur die Wertung entscheidet, auch wenn jemand heute schon ein Item hat."]
        end,
        werte = { { wert = "aus", label = L["Aus"] }, { wert = "leicht", label = L["Leicht"] }, { wert = "streng", label = L["Streng"] } },
        get = function() return V.Regel() end, set = function(v) V.RegelSetzen(v) end })

    local kk = karte(P, L["Korrektur"],
        L["Für besondere Fälle: ein Wert mit Kommentar, zum Beispiel unangekündigt nicht erschienen, besondere Leistung oder Legendary außerhalb des Systems. Plus zählt wie ein erhaltenes Item, Minus wie ein verrechnetes. Alle sehen die Korrektur im Spielerdetail; sie zählt wie ein Item aus ihrer Raid-ID. Nur die Leitung darf eintragen."])
    zeile(kk, { art = "korrektur", label = L["Korrektur eintragen"],
        beschr = function()
            return Meldung.korrektur or L["Name, Wert (zum Beispiel 1 oder -0,5) und ein Kommentar, dann „Eintragen“."]
        end,
        knopf = { text = L["Eintragen"],
            klick = function(name, wert, text)
                local w = tonumber((tostring(wert or ""):gsub(",", ".")))
                local id, grund = ns.Anwesenheit.KorrekturBuchen(name, w, text)
                if id then
                    Meldung.korrektur = farbig(C.ok, string.format(L["Korrektur für %s eingetragen."], tostring(name)))
                    if ns.Fenster then ns.Fenster.Aktualisieren() end
                    return true
                end
                Meldung.korrektur = farbig(C.bad, tostring(grund))
                return false
            end },
        vorbelegung = function() return Meldung.korrekturName end,
        vorbelegungLeeren = function() Meldung.korrekturName = nil end })
end

local NAV = {
    { id = "erfassung", label = L["Erfassung"],         icon = "settings.tga",
      titel = L["Erfassung"], beschr = L["Was, wo und von wem aufgezeichnet wird."], bauen = seiteErfassung },
    { id = "wuerfeln",  label = L["Würfeln & Abgleich"], icon = "rotate.tga",
      titel = L["Würfeln & Abgleich"], beschr = L["Würfelbereiche, Würfelfenster und der Abgleich zwischen den Spielern."], bauen = seiteWuerfeln },
    { id = "verteilung", label = L["Verteilung"],       icon = "settings.tga",
      titel = L["Verteilung"], beschr = L["Wie die Wertung zustande kommt, die Regel für den Abend und Korrekturen der Leitung."], bauen = seiteVerteilung },
    { id = "gruppen",   label = L["Gruppen"],           icon = "users-group.tga",
      titel = L["Gruppen"], beschr = L["Gruppen, Raidkader und Raid-ID für verschiedene Raidgrößen."], bauen = seiteGruppen },
}

-- =====================================================================
--  Fenster
-- =====================================================================

local function version()
    local f = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
    if not f then return "?" end
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
    kopf:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        if win.speichern then win.speichern() end
    end)

    local logo = CreateFrame("Frame", nil, kopf)
    logo:SetSize(22, 22)
    logo:SetPoint("LEFT", kopf, "LEFT", 12, 0)
    S.Form(logo, 5, C.ac)
    local l = S.Text(logo, 13, C.white, "CENTER")
    l:SetPoint("CENTER", 1, 0)
    l:SetText("F")

    local name = S.Text(kopf, 14, C.tx, "LEFT")
    name:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    name:SetText("KaosLoot")

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
    if ns.Neu then ns.Neu.Marker(b, nav.id, -8) end          -- „!“, solange auf der Seite etwas Neues steht

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
    win = CreateFrame("Frame", "FairshareEinstellungen", UIParent)
    -- ⭐ Immer UEBER der Uebersicht: andere Ebene UND hoeher gelegene
    -- Rahmenstufe. Nur die Ebene zu waehlen genuegt nicht — die Unterelemente
    -- beider Fenster haben sonst gleiche Stufen und mischen sich beim
    -- Ueberlappen. Die Stufe muss vor dem Anlegen der Kinder stehen.
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetFrameLevel(200)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    S.Kasten(win, 10, C.bg, C.ln)
    win:Hide()
    tinsert(UISpecialFrames, "FairshareEinstellungen")   -- ESC schliesst

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
    gl:SetText(L["Einstellungen"])
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
    -- Aendert sich die Breite, rechnen die Karten neu.
    scroll.beiGroesse = function() Einstellungen.Aktualisieren() end

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

    local tests = S.Knopf(fuss, L["Selbsttests"], "secondary", 24)
    tests:SetPoint("RIGHT", fuss, "RIGHT", -12, 0)
    tests:SetScript("OnClick", function()
        if ns.Tests then ns.Tests.Alle() end
    end)

    -- Seiten bauen: je ein Kind-Frame im Bildlauf, nur die aktuelle sichtbar
    for _, nav in ipairs(NAV) do
        local P = { karten = {}, kind = CreateFrame("Frame", nil, scroll.kind), nav = nav }
        P.kind:SetPoint("TOPLEFT", scroll.kind, "TOPLEFT", 0, 0)
        P.kind:SetSize(STANDARDBREITE, 1)
        P.kind:Hide()
        nav.bauen(P)
        Seiten[nav.id] = P
    end

    -- Groesse und Lage merken, Griff unten rechts. Nach dem Aufbau, damit
    -- alle Kinder schon da sind.
    S.Verstellbar(win, "einstellungen", { b = BREITE, h = HOEHE, minB = 640, minH = 420,
        maxB = 1200, maxH = 1000, dx = 40, dy = 0 }, function() Einstellungen.Aktualisieren() end)

    win:SetScript("OnShow", function()
        Einstellungen.Aktualisieren()
        -- Erste Fassung der Schrift nachziehen: ein neuer Client zeichnet
        -- Text, der vor dem Laden der Schriftdatei gesetzt wurde, nicht.
        if C_Timer then
            C_Timer.After(0.1, function() S.Auffrischen(); Einstellungen.Aktualisieren() end)
            C_Timer.After(0.6, function() S.Auffrischen() end)
            S.AuffrischenBisFertig()
        end
    end)
end

-- =====================================================================
--  Steuerung
-- =====================================================================

function Einstellungen.Aktualisieren()
    if not win or not win:IsShown() then return end
    local ok, fehler = pcall(function()
        local P = Seiten[aktuelleSeite]
        if not P then return end
        if ns.Neu then ns.Neu.SeiteGesehen(aktuelleSeite) end          -- das „!“ der Seite verschwindet beim Besuch

        for id, Q in pairs(Seiten) do Q.kind:SetShown(id == aktuelleSeite) end
        setzeNav(aktuelleSeite)

        kruemel:SetText(L["Einstellungen"] .. "  ›  " .. P.nav.label)
        titel:SetText(P.nav.titel)
        beschr:SetText(P.nav.beschr)

        seiteMessen(aktuelleSeite)

        local darf, grund = ns.Rolle.IchSchreibe()
        fussText:SetText((darf and L["Du zeichnest auf"] or L["Du zeichnest nicht auf"]) ..
            "  ·  " .. tostring(grund))
    end)
    if not ok then
        print("|cff1B6B57KaosLoot|r: |cffff5555" ..
            string.format(L["Fehler in den Einstellungen: %s"], tostring(fehler)) .. "|r")
    end
end

function Einstellungen.Waehle(id)
    if not Seiten[id] then return end
    aktuelleSeite = id
    Meldung.bereich, Meldung.verz, Meldung.konfig, Meldung.einlade = nil, nil, nil, nil
    loeschenBereit = nil
    verlaufBereit = false
    scroll:Zurueck()
    Einstellungen.Aktualisieren()
    if C_Timer then C_Timer.After(0.1, function() S.Auffrischen() end) end
end

--- Oeffnet die Seite Verteilung mit dem Namen in der Korrektur (aus dem Spielerdetail).
function Einstellungen.KorrekturFuer(name)
    Meldung.korrekturName = ns.Kern.Anzeigename(name)
    Meldung.korrektur = nil
    Einstellungen.Zeigen("verteilung")
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

--- Diagnose: was weiss der Client ueber unsere Textfelder?
--  Fuer den Fall „Text steht im Layout, wird aber nicht gezeichnet".
function Einstellungen.Diagnose()
    local zeilen = {}
    local function z(t) zeilen[#zeilen + 1] = t end

    z(string.format("Sprache: %s  Locale: %s", ns.Sprache or "?", tostring(GetLocale and GetLocale())))
    z(string.format("Textfelder des Baukastens: %d", S.AnzahlTexte()))
    z(string.format("Seite: %s  Breite %s  Hoehe %s", aktuelleSeite,
        tostring(letzteMasse.breite), tostring(letzteMasse.hoehe)))

    local P = Seiten[aktuelleSeite]
    if not P then z("keine Seite") return zeilen end

    for ci, c in ipairs(P.karten) do
        z(string.format("Karte %d: sichtbar=%s Titel=%q H=%s", ci, tostring(c:IsShown()),
            tostring(c.titel:GetText()), tostring(c:GetHeight())))
        for ri, r in ipairs(c.zeilen) do
            if r:IsShown() then
                local fs = r.label
                local pfad, groesse = fs:GetFont()
                local rot, gruen, blau, alpha = fs:GetTextColor()
                z(string.format("  Zeile %d: %q  sichtbar=%s w=%s h=%s eff.alpha=%s font=%s/%s farbe=%.2f,%.2f,%.2f,%.2f",
                    ri, tostring(fs:GetText()), tostring(fs:IsVisible()),
                    tostring(fs:GetStringWidth()), tostring(fs:GetStringHeight()),
                    tostring(fs:GetEffectiveAlpha()), tostring(pfad and pfad:match("[^\\]+$")), tostring(groesse),
                    rot or -1, gruen or -1, blau or -1, alpha or -1))
                if ri >= 2 then break end
            end
        end
        if ci >= 2 then break end
    end
    return zeilen
end

return ns
