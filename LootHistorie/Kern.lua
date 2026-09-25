--[[----------------------------------------------------------------------
    Kern.lua  —  Auswertung der Vergabe-Historie

    Enthaelt ausschliesslich Rechnerei: keine WoW-API, keine Frames, keine
    Events. Dadurch laeuft diese Datei im Spiel UND in einem gewoehnlichen
    Lua-Interpreter, und der Pruefstand kann sie ohne Client testen.

    ⭐ **Das Addon fuehrt keine eigene Datenbank.** Die Vergaben liegen in
    Garguls `AwardHistory`, dauerhaft und nach Pruefsumme abgelegt. Wir
    lesen, zaehlen, zeigen an — und schreiben nie. Was es nicht gibt, kann
    auch nicht auseinanderlaufen.

    Jede Funktion bekommt die Historie als Parameter. Dadurch laesst sich
    dieselbe Auswertung mit Beispieldaten fuettern, ohne irgendwo etwas
    abzulegen.
------------------------------------------------------------------------]]

local _, ns = ...
ns = ns or {}

local Kern = {}
ns.Kern = Kern

Kern.WOCHE = 604800
Kern.TAG   = 86400

-- Gargul traegt diesen Namen als Gewinner ein, wenn entzaubert wurde.
Kern.ENTZAUBERT = "||de||"

-- =====================================================================
--  Einzelne Eintraege
-- =====================================================================

--- Zaehlt diese Vergabe als Zuteilung an einen Spieler?
--
--  ⚠️ Drei Faelle fallen heraus, und jeder aus einem eigenen Grund:
--  * **Entzaubert** — der Gegenstand ging an niemanden.
--  * **Bonus-Beute** — zusaetzliche Beute ausserhalb der Vergabe.
--  * **Unvollstaendig** — ohne Gewinner oder Zeitstempel nicht auswertbar.
--
--  @return true, oder false und der Grund
function Kern.Zaehlt(e)
    if type(e) ~= "table" then return false, "kein Eintrag" end
    if not e.awardedTo or e.awardedTo == "" then return false, "ohne Gewinner" end
    if e.awardedTo == Kern.ENTZAUBERT then return false, "entzaubert" end
    if e.isBonusLoot then return false, "Bonus-Beute" end
    if not tonumber(e.timestamp) then return false, "ohne Zeitstempel" end
    return true
end

--- Schluessel, unter dem ein Spieler gefuehrt wird.
--
--  ⚠️ Gargul schreibt den Gewinner mal mit, mal ohne Realm — je nachdem,
--  ob die Vergabe lokal entstand oder ueber die Gruppe hereinkam. Ohne
--  Vereinheitlichung steht derselbe Spieler zweimal in der Liste.
--  Das setzt eine Gilde auf einem Realm voraus; zwei Gleichnamige von
--  verschiedenen Realms liefen zusammen.
function Kern.Schluessel(name)
    if type(name) ~= "string" or name == "" then return nil end
    return (name:match("^([^%-]+)") or name):lower()
end

--- Wie der Name angezeigt wird: ohne Realm, erster Buchstabe gross.
function Kern.Anzeigename(name)
    if type(name) ~= "string" or name == "" then return "?" end
    local kurz = name:match("^([^%-]+)") or name
    return kurz:sub(1, 1):upper() .. kurz:sub(2)
end

-- =====================================================================
--  Auswertung
-- =====================================================================

--- Wer hat wie viel bekommen.
--
--  Sortiert nach Hauptbedarf. ⚠️ Zweitbedarf wird getrennt gefuehrt und
--  fliesst NICHT in die Reihenfolge ein: Wer einen Gegenstand fuer die
--  Zweitrolle bekommt, hat damit keinen Anspruch verbraucht. Er steht
--  trotzdem da, weil die Leitung ihn sehen will.
--
--  @param historie  Tabelle: Pruefsumme -> Eintrag
--  @param seit      Zeitstempel, ab dem gezaehlt wird; nil = alles
--  @return Liste aus { name, haupt, zweit, letzte, letzterEintrag },
--          Zahl der gezaehlten Vergaben, aeltester Zeitstempel
function Kern.Bilanz(historie, seit)
    if type(historie) ~= "table" then return {}, 0, nil end
    seit = seit or 0

    local nach, gesamt, aeltester = {}, 0, nil

    for _, e in pairs(historie) do
        if Kern.Zaehlt(e) and e.timestamp >= seit then
            local k = Kern.Schluessel(e.awardedTo)
            local z = nach[k]
            if not z then
                z = { name = Kern.Anzeigename(e.awardedTo), haupt = 0, zweit = 0, letzte = 0 }
                nach[k] = z
            end

            if e.OS then
                z.zweit = z.zweit + 1
            else
                z.haupt = z.haupt + 1
                -- „Zuletzt" meint Hauptbedarf. Ein Zweitbedarfs-Stueck
                -- sagt ueber den Anspruch nichts aus.
                if e.timestamp > z.letzte then
                    z.letzte = e.timestamp
                    z.letzterEintrag = e
                end
            end

            gesamt = gesamt + 1
            if not aeltester or e.timestamp < aeltester then aeltester = e.timestamp end
        end
    end

    local liste = {}
    for _, z in pairs(nach) do liste[#liste + 1] = z end

    table.sort(liste, function(a, b)
        if a.haupt ~= b.haupt then return a.haupt > b.haupt end
        if a.zweit ~= b.zweit then return a.zweit > b.zweit end
        return a.name < b.name
    end)

    return liste, gesamt, aeltester
end

--- Alle Vergaben eines Spielers, neueste zuerst.
--  @return Liste aus { zeit, eintrag, zweit }
function Kern.Spieler(historie, name, seit)
    if type(historie) ~= "table" then return {} end
    local gesucht = Kern.Schluessel(name)
    if not gesucht then return {} end
    seit = seit or 0

    local liste = {}
    for _, e in pairs(historie) do
        if Kern.Zaehlt(e) and e.timestamp >= seit
           and Kern.Schluessel(e.awardedTo) == gesucht then
            liste[#liste + 1] = {
                zeit    = e.timestamp,
                eintrag = e,
                zweit   = e.OS and true or false,
            }
        end
    end

    table.sort(liste, function(a, b) return a.zeit > b.zeit end)
    return liste
end

--- Verschiedene Kalendertage mit mindestens einer Vergabe.
--
--  ⚠️ Das ist NICHT Anwesenheit. Wer da war und nichts bekam, steht in
--  Garguls Daten nirgends. Die Zahl taugt als Bezugsgroesse fuer „viel"
--  und „wenig", nicht als Teilnahmenachweis.
--
--  @param tagOf  Funktion Zeitstempel -> Tagesschluessel (wegen date())
function Kern.Raidtage(historie, seit, tagOf)
    if type(historie) ~= "table" or not tagOf then return 0 end
    seit = seit or 0

    local tage, n = {}, 0
    for _, e in pairs(historie) do
        if Kern.Zaehlt(e) and e.timestamp >= seit then
            local tag = tagOf(e.timestamp)
            if not tage[tag] then tage[tag] = true; n = n + 1 end
        end
    end
    return n
end

--- Zeitstempel, ab dem gezaehlt wird.
--  @param wochen  nil oder 0 = alles
function Kern.Seit(jetzt, wochen)
    if not wochen or wochen <= 0 then return 0 end
    return jetzt - wochen * Kern.WOCHE
end

return ns
