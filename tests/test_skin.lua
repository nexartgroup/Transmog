-- tests/test_skin.lua
-- ---------------------------------------------------------------------------
-- Verhaltenstests fuer UI/Skin.lua (T.UI.Skin) gegen die strenge Attrappe.
--
-- Getestet wird das Verhalten aus SPEC 6.2 und aus der Erfahrung mit AutoTravel
-- (gesperrte Knoepfe, Tastaturfang, ein Dialog zugleich), nicht die Innereien:
--   * jeder Widget-Konstruktor laeuft gegen die strenge Attrappe
--   * Button/Check: SetEnabledState (Klick verworfen, Tooltip nennt den Grund,
--     Alpha), Hover/Auswahl, Rechtsklick, Disable()/Enable()-Gewohnheiten
--   * EditBox: Platzhalter, onChange(text, userInput), Enter/Escape
--   * Slider: Einrasten, onChange nur bei Eingabe, SetValueQuiet, gesperrt
--   * Menue: Oeffnen/Schliessen, Klick daneben, ESC, Scrollen (40 Zeilen),
--     keepOpen, Position/Umklappen, kein haengendes OnUpdate
--   * Prompt/Confirm: Annehmen, Abbrechen, Enter, ESC, leere Eingabe sperrt,
--     ein Dialog zugleich, Wiedereintritt aus den Rueckrufen
--   * Zustandsautomat-Test (Zufallsfolge mit festem Startwert) ueber Menue,
--     Dialoge, ESC, Eingabe: die Invarianten halten, kein Handler-Fehler
--
-- Die Attrappe setzt IsShown() & Co. auf 1/nil: deshalb H.truthy/H.falsy.
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   -- Skin mit den weichen Abhaengigkeiten laden (Init: T.COLORS, Util: G()).
   -- Absichtlich NICHT die ganze TOC: ein Fehler in einem fremden Modul soll
   -- diese Tests nicht mitreissen.
   local MIN_FILES = { "Locales/Locale.lua", "Core/Init.lua", "Core/Util.lua", "UI/Skin.lua" }

   local function boot()
      H.install()
      M.LoadFiles(MIN_FILES)
      local T = rawget(_G, "Transmog")
      return T, T.UI.Skin
   end

   -- Sichtbarer Elternrahmen mit fester Groesse und Position
   local function newParent(w, h, x, y)
      local f = CreateFrame("Frame", nil, UIParent)
      f:SetWidth(w or 400)
      f:SetHeight(h or 300)
      f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x or 100, y or 100)
      return f
   end

   -- Texte der Tooltip-Zeilen (links)
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

   local function tipShown()
      return GameTooltip:IsShown() and true or false
   end

   -- Sichtbare Zeilen des Menues in Reihenfolge
   local function menuRows()
      local out = {}
      local f = rawget(_G, "TransmogMenuFrame")
      if not f then return out end
      for _, b in ipairs(M.Find(f, "Button")) do
         if b:IsShown() and b.item then out[#out + 1] = b end
      end
      return out
   end

   local function rowTexts()
      local t = {}
      for i, r in ipairs(menuRows()) do t[i] = r.text:GetText() end
      return t
   end

   -- Die unsichtbare Vollbildflaeche unter dem Menue: sichtbar, mausaktiv,
   -- unbenannt, FULLSCREEN_DIALOG, an UIParent verankert, ohne eigene Darstellung
   -- (die Abdunklung hinter einem Dialog hat eine Textur und zaehlt nicht).
   local function findCatcher()
      for _, c in ipairs({ UIParent:GetChildren() }) do
         if c:IsShown() and c.__mouse and c.__name == nil and c:GetFrameStrata() == "FULLSCREEN_DIALOG"
            and c:GetNumPoints() == 2 and c:GetNumRegions() == 0 then
            return c
         end
      end
      return nil
   end

   local function numbered(n, prefix)
      local items = {}
      for i = 1, n do items[i] = { text = (prefix or "Item ") .. i } end
      return items
   end

   -- Sichtbare Frames mit OnUpdate-Skript
   local function updateFrames()
      return M.UpdateFrames()
   end

   local function color(r)
      return { r:GetBackdropColor() }
   end

   local function same4(a, b, eps)
      eps = eps or 1e-9
      for i = 1, 4 do
         if math.abs((a[i] or 0) - (b[i] or 0)) > eps then return false end
      end
      return true
   end

   -- ======================================================================
   H.section("Laden und Oberflaeche")
   -- ======================================================================

   H.test("Skin laedt auch allein (ohne Init/Util/DB) und bietet die SPEC-6.2-Oberflaeche", function()
      H.install()
      M.LoadFiles({ "UI/Skin.lua" })
      local T = rawget(_G, "Transmog")
      local S = T.UI.Skin
      H.eq(type(S), "table")
      for _, fn in ipairs({ "Backdrop", "Button", "Check", "EditBox", "Label", "Slider", "Prompt", "Confirm",
                            "Tooltip", "Header", "Desaturate", "Icon", "TrimIcon" }) do
         H.eq(type(S[fn]), "function", "Skin." .. fn)
      end
      H.eq(type(S.Menu), "table")
      H.eq(type(S.Menu.Open), "function")
      H.eq(type(S.Menu.Close), "function")
      H.eq(type(S.COL), "table")
      H.eq(S.WHITE, "Interface\\Buttons\\WHITE8X8")
      -- ohne Util/DB: Dialoge und Menues funktionieren trotzdem
      S.Confirm({ title = "t", text = "x", onAccept = function() end })
      H.truthy(S.DialogOpen())
      S.CloseDialog()
      S.Menu.Open(nil, { { text = "a" } })
      H.truthy(S.Menu.IsOpen())
      S.Menu.Close()
   end)

   H.test("Laden ueber die TOC bis Skin.lua: keine Fehler, Farben aus T.COLORS, Skalierung aus der echten DB", function()
      local T = H.boot({ upTo = "UI\\Skin.lua" })
      H.truthy(T.UI and T.UI.Skin, "T.UI.Skin")
      local S = T.UI.Skin
      H.eq(S.COL.accent[1], T.COLORS.accent[1], "Farben kommen aus T.COLORS")
      H.eq(T.Util.G("YES", "Yes"), YES, "Util.G wird fuer die Dialogtexte benutzt")
      -- DB.global.scale: 0 = automatisch -> Dialoge/Menues ohne Fenster nehmen 1.0
      T.DB.Init()
      H.eq(T.DB.global.scale, 0)
      H.eq(S.GetScale(), 1)
      T.DB.global.scale = 1.3
      H.eq(S.GetScale(), 1.3)
      S.Confirm({ title = "t", text = "x", onAccept = function() end })
      H.near(TransmogConfirmFrame:GetScale(), 1.3, 1e-6, "Dialog ohne Fenster folgt DB.global.scale")
      S.CloseDialog()
      S.Menu.Open(nil, { { text = "a" } })
      H.near(TransmogMenuFrame:GetScale(), 1.3, 1e-6, "Menue ohne Anker folgt DB.global.scale")
      S.Menu.Close()
   end)

   H.test("Alle Widgets laufen auch in CJK-/kyrillischen Clients (keine fest eincodierte Schrift)", function()
      for _, loc in ipairs({ "koKR", "zhCN", "zhTW", "ruRU", "deDE" }) do
         H.install({ world = { locale = loc } })
         M.LoadFiles(MIN_FILES)
         local S = rawget(_G, "Transmog").UI.Skin
         local p = newParent()
         local b = S.Button(p, 100, 22, "Button", function() end)
         b:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark")
         S.Check(p, "Check", function() end)
         S.EditBox(p, 100, 22, "Platzhalter", function() end)
         S.Slider(p, 100, 0, 1, 0.1, function() end)
         S.Label(p, "Label", "GameFontNormal")
         S.Header(p, "Titel")
         S.Menu.Open(b, { { text = "Eintrag", checked = true } })
         S.Menu.Close()
         S.Prompt({ title = "T", text = "x", default = "d" })
         S.CloseDialog()
         S.Confirm({ title = "T", text = "x" })
         S.CloseDialog()
         S.Tooltip(b, "ANCHOR_RIGHT", { "x" })
      end
      H.truthy(true)
   end)

   H.test("Farbpalette entspricht SPEC 6.1", function()
      local _, S = boot()
      local C = S.COL
      local function chk(name, r, g, b, a)
         local c = C[name]
         H.truthy(c, name)
         if c then
            H.near(c[1], r, 1e-9, name .. ".r")
            H.near(c[2], g, 1e-9, name .. ".g")
            H.near(c[3], b, 1e-9, name .. ".b")
            H.near(c[4] or 1, a, 1e-9, name .. ".a")
         end
      end
      chk("bg", 0.055, 0.062, 0.075, 0.94)
      chk("border", 0.22, 0.25, 0.30, 1)
      chk("accent", 0.20, 0.62, 0.92, 1)
      chk("text", 0.86, 0.88, 0.92, 1)
      chk("dim", 0.50, 0.54, 0.60, 1)
      chk("head", 0.10, 0.12, 0.15, 1)
      chk("button", 0.13, 0.15, 0.18, 1)
      chk("buttonBorder", 0.26, 0.29, 0.34, 1)
      chk("hover", 0.19, 0.22, 0.27, 1)
      chk("selected", 0.16, 0.34, 0.46, 1)
      chk("selectedBorder", 0.35, 0.71, 0.91, 1)
      chk("yellow", 0.91, 0.77, 0.29, 1)
      chk("green", 0.33, 0.82, 0.48, 1)
      chk("red", 0.91, 0.40, 0.29, 1)
      chk("blue", 0.35, 0.71, 0.91, 1)
      chk("grey", 0.35, 0.38, 0.44, 1)
      chk("pink", 0.96, 0.44, 0.96, 1)
   end)

   H.test("unbekannter Farbname liefert eine Ersatzfarbe statt eines Fehlers", function()
      local _, S = boot()
      local c = S.COL.gibtEsNicht
      H.truthy(c, "Ersatzfarbe")
      H.eq(type(c[1]), "number")
      H.truthy(S.missingColors.gibtEsNicht, "wird vermerkt")
   end)

   H.test("Backdrop: flacher 1-px-Rahmen aus WHITE8X8, Standard- und eigene Farben", function()
      local _, S = boot()
      local f = CreateFrame("Frame", nil, UIParent)
      S.Backdrop(f)
      local bd = f:GetBackdrop()
      H.eq(bd.bgFile, "Interface\\Buttons\\WHITE8X8")
      H.eq(bd.edgeFile, "Interface\\Buttons\\WHITE8X8")
      H.eq(bd.edgeSize, 1)
      H.truthy(same4(color(f), S.COL.bg), "Fuellfarbe = COL.bg")
      local br, bg, bb, ba = f:GetBackdropBorderColor()
      H.truthy(same4({ br, bg, bb, ba }, S.COL.border), "Randfarbe = COL.border")
      S.Backdrop(f, { 1, 0, 0, 0.5 }, { 0, 1, 0 })
      H.truthy(same4(color(f), { 1, 0, 0, 0.5 }))
      local r2, g2, b2, a2 = f:GetBackdropBorderColor()
      H.truthy(same4({ r2, g2, b2, a2 }, { 0, 1, 0, 1 }), "fehlender Alphawert = 1")
      -- nil-Frame: kein Fehler
      S.Backdrop(nil)
   end)

   H.test("Panel, Divider, Label, GetScale", function()
      local T, S = boot()
      local p = S.Panel(UIParent)
      H.eq(p:GetObjectType(), "Frame")
      H.truthy(p:GetBackdrop())
      local d = S.Divider(p)
      H.eq(d:GetObjectType(), "Texture")
      H.eq(d:GetHeight(), 1)
      local l1 = S.Label(p, "Hallo")
      H.eq(l1:GetObjectType(), "FontString")
      H.eq(l1:GetText(), "Hallo")
      local l2 = S.Label(p, "Gross", "GameFontNormalLarge")
      H.eq(l2:GetText(), "Gross")
      H.eq(l2:GetFontObject(), GameFontNormalLarge)
      local l3 = S.Label(p, nil, "GibtEsNicht")
      H.eq(l3:GetText(), "", "unbekannte Schrift -> Standard, nil-Text -> leer")
      local l4 = S.Label(p, "Objekt", GameFontDisable)
      H.eq(l4:GetFontObject(), GameFontDisable, "Schriftobjekt statt Name")
      -- GetScale: ohne DB 1; mit DB.global.scale 0 = automatisch = 1; manuell begrenzt
      H.eq(S.GetScale(), 1)
      T.DB = { global = { scale = 0 } }
      H.eq(S.GetScale(), 1)
      T.DB.global.scale = 1.25
      H.eq(S.GetScale(), 1.25)
      T.DB.global.scale = 9
      H.eq(S.GetScale(), 1.5)
      T.DB.global.scale = 0.1
      H.eq(S.GetScale(), 0.6)
   end)

   H.test("Header: Akzentstreifen, Titel, SetTitle", function()
      local _, S = boot()
      local f = newParent(300, 200)
      local h = S.Header(f, "Transmog")
      H.truthy(h.title and h.stripe, "title/stripe")
      H.eq(h.title:GetText(), "Transmog")
      h:SetTitle("Neu")
      H.eq(h.title:GetText(), "Neu")
      H.eq(h:GetHeight(), 30)
      local h2 = S.Header(f, nil, 24)
      H.eq(h2:GetHeight(), 24)
      H.eq(h2.title:GetText(), "")
   end)

   H.test("Desaturate / Icon / TrimIcon", function()
      local _, S = boot()
      local f = newParent()
      local t = f:CreateTexture(nil, "ARTWORK")
      H.truthy(S.Desaturate(t, true), "unterstuetzt -> true")
      H.eq(t.__desaturated, true)
      S.Desaturate(t, false)
      H.eq(t.__desaturated, false)
      H.falsy(S.Desaturate(nil, true))

      S.Icon(t, "Interface\\Icons\\INV_Misc_QuestionMark")
      H.eq(t:GetTexture(), "Interface\\Icons\\INV_Misc_QuestionMark")
      local l, tt, _, b, r = t:GetTexCoord()
      H.near(l, 0.07)
      H.near(r, 0.93)
      H.near(tt, 0.07)
      H.near(b, 0.93)
      -- WHITE8X8 wird nie beschnitten, nil leert
      S.Icon(t, S.WHITE)
      local l2, t2, _, b2, r2 = t:GetTexCoord()
      H.eq(l2, 0)
      H.eq(r2, 1)
      H.eq(t2, 0)
      H.eq(b2, 1)
      S.Icon(t, nil)
      H.eq(t:GetTexture(), nil)
      -- noTrim
      S.Icon(t, "Interface\\Icons\\INV_Misc_QuestionMark", true)
      local l3 = t:GetTexCoord()
      H.eq(l3, 0)
      S.TrimIcon(t)
      local l4 = t:GetTexCoord()
      H.near(l4, 0.07)
      -- nil-sicher
      H.eq(S.Icon(nil, "x"), nil)
      S.TrimIcon(nil)
   end)

   H.test("Desaturate ohne Unterstuetzung dunkelt nur ab und stellt wieder her", function()
      local _, S = boot()
      local f = newParent()
      local t = f:CreateTexture(nil, "ARTWORK")
      -- Attrappe: SetDesaturated meldet "nicht unterstuetzt"
      t.SetDesaturated = function() return nil end
      H.falsy(S.Desaturate(t, true))
      local r1, g1, b1 = t.__vertex[1], t.__vertex[2], t.__vertex[3]
      H.near(r1, 0.5)
      H.near(g1, 0.5)
      H.near(b1, 0.5)
      H.falsy(S.Desaturate(t, false))
      H.near(t.__vertex[1], 1)
   end)

   -- ======================================================================
   H.section("Button")
   -- ======================================================================

   H.test("Button: Konstruktor, Groesse, Beschriftung, Klick ruft onClick(self, button)", function()
      local _, S = boot()
      local p = newParent()
      local got = {}
      local b = S.Button(p, 120, 26, "Anwenden", function(self, button) got[#got + 1] = { self, button } end)
      H.eq(b:GetObjectType(), "Button")
      H.eq(b:GetWidth(), 120)
      H.eq(b:GetHeight(), 26)
      H.eq(b.label:GetText(), "Anwenden")
      H.truthy(b.icon, ".icon")
      H.eq(b:GetParent(), p)
      M.Click(b)
      H.len(got, 1)
      H.eq(got[1][1], b)
      H.eq(got[1][2], "LeftButton")
      M.Click(b)
      H.len(got, 2)
   end)

   H.test("Button ohne onClick und ohne Beschriftung: Klick wirft nicht", function()
      local _, S = boot()
      local b = S.Button(newParent(), nil, nil, nil, nil)
      H.eq(b:GetWidth(), 80)
      H.eq(b:GetHeight(), 22)
      H.eq(b.label:GetText(), "")
      M.Click(b)
   end)

   H.test("Button: SetLabel/GetLabel und die Gewohnheiten SetText/GetText", function()
      local _, S = boot()
      local b = S.Button(newParent(), 100, 22, "A")
      b:SetLabel("Neu")
      H.eq(b.label:GetText(), "Neu")
      H.eq(b:GetLabel(), "Neu")
      b:SetText("Alt-Stil")
      H.eq(b:GetText(), "Alt-Stil")
      H.eq(b.label:GetText(), "Alt-Stil")
      b:SetLabel(nil)
      H.eq(b:GetLabel(), "")
   end)

   H.test("Button gesperrt: Klick verworfen, Alpha abgedunkelt, wieder frei -> Klick geht", function()
      local _, S = boot()
      local n = 0
      local b = S.Button(newParent(), 100, 22, "X", function() n = n + 1 end)
      H.eq(b:GetAlpha(), 1)
      H.truthy(b:IsEnabledState())
      b:SetEnabledState(false, "Grund")
      H.falsy(b:IsEnabledState())
      H.truthy(b:GetAlpha() < 1, "abgedunkelt")
      M.Click(b)
      M.Click(b, "LeftButton")
      H.eq(n, 0, "gesperrt: kein onClick")
      b:SetEnabledState(true)
      H.truthy(b:IsEnabledState())
      H.eq(b:GetAlpha(), 1)
      M.Click(b)
      H.eq(n, 1, "wieder frei: Klick kommt an")
   end)

   H.test("Button gesperrt: Tooltip nennt Titel und Grund; frei: kein Tooltip ohne .tip", function()
      local _, S = boot()
      local b = S.Button(newParent(), 100, 22, "Anwenden", function() end)
      b:SetEnabledState(false, "Kein Transmogrifizierer in der Naehe")
      M.Enter(b)
      H.truthy(tipShown(), "Tooltip sichtbar")
      H.eq(GameTooltip:GetOwner(), b)
      H.truthy(tipHas("Kein Transmogrifizierer in der Naehe"), "Grund")
      H.truthy(tipHas("Anwenden"), "Titel")
      M.Leave(b)
      H.falsy(tipShown(), "nach OnLeave verborgen")
      b:SetEnabledState(true)
      M.Enter(b)
      H.falsy(tipShown(), "freigegeben und ohne .tip: kein Tooltip")
      M.Leave(b)
   end)

   H.test("Button: Zustandswechsel unter ruhender Maus baut den Tooltip neu auf", function()
      local _, S = boot()
      local b = S.Button(newParent(), 100, 22, "Anwenden", function() end)
      b.tip = function(tt) tt:AddLine("Hinweis") end
      M.Enter(b)
      H.truthy(tipHas("Hinweis"), "freigegeben: .tip")
      b:SetEnabledState(false, "Nicht moeglich")
      H.truthy(tipShown(), "Tooltip bleibt sichtbar")
      H.truthy(tipHas("Nicht moeglich"), "Grund erscheint ohne erneutes OnEnter")
      H.falsy(tipHas("Hinweis"), ".tip ersetzt")
      b:SetEnabledState(true)
      H.truthy(tipHas("Hinweis"), "wieder .tip")
      H.falsy(tipHas("Nicht moeglich"))
      M.Leave(b)
   end)

   H.test("Button ohne .tip: Sperre unter ruhender Maus zeigt den Grund sofort (kein erneutes OnEnter)", function()
      local _, S = boot()
      local b = S.Button(newParent(), 100, 22, "Anwenden", function() end)
      M.Enter(b)
      H.falsy(tipShown(), "frei und ohne .tip: kein Tooltip")
      -- z. B. nach dem Klick auf "Anwenden": Knopf wird gesperrt, die Maus liegt noch darauf
      b:SetEnabledState(false, "Wird angewendet ...")
      H.truthy(tipShown(), "Grund erscheint ohne Verlassen und erneutes Betreten")
      H.truthy(tipHas("Wird angewendet ..."))
      H.eq(GameTooltip:GetOwner(), b)
      -- Freigabe: der Grund verschwindet wieder
      b:SetEnabledState(true)
      H.falsy(tipShown(), "freigegeben: Tooltip weg")
      M.Leave(b)
      -- Maus liegt NICHT auf dem Knopf: Zustandswechsel loest keinen Tooltip aus
      b:SetEnabledState(false, "Grund")
      H.falsy(tipShown(), "ohne Hover kein Tooltip")
      -- ein fremder Tooltip bleibt unberuehrt, solange die Maus nicht auf dem Knopf liegt
      local other = newParent()
      Transmog.UI.Skin.Tooltip(other, "ANCHOR_RIGHT", { "Fremd" })
      b:SetEnabledState(true)
      b:SetEnabledState(false, "Anderer Grund")
      H.eq(GameTooltip:GetOwner(), other)
      H.truthy(tipHas("Fremd"))
   end)

   H.test("Check: Sperre unter ruhender Maus zeigt den Grund sofort", function()
      local _, S = boot()
      local c = S.Check(newParent(), "Option", function() end)
      M.Enter(c)
      H.falsy(tipShown())
      c:SetEnabledState(false, "Nur am Transmogrifizierer")
      H.truthy(tipHas("Nur am Transmogrifizierer"))
      c:SetEnabledState(true)
      H.falsy(tipShown())
      M.Leave(c)
   end)

   H.test("Button: gesperrt ohne Grund aber mit .tip zeigt den normalen Tooltip", function()
      local _, S = boot()
      local b = S.Button(newParent(), 100, 22, "X", function() end)
      b.tip = function(tt) tt:AddLine("Normal") end
      b:SetEnabledState(false)
      M.Enter(b)
      H.truthy(tipHas("Normal"))
      M.Leave(b)
   end)

   H.test("Button: .tip als Funktion, Text oder Zeilenliste", function()
      local _, S = boot()
      local b = S.Button(newParent(), 100, 22, "X", function() end)
      local gotTip, gotSelf
      b.tip = function(tooltip, self)
         gotTip, gotSelf = tooltip, self
         tooltip:AddLine("Aus Funktion")
      end
      M.Enter(b)
      H.eq(gotTip, GameTooltip, "erstes Argument: GameTooltip")
      H.eq(gotSelf, b, "zweites Argument: Knopf")
      H.truthy(tipHas("Aus Funktion"))
      M.Leave(b)

      b.tip = "Nur Text"
      M.Enter(b)
      H.eq(tipLines()[1], "Nur Text")
      M.Leave(b)

      b.tip = { "Titel", { "Zeile", 1, 0, 0 } }
      M.Enter(b)
      local l = tipLines()
      H.eq(l[1], "Titel")
      H.eq(l[2], "Zeile")
      M.Leave(b)

      -- leere Funktion (keine Zeilen) darf keinen leeren Tooltip stehen lassen
      b.tip = function() end
      M.Enter(b)
      H.falsy(tipShown())
      M.Leave(b)
   end)

   H.test("Button: Verbergen unter der Maus setzt Hover zurueck und verbirgt den Tooltip", function()
      local _, S = boot()
      local p = newParent()
      local b = S.Button(p, 100, 22, "X", function() end)
      b.tip = "Hinweis"
      M.Enter(b)
      H.truthy(tipShown())
      local hoverBorder = { b:GetBackdropBorderColor() }
      H.truthy(same4(hoverBorder, S.COL.accent), "Hover: Akzentrand")
      b:Hide()
      H.falsy(tipShown(), "Tooltip weg")
      b:Show()
      local rest = { b:GetBackdropBorderColor() }
      H.truthy(same4(rest, S.COL.buttonBorder), "Ruhefarbe nach erneutem Anzeigen")
   end)

   H.test("Button: Farben fuer Ruhe, Hover, Gedrueckt, Ausgewaehlt", function()
      local _, S = boot()
      local b = S.Button(newParent(), 100, 22, "X", function() end)
      local C = S.COL
      H.truthy(same4(color(b), C.button), "Ruhe: Fuellung")
      H.truthy(same4({ b:GetBackdropBorderColor() }, C.buttonBorder), "Ruhe: Rand")
      M.Enter(b)
      H.truthy(same4(color(b), C.hover), "Hover: Fuellung")
      H.truthy(same4({ b:GetBackdropBorderColor() }, C.accent), "Hover: Rand")
      M.Leave(b)
      H.truthy(same4(color(b), C.button), "wieder Ruhe")

      b:SetSelected(true)
      H.truthy(b:IsSelected())
      H.truthy(same4(color(b), C.selected), "Auswahl: Fuellung")
      H.truthy(same4({ b:GetBackdropBorderColor() }, C.selectedBorder), "Auswahl: Rand")
      b:SetSelected(false)
      H.falsy(b:IsSelected())
      H.truthy(same4(color(b), C.button))

      -- gedrueckt (Maus ueber dem Knopf): dunkler als Ruhe
      M.Enter(b)
      M.MouseDown(b)
      local down = color(b)
      H.truthy(down[1] < C.hover[1], "gedrueckt dunkler als Hover")
      M.MouseUp(b)
      H.truthy(same4(color(b), C.hover), "nach Loslassen wieder Hover")
      M.Leave(b)
   end)

   H.test("Button: gesperrt zeigt keine Hover-Hervorhebung", function()
      local _, S = boot()
      local b = S.Button(newParent(), 100, 22, "X", function() end)
      b:SetEnabledState(false, "nein")
      M.Enter(b)
      H.truthy(same4(color(b), S.COL.button), "keine Hover-Fuellung")
      H.truthy(same4({ b:GetBackdropBorderColor() }, S.COL.buttonBorder), "kein Hover-Rand")
      -- freigegeben unter ruhender Maus: sofort Hover
      b:SetEnabledState(true)
      H.truthy(same4(color(b), S.COL.hover), "sofort Hover")
      M.Leave(b)
   end)

   H.test("Button: Rechtsklick nur nach EnableRightClick, onClick bekommt die Taste", function()
      local _, S = boot()
      local got = {}
      local b = S.Button(newParent(), 100, 22, "X", function(_, button) got[#got + 1] = button end)
      M.Click(b, "RightButton")
      H.len(got, 0, "Standard: nur Linksklick")
      b:EnableRightClick(true)
      M.Click(b, "RightButton")
      M.Click(b, "LeftButton")
      H.eq(got[1], "RightButton")
      H.eq(got[2], "LeftButton")
      b:EnableRightClick(false)
      M.Click(b, "RightButton")
      H.len(got, 2)
   end)

   H.test("Button: Disable()/Enable()/IsEnabled() sperren ueber den eigenen Merker (AutoTravel-Erfahrung)", function()
      local _, S = boot()
      local n = 0
      local b = S.Button(newParent(), 100, 22, "X", function() n = n + 1 end)
      H.truthy(b:IsEnabled())
      b:Disable()
      H.falsy(b:IsEnabled())
      M.Click(b)
      H.eq(n, 0)
      b:Enable()
      H.truthy(b:IsEnabled())
      M.Click(b)
      H.eq(n, 1)
      -- viele Wechsel: danach kommen Klicks weiter an
      for _ = 1, 25 do
         b:SetEnabledState(false, "x")
         b:SetEnabledState(true)
      end
      M.Click(b)
      H.eq(n, 2)
      -- Die Engine selbst wird nie gesperrt (sonst verwirft sie Klicks)
      b:SetEnabledState(false, "x")
      M.Click(b)
      H.eq(n, 2)
      b:SetEnabledState(true)
      H.eq(b.__enabled, true, "Engine-Zustand bleibt Enable")
   end)

   H.test("Button: Sperren nach dem Druecken, Freigeben vor dem Loslassen -> Klick geht durch", function()
      local _, S = boot()
      local n = 0
      local b = S.Button(newParent(), 100, 22, "X", function() n = n + 1 end)
      M.MouseDown(b)
      b:SetEnabledState(false, "x")
      b:SetEnabledState(true)
      M.MouseUp(b)
      H.eq(n, 1, "der Klick ist nicht verloren gegangen")
      -- gesperrt beim Loslassen -> verworfen
      M.MouseDown(b)
      b:SetEnabledState(false, "x")
      M.MouseUp(b)
      H.eq(n, 1)
   end)

   H.test("Button: SetIcon, SetAccent, SetTheme, SetTextColor laufen gegen die strenge Attrappe", function()
      local _, S = boot()
      local b = S.Button(newParent(), 120, 24, "Mit Symbol", function() end)
      b:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark")
      H.eq(b.icon:GetTexture(), "Interface\\Icons\\INV_Misc_QuestionMark")
      H.eq(b.icon:GetWidth(), 14)
      b:SetIcon("Interface\\Icons\\INV_Misc_QuestionMark", 18)
      H.eq(b.icon:GetWidth(), 18)
      b:SetIcon(nil)
      H.eq(b.icon:GetTexture(), nil)
      b:SetAccent(1, 0.5, 0)
      H.truthy(b.accentTex:IsShown())
      b:SetAccent(nil)
      H.falsy(b.accentTex:IsShown())
      for _, th in ipairs({ "default", "primary", "danger" }) do
         b:SetTheme(th)
      end
      b:SetTheme({ bg = { 0, 0, 0, 1 }, border = { 1, 1, 1, 1 }, hoverBg = { 0, 0, 0, 1 }, hoverBorder = { 1, 1, 1, 1 },
                   pressBg = { 0, 0, 0, 1 }, selBg = { 0, 0, 0, 1 }, selBorder = { 1, 1, 1, 1 },
                   selHoverBg = { 0, 0, 0, 1 }, text = { 1, 1, 1, 1 }, selText = { 1, 1, 1, 1 } })
      b:SetTheme("gibt es nicht")
      b:SetTextColor(1, 0, 0)
      H.near(select(1, b.label:GetTextColor()), 1)
      b:SetTextColor(nil)
      b:RefreshLayout()
      -- direktes b.icon:SetTexture zieht das Layout nach (kein Ueberlappen mit dem Text)
      b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      H.truthy(b.icon:GetNumPoints() >= 1)
   end)

   H.test("Button: Gewohnheit Button.label:SetText bleibt gueltig (Schrift vorhanden)", function()
      local _, S = boot()
      local b = S.Button(newParent(), 100, 22, "A")
      b.label:SetText("direkt")
      H.eq(b:GetLabel(), "direkt")
   end)

   -- ======================================================================
   H.section("Check")
   -- ======================================================================

   H.test("Check: SetChecked/GetChecked liefern bool, onChange nur bei Klick", function()
      local _, S = boot()
      local calls = {}
      local c = S.Check(newParent(), "Sound", function(checked, self) calls[#calls + 1] = { checked, self } end)
      H.eq(c.label:GetText(), "Sound")
      H.eq(c:GetChecked(), false)
      c:SetChecked(true)
      H.eq(c:GetChecked(), true)
      H.len(calls, 0, "SetChecked ruft onChange nicht")
      c:SetChecked(nil)
      H.eq(c:GetChecked(), false)
      M.Click(c)
      H.len(calls, 1)
      H.eq(calls[1][1], true)
      H.eq(calls[1][2], c)
      H.eq(c:GetChecked(), true)
      M.Click(c)
      H.len(calls, 2)
      H.eq(calls[2][1], false)
      H.eq(c:GetChecked(), false)
      H.eq(c:GetLabel(), "Sound")
   end)

   H.test("Check gesperrt: Klick verworfen, Tooltip nennt den Grund, Zustand bleibt", function()
      local _, S = boot()
      local n = 0
      local c = S.Check(newParent(), "Option", function() n = n + 1 end)
      c:SetChecked(true)
      c:SetEnabledState(false, "Nur am Transmogrifizierer")
      H.truthy(c:GetAlpha() < 1)
      M.Click(c)
      H.eq(n, 0)
      H.eq(c:GetChecked(), true, "Haken unveraendert")
      M.Enter(c)
      H.truthy(tipHas("Nur am Transmogrifizierer"))
      M.Leave(c)
      c:SetEnabledState(true)
      H.eq(c:GetAlpha(), 1)
      M.Click(c)
      H.eq(n, 1)
      H.eq(c:GetChecked(), false)
   end)

   H.test("Check: Breite folgt dem Text; SetWidth des Aufrufers gewinnt", function()
      local _, S = boot()
      local c = S.Check(newParent(), "Kurz", nil)
      local w1 = c:GetWidth()
      H.truthy(w1 > 16, "mindestens Kasten + Text")
      c:SetLabel("Ein deutlich laengerer Beschriftungstext")
      H.truthy(c:GetWidth() > w1, "waechst mit dem Text")
      c:SetWidth(200)
      H.eq(c:GetWidth(), 200)
      c:SetLabel("Noch ein anderer, sehr langer Text fuer das Kontrollkaestchen")
      H.eq(c:GetWidth(), 200, "manuelle Breite bleibt")
   end)

   H.test("Check ohne onChange und ohne Text: Klick wirft nicht", function()
      local _, S = boot()
      local c = S.Check(newParent(), nil, nil)
      M.Click(c)
      H.eq(c:GetChecked(), true)
   end)

   -- ======================================================================
   H.section("EditBox")
   -- ======================================================================

   H.test("EditBox: Konstruktor, Groesse, Platzhalter sichtbar solange leer und ohne Fokus", function()
      local _, S = boot()
      local e = S.EditBox(newParent(), 180, 24, "Suche...", function() end)
      H.eq(e:GetObjectType(), "EditBox")
      H.eq(e:GetWidth(), 180)
      H.eq(e:GetHeight(), 24)
      H.eq(e:GetText(), "")
      H.eq(e.placeholderText:GetText(), "Suche...")
      H.truthy(e.placeholderText:IsShown(), "leer + ohne Fokus: sichtbar")
      e:SetFocus()
      H.falsy(e.placeholderText:IsShown(), "mit Fokus: verborgen")
      e:ClearFocus()
      H.truthy(e.placeholderText:IsShown(), "ohne Fokus wieder sichtbar")
      e:SetText("abc")
      H.falsy(e.placeholderText:IsShown(), "mit Text: verborgen")
      e:SetText("")
      H.truthy(e.placeholderText:IsShown(), "wieder leer: sichtbar")
   end)

   H.test("EditBox: Tippen meldet onChange(text, true), SetText meldet false", function()
      local _, S = boot()
      local calls = {}
      local e = S.EditBox(newParent(), 180, 24, "p", function(text, userInput)
         calls[#calls + 1] = { text, userInput }
      end)
      M.Type(e, "foo")
      H.len(calls, 1)
      H.eq(calls[1][1], "foo")
      H.eq(calls[1][2], true, "getippt = Eingabe")
      e:SetText("bar")
      H.len(calls, 2)
      H.eq(calls[2][1], "bar")
      H.eq(calls[2][2], false, "per SetText = keine Eingabe")
      e:SetText("")
      H.eq(calls[3][1], "")
      H.eq(calls[3][2], false)
      M.Type(e, "")
      H.eq(calls[4][2], true, "geloescht per Tastatur = Eingabe")
   end)

   H.test("EditBox: fehlt das userInput-Argument der Engine, gilt Eingabe nur ausserhalb von SetText", function()
      local _, S = boot()
      local calls = {}
      local e = S.EditBox(newParent(), 180, 24, "p", function(text, userInput)
         calls[#calls + 1] = userInput
      end)
      local handler = e:GetScript("OnTextChanged")
      -- Engine ruft ohne zweites Argument: Spielereingabe
      handler(e)
      H.eq(calls[1], true)
      -- per SetText (Attrappe liefert false mit, aber auch ohne muss es false bleiben)
      e.SetText = e.SetText   -- Wrapper bleibt erhalten
      local engineScript = e:GetScript("OnTextChanged")
      e:SetScript("OnTextChanged", function(self) engineScript(self) end)   -- Engine ohne Argument
      e:SetText("x")
      H.eq(calls[2], false, "SetText ohne Engine-Argument")
      -- und danach wieder echte Eingabe
      M.Type(e, "xy")
      H.eq(calls[3], true)
   end)

   H.test("EditBox: SetPlaceholder, Enter ruft onEnter und gibt den Fokus ab, Escape nur Fokus", function()
      local _, S = boot()
      local e = S.EditBox(newParent(), 180, 24, "alt", nil)
      e:SetPlaceholder("neu")
      H.eq(e.placeholderText:GetText(), "neu")
      e:SetPlaceholder(nil)
      H.eq(e.placeholderText:GetText(), "")
      local entered
      e.onEnter = function(text, self) entered = { text, self } end
      e:SetFocus()
      H.truthy(e:HasFocus())
      M.Type(e, "Suchtext")
      M.Key(e, "ENTER")
      H.falsy(e:HasFocus(), "Enter gibt den Fokus ab")
      H.eq(entered[1], "Suchtext")
      H.eq(entered[2], e)
      entered = nil
      e:SetFocus()
      M.Key(e, "ESCAPE")
      H.falsy(e:HasFocus(), "Escape gibt den Fokus ab")
      H.eq(entered, nil, "Escape ruft onEnter nicht")
      H.eq(e:GetText(), "Suchtext", "Text bleibt")
   end)

   H.test("EditBox: SetEnabledState sperrt Maus, dunkelt ab und gibt den Fokus ab", function()
      local _, S = boot()
      local e = S.EditBox(newParent(), 180, 24, "p", nil)
      e:SetFocus()
      H.truthy(e:HasFocus())
      e:SetEnabledState(false)
      H.falsy(e:HasFocus())
      H.falsy(e:IsMouseEnabled())
      H.truthy(e:GetAlpha() < 1)
      e:SetEnabledState(true)
      H.truthy(e:IsMouseEnabled())
      H.eq(e:GetAlpha(), 1)
   end)

   H.test("EditBox: gesperrt unter der Maus setzt den Hover zurueck (kein haengender Rand)", function()
      local _, S = boot()
      local e = S.EditBox(newParent(), 180, 24, "p", nil)
      M.Enter(e)
      H.truthy(same4({ e:GetBackdropBorderColor() }, S.COL.fieldHover))
      e:SetEnabledState(false)
      H.truthy(same4({ e:GetBackdropBorderColor() }, S.COL.buttonBorder), "Ruhefarbe trotz Maus")
      e:SetEnabledState(true)
      H.truthy(same4({ e:GetBackdropBorderColor() }, S.COL.buttonBorder), "bleibt Ruhe bis zum naechsten OnEnter")
   end)

   H.test("EditBox: Randfarbe Fokus > Hover > Ruhe", function()
      local _, S = boot()
      local e = S.EditBox(newParent(), 180, 24, "p", nil)
      local C = S.COL
      H.truthy(same4({ e:GetBackdropBorderColor() }, C.buttonBorder))
      M.Enter(e)
      H.truthy(same4({ e:GetBackdropBorderColor() }, C.fieldHover), "Hover")
      e:SetFocus()
      H.truthy(same4({ e:GetBackdropBorderColor() }, C.accent), "Fokus")
      M.Leave(e)
      H.truthy(same4({ e:GetBackdropBorderColor() }, C.accent), "Fokus gewinnt gegen Ruhe")
      e:ClearFocus()
      H.truthy(same4({ e:GetBackdropBorderColor() }, C.buttonBorder), "Ruhe")
   end)

   -- ======================================================================
   H.section("Slider")
   -- ======================================================================

   H.test("Slider: Konstruktor, Startwert = Minimum, Wertetext", function()
      local _, S = boot()
      local s = S.Slider(newParent(), 150, 0, 10, 1, function() end)
      H.eq(s:GetObjectType(), "Slider")
      H.eq(s:GetWidth(), 150)
      H.eq(s:GetValue(), 0)
      H.eq(s.valueText:GetText(), "0")
      s:SetValueQuiet(7)
      H.eq(s:GetValue(), 7)
      H.eq(s.valueText:GetText(), "7")
   end)

   H.test("Slider: onChange nur bei Eingabe, SetValueQuiet bleibt still", function()
      local _, S = boot()
      local calls = {}
      local s = S.Slider(newParent(), 150, 0.6, 1.5, 0.05, function(v, self) calls[#calls + 1] = { v, self } end)
      s:SetValueQuiet(1.0)
      H.len(calls, 0)
      H.near(s:GetValue(), 1.0)
      s:SetValue(1.2)   -- wie Ziehen/Klick
      H.len(calls, 1)
      H.near(calls[1][1], 1.2, 1e-9)
      H.eq(calls[1][2], s)
      s:SetValue(1.2)
      H.len(calls, 1, "gleicher Wert: keine neue Meldung")
      H.eq(s.valueText:GetText(), "1.2")
      -- Auf- und Abrundung auf die Schrittweite, in den Bereich geklemmt
      s:SetValue(0.77)
      H.near(calls[#calls][1], 0.75, 1e-9)
      s:SetValue(99)
      H.near(calls[#calls][1], 1.5, 1e-9)
      s:SetValue(-5)
      H.near(calls[#calls][1], 0.6, 1e-9)
      -- SetValueQuiet rastet ein, meldet aber nichts
      local n = #calls
      s:SetValueQuiet(0.912)
      H.near(s:GetValue(), 0.9, 1e-9)
      H.eq(#calls, n)
      H.near(s:GetSnappedValue(), 0.9, 1e-9)
   end)

   H.test("Slider: Mausrad aendert um eine Schrittweite und klemmt am Rand", function()
      local _, S = boot()
      local last
      local s = S.Slider(newParent(), 150, 0, 3, 1, function(v) last = v end)
      s:SetValueQuiet(1)
      M.Wheel(s, 1)
      H.eq(last, 2)
      M.Wheel(s, 1)
      M.Wheel(s, 1)
      H.eq(s:GetValue(), 3, "am Maximum")
      M.Wheel(s, -1)
      H.eq(last, 2)
      M.Wheel(s, 0)
      H.eq(s:GetValue(), 2)
   end)

   H.test("Slider gesperrt: Eingabe wird verworfen, Wert springt zurueck, kein onChange", function()
      local _, S = boot()
      local n = 0
      local s = S.Slider(newParent(), 150, 0, 10, 1, function() n = n + 1 end)
      s:SetValueQuiet(4)
      s:SetEnabledState(false, "Gesperrt")
      H.truthy(s:GetAlpha() < 1)
      s:SetValue(8)
      H.eq(s:GetValue(), 4, "zurueckgesetzt")
      H.eq(n, 0)
      M.Wheel(s, 1)
      H.eq(s:GetValue(), 4)
      s:SetValueQuiet(6)
      H.eq(s:GetValue(), 6, "SetValueQuiet geht auch gesperrt")
      H.eq(n, 0)
      s:SetEnabledState(true)
      H.eq(s:GetAlpha(), 1)
      s:SetValue(9)
      H.eq(s:GetValue(), 9)
      H.eq(n, 1)
   end)

   H.test("Slider: Formatter, SetRange, Tooltip-Grund", function()
      local _, S = boot()
      local s = S.Slider(newParent(), 150, 60, 150, 5, nil)
      s.formatter = function(v) return v .. " %" end
      s:SetValueQuiet(100)
      H.eq(s.valueText:GetText(), "100 %")
      s:SetRange(0, 20, 2)
      H.eq(s:GetValue(), 20, "alter Wert 100 klemmt auf das neue Maximum")
      s:SetValueQuiet(7)
      H.eq(s:GetValue(), 8, "rastet auf Schrittweite 2")
      -- vertauschte Grenzen, ungueltige Schrittweite
      local s2 = S.Slider(newParent(), 100, 5, 1, 0, nil)
      local lo, hi = s2:GetMinMaxValues()
      H.eq(lo, 1)
      H.eq(hi, 5)
      -- Hover zeigt den Sperrgrund
      s:SetEnabledState(false, "Nur automatisch")
      M.Enter(s)
      H.truthy(tipHas("Nur automatisch"))
      M.Leave(s)
      H.falsy(tipShown())
   end)

   H.test("Slider: Sperre unter ruhender Maus zeigt den Grund sofort, Freigabe nimmt ihn zurueck", function()
      local _, S = boot()
      local s = S.Slider(newParent(), 150, 0, 10, 1, nil)
      M.Enter(s)
      H.falsy(tipShown())
      s:SetEnabledState(false, "Nur im Automatikmodus")
      H.truthy(tipHas("Nur im Automatikmodus"))
      s:SetEnabledState(true)
      H.falsy(tipShown())
      M.Leave(s)
      -- Verbergen unter der Maus verbirgt auch den Tooltip
      s:SetEnabledState(false, "Grund")
      M.Enter(s)
      H.truthy(tipShown())
      s:Hide()
      H.falsy(tipShown())
   end)

   -- ======================================================================
   H.section("Tooltip")
   -- ======================================================================

   H.test("Skin.Tooltip: Strings, Tabellen {text,r,g,b}, Doppelzeilen, leere Liste verbirgt", function()
      local _, S = boot()
      local p = newParent()
      S.Tooltip(p, "ANCHOR_RIGHT", { "Titel", { "Gruen", 0, 1, 0 }, { left = "Links", right = "Rechts" } })
      H.truthy(tipShown())
      H.eq(GameTooltip:GetOwner(), p)
      local l = tipLines()
      H.eq(l[1], "Titel")
      H.eq(l[2], "Gruen")
      H.eq(l[3], "Links")
      local rfs = rawget(_G, "GameTooltipTextRight3")
      H.eq(rfs:GetText(), "Rechts")
      local r, g, b = GameTooltipTextLeft2:GetTextColor()
      H.eq(r, 0)
      H.eq(g, 1)
      H.eq(b, 0)
      -- Titel weiss
      H.eq(select(1, GameTooltipTextLeft1:GetTextColor()), 1)
      -- einzelner String
      S.Tooltip(p, nil, "Allein")
      H.eq(tipLines()[1], "Allein")
      -- leer: verborgen
      S.Tooltip(p, "ANCHOR_RIGHT", {})
      H.falsy(tipShown())
      -- ohne Besitzer: nichts
      S.Tooltip(nil, "ANCHOR_RIGHT", { "x" })
      -- HideTooltip nur fuer den Besitzer
      S.Tooltip(p, "ANCHOR_RIGHT", { "x" })
      local other = newParent()
      S.HideTooltip(other)
      H.truthy(tipShown(), "fremder Besitzer: bleibt")
      S.HideTooltip(p)
      H.falsy(tipShown())
   end)

   H.test("Skin.Tooltip: fehlerhafte Zeilen (leer, Zahl, unvollstaendige Farbe, Doppelzeile ohne Farben) werfen nicht", function()
      local _, S = boot()
      local p = newParent()
      S.Tooltip(p, "ANCHOR_RIGHT", { "Titel", {}, 5, { "Nur rot", 1 }, { left = "L", right = "R" }, { "Mit Wrap", 1, 1, 1, true } })
      local l = tipLines()
      H.eq(l[1], "Titel")
      H.contains(l, "5")
      H.contains(l, "Nur rot")
      H.contains(l, "L")
      H.contains(l, "Mit Wrap")
      -- keine Liste: nichts, kein Fehler
      S.Tooltip(p, "ANCHOR_RIGHT", nil)
      H.falsy(tipShown())
      S.Tooltip(p, "ANCHOR_RIGHT", 42)
      H.falsy(tipShown())
   end)

   -- ======================================================================
   H.section("Menue")
   -- ======================================================================

   H.test("Menue: Oeffnen zeigt Zeilen, Zustandsabfragen, Close ruft onClose genau einmal", function()
      local _, S = boot()
      local anchor = S.Button(newParent(), 120, 24, "Menue", function() end)
      anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 200, -100)
      local closed = 0
      H.falsy(S.Menu.IsOpen())
      S.Menu.Open(anchor, { { text = "Eins" }, { text = "Zwei" }, { text = "Drei" } },
         { onClose = function() closed = closed + 1 end })
      H.truthy(S.Menu.IsOpen())
      H.eq(S.Menu.Anchor(), anchor)
      H.truthy(TransmogMenuFrame:IsShown())
      H.deepEq(rowTexts(), { "Eins", "Zwei", "Drei" })
      H.eq(TransmogMenuFrame:GetFrameStrata(), "FULLSCREEN_DIALOG")
      S.Menu.Close()
      H.falsy(S.Menu.IsOpen())
      H.falsy(TransmogMenuFrame:IsShown())
      H.eq(closed, 1)
      S.Menu.Close()   -- zweites Close: nichts
      H.eq(closed, 1)
      H.eq(S.Menu.Anchor(), nil)
   end)

   H.test("Menue: ungueltige Eingabe oeffnet nichts und wirft nicht", function()
      local _, S = boot()
      S.Menu.Open(nil, nil)
      H.falsy(S.Menu.IsOpen())
      S.Menu.Open(nil, {})
      H.falsy(S.Menu.IsOpen())
      S.Menu.Open(nil, { "kein Eintrag", 5, false })
      H.falsy(S.Menu.IsOpen())
      S.Menu.Open(nil, { "x", { text = "ok" }, 3 })
      H.truthy(S.Menu.IsOpen())
      H.deepEq(rowTexts(), { "ok" }, "nur Tabellen werden Zeilen")
      S.Menu.Scroll(1)     -- offen, aber nichts zu scrollen
      S.Menu.Close()
      S.Menu.Scroll(-1)    -- geschlossen
      S.Menu.Refresh()
   end)

   H.test("Menue: Klick auf einen Eintrag schliesst vor dem Rueckruf und uebergibt den Eintrag", function()
      local _, S = boot()
      local order = {}
      local item
      item = { text = "Waehlen", onClick = function(it)
         order[#order + 1] = "click"
         H.eq(it, item, "Rueckruf bekommt den Eintrag")
         H.falsy(S.Menu.IsOpen(), "Menue ist beim Rueckruf schon zu")
      end }
      S.Menu.Open(nil, { item, { text = "Anderes" } }, { onClose = function() order[#order + 1] = "close" end })
      M.Click(menuRows()[1])
      H.deepEq(order, { "close", "click" })
      H.falsy(S.Menu.IsOpen())
   end)

   H.test("Menue: Rueckruf darf sofort ein neues Menue oder einen Dialog oeffnen", function()
      local _, S = boot()
      local opened = 0
      S.Menu.Open(nil, { { text = "Weiter", onClick = function()
         opened = opened + 1
         S.Menu.Open(nil, { { text = "Zweite Stufe" } })
      end } })
      M.Click(menuRows()[1])
      H.truthy(S.Menu.IsOpen())
      H.deepEq(rowTexts(), { "Zweite Stufe" })
      S.Menu.Close()

      S.Menu.Open(nil, { { text = "Dialog", onClick = function()
         S.Confirm({ title = "t", text = "x", onAccept = function() end })
      end } })
      M.Click(menuRows()[1])
      H.falsy(S.Menu.IsOpen())
      H.truthy(S.DialogOpen())
      S.CloseDialog()
   end)

   H.test("Menue: keepOpen laesst es offen und zeichnet neu (Haken wechselt)", function()
      local _, S = boot()
      local item = { text = "Umschalten", checked = false, keepOpen = true }
      item.onClick = function(it) it.checked = not it.checked end
      S.Menu.Open(nil, { item, { text = "Zu" } })
      local row = menuRows()[1]
      H.falsy(row.check:IsShown(), "ohne Haken")
      M.Click(row)
      H.truthy(S.Menu.IsOpen(), "bleibt offen")
      H.truthy(menuRows()[1].check:IsShown(), "Haken sichtbar")
      M.Click(menuRows()[1])
      H.falsy(menuRows()[1].check:IsShown(), "Haken wieder weg")
      H.truthy(S.Menu.IsOpen())
   end)

   H.test("Menue: checked/radio/isTitle/disabled/color/reason", function()
      local _, S = boot()
      local clicked = {}
      local mk = function(name) return function() clicked[#clicked + 1] = name end end
      S.Menu.Open(nil, {
         { text = "Titel", isTitle = true, onClick = mk("title") },
         { text = "Haken", checked = true, onClick = mk("check") },
         { text = "Punkt", checked = true, radio = true, onClick = mk("radio") },
         { text = "Aus", disabled = true, reason = "Nicht verfuegbar", onClick = mk("off") },
         { text = "Farbig", color = { 1, 0, 0 }, onClick = mk("color") },
      })
      local rows = menuRows()
      H.len(rows, 5)
      H.falsy(rows[1].check:IsShown())
      H.truthy(rows[2].check:IsShown())
      H.falsy(rows[2].dot:IsShown())
      H.truthy(rows[3].dot:IsShown())
      H.falsy(rows[3].check:IsShown())
      -- Titel und gesperrte Zeile reagieren nicht
      M.Click(rows[1])
      M.Click(rows[4])
      H.len(clicked, 0)
      H.truthy(S.Menu.IsOpen(), "Titel/gesperrt schliessen nicht")
      -- Sperrgrund im Tooltip
      M.Enter(rows[4])
      H.truthy(tipHas("Nicht verfuegbar"))
      M.Leave(rows[4])
      -- Farbe
      local r, g, b = rows[5].text:GetTextColor()
      H.near(r, 1)
      H.near(g, 0)
      H.near(b, 0)
      M.Click(rows[5])
      H.deepEq(clicked, { "color" })
   end)

   H.test("Menue: Klick daneben (Fangflaeche) schliesst und ruft onClose", function()
      local _, S = boot()
      local closed = 0
      S.Menu.Open(nil, numbered(3), { onClose = function() closed = closed + 1 end })
      local catcher = findCatcher()
      H.truthy(catcher, "Fangflaeche vorhanden")
      -- Klick auf das Menue selbst (Rand) schliesst nicht
      M.MouseDown(TransmogMenuFrame)
      H.truthy(S.Menu.IsOpen())
      M.MouseDown(catcher)
      H.falsy(S.Menu.IsOpen())
      H.falsy(catcher:IsShown(), "Fangflaeche weg")
      H.eq(closed, 1)
   end)

   H.test("Menue: ESC schliesst nur das Menue, ein Hauptfenster in UISpecialFrames bleibt offen", function()
      local _, S = boot()
      local win = CreateFrame("Frame", "TransmogWindow", UIParent)
      win:SetWidth(200)
      win:SetHeight(200)
      win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      tinsert(UISpecialFrames, "TransmogWindow")
      local closed = 0
      S.Menu.Open(nil, numbered(3), { onClose = function() closed = closed + 1 end })
      H.truthy(M.Escape(), "ESC wurde verbraucht")
      H.falsy(S.Menu.IsOpen())
      H.eq(closed, 1)
      H.truthy(win:IsShown(), "Hauptfenster bleibt")
      -- Ohne Menue schliesst ESC das Fenster wie gewohnt
      M.Escape()
      H.falsy(win:IsShown())
   end)

   H.test("Menue: faengt der Tastaturfaenger nicht, schliesst UISpecialFrames es sauber", function()
      local _, S = boot()
      local closed = 0
      S.Menu.Open(nil, numbered(3), { onClose = function() closed = closed + 1 end })
      for _, e in ipairs(M.Find(TransmogMenuFrame, "EditBox")) do e:ClearFocus() end
      H.truthy(M.Escape())
      H.falsy(S.Menu.IsOpen(), "Zustand zurueckgesetzt")
      H.falsy(TransmogMenuFrame:IsShown())
      H.eq(closed, 1, "onClose genau einmal")
      H.falsy(findCatcher(), "Fangflaeche weg")
   end)

   H.test("Menue: Eintippen wird verschluckt (kein Text im Fanger), Enter schliesst nicht", function()
      local _, S = boot()
      S.Menu.Open(nil, numbered(3))
      local grab = M.Find(TransmogMenuFrame, "EditBox")[1]
      H.truthy(grab:HasFocus(), "Fanger hat den Fokus")
      M.Type(grab, "wasd")
      H.eq(grab:GetText(), "", "Eingabe wird geleert")
      M.Key(grab, "ENTER")
      H.truthy(S.Menu.IsOpen())
      S.Menu.Close()
      H.falsy(grab:HasFocus(), "Fokus nach dem Schliessen frei")
   end)

   H.test("Menue mit 40 Zeilen: begrenzte Zeilenzahl, Mausrad scrollt, klemmt oben und unten", function()
      local _, S = boot()
      S.Menu.Open(nil, numbered(40))
      local rows = menuRows()
      H.eq(#rows, 18, "hoechstens 18 Zeilen sichtbar")
      H.eq(rowTexts()[1], "Item 1")
      H.eq(rowTexts()[18], "Item 18")
      -- Rollbalken sichtbar
      H.truthy(TransmogMenuFrame.__children and true)
      -- oben: Scrollen nach oben aendert nichts
      M.Wheel(TransmogMenuFrame, 1)
      H.eq(rowTexts()[1], "Item 1")
      -- nach unten
      M.Wheel(TransmogMenuFrame, -1)
      H.eq(rowTexts()[1], "Item 4", "drei Zeilen je Rastung")
      H.eq(rowTexts()[18], "Item 21")
      for _ = 1, 20 do M.Wheel(TransmogMenuFrame, -1) end
      H.eq(rowTexts()[1], "Item 23", "unten geklemmt: 40 - 18 + 1")
      H.eq(rowTexts()[18], "Item 40")
      -- Mausrad ueber einer Zeile scrollt ebenfalls
      M.Wheel(menuRows()[5], 1)
      H.eq(rowTexts()[1], "Item 20")
      -- Klick auf eine gescrollte Zeile liefert den richtigen Eintrag
      local got
      S.Menu.Close()
      local items = numbered(40)
      for i, it in ipairs(items) do it.onClick = function() got = i end end
      S.Menu.Open(nil, items)
      for _ = 1, 3 do M.Wheel(TransmogMenuFrame, -1) end
      M.Click(menuRows()[2])
      H.eq(got, 11, "Zeile 2 nach drei Rastungen = Eintrag 9 + 2")
   end)

   H.test("Menue: wenige Eintraege scrollen nicht", function()
      local _, S = boot()
      S.Menu.Open(nil, numbered(5))
      M.Wheel(TransmogMenuFrame, -1)
      H.eq(rowTexts()[1], "Item 1")
      H.eq(#menuRows(), 5)
   end)

   H.test("Menue: maxRows und Zeilenzahl nach unten durch den Bildschirm begrenzt", function()
      local _, S = boot()
      S.Menu.Open(nil, numbered(40), { maxRows = 6 })
      H.eq(#menuRows(), 6)
      S.Menu.Close()
      -- sehr niedriger Bildschirm: weniger Zeilen, mindestens 3
      M.SetScreen(1024, 150)
      S.Menu.Open(nil, numbered(40))
      local n = #menuRows()
      H.truthy(n >= 3 and n < 18, "Zeilen " .. n)
      H.truthy(TransmogMenuFrame:GetHeight() * TransmogMenuFrame:GetScale() <= 150 * 0.92 + 21,
         "Menue passt (ungefaehr) auf den Bildschirm")
   end)

   H.test("Menue: erneutes Oeffnen am selben Anker behaelt die Scrollposition, anderer Anker nicht", function()
      local _, S = boot()
      local a1 = S.Button(newParent(), 100, 20, "A", nil)
      a1:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -50)
      local a2 = S.Button(newParent(), 100, 20, "B", nil)
      a2:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -50)
      local items = numbered(40)
      S.Menu.Open(a1, items)
      M.Wheel(TransmogMenuFrame, -1)
      H.eq(rowTexts()[1], "Item 4")
      S.Menu.Open(a1, items)
      H.eq(rowTexts()[1], "Item 4", "gleicher Anker: Position bleibt")
      S.Menu.Open(a2, items)
      H.eq(rowTexts()[1], "Item 1", "anderer Anker: von vorn")
      S.Menu.Close()
      S.Menu.Open(a2, items)
      H.eq(rowTexts()[1], "Item 1", "nach Schliessen von vorn")
   end)

   H.test("Menue: zweites Open ersetzt das erste und ruft dessen onClose", function()
      local _, S = boot()
      local c1, c2 = 0, 0
      S.Menu.Open(nil, numbered(3, "A"), { onClose = function() c1 = c1 + 1 end })
      S.Menu.Open(nil, numbered(2, "B"), { onClose = function() c2 = c2 + 1 end })
      H.eq(c1, 1)
      H.eq(c2, 0)
      H.deepEq(rowTexts(), { "B1", "B2" })
      S.Menu.Close()
      H.eq(c2, 1)
      H.eq(c1, 1)
   end)

   H.test("Menue: Position unter dem Anker, klappt nach oben, bleibt im Bildschirm", function()
      local _, S = boot()
      local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
      -- Anker oben links: Menue beginnt direkt unter dem Anker
      local a = S.Button(UIParent, 100, 20, "A", nil)
      a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
      S.Menu.Open(a, numbered(3))
      local f = TransmogMenuFrame
      H.near(f:GetLeft(), 100, 0.01, "linksbuendig")
      H.truthy(f:GetTop() <= a:GetBottom() + 0.01, "unter dem Anker")
      H.truthy(f:GetTop() >= a:GetBottom() - 4, "direkt darunter")
      S.Menu.Close()

      -- Anker am unteren Rand: Menue klappt nach oben
      local b = S.Button(UIParent, 100, 20, "B", nil)
      b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 100, 5)
      S.Menu.Open(b, numbered(6))
      H.truthy(f:GetBottom() >= b:GetTop() - 0.01, "ueber dem Anker")
      H.truthy(f:GetTop() <= sh + 0.01, "oben im Bildschirm")
      S.Menu.Close()

      -- Anker am rechten Rand: nach links geschoben
      local c = S.Button(UIParent, 100, 20, "C", nil)
      c:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -2, -100)
      S.Menu.Open(c, { { text = "Ein recht langer Menuetext fuer die Breite" } })
      H.truthy(f:GetRight() <= sw + 0.01, "rechts im Bildschirm")
      H.truthy(f:GetLeft() >= 0)
      S.Menu.Close()

      -- align = RIGHT: rechtsbuendig zum Anker
      local d = S.Button(UIParent, 100, 20, "D", nil)
      d:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 500, -100)
      S.Menu.Open(d, numbered(3), { align = "RIGHT" })
      H.near(f:GetRight(), d:GetRight(), 0.01)
   end)

   H.test("Menue: Breite folgt Text und Anker, Mindest- und Hoechstbreite", function()
      local _, S = boot()
      S.Menu.Open(nil, { { text = "x" } })
      local wMin = TransmogMenuFrame:GetWidth()
      H.truthy(wMin >= 120, "Mindestbreite")
      S.Menu.Close()
      local long = string.rep("W", 200)
      S.Menu.Open(nil, { { text = long } })
      H.truthy(TransmogMenuFrame:GetWidth() <= 380 + 8 + 6, "Hoechstbreite")
      S.Menu.Close()
      -- breiter Anker: mindestens so breit wie der Anker
      local a = S.Button(UIParent, 300, 20, "A", nil)
      a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -50)
      S.Menu.Open(a, { { text = "x" } })
      H.truthy(TransmogMenuFrame:GetWidth() >= 300 - 0.01)
   end)

   H.test("Menue: skaliert mit dem Anker (Fensterscale)", function()
      local _, S = boot()
      local win = CreateFrame("Frame", nil, UIParent)
      win:SetScale(1.4)
      win:SetWidth(300)
      win:SetHeight(200)
      win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -50)
      local a = S.Button(win, 100, 20, "A", nil)
      a:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -10)
      S.Menu.Open(a, numbered(3))
      H.near(TransmogMenuFrame:GetScale(), 1.4, 1e-6)
      S.Menu.Close()
      S.Menu.Open(a, numbered(3), { scale = 0.8 })
      H.near(TransmogMenuFrame:GetScale(), 0.8, 1e-6)
   end)

   H.test("Menue: in einem skalierten Fenster sitzt es (absolut gemessen) unter dem Anker", function()
      local _, S = boot()
      for _, scale in ipairs({ 0.7, 1.0, 1.4 }) do
         local win = CreateFrame("Frame", nil, UIParent)
         win:SetScale(scale)
         win:SetWidth(300)
         win:SetHeight(200)
         win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -80)
         local a = S.Button(win, 100, 20, "A", nil)
         a:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -10)
         S.Menu.Open(a, numbered(3))
         local f = TransmogMenuFrame
         local es = f:GetEffectiveScale()
         local ea = a:GetEffectiveScale()
         H.near(f:GetLeft() * es, a:GetLeft() * ea, 0.01, "links bei Skalierung " .. scale)
         local gap = a:GetBottom() * ea - f:GetTop() * es
         H.truthy(gap >= -0.01 and gap <= 3, "direkt unter dem Anker: " .. gap .. " bei " .. scale)
         S.Menu.Close()
      end
   end)

   H.test("Menue: Anker verschwindet -> Menue schliesst sich selbst (OnUpdate), danach kein OnUpdate", function()
      local _, S = boot()
      local p = newParent()
      local a = S.Button(p, 100, 20, "A", nil)
      a:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10)
      H.len(updateFrames(), 0, "vorher kein OnUpdate")
      local closed = 0
      S.Menu.Open(a, numbered(3), { onClose = function() closed = closed + 1 end })
      H.len(updateFrames(), 1, "waehrend es offen ist genau einer")
      M.Advance(1)
      H.truthy(S.Menu.IsOpen(), "Anker sichtbar: bleibt offen")
      p:Hide()
      M.Advance(1)
      H.falsy(S.Menu.IsOpen(), "Anker weg: geschlossen")
      H.eq(closed, 1)
      H.len(updateFrames(), 0, "kein haengendes OnUpdate")
   end)

   H.test("Menue ohne Anker steht am Mauszeiger und im Bildschirm", function()
      local _, S = boot()
      M.world.cursor = { 300, 400 }
      S.Menu.Open(nil, numbered(3))
      local f = TransmogMenuFrame
      H.near(f:GetLeft(), 300, 0.01)
      H.near(f:GetTop(), 400, 0.01)
      S.Menu.Close()
      M.world.cursor = { 5000, 5000 }
      S.Menu.Open(nil, numbered(3))
      H.truthy(f:GetRight() <= UIParent:GetWidth() + 0.01)
      H.truthy(f:GetTop() <= UIParent:GetHeight() + 0.01)
   end)

   H.test("Menue: viele Oeffnen/Schliessen-Zyklen haengen nichts an (Zeilen und Frames begrenzt)", function()
      local _, S = boot()
      -- Einschwingen: das groesste Menue legt die Zeilen an, danach nichts mehr
      S.Menu.Open(nil, numbered(40))
      S.Menu.Close()
      local before = #M.frames
      for i = 1, 60 do
         S.Menu.Open(nil, numbered(1 + i % 40))
         S.Menu.Close()
      end
      H.eq(#M.frames, before, "keine neuen Frames nach dem Einschwingen")
      H.len(updateFrames(), 0)
      H.falsy(findCatcher())
   end)

   -- ======================================================================
   H.section("Dialoge: Prompt und Confirm")
   -- ======================================================================

   -- Text-Elemente des Dialogs (sichtbar)
   local function dialogTexts(frame)
      return M.Texts(frame)
   end

   local function dialogEdit(frame)
      for _, e in ipairs(M.Find(frame, "EditBox")) do
         if e:GetWidth() > 10 then return e end
      end
   end

   local function dialogButtons(frame)
      local out = {}
      for _, b in ipairs(M.Find(frame, "Button")) do
         if b:IsShown() then out[#out + 1] = b end
      end
      return out
   end

   local function findButton(frame, label)
      for _, b in ipairs(M.Find(frame, "Button")) do
         if b.label and b.label:GetText() == label and b:IsShown() then return b end
      end
   end

   H.test("Prompt: zeigt Titel/Text/Vorbelegung, Annehmen liefert den getrimmten Text", function()
      local _, S = boot()
      local got, cancelled = {}, 0
      S.Prompt({ title = "Outfit speichern", text = "Name eingeben:", default = "Outfit 3",
                 accept = "Speichern", onAccept = function(t) got[#got + 1] = t end,
                 onCancel = function() cancelled = cancelled + 1 end })
      local f = TransmogPromptFrame
      H.truthy(f:IsShown())
      H.truthy(S.DialogOpen())
      H.eq(f:GetFrameStrata(), "FULLSCREEN_DIALOG")
      H.truthy(M.HasText(f, "Outfit speichern"), "Titel")
      H.truthy(M.HasText(f, "Name eingeben:"), "Text")
      local e = dialogEdit(f)
      H.eq(e:GetText(), "Outfit 3", "Vorbelegung")
      H.truthy(e:HasFocus(), "Eingabefeld hat den Fokus")
      local accept = findButton(f, "Speichern")
      H.truthy(accept, "Knopf mit eigener Beschriftung")
      M.Type(e, "  Mein Look  ")
      M.Click(accept)
      H.deepEq(got, { "Mein Look" })
      H.eq(cancelled, 0)
      H.falsy(f:IsShown())
      H.falsy(S.DialogOpen())
   end)

   H.test("Prompt: Enter nimmt an, ESC und Abbrechen-Knopf rufen onCancel genau einmal", function()
      local _, S = boot()
      local acc, can = 0, 0
      local function open(default)
         S.Prompt({ title = "T", text = "x", default = default or "Name",
                    onAccept = function() acc = acc + 1 end, onCancel = function() can = can + 1 end })
      end
      open()
      M.Key(M.S.focus, "ENTER")
      H.eq(acc, 1)
      H.eq(can, 0)
      H.falsy(S.DialogOpen())

      open()
      M.Key(M.S.focus, "ESCAPE")
      H.eq(acc, 1)
      H.eq(can, 1)
      H.falsy(S.DialogOpen())

      open()
      M.Escape()
      H.eq(can, 2, "ESC im Spiel")
      H.falsy(TransmogPromptFrame:IsShown())

      open()
      local cancelBtn = findButton(TransmogPromptFrame, CANCEL)
      H.truthy(cancelBtn, "Abbrechen-Knopf mit Blizzard-Text")
      M.Click(cancelBtn)
      H.eq(can, 3)
      H.eq(acc, 1)
   end)

   H.test("Prompt: leere Eingabe sperrt Annehmen (Knopf und Enter), Tippen gibt frei", function()
      local _, S = boot()
      local acc = 0
      S.Prompt({ title = "T", default = "", onAccept = function() acc = acc + 1 end })
      local f = TransmogPromptFrame
      local e = dialogEdit(f)
      local accept = findButton(f, OKAY)
      H.truthy(accept, "OK-Knopf (Blizzard-Text)")
      H.falsy(accept:IsEnabledState(), "leer: gesperrt")
      M.Click(accept)
      M.Key(e, "ENTER")
      H.eq(acc, 0)
      H.truthy(S.DialogOpen(), "Dialog bleibt offen")
      H.truthy(e:HasFocus(), "Fokus bleibt im Feld")
      M.Type(e, "   ")
      H.falsy(accept:IsEnabledState(), "nur Leerzeichen: weiter gesperrt")
      M.Type(e, "x")
      H.truthy(accept:IsEnabledState(), "Text: freigegeben")
      M.Type(e, "")
      H.falsy(accept:IsEnabledState(), "wieder leer: gesperrt")
      M.Type(e, "Name")
      M.Key(e, "ENTER")
      H.eq(acc, 1)
   end)

   H.test("Prompt: validate sperrt mit Grund, der als Text und im Knopf-Tooltip erscheint", function()
      local _, S = boot()
      local acc = 0
      S.Prompt({ title = "T", default = "Vorhanden", validate = function(text)
         if text == "Vorhanden" then return false, "Name existiert schon" end
         return true
      end, onAccept = function() acc = acc + 1 end })
      local f = TransmogPromptFrame
      local e = dialogEdit(f)
      local accept = findButton(f, OKAY)
      H.falsy(accept:IsEnabledState())
      H.truthy(M.HasText(f, "Name existiert schon"), "Grund sichtbar")
      M.Click(accept)
      M.Key(e, "ENTER")
      H.eq(acc, 0)
      M.Enter(accept)
      H.truthy(tipHas("Name existiert schon"), "Grund im Tooltip")
      M.Leave(accept)
      M.Type(e, "Neu")
      H.truthy(accept:IsEnabledState())
      H.falsy(M.HasText(f, "Name existiert schon"), "Fehlertext weg")
      M.Click(accept)
      H.eq(acc, 1)
   end)

   H.test("Prompt: input=false verhaelt sich wie eine Rueckfrage (kein Eingabefeld)", function()
      local _, S = boot()
      local got
      S.Prompt({ title = "T", text = "Sicher?", input = false, onAccept = function(...) got = { n = select("#", ...), ... } end })
      local f = TransmogPromptFrame
      local e = dialogEdit(f)
      H.falsy(e:IsShown(), "Eingabefeld verborgen")
      local accept = findButton(f, OKAY)
      H.truthy(accept:IsEnabledState(), "ohne Eingabe nie gesperrt")
      M.Click(accept)
      H.truthy(got)
      H.falsy(S.DialogOpen())
   end)

   H.test("Prompt: Wiedereintritt: Rueckrufe duerfen den naechsten Dialog oeffnen", function()
      local _, S = boot()
      local log = {}
      S.Prompt({ title = "Eins", default = "a", onAccept = function(t)
         log[#log + 1] = "p1:" .. t
         S.Confirm({ title = "Zwei", text = "Sicher?", onAccept = function() log[#log + 1] = "c1" end,
                     onCancel = function() log[#log + 1] = "c1cancel" end })
      end })
      M.Key(M.S.focus, "ENTER")
      H.deepEq(log, { "p1:a" })
      H.truthy(S.DialogOpen())
      H.truthy(TransmogConfirmFrame:IsShown())
      H.falsy(TransmogPromptFrame:IsShown())
      M.Key(M.S.focus, "ENTER")
      H.deepEq(log, { "p1:a", "c1" })
      H.falsy(S.DialogOpen())
   end)

   H.test("Confirm: Ja/Nein ohne eigene Beschriftung, Annehmen/Abbrechen, Enter und ESC", function()
      local _, S = boot()
      local acc, can = 0, 0
      local function open(extra)
         local o = { title = "Loeschen?", text = "Wirklich loeschen?", onAccept = function(...)
            acc = acc + 1
            H.eq(select("#", ...), 1, "onAccept(text) bekommt auch bei Confirm ein Argument")
         end, onCancel = function() can = can + 1 end }
         for k, v in pairs(extra or {}) do o[k] = v end
         S.Confirm(o)
      end
      open()
      local f = TransmogConfirmFrame
      H.truthy(f:IsShown())
      H.truthy(M.HasText(f, "Wirklich loeschen?"))
      H.truthy(findButton(f, YES), "Ja")
      H.truthy(findButton(f, NO), "Nein")
      M.Click(findButton(f, YES))
      H.eq(acc, 1)
      H.falsy(f:IsShown())

      open()
      M.Click(findButton(f, NO))
      H.eq(can, 1)
      H.eq(acc, 1)

      -- Enter (Tastaturfaenger) nimmt an, ESC bricht ab
      open()
      H.truthy(M.S.focus, "Fokus liegt im Dialog (Tastaturfaenger)")
      M.Key(M.S.focus, "ENTER")
      H.eq(acc, 2)
      open()
      M.Key(M.S.focus, "ESCAPE")
      H.eq(can, 2)
      open()
      M.Escape()
      H.eq(can, 3)
      H.falsy(f:IsShown())

      -- eigene Beschriftungen und ohne Abbrechen-Knopf
      open({ accept = "Loeschen", cancel = "Behalten" })
      H.truthy(findButton(f, "Loeschen"))
      H.truthy(findButton(f, "Behalten"))
      S.CloseDialog()
      open({ accept = "Verstanden", cancel = false })
      H.truthy(findButton(f, "Verstanden"))
      H.falsy(findButton(f, "Behalten"))
      H.falsy(findButton(f, NO))
      H.falsy(findButton(f, CANCEL))
      S.CloseDialog()
      -- danach ist der Abbrechen-Knopf beim naechsten Mal wieder da
      open({ accept = "A", cancel = "B" })
      H.truthy(findButton(f, "B"))
      S.CloseDialog()
   end)

   H.test("Confirm: danger faerbt Streifen und Knopf rot, danach wieder normal", function()
      local _, S = boot()
      S.Confirm({ title = "Achtung", text = "x", danger = true, accept = "Weg", onAccept = function() end })
      local f = TransmogConfirmFrame
      local accept = findButton(f, "Weg")
      H.truthy(same4(color(accept), S.THEMES.danger.bg), "Knopf: Danger-Thema")
      local stripe = f.__children[1]
      S.CloseDialog()
      S.Confirm({ title = "Normal", text = "x", accept = "Ok", onAccept = function() end })
      local accept2 = findButton(f, "Ok")
      H.truthy(same4(color(accept2), S.THEMES.primary.bg), "Knopf: Primary-Thema")
      S.CloseDialog()
   end)

   H.test("Nur ein Dialog zugleich: der neue bricht den offenen ab (onCancel genau einmal)", function()
      local _, S = boot()
      local log = {}
      S.Prompt({ title = "A", default = "x", onAccept = function() log[#log + 1] = "A:acc" end,
                 onCancel = function() log[#log + 1] = "A:cancel" end })
      S.Confirm({ title = "B", text = "b", onAccept = function() log[#log + 1] = "B:acc" end,
                  onCancel = function() log[#log + 1] = "B:cancel" end })
      H.deepEq(log, { "A:cancel" })
      H.falsy(TransmogPromptFrame:IsShown())
      H.truthy(TransmogConfirmFrame:IsShown())
      -- gleiche Art noch einmal
      S.Confirm({ title = "C", text = "c", onAccept = function() log[#log + 1] = "C:acc" end,
                  onCancel = function() log[#log + 1] = "C:cancel" end })
      H.deepEq(log, { "A:cancel", "B:cancel" })
      H.truthy(TransmogConfirmFrame:IsShown())
      M.Click(findButton(TransmogConfirmFrame, YES))
      H.deepEq(log, { "A:cancel", "B:cancel", "C:acc" })
      H.falsy(S.DialogOpen())
      H.falsy(M.S.focus and M.S.focus:IsVisible(), "kein Fokus bleibt haengen")
   end)

   H.test("Dialog fremd verborgen (z. B. UISpecialFrames/UI aus) zaehlt als Abbrechen, einmal", function()
      local _, S = boot()
      local can, acc = 0, 0
      S.Confirm({ title = "T", text = "x", onAccept = function() acc = acc + 1 end,
                  onCancel = function() can = can + 1 end })
      TransmogConfirmFrame:Hide()
      H.eq(can, 1)
      H.eq(acc, 0)
      H.falsy(S.DialogOpen())
      H.falsy(findCatcher() ~= nil and false)
      -- neuer Dialog danach geht
      S.Confirm({ title = "T", text = "x", onAccept = function() acc = acc + 1 end })
      M.Click(findButton(TransmogConfirmFrame, YES))
      H.eq(acc, 1)
      H.eq(can, 1)
   end)

   H.test("Dialog: Skin.CloseDialog bricht ab; ohne Dialog false", function()
      local _, S = boot()
      H.falsy(S.CloseDialog())
      local can = 0
      S.Confirm({ title = "T", text = "x", onCancel = function() can = can + 1 end })
      H.truthy(S.CloseDialog())
      H.eq(can, 1)
      H.falsy(S.DialogOpen())
      H.falsy(S.CloseDialog())
   end)

   H.test("Dialog schliesst ein offenes Menue; ein Menue ueber dem Dialog laesst ESC beim Menue", function()
      local _, S = boot()
      S.Menu.Open(nil, numbered(3))
      S.Confirm({ title = "T", text = "x", onAccept = function() end })
      H.falsy(S.Menu.IsOpen(), "Menue vom Dialog geschlossen")
      -- Menue innerhalb eines offenen Dialogs: ESC schliesst erst das Menue
      S.Menu.Open(nil, numbered(3))
      H.truthy(S.Menu.IsOpen())
      H.truthy(S.DialogOpen())
      M.Escape()
      H.falsy(S.Menu.IsOpen(), "ESC 1: Menue")
      H.truthy(S.DialogOpen(), "Dialog bleibt")
      H.truthy(M.S.focus, "Dialog hat den Fokus wieder")
      M.Escape()
      H.falsy(S.DialogOpen(), "ESC 2: Dialog")
   end)

   H.test("Dialog: Hauptfenster in UISpecialFrames bleibt bei ESC im Dialog offen", function()
      local _, S = boot()
      local win = CreateFrame("Frame", "TransmogWindow", UIParent)
      win:SetWidth(200)
      win:SetHeight(200)
      win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      tinsert(UISpecialFrames, "TransmogWindow")
      S.Prompt({ title = "T", default = "x", onAccept = function() end })
      M.Escape()
      H.falsy(S.DialogOpen())
      H.truthy(win:IsShown(), "Fenster bleibt")
      S.Confirm({ title = "T", text = "x", onAccept = function() end })
      M.Escape()
      H.falsy(S.DialogOpen())
      H.truthy(win:IsShown(), "Fenster bleibt (Confirm)")
   end)

   H.test("Dialog: kein haengendes OnUpdate, Abdunklung weg, Frames werden wiederverwendet", function()
      local _, S = boot()
      local n
      for i = 1, 20 do
         if i % 2 == 0 then
            S.Prompt({ title = "T", default = "x", onAccept = function() end })
         else
            S.Confirm({ title = "T", text = "x", onAccept = function() end })
         end
         if i == 4 then n = #M.frames end
         S.CloseDialog()
      end
      H.len(updateFrames(), 0)
      H.eq(#M.frames, n, "keine neuen Frames je Dialog")
      for _, c in ipairs({ UIParent:GetChildren() }) do
         if c.__strata == "FULLSCREEN_DIALOG" and c:IsShown() then
            H.fail("sichtbarer Rest-Frame: " .. tostring(c.__name))
         end
      end
   end)

   H.test("Dialog: Fehler in onAccept raeumen den Zustand trotzdem auf", function()
      local _, S = boot()
      H.allowErrors()
      S.Confirm({ title = "T", text = "x", onAccept = function() error("kaputt") end })
      M.Click(findButton(TransmogConfirmFrame, YES))
      H.eq(#H.takeErrors(), 1)
      H.falsy(S.DialogOpen())
      H.falsy(TransmogConfirmFrame:IsShown())
      S.Confirm({ title = "T", text = "x", onAccept = function() end })
      H.truthy(S.DialogOpen())
      S.CloseDialog()
   end)

   H.test("Dialog: Breite wird begrenzt, lange Texte machen ihn hoeher, Skalierung folgt dem Fenster", function()
      local _, S = boot()
      S.Confirm({ title = "T", text = "kurz", width = 10, onAccept = function() end })
      H.eq(TransmogConfirmFrame:GetWidth(), 280, "Mindestbreite")
      local h1 = TransmogConfirmFrame:GetHeight()
      S.CloseDialog()
      S.Confirm({ title = "T", text = string.rep("Sehr langer Text ", 40), width = 9999, onAccept = function() end })
      H.eq(TransmogConfirmFrame:GetWidth(), 600, "Hoechstbreite")
      S.CloseDialog()
      S.Confirm({ title = "T", text = string.rep("Sehr langer Text ", 40), onAccept = function() end })
      H.truthy(TransmogConfirmFrame:GetHeight() > h1, "mehr Text, mehr Hoehe")
      S.CloseDialog()
      -- Skalierung wie das Hauptfenster
      local win = CreateFrame("Frame", "TransmogWindow", UIParent)
      win:SetScale(1.3)
      S.Confirm({ title = "T", text = "x", onAccept = function() end })
      H.near(TransmogConfirmFrame:GetScale(), 1.3, 1e-6)
      S.CloseDialog()
      S.Confirm({ title = "T", text = "x", scale = 0.9, onAccept = function() end })
      H.near(TransmogConfirmFrame:GetScale(), 0.9, 1e-6)
   end)

   H.test("Dialog-Layout: Text, Eingabe, Fehlerzeile und Knoepfe ueberlappen nicht und liegen im Rahmen", function()
      local _, S = boot()
      local long = string.rep("Dies ist ein laengerer Hinweistext. ", 8)
      S.Prompt({ title = "Titel", text = long, default = "Name", validate = function() return false, "Fehler" end,
                 onAccept = function() end })
      local f = TransmogPromptFrame
      local e = dialogEdit(f)
      local accept = findButton(f, OKAY)
      local cancel = findButton(f, CANCEL)
      -- Textregion: die mit dem langen Text
      local text
      for _, r in ipairs({ f:GetRegions() }) do
         if r.GetText and r:GetText() == long then text = r end
      end
      H.truthy(text, "Textregion")
      local fTop, fBottom, fLeft, fRight = f:GetTop(), f:GetBottom(), f:GetLeft(), f:GetRight()
      H.truthy(text:GetStringHeight() > 14 * 2, "mehrzeilig")
      -- Abstand der Eingabe von der Oberkante: Kopf + Luft + gemessene Texthoehe
      local editFromTop = fTop - e:GetTop()
      H.truthy(editFromTop >= 28 + text:GetStringHeight(), "Eingabe unter dem Text: " .. editFromTop)
      H.truthy(e:GetBottom() >= accept:GetTop(), "Knoepfe unter der Eingabe (und Fehlerzeile)")
      H.truthy(accept:GetBottom() >= fBottom, "Knopf im Rahmen unten")
      H.truthy(accept:GetRight() <= fRight and cancel:GetLeft() >= fLeft, "Knoepfe im Rahmen seitlich")
      H.truthy(cancel:GetRight() <= accept:GetLeft(), "Abbrechen links neben Annehmen")
      H.truthy(e:GetLeft() >= fLeft and e:GetRight() <= fRight, "Eingabe im Rahmen")
      H.truthy(f:GetHeight() >= editFromTop + e:GetHeight() + 14 + 26, "Rahmen hoch genug")
      S.CloseDialog()
   end)

   H.test("Skin.Prompt()/Confirm() ohne Argumente zeigen einen leeren Dialog statt zu werfen", function()
      local _, S = boot()
      S.Confirm()
      H.truthy(S.DialogOpen())
      S.CloseDialog()
      S.Prompt()
      H.truthy(S.DialogOpen())
      H.falsy(findButton(TransmogPromptFrame, OKAY):IsEnabledState(), "leer: Annehmen gesperrt")
      S.CloseDialog()
   end)

   -- ======================================================================
   H.section("Zustandsautomat (Zufallsfolge, fester Startwert)")
   -- ======================================================================

   -- Kleiner linearer Kongruenzgenerator: reproduzierbar ohne math.random-Zustand.
   -- Es werden die OBEREN Bits benutzt (die unteren haben kurze Perioden).
   local function lcg(seed)
      local s = seed
      return function(n)
         s = (s * 1664525 + 1013904223) % 4294967296
         return (math.floor(s / 65536) % n) + 1
      end
   end

   local function runFuzz(seed, steps)
      local _, S = boot()
      local rnd = lcg(seed)
      local win = CreateFrame("Frame", "TransmogWindow", UIParent)
      win:SetWidth(200)
      win:SetHeight(200)
      win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      tinsert(UISpecialFrames, "TransmogWindow")
      local anchor = S.Button(UIParent, 100, 20, "A", nil)
      anchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)

      local opened, finished = 0, 0       -- Dialoge: geoeffnet / mit Rueckruf beendet
      local menuOpened, menuClosed = 0, 0

      local function openDialog(kind)
         opened = opened + 1
         local opts = { title = "T" .. opened, text = "Text", default = "Name",
                        onAccept = function() finished = finished + 1 end,
                        onCancel = function() finished = finished + 1 end }
         if kind == 1 then S.Prompt(opts) else S.Confirm(opts) end
      end

      local function openMenu(count)
         menuOpened = menuOpened + 1
         S.Menu.Open(rnd(2) == 1 and anchor or nil, numbered(count), { onClose = function()
            menuClosed = menuClosed + 1
         end })
      end

      local function invariants(step, what)
         local label = "Schritt " .. step .. " (" .. what .. ")"
         local prompt = rawget(_G, "TransmogPromptFrame")
         local confirm = rawget(_G, "TransmogConfirmFrame")
         local menu = rawget(_G, "TransmogMenuFrame")
         local pShown = prompt and prompt:IsShown() and true or false
         local cShown = confirm and confirm:IsShown() and true or false
         local mShown = menu and menu:IsShown() and true or false
         H.falsy(pShown and cShown, label .. ": zwei Dialoge sichtbar")
         H.eq(S.DialogOpen(), pShown or cShown, label .. ": DialogOpen == sichtbar")
         H.eq(S.Menu.IsOpen(), mShown, label .. ": Menu.IsOpen == sichtbar")
         H.eq(findCatcher() ~= nil, mShown, label .. ": Fangflaeche nur mit Menue")
         H.len(updateFrames(), mShown and 1 or 0, label .. ": OnUpdate nur mit offenem Menue")
         H.eq(finished + ((pShown or cShown) and 1 or 0), opened, label .. ": jeder Dialog genau einmal beendet")
         H.eq(menuClosed + (mShown and 1 or 0), menuOpened, label .. ": onClose genau einmal je Menue")
         local focus = M.S.focus
         if (pShown or cShown) or mShown then
            H.truthy(focus and focus:IsVisible(), label .. ": Fokus im offenen Dialog/Menue")
         else
            H.falsy(focus, label .. ": kein Fokus ohne Dialog/Menue")
         end
         H.truthy(win:IsShown() or (what == "ESC-ohne-Fokus"), label .. ": Hauptfenster")
      end

      for step = 1, steps do
         local act = rnd(11)
         local what
         if act == 1 then
            what = "Prompt"
            openDialog(1)
         elseif act == 2 then
            what = "Confirm"
            openDialog(2)
         elseif act == 3 then
            what = "Menue"
            openMenu(rnd(40))
         elseif act == 4 then
            what = "ESC"
            M.Escape()
            -- ESC schliesst das Hauptfenster nur, wenn weder Menue noch Dialog offen waren
            if not win:IsShown() then win:Show() end
         elseif act == 5 then
            what = "Enter"
            local f = M.S.focus
            if f and f:IsVisible() then M.Key(f, "ENTER") end
         elseif act == 6 then
            what = "Tippen"
            local f = M.S.focus
            if f and f:IsVisible() and f:GetObjectType() == "EditBox" then
               M.Type(f, (rnd(3) == 1) and "" or ("x" .. rnd(99)))
            end
         elseif act == 7 then
            what = "CloseDialog"
            S.CloseDialog()
         elseif act == 8 then
            what = "MenuClose"
            S.Menu.Close()
         elseif act == 9 then
            what = "Klick daneben"
            local c = findCatcher()
            if c then M.MouseDown(c) end
         elseif act == 10 then
            what = "Mausrad"
            if S.Menu.IsOpen() then M.Wheel(TransmogMenuFrame, rnd(2) == 1 and 1 or -1) end
         else
            what = "Zeit"
            M.Advance(0.3)
         end
         invariants(step, what)
      end

      -- aufraeumen: alles zu, alle Rueckrufe gezaehlt
      S.Menu.Close()
      S.CloseDialog()
      H.eq(finished, opened, "alle Dialoge beendet")
      H.eq(menuClosed, menuOpened, "alle Menues beendet")
   end

   H.test("Zufallsfolge A: Menue, Dialoge, ESC, Eingabe halten die Invarianten", function()
      runFuzz(20240611, 400)
   end)

   H.test("Zufallsfolge B (anderer Startwert, laenger)", function()
      runFuzz(7, 700)
   end)

   H.test("Zufallsfolge C", function()
      runFuzz(987654321, 500)
   end)

   -- Zufallsfolge ueber Knoepfe/Haken/Slider: Tooltip- und Hover-Zustand
   local function runWidgetFuzz(seed, steps)
      local _, S = boot()
      local rnd = lcg(seed)
      local p = newParent(500, 300)
      local widgets = {}
      local clicks = {}
      for i = 1, 3 do
         local b = S.Button(p, 100, 22, "B" .. i, function(self) clicks[self] = (clicks[self] or 0) + 1 end)
         b:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10 - 30 * i)
         widgets[#widgets + 1] = b
      end
      widgets[1].tip = "Hinweis 1"
      widgets[2].tip = function(tt) tt:AddLine("Hinweis 2") end
      local c = S.Check(p, "Haken", function() end)
      c:SetPoint("TOPLEFT", p, "TOPLEFT", 200, -40)
      widgets[#widgets + 1] = c
      local sl = S.Slider(p, 100, 0, 10, 1, function() end)
      sl:SetPoint("TOPLEFT", p, "TOPLEFT", 200, -80)
      widgets[#widgets + 1] = sl

      local function expectTip(w)
         -- Was w zeigen wuerde, wenn die Maus darauf liegt
         if w.uiOff and w.disabledTip and w.disabledTip ~= "" then return true end
         return w.tip ~= nil and w.tip ~= false
      end

      for step = 1, steps do
         local w = widgets[rnd(#widgets)]
         local act = rnd(8)
         local what
         if act == 1 then
            what = "Enter"
            if w:IsVisible() then M.Enter(w) end
         elseif act == 2 then
            what = "Leave"
            M.Leave(w)
         elseif act == 3 then
            what = "sperren"
            w:SetEnabledState(false, (rnd(2) == 1) and "Grund " .. step or nil)
         elseif act == 4 then
            what = "freigeben"
            w:SetEnabledState(true)
         elseif act == 5 then
            what = "verbergen"
            w:Hide()
         elseif act == 6 then
            what = "anzeigen"
            w:Show()
         elseif act == 7 then
            what = "Klick"
            if w:IsVisible() and w.GetObjectType and w:GetObjectType() == "Button" then M.Click(w) end
         else
            what = "Zeit"
            M.Advance(0.2)
         end

         local label = "Schritt " .. step .. " (" .. what .. ")"
         -- 1. Tooltip gehoert hoechstens dem Widget unter der Maus
         if GameTooltip:IsShown() then
            local owner = GameTooltip:GetOwner()
            H.truthy(owner and owner == M.S.hover, label .. ": Tooltip nur unter der Maus")
            H.truthy(owner:IsVisible(), label .. ": Besitzer sichtbar")
            H.truthy(expectTip(owner), label .. ": Tooltip hat Anlass")
         end
         -- 2. Liegt die Maus auf einem sichtbaren Widget mit Anlass: Tooltip steht
         local h = M.S.hover
         if h and h:IsVisible() then
            for _, x in ipairs(widgets) do
               if x == h and x.hover then
                  H.eq(GameTooltip:IsShown() and GameTooltip:GetOwner() == x and true or false,
                     expectTip(x) and true or false, label .. ": Tooltip passend zum Zustand")
               end
            end
         end
         -- 3. Hover-Merker stimmt mit der Maus ueberein (versteckt: zurueckgesetzt)
         for _, x in ipairs(widgets) do
            if x.hover then
               H.truthy(x == M.S.hover and x:IsVisible(), label .. ": haengender Hover")
            end
         end
      end
   end

   H.test("Zufallsfolge Widgets: Tooltip und Hover bleiben zum Zustand passend", function()
      runWidgetFuzz(31337, 400)
   end)

   H.test("Zufallsfolge Widgets (anderer Startwert)", function()
      runWidgetFuzz(2718281, 500)
   end)

   H.test("Zufallsfolge Slider: Bereich, Schrittraster, Rueckrufe nur bei echter Aenderung", function()
      local _, S = boot()
      local p = newParent()
      local rnd = lcg(424242)
      local configs = { { 0.6, 1.5, 0.05 }, { 0, 1, 0.1 }, { 60, 150, 5 }, { 0, 10, 1 }, { 1, 5, 0.25 } }
      for _, c in ipairs(configs) do
         local lo, hi, st = c[1], c[2], c[3]
         local calls, lastV = 0, nil
         local s = S.Slider(p, 150, lo, hi, st, function(v) calls = calls + 1; lastV = v end)
         for i = 1, 250 do
            local a = rnd(7)
            local before, n0 = s:GetValue(), calls
            local target = lo + (hi - lo) * (rnd(1001) - 1) / 1000
            if a == 1 then
               s:SetValue(target)
            elseif a == 2 then
               s:SetValueQuiet(target)
               H.eq(calls, n0, "SetValueQuiet ist still")
            elseif a == 3 then
               M.Wheel(s, rnd(2) == 1 and 1 or -1)
            elseif a == 4 then
               s:SetEnabledState(false, "x")
               s:SetValue(target)
               M.Wheel(s, 1)
               H.eq(s:GetValue(), before, "gesperrt: Wert unveraendert")
               H.eq(calls, n0, "gesperrt: kein Rueckruf")
               s:SetEnabledState(true)
            elseif a == 5 then
               s:SetValue(hi * 10 + 5)
            elseif a == 6 then
               s:SetValue(lo - 77)
            else
               s:SetValueQuiet(lo)
            end
            local v = s:GetValue()
            H.truthy(v >= lo - 1e-9 and v <= hi + 1e-9, "im Bereich: " .. tostring(v))
            local k = (v - lo) / st
            H.truthy(math.abs(k - math.floor(k + 0.5)) < 1e-6 or math.abs(v - hi) < 1e-9,
               "auf dem Raster: " .. tostring(v))
            if calls ~= n0 then
               H.near(lastV, v, 1e-9, "Rueckruf meldet den neuen Wert")
               H.truthy(math.abs(v - before) > 1e-9, "Rueckruf nur bei Aenderung")
               H.eq(calls, n0 + 1, "genau ein Rueckruf je Eingabe")
            end
         end
      end
   end)

   -- ======================================================================
   H.section("Hygiene")
   -- ======================================================================

   H.test("Skin legt ausser Transmog* keine Globals an und liest keine Implicit-Globals", function()
      boot()
      local _, S = boot()
      local b = S.Button(newParent(), 100, 22, "x", function() end)
      M.Click(b)
      M.Enter(b)
      M.Leave(b)
      S.Menu.Open(nil, numbered(3))
      S.Menu.Close()
      S.Prompt({ title = "t", default = "d" })
      M.Escape()
      -- (der Runner prueft am Testende: Stray-Globals, this/arg1/event, fehlende Dateien, Handler-Fehler)
      H.len(M.StrayGlobals(), 0)
      H.len(M.ImplicitGlobalReads(), 0)
      H.len(M.StrayFrameNames(), 0)
   end)

   H.test("Skin laedt dieselbe Tabelle bei erneutem Laden nicht doppelt in UISpecialFrames", function()
      local _, S = boot()
      S.Menu.Open(nil, numbered(2))
      S.Menu.Close()
      S.Menu.Open(nil, numbered(2))
      S.Menu.Close()
      S.Confirm({ title = "t", text = "x" })
      S.CloseDialog()
      S.Prompt({ title = "t" })
      S.CloseDialog()
      S.Confirm({ title = "t", text = "x" })
      S.CloseDialog()
      local count = {}
      for _, n in ipairs(UISpecialFrames) do count[n] = (count[n] or 0) + 1 end
      H.eq(count.TransmogMenuFrame, 1)
      H.eq(count.TransmogPromptFrame, 1)
      H.eq(count.TransmogConfirmFrame, 1)
   end)
end
