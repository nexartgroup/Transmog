-- _skin_smoke.lua
-- ---------------------------------------------------------------------------
-- Wegwerf-Rauchtest fuer UI/Skin.lua mit einer kleinen, STRENGEN Attrappe der
-- WoW-3.3.5a-Widget-API: Methoden, die es dort nicht gibt (oder die hier nicht
-- aufgefuehrt sind), loesen einen Fehler aus. Start im Hauptverzeichnis:
--    luajit tests/_skin_smoke.lua
-- ---------------------------------------------------------------------------

local ROOT = arg and arg[0] and arg[0]:match("^(.*)/tests/[^/]+$") or "."

-- ---------------------------------------------------------------------------
-- Attrappe
-- ---------------------------------------------------------------------------

local MOCK = {
   userInputArg = "present",   -- "present" | "absent": liefert OnTextChanged das 2. Argument?
   engineSnaps = false,        -- rastet Slider:SetValue selbst ein?
   desatSupported = true,      -- Rueckgabe von Texture:SetDesaturated
   hasIsMouseOver = true,
}

local KNOWN_FONTS = {
   GameFontNormal = true, GameFontNormalSmall = true, GameFontNormalLarge = true,
   GameFontHighlight = true, GameFontHighlightSmall = true,
   GameFontDisable = true, GameFontDisableSmall = true, ChatFontNormal = true,
}
for name in pairs(KNOWN_FONTS) do _G[name] = { _isFont = true, name = name } end

local FOCUS = nil
local ALL = {}          -- alle erzeugten Objekte (zum Zaehlen)
local NAMED = {}

local function class(base)
   local c = {}
   c.__index = c
   if base then setmetatable(c, { __index = base }) end
   return c
end

local function fire(obj, script, ...)
   local fn = obj._scripts and obj._scripts[script]
   if fn then return fn(obj, ...) end
end

-- Region (Basis fuer Frame/Texture/FontString)
local Region = class()
function Region:SetWidth(w) assert(type(w) == "number", "SetWidth: Zahl erwartet"); local old = self._w; self._w = w
   if old ~= w and self._isFrame then fire(self, "OnSizeChanged", self._w, self._h or 0) end end
function Region:SetHeight(h) assert(type(h) == "number", "SetHeight: Zahl erwartet"); local old = self._h; self._h = h
   if old ~= h and self._isFrame then fire(self, "OnSizeChanged", self._w or 0, self._h) end end
function Region:GetWidth() return self._w or 0 end
function Region:GetHeight() return self._h or 0 end
function Region:SetPoint(point, rel, relPoint, x, y)
   if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
   self._points = self._points or {}
   tinsert(self._points, { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 })
end
function Region:ClearAllPoints() self._points = {} end
function Region:SetAllPoints(rel) self._allPoints = rel or true end
function Region:Show() self._shown = true end
function Region:Hide() self._shown = false end
function Region:IsShown() return self._shown and true or false end
function Region:IsVisible()
   if not self._shown then return false end
   local p = self._parent
   if p and p.IsVisible then return p:IsVisible() end
   return true
end
function Region:SetAlpha(a) self._alpha = a end
function Region:GetAlpha() return self._alpha or 1 end
function Region:GetParent() return self._parent end
function Region:GetLeft() return self._rect and self._rect[1] end
function Region:GetBottom() return self._rect and self._rect[2] end
function Region:GetRight() return self._rect and self._rect[3] end
function Region:GetTop() return self._rect and self._rect[4] end
function Region:GetName() return self._name end
if true then
   function Region:IsMouseOver() return self._mouseOver and true or false end
end

-- Texture
local Texture = class(Region)
function Texture:SetTexture(path) self._texture = path end
function Texture:GetTexture() return self._texture end
function Texture:SetTexCoord(a, b, c, d) self._texcoord = { a, b, c, d } end
function Texture:SetVertexColor(r, g, b, a) self._vertex = { r, g, b, a } end
function Texture:SetDrawLayer(l) self._layer = l end
function Texture:SetDesaturated(flag) self._desat = flag; return MOCK.desatSupported end

-- FontString
local FontString = class(Region)
function FontString:SetText(t) assert(self._font, "Font not set"); self._text = t end
function FontString:GetText() return self._text end
function FontString:SetFontObject(f) assert(type(f) == "table" or KNOWN_FONTS[f], "unbekannte Schrift"); self._font = f end
function FontString:SetTextColor(r, g, b, a) self._color = { r, g, b, a } end
function FontString:SetJustifyH(j) self._justifyH = j end
function FontString:SetJustifyV(j) self._justifyV = j end
function FontString:GetStringWidth() return #(self._text or "") * 6 end
function FontString:GetStringHeight()
   local w = #(self._text or "") * 6
   if self._w and self._w > 0 and w > self._w then
      return 12 * math.ceil(w / self._w)
   end
   return 12
end

-- Frame
local Frame = class(Region)
function Frame:SetScript(name, fn) self._scripts[name] = fn end
function Frame:GetScript(name) return self._scripts[name] end
function Frame:HookScript(name, fn)
   local old = self._scripts[name]
   self._scripts[name] = function(...) if old then old(...) end fn(...) end
end
function Frame:Show()
   if self._shown then return end
   self._shown = true
   fire(self, "OnShow")
end
function Frame:Hide()
   if not self._shown then return end
   self._shown = false
   if FOCUS == self then FOCUS = nil end
   fire(self, "OnHide")
   local function walk(f)
      for _, c in ipairs(f._children) do
         if c._shown then
            if FOCUS == c then FOCUS = nil end
            fire(c, "OnHide")
            walk(c)
         end
      end
   end
   walk(self)
end
function Frame:SetFrameStrata(s) self._strata = s end
function Frame:GetFrameStrata() return self._strata end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:GetFrameLevel() return self._level or 1 end
function Frame:Raise() self._raised = true end
function Frame:EnableMouse(b) self._mouse = b and true or false end
function Frame:IsMouseEnabled() return self._mouse end
function Frame:EnableMouseWheel(b) self._wheel = b and true or false end
function Frame:SetClampedToScreen(b) self._clamped = b end
function Frame:SetScale(s) self._scale = s end
function Frame:GetScale() return self._scale or 1 end
function Frame:GetEffectiveScale()
   local s = self._scale or 1
   local p = self._parent
   if p and p.GetEffectiveScale then s = s * p:GetEffectiveScale() end
   return s
end
function Frame:SetBackdrop(t) self._backdrop = t end
function Frame:SetBackdropColor(r, g, b, a) self._bd = { r, g, b, a } end
function Frame:SetBackdropBorderColor(r, g, b, a) self._bdBorder = { r, g, b, a } end
function Frame:CreateTexture(name, layer)
   local t = setmetatable({ _shown = true, _layer = layer, _parent = self }, Texture)
   tinsert(ALL, t)
   return t
end
function Frame:CreateFontString(name, layer, inherits)
   local fs = setmetatable({ _shown = true, _layer = layer, _parent = self }, FontString)
   if inherits ~= nil then
      assert(KNOWN_FONTS[inherits], "CreateFontString: unbekanntes Font-Objekt " .. tostring(inherits))
      fs._font = inherits
   end
   tinsert(ALL, fs)
   return fs
end
function Frame:RegisterForClicks(...) self._clicks = { ... } end

-- Button
local Button = class(Frame)
function Button:IsEnabled() return self._enabled ~= false and 1 or nil end
function Button:Enable() self._enabled = true end
function Button:Disable() self._enabled = false end
function Button:SetText(t) error("Button:SetText der Engine darf nicht erreicht werden") end

