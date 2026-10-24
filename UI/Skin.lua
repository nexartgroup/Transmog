-- Skin.lua  (T.UI.Skin)
-- ---------------------------------------------------------------------------
-- Gemeinsamer Baukasten fuer das flache dunkle UI (Stil wie AutoTravel).
--
-- Bewusst ohne Blizzard-Vorlagen und ohne mitgelieferte Grafikdateien: alles
-- besteht aus Backdrop + Interface\Buttons\WHITE8X8 und den paar eingebauten
-- 3.3.5a-Texturen, die SPEC 1.5 nennt.
--
-- Erfahrungen aus AutoTravel, die hier eingebaut sind:
--   * Knoepfe werden NICHT ueber Disable()/Enable() gesperrt (die Engine
--     verwarf danach Klicks), sondern ueber ein eigenes Merkmal (uiOff).
--     Ein gesperrter Knopf bleibt sichtbar und nennt den Grund im Tooltip.
--   * Handler bekommen ihre Parameter explizit, nie ueber this/arg1.
--
-- Abhaengigkeiten (alle weich, die Datei laedt auch allein):
--   T.COLORS, T.Util.G, T.DB.global.scale.
--
-- Kurzuebersicht der Schnittstelle (Details bei den Funktionen unten):
--   Skin.COL, Skin.WHITE, Skin.THEMES            Farben (SPEC 6.1), Textur, Knopf-Themen
--   Skin.Backdrop(frame, bg, border)             Flachrahmen aus WHITE8X8 (1 px Rand)
--   Skin.Panel(parent, bg, border)               Container mit Flachrahmen
--   Skin.Divider(parent, r, g, b, a)             1-px-Linie (Position setzt der Aufrufer)
--   Skin.Label(parent, text, font)               FontString (font = Name oder Objekt)
--   Skin.Header(frame, title, height)            Kopfzeile mit Akzentstreifen; :SetTitle
--   Skin.Button(parent, w, h, label, onClick)    onClick(self, mouseButton), nicht wenn gesperrt
--        :SetLabel :SetSelected :SetEnabledState(bool, reasonText) :SetIcon :SetAccent
--        :SetTheme("default"|"primary"|"danger") :SetTextColor :EnableRightClick(bool)
--        .tip = function(tooltip, button) | Text | Zeilenliste, .label, .icon
--   Skin.Check(parent, label, onChange)          onChange(checked, check) nur bei Klick
--        :SetChecked :GetChecked :SetLabel :SetEnabledState
--   Skin.EditBox(parent, w, h, placeholder, onChange)   onChange(text, userInput)
--        :SetPlaceholder :SetEnabledState, .onEnter(text, edit)
--   Skin.Slider(parent, w, min, max, step, onChange)    onChange(value, slider) nur bei Eingabe
--        :SetValueQuiet :SetRange :SetEnabledState, .valueText, .formatter(v, slider)
--   Skin.Menu.Open(anchor, items, opts), .Close(), .IsOpen(), .Anchor(), .Refresh(), .Scroll(delta)
--   Skin.Prompt(opts), Skin.Confirm(opts), Skin.CloseDialog(), Skin.DialogOpen()
--   Skin.Tooltip(owner, anchor, lines), Skin.HideTooltip(owner)
--   Skin.Desaturate(texture, bool), Skin.Icon(texture, path, noTrim), Skin.TrimIcon(texture)
--   Skin.GetScale(), Skin.IsMouseOver(frame)
--
-- Zum Verhalten: Es gibt hoechstens EIN Menue und EINEN Dialog zugleich. Beide
-- nehmen den Tastaturfokus (Menue/Confirm: unsichtbares EditBox, Prompt: das
-- Eingabefeld), damit ESC nur sie schliesst und nicht auch das Hauptfenster aus
-- UISpecialFrames; ein Klick neben das Menue schliesst es, ohne etwas dahinter
-- auszuloesen. OnUpdate laeuft nur, solange ein Menue offen ist.
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.UI = T.UI or {}

local Skin = {}
T.UI.Skin = Skin

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local format, tinsert = string.format, table.insert

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CHECK_TEXTURE = "Interface\\Buttons\\UI-CheckBox-Check"

Skin.WHITE = WHITE

-- ---------------------------------------------------------------------------
-- Farben
-- ---------------------------------------------------------------------------

-- Farbe aus T.COLORS holen (Init.lua kann noch fehlen), sonst Vorgabewert
local function pick(key, r, g, b)
   local src = T.COLORS and T.COLORS[key]
   if type(src) == "table" and tonumber(src[1]) then
      return { src[1], src[2] or g, src[3] or b, src[4] or 1 }
   end
   return { r, g, b, 1 }
end

local COL = {
   bg             = { 0.055, 0.062, 0.075, 0.94 },
   bgSolid        = { 0.055, 0.062, 0.075, 0.98 },
   border         = { 0.22,  0.25,  0.30,  1 },
   accent         = pick("accent", 0.20, 0.62, 0.92),
   text           = pick("text",   0.86, 0.88, 0.92),
   dim            = pick("dim",    0.50, 0.54, 0.60),
   yellow         = pick("yellow", 0.91, 0.77, 0.29),
   green          = pick("green",  0.33, 0.82, 0.48),
   red            = pick("red",    0.91, 0.40, 0.29),
   blue           = pick("blue",   0.35, 0.71, 0.91),
   grey           = pick("grey",   0.35, 0.38, 0.44),
   pink           = pick("pink",   0.96, 0.44, 0.96),
   head           = { 0.10,  0.12,  0.15,  1 },
   button         = { 0.13,  0.15,  0.18,  1 },
   buttonBorder   = { 0.26,  0.29,  0.34,  1 },
   hover          = { 0.19,  0.22,  0.27,  1 },
   pressed        = { 0.09,  0.10,  0.13,  1 },
   selected       = { 0.16,  0.34,  0.46,  1 },
   selectedBorder = { 0.35,  0.71,  0.91,  1 },
   selectedHover  = { 0.19,  0.40,  0.54,  1 },
   field          = { 0.08,  0.09,  0.11,  1 },
   fieldHover     = { 0.34,  0.38,  0.44,  1 },
   shade          = { 0,     0,     0,     0.55 },
   white          = { 1,     1,     1,     1 },
}

-- Alias-Namen (dieselben Tabellen, keine Kopien): andere Module greifen auf die Farben
-- ueber die Bezeichnungen aus SPEC 6.1 zu und raten dabei teils andere Kurzformen.
COL.header, COL.headerBg = COL.head, COL.head
COL.btn, COL.btnBg, COL.buttonBg = COL.button, COL.button, COL.button
COL.btnBorder = COL.buttonBorder
COL.hoverBg, COL.buttonHover = COL.hover, COL.hover
COL.selectedBg, COL.selBg = COL.selected, COL.selected
COL.selBorder = COL.selectedBorder
COL.panel, COL.panelBg = COL.bg, COL.bg
COL.input, COL.inputBg = COL.field, COL.field
COL.muted, COL.disabled = COL.dim, COL.grey
COL.highlight = COL.accent
COL.good, COL.success = COL.green, COL.green
COL.warn, COL.warning = COL.yellow, COL.yellow
COL.bad, COL.error, COL.danger = COL.red, COL.red, COL.red
COL.info = COL.blue
COL.transmog = COL.pink

-- Unbekannter Farbname: neutrale Textfarbe statt Fehler beim Aufbau des Fensters;
-- der Name wird in Skin.missingColors vermerkt (Hilfe beim Aufspueren).
Skin.missingColors = {}
setmetatable(COL, { __index = function(_, key)
   Skin.missingColors[tostring(key)] = true
   return rawget(COL, "text")
end })

Skin.COL = COL

-- Knopf-Themen: Farbsaetze je Zustand
local THEMES = {
   default = {
      bg = COL.button, border = COL.buttonBorder,
      hoverBg = COL.hover, hoverBorder = COL.accent, pressBg = COL.pressed,
      selBg = COL.selected, selBorder = COL.selectedBorder, selHoverBg = COL.selectedHover,
      text = COL.text, selText = COL.white,
   },
   primary = {
      bg = { 0.12, 0.30, 0.44, 1 }, border = { 0.26, 0.52, 0.70, 1 },
      hoverBg = { 0.16, 0.38, 0.55, 1 }, hoverBorder = COL.selectedBorder,
      pressBg = { 0.09, 0.22, 0.33, 1 },
      selBg = { 0.16, 0.38, 0.55, 1 }, selBorder = COL.selectedBorder,
      selHoverBg = { 0.19, 0.43, 0.60, 1 },
      text = COL.white, selText = COL.white,
   },
   danger = {
      bg = { 0.34, 0.12, 0.10, 1 }, border = { 0.66, 0.28, 0.21, 1 },
      hoverBg = { 0.46, 0.16, 0.13, 1 }, hoverBorder = COL.red,
      pressBg = { 0.25, 0.09, 0.08, 1 },
      selBg = { 0.46, 0.16, 0.13, 1 }, selBorder = COL.red,
      selHoverBg = { 0.52, 0.19, 0.15, 1 },
      text = { 1, 0.90, 0.87, 1 }, selText = COL.white,
   },
}

