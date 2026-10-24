-- tests/_filter_smoke.lua
-- ---------------------------------------------------------------------------
-- Wegwerf-Selbsttest fuer Core\Filter.lua und Core\Outfits.lua.
-- Laeuft eigenstaendig mit luajit (kein mock_wow noetig): Util/Events/DB/
-- Items/State sind hier minimal nachgebaut. Aufruf:
--   luajit tests/_filter_smoke.lua
-- Globale Zugriffe werden strikt ueberwacht (Lesen/Schreiben unbekannter
-- Globals bricht ab), so fallen versehentliche Globals auf.
-- ---------------------------------------------------------------------------

local script = debug.getinfo(1, "S").source:gsub("^@", "")
local BUILD = script:gsub("/tests/[^/]*$", "")
if BUILD == script then BUILD = "." end

local passes, failures = 0, 0

local function check(cond, msg)
   if cond then
      passes = passes + 1
   else
      failures = failures + 1
      print("FAIL: " .. tostring(msg))
   end
end

local function eq(actual, expected, msg)
   if actual == expected then
      passes = passes + 1
   else
      failures = failures + 1
      print(string.format("FAIL: %s (erwartet %s, erhalten %s)", tostring(msg), tostring(expected), tostring(actual)))
   end
end

-- Array-Vergleich als String
local function arr(t)
   local out = {}
   for i = 1, #t do out[i] = tostring(t[i]) end
   return table.concat(out, ",")
end

local function ids(entries)
   local out = {}
   for i = 1, #entries do out[i] = entries[i].id end
   return arr(out)
end

-- ---------------------------------------------------------------------------
-- Globale Attrappen (vor dem Strikt-Modus)
-- ---------------------------------------------------------------------------

local clock = 100
function GetTime() return clock end
function time() return 1700000000 + clock end

Transmog = {}
local T = Transmog
T.HIDDEN_ID = 999999

T.L = setmetatable({}, { __index = function(_, k) return k end })
local LOCALE_ADDED = {}
T.Locale = {
   Add = function(code, tbl)
      LOCALE_ADDED[code] = LOCALE_ADDED[code] or {}
      for k, v in pairs(tbl) do
         LOCALE_ADDED[code][k] = v
         rawset(T.L, k, v)
      end
   end,
}

T.Util = {
   Trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end,
   Lower = function(s) return string.lower(s) end,
   G = function(name, fb) return rawget(_G, name) or fb end,
}

-- Ereignisbus
local handlers, fired = {}, {}
T.Events = {
   On = function(name, fn, owner)
      handlers[name] = handlers[name] or {}
      table.insert(handlers[name], { fn = fn, owner = owner })
   end,
   Fire = function(name, ...)
      fired[name] = (fired[name] or 0) + 1
      for _, h in ipairs(handlers[name] or {}) do h.fn(...) end
   end,
}

T.DB = {
   char = {
      filter = { qualities = {}, typesOff = {}, hideDuplicates = true, sort = "QUALITY",
                 favoritesOnly = false, newOnly = false },
      favorites = {},
      outfits = {},
   },
}

-- Items
local DATA, RESOLVED = {}, {}
local LABELS = { [401] = "Cloth", [402] = "Leather", [403] = "Mail", [404] = "Plate",
                 [201] = "Two-Handed Axes", [207] = "One-Handed Swords", [406] = "Shields" }
local requested, requestCalls = nil, 0
T.Items = {
   ARMOR_ORDER = { 404, 403, 402, 401 },
   Info = function(id) if RESOLVED[id] then return DATA[id] end return nil end,
   RequestMany = function(list)
      requested = list
      requestCalls = requestCalls + 1
   end,
   TypeLabel = function(k) return LABELS[k] end,
}

-- State
local S = { lists = {}, equipped = {}, wanted = {}, baseline = {}, applied = {}, slotState = {} }
local HIDEABLE = { [0] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
                   [7] = true, [8] = true, [9] = true, [14] = true, [18] = true }
local setManyCalls, lastMap = 0, nil
T.State = {
   new = {},
   List = function(slot) return S.lists[slot] or { ids = {}, set = {}, received = 0, ready = false } end,
   Equipped = function(slot) return S.equipped[slot] end,
   Wanted = function(slot) return S.wanted[slot] or S.baseline[slot] or 0 end,
   Baseline = function(slot) return S.baseline[slot] or 0 end,
   Applied = function(slot) return S.applied[slot] or S.baseline[slot] or 0 end,
   SlotState = function(slot) return S.slotState[slot] or "READY" end,
   IsAvailable = function(slot, id)
      if id == 0 then return true end
      if id == 999999 then return HIDEABLE[slot] == true end
      local l = S.lists[slot]
      return (l and l.set[id]) and true or false
   end,
   SetMany = function(map)
      setManyCalls = setManyCalls + 1
      lastMap = map
   end,
}

-- Strikter Globals-Modus: ab hier faellt jedes unbekannte Global auf
setmetatable(_G, {
   __newindex = function(_, k) error("globale Zuweisung: " .. tostring(k), 2) end,
   __index = function(_, k) error("unbekanntes Global gelesen: " .. tostring(k), 2) end,
})

local function load(rel)
   local chunk, err = loadfile(BUILD .. "/" .. rel)
   if not chunk then error(err) end
   chunk()
end

load("Locales/enUS_Filter.lua")
load("Core/Filter.lua")
load("Core/Outfits.lua")

local Filter, Outfits = T.Filter, T.Outfits
local Events = T.Events

-- ---------------------------------------------------------------------------
-- Testdaten
-- ---------------------------------------------------------------------------

local function item(id, name, quality, ilvl, typeKey, subtype, icon, equipLoc)
   DATA[id] = {
      id = id, name = name, quality = quality, ilvl = ilvl, typeKey = typeKey,
      typeName = typeKey and (typeKey >= 400 and "Armor" or "Weapon") or "Junk",
      subtypeName = subtype, icon = icon, equipLoc = equipLoc or "INVTYPE_CHEST",
   }
   RESOLVED[id] = true
