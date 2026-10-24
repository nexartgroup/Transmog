-- UI\OutfitsTab.lua  (T.UI.OutfitsTab)
-- ---------------------------------------------------------------------------
-- Outfit-Reiter: gespeicherte Outfits ansehen, laden, ueberschreiben,
-- umbenennen und loeschen; den aktuellen Look als neues Outfit speichern.
--
-- Aufbau (alle Masse werden von oben gerechnet, nie aus fremden Frames gelesen):
--
--   +---------------------------------------------------------------+
--   | [ Aktuellen Look speichern ]                          n / 50  |  Kopf 36
--   +---------------------------------------------------------------+
--   | Name                                       Teile: 7  [Laden ] |  Zeile 52
--   | [ic][ic][ic][ic][ic][ic][ic][ic] +3     [Ueberschr.][Loeschen]|
--   | ...                                                           |
--   +---------------------------------------------------------------+
--   |                    <   Seite 1 / 3   >                        |  Leiste 30
--   +---------------------------------------------------------------+
--
-- Schnittstelle (SPEC 6.9 / 11.2; Singleton, Punkt-Aufruf):
--   OutfitsTab.Create(parent) -> Frame      baut den Reiter einmal (weiteres Create liefert denselben)
--   OutfitsTab.Layout(w, h)                 Groesse setzen, Zeilen pro Seite rechnen, neu zeichnen
--   OutfitsTab.Refresh()                    Liste neu zeichnen (nur wenn sichtbar, sonst beim Zeigen)
--   OutfitsTab.Show() / OutfitsTab.Hide()
--   OutfitsTab.onStatus = function(text, colorKey)   setzt das Fenster (Statuszeile)
--
-- Zusaetzlich (nicht Teil des Vertrags): SetPage/Page, ApplyLocale, die
-- Aktionen PromptSave/LoadOutfit/PromptOverwrite/PromptRename/PromptDelete
-- (laufen so, wie die Knoepfe sie rufen) und die Felder page/pages/perPage.
--
-- Ereignisse (Bus): OUTFITS_CHANGED, WANTED_CHANGED, STATUS_CHANGED, LIST_READY,
-- EQUIPMENT_CHANGED, ITEMS_RESOLVED (Symbole), LOCALE_CHANGED. Aktualisierung
-- gebuendelt (Util.Debounce) und nur bei sichtbarem Reiter; sonst Dirty-Flag
-- und Nachholen im OnShow. Es laeuft kein OnUpdate.
--
-- Einzelheiten, die leicht uebersehen werden:
--   * Teile, die nur auf eine noch ladende Liste warten (OUTFIT_SKIP_LOADING),
--     zaehlen weder in der Info ("Verfuegbar x von n") noch in der Meldung von
--     "Laden" als nicht verfuegbar; sie bekommen eigene Texte.
--   * Passt der Info-Text nicht in die Haelfte der Zeile, steht die Kurzform
--     "x/n" bzw. "n" (nie ein mitten abgeschnittener Satz).
--   * Namen in Statusmeldungen sind auf 20 Zeichen gekuerzt (schmale Fusszeile).
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.UI = T.UI or {}

local OutfitsTab = {}
T.UI.OutfitsTab = OutfitsTab

local L = T.L
local Util = T.Util
local Events = T.Events
local Slots = T.Slots
local Items = T.Items
local Outfits = T.Outfits
local Skin = T.UI.Skin
local COL = Skin.COL

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- ---------------------------------------------------------------------------
-- Masse und Farben
-- ---------------------------------------------------------------------------

local TOP_H = 36            -- Kopfzeile (Speichern-Knopf, Zaehler)
local GAP = 6               -- Abstand zwischen Kopf, Liste und Leiste
local PAGER_H = 30          -- Blaetterleiste unten
local ROW_H = 52
local ROW_GAP = 4
local PAD = 10              -- Innenrand links in einer Zeile
local ICON = 24
local ICON_GAP = 2
local MAX_ICONS = 8         -- hoechstens so viele Symbole je Zeile (SPEC 6.9)
local BTN_H = 20
local BTN_MIN, BTN_MAX = 60, 112
local SAVE_H = 28

-- Blizzards Dateiname ist falsch geschrieben (Invisibilty): nur diese Schreibweise
-- gibt es im Client, mit "Invisibility" zeigt 3.3.5a das Fehlstueck-Quadrat.
local ICON_HIDDEN = "Interface\\Icons\\Spell_Nature_Invisibilty"
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

local ROW_BG = { 0.075, 0.085, 0.10, 1 }
local ROW_BORDER_CURRENT = { 0.20, 0.50, 0.32, 1 }   -- Rand des Outfits, das dem aktuellen Look entspricht
local ICON_BG = { 0.02, 0.02, 0.03, 1 }

-- ---------------------------------------------------------------------------
-- Zustand
-- ---------------------------------------------------------------------------

local S = {
   tab = nil,          -- Container-Frame
   parent = nil,
   list = nil,         -- Frame, der die Zeilen aufnimmt
   pager = nil,        -- Blaetterleiste
   empty = nil,        -- Leerzustand (Frame)
   saveBtn = nil,
   counter = nil,      -- FontString "n / 50"
   rows = {},          -- Zeilen-Frames (Vorrat)
   w = 0, h = 0,       -- zuletzt gesetzte Groesse
   page = 1, pages = 1, perPage = 1, count = 0,
   btnW = 80,          -- Breite der Zeilenknoepfe (aus den Beschriftungen)
   outfits = {},       -- Outfits der letzten Zeichnung
   look = {},          -- CurrentLook der letzten Zeichnung
   hasLook = false,
   dirty = true,       -- muss neu gezeichnet werden
   tipRow = nil,       -- Zeile, deren Tooltip gezeigt wird
   showName = nil,     -- frisch gespeichertes Outfit: beim naechsten Zeichnen anzeigen
   relayout = false,   -- Layout trotz gleicher Groesse neu rechnen (Sprachwechsel)
   measure = nil,      -- unsichtbarer FontString zum Messen
}

