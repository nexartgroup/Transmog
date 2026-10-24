-- tests/test_ui_window.lua
-- ---------------------------------------------------------------------------
-- Verhaltenstests fuer UI/Window.lua (T.UI.Window, das Hauptfenster) gegen die
-- strenge Attrappe, mit dem ECHTEN Core (Boot, DB, State, Net ...) und mit
-- Attrappen der Unterkomponenten (SlotBar, Preview, Grid, FilterBar,
-- OutfitsTab, Options) nach dem Vertrag aus SPEC 11.2. So pruefen diese Tests
-- das Fenster, nicht die Arbeit anderer Dateien; ein letzter Abschnitt laesst
-- die vorhandenen ECHTEN Komponenten einmal zusammen laufen.
--
--   * Aufbau und Reihenfolge, lazy (nichts vor dem ersten Oeffnen), ESC
--   * Masse (Standard, Minimum, gross, Scales, mit/ohne Hinweisleiste)
--   * Reiter, Slotwahl, Hinweisleiste (Vorschau, Server fehlt, allowAnywhere)
--   * Anwenden-Knopf je Grund aus State.CanApply, Kosten, Verwerfen,
--     Alles entfernen (Rueckfrage), Anwenden-Ablauf mit Ton/Blinken/Status
--   * Oeffnen/Schliessen inkl. NPC-Gossip, Groesse/Position speichern,
--     Aufloesungswechsel, Zuruecksetzen, Sprachwechsel, Robustheit
--   * Unabhaengige Pruefung (letzte Abschnitte): Nachholen des Modell-Neuaufbaus,
--     Fortschritt und Chat-Ergebnis beim Anwenden, Kostenfeld mit langen Texten,
--     Layout-Matrix mit den echten Komponenten und dem Server-Nachbau
--     (tests/fixtures.lua, tests/layout.lua), Spielerablauf bis ESC
--
-- Die Attrappe setzt IsShown() & Co. auf 1/nil: deshalb H.truthy/H.falsy.
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   -- -----------------------------------------------------------------------
   -- Konstanten
   -- -----------------------------------------------------------------------

   local HEAD, SHOULDER, SHIRT, CHEST, LEGS = 0, 2, 3, 4, 6
   local BACK, MAINHAND, OFFHAND, RANGED = 14, 15, 16, 17
   local HIDDEN = 999999
   -- Ton nach dem Anwenden: Standardton des Clients (PlaySound), keine Mediendatei des Addons
   local SOUND_APPLY = "LOOTWINDOWCOINSOUND"

   -- Slots in Anzeigereihenfolge (Slots.LIST)
   local ORDER = { 0, 2, 14, 4, 3, 18, 8, 9, 5, 6, 7, 15, 16, 17 }

   -- -----------------------------------------------------------------------
   -- Zustand je Test
   -- -----------------------------------------------------------------------

   local T, W, State, DB
   local calls = {}         -- Aufrufprotokoll der Komponenten-Attrappen
   local stubs = {}         -- die Attrappen selbst

   local function clearCalls()
      for i = #calls, 1, -1 do calls[i] = nil end
   end

   local function rec(name, ...)
      calls[#calls + 1] = { name = name, n = select("#", ...), ... }
   end

   local function callsOf(name)
      local out = {}
      for _, c in ipairs(calls) do
         if c.name == name then out[#out + 1] = c end
      end
      return out
   end

   local function lastCall(name)
      local l = callsOf(name)
      return l[#l]
   end

   local function names()
      local out = {}
      for i, c in ipairs(calls) do out[i] = c.name end
      return out
   end

   -- -----------------------------------------------------------------------
   -- Attrappen der Komponenten (SPEC 11.2)
   -- -----------------------------------------------------------------------

   local function newStubs(opts)
      opts = opts or {}
      local s = {}

      -- SlotBar
      local sb = { COLUMN_WIDTH = 44, BUTTON_SIZE = 40 }
      function sb.Create(parent, onSelect)
         rec("SlotBar.Create")
         sb.parent, sb.onSelect = parent, onSelect
         sb.bar = {
            left = CreateFrame("Frame", nil, parent),
            right = CreateFrame("Frame", nil, parent),
            buttons = {},
         }
         return sb.bar
      end
      function sb.Layout(h) rec("SlotBar.Layout", h) end
      function sb.Refresh(slot) rec("SlotBar.Refresh", slot) end
      function sb.Select(slot) rec("SlotBar.Select", slot) end
      function sb.Flash(slot, ok) rec("SlotBar.Flash", slot, ok) end
      s.SlotBar = sb

      -- Preview
      local pv = {}
      function pv.Create(parent)
         rec("Preview.Create")
         pv.frame = CreateFrame("Frame", nil, parent)
         return pv.frame
      end
      function pv.Layout(w, h) rec("Preview.Layout", w, h) end
      function pv.Refresh() rec("Preview.Refresh") end
      function pv.Rebuild() rec("Preview.Rebuild") end
      function pv.ResetCamera() rec("Preview.ResetCamera") end
      function pv.SetFocusSlot(slot) rec("Preview.SetFocusSlot", slot) end
      s.Preview = pv

      -- Grid (mit oder ohne Rebuild)
      local gr = {}
      function gr.Create(parent)
         rec("Grid.Create")
         gr.frame = CreateFrame("Frame", nil, parent)
         return gr.frame
      end
      function gr.Layout(w, h) rec("Grid.Layout", w, h) end
      function gr.SetSlot(slot) rec("Grid.SetSlot", slot) end
      function gr.Refresh() rec("Grid.Refresh") end
      function gr.InvalidateModels() rec("Grid.InvalidateModels") end
      if opts.gridRebuild then
         function gr.Rebuild() rec("Grid.Rebuild") end
      end
      s.Grid = gr

      -- FilterBar
      local fb = { HEIGHT = 58 }
      function fb.Create(parent, onChange)
         rec("FilterBar.Create")
         fb.onChange = onChange
         fb.frame = CreateFrame("Frame", nil, parent)
         return fb.frame
      end
      function fb.Layout(w) rec("FilterBar.Layout", w) end
      function fb.Refresh(slot) rec("FilterBar.Refresh", slot) end
      s.FilterBar = fb

      -- OutfitsTab
      local ot = {}
      function ot.Create(parent)
         rec("OutfitsTab.Create")
         ot.frame = CreateFrame("Frame", nil, parent)
         ot.frame:Hide()
         return ot.frame
      end
      function ot.Layout(w, h) rec("OutfitsTab.Layout", w, h) end
      function ot.Refresh() rec("OutfitsTab.Refresh") end
      function ot.Show()
         rec("OutfitsTab.Show")
         ot.frame:Show()
      end
      function ot.Hide()
         rec("OutfitsTab.Hide")
         ot.frame:Hide()
      end
      s.OutfitsTab = ot

      -- Options
      local op = { open = false }
      function op.Open() rec("Options.Open") op.open = true end
      function op.Close() rec("Options.Close") op.open = false end
      function op.Toggle() rec("Options.Toggle") op.open = not op.open end
      function op.IsShown() return op.open end
      s.Options = op

      return s
   end

   local function installStubs(opts)
      stubs = newStubs(opts)
      for name, mod in pairs(stubs) do
         T.UI[name] = mod
      end
   end

   -- -----------------------------------------------------------------------
   -- Testgegenstaende und Nachrichten
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
      add(114, "Cloth Cloak", 2, "INVTYPE_CLOAK", "Armor", "Cloth")
      add(115, "Old Mace", 4, "INVTYPE_WEAPON", "Weapon", "One-Handed Maces")
      add(116, "Kite Shield", 3, "INVTYPE_SHIELD", "Armor", "Shields")
      add(117, "Short Bow", 3, "INVTYPE_RANGED", "Weapon", "Bows")
      add(118, "Idol of Testing", 3, "INVTYPE_RELIC", "Armor", "Idols")
      for id = 200, 230 do
         add(id, "Look " .. id, id % 6, "INVTYPE_HEAD", "Armor", "Plate")
      end
      return items
   end

   -- Standardausruestung: Kopf, Schulter, Brust, Beine, Ruecken, Haupthand, Nebenhand, Fernkampf
   local function defaultEquip()
      return { [0] = 101, [2] = 102, [4] = 104, [6] = 106, [14] = 114, [15] = 115, [16] = 116, [17] = 117 }
   end

   -- Stromnachrichten genau wie der Server (Chunks zu 20)
   local function listMsgs(slot, ids)
      local out = {}
      local header = "AvailableTransmogs:" .. slot .. ":0:" .. #ids .. ":"
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

   local function range(a, b)
      local t = {}
      for i = a, b do t[#t + 1] = i end
      return t
   end

   local function setList(slot, ids)
      for _, m in ipairs(listMsgs(slot, ids)) do M.ServerMessage(m) end
   end

   -- Status des Servers: map[slot] = fakeEntry
   local function setApplied(map)
      local parts, n = {}, 0
      for slot = 0, 18 do
         if map[slot] and map[slot] ~= 0 then
            n = n + 1
            parts[#parts + 1] = ":" .. slot .. "," .. map[slot]
         end
      end
      M.ServerMessage("TransmogStatus:" .. n .. table.concat(parts))
   end

   -- Wartet die Entprellungen ab (Fuss 0,03 s, Kosten 0,25 s)
   local function settle(seconds)
      M.Advance(seconds or 0.4)
   end

   -- Kostenanfrage beantworten (falls eine hinausging)
   local function answerCost(copper, can)
      M.Advance(0.3)
      local cmds = M.SentCommands()
      local last = cmds[#cmds]
      if last and string.sub(last, 1, 13) == "CalculateCost" then
         M.ServerMessage("TransmogCost:" .. copper .. ":" .. (can and 1 or 0))
      end
      M.Advance(0.1)
   end

   -- -----------------------------------------------------------------------
   -- Start eines Tests
   -- -----------------------------------------------------------------------

   -- opts.equip    [Server-Slot] = itemId (Standard: defaultEquip)
   -- opts.world    zusaetzliche Welt (Bildschirm usw.)
   -- opts.saved    SavedVariables einer frueheren Sitzung
   -- opts.stubs    false = die echten Komponenten behalten
   -- opts.alive    false = dem Addon keine Serverantwort vorspielen
   -- opts.gridRebuild  Attrappe des Rasters mit Rebuild
   -- opts.noSeed   true = echte Vorgabe seit 2.1 (Neuinstallation: "Anwenden auch ohne Transmogrifizierer" an);
   --               ohne: H.boot belegt TransmogGlobalDB mit allowAnywhere = false (Vorschau-Modus ausserhalb des NPCs)
   local function start(opts)
      opts = opts or {}
      local equip = opts.equip or defaultEquip()
      local world = { equipment = {}, money = 100000000 }
      for slot, id in pairs(equip) do world.equipment[slot + 1] = id end
      for k, v in pairs(opts.world or {}) do world[k] = v end
      T = H.boot({ items = buildItems(), world = world, globals = opts.saved, noSeed = opts.noSeed })
      H.assert(type(T) == "table", "Transmog wurde nicht geladen")
      W, State, DB = T.UI.Window, T.State, T.DB
      H.assert(type(W) == "table", "T.UI.Window fehlt")
      T.enteredWorldAt = GetTime() - 1000          -- kein Login-Sweep
      if opts.stubs ~= false then installStubs(opts) end
      if opts.alive ~= false then M.ServerMessage("TransmogStatus:0") end
      M.Advance(1.0)
      M.ClearSent()
      clearCalls()
      return T
   end

   local function F()
      return W.frame
   end

   -- Text einer Beschriftung
   local function labelOf(btn)
      return btn.label:GetText()
   end

   -- Alle Texte (auch versteckte) eines Frames enthalten text?
   local function hasText(frame, text)
      return M.HasText(frame, text, true)
   end

   -- Tooltip-Zeilen (links) des GameTooltip
   local function tipLines()
      local out = {}
      for i = 1, GameTooltip:NumLines() do
         local fs = rawget(_G, "GameTooltipTextLeft" .. i)
         out[i] = fs and fs:GetText() or nil
      end
      return out
   end

   local function tipHas(text)
      for _, l in ipairs(tipLines()) do
         if l == text then return true end
      end
      return false
   end

   local function contains(text, part)
      return type(text) == "string" and string.find(text, part, 1, true) ~= nil
   end

   -- ======================================================================
   H.section("Aufbau")
   -- ======================================================================

   H.test("Window.Init baut nichts; das Fenster entsteht erst beim ersten Oeffnen", function()
      start()
      H.eq(rawget(_G, "TransmogWindow"), nil)
      H.eq(W.frame, nil)
      H.falsy(W.IsShown())
      H.eq(State.chatMessages, false, "Window.Init schaltet die Chatmeldungen von State ab")
      H.eq(#callsOf("SlotBar.Create"), 0)
      H.truthy(W.Open({ fromNpc = true }))
      H.truthy(rawget(_G, "TransmogWindow"))
      H.eq(W.frame, TransmogWindow)
      H.truthy(W.IsShown())
   end)

   H.test("Fenster: Name, Strata HIGH, beweglich, skalierbar, ESC-faehig, Titel, Reiter", function()
      start()
      W.Open({ fromNpc = true })
      local f = F()
      H.eq(f:GetObjectType(), "Frame")
      H.eq(f:GetFrameStrata(), "HIGH")
      H.truthy(f:IsMovable())
      H.truthy(f:IsResizable())
      H.truthy(f.__clamped, "SetClampedToScreen")
      H.deepEq(f.__minResize, { 740, 520 })
      local found = false
      for _, n in ipairs(UISpecialFrames) do
         if n == "TransmogWindow" then found = true end
      end
      H.truthy(found, "TransmogWindow steht in UISpecialFrames")
      H.truthy(hasText(f, "Transmog"), "Titel")
      H.eq(labelOf(f.tabItems), "Items")
      H.eq(labelOf(f.tabOutfits), "Outfits")
      H.eq(labelOf(f.btnOptions), "*")
      H.eq(labelOf(f.btnClose), "x")
      H.eq(labelOf(f.btnDiscard), "Discard")
      H.eq(labelOf(f.btnRemoveAll), "Remove all")
      H.eq(labelOf(f.btnApply), "Apply")
   end)

   H.test("Methoden auch als Frame-Felder (Doppelpunkt-Aufruf)", function()
      start()
      W.Open({ fromNpc = true })
      local f = F()
      f:SetTab("outfits")
      H.eq(W.GetTab(), "outfits")
      f:SetTab("items")
      f:SelectSlot(CHEST)
      H.eq(W.currentSlot, CHEST)
      f:SetStatus("hi", "green")
      H.eq(f.statusText:GetText(), "hi")
      clearCalls()
      f:Layout()
      H.truthy(lastCall("Grid.Layout"))
      f:Close()
      H.falsy(W.IsShown())
      f:Toggle()
      H.truthy(W.IsShown())
      H.truthy(f:IsShown(), "die Standardmethoden des Frames bleiben")
   end)

   H.test("Aufbau: Komponenten in fester Reihenfolge, genau einmal, auch bei erneutem Oeffnen", function()
      start()
      W.Open({ fromNpc = true })
      local created = {}
      for _, c in ipairs(calls) do
         if string.find(c.name, "%.Create$") then created[#created + 1] = c.name end
      end
      H.deepEq(created, { "SlotBar.Create", "Preview.Create", "FilterBar.Create", "Grid.Create", "OutfitsTab.Create" })
      W.Close()
      W.Open({ fromNpc = false })
      W.Toggle()
      W.Toggle()
      H.eq(#callsOf("SlotBar.Create"), 1)
      H.eq(#callsOf("Grid.Create"), 1)
      -- die Komponenten haengen in den Panels des Fensters
      H.eq(stubs.SlotBar.parent, F().left)
      H.eq(stubs.Preview.frame:GetParent(), F().left)
      H.eq(stubs.FilterBar.frame:GetParent(), F().right)
      H.eq(stubs.Grid.frame:GetParent(), F().right)
      H.eq(stubs.OutfitsTab.frame:GetParent(), F().right)
   end)

   H.test("Fehlende Komponenten: das Fenster oeffnet trotzdem, ohne Fehler", function()
      start({ stubs = false })
      for _, n in ipairs({ "SlotBar", "Preview", "Grid", "FilterBar", "OutfitsTab", "Options" }) do
         T.UI[n] = nil
      end
      H.truthy(W.Open({ fromNpc = true }))
      H.truthy(W.IsShown())
      W.SetTab("outfits")
      W.SelectSlot(HEAD)
      W.RefreshAll()
      W.Layout()
      H.eq(W.currentSlot, HEAD)
      M.Click(F().btnOptions)
      W.Close()
   end)

   H.test("Eine werfende Komponente reisst das Fenster nicht mit; der Fehler wird gemeldet", function()
      start()
      H.allowErrors()
      T.UI.Grid.Create = function() error("kaputt im Raster") end
      T.UI.Preview.Layout = function() error("kaputt in der Vorschau") end
      H.truthy(W.Open({ fromNpc = true }))
      H.truthy(W.IsShown())
      local errs = M.TakeErrors()
      H.truthy(#errs >= 2, "beide Fehler gemeldet")
      local joined = table.concat(errs, "\n")
      H.contains(joined, "kaputt im Raster")
      H.contains(joined, "kaputt in der Vorschau")
      -- das Fenster funktioniert weiter
      W.SetTab("outfits")
      W.SetTab("items")
      W.Close()
   end)

   -- ======================================================================
   H.section("Masse")
   -- ======================================================================

   -- Position eines Frames relativ zum Eltern-Frame: point, x, y des ersten Ankers
   local function anchorOf(frame)
      local point, rel, relPoint, x, y = frame:GetPoint(1)
      return point, rel, relPoint, x, y
   end

   H.test("Metrics: Standard 880x600 mit und ohne Hinweisleiste (SPEC 11.4)", function()
      start()
      local m = W.Metrics(880, 600, false)
      H.eq(m.headerH, 30)
      H.eq(m.footerH, 46)
      H.eq(m.leftW, 318)
      H.eq(m.columnW, 44)
      H.eq(m.previewW, 230, "318 - 2 x 44")
      H.eq(m.leftX, 8)
      H.eq(m.rightX, 334, "8 + 318 + 8")
      H.eq(m.rightW, 538, "880 - 8 - 334")
      H.eq(m.contentY, 38, "30 + 8")
      H.eq(m.contentH, 508, "600 - 46 - 8 - 38")
      H.eq(m.filterH, 58)
      H.eq(m.gridY, 64, "58 + 6")
      H.eq(m.gridH, 444)
      H.eq(m.footerY, 553)
      local n = W.Metrics(880, 600, true)
      H.eq(n.noticeH, 22)
      H.eq(n.contentY, 60)
      H.eq(n.contentH, 486, "die Hinweisleiste nimmt 22 vom Inhalt")
      H.eq(n.gridH, 422)
      H.eq(n.rightW, 538)
   end)

   H.test("Standardgroesse: Frame- und Komponentenmasse stimmen mit Metrics ueberein", function()
      start()
      W.Open({ fromNpc = true })
      local f = F()
      H.eq(f:GetWidth(), 880)
      H.eq(f:GetHeight(), 600)
      H.eq(f.left:GetWidth(), 318)
      H.eq(f.left:GetHeight(), 508)
      H.eq(f.right:GetWidth(), 538)
      H.eq(f.right:GetHeight(), 508)
      H.eq(f.footer:GetWidth(), 878)
      H.eq(f.footer:GetHeight(), 46)
      local p, _, rp, x, y = anchorOf(f.left)
      H.eq(p, "TOPLEFT")
      H.eq(rp, "TOPLEFT")
      H.eq(x, 8)
      H.eq(y, -38)
      p, _, _, x, y = anchorOf(f.right)
      H.eq(x, 334)
      H.eq(y, -38)
      -- Komponenten: das Fenster reicht die Masse von oben durch
      H.eq(lastCall("SlotBar.Layout")[1], 508)
      local pl = lastCall("Preview.Layout")
      H.eq(pl[1], 230)
      H.eq(pl[2], 508)
      H.eq(lastCall("FilterBar.Layout")[1], 538)
      local gl = lastCall("Grid.Layout")
      H.eq(gl[1], 538)
      H.eq(gl[2], 444)
      -- SlotBar-Spalten: je 44 breit, links und rechts im linken Panel
      local bar = stubs.SlotBar.bar
      H.eq(bar.left:GetWidth(), 44)
      H.eq(bar.right:GetWidth(), 44)
      H.eq(bar.left:GetHeight(), 508)
      local lp = anchorOf(bar.left)
      H.eq(lp, "TOPLEFT")
      local rpnt = anchorOf(bar.right)
      H.eq(rpnt, "TOPRIGHT")
      -- Vorschau zwischen den Spalten
      local _, _, _, px = anchorOf(stubs.Preview.frame)
      H.eq(px, 44)
      H.eq(stubs.Preview.frame:GetWidth(), 230)
      H.eq(stubs.FilterBar.frame:GetHeight(), 58)
      H.eq(stubs.Grid.frame:GetHeight(), 444)
      local _, _, _, _, gy = anchorOf(stubs.Grid.frame)
      H.eq(gy, -64)
   end)

   H.test("Vorschau-Modus: die Hinweisleiste schiebt den Inhalt um 22 nach unten", function()
      start()
      W.Open({ fromNpc = false })
      local f = F()
      H.truthy(f.notice:IsShown())
      H.eq(f.left:GetHeight(), 486)
      local _, _, _, _, y = anchorOf(f.left)
      H.eq(y, -60)
      H.eq(lastCall("SlotBar.Layout")[1], 486)
      H.eq(lastCall("Grid.Layout")[2], 422)
      -- per NPC geoeffnet: Leiste weg, Inhalt wieder hoch
      W.Open({ fromNpc = true })
      H.falsy(f.notice:IsShown())
      H.eq(f.left:GetHeight(), 508)
      H.eq(lastCall("Grid.Layout")[2], 444)
   end)

   H.test("Mindestgroesse 740x520: alles passt, rechtes Panel 398 breit", function()
      start()
      DB.Set("width", 740)
      DB.Set("height", 520)
      W.Open({ fromNpc = true })
      local f = F()
      H.eq(f:GetWidth(), 740)
      H.eq(f:GetHeight(), 520)
      H.eq(f.right:GetWidth(), 398)
      H.eq(f.left:GetHeight(), 428, "520 - 46 - 8 - 38")
      H.eq(lastCall("Grid.Layout")[1], 398)
      H.eq(lastCall("Grid.Layout")[2], 364)
   end)

   H.test("Zu kleine gespeicherte Groesse wird beim Anzeigen auf das Minimum gehoben", function()
      start()
      DB.global.width, DB.global.height = 300, 100
      W.Open({ fromNpc = true })
      H.eq(F():GetWidth(), 740)
      H.eq(F():GetHeight(), 520)
      H.eq(DB.global.width, 300, "der gespeicherte Wert wird nicht ueberschrieben")
   end)

   H.test("Grosse Fenster: 1600x1000 bei Scale 1.0 auf 1920x1200", function()
      start({ world = { screenWidth = 1920, screenHeight = 1200 } })
      DB.Set("scale", 1.0)
      DB.Set("width", 1600)
      DB.Set("height", 1000)
      W.Open({ fromNpc = true })
      local f = F()
      H.eq(f:GetScale(), 1.0)
      H.eq(f:GetWidth(), 1600)
      H.eq(f:GetHeight(), 1000)
      H.eq(f.right:GetWidth(), 1600 - 342)
      H.eq(f.left:GetHeight(), 1000 - 46 - 8 - 38)
      H.deepEq(f.__maxResize, { 1920, 1200 })
   end)

   H.test("Scale: automatisch begrenzt auf 0.7..1.5, manuell 0.6..1.5", function()
      start()
      -- 1365x768: min(1365*0.82/880, 768*0.82/600) = 1.0496
      W.Open({ fromNpc = true })
      H.near(F():GetScale(), 768 * 0.82 / 600, 1e-9)
      H.near(W.ComputeScale(), F():GetScale(), 1e-9)
      for _, s in ipairs({ 0.6, 0.8, 1.0, 1.25 }) do
         DB.Set("scale", s)
         H.near(F():GetScale(), s, 1e-9, "manuell " .. s)
      end
      -- 1.5 passt auf 768 Hoehe nicht (520 * 1.5 = 780): so, dass die Mindestgroesse passt
      DB.Set("scale", 1.5)
      H.near(F():GetScale(), 768 / 520, 1e-9)
      DB.Set("scale", 0)
      H.near(F():GetScale(), 768 * 0.82 / 600, 1e-9, "0 = automatisch")
      -- grosser Bildschirm: automatisch hoechstens 1.5, kleiner Wunsch bleibt
      M.SetScreen(3840, 2160)
      M.Advance(1.2)
      H.near(F():GetScale(), 1.5, 1e-9)
      DB.Set("scale", 0.6)
      H.near(F():GetScale(), 0.6, 1e-9)
   end)

   H.test("Scale und Groesse: das Fenster passt immer auf den Bildschirm", function()
      start()
      DB.Set("scale", 1.25)
      DB.Set("width", 1600)
      DB.Set("height", 900)
      W.Open({ fromNpc = true })
      local f = F()
      local sc = f:GetScale()
      H.eq(f:GetWidth(), math.floor(1365 / sc), "Breite auf Bildschirm / Scale geklemmt")
      H.eq(f:GetHeight(), math.floor(768 / sc))
      H.truthy(f:GetWidth() * sc <= 1365 + 1e-9)
      H.truthy(f:GetHeight() * sc <= 768 + 1e-9)
      H.eq(DB.global.width, 1600, "der Wunsch bleibt gespeichert")
      -- kleinerer Scale: die gespeicherte Groesse passt wieder (1600 <= 1365 / 0.8)
      DB.Set("scale", 0.8)
      H.eq(F():GetWidth(), 1600)
      H.eq(F():GetHeight(), 900)
   end)

   H.test("Position: ohne gespeicherten Wert zentriert, sonst wiederhergestellt und geklemmt", function()
      start()
      DB.Set("scale", 1.0)
      W.Open({ fromNpc = true })
      local f = F()
      -- zentriert: (1365 - 880) / 2 = 242.5 von links, oben bei (768 + 600) / 2 = 684
      local p, _, rp, x, y = anchorOf(f)
      H.eq(p, "TOPLEFT")
      H.eq(rp, "BOTTOMLEFT")
      H.near(x, 242.5, 1e-9)
      H.near(y, 684, 1e-9)
      -- gespeichert: { TOPLEFT, BOTTOMLEFT, x, y } in UIParent-Einheiten
      DB.Set("point", { "TOPLEFT", "BOTTOMLEFT", 100, 700 })
      p, _, rp, x, y = anchorOf(f)
      H.near(x, 100, 1e-9)
      H.near(y, 700, 1e-9)
      -- ausserhalb: an den Bildschirm geklemmt
      DB.Set("point", { "TOPLEFT", "BOTTOMLEFT", 5000, -300 })
      p, _, rp, x, y = anchorOf(f)
      H.near(x, 1365 - 880, 1e-9)
      H.near(y, 600, 1e-9, "oben mindestens Fensterhoehe vom unteren Rand")
      -- anderer Ankerpunkt (CENTER/CENTER) wird in TOPLEFT umgerechnet
      DB.Set("point", { "CENTER", "CENTER", 0, 0 })
      p, _, rp, x, y = anchorOf(f)
      H.near(x, 242.5, 1e-9)
      H.near(y, 684, 1e-9)
   end)

   H.test("Position haengt nicht vom Scale ab: dieselbe Stelle in UIParent-Einheiten", function()
      start()
      DB.Set("scale", 1.0)
      DB.Set("point", { "TOPLEFT", "BOTTOMLEFT", 200, 700 })
      W.Open({ fromNpc = true })
      local f = F()
      local _, _, _, x1, y1 = anchorOf(f)
      DB.Set("scale", 0.8)
      local _, _, _, x2, y2 = anchorOf(f)
      H.near(x2 * 0.8, 200, 1e-6)
      H.near(y2 * 0.8, 700, 1e-6)
      H.near(x1, 200, 1e-9)
      H.near(y1, 700, 1e-9)
   end)

   H.test("Fuss: nichts ragt aus dem Fenster, nichts liegt uebereinander (Mindestgroesse, lange Texte)", function()
      start()
      T.Locale.Add("deDE", {
         WIN_DISCARD = "Alle Aenderungen verwerfen",
         WIN_REMOVE_ALL = "Alle Aussehen entfernen",
         WIN_APPLY = "Aenderungen anwenden",
         WIN_APPLY_RESET = "Urspruenglichen Look anwenden",
         WIN_COST = "Gesamtkosten:",
      })
      T.Locale.Set("deDE")
      DB.Set("width", 740)
      DB.Set("height", 520)
      W.Open({ fromNpc = true })
      local f = F()
      local items = { f.btnDiscard, f.btnRemoveAll, f.statusText, f.costText, f.btnApply }
      local prevRight = -1
      for i, o in ipairs(items) do
         local l, r = o:GetLeft(), o:GetRight()
         H.truthy(l and r, "Position aufloesbar " .. i)
         if l and r then
            H.truthy(l >= f:GetLeft() - 1e-6, "links im Fenster " .. i)
            H.truthy(r <= f:GetRight() + 1e-6, "rechts im Fenster " .. i)
            -- Reihenfolge links -> rechts ohne Ueberlappung
            H.truthy(l >= prevRight - 1e-6, "keine Ueberlappung bei " .. i)
            prevRight = r
         end
      end
      -- kein Text laeuft ueber seine Breite: Breite und Hoehe der Textfelder sind gesetzt
      H.truthy(f.statusText:GetWidth() >= 40)
      H.eq(f.statusText:GetHeight(), 14)
      H.eq(f.costText:GetHeight(), 14)
      -- Griff unten rechts: im Fenster und ohne Ueberlappung mit dem Anwenden-Knopf
      H.eq(f.grip:GetWidth(), 12)
      H.truthy(f.grip:GetRight() <= f:GetRight() + 1e-6)
      H.truthy(f.grip:GetBottom() >= f:GetBottom() - 1e-6)
      local apply, grip = f.btnApply, f.grip
      local overlapX = math.min(apply:GetRight(), grip:GetRight()) - math.max(apply:GetLeft(), grip:GetLeft())
      local overlapY = math.min(apply:GetTop(), grip:GetTop()) - math.max(apply:GetBottom(), grip:GetBottom())
      H.truthy(overlapX <= 1e-6 or overlapY <= 1e-6, "Griff und Anwenden-Knopf ueberlappen nicht")
      -- Knoepfe liegen innerhalb des Fusses
      for _, b in ipairs({ f.btnDiscard, f.btnRemoveAll, f.btnApply }) do
         H.truthy(b:GetTop() <= f.footer:GetTop() + 1e-6, "Knopf unter der Oberkante des Fusses")
         H.truthy(b:GetBottom() >= f.footer:GetBottom() - 1e-6, "Knopf ueber der Unterkante des Fusses")
      end
   end)

   -- ======================================================================
   H.section("Reiter und Slotwahl")
   -- ======================================================================

   H.test("Reiter: Outfits zeigt OutfitsTab und versteckt FilterBar/Raster, Items umgekehrt", function()
      start()
      W.Open({ fromNpc = true })
      local f = F()
      H.eq(W.GetTab(), "items")
      H.truthy(f.tabItems:IsSelected())
      H.falsy(f.tabOutfits:IsSelected())
      H.truthy(stubs.Grid.frame:IsShown())
      H.truthy(stubs.FilterBar.frame:IsShown())
      H.falsy(stubs.OutfitsTab.frame:IsShown())

      clearCalls()
      M.Click(f.tabOutfits)
      H.eq(W.GetTab(), "outfits")
      H.eq(DB.global.lastTab, "outfits", "DB.global.lastTab gespeichert")
      H.truthy(f.tabOutfits:IsSelected())
      H.falsy(f.tabItems:IsSelected())
      H.falsy(stubs.Grid.frame:IsShown())
      H.falsy(stubs.FilterBar.frame:IsShown())
      H.truthy(stubs.OutfitsTab.frame:IsShown())
      local ol = lastCall("OutfitsTab.Layout")
      H.eq(ol[1], 538)
      H.eq(ol[2], 508)
      H.truthy(lastCall("OutfitsTab.Refresh"))
      H.eq(stubs.OutfitsTab.frame:GetWidth(), 538)
      H.eq(stubs.OutfitsTab.frame:GetHeight(), 508)

      clearCalls()
      M.Click(f.tabItems)
      H.eq(W.GetTab(), "items")
      H.eq(DB.global.lastTab, "items")
      H.truthy(stubs.Grid.frame:IsShown())
      H.truthy(stubs.FilterBar.frame:IsShown())
      H.falsy(stubs.OutfitsTab.frame:IsShown())
      H.truthy(lastCall("OutfitsTab.Hide"))
      H.eq(lastCall("Grid.Layout")[2], 444)
      H.truthy(lastCall("Grid.Refresh"))
      H.eq(lastCall("FilterBar.Refresh")[1], W.currentSlot)
   end)

   H.test("Reiter: Open(opts.tab) und DB.global.lastTab bestimmen den Start-Reiter", function()
      start()
      W.Open({ fromNpc = true, tab = "outfits" })
      H.eq(W.GetTab(), "outfits")
      H.truthy(stubs.OutfitsTab.frame:IsShown())
      W.Close()
      -- ohne opts.tab gilt der gespeicherte Reiter
      W.Open({ fromNpc = true })
      H.eq(W.GetTab(), "outfits")
      W.SetTab("items")
      W.Close()
      W.Open({})
      H.eq(W.GetTab(), "items")
      -- ungueltige Namen werden zu "items"
      W.SetTab("unsinn")
      H.eq(W.GetTab(), "items")
   end)

   H.test("Reiter: vor dem ersten Oeffnen gesetzt, wirkt beim Bau", function()
      start()
      W.SetTab("outfits")
      H.eq(DB.global.lastTab, "outfits")
      H.eq(W.frame, nil, "SetTab baut das Fenster nicht")
      W.Open({})
      H.eq(W.GetTab(), "outfits")
      H.truthy(stubs.OutfitsTab.frame:IsShown())
   end)

   -- Ein verborgenes DressUpModel verliert im echten Client Auskleidung und Kamera (Spieltest
   -- 2026-10-12): das Fenster laesst die Zellmodelle des Rasters beim Zurueckwechseln zu "Items"
   -- und beim Oeffnen verwerfen (Grid.InvalidateModels), damit das naechste Zeichnen neu ankleidet.
   -- Wer schon auf "Items" steht und nichts verbirgt, behaelt seine Modelle.
   H.test("Reiter: Zurueck zu Items verwirft die Zellmodelle vor dem Zeichnen (einmal); Outfits und der aktive Reiter nicht", function()
      start()
      W.Open({ fromNpc = true })
      local f = F()
      clearCalls()
      M.Click(f.tabOutfits)
      H.eq(#callsOf("Grid.InvalidateModels"), 0, "Outfits: nichts zu verwerfen")
      clearCalls()
      M.Click(f.tabItems)
      H.eq(#callsOf("Grid.InvalidateModels"), 1, "Items: genau einmal")
      local iInv, iRef
      for i, n in ipairs(names()) do
         if n == "Grid.InvalidateModels" and not iInv then iInv = i end
         if n == "Grid.Refresh" and not iRef then iRef = i end
      end
      H.truthy(iInv and iRef and iInv < iRef, "InvalidateModels steht vor Grid.Refresh: " .. table.concat(names(), " "))
      -- Klick auf den aktiven Reiter und SetTab("items") bei Items: die Modelle bleiben
      clearCalls()
      M.Click(f.tabItems)
      W.SetTab("items")
      H.eq(#callsOf("Grid.InvalidateModels"), 0, "aktiver Reiter: nichts verwerfen")
   end)

   H.test("Oeffnen: ein verborgenes Fenster laesst die Zellmodelle vor dem Zeigen verwerfen, ein offenes nicht", function()
      start()
      W.Open({ fromNpc = true })
      W.Close()
      local f = F()
      local shows = 0
      f:HookScript("OnShow", function()
         shows = shows + 1
         rec("Window.OnShow")
      end)
      clearCalls()
      W.Open({ fromNpc = true })
      H.eq(shows, 1)
      H.eq(#callsOf("Grid.InvalidateModels"), 1, "beim Oeffnen genau einmal")
      local iInv, iShow
      for i, n in ipairs(names()) do
         if n == "Grid.InvalidateModels" and not iInv then iInv = i end
         if n == "Window.OnShow" and not iShow then iShow = i end
      end
      H.truthy(iInv and iShow and iInv < iShow, "vor dem Zeigen: " .. table.concat(names(), " "))
      -- noch einmal bei offenem Fenster (Reiter Items): nichts zu verwerfen, nichts neu gezeigt
      clearCalls()
      W.Open({ fromNpc = true })
      H.eq(shows, 1, "kein erneutes Zeigen")
      H.eq(#callsOf("Grid.InvalidateModels"), 0, "offenes Fenster: Modelle bleiben")
      -- Schliessen + Oeffnen auf dem Reiter Outfits: das Raster bleibt verborgen; zurueck zu Items
      -- verwirft (und nur dann kleidet das Raster neu an)
      W.SetTab("outfits")
      W.Close()
      W.Open({ fromNpc = true })
      H.eq(W.GetTab(), "outfits")
      clearCalls()
      W.SetTab("items")
      H.eq(#callsOf("Grid.InvalidateModels"), 1, "Outfits -> Items: einmal")
   end)

   H.test("Slotwahl: Open nimmt opts.slot, sonst lastSlot (wenn bereit), sonst den ersten bereiten", function()
      start()
      -- erster bereiter Slot in Anzeigereihenfolge: Kopf
      W.Open({ fromNpc = true })
      H.eq(W.currentSlot, HEAD)
      H.eq(lastCall("SlotBar.Select")[1], HEAD)
      H.eq(lastCall("Grid.SetSlot")[1], HEAD)
      H.eq(lastCall("FilterBar.Refresh")[1], HEAD)
      H.eq(lastCall("Preview.SetFocusSlot")[1], HEAD)
      H.eq(DB.char.lastSlot, HEAD)
      W.Close()

      -- opts.slot gewinnt, auch wenn kein Gegenstand angelegt ist
      W.Open({ fromNpc = true, slot = SHIRT })
      H.eq(W.currentSlot, SHIRT)
      H.eq(DB.char.lastSlot, SHIRT)
      W.Close()

      -- lastSlot, wenn bereit
      DB.SetChar("lastSlot", BACK)
      W.Open({ fromNpc = true })
      H.eq(W.currentSlot, BACK)
      W.Close()

      -- lastSlot nicht bereit (Wappenrock leer): der erste bereite
      DB.SetChar("lastSlot", 18)
      W.Open({ fromNpc = true })
      H.eq(W.currentSlot, HEAD)
   end)

   H.test("Slotwahl: nichts angelegt -> kein Slot; ungueltige Slots werden abgelehnt", function()
      start({ equip = {} })
      W.Open({ fromNpc = true })
      H.eq(W.currentSlot, nil)
      H.eq(lastCall("Grid.SetSlot")[1], nil)
      H.eq(W.SelectSlot(1), false, "1 ist der Hals (kein transmogbarer Server-Slot)")
      H.eq(W.SelectSlot(99), false)
      H.eq(W.SelectSlot("x"), false)
      H.eq(W.currentSlot, nil)
      H.eq(W.SelectSlot(CHEST), true)
      H.eq(W.currentSlot, CHEST)
      H.eq(W.SelectSlot(nil), true)
      H.eq(W.currentSlot, nil)
   end)

   H.test("Slotwahl per Klick auf die SlotBar; im Outfit-Reiter geht es zurueck zu Items", function()
      start()
      W.Open({ fromNpc = true })
      stubs.SlotBar.onSelect(CHEST)
      H.eq(W.currentSlot, CHEST)
      H.eq(W.GetTab(), "items")
      W.SetTab("outfits")
      clearCalls()
      stubs.SlotBar.onSelect(LEGS)
      H.eq(W.currentSlot, LEGS)
      H.eq(W.GetTab(), "items", "ein Slotklick im Outfit-Reiter zeigt wieder die Aussehen")
      H.eq(lastCall("Grid.SetSlot")[1], LEGS)
   end)

   -- ======================================================================
   H.section("Hinweisleiste")
   -- ======================================================================

   -- Farbe des Streifens der Hinweisleiste (Textur-Vertexfarbe)
   local function noticeStripe()
      local c = F().notice.stripe.__vertex
      return c and c[1], c and c[2], c and c[3]
   end

   H.test("Vorschau-Modus: gelber Hinweis; per NPC, allowAnywhere oder VENDOR_CHANGED weg", function()
      start()
      W.Open({ fromNpc = false })
      local f = F()
      H.truthy(f.notice:IsShown())
      H.eq(f.notice.text:GetText(), T.L.MSG_NO_VENDOR)
      local r, g, b = noticeStripe()
      H.near(r, T.COLORS.yellow[1], 1e-6)
      H.near(g, T.COLORS.yellow[2], 1e-6)
      H.eq(f.notice:GetHeight(), 22)
      H.eq(f.notice:GetWidth(), 878)
      H.eq(f.notice.text:GetHeight(), 14)
      -- allowAnywhere blendet den Hinweis aus und holt ihn zurueck
      DB.Set("allowAnywhere", true)
      H.falsy(f.notice:IsShown())
      H.eq(f.left:GetHeight(), 508)
      DB.Set("allowAnywhere", false)
      H.truthy(f.notice:IsShown())
      H.eq(f.left:GetHeight(), 486)
      -- Transmogrifizierer in Reichweite
      State.SetVendor(true)
      H.falsy(f.notice:IsShown())
      State.SetVendor(false)
      H.truthy(f.notice:IsShown())
   end)

   H.test("Server antwortet nicht: roter Hinweis (vor dem gelben), weg bei der ersten Antwort", function()
      start({ alive = false })
      M.Advance(9)
      H.eq(T.Net.state, "ABSENT")
      W.Open({ fromNpc = true })
      local f = F()
      H.truthy(f.notice:IsShown())
      H.eq(f.notice.text:GetText(), T.L.MSG_SERVER_ABSENT)
      local r, g = noticeStripe()
      H.near(r, T.COLORS.red[1], 1e-6)
      H.near(g, T.COLORS.red[2], 1e-6)
      H.eq(f.left:GetHeight(), 486)
      -- auch im Vorschau-Modus gewinnt Rot
      W.Open({ fromNpc = false })
      H.eq(f.notice.text:GetText(), T.L.MSG_SERVER_ABSENT)
      -- der Server meldet sich
      M.ServerMessage("TransmogStatus:0")
      H.eq(T.Net.state, "OK")
      H.eq(f.notice.text:GetText(), T.L.MSG_NO_VENDOR)
      State.SetVendor(true)
      H.falsy(f.notice:IsShown())
      H.eq(f.left:GetHeight(), 508)
   end)

   -- ======================================================================
   H.section("Fuss: Anwenden, Kosten, Verwerfen, Alles entfernen")
   -- ======================================================================

   -- Beschreibung der Sperre eines Knopfs (nil = freigegeben)
   local function lockReason(btn)
      if btn.uiOff then return btn.disabledTip or "?" end
      return nil
   end

   -- Vorbereitung: Kopf-Liste fertig, Fenster per NPC geoeffnet
   local function openVendor(opts)
      opts = opts or {}
      setList(HEAD, range(200, 230))
      if opts.applied then setApplied(opts.applied) end
      W.Open({ fromNpc = opts.fromNpc ~= false })
      settle(0.1)
   end

   H.test("Anwenden gesperrt: NONE, VENDOR, COST_PENDING, MONEY, SERVER, BUSY mit dem Grund als Text", function()
      start()
      openVendor()
      local f = F()
      -- NONE
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_NONE)
      H.eq(labelOf(f.btnApply), "Apply")
      -- COST_PENDING (Auswahl, Kosten noch nicht beantwortet)
      State.Select(HEAD, 200)
      settle(0.05)
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_COST_PENDING)
      -- MONEY
      answerCost(5000, false)
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_MONEY)
      -- frei
      State.Select(HEAD, 201)
      answerCost(5000, true)
      H.eq(lockReason(f.btnApply), nil)
      H.truthy(f.btnApply:IsEnabledState())
      H.eq(f.btnApply:GetAlpha(), 1)
      -- BUSY: ein Stapel laeuft (keine Serverantwort)
      M.Click(f.btnApply)
      settle(0.1)
      H.truthy(State.Busy())
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_BUSY)
      H.eq(lockReason(f.btnDiscard), T.L.APPLY_REASON_BUSY)
   end)

   H.test("Anwenden gesperrt: VENDOR im Vorschau-Modus, SERVER ohne Modul", function()
      start()
      openVendor({ fromNpc = false })
      local f = F()
      State.Select(HEAD, 200)
      settle(0.1)
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_VENDOR)
      -- allowAnywhere: Kosten werden jetzt der Grund
      DB.Set("allowAnywhere", true)
      settle(0.1)
      H.neq(lockReason(f.btnApply), T.L.APPLY_REASON_VENDOR)
      DB.Set("allowAnywhere", false)

      start({ alive = false })
      M.Advance(9)
      H.eq(T.Net.state, "ABSENT")
      W.Open({ fromNpc = true })
      settle(0.1)
      H.eq(lockReason(F().btnApply), T.L.APPLY_REASON_SERVER)
      H.eq(lockReason(F().btnRemoveAll), T.L.APPLY_REASON_SERVER)
   end)

   H.test("Gesperrter Anwenden-Knopf: Klick wird verworfen, Tooltip nennt den Grund", function()
      start()
      openVendor()
      local f = F()
      M.ClearSent()
      M.Click(f.btnApply)
      H.eq(#M.SentCommands(), 0, "nichts gesendet")
      M.Enter(f.btnApply)
      H.truthy(GameTooltip:IsShown())
      H.truthy(tipHas(T.L.APPLY_REASON_NONE))
      M.Leave(f.btnApply)
      H.eq(f.btnApply:GetAlpha(), 0.45)
   end)

   H.test("Anwenden: Beschriftung 'Apply' / 'Apply reset' (nur Entfernen) und Tooltip mit den Slots", function()
      start()
      openVendor({ applied = { [HEAD] = 200 } })
      local f = F()
      State.Select(HEAD, 0)                    -- Entfernen vormerken
      answerCost(0, true)
      H.eq(labelOf(f.btnApply), "Apply reset")
      H.eq(lockReason(f.btnApply), nil, "Entfernen ist kostenlos und anwendbar")
      State.Select(CHEST, HIDDEN)              -- Verbergen: kein Entfernen
      answerCost(0, true)
      H.eq(labelOf(f.btnApply), "Apply")
      -- Tooltip: Zahl und je Slot Name/Aussehen
      M.Enter(f.btnApply)
      local lines = tipLines()
      H.eq(lines[1], "Apply pending changes: 2")
      H.truthy(tipHas("Head"))
      H.truthy(tipHas("Chest"))
      M.Leave(f.btnApply)
      -- Auswahl verwerfen: wieder "Apply"
      State.DiscardAll()
      settle(0.1)
      H.eq(labelOf(f.btnApply), "Apply")
   end)

   -- Text des Kostenfelds
   local function costText()
      return F().costText:GetText()
   end

   H.test("Kosten: leer ohne Auswahl, '...' waehrend der Anfrage, dann gruen/rot, 'Free' bei 0", function()
      start()
      openVendor()
      local f = F()
      H.eq(costText(), "")
      State.Select(HEAD, 200)
      settle(0.05)
      H.contains(costText(), T.L.WIN_COST)
      H.contains(costText(), "...")
      -- bezahlbar: gruen mit Muenzsymbolen
      answerCost(12345, true)
      local money = T.Util.FormatMoney(12345)
      H.contains(costText(), money)
      H.contains(costText(), T.HEX.green .. money)
      -- zu teuer: rot
      State.Select(HEAD, 201)
      answerCost(12345, false)
      H.contains(costText(), T.HEX.red .. money)
      -- Verborgen ist kostenlos
      State.Discard(HEAD)
      State.Select(CHEST, HIDDEN)
      settle(0.1)
      H.contains(costText(), T.L.WIN_COST_FREE)
      H.contains(costText(), T.HEX.green)
      -- Auswahl weg: Kosten weg
      State.DiscardAll()
      settle(0.1)
      H.eq(costText(), "")
      H.eq(f.costText:GetHeight(), 14)
   end)

   H.test("Kosten: Anfrage ohne Antwort ergibt nach dem Aufgeben '?' (nicht '...')", function()
      start()
      openVendor()
      State.Select(HEAD, 200)
      settle(0.4)
      M.Advance(12)
      local text = costText()
      H.contains(text, T.L.WIN_COST_UNKNOWN)
      H.falsy(contains(text, "..."))
   end)

   H.test("Verwerfen: gesperrt ohne Auswahl, sonst DiscardAll", function()
      start()
      openVendor()
      local f = F()
      H.eq(lockReason(f.btnDiscard), T.L.WIN_DISCARD_NONE)
      State.Select(HEAD, 200)
      State.Select(CHEST, HIDDEN)
      settle(0.1)
      H.eq(State.PendingCount(), 2)
      H.eq(lockReason(f.btnDiscard), nil)
      M.Click(f.btnDiscard)
      H.eq(State.PendingCount(), 0)
      settle(0.1)
      H.eq(lockReason(f.btnDiscard), T.L.WIN_DISCARD_NONE)
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_NONE)
   end)

   -- Knoepfe des Rueckfragedialogs (Skin.Confirm)
   local function confirmButtons()
      local frame = rawget(_G, "TransmogConfirmFrame")
      local out = {}
      if frame and frame:IsShown() then
         for _, b in ipairs(M.Find(frame, "Button")) do
            if b:IsShown() and b.label and b.label.GetText then out[#out + 1] = b end
         end
      end
      return out
   end

   local function confirmButton(text)
      for _, b in ipairs(confirmButtons()) do
         if b.label:GetText() == text then return b end
      end
      return nil
   end

   H.test("Alles entfernen: Rueckfrage, Abbrechen sendet nichts, Bestaetigen sendet RemoveAll", function()
      start()
      openVendor({ applied = { [HEAD] = 200, [CHEST] = 777 } })
      local f = F()
      H.eq(lockReason(f.btnRemoveAll), nil)
      M.Click(f.btnRemoveAll)
      H.truthy(T.UI.Skin.DialogOpen(), "Rueckfrage offen")
      H.truthy(confirmButton("Remove all"), "Bestaetigen-Knopf mit der Beschriftung")
      H.truthy(confirmButton("Cancel"))
      H.truthy(M.HasText(TransmogConfirmFrame, T.L.WIN_REMOVE_ALL_TITLE))
      -- abbrechen
      M.Click(confirmButton("Cancel"))
      H.falsy(T.UI.Skin.DialogOpen())
      H.eq(M.CountSent("RemoveAll"), 0)
      H.eq(State.Applied(HEAD), 200)
      -- bestaetigen
      M.Click(f.btnRemoveAll)
      M.Click(confirmButton("Remove all"))
      H.eq(M.CountSent("RemoveAll"), 1)
      H.eq(State.Applied(HEAD), 0, "lokal sofort nachgezogen")
      H.eq(f.statusText:GetText(), T.L.WIN_REMOVED_ALL)
   end)

   H.test("Alles entfernen: gesperrt im Vorschau-Modus, ohne Aussehen und ohne Server", function()
      start()
      openVendor({ fromNpc = false, applied = { [HEAD] = 200 } })
      local f = F()
      H.eq(lockReason(f.btnRemoveAll), T.L.APPLY_REASON_VENDOR)
      M.Click(f.btnRemoveAll)
      H.falsy(T.UI.Skin.DialogOpen())
      -- mit Transmogrifizierer, aber ohne angewendetes Aussehen
      State.SetVendor(true)
      setApplied({})
      settle(0.1)
      H.eq(lockReason(f.btnRemoveAll), T.L.WIN_REMOVE_ALL_NONE)
      M.Click(f.btnRemoveAll)
      H.falsy(T.UI.Skin.DialogOpen())
      H.eq(M.CountSent("RemoveAll"), 0)
   end)

   -- ======================================================================
   H.section("Anwenden ueberall (Vorgabe seit 2.1)")
   -- ======================================================================
   -- Der Server prueft den Abstand zum Transmogrifizierer nicht; seit 2.1 ist "Anwenden auch ohne
   -- Transmogrifizierer" deshalb standardmaessig an (Neuinstallation = noSeed). Der Vorschau-Modus (gelbe
   -- Hinweisleiste, Anwenden gesperrt) gibt es nur noch, wenn der Spieler die Option ausschaltet.

   H.test("Vorgabe an: ohne NPC keine gelbe Hinweisleiste, Inhalt in voller Hoehe, auch per Toggle", function()
      start({ noSeed = true })
      H.eq(DB.global.allowAnywhere, true)
      W.Open({ fromNpc = false })
      local f = F()
      H.eq(State.atVendor, false)
      H.falsy(f.notice:IsShown(), "keine Hinweisleiste")
      H.eq(f.left:GetHeight(), 508, "volle Hoehe wie am NPC")
      H.eq(lastCall("SlotBar.Layout")[1], 508)
      H.eq(lastCall("Grid.Layout")[2], 444)
      W.Close()
      W.Toggle()
      H.truthy(W.IsShown())
      H.falsy(F().notice:IsShown())
      H.eq(State.openedByNpc, false)
      -- am NPC geoeffnet: gleiches Bild
      W.Open({ fromNpc = true })
      H.falsy(F().notice:IsShown())
      H.eq(f.left:GetHeight(), 508)
      H.eq(State.atVendor, true)
   end)

   H.test("Vorgabe an: fehlt das Servermodul, bleibt die rote Hinweisleiste auch ohne NPC", function()
      start({ noSeed = true, alive = false })
      M.Advance(9)
      H.eq(T.Net.state, "ABSENT")
      W.Open({ fromNpc = false })
      local f = F()
      H.truthy(f.notice:IsShown())
      H.eq(f.notice.text:GetText(), T.L.MSG_SERVER_ABSENT)
      settle(0.1)
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_SERVER)
      H.eq(lockReason(f.btnRemoveAll), T.L.APPLY_REASON_SERVER)
      M.ServerMessage("TransmogStatus:0")
      H.falsy(f.notice:IsShown(), "Server da, kein NPC noetig: Leiste weg")
   end)

   H.test("Vorgabe an: Anwenden ist ohne NPC frei und sendet; gesperrt bleibt es bei NONE, COST_PENDING und MONEY", function()
      start({ noSeed = true })
      openVendor({ fromNpc = false })
      local f = F()
      H.eq(State.atVendor, false)
      -- nichts ausgewaehlt
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_NONE)
      -- Kosten noch offen
      State.Select(HEAD, 200)
      settle(0.05)
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_COST_PENDING)
      -- zu wenig Geld
      answerCost(5000, false)
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_MONEY)
      -- frei: Klick sendet, Erfolg wird verbucht
      State.Select(HEAD, 201)
      answerCost(5000, true)
      H.eq(lockReason(f.btnApply), nil)
      H.truthy(f.btnApply:IsEnabledState())
      H.eq(f.btnApply:GetAlpha(), 1)
      M.ClearSent()
      M.Click(f.btnApply)
      local cmds = M.SentCommands()
      H.eq(cmds[#cmds], "Apply:0:201")
      M.ServerMessage("ApplyTransmogResult:1:0,201")
      settle(0.2)
      H.eq(State.Applied(HEAD), 201)
      H.eq(State.Busy(), false)
   end)

   H.test("Vorgabe an: Alles entfernen funktioniert ohne NPC (Rueckfrage, RemoveAll gesendet)", function()
      start({ noSeed = true })
      openVendor({ fromNpc = false, applied = { [HEAD] = 200, [CHEST] = 777 } })
      local f = F()
      H.eq(State.atVendor, false)
      H.eq(lockReason(f.btnRemoveAll), nil)
      M.Click(f.btnRemoveAll)
      H.truthy(T.UI.Skin.DialogOpen(), "Rueckfrage offen")
      M.Click(confirmButton("Remove all"))
      H.eq(M.CountSent("RemoveAll"), 1)
      H.eq(State.Applied(HEAD), 0, "lokal sofort nachgezogen")
      H.eq(f.statusText:GetText(), T.L.WIN_REMOVED_ALL)
      -- ohne angewendetes Aussehen bleibt es gesperrt (anderer Grund als VENDOR)
      setApplied({})
      settle(0.1)
      H.eq(lockReason(f.btnRemoveAll), T.L.WIN_REMOVE_ALL_NONE)
   end)

   H.test("Vorgabe an, dann ausgeschaltet: gelbe Leiste und Sperre kommen zurueck, auch nach Neuanmeldung", function()
      start({ noSeed = true })
      openVendor({ fromNpc = false, applied = { [HEAD] = 200 } })
      local f = F()
      State.Select(HEAD, 201)
      answerCost(5000, true)
      H.eq(lockReason(f.btnApply), nil)
      H.falsy(f.notice:IsShown())
      -- Spieler schaltet "Anwenden auch ohne Transmogrifizierer" aus
      DB.Set("allowAnywhere", false)
      settle(0.1)
      H.truthy(f.notice:IsShown(), "Vorschau-Modus")
      H.eq(f.notice.text:GetText(), T.L.MSG_NO_VENDOR)
      H.eq(f.left:GetHeight(), 486)
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_VENDOR)
      H.eq(lockReason(f.btnRemoveAll), T.L.APPLY_REASON_VENDOR)
      M.ClearSent()
      M.Click(f.btnApply)
      M.Click(f.btnRemoveAll)
      H.eq(#M.SentCommands(), 0, "nichts gesendet")
      H.falsy(T.UI.Skin.DialogOpen())
      -- wieder an
      DB.Set("allowAnywhere", true)
      settle(0.1)
      H.falsy(f.notice:IsShown())
      H.eq(lockReason(f.btnApply), nil)
      -- aus, abmelden, anmelden: bleibt aus, Fenster oeffnet im Vorschau-Modus
      DB.Set("allowAnywhere", false)
      local sv = M.SavedVariables()
      start({ saved = sv })
      H.eq(DB.global.allowAnywhere, false, "Wahl ueberlebt die Neuanmeldung")
      W.Open({ fromNpc = false })
      H.truthy(F().notice:IsShown())
      H.eq(F().notice.text:GetText(), T.L.MSG_NO_VENDOR)
      -- am NPC trotzdem normal
      W.Open({ fromNpc = true })
      H.falsy(F().notice:IsShown())
   end)

   H.test("Vorgabe an: /transmog oeffnet im Anwenden-Modus, der NPC bleibt unveraendert (Weggehen schliesst)", function()
      start({ noSeed = true })
      M.Slash("/transmog")
      H.truthy(W.IsShown())
      H.eq(State.openedByNpc, false)
      H.eq(State.atVendor, false)
      H.falsy(F().notice:IsShown(), "kein Vorschau-Modus")
      -- Anwenden gilt als moeglich (nur noch Auswahl/Kosten entscheiden)
      setList(HEAD, range(200, 230))
      State.Select(HEAD, 200)
      answerCost(5000, true)
      H.eq(lockReason(F().btnApply), nil)
      H.deepEq({ State.CanApply() }, { true })
      -- NPC darueber: wie bisher ein Transmogrifizierer-Fenster
      M.OpenNpc()
      H.truthy(W.IsShown())
      H.eq(State.atVendor, true)
      H.eq(State.openedByNpc, true)
      H.falsy(F().notice:IsShown())
      H.eq(lockReason(F().btnApply), nil)
      -- Weggehen vom NPC schliesst das NPC-Fenster wie zuvor
      M.Advance(2)
      M.Fire("GOSSIP_CLOSED")
      H.falsy(W.IsShown())
      -- /transmog schliesst wieder
      M.Slash("/transmog")
      H.truthy(W.IsShown())
      M.Slash("/transmog")
      H.falsy(W.IsShown())
   end)

   -- ======================================================================
   H.section("Anwenden: Ereignisse, Ton, Blinken, Status")
   -- ======================================================================

   -- Wartet, bis eine Server-Operation vorliegt, und antwortet
   local function lastSent()
      local c = M.SentCommands()
      return c[#c]
   end

   H.test("Anwenden: Klick sendet Apply, Erfolg blinkt gruen, Ton und Meldung am Ende", function()
      start()
      openVendor()
      State.Select(HEAD, 200)
      answerCost(5000, true)
      local f = F()
      M.ClearSent()
      clearCalls()
      M.Click(f.btnApply)
      H.eq(lastSent(), "Apply:0:200")
      H.contains(f.statusText:GetText(), "1", "Anwenden laeuft: Status nennt die Anzahl")
      H.eq(f.statusText:GetText(), "Applying changes (1)...")
      M.ServerMessage("ApplyTransmogResult:1:0,200")
      local fl = lastCall("SlotBar.Flash")
      H.truthy(fl, "SlotBar.Flash")
      H.eq(fl[1], HEAD)
      H.eq(fl[2], true)
      settle(0.1)
      H.eq(f.statusText:GetText(), T.L.MSG_APPLY_OK)
      -- Ton: genau der Standardton des Clients, keine Datei des Addons
      local names = {}
      for _, s in ipairs(M.sounds) do
         H.neq(s.kind, "file", "das Addon spielt keine eigene Datei")
         if s.kind == "sound" and s.name == SOUND_APPLY then names[#names + 1] = s.name end
      end
      H.deepEq(names, { SOUND_APPLY })
      H.eq(State.Applied(HEAD), 200)
      H.eq(State.PendingCount(), 0)
      settle(0.1)
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_NONE)
      -- State schreibt nichts in den Chat (die Oberflaeche zeigt es in der Statuszeile)
      H.eq(State.chatMessages, false)
   end)

   H.test("Anwenden: Fehlschlag blinkt rot, Meldung nennt den Slot, kein Ton", function()
      start()
      openVendor()
      State.Select(HEAD, 200)
      answerCost(5000, true)
      local f = F()
      clearCalls()
      M.Click(f.btnApply)
      M.ServerMessage("ApplyTransmogResult:0")
      local fl = lastCall("SlotBar.Flash")
      H.eq(fl[1], HEAD)
      H.eq(fl[2], false)
      -- scheitert die einzige Operation, nennt die Meldung den Slot
      H.eq(f.statusText:GetText(), string.format(T.L.MSG_APPLY_SLOT_FAILED, "Head"))
      for _, s in ipairs(M.sounds) do
         H.neq(s.name, SOUND_APPLY, "kein Ton bei Fehlschlag")
      end
      -- Auswahl bleibt, Knopf wieder frei (kein ewiges Warten)
      H.eq(State.PendingCount(), 1)
      H.falsy(State.Busy())
      answerCost(5000, true)
      H.eq(lockReason(f.btnApply), nil)
   end)

   H.test("Anwenden: Fehlschlagsmeldung des Slots erscheint, bevor die Zusammenfassung kommt", function()
      start()
      openVendor()
      State.Select(HEAD, 200)
      State.Select(CHEST, HIDDEN)
      answerCost(5000, true)
      local f = F()
      M.Click(f.btnApply)
      -- erste Operation (Kopf) schlaegt fehl: Meldung mit dem Slotnamen
      M.ServerMessage("ApplyTransmogResult:0")
      H.eq(f.statusText:GetText(), string.format(T.L.MSG_APPLY_SLOT_FAILED, "Head"))
      -- zweite gelingt: Zusammenfassung 1 geaendert, 1 fehlgeschlagen; Ton wegen nOk > 0
      M.ServerMessage("ApplyTransmogResult:1:4," .. HIDDEN)
      H.eq(f.statusText:GetText(), string.format(T.L.MSG_APPLY_DONE, 1, 1))
      local sounds = 0
      for _, s in ipairs(M.sounds) do
         if s.kind == "sound" and s.name == SOUND_APPLY then sounds = sounds + 1 end
      end
      H.eq(sounds, 1)
   end)

   H.test("Anwenden: DB.global.sound = false schaltet den Ton ab", function()
      start()
      DB.Set("sound", false)
      openVendor()
      State.Select(HEAD, 200)
      answerCost(5000, true)
      M.Click(F().btnApply)
      M.ServerMessage("ApplyTransmogResult:1:0,200")
      H.eq(F().statusText:GetText(), T.L.MSG_APPLY_OK)
      for _, s in ipairs(M.sounds) do
         H.neq(s.name, SOUND_APPLY, "Ton ausgeschaltet")
      end
   end)

   H.test("Statuszeile: Meldung zeitlich begrenzt, danach 'Pending changes' oder leer", function()
      start()
      openVendor()
      local f = F()
      W.SetStatus("Hallo", "green")
      H.eq(f.statusText:GetText(), "Hallo")
      local r, g = f.statusText:GetTextColor()
      H.near(r, T.COLORS.green[1], 1e-6)
      H.near(g, T.COLORS.green[2], 1e-6)
      M.Advance(5)
      H.eq(f.statusText:GetText(), "Hallo")
      M.Advance(2)
      H.eq(f.statusText:GetText(), "", "Leerlauf ohne Aenderungen: leer")
      State.Select(HEAD, 200)
      settle(0.1)
      H.eq(f.statusText:GetText(), "Pending changes: 1")
      -- eine neue Meldung ersetzt die alte und startet die Frist neu
      W.SetStatus("Eins", "red")
      M.Advance(4)
      W.SetStatus("Zwei", "yellow")
      M.Advance(4)
      H.eq(f.statusText:GetText(), "Zwei", "die erste Frist loescht die zweite Meldung nicht")
      M.Advance(3)
      H.eq(f.statusText:GetText(), "Pending changes: 1")
      -- explizit leeren
      W.SetStatus("Drei", "dim")
      W.SetStatus(nil)
      H.eq(f.statusText:GetText(), "Pending changes: 1")
      -- vor dem Bau: keine Fehler (Meldung wird gemerkt)
   end)

   H.test("OutfitsTab.onStatus setzt die Statuszeile des Fensters", function()
      start()
      openVendor()
      H.eq(type(stubs.OutfitsTab.onStatus), "function")
      stubs.OutfitsTab.onStatus("7 pieces loaded, 1 unavailable", "yellow")
      H.eq(F().statusText:GetText(), "7 pieces loaded, 1 unavailable")
   end)

   -- ======================================================================
   H.section("Oeffnen und Schliessen")
   -- ======================================================================

   H.test("Oeffnen per NPC: openedByNpc, atVendor, openedAt, VENDOR_CHANGED; Schliessen ruft CloseGossip", function()
      start()
      local vendor = {}
      T.Events.On("VENDOR_CHANGED", function(v) vendor[#vendor + 1] = v end, vendor)
      M.world.gossipOpen = true
      M.Advance(2)
      W.Open({ fromNpc = true })
      H.eq(State.openedByNpc, true)
      H.eq(State.atVendor, true)
      H.eq(W.openedAt, GetTime())
      H.deepEq(vendor, { true })
      H.truthy(W.IsShown())
      W.Close()
      H.falsy(W.IsShown())
      H.eq(M.world.gossipOpen, false, "OnHide ruft CloseGossip nur bei NPC-Oeffnung")
      H.eq(State.openedByNpc, false)
      H.eq(State.atVendor, false)
      H.deepEq(vendor, { true, false })
   end)

   H.test("Vorschau-Modus: Schliessen laesst ein fremdes Gossip-Fenster in Ruhe", function()
      start()
      M.world.gossipOpen = true
      W.Open({ fromNpc = false })
      H.eq(State.openedByNpc, false)
      H.eq(State.atVendor, false)
      W.Close()
      H.eq(M.world.gossipOpen, true, "kein CloseGossip im Vorschau-Modus")
   end)

   H.test("Toggle oeffnet im Vorschau-Modus und schliesst wieder; Open merkt sich die Zeit", function()
      start()
      W.Toggle()
      H.truthy(W.IsShown())
      H.eq(State.openedByNpc, false)
      H.eq(State.atVendor, false)
      H.truthy(F().notice:IsShown())
      local t0 = W.openedAt
      M.Advance(5)
      W.Toggle()
      H.falsy(W.IsShown())
      W.Open({})
      H.truthy(W.openedAt >= t0 + 4.9, "openedAt wird bei jedem Oeffnen neu gesetzt")
      -- Open auf ein offenes Fenster setzt nur den Zustand neu (kein erneutes Zeigen)
      W.Open({ fromNpc = true })
      H.eq(State.openedByNpc, true)
      H.eq(State.atVendor, true)
      H.falsy(F().notice:IsShown())
      H.truthy(W.IsShown())
   end)

   H.test("Open ruft State.Refresh genau einmal und sendet Status- und Listenanfrage", function()
      start()
      M.ClearSent()
      -- Listen sind noch nie angefordert worden: Refresh fordert beide an
      W.Open({ fromNpc = true })
      local sent = M.SentCommands()
      H.eq(M.CountSent("GetTransmogStatus"), 1)
      H.truthy(M.CountSent("GetAvailableTransmogs") <= 1)
      H.truthy(#sent >= 1)
   end)

   H.test("Verbergen schliesst Menue, Dialog und Optionen", function()
      start()
      openVendor({ applied = { [HEAD] = 200 } })
      local skin = T.UI.Skin
      skin.Menu.Open(F().btnOptions, { { text = "a" }, { text = "b" } })
      H.truthy(skin.Menu.IsOpen())
      clearCalls()
      W.Close()
      H.falsy(skin.Menu.IsOpen(), "Menue zu")
      H.truthy(lastCall("Options.Close"), "Options.Close gerufen")

      openVendor({ applied = { [HEAD] = 200 } })
      M.Click(F().btnRemoveAll)
      H.truthy(skin.DialogOpen())
      W.Close()
      H.falsy(skin.DialogOpen(), "Dialog zu")
      -- Schliessen ohne Rueckfrage-Nebenwirkung
      H.eq(M.CountSent("RemoveAll"), 0)
   end)

   H.test("UI ausblenden (Alt-Z): der NPC-Zustand bleibt, kein CloseGossip; beim Einblenden geht es weiter", function()
      start()
      M.world.gossipOpen = true
      W.Open({ fromNpc = true })
      local f = F()
      UIParent:Hide()
      H.falsy(f:IsVisible(), "durch den Elternrahmen unsichtbar")
      H.eq(State.openedByNpc, true)
      H.eq(State.atVendor, true)
      H.eq(M.world.gossipOpen, true, "kein CloseGossip, wenn nur das UI ausgeblendet ist")
      H.eq(f.watcher:GetScript("OnUpdate"), nil, "kein Beobachter, solange nichts zu sehen ist")
      UIParent:Show()
      H.truthy(f:IsVisible())
      H.truthy(f.watcher:GetScript("OnUpdate"))
      H.eq(State.atVendor, true)
      W.Close()
      H.eq(State.atVendor, false)
   end)

   H.test("Optionen-Knopf schaltet das Optionsfenster um (Toggle)", function()
      start()
      W.Open({ fromNpc = true })
      clearCalls()
      M.Click(F().btnOptions)
      H.truthy(lastCall("Options.Toggle"))
      H.truthy(stubs.Options.open)
      M.Click(F().btnOptions)
      H.falsy(stubs.Options.open)
   end)

   H.test("Schliessen-Knopf und ESC schliessen; ein offener Dialog faengt das erste ESC", function()
      start()
      openVendor({ applied = { [HEAD] = 200 } })
      M.Click(F().btnClose)
      H.falsy(W.IsShown())

      openVendor({ applied = { [HEAD] = 200 } })
      H.truthy(M.Escape())
      H.falsy(W.IsShown(), "ESC schliesst das Fenster (UISpecialFrames)")

      openVendor({ applied = { [HEAD] = 200 } })
      M.Click(F().btnRemoveAll)
      H.truthy(T.UI.Skin.DialogOpen())
      M.Escape()
      H.falsy(T.UI.Skin.DialogOpen(), "erstes ESC schliesst nur den Dialog")
      H.truthy(W.IsShown())
      M.Escape()
      H.falsy(W.IsShown())
   end)

   H.test("Tooltips der Kopfknoepfe und des Griffs", function()
      start()
      W.Open({ fromNpc = true })
      local f = F()
      M.Enter(f.btnClose)
      H.truthy(tipHas("Close"))
      M.Leave(f.btnClose)
      M.Enter(f.btnOptions)
      H.truthy(tipHas("Options"))
      M.Leave(f.btnOptions)
      M.Enter(f.grip)
      H.truthy(tipHas("Drag to resize the window."))
      M.Leave(f.grip)
      H.falsy(GameTooltip:IsShown())
   end)

   -- ======================================================================
   H.section("Groesse und Position speichern, Aufloesung, Zuruecksetzen")
   -- ======================================================================

   H.test("Ziehen am Griff: Groesse live, bei Maus hoch gespeichert, Modelle einmal neu", function()
      start({ world = { screenWidth = 1920, screenHeight = 1200 } })
      DB.Set("scale", 1.0)
      W.Open({ fromNpc = true })
      local f = F()
      M.world.mouseDown = { LeftButton = true }
      clearCalls()
      M.Drag(f.grip, 100, -60)       -- nach rechts unten (y zaehlt nach oben)
      H.eq(f:GetWidth(), 980)
      H.eq(f:GetHeight(), 660)
      H.eq(DB.global.width, 980)
      H.eq(DB.global.height, 660)
      H.eq(f.right:GetWidth(), 980 - 342)
      H.eq(lastCall("Grid.Layout")[1], 638)
      H.eq(lastCall("Grid.Layout")[2], 660 - 46 - 8 - 38 - 64)
      H.eq(#callsOf("Preview.Rebuild"), 1, "Modelle genau einmal neu aufgebaut")
      H.eq(#callsOf("Grid.Refresh"), 1)
      H.eq(f.grip:GetScript("OnUpdate"), nil, "kein haengender OnUpdate")
      M.Advance(1)
      H.eq(#callsOf("Preview.Rebuild"), 1, "kein Nachlaufen")
   end)

   H.test("Ziehen am Griff: Mindestgroesse und Bildschirmgrenze; das Raster wird mit Rebuild neu gekleidet", function()
      start({ world = { screenWidth = 1920, screenHeight = 1200 }, gridRebuild = true })
      DB.Set("scale", 1.0)
      W.Open({ fromNpc = true })
      local f = F()
      M.Drag(f.grip, -2000, 2000)
      H.eq(f:GetWidth(), 740)
      H.eq(f:GetHeight(), 520)
      H.eq(DB.global.width, 740)
      M.Drag(f.grip, 5000, -5000)
      H.eq(f:GetWidth(), 1920)
      H.eq(f:GetHeight(), 1200)
      H.truthy(#callsOf("Grid.Rebuild") >= 2, "Grid.Rebuild statt Refresh")
      H.eq(#callsOf("Grid.Refresh"), 0)
   end)

   H.test("Ziehen am Griff: waechst das Fenster ueber den Rand, rutscht es ins Bild und die Position wird gemerkt", function()
      start()
      DB.Set("scale", 1.0)
      W.Open({ fromNpc = true })
      local f = F()
      M.Drag(f.grip, 5000, -5000)
      H.eq(f:GetWidth(), 1365)
      H.eq(f:GetHeight(), 768)
      local p = DB.global.point
      H.eq(type(p), "table")
      H.near(p[3], 0, 1e-6, "links bei 0")
      H.near(p[4], 768, 1e-6, "oben am oberen Rand")
      local _, _, _, x, y = f:GetPoint(1)
      H.near(x, 0, 1e-6)
      H.near(y, 768, 1e-6)
   end)

   H.test("Griff: ein verpasstes OnMouseUp beendet das Ziehen (Sicherheitsnetz), Verbergen auch", function()
      start()
      W.Open({ fromNpc = true })
      local f = F()
      M.world.mouseDown = { LeftButton = true }
      M.MouseDown(f.grip, "LeftButton")
      H.truthy(f.grip:GetScript("OnUpdate"), "waehrend des Ziehens")
      M.Advance(0.1)
      H.truthy(f.grip:GetScript("OnUpdate"), "Taste noch gedrueckt")
      M.world.mouseDown = nil
      M.Advance(0.1)
      H.eq(f.grip:GetScript("OnUpdate"), nil, "Taste losgelassen, OnUpdate weg")
      -- Fenster schliessen mitten im Ziehen
      M.world.mouseDown = { LeftButton = true }
      M.MouseDown(f.grip, "LeftButton")
      W.Close()
      H.eq(f.grip:GetScript("OnUpdate"), nil)
   end)

   H.test("Ziehen am Kopf: Position wird gespeichert und in der naechsten Sitzung wiederhergestellt", function()
      start()
      DB.Set("scale", 1.0)
      W.Open({ fromNpc = true })
      local f = F()
      M.Drag(f.head, 50, -30)
      local p = DB.global.point
      H.eq(type(p), "table")
      H.eq(p[1], "TOPLEFT")
      H.eq(p[2], "BOTTOMLEFT")
      H.near(p[3], 292.5, 1e-6)
      H.near(p[4], 654, 1e-6)
      local _, _, _, x, y = f:GetPoint(1)
      H.near(x, 292.5, 1e-6)
      H.near(y, 654, 1e-6)

      -- neue Sitzung mit den gespeicherten Variablen
      local sv = M.SavedVariables()
      start({ saved = sv })
      W.Open({ fromNpc = true })
      local _, _, _, x2, y2 = F():GetPoint(1)
      local sc = F():GetScale()
      H.near(x2 * sc, 292.5, 1e-6)
      H.near(y2 * sc, 654, 1e-6)
   end)

   H.test("Verschieben am Kopf: nicht ueber den Bildschirmrand hinaus (Klemme beim Speichern)", function()
      start()
      DB.Set("scale", 1.0)
      W.Open({ fromNpc = true })
      M.Drag(F().head, 5000, 5000)
      local p = DB.global.point
      H.near(p[3], 1365 - 880, 1e-6)
      H.near(p[4], 768, 1e-6)
      M.Drag(F().head, -9000, -9000)
      p = DB.global.point
      H.near(p[3], 0, 1e-6)
      H.near(p[4], 600, 1e-6)
   end)

   H.test("Aufloesungswechsel: einmal je Sekunde geprueft, Scale und Groesse neu, Modelle neu", function()
      start()
      W.Open({ fromNpc = true })
      local f = F()
      local s1 = f:GetScale()
      H.near(s1, 768 * 0.82 / 600, 1e-9)
      H.truthy(f.watcher:GetScript("OnUpdate"), "Beobachter laeuft nur, solange das Fenster offen ist")
      clearCalls()
      M.SetScreen(1920, 1080)
      M.Advance(0.5)
      H.near(f:GetScale(), s1, 1e-9, "noch nicht abgefragt")
      M.Advance(0.7)
      H.near(f:GetScale(), 1080 * 0.82 / 600, 1e-9)
      M.Advance(0.2)
      H.truthy(#callsOf("Preview.Rebuild") >= 1, "Modelle neu aufgebaut")
      -- kleinerer Bildschirm: Groesse wird geklemmt, Position bleibt im Bild
      DB.Set("width", 1400)
      DB.Set("height", 900)
      M.SetScreen(1024, 768)
      M.Advance(1.2)
      local sc = f:GetScale()
      H.truthy(f:GetWidth() * sc <= 1024 + 1e-9)
      H.truthy(f:GetHeight() * sc <= 768 + 1e-9)
      H.truthy(f:GetWidth() >= 740)
      local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
      H.truthy(l >= -1e-6 and b >= -1e-6, "links/unten im Bild")
      H.truthy(r * sc <= 1024 + 1e-6 and t * sc <= 768 + 1e-6, "rechts/oben im Bild")
      -- zurueck auf den grossen Bildschirm: der Wunsch (1400x900) kommt wieder
      M.SetScreen(1920, 1200)
      M.Advance(1.2)
      H.eq(f:GetWidth(), math.min(1400, math.floor(1920 / f:GetScale())))
   end)

   H.test("Aufloesungswechsel bei geschlossenem Fenster: kein OnUpdate, Nachholen beim Oeffnen", function()
      start()
      W.Open({ fromNpc = true })
      local f = F()
      W.Close()
      H.eq(f.watcher:GetScript("OnUpdate"), nil, "kein OnUpdate, solange das Fenster zu ist")
      for _, fr in ipairs(M.UpdateFrames()) do
         local p, inside = fr, false
         while p do
            if p == f then inside = true end
            p = p:GetParent()
         end
         H.falsy(inside, "kein sichtbarer OnUpdate im Fenster")
      end
      local s1 = f:GetScale()
      M.SetScreen(1920, 1080)
      M.Advance(3)
      H.near(f:GetScale(), s1, 1e-9)
      W.Open({ fromNpc = true })
      H.near(f:GetScale(), 1080 * 0.82 / 600, 1e-9, "beim Zeigen nachgeholt")
   end)

   H.test("ResetLayout: Position weg, Standardgroesse, Scale bleibt; auch vor dem Bau", function()
      start({ world = { screenWidth = 1920, screenHeight = 1200 } })
      DB.Set("scale", 1.0)
      DB.Set("width", 1200)
      DB.Set("height", 800)
      DB.Set("point", { "TOPLEFT", "BOTTOMLEFT", 10, 900 })
      W.ResetLayout()      -- vor dem Bau: nur die Werte
      H.eq(DB.global.width, 880)
      H.eq(DB.global.height, 600)
      H.eq(DB.global.point, nil)
      H.eq(W.frame, nil)
      DB.Set("width", 1200)
      DB.Set("point", { "TOPLEFT", "BOTTOMLEFT", 10, 900 })
      W.Open({ fromNpc = true })
      H.eq(F():GetWidth(), 1200)
      clearCalls()
      W.ResetLayout()
      H.eq(F():GetWidth(), 880)
      H.eq(F():GetHeight(), 600)
      H.eq(DB.global.point, nil)
      H.eq(DB.global.scale, 1.0, "der Scale bleibt")
      local _, _, _, x, y = F():GetPoint(1)
      H.near(x, (1920 - 880) / 2, 1e-6)
      H.near(y, (1200 + 600) / 2, 1e-6)
      H.eq(lastCall("Grid.Layout")[1], 880 - 342)
   end)

   H.test("Einstellungen von aussen: width/height/scale/point wirken sofort", function()
      start({ world = { screenWidth = 1920, screenHeight = 1200 } })
      DB.Set("scale", 1.0)
      W.Open({ fromNpc = true })
      DB.Set("width", 1000)
      H.eq(F():GetWidth(), 1000)
      DB.Set("height", 700)
      H.eq(F():GetHeight(), 700)
      DB.Set("scale", 0.8)
      H.near(F():GetScale(), 0.8, 1e-9)
      DB.Set("point", { "TOPLEFT", "BOTTOMLEFT", 40, 800 })
      local _, _, _, x, y = F():GetPoint(1)
      H.near(x, 40 / 0.8, 1e-6)
      H.near(y, 800 / 0.8, 1e-6)
   end)

   -- ======================================================================
   H.section("Sprache, Aktualisierung, Robustheit")
   -- ======================================================================

   H.test("Sprachwechsel: Reiter, Knoepfe, Hinweis und Fuss in der neuen Sprache", function()
      start()
      T.Locale.Add("deDE", {
         WIN_TAB_ITEMS = "Gegenstaende", WIN_TAB_OUTFITS = "Outfits",
         WIN_DISCARD = "Verwerfen", WIN_REMOVE_ALL = "Alles entfernen",
         WIN_APPLY = "Anwenden", WIN_APPLY_RESET = "Zuruecksetzen anwenden",
         WIN_COST = "Kosten:", WIN_OPTIONS = "Optionen",
         MSG_NO_VENDOR = "Vorschau - besuche einen Transmogrifizierer.",
      })
      W.Open({ fromNpc = false })
      local f = F()
      T.Locale.Set("deDE")
      H.eq(labelOf(f.tabItems), "Gegenstaende")
      H.eq(labelOf(f.btnDiscard), "Verwerfen")
      H.eq(labelOf(f.btnRemoveAll), "Alles entfernen")
      H.eq(labelOf(f.btnApply), "Anwenden")
      H.eq(f.notice.text:GetText(), "Vorschau - besuche einen Transmogrifizierer.")
      State.Select(HEAD, 200)
      settle(0.1)
      H.contains(f.costText:GetText(), "Kosten:")
      -- Tooltip des Options-Knopfs
      M.Enter(f.btnOptions)
      H.truthy(tipHas("Optionen"))
      M.Leave(f.btnOptions)
      -- zurueck
      T.Locale.Set("enUS")
      H.eq(labelOf(f.tabItems), "Items")
      H.eq(labelOf(f.btnApply), "Apply")
   end)

   H.test("RefreshAll zeichnet alle Komponenten genau einmal neu", function()
      start()
      W.Open({ fromNpc = true })
      clearCalls()
      W.RefreshAll()
      H.eq(#callsOf("SlotBar.Refresh"), 1)
      H.eq(#callsOf("Preview.Refresh"), 1)
      H.eq(#callsOf("FilterBar.Refresh"), 1)
      H.eq(#callsOf("Grid.Refresh"), 1)
      H.eq(#callsOf("OutfitsTab.Refresh"), 0)
      W.SetTab("outfits")
      clearCalls()
      W.RefreshAll()
      H.eq(#callsOf("OutfitsTab.Refresh"), 1)
      H.eq(#callsOf("Grid.Refresh"), 0)
   end)

   H.test("Viele Ereignisse hintereinander: der Fuss wird gebuendelt gezeichnet", function()
      start()
      openVendor()
      local f = F()
      local sets = 0
      local orig = f.btnApply.SetLabel
      f.btnApply.SetLabel = function(self, text)
         sets = sets + 1
         return orig(self, text)
      end
      for i = 1, 10 do
         State.Select(HEAD, 200 + i)
      end
      H.eq(sets, 0, "sofort noch nichts (entprellt)")
      settle(0.1)
      H.eq(sets, 1, "ein Zeichnen fuer alle Aenderungen")
   end)

   H.test("Unsichtbar: Ereignisse zeichnen nichts; beim Zeigen wird der Fuss nachgeholt", function()
      start()
      openVendor()
      local f = F()
      W.Close()
      State.Select(HEAD, 200)
      settle(0.5)
      -- (kein Vendor mehr: egal; es zaehlt, dass der Fuss beim Zeigen stimmt)
      W.Open({ fromNpc = true })
      settle(0.1)
      H.eq(State.PendingCount(), 1)
      H.contains(f.statusText:GetText(), "1")
   end)

   H.test("Hygiene: keine fremden Globals ausser TransmogWindow, kein Handlerfehler, kein OnUpdate im Leerlauf", function()
      start()
      W.Open({ fromNpc = true })
      W.SetTab("outfits")
      W.SetTab("items")
      W.SetStatus("x", "red")
      W.Close()
      H.eq(#M.errors, 0)
      H.deepEq(M.StrayGlobals(), {})
      H.deepEq(M.StrayFrameNames(), {})
      -- Fenster zu: kein sichtbarer Frame mit OnUpdate ausser dem Timer-Treiber
      local n = 0
      for _, fr in ipairs(M.UpdateFrames()) do
         local p = fr
         while p do
            if p == W.frame then n = n + 1 end
            p = p:GetParent()
         end
      end
      H.eq(n, 0)
   end)

   H.test("SetStatus vor dem Bau ist harmlos; Open zeigt dann den Leerlauftext", function()
      start()
      W.SetStatus("frueh", "red")
      H.eq(W.frame, nil)
      W.Open({ fromNpc = true })
      H.eq(F().statusText:GetText(), "frueh")
   end)

   H.test("Zufallsfolge (fester Startwert): Invarianten halten, keine Handlerfehler", function()
      start({ world = { screenWidth = 1920, screenHeight = 1080 } })
      setList(HEAD, range(200, 230))
      setList(CHEST, range(200, 230))
      setApplied({ [HEAD] = 205 })
      local seed = 20240611
      local function rnd(n)
         seed = (seed * 1103515245 + 12345) % 2147483648
         return (seed % n) + 1
      end
      local slots = { HEAD, SHOULDER, CHEST, LEGS, BACK, MAINHAND, OFFHAND, RANGED, SHIRT }
      M.world.mouseDown = { LeftButton = true }
      for step = 1, 300 do
         local op = rnd(15)
         if op == 1 then
            W.Open({ fromNpc = rnd(2) == 1, tab = rnd(2) == 1 and "outfits" or "items" })
         elseif op == 2 then
            W.Close()
         elseif op == 3 then
            W.Toggle()
         elseif op == 4 then
            W.SetTab(rnd(2) == 1 and "items" or "outfits")
         elseif op == 5 then
            W.SelectSlot(slots[rnd(#slots)])
         elseif op == 6 then
            State.Select(slots[rnd(#slots)], rnd(3) == 1 and HIDDEN or (199 + rnd(31)))
         elseif op == 7 then
            State.DiscardAll()
         elseif op == 8 then
            State.Select(HEAD, 0)
         elseif op == 9 then
            M.Advance(0.05 * rnd(8))
         elseif op == 10 then
            answerCost(rnd(20000), rnd(4) ~= 1)
         elseif op == 11 and W.IsShown() then
            M.Click(F().btnApply)
         elseif op == 12 then
            DB.Set("scale", ({ 0, 0.6, 1.0, 1.5 })[rnd(4)])
         elseif op == 13 and W.IsShown() then
            M.Drag(F().grip, rnd(300) - 150, rnd(300) - 150)
         elseif op == 14 then
            M.ServerMessage("ApplyTransmogResult:" .. (rnd(2) == 1 and "0" or ("1:0," .. (199 + rnd(31)))))
         elseif op == 15 then
            M.SetScreen(({ 1024, 1365, 1920 })[rnd(3)], ({ 768, 1080 })[rnd(2)])
            M.Advance(1.1)
         end
         if W.frame then
            local f = W.frame
            local w, h = f:GetWidth(), f:GetHeight()
            H.truthy(w >= 740 and h >= 520, "Mindestgroesse (Schritt " .. step .. ")")
            H.falsy(M.world.mouseDown == nil)
            if W.IsShown() then
               -- Fuss und Zustand stimmen nach der Entprellung ueberein
               M.Advance(0.1)
               local ok = State.CanApply()
               H.eq(f.btnApply.uiOff and true or false, not ok, "Anwenden-Zustand (Schritt " .. step .. ")")
               H.eq(f.btnDiscard.uiOff and true or false, State.PendingCount() == 0 or State.Busy(),
                  "Verwerfen-Zustand (Schritt " .. step .. ")")
            end
         end
         H.eq(#M.errors, 0, "Handlerfehler in Schritt " .. step .. ": " .. tostring(M.errors[1]))
      end
      -- Ende: Fenster zu, nichts haengt
      W.Close()
      H.eq(W.frame.grip:GetScript("OnUpdate"), nil)
      H.eq(State.atVendor, false)
   end)

   -- ======================================================================
   H.section("Zusammenspiel mit den echten Komponenten (soweit vorhanden)")
   -- ======================================================================

   H.test("Echte Komponenten: Fenster oeffnet, schaltet Reiter, Slot, Groesse - ohne Fehler", function()
      start({ stubs = false })
      local have = {}
      for _, n in ipairs({ "SlotBar", "Preview", "Grid", "FilterBar", "OutfitsTab", "Options" }) do
         have[n] = T.UI[n] ~= nil
      end
      setList(HEAD, range(200, 230))
      H.truthy(W.Open({ fromNpc = true }))
      M.Advance(0.5)
      H.eq(W.currentSlot, HEAD)
      W.SetTab("outfits")
      M.Advance(0.2)
      W.SetTab("items")
      W.SelectSlot(CHEST)
      M.Advance(0.2)
      DB.Set("width", 1000)
      M.Advance(0.3)
      local f = F()
      local m = W.Metrics(f:GetWidth(), f:GetHeight(), false)
      if have.Grid and T.UI.Grid.frame then
         -- das Raster hat die Groesse bekommen, die das Fenster vorgab
         H.eq(T.UI.Grid.w, m.rightW)
      end
      W.Close()
      H.eq(#M.errors, 0, "keine Handlerfehler: " .. tostring(M.errors[1]))
   end)

   H.test("Echte Komponenten: Slotklick, Zellklick, Anwenden und Antwort laufen durch das Fenster", function()
      start({ stubs = false })
      for _, n in ipairs({ "SlotBar", "Preview", "Grid", "FilterBar", "OutfitsTab" }) do
         if not T.UI[n] then
            return    -- Teilstand: die Komponente fehlt noch, der Durchlauf waere unvollstaendig
         end
      end
      M.CacheAll()
      setList(HEAD, range(200, 230))
      setList(CHEST, range(200, 230))
      W.Open({ fromNpc = true })
      M.Advance(1)
      H.eq(W.currentSlot, HEAD)
      H.eq(T.UI.Grid.slot, HEAD, "das Raster zeigt den gewaehlten Slot")

      -- Slotklick in der echten SlotBar
      local bar = T.UI.SlotBar.Get and T.UI.SlotBar.Get()
      if bar and bar.buttons and bar.buttons[CHEST] then
         M.Click(bar.buttons[CHEST])
         H.eq(W.currentSlot, CHEST)
         H.eq(T.UI.Grid.slot, CHEST)
         M.Click(bar.buttons[HEAD])
         H.eq(W.currentSlot, HEAD)
      end
      M.Advance(0.5)

      -- Zellklick im echten Raster waehlt ein Aussehen
      local pick
      for _, cell in ipairs(T.UI.Grid.cells or {}) do
         if cell:IsShown() and cell.kind == "item" and cell.itemId then
            pick = cell
            break
         end
      end
      H.truthy(pick, "eine sichtbare Zelle mit Gegenstand")
      if pick then
         local id = pick.itemId
         M.Click(pick)
         H.eq(State.Wanted(HEAD), id)
         answerCost(5000, true)
         H.eq(F().btnApply.uiOff, false, "Anwenden frei")
         M.ClearSent()
         M.Click(F().btnApply)
         H.eq(M.SentCommands()[1], "Apply:0:" .. id)
         M.ServerMessage("ApplyTransmogResult:1:0," .. id)
         M.Advance(0.3)
         H.eq(State.Applied(HEAD), id)
         H.eq(F().statusText:GetText(), T.L.MSG_APPLY_OK)
      end
      W.Close()
      H.eq(#M.errors, 0, "keine Handlerfehler: " .. tostring(M.errors[1]))
   end)

   -- ======================================================================
   H.section("Unabhaengige Pruefung: Regressionen und Spielersicht")
   -- ======================================================================

   -- Chatzeile mit Teilstring (plain)?
   local function chatHas(text)
      for _, line in ipairs(M.messages) do
         if string.find(line, text, 1, true) then return true end
      end
      return false
   end

   local function soundFiles()
      local n = 0
      for _, snd in ipairs(M.sounds) do
         if snd.kind == "sound" and snd.name == SOUND_APPLY then n = n + 1 end
      end
      return n
   end

   H.test("Scale aendert sich bei geschlossenem Fenster: Modelle werden beim Zeigen genau einmal neu geladen", function()
      start({ gridRebuild = true })
      W.Open({ fromNpc = true })
      settle(0.3)
      H.eq(#callsOf("Preview.Rebuild"), 0, "erstes Oeffnen: die Komponenten laden ihre Modelle selbst")
      W.Close()
      clearCalls()
      DB.Set("scale", 0.8)                      -- z. B. Optionen ohne offenes Fenster
      settle(0.5)
      H.eq(#callsOf("Preview.Rebuild"), 0, "verborgen: nichts neu geladen")
      H.eq(#callsOf("Grid.Rebuild"), 0)
      W.Open({ fromNpc = true })
      settle(0.3)
      H.eq(#callsOf("Preview.Rebuild"), 1, "beim Zeigen nachgeholt")
      H.eq(#callsOf("Grid.Rebuild"), 1)
      -- ein weiteres Zeigen ohne Aenderung laedt nichts neu
      W.Close()
      clearCalls()
      W.Open({ fromNpc = true })
      settle(0.3)
      H.eq(#callsOf("Preview.Rebuild"), 0)
      H.eq(#callsOf("Grid.Rebuild"), 0)
   end)

   H.test("Anwenden dauert laenger als eine Meldung: die Statuszeile zeigt weiter den Fortschritt", function()
      start()
      openVendor()
      State.Select(HEAD, 200)
      State.Select(CHEST, HIDDEN)
      answerCost(5000, true)
      local f = F()
      M.Click(f.btnApply)
      H.eq(f.statusText:GetText(), "Applying changes (2)...")
      M.Advance(3)
      M.ServerMessage("ApplyTransmogResult:1:0,200")   -- die erste ist da, die zweite laeuft
      M.Advance(4)                                     -- Meldung (6 s) ist abgelaufen, Operation 2 laeuft noch
      H.truthy(State.Busy())
      H.eq(f.statusText:GetText(), "Applying changes (2)...", "weiter Fortschritt statt 'Pending changes'")
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_BUSY)
      M.ServerMessage("ApplyTransmogResult:1:4," .. HIDDEN)
      settle(0.1)
      H.falsy(State.Busy())
      H.eq(f.statusText:GetText(), T.L.MSG_APPLY_OK)
   end)

   H.test("Fenster waehrend des Anwendens geschlossen: Ergebnis im Chat (Erfolg mit Ton, Fehlschlag ohne)", function()
      start()
      openVendor()
      State.Select(HEAD, 200)
      answerCost(5000, true)
      M.Click(F().btnApply)
      W.Close()
      H.eq(State.chatMessages, false)
      M.ServerMessage("ApplyTransmogResult:1:0,200")
      M.Advance(0.1)
      H.truthy(chatHas(T.L.MSG_APPLY_OK), "Erfolg im Chat")
      H.eq(soundFiles(), 1)
      -- Fehlschlag
      openVendor()
      State.Select(HEAD, 201)
      answerCost(5000, true)
      M.Click(F().btnApply)
      W.Close()
      M.ServerMessage("ApplyTransmogResult:0")
      M.Advance(0.1)
      H.truthy(chatHas(string.format(T.L.MSG_APPLY_SLOT_FAILED, "Head")), "Fehlschlag nennt den Slot")
      H.eq(soundFiles(), 1, "kein Ton bei Fehlschlag")
      H.eq(#M.errors, 0)
   end)

   H.test("Mehrere Fehlschlaege: die Zusammenfassung nennt Zahlen, ein einzelner den Slot", function()
      start()
      openVendor()
      State.Select(HEAD, 200)
      State.Select(CHEST, HIDDEN)
      State.Select(LEGS, HIDDEN)
      answerCost(5000, true)
      M.Click(F().btnApply)
      M.ServerMessage("ApplyTransmogResult:0")
      M.ServerMessage("ApplyTransmogResult:0")
      M.ServerMessage("ApplyTransmogResult:0")
      settle(0.1)
      H.eq(F().statusText:GetText(), string.format(T.L.MSG_APPLY_DONE, 0, 3))
      local r = F().statusText:GetTextColor()
      H.near(r, T.COLORS.red[1], 1e-6, "alles fehlgeschlagen: rot")
   end)

   H.test("Zweites Oeffnen bei offenem Fenster wechselt Reiter und Slot ohne Schliessen", function()
      start()
      local hides = 0
      W.Open({ fromNpc = true })
      F():HookScript("OnHide", function() hides = hides + 1 end)
      W.Open({ fromNpc = true, tab = "outfits", slot = CHEST })
      H.eq(hides, 0)
      H.eq(W.GetTab(), "outfits")
      H.eq(W.currentSlot, CHEST)
      W.Open({ fromNpc = true, tab = "items", slot = LEGS })
      H.eq(hides, 0)
      H.eq(W.GetTab(), "items")
      H.eq(W.currentSlot, LEGS)
      H.truthy(stubs.Grid.frame:IsShown())
      H.falsy(stubs.OutfitsTab.frame:IsShown())
   end)

   H.test("Window.Init mehrfach gerufen: jedes Ereignis wirkt genau einmal", function()
      start()
      openVendor()
      W.Init()
      W.Init()
      State.Select(HEAD, 200)
      answerCost(5000, true)
      M.Click(F().btnApply)
      M.ServerMessage("ApplyTransmogResult:1:0,200")
      M.Advance(0.1)
      H.eq(soundFiles(), 1, "ein Ton, nicht drei")
      H.eq(#callsOf("SlotBar.Flash"), 1)
      H.eq(State.chatMessages, false)
   end)

   H.test("Neuaufbau in einer Komponente: Layout und RefreshAll aus dem Layout heraus laufen nicht rekursiv", function()
      start()
      W.Open({ fromNpc = true })
      local depth, maxDepth, n = 0, 0, 0
      stubs.Grid.Layout = function(w, h)
         depth, n = depth + 1, n + 1
         maxDepth = math.max(maxDepth, depth)
         W.Layout()
         W.RefreshAll()
         depth = depth - 1
      end
      W.Layout()
      H.eq(n, 1, "das innere Layout wurde verworfen (Wiedereintrittsschutz)")
      H.eq(maxDepth, 1)
      H.eq(#M.errors, 0)
   end)

   H.test("Layout: gleicher Hinweis-Zustand laesst das Layout in Ruhe (kein Flackern der Raster-Hoehe)", function()
      start()
      openVendor()                          -- per NPC: kein Hinweis
      clearCalls()
      State.SetVendor(true)
      State.SetVendor(true)
      DB.Set("allowAnywhere", true)
      DB.Set("allowAnywhere", false)
      H.eq(#callsOf("Grid.Layout"), 0, "kein Hinweiswechsel, kein Layout")
      State.SetVendor(false)
      H.eq(#callsOf("Grid.Layout"), 1, "Hinweis erscheint: ein Layout")
      State.SetVendor(true)
      H.eq(#callsOf("Grid.Layout"), 2)
   end)

   H.test("Anwenden-Tooltip: nicht geladene Gegenstaende erscheinen als #id, geladene mit Qualitaetsfarbe", function()
      start()
      openVendor({ applied = { [LEGS] = 777 } })
      State.Select(HEAD, 200)
      State.Select(CHEST, HIDDEN)
      State.Select(LEGS, 0)
      answerCost(5000, true)
      local f = F()
      local info = T.Items.Info
      T.Items.Info = function() return nil end
      local function rightHas(text)
         for i = 1, GameTooltip:NumLines() do
            local fs = rawget(_G, "GameTooltipTextRight" .. i)
            if fs and fs:GetText() == text then return true end
         end
         return false
      end
      M.Enter(f.btnApply)
      H.truthy(rightHas("#200"), "unbekannter Gegenstand")
      H.truthy(rightHas(T.L.WIN_TIP_HIDDEN))
      H.truthy(rightHas(T.L.WIN_TIP_REMOVE))
      M.Leave(f.btnApply)
      T.Items.Info = function(id)
         if id == 200 then return { id = 200, name = "Look 200", quality = 4 } end
         return nil
      end
      M.Enter(f.btnApply)
      H.truthy(rightHas("Look 200"))
      H.truthy(tipHas("Head"))
      M.Leave(f.btnApply)
      T.Items.Info = info
   end)

   -- ----------------------------------------------------------------------
   -- Fuss mit Kosten: Breiten, lange Texte, mehrere Sprachen
   -- ----------------------------------------------------------------------

   -- liegt o (links nach rechts) im Fenster und hinter prevRight?
   local function footerRow(f)
      return { f.btnDiscard, f.btnRemoveAll, f.statusText, f.costText, f.btnApply }
   end

   local function assertFooterFits(f, label)
      local prevRight = -1e9
      for i, o in ipairs(footerRow(f)) do
         local l, r = o:GetLeft(), o:GetRight()
         H.truthy(l and r, label .. ": Position aufloesbar " .. i)
         if l and r then
            H.truthy(l >= f:GetLeft() - 1e-6, label .. ": links im Fenster " .. i)
            H.truthy(r <= f:GetRight() + 1e-6, label .. ": rechts im Fenster " .. i)
            H.truthy(l >= prevRight - 1e-6, label .. ": keine Ueberlappung bei " .. i)
            prevRight = r
         end
      end
   end

   local GERMAN_FOOTER = {
      WIN_COST = "Gesamtkosten:",
      WIN_DISCARD = "Alle Aenderungen verwerfen",
      WIN_REMOVE_ALL = "Alle Aussehen entfernen",
      WIN_APPLY = "Aenderungen anwenden",
      WIN_APPLY_RESET = "Urspruenglichen Look anwenden",
   }

   H.test("Kosten: das Feld waechst mit seinem Text, die Beschriftung bleibt; nichts ueberlappt (deutsche Texte)", function()
      local Layout = require("layout")
      start()
      T.Locale.Add("deDE", GERMAN_FOOTER)
      T.Locale.Set("deDE")
      DB.Set("scale", 1.0)
      openVendor()
      local f = F()
      H.eq(f:GetWidth(), 880)
      H.eq(costText(), "")
      assertFooterFits(f, "ohne Kosten")
      local statusEmpty = f.statusText:GetWidth()
      State.Select(HEAD, 200)
      answerCost(123456789, true)
      H.contains(costText(), "Gesamtkosten:")
      H.contains(costText(), T.Util.FormatMoney(123456789))
      assertFooterFits(f, "mit Kosten")
      H.truthy(Layout.TextWidth(f.costText) <= f.costText:GetWidth() + 1e-6, "der Kostentext passt in sein Feld")
      H.truthy(f.statusText:GetWidth() < statusEmpty, "die Statuszeile gibt Platz ab")
      -- ohne Auswahl: das Kostenfeld ist leer, die Statuszeile hat wieder den ganzen Platz
      State.DiscardAll()
      settle(0.1)
      H.eq(costText(), "")
      H.eq(f.statusText:GetWidth(), statusEmpty)
      assertFooterFits(f, "wieder ohne Kosten")
   end)

   H.test("Kosten: reicht der Platz nicht (Minimum, lange Texte), entfaellt die Beschriftung; die Summe bleibt", function()
      local Layout = require("layout")
      start()
      T.Locale.Add("deDE", GERMAN_FOOTER)
      T.Locale.Set("deDE")
      DB.Set("scale", 1.0)
      DB.Set("width", 740)
      DB.Set("height", 520)
      openVendor()
      local f = F()
      State.Select(HEAD, 200)
      answerCost(123456789, true)
      local text = costText()
      H.falsy(contains(text, "Gesamtkosten"), "Beschriftung entfallen")
      H.contains(text, T.Util.FormatMoney(123456789))
      H.truthy(Layout.TextWidth(f.costText) <= f.costText:GetWidth() + 1e-6, "die Summe passt in ihr Feld")
      assertFooterFits(f, "Minimum")
      -- bei viel Platz steht die Beschriftung wieder
      DB.Set("width", 1400)
      DB.Set("height", 800)
      settle(0.3)
      H.contains(costText(), "Gesamtkosten:")
      assertFooterFits(f, "gross")
   end)

   for _, sc in ipairs({ 0.6, 1.0, 1.5 }) do
      H.test("Fuss und Kopf bei Scale " .. sc .. ": kein Text ragt ueber, Mindest- und Standardgroesse", function()
         local Layout = require("layout")
         for _, size in ipairs({ { 740, 520 }, { 880, 600 } }) do
            start({ world = { screenWidth = 1920, screenHeight = 1200 } })
            DB.Set("scale", sc)
            DB.Set("width", size[1])
            DB.Set("height", size[2])
            openVendor({ applied = { [HEAD] = 205 } })
            State.Select(HEAD, 206)
            State.Select(CHEST, HIDDEN)
            answerCost(250000, true)
            W.SetStatus("7 pieces loaded, 1 unavailable", "yellow")
            local f = F()
            local label = "Scale " .. sc .. " " .. size[1] .. "x" .. size[2]
            H.near(f:GetScale(), sc, 1e-9, label)
            assertFooterFits(f, label)
            local entries = Layout.Rects(f)
            local problems = Layout.Check(entries)
            for _, p in ipairs(problems) do
               if p.severity ~= "info" then
                  H.fail(label .. ": " .. tostring(p.kind) .. " " .. tostring(p.path))
               end
            end
         end
      end)
   end

   -- ----------------------------------------------------------------------
   -- Gossip-Ablauf mit dem echten Boot (Spielersicht)
   -- ----------------------------------------------------------------------

   H.test("Am NPC: Fenster auf, ESC schliesst es und das Gossip; erneutes Ansprechen oeffnet wieder", function()
      start()
      M.OpenNpc()
      H.truthy(W.IsShown())
      H.eq(State.atVendor, true)
      H.eq(M.world.gossipOpen, false, "das normale Gossip-Fenster ist ersetzt")
      M.world.gossipOpen = true                   -- der Server-Dialog ist fuer den Client offen
      H.truthy(M.Escape())
      H.falsy(W.IsShown())
      H.eq(State.atVendor, false)
      H.eq(M.world.gossipOpen, false, "ESC schliesst auch das Gossip")
      M.Advance(5)
      M.OpenNpc()
      H.truthy(W.IsShown())
      H.eq(State.atVendor, true)
      H.falsy(GossipFrame:IsShown())
   end)

   H.test("Am NPC: Weggehen (GOSSIP_CLOSED nach der Schonfrist) schliesst, im Vorschau-Modus nicht", function()
      start()
      M.OpenNpc()
      M.Advance(0.4)
      M.Fire("GOSSIP_CLOSED")
      H.truthy(W.IsShown(), "innerhalb der Schonfrist bleibt es offen")
      M.Advance(2)
      M.Fire("GOSSIP_CLOSED")
      H.falsy(W.IsShown())
      W.Toggle()
      M.Advance(3)
      M.Fire("GOSSIP_CLOSED")
      H.truthy(W.IsShown(), "Vorschau-Modus ist an keinen NPC gebunden")
   end)

   H.test("Zwei Aufrufe des NPCs hintereinander: das Fenster flackert nicht (kein Hide/Show, keine Zustandswechsel)", function()
      start()
      local vendor = {}
      M.OpenNpc()
      T.Events.On("VENDOR_CHANGED", function(v) vendor[#vendor + 1] = v end, vendor)
      local hides, shows = 0, 0
      F():HookScript("OnHide", function() hides = hides + 1 end)
      F():HookScript("OnShow", function() shows = shows + 1 end)
      stubs.Options.open = true
      M.Advance(5)
      M.OpenNpc()
      H.truthy(W.IsShown())
      H.eq(hides, 0)
      H.eq(shows, 0)
      H.deepEq(vendor, { true }, "nur der Vendor-Zustand wird neu gesetzt, nie auf false")
      H.eq(stubs.Options.open, true, "ein offenes Optionsfenster bleibt offen")
      H.eq(State.openedByNpc, true)
      H.eq(M.world.gossipOpen, false)
   end)

   H.test("/transmog im Vorschau-Modus und danach der NPC: das Fenster wird zum Transmogrifizierer-Fenster", function()
      start()
      M.Slash("/transmog")
      H.truthy(W.IsShown())
      H.eq(State.atVendor, false)
      H.truthy(F().notice:IsShown())
      M.OpenNpc()
      H.truthy(W.IsShown())
      H.eq(State.atVendor, true)
      H.eq(State.openedByNpc, true)
      H.falsy(F().notice:IsShown())
      M.Slash("/transmog")
      H.falsy(W.IsShown())
   end)

   -- ----------------------------------------------------------------------
   -- Schluessel der Texte: nichts fehlt in der englischen Tabelle
   -- ----------------------------------------------------------------------

   H.test("Ein Durchlauf durch alle Zustaende fragt keinen fehlenden Textschluessel ab", function()
      start()
      local function missingKeys()
         local out = {}
         for k in pairs(T.L.__missing) do out[#out + 1] = k end
         table.sort(out)
         return out
      end
      -- Vorschau-Modus, Server fehlt, NPC, Kosten, Anwenden, Fehlschlag, Entfernen, Verwerfen
      setList(HEAD, range(200, 230))
      setApplied({ [HEAD] = 205, [CHEST] = 777 })
      W.Open({ fromNpc = false })
      settle(0.2)
      State.Select(HEAD, 206)
      settle(0.5)
      for _, b in ipairs({ F().btnApply, F().btnDiscard, F().btnRemoveAll, F().btnOptions, F().btnClose, F().tabItems, F().tabOutfits }) do
         M.Enter(b)
         M.Leave(b)
      end
      M.Enter(F().grip)
      M.Leave(F().grip)
      State.SetVendor(true)
      answerCost(5000, true)
      State.Select(CHEST, 0)
      State.Select(LEGS, HIDDEN)
      answerCost(5000, false)
      answerCost(5000, true)
      M.Enter(F().btnApply)
      M.Leave(F().btnApply)
      M.Click(F().btnApply)
      M.ServerMessage("ApplyTransmogResult:0")
      M.ServerMessage("ApplyTransmogResult:0")
      M.ServerMessage("ApplyTransmogResult:1:6," .. HIDDEN)
      settle(0.2)
      M.Click(F().btnRemoveAll)
      M.Click(confirmButton("Remove all"))
      State.DiscardAll()
      settle(0.2)
      M.Enter(F().btnApply)
      M.Leave(F().btnApply)
      DB.Set("allowAnywhere", true)
      W.SetTab("outfits")
      W.SetTab("items")
      W.Close()
      H.deepEq(missingKeys(), {}, "fehlende Textschluessel")
      H.eq(#M.errors, 0)
   end)

   H.test("Server meldet sich nicht: Hinweis rot, Anwenden und Alles entfernen nennen den Grund", function()
      start({ alive = false })
      M.Advance(9)
      W.Open({ fromNpc = true })
      settle(0.1)
      local f = F()
      H.truthy(f.notice:IsShown())
      H.eq(lockReason(f.btnApply), T.L.APPLY_REASON_SERVER)
      H.eq(lockReason(f.btnRemoveAll), T.L.APPLY_REASON_SERVER)
      M.Enter(f.btnRemoveAll)
      H.truthy(tipHas(T.L.APPLY_REASON_SERVER))
      M.Leave(f.btnRemoveAll)
      -- der Server antwortet doch noch
      M.ServerMessage("TransmogStatus:0")
      settle(0.1)
      H.neq(lockReason(f.btnApply), T.L.APPLY_REASON_SERVER)
   end)

   -- ----------------------------------------------------------------------
   -- Echte Komponenten (Fixtures): Layout-Matrix und Spielerablauf
   -- ----------------------------------------------------------------------

   -- Rechtecke zweier Frames ueberlappen sich (mit Toleranz)?
   local function overlaps(a, b)
      local al, ar, at, ab = a:GetLeft(), a:GetRight(), a:GetTop(), a:GetBottom()
      local bl, br, bt, bb = b:GetLeft(), b:GetRight(), b:GetTop(), b:GetBottom()
      if not (al and ar and at and ab and bl and br and bt and bb) then return false end
      local ox = math.min(ar, br) - math.max(al, bl)
      local oy = math.min(at, bt) - math.max(ab, bb)
      return ox > 0.01 and oy > 0.01
   end

   H.test("Echte Komponenten: Layout-Matrix (Scale 0.6/1/1.5, Minimum/Standard/gross, NPC/Vorschau, beide Reiter)", function()
      local Fixtures = require("fixtures")
      local Layout = require("layout")
      local combos = 0
      for _, loc in ipairs({ "enUS", "deDE" }) do
         local FX = Fixtures.Boot(H, { locale = loc, screen = { w = 1920, h = 1080 } })
         Fixtures.ServerHello(FX)
         Fixtures.ServerAutoReply(FX)
         local Win = FX.UI.Window
         for _, scale in ipairs({ 0.6, 1.0, 1.5 }) do
            for _, size in ipairs({ { 740, 520 }, { 880, 600 }, { 1400, 900 } }) do
               for _, npc in ipairs({ true, false }) do
                  for _, tab in ipairs({ "items", "outfits" }) do
                     local label = string.format("%s scale %s %dx%d %s %s", loc, tostring(scale), size[1], size[2],
                        npc and "NPC" or "Vorschau", tab)
                     FX.DB.Set("scale", scale)
                     FX.DB.Set("width", size[1])
                     FX.DB.Set("height", size[2])
                     Win.Close()
                     Win.Open({ fromNpc = npc, tab = tab, slot = HEAD })
                     Fixtures.Settle(FX, 0.5)
                     FX.State.Select(HEAD, FX.State.List(HEAD).ids[3] or 0)
                     Fixtures.Settle(FX, 0.5)
                     local f = Win.frame
                     local m = Win.Metrics(f:GetWidth(), f:GetHeight(), not npc)
                     combos = combos + 1
                     -- Masse laut Metrik
                     H.eq(f.left:GetWidth(), 318, label)
                     H.eq(f.left:GetHeight(), m.contentH, label)
                     H.eq(f.right:GetWidth(), m.rightW, label)
                     H.eq(f.footer:GetHeight(), 46, label)
                     H.near(f:GetScale(), scale, 1e-9, label)
                     H.truthy(f:GetWidth() * scale <= 1920 + 1e-6 and f:GetHeight() * scale <= 1080 + 1e-6, label)
                     if tab == "items" then
                        H.eq(FX.UI.Grid.frame:GetWidth(), m.rightW, label)
                        H.eq(FX.UI.Grid.frame:GetHeight(), m.gridH, label)
                        H.eq(FX.UI.FilterBar.frame:GetHeight(), 58, label)
                        H.truthy(FX.UI.Grid.perPage >= 1, label)
                     else
                        H.eq(FX.UI.OutfitsTab.frame:GetWidth(), m.rightW, label)
                        H.eq(FX.UI.OutfitsTab.frame:GetHeight(), m.contentH, label)
                     end
                     -- Panels liegen im Fenster und ueberlappen sich nicht
                     for _, part in ipairs({ f.head, f.left, f.right, f.footer }) do
                        H.truthy(part:GetLeft() >= f:GetLeft() - 1e-6 and part:GetRight() <= f:GetRight() + 1e-6, label)
                        H.truthy(part:GetTop() <= f:GetTop() + 1e-6 and part:GetBottom() >= f:GetBottom() - 1e-6, label)
                     end
                     H.falsy(overlaps(f.left, f.right), label)
                     H.falsy(overlaps(f.head, f.left), label)
                     H.falsy(overlaps(f.footer, f.left), label)
                     H.falsy(overlaps(f.footer, f.right), label)
                     if not npc then
                        H.truthy(f.notice:IsShown(), label)
                        H.falsy(overlaps(f.notice, f.left), label)
                        H.falsy(overlaps(f.notice, f.head), label)
                     end
                     assertFooterFits(f, label)
                     -- Layout-Pruefung: keine Fehler; Warnungen nur aus Fremdkomponenten
                     local problems = Layout.Check(Layout.Rects(f), {
                        truncateOk = { "/name$", "/nameText$", "/nameLabel$" },
                     })
                     for _, p in ipairs(problems) do
                        local own = string.find(p.path or "", "^TransmogWindow/footer") or
                           string.find(p.path or "", "^TransmogWindow/head") or
                           string.find(p.path or "", "^TransmogWindow/notice") or
                           string.find(p.path or "", "^TransmogWindow/grip")
                        if p.severity == "error" or (own and p.severity ~= "info") then
                           H.fail(label .. ": " .. tostring(p.severity) .. " " .. tostring(p.kind) .. " " .. tostring(p.path))
                        end
                     end
                  end
               end
            end
         end
      end
      H.eq(combos, 72)
      H.eq(#M.errors, 0)
   end)

   H.test("Echte Komponenten, Spielerablauf: Slot wechseln, Aussehen waehlen, Kosten, Anwenden, Entfernen", function()
      local Fixtures = require("fixtures")
      local FX = Fixtures.Boot(H, { locale = "enUS" })
      Fixtures.ServerHello(FX)
      local srv = Fixtures.ServerAutoReply(FX)
      local Win = FX.UI.Window
      Fixtures.OpenAtNpc(FX)
      Fixtures.Settle(FX, 1)
      local f = Win.frame
      H.truthy(Win.IsShown())
      H.eq(FX.State.atVendor, true)
      H.falsy(f.notice:IsShown())
      -- Kopf-Slot ist gewaehlt, die Liste ist da
      H.eq(Win.currentSlot, HEAD)
      local ids = FX.State.List(HEAD).ids
      H.truthy(#ids >= 3)
      local before = FX.State.Applied(HEAD)
      -- ein Aussehen waehlen: Verwerfen/Anwenden werden frei, Kosten erscheinen
      H.truthy(FX.State.Select(HEAD, ids[1]))
      Fixtures.Settle(FX, 1)
      H.eq(f.btnApply.uiOff, false)
      H.eq(f.btnDiscard.uiOff, false)
      H.contains(f.costText:GetText(), FX.Util.FormatMoney(srv.price))
      H.contains(f.statusText:GetText(), "1")
      -- anwenden
      M.Click(f.btnApply)
      Fixtures.Settle(FX, 1)
      H.eq(FX.State.Applied(HEAD), ids[1])
      H.neq(FX.State.Applied(HEAD), before)
      H.eq(f.statusText:GetText(), FX.L.MSG_APPLY_OK)
      H.eq(FX.State.PendingCount(), 0)
      H.eq(f.costText:GetText(), "")
      -- Anwenden schlaegt am Server fehl: Auswahl bleibt, Meldung nennt den Slot
      srv.failApply = 1
      H.truthy(FX.State.Select(HEAD, ids[2]))
      Fixtures.Settle(FX, 1)
      M.Click(f.btnApply)
      Fixtures.Settle(FX, 1)
      H.eq(FX.State.PendingCount(), 1)
      H.eq(f.statusText:GetText(), string.format(FX.L.MSG_APPLY_SLOT_FAILED, FX.Slots.Label(HEAD)))
      H.eq(f.btnApply.uiOff, false, "kein ewiges Warten nach einem Fehlschlag")
      -- Entfernen vormerken und anwenden: Beschriftung 'Apply reset'
      FX.State.Discard(HEAD)
      Fixtures.Settle(FX, 0.5)
      FX.State.Select(HEAD, 0)
      Fixtures.Settle(FX, 1)
      H.eq(f.btnApply.label:GetText(), FX.L.WIN_APPLY_RESET)
      M.Click(f.btnApply)
      Fixtures.Settle(FX, 1)
      H.eq(FX.State.Applied(HEAD), 0)
      H.eq(f.btnApply.label:GetText(), FX.L.WIN_APPLY)
      -- Alles entfernen mit Rueckfrage
      H.eq(f.btnRemoveAll.uiOff, false, "es gibt noch angewendete Aussehen (Standardausstattung des Servers)")
      M.Click(f.btnRemoveAll)
      M.Click(confirmButton(FX.L.WIN_REMOVE_ALL))
      Fixtures.Settle(FX, 1)
      for _, slot in ipairs({ 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }) do
         H.eq(FX.State.Applied(slot), 0, "Slot " .. slot)
      end
      H.eq(f.btnRemoveAll.uiOff, true)
      H.eq(#M.errors, 0)
      -- ESC schliesst das Fenster; danach bleibt weder ein Timer noch ein OnUpdate
      M.Escape()
      H.falsy(Win.IsShown())
      Fixtures.Settle(FX, 20)
      H.eq(FX.Util.TimerCount(), 0, "keine Timer")
      H.eq(#M.UpdateFrames(), 0, "kein sichtbarer OnUpdate")
   end)

   H.test("Ausruestung wechselt bei offenem Fenster: Auswahl des Slots faellt weg, Fuss und Kosten ziehen nach", function()
      local Fixtures = require("fixtures")
      local FX = Fixtures.Boot(H, { locale = "enUS" })
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX)
      local Win = FX.UI.Window
      Fixtures.OpenAtNpc(FX)
      Fixtures.Settle(FX, 1)
      local f = Win.frame
      local ids = FX.State.List(HEAD).ids
      FX.State.Select(HEAD, ids[1])
      FX.State.Select(CHEST, HIDDEN)
      Fixtures.Settle(FX, 1)
      H.eq(FX.State.PendingCount(), 2)
      H.truthy(f.statusText:GetText():find("2", 1, true))
      Fixtures.Unequip(FX, HEAD)
      Fixtures.Settle(FX, 1)
      H.eq(FX.State.PendingCount(), 1, "die Auswahl des geleerten Slots ist weg")
      H.truthy(f.statusText:GetText():find("1", 1, true))
      H.eq(f.btnApply.uiOff, false)
      H.eq(Win.currentSlot, HEAD, "das Fenster bleibt beim gewaehlten Slot (das Raster zeigt den Leerzustand)")
      FX.State.DiscardAll()
      Fixtures.Settle(FX, 1)
      H.eq(f.btnApply.uiOff, true)
      H.eq(f.costText:GetText(), "")
      H.eq(#M.errors, 0)
   end)

   H.test("Ereignissturm: 500 Aenderungsmeldungen ergeben genau ein Neuzeichnen des Fusses", function()
      start()
      openVendor()
      local f = F()
      local sets = 0
      local orig = f.btnApply.SetLabel
      f.btnApply.SetLabel = function(self, text)
         sets = sets + 1
         return orig(self, text)
      end
      for i = 1, 500 do
         T.Events.Fire("WANTED_CHANGED", HEAD)
         T.Events.Fire("COST_CHANGED")
         T.Events.Fire("STATUS_CHANGED")
      end
      H.eq(sets, 0, "noch nichts gezeichnet")
      settle(0.1)
      H.eq(sets, 1)
      H.eq(#M.errors, 0)
   end)

   H.test("Reiterwechsel mit echten Komponenten: Groesse im verborgenen Reiter wird beim Wechsel nachgezogen", function()
      local Fixtures = require("fixtures")
      local FX = Fixtures.Boot(H, { locale = "enUS", screen = { w = 1920, h = 1080 } })
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX)
      local Win = FX.UI.Window
      FX.DB.Set("scale", 1.0)
      FX.DB.Set("width", 880)
      FX.DB.Set("height", 600)
      Fixtures.OpenAtNpc(FX)
      Fixtures.Settle(FX, 1)
      local perPage = FX.UI.Grid.perPage
      H.truthy(perPage >= 6)
      -- Reiter Outfits; waehrenddessen wird das Fenster groesser
      Win.SetTab("outfits")
      Fixtures.Settle(FX, 0.3)
      H.falsy(FX.UI.Grid.frame:IsShown())
      H.truthy(FX.UI.OutfitsTab.frame:IsShown())
      FX.DB.Set("width", 1300)
      FX.DB.Set("height", 850)
      Fixtures.Settle(FX, 0.5)
      H.eq(FX.UI.OutfitsTab.frame:GetWidth(), 1300 - 342)
      -- zurueck: das Raster hat die neue Groesse und mehr Zellen
      Win.SetTab("items")
      Fixtures.Settle(FX, 0.5)
      H.truthy(FX.UI.Grid.frame:IsShown())
      H.falsy(FX.UI.OutfitsTab.frame:IsShown())
      H.eq(FX.UI.Grid.frame:GetWidth(), 1300 - 342)
      H.eq(FX.UI.Grid.frame:GetHeight(), 850 - 46 - 8 - 38 - 64)
      H.truthy(FX.UI.Grid.perPage > perPage, "mehr Zellen im groesseren Fenster")
      -- und wieder klein, solange der Reiter Items offen ist
      FX.DB.Set("width", 740)
      FX.DB.Set("height", 520)
      Fixtures.Settle(FX, 0.5)
      H.eq(FX.UI.Grid.frame:GetWidth(), 398)
      H.truthy(FX.UI.Grid.perPage >= 1)
      Win.SetTab("outfits")
      Fixtures.Settle(FX, 0.3)
      H.eq(FX.UI.OutfitsTab.frame:GetWidth(), 398)
      H.eq(FX.UI.OutfitsTab.frame:GetHeight(), 520 - 46 - 8 - 38)
      H.eq(#M.errors, 0)
   end)

   H.test("Metrics: absolute Zahlen fuer Minimum und gross, mit und ohne Hinweisleiste (SPEC 11.4)", function()
      start()
      local cases = {
         -- w, h, notice, contentY, contentH, rightW, gridH, footerY
         { 740, 520, false, 38, 428, 398, 364, 473 },
         { 740, 520, true, 60, 406, 398, 342, 473 },
         { 1400, 900, false, 38, 808, 1058, 744, 853 },
         { 1400, 900, true, 60, 786, 1058, 722, 853 },
         { 1920, 1080, false, 38, 988, 1578, 924, 1033 },
      }
      for _, c in ipairs(cases) do
         local m = W.Metrics(c[1], c[2], c[3])
         local label = c[1] .. "x" .. c[2] .. (c[3] and " mit Leiste" or "")
         H.eq(m.contentY, c[4], label .. " contentY")
         H.eq(m.contentH, c[5], label .. " contentH")
         H.eq(m.rightW, c[6], label .. " rightW")
         H.eq(m.gridH, c[7], label .. " gridH")
         H.eq(m.footerY, c[8], label .. " footerY")
         H.eq(m.leftW, 318)
         H.eq(m.previewW, 230)
         H.eq(m.filterH, 58)
         H.eq(m.innerW, c[1] - 2)
      end
      -- ungueltige Eingaben: Standardgroesse, nie ein Fehler
      local m = W.Metrics(nil, "x", nil)
      H.eq(m.width, 880)
      H.eq(m.height, 600)
   end)

   -- ======================================================================
   H.section("Tastaturfokus des Suchfelds")
   -- ======================================================================

   -- 3.3.5a laesst einem EditBox den Fokus bei Klicks auf andere Frames. Jeder Klick
   -- im Fenster ausserhalb des Suchfelds muss ihn nehmen (sonst landen Tasten im Feld).
   H.test("Fokus: Fensterflaeche, Kopf, Skin-Knoepfe, Platzleiste und Modell nehmen dem Suchfeld den Fokus", function()
      start({ stubs = false })
      for _, n in ipairs({ "SlotBar", "Preview", "Grid", "FilterBar" }) do
         if not T.UI[n] then
            return    -- Teilstand: die Komponente fehlt noch
         end
      end
      M.CacheAll()
      setList(HEAD, range(200, 230))
      setList(CHEST, range(200, 230))
      W.Open({ fromNpc = true })
      M.Advance(1)
      local FB = T.UI.FilterBar
      H.truthy(FB.search, "Suchfeld vorhanden")
      local function typed(label, fn)
         M.Type(FB.search, "Look")
         H.truthy(FB.search:HasFocus(), label .. ": getippt, Fokus im Suchfeld")
         fn()
         H.falsy(FB.search:HasFocus(), label .. ": Fokus weg")
         M.Advance(0.4)
      end

      typed("Fensterflaeche", function()
         M.MouseDown(F())
         M.MouseUp(F())
      end)
      typed("Kopf", function()
         M.MouseDown(F().head)
         M.MouseUp(F().head)
      end)
      typed("Skin-Knopf (Reiter)", function()
         M.Click(F().tabItems)
      end)
      typed("Skin-Knopf (Verwerfen, gesperrt)", function()
         M.Click(F().btnDiscard)
      end)
      local bar = T.UI.SlotBar.Get and T.UI.SlotBar.Get()
      if bar and bar.buttons and bar.buttons[CHEST] then
         typed("Platzleiste", function()
            M.Click(bar.buttons[CHEST])
         end)
         H.eq(W.currentSlot, CHEST)
         typed("Platzleiste, Rechtsklick", function()
            M.Click(bar.buttons[HEAD], "RightButton")
         end)
      end
      local model = T.UI.Preview.model
      if model then
         typed("Modell", function()
            M.MouseDown(model, "LeftButton")
            M.MouseUp(model, "LeftButton")
         end)
      end
      -- die getippte Suche wurde dabei uebernommen, nicht verworfen
      H.eq(T.Filter.search, "Look")
      W.Close()
      H.eq(#M.errors, 0, "keine Handlerfehler: " .. tostring(M.errors[1]))
   end)

   H.test("Fokus: ohne Filterleiste bleibt ein Klick im Fenster harmlos", function()
      start({ stubs = true })
      W.Open({ fromNpc = true })
      M.Advance(1)
      M.MouseDown(F())
      M.MouseUp(F())
      M.MouseDown(F().head)
      M.MouseUp(F().head)
      M.Click(F().tabItems)
      H.eq(#M.errors, 0, "keine Handlerfehler: " .. tostring(M.errors[1]))
   end)
end
