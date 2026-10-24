-- tests/_filter_integration.lua
-- ---------------------------------------------------------------------------
-- Wegwerf-Integrationstest fuer Core\Filter.lua und Core\Outfits.lua mit den
-- ECHTEN Modulen Locale, Init, Util, Events, DB, Slots, Items, Net und State.
-- Nur die WoW-API (CreateFrame, GetItemInfo, ...) ist nachgebaut; der Server
-- wird ueber Net.Handle mit Nachrichten im echten Protokollformat gespielt.
-- Aufruf im Hauptverzeichnis:  luajit tests/_filter_integration.lua
-- ---------------------------------------------------------------------------

local scriptDir = (arg and arg[0] or ""):match("^(.*)/tests/[^/]*$") or "."

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

local function ids(entries)
   local out = {}
   for i = 1, #entries do out[i] = tostring(entries[i].id) end
   return table.concat(out, ",")
end

local function arr(t)
   local out = {}
   for i = 1, #t do out[i] = tostring(t[i]) end
   return table.concat(out, ",")
end

-- ---------------------------------------------------------------------------
-- WoW-Attrappe
-- ---------------------------------------------------------------------------

local now = 1000
local frames = {}
local known = {}      -- [id] = Datensatz im Client-Cache
local serverItems = {}-- [id] = Datensatz, der nach Abfrage bekannt wird
local queriedAt = {}  -- [id] = Zeit der Abfrage
local equip = {}      -- [clientSlot] = Item-Link
local errors = {}
local DELAY = 0.3

local WEAPON_ENUS = { "One-Handed Axes", "Two-Handed Axes", "Bows", "Guns", "One-Handed Maces",
   "Two-Handed Maces", "Polearms", "One-Handed Swords", "Two-Handed Swords", "Staves",
   "Fist Weapons", "Miscellaneous", "Daggers", "Thrown", "Crossbows", "Wands", "Fishing Poles" }
local ARMOR_ENUS = { "Miscellaneous", "Cloth", "Leather", "Mail", "Plate", "Shields", "Librams",
   "Idols", "Totems", "Sigils" }
local CLASSES_ENUS = { "Weapon", "Armor", "Container", "Consumable", "Glyph", "Trade Goods",
   "Projectile", "Quiver", "Recipe", "Gem", "Miscellaneous", "Quest" }

local function makeFrame(kind, name)
   local f = { kind = kind, shown = true, scripts = {}, registered = {} }
   setmetatable(f, { __index = function() return function() end end })
   function f.SetScript(self, n, fn) self.scripts[n] = fn end
   function f.GetScript(self, n) return self.scripts[n] end
   function f.RegisterEvent(self, ev) self.registered[ev] = true end
   function f.UnregisterEvent(self, ev) self.registered[ev] = nil end
   function f.Show(self) self.shown = true end
   function f.Hide(self) self.shown = false end
   function f.IsShown(self) return self.shown end
   if kind == "GameTooltip" then
      function f.SetOwner(self, owner) self.owner = owner end
      function f.SetHyperlink(self, link)
         local id = tonumber(tostring(link):match("^item:(%d+)"))
         if id and queriedAt[id] == nil then queriedAt[id] = now end
      end
      function f.Show() error("Scan-Tooltip darf nie Show() erhalten") end
   end
   if name then _G[name] = f end
   return f
end