-- ---------------------------------------------------------------------------
-- Kleine Helfer
-- ---------------------------------------------------------------------------

-- Textbreite in Pixeln (GameFontHighlightSmall, ohne Umbruch)
local function TextWidth(text)
   if not S.measure then
      S.measure = UIParent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      S.measure:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -4096, -4096)
      S.measure:SetAlpha(0)
   end
   S.measure:SetText(text or "")
   return S.measure:GetStringWidth() or 0
end

-- Text zu einem Fehler-/Grundschluessel, den Outfits.* liefert (ausgeschrieben
-- statt L[key], damit die Locale-Pruefung die Schluessel statisch findet).
-- Unbekannter Schluessel: der Schluessel selbst (wie L).
local function KeyText(key)
   if type(key) ~= "string" then return "" end
   if key == "OUTFIT_ERR_EMPTY" then return L.OUTFIT_ERR_EMPTY end
   if key == "OUTFIT_ERR_EXISTS" then return L.OUTFIT_ERR_EXISTS end
   if key == "OUTFIT_ERR_LONG" then return L.OUTFIT_ERR_LONG end
   if key == "OUTFIT_ERR_FULL" then return L.OUTFIT_ERR_FULL end
   if key == "OUTFIT_ERR_NOITEMS" then return L.OUTFIT_ERR_NOITEMS end
   if key == "OUTFIT_ERR_MISSING" then return L.OUTFIT_ERR_MISSING end
   if key == "OUTFIT_SKIP_EMPTY" then return L.OUTFIT_SKIP_EMPTY end
   if key == "OUTFIT_SKIP_NEVER" then return L.OUTFIT_SKIP_NEVER end
   if key == "OUTFIT_SKIP_LOADING" then return L.OUTFIT_SKIP_LOADING end
   if key == "OUTFIT_SKIP_UNAVAILABLE" then return L.OUTFIT_SKIP_UNAVAILABLE end
   if key == "OUTFIT_SKIP_HIDDEN" then return L.OUTFIT_SKIP_HIDDEN end
   return key
end

-- Name in Statusmeldungen: auf STATUS_NAME_MAX Zeichen (UTF-8, nie mitten im
-- Zeichen) gekuerzt. Die Fusszeile des Fensters ist bei Mindestgroesse nur etwa
-- 290 px breit; ein 32-Zeichen-Name mit Text drumherum wuerde abgeschnitten.
local STATUS_NAME_MAX = 20
local function StatusName(name)
   name = tostring(name or "")
   local n = 0
   for i = 1, #name do
      local b = string.byte(name, i)
      if b < 128 or b >= 192 then      -- Folgebytes (128..191) zaehlen nicht
         n = n + 1
         if n > STATUS_NAME_MAX then
            local head = string.gsub(string.sub(name, 1, i - 1), "%s+$", "")
            return head .. "..."
         end
      end
   end
   return name
end

-- Vorgabe fuer OutfitsTab.onStatus: die Statuszeile des Fensters, falls es sie gibt.
-- Das Fenster ersetzt die Funktion (SPEC 11.2); ohne Fenster bleibt es still.
function OutfitsTab.onStatus(text, colorKey)
   local W = T.UI.Window
   if type(W) == "table" and type(W.SetStatus) == "function" then
      W.SetStatus(text, colorKey)
   end
end

-- Meldung an die Statuszeile (colorKey: green|yellow|red|dim); onStatus darf fehlen
local function Status(text, colorKey)
   local fn = OutfitsTab.onStatus
   if type(fn) == "function" then
      fn(text, colorKey or "dim")
   end
end

-- Anzahl belegter Slots einer Slot-Tabelle
local function CountSlots(slots)
   local n = 0
   if type(slots) == "table" then
      for i = 1, #Slots.LIST do
         if tonumber(slots[Slots.LIST[i].server]) then n = n + 1 end
      end
   end
   return n
end

-- Entspricht das Outfit genau dem aktuellen Look?
local function SameLook(slots, look)
   if type(slots) ~= "table" then return false end
   local any = false
   for i = 1, #Slots.LIST do
      local s = Slots.LIST[i].server
      local a = tonumber(slots[s]) or 0
      local b = tonumber(look[s]) or 0
      if a ~= b then return false end
      if a ~= 0 then any = true end
   end
   return any
end

-- Ist der Reiter sichtbar?
local function IsVisible()
   return S.tab ~= nil and S.tab:IsVisible() and true or false
end

-- ---------------------------------------------------------------------------
-- Tooltip einer Zeile
-- ---------------------------------------------------------------------------

