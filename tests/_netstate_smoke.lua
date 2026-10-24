-- _netstate_smoke.lua
-- Wegwerf-Selbsttest fuer Core/Net.lua und Core/State.lua.
-- Aufruf im Hauptverzeichnis:  luajit tests/_netstate_smoke.lua
--
-- Geladen werden die ECHTEN Module Locale, Init, Util, Events, Slots, Net, State;
-- Items und DB sind Attrappen. Ein kleiner Fake-Server bildet die Handler aus
-- TransmogAddonProtocol.cpp nach (Formate und Reihenfolge wie im Servercode).

local scriptDir = (arg and arg[0] or ""):match("^(.*)/tests/[^/]*$") or "."

local failures, checks = 0, 0
local current = "?"

local function check(cond, msg)
   checks = checks + 1
   if not cond then
      failures = failures + 1
      print("FAIL [" .. current .. "]: " .. tostring(msg))
   end
end

local function eq(a, b, msg)
   checks = checks + 1
   if a ~= b then
      failures = failures + 1
      print("FAIL [" .. current .. "]: " .. tostring(msg)
         .. " (erwartet " .. tostring(b) .. ", war " .. tostring(a) .. ")")
   end
end

-- ---------------------------------------------------------------------------
-- Umgebung
-- ---------------------------------------------------------------------------

local T                       -- Transmog (je Szenario neu)
local now, frames, sent, chat, errors, equip, itemDB, money, events, log
local srv                     -- Fake-Server

local SERVER_SLOTS = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }
local ARMOR = { [0] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
   [7] = true, [8] = true, [9] = true, [14] = true, [18] = true }

local NEVER = { INVTYPE_BAG = 1, INVTYPE_RELIC = 1, INVTYPE_FINGER = 1, INVTYPE_TRINKET = 1,
   INVTYPE_AMMO = 1, INVTYPE_QUIVER = 1, INVTYPE_NECK = 1 }

local WATCHED = { "LOCALE_CHANGED", "SETTINGS_CHANGED", "ITEMS_RESOLVED", "STATUS_CHANGED",
   "LIST_PROGRESS", "LIST_READY", "EQUIPMENT_CHANGED", "WANTED_CHANGED", "COST_CHANGED",
   "APPLY_STARTED", "APPLY_PROGRESS", "APPLY_DONE", "COLLECTION_UPDATED", "COLLECTION_STATUS",
   "SERVER_OPEN", "SERVER_STATE", "VENDOR_CHANGED" }

local function countEvents(name)
   local n = 0
   for _, e in ipairs(log) do if e.name == name then n = n + 1 end end
   return n
end

local function lastEvent(name)
   for i = #log, 1, -1 do
      if log[i].name == name then return log[i] end
   end
   return nil
end

