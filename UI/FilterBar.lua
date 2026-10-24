-- UI\FilterBar.lua  (T.UI.FilterBar)
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Filterleiste ueber dem Raster (SPEC 6.8 und 11).
--
-- Feste Hoehe 58 = 4 + 24 + 6 + 24 (zwei Zeilen zu je 24 px, 6 px Abstand):
--
--   Zeile 1:  [ Suchfeld (flexibel) ] [Sortierung] [Filter] [x]
--   Zeile 2:  [Q][Q][Q][Q]  ...                       [Neu] [Stern]
--
--   * Das Suchfeld ist der einzige flexible Teil; die Knoepfe behalten ihre
--     (am Text gemessene) Breite. Bis w = 398 (Mindestfenster) ueberlappt
--     nichts; die Schnellschalter in Zeile 2 werden ausgeblendet, wenn sie
--     nicht mehr neben die Qualitaets-Chips passen.
--   * Alle Aenderungen laufen ueber die Setter von T.Filter (sie feuern
--     FILTER_CHANGED selbst); der onChange-Rueckruf von Create wird danach
--     zusaetzlich gerufen.
--   * Ein Klick auf Chip, Knopf oder (ueber FilterBar.ReleaseFocus) Kachel nimmt
--     dem Suchfeld den Tastaturfokus: 3.3.5a laesst ihn sonst bis Enter/Esc stehen.
--   * Das Suchfeld wirkt entprellt (0.2 s). Die Typ-Liste des Filtermenues
--     wird beim Oeffnen aus Filter.Types(slot) gebaut; die Haken lassen das
--     Menue offen, "Zuruecksetzen" im Menue folgt dem Filterzustand mit.
--   * Abweichung von SPEC 6.8 (Platz bei 398 px): Typ-Knopf und "Doppelte
--     ausblenden" stehen im Menue des Filter-Knopfs, nicht als eigene Elemente.
--
-- Aktualisierung: nur sichtbar, gebuendelt ueber Util.Debounce("ui-filterbar");
-- unsichtbar -> Dirty-Flag, Nachholen im OnShow.
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.UI = T.UI or {}

local FilterBar = T.UI.FilterBar or {}
T.UI.FilterBar = FilterBar

local Util, Events = T.Util, T.Events
local Filter = T.Filter
local Skin = T.UI.Skin
local L = T.L
local COL = Skin.COL

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

-- ---------------------------------------------------------------------------
-- Konstanten
-- ---------------------------------------------------------------------------

local STAR_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local RESET_GLYPH = "x"

local HEIGHT = 58
local PAD_TOP = 4
local ROW_H = 24
local ROW_GAP = 6
local GAP = 6                 -- waagerechter Abstand in Zeile 1
local CHIP = 20               -- Qualitaets-Chip (Quadrat)
local CHIP_GAP = 4
local RESET_W = 24
local STAR_W = 24
local MIN_SEARCH = 40         -- Mindestbreite des Suchfelds
local SEARCH_DELAY = 0.2      -- Entprellung der Suche (Sekunden)
local REFRESH_DELAY = 0.05
local QUALITY_MAX = 7

FilterBar.HEIGHT = HEIGHT
FilterBar.w = 398
FilterBar.slot = nil
FilterBar.chips = {}

-- Lokaler Zustand
local bar = nil
local search, sortButton, filterButton, resetButton = nil, nil, nil, nil
local favChip, newChip, measureFS = nil, nil, nil
local chips = FilterBar.chips
local onChangeFn = nil
local dirty = false
local hooked = false
local pendingSearch = false
local shownChips = {}        -- Reihenfolge der sichtbaren Qualitaets-Chips (Qualitaeten)
local sortWidth, filterWidth, newWidth = 90, 56, 40
local UpdateAll              -- vorwaerts (unten definiert)

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------

-- Textbreite (GameFontHighlightSmall, wie die Knopfbeschriftung)
local function TextWidth(text)
   if not measureFS then
      return 0
   end
   measureFS:SetText(text or "")
   local w = measureFS:GetStringWidth() or 0
   measureFS:SetText("")
   return w
end

-- Aktiver Sortierschluessel (gueltig, sonst QUALITY)
local function CurrentSort()
   local key = Filter.state.sort
   local sorts = Filter.SORTS
   for i = 1, #sorts do
      if sorts[i] == key then
         return key
      end
   end
   return "QUALITY"
end

