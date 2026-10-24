-- UI\Grid.lua  (T.UI.Grid)
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Raster der Aussehen (Hauptansicht des Items-Tabs).
--
-- Aufbau (SPEC 6.7 und 11):
--
--   Container (Frame, w x h)
--     raster   Rasterflaeche (w x h-30): Zellen ODER eine Meldung in der Mitte
--     pager    Blaetterleiste (30 px): << < > >>, "Seite x / y", Zaehler
--
--   Zelle (Button, Basis 92 x 126 bei Groesse 1.0)
--     DressUpModel (Template TransmogCellModelTemplate, 80f x 107f, lazy)
--     Name (1 Zeile, Qualitaetsfarbe), Qualitaetsstreifen, Stern, NEU-Marke,
--     Haken (angewendet); Rand und Marken liegen in einem Kind-Frame mit
--     hoeherem FrameLevel als das Modell (sonst deckt das Modell sie zu).
--
-- Datenfluss: Grid.SetSlot(slot) -> Grid.Refresh() = EIN Filter.Compute(slot),
-- synthetische Kacheln davor (Original, Verborgen), Filter.Page, Zellen. Ein
-- Modell wird nur neu angekleidet, wenn sich der Schluessel (Art, Slot, Item,
-- Groesse) der Zelle aendert oder Grid.Rebuild() es erzwingt.
--
-- Zustaende der Rasterflaeche (Grid.mode):
--   NO_SLOT, EMPTY, NEVER, ABSENT, LOADING (Liste oder Itemdaten), NO_ITEMS,
--   FILTERED, GRID. Nur in NO_ITEMS/FILTERED stehen die synthetischen Kacheln
--   (immer sichtbar) ueber der Meldung; sonst gibt es keine Zellen.
--
-- Seiten: Slot- und Filterwechsel beginnen auf Seite 1; Auswahl, Status,
-- Favoriten und eintreffende Itemdaten lassen die Seite stehen. Laedt die Liste
-- desselben Gegenstands neu (Meldung statt Raster), kehrt das Raster auf diese
-- Seite zurueck; ein anderer angelegter Gegenstand ist eine andere Liste und
-- beginnt vorn. Aendert sich die Kachelzahl je Seite (Fenster, Vorschaugroesse),
-- bleibt die erste Kachel der Seite sichtbar; erscheint oder verschwindet durch
-- einen Klick die Original-Kachel (alle Eintraege ruecken eine Stelle), folgt die
-- Seite der angeklickten Kachel.
--
-- Aktualisierung: nur sichtbar (frame:IsVisible()), gebuendelt ueber
-- Util.Debounce("ui-grid"); unsichtbar -> Dirty-Flag, Nachholen im OnShow.
--
-- Ankleidebudget: ein Zeichenvorgang kleidet hoechstens DRESS_BUDGET Modelle neu
-- an (SetUnit/Undress/TryOn laden je ein Spielermodell). Der Rest der Seite zeigt
-- zunaechst den Platzhalter (Name und Streifen stehen schon) und folgt in Schritten
-- ueber Util.Debounce("ui-grid-dress"): Draw ist wiederholbar, DressCell ueber-
-- springt Zellen mit passendem Schluessel. So bleibt ein Seitenwechsel im grossen
-- Fenster (bis 120 Zellen) ein Bild lang kurz, ohne Layout oder Obergrenze zu aendern.
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.UI = T.UI or {}

local Grid = T.UI.Grid or {}
T.UI.Grid = Grid

local Util, Events, DB, Slots, Items = T.Util, T.Events, T.DB, T.Slots, T.Items
local State, Filter, Net = T.State, T.Filter, T.Net
local Skin, Cameras = T.UI.Skin, T.UI.Cameras
local L = T.L
local COL = Skin.COL

local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs

-- ---------------------------------------------------------------------------
-- Konstanten
-- ---------------------------------------------------------------------------

local WHITE = "Interface\\Buttons\\WHITE8X8"
local STAR_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local CHECK_ICON = "Interface\\Buttons\\UI-CheckBox-Check"
-- Blizzards Dateiname ist falsch geschrieben (Invisibilty): nur diese Schreibweise
-- gibt es im Client, mit "Invisibility" zeigt 3.3.5a das Fehlstueck-Quadrat.
local HIDDEN_ICON = "Interface\\Icons\\Spell_Nature_Invisibilty"

local BASE_W, BASE_H = 92, 126        -- Zelle bei Vorschaugroesse 1.0
local MODEL_W, MODEL_H = 80, 107      -- Modell bei Vorschaugroesse 1.0
local GAP = 6                         -- Zellabstand
local PAD = 4                         -- Abstand des Modells zum oberen Zellenrand
local NAME_H = 12                     -- Namenszeile (eine Zeile)
local PAGER_H = 30                    -- Hoehe der Blaetterleiste
local MAX_PER_PAGE = 120              -- Obergrenze der Zellen (Modelle) je Seite
local EPS = 1e-6                      -- Rundungsschutz bei floor((w+gap)/(cell+gap))
local REFRESH_DELAY = 0.05            -- Buendelung der Ereignisse (Sekunden)
local DRESS_BUDGET = 16               -- hoechstens so viele Modelle je Zeichenvorgang neu ankleiden
local DRESS_DELAY = 0.03              -- Pause bis zum naechsten Schritt des Ankleidens (Sekunden)
local BTN_W, BTN_H, BTN_GAP = 26, 22, 3

local PREVIEW_SIZES = { 0.8, 1.0, 1.25, 1.5 }
local HIDDEN = T.HIDDEN_ID or 999999

local CELL_BG = { 0.095, 0.105, 0.13, 1 }

-- Oeffentliche Zustandsfelder (je Feld eine Zuweisung: die Schnittstellen-
-- pruefung tests/audit_api.lua erkennt nur einfache Zuweisungen)
Grid.w = 500                 -- Containerbreite (Layout)
Grid.h = 400                 -- Containerhoehe (Layout)
Grid.slot = nil              -- gewaehlter Server-Slot
Grid.page = 1                -- aktuelle Seite
Grid.pages = 1               -- Seitenzahl (mindestens 1)
Grid.perPage = 1             -- Kacheln je Seite (Spalten * Zeilen)
Grid.cols = 1
Grid.rows = 1
Grid.scale = 1.0             -- Vorschaugroesse (0.8 / 1.0 / 1.25 / 1.5)
Grid.cellW = BASE_W          -- Zellengroesse (92f x 126f)
Grid.cellH = BASE_H
Grid.modelW = MODEL_W        -- Modellgroesse (80f x 107f)
Grid.modelH = MODEL_H
Grid.mode = "NO_SLOT"        -- Zustand der Rasterflaeche (siehe Dateikopf)
Grid.GAP = GAP
Grid.PAGER_HEIGHT = PAGER_H
Grid.MAX_PER_PAGE = MAX_PER_PAGE
Grid.BASE_W = BASE_W
Grid.BASE_H = BASE_H
Grid.cells = {}              -- Zellen (Buttons), Index = Platz im Raster
Grid.reuseModels = false     -- true: Modelle zwischen Zellen verschieben (SetParent). AUS: im echten Client
                             -- verlieren verschobene Modelle Auskleidung und Kamera (Spieltest 2026-10-12)
Grid.frame = nil             -- Container (nach Create)
Grid.raster = nil
Grid.pager = nil
Grid.msgTitle = nil
Grid.msgHint = nil
Grid.msgBar = nil
Grid.msgFill = nil
Grid.resetButton = nil
Grid.pageButtons = nil
Grid.pageText = nil
Grid.countText = nil

-- Lokaler Zustand
local frame, raster, pager = nil, nil, nil
local msgTitle, msgHint, msgBar, msgFill, resetButton = nil, nil, nil, nil, nil
local pageButtons = {}
local pageText, countText, measureFS = nil, nil, nil
local cells = Grid.cells
local dirty = false
local laidOut = false
local loadedOnce = {}      -- [slot] = true: Raster wurde fuer den Slot schon gezeichnet
local hooked = false
local pageTextW = 80       -- Breite des Seitentexts (aus dem breitesten Text berechnet)
local shortPage = false    -- true: "2 / 9" statt "Page 2 / 9" (schmaler Container)
local keepFirst = nil      -- erste Kachel (Index) der Seite, die eine Meldung (Laden) verdraengt hat
local lastEq = {}          -- [slot] = ID des angelegten Gegenstands beim letzten Zeichnen
local drawnSyn = 0         -- Zahl der synthetischen Kacheln beim letzten Zeichnen
local fitMemo = {}         -- [Name] = gekuerzter Name (gueltig fuer die Breite fitMemoW)
local fitMemoW, fitMemoN = nil, 0

