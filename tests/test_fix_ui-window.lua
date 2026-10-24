-- tests/test_fix_ui-window.lua
-- ---------------------------------------------------------------------------
-- Regressionstests zu UI/Window.lua nach der unabhaengigen Pruefung, mit den
-- ECHTEN Komponenten und dem Server-Nachbau (tests/fixtures.lua):
--
--   engine-1   Scale-/Groessenaenderung, waehrend der Outfit-Reiter aktiv ist
--              (oder das Fenster mit lastTab = outfits geschlossen war): die
--              Rasterzellen verlieren ihre Schluessel, damit die Modelle beim
--              Zurueckwechseln per SetUnit neu geladen werden (die Projektion
--              wird beim Laden berechnet, SPEC 9.2)
--   robust-1   Aufbaufehler des Fensters (und einer Komponente) sind fuer den
--              Spieler sichtbar: eine rote Chatzeile BOOT_INIT_FAILED, danach
--              bei jedem weiteren Versuch BOOT_UNAVAILABLE; der Aufbau wird
--              nicht wiederholt, ein halber Rahmen bleibt verborgen
--
-- Aufruf:  cd <Addon>;  luajit tests/run.lua fix_ui-window
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local Fixtures = require("fixtures")

   local function settle(FX, s)
      Fixtures.Settle(FX, s or 0.5)
   end

   -- -----------------------------------------------------------------------
   -- engine-1: Modelle des Rasters nach Scale-Aenderung im Outfit-Reiter
   -- -----------------------------------------------------------------------

   -- SetUnit-Aufrufe je Zellmodell des Rasters (Zelle -> Anzahl) und ihre Summe
   local function unitCounts(FX)
      local per, sum = {}, 0
      for i, c in ipairs(FX.UI.Grid.cells) do
         if c.model then
            local n = M.Model(c.model).count("SetUnit")
            per[i] = n
            sum = sum + n
         end
      end
      return per, sum
   end

   -- Hat jede Zelle, die vorher ein Modell geladen hatte, es seitdem neu geladen?
   local function allReloaded(before, after)
      local n = 0
      for i, was in pairs(before) do
         if was > 0 then
            n = n + 1
            if after[i] <= was then return false, i end
         end
      end
      return n > 0, nil
   end

   H.section("engine-1: Raster-Modelle nach Scale-Aenderung ausserhalb des Items-Reiters")

   H.test("Scale aendert sich im Outfit-Reiter: Window ruft Grid.Rebuild trotz verborgenem Raster", function()
      local FX = Fixtures.Boot(H, { screen = { w = 1366, h = 768 } })
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX, { mute = true })
      FX.DB.Set("scale", 1.0)
      Fixtures.OpenAtNpc(FX)
      settle(FX, 3)
      local rebuilds = 0
      local orig = FX.UI.Grid.Rebuild
      FX.UI.Grid.Rebuild = function(...)
         rebuilds = rebuilds + 1
         return orig(...)
      end
      FX.UI.Window.SetTab("outfits")
      settle(FX, 0.5)
      H.falsy(FX.UI.Grid.frame:IsShown(), "das Raster ist verborgen")
      H.eq(rebuilds, 0, "ein Reiterwechsel allein laedt nichts neu")
      FX.DB.Set("scale", 1.3)
      settle(FX, 1.0)
      H.eq(rebuilds, 1, "genau ein Neuaufbau, obwohl das Raster verborgen ist")
      -- Aufloesungswechsel (UI-Scale) im Outfit-Reiter: ebenso
      rebuilds = 0
      FX.DB.Set("scale", 1.0)
      settle(FX, 1.0)
      H.eq(rebuilds, 1)
      H.eq(#M.errors, 0)
   end)

   H.test("Scale aendert sich im Outfit-Reiter: zurueck zu Items laedt jedes Zellmodell neu (SetUnit)", function()
      local FX = Fixtures.Boot(H, { screen = { w = 1366, h = 768 } })
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX, { mute = true })
      FX.DB.Set("scale", 1.0)
      Fixtures.OpenAtNpc(FX)
      settle(FX, 3)
      H.eq(FX.UI.Grid.mode, "GRID")
      local opened, openedSum = unitCounts(FX)
      H.truthy(openedSum > 0, "das Raster hat Modelle geladen")
      FX.UI.Window.SetTab("outfits")
      settle(FX, 0.5)
      local _, noChangeSum = unitCounts(FX)
      FX.DB.Set("scale", 1.3)                       -- z. B. ueber die Optionen
      settle(FX, 1.0)
      -- das verborgene Raster wird nicht beladen (ein verstecktes Modell laedt nicht zuverlaessig)
      local _, midSum = unitCounts(FX)
      H.eq(midSum, noChangeSum, "waehrend das Raster verborgen ist, kein SetUnit")
      FX.UI.Window.SetTab("items")
      settle(FX, 1.0)
      local after = unitCounts(FX)
      local ok, cell = allReloaded(opened, after)
      H.truthy(ok, "Zelle " .. tostring(cell) .. " hat ihr Modell nach der Scale-Aenderung nicht neu geladen")
      H.eq(#M.errors, 0)
   end)

   -- Ein verborgenes DressUpModel verliert im echten Client Auskleidung und Kamera (Spieltest
   -- 2026-10-12): auch ohne Scale-Aenderung wird beim Zurueckwechseln zu Items jedes sichtbare
   -- Zellmodell neu angekleidet -- genau einmal, nie doppelt.
   H.test("Ohne Scale-Aenderung kleidet der Reiterwechsel jedes sichtbare Zellmodell genau einmal neu an", function()
      local FX = Fixtures.Boot(H, { screen = { w = 1366, h = 768 } })
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX, { mute = true })
      FX.DB.Set("scale", 1.0)
      Fixtures.OpenAtNpc(FX)
      settle(FX, 3)
      local opened, openedSum = unitCounts(FX)
      H.truthy(openedSum > 0)
      FX.UI.Window.SetTab("outfits")
      settle(FX, 0.5)
      local _, hiddenSum = unitCounts(FX)
      H.eq(hiddenSum, openedSum, "verborgenes Raster: kein Ankleiden")
      FX.UI.Window.SetTab("items")
      settle(FX, 0.5)
      local after, afterSum = unitCounts(FX)
      local visible = 0
      for i, c in ipairs(FX.UI.Grid.cells) do
         if c:IsShown() and c.model then
            visible = visible + 1
            H.eq(after[i], opened[i] + 1, "Zelle " .. i .. " genau einmal neu angekleidet")
         elseif after[i] then
            H.eq(after[i], opened[i], "Zelle " .. i .. " (nicht sichtbar) unberuehrt")
         end
      end
      H.truthy(visible > 0)
      H.eq(afterSum, openedSum + visible, "Summe: je sichtbarem Modell ein SetUnit")
      -- und Ruhe danach: nochmaliges Anklicken des aktiven Reiters laedt nichts
      FX.UI.Window.SetTab("items")
      settle(FX, 0.5)
      local _, quietSum = unitCounts(FX)
      H.eq(quietSum, afterSum, "aktiver Reiter erneut gewaehlt: nichts neu")
      H.eq(#M.errors, 0)
   end)

   H.test("Scale aendert sich bei geschlossenem Fenster (letzter Reiter Outfits): Items laedt die Modelle neu", function()
      local FX = Fixtures.Boot(H, { screen = { w = 1366, h = 768 } })
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX, { mute = true })
      FX.DB.Set("scale", 1.0)
      Fixtures.OpenAtNpc(FX)
      settle(FX, 3)
      local opened = unitCounts(FX)
      FX.UI.Window.SetTab("outfits")
      settle(FX, 0.5)
      FX.UI.Window.Close()
      settle(FX, 0.5)
      FX.DB.Set("scale", 1.3)
      settle(FX, 0.5)
      FX.UI.Window.Open({ fromNpc = false })         -- merkt sich lastTab = outfits
      settle(FX, 1.0)
      H.eq(FX.UI.Window.GetTab(), "outfits")
      FX.UI.Window.SetTab("items")
      settle(FX, 1.0)
      local after = unitCounts(FX)
      local ok, cell = allReloaded(opened, after)
      H.truthy(ok, "Zelle " .. tostring(cell) .. " hat ihr Modell nach der Scale-Aenderung nicht neu geladen")
      H.eq(#M.errors, 0)
   end)

   -- -----------------------------------------------------------------------
   -- robust-1: Aufbaufehler sind fuer den Spieler sichtbar
   -- -----------------------------------------------------------------------

   -- Chatzeilen ab Index from + 1
   local function linesSince(from)
      local out = {}
      for i = from + 1, #M.messages do out[#out + 1] = M.messages[i] end
      return out
   end

   -- Anzahl der Zeilen unter lines, die text (plain) enthalten
   local function countWith(lines, text)
      local n = 0
      for _, line in ipairs(lines) do
         if string.find(line, text, 1, true) then n = n + 1 end
      end
      return n
   end

   local function boot()
      local FX = Fixtures.Boot(H, {})
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX, {})
      return FX
   end

   H.section("robust-1: Aufbaufehler des Fensters")

   H.test("Aufbau wirft: erste /transmog zeigt BOOT_INIT_FAILED, danach nur BOOT_UNAVAILABLE, kein zweiter Aufbau", function()
      local FX = boot()
      local W = FX.UI.Window
      local headers = 0
      FX.UI.Skin.Header = function()
         headers = headers + 1
         error("simulated: method missing in 3.3.5a")
      end
      local failed = string.format(FX.L.BOOT_INIT_FAILED, "Window")
      local mark = #M.messages
      M.Slash("/transmog")
      local lines = linesSince(mark)
      H.eq(#lines, 1, "genau eine Chatzeile beim ersten Fehlschlag")
      H.eq(countWith(lines, failed), 1)
      H.falsy(W.IsShown())
      local errs = H.takeErrors()
      H.eq(#errs, 1, "der Fehlerbehandler bekommt die genaue Meldung")
      H.contains(errs[1], "simulated: method missing")

      -- jeder weitere Versuch: die kurze Meldung, kein neuer Aufbau, kein neuer Fehlerbericht
      for _ = 1, 2 do
         mark = #M.messages
         M.Slash("/transmog")
         lines = linesSince(mark)
         H.eq(#lines, 1)
         H.eq(countWith(lines, FX.L.BOOT_UNAVAILABLE), 1)
         H.eq(countWith(lines, failed), 0)
      end
      H.eq(headers, 1, "der Aufbau wird nicht wiederholt")
      H.eq(#H.takeErrors(), 0)
      H.eq(W.Open({ fromNpc = true }), false)
      H.falsy(W.IsShown())
   end)

   H.test("Aufbau wirft beim NPC-Besuch: das Gossip-Fenster bleibt, die Zeile erscheint einmal", function()
      local FX = boot()
      FX.UI.Skin.Header = function() error("simulated: method missing in 3.3.5a") end
      local failed = string.format(FX.L.BOOT_INIT_FAILED, "Window")
      local mark = #M.messages
      M.OpenNpc()
      local lines = linesSince(mark)
      H.eq(countWith(lines, failed), 1)
      H.truthy(GossipFrame:IsShown(), "das normale Gossip-Fenster bleibt dem Spieler")
      H.falsy(FX.UI.Window.IsShown())
      H.eq(#H.takeErrors(), 1)
      -- noch ein Besuch: stumm (das Gossip-Fenster steht ohnehin), kein Fehlerbericht
      mark = #M.messages
      M.OpenNpc()
      H.eq(countWith(linesSince(mark), failed), 0)
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Fehler beim Anlegen des Rahmens selbst (Hintergrund): gemeldet, ohne Wiederholung, Rahmen verborgen", function()
      local FX = boot()
      local W = FX.UI.Window
      local calls = 0
      FX.UI.Skin.Backdrop = function()
         calls = calls + 1
         error("simulated: SetBackdrop failed")
      end
      local failed = string.format(FX.L.BOOT_INIT_FAILED, "Window")
      local mark = #M.messages
      M.Slash("/transmog")
      H.eq(countWith(linesSince(mark), failed), 1)
      H.eq(#H.takeErrors(), 1)
      local f = rawget(_G, "TransmogWindow")
      H.falsy(f and f:IsShown(), "ein halber Rahmen bleibt nicht sichtbar stehen")
      mark = #M.messages
      M.Slash("/transmog")
      M.Slash("/transmog")
      H.eq(countWith(linesSince(mark), FX.L.BOOT_UNAVAILABLE), 2)
      H.eq(calls, 1, "kein weiterer TransmogWindow-Rahmen")
      H.eq(rawget(_G, "TransmogWindow"), f)
      H.falsy(W.IsShown())
   end)

   H.test("Eine Komponente laesst sich nicht anlegen: Chatzeile mit ihrem Namen, das Fenster oeffnet trotzdem", function()
      local FX = boot()
      local W = FX.UI.Window
      FX.UI.Grid.Create = function() error("simulated Grid.Create failure") end
      local mark = #M.messages
      M.Slash("/transmog")
      settle(FX, 1)
      local lines = linesSince(mark)
      H.eq(countWith(lines, string.format(FX.L.BOOT_INIT_FAILED, "Grid")), 1)
      H.eq(countWith(lines, string.format(FX.L.BOOT_INIT_FAILED, "Window")), 0)
      H.truthy(W.IsShown(), "das Fenster ist offen und bedienbar")
      local errs = H.takeErrors()
      H.truthy(#errs >= 1)
      H.contains(table.concat(errs, "\n"), "Grid.Create")
      W.Close()
      H.falsy(W.IsShown())
   end)

   H.test("Ohne Skin kann das Fenster nicht entstehen: /transmog meldet es statt zu schweigen", function()
      local FX = boot()
      FX.UI.Skin = nil
      local mark = #M.messages
      M.Slash("/transmog")
      local lines = linesSince(mark)
      H.eq(#lines, 1)
      H.eq(countWith(lines, FX.L.BOOT_UNAVAILABLE), 1)
      H.eq(FX.UI.Window.Open({ fromNpc = false }), false)
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Gelingt der Aufbau, bleibt der Chat still", function()
      local FX = boot()
      local mark = #M.messages
      M.Slash("/transmog")
      settle(FX, 1)
      H.truthy(FX.UI.Window.IsShown())
      H.eq(countWith(linesSince(mark), "could not be started"), 0)
      H.eq(countWith(linesSince(mark), FX.L.BOOT_UNAVAILABLE), 0)
      H.eq(#M.errors, 0)
   end)
end