function GetTime() return now end
function time() return 1700000000 + math.floor(now) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function geterrorhandler() return function(msg) errors[#errors + 1] = tostring(msg) end end
function CreateFrame(kind, name)
   local f = makeFrame(kind, name)
   frames[#frames + 1] = f
   return f
end
UIParent = {}
function GetLocale() return "enUS" end
function UnitName() return "Tester" end
function UnitRace() return "Human", "Human" end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitFactionGroup() return "Alliance" end
function SendAddonMessage() end
function GetMoney() return 10000000 end
function GetInventoryItemLink(_, id) return equip[id] end
function GetInventorySlotInfo() return 1, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" end
function GetAuctionItemClasses() return unpack(CLASSES_ENUS) end
function GetAuctionItemSubClasses(i)
   if i == 1 then return unpack(WEAPON_ENUS) end
   if i == 2 then return unpack(ARMOR_ENUS) end
   return
end

function GetItemInfo(v)
   local id = tonumber(v) or tonumber(tostring(v):match("item:(%d+)"))
   if not id then return nil end
   local rec = known[id]
   if not rec then
      local srv = serverItems[id]
      if srv and queriedAt[id] and now - queriedAt[id] >= DELAY then
         known[id] = srv
         rec = srv
      end
   end
   if not rec then return nil end
   return rec.name, "|cffffffff|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. rec.name .. "]|h|r",
      rec.quality, rec.ilvl, 80, rec.class, rec.sub, 1, rec.loc, rec.icon, 100
end

-- Zeit vorruecken; OnUpdate aller sichtbaren Frames im 0,05-s-Takt
local function advance(dt)
   local steps = math.floor(dt / 0.05 + 0.5)
   for _ = 1, steps do
      now = now + 0.05
      for i = 1, #frames do
         local f = frames[i]
         local fn = f.scripts.OnUpdate
         if fn and f.shown then fn(f, 0.05) end
      end
   end
end

local function fireGame(event, ...)
   for i = 1, #frames do
      local f = frames[i]
      local fn = f.scripts.OnEvent
      if fn and f.registered[event] then fn(f, event, ...) end
   end
end

-- ---------------------------------------------------------------------------
-- Module laden (TOC-Reihenfolge)
-- ---------------------------------------------------------------------------

local function load(rel) dofile(scriptDir .. "/" .. rel) end

load("Locales/Locale.lua")
load("Locales/enUS_Core.lua")
load("Locales/enUS_State.lua")
load("Locales/enUS_Filter.lua")
load("Core/Init.lua")
load("Core/Util.lua")
load("Core/Events.lua")
load("Core/DB.lua")
load("Core/Slots.lua")
load("Core/Items.lua")
load("Core/Net.lua")
load("Core/State.lua")
load("Core/Filter.lua")
load("Core/Outfits.lua")

local T = Transmog
local Net, State, Filter, Outfits, Events = T.Net, T.State, T.Filter, T.Outfits, T.Events

-- Ereignisprotokoll
local fired = {}
for _, name in ipairs({ "FILTER_CHANGED", "OUTFITS_CHANGED", "WANTED_CHANGED", "LIST_READY",
                        "ITEMS_RESOLVED", "STATUS_CHANGED", "EQUIPMENT_CHANGED" }) do
   Events.On(name, function() fired[name] = (fired[name] or 0) + 1 end)
end

-- Ein Beobachter, der NACH Filter registriert wurde und in LIST_READY sofort
-- Compute ruft (wie Grid): muss bereits frische Daten sehen
local observed = {}
Events.On("LIST_READY", function(slot)
   local entries, stats = Filter.Compute(slot)
   observed[slot] = { ids = ids(entries), total = stats.total }
end)

T.DB.Init()
T.Locale.Set("enUS")
T.Slots.Init()
T.Items.Init()
T.State.Init()
T.enteredWorldAt = now - 60

-- ---------------------------------------------------------------------------
-- Gegenstaende
-- ---------------------------------------------------------------------------

local function def(id, name, quality, ilvl, class, sub, loc, icon, isKnown)
   local rec = { name = name, quality = quality, ilvl = ilvl, class = class, sub = sub,
                 loc = loc, icon = "Interface\\Icons\\" .. icon }
   if isKnown then known[id] = rec else serverItems[id] = rec end
end

local function link(id, name)
   return "|cffa335ee|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
end

-- angelegt (dem Client bekannt)
def(1001, "Helm of Plate", 4, 200, "Armor", "Plate", "INVTYPE_HEAD", "HeadP", true)
def(1004, "Chest of Plate", 4, 200, "Armor", "Plate", "INVTYPE_CHEST", "ChestP", true)
def(1005, "Chest of Mail", 4, 200, "Armor", "Mail", "INVTYPE_CHEST", "ChestM", true)
def(1015, "Sword of Doom", 4, 200, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "SwordD", true)
equip[1] = link(1001, "Helm of Plate")
equip[5] = link(1004, "Chest of Plate")
equip[16] = link(1015, "Sword of Doom")

-- Aussehen (erst nach Abfrage bekannt)
def(2001, "Plate Chest Alpha", 4, 200, "Armor", "Plate", "INVTYPE_CHEST", "A")
def(2002, "Plate Chest Beta", 3, 150, "Armor", "Plate", "INVTYPE_CHEST", "B")
def(2003, "Mail Chest Gamma", 3, 140, "Armor", "Mail", "INVTYPE_CHEST", "C")
def(2004, "Cloth Robe Delta", 2, 100, "Armor", "Cloth", "INVTYPE_ROBE", "D")
def(2005, "Leather Epsilon", 2, 90, "Armor", "Leather", "INVTYPE_CHEST", "E")
def(2006, "Plate Chest Beta Copy", 2, 80, "Armor", "Plate", "INVTYPE_CHEST", "B")   -- Duplikat von 2002
def(2101, "Plate Helm Zeta", 3, 150, "Armor", "Plate", "INVTYPE_HEAD", "H1")
def(2102, "Plate Helm Eta", 2, 100, "Armor", "Plate", "INVTYPE_HEAD", "H2")
def(2201, "Sword Alpha", 3, 100, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "S1")
def(2202, "Axe Beta", 3, 100, "Weapon", "Two-Handed Axes", "INVTYPE_2HWEAPON", "S2")

-- Server-Strom einspielen: ids in Chunks zu je 20
local function feed(slot, bucket, list)
   Net.Handle("AvailableTransmogs:" .. slot .. ":" .. bucket .. ":" .. #list .. ":start")
   local i = 1
   while i <= #list do
      local parts = {}
      for j = i, math.min(i + 19, #list) do parts[#parts + 1] = list[j] end
      Net.Handle("AvailableTransmogs:" .. slot .. ":" .. bucket .. ":" .. #list .. ":" .. table.concat(parts, ":"))
      i = i + 20
   end
   Net.Handle("AvailableTransmogs:" .. slot .. ":" .. bucket .. ":" .. #list .. ":end")
end

State.RefreshEquipment()
eq(State.SlotState(4), "READY", "Brust READY")
eq(State.SlotState(0), "READY", "Kopf READY")
eq(State.SlotState(15), "READY", "Haupthand READY")
eq(State.SlotState(2), "EMPTY", "Schulter leer")
eq(State.Equipped(4).typeKey, 404, "angelegte Brust: Platte")

-- ---------------------------------------------------------------------------
-- Liste laden: erst unbekannt, dann aufgeloest
-- ---------------------------------------------------------------------------

local entries, stats = Filter.Compute(4)
eq(#entries, 0, "ohne Liste: leer")
eq(stats.total, 0, "ohne Liste: total 0")
eq(stats.ready, false, "ohne Liste: nicht fertig")
eq(Filter.Compute(99) ~= nil, true, "unbekannter Slot wirft nicht")

fired = {}
feed(4, 405, { 2001, 2002, 2003, 2004, 2005, 2006 })
eq(fired.LIST_READY, 1, "LIST_READY einmal")
eq(observed[4] and observed[4].total, 6, "Beobachter nach Filter sieht die neue Liste in LIST_READY")
eq(observed[4] and observed[4].ids, "", "Beobachter: noch nichts aufgeloest")

entries, stats = Filter.Compute(4)
eq(#entries, 0, "Items unbekannt: keine Eintraege")
eq(stats.total, 6, "total 6")
eq(stats.unresolved, 6, "6 unbekannt")
eq(stats.ready, true, "Liste fertig")
check(T.Items.PendingCount() > 0, "Filter hat die Items bei Items angemeldet")

advance(1.0)
entries, stats = Filter.Compute(4)
eq(stats.unresolved, 0, "nach Aufloesung: 0 unbekannt")
eq(ids(entries), "2001,2003,2002,2004,2005", "Qualitaet absteigend, Name aufsteigend, Duplikat 2006 weg: " .. ids(entries))
eq(stats.hiddenDuplicates, 1, "ein Duplikat")
check(fired.ITEMS_RESOLVED and fired.ITEMS_RESOLVED >= 1, "ITEMS_RESOLVED gefeuert")
eq(entries[1].info.typeKey, 404, "typeKey aus echten AH-Listen: Platte")
eq(entries[2].info.typeKey, 403, "typeKey Kette")

-- Facetten
local types = Filter.Types(4)
local tk, own = {}, {}
for i, t in ipairs(types) do tk[i] = t.typeKey; own[i] = t.own and "1" or "0" end
eq(arr(tk), "404,403,402,401", "Typen: Platte -> Stoff")
eq(arr(own), "1,0,0,0", "own = angelegte Brust (Platte)")
eq(types[1].label, "Plate", "Label aus AH-Liste")
eq(types[1].count, 3, "3 Plattenteile (inkl. Duplikat)")
local quals = Filter.Qualities(4)
local qs = {}
for i, q in ipairs(quals) do qs[i] = q.quality .. "x" .. q.count end
eq(arr(qs), "2x3,3x2,4x1", "Qualitaeten")

-- ---------------------------------------------------------------------------
-- Filter
-- ---------------------------------------------------------------------------

fired = {}
Filter.SetType(401, false)
eq(fired.FILTER_CHANGED, 1, "SetType feuert")
entries, stats = Filter.Compute(4)
eq(ids(entries), "2001,2003,2002,2005", "Stoff ausgeblendet")
eq(stats.hiddenByFilter, 1, "ein ausgeblendet")
Filter.SetType(404, false)   -- eigener Typ: bleibt sichtbar
entries = Filter.Compute(4)
eq(ids(entries), "2001,2003,2002,2005", "eigener Typ nie ausgeblendet")
Filter.SetType(403, false)
entries = Filter.Compute(4)
eq(ids(entries), "2001,2002,2005", "Kette zusaetzlich ausgeblendet")
check(Filter.IsActive(), "IsActive")
Filter.Reset()
check(not Filter.IsActive(), "nach Reset inaktiv")
entries = Filter.Compute(4)
eq(ids(entries), "2001,2003,2002,2004,2005", "nach Reset wieder alles")

Filter.SetQuality(3, false)
entries = Filter.Compute(4)
-- 2002 (q3) weg => 2006 (q2, Plate B) wird Repraesentant seiner Gruppe
eq(ids(entries), "2001,2004,2005,2006", "Qualitaet 3 aus: Duplikat 2006 rueckt nach: " .. ids(entries))
Filter.SetQuality(3, true)

Filter.SetSearch("plate")
entries = Filter.Compute(4)
eq(ids(entries), "2001,2002", "Suche 'plate'")
Filter.SetSearch("#2003")
eq(ids((Filter.Compute(4))), "2003", "Suche #2003")
Filter.SetSearch("armor")
eq(ids((Filter.Compute(4))), "2001,2003,2002,2004,2005", "Suche im Typnamen 'Armor'")
Filter.SetSearch("")

Filter.SetSort("NAME")
eq(ids((Filter.Compute(4))), "2004,2005,2003,2001,2002", "Sort NAME")
Filter.SetSort("ILEVEL")
eq(ids((Filter.Compute(4))), "2001,2002,2003,2004,2005", "Sort ILEVEL")
Filter.SetSort("QUALITY")

-- ---------------------------------------------------------------------------
-- Status / Auswahl: applied / wanted, Repraesentant
-- ---------------------------------------------------------------------------

fired = {}
Net.Handle("TransmogStatus:1:4,2006")
eq(State.Applied(4), 2006, "Status uebernommen")
check(not State.IsInactive(4), "2006 steht in der Liste: aktiv")
entries = Filter.Compute(4)
eq(ids(entries), "2001,2003,2004,2005,2006", "applied-Duplikat 2006 ist Repraesentant: " .. ids(entries))
local e2006
for _, e in ipairs(entries) do if e.id == 2006 then e2006 = e end end
check(e2006 and e2006.applied, "applied-Flag")
check(e2006 and e2006.wanted, "ohne Auswahl ist wanted == Baseline (State.Wanted)")
check(not State.HasPending(4), "keine ausstehende Aenderung")

check(State.Select(4, 2002), "Select(4, 2002)")
eq(State.Wanted(4), 2002, "Wanted 2002")
entries = Filter.Compute(4)
eq(ids(entries), "2001,2003,2002,2004,2005", "wanted schlaegt applied: " .. ids(entries))
local e2002
for _, e in ipairs(entries) do if e.id == 2002 then e2002 = e end end
check(e2002 and e2002.wanted and not e2002.applied, "wanted-Flag")

-- Aussehen, das nicht mehr in der Liste steht => inaktiv => nicht applied
Net.Handle("TransmogStatus:1:4,9999")
check(State.IsInactive(4), "9999 nicht in Liste: inaktiv")
State.DiscardAll()
entries = Filter.Compute(4)
eq(ids(entries), "2001,2003,2002,2004,2005", "inaktiv: kein Eintrag applied")
Net.Handle("TransmogStatus:0")

-- ---------------------------------------------------------------------------
-- Zweiter Slot, Waffen, Ausruestungswechsel (own-Typ)
-- ---------------------------------------------------------------------------

feed(0, 405, { 2101, 2102 })
advance(1.0)
entries = Filter.Compute(0)
eq(ids(entries), "2101,2102", "Kopfliste")
eq(observed[0] and observed[0].total, 2, "Beobachter Kopf")

feed(15, 0, { 2201, 2202 })
advance(1.0)
types = Filter.Types(15)
tk = {}
for i, t in ipairs(types) do tk[i] = t.typeKey .. (t.own and "*" or "") end
eq(arr(tk), "201,207*", "Waffentypen, own = Einhandschwert (207)")

-- Brust wechselt auf Kette: own-Typ wechselt mit
fired = {}
equip[5] = link(1005, "Chest of Mail")
State.RefreshEquipment()
eq(State.Equipped(4).typeKey, 403, "angelegte Brust jetzt Kette")
check(fired.EQUIPMENT_CHANGED and fired.EQUIPMENT_CHANGED >= 1, "EQUIPMENT_CHANGED")
-- Liste ist jetzt veraltet (ready = false); neue Liste einspielen
eq(State.List(4).ready, false, "Liste nach Wechsel veraltet")
feed(4, 405, { 2001, 2002, 2003, 2004, 2005, 2006 })
Filter.SetType(403, false)
entries = Filter.Compute(4)
eq(ids(entries), "2001,2003,2002,2004,2005", "own (Kette) bleibt trotz typesOff sichtbar: " .. ids(entries))
Filter.SetType(403, true)
equip[5] = link(1004, "Chest of Plate")
State.RefreshEquipment()
feed(4, 405, { 2001, 2002, 2003, 2004, 2005, 2006 })
Filter.SetType(403, false)
entries = Filter.Compute(4)
eq(ids(entries), "2001,2002,2004,2005", "wieder Platte angelegt: Kette ausgeblendet")
Filter.Reset()

-- ---------------------------------------------------------------------------
-- Seiten
-- ---------------------------------------------------------------------------

entries = Filter.Compute(4)
local page, total, cur = Filter.Page(entries, 2, 2)
eq(#page, 2, "Seite 2 hat 2")
eq(total, 3, "3 Seiten")
eq(page[1].id, 2002, "Seite 2 beginnt bei 2002")
page, total, cur = Filter.Page(entries, 50, 2)
eq(cur, 3, "geklemmt")

-- ---------------------------------------------------------------------------
-- Outfits mit echtem State
-- ---------------------------------------------------------------------------

T.DB.char.outfits = {}
Outfits.Init()
State.DiscardAll()
Net.Handle("TransmogStatus:0")
check(State.Select(4, 2005), "Brust waehlen")
check(State.Select(0, 2101), "Kopf waehlen")
check(State.Select(0, T.HIDDEN_ID), "Kopf verbergen")   -- ersetzt die Auswahl
local look = Outfits.CurrentLook()
eq(look[4], 2005, "CurrentLook Brust")
eq(look[0], T.HIDDEN_ID, "CurrentLook Kopf verborgen")
eq(look[15], nil, "CurrentLook Waffe leer")

fired = {}
local ok, err = Outfits.Save("Mein Look", nil)
check(ok, "Save aktueller Look: " .. tostring(err))
eq(Outfits.Get("mein look").count, 2, "2 Teile")
ok, err = Outfits.Save("MEIN LOOK", nil)
check(not ok and err == "OUTFIT_ERR_EXISTS", "Save ueberschreibt nie")
eq(T.L.OUTFIT_ERR_EXISTS ~= "OUTFIT_ERR_EXISTS", true, "Fehlertext lokalisiert")

State.DiscardAll()
eq(State.PendingCount(), 0, "nichts ausstehend")
fired = {}
local applied, skipped = Outfits.Load("Mein Look")
eq(arr(applied), "0,4", "Load: Kopf und Brust")
eq(#skipped, 0, "Load: nichts uebersprungen")
eq(fired.WANTED_CHANGED, 1, "genau ein WANTED_CHANGED")
eq(State.Wanted(4), 2005, "Brust gewaehlt")
eq(State.Wanted(0), T.HIDDEN_ID, "Kopf verborgen gewaehlt")

-- Outfit mit nicht verfuegbaren / leeren / nicht verbergbaren Teilen
State.DiscardAll()
ok = Outfits.Save("Gemischt", {
   [0] = 2101,      -- verfuegbar
   [2] = 2101,      -- Schulter leer
   [4] = 2201,      -- nicht in der Brustliste
   [15] = 2201,     -- verfuegbar (Waffe)
   [16] = 2201,     -- Nebenhand leer
})
check(ok, "Gemischt gespeichert")
-- Waffe im Rohspeicher auf HIDDEN umbiegen (nicht verbergbar)
Outfits.Get("Gemischt").slots[15] = T.HIDDEN_ID
applied, skipped = Outfits.Load("Gemischt")
eq(arr(applied), "0", "nur der Kopf wird uebernommen")
local why = {}
for _, s in ipairs(skipped) do why[s.slot] = s.reasonKey end
eq(why[2], "OUTFIT_SKIP_EMPTY", "Schulter leer")
eq(why[4], "OUTFIT_SKIP_UNAVAILABLE", "Brust nicht verfuegbar")
eq(why[15], "OUTFIT_SKIP_HIDDEN", "Waffe nicht verbergbar")
eq(why[16], "OUTFIT_SKIP_EMPTY", "Nebenhand leer")
eq(State.Wanted(0), 2101, "Kopf gewaehlt")
eq(State.HasPending(0), true, "Kopf ausstehend")

-- Liste des Kopfes beginnt neu zu laden (Strom gestartet, noch leer):
-- Teile des Slots gelten als noch nicht verfuegbar, "Verborgen" geht ohne Liste
State.DiscardAll()
Net.Handle("AvailableTransmogs:0:405:2:start")
eq(State.List(0).ready, false, "Kopfliste laedt")
fired = {}
applied, skipped = Outfits.Load("Gemischt")
eq(#applied, 0, "Kopf: Liste laedt -> nichts uebernommen")
why = {}
for _, s in ipairs(skipped) do why[s.slot] = s.reasonKey end
eq(why[0], "OUTFIT_SKIP_LOADING", "Kopf: LOADING")
eq(fired.WANTED_CHANGED, nil, "nichts uebernommen => kein WANTED_CHANGED")
applied, skipped = Outfits.Load("Mein Look")
eq(arr(applied), "0,4", "Verborgen und Brust gehen ohne Kopfliste")
Net.Handle("AvailableTransmogs:0:405:2:end")
State.DiscardAll()

-- ---------------------------------------------------------------------------
-- Keine Fehler im Fehlerhandler
-- ---------------------------------------------------------------------------

eq(#errors, 0, "keine gemeldeten Fehler: " .. tostring(errors[1]))

print(string.format("%d Pruefungen bestanden, %d fehlgeschlagen", passes, failures))
os.exit(failures == 0 and 0 or 1)