Skin.THEMES = THEMES

-- ---------------------------------------------------------------------------
-- Kleine Helfer (lokal)
-- ---------------------------------------------------------------------------

-- Wert in [lo, hi] zwingen
local function clamp(v, lo, hi)
   if v < lo then return lo end
   if v > hi then return hi end
   return v
end

-- Leerraum vorn/hinten entfernen (reines Lua, damit die Datei allein laedt)
local function trim(s)
   s = tostring(s or "")
   s = string.gsub(s, "^%s+", "")
   s = string.gsub(s, "%s+$", "")
   return s
end

-- Blizzard-Globalstring oder Fallback (nie nil)
local function G(name, fallback)
   local u = T.Util
   if u and u.G then return u.G(name, fallback) end
   local v = _G[name]
   if type(v) == "string" and v ~= "" then return v end
   return fallback
end

-- Liegt die Maus auf dem Rahmen? (Methode, sonst globale Hilfsfunktion)
local function isOver(frame)
   if not frame then return false end
   if frame.IsMouseOver then return frame:IsMouseOver() and true or false end
   if MouseIsOver then return MouseIsOver(frame) and true or false end
   if GetMouseFocus then return GetMouseFocus() == frame end
   return false
end

-- Klickgeraeusch (nur fuer Haken und Menueeintraege; unbekannte Namen schaden nicht)
local function clickSound(on)
   if PlaySound then
      pcall(PlaySound, on == false and "igMainMenuOptionCheckBoxOff" or "igMainMenuOptionCheckBoxOn")
   end
end

-- Schrift-Objekt eines EditBox-Aufrufs: Objekt bevorzugt, sonst Name
local function fontObject(name)
   return _G[name] or name
end

-- Skalierung des Rahmens relativ zu UIParent (1 = gleich gross)
local function scaleRatio(frame)
   if not frame or not frame.GetEffectiveScale or not UIParent then return nil end
   local es, ps = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
   if type(es) == "number" and type(ps) == "number" and ps > 0 and es > 0 then
      return es / ps
   end
   return nil
end

-- Textbreite in Pixeln (GameFontHighlightSmall, ohne Umbruch). Gemessen wird an einem
-- eigenen FontString ohne feste Breite, weil GetStringWidth() an einem Feld mit
-- fester Breite nur die umbrochene Breite liefert.
local measureFS
local function textWidth(text)
   if not measureFS then
      measureFS = UIParent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      measureFS:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -4096, -4096)
      measureFS:SetAlpha(0)
   end
   measureFS:SetText(text or "")
   return measureFS:GetStringWidth() or 0
end

-- Einfarbige Flaeche (WHITE8X8 + Vertexfarbe)
local function solid(parent, layer, c, alpha)
   local t = parent:CreateTexture(nil, layer or "ARTWORK")
   t:SetTexture(WHITE)
   t:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1)
   return t
end

-- ---------------------------------------------------------------------------
-- Grundfunktionen
-- ---------------------------------------------------------------------------

local BACKDROP = {
   bgFile = WHITE, edgeFile = WHITE, tile = false, edgeSize = 1,
   insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- Flachrahmen: 1-px-Rand + Fuellung (bg/border = {r,g,b,a}, Vorgabe COL.bg/COL.border)
function Skin.Backdrop(frame, bg, border)
   if not frame or not frame.SetBackdrop then return end
   bg = bg or COL.bg
   border = border or COL.border
   frame:SetBackdrop(BACKDROP)
   frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
   frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

-- Flacher Container-Rahmen ohne Maus (Panel); gibt den Frame zurueck
function Skin.Panel(parent, bg, border)
   local f = CreateFrame("Frame", nil, parent)
   Skin.Backdrop(f, bg, border)
   return f
end

-- 1-px-Trennlinie als Textur (Position setzt der Aufrufer); gibt die Textur zurueck
function Skin.Divider(parent, r, g, b, a)
   local t = parent:CreateTexture(nil, "ARTWORK")
   t:SetTexture(WHITE)
   t:SetVertexColor(r or COL.border[1], g or COL.border[2], b or COL.border[3], a or 0.9)
   t:SetHeight(1)
   return t
end

-- Skalierung fuer Dialoge/Menues ohne Bezugsrahmen: DB.global.scale (0 = 1.0)
function Skin.GetScale()
   local db = T.DB and T.DB.global
   local s = db and tonumber(db.scale)
   if s and s > 0 then return clamp(s, 0.6, 1.5) end
   return 1
end

-- Maus ueber Rahmen? (siehe isOver)
Skin.IsMouseOver = isOver

-- Beschriftung (FontString). font = Name eines Font-Objekts oder das Objekt selbst.
function Skin.Label(parent, text, font)
   local fs
   if type(font) == "string" and _G[font] then
      fs = parent:CreateFontString(nil, "ARTWORK", font)
   else
      fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      if type(font) == "table" then
         fs:SetFontObject(font)
      else
         fs:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
      end
   end
   fs:SetJustifyH("LEFT")
   fs:SetText(text or "")
   return fs
end

-- Textur entsaettigen (true/false). Rueckgabe: ob das Entsaettigen unterstuetzt wird.
-- Erst die Texturmethode, dann die alte globale Funktion; ohne beides wird nur abgedunkelt.
function Skin.Desaturate(texture, on)
   if not texture then return false end
   on = on and true or false
   local flag = on and 1 or nil
   local ok = false
   if texture.SetDesaturated then
      local called, supported = pcall(texture.SetDesaturated, texture, flag)
      ok = called and supported and true or false
   end
   -- Alte globale Funktion nur ueber _G lesen: sie fehlt in manchen Clients.
   local legacy = _G.SetDesaturation
   if not ok and type(legacy) == "function" then
      ok = pcall(legacy, texture, flag) and true or false
   end
   if on then
      if not ok and texture.SetVertexColor then
         texture.skinDimmed = true
         texture:SetVertexColor(0.5, 0.5, 0.5)
      end
   elseif texture.skinDimmed then
      texture.skinDimmed = nil
      texture:SetVertexColor(1, 1, 1)
   end
   return ok
end

-- Symbol-Ausschnitt ohne den Blizzard-Rand (TexCoord 0.07..0.93)
function Skin.TrimIcon(texture)
   if texture and texture.SetTexCoord then
      texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
   end
   return texture
end

-- Symbol setzen (path = nil leert); standardmaessig beschnitten, WHITE8X8 nie
function Skin.Icon(texture, path, noTrim)
   if not texture then return nil end
   if path then texture:SetTexture(path) else texture:SetTexture(nil) end
   if noTrim or path == WHITE or not path then
      texture:SetTexCoord(0, 1, 0, 1)
   else
      Skin.TrimIcon(texture)
   end
   return texture
end

-- ---------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------

-- Zeilen anhaengen: String | { text, r, g, b, wrap } | { left=, right=, r=, g=, b=, rr=, rg=, rb= }
local function addLines(tooltip, lines)
   if type(lines) == "string" then lines = { lines } end
   if type(lines) ~= "table" then return end
   for i = 1, #lines do
      local ln = lines[i]
      local first = (i == 1)
      local text, r, g, b, wrap, right
      if type(ln) == "table" then
         text = ln[1] or ln.text or ln.left
         r, g, b = ln[2] or ln.r, ln[3] or ln.g, ln[4] or ln.b
         wrap = ln[5]
         if wrap == nil then wrap = ln.wrap end
         right = ln.right
         if right ~= nil then
            tooltip:AddDoubleLine(tostring(text or ""), tostring(right),
               r or COL.text[1], g or COL.text[2], b or COL.text[3],
               ln.rr or COL.text[1], ln.rg or COL.text[2], ln.rb or COL.text[3])
            text = nil
         end
      else
         text = ln
      end
      if text ~= nil then
         if not r then
            if first then r, g, b = 1, 1, 1 else r, g, b = 0.78, 0.81, 0.86 end
         elseif g == nil or b == nil then
            -- unvollstaendige Farbangabe: Grauton aus r statt Fehler im OnEnter
            g, b = g or r, b or r
         end
         if wrap == nil then wrap = not first end
         tooltip:AddLine(tostring(text), r, g, b, wrap and true or nil)
      end
   end
end

-- GameTooltip an owner verankern und mit Zeilen fuellen
-- (anchor z. B. "ANCHOR_RIGHT"; lines siehe addLines). Leere Liste verbirgt ihn.
function Skin.Tooltip(owner, anchor, lines)
   if not owner or not GameTooltip then return end
   GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
   addLines(GameTooltip, lines)
   if GameTooltip:NumLines() > 0 then GameTooltip:Show() else GameTooltip:Hide() end
end

-- GameTooltip verbergen, aber nur wenn er diesem Rahmen gehoert
function Skin.HideTooltip(owner)
   if not GameTooltip then return end
   if owner and GameTooltip.IsOwned then
      if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
   else
      GameTooltip:Hide()
   end
end

-- Tooltip eines Widgets zeigen: Sperrgrund (falls gesperrt) oder .tip
-- (.tip = function(tooltip, widget) | String | Zeilenliste)
local function showWidgetTip(w, title)
   if not GameTooltip then return end
   local anchor = w.tipAnchor or "ANCHOR_RIGHT"
   if w.uiOff and w.disabledTip and w.disabledTip ~= "" then
      GameTooltip:SetOwner(w, anchor)
      if title and title ~= "" then GameTooltip:AddLine(title, 1, 1, 1) end
      GameTooltip:AddLine(w.disabledTip, COL.yellow[1], COL.yellow[2], COL.yellow[3], true)
      GameTooltip:Show()
      return
   end
   local tip = w.tip
   if tip == nil or tip == false then return end
   GameTooltip:SetOwner(w, anchor)
   if type(tip) == "function" then
      tip(GameTooltip, w)
   else
      addLines(GameTooltip, tip)
   end
   if GameTooltip:NumLines() > 0 then GameTooltip:Show() else GameTooltip:Hide() end
end

-- Liegt die Maus auf dem Widget und aendert sich sein Zustand (gesperrt/frei), den
-- Tooltip neu aufbauen: OnEnter feuert dafuer nicht erneut. Das gilt auch, wenn
-- bisher gar kein Tooltip da war (freier Knopf ohne .tip, der gesperrt wird: der
-- Grund soll sofort erscheinen, z. B. direkt nach dem Klick auf "Anwenden").
local function refreshWidgetTip(w, title)
   if not GameTooltip or not w.hover then return end
   if GameTooltip.IsOwned and GameTooltip:IsOwned(w) and GameTooltip:IsShown() then
      GameTooltip:Hide()
   end
   showWidgetTip(w, title)
end

-- ---------------------------------------------------------------------------
-- Header
-- ---------------------------------------------------------------------------

-- Kopfzeile mit Akzentstreifen (wie AutoTravel) oben in frame. Gibt den Kopf-Frame
-- zurueck: .title (FontString), .stripe (Textur), :SetTitle(text). height optional (30).
function Skin.Header(frame, title, height)
   local head = CreateFrame("Frame", nil, frame)
   head:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
   head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
   head:SetHeight(height or 30)
   head:SetBackdrop({ bgFile = WHITE })
   head:SetBackdropColor(COL.head[1], COL.head[2], COL.head[3], 1)

   local stripe = solid(head, "OVERLAY", COL.accent, 1)
   stripe:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
   stripe:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
   stripe:SetWidth(3)
   head.stripe = stripe

   local line = solid(head, "OVERLAY", COL.border, 0.9)
   line:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
   line:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
   line:SetHeight(1)
   head.line = line

   local fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   fs:SetPoint("LEFT", head, "LEFT", 12, 0)
   fs:SetTextColor(0.92, 0.94, 0.97)
   fs:SetText(title or "")
   head.title = fs

   head.SetTitle = function(self, text)
      self.title:SetText(text or "")
   end
   return head
end

-- ---------------------------------------------------------------------------
-- Button
-- ---------------------------------------------------------------------------

-- Inhalt (Icon + Text) im Knopf platzieren; Breite wird explizit gerechnet
local function buttonLayout(b)
   local fs, icon = b.label, b.icon
   local inset = 4
   if b.accentTex and b.accentTex:IsShown() then inset = 8 end
   local hasIcon = icon ~= nil and icon:GetTexture() ~= nil
   local text = fs:GetText()
   local hasText = text ~= nil and text ~= ""

   fs:ClearAllPoints()
   if icon then icon:ClearAllPoints() end

   if hasIcon then
      -- Groesse des Symbols: tatsaechliche Breite (auch bei direktem icon:SetWidth)
      local isz = icon:GetWidth() or 0
      if isz < 1 then isz = b.iconSize or 14 end
      if hasText then
         local avail = max(10, (b:GetWidth() or 0) - inset - 4)
         local tw = min(fs:GetStringWidth() or 0, max(0, avail - isz - 4))
         local x = inset + floor((avail - (isz + 4 + tw)) / 2)
         icon:SetPoint("LEFT", b, "LEFT", max(inset, x), 0)
         fs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
         fs:SetPoint("RIGHT", b, "RIGHT", -4, 0)
         fs:SetJustifyH("LEFT")
      else
         icon:SetPoint("CENTER", b, "CENTER", 0, 0)
         fs:SetPoint("CENTER", b, "CENTER", 0, 0)
         fs:SetJustifyH("CENTER")
      end
   else
      if icon then icon:SetPoint("CENTER", b, "CENTER", 0, 0) end
      fs:SetPoint("LEFT", b, "LEFT", inset, 0)
      fs:SetPoint("RIGHT", b, "RIGHT", -4, 0)
      fs:SetJustifyH("CENTER")
   end
end

-- Farben nach Zustand setzen: gesperrt > gedrueckt > Hover > ausgewaehlt > Ruhe
local function buttonPaint(b)
   local th = b.theme or THEMES.default
   local bg, bd, tc
   if b.uiOff then
      if b.selected then bg, bd = th.selBg, th.selBorder else bg, bd = th.bg, th.border end
      tc = COL.dim
   elseif b.pressed and b.hover then
      bg, bd = th.pressBg, th.hoverBorder
      tc = b.selected and th.selText or b.textColor or th.text
   elseif b.hover then
      bg = b.selected and th.selHoverBg or th.hoverBg
      bd = th.hoverBorder
      tc = b.selected and th.selText or b.textColor or th.text
   elseif b.selected then
      bg, bd, tc = th.selBg, th.selBorder, th.selText
   else
      bg, bd, tc = th.bg, th.border, b.textColor or th.text
   end
   b:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
   b:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4] or 1)
   b.label:SetTextColor(tc[1], tc[2], tc[3])
