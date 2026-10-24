-- UI\Options.lua  (T.UI.Options)
-- ---------------------------------------------------------------------------
-- Eigenes flaches Optionsfenster (kein Interface-Options-Frame):
--
--   +----------------------------------------------+
--   | Transmog options                          [x]|  Kopf 30 (Skin.Header)
--   +----------------------------------------------+
--   | Language ------------------------------------|
--   |  [ Auto (client language: English)        v ]|
--   |  Hinweis zur Schrift                         |
--   | Window --------------------------------------|
--   |  Window scale        [====o-------]  Auto    |
--   |  Preview size        [S] [M] [L] [XL]        |
--   |  [ Reset window position and size ]          |
--   | General -------------------------------------|
--   |  [x] Sound when applying                     |
--   |  [x] Notifications for new appearances       |
--   |  [x] Tooltip: ... / [x] Tooltip: ...         |
--   |  [ ] Allow applying without a transmogrifier |
--   |  [ Move notifications ] [ Test notification ]|
--   +----------------------------------------------+
--
-- Schnittstelle (SPEC 6.10 / 11.2):
--   Options.Open() / Options.Close() / Options.Toggle() / Options.IsShown()
--   Options.Refresh()       Steuerelemente aus DB.global lesen (bei Open und SETTINGS_CHANGED)
--   Options.ApplyLocale()   alle Texte neu setzen (bei LOCALE_CHANGED)
--   Options.frame, Options.controls   Rahmen und Steuerelemente (nach dem ersten Open)
--
-- Alle Aenderungen wirken sofort ueber DB.Set (feuert SETTINGS_CHANGED); die
-- Module, die den Wert brauchen (Fenster: scale/width/height, Raster:
-- previewSize, Tooltips, Toasts), hoeren selbst darauf (SPEC 11.3). Modul-
-- aufrufe gibt es nur fuer die Knoepfe (Window.ResetLayout, Toasts.ShowAnchor,
-- Toasts.Test) und nur, wenn das Modul existiert.
--
-- Skalierung: das Optionsfenster oeffnet in der Skalierung des Hauptfensters
-- (Window.ComputeScale, sonst DB.global.scale, sonst 1.0). Waehrend es offen
-- ist, bleibt sie, damit der Regler beim Ziehen nicht unter der Maus wandert.
--
-- Sprachen, die die Schrift des Clients nicht darstellen kann (Kyrillisch/CJK
-- auf lateinischem Client), tragen im Menue und am Knopf den Code dahinter
-- ("<russischer Name> (ruRU)"), damit sie erkennbar bleiben; der gelbe Schrifthinweis
-- erscheint nur dann (Lateinisch kann jeder Client).
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.UI = T.UI or {}

local Options = {}
T.UI.Options = Options

local L = T.L
local Util = T.Util
local Events = T.Events
local DB = T.DB
local Skin = T.UI.Skin
local COL = Skin.COL

local floor = math.floor
local format = string.format

-- ---------------------------------------------------------------------------
-- Masse und Tabellen
-- ---------------------------------------------------------------------------

local FRAME_NAME = "TransmogOptionsFrame"
local WIDTH = 400
local PAD = 16
local INNER = WIDTH - 2 * PAD
local HEAD_H = 30
local ROW = 24
local VALUE_W = 80          -- Platz rechts vom Regler fuer den Wertetext (8 Abstand + 72)

-- Fensterskalierung: Schieberegler in Prozent. Die linke Raste (55) bedeutet
-- "Auto" (DB scale = 0); danach 60 .. 150 in 5er-Schritten.
local SCALE_AUTO, SCALE_MIN, SCALE_MAX, SCALE_STEP = 55, 60, 150, 5

-- Vorschaugroessen (DB previewSize) mit ihren Beschriftungs-Schluesseln
local PREVIEW_SIZES = {
   { value = 0.8, key = "OPT_PREVIEW_SMALL" },
   { value = 1.0, key = "OPT_PREVIEW_MEDIUM" },
   { value = 1.25, key = "OPT_PREVIEW_LARGE" },
   { value = 1.5, key = "OPT_PREVIEW_XLARGE" },
}

