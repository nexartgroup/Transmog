-- tests/test_ui_grid.lua
-- ---------------------------------------------------------------------------
-- Tests fuer UI/Grid.lua (T.UI.Grid): das Raster der Aussehen.
--
-- Getestet gegen die ECHTEN Module (Locale, Util, Events, DB, Slots, Items,
-- Net, State, Filter, Skin, Cameras) auf der strengen Attrappe. Der Server
-- wird ueber Net.Handle im echten Protokollformat gespielt; Boot/Window
-- werden nicht geladen, die Init()-Funktionen laufen in der Reihenfolge der
-- SPEC (3) selbst.
--
--   * Layout-Rechnung: Spalten/Zeilen/Zellen je Groesse und Vorschaugroesse,
--     Zellen- und Modellmasse (uniform), Obergrenze der Zellen
--   * Kachelreihenfolge: Original (IMMER die erste Kachel, damit beim ersten
--     Klick nichts rutscht), Verborgen (nur verbergbare Slots), Eintraege
--   * Seiten: Klemmen, Seite halten/zuruecksetzen, Mausrad, Blaetterleiste
--   * Meldungen: kein Slot, leer, nie, Server stumm, Laden (Liste/Items,
--     nie ewig), keine Aussehen, Filter blenden alles aus
--   * Interaktion: Auswahl/Verwerfen, Favorit (Persistenz), Shift-Link,
--     Tooltip, Original-/Verborgen-Kachel (Original ohne Transmogrifikation =
--     "angewendet"; Klick ohne Auswahl aendert nichts)
--   * Ankleiden nur bei geaendertem Schluessel (Zaehlen von SetUnit/TryOn);
--     Modelle bleiben in ihrer Zelle (nie SetParent, Spieltest 2026-10-12) und
--     werden beim Zeigen des Rasters (Reiterwechsel, Fenster auf) neu angekleidet
--   * Tooltip-Hinweis fuer Einhandwaffen im Nebenhand-Slot (Client zeigt sie rechts)
--   * Ereignisse: gebuendelt, ein Compute je Aktualisierung, unsichtbar =
--     Dirty-Flag, kein haengendes OnUpdate
--   * Ankleidebudget (16 Modelle je Zeichenvorgang, Rest in Schritten), gekuerzte
--     Namen ("..."), Zaehler mit ausgeblendeten Duplikaten, Symbol der
--     Verborgen-Kachel, Fokus des Suchfelds nach Klicks im Raster
--
-- Aufruf (im Hauptverzeichnis):  luajit tests/run.lua ui_grid
-- ---------------------------------------------------------------------------