-- Leere Statistik (wie Filter.Compute, wenn es nichts zu zeigen gibt)
local function EmptyStats()
   return {
      total = 0, shown = 0, unresolved = 0, hiddenByFilter = 0,
      hiddenDuplicates = 0, resolved = 0, ready = false, version = 0,
   }
end
Grid.stats = EmptyStats()

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------

-- Vorschaugroesse aus den Einstellungen (nur 0.8 / 1.0 / 1.25 / 1.5)
local function PreviewScale()
   local g = DB.global
   local v = type(g) == "table" and tonumber(g.previewSize) or nil
   if not v or v ~= v then
      return 1.0
   end
   local best, dist = 1.0, math.huge
   for i = 1, #PREVIEW_SIZES do
      local d = abs(PREVIEW_SIZES[i] - v)
      if d < dist then
         best, dist = PREVIEW_SIZES[i], d
      end
   end
   return best
end

-- Einfarbige Flaeche (WHITE8X8 + Vertexfarbe)
local function NewTexture(parent, layer, c, alpha)
   local t = parent:CreateTexture(nil, layer or "ARTWORK")
   t:SetTexture(WHITE)
   if c then
      t:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
   end
   return t
end

-- Textbreite in Pixeln (GameFontHighlightSmall, ohne feste Breite)
local function TextWidth(text)
   if not measureFS then
      return 0
   end
   measureFS:SetText(text or "")
   local w = measureFS:GetStringWidth() or 0
   measureFS:SetText("")
   return w
end

-- Zahl mit Tausendertrenner
local function Num(n)
   return Util.FormatNumber(n)
end

-- Breite der Namenszeile einer Zelle
local function NameWidth()
   return max(8, Grid.cellW - 6)
end