-- Haken: DB-Schluessel, Beschriftung, Erklaerung
local CHECKS = {
   { key = "sound", label = "OPT_SOUND", tip = "OPT_SOUND_TIP" },
   { key = "toasts", label = "OPT_TOASTS", tip = "OPT_TOASTS_TIP" },
   { key = "tooltipCollected", label = "OPT_TOOLTIP_COLLECTED", tip = "OPT_TOOLTIP_COLLECTED_TIP" },
   { key = "tooltipApplied", label = "OPT_TOOLTIP_APPLIED", tip = "OPT_TOOLTIP_APPLIED_TIP" },
   { key = "allowAnywhere", label = "OPT_ALLOW_ANYWHERE", tip = "OPT_ALLOW_ANYWHERE_TIP" },
}

-- Ersatzsprachen (wie Locale.lua) und Schriftgruppen: ausserhalb der Gruppe
-- des Clients fehlen der Schrift oft Zeichen. Lateinische Zeichen kann jede
-- Clientschrift (auch die koreanische/chinesische), Kyrillisch und CJK nur die
-- eigene.
local ALIAS = { enGB = "enUS", esMX = "esES", enCN = "enUS", enTW = "enUS" }
local GROUP = {
   enUS = "latin", enGB = "latin", deDE = "latin", frFR = "latin", esES = "latin",
   esMX = "latin", ruRU = "cyrillic", koKR = "korean", zhCN = "hans", zhTW = "hant",
}

-- ---------------------------------------------------------------------------
-- Zustand
-- ---------------------------------------------------------------------------

local O = {
   frame = nil,
   texts = {},        -- { obj=, key=, method= } fuer ApplyLocale
   checks = {},       -- [dbKey] = Skin.Check
   sizeBtns = {},     -- Vorschaugroessen-Knoepfe (value = Faktor)
}

-- ---------------------------------------------------------------------------
-- Sprache
-- ---------------------------------------------------------------------------

-- Sprachcode des Spielclients (GetLocale), "enUS" als Ersatz
local function ClientLocale()
   local code = "enUS"
   if type(GetLocale) == "function" then
      local ok, c = pcall(GetLocale)
      if ok and type(c) == "string" and c ~= "" then code = c end
   end
   return code
end

-- Schriftgruppe eines Sprachcodes (Ersatzsprachen beachtet; unbekannt = lateinisch)
local function GroupOf(code)
   return GROUP[code] or GROUP[ALIAS[code] or ""] or "latin"
end

-- Kann die Schrift des Clients die Zeichen der Sprache `code` darstellen?
local function Readable(code)
   local g = GroupOf(code)
   return g == "latin" or g == GroupOf(ClientLocale())
end

-- Eintrag { code, name } aus Locale.List() zu einem Code (Ersatzsprachen beachtet)
local function ListEntry(code)
   local list = T.Locale.List()
   for i = 1, #list do
      if list[i].code == code then return list[i] end
   end
   local alias = ALIAS[code]
   if alias then
      for i = 1, #list do
         if list[i].code == alias then return list[i] end
      end
   end
   return nil
end

-- Anzeigename einer Sprache: der native Name; kann die Clientschrift ihn nicht
-- darstellen (Kyrillisch/CJK auf einem westlichen Client), steht der Code in
-- Klammern dahinter, damit der Eintrag trotzdem erkennbar bleibt.
local function DisplayName(entry)
   if entry.code and not Readable(entry.code) then
      return entry.name .. " (" .. entry.code .. ")"
   end
   return entry.name
end

-- Name der Clientsprache (nativ), sonst der Code
local function ClientName()
   local code = ClientLocale()
   local entry = ListEntry(code)
   return entry and entry.name or code
end

-- Beschriftung des Sprachknopfs zur gespeicherten Einstellung
local function LanguageLabel(code)
   if code == nil or code == "auto" then
      return Util.Format(L.OPT_LANG_AUTO, ClientName())
   end
   local entry = ListEntry(code)
   return entry and DisplayName(entry) or tostring(code)
end

-- Setzt die Sprache: Einstellung speichern und die Texte umschalten
local function SetLanguage(code)
   DB.Set("locale", code)
   if type(T.Locale) == "table" and type(T.Locale.Set) == "function" then
      T.Locale.Set(code)
   end
end