return function(H)
   local mock = H.mock
   local HIDDEN = 999999
   local CHEST = 4          -- Server-Slot Brust (Client-Slot 5)
   local HEAD = 0
   local MAINHAND = 15

   -- -------------------------------------------------------------------------
   -- Hilfen
   -- -------------------------------------------------------------------------

   local function put(defs, id, name, quality, ilvl, class, sub, loc, icon)
      defs[id] = {
         name = name, quality = quality, ilvl = ilvl, class = class, subclass = sub,
         equipLoc = loc, icon = icon and ("Interface\\Icons\\" .. icon) or nil,
      }
   end

   -- Brust: angelegt 1004 (Platte, episch); 40 Kandidaten 2001..2040 mit
   -- eigenen Icons (keine Duplikate), Qualitaet = i % 5
   local CHEST_COUNT = 40
   local CHEST_LIST = {}
   for i = 1, CHEST_COUNT do CHEST_LIST[i] = 2000 + i end

   local function baseItems()
      local d = {}
      put(d, 1004, "Chest of Plate", 4, 200, "Armor", "Plate", "INVTYPE_CHEST", "ChestP")
      put(d, 1001, "Helm of Plate", 4, 200, "Armor", "Plate", "INVTYPE_HEAD", "HeadP")
      put(d, 1015, "Sword of Doom", 4, 200, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "SwordD")
      for i = 1, CHEST_COUNT do
         put(d, 2000 + i, string.format("Look %02d", i), i % 5, 100 + i, "Armor", "Plate",
            "INVTYPE_CHEST", "Look" .. i)
      end
      -- Kopf und Waffe (je zwei Kandidaten)
      put(d, 3001, "Plate Helm A", 3, 150, "Armor", "Plate", "INVTYPE_HEAD", "HeadA")
      put(d, 3002, "Plate Helm B", 2, 140, "Armor", "Plate", "INVTYPE_HEAD", "HeadB")
      put(d, 4001, "Sword Alpha", 3, 150, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "SwordA")
      put(d, 4002, "Sword Beta", 2, 140, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "SwordB")
      return d
   end

   -- Spielt einen Listenstrom des Servers (start, Chunks zu 20, end) ein
   local function feed(T, slot, list, opts)
      opts = opts or {}
      local bucket, n = opts.bucket or 0, #list
      T.Net.Handle(string.format("AvailableTransmogs:%d:%d:%d:start", slot, bucket, n))
      local i = 1
      while i <= n do
         local part = {}
         for j = i, math.min(i + 19, n) do part[#part + 1] = tostring(list[j]) end
         T.Net.Handle(string.format("AvailableTransmogs:%d:%d:%d:%s", slot, bucket, n,
            table.concat(part, ":")))
         i = i + 20
      end
      if not opts.noEnd then
         T.Net.Handle(string.format("AvailableTransmogs:%d:%d:%d:end", slot, bucket, n))
      end
   end

   -- Laedt das Addon bis FilterBar.lua und initialisiert die Module wie Boot.
   --   spec.items     Gegenstandsdefinitionen (Standard baseItems())
   --   spec.equip     [Client-Slot] = itemId (Standard Brust 1004)
   --   spec.cache     false: Gegenstaende NICHT in den Client-Cache legen
   --   spec.feed      false: keine Brustliste einspielen
   --   spec.previewSize  Vorschaugroesse vor dem Aufbau
   --   spec.noGrid    true: Grid nicht erzeugen
   --   spec.w, spec.h Containergroesse (Standard 500 x 400)
   local function boot(spec)
      spec = spec or {}
      local T = H.boot({
         upTo = "UI\\FilterBar.lua", login = false,
         items = spec.items or baseItems(),
         world = { equipment = spec.equip or { [5] = 1004 } },
         globals = spec.globals,
      })
      T.DB.Init()
      if spec.previewSize then T.DB.global.previewSize = spec.previewSize end
      T.Locale.Set("enUS")
      T.Slots.Init()
      T.Items.Init()
      T.Net.Init()
      T.State.Init()
      T.Outfits.Init()
      T.enteredWorldAt = GetTime() - 60   -- kein Login-Sweep mehr
      if spec.cache ~= false then mock.CacheAll() end
      T.State.RefreshEquipment()
      if spec.feed ~= false then feed(T, CHEST, CHEST_LIST, { bucket = 405 }) end
      if not spec.noGrid then
         local parent = CreateFrame("Frame", nil, UIParent)
         parent:SetWidth(900)
         parent:SetHeight(700)
         parent:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
         local grid = T.UI.Grid.Create(parent)
         grid:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
         T.UI.Grid.Layout(spec.w or 500, spec.h or 400)
         T.parent = parent
      end
      return T
   end

   -- Zaehler fuer Bus-Ereignisse
   local function counter(T, names)
      local c = {}
      for _, name in ipairs(names) do
         T.Events.On(name, function() c[name] = (c[name] or 0) + 1 end, c)
      end
      return c
   end

   -- Zellen, die sichtbar sind (in Reihenfolge)
   local function shownCells(G)
      local out = {}
      for i = 1, #G.cells do
         if G.cells[i]:IsShown() then out[#out + 1] = G.cells[i] end
      end
      return out
   end

   -- Kachelkennung einer Zelle: "orig", "hide" oder die Item-ID
   local function tag(cell)
      if cell.kind == "original" then return "orig" end
      if cell.kind == "hidden" then return "hide" end
      return cell.itemId
   end

   local function tags(G)
      local out = {}
      for i, c in ipairs(shownCells(G)) do out[i] = tag(c) end
      return out
   end

   -- Blaettert, bis die Kachel mit der Item-ID sichtbar ist; liefert die Zelle
   -- (Zellen werden wiederverwendet: sofort auswerten, nicht aufbewahren).
   local function findCell(G, id)
      for page = 1, G.pages do
         G.SetPage(page)
         for _, c in ipairs(shownCells(G)) do
            if c.itemId == id then return c end
         end
      end
      return nil
   end

   local function ids(entries, from, to)
      local out = {}
      for i = from, to do out[#out + 1] = entries[i].id end
      return out
   end

   -- Summe der Modellaufrufe "name" ueber alle Zellen
   local function modelCalls(G, name)
      local n = 0
      for _, c in ipairs(G.cells) do
         if c.model then n = n + mock.Model(c.model).count(name) end
      end
      return n
   end

   local function clearModelCalls(G)
      for _, c in ipairs(G.cells) do
         if c.model then mock.Model(c.model).clear() end
      end
   end

   -- Alle Aufrufe aller Zellmodelle (Name, Zelle): jeder Aufruf der Attrappe steht im Protokoll
   local function totalModelCalls(G)
      local n = 0
      for _, c in ipairs(G.cells) do
         if c.model then n = n + #mock.Model(c.model).calls end
      end
      return n
   end

   -- Zellen -> Modell (Identitaet): zum Vergleich "kein Modell hat die Zelle gewechselt"
   local function modelMap(G)
      local out = {}
      for i, c in ipairs(G.cells) do out[i] = c.model or false end
      return out
   end

   -- Protokolliert SetParent-Aufrufe auf DressUpModels (die Attrappe schreibt sie nicht ins
   -- Modellprotokoll): umhuellt die Methode der Attrappe; w.stop() stellt sie wieder her.
   -- Standard: wie im echten Client verliert ein umgehaengtes Modell Auskleidung, Anprobe und
   -- Kamera (Spieltest 2026-10-12); plain = true laesst den Zustand der Attrappe unberuehrt.
   local origSetParent = nil
   local function watchSetParent(plain)
      local methods = mock.methods.DressUpModel
      origSetParent = origSetParent or methods.SetParent
      local w = { count = 0 }
      methods.SetParent = function(self, parent)
         w.count = w.count + 1
         local changed = rawget(self, "__parent") ~= parent
         local r = origSetParent(self, parent)
         if changed and not plain then mock.U.modelReset(self) end
         return r
      end
      function w.stop() methods.SetParent = origSetParent end
      return w
   end
   -- Bricht ein Test vor w.stop() ab, bleibt die Huelle nicht fuer die naechsten Tests stehen
   H.beforeEach(function()
      if origSetParent then mock.methods.DressUpModel.SetParent = origSetParent end
   end)

   -- Hat das Modell das Ganze genau EINMAL durchlaufen? SetUnit -> (Kamera) -> Undress -> TryOn(itemId);
   -- Hand-Slots: kein Undress (es wuerde beide Haende leeren), TryOn bleibt.
   local function assertDressedOnce(m, label, itemId, hand)
      H.eq(m.count("SetUnit"), 1, label .. ": SetUnit genau einmal")
      H.eq(m.count("TryOn"), 1, label .. ": TryOn genau einmal")
      H.eq(m.count("Undress"), hand and 0 or 1, label .. (hand and ": Hand-Slot ohne Undress" or ": Undress genau einmal"))
      H.deepEq(m.tried, { itemId }, label .. ": angezogen wurde das Aussehen der Kachel")
      local iUnit, iUndress, iTry
      for i, n in ipairs(m.names()) do
         if n == "SetUnit" and not iUnit then iUnit = i end
         if n == "Undress" and not iUndress then iUndress = i end
         if n == "TryOn" and not iTry then iTry = i end
      end
      H.truthy(iUnit and iTry and iUnit < iTry, label .. ": SetUnit vor TryOn")
      if not hand then
         H.truthy(iUndress and iUnit < iUndress and iUndress < iTry, label .. ": Undress zwischen SetUnit und TryOn")
      end
   end

   -- Anzahl der Aufrufe von T.State.RequestCost (Kostenanfragen) ab jetzt
   local function watchCost(T)
      local w = { count = 0 }
      local orig = T.State.RequestCost
      T.State.RequestCost = function(...)
         w.count = w.count + 1
         return orig(...)
      end
      return w
   end

   -- Zeilen des GameTooltips (links)
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

   -- Sichtbare Texte der Rasterflaeche (ohne Zellen)
   local function msg(G)
      return G.msgTitle:IsShown() and G.msgTitle:GetText() or nil
   end

   local function advance(dt)
      mock.Advance(dt or 0.2)
   end

   -- Wie Grid.Layout rechnet: Gegenprobe im Test (unabhaengig vom Addon-Code)
   local function expectedGrid(w, h, f)
      local cw, ch = 92 * f, 126 * f
      local cols = math.floor((w + 6) / (cw + 6) + 1e-6)
      local rows = math.floor(((h - 30) + 6) / (ch + 6) + 1e-6)
      if cols < 1 then cols = 1 end
      if rows < 1 then rows = 1 end
      return cols, rows
   end

   -- =========================================================================
   H.section("Aufbau und Layout")
   -- =========================================================================

   H.test("Create: Singleton, Frame-Methoden, Container 500x400, Blaetterleiste 30 px", function()
      local T = boot()
      local G = T.UI.Grid
      local again = G.Create(T.parent)
      H.truthy(rawequal(again, G.frame), "zweites Create liefert denselben Container")
      H.eq(G.frame:GetWidth(), 500)
      H.eq(G.frame:GetHeight(), 400)
      H.eq(G.raster:GetHeight(), 370, "Raster = h - 30")
      H.eq(G.pager:GetHeight(), 30)
      H.eq(G.pager:GetWidth(), 500)
      -- Doppelpunkt-Aufrufe am Frame
      H.eq(type(G.frame.Layout), "function")
      H.eq(type(G.frame.SetSlot), "function")
      H.eq(type(G.frame.Refresh), "function")
      H.eq(type(G.frame.SetPage), "function")
      H.eq(type(G.frame.Page), "function")
      G.frame:SetSlot(CHEST)
      H.eq(G.slot, CHEST)
      G.frame:Layout(600, 420)
      H.eq(G.frame:GetWidth(), 600)
      H.eq(G.frame:GetHeight(), 420)
      -- Singleton: Ereignisse nur einmal angemeldet
      local c = counter(T, {})
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout: Spalten, Zeilen und Zellen je Seite (Groesse x Vorschaugroesse)", function()
      local T = boot()
      local G = T.UI.Grid
      -- feste Sollwerte von Hand: floor((w+6)/(cell+6)), floor((h-30+6)/(cell+6))
      local cases = {
         -- f      w    h    cols rows
         { 1.0,  500, 400,   5,   2 },
         { 1.0,  398, 300,   4,   2 },
         { 1.0,  484, 400,   5,   2 },   -- (484+6)/98 = 5 exakt
         { 1.0,  483, 400,   4,   2 },
         { 0.8,  500, 400,   6,   3 },   -- 506/79.6 = 6.36 ; 376/106.8 = 3.52
         { 0.8,  392, 400,   5,   3 },   -- 398/79.6 = 5 exakt (Fliesskomma!)
         { 1.25, 500, 400,   4,   2 },   -- 506/121 ; 376/163.5
         { 1.5,  500, 400,   3,   1 },   -- 506/144 ; 376/195
         { 1.5,  700, 600,   4,   2 },   -- 706/144 = 4.9 ; 576/195 = 2.95
         { 1.0,   50, 100,   1,   1 },   -- nie unter 1
         { 1.0,  880, 560,   8,   3 },   -- 886/98 = 9.04 -> 9 ? (siehe unten)
      }
      -- die letzte Zeile aus der Formel statt von Hand (886/98 = 9.04)
      cases[#cases][4], cases[#cases][5] = expectedGrid(880, 560, 1.0)
      H.eq(cases[#cases][4], 9)
      for _, c in ipairs(cases) do
         local f, w, h, cols, rows = c[1], c[2], c[3], c[4], c[5]
         T.DB.Set("previewSize", f)
         G.Layout(w, h)
         local label = string.format("f=%s %dx%d", tostring(f), w, h)
         H.eq(G.cols, cols, label .. " cols")
         H.eq(G.rows, rows, label .. " rows")
         H.eq(G.perPage, cols * rows, label .. " perPage")
         local ec, er = expectedGrid(w, h, f)
         H.eq(G.cols, ec, label .. " (Gegenprobe)")
         H.eq(G.rows, er, label .. " (Gegenprobe)")
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout: Zell- und Modellmasse skalieren uniform, Modell 80f x 107f, 4 px oben", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      for _, f in ipairs({ 0.8, 1.0, 1.25, 1.5 }) do
         T.DB.Set("previewSize", f)
         G.Layout(700, 560)
         G.SetSlot(CHEST)
         G.Refresh()
         H.eq(G.scale, f)
         H.near(G.cellW, 92 * f, 1e-9, "cellW " .. f)
         H.near(G.cellH, 126 * f, 1e-9, "cellH " .. f)
         local shown = shownCells(G)
         H.truthy(#shown > 0)
         local withModel = nil
         for _, c in ipairs(shown) do
            H.near(c:GetWidth(), 92 * f, 1e-9)
            H.near(c:GetHeight(), 126 * f, 1e-9)
            if c.model and c.model:IsShown() then withModel = c end
         end
         H.truthy(withModel, "mindestens ein Modell")
         H.near(withModel.model:GetWidth(), 80 * f, 1e-9, "Modellbreite " .. f)
         H.near(withModel.model:GetHeight(), 107 * f, 1e-9, "Modellhoehe " .. f)
         -- Seitenverhaeltnis fix (80:107)
         H.near(withModel.model:GetWidth() / withModel.model:GetHeight(), 80 / 107, 1e-9)
         local point, rel, relPoint, x, y = withModel.model:GetPoint(1)
         H.eq(point, "TOP")
         H.eq(rel, withModel)
         H.eq(y, -4, "4 px Abstand oben")
         H.eq(x, 0)
         -- Template: DressUpModel mit TransmogCellModelTemplate
         H.eq(withModel.model:GetObjectType(), "DressUpModel")
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout: Zellen stehen im Raster (Abstand 6, waagerecht zentriert)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      G.Layout(500, 400)   -- 5 Spalten * 92 + 4 * 6 = 484 -> Rand (500-484)/2 = 8
      local x0 = math.floor((500 - (5 * 98 - 6)) / 2)
      H.eq(x0, 8)
      for i = 1, 10 do
         local c = G.cells[i]
         local point, rel, relPoint, x, y = c:GetPoint(1)
         H.eq(point, "TOPLEFT")
         H.eq(rel, G.raster)
         local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
         H.eq(x, x0 + col * 98, "x " .. i)
         H.eq(y, -(row * 132), "y " .. i)
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout: Zellen je Seite sind nach oben begrenzt (riesiges Fenster, kleine Vorschau)", function()
      local T = boot({ previewSize = 0.8 })
      local G = T.UI.Grid
      G.Layout(2800, 1400)
      H.truthy(G.perPage <= G.MAX_PER_PAGE, "perPage " .. G.perPage)
      H.truthy(G.perPage >= 100)
      H.eq(G.perPage, G.cols * G.rows)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout: unsinnige Groessen werfen nicht und behalten die letzte gueltige", function()
      local T = boot()
      local G = T.UI.Grid
      G.Layout(500, 400)
      G.Layout(nil, nil)
      G.Layout(0 / 0, "x")
      G.Layout(-5, -5)
      H.eq(G.w, 500)
      H.eq(G.h, 400)
      H.eq(G.perPage, 10)
      G.Layout(1, 1)   -- winzig, aber nie 0 Zellen
      H.eq(G.cols, 1)
      H.eq(G.rows, 1)
      H.eq(G.perPage, 1)
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Kacheln und Reihenfolge")
   -- =========================================================================

   H.test("Seite 1: Original und Verborgen vor den Eintraegen; Eintraege wie Filter.Compute", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      H.eq(G.mode, "GRID")
      local entries, stats = T.Filter.Compute(CHEST)
      H.eq(#entries, CHEST_COUNT)
      -- Baseline 0, keine Auswahl: Original steht trotzdem vorn (immer); Brust ist verbergbar
      local want = { "orig", "hide" }
      for i = 1, 8 do want[#want + 1] = entries[i].id end
      H.deepEq(tags(G), want)
      H.deepEq(G.stats, stats)
      H.eq(G.stats.total, CHEST_COUNT)
      H.eq(G.stats.shown, CHEST_COUNT, "synthetische Kacheln zaehlen nicht")
      H.eq(G.perPage, 10)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Original-Kachel steht IMMER vorn (auch ohne Auswahl und ohne Baseline), danach Verborgen", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local first = tags(G)
      H.eq(first[1], "orig", "Baseline 0, nichts gewaehlt")
      H.eq(first[2], "hide")
      -- Auswahl: dieselbe Kachelfolge, nichts rutscht
      T.State.Select(CHEST, 2005)
      advance()
      H.deepEq(tags(G), first, "Auswahl")
      -- Auswahl verwerfen: dieselbe Kachelfolge
      T.State.Discard(CHEST)
      advance()
      H.deepEq(tags(G), first, "verworfen")
      -- angewendet (Baseline ~= 0): ebenso
      T.Net.Handle("TransmogStatus:1:4,2005")
      advance()
      H.deepEq(tags(G), first, "angewendet")
      -- Verborgen angewendet: ebenso
      T.Net.Handle("TransmogStatus:1:4," .. HIDDEN)
      advance()
      H.deepEq(tags(G), first, "Verborgen angewendet")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Nicht verbergbarer Slot (Haupthand): keine Verborgen-Kachel, Original bleibt", function()
      local T = boot({ equip = { [16] = 1015, [5] = 1004 } })
      local G = T.UI.Grid
      feed(T, MAINHAND, { 4001, 4002 }, { bucket = 207 })
      G.SetSlot(MAINHAND)
      H.eq(G.mode, "GRID")
      local t = tags(G)
      H.deepEq(t, { "orig", 4001, 4002 }, "Original ja, Verborgen nein")
      T.State.Select(MAINHAND, 4002)
      advance()
      H.deepEq(tags(G), { "orig", 4001, 4002 }, "eine Auswahl aendert die Kacheln nicht")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Original-Kachel zeigt das Modell des ANGELEGTEN Gegenstands, Eintraege ihr Aussehen", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.State.Select(CHEST, 2005)
      advance()
      local cells = shownCells(G)
      local orig, hide, item = cells[1], cells[2], cells[3]
      H.eq(orig.kind, "original")
      local mo = mock.Model(orig.model)
      H.deepEq(mo.tried, { 1004 }, "TryOn(angelegt)")
      H.eq(mo.unit, "player")
      H.truthy(mo.undressed)
      -- Verborgen: kein Modell
      H.eq(hide.kind, "hidden")
      H.falsy(hide.model and hide.model:IsShown(), "kein Modell fuer Verborgen")
      -- Eintrag: TryOn(Item-ID)
      local mi = mock.Model(item.model)
      H.deepEq(mi.tried, { item.itemId })
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zelleninhalt: Name in Qualitaetsfarbe, Streifen, Stern, NEU-Marke, Haken", function()
      local T = boot()
      local G = T.UI.Grid
      -- 2004 ist favorit, 2009 neu, 2014 angewendet
      T.DB.char.favorites[2004] = true
      T.State.new[2009] = true
      T.Net.Handle("TransmogStatus:1:4,2014")
      G.SetSlot(CHEST)

      local fav = findCell(G, 2004)
      H.truthy(fav)
      -- Name und Farbe
      local r, g, b = T.Util.QualityColor(fav.tile.info.quality)
      H.eq(fav.ov.name:GetText(), fav.tile.info.name)
      local cr, cg, cb = fav.ov.name:GetTextColor()
      H.near(cr, r, 1e-6)
      H.near(cg, g, 1e-6)
      H.near(cb, b, 1e-6)
      H.truthy(fav.ov.stripe:IsShown())
      H.eq(fav.ov.stripe:GetHeight(), 2)
      H.truthy(fav.favorite)
      H.truthy(fav.ov.star:IsShown())
      H.falsy(fav.ov.newBg:IsShown())
      H.falsy(fav.ov.check:IsShown())

      local new = findCell(G, 2009)
      H.truthy(new)
      H.truthy(new.isNew)
      H.truthy(new.ov.newBg:IsShown())
      H.truthy(new.ov.newText:IsShown())
      H.eq(new.ov.newText:GetText(), "NEW")
      H.falsy(new.ov.star:IsShown())

      local app = findCell(G, 2014)
      H.truthy(app)
      H.truthy(app.applied)
      H.truthy(app.ov.check:IsShown())
      H.eq(app.ov.edgeT:GetHeight(), 2, "angewendet: 2 px Rand")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Rand/Marken liegen in einem Kind-Frame ueber dem Modell", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local c = shownCells(G)[3]   -- Original, Verborgen, dann der erste Eintrag
      H.eq(c.kind, "item")
      H.truthy(c.model)
      H.truthy(c.ov:GetFrameLevel() > c.model:GetFrameLevel(), "overlay ueber dem Modell")
      H.falsy(c.ov.__mouse, "overlay nimmt keine Maus")
      H.falsy(c.model.__mouse, "Modell nimmt keine Maus (Klicks gehen an die Zelle)")
      H.eq(c.ov:GetParent(), c)
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Seiten und Blaetterleiste")
   -- =========================================================================

   H.test("Seiten: Anzahl inkl. synthetischer Kacheln, SetPage klemmt, Page blaettert", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      -- 40 Eintraege + Original + Verborgen = 42 Kacheln, 10 je Seite
      H.eq(G.perPage, 10)
      H.eq(G.pages, 5)
      H.eq(G.page, 1)
      G.SetPage(3)
      H.eq(G.page, 3)
      G.SetPage(99)
      H.eq(G.page, 5)
      G.SetPage(-4)
      H.eq(G.page, 1)
      G.SetPage(2.7)
      H.eq(G.page, 2)
      G.Page(1)
      H.eq(G.page, 3)
      G.Page(-1)
      G.Page(-1)
      G.Page(-1)
      H.eq(G.page, 1, "nicht unter 1")
      G.SetPage(5)
      G.Page(1)
      H.eq(G.page, 5, "nicht ueber die letzte")
      -- letzte Seite: 42 - 40 = 2 Eintraege
      H.eq(#shownCells(G), 2)
      -- Seite 2 beginnt mit Eintrag 9 (Original und Verborgen stehen nur auf Seite 1:
      -- Seite 1 = 2 synthetische + Eintraege 1..8)
      local entries = T.Filter.Compute(CHEST)
      G.SetPage(2)
      H.deepEq(tags(G), ids(entries, 9, 18))
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Seite bleibt bei Auswahl/Status, springt auf 1 bei Slot- und Filterwechsel", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      G.SetPage(3)
      T.State.Select(CHEST, 2010)
      advance()
      H.eq(G.page, 3, "Auswahl aendert die Seite nicht")
      T.Net.Handle("TransmogStatus:1:4,2010")
      advance()
      H.eq(G.page, 3, "Status aendert die Seite nicht")
      T.DB.char.favorites[2011] = true
      T.Events.Fire("FAVORITES_CHANGED")
      advance()
      H.eq(G.page, 3, "Favorit aendert die Seite nicht")
      -- Filter
      T.Filter.SetSearch("Look 1")
      advance()
      H.eq(G.page, 1, "Filter setzt auf Seite 1")
      T.Filter.SetSearch("")
      advance()
      G.SetPage(4)
      G.SetSlot(HEAD)
      H.eq(G.page, 1, "Slotwechsel setzt auf Seite 1")
      G.SetSlot(CHEST)
      H.eq(G.page, 1)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Seite wird geklemmt, wenn die Liste schrumpft", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      G.SetPage(5)
      H.eq(G.page, 5)
      -- Liste schrumpft auf 15 Eintraege (neuer Strom)
      local small = {}
      for i = 1, 15 do small[i] = 2000 + i end
      feed(T, CHEST, small, { bucket = 405 })
      advance()
      H.eq(G.pages, 2, "15 + Original + Verborgen = 17 Kacheln")
      H.eq(G.page, 2, "auf die letzte Seite geklemmt")
      H.eq(#shownCells(G), 7)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Blaetterleiste: Knoepfe, Seitentext, Zaehler", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local b = G.pageButtons
      H.eq(b.first:GetLabel(), "<<")
      H.eq(b.prev:GetLabel(), "<")
      H.eq(b.next:GetLabel(), ">")
      H.eq(b.last:GetLabel(), ">>")
      H.truthy(b.first.uiOff)
      H.truthy(b.prev.uiOff)
      H.falsy(b.next.uiOff)
      H.falsy(b.last.uiOff)
      H.eq(G.pageText:GetText(), "Page 1 / 5")
      H.eq(G.countText:GetText(), "40 of 40 appearances")

      mock.Click(b.next)
      H.eq(G.page, 2)
      H.eq(G.pageText:GetText(), "Page 2 / 5")
      H.falsy(b.first.uiOff)
      H.falsy(b.prev.uiOff)
      mock.Click(b.last)
      H.eq(G.page, 5)
      H.truthy(b.next.uiOff)
      H.truthy(b.last.uiOff)
      mock.Click(b.next)   -- gesperrt: nichts
      H.eq(G.page, 5)
      mock.Click(b.prev)
      H.eq(G.page, 4)
      mock.Click(b.first)
      H.eq(G.page, 1)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zaehler: 'n of m' und bei Filtern '(filtered)'; schmal faellt auf 'n / m'", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      H.eq(G.countText:GetText(), "40 of 40 appearances")
      T.Filter.SetQuality(0, false)   -- blendet die Qualitaet 0 aus (8 Eintraege)
      advance()
      H.eq(G.stats.shown, 32)
      H.eq(G.stats.hiddenByFilter, 8)
      H.eq(G.countText:GetText(), "32 of 40 appearances (filtered)")
      -- sehr schmaler Container: die kurze Form
      G.Layout(398, 400)
      H.truthy(G.countText:GetText() == "32 / 40" or G.countText:GetText():find("32 of 40", 1, true),
         "Text: " .. tostring(G.countText:GetText()))
      G.Layout(220, 400)
      H.eq(G.countText:GetText(), "32 / 40")
      -- Duplikate zaehlen nicht als "gefiltert"
      T.Filter.Reset()
      advance()
      H.eq(G.countText:GetText():find("filtered", 1, true), nil)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Blaetterleiste: schmal wird der Seitentext kurz, alle Texte passen in ihre Felder", function()
      local T = boot()
      T.Locale.Add("deDE", {
         GRID_PAGE = "Seite %d / %d", GRID_COUNT = "%s von %s Aussehen",
         GRID_COUNT_FILTERED = "%s von %s Aussehen (gefiltert)",
      })
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.Filter.SetQuality(0, false)
      advance()
      local U = mock.U
      for _, loc in ipairs({ "enUS", "deDE" }) do
         T.Locale.Set(loc)
         advance()
         for _, w in ipairs({ 880, 600, 500, 398, 300, 240 }) do
            G.Layout(w, 400)
            local label = loc .. " w=" .. w
            local page = G.pageText:GetText()
            local count = G.countText:GetText()
            H.truthy(page and page ~= "", label .. " Seitentext")
            H.truthy(U.textWidth(G.pageText) <= G.pageText:GetWidth() + 1e-6,
               label .. " Seitentext passt: " .. page)
            H.truthy(U.textWidth(G.countText) <= G.countText:GetWidth() + 1e-6,
               label .. " Zaehler passt: " .. count)
            -- nichts ueberlappt: Seitentext endet vor dem Zaehler
            local _, _, _, px = G.pageText:GetPoint(1)
            H.truthy(px + G.pageText:GetWidth() <= w - G.countText:GetWidth() + 1e-6, label .. " ueberlappt nicht")
         end
      end
      G.Layout(880, 400)
      H.matches(G.pageText:GetText(), "^Seite 1 / %d+$")
      G.Layout(300, 400)
      H.matches(G.pageText:GetText(), "^1 / %d+$", "schmal: kurzer Seitentext")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Mausrad ueber Raster, Zelle und Container blaettert", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      mock.Wheel(G.frame, -1)
      H.eq(G.page, 2)
      mock.Wheel(G.cells[1], -1)
      H.eq(G.page, 3)
      mock.Wheel(G.raster, 1)
      H.eq(G.page, 2)
      mock.Wheel(G.pager, 1)
      H.eq(G.page, 1)
      mock.Wheel(G.frame, 1)
      H.eq(G.page, 1, "nicht unter Seite 1")
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Meldungen in der Rasterflaeche")
   -- =========================================================================

   H.test("Kein Slot gewaehlt: Meldung, keine Zellen, Leiste gesperrt", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(nil)
      H.eq(G.mode, "NO_SLOT")
      H.eq(msg(G), "Select an equipment slot")
      H.eq(#shownCells(G), 0)
      H.truthy(G.pageButtons.next.uiOff)
      H.eq(G.countText:GetText(), "")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Slot leer: 'Nothing equipped in this slot'", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(HEAD)   -- Kopf: nichts angelegt
      H.eq(G.mode, "EMPTY")
      H.eq(msg(G), "Nothing equipped in this slot")
      H.eq(#shownCells(G), 0)
      H.falsy(G.resetButton:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Slot nie transmogbar: 'This item cannot be transmogrified'", function()
      local d = baseItems()
      put(d, 1500, "Relic of Testing", 3, 100, "Armor", "Idols", "INVTYPE_RELIC", "Relic")
      local T = boot({ items = d, equip = { [5] = 1004, [18] = 1500 } })
      local G = T.UI.Grid
      G.SetSlot(17)   -- Fernkampf mit Relikt
      H.eq(T.State.SlotState(17), "NEVER")
      H.eq(G.mode, "NEVER")
      H.eq(msg(G), "This item cannot be transmogrified")
      H.eq(#shownCells(G), 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Server stumm (Net.state ABSENT): eigene Meldung; Antwort loest sie auf", function()
      local T = boot({ feed = false })
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      -- Anfrage senden und 9 s nichts hoeren
      T.Net.RequestStatus()
      advance(0.1)
      mock.Advance(9, 0.5)
      H.eq(T.Net.state, "ABSENT")
      advance()
      H.eq(G.mode, "ABSENT")
      H.eq(msg(G), "The transmog server module does not answer")
      H.eq(#shownCells(G), 0)
      -- Antwort kommt doch: Meldung weg, Liste da
      feed(T, CHEST, CHEST_LIST, { bucket = 405 })
      advance()
      H.eq(T.Net.state, "OK")
      H.eq(G.mode, "GRID")
      H.truthy(#shownCells(G) > 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Liste laedt (nicht fertig): 'Loading appearances... n / m' mit Balken", function()
      local T = boot({ feed = false })
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      -- Strom beginnt, 20 von 40 IDs, noch kein Ende
      T.Net.Handle("AvailableTransmogs:4:405:40:start")
      local part = {}
      for i = 1, 20 do part[i] = tostring(2000 + i) end
      T.Net.Handle("AvailableTransmogs:4:405:40:" .. table.concat(part, ":"))
      advance()
      H.eq(G.mode, "LOADING")
      H.eq(msg(G), "Loading appearances... 20 / 40")
      H.truthy(G.msgBar:IsShown())
      H.truthy(G.msgFill:IsShown())
      -- Fuellbreite = halbe Spur (Spur 280 - 2)
      H.eq(G.msgFill:GetWidth(), math.floor((G.msgBar:GetWidth() - 2) * 0.5))
      H.eq(#shownCells(G), 0)
      H.truthy(G.pageButtons.next.uiOff)
      -- Ende: Raster
      local rest = {}
      for i = 21, 40 do rest[#rest + 1] = tostring(2000 + i) end
      T.Net.Handle("AvailableTransmogs:4:405:40:" .. table.concat(rest, ":"))
      T.Net.Handle("AvailableTransmogs:4:405:40:end")
      advance()
      H.eq(G.mode, "GRID")
      H.falsy(G.msgBar:IsShown())
      H.falsy(G.msgTitle:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Itemdaten fehlen: Ladezustand mit Fortschritt, danach Raster", function()
      local T = boot({ cache = false })
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      H.eq(G.mode, "LOADING")
      H.eq(msg(G), "Loading appearances... 0 / 40")
      H.eq(#shownCells(G), 0)
      -- Daten laufen ueber die Zeit ein
      local ok = mock.AdvanceUntil(function() return G.mode == "GRID" end, 10, 0.1)
      H.truthy(ok, "Raster erscheint, sobald alles aufgeloest ist")
      H.truthy(#shownCells(G) > 0)
      H.eq(G.stats.unresolved, 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ladezustand blockiert nie ewig: aufgegebene Items (IsFailed) beenden ihn", function()
      -- 36 aufloesbare Items + 4 unbekannte (nie im Cache)
      local T = boot({ cache = false })
      local G = T.UI.Grid
      local list = {}
      for i = 1, 36 do list[i] = 2000 + i end
      for i = 1, 4 do list[#list + 1] = 9000 + i end
      feed(T, CHEST, list, { bucket = 405 })
      G.SetSlot(CHEST)
      H.eq(G.mode, "LOADING")
      -- nach 40 s sind die vier unbekannten aufgegeben (20 s Frist)
      mock.Advance(40, 0.5)
      advance()
      H.eq(T.Items.IsFailed(9001), true)
      H.eq(G.mode, "GRID", "nicht ewig im Ladezustand")
      H.eq(G.stats.unresolved, 4)
      H.eq(G.stats.shown, 36)
      H.truthy(#shownCells(G) > 0)
      H.eq(msg(G), nil)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Liste fertig, aber leer: 'No matching appearances yet' + Original und Verborgen darueber", function()
      local T = boot({ feed = false })
      local G = T.UI.Grid
      feed(T, CHEST, {}, { bucket = 405 })
      G.SetSlot(CHEST)
      H.eq(G.mode, "NO_ITEMS")
      H.eq(msg(G), "No matching appearances yet")
      H.truthy(G.msgHint:IsShown())
      -- Original und Verborgen gibt es trotzdem (der Slot laesst sich verbergen)
      H.deepEq(tags(G), { "orig", "hide" })
      H.falsy(G.resetButton:IsShown())
      H.eq(G.pageText:GetText(), "Page 1 / 1")
      -- Meldung steht unterhalb der ersten Zeile
      local _, _, _, _, y = G.msgTitle:GetPoint(1)
      H.truthy(-y >= G.cellH + 6, "unter der Kachelzeile (y=" .. tostring(y) .. ")")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Filter blenden alles aus: Meldung + 'Reset filters' (ruft Filter.Reset)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.Filter.SetSearch("zzz-nothing")
      advance()
      H.eq(G.mode, "FILTERED")
      H.eq(msg(G), "No appearances match your filters")
      H.truthy(G.resetButton:IsShown())
      H.eq(G.resetButton:GetLabel(), "Reset filters")
      H.deepEq(tags(G), { "orig", "hide" }, "synthetische Kacheln bleiben trotz Filter")
      H.eq(G.countText:GetText(), "0 of 40 appearances (filtered)")
      local events = counter(T, { "FILTER_CHANGED" })
      mock.Click(G.resetButton)
      H.eq(events.FILTER_CHANGED, 1)
      H.eq(T.Filter.IsActive(), false)
      advance()
      H.eq(G.mode, "GRID")
      H.falsy(G.resetButton:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zustandswechsel hinterlassen keine Reste (Balken/Knopf/Zellen verschwinden)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.Filter.SetSearch("zzz")
      advance()
      H.truthy(G.resetButton:IsShown())
      G.SetSlot(HEAD)
      H.eq(G.mode, "EMPTY")
      H.falsy(G.resetButton:IsShown())
      H.falsy(G.msgBar:IsShown())
      H.eq(#shownCells(G), 0)
      G.SetSlot(nil)
      H.eq(G.mode, "NO_SLOT")
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Interaktion")
   -- =========================================================================

   H.test("Linksklick waehlt, zweiter Klick verwirft die Auswahl", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local events = counter(T, { "WANTED_CHANGED" })
      local before = tags(G)
      local cell = shownCells(G)[3]   -- Original, Verborgen, erster Eintrag
      local id = cell.itemId
      H.truthy(id)
      mock.Click(cell)
      H.eq(T.State.Wanted(CHEST), id)
      H.truthy(T.State.HasPending(CHEST))
      H.eq(events.WANTED_CHANGED, 1)
      advance()
      -- die Original-Kachel stand schon vorn: nichts rutscht, die gewaehlte Kachel ist markiert
      H.deepEq(tags(G), before, "Kachelfolge unveraendert")
      local sel
      for _, c in ipairs(shownCells(G)) do
         if c.itemId == id then sel = c end
      end
      H.truthy(sel and sel.selected)
      H.eq(sel.ov.edgeT:GetHeight(), 2, "ausgewaehlt: 2 px Rand")
      -- nochmal: verwirft
      mock.Click(sel)
      H.falsy(T.State.HasPending(CHEST))
      H.eq(T.State.Wanted(CHEST), 0)
      H.eq(events.WANTED_CHANGED, 2)
      advance()
      H.deepEq(tags(G), before, "Kachelfolge nach dem Verwerfen unveraendert")
      for _, c in ipairs(shownCells(G)) do
         H.falsy(c.selected, "nichts mehr ausgewaehlt")
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Original- und Verborgen-Kachel waehlen 0 bzw. HIDDEN; Auswahl-Zustand folgt Wanted", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.Net.Handle("TransmogStatus:1:4,2005")
      advance()
      local cells = shownCells(G)
      H.eq(cells[1].kind, "original")
      H.eq(cells[2].kind, "hidden")
      H.falsy(cells[1].selected)
      H.falsy(cells[2].selected)
      H.falsy(cells[1].applied, "Original ist nicht 'angewendet', solange ein Aussehen angewendet ist")
      -- Verborgen
      mock.Click(cells[2])
      H.eq(T.State.Wanted(CHEST), HIDDEN)
      advance()
      cells = shownCells(G)
      H.truthy(cells[2].selected)
      H.falsy(cells[1].selected)
      -- nochmal: verwirft
      mock.Click(cells[2])
      H.falsy(T.State.HasPending(CHEST))
      H.eq(T.State.Wanted(CHEST), 2005)
      -- Original: waehlt 0 (Entfernen)
      advance()
      cells = shownCells(G)
      mock.Click(cells[1])
      H.eq(T.State.Wanted(CHEST), 0)
      H.truthy(T.State.HasPending(CHEST))
      advance()
      cells = shownCells(G)
      H.truthy(cells[1].selected)
      -- nochmal verwirft
      mock.Click(cells[1])
      H.eq(T.State.Wanted(CHEST), 2005)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Angewendetes Aussehen: rosa Rand + Haken; Verborgen angewendet markiert die Kachel", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.Net.Handle("TransmogStatus:1:4,2003")
      advance()
      local cell = findCell(G, 2003)
      H.truthy(cell and cell.applied)
      H.truthy(cell.ov.check:IsShown())
      H.falsy(cell.selected)
      -- auf Verborgen umstellen
      G.SetPage(1)
      T.Net.Handle("TransmogStatus:1:4," .. HIDDEN)
      advance()
      local cells = shownCells(G)
      H.eq(cells[1].kind, "original")
      H.eq(cells[2].kind, "hidden")
      H.truthy(cells[2].applied)
      H.truthy(cells[2].ov.check:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Rechtsklick: Favorit umschalten, in DB.char.favorites, FAVORITES_CHANGED, Stern", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local events = counter(T, { "FAVORITES_CHANGED", "WANTED_CHANGED" })
      local cell = shownCells(G)[3]   -- erster Eintrag (davor Original und Verborgen)
      local id = cell.itemId
      H.truthy(id)
      mock.Click(cell, "RightButton")
      H.eq(T.DB.char.favorites[id], true)
      H.eq(events.FAVORITES_CHANGED, 1)
      H.eq(events.WANTED_CHANGED, nil, "Rechtsklick waehlt nichts")
      advance()
      local again
      for _, c in ipairs(shownCells(G)) do
         if c.itemId == id then again = c end
      end
      H.truthy(again.favorite)
      H.truthy(again.ov.star:IsShown())
      H.eq(again.ov.star:GetAlpha(), 1)
      -- zurueck
      mock.Click(again, "RightButton")
      H.eq(T.DB.char.favorites[id], nil)
      H.eq(events.FAVORITES_CHANGED, 2)
      -- Persistenz: DB.char ist die gespeicherte Tabelle
      H.eq(rawequal(T.DB.char, TransmogDB), true)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Rechtsklick auf Verborgen/Original aendert keine Favoriten", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.Net.Handle("TransmogStatus:1:4,2005")
      advance()
      local events = counter(T, { "FAVORITES_CHANGED" })
      local before = T.Util.Count(T.DB.char.favorites)
      for _, c in ipairs(shownCells(G)) do
         if c.kind ~= "item" then mock.Click(c, "RightButton") end
      end
      H.eq(events.FAVORITES_CHANGED, nil)
      H.eq(T.Util.Count(T.DB.char.favorites), before)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Shift-Linksklick fuegt den Item-Link in den Chat ein (waehlt nichts)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local cell = shownCells(G)[3]   -- erster Eintrag (davor Original und Verborgen)
      local id = cell.itemId
      H.truthy(id)
      mock.Click(cell, "LeftButton", { shift = true })
      H.eq(#mock.chatInserts, 1)
      H.contains(mock.chatInserts[1], "Hitem:" .. id .. ":")
      H.falsy(T.State.HasPending(CHEST), "Shift-Klick waehlt nicht")
      -- Original-Kachel: der Link des angelegten Gegenstands
      T.State.Select(CHEST, 2005)
      advance()
      local orig = shownCells(G)[1]
      mock.Click(orig, "LeftButton", { shift = true })
      H.eq(#mock.chatInserts, 2)
      H.contains(mock.chatInserts[2], "Hitem:1004:")
      -- Verborgen: kein Link; Shift-Klick wie ein normaler Klick
      local hide = shownCells(G)[2]
      mock.Click(hide, "LeftButton", { shift = true })
      H.eq(#mock.chatInserts, 2)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Tooltip: Item-Tooltip + Zeilen (Angewendet/Ausgewaehlt/Favorit/Neu/Hinweise)", function()
      local T = boot()
      local G = T.UI.Grid
      T.DB.char.favorites[2004] = true
      T.State.new[2004] = true
      G.SetSlot(CHEST)
      local cell = findCell(G, 2004)
      H.truthy(cell)
      mock.Enter(cell)
      H.truthy(GameTooltip:IsShown())
      H.eq(GameTooltip:GetOwner(), cell)
      local lines = tipLines()
      H.eq(lines[1], "Look 04", "Item-Tooltip (SetHyperlink)")
      H.truthy(tipHas("Favourite"))
      H.truthy(tipHas("Newly unlocked"))
      H.truthy(tipHas("Left click: select"))
      H.truthy(tipHas("Right click: toggle favourite"))
      H.truthy(tipHas("Shift + left click: link in chat"))
      H.falsy(tipHas("Currently applied"))
      mock.Leave(cell)
      H.falsy(GameTooltip:IsShown())

      -- ausgewaehlt: Hinweis wechselt
      mock.Click(cell)
      advance()
      cell = findCell(G, 2004)
      mock.Enter(cell)
      H.truthy(tipHas("Selected - not applied yet"))
      H.truthy(tipHas("Left click: discard the selection"))
      H.falsy(tipHas("Left click: select"))
      mock.Leave(cell)

      -- angewendet
      T.State.Discard(CHEST)
      T.Net.Handle("TransmogStatus:1:4,2004")
      advance()
      cell = findCell(G, 2004)
      mock.Enter(cell)
      H.truthy(tipHas("Currently applied"))
      mock.Leave(cell)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Tooltips der synthetischen Kacheln", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.Net.Handle("TransmogStatus:1:4,2005")
      advance()
      local cells = shownCells(G)
      mock.Enter(cells[1])
      H.eq(tipLines()[1], "Chest of Plate", "Item-Tooltip des angelegten Gegenstands")
      H.truthy(tipHas("Original appearance"))
      mock.Leave(cells[1])
      mock.Enter(cells[2])
      H.eq(tipLines()[1], "Hidden")
      H.falsy(tipHas("Right click: toggle favourite"))
      H.falsy(tipHas("Shift + left click: link in chat"))
      mock.Leave(cells[2])
      H.deepEq(H.takeErrors(), {})
   end)

   -- Der 3.3.5-Client zeigt eine anprobierte Einhandwaffe immer in der Haupthand: im Nebenhand-Slot
   -- bekommen Kacheln mit INVTYPE_WEAPON darum eine Hinweiszeile im Tooltip (sonst nirgends).
   H.test("Tooltip im Nebenhand-Slot: Einhandwaffen (INVTYPE_WEAPON) bekommen den Hinweis, andere Kacheln und Slots nicht", function()
      local d = baseItems()
      put(d, 1016, "Kite Shield", 4, 200, "Armor", "Shields", "INVTYPE_SHIELD", "ShieldK")
      put(d, 5001, "Dagger Alpha", 3, 150, "Weapon", "Daggers", "INVTYPE_WEAPON", "DaggerA")
      put(d, 5002, "Shield Beta", 3, 140, "Armor", "Shields", "INVTYPE_SHIELD", "ShieldB")
      put(d, 5003, "Offhand Gamma", 3, 130, "Weapon", "Daggers", "INVTYPE_WEAPONOFFHAND", "OffG")
      put(d, 5004, "Orb Delta", 3, 120, "Armor", "Miscellaneous", "INVTYPE_HOLDABLE", "OrbD")
      local T = boot({ items = d, equip = { [17] = 1016, [16] = 1015, [5] = 1004 } })
      local G = T.UI.Grid
      local OFFHAND = T.Slots.BY_KEY.OFFHAND.server
      H.eq(OFFHAND, 16)
      feed(T, OFFHAND, { 5001, 5002, 5003, 5004 })
      feed(T, MAINHAND, { 4001, 4002 }, { bucket = 207 })
      local hint = T.L.GRID_TIP_OFFHAND_PREVIEW
      H.eq(type(hint), "string")
      H.neq(hint, "GRID_TIP_OFFHAND_PREVIEW", "uebersetzt, nicht der Schluessel")
      H.neq(hint, "")

      G.SetSlot(OFFHAND)
      H.eq(G.mode, "GRID")
      local function tipFor(cell)
         mock.Enter(cell)
         H.truthy(GameTooltip:IsShown())
         local has = tipHas(hint)
         mock.Leave(cell)
         return has
      end
      local seen = {}
      for _, c in ipairs(shownCells(G)) do
         local key = c.kind == "item" and c.itemId or c.kind
         seen[key] = tipFor(c)
      end
      H.eq(seen[5001], true, "Einhandwaffe (INVTYPE_WEAPON): Hinweis")
      H.eq(seen[5002], false, "Schild: kein Hinweis")
      H.eq(seen[5003], false, "Nebenhand-Waffe (INVTYPE_WEAPONOFFHAND): kein Hinweis")
      H.eq(seen[5004], false, "Frei in der Hand (INVTYPE_HOLDABLE): kein Hinweis")
      H.eq(seen.original, false, "Original-Kachel: kein Hinweis")
      H.eq(seen.hidden, nil, "Nebenhand ist nicht verbergbar")
      -- die uebrigen Hinweise der Kachel stehen weiterhin da
      local c5001
      for _, c in ipairs(shownCells(G)) do
         if c.itemId == 5001 then c5001 = c end
      end
      mock.Enter(c5001)
      H.truthy(tipHas("Left click: select"))
      H.truthy(tipHas("Right click: toggle favourite"))
      mock.Leave(c5001)

      -- derselbe Gegenstandstyp in anderen Slots: kein Hinweis
      G.SetSlot(MAINHAND)
      H.eq(G.mode, "GRID")
      local n = 0
      for _, c in ipairs(shownCells(G)) do
         if c.kind == "item" then
            n = n + 1
            H.eq(c.tile.info.equipLoc, "INVTYPE_WEAPON")
            H.eq(tipFor(c), false, "Haupthand " .. tostring(c.itemId) .. ": kein Hinweis")
         end
      end
      H.eq(n, 2)
      G.SetSlot(CHEST)
      for _, c in ipairs(shownCells(G)) do
         H.eq(tipFor(c), false, "Brust: kein Hinweis")
      end
      H.deepEq(H.takeErrors(), {})
   end)

   -- Die Original-Kachel steht immer vorn. Ohne Transmogrifikation IST sie der aktuelle Zustand
   -- ("angewendet": rosa Rand, Haken, Tooltip-Zeile); "ausgewaehlt" ist sie nur, wenn das Entfernen
   -- vorgemerkt ist.
   H.test("Original-Kachel: erste Kachel, 'angewendet' ohne Transmogrifikation, 'ausgewaehlt' beim vorgemerkten Entfernen", function()
      local T = boot()
      local G = T.UI.Grid
      local COL = T.UI.Skin.COL
      G.SetSlot(CHEST)
      local function orig()
         local c = shownCells(G)[1]
         H.eq(c.kind, "original", "erste Kachel")
         return c
      end
      local function edgeIs(c, col, label)
         local v = c.ov.edgeT.__vertex
         H.truthy(v, label .. ": Randfarbe gesetzt")
         H.near(v[1], col[1], 1e-6, label .. " r")
         H.near(v[2], col[2], 1e-6, label .. " g")
         H.near(v[3], col[3], 1e-6, label .. " b")
      end

      -- Baseline 0, nichts gewaehlt: Original ist der aktuelle Zustand
      local o = orig()
      H.truthy(o.applied)
      H.falsy(o.selected)
      H.truthy(o.ov.check:IsShown(), "Haken")
      H.eq(o.ov.edgeT:GetHeight(), 2, "angewendet: 2 px Rand")
      edgeIs(o, COL.pink, "angewendet: rosa Rand")
      mock.Enter(o)
      H.truthy(tipHas("Currently applied"), "Tooltip: aktuell angewendet")
      H.falsy(tipHas("Selected - not applied yet"))
      H.truthy(tipHas("Left click: select"))
      mock.Leave(o)

      -- ein Eintrag gewaehlt: Original bleibt der aktuelle (angewendete) Zustand, ist aber nicht gewaehlt
      mock.Click(shownCells(G)[3])
      advance()
      o = orig()
      H.truthy(T.State.HasPending(CHEST))
      H.truthy(o.applied, "Original ist weiter der angewendete Zustand")
      H.falsy(o.selected)
      H.truthy(shownCells(G)[3].selected)
      -- Original anklicken: verwirft die Auswahl (Wanted == Baseline == 0)
      mock.Click(o)
      advance()
      H.falsy(T.State.HasPending(CHEST))
      H.eq(T.State.Wanted(CHEST), 0)
      H.falsy(shownCells(G)[3].selected)

      -- ein Aussehen angewendet (Baseline ~= 0): Original ist nicht mehr der aktuelle Zustand
      T.Net.Handle("TransmogStatus:1:4,2005")
      advance()
      o = orig()
      H.falsy(o.applied, "ein Aussehen ist angewendet")
      H.falsy(o.selected)
      H.falsy(o.ov.check:IsShown())
      H.eq(o.ov.edgeT:GetHeight(), 1)
      mock.Enter(o)
      H.falsy(tipHas("Currently applied"))
      mock.Leave(o)
      -- Klick: Entfernen vormerken -> ausgewaehlt, nicht angewendet
      mock.Click(o)
      advance()
      H.eq(T.State.Wanted(CHEST), 0)
      H.truthy(T.State.HasPending(CHEST))
      o = orig()
      H.truthy(o.selected, "Entfernen vorgemerkt: ausgewaehlt")
      H.falsy(o.applied)
      H.eq(o.ov.edgeT:GetHeight(), 2)
      edgeIs(o, COL.accent, "ausgewaehlt: Akzentrand")
      mock.Enter(o)
      H.truthy(tipHas("Selected - not applied yet"))
      H.truthy(tipHas("Left click: discard the selection"))
      H.falsy(tipHas("Currently applied"))
      mock.Leave(o)
      -- nochmal: verwirft
      mock.Click(o)
      advance()
      H.falsy(T.State.HasPending(CHEST))
      H.falsy(orig().selected)
      -- Verborgen angewendet: Original weder angewendet noch gewaehlt, Verborgen angewendet
      T.Net.Handle("TransmogStatus:1:4," .. HIDDEN)
      advance()
      o = orig()
      H.falsy(o.applied)
      H.falsy(o.selected)
      H.truthy(shownCells(G)[2].applied)
      -- alles entfernt: Original ist wieder der aktuelle Zustand
      T.Net.Handle("TransmogStatus:0")
      advance()
      o = orig()
      H.truthy(o.applied)
      H.falsy(shownCells(G)[2].applied)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Original-Kachel anklicken, ohne dass etwas vorgemerkt ist: aendert nichts (kein Ereignis, keine Kostenanfrage)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      advance()
      local events = counter(T, { "WANTED_CHANGED", "STATUS_CHANGED" })
      local cost = watchCost(T)
      local before = tags(G)
      clearModelCalls(G)
      local o = shownCells(G)[1]
      H.eq(o.kind, "original")
      mock.Click(o)
      advance(1.0)
      H.eq(T.State.Wanted(CHEST), 0)
      H.falsy(T.State.HasPending(CHEST))
      H.eq(events.WANTED_CHANGED, nil, "kein WANTED_CHANGED")
      H.eq(cost.count, 0, "keine Kostenanfrage")
      H.eq(mock.CountSent("CalculateCost"), 0, "nichts gesendet")
      H.deepEq(tags(G), before)
      H.truthy(shownCells(G)[1].applied)
      H.falsy(shownCells(G)[1].selected)
      H.eq(totalModelCalls(G), 0, "nichts neu angekleidet")
      -- zur Gegenprobe: ein Eintrag loest beides aus
      mock.Click(shownCells(G)[3])
      H.eq(events.WANTED_CHANGED, 1)
      H.eq(cost.count, 1)
      advance(1.0)
      H.truthy(mock.CountSent("CalculateCost") >= 1, "die Kostenanfrage geht jetzt hinaus")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Hover: Rand wird Akzent; Stern als Hinweis; beim Verlassen zurueck", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local cell = shownCells(G)[3]
      H.falsy(cell.hover)
      H.falsy(cell.ov.star:IsShown())
      mock.Enter(cell)
      H.truthy(cell.hover)
      H.truthy(cell.ov.star:IsShown(), "Stern als Hinweis unter der Maus")
      H.truthy(cell.ov.star:GetAlpha() < 1)
      H.truthy(cell.ov.tint:IsShown())
      mock.Leave(cell)
      H.falsy(cell.hover)
      H.falsy(cell.ov.star:IsShown())
      H.falsy(cell.ov.tint:IsShown())
      H.eq(cell.ov.edgeT:GetHeight(), 1)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Tooltip folgt der Zelle, wenn der Inhalt unter der Maus wechselt", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local cell = shownCells(G)[3]   -- erster Eintrag
      mock.Enter(cell)
      local first = tipLines()[1]
      mock.Wheel(cell, -1)   -- naechste Seite, Zelle unter der Maus
      advance()
      local now = tipLines()[1]
      H.eq(now, cell.tile.info.name)
      H.neq(now, first)
      mock.Leave(cell)
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Ankleiden")
   -- =========================================================================

   H.test("Jedes sichtbare Modell wird genau einmal angekleidet (SetUnit/Undress/TryOn)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local cells = shownCells(G)   -- Original + Verborgen + 8 Eintraege
      local models = 0
      for _, c in ipairs(cells) do
         if c.kind == "item" then
            models = models + 1
            local m = mock.Model(c.model)
            H.eq(m.count("SetUnit"), 1, "SetUnit")
            H.eq(m.count("TryOn"), 1, "TryOn")
            H.eq(m.count("Undress"), 1, "Undress (kein Hand-Slot)")
            H.deepEq(m.tried, { c.itemId })
         end
      end
      H.eq(models, 8)
      -- die Original-Kachel zieht den angelegten Gegenstand an (ebenfalls genau einmal)
      local om = mock.Model(cells[1].model)
      H.eq(cells[1].kind, "original")
      H.eq(om.count("SetUnit"), 1)
      H.eq(om.count("Undress"), 1)
      H.eq(om.count("TryOn"), 1)
      H.deepEq(om.tried, { 1004 })
      -- Verborgen: gar kein Modell
      H.eq(cells[2].kind, "hidden")
      H.falsy(cells[2].model)
      H.eq(modelCalls(G, "SetUnit"), 9, "8 Eintraege + Original")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Favorit/Status-/Itemereignisse ohne Aenderung der Kachelliste kleiden NICHT neu an", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      clearModelCalls(G)
      T.DB.char.favorites[2002] = true
      T.Events.Fire("FAVORITES_CHANGED")
      advance()
      T.Events.Fire("ITEMS_RESOLVED", 1)
      T.Events.Fire("STATUS_CHANGED")
      T.Events.Fire("LIST_PROGRESS", CHEST, 40, 40)
      T.Events.Fire("COLLECTION_UPDATED", 2001)
      advance()
      H.eq(modelCalls(G, "SetUnit"), 0, "kein SetUnit")
      H.eq(modelCalls(G, "TryOn"), 0, "kein TryOn")
      H.eq(modelCalls(G, "Undress"), 0, "kein Undress")
      -- eine Auswahl auf einer anderen Seite aendert die Kacheln dieser Seite nicht:
      -- auch die Original-Kachel steht schon da und wird nicht neu angekleidet
      T.State.Select(CHEST, 2040)
      advance()
      local sel = 0
      for _, c in ipairs(shownCells(G)) do
         if c.selected then sel = sel + 1 end
      end
      H.eq(sel, 0, "2040 steht auf der letzten Seite")
      H.eq(modelCalls(G, "SetUnit"), 0, "kein SetUnit nach der Auswahl")
      H.eq(modelCalls(G, "TryOn"), 0)
      H.eq(modelCalls(G, "Undress"), 0)
      H.deepEq(H.takeErrors(), {})
   end)

   -- Die Modelle (DressUpModel) verlieren im echten Client Auskleidung und Kamera, wenn man sie
   -- mit SetParent in eine andere Zelle haengt (Spieltest 2026-10-12: nach dem ersten Klick sah
   -- jede Kachel "voll angezogen, Standardkamera" aus). Darum: Modell bleibt in seiner Zelle.
   H.test("Erste Auswahl verschiebt nichts: gleiche Kacheln, kein Modell wechselt die Zelle, kein Ankleiden, kein SetParent", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local before = tags(G)                    -- orig, hide, e1 .. e8
      H.eq(#before, 10)
      H.eq(before[1], "orig")
      H.eq(before[2], "hide")
      local cellsBefore, modelsBefore = {}, modelMap(G)
      for i, c in ipairs(G.cells) do cellsBefore[i] = c end
      clearModelCalls(G)
      local watch = watchSetParent()

      -- nichts darf sich bewegen oder neu geladen werden
      local function assertStill(label)
         advance()
         H.deepEq(tags(G), before, label .. ": gleiche Kachelfolge")
         H.eq(#G.cells, #cellsBefore, label .. ": keine neuen Zellen")
         for i, c in ipairs(G.cells) do
            H.eq(c, cellsBefore[i], label .. ": Zelle " .. i)
            H.eq(c.model or false, modelsBefore[i], label .. ": Modell blieb in Zelle " .. i)
            if c.model then
               H.eq(c.model:GetParent(), c, label .. ": Modell haengt an Zelle " .. i)
            end
         end
         H.eq(totalModelCalls(G), 0, label .. ": kein einziger Modellaufruf (SetUnit/Undress/TryOn/Kamera)")
         H.eq(watch.count, 0, label .. ": kein SetParent auf einem Zellmodell")
      end

      local function selectedCells()
         local out = {}
         for i, c in ipairs(G.cells) do
            if c:IsShown() and c.selected then out[#out + 1] = i end
         end
         return out
      end

      -- 1. erste Auswahl: ein Eintrag (der erste Klick im Spieltest)
      local id1 = G.cells[3].itemId
      mock.Click(G.cells[3])
      H.eq(T.State.Wanted(CHEST), id1)
      assertStill("erste Auswahl")
      H.deepEq(selectedCells(), { 3 })
      -- 2. andere Kachel: ersetzt die Auswahl
      mock.Click(G.cells[4])
      H.eq(T.State.Wanted(CHEST), G.cells[4].itemId)
      assertStill("zweite Auswahl")
      H.deepEq(selectedCells(), { 4 })
      -- 3. Verborgen
      mock.Click(G.cells[2])
      H.eq(T.State.Wanted(CHEST), HIDDEN)
      assertStill("Verborgen")
      H.deepEq(selectedCells(), { 2 })
      -- 4. wieder ein Eintrag, dann dieselbe Kachel nochmal: verwirft
      mock.Click(G.cells[3])
      assertStill("Eintrag nach Verborgen")
      mock.Click(G.cells[3])
      H.falsy(T.State.HasPending(CHEST))
      assertStill("verworfen")
      H.deepEq(selectedCells(), {})
      -- 5. Original mit Auswahl: verwirft sie (Baseline 0)
      mock.Click(G.cells[5])
      assertStill("Auswahl vor Original")
      mock.Click(G.cells[1])
      H.falsy(T.State.HasPending(CHEST))
      assertStill("Original")
      watch.stop()
      -- Endzustand wie im Spieltest: jedes Modell ist noch ausgezogen und zeigt nur sein Aussehen
      for i, c in ipairs(shownCells(G)) do
         if c.model then
            local m = mock.Model(c.model)
            H.truthy(m.undressed, "Zelle " .. i .. ": Modell noch ausgezogen")
            H.deepEq(m.tried, { c.kind == "original" and 1004 or c.itemId }, "Zelle " .. i .. ": nur das eigene Aussehen")
         end
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Erste Auswahl bei angewendetem Aussehen: ebenfalls keine Bewegung (Baseline ~= 0)", function()
      local T = boot()
      local G = T.UI.Grid
      T.Net.Handle("TransmogStatus:1:4,2005")
      G.SetSlot(CHEST)
      advance()
      local before = tags(G)
      local models = modelMap(G)
      clearModelCalls(G)
      local watch = watchSetParent()
      mock.Click(G.cells[4])
      advance()
      mock.Click(G.cells[1])        -- Original: Entfernen vormerken
      advance()
      watch.stop()
      H.eq(T.State.Wanted(CHEST), 0)
      H.truthy(G.cells[1].selected)
      H.deepEq(tags(G), before)
      H.deepEq(modelMap(G), models)
      H.eq(totalModelCalls(G), 0)
      H.eq(watch.count, 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Modelle bleiben in ihrer Zelle (nie SetParent); wechselt die Kachel einer Zelle, wird dort neu angekleidet", function()
      local T = boot()
      local G = T.UI.Grid
      H.eq(G.reuseModels, false, "Standard: Modelle nicht zwischen Zellen verschieben")
      G.SetSlot(CHEST)
      local before = tags(G)                    -- orig, hide, Qualitaet 4 nach Name: Look 04, 09, 14 ...
      local models = modelMap(G)
      local pos04                               -- Zelle, in der "Look 04" (2004) vor der Sortierung steht
      for i, t in ipairs(before) do
         if t == 2004 then pos04 = i end
      end
      H.truthy(pos04, "Look 04 steht auf Seite 1 (Qualitaet 4)")
      clearModelCalls(G)
      local watch = watchSetParent()
      T.Filter.SetSort("NAME")                  -- Look 01 .. Look 08: alle Eintraege wechseln, 2004 rutscht in eine andere Zelle
      advance()
      watch.stop()
      local after = tags(G)
      H.deepEq(after, { "orig", "hide", 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008 })
      local pos04After
      for i, t in ipairs(after) do
         if t == 2004 then pos04After = i end
      end
      H.neq(pos04After, pos04, "2004 steht jetzt in einer anderen Zelle")
      H.eq(watch.count, 0, "kein SetParent auf einem Zellmodell")
      for i, c in ipairs(G.cells) do
         H.eq(c.model or false, models[i], "Modell blieb in Zelle " .. i)
         if c.model then H.eq(c.model:GetParent(), c) end
      end
      -- Zellen mit gleicher Kachel unberuehrt, die anderen genau einmal neu angekleidet
      local dressed = 0
      for i, c in ipairs(G.cells) do
         if c:IsShown() and c.model and c.model:IsShown() then
            local m = mock.Model(c.model)
            if after[i] == before[i] then
               H.eq(#m.calls, 0, "Zelle " .. i .. " unveraendert: kein Aufruf")
            else
               dressed = dressed + 1
               H.eq(m.count("SetUnit"), 1, "Zelle " .. i .. " neu angekleidet")
               H.eq(m.count("Undress"), 1)
               H.eq(m.count("TryOn"), 1)
               H.deepEq(m.tried, { after[i] }, "Zelle " .. i .. " zeigt ihren neuen Eintrag")
            end
         end
      end
      H.eq(dressed, 8, "alle acht Eintragszellen haben eine neue Kachel")
      H.eq(modelCalls(G, "SetUnit"), 8)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Grid.reuseModels = true (Opt-in, im echten Client unbrauchbar): Modelle wandern mit ihrer Kachel", function()
      -- Die alte Arbeitsweise bleibt als Schalter erhalten: wer sie einschaltet, bekommt
      -- Modelle, die mit ihrer Kachel die Zelle wechseln (SetParent), und spart das Ankleiden.
      local T = boot()
      local G = T.UI.Grid
      G.reuseModels = true
      G.SetSlot(CHEST)
      local before = tags(G)
      local pos04
      for i, t in ipairs(before) do
         if t == 2004 then pos04 = i end
      end
      H.truthy(pos04)
      local model04 = G.cells[pos04].model
      clearModelCalls(G)
      local watch = watchSetParent(true)   -- (die Attrappe laesst den Zustand des Modells stehen)
      T.Filter.SetSort("NAME")
      advance()
      watch.stop()
      local after = tags(G)
      H.deepEq(after, { "orig", "hide", 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008 })
      H.truthy(watch.count > 0, "Modelle werden umgehaengt")
      local cell04
      for i, c in ipairs(G.cells) do
         if after[i] == 2004 then cell04 = c end
      end
      H.eq(cell04.model, model04, "das Modell von 2004 ist mitgewandert")
      H.eq(model04:GetParent(), cell04)
      H.eq(#mock.Model(model04).calls, 0, "und wurde nicht neu angekleidet")
      H.eq(modelCalls(G, "SetUnit"), 7, "nur die anderen sieben Eintraege")
      for _, c in ipairs(shownCells(G)) do
         if c.kind == "item" then
            local m = mock.Model(c.model)
            H.eq(m.tried[#m.tried], c.itemId, "Modell gehoert zur Kachel")
            H.eq(c.model:GetParent(), c)
         end
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Seitenwechsel kleidet die geaenderten Zellen an; Rueckkehr gleiche IDs neu", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      clearModelCalls(G)
      G.SetPage(2)
      H.eq(modelCalls(G, "SetUnit"), 10, "Seite 2: 10 neue Eintraege")
      H.eq(modelCalls(G, "TryOn"), 10)
      clearModelCalls(G)
      G.SetPage(2)   -- gleiche Seite: nichts
      G.Refresh()
      H.eq(modelCalls(G, "SetUnit"), 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Rebuild erzwingt neues Ankleiden aller sichtbaren Modelle", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      clearModelCalls(G)
      G.Rebuild()
      H.eq(modelCalls(G, "SetUnit"), 9)
      H.eq(modelCalls(G, "TryOn"), 9)
      H.deepEq(H.takeErrors(), {})
   end)

   -- Ein verborgenes Modell verliert im echten Client Auskleidung und Kamera (Spieltest: nach dem
   -- Wechsel Outfits -> Items sahen die Kacheln "voll angezogen" aus): beim Zeigen wird alles neu
   -- angekleidet, genau einmal.
   H.test("Raster verbergen (Outfit-Reiter) und wieder zeigen: jedes sichtbare Modell wird genau einmal neu angekleidet", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      advance()
      local before = tags(G)
      H.eq(#before, 10)
      clearModelCalls(G)
      local watch = watchSetParent()

      local function checkRedressed(label)
         local n = 0
         for i, c in ipairs(shownCells(G)) do
            if c.kind == "hidden" then
               H.falsy(c.model, label .. ": Verborgen hat kein Modell")
            else
               n = n + 1
               local id = (c.kind == "original") and 1004 or c.itemId
               assertDressedOnce(mock.Model(c.model), label .. " Zelle " .. i, id, false)
            end
         end
         H.eq(n, 9, label .. ": Original + 8 Eintraege")
         H.eq(modelCalls(G, "SetUnit"), 9, label)
      end

      G.frame:Hide()                 -- Reiter "Outfits"
      advance(0.5)
      H.eq(totalModelCalls(G), 0, "Verbergen laedt nichts")
      G.frame:Show()                 -- Reiter "Items"
      advance(0.5)
      H.deepEq(tags(G), before, "gleiche Kacheln")
      checkRedressed("Reiterwechsel")

      -- noch ein Mal; und der Rahmen darueber (Fenster zu/auf) zaehlt ebenso
      clearModelCalls(G)
      G.frame:Hide()
      advance(0.5)
      G.frame:Show()
      advance(0.5)
      checkRedressed("zweiter Reiterwechsel")
      clearModelCalls(G)
      T.parent:Hide()
      advance(0.5)
      H.eq(totalModelCalls(G), 0, "Fenster zu: nichts")
      T.parent:Show()
      advance(0.5)
      checkRedressed("Fenster zu und auf")

      -- danach Ruhe: weitere Aktualisierungen ziehen nichts neu an
      clearModelCalls(G)
      G.Refresh()
      T.Events.Fire("STATUS_CHANGED")
      advance()
      H.eq(totalModelCalls(G), 0, "kein weiteres Ankleiden")
      watch.stop()
      H.eq(watch.count, 0, "kein SetParent")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Raster verbergen und zeigen im Hand-Slot: SetUnit + TryOn, nie Undress", function()
      local T = boot({ equip = { [16] = 1015, [5] = 1004 } })
      local G = T.UI.Grid
      feed(T, MAINHAND, { 4001, 4002 }, { bucket = 207 })
      G.SetSlot(MAINHAND)
      advance()
      H.deepEq(tags(G), { "orig", 4001, 4002 })
      clearModelCalls(G)
      G.frame:Hide()
      advance(0.5)
      H.eq(totalModelCalls(G), 0)
      G.frame:Show()
      advance(0.5)
      for i, c in ipairs(shownCells(G)) do
         local id = (c.kind == "original") and 1015 or c.itemId
         assertDressedOnce(mock.Model(c.model), "Zelle " .. i, id, true)
      end
      H.eq(modelCalls(G, "SetUnit"), 3)
      H.eq(modelCalls(G, "Undress"), 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Raster zeigen ohne Slot oder mit Meldung: es gibt nichts anzukleiden, kein Fehler", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(nil)
      G.frame:Hide()
      G.frame:Show()
      advance()
      H.eq(G.mode, "NO_SLOT")
      H.eq(#shownCells(G), 0)
      G.SetSlot(HEAD)               -- nichts angelegt
      G.frame:Hide()
      G.frame:Show()
      advance()
      H.eq(G.mode, "EMPTY")
      H.eq(totalModelCalls(G), 0)
      G.SetSlot(CHEST)
      H.eq(G.mode, "GRID")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Grid.InvalidateModels: loescht nur die Schluessel; das naechste Zeichnen kleidet alles neu an", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      clearModelCalls(G)
      G.InvalidateModels()
      H.eq(totalModelCalls(G), 0, "InvalidateModels allein ruft nichts auf")
      for _, c in ipairs(G.cells) do H.falsy(c.dressKey) end
      G.Refresh()
      H.eq(modelCalls(G, "SetUnit"), 9)
      H.eq(modelCalls(G, "TryOn"), 9)
      G.Refresh()
      H.eq(modelCalls(G, "SetUnit"), 9, "und danach wieder Ruhe")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Vorschaugroesse aendern: Zellen neu dimensioniert, Modelle neu geladen (SetUnit)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      clearModelCalls(G)
      T.DB.Set("previewSize", 1.25)   -- SETTINGS_CHANGED -> Layout
      H.eq(G.scale, 1.25)
      H.eq(G.perPage, 8)
      local models = 0
      for _, c in ipairs(shownCells(G)) do
         H.near(c:GetWidth(), 115, 1e-9)
         if c.model and c.model:IsShown() then
            models = models + 1
            H.near(c.model:GetWidth(), 100, 1e-9)
            H.eq(mock.Model(c.model).count("SetUnit"), 1, "SetUnit nach der Groessenaenderung")
         end
      end
      H.truthy(models > 0)
      H.eq(#shownCells(G), 8)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout ohne Aenderung von Zellgroesse/-zahl kleidet nicht neu an", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      clearModelCalls(G)
      G.Layout(510, 400)   -- gleiche Spalten, andere Breite
      G.Layout(520, 410)
      H.eq(modelCalls(G, "SetUnit"), 0)
      H.eq(G.perPage, 10)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Hand-Slot: kein Undress, Kamera ueber Cameras.Dress", function()
      local T = boot({ equip = { [16] = 1015, [5] = 1004 } })
      local G = T.UI.Grid
      feed(T, MAINHAND, { 4001, 4002 }, { bucket = 207 })
      G.SetSlot(MAINHAND)
      for _, c in ipairs(shownCells(G)) do
         local m = mock.Model(c.model)
         H.eq(m.count("Undress"), 0, "Hand-Slot: nie Undress")
         H.eq(m.count("TryOn"), 1)
         H.eq(m.count("SetUnit"), 1)
      end
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Ereignisse und Aktualisierung")
   -- =========================================================================

   H.test("Ereignisse werden gebuendelt: viele Ereignisse = ein Filter.Compute", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      advance()
      local calls = 0
      local orig = T.Filter.Compute
      T.Filter.Compute = function(...)
         calls = calls + 1
         return orig(...)
      end
      for _ = 1, 5 do
         T.Events.Fire("ITEMS_RESOLVED", 1)
         T.Events.Fire("LIST_PROGRESS", CHEST, 1, 40)
         T.Events.Fire("WANTED_CHANGED", CHEST)
         T.Events.Fire("STATUS_CHANGED")
      end
      H.eq(calls, 0, "noch nichts berechnet (gebuendelt)")
      advance()
      H.eq(calls, 1, "genau ein Compute je Aktualisierung")
      T.Filter.Compute = orig
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ein Refresh ruft Filter.Compute genau einmal (auch SetSlot/SetPage/Layout)", function()
      local T = boot()
      local G = T.UI.Grid
      local calls = 0
      local orig = T.Filter.Compute
      T.Filter.Compute = function(...)
         calls = calls + 1
         return orig(...)
      end
      G.SetSlot(CHEST)
      H.eq(calls, 1, "SetSlot")
      G.SetPage(2)
      H.eq(calls, 2, "SetPage")
      G.Refresh()
      H.eq(calls, 3, "Refresh")
      G.Layout(700, 500)
      H.truthy(calls <= 4, "Layout hoechstens ein weiteres Compute: " .. calls)
      T.Filter.Compute = orig
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ereignisse anderer Slots loesen keine Aktualisierung aus", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      advance()
      local calls = 0
      local orig = T.Filter.Compute
      T.Filter.Compute = function(...)
         calls = calls + 1
         return orig(...)
      end
      T.Events.Fire("LIST_READY", HEAD)
      T.Events.Fire("LIST_PROGRESS", HEAD, 1, 2)
      T.Events.Fire("WANTED_CHANGED", HEAD)
      T.Events.Fire("EQUIPMENT_CHANGED", HEAD)
      advance()
      H.eq(calls, 0)
      T.Events.Fire("LIST_READY", CHEST)
      advance()
      H.eq(calls, 1)
      T.Filter.Compute = orig
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Unsichtbar: kein Berechnen (Dirty-Flag), Nachholen im OnShow", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      advance()
      T.parent:Hide()
      local calls = 0
      local orig = T.Filter.Compute
      T.Filter.Compute = function(...)
         calls = calls + 1
         return orig(...)
      end
      T.State.Select(CHEST, 2005)
      T.Filter.SetSearch("Look 11")
      T.Events.Fire("ITEMS_RESOLVED", 3)
      advance()
      G.Refresh()
      H.eq(calls, 0, "versteckt: nichts berechnet")
      T.parent:Show()
      H.eq(calls, 1, "OnShow holt nach")
      H.eq(G.page, 1)
      T.Filter.Compute = orig
      -- und die Anzeige stimmt: Suche aktiv
      local n = 0
      for _, c in ipairs(shownCells(G)) do
         if c.kind == "item" then
            n = n + 1
            H.eq(c.tile.info.name, "Look 11")
         end
      end
      H.eq(n, 1)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("SetSlot fordert die Itemdaten der Liste an (RequestMany)", function()
      local T = boot({ cache = false })
      local G = T.UI.Grid
      local requested = {}
      local orig = T.Items.RequestMany
      T.Items.RequestMany = function(array)
         for i = 1, #array do requested[#requested + 1] = array[i] end
         return orig(array)
      end
      G.SetSlot(CHEST)
      H.truthy(#requested >= CHEST_COUNT, "alle IDs der Liste angefordert: " .. #requested)
      H.eq(requested[1], 2001)
      H.eq(requested[CHEST_COUNT], 2040)
      T.Items.RequestMany = orig
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Kein haengendes OnUpdate nach dem Aktualisieren (Leerlauf)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.State.Select(CHEST, 2005)
      G.SetPage(2)
      T.Filter.SetSearch("Look")
      advance(0.5)
      -- Kostenabfrage des Modells (5 s Frist) und Items laufen aus
      mock.Advance(20, 0.5)
      H.eq(T.Util.TimerCount(), 0, "keine offenen Timer")
      H.eq(#mock.UpdateFrames(), 0, "keine sichtbaren OnUpdate-Frames im Leerlauf")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Sprachwechsel: Texte der Meldungen, Leiste und Zellen folgen", function()
      local T = boot()
      T.Locale.Add("deDE", {
         GRID_NO_SLOT = "Waehle einen Ausruestungsplatz", GRID_PAGE = "Seite %d / %d",
         GRID_COUNT = "%s von %s Aussehen", GRID_COUNT_FILTERED = "%s von %s Aussehen (gefiltert)",
         GRID_NEW = "NEU", GRID_ORIGINAL = "Urspruenglich", GRID_HIDDEN = "Verborgen",
         GRID_RESET_FILTERS = "Filter zuruecksetzen", GRID_TIP_LEFT_SELECT = "Linksklick: auswaehlen",
      })
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.State.new[2002] = true
      G.Refresh()
      H.eq(G.pageText:GetText(), "Page 1 / 5")
      T.Locale.Set("deDE")
      advance()
      H.eq(G.pageText:GetText(), "Seite 1 / 5")
      H.eq(G.countText:GetText(), "40 von 40 Aussehen")
      H.eq(G.resetButton:GetLabel(), "Filter zuruecksetzen")
      H.eq(shownCells(G)[1].kind, "original")
      H.eq(shownCells(G)[1].ov.name:GetText(), "Urspruenglich")
      H.eq(shownCells(G)[2].kind, "hidden")
      H.eq(shownCells(G)[2].ov.name:GetText(), "Verborgen")
      G.SetSlot(nil)
      H.eq(msg(G), "Waehle einen Ausruestungsplatz")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zufallsfolge: Invarianten von Kacheln, Modellen und Seiten halten", function()
      local T = boot({ equip = { [16] = 1015, [5] = 1004, [1] = 1001 } })
      local G = T.UI.Grid
      feed(T, MAINHAND, { 4001, 4002 }, { bucket = 207 })
      feed(T, HEAD, { 3001, 3002 }, { bucket = 404 })

      -- reproduzierbare Zufallszahlen
      local seed = 20240611
      local function rnd(n)
         seed = (seed * 1103515245 + 12345) % 2147483648
         return math.floor(seed / 65536) % n
      end

      -- 2: nichts angelegt, "none": kein Slot gewaehlt
      local slots = { CHEST, CHEST, HEAD, MAINHAND, 2, "none", CHEST }
      local function pickSlot()
         local v = slots[rnd(#slots) + 1]
         if v == "none" then return nil end
         return v
      end
      local sizes = { { 500, 400 }, { 398, 300 }, { 700, 560 }, { 880, 500 }, { 300, 250 } }
      local scales = { 0.8, 1.0, 1.25, 1.5 }
      local filters = {
         function() T.Filter.SetQuality(rnd(5), rnd(2) == 0) end,
         function() T.Filter.SetSearch(({ "", "Look", "Look 1", "zz", "#2005" })[rnd(5) + 1]) end,
         function() T.Filter.SetFavoritesOnly(rnd(2) == 0) end,
         function() T.Filter.SetNewOnly(rnd(2) == 0) end,
         function() T.Filter.SetHideDuplicates(rnd(2) == 0) end,
         function() T.Filter.SetSort(({ "QUALITY", "NAME", "ILEVEL" })[rnd(3) + 1]) end,
         function() T.Filter.Reset() end,
      }

      -- erwartete Kachelfolge der aktuellen Seite (unabhaengig vom Grid gerechnet)
      local function expectedTags()
         local slot = G.slot
         local out = {}
         local mode = G.mode
         if mode ~= "GRID" and mode ~= "NO_ITEMS" and mode ~= "FILTERED" then return out end
         local tiles = { "orig" }   -- Original steht immer vorn
         if T.Slots.IsHideable(slot) then tiles[#tiles + 1] = "hide" end
         if mode == "GRID" then
            local entries = T.Filter.Compute(slot)
            for i = 1, #entries do tiles[#tiles + 1] = entries[i].id end
         end
         local per = G.perPage
         local pages = math.max(1, math.ceil(#tiles / per))
         local page = math.min(math.max(G.page, 1), pages)
         for i = (page - 1) * per + 1, math.min(#tiles, page * per) do out[#out + 1] = tiles[i] end
         return out, pages
      end

      -- Jede Zelle behaelt fuer immer ihr erstes Modell (kein Umhaengen zwischen Zellen)
      local modelOf = {}
      local watch = watchSetParent()

      local function check(step, what)
         advance(0.2)
         local label = "step " .. step .. " (" .. what .. ")"
         local shown = shownCells(G)
         local mode = G.mode
         if mode == "GRID" or mode == "NO_ITEMS" or mode == "FILTERED" then
            local want, pages = expectedTags()
            H.deepEq(tags(G), want, label .. ": Kacheln der Seite")
            H.eq(G.pages, pages, label .. ": Seitenzahl")
            H.truthy(G.page >= 1 and G.page <= G.pages, label .. ": Seite im Bereich")
            H.truthy(#shown <= G.perPage, label .. ": nicht mehr Zellen als perPage")
         else
            H.eq(#shown, 0, label .. ": " .. mode .. " zeigt keine Zellen")
         end
         -- Modelle: eigenes Eltern, einmalig, passen zur Kachel
         local seen = {}
         for _, c in ipairs(shown) do
            if c.model and c.model:IsShown() then
               H.eq(c.model:GetParent(), c, label .. ": Modell haengt an seiner Zelle")
               H.falsy(seen[c.model], label .. ": Modell nur einmal")
               seen[c.model] = true
               local m = mock.Model(c.model)
               local last = m.tried[#m.tried]
               if c.kind == "item" then
                  H.eq(last, c.itemId, label .. ": Modell zeigt das Item der Kachel")
               elseif c.kind == "original" then
                  local eq = T.State.Equipped(G.slot)
                  H.eq(last, eq and eq.id, label .. ": Original zeigt den angelegten Gegenstand")
               end
            elseif c.kind ~= "hidden" then
               H.fail(label .. ": Kachel ohne sichtbares Modell (" .. tostring(tag(c)) .. ")")
            end
            if c.kind == "original" then
               -- ohne Transmogrifikation ist Original der aktuelle Zustand; "ausgewaehlt"
               -- nur, wenn das Entfernen vorgemerkt ist
               H.eq(c.applied, T.State.Baseline(G.slot) == 0, label .. ": Original angewendet")
               H.eq(c.selected, T.State.HasPending(G.slot) and T.State.Wanted(G.slot) == 0,
                  label .. ": Original ausgewaehlt")
            end
         end
         for i, c in ipairs(G.cells) do
            if c.model then
               modelOf[c] = modelOf[c] or c.model
               H.eq(c.model, modelOf[c], label .. ": Zelle " .. i .. " behaelt ihr Modell")
            end
         end
         -- Zellen jenseits der Seite sind versteckt
         for i = #shown + 1, #G.cells do
            H.falsy(G.cells[i]:IsShown(), label .. ": ueberzaehlige Zelle versteckt")
         end
      end

      G.SetSlot(CHEST)
      check(0, "start")
      for step = 1, 400 do
         local op = rnd(18)
         local what
         if op == 0 then
            local l = sizes[rnd(#sizes) + 1]
            G.Layout(l[1], l[2])
            what = "Layout " .. l[1] .. "x" .. l[2]
         elseif op == 1 then
            local f = scales[rnd(#scales) + 1]
            T.DB.Set("previewSize", f)
            what = "previewSize " .. f
         elseif op == 2 or op == 3 then
            G.SetPage(rnd(6) + 1)
            what = "SetPage"
         elseif op == 4 then
            G.Page(rnd(2) == 0 and -1 or 1)
            what = "Page"
         elseif op == 5 then
            local cells = shownCells(G)
            if #cells > 0 then
               local c = cells[rnd(#cells) + 1]
               mock.Click(c)
            end
            what = "Linksklick"
         elseif op == 6 then
            local cells = shownCells(G)
            if #cells > 0 then
               mock.Click(cells[rnd(#cells) + 1], "RightButton")
            end
            what = "Rechtsklick"
         elseif op == 7 then
            filters[rnd(#filters) + 1]()
            what = "Filter"
         elseif op == 8 then
            G.SetSlot(pickSlot())
            what = "SetSlot"
         elseif op == 9 then
            local id = 2000 + rnd(CHEST_COUNT) + 1
            T.Net.Handle("TransmogStatus:1:4," .. (rnd(4) == 0 and HIDDEN or id))
            what = "Status"
         elseif op == 10 then
            T.State.DiscardAll()
            what = "DiscardAll"
         elseif op == 11 then
            T.State.new[2000 + rnd(CHEST_COUNT) + 1] = true
            T.Events.Fire("COLLECTION_UPDATED", 2001)
            what = "neu gesammelt"
         elseif op == 12 then
            local n = 5 + rnd(CHEST_COUNT - 5)
            local list = {}
            for i = 1, n do list[i] = 2000 + i end
            feed(T, CHEST, list, { bucket = 405 })
            what = "neue Liste " .. n
         elseif op == 13 then
            G.Rebuild()
            what = "Rebuild"
         elseif op == 14 then
            -- Brust aus-/anziehen (leerer Slot, neuer Strom)
            if mock.world.equipment[5] then
               mock.world.equipment[5] = nil
            else
               mock.world.equipment[5] = 1004
            end
            mock.Fire("PLAYER_EQUIPMENT_CHANGED", 5)
            what = "Ausruestung"
         elseif op == 15 then
            -- Strom beginnt, endet aber nicht (Ladezustand)
            T.Net.Handle("AvailableTransmogs:4:405:30:start")
            local part = {}
            for i = 1, 10 do part[i] = tostring(2000 + i) end
            T.Net.Handle("AvailableTransmogs:4:405:30:" .. table.concat(part, ":"))
            what = "Teilstrom"
         elseif op == 16 then
            G.SetSlot(pickSlot())
            what = "SetSlot"
         else
            mock.Wheel(G.frame, rnd(2) == 0 and -1 or 1)
            what = "Mausrad"
         end
         check(step, what)
         -- der Server liefert die Liste nach: haeufig, damit das Raster oft zu sehen ist
         if mock.world.equipment[5] and not T.State.ListReady(CHEST) and rnd(3) > 0 then
            feed(T, CHEST, CHEST_LIST, { bucket = 405 })
         end
         -- und der Spieler kehrt oft zur Brust zurueck
         if (G.mode == "NO_SLOT" or G.mode == "EMPTY") and rnd(2) == 0 then
            if not mock.world.equipment[5] then
               mock.world.equipment[5] = 1004
               mock.Fire("PLAYER_EQUIPMENT_CHANGED", 5)
               feed(T, CHEST, CHEST_LIST, { bucket = 405 })
            end
            G.SetSlot(CHEST)
         end
      end
      watch.stop()
      H.eq(watch.count, 0, "kein Modell wurde je mit SetParent umgehaengt")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ausgang: Erst Layout dann SetSlot und umgekehrt liefern dasselbe Bild", function()
      local T1 = boot({ noGrid = true })
      local parent = CreateFrame("Frame", nil, UIParent)
      parent:SetWidth(800)
      parent:SetHeight(600)
      parent:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      local G = T1.UI.Grid
      G.SetSlot(CHEST)            -- vor Create: nur merken
      G.Create(parent)
      G.Layout(500, 400)
      G.Refresh()
      H.eq(G.mode, "GRID")
      H.eq(#shownCells(G), 10)
      H.deepEq(H.takeErrors(), {})
   end)
   -- =========================================================================
   H.section("Nachpruefung: Seiten- und Auswahlsemantik")
   -- =========================================================================

   -- Kachelnummer (1-basiert, ueber alle Seiten) der Kachel mit der Item-ID
   local function tileIndexOf(T, G, id)
      local entries = T.Filter.Compute(G.slot)
      local n = 1                -- Original steht immer vorn
      local slot = G.slot
      if T.Slots.IsHideable(slot) then n = n + 1 end
      for i = 1, #entries do
         if entries[i].id == id then return n + i end
      end
      return nil
   end

   -- Liegt Kachel Nummer idx auf der aktuellen Seite?
   local function onPage(G, idx)
      return idx > (G.page - 1) * G.perPage and idx <= G.page * G.perPage
   end

   H.test("Liste laedt neu (gleicher Gegenstand): Meldung dazwischen, danach dieselbe Seite", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      G.SetPage(3)
      local before = tags(G)
      T.Net.Handle("AvailableTransmogs:4:405:40:start")   -- neuer Strom (z. B. nach neuem Aussehen)
      advance()
      H.eq(G.mode, "LOADING")
      -- waehrend der Meldung gibt es keine Seiten: Mausrad/Knoepfe aendern nichts
      mock.Wheel(G.frame, -1)
      mock.Wheel(G.frame, 1)
      mock.Click(G.pageButtons.last)
      H.eq(G.page, 1)
      H.eq(G.pages, 1)
      feed(T, CHEST, CHEST_LIST, { bucket = 405 })
      advance()
      H.eq(G.mode, "GRID")
      H.eq(G.page, 3, "die vorige Seite ist wieder da")
      H.deepEq(tags(G), before)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Liste laedt kuerzer neu: gemerkte Seite wird auf die letzte geklemmt", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      G.SetPage(5)
      T.Net.Handle("AvailableTransmogs:4:405:12:start")
      advance()
      feed(T, CHEST, { 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012 },
         { bucket = 405 })
      advance()
      H.eq(G.mode, "GRID")
      H.eq(G.pages, 2, "12 + Original + Verborgen = 14 Kacheln")
      H.eq(G.page, 2)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Anderer angelegter Gegenstand = andere Liste: zurueck auf Seite 1; gleicher Gegenstand nicht", function()
      local d = baseItems()
      put(d, 1005, "Chest of Mail", 4, 200, "Armor", "Mail", "INVTYPE_CHEST", "ChestM")
      local T = boot({ items = d })
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      G.SetPage(3)
      -- EQUIPMENT_CHANGED ohne Wechsel (Itemdaten des angelegten Gegenstands trafen ein)
      T.Events.Fire("EQUIPMENT_CHANGED", CHEST)
      advance()
      H.eq(G.page, 3, "kein echter Wechsel: Seite bleibt")
      -- echter Wechsel
      mock.world.equipment[5] = 1005
      mock.Fire("PLAYER_EQUIPMENT_CHANGED", 5)
      advance(0.7)
      feed(T, CHEST, CHEST_LIST, { bucket = 403 })
      advance()
      H.eq(G.mode, "GRID")
      H.eq(G.page, 1, "neue Liste beginnt vorn")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Klick auf die letzte Kachel einer Seite: nichts rutscht, die Kachel und die Seite bleiben", function()
      -- (frueher erschien die Original-Kachel erst bei der ersten Auswahl und schob alles um eine
      -- Stelle: die Kachel wanderte auf die naechste Seite und die Seite musste ihr folgen)
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      G.SetPage(3)
      -- letzte Zelle der Seite
      local cells = shownCells(G)
      local last = cells[#cells]
      local id = last.itemId
      local idx = tileIndexOf(T, G, id)
      H.eq(idx, 3 * 10, "letzte Kachel der Seite 3")
      local before = tags(G)
      mock.Click(last)
      advance()
      H.eq(tileIndexOf(T, G, id), 30, "die Kachel bleibt an ihrer Stelle")
      H.eq(G.page, 3, "die Seite bleibt")
      H.deepEq(tags(G), before)
      local found
      for _, c in ipairs(shownCells(G)) do
         if c.itemId == id then found = c end
      end
      H.truthy(found, "die gewaehlte Kachel ist sichtbar")
      H.truthy(found.selected)
      -- Verwerfen: wieder nichts bewegt
      mock.Click(found)
      advance()
      H.eq(tileIndexOf(T, G, id), 30)
      found = nil
      for _, c in ipairs(shownCells(G)) do
         if c.itemId == id then found = c end
      end
      H.truthy(found, "auch nach dem Verwerfen sichtbar")
      H.eq(G.page, 3)
      H.deepEq(tags(G), before)
      H.falsy(found.selected)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Auswahl mitten auf der Seite aendert die Seite nicht; Original/Verborgen auf Seite 1 auch nicht", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      G.SetPage(2)
      local mid = shownCells(G)[4]
      local midId = mid.itemId
      mock.Click(mid)
      advance()
      H.eq(G.page, 2)
      H.truthy(onPage(G, tileIndexOf(T, G, midId) or 0), "die gewaehlte Kachel steht weiter auf der Seite")
      -- Seite 1: Original waehlen/verwerfen, Verborgen waehlen
      G.SetPage(1)
      local orig = shownCells(G)[1]
      H.eq(orig.kind, "original")
      mock.Click(orig)    -- Baseline 0, Auswahl vorhanden: Original = Auswahl verwerfen
      advance()
      H.eq(G.page, 1)
      H.falsy(T.State.HasPending(CHEST))
      local hide = shownCells(G)[2]
      H.eq(hide.kind, "hidden")
      mock.Click(hide)               -- Verborgen waehlen: auch das schiebt nichts
      advance()
      H.eq(G.page, 1)
      H.eq(T.State.Wanted(CHEST), HIDDEN)
      H.eq(shownCells(G)[1].kind, "original", "Original steht weiter vorn")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Fenstergroesse aendern: die erste sichtbare Kachel der Seite bleibt sichtbar", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      G.SetPage(3)                       -- 10 je Seite: Kacheln 21..30
      local first = (G.page - 1) * G.perPage + 1
      for _, sz in ipairs({ { 398, 400 }, { 880, 560 }, { 300, 250 }, { 500, 400 } }) do
         G.Layout(sz[1], sz[2])
         advance()
         H.truthy(onPage(G, first), string.format("%dx%d: Kachel %d auf Seite %d (%d je Seite)",
            sz[1], sz[2], first, G.page, G.perPage))
         first = (G.page - 1) * G.perPage + 1
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Vorschaugroesse aendern: die Seite behaelt ihre erste Kachel", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      G.SetPage(3)
      local first = (G.page - 1) * G.perPage + 1
      T.DB.Set("previewSize", 1.5)
      advance()
      H.truthy(onPage(G, first), "1.5: Kachel " .. first .. " auf Seite " .. G.page)
      first = (G.page - 1) * G.perPage + 1
      T.DB.Set("previewSize", 0.8)
      advance()
      H.truthy(onPage(G, first), "0.8: Kachel " .. first .. " auf Seite " .. G.page)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ladezustand ohne bekannte Gesamtzahl: kein '0 / 0', kein Balken", function()
      local T = boot({ feed = false })
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      H.eq(G.mode, "LOADING")
      H.eq(msg(G), "Loading appearances...")
      H.falsy(G.msgBar:IsShown())
      -- sobald der Strom die Gesamtzahl nennt: Zahlen und Balken
      T.Net.Handle("AvailableTransmogs:4:405:40:start")
      advance()
      H.eq(msg(G), "Loading appearances... 0 / 40")
      H.truthy(G.msgBar:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("SetPage im unsichtbaren Zustand wird gemerkt und beim Zeigen geklemmt", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      T.parent:Hide()
      G.SetPage(4)
      H.eq(G.page, 4)
      T.parent:Show()
      H.eq(G.page, 4)
      H.eq(#shownCells(G), 10)
      T.parent:Hide()
      G.SetPage(99)
      T.parent:Show()
      H.eq(G.page, 5, "auf die letzte Seite geklemmt")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zelle unter der Maus verschwindet: Tooltip geht mit, kein Rest-Hover", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local cells = shownCells(G)
      local c10 = cells[#cells]
      mock.Enter(c10)
      H.truthy(GameTooltip:IsShown())
      H.eq(GameTooltip:GetOwner(), c10)
      -- Filter: nur noch ein Treffer, die Zelle faellt weg
      T.Filter.SetSearch("Look 11")
      advance()
      H.falsy(c10:IsShown())
      H.falsy(c10.hover, "Hover zurueckgesetzt")
      H.falsy(GameTooltip:IsShown() and GameTooltip:GetOwner() == c10, "Tooltip der versteckten Zelle weg")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Favoriten ueberleben das Neuladen (SavedVariables): Stern beim naechsten Start", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local cell = shownCells(G)[3]   -- erster Eintrag (davor Original und Verborgen)
      local id = cell.itemId
      H.truthy(id)
      mock.Click(cell, "RightButton")
      H.eq(T.DB.char.favorites[id], true)
      local saved = T.Util.CopyTable(T.DB.char)
      -- neue Sitzung mit den gespeicherten Daten
      local T2 = boot({ globals = { TransmogDB = saved } })
      local G2 = T2.UI.Grid
      G2.SetSlot(CHEST)
      local found
      for page = 1, G2.pages do
         G2.SetPage(page)
         for _, c in ipairs(shownCells(G2)) do
            if c.itemId == id then found = c end
         end
         if found then break end
      end
      H.truthy(found, "Kachel gefunden")
      H.truthy(found.favorite, "Favorit gespeichert")
      H.truthy(found.ov.star:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Erneuter Aufruf im Aufbau (Re-Entrancy): Refresh aus Filter.Compute heraus bleibt konsistent", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local orig = T.Filter.Compute
      local depth = 0
      T.Filter.Compute = function(...)
         depth = depth + 1
         if depth == 1 then G.Refresh() end   -- verschachtelt
         return orig(...)
      end
      G.SetPage(2)
      T.Filter.Compute = orig
      H.eq(G.mode, "GRID")
      H.eq(G.page, 2)
      local entries = T.Filter.Compute(CHEST)
      H.deepEq(tags(G), ids(entries, 9, 18), "Seite 2: Eintraege 9..18 (Seite 1 = 2 synthetische + 8)")
      for _, c in ipairs(shownCells(G)) do
         H.eq(c.model:GetParent(), c)
         H.eq(mock.Model(c.model).tried[#mock.Model(c.model).tried], c.itemId)
      end
      H.deepEq(H.takeErrors(), {})
   end)
   -- =========================================================================
   H.section("Nachpruefung: echtes Fenster, Sprachen, Groessen (Fixtures + Layout-Pruefung)")
   -- =========================================================================

   local Fixtures = require("fixtures")
   local LayoutTool = require("layout")

   -- sehr lange deutsche Texte (so lang wie ein Uebersetzer sie schreiben koennte)
   local LONG_DE = {
      GRID_NO_SLOT = "Waehle einen Ausruestungsplatz auf der linken Seite des Fensters aus",
      GRID_NO_SLOT_HINT = "Waehle links einen Platz, um die verfuegbaren Aussehen durchzublaettern und eines auszuwaehlen.",
      GRID_EMPTY_SLOT = "In diesem Platz ist nichts angelegt, deshalb gibt es nichts zu veraendern",
      GRID_EMPTY_SLOT_HINT = "Lege einen Gegenstand an, damit die dazu passenden Aussehen angezeigt werden koennen.",
      GRID_NEVER = "Dieser Gegenstand kann nicht transmogrifiziert werden, auch nicht mit Zusatzregeln",
      GRID_NEVER_HINT = "Ringe, Halsketten, Schmuckstuecke und Reliktgegenstaende koennen ihr Aussehen nicht aendern.",
      GRID_ABSENT = "Das Transmogrifikationsmodul des Servers antwortet leider nicht auf Anfragen",
      GRID_ABSENT_HINT = "Die Aussehen werden vom Server geladen. Stelle sicher, dass mod-transmog-plus installiert und aktiv ist.",
      GRID_NO_ITEMS = "Noch keine passenden Aussehen vorhanden, die du verwenden koenntest",
      GRID_NO_ITEMS_HINT = "Sie werden freigeschaltet, sobald du Gegenstaende erhaeltst, die in diesen Platz passen koennen.",
      GRID_FILTERED = "Keine Aussehen entsprechen den aktuell eingestellten Filtern der Leiste",
      GRID_FILTERED_HINT = "Aendere oder setze die Filter oben zurueck, um mehr Aussehen zu sehen und auswaehlen zu koennen.",
      GRID_RESET_FILTERS = "Filter komplett zuruecksetzen",
      GRID_LOADING = "Aussehen werden geladen... %s / %s",
      GRID_LOADING_PLAIN = "Aussehen werden geladen...",
      GRID_LOADING_HINT = "Gegenstandsdaten werden beim Server angefordert und im Zwischenspeicher abgelegt.",
      GRID_PAGE = "Seite %d / %d", GRID_COUNT = "%s von %s Aussehen insgesamt",
      GRID_COUNT_FILTERED = "%s von %s Aussehen insgesamt (gefiltert)",
      GRID_NEW = "NEUES", GRID_ORIGINAL = "Urspruenglich", GRID_HIDDEN = "Verborgen",
   }

   -- Befunde der Layout-Pruefung unterhalb des rechten Panels (Filterleiste + Raster),
   -- ohne die absichtlich abgeschnittenen Kachelnamen
   local function rightProblems(T)
      local ents = LayoutTool.Rects(TransmogWindow)
      local problems = LayoutTool.Check(ents, { truncateOk = { "/name$" } })
      local out = {}
      for _, p in ipairs(problems) do
         if p.path:find("/right/", 1, true) and p.severity ~= "info" then
            out[#out + 1] = p.severity .. " " .. p.kind .. " " .. p.path .. " -- " .. tostring(p.message)
         end
      end
      return out, ents
   end

   -- Fenster am NPC mit dem Fixtures-Katalog und echtem Server
   local function realWindow(opts)
      opts = opts or {}
      local T = Fixtures.Boot(H, { locale = opts.locale or "enUS", screen = { w = 1366, h = 768 },
         cacheItems = opts.cacheItems })
      if not opts.mute then Fixtures.ServerHello(T) end
      Fixtures.ServerAutoReply(T, { mute = opts.mute })
      T.DB.Set("scale", 1.0)
      if opts.long then T.Locale.Add("deDE", LONG_DE) end
      if opts.preview then
         T.UI.Window.Open({ fromNpc = false })   -- /transmog: der NPC-Gruss "Open" bliebe ein Lebenszeichen
      else
         Fixtures.OpenAtNpc(T)
      end
      return T
   end

   H.test("Echtes Fenster, lange deutsche Texte: Raster und Filterleiste ueberlappen/ueberragen nie (Groessen x Vorschau)", function()
      local T = realWindow({ locale = "deDE", long = true })
      T.Locale.Set("deDE")
      local W, G = T.UI.Window, T.UI.Grid
      local checked = 0
      for _, size in ipairs({ { 740, 520 }, { 880, 600 }, { 1280, 800 } }) do
         for _, f in ipairs({ 0.8, 1.0, 1.25, 1.5 }) do
            T.DB.Set("width", size[1])
            T.DB.Set("height", size[2])
            T.DB.Set("previewSize", f)
            Fixtures.Settle(T, 0.4)
            for _, slot in ipairs({ 0, 4, 15 }) do
               W.SelectSlot(slot)
               Fixtures.Settle(T, 0.4)
               local label = string.format("%dx%d f=%s slot=%d", size[1], size[2], f, slot)
               H.eq(G.mode, "GRID", label)
               local problems = rightProblems(T)
               H.deepEq(problems, {}, label)
               checked = checked + 1
            end
         end
      end
      H.eq(checked, 36)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Echtes Fenster, lange Meldungen in jedem Zustand: Text bleibt in der Rasterflaeche", function()
      local T = realWindow({ locale = "deDE", long = true })
      T.Locale.Set("deDE")
      local W, G = T.UI.Window, T.UI.Grid
      for _, size in ipairs({ { 740, 520 }, { 880, 600 } }) do
         for _, f in ipairs({ 1.0, 1.5 }) do
            T.DB.Set("width", size[1])
            T.DB.Set("height", size[2])
            T.DB.Set("previewSize", f)
            Fixtures.Settle(T, 0.4)
            local function check(label, mode)
               Fixtures.Settle(T, 0.3)
               local label2 = string.format("%dx%d f=%s %s", size[1], size[2], f, label)
               H.eq(G.mode, mode, label2)
               local problems, ents = rightProblems(T)
               H.deepEq(problems, {}, label2)
               -- jedes sichtbare Meldungsteil liegt ganz in der Rasterflaeche
               local raster = LayoutTool.Find(ents, G.raster)
               for _, part in ipairs({ G.msgTitle, G.msgHint, G.msgBar, G.resetButton }) do
                  if part:IsShown() then
                     local e = LayoutTool.Find(ents, part)
                     H.truthy(e and raster and e.y >= raster.y - 0.5 and e.y + e.h <= raster.y + raster.h + 0.5,
                        label2 .. ": Meldung innerhalb der Rasterflaeche")
                  end
               end
            end
            W.SelectSlot(nil)
            check("kein Slot", "NO_SLOT")
            Fixtures.Unequip(T, 18)
            W.SelectSlot(18)
            check("leerer Slot", "EMPTY")
            Fixtures.Equip(T, 18, "e_tabard")
            W.SelectSlot(4)
            check("Raster", "GRID")
            T.Filter.SetSearch("zzzzz")
            check("gefiltert", "FILTERED")
            T.State.Select(4, 0)
            T.State.Select(4, T.Filter.Compute(4)[1] and T.Filter.Compute(4)[1].id or 0)
            check("gefiltert + Original", "FILTERED")
            T.Filter.SetSearch("")
            T.State.DiscardAll()
         end
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Echtes Fenster, Server stumm: Meldung ohne Zellen, spaetere Antwort loest sie auf", function()
      local T = realWindow({ mute = true, preview = true })
      local G = T.UI.Grid
      Fixtures.Settle(T, 9.5)
      T.UI.Window.SelectSlot(4)
      Fixtures.Settle(T, 0.5)
      H.eq(G.mode, "ABSENT")
      H.eq(#shownCells(G), 0)
      H.truthy(msg(G))
      -- der Server meldet sich doch: Strom einspielen
      local ids = Fixtures.List(T, 4)
      feed(T, 4, ids, { bucket = 405 })
      Fixtures.Settle(T, 0.5)
      H.eq(G.mode, "GRID")
      H.truthy(#shownCells(G) > 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Echtes Fenster: Klick waehlt, Anwenden mit Serverantwort markiert die Kachel als angewendet", function()
      local T = realWindow()
      local W, G, State = T.UI.Window, T.UI.Grid, T.State
      W.SelectSlot(0)
      Fixtures.Settle(T, 0.6)
      H.eq(G.mode, "GRID")
      -- eine Kachel, die weder angewendet noch gewaehlt ist
      local pick
      for _, c in ipairs(shownCells(G)) do
         if c.kind == "item" and not c.applied then pick = c break end
      end
      H.truthy(pick, "waehlbare Kachel")
      local id = pick.itemId
      mock.Click(pick)
      Fixtures.Settle(T, 0.5)
      H.eq(State.Wanted(0), id)
      local sel
      for _, c in ipairs(shownCells(G)) do
         if c.itemId == id then sel = c end
      end
      H.truthy(sel and sel.selected, "gewaehlte Kachel ist markiert")
      H.eq(shownCells(G)[1].kind, "original")
      -- anwenden (Kosten antwortet der Server)
      H.truthy(State.CanApply(), "anwendbar")
      mock.Click(TransmogWindow.btnApply)
      Fixtures.Settle(T, 1.0)
      H.falsy(State.HasPending(0), "nichts mehr ausstehend")
      H.eq(State.Applied(0), id)
      local app
      for _, c in ipairs(shownCells(G)) do
         if c.itemId == id then app = c end
      end
      H.truthy(app and app.applied and app.ov.check:IsShown(), "angewendet: Haken")
      H.falsy(app.selected)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Echtes Fenster, Itemdaten unbekannt: Fortschritt, dann Raster; Slotwechsel waehrend des Ladens", function()
      local T = realWindow({ cacheItems = false })
      local W, G = T.UI.Window, T.UI.Grid
      W.SelectSlot(0)
      Fixtures.Settle(T, 0.05)
      H.truthy(G.mode == "LOADING" or G.mode == "GRID")
      -- mitten im Laden den Slot wechseln und zurueck: kein Fehler, am Ende Raster
      W.SelectSlot(4)
      W.SelectSlot(0)
      Fixtures.Settle(T, 3)
      H.eq(G.mode, "GRID")
      H.truthy(#shownCells(G) > 0)
      H.deepEq(H.takeErrors(), {})
   end)
   -- SetUnit-Aufrufe je Zelle (Index) im echten Raster
   local function unitCountsOf(G)
      local out = {}
      for i, c in ipairs(G.cells) do
         out[i] = c.model and mock.Model(c.model).count("SetUnit") or 0
      end
      return out
   end

   -- Jede sichtbare Zelle mit Modell hat es seit "before" genau einmal neu angekleidet (SetUnit + 1),
   -- alle anderen blieben unberuehrt. Rueckgabe: Zahl der neu angekleideten Zellen.
   local function assertRedressedOnce(G, before, label)
      local after = unitCountsOf(G)
      local shown, redressed = {}, 0
      for _, c in ipairs(shownCells(G)) do shown[c.index] = c end
      for i = 1, #G.cells do
         local c = G.cells[i]
         if shown[i] and c.model then
            H.eq(after[i], (before[i] or 0) + 1, label .. ": Zelle " .. i .. " genau einmal neu angekleidet")
            H.truthy(c.model:IsShown(), label .. ": Zelle " .. i .. " zeigt ihr Modell")
            redressed = redressed + 1
         else
            H.eq(after[i], before[i] or 0, label .. ": Zelle " .. i .. " (nicht sichtbar) unberuehrt")
         end
      end
      return redressed
   end

   H.test("Echtes Fenster: Reiterwechsel Items -> Outfits -> Items kleidet jedes sichtbare Zellmodell genau einmal neu an", function()
      local T = realWindow()
      local W, G = T.UI.Window, T.UI.Grid
      W.SelectSlot(0)
      Fixtures.Settle(T, 3)
      H.eq(G.mode, "GRID")
      local opened = unitCountsOf(G)
      local n = 0
      for _, c in ipairs(shownCells(G)) do
         if c.model then n = n + 1 end
      end
      H.truthy(n > 1, "das Raster hat Modelle geladen")
      local watch = watchSetParent()

      W.SetTab("outfits")
      Fixtures.Settle(T, 0.5)
      H.falsy(G.frame:IsShown(), "Raster verborgen")
      local hiddenCounts = unitCountsOf(G)
      H.deepEq(hiddenCounts, opened, "verborgen: kein Ankleiden")

      W.SetTab("items")
      Fixtures.Settle(T, 1.0)
      H.truthy(G.frame:IsShown())
      local redressed = assertRedressedOnce(G, opened, "nach dem Reiterwechsel")
      H.eq(redressed, n, "alle sichtbaren Modelle")
      -- und keines hat die Zelle gewechselt
      for i, c in ipairs(shownCells(G)) do
         if c.model then H.eq(c.model:GetParent(), c) end
      end
      H.eq(watch.count, 0, "kein SetParent")

      -- zweiter Wechsel: wieder genau einmal
      local second = unitCountsOf(G)
      W.SetTab("outfits")
      Fixtures.Settle(T, 0.5)
      W.SetTab("items")
      Fixtures.Settle(T, 1.0)
      assertRedressedOnce(G, second, "zweiter Reiterwechsel")
      watch.stop()
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Echtes Fenster: Schliessen und Wiederoeffnen kleidet jedes sichtbare Zellmodell genau einmal neu an", function()
      local T = realWindow()
      local W, G = T.UI.Window, T.UI.Grid
      W.SelectSlot(0)
      Fixtures.Settle(T, 3)
      H.eq(G.mode, "GRID")
      local opened = unitCountsOf(G)
      W.Close()
      Fixtures.Settle(T, 0.5)
      H.falsy(W.IsShown())
      H.deepEq(unitCountsOf(G), opened, "geschlossen: kein Ankleiden")
      W.Open({ fromNpc = false })
      Fixtures.Settle(T, 1.0)
      H.truthy(W.IsShown())
      H.eq(G.mode, "GRID")
      local n = assertRedressedOnce(G, opened, "nach dem Wiederoeffnen")
      H.truthy(n > 1)
      -- noch einmal: ESC und /transmog
      local second = unitCountsOf(G)
      mock.Escape()
      Fixtures.Settle(T, 0.3)
      H.falsy(W.IsShown())
      mock.Slash("/transmog")
      Fixtures.Settle(T, 1.0)
      H.truthy(W.IsShown())
      assertRedressedOnce(G, second, "ESC und /transmog")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Echtes Fenster: Schliessen mit Reiter Outfits, Wiederoeffnen dort, Zurueck zu Items: einmal neu angekleidet", function()
      local T = realWindow()
      local W, G = T.UI.Window, T.UI.Grid
      W.SelectSlot(0)
      Fixtures.Settle(T, 3)
      local opened = unitCountsOf(G)
      W.SetTab("outfits")
      Fixtures.Settle(T, 0.3)
      W.Close()
      Fixtures.Settle(T, 0.3)
      W.Open({ fromNpc = false })    -- merkt sich den Reiter Outfits
      Fixtures.Settle(T, 0.5)
      H.eq(W.GetTab(), "outfits")
      H.falsy(G.frame:IsShown())
      H.deepEq(unitCountsOf(G), opened, "das verborgene Raster laedt nichts")
      W.SetTab("items")
      Fixtures.Settle(T, 1.0)
      assertRedressedOnce(G, opened, "Items nach Outfits")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Echtes Fenster: Reiter Items anklicken, waehrend er aktiv ist, und erneutes Oeffnen bei offenem Fenster kleiden nicht neu an", function()
      local T = realWindow()
      local W, G = T.UI.Window, T.UI.Grid
      W.SelectSlot(0)
      Fixtures.Settle(T, 3)
      H.eq(G.mode, "GRID")
      local opened = unitCountsOf(G)
      -- Klick auf den schon aktiven Reiter
      mock.Click(TransmogWindow.tabItems)
      Fixtures.Settle(T, 1.0)
      H.deepEq(unitCountsOf(G), opened, "aktiver Reiter angeklickt: nichts neu angekleidet")
      -- noch einmal oeffnen (z. B. /transmog-Befehl ueber den Gossip, waehrend das Fenster offen ist)
      W.Open({ fromNpc = true })
      Fixtures.Settle(T, 1.0)
      H.truthy(W.IsShown())
      H.deepEq(unitCountsOf(G), opened, "Open bei offenem Fenster: nichts neu angekleidet")
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Nachpruefung: Auswahl, Randfaelle, Ladezustaende")
   -- =========================================================================

   H.test("Verborgen nur gewaehlt (nichts angewendet): Kachel ist 'ausgewaehlt', nicht 'angewendet'", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local hide = shownCells(G)[2]   -- hinter der Original-Kachel
      H.eq(hide.kind, "hidden")
      mock.Click(hide)
      advance()
      hide = nil
      for _, c in ipairs(shownCells(G)) do
         if c.kind == "hidden" then hide = c end
      end
      H.truthy(hide.selected)
      H.falsy(hide.applied, "noch nicht angewendet: kein Haken")
      H.falsy(hide.ov.check:IsShown())
      -- ist es angewendet UND etwas anderes gewaehlt: angewendet, nicht ausgewaehlt
      T.State.Discard(CHEST)
      T.Net.Handle("TransmogStatus:1:4," .. HIDDEN)
      T.State.Select(CHEST, 2005)
      advance()
      for _, c in ipairs(shownCells(G)) do
         if c.kind == "hidden" then hide = c end
      end
      H.truthy(hide.applied)
      H.falsy(hide.selected)
      H.truthy(hide.ov.check:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Klick auf eine andere Kachel bei vorhandener Auswahl waehlt diese (statt zu verwerfen)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local cells = shownCells(G)
      local a, b = cells[3].itemId, cells[4].itemId   -- die ersten beiden Eintraege
      H.truthy(a and b)
      mock.Click(cells[3])
      advance()
      H.eq(T.State.Wanted(CHEST), a)
      mock.Click(findCell(G, b))
      H.eq(T.State.Wanted(CHEST), b, "die zweite Kachel ersetzt die Auswahl")
      H.truthy(T.State.HasPending(CHEST))
      advance()
      local selected = 0
      for _, c in ipairs(shownCells(G)) do
         if c.selected then
            selected = selected + 1
            H.eq(c.itemId, b)
         end
      end
      H.eq(selected, 1)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Shift-Klick auf Verborgen waehlt Verborgen (es gibt keinen Link)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local hide = shownCells(G)[2]
      H.eq(hide.kind, "hidden")
      mock.Click(hide, "LeftButton", { shift = true })
      H.eq(#mock.chatInserts, 0)
      H.eq(T.State.Wanted(CHEST), HIDDEN)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout: Zeilen und Spalten genau an der Grenze (passt genau / ein Pixel zu wenig)", function()
      local T = boot()
      local G = T.UI.Grid
      -- zwei Zeilen: 30 (Leiste) + 126 + 6 + 126 = 288
      G.Layout(500, 288)
      H.eq(G.rows, 2)
      G.Layout(500, 287)
      H.eq(G.rows, 1)
      -- drei Zeilen: 30 + 3*126 + 2*6 = 420
      G.Layout(500, 420)
      H.eq(G.rows, 3)
      -- vier Spalten: 4*92 + 3*6 = 386
      G.Layout(386, 400)
      H.eq(G.cols, 4)
      G.Layout(385, 400)
      H.eq(G.cols, 3)
      -- die Zellen der letzten Zeile liegen ganz im Raster
      G.SetSlot(CHEST)
      G.Layout(500, 288)
      for _, c in ipairs(shownCells(G)) do
         local _, _, _, x, y = c:GetPoint(1)
         H.truthy(x >= 0 and x + c:GetWidth() <= 500 + 1e-6)
         H.truthy(-y + c:GetHeight() <= G.raster:GetHeight() + 1e-6, "Zelle im Raster")
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Aufgegebene Items: auch nach der 60-s-Wiederholung kein erneuter Ladezustand", function()
      local T = boot({ cache = false })
      local G = T.UI.Grid
      local list = {}
      for i = 1, 36 do list[i] = 2000 + i end
      for i = 1, 4 do list[#list + 1] = 9000 + i end
      feed(T, CHEST, list, { bucket = 405 })
      G.SetSlot(CHEST)
      mock.Advance(25, 0.5)          -- aufgegeben nach 20 s
      advance()
      H.eq(G.mode, "GRID")
      -- Ruhe, bis Items die Wiederholung zulaesst; der Spieler blaettert
      mock.Advance(70, 0.5)
      G.SetPage(2)
      H.eq(G.mode, "GRID", "kein Ladezustand durch die Wiederholung der aufgegebenen Items")
      H.eq(G.page, 2)
      H.truthy(#shownCells(G) > 0)
      G.SetPage(1)
      H.eq(G.mode, "GRID")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Liste waechst um unbekannte Items: das Raster bleibt stehen, die neuen kommen nach", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      H.eq(G.mode, "GRID")
      -- fuenf zusaetzliche Aussehen, die der Client noch nie gesehen hat
      local list = {}
      for i = 1, 20 do list[i] = 2000 + i end
      for i = 1, 5 do
         local id = 7000 + i
         mock.items[id] = {
            name = "Fresh Look " .. i, quality = 3, ilvl = 150, class = "Armor", subclass = "Plate",
            equipLoc = "INVTYPE_CHEST", icon = "Interface\\Icons\\Fresh" .. i,
         }
         list[#list + 1] = id
      end
      feed(T, CHEST, list, { bucket = 405 })
      advance(0.1)
      -- bereits Sichtbares verschwindet nicht hinter einem Ladebalken
      H.eq(G.mode, "GRID")
      H.eq(G.stats.unresolved, 5)
      H.eq(G.stats.shown, 20)
      H.truthy(#shownCells(G) > 0)
      -- die Itemdaten laufen ein: alle 25 sind da
      mock.Advance(2, 0.1)
      H.eq(G.mode, "GRID")
      H.eq(G.stats.shown, 25)
      H.eq(G.stats.unresolved, 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Liste laedt sichtbar neu und bringt unbekannte Items mit: Ladezustand bis alles da ist", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      H.eq(G.mode, "GRID")
      local list = {}
      for i = 1, 20 do list[i] = 2000 + i end
      for i = 1, 5 do
         local id = 7100 + i
         mock.items[id] = {
            name = "Newer Look " .. i, quality = 3, ilvl = 150, class = "Armor", subclass = "Plate",
            equipLoc = "INVTYPE_CHEST", icon = "Interface\\Icons\\Newer" .. i,
         }
         list[#list + 1] = id
      end
      -- Strom beginnt (ein Zeichnen im Zwischenzustand), dann kommt der Rest
      T.Net.Handle("AvailableTransmogs:4:405:25:start")
      advance(0.1)
      H.eq(G.mode, "LOADING")
      local part = {}
      for i = 1, 20 do part[i] = tostring(list[i]) end
      T.Net.Handle("AvailableTransmogs:4:405:25:" .. table.concat(part, ":"))
      part = {}
      for i = 21, 25 do part[#part + 1] = tostring(list[i]) end
      T.Net.Handle("AvailableTransmogs:4:405:25:" .. table.concat(part, ":"))
      T.Net.Handle("AvailableTransmogs:4:405:25:end")
      advance(0.1)
      H.eq(G.mode, "LOADING", "neue Items sind noch unbekannt")
      H.eq(msg(G), "Loading appearances... 20 / 25")
      mock.Advance(2, 0.1)
      H.eq(G.mode, "GRID")
      H.eq(G.stats.shown, 25)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("COLLECTION_UPDATED (nicht Login-Sweep): NEU-Marke erscheint ohne weiteres Ereignis", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local cell = shownCells(G)[3]
      local id = cell.itemId
      H.falsy(cell.isNew)
      -- das Ereignis allein (kein Listenstrom, keine Itemdaten) muss die Anzeige nachziehen
      T.State.new[id] = true
      T.Events.Fire("COLLECTION_UPDATED", id)
      advance()
      local again
      for _, c in ipairs(shownCells(G)) do
         if c.itemId == id then again = c end
      end
      H.truthy(again and again.isNew)
      H.truthy(again.ov.newBg:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)
   -- =========================================================================
   H.section("Nachpruefung: Zusammenspiel von Filterleiste und Raster")
   -- =========================================================================

   -- Filterleiste ueber dem Raster (wie im Fenster), onChange-Zaehler in T.barChanges
   local function withBar(T)
      local parent = T.parent
      T.barChanges = 0
      local bar = T.UI.FilterBar.Create(parent, function() T.barChanges = T.barChanges + 1 end)
      bar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
      T.UI.FilterBar.Layout(500)
      T.UI.FilterBar.Refresh(CHEST)
      return T.UI.FilterBar
   end

   local function names(G)
      local out = {}
      for _, c in ipairs(shownCells(G)) do
         if c.kind == "item" then out[#out + 1] = c.tile.info.name end
      end
      return out
   end

   H.test("Suchfeld -> Raster: Tippen filtert entprellt, Seite springt auf 1, Zaehler stimmt", function()
      local T = boot()
      local G = T.UI.Grid
      local FB = withBar(T)
      G.SetSlot(CHEST)
      G.SetPage(3)
      mock.Type(FB.search, "Look 2")
      advance(0.1)
      H.eq(G.page, 3, "noch nicht uebernommen (Entprellung)")
      advance(0.3)
      H.eq(G.page, 1)
      H.eq(T.barChanges, 1)
      -- Begriffe: "look" und "2" (Namensteil): Look 02, 12, 20..29, 32 = 13 Treffer
      local want = 0
      for i = 1, CHEST_COUNT do
         if string.format("Look %02d", i):find("2", 1, true) then want = want + 1 end
      end
      H.eq(want, 13)
      H.eq(G.stats.shown, 13)
      H.eq(G.countText:GetText(), "13 of 40 appearances (filtered)")
      for _, n in ipairs(names(G)) do H.truthy(n:find("2", 1, true), n) end
      -- zusaetzlich eine Qualitaet ausblenden: beide Bedingungen gelten zugleich (UND)
      local q = T.Filter.Compute(CHEST)[1].quality
      mock.Click(FB.chips[q])
      advance()
      local entries, stats = T.Filter.Compute(CHEST)
      H.truthy(stats.shown < 13)
      H.truthy(stats.shown > 0)
      for _, e in ipairs(entries) do
         H.neq(e.quality, q)
         H.truthy(e.info.name:find("2", 1, true), e.info.name)
      end
      -- Zuruecksetzen ueber die Leiste: Feld leer, Chips normal, Raster komplett
      mock.Click(FB.resetButton)
      advance()
      H.eq(FB.search:GetText(), "")
      H.eq(G.stats.shown, 40)
      H.falsy(FB.chips[q].hiddenQuality)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Raster-Knopf 'Reset filters' leert auch das Suchfeld der Leiste", function()
      local T = boot()
      local G = T.UI.Grid
      local FB = withBar(T)
      G.SetSlot(CHEST)
      mock.Type(FB.search, "zzz-nothing")
      advance(0.4)
      H.eq(G.mode, "FILTERED")
      mock.Click(G.resetButton)
      advance()
      H.eq(G.mode, "GRID")
      H.eq(FB.search:GetText(), "")
      H.eq(T.Filter.search, "")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Sortierung ueber das Menue aendert die Reihenfolge im Raster und springt auf Seite 1", function()
      local T = boot()
      local G = T.UI.Grid
      local FB = withBar(T)
      G.SetSlot(CHEST)
      G.SetPage(2)
      mock.Click(FB.sortButton)
      local menu = rawget(_G, "TransmogMenuFrame")
      local row
      for _, b in ipairs(mock.Find(menu, "Button")) do
         if b:IsShown() and b.item and b.item.sortKey == "NAME" then row = b end
      end
      H.truthy(row)
      mock.Click(row)
      advance()
      H.eq(G.page, 1)
      local n = names(G)
      H.truthy(#n > 3)
      for i = 2, #n do
         H.truthy(n[i - 1] <= n[i], "nach Name aufsteigend: " .. n[i - 1] .. " <= " .. n[i])
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Favoriten-Chip der Leiste + Rechtsklick im Raster: Sterne erscheinen, Filter 'nur Favoriten' zeigt sie", function()
      local T = boot()
      local G = T.UI.Grid
      local FB = withBar(T)
      G.SetSlot(CHEST)
      local cells = shownCells(G)
      local a, b = cells[3].itemId, cells[5].itemId   -- Eintrag 1 und 3 (davor Original, Verborgen)
      H.truthy(a and b)
      mock.Click(cells[3], "RightButton")
      advance()
      mock.Click(findCell(G, b), "RightButton")
      advance()
      G.SetPage(1)
      mock.Click(FB.favChip)
      advance()
      H.eq(G.stats.shown, 2)
      local got = {}
      for _, c in ipairs(shownCells(G)) do
         if c.kind == "item" then
            got[c.itemId] = true
            H.truthy(c.ov.star:IsShown())
         end
      end
      H.truthy(got[a] and got[b])
      -- Favorit entfernen: verschwindet aus der Ansicht (Filter aktiv), Seite bleibt gueltig
      mock.Click(findCell(G, a), "RightButton")
      advance()
      H.eq(G.stats.shown, 1)
      H.eq(G.page, 1)
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Nachpruefung: Ankleidebudget, Namen, Zaehler, Symbol, Fokus")
   -- =========================================================================

   -- Sichtbare Zellen, deren Modell zu sehen ist
   local function dressedCount(G)
      local n = 0
      for _, c in ipairs(shownCells(G)) do
         if c.model and c.model:IsShown() then n = n + 1 end
      end
      return n
   end

   -- Jede sichtbare Item-Zelle zeigt entweder ihr eigenes Modell oder den Platzhalter
   -- (nie ein altes Modell unter dem Namen einer anderen Kachel).
   local function checkNoStaleModels(G, label)
      for i, c in ipairs(shownCells(G)) do
         if c.kind == "item" then
            if c.model and c.model:IsShown() then
               local m = mock.Model(c.model)
               H.eq(m.tried[#m.tried], c.itemId, label .. ": Zelle " .. i .. " zeigt ihr eigenes Aussehen")
               H.falsy(c.ov.placeholder:IsShown(), label .. ": Zelle " .. i .. " mit Modell ohne Platzhalter")
            else
               H.truthy(c.ov.placeholder:IsShown(), label .. ": Zelle " .. i .. " ohne Modell: Platzhalter")
               H.eq(c.ov.name:GetText(), c.tile.info.name, label .. ": Name steht schon")
               H.truthy(c.ov.stripe:IsShown(), label .. ": Streifen steht schon")
            end
         end
      end
   end

   H.test("Ankleidebudget: ein Zeichenvorgang laedt hoechstens 16 Modelle, der Rest folgt in Schritten", function()
      local T = boot()
      local G = T.UI.Grid
      G.Layout(1000, 700)        -- 10 x 5 = 50 Zellen: Original + Verborgen + 40 Eintraege auf einer Seite
      H.eq(G.perPage, 50)
      G.SetSlot(CHEST)
      H.eq(#shownCells(G), 42)
      H.eq(modelCalls(G, "SetUnit"), 16, "erster Schritt: genau das Budget")
      H.eq(modelCalls(G, "TryOn"), 16)
      H.eq(dressedCount(G), 16)
      checkNoStaleModels(G, "Schritt 1")
      -- der Rest kommt von allein, jedes Modell genau einmal (40 Eintraege + Original)
      advance(0.5)
      H.eq(modelCalls(G, "SetUnit"), 41, "jedes Modell genau einmal angekleidet")
      H.eq(dressedCount(G), 41)
      checkNoStaleModels(G, "fertig")
      mock.Advance(20, 0.5)
      H.eq(T.Util.TimerCount(), 0, "kein Rest-Timer nach dem letzten Schritt")
      H.eq(#mock.UpdateFrames(), 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ankleidebudget: Seitenwechsel im grossen Fenster laesst kein altes Modell unter neuem Namen stehen", function()
      local T = boot({ previewSize = 0.8 })
      local G = T.UI.Grid
      G.Layout(398, 452)         -- 5 x 4 = 20 Zellen je Seite
      H.eq(G.perPage, 20)
      G.SetSlot(CHEST)           -- Seite 1: Original, Verborgen + 18 Eintraege (fast alle in einem Schritt)
      advance(0.5)
      H.eq(dressedCount(G), 19)
      clearModelCalls(G)
      G.SetPage(2)               -- 20 neue Eintraege
      H.eq(modelCalls(G, "SetUnit"), 16, "Seitenwechsel: hoechstens das Budget")
      H.eq(#shownCells(G), 20)
      checkNoStaleModels(G, "Seite 2, Schritt 1")
      advance(0.5)
      H.eq(modelCalls(G, "SetUnit"), 20, "Seite 2: jeder Eintrag genau einmal")
      checkNoStaleModels(G, "Seite 2 fertig")
      -- zurueck: wieder in Schritten, wieder ohne Reste
      clearModelCalls(G)
      G.SetPage(1)
      H.truthy(modelCalls(G, "SetUnit") <= 16)
      checkNoStaleModels(G, "Seite 1, Schritt 1")
      advance(0.5)
      H.eq(dressedCount(G), 19)
      checkNoStaleModels(G, "Seite 1 fertig")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ankleidebudget: Weiterblaettern verwirft den Rest der alten Seite (kein Laden fuer Unsichtbares)", function()
      local T = boot({ previewSize = 0.8 })
      local G = T.UI.Grid
      G.Layout(398, 452)
      G.SetSlot(CHEST)
      advance(0.5)
      clearModelCalls(G)
      G.SetPage(2)               -- 16 von 20 angekleidet, 4 fehlen noch
      H.eq(modelCalls(G, "SetUnit"), 16)
      G.SetPage(3)               -- Seite 3: 42 - 40 = zwei Eintraege
      advance(0.5)
      H.eq(modelCalls(G, "SetUnit"), 18, "nur die zwei Eintraege der neuen Seite kamen dazu")
      H.eq(#shownCells(G), 2)
      checkNoStaleModels(G, "Seite 3")
      mock.Advance(20, 0.5)
      H.eq(T.Util.TimerCount(), 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ankleidebudget: Rebuild und Layout in Schritten, Unsichtbar laedt nichts nach", function()
      local T = boot()
      local G = T.UI.Grid
      G.Layout(1000, 700)
      G.SetSlot(CHEST)
      advance(0.5)
      H.eq(dressedCount(G), 41, "40 Eintraege + Original")
      clearModelCalls(G)
      G.Rebuild()
      H.eq(modelCalls(G, "SetUnit"), 16, "Rebuild: hoechstens das Budget je Vorgang")
      checkNoStaleModels(G, "Rebuild")
      -- Fenster zu: die Fortsetzung laedt keine Modelle fuer ein verborgenes Raster
      T.parent:Hide()
      advance(0.5)
      H.eq(modelCalls(G, "SetUnit"), 16, "unsichtbar: nichts nachgeladen")
      -- beim Zeigen verlieren die Modelle im Client ihren Zustand: ALLE werden neu angekleidet
      -- (auch die 16 des Rebuilds), in Schritten, jedes genau einmal
      clearModelCalls(G)
      T.parent:Show()
      H.eq(modelCalls(G, "SetUnit"), 16, "beim Zeigen: erster Schritt = Budget")
      advance(0.5)
      H.eq(modelCalls(G, "SetUnit"), 41, "beim Zeigen: alle Modelle neu, jedes genau einmal")
      for _, c in ipairs(shownCells(G)) do
         if c.model then H.eq(mock.Model(c.model).count("SetUnit"), 1, "Zelle " .. c.index .. " genau einmal") end
      end
      H.eq(dressedCount(G), 41)
      checkNoStaleModels(G, "nach dem Zeigen")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ankleidebudget: Meldung statt Raster bricht die Fortsetzung ab", function()
      local T = boot()
      local G = T.UI.Grid
      G.Layout(1000, 700)
      G.SetSlot(CHEST)
      H.eq(modelCalls(G, "SetUnit"), 16)
      G.SetSlot(nil)             -- "Select an equipment slot": keine Zellen mehr
      H.eq(#shownCells(G), 0)
      mock.Advance(20, 0.5)
      H.eq(T.Util.TimerCount(), 0, "kein Timer der Fortsetzung")
      H.eq(modelCalls(G, "SetUnit"), 16, "kein weiteres Laden")
      H.deepEq(H.takeErrors(), {})
   end)

   -- Fuer die Namen: lange (auch deutsche) Namen, ein kurzer
   local function nameItems()
      local d = baseItems()
      put(d, 2001, "Beinkleider des Sturmbringers", 4, 150, "Armor", "Plate", "INVTYPE_CHEST", "Look1")
      put(d, 2002, "Großhelm des unermüdlichen Hüters", 4, 150, "Armor", "Plate", "INVTYPE_CHEST", "Look2")
      put(d, 2003, "Kapuze", 3, 150, "Armor", "Plate", "INVTYPE_CHEST", "Look3")
      put(d, 2004, "Gamaschen des Nachtfalken", 3, 150, "Armor", "Plate", "INVTYPE_CHEST", "Look4")
      return d
   end

   H.test("Namen: zu lange Namen enden auf '...' und passen in die Zeile, kurze bleiben unveraendert", function()
      for _, f in ipairs({ 0.8, 1.0, 1.25 }) do
         local T = boot({ items = nameItems(), previewSize = f })
         local G = T.UI.Grid
         G.Layout(900, 500)
         G.SetSlot(CHEST)
         advance(0.5)
         -- Messfeld wie das des Rasters (GameFontHighlightSmall, ohne feste Breite)
         local meas = G.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
         local function width(text)
            meas:SetText(text)
            return meas:GetStringWidth()
         end
         local maxW = math.max(8, G.cellW - 6) - 1
         local cut, kept = 0, 0
         for _, c in ipairs(shownCells(G)) do
            if c.kind == "item" then
               local name, text = c.tile.info.name, c.ov.name:GetText()
               if width(name) <= maxW then
                  kept = kept + 1
                  H.eq(text, name, "passt: unveraendert (" .. name .. ", f=" .. f .. ")")
               else
                  cut = cut + 1
                  H.eq(text:sub(-3), "...", "gekuerzt: Auslassungspunkte (" .. name .. ", f=" .. f .. ")")
                  local head = text:sub(1, -4)
                  H.eq(name:sub(1, #head), head, "Anfang des Namens (" .. name .. ")")
                  H.falsy(head:find("%s$"), "kein Leerzeichen vor den Punkten")
                  H.truthy(width(text) <= maxW, "passt in die Zeile: " .. text .. " " .. width(text) .. " <= " .. maxW)
                  -- so lang wie moeglich: das naechste Zeichen mehr passt nicht
                  local rest = name:sub(#head + 1):gsub("^%s+", "")
                  local nextChar = rest:match("^[%z\1-\127\194-\244][\128-\191]*")
                  H.truthy(nextChar, "es gibt ein weiteres Zeichen")
                  local fits = head .. name:sub(#head + 1):match("^%s*") .. nextChar .. "..."
                  H.truthy(width(fits) > maxW, "ein Zeichen mehr passt nicht: " .. fits)
                  -- Zeichen bleiben ganz (UTF-8: kein halber Umlaut)
                  H.falsy(head:find("[\194-\244]$"), "kein abgeschnittenes Mehrbyte-Zeichen")
                  -- die Kachel behaelt den vollen Namen
                  H.neq(c.tile.info.name, text)
               end
            end
         end
         H.truthy(cut >= 2, "lange Namen kommen vor (f=" .. f .. ")")
         H.truthy(kept >= 1, "kurze Namen kommen vor (f=" .. f .. ")")
         H.deepEq(H.takeErrors(), {})
      end
   end)

   H.test("Namen: Original/Verborgen und Breitenwechsel; der Tooltip bleibt beim vollen Namen", function()
      local T = boot({ items = nameItems() })
      local G = T.UI.Grid
      -- sehr lange Beschriftung der synthetischen Kacheln (andere Sprache)
      T.Locale.Add("enUS", {
         GRID_HIDDEN = "Verborgene Ausruestung im Platz",
         GRID_ORIGINAL = "Urspruengliche Ausruestung im Platz",
      })
      T.Locale.Set("enUS")
      G.Layout(500, 400)
      G.SetSlot(CHEST)
      advance(0.5)
      local orig, hide = shownCells(G)[1], shownCells(G)[2]
      H.eq(orig.kind, "original")
      H.eq(hide.kind, "hidden")
      local origLabel = orig.ov.name:GetText()
      H.eq(origLabel:sub(-3), "...", "Beschriftung der Original-Kachel gekuerzt: " .. origLabel)
      H.eq(origLabel:sub(1, 5), "Urspr")
      local label = hide.ov.name:GetText()
      H.eq(label:sub(-3), "...", "Beschriftung der Verborgen-Kachel gekuerzt: " .. label)
      H.eq(label:sub(1, 5), "Verbo")
      -- schmalere Zellen (Vorschau 0.8 ist schmaler, 1.5 breiter): Text folgt der Breite
      T.DB.Set("previewSize", 1.5)
      advance(0.5)
      local wide = shownCells(G)[2].ov.name:GetText()
      H.truthy(#wide > #label, "breitere Zelle zeigt mehr: " .. wide .. " / " .. label)
      local wideOrig = shownCells(G)[1].ov.name:GetText()
      H.truthy(#wideOrig > #origLabel, "breitere Zelle zeigt mehr: " .. wideOrig .. " / " .. origLabel)
      -- Tooltip: voller Name ueber den Item-Link, nicht der gekuerzte Text
      local cell
      for _, c in ipairs(shownCells(G)) do
         if c.itemId == 2001 then cell = c end
      end
      if cell then
         mock.Enter(cell)
         H.truthy(tipHas(cell.tile.info.name) or GameTooltip:IsShown(), "Tooltip zeigt sich")
         mock.Leave(cell)
      end
      H.deepEq(H.takeErrors(), {})
   end)

   -- Aussehen mit gleichem Symbol/Typ/Slot (Duplikate): 2001..2006 teilen sich ein Symbol
   local function dupItems()
      local d = baseItems()
      for i = 1, 6 do
         put(d, 2000 + i, string.format("Look %02d", i), 3, 100 + i, "Armor", "Plate", "INVTYPE_CHEST",
            "SameIcon")
      end
      return d
   end

   H.test("Zaehler: ausgeblendete Duplikate werden genannt; '(filtered)' bleibt echten Filtern vorbehalten", function()
      local T = boot({ items = dupItems() })
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      advance(0.5)
      -- Standard: Duplikate ausgeblendet -> 35 von 40, der Zaehler sagt warum
      H.eq(G.stats.hiddenByFilter, 0)
      H.eq(G.stats.hiddenDuplicates, 5)
      H.eq(G.stats.shown, 35)
      H.eq(G.countText:GetText(), "35 of 40 appearances (5 duplicates hidden)")
      -- Duplikate sichtbar: alles da, schlichter Zaehler
      T.Filter.SetHideDuplicates(false)
      advance(0.5)
      H.eq(G.stats.hiddenDuplicates, 0)
      H.eq(G.countText:GetText(), "40 of 40 appearances")
      -- echter Filter (Qualitaet) und Duplikate zugleich: "(filtered)" gewinnt
      T.Filter.SetHideDuplicates(true)
      T.Filter.SetQuality(0, false)
      advance(0.5)
      H.truthy(G.stats.hiddenByFilter > 0)
      H.truthy(G.stats.hiddenDuplicates > 0)
      H.eq(G.countText:GetText(), string.format("%d of 40 appearances (filtered)", G.stats.shown))
      -- zuruecksetzen: Duplikate bleiben ausgeblendet (Standard), der Zaehler sagt es wieder
      T.Filter.Reset()
      advance(0.5)
      H.eq(G.countText:GetText(), "35 of 40 appearances (5 duplicates hidden)")
      -- schmal: kurze Form "n / m"
      G.Layout(220, 400)
      H.eq(G.countText:GetText(), "35 / 40")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zaehler: Duplikat-Hinweis in jeder Sprache mit denselben drei Zahlen, passt in sein Feld oder faellt auf n / m", function()
      local T = boot({ items = dupItems() })
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      for _, code in ipairs({ "deDE", "frFR", "esES", "ruRU", "koKR", "zhCN", "zhTW" }) do
         T.Locale.Set(code)
         for _, w in ipairs({ 398, 500, 900 }) do
            G.Layout(w, 400)
            advance(0.5)
            local text = G.countText:GetText()
            H.truthy(text:find("35", 1, true) and text:find("40", 1, true), code .. " " .. w .. ": " .. text)
            if text ~= "35 / 40" then
               H.truthy(text:find("5", 1, true), code .. ": Zahl der Duplikate steht da: " .. text)
            end
            H.truthy(G.countText:GetStringWidth() <= G.countText:GetWidth() + 0.01,
               code .. " " .. w .. ": Zaehler passt in sein Feld")
         end
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Verborgen-Kachel: Symbol mit Blizzards Schreibweise (Spell_Nature_Invisibilty)", function()
      local T = boot()
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      local hidden = shownCells(G)[2]   -- hinter der Original-Kachel
      H.eq(hidden.kind, "hidden")
      H.truthy(hidden.ov.icon:IsShown())
      -- die Datei im Client heisst mit dem Tippfehler; die korrekt geschriebene gibt es nicht
      H.eq(hidden.ov.icon:GetTexture(), "Interface\\Icons\\Spell_Nature_Invisibilty")
      H.neq(hidden.ov.icon:GetTexture(), "Interface\\Icons\\Spell_Nature_Invisibility")
      H.deepEq(H.takeErrors(), {})
   end)

   -- Das Suchfeld (EditBox) behaelt in 3.3.5a den Fokus bei Klicks auf andere Frames.
   H.test("Fokus: Klick auf eine Kachel nimmt dem Suchfeld den Fokus, die Suche wird trotzdem uebernommen", function()
      local T = boot()
      local G = T.UI.Grid
      local FB = withBar(T)
      G.SetSlot(CHEST)
      mock.Type(FB.search, "Look 2")
      H.truthy(FB.search:HasFocus(), "getippt: Fokus im Suchfeld")
      local cell = shownCells(G)[3]   -- erster Eintrag
      mock.Click(cell)
      H.falsy(FB.search:HasFocus(), "Klick auf die Kachel: Fokus weg")
      H.falsy(FB.search.focused)
      -- der entprellte Text wird uebernommen (ClearFocus loest weder Enter noch Textaenderung aus)
      advance(0.4)
      H.eq(T.Filter.search, "Look 2")
      H.eq(FB.search:GetText(), "Look 2")
      H.eq(G.stats.shown, 13)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Fokus: Rechtsklick, Blaetterleiste und Reset-Knopf des Rasters geben ihn ebenfalls frei", function()
      local T = boot()
      local G = T.UI.Grid
      local FB = withBar(T)
      G.SetSlot(CHEST)
      -- Rechtsklick (Favorit)
      mock.Type(FB.search, "Look")
      H.truthy(FB.search:HasFocus())
      mock.Click(shownCells(G)[3], "RightButton")
      H.falsy(FB.search:HasFocus(), "Rechtsklick")
      -- Blaetterleiste
      for _, name in ipairs({ "next", "prev", "last", "first" }) do
         FB.search:SetFocus()
         H.truthy(FB.search:HasFocus())
         mock.Click(G.pageButtons[name])
         H.falsy(FB.search:HasFocus(), "Blaetterknopf " .. name)
      end
      -- Reset-Knopf der Meldung "keine Treffer"
      mock.Type(FB.search, "zzz-nothing")
      advance(0.4)
      H.eq(G.mode, "FILTERED")
      FB.search:SetFocus()
      mock.Click(G.resetButton)
      H.falsy(FB.search:HasFocus(), "Reset-Knopf")
      advance(0.4)
      H.eq(G.mode, "GRID")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Fokus: ohne Filterleiste oder ohne Fokus bleibt ein Klick auf die Kachel harmlos", function()
      local T = boot()                         -- Leiste noch nicht gebaut
      local G = T.UI.Grid
      G.SetSlot(CHEST)
      mock.Click(shownCells(G)[3])             -- waehlt (erster Eintrag), kein Fehler
      H.truthy(T.State.HasPending(CHEST))
      local FB = withBar(T)
      mock.Click(shownCells(G)[4])             -- Leiste da, aber ohne Fokus
      H.falsy(FB.search:HasFocus())
      H.deepEq(H.takeErrors(), {})
   end)
end
