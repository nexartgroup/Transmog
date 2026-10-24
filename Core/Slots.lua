-- Slots.lua
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Die 14 transmogbaren Plaetze (T.Slots).
--
-- "server" ist der 0-basierte Server-Slot (EQUIPMENT_SLOT_*), "client" die
-- Inventar-ID des Spiels (server + 1). Alle Module sprechen in Server-Slots.
--
-- Anzeigereihenfolge (LIST):
--   Spalte 1 (links, oben nach unten):  HEAD SHOULDER BACK CHEST SHIRT TABARD WRIST
--   Spalte 2 (rechts):                  HANDS WAIST LEGS FEET MAINHAND OFFHAND RANGED
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog

T.Slots = T.Slots or {}
local Slots = T.Slots

-- Blizzard-Texturen der leeren Slots (Ersatz, falls GetInventorySlotInfo fehlt)
local EMPTY_FALLBACK = {
   HeadSlot          = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head",
   ShoulderSlot      = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder",
   BackSlot          = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",   -- Umhang nutzt die Brusttextur
   ChestSlot         = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
   ShirtSlot         = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shirt",
   TabardSlot        = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Tabard",
   WristSlot         = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists",
   HandsSlot         = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands",
   WaistSlot         = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist",
   LegsSlot          = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs",
   FeetSlot          = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet",
   MainHandSlot      = "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand",
   SecondaryHandSlot = "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand",
   RangedSlot        = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ranged",
}
local EMPTY_DEFAULT = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest"

-- Hilfsfunktion fuer die Tabelle: legt eine Definition an.
--   fallback = englischer Name, falls das Blizzard-Global fehlt
local function Def(key, server, invName, globalName, fallback, hideable, column, index)
   return {
      key = key, server = server, client = server + 1,
      invName = invName, globalName = globalName, fallback = fallback,
      hideable = hideable, column = column, index = index,
      weapon = (key == "MAINHAND" or key == "OFFHAND" or key == "RANGED"),
      hand = (key == "MAINHAND" or key == "OFFHAND"),
   }
end

-- Die 14 Definitionen in Anzeigereihenfolge.
Slots.LIST = {
   Def("HEAD",     0,  "HeadSlot",          "HEADSLOT",          "Head",      true,  1, 1),
   Def("SHOULDER", 2,  "ShoulderSlot",      "SHOULDERSLOT",      "Shoulders", true,  1, 2),
   Def("BACK",     14, "BackSlot",          "BACKSLOT",          "Back",      true,  1, 3),
   Def("CHEST",    4,  "ChestSlot",         "CHESTSLOT",         "Chest",     true,  1, 4),
   Def("SHIRT",    3,  "ShirtSlot",         "SHIRTSLOT",         "Shirt",     true,  1, 5),
   Def("TABARD",   18, "TabardSlot",        "TABARDSLOT",        "Tabard",    true,  1, 6),
   Def("WRIST",    8,  "WristSlot",         "WRISTSLOT",         "Wrist",     true,  1, 7),
   Def("HANDS",    9,  "HandsSlot",         "HANDSSLOT",         "Hands",     true,  2, 1),
   Def("WAIST",    5,  "WaistSlot",         "WAISTSLOT",         "Waist",     true,  2, 2),
   Def("LEGS",     6,  "LegsSlot",          "LEGSSLOT",          "Legs",      true,  2, 3),
   Def("FEET",     7,  "FeetSlot",          "FEETSLOT",          "Feet",      true,  2, 4),
   Def("MAINHAND", 15, "MainHandSlot",      "MAINHANDSLOT",      "Main Hand", false, 2, 5),
   Def("OFFHAND",  16, "SecondaryHandSlot", "SECONDARYHANDSLOT", "Off Hand",  false, 2, 6),
   Def("RANGED",   17, "RangedSlot",        "RANGEDSLOT",        "Ranged",    false, 2, 7),
}

Slots.COUNT = #Slots.LIST

Slots.BY_SERVER = {}
Slots.BY_KEY = {}
Slots.BY_CLIENT = {}

-- Position in LIST je Server-Slot (fuer Next)
local position = {}

for i = 1, #Slots.LIST do
   local def = Slots.LIST[i]
   Slots.BY_SERVER[def.server] = def
   Slots.BY_KEY[def.key] = def
   Slots.BY_CLIENT[def.client] = def
   position[def.server] = i
end

-- Leertextur-Cache je Server-Slot (GetInventorySlotInfo kostet etwas)
local emptyCache = {}

-- Initialisierung (Boot, nach PLAYER_LOGIN): wirft den Textur-Cache weg.
function Slots.Init()
   emptyCache = {}
end

-- Lokalisierter Slotname (Blizzard-Global, Ersatz englisch); unbekannt -> "?".
function Slots.Label(server)
   local def = Slots.BY_SERVER[server]
   if not def then
      return "?"
   end
   local util = T.Util
   if util and util.G then
      return util.G(def.globalName, def.fallback)
   end
   local value = _G[def.globalName]
   if type(value) == "string" and value ~= "" then
      return value
   end
   return def.fallback
end

-- Pfad der Leertextur des Slots (Paperdoll-Symbol); nie nil.
function Slots.EmptyTexture(server)
   local def = Slots.BY_SERVER[server]
   if not def then
      return EMPTY_DEFAULT
   end
   local cached = emptyCache[server]
   if cached then
      return cached
   end

   local path
   if type(GetInventorySlotInfo) == "function" then
      local ok, _, texture = pcall(GetInventorySlotInfo, def.invName)
      if ok and type(texture) == "string" and texture ~= "" then
         path = texture
      end
   end
   if not path then
      path = EMPTY_FALLBACK[def.invName] or EMPTY_DEFAULT
   end
   emptyCache[server] = path
   return path
end

-- Item-Link des angelegten Gegenstands im Slot oder nil.
function Slots.EquippedLink(server)
   local def = Slots.BY_SERVER[server]
   if not def or type(GetInventoryItemLink) ~= "function" then
      return nil
   end
   return GetInventoryItemLink("player", def.client)
end

-- true, wenn das Aussehen im Slot verborgen werden darf (0,2,3,4,5,6,7,8,9,14,18).
function Slots.IsHideable(server)
   local def = Slots.BY_SERVER[server]
   return def ~= nil and def.hideable == true
end

-- Naechster (dir > 0, Standard) oder vorheriger (dir < 0) Slot in Anzeige-
-- reihenfolge, zyklisch. Unbekannter/fehlender Slot: erster bzw. letzter.
function Slots.Next(server, dir)
   local count = #Slots.LIST
   local step = 1
   if type(dir) == "number" and dir < 0 then
      step = -1
   end
   local pos = position[server]
   if not pos then
      if step > 0 then
         return Slots.LIST[1].server
      end
      return Slots.LIST[count].server
   end
   pos = pos + step
   if pos > count then
      pos = 1
   elseif pos < 1 then
      pos = count
   end
   return Slots.LIST[pos].server
end
