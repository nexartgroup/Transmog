-- tests/test_netstate.lua
-- ---------------------------------------------------------------------------
-- Unabhaengige Pruefung von Core\Net.lua (Protokoll) und Core\State.lua (Modell).
--
-- Geprueft wird das VERHALTEN aus SPEC 2 / 5.7 / 5.8 und aus dem Servercode
-- (TransmogAddonProtocol.cpp), nicht die Implementierung:
--   * Parser gegen die woertlichen Serverformate (Open, TransmogStatus,
--     AvailableTransmogs start/Chunk/end, ApplyTransmogResult, TransmogCost,
--     CollectionUpdated, CollectionStatus), verstuemmelte und fremde Eingaben
--   * Net.state (UNKNOWN/OK/ABSENT) mit Spielzeit, Sammlungsabfragen
--   * State: Ausruestung, Status, Listen (Stroeme), Applied/Baseline/Inactive/
--     Wanted/Pending, Select/Toggle/SetMany, Kosten (FIFO-Zaehler), CanApply,
--     Apply-Ablauf (Fehlschlag, Zeitueberschreitung, Spaetantworten), RemoveAll,
--     Login-Sweep, Refresh-Logik
--   * Robustheit: zufaelliger Muell darf nie werfen, keine Handlerfehler,
--     keine liegengebliebenen Timer
--
-- Ein kleiner Server-Nachbau (newServer) bildet die Handler des C++-Moduls ab.
-- Aufruf:  cd <Addon>;  luajit tests/run.lua netstate
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   -- -----------------------------------------------------------------------
   -- Konstanten
   -- -----------------------------------------------------------------------

   local HEAD, SHOULDER, SHIRT, CHEST, WAIST, LEGS, FEET, WRIST, HANDS = 0, 2, 3, 4, 5, 6, 7, 8, 9
   local BACK, MAINHAND, OFFHAND, RANGED, TABARD = 14, 15, 16, 17, 18
   local SERVER_SLOTS = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }
   local HIDEABLE = {
      [0] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
      [7] = true, [8] = true, [9] = true, [14] = true, [18] = true,
   }
   local HIDDEN = 999999

   local WATCHED = {
      "LOCALE_CHANGED", "SETTINGS_CHANGED", "ITEMS_RESOLVED", "STATUS_CHANGED",
      "LIST_PROGRESS", "LIST_READY", "EQUIPMENT_CHANGED", "WANTED_CHANGED", "COST_CHANGED",
      "APPLY_STARTED", "APPLY_PROGRESS", "APPLY_DONE", "COLLECTION_UPDATED",
      "COLLECTION_STATUS", "SERVER_OPEN", "SERVER_STATE", "VENDOR_CHANGED",
   }

   -- -----------------------------------------------------------------------
   -- Zustand je Test
   -- -----------------------------------------------------------------------

   local T, Net, State
   local log = {}            -- Ereignisprotokoll { name=, n=, [1..n]=Argumente }
   local srv = nil           -- Server-Nachbau (optional)

   local function clearLog()
      for i = #log, 1, -1 do log[i] = nil end
   end

   local function evList(name)
      local out = {}
      for _, e in ipairs(log) do
         if e.name == name then out[#out + 1] = e end
      end
      return out
   end

   local function evCount(name)
      return #evList(name)
   end

   local function evLast(name)
      local l = evList(name)
      return l[#l]
   end

   -- Namen aller protokollierten Ereignisse in Reihenfolge (nur die genannten, sonst alle)
   local function evNames(only)
      local out = {}
      for _, e in ipairs(log) do
         if not only or only[e.name] then out[#out + 1] = e.name end
      end
      return out
   end

   local function hookEvents()
      for _, name in ipairs(WATCHED) do
         T.Events.On(name, function(...)
            log[#log + 1] = { name = name, n = select("#", ...), ... }
         end, log)
      end
   end

   -- -----------------------------------------------------------------------
   -- Testgegenstaende
   -- -----------------------------------------------------------------------

   local function buildItems()
      local items = {}
      local function add(id, name, quality, loc, class, sub)
         items[id] = {
            name = name, quality = quality, equipLoc = loc, class = class, subclass = sub,
            icon = "Interface\\Icons\\INV_Test_" .. id, ilvl = 100 + id % 50,
         }
      end
      add(101, "Plate Helm", 4, "INVTYPE_HEAD", "Armor", "Plate")
      add(102, "Plate Pauldrons", 3, "INVTYPE_SHOULDER", "Armor", "Plate")
      add(103, "Cotton Shirt", 1, "INVTYPE_BODY", "Armor", "Miscellaneous")
      add(104, "Plate Breastplate", 4, "INVTYPE_CHEST", "Armor", "Plate")
      add(106, "Plate Greaves", 3, "INVTYPE_LEGS", "Armor", "Plate")
      add(109, "Plate Helm II", 4, "INVTYPE_HEAD", "Armor", "Plate")
      add(114, "Cloth Cloak", 2, "INVTYPE_CLOAK", "Armor", "Cloth")
      add(115, "Old Mace", 4, "INVTYPE_WEAPON", "Weapon", "One-Handed Maces")
      add(116, "Kite Shield", 3, "INVTYPE_SHIELD", "Armor", "Shields")
      add(117, "Short Bow", 3, "INVTYPE_RANGED", "Weapon", "Bows")
      add(118, "Idol of Testing", 3, "INVTYPE_RELIC", "Armor", "Idols")
      for id = 200, 340 do
         add(id, "Look " .. id, id % 6, "INVTYPE_HEAD", "Armor", "Plate")
      end
      return items
   end

   -- Standardausruestung: Kopf, Schulter, Brust, Beine, Ruecken, Haupthand,
   -- Nebenhand, Fernkampf (Hemd, Taille, Fuesse, Handgelenke, Haende, Wappenrock leer)
   local function defaultEquip()
      return { [0] = 101, [2] = 102, [4] = 104, [6] = 106, [14] = 114, [15] = 115, [16] = 116, [17] = 117 }
   end

   -- -----------------------------------------------------------------------
   -- Nachrichten und Server-Nachbau
   -- -----------------------------------------------------------------------

   local function range(a, b)
      local t = {}
      for i = a, b do t[#t + 1] = i end
      return t
   end

   -- Stromnachrichten genau wie SendAvailableForSlot (Chunks zu 20)
   local function listMsgs(slot, ids, bucket)
      local out = {}
      local header = "AvailableTransmogs:" .. slot .. ":" .. (bucket or 0) .. ":" .. #ids .. ":"
      out[#out + 1] = header .. "start"
      local i = 1
      while i <= #ids do
         local j = math.min(i + 19, #ids)
         local parts = {}
         for k = i, j do parts[#parts + 1] = tostring(ids[k]) end
         out[#out + 1] = header .. table.concat(parts, ":")
         i = j + 1
      end
      out[#out + 1] = header .. "end"
      return out
   end

   -- Statusnachricht genau wie SendStatus (aufsteigende Slots, nur ~= 0)
   local function statusMsg(map)
      local parts, n = {}, 0
      for slot = 0, 18 do
         local fake = map[slot]
         if fake and fake ~= 0 then
            parts[#parts + 1] = ":" .. slot .. "," .. fake
            n = n + 1
         end
      end
      if n == 0 then return "TransmogStatus:0" end
      return "TransmogStatus:" .. n .. table.concat(parts)
   end

   local function deliver(list)
      for _, m in ipairs(list) do M.ServerMessage(m) end
   end

   local function setList(slot, ids, bucket)
      deliver(listMsgs(slot, ids, bucket))
   end

   local function sent()
      return M.SentCommands()
   end

   local function clearSent()
      M.ClearSent()
      if srv then srv.seen = 0 end
   end

   -- Wie oft wurde ein Befehl mit diesem Anfang gesendet?
   local function countSent(prefix)
      return M.CountSent(prefix)
   end

   local function newServer()
      local s = {
         stored = {}, valid = {}, bucket = {}, price = 5000, money = 1000000000,
         collected = {}, never = {}, hold = false, held = {}, drop = {}, lost = {},
         log = {}, seen = 0,
         equipped = setmetatable({}, { __index = function() return true end }),
      }

      local function emit(text)
         if s.hold then
            s.held[#s.held + 1] = text
         else
            M.ServerMessage(text)
         end
      end

      function s.handle(text)
         s.log[#s.log + 1] = text
         local colon = string.find(text, ":", 1, true)
         local cmd = colon and string.sub(text, 1, colon - 1) or text
         local args = colon and string.sub(text, colon + 1) or ""

         local function reply(msg)
            if s.drop[cmd] and s.drop[cmd] > 0 then
               s.drop[cmd] = s.drop[cmd] - 1
               s.lost[#s.lost + 1] = msg
               return
            end
            emit(msg)
         end

         if cmd == "GetTransmogStatus" then
            reply(statusMsg(s.stored))
         elseif cmd == "GetAvailableTransmogs" then
            for _, slot in ipairs(SERVER_SLOTS) do
               for _, m in ipairs(listMsgs(slot, s.valid[slot] or {}, s.bucket[slot] or 0)) do
                  reply(m)
               end
            end
         elseif cmd == "GetCollectionStatus" then
            local id = tonumber(string.match(args, "^(%d+)$"))
            if not id or id == 0 then return end
            local state = 0
            if s.never[id] then state = 2 elseif s.collected[id] then state = 1 end
            reply("CollectionStatus:" .. id .. ":" .. state)
         elseif cmd == "Apply" then
            local a, b = string.match(args, "^(%d+):(%d+)$")
            local slot, id = tonumber(a), tonumber(b)
            if not slot or not id or slot >= 19 or id == 0 then
               reply("ApplyTransmogResult:0")
               return
            end
            local ok = false
            if s.stored[slot] == id then
               ok = true
            elseif s.equipped[slot] == false then
               ok = false
            elseif id == HIDDEN then
               ok = HIDEABLE[slot] == true
            else
               local found = false
               for _, v in ipairs(s.valid[slot] or {}) do
                  if v == id then found = true end
               end
               local price = s.priceFn and s.priceFn(id) or s.price
               if found and s.money >= price then
                  s.money = s.money - price
                  ok = true
               end
            end
            if ok then
               s.stored[slot] = id
               reply("ApplyTransmogResult:1:" .. slot .. "," .. id)
            else
               reply("ApplyTransmogResult:0")
            end
         elseif cmd == "Remove" then
            local slot = tonumber(string.match(args, "^(%d+)$"))
            if not slot or slot >= 19 then
               reply("ApplyTransmogResult:0")
               return
            end
            s.stored[slot] = nil
            reply("ApplyTransmogResult:1:" .. slot .. ",0")
         elseif cmd == "RemoveAll" then
            s.stored = {}
            reply(statusMsg(s.stored))
         elseif cmd == "CalculateCost" then
            local total = 0
            for pair in string.gmatch(args, "[^,]+") do
               local a, b = string.match(pair, "^(%d+):(%d+)$")
               local slot, id = tonumber(a), tonumber(b)
               if slot and id and slot < 19 and id ~= 0 then
                  if id ~= HIDDEN then total = total + (s.priceFn and s.priceFn(id) or s.price) end
               end
            end
            reply("TransmogCost:" .. total .. ":" .. (s.money >= total and 1 or 0))
         end
      end

      -- Verarbeitet alle seit dem letzten Aufruf gesendeten Befehle (auch Folgebefehle)
      function s.pump()
         if s.seen > #M.sentAddon then s.seen = 0 end
         while s.seen < #M.sentAddon do
            s.seen = s.seen + 1
            local c = M.sentAddon[s.seen]
            if c.prefix == "transmog" then s.handle(c.msg) end
         end
      end

      -- Zurueckgehaltene Antworten ausliefern
      function s.flush()
         local q = s.held
         s.held = {}
         for _, m in ipairs(q) do M.ServerMessage(m) end
      end

      return s
   end

   -- -----------------------------------------------------------------------
   -- Start eines Tests
   -- -----------------------------------------------------------------------

   -- opts.equip   Tabelle [Server-Slot] = itemId (Standard: defaultEquip)
   -- opts.alive   false = dem Addon keine Serverantwort vorspielen (Net.state bleibt UNKNOWN)
   -- opts.server  true = Server-Nachbau anlegen (srv)
   -- opts.vendor  true = State.SetVendor(true)
   -- opts.noSeed  true = echte Vorgabe seit 2.1 (Neuinstallation: "Anwenden auch ohne Transmogrifizierer" an);
   --              ohne: H.boot belegt TransmogGlobalDB mit allowAnywhere = false (Vorschau-Modus ausserhalb des NPCs)
   local function start(opts)
      opts = opts or {}
      local equip = opts.equip
      if equip == nil then equip = defaultEquip() end
      local world = { equipment = {} }
      for slot, id in pairs(equip) do world.equipment[slot + 1] = id end
      T = H.boot({ items = buildItems(), world = world, noSeed = opts.noSeed })
      Net, State = T.Net, T.State
      T.DB.Init()
      T.Slots.Init()
      T.Items.Init()
      Net.Init()
      State.Init()
      T.enteredWorldAt = GetTime() - 1000          -- kein Login-Sweep
      State.chatMessages = true                    -- (eine UI darf es ausschalten; die Tests pruefen den Chat)
      srv = nil
      clearLog()
      hookEvents()
      if opts.alive ~= false then
         M.ServerMessage("TransmogStatus:0")
      end
      M.Advance(1.0)                               -- Ausruestungsabfrage (0,5 s) ablaufen lassen
      M.ClearSent()
      if opts.server then srv = newServer() end
      if opts.vendor then State.SetVendor(true) end
      clearLog()
      return T
   end

   -- Setzt die Liste und Applied-Werte eines Slots ueber echte Servernachrichten
   local function setApplied(map)
      M.ServerMessage(statusMsg(map))
   end

   -- Listen je Slot fertig melden: map[slot] = Array von IDs
   local function ready(map)
      for slot, ids in pairs(map) do setList(slot, ids) end
   end

   -- Wartet die Kostenentprellung ab und beantwortet die Anfrage (falls eine ging)
   local function settleCost(copper, can)
      M.Advance(0.3)
      local cmds = sent()
      local last = cmds[#cmds]
      if last and string.sub(last, 1, 13) == "CalculateCost" then
         M.ServerMessage("TransmogCost:" .. copper .. ":" .. (can and 1 or 0))
      end
   end

   -- -----------------------------------------------------------------------
   -- Stubs fuer reine Parser-Tests
   -- -----------------------------------------------------------------------

   local calls
   local STATE_FUNCS = {
      "OnOpen", "OnStatus", "OnListStart", "OnListChunk", "OnListEnd", "OnCost",
      "OnApplyResult", "OnCollectionUpdated", "OnCollectionStatus",
   }

   local function stubState()
      calls = {}
      for _, name in ipairs(STATE_FUNCS) do
         T.State[name] = function(...)
            calls[#calls + 1] = { name = name, n = select("#", ...), ... }
         end
      end
   end

   local function parse(message)
      calls = {}
      local res = Net.Handle(message)
      return res, calls
   end

   -- =======================================================================
   H.section("Net: Senden")
   -- =======================================================================

   H.test("Net.Send: Praefix, Kanal WHISPER, Ziel = Spielername, Befehl[:Argument]", function()
      start({ equip = {}, alive = false })
      H.eq(Net.Send("GetTransmogStatus"), true)
      H.eq(Net.Send("Apply", "4:555"), true)
      H.eq(Net.Send("Foo", 0), true)
      H.eq(#M.sentAddon, 3)
      H.deepEq(M.sentAddon[1], { prefix = "transmog", msg = "GetTransmogStatus", channel = "WHISPER", target = "Testplayer" })
      H.eq(M.sentAddon[2].msg, "Apply:4:555")
      H.eq(M.sentAddon[3].msg, "Foo:0")
      H.eq(M.sentAddon[2].channel, "WHISPER")
      H.eq(M.sentAddon[2].target, M.world.playerName)
   end)

   H.test("Net.Send: ungueltige Befehle, zu lange Nachricht und fehlender Spielername werfen nie", function()
      start({ equip = {}, alive = false })
      H.eq(Net.Send(nil), false)
      H.eq(Net.Send(""), false)
      H.eq(Net.Send(5), false)
      H.eq(Net.Send({}), false)
      H.eq(#M.sentAddon, 0)
      -- Grenze von SendAddonMessage: Praefix ("transmog" = 8) + Text <= 254 Zeichen
      H.eq(Net.Send("X", string.rep("1", 300)), false)
      H.eq(#M.sentAddon, 0)
      local fits = string.rep("a", 254 - #"transmog")
      H.eq(Net.Send(fits), true)
      H.eq(#M.sentAddon, 1)
      H.eq(Net.Send(fits .. "a"), false)
      H.eq(#M.sentAddon, 1)
      M.world.playerName = ""
      H.eq(Net.Send("GetTransmogStatus"), false)
      H.eq(#M.sentAddon, 1)
   end)

   H.test("Net.Send: wirft SendAddonMessage selbst, kommt false zurueck (kein Fehler, kein Zaehler)", function()
      start({ equip = {}, alive = false })
      local orig = _G.SendAddonMessage
      _G.SendAddonMessage = function() error("kaputt") end
      local before = Net.sentCount
      H.eq(Net.Send("GetTransmogStatus"), false)
      H.eq(Net.RequestStatus(), false)
      H.eq(Net.sentCount, before)
      _G.SendAddonMessage = orig
      H.eq(Net.Send("GetTransmogStatus"), true)
      H.eq(Net.sentCount, before + 1)
   end)

   H.test("Net: typisierte Sender erzeugen exakt die Befehle des Protokolls", function()
      start({ equip = {}, alive = false })
      Net.RequestStatus()
      Net.RequestLists()
      Net.RequestCost({ { 0, 123 }, { 2, 456 }, { 14, HIDDEN } })
      Net.SendApply(4, 555)
      Net.SendApply("15", "777")
      Net.SendRemove(0)
      Net.SendRemove(18)
      Net.SendRemoveAll()
      H.deepEq(sent(), {
         "GetTransmogStatus",
         "GetAvailableTransmogs",
         "CalculateCost:0:123,2:456,14:999999",
         "Apply:4:555",
         "Apply:15:777",
         "Remove:0",
         "Remove:18",
         "RemoveAll",
      })
   end)

   H.test("Net: ungueltige Argumente der Sender senden nichts", function()
      start({ equip = {}, alive = false })
      H.eq(Net.SendApply(4, 0), false)
      H.eq(Net.SendApply(-1, 5), false)
      H.eq(Net.SendApply(19, 5), false)
      H.eq(Net.SendApply(nil, 5), false)
      H.eq(Net.SendApply(4, nil), false)
      H.eq(Net.SendApply(4.5, 5), false)
      H.eq(Net.SendApply("x", 5), false)
      H.eq(Net.SendRemove(-1), false)
      H.eq(Net.SendRemove(19), false)
      H.eq(Net.SendRemove(nil), false)
      H.eq(Net.SendRemove("abc"), false)
      H.eq(Net.RequestCost(nil), false)
      H.eq(Net.RequestCost("x"), false)
      H.eq(Net.RequestCost({}), false)
      H.eq(Net.RequestCost({ { 0, 0 }, { 99, 5 }, { "x", 5 }, { 4 }, "junk", {} }), false)
      H.eq(#M.sentAddon, 0)
      -- gemischt: nur die gueltigen Paare gehen hinaus
      H.eq(Net.RequestCost({ { 0, 123 }, { 2, 0 }, { 99, 5 }, { 4, "7" }, "junk" }), true)
      H.deepEq(sent(), { "CalculateCost:0:123,4:7" })
   end)

   H.test("Net.Init: RegisterAddonMessagePrefix nur mit Guard, mehrfaches Init ist harmlos", function()
      -- ohne die Funktion (Standard der Attrappe in 3.3.5a)
      start({ equip = {}, alive = false })
      Net.Init()
      Net.Init()
      H.eq(rawget(_G, "RegisterAddonMessagePrefix"), nil)
      -- genau EIN Handler: eine Nachricht erzeugt genau EIN Ereignis
      M.ServerMessage("Open")
      H.eq(evCount("SERVER_OPEN"), 1)
      -- mit der Funktion (Client mit Praefix-Registrierung)
      H.boot({ world = { hasRegisterAddonMessagePrefix = true } })
      local T2 = rawget(_G, "Transmog")
      T2.Net.Init()
      T2.Net.Init()
      H.eq(M.registeredPrefixes["transmog"], true)
   end)

   -- =======================================================================
   H.section("Net: Parser (woertliche Serverformate)")
   -- =======================================================================

   H.test("Parser: Open", function()
      start({ equip = {}, alive = false })
      stubState()
      local res, c = parse("Open")
      H.eq(res, true)
      H.deepEq(c, { { name = "OnOpen", n = 0 } })
      -- ueber den echten Weg (CHAT_MSG_ADDON)
      M.ServerMessage("Open")
      H.eq(#calls, 2)
      H.eq(calls[2].name, "OnOpen")
   end)

   H.test("Parser: TransmogStatus (leer, mehrere Slots, HIDDEN, Rauschen)", function()
      start({ equip = {}, alive = false })
      stubState()
      local _, c = parse("TransmogStatus:0")
      H.deepEq(c, { { name = "OnStatus", n = 1, {} } })

      _, c = parse("TransmogStatus:3:0,100:4,200:14,999999")
      H.eq(#c, 1)
      H.deepEq(c[1][1], { [0] = 100, [4] = 200, [14] = 999999 })

      -- fakeEntry 0 wird verworfen (der Server sendet nie welche), Muell-Eintraege auch
      _, c = parse("TransmogStatus:3:0,0:4,200:junk")
      H.eq(#c, 1)
      H.deepEq(c[1][1], { [4] = 200 })

      -- Slot ausserhalb 0..18 wird verworfen
      _, c = parse("TransmogStatus:2:0,100:99,5")
      H.eq(#c, 1)
      H.deepEq(c[1][1], { [0] = 100 })

      -- derselbe Slot zweimal: der spaetere gewinnt
      _, c = parse("TransmogStatus:2:4,200:4,300")
      H.deepEq(c[1][1], { [4] = 300 })
   end)

   H.test("Parser: verstuemmelter TransmogStatus wird verworfen und aendert nichts", function()
      start({ equip = {}, alive = false })
      stubState()
      for _, m in ipairs({
         "TransmogStatus", "TransmogStatus:", "TransmogStatus:abc", "TransmogStatus:-1",
         "TransmogStatus:2", "TransmogStatus:1:junk", "TransmogStatus:1:,", "TransmogStatus:1:4",
         "TransmogStatus:1:4,", "TransmogStatus:1:,5", "TransmogStatus:1:4,x",
      }) do
         local res, c = parse(m)
         H.eq(res, false, m)
         H.eq(#c, 0, m)
      end
      H.eq(Net.state, "UNKNOWN")
   end)

   H.test("Parser: AvailableTransmogs start / Chunk / end", function()
      start({ equip = {}, alive = false })
      stubState()
      local _, c = parse("AvailableTransmogs:0:8:3:start")
      H.deepEq(c, { { name = "OnListStart", n = 3, 0, 8, 3 } })
      _, c = parse("AvailableTransmogs:0:8:3:11:22:33")
      H.deepEq(c, { { name = "OnListChunk", n = 2, 0, { 11, 22, 33 } } })
      _, c = parse("AvailableTransmogs:0:8:3:end")
      H.deepEq(c, { { name = "OnListEnd", n = 1, 0 } })

      -- leerer Slot: bucket 0, amount 0 (der Server sendet start und end)
      _, c = parse("AvailableTransmogs:17:0:0:start")
      H.deepEq(c, { { name = "OnListStart", n = 3, 17, 0, 0 } })
      _, c = parse("AvailableTransmogs:17:0:0:end")
      H.deepEq(c, { { name = "OnListEnd", n = 1, 17 } })

      -- ein Chunk mit 20 IDs (Maximum des Servers)
      local ids = range(1001, 1020)
      _, c = parse("AvailableTransmogs:4:8:40:" .. table.concat(ids, ":"))
      H.eq(#c, 1)
      H.deepEq(c[1][2], ids)

      -- Duplikate im Chunk und Nullen/Muell werden verworfen, Reihenfolge bleibt
      _, c = parse("AvailableTransmogs:4:8:9:5:5:6:0:-3:abc:7:6")
      H.deepEq(c[1][2], { 5, 6, 7 })
   end)

   H.test("Parser: verstuemmelte AvailableTransmogs werden verworfen", function()
      start({ equip = {}, alive = false })
      stubState()
      for _, m in ipairs({
         "AvailableTransmogs", "AvailableTransmogs:", "AvailableTransmogs:0",
         "AvailableTransmogs:0:8:3", "AvailableTransmogs:0:8:3:", "AvailableTransmogs:0:8:3:abc",
         "AvailableTransmogs:19:0:0:start", "AvailableTransmogs:x:0:0:start",
         "AvailableTransmogs:-1:0:0:start", "AvailableTransmogs:0:8:3:0",
         "AvailableTransmogs:99:8:3:5:6", "AvailableTransmogs:0:8:3:0:0:0",
      }) do
         local res, c = parse(m)
         H.eq(res, false, m)
         H.eq(#c, 0, m)
      end
      H.eq(Net.state, "UNKNOWN")
   end)

   H.test("Parser: ApplyTransmogResult (Fehlschlag ohne Slot, Erfolg mit slot,itemId)", function()
      start({ equip = {}, alive = false })
      stubState()
      local _, c = parse("ApplyTransmogResult:0")
      H.deepEq(c, { { name = "OnApplyResult", n = 3, false } })

      _, c = parse("ApplyTransmogResult:1:4,555")
      H.deepEq(c, { { name = "OnApplyResult", n = 3, true, 4, 555 } })

      -- Remove: itemId 0
      _, c = parse("ApplyTransmogResult:1:4,0")
      H.deepEq(c, { { name = "OnApplyResult", n = 3, true, 4, 0 } })

      -- Slot 0 (Kopf) ist gueltig
      _, c = parse("ApplyTransmogResult:1:0,100")
      H.deepEq(c, { { name = "OnApplyResult", n = 3, true, 0, 100 } })

      -- Erfolg ohne lesbare Angabe: ohne slot/id weiterreichen (FIFO in State)
      _, c = parse("ApplyTransmogResult:1")
      H.deepEq(c, { { name = "OnApplyResult", n = 3, true } })
      _, c = parse("ApplyTransmogResult:1:junk")
      H.deepEq(c, { { name = "OnApplyResult", n = 3, true } })
      _, c = parse("ApplyTransmogResult:1:99,5")
      H.deepEq(c, { { name = "OnApplyResult", n = 3, true } })

      for _, m in ipairs({ "ApplyTransmogResult", "ApplyTransmogResult:", "ApplyTransmogResult:2",
         "ApplyTransmogResult:x", "ApplyTransmogResult:-1:4,5" }) do
         local res, c2 = parse(m)
         H.eq(res, false, m)
         H.eq(#c2, 0, m)
      end
   end)

   H.test("Parser: TransmogCost", function()
      start({ equip = {}, alive = false })
      stubState()
      local _, c = parse("TransmogCost:12345:1")
      H.deepEq(c, { { name = "OnCost", n = 2, 12345, true } })
      _, c = parse("TransmogCost:0:0")
      H.deepEq(c, { { name = "OnCost", n = 2, 0, false } })
      -- Kupfer in der Groessenordnung eines 32-Bit-Werts
      _, c = parse("TransmogCost:4000000000:1")
      H.deepEq(c, { { name = "OnCost", n = 2, 4000000000, true } })
      for _, m in ipairs({ "TransmogCost", "TransmogCost:", "TransmogCost:5", "TransmogCost:5:",
         "TransmogCost:x:1", "TransmogCost:5:x", "TransmogCost:-5:1", "TransmogCost:99999999999:1" }) do
         local res, c2 = parse(m)
         H.eq(res, false, m)
         H.eq(#c2, 0, m)
      end
   end)

   H.test("Parser: CollectionUpdated und CollectionStatus", function()
      start({ equip = {}, alive = false })
      stubState()
      local _, c = parse("CollectionUpdated:12345")
      H.deepEq(c, { { name = "OnCollectionUpdated", n = 1, 12345 } })
      _, c = parse("CollectionStatus:22345:0")
      H.deepEq(c, { { name = "OnCollectionStatus", n = 2, 22345, 0 } })
      _, c = parse("CollectionStatus:32345:1")
      H.deepEq(c, { { name = "OnCollectionStatus", n = 2, 32345, 1 } })
      _, c = parse("CollectionStatus:42345:2")
      H.deepEq(c, { { name = "OnCollectionStatus", n = 2, 42345, 2 } })
      for _, m in ipairs({ "CollectionUpdated", "CollectionUpdated:", "CollectionUpdated:0",
         "CollectionUpdated:x", "CollectionUpdated:-4", "CollectionStatus", "CollectionStatus:5",
         "CollectionStatus:5:3", "CollectionStatus:0:1", "CollectionStatus:x:1", "CollectionStatus:5:x" }) do
         local res, c2 = parse(m)
         H.eq(res, false, m)
         H.eq(#c2, 0, m)
      end
   end)

   H.test("Parser: unbekannte Befehle, Echo der eigenen Befehle und Fremdtext", function()
      start({ equip = {}, alive = false })
      stubState()
      for _, m in ipairs({
         "", ":", "::", "Foo", "foo:bar", "open", "OPEN", "GetTransmogStatus", "GetAvailableTransmogs",
         "GetCollectionStatus:5", "Apply:4:555", "Remove:4", "RemoveAll", "CalculateCost:0:5",
         "NewTransmog:123", "TransmogStatusX:0", " TransmogStatus:0", "transmogstatus:0",
         "ApplyTransmogResult", "__index", "Handle", "ToUInt",
      }) do
         local res, c = parse(m)
         H.eq(res, false, "'" .. m .. "'")
         H.eq(#c, 0, "'" .. m .. "'")
      end
      H.eq(Net.state, "UNKNOWN")
      H.eq(Net.receivedCount, 0)
      -- Nicht-Strings
      for _, v in ipairs({ 5, true }) do
         H.eq(Net.Handle(v), false)
      end
      H.eq(Net.Handle(nil), false)
      H.eq(Net.Handle({}), false)
      H.eq(#calls, 0)
   end)

   H.test("Praefix: getrennt (prefix, message), zusammengezogen und fremde Praefixe", function()
      start({ equip = {}, alive = false })
      stubState()
      -- Standard: prefix == "transmog", message = Nutzdaten
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Testplayer")
      H.eq(#calls, 1)
      -- zusammengezogen im Praefix-Feld
      M.Fire("CHAT_MSG_ADDON", "transmog\tOpen", "", "WHISPER", "Testplayer")
      H.eq(#calls, 2)
      M.Fire("CHAT_MSG_ADDON", "transmog\tTransmogCost:7:1", nil, "WHISPER", "Testplayer")
      H.eq(#calls, 3)
      H.eq(calls[3].name, "OnCost")
      -- zusammengezogen im Nachrichtenfeld
      M.Fire("CHAT_MSG_ADDON", nil, "transmog\tOpen", "WHISPER", "Testplayer")
      H.eq(#calls, 4)
      M.Fire("CHAT_MSG_ADDON", "", "transmog\tOpen", "WHISPER", "Testplayer")
      H.eq(#calls, 5)
      -- Praefix mit Tab, Nutzdaten in message
      M.Fire("CHAT_MSG_ADDON", "transmog\t", "Open", "WHISPER", "Testplayer")
      H.eq(#calls, 6)
      -- Net.Handle toleriert das vorangestellte Praefix
      H.eq(Net.Handle("transmog\tOpen"), true)
      H.eq(#calls, 7)
      -- fremde Praefixe und Nicht-Strings: ignorieren
      M.Fire("CHAT_MSG_ADDON", "otheraddon", "Open", "WHISPER", "Testplayer")
      M.Fire("CHAT_MSG_ADDON", "TRANSMOG", "Open", "WHISPER", "Testplayer")
      M.Fire("CHAT_MSG_ADDON", "transmogx", "Open", "WHISPER", "Testplayer")
      M.Fire("CHAT_MSG_ADDON", "transmog", nil, "WHISPER", "Testplayer")
      M.Fire("CHAT_MSG_ADDON", "transmog", 5, "WHISPER", "Testplayer")
      M.Fire("CHAT_MSG_ADDON", nil, nil, nil, nil)
      H.eq(#calls, 7)
      H.eq(Net.state, "OK")      -- ausgeloest durch die gueltigen Nachrichten
   end)

   H.test("Net.checkSender: Standard AUS; eingeschaltet nur der Spieler selbst", function()
      start({ equip = {}, alive = false })
      stubState()
      -- Standard AUS (fail-open): auch ein anderer Absender kommt durch
      H.eq(Net.checkSender, false)
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Somebodyelse")
      H.eq(#calls, 1)
      -- eingeschaltet: ein fremder Absender wird verworfen (jeder Spieler kann
      -- SendAddonMessage("transmog", ..., "WHISPER", Ziel) senden)
      Net.checkSender = true
      for i = #calls, 1, -1 do calls[i] = nil end
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Somebodyelse")
      H.eq(#calls, 0)
      H.eq(Net.OnAddonMessage("transmog", "Open", "WHISPER", "Somebodyelse"), false)
      -- der Server fluestert dem Spieler an sich selbst
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Testplayer")
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "testplayer")
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Testplayer-Realm")
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", nil)
      H.eq(#calls, 4)
      -- wieder abgeschaltet -> auch ein fremder Absender kommt durch
      Net.checkSender = false
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Somebodyelse")
      H.eq(#calls, 5)
   end)

   H.test("Net.checkSender: vorgetaeuschte Servernachrichten fremder Spieler bleiben ohne Wirkung", function()
      start({ equip = {}, alive = false })
      Net.checkSender = true
      local id = 41011
      -- ein fremder Spieler schickt "Open", "CollectionUpdated", Kosten, Status, Liste
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Griefer")
      M.Fire("CHAT_MSG_ADDON", "transmog", "CollectionUpdated:" .. id, "WHISPER", "Griefer")
      M.Fire("CHAT_MSG_ADDON", "transmog", "TransmogCost:12345:1", "WHISPER", "Griefer")
      M.Fire("CHAT_MSG_ADDON", "transmog", "TransmogStatus:1:0,500", "WHISPER", "Griefer")
      M.Fire("CHAT_MSG_ADDON", "transmog", "AvailableTransmogs:0:0:1:start", "WHISPER", "Griefer")
      H.eq(State.serverOpenAt, nil, "ein fremdes Open darf das naechste Gossip-Fenster nicht kapern")
      H.eq(evCount("SERVER_OPEN"), 0)
      H.eq(State.new[id], nil)
      H.eq(Net.CollectionState(id), nil)
      H.eq(State.Applied(HEAD), 0)
      H.eq(evCount("COLLECTION_UPDATED"), 0)
      H.eq(Net.receivedCount, 0)
      -- dieselben Nachrichten vom Spieler selbst (= vom Server) wirken
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Testplayer")
      H.truthy(State.serverOpenAt)
      H.eq(evCount("SERVER_OPEN"), 1)
   end)

   H.test("Net.OnAddonMessage: Gruppenkanaele werden verworfen, auch mit ausgeschalteter Absenderpruefung", function()
      start({ equip = {}, alive = false })
      stubState()
      for _, ch in ipairs({ "GUILD", "PARTY", "RAID", "OFFICER", "BATTLEGROUND" }) do
         -- Absender = der Spieler selbst: nur der Kanal entscheidet
         H.eq(Net.OnAddonMessage("transmog", "Open", ch, "Testplayer"), false, ch)
         Net.checkSender = false
         H.eq(Net.OnAddonMessage("transmog", "Open", ch, "Griefer"), false, ch .. " ohne Absenderpruefung")
         Net.checkSender = true
      end
      H.eq(#calls, 0)
      H.eq(Net.receivedCount, 0)
      -- WHISPER (und ein nicht lesbarer Kanal) bleiben moeglich
      H.eq(Net.OnAddonMessage("transmog", "Open", "WHISPER", "Testplayer"), true)
      H.eq(Net.OnAddonMessage("transmog", "Open", nil, "Testplayer"), true)
      H.eq(#calls, 2)
   end)

   H.test("Net.checkSender: solange der eigene Name noch 'Unknown' ist, wird nichts verworfen", function()
      start({ equip = {}, alive = false })
      stubState()
      Net.checkSender = true
      M.world.playerName = "Unknown"
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Somebodyelse")
      H.eq(#calls, 1)
   end)

   -- =======================================================================
   H.section("Net.state")
   -- =======================================================================

   H.test("Net.state: ohne Anfrage bleibt der Zustand UNKNOWN", function()
      start({ equip = {}, alive = false })
      H.eq(Net.state, "UNKNOWN")
      M.Advance(30)
      H.eq(Net.state, "UNKNOWN")
      H.eq(evCount("SERVER_STATE"), 0)
   end)

   H.test("Net.state: 8 s nach der ersten Anfrage ohne Antwort -> ABSENT (genau einmal gemeldet)", function()
      start({ equip = {}, alive = false })
      Net.RequestStatus()
      H.eq(Net.state, "UNKNOWN")
      M.Advance(7.5)
      H.eq(Net.state, "UNKNOWN")
      M.Advance(0.7)
      H.eq(Net.state, "ABSENT")
      H.eq(evCount("SERVER_STATE"), 1)
      H.eq(evLast("SERVER_STATE")[1], "ABSENT")
      -- weitere Anfragen aendern nichts und melden nichts
      Net.RequestStatus()
      M.Advance(20)
      H.eq(Net.state, "ABSENT")
      H.eq(evCount("SERVER_STATE"), 1)
   end)

   H.test("Net.state: weitere Anfragen verlaengern die Frist nicht (8 s ab der ERSTEN)", function()
      start({ equip = {}, alive = false })
      Net.RequestStatus()
      M.Advance(6)
      Net.RequestStatus()
      Net.RequestLists()
      M.Advance(2.2)
      H.eq(Net.state, "ABSENT")
   end)

   H.test("Net.state: Antwort vor Fristende -> OK, SERVER_STATE feuert VOR dem State-Aufruf", function()
      start({ equip = {}, alive = false })
      Net.RequestStatus()
      M.Advance(3)
      local seenState
      local origOnStatus = State.OnStatus
      State.OnStatus = function(map)
         seenState = Net.state
         -- zu diesem Zeitpunkt muss das Ereignis schon gefeuert sein
         H.eq(evCount("SERVER_STATE"), 1)
         return origOnStatus(map)
      end
      M.ServerMessage("TransmogStatus:0")
      H.eq(seenState, "OK")
      H.eq(Net.state, "OK")
      H.eq(evLast("SERVER_STATE")[1], "OK")
      -- die 8-s-Frist darf nicht mehr zuschlagen
      M.Advance(20)
      H.eq(Net.state, "OK")
      H.eq(evCount("SERVER_STATE"), 1)
   end)

   H.test("Net.state: ABSENT erholt sich mit der naechsten gueltigen Antwort", function()
      start({ equip = {}, alive = false })
      Net.RequestStatus()
      M.Advance(9)
      H.eq(Net.state, "ABSENT")
      M.ServerMessage("TransmogStatus:0")
      H.eq(Net.state, "OK")
      H.deepEq(evNames({ SERVER_STATE = true }), { "SERVER_STATE", "SERVER_STATE" })
      H.eq(evList("SERVER_STATE")[1][1], "ABSENT")
      H.eq(evList("SERVER_STATE")[2][1], "OK")
   end)

   H.test("Net.state: das Echo der eigenen Befehle (Server ohne Modul) zaehlt nicht als Lebenszeichen", function()
      start({ equip = {}, alive = false })
      Net.RequestStatus()
      Net.RequestLists()
      -- ein Server ohne das Modul fluestert den Befehl zurueck
      M.ServerMessage("GetTransmogStatus")
      M.ServerMessage("GetAvailableTransmogs")
      H.eq(Net.state, "UNKNOWN")
      M.Advance(8.5)
      H.eq(Net.state, "ABSENT")
   end)

   H.test("Net.state: ungueltige Servernachricht ist kein Lebenszeichen", function()
      start({ equip = {}, alive = false })
      Net.RequestStatus()
      M.ServerMessage("TransmogStatus:abc")
      M.ServerMessage("Whatever")
      H.eq(Net.state, "UNKNOWN")
      M.Advance(8.5)
      H.eq(Net.state, "ABSENT")
   end)

   -- =======================================================================
   H.section("Net: Sammlungsabfragen")
   -- =======================================================================

   H.test("QueryCollection: nur einmal je ID gesendet, Antwort wird gecacht", function()
      start({ equip = {}, alive = false })
      H.eq(Net.QueryCollection(123), nil)
      H.deepEq(sent(), { "GetCollectionStatus:123" })
      H.eq(Net.QueryCollection(123), nil)
      H.eq(Net.QueryCollection(123), nil)
      H.eq(countSent("GetCollectionStatus"), 1)
      H.eq(Net.CollectionState(123), nil)

      M.ServerMessage("CollectionStatus:123:0")
      H.eq(Net.CollectionState(123), 0)
      H.eq(Net.QueryCollection(123), 0)
      H.eq(countSent("GetCollectionStatus"), 1)
      H.eq(evLast("COLLECTION_STATUS")[1], 123)
      H.eq(evLast("COLLECTION_STATUS")[2], 0)

      M.ServerMessage("CollectionStatus:200:1")
      M.ServerMessage("CollectionStatus:201:2")
      H.eq(Net.CollectionState(200), 1)
      H.eq(Net.CollectionState(201), 2)
      H.eq(Net.QueryCollection(200), 1)
      H.eq(Net.QueryCollection(201), 2)
      H.eq(countSent("GetCollectionStatus"), 1)
   end)

   H.test("QueryCollection: unbeantwortet -> nach 30 s erneuter Versuch", function()
      start({ equip = {}, alive = false })
      Net.QueryCollection(500)
      M.Advance(29)
      Net.QueryCollection(500)
      H.eq(countSent("GetCollectionStatus"), 1)
      M.Advance(1.5)
      Net.QueryCollection(500)
      H.eq(countSent("GetCollectionStatus"), 2)
      -- und danach wieder gedrosselt
      Net.QueryCollection(500)
      H.eq(countSent("GetCollectionStatus"), 2)
   end)

   H.test("QueryCollection: Flutschutz (30 je Sekunde) und ungueltige IDs", function()
      start({ equip = {}, alive = false })
      for id = 1, 40 do Net.QueryCollection(id) end
      H.eq(countSent("GetCollectionStatus"), 30)
      M.Advance(1.1)
      for id = 31, 40 do Net.QueryCollection(id) end
      H.eq(countSent("GetCollectionStatus"), 40)
      -- die 10 vorher abgewiesenen werden nicht doppelt gesendet
      for id = 1, 40 do Net.QueryCollection(id) end
      H.eq(countSent("GetCollectionStatus"), 40)

      clearSent()
      for _, v in ipairs({ 0, -1, 1.5, "abc", "", true }) do
         H.eq(Net.QueryCollection(v), nil)
      end
      H.eq(Net.QueryCollection(nil), nil)
      H.eq(Net.QueryCollection({}), nil)
      H.eq(#sent(), 0)
      H.eq(Net.CollectionState(nil), nil)
      H.eq(Net.CollectionState(0), nil)
      H.eq(Net.CollectionState("x"), nil)
   end)

   H.test("CollectionUpdated setzt den Cache auf 1; eine veraltete 0-Antwort nimmt es nicht zurueck", function()
      start({ equip = {}, alive = false })
      Net.QueryCollection(777)
      M.ServerMessage("CollectionUpdated:777")
      H.eq(Net.CollectionState(777), 1)
      M.ServerMessage("CollectionStatus:777:0")
      H.eq(Net.CollectionState(777), 1)
      -- das Ereignis meldet den effektiven Stand
      H.eq(evLast("COLLECTION_STATUS")[2], 1)
      H.eq(Net.QueryCollection(777), 1)
   end)

   -- =======================================================================
   H.section("State: Ausruestung")
   -- =======================================================================

   H.test("Ausruestung: Slotzustaende, Equipped-Felder, nur die 14 Slots", function()
      start()
      local want = { [0] = "READY", [2] = "READY", [3] = "EMPTY", [4] = "READY", [5] = "EMPTY", [6] = "READY",
         [7] = "EMPTY", [8] = "EMPTY", [9] = "EMPTY", [14] = "READY", [15] = "READY", [16] = "READY",
         [17] = "READY", [18] = "EMPTY" }
      for slot, st in pairs(want) do
         H.eq(State.SlotState(slot), st, "slot " .. slot)
      end
      -- keine transmogbaren Slots (Hals, Ringe, Schmuck) und Unsinn
      H.eq(State.SlotState(1), "NEVER")
      H.eq(State.SlotState(10), "NEVER")
      H.eq(State.SlotState(99), "NEVER")
      H.eq(State.SlotState(nil), "NEVER")

      local eq = State.Equipped(HEAD)
      H.truthy(eq)
      H.eq(eq.id, 101)
      H.eq(eq.name, "Plate Helm")
      H.eq(eq.quality, 4)
      H.eq(eq.equipLoc, "INVTYPE_HEAD")
      H.eq(eq.icon, "Interface\\Icons\\INV_Test_101")
      H.eq(eq.typeKey, 404)
      H.matches(eq.link, "item:101")
      H.eq(State.Equipped(SHIRT), nil)
      H.eq(State.Equipped(1), nil)
      H.eq(State.Equipped(nil), nil)
   end)

   H.test("State.Init: PLAYER_ENTERING_WORLD liest die Ausruestung neu; mehrfaches Init verdoppelt nichts", function()
      start()
      State.Init()
      State.Init()
      M.world.equipment[HEAD + 1] = 109
      M.Fire("PLAYER_ENTERING_WORLD")
      H.eq(State.Equipped(HEAD).id, 109)
      H.eq(evCount("EQUIPMENT_CHANGED"), 1)
      M.world.equipment[HEAD + 1] = 101
      M.Fire("PLAYER_EQUIPMENT_CHANGED", 1, 1)
      H.eq(evCount("EQUIPMENT_CHANGED"), 2)
      -- genau eine Neuanfrage nach der Ruhezeit, nicht je Init-Aufruf
      clearSent()
      M.Advance(0.6)
      H.eq(countSent("GetAvailableTransmogs"), 1)
      -- PLAYER_MONEY wird genau einmal bewertet
      ready({ [HEAD] = { 201 } })
      State.SetVendor(true)
      State.Select(HEAD, 201)
      settleCost(5000, false)
      clearLog()
      M.world.money = 9000
      M.Fire("PLAYER_MONEY")
      H.eq(evCount("COST_CHANGED"), 1)
   end)

   H.test("Ausruestung: Fernkampf-Relikt ist NEVER und nicht auswaehlbar", function()
      start({ equip = { [17] = 118, [0] = 101 } })
      H.eq(State.SlotState(RANGED), "NEVER")
      H.eq(State.SlotState(HEAD), "READY")
      setList(RANGED, { 201, 202 })
      H.eq(State.Select(RANGED, 201), false)
      H.eq(State.Select(RANGED, 0), false)
      H.eq(State.HasPending(RANGED), false)
   end)

   H.test("Ausruestung: Wechsel -> EQUIPMENT_CHANGED(slot), Auswahl verworfen, Liste veraltet, Neuanfrage nach 0,5 s", function()
      start({ server = true })
      srv.valid[HEAD] = { 201, 202, 203 }
      srv.valid[CHEST] = { 204, 205 }
      State.Refresh(true)
      srv.pump()
      State.SetVendor(true)
      H.eq(State.List(HEAD).ready, true)
      H.eq(State.Select(HEAD, 201), true)
      H.eq(State.Select(CHEST, 204), true)
      M.Advance(0.3)
      clearSent()
      clearLog()

      M.world.equipment[HEAD + 1] = 109
      M.Fire("PLAYER_EQUIPMENT_CHANGED", 1, 1)

      H.eq(State.Equipped(HEAD).id, 109)
      H.eq(State.Equipped(HEAD).name, "Plate Helm II")
      H.eq(evCount("EQUIPMENT_CHANGED"), 1)
      H.eq(evLast("EQUIPMENT_CHANGED")[1], HEAD)
      -- Auswahl nur dieses Slots verworfen
      H.eq(State.HasPending(HEAD), false)
      H.eq(State.HasPending(CHEST), true)
      H.eq(evCount("WANTED_CHANGED"), 1)
      H.eq(evLast("WANTED_CHANGED")[1], HEAD)
      -- die Liste gehoert zum alten Gegenstand: nicht mehr "fertig"
      H.eq(State.List(HEAD).ready, false)
      H.eq(State.List(CHEST).ready, true)

      -- entprellt: noch nichts gesendet
      M.Advance(0.3)
      H.eq(countSent("GetAvailableTransmogs"), 0)
      -- zweiter Wechsel verschiebt die Frist
      M.world.equipment[HEAD + 1] = 101
      M.Fire("PLAYER_EQUIPMENT_CHANGED", 1, 1)
      M.Advance(0.3)
      H.eq(countSent("GetAvailableTransmogs"), 0)
      M.Advance(0.4)
      H.eq(countSent("GetAvailableTransmogs"), 1)
      H.eq(countSent("GetTransmogStatus"), 1)
   end)

   H.test("Ausruestung: Slot leeren und neu belegen", function()
      start()
      M.world.equipment[CHEST + 1] = nil
      M.Fire("PLAYER_EQUIPMENT_CHANGED", 5, nil)
      H.eq(State.SlotState(CHEST), "EMPTY")
      H.eq(State.Equipped(CHEST), nil)
      H.eq(evCount("EQUIPMENT_CHANGED"), 1)
      H.eq(State.Select(CHEST, 201), false)
      M.world.equipment[CHEST + 1] = 104
      M.Fire("PLAYER_EQUIPMENT_CHANGED", 5, 1)
      H.eq(State.SlotState(CHEST), "READY")
      H.eq(evCount("EQUIPMENT_CHANGED"), 2)
   end)

   H.test("Ausruestung: gleiche ID mit anderem Link (Verzauberung) feuert nichts, aktualisiert aber den Link", function()
      start()
      local before = State.Equipped(HEAD).link
      local orig = _G.GetInventoryItemLink
      _G.GetInventoryItemLink = function(unit, slot)
         if unit == "player" and slot == HEAD + 1 then
            return "|cffa335ee|Hitem:101:2564:0:0:0:0:0:0:80|h[Plate Helm]|h|r"
         end
         return orig(unit, slot)
      end
      M.Fire("PLAYER_EQUIPMENT_CHANGED", 1, 1)
      _G.GetInventoryItemLink = orig
      H.eq(evCount("EQUIPMENT_CHANGED"), 0)
      H.neq(State.Equipped(HEAD).link, before)
      H.matches(State.Equipped(HEAD).link, "101:2564")
      H.eq(State.Equipped(HEAD).id, 101)
   end)

   H.test("Ausruestung: unbekannte Iteminfo -> READY, wird bei ITEMS_RESOLVED neu bewertet (Relikt -> NEVER)", function()
      -- Gegenstand nicht im Client-Cache: GetItemInfo liefert nichts
      start({ equip = {} })
      M.world.equipmentCached = false
      M.world.equipment[RANGED + 1] = 118
      M.Fire("PLAYER_EQUIPMENT_CHANGED", 18, 1)
      H.eq(State.SlotState(RANGED), "READY")
      local eq = State.Equipped(RANGED)
      H.truthy(eq)
      H.eq(eq.id, 118)
      H.eq(eq.equipLoc, nil)
      H.eq(eq.name, "Idol of Testing")          -- aus dem Link
      -- Auswahl in der Zwischenzeit (Liste unfertig -> optimistisch angenommen)
      setList(RANGED, { 201 })
      H.eq(State.Select(RANGED, 201), true)
      H.eq(State.HasPending(RANGED), true)
      clearLog()
      -- die Info trifft ein
      M.world.equipmentCached = true
      M.CacheAll()
      T.Events.Fire("ITEMS_RESOLVED", 1)
      H.eq(State.SlotState(RANGED), "NEVER")
      H.eq(State.Equipped(RANGED).equipLoc, "INVTYPE_RELIC")
      H.eq(State.HasPending(RANGED), false)
      H.eq(evCount("WANTED_CHANGED"), 1)
   end)

   H.test("Ausruestung: Iteminfo trifft spaeter ein (kein Relikt) -> EQUIPMENT_CHANGED aktualisiert Felder", function()
      start({ equip = {} })
      M.world.equipmentCached = false
      M.world.equipment[CHEST + 1] = 104
      M.Fire("PLAYER_EQUIPMENT_CHANGED", 5, 1)
      H.eq(State.Equipped(CHEST).equipLoc, nil)
      H.eq(State.Equipped(CHEST).icon, nil)
      clearLog()
      M.world.equipmentCached = true
      M.CacheAll()
      T.Events.Fire("ITEMS_RESOLVED", 1)
      H.eq(State.Equipped(CHEST).equipLoc, "INVTYPE_CHEST")
      H.eq(State.Equipped(CHEST).icon, "Interface\\Icons\\INV_Test_104")
      H.eq(State.SlotState(CHEST), "READY")
      H.eq(evCount("EQUIPMENT_CHANGED"), 1)
      H.eq(evLast("EQUIPMENT_CHANGED")[1], CHEST)
      -- ein weiteres ITEMS_RESOLVED aendert nichts mehr
      T.Events.Fire("ITEMS_RESOLVED", 1)
      H.eq(evCount("EQUIPMENT_CHANGED"), 1)
   end)

   -- =======================================================================
   H.section("State: Status und Listen")
   -- =======================================================================

   H.test("Status: ersetzt den vorherigen vollstaendig, STATUS_CHANGED nur bei Aenderung", function()
      start()
      setApplied({ [0] = 500, [4] = 600 })
      H.eq(State.Applied(HEAD), 500)
      H.eq(State.Applied(CHEST), 600)
      H.eq(State.Applied(LEGS), 0)
      H.eq(evCount("STATUS_CHANGED"), 1)

      setApplied({ [4] = 700, [14] = HIDDEN })
      H.eq(State.Applied(HEAD), 0)
      H.eq(State.Applied(CHEST), 700)
      H.eq(State.Applied(BACK), HIDDEN)
      H.eq(evCount("STATUS_CHANGED"), 2)

      setApplied({ [4] = 700, [14] = HIDDEN })      -- identisch
      H.eq(evCount("STATUS_CHANGED"), 2)

      setApplied({})
      H.eq(State.Applied(CHEST), 0)
      H.eq(State.Applied(BACK), 0)
      H.eq(evCount("STATUS_CHANGED"), 3)

      -- unbekannte Slots (Hals = 1) werden ignoriert, kein Fehler
      M.ServerMessage("TransmogStatus:1:1,123")
      H.eq(State.Applied(1), 0)
      H.eq(State.Applied(nil), 0)
      H.eq(State.Applied(99), 0)
   end)

   H.test("Status: das erste Ergebnis meldet STATUS_CHANGED auch ohne Aenderung (Status ist bekannt)", function()
      start({ alive = false })
      H.eq(State.StatusKnown(), false)
      M.ServerMessage("TransmogStatus:0")
      H.eq(State.StatusKnown(), true)
      H.eq(evCount("STATUS_CHANGED"), 1)
   end)

   H.test("Liste: start -> Chunks -> end liefert IDs in Serverreihenfolge, LIST_PROGRESS und LIST_READY", function()
      start()
      local ids = range(201, 245)               -- 45 IDs -> Chunks 20 + 20 + 5
      local msgs = listMsgs(HEAD, ids, 8)
      H.eq(#msgs, 5)
      local before = State.List(HEAD)
      H.eq(before.ready, false)
      H.deepEq(before.ids, {})

      M.ServerMessage(msgs[1])                  -- start
      local l = State.List(HEAD)
      H.eq(l.ready, false)
      H.eq(l.amount, 45)
      H.eq(l.bucket, 8)
      H.eq(l.received, 0)
      H.deepEq(evLast("LIST_PROGRESS"), { name = "LIST_PROGRESS", n = 3, HEAD, 0, 45 })

      M.ServerMessage(msgs[2])
      l = State.List(HEAD)
      H.eq(l.received, 20)
      H.eq(l.ready, false)
      H.deepEq(evLast("LIST_PROGRESS"), { name = "LIST_PROGRESS", n = 3, HEAD, 20, 45 })
      M.ServerMessage(msgs[3])
      M.ServerMessage(msgs[4])
      H.eq(State.List(HEAD).received, 45)
      H.eq(evCount("LIST_READY"), 0)

      M.ServerMessage(msgs[5])                  -- end
      l = State.List(HEAD)
      H.eq(l.ready, true)
      H.deepEq(l.ids, ids)
      H.eq(evCount("LIST_READY"), 1)
      H.eq(evLast("LIST_READY")[1], HEAD)
      H.eq(State.IsAvailable(HEAD, 201), true)
      H.eq(State.IsAvailable(HEAD, 245), true)
      H.eq(State.IsAvailable(HEAD, 246), false)
      for _, id in ipairs(ids) do H.eq(l.set[id], true) end
   end)

   H.test("Liste: kompletter Server-Antwortstrom fuer alle 14 Slots hintereinander", function()
      start({ server = true })
      for i, slot in ipairs(SERVER_SLOTS) do
         srv.valid[slot] = range(200 + i * 5, 200 + i * 5 + (i % 4) * 7)   -- 1..22 IDs
         srv.bucket[slot] = 3 + i
      end
      srv.valid[SHIRT] = {}                                              -- leerer Slot
      srv.bucket[SHIRT] = 0
      State.Refresh(true)
      srv.pump()
      for i, slot in ipairs(SERVER_SLOTS) do
         local l = State.List(slot)
         H.eq(l.ready, true, "slot " .. slot)
         H.deepEq(l.ids, srv.valid[slot], "slot " .. slot)
         H.eq(l.amount, #srv.valid[slot])
         H.eq(l.received, #srv.valid[slot])
         H.eq(l.bucket, srv.bucket[slot])
      end
      H.eq(evCount("LIST_READY"), 14)
      H.eq(State.ListsReady(), true)
   end)

   H.test("Liste: verschraenkte Stroeme verschiedener Slots bleiben getrennt", function()
      start()
      M.ServerMessage("AvailableTransmogs:0:8:3:start")
      M.ServerMessage("AvailableTransmogs:4:8:2:start")
      M.ServerMessage("AvailableTransmogs:0:8:3:201:202")
      M.ServerMessage("AvailableTransmogs:4:8:2:204")
      M.ServerMessage("AvailableTransmogs:0:8:3:203")
      M.ServerMessage("AvailableTransmogs:4:8:2:end")
      H.eq(State.List(CHEST).ready, true)
      H.eq(State.List(HEAD).ready, false)
      M.ServerMessage("AvailableTransmogs:0:8:3:end")
      H.deepEq(State.List(HEAD).ids, { 201, 202, 203 })
      H.deepEq(State.List(CHEST).ids, { 204 })
      H.eq(State.List(HEAD).ready, true)
   end)

   H.test("Liste: neues Start-Signal mitten im Strom verwirft das Bisherige", function()
      start()
      setList(HEAD, { 201, 202 })
      H.eq(State.List(HEAD).ready, true)
      M.ServerMessage("AvailableTransmogs:0:8:4:start")
      M.ServerMessage("AvailableTransmogs:0:8:4:210:211")
      M.ServerMessage("AvailableTransmogs:0:8:2:start")         -- Neustart mitten im Strom
      local l = State.List(HEAD)
      H.eq(l.ready, false)
      H.deepEq(l.ids, {})
      H.eq(l.amount, 2)
      H.eq(l.received, 0)
      M.ServerMessage("AvailableTransmogs:0:8:2:220")
      M.ServerMessage("AvailableTransmogs:0:8:2:221")
      M.ServerMessage("AvailableTransmogs:0:8:2:end")
      l = State.List(HEAD)
      H.deepEq(l.ids, { 220, 221 })
      H.eq(l.ready, true)
      H.eq(State.IsAvailable(HEAD, 210), false)
      H.eq(State.IsAvailable(HEAD, 201), false)
      H.eq(State.IsAvailable(HEAD, 220), true)
      H.eq(evCount("LIST_READY"), 2)       -- einmal je abgeschlossenem Strom
   end)

   H.test("Liste: doppelte IDs (auch ueber Chunks) zaehlen einmal", function()
      start()
      M.ServerMessage("AvailableTransmogs:0:8:5:start")
      M.ServerMessage("AvailableTransmogs:0:8:5:201:202")
      M.ServerMessage("AvailableTransmogs:0:8:5:202:203")
      M.ServerMessage("AvailableTransmogs:0:8:5:201")
      M.ServerMessage("AvailableTransmogs:0:8:5:end")
      local l = State.List(HEAD)
      H.deepEq(l.ids, { 201, 202, 203 })
      H.eq(l.received, 3)
      H.eq(l.amount, 5)           -- die gemeldete Menge bleibt die Serverangabe
      H.eq(l.ready, true)
   end)

   H.test("Liste: leere Liste (start, end) ist fertig und leer", function()
      start()
      M.ServerMessage("AvailableTransmogs:3:0:0:start")
      H.eq(State.List(SHIRT).ready, false)
      M.ServerMessage("AvailableTransmogs:3:0:0:end")
      local l = State.List(SHIRT)
      H.eq(l.ready, true)
      H.deepEq(l.ids, {})
      H.eq(l.amount, 0)
      H.eq(l.received, 0)
      H.eq(evCount("LIST_READY"), 1)
      H.eq(State.IsAvailable(SHIRT, 201), false)
   end)

   H.test("Liste: Chunk/Ende ohne Start und unbekannte Slots werden ignoriert", function()
      start()
      M.ServerMessage("AvailableTransmogs:0:8:3:201:202")
      M.ServerMessage("AvailableTransmogs:0:8:3:end")
      H.eq(State.List(HEAD).ready, false)
      H.deepEq(State.List(HEAD).ids, {})
      H.eq(evCount("LIST_READY"), 0)
      -- Hals (1) und Fingerslots gehoeren nicht zu den 14
      M.ServerMessage("AvailableTransmogs:1:0:2:start")
      M.ServerMessage("AvailableTransmogs:1:0:2:5:6")
      M.ServerMessage("AvailableTransmogs:1:0:2:end")
      H.eq(evCount("LIST_READY"), 0)
      H.deepEq(State.List(1).ids, {})
      H.eq(State.List(1).ready, false)
      -- zweites "end" nach fertigem Strom aendert nichts
      setList(HEAD, { 201 })
      M.ServerMessage("AvailableTransmogs:0:8:1:end")
      H.eq(evCount("LIST_READY"), 1)
   end)

   H.test("State.List: nie nil; unbekannter Slot liefert eine leere, unfertige Liste", function()
      start()
      for _, v in ipairs({ 1, 10, 99, -1 }) do
         local l = State.List(v)
         H.truthy(l, tostring(v))
         H.deepEq(l.ids, {})
         H.eq(l.ready, false)
         H.eq(l.amount, 0)
      end
      H.truthy(State.List(nil))
      H.truthy(State.List("x"))
      H.eq(State.IsAvailable(99, 5), false)
      H.eq(State.IsAvailable(HEAD, nil), false)
   end)

   H.test("Inaktiv: angewendetes Aussehen nicht (mehr) in der fertigen Liste -> Baseline 0", function()
      start()
      setApplied({ [HEAD] = 500 })
      -- Liste noch nicht fertig: nie inaktiv, Baseline = angewendet
      H.eq(State.IsInactive(HEAD), false)
      H.eq(State.Baseline(HEAD), 500)
      H.eq(State.Wanted(HEAD), 500)

      setList(HEAD, { 500, 501 })
      H.eq(State.IsInactive(HEAD), false)
      H.eq(State.Baseline(HEAD), 500)

      -- neue Liste ohne 500 (z.B. anderer Gegenstand angelegt)
      setList(HEAD, { 501, 502 })
      H.eq(State.IsInactive(HEAD), true)
      H.eq(State.Applied(HEAD), 500)            -- roh bleibt
      H.eq(State.Baseline(HEAD), 0)
      H.eq(State.Wanted(HEAD), 0)
      H.eq(State.HasPending(HEAD), false)
      H.eq(State.PendingCount(), 0)

      -- taucht wieder auf -> wieder aktiv
      setList(HEAD, { 500, 501 })
      H.eq(State.IsInactive(HEAD), false)
      H.eq(State.Baseline(HEAD), 500)
   end)

   H.test("Inaktiv: waehrend eines neuen Stroms (unfertig) gilt wieder Baseline = angewendet", function()
      start()
      setApplied({ [HEAD] = 500 })
      setList(HEAD, { 501 })
      H.eq(State.IsInactive(HEAD), true)
      M.ServerMessage("AvailableTransmogs:0:8:2:start")
      H.eq(State.IsInactive(HEAD), false)
      H.eq(State.Baseline(HEAD), 500)
      M.ServerMessage("AvailableTransmogs:0:8:2:501:502")
      M.ServerMessage("AvailableTransmogs:0:8:2:end")
      H.eq(State.IsInactive(HEAD), true)
   end)

   H.test("Inaktiv: VERBORGEN ist nie inaktiv (auch bei leerer fertiger Liste)", function()
      start()
      setApplied({ [HEAD] = HIDDEN, [BACK] = HIDDEN })
      setList(HEAD, {})
      setList(BACK, { 201 })
      H.eq(State.IsInactive(HEAD), false)
      H.eq(State.IsInactive(BACK), false)
      H.eq(State.Baseline(HEAD), HIDDEN)
      H.eq(State.Wanted(BACK), HIDDEN)
   end)

   H.test("Inaktiv: Listenende verwirft Auswahlen, die nicht (mehr) in der Liste stehen", function()
      start({ vendor = true })
      -- Liste noch unfertig: optimistisch angenommen
      H.eq(State.Select(HEAD, 250), true)
      H.eq(State.HasPending(HEAD), true)
      clearLog()
      setList(HEAD, { 201, 202 })
      H.eq(State.HasPending(HEAD), false)
      H.eq(evCount("WANTED_CHANGED"), 1)
      H.eq(evLast("WANTED_CHANGED")[1], HEAD)
      -- eine Auswahl, die in der Liste steht, bleibt
      H.eq(State.Select(HEAD, 201), true)
      setList(HEAD, { 201, 202, 203 })
      H.eq(State.HasPending(HEAD), true)
      H.eq(State.Wanted(HEAD), 201)
   end)

   H.test("Status-Antwort entfernt Auswahlen, die jetzt der Baseline entsprechen", function()
      start({ vendor = true })
      setList(HEAD, { 201, 202 })
      State.Select(HEAD, 201)
      H.eq(State.HasPending(HEAD), true)
      clearLog()
      setApplied({ [HEAD] = 201 })              -- der Server meldet bereits 201
      H.eq(State.HasPending(HEAD), false)
      H.eq(State.Wanted(HEAD), 201)
      H.eq(evCount("WANTED_CHANGED"), 1)
   end)

   -- =======================================================================
   H.section("State: Auswahl")
   -- =======================================================================

   H.test("Select: ungueltige Slots/Zustaende/IDs werden ignoriert (false, kein Ereignis)", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201, 202 }, [MAINHAND] = { 210 }, [RANGED] = { 211 } })
      clearLog()
      H.eq(State.Select(SHIRT, 201), false)            -- leerer Slot
      H.eq(State.Select(SHIRT, HIDDEN), false)
      H.eq(State.Select(SHIRT, 0), false)
      H.eq(State.Select(MAINHAND, HIDDEN), false)      -- Waffe nie verborgen
      H.eq(State.Select(OFFHAND, HIDDEN), false)
      H.eq(State.Select(RANGED, HIDDEN), false)
      H.eq(State.Select(HEAD, 203), false)             -- nicht in der fertigen Liste
      H.eq(State.Select(HEAD, "abc"), false)
      H.eq(State.Select(HEAD, -5), false)
      H.eq(State.Select(HEAD, 1.5), false)
      H.eq(State.Select(HEAD, nil), false)
      H.eq(State.Select(1, 201), false)                -- Hals
      H.eq(State.Select(99, 201), false)
      H.eq(State.Select(nil, 201), false)
      H.eq(State.Select("x", 201), false)
      H.eq(State.PendingCount(), 0)
      H.eq(evCount("WANTED_CHANGED"), 0)
      -- gueltig
      H.eq(State.Select(HEAD, HIDDEN), true)           -- Kopf verbergbar
      H.eq(State.Select(HEAD, 201), true)
      H.eq(State.Select(HEAD, 0), true)                -- 0 = Original: bei Baseline 0 kein Pending
      H.eq(State.HasPending(HEAD), false)
      H.eq(State.Select(MAINHAND, 210), true)
   end)

   H.test("Select: Auswahl gleich Baseline kollabiert zu keiner Auswahl", function()
      start({ vendor = true })
      setApplied({ [HEAD] = 500 })
      setList(HEAD, { 500, 501 })
      clearLog()
      H.eq(State.Select(HEAD, 500), true)
      H.eq(State.HasPending(HEAD), false)
      H.eq(evCount("WANTED_CHANGED"), 0)            -- nichts geaendert
      H.eq(State.Select(HEAD, 501), true)
      H.eq(State.HasPending(HEAD), true)
      H.eq(State.Wanted(HEAD), 501)
      H.eq(evCount("WANTED_CHANGED"), 1)
      H.eq(State.Select(HEAD, 500), true)           -- zurueck auf Baseline
      H.eq(State.HasPending(HEAD), false)
      H.eq(State.Wanted(HEAD), 500)
      H.eq(evCount("WANTED_CHANGED"), 2)
      H.eq(State.Select(HEAD, 0), true)             -- Entfernen vormerken
      H.eq(State.HasPending(HEAD), true)
      H.eq(State.Wanted(HEAD), 0)
      H.eq(evCount("WANTED_CHANGED"), 3)
      H.eq(State.Select(HEAD, 0), true)             -- erneut: keine Aenderung
      H.eq(evCount("WANTED_CHANGED"), 3)
      -- Baseline 0 (kein Aussehen): Select 0 ist keine Aenderung
      H.eq(State.Select(CHEST, 0), true)
      H.eq(State.HasPending(CHEST), false)
   end)

   H.test("Select: gleiches Aussehen wie Baseline bei inaktivem Aussehen (Baseline 0) ist nicht waehlbar", function()
      start({ vendor = true })
      setApplied({ [HEAD] = 500 })
      setList(HEAD, { 501 })                        -- 500 nicht mehr in der Liste -> inaktiv
      H.eq(State.IsInactive(HEAD), true)
      H.eq(State.Select(HEAD, 500), false)
      H.eq(State.Select(HEAD, 0), true)
      H.eq(State.HasPending(HEAD), false)           -- Baseline ist 0
   end)

   H.test("Toggle: Pending -> verwerfen; sonst Aussehen vorhanden -> Entfernen vormerken", function()
      start({ vendor = true })
      setApplied({ [HEAD] = 500, [CHEST] = HIDDEN })
      ready({ [HEAD] = { 500, 501 }, [CHEST] = { 201 }, [LEGS] = { 202 } })
      clearLog()

      -- ohne Aussehen und ohne Auswahl: nichts zu tun
      H.eq(State.Toggle(LEGS), false)
      H.eq(State.HasPending(LEGS), false)
      H.eq(evCount("WANTED_CHANGED"), 0)

      -- Baseline ~= 0: Entfernen vormerken
      H.eq(State.Toggle(HEAD), true)
      H.eq(State.HasPending(HEAD), true)
      H.eq(State.Wanted(HEAD), 0)
      -- erneut: Pending -> verwerfen
      H.eq(State.Toggle(HEAD), true)
      H.eq(State.HasPending(HEAD), false)
      H.eq(State.Wanted(HEAD), 500)

      -- Pending auf Baseline 0: verwerfen
      State.Select(LEGS, 202)
      H.eq(State.HasPending(LEGS), true)
      H.eq(State.Toggle(LEGS), true)
      H.eq(State.HasPending(LEGS), false)
      H.eq(State.Wanted(LEGS), 0)

      -- Verborgen als Baseline: Rechtsklick entfernt (Auswahl 0)
      H.eq(State.Toggle(CHEST), true)
      H.eq(State.Wanted(CHEST), 0)
      H.eq(State.HasPending(CHEST), true)

      -- Unsinn
      H.eq(State.Toggle(99), false)
      H.eq(State.Toggle(nil), false)
      H.eq(State.Toggle(SHIRT), false)
   end)

   H.test("Discard / DiscardAll", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201 }, [CHEST] = { 204 }, [LEGS] = { 206 } })
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      State.Select(LEGS, 206)
      clearLog()
      H.eq(State.Discard(HEAD), true)
      H.eq(State.Discard(HEAD), false)             -- schon verworfen
      H.eq(State.Discard(SHIRT), false)
      H.eq(State.Discard(99), false)
      H.eq(evCount("WANTED_CHANGED"), 1)
      H.eq(evLast("WANTED_CHANGED")[1], HEAD)
      H.eq(State.PendingCount(), 2)
      clearLog()
      H.eq(State.DiscardAll(), true)
      H.eq(State.PendingCount(), 0)
      H.eq(evCount("WANTED_CHANGED"), 1)           -- ein einziges Ereignis
      H.eq(evLast("WANTED_CHANGED").n, 1)
      H.eq(evLast("WANTED_CHANGED")[1], nil)
      H.eq(State.DiscardAll(), false)
      H.eq(evCount("WANTED_CHANGED"), 1)
   end)

   H.test("SetMany: ein einziges WANTED_CHANGED(nil), ungueltige Eintraege uebersprungen", function()
      start({ vendor = true })
      setApplied({ [LEGS] = 500 })
      ready({ [HEAD] = { 201 }, [CHEST] = { 204 }, [LEGS] = { 500, 206 }, [SHOULDER] = { 202 } })
      clearLog()
      local n = State.SetMany({
         [HEAD] = 201,
         [CHEST] = HIDDEN,
         [SHIRT] = 205,           -- leerer Slot
         [MAINHAND] = HIDDEN,     -- Waffe nie verborgen
         [LEGS] = 500,            -- == Baseline: keine Aenderung
         [SHOULDER] = 999,        -- nicht in der Liste
         [BACK] = "x",            -- Muell
         [1] = 5,                 -- kein transmogbarer Slot
      })
      H.eq(n, 2)
      H.eq(State.Wanted(HEAD), 201)
      H.eq(State.Wanted(CHEST), HIDDEN)
      H.eq(State.PendingCount(), 2)
      H.eq(evCount("WANTED_CHANGED"), 1)
      H.eq(evLast("WANTED_CHANGED").n, 1)
      H.eq(evLast("WANTED_CHANGED")[1], nil)

      -- keine Aenderung -> kein Ereignis
      clearLog()
      H.eq(State.SetMany({ [HEAD] = 201 }), 0)
      H.eq(State.SetMany({}), 0)
      H.eq(State.SetMany(nil), 0)
      H.eq(State.SetMany("x"), 0)
      H.eq(evCount("WANTED_CHANGED"), 0)
      -- 0 hebt eine Auswahl auf (Baseline 0)
      H.eq(State.SetMany({ [HEAD] = 0 }), 1)
      H.eq(State.HasPending(HEAD), false)
   end)

   H.test("PendingSlots: aufsteigend nach Server-Slot, PendingCount passend", function()
      start({ vendor = true })
      ready({ [MAINHAND] = { 210 }, [CHEST] = { 204 }, [HEAD] = { 201 }, [BACK] = { 214 }, [RANGED] = { 217 } })
      State.Select(MAINHAND, 210)
      State.Select(BACK, 214)
      State.Select(CHEST, 204)
      State.Select(HEAD, 201)
      H.deepEq(State.PendingSlots(), { 0, 4, 14, 15 })
      H.eq(State.PendingCount(), 4)
      State.Discard(CHEST)
      H.deepEq(State.PendingSlots(), { 0, 14, 15 })
      H.eq(State.PendingCount(), 3)
      -- die Rueckgabe ist eine frische Tabelle
      local a = State.PendingSlots()
      a[#a + 1] = 99
      H.deepEq(State.PendingSlots(), { 0, 14, 15 })
   end)

   H.test("IsAvailable: 0 immer, HIDDEN nur verbergbare Slots, sonst Liste", function()
      start()
      setList(HEAD, { 201 })
      setList(MAINHAND, { 210 })
      H.eq(State.IsAvailable(HEAD, 0), true)
      H.eq(State.IsAvailable(MAINHAND, 0), true)
      for _, slot in ipairs(SERVER_SLOTS) do
         H.eq(State.IsAvailable(slot, HIDDEN), HIDEABLE[slot] == true, "slot " .. slot)
      end
      H.eq(State.IsAvailable(HEAD, 201), true)
      H.eq(State.IsAvailable(HEAD, 210), false)
      H.eq(State.IsAvailable(MAINHAND, 210), true)
   end)

   H.test("Verborgen-Auswahl ist in allen 11 verbergbaren Slots moeglich und nur dort", function()
      local equip = {}
      for i, slot in ipairs(SERVER_SLOTS) do equip[slot] = 101 + (i % 3) end   -- irgendwas Anlegbares
      start({ equip = equip, vendor = true })
      for _, slot in ipairs(SERVER_SLOTS) do
         local ok = State.Select(slot, HIDDEN)
         H.eq(ok, HIDEABLE[slot] == true, "slot " .. slot)
         H.eq(State.HasPending(slot), HIDEABLE[slot] == true, "slot " .. slot)
      end
   end)

   -- =======================================================================
   H.section("State: Kosten")
   -- =======================================================================

   H.test("Kosten ohne Pending: 0, gueltig, nichts gesendet", function()
      start({ vendor = true })
      local c = State.Cost()
      H.deepEq(c, { copper = 0, canPurchase = true, valid = true, pending = false })
      M.Advance(2)
      H.eq(countSent("CalculateCost"), 0)
   end)

   H.test("Kosten: Verborgen und Entfernen kosten nichts -> es wird gar nicht angefragt", function()
      start({ vendor = true })
      setApplied({ [CHEST] = 600 })
      ready({ [HEAD] = { 201 }, [CHEST] = { 600, 204 } })
      State.Select(HEAD, HIDDEN)
      State.Select(CHEST, 0)
      H.eq(State.PendingCount(), 2)
      M.Advance(2)
      H.eq(countSent("CalculateCost"), 0)
      H.deepEq(State.Cost(), { copper = 0, canPurchase = true, valid = true, pending = false })
      H.deepEq({ State.CanApply() }, { true })
   end)

   H.test("Kosten: entprellt (0,25 s), nur die letzte Auswahl wird angefragt, Antwort macht gueltig", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201, 202, 203 }, [CHEST] = { 204 } })
      State.Select(HEAD, 201)
      -- sofort: angefragt, aber noch nichts gesendet
      local c = State.Cost()
      H.eq(c.valid, false)
      H.eq(c.pending, true)
      H.eq(countSent("CalculateCost"), 0)
      H.eq(evCount("COST_CHANGED"), 1)
      M.Advance(0.1)
      State.Select(HEAD, 202)
      M.Advance(0.1)
      State.Select(HEAD, 203)
      M.Advance(0.2)
      H.eq(countSent("CalculateCost"), 0)           -- noch in der Ruhezeit
      M.Advance(0.2)
      H.deepEq(sent(), { "CalculateCost:0:203" })
      H.eq(State.Cost().pending, true)
      H.eq(State.Cost().valid, false)

      M.ServerMessage("TransmogCost:5000:1")
      c = State.Cost()
      H.deepEq(c, { copper = 5000, canPurchase = true, valid = true, pending = false })
      H.eq(evLast("COST_CHANGED") ~= nil, true)

      -- zweiter Slot -> neue Anfrage mit beiden Paaren, aufsteigend nach Slot
      clearSent()
      State.Select(CHEST, 204)
      c = State.Cost()
      H.eq(c.valid, false)
      H.eq(c.pending, true)
      M.Advance(0.3)
      H.deepEq(sent(), { "CalculateCost:0:203,4:204" })
      M.ServerMessage("TransmogCost:10000:1")
      H.eq(State.Cost().copper, 10000)
      H.eq(State.Cost().valid, true)

      -- zurueck zur frueheren Auswahl: der Preis gilt nur fuer die letzte angefragte
      -- Auswahl, also wird neu gefragt (Kosten sind nie "gueltig" fuer eine andere Auswahl)
      clearSent()
      State.Discard(CHEST)
      H.eq(State.Cost().valid, false)
      M.Advance(0.3)
      H.deepEq(sent(), { "CalculateCost:0:203" })
      M.ServerMessage("TransmogCost:5000:1")
      H.deepEq(State.Cost(), { copper = 5000, canPurchase = true, valid = true, pending = false })
   end)

   H.test("Kosten: Verborgen-Paar wird mitgeschickt, sobald ein kostenpflichtiger Slot dabei ist", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201 }, [BACK] = { 214 } })
      State.Select(BACK, HIDDEN)
      State.Select(HEAD, 201)
      M.Advance(0.3)
      H.deepEq(sent(), { "CalculateCost:0:201,14:999999" })
   end)

   H.test("Kosten: aeltere Antworten werden verworfen (nur die der LETZTEN Anfrage gilt)", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201, 202 } })
      State.Select(HEAD, 201)
      M.Advance(0.3)                                -- Anfrage 1 gesendet
      State.Select(HEAD, 202)
      M.Advance(0.3)                                -- Anfrage 2 gesendet
      H.deepEq(sent(), { "CalculateCost:0:201", "CalculateCost:0:202" })
      H.eq(State.Cost().pending, true)

      M.ServerMessage("TransmogCost:111:1")         -- Antwort auf 1: veraltet
      local c = State.Cost()
      H.eq(c.valid, false)
      H.eq(c.pending, true)
      H.eq(evCount("COST_CHANGED") >= 1, true)

      M.ServerMessage("TransmogCost:222:1")         -- Antwort auf 2
      c = State.Cost()
      H.deepEq(c, { copper = 222, canPurchase = true, valid = true, pending = false })
   end)

   H.test("Kosten: Auswahl aendert sich, waehrend die Anfrage laeuft -> Antwort gilt nicht, es wird neu gefragt", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201, 202 } })
      State.Select(HEAD, 201)
      M.Advance(0.3)                                -- Anfrage fuer 201 unterwegs
      State.Select(HEAD, 202)                       -- Aenderung, Entprellung laeuft
      M.ServerMessage("TransmogCost:111:1")         -- Antwort fuer 201 trifft ein
      local c = State.Cost()
      H.eq(c.valid, false)                          -- gehoert nicht zur aktuellen Auswahl
      H.eq(c.pending, true)
      M.Advance(0.3)
      H.eq(sent()[#sent()], "CalculateCost:0:202")
      M.ServerMessage("TransmogCost:222:1")
      H.deepEq(State.Cost(), { copper = 222, canPurchase = true, valid = true, pending = false })
   end)

   H.test("Kosten: Auswahl verworfen waehrend die Anfrage laeuft -> Kosten 0 und gueltig", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201 } })
      State.Select(HEAD, 201)
      M.Advance(0.3)
      State.Discard(HEAD)
      H.deepEq(State.Cost(), { copper = 0, canPurchase = true, valid = true, pending = false })
      M.ServerMessage("TransmogCost:111:1")         -- verspaetete Antwort
      H.deepEq(State.Cost(), { copper = 0, canPurchase = true, valid = true, pending = false })
   end)

   H.test("Kosten: keine Antwort -> nach 5 s eine Wiederholung, danach aufgeben (nie ewig gesperrt)", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201 } })
      State.Select(HEAD, 201)
      M.Advance(0.3)
      H.eq(countSent("CalculateCost"), 1)
      H.eq(State.Cost().pending, true)
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_COST_PENDING" })

      M.Advance(5.2)                                -- 1. Zeitueberschreitung -> Wiederholung
      H.eq(countSent("CalculateCost"), 2)
      H.eq(State.Cost().pending, true)

      M.Advance(5.2)                                -- 2. Zeitueberschreitung -> aufgeben
      H.eq(countSent("CalculateCost"), 2)
      local c = State.Cost()
      H.eq(c.pending, false)
      H.eq(c.valid, false)
      -- der Knopf bleibt benutzbar (Kosten unbekannt)
      H.deepEq({ State.CanApply() }, { true })
   end)

   H.test("Kosten: eine nach dem Aufgeben eintreffende Antwort wird fuer dieselbe Auswahl noch uebernommen", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201 } })
      State.Select(HEAD, 201)
      M.Advance(0.3)
      M.Advance(10.5)                               -- Wiederholung, dann aufgegeben
      H.eq(State.Cost().valid, false)
      H.eq(State.Cost().pending, false)
      M.ServerMessage("TransmogCost:5000:1")
      H.deepEq(State.Cost(), { copper = 5000, canPurchase = true, valid = true, pending = false })
   end)

   H.test("Kosten: kann nicht gesendet werden (kein Spielername), bleibt nichts ausstehend", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201, 202 } })
      M.world.playerName = ""
      State.Select(HEAD, 201)
      M.Advance(0.3)
      H.eq(#M.sentAddon, 0)
      local c = State.Cost()
      H.eq(c.pending, false)
      H.eq(c.valid, false)
      H.deepEq({ State.CanApply() }, { true })
      -- wieder moeglich: die naechste Aenderung fragt an
      M.world.playerName = "Testplayer"
      State.Select(HEAD, 202)
      M.Advance(0.3)
      H.deepEq(sent(), { "CalculateCost:0:202" })
      M.ServerMessage("TransmogCost:7:1")
      H.eq(State.Cost().valid, true)
   end)

   H.test("CanApply: unbekannte Kosten (aufgegeben) sperren nicht, auch wenn der letzte Stand 'nicht bezahlbar' war", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201, 202 } })
      State.Select(HEAD, 201)
      settleCost(5000, false)
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_MONEY" })
      State.Select(HEAD, 202)
      M.Advance(0.3)
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_COST_PENDING" })
      M.Advance(11)                                 -- keine Antwort: Wiederholung, dann aufgeben
      local c = State.Cost()
      H.eq(c.valid, false)
      H.eq(c.pending, false)
      H.deepEq({ State.CanApply() }, { true })
   end)

   H.test("Anwenden abgelehnt (zu wenig Geld / Kosten offen) meldet den Grund im Chat", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201 } })
      State.Select(HEAD, 201)
      local n0 = #M.messages
      State.Apply()                                 -- Kosten noch offen
      H.eq(#M.messages, n0 + 1)
      H.contains(M.messages[#M.messages], T.L.APPLY_REASON_COST_PENDING)
      settleCost(5000, false)
      n0 = #M.messages
      State.Apply()
      H.eq(#M.messages, n0 + 1)
      H.contains(M.messages[#M.messages], T.L.APPLY_REASON_MONEY)
      -- NONE und BUSY bleiben still
      State.DiscardAll()
      n0 = #M.messages
      State.Apply()
      H.eq(#M.messages, n0)
   end)

   H.test("Kosten: kommen nach einer Wiederholung beide Antworten, gilt die letzte", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201 } })
      State.Select(HEAD, 201)
      M.Advance(0.3)
      M.Advance(5.2)                                -- Wiederholung unterwegs
      H.eq(countSent("CalculateCost"), 2)
      M.ServerMessage("TransmogCost:5000:1")        -- (langsame) Antwort 1
      M.ServerMessage("TransmogCost:5000:1")        -- Antwort 2
      H.deepEq(State.Cost(), { copper = 5000, canPurchase = true, valid = true, pending = false })
   end)

   H.test("Kosten: nicht bezahlbar -> MONEY; PLAYER_MONEY bewertet neu", function()
      start({ vendor = true })
      ready({ [HEAD] = { 201 } })
      M.world.money = 1000
      State.Select(HEAD, 201)
      settleCost(5000, false)
      H.deepEq(State.Cost(), { copper = 5000, canPurchase = false, valid = true, pending = false })
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_MONEY" })
      clearLog()
      M.world.money = 6000
      M.Fire("PLAYER_MONEY")
      H.eq(State.Cost().canPurchase, true)
      H.eq(evCount("COST_CHANGED"), 1)
      H.deepEq({ State.CanApply() }, { true })
      M.world.money = 10
      M.Fire("PLAYER_MONEY")
      H.eq(State.Cost().canPurchase, false)
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_MONEY" })
   end)

   H.test("Kosten: unaufgeforderte TransmogCost-Nachricht aendert nichts und wirft nicht", function()
      start({ vendor = true })
      M.ServerMessage("TransmogCost:12345:0")
      H.deepEq(State.Cost(), { copper = 0, canPurchase = true, valid = true, pending = false })
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_NONE" })
   end)

   -- =======================================================================
   H.section("State: CanApply")
   -- =======================================================================

   H.test("CanApply: Gruende einzeln", function()
      start({ server = true })
      srv.valid[HEAD] = { 201, 202 }
      State.Refresh(true)
      srv.pump()
      -- nichts geaendert
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_NONE" })

      -- Auswahl, aber kein Transmogrifizierer
      State.Select(HEAD, 201)
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_VENDOR" })
      -- Option "Anwenden auch ohne Transmogrifizierer"
      T.DB.Set("allowAnywhere", true)
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_COST_PENDING" })
      T.DB.Set("allowAnywhere", false)
      State.SetVendor(true)
      H.eq(evCount("VENDOR_CHANGED"), 1)
      H.eq(evLast("VENDOR_CHANGED")[1], true)
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_COST_PENDING" })

      -- Kosten da -> frei
      M.Advance(0.3)
      srv.pump()
      H.deepEq({ State.CanApply() }, { true })

      -- zu wenig Geld
      srv.money = 100
      State.Select(HEAD, 202)
      M.Advance(0.3)
      srv.pump()
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_MONEY" })
   end)

   H.test("CanApply: SERVER, wenn das Modul nicht antwortet (Net.state == ABSENT)", function()
      start({ vendor = true, alive = false })
      -- ohne Servernachricht (Liste unfertig -> Auswahl wird optimistisch angenommen)
      H.eq(State.Select(HEAD, 201), true)
      Net.RequestStatus()
      M.Advance(9)
      H.eq(Net.state, "ABSENT")
      local ok, reason = State.CanApply()
      H.eq(ok, false)
      H.eq(reason, "APPLY_REASON_SERVER")
      -- Apply wird abgelehnt und sendet nichts
      clearSent()
      H.deepEq({ State.Apply() }, { false, "APPLY_REASON_SERVER" })
      H.eq(#sent(), 0)
      H.eq(State.Busy(), false)
   end)

   H.test("CanApply: Reihenfolge der Gruende (dokumentiert in State.lua)", function()
      -- SERVER vor allem; dann NONE, BUSY, VENDOR, COST_PENDING, MONEY
      start({ alive = false })
      Net.RequestStatus()
      M.Advance(9)
      H.eq(Net.state, "ABSENT")
      local _, reason = State.CanApply()
      H.eq(reason, "APPLY_REASON_SERVER")
      M.ServerMessage("TransmogStatus:0")
      H.eq(Net.state, "OK")
      -- NONE vor VENDOR (kein Transmogrifizierer, aber auch nichts geaendert)
      _, reason = State.CanApply()
      H.eq(reason, "APPLY_REASON_NONE")
      -- VENDOR vor COST_PENDING
      setList(HEAD, { 201 })
      State.Select(HEAD, 201)
      _, reason = State.CanApply()
      H.eq(reason, "APPLY_REASON_VENDOR")
      State.SetVendor(true)
      _, reason = State.CanApply()
      H.eq(reason, "APPLY_REASON_COST_PENDING")
   end)

   -- Seit 2.1 ist "Anwenden auch ohne Transmogrifizierer" an (Neuinstallation, noSeed = true): der Server
   -- prueft den Abstand zum NPC nicht (TransmogAddonProtocol.cpp), nur das Addon sperrte den Vorschau-Modus.
   H.test("CanApply (Vorgabe seit 2.1): ohne Transmogrifizierer frei; SERVER, NONE, COST_PENDING und MONEY sperren weiter", function()
      start({ server = true, noSeed = true })
      H.eq(T.DB.global.allowAnywhere, true, "Vorgabe an")
      H.eq(State.atVendor, false, "weit weg vom NPC")
      srv.valid[HEAD] = { 201, 202 }
      State.Refresh(true)
      srv.pump()
      -- nichts ausgewaehlt
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_NONE" })
      -- Auswahl: der Grund VENDOR entfaellt, jetzt zaehlen die Kosten
      State.Select(HEAD, 201)
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_COST_PENDING" })
      M.Advance(0.3)
      srv.pump()
      H.deepEq({ State.CanApply() }, { true })
      -- zu wenig Geld sperrt weiter
      srv.money = 100
      State.Select(HEAD, 202)
      M.Advance(0.3)
      srv.pump()
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_MONEY" })
      -- am NPC: unveraendert; danach wieder weg vom NPC: ebenfalls
      srv.money = 100000000
      State.Select(HEAD, 201)
      M.Advance(0.3)
      srv.pump()
      State.SetVendor(true)
      H.deepEq({ State.CanApply() }, { true })
      State.SetVendor(false)
      H.deepEq({ State.CanApply() }, { true })
      -- der Spieler schaltet die Option aus: der Grund VENDOR ist zurueck; wieder an: frei
      T.DB.Set("allowAnywhere", false)
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_VENDOR" })
      T.DB.Set("allowAnywhere", true)
      H.deepEq({ State.CanApply() }, { true })
   end)

   H.test("CanApply (Vorgabe seit 2.1): SERVER sperrt auch ueberall, BUSY ebenso; die Reihenfolge bleibt", function()
      start({ alive = false, noSeed = true })
      Net.RequestStatus()
      M.Advance(9)
      H.eq(Net.state, "ABSENT")
      local _, reason = State.CanApply()
      H.eq(reason, "APPLY_REASON_SERVER", "kein Modul: SERVER vor allem")
      H.deepEq({ State.CanRemoveAll() }, { false, "APPLY_REASON_SERVER" })
      M.ServerMessage("TransmogStatus:0")
      H.eq(Net.state, "OK")
      _, reason = State.CanApply()
      H.eq(reason, "APPLY_REASON_NONE", "NONE vor allem anderen")
      setList(HEAD, { 201 })
      State.Select(HEAD, 201)
      _, reason = State.CanApply()
      H.eq(reason, "APPLY_REASON_COST_PENDING", "ohne NPC: gleich Kosten, kein VENDOR")
      H.deepEq({ State.CanRemoveAll() }, { true })
   end)

   H.test("Apply und RemoveAll (Vorgabe seit 2.1): funktionieren ohne Transmogrifizierer bis zum Server", function()
      start({ server = true, noSeed = true })
      srv.valid[HEAD] = { 201, 202, 203 }
      srv.valid[CHEST] = { 204, 205 }
      srv.stored[LEGS] = 207
      State.Refresh(true)
      srv.pump()
      clearSent()
      srv.seen = 0
      H.eq(State.atVendor, false)
      H.eq(State.Applied(LEGS), 207)

      -- Anwenden
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      M.Advance(0.3)
      srv.pump()
      clearSent()
      local ok, reason = State.Apply()
      H.eq(ok, true)
      H.eq(reason, nil)
      srv.pump()
      srv.pump()
      H.deepEq({ sent()[1], sent()[2] }, { "Apply:0:201", "Apply:4:204" })
      H.eq(State.Busy(), false)
      H.eq(State.Applied(HEAD), 201)
      H.eq(State.Applied(CHEST), 204)
      H.eq(State.PendingCount(), 0)
      local nApply = countSent("Apply")
      H.eq(nApply, 2)

      -- Alles entfernen
      clearSent()
      H.eq(State.RemoveAll(), true)
      srv.pump()
      H.deepEq(sent(), { "RemoveAll" })
      H.eq(State.Applied(HEAD), 0)
      H.eq(State.Applied(LEGS), 0)
   end)

   H.test("Apply und RemoveAll mit ausgeschalteter Option: abgelehnt mit VENDOR, nichts gesendet (Wahl des Spielers)", function()
      start({ server = true, noSeed = true })
      srv.valid[HEAD] = { 201 }
      srv.stored[LEGS] = 207
      State.Refresh(true)
      srv.pump()
      T.DB.Set("allowAnywhere", false)
      State.Select(HEAD, 201)
      M.Advance(0.3)
      srv.pump()
      clearSent()
      H.deepEq({ State.Apply() }, { false, "APPLY_REASON_VENDOR" })
      H.deepEq({ State.RemoveAll() }, { false, "APPLY_REASON_VENDOR" })
      srv.pump()
      H.eq(#sent(), 0)
      H.eq(State.Busy(), false)
      -- am NPC geht beides trotzdem
      State.SetVendor(true)
      H.deepEq({ State.CanApply() }, { true })
      H.eq(State.RemoveAll(), true)
   end)

   -- =======================================================================
   H.section("State: Anwenden")
   -- =======================================================================

   -- Standardlage fuer Apply-Tests: Server-Nachbau, Listen/Status geladen, am Transmogrifizierer
   local function applyScene()
      start({ server = true, vendor = true })
      srv.valid[HEAD] = { 201, 202, 203 }
      srv.valid[SHOULDER] = { 211, 212 }
      srv.valid[CHEST] = { 204, 205 }
      srv.valid[LEGS] = { 206, 207 }
      srv.valid[BACK] = { 214 }
      srv.valid[MAINHAND] = { 215 }
      srv.stored[LEGS] = 207
      State.Refresh(true)
      srv.pump()
      clearSent()
      srv.seen = 0
      clearLog()
   end

   local function settle()
      -- Kosten abwarten und beantworten lassen
      M.Advance(0.3)
      srv.pump()
   end

   H.test("Apply: kompletter Ablauf mit Antworten, Ereignissen und Resync", function()
      applyScene()
      H.eq(State.Applied(LEGS), 207)
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      settle()
      H.deepEq({ State.CanApply() }, { true })
      clearSent()
      clearLog()
      srv.hold = true

      local ok, reason = State.Apply()
      H.eq(ok, true)
      H.eq(reason, nil)
      H.eq(State.Busy(), true)
      -- genau EIN Befehl ist unterwegs, aufsteigende Slotfolge
      srv.pump()
      H.deepEq(sent(), { "Apply:0:201" })
      H.eq(evNames({ APPLY_STARTED = true })[1], "APPLY_STARTED")
      H.eq(evLast("APPLY_STARTED")[1], 2)
      -- waehrend der Bearbeitung kein zweiter Apply, kein neuer Befehl
      H.deepEq({ State.Apply() }, { false, "APPLY_REASON_BUSY" })
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_BUSY" })
      H.eq(#sent(), 1)

      srv.flush()                                   -- Antwort 1 -> Befehl 2
      srv.pump()
      H.deepEq(sent(), { "Apply:0:201", "Apply:4:204" })
      H.eq(State.Applied(HEAD), 201)                -- sofort lokal uebernommen
      H.eq(State.HasPending(HEAD), false)
      H.eq(State.HasPending(CHEST), true)
      H.eq(evCount("APPLY_PROGRESS"), 1)
      H.deepEq(evLast("APPLY_PROGRESS"), { name = "APPLY_PROGRESS", n = 3, HEAD, true, 201 })
      H.eq(State.Busy(), true)

      srv.flush()
      srv.pump()
      H.eq(State.Busy(), false)
      H.eq(State.Applied(CHEST), 204)
      H.eq(State.PendingCount(), 0)
      H.eq(evCount("APPLY_PROGRESS"), 2)
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 2, 0 })
      -- Reihenfolge: STARTED zuerst, DONE zuletzt unter den Apply-Ereignissen
      local names = evNames({ APPLY_STARTED = true, APPLY_PROGRESS = true, APPLY_DONE = true })
      H.deepEq(names, { "APPLY_STARTED", "APPLY_PROGRESS", "APPLY_PROGRESS", "APPLY_DONE" })
      -- Resync: Status wird nach Abschluss erneut angefordert
      H.eq(sent()[#sent()], "GetTransmogStatus")
      srv.pump()
      srv.flush()
      H.eq(State.Applied(HEAD), 201)
      H.eq(State.Applied(CHEST), 204)
      H.eq(State.Applied(LEGS), 207)
   end)

   H.test("Apply: Entfernen (Remove) und Verborgen (999999) im selben Stapel", function()
      applyScene()
      State.Select(LEGS, 0)                         -- Remove
      State.Select(BACK, HIDDEN)                    -- Hidden
      State.Select(HEAD, 202)
      settle()
      H.deepEq({ State.CanApply() }, { true })
      clearSent()
      local ok = State.Apply()
      H.eq(ok, true)
      srv.pump()
      H.eq(State.Busy(), false)
      -- Reihenfolge nach Slot: 0, 6 (Remove), 14 (Hidden)
      local cmds = srv.log
      local applyCmds = {}
      for _, c in ipairs(cmds) do
         if string.match(c, "^Apply") or string.match(c, "^Remove:") then applyCmds[#applyCmds + 1] = c end
      end
      H.deepEq(applyCmds, { "Apply:0:202", "Remove:6", "Apply:14:999999" })
      H.eq(State.Applied(HEAD), 202)
      H.eq(State.Applied(LEGS), 0)
      H.eq(State.Applied(BACK), HIDDEN)
      H.eq(State.PendingCount(), 0)
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 3, 0 })
   end)

   H.test("Apply: Fehlschlag mitten im Stapel -> Slot behaelt Auswahl, naechste Operationen laufen weiter", function()
      applyScene()
      State.Select(HEAD, 201)
      State.Select(SHOULDER, 211)
      State.Select(CHEST, 204)
      settle()
      srv.valid[SHOULDER] = {}                      -- der Server lehnt Slot 2 ab
      clearLog()
      State.Apply()
      srv.pump()
      H.eq(State.Busy(), false)
      local progress = evList("APPLY_PROGRESS")
      H.eq(#progress, 3)
      H.deepEq({ progress[1][1], progress[1][2], progress[1][3] }, { HEAD, true, 201 })
      H.deepEq({ progress[2][1], progress[2][2], progress[2][3] }, { SHOULDER, false, 211 })
      H.deepEq({ progress[3][1], progress[3][2], progress[3][3] }, { CHEST, true, 204 })
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 2, 1 })
      -- Auswahl des fehlgeschlagenen Slots bleibt; die uebrigen sind angewendet
      H.eq(State.HasPending(SHOULDER), true)
      H.eq(State.Wanted(SHOULDER), 211)
      H.eq(State.Applied(SHOULDER), 0)
      H.eq(State.PendingCount(), 1)
      H.eq(State.Applied(HEAD), 201)
      H.eq(State.Applied(CHEST), 204)
   end)

   H.test("Apply: alle Operationen schlagen fehl -> APPLY_DONE(0, n), nichts angewendet, wieder bedienbar", function()
      applyScene()
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      settle()
      srv.money = 0
      clearLog()
      State.Apply()
      srv.pump()
      H.eq(State.Busy(), false)
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 0, 2 })
      H.eq(State.PendingCount(), 2)
      -- erneut moeglich (Kosten sind gueltig, Geldlage ist Sache des Servers)
      srv.money = 1000000
      settle()
      H.deepEq({ State.CanApply() }, { true })
      clearLog()
      State.Apply()
      srv.pump()
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 2, 0 })
      H.eq(State.PendingCount(), 0)
   end)

   H.test("Apply: Zeitueberschreitung nach 5 s -> Fehlschlag, naechste Operation geht hinaus", function()
      applyScene()
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      settle()
      srv.hold = true                               -- Antworten bleiben aus
      clearSent()
      clearLog()
      State.Apply()
      srv.pump()
      H.deepEq(sent(), { "Apply:0:201" })
      M.Advance(4.5)
      H.eq(#sent(), 1)
      H.eq(State.Busy(), true)
      M.Advance(0.7)                                -- > 5 s
      H.eq(evCount("APPLY_PROGRESS"), 1)
      H.deepEq(evLast("APPLY_PROGRESS"), { name = "APPLY_PROGRESS", n = 3, HEAD, false, 201 })
      srv.pump()
      H.deepEq(sent(), { "Apply:0:201", "Apply:4:204" })
      H.eq(State.Busy(), true)
      M.Advance(5.2)
      H.eq(State.Busy(), false)
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 0, 2 })
      H.eq(State.PendingCount(), 2)                 -- beide Auswahlen bleiben
      -- Resync nach Abschluss
      H.eq(sent()[#sent()], "GetTransmogStatus")
   end)

   H.test("Apply: Spaetantwort einer abgelaufenen Operation wird nicht der naechsten zugeschlagen", function()
      applyScene()
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      settle()
      srv.hold = true
      clearSent()
      clearLog()
      State.Apply()
      srv.pump()
      M.Advance(5.2)                                -- Operation 1 laeuft ab, Operation 2 ist unterwegs
      srv.pump()
      H.deepEq(sent(), { "Apply:0:201", "Apply:4:204" })
      H.eq(evCount("APPLY_PROGRESS"), 1)

      -- Jetzt trifft die (verspaetete) Antwort 1 ein, gefolgt von Antwort 2
      srv.flush()
      -- Antwort 1 betrifft Slot 0: lokal uebernommen; Operation 2 ist weiterhin die laufende
      H.eq(State.Applied(HEAD), 201)
      -- Antwort 2 beendet den Stapel regulaer
      H.eq(State.Busy(), false)
      H.eq(State.Applied(CHEST), 204)
      local progress = evList("APPLY_PROGRESS")
      H.eq(#progress, 2)
      H.eq(progress[1][2], false)                   -- 1 zaehlt als Fehlschlag (abgelaufen)
      H.eq(progress[2][1], CHEST)
      H.eq(progress[2][2], true)
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 1, 1 })
   end)

   H.test("Apply: abgelaufene Operation + verspaetete FEHLantwort frisst nur den Geist", function()
      applyScene()
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      settle()
      srv.hold = true
      State.Apply()
      srv.pump()
      M.Advance(5.2)                                -- Operation 1 abgelaufen
      srv.pump()                                    -- Operation 2 gesendet
      srv.held = {}                                 -- Server-Antworten verwerfen
      M.ServerMessage("ApplyTransmogResult:0")      -- verspaetete Fehlantwort zu Operation 1
      H.eq(State.Busy(), true)                      -- Operation 2 laeuft unbeeintraechtigt
      M.ServerMessage("ApplyTransmogResult:1:4,204")
      H.eq(State.Busy(), false)
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 1, 1 })
      H.eq(State.Applied(CHEST), 204)
   end)

   H.test("Apply: geht die Antwort einer abgelaufenen Operation ganz verloren, wird die naechste per Slot zugeordnet", function()
      applyScene()
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      settle()
      srv.drop.Apply = 1                            -- Antwort der 1. Operation geht verloren (Effekt tritt ein)
      clearSent()
      clearLog()
      State.Apply()
      srv.pump()
      M.Advance(5.2)                                -- Operation 1 laeuft ab, Operation 2 geht hinaus
      srv.pump()                                    -- der Server beantwortet Operation 2
      -- sofort fertig: nicht noch einmal 5 s auf Operation 2 warten
      H.eq(State.Busy(), false)
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 1, 1 })
      H.eq(State.Applied(CHEST), 204)
      H.eq(State.HasPending(CHEST), false)
      -- der Server hatte Operation 1 ausgefuehrt: der Resync holt es nach
      srv.pump()
      H.eq(State.Applied(HEAD), 201)
      H.eq(State.HasPending(HEAD), false)
   end)

   H.test("Apply: nach lokalem Erfolg bleibt keine verdeckte Auswahl zurueck (spaeterer Status zeigt kein Pending)", function()
      applyScene()
      State.Select(HEAD, 201)
      settle()
      State.Apply()
      srv.pump()
      srv.pump()
      H.eq(State.Applied(HEAD), 201)
      H.eq(State.HasPending(HEAD), false)
      -- das Aussehen verschwindet (z.B. an anderer Stelle entfernt): kein "Geister-Pending"
      M.ServerMessage("TransmogStatus:0")
      H.eq(State.Applied(HEAD), 0)
      H.eq(State.HasPending(HEAD), false)
      H.eq(State.Wanted(HEAD), 0)
      H.eq(State.PendingCount(), 0)
      -- ebenso beim Entfernen ueber Remove
      State.Select(HEAD, 202)
      settle()
      State.Apply()
      srv.pump()
      srv.pump()
      State.Select(HEAD, 0)
      settle()
      State.Apply()
      srv.pump()
      srv.pump()
      M.ServerMessage(statusMsg({ [HEAD] = 202 }))
      H.eq(State.Applied(HEAD), 202)
      H.eq(State.HasPending(HEAD), false)
   end)

   H.test("Apply: waehrend des Stapels alle Auswahlen verworfen -> NONE (Stapel laeuft zu Ende)", function()
      applyScene()
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      settle()
      srv.hold = true
      State.Apply()
      srv.pump()
      State.DiscardAll()
      H.eq(State.Busy(), true)
      -- Auswahlen sind weg: nichts anzuwenden; beide Operationen laufen trotzdem sauber zu Ende
      H.deepEq({ State.CanApply() }, { false, "APPLY_REASON_NONE" })
      srv.flush()
      srv.pump()
      srv.flush()
      H.eq(State.Busy(), false)
      H.eq(State.Applied(HEAD), 201)
      H.eq(State.Applied(CHEST), 204)
   end)

   H.test("Apply: Erfolgsmeldung ohne Slotangabe wird der aeltesten Operation zugeordnet", function()
      applyScene()
      State.Select(HEAD, 201)
      settle()
      srv.hold = true
      clearLog()
      State.Apply()
      srv.pump()
      srv.held = {}
      M.ServerMessage("ApplyTransmogResult:1")
      H.eq(State.Busy(), false)
      H.eq(State.Applied(HEAD), 201)
      H.deepEq(evLast("APPLY_PROGRESS"), { name = "APPLY_PROGRESS", n = 3, HEAD, true, 201 })
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 1, 0 })
   end)

   H.test("Apply: der Erfolg heilt auch ohne spaeteren Status (keine verdeckte Auswahl)", function()
      applyScene()
      State.Select(HEAD, 201)
      settle()
      srv.hold = true
      State.Apply()
      srv.pump()
      srv.flush()                                   -- Erfolgsantwort; der Resync-Status wurde noch nicht beantwortet
      H.eq(State.Busy(), false)
      H.eq(State.Applied(HEAD), 201)
      -- bevor der Resync eintrifft, meldet der Server das Aussehen als weg
      M.ServerMessage("TransmogStatus:0")
      H.eq(State.Applied(HEAD), 0)
      H.eq(State.HasPending(HEAD), false)
      H.eq(State.Wanted(HEAD), 0)
   end)

   H.test("Apply: alte Geister (> 30 s) werden vor einem neuen Stapel entfernt", function()
      applyScene()
      State.Select(HEAD, 201)
      settle()
      srv.hold = true
      srv.valid[CHEST] = { 204 }
      State.Apply()
      srv.pump()
      M.Advance(5.2)                                -- Operation laeuft ab, Antwort kommt nie
      H.eq(State.Busy(), false)
      srv.held = {}
      M.Advance(40)                                 -- der Geist ist jetzt alt
      srv.hold = false
      settle()                                      -- der Resync-Status nach Stapel 1 wird beantwortet
      H.eq(State.Applied(HEAD), 201)                -- der Server hatte Operation 1 ausgefuehrt
      -- neuer Stapel; der Server lehnt ab (kein Geld, was der Client nicht weiss)
      State.Select(CHEST, 204)
      settle()
      srv.money = 0
      clearLog()
      H.deepEq({ State.CanApply() }, { true })
      State.Apply()
      srv.pump()
      -- die Fehlantwort gehoert zur neuen Operation und beendet den Stapel sofort
      -- (ein liegengebliebener Geist wuerde sie schlucken und den Stapel 5 s warten lassen)
      H.eq(State.Busy(), false)
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 0, 1 })
   end)

   H.test("Apply: unerwartete Zusatzantworten (kein Stapel laeuft) werfen nicht und beschaedigen nichts", function()
      applyScene()
      -- Fehlantwort ohne laufende Operation
      M.ServerMessage("ApplyTransmogResult:0")
      H.eq(State.Busy(), false)
      H.eq(evCount("APPLY_PROGRESS"), 0)
      -- Erfolgsmeldung ohne Operation: der Server hat angewendet -> lokal uebernehmen
      M.ServerMessage("ApplyTransmogResult:1:4,204")
      H.eq(State.Applied(CHEST), 204)
      H.eq(State.Busy(), false)
      -- Erfolg ohne Slotangabe und ohne Operation: ignorieren
      M.ServerMessage("ApplyTransmogResult:1")
      H.eq(State.Busy(), false)
      H.eq(evCount("APPLY_DONE"), 0)
      -- Slot ausserhalb der 14
      M.ServerMessage("ApplyTransmogResult:1:1,5")
      H.eq(State.Applied(1), 0)
   end)

   H.test("Apply: Zusatzantwort NACH Abschluss eines Stapels wird als lokaler Erfolg verbucht, ohne Ereignisse", function()
      applyScene()
      State.Select(HEAD, 201)
      settle()
      State.Apply()
      srv.pump()
      H.eq(State.Busy(), false)
      clearLog()
      M.ServerMessage("ApplyTransmogResult:1:0,201")     -- doppelt
      H.eq(State.Applied(HEAD), 201)
      H.eq(evCount("APPLY_PROGRESS"), 0)
      H.eq(evCount("APPLY_DONE"), 0)
      H.eq(State.Busy(), false)
   end)

   H.test("Apply: zweiter Aufruf waehrend Busy ignoriert; nach Abschluss wieder moeglich", function()
      applyScene()
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      settle()
      srv.hold = true
      clearSent()
      State.Apply()
      srv.pump()
      local before = #sent()
      for _ = 1, 3 do
         H.deepEq({ State.Apply() }, { false, "APPLY_REASON_BUSY" })
      end
      srv.pump()
      H.eq(#sent(), before)
      H.eq(evCount("APPLY_STARTED"), 1)
      srv.flush()
      srv.pump()
      srv.flush()
      H.eq(State.Busy(), false)
      srv.hold = false
      -- neue Auswahl -> neuer Stapel
      State.Select(SHOULDER, 211)
      settle()
      H.deepEq({ State.CanApply() }, { true })
   end)

   H.test("Apply: Nichts zu tun -> NONE; keine Befehle, kein Busy", function()
      applyScene()
      H.deepEq({ State.Apply() }, { false, "APPLY_REASON_NONE" })
      H.eq(State.Busy(), false)
      srv.pump()
      H.eq(#sent(), 0)
      H.eq(evCount("APPLY_STARTED"), 0)
   end)

   H.test("Apply: Befehl laesst sich nicht senden (kein Spielername) -> sofortiger Fehlschlag, Stapel laeuft weiter", function()
      applyScene()
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      settle()
      M.world.playerName = ""
      clearLog()
      State.Apply()
      H.eq(State.Busy(), false)                     -- alles sofort fehlgeschlagen
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 0, 2 })
      H.eq(State.PendingCount(), 2)
   end)

   H.test("Apply: waehrend des Stapels geaenderte Auswahl bleibt Pending", function()
      applyScene()
      State.Select(HEAD, 201)
      settle()
      srv.hold = true
      State.Apply()
      srv.pump()
      State.Select(HEAD, 202)                       -- Auswahl aendert sich, Antwort fuer 201 steht noch aus
      srv.flush()
      H.eq(State.Busy(), false)
      H.eq(State.Applied(HEAD), 201)
      H.eq(State.HasPending(HEAD), true)
      H.eq(State.Wanted(HEAD), 202)
   end)

   H.test("Apply: Chatmeldungen nur mit State.chatMessages", function()
      applyScene()
      -- ohne Transmogrifizierer abgelehnt
      State.SetVendor(false)
      State.Select(HEAD, 201)
      settle()
      local n0 = #M.messages
      State.Apply()
      H.eq(#M.messages, n0 + 1)
      H.contains(M.messages[#M.messages], T.L.MSG_NO_VENDOR)
      State.chatMessages = false
      State.Apply()
      H.eq(#M.messages, n0 + 1)
      State.chatMessages = true
      -- Erfolg
      State.SetVendor(true)
      local n1 = #M.messages
      State.Apply()
      srv.pump()
      H.eq(#M.messages, n1 + 1)
      H.contains(M.messages[#M.messages], T.L.MSG_APPLY_OK)
   end)

   -- =======================================================================
   H.section("State: RemoveAll")
   -- =======================================================================

   H.test("RemoveAll: sendet RemoveAll, verwirft Auswahl, Status wird lokal und per Antwort nachgezogen", function()
      applyScene()
      srv.stored[HEAD] = 201
      srv.stored[CHEST] = HIDDEN
      M.ServerMessage(statusMsg(srv.stored))
      H.eq(State.Applied(HEAD), 201)
      State.Select(SHOULDER, 211)
      clearSent()
      clearLog()
      srv.hold = true
      H.eq(State.RemoveAll(), true)
      srv.pump()
      H.deepEq(sent(), { "RemoveAll" })
      H.eq(State.PendingCount(), 0)
      H.eq(State.Applied(HEAD), 0)
      H.eq(State.Applied(CHEST), 0)
      H.eq(State.Applied(LEGS), 0)
      H.eq(evCount("APPLY_STARTED"), 0)             -- kein ApplyTransmogResult erwartet
      srv.flush()                                   -- TransmogStatus:0
      H.eq(State.Applied(HEAD), 0)
      H.eq(State.Busy(), false)
   end)

   H.test("RemoveAll: abgelehnt ohne Transmogrifizierer / beim Anwenden / ohne Server", function()
      applyScene()
      State.SetVendor(false)
      clearSent()
      H.deepEq({ State.RemoveAll() }, { false, "APPLY_REASON_VENDOR" })
      H.eq(#sent(), 0)
      T.DB.Set("allowAnywhere", true)
      H.eq(State.RemoveAll(), true)
      T.DB.Set("allowAnywhere", false)
      -- beim Anwenden
      State.SetVendor(true)
      srv.pump()
      State.Select(HEAD, 201)
      settle()
      srv.hold = true
      State.Apply()
      srv.pump()
      H.deepEq({ State.RemoveAll() }, { false, "APPLY_REASON_BUSY" })
   end)

   -- =======================================================================
   H.section("State: Sammlung, Login-Sweep, Refresh")
   -- =======================================================================

   H.test("CollectionUpdated: State.new je nach Login-Sweep (10 s nach PLAYER_ENTERING_WORLD)", function()
      start()
      -- noch nicht in der Welt: Sweep
      T.enteredWorldAt = nil
      M.ServerMessage("CollectionUpdated:300")
      H.eq(State.new[300], nil)
      H.eq(evCount("COLLECTION_UPDATED"), 1)        -- das Ereignis feuert immer
      H.eq(evLast("COLLECTION_UPDATED")[1], 300)
      H.eq(Net.CollectionState(300), 1)

      -- eben betreten: Sweep (< 10 s)
      T.enteredWorldAt = GetTime()
      M.ServerMessage("CollectionUpdated:301")
      H.eq(State.new[301], nil)
      M.Advance(9.5)
      M.ServerMessage("CollectionUpdated:302")
      H.eq(State.new[302], nil)
      M.Advance(0.6)
      M.ServerMessage("CollectionUpdated:303")
      H.eq(State.new[303], true)
      H.eq(evCount("COLLECTION_UPDATED"), 4)
      -- State.new bleibt dieselbe Tabelle (Filter haelt eine Referenz)
      local ref = State.new
      M.ServerMessage("CollectionUpdated:304")
      H.eq(State.new, ref)
      H.eq(ref[304], true)
   end)

   H.test("CollectionUpdated: Listen werden nach 3 s neu angefordert, wenn das Fenster offen ist", function()
      start()
      local shown = false
      T.UI = T.UI or {}
      T.UI.Window = { IsShown = function() return shown end }
      M.ServerMessage("CollectionUpdated:310")
      M.Advance(3.5)
      H.eq(countSent("GetAvailableTransmogs"), 0)   -- Fenster zu: nicht jetzt
      -- beim naechsten Oeffnen (Refresh) wird nachgeholt
      State.Refresh()
      H.eq(countSent("GetAvailableTransmogs"), 1)
      State.Refresh()
      H.eq(countSent("GetAvailableTransmogs"), 1)   -- nicht mehr veraltet
      -- Fenster offen: automatisch
      shown = true
      M.ServerMessage("CollectionUpdated:311")
      M.Advance(2.5)
      H.eq(countSent("GetAvailableTransmogs"), 1)
      M.Advance(1.0)
      H.eq(countSent("GetAvailableTransmogs"), 2)
      -- Serie von Meldungen -> entprellt zu einer Anfrage
      for id = 320, 330 do
         M.ServerMessage("CollectionUpdated:" .. id)
         M.Advance(0.5)
      end
      H.eq(countSent("GetAvailableTransmogs"), 2)
      M.Advance(3.0)
      H.eq(countSent("GetAvailableTransmogs"), 3)
   end)

   H.test("Refresh: Status immer, Listen nur wenn noetig (neu / veraltet / aelter als 60 s / unfertig)", function()
      start({ server = true })
      State.Refresh(true)
      srv.pump()
      H.eq(State.ListsReady(), true)
      clearSent()
      State.Refresh()
      H.eq(countSent("GetTransmogStatus"), 1)
      H.eq(countSent("GetAvailableTransmogs"), 0)
      M.Advance(30)
      State.Refresh()
      H.eq(countSent("GetAvailableTransmogs"), 0)
      M.Advance(31)
      State.Refresh()
      H.eq(countSent("GetAvailableTransmogs"), 1)
      -- force
      State.Refresh(true)
      H.eq(countSent("GetAvailableTransmogs"), 2)
      -- eine unfertige Liste (Strom begonnen, nie beendet) wird nach 10 s erneut angefordert
      M.ServerMessage("AvailableTransmogs:0:8:5:start")
      H.eq(State.ListsReady(), false)
      M.Advance(5)
      State.Refresh()
      H.eq(countSent("GetAvailableTransmogs"), 2)
      M.Advance(6)
      State.Refresh()
      H.eq(countSent("GetAvailableTransmogs"), 3)
   end)

   H.test("Refresh: Ausruestungswechsel ausserhalb der Ereignisse wird erkannt", function()
      start()
      M.world.equipment[SHOULDER + 1] = nil
      State.Refresh()
      H.eq(State.SlotState(SHOULDER), "EMPTY")
      H.eq(evCount("EQUIPMENT_CHANGED"), 1)
      -- Listen wegen des Wechsels sofort mit angefordert
      H.eq(countSent("GetAvailableTransmogs"), 1)
   end)

   H.test("ABSENT: Meldung im Chat nur, wenn das Fenster sichtbar ist", function()
      start({ alive = false, equip = {} })
      local shown = false
      T.UI = T.UI or {}
      T.UI.Window = { IsShown = function() return shown end }
      Net.RequestStatus()
      local n0 = #M.messages
      M.Advance(9)
      H.eq(Net.state, "ABSENT")
      H.eq(#M.messages, n0)                         -- Fenster zu: stille

      start({ alive = false, equip = {} })
      T.UI = T.UI or {}
      T.UI.Window = { IsShown = function() return true end }
      Net.RequestStatus()
      n0 = #M.messages
      M.Advance(9)
      H.eq(Net.state, "ABSENT")
      H.eq(#M.messages, n0 + 1)
      H.contains(M.messages[#M.messages], T.L.MSG_SERVER_ABSENT)
      -- keine Meldung bei Erholung
      M.ServerMessage("TransmogStatus:0")
      H.eq(#M.messages, n0 + 1)
   end)

   H.test("ABSENT -> OK: meldet sich der Server erst nach der Frist, werden die Listen erneut angefordert", function()
      start({ alive = false })
      State.Refresh(true)
      H.eq(countSent("GetAvailableTransmogs"), 1)
      M.Advance(9)
      H.eq(Net.state, "ABSENT")
      -- das erste Lebenszeichen kommt Sekunden nach der (verlorenen) Listenanfrage
      M.ServerMessage("TransmogStatus:0")
      H.eq(Net.state, "OK")
      H.eq(countSent("GetAvailableTransmogs"), 2, "Listen sofort neu angefordert, nicht erst beim naechsten Oeffnen")
      -- nur einmal je Erholung
      M.ServerMessage("TransmogStatus:0")
      M.Advance(2)
      H.eq(countSent("GetAvailableTransmogs"), 2)
   end)

   H.test("ABSENT -> OK: wurden die Listen eben erst angefordert (< 1 s), kommt keine zweite Anfrage", function()
      start({ alive = false })
      State.Refresh(true)
      M.Advance(9)
      H.eq(Net.state, "ABSENT")
      State.Refresh(true)
      H.eq(countSent("GetAvailableTransmogs"), 2)
      M.Advance(0.3)
      M.ServerMessage("TransmogStatus:0")
      H.eq(Net.state, "OK")
      H.eq(countSent("GetAvailableTransmogs"), 2)
   end)

   H.test("OnOpen: serverOpenAt und SERVER_OPEN", function()
      start({ alive = false })
      H.eq(State.serverOpenAt, nil)
      M.Advance(2)
      local t = GetTime()
      M.ServerMessage("Open")
      H.eq(State.serverOpenAt, t)
      H.eq(evCount("SERVER_OPEN"), 1)
      -- "Open" kommt unaufgefordert (auch bei Transmog.Enable=0): kein Lebenszeichen
      H.eq(Net.state, "UNKNOWN")
   end)

   H.test("SetVendor: Wahrheitswert, VENDOR_CHANGED", function()
      start()
      H.eq(State.atVendor, false)
      State.SetVendor(true)
      H.eq(State.atVendor, true)
      State.SetVendor(nil)
      H.eq(State.atVendor, false)
      State.SetVendor(1)
      H.eq(State.atVendor, true)
      H.eq(evCount("VENDOR_CHANGED"), 3)
      H.eq(evList("VENDOR_CHANGED")[2][1], false)
   end)

   -- =======================================================================
   H.section("Robustheit")
   -- =======================================================================

   -- Eigener, deterministischer Zufallsgenerator (nicht vom globalen Zustand abhaengig)
   local function rng(seed)
      local s = seed
      return function(n)
         s = (s * 1103515245 + 12345) % 2147483648
         return (math.floor(s / 65536) % n) + 1       -- hohe Bits (die niedrigen sind kurzperiodisch)
      end
   end

   local PIECES = {
      "Open", "TransmogStatus", "AvailableTransmogs", "ApplyTransmogResult", "TransmogCost",
      "CollectionUpdated", "CollectionStatus", "start", "end", "0", "1", "2", "4", "14", "18", "19",
      "999999", "-1", "4294967295", "4294967296", "1e5", "0x10", " ", "", ",", "x", "nil", "transmog",
      "\t", "|cffffffff", "%s", "%d", "\0", "9999999999999999999999", "1.5", "-0",
   }

   local function garbage(r)
      local parts = {}
      for i = 1, r(6) do
         parts[i] = PIECES[r(#PIECES)]
      end
      local sep = ({ ":", ":", ":", ",", "" })[r(5)]
      return table.concat(parts, sep)
   end

   local VALID = {
      "Open", "TransmogStatus:0", "TransmogStatus:3:0,100:4,200:14,999999",
      "AvailableTransmogs:0:8:3:start", "AvailableTransmogs:0:8:3:11:22:33",
      "AvailableTransmogs:0:8:3:end", "ApplyTransmogResult:0", "ApplyTransmogResult:1:4,555",
      "ApplyTransmogResult:1:4,0", "TransmogCost:12345:1", "CollectionUpdated:123",
      "CollectionStatus:123:2",
   }

   H.test("Fuzz: zufaelliger Muell an Net.Handle / CHAT_MSG_ADDON wirft nie und erzeugt keine Fehler", function()
      start({ vendor = true })
      setList(HEAD, { 201, 202 })
      State.Select(HEAD, 201)
      local r = rng(20240611)
      for _ = 1, 3000 do
         local msg = garbage(r)
         local ok, res = pcall(Net.Handle, msg)
         H.assert(ok, "Net.Handle warf bei '" .. msg .. "': " .. tostring(res))
         M.Fire("CHAT_MSG_ADDON", "transmog", msg, "WHISPER", "Testplayer")
      end
      -- Nicht-String-Eingaben
      for _, v in ipairs({ true, false, 0, -1, 1e300, {}, function() end }) do
         local ok = pcall(Net.Handle, v)
         H.eq(ok, true)
         M.Fire("CHAT_MSG_ADDON", "transmog", v, "WHISPER", "Testplayer")
         M.Fire("CHAT_MSG_ADDON", v, "Open", v, v)
      end
      H.eq(#H.takeErrors(), 0)
      -- Zustand intakt
      H.eq(State.SlotState(HEAD), "READY")
      H.truthy(State.Cost())
      H.truthy(State.List(HEAD))
   end)

   H.test("Fuzz: verstuemmelte Varianten gueltiger Nachrichten (Kuerzen, Einfuegen, Vertauschen)", function()
      start({ vendor = true })
      local r = rng(987654321)
      local count = 0
      for _, base in ipairs(VALID) do
         for _ = 1, 200 do
            local m = base
            local kind = r(4)
            if kind == 1 then
               m = string.sub(m, 1, r(#m + 1) - 1)                       -- kuerzen
            elseif kind == 2 then
               local at = r(#m + 1)
               m = string.sub(m, 1, at - 1) .. PIECES[r(#PIECES)] .. string.sub(m, at)   -- einfuegen
            elseif kind == 3 then
               local at = r(#m)
               m = string.sub(m, 1, at - 1) .. string.sub(m, at + 1)    -- Zeichen loeschen
            else
               m = m .. ":" .. garbage(r)                               -- anhaengen
            end
            local ok, res = pcall(Net.Handle, m)
            H.assert(ok, "Net.Handle warf bei '" .. m .. "': " .. tostring(res))
            H.assert(type(res) == "boolean", "Rueckgabe kein boolean bei '" .. m .. "'")
            count = count + 1
         end
      end
      H.eq(#H.takeErrors(), 0)
      H.truthy(count > 1000)
   end)

   -- Referenzmodell: unabhaengig aus SPEC 2 / 5.8 geschrieben (Applied, inaktiv, Baseline,
   -- Wanted, Pending, Auswahlregeln). Zufallsfolgen aus Servernachrichten und Aktionen des
   -- Spielers muessen in jedem Schritt dieselben Antworten liefern wie das Modell.
   H.test("Modell: Zufallsfolgen (Status, Stroeme, Ausruestung, Auswahl) gegen ein Referenzmodell", function()
      local MODEL_SLOTS = { 0, 3, 4, 14, 15, 17 }      -- 3 = Hemd (anfangs leer), 17 = Relikt (NEVER)
      local POOL = { 201, 202, 203, 204, 205, 500, 501, HIDDEN }
      local TOTAL_STEPS = 0

      for seed = 1, 6 do
         local equip = { [0] = 101, [4] = 104, [14] = 114, [15] = 115, [17] = 118 }
         start({ equip = equip, vendor = true })
         local r = rng(seed * 7919)

         -- Modell
         local mod = {}
         for _, s in ipairs(MODEL_SLOTS) do
            mod[s] = {
               item = equip[s] or 0, never = (s == 17), applied = 0, sel = nil,
               ready = false, set = {}, streaming = false, newSet = nil,
            }
         end
         local function inactive(m)
            return m.applied ~= 0 and m.applied ~= HIDDEN and m.ready and not m.set[m.applied]
         end
         local function baseline(m) return inactive(m) and 0 or m.applied end
         local function wanted(m) if m.sel ~= nil then return m.sel end return baseline(m) end
         local function pending(m) return m.sel ~= nil and m.sel ~= baseline(m) end
         local function readyForSelect(m) return m.item ~= 0 and not m.never end
         local function canSelect(s, m, id)
            if not readyForSelect(m) then return false end
            if id == HIDDEN then return HIDEABLE[s] == true end
            if id == 0 then return true end
            if m.ready then return m.set[id] == true end
            return true
         end
         local function prune(s, m)
            local sel = m.sel
            if sel == nil then return end
            local drop = false
            if sel == baseline(m) then drop = true
            elseif not readyForSelect(m) then drop = true
            elseif sel ~= 0 and sel ~= HIDDEN and m.ready and not m.set[sel] then drop = true
            elseif sel == HIDDEN and not HIDEABLE[s] then drop = true end
            if drop then m.sel = nil end
         end

         local function snapshot()
            local snap = {}
            for _, s in ipairs(MODEL_SLOTS) do
               snap[s] = { wanted = State.Wanted(s), pending = State.HasPending(s) }
            end
            return snap
         end

         local function compare(step, what)
            local expectPending = {}
            for _, s in ipairs(MODEL_SLOTS) do
               local m = mod[s]
               local tag = "seed " .. seed .. " step " .. step .. " (" .. what .. ") slot " .. s
               H.eq(State.Applied(s), m.applied, tag .. " Applied")
               H.eq(State.IsInactive(s), inactive(m), tag .. " IsInactive")
               H.eq(State.Baseline(s), baseline(m), tag .. " Baseline")
               H.eq(State.Wanted(s), wanted(m), tag .. " Wanted")
               H.eq(State.HasPending(s), pending(m), tag .. " HasPending")
               H.eq(State.List(s).ready, m.ready, tag .. " List.ready")
               local st = (m.item == 0) and "EMPTY" or (m.never and "NEVER" or "READY")
               H.eq(State.SlotState(s), st, tag .. " SlotState")
               for _, id in ipairs(POOL) do
                  local av = (id == HIDDEN) and (HIDEABLE[s] == true) or (m.set[id] == true)
                  H.eq(State.IsAvailable(s, id), av, tag .. " IsAvailable " .. id)
               end
               if pending(m) then expectPending[#expectPending + 1] = s end
            end
            H.deepEq(State.PendingSlots(), expectPending, "seed " .. seed .. " step " .. step .. " PendingSlots")
            H.eq(State.PendingCount(), #expectPending, "PendingCount")
         end

         -- Ereignis-Invariante: aendert sich Wanted/Pending eines Slots, muss ein Ereignis kommen,
         -- das die Oberflaeche zum Neuzeichnen bringt; WANTED_CHANGED(slot) nur bei echter Aenderung.
         local REDRAW = { WANTED_CHANGED = true, STATUS_CHANGED = true, LIST_READY = true,
            LIST_PROGRESS = true, EQUIPMENT_CHANGED = true }
         local function checkEvents(step, what, before)
            for _, s in ipairs(MODEL_SLOTS) do
               local after = { wanted = State.Wanted(s), pending = State.HasPending(s) }
               if after.wanted ~= before[s].wanted or after.pending ~= before[s].pending then
                  local covered = false
                  for _, e in ipairs(log) do
                     if REDRAW[e.name] and (e[1] == s or e[1] == nil or e.name == "STATUS_CHANGED") then
                        covered = true
                     end
                  end
                  H.truthy(covered, "seed " .. seed .. " step " .. step .. " (" .. what .. ") slot " .. s
                     .. ": Wanted/Pending geaendert ohne Ereignis")
               end
            end
            for _, e in ipairs(evList("WANTED_CHANGED")) do
               local s = e[1]
               if s ~= nil and mod[s] then
                  local changed = before[s].wanted ~= State.Wanted(s) or before[s].pending ~= State.HasPending(s)
                  -- ein WANTED_CHANGED(slot) ohne sichtbare Aenderung ist nur bei Auswahlwechsel
                  -- zwischen zwei Pending-Werten sinnvoll; hier genuegt: es muss eine Aenderung geben
                  H.truthy(changed, "seed " .. seed .. " step " .. step .. " (" .. what
                     .. ") WANTED_CHANGED(" .. s .. ") ohne Aenderung")
               end
            end
         end

         local function pick(list) return list[r(#list)] end
         local streamOpen = {}       -- Slots mit geoeffnetem Strom (Chunks/Ende erlaubt)

         for step = 1, 250 do
            TOTAL_STEPS = TOTAL_STEPS + 1
            local what
            local slot = pick(MODEL_SLOTS)
            local m = mod[slot]
            local before = snapshot()
            clearLog()
            local kind = r(12)
            if kind <= 2 then
               -- Status
               local map = {}
               local n = r(3) - 1
               for _ = 1, n do
                  map[pick(MODEL_SLOTS)] = pick(POOL)
               end
               what = "status"
               M.ServerMessage(statusMsg(map))
               for _, s in ipairs(MODEL_SLOTS) do mod[s].applied = map[s] or 0 end
               for _, s in ipairs(MODEL_SLOTS) do prune(s, mod[s]) end
            elseif kind == 3 then
               what = "listStart"
               M.ServerMessage("AvailableTransmogs:" .. slot .. ":8:3:start")
               m.streaming = true
               m.set = {}
               m.ready = false
               streamOpen[slot] = true
            elseif kind == 4 then
               what = "listChunk"
               local ids = {}
               for _ = 1, r(3) do ids[#ids + 1] = pick({ 201, 202, 203, 204, 205, 500, 501 }) end
               M.ServerMessage("AvailableTransmogs:" .. slot .. ":8:3:" .. table.concat(ids, ":"))
               if m.streaming then
                  for _, id in ipairs(ids) do m.set[id] = true end
               end
            elseif kind == 5 then
               what = "listEnd"
               M.ServerMessage("AvailableTransmogs:" .. slot .. ":8:3:end")
               if m.streaming then
                  m.streaming = false
                  m.ready = true
                  prune(slot, m)
               end
            elseif kind == 6 then
               -- kompletter Strom am Stueck
               what = "fullList"
               local ids = {}
               for _, id in ipairs({ 201, 202, 203, 204, 205, 500, 501 }) do
                  if r(2) == 1 then ids[#ids + 1] = id end
               end
               deliver(listMsgs(slot, ids, 8))
               m.set = {}
               for _, id in ipairs(ids) do m.set[id] = true end
               m.streaming = false
               m.ready = true
               prune(slot, m)
            elseif kind <= 9 then
               what = "select"
               local id = (r(6) == 1) and 0 or pick(POOL)
               local expect = canSelect(slot, m, id)
               local got = State.Select(slot, id)
               H.eq(got, expect, "seed " .. seed .. " step " .. step .. " Select(" .. slot .. "," .. id .. ")")
               if expect then
                  if id == baseline(m) then m.sel = nil else m.sel = id end
               end
            elseif kind == 10 then
               what = "toggle"
               State.Toggle(slot)
               if pending(m) then
                  m.sel = nil
               elseif baseline(m) ~= 0 and canSelect(slot, m, 0) then
                  m.sel = 0
               end
            elseif kind == 11 then
               what = "equipment"
               if slot ~= 17 then
                  local newId = pick({ 0, 101, 104, 109 })
                  M.world.equipment[slot + 1] = (newId ~= 0) and newId or nil
                  if newId ~= m.item then
                     m.item = newId
                     m.ready = false
                     m.sel = nil
                  end
                  M.Fire("PLAYER_EQUIPMENT_CHANGED", slot + 1, newId ~= 0)
               end
            else
               what = "discard"
               State.Discard(slot)
               m.sel = nil
            end
            compare(step, what)
            checkEvents(step, what, before)
            -- die Kostenabfrage-Zeitgeber ablaufen lassen, damit nichts liegen bleibt
            if step % 25 == 0 then M.Advance(0.6) end
         end
      end
      H.eq(#H.takeErrors(), 0)
      H.truthy(TOTAL_STEPS == 1500)
   end)

   -- Kosten ueber zufaellige Auswahlen und zufaellig verzoegerte Antworten: ist Cost() "valid",
   -- muss der Betrag zur AKTUELLEN Auswahl passen; nach Ruhe muss er immer gueltig und richtig sein.
   H.test("Modell: Kosten bleiben ueber Zufallsfolgen mit verzoegerten Antworten korrekt", function()
      local SLOTS = { 0, 2, 4, 6, 14, 15 }
      for seed = 1, 6 do
         start({ server = true, vendor = true })
         srv.priceFn = function(id) return id end          -- Preis = ItemId: jede Verwechslung faellt auf
         for i, slot in ipairs(SLOTS) do
            srv.valid[slot] = { 200 + i * 10, 201 + i * 10, 202 + i * 10, 203 + i * 10 }
         end
         State.Refresh(true)
         srv.pump()
         local r = rng(seed * 104729)
         srv.hold = true

         local function expected()
            local sum, paid = 0, false
            for _, slot in ipairs(State.PendingSlots()) do
               local w = State.Wanted(slot)
               if w ~= 0 and w ~= HIDDEN then
                  sum = sum + w
                  paid = true
               end
            end
            return sum, paid
         end

         local function checkNow(tag)
            local c = State.Cost()
            local sum, paid = expected()
            if not paid then
               H.eq(c.valid, true, tag .. " ohne kostenpflichtige Slots gueltig")
               H.eq(c.copper, 0, tag)
               H.eq(c.pending, false, tag)
            elseif c.valid then
               H.eq(c.copper, sum, tag .. " gueltiger Betrag passt zur aktuellen Auswahl")
            end
         end

         for step = 1, 160 do
            local slot = SLOTS[r(#SLOTS)]
            local kind = r(10)
            if kind <= 5 then
               local list = srv.valid[slot]
               State.Select(slot, list[r(#list)])
            elseif kind == 6 then
               State.Select(slot, HIDDEN)
            elseif kind == 7 then
               State.Discard(slot)
            elseif kind == 8 then
               State.Select(slot, 0)
            end
            -- zufaellig Zeit vergehen lassen, Befehle abholen, Antworten ausliefern
            local dt = ({ 0, 0.1, 0.3, 0.6, 1.0 })[r(5)]
            if dt > 0 then M.Advance(dt) end
            srv.pump()
            if r(3) == 1 then
               srv.flush()
               srv.pump()
            end
            checkNow("seed " .. seed .. " step " .. step)
         end

         -- Ruhe: alle Antworten ausliefern, Zeitgeber ablaufen lassen
         for _ = 1, 4 do
            M.Advance(1.0)
            srv.pump()
            srv.flush()
         end
         local c = State.Cost()
         local sum, paid = expected()
         local tag = "seed " .. seed .. " Ruhe"
         H.eq(c.pending, false, tag .. " nichts mehr ausstehend")
         H.eq(c.valid, true, tag .. " gueltig")
         H.eq(c.copper, paid and sum or 0, tag .. " Betrag")
      end
      H.eq(#H.takeErrors(), 0)
   end)

   -- Anwenden mit zufaelligen Serverantworten (Erfolg, Ablehnung, spaet, verloren): am Ende muss
   -- State.Applied dem Server entsprechen (Resync), kein Stapel haengt, Ereigniszahlen stimmen.
   H.test("Modell: Anwenden mit abgelehnten, verzoegerten und verlorenen Antworten bleibt konsistent", function()
      local SLOTS = { 0, 2, 4, 6, 14, 15 }
      local totalBatches = 0
      for seed = 1, 8 do
         start({ server = true, vendor = true })
         for i, slot in ipairs(SLOTS) do
            srv.valid[slot] = { 200 + i * 10, 201 + i * 10, 202 + i * 10 }
         end
         State.Refresh(true)
         srv.pump()
         local r = rng(seed * 15485863)
         local started, done, progressTotal, opsTotal = 0, 0, 0, 0

         for _, name in ipairs({ "APPLY_STARTED", "APPLY_DONE", "APPLY_PROGRESS" }) do
            T.Events.On(name, function(...)
               local a1, a2 = ...
               if name == "APPLY_STARTED" then
                  started = started + 1
                  opsTotal = opsTotal + a1
               elseif name == "APPLY_DONE" then
                  done = done + 1
               else
                  progressTotal = progressTotal + 1
               end
            end)
         end

         for round = 1, 12 do
            -- Auswahlen
            for _, slot in ipairs(SLOTS) do
               if r(2) == 1 then
                  local list = srv.valid[slot]
                  local k = r(5)
                  if k <= 3 then
                     State.Select(slot, list[r(#list)])
                  elseif k == 4 then
                     State.Select(slot, 0)
                  else
                     State.Select(slot, HIDDEN)
                  end
               end
            end
            -- Server verhaelt sich zufaellig
            srv.hold = false
            srv.money = 1000000000
            M.Advance(0.3)
            srv.pump()
            srv.flush()
            srv.pump()
            -- der Server ist jetzt knapp bei Kasse (der Client weiss es nicht) und antwortet zaehe
            if r(4) == 1 then srv.money = 0 end
            srv.hold = (r(3) == 1)
            local ok = State.Apply()
            local waited = 0
            while State.Busy() and waited < 90 do
               local dt = ({ 0.1, 0.5, 2, 6 })[r(4)]
               M.Advance(dt)
               waited = waited + dt
               srv.pump()
               if r(2) == 1 then
                  srv.flush()
                  srv.pump()
               end
            end
            H.eq(State.Busy(), false, "seed " .. seed .. " round " .. round .. ": Stapel haengt")
            srv.hold = false
            srv.flush()
            srv.pump()
            totalBatches = totalBatches + (ok and 1 or 0)
         end

         -- Resync
         srv.hold = false
         srv.money = 1000000000
         M.Advance(6)
         srv.pump()
         srv.flush()
         State.Refresh(true)
         srv.pump()
         M.Advance(1)
         srv.pump()
         for _, slot in ipairs(SLOTS) do
            H.eq(State.Applied(slot), srv.stored[slot] or 0, "seed " .. seed .. " slot " .. slot .. " Applied == Server")
         end
         H.eq(started, done, "seed " .. seed .. ": jedes APPLY_STARTED hat ein APPLY_DONE")
         H.eq(progressTotal, opsTotal, "seed " .. seed .. ": je Operation genau ein APPLY_PROGRESS")
         -- Auswahlen, die dem Server-Stand entsprechen, duerfen nicht mehr als Pending gelten
         for _, slot in ipairs(State.PendingSlots()) do
            H.neq(State.Wanted(slot), State.Baseline(slot), "Pending == Baseline")
         end
      end
      H.truthy(totalBatches > 10)
      H.eq(#H.takeErrors(), 0)
   end)

   -- Ganze Sitzungen: Auswahl, Anwenden, Ausruestungswechsel, Sammlung, RemoveAll, Fenster auf/zu,
   -- verzoegerte Serverantworten. Invarianten in jedem Schritt, Konsistenz mit dem Server am Ende.
   H.test("Modell: Zufallssitzungen mit Ausruestungswechsel, Sammlung und RemoveAll bleiben konsistent", function()
      local SLOTS = { 0, 2, 4, 6, 14, 15 }
      local ITEM_A, ITEM_B = 101, 109
      for seed = 1, 6 do
         start({ server = true, vendor = true, equip = { [0] = 101, [2] = 102, [4] = 104, [6] = 106, [14] = 114, [15] = 115 } })
         local r = rng(seed * 2750159)
         local windowShown = true
         T.UI = T.UI or {}
         T.UI.Window = { IsShown = function() return windowShown end }
         srv.priceFn = function(id) return id % 97 + 1 end

         -- Der Server haelt je Slot zwei Listen (zum Gegenstand A bzw. B) und gibt sie je nach
         -- ausgeruestetem Gegenstand heraus.
         local listA, listB, itemOf = {}, {}, {}
         for i, slot in ipairs(SLOTS) do
            listA[slot] = { 200 + i * 10, 201 + i * 10, 202 + i * 10 }
            listB[slot] = { 202 + i * 10, 203 + i * 10, 204 + i * 10 }
            itemOf[slot] = "A"
            srv.valid[slot] = listA[slot]
         end
         local pool = { 0, HIDDEN }
         for _, slot in ipairs(SLOTS) do
            for _, id in ipairs(listA[slot]) do pool[#pool + 1] = id end
            for _, id in ipairs(listB[slot]) do pool[#pool + 1] = id end
         end

         State.Refresh(true)
         srv.pump()
         srv.hold = (r(3) == 1)

         local function invariants(tag)
            for _, s2 in ipairs(State.PendingSlots()) do
               H.eq(State.SlotState(s2), "READY", tag .. " Pending nur in READY-Slots")
               H.neq(State.Wanted(s2), State.Baseline(s2), tag .. " Pending ~= Baseline")
            end
            for _, s2 in ipairs(SLOTS) do
               if State.HasPending(s2) then
                  local w = State.Wanted(s2)
                  H.truthy(w == 0 or w == HIDDEN or State.IsAvailable(s2, w) or not State.List(s2).ready,
                     tag .. " Auswahl steht in der fertigen Liste")
               end
            end
            local c = State.Cost()
            H.truthy(type(c.copper) == "number" and c.copper >= 0, tag .. " Kosten")
         end

         for step = 1, 200 do
            local tag = "seed " .. seed .. " step " .. step
            local slot = SLOTS[r(#SLOTS)]
            local kind = r(16)
            if kind <= 5 then
               State.Select(slot, pool[r(#pool)])
            elseif kind == 6 then
               State.Discard(slot)
            elseif kind == 7 then
               State.Toggle(slot)
            elseif kind <= 9 then
               State.Apply()
            elseif kind == 10 then
               -- Ausruestungswechsel: der Server wechselt seine Liste mit
               local which = r(2) == 1 and "A" or "B"
               itemOf[slot] = which
               srv.valid[slot] = (which == "A") and listA[slot] or listB[slot]
               M.world.equipment[slot + 1] = (which == "A") and ITEM_A or ITEM_B
               M.Fire("PLAYER_EQUIPMENT_CHANGED", slot + 1, 1)
            elseif kind == 11 then
               M.ServerMessage("CollectionUpdated:" .. (300 + r(30)))
            elseif kind == 12 then
               windowShown = not windowShown
               if windowShown then State.Refresh() end
            elseif kind == 13 then
               if r(6) == 1 then State.RemoveAll() end
            elseif kind == 14 then
               State.Refresh()
            elseif kind == 15 then
               srv.hold = (r(3) == 1)
               if not srv.hold then srv.flush() end
            end
            local dt = ({ 0, 0.05, 0.3, 1, 3, 6 })[r(6)]
            if dt > 0 then M.Advance(dt) end
            srv.pump()
            if r(2) == 1 then
               srv.flush()
               srv.pump()
            end
            invariants(tag)
         end

         -- Ruhe und Abgleich
         srv.hold = false
         srv.money = 1000000000
         for _ = 1, 6 do
            M.Advance(5)
            srv.pump()
            srv.flush()
            srv.pump()
         end
         H.eq(State.Busy(), false, "seed " .. seed .. ": Stapel haengt")
         windowShown = true
         State.Refresh(true)
         srv.pump()
         M.Advance(1)
         srv.pump()
         for _, slot in ipairs(SLOTS) do
            H.eq(State.Applied(slot), srv.stored[slot] or 0, "seed " .. seed .. " slot " .. slot .. " Applied == Server")
            H.eq(State.List(slot).ready, true, "seed " .. seed .. " slot " .. slot .. " Liste fertig")
            H.deepEq(State.List(slot).ids, srv.valid[slot], "seed " .. seed .. " slot " .. slot .. " Liste == Server")
         end
         M.Advance(30)
         srv.pump()
         H.eq(T.Util.TimerCount(), 0, "seed " .. seed .. ": Timer liegengeblieben")
         local c = State.Cost()
         H.eq(c.pending, false, "seed " .. seed .. ": Kosten ausstehend")
      end
      H.eq(#H.takeErrors(), 0)
   end)

   -- Der Server antwortet SYNCHRON innerhalb von SendAddonMessage (Wiedereintritt): Cost, Apply, Refresh.
   H.test("Wiedereintritt: Antworten innerhalb von SendAddonMessage werden korrekt verarbeitet", function()
      start({ server = true, vendor = true })
      for i, slot in ipairs({ 0, 2, 4, 6 }) do
         srv.valid[slot] = { 200 + i * 10, 201 + i * 10 }
      end
      srv.priceFn = function(id) return id end
      local orig = _G.SendAddonMessage
      local inSend = 0
      _G.SendAddonMessage = function(prefix, msg, channel, target)
         orig(prefix, msg, channel, target)
         if prefix == "transmog" then
            inSend = inSend + 1
            srv.handle(msg)
            inSend = inSend - 1
         end
      end
      -- alles ohne pump: der Server antwortet sofort
      State.Refresh(true)
      H.eq(State.ListsReady(), true)
      State.Select(0, 210)
      State.Select(2, 221)
      State.Select(4, 230)
      M.Advance(0.3)
      H.deepEq(State.Cost(), { copper = 210 + 221 + 230, canPurchase = true, valid = true, pending = false })
      H.deepEq({ State.CanApply() }, { true })
      State.Apply()
      H.eq(State.Busy(), false)                      -- alles synchron erledigt
      H.eq(State.Applied(0), 210)
      H.eq(State.Applied(2), 221)
      H.eq(State.Applied(4), 230)
      H.eq(State.PendingCount(), 0)
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 3, 0 })
      H.eq(evCount("APPLY_PROGRESS"), 3)
      -- mit Ablehnung mittendrin
      srv.valid[2] = {}
      State.Select(0, 211)
      State.Select(2, 220)
      State.Select(4, 231)
      M.Advance(0.3)
      State.Apply()
      H.eq(State.Busy(), false)
      H.deepEq(evLast("APPLY_DONE"), { name = "APPLY_DONE", n = 2, 2, 1 })
      H.eq(State.Applied(2), 221)
      H.eq(State.HasPending(2), true)
      _G.SendAddonMessage = orig
   end)

   -- Login-Szene: der Server schickt CollectionUpdated fuer ALLE Gegenstaende, dazu 14 grosse Listen.
   H.test("Login-Sturm: tausende CollectionUpdated + grosse Listen sind schnell, ohne Timer-Wucherung und ohne 'neu'", function()
      start({ server = true, alive = false })
      T.enteredWorldAt = nil                         -- noch nicht in der Welt: Sweep
      for _, slot in ipairs(SERVER_SLOTS) do
         srv.valid[slot] = range(1000 + slot * 1000, 1000 + slot * 1000 + 299)
      end
      local t0 = os.clock()
      -- 3000 CollectionUpdated (wie beim Login-Sweep), mit wenig Spielzeit dazwischen
      for id = 5000, 7999 do
         M.ServerMessage("CollectionUpdated:" .. id)
         if id % 500 == 0 then M.Advance(0.5) end
      end
      T.enteredWorldAt = GetTime()
      State.Refresh(true)
      srv.pump()
      local dt = os.clock() - t0
      H.truthy(dt < 3, "zu langsam: " .. dt .. " s")
      H.eq(next(State.new), nil)                     -- nichts davon gilt als "neu"
      H.eq(State.ListsReady(), true)
      for _, slot in ipairs(SERVER_SLOTS) do
         H.eq(#State.List(slot).ids, 300)
      end
      -- hoechstens eine Handvoll Timer (entprellt), nicht einer je Nachricht
      H.truthy(T.Util.TimerCount() < 10, "Timer: " .. T.Util.TimerCount())
      H.eq(Net.CollectionState(5000), 1)
      H.eq(Net.CollectionState(7999), 1)
      M.Advance(30)
      H.eq(T.Util.TimerCount(), 0)
   end)

   H.test("Fuzz: State.On* mit beliebigen Argumenten wirft nie", function()
      start({ vendor = true })
      local junk = { nil, true, false, 0, -1, 1.5, 4294967296, 1e300, -1e300, "", "x", "5", "0",
         {}, { 1, 2, "x" }, { [0] = 5 }, { [4] = "x" }, function() end }
      local nJunk = 18
      local function arg(i) return junk[i] end   -- Index 1 = nil
      local fnNames = { "OnOpen", "OnStatus", "OnListStart", "OnListChunk", "OnListEnd", "OnCost",
         "OnApplyResult", "OnCollectionUpdated", "OnCollectionStatus", "Select", "Discard", "Toggle",
         "SetMany", "List", "IsAvailable", "Applied", "Baseline", "Wanted", "HasPending", "IsInactive",
         "SlotState", "Equipped" }
      for _, name in ipairs(fnNames) do
         local fn = State[name]
         H.truthy(fn, name)
         for i = 1, nJunk do
            for j = 1, nJunk, 3 do
               local ok, err = pcall(fn, arg(i), arg(j), arg(i))
               H.assert(ok, name .. " warf: " .. tostring(err))
            end
         end
      end
      H.eq(#H.takeErrors(), 0)
      -- danach noch benutzbar
      setList(HEAD, { 201 })
      H.eq(State.Select(HEAD, 201), true)
   end)

   H.test("Handlerfehler: ein werfender Abonnent bricht State nicht ab", function()
      start({ vendor = true })
      H.allowErrors()
      T.Events.On("WANTED_CHANGED", function() error("boom") end)
      T.Events.On("LIST_READY", function() error("boom2") end)
      T.Events.On("STATUS_CHANGED", function() error("boom3") end)
      setList(HEAD, { 201, 202 })
      H.eq(State.List(HEAD).ready, true)
      H.eq(State.Select(HEAD, 201), true)
      H.eq(State.HasPending(HEAD), true)
      setApplied({ [CHEST] = 500 })
      H.eq(State.Applied(CHEST), 500)
      local errs = H.takeErrors()
      H.truthy(#errs >= 3)
   end)

   H.test("Net: ein werfendes State.On* wird gemeldet, Net.Handle wirft nicht und faehrt fort", function()
      start({ alive = false })
      H.allowErrors()
      T.State.OnStatus = function() error("kaputt") end
      local ok, res = pcall(Net.Handle, "TransmogStatus:0")
      H.eq(ok, true)
      H.eq(res, true)
      H.eq(Net.state, "OK")
      H.eq(#H.takeErrors(), 1)
   end)

   H.test("Net: ein werfendes State.OnOpen/OnCollectionUpdated wird gemeldet, ohne Lebenszeichen", function()
      start({ alive = false })
      H.allowErrors()
      T.State.OnOpen = function() error("kaputt") end
      T.State.OnCollectionUpdated = function() error("kaputt2") end
      local ok, res = pcall(Net.Handle, "Open")
      H.eq(ok, true)
      H.eq(res, true)
      ok, res = pcall(Net.Handle, "CollectionUpdated:123")
      H.eq(ok, true)
      H.eq(res, true)
      H.eq(Net.state, "UNKNOWN")
      H.eq(Net.receivedCount, 2, "werden trotzdem gezaehlt")
      H.eq(#H.takeErrors(), 2)
   end)

   H.test("Zeitgeber: nach Abschluss aller Vorgaenge bleibt kein Timer und kein OnUpdate-Frame sichtbar", function()
      applyScene()
      M.Advance(30)                                  -- Ruhezustand als Vergleich
      local function visibleUpdateFrames()
         local set = {}
         for _, f in ipairs(M.frames) do
            local ok, shown = pcall(function() return f:IsShown() end)
            local ok2, onUpdate = pcall(function() return f:GetScript("OnUpdate") end)
            if ok and ok2 and onUpdate and shown then set[f] = true end
         end
         return set
      end
      H.eq(T.Util.TimerCount(), 0)
      local baseline = visibleUpdateFrames()
      State.Select(HEAD, 201)
      State.Select(CHEST, 204)
      settle()
      State.Apply()
      srv.pump()
      srv.pump()
      State.RemoveAll()
      srv.pump()
      M.ServerMessage("CollectionUpdated:2000")
      M.Advance(30)
      H.eq(State.Busy(), false)
      H.eq(T.Util.TimerCount(), 0)
      -- Timer-Treiber und Item-Abfrage haben sich wieder versteckt: nichts Neues sichtbar
      for f in pairs(visibleUpdateFrames()) do
         H.truthy(baseline[f], "ein OnUpdate-Frame blieb sichtbar, obwohl nichts mehr ansteht")
      end
   end)

   H.test("Locale: alle von State/CanApply benutzten Schluessel sind in enUS vorhanden, Platzhalter stimmen", function()
      start()
      local L = T.L
      local keys = { "APPLY_REASON_NONE", "APPLY_REASON_VENDOR", "APPLY_REASON_BUSY",
         "APPLY_REASON_COST_PENDING", "APPLY_REASON_MONEY", "APPLY_REASON_SERVER",
         "MSG_APPLY_OK", "MSG_APPLY_DONE", "MSG_APPLY_SLOT_FAILED", "MSG_SERVER_ABSENT", "MSG_NO_VENDOR" }
      for _, k in ipairs(keys) do
         local v = rawget(L, k)
         H.eq(type(v), "string", k)
         H.neq(v, k, k)
      end
      H.eq(select(2, string.gsub(L.MSG_APPLY_DONE, "%%d", "")), 2)
      H.eq(select(2, string.gsub(L.MSG_APPLY_SLOT_FAILED, "%%s", "")), 1)
   end)
end
