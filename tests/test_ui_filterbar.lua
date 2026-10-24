-- tests/test_ui_filterbar.lua
-- ---------------------------------------------------------------------------
-- Tests fuer UI/FilterBar.lua (T.UI.FilterBar): Suche, Sortierung, Filter-
-- menue, Qualitaets-Chips, Schnellschalter und Anordnung.
--
-- Gegen die ECHTEN Module (Locale, Util, Events, DB, Slots, Items, Net, State,
-- Filter, Skin) auf der strengen Attrappe; der Server wird ueber Net.Handle im
-- echten Protokollformat gespielt.
--
--   * Aufbau: feste Hoehe 58, zwei Zeilen, Singleton, Frame-Methoden
--   * Anordnung bis w = 398 ohne Ueberlappung (auch mit sehr langen Texten),
--     nur das Suchfeld schrumpft, Schnellschalter entfallen vor Ueberlappung
--   * Suche: entprellt (0.2 s), nur Eingaben des Spielers, Nachziehen nach
--     externem Zuruecksetzen
--   * Menues: Sortierung (Radio), Filter (Haken, Typen mit Anzahl, eigener
--     Typ gesperrt, Zuruecksetzen) <-> Filter-Zustand
--   * Chips: nur vorhandene Qualitaeten, Tooltip, abgedunkelt wenn ausgeblendet
--   * Ereignisse: gebuendelt, unsichtbar = Dirty-Flag; onChange-Rueckruf
--   * Tastaturfokus: ReleaseFocus und die Klicks der Leiste nehmen dem Suchfeld
--     den Fokus (3.3.5a tut es nicht von selbst), die Suche bleibt erhalten
--
-- Aufruf (im Hauptverzeichnis):  luajit tests/run.lua ui_filterbar
-- ---------------------------------------------------------------------------

