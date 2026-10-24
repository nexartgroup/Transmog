-- SlotBar.lua  (T.UI.SlotBar)
-- ---------------------------------------------------------------------------
-- Die 14 transmogbaren Plaetze als zwei Spalten mit je 7 Knoepfen (40x40):
--
--   Spalte 1 (bar.left):   HEAD SHOULDER BACK CHEST SHIRT TABARD WRIST
--   Spalte 2 (bar.right):  HANDS WAIST LEGS FEET | MAINHAND OFFHAND RANGED
--
-- Jeder Knopf zeigt das gewuenschte Aussehen (State.Wanted), sonst den
-- angelegten Gegenstand, sonst die abgedunkelte Leertextur des Platzes.
-- Der Rand verraet den Zustand (Auswahl = Akzent, ausstehend = gelb,
-- angewendet = rosa, inaktiv = rot, leer/nie = gedaempft); eine ausgewaehlte
-- Taste behaelt den Zustand ueber einen Streifen unten und das Glyph oben links.
--
-- Aufbau eines Knopfes (alles ueber dem Symbol liegt in einem Kind-Frame mit
-- hoeherem FrameLevel, damit nichts verdeckt wird und Klicks durchgehen):
--
--   btn            Button, Backdrop (Hintergrund + 1-px-Rand), .icon
--   btn.over       Kind-Frame (ohne Maus): Auswahlrahmen (2 px), Streifen,
--                  Glyph (* / !), Sperre (x), Zahl-Plakette, Hover, Aufblitzen
--
-- Aktualisierung: Ereignisse -> Merker je Slot -> EIN entprellter Durchlauf
-- (nur sichtbar; sonst holt OnShow nach). Aufblitzen (Flash) laeuft ueber einen
-- einzigen OnUpdate-Frame, der sich nach 0,7 s selbst versteckt.
--
-- Oeffentliche Schnittstelle (SPEC 6.4 / 11.2; Punkt-Aufruf, und als Methoden
-- der von Create gelieferten Tabelle auch mit Doppelpunkt):
--   SlotBar.Create(parent, onSelect) -> bar    bar.left, bar.right, bar.buttons[server]
--   SlotBar.Layout(height)     SlotBar.Refresh(slot|nil)   SlotBar.Select(slot|nil)
--   SlotBar.Flash(slot, ok)    SlotBar.ApplyLocale()
--   SlotBar.COLUMN_WIDTH = 44  SlotBar.BUTTON_SIZE = 40
-- Zusaetzlich: SlotBar.TooltipLines(slot), SlotBar.Selected(), SlotBar.Get().
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.UI = T.UI or {}

local SlotBar = T.UI.SlotBar or {}
T.UI.SlotBar = SlotBar

local floor, min, max = math.floor, math.min, math.max
local format, strfind = string.format, string.find

local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Blizzards Dateiname ist falsch geschrieben (Invisibilty): nur diese Schreibweise
-- gibt es im Client, mit "Invisibility" zeigt 3.3.5a das Fehlstueck-Quadrat.
local ICON_HIDDEN = "Interface\\Icons\\Spell_Nature_Invisibilty"
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

local BUTTON = 40            -- Kantenlaenge eines Knopfes
local COLUMN = 44            -- Breite einer Spalte
local ROWS = 7               -- Knoepfe je Spalte
local GAP_MIN = 4            -- Abstand zwischen Knoepfen (min/max)
local GAP_MAX = 14
local HAND_GAP = 8           -- zusaetzliche Luecke vor MAINHAND (Spalte 2)
local DEFAULT_HEIGHT = 400   -- Hoehe bis Layout gerufen wird (372 Inhalt + Steuerzeile der Vorschau)
local ICON_INSET = 3         -- Symbol sitzt 3 px innerhalb des Knopfes
local EDGE = 2               -- Dicke des Auswahlrahmens
local DIM_ALPHA = 0.4        -- Leertextur
local NEVER_ALPHA = 0.5      -- nie transmogbarer Gegenstand
local FLASH_TIME = 0.7       -- Dauer des Aufblitzens in Sekunden
local FLASH_PEAK = 0.75      -- Deckkraft zu Beginn
local REFRESH_DELAY = 0.05   -- Entprellung der Ereignisse
local DEBOUNCE_KEY = "ui-slotbar"
local BADGE_H = 12           -- Hoehe der Zahl-Plakette
local BADGE_MAX = 99         -- ab 100 wird "99+" gezeigt