-- Oeffnet das Sprachmenue am Knopf: Auto + alle Sprachen (native Namen)
local function OpenLanguageMenu(anchor)
   local g = DB.global or {}
   local cur = g.locale
   if cur == nil then cur = "auto" end
   local curEntry = nil
   if cur ~= "auto" then curEntry = ListEntry(cur) end

   local items = {
      {
         text = Util.Format(L.OPT_LANG_AUTO, ClientName()),
         radio = true,
         checked = (cur == "auto"),
         onClick = function() SetLanguage("auto") end,
      },
   }
   local list = T.Locale.List()
   for i = 1, #list do
      local code = list[i].code
      items[#items + 1] = {
         text = DisplayName(list[i]),
         radio = true,
         checked = (curEntry ~= nil and curEntry.code == code),
         onClick = function() SetLanguage(code) end,
      }
   end
   Skin.Menu.Open(anchor, items, {})
end

-- ---------------------------------------------------------------------------
-- Umrechnung Schieberegler <-> DB
-- ---------------------------------------------------------------------------

-- DB.scale (0 = Auto, sonst 0.6 .. 1.5) -> Reglerwert (55 .. 150)
local function ScaleToSlider(scale)
   scale = tonumber(scale) or 0
   if scale <= 0 then return SCALE_AUTO end
   local v = floor(scale * 100 / SCALE_STEP + 0.5) * SCALE_STEP
   if v < SCALE_MIN then v = SCALE_MIN end
   if v > SCALE_MAX then v = SCALE_MAX end
   return v
end

-- Reglerwert -> DB.scale
local function SliderToScale(v)
   v = tonumber(v) or SCALE_AUTO
   if v < SCALE_MIN then return 0 end
   return v / 100
end

-- ---------------------------------------------------------------------------
-- Bausteine
-- ---------------------------------------------------------------------------

-- Alle Texte des Fensters als Tabelle [Schluessel] = aktueller Text. Die
-- L.KEY-Zugriffe sind bewusst ausgeschrieben (kein L[key]), damit die
-- Locale-Pruefung jeden Schluessel statisch findet.
local function Texts()
   return {
      OPT_TITLE = L.OPT_TITLE,
      OPT_SECTION_LANGUAGE = L.OPT_SECTION_LANGUAGE,
      OPT_LANG_AUTO = L.OPT_LANG_AUTO,
      OPT_LANG_TIP = L.OPT_LANG_TIP,
      OPT_LANG_NOTE = L.OPT_LANG_NOTE,
      OPT_SECTION_WINDOW = L.OPT_SECTION_WINDOW,
      OPT_SCALE = L.OPT_SCALE,
      OPT_SCALE_AUTO = L.OPT_SCALE_AUTO,
      OPT_SCALE_TIP = L.OPT_SCALE_TIP,
      OPT_PREVIEW_SIZE = L.OPT_PREVIEW_SIZE,
      OPT_PREVIEW_TIP = L.OPT_PREVIEW_TIP,
      OPT_PREVIEW_SMALL = L.OPT_PREVIEW_SMALL,
      OPT_PREVIEW_MEDIUM = L.OPT_PREVIEW_MEDIUM,
      OPT_PREVIEW_LARGE = L.OPT_PREVIEW_LARGE,
      OPT_PREVIEW_XLARGE = L.OPT_PREVIEW_XLARGE,
      OPT_RESET_WINDOW = L.OPT_RESET_WINDOW,
      OPT_RESET_WINDOW_TIP = L.OPT_RESET_WINDOW_TIP,
      OPT_RESET_DONE = L.OPT_RESET_DONE,
      OPT_SECTION_GENERAL = L.OPT_SECTION_GENERAL,
      OPT_SOUND = L.OPT_SOUND,
      OPT_SOUND_TIP = L.OPT_SOUND_TIP,
      OPT_TOASTS = L.OPT_TOASTS,
      OPT_TOASTS_TIP = L.OPT_TOASTS_TIP,
      OPT_TOOLTIP_COLLECTED = L.OPT_TOOLTIP_COLLECTED,
      OPT_TOOLTIP_COLLECTED_TIP = L.OPT_TOOLTIP_COLLECTED_TIP,
      OPT_TOOLTIP_APPLIED = L.OPT_TOOLTIP_APPLIED,
      OPT_TOOLTIP_APPLIED_TIP = L.OPT_TOOLTIP_APPLIED_TIP,
      OPT_ALLOW_ANYWHERE = L.OPT_ALLOW_ANYWHERE,
      OPT_ALLOW_ANYWHERE_TIP = L.OPT_ALLOW_ANYWHERE_TIP,
      OPT_MOVE_TOASTS = L.OPT_MOVE_TOASTS,
      OPT_MOVE_TOASTS_TIP = L.OPT_MOVE_TOASTS_TIP,
      OPT_TEST_TOAST = L.OPT_TEST_TOAST,
      OPT_TEST_TOAST_TIP = L.OPT_TEST_TOAST_TIP,
   }