-- Kuerzt einen Namen so, dass er mit "..." in maxW Pixel passt (Schnitt nur
-- zwischen UTF-8-Zeichen, nie ein Leerzeichen vor den Punkten). Passt er, bleibt
-- er unveraendert. Das Ergebnis gilt je Name und Breite und wird gemerkt.
local function FitName(text, maxW)
   if type(text) ~= "string" or text == "" then
      return ""
   end
   if fitMemoW ~= maxW or fitMemoN >= 2048 then
      fitMemo, fitMemoW, fitMemoN = {}, maxW, 0
   end
   local out = fitMemo[text]
   if out then
      return out
   end
   out = text
   if TextWidth(text) > maxW then
      -- Zeichenanfaenge (alles ausser UTF-8-Folgebytes); n Zeichen = Bytes 1..starts[n + 1] - 1
      local starts = {}
      for pos in string.gmatch(text, "()[^\128-\191]") do
         starts[#starts + 1] = pos
      end
      if #starts > 0 then
         -- groesstes n, fuer das n Zeichen plus "..." noch passen (n = 0: nur "...")
         local lo, hi = 0, #starts - 1
         while lo < hi do
            local mid = floor((lo + hi + 1) / 2)
            local cut = string.gsub(string.sub(text, 1, starts[mid + 1] - 1), "%s+$", "")
            if TextWidth(cut .. "...") <= maxW then
               lo = mid
            else
               hi = mid - 1
            end
         end
         local cut = string.gsub(string.sub(text, 1, starts[lo + 1] - 1), "%s+$", "")
         out = cut .. "..."
      end
   end
   fitMemo[text] = out
   fitMemoN = fitMemoN + 1
   return out
end

-- Nimmt dem Suchfeld der Filterleiste den Tastaturfokus. In 3.3.5a verliert ein
-- EditBox ihn bei Klicks auf andere Frames nicht; ohne das landeten Bewegungs-
-- und Aktionstasten nach einem Klick auf eine Kachel weiter im Suchfeld. Die
-- Leiste wird nach dem Raster geladen: darum spaet gebunden.
local function ReleaseSearchFocus()
   local fb = T.UI.FilterBar
   if fb and fb.ReleaseFocus then
      fb.ReleaseFocus()
   end
end

-- Item-Link fuer den Chat (nur echte Links; sonst aus Name und ID gebaut)
local function ChatLink(id, info)
   local link = info and info.link
   if type(link) == "string" and string.find(link, "|H", 1, true) then
      return link
   end
   local name = info and info.name or ("Item " .. tostring(id))
   return "|cffffffff|Hitem:" .. tostring(id) .. ":0:0:0:0:0:0:0:0|h[" .. tostring(name) .. "]|h|r"
end

-- Synthetische Kacheln des Slots (immer vor den Eintraegen, nie gefiltert):
-- Original (immer, damit die Reihenfolge beim Waehlen stabil bleibt), Verborgen
-- (nur verbergbare Slots).
local function BuildSynthetic(slot, pending, baseline)
   local out = {}
   out[#out + 1] = { kind = "original", id = 0 }
   if Slots.IsHideable(slot) then
      out[#out + 1] = { kind = "hidden", id = HIDDEN }
   end
   return out
end

-- Zustaende der Rasterflaeche, in denen es Kacheln und Seiten gibt.
local function IsPaging(mode)
   return mode == "GRID" or mode == "NO_ITEMS" or mode == "FILTERED"
end

-- ---------------------------------------------------------------------------
-- Favoriten
-- ---------------------------------------------------------------------------

-- Schaltet den Favoriten der Item-ID um und meldet FAVORITES_CHANGED.
function Grid.ToggleFavorite(id)
   id = tonumber(id)
   local char = DB.char
   if not id or type(char) ~= "table" then
      return false
   end
   if type(char.favorites) ~= "table" then
      char.favorites = {}
   end
   if char.favorites[id] then
      char.favorites[id] = nil
   else
      char.favorites[id] = true
   end
   Events.Fire("FAVORITES_CHANGED")
   return true
end

-- ---------------------------------------------------------------------------
-- Zellen
-- ---------------------------------------------------------------------------

-- Zeichnet Rand, Toenung und Marken einer Zelle nach ihrem Zustand.
-- Rangfolge: ausgewaehlt > angewendet > Hover > normal.
local function PaintCell(cell)
   local ov = cell.ov
   if not ov then
      return
   end
   local c, t = COL.buttonBorder, 1
   local tint, tintAlpha = nil, 0
   if cell.selected then
      c, t = COL.accent, 2
      tint, tintAlpha = COL.blue, cell.hover and 0.26 or 0.16
   elseif cell.applied then
      c, t = COL.pink, 2
      if cell.hover then
         tint, tintAlpha = COL.white, 0.07
      end
   elseif cell.hover then
      c, t = COL.accent, 1
      tint, tintAlpha = COL.white, 0.07
   end

   ov.edgeT:SetVertexColor(c[1], c[2], c[3], 1)
   ov.edgeB:SetVertexColor(c[1], c[2], c[3], 1)
   ov.edgeL:SetVertexColor(c[1], c[2], c[3], 1)
   ov.edgeR:SetVertexColor(c[1], c[2], c[3], 1)
   ov.edgeT:SetHeight(t)
   ov.edgeB:SetHeight(t)
   ov.edgeL:SetWidth(t)
   ov.edgeR:SetWidth(t)

   if tint then
      ov.tint:SetVertexColor(tint[1], tint[2], tint[3], tintAlpha)
      ov.tint:Show()
   else
      ov.tint:Hide()
   end

   -- Stern: Favorit immer, sonst nur als blasser Hinweis unter der Maus
   if cell.favorite then
      ov.star:SetAlpha(1)
      ov.star:Show()
   elseif cell.hover and cell.kind == "item" then
      ov.star:SetAlpha(0.35)
      ov.star:Show()
   else
      ov.star:Hide()
   end

   if cell.isNew then
      ov.newBg:Show()
      ov.newText:Show()
   else
      ov.newBg:Hide()
      ov.newText:Hide()
   end

   if cell.applied then
      ov.check:Show()
   else
      ov.check:Hide()
   end
end

-- Groessen und Anker aller Teile einer Zelle aus der aktuellen Vorschaugroesse.
local function SizeCell(cell)
   local cw, ch = Grid.cellW, Grid.cellH
   local mw, mh = Grid.modelW, Grid.modelH
   local mx = (cw - mw) / 2
   local ov = cell.ov
   cell:SetWidth(cw)
   cell:SetHeight(ch)

   if cell.model then
      cell.model:ClearAllPoints()
      cell.model:SetPoint("TOP", cell, "TOP", 0, -PAD)
      cell.model:SetWidth(mw)
      cell.model:SetHeight(mh)
   end

   ov.stripe:ClearAllPoints()
   ov.stripe:SetPoint("TOPLEFT", cell, "TOPLEFT", mx, -(PAD + mh - 2))
   ov.stripe:SetWidth(mw)
   ov.stripe:SetHeight(2)

   ov.name:ClearAllPoints()
   ov.name:SetPoint("BOTTOM", cell, "BOTTOM", 0, 1)
   ov.name:SetWidth(NameWidth())
   ov.name:SetHeight(NAME_H)

   ov.star:ClearAllPoints()
   ov.star:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -(mx + 2), -(PAD + 2))

   ov.newBg:ClearAllPoints()
   ov.newBg:SetPoint("TOPLEFT", cell, "TOPLEFT", mx + 2, -(PAD + 2))
   ov.newText:ClearAllPoints()
   ov.newText:SetPoint("CENTER", ov.newBg, "CENTER", 0, 0)

   ov.check:ClearAllPoints()
   ov.check:SetPoint("BOTTOMRIGHT", cell, "TOPLEFT", mx + mw - 2, -(PAD + mh - 4))

   local icon = max(20, min(mw, mh) * 0.42)
   ov.icon:ClearAllPoints()
   ov.icon:SetPoint("CENTER", cell, "TOPLEFT", cw / 2, -(PAD + mh / 2))
   ov.icon:SetWidth(icon)
   ov.icon:SetHeight(icon)

   ov.placeholder:ClearAllPoints()
   ov.placeholder:SetPoint("CENTER", cell, "TOPLEFT", cw / 2, -(PAD + mh / 2))
end

-- Breite der NEU-Marke aus dem Text (Sprache), Hoehe fest
local function SizeNewBadge(cell)
   local w = max(24, ceil(TextWidth(L.GRID_NEW)) + 8)
   cell.ov.newBg:SetWidth(w)
   cell.ov.newBg:SetHeight(12)
   cell.ov.newText:SetText(L.GRID_NEW)
end

-- Platz der Zelle im Raster (Zeile/Spalte aus dem Index, waagerecht zentriert).
local function PlaceCell(cell)
   local cols = max(1, Grid.cols)
   local cw, ch = Grid.cellW, Grid.cellH
   local used = cols * (cw + GAP) - GAP
   local x0 = max(0, floor((Grid.w - used) / 2))
   local c = (cell.index - 1) % cols
   local r = floor((cell.index - 1) / cols)
   cell:ClearAllPoints()
   cell:SetPoint("TOPLEFT", raster, "TOPLEFT", x0 + c * (cw + GAP), -(r * (ch + GAP)))
end

local OnCellClick, OnCellEnter, OnCellLeave, OnWheel, ShowCellTooltip

-- Legt die Zelle Nummer index an (einmalig); das Modell entsteht erst bei Bedarf.
local function CreateCell(index)
   local cell = CreateFrame("Button", nil, raster)
   cell.index = index
   cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
   cell:EnableMouse(true)
   cell:EnableMouseWheel(true)

   local bg = NewTexture(cell, "BACKGROUND", CELL_BG)
   bg:SetAllPoints(cell)
   cell.bg = bg

   -- Rand/Marken in einem Kind-Frame ueber dem Modell
   local ov = CreateFrame("Frame", nil, cell)
   ov:SetAllPoints(cell)
   ov:SetFrameLevel(cell:GetFrameLevel() + 8)
   ov:EnableMouse(false)
   cell.ov = ov

   -- Zeichenreihenfolge ohne Unterebenen (die gibt es in 3.3.5a nicht): Flaechen
   -- und Symbole in ARTWORK (nach Erzeugung), die vier Randlinien darueber in
   -- OVERLAY, alle Texte zuletzt ebenfalls in OVERLAY (nach den Randlinien erzeugt).
   ov.tint = NewTexture(ov, "ARTWORK", COL.white, 0)
   ov.tint:SetAllPoints(ov)
   ov.tint:Hide()

   ov.icon = ov:CreateTexture(nil, "ARTWORK")
   ov.icon:SetTexture(HIDDEN_ICON)
   Skin.TrimIcon(ov.icon)
   ov.icon:Hide()

   ov.stripe = NewTexture(ov, "ARTWORK", COL.grey)
   ov.stripe:Hide()

   ov.newBg = NewTexture(ov, "ARTWORK", { 0, 0, 0, 0.7 })
   ov.newBg:Hide()

   ov.star = ov:CreateTexture(nil, "ARTWORK")
   ov.star:SetTexture(STAR_ICON)
   ov.star:SetWidth(14)
   ov.star:SetHeight(14)
   ov.star:Hide()

   ov.check = ov:CreateTexture(nil, "ARTWORK")
   ov.check:SetTexture(CHECK_ICON)
   ov.check:SetWidth(18)
   ov.check:SetHeight(18)
   Skin.Desaturate(ov.check, true)
   ov.check:SetVertexColor(COL.green[1], COL.green[2], COL.green[3])
   ov.check:Hide()

   ov.edgeT = NewTexture(ov, "OVERLAY", COL.buttonBorder)
   ov.edgeT:SetPoint("TOPLEFT", ov, "TOPLEFT", 0, 0)
   ov.edgeT:SetPoint("TOPRIGHT", ov, "TOPRIGHT", 0, 0)
   ov.edgeB = NewTexture(ov, "OVERLAY", COL.buttonBorder)
   ov.edgeB:SetPoint("BOTTOMLEFT", ov, "BOTTOMLEFT", 0, 0)
   ov.edgeB:SetPoint("BOTTOMRIGHT", ov, "BOTTOMRIGHT", 0, 0)
   ov.edgeL = NewTexture(ov, "OVERLAY", COL.buttonBorder)
   ov.edgeL:SetPoint("TOPLEFT", ov, "TOPLEFT", 0, 0)
   ov.edgeL:SetPoint("BOTTOMLEFT", ov, "BOTTOMLEFT", 0, 0)
   ov.edgeR = NewTexture(ov, "OVERLAY", COL.buttonBorder)
   ov.edgeR:SetPoint("TOPRIGHT", ov, "TOPRIGHT", 0, 0)
   ov.edgeR:SetPoint("BOTTOMRIGHT", ov, "BOTTOMRIGHT", 0, 0)

   ov.placeholder = ov:CreateFontString(nil, "OVERLAY", "GameFontDisable")
   ov.placeholder:SetJustifyH("CENTER")
   ov.placeholder:SetText(L.GRID_PLACEHOLDER)
   ov.placeholder:Hide()

   ov.newText = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   ov.newText:SetTextColor(COL.green[1], COL.green[2], COL.green[3])
   ov.newText:SetText(L.GRID_NEW)
   ov.newText:Hide()

   ov.name = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   ov.name:SetJustifyH("CENTER")
   -- Namen ohne Leerzeichen (Chinesisch) brauchen den Umbruch ohne Leerzeichen
   if ov.name.SetNonSpaceWrap then ov.name:SetNonSpaceWrap(true) end
   ov.name:SetText("")

   cell:SetScript("OnClick", OnCellClick)
   cell:SetScript("OnEnter", OnCellEnter)
   cell:SetScript("OnLeave", OnCellLeave)
   cell:SetScript("OnMouseWheel", OnWheel)
   cell:SetScript("OnHide", function(self)
      -- OnLeave feuert beim Verbergen nicht zuverlaessig
      if self.hover then
         self.hover = false
         Skin.HideTooltip(self)
      end
   end)

   cell.hover = false
   SizeCell(cell)
   PlaceCell(cell)
   SizeNewBadge(cell)
   PaintCell(cell)
   return cell
end

-- Liefert Zelle Nummer index (legt sie bei Bedarf an).
local function EnsureCell(index)
   local cell = cells[index]
   if not cell then
      cell = CreateCell(index)
      cells[index] = cell
   end
   return cell
end

-- Das Modell der Zelle (lazy, nie mausaktiv: Klicks gehen an die Zelle).
local function EnsureModel(cell)
   local m = cell.model
   if m then
      return m
   end
   m = CreateFrame("DressUpModel", nil, cell, "TransmogCellModelTemplate")
   m:EnableMouse(false)
   m:SetPoint("TOP", cell, "TOP", 0, -PAD)
   m:SetWidth(Grid.modelW)
   m:SetHeight(Grid.modelH)
   cell.model = m
   return m
end

-- Haengt ein Modell an eine Zelle (nach dem Tausch zwischen Zellen).
local function AttachModel(model, cell)
   model:SetParent(cell)
   model:SetFrameLevel(cell:GetFrameLevel() + 1)
   model:ClearAllPoints()
   model:SetPoint("TOP", cell, "TOP", 0, -PAD)
   model:SetWidth(Grid.modelW)
   model:SetHeight(Grid.modelH)
end

-- Tauscht Modell und Schluessel zweier Zellen (kein Neuladen der Modelle).
local function SwapModels(a, b)
   a.model, b.model = b.model, a.model
   a.dressKey, b.dressKey = b.dressKey, a.dressKey
   if a.model then
      AttachModel(a.model, a)
   end
   if b.model then
      AttachModel(b.model, b)
   end
end

-- Schluessel des Ankleidens einer Kachel (nil: Kachel braucht kein Modell).
-- Art, Slot, Item und Vorschaugroesse; aendert er sich, wird neu angekleidet.
local function TileKey(tile, ctx)
   local kind = tile.kind or "item"
   if kind == "item" then
      if type(tile.info) == "table" then
         return "i:" .. ctx.slot .. ":" .. tile.id .. ":" .. Grid.scale
      end
   elseif kind == "original" then
      local eq = ctx.eq
      if type(eq) == "table" and eq.id then
         return "o:" .. ctx.slot .. ":" .. eq.id .. ":" .. Grid.scale
      end
   end
   return nil
end

-- Verteilt die bereits angekleideten Modelle auf die neuen Zellen der Seite:
-- verschiebt sich eine Kachel (z. B. weil die Original-Kachel davor erscheint),
-- wandert ihr Modell mit, statt neu geladen zu werden. Nur Zellen 1..n.
local function AssignModels(pageTiles, ctx)
   if not Grid.reuseModels then
      return
   end
   local holder = {}
   for i = 1, #cells do
      local c = cells[i]
      if c.dressKey and c.model then
         holder[c.dressKey] = c
      end
   end
   for i = 1, #pageTiles do
      local cell = EnsureCell(i)
      local key = TileKey(pageTiles[i], ctx)
      if key and cell.dressKey ~= key then
         local src = holder[key]
         if src and src ~= cell then
            local displaced = cell.dressKey
            SwapModels(cell, src)
            holder[key] = cell
            if displaced and cell.model then
               -- (cell hat jetzt das Modell von src; src das alte von cell)
               holder[displaced] = src
            end
         end
      end
   end
end

-- Kleidet das Zellenmodell an, aber nur wenn sich der Schluessel aendert. Jedes
-- echte Ankleiden kostet ein Stueck des Budgets (ctx.budget) dieses Zeichen-
-- vorgangs; ist es aufgebraucht, bleibt die Zelle ohne Modell (ctx.skipped zaehlt
-- sie, Draw plant den naechsten Schritt). Rueckgabe: false, wenn die Zelle kein
-- Modell zeigt; dann steht der Platzhalter da. Ein altes Modell bleibt nie unter
-- dem Namen einer anderen Kachel sichtbar.
local function DressCell(cell, slotDef, itemId, equipLoc, key, ctx)
   if cell.dressKey == key and cell.model then
      cell.model:Show()
      return true
   end
   if ctx.budget <= 0 then
      if cell.model then
         cell.model:Hide()
      end
      cell.dressKey = nil
      ctx.skipped = ctx.skipped + 1
      return false
   end
   ctx.budget = ctx.budget - 1
   local model = EnsureModel(cell)
   cell.dressKey = key
   model:Show()
   Cameras.Dress(model, slotDef, itemId, equipLoc, T.race)
   return true
end

-- Setzt die Zelle auf "leer" zurueck und versteckt sie.
local function HideCell(cell)
   cell.tile, cell.kind, cell.itemId = nil, nil, nil
   cell.selected, cell.applied, cell.favorite, cell.isNew = false, false, false, false
   if cell.hover then
      cell.hover = false
      Skin.HideTooltip(cell)
   end
   if cell.model then
      cell.model:Hide()
   end
   cell.dressKey = nil
   cell:Hide()
end

-- Zeigt eine Kachel in der Zelle. ctx = { slot, slotDef, pending, wanted,
-- baseline, eq, nameW, budget, skipped } (einmal je Zeichenvorgang berechnet;
-- budget/skipped siehe DressCell).
local function ShowTile(cell, tile, ctx)
   local kind = tile.kind or "item"
   local ov = cell.ov
   cell.tile, cell.kind = tile, kind
   cell.itemId = (kind == "item") and tile.id or nil
   -- sichtbar machen, BEVOR das Modell geladen wird (ein verstecktes Modell laedt
   -- nicht zuverlaessig)
   cell:Show()

   ov.icon:Hide()
   ov.placeholder:Hide()
   ov.stripe:Hide()
   ov.name:SetTextColor(COL.text[1], COL.text[2], COL.text[3])

   if kind == "item" then
      local info = tile.info
      cell.selected = (tile.wanted == true) and ctx.pending
      cell.applied = tile.applied == true
      cell.favorite = tile.favorite == true
      cell.isNew = tile.isNew == true
      if type(info) ~= "table" then
         -- ohne Itemdaten: dunkler Platzhalter, die Daten werden angefordert
         Items.Request(tile.id)
         if cell.model then
            cell.model:Hide()
         end
         cell.dressKey = nil
         ov.placeholder:Show()
         ov.name:SetText("")
      else
         local r, g, b = Util.QualityColor(info.quality)
         ov.name:SetText(FitName(info.name, ctx.nameW))
         ov.name:SetTextColor(r, g, b)
         ov.stripe:SetVertexColor(r, g, b, 1)
         ov.stripe:Show()
         if not DressCell(cell, ctx.slotDef, tile.id, info.equipLoc, TileKey(tile, ctx), ctx) then
            ov.placeholder:Show()
         end
      end
   elseif kind == "original" then
      local eq = ctx.eq
      cell.selected = ctx.pending and ctx.wanted == 0
      -- ohne angewendete Transmogrifikation ist "Original" der aktuelle Zustand
      cell.applied = ctx.baseline == 0
      cell.favorite, cell.isNew = false, false
      ov.name:SetText(FitName(L.GRID_ORIGINAL, ctx.nameW))
      if type(eq) == "table" and eq.id then
         if eq.quality then
            local r, g, b = Util.QualityColor(eq.quality)
            ov.stripe:SetVertexColor(r, g, b, 1)
            ov.stripe:Show()
         end
         if not DressCell(cell, ctx.slotDef, eq.id, eq.equipLoc, TileKey(tile, ctx), ctx) then
            ov.placeholder:Show()
         end
      elseif cell.model then
         cell.model:Hide()
         cell.dressKey = nil
      end
   else
      -- Verborgen: flache Kachel mit Symbol, kein Modell
      cell.selected = ctx.pending and ctx.wanted == HIDDEN
      cell.applied = ctx.baseline == HIDDEN
      cell.favorite, cell.isNew = false, false
      ov.name:SetText(FitName(L.GRID_HIDDEN, ctx.nameW))
      if cell.model then
         cell.model:Hide()
      end
      cell.dressKey = nil
      ov.icon:Show()
   end

   PaintCell(cell)
   if cell.hover then
      -- der Inhalt wechselt unter der Maus (Seitenwechsel, Mausrad)
      ShowCellTooltip(cell)
   end
end

-- ---------------------------------------------------------------------------
-- Tooltip und Klicks
-- ---------------------------------------------------------------------------

-- Baut den Tooltip der Zelle auf (Item-Tooltip + eigene Zeilen).
ShowCellTooltip = function(cell)
   local tile, kind = cell.tile, cell.kind
   if not tile or not GameTooltip then
      return
   end
   local slot = Grid.slot
   GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")

   local dim = COL.dim
   if kind == "item" then
      pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(tile.id))
   elseif kind == "original" then
      local eq = slot ~= nil and State.Equipped(slot) or nil
      if eq and eq.id then
         pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(eq.id))
      end
      GameTooltip:AddLine(L.GRID_ORIGINAL_TITLE, COL.accent[1], COL.accent[2], COL.accent[3])
      GameTooltip:AddLine(L.GRID_ORIGINAL_TIP, dim[1], dim[2], dim[3], true)
   else
      GameTooltip:AddLine(L.GRID_HIDDEN, 1, 1, 1)
      GameTooltip:AddLine(L.GRID_HIDDEN_TIP, dim[1], dim[2], dim[3], true)
   end

   if cell.applied then
      GameTooltip:AddLine(L.GRID_TIP_APPLIED, COL.pink[1], COL.pink[2], COL.pink[3])
   end
   if cell.selected then
      GameTooltip:AddLine(L.GRID_TIP_SELECTED, COL.blue[1], COL.blue[2], COL.blue[3])
   end
   if cell.favorite then
      GameTooltip:AddLine(L.GRID_TIP_FAVORITE, COL.yellow[1], COL.yellow[2], COL.yellow[3])
   end
   if cell.isNew then
      GameTooltip:AddLine(L.GRID_TIP_NEW, COL.green[1], COL.green[2], COL.green[3])
   end

   -- Der 3.3.5-Client zeigt eine anprobierte Einhandwaffe immer in der Haupthand
   local offDef = Slots.BY_KEY and Slots.BY_KEY.OFFHAND
   if kind == "item" and offDef and slot == offDef.server and type(tile.info) == "table"
         and tile.info.equipLoc == "INVTYPE_WEAPON" then
      GameTooltip:AddLine(L.GRID_TIP_OFFHAND_PREVIEW, dim[1], dim[2], dim[3], true)
   end

   -- Bedienhinweise
   if cell.selected then
      GameTooltip:AddLine(L.GRID_TIP_LEFT_DISCARD, dim[1], dim[2], dim[3])
   else
      GameTooltip:AddLine(L.GRID_TIP_LEFT_SELECT, dim[1], dim[2], dim[3])
   end
   if kind == "item" then
      GameTooltip:AddLine(L.GRID_TIP_RIGHT_FAV, dim[1], dim[2], dim[3])
   end
   if kind ~= "hidden" then
      GameTooltip:AddLine(L.GRID_TIP_SHIFT_LINK, dim[1], dim[2], dim[3])
   end
   GameTooltip:Show()
