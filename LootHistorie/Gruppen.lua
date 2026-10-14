--[[----------------------------------------------------------------------
    Gruppen.lua  —  Kader und Raidgruppen

    Die Gilde faehrt Schlachtzuege verschiedener Groesse (10, 20, 40). Eine
    Gruppe sagt, WER in der Liste stehen soll, auch wenn er noch nichts
    bekommen hat — und welcher Gruppe eine Vergabe zugeschrieben wird.

    Zwei Arten:
      * kader  feste Namensliste (der ganze 40er-Kader)
      * raid   wer gerade in der Gruppe steht (kleinere Schlachtzuege)

    ⭐ Jede Vergabe merkt sich die Gruppe, die beim Eintragen aktiv war.
    Gezaehlt wird trotzdem ueber alles: Die Ansicht laesst sich auf eine
    Gruppe einschraenken oder auf alle ausweiten. Ob ein 10er-Raid fuer
    die 40er-Statistik zaehlt, bleibt damit eine Frage der Ansicht und
    nicht der Aufzeichnung — nichts geht verloren, was sich spaeter anders
    entscheiden liesse.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Gruppen = {}
ns.Gruppen = Gruppen

local Kern = ns.Kern

local function db()
    local d = ns.Erfassung.Einstellungen()
    d.gruppen = d.gruppen or {}
    return d
end

--- Namen aller Gruppen, alphabetisch.
function Gruppen.Namen()
    local liste = {}
    for name in pairs(db().gruppen) do liste[#liste + 1] = name end
    table.sort(liste, function(a, b) return a:lower() < b:lower() end)
    return liste
end

function Gruppen.Holen(name)
    return name and db().gruppen[name] or nil
end

--- Die aktive Gruppe (die neue Vergaben bekommen).
function Gruppen.AktivName()
    local d = db()
    if d.aktiveGruppe and d.gruppen[d.aktiveGruppe] then return d.aktiveGruppe end
    return nil
end

function Gruppen.Aktiv()
    return Gruppen.Holen(Gruppen.AktivName())
end

--- @return true, oder false und ein Grund
function Gruppen.Anlegen(name, modus)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return false, "kein Name" end
    if #name > 40 then return false, "Name zu lang (höchstens 40 Zeichen)" end
    -- ⚠️ Kein Semikolon und keine Steuerzeichen: Der Name geht beim Abgleich
    -- mit auf die Reise. Kodieren schuetzt zwar, aber Ruhe ist besser.
    if name:find("[;~|%c]") then return false, "Zeichen nicht erlaubt" end

    local d = db()
    if d.gruppen[name] then return false, "gibt es schon" end
    d.gruppen[name] = { name = name, modus = modus == "raid" and "raid" or "kader", kader = {} }
    if not d.aktiveGruppe then d.aktiveGruppe = name end
    return true
end

function Gruppen.Loeschen(name)
    local d = db()
    if not d.gruppen[name] then return false end
    d.gruppen[name] = nil
    if d.aktiveGruppe == name then d.aktiveGruppe = nil end
    return true
end

function Gruppen.Aktivieren(name)
    local d = db()
    if name ~= nil and not d.gruppen[name] then return false end
    d.aktiveGruppe = name
    return true
end

function Gruppen.ModusUmschalten(name)
    local G = Gruppen.Holen(name)
    if not G then return nil end
    G.modus = (G.modus == "raid") and "kader" or "raid"
    return G.modus
end

--- Kader aus den Namen der aktuellen Gruppe fuellen (ersetzt den alten).
--  @return Anzahl
function Gruppen.KaderAusGruppe(name)
    local G = Gruppen.Holen(name)
    if not G then return nil end
    G.kader = {}
    for _, n in ipairs(ns.Rolle.Namen()) do G.kader[#G.kader + 1] = n end
    return #G.kader
end

--- Namen zum Kader hinzufuegen, durch Leerzeichen UND Komma getrennt
--  waere zweideutig (Nachnamen!) — deshalb nur Komma oder Zeilenumbruch.
function Gruppen.KaderErgaenzen(name, text)
    local G = Gruppen.Holen(name)
    if not G then return nil end
    local n = 0
    for roh in (text or ""):gmatch("[^,\n]+") do
        local eintrag = roh:match("^%s*(.-)%s*$")
        if eintrag ~= "" then
            local da = false
            for _, e in ipairs(G.kader) do
                if Kern.GleicherSpieler(e, eintrag) then da = true break end
            end
            if not da then
                G.kader[#G.kader + 1] = eintrag
                n = n + 1
            end
        end
    end
    return n
end

function Gruppen.KaderEntfernen(name, wer)
    local G = Gruppen.Holen(name)
    if not G then return false end
    for i, e in ipairs(G.kader) do
        if Kern.GleicherSpieler(e, wer) then
            table.remove(G.kader, i)
            return true
        end
    end
    return false
end

--- Namen, die in der Liste stehen muessen — fuer die gewaehlte Gruppe
--  oder, ohne Auswahl, fuer die aktive.
function Gruppen.Pflicht(gewaehlt)
    local G = Gruppen.Holen(gewaehlt) or Gruppen.Aktiv()
    if not G then return {} end
    local raid = (G.modus == "raid") and ns.Rolle.Namen() or nil
    return Kern.Pflichtnamen(G, raid)
end

return ns