-- EditBox
local EditBox = class(Frame)
function EditBox:SetFontObject(f) assert(type(f) == "table" or KNOWN_FONTS[f], "unbekannte Schrift"); self._font = f end
function EditBox:SetAutoFocus(b) self._autoFocus = b end
function EditBox:SetTextInsets(l, r, t, b) self._insets = { l, r, t, b } end
function EditBox:SetTextColor(r, g, b) self._color = { r, g, b } end
function EditBox:SetMaxLetters(n) self._maxLetters = n end
function EditBox:SetText(t)
   assert(self._font, "Font not set")
   self._text = tostring(t)
   if MOCK.userInputArg == "present" then fire(self, "OnTextChanged", false) else fire(self, "OnTextChanged") end
end
function EditBox:GetText() return self._text or "" end
function EditBox:HighlightText() self._highlighted = true end
function EditBox:SetFocus()
   if not self:IsVisible() then return end
   if FOCUS and FOCUS ~= self then FOCUS:ClearFocus() end
   if FOCUS == self then return end
   FOCUS = self
   fire(self, "OnEditFocusGained")
end
function EditBox:ClearFocus()
   if FOCUS == self then
      FOCUS = nil
      self._highlighted = false
      fire(self, "OnEditFocusLost")
   end
end
function EditBox:HasFocus() return FOCUS == self end
-- Testhilfen
function EditBox:_typeText(text)
   assert(FOCUS == self or true)
   self._text = text
   if MOCK.userInputArg == "present" then fire(self, "OnTextChanged", true) else fire(self, "OnTextChanged") end
end

-- Slider
local Slider = class(Frame)
function Slider:SetOrientation(o) self._orient = o end
function Slider:SetMinMaxValues(lo, hi)
   self._min, self._max = lo, hi
   if self._value then
      local v = math.max(lo, math.min(hi, self._value))
      if v ~= self._value then self._value = v; fire(self, "OnValueChanged", v) end
   end
end
function Slider:GetMinMaxValues() return self._min, self._max end
function Slider:SetValueStep(s) self._step = s end
function Slider:GetValueStep() return self._step end
function Slider:SetValue(v)
   v = math.max(self._min or 0, math.min(self._max or 1, v))
   if MOCK.engineSnaps and self._step then
      v = self._min + math.floor((v - self._min) / self._step + 0.5) * self._step
   end
   if self._value ~= v then
      self._value = v
      fire(self, "OnValueChanged", v)
   end
end
function Slider:GetValue() return self._value or self._min or 0 end
function Slider:SetThumbTexture(path)
   local t = setmetatable({ _shown = true, _parent = self }, Texture)
   t._texture = path
   self._thumb = t
end
function Slider:GetThumbTexture() return self._thumb end

local CLASSES = { Frame = Frame, Button = Button, EditBox = EditBox, Slider = Slider }

function CreateFrame(kind, name, parent, template)
   assert(template == nil, "Skin darf keine Vorlage benutzen: " .. tostring(template))
   local cls = assert(CLASSES[kind], "unbekannter Frame-Typ " .. tostring(kind))
   local f = setmetatable({
      _isFrame = true, _type = kind, _name = name, _parent = parent, _shown = true,
      _scripts = {}, _children = {}, _points = {}, _level = (parent and parent._level or 0) + 1,
      _strata = parent and parent._strata or "MEDIUM", _scale = 1,
   }, cls)
   if parent then tinsert(parent._children, f) end
   if name then _G[name] = f; NAMED[name] = f end
   tinsert(ALL, f)
   return f
end

-- Globale Umgebung
UIParent = setmetatable({
   _isFrame = true, _type = "Frame", _name = "UIParent", _shown = true, _scripts = {},
   _children = {}, _points = {}, _w = 1600, _h = 900, _scale = 0.8, _level = 0, _strata = "MEDIUM",
}, Frame)
function UIParent:CreateFontString(name, layer, inherits)
   return Frame.CreateFontString(self, name, layer, inherits)
end

tinsert = table.insert
UISpecialFrames = {}
local sounds = {}
function PlaySound(name) tinsert(sounds, name) end
function GetCursorPosition() return 800 * 0.8, 450 * 0.8 end
function GetScreenWidth() return 1600 end
function GetScreenHeight() return 900 end
function GetTime() return 0 end
function MouseIsOver() return false end
function GetMouseFocus() return nil end

-- Tooltip
GameTooltip = { lines = {}, owner = nil, shown = false }
function GameTooltip:SetOwner(o, anchor) self.owner = o; self.anchor = anchor; self.lines = {}; self.shown = false end
function GameTooltip:AddLine(text, r, g, b, wrap) tinsert(self.lines, { text = text, r = r, g = g, b = b, wrap = wrap }) end
function GameTooltip:AddDoubleLine(l, r) tinsert(self.lines, { text = l, right = r }) end
function GameTooltip:NumLines() return #self.lines end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end
function GameTooltip:IsShown() return self.shown end
function GameTooltip:IsOwned(f) return self.owner == f end

-- Tastatur: ESC ohne Fokus schliesst alle sichtbaren UISpecialFrames (wie CloseSpecialWindows)
local function pressEscape()
   if FOCUS then
      fire(FOCUS, "OnEscapePressed")
      return "edit"
   end
   local found = false
   for _, name in ipairs(UISpecialFrames) do
      local fr = _G[name]
      if fr and fr:IsShown() then fr:Hide(); found = true end
   end
   return found and "special" or "none"
end

local function pressEnter()
   if FOCUS then fire(FOCUS, "OnEnterPressed"); return true end
   return false
end

-- ---------------------------------------------------------------------------
-- Testrahmen
-- ---------------------------------------------------------------------------

local failures, checks = 0, 0
local function ok(cond, msg)
   checks = checks + 1
   if not cond then
      failures = failures + 1
      print("FEHLER: " .. tostring(msg))
   end
end
local function eq(a, b, msg)
   checks = checks + 1
   if a ~= b then
      failures = failures + 1
      print(format and "" or "", "FEHLER: " .. tostring(msg) .. "  erwartet=" .. tostring(b) .. " war=" .. tostring(a))
   end
end
local function near(a, b, msg)
   checks = checks + 1
   if type(a) ~= "number" or math.abs(a - b) > 0.0001 then
      failures = failures + 1
      print("FEHLER: " .. tostring(msg) .. "  erwartet~=" .. tostring(b) .. " war=" .. tostring(a))
   end
end
local function section(name) print("-- " .. name) end

-- ---------------------------------------------------------------------------
-- Laden (ohne Init.lua/Util.lua: Fallbacks)
-- ---------------------------------------------------------------------------

section("Laden ohne Abhaengigkeiten")
dofile(ROOT .. "/UI/Skin.lua")
local T = Transmog
local Skin = T.UI.Skin
ok(type(Skin) == "table", "Transmog.UI.Skin vorhanden")
for _, name in ipairs({ "COL", "WHITE", "Backdrop", "Button", "Check", "EditBox", "Label", "Slider",
                        "Menu", "Prompt", "Confirm", "Tooltip", "Header", "Desaturate", "Icon", "TrimIcon" }) do
   ok(Skin[name] ~= nil, "Skin." .. name)
end
ok(Skin.Menu.Open and Skin.Menu.Close, "Skin.Menu.Open/Close")
eq(Skin.WHITE, "Interface\\Buttons\\WHITE8X8", "WHITE")

-- Farb-Aliase und Fallback
ok(Skin.COL.header == Skin.COL.head and Skin.COL.btnBorder == Skin.COL.buttonBorder, "Farb-Aliase")
local fallbackCol = Skin.COL.gibtEsNicht
ok(fallbackCol == Skin.COL.text, "unbekannte Farbe -> Textfarbe")
ok(Skin.missingColors.gibtEsNicht, "fehlende Farbe vermerkt")

