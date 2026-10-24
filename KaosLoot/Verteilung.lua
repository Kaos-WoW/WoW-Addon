--[[----------------------------------------------------------------------
    Verteilung.lua  —  Wie die Wertung zustande kommt

    Zwei Verfahren, die Leitung waehlt eines (geteilte Einstellung):

      Punkte mit Zuschlaegen   (bisher)
          Wertung = Main-Items + Zuschlaege fuer verpasste Abende + Anhebungen.
      Items pro Abend          (neu, 1.1.0)
          Wertung = Items pro besuchtem Abend der letzten N Raid-IDs (Standard 8, gleitend,
          ohne Reset zur neuen Phase). Weder bestraft Fehlen noch Anwesenheit. Neue Spieler
          und Rueckkehrer starten am Gildenschnitt (Glaettung: k Pseudo-Abende).
              Wertung = (Items im Fenster + Korrektur + Schnitt * k) / (besuchte Abende + k)
          Besuchte Abende kommen aus den Abschluessen (Status „imRaid“), der heutige Abend zaehlt mit,
          wenn der Spieler jetzt im Raid ist.

    In beiden gilt die Regel „Heute schon ein Item“ (aus | leicht | streng, Standard streng):
    Wer an diesem Abend schon ein Main-Item bekommen hat, steht hinter allen, die noch keins haben.

    Die Korrektur der Leitung (Plus oder Minus mit Pflichtkommentar) liegt in Anwesenheit.lua; sie wird
    wie eine Anhebung als Satz des Datenbuchs verteilt (Kennung `k_…`).

    ⚠️ Die Rechnung selbst steht in Kern.Bilanz; hier werden nur die Einstellungen gelesen und die Zahlen
    zusammengesucht (`Verteilung.AbendDaten`, aufgerufen aus Anwesenheit.ZuschlaegeDaten).
------------------------------------------------------------------------]]

local ADDON, ns = ...
local L = ns.L

local Verteilung = {}
ns.Verteilung = Verteilung

local Kern = ns.Kern

local TAG = 86400
Verteilung.STANDARD = { verfahren = "zuschlag", fenster = 8, glaettung = 4, regel = "streng" }
Verteilung.HEUTE_VON = 12 * 3600      -- „heute“ = die letzten 12 Stunden

local function einst() return ns.Erfassung.Einstellungen() end

-- =====================================================================
--  Einstellungen (geteilt, siehe Konfig.lua)
-- =====================================================================

function Verteilung.Verfahren()
    return (einst().verfahren == "abend") and "abend" or "zuschlag"
end

function Verteilung.Fenster()
    local n = tonumber(einst().fensterIds)
    if not n then return Verteilung.STANDARD.fenster end
    return math.max(2, math.min(52, math.floor(n)))
end

function Verteilung.Glaettung()
    local n = tonumber(einst().glaettung)
    if not n then return Verteilung.STANDARD.glaettung end
    return math.max(0, math.min(20, math.floor(n)))
end

function Verteilung.Regel()
    local r = einst().heuteRegel
    if r == "aus" or r == "leicht" or r == "streng" then return r end
    return Verteilung.STANDARD.regel
end

function Verteilung.VerfahrenSetzen(v)
    if v ~= "abend" and v ~= "zuschlag" then return false end
    einst().verfahren = v
    return true
end

function Verteilung.FensterSetzen(n)
    n = tonumber(n)
    if not n or n < 2 or n > 52 then return false end
    einst().fensterIds = math.floor(n)
    return true
end

function Verteilung.GlaettungSetzen(n)
    n = tonumber(n)
    if not n or n < 0 or n > 20 then return false end
    einst().glaettung = math.floor(n)
    return true
end

function Verteilung.RegelSetzen(r)
    if r ~= "aus" and r ~= "leicht" and r ~= "streng" then return false end
    einst().heuteRegel = r
    return true
end

--- Der Name eines Verfahrens, wie die Gilde ihn sagt.
function Verteilung.Name(v)
    if v == "abend" then return L["Items pro Abend"] end
    return L["Punkte mit Zuschlägen"]
end

--- Ist „Items pro Abend“ gerade das Verfahren?
function Verteilung.ProAbend()
    return Verteilung.Verfahren() == "abend"
end

-- =====================================================================
--  Die Zahlen fuer „Items pro Abend“
-- =====================================================================

--- Beginn des Zeitfensters: die letzten N Raid-IDs, die laufende eingeschlossen.
--  @return Zeitstempel (Mitternacht des ersten ID-Tages) und das Datum als Text
function Verteilung.FensterVon(jetzt)
    jetzt = jetzt or time()
    local n = Verteilung.Fenster()
    local tag = date("%Y-%m-%d", jetzt - (n - 1) * 7 * TAG)
    local start = (ns.Gruppen and ns.Gruppen.IdStart) and ns.Gruppen.IdStart(tag) or tag
    local y, m, d = tostring(start):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return 0, tostring(start) end
    return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 }), start
end

local function istWochenbuchung(ab)
    return (ab.woche or tostring(ab.id or ""):match("_wb%d+$") ~= nil) and true or false
end

--- Sammelt fuer Kern.Bilanz: besuchte Abende je Spieler, Korrekturen im Fenster, den Gildenschnitt und wer jetzt da ist.
function Verteilung.AbendDaten(jetzt)
    jetzt = jetzt or time()
    local von, vonDatum = Verteilung.FensterVon(jetzt)
    local A = ns.Anwesenheit.Daten()

    local abende, summeAbende = {}, 0
    for _, ab in pairs(A.abende or {}) do
        if ab.abgeschlossen and ab.abschluss and not istWochenbuchung(ab) and tostring(ab.datum or "") >= vonDatum then
            for k, p in pairs(ab.abschluss.spieler or {}) do
                if p.status == "imRaid" then
                    abende[k] = (abende[k] or 0) + 1
                    summeAbende = summeAbende + 1
                end
            end
        end
    end

    local korrektur = {}
    for id, h in pairs(A.anhebungsliste or {}) do
        if Kern.IstKorrektur(id) and (tonumber(h.zeit) or 0) >= von then
            local k = h.schluessel or Kern.Schluessel(h.name)
            if k then korrektur[k] = (korrektur[k] or 0) + (tonumber(h.wert) or 0) end
        end
    end

    -- Gildenschnitt: Main-Items im Fenster je besuchtem Abend (ohne Daten: ein halbes Item)
    local items = 0
    local H = (ns.Erfassung and ns.Erfassung.Historie and ns.Erfassung.Historie()) or {}
    for _, e in pairs(H) do
        if Kern.Zaehlt(e) and not e.OS and (tonumber(e.timestamp) or 0) >= von then items = items + 1 end
    end
    local p0 = (summeAbende > 0) and (items / summeAbende) or 0.5

    local heute = {}
    if ns.Rolle and ns.Rolle.Namen then
        for _, n in ipairs(ns.Rolle.Namen()) do
            local k = Kern.Schluessel(n)
            if k then heute[k] = true end
        end
    end

    return { von = von, k = Verteilung.Glaettung(), p0 = p0, abende = abende, korrektur = korrektur, heute = heute }
end

return ns
