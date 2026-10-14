--[[----------------------------------------------------------------------
    Kern.lua  —  Auswertung der Vergabe-Historie

    Enthaelt ausschliesslich Rechnerei: keine WoW-API, keine Frames, keine
    Events. Dadurch laeuft diese Datei im Spiel UND in einem gewoehnlichen
    Lua-Interpreter, und der Pruefstand kann sie ohne Client testen.

    ⭐ **Alles Rechnerische liegt hier**, auch das Zusammenfuehren zweier
    Historien, die Pruefsummen fuer den Abgleich und die Wahl des
    Schreibers. Dadurch ist es ohne Client pruefbar — und genau die Teile,
    bei denen ein Fehler still Daten verfaelscht, haben ihre Tests.

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
    if e.zurueck then return false, "zurückgenommen" end
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
--  ⚠️ **Wer nichts bekommen hat, steht in Garguls Historie nicht.**
--  Ausgerechnet der ist aber der Interessanteste, wenn gerade gewuerfelt
--  wird. Darum nimmt `pflicht` Namen entgegen, die auch mit null
--  Vergaben in der Liste auftauchen muessen.
--
--  @param historie  Tabelle: Pruefsumme -> Eintrag
--  @param seit      Zeitstempel, ab dem gezaehlt wird; nil = alles
--  ⭐ `nur` ist das Gegenstueck: Dann zaehlen und erscheinen AUSSCHLIESSLICH
--  diese Namen (die Spieler, die gerade in der Gruppe stehen). Wer nicht
--  dazugehoert, fehlt in Liste und Summe. Ein Name der Historie ohne
--  Nachnamen wird dem Namen MIT Nachnamen aus `nur` zugeschlagen, damit
--  niemand doppelt in der Liste steht.
--
--  @param historie  Tabelle: Pruefsumme -> Eintrag
--  @param seit      Zeitstempel, ab dem gezaehlt wird; nil = alles
--  @param pflicht   Liste von Namen, die in jedem Fall erscheinen
--  @param nur       Liste von Namen; wenn gegeben, nur diese
--  @return Liste aus { name, haupt, zweit, letzte, letzterEintrag },
--          Zahl der gezaehlten Vergaben, aeltester Zeitstempel
function Kern.Bilanz(historie, seit, pflicht, nur)
    if type(historie) ~= "table" then historie = {} end
    seit = seit or 0

    local nach, gesamt, aeltester = {}, 0, nil
    local gemerkt = {}

    -- Mit `nur`: der passende Name aus der Liste oder nil
    local function zugelassen(name)
        if not nur then return name end
        local k = Kern.Schluessel(name)
        if not k then return nil end
        if gemerkt[k] ~= nil then return gemerkt[k] or nil end
        local treffer = false
        for _, n in ipairs(nur) do
            if Kern.GleicherSpieler(n, name) then treffer = n break end
        end
        gemerkt[k] = treffer
        return treffer or nil
    end

    local function eintragFuer(name)
        name = zugelassen(name)
        if not name then return nil end
        local k = Kern.Schluessel(name)
        if not k then return nil end
        local z = nach[k]
        if not z then
            z = { name = Kern.Anzeigename(name), haupt = 0, zweit = 0, letzte = 0 }
            nach[k] = z
        end
        return z
    end

    for _, name in ipairs(pflicht or {}) do eintragFuer(name) end

    for _, e in pairs(historie) do
        local z
        if Kern.Zaehlt(e) and e.timestamp >= seit then z = eintragFuer(e.awardedTo) end
        if z then
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

--- Reihenfolge waehrend eines Wurfs.
--
--  ⭐ Wer gewuerfelt hat, steht oben — und dort **der mit den wenigsten
--  Stuecken zuerst**. Genau diese Frage stellt sich der Pluendermeister
--  in dem Moment. Alle uebrigen folgen in der gewohnten Reihenfolge,
--  damit der Ueberblick nicht verlorengeht.
--
--  @param liste        Ergebnis von Kern.Bilanz
--  @param istWuerfler  Funktion Name -> true/false
function Kern.WurfReihenfolge(liste, istWuerfler)
    if not istWuerfler then return liste end

    table.sort(liste, function(a, b)
        local wa, wb = istWuerfler(a.name), istWuerfler(b.name)
        if wa ~= wb then return wa end

        if wa then
            -- Wenigste zuerst
            if a.haupt ~= b.haupt then return a.haupt < b.haupt end
            if a.zweit ~= b.zweit then return a.zweit < b.zweit end
            -- Bei Gleichstand entscheidet, wer laenger nichts hatte
            if a.letzte ~= b.letzte then return a.letzte < b.letzte end
            return a.name < b.name
        end

        if a.haupt ~= b.haupt then return a.haupt > b.haupt end
        if a.zweit ~= b.zweit then return a.zweit > b.zweit end
        return a.name < b.name
    end)

    return liste
end

-- =====================================================================
--  Textvorlagen
-- =====================================================================

--- Baut aus einer Blizzard-Textvorlage ein Lua-Suchmuster.
--
--  Aus `"%s receives loot: %s."` wird `"^(.-) receives loot: (.-)%.$"`.
--
--  ⭐ **`%s` wird zu `(.-)`, nicht zu `(%S+)`.** Das ist der Unterschied,
--  an dem Gargul in Forever scheitert: Charakternamen duerfen dort ein
--  Leerzeichen enthalten („Yondaime Kaos"). Ein Muster, das am ersten
--  Leerzeichen abbricht, verliert den Nachnamen.
--
--  ⚠️ Verankert mit ^ und $. Dadurch funktioniert auch das traege `(.-)`
--  am Ende: es muss bis zum Zeilenende reichen.
--
--  @return Muster, Zahl der Fundstellen
function Kern.Muster(vorlage)
    if type(vorlage) ~= "string" then return nil, 0 end

    -- 1. Platzhalter sichern, damit das Escapen sie nicht zerlegt
    local Platzhalter, n = {}, 0
    local roh = vorlage:gsub("%%%d?%$?[sd]", function(p)
        n = n + 1
        Platzhalter[n] = p
        return "\1" .. n .. "\2"
    end)

    -- 2. Alles Magische entschaerfen
    roh = roh:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")

    -- 3. Platzhalter durch Fundstellen ersetzen
    roh = roh:gsub("\1(%d+)\2", function(i)
        local p = Platzhalter[tonumber(i)]
        -- ⚠️ Der Rueckgabewert einer gsub-Funktion wird WOERTLICH eingesetzt;
        -- Lua verarbeitet darin keine %-Escapes. Also einfaches %, nicht %%.
        if p:sub(-1) == "d" then return "(%d+)" end
        return "(.-)"
    end)

    return "^" .. roh .. "$", n
end

--- Der Wurfbereich sagt, wofuer gewuerfelt wurde.
--  Die Gilde wuerfelt `/rnd 100` fuer Hauptbedarf und `/rnd 50` fuer
--  Zweitbedarf. ⚠️ Alles andere ist kein Bedarfswurf und zaehlt nicht —
--  lieber nichts erfassen als etwas Falsches.
--  @return "haupt", "zweit" oder nil
function Kern.Bedarfsart(min, max)
    min, max = tonumber(min), tonumber(max)
    if min ~= 1 or not max then return nil end
    if max == 100 then return "haupt" end
    if max == 50  then return "zweit" end
    return nil
end

--- Zeitstempel, ab dem gezaehlt wird.
--  @param wochen  nil oder 0 = alles
function Kern.Seit(jetzt, wochen)
    if not wochen or wochen <= 0 then return 0 end
    return jetzt - wochen * Kern.WOCHE
end

-- =====================================================================
--  Spieler vergleichen
-- =====================================================================

--- Sind das derselbe Spieler?
--
--  ⚠️ Forever kennt Nachnamen („Yondaime Kaos"). Manche Quellen nennen sie,
--  andere nur den Vornamen. Fehlt auf EINER Seite der Nachname, genuegt der
--  gleiche Vorname. Haben beide einen, muessen sie ganz uebereinstimmen —
--  sonst waeren „Yondaime Kaos" und „Yondaime Nuhkomm" derselbe.
--  Der Preis: Fehlt der Nachname, treffen zwei Gleichvornamige aufeinander.
function Kern.GleicherSpieler(a, b)
    local ka, kb = Kern.Schluessel(a), Kern.Schluessel(b)
    if not ka or not kb then return false end
    if ka == kb then return true end

    local la, lb = ka:find(" ", 1, true), kb:find(" ", 1, true)
    if (la and lb) or (not la and not lb) then return false end
    return ka:match("^(%S+)") == kb:match("^(%S+)")
end

-- =====================================================================
--  Kennungen und Pruefsummen
-- =====================================================================

local MODUL = 4294967296   -- 2^32

--- Einfacher Textwert, 32 Bit. Kein Schutz, nur zum Vergleichen.
function Kern.Hash(text)
    local h = 5381
    text = tostring(text)
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % MODUL
    end
    return h
end

--- Pruefsumme einer Historie.
--
--  ⭐ Reihenfolgeunabhaengig (Summe), damit zwei Spieler mit denselben
--  Eintraegen dieselbe Zahl bekommen, egal wie ihre Tabelle gewachsen ist.
--
--  ⚠️ `alias` sind Kennungen, die als Doppelgaenger verworfen wurden. Sie
--  zaehlen MIT: Hat A „X" und kennt „Y" als Alias, B umgekehrt, kommt bei
--  beiden dieselbe Summe heraus. Ohne das waeren sie fuer immer
--  „verschieden", und der Abgleich liefe endlos.
--
--  @return Anzahl der Eintraege, Summe
function Kern.Pruefsumme(historie, alias)
    local n, summe = 0, 0
    for id in pairs(historie or {}) do
        n = n + 1
        summe = (summe + Kern.Hash(id)) % MODUL
    end
    for id in pairs(alias or {}) do
        summe = (summe + Kern.Hash(id)) % MODUL
    end
    return n, summe
end

--- Pruefsumme je Tag (Tagesschluessel kommt von `tagOf`).
--  ⚠️ Der Aufrufer nimmt UTC, nicht die Ortszeit: Wer in einer anderen
--  Zeitzone spielt, haette sonst andere Tage und damit nie dieselbe Summe.
--  @return Tabelle Tag -> { n, summe }
function Kern.Tagesstand(historie, alias, tagOf)
    local tage = {}

    for id, e in pairs(historie or {}) do
        local t = tagOf(e.timestamp or 0)
        local d = tage[t] or { n = 0, summe = 0 }
        d.n = d.n + 1
        d.summe = (d.summe + Kern.Hash(id)) % MODUL
        tage[t] = d
    end
    for id, ziel in pairs(alias or {}) do
        local e = (historie or {})[ziel]
        if e then
            local d = tage[tagOf(e.timestamp or 0)]
            if d then d.summe = (d.summe + Kern.Hash(id)) % MODUL end
        end
    end
    return tage
end

--- Welche Tage unterscheiden sich?  Beide Richtungen: ein Tag, den nur
--  eine Seite kennt, zaehlt auch.
--  @return sortierte Liste von Tagesschluesseln
function Kern.AbweichendeTage(lokal, fremd)
    local aus, liste = {}, {}
    local function pruefe(t)
        if aus[t] then return end
        local a, b = lokal[t], fremd[t]
        if not a or not b or a.n ~= b.n or a.summe ~= b.summe then
            aus[t] = true
            liste[#liste + 1] = t
        end
    end
    for t in pairs(lokal) do pruefe(t) end
    for t in pairs(fremd) do pruefe(t) end
    table.sort(liste)
    return liste
end

--- Tagesstand als Text:  "20261013:3:12345,20261014:1:99"
function Kern.TageKodieren(tage)
    local schluessel = {}
    for t in pairs(tage) do schluessel[#schluessel + 1] = t end
    table.sort(schluessel)
    local teile = {}
    for _, t in ipairs(schluessel) do
        -- ⚠️ `%.0f`, nie `%d`: Summen reichen bis 2^32. `%d` schneidet in
        -- manchen Lua-Fassungen bei 2^31 ab (-2147483648), und die Gegenseite
        -- wuerde den Tag mit dem Minuszeichen verwerfen.
        teile[#teile + 1] = string.format("%s:%d:%.0f", t, tage[t].n, tage[t].summe)
    end
    return table.concat(teile, ",")
end

function Kern.TageDekodieren(text)
    local tage = {}
    if type(text) ~= "string" then return tage end
    for t, n, summe in text:gmatch("([^,:]+):(%d+):(%d+)") do
        tage[t] = { n = tonumber(n), summe = tonumber(summe) }
    end
    return tage
end

-- =====================================================================
--  Zusammenfuehren
-- =====================================================================

--- ⭐ Fuehrt eingehende Eintraege in eine Historie ein — ohne je etwas zu
--  ueberschreiben oder zu loeschen.
--
--  Drei Wege fuer einen eingehenden Eintrag:
--    * Kennung schon bekannt (als Eintrag oder Alias)   -> vorhanden
--    * gleicher Spieler und Gegenstand nahe beieinander -> Doppelgaenger;
--      die Kennung wandert in `alias`, damit die Pruefsummen uebereinstimmen
--    * sonst                                            -> neu
--
--  ⚠️ Der Doppelgaenger-Weg ist eine Annaeherung: Gewinnt jemand denselben
--  Gegenstand zweimal binnen `fenster` Sekunden, geht der zweite verloren.
--  Das ist selten; systematisches Doppelzaehlen waere schlimmer.
--
--  Eine Ausnahme von „nichts aendern": Meldet der Eingehende einen Eintrag
--  als **zurueckgenommen**, wird das uebernommen. Das Merkmal kann nur von
--  „nein" auf „ja" wechseln und nie zurueck — so ist es ein Zusammenfuehren
--  und kein Ueberschreiben, und alle Seiten kommen zum selben Ergebnis.
--
--  @param eingehend  Liste aus { id =, e = }
--  @return neu, doppelt, vorhanden, abgelehnt, zurueckgenommen
function Kern.Zusammenfuehren(historie, alias, eingehend, fenster)
    fenster = fenster or 180
    local neu, doppelt, vorhanden, abgelehnt, zurueckgenommen = 0, 0, 0, 0, 0

    -- Index Spieler:Gegenstand -> { { id, zeit }, ... }
    local Index = {}
    local function schluessel(e)
        return (Kern.Schluessel(e.awardedTo) or "?") .. ":" .. tostring(e.itemID)
    end
    local function merke(id, e)
        local k = schluessel(e)
        Index[k] = Index[k] or {}
        Index[k][#Index[k] + 1] = { id = id, zeit = e.timestamp }
    end
    for id, e in pairs(historie) do
        if e.awardedTo and e.itemID then merke(id, e) end
    end

    for _, X in ipairs(eingehend or {}) do
        local id, e = X.id, X.e
        if type(id) ~= "string" or type(e) ~= "table"
           or not e.awardedTo or e.awardedTo == ""
           or not tonumber(e.itemID) or not tonumber(e.timestamp) then
            abgelehnt = abgelehnt + 1
        elseif historie[id] or alias[id] then
            vorhanden = vorhanden + 1
            local ziel = historie[id] or historie[alias[id]]
            if e.zurueck and ziel and not ziel.zurueck then
                ziel.zurueck = true
                zurueckgenommen = zurueckgenommen + 1
            end
        else
            local treffer
            for _, B in ipairs(Index[schluessel(e)] or {}) do
                if math.abs((B.zeit or 0) - e.timestamp) <= fenster then
                    treffer = B.id
                    break
                end
            end

            if treffer then
                alias[id] = treffer
                doppelt = doppelt + 1
            else
                historie[id] = e
                merke(id, e)
                neu = neu + 1
            end
        end
    end

    return neu, doppelt, vorhanden, abgelehnt, zurueckgenommen
end

-- =====================================================================
--  Uebertragung
-- =====================================================================

-- Zeichen, die in Feldern nicht roh vorkommen duerfen: Feldtrenner `;`,
-- Listentrenner `,` und `:`, Paketttrenner `~`, der Escape `%` selbst,
-- `|` (Blizzards Escape im Chat) und Steuerzeichen.
local function schuetze(s)
    return (tostring(s or ""):gsub("[%%;,:~|%c]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function entschuetze(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

--- Ein Eintrag als Zeile.
--  Felder: Kennung ; Name ; Gegenstand ; Zeit ; Art ; Gruppe ; Wurf ; Zurueck
--  ⚠️ Der Verweis (itemLink) wird NICHT mitgeschickt: Er ist lang und
--  enthaelt `|`. Der Empfaenger holt ihn ueber die Gegenstandsnummer.
function Kern.Kodieren(id, e)
    return table.concat({
        schuetze(id),
        schuetze(e.awardedTo),
        tostring(tonumber(e.itemID) or 0),
        tostring(tonumber(e.timestamp) or 0),
        e.OS and "Z" or "H",
        schuetze(e.gruppe),
        e.wurf and tostring(tonumber(e.wurf) or "") or "",
        e.zurueck and "1" or "",
    }, ";")
end

--- Zeile -> id, Eintrag; oder nil und ein Grund.
--  ⚠️ Alles, was von aussen kommt, wird geprueft: Namenslaenge, Zahlen,
--  ein vernuenftiger Zeitraum. Eine kaputte oder boesartige Zeile darf
--  hoechstens abgelehnt werden, nie die Historie verfaelschen.
function Kern.Dekodieren(zeile, jetzt)
    if type(zeile) ~= "string" then return nil, "kein Text" end
    local id, name, item, zeit, art, gruppe, wurf, zurueck =
        zeile:match("^([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*)$")
    if not id then return nil, "Aufbau" end

    id, name, gruppe = entschuetze(id), entschuetze(name), entschuetze(gruppe)
    item, zeit = tonumber(item), tonumber(zeit)

    if id == "" or #id > 80 then return nil, "Kennung" end
    if name == "" or #name > 60 then return nil, "Name" end
    if not item or item <= 0 or item > 10000000 then return nil, "Gegenstand" end
    if not zeit or zeit < 1000000000 then return nil, "Zeit" end
    if jetzt and zeit > jetzt + 2 * Kern.TAG then return nil, "Zeit in der Zukunft" end
    if art ~= "H" and art ~= "Z" then return nil, "Art" end
    if #gruppe > 40 then return nil, "Gruppe" end

    return id, {
        awardedTo = name,
        itemID    = item,
        timestamp = zeit,
        OS        = (art == "Z") or nil,
        gruppe    = gruppe ~= "" and gruppe or nil,
        wurf      = tonumber(wurf),
        zurueck   = (zurueck == "1") or nil,
        empfangen = true,
    }
end

--- Packt Zeilen in Nachrichten bis `grenze` Zeichen.
--  Trenner ist `~` (innerhalb der Zeilen immer geschuetzt).
--  ⚠️ Eine einzelne Zeile, die allein schon zu lang ist, bekommt eine
--  eigene Nachricht und wird vom Sender abgelehnt — nicht gekappt: eine
--  abgeschnittene Zeile waere ein falscher Eintrag.
function Kern.Pakete(zeilen, grenze)
    local pakete, aktuell = {}, nil
    for _, z in ipairs(zeilen) do
        if aktuell and (#aktuell + 1 + #z) <= grenze then
            aktuell = aktuell .. "~" .. z
        else
            if aktuell then pakete[#pakete + 1] = aktuell end
            aktuell = z
        end
    end
    if aktuell then pakete[#pakete + 1] = aktuell end
    return pakete
end

--- Gegenstueck zu Pakete.
function Kern.Entpacken(paket)
    local zeilen = {}
    if type(paket) ~= "string" or paket == "" then return zeilen end
    for z in (paket .. "~"):gmatch("(.-)~") do
        if z ~= "" then zeilen[#zeilen + 1] = z end
    end
    return zeilen
end

-- =====================================================================
--  Wer zeichnet auf?
-- =====================================================================

--- ⭐ Wer in der Gruppe fuehrt die Historie?
--
--  Nur EINER soll mitschreiben. Sonst entstuende fuer jeden Drop ein
--  Eintrag je Teilnehmer, und der Abgleich muesste sie wieder
--  zusammenfuehren. Entscheid des Gildenleiters (14.10.2026): der
--  Pluendermeister, und gibt es keinen, der Schlachtzugsleiter.
--
--  ⚠️ Die Wahl haengt daran, WER das Addon hat. Hat der Pluendermeister es
--  nicht, springt die Reihenfolge weiter (Leiter, dann Assistenten) —
--  sonst ginge der ganze Abend verloren.
--
--  @param kandidaten  geordnet: { { name =, ich = true/false }, ... }
--  @param hat         Menge der Schluessel von Mitspielern MIT Addon
--  @return der gewaehlte Kandidat, oder nil
function Kern.Schreiber(kandidaten, hat)
    hat = hat or {}
    for _, k in ipairs(kandidaten or {}) do
        if k.ich then return k end
        local s = Kern.Schluessel(k.name)
        if s and hat[s] then return k end
    end
    return nil
end

-- =====================================================================
--  Ansichten
-- =====================================================================

--- Nur die Eintraege einer Gruppe. nil = alle (dieselbe Tabelle).
function Kern.NachGruppe(historie, gruppe)
    if not gruppe then return historie end
    local aus = {}
    for id, e in pairs(historie or {}) do
        if e.gruppe == gruppe then aus[id] = e end
    end
    return aus
end

--- Der Verlauf: wer bekam was, wann. Neueste zuerst.
--  @return Liste aus { zeit, name, zweit, eintrag }
function Kern.Verlauf(historie, seit, gruppe)
    local liste = {}
    seit = seit or 0
    for _, e in pairs(Kern.NachGruppe(historie, gruppe) or {}) do
        if Kern.Zaehlt(e) and e.timestamp >= seit then
            liste[#liste + 1] = {
                zeit    = e.timestamp,
                name    = Kern.Anzeigename(e.awardedTo),
                zweit   = e.OS and true or false,
                eintrag = e,
            }
        end
    end
    table.sort(liste, function(a, b)
        if a.zeit ~= b.zeit then return a.zeit > b.zeit end
        return a.name < b.name
    end)
    return liste
end

return ns