-- Nach dem Laden mit "Init.lua": zweiter Ladevorgang uebernimmt T.COLORS
-- Echte Init.lua/Util.lua laden, falls sie in der Attrappe laufen; sonst Stuetzen.
local realInit = pcall(dofile, ROOT .. "/Core/Init.lua")
local realUtil = pcall(dofile, ROOT .. "/Core/Util.lua")
if not (realInit and T.COLORS) then
   T.COLORS = { accent = { 0.2, 0.62, 0.92 }, text = { 0.86, 0.88, 0.92 }, dim = { 0.5, 0.54, 0.6 },
                yellow = { 0.91, 0.77, 0.29 }, green = { 0.33, 0.82, 0.48 }, red = { 0.91, 0.40, 0.29 },
                blue = { 0.35, 0.71, 0.91 }, grey = { 0.35, 0.38, 0.44 }, pink = { 0.96, 0.44, 0.96 } }
end
if not (realUtil and T.Util and T.Util.G) then
   T.Util = { G = function(name, fb) local v = _G[name]; if type(v) == "string" then return v end return fb end }
end
print("   (echte Init.lua: " .. tostring(realInit) .. ", echte Util.lua: " .. tostring(realUtil) .. ")")
dofile(ROOT .. "/UI/Skin.lua")
Skin = T.UI.Skin
near(Skin.COL.accent[1], 0.2, "COL.accent aus T.COLORS")
OKAY, CANCEL = "OK-DE", "Abbrechen"

local parent = CreateFrame("Frame", nil, UIParent)
parent:SetWidth(400)
parent:SetHeight(300)

-- ---------------------------------------------------------------------------
section("Backdrop / Panel / Divider / Label")
do
   local f = CreateFrame("Frame", nil, parent)
   Skin.Backdrop(f)
   eq(f._backdrop.bgFile, Skin.WHITE, "Backdrop bgFile")
   eq(f._backdrop.edgeSize, 1, "Backdrop edgeSize")
   near(f._bd[1], 0.055, "Backdrop Standardfarbe")
   Skin.Backdrop(f, { 1, 0, 0, 0.5 }, { 0, 1, 0, 1 })
   near(f._bd[4], 0.5, "Backdrop bg alpha")
   near(f._bdBorder[2], 1, "Backdrop border")
   local p = Skin.Panel(parent)
   ok(p._backdrop ~= nil, "Panel hat Backdrop")
   local d = Skin.Divider(parent)
   eq(d._h, 1, "Divider Hoehe 1")
   local l = Skin.Label(parent, "Hallo")
   eq(l:GetText(), "Hallo", "Label Text")
   eq(l._font, "GameFontHighlightSmall", "Label Standardfont")
   local l2 = Skin.Label(parent, "x", "GameFontNormalLarge")
   eq(l2._font, "GameFontNormalLarge", "Label Font per Name")
   local l3 = Skin.Label(parent, "x", GameFontDisable)
   eq(l3._font, GameFontDisable, "Label Font per Objekt")
   local l4 = Skin.Label(parent, nil)
   eq(l4:GetText(), "", "Label ohne Text")
end

-- ---------------------------------------------------------------------------
section("Desaturate / Icon / TrimIcon")
do
   local t = parent:CreateTexture(nil, "ARTWORK")
   ok(Skin.Desaturate(t, true) == true, "Desaturate liefert true bei Unterstuetzung")
   eq(t._desat, 1, "SetDesaturated(1)")
   Skin.Desaturate(t, false)
   eq(t._desat, nil, "SetDesaturated(nil)")

   MOCK.desatSupported = false
   local calledGlobal
   function SetDesaturation(tex, flag) calledGlobal = { tex, flag } end
   local t2 = parent:CreateTexture(nil, "ARTWORK")
   local res = Skin.Desaturate(t2, true)
   ok(calledGlobal and calledGlobal[1] == t2, "Fallback ruft SetDesaturation")
   ok(res == true, "Fallback meldet Erfolg (pcall ok)")
   SetDesaturation = nil

   local t3 = parent:CreateTexture(nil, "ARTWORK")
   res = Skin.Desaturate(t3, true)
   ok(res == false, "ohne Unterstuetzung false")
   near(t3._vertex[1], 0.5, "ohne Unterstuetzung abgedunkelt")
   Skin.Desaturate(t3, false)
   near(t3._vertex[1], 1, "Abdunklung zurueckgesetzt")
   MOCK.desatSupported = true

   ok(Skin.Desaturate(nil, true) == false, "Desaturate(nil) sicher")

   Skin.Icon(t, "Interface\\Icons\\INV_Misc_QuestionMark")
   eq(t._texture, "Interface\\Icons\\INV_Misc_QuestionMark", "Icon Pfad")
   near(t._texcoord[1], 0.07, "Icon beschnitten")
   near(t._texcoord[2], 0.93, "Icon beschnitten 2")
   Skin.Icon(t, Skin.WHITE)
   near(t._texcoord[1], 0, "WHITE nicht beschnitten")
   Skin.Icon(t, nil)
   eq(t._texture, nil, "Icon(nil) leert")
   Skin.TrimIcon(t)
   near(t._texcoord[4], 0.93, "TrimIcon")
end

-- ---------------------------------------------------------------------------
section("Header")
do
   local f = CreateFrame("Frame", nil, parent)
   local h = Skin.Header(f, "Transmog")
   eq(h.title:GetText(), "Transmog", "Header Titel")
   ok(h.stripe ~= nil, "Header Streifen")
   eq(h._h, 30, "Header Standardhoehe 30")
   h:SetTitle("Neu")
   eq(h.title:GetText(), "Neu", "Header SetTitle")
   local h2 = Skin.Header(f, "x", 24)
   eq(h2._h, 24, "Header Hoehe")
end

