-- tests/test_fix_core-net.lua
-- ---------------------------------------------------------------------------
-- Regressionstests zu bestaetigten Befunden in Core\Net.lua:
--
--   flow-2    Transmog.Enable=0: der Server beantwortet nichts, schickt aber
--             weiter "Open" (NPC-Gossip) und "CollectionUpdated" (Loot-Haken).
--             Beide zaehlen NICHT als Lebenszeichen: ABSENT wird erreicht und
--             bleibt. Sie werden trotzdem an State ausgeliefert (Gossip-Takeover).
--   flow-4    "nicht gesammelt" (0) im Sitzungs-Cache gilt nur 45 s; danach
--             ist der Stand unbekannt und wird neu erfragt. 1 und 2 bleiben.
--   robust-2  Servernachrichten fremder Spieler (Absender ~= Spieler) und aus
--             Gruppenkanaelen werden verworfen; Net.checkSender (Standard AUS) ist optional.
--
-- Aufruf:  cd <Addon>;  luajit tests/run.lua fix_core-net
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local Fixtures = require("fixtures")

   local ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

   -- Server MIT Modul, aber Transmog.Enable=0: jeder Befehl wird nur als Echo
   -- (Player::Whisper an sich selbst) zurueckgefluestert, beantwortet wird nichts.
   local function installEcho()
      local orig = rawget(_G, "SendAddonMessage")
      rawset(_G, "SendAddonMessage", function(prefix, msg, channel, target)
         orig(prefix, msg, channel, target)
         M.Fire("CHAT_MSG_ADDON", prefix, msg, "WHISPER", target)
      end)
   end

   -- =======================================================================
   H.section("flow-2: Transmog.Enable=0 (Open und CollectionUpdated sind kein Lebenszeichen)")
   -- =======================================================================

   H.test("Enable=0: nur Echo, dann Open und CollectionUpdated -> ABSENT bleibt, Raster ABSENT, Anwenden gesperrt", function()
      local T = Fixtures.Boot(H, {})
      installEcho()
      M.Fire("PLAYER_ENTERING_WORLD")
      Fixtures.Settle(T, 12, 0.1)
      H.eq(T.Net.state, "ABSENT", "nach der Frist")

      -- der Spieler spricht den NPC an: der Server schickt (trotz Enable=0) Open + Gossip
      local window = Fixtures.OpenAtNpc(T)
      H.truthy(window, "Open erreicht Boot: das Fenster ersetzt das Gossip-Fenster")
      H.eq(T.State.openedByNpc, true)
      H.eq(T.UI.Window.IsShown() and true or false, true)
      Fixtures.Settle(T, 30, 0.1)
      H.eq(T.Net.state, "ABSENT", "Open ist kein Lebenszeichen")
      H.eq(T.UI.Grid.mode, "ABSENT", "Raster zeigt 'Server antwortet nicht' statt ewig zu laden")
      H.eq(T.State.ListsReady(), false)

      -- ein gelooteter Gegenstand: CollectionUpdated kommt trotzdem
      local id = Fixtures.Item(T, "e_head_plate")
      M.ServerMessage("CollectionUpdated:" .. id)
      Fixtures.Settle(T, 10, 0.1)
      H.eq(T.Net.state, "ABSENT", "CollectionUpdated ist kein Lebenszeichen")
      H.eq(T.Net.CollectionState(id), 1, "wird aber ausgeliefert und gemerkt")
      H.eq(T.State.new[id], true, "State.OnCollectionUpdated lief")

      -- Alles entfernen und Anwenden nennen den Grund, statt ins Leere zu senden
      local ok, why = T.State.CanRemoveAll()
      H.eq(ok, false)
      H.eq(why, "APPLY_REASON_SERVER")
      ok, why = T.State.CanApply()
      H.eq(ok, false)
      H.eq(why, "APPLY_REASON_SERVER")
   end)

   H.test("Enable=0: ein spaeteres Open/CollectionUpdated hebt ABSENT nicht auf, die erste Antwort schon", function()
      local T = Fixtures.Boot(H, {})
      installEcho()
      M.Fire("PLAYER_ENTERING_WORLD")
      Fixtures.Settle(T, 12, 0.1)
      H.eq(T.Net.state, "ABSENT")

      local states = {}
      T.Events.On("SERVER_STATE", function(s) states[#states + 1] = s end, states)

      M.ServerMessage("Open")
      M.ServerMessage("CollectionUpdated:41011")
      M.ServerMessage("Open")
      H.eq(T.Net.state, "ABSENT")
      H.eq(#states, 0, "kein SERVER_STATE-Wechsel")

      -- der Server wird doch noch geladen und antwortet: das ist ein Lebenszeichen
      M.ServerMessage("TransmogStatus:0")
      H.eq(T.Net.state, "OK")
      H.eq(#states, 1)
      H.eq(states[1], "OK")
   end)

   H.test("Net: Open/CollectionUpdated vor der ersten Anfrage verhindern ABSENT nicht (Login-Sweep)", function()
      local T = Fixtures.Boot(H, { enterWorld = false })
      local Net = T.Net
      H.eq(Net.state, "UNKNOWN")
      -- Login-Sweep des Servers (Enable-unabhaengig), noch bevor das Addon etwas fragt
      for id = 41001, 41020 do M.ServerMessage("CollectionUpdated:" .. id) end
      M.ServerMessage("Open")
      H.eq(Net.state, "UNKNOWN", "weder OK noch ABSENT ohne Anfrage")
      H.eq(Net.receivedCount, 21, "werden trotzdem gezaehlt (Debug-Ausgabe)")
      H.truthy(Net.lastReceiveAt)

      -- danach die erste Anfrage; der Server (Enable=0) schweigt -> nach 8 s ABSENT
      Net.RequestStatus()
      M.Advance(7.5)
      H.eq(Net.state, "UNKNOWN")
      M.Advance(1.0)
      H.eq(Net.state, "ABSENT")
   end)

   H.test("Net: Open/CollectionUpdated wirken weiter auf State (SERVER_OPEN, COLLECTION_UPDATED, Cache)", function()
      local T = Fixtures.Boot(H, { enterWorld = false })
      local Net, State = T.Net, T.State
      local log = {}
      T.Events.On("SERVER_OPEN", function() log[#log + 1] = "SERVER_OPEN" end, log)
      T.Events.On("COLLECTION_UPDATED", function(id) log[#log + 1] = "COLLECTION_UPDATED:" .. tostring(id) end, log)
      H.eq(Net.Handle("Open"), true)
      H.eq(Net.Handle("CollectionUpdated:123"), true)
      H.truthy(State.serverOpenAt)
      H.eq(Net.CollectionState(123), 1)
      H.deepEq(log, { "SERVER_OPEN", "COLLECTION_UPDATED:123" })
      -- verstuemmelt: weiterhin verworfen (false, nichts gezaehlt)
      local before = Net.receivedCount
      H.eq(Net.Handle("CollectionUpdated:abc"), false)
      H.eq(Net.Handle("CollectionUpdated:0"), false)
      H.eq(Net.receivedCount, before)
      H.eq(#H.takeErrors(), 0)
   end)

   -- =======================================================================
   H.section("flow-4: Cache fuer 'nicht gesammelt' laeuft nach 45 s ab")
   -- =======================================================================

   local function start()
      local T = Fixtures.Boot(H, { enterWorld = false })
      M.ClearSent()
      return T
   end

   H.test("0 gilt 45 s; danach unbekannt, genau eine neue Abfrage, neue Antwort stempelt neu", function()
      local T = start()
      local Net = T.Net
      H.eq(Net.QueryCollection(5001), nil)
      H.eq(M.CountSent("GetCollectionStatus:5001"), 1)
      M.ServerMessage("CollectionStatus:5001:0")
      H.eq(Net.CollectionState(5001), 0)

      M.Advance(44)
      H.eq(Net.CollectionState(5001), 0, "kurz vor Ablauf noch bekannt")
      H.eq(Net.QueryCollection(5001), 0)
      H.eq(M.CountSent("GetCollectionStatus:5001"), 1, "innerhalb der Frist keine neue Abfrage")

      M.Advance(2)
      H.eq(Net.CollectionState(5001), nil, "abgelaufen: unbekannt")
      H.eq(Net.QueryCollection(5001), nil)
      H.eq(M.CountSent("GetCollectionStatus:5001"), 2, "neue Abfrage")
      H.eq(Net.QueryCollection(5001), nil)
      H.eq(M.CountSent("GetCollectionStatus:5001"), 2, "laufende Abfrage wird nicht doppelt gesendet")

      -- Antwort 0: wieder fuer 45 s bekannt, der Zeitstempel ist neu
      M.ServerMessage("CollectionStatus:5001:0")
      H.eq(Net.CollectionState(5001), 0)
      M.Advance(30)
      H.eq(Net.CollectionState(5001), 0, "30 s nach der neuen Antwort")
      M.Advance(16)
      H.eq(Net.CollectionState(5001), nil, "46 s nach der neuen Antwort")
   end)

   H.test("Anderer Zugang des Kontos sammelt: die neue Abfrage liefert 1, danach bleibt es 1", function()
      local T = start()
      local Net = T.Net
      Net.QueryCollection(5002)
      M.ServerMessage("CollectionStatus:5002:0")
      H.eq(Net.CollectionState(5002), 0)
      -- ein Begleiter-Zugang des Kontos sammelt; dieser Client bekommt kein CollectionUpdated
      M.Advance(60)
      H.eq(Net.QueryCollection(5002), nil)
      H.eq(M.CountSent("GetCollectionStatus:5002"), 2)
      local events = {}
      T.Events.On("COLLECTION_STATUS", function(id, s) events[#events + 1] = { id, s } end, events)
      M.ServerMessage("CollectionStatus:5002:1")
      H.eq(Net.CollectionState(5002), 1)
      H.eq(#events, 1)
      H.eq(events[1][2], 1)
      M.Advance(3600)
      H.eq(Net.CollectionState(5002), 1, "gesammelt laeuft nie ab")
      H.eq(Net.QueryCollection(5002), 1)
      H.eq(M.CountSent("GetCollectionStatus:5002"), 2)
   end)

   H.test("1 (gesammelt) und 2 (nicht anwendbar) laufen nie ab; CollectionUpdated nimmt 0 zurueck und bleibt", function()
      local T = start()
      local Net = T.Net
      M.ServerMessage("CollectionStatus:5003:1")
      M.ServerMessage("CollectionStatus:5004:2")
      Net.QueryCollection(5005)
      M.ServerMessage("CollectionStatus:5005:0")
      M.ServerMessage("CollectionUpdated:5005")
      M.Advance(7200)
      H.eq(Net.CollectionState(5003), 1)
      H.eq(Net.CollectionState(5004), 2)
      H.eq(Net.CollectionState(5005), 1, "durch CollectionUpdated 1; kein Zeitstempel mehr")
      M.ClearSent()
      H.eq(Net.QueryCollection(5003), 1)
      H.eq(Net.QueryCollection(5004), 2)
      H.eq(Net.QueryCollection(5005), 1)
      H.eq(#M.SentCommands(), 0, "kein Server-Verkehr")
      -- eine verspaetete, aeltere 0-Antwort nimmt 1 nicht zurueck und stempelt nichts
      M.ServerMessage("CollectionStatus:5005:0")
      M.Advance(3600)
      H.eq(Net.CollectionState(5005), 1)
   end)

   H.test("Abgelaufenes 0 ohne Antwort: Wiederholung nach 30 s, Flutschutz bleibt wirksam", function()
      local T = start()
      local Net = T.Net
      for id = 6001, 6040 do
         Net.QueryCollection(id)
         M.ServerMessage("CollectionStatus:" .. id .. ":0")   -- 40 Antworten (Flutschutz: 30 je Sekunde)
      end
      M.ClearSent()
      M.Advance(50)                       -- alle 40 abgelaufen
      for id = 6001, 6040 do Net.QueryCollection(id) end
      H.eq(M.CountSent("GetCollectionStatus"), 30, "hoechstens 30 Abfragen je Sekunde")
      M.Advance(1.1)
      for id = 6001, 6040 do Net.QueryCollection(id) end
      H.eq(M.CountSent("GetCollectionStatus"), 40, "die uebrigen in der naechsten Sekunde, keine doppelt")
      -- keine Antwort: nach 30 s ein neuer Versuch
      M.Advance(31)
      Net.QueryCollection(6001)
      H.eq(M.CountSent("GetCollectionStatus:6001"), 2)
   end)

   -- Tooltip mit den echten Modulen: die rosa Zeile folgt dem Server.
   local function item(name, quality, class, subclass, loc)
      return {
         name = name, quality = quality, ilvl = 100, minLevel = 0,
         class = class, subclass = subclass, equipLoc = loc, icon = ICON,
      }
   end

   local function startTooltips()
      local T = H.boot({
         world = { equipment = { [1] = 1001 }, locale = "enUS" },
         items = {
            [1001] = item("Equipped Helm", 3, "Armor", "Plate", "INVTYPE_HEAD"),
            [2001] = item("Missing Helm", 4, "Armor", "Plate", "INVTYPE_HEAD"),
         },
         login = true,
         enterWorld = false,
      })
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

   local function pinkLines(T)
      local n = 0
      for i = 1, GameTooltip:NumLines() do
         local fs = _G["GameTooltipTextLeft" .. i]
         if fs and fs:GetText() == T.L.TIP_NOT_COLLECTED then n = n + 1 end
      end
      return n
   end

   local function hover(id)
      GameTooltip:Hide()
      GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink("item:" .. id)
   end

   H.test("Tooltip: wurde der Gegenstand inzwischen von einem anderen Zugang gesammelt, verschwindet die Zeile", function()
      local T = startTooltips()
      M.ClearSent()
      hover(2001)
      H.eq(M.CountSent("GetCollectionStatus:2001"), 1)
      M.ServerMessage("CollectionStatus:2001:0")
      H.eq(pinkLines(T), 1, "nicht gesammelt: Zeile")

      -- Minuten spaeter hat ein Begleiter des Kontos den Gegenstand gesammelt (kein CollectionUpdated)
      M.Advance(120)
      hover(2001)
      H.eq(M.CountSent("GetCollectionStatus:2001"), 2, "neue Abfrage statt veraltetem Cache")
      M.ServerMessage("CollectionStatus:2001:1")
      H.eq(pinkLines(T), 0, "gesammelt: keine Zeile")
      hover(2001)
      H.eq(pinkLines(T), 0)
      H.eq(M.CountSent("GetCollectionStatus:2001"), 2, "danach dauerhaft bekannt")
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Tooltip: bleibt der Gegenstand nicht gesammelt, kommt die Zeile nach der neuen Antwort wieder", function()
      local T = startTooltips()
      M.ClearSent()
      hover(2001)
      M.ServerMessage("CollectionStatus:2001:0")
      M.Advance(120)
      hover(2001)
      H.eq(M.CountSent("GetCollectionStatus:2001"), 2)
      M.ServerMessage("CollectionStatus:2001:0")
      H.eq(pinkLines(T), 1, "Zeile wird nachgetragen, genau einmal")
      hover(2001)
      H.eq(pinkLines(T), 1)
      H.eq(M.CountSent("GetCollectionStatus:2001"), 2, "wieder 45 s bekannt")
      H.eq(#H.takeErrors(), 0)
   end)

   -- =======================================================================
   H.section("robust-2: fremde Absender und Gruppenkanaele")
   -- =======================================================================

   H.test("Net.checkSender ist Standard AUS (fail-open)", function()
      local T = Fixtures.Boot(H, { enterWorld = false })
      H.eq(T.Net.checkSender, false)
   end)

   H.test("Fremdes Open (WHISPER eines Spielers) kapert das naechste Gossip-Fenster nicht (Pruefung an)", function()
      local T = Fixtures.Boot(H, {})
      T.Net.checkSender = true
      Fixtures.ServerHello(T)
      Fixtures.ServerAutoReply(T, {})
      Fixtures.Settle(T, 15)
      -- ein Fremder: SendAddonMessage("transmog", "Open", "WHISPER", <Spielername>)
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "WHISPER", "Griefer")
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "GUILD", "Griefer")
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "PARTY", "Griefer")
      M.Fire("CHAT_MSG_ADDON", "transmog", "Open", "RAID", "Griefer")
      H.eq(T.State.serverOpenAt, nil)
      -- ein beliebiger anderer NPC (Flugmeister, Haendler ...)
      M.GossipShow()
      H.eq(T.UI.Window.IsShown() and true or false, false, "Transmog-Fenster bleibt zu")
      H.eq(T.State.openedByNpc, false)

      -- Kontrolle: das echte Open (Absender = Spieler) funktioniert
      M.ServerMessage("Open")
      M.GossipShow()
      H.eq(T.UI.Window.IsShown() and true or false, true)
      H.eq(T.State.openedByNpc, true)
   end)

   H.test("Gefaelschte Sammlungs-, Status-, Kosten- und Listennachrichten bleiben ohne Wirkung (Pruefung an)", function()
      local T = Fixtures.Boot(H, {})
      T.Net.checkSender = true
      Fixtures.ServerHello(T)
      Fixtures.ServerAutoReply(T, {})
      Fixtures.Settle(T, 15)             -- hinter dem Login-Sweep
      local id = Fixtures.Item(T, "e_head_plate")
      local before = T.Net.receivedCount
      local newBefore = T.State.new[id]
      local stateBefore = T.Net.CollectionState(id)
      for _, channel in ipairs({ "WHISPER", "GUILD", "PARTY", "RAID", "OFFICER", "BATTLEGROUND" }) do
         M.Fire("CHAT_MSG_ADDON", "transmog", "CollectionUpdated:" .. id, channel, "Griefer")
         M.Fire("CHAT_MSG_ADDON", "transmog", "CollectionStatus:" .. id .. ":2", channel, "Griefer")
         M.Fire("CHAT_MSG_ADDON", "transmog", "TransmogCost:1:1", channel, "Griefer")
         M.Fire("CHAT_MSG_ADDON", "transmog", "TransmogStatus:1:0,500", channel, "Griefer")
         M.Fire("CHAT_MSG_ADDON", "transmog", "AvailableTransmogs:0:0:1:start", channel, "Griefer")
      end
      H.eq(T.Net.receivedCount, before, "nichts davon wurde angenommen")
      H.eq(T.State.new[id], newBefore)
      H.eq(T.Net.CollectionState(id), stateBefore)
      H.eq(T.State.Applied(0) ~= 500, true)
      -- auch eine Nachricht des Spielers selbst ueber einen Gruppenkanal kommt nicht vom Server
      M.Fire("CHAT_MSG_ADDON", "transmog", "CollectionUpdated:" .. id, "PARTY", M.world.playerName)
      H.eq(T.Net.receivedCount, before)
      H.eq(#H.takeErrors(), 0)
   end)
end