end

OnCellEnter = function(self)
   self.hover = true
   PaintCell(self)
   ShowCellTooltip(self)
end

OnCellLeave = function(self)
   self.hover = false
   PaintCell(self)
   Skin.HideTooltip(self)
end

-- Item-Link der Kachel in den Chat einfuegen; true, wenn etwas eingefuegt wurde.
local function InsertLink(cell)
   local tile, kind = cell.tile, cell.kind
   if not tile or type(ChatEdit_InsertLink) ~= "function" then
      return false
   end
   local link
   if kind == "item" then
      link = ChatLink(tile.id, tile.info)
   elseif kind == "original" and Grid.slot ~= nil then
      local eq = State.Equipped(Grid.slot)
      if eq and eq.id then
         local info = Items.Info(eq.id)
         link = (type(eq.link) == "string" and string.find(eq.link, "|H", 1, true)) and eq.link
            or ChatLink(eq.id, info)
      end
   end
   if not link then
      return false
   end
   return ChatEdit_InsertLink(link) and true or false
end

-- Erscheint oder verschwindet durch eine Auswahl die Original-Kachel, rutschen
-- alle Eintraege um eine Stelle. Damit die angeklickte Kachel nicht auf eine
-- andere Seite wegrutscht, folgt die Seite ihr (pos = Kachelindex vor dem Klick,
-- synBefore = Zahl der synthetischen Kacheln vor dem Klick).
local function FollowShift(pos, synBefore, slot)
   if not IsPaging(Grid.mode) then
      return
   end
   local now = #BuildSynthetic(slot, State.HasPending(slot), State.Baseline(slot))
   local delta = now - synBefore
   if delta == 0 then
      return
   end
   local newPos = max(1, pos + delta)
   Grid.page = floor((newPos - 1) / max(1, Grid.perPage)) + 1