end

-- Merkt Text-Objekte fuer ApplyLocale und setzt den Text gleich
local function Reg(obj, key, method)
   O.texts[#O.texts + 1] = { obj = obj, key = key, method = method or "SetText" }
   obj[method or "SetText"](obj, Texts()[key])
   return obj
end

-- Abschnittstitel mit Trennlinie; Rueckgabe: neue y-Position
local function Section(f, y, key)
   local fs = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
   fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
   fs:SetWidth(INNER)
   fs:SetHeight(16)
   fs:SetJustifyH("LEFT")
   fs:SetTextColor(COL.blue[1], COL.blue[2], COL.blue[3])
   Reg(fs, key)

   local line = Skin.Divider(f)
   line:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(y + 19))
   line:SetWidth(INNER)
   return y + 28
end

-- Beschriftung ueber einem Steuerelement; Rueckgabe: FontString
local function Caption(f, y, key)
   local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
   fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
   fs:SetWidth(INNER)
   fs:SetHeight(14)
   fs:SetJustifyH("LEFT")
   fs:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
   Reg(fs, key)
   return fs
end

-- Erklaerung als Tooltip eines Widgets: Titel (weiss) + Text (grau, umbrochen)
local function SetTip(widget, titleKey, textKey)
   widget.tip = function(tt)
      local tx = Texts()
      tt:AddLine(tx[titleKey], 1, 1, 1)
      if textKey then
         tt:AddLine(tx[textKey], 0.78, 0.81, 0.86, true)
      end
   end
end

-- ---------------------------------------------------------------------------
-- Anzeige aktualisieren
-- ---------------------------------------------------------------------------

-- Options.Refresh() -- liest DB.global in alle Steuerelemente (ohne DB zu schreiben)
function Options.Refresh()
   if not O.frame then return end
   local g = DB.global
   if type(g) ~= "table" then return end

   -- Sprache + Schrifthinweis (gelb, wenn die Schriftgruppe vom Client abweicht)
   O.langBtn:SetLabel(LanguageLabel(g.locale))
   local mismatch = not Readable(T.Locale.Current())
   if mismatch then
      O.note:SetTextColor(COL.yellow[1], COL.yellow[2], COL.yellow[3])
   else
      O.note:SetTextColor(COL.dim[1], COL.dim[2], COL.dim[3])
   end

   -- Fenster
   O.scale:SetValueQuiet(ScaleToSlider(g.scale))
   local size = tonumber(g.previewSize) or 1
   for i = 1, #O.sizeBtns do
      local b = O.sizeBtns[i]
      b:SetSelected(math.abs(b.value - size) < 0.001)
   end

   -- Haken
   for key, c in pairs(O.checks) do
      c:SetChecked(g[key] and true or false)
   end
end

-- Options.ApplyLocale() -- setzt alle statischen Texte neu
function Options.ApplyLocale()
   if not O.frame then return end
   local tx = Texts()
   for i = 1, #O.texts do
      local e = O.texts[i]
      e.obj[e.method](e.obj, tx[e.key])
   end
   O.head:SetTitle(L.OPT_TITLE)
   O.scale:RefreshText()
   Options.Refresh()
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