-- ---------------------------------------------------------------------------
section("Button")
do
   local clicks, lastBtn = 0, nil
   local b = Skin.Button(parent, 100, 24, "Anwenden", function(self, button) clicks = clicks + 1; lastBtn = button end)
   eq(b:GetLabel(), "Anwenden", "Label")
   eq(b.label:GetText(), "Anwenden", ".label")
   ok(b.icon ~= nil, ".icon vorhanden")
   fire(b, "OnClick", "LeftButton")
   eq(clicks, 1, "Klick ruft onClick")
   eq(lastBtn, "LeftButton", "onClick bekommt Taste")

   -- SetLabel / SetText-Umleitung
   b:SetLabel("Los")
   eq(b.label:GetText(), "Los", "SetLabel")
   b:SetText("Weiter")
   eq(b.label:GetText(), "Weiter", "SetText leitet um (Engine-SetText nie gerufen)")

   -- Hover
   fire(b, "OnEnter")
   near(b._bdBorder[1], Skin.COL.accent[1], "Hover Akzentrand")
   near(b._bd[1], 0.19, "Hover Hintergrund")
   fire(b, "OnLeave")
   near(b._bdBorder[1], 0.26, "Ruhefarbe")

   -- Auswahl
   b:SetSelected(true)
   near(b._bd[2], 0.34, "ausgewaehlt bg")
   near(b._bdBorder[2], 0.71, "ausgewaehlt rand")
   fire(b, "OnEnter")
   fire(b, "OnLeave")
   near(b._bd[2], 0.34, "ausgewaehlt bleibt nach Hover")
   ok(b:IsSelected(), "IsSelected")
   b:SetSelected(false)
   near(b._bd[1], 0.13, "Auswahl zurueck")

   -- Sperren
   b:SetEnabledState(false, "Nichts zu tun")
   near(b._alpha, 0.45, "gesperrt: Alpha 0.45")
   fire(b, "OnClick", "LeftButton")
   eq(clicks, 1, "gesperrt: kein Klick")
   ok(b:IsEnabled() == nil, "IsEnabled() nil bei gesperrt")
   fire(b, "OnEnter")
   eq(GameTooltip.owner, b, "gesperrt: Tooltip")
   eq(GameTooltip.lines[#GameTooltip.lines].text, "Nichts zu tun", "gesperrt: Grund im Tooltip")
   ok(GameTooltip.shown, "Tooltip sichtbar")
   near(b._bdBorder[1], 0.26, "gesperrt: kein Akzentrand bei Hover")
   fire(b, "OnLeave")
   ok(not GameTooltip.shown, "Tooltip nach Leave verborgen")
   b:SetEnabledState(true)
   near(b._alpha, 1, "frei: Alpha 1")
   fire(b, "OnClick", "LeftButton")
   eq(clicks, 2, "frei: Klick")
   ok(b:IsEnabled() == 1, "IsEnabled() 1")

   -- Disable()/Enable() aus Gewohnheit gehen ueber unseren Merker
   b:Disable()
   ok(b.uiOff == true, "Disable() -> uiOff")
   eq(b._enabled, nil, "Engine-Disable nie gerufen")
   b:Enable()
   ok(b.uiOff == false, "Enable() -> frei")

   -- Maus lag schon drauf (OnEnter lief im gesperrten Zustand), dann freigegeben
   b:SetEnabledState(false, "Grund A")
   fire(b, "OnEnter")
   near(b._bdBorder[1], 0.26, "gesperrt unter der Maus: kein Akzentrand")
   eq(GameTooltip.lines[#GameTooltip.lines].text, "Grund A", "Grund A im Tooltip")
   b:SetEnabledState(false, "Grund B")
   eq(GameTooltip.lines[#GameTooltip.lines].text, "Grund B", "Tooltip folgt dem geaenderten Grund")
   b.tip = "Normaler Text"
   b:SetEnabledState(true)
   near(b._bdBorder[1], Skin.COL.accent[1], "Freigabe unter der Maus -> Hover")
   eq(GameTooltip.lines[1].text, "Normaler Text", "Tooltip wird bei Freigabe umgebaut")
   ok(GameTooltip.shown, "Tooltip bleibt sichtbar")
   fire(b, "OnLeave")
   b.tip = nil
   -- Ohne OnEnter (Maus nur geometrisch darueber, z. B. hinter dem Dialog): kein klebender Hover
   b:SetEnabledState(false)
   b._mouseOver = true
   b:SetEnabledState(true)
   near(b._bdBorder[1], 0.26, "kein Hover ohne OnEnter")
   b._mouseOver = false

   -- Tooltip-Callback bekommt den Tooltip
   local gotTip
   b.tip = function(tt) gotTip = tt; tt:AddLine("Titel") end
   fire(b, "OnEnter")
   eq(gotTip, GameTooltip, ".tip(tooltip)")
   ok(GameTooltip.shown, ".tip zeigt Tooltip")
   fire(b, "OnLeave")
   b.tip = "Text-Tooltip"
   fire(b, "OnEnter")
   eq(GameTooltip.lines[1].text, "Text-Tooltip", ".tip als String")
   fire(b, "OnLeave")
   b.tip = function() end
   fire(b, "OnEnter")
   ok(not GameTooltip.shown, "leerer Tooltip wird nicht gezeigt")
   fire(b, "OnLeave")
   b.tip = nil

   -- Verbergen setzt Hover zurueck
   fire(b, "OnEnter")
   b:Hide()
   ok(b.hover == false, "Hide setzt Hover zurueck")

   -- Theme / Icon / Akzent / Rechtsklick
   local d = Skin.Button(parent, 100, 24, "Loeschen")
   d:SetTheme("danger")
   near(d._bd[1], 0.34, "Danger-Hintergrund")
   d:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark", 16)
   eq(d.icon._texture, "Interface\\Icons\\INV_Misc_QuestionMark", "SetIcon")
   eq(d.icon._w, 16, "Icon-Groesse")
   d:SetIcon(nil)
   eq(d.icon._texture, nil, "Icon entfernt")
   d:SetAccent(1, 0, 0)
   ok(d.accentTex:IsShown(), "Akzent sichtbar")
   d:SetAccent(nil)
   ok(not d.accentTex:IsShown(), "Akzent aus")
   d:EnableRightClick(true)
   eq(#d._clicks, 2, "Rechtsklick registriert")
   local icBtn = Skin.Button(parent, 22, 22, "")
   icBtn:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark")
   eq(icBtn.icon._points[#icBtn.icon._points].point, "CENTER", "Icon-only zentriert")
   local lBtn = Skin.Button(parent, 120, 24, "Mit Symbol")
   lBtn:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark")
   eq(lBtn.icon._points[#lBtn.icon._points].point, "LEFT", "Icon + Text links")
   -- Direkter Zugriff auf .icon (SPEC: .icon = Texture): Anordnung folgt
   local direct = Skin.Button(parent, 120, 24, "Direkt")
   direct.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
   eq(direct.icon._points[#direct.icon._points].point, "LEFT", "direktes icon:SetTexture ordnet an")
   -- Breite wird nach SetWidth neu gerechnet
   lBtn:SetWidth(200)
   ok(lBtn.icon._points[#lBtn.icon._points].x > 4, "Icon + Text wird zentriert")
end

-- ---------------------------------------------------------------------------
section("Check")
do
   local last, count = nil, 0
   local c = Skin.Check(parent, "Doppelte ausblenden", function(v, self) last = v; count = count + 1 end)
   eq(c:GetChecked(), false, "Start ungehakt")
   ok(c.label ~= nil and c.label:GetText() == "Doppelte ausblenden", ".label")
   ok(c:GetWidth() > 22, "Breite folgt dem Text")
   c:SetChecked(true)
   eq(c:GetChecked(), true, "SetChecked")
   eq(count, 0, "SetChecked feuert nicht")
   ok(c.mark:IsShown(), "Haken sichtbar")
   fire(c, "OnClick", "LeftButton")
   eq(c:GetChecked(), false, "Klick schaltet um")
   eq(last, false, "onChange(false)")
   fire(c, "OnClick", "LeftButton")
   eq(last, true, "onChange(true)")
   eq(count, 2, "onChange 2x")
   ok(sounds[#sounds] == "igMainMenuOptionCheckBoxOn", "Klick-Ton")
   c:SetEnabledState(false, "Gesperrt")
   fire(c, "OnClick", "LeftButton")
   eq(count, 2, "gesperrt: kein onChange")
   eq(c:GetChecked(), true, "gesperrt: Zustand bleibt")
   near(c._alpha, 0.45, "gesperrt: Alpha")
   fire(c, "OnEnter")
   eq(GameTooltip.lines[#GameTooltip.lines].text, "Gesperrt", "Grund im Tooltip")
   fire(c, "OnLeave")
   c:SetEnabledState(true)
   -- SetLabel aendert Breite; explizite Breite bleibt
   c:SetLabel("Kurz")
   local wShort = c:GetWidth()
   ok(wShort < 80, "Breite schrumpft")
   c:SetWidth(240)
   c:SetLabel("Ein sehr langer Text ueber mehrere Zeilen")
   eq(c:GetWidth(), 240, "explizite Breite bleibt")
   eq(c.label._w, 240 - 16 - 6, "Label-Breite folgt der Checkbox")
end

-- ---------------------------------------------------------------------------
local function editTests(mode)
   MOCK.userInputArg = mode
   section("EditBox (userInput-Argument: " .. mode .. ")")
   local got = {}
   local e = Skin.EditBox(parent, 180, 22, "Suche...", function(text, userInput)
      tinsert(got, { text, userInput })
   end)
   ok(e.placeholderText:IsShown(), "Platzhalter sichtbar (leer, ohne Fokus)")
   eq(e.placeholderText:GetText(), "Suche...", "Platzhaltertext")
   e:SetFocus()
   ok(e:HasFocus(), "Fokus")
   ok(not e.placeholderText:IsShown(), "Platzhalter weg bei Fokus")
   near(e._bdBorder[1], Skin.COL.accent[1], "Fokus: Akzentrand")
   e:ClearFocus()
   ok(e.placeholderText:IsShown(), "Platzhalter wieder da")

   -- Programmatisches SetText: userInput = false
   got = {}
   e:SetText("Schwert")
   eq(#got, 1, "SetText feuert onChange einmal")
   eq(got[1][1], "Schwert", "SetText Text")
   eq(got[1][2], false, "SetText: userInput=false")
   ok(not e.placeholderText:IsShown(), "Platzhalter weg bei Text")

   -- Eingabe: userInput = true
   got = {}
   e:SetFocus()
   e:_typeText("Schwerter")
   eq(#got, 1, "Eingabe feuert onChange")
   eq(got[1][2], true, "Eingabe: userInput=true")
   eq(got[1][1], "Schwerter", "Eingabe Text")

   -- Escape/Enter geben den Fokus ab
   fire(e, "OnEscapePressed")
   ok(not e:HasFocus(), "ESC gibt Fokus ab")
   eq(e:GetText(), "Schwerter", "ESC behaelt Text")
   e:SetFocus()
   local entered
   e.onEnter = function(text) entered = text end
   fire(e, "OnEnterPressed")
   ok(not e:HasFocus(), "Enter gibt Fokus ab")
   eq(entered, "Schwerter", "onEnter(text)")

   e:SetText("")
   ok(e.placeholderText:IsShown(), "leer -> Platzhalter")
   e:SetPlaceholder("Neu")
   eq(e.placeholderText:GetText(), "Neu", "SetPlaceholder")
   eq(e._font, GameFontHighlight, "EditBox hat Schrift")
   e:SetEnabledState(false)
   near(e._alpha, 0.45, "EditBox gesperrt")
   e:SetEnabledState(true)
end
editTests("present")
editTests("absent")
MOCK.userInputArg = "present"

-- ---------------------------------------------------------------------------
local function sliderTests(snaps)
   MOCK.engineSnaps = snaps
   section("Slider (Engine rastet selbst ein: " .. tostring(snaps) .. ")")
   local calls = {}
   local s = Skin.Slider(parent, 200, 60, 150, 5, function(v, self) tinsert(calls, v) end)
   ok(s.valueText ~= nil, ".valueText")
   eq(s._orient, "HORIZONTAL", "Orientierung")
   eq(s:GetValue(), 60, "Startwert = min")
   eq(s.valueText:GetText(), "60", "Wertetext")
   eq(#calls, 0, "Aufbau ruft onChange nicht")

   -- Engine liefert zwischenwerte (wie beim Ziehen)
   s:SetValue(83)
   eq(s:GetValue(), 85, "rastet auf 85 ein")
   eq(calls[#calls], 85, "onChange(85)")
   eq(s.valueText:GetText(), "85", "Wertetext 85")
   eq(#calls, 1, "genau ein onChange")

   -- Quiet
   s:SetValueQuiet(100)
   eq(s:GetValue(), 100, "SetValueQuiet setzt")
   eq(#calls, 1, "SetValueQuiet ruft onChange nicht")
   eq(s.valueText:GetText(), "100", "Wertetext nach Quiet")
   s:SetValueQuiet(103)
   eq(s:GetValue(), 105, "SetValueQuiet rastet ein")
   s:SetValueQuiet(500)
   eq(s:GetValue(), 150, "SetValueQuiet klemmt")
   s:SetValueQuiet(-5)
   eq(s:GetValue(), 60, "SetValueQuiet klemmt unten")

   -- Mausrad
   fire(s, "OnMouseWheel", 1)
   eq(s:GetValue(), 65, "Rad hoch +step")
   eq(calls[#calls], 65, "Rad meldet")
   fire(s, "OnMouseWheel", -1)
   eq(s:GetValue(), 60, "Rad runter -step")
   fire(s, "OnMouseWheel", -1)
   eq(s:GetValue(), 60, "am Anschlag bleibt")

   -- Fuellbalken
   s:SetValueQuiet(150)
   ok(s.fill._w >= 190, "Fuellung bei max voll")
   s:SetValueQuiet(60)
   ok(s.fill._w <= 8, "Fuellung bei min klein")

   -- Gesperrt
   s:SetValueQuiet(100)
   s:SetEnabledState(false, "Nur im Automatikmodus")
   local before = #calls
   s:SetValue(120)
   eq(s:GetValue(), 100, "gesperrt: Wert springt zurueck")
   eq(#calls, before, "gesperrt: kein onChange")
   fire(s, "OnMouseWheel", 1)
   eq(s:GetValue(), 100, "gesperrt: Rad wirkungslos")
   fire(s, "OnEnter")
   eq(GameTooltip.lines[#GameTooltip.lines].text, "Nur im Automatikmodus", "gesperrt: Grund")
   fire(s, "OnLeave")
   s:SetEnabledState(true)

   -- Formatter
   s.formatter = function(v) return format and "" or "" end
   s.formatter = function(v) return string.format("%d%%", v) end
   s:SetValueQuiet(110)
   eq(s.valueText:GetText(), "110%", "formatter")

   -- Dezimalschritte
   local d = Skin.Slider(parent, 100, 0.5, 2, 0.25, function() end)
   d:SetValueQuiet(1.1)
   near(d:GetValue(), 1.0, "Dezimalschritt rastet")
   d:SetValueQuiet(1.2)
   near(d:GetValue(), 1.25, "Dezimalschritt rastet 1.25")
   eq(d.valueText:GetText(), "1.25", "Dezimaltext")
end
sliderTests(false)
sliderTests(true)
MOCK.engineSnaps = false

-- ---------------------------------------------------------------------------
section("Menu")
do
   local anchor = CreateFrame("Button", nil, parent)
   anchor:SetWidth(120)
   anchor:SetHeight(22)
   anchor._rect = { 100 / 0.8 * 0.8, 600, 220, 622 }   -- in UIParent-Einheiten (Effektivscale: 0.8 * 1)
   -- anchor hat Effektivscale 0.8 (UIParent) -> Rechteck-Werte sind in "Anker-Einheiten"
   anchor._rect = { 100, 600, 220, 622 }

   local clicked = {}
   local closed = 0
   local items = {
      { text = "Titel", isTitle = true },
      { text = "Qualitaet", checked = true, onClick = function() tinsert(clicked, "q") end },
      { text = "Name", radio = true, checked = true, onClick = function() tinsert(clicked, "n") end },
      { text = "Itemlevel", radio = true, checked = false, onClick = function() tinsert(clicked, "i") end },
      { text = "Gesperrt", disabled = true, onClick = function() tinsert(clicked, "x") end },
      { text = "Bleibt", keepOpen = true, checked = false, onClick = function(it) it.checked = not it.checked; tinsert(clicked, "k") end },
      { text = "Rot", color = { 1, 0, 0 }, onClick = function() tinsert(clicked, "r") end },
   }
   Skin.Menu.Open(anchor, items, { onClose = function() closed = closed + 1 end })
   local mf = TransmogMenuFrame
   ok(mf ~= nil and mf:IsShown(), "TransmogMenuFrame sichtbar")
   eq(mf._strata, "FULLSCREEN_DIALOG", "Menue-Strata")
   local found = false
   for _, n in ipairs(UISpecialFrames) do if n == "TransmogMenuFrame" then found = true end end
   ok(found, "TransmogMenuFrame in UISpecialFrames")
   ok(Skin.Menu.IsOpen(), "IsOpen")
   local rows = mf._children
   -- erste Kindframes: Fanger, Zeilen
   local rowFrames = {}
   for _, c in ipairs(mf._children) do if c._type == "Button" then tinsert(rowFrames, c) end end
   eq(#rowFrames, 7, "7 Zeilen")
   eq(rowFrames[1].text:GetText(), "Titel", "Zeile 1 Text")
   near(rowFrames[1].text._color[1], Skin.COL.yellow[1], "Titelfarbe gelb")
   ok(rowFrames[2].check:IsShown(), "Haken sichtbar")
   ok(not rowFrames[2].dot:IsShown(), "kein Punkt")
   ok(rowFrames[3].dot:IsShown(), "Radiopunkt sichtbar")
   ok(not rowFrames[3].check:IsShown(), "Radio ohne Haken")
   ok(not rowFrames[4].dot:IsShown() and not rowFrames[4].check:IsShown(), "unchecked ohne Marke")
   near(rowFrames[5].text._color[1], Skin.COL.grey[1], "gesperrt grau")
   near(rowFrames[7].text._color[2], 0, "Eintragsfarbe rot")

   -- Position: unter dem Anker, links ausgerichtet
   local pt = mf._points[#mf._points]
   eq(pt.point, "TOPLEFT", "Menue TOPLEFT")
   ok(pt.rel == UIParent, "Menue relativ zu UIParent")
   -- Anker-Rechteck ist in Anker-Einheiten: Effektivscale 0.8 -> UI-Einheiten = Wert (0.8/0.8=1)
   near(pt.x, 100, "Menue x = Ankerlinks")
   near(pt.y, 600 - 2, "Menue y = Ankerunten - 2")
   ok(mf._w >= 120, "Menue Breite >= 120")
   eq(mf._h, 7 * 20 + 8, "Menue Hoehe")

   -- Klick auf Eintrag: schliesst, ruft onClick
   fire(rowFrames[2], "OnClick", "LeftButton")
   eq(clicked[#clicked], "q", "onClick gerufen")
   ok(not mf:IsShown(), "schliesst nach Klick")
   ok(not TransmogMenuFrame:IsShown(), "Frame zu")
   eq(closed, 1, "onClose einmal")
   ok(not Skin.Menu.IsOpen(), "IsOpen false")

   -- Titel / gesperrt: keine Reaktion
   Skin.Menu.Open(anchor, items, { onClose = function() closed = closed + 1 end })
   local n = #clicked
   fire(rowFrames[1], "OnClick", "LeftButton")
   fire(rowFrames[5], "OnClick", "LeftButton")
   eq(#clicked, n, "Titel/gesperrt reagieren nicht")
   ok(mf:IsShown(), "bleibt offen")

   -- keepOpen
   fire(rowFrames[6], "OnClick", "LeftButton")
   eq(clicked[#clicked], "k", "keepOpen-onClick")
   ok(mf:IsShown(), "keepOpen bleibt offen")
   ok(rowFrames[6].check:IsShown(), "keepOpen: Haken aktualisiert")

   -- Klick ausserhalb (Fangflaeche)
   local catcher = M_catcher
   local cf
   for _, c in ipairs(UIParent._children) do
      if c._mouse and c._allPoints == UIParent and c._level == 60 then cf = c end
   end
   ok(cf ~= nil, "Fangflaeche gefunden")
   ok(cf:IsShown(), "Fangflaeche sichtbar")
   eq(cf._strata, "FULLSCREEN_DIALOG", "Fangflaeche Strata")
   fire(cf, "OnMouseDown", "LeftButton")
   ok(not mf:IsShown(), "Klick ausserhalb schliesst")
   ok(not cf:IsShown(), "Fangflaeche weg")
   eq(closed, 2, "onClose beim Klick ausserhalb")

   -- ESC
   Skin.Menu.Open(anchor, items, { onClose = function() closed = closed + 1 end })
   local fr = TransmogMenuFrame
   ok(FOCUS ~= nil, "Tastaturfaenger hat Fokus")
   -- Hauptfenster-Attrappe in UISpecialFrames: darf von ESC im Menue NICHT geschlossen werden
   local win = CreateFrame("Frame", "TransmogWindow", UIParent)
   tinsert(UISpecialFrames, "TransmogWindow")
   local what = pressEscape()
   eq(what, "edit", "ESC geht an den Tastaturfaenger")
   ok(not fr:IsShown(), "ESC schliesst das Menue")
   ok(win:IsShown(), "ESC schliesst das Hauptfenster NICHT")
   eq(closed, 3, "onClose bei ESC")

   -- ESC ueber UISpecialFrames (Fokus verloren): Menue raeumt auf
   Skin.Menu.Open(anchor, items, { onClose = function() closed = closed + 1 end })
   FOCUS = nil
   pressEscape()
   ok(not TransmogMenuFrame:IsShown(), "UISpecialFrames-ESC schliesst Menue")
   ok(not cf:IsShown(), "Fangflaeche zu")
   eq(closed, 4, "onClose bei UISpecialFrames-ESC")
   win:Show()

   -- Erneutes Open ersetzt (onClose des alten)
   Skin.Menu.Open(anchor, items, { onClose = function() closed = closed + 1 end })
   Skin.Menu.Open(anchor, items, { onClose = function() closed = closed + 100 end })
   eq(closed, 5, "Ersetzen ruft altes onClose")
   Skin.Menu.Close()
   eq(closed, 105, "Close ruft neues onClose")
   Skin.Menu.Close()
   eq(closed, 105, "doppeltes Close ohne Wirkung")

   -- Leere Liste
   Skin.Menu.Open(anchor, {})
   ok(not Skin.Menu.IsOpen(), "leere Liste oeffnet nichts")

   -- Viele Eintraege: Scrollen
   local many = {}
   local sel = {}
   for i = 1, 40 do
      many[i] = { text = "Eintrag " .. i, onClick = function() tinsert(sel, i) end }
   end
   Skin.Menu.Open(anchor, many)
   local rf = {}
   for _, c in ipairs(TransmogMenuFrame._children) do if c._type == "Button" then tinsert(rf, c) end end
   local shownRows = 0
   for _, r in ipairs(rf) do if r:IsShown() then shownRows = shownRows + 1 end end
   eq(shownRows, 18, "18 Zeilen sichtbar")
   eq(rf[1].text:GetText(), "Eintrag 1", "erste Zeile")
   eq(TransmogMenuFrame._h, 18 * 20 + 8, "Hoehe 18 Zeilen")
   ok(Skin.Menu and TransmogMenuFrame._children, "ok")
   fire(rf[1], "OnMouseWheel", -1)
   eq(rf[1].text:GetText(), "Eintrag 4", "Rad scrollt 3 Zeilen")
   for i = 1, 20 do fire(rf[1], "OnMouseWheel", -1) end
   eq(rf[1].text:GetText(), "Eintrag 23", "Scrollen klemmt (40-18+1)")
   eq(rf[18].text:GetText(), "Eintrag 40", "letzte Zeile")
   fire(TransmogMenuFrame, "OnMouseWheel", 1)
   eq(rf[1].text:GetText(), "Eintrag 20", "Rad am Rahmen")
   fire(rf[3], "OnClick", "LeftButton")
   eq(sel[#sel], 22, "Klick waehlt den richtigen Eintrag (3. sichtbare = 22)")
   ok(not Skin.Menu.IsOpen(), "geschlossen")

   -- Bildschirmgrenzen: unten -> nach oben klappen
   local low = CreateFrame("Button", nil, parent)
   low:SetWidth(100)
   low:SetHeight(20)
   low._rect = { 300, 30, 400, 50 }
   Skin.Menu.Open(low, items)
   local p2 = TransmogMenuFrame._points[#TransmogMenuFrame._points]
   -- Hoehe 148 * scale 1: darunter ist nicht genug Platz -> oberhalb (Ankeroberkante + 2 + Hoehe)
   near(p2.y, 50 + 2 + 148, "klappt nach oben")
   Skin.Menu.Close()

   -- rechter Rand: nach links verschieben
   local right = CreateFrame("Button", nil, parent)
   right:SetWidth(100)
   right:SetHeight(20)
   right._rect = { 1580, 500, 1680, 520 }
   Skin.Menu.Open(right, items)
   local p3 = TransmogMenuFrame._points[#TransmogMenuFrame._points]
   ok(p3.x + TransmogMenuFrame._w <= 1600 + 0.001, "am rechten Rand begrenzt")
   Skin.Menu.Close()

   -- align RIGHT
   Skin.Menu.Open(anchor, items, { align = "RIGHT" })
   local p4 = TransmogMenuFrame._points[#TransmogMenuFrame._points]
   near(p4.x + TransmogMenuFrame._w, 220, "align RIGHT: rechtsbuendig")
   Skin.Menu.Close()

   -- Skalierung folgt dem Anker (Fenster skaliert)
   local scaled = CreateFrame("Frame", nil, UIParent)
   scaled:SetScale(1.5)
   local sbtn = CreateFrame("Button", nil, scaled)
   sbtn:SetWidth(80)
   sbtn:SetHeight(20)
   sbtn._rect = { 100, 600, 180, 620 }
   Skin.Menu.Open(sbtn, items)
   near(TransmogMenuFrame._scale, 1.5, "Menue skaliert wie das Fenster")
   -- Position in Menue-Einheiten: Ankerlinks in UI-Einheiten = 100 * (0.8*1.5/0.8) = 150 -> /1.5 = 100
   local p5 = TransmogMenuFrame._points[#TransmogMenuFrame._points]
   near(p5.x, 100, "Offset in Menue-Einheiten")
   Skin.Menu.Close()

   -- Anker verschwindet -> Menue schliesst (OnUpdate)
   local hid = CreateFrame("Button", nil, parent)
   hid:SetWidth(50)
   hid:SetHeight(20)
   hid._rect = { 10, 10, 60, 30 }
   Skin.Menu.Open(hid, items)
   hid:Hide()
   fire(TransmogMenuFrame, "OnUpdate", 0.5)
   ok(not Skin.Menu.IsOpen(), "Anker verborgen -> Menue zu")

   -- Ohne Anker: am Mauszeiger
   Skin.Menu.Open(nil, items)
   local p6 = TransmogMenuFrame._points[#TransmogMenuFrame._points]
   near(p6.x, 800, "Cursor-x")
   Skin.Menu.Close()
end

-- ---------------------------------------------------------------------------
section("Prompt")
do
   -- TransmogWindow existiert aus dem Menuetest (Skalierung 1.0)
   local accepted, cancelled = {}, 0
   Skin.Prompt({
      title = "Outfit speichern", text = "Name des Outfits:", default = "Outfit 1", accept = "Speichern",
      onAccept = function(text) tinsert(accepted, text) end,
      onCancel = function() cancelled = cancelled + 1 end,
   })
   local pf = TransmogPromptFrame
   ok(pf ~= nil and pf:IsShown(), "TransmogPromptFrame sichtbar")
   eq(pf._strata, "FULLSCREEN_DIALOG", "Prompt-Strata")
   local found = false
   for _, n in ipairs(UISpecialFrames) do if n == "TransmogPromptFrame" then found = true end end
   ok(found, "Prompt in UISpecialFrames")
   ok(Skin.DialogOpen(), "DialogOpen")

   -- Elemente finden
   local edit, acceptBtn, cancelBtn
   for _, c in ipairs(pf._children) do
      if c._type == "EditBox" and c._w and c._w > 10 then edit = c end
   end
   ok(edit ~= nil and edit:IsShown(), "Eingabefeld sichtbar")
   eq(edit:GetText(), "Outfit 1", "Vorgabetext")
   ok(edit:HasFocus(), "Eingabefeld hat Fokus")
   ok(edit._highlighted, "Text markiert")
   for _, c in ipairs(pf._children) do
      if c._type == "Button" then
         if c.label:GetText() == "Speichern" then acceptBtn = c end
         if c.label:GetText() == "Abbrechen" then cancelBtn = c end
      end
   end
   ok(acceptBtn ~= nil, "Annehmen-Knopf mit Beschriftung")
   ok(cancelBtn ~= nil, "Abbrechen-Knopf mit Blizzard-Text (CANCEL)")
   ok(acceptBtn:IsEnabledState(), "Annehmen frei bei Text")
   -- Abdunklung
   local dim
   for _, c in ipairs(UIParent._children) do
      if c._level == 20 and c._allPoints == UIParent then dim = c end
   end
   ok(dim and dim:IsShown(), "Abdunklung sichtbar")
   ok(dim._mouse, "Abdunklung faengt Maus")

   -- Leeren: Knopf gesperrt
   edit:_typeText("")
   ok(not acceptBtn:IsEnabledState(), "Annehmen gesperrt bei leerem Feld")
   edit:_typeText("   ")
   ok(not acceptBtn:IsEnabledState(), "Annehmen gesperrt bei Leerzeichen")
   -- Enter bei gesperrt: nichts
   pressEnter()
   eq(#accepted, 0, "Enter bei leerem Feld nimmt nicht an")
   ok(pf:IsShown(), "Dialog bleibt offen")
   edit:_typeText("  Mein Look  ")
   ok(acceptBtn:IsEnabledState(), "Annehmen frei nach Eingabe")
   pressEnter()
   eq(accepted[1], "Mein Look", "Enter -> onAccept(getrimmter Text)")
   ok(not pf:IsShown(), "Dialog zu")
   ok(not dim:IsShown(), "Abdunklung zu")
   eq(cancelled, 0, "nicht abgebrochen")
   ok(not Skin.DialogOpen(), "DialogOpen false")

   -- ESC im Eingabefeld: onCancel, Hauptfenster bleibt
   Skin.Prompt({ title = "x", text = "y", default = "abc",
      onAccept = function(t) tinsert(accepted, t) end, onCancel = function() cancelled = cancelled + 1 end })
   ok(TransmogWindow:IsShown(), "Fenster offen")
   local what = pressEscape()
   eq(what, "edit", "ESC geht an das Eingabefeld")
   eq(cancelled, 1, "ESC -> onCancel")
   ok(not TransmogPromptFrame:IsShown(), "Dialog zu nach ESC")
   ok(TransmogWindow:IsShown(), "ESC im Dialog schliesst das Hauptfenster nicht")

   -- Annehmen-Knopf
   Skin.Prompt({ title = "x", text = "y", default = "klick", onAccept = function(t) tinsert(accepted, t) end })
   acceptBtn = nil
   for _, c in ipairs(TransmogPromptFrame._children) do
      if c._type == "Button" and c.label:GetText() == "OK-DE" then acceptBtn = c end
   end
   ok(acceptBtn ~= nil, "Standardbeschriftung OKAY")
   fire(acceptBtn, "OnClick", "LeftButton")
   eq(accepted[2], "klick", "Knopf -> onAccept")

   -- Validate
   Skin.Prompt({ title = "x", text = "y", default = "",
      validate = function(t) if t == "vergeben" then return false, "Name existiert bereits" end return true end,
      onAccept = function(t) tinsert(accepted, t) end })
   local e2
   for _, c in ipairs(TransmogPromptFrame._children) do
      if c._type == "EditBox" and c._w and c._w > 10 then e2 = c end
   end
   e2:_typeText("vergeben")
   local ab
   for _, c in ipairs(TransmogPromptFrame._children) do
      if c._type == "Button" and c.label:GetText() == "OK-DE" then ab = c end
   end
   ok(not ab:IsEnabledState(), "validate=false sperrt Annehmen")
   eq(ab.disabledTip, "Name existiert bereits", "Grund als Tooltip")
   e2:_typeText("frei")
   ok(ab:IsEnabledState(), "validate=true gibt frei")
   Skin.CloseDialog()
   ok(not TransmogPromptFrame:IsShown(), "CloseDialog")

   -- Prompt ohne Eingabe
   local acc = 0
   Skin.Prompt({ title = "Info", text = "Nur Text", input = false, onAccept = function() acc = acc + 1 end })
   ok(FOCUS ~= nil and FOCUS ~= nil, "Tastaturfaenger fokussiert")
   pressEnter()
   eq(acc, 1, "Enter ohne Eingabefeld akzeptiert")
end

-- ---------------------------------------------------------------------------
section("Confirm")
do
   local acc, canc = 0, 0
   Skin.Confirm({
      title = "Loeschen", text = "Outfit wirklich loeschen?", accept = "Loeschen", cancel = "Behalten",
      danger = true, onAccept = function() acc = acc + 1 end, onCancel = function() canc = canc + 1 end,
   })
   local cf = TransmogConfirmFrame
   ok(cf ~= nil and cf:IsShown(), "TransmogConfirmFrame sichtbar")
   eq(cf._strata, "FULLSCREEN_DIALOG", "Confirm-Strata")
   local found = false
   for _, n in ipairs(UISpecialFrames) do if n == "TransmogConfirmFrame" then found = true end end
   ok(found, "Confirm in UISpecialFrames")
   local acceptBtn, cancelBtn
   for _, c in ipairs(cf._children) do
      if c._type == "Button" then
         if c.label:GetText() == "Loeschen" then acceptBtn = c end
         if c.label:GetText() == "Behalten" then cancelBtn = c end
      end
   end
   ok(acceptBtn and cancelBtn, "Knoepfe beschriftet")
   near(acceptBtn._bd[1], 0.34, "danger: roter Hintergrund")
   ok(FOCUS ~= nil, "Fokus (Tastaturfaenger)")
   -- Enter akzeptiert
   pressEnter()
   eq(acc, 1, "Enter akzeptiert")
   ok(not cf:IsShown(), "Dialog zu")

   -- ESC bricht ab
   Skin.Confirm({ title = "a", text = "b", onAccept = function() acc = acc + 1 end, onCancel = function() canc = canc + 1 end })
   pressEscape()
   eq(canc, 1, "ESC -> onCancel")
   eq(acc, 1, "ESC akzeptiert nicht")
   ok(TransmogWindow:IsShown(), "ESC laesst das Hauptfenster offen")

   -- Nur ein Dialog zugleich
   local pcancel = 0
   Skin.Prompt({ title = "p", text = "q", default = "x", onCancel = function() pcancel = pcancel + 1 end })
   Skin.Confirm({ title = "c", text = "d", onAccept = function() end })
   ok(TransmogConfirmFrame:IsShown(), "Confirm sichtbar")
   ok(not TransmogPromptFrame:IsShown(), "Prompt wurde verdraengt")
   eq(pcancel, 1, "verdraengter Dialog bekommt onCancel")
   Skin.CloseDialog()

   -- Ein offenes Menue wird beim Oeffnen eines Dialogs geschlossen
   do
      local anc = CreateFrame("Button", nil, parent)
      anc:SetWidth(80)
      anc:SetHeight(20)
      anc._rect = { 100, 600, 180, 620 }
      Skin.Menu.Open(anc, { { text = "a" }, { text = "b" } })
      ok(Skin.Menu.IsOpen(), "Menue offen")
      Skin.Confirm({ title = "m", text = "n", onAccept = function() end })
      ok(not Skin.Menu.IsOpen(), "Dialog schliesst offenes Menue")
      ok(TransmogConfirmFrame:IsShown(), "Dialog steht")
      Skin.CloseDialog()
   end

   -- Ohne Beschriftungen: Ja/Nein aus den Blizzard-Globalstrings
   YES, NO = "Ja", "Nein"
   Skin.Confirm({ title = "yn", text = "Sicher?", onAccept = function() acc = acc + 1 end })
   local yb, nb
   for _, c in ipairs(TransmogConfirmFrame._children) do
      if c._type == "Button" then
         if c.label:GetText() == "Ja" then yb = c end
         if c.label:GetText() == "Nein" then nb = c end
      end
   end
   ok(yb ~= nil and nb ~= nil and nb:IsShown(), "Confirm ohne Texte: Ja/Nein")
   Skin.CloseDialog()
   -- Nur accept gesetzt: Abbrechen bleibt Abbrechen (kein Ja/Nein-Paar)
   Skin.Confirm({ title = "yn", text = "Sicher?", accept = "Loeschen", onAccept = function() end })
   local cb2
   for _, c in ipairs(TransmogConfirmFrame._children) do
      if c._type == "Button" and c.label:GetText() == "Abbrechen" and c:IsShown() then cb2 = c end
   end
   ok(cb2 ~= nil, "Confirm mit accept: cancel bleibt CANCEL")
   Skin.CloseDialog()
   YES, NO = nil, nil

   -- Knopf-Klick auf Abbrechen; cancel=false blendet ihn aus
   Skin.Confirm({ title = "i", text = "Info", cancel = false, accept = "Verstanden", onAccept = function() acc = acc + 1 end })
   local cb
   for _, c in ipairs(TransmogConfirmFrame._children) do
      if c._type == "Button" and c.label:GetText() == "Abbrechen" then cb = c end
   end
   ok(cb == nil or not cb:IsShown(), "cancel=false: kein Abbrechen-Knopf")
   Skin.CloseDialog()

   -- Dialog aus dem Rueckruf eines anderen oeffnen
   local nested = false
   Skin.Prompt({ title = "1", text = "x", default = "a", onAccept = function()
      Skin.Confirm({ title = "2", text = "y", onAccept = function() nested = true end })
   end })
   pressEnter()
   ok(TransmogConfirmFrame:IsShown(), "verschachtelter Dialog offen")
   pressEnter()
   ok(nested, "verschachtelter Dialog akzeptiert")

   -- Skalierung folgt dem Hauptfenster
   TransmogWindow:SetScale(1.25)
   Skin.Confirm({ title = "s", text = "t", onAccept = function() end })
   near(TransmogConfirmFrame._scale, 1.25, "Dialog skaliert wie das Fenster")
   Skin.CloseDialog()
   TransmogWindow:SetScale(1)
end

-- ---------------------------------------------------------------------------
section("Tooltip")
do
   local owner = CreateFrame("Frame", nil, parent)
   Skin.Tooltip(owner, "ANCHOR_LEFT", { "Titel", { "Gruen", 0, 1, 0 }, { left = "Links", right = "Rechts" }, "Letzte" })
   eq(GameTooltip.owner, owner, "Owner")
   eq(GameTooltip.anchor, "ANCHOR_LEFT", "Anker")
   eq(#GameTooltip.lines, 4, "4 Zeilen")
   eq(GameTooltip.lines[1].text, "Titel", "Zeile 1")
   eq(GameTooltip.lines[2].g, 1, "Zeile 2 gruen")
   eq(GameTooltip.lines[3].right, "Rechts", "Doppelzeile")
   ok(GameTooltip.shown, "Tooltip gezeigt")
   Skin.HideTooltip(owner)
   ok(not GameTooltip.shown, "HideTooltip")
   Skin.Tooltip(owner, nil, {})
   ok(not GameTooltip.shown, "leere Zeilen: nicht gezeigt")
   Skin.Tooltip(owner, nil, "Einzeiler")
   eq(GameTooltip.lines[1].text, "Einzeiler", "String statt Liste")
end

-- ---------------------------------------------------------------------------
section("Hygiene")
do
   -- Alle benannten Rahmen: nur die erlaubten Namen
   local allowed = { TransmogPromptFrame = true, TransmogConfirmFrame = true, TransmogMenuFrame = true,
                     TransmogWindow = true }
   for name in pairs(NAMED) do ok(allowed[name], "unerlaubter Frame-Name " .. name) end
   -- Jede FontString hat eine Schrift
   for _, o in ipairs(ALL) do
      if getmetatable(o) == FontString then ok(o._font ~= nil, "FontString ohne Schrift") end
   end
end

print(string.format("%d Pruefungen, %d Fehler", checks, failures))
os.exit(failures == 0 and 0 or 1)
