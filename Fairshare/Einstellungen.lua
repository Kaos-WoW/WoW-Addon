--[[----------------------------------------------------------------------
    Einstellungen.lua  —  Das Einstellungsfenster (Look wie KaosUI)

    Ein eigenes Fenster neben der Uebersicht: Kopf mit Logo und Version,
    Seitenleiste, Karten mit Zeilen (Text und Erklaerung links, Schalter,
    Segmentwahl oder Knopf rechts), Fussleiste.

    Drei Seiten:
      * Erfassung          was, wo und von wem aufgezeichnet wird
      * Gargul & Abgleich  Wuerfelbereiche, Import, Fenster, Abgleich
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
local letzteMasse = {}

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

local function seiteErfassung(P)
    local k1 = karte(P, L["Aufzeichnen"], L["Was das Addon in die Historie aufnimmt."])
    zeile(k1, { art = "schalter", label = L["Vergaben aufzeichnen"],
        beschr = L["Aus heißt: nichts Neues wird erfasst. Vorhandenes bleibt."],
        get = function() return d().erfassen end,
        set = function(v) d().erfassen = v end })
    zeile(k1, { art = "schalter", label = L["Nur Ausgewürfeltes zählen"],
        beschr = L["Streng: Ohne Bedarfswurf zugeteilte Stücke fallen heraus."],
        get = function() return d().nurGewuerfelt end,
        set = function(v) d().nurGewuerfelt = v end })

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
    zeile(k3, { art = "segment", label = L["Ort"], werte = ORTE,
        beschr = function() return ORT_TEXT[d().ort] or "" end,
        get = function() return d().ort end,
        set = function(v) d().ort = v end })
    zeile(k3, { art = "segment", label = L["Ab welcher Qualität"], werte = QUALITAETEN, gestapelt = true,
        beschr = L["Auf Stufe 60 fällt in manchen Raids überwiegend Blaues – lieber zu viel erfassen als einen Drop verlieren."],
        get = function() return d().mindestQualitaet end,
        set = function(v) d().mindestQualitaet = v end })
end

local function seiteGargul(P)
    local k1 = karte(P, "Gargul", L["Gewürfelt wird 100 für Hauptbedarf und 50 für Zweitbedarf."])
    zeile(k1, { art = "knopf", label = L["Würfelbereiche"],
        beschr = function()
            local B, grund = ns.Quelle.GargulBereiche()
            if not B then
                return string.format(L["Gargul ist nicht bereit (%s). Ohne Gargul liest das Addon die Würfe selbst aus dem Chat."],
                    tostring(grund))
            end
            local liste = table.concat(B.bereiche, ", ")
            if B.ok then
                return farbig(C.ok, L["Stimmen."]) .. "  " .. string.format(L["Gargul kennt: %s"], liste)
            end
            return farbig(C.bad, L["Passen nicht."]) .. "  " .. string.format(L["Gargul kennt: %s"], liste) ..
                ". " .. L["Erwartet werden 1-100 und 1-50, sonst wird der Zweitbedarf nicht erkannt."]
        end,
        knopf = { text = L["Auf 100/50 stellen"], art = "primary",
            aktiv = function()
                local B = ns.Quelle.GargulBereiche()
                return B ~= nil and not B.ok
            end,
            klick = function() ns.Quelle.GargulBereicheSetzen() end } })
    zeile(k1, { art = "knopf", label = L["Bisherige Vergaben übernehmen"],
        beschr = function()
            return Meldung.import or L["Holt Garguls bisherige Aufzeichnungen in die eigene Historie. Mehrfaches Übernehmen ändert nichts."]
        end,
        knopf = { text = L["Übernehmen"],
            klick = function()
                local neu, doppelt = ns.Quelle.GargulImport()
                if not neu then
                    Meldung.import = farbig(C.bad, tostring(doppelt))
                else
                    Meldung.import = farbig(C.ok, string.format(L["%d übernommen"], neu)) ..
                        (doppelt > 0 and (", " .. string.format(L["%d schon vorhanden"], doppelt)) or "")
                end
                if ns.Fenster then ns.Fenster.Aktualisieren() end
            end } })

    local k2 = karte(P, L["Fenster"])
    zeile(k2, { art = "schalter", label = L["Bei Wurfbeginn selbst öffnen"],
        beschr = L["Die Übersicht springt auf, sobald der erste Bedarfswurf fällt."],
        get = function() return ns.Fenster.AutoOeffnen() end,
        set = function(v) ns.Fenster.AutoSetzen(v) end })

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
    zeile(k3, { art = "schalter", label = L["Automatisch abgleichen"],
        beschr = L["Weichen die Historien in der Gruppe ab, gleicht der Leiter oder Plündermeister von selbst ab. Aus: es erscheint nur ein Hinweis."],
        get = function() return d().autoAbgleich ~= false end,
        set = function(v) d().autoAbgleich = v end })
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

    local k1 = karte(P, L["Gruppen"],
        L["Eine Gruppe ist eine Beschriftung (zum Beispiel 40er oder 10er) mit einem Kader. In einer Gruppe zeigt die Übersicht nur die Spieler, die bei dir sind; ohne Gruppe den Kader."])
    for i = 1, 8 do
        zeile(k1, { art = "knopf",
            sichtbar = function() return G.Namen()[i] ~= nil end,
            label = function() return G.Namen()[i] or "" end,
            beschr = function()
                local g = G.Holen(G.Namen()[i])
                if not g then return "" end
                return string.format(L["%d Namen im Kader"], #G.Namensliste(g))
            end,
            knopf = { text = function() return G.Namen()[i] == G.AktivName() and L["Aktiv"] or L["Aktivieren"] end,
                art = "primary",
                aktiv = function() return G.Namen()[i] ~= G.AktivName() end,
                klick = function()
                    loeschenBereit = nil
                    G.Aktivieren(G.Namen()[i])
                end } })
    end
    zeile(k1, { art = "info", sichtbar = function() return #G.Namen() == 0 end,
        label = L["Noch keine Gruppe"],
        beschr = L["Unten eine anlegen, zum Beispiel „40er“ oder „10er“."] })
    zeile(k1, { art = "knopf", sichtbar = function() return G.AktivName() ~= nil end,
        label = L["Keine Gruppe verwenden"],
        beschr = L["Neue Vergaben bekommen dann keine Gruppe, die Liste keine Pflichtnamen."],
        knopf = { text = L["Abwählen"], klick = function() G.Aktivieren(nil) end } })

    local aktiv = function() return G.AktivName() ~= nil end
    local k2 = karte(P, function() return string.format(L["Aktive Gruppe: %s"], tostring(G.AktivName() or "")) end,
        L["Der Kader steht ohne Gruppe in der Liste. In einer Gruppe zählen nur die, die dabei sind."], aktiv)
    zeile(k2, { art = "knopf", label = L["Mitglieder synchronisieren"],
        beschr = function()
            return Meldung.kader or L["Mit gewählten Gildenrängen ist der Kader genau deren Mitglieder: Neue kommen dazu, Ausgetretene fallen weg. Von Hand ergänzte Namen bleiben. Ohne Ränge werden nur Spieler aus deiner Gruppe aufgenommen."]
        end,
        knopf = { text = L["Synchronisieren"], art = "primary",
            klick = function()
                local neu, weg = G.Synchronisieren(G.AktivName())
                if neu then
                    Meldung.kader = farbig(C.ok, string.format(L["%d neu, %d entfernt"], neu, weg or 0))
                else
                    Meldung.kader = farbig(C.bad, tostring(weg))
                end
            end } })
    zeile(k2, { art = "schalter", label = L["Beim Anmelden automatisch synchronisieren"],
        beschr = L["Nur wirksam, wenn unten Gildenränge gewählt sind."],
        get = function() local g = G.Aktiv() return g and g.auto ~= false end,
        set = function(v) local g = G.Aktiv() if g then g.auto = v end end })
    zeile(k2, { art = "eingabe", label = L["Namen hinzufügen"],
        beschr = function()
            return Meldung.namen or L["Mit Komma trennen – Nachnamen enthalten Leerzeichen. Diese Namen bleiben immer erhalten."]
        end,
        knopf = { text = L["Hinzufügen"],
            klick = function(text)
                local n = G.KaderErgaenzen(G.AktivName(), text)
                Meldung.namen = farbig(C.ok, string.format(L["%d ergänzt"], n or 0))
            end } })
    zeile(k2, { art = "eingabe", label = L["Name entfernen"],
        beschr = function()
            return Meldung.entfernt or L["Wer nur durch einen Rang im Kader steht, kommt beim nächsten Abgleich zurück – dafür den Rang abwählen."]
        end,
        knopf = { text = L["Entfernen"],
            klick = function(text)
                local ok = G.KaderEntfernen(G.AktivName(), text)
                Meldung.entfernt = ok and farbig(C.ok, L["Entfernt."]) or farbig(C.bad, L["Den Namen gibt es nicht im Kader."])
            end } })
    zeile(k2, { art = "info", label = L["Kader"],
        beschr = function()
            local liste = G.Namensliste(G.Aktiv())
            if #liste == 0 then return L["Noch leer."] end
            local teile = {}
            for i, n in ipairs(liste) do
                if i > 16 then teile[#teile + 1] = "…" break end
                teile[#teile + 1] = n
            end
            return string.format(L["%d Namen: %s"], #liste, table.concat(teile, ", "))
        end })
    zeile(k2, { art = "knopf", label = L["Gruppe löschen"],
        beschr = function()
            return loeschenBereit and farbig(C.warn, L["Nochmal klicken, um die Gruppe wirklich zu löschen."])
                   or L["Die Vergaben bleiben erhalten, sie verlieren nur ihre Gruppe nicht."]
        end,
        knopf = { text = function() return loeschenBereit and L["Wirklich löschen"] or L["Löschen"] end,
            klick = function()
                local name = G.AktivName()
                if loeschenBereit == name then
                    G.Loeschen(name)
                    loeschenBereit = nil
                else
                    loeschenBereit = name
                end
            end } })

    -- Gildenraenge: wer in diesen Raengen ist, kommt beim Auffuellen in den Kader
    local k3 = karte(P, L["Gildenränge für den Kader"],
        L["Wer in einem gewählten Rang ist, gehört zum Kader. Wer den Rang oder die Gilde verlässt, fällt beim Synchronisieren heraus."], aktiv)
    zeile(k3, { art = "info", sichtbar = function() return not G.Raenge() end,
        label = L["Gildenliste nicht geladen"],
        beschr = function() local _, grund = G.Raenge() return tostring(grund or "") end })
    for i = 1, 10 do
        zeile(k3, { art = "schalter",
            sichtbar = function() local R = G.Raenge() return R ~= nil and R[i] ~= nil end,
            label = function() local R = G.Raenge() return R and R[i] and R[i].name or "" end,
            get = function()
                local R = G.Raenge()
                return R and R[i] and G.RangGewaehlt(G.AktivName(), R[i].index) or false
            end,
            set = function(v)
                local R = G.Raenge()
                if R and R[i] then G.RangSetzen(G.AktivName(), R[i].index, v) end
            end })
    end

    local k4 = karte(P, L["Neue Gruppe"])
    zeile(k4, { art = "eingabe", label = L["Name"],
        beschr = function()
            return Meldung.neu or L["Höchstens 40 Zeichen, ohne Semikolon."]
        end,
        knopf = { text = L["Anlegen"],
            klick = function(text)
                local ok, grund = G.Anlegen(text)
                Meldung.neu = ok and farbig(C.ok, L["Angelegt."]) or farbig(C.bad, tostring(grund))
            end } })
end

local NAV = {
    { id = "erfassung", label = L["Erfassung"],         icon = "settings.tga",
      titel = L["Erfassung"], beschr = L["Was, wo und von wem aufgezeichnet wird."], bauen = seiteErfassung },
    { id = "gargul",    label = L["Gargul & Abgleich"], icon = "rotate.tga",
      titel = L["Gargul & Abgleich"], beschr = L["Würfelbereiche, Import und der Abgleich zwischen den Spielern."], bauen = seiteGargul },
    { id = "gruppen",   label = L["Gruppen"],           icon = "users-group.tga",
      titel = L["Gruppen"], beschr = L["Kader und Raidgruppen für verschiedene Raidgrößen."], bauen = seiteGruppen },
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
    name:SetText("Fairshare")

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
        print("|cff1B6B57Fairshare|r: |cffff5555" ..
            string.format(L["Fehler in den Einstellungen: %s"], tostring(fehler)) .. "|r")
    end
end

function Einstellungen.Waehle(id)
    if not Seiten[id] then return end
    aktuelleSeite = id
    loeschenBereit = nil
    scroll:Zurueck()
    Einstellungen.Aktualisieren()
    if C_Timer then C_Timer.After(0.1, function() S.Auffrischen() end) end
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