-- Baut die Tooltip-Zeilen zu einem Outfit (Name, Teile je Slot, Gruende)
local function TipLines(name)
   local o = Outfits.Get(name)
   if not o then return nil end
   local _, skipped = Outfits.Check(name)
   local reason = {}
   for i = 1, #skipped do
      reason[skipped[i].slot] = skipped[i].reasonKey
   end

   local lines = { { o.name, 1, 1, 1 } }
   if SameLook(o.slots, S.look) then
      lines[#lines + 1] = { L.OUTFITS_TIP_CURRENT, COL.green[1], COL.green[2], COL.green[3], true }
   end

   local hidden = T.HIDDEN_ID or 999999
   for i = 1, #Slots.LIST do
      local def = Slots.LIST[i]
      local id = tonumber(o.slots[def.server])
      if id then
         local text, r, g, b
         if id == hidden then
            text, r, g, b = L.OUTFITS_HIDDEN, COL.pink[1], COL.pink[2], COL.pink[3]
         else
            local info = Items.Info(id)
            if info and info.name then
               text = info.name
               r, g, b = Util.QualityColor(info.quality)
            elseif Items.IsFailed(id) then
               -- der Client kennt den Gegenstand nicht (mehr): nicht ewig "Laedt..."
               text = Util.Format(L.OUTFITS_ITEM_UNKNOWN, id)
               r, g, b = COL.dim[1], COL.dim[2], COL.dim[3]
            else
               text, r, g, b = L.OUTFITS_LOADING, COL.dim[1], COL.dim[2], COL.dim[3]
            end
         end
         local rk = reason[def.server]
         local lr, lg, lb = COL.dim[1], COL.dim[2], COL.dim[3]
         if rk then lr, lg, lb = COL.yellow[1], COL.yellow[2], COL.yellow[3] end
         lines[#lines + 1] = {
            left = Slots.Label(def.server), right = text,
            r = lr, g = lg, b = lb, rr = r, rg = g, rb = b,
         }
         if rk then
            lines[#lines + 1] = { "  " .. KeyText(rk), COL.yellow[1], COL.yellow[2], COL.yellow[3], true }
         end
      end
   end
   return lines
end

-- Tooltip der Zeile zeigen (setzt voraus, dass row.outfitName gesetzt ist)
local function ShowRowTip(row)
   local name = row.outfitName
   if not name then return end
   local lines = TipLines(name)
   if not lines then return end
   Skin.Tooltip(row, "ANCHOR_RIGHT", lines)
end

-- Hervorhebung der Zeile: an, solange die Maus auf der Zeile oder einem ihrer Kinder liegt
local function RowHover(row)
   if Skin.IsMouseOver(row) then row.hl:Show() else row.hl:Hide() end
end

-- ---------------------------------------------------------------------------
-- Aktionen (Knoepfe)
-- ---------------------------------------------------------------------------

-- Der Look, der gespeichert wuerde, ist leer?
local function LookIsEmpty()
   return next(Outfits.CurrentLook()) == nil
end

-- OutfitsTab.PromptSave() -- Dialog "Aktuellen Look speichern" (Name mit Pruefung)
function OutfitsTab.PromptSave()
   if Outfits.Count() >= Outfits.MAX then
      Status(L.OUTFIT_ERR_FULL, "red")
      return false
   end
   if LookIsEmpty() then
      Status(L.OUTFIT_ERR_NOITEMS, "red")
      return false
   end
   Skin.Prompt({
      title = L.OUTFITS_SAVE_TITLE,
      text = L.OUTFITS_SAVE_TEXT,
      default = Outfits.SuggestName(),
      accept = Util.G("SAVE", "Save"),
      maxLetters = Outfits.MAX_NAME + 8,
      owner = S.tab,
      validate = function(text)
         local ok, errKey = Outfits.ValidateName(text)
         if ok then return true end
         return false, KeyText(errKey)
      end,
      onAccept = function(text)
         local name = Outfits.NormalizeName(text)
         local ok, errKey = Outfits.Save(name, Outfits.CurrentLook())
         if ok then
            S.showName = name      -- beim naechsten Zeichnen zu seiner Seite blaettern
            Status(Util.Format(L.OUTFITS_SAVED, StatusName(name)), "green")
         else
            Status(KeyText(errKey), "red")
         end
      end,
   })
   return true
end

-- Wie viele der uebersprungenen Teile warten nur auf eine noch ladende Liste?
-- (skipped = zweiter Rueckgabewert von Outfits.Load/Check)
local function CountLoading(skipped)
   local n = 0
   for i = 1, #skipped do
      if skipped[i].reasonKey == "OUTFIT_SKIP_LOADING" then n = n + 1 end
   end
   return n
end

-- OutfitsTab.LoadOutfit(name) -- laedt das Outfit als Auswahl und meldet das
-- Ergebnis in der Statuszeile. Rueckgabe: ok, geladen, nicht verfuegbar
function OutfitsTab.LoadOutfit(name)
   local applied, skipped, errKey = Outfits.Load(name)
   if errKey then
      Status(KeyText(errKey), "red")
      return false, 0, 0
   end
   local nApplied, nSkipped = #applied, #skipped
   local nLoading = CountLoading(skipped)
   if nApplied == 0 and nSkipped == 0 then
      -- Outfit ohne Teile (z. B. aus alten Daten uebernommen)
      Status(L.OUTFITS_LOADED_EMPTY, "red")
   elseif nApplied == 0 and nLoading > 0 then
      -- vielleicht nur zu frueh: Listen laden noch, spaeter nochmal versuchen
      Status(L.OUTFITS_LOADED_WAIT, "yellow")
   elseif nApplied == 0 then
      Status(Util.Format(L.OUTFITS_LOADED_NONE, nSkipped), "red")
   elseif nSkipped == 0 then
      Status(Util.Format(L.OUTFITS_LOADED, nApplied), "green")
   elseif nLoading == nSkipped then
      Status(Util.Format(L.OUTFITS_LOADED_PENDING, nApplied, nLoading), "yellow")
   else
      Status(Util.Format(L.OUTFITS_LOADED_PARTIAL, nApplied, nSkipped), "yellow")
   end
   return true, nApplied, nSkipped
end

-- OutfitsTab.PromptOverwrite(name) -- Rueckfrage, dann Outfit durch den aktuellen Look ersetzen
function OutfitsTab.PromptOverwrite(name)
   if LookIsEmpty() then
      Status(L.OUTFIT_ERR_NOITEMS, "red")
      return false
   end
   Skin.Confirm({
      title = L.OUTFITS_OVERWRITE_TITLE,
      text = Util.Format(L.OUTFITS_OVERWRITE_TEXT, name),
      accept = L.OUTFITS_OVERWRITE,
      owner = S.tab,
      onAccept = function()
         local ok, errKey = Outfits.Overwrite(name, Outfits.CurrentLook())
         if ok then
            Status(Util.Format(L.OUTFITS_OVERWRITTEN, StatusName(name)), "green")
         else
            Status(KeyText(errKey), "red")
         end
      end,
   })
   return true
end

-- Pruefung fuer den Umbenennen-Dialog: nur die Schreibweise aendern ist erlaubt
local function RenameValidator(old)
   local oldKey = Util.Lower(Outfits.NormalizeName(old))
   return function(text)
      local norm = Outfits.NormalizeName(text)
      if norm ~= "" and Util.Lower(norm) == oldKey then
         return true
      end
      local ok, errKey = Outfits.ValidateName(text)
      if ok then return true end
      return false, KeyText(errKey)
   end
end

-- OutfitsTab.PromptRename(name) -- Eingabedialog, vorbelegt mit dem alten Namen
function OutfitsTab.PromptRename(name)
   Skin.Prompt({
      title = L.OUTFITS_RENAME_TITLE,
      text = Util.Format(L.OUTFITS_RENAME_TEXT, name),
      default = name,
      accept = L.OUTFITS_RENAME,
      maxLetters = Outfits.MAX_NAME + 8,
      owner = S.tab,
      validate = RenameValidator(name),
      onAccept = function(text)
         local norm = Outfits.NormalizeName(text)
         local ok, errKey = Outfits.Rename(name, norm)
         if ok then
            Status(Util.Format(L.OUTFITS_RENAMED, StatusName(norm)), "green")
         else
            Status(KeyText(errKey), "red")
         end
      end,
   })
   return true
end

-- OutfitsTab.PromptDelete(name) -- Rueckfrage (rot), dann Outfit loeschen
function OutfitsTab.PromptDelete(name)
   Skin.Confirm({
      title = L.OUTFITS_DELETE_TITLE,
      text = Util.Format(L.OUTFITS_DELETE_TEXT, name),
      accept = L.OUTFITS_DELETE,
      danger = true,
      owner = S.tab,
      onAccept = function()
         local ok, errKey = Outfits.Delete(name)
         if ok then
            Status(Util.Format(L.OUTFITS_DELETED, StatusName(name)), "yellow")
         else
            Status(KeyText(errKey), "red")
         end
      end,
   })
   return true
end

-- ---------------------------------------------------------------------------
-- Zeilen
-- ---------------------------------------------------------------------------

-- Ein Symbolfeld (Rahmen mit Qualitaetsrand + Textur) in der Zeile
local function NewIcon(row)
   local f = CreateFrame("Frame", nil, row)
   f:SetWidth(ICON)
   f:SetHeight(ICON)
   Skin.Backdrop(f, ICON_BG, COL.grey)
   local tex = f:CreateTexture(nil, "ARTWORK")
   tex:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
   tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
   Skin.Icon(tex, ICON_UNKNOWN)
   f:Hide()
   return { frame = f, tex = tex }
end

-- Zeichnet ein Symbolfeld fuer die Item-ID (oder "Verborgen")
local function PaintIcon(cell, id)
   local path = ICON_UNKNOWN
   local r, g, b = COL.grey[1], COL.grey[2], COL.grey[3]
   if id == (T.HIDDEN_ID or 999999) then
      path = ICON_HIDDEN
      r, g, b = COL.pink[1], COL.pink[2], COL.pink[3]
   else
      local info = Items.Info(id)
      if info then
         if info.icon then path = info.icon end
         r, g, b = Util.QualityColor(info.quality)
      end
   end
   Skin.Icon(cell.tex, path)
   cell.frame:SetBackdropBorderColor(r, g, b, 1)
   cell.id = id
   cell.frame:Show()
end

-- Baut eine Zeile (Rahmen, Name, Info, Symbole, vier Knoepfe)
local function NewRow(index)
   local row = CreateFrame("Frame", nil, S.list)
   row:SetHeight(ROW_H)
   row:EnableMouse(true)
   row:EnableMouseWheel(true)
   Skin.Backdrop(row, ROW_BG, COL.border)
   row.index = index

   local hl = row:CreateTexture(nil, "BACKGROUND")
   hl:SetTexture(Skin.WHITE)
   hl:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3], 0.12)
   hl:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
   hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
   hl:Hide()
   row.hl = hl

   -- gruener Streifen: das Outfit entspricht dem aktuellen Look
   local stripe = row:CreateTexture(nil, "OVERLAY")
   stripe:SetTexture(Skin.WHITE)
   stripe:SetVertexColor(COL.green[1], COL.green[2], COL.green[3], 1)
   stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
   stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
   stripe:SetWidth(3)
   stripe:Hide()
   row.stripe = stripe

   local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   name:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -7)
   name:SetWidth(100)
   name:SetHeight(16)
   name:SetJustifyH("LEFT")
   name:SetTextColor(0.92, 0.94, 0.97)
   row.name = name

   local info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   info:SetPoint("TOPRIGHT", row, "TOPRIGHT", -100, -9)
   info:SetWidth(60)
   info:SetHeight(14)
   info:SetJustifyH("RIGHT")
   row.info = info

   row.icons = {}
   for i = 1, MAX_ICONS do
      row.icons[i] = NewIcon(row)
   end

   local more = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   more:SetWidth(36)
   more:SetHeight(14)
   more:SetJustifyH("LEFT")
   more:Hide()
   row.more = more

   -- Knoepfe (Position und Breite setzt LayoutRow)
   row.load = Skin.Button(row, S.btnW, BTN_H, L.OUTFITS_LOAD, function()
      if row.outfitName then OutfitsTab.LoadOutfit(row.outfitName) end
   end)
   row.load:SetTheme("primary")
   row.load.tip = function(tt)
      tt:AddLine(L.OUTFITS_LOAD, 1, 1, 1)
      tt:AddLine(L.OUTFITS_LOAD_TIP, 0.78, 0.81, 0.86, true)
   end

   row.over = Skin.Button(row, S.btnW, BTN_H, L.OUTFITS_OVERWRITE, function()
      if row.outfitName then OutfitsTab.PromptOverwrite(row.outfitName) end
   end)
   row.over.tip = function(tt)
      tt:AddLine(L.OUTFITS_OVERWRITE, 1, 1, 1)
      tt:AddLine(L.OUTFITS_OVERWRITE_TIP, 0.78, 0.81, 0.86, true)
   end

   row.ren = Skin.Button(row, S.btnW, BTN_H, L.OUTFITS_RENAME, function()
      if row.outfitName then OutfitsTab.PromptRename(row.outfitName) end
   end)
   row.ren.tip = function(tt)
      tt:AddLine(L.OUTFITS_RENAME, 1, 1, 1)
      tt:AddLine(L.OUTFITS_RENAME_TIP, 0.78, 0.81, 0.86, true)
   end

   row.del = Skin.Button(row, S.btnW, BTN_H, L.OUTFITS_DELETE, function()
      if row.outfitName then OutfitsTab.PromptDelete(row.outfitName) end
   end)
   row.del:SetTextColor(COL.red[1], COL.red[2], COL.red[3])
   row.del.tip = function(tt)
      tt:AddLine(L.OUTFITS_DELETE, 1, 1, 1)
      tt:AddLine(L.OUTFITS_DELETE_TIP, 0.78, 0.81, 0.86, true)
   end

   -- Hover: Zeile und Kinder teilen sich die Hervorhebung
   row:SetScript("OnEnter", function(self)
      self.hl:Show()
      S.tipRow = self
      ShowRowTip(self)
   end)
   row:SetScript("OnLeave", function(self)
      if S.tipRow == self then S.tipRow = nil end
      Skin.HideTooltip(self)
      RowHover(self)
   end)
   row:SetScript("OnHide", function(self)
      self.hl:Hide()
      if S.tipRow == self then S.tipRow = nil end
      Skin.HideTooltip(self)
   end)
   row:SetScript("OnMouseWheel", function(_, delta)
      OutfitsTab.Page((delta or 0) > 0 and -1 or 1)
   end)

   local buttons = { row.load, row.over, row.ren, row.del }
   for i = 1, #buttons do
      local b = buttons[i]
      b:EnableMouseWheel(true)
      b:SetScript("OnMouseWheel", function(_, delta)
         OutfitsTab.Page((delta or 0) > 0 and -1 or 1)
      end)
      b:HookScript("OnEnter", function() row.hl:Show() end)
      b:HookScript("OnLeave", function() RowHover(row) end)
   end

   row:Hide()
   return row