end

-- Klick auf eine Zelle: links waehlen/verwerfen, rechts Favorit, Shift-Link.
OnCellClick = function(self, button)
   ReleaseSearchFocus()
   local tile, kind, slot = self.tile, self.kind, Grid.slot
   if not tile or slot == nil then
      return
   end

   if button == "RightButton" then
      if kind == "item" then
         Grid.ToggleFavorite(tile.id)
      end
      return
   end

   if IsModifiedClick("CHATLINK") and kind ~= "hidden" then
      InsertLink(self)
      return
   end

   local id
   if kind == "item" then
      id = tile.id
   elseif kind == "original" then
      id = 0
   else
      id = HIDDEN
   end
   local pos = (Grid.page - 1) * Grid.perPage + (self.index or 1)
   local synBefore = drawnSyn
   if State.HasPending(slot) and State.Wanted(slot) == id then
      State.Discard(slot)
   else
      State.Select(slot, id)
   end
   FollowShift(pos, synBefore, slot)
end

-- Mausrad: nach oben = vorherige Seite, nach unten = naechste
OnWheel = function(_, delta)
   delta = tonumber(delta) or 0
   if delta > 0 then
      Grid.Page(-1)
   elseif delta < 0 then
      Grid.Page(1)
   end
end

-- ---------------------------------------------------------------------------
-- Meldungen in der Rasterflaeche
-- ---------------------------------------------------------------------------

-- Versteckt Meldung, Balken und Knopf.
local function HideMessage()
   msgTitle:Hide()
   msgHint:Hide()
   msgBar:Hide()
   resetButton:Hide()
end

-- Zeigt eine zentrierte Meldung in der Rasterflaeche unterhalb von areaTop.
--   title/hint  Texte (hint optional)
--   progress    0..1 zeigt einen duennen Balken, nil keinen
--   button      true zeigt "Filter zuruecksetzen"
local function ShowMessage(title, hint, progress, button, areaTop)
   local w = Grid.w
   local rasterH = max(1, Grid.h - PAGER_H)
   areaTop = areaTop or 0
   local blockW = max(40, min(440, w - 40))

   msgTitle:SetWidth(blockW)
   msgTitle:SetText(title or "")
   msgTitle:Show()
   local th = msgTitle:GetStringHeight() or 14
   if th < 12 then
      th = 12
   end

   local hh = 0
   if hint and hint ~= "" then
      msgHint:SetWidth(blockW)
      msgHint:SetText(hint)
      hh = msgHint:GetStringHeight() or 12
      if hh < 10 then
         hh = 10
      end
      msgHint:Show()
   else
      msgHint:SetText("")
      msgHint:Hide()
   end

   local total = th
   if hh > 0 then
      total = total + 6 + hh
   end
   if progress then
      total = total + 14 + 6
   end
   if button then
      total = total + 12 + 24
   end

   local areaH = max(0, rasterH - areaTop)
   local top = areaTop + max(0, floor((areaH - total) / 2))

   msgTitle:ClearAllPoints()
   msgTitle:SetPoint("TOP", raster, "TOP", 0, -top)
   local y = top + th
   if hh > 0 then
      msgHint:ClearAllPoints()
      msgHint:SetPoint("TOP", raster, "TOP", 0, -(y + 6))
      y = y + 6 + hh
   end

   if progress then
      local trackW = max(20, min(280, blockW))
      msgBar:SetWidth(trackW)
      msgBar:ClearAllPoints()
      msgBar:SetPoint("TOP", raster, "TOP", 0, -(y + 14))
      local frac = max(0, min(1, progress))
      local fillW = floor((trackW - 2) * frac)
      if fillW >= 1 then
         msgFill:SetWidth(fillW)
         msgFill:Show()
      else
         msgFill:Hide()
      end
      msgBar:Show()
      y = y + 14 + 6
   else
      msgBar:Hide()
   end

   if button then
      resetButton:ClearAllPoints()
      resetButton:SetPoint("TOP", raster, "TOP", 0, -(y + 12))
      resetButton:Show()
   else
      resetButton:Hide()
   end
