-- Tooltips.lua  (T.Tooltips)
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Zusatzzeilen in Gegenstands-Tooltips.
--
--   (a) Item-Tooltips (GameTooltip, ItemRefTooltip, ShoppingTooltip1-3,
--       ItemRefShoppingTooltip1-3): rosa Zeile "Aussehen nicht gesammelt",
--       wenn der Server den Gegenstand als nicht gesammelt meldet.
--   (b) GameTooltip:SetInventoryItem("player", slot): rosa Zeile
--       "Transmogrifiziert zu: <Name>" bzw. "Verborgen" fuer angelegte
--       Gegenstaende mit angewendetem Aussehen.
--
-- Ablauf (a)
--   OnTooltipSetItem -> Gegenstands-ID aus tooltip:GetItem() -> nur Ausruestung
--   (equipLoc nicht leer und nicht Items.IsNever; unbekannte Iteminfo: Request
--   und ueberspringen, der Tooltip meldet sich beim naechsten OnTooltipSetItem
--   bzw. ITEMS_RESOLVED erneut) -> Net.CollectionState(id):
--       0    Zeile anfuegen
--       nil  Net.QueryCollection(id); die Zeile kommt mit COLLECTION_STATUS
--            (id, 0), sofern der Tooltip dann noch denselben Gegenstand zeigt
--       1/2  nichts
--   Net haelt den Sitzungs-Cache und die Flutbremse: je Gegenstand hoechstens
--   eine Abfrage. Ein "nicht gesammelt" (0) gilt dort nur 45 s (ein anderer
--   Zugang des Kontos kann den Gegenstand inzwischen gesammelt haben); danach
--   ist der Stand nil und der naechste Tooltip fragt neu. 1 und 2 bleiben. Ist
--   der Server stumm (Net.state "ABSENT"), wird gar nicht mehr gefragt.
--
-- Doppelte Zeilen sind ausgeschlossen, weil vor dem Anfuegen die vorhandenen
-- Zeilen des Tooltips nach demselben Text durchsucht werden (das gilt auch,
-- wenn OnTooltipSetItem mehrfach feuert oder die Antwort spaeter eintrifft).
--
-- Fehler: die Haken laufen in einem pcall (Guard). Ein Fehler stoert den
-- Tooltip des Spiels nicht und geht einmal je Meldung an den Fehlerbehandler,
-- nicht bei jedem Hover.
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.Tooltips = T.Tooltips or {}
local Tips = T.Tooltips

local L = T.L

local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring

-- Alle Tooltips, die Gegenstaende zeigen (nur vorhandene werden eingehaengt).
local TOOLTIP_NAMES = {
   "GameTooltip", "ItemRefTooltip",
   "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3",
   "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "ItemRefShoppingTooltip3",
}

local PINK_FALLBACK = { 0.96, 0.44, 0.96 }
local RED_FALLBACK = { 0.91, 0.40, 0.29 }

local hooked = {}               -- [tooltip] = { waitId = id|nil }
local inventoryHooked = false   -- SetInventoryItem-Hook liegt schon
local reported = {}             -- Fehlermeldungen der Haken, die schon gemeldet wurden
local reportedCount = 0         -- deren Anzahl (hoechstens MAX_REPORTS)
local MAX_REPORTS = 10          -- danach schweigen die Haken (kein Dauerfeuer)

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------

-- Verpackt einen Haken so, dass ein Fehler nie bis in den Tooltip-Aufruf des
-- Spiels durchschlaegt: er geht einmal je Meldung an den Fehlerbehandler (sonst
-- kaeme bei jedem Tooltip ein neuer Fehlerdialog).
local function Guard(fn)
   return function(...)
      local ok, err = pcall(fn, ...)
      if ok then
         return
      end
      err = tostring(err)
      if reported[err] or reportedCount >= MAX_REPORTS then
         return
      end
      reported[err] = true
      reportedCount = reportedCount + 1
      local getter = _G.geterrorhandler
      local handler = type(getter) == "function" and getter() or nil
      if type(handler) == "function" then
         pcall(handler, err)
      end
   end
end

-- true, wenn die Einstellung nicht ausdruecklich abgeschaltet ist; solange die
-- DB nicht bereit ist, false (dann wird auch nichts abgefragt).
local function Enabled(key)
   local db = T.DB
   local g = type(db) == "table" and db.global or nil
   if type(g) ~= "table" then
      return false
   end
   return g[key] ~= false
end

-- Farbe {r, g, b} aus T.COLORS (mit festem Ersatz).
local function Color(name, fallback)
   local c = type(T.COLORS) == "table" and T.COLORS[name] or nil
   if type(c) == "table" and type(c[1]) == "number" then
      return c
   end
   return fallback
end

-- Gegenstands-ID, die der Tooltip gerade zeigt (aus GetItem), sonst nil.
local function ItemIdOf(tip)
   if type(tip.GetItem) ~= "function" then
      return nil
   end
   local ok, _, link = pcall(tip.GetItem, tip)
   if not ok or type(link) ~= "string" then
      return nil
   end
   local util = T.Util
   if type(util) ~= "table" or type(util.ItemIdFromLink) ~= "function" then
      return nil
   end
   return util.ItemIdFromLink(link)