end

item(100, "Plate Chest Alpha", 4, 200, 404, "Plate", "Interface\\Icons\\A")
item(101, "Plate Chest Beta", 3, 150, 404, "Plate", "Interface\\Icons\\B")
item(102, "Mail Chest Gamma", 3, 140, 403, "Mail", "Interface\\Icons\\C")
item(103, "Cloth Robe Delta", 2, 100, 401, "Cloth", "Interface\\Icons\\D")
item(104, "Leather Epsilon", 2, 90, 402, "Leather", "Interface\\Icons\\E")
item(105, "Plate Chest Beta Copy", 2, 80, 404, "Plate", "interface\\icons\\b")   -- Duplikat von 101 (Schreibweise egal)
item(106, "Strange Thing", 1, 10, nil, "Strange", "Interface\\Icons\\F")
item(108, "Rag", 0, 1, 401, "Cloth", "Interface\\Icons\\G")
DATA[107] = { id = 107, name = "Late Bloomer", quality = 3, ilvl = 120, typeKey = 403,
              typeName = "Armor", subtypeName = "Mail", icon = "Interface\\Icons\\H",
              equipLoc = "INVTYPE_CHEST" }
-- 107 ist zunaechst NICHT aufgeloest

S.lists[4] = {
   ids = { 100, 101, 102, 103, 104, 105, 106, 107, 108 },
   set = { [100] = true, [101] = true, [102] = true, [103] = true, [104] = true,
           [105] = true, [106] = true, [107] = true, [108] = true },
   received = 9, amount = 9, ready = true,
}
S.equipped[4] = { id = 999, typeKey = 404, quality = 4 }

local function reset()
   local f = T.DB.char.filter
   f.qualities, f.typesOff = {}, {}
   f.hideDuplicates, f.sort, f.favoritesOnly, f.newOnly = true, "QUALITY", false, false
   T.DB.char.favorites = {}
   T.State.new = {}
   S.wanted, S.baseline, S.applied = {}, {}, {}
   Filter.search = ""
   Filter.Invalidate()
end

-- ---------------------------------------------------------------------------
-- Filter: Grundverhalten
-- ---------------------------------------------------------------------------

reset()
local entries, stats = Filter.Compute(4)
eq(ids(entries), "100,102,101,103,104,106,108", "Standard: Qualitaet absteigend, Name aufsteigend, Duplikat 105 weg")
eq(stats.total, 9, "stats.total")
eq(stats.shown, 7, "stats.shown")
eq(stats.unresolved, 1, "stats.unresolved")
eq(stats.hiddenByFilter, 0, "stats.hiddenByFilter")
eq(stats.hiddenDuplicates, 1, "stats.hiddenDuplicates")
eq(stats.resolved, 8, "stats.resolved")
check(stats.ready, "stats.ready")
check(requested and arr(requested) == "107", "unbekannte Items angemeldet: " .. tostring(requested and arr(requested)))
eq(entries[1].favorite, false, "favorite ist Boolean false")
eq(entries[1].isNew, false, "isNew ist Boolean false")
eq(entries[1].applied, false, "applied ist Boolean false")
eq(entries[1].wanted, false, "wanted ist Boolean false")
check(entries[1].info == DATA[100], "info-Referenz")

-- Cache-Treffer: gleiches Ergebnis (stats.version), aber eigene Kopien
local entries2, stats2 = Filter.Compute(4)
eq(stats2.version, stats.version, "Cache-Treffer: gleiche stats.version")
check(entries ~= entries2 and stats ~= stats2, "Cache-Treffer liefert Kopien")
eq(ids(entries2), ids(entries), "Cache-Treffer: gleicher Inhalt")
check(entries2[1] == entries[1], "Eintrags-Tabellen sind geteilt")
check(stats.version > 0, "stats.version > 0 nach Berechnung")
-- Veraendern der Kopien darf den Cache nicht beschaedigen
table.insert(entries2, 1, { id = -1 })
entries2[2] = nil
stats2.shown = 999
local entries3, stats3 = Filter.Compute(4)
eq(ids(entries3), "100,102,101,103,104,106,108", "Cache nach Veraenderung der Kopie unversehrt")
eq(stats3.shown, 7, "stats nach Veraenderung der Kopie unversehrt")

-- Unaufgeloeste Items werden gedrosselt erneut angemeldet (Cache-Treffer)
local before = requestCalls
Filter.Compute(4)
eq(requestCalls, before, "kein erneutes Anmelden vor Ablauf der Drosselung")
clock = clock + 6
Filter.Compute(4)
eq(requestCalls, before + 1, "erneutes Anmelden nach 5 s")

-- Duplikate nicht ausblenden
Filter.SetHideDuplicates(false)
entries, stats = Filter.Compute(4)
eq(ids(entries), "100,102,101,103,104,105,106,108", "ohne Duplikat-Filter")
eq(stats.hiddenDuplicates, 0, "hiddenDuplicates ohne Filter")
Filter.SetHideDuplicates(true)

-- Sortierungen
Filter.SetSort("name")
entries = Filter.Compute(4)
eq(ids(entries), "103,104,102,100,101,108,106", "Sort NAME: " .. ids(entries))
-- Hinweis: "cloth robe delta" < "leather epsilon" < "mail chest gamma" < "plate chest alpha" < "plate chest beta" < "rag" < "strange thing"
Filter.SetSort("ILEVEL")
entries = Filter.Compute(4)
eq(ids(entries), "100,101,102,103,104,106,108", "Sort ILEVEL")
Filter.SetSort("bogus")
eq(T.DB.char.filter.sort, "ILEVEL", "ungueltiger Sortierschluessel wird ignoriert")
Filter.SetSort("QUALITY")