end

local ButtonMethods = {}

-- Beschriftung setzen
function ButtonMethods:SetLabel(text)
   self.label:SetText(text or "")
   buttonLayout(self)
end

-- Beschriftung lesen (nie nil)
function ButtonMethods:GetLabel()
   return self.label:GetText() or ""
end

-- Hervorgehoben ("ausgewaehlt") darstellen, z. B. aktiver Tab
function ButtonMethods:SetSelected(selected)
   self.selected = selected and true or false
   buttonPaint(self)
end

-- Ist der Knopf ausgewaehlt?
function ButtonMethods:IsSelected()
   return self.selected and true or false
end

-- Sperren/freigeben ohne Disable()/Enable(); reasonText erscheint im Tooltip
function ButtonMethods:SetEnabledState(enabled, reasonText)
   enabled = enabled and true or false
   self.disabledTip = (not enabled) and reasonText or nil
   if enabled then
      -- Die Maus-Hervorhebung (self.hover) wird auch im gesperrten Zustand mitgefuehrt:
      -- OnEnter/OnLeave laufen weiter, nur der Klick wird verworfen. Ein Knopf, der
      -- unter der ruhenden Maus freigegeben wird, zeigt also sofort den Hover.
      self.uiOff = false
      self:SetAlpha(1)
   else
      self.uiOff = true
      self:SetAlpha(0.45)
   end
   buttonPaint(self)
   refreshWidgetTip(self, self.label:GetText())
end

-- Ist der Knopf freigegeben? (eigener Merker)
function ButtonMethods:IsEnabledState()
   return not self.uiOff
end

-- Farbthema: "default" | "primary" | "danger" oder eine eigene Tabelle (siehe Skin.THEMES)
function ButtonMethods:SetTheme(theme)
   if type(theme) == "table" then
      self.theme = theme
   else
      self.theme = THEMES[theme or "default"] or THEMES.default
   end
   buttonPaint(self)
end

-- Eigene Textfarbe fuer den Ruhezustand (nil = Thema)
function ButtonMethods:SetTextColor(r, g, b)
   if r then self.textColor = { r, g, b, 1 } else self.textColor = nil end
   buttonPaint(self)
end

-- Symbol (Texturpfad) links vom Text; path = nil entfernt es. size Vorgabe 14.
function ButtonMethods:SetIcon(path, size, noTrim)
   if size then self.iconSize = size end
   local sz = self.iconSize or 14
   self.icon:SetWidth(sz)
   self.icon:SetHeight(sz)
   Skin.Icon(self.icon, path, noTrim)
   buttonLayout(self)
end

-- Linker Akzentstreifen in Farbe r,g,b (nil blendet ihn aus)
function ButtonMethods:SetAccent(r, g, b, a)
   if not self.accentTex then
      local t = solid(self, "OVERLAY", COL.accent, 1)
      t:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
      t:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 1, 1)
      t:SetWidth(3)
      self.accentTex = t
   end
   if r then
      self.accentTex:SetVertexColor(r, g or r, b or r, a or 1)
      self.accentTex:Show()
   else
      self.accentTex:Hide()
   end
   buttonLayout(self)
end

-- Rechtsklick zusaetzlich zu Linksklick melden (onClick(self, button))
function ButtonMethods:EnableRightClick(on)
   if on == false then
      self:RegisterForClicks("LeftButtonUp")
   else
      self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
   end
end

-- Inhalt neu anordnen (nach direktem Zugriff auf .icon/.label)
function ButtonMethods:RefreshLayout()
   buttonLayout(self)
   buttonPaint(self)
end