end

-- Position und Breite der Teile einer Zeile (abhaengig von der Reiterbreite)
local function LayoutRow(row)
   local w = S.w
   local bw = S.btnW
   local rightW = 2 * bw + 4
   row:SetWidth(w)

   local x2 = w - 8 - bw        -- rechte Knopfspalte
   local x1 = x2 - 4 - bw       -- linke Knopfspalte
   row.load:SetWidth(bw)
   row.over:SetWidth(bw)
   row.ren:SetWidth(bw)
   row.del:SetWidth(bw)
   row.load:ClearAllPoints()
   row.load:SetPoint("TOPLEFT", row, "TOPLEFT", x1, -4)
   row.over:ClearAllPoints()
   row.over:SetPoint("TOPLEFT", row, "TOPLEFT", x2, -4)
   row.ren:ClearAllPoints()
   row.ren:SetPoint("TOPLEFT", row, "TOPLEFT", x1, -(4 + BTN_H + 4))
   row.del:ClearAllPoints()
   row.del:SetPoint("TOPLEFT", row, "TOPLEFT", x2, -(4 + BTN_H + 4))

   -- linker Bereich: Name, Info, Symbole
   local leftW = max(40, w - 8 - rightW - 8 - PAD)
   row.leftW = leftW
   row.info:ClearAllPoints()
   row.info:SetPoint("TOPRIGHT", row, "TOPLEFT", PAD + leftW, -9)
   row.fit = max(1, floor((leftW + ICON_GAP) / (ICON + ICON_GAP)))   -- Symbole, die links der Knoepfe passen
   for i = 1, MAX_ICONS do
      local f = row.icons[i].frame
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", row, "TOPLEFT", PAD + (i - 1) * (ICON + ICON_GAP), -26)
   end