-- Qualitaetsfilter
fired = {}
Filter.SetQuality(0, false)
eq(fired.FILTER_CHANGED, 1, "SetQuality feuert FILTER_CHANGED")
Filter.SetQuality(0, false)
eq(fired.FILTER_CHANGED, 1, "SetQuality ohne Aenderung feuert nicht")
entries, stats = Filter.Compute(4)
eq(ids(entries), "100,102,101,103,104,106", "Qualitaet 0 ausgeblendet")
eq(stats.hiddenByFilter, 1, "hiddenByFilter = 1")
check(T.DB.char.filter.qualities[0] == false, "qualities[0] == false")
Filter.SetQuality(0, true)
check(T.DB.char.filter.qualities[0] == nil, "qualities[0] == nil nach Einblenden")
check(not Filter.IsActive(), "kein Filter aktiv")

-- Typfilter, eigener Typ nie ausgeblendet, Items ohne typeKey nie
Filter.SetType(401, false)
Filter.SetType(404, false)   -- eigener Typ (Ausruestung ist 404)
entries, stats = Filter.Compute(4)
eq(ids(entries), "100,102,101,104,106", "Typ Stoff aus, Platte (own) bleibt, typeKey nil bleibt: " .. ids(entries))
eq(stats.hiddenByFilter, 2, "hiddenByFilter durch Typ")
check(Filter.IsActive(), "IsActive durch Typfilter")
Filter.SetType(403, false)
entries = Filter.Compute(4)
eq(ids(entries), "100,101,104,106", "Kette zusaetzlich aus")
Filter.Reset()
check(not Filter.IsActive(), "Reset -> nicht aktiv")
eq(next(T.DB.char.filter.typesOff), nil, "typesOff nach Reset leer")
eq(T.DB.char.filter.hideDuplicates, true, "Reset laesst hideDuplicates")

-- ---------------------------------------------------------------------------
-- Suche
-- ---------------------------------------------------------------------------