local function eventsOf(name)
   local out = {}
   for _, e in ipairs(log) do if e.name == name then out[#out + 1] = e end end
   return out
end

local function clearLog() log = {} end

local function makeFrame()
   local f = { shown = true, scripts = {}, registered = {} }
   local mt = {}
   mt.__index = function(_, key)
      return function() end
   end
   setmetatable(f, mt)
   function f.SetScript(self, name, fn) self.scripts[name] = fn end
   function f.GetScript(self, name) return self.scripts[name] end
   function f.RegisterEvent(self, ev) self.registered[ev] = true end
   function f.UnregisterEvent(self, ev) self.registered[ev] = nil end
   function f.Show(self) self.shown = true end
   function f.Hide(self) self.shown = false end
   function f.IsShown(self) return self.shown end
   return f
end

-- Zeit vorruecken (in kleinen Schritten, damit Timer in Reihenfolge laufen)
local function advance(dt)
   local step = 0.05
   local n = math.floor(dt / step + 0.5)
   for _ = 1, n do
      now = now + step
      for _, f in ipairs(frames) do
         local fn = f.scripts.OnUpdate
         if fn and f.shown then fn(f, step) end
      end
   end
end

-- WoW-Ereignis an die Handler des gemeinsamen Event-Frames
local function fireGame(event, ...)
   for _, f in ipairs(frames) do
      local fn = f.scripts.OnEvent
      if fn and f.registered[event] then fn(f, event, ...) end
   end
end

-- Servernachricht an den Client (wie CHAT_MSG_ADDON)
local function S(payload)
   fireGame("CHAT_MSG_ADDON", "transmog", payload, "WHISPER", "Tester")
end

-- ---------------------------------------------------------------------------
-- Fake-Server (Spiegel der C++-Handler)
-- ---------------------------------------------------------------------------

local function newServer()
   local s = {
      mode = "queue",         -- "queue": Antworten per flush(); "sync": sofort
      queue = {},
      collected = {},         -- [id] = true
      valid = {},             -- [slot] = Array von IDs (Reihenfolge wie gesendet)
      stored = {},            -- [slot] = fakeEntry
      equipped = {},          -- [slot] = true
      bucket = {},            -- [slot] = Class+SubClass
      price = 10000,
      money = 1000000,
      drop = {},              -- [Befehlsname] = n  (n Antworten verschlucken)
      log = {},               -- empfangene Befehle
   }

   local function emit(payload)
      if s.mode == "sync" then
         S(payload)
      else
         s.queue[#s.queue + 1] = payload
      end
   end
   s.emit = emit

   function s.flush()
      local q = s.queue
      s.queue = {}
      for _, p in ipairs(q) do S(p) end
      return #q
   end

   local function statusPayload()
      local parts, n = {}, 0
      for slot = 0, 18 do
         local fake = s.stored[slot]
         if fake and fake ~= 0 then
            parts[#parts + 1] = ":" .. slot .. "," .. fake
            n = n + 1
         end
      end
      if n == 0 then return "TransmogStatus:0" end
      return "TransmogStatus:" .. n .. table.concat(parts)
   end

   local function isValid(slot, id)
      for _, v in ipairs(s.valid[slot] or {}) do
         if v == id then return true end
      end
      return false
   end

   local function splitColon(str)
      local out = {}
      for piece in (str .. ":"):gmatch("(.-):") do out[#out + 1] = piece end
      return out
   end

   -- Handler je Befehl
   function s.handle(text)
      s.log[#s.log + 1] = text
      local cmd, args = text:match("^([^:]+):?(.*)$")
      if s.drop[cmd] and s.drop[cmd] > 0 then
         s.drop[cmd] = s.drop[cmd] - 1
         return
      end
      if cmd == "GetTransmogStatus" then
         emit(statusPayload())
      elseif cmd == "GetAvailableTransmogs" then
         for _, slot in ipairs(SERVER_SLOTS) do
            local ids = s.valid[slot] or {}
            local header = "AvailableTransmogs:" .. slot .. ":" .. (s.bucket[slot] or 0)
               .. ":" .. #ids .. ":"
            emit(header .. "start")
            local i = 1
            while i <= #ids do
               local parts = {}
               for j = i, math.min(i + 19, #ids) do parts[#parts + 1] = ids[j] end
               emit(header .. table.concat(parts, ":"))
               i = i + 20
            end
            emit(header .. "end")
         end
      elseif cmd == "GetCollectionStatus" then
         local id = tonumber(args)
         if id then
            emit("CollectionStatus:" .. id .. ":" .. (s.collected[id] and 1 or 0))
         end
      elseif cmd == "Apply" then
         local parts = splitColon(args)
         local slot, id = tonumber(parts[1]), tonumber(parts[2])
         local ok = false
         if #parts == 2 and slot and id and id ~= 0 and slot < 19 and s.equipped[slot] then
            if s.stored[slot] == id then
               ok = true
            elseif id == 999999 then
               ok = ARMOR[slot] == true
            elseif s.collected[id] and isValid(slot, id) then
               if s.money >= s.price then
                  s.money = s.money - s.price
                  ok = true
               end
            end
            if ok then s.stored[slot] = id end
         end
         if ok then emit("ApplyTransmogResult:1:" .. slot .. "," .. id)
         else emit("ApplyTransmogResult:0") end
      elseif cmd == "Remove" then
         local slot = tonumber(args)
         if slot and slot < 19 then
            s.stored[slot] = nil
            emit("ApplyTransmogResult:1:" .. slot .. ",0")
         else
            emit("ApplyTransmogResult:0")
         end
      elseif cmd == "RemoveAll" then
         s.stored = {}
         emit(statusPayload())
      elseif cmd == "CalculateCost" then
         local total = 0
         for pair in (args .. ","):gmatch("(.-),") do
            local a, b = pair:match("^(%d+):(%d+)$")
            if a and tonumber(b) ~= 0 then
               total = total + ((tonumber(b) == 999999) and 0 or s.price)
            end
         end
         emit("TransmogCost:" .. total .. ":" .. (s.money >= total and 1 or 0))
      end
   end

   return s
end

-- ---------------------------------------------------------------------------
-- Szenario-Umgebung
-- ---------------------------------------------------------------------------

local function setItem(id, equipLoc, quality)
   itemDB[id] = { id = id, name = "Item" .. id, quality = quality or 4, icon = "Interface\\Icons\\X" .. id,
      equipLoc = equipLoc, typeKey = 403 }
end

local function equipSlot(server, id, equipLoc)
   setItem(id, equipLoc or "INVTYPE_CHEST", 4)
   equip[server + 1] = "|cffa335ee|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[Item" .. id .. "]|h|r"
   srv.equipped[server] = true
end

local function fresh(name, opts)
   opts = opts or {}
   current = name
   now = 1000
   frames, sent, chat, errors, equip, itemDB, log = {}, {}, {}, {}, {}, {}, {}
   money = 1000000
   srv = newServer()
   srv.mode = opts.mode or "queue"

   _G.Transmog = nil
   _G.GetTime = function() return now end
   _G.UnitName = function() return "Tester" end
   _G.SendAddonMessage = function(prefix, text, channel, target)
      sent[#sent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
      if opts.serverDown then return end
      srv.handle(text)
   end
   _G.GetInventoryItemLink = function(unit, id) return equip[id] end
   _G.GetItemInfo = function(v)
      local id = tonumber(v) or tonumber(tostring(v):match("item:(%d+)"))
      local rec = id and itemDB[id]
      if not rec then return nil end
      return rec.name, "|Hitem:" .. id .. "|h[" .. rec.name .. "]|h", rec.quality, 1, 1, "Armor", "Mail", 1,
         rec.equipLoc, rec.icon
   end
   _G.GetMoney = function() return money end
   _G.geterrorhandler = function() return function(err) errors[#errors + 1] = tostring(err) end end
   _G.CreateFrame = function()
      local f = makeFrame()
      frames[#frames + 1] = f
      return f
   end
   _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) chat[#chat + 1] = text end }

   dofile(scriptDir .. "/Locales/Locale.lua")
   dofile(scriptDir .. "/Core/Init.lua")
   dofile(scriptDir .. "/Core/Util.lua")
   dofile(scriptDir .. "/Core/Events.lua")
   dofile(scriptDir .. "/Core/Slots.lua")
   T = _G.Transmog

   -- Attrappen: Items, DB
   T.Items = {
      Info = function(id) return itemDB[id] end,
      Get = function(id) return itemDB[id] end,
      Request = function(id) T._requested = T._requested or {}; T._requested[id] = true end,
      IsNever = function(loc) return NEVER[loc] ~= nil end,
      TypeKeyFromNames = function() return nil end,
   }
   T.DB = { global = { allowAnywhere = false }, char = {} }

   dofile(scriptDir .. "/Locales/enUS_State.lua")
   dofile(scriptDir .. "/Core/Net.lua")
   dofile(scriptDir .. "/Core/State.lua")
   T.Locale.Set("enUS")

   events = {}
   for _, ev in ipairs(WATCHED) do
      T.Events.On(ev, function(...) log[#log + 1] = { name = ev, n = select("#", ...), ... } end)
   end

   T.enteredWorldAt = now - 60      -- Login-Sweep vorbei
   T.Net.Init()
   T.State.Init()
end

local function startStream(slot, bucket, amount) S("AvailableTransmogs:" .. slot .. ":" .. bucket .. ":" .. amount .. ":start") end
local function endStream(slot, bucket, amount) S("AvailableTransmogs:" .. slot .. ":" .. bucket .. ":" .. amount .. ":end") end

-- Liste eines Slots komplett einspielen
local function feedList(slot, ids, bucket)
   bucket = bucket or 0
   startStream(slot, bucket, #ids)
   local i = 1
   while i <= #ids do
      local parts = {}
      for j = i, math.min(i + 19, #ids) do parts[#parts + 1] = ids[j] end
      S("AvailableTransmogs:" .. slot .. ":" .. bucket .. ":" .. #ids .. ":" .. table.concat(parts, ":"))
      i = i + 20
   end
   endStream(slot, bucket, #ids)
end

local function sentTexts()
   local out = {}
   for _, m in ipairs(sent) do out[#out + 1] = m.text end
   return out
end

local function countSent(prefix)
   local n = 0
   for _, m in ipairs(sent) do
      if m.text:sub(1, #prefix) == prefix then n = n + 1 end
   end
   return n
end

local function lastSent()
   return sent[#sent] and sent[#sent].text
end

local function noErrors(msg)
   eq(#errors, 0, (msg or "keine Fehler") .. (errors[1] and (": " .. errors[1]) or ""))
end

-- ===========================================================================
-- S1: Parser-Robustheit
-- ===========================================================================
do
   fresh("S1 parser robustness")
   local N = T.Net
   -- unbekannte oder verstuemmelte Nachrichten: werfen nicht, sind kein Lebenszeichen
   local garbage = {
      "", ":", "::", ":::", "open", "OPEN", "AvailableTransmogs",
      "AvailableTransmogs:", "AvailableTransmogs:0", "AvailableTransmogs:0:1",
      "AvailableTransmogs:0:1:2", "AvailableTransmogs:0:1:2:", "AvailableTransmogs:x:y:z:start",
      "AvailableTransmogs:99:0:0:start", "AvailableTransmogs:-1:0:0:end", "AvailableTransmogs:0:0:0:abc:def",
      "AvailableTransmogs:0:0:0:1.5:2e3", "TransmogStatus", "TransmogStatus:", "TransmogStatus:abc",
      "TransmogStatus:2", "TransmogStatus:2:abc", "TransmogStatus:1:0", "TransmogStatus:1:0,", "TransmogStatus:1:,5",
      "TransmogStatus:1:99,5", "ApplyTransmogResult", "ApplyTransmogResult:", "ApplyTransmogResult:2",
      "ApplyTransmogResult:x", "TransmogCost", "TransmogCost:abc:1",
      "TransmogCost:100", "TransmogCost:100:x", "TransmogCost:-5:1", "CollectionStatus", "CollectionStatus:12",
      "CollectionStatus:12:7", "CollectionStatus:x:1", "CollectionUpdated", "CollectionUpdated:abc",
      "CollectionUpdated:0", "NewTransmog:123", "transmog\tOpen\0", "\0", string.rep("A", 5000),
      string.rep(":", 5000), "|cffff0000|Hitem:1|h[x]|h|r", "%s%d",
   }
   for _, g in ipairs(garbage) do
      local ok, err = pcall(N.Handle, g)
      check(ok, "Handle wirft nicht bei: " .. tostring(g):sub(1, 40) .. " " .. tostring(err))
      eq(err, false, "verworfen: " .. tostring(g):sub(1, 40))
   end
   for _, v in ipairs({ 1, true, {}, function() end }) do
      local ok = pcall(N.Handle, v)
      check(ok, "Handle wirft nicht bei Typ " .. type(v))
   end
   local ok = pcall(N.Handle, nil)
   check(ok, "Handle(nil)")
   noErrors("Parser: keine gemeldeten Fehler")
   eq(N.Handle("Bogus:1"), false, "unbekannter Befehl -> false")
   eq(N.state, "UNKNOWN", "unbekannte/verstuemmelte Befehle sind kein Lebenszeichen")
   eq(countEvents("SERVER_STATE"), 0, "kein SERVER_STATE")
   -- das Echo der eigenen Befehle (Server ohne Modul) ist kein Lebenszeichen
   for _, echo in ipairs({ "GetTransmogStatus", "GetAvailableTransmogs", "GetCollectionStatus:5",
      "Apply:0:123", "Remove:0", "RemoveAll", "CalculateCost:0:5" }) do
      eq(N.Handle(echo), false, "Echo ignoriert: " .. echo)
   end
   eq(N.state, "UNKNOWN", "Echo der eigenen Befehle ist kein Lebenszeichen")
   -- Nachrichten, die ueber CHAT_MSG_ADDON hereinkommen, verhalten sich genauso
   for _, echo in ipairs({ "GetTransmogStatus", "Apply:0:5", "RemoveAll" }) do
      fireGame("CHAT_MSG_ADDON", "transmog", echo, "WHISPER", "Tester")
   end
   eq(N.state, "UNKNOWN", "Echo ueber CHAT_MSG_ADDON ist kein Lebenszeichen")

   -- gueltige Befehle mit unlesbarem Rest: nur "wirft nicht" und "aendert nichts"
   local lenient = {
      "ApplyTransmogResult:1", "ApplyTransmogResult:1:", "ApplyTransmogResult:1:x,y",
      "ApplyTransmogResult:1:5", "ApplyTransmogResult:1:99,5",
      "AvailableTransmogs:0:0:0:" .. string.rep("1:", 300),
   }
   for _, g in ipairs(lenient) do
      local ok2, err2 = pcall(N.Handle, g)
      check(ok2, "Handle wirft nicht bei: " .. tostring(g):sub(1, 40) .. " " .. tostring(err2))
   end
   eq(T.State.Busy(), false, "lenient: nichts passiert")
   eq(T.State.PendingCount(), 0, "lenient: nichts ausstehend")
   eq(T.State.Applied(0), 0, "lenient: nichts angewendet")
   noErrors("lenient: keine gemeldeten Fehler")

   fresh("S1b open and status")
   N = T.Net
   eq(N.Handle("Open:extra"), true, "Open mit Zusatzfeld bleibt ein Open")
   eq(N.state, "UNKNOWN", "Open ist unaufgefordert: kein Lebenszeichen")
   eq(countEvents("SERVER_STATE"), 0, "kein SERVER_STATE durch Open")
   eq(N.Handle("TransmogStatus:0"), true, "Antwort erkannt")
   eq(N.state, "OK", "Antwort -> OK")
   eq(countEvents("SERVER_STATE"), 1, "SERVER_STATE(OK)")
   eq(N.Handle("Open"), true, "Open erkannt")
   eq(countEvents("SERVER_STATE"), 1, "OK nur einmal gemeldet")
   -- verstuemmelte Status-/Ergebnis-Nachrichten duerfen den Zustand nicht veraendern
   S("TransmogStatus:2:0,555:4,666")
   eq(T.State.Applied(0), 555, "Status uebernommen")
   S("TransmogStatus:2:abc")
   eq(T.State.Applied(0), 555, "verstuemmelter Status veraendert nichts")
   S("TransmogStatus:3")
   eq(T.State.Applied(0), 555, "Status ohne Eintraege bei n>0 verworfen")
   S("TransmogStatus:0")
   eq(T.State.Applied(0), 0, "TransmogStatus:0 leert")
   noErrors()
end

-- ===========================================================================
-- S2: Status-Format
-- ===========================================================================
do
   fresh("S2 status")
   S("TransmogStatus:3:0,12345:4,999999:15,0")
   eq(T.State.Applied(0), 12345, "slot 0")
   eq(T.State.Applied(4), 999999, "slot 4 hidden")
   eq(T.State.Applied(15), 0, "slot 15 (fake 0) bleibt 0")
   eq(T.State.Applied(2), 0, "unerwaehnter Slot = 0")
   check(T.State.StatusKnown(), "StatusKnown")
   eq(countEvents("STATUS_CHANGED"), 1, "STATUS_CHANGED einmal")
   S("TransmogStatus:3:0,12345:4,999999:15,0")
   eq(countEvents("STATUS_CHANGED"), 1, "unveraenderter Status feuert nicht erneut")
   -- Slots ausserhalb der 14 werden ignoriert
   S("TransmogStatus:2:1,111:10,222")
   eq(T.State.Applied(1), 0, "Halsslot ignoriert")
   eq(T.State.Applied(0), 0, "Rest zurueckgesetzt")
   -- Items der angewendeten Aussehen werden vorgewaermt
   S("TransmogStatus:1:2,777")
   check(T._requested and T._requested[777], "Item 777 vorgewaermt")
   noErrors()
end

-- ===========================================================================
-- S3: Listen
-- ===========================================================================
do
   fresh("S3 lists")
   local list = T.State.List(0)
   check(list ~= nil and list.ready == false, "List nie nil, nicht fertig")
   check(T.State.List(99) ~= nil, "List(99) nie nil")
   eq(#T.State.List(1).ids, 0, "List(1) leer")

   -- Chunk/Ende ohne Start werden ignoriert
   S("AvailableTransmogs:0:5:3:100:101:102")
   S("AvailableTransmogs:0:5:3:end")
   eq(T.State.List(0).ready, false, "Ende ohne Start macht nicht fertig")
   eq(#T.State.List(0).ids, 0, "Chunk ohne Start ignoriert")

   startStream(0, 7, 5)
   eq(T.State.List(0).bucket, 7, "bucket")
   eq(T.State.List(0).amount, 5, "amount")
   eq(T.State.List(0).ready, false, "nach Start nicht fertig")
   S("AvailableTransmogs:0:7:5:100:101:101:102")
   eq(#T.State.List(0).ids, 3, "dedupliziert im Chunk")
   S("AvailableTransmogs:0:7:5:102:103:104")
   eq(#T.State.List(0).ids, 5, "dedupliziert ueber Chunks")
   eq(T.State.List(0).received, 5, "received")
   eq(T.State.List(0).ids[1], 100, "Reihenfolge")
   eq(T.State.List(0).ids[5], 104, "Reihenfolge Ende")
   check(T.State.List(0).set[103], "set")
   eq(T.State.List(0).ready, false, "noch nicht fertig")
   eq(countEvents("LIST_READY"), 0, "noch kein LIST_READY")
   endStream(0, 7, 5)
   eq(T.State.List(0).ready, true, "fertig nach end")
   eq(countEvents("LIST_READY"), 1, "LIST_READY einmal")
   eq(lastEvent("LIST_READY")[1], 0, "LIST_READY(slot)")
   check(countEvents("LIST_PROGRESS") >= 3, "LIST_PROGRESS gefeuert")
   check(T.State.IsAvailable(0, 100), "IsAvailable true")
   check(not T.State.IsAvailable(0, 999), "IsAvailable false")
   check(T.State.IsAvailable(0, 0), "IsAvailable(0) true")
   check(T.State.IsAvailable(0, T.HIDDEN_ID), "IsAvailable(HIDDEN) Kopf true")
   check(not T.State.IsAvailable(15, T.HIDDEN_ID), "IsAvailable(HIDDEN) Waffe false")

   -- Neustart ersetzt die Liste
   startStream(0, 7, 2)
   eq(T.State.List(0).ready, false, "Neustart: nicht fertig")
   eq(#T.State.List(0).ids, 0, "Neustart: leer")
   check(not T.State.IsAvailable(0, 100), "Neustart: alte id weg")
   S("AvailableTransmogs:0:7:2:200:201")
   endStream(0, 7, 2)
   eq(#T.State.List(0).ids, 2, "zweite Liste")
   -- Slot 1 (Hals) gibt es nicht
   startStream(1, 0, 0)
   endStream(1, 0, 0)
   eq(T.State.List(1).ready, false, "Slot 1 wird nicht gefuehrt")
   noErrors()
end

-- ===========================================================================
-- S4: Inaktiv / Baseline
-- ===========================================================================
do
   fresh("S4 inactive baseline")
   equipSlot(4, 5001, "INVTYPE_CHEST")
   T.State.RefreshEquipment()
   S("TransmogStatus:2:4,555:0,999999")
   eq(T.State.Applied(4), 555, "applied")
   check(not T.State.IsInactive(4), "ohne fertige Liste nie inaktiv")
   eq(T.State.Baseline(4), 555, "Baseline == Applied ohne Liste")
   feedList(4, { 1, 2, 3 })
   check(T.State.IsInactive(4), "inaktiv: 555 nicht in Liste")
   eq(T.State.Baseline(4), 0, "Baseline 0 bei inaktiv")
   eq(T.State.Wanted(4), 0, "Wanted = Baseline")
   check(not T.State.HasPending(4), "kein Pending")
   -- HIDDEN ist nie inaktiv
   feedList(0, { 1, 2 })
   check(not T.State.IsInactive(0), "HIDDEN nie inaktiv")
   eq(T.State.Baseline(0), 999999, "Baseline HIDDEN")
   -- aktiv, wenn in der Liste
   feedList(4, { 1, 555, 3 })
   check(not T.State.IsInactive(4), "aktiv")
   eq(T.State.Baseline(4), 555, "Baseline = Applied")
   -- Neustart des Stroms: wieder Baseline == Applied
   startStream(4, 0, 3)
   check(not T.State.IsInactive(4), "waehrend Neustart nicht inaktiv")
   eq(T.State.Baseline(4), 555, "Baseline waehrend Neustart")
   -- leerer Slot: Liste leer => inaktiv
   noErrors()
end

-- ===========================================================================
-- S5: Select
-- ===========================================================================
do
   fresh("S5 select")
   equipSlot(0, 1001, "INVTYPE_HEAD")
   equipSlot(4, 1004, "INVTYPE_CHEST")
   equipSlot(15, 1015, "INVTYPE_2HWEAPON")
   equipSlot(17, 1017, "INVTYPE_RELIC")
   T.State.RefreshEquipment()
   eq(T.State.SlotState(0), "READY", "Kopf READY")
   eq(T.State.SlotState(3), "EMPTY", "Hemd leer")
   eq(T.State.SlotState(17), "NEVER", "Relikt NEVER")
   eq(T.State.SlotState(1), "NEVER", "unbekannter Slot NEVER")
   check(T.State.Equipped(0) ~= nil and T.State.Equipped(0).id == 1001, "Equipped id")
   eq(T.State.Equipped(0).equipLoc, "INVTYPE_HEAD", "Equipped equipLoc")
   eq(T.State.Equipped(3), nil, "Equipped leer = nil")
   check(countEvents("EQUIPMENT_CHANGED") == 4, "EQUIPMENT_CHANGED je geaendertem Slot (" .. countEvents("EQUIPMENT_CHANGED") .. ")")

   check(not T.State.Select(3, 5), "leerer Slot")
   check(not T.State.Select(17, 5), "NEVER-Slot")
   check(not T.State.Select(1, 5), "kein Slot")
   check(not T.State.Select(15, T.HIDDEN_ID), "HIDDEN auf Waffe")
   check(not T.State.Select(0, "abc"), "nicht numerisch")
   check(not T.State.Select(0, -1), "negativ")
   check(not T.State.Select(0, 1.5), "gebrochen")
   check(not T.State.Select(0, nil), "nil")
   eq(T.State.PendingCount(), 0, "nichts ausstehend nach ungueltigen")

   clearLog()
   check(T.State.Select(0, T.HIDDEN_ID), "HIDDEN auf Kopf")
   eq(T.State.Wanted(0), 999999, "Wanted HIDDEN")
   check(T.State.HasPending(0), "pending")
   eq(countEvents("WANTED_CHANGED"), 1, "WANTED_CHANGED")
   eq(lastEvent("WANTED_CHANGED")[1], 0, "WANTED_CHANGED(slot)")
   -- gleicher Wert nochmals: gueltig, aber keine Aenderung
   check(T.State.Select(0, T.HIDDEN_ID), "nochmals HIDDEN")
   eq(countEvents("WANTED_CHANGED"), 1, "kein weiteres Event")
   -- 0 == Baseline (0) entfernt die Auswahl
   check(T.State.Select(0, 0), "0 waehlen")
   check(not T.State.HasPending(0), "== Baseline: keine Auswahl")
   eq(countEvents("WANTED_CHANGED"), 2, "Event bei Entfernen")

   -- Liste nicht fertig: optimistisch
   check(T.State.Select(4, "12345"), "Zahlenstring, Liste nicht fertig: optimistisch")
   eq(T.State.Wanted(4), 12345, "normalisiert")
   -- Liste kommt ohne 12345: Auswahl wird verworfen
   clearLog()
   feedList(4, { 1, 2, 3 })
   eq(T.State.Wanted(4), 0, "Auswahl nicht in Liste: verworfen")
   check(not T.State.HasPending(4), "kein Pending mehr")
   eq(countEvents("WANTED_CHANGED"), 1, "WANTED_CHANGED beim Verwerfen")
   -- Liste fertig: unbekannte id abgelehnt
   check(not T.State.Select(4, 99), "ID nicht in fertiger Liste")
   check(T.State.Select(4, 2), "ID in Liste")
   eq(T.State.Wanted(4), 2, "Wanted 2")
   eq(T.State.PendingCount(), 1, "1 Pending")
   -- PendingSlots aufsteigend
   feedList(15, { 70, 71 })
   check(T.State.Select(15, 71), "Waffe")
   check(T.State.Select(0, T.HIDDEN_ID), "Kopf hidden")
   local p = T.State.PendingSlots()
   eq(#p, 3, "drei Pending")
   eq(p[1], 0, "aufsteigend 1"); eq(p[2], 4, "aufsteigend 2"); eq(p[3], 15, "aufsteigend 3")
   -- Toggle
   check(T.State.Toggle(15), "Toggle verwirft Pending")
   check(not T.State.HasPending(15), "verworfen")
   S("TransmogStatus:1:15,70")
   eq(T.State.Baseline(15), 70, "Baseline 70")
   check(T.State.Toggle(15), "Toggle: Baseline ~= 0 -> Entfernen vormerken")
   eq(T.State.Wanted(15), 0, "Wanted 0 (Entfernen)")
   check(T.State.HasPending(15), "pending Entfernen")
   check(T.State.Toggle(15), "Toggle verwirft")
   check(not T.State.Toggle(3), "Toggle leerer Slot")
   -- Discard / DiscardAll
   check(T.State.Discard(4), "Discard")
   check(not T.State.Discard(4), "Discard ohne Auswahl")
   clearLog()
   check(T.State.DiscardAll(), "DiscardAll")
   eq(T.State.PendingCount(), 0, "alles verworfen")
   eq(countEvents("WANTED_CHANGED"), 1, "ein Event")
   eq(lastEvent("WANTED_CHANGED").n, 1, "Event mit nil-Argument gefeuert")
   -- SetMany
   clearLog()
   feedList(0, { 8, 9 })
   local changed = T.State.SetMany({ [0] = 8, [4] = 3, [15] = 71, [3] = 5, [17] = 5, [1] = 5, [2] = 5 })
   eq(changed, 3, "SetMany: nur gueltige Slots (0,4,15)")
   eq(countEvents("WANTED_CHANGED"), 1, "SetMany: EIN Event")
   eq(T.State.Wanted(0), 8, "SetMany Kopf")
   eq(T.State.PendingCount(), 3, "SetMany pending")
   noErrors()
end

-- ===========================================================================
-- S6: Apply (Warteschlange, FIFO)
-- ===========================================================================
do
   fresh("S6 apply queue")
   srv.collected = { [11] = true, [12] = true, [13] = true }
   equipSlot(0, 1001, "INVTYPE_HEAD")
   equipSlot(4, 1004, "INVTYPE_CHEST")
   equipSlot(15, 1015, "INVTYPE_2HWEAPON")
   srv.valid[0] = { 11 }
   srv.valid[4] = { 12 }
   srv.valid[15] = { 13 }
   srv.stored[15] = 13
   T.State.RefreshEquipment()
   -- Status und Listen vom Server holen
   T.Net.RequestStatus()
   T.Net.RequestLists()
   srv.flush()
   check(T.State.ListsReady(), "alle 14 Listen fertig")
   eq(countEvents("LIST_READY"), 14, "14x LIST_READY")
   eq(T.State.Applied(15), 13, "Status geladen")

   T.State.SetVendor(true)
   eq(T.State.CanApply(), false, "nichts gewaehlt")
   check(select(2, T.State.CanApply()) == "APPLY_REASON_NONE", "Grund NONE")
   check(T.State.Select(4, 12), "wahl Brust")
   check(T.State.Select(0, 11), "wahl Kopf")
   check(T.State.Select(15, 0), "Waffe entfernen")
   eq(T.State.PendingCount(), 3, "3 Pending")
   -- Kosten: noch ausstehend
   local ok, why = T.State.CanApply()
   eq(ok, false, "Kosten ausstehend")
   eq(why, "APPLY_REASON_COST_PENDING", "Grund COST_PENDING")
   advance(0.3)
   eq(countSent("CalculateCost:"), 1, "eine Kostenanfrage")
   eq(lastSent(), "CalculateCost:0:11,4:12", "Paare ohne wanted==0, aufsteigend")
   srv.flush()
   local c = T.State.Cost()
   check(c.valid and not c.pending, "Kosten gueltig")
   eq(c.copper, 20000, "2 x 10000")
   check(c.canPurchase, "bezahlbar")
   check(T.State.CanApply(), "kann anwenden")

   clearLog()
   local before = #sent
   check(T.State.Apply(), "Apply gestartet")
   check(T.State.Busy(), "Busy")
   eq(#sent, before + 1, "genau EINE Operation unterwegs")
   eq(lastSent(), "Apply:0:11", "erste Operation: Slot 0")
   -- zweites Apply waehrend Busy wird ignoriert
   local ok2, why2 = T.State.Apply()
   eq(ok2, false, "zweites Apply ignoriert")
   eq(why2, "APPLY_REASON_BUSY", "Grund BUSY")
   eq(#sent, before + 1, "nichts zusaetzlich gesendet")
   eq(countEvents("APPLY_STARTED"), 1, "APPLY_STARTED")
   eq(lastEvent("APPLY_STARTED")[1], 3, "APPLY_STARTED(total=3)")
   srv.flush()                                  -- Antwort 1
   eq(#sent, before + 2, "zweite Operation nach Antwort")
   eq(lastSent(), "Apply:4:12", "zweite: Slot 4")
   eq(T.State.Applied(0), 11, "lokal angewendet nach Erfolg")
   srv.flush()
   eq(lastSent(), "Remove:15", "dritte: Remove Slot 15")
   srv.flush()
   check(not T.State.Busy(), "fertig")
   eq(T.State.Applied(4), 12, "Slot 4 = 12")
   eq(T.State.Applied(15), 0, "Slot 15 entfernt")
   eq(T.State.PendingCount(), 0, "nichts ausstehend")
   eq(countEvents("APPLY_PROGRESS"), 3, "3x APPLY_PROGRESS")
   local prog = eventsOf("APPLY_PROGRESS")
   eq(prog[1][1], 0, "Progress 1 slot"); eq(prog[1][2], true, "Progress 1 ok"); eq(prog[1][3], 11, "Progress 1 id")
   eq(prog[3][1], 15, "Progress 3 slot"); eq(prog[3][3], 0, "Progress 3 id 0 (Remove)")
   eq(countEvents("APPLY_DONE"), 1, "APPLY_DONE")
   eq(lastEvent("APPLY_DONE")[1], 3, "nOk=3")
   eq(lastEvent("APPLY_DONE")[2], 0, "nFail=0")
   -- Resync: Status und Kosten wurden danach angefragt
   check(countSent("GetTransmogStatus") >= 2, "Status neu angefragt")
   check(srv.log[#srv.log]:match("^GetTransmogStatus") ~= nil, "letzter Befehl: GetTransmogStatus")
   -- Chatmeldung
   local sawOk = false
   for _, line in ipairs(chat) do if line:find("Appearance applied.", 1, true) then sawOk = true end end
   check(sawOk, "Chat: MSG_APPLY_OK")
   noErrors()
end

-- ===========================================================================
-- S7: Fehlschlag, Zeitueberschreitung, verspaetete Antwort
-- ===========================================================================
do
   fresh("S7 failure and timeout")
   srv.collected = { [11] = true, [12] = true, [13] = true }
   equipSlot(0, 1001, "INVTYPE_HEAD")
   equipSlot(4, 1004, "INVTYPE_CHEST")
   equipSlot(7, 1007, "INVTYPE_FEET")
   srv.valid[0] = { 11 }
   srv.valid[4] = { 12 }
   srv.valid[7] = { 13 }
   T.State.RefreshEquipment()
   T.Net.RequestLists(); srv.flush()
   T.State.SetVendor(true)
   T.State.Select(0, 11); T.State.Select(4, 12); T.State.Select(7, 13)
   advance(0.3); srv.flush()
   check(T.State.CanApply(), "bereit")

   -- Operation 1 scheitert (Server verschluckt nichts, aber wir lassen Slot 0 ablehnen)
   srv.collected[11] = nil
   T.State.Apply()
   srv.flush()                                   -- Antwort 0 fuer Slot 0
   eq(T.State.Applied(0), 0, "Slot 0 nicht angewendet")
   eq(T.State.Wanted(0), 11, "Auswahl bleibt bei Fehlschlag")
   check(T.State.HasPending(0), "Slot 0 weiter pending")
   eq(lastSent(), "Apply:4:12", "naechste Operation nach Fehlschlag")
   -- Operation 2 wird normal beantwortet, danach geht Operation 3 raus; deren
   -- Antwort halten wir zurueck (Timeout), liefern sie aber spaeter aus.
   srv.flush()
   eq(T.State.Applied(4), 12, "Slot 4 angewendet")
   eq(lastSent(), "Apply:7:13", "Operation 3 gesendet")
   -- jetzt Operation 3 haengen lassen: Antwort eingereiht NICHT ausliefern
   local heldAnswer = srv.queue
   srv.queue = {}
   eq(T.State.Busy(), true, "noch busy")
   advance(4.5)
   eq(T.State.Busy(), true, "vor 5 s noch busy")
   advance(1.0)
   check(not T.State.Busy(), "nach 5 s Timeout fertig")
   eq(lastEvent("APPLY_DONE")[1], 1, "nOk=1")
   eq(lastEvent("APPLY_DONE")[2], 2, "nFail=2 (Fehlschlag + Timeout)")
   eq(T.State.Wanted(7), 13, "Auswahl bleibt bei Timeout")
   -- verspaetete Antwort: lokal uebernommen, Warteschlange konsistent
   for _, p in ipairs(heldAnswer) do S(p) end
   eq(T.State.Applied(7), 13, "verspaetete Erfolgsantwort uebernommen")
   check(not T.State.HasPending(7), "Slot 7 nicht mehr pending")
   check(not T.State.Busy(), "weiter nicht busy")
   -- Slot 0 ist noch pending; erneutes Anwenden moeglich
   advance(0.5); srv.flush()
   srv.collected[11] = true
   local ok3, why3 = T.State.CanApply()
   check(ok3, "erneut anwendbar: " .. tostring(why3))
   T.State.Apply(); srv.flush()
   eq(T.State.Applied(0), 11, "Wiederholung erfolgreich")
   check(not T.State.Busy(), "fertig")
   noErrors()
end

-- ===========================================================================
-- S8: Fehlantwort ohne Operation, unaufgeforderter Erfolg
-- ===========================================================================
do
   fresh("S8 unsolicited results")
   equipSlot(0, 1001, "INVTYPE_HEAD")
   T.State.RefreshEquipment()
   S("ApplyTransmogResult:0")
   check(not T.State.Busy(), "Fehlantwort ohne Operation: ignoriert")
   S("ApplyTransmogResult:1:0,4321")
   eq(T.State.Applied(0), 4321, "unaufgeforderter Erfolg wird lokal uebernommen")
   S("ApplyTransmogResult:1")
   S("ApplyTransmogResult:1:x,y")
   eq(T.State.Applied(0), 4321, "ohne Nutzdaten und ohne Operation: nichts")
   noErrors()
end

-- ===========================================================================
-- S9: Kosten (Zaehler, Verwerfen, Wiederholung, Aufgeben)
-- ===========================================================================
do
   fresh("S9 cost counters")
   srv.collected = { [11] = true, [12] = true, [13] = true }
   equipSlot(0, 1001, "INVTYPE_HEAD")
   equipSlot(4, 1004, "INVTYPE_CHEST")
   equipSlot(5, 1005, "INVTYPE_WAIST")
   srv.valid[0] = { 11 }
   srv.valid[4] = { 12 }
   srv.valid[5] = { 13 }
   T.State.RefreshEquipment()
   T.Net.RequestLists(); srv.flush()

   -- nichts ausstehend: kostenlos und gueltig, keine Anfrage
   local c = T.State.Cost()
   check(c.valid and not c.pending and c.copper == 0 and c.canPurchase, "ohne Auswahl: 0 / gueltig")
   -- nur HIDDEN: keine Anfrage
   T.State.Select(0, T.HIDDEN_ID)
   advance(1)
   eq(countSent("CalculateCost:"), 0, "nur HIDDEN: keine Anfrage")
   c = T.State.Cost()
   check(c.valid and not c.pending and c.copper == 0, "nur HIDDEN: 0 / gueltig")
   -- HIDDEN + bezahlt: beide Paare in der Anfrage
   T.State.Select(4, 12)
   c = T.State.Cost()
   check(c.pending and not c.valid, "direkt nach Auswahl: ausstehend (entprellt)")
   eq(countSent("CalculateCost:"), 0, "noch nicht gesendet (Entprellung)")
   advance(0.3)
   eq(countSent("CalculateCost:"), 1, "gesendet nach 0,25 s")
   eq(lastSent(), "CalculateCost:0:999999,4:12", "Paare inkl. HIDDEN")
   -- zweite Aenderung, bevor die Antwort da ist => zweite Anfrage
   T.State.Select(5, 13)
   advance(0.3)
   eq(countSent("CalculateCost:"), 2, "zweite Anfrage")
   eq(lastSent(), "CalculateCost:0:999999,4:12,5:13", "Paare Slot 0,4,5")
   -- beide Antworten treffen jetzt ein: die erste ist veraltet
   clearLog()
   S("TransmogCost:111:0")           -- Antwort der ERSTEN Anfrage (verworfen)
   c = T.State.Cost()
   check(c.pending and not c.valid, "erste (veraltete) Antwort verworfen, weiter ausstehend")
   S("TransmogCost:20000:1")         -- Antwort der LETZTEN Anfrage
   c = T.State.Cost()
   check(c.valid and not c.pending, "letzte Antwort uebernommen")
   eq(c.copper, 20000, "copper")
   check(c.canPurchase, "canPurchase")
   check(countEvents("COST_CHANGED") >= 1, "COST_CHANGED gefeuert")
   -- unveraenderte Auswahl: keine neue Anfrage
   local n = countSent("CalculateCost:")
   T.State.RequestCost()
   advance(0.5)
   eq(countSent("CalculateCost:"), n, "gleiche Signatur: gecacht")
   -- Geld sinkt: canPurchase lokal neu bewertet
   money = 5000
   fireGame("PLAYER_MONEY")
   c = T.State.Cost()
   eq(c.canPurchase, false, "PLAYER_MONEY: nicht mehr bezahlbar")
   T.State.SetVendor(true)
   local ok, why = T.State.CanApply()
   eq(why, "APPLY_REASON_MONEY", "Grund MONEY")
   money = 1000000
   fireGame("PLAYER_MONEY")
   check(T.State.Cost().canPurchase, "wieder bezahlbar")

   -- Verlorene Antwort: einmal wiederholen, dann aufgeben
   T.State.DiscardAll()
   srv.mode = "queue"
   srv.drop.CalculateCost = 100
   T.State.Select(4, 12)
   advance(0.3)
   local base = countSent("CalculateCost:")
   c = T.State.Cost()
   check(c.pending, "ausstehend")
   advance(5.2)
   eq(countSent("CalculateCost:"), base + 1, "nach 5 s einmal wiederholt")
   check(T.State.Cost().pending, "weiter ausstehend")
   advance(5.2)
   eq(countSent("CalculateCost:"), base + 1, "nicht ein drittes Mal")
   c = T.State.Cost()
   check(not c.pending and not c.valid, "aufgegeben: nicht ausstehend, ungueltig")
   local okA, whyA = T.State.CanApply()
   check(okA, "Anwenden trotzdem moeglich (Server prueft): " .. tostring(whyA))
   noErrors()
end

-- ===========================================================================
-- S10: CanApply-Reihenfolge
-- ===========================================================================
do
   fresh("S10 canapply order", { serverDown = true })
   srv.collected = { [11] = true }
   equipSlot(0, 1001, "INVTYPE_HEAD")
   srv.valid[0] = { 11 }
   T.State.RefreshEquipment()
   -- (kein feedList: jede Servernachricht waere ein Lebenszeichen)
   -- UNKNOWN: kein SERVER-Grund
   local ok, why = T.State.CanApply()
   eq(why, "APPLY_REASON_NONE", "NONE bei UNKNOWN")
   T.State.Select(0, 11)
   ok, why = T.State.CanApply()
   eq(why, "APPLY_REASON_VENDOR", "VENDOR")
   T.State.SetVendor(true)
   ok, why = T.State.CanApply()
   eq(why, "APPLY_REASON_COST_PENDING", "COST_PENDING")
   T.DB.global.allowAnywhere = true
   T.State.SetVendor(false)
   ok, why = T.State.CanApply()
   eq(why, "APPLY_REASON_COST_PENDING", "allowAnywhere umgeht VENDOR")
   -- Server stumm: ABSENT hat Vorrang vor allem
   advance(9)
   eq(T.Net.state, "ABSENT", "ABSENT nach 8 s")
   ok, why = T.State.CanApply()
   eq(why, "APPLY_REASON_SERVER", "SERVER hat Vorrang")
   T.State.DiscardAll()
   ok, why = T.State.CanApply()
   eq(why, "APPLY_REASON_SERVER", "SERVER vor NONE")
   -- Apply wird abgelehnt und meldet
   local started = T.State.Apply()
   eq(started, false, "Apply bei ABSENT abgelehnt")
   local saw = false
   for _, line in ipairs(chat) do if line:find("does not answer", 1, true) then saw = true end end
   check(saw, "Chatmeldung MSG_SERVER_ABSENT")
   noErrors()
end

-- ===========================================================================
-- S11: Ausruestungswechsel
-- ===========================================================================
do
   fresh("S11 equipment change")
   srv.collected = { [11] = true, [12] = true }
   equipSlot(0, 1001, "INVTYPE_HEAD")
   srv.valid[0] = { 11 }
   T.State.RefreshEquipment()
   advance(1)           -- Entprellung aus Init/RefreshEquipment ablaufen lassen
   srv.flush()
   check(T.State.List(0).ready, "Liste fertig")
   eq(countSent("GetAvailableTransmogs"), 1, "Listen einmal angefordert")
   T.State.Select(0, 11)
   check(T.State.HasPending(0), "pending")
   clearLog()
   -- neuer Gegenstand
   equipSlot(0, 1002, "INVTYPE_HEAD")
   fireGame("PLAYER_EQUIPMENT_CHANGED", 1, false)
   fireGame("PLAYER_EQUIPMENT_CHANGED", 1, false)
   eq(countEvents("EQUIPMENT_CHANGED"), 1, "EQUIPMENT_CHANGED(slot) einmal")
   eq(lastEvent("EQUIPMENT_CHANGED")[1], 0, "slot 0")
   check(not T.State.HasPending(0), "Auswahl verworfen")
   eq(countEvents("WANTED_CHANGED"), 1, "WANTED_CHANGED")
   eq(T.State.Equipped(0).id, 1002, "neuer Gegenstand")
   check(not T.State.List(0).ready, "Liste als veraltet markiert")
   local lists = countSent("GetAvailableTransmogs")
   advance(0.3)
   eq(countSent("GetAvailableTransmogs"), lists, "noch nicht (0,5 s Entprellung)")
   advance(0.4)
   eq(countSent("GetAvailableTransmogs"), lists + 1, "nach 0,5 s genau eine Listenanfrage")
   check(countSent("GetTransmogStatus") >= 1, "Status auch angefordert")
   srv.flush()
   check(T.State.List(0).ready, "neue Liste fertig")
   -- Slot wird geleert
   equip[1] = nil
   fireGame("PLAYER_EQUIPMENT_CHANGED", 1, true)
   eq(T.State.SlotState(0), "EMPTY", "leer")
   eq(T.State.Equipped(0), nil, "Equipped nil")
   -- gleicher Gegenstand mit anderem Link (Verzauberung): kein Event
   equipSlot(0, 1003, "INVTYPE_HEAD")
   T.State.RefreshEquipment()
   clearLog()
   equip[1] = "|cffa335ee|Hitem:1003:3000:0:0:0:0:0:0:0|h[Item1003]|h|r"
   T.State.RefreshEquipment()
   eq(countEvents("EQUIPMENT_CHANGED"), 0, "Verzauberung ist keine Aenderung")
   noErrors()
end

-- ===========================================================================
-- S12: Verbindungszustand
-- ===========================================================================
do
   fresh("S12 net state", { serverDown = true })
   eq(T.Net.state, "UNKNOWN", "UNKNOWN am Anfang")
   advance(20)
   eq(T.Net.state, "UNKNOWN", "ohne Anfrage bleibt UNKNOWN")
   T.Net.RequestStatus()
   advance(7.5)
   eq(T.Net.state, "UNKNOWN", "vor 8 s noch UNKNOWN")
   advance(1)
   eq(T.Net.state, "ABSENT", "8 s ohne Antwort: ABSENT")
   eq(countEvents("SERVER_STATE"), 1, "SERVER_STATE gefeuert")
   eq(lastEvent("SERVER_STATE")[1], "ABSENT", "SERVER_STATE(ABSENT)")
   S("TransmogStatus:0")
   eq(T.Net.state, "OK", "spaete Nachricht: OK")
   eq(countEvents("SERVER_STATE"), 2, "SERVER_STATE(OK)")

   fresh("S12b net state ok")
   T.Net.RequestStatus()
   advance(2)
   S("TransmogStatus:0")
   eq(T.Net.state, "OK", "OK")
   advance(10)
   eq(T.Net.state, "OK", "bleibt OK")
   eq(countEvents("SERVER_STATE"), 1, "ein Wechsel")
end

-- ===========================================================================
-- S13: Sammlung
-- ===========================================================================
do
   fresh("S13 collection")
   srv.collected = { [500] = true }
   T.Net.QueryCollection(500)
   eq(countSent("GetCollectionStatus:500"), 1, "gesendet")
   T.Net.QueryCollection(500)
   T.Net.QueryCollection("500")
   eq(countSent("GetCollectionStatus:500"), 1, "nicht doppelt solange ausstehend")
   eq(T.Net.CollectionState(500), nil, "unbekannt bis Antwort")
   srv.flush()
   eq(T.Net.CollectionState(500), 1, "Cache aus Antwort")
   eq(lastEvent("COLLECTION_STATUS")[1], 500, "COLLECTION_STATUS id")
   eq(lastEvent("COLLECTION_STATUS")[2], 1, "COLLECTION_STATUS state")
   eq(T.Net.QueryCollection(500), 1, "bekannter Stand wird zurueckgegeben")
   eq(countSent("GetCollectionStatus:500"), 1, "bekannt: nichts gesendet")

   -- ohne Antwort: nach 30 s ein neuer Versuch
   srv.drop.GetCollectionStatus = 5
   T.Net.QueryCollection(501)
   eq(countSent("GetCollectionStatus:501"), 1, "501 gesendet")
   advance(29)
   T.Net.QueryCollection(501)
   eq(countSent("GetCollectionStatus:501"), 1, "vor 30 s nicht wiederholt")
   advance(2)
   T.Net.QueryCollection(501)
   eq(countSent("GetCollectionStatus:501"), 2, "nach 30 s wiederholt")

   -- ungueltige IDs
   T.Net.QueryCollection(nil); T.Net.QueryCollection("x"); T.Net.QueryCollection(0); T.Net.QueryCollection(-3)
   eq(countSent("GetCollectionStatus:x"), 0, "ungueltig nicht gesendet")

   -- CollectionUpdated: Cache, new, Event
   clearLog()
   S("CollectionUpdated:600")
   eq(T.Net.CollectionState(600), 1, "Update setzt Cache")
   check(T.State.new[600], "State.new ausserhalb des Login-Sweeps")
   eq(countEvents("COLLECTION_UPDATED"), 1, "COLLECTION_UPDATED")
   -- Login-Sweep: Event immer, new nicht
   T.enteredWorldAt = now - 2
   S("CollectionUpdated:601")
   check(not T.State.new[601], "Login-Sweep: nicht neu")
   eq(countEvents("COLLECTION_UPDATED"), 2, "Event trotzdem")
   eq(T.Net.CollectionState(601), 1, "Cache trotzdem")
   advance(11)
   S("CollectionUpdated:602")
   check(T.State.new[602], "nach 10 s wieder neu")
   -- "gesammelt" wird nicht durch eine aeltere "0" ueberschrieben
   S("CollectionStatus:602:0")
   eq(T.Net.CollectionState(602), 1, "1 bleibt 1")
   -- Zustand 2
   S("CollectionStatus:603:2")
   eq(T.Net.CollectionState(603), 2, "nicht anwendbar")
   -- Flutschutz
   local before = #sent
   for id = 10000, 10100 do T.Net.QueryCollection(id) end
   check(#sent - before <= 30, "Flutschutz: hoechstens 30 je Sekunde (" .. (#sent - before) .. ")")
   noErrors()
end

-- ===========================================================================
-- S14: RemoveAll
-- ===========================================================================
do
   fresh("S14 remove all")
   equipSlot(0, 1001, "INVTYPE_HEAD")
   T.State.RefreshEquipment()
   S("TransmogStatus:2:0,11:4,12")
   feedList(0, { 11, 13 })
   T.State.Select(0, 13)
   local ok, why = T.State.RemoveAll()
   eq(ok, false, "ohne Transmogrifizierer abgelehnt")
   eq(why, "APPLY_REASON_VENDOR", "Grund VENDOR")
   eq(countSent("RemoveAll"), 0, "nichts gesendet")
   T.State.SetVendor(true)
   check(T.State.RemoveAll(), "RemoveAll")
   eq(lastSent(), "RemoveAll", "gesendet")
   eq(T.State.Applied(0), 0, "lokal geleert")
   eq(T.State.PendingCount(), 0, "Auswahl verworfen")
   srv.flush()
   eq(T.State.Applied(4), 0, "TransmogStatus:0 bestaetigt")
   noErrors()
end

-- ===========================================================================
-- S15: CHAT_MSG_ADDON-Filter
-- ===========================================================================
do
   fresh("S15 addon message filter")
   fireGame("CHAT_MSG_ADDON", "OtherAddon", "TransmogStatus:0", "WHISPER", "Tester")
   eq(T.Net.state, "UNKNOWN", "fremder Praefix ignoriert")
   eq(T.Net.checkSender, false, "Absenderpruefung ist standardmaessig aus (fail-open)")
   T.Net.checkSender = true
   fireGame("CHAT_MSG_ADDON", "transmog", "TransmogStatus:0", "WHISPER", "Somebody")
   eq(T.Net.state, "UNKNOWN", "fremder Absender ignoriert (checkSender)")
   fireGame("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Somebody")
   check(T.State.serverOpenAt == nil, "fremdes Open setzt serverOpenAt nicht")
   fireGame("CHAT_MSG_ADDON", "transmog", "TransmogStatus:0", "WHISPER", "Tester")
   eq(T.Net.state, "OK", "richtig")
   fresh("S15a1 sender check off")
   T.Net.checkSender = false
   fireGame("CHAT_MSG_ADDON", "transmog", "TransmogStatus:0", "WHISPER", "Somebody")
   eq(T.Net.state, "OK", "ohne checkSender zaehlt jeder Absender")
   fresh("S15a2 sender variants")
   fireGame("CHAT_MSG_ADDON", "transmog", "TransmogStatus:0", "WHISPER", nil)
   eq(T.Net.state, "OK", "Absender fehlt: angenommen")
   fresh("S15a3 group channels")
   fireGame("CHAT_MSG_ADDON", "transmog", "TransmogStatus:0", "GUILD", "Tester")
   fireGame("CHAT_MSG_ADDON", "transmog", "TransmogStatus:0", "PARTY", "Tester")
   eq(T.Net.state, "UNKNOWN", "Gruppenkanal verworfen")
   fresh("S15b merged prefix")
   fireGame("CHAT_MSG_ADDON", nil, "transmog\tTransmogStatus:0", "WHISPER", "Tester")
   eq(T.Net.state, "OK", "zusammengezogene Form in message")
   fresh("S15c merged prefix 2")
   fireGame("CHAT_MSG_ADDON", "transmog\tTransmogStatus:0", "", "WHISPER", "Tester")
   eq(T.Net.state, "OK", "zusammengezogene Form im Praefix")
   fresh("S15d tab inside payload")
   fireGame("CHAT_MSG_ADDON", "transmog", "transmog\tTransmogStatus:0", "WHISPER", "Tester")
   eq(T.Net.state, "OK", "Praefix doppelt toleriert")
   fireGame("CHAT_MSG_ADDON", "transmog", "transmog\tOpen", "WHISPER", "Tester")
   eq(countEvents("SERVER_OPEN"), 1, "SERVER_OPEN")
   check(T.State.serverOpenAt ~= nil, "serverOpenAt gesetzt")
   -- Realname mit Realm
   fresh("S15e realm")
   T.Net.checkSender = true
   fireGame("CHAT_MSG_ADDON", "transmog", "TransmogStatus:0", "WHISPER", "tester-Realm")
   eq(T.Net.state, "OK", "Name-Realm akzeptiert")
   fresh("S15f other realm name")
   T.Net.checkSender = true
   fireGame("CHAT_MSG_ADDON", "transmog", "TransmogStatus:0", "WHISPER", "Other-Tester")
   eq(T.Net.state, "UNKNOWN", "fremder Name mit Realm abgelehnt")
end

-- ===========================================================================
-- S16: synchroner Server (Wiedereintritt)
-- ===========================================================================
do
   fresh("S16 synchronous server", { mode = "sync" })
   srv.collected = { [11] = true, [12] = true, [13] = true }
   equipSlot(0, 1001, "INVTYPE_HEAD")
   equipSlot(4, 1004, "INVTYPE_CHEST")
   equipSlot(15, 1015, "INVTYPE_2HWEAPON")
   srv.valid[0] = { 11 }
   srv.valid[4] = { 12 }
   srv.valid[15] = { 13 }
   T.State.RefreshEquipment()
   T.Net.RequestLists()
   T.Net.RequestStatus()
   check(T.State.ListsReady(), "Listen fertig (synchron)")
   T.State.SetVendor(true)
   T.State.Select(0, 11); T.State.Select(4, 12); T.State.Select(15, 13)
   advance(0.3)
   local c = T.State.Cost()
   check(c.valid and c.copper == 30000, "Kosten synchron: " .. tostring(c.copper))
   check(T.State.CanApply(), "kann anwenden")
   T.State.Apply()
   check(not T.State.Busy(), "synchron sofort fertig")
   eq(lastEvent("APPLY_DONE")[1], 3, "3 ok")
   eq(T.State.Applied(15), 13, "Slot 15")
   eq(T.State.PendingCount(), 0, "keine Pending")
   -- Fehlerfall synchron
   srv.collected[11] = nil
   T.State.Select(0, 0)          -- entfernen
   T.State.Select(4, 0)
   advance(0.3)
   T.State.Apply()
   check(not T.State.Busy(), "Remove synchron fertig")
   eq(T.State.Applied(0), 0, "entfernt")
   noErrors()
end

-- ===========================================================================
-- S17: Iteminfo kommt spaeter (ITEMS_RESOLVED)
-- ===========================================================================
do
   fresh("S17 late item info")
   -- Link vorhanden, Info (noch) nicht
   equip[18] = "|cffa335ee|Hitem:7777:0:0:0:0:0:0:0:0|h[Relic]|h|r"
   T.State.RefreshEquipment()
   eq(T.State.SlotState(17), "READY", "ohne Iteminfo: READY")
   check(T.State.Equipped(17) ~= nil and T.State.Equipped(17).id == 7777, "Equipped id ohne Info")
   eq(T.State.Equipped(17).name, "Relic", "Name aus dem Link")
   check(T.State.Select(17, 5), "Auswahl moeglich (optimistisch)")
   clearLog()
   setItem(7777, "INVTYPE_RELIC", 3)
   T.Events.Fire("ITEMS_RESOLVED", 1)
   eq(T.State.SlotState(17), "NEVER", "nach ITEMS_RESOLVED: NEVER")
   eq(countEvents("EQUIPMENT_CHANGED"), 1, "EQUIPMENT_CHANGED nach Aufloesung")
   check(not T.State.HasPending(17), "Auswahl verworfen")
   eq(T.State.Equipped(17).quality, 3, "Qualitaet bekannt")
   noErrors()
end

-- ===========================================================================
-- S18: Refresh-Drosselung der Listen
-- ===========================================================================
do
   fresh("S18 refresh throttle")
   equipSlot(0, 1001, "INVTYPE_HEAD")
   T.State.Refresh()
   eq(countSent("GetAvailableTransmogs"), 1, "erstes Refresh fordert Listen")
   eq(countSent("GetTransmogStatus"), 1, "und Status")
   advance(1)               -- Entprellung der Ausruestung laeuft ab; sie hatte schon alles gesendet
   local lists = countSent("GetAvailableTransmogs")
   T.State.Refresh()
   eq(countSent("GetAvailableTransmogs"), lists, "zweites Refresh: Listen nicht erneut")
   check(countSent("GetTransmogStatus") >= 2, "Status schon")
   -- neue Sammlung => veraltet
   S("CollectionUpdated:900")
   T.State.Refresh()
   eq(countSent("GetAvailableTransmogs"), lists + 1, "nach CollectionUpdated wieder")
   T.State.Refresh()
   eq(countSent("GetAvailableTransmogs"), lists + 1, "danach wieder gedrosselt")
   advance(61)
   T.State.Refresh()
   eq(countSent("GetAvailableTransmogs"), lists + 2, "nach 60 s wieder")
   T.State.Refresh(true)
   eq(countSent("GetAvailableTransmogs"), lists + 3, "force")
   -- Fenster sichtbar + CollectionUpdated => automatisch nach 3 s
   T.UI = { Window = { IsShown = function() return true end } }
   S("CollectionUpdated:901")
   local n = countSent("GetAvailableTransmogs")
   advance(3.5)
   eq(countSent("GetAvailableTransmogs"), n + 1, "sichtbares Fenster: automatische Aktualisierung")
   noErrors()
end

-- ===========================================================================
-- S21: Erfolg fuer einen fremden Slot, HIDDEN-Anwendung, Geister-Antworten
-- ===========================================================================
do
   fresh("S21 foreign slot success")
   srv.collected = { [11] = true, [12] = true, [13] = true }
   equipSlot(0, 1001, "INVTYPE_HEAD")
   equipSlot(4, 1004, "INVTYPE_CHEST")
   equipSlot(7, 1007, "INVTYPE_FEET")
   srv.valid[0] = { 11 }
   srv.valid[4] = { 12 }
   srv.valid[7] = { 13 }
   T.State.RefreshEquipment()
   T.Net.RequestLists(); srv.flush()
   T.State.SetVendor(true)
   T.State.Select(0, 11); T.State.Select(4, 12)
   advance(0.3); srv.flush()
   check(T.State.Apply(), "Apply gestartet")
   eq(lastSent(), "Apply:0:11", "Operation 1 unterwegs")
   -- der Server meldet zusaetzlich einen Erfolg fuer Slot 7 (nicht in der Warteschlange)
   S("ApplyTransmogResult:1:7,13")
   eq(T.State.Applied(7), 13, "fremder Slot lokal uebernommen")
   eq(T.State.Busy(), true, "Operation 1 weiter unterwegs")
   eq(lastSent(), "Apply:0:11", "keine zusaetzliche Operation gesendet")
   srv.flush()                                   -- Antwort fuer Slot 0
   eq(T.State.Applied(0), 11, "Operation 1 normal beendet")
   eq(lastSent(), "Apply:4:12", "Operation 2 folgt")
   srv.flush()
   check(not T.State.Busy(), "Stapel beendet")
   eq(lastEvent("APPLY_DONE")[1], 2, "nOk = 2 (fremder Slot zaehlt nicht mit)")
   eq(lastEvent("APPLY_DONE")[2], 0, "nFail = 0")
   noErrors()

   fresh("S21b hidden apply")
   equipSlot(0, 1001, "INVTYPE_HEAD")
   equipSlot(15, 1015, "INVTYPE_2HWEAPON")
   T.State.RefreshEquipment()
   T.Net.RequestLists(); srv.flush()
   T.State.SetVendor(true)
   check(T.State.Select(0, T.HIDDEN_ID), "Kopf verbergen")
   check(not T.State.Select(15, T.HIDDEN_ID), "Waffe nicht verbergbar")
   eq(countSent("CalculateCost:"), 0, "vorab keine Kostenanfrage")
   local c = T.State.Cost()
   check(c.valid and not c.pending and c.copper == 0 and c.canPurchase, "HIDDEN ist kostenlos")
   check(T.State.CanApply(), "HIDDEN anwendbar ohne Kostenantwort")
   check(T.State.Apply(), "Apply HIDDEN")
   eq(lastSent(), "Apply:0:999999", "gesendet")
   srv.flush()
   eq(T.State.Applied(0), 999999, "verborgen angewendet")
   check(not T.State.IsInactive(0), "HIDDEN nie inaktiv")
   eq(T.State.Baseline(0), 999999, "Baseline HIDDEN")
   eq(countSent("CalculateCost:"), 0, "auch danach keine Kostenanfrage")
   noErrors()

   fresh("S21c ghost then failure")
   srv.collected = { [11] = true, [12] = true }
   equipSlot(0, 1001, "INVTYPE_HEAD")
   equipSlot(4, 1004, "INVTYPE_CHEST")
   srv.valid[0] = { 11 }
   srv.valid[4] = { 12 }
   T.State.RefreshEquipment()
   T.Net.RequestLists(); srv.flush()
   T.State.SetVendor(true)
   T.State.Select(0, 11); T.State.Select(4, 12)
   advance(0.3); srv.flush()
   check(T.State.Apply(), "Apply gestartet")
   local held1 = srv.queue                       -- Antwort fuer Slot 0 zurueckhalten
   srv.queue = {}
   advance(5.2)                                  -- Timeout: Slot 0 ist ein Geist, Slot 4 unterwegs
   eq(lastSent(), "Apply:4:12", "naechste Operation nach Timeout")
   eq(T.State.Busy(), true, "Slot 4 unterwegs")
   -- spaete Antwort fuer Slot 0 (Erfolg): Geist wird abgeraeumt, Slot 4 bleibt unterwegs
   for _, p in ipairs(held1) do S(p) end
   eq(T.State.Applied(0), 11, "Spaetantwort uebernommen")
   eq(T.State.Busy(), true, "Slot 4 weiter unterwegs")
   srv.flush()                                   -- Antwort fuer Slot 4
   check(not T.State.Busy(), "fertig")
   eq(T.State.Applied(4), 12, "Slot 4 angewendet")
   eq(lastEvent("APPLY_DONE")[1], 1, "nOk = 1 (Slot 4)")
   eq(lastEvent("APPLY_DONE")[2], 1, "nFail = 1 (Zeitueberschreitung Slot 0)")
   noErrors()
end

-- ===========================================================================
-- S19: Zufallslauf (Fuzz): Invarianten ueber viele zufaellige Ablaeufe
-- ===========================================================================
do
   local fuzzStats = { done = 0, ok = 0, fail = 0, equip = 0, listReady = 0, wanted = 0, reasons = {} }
   local seedV = 1
   local function rnd(n)
      seedV = (seedV * 16807) % 2147483647
      return (seedV % n) + 1
   end

   local function idsFor(slot, k)
      local out = {}
      for i = 1, (k % 5) + 2 do out[i] = slot * 1000 + k * 10 + i end
      return out
   end

   local function equipItem(slot, k)
      local itemId = 10000 + slot * 100 + k
      local loc = ARMOR[slot] and "INVTYPE_CHEST" or "INVTYPE_WEAPON"
      if slot == 17 and k % 3 == 0 then loc = "INVTYPE_RELIC" end
      equipSlot(slot, itemId, loc)
      local ids = idsFor(slot, k)
      if loc == "INVTYPE_RELIC" then ids = {} end
      srv.valid[slot] = ids
      for _, id in ipairs(ids) do srv.collected[id] = true end
   end

   local function unequip(slot)
      equip[slot + 1] = nil
      srv.equipped[slot] = nil
      srv.valid[slot] = {}
   end

   local function flushSome(k)
      local q = srv.queue
      local rest = {}
      for i = 1, #q do
         if i <= k then S(q[i]) else rest[#rest + 1] = q[i] end
      end
      -- waehrend S() koennen neue Eintraege entstanden sein (srv.queue ist
      -- dann ein neuer Stand): hinten anhaengen
      local added = srv.queue
      srv.queue = rest
      for i = 1, #added do
         if i > #q then srv.queue[#srv.queue + 1] = added[i] end
      end
   end

   local function invariants(step, seed)
      local St = T.State
      local pend = St.PendingSlots()
      local prev = -1
      for i = 1, #pend do
         check(pend[i] > prev, "seed " .. seed .. " step " .. step .. ": Pending aufsteigend")
         prev = pend[i]
         check(St.HasPending(pend[i]), "seed " .. seed .. ": PendingSlots/HasPending")
      end
      eq(St.PendingCount(), #pend, "seed " .. seed .. " step " .. step .. ": PendingCount")
      for i = 1, #SERVER_SLOTS do
         local slot = SERVER_SLOTS[i]
         local w, b = St.Wanted(slot), St.Baseline(slot)
         eq(St.HasPending(slot), w ~= b,
            "seed " .. seed .. " step " .. step .. " slot " .. slot .. ": HasPending == (Wanted ~= Baseline)")
         if St.HasPending(slot) then
            eq(St.SlotState(slot), "READY", "seed " .. seed .. " slot " .. slot .. ": Pending nur bei READY")
            if w ~= 0 and w ~= 999999 and St.List(slot).ready then
               check(St.IsAvailable(slot, w), "seed " .. seed .. " slot " .. slot .. ": Auswahl steht in fertiger Liste")
            end
         end
         local list = St.List(slot)
         check(type(list.ids) == "table" and type(list.set) == "table", "List-Form")
         eq(#list.ids, list.received, "seed " .. seed .. " slot " .. slot .. ": received == #ids")
      end
      local c = St.Cost()
      check(type(c.copper) == "number" and type(c.canPurchase) == "boolean"
         and type(c.valid) == "boolean" and type(c.pending) == "boolean", "Cost-Form")
   end

   local function settle(seed)
      srv.drop = {}
      for _ = 1, 30 do
         srv.flush()
         advance(1)
      end
      T.State.Refresh(true)
      for _ = 1, 12 do
         srv.flush()
         advance(1)
      end
      local St = T.State
      eq(St.Busy(), false, "seed " .. seed .. ": nach Ruhe nicht busy")
      check(St.ListsReady(), "seed " .. seed .. ": alle Listen fertig")
      for i = 1, #SERVER_SLOTS do
         local slot = SERVER_SLOTS[i]
         local stored = srv.stored[slot] or 0
         eq(St.Applied(slot), stored, "seed " .. seed .. " slot " .. slot .. ": Applied == Server")
         local inactive = false
         if stored ~= 0 and stored ~= 999999 then
            inactive = true
            for _, v in ipairs(srv.valid[slot] or {}) do
               if v == stored then inactive = false end
            end
         end
         eq(St.IsInactive(slot), inactive, "seed " .. seed .. " slot " .. slot .. ": IsInactive")
         eq(St.Baseline(slot), inactive and 0 or stored, "seed " .. seed .. " slot " .. slot .. ": Baseline")
      end
      local c = St.Cost()
      eq(c.pending, false, "seed " .. seed .. ": Kosten nicht ausstehend")
      local paid = 0
      for _, slot in ipairs(St.PendingSlots()) do
         local w = St.Wanted(slot)
         if w ~= 0 and w ~= 999999 then paid = paid + 1 end
      end
      if paid == 0 then
         check(c.valid and c.copper == 0, "seed " .. seed .. ": ohne bezahlte Slots 0/gueltig")
      elseif c.valid then
         eq(c.copper, paid * srv.price, "seed " .. seed .. ": Kosten = Anzahl x Preis")
      end
      noErrors("seed " .. seed)
   end

   for seed = 1, 40 do
      local mode = (seed % 5 == 0) and "sync" or "queue"
      seedV = seed * 7919
      fresh("S19 fuzz " .. seed, { mode = mode })
      for i = 1, #SERVER_SLOTS do
         if rnd(10) <= 7 then equipItem(SERVER_SLOTS[i], rnd(40)) end
      end
      T.State.RefreshEquipment()
      T.State.SetVendor(true)
      T.State.Refresh(true)
      srv.flush()
      for step = 1, 260 do
         local r = rnd(100)
         local slot = SERVER_SLOTS[rnd(#SERVER_SLOTS)]
         local St = T.State
         if r <= 4 then
            if rnd(10) <= 7 then equipItem(slot, rnd(40)) else unequip(slot) end
            fireGame("PLAYER_EQUIPMENT_CHANGED", slot + 1, equip[slot + 1] == nil)
         elseif r <= 30 then
            local list = St.List(slot)
            local pick = rnd(10)
            local id
            if pick <= 5 and #list.ids > 0 then id = list.ids[rnd(#list.ids)]
            elseif pick <= 6 then id = 999999
            elseif pick <= 7 then id = 0
            elseif pick <= 8 then id = rnd(99999)
            elseif #(srv.valid[slot] or {}) > 0 then id = srv.valid[slot][rnd(#srv.valid[slot])]
            else id = 0 end
            local ok = St.Select(slot, id)
            if ok and not St.HasPending(slot) then
               eq(St.Wanted(slot), St.Baseline(slot), "Select == Baseline entfernt Auswahl")
            end
            if ok and St.HasPending(slot) then
               eq(St.Wanted(slot), id, "Select uebernimmt id")
            end
         elseif r <= 33 then
            St.Discard(slot)
         elseif r <= 34 then
            St.DiscardAll()
         elseif r <= 38 then
            St.Toggle(slot)
         elseif r <= 41 then
            local map = {}
            for _ = 1, rnd(5) do
               local sl = SERVER_SLOTS[rnd(#SERVER_SLOTS)]
               local list = St.List(sl)
               if #list.ids > 0 and rnd(3) > 1 then map[sl] = list.ids[rnd(#list.ids)]
               else map[sl] = (rnd(2) == 1) and 999999 or 0 end
            end
            St.SetMany(map)
         elseif r <= 54 then
            if rnd(10) <= 7 then       -- der Spieler wartet kurz, bis die Kosten da sind
               advance(0.3)
               srv.flush()
            end
            local started, why = St.Apply()
            local key = started and "STARTED" or tostring(why)
            fuzzStats.reasons[key] = (fuzzStats.reasons[key] or 0) + 1
         elseif r <= 76 then
            flushSome(rnd(6))
         elseif r <= 90 then
            advance(rnd(30) / 10 + 0.05)
         elseif r <= 92 then
            St.Refresh(false)
         elseif r <= 93 then
            St.Refresh(true)
         elseif r <= 95 then
            local ids = srv.valid[slot]
            if srv.equipped[slot] and ids and #ids > 0 and srv.valid[slot][1] ~= nil then
               local newId = 50000 + rnd(9000)
               if not srv.collected[newId] then
                  srv.collected[newId] = true
                  ids[#ids + 1] = newId
                  srv.emit("CollectionUpdated:" .. newId)
               end
            end
         elseif r <= 97 then
            money = rnd(5) * 10000
            srv.money = money
            fireGame("PLAYER_MONEY")
         elseif r <= 98 then
            -- der Server verschluckt die naechste Antwort eines Befehls
            local names = { "Apply", "Apply", "CalculateCost", "GetTransmogStatus", "GetAvailableTransmogs" }
            local which = names[rnd(#names)]
            srv.drop[which] = (srv.drop[which] or 0) + 1
         elseif r <= 99 then
            St.RemoveAll()
         else
            T.Net.RequestStatus()
         end
         invariants(step, seed)
      end
      -- Statistik: der Lauf soll die Pfade auch wirklich beruehren
      for _, e in ipairs(eventsOf("APPLY_DONE")) do
         fuzzStats.done = fuzzStats.done + 1
         fuzzStats.ok = fuzzStats.ok + e[1]
         fuzzStats.fail = fuzzStats.fail + e[2]
      end
      fuzzStats.equip = fuzzStats.equip + countEvents("EQUIPMENT_CHANGED")
      fuzzStats.listReady = fuzzStats.listReady + countEvents("LIST_READY")
      fuzzStats.wanted = fuzzStats.wanted + countEvents("WANTED_CHANGED")
      settle(seed)
   end
   print(string.format("  Fuzz: %d Stapel, %d ok, %d fehlgeschlagen, %d Ausruestungswechsel, "
      .. "%d LIST_READY, %d WANTED_CHANGED", fuzzStats.done, fuzzStats.ok, fuzzStats.fail,
      fuzzStats.equip, fuzzStats.listReady, fuzzStats.wanted))
   for k, v in pairs(fuzzStats.reasons) do print("    Apply -> " .. k .. ": " .. v) end
   check(fuzzStats.done > 50 and fuzzStats.ok > 100, "Fuzz hat Anwenden wirklich ausgeloest")
   check(fuzzStats.fail > 0, "Fuzz hat Fehlschlaege/Zeitueberschreitungen erzeugt")
end

-- ===========================================================================
-- S20: echte Items-Attrappe: Iteminfo-Weg ueber Core/Items.lua
-- ===========================================================================
do
   fresh("S20 real Items module")
   -- das echte Items-Modul (nutzt GetItemInfo/Scan-Tooltip der Attrappe)
   _G.GetAuctionItemClasses = nil
   _G.GetAuctionItemSubClasses = nil
   dofile(scriptDir .. "/Core/Items.lua")
   check(T.Items ~= nil and T.Items.Get ~= nil, "Items geladen")
   T.Items.Init()
   setItem(5001, "INVTYPE_CHEST", 3)
   equip[5] = "|cff0070dd|Hitem:5001:0:0:0:0:0:0:0:0|h[Item5001]|h|r"
   setItem(5017, "INVTYPE_RELIC", 2)
   equip[18] = "|cff1eff00|Hitem:5017:0:0:0:0:0:0:0:0|h[Item5017]|h|r"
   T.State.RefreshEquipment()
   eq(T.State.SlotState(4), "READY", "Brust READY")
   eq(T.State.SlotState(17), "NEVER", "Relikt NEVER (echtes Items)")
   local eqp = T.State.Equipped(4)
   check(eqp ~= nil and eqp.id == 5001, "Equipped id")
   eq(eqp.equipLoc, "INVTYPE_CHEST", "equipLoc aus echter Items.Info")
   eq(eqp.quality, 3, "quality")
   check(not T.State.Select(17, 12), "NEVER nicht waehlbar")
   noErrors()
end

-- ===========================================================================
-- Abschluss
-- ===========================================================================
print(string.format("%d Pruefungen, %d Fehler", checks, failures))
if failures > 0 then os.exit(1) end
print("OK")