end

-- true, wenn der Tooltip schon eine linke Zeile mit genau diesem Text hat.
local function HasLine(tip, text)
   local name = type(tip.GetName) == "function" and tip:GetName() or nil
   if type(name) ~= "string" then
      return false
   end
   local n = tip:NumLines() or 0
   for i = n, 1, -1 do
      local fs = _G[name .. "TextLeft" .. i]
      if fs and type(fs.GetText) == "function" and fs:GetText() == text then
         return true
      end
   end
   return false
end

-- Haengt eine einzelne Zeile in Farbe c an (nur wenn sie noch fehlt) und laesst
-- den sichtbaren Tooltip neu ausmessen. Rueckgabe: true, wenn angefuegt.
local function AddColoredLine(tip, text, c)
   if HasLine(tip, text) then
      return false
   end
   tip:AddLine(text, c[1], c[2], c[3], true)
   if tip:IsShown() then
      tip:Show()
   end
   return true
end

-- Name des Gegenstands in Qualitaetsfarbe; ohne Iteminfo "Item <id>" (und eine
-- Anfrage, damit er beim naechsten Mal bekannt ist).
local function ColoredName(id)
   local items, util = T.Items, T.Util
   local info = type(items) == "table" and items.Info and items.Info(id) or nil
   if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
      local _, _, _, hex = util.QualityColor(info.quality)
      return hex .. info.name .. "|r"
   end
   if type(items) == "table" and items.Request then
      items.Request(id)
   end
   return util.Format(L.TIP_ITEM_UNKNOWN, id)
end

-- ---------------------------------------------------------------------------
-- (a) "Aussehen nicht gesammelt"
-- ---------------------------------------------------------------------------

-- true, wenn die ID in der Liste eines Slots steht: die Listen des Servers
-- enthalten nur gesammelte Aussehen, eine Abfrage waere also ueberfluessig
-- (z. B. beim Hover im Raster des Fensters).
local function InCollectionList(id)
   local state, slots = T.State, T.Slots
   if type(state) ~= "table" or type(state.List) ~= "function" then
      return false
   end
   if type(slots) ~= "table" or type(slots.LIST) ~= "table" then
      return false
   end
   for i = 1, #slots.LIST do
      local list = state.List(slots.LIST[i].server)
      if type(list) == "table" and type(list.set) == "table" and list.set[id] then
         return true
      end
   end
   return false
end

-- Prueft den Gegenstand id im Tooltip und fuegt die Zeile an oder fragt den
-- Server. Wirft nie, auch wenn Items/Net noch nicht bereit sind.
local function Evaluate(tip, id)
   local items, net = T.Items, T.Net
   if type(items) ~= "table" or type(net) ~= "table" then
      return
   end
   if type(items.Info) ~= "function" or type(net.CollectionState) ~= "function" then
      return
   end

   local info = items.Info(id)
   if not info then
      -- Unbekannt: nicht blind den Server fragen (Traenke, Material ...)
      if type(items.Request) == "function" then
         items.Request(id)
      end
      local st = hooked[tip]
      if st then
         st.waitId = id
      end
      return
   end

   local loc = info.equipLoc
   if type(loc) ~= "string" or loc == "" then
      return
   end
   if type(items.IsNever) == "function" and items.IsNever(loc) then
      return
   end

   local state = net.CollectionState(id)
   if state == 0 then
      AddColoredLine(tip, L.TIP_NOT_COLLECTED, Color("pink", PINK_FALLBACK))
   elseif state == nil and net.state ~= "ABSENT" and type(net.QueryCollection) == "function" then
      if not InCollectionList(id) then
         net.QueryCollection(id)
      end
   end
end

-- OnTooltipSetItem eines eingehaengten Tooltips.
local function OnTooltipSetItem(tip)
   local st = hooked[tip]
   if st then
      st.waitId = nil
   end
   if not Enabled("tooltipCollected") then
      return
   end
   local id = ItemIdOf(tip)
   if id then
      Evaluate(tip, id)
   end
end

-- OnHide: Zustand des Tooltips verwerfen.
local function OnTooltipHide(tip)
   local st = hooked[tip]
   if st then
      st.waitId = nil
   end
end

-- COLLECTION_STATUS(id, state): "nicht gesammelt" nachtragen, solange ein
-- Tooltip noch denselben Gegenstand zeigt.
local function OnCollectionStatus(id, state)
   if state ~= 0 or not Enabled("tooltipCollected") then
      return
   end
   for tip in pairs(hooked) do
      if tip:IsShown() and ItemIdOf(tip) == id then
         Evaluate(tip, id)
      end
   end
end

-- ITEMS_RESOLVED: Tooltips, die auf Iteminfo warteten, noch einmal pruefen.
local function OnItemsResolved()
   if not Enabled("tooltipCollected") then
      return
   end
   for tip, st in pairs(hooked) do
      local id = st.waitId
      if id then
         st.waitId = nil
         if tip:IsShown() and ItemIdOf(tip) == id then
            Evaluate(tip, id)
         end
      end
   end