-- Flacher Knopf. onClick(self, button) wird bei Linksklick gerufen (nicht, wenn gesperrt).
function Skin.Button(parent, w, h, label, onClick)
   local b = CreateFrame("Button", nil, parent)
   b:SetWidth(w or 80)
   b:SetHeight(h or 22)
   Skin.Backdrop(b, COL.button, COL.buttonBorder)

   local icon = b:CreateTexture(nil, "ARTWORK")
   icon:SetWidth(14)
   icon:SetHeight(14)
   b.icon = icon
   -- Wer b.icon:SetTexture(...) direkt aufruft, soll nicht ueber den Text malen:
   -- das Layout wird dann nachgezogen.
   local engineIconSetTexture = icon.SetTexture
   icon.SetTexture = function(self, ...)
      engineIconSetTexture(self, ...)
      buttonLayout(b)
   end

   local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   fs:SetHeight(14)
   fs:SetText(label or "")
   b.label = fs

   for k, fn in pairs(ButtonMethods) do b[k] = fn end

   b.onClick = onClick
   b.theme = THEMES.default
   b.hover, b.pressed, b.selected, b.uiOff = false, false, false, false
   b:RegisterForClicks("LeftButtonUp")

   -- Fremder Code ruft aus Gewohnheit :SetText/:Enable/:Disable: auf unsere Mittel umleiten.
   b.SetText = ButtonMethods.SetLabel
   b.GetText = ButtonMethods.GetLabel
   b.Enable = function(self) self:SetEnabledState(true) end
   b.Disable = function(self) self:SetEnabledState(false, self.disabledTip) end
   b.IsEnabled = function(self) return (not self.uiOff) and 1 or nil end

   b:SetScript("OnEnter", function(self)
      self.hover = true
      buttonPaint(self)
      showWidgetTip(self, self.label:GetText())
   end)
   b:SetScript("OnLeave", function(self)
      self.hover = false
      self.pressed = false
      buttonPaint(self)
      Skin.HideTooltip(self)
   end)
   b:SetScript("OnMouseDown", function(self)
      -- Reiter, Anwenden, Verwerfen, Menues usw.: ein Klick nimmt dem Suchfeld
      -- der Filterleiste den Tastaturfokus (Leiste spaet gebunden: sie wird nach
      -- dem Skin geladen)
      local fb = T.UI and T.UI.FilterBar
      if fb and fb.ReleaseFocus then
         fb.ReleaseFocus()
      end
      self.pressed = true
      buttonPaint(self)
   end)
   b:SetScript("OnMouseUp", function(self)
      self.pressed = false
      buttonPaint(self)
   end)
   b:SetScript("OnHide", function(self)
      -- OnLeave feuert beim Verbergen nicht zuverlaessig
      self.hover = false
      self.pressed = false
      buttonPaint(self)
      Skin.HideTooltip(self)
   end)
   b:SetScript("OnSizeChanged", function(self)
      buttonLayout(self)
   end)
   b:SetScript("OnClick", function(self, button)
      if self.uiOff then return end
      local fn = self.onClick
      if fn then fn(self, button) end
   end)

   buttonLayout(b)
   buttonPaint(b)
   return b
end

-- ---------------------------------------------------------------------------
-- Check (Checkbox)
-- ---------------------------------------------------------------------------

local CHECK_BOX = 16
local CHECK_GAP = 6

-- Zustand der Box zeichnen
local function checkPaint(c)
   local bg, bd
   if c.checked then
      bg, bd = COL.selected, COL.selectedBorder
   else
      bg, bd = COL.field, COL.buttonBorder
   end
   if c.hover and not c.uiOff then bd = COL.accent end
   c.box:SetBackdropColor(bg[1], bg[2], bg[3], 1)
   c.box:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
   if c.checked then c.mark:Show() else c.mark:Hide() end
   local tc = c.uiOff and COL.dim or COL.text
   c.label:SetTextColor(tc[1], tc[2], tc[3])
end

local CheckMethods = {}

-- Haken setzen, ohne onChange zu rufen
function CheckMethods:SetChecked(value)
   self.checked = value and true or false
   checkPaint(self)
end

-- Ist der Haken gesetzt? (bool)
function CheckMethods:GetChecked()
   return self.checked and true or false
end

-- Beschriftung setzen; die Breite folgt dem Text, solange niemand SetWidth rief
function CheckMethods:SetLabel(text)
   self.label:SetText(text or "")
   if self.autoWidth then
      -- Am Messer, nicht am Label: dessen Breite folgt noch dem alten, kuerzeren Text.
      local tw = textWidth(text)
      self.engineSetWidth(self, CHECK_BOX + CHECK_GAP + ceil(tw) + 4)
   end
end

-- Beschriftung lesen (nie nil)
function CheckMethods:GetLabel()
   return self.label:GetText() or ""
end

-- Sperren/freigeben (wie beim Button), reasonText erscheint im Tooltip
function CheckMethods:SetEnabledState(enabled, reasonText)
   enabled = enabled and true or false
   self.disabledTip = (not enabled) and reasonText or nil
   self.uiOff = not enabled
   self:SetAlpha(enabled and 1 or 0.45)
   checkPaint(self)
   refreshWidgetTip(self, self.label:GetText())
end

-- Ist die Checkbox freigegeben?
function CheckMethods:IsEnabledState()
   return not self.uiOff
end

-- Flache Checkbox mit Beschriftung. onChange(checked, check) nur bei Klick des Spielers.
function Skin.Check(parent, label, onChange)
   local c = CreateFrame("Button", nil, parent)
   c:SetHeight(20)

   local box = CreateFrame("Frame", nil, c)
   box:SetWidth(CHECK_BOX)
   box:SetHeight(CHECK_BOX)
   box:SetPoint("LEFT", c, "LEFT", 0, 0)
   Skin.Backdrop(box, COL.field, COL.buttonBorder)
   c.box = box

   local mark = box:CreateTexture(nil, "OVERLAY")
   mark:SetTexture(CHECK_TEXTURE)
   mark:SetWidth(CHECK_BOX + 6)
   mark:SetHeight(CHECK_BOX + 6)
   mark:SetPoint("CENTER", box, "CENTER", 0, 0)
   Skin.Desaturate(mark, true)
   mark:SetVertexColor(0.80, 0.93, 1.0)
   mark:Hide()
   c.mark = mark

   local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   fs:SetPoint("LEFT", box, "RIGHT", CHECK_GAP, 0)
   fs:SetHeight(14)
   fs:SetJustifyH("LEFT")
   c.label = fs

   for k, fn in pairs(CheckMethods) do c[k] = fn end

   c.onChange = onChange
   c.checked, c.hover, c.uiOff = false, false, false
   c.autoWidth = true
   c.engineSetWidth = c.SetWidth
   -- Ein vom Aufrufer gesetzter Wert gewinnt gegen die automatische Breite.
   c.SetWidth = function(self, width)
      self.autoWidth = false
      self.engineSetWidth(self, width)
   end

   -- Alte Gewohnheiten (SetText/Enable/Disable) auf unsere Mittel umleiten
   c.SetText = CheckMethods.SetLabel
   c.GetText = CheckMethods.GetLabel
   c.Enable = function(self) self:SetEnabledState(true) end
   c.Disable = function(self) self:SetEnabledState(false, self.disabledTip) end
   c.IsEnabled = function(self) return (not self.uiOff) and 1 or nil end

   c:SetScript("OnSizeChanged", function(self, w)
      w = tonumber(w) or self:GetWidth() or 0
      self.label:SetWidth(max(8, w - CHECK_BOX - CHECK_GAP))
   end)
   c:SetScript("OnEnter", function(self)
      self.hover = true
      checkPaint(self)
      showWidgetTip(self, self.label:GetText())
   end)
   c:SetScript("OnLeave", function(self)
      self.hover = false
      checkPaint(self)
      Skin.HideTooltip(self)
   end)
   c:SetScript("OnHide", function(self)
      self.hover = false
      checkPaint(self)
      Skin.HideTooltip(self)
   end)
   c:SetScript("OnClick", function(self)
      if self.uiOff then return end
      self.checked = not self.checked
      checkPaint(self)
      clickSound(self.checked)
      local fn = self.onChange
      if fn then fn(self.checked, self) end
   end)

   c:SetLabel(label or "")
   checkPaint(c)
   return c
end

-- ---------------------------------------------------------------------------
-- EditBox
-- ---------------------------------------------------------------------------

-- Platzhalter nur zeigen, solange leer UND ohne Fokus
local function editPlaceholder(e)
   local ph = e.placeholderText
   if not ph then return end
   local text = e:GetText()
   if (text == nil or text == "") and not e.focused then ph:Show() else ph:Hide() end
end

-- Randfarbe: Fokus > Hover > Ruhe
local function editPaint(e)
   local bd = COL.buttonBorder
   if e.focused then bd = COL.accent elseif e.hover then bd = COL.fieldHover end
   e:SetBackdropColor(COL.field[1], COL.field[2], COL.field[3], 1)
   e:SetBackdropBorderColor(bd[1], bd[2], bd[3], 1)
end

local EditMethods = {}

