--[[----------------------------------------------------------------------
    Abgleich.lua  —  Vergabe-Register zwischen Raidleitern abgleichen

    Solange die Offiziersnotiz nicht beschreibbar ist, gibt es keinen
    Speicher, den alle gemeinsam sehen. Stattdessen traegt jeder Leiter
    sein eigenes Register und gleicht es auf Knopfdruck mit den anderen
    ab.

    ⭐ Das geht nur, weil das Register aus Einzelvergaben mit Kennung
    besteht (siehe Vergabe.lua). Die Vereinigung ist monoton: Reihenfolge
    egal, mehrfach anwendbar, kein Aushandeln noetig. Wer wann sendet,
    spielt keine Rolle.

    ⚠️ **Abgeglichen wird nur mit ausgewaehlten Raengen.** Eine
    Addon-Nachricht kann jeder schicken, der das Format kennt — bei einem
    System, an dem Loot haengt, waere „jeder darf einspielen" ein offenes
    Tor. Die Rangauswahl aus /lo raenge wird ohnehin gepflegt und ist
    damit die natuerliche Liste.

    ⚠️ Eine Addon-Nachricht fasst 255 Zeichen. Groessere Register werden
    zerlegt und beim Empfaenger wieder zusammengesetzt.
------------------------------------------------------------------------]]

local ADDON, ns = ...

local Abgleich = {}
ns.Abgleich = Abgleich

local Vergabe = ns.Vergabe

local PRAEFIX   = "|cff1B6B57Loot-Ordnung|r: "
local KANAL     = "LootOrdnung"   -- Nachrichtenpraefix, max. 16 Zeichen
local NUTZLAST  = 220             -- Zeichen je Nachricht, mit Sicherheit
local SENDEPAUSE = 0.25           -- Sekunden; zu schnelles Senden trennt
                                  -- die Verbindung
local VERFALL   = 30              -- Sekunden, bis ein halber Eingang
                                  -- verworfen wird

-- =====================================================================
--  Versionsbewusste Anbindung
-- =====================================================================

local function senden(text)
    local C = rawget(_G, "C_ChatInfo")
    local fn = (C and C.SendAddonMessage) or rawget(_G, "SendAddonMessage")
    if not fn then return false end
    local ok = pcall(fn, KANAL, text, "GUILD")
    return ok
end

local function praefixAnmelden()
    local C = rawget(_G, "C_ChatInfo")
    local fn = (C and C.RegisterAddonMessagePrefix) or rawget(_G, "RegisterAddonMessagePrefix")
    if fn then pcall(fn, KANAL) end
end

-- =====================================================================
--  Wer darf mitreden
-- =====================================================================

--- Steht der Absender auf einem ausgewaehlten Rang?
--  @return true, Kurzname
function Abgleich.Erlaubt(absender)
    if not absender or absender == "" then return false end
    if not (ns.Gilde and ns.Gilde.Teilnehmer) then return false end

    for _, e in ipairs(ns.Gilde.Teilnehmer()) do
        if e.name == absender then return true, e.kurz end
    end
    return false
end

-- =====================================================================
--  Zerlegen und zusammensetzen
-- =====================================================================

--- Register -> Text. Ein Satz je Vergabe, Felder mit ~ getrennt.
--  Gespeichert wird die Gegenstands-ID, nicht der Verweis: Verweise
--  enthalten senkrechte Striche, und die haben in einer Chatnachricht
--  eine eigene Bedeutung.
--  Ohne WoW-API, damit der Pruefstand sie testen kann.
function Abgleich.Packen(register)
    local teile = {}
    for kennung, e in pairs(register or {}) do
        teile[#teile + 1] = table.concat({
            kennung,
            e.spieler or "",
            tostring(e.gegenstand or ""),
            tostring(e.zeit or 0),
            e.weg and "w" or "",
        }, "~")
    end
    table.sort(teile)   -- stabile Reihenfolge, erleichtert den Vergleich
    return table.concat(teile, ";")
end

--- Text -> Register.
function Abgleich.Auspacken(text)
    local register = {}
    if type(text) ~= "string" then return register end

    for satz in text:gmatch("[^;]+") do
        local kennung, spieler, gegenstand, zeit, weg =
            satz:match("^([^~]*)~([^~]*)~([^~]*)~([^~]*)~([^~]*)$")
        if kennung and kennung ~= "" then
            register[kennung] = {
                spieler    = (spieler ~= "" and spieler) or nil,
                gegenstand = tonumber(gegenstand) or (gegenstand ~= "" and gegenstand) or nil,
                zeit       = tonumber(zeit) or 0,
                weg        = (weg == "w") or nil,
            }
        end
    end
    return register