-- Beschriftung des Sortierknopfs ("Sortierung: Qualitaet").
local function SortLabel(key)
   return Util.Format(L.FILTER_SORT, Filter.SortLabel(key))
end

-- Nach einer Aenderung durch den Spieler: Leiste sofort nachziehen (die
-- Ereignisse kommen erst gebuendelt) und den onChange-Rueckruf melden (geschuetzt).
local function Notify()
   if bar and UpdateAll then
      if bar:IsVisible() then
         UpdateAll()
      else
         dirty = true
      end
   end
   local fn = onChangeFn
   if type(fn) == "function" then
      local ok, err = pcall(fn)
      if not ok then
         local handler = geterrorhandler and geterrorhandler()
         if type(handler) == "function" then
            pcall(handler, err)
         end
      end
   end
end

-- Hat das Filtermenue (ausser Duplikate/Sortierung) einen aktiven Wert?
local function MenuFilterActive()
   local f = Filter.state
   if f.favoritesOnly or f.newOnly then
      return true
   end
   for _, v in pairs(f.typesOff) do
      if v then
         return true
      end
   end
   return false
end

-- ---------------------------------------------------------------------------
-- Menues
-- ---------------------------------------------------------------------------

-- Eintraege des Sortiermenues: je Schluessel ein Radio-Eintrag.
function FilterBar.BuildSortMenu()
   local items = {}
   local current = CurrentSort()
   local sorts = Filter.SORTS
   for i = 1, #sorts do
      local key = sorts[i]
      items[#items + 1] = {
         text = Filter.SortLabel(key),
         checked = (key == current),
         radio = true,
         sortKey = key,
         onClick = function()
            Filter.SetSort(key)
            Notify()
         end,
      }
   end
   return items
end

-- Leerzeile als Trenner im Menue (Skin.Menu kennt keinen eigenen Typ).
local function Separator()
   return { text = "", disabled = true, separator = true }
end