-- Platzhaltertext setzen (grau, nur bei leerem Feld ohne Fokus)
function EditMethods:SetPlaceholder(text)
   self.placeholderText:SetText(text or "")
   editPlaceholder(self)
end

-- Sperren/freigeben (Maus aus, abgeblendet); kein Disable() noetig
function EditMethods:SetEnabledState(enabled)
   enabled = enabled and true or false
   self.uiOff = not enabled
   self:EnableMouse(enabled)
   self:SetAlpha(enabled and 1 or 0.45)
   if not enabled then
      -- Ohne Maus feuert OnLeave nicht mehr: Hover-Merker selbst zuruecksetzen
      self.hover = false
      if self.focused then self:ClearFocus() end
   end
   editPaint(self)
end

-- Flaches Eingabefeld. onChange(text, userInput): userInput ist false, wenn der Text
-- per :SetText gesetzt wurde (auch ueber fremde Aufrufer), true bei Eingabe.
-- Escape und Enter geben den Fokus ab; .onEnter(text, edit) wird bei Enter gerufen.
function Skin.EditBox(parent, w, h, placeholder, onChange)
   local e = CreateFrame("EditBox", nil, parent)
   e:SetWidth(w or 160)
   e:SetHeight(h or 22)
   e:SetFontObject(fontObject("GameFontHighlight"))
   e:SetAutoFocus(false)
   e:SetTextInsets(6, 6, 0, 0)
   e:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
   Skin.Backdrop(e, COL.field, COL.buttonBorder)

   local ph = e:CreateFontString(nil, "ARTWORK", "GameFontDisable")
   ph:SetPoint("LEFT", e, "LEFT", 7, 0)
   ph:SetPoint("RIGHT", e, "RIGHT", -7, 0)
   ph:SetHeight(14)
   ph:SetJustifyH("LEFT")
   ph:SetText(placeholder or "")
   e.placeholderText = ph

   for k, fn in pairs(EditMethods) do e[k] = fn end

   e.onChange = onChange
   e.focused, e.hover, e.uiOff = false, false, false

   -- :SetText meldet sich als "keine Eingabe" (settingText), egal ob die Engine das
   -- userInput-Argument von OnTextChanged mitliefert.
   local engineSetText = e.SetText
   e.SetText = function(self, text)
      self.settingText = true
      engineSetText(self, text or "")
      self.settingText = false
      editPlaceholder(self)
   end

   e:SetScript("OnTextChanged", function(self, userInput)
      local ui
      if self.settingText then
         ui = false
      elseif userInput == nil then
         ui = true
      else
         ui = userInput and true or false
      end
      editPlaceholder(self)
      local fn = self.onChange
      if fn then fn(self:GetText() or "", ui) end
   end)
   e:SetScript("OnEditFocusGained", function(self)
      self.focused = true
      editPaint(self)
      editPlaceholder(self)
   end)
   e:SetScript("OnEditFocusLost", function(self)
      self.focused = false
      editPaint(self)
      editPlaceholder(self)
   end)
   e:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
   end)
   e:SetScript("OnEnterPressed", function(self)
      self:ClearFocus()
      local fn = self.onEnter
      if fn then fn(self:GetText() or "", self) end
   end)
   e:SetScript("OnEnter", function(self)
      self.hover = true
      editPaint(self)
   end)
   e:SetScript("OnLeave", function(self)
      self.hover = false
      editPaint(self)
   end)
   e:SetScript("OnHide", function(self)
      self.hover = false
      editPaint(self)
   end)

   editPaint(e)
   editPlaceholder(e)
   return e
end

-- ---------------------------------------------------------------------------
-- Slider
-- ---------------------------------------------------------------------------

-- Wert auf Schrittweite einrasten und in [min, max] halten
local function sliderSnap(s, v)
   local lo, hi, st = s.minV, s.maxV, s.stepV
   v = tonumber(v) or lo
   if st and st > 0 then
      v = lo + floor((v - lo) / st + 0.5) * st
      v = floor(v * 1000 + 0.5) / 1000    -- Rundungsrauschen bei Dezimalschritten
   end
   return clamp(v, lo, hi)
end

-- Wert als Text (formatter(v, slider) falls gesetzt)
local function sliderText(s, v)
   if s.formatter then
      local ok, text = pcall(s.formatter, v, s)
      if ok and text ~= nil then return tostring(text) end
   end
   if s.stepV and s.stepV >= 1 and floor(s.stepV) == s.stepV then
      return format("%d", floor(v + 0.5))
   end
   return tostring(floor(v * 100 + 0.5) / 100)
end

-- Fuellbalken, Daumen und Wertetext an den aktuellen Wert anpassen
local function sliderVisual(s)
   local v = s:GetValue() or s.minV
   local span = s.maxV - s.minV
   local frac = span > 0 and clamp((v - s.minV) / span, 0, 1) or 0
   local inner = max(1, (s:GetWidth() or 0) - 2)
   local tw = s.thumbW
   s.fill:SetWidth(max(1, floor(frac * (inner - tw) + tw / 2 + 0.5)))
   s.valueText:SetText(sliderText(s, v))
end

local SliderMethods = {}

-- Wert setzen, ohne onChange zu rufen (rastet ein)
function SliderMethods:SetValueQuiet(v)
   v = sliderSnap(self, v)
   self.quiet = true
   self:SetValue(v)
   self.quiet = false
   self.lastValue = v
   sliderVisual(self)
end

-- Eingerasteter aktueller Wert
function SliderMethods:GetSnappedValue()
   return sliderSnap(self, self:GetValue())
end

-- Wertetext neu berechnen (nach Aenderung von .formatter)
function SliderMethods:RefreshText()
   sliderVisual(self)
end

-- Sperren/freigeben; gesperrt springt der Wert zurueck, der Grund steht im Tooltip
function SliderMethods:SetEnabledState(enabled, reasonText)
   enabled = enabled and true or false
   self.disabledTip = (not enabled) and reasonText or nil
   self.uiOff = not enabled
   self:SetAlpha(enabled and 1 or 0.45)
   refreshWidgetTip(self, nil)
end

-- Neuen Bereich setzen (Wert wird eingerastet, onChange nicht gerufen)
function SliderMethods:SetRange(lo, hi, step)
   self.minV, self.maxV = lo, hi
   if step and step > 0 then self.stepV = step end
   self.quiet = true
   self:SetMinMaxValues(lo, hi)
   self:SetValueStep(self.stepV)
   self.quiet = false
   self:SetValueQuiet(self:GetValue())
end

-- Flacher Slider (Spur + Daumen aus WHITE8X8). onChange(value, slider) nur bei Eingabe
-- (Ziehen, Klick, Mausrad). .valueText = FontString rechts neben der Spur,
-- .formatter = function(v, slider) -> Text (optional).
function Skin.Slider(parent, w, minV, maxV, step, onChange)
   local s = CreateFrame("Slider", nil, parent)
   minV = tonumber(minV) or 0
   maxV = tonumber(maxV) or 1
   if maxV < minV then minV, maxV = maxV, minV end
   step = tonumber(step)
   if not step or step <= 0 then step = 1 end

   s:SetOrientation("HORIZONTAL")
   s:EnableMouse(true)
   s:SetWidth(w or 160)
   s:SetHeight(16)
   s.minV, s.maxV, s.stepV = minV, maxV, step
   s.thumbW = 10
   s.onChange = onChange
   s.quiet, s.snapping, s.uiOff = false, false, false

   -- Spur: Rand, Grund, Fuellung (alles Texturen des Sliders, damit der Daumen darueber liegt)
   local track = solid(s, "BACKGROUND", COL.buttonBorder, 1)
   track:SetPoint("LEFT", s, "LEFT", 0, 0)
   track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
   track:SetHeight(6)
   local inner = solid(s, "BORDER", COL.field, 1)
   inner:SetPoint("LEFT", s, "LEFT", 1, 0)
   inner:SetPoint("RIGHT", s, "RIGHT", -1, 0)
   inner:SetHeight(4)
   local fill = solid(s, "ARTWORK", COL.accent, 0.75)
   fill:SetPoint("LEFT", s, "LEFT", 1, 0)
   fill:SetHeight(4)
   fill:SetWidth(1)
   s.track, s.fill = track, fill

   s:SetThumbTexture(WHITE)
   local thumb = s:GetThumbTexture()
   if thumb then
      thumb:SetDrawLayer("OVERLAY")
      thumb:SetWidth(s.thumbW)
      thumb:SetHeight(16)
      thumb:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3], 1)
   end
   s.thumb = thumb

   local vt = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   vt:SetPoint("LEFT", s, "RIGHT", 8, 0)
   vt:SetHeight(14)
   vt:SetJustifyH("LEFT")
   vt:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
   s.valueText = vt

   for k, fn in pairs(SliderMethods) do s[k] = fn end

   -- Bereich setzen, bevor die Skripte haengen (SetMinMaxValues kann den Wert bewegen)
   s:SetMinMaxValues(minV, maxV)
   s:SetValueStep(step)
   s:SetValue(minV)
   s.lastValue = minV

   s:SetScript("OnValueChanged", function(self, value)
      if self.snapping then return end
      value = tonumber(value) or self:GetValue()
      local snapped = sliderSnap(self, value)

      -- Gesperrt: Eingabe verwerfen, alten Wert wiederherstellen
      if self.uiOff and not self.quiet then
         self.snapping = true
         self:SetValue(self.lastValue or self.minV)
         self.snapping = false
         sliderVisual(self)
         return
      end

      if snapped ~= value then
         self.snapping = true
         self:SetValue(snapped)
         self.snapping = false
      end
      sliderVisual(self)
      if self.quiet then return end
      if self.lastValue == snapped then return end
      self.lastValue = snapped
      local fn = self.onChange
      if fn then fn(snapped, self) end
   end)

   s:EnableMouseWheel(true)
   s:SetScript("OnMouseWheel", function(self, delta)
      if self.uiOff or not delta or delta == 0 then return end
      local v = sliderSnap(self, (self:GetValue() or self.minV) + (delta > 0 and 1 or -1) * self.stepV)
      self:SetValue(v)
   end)
   s:SetScript("OnSizeChanged", function(self)
      sliderVisual(self)
   end)
   s:SetScript("OnEnter", function(self)
      self.hover = true
      if self.thumb then
         self.thumb:SetVertexColor(COL.selectedBorder[1], COL.selectedBorder[2], COL.selectedBorder[3], 1)
      end
      showWidgetTip(self, nil)
   end)
   s:SetScript("OnLeave", function(self)
      self.hover = false
      if self.thumb then
         self.thumb:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3], 1)
      end
      Skin.HideTooltip(self)
   end)
   s:SetScript("OnHide", function(self)
      self.hover = false
      Skin.HideTooltip(self)
   end)

   sliderVisual(s)
   return s