SlotBar.COLUMN_WIDTH = COLUMN
SlotBar.BUTTON_SIZE = BUTTON

-- Zustand des Singletons (eine Tabelle spart Upvalues)
local S = {
   bar = nil,            -- die Tabelle, die Create liefert
   buttons = {},         -- [server] = Button (dieselbe Tabelle wie bar.buttons)
   onSelect = nil,       -- Rueckruf fuer Linksklick
   selected = nil,       -- ausgewaehlter Slot
   hover = nil,          -- Slot unter der Maus
   dirty = {},           -- [slot] = true: muss neu gezeichnet werden
   dirtyAll = false,
   flashes = {},         -- [slot] = Startzeit (GetTime)
   flashCount = 0,
   flashFrame = nil,     -- OnUpdate-Frame des Aufblitzens
   height = nil,         -- zuletzt gesetzte Hoehe
   built = false,
}

-- ---------------------------------------------------------------------------
-- Kleine Helfer
-- ---------------------------------------------------------------------------

-- Farbtabellen der Skin (immer vorhanden; siehe TOC-Reihenfolge).
local function Colors()
   local skin = T.UI.Skin
   return skin and skin.COL or {}
end

-- ID des Pseudo-Aussehens "verborgen".
local function HiddenId()
   return T.HIDDEN_ID or 999999
end

-- Einfarbige Flaeche aus WHITE8X8 (Farbe c = {r,g,b[,a]}, alpha optional).
local function Solid(parent, layer, c, alpha)
   local t = parent:CreateTexture(nil, layer)
   t:SetTexture(WHITE)
   t:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
   return t
end

-- Begrenzt v auf lo..hi.
local function Clamp(v, lo, hi)
   if v < lo then
      return lo
   elseif v > hi then
      return hi
   end
   return v
end

-- Zustandsschluessel eines Platzes: "pending" | "inactive" | "applied" | nil.
-- Ausstehend gewinnt vor inaktiv, inaktiv vor angewendet.
local function StateKey(slot, st)
   if st ~= "READY" then
      return nil
   end
   local State = T.State
   if State.HasPending(slot) then
      return "pending"
   end
   if State.IsInactive(slot) then
      return "inactive"
   end
   if State.Baseline(slot) ~= 0 then
      return "applied"
   end
   return nil
end

-- Farbe zum Zustandsschluessel (nil -> nil).
local function StateColor(key)
   local COL = Colors()
   if key == "pending" then
      return COL.yellow
   elseif key == "inactive" then
      return COL.red
   elseif key == "applied" then
      return COL.pink
   end
   return nil
end

-- Name und Qualitaets-Farbcode eines Aussehens; nil, solange die Daten fehlen
-- (dann wird die Abfrage angestossen und ITEMS_RESOLVED zeichnet neu).
local function AppearanceName(id)
   local info = T.Items.Info(id)
   if info and info.name then
      local _, _, _, hex = T.Util.QualityColor(info.quality)
      return info.name, hex
   end
   T.Items.Request(id)
   return nil
end

-- Text "Name" in Qualitaetsfarbe fuer ein Aussehen; Ersatz "Item <id>".
local function AppearanceText(id)
   local L = T.L
   local name, hex = AppearanceName(id)
   if name then
      return (hex or "") .. name .. "|r"
   end
   return format(L.SLOTBAR_UNKNOWN_ITEM, id)
end

-- Symbol des angelegten Gegenstands; nil, wenn nicht ermittelbar.
-- Rueckgabe zusaetzlich: true, wenn die Iteminfo noch fehlt (Abfrage laeuft).
local function EquippedIcon(eq)
   if eq and eq.icon then
      return eq.icon, false
   end
   if eq and eq.id then
      local info = T.Items.Info(eq.id)
      if info and info.icon then
         return info.icon, false
      end
      T.Items.Request(eq.id)
      return nil, true
   end
   return nil, false
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------

