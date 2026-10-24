-- tests/test_ui_tooltips.lua
-- ---------------------------------------------------------------------------
-- Tests fuer Features/Tooltips.lua (T.Tooltips) mit den ECHTEN Kernmodulen
-- (Items, Net, State, DB, Slots): der "Server" antwortet ueber Net.Handle bzw.
-- M.ServerMessage, die Tooltips sind die der Attrappe (GameTooltip & Co.).
--
--   Init               alle vorhandenen Item-Tooltips eingehaengt, idempotent
--   (a) nicht gesammelt   Zeile genau einmal; Abfrage nur fuer Ausruestung und
--                         nur einmal je Gegenstand; spaete Antwort; kein
--                         Fehler bei fehlenden Modulen
--   (b) SetInventoryItem  "Transmogrifiziert zu: Name" / "Verborgen" /
--                         "inaktiv"; nichts fuer leere oder nicht
--                         transmogbare Plaetze, andere Einheiten, Einstellung aus
--   Haken/Fluten          genau ein Haken je Tooltip, mehrfaches Feuern ohne
--                         Leeren, 45 Abfragen in einem Bild (Flutbremse), drei
--                         Tooltips, versteckter Tooltip, Fehler im Haken
--   Spielersicht          deutscher Client mit Katalog und Serverattrappe
--                         (tests/fixtures.lua): Antwort, Sammeln, Listen des
--                         Fensters, Charakterfenster, langer Name, Sprachwechsel
--   Zufallsfolgen         feste Startwerte, Invarianten je Tooltip
--
-- Aufruf:  cd <Addon>;  luajit tests/run.lua ui_tooltips
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   local ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
   local HIDDEN = 999999

   -- -----------------------------------------------------------------------
   -- Gegenstaende
   -- -----------------------------------------------------------------------

   local function item(name, quality, class, subclass, loc)
      return {
         name = name, quality = quality, ilvl = 100, minLevel = 0,
         class = class, subclass = subclass, equipLoc = loc, icon = ICON,
      }
   end

   local function itemTable()
      return {
         -- angelegt (Client-Slot 1 Kopf, 5 Brust, 2 Hals, 11 Ring)
         [1001] = item("Equipped Helm", 3, "Armor", "Plate", "INVTYPE_HEAD"),
         [1004] = item("Equipped Chest", 3, "Armor", "Plate", "INVTYPE_CHEST"),
         [1002] = item("Equipped Amulet", 3, "Armor", "Miscellaneous", "INVTYPE_NECK"),
         -- Kandidaten
         [2001] = item("Missing Helm", 4, "Armor", "Plate", "INVTYPE_HEAD"),
         [2002] = item("Owned Helm", 3, "Armor", "Plate", "INVTYPE_HEAD"),
         [2003] = item("Third Helm", 2, "Armor", "Plate", "INVTYPE_HEAD"),
         [2004] = item("Fourth Helm", 2, "Armor", "Plate", "INVTYPE_HEAD"),
         [2005] = item("Fifth Helm", 2, "Armor", "Plate", "INVTYPE_HEAD"),
         [2101] = item("Missing Sword", 3, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON"),
         -- nicht transmogbar bzw. keine Ausruestung
         [3001] = item("Healing Potion", 1, "Consumable", "Potion", ""),
         [3002] = item("Test Ring", 3, "Armor", "Miscellaneous", "INVTYPE_FINGER"),
         [3003] = item("Test Trinket", 3, "Armor", "Miscellaneous", "INVTYPE_TRINKET"),
         [3004] = item("Test Bag", 1, "Container", "Bag", "INVTYPE_BAG"),
         [3005] = item("Test Amulet", 3, "Armor", "Miscellaneous", "INVTYPE_NECK"),
         -- angewendete Aussehen
         [4001] = item("Frostmourne Look", 5, "Weapon", "Two-Handed Swords", "INVTYPE_2HWEAPON"),
         [4002] = item("Plain Look", 2, "Armor", "Plate", "INVTYPE_CHEST"),
      }
   end

   -- -----------------------------------------------------------------------
   -- Sitzung
   -- -----------------------------------------------------------------------

   -- Startet eine Sitzung (echte TOC; ohne Core\Boot.lua wird der Ablauf aus
   -- SPEC 3 nachgebildet). opts: equipment, globals, items (zusaetzliche
   -- Gegenstaende), locale.
   local function start(opts)
      opts = opts or {}
      local itemsT = itemTable()
      for id, it in pairs(opts.items or {}) do
         itemsT[id] = it
      end
      local T = H.boot({
         world = {
            equipment = opts.equipment or { [1] = 1001, [5] = 1004, [2] = 1002 },
            locale = opts.locale or "enUS",
         },
         items = itemsT,
         globals = opts.globals,
         login = true,
         enterWorld = false,
      })
      H.assert(type(T) == "table" and type(T.Tooltips) == "table", "Features\\Tooltips.lua wurde nicht geladen")

      if not (T.DB.global and T.DB.char) then
         T.DB.Init()
         T.Locale.Set(T.DB.global.locale)
         T.RefreshPlayerInfo()
         T.Slots.Init()
         T.Items.Init()
         T.Net.Init()
         T.State.Init()
         T.Outfits.Init()
      end
      T.Tooltips.Init()
      M.CacheAll()
      return T
   end

   -- Linker Text aller Zeilen eines Tooltips
   local function lines(tip)
      tip = tip or GameTooltip
      local out = {}
      local name = tip:GetName()
      for i = 1, tip:NumLines() do
         local fs = _G[name .. "TextLeft" .. i]
         out[i] = fs and fs:GetText() or ""
      end
      return out
   end

   -- Wie oft kommt ein Text als eigene Zeile vor?
   local function countLine(tip, text)
      local n = 0
      for _, l in ipairs(lines(tip)) do
         if l == text then n = n + 1 end
      end
      return n
   end

   -- Zeilen, die einen Teilstring enthalten
   local function countMatching(tip, needle)
      local n = 0
      for _, l in ipairs(lines(tip)) do
         if l:find(needle, 1, true) then n = n + 1 end
      end
      return n
   end

   -- Index der Zeile mit genau diesem Text (oder nil)
   local function lineIndex(tip, text)
      for i, l in ipairs(lines(tip)) do
         if l == text then return i end
      end
      return nil
   end

   -- Hover ueber einen Gegenstand (Link, wie Haendler/Chat/Auktionshaus)
   local function hover(tip, id)
      tip = tip or GameTooltip
      tip:SetOwner(UIParent, "ANCHOR_RIGHT")
      tip:SetHyperlink("item:" .. id)
      return tip
   end

   local function queries(id)
      return M.CountSent("GetCollectionStatus:" .. id)
   end

   local function settle(seconds)
      M.Advance(seconds, 0.05)
   end

   -- ======================================================================
   -- Einhaengen
   -- ======================================================================

   H.test("Init: haengt alle vorhandenen Item-Tooltips ein, Init ist idempotent", function()
      local T = start()
      local Tips = T.Tooltips
      for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                              "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
         local tip = _G[name]
         H.truthy(tip, name .. " existiert in der Attrappe")
         if tip then H.eq(Tips.IsHooked(tip), true, name .. " eingehaengt") end
      end
      -- nicht vorhandene (3.3.5a hat kein ShoppingTooltip3) sind kein Fehler
      H.falsy(_G.ShoppingTooltip3, "ShoppingTooltip3 gibt es nicht")

      Tips.Init()
      Tips.Init()
      T.Net.Handle("CollectionStatus:2001:0")
      hover(GameTooltip, 2001)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1, "trotz dreifachem Init nur eine Zeile")
      H.eq(#M.TakeErrors(), 0, "keine Handlerfehler")
   end)

   -- ======================================================================
   -- (a) Aussehen nicht gesammelt
   -- ======================================================================

   H.test("(a) Zustand 0: genau eine rosa Zeile am Ende, der Tooltip wird neu ausgemessen", function()
      local T = start()
      T.Net.Handle("CollectionStatus:2001:0")
      M.ClearSent()

      hover(GameTooltip, 2001)
      local text = T.L.TIP_NOT_COLLECTED
      H.eq(text, "Appearance not collected")
      H.eq(countLine(GameTooltip, text), 1)
      local ls = lines(GameTooltip)
      H.eq(ls[#ls], text, "die Zeile steht ganz unten")
      H.eq(queries(2001), 0, "der Stand ist bekannt: keine Abfrage")
      H.truthy(GameTooltip:IsShown(), "Tooltip sichtbar")

      local fs = _G["GameTooltipTextLeft" .. #ls]
      local r, g, b = fs:GetTextColor()
      local pink = T.COLORS.pink
      H.near(r, pink[1], 0.01, "rosa r")
      H.near(g, pink[2], 0.01, "rosa g")
      H.near(b, pink[3], 0.01, "rosa b")

      -- Ein zweiter Hover (ohne Hide, der Tooltip wird neu gefuellt) ergibt wieder genau eine Zeile
      hover(GameTooltip, 2001)
      H.eq(countLine(GameTooltip, text), 1, "nach erneutem Fuellen ebenfalls genau eine")
      GameTooltip:Hide()
      hover(GameTooltip, 2001)
      H.eq(countLine(GameTooltip, text), 1, "nach Hide/Show ebenfalls genau eine")
   end)

   H.test("(a) gesammelt (1) und nicht anwendbar (2): keine Zeile", function()
      local T = start()
      T.Net.Handle("CollectionStatus:2002:1")
      T.Net.Handle("CollectionStatus:2003:2")
      hover(GameTooltip, 2002)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0, "gesammelt")
      hover(GameTooltip, 2003)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0, "nicht anwendbar")
      H.eq(queries(2002) + queries(2003), 0, "kein Abfragen mehr")
   end)

   H.test("(a) Zustand unbekannt: genau eine Abfrage, die Zeile kommt mit der Antwort", function()
      local T = start()
      M.ClearSent()

      hover(GameTooltip, 2001)
      H.eq(queries(2001), 1, "eine Abfrage")
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0, "noch keine Zeile")
      local before = GameTooltip:NumLines()

      -- erneutes Zeigen, solange die Antwort aussteht: keine zweite Abfrage
      GameTooltip:Hide()
      hover(GameTooltip, 2001)
      hover(GameTooltip, 2001)
      H.eq(queries(2001), 1, "weiterhin eine Abfrage")

      -- Antwort ueber den ganzen Weg (CHAT_MSG_ADDON -> Net -> State -> COLLECTION_STATUS)
      M.ServerMessage("CollectionStatus:2001:0")
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1, "Zeile nachgetragen")
      H.eq(GameTooltip:NumLines(), before + 1, "genau eine Zeile mehr")

      -- eine zweite Antwort (z. B. nach Wiederholung) ergibt keine zweite Zeile
      T.Net.Handle("CollectionStatus:2001:0")
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1, "keine doppelte Zeile")
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("(a) Antwort 1 (gesammelt) bleibt ohne Zeile; spaeter wieder Hover fragt nicht erneut", function()
      local T = start()
      M.ClearSent()
      hover(GameTooltip, 2002)
      H.eq(queries(2002), 1)
      M.ServerMessage("CollectionStatus:2002:1")
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0)
      for _ = 1, 5 do
         GameTooltip:Hide()
         hover(GameTooltip, 2002)
      end
      H.eq(queries(2002), 1, "je Gegenstand und Sitzung eine Abfrage")
   end)

   H.test("(a) Antwort kommt, nachdem der Tooltip einen anderen Gegenstand zeigt: keine Zeile", function()
      local T = start()
      hover(GameTooltip, 2001)
      hover(GameTooltip, 2002)          -- Wechsel: anderer Gegenstand
      T.Net.Handle("CollectionStatus:2001:0")
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0, "Tooltip zeigt 2002, nicht 2001")
      -- und nach dem Verbergen erst recht nicht
      GameTooltip:Hide()
      T.Net.Handle("CollectionStatus:2002:0")
      H.eq(GameTooltip:NumLines() > 0 and countLine(GameTooltip, T.L.TIP_NOT_COLLECTED) or 0, 0,
         "versteckter Tooltip bekommt nichts")
   end)

   H.test("(a) keine Zeile und keine Abfrage fuer Traenke, Ringe, Schmuck, Taschen, Amulette", function()
      local T = start()
      M.ClearSent()
      for _, id in ipairs({ 3001, 3002, 3003, 3004, 3005 }) do
         hover(GameTooltip, id)
         H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0, "keine Zeile fuer " .. id)
      end
      H.eq(M.CountSent("GetCollectionStatus"), 0, "kein Server-Verkehr fuer Nicht-Ausruestung")
      -- auch eine spaete (erfundene) Antwort fuer so einen Gegenstand erzeugt nichts
      hover(GameTooltip, 3001)
      T.Net.Handle("CollectionStatus:3001:0")
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0, "Trank bleibt ohne Zeile")
   end)

   H.test("(a) Waffen und andere Plaetze werden abgefragt (nicht nur Ruestung)", function()
      local T = start()
      M.ClearSent()
      hover(GameTooltip, 2101)
      H.eq(queries(2101), 1)
      M.ServerMessage("CollectionStatus:2101:0")
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1)
   end)

   H.test("(a) Gegenstand steht in einer Liste des Fensters: gesammelt, keine Abfrage", function()
      local T = start()
      T.Net.Handle("AvailableTransmogs:0:8:2:start")
      T.Net.Handle("AvailableTransmogs:0:8:2:2002:2003")
      T.Net.Handle("AvailableTransmogs:0:8:2:end")
      H.eq(T.State.List(0).set[2002], true, "Voraussetzung: in der Liste")
      M.ClearSent()
      hover(GameTooltip, 2002)
      H.eq(queries(2002), 0, "gesammelt laut Liste: keine Abfrage")
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0)
      hover(GameTooltip, 2004)
      H.eq(queries(2004), 1, "nicht in der Liste: Abfrage")
   end)

   H.test("(a) Iteninfo unbekannt: Request, keine Abfrage; mit ITEMS_RESOLVED wird nachgeholt", function()
      local T = start()
      T.Net.Handle("CollectionStatus:2001:0")
      M.ClearSent()

      -- Die Attrappe feuert OnTooltipSetItem nur fuer gecachte Gegenstaende; die
      -- Info-Luecke wird daher ueber einen Stub von Items.Info nachgestellt.
      local realInfo = T.Items.Info
      local requested = {}
      local realRequest = T.Items.Request
      T.Items.Info = function() return nil end
      T.Items.Request = function(id)
         requested[#requested + 1] = id
         return false
      end

      hover(GameTooltip, 2001)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0, "ohne Info keine Zeile")
      H.deepEq(requested, { 2001 }, "Items.Request(2001)")
      H.eq(M.CountSent("GetCollectionStatus"), 0, "keine Serverabfrage ohne Info")

      -- Info trifft ein
      T.Items.Info = realInfo
      T.Items.Request = realRequest
      T.Events.Fire("ITEMS_RESOLVED", 1)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1, "nachgetragen")

      -- ein weiteres ITEMS_RESOLVED aendert nichts
      T.Events.Fire("ITEMS_RESOLVED", 1)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1, "weiterhin eine Zeile")
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("(a) Hide verwirft den Wartezustand: spaetes ITEMS_RESOLVED fuegt nichts an", function()
      local T = start()
      T.Net.Handle("CollectionStatus:2001:0")
      local realInfo = T.Items.Info
      T.Items.Info = function() return nil end
      hover(GameTooltip, 2001)
      T.Items.Info = realInfo
      GameTooltip:Hide()
      T.Events.Fire("ITEMS_RESOLVED", 1)
      H.eq(GameTooltip:NumLines() > 0 and countLine(GameTooltip, T.L.TIP_NOT_COLLECTED) or 0, 0)
   end)

   H.test("(a) Einstellung tooltipCollected = false: nichts, auch keine Abfrage", function()
      local T = start()
      T.DB.Set("tooltipCollected", false)
      T.Net.Handle("CollectionStatus:2001:0")
      M.ClearSent()
      hover(GameTooltip, 2001)
      hover(GameTooltip, 2002)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0)
      H.eq(M.CountSent("GetCollectionStatus"), 0, "keine Abfrage bei abgeschalteter Zeile")
      -- und wieder einschalten: sichtbarer Tooltip bekommt die Zeile sofort
      hover(GameTooltip, 2001)
      T.DB.Set("tooltipCollected", true)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1, "sofort nach dem Einschalten")
   end)

   H.test("(a) Server stumm (Net.state ABSENT): keine weiteren Abfragen", function()
      local T = start()
      -- erste Anfrage setzt den Zaehler; 9 s ohne Antwort -> ABSENT
      T.Net.RequestStatus()
      settle(9)
      H.eq(T.Net.state, "ABSENT")
      M.ClearSent()
      hover(GameTooltip, 2001)
      H.eq(M.CountSent("GetCollectionStatus"), 0, "kein Verkehr zu einem Server ohne Modul")
      -- gibt es doch eine Antwort, laeuft es wieder
      T.Net.Handle("CollectionStatus:2001:0")
      H.eq(T.Net.state, "OK")
      hover(GameTooltip, 2001)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1)
   end)

   H.test("(a) Item-Tooltips der Vergleichs- und Link-Tooltips bekommen die Zeile ebenfalls", function()
      local T = start()
      T.Net.Handle("CollectionStatus:2001:0")
      for _, name in ipairs({ "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                              "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
         local tip = _G[name]
         hover(tip, 2001)
         H.eq(countLine(tip, T.L.TIP_NOT_COLLECTED), 1, name)
      end
      -- ein Tooltip beeinflusst den anderen nicht
      H.eq(GameTooltip:NumLines(), 0, "GameTooltip blieb leer")
   end)

   H.test("(a) Sprachwechsel: neue Zeilen kommen in der neuen Sprache", function()
      local T = start()
      T.Locale.Add("deDE", { TIP_NOT_COLLECTED = "Aussehen nicht gesammelt" })
      T.Net.Handle("CollectionStatus:2001:0")
      T.Locale.Set("deDE")
      hover(GameTooltip, 2001)
      H.eq(countLine(GameTooltip, "Aussehen nicht gesammelt"), 1)
      H.eq(countLine(GameTooltip, "Appearance not collected"), 0)
   end)

   H.test("(a) nur eine Abfrage je Gegenstand, auch bei vielen Gegenstaenden und Wiederholung", function()
      local T = start()
      M.ClearSent()
      local ids = { 2001, 2002, 2003, 2004, 2005, 2101 }
      for round = 1, 4 do
         for _, id in ipairs(ids) do
            hover(GameTooltip, id)
            GameTooltip:Hide()
         end
      end
      for _, id in ipairs(ids) do
         H.eq(queries(id), 1, "Abfrage fuer " .. id)
      end
      H.eq(M.CountSent("GetCollectionStatus"), #ids, "insgesamt je Gegenstand eine")
   end)

   H.test("(a) ohne State/Items/Net/DB: kein Fehler, keine Zeile", function()
      local T = start()
      T.Net.Handle("CollectionStatus:2001:0")
      local items, net, db = T.Items, T.Net, T.DB.global
      T.Items = nil
      hover(GameTooltip, 2001)
      T.Items = items
      T.Net = nil
      hover(GameTooltip, 2001)
      T.Net = net
      T.DB.global = nil
      hover(GameTooltip, 2001)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0, "ohne DB nichts")
      T.DB.global = db
      hover(GameTooltip, 2001)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1, "mit DB wieder")
      H.eq(#M.TakeErrors(), 0, "nirgends ein Fehler")
   end)

   -- ======================================================================
   -- (b) Transmogrifiziert zu
   -- ======================================================================

   -- Setzt den Serverstand: map = { [server] = fake }
   local function setStatus(T, map)
      local parts, n = {}, 0
      for slot, fake in pairs(map) do
         parts[#parts + 1] = slot .. "," .. fake
         n = n + 1
      end
      T.Net.Handle("TransmogStatus:" .. n .. (n > 0 and (":" .. table.concat(parts, ":")) or ""))
   end

   -- Hover ueber den angelegten Gegenstand (Charakterfenster)
   local function hoverEquipped(clientSlot, unit)
      GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
      GameTooltip:SetInventoryItem(unit or "player", clientSlot)
      return GameTooltip
   end

   H.test("(b) angewendetes Aussehen: eine rosa Zeile 'Transmogrifiziert zu: <Name in Qualitaetsfarbe>'", function()
      local T = start()
      setStatus(T, { [0] = 4001 })
      H.eq(T.State.Applied(0), 4001)

      hoverEquipped(1)
      local _, _, _, hex = T.Util.QualityColor(5)
      local want = "Transmogrified to: " .. hex .. "Frostmourne Look|r"
      H.eq(countLine(GameTooltip, want), 1, "Zeile mit eingefaerbtem Namen")
      local ls = lines(GameTooltip)
      H.eq(ls[#ls], want, "ganz unten")
      H.eq(ls[1], "Equipped Helm", "Kopfzeile des Gegenstands bleibt")

      local fs = _G["GameTooltipTextLeft" .. #ls]
      local r, g, b = fs:GetTextColor()
      H.near(r, T.COLORS.pink[1], 0.01)
      H.near(g, T.COLORS.pink[2], 0.01)
      H.near(b, T.COLORS.pink[3], 0.01)

      -- erneut: wieder genau eine Zeile
      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Transmogrified to:"), 1)
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("(b) verborgen: 'Transmogrifiziert zu: Verborgen'", function()
      local T = start()
      setStatus(T, { [4] = HIDDEN })
      hoverEquipped(5)
      H.eq(countLine(GameTooltip, T.L.TIP_APPLIED_HIDDEN), 1)
      H.eq(T.L.TIP_APPLIED_HIDDEN, "Transmogrified to: Hidden")
   end)

   H.test("(b) kein Aussehen oder anderer Slot: keine Zeile", function()
      local T = start()
      setStatus(T, { [0] = 4001 })
      hoverEquipped(5)    -- Brust: nichts angewendet
      H.eq(countMatching(GameTooltip, "Transmogrified"), 0, "Brust ohne Aussehen")
      setStatus(T, {})
      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Transmogrified"), 0, "Status leer")
   end)

   H.test("(b) nur fuer 'player', nur fuer die 14 Plaetze, nicht fuer leere Plaetze", function()
      local T = start()
      setStatus(T, { [0] = 4001, [4] = 4002 })

      hoverEquipped(1, "target")
      H.eq(countMatching(GameTooltip, "Transmogrified"), 0, "Einheit 'target'")

      hoverEquipped(2)       -- Hals: nicht transmogbar (kein Eintrag in BY_CLIENT)
      H.eq(countMatching(GameTooltip, "Transmogrified"), 0, "Hals")
      hoverEquipped(11)      -- Ringplatz (leer in diesem Test)
      H.eq(countMatching(GameTooltip, "Transmogrified"), 0, "Ring")

      -- leerer Kopfplatz, obwohl der Server noch ein Aussehen kennt
      M.world.equipment[1] = nil
      T.State.RefreshEquipment()
      H.eq(T.State.SlotState(0), "EMPTY")
      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Transmogrified"), 0, "leerer Platz")
   end)

   H.test("(b) alle 14 Plaetze: Zuordnung Client-Slot -> Server-Slot", function()
      local equipment = {}
      local map = {}
      local itemsT = itemTable()
      -- je Plaetze ein eigenes angelegtes Stueck und ein eigenes Aussehen
      local clients = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19 }
      for i, client in ipairs(clients) do
         equipment[client] = 5000 + i
         map[client - 1] = 6000 + i
      end
      local T = H.boot({
         world = { equipment = equipment },
         items = (function()
            for i, client in ipairs(clients) do
               itemsT[5000 + i] = item("Worn " .. client, 3, "Armor", "Plate", "INVTYPE_CHEST")
               itemsT[6000 + i] = item("Look " .. client, 2, "Armor", "Plate", "INVTYPE_CHEST")
            end
            return itemsT
         end)(),
         login = true,
      })
      if not (T.DB.global and T.DB.char) then
         T.DB.Init(); T.Locale.Set(T.DB.global.locale); T.RefreshPlayerInfo()
         T.Slots.Init(); T.Items.Init(); T.Net.Init(); T.State.Init(); T.Outfits.Init()
      end
      T.Tooltips.Init()
      M.CacheAll()
      setStatus(T, map)
      for i, client in ipairs(clients) do
         hoverEquipped(client)
         local _, _, _, hex = T.Util.QualityColor(2)
         H.eq(countLine(GameTooltip, "Transmogrified to: " .. hex .. "Look " .. client .. "|r"), 1,
            "Client-Slot " .. client)
      end
   end)

   H.test("(b) Einstellung tooltipApplied = false: keine Zeile", function()
      local T = start()
      setStatus(T, { [0] = 4001 })
      T.DB.Set("tooltipApplied", false)
      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Transmogrified"), 0)
      T.DB.Set("tooltipApplied", true)
      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Transmogrified"), 1)
   end)

   H.test("(b) inaktives Aussehen (nicht in der fertigen Liste): 'inaktiv' statt 'Transmogrifiziert zu'", function()
      local T = start()
      setStatus(T, { [0] = 4001 })
      -- fertige Liste fuer den Kopf ohne 4001
      T.Net.Handle("AvailableTransmogs:0:8:1:start")
      T.Net.Handle("AvailableTransmogs:0:8:1:2002")
      T.Net.Handle("AvailableTransmogs:0:8:1:end")
      H.eq(T.State.IsInactive(0), true, "Voraussetzung: inaktiv")

      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Transmogrified to:"), 0, "kein falsches 'Transmogrifiziert zu'")
      H.eq(countMatching(GameTooltip, "Transmog inactive:"), 1, "inaktiv-Zeile")
      local ls = lines(GameTooltip)
      local fs = _G["GameTooltipTextLeft" .. #ls]
      local r = fs:GetTextColor()
      H.near(r, T.COLORS.red[1], 0.01, "rot")

      -- steht es doch in der Liste, ist es aktiv
      T.Net.Handle("AvailableTransmogs:0:8:1:start")
      T.Net.Handle("AvailableTransmogs:0:8:2:4001:2002")
      T.Net.Handle("AvailableTransmogs:0:8:2:end")
      H.eq(T.State.IsInactive(0), false)
      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Transmogrified to:"), 1)
   end)

   H.test("(b) Name noch unbekannt: 'Item <id>', danach (nach der Abfrage) der Name", function()
      local T = start()
      M.UncacheItem(4001)
      setStatus(T, { [0] = 4001 })
      hoverEquipped(1)
      H.eq(countLine(GameTooltip, "Transmogrified to: Item 4001"), 1, "Ersatztext")
      settle(2)       -- Abfrage laeuft ein (Items-Poll)
      H.truthy(T.Items.Info(4001), "Info ist da")
      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Frostmourne Look"), 1, "jetzt mit Name")
      H.eq(countMatching(GameTooltip, "Item 4001"), 0)
   end)

   H.test("(b) (a) und (b) zusammen: nicht gesammelt UND transmogrifiziert, je eine Zeile", function()
      local T = start()
      setStatus(T, { [0] = 4001 })
      T.Net.Handle("CollectionStatus:1001:0")   -- (kuenstlich) der angelegte Gegenstand selbst
      hoverEquipped(1)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1)
      H.eq(countMatching(GameTooltip, "Transmogrified to:"), 1)
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("(b) ohne State/Slots/Util: kein Fehler", function()
      local T = start()
      setStatus(T, { [0] = 4001 })
      local state, slots = T.State, T.Slots
      T.State = nil
      hoverEquipped(1)
      T.State = state
      T.Slots = nil
      hoverEquipped(1)
      T.Slots = slots
      H.eq(countMatching(GameTooltip, "Transmogrified"), 0)
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Hygiene: keine fremden Globals, keine impliziten Handler-Globals", function()
      local T = start()
      setStatus(T, { [0] = 4001 })
      hoverEquipped(1)
      hover(ItemRefTooltip, 2001)
      -- die automatische Pruefung am Testende (Strays, this/arg1/event) deckt den Rest ab
      H.eq(#M.TakeErrors(), 0)
   end)

   -- ======================================================================
   -- Haken, Fluten, mehrfaches Feuern, Fehler
   -- ======================================================================

   -- Alle Haken eines Tooltips fuer ein Skript (Attrappe: __hooks)
   local function hooksOf(tip, script)
      return (tip.__hooks and tip.__hooks[script]) or {}
   end

   H.test("Haken: genau ein OnTooltipSetItem-Haken je Tooltip, auch nach mehrfachem Init", function()
      local T = start()
      local names = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                      "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }
      local hide = {}
      for _, name in ipairs(names) do
         H.eq(#hooksOf(_G[name], "OnTooltipSetItem"), 1, name .. ": OnTooltipSetItem")
         hide[name] = #hooksOf(_G[name], "OnHide")
      end
      T.Tooltips.Init()
      T.Tooltips.Init()
      for _, name in ipairs(names) do
         H.eq(#hooksOf(_G[name], "OnTooltipSetItem"), 1, name .. ": weiterhin einer")
         H.eq(#hooksOf(_G[name], "OnHide"), hide[name], name .. ": OnHide unveraendert")
      end
   end)

   H.test("OnTooltipSetItem feuert mehrfach, ohne dass der Tooltip zwischendurch geleert wird: eine Zeile", function()
      local T = start()
      T.Net.Handle("CollectionStatus:2001:0")
      hover(GameTooltip, 2001)
      local before = GameTooltip:NumLines()
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1)
      for _ = 1, 6 do
         for _, fn in ipairs(hooksOf(GameTooltip, "OnTooltipSetItem")) do
            fn(GameTooltip)
         end
      end
      H.eq(GameTooltip:NumLines(), before, "keine weitere Zeile")
      H.eq(M.CountSent("GetCollectionStatus:2001"), 0)
   end)

   H.test("Anfragenflut: 45 Gegenstaende in einem Bild - die Bremse des Netzes haelt, der Hover holt den Rest spaeter nach", function()
      local extra = {}
      for i = 1, 45 do
         extra[8000 + i] = item("Flood Helm " .. i, 3, "Armor", "Plate", "INVTYPE_HEAD")
      end
      local T = start({ items = extra })
      M.ClearSent()
      for i = 1, 45 do
         hover(GameTooltip, 8000 + i)
      end
      H.eq(M.CountSent("GetCollectionStatus"), 30, "Net begrenzt auf 30 je Sekunde")
      for i = 1, 45 do
         H.truthy(queries(8000 + i) <= 1, "Gegenstand " .. i .. " hoechstens einmal")
      end
      settle(1.1)
      for i = 1, 45 do
         hover(GameTooltip, 8000 + i)
      end
      H.eq(M.CountSent("GetCollectionStatus"), 45, "der Rest wurde nachgeholt, nichts doppelt")
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Ein Gegenstand in drei Tooltips: eine Abfrage, die Antwort bedient alle", function()
      local T = start()
      M.ClearSent()
      hover(GameTooltip, 2001)
      hover(ItemRefTooltip, 2001)
      hover(ShoppingTooltip1, 2001)
      H.eq(queries(2001), 1, "nur eine Abfrage")
      M.ServerMessage("CollectionStatus:2001:0")
      for _, tip in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1 }) do
         H.eq(countLine(tip, T.L.TIP_NOT_COLLECTED), 1, tip:GetName())
      end
   end)

   H.test("Antwort kommt bei verstecktem Tooltip: beim naechsten Zeigen steht die Zeile sofort, ohne neue Abfrage", function()
      local T = start()
      M.ClearSent()
      hover(GameTooltip, 2001)
      GameTooltip:Hide()
      M.ServerMessage("CollectionStatus:2001:0")
      M.ClearSent()
      hover(GameTooltip, 2001)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1, "sofort da")
      H.eq(M.CountSent("GetCollectionStatus"), 0, "keine neue Abfrage")
   end)

   H.test("Tooltip ohne Gegenstand (Text/Zauber): eine Antwort aendert nichts", function()
      local T = start()
      GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
      GameTooltip:SetText("Frostbolt", 1, 1, 1)
      GameTooltip:Show()
      T.Net.Handle("CollectionStatus:2001:0")
      T.Net.Handle("CollectionStatus:3001:0")
      T.Events.Fire("ITEMS_RESOLVED", 3)
      H.eq(GameTooltip:NumLines(), 1, "weiterhin nur der Zaubertext")
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Fehler im Haken: einmal gemeldet statt bei jedem Tooltip, der Tooltip bleibt benutzbar", function()
      local T = start()
      setStatus(T, { [0] = 4001 })

      -- (b) SetInventoryItem
      local realApplied = T.State.Applied
      T.State.Applied = function() error("boom-applied") end
      for _ = 1, 5 do hoverEquipped(1) end
      local errs = M.TakeErrors()
      H.eq(#errs, 1, "genau eine Meldung statt fuenf")
      H.contains(tostring(errs[1]), "boom-applied")
      H.eq(lines(GameTooltip)[1], "Equipped Helm", "der Gegenstandstext steht trotzdem")
      T.State.Applied = realApplied
      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Transmogrified to:"), 1, "danach wieder in Ordnung")
      H.eq(#M.TakeErrors(), 0)

      -- (a) OnTooltipSetItem
      local realState = T.Net.CollectionState
      T.Net.CollectionState = function() error("boom-state") end
      for _ = 1, 4 do hover(GameTooltip, 2001) end
      errs = M.TakeErrors()
      H.eq(#errs, 1, "auch hier nur eine Meldung")
      H.contains(tostring(errs[1]), "boom-state")
      H.eq(lines(GameTooltip)[1], "Missing Helm")
      T.Net.CollectionState = realState
   end)

   -- ======================================================================
   -- Spielersicht: deutscher Client, Katalog und Serverattrappe
   -- ======================================================================

   local Fixtures = require("fixtures")

   -- Sitzung mit Katalog, fertigen Listen und antwortendem Server (Latenz 0,1 s)
   local function fxSession(hello, locale)
      local T = Fixtures.Boot(H, { locale = locale or "deDE" })
      Fixtures.ServerHello(T, hello)
      Fixtures.ServerAutoReply(T)
      M.ClearSent()
      return T
   end

   H.test("Spielersicht: ein nicht gesammeltes Aussehen bekommt die Zeile mit der Antwort, nach dem Sammeln nie wieder", function()
      local T = fxSession()
      local unc
      for _, rec in ipairs(Fixtures.Catalog(T).list) do
         if rec.uncollected and not unc then unc = rec end
      end
      H.truthy(unc, "der Katalog hat ein nicht gesammeltes Aussehen")

      hover(GameTooltip, unc.id)
      H.eq(lines(GameTooltip)[1], unc.name, "deutscher Name")
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0, "vor der Antwort keine Zeile")
      H.eq(queries(unc.id), 1)
      Fixtures.Settle(T, 0.3)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1, "mit der Antwort genau eine")
      local ls = lines(GameTooltip)
      H.eq(ls[#ls], T.L.TIP_NOT_COLLECTED, "unten")

      -- erneut zeigen: aus dem Cache, keine neue Abfrage
      GameTooltip:Hide()
      hover(GameTooltip, unc.id)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 1)
      H.eq(queries(unc.id), 1, "weiterhin eine")

      -- der Server meldet das Aussehen als gesammelt
      Fixtures.Collect(T, unc.id)
      Fixtures.Settle(T, 0.3)
      GameTooltip:Hide()
      hover(GameTooltip, unc.id)
      H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0, "gesammelt: keine Zeile mehr")
      H.eq(queries(unc.id), 1, "und keine neue Abfrage")
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Spielersicht: Aussehen aus den Listen des Fensters werden nie abgefragt", function()
      local T = fxSession()
      local ids = Fixtures.List(T, 0)
      H.truthy(#ids >= 3, "Kopfliste gefuellt")
      for i = 1, 3 do
         H.eq(T.State.List(0).set[ids[i]], true, "Voraussetzung: in der Liste")
         hover(GameTooltip, ids[i])
         H.eq(countLine(GameTooltip, T.L.TIP_NOT_COLLECTED), 0)
      end
      Fixtures.Settle(T, 0.3)
      H.eq(M.CountSent("GetCollectionStatus"), 0)
   end)

   H.test("Spielersicht: Charakterfenster - angewendet, verborgen, inaktiv und unveraendert je Platz", function()
      local T = fxSession()
      local function name(id) return M.items[id].name end
      -- Zeile "<Text der Sprache>: <farbiger Name>" fuer TIP_APPLIED / TIP_INACTIVE
      local function coloredLine(key, id)
         local _, _, _, hex = T.Util.QualityColor(M.items[id].quality)
         return string.format(T.L[key], hex .. name(id) .. "|r")
      end
      -- Text vor dem Platzhalter (zum Zaehlen ohne den Namen)
      local function prefixOf(key)
         return (T.L[key]:match("^(.-)%%s"))
      end

      -- Kopf (client 1): angewendet
      local head = T.State.Applied(0)
      H.truthy(head ~= 0 and head ~= HIDDEN)
      hoverEquipped(1)
      H.eq(countLine(GameTooltip, coloredLine("TIP_APPLIED", head)), 1, "Kopf")
      H.eq(countMatching(GameTooltip, prefixOf("TIP_INACTIVE")), 0)

      -- Ruecken (client 15): verborgen
      H.eq(T.State.Applied(14), HIDDEN)
      hoverEquipped(15)
      H.eq(countLine(GameTooltip, T.L.TIP_APPLIED_HIDDEN), 1, "Ruecken verborgen")

      -- Beine (client 7): gespeichert, aber nicht in der Liste -> inaktiv, nicht "Transmogrifiziert zu"
      local legs = T.State.Applied(6)
      H.truthy(legs ~= 0)
      H.eq(T.State.IsInactive(6), true, "Voraussetzung: inaktiv")
      hoverEquipped(7)
      H.eq(countLine(GameTooltip, coloredLine("TIP_INACTIVE", legs)), 1, "Beine inaktiv")
      H.eq(countMatching(GameTooltip, prefixOf("TIP_APPLIED")), 0)

      -- Plaetze ohne Aussehen und nicht transmogbare Plaetze
      for _, client in ipairs({ 8, 10, 4, 19, 2, 11, 12, 13, 14 }) do
         hoverEquipped(client)
         H.eq(countMatching(GameTooltip, "Transmog"), 0, "Platz " .. client .. " ohne Zeile")
      end
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Spielersicht: langer deutscher Name steht vollstaendig und umbrechbar im Tooltip", function()
      local T = fxSession({ applied = { [6] = "e_legs_cloth" }, hidden = {}, inactive = {} })
      local id = Fixtures.Item(T, "e_legs_cloth")
      local long = M.items[id].name
      H.truthy(#long > 55, "Voraussetzung: langer Name")
      hoverEquipped(7)
      local n = GameTooltip:NumLines()
      local fs = _G["GameTooltipTextLeft" .. n]
      H.contains(fs:GetText(), long, "der Name steht ungekuerzt")
      H.eq(GameTooltip.__lines[n].wrap, true, "umbrechbar, damit der Tooltip nicht verbreitert wird")
   end)

   H.test("Spielersicht: Sprachwechsel zur Laufzeit - neue Zeilen in der neuen Sprache, Zahl der Zeilen bleibt", function()
      local T = fxSession(nil, "enUS")
      T.Locale.Add("deDE", {
         TIP_NOT_COLLECTED = "Aussehen nicht gesammelt",
         TIP_APPLIED = "Transmogrifiziert zu: %s",
         TIP_APPLIED_HIDDEN = "Transmogrifiziert zu: Verborgen",
      })
      local head = T.State.Applied(0)
      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Transmogrified to:"), 1, "englisch")
      T.Locale.Set("deDE")
      hoverEquipped(1)
      H.eq(countMatching(GameTooltip, "Transmogrifiziert zu:"), 1, "deutsch")
      H.eq(countMatching(GameTooltip, "Transmogrified to:"), 0)
      hoverEquipped(15)
      H.eq(countLine(GameTooltip, "Transmogrifiziert zu: Verborgen"), 1)
      T.Locale.Set("enUS")
      hoverEquipped(15)
      H.eq(countLine(GameTooltip, "Transmogrified to: Hidden"), 1)
      H.truthy(head ~= 0)
   end)

   -- ======================================================================
   -- Zufallsfolgen (feste Startwerte)
   -- ======================================================================

   H.test("Zufallsfolgen: hoechstens eine Zeile je Art und Tooltip, je Gegenstand eine Abfrage, keine Fehler", function()
      local extra = {}
      for i = 1, 12 do
         extra[8000 + i] = item("Fuzz Helm " .. i, 2 + i % 3, "Armor", "Plate", "INVTYPE_HEAD")
      end
      local tipNames = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                         "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }
      local ids = { 2001, 2002, 2003, 2004, 2005, 2101, 3001, 3002, 3003, 3004, 3005, 4001, 4002, 1001 }
      for i = 1, 12 do ids[#ids + 1] = 8000 + i end

      for seed = 1, 20 do
         math.randomseed(seed)
         local T = start({ items = extra })
         M.ClearSent()
         local rnd = math.random
         for step = 1, 220 do
            local r = rnd(1, 100)
            local what
            if r <= 30 then
               what = "hover"
               hover(_G[tipNames[rnd(1, #tipNames)]], ids[rnd(1, #ids)])
            elseif r <= 40 then
               what = "inventory"
               hoverEquipped(({ 1, 5, 2, 11, 16, 15 })[rnd(1, 6)])
            elseif r <= 50 then
               what = "hide"
               _G[tipNames[rnd(1, #tipNames)]]:Hide()
            elseif r <= 65 then
               what = "reply"
               T.Net.Handle("CollectionStatus:" .. ids[rnd(1, #ids)] .. ":" .. rnd(0, 2))
            elseif r <= 70 then
               what = "collected"
               T.Net.Handle("CollectionUpdated:" .. ids[rnd(1, #ids)])
            elseif r <= 78 then
               what = "status"
               local map = {}
               if rnd() < 0.7 then map[0] = ({ 4001, HIDDEN, 4002 })[rnd(1, 3)] end
               if rnd() < 0.5 then map[4] = ({ 4002, HIDDEN })[rnd(1, 2)] end
               setStatus(T, map)
            elseif r <= 82 then
               what = "settings"
               T.DB.Set("tooltipCollected", rnd() < 0.7)
               T.DB.Set("tooltipApplied", rnd() < 0.7)
            elseif r <= 86 then
               what = "resolved"
               T.Events.Fire("ITEMS_RESOLVED", rnd(1, 5))
            else
               what = "time"
               settle(rnd() * 0.2)
            end

            for _, name in ipairs(tipNames) do
               local tip = _G[name]
               local c = countLine(tip, T.L.TIP_NOT_COLLECTED)
               local a = countMatching(tip, "Transmogrified to:") + countMatching(tip, "Transmog inactive:")
               if c > 1 or a > 1 then
                  H.fail(("Startwert %d, Schritt %d (%s): %s hat %d/%d Zeilen"):format(seed, step, what, name, c, a))
                  return
               end
            end
            local errs = M.TakeErrors()
            if #errs > 0 then
               H.fail(("Startwert %d, Schritt %d (%s): Fehler %s"):format(seed, step, what, tostring(errs[1])))
               return
            end
         end
         for _, id in ipairs(ids) do
            if queries(id) > 1 then
               H.fail(("Startwert %d: Gegenstand %d wurde %d-mal abgefragt"):format(seed, id, queries(id)))
               return
            end
         end
      end
   end)

end