end

-- ---------------------------------------------------------------------------
-- Tastatur-Fanger
-- ---------------------------------------------------------------------------
-- UISpecialFrames schliesst bei ESC ALLE sichtbaren Sonderfenster auf einmal, also
-- auch das Hauptfenster hinter einem Dialog. Ein unsichtbares, fokussiertes
-- EditBox faengt ESC/Enter vorher ab und verschluckt Tipp-Tasten, solange das
-- Menue/der Dialog offen ist.

-- Unsichtbares Eingabefeld, das Enter/Escape an die Rueckrufe weitergibt
local function makeGrabber(parent, onEnter, onEscape)
   local g = CreateFrame("EditBox", nil, parent)
   g:SetWidth(2)
   g:SetHeight(2)
   g:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
   g:SetFontObject(fontObject("ChatFontNormal"))
   g:SetAutoFocus(false)
   g:EnableMouse(false)    -- nur per SetFocus erreichbar, nimmt keine Klicks
   g:SetAlpha(0)
   g:SetScript("OnTextChanged", function(self)
      local t = self:GetText()
      if t ~= nil and t ~= "" then self:SetText("") end
   end)
   g:SetScript("OnEnterPressed", function() if onEnter then onEnter() end end)
   g:SetScript("OnEscapePressed", function() if onEscape then onEscape() end end)
   return g
end

-- ---------------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------------

local Menu = {}
Skin.Menu = Menu

local MENU_ROW = 20
local MENU_PAD = 4
local MENU_MAX_ROWS = 18
local MENU_MIN_W = 120
local MENU_MAX_W = 380
local MENU_WHEEL = 3

-- Vorwaertsdeklaration (unten bei den Dialogen gesetzt): nach dem Schliessen eines
-- Menues den offenen Dialog wieder fokussieren, damit ESC nicht durchrutscht.
local refocusDialog

-- Zustand des (einzigen) Menues
local M = {
   frame = nil, catcher = nil, grab = nil, barThumb = nil,
   rows = {}, items = nil, opts = nil, anchor = nil,
   count = 0, visible = 0, offset = 0, rowW = 0, open = false, acc = 0,
}

-- Eintrag zeichnen (Text, Farbe, Haken/Punkt, Zustand)
local function menuPaintRow(r, item)
   r.item = item
   local isTitle = item.isTitle and true or false
   local off = item.disabled and true or false
   local c
   if isTitle then
      c = item.color or COL.yellow
   elseif off then
      c = COL.grey
   else
      c = item.color or COL.text
   end

   r.text:ClearAllPoints()
   if isTitle then
      r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
   else
      r.text:SetPoint("LEFT", r, "LEFT", 24, 0)
   end
   r.text:SetPoint("RIGHT", r, "RIGHT", -8, 0)
   r.text:SetText(item.text or "")
   r.text:SetTextColor(c[1], c[2], c[3])

   if isTitle or not item.checked then
      r.check:Hide()
      r.dot:Hide()
   elseif item.radio then
      r.check:Hide()
      r.dot:Show()
   else
      r.check:Show()
      r.dot:Hide()
   end

   r.uiOff = off
   r.disabledTip = item.reason
   r.tip = item.tip
   r.tipAnchor = "ANCHOR_RIGHT"

   if not isTitle and not off and isOver(r) then r.hl:Show() else r.hl:Hide() end
end

-- Zeile aus dem Vorrat holen/anlegen
local function menuRow(i)
   local r = M.rows[i]
   if r then return r end
   r = CreateFrame("Button", nil, M.frame)
   r:SetHeight(MENU_ROW)

   local hl = solid(r, "BACKGROUND", COL.accent, 0.25)
   hl:SetAllPoints(r)
   hl:Hide()
   r.hl = hl

   local check = r:CreateTexture(nil, "ARTWORK")
   check:SetTexture(CHECK_TEXTURE)
   check:SetWidth(20)
   check:SetHeight(20)
   check:SetPoint("LEFT", r, "LEFT", 2, 0)
   Skin.Desaturate(check, true)
   check:SetVertexColor(0.80, 0.93, 1.0)
   check:Hide()
   r.check = check

   local dot = solid(r, "ARTWORK", COL.selectedBorder, 1)
   dot:SetWidth(6)
   dot:SetHeight(6)
   dot:SetPoint("LEFT", r, "LEFT", 9, 0)
   dot:Hide()
   r.dot = dot

   local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   fs:SetHeight(14)
   fs:SetJustifyH("LEFT")
   r.text = fs

   r:EnableMouseWheel(true)
   r:SetScript("OnMouseWheel", function(self, delta) Menu.Scroll(delta) end)
   r:SetScript("OnEnter", function(self)
      local item = self.item
      if item and not item.isTitle and not item.disabled then self.hl:Show() end
      if item then showWidgetTip(self, nil) end
   end)
   r:SetScript("OnLeave", function(self)
      self.hl:Hide()
      Skin.HideTooltip(self)
   end)
   r:SetScript("OnClick", function(self, button)
      local item = self.item
      if not item or item.isTitle or item.disabled then return end
      clickSound(true)
      local fn = item.onClick
      local keep = item.keepOpen
      -- Erst schliessen, dann Rueckruf: der darf gleich ein neues Menue/einen Dialog oeffnen.
      if not keep then Menu.Close() end
      if fn then fn(item) end
      if keep and M.open and M.items then Menu.Refresh() end
   end)

   M.rows[i] = r
   return r
end

-- Sichtbaren Ausschnitt (offset, visible) auf die Zeilen abbilden
local function menuRender()
   if not M.open or not M.items then return end
   local items, vis, off = M.items, M.visible, M.offset
   for i = 1, vis do
      local r = menuRow(i)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", M.frame, "TOPLEFT", MENU_PAD, -(MENU_PAD + (i - 1) * MENU_ROW))
      r:SetWidth(M.rowW)
      menuPaintRow(r, items[off + i])
      r:Show()
   end
   for i = vis + 1, #M.rows do
      M.rows[i].item = nil
      M.rows[i]:Hide()
   end

   if M.barThumb then
      if M.count > vis then
         local trackH = vis * MENU_ROW
         local th = max(12, floor(trackH * vis / M.count))
         local range = M.count - vis
         local y = floor((trackH - th) * (off / range) + 0.5)
         M.barThumb:SetHeight(th)
         M.barThumb:ClearAllPoints()
         M.barThumb:SetPoint("TOPRIGHT", M.frame, "TOPRIGHT", -2, -(MENU_PAD + y))
         M.barThumb:Show()
      else
         M.barThumb:Hide()
      end
   end
end

-- Menue verbergen und Zustand freigeben (onClose genau einmal)
local function menuClose()
   if not M.open then return end
   M.open = false
   local cb = M.opts and M.opts.onClose
   M.items, M.opts, M.anchor = nil, nil, nil
   if M.grab then M.grab:ClearFocus() end
   if M.catcher then M.catcher:Hide() end
   if M.frame then M.frame:Hide() end
   if refocusDialog then refocusDialog() end
   if cb then cb() end
end

