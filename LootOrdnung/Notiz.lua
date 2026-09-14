--[[----------------------------------------------------------------------
    Notiz.lua  —  Das Kontenformat in der Offiziersnotiz

    Format:  LO:Einsatz,Ruestwert,Woche,Deckel,Gegenstaende,Gebucht
    Beispiel: LO:4500,3800,2953,0,3,87234

    Das letzte Feld ist die Stunde der letzten Abendbuchung (Stunden seit
    der Unix-Epoche, gekuerzt). Es verhindert, dass mehrere Raidleiter
    denselben Abend nacheinander buchen und der Einsatz sich verdoppelt.

    Warum dort: Der Server synchronisiert die Notizen von selbst. Damit
    braucht es kein eigenes Sync-Protokoll und keine Absprache zwischen
    den Raidleitern der einzelnen Gruppen — es gibt genau eine Wahrheit.
    Dasselbe Verfahren nutzen EPGP und CEPGP seit Jahren.

    Wie Kern.lua ohne WoW-API, damit der Pruefstand sie testen kann.
------------------------------------------------------------------------]]

local _, ns = ...
ns = ns or {}

local Notiz = {}
ns.Notiz = Notiz

local floor, max = math.floor, math.max

Notiz.PRAEFIX  = "LO:"
Notiz.MAXLAENGE = 31   -- am Anniversary-Client gemessen: 30 Zeichen kamen
                       -- ungekuerzt an; 31 ist der klassische Wert.

-- =====================================================================
--  Lesen
-- =====================================================================

--- Gehoert dieser Text dem System?
function Notiz.IstUnser(text)
    if type(text) ~= "string" then return false end
    return text:sub(1, #Notiz.PRAEFIX) == Notiz.PRAEFIX
end

--- Traegt die Notiz Fremdinhalt, den wir nicht ueberschreiben duerfen?
--  Leer ist in Ordnung, unser eigenes Format auch — alles andere hat
--  jemand von Hand eingetragen. Bei Resurrected standen dort Dinge wie
--  "von Patric".
function Notiz.IstFremd(text)
    if type(text) ~= "string" then return false end
    if text == "" then return false end
    return not Notiz.IstUnser(text)
end

--- Liest ein Konto aus der Notiz.
--  @return konto oder nil, Grund bei Misserfolg
function Notiz.Lesen(text)
    if type(text) ~= "string" or text == "" then
        return nil, "leer"
    end
    if not Notiz.IstUnser(text) then
        return nil, "fremd"
    end

    local rumpf = text:sub(#Notiz.PRAEFIX + 1)

    -- Vollstaendige Fassung mit Buchungsstempel
    local e, r, w, d, g, b = rumpf:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)$")
    if not e then
        -- Fassung ohne Buchungsstempel
        e, r, w, d, g = rumpf:match("^(%d+),(%d+),(%d+),(%d+),(%d+)$")
        b = "0"
    end
    if not e then
        -- Kurzfassung ohne Zaehler
        e, r, w = rumpf:match("^(%d+),(%d+),(%d+)$")
        d, g, b = "0", "0", "0"
    end
    if not e then
        return nil, "unlesbar"
    end

    return {
        einsatz      = tonumber(e),
        ruestwert    = tonumber(r),
        woche        = tonumber(w),
        deckel       = tonumber(d),
        gegenstaende = tonumber(g),
        gebucht      = tonumber(b),
    }
end

-- =====================================================================
--  Schreiben
-- =====================================================================

--- Baut den Notiztext aus einem Konto.
--  ACHTUNG: gerundet auf ganze Zahlen. Einsatz und Ruestwert sind durch
--  den Verfall Kommazahlen; weil er multiplikativ wirkt, bleibt der
--  relative Rundungsfehler winzig und summiert sich nicht auf.
--  @return text oder nil, Grund
function Notiz.Schreiben(konto)
    if type(konto) ~= "table" then return nil, "kein Konto" end

    local text = string.format("%s%d,%d,%d,%d,%d,%d",
        Notiz.PRAEFIX,
        max(floor((konto.einsatz      or 0) + 0.5), 0),
        max(floor((konto.ruestwert    or 0) + 0.5), 0),
        max(floor( konto.woche        or 0),        0),
        max(floor((konto.deckel       or 0)),       0),
        max(floor((konto.gegenstaende or 0)),       0),
        max(floor((konto.gebucht      or 0)),       0))

    if #text > Notiz.MAXLAENGE then
        return nil, "zu lang"
    end
    return text
end

--- Schreiben und sofort wieder lesen — fuer den Pruefstand und als
--  Selbstkontrolle vor dem echten Schreibvorgang.
function Notiz.Rundlauf(konto)
    local text, grund = Notiz.Schreiben(konto)
    if not text then return nil, grund end
    return Notiz.Lesen(text)
end

return ns