-- Baut das Fenster einmal (Rueckgabe: Frame)
local function Build()
   if O.frame then return O.frame end

   local f = CreateFrame("Frame", FRAME_NAME, UIParent)
   f:SetFrameStrata("DIALOG")
   f:SetWidth(WIDTH)
   f:SetHeight(480)
   f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
   f:SetClampedToScreen(true)
   f:SetMovable(true)
   f:EnableMouse(true)
   f:RegisterForDrag("LeftButton")
   f:SetScript("OnDragStart", function(self) self:StartMoving() end)
   f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
   Skin.Backdrop(f, COL.bgSolid, COL.border)
   f:Hide()
   O.frame = f

   -- ESC schliesst
   if UISpecialFrames then
      local found = false
      for i = 1, #UISpecialFrames do
         if UISpecialFrames[i] == FRAME_NAME then found = true end
      end
      if not found then table.insert(UISpecialFrames, FRAME_NAME) end
   end

   -- Kopf mit Schliessen-Knopf
   O.head = Skin.Header(f, L.OPT_TITLE, HEAD_H)
   O.close = Skin.Button(O.head, 22, 20, "x", function() Options.Close() end)
   O.close:SetPoint("RIGHT", O.head, "RIGHT", -6, 0)
   O.close.tip = function(tt) tt:AddLine(Util.G("CLOSE", "Close"), 1, 1, 1) end

   local y = HEAD_H + 12

   -- Sprache -------------------------------------------------------------
   y = Section(f, y, "OPT_SECTION_LANGUAGE")
   O.langBtn = Skin.Button(f, INNER, ROW, "", function(self) OpenLanguageMenu(self) end)
   O.langBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
   SetTip(O.langBtn, "OPT_SECTION_LANGUAGE", "OPT_LANG_TIP")
   local arrow = O.langBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   arrow:SetPoint("RIGHT", O.langBtn, "RIGHT", -8, 0)
   arrow:SetText("v")
   y = y + ROW + 4

   O.note = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
   O.note:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
   O.note:SetWidth(INNER)
   O.note:SetHeight(26)
   O.note:SetJustifyH("LEFT")
   O.note:SetJustifyV("TOP")
   if O.note.SetNonSpaceWrap then O.note:SetNonSpaceWrap(true) end
   Reg(O.note, "OPT_LANG_NOTE")
   y = y + 26 + 10

   -- Fenster -------------------------------------------------------------
   y = Section(f, y, "OPT_SECTION_WINDOW")

   Caption(f, y, "OPT_SCALE")
   y = y + 18
   -- Das Hauptfenster hoert auf SETTINGS_CHANGED("scale") und wendet den Wert
   -- selbst an (SPEC 11.3); ein eigener Aufruf von Window.ApplyScale wuerde jede
   -- Reglerstufe doppelt anordnen.
   O.scale = Skin.Slider(f, INNER - VALUE_W, SCALE_AUTO, SCALE_MAX, SCALE_STEP, function(v)
      DB.Set("scale", SliderToScale(v))
   end)
   O.scale:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(y + 2))
   -- Wertetext mit fester Breite: auch ein langes "Automatisch" bleibt im Fenster
   O.scale.valueText:SetWidth(VALUE_W - 12)
   O.scale.formatter = function(v)
      if v < SCALE_MIN then return L.OPT_SCALE_AUTO end
      return format("%d%%", floor(v + 0.5))
   end
   SetTip(O.scale, "OPT_SCALE", "OPT_SCALE_TIP")
   y = y + 24

   Caption(f, y, "OPT_PREVIEW_SIZE")
   y = y + 18
   local gap = 4
   local bw = floor((INNER - gap * (#PREVIEW_SIZES - 1)) / #PREVIEW_SIZES)
   for i = 1, #PREVIEW_SIZES do
      local def = PREVIEW_SIZES[i]
      local b = Skin.Button(f, bw, ROW, "", function(self)
         DB.Set("previewSize", self.value)
      end)
      b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * (bw + gap), -y)
      b.value = def.value
      Reg(b, def.key, "SetLabel")
      SetTip(b, "OPT_PREVIEW_SIZE", "OPT_PREVIEW_TIP")
      O.sizeBtns[i] = b
   end
   y = y + ROW + 8

   O.resetBtn = Skin.Button(f, INNER, ROW, "", function()
      local W = T.UI.Window
      if type(W) == "table" and type(W.ResetLayout) == "function" then
         W.ResetLayout()
         Util.Print(L.OPT_RESET_DONE)
      end
   end)
   O.resetBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
   Reg(O.resetBtn, "OPT_RESET_WINDOW", "SetLabel")
   SetTip(O.resetBtn, "OPT_RESET_WINDOW", "OPT_RESET_WINDOW_TIP")
   y = y + ROW + 14

   -- Allgemein -----------------------------------------------------------
   y = Section(f, y, "OPT_SECTION_GENERAL")
   for i = 1, #CHECKS do
      local def = CHECKS[i]
      local c = Skin.Check(f, "", function(checked)
         DB.Set(def.key, checked and true or false)
      end)
      c:SetWidth(INNER)
      c:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
      Reg(c, def.label, "SetLabel")
      SetTip(c, def.label, def.tip)
      O.checks[def.key] = c
      y = y + ROW
   end
   y = y + 6

   local half = floor((INNER - 8) / 2)
   -- Anker und Probekarten erscheinen oben in der Mitte und liegen in derselben
   -- Strata wie dieses Fenster; auf kleinen Bildschirmen wuerde es sie
   -- ueberdecken: nach dem Aufruf unter die Karten legen (Open hebt es wieder).
   O.moveBtn = Skin.Button(f, half, ROW, "", function()
      local Tt = T.Toasts
      if type(Tt) == "table" and type(Tt.ShowAnchor) == "function" then
         Tt.ShowAnchor()
         f:Lower()
      end
   end)
   O.moveBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
   Reg(O.moveBtn, "OPT_MOVE_TOASTS", "SetLabel")
   SetTip(O.moveBtn, "OPT_MOVE_TOASTS", "OPT_MOVE_TOASTS_TIP")

   O.testBtn = Skin.Button(f, half, ROW, "", function()
      local Tt = T.Toasts
      if type(Tt) == "table" and type(Tt.Test) == "function" then
         Tt.Test()
         f:Lower()
      end
   end)
   O.testBtn:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + half + 8, -y)
   Reg(O.testBtn, "OPT_TEST_TOAST", "SetLabel")
   SetTip(O.testBtn, "OPT_TEST_TOAST", "OPT_TEST_TOAST_TIP")
   y = y + ROW + PAD

   f:SetHeight(y)

   -- Skripte
   f:SetScript("OnShow", function() Options.Refresh() end)
   f:SetScript("OnHide", function()
      if Skin.Menu.IsOpen() and Skin.Menu.Anchor() == O.langBtn then
         Skin.Menu.Close()
      end
   end)

   -- Zugriff fuer Tests und andere Module
   Options.frame = f
   Options.controls = {
      head = O.head, close = O.close, language = O.langBtn, note = O.note, scale = O.scale,
      sizes = O.sizeBtns, checks = O.checks, reset = O.resetBtn, moveToasts = O.moveBtn,
      testToast = O.testBtn,
   }

   Events.On("SETTINGS_CHANGED", function()
      if O.frame and O.frame:IsShown() then Options.Refresh() end
   end, Options)
   Events.On("LOCALE_CHANGED", function() Options.ApplyLocale() end, Options)

   return f
end

-- ---------------------------------------------------------------------------
-- Oeffentliche Funktionen
-- ---------------------------------------------------------------------------

-- Skalierung des Optionsfensters: wie das Hauptfenster (auch der berechnete Wert
-- bei "Auto"), sonst DB.global.scale; so bleibt es neben dem Fenster lesbar.
local function PanelScale()
   local s = nil
   local W = T.UI.Window
   if type(W) == "table" and type(W.ComputeScale) == "function" then
      local ok, v = pcall(W.ComputeScale)
      if ok then s = tonumber(v) end
   end
   if not s or s <= 0 then s = Skin.GetScale() end
   return Util.Clamp(s, 0.5, 1.5)
end

-- Options.Open() -- zeigt das Fenster (baut es beim ersten Mal, mittig)
function Options.Open()
   local f = Build()
   -- nicht bei geoeffnetem Fenster nachfuehren: der Regler darunter soll beim
   -- Ziehen nicht mit dem Fenster wandern
   if not f:IsShown() then f:SetScale(PanelScale()) end
   Options.Refresh()
   f:Show()
   f:Raise()
end

-- Options.Close() -- verbirgt das Fenster
function Options.Close()
   if O.frame then O.frame:Hide() end
end

-- Options.Toggle() -- Fenster umschalten
function Options.Toggle()
   if Options.IsShown() then
      Options.Close()
   else
      Options.Open()
   end
end

-- Options.IsShown() -> bool
function Options.IsShown()
   return O.frame ~= nil and O.frame:IsShown() and true or false
end