-- Rahmen, Fangflaeche und Tastaturfaenger einmalig bauen
local function menuEnsure()
   if M.frame then return end

   -- Unsichtbare Vollbildflaeche unter dem Menue: ein Klick daneben schliesst es.
   local catcher = CreateFrame("Frame", nil, UIParent)
   catcher:SetFrameStrata("FULLSCREEN_DIALOG")
   catcher:SetFrameLevel(60)
   catcher:SetAllPoints(UIParent)
   catcher:EnableMouse(true)
   catcher:EnableMouseWheel(true)
   catcher:SetScript("OnMouseDown", function() menuClose() end)
   catcher:SetScript("OnMouseWheel", function() end)
   catcher:Hide()
   M.catcher = catcher

   local f = CreateFrame("Frame", "TransmogMenuFrame", UIParent)
   f:SetFrameStrata("FULLSCREEN_DIALOG")
   f:SetFrameLevel(62)
   f:EnableMouse(true)
   f:EnableMouseWheel(true)
   f:SetClampedToScreen(true)
   Skin.Backdrop(f, COL.bgSolid, COL.border)
   f:Hide()
   M.frame = f

   if UISpecialFrames then
      local found = false
      for i = 1, #UISpecialFrames do
         if UISpecialFrames[i] == "TransmogMenuFrame" then found = true end
      end
      if not found then tinsert(UISpecialFrames, "TransmogMenuFrame") end
   end

   -- ESC (UISpecialFrames) oder fremdes Hide(): Zustand aufraeumen
   f:SetScript("OnHide", function() menuClose() end)
   f:SetScript("OnMouseWheel", function(self, delta) Menu.Scroll(delta) end)
   f:SetScript("OnUpdate", function(self, elapsed)
      M.acc = M.acc + (elapsed or 0)
      if M.acc < 0.25 then return end
      M.acc = 0
      local a = M.anchor
      -- Verschwindet der Anker (Fenster zu), hat das Menue keinen Sinn mehr.
      if a and a.IsVisible and not a:IsVisible() then menuClose() end
   end)

   -- Rollbalken-Anzeige (nur Daumen), erscheint bei mehr Eintraegen als Zeilen
   local thumb = solid(f, "OVERLAY", COL.accent, 0.8)
   thumb:SetWidth(3)
   thumb:SetHeight(12)
   thumb:Hide()
   M.barThumb = thumb

   -- Eingaben (ESC/Enter) abfangen, damit ESC nicht auch das Hauptfenster schliesst
   M.grab = makeGrabber(f, function() end, function() menuClose() end)
end

-- Menue ist offen?
function Menu.IsOpen()
   return M.open and true or false
end

-- Der Rahmen, an dem das Menue haengt (nil wenn zu)
function Menu.Anchor()
   return M.open and M.anchor or nil
end

-- Menue schliessen (ruft opts.onClose einmal)
function Menu.Close()
   menuClose()
end

-- Eintraege neu zeichnen (nach Aenderung von item.checked u. ae. bei keepOpen)
function Menu.Refresh()
   menuRender()
end

-- Menue um delta Zeilengruppen scrollen (delta aus OnMouseWheel: +1 hoch, -1 runter)
function Menu.Scroll(delta)
   if not M.open or M.count <= M.visible then return end
   local range = M.count - M.visible
   local off = clamp(M.offset - (delta or 0) * MENU_WHEEL, 0, range)
   if off ~= M.offset then
      M.offset = off
      menuRender()
   end
end

-- Menue oeffnen.
-- anchor: Rahmen, unter dem es erscheint (nil = am Mauszeiger).
-- items:  { {text=, checked=, radio=, disabled=, isTitle=, color={r,g,b}, keepOpen=,
--            onClick=function(item), tip=, reason=} ... }
-- opts:   { width=Mindestbreite, maxRows=18, align="LEFT"|"RIGHT", scale=, onClose=fn,
--           matchWidth=false schaltet "mindestens so breit wie der Anker" aus }
function Menu.Open(anchor, items, opts)
   if type(items) ~= "table" then return end
   opts = opts or {}

   -- Nur Tabellen uebernehmen (dieselben Eintraege, damit keepOpen-Aenderungen sichtbar bleiben)
   local list = {}
   for i = 1, #items do
      if type(items[i]) == "table" then list[#list + 1] = items[i] end
   end
   local n = #list
   if n == 0 then return end

   menuEnsure()
   -- Wird das Menue am selben Anker neu aufgebaut (z. B. nach einem keepOpen-Klick),
   -- bleibt die Scrollposition erhalten.
   local keepOffset = 0
   if M.open and M.anchor == anchor and anchor ~= nil then keepOffset = M.offset end
   if M.open then menuClose() end

   -- Skalierung: wie der Anker (Fenster skaliert -> Menue auch), sonst Skin.GetScale()
   local ps = (UIParent:GetEffectiveScale() or 1)
   if ps <= 0 then ps = 1 end
   local scale = tonumber(opts.scale) or scaleRatio(anchor) or Skin.GetScale()
   scale = clamp(scale, 0.5, 2)

   local sw = UIParent:GetWidth() or 0
   local sh = UIParent:GetHeight() or 0
   if sw <= 0 and GetScreenWidth then sw = GetScreenWidth() or 1024 end
   if sh <= 0 and GetScreenHeight then sh = GetScreenHeight() or 768 end

   -- Zeilenzahl: Vorgabe, hoechstens was auf den Bildschirm passt
   local rowsMax = floor(tonumber(opts.maxRows) or MENU_MAX_ROWS)
   if rowsMax < 3 then rowsMax = 3 end
   local fit = floor((sh * 0.92 / scale - 2 * MENU_PAD) / MENU_ROW)
   local vis = min(n, rowsMax, max(3, fit))
   local scrolling = n > vis

   -- Breite: breitester Text + Markenspalte, mindestens Ankerbreite
   local textW = 0
   for i = 1, n do
      local t = list[i].text
      if t then
         local tw = textWidth(t)
         if tw > textW then textW = tw end
      end
   end
   local rowW = textW + 24 + 14
   local minW = tonumber(opts.width) or 0
   if anchor and anchor.GetWidth and opts.matchWidth ~= false then
      local aw = (anchor:GetWidth() or 0) * (scaleRatio(anchor) or 1) / scale
      if aw - 2 * MENU_PAD > minW then minW = aw - 2 * MENU_PAD end
   end
   rowW = clamp(max(rowW, minW, MENU_MIN_W - 2 * MENU_PAD), MENU_MIN_W - 2 * MENU_PAD, MENU_MAX_W)
   local fw = rowW + 2 * MENU_PAD + (scrolling and 6 or 0)
   local fh = vis * MENU_ROW + 2 * MENU_PAD

   -- Ort in UIParent-Einheiten bestimmen
   local wUI, hUI = fw * scale, fh * scale
   local x, yTop
   local l, b, r, t
   if anchor and anchor.GetLeft then
      local al, ab, ar, at = anchor:GetLeft(), anchor:GetBottom(), anchor:GetRight(), anchor:GetTop()
      if al and ab and ar and at then
         local k = (anchor:GetEffectiveScale() or ps) / ps
         l, b, r, t = al * k, ab * k, ar * k, at * k
      end
   end
   if l then
      if opts.align == "RIGHT" then x = r - wUI else x = l end
      yTop = b - 2
      if yTop - hUI < 0 then
         local above = t + 2 + hUI
         if above <= sh then yTop = above else yTop = hUI end
      end
   else
      local cx, cy = 0, 0
      if GetCursorPosition then cx, cy = GetCursorPosition() end
      x, yTop = (cx or 0) / ps, (cy or 0) / ps
   end
   if x > sw - wUI then x = sw - wUI end
   if x < 0 then x = 0 end
   if yTop > sh then yTop = sh end
   if yTop < hUI then yTop = min(hUI, sh) end

   -- Zustand uebernehmen
   M.items, M.opts, M.anchor = list, opts, anchor
   M.count, M.visible, M.rowW = n, vis, rowW
   M.offset = clamp(keepOffset, 0, max(0, n - vis))
   M.acc = 0
   M.open = true

   local f = M.frame
   f:SetScale(scale)
   f:SetWidth(fw)
   f:SetHeight(fh)
   f:ClearAllPoints()
   f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, yTop / scale)

   M.catcher:Show()
   f:Show()
   menuRender()
   if M.grab then M.grab:SetFocus() end
   return f
end

-- ---------------------------------------------------------------------------
-- Dialoge: Prompt und Confirm
-- ---------------------------------------------------------------------------

local DIALOG_HEAD = 28
local DIALOG_PAD = 16

local dialogs = {}          -- [kind] = Dialog-Objekt (lazy gebaut)
local activeDialog = nil    -- nur ein Dialog zugleich

-- Dialog beenden. accepted=true ruft onAccept(text), sonst onCancel().
local function dialogFinish(d, accepted)
   if d.done then return end
   d.done = true
   if activeDialog == d then activeDialog = nil end
   local text
   if d.input then text = trim(d.edit:GetText()) end
   local onAccept, onCancel = d.onAccept, d.onCancel
   d.onAccept, d.onCancel = nil, nil
   d.frame:Hide()
   if accepted then
      if onAccept then onAccept(text) end
   else
      if onCancel then onCancel() end
   end
end

-- Eingabe pruefen und Annehmen-Knopf entsprechend freigeben/sperren
local function dialogRefresh(d)
   if not d.input then
      d.accept:SetEnabledState(true)
      d.err:SetText("")
      return
   end
   local text = trim(d.edit:GetText())
   local ok, why = true, nil
   if text == "" then
      ok = false
   elseif d.validate then
      local good, reason = d.validate(text)
      if not good then ok, why = false, reason end
   end
   d.accept:SetEnabledState(ok, why)
   d.err:SetText((not ok and why) or "")
