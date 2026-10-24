-- tests/test_fix_model_refresh.lua
-- ---------------------------------------------------------------------------
-- Spieltest 2026-10-12: Aenderungen (angewendete Transmogrifikation, Ausruestung)
-- erschienen in der grossen Vorschau und den Handslot-Kacheln erst nach erneutem
-- Oeffnen. Ursache: ein DressUpModel mit SetUnit("player") laedt nicht von selbst
-- nach; Blizzards Charakterfenster ruft bei UNIT_MODEL_CHANGED ("player") erneut
-- SetUnit. Das Fenster tut das jetzt ebenfalls (entprellt), und nach erfolgreichem
-- Anwenden zusaetzlich einmal verzoegert.
--
-- Aufruf:  cd <Addon>;  luajit tests/run.lua fix_model_refresh
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local Fixtures = require("fixtures")

   local function settle(FX, s)
      Fixtures.Settle(FX, s or 1)
   end

   local function previewUnits(FX)
      return M.Model(FX.UI.Preview.model).count("SetUnit")
   end

   -- SetUnit-Aufrufe je sichtbarem Zellmodell und ihre Summe
   local function cellUnits(FX)
      local sum, shown = 0, 0
      for _, c in ipairs(FX.UI.Grid.cells) do
         if c.model and c:IsShown() then
            sum = sum + M.Model(c.model).count("SetUnit")
            shown = shown + 1
         end
      end
      return sum, shown
   end

   local function openWindow()
      local FX = Fixtures.Boot(H, { screen = { w = 1366, h = 768 } })
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX, { mute = true })
      FX.DB.Set("scale", 1.0)
      Fixtures.OpenAtNpc(FX)
      settle(FX, 3)
      H.eq(FX.UI.Grid.mode, "GRID")
      return FX
   end

   H.section("UNIT_MODEL_CHANGED laedt die Modelle neu")

   H.test("UNIT_MODEL_CHANGED(player): grosse Vorschau und sichtbare Zellen laden einmal neu", function()
      local FX = openWindow()
      local p0 = previewUnits(FX)
      local c0, shown = cellUnits(FX)
      H.truthy(shown > 0, "es gibt sichtbare Zellmodelle")
      M.Fire("UNIT_MODEL_CHANGED", "player")
      settle(FX, 1)
      H.eq(previewUnits(FX), p0 + 1, "Vorschau: ein SetUnit")
      local c1 = cellUnits(FX)
      H.eq(c1, c0 + shown, "je sichtbarem Zellmodell ein SetUnit")
      H.eq(#M.errors, 0)
   end)

   H.test("andere Einheiten loesen nichts aus", function()
      local FX = openWindow()
      local p0 = previewUnits(FX)
      local c0 = cellUnits(FX)
      M.Fire("UNIT_MODEL_CHANGED", "target")
      M.Fire("UNIT_MODEL_CHANGED", "pet")
      settle(FX, 1)
      H.eq(previewUnits(FX), p0)
      H.eq(cellUnits(FX), c0)
   end)

   H.test("ein Schwarm von Ereignissen ergibt genau ein Neuladen", function()
      local FX = openWindow()
      local p0 = previewUnits(FX)
      for _ = 1, 25 do
         M.Fire("UNIT_MODEL_CHANGED", "player")
         M.Advance(0.05)
      end
      settle(FX, 1)
      H.eq(previewUnits(FX), p0 + 1)
   end)

   H.test("verborgenes Fenster: kein Laden, beim Oeffnen sind die Modelle frisch", function()
      local FX = openWindow()
      FX.UI.Window.Close()
      settle(FX, 0.5)
      local p0 = previewUnits(FX)
      local c0 = cellUnits(FX)
      M.Fire("UNIT_MODEL_CHANGED", "player")
      settle(FX, 1)
      H.eq(previewUnits(FX), p0, "verborgen: kein SetUnit")
      H.eq(cellUnits(FX), c0)
      Fixtures.OpenAtNpc(FX)
      settle(FX, 2)
      H.truthy(previewUnits(FX) > p0, "Vorschau beim Oeffnen neu geladen")
      H.truthy(cellUnits(FX) > c0, "Zellen beim Oeffnen neu geladen")
      H.eq(#M.errors, 0)
   end)

   H.section("nach dem Anwenden")

   H.test("APPLY_DONE mit Erfolg: Modelle werden verzoegert noch einmal neu geladen", function()
      local FX = openWindow()
      local p0 = previewUnits(FX)
      FX.Events.Fire("APPLY_DONE", 1, 0)
      M.Advance(0.3)
      H.eq(previewUnits(FX), p0, "noch nicht (verzoegert)")
      settle(FX, 1)
      H.eq(previewUnits(FX), p0 + 1)
   end)

   H.test("APPLY_DONE ohne Erfolg laedt nichts neu", function()
      local FX = openWindow()
      local p0 = previewUnits(FX)
      FX.Events.Fire("APPLY_DONE", 0, 2)
      settle(FX, 1.5)
      H.eq(previewUnits(FX), p0)
   end)
end