-- Eintraege des Filtermenues (Duplikate, Favoriten, Neu, Typen, Zuruecksetzen).
-- Die Haken lassen das Menue offen; der Eintrag "Zuruecksetzen" wird dabei
-- nachgefuehrt (frei, sobald irgendein Filter aktiv ist).
function FilterBar.BuildFilterMenu()
   local items = {}
   local f = Filter.state
   local resetItem = nil

   -- Nach einer Aenderung im offenen Menue: Zuruecksetzen-Eintrag nachziehen
   local function SyncReset()
      if resetItem then
         resetItem.disabled = not Filter.IsActive()
      end
   end

   items[#items + 1] = {
      text = L.FILTER_HIDE_DUPLICATES,
      checked = f.hideDuplicates ~= false,
      keepOpen = true,
      -- Titel + umbrochene Erlaeuterung (eine einzelne lange Zeile wuerde den Tooltip sprengen)
      tip = { L.FILTER_HIDE_DUPLICATES, L.FILTER_HIDE_DUPLICATES_TIP },
      onClick = function(item)
         item.checked = not item.checked
         Filter.SetHideDuplicates(item.checked)
         Notify()
      end,
   }
   items[#items + 1] = {
      text = L.FILTER_FAVORITES_ONLY,
      checked = f.favoritesOnly and true or false,
      keepOpen = true,
      onClick = function(item)
         item.checked = not item.checked
         Filter.SetFavoritesOnly(item.checked)
         SyncReset()
         Notify()
      end,
   }
   items[#items + 1] = {
      text = L.FILTER_NEW_ONLY,
      checked = f.newOnly and true or false,
      keepOpen = true,
      onClick = function(item)
         item.checked = not item.checked
         Filter.SetNewOnly(item.checked)
         SyncReset()
         Notify()
      end,
   }

   local slot = FilterBar.slot
   local types = slot ~= nil and Filter.Types(slot) or {}
   if #types > 0 then
      items[#items + 1] = Separator()
      items[#items + 1] = { text = L.FILTER_TYPE_TITLE, isTitle = true }
      for i = 1, #types do
         local t = types[i]
         local off = f.typesOff[t.typeKey] == true
         items[#items + 1] = {
            text = Util.Format(L.FILTER_TYPE_ROW, t.label, t.count),
            checked = t.own or not off,
            disabled = t.own and true or false,
            reason = t.own and L.FILTER_TYPE_OWN or nil,
            keepOpen = true,
            typeKey = t.typeKey,
            onClick = function(item)
               item.checked = not item.checked
               Filter.SetType(t.typeKey, item.checked)
               SyncReset()
               Notify()
            end,
         }
      end
   end

   items[#items + 1] = Separator()
   resetItem = {
      text = L.FILTER_RESET,
      disabled = not Filter.IsActive(),
      reset = true,
      onClick = function()
         Util.Cancel("ui-filterbar-search")
         pendingSearch = false
         Filter.Reset()
         Notify()
      end,
   }
   items[#items + 1] = resetItem
   return items
end

-- ---------------------------------------------------------------------------
-- Qualitaets-Chips
-- ---------------------------------------------------------------------------

-- Faerbt einen Chip nach Qualitaet, Sichtbarkeit und Hover.
local function PaintChip(chip)
   local r, g, b = Util.QualityColor(chip.quality)
   local hidden = Filter.state.qualities[chip.quality] == false
   chip.hiddenQuality = hidden
   local bg, bd
   if hidden then
      bg = { r * 0.28, g * 0.28, b * 0.28, 1 }
      bd = COL.buttonBorder
      chip:SetAlpha(0.7)
   else
      bg = { r * 0.9, g * 0.9, b * 0.9, 1 }
      bd = { min(1, r + 0.3), min(1, g + 0.3), min(1, b + 0.3), 1 }
      chip:SetAlpha(1)
   end
   if chip.hover then
      bd = COL.accent
   end
   chip:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
   chip:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4] or 1)
end

-- Tooltip eines Chips: Qualitaetsname (Farbe), Anzahl, Klickhinweis.
local function ShowChipTip(chip)
   local r, g, b = Util.QualityColor(chip.quality)
   local dim = COL.dim
   Skin.Tooltip(chip, "ANCHOR_RIGHT", {
      { Filter.QualityLabel(chip.quality), r, g, b },
      { Util.Format(L.FILTER_QUALITY_COUNT, chip.count or 0), 0.78, 0.81, 0.86 },
      { chip.hiddenQuality and L.FILTER_QUALITY_SHOW or L.FILTER_QUALITY_HIDE, dim[1], dim[2], dim[3] },
   })
end

-- Legt den Chip der Qualitaet q an (einmalig).
local function EnsureChip(q)
   local chip = chips[q]
   if chip then
      return chip
   end
   chip = CreateFrame("Button", nil, bar)
   chip:SetWidth(CHIP)
   chip:SetHeight(CHIP)
   Skin.Backdrop(chip, COL.button, COL.buttonBorder)
   chip:RegisterForClicks("LeftButtonUp")
   chip.quality = q
   chip.count = 0
   chip.hover = false
   chip:SetScript("OnEnter", function(self)
      self.hover = true
      PaintChip(self)
      ShowChipTip(self)
   end)
   chip:SetScript("OnLeave", function(self)
      self.hover = false
      PaintChip(self)
      Skin.HideTooltip(self)
   end)
   chip:SetScript("OnHide", function(self)
      self.hover = false
      Skin.HideTooltip(self)
   end)
   chip:SetScript("OnClick", function(self)
      FilterBar.ReleaseFocus()
      local visible = Filter.state.qualities[self.quality] ~= false
      Filter.SetQuality(self.quality, not visible)
      PaintChip(self)
      if self.hover then
         ShowChipTip(self)
      end
      Notify()
   end)
   chips[q] = chip
   PaintChip(chip)
   return chip
end

-- ---------------------------------------------------------------------------
-- Anordnung
-- ---------------------------------------------------------------------------

-- Misst die Knopfbreiten aus den Texten der aktuellen Sprache. Der Sortierknopf
-- ist so breit wie der laengste der drei Namen (kein Springen beim Wechsel);
-- die Breiten haengen nie von der Leistenbreite ab.
local function MeasureButtons()
   local w = 0
   local sorts = Filter.SORTS
   for i = 1, #sorts do
      w = max(w, TextWidth(SortLabel(sorts[i])))
   end
   sortWidth = max(60, ceil(w) + 20)
   filterWidth = max(56, ceil(TextWidth(L.FILTER_BUTTON)) + 20)
   newWidth = max(36, ceil(TextWidth(L.FILTER_NEW)) + 16)
end

-- Zeile 1: Suchfeld links (flexibel), rechts Sortierung, Filter, Zuruecksetzen.
local function LayoutRow1()
   local w = FilterBar.w
   MeasureButtons()

   local resetX = max(0, w - RESET_W)
   local filterX = max(0, resetX - GAP - filterWidth)
   local sortX = max(0, filterX - GAP - sortWidth)
   local searchW = max(MIN_SEARCH, sortX - GAP)

   search:ClearAllPoints()
   search:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -PAD_TOP)
   search:SetWidth(searchW)
   search:SetHeight(ROW_H)

   sortButton:ClearAllPoints()
   sortButton:SetPoint("TOPLEFT", bar, "TOPLEFT", sortX, -PAD_TOP)
   sortButton:SetWidth(sortWidth)
   sortButton:SetHeight(ROW_H)
   sortButton:SetLabel(SortLabel(CurrentSort()))

   filterButton:ClearAllPoints()
   filterButton:SetPoint("TOPLEFT", bar, "TOPLEFT", filterX, -PAD_TOP)
   filterButton:SetWidth(filterWidth)
   filterButton:SetHeight(ROW_H)

   resetButton:ClearAllPoints()
   resetButton:SetPoint("TOPLEFT", bar, "TOPLEFT", resetX, -PAD_TOP)
   resetButton:SetWidth(RESET_W)
   resetButton:SetHeight(ROW_H)
end

-- Zeile 2: Qualitaets-Chips links, Schnellschalter rechts (nur wenn sie passen).
local function LayoutRow2()
   local w = FilterBar.w
   local y = -(PAD_TOP + ROW_H + ROW_GAP + floor((ROW_H - CHIP) / 2))

   local x = 0
   for i = 1, #shownChips do
      local chip = chips[shownChips[i]]
      chip:ClearAllPoints()
      chip:SetPoint("TOPLEFT", bar, "TOPLEFT", x, y)
      x = x + CHIP + CHIP_GAP
   end
   local leftEnd = (#shownChips > 0) and (x - CHIP_GAP) or 0

   local starX = max(0, w - STAR_W)
   local newX = max(0, starX - CHIP_GAP - newWidth)
   local limit = leftEnd + (leftEnd > 0 and 8 or 0)

   favChip:ClearAllPoints()
   favChip:SetPoint("TOPLEFT", bar, "TOPLEFT", starX, y)
   favChip:SetWidth(STAR_W)
   favChip:SetHeight(CHIP)
   newChip:ClearAllPoints()
   newChip:SetPoint("TOPLEFT", bar, "TOPLEFT", newX, y)
   newChip:SetWidth(newWidth)
   newChip:SetHeight(CHIP)

   -- passt der Stern nicht neben die Chips, entfaellt alles; passt "Neu" nicht, nur dieses
   local showFav = (starX >= limit)
   local showNew = showFav and (newX >= limit)
   if showFav then
      favChip:Show()
   else
      favChip:Hide()
   end
   if showNew then
      newChip:Show()
   else
      newChip:Hide()
   end
end

-- ---------------------------------------------------------------------------
-- Aktualisierung
-- ---------------------------------------------------------------------------

-- Gleicht die Qualitaets-Chips mit Filter.Qualities(slot) ab.
local function UpdateChips()
   local slot = FilterBar.slot
   local qualities = slot ~= nil and Filter.Qualities(slot) or {}
   local want = {}
   local order = {}
   for i = 1, #qualities do
      local q = tonumber(qualities[i].quality)
      if q and q >= 0 and q <= QUALITY_MAX and not want[q] then
         want[q] = qualities[i].count or 0
         order[#order + 1] = q
      end
   end
   table.sort(order)

   for q = 0, QUALITY_MAX do
      local chip = chips[q]
      if want[q] ~= nil then
         chip = EnsureChip(q)
         chip.count = want[q]
         PaintChip(chip)
         chip:Show()
      elseif chip then
         chip:Hide()
      end
   end
   shownChips = order
end

-- Zustand der Schalter aus Filter.state (Knoepfe, Chips, Suchfeld).
local function UpdateControls()
   local f = Filter.state

   sortButton:SetLabel(SortLabel(CurrentSort()))
   filterButton:SetSelected(MenuFilterActive())

   local active = Filter.IsActive()
   resetButton:SetEnabledState(active, L.FILTER_RESET_NONE)

   favChip:SetSelected(f.favoritesOnly and true or false)
   newChip:SetSelected(f.newOnly and true or false)

   -- Suchfeld nachziehen (z. B. nach "Filter zuruecksetzen" im Raster), nie
   -- waehrend eine eigene Eingabe noch nicht uebernommen wurde
   if not pendingSearch then
      local text = Filter.search or ""
      if search:GetText() ~= text then
         search:SetText(text)
      end
   end
end

-- Alles neu: Chips, Schalter, Anordnung von Zeile 2.
UpdateAll = function()
   dirty = false
   UpdateChips()
   UpdateControls()
   LayoutRow2()
end

-- Aktualisiert die Leiste fuer den Slot (nil = keiner); ohne Argument bleibt der
-- zuletzt gemerkte Slot. Sofort, aber nur wenn sichtbar (sonst Nachholen im OnShow).
function FilterBar.Refresh(...)
   if select("#", ...) > 0 then
      FilterBar.slot = (...)
   end
   if not bar then
      return
   end
   if not bar:IsVisible() then
      dirty = true
      return
   end
   UpdateAll()
end

-- Anordnung nach Breite w (Hoehe ist fest 58).
function FilterBar.Layout(w)
   w = tonumber(w)
   if not w or w ~= w or w < 1 then
      w = FilterBar.w
   end
   FilterBar.w = w
   if not bar then
      return
   end
   bar:SetWidth(w)
   bar:SetHeight(HEIGHT)
   LayoutRow1()
   LayoutRow2()
end

-- Anforderung aus einem Ereignis: gebuendelt, nur wenn sichtbar.
local function RequestRefresh()
   if not bar then
      return
   end
   if bar:IsVisible() then
      Util.Debounce("ui-filterbar", REFRESH_DELAY, function()
         FilterBar.Refresh()
      end)
   else
      dirty = true
   end
end

-- ---------------------------------------------------------------------------
-- Eingaben
-- ---------------------------------------------------------------------------

-- Uebernimmt den Suchtext (nach der Entprellung).
local function CommitSearch()
   pendingSearch = false
   if not search then
      return
   end
   Filter.SetSearch(search:GetText() or "")
   Notify()
end

-- Suchfeld: nur Eingaben des Spielers zaehlen, entprellt.
local function OnSearchChanged(_, userInput)
   if not userInput then
      return
   end
   pendingSearch = true
   Util.Debounce("ui-filterbar-search", SEARCH_DELAY, CommitSearch)
end

-- Nimmt dem Suchfeld den Tastaturfokus (Klick auf Kachel, Slot, Knopf, Chip).
-- In 3.3.5a verliert ein EditBox den Fokus bei Klicks auf andere Frames nicht;
-- ohne das landeten Bewegungs- und Aktionstasten weiter im Suchfeld. ClearFocus
-- feuert weder OnEnterPressed noch OnTextChanged: der entprellte Suchtext wird
-- trotzdem uebernommen. Ohne Fokus tut die Funktion nichts.
function FilterBar.ReleaseFocus()
   if search and search:HasFocus() then
      search:ClearFocus()
   end
end

local function OpenSortMenu()
   Skin.Menu.Open(sortButton, FilterBar.BuildSortMenu(), { width = sortWidth })
end

local function OpenFilterMenu()
   Skin.Menu.Open(filterButton, FilterBar.BuildFilterMenu(), { width = 200 })
end

local function OnResetClick()
   FilterBar.ReleaseFocus()
   Util.Cancel("ui-filterbar-search")
   pendingSearch = false
   Filter.Reset()
   Notify()
end

-- ---------------------------------------------------------------------------
-- Texte, Ereignisse
-- ---------------------------------------------------------------------------

-- Setzt alle statischen Texte neu (Sprachwechsel) und ordnet neu an.
function FilterBar.ApplyLocale()
   if not bar then
      return
   end
   search:SetPlaceholder(L.FILTER_SEARCH_PLACEHOLDER)
   filterButton:SetLabel(L.FILTER_BUTTON)
   newChip:SetLabel(L.FILTER_NEW)
   sortButton.tip = { L.FILTER_SORT_TIP, L.FILTER_SORT_TIP_HINT }
   filterButton.tip = { L.FILTER_BUTTON_TIP }
   resetButton.tip = { L.FILTER_RESET_TIP }
   LayoutRow1()
   LayoutRow2()
end

-- Ereignis, das nur den aktuellen Slot betrifft (slot == nil: alle).
local function OnSlotEvent(slot)
   if slot == nil or FilterBar.slot == nil or slot == FilterBar.slot then
      RequestRefresh()
   end
end

local function OnAnyEvent()
   RequestRefresh()
end

local function OnLocaleChanged()
   FilterBar.ApplyLocale()
   RequestRefresh()
end

-- Meldet die Ereignisse an (einmalig).
local function HookEvents()
   if hooked then
      return
   end
   hooked = true
   Events.On("FILTER_CHANGED", OnAnyEvent, FilterBar)
   Events.On("LIST_READY", OnSlotEvent, FilterBar)
   Events.On("ITEMS_RESOLVED", OnAnyEvent, FilterBar)
   Events.On("EQUIPMENT_CHANGED", OnSlotEvent, FilterBar)
   Events.On("LOCALE_CHANGED", OnLocaleChanged, FilterBar)
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

-- Baut die Leiste (einmalig; weitere Aufrufe liefern dieselbe und setzen nur
-- einen neuen onChange-Rueckruf). onChange() wird nach jeder Aenderung durch
-- den Spieler gerufen. Rueckgabe: der Container-Frame.
function FilterBar.Create(parent, onChange)
   if type(onChange) == "function" then
      onChangeFn = onChange
   end
   if bar then
      return bar
   end

   bar = CreateFrame("Frame", nil, parent or UIParent)
   bar:SetWidth(FilterBar.w)
   bar:SetHeight(HEIGHT)
   bar.height = HEIGHT
   bar:SetScript("OnShow", function()
      if dirty then
         UpdateAll()
      end
   end)
   FilterBar.frame = bar

   -- Messfeld fuer Textbreiten (unsichtbar)
   measureFS = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
   measureFS:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
   measureFS:SetAlpha(0)

   -- Zeile 1
   search = Skin.EditBox(bar, 200, ROW_H, L.FILTER_SEARCH_PLACEHOLDER, OnSearchChanged)
   FilterBar.search = search

   sortButton = Skin.Button(bar, sortWidth, ROW_H, "", OpenSortMenu)
   FilterBar.sortButton = sortButton
   filterButton = Skin.Button(bar, filterWidth, ROW_H, L.FILTER_BUTTON, OpenFilterMenu)
   FilterBar.filterButton = filterButton
   resetButton = Skin.Button(bar, RESET_W, ROW_H, RESET_GLYPH, OnResetClick)
   FilterBar.resetButton = resetButton

   -- Zeile 2: Schnellschalter (Chips der Qualitaeten entstehen bei Bedarf)
   favChip = Skin.Button(bar, STAR_W, CHIP, "", function()
      FilterBar.ReleaseFocus()
      Filter.SetFavoritesOnly(not Filter.state.favoritesOnly)
      Notify()
   end)
   favChip:SetIcon(STAR_ICON, 14, true)
   favChip.tip = function(tooltip)
      local on = Filter.state.favoritesOnly and true or false
      local dim = COL.dim
      tooltip:AddLine(L.FILTER_FAVORITES_CHIP, 1, 1, 1)
      tooltip:AddLine(L.FILTER_FAVORITES_CHIP_TIP, 0.78, 0.81, 0.86, true)
      tooltip:AddLine(on and L.FILTER_CHIP_ON or L.FILTER_CHIP_OFF, dim[1], dim[2], dim[3])
   end
   FilterBar.favChip = favChip

   newChip = Skin.Button(bar, newWidth, CHIP, L.FILTER_NEW, function()
      FilterBar.ReleaseFocus()
      Filter.SetNewOnly(not Filter.state.newOnly)
      Notify()
   end)
   newChip.tip = function(tooltip)
      local on = Filter.state.newOnly and true or false
      local dim = COL.dim
      tooltip:AddLine(L.FILTER_NEW, 1, 1, 1)
      tooltip:AddLine(L.FILTER_NEW_TIP, 0.78, 0.81, 0.86, true)
      tooltip:AddLine(on and L.FILTER_CHIP_ON or L.FILTER_CHIP_OFF, dim[1], dim[2], dim[3])
   end
   FilterBar.newChip = newChip

   -- Methoden auch als Frame-Felder (Doppelpunkt-Aufruf)
   bar.Layout = function(_, w) return FilterBar.Layout(w) end
   bar.Refresh = function(_, ...) return FilterBar.Refresh(...) end

   HookEvents()
   FilterBar.ApplyLocale()
   FilterBar.Layout(FilterBar.w)
   UpdateAll()
   return bar
end