end

-- Annehmen (Enter oder Knopf), nur wenn freigegeben
local function dialogAccept(d)
   if d.done or d.accept.uiOff then return end
   dialogFinish(d, true)
end

-- Fokus auf das Eingabefeld bzw. den Tastaturfaenger legen
local function dialogFocus(d)
   if d.done then return end
   if d.input then d.edit:SetFocus() else d.grab:SetFocus() end
end

-- Nach einem geschlossenen Menue: offenen Dialog wieder fokussieren
refocusDialog = function()
   if activeDialog then dialogFocus(activeDialog) end
end

-- Dialog-Objekt (Rahmen, Abdunklung, Kopf, Text, Eingabe, Knoepfe) einmalig bauen
local function dialogBuild(kind)
   local d = { kind = kind }
   local name = (kind == "prompt") and "TransmogPromptFrame" or "TransmogConfirmFrame"

   -- Abdunklung: faengt Maus und Mausrad ab (modal)
   local dim = CreateFrame("Frame", nil, UIParent)
   dim:SetFrameStrata("FULLSCREEN_DIALOG")
   dim:SetFrameLevel(20)
   dim:SetAllPoints(UIParent)
   dim:EnableMouse(true)
   dim:EnableMouseWheel(true)
   local shade = solid(dim, "BACKGROUND", COL.shade, COL.shade[4])
   shade:SetAllPoints(dim)
   dim:SetScript("OnMouseWheel", function() end)
   dim:SetScript("OnMouseDown", function() dialogFocus(d) end)
   dim:Hide()
   d.dim = dim

   local f = CreateFrame("Frame", name, UIParent)
   f:SetFrameStrata("FULLSCREEN_DIALOG")
   f:SetFrameLevel(24)
   f:EnableMouse(true)
   f:SetClampedToScreen(true)
   Skin.Backdrop(f, COL.bgSolid, COL.border)
   f:Hide()
   d.frame = f

   if UISpecialFrames then
      local found = false
      for i = 1, #UISpecialFrames do
         if UISpecialFrames[i] == name then found = true end
      end
      if not found then tinsert(UISpecialFrames, name) end
   end

   d.head = Skin.Header(f, "", DIALOG_HEAD)

   local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
   text:SetJustifyH("LEFT")
   text:SetJustifyV("TOP")
   text:SetTextColor(COL.text[1], COL.text[2], COL.text[3])
   d.text = text

   d.edit = Skin.EditBox(f, 200, 26, nil, function() dialogRefresh(d) end)
   d.edit:SetScript("OnEnterPressed", function() dialogAccept(d) end)
   d.edit:SetScript("OnEscapePressed", function() dialogFinish(d, false) end)

   local err = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
   err:SetJustifyH("LEFT")
   err:SetHeight(14)
   err:SetTextColor(COL.red[1], COL.red[2], COL.red[3])
   d.err = err

   d.accept = Skin.Button(f, 110, 26, "", function() dialogAccept(d) end)
   d.cancel = Skin.Button(f, 110, 26, "", function() dialogFinish(d, false) end)

   d.grab = makeGrabber(f, function() dialogAccept(d) end, function() dialogFinish(d, false) end)

   f:SetScript("OnMouseDown", function() dialogFocus(d) end)
   f:SetScript("OnHide", function()
      dim:Hide()
      d.edit:ClearFocus()
      d.grab:ClearFocus()
      -- Fremdes Hide() (z. B. ESC ueber UISpecialFrames, UI aus) zaehlt als Abbrechen.
      if not d.done then
         d.done = true
         if activeDialog == d then activeDialog = nil end
         local onCancel = d.onCancel
         d.onAccept, d.onCancel = nil, nil
         if onCancel then onCancel() end
      end
   end)

   return d
end

-- Dialog gemaess opts zeigen
local function dialogOpen(kind, opts)
   opts = opts or {}
   -- Ein offenes Menue liegt sonst ueber dem Dialog (hoehere Ebene).
   if M.open then menuClose() end
   local d = dialogs[kind]
   if not d then
      d = dialogBuild(kind)
      dialogs[kind] = d
   end

   -- Nur ein Dialog zugleich: den offenen abbrechen
   if activeDialog and activeDialog ~= d then
      dialogFinish(activeDialog, false)
   elseif activeDialog == d then
      dialogFinish(d, false)
   end

   d.done = false
   d.onAccept, d.onCancel = opts.onAccept, opts.onCancel
   d.validate = opts.validate
   d.input = (kind == "prompt") and (opts.input ~= false)
   activeDialog = d

   local f = d.frame
   local ratio = tonumber(opts.scale) or scaleRatio(opts.owner) or scaleRatio(_G.TransmogWindow) or Skin.GetScale()
   f:SetScale(clamp(ratio, 0.6, 1.6))
   local w = clamp(tonumber(opts.width) or 380, 280, 600)
   local inner = w - 2 * DIALOG_PAD
   f:SetWidth(w)

   -- Kopf
   d.head:SetTitle(opts.title or "")
   local stripe = opts.danger and COL.red or COL.accent
   d.head.stripe:SetVertexColor(stripe[1], stripe[2], stripe[3], 1)

   -- Text (Breite vor der Hoehenmessung setzen)
   local y = DIALOG_HEAD + 14
   d.text:ClearAllPoints()
   d.text:SetPoint("TOPLEFT", f, "TOPLEFT", DIALOG_PAD, -y)
   d.text:SetWidth(inner)
   local msg = opts.text
   if msg ~= nil and msg ~= "" then
      d.text:SetText(tostring(msg))
      d.text:Show()
      y = y + max(14, d.text:GetStringHeight() or 14)
   else
      d.text:SetText("")
      d.text:Hide()
   end

   -- Eingabefeld + Fehlerzeile
   if d.input then
      y = y + 12
      d.edit:ClearAllPoints()
      d.edit:SetPoint("TOPLEFT", f, "TOPLEFT", DIALOG_PAD, -y)
      d.edit:SetWidth(inner)
      d.edit:SetHeight(26)
      d.edit:SetMaxLetters(tonumber(opts.maxLetters) or 64)
      d.edit:SetPlaceholder(opts.placeholder or "")
      d.edit:SetText(opts.default and tostring(opts.default) or "")
      d.edit:Show()
      y = y + 26
      d.err:ClearAllPoints()
      d.err:SetPoint("TOPLEFT", f, "TOPLEFT", DIALOG_PAD, -(y + 4))
      d.err:SetWidth(inner)
      d.err:Show()
      y = y + 4 + 14
   else
      d.edit:SetText("")
      d.edit:Hide()
      d.err:SetText("")
      d.err:Hide()
   end

   -- Knoepfe unten rechts. Ohne eigene Beschriftung: Rueckfrage = Ja/Nein,
   -- Eingabedialog = OK/Abbrechen (Blizzard-Globalstrings, daher lokalisiert).
   local yesNo = (kind == "confirm") and opts.accept == nil and opts.cancel == nil
   d.accept:SetLabel(opts.accept or (yesNo and G("YES", "Yes") or G("OKAY", "OK")))
   d.accept:SetTheme(opts.danger and "danger" or "primary")
   d.accept:ClearAllPoints()
   d.accept:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -DIALOG_PAD, 14)
   if opts.cancel == false then
      d.cancel:Hide()
   else
      d.cancel:SetLabel(opts.cancel or (yesNo and G("NO", "No") or G("CANCEL", "Cancel")))
      d.cancel:ClearAllPoints()
      d.cancel:SetPoint("RIGHT", d.accept, "LEFT", -8, 0)
      d.cancel:Show()
   end

   y = y + 16
   f:SetHeight(y + 26 + 14)
   f:ClearAllPoints()
   f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)

   dialogRefresh(d)

   d.dim:Show()
   f:Show()
   f:Raise()
   dialogFocus(d)
   if d.input then d.edit:HighlightText() end
   return f
end

-- Modaler Dialog mit Texteingabe: { title=, text=, input=true, default=, placeholder=,
-- accept=, cancel=, onAccept=fn(text), onCancel=fn, validate=fn(text)->ok,reason,
-- maxLetters=64, width=380, danger=bool, owner=Rahmen (Skalierung), scale= }
function Skin.Prompt(opts)
   return dialogOpen("prompt", opts)
end

-- Modale Rueckfrage: { title=, text=, accept=, cancel= (false = ohne Abbrechen-Knopf),
-- onAccept=fn, onCancel=fn, danger=bool, width=, owner=, scale= }
-- Ohne accept/cancel zeigt sie Ja/Nein (YES/NO), sonst OK/Abbrechen.
function Skin.Confirm(opts)
   return dialogOpen("confirm", opts)
end

-- Offenen Dialog abbrechen (ruft onCancel); true, wenn einer offen war
function Skin.CloseDialog()
   if activeDialog then
      dialogFinish(activeDialog, false)
      return true
   end
   return false
end

-- Ist gerade ein Dialog offen?
function Skin.DialogOpen()
   return activeDialog ~= nil
end