Filter.SetSearch("plate")
entries = Filter.Compute(4)
eq(ids(entries), "100,101", "Suche 'plate': " .. ids(entries))
Filter.SetSearch("  PLATE  ")
eq(ids((Filter.Compute(4))), "100,101", "Suche getrimmt/Gross-Klein")
Filter.SetSearch("plate alpha")
eq(ids((Filter.Compute(4))), "100", "mehrere Begriffe (UND)")
Filter.SetSearch("armor")
eq(ids((Filter.Compute(4))), "100,102,101,103,104,108", "Suche im lokalisierten Typ (typeName): " .. ids((Filter.Compute(4))))
Filter.SetSearch("#101")
eq(ids((Filter.Compute(4))), "101", "Suche #101")
Filter.SetSearch("101")
eq(ids((Filter.Compute(4))), "101", "Suche reine Zahl 101")
-- "#id" meint die GANZE Item-ID (kein Praefix); es gibt keine Item-ID 10
Filter.SetSearch("#10")
eq(ids((Filter.Compute(4))), "", "Suche #10 (ganze ID, kein Praefix)")
Filter.SetSearch("#101 beta")
eq(ids((Filter.Compute(4))), "101", "Suche '#101 beta'")
Filter.SetSearch("#")
eq(ids((Filter.Compute(4))), "100,102,101,103,104,106,108", "einzelnes # filtert nicht")
check(not Filter.IsActive(), "einzelnes # ist kein aktiver Filter")
Filter.SetSearch("nomatchxyz")
entries, stats = Filter.Compute(4)
eq(#entries, 0, "keine Treffer")
eq(stats.hiddenByFilter, 8, "alle 8 aufgeloesten ausgeblendet")
-- Suche wirkt vor Duplikat-Zusammenfassung: 105 (Copy) passt, 101 nicht
Filter.SetSearch("copy")
eq(ids((Filter.Compute(4))), "105", "Duplikat-Repraesentant wird unter den Treffern gewaehlt")
Filter.SetSearch("")
fired = {}
Filter.SetSearch("   ")
eq(fired.FILTER_CHANGED, nil, "Leerraum -> kein Ereignis")

-- Komfort: Filter.state
check(Filter.state == T.DB.char.filter, "Filter.state ist DB.char.filter")
Filter.state.search = "gamma"
eq(Filter.search, "gamma", "Filter.state.search schreibt Filter.search")
eq(Filter.state.search, "gamma", "Filter.state.search liest Filter.search")
check(rawget(T.DB.char.filter, "search") == nil, "search wird nicht persistiert")
eq(ids((Filter.Compute(4))), "102", "Suche ueber Filter.state.search")
Filter.SetSearch("")

-- ---------------------------------------------------------------------------
-- Favoriten / Neu / Duplikat-Repraesentant
-- ---------------------------------------------------------------------------

reset()
T.DB.char.favorites[103] = true
Events.Fire("FAVORITES_CHANGED")
Filter.SetFavoritesOnly(true)
entries = Filter.Compute(4)
eq(ids(entries), "103", "nur Favoriten")
check(entries[1].favorite == true, "favorite true")
check(Filter.IsActive(), "Favoriten aktiv")
Filter.SetFavoritesOnly(false)

T.State.new[104] = true
Events.Fire("COLLECTION_UPDATED", 104)
Filter.SetNewOnly(true)
entries = Filter.Compute(4)
eq(ids(entries), "104", "nur Neue")
check(entries[1].isNew == true, "isNew true")
Filter.SetNewOnly(false)

-- Repraesentant: Gruppe {101 (q3), 105 (q2)}
reset()
entries = Filter.Compute(4)
check(ids(entries):find("101", 1, true) and not ids(entries):find("105", 1, true), "Repraesentant: hoehere Qualitaet")
T.DB.char.favorites[105] = true
Events.Fire("FAVORITES_CHANGED")
entries = Filter.Compute(4)
check(ids(entries):find("105", 1, true) and not ids(entries):find("101", 1, true), "Repraesentant: Favorit schlaegt Qualitaet")
S.baseline[4] = 101
Events.Fire("STATUS_CHANGED")
entries = Filter.Compute(4)
check(ids(entries):find("101", 1, true) and not ids(entries):find("105", 1, true), "Repraesentant: applied schlaegt Favorit")
local e101
for _, e in ipairs(entries) do if e.id == 101 then e101 = e end end
check(e101 and e101.applied, "applied-Flag gesetzt")
S.wanted[4] = 105
Events.Fire("WANTED_CHANGED", 4)
entries = Filter.Compute(4)
check(ids(entries):find("105", 1, true) and not ids(entries):find("101", 1, true), "Repraesentant: wanted schlaegt applied")
local e105
for _, e in ipairs(entries) do if e.id == 105 then e105 = e end end
check(e105 and e105.wanted and e105.favorite, "wanted-Flag gesetzt")
reset()
-- Gleichstand: niedrigere id gewinnt
item(110, "Twin A", 3, 100, 404, "Plate", "Interface\\Icons\\TWIN")
item(111, "Twin B", 3, 100, 404, "Plate", "Interface\\Icons\\TWIN")
S.lists[0] = { ids = { 111, 110 }, set = { [110] = true, [111] = true }, received = 2, ready = true }
entries = Filter.Compute(0)
eq(ids(entries), "110", "Gleichstand: niedrigere id ist Repraesentant")

-- ---------------------------------------------------------------------------
-- Cache-Invalidierung bei aufgeloesten Items
-- ---------------------------------------------------------------------------

reset()
entries, stats = Filter.Compute(4)
eq(stats.unresolved, 1, "vor Aufloesung: 1 unbekannt")
RESOLVED[107] = true
Events.Fire("ITEMS_RESOLVED", 1)
entries, stats = Filter.Compute(4)
eq(stats.unresolved, 0, "nach Aufloesung: 0 unbekannt")
eq(ids(entries), "100,107,102,101,103,104,106,108", "107 (q3, 'late bloomer') sortiert ein: " .. ids(entries))

-- Listenaenderung (ohne Ereignis) wird ueber die Signatur erkannt
S.lists[4].ids[#S.lists[4].ids + 1] = 120
S.lists[4].received = 10
item(120, "Brand New", 5, 300, 404, "Plate", "Interface\\Icons\\NEW")
entries = Filter.Compute(4)
eq(entries[1].id, 120, "neue Liste -> neu berechnet (Signatur)")
S.lists[4].ids[#S.lists[4].ids] = nil
S.lists[4].received = 9
RESOLVED[120] = nil

-- Listenversion (State.List(slot).version): Liste wird an Ort und Stelle
-- geaendert, alle Zaehler (Anzahl, received, ready) bleiben gleich
reset()
item(140, "Ver A", 3, 100, 404, "Plate", "Interface\\Icons\\VA")
item(141, "Ver B", 2, 100, 404, "Plate", "Interface\\Icons\\VB")
S.lists[9] = { ids = { 140 }, set = { [140] = true }, received = 1, ready = true, version = 1 }
entries = Filter.Compute(9)
eq(ids(entries), "140", "Listenversion: Ausgangslage")
S.lists[9].ids[1] = 141
entries = Filter.Compute(9)
eq(ids(entries), "140", "gleiche Listenversion: Cache-Treffer")
S.lists[9].version = 2
entries = Filter.Compute(9)
eq(ids(entries), "141", "neue Listenversion: neu berechnet")
S.lists[9] = nil

-- Selbstheilung: Aufloesung OHNE ITEMS_RESOLVED-Ereignis wird trotzdem bemerkt
reset()
RESOLVED[107] = nil
Filter.Invalidate()
entries, stats = Filter.Compute(4)
eq(stats.unresolved, 1, "Selbstheilung: vorher 1 unbekannt")
local mailCount = 0
for _, t in ipairs(Filter.Types(4)) do if t.typeKey == 403 then mailCount = t.count end end
eq(mailCount, 1, "Selbstheilung: Mail-Zaehler vorher 1")
RESOLVED[107] = true   -- bewusst kein Ereignis
entries, stats = Filter.Compute(4)
eq(stats.unresolved, 1, "Selbstheilung ist gedrosselt (< 0,25 s)")
mailCount = 0
for _, t in ipairs(Filter.Types(4)) do if t.typeKey == 403 then mailCount = t.count end end
eq(mailCount, 1, "Selbstheilung der Facetten ist gedrosselt")
clock = clock + 0.3
entries, stats = Filter.Compute(4)
eq(stats.unresolved, 0, "Selbstheilung: Compute bemerkt Aufloesung")
mailCount = 0
for _, t in ipairs(Filter.Types(4)) do if t.typeKey == 403 then mailCount = t.count end end
eq(mailCount, 2, "Selbstheilung: Facetten bemerken Aufloesung")

-- Facetten-Arrays sind Kopien
do
   local a = Filter.Types(4)
   local n = #a
   a[#a + 1] = { typeKey = 1 }
   eq(#Filter.Types(4), n, "Filter.Types liefert eine Kopie")
   local qa = Filter.Qualities(4)
   local qn = #qa
   qa[#qa + 1] = { quality = 9, count = 1 }
   eq(#Filter.Qualities(4), qn, "Filter.Qualities liefert eine Kopie")
end

-- ---------------------------------------------------------------------------
-- Facetten
-- ---------------------------------------------------------------------------

reset()
Filter.Invalidate()
local types = Filter.Types(4)
local tkeys, labels = {}, {}
for i, t in ipairs(types) do tkeys[i] = t.typeKey; labels[i] = t.label end
eq(arr(tkeys), "404,403,402,401", "Typen: Platte -> Stoff: " .. arr(tkeys))
eq(labels[1], "Plate", "Typ-Label aus Items.TypeLabel")
eq(types[1].count, 3, "Plate: 100,101,105")
check(types[1].own and not types[2].own, "own-Flag nur auf Platte")
local quals = Filter.Qualities(4)
local qk = {}
for i, q in ipairs(quals) do qk[i] = q.quality .. "x" .. q.count end
eq(arr(qk), "0x1,1x1,2x3,3x3,4x1", "Qualitaeten aufsteigend, ungefiltert gezaehlt: " .. arr(qk))
-- Facetten bleiben ungefiltert, auch wenn Filter aktiv sind
Filter.SetType(401, false)
eq(#Filter.Types(4), 4, "Typen ungefiltert")
Filter.Reset()
-- Types listet nur Typen, die in der Liste des Slots vorkommen: ein own-Typ
-- ohne Items in der Liste erscheint nicht (es gaebe nichts auszublenden)
S.equipped[4] = { id = 999, typeKey = 405 }
Filter.Invalidate()
types = Filter.Types(4)
eq(#types, 4, "own-Typ ohne Items wird nicht zusaetzlich gelistet")
local ownCount = 0
for _, t in ipairs(types) do if t.own then ownCount = ownCount + 1 end end
eq(ownCount, 0, "kein own-Typ in der Liste")
S.equipped[4] = { id = 999, typeKey = 404 }
Filter.Invalidate()

-- Waffen: Reihenfolge nach typeKey
item(130, "Axe", 3, 100, 201, "Two-Handed Axes", "Interface\\Icons\\AXE", "INVTYPE_2HWEAPON")
item(131, "Sword", 3, 100, 207, "One-Handed Swords", "Interface\\Icons\\SWORD", "INVTYPE_WEAPON")
item(132, "Shield", 3, 100, 406, "Shields", "Interface\\Icons\\SHIELD", "INVTYPE_SHIELD")
S.lists[15] = { ids = { 132, 131, 130 }, set = {}, received = 3, ready = true }
S.equipped[15] = { id = 998, typeKey = 207 }
types = Filter.Types(15)
tkeys = {}
for i, t in ipairs(types) do tkeys[i] = t.typeKey end
eq(arr(tkeys), "201,207,406", "Nicht-Ruestungstypen nach typeKey")

-- ---------------------------------------------------------------------------
-- Seiten
-- ---------------------------------------------------------------------------

local list = {}
for i = 1, 25 do list[i] = { id = i } end
local pg, total, cur = Filter.Page(list, 1, 10)
eq(#pg, 10, "Seite 1 hat 10")
eq(total, 3, "3 Seiten")
eq(cur, 1, "Seite 1")
pg, total, cur = Filter.Page(list, 3, 10)
eq(#pg, 5, "Seite 3 hat 5")
eq(pg[1].id, 21, "Seite 3 beginnt bei 21")
pg, total, cur = Filter.Page(list, 99, 10)
eq(cur, 3, "Seite geklemmt (oben)")
pg, total, cur = Filter.Page(list, -4, 10)
eq(cur, 1, "Seite geklemmt (unten)")
pg, total, cur = Filter.Page({}, 5, 10)
eq(total, 1, "leere Liste -> 1 Seite")
eq(cur, 1, "leere Liste -> Seite 1")
eq(#pg, 0, "leere Seite")
pg, total, cur = Filter.Page(list, nil, nil)
eq(total, 25, "perPage nil -> 1")
pg, total, cur = Filter.Page(nil, 1, 10)
eq(total, 1, "entries nil")
pg, total, cur = Filter.Page(list, 0/0, 10)
eq(cur, 1, "NaN-Seite -> 1")

-- ---------------------------------------------------------------------------
-- Robustheit: ungueltige Slots, nil-Daten
-- ---------------------------------------------------------------------------

entries, stats = Filter.Compute(nil)
eq(#entries, 0, "Compute(nil) leer")
eq(stats.total, 0, "Compute(nil) total 0")
entries, stats = Filter.Compute(11)   -- Slot ohne Liste
eq(#entries, 0, "Slot ohne Liste leer")
eq(stats.total, 0, "Slot ohne Liste total 0")
eq(#Filter.Types(11), 0, "Types leer")
eq(#Filter.Qualities(11), 0, "Qualities leer")
S.lists[7] = { ids = { 100, "101", 0, -5, 100, 9999 }, set = {}, received = 6, ready = true }
entries, stats = Filter.Compute(7)
eq(ids(entries), "100,101", "ids: Strings/0/negativ/Doppelte tolerant: " .. ids(entries))
eq(stats.unresolved, 1, "9999 unbekannt")
S.lists[8] = { ids = { 100, 999999 }, set = {}, received = 2, ready = true }
entries, stats = Filter.Compute(8)
eq(ids(entries), "100", "HIDDEN-ID in der Liste wird ignoriert")
eq(stats.unresolved, 0, "HIDDEN-ID zaehlt nicht als unbekannt")
eq(Filter.QualityLabel(4), "Epic", "QualityLabel Fallback")
eq(Filter.SortLabel("NAME"), "Name", "SortLabel aus enUS_Filter")

-- ---------------------------------------------------------------------------
-- Leistung / Ordnung: 3000 Eintraege
-- ---------------------------------------------------------------------------

local N = 3000
local big = { ids = {}, set = {}, received = N, ready = true }
local seed = 12345
local function rnd(n)
   seed = (seed * 1103515245 + 12345) % 2147483648
   return math.floor(seed / 65536) % n   -- obere Bits (die unteren sind bei LCGs schwach)
end
for i = 1, N do
   local id = 20000 + i
   local tk = 401 + rnd(4)
   -- viele Gleichstaende: wenige Qualitaeten/Namen/Itemlevel, Icons teils gleich
   item(id, "Name " .. rnd(40), rnd(6), 100 + rnd(5) * 10, tk, "Sub" .. tk, "Interface\\Icons\\I" .. rnd(900))
   big.ids[i] = id
   big.set[id] = true
end
S.lists[3] = big
S.equipped[3] = { id = 1, typeKey = 403 }

for _, key in ipairs({ "QUALITY", "NAME", "ILEVEL" }) do
   Filter.SetSort(key)
   local t0 = os.clock()
   local ok, res, st = pcall(Filter.Compute, 3)
   local dt = os.clock() - t0
   check(ok, "Compute(3000) wirft nicht (" .. key .. "): " .. tostring(res))
   if ok then
      check(#res > 0, "Compute(3000) liefert Eintraege")
      -- Ordnung pruefen
      local good = true
      for i = 2, #res do
         local a, b = res[i - 1], res[i]
         if key == "QUALITY" then
            if a.quality < b.quality or (a.quality == b.quality and (a.nameKey > b.nameKey
               or (a.nameKey == b.nameKey and a.id >= b.id))) then good = false end
         elseif key == "NAME" then
            if a.nameKey > b.nameKey or (a.nameKey == b.nameKey and a.id >= b.id) then good = false end
         else
            if a.ilvl < b.ilvl or (a.ilvl == b.ilvl and (a.quality < b.quality
               or (a.quality == b.quality and (a.nameKey > b.nameKey
               or (a.nameKey == b.nameKey and a.id >= b.id))))) then good = false end
         end
      end
      check(good, "Sortierung korrekt (" .. key .. ")")
      print(string.format("  Compute(3000, %s): %.1f ms, shown=%d, dup=%d", key, dt * 1000, st.shown, st.hiddenDuplicates))
      check(dt < 0.5, "Compute(3000) schnell genug (" .. key .. ")")
   end
end
-- ohne Duplikat-Filter und mit Suche
Filter.SetHideDuplicates(false)
local t0 = os.clock()
entries, stats = Filter.Compute(3)
print(string.format("  Compute(3000, ohne Duplikatfilter): %.1f ms, shown=%d", (os.clock() - t0) * 1000, stats.shown))
eq(stats.shown, N, "ohne Duplikatfilter alle 3000")
t0 = os.clock()
local e3 = Filter.Compute(3)
local hitTime = os.clock() - t0
print(string.format("  Cache-Treffer: %.3f ms", hitTime * 1000))
eq(select(2, Filter.Compute(3)).version, stats.version, "Cache-Treffer: gleiche Version")
check(#e3 == #entries, "Cache-Treffer: gleiche Laenge")
Filter.SetSearch("name 17")
t0 = os.clock()
entries, stats = Filter.Compute(3)
print(string.format("  Compute(3000, Suche 'name 17'): %.1f ms, shown=%d", (os.clock() - t0) * 1000, stats.shown))
check(stats.shown > 0 and stats.shown < N, "Suche reduziert")
local allMatch = true
for _, e in ipairs(entries) do if e.nameKey ~= "name 17" then allMatch = false end end
check(allMatch, "Suche 'name 17' trifft nur Name 17")
Filter.SetSearch("")
Filter.SetHideDuplicates(true)
Filter.Reset()

-- ---------------------------------------------------------------------------
-- Outfits
-- ---------------------------------------------------------------------------

-- Init: Aufraeumen
T.DB.char.outfits = {
   { name = "  Raid   Look ", slots = { [0] = 100, [4] = "200", [1] = 5, [15] = 999999, [18] = 999999 }, time = 5 },
   { name = "raid look", slots = { [0] = 1 } },
   { name = "", slots = {} },
   "muell",
   { name = "Bar|cffff0000Red", slots = { ["3"] = 7 } },
}
Outfits.Init()
local o = T.DB.char.outfits
eq(#o, 4, "Init: Muell entfernt, 4 Outfits")
eq(o[1].name, "Raid Look", "Init: Name bereinigt")
eq(o[2].name, "raid look (2)", "Init: doppelter Name eindeutig")
eq(o[3].name, "Outfit 3", "Init: leerer Name -> Standardname")
eq(o[4].name, "BarRed", "Init: Farbcode samt Pipe entfernt")
eq(o[1].slots[0], 100, "Init: Slot 0 bleibt")
eq(o[1].slots[4], 200, "Init: String-ID -> Zahl")
eq(o[1].slots[1], nil, "Init: Nicht-Transmog-Slot entfernt")
eq(o[1].slots[15], nil, "Init: HIDDEN im Waffenslot entfernt")
eq(o[1].slots[18], 999999, "Init: HIDDEN im Wappenrock bleibt")
eq(o[4].slots[3], 7, "Init: String-Slotschluessel -> Zahl")
eq(o[1].time, 5, "Init: time bleibt")
Outfits.Init()
eq(#T.DB.char.outfits, 4, "Init ist idempotent")
check(T.DB.char.outfits == o, "Init ersetzt in-place (gleiche Referenz)")

-- Init: zu lange Namen werden gekuerzt (Zeichen, nicht Bytes), bleiben eindeutig
T.DB.char.outfits = {
   { name = string.rep("x", 40), slots = { [0] = 1 } },
   { name = string.rep("x", 35), slots = { [0] = 2 } },
   { name = string.rep("\195\164", 40), slots = { [0] = 3 } },
}
Outfits.Init()
o = T.DB.char.outfits
eq(o[1].name, string.rep("x", 32), "Init: langer Name auf 32 Zeichen gekuerzt")
eq(o[2].name, string.rep("x", 28) .. " (2)", "Init: gekuerzter doppelter Name bleibt <= 32 und eindeutig")
eq(#o[3].name, 64, "Init: UTF-8-Name auf 32 Zeichen (64 Bytes) gekuerzt")
for i = 1, #o do
   check(select(2, o[i].name:gsub("[^\128-\191]", "")) <= 32, "Init: Name " .. i .. " hoechstens 32 Zeichen")
   check(Outfits.ValidateName("zz" .. i), "ValidateName nach Init " .. i)
end

T.DB.char.outfits = {}
local ok, err = Outfits.ValidateName("")
check(not ok and err == "OUTFIT_ERR_EMPTY", "ValidateName leer")
ok, err = Outfits.ValidateName("   \t ")
check(not ok and err == "OUTFIT_ERR_EMPTY", "ValidateName nur Leerraum")
ok, err = Outfits.ValidateName(nil)
check(not ok and err == "OUTFIT_ERR_EMPTY", "ValidateName nil")
ok, err = Outfits.ValidateName(string.rep("x", 33))
check(not ok and err == "OUTFIT_ERR_LONG", "ValidateName 33 Zeichen")
ok, err = Outfits.ValidateName(string.rep("x", 32))
check(ok and err == nil, "ValidateName 32 Zeichen ok")
ok, err = Outfits.ValidateName(string.rep("\195\164", 32))   -- 32 x "ae" (UTF-8, 64 Byte)
check(ok, "ValidateName 32 UTF-8-Zeichen (64 Byte) ok")
ok, err = Outfits.ValidateName(string.rep("\195\164", 33))
check(not ok and err == "OUTFIT_ERR_LONG", "ValidateName 33 UTF-8-Zeichen")

-- Save
fired = {}
local look = { [0] = 100, [4] = 101, [18] = 999999, [15] = 130 }
ok, err = Outfits.Save("  Mein Outfit ", look)
check(ok and err == nil, "Save ok")
eq(fired.OUTFITS_CHANGED, 1, "Save feuert OUTFITS_CHANGED")
check(Outfits.Exists("mein OUTFIT"), "Exists ohne Beachtung der Schreibweise")
local got = Outfits.Get("MEIN outfit")
check(got ~= nil and got.name == "Mein Outfit", "Get liefert Outfit, Name getrimmt")
eq(got.count, 4, "count = 4")
eq(got.time, 1700000000 + clock, "time gesetzt")
look[0] = 555   -- Aenderung am Original darf das Outfit nicht beeinflussen
eq(got.slots[0], 100, "Save kopiert die Slot-Tabelle")
ok, err = Outfits.Save("MEIN OUTFIT", look)
check(not ok and err == "OUTFIT_ERR_EXISTS", "Save ueberschreibt nie still (EXISTS)")
eq(got.slots[0], 100, "bestehendes Outfit unveraendert")
ok, err = Outfits.Save("Leer", {})
check(not ok and err == "OUTFIT_ERR_NOITEMS", "Save ohne Teile -> NOITEMS")
ok, err = Outfits.Save("Muell", { [1] = 5, [10] = 5, [0] = 0, [2] = -3 })
check(not ok and err == "OUTFIT_ERR_NOITEMS", "Save nur ungueltige Teile -> NOITEMS")

-- Overwrite
fired = {}
ok, err = Outfits.Overwrite("mein outfit", { [0] = 777 })
check(ok, "Overwrite ok")
eq(Outfits.Get("Mein Outfit").slots[0], 777, "Overwrite ersetzt Teile")
eq(Outfits.Get("Mein Outfit").slots[4], nil, "Overwrite ersetzt komplett")
eq(Outfits.Get("Mein Outfit").count, 1, "count nach Overwrite")
eq(fired.OUTFITS_CHANGED, 1, "Overwrite feuert")
ok, err = Outfits.Overwrite("gibt es nicht", { [0] = 1 })
check(not ok and err == "OUTFIT_ERR_MISSING", "Overwrite unbekannt")

-- aktueller Look via State.Wanted
S.wanted = { [0] = 100, [4] = 999999, [16] = 555 }
S.baseline = { [3] = 300 }
local cur2 = Outfits.CurrentLook()
eq(cur2[0], 100, "CurrentLook: Wanted")
eq(cur2[4], 999999, "CurrentLook: HIDDEN enthalten")
eq(cur2[16], 555, "CurrentLook: Offhand")
eq(cur2[3], 300, "CurrentLook: Baseline")
eq(cur2[2], nil, "CurrentLook: leer bleibt leer")
ok = Outfits.Save("Aktuell", nil)
check(ok, "Save(name, nil) nimmt aktuellen Look")
eq(Outfits.Get("Aktuell").count, 4, "aktueller Look: 4 Teile")
S.wanted, S.baseline = {}, {}

-- Rename
fired = {}
ok, err = Outfits.Rename("mein outfit", "Aktuell")
check(not ok and err == "OUTFIT_ERR_EXISTS", "Rename auf bestehenden Namen")
ok, err = Outfits.Rename("mein outfit", "")
check(not ok and err == "OUTFIT_ERR_EMPTY", "Rename leer")
ok, err = Outfits.Rename("mein outfit", string.rep("y", 40))
check(not ok and err == "OUTFIT_ERR_LONG", "Rename zu lang")
ok, err = Outfits.Rename("nix", "Neu")
check(not ok and err == "OUTFIT_ERR_MISSING", "Rename unbekannt")
ok = Outfits.Rename("mein outfit", "MEIN OUTFIT")
check(ok and Outfits.Get("mein outfit").name == "MEIN OUTFIT", "Rename nur Schreibweise erlaubt")
ok = Outfits.Rename("MEIN OUTFIT", "Drache")
check(ok and Outfits.Exists("Drache") and not Outfits.Exists("MEIN OUTFIT"), "Rename ok")
eq(fired.OUTFITS_CHANGED, 2, "Rename feuert nur bei Aenderung")

-- Delete
ok, err = Outfits.Delete("nix")
check(not ok and err == "OUTFIT_ERR_MISSING", "Delete unbekannt")
ok = Outfits.Delete("DRACHE")
check(ok and not Outfits.Exists("Drache"), "Delete ok")
eq(#Outfits.List(), 1, "ein Outfit uebrig")

-- Limit
for i = 1, Outfits.MAX - 1 do
   ok, err = Outfits.Save("O" .. i, { [0] = i })
   if not ok then check(false, "Save " .. i .. " sollte gehen: " .. tostring(err)) break end
end
eq(#Outfits.List(), Outfits.MAX, "genau MAX Outfits")
ok, err = Outfits.Save("Zuviel", { [0] = 1 })
check(not ok and err == "OUTFIT_ERR_FULL", "MAX erreicht -> FULL")
-- Ueberschreiben/Umbenennen bleibt moeglich
ok = Outfits.Overwrite("O1", { [0] = 2 })
check(ok, "Overwrite bei vollem Speicher ok")
for i = 2, Outfits.MAX - 1 do Outfits.Delete("O" .. i) end
eq(#Outfits.List(), 2, "aufgeraeumt")

-- SuggestName
eq(Outfits.SuggestName(), "Outfit 3", "SuggestName: naechste freie Nummer")
Outfits.Save("Outfit 3", { [0] = 9 })
eq(Outfits.SuggestName(), "Outfit 4", "SuggestName ueberspringt belegte")

-- Load
T.DB.char.outfits = {}
S.lists = {
   [0] = { ids = { 10 }, set = { [10] = true }, received = 1, ready = true },
   [4] = { ids = { 21 }, set = { [21] = true }, received = 1, ready = true },    -- 20 fehlt
   [6] = { ids = { }, set = {}, received = 0, ready = false },                  -- laedt noch
   [18] = { ids = {}, set = {}, received = 0, ready = true },
   [16] = { ids = { 50 }, set = { [50] = true }, received = 1, ready = true },
}
S.slotState = { [2] = "EMPTY", [17] = "NEVER" }
ok = Outfits.Save("Voll", {
   [0] = 10, [2] = 30, [4] = 20, [6] = 40, [17] = 60, [18] = 999999, [16] = 50, [14] = 70,
})
check(ok, "Voll gespeichert")
-- Slot 14: Liste fehlt komplett -> ready=false -> LOADING
setManyCalls, lastMap = 0, nil
local applied, skipped = Outfits.Load("voll")
eq(arr(applied), "0,16,18", "Load: uebernommen 0,16,18: " .. arr(applied))
eq(setManyCalls, 1, "Load ruft State.SetMany genau einmal")
check(lastMap and lastMap[0] == 10 and lastMap[16] == 50 and lastMap[18] == 999999, "SetMany-Map korrekt")
local nMap = 0
for _ in pairs(lastMap) do nMap = nMap + 1 end
eq(nMap, 3, "SetMany-Map hat 3 Eintraege")
local reasons = {}
for _, sk in ipairs(skipped) do reasons[sk.slot] = sk.reasonKey end
eq(#skipped, 5, "5 uebersprungen")
eq(reasons[2], "OUTFIT_SKIP_EMPTY", "leerer Slot")
eq(reasons[4], "OUTFIT_SKIP_UNAVAILABLE", "nicht verfuegbar")
eq(reasons[6], "OUTFIT_SKIP_LOADING", "Liste laedt")
eq(reasons[14], "OUTFIT_SKIP_LOADING", "Liste fehlt")
eq(reasons[17], "OUTFIT_SKIP_NEVER", "nicht transmogbar")
eq(skipped[1][1], skipped[1].slot, "skipped positionell [1]=slot")
eq(skipped[1][2], skipped[1].id, "skipped positionell [2]=id")
eq(skipped[1][3], skipped[1].reasonKey, "skipped positionell [3]=reasonKey")
-- Check hat keine Seiteneffekte
setManyCalls = 0
local a2, s2 = Outfits.Check("voll")
eq(setManyCalls, 0, "Check ruft SetMany nicht")
eq(arr(a2), "0,16,18", "Check liefert dasselbe")
-- nichts uebernehmbar -> kein SetMany
Outfits.Save("Nur20", { [4] = 20 })
setManyCalls = 0
applied, skipped = Outfits.Load("Nur20")
eq(#applied, 0, "nichts uebernommen")
eq(#skipped, 1, "eins uebersprungen")
eq(setManyCalls, 0, "kein SetMany ohne Eintraege")
applied, skipped, err = Outfits.Load("gibt es nicht")
eq(#applied + #skipped, 0, "unbekanntes Outfit: leer")
eq(err, "OUTFIT_ERR_MISSING", "unbekanntes Outfit: Fehlerschluessel")

-- Rohdaten: HIDDEN im Waffenslot (nur durch Handarbeit am Speicher moeglich)
T.DB.char.outfits[#T.DB.char.outfits + 1] = { name = "Roh", slots = { [16] = 999999, [0] = 10 } }
setManyCalls, lastMap = 0, nil
applied, skipped = Outfits.Load("Roh")
eq(arr(applied), "0", "Rohdaten: nur Kopf uebernommen")
eq(#skipped, 1, "Rohdaten: HIDDEN im Waffenslot gemeldet")
eq(skipped[1].reasonKey, "OUTFIT_SKIP_HIDDEN", "Rohdaten: Grund HIDDEN")
eq(lastMap[16], nil, "Rohdaten: HIDDEN nicht gesetzt")

-- Liste ohne ready-Feld: Entscheidung allein ueber State.IsAvailable
S.lists[9] = { ids = { 80 }, set = { [80] = true } }
Outfits.Save("OhneReady", { [9] = 80, [7] = 81 })
S.lists[7] = { ids = {}, set = {} }
applied, skipped = Outfits.Load("OhneReady")
eq(arr(applied), "9", "ohne ready: verfuegbar -> uebernommen")
eq(skipped[1].reasonKey, "OUTFIT_SKIP_UNAVAILABLE", "ohne ready: Grund UNAVAILABLE")

-- RequestItems
requested, requestCalls = nil, 0
Outfits.RequestItems()
check(requested ~= nil and #requested > 0, "RequestItems fordert Items an")
local hasHidden = false
for _, id in ipairs(requested) do if id == 999999 then hasHidden = true end end
check(not hasHidden, "RequestItems laesst HIDDEN aus")

-- ohne DB.char: Notfall-Speicher, keine Fehler
local savedChar = T.DB.char
T.DB.char = nil
check(pcall(Outfits.List), "List ohne DB.char")
check(pcall(Outfits.Save, "X", { [0] = 1 }), "Save ohne DB.char")
check(pcall(Filter.Compute, 4), "Compute ohne DB.char")
check(pcall(Filter.IsActive), "IsActive ohne DB.char")
T.DB.char = savedChar

-- ---------------------------------------------------------------------------
-- Ergebnis
-- ---------------------------------------------------------------------------

print(string.format("%d Pruefungen bestanden, %d fehlgeschlagen", passes, failures))
os.exit(failures == 0 and 0 or 1)
