-- tests/test_fix_core-misc.lua
-- ---------------------------------------------------------------------------
-- Regressionstests zu Befunden in Core/ (Boot, Events, DB, ...).
--
--   flow-1 / engine-2 / ux-5: NPC-Uebernahme mit einem Gossip-Ersatz-Addon
--   (Immersion): Das Ersatz-Addon koppelt das Blizzard-GossipFrame ab (nie
--   gezeigt), HideUIPanel(GossipFrame) tut nichts, das OnHide mit CloseGossip()
--   laeuft nie: das Gespraech blieb samt fremder Sprechbox und deren
--   Tastenbelegung (SPACE/BACKSPACE/ESC) offen. Die Nachpruefung 0,15 s nach
--   der Uebernahme schliesst es jetzt selbst (CloseGossip, alle Addons bekommen
--   ihr GOSSIP_CLOSED). Geprueft in beiden Handler-Reihenfolgen.
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local Fixtures = require("fixtures")

   -- Nachbau eines Gossip-Ersatz-Addons nach Immersion (Utils.lua L.HideFrame,
   -- Events:GOSSIP_SHOW/GOSSIP_CLOSED): GossipFrame bekommt keine Ereignisse mehr
   -- und haengt an einem versteckten Elternrahmen; die eigene Sprechbox zeigt sich
   -- bei GOSSIP_SHOW (mit Tastenbelegung) und raeumt bei GOSSIP_CLOSED auf.
   -- before = true: der Handler laeuft VOR dem von Transmog, sonst danach.
   local function installReplacement(T, before)
      local hider = CreateFrame("Frame")
      hider:Hide()
      GossipFrame:UnregisterAllEvents()
      GossipFrame:SetParent(hider)

      local r = { keysBound = false, shows = 0, closes = 0, windowShownAtShow = "unset" }
      local talk = CreateFrame("Frame", "ImmersionTalkBoxFake", UIParent)
      talk:Hide()
      talk:RegisterEvent("GOSSIP_SHOW")
      talk:RegisterEvent("GOSSIP_CLOSED")
      talk:SetScript("OnEvent", function(self, event)
         if event == "GOSSIP_SHOW" then
            r.shows = r.shows + 1
            local win = T.UI and T.UI.Window
            r.windowShownAtShow = win and win.IsShown and win.IsShown() or nil
            self:Show()
            r.keysBound = true
         else
            r.closes = r.closes + 1
            self:Hide()
            r.keysBound = false
         end
      end)
      r.talk = talk
      H.allowGlobals({ "^ImmersionTalkBoxFake$" })

      if before then
         -- Transmog hinten neu anmelden: der Ersatz-Handler kommt zuerst
         T.Events.UnGame("GOSSIP_SHOW", T.Boot.OnGossipShow)
         T.Events.Game("GOSSIP_SHOW", T.Boot.OnGossipShow)
      end
      return r
   end

   local function bootAtVendor()
      local T = Fixtures.Boot(H, {})
      Fixtures.ServerAutoReply(T, {})
      Fixtures.ServerHello(T)
      Fixtures.Settle(T, 3)
      return T
   end

   -- ======================================================================
   H.section("Gossip-Ersatz-Addon (Immersion)")
   -- ======================================================================

   H.test("Ersatz-Handler laeuft NACH unserem: die Nachpruefung schliesst das Gespraech, Sprechbox und Tasten weg", function()
      local T = bootAtVendor()
      local r = installReplacement(T, false)
      local w = Fixtures.OpenAtNpc(T)
      H.truthy(w, "Fenster wurde gebaut")
      H.truthy(T.UI.Window.IsShown(), "Fenster per NPC offen")
      H.eq(T.State.openedByNpc, true)
      H.eq(r.shows, 1)
      H.truthy(r.windowShownAtShow, "Reihenfolge: Ersatz-Handler nach Transmog")
      -- noch in der Uebernahme: die Nachpruefung steht aus
      H.eq(M.world.gossipOpen, true, "Gespraech bis zur Nachpruefung offen")
      H.truthy(r.talk:IsShown())

      Fixtures.Settle(T, 0.5)
      H.eq(M.world.gossipOpen, false, "Gespraech geschlossen")
      H.falsy(r.talk:IsShown(), "fremde Sprechbox weg")
      H.eq(r.keysBound, false, "fremde Tastenbelegung frei")
      H.eq(r.closes, 1, "GOSSIP_CLOSED genau einmal")
      H.truthy(T.UI.Window.IsShown(), "unser Fenster bleibt (das Schliessen gehoert zur Uebernahme)")
      H.eq(T.State.openedByNpc, true)
      H.eq(T.State.atVendor, true)
      H.eq(#M.errors, 0)
   end)

   H.test("Ersatz-Handler laeuft VOR unserem: dasselbe Ergebnis", function()
      local T = bootAtVendor()
      local r = installReplacement(T, true)
      Fixtures.OpenAtNpc(T)
      H.truthy(T.UI.Window.IsShown())
      H.eq(r.shows, 1)
      H.falsy(r.windowShownAtShow, "Reihenfolge: Ersatz-Handler vor Transmog")

      Fixtures.Settle(T, 0.5)
      H.eq(M.world.gossipOpen, false)
      H.falsy(r.talk:IsShown())
      H.eq(r.keysBound, false)
      H.eq(r.closes, 1)
      H.truthy(T.UI.Window.IsShown())
      H.eq(T.State.openedByNpc, true)
      H.eq(#M.errors, 0)
   end)

   H.test("Nach der Uebernahme: Weggehen (spaetes GOSSIP_CLOSED) schliesst das Fenster weiterhin", function()
      local T = bootAtVendor()
      installReplacement(T, false)
      Fixtures.OpenAtNpc(T)
      Fixtures.Settle(T, 3)
      H.truthy(T.UI.Window.IsShown())
      M.Fire("GOSSIP_CLOSED")
      H.falsy(T.UI.Window.IsShown())
      H.eq(T.State.openedByNpc, false)
   end)

   H.test("Fenster innerhalb der 0,15 s geschlossen: kein weiteres CloseGossip aus der Nachpruefung", function()
      local T = bootAtVendor()
      local r = installReplacement(T, false)
      local calls = 0
      local original = rawget(_G, "CloseGossip")
      rawset(_G, "CloseGossip", function(...)
         calls = calls + 1
         return original(...)
      end)
      Fixtures.OpenAtNpc(T)
      T.UI.Window.Close()
      H.falsy(T.UI.Window.IsShown())
      H.eq(calls, 1, "das Fenster schliesst das Gespraech (OnHide)")
      H.eq(r.closes, 1)
      Fixtures.Settle(T, 0.5)
      H.eq(calls, 1, "die Nachpruefung tut nichts mehr")
      rawset(_G, "CloseGossip", original)
   end)

   H.test("Anderes Gossip lange nach dem Oeffnen (ohne 'Open'): bleibt unberuehrt", function()
      local T = bootAtVendor()
      local r = installReplacement(T, false)
      Fixtures.OpenAtNpc(T)
      Fixtures.Settle(T, 5)
      H.eq(r.closes, 1)
      -- ein anderer NPC: kein "Open" davor
      M.GossipShow()
      Fixtures.Settle(T, 0.5)
      H.eq(M.world.gossipOpen, true, "fremdes Gespraech bleibt offen")
      H.truthy(r.talk:IsShown())
      H.eq(r.closes, 1)
   end)

   H.test("Normales Blizzard-Gossip: genau ein GOSSIP_CLOSED, Fenster bleibt, nichts doppelt geschlossen", function()
      local T = bootAtVendor()
      local closed = 0
      local watcher = CreateFrame("Frame")
      watcher:RegisterEvent("GOSSIP_CLOSED")
      watcher:SetScript("OnEvent", function() closed = closed + 1 end)
      Fixtures.OpenAtNpc(T)
      H.falsy(GossipFrame:IsShown(), "Blizzard-Fenster versteckt")
      H.eq(M.world.gossipOpen, false)
      H.eq(closed, 1)
      Fixtures.Settle(T, 0.5)
      H.eq(closed, 1, "die Nachpruefung loest kein weiteres GOSSIP_CLOSED aus")
      H.truthy(T.UI.Window.IsShown())
      H.eq(T.State.openedByNpc, true)
      H.eq(#M.errors, 0)
   end)
end