-- Zeilen fuer Skin.Tooltip: Slotname, angelegter Gegenstand, Zustand, Anzahl,
-- Bedienhinweise. Rueckgabe: Array { text, r, g, b }.
function SlotBar.TooltipLines(slot)
   local L, State, Slots, Util = T.L, T.State, T.Slots, T.Util
   local COL = Colors()
   local lines = {}

   local function add(text, c)
      lines[#lines + 1] = { text, c[1], c[2], c[3] }
   end

   lines[1] = { Slots.Label(slot), 1, 1, 1 }

   local st = State.SlotState(slot)
   local eq = State.Equipped(slot)
   if eq then
      local r, g, b = Util.QualityColor(eq.quality)
      lines[#lines + 1] = { eq.name or format(L.SLOTBAR_UNKNOWN_ITEM, eq.id), r, g, b }
   end

   if st == "EMPTY" then
      add(L.SLOTBAR_NOTHING_EQUIPPED, COL.dim)
      return lines
   elseif st == "NEVER" then
      add(L.SLOTBAR_NEVER, COL.dim)
      return lines
   end

   local hidden = HiddenId()
   local pending = State.HasPending(slot)
   local base = State.Baseline(slot)

   -- was der Server gerade zeigt
   if base == hidden then
      add(L.SLOTBAR_HIDDEN, COL.pink)
   elseif base ~= 0 then
      add(format(L.SLOTBAR_APPLIED, AppearanceText(base)), COL.pink)
   end

   -- ausstehende Aenderung
   if pending then
      local want = State.Wanted(slot)
      if want == 0 then
         add(L.SLOTBAR_PENDING_RESET, COL.yellow)
      elseif want == hidden then
         add(format(L.SLOTBAR_PENDING, L.SLOTBAR_HIDDEN), COL.yellow)
      else
         add(format(L.SLOTBAR_PENDING, AppearanceText(want)), COL.yellow)
      end
   end

   -- gespeichert, passt aber nicht zum angelegten Gegenstand
   if State.IsInactive(slot) then
      add(format(L.SLOTBAR_INACTIVE, AppearanceText(State.Applied(slot))), COL.red)
   end

   -- Anzahl verfuegbarer Aussehen (oder Ladefortschritt)
   local list = State.List(slot)
   if list.ready then
      add(format(L.SLOTBAR_AVAILABLE, list.amount), COL.text)
   elseif list.amount > 0 then
      add(format(L.SLOTBAR_LOADING, list.received, list.amount), COL.dim)
   end

   -- Bedienhinweise
   add(L.SLOTBAR_HINT_EDIT, COL.dim)
   if pending then
      add(L.SLOTBAR_HINT_DISCARD, COL.dim)
   elseif base ~= 0 then
      add(L.SLOTBAR_HINT_REMOVE, COL.dim)
   end
   local want = State.Wanted(slot)
   if want ~= 0 and want ~= hidden then
      add(L.SLOTBAR_HINT_LINK, COL.dim)
   end
   return lines
end

-- Zeigt den Tooltip des Knopfes (Spalte 1 nach rechts, Spalte 2 nach links,
-- damit er die Modellflaeche und nicht das Raster verdeckt).
local function ShowTip(btn)
   local skin = T.UI.Skin
   if not btn or not skin or not skin.Tooltip then
      return
   end
   local anchor = (btn.def and btn.def.column == 2) and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
   skin.Tooltip(btn, anchor, SlotBar.TooltipLines(btn.slot))
end

-- Baut den Tooltip neu, wenn er gerade zu diesem Knopf gehoert und sichtbar ist.
local function RetipIfHover(slot)
   local btn = S.buttons[slot]
   if not btn or S.hover ~= slot or not GameTooltip then
      return
   end
   if GameTooltip:IsOwned(btn) and GameTooltip:IsShown() then
      ShowTip(btn)
   end
end

-- ---------------------------------------------------------------------------
-- Darstellung eines Knopfes
-- ---------------------------------------------------------------------------

-- Zeichnet einen Platz neu (Symbol, Rand, Glyph, Streifen, Zahl, Hover).
local function Paint(slot)
   local btn = S.buttons[slot]
   if not btn then
      return
   end
   local State, Slots, Items, Skin = T.State, T.Slots, T.Items, T.UI.Skin
   local COL = Colors()
   local hidden = HiddenId()

   local st = State.SlotState(slot)
   local eq = State.Equipped(slot)
   local wanted = 0
   if st == "READY" then
      wanted = State.Wanted(slot)
   end

   -- 1. Symbol ---------------------------------------------------------------
   local tex, alpha, desat = nil, 1, false
   local needItems = false
   if st == "EMPTY" then
      tex = Slots.EmptyTexture(slot)
      alpha = DIM_ALPHA
   else
      if wanted == hidden then
         tex = ICON_HIDDEN
      elseif wanted ~= 0 then
         local info = Items.Info(wanted)
         if info and info.icon then
            tex = info.icon
         else
            Items.Request(wanted)
            needItems = true
            tex = ICON_UNKNOWN          -- ehrlicher als der Originalgegenstand
         end
      else
         local missing
         tex, missing = EquippedIcon(eq)
         needItems = missing and true or false
      end
      if st == "NEVER" then
         alpha = NEVER_ALPHA
         desat = true
      end
   end
   Skin.Icon(btn.icon, tex or ICON_UNKNOWN)
   btn.icon:SetAlpha(alpha)
   Skin.Desaturate(btn.icon, desat)
   btn.needItems = needItems

   -- 2. Rand und Hintergrund -------------------------------------------------
   local key = StateKey(slot, st)
   local selected = (S.selected == slot)
   local hover = (S.hover == slot) and st == "READY"
   local stateCol = StateColor(key)

   local bg, border
   if selected then
      bg, border = COL.selected, COL.accent
   else
      bg = hover and COL.hover or COL.button
      border = stateCol
      if not border then
         border = (st == "READY") and COL.buttonBorder or COL.border
      end
      if hover and not stateCol then
         border = COL.accent
      end
   end
   btn:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
   btn:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
   btn.stateKey = key

   local over = btn.over
   local edges = over.edges
   for i = 1, #edges do
      if selected then
         edges[i]:Show()
      else
         edges[i]:Hide()
      end
   end

   -- ausgewaehlt: der Zustand bleibt ueber einen Streifen unten sichtbar
   if selected and stateCol then
      over.stripe:SetVertexColor(stateCol[1], stateCol[2], stateCol[3], 1)
      over.stripe:Show()
   else
      over.stripe:Hide()
   end

   -- 3. Glyph oben links, Sperre in der Mitte --------------------------------
   if key == "pending" then
      over.glyph:SetText("*")
      over.glyph:SetTextColor(COL.yellow[1], COL.yellow[2], COL.yellow[3])
      over.glyph:Show()
   elseif key == "inactive" then
      over.glyph:SetText("!")
      over.glyph:SetTextColor(COL.red[1], COL.red[2], COL.red[3])
      over.glyph:Show()
   else
      over.glyph:Hide()
   end

   if st == "NEVER" then
      over.lock:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
      over.lock:Show()
   else
      over.lock:Hide()
   end

   -- 4. Zahl-Plakette unten rechts -------------------------------------------
   local amount = 0
   if st == "READY" then
      amount = State.List(slot).amount or 0
   end
   if amount > 0 then
      local text = (amount > BADGE_MAX) and (BADGE_MAX .. "+") or tostring(amount)
      over.count:SetText(text)
      over.count:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
      local w = (over.count:GetStringWidth() or 0) + 4
      over.badgeBg:SetWidth(max(w, BADGE_H))
      over.badgeBg:Show()
      over.count:Show()
   else
      over.count:SetText("")
      over.badgeBg:Hide()
      over.count:Hide()
   end

   -- 5. Hover-Aufhellung -----------------------------------------------------
   if hover then
      over.hover:Show()
   else
      over.hover:Hide()
   end
end

-- ---------------------------------------------------------------------------
-- Klicks
-- ---------------------------------------------------------------------------

-- Shift-Klick: Link des gewuenschten Aussehens in den Chat einfuegen.
-- Rueckgabe: true, wenn der Klick damit erledigt ist (auch ohne Einfuegen).
local function LinkAppearance(slot)
   local State, Items = T.State, T.Items
   if State.SlotState(slot) ~= "READY" then
      return false
   end
   local id = State.Wanted(slot)
   if id == 0 or id == HiddenId() then
      return false
   end
   local info = Items.Info(id)
   if not info or type(info.link) ~= "string" or not strfind(info.link, "|H", 1, true) then
      Items.Request(id)          -- ohne echten Link nichts einfuegen
      return true
   end
   if type(ChatEdit_InsertLink) == "function" then
      ChatEdit_InsertLink(info.link)
   end
   return true
end

-- OnClick eines Knopfes: Links = auswaehlen (Shift = Link), Rechts = Toggle.
-- Auch leere und nie transmogbare Plaetze werden gemeldet: das Raster nennt dort
-- den Grund ("nichts angelegt", "nicht transmogbar"), der Klick bleibt so nicht
-- ohne Antwort (SPEC 6.4: Linksklick -> onSelect(slot)).
local function OnButtonClick(self, mouseButton)
   local slot = self.slot
   local State = T.State
   -- ein Klick auf einen Platz nimmt dem Suchfeld den Tastaturfokus (die Leiste
   -- wird nach der Platzleiste geladen: spaet gebunden)
   local fb = T.UI and T.UI.FilterBar
   if fb and fb.ReleaseFocus then
      fb.ReleaseFocus()
   end
   if mouseButton == "RightButton" then
      State.Toggle(slot)
      return
   end
   if type(IsModifiedClick) == "function" and IsModifiedClick("CHATLINK") then
      if LinkAppearance(slot) then
         return
      end
   end
   local fn = S.onSelect
   if fn then
      fn(slot)
   end
end

-- OnEnter: Hover merken, neu zeichnen, Tooltip zeigen.
local function OnButtonEnter(self)
   S.hover = self.slot
   Paint(self.slot)
   ShowTip(self)
end

-- OnLeave/OnHide: Hover loeschen, neu zeichnen, Tooltip verbergen.
local function OnButtonLeave(self)
   if S.hover == self.slot then
      S.hover = nil
   end
   Paint(self.slot)
   local skin = T.UI.Skin
   if skin and skin.HideTooltip then
      skin.HideTooltip(self)
   end
end

-- ---------------------------------------------------------------------------
-- Aufblitzen
-- ---------------------------------------------------------------------------

-- Beendet alle laufenden Blitze und versteckt den Treiber.
local function ClearFlashes()
   for slot in pairs(S.flashes) do
      local btn = S.buttons[slot]
      if btn then
         btn.over.glow:Hide()
      end
      S.flashes[slot] = nil
   end
   S.flashCount = 0
   if S.flashFrame then
      S.flashFrame:Hide()
   end
end

-- OnUpdate des Treibers: Deckkraft linear abbauen, fertige Blitze entfernen.
local function FlashUpdate(self)
   local now = GetTime()
   for slot, t0 in pairs(S.flashes) do
      local btn = S.buttons[slot]
      local dt = now - t0
      if not btn or dt >= FLASH_TIME then
         if btn then
            btn.over.glow:Hide()
         end
         S.flashes[slot] = nil
         S.flashCount = S.flashCount - 1
      else
         btn.over.glow:SetAlpha(FLASH_PEAK * (1 - dt / FLASH_TIME))
      end
   end
   if S.flashCount <= 0 then
      S.flashCount = 0
      self:Hide()      -- nichts mehr zu tun: kein OnUpdate im Leerlauf
   end
end

-- Laesst den Knopf 0,7 s aufleuchten: rosa bei Erfolg, rot bei Fehlschlag.
-- Rueckgabe: true, wenn ein Blitz gestartet wurde (Slot bekannt und sichtbar).
function SlotBar.Flash(slot, ok)
   local btn = S.buttons[slot]
   if not btn or not S.flashFrame then
      return false
   end
   if not S.bar.left:IsVisible() then
      return false
   end
   local COL = Colors()
   local c = ok and COL.pink or COL.red
   local glow = btn.over.glow
   glow:SetVertexColor(c[1], c[2], c[3], 1)
   glow:SetAlpha(FLASH_PEAK)
   glow:Show()
   if S.flashes[slot] == nil then
      S.flashCount = S.flashCount + 1
   end
   S.flashes[slot] = GetTime()
   S.flashFrame:Show()
   return true
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

-- Verteilt die 7 Knoepfe je Spalte auf die Hoehe: Abstand 4..14 px; in Spalte 2
-- zusaetzlich 8 px vor MAINHAND. Beide Spalten nutzen denselben Abstand und
-- dieselbe Oberkante, damit die Zeilen nebeneinander fluchten; ist die Hoehe
-- groesser als der Inhalt, wird er senkrecht zentriert. Die Vorschau belegt
-- unten eine Steuerzeile (Preview.CONTROLS_HEIGHT): die Plaetze richten sich an
-- der Buehne darueber aus, damit sie dieselbe Mitte haben wie das Modell.
function SlotBar.Layout(height)
   if not S.bar then
      return
   end
   height = tonumber(height) or S.height or DEFAULT_HEIGHT
   if height < 0 then
      height = 0
   end
   S.height = height

   local reserve = 0
   local preview = T.UI.Preview
   if preview and type(preview.CONTROLS_HEIGHT) == "number" then
      reserve = preview.CONTROLS_HEIGHT
   end
   local usable = max(height - reserve, 0)

   local free = usable - ROWS * BUTTON - HAND_GAP
   local gap = Clamp(free / (ROWS - 1), GAP_MIN, GAP_MAX)
   local total = ROWS * BUTTON + (ROWS - 1) * gap + HAND_GAP
   local top = 0
   if total < usable then
      top = floor((usable - total) / 2)
   end

   local x = floor((COLUMN - BUTTON) / 2)

   S.bar.left:SetWidth(COLUMN)
   S.bar.left:SetHeight(height)
   S.bar.right:SetWidth(COLUMN)
   S.bar.right:SetHeight(height)

   -- Zeile von MAINHAND: ab hier sitzt die zusaetzliche Luecke (Spalte 2)
   local list = T.Slots.LIST
   local handIndex = ROWS + 1
   for i = 1, #list do
      if list[i].key == "MAINHAND" then
         handIndex = list[i].index
      end
   end

   for i = 1, #list do
      local def = list[i]
      local btn = S.buttons[def.server]
      if btn then
         local y = top + (def.index - 1) * (BUTTON + gap)
         if def.column == 2 and def.index >= handIndex then
            y = y + HAND_GAP
         end
         local parent = (def.column == 2) and S.bar.right or S.bar.left
         btn:ClearAllPoints()
         btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -floor(y + 0.5))
      end
   end
end

-- ---------------------------------------------------------------------------
-- Aktualisierung
-- ---------------------------------------------------------------------------

-- Zeichnet einen Slot (nil = alle) sofort neu; erneuert einen offenen Tooltip.
function SlotBar.Refresh(slot)
   if not S.built then
      return
   end
   if slot == nil then
      local list = T.Slots.LIST
      for i = 1, #list do
         Paint(list[i].server)
      end
      if S.hover then
         RetipIfHover(S.hover)
      end
   else
      if not S.buttons[slot] then
         return
      end
      Paint(slot)
      RetipIfHover(slot)
   end
end

-- Entprellter Durchlauf: nur sichtbar; sonst bleibt der Merker fuer OnShow.
local function Flush()
   if not S.built or not S.bar.left:IsVisible() then
      return
   end
   local all, list = S.dirtyAll, S.dirty
   S.dirtyAll = false
   S.dirty = {}
   if all then
      SlotBar.Refresh(nil)
   else
      for slot in pairs(list) do
         SlotBar.Refresh(slot)
      end
   end
end

-- Merkt einen Slot (oder alle) zum Neuzeichnen vor und entprellt den Durchlauf.
local function Mark(slot)
   if type(slot) == "number" and S.buttons[slot] then
      S.dirty[slot] = true
   else
      S.dirtyAll = true
   end
   T.Util.Debounce(DEBOUNCE_KEY, REFRESH_DELAY, Flush)
end

-- Waehlt einen Slot aus (nil = keine Auswahl); zeichnet alt und neu.
function SlotBar.Select(slot)
   if slot ~= nil and not (type(slot) == "number" and S.buttons[slot]) then
      slot = nil
   end
   local old = S.selected
   S.selected = slot
   if not S.built then
      return
   end
   if old ~= nil and old ~= slot then
      Paint(old)
   end
   if slot ~= nil then
      Paint(slot)
   end
end

-- Liefert den ausgewaehlten Slot (oder nil).
function SlotBar.Selected()
   return S.selected
end

-- Liefert die Tabelle von Create (nil vor Create).
function SlotBar.Get()
   return S.bar
end

-- Setzt Texte neu (Tooltips entstehen bei Bedarf; hier nur Neuzeichnen).
function SlotBar.ApplyLocale()
   SlotBar.Refresh(nil)
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

-- Baut Knopf und Kind-Frame fuer einen Platz.
local function BuildButton(container, def)
   local Skin = T.UI.Skin
   local COL = Colors()

   local btn = CreateFrame("Button", nil, container)
   btn:SetWidth(BUTTON)
   btn:SetHeight(BUTTON)
   Skin.Backdrop(btn, COL.button, COL.buttonBorder)
   btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
   btn.slot = def.server
   btn.def = def

   -- Symbol: 3 px nach innen, ohne Blizzard-Rand
   local icon = btn:CreateTexture(nil, "ARTWORK")
   icon:SetPoint("TOPLEFT", btn, "TOPLEFT", ICON_INSET, -ICON_INSET)
   icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
   Skin.TrimIcon(icon)
   btn.icon = icon

   -- alles Weitere in einem Kind-Frame ueber dem Symbol (ohne Maus)
   local over = CreateFrame("Frame", nil, btn)
   over:SetAllPoints(btn)
   over:SetFrameLevel(btn:GetFrameLevel() + 2)
   over:EnableMouse(false)
   btn.over = over

   -- Hover-Aufhellung und Blitz: Flaechen ueber dem Symbol
   local hover = Solid(over, "ARTWORK", COL.white, 0.12)
   hover:SetPoint("TOPLEFT", over, "TOPLEFT", 1, -1)
   hover:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", -1, 1)
   hover:Hide()
   over.hover = hover

   local glow = Solid(over, "ARTWORK", COL.pink, 1)
   glow:SetPoint("TOPLEFT", over, "TOPLEFT", 1, -1)
   glow:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", -1, 1)
   glow:Hide()
   over.glow = glow

   -- Auswahlrahmen: vier 2-px-Balken in Akzentfarbe
   local top = Solid(over, "OVERLAY", COL.accent, 1)
   top:SetPoint("TOPLEFT", over, "TOPLEFT", 0, 0)
   top:SetPoint("TOPRIGHT", over, "TOPRIGHT", 0, 0)
   top:SetHeight(EDGE)
   local bottom = Solid(over, "OVERLAY", COL.accent, 1)
   bottom:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", 0, 0)
   bottom:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", 0, 0)
   bottom:SetHeight(EDGE)
   local left = Solid(over, "OVERLAY", COL.accent, 1)
   left:SetPoint("TOPLEFT", over, "TOPLEFT", 0, -EDGE)
   left:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", 0, EDGE)
   left:SetWidth(EDGE)
   local right = Solid(over, "OVERLAY", COL.accent, 1)
   right:SetPoint("TOPRIGHT", over, "TOPRIGHT", 0, -EDGE)
   right:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", 0, EDGE)
   right:SetWidth(EDGE)
   over.edges = { top, bottom, left, right }
   for i = 1, #over.edges do
      over.edges[i]:Hide()
   end

   -- Zustandsstreifen am unteren Rand (nur bei Auswahl sichtbar)
   local stripe = Solid(over, "OVERLAY", COL.yellow, 1)
   stripe:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", EDGE, EDGE)
   stripe:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", -EDGE, EDGE)
   stripe:SetHeight(3)
   stripe:Hide()
   over.stripe = stripe

   -- Glyph oben links ("*" ausstehend, "!" inaktiv)
   local glyph = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   glyph:SetPoint("TOPLEFT", over, "TOPLEFT", 4, -3)
   glyph:SetWidth(10)
   glyph:SetHeight(12)
   glyph:SetJustifyH("LEFT")
   glyph:SetText("")
   glyph:Hide()
   over.glyph = glyph

   -- Sperre in der Mitte (nie transmogbar)
   local lock = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
   lock:SetPoint("CENTER", over, "CENTER", 0, 0)
   lock:SetWidth(16)
   lock:SetHeight(18)
   lock:SetJustifyH("CENTER")
   lock:SetText("x")
   lock:Hide()
   over.lock = lock

   -- Zahl-Plakette unten rechts: dunkle Flaeche + Ziffern
   local badgeBg = Solid(over, "ARTWORK", { 0, 0, 0, 1 }, 0.7)
   badgeBg:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", -1, 1)
   badgeBg:SetWidth(BADGE_H)
   badgeBg:SetHeight(BADGE_H)
   badgeBg:Hide()
   over.badgeBg = badgeBg

   local count = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   count:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", -3, 2)
   count:SetWidth(BUTTON - 6)
   count:SetHeight(BADGE_H)
   count:SetJustifyH("RIGHT")
   count:SetText("")
   count:Hide()
   over.count = count

   -- bequemer Zugriff fuer Tests und andere Module
   btn.count = count
   btn.glyph = glyph
   btn.glow = glow
   btn.stripe = stripe
   btn.lock = lock

   btn:SetScript("OnEnter", OnButtonEnter)
   btn:SetScript("OnLeave", OnButtonLeave)
   btn:SetScript("OnHide", OnButtonLeave)
   btn:SetScript("OnClick", OnButtonClick)
   return btn
end

-- Meldet die Ereignisse an (einmalig, Besitzer = SlotBar).
local function RegisterEvents()
   local E = T.Events
   if not E or not E.On then
      return
   end
   E.On("WANTED_CHANGED", function(slot) Mark(slot) end, SlotBar)
   E.On("EQUIPMENT_CHANGED", function(slot) Mark(slot) end, SlotBar)
   E.On("STATUS_CHANGED", function() Mark(nil) end, SlotBar)
   E.On("LIST_PROGRESS", function(slot) Mark(slot) end, SlotBar)
   E.On("LIST_READY", function(slot) Mark(slot) end, SlotBar)
   E.On("ITEMS_RESOLVED", function()
      -- nur Plaetze, deren Symbol oder Name noch fehlte, brauchen einen Durchlauf
      local any = false
      for slot, btn in pairs(S.buttons) do
         if btn.needItems then
            S.dirty[slot] = true
            any = true
         end
      end
      if S.hover then
         S.dirty[S.hover] = true     -- Tooltip kann Namen nachtragen
         any = true
      end
      if any then
         T.Util.Debounce(DEBOUNCE_KEY, REFRESH_DELAY, Flush)
      end
   end, SlotBar)
   E.On("LOCALE_CHANGED", function() SlotBar.ApplyLocale() end, SlotBar)
end

-- Erstellt die 14 Knoepfe in zwei Spalten. onSelect(slot) wird bei Linksklick
-- auf einen auswaehlbaren Platz gerufen. Ein weiteres Create liefert dieselbe
-- Tabelle (und uebernimmt einen neuen onSelect).
function SlotBar.Create(parent, onSelect)
   if S.bar then
      if type(onSelect) == "function" then
         S.onSelect = onSelect
      end
      return S.bar
   end

   S.onSelect = onSelect

   local left = CreateFrame("Frame", nil, parent)
   left:SetWidth(COLUMN)
   left:SetHeight(DEFAULT_HEIGHT)
   local right = CreateFrame("Frame", nil, parent)
   right:SetWidth(COLUMN)
   right:SetHeight(DEFAULT_HEIGHT)

   local bar = { left = left, right = right, buttons = S.buttons }
   S.bar = bar

   local list = T.Slots.LIST
   for i = 1, #list do
      local def = list[i]
      local container = (def.column == 2) and right or left
      S.buttons[def.server] = BuildButton(container, def)
   end

   -- Treiber fuers Aufblitzen: versteckt, bis ein Blitz laeuft
   local flash = CreateFrame("Frame", nil, left)
   flash:SetScript("OnUpdate", FlashUpdate)
   flash:Hide()
   S.flashFrame = flash

   -- Methoden fuer Doppelpunkt- UND Punkt-Aufruf (bar:Layout(h) / bar.Layout(h))
   local function Method(fn)
      return function(a, ...)
         if a == bar then
            return fn(...)
         end
         return fn(a, ...)
      end
   end
   bar.Layout = Method(SlotBar.Layout)
   bar.Refresh = Method(SlotBar.Refresh)
   bar.Select = Method(SlotBar.Select)
   bar.Flash = Method(SlotBar.Flash)
   bar.ApplyLocale = Method(SlotBar.ApplyLocale)

   -- Felder auch am Modul (bequem fuer Window und Tests)
   SlotBar.left = left
   SlotBar.right = right
   SlotBar.buttons = S.buttons
   SlotBar.bar = bar

   S.built = true
   SlotBar.Layout(DEFAULT_HEIGHT)

   -- sichtbar werden: Versaeumtes nachholen; verschwinden: Blitze beenden
   left:HookScript("OnShow", function()
      Flush()
   end)
   left:HookScript("OnHide", function()
      ClearFlashes()
   end)

   RegisterEvents()
   S.dirtyAll = true
   SlotBar.Refresh(nil)
   S.dirtyAll = false
   return bar
end