end

--- Zerlegt einen Text in sendbare Stuecke.
function Abgleich.Stuecke(text, groesse)
    groesse = groesse or NUTZLAST
    local liste = {}
    local i, n = 1, #text
    if n == 0 then return liste end
    while i <= n do
        liste[#liste + 1] = text:sub(i, i + groesse - 1)
        i = i + groesse
    end
    return liste
end

-- =====================================================================
--  Senden
-- =====================================================================

local warteschlange, laeuft = {}, false

local function abarbeiten()
    local naechste = table.remove(warteschlange, 1)
    if not naechste then laeuft = false return end
    senden(naechste)
    C_Timer.After(SENDEPAUSE, abarbeiten)
end

local function einreihen(text)
    warteschlange[#warteschlange + 1] = text
    if not laeuft then
        laeuft = true
        C_Timer.After(0, abarbeiten)
    end
end

--- Schickt das eigene Register an die Gilde.
--  @return Anzahl Nachrichten
function Abgleich.Senden()
    local text = Abgleich.Packen(Vergabe.Register())
    local stuecke = Abgleich.Stuecke(text)

    if #stuecke == 0 then
        einreihen("D|1|1|")   -- leeres Register ist auch eine Antwort
        return 1
    end

    for i, stueck in ipairs(stuecke) do
        einreihen(string.format("D|%d|%d|%s", i, #stuecke, stueck))
    end
    return #stuecke
end

--- Bittet die anderen Raidleiter um ihr Register.
function Abgleich.Anfordern()
    einreihen("A")
end

-- =====================================================================
--  Empfangen
-- =====================================================================

local eingang = {}   -- absender -> { teile, gesamt, zeit }

local function verarbeiten(absender, kurz, text)
    local fremd = Abgleich.Auspacken(text)
    local neu, weg = Vergabe.Vereinen(Vergabe.Register(), fremd)

    if neu > 0 or weg > 0 then
        print(string.format("%sVon %s übernommen: |cff55ff55%d neu|r%s",
            PRAEFIX, kurz or absender, neu,
            weg > 0 and string.format(", |cffffff78%d zurückgenommen|r", weg) or ""))
    end
    return neu, weg
end

local function empfangen(text, absender)
    if not text or absender == nil then return end

    -- Eigene Nachrichten ignorieren; sonst zaehlt man sich selbst mit.
    local ich = Vergabe.VollerName(UnitName("player"))
    if absender == ich then return end

    local erlaubt, kurz = Abgleich.Erlaubt(absender)
    if not erlaubt then return end

    if text == "A" then
        Abgleich.Senden()
        return
    end

    local lfd, gesamt, daten = text:match("^D|(%d+)|(%d+)|(.*)$")
    if not lfd then return end
    lfd, gesamt = tonumber(lfd), tonumber(gesamt)

    local e = eingang[absender]
    if not e or e.gesamt ~= gesamt or (time() - e.zeit) > VERFALL then
        e = { teile = {}, gesamt = gesamt, zeit = time() }
        eingang[absender] = e
    end
    e.teile[lfd] = daten
    e.zeit = time()

    -- Vollstaendig? Erst dann auswerten — ein halbes Register waere
    -- schlimmer als gar keines.
    for i = 1, gesamt do
        if e.teile[i] == nil then return end
    end

    eingang[absender] = nil
    verarbeiten(absender, kurz, table.concat(e.teile))
end

-- =====================================================================
--  Ereignisse
-- =====================================================================

local rahmen = CreateFrame("Frame")
rahmen:RegisterEvent("CHAT_MSG_ADDON")
rahmen:RegisterEvent("PLAYER_ENTERING_WORLD")
rahmen:SetScript("OnEvent", function(_, ereignis, a1, a2, a3, a4)
    if ereignis == "PLAYER_ENTERING_WORLD" then
        praefixAnmelden()
        return
    end
    -- a1 Praefix, a2 Text, a3 Kanal, a4 Absender
    if a1 ~= KANAL then return end
    local ok, fehler = pcall(empfangen, a2, a4)
    if not ok then
        print(PRAEFIX .. "|cffff5555Fehler beim Abgleich: " .. tostring(fehler) .. "|r")
    end
end)

return ns