end

-- ---------------------------------------------------------------------------
-- Blaetterleiste
-- ---------------------------------------------------------------------------

-- Waehlt aus Textvarianten (breit -> schmal) die erste, die in avail passt.
local function PickText(variants, avail)
   for i = 1, #variants do
      if TextWidth(variants[i]) <= avail then
         return variants[i]
      end
   end
   return variants[#variants]
end

-- Texte und Zustand der Blaetterleiste aus Grid.page/pages/stats/mode.
local function UpdatePager()
   if not pager then
      return
   end
   local page, pages = Grid.page, Grid.pages
   local mode = Grid.mode
   local active = IsPaging(mode)

   pageButtons.first:SetEnabledState(active and page > 1)
   pageButtons.prev:SetEnabledState(active and page > 1)
   pageButtons.next:SetEnabledState(active and page < pages)
   pageButtons.last:SetEnabledState(active and page < pages)

   if active then
      pageText:SetText(Util.Format(shortPage and L.GRID_PAGE_SHORT or L.GRID_PAGE, page, pages))
      local stats = Grid.stats
      -- "(filtered)" nur bei echten Filtern (die der Spieler mit "x" aufhebt);
      -- ausgeblendete Duplikate (Standard!) bekommen ihren eigenen Hinweis.
      local full
      if (stats.hiddenByFilter or 0) > 0 then
         full = Util.Format(L.GRID_COUNT_FILTERED, Num(stats.shown), Num(stats.total))
      elseif (stats.hiddenDuplicates or 0) > 0 then
         full = Util.Format(L.GRID_COUNT_DUPES, Num(stats.shown), Num(stats.total),
            Num(stats.hiddenDuplicates))
      else
         full = Util.Format(L.GRID_COUNT, Num(stats.shown), Num(stats.total))
      end
      local short = Util.Format(L.GRID_COUNT_SHORT, Num(stats.shown), Num(stats.total))
      local avail = countText:GetWidth() or 0
      countText:SetText(PickText({ full, short }, avail))
   else
      pageText:SetText("")
      countText:SetText("")
   end
end

-- Positioniert die Blaetterleiste (aus Grid.w).
local function LayoutPager()
   local x = 0
   local order = { "first", "prev", "next", "last" }
   for i = 1, #order do
      local b = pageButtons[order[i]]
      b:ClearAllPoints()
      b:SetPoint("LEFT", pager, "LEFT", x, 0)
      x = x + BTN_W + BTN_GAP
   end
   -- Seitentext: lang, solange daneben noch ein brauchbarer Zaehler passt
   local longW = max(40, ceil(TextWidth(Util.Format(L.GRID_PAGE, 999, 999))) + 4)
   local shortW = max(24, ceil(TextWidth(Util.Format(L.GRID_PAGE_SHORT, 999, 999))) + 4)
   local counterMin = ceil(TextWidth(Util.Format(L.GRID_COUNT_SHORT, "9,999", "9,999"))) + 8
   local free = Grid.w - (x + 5) - 8
   shortPage = free < longW + counterMin + 40
   pageTextW = shortPage and shortW or longW
   pageText:ClearAllPoints()
   pageText:SetPoint("LEFT", pager, "LEFT", x + 5, 0)
   pageText:SetWidth(pageTextW)
   local used = x + 5 + pageTextW + 8
   countText:ClearAllPoints()
   countText:SetPoint("RIGHT", pager, "RIGHT", -2, 0)
   countText:SetWidth(max(8, Grid.w - used))
end

-- ---------------------------------------------------------------------------
-- Aktualisierung
-- ---------------------------------------------------------------------------

-- Anzahl der noch unaufgeloesten Item-IDs der Liste, die weder fertig noch
-- aufgegeben (Items.IsFailed) sind: nur sie halten den Ladezustand.
local function CountPending(ids)
   local n = 0
   if type(ids) ~= "table" then
      return 0
   end
   for i = 1, #ids do
      local id = ids[i]
      if Items.Info(id) == nil and not Items.IsFailed(id) then
         n = n + 1
      end
   end
   return n
end

-- Setzt den Anzeigezustand zurueck (keine Zellen sichtbar).
local function ClearCells()
   for i = 1, #cells do
      HideCell(cells[i])
   end
end

local POLL_DELAY = 0.5   -- Neubewertung im Ladezustand der Itemdaten (Sekunden)

-- Zeichnet die Rasterflaeche neu: ein Filter.Compute, Kacheln, Seite, Zustand.
local function Draw()
   local slot = Grid.slot
   local mode = "NO_SLOT"
   local entries, stats = nil, EmptyStats()
   local list = nil
   local loadN, loadM = 0, 0
   local poll = false

   if slot ~= nil then
      -- ein anderer angelegter Gegenstand heisst eine andere Liste: zurueck auf Seite 1
      local eq = State.Equipped(slot)
      local eqId = (type(eq) == "table" and eq.id) or 0
      if lastEq[slot] ~= nil and lastEq[slot] ~= eqId then
         Grid.page, keepFirst = 1, nil
      end
      lastEq[slot] = eqId

      local ss = State.SlotState(slot)
      if ss == "EMPTY" then
         mode = "EMPTY"
      elseif ss == "NEVER" then
         mode = "NEVER"
      else
         list = State.List(slot)
         if Net.state == "ABSENT" and not list.ready then
            mode = "ABSENT"
         else
            entries, stats = Filter.Compute(slot)
            if not list.ready then
               mode = "LOADING"
               loadN = list.received or 0
               loadM = max(list.amount or 0, loadN)
               loadedOnce[slot] = nil
            else
               local pendingItems = 0
               if stats.unresolved > 0 then
                  pendingItems = CountPending(list.ids)
               end
               if stats.unresolved > 0 and pendingItems > 0
                  and not (loadedOnce[slot] and stats.shown > 0) then
                  mode = "LOADING"
                  loadN = stats.resolved
                  loadM = stats.resolved + stats.unresolved
                  poll = true
               elseif stats.shown == 0 then
                  if (stats.hiddenByFilter or 0) > 0 then
                     mode = "FILTERED"
                  else
                     mode = "NO_ITEMS"
                  end
               else
                  mode = "GRID"
               end
            end
         end
      end
   end

   Grid.mode = mode
   Grid.stats = stats

   -- Aufgegebene Items melden kein Ereignis: solange Itemdaten ausstehen, wird
   -- regelmaessig neu bewertet, damit der Ladezustand nie ewig stehen bleibt.
   if poll then
      Util.Debounce("ui-grid-poll", POLL_DELAY, Grid.Refresh)
   end

   -- Meldungen ohne Zellen
   if not IsPaging(mode) then
      Util.Cancel("ui-grid-dress")
      ClearCells()
      -- die Seite merken (Liste laedt neu): danach geht es dort weiter
      if Grid.page > 1 then
         keepFirst = (Grid.page - 1) * max(1, Grid.perPage) + 1
      end
      Grid.page, Grid.pages = 1, 1
      drawnSyn = 0
      if mode == "NO_SLOT" then
         ShowMessage(L.GRID_NO_SLOT, L.GRID_NO_SLOT_HINT, nil, false, 0)
      elseif mode == "EMPTY" then
         ShowMessage(L.GRID_EMPTY_SLOT, L.GRID_EMPTY_SLOT_HINT, nil, false, 0)
      elseif mode == "NEVER" then
         ShowMessage(L.GRID_NEVER, L.GRID_NEVER_HINT, nil, false, 0)
      elseif mode == "ABSENT" then
         ShowMessage(L.GRID_ABSENT, L.GRID_ABSENT_HINT, nil, false, 0)
      else
         if loadM > 0 then
            ShowMessage(Util.Format(L.GRID_LOADING, Num(loadN), Num(loadM)), L.GRID_LOADING_HINT,
               loadN / loadM, false, 0)
         else
            -- Gesamtzahl noch unbekannt: kein "0 / 0", kein Balken
            ShowMessage(L.GRID_LOADING_PLAIN, L.GRID_LOADING_HINT, nil, false, 0)
         end
      end
      UpdatePager()
      return
   end

   -- Kacheln: synthetische zuerst, dann die gefilterten Eintraege
   local pending = State.HasPending(slot)
   local baseline = State.Baseline(slot)
   local tiles = BuildSynthetic(slot, pending, baseline)
   local nSynthetic = #tiles
   if mode == "GRID" then
      for i = 1, #entries do
         tiles[#tiles + 1] = entries[i]
      end
   end

   local want = Grid.page
   if keepFirst then
      want = floor((keepFirst - 1) / max(1, Grid.perPage)) + 1
      keepFirst = nil
   end
   local pageTiles, pages, page = Filter.Page(tiles, want, Grid.perPage)
   Grid.page, Grid.pages = page, pages
   drawnSyn = nSynthetic

   local ctx = {
      slot = slot,
      slotDef = Slots.BY_SERVER[slot],
      pending = pending,
      wanted = State.Wanted(slot),
      baseline = baseline,
      eq = State.Equipped(slot),
      nameW = NameWidth() - 1,      -- ein Pixel Luft: der Umbruch rechnet knapp
      budget = DRESS_BUDGET,
      skipped = 0,
   }
   AssignModels(pageTiles, ctx)
   for i = 1, #pageTiles do
      ShowTile(EnsureCell(i), pageTiles[i], ctx)
   end
   for i = #pageTiles + 1, #cells do
      HideCell(cells[i])
   end
   -- Reicht das Budget nicht, kleiden die naechsten Schritte den Rest an: ein
   -- Seitenwechsel in einem grossen Fenster laedt nicht 100 Modelle in einem Bild.
   if ctx.skipped > 0 then
      Util.Debounce("ui-grid-dress", DRESS_DELAY, Grid.Refresh)
   else
      Util.Cancel("ui-grid-dress")
   end

   if mode == "GRID" then
      loadedOnce[slot] = true
      HideMessage()
   elseif mode == "NO_ITEMS" then
      local top = nSynthetic > 0 and (Grid.cellH + GAP) or 0
      ShowMessage(L.GRID_NO_ITEMS, L.GRID_NO_ITEMS_HINT, nil, false, top)
   else
      local top = nSynthetic > 0 and (Grid.cellH + GAP) or 0
      ShowMessage(L.GRID_FILTERED, L.GRID_FILTERED_HINT, nil, true, top)
   end
   UpdatePager()
end

-- Zeichnet die Liste des aktuellen Slots neu (sofort; nur wenn sichtbar,
-- sonst wird es im OnShow nachgeholt).
function Grid.Refresh()
   if not frame then
      return
   end
   if not frame:IsVisible() then
      dirty = true
      return
   end
   dirty = false
   Draw()
end

-- Anforderung aus einem Ereignis: gebuendelt und nur wenn sichtbar.
local function RequestRefresh()
   if not frame then
      return
   end
   if frame:IsVisible() then
      Util.Debounce("ui-grid", REFRESH_DELAY, Grid.Refresh)
   else
      dirty = true
   end
end

-- ---------------------------------------------------------------------------
-- Seiten, Slot, Layout
-- ---------------------------------------------------------------------------

-- Springt auf Seite n (wird auf 1..pages geklemmt) und zeichnet neu.
function Grid.SetPage(n)
   n = floor(tonumber(n) or 1)
   if not frame or not frame:IsVisible() then
      -- unsichtbar: nur vormerken, beim Zeigen wird auf die Seitenzahl geklemmt
      Grid.page = max(1, n)
      keepFirst = nil
      dirty = true
      return
   end
   if not IsPaging(Grid.mode) then
      return   -- Meldung statt Raster: es gibt keine Seiten (die gemerkte bleibt)
   end
   local pages = max(1, Grid.pages or 1)
   if n < 1 then
      n = 1
   elseif n > pages then
      n = pages
   end
   if n == Grid.page then
      return
   end
   Grid.page = n
   Grid.Refresh()
end

-- Blaettert um dir Seiten (nur das Vorzeichen zaehlt: -1 zurueck, +1 vor).
function Grid.Page(dir)
   dir = tonumber(dir) or 0
   if dir > 0 then
      Grid.SetPage(Grid.page + 1)
   elseif dir < 0 then
      Grid.SetPage(Grid.page - 1)
   end
end

-- Wechselt den Slot (nil = keiner): Seite 1, Itemdaten der Liste anfordern.
function Grid.SetSlot(slot)
   slot = tonumber(slot)
   Grid.slot = slot
   Grid.page = 1
   keepFirst = nil
   if slot ~= nil then
      local list = State.List(slot)
      local ids = type(list) == "table" and list.ids or nil
      if type(ids) == "table" and #ids > 0 then
         local copy = {}
         for i = 1, #ids do
            copy[i] = ids[i]
         end
         Items.RequestMany(copy)
      end
   end
   Grid.Refresh()
end

-- Verwirft die Ankleide-Schluessel aller Zellen: das naechste Zeichnen laedt
-- alle Modelle neu (SetUnit, Auskleiden, Anprobe, Kamera).
function Grid.InvalidateModels()
   for i = 1, #cells do
      cells[i].dressKey = nil
   end
end

-- Alle Modelle neu ankleiden lassen (nach Groessen-/Scale-Aenderung).
function Grid.Rebuild()
   Grid.InvalidateModels()
   Grid.Refresh()
end

-- Berechnet Zellgroesse, Spalten, Zeilen, Zellen pro Seite und ordnet alles an.
-- w x h ist die Groesse des Containers (Raster + Blaetterleiste).
function Grid.Layout(w, h)
   w, h = tonumber(w), tonumber(h)
   if not w or w ~= w or w < 1 then
      w = Grid.w
   end
   if not h or h ~= h or h < 1 then
      h = Grid.h
   end
   w, h = max(1, w), max(1, h)
   Grid.w, Grid.h = w, h
   local wasLaidOut, oldPerPage = laidOut, Grid.perPage

   local f = PreviewScale()
   local cw, ch = BASE_W * f, BASE_H * f
   local rasterH = max(1, h - PAGER_H)
   local cols = max(1, floor((w + GAP) / (cw + GAP) + EPS))
   local rows = max(1, floor((rasterH + GAP) / (ch + GAP) + EPS))
   if cols * rows > MAX_PER_PAGE then
      rows = max(1, floor(MAX_PER_PAGE / cols))
      if cols > MAX_PER_PAGE then
         cols = MAX_PER_PAGE
      end
   end
   local perPage = cols * rows

   local changed = (not laidOut) or perPage ~= Grid.perPage or cols ~= Grid.cols
      or f ~= Grid.scale
   local rescaled = (f ~= Grid.scale)

   Grid.scale = f
   Grid.cellW, Grid.cellH = cw, ch
   Grid.modelW, Grid.modelH = MODEL_W * f, MODEL_H * f
   Grid.cols, Grid.rows, Grid.perPage = cols, rows, perPage
   laidOut = true

   -- andere Kachelzahl je Seite: die erste sichtbare Kachel bleibt sichtbar
   if wasLaidOut and perPage ~= oldPerPage and Grid.page > 1 then
      local first = (Grid.page - 1) * max(1, oldPerPage) + 1
      Grid.page = floor((first - 1) / perPage) + 1
   end

   if not frame then
      return
   end

   frame:SetWidth(w)
   frame:SetHeight(h)
   raster:SetWidth(w)
   raster:SetHeight(rasterH)
   pager:SetWidth(w)
   pager:SetHeight(PAGER_H)

   -- Zellen: Groesse und Platz im Raster (waagerecht zentriert)
   for i = 1, #cells do
      local cell = cells[i]
      if rescaled then
         SizeCell(cell)
         cell.dressKey = nil
      end
      PlaceCell(cell)
   end

   LayoutPager()
   if changed then
      Grid.Refresh()
   else
      UpdatePager()
      if Grid.mode ~= "GRID" then
         -- Breite/Hoehe geaendert, Raster gleich: Meldung neu zentrieren
         if frame:IsVisible() then
            Draw()
         else
            dirty = true
         end
      end
   end
end

-- ---------------------------------------------------------------------------
-- Texte
-- ---------------------------------------------------------------------------

-- Setzt alle statischen Texte neu (Sprachwechsel).
function Grid.ApplyLocale()
   if not frame then
      return
   end
   fitMemoW = nil
   pageButtons.first.tip = L.GRID_PAGE_FIRST
   pageButtons.prev.tip = L.GRID_PAGE_PREV
   pageButtons.next.tip = L.GRID_PAGE_NEXT
   pageButtons.last.tip = L.GRID_PAGE_LAST
   resetButton:SetLabel(L.GRID_RESET_FILTERS)
   for i = 1, #cells do
      cells[i].ov.placeholder:SetText(L.GRID_PLACEHOLDER)
      SizeNewBadge(cells[i])
   end
   LayoutPager()
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

-- Ereignis, das nur den aktuellen Slot betrifft (slot == nil: alle).
local function ForSlot(slot)
   return slot == nil or Grid.slot == nil or slot == Grid.slot
end

local function OnListEvent(slot)
   if ForSlot(slot) then
      RequestRefresh()
   end
end

local function OnAnyChange()
   RequestRefresh()
end

local function OnFilterChanged()
   Grid.page = 1
   keepFirst = nil
   RequestRefresh()
end

local function OnSettingsChanged(key)
   if key == "previewSize" then
      Grid.Layout(Grid.w, Grid.h)
   end
end

local function OnLocaleChanged()
   Grid.ApplyLocale()
   RequestRefresh()
end

-- Meldet die Ereignisse an (einmalig).
local function HookEvents()
   if hooked then
      return
   end
   hooked = true
   Events.On("LIST_PROGRESS", OnListEvent, Grid)
   Events.On("LIST_READY", OnListEvent, Grid)
   Events.On("WANTED_CHANGED", OnListEvent, Grid)
   Events.On("EQUIPMENT_CHANGED", OnListEvent, Grid)
   Events.On("ITEMS_RESOLVED", OnAnyChange, Grid)
   Events.On("STATUS_CHANGED", OnAnyChange, Grid)
   Events.On("FAVORITES_CHANGED", OnAnyChange, Grid)
   Events.On("COLLECTION_UPDATED", OnAnyChange, Grid)
   Events.On("SERVER_STATE", OnAnyChange, Grid)
   Events.On("FILTER_CHANGED", OnFilterChanged, Grid)
   Events.On("SETTINGS_CHANGED", OnSettingsChanged, Grid)
   Events.On("LOCALE_CHANGED", OnLocaleChanged, Grid)
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

-- Baut Container, Rasterflaeche, Meldungen und Blaetterleiste (einmalig).
-- Weitere Aufrufe liefern denselben Container. Rueckgabe: der Container.
function Grid.Create(parent)
   if frame then
      return frame
   end

   frame = CreateFrame("Frame", nil, parent or UIParent)
   frame:SetWidth(Grid.w)
   frame:SetHeight(Grid.h)
   frame:EnableMouseWheel(true)
   frame:SetScript("OnMouseWheel", OnWheel)
   frame:SetScript("OnShow", function()
      -- Ein verborgenes Modell verliert im Client Auskleidung und Kamera (Tab-Wechsel,
      -- Fenster zu/auf): beim Zeigen alles neu ankleiden.
      Grid.InvalidateModels()
      Grid.Refresh()
   end)
   Grid.frame = frame

   raster = CreateFrame("Frame", nil, frame)
   raster:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
   raster:SetWidth(Grid.w)
   raster:SetHeight(max(1, Grid.h - PAGER_H))
   raster:EnableMouseWheel(true)
   raster:SetScript("OnMouseWheel", OnWheel)
   Grid.raster = raster

   -- Messfeld fuer Textbreiten (unsichtbar)
   measureFS = raster:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
   measureFS:SetPoint("TOPLEFT", raster, "TOPLEFT", 0, 0)
   measureFS:SetAlpha(0)

   -- Meldung: Titel, Hinweis, Balken, Knopf
   msgTitle = raster:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   msgTitle:SetJustifyH("CENTER")
   if msgTitle.SetNonSpaceWrap then msgTitle:SetNonSpaceWrap(true) end
   msgTitle:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
   msgTitle:SetText("")
   msgTitle:Hide()

   msgHint = raster:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   msgHint:SetJustifyH("CENTER")
   if msgHint.SetNonSpaceWrap then msgHint:SetNonSpaceWrap(true) end
   msgHint:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
   msgHint:SetText("")
   msgHint:Hide()

   msgBar = CreateFrame("Frame", nil, raster)
   msgBar:SetHeight(6)
   msgBar:SetWidth(200)
   Skin.Backdrop(msgBar, COL.field, COL.border)
   msgFill = NewTexture(msgBar, "ARTWORK", COL.accent, 0.9)
   msgFill:SetPoint("TOPLEFT", msgBar, "TOPLEFT", 1, -1)
   msgFill:SetHeight(4)
   msgFill:SetWidth(1)
   msgBar:Hide()

   resetButton = Skin.Button(raster, 170, 24, L.GRID_RESET_FILTERS, function()
      ReleaseSearchFocus()
      Filter.Reset()
   end)
   resetButton:Hide()

   -- Blaetterleiste
   pager = CreateFrame("Frame", nil, frame)
   pager:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
   pager:SetWidth(Grid.w)
   pager:SetHeight(PAGER_H)
   pager:EnableMouseWheel(true)
   pager:SetScript("OnMouseWheel", OnWheel)
   Grid.pager = pager

   local line = Skin.Divider(pager)
   line:SetPoint("TOPLEFT", pager, "TOPLEFT", 0, 0)
   line:SetPoint("TOPRIGHT", pager, "TOPRIGHT", 0, 0)

   pageButtons.first = Skin.Button(pager, BTN_W, BTN_H, "<<", function()
      ReleaseSearchFocus()
      Grid.SetPage(1)
   end)
   pageButtons.prev = Skin.Button(pager, BTN_W, BTN_H, "<", function()
      ReleaseSearchFocus()
      Grid.Page(-1)
   end)
   pageButtons.next = Skin.Button(pager, BTN_W, BTN_H, ">", function()
      ReleaseSearchFocus()
      Grid.Page(1)
   end)
   pageButtons.last = Skin.Button(pager, BTN_W, BTN_H, ">>", function()
      ReleaseSearchFocus()
      Grid.SetPage(Grid.pages)
   end)

   pageText = pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   pageText:SetHeight(14)
   pageText:SetJustifyH("LEFT")
   pageText:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
   pageText:SetText("")

   countText = pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   countText:SetHeight(14)
   countText:SetJustifyH("RIGHT")
   countText:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
   countText:SetText("")

   Grid.msgTitle = msgTitle
   Grid.msgHint = msgHint
   Grid.msgBar = msgBar
   Grid.msgFill = msgFill
   Grid.resetButton = resetButton
   Grid.pageButtons = pageButtons
   Grid.pageText = pageText
   Grid.countText = countText

   -- Methoden auch als Frame-Felder (Doppelpunkt-Aufruf)
   frame.Layout = function(_, w, h) return Grid.Layout(w, h) end
   frame.SetSlot = function(_, slot) return Grid.SetSlot(slot) end
   frame.Refresh = function() return Grid.Refresh() end
   frame.SetPage = function(_, n) return Grid.SetPage(n) end
   frame.Page = function(_, dir) return Grid.Page(dir) end

   HookEvents()
   Grid.ApplyLocale()
   Grid.Layout(Grid.w, Grid.h)
   return frame
end