return function(H)
   local mock = H.mock
   local CHEST = 4
   local HEAD = 0

   -- -------------------------------------------------------------------------
   -- Hilfen
   -- -------------------------------------------------------------------------

   local function put(defs, id, name, quality, ilvl, class, sub, loc, icon)
      defs[id] = {
         name = name, quality = quality, ilvl = ilvl, class = class, subclass = sub,
         equipLoc = loc, icon = icon and ("Interface\\Icons\\" .. icon) or nil,
      }
   end

   -- Brust: angelegt 1004 (Platte); 24 Kandidaten 2001..2024, Qualitaet i % 8
   -- (alle acht 0..7 kommen vor), Typ rotiert Platte/Kette/Leder/Stoff
   local SUBS = { "Plate", "Mail", "Leather", "Cloth" }
   local CHEST_LIST = {}
   local function baseItems()
      local d = {}
      put(d, 1004, "Chest of Plate", 4, 200, "Armor", "Plate", "INVTYPE_CHEST", "ChestP")
      put(d, 1001, "Helm of Plate", 4, 200, "Armor", "Plate", "INVTYPE_HEAD", "HeadP")
      for i = 1, 24 do
         local id = 2000 + i
         CHEST_LIST[i] = id
         put(d, id, string.format("Look %02d", i), i % 8, 100 + i, "Armor", SUBS[(i - 1) % 4 + 1],
            "INVTYPE_CHEST", "Look" .. i)
      end
      put(d, 3001, "Plate Helm A", 3, 150, "Armor", "Plate", "INVTYPE_HEAD", "HeadA")
      put(d, 3002, "Plate Helm B", 2, 140, "Armor", "Plate", "INVTYPE_HEAD", "HeadB")
      return d
   end

   local function feed(T, slot, list, bucket)
      local n = #list
      T.Net.Handle(string.format("AvailableTransmogs:%d:%d:%d:start", slot, bucket, n))
      local i = 1
      while i <= n do
         local part = {}
         for j = i, math.min(i + 19, n) do part[#part + 1] = tostring(list[j]) end
         T.Net.Handle(string.format("AvailableTransmogs:%d:%d:%d:%s", slot, bucket, n,
            table.concat(part, ":")))
         i = i + 20
      end
      T.Net.Handle(string.format("AvailableTransmogs:%d:%d:%d:end", slot, bucket, n))
   end

   -- Laedt das Addon bis FilterBar.lua, initialisiert die Module wie Boot und
   -- baut die Leiste. spec.w Breite (Standard 600), spec.onChange Rueckruf,
   -- spec.noBar: nicht erzeugen, spec.slot: Slot fuer Refresh (Standard Brust).
   local function boot(spec)
      spec = spec or {}
      local T = H.boot({
         upTo = "UI\\FilterBar.lua", login = false,
         items = baseItems(),
         world = { equipment = { [5] = 1004, [1] = 1001 } },
      })
      T.DB.Init()
      T.Locale.Set("enUS")
      T.Slots.Init()
      T.Items.Init()
      T.Net.Init()
      T.State.Init()
      T.Outfits.Init()
      T.enteredWorldAt = GetTime() - 60
      mock.CacheAll()
      T.State.RefreshEquipment()
      feed(T, CHEST, CHEST_LIST, 405)
      feed(T, HEAD, { 3001, 3002 }, 405)
      if not spec.noBar then
         local parent = CreateFrame("Frame", nil, UIParent)
         parent:SetWidth(900)
         parent:SetHeight(300)
         parent:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
         local calls = { n = 0 }
         T.changes = calls
         local bar = T.UI.FilterBar.Create(parent, spec.onChange or function()
            calls.n = calls.n + 1
         end)
         bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
         T.UI.FilterBar.Layout(spec.w or 600)
         T.UI.FilterBar.Refresh(spec.slot ~= nil and spec.slot or CHEST)
         T.parent = parent
      end
      return T
   end

   local function advance(dt)
      mock.Advance(dt or 0.2)
   end

   local function counter(T, names)
      local c = {}
      for _, name in ipairs(names) do
         T.Events.On(name, function() c[name] = (c[name] or 0) + 1 end, c)
      end
      return c
   end

   -- Rechteck eines TOPLEFT-verankerten Kindes der Leiste: links, oben, rechts, unten
   local function rect(f, bar)
      local point, rel, _, x, y = f:GetPoint(1)
      H.eq(point, "TOPLEFT", "Anker")
      H.eq(rel, bar, "Bezug")
      return x, -y, x + f:GetWidth(), -y + f:GetHeight()
   end

   -- Alle sichtbaren Bedienelemente { name, l, t, r, b }
   local function elements(FB)
      local bar = FB.frame
      local out = {}
      local function add(name, f)
         if f and f:IsShown() then
            local l, t, r, b = rect(f, bar)
            out[#out + 1] = { name = name, l = l, t = t, r = r, b = b }
         end
      end
      add("search", FB.search)
      add("sort", FB.sortButton)
      add("filter", FB.filterButton)
      add("reset", FB.resetButton)
      for q = 0, 7 do
         if FB.chips[q] then add("chip" .. q, FB.chips[q]) end
      end
      add("fav", FB.favChip)
      add("new", FB.newChip)
      return out
   end

   -- Prueft: alles liegt in [0, w] x [0, 58], nichts ueberlappt
   local function assertNoOverlap(FB, w, label)
      local els = elements(FB)
      for _, e in ipairs(els) do
         H.truthy(e.l >= 0, label .. ": " .. e.name .. " links >= 0 (" .. e.l .. ")")
         H.truthy(e.r <= w + 1e-6, label .. ": " .. e.name .. " rechts <= " .. w .. " (" .. e.r .. ")")
         H.truthy(e.t >= 0 and e.b <= 58 + 1e-6, label .. ": " .. e.name .. " innerhalb der Hoehe")
         H.truthy(e.r > e.l and e.b > e.t, label .. ": " .. e.name .. " hat Groesse")
      end
      for i = 1, #els do
         for j = i + 1, #els do
            local a, b = els[i], els[j]
            local overlap = a.l < b.r - 1e-6 and b.l < a.r - 1e-6 and a.t < b.b - 1e-6 and b.t < a.b - 1e-6
            H.falsy(overlap, string.format("%s: %s (%g..%g) ueberlappt %s (%g..%g)", label, a.name,
               a.l, a.r, b.name, b.l, b.r))
         end
      end
      return els
   end

   -- Zeilen des Menues in Reihenfolge
   local function menuRows()
      local out = {}
      local f = rawget(_G, "TransmogMenuFrame")
      if not f then return out end
      for _, b in ipairs(mock.Find(f, "Button")) do
         if b:IsShown() and b.item then out[#out + 1] = b end
      end
      return out
   end

   local function rowTexts()
      local t = {}
      for i, r in ipairs(menuRows()) do t[i] = r.text:GetText() end
      return t
   end

   local function rowByText(text)
      for _, r in ipairs(menuRows()) do
         if r.text:GetText() == text then return r end
      end
      return nil
   end

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

   local function qualityList(T, slot)
      local out = {}
      for i, q in ipairs(T.Filter.Qualities(slot)) do out[i] = q.quality end
      return out
   end

   -- Chips, die gezeigt werden (Qualitaeten, aufsteigend)
   local function shownChips(FB)
      local out = {}
      for q = 0, 7 do
         if FB.chips[q] and FB.chips[q]:IsShown() then out[#out + 1] = q end
      end
      return out
   end

   -- =========================================================================
   H.section("Aufbau")
   -- =========================================================================

   H.test("Create: Singleton, Hoehe 58, Frame-Methoden, alle Bedienelemente", function()
      local T = boot()
      local FB = T.UI.FilterBar
      H.eq(FB.HEIGHT, 58)
      H.eq(FB.frame:GetHeight(), 58)
      H.eq(FB.frame.height, 58)
      H.eq(FB.frame:GetWidth(), 600)
      H.truthy(rawequal(FB.Create(T.parent), FB.frame), "zweites Create liefert dieselbe Leiste")
      H.eq(type(FB.frame.Layout), "function")
      H.eq(type(FB.frame.Refresh), "function")
      FB.frame:Layout(500)
      H.eq(FB.frame:GetWidth(), 500)
      FB.frame:Refresh(HEAD)
      H.eq(FB.slot, HEAD)
      -- Bedienelemente
      H.truthy(FB.search and FB.sortButton and FB.filterButton and FB.resetButton)
      H.truthy(FB.favChip and FB.newChip)
      -- Platzhalter
      H.eq(FB.search.placeholderText:GetText(), "Search name, type or #id")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zwei Zeilen zu 24 px, 6 px Abstand, 4 px oben", function()
      local T = boot()
      local FB = T.UI.FilterBar
      local l, t, r, b = rect(FB.search, FB.frame)
      H.eq(t, 4)
      H.eq(b - t, 24)
      l, t, r, b = rect(FB.sortButton, FB.frame)
      H.eq(t, 4)
      H.eq(b - t, 24)
      l, t, r, b = rect(FB.filterButton, FB.frame)
      H.eq(t, 4)
      l, t, r, b = rect(FB.resetButton, FB.frame)
      H.eq(t, 4)
      H.eq(r, 600, "Zuruecksetzen schliesst rechts buendig ab")
      -- Zeile 2 beginnt bei 4 + 24 + 6 = 34; Chips 20 px mittig in 24 -> 36
      for _, q in ipairs(shownChips(FB)) do
         l, t, r, b = rect(FB.chips[q], FB.frame)
         H.eq(t, 36)
         H.eq(b - t, 20)
         H.eq(r - l, 20)
      end
      l, t, r, b = rect(FB.favChip, FB.frame)
      H.eq(t, 36)
      H.eq(r, 600)
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Anordnung")
   -- =========================================================================

   H.test("Layout: nichts ueberlappt von 398 bis 1200; die Knoepfe behalten ihre Breite", function()
      local T = boot()
      local FB = T.UI.FilterBar
      H.deepEq(shownChips(FB), { 0, 1, 2, 3, 4, 5, 6, 7 }, "alle acht Qualitaeten vorhanden")
      local widths
      for _, w in ipairs({ 1200, 880, 700, 600, 500, 440, 398 }) do
         FB.Layout(w)
         H.eq(FB.frame:GetWidth(), w)
         local els = assertNoOverlap(FB, w, "w=" .. w)
         local byName = {}
         for _, e in ipairs(els) do byName[e.name] = e end
         -- beide Schnellschalter passen bis 398 neben acht Chips
         H.truthy(byName.fav, "Stern bei " .. w)
         H.truthy(byName.new, "Neu bei " .. w)
         local cur = {
            sort = byName.sort.r - byName.sort.l,
            filter = byName.filter.r - byName.filter.l,
            reset = byName.reset.r - byName.reset.l,
         }
         widths = widths or cur
         H.deepEq(cur, widths, "Knopfbreiten bei " .. w)
         -- das Suchfeld ist flexibel
         H.eq(byName.search.l, 0)
         H.near(byName.search.r, byName.sort.l - 6, 1e-6, "Suchfeld endet 6 px vor dem Sortierknopf")
      end
      -- bei 398 bleibt fuer die Suche brauchbar Platz
      FB.Layout(398)
      local els = elements(FB)
      for _, e in ipairs(els) do
         if e.name == "search" then
            H.truthy(e.r - e.l >= 100, "Suchfeld bei 398 mindestens 100 px: " .. (e.r - e.l))
         end
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout: sehr lange Texte (Russisch/Deutsch) bleiben bis 398 ueberlappungsfrei", function()
      local T = boot()
      T.Locale.Add("ruRU", {
         SORT_QUALITY = "Качество предмета", SORT_NAME = "Название", SORT_ILEVEL = "Уровень предмета",
         FILTER_SORT = "Сортировка: %s", FILTER_BUTTON = "Фильтр",
         FILTER_NEW = "Новые", FILTER_SEARCH_PLACEHOLDER = "Поиск по названию, типу или #id",
      })
      local FB = T.UI.FilterBar
      T.Locale.Set("ruRU")
      advance()
      for _, w in ipairs({ 398, 420, 500, 880 }) do
         FB.Layout(w)
         assertNoOverlap(FB, w, "ruRU w=" .. w)
      end
      -- Texte folgen
      H.eq(FB.search.placeholderText:GetText(), "Поиск по названию, типу или #id")
      H.eq(FB.filterButton:GetLabel(), "Фильтр")
      H.eq(FB.newChip:GetLabel(), "Новые")
      H.eq(FB.sortButton:GetLabel(), "Сортировка: Качество предмета")
      -- Suchfeld ist nie negativ/zu klein (ueberlappungsfrei, mindestens 40)
      FB.Layout(398)
      H.truthy(FB.search:GetWidth() >= 40, "Suchfeld " .. FB.search:GetWidth())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout: Schnellschalter entfallen vor einer Ueberlappung (erst Neu, dann Stern)", function()
      local T = boot()
      local FB = T.UI.FilterBar
      FB.Layout(398)
      H.truthy(FB.favChip:IsShown())
      H.truthy(FB.newChip:IsShown())
      -- Chips 8*20 + 7*4 = 188; Stern 24 + Abstand 8 -> ab w = 220 Stern; Neu je nach Breite
      FB.Layout(240)
      H.truthy(FB.favChip:IsShown(), "Stern passt noch")
      H.falsy(FB.newChip:IsShown(), "Neu passt nicht mehr")
      FB.Layout(205)
      H.falsy(FB.favChip:IsShown())
      H.falsy(FB.newChip:IsShown())
      -- zurueck
      FB.Layout(500)
      H.truthy(FB.favChip:IsShown())
      H.truthy(FB.newChip:IsShown())
      assertNoOverlap(FB, 500, "w=500")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout: ungueltige Breiten werfen nicht", function()
      local T = boot()
      local FB = T.UI.FilterBar
      FB.Layout(500)
      FB.Layout(nil)
      FB.Layout("x")
      FB.Layout(0 / 0)
      FB.Layout(-3)
      H.eq(FB.frame:GetWidth(), 500)
      FB.Layout(10)   -- unter dem Mindestmass: keine negativen Groessen
      H.truthy(FB.search:GetWidth() >= 40)
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Suche")
   -- =========================================================================

   H.test("Suchfeld: entprellt 0.2 s, ein SetSearch, ein FILTER_CHANGED, ein onChange", function()
      local T = boot()
      local FB = T.UI.FilterBar
      local events = counter(T, { "FILTER_CHANGED" })
      mock.Type(FB.search, "p")
      advance(0.1)
      mock.Type(FB.search, "pl")
      advance(0.1)
      mock.Type(FB.search, "pla")
      H.eq(T.Filter.search, "", "noch nicht uebernommen")
      advance(0.15)
      H.eq(T.Filter.search, "", "Entprellung laeuft neu an")
      advance(0.1)
      H.eq(T.Filter.search, "pla")
      H.eq(events.FILTER_CHANGED, 1)
      H.eq(T.changes.n, 1)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Suchfeld: programmatisches SetText loest nichts aus", function()
      local T = boot()
      local FB = T.UI.FilterBar
      FB.search:SetText("abc")
      advance(0.5)
      H.eq(T.Filter.search, "")
      H.eq(T.changes.n, 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Suche wirkt auf Filter.Compute und Zaehler der Leiste", function()
      local T = boot()
      local FB = T.UI.FilterBar
      mock.Type(FB.search, "Look 07")
      advance(0.3)
      local entries, stats = T.Filter.Compute(CHEST)
      H.eq(stats.shown, 1)
      H.eq(entries[1].id, 2007)
      H.truthy(FB.resetButton:IsEnabled(), "Zuruecksetzen aktiv")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Externes Zuruecksetzen leert das Suchfeld (auch mit Fokus)", function()
      local T = boot()
      local FB = T.UI.FilterBar
      mock.Type(FB.search, "Look")
      advance(0.3)
      H.eq(T.Filter.search, "Look")
      H.truthy(FB.search:HasFocus(), "Fokus bleibt im Feld")
      T.Filter.Reset()   -- z. B. der Knopf im Raster
      advance(0.2)
      H.eq(FB.search:GetText(), "")
      -- externes SetSearch erscheint im Feld
      T.Filter.SetSearch("plate")
      advance(0.2)
      H.eq(FB.search:GetText(), "plate")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Noch nicht uebernommene Eingabe wird von fremden Filter-Ereignissen nicht ueberschrieben", function()
      local T = boot()
      local FB = T.UI.FilterBar
      mock.Type(FB.search, "Lo")
      T.Filter.SetQuality(0, false)   -- fremde Aenderung waehrend der Entprellung
      advance(0.1)
      H.eq(FB.search:GetText(), "Lo")
      advance(0.2)
      H.eq(T.Filter.search, "Lo")
      H.eq(FB.search:GetText(), "Lo")
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Sortierung")
   -- =========================================================================

   H.test("Sortierknopf: Label zeigt die Sortierung, Menue mit drei Radio-Eintraegen", function()
      local T = boot()
      local FB = T.UI.FilterBar
      H.eq(FB.sortButton:GetLabel(), "Sort: Quality")
      mock.Click(FB.sortButton)
      H.truthy(T.UI.Skin.Menu.IsOpen())
      H.deepEq(rowTexts(), { "Quality", "Name", "Item level" })
      local rows = menuRows()
      for _, r in ipairs(rows) do
         H.eq(r.item.radio, true)
      end
      H.eq(rows[1].item.checked, true)
      H.eq(rows[2].item.checked, false)
      -- waehlen
      mock.Click(rows[2])
      H.falsy(T.UI.Skin.Menu.IsOpen(), "schliesst nach der Wahl")
      H.eq(T.Filter.state.sort, "NAME")
      H.eq(FB.sortButton:GetLabel(), "Sort: Name")
      H.eq(T.changes.n, 1)
      -- nochmal: Haken wandert
      mock.Click(FB.sortButton)
      rows = menuRows()
      H.eq(rows[2].item.checked, true)
      H.eq(rows[1].item.checked, false)
      mock.Click(rows[3])
      H.eq(T.Filter.state.sort, "ILEVEL")
      H.eq(FB.sortButton:GetLabel(), "Sort: Item level")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Sortierung extern geaendert: Label folgt", function()
      local T = boot()
      local FB = T.UI.FilterBar
      T.Filter.SetSort("ILEVEL")
      advance()
      H.eq(FB.sortButton:GetLabel(), "Sort: Item level")
      H.eq(T.changes.n, 0, "nur Eingaben des Spielers melden onChange")
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Filtermenue")
   -- =========================================================================

   H.test("Filtermenue: Duplikate, Favoriten, Neu, Trenner, Typ-Titel, Typen mit Anzahl, Reset", function()
      local T = boot()
      local FB = T.UI.FilterBar
      mock.Click(FB.filterButton)
      H.truthy(T.UI.Skin.Menu.IsOpen())
      local texts = rowTexts()
      H.eq(texts[1], "Hide duplicate looks")
      H.eq(texts[2], "Favourites only")
      H.eq(texts[3], "New only")
      H.eq(texts[4], "", "Trenner")
      H.eq(texts[5], "Type")
      -- Typen: Platte, Kette, Leder, Stoff (je 6 von 24)
      H.eq(texts[6], "Plate (6)")
      H.eq(texts[7], "Mail (6)")
      H.eq(texts[8], "Leather (6)")
      H.eq(texts[9], "Cloth (6)")
      H.eq(texts[10], "", "Trenner")
      H.eq(texts[11], "Reset filters")
      H.eq(#texts, 11)
      local rows = menuRows()
      -- Zustand der Haken
      H.eq(rows[1].item.checked, true, "Duplikate verbergen ist Standard")
      H.eq(rows[2].item.checked, false)
      H.eq(rows[3].item.checked, false)
      H.eq(rows[5].item.isTitle, true)
      -- eigener Typ (Platte): angehakt und gesperrt
      H.eq(rows[6].item.checked, true)
      H.eq(rows[6].item.disabled, true)
      H.eq(rows[7].item.checked, true)
      H.eq(rows[7].item.disabled, false)
      -- Reset gesperrt, solange nichts aktiv ist
      H.eq(rows[11].item.disabled, true)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Filtermenue: Haken schalten Filter.state; das Menue bleibt offen; onChange je Klick", function()
      local T = boot()
      local FB = T.UI.FilterBar
      mock.Click(FB.filterButton)
      local rows = menuRows()
      mock.Click(rows[1])   -- Duplikate: aus
      H.eq(T.Filter.state.hideDuplicates, false)
      H.truthy(T.UI.Skin.Menu.IsOpen(), "keepOpen")
      H.eq(menuRows()[1].item.checked, false)
      mock.Click(menuRows()[2])   -- Favoriten
      H.eq(T.Filter.state.favoritesOnly, true)
      mock.Click(menuRows()[3])   -- Neu
      H.eq(T.Filter.state.newOnly, true)
      H.eq(T.changes.n, 3)
      -- Typ Kette ausblenden
      mock.Click(rowByText("Mail (6)"))
      H.eq(T.Filter.state.typesOff[403], true)
      H.eq(rowByText("Mail (6)").item.checked, false)
      -- wieder an
      mock.Click(rowByText("Mail (6)"))
      H.eq(T.Filter.state.typesOff[403], nil)
      -- eigener Typ: Klick tut nichts
      mock.Click(rowByText("Plate (6)"))
      H.eq(T.Filter.state.typesOff[404], nil)
      H.eq(T.changes.n, 5)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Filtermenue: 'Reset filters' setzt zurueck, schliesst, meldet onChange", function()
      local T = boot()
      local FB = T.UI.FilterBar
      T.Filter.SetFavoritesOnly(true)
      T.Filter.SetType(402, false)
      T.Filter.SetQuality(1, false)
      T.Filter.SetSearch("x")
      T.Filter.SetHideDuplicates(false)
      advance()
      mock.Click(FB.filterButton)
      local reset = rowByText("Reset filters")
      H.eq(reset.item.disabled, false)
      mock.Click(reset)
      H.falsy(T.UI.Skin.Menu.IsOpen())
      H.eq(T.Filter.IsActive(), false)
      H.eq(T.Filter.state.hideDuplicates, false, "Duplikate/Sortierung bleiben (Filter.Reset)")
      H.eq(T.changes.n, 1)
      advance()
      H.eq(FB.search:GetText(), "")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Filtermenue: Typen des aktuellen Slots (Kopf: nur Platte, eigener Typ)", function()
      local T = boot()
      local FB = T.UI.FilterBar
      FB.Refresh(HEAD)
      mock.Click(FB.filterButton)
      local texts = rowTexts()
      H.eq(texts[5], "Type")
      H.eq(texts[6], "Plate (2)")
      H.eq(menuRows()[6].item.disabled, true)
      T.UI.Skin.Menu.Close()
      -- kein Slot: kein Typ-Abschnitt
      FB.Refresh(nil)
      mock.Click(FB.filterButton)
      texts = rowTexts()
      H.deepEq(texts, { "Hide duplicate looks", "Favourites only", "New only", "", "Reset filters" })
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Filterknopf ist hervorgehoben, solange Menue-Filter aktiv sind", function()
      local T = boot()
      local FB = T.UI.FilterBar
      H.falsy(FB.filterButton.selected)
      T.Filter.SetNewOnly(true)
      advance()
      H.truthy(FB.filterButton.selected)
      T.Filter.SetNewOnly(false)
      T.Filter.SetType(401, false)
      advance()
      H.truthy(FB.filterButton.selected)
      T.Filter.Reset()
      advance()
      H.falsy(FB.filterButton.selected)
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Chips")
   -- =========================================================================

   H.test("Qualitaets-Chips: nur vorhandene Qualitaeten, aufsteigend, je Slot", function()
      local T = boot()
      local FB = T.UI.FilterBar
      H.deepEq(shownChips(FB), qualityList(T, CHEST))
      H.deepEq(shownChips(FB), { 0, 1, 2, 3, 4, 5, 6, 7 })
      FB.Refresh(HEAD)
      H.deepEq(shownChips(FB), { 2, 3 }, "Kopf hat Qualitaet 2 und 3")
      assertNoOverlap(FB, 600, "Kopf")
      FB.Refresh(nil)
      H.deepEq(shownChips(FB), {})
      FB.Refresh(CHEST)
      H.deepEq(shownChips(FB), { 0, 1, 2, 3, 4, 5, 6, 7 })
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Chip: Farbe der Qualitaet, Tooltip mit Name und Anzahl", function()
      local T = boot()
      local FB = T.UI.FilterBar
      local chip = FB.chips[3]
      H.eq(chip.quality, 3)
      H.eq(chip.count, 3)    -- 24 / 8 je Qualitaet
      mock.Enter(chip)
      H.truthy(GameTooltip:IsShown())
      H.eq(GameTooltip:GetOwner(), chip)
      local lines = tipLines()
      H.eq(lines[1], "Rare", "Qualitaetsname (Blizzard-Global)")
      H.eq(lines[2], "Appearances: 3")
      H.eq(lines[3], "Click to hide this quality")
      mock.Leave(chip)
      H.falsy(GameTooltip:IsShown())
      -- Backdrop in Qualitaetsfarbe (Rand heller als Grund)
      local r, g, b = T.Util.QualityColor(3)
      local br, bg, bb = chip:GetBackdropColor()
      H.near(br, r * 0.9, 1e-6)
      H.near(bg, g * 0.9, 1e-6)
      H.near(bb, b * 0.9, 1e-6)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Chip-Klick blendet die Qualitaet aus/ein; ausgeblendet = abgedunkelt", function()
      local T = boot()
      local FB = T.UI.FilterBar
      local chip = FB.chips[2]
      H.falsy(chip.hiddenQuality)
      H.eq(chip:GetAlpha(), 1)
      mock.Click(chip)
      H.eq(T.Filter.state.qualities[2], false)
      H.truthy(chip.hiddenQuality)
      H.truthy(chip:GetAlpha() < 1, "abgedunkelt")
      H.eq(T.changes.n, 1)
      -- Zaehler in Filter.Compute
      local _, stats = T.Filter.Compute(CHEST)
      H.eq(stats.hiddenByFilter, 3)
      -- Tooltip bietet "einblenden" an
      mock.Enter(chip)
      H.truthy(tipHas("Click to show this quality"))
      mock.Leave(chip)
      -- die Qualitaet bleibt als Chip stehen (auch wenn ihre Eintraege ausgeblendet sind)
      H.deepEq(shownChips(FB), { 0, 1, 2, 3, 4, 5, 6, 7 })
      mock.Click(chip)
      H.eq(T.Filter.state.qualities[2], nil)
      H.falsy(chip.hiddenQuality)
      H.eq(chip:GetAlpha(), 1)
      H.eq(T.changes.n, 2)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Externe Qualitaetsaenderung (z. B. Zuruecksetzen) faerbt die Chips nach", function()
      local T = boot()
      local FB = T.UI.FilterBar
      T.Filter.SetQuality(5, false)
      T.Filter.SetQuality(6, false)
      advance()
      H.truthy(FB.chips[5].hiddenQuality)
      H.truthy(FB.chips[6].hiddenQuality)
      H.falsy(FB.chips[4].hiddenQuality)
      T.Filter.Reset()
      advance()
      H.falsy(FB.chips[5].hiddenQuality)
      H.falsy(FB.chips[6].hiddenQuality)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Schnellschalter: Stern = Nur Favoriten, Neu = Nur neue; Zustand folgt Filter.state", function()
      local T = boot()
      local FB = T.UI.FilterBar
      H.falsy(FB.favChip.selected)
      H.falsy(FB.newChip.selected)
      mock.Click(FB.favChip)
      H.eq(T.Filter.state.favoritesOnly, true)
      H.truthy(FB.favChip.selected)
      mock.Click(FB.newChip)
      H.eq(T.Filter.state.newOnly, true)
      H.truthy(FB.newChip.selected)
      H.eq(T.changes.n, 2)
      mock.Click(FB.favChip)
      H.eq(T.Filter.state.favoritesOnly, false)
      H.falsy(FB.favChip.selected)
      -- extern
      T.Filter.SetNewOnly(false)
      advance()
      H.falsy(FB.newChip.selected)
      -- Tooltip
      mock.Enter(FB.newChip)
      H.truthy(tipHas("New"))
      H.truthy(tipHas("Click to turn on"))
      mock.Leave(FB.newChip)
      mock.Enter(FB.favChip)
      H.truthy(tipHas("Favourites"))
      mock.Leave(FB.favChip)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zuruecksetzen (x): nur aktiv, wenn ein Filter aktiv ist; Klick setzt alles zurueck", function()
      local T = boot()
      local FB = T.UI.FilterBar
      H.eq(FB.resetButton:GetLabel(), "x")
      H.truthy(FB.resetButton.uiOff, "gesperrt ohne Filter")
      -- gesperrter Klick tut nichts
      mock.Click(FB.resetButton)
      H.eq(T.changes.n, 0)
      -- Tooltip nennt den Grund
      mock.Enter(FB.resetButton)
      H.truthy(tipHas("No filters are active."))
      mock.Leave(FB.resetButton)

      T.Filter.SetQuality(1, false)
      T.Filter.SetFavoritesOnly(true)
      advance()
      H.falsy(FB.resetButton.uiOff)
      mock.Enter(FB.resetButton)
      H.truthy(tipHas("Reset all filters"))
      mock.Leave(FB.resetButton)
      mock.Click(FB.resetButton)
      H.eq(T.Filter.IsActive(), false)
      H.eq(T.changes.n, 1)
      advance()
      H.truthy(FB.resetButton.uiOff)
      H.falsy(FB.chips[1].hiddenQuality)
      H.falsy(FB.favChip.selected)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zuruecksetzen bricht eine laufende Suchentprellung ab", function()
      local T = boot()
      local FB = T.UI.FilterBar
      T.Filter.SetQuality(1, false)
      advance()
      mock.Type(FB.search, "Look")      -- noch nicht uebernommen
      mock.Click(FB.resetButton)
      advance(0.5)
      H.eq(T.Filter.search, "", "die Suche wird nach dem Reset nicht nachtraeglich gesetzt")
      H.eq(FB.search:GetText(), "")
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Aktualisierung")
   -- =========================================================================

   H.test("LIST_READY des aktuellen Slots aktualisiert Chips; anderer Slot nicht", function()
      local T = boot()
      local FB = T.UI.FilterBar
      FB.Refresh(HEAD)
      H.deepEq(shownChips(FB), { 2, 3 })
      -- neue Kopfliste mit zusaetzlicher Qualitaet 4
      local d = {}
      put(d, 3003, "Plate Helm C", 4, 160, "Armor", "Plate", "INVTYPE_HEAD", "HeadC")
      for id, it in pairs(d) do mock.items[id] = it end
      mock.CacheAll()
      feed(T, HEAD, { 3001, 3002, 3003 }, 405)
      advance()
      H.deepEq(shownChips(FB), { 2, 3, 4 })
      -- Brust-Strom beeinflusst die Kopf-Leiste nicht (Ereignis anderer Slots)
      local calls = 0
      local orig = T.Filter.Qualities
      T.Filter.Qualities = function(...)
         calls = calls + 1
         return orig(...)
      end
      T.Events.Fire("LIST_READY", CHEST)
      advance()
      H.eq(calls, 0)
      T.Events.Fire("LIST_READY", HEAD)
      advance()
      H.eq(calls, 1)
      T.Filter.Qualities = orig
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ereignisse werden gebuendelt (ein Abgleich je Burst)", function()
      local T = boot()
      local FB = T.UI.FilterBar
      advance()
      local calls = 0
      local orig = T.Filter.Qualities
      T.Filter.Qualities = function(...)
         calls = calls + 1
         return orig(...)
      end
      for _ = 1, 6 do
         T.Events.Fire("ITEMS_RESOLVED", 1)
         T.Events.Fire("FILTER_CHANGED")
         T.Events.Fire("EQUIPMENT_CHANGED", CHEST)
      end
      H.eq(calls, 0)
      advance()
      H.eq(calls, 1)
      T.Filter.Qualities = orig
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Unsichtbar: kein Abgleich (Dirty-Flag), Nachholen im OnShow", function()
      local T = boot()
      local FB = T.UI.FilterBar
      advance()
      T.parent:Hide()
      local calls = 0
      local orig = T.Filter.Qualities
      T.Filter.Qualities = function(...)
         calls = calls + 1
         return orig(...)
      end
      T.Filter.SetQuality(3, false)
      T.Events.Fire("ITEMS_RESOLVED", 5)
      advance()
      FB.Refresh(CHEST)
      H.eq(calls, 0)
      T.parent:Show()
      H.eq(calls, 1)
      H.truthy(FB.chips[3].hiddenQuality)
      T.Filter.Qualities = orig
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Refresh ohne Argument behaelt den Slot, Refresh(nil) loescht ihn", function()
      local T = boot()
      local FB = T.UI.FilterBar
      FB.Refresh(HEAD)
      FB.Refresh()
      H.eq(FB.slot, HEAD)
      H.deepEq(shownChips(FB), { 2, 3 })
      FB.Refresh(nil)
      H.eq(FB.slot, nil)
      H.deepEq(shownChips(FB), {})
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("onChange-Fehler stoeren die Leiste nicht (Fehlerbehandler)", function()
      local T = boot({ onChange = function() error("boom") end })
      local FB = T.UI.FilterBar
      H.allowErrors()
      mock.Click(FB.favChip)
      H.eq(T.Filter.state.favoritesOnly, true)
      local errs = H.takeErrors()
      H.eq(#errs, 1)
      H.contains(errs[1], "boom")
   end)

   H.test("Sprachwechsel: Texte und Breiten werden neu gerechnet", function()
      local T = boot()
      local FB = T.UI.FilterBar
      T.Locale.Add("deDE", {
         SORT_QUALITY = "Qualitaet", SORT_NAME = "Name", SORT_ILEVEL = "Gegenstandsstufe",
         FILTER_SORT = "Sortierung: %s", FILTER_BUTTON = "Filter",
         FILTER_NEW = "Neu", FILTER_SEARCH_PLACEHOLDER = "Suche nach Name, Typ oder #id",
         FILTER_RESET = "Filter zuruecksetzen", FILTER_HIDE_DUPLICATES = "Doppelte ausblenden",
         FILTER_FAVORITES_ONLY = "Nur Favoriten", FILTER_NEW_ONLY = "Nur neue",
         FILTER_TYPE_TITLE = "Typ",
      })
      local before = FB.sortButton:GetWidth()
      T.Locale.Set("deDE")
      advance()
      H.eq(FB.search.placeholderText:GetText(), "Suche nach Name, Typ oder #id")
      H.eq(FB.sortButton:GetLabel(), "Sortierung: Qualitaet")
      H.eq(FB.newChip:GetLabel(), "Neu")
      H.truthy(FB.sortButton:GetWidth() > before, "laengere Texte: breiterer Knopf")
      assertNoOverlap(FB, 600, "deDE 600")
      FB.Layout(398)
      assertNoOverlap(FB, 398, "deDE 398")
      mock.Click(FB.filterButton)
      H.eq(rowTexts()[1], "Doppelte ausblenden")
      H.eq(rowTexts()[5], "Typ")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Kein haengendes OnUpdate im Leerlauf, keine offenen Timer", function()
      local T = boot()
      local FB = T.UI.FilterBar
      mock.Type(FB.search, "Look")
      T.Filter.SetQuality(1, false)
      mock.Click(FB.favChip)
      advance(1)
      mock.Advance(10, 0.5)
      H.eq(T.Util.TimerCount(), 0)
      H.eq(#mock.UpdateFrames(), 0)
      H.deepEq(H.takeErrors(), {})
   end)
   -- =========================================================================
   H.section("Nachpruefung: Menue, Suche, Chips, Texte")
   -- =========================================================================

   H.test("Filtermenue: 'Reset filters' folgt den Haken im offenen Menue (ohne es neu zu oeffnen)", function()
      local T = boot()
      local FB = T.UI.FilterBar
      mock.Click(FB.filterButton)
      H.eq(rowByText("Reset filters").item.disabled, true, "nichts aktiv")
      -- Favoriten an: der Eintrag wird frei
      mock.Click(rowByText("Favourites only"))
      H.eq(rowByText("Reset filters").item.disabled, false)
      H.truthy(T.UI.Skin.Menu.IsOpen())
      -- wieder aus: gesperrt
      mock.Click(rowByText("Favourites only"))
      H.eq(rowByText("Reset filters").item.disabled, true)
      -- ein Typ ausblenden
      mock.Click(rowByText("Mail (6)"))
      H.eq(rowByText("Reset filters").item.disabled, false)
      mock.Click(rowByText("Mail (6)"))
      H.eq(rowByText("Reset filters").item.disabled, true)
      -- "Neu" und "Duplikate" (Duplikate zaehlen nicht als aktiver Filter)
      mock.Click(rowByText("New only"))
      H.eq(rowByText("Reset filters").item.disabled, false)
      mock.Click(rowByText("New only"))
      mock.Click(rowByText("Hide duplicate looks"))
      H.eq(rowByText("Reset filters").item.disabled, true, "Duplikate sind kein Filter im Sinn von IsActive")
      -- gesperrter Eintrag tut nichts
      local n = T.changes.n
      mock.Click(rowByText("Reset filters"))
      H.eq(T.changes.n, n)
      H.truthy(T.UI.Skin.Menu.IsOpen())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Filtermenue: Erlaeuterung der Duplikate steht umbrochen unter einem Titel", function()
      local T = boot()
      local FB = T.UI.FilterBar
      mock.Click(FB.filterButton)
      local row = rowByText("Hide duplicate looks")
      mock.Enter(row)
      H.truthy(GameTooltip:IsShown())
      local lines = GameTooltip.__lines
      H.eq(lines[1].left, "Hide duplicate looks", "Titel")
      H.eq(#lines, 2)
      H.truthy(lines[2].left:find("approximation", 1, true), "Erlaeuterung (Icon-Naeherung)")
      H.eq(lines[2].wrap, true, "umbrochen statt einer sehr breiten Zeile")
      mock.Leave(row)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Filtermenue: eigener Typ bleibt angehakt und gesperrt, auch wenn er (alt) ausgeblendet ist", function()
      local T = boot()
      local FB = T.UI.FilterBar
      T.Filter.state.typesOff[404] = true       -- Altlast: Platte war ausgeblendet, dann Platte angelegt
      mock.Click(FB.filterButton)
      local row = rowByText("Plate (6)")
      H.eq(row.item.checked, true)
      H.eq(row.item.disabled, true)
      mock.Enter(row)
      H.truthy(tipHas("This is the type of your equipped item and cannot be hidden."))
      mock.Leave(row)
      mock.Click(row)
      H.eq(T.Filter.state.typesOff[404], true, "der gesperrte Eintrag aendert nichts")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Filtermenue: fehlendes hideDuplicates (nil) gilt als angehakt", function()
      local T = boot()
      local FB = T.UI.FilterBar
      T.Filter.state.hideDuplicates = nil
      mock.Click(FB.filterButton)
      H.eq(rowByText("Hide duplicate looks").item.checked, true)
      mock.Click(rowByText("Hide duplicate looks"))
      H.eq(T.Filter.state.hideDuplicates, false)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Filterknopf: nur die Menue-Filter heben ihn hervor (Suche und Qualitaet nicht)", function()
      local T = boot()
      local FB = T.UI.FilterBar
      T.Filter.SetSearch("Look")
      T.Filter.SetQuality(2, false)
      advance()
      H.falsy(FB.filterButton.selected, "Suche/Qualitaet haben ihre eigenen Bedienelemente")
      H.falsy(FB.resetButton.uiOff, "aber 'x' ist frei")
      T.Filter.SetFavoritesOnly(true)
      advance()
      H.truthy(FB.filterButton.selected)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Menue-Reset bricht eine laufende Suchentprellung ab (kein spaeteres Nachtragen)", function()
      local T = boot()
      local FB = T.UI.FilterBar
      T.Filter.SetFavoritesOnly(true)
      advance()
      mock.Type(FB.search, "Look")      -- noch nicht uebernommen
      mock.Click(FB.filterButton)
      mock.Click(rowByText("Reset filters"))
      advance(0.6)
      H.eq(T.Filter.search, "")
      H.eq(FB.search:GetText(), "")
      H.eq(T.Filter.state.favoritesOnly, false)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Itemdaten treffen spaeter ein: Chips erscheinen erst dann (ITEMS_RESOLVED)", function()
      local T = boot({ noBar = true })
      for i = 1, 24 do mock.UncacheItem(2000 + i) end
      local parent = CreateFrame("Frame", nil, UIParent)
      parent:SetWidth(900)
      parent:SetHeight(300)
      parent:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      local FB = T.UI.FilterBar
      FB.Create(parent, function() end)
      FB.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
      FB.Layout(600)
      FB.Refresh(CHEST)
      H.deepEq(shownChips(FB), {}, "noch nichts aufgeloest")
      -- die Anfrage laeuft ueber Items (Grid/Filter stellen sie normalerweise)
      T.Items.RequestMany(CHEST_LIST)
      mock.Advance(2, 0.1)
      H.deepEq(shownChips(FB), { 0, 1, 2, 3, 4, 5, 6, 7 })
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ausgeblendete Qualitaet: Chip ist dunkler gefaerbt als ein sichtbarer", function()
      local T = boot()
      local FB = T.UI.FilterBar
      local chip = FB.chips[1]          -- weiss: alle Kanaele > 0
      local r, g, b = chip:GetBackdropColor()
      mock.Click(chip)
      local r2, g2, b2 = chip:GetBackdropColor()
      H.truthy(r2 < r and g2 < g and b2 < b, "abgedunkelt")
      local q = { T.Util.QualityColor(1) }
      H.near(r2, q[1] * 0.28, 1e-6)
      H.near(g2, q[2] * 0.28, 1e-6)
      H.near(b2, q[3] * 0.28, 1e-6)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Knopfbeschriftungen passen in ihre Knoepfe (alle Sortierungen, lange Sprachen)", function()
      local T = boot()
      local FB = T.UI.FilterBar
      T.Locale.Add("deDE", {
         SORT_QUALITY = "Qualitaet", SORT_NAME = "Name", SORT_ILEVEL = "Gegenstandsstufe",
         FILTER_SORT = "Sortierung: %s", FILTER_BUTTON = "Filter", FILTER_NEW = "Neu",
      })
      T.Locale.Add("ruRU", {
         SORT_QUALITY = "Качество", SORT_NAME = "Название", SORT_ILEVEL = "Уровень предмета",
         FILTER_SORT = "Сортировка: %s", FILTER_BUTTON = "Фильтры", FILTER_NEW = "Новинки",
      })
      local U = mock.U
      for _, loc in ipairs({ "enUS", "deDE", "ruRU" }) do
         T.Locale.Set(loc)
         advance()
         for _, key in ipairs({ "QUALITY", "NAME", "ILEVEL" }) do
            T.Filter.SetSort(key)
            advance()
            local label = FB.sortButton.label
            -- Beschriftung liegt 4 px vom Rand (links/rechts): Knopfbreite - 8 muss reichen
            H.truthy(U.textWidth(label) <= FB.sortButton:GetWidth() - 8 + 1e-6,
               loc .. " " .. key .. ": '" .. tostring(label:GetText()) .. "' passt in den Knopf")
         end
         H.truthy(U.textWidth(FB.filterButton.label) <= FB.filterButton:GetWidth() - 8 + 1e-6,
            loc .. ": Filter-Knopf")
         H.truthy(U.textWidth(FB.newChip.label) <= FB.newChip:GetWidth() - 8 + 1e-6, loc .. ": Neu")
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Unsichtbar: Eingaben melden onChange, zeichnen aber nichts (Notify)", function()
      local T = boot()
      local FB = T.UI.FilterBar
      advance()
      T.parent:Hide()
      local calls = 0
      local orig = T.Filter.Qualities
      T.Filter.Qualities = function(...)
         calls = calls + 1
         return orig(...)
      end
      FB.Create(T.parent, function() T.changes.n = T.changes.n + 1 end)
      FB.favChip:GetScript("OnClick")(FB.favChip, "LeftButton")
      H.eq(T.Filter.state.favoritesOnly, true)
      H.eq(T.changes.n, 1)
      H.eq(calls, 0, "versteckt: kein Abgleich")
      T.parent:Show()
      H.eq(calls, 1)
      H.truthy(FB.favChip.selected)
      T.Filter.Qualities = orig
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   H.section("Nachpruefung: Tastaturfokus des Suchfelds")
   -- =========================================================================

   -- In 3.3.5a verliert ein EditBox den Fokus bei Klicks auf andere Frames nicht:
   -- die Leiste gibt ihn bei ihren eigenen Klicks frei und bietet ReleaseFocus an.
   H.test("ReleaseFocus: nimmt dem Suchfeld den Fokus; die getippte Suche wird trotzdem uebernommen", function()
      local T = boot()
      local FB = T.UI.FilterBar
      H.eq(type(FB.ReleaseFocus), "function")
      FB.ReleaseFocus()                       -- ohne Fokus: harmlos
      H.falsy(FB.search:HasFocus())
      mock.Type(FB.search, "Look 07")
      H.truthy(FB.search:HasFocus())
      FB.ReleaseFocus()
      H.falsy(FB.search:HasFocus(), "Fokus frei")
      H.falsy(FB.search.focused, "Zustand der Huelle folgt (OnEditFocusLost)")
      H.eq(FB.search:GetText(), "Look 07", "Text bleibt stehen")
      advance(0.3)
      H.eq(T.Filter.search, "Look 07", "entprellte Suche wird uebernommen")
      H.eq(T.changes.n, 1, "genau ein onChange")
      -- noch einmal ohne Fokus: nichts
      FB.ReleaseFocus()
      advance(0.3)
      H.eq(T.changes.n, 1)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Fokus: Chips, Stern, Neu und Zuruecksetzen (x) der Leiste geben den Fokus frei", function()
      local T = boot()
      local FB = T.UI.FilterBar
      local q = shownChips(FB)[1]
      local targets = {
         { "Qualitaets-Chip", FB.chips[q] },
         { "Stern", FB.favChip },
         { "Neu", FB.newChip },
      }
      for _, t in ipairs(targets) do
         FB.search:SetFocus()
         H.truthy(FB.search:HasFocus(), t[1] .. ": Vorbedingung")
         mock.Click(t[2])
         H.falsy(FB.search:HasFocus(), t[1] .. ": Fokus frei")
      end
      -- Zuruecksetzen: Feld leer UND ohne Fokus (Tippen landet nicht mehr im Feld)
      mock.Type(FB.search, "zzz")
      advance(0.3)
      H.truthy(FB.resetButton:IsEnabled())
      FB.search:SetFocus()
      mock.Click(FB.resetButton)
      H.falsy(FB.search:HasFocus(), "x: Fokus frei")
      advance(0.3)
      H.eq(FB.search:GetText(), "")
      H.eq(T.Filter.search, "")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Fokus: Sortier- und Filtermenue nehmen den Fokus ebenfalls (Grabber des Menues)", function()
      local T = boot()
      local FB = T.UI.FilterBar
      for _, button in ipairs({ FB.sortButton, FB.filterButton }) do
         mock.Type(FB.search, "Look")
         H.truthy(FB.search:HasFocus())
         mock.Click(button)
         H.falsy(FB.search:HasFocus(), "Menue offen: Fokus nicht mehr im Suchfeld")
         mock.Escape()                        -- Menue schliessen
      end
      advance(0.3)
      H.eq(T.Filter.search, "Look", "die Eingabe ging nicht verloren")
      H.deepEq(H.takeErrors(), {})
   end)
end