end

-- SETTINGS_CHANGED(key): wurde die Zeile eingeschaltet, sichtbare Tooltips
-- sofort pruefen.
local function OnSettingsChanged(key)
   if key ~= "tooltipCollected" or not Enabled("tooltipCollected") then
      return
   end
   for tip in pairs(hooked) do
      if tip:IsShown() then
         local id = ItemIdOf(tip)
         if id then
            Evaluate(tip, id)
         end
      end
   end
end

-- Die geschuetzten Fassungen der Haken (je eine fuer alle Tooltips).
local GuardedSetItem = Guard(OnTooltipSetItem)
local GuardedHide = Guard(OnTooltipHide)

-- Haengt einen Tooltip ein (einmal je Tooltip); false, wenn er fehlt.
local function HookTooltip(tip)
   if type(tip) ~= "table" or type(tip.HookScript) ~= "function" then
      return false
   end
   if hooked[tip] then
      return true
   end
   local ok = pcall(tip.HookScript, tip, "OnTooltipSetItem", GuardedSetItem)
   if not ok then
      return false
   end
   pcall(tip.HookScript, tip, "OnHide", GuardedHide)
   hooked[tip] = {}
   return true
end

-- ---------------------------------------------------------------------------
-- (b) "Transmogrifiziert zu: ..."
-- ---------------------------------------------------------------------------

-- hooksecurefunc auf GameTooltip:SetInventoryItem(unit, slot).
local function OnSetInventoryItem(tip, unit, slot)
   if unit ~= "player" or type(slot) ~= "number" then
      return
   end
   if not Enabled("tooltipApplied") then
      return
   end

   local slots, state, util = T.Slots, T.State, T.Util
   if type(slots) ~= "table" or type(state) ~= "table" or type(util) ~= "table" then
      return
   end
   if type(state.Applied) ~= "function" or type(state.SlotState) ~= "function" then
      return
   end

   local def = type(slots.BY_CLIENT) == "table" and slots.BY_CLIENT[slot] or nil
   if not def then
      return
   end
   local applied = state.Applied(def.server)
   if type(applied) ~= "number" or applied == 0 then
      return
   end
   -- leerer Platz: kein angelegter Gegenstand, der Tooltip zeigt nur den Slotnamen
   if state.SlotState(def.server) ~= "READY" then
      return
   end

   local hiddenId = T.HIDDEN_ID or 999999
   if applied == hiddenId then
      AddColoredLine(tip, L.TIP_APPLIED_HIDDEN, Color("pink", PINK_FALLBACK))
      return
   end

   -- gespeichert, aber der Server zeigt den echten Gegenstand (siehe SPEC 2)
   if type(state.IsInactive) == "function" and state.IsInactive(def.server) then
      AddColoredLine(tip, util.Format(L.TIP_INACTIVE, ColoredName(applied)),
         Color("red", RED_FALLBACK))
      return
   end

   AddColoredLine(tip, util.Format(L.TIP_APPLIED, ColoredName(applied)),
      Color("pink", PINK_FALLBACK))
end

-- Haengt SetInventoryItem des GameTooltip ein (einmal).
local function HookInventory()
   if inventoryHooked then
      return
   end
   local tip = _G.GameTooltip
   if type(tip) ~= "table" or type(tip.SetInventoryItem) ~= "function" then
      return
   end
   if type(hooksecurefunc) ~= "function" then
      return
   end
   inventoryHooked = true
   hooksecurefunc(tip, "SetInventoryItem", Guard(OnSetInventoryItem))
end

-- ---------------------------------------------------------------------------
-- Oeffentliche Schnittstelle
-- ---------------------------------------------------------------------------

-- Haengt alle Item-Tooltips und SetInventoryItem ein und meldet die Ereignisse
-- an; darf beliebig oft gerufen werden.
function Tips.Init()
   for _, name in ipairs(TOOLTIP_NAMES) do
      local tip = _G[name]
      if tip ~= nil then
         HookTooltip(tip)
      end
   end
   HookInventory()

   local events = T.Events
   if type(events) == "table" and type(events.On) == "function" then
      events.On("COLLECTION_STATUS", OnCollectionStatus, Tips)
      events.On("ITEMS_RESOLVED", OnItemsResolved, Tips)
      events.On("SETTINGS_CHANGED", OnSettingsChanged, Tips)
      events.On("LOCALE_CHANGED", Tips.ApplyLocale, Tips)
   end
end

-- Texte neu setzen: die Zeilen werden bei jedem Anfuegen frisch aus L gebaut,
-- hier faellt nur der Wartezustand weg (LOCALE_CHANGED).
function Tips.ApplyLocale()
   for _, st in pairs(hooked) do
      st.waitId = nil
   end
end

-- true, wenn der Tooltip (Frame-Objekt) von Init eingehaengt wurde.
function Tips.IsHooked(tip)
   return hooked[tip] ~= nil
end