end

-- Befuellt eine Zeile mit einem Outfit
local function FillRow(row, o)
   row.outfitName = o.name

   local pieces = o.count or CountSlots(o.slots)
   local _, skipped = Outfits.Check(o.name)
   -- Teile, die auf eine noch ladende Liste warten, gelten nicht als fehlend
   -- (sonst stuende beim Oeffnen kurz "Verfuegbar: 0 von n" in Gelb)
   local nMissing = #skipped - CountLoading(skipped)
   local nOk = max(0, pieces - nMissing)
   local current = SameLook(o.slots, S.look)

   -- Info (Teile/verfuegbar)
   local infoText, ir, ig, ib
   if nOk >= pieces then
      infoText = Util.Format(L.OUTFITS_PIECES, pieces)
      ir, ig, ib = COL.dim[1], COL.dim[2], COL.dim[3]
   else
      infoText = Util.Format(L.OUTFITS_PIECES_PARTIAL, nOk, pieces)
      ir, ig, ib = COL.yellow[1], COL.yellow[2], COL.yellow[3]
   end
   local leftW = row.leftW or 100
   -- hoechstens die Haelfte des linken Bereichs; passt der Text nicht hinein
   -- (lange Uebersetzung, Mindestbreite), steht stattdessen eine sprachneutrale
   -- Kurzform: lieber "7/10" als ein mitten in der Zahl abgeschnittenes "... 7 von"
   local maxInfo = max(40, floor(leftW * 0.5))
   if ceil(TextWidth(infoText)) + 2 > maxInfo then
      if nOk >= pieces then
         infoText = Util.Format("%d", pieces)
      else
         infoText = Util.Format("%d/%d", nOk, pieces)
      end
   end
   local iw = min(ceil(TextWidth(infoText)) + 2, maxInfo)
   row.info:SetText(infoText)
   row.info:SetTextColor(ir, ig, ib)
   row.info:SetWidth(iw)

   row.name:SetText(o.name)
   row.name:SetWidth(max(20, leftW - iw - 8))

   if current then
      row.stripe:Show()
      row:SetBackdropBorderColor(ROW_BORDER_CURRENT[1], ROW_BORDER_CURRENT[2], ROW_BORDER_CURRENT[3], 1)
   else
      row.stripe:Hide()
      row:SetBackdropBorderColor(COL.border[1], COL.border[2], COL.border[3], 1)
   end

   -- Symbole in Anzeigereihenfolge der Slots. Es werden hoechstens MAX_ICONS
   -- gezeigt und nur so viele, wie links der Knoepfe passen; muessen Teile
   -- weggelassen werden, bleibt ein Feld fuer den Zaehler "+n" frei.
   local ids = {}
   for i = 1, #Slots.LIST do
      local id = tonumber(o.slots[Slots.LIST[i].server])
      if id then ids[#ids + 1] = id end
   end
   local total = #ids
   local fit = row.fit or MAX_ICONS
   local cap = min(MAX_ICONS, fit)
   if total > cap then
      cap = min(MAX_ICONS, max(1, fit - 1))
   end
   local shown = min(total, cap)
   for i = 1, shown do
      PaintIcon(row.icons[i], ids[i])
   end
   for i = shown + 1, MAX_ICONS do
      row.icons[i].frame:Hide()
   end
   if total > shown then
      row.more:ClearAllPoints()
      row.more:SetPoint("TOPLEFT", row, "TOPLEFT", PAD + shown * (ICON + ICON_GAP) + 2, -31)
      row.more:SetText(Util.Format("+%d", total - shown))
      row.more:Show()
   else
      row.more:Hide()
   end

   -- "Ueberschreiben" braucht einen Look, der gespeichert werden kann
   row.over:SetEnabledState(S.hasLook, L.OUTFIT_ERR_NOITEMS)
end

-- Setzt die Beschriftungen und die gemeinsame Knopfbreite
local function RelabelRows()
   local labels = { L.OUTFITS_LOAD, L.OUTFITS_OVERWRITE, L.OUTFITS_RENAME, L.OUTFITS_DELETE }
   local widest = 0
   for i = 1, #labels do
      widest = max(widest, TextWidth(labels[i]))
   end
   S.btnW = max(BTN_MIN, min(BTN_MAX, ceil(widest) + 16))
   for i = 1, #S.rows do
      local row = S.rows[i]
      row.load:SetLabel(L.OUTFITS_LOAD)
      row.over:SetLabel(L.OUTFITS_OVERWRITE)
      row.ren:SetLabel(L.OUTFITS_RENAME)
      row.del:SetLabel(L.OUTFITS_DELETE)
   end
end

-- ---------------------------------------------------------------------------
-- Zeichnen
-- ---------------------------------------------------------------------------

-- Zaehler, Speichern-Knopf und Blaetterleiste
local function PaintHeader()
   local count = S.count
   S.counter:SetText(Util.Format(L.OUTFITS_COUNT, count, Outfits.MAX))
   if count >= Outfits.MAX then
      S.counter:SetTextColor(COL.red[1], COL.red[2], COL.red[3])
   else
      S.counter:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
   end

   if count >= Outfits.MAX then
      S.saveBtn:SetEnabledState(false, L.OUTFIT_ERR_FULL)
   elseif not S.hasLook then
      S.saveBtn:SetEnabledState(false, L.OUTFIT_ERR_NOITEMS)
   else
      S.saveBtn:SetEnabledState(true)
   end

   S.pageText:SetText(Util.Format(L.OUTFITS_PAGE, OutfitsTab.page, OutfitsTab.pages))
   S.prevBtn:SetEnabledState(OutfitsTab.page > 1)
   S.nextBtn:SetEnabledState(OutfitsTab.page < OutfitsTab.pages)
end

-- OutfitsTab.Refresh() -- Liste neu zeichnen (sichtbar) oder vormerken
function OutfitsTab.Refresh()
   if not S.tab then return end
   if not IsVisible() then
      S.dirty = true
      return
   end
   S.dirty = false

   local list = Outfits.List()
   local count = #list
   S.outfits, S.count = list, count
   S.look = Outfits.CurrentLook()
   S.hasLook = next(S.look) ~= nil

   -- frisch gespeichertes Outfit: seine Seite zeigen (es steht am Ende der Liste)
   if S.showName then
      for i = 1, count do
         if list[i].name == S.showName then
            OutfitsTab.page = ceil(i / OutfitsTab.perPage)
            break
         end
      end
      S.showName = nil
   end

   OutfitsTab.pages = max(1, ceil(count / OutfitsTab.perPage))
   if OutfitsTab.page > OutfitsTab.pages then OutfitsTab.page = OutfitsTab.pages end
   if OutfitsTab.page < 1 then OutfitsTab.page = 1 end

   PaintHeader()

   if count == 0 then
      S.empty:Show()
      S.list:Hide()
      S.pager:Hide()
      for i = 1, #S.rows do S.rows[i]:Hide() end
      return
   end
   S.empty:Hide()
   S.list:Show()
   S.pager:Show()

   local first = (OutfitsTab.page - 1) * OutfitsTab.perPage
   for i = 1, #S.rows do
      local row = S.rows[i]
      local o = (i <= OutfitsTab.perPage) and list[first + i] or nil
      if o then
         FillRow(row, o)
         row:Show()
         -- Item-Daten fuer Symbole/Tooltip anfordern (nur die sichtbaren Outfits)
         Outfits.RequestItems(o.name)
      else
         row.outfitName = nil
         row:Hide()
      end
   end

   -- Zeigt die Maus gerade auf einer Zeile, deren Inhalt sich geaendert hat: Tooltip erneuern
   local tr = S.tipRow
   if tr and tr:IsShown() and tr.outfitName and GameTooltip:IsOwned(tr) then
      ShowRowTip(tr)
   end
end

-- Vormerken und gebuendelt neu zeichnen (nur wenn sichtbar)
local function RequestRefresh()
   S.dirty = true
   if IsVisible() then
      Util.Debounce("ui-outfits", 0.05, function() OutfitsTab.Refresh() end)
   end
end

-- ---------------------------------------------------------------------------
-- Oeffentliche Funktionen
-- ---------------------------------------------------------------------------

-- OutfitsTab.SetPage(n) -- Seite waehlen (wird geklemmt) und neu zeichnen
function OutfitsTab.SetPage(n)
   n = floor(tonumber(n) or 1)
   if n < 1 then n = 1 end
   if n > OutfitsTab.pages then n = OutfitsTab.pages end
   if n == OutfitsTab.page then return end
   OutfitsTab.page = n
   OutfitsTab.Refresh()
end

-- OutfitsTab.Page(dir) -- eine Seite vor (dir > 0) oder zurueck (dir < 0)
function OutfitsTab.Page(dir)
   if type(dir) ~= "number" or dir == 0 then return end
   OutfitsTab.SetPage(OutfitsTab.page + (dir > 0 and 1 or -1))
end

-- OutfitsTab.Layout(w, h) -- Reiter w x h; rechnet Zeilen je Seite und zeichnet neu.
-- Bei unveraenderter Groesse (das Fenster ruft oft) wird nur nachgezeichnet.
function OutfitsTab.Layout(w, h)
   if not S.tab then return end
   w = floor(tonumber(w) or S.w or 0)
   h = floor(tonumber(h) or S.h or 0)
   if w < 120 then w = 120 end
   if h < TOP_H + GAP + ROW_H then h = TOP_H + GAP + ROW_H end
   if w == S.w and h == S.h and not S.relayout then
      if S.dirty and IsVisible() then OutfitsTab.Refresh() end
      return
   end
   S.relayout = false
   S.w, S.h = w, h
   S.tab:SetWidth(w)
   S.tab:SetHeight(h)

   -- Kopfzeile: Zaehler rechts, Speichern-Knopf links (Breite nach Text, hoechstens der Rest)
   local label = L.OUTFITS_SAVE
   local saveW = max(120, min(ceil(TextWidth(label)) + 28, w - 90))
   S.saveBtn:SetWidth(saveW)
   S.saveBtn:ClearAllPoints()
   S.saveBtn:SetPoint("TOPLEFT", S.tab, "TOPLEFT", 0, -floor((TOP_H - SAVE_H) / 2))
   S.counter:ClearAllPoints()
   S.counter:SetPoint("TOPRIGHT", S.tab, "TOPRIGHT", -4, -floor((TOP_H - 14) / 2))

   -- Liste: Rest zwischen Kopf und Leiste
   local listTop = TOP_H + GAP
   local listH = max(ROW_H, h - listTop - GAP - PAGER_H)
   S.list:ClearAllPoints()
   S.list:SetPoint("TOPLEFT", S.tab, "TOPLEFT", 0, -listTop)
   S.list:SetWidth(w)
   S.list:SetHeight(listH)
   OutfitsTab.perPage = max(1, floor((listH + ROW_GAP) / (ROW_H + ROW_GAP)))
   OutfitsTab.perPage = OutfitsTab.perPage

   -- Blaetterleiste
   S.pager:ClearAllPoints()
   S.pager:SetPoint("BOTTOMLEFT", S.tab, "BOTTOMLEFT", 0, 0)
   S.pager:SetWidth(w)
   S.pager:SetHeight(PAGER_H)

   -- Leerzustand: ueber der ganzen Listenflaeche
   S.empty:ClearAllPoints()
   S.empty:SetPoint("TOPLEFT", S.tab, "TOPLEFT", 0, -listTop)
   S.empty:SetWidth(w)
   S.empty:SetHeight(listH)
   local textW = max(60, min(w - 48, 460))
   S.emptyTitle:ClearAllPoints()
   S.emptyTitle:SetPoint("TOP", S.empty, "TOP", 0, -floor(min(listH * 0.25, 60)))
   S.emptyTitle:SetWidth(textW)
   S.emptyText:ClearAllPoints()
   S.emptyText:SetPoint("TOP", S.emptyTitle, "BOTTOM", 0, -10)
   S.emptyText:SetWidth(textW)
   S.emptyText:SetHeight(max(30, listH - 90))

   -- Zeilen: Vorrat auffuellen, positionieren
   for i = #S.rows + 1, OutfitsTab.perPage do
      S.rows[i] = NewRow(i)
   end
   for i = 1, #S.rows do
      local row = S.rows[i]
      LayoutRow(row)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", S.list, "TOPLEFT", 0, -((i - 1) * (ROW_H + ROW_GAP)))
      if i > OutfitsTab.perPage then row:Hide() end
   end

   S.dirty = true
   if IsVisible() then OutfitsTab.Refresh() end
end

-- OutfitsTab.ApplyLocale() -- setzt alle statischen Texte neu
function OutfitsTab.ApplyLocale()
   if not S.tab then return end
   S.saveBtn:SetLabel(L.OUTFITS_SAVE)
   S.emptyTitle:SetText(L.OUTFITS_EMPTY_TITLE)
   S.emptyText:SetText(L.OUTFITS_EMPTY_TEXT)
   RelabelRows()
   -- Breiten haengen von den Texten ab: neu rechnen, auch bei gleicher Groesse
   S.relayout = true
   if S.w > 0 then
      OutfitsTab.Layout(S.w, S.h)
   else
      S.dirty = true
   end
end

-- OutfitsTab.Show() / OutfitsTab.Hide()
function OutfitsTab.Show()
   if S.tab then S.tab:Show() end
end

function OutfitsTab.Hide()
   if S.tab then S.tab:Hide() end
end

-- OutfitsTab.IsShown() -> bool
function OutfitsTab.IsShown()
   return S.tab ~= nil and S.tab:IsShown() and true or false
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

-- OutfitsTab.Create(parent) -> Frame (baut einmal; weiteres Create liefert denselben)
function OutfitsTab.Create(parent)
   if S.tab then
      if parent and S.parent ~= parent then
         S.parent = parent
         S.tab:SetParent(parent)
      end
      return S.tab
   end
   parent = parent or UIParent
   S.parent = parent

   local tab = CreateFrame("Frame", nil, parent)
   tab:SetWidth(400)
   tab:SetHeight(300)
   tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
   tab:EnableMouseWheel(true)
   tab:SetScript("OnMouseWheel", function(_, delta)
      OutfitsTab.Page((delta or 0) > 0 and -1 or 1)
   end)
   S.tab = tab

   -- Kopfzeile
   S.saveBtn = Skin.Button(tab, 160, SAVE_H, L.OUTFITS_SAVE, function()
      OutfitsTab.PromptSave()
   end)
   S.saveBtn:SetTheme("primary")
   S.saveBtn.tip = function(tt)
      tt:AddLine(L.OUTFITS_SAVE, 1, 1, 1)
      tt:AddLine(L.OUTFITS_SAVE_TIP, 0.78, 0.81, 0.86, true)
   end

   S.counter = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   S.counter:SetWidth(90)
   S.counter:SetHeight(14)
   S.counter:SetJustifyH("RIGHT")

   -- Liste (nimmt die Zeilen auf; selbst ohne Maus)
   S.list = CreateFrame("Frame", nil, tab)
   S.list:SetWidth(400)
   S.list:SetHeight(ROW_H)

   -- Blaetterleiste
   S.pager = CreateFrame("Frame", nil, tab)
   S.pager:SetWidth(400)
   S.pager:SetHeight(PAGER_H)
   S.pageText = S.pager:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   S.pageText:SetPoint("CENTER", S.pager, "CENTER", 0, 0)
   S.pageText:SetWidth(120)
   S.pageText:SetHeight(14)
   S.pageText:SetJustifyH("CENTER")
   S.prevBtn = Skin.Button(S.pager, 30, 22, "<", function() OutfitsTab.Page(-1) end)
   S.prevBtn:SetPoint("CENTER", S.pager, "CENTER", -(60 + 8 + 15), 0)
   S.prevBtn.tip = function(tt) tt:AddLine(L.OUTFITS_PAGE_PREV, 1, 1, 1) end
   S.nextBtn = Skin.Button(S.pager, 30, 22, ">", function() OutfitsTab.Page(1) end)
   S.nextBtn:SetPoint("CENTER", S.pager, "CENTER", 60 + 8 + 15, 0)
   S.nextBtn.tip = function(tt) tt:AddLine(L.OUTFITS_PAGE_NEXT, 1, 1, 1) end

   -- Leerzustand
   S.empty = CreateFrame("Frame", nil, tab)
   S.empty:SetWidth(400)
   S.empty:SetHeight(200)
   S.emptyTitle = S.empty:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
   S.emptyTitle:SetHeight(20)
   S.emptyTitle:SetJustifyH("CENTER")
   S.emptyTitle:SetTextColor(0.92, 0.94, 0.97)
   S.emptyText = S.empty:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
   S.emptyText:SetJustifyH("CENTER")
   S.emptyText:SetJustifyV("TOP")
   if S.emptyText.SetNonSpaceWrap then S.emptyText:SetNonSpaceWrap(true) end
   S.emptyText:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
   S.emptyTitle:SetText(L.OUTFITS_EMPTY_TITLE)
   S.emptyText:SetText(L.OUTFITS_EMPTY_TEXT)
   S.empty:Hide()

   -- Methoden auch am Frame (Doppelpunkt-Aufruf)
   tab.Layout = function(_, w, h) return OutfitsTab.Layout(w, h) end
   tab.Refresh = function() return OutfitsTab.Refresh() end
   tab.SetPage = function(_, n) return OutfitsTab.SetPage(n) end
   tab.Page = function(_, dir) return OutfitsTab.Page(dir) end
   tab.ApplyLocale = function() return OutfitsTab.ApplyLocale() end

   tab:SetScript("OnShow", function()
      if S.dirty then OutfitsTab.Refresh() end
   end)

   -- Ereignisse
   Events.On("OUTFITS_CHANGED", RequestRefresh, OutfitsTab)
   Events.On("WANTED_CHANGED", RequestRefresh, OutfitsTab)
   Events.On("STATUS_CHANGED", RequestRefresh, OutfitsTab)
   Events.On("LIST_READY", RequestRefresh, OutfitsTab)
   Events.On("EQUIPMENT_CHANGED", RequestRefresh, OutfitsTab)
   Events.On("ITEMS_RESOLVED", RequestRefresh, OutfitsTab)
   Events.On("LOCALE_CHANGED", function() OutfitsTab.ApplyLocale() end, OutfitsTab)

   -- Zugriff fuer Tests und das Fenster: Frame, Zeilenvorrat, Einzelteile
   OutfitsTab.frame = tab
   OutfitsTab.rows = S.rows
   OutfitsTab.parts = {
      save = S.saveBtn, counter = S.counter, list = S.list, pager = S.pager,
      pageText = S.pageText, prev = S.prevBtn, next = S.nextBtn, empty = S.empty,
      emptyTitle = S.emptyTitle, emptyText = S.emptyText,
   }

   RelabelRows()
   OutfitsTab.page, OutfitsTab.pages, OutfitsTab.perPage = 1, 1, 1
   S.dirty = true
   OutfitsTab.Layout(400, 300)
   return tab
end
