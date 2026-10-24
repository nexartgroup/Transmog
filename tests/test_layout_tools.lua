-- tests/test_layout_tools.lua
-- ---------------------------------------------------------------------------
-- Tests der Werkzeuge tests/layout.lua (Rects/Check/Render), tests/fixtures.lua
-- (Katalog, Serverregeln, Hallo, Antwortschleife) und tests/render_ui.lua
-- (Szenarien, index.html).
--
-- Die Layout-Tests laufen auf kuenstlichen Frame-Baeumen aus Skin-Widgets und
-- einfachen Frames (kein Fenster noetig). Als Gegenprobe dient die Anker-
-- Aufloesung der Attrappe selbst (GetLeft/GetTop ...): ein Zufallsbaum muss mit
-- ihr uebereinstimmen. Die Fixtures-Tests brauchen nur den Kern.
--
-- Aufruf:  cd <Addon>;  luajit tests/run.lua layout_tools
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local Layout = require("layout")
   local Fixtures = require("fixtures")

   -- Verzeichnis dieser Datei (fuer render_ui.lua)
   local TESTS_DIR = (debug.getinfo(1, "S").source or ""):gsub("^@", ""):match("^(.*)[/\\]test_layout_tools%.lua$") or "tests"

   local POINTS = {
      TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
      LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
      BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
   }
   local POINT_NAMES = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

   -- Skin mit den weichen Abhaengigkeiten laden (wie test_skin)
   local MIN_FILES = { "Locales/Locale.lua", "Core/Init.lua", "Core/Util.lua", "UI/Skin.lua" }

   local function boot(world)
      H.install(world and { world = world } or nil)
      M.LoadFiles(MIN_FILES)
      local T = rawget(_G, "Transmog")
      return T, T.UI.Skin
   end

   -- Fester Rahmen mit Groesse und Position (links unten relativ zum Bildschirm)
   local function box(parent, w, h, point, rel, relPoint, x, y)
      local f = CreateFrame("Frame", nil, parent or UIParent)
      f:SetWidth(w)
      f:SetHeight(h)
      f:SetPoint(point or "BOTTOMLEFT", rel or UIParent, relPoint or point or "BOTTOMLEFT", x or 0, y or 0)
      return f
   end

   -- Eintrag zu einem Objekt
   local function entryOf(entries, obj)
      return entries.byFrame[obj]
   end

   local function kinds(problems, kind)
      local out = {}
      for _, p in ipairs(problems) do
         if not kind or p.kind == kind then out[#out + 1] = p end
      end
      return out
   end

   local function firstOf(problems, kind)
      return kinds(problems, kind)[1]
   end

   local function btn(Skin, parent, w, h, label)
      return Skin.Button(parent, w, h, label or "", function() end)
   end

   -- ======================================================================
   H.section("Layout.Rects: Anker und Groessen")
   -- ======================================================================

   H.test("Rects: explizite Groesse, Ursprung oben links, UIParent = Bildschirm", function()
      boot({ screenWidth = 1366, screenHeight = 768 })
      local f = box(UIParent, 200, 100, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 50, 40)
      local e = Layout.Rects(f)
      H.eq(#e, 1)
      local r = e[1]
      H.near(r.x, 50)
      H.near(r.y, 768 - 40 - 100)
      H.near(r.w, 200)
      H.near(r.h, 100)
      H.eq(r.kind, "frame")
      H.eq(r.visible, true)
      H.eq(r.resolved, true)
      H.eq(e.screen.w, 1366)
      H.eq(e.screen.h, 768)
      H.eq(e.byFrame[f], r)
   end)

   H.test("Rects: alle 9 Ankerpunkte x 9 Gegenpunkte stimmen mit Rechnung und Attrappe ueberein", function()
      boot()
      local parent = box(UIParent, 200, 120, "CENTER", UIParent, "CENTER", 0, 0)
      for _, p in ipairs(POINT_NAMES) do
         for _, q in ipairs(POINT_NAMES) do
            local c = CreateFrame("Frame", nil, parent)
            c:SetWidth(40)
            c:SetHeight(20)
            c:SetPoint(p, parent, q, 5, -3)
            local e = Layout.Rects(parent)
            local pe, ce = entryOf(e, parent), entryOf(e, c)
            local fp, fq = POINTS[p], POINTS[q]
            local ax = pe.x + fq[1] * pe.w + 5
            local ayTop = pe.y + (1 - fq[2]) * pe.h - (-3)       -- y nach unten: +3 Versatz nach oben = -3
            local left = ax - fp[1] * 40
            local top = ayTop - (1 - fp[2]) * 20
            H.near(ce.x, left, 1e-6, p .. "->" .. q .. " x")
            H.near(ce.y, top, 1e-6, p .. "->" .. q .. " y")
            H.near(ce.w, 40)
            H.near(ce.h, 20)
            -- Gegenprobe: die Attrappe selbst
            H.near(ce.x, c:GetLeft(), 1e-6, p .. "->" .. q .. " GetLeft")
            H.near(ce.y, 768 - c:GetTop(), 1e-6, p .. "->" .. q .. " GetTop")
            c:Hide()
            c:SetParent(nil)
         end
      end
   end)

   H.test("Rects: zwei Anker bestimmen die Groesse, SetAllPoints, Versatz", function()
      boot()
      local parent = box(UIParent, 300, 200, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 100, 100)
      local c = CreateFrame("Frame", nil, parent)
      c:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -20)
      c:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 40)
      local all = CreateFrame("Frame", nil, parent)
      all:SetAllPoints(parent)
      local tex = parent:CreateTexture(nil, "ARTWORK")
      tex:SetAllPoints()
      local e = Layout.Rects(parent)
      local ce, ae, te = entryOf(e, c), entryOf(e, all), entryOf(e, tex)
      H.near(ce.x, 110)
      H.near(ce.w, 300 - 10 - 30)
      H.near(ce.h, 200 - 20 - 40)
      H.near(ce.y, 768 - (100 + 200) + 20)
      H.eq(ce.sizeFromAnchors, true)
      H.near(ae.w, 300)
      H.near(ae.h, 200)
      H.near(te.w, 300)
      H.near(te.h, 200)
      H.eq(te.region, true)
      H.eq(te.kind, "texture")
   end)

   H.test("Rects: relativeTo Geschwister, Region und relativePoint", function()
      boot()
      local parent = box(UIParent, 400, 200, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
      local a = box(parent, 80, 30, "TOPLEFT", parent, "TOPLEFT", 10, -10)
      local b = CreateFrame("Frame", nil, parent)
      b:SetWidth(50)
      b:SetHeight(30)
      b:SetPoint("LEFT", a, "RIGHT", 6, 0)
      local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      fs:SetText("Hello")
      fs:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -4)
      local icon = parent:CreateTexture(nil, "ARTWORK")
      icon:SetWidth(16)
      icon:SetHeight(16)
      icon:SetPoint("LEFT", fs, "RIGHT", 3, 0)
      local e = Layout.Rects(parent)
      local be, fe, ie = entryOf(e, b), entryOf(e, fs), entryOf(e, icon)
      local ae = entryOf(e, a)
      H.near(be.x, ae.x + ae.w + 6)
      H.near(be.y, ae.y)
      H.near(fe.x, be.x)
      H.near(fe.y, be.y + be.h + 4)
      H.near(ie.x, fe.x + fe.w + 3)
      H.near(ie.y + ie.h / 2, fe.y + fe.h / 2, 1e-6)
   end)

   H.test("Rects: Skalierung je Frame relativ zum Elternteil (und UIParent-Skalierung)", function()
      boot({ uiScale = 1 })
      local parent = box(UIParent, 200, 100, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 100, 100)
      parent:SetScale(2)
      local child = CreateFrame("Frame", nil, parent)
      child:SetWidth(50)
      child:SetHeight(25)
      child:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
      child:SetScale(0.5)
      local e = Layout.Rects(parent)
      local pe, ce = entryOf(e, parent), entryOf(e, child)
      -- Elternteil: Anker (100,100) liegen in UIParent-Einheiten, Groesse x2
      H.near(pe.w, 400)
      H.near(pe.h, 200)
      H.near(pe.scale, 2)
      -- Kind: Skalierung 2 * 0.5 = 1; Versatz (10,-10) gilt in den Einheiten des Kindes
      H.near(ce.scale, 1)
      H.near(ce.w, 50)
      H.near(ce.x, pe.x + 10)
      H.near(ce.y, pe.y + 10)
      -- Gegenprobe: die Attrappe
      H.near(ce.x, child:GetLeft() * child:GetEffectiveScale(), 1e-6)
   end)

   H.test("Rects: UIParent-Skalierung 0.8 wird herausgerechnet (UIParent-Einheiten)", function()
      boot({ screenWidth = 1000, screenHeight = 600, uiScale = 0.8 })
      local f = box(UIParent, 100, 50, "TOPLEFT", UIParent, "TOPLEFT", 10, -20)
      local e = Layout.Rects(f)
      H.near(e[1].x, 10)
      H.near(e[1].y, 20)
      H.near(e[1].w, 100)
      H.near(e[1].h, 50)
      H.near(e[1].scale, 1)
   end)

   H.test("Rects: ohne Anker nicht aufloesbar, Zeichenreihenfolge nach Strata, Level und Ebene", function()
      boot()
      local lone = CreateFrame("Frame", nil, UIParent)
      lone:SetWidth(10)
      lone:SetHeight(10)
      local e = Layout.Rects(lone)
      H.eq(e[1].resolved, false)

      local root = box(UIParent, 300, 300, "CENTER", UIParent, "CENTER", 0, 0)
      root:SetFrameStrata("MEDIUM")
      local hi = box(root, 100, 100, "TOPLEFT", root, "TOPLEFT", 0, 0)
      hi:SetFrameStrata("HIGH")
      local lo = box(root, 100, 100, "TOPLEFT", root, "TOPLEFT", 0, 0)
      lo:SetFrameStrata("LOW")
      local mid = box(root, 100, 100, "TOPLEFT", root, "TOPLEFT", 0, 0)
      local mid2 = box(root, 100, 100, "TOPLEFT", root, "TOPLEFT", 0, 0)
      mid2:SetFrameLevel(mid:GetFrameLevel() + 5)
      local tOverlay = mid:CreateTexture(nil, "OVERLAY")
      local tBg = mid:CreateTexture(nil, "BACKGROUND")
      local tArt = mid:CreateTexture(nil, "ARTWORK")
      for _, t in ipairs({ tOverlay, tBg, tArt }) do
         t:SetWidth(5)
         t:SetHeight(5)
         t:SetPoint("CENTER", mid, "CENTER", 0, 0)
         t:SetTexture(1, 0, 0, 1)
      end
      e = Layout.Rects(root)
      local o = function(obj) return entryOf(e, obj).order end
      H.truthy(o(lo) < o(mid), "LOW unter MEDIUM")
      H.truthy(o(mid) < o(hi), "MEDIUM unter HIGH")
      H.truthy(o(mid) < o(mid2), "hoeheres Level darueber")
      H.truthy(o(root) < o(lo) or o(root) > o(lo), "alle haben eine Ordnung")
      H.truthy(o(mid) < o(tBg), "Regionen nach ihrem Frame")
      H.truthy(o(tBg) < o(tArt), "BACKGROUND < ARTWORK")
      H.truthy(o(tArt) < o(tOverlay), "ARTWORK < OVERLAY")
      H.truthy(o(tOverlay) < o(mid2), "Regionen eines Frames vor Frames mit hoeherem Level")
   end)

   H.test("Rects: Sichtbarkeit; unsichtbare fehlen oder tragen visible=false", function()
      boot()
      local root = box(UIParent, 200, 100, "CENTER", UIParent, "CENTER", 0, 0)
      local a = box(root, 50, 50, "TOPLEFT", root, "TOPLEFT", 0, 0)
      local b = box(a, 20, 20, "TOPLEFT", a, "TOPLEFT", 0, 0)
      local fs = root:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      fs:SetPoint("CENTER", root, "CENTER", 0, 0)
      fs:SetText("x")
      a:Hide()
      local e = Layout.Rects(root)
      H.eq(entryOf(e, a), nil)
      H.eq(entryOf(e, b), nil)
      H.truthy(entryOf(e, fs))
      e = Layout.Rects(root, { includeHidden = true })
      H.eq(entryOf(e, a).visible, false)
      H.eq(entryOf(e, b).visible, false)
      H.eq(entryOf(e, b).shown, true)
      H.eq(entryOf(e, fs).visible, true)
      fs:Hide()
      e = Layout.Rects(root, { includeHidden = true })
      H.eq(entryOf(e, fs).visible, false)
   end)

   H.test("Rects: FontString - natuerliche Breite wie GetStringWidth, Umbruch, Escapes, Ausrichtung", function()
      boot()
      local root = box(UIParent, 300, 200, "CENTER", UIParent, "CENTER", 0, 0)
      local fs = root:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      fs:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -4)
      fs:SetText("Hello World")
      local e = Layout.Rects(root)
      local fe = entryOf(e, fs)
      H.near(fe.w, fs:GetStringWidth(), 1e-6)
      H.near(fe.h, 12)
      H.eq(fe.constrainedW, false)
      H.near(Layout.TextWidth(fs), fs:GetStringWidth(), 1e-6)

      -- mit Breite: umbrechen, Hoehe = Zeilen
      fs:SetWidth(40)
      fs:SetText("Hello World again")
      e = Layout.Rects(root)
      fe = entryOf(e, fs)
      H.eq(fe.constrainedW, true)
      H.near(fe.w, 40)
      H.truthy(#fe.lines >= 3, "umgebrochen")
      H.near(fe.h, #fe.lines * 12)

      -- feste Hoehe: Hoehe bleibt
      fs:SetHeight(14)
      e = Layout.Rects(root)
      H.near(entryOf(e, fs).h, 14)
      H.eq(entryOf(e, fs).explicitH, true)

      -- Escapes zaehlen nicht, Inline-Texturen haben ihre Breite
      local plain = root:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      plain:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -40)
      plain:SetText("Hi")
      local colored = root:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      colored:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -60)
      colored:SetText("|cffff0000Hi|r")
      local icon = root:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      icon:SetPoint("TOPLEFT", root, "TOPLEFT", 4, -80)
      icon:SetText("|TInterface\\MoneyFrame\\UI-GoldIcon:20:20:2:0|t")
      e = Layout.Rects(root)
      H.near(entryOf(e, colored).w, entryOf(e, plain).w, 1e-6)
      H.near(entryOf(e, icon).w, 20, 1e-6)
      H.eq(entryOf(e, plain).justifyH, "CENTER")
      local wrapped, widest = Layout.Wrap("aaa bbb ccc ddd", 10, 40)
      H.truthy(#wrapped >= 2)
      H.truthy(widest <= 40.01)
   end)

   H.test("Rects: implizite Anker (Button-Text/-Texturen, Slider-Daumen, StatusBar, Scroll-Kind)", function()
      boot()
      local root = box(UIParent, 300, 200, "CENTER", UIParent, "CENTER", 0, 0)
      local b = CreateFrame("Button", nil, root)
      b:SetWidth(100)
      b:SetHeight(24)
      b:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
      b:SetNormalFontObject("GameFontNormal")
      b:SetText("OK")
      b:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
      local s = CreateFrame("Slider", nil, root)
      s:SetWidth(100)
      s:SetHeight(16)
      s:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -50)
      s:SetMinMaxValues(0, 10)
      s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
      s:GetThumbTexture():SetWidth(10)
      s:GetThumbTexture():SetHeight(16)
      s:SetValue(10)
      local sb = CreateFrame("StatusBar", nil, root)
      sb:SetWidth(100)
      sb:SetHeight(10)
      sb:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -80)
      sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
      sb:SetMinMaxValues(0, 4)
      sb:SetValue(1)
      local sf = CreateFrame("ScrollFrame", nil, root)
      sf:SetWidth(100)
      sf:SetHeight(60)
      sf:SetPoint("TOPLEFT", root, "TOPLEFT", 150, -10)
      local child = CreateFrame("Frame", nil, sf)
      child:SetWidth(100)
      child:SetHeight(300)
      sf:SetScrollChild(child)
      local inner = CreateFrame("Frame", nil, child)
      inner:SetWidth(40)
      inner:SetHeight(20)
      inner:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -200)
      local e = Layout.Rects(root)
      local be = entryOf(e, b)
      local text = entryOf(e, b:GetFontString())
      local ntex = entryOf(e, b:GetNormalTexture())
      H.truthy(text.resolved, "Button-Text verankert")
      H.near(text.x + text.w / 2, be.x + be.w / 2, 1e-6)
      H.near(ntex.w, 100)
      H.near(ntex.h, 24)
      local thumb = entryOf(e, s:GetThumbTexture())
      H.near(thumb.x, entryOf(e, s).x + 100 - 10, 1e-6)
      local bar = entryOf(e, sb:GetStatusBarTexture())
      H.near(bar.w, 25, 1e-6)
      H.near(bar.h, 10)
      -- Scroll-Kind und Nachkomme: Ausschnitt = ScrollFrame
      local ie = entryOf(e, inner)
      H.truthy(ie.clip, "Ausschnitt")
      H.near(ie.clip.w, 100)
      H.near(ie.clip.h, 60)
      H.eq(entryOf(e, child).resolved, true)
      H.eq(entryOf(e, sf).clip, nil)
   end)

   H.test("Rects: Zufallsbaum stimmt mit der Anker-Aufloesung der Attrappe ueberein", function()
      boot({ screenWidth = 1500, screenHeight = 900, uiScale = 1 })
      local seed = 12345
      local function rnd(n)
         seed = (seed * 1103515245 + 12345) % 2147483648
         return (seed % n) + 1
      end
      local scales = { 0.5, 0.75, 1, 1.25, 2 }
      local objects = { UIParent }
      local frames = {}
      for i = 1, 120 do
         local parent = objects[rnd(#objects)]
         if not parent.GetObjectType or parent:GetObjectType() == "Texture" or parent:GetObjectType() == "FontString" then
            parent = UIParent
         end
         local f = CreateFrame("Frame", nil, parent)
         f:SetWidth(rnd(120) + 10)
         f:SetHeight(rnd(80) + 10)
         f:SetScale(scales[rnd(#scales)])
         local rel = objects[rnd(#objects)]
         local p, q = POINT_NAMES[rnd(9)], POINT_NAMES[rnd(9)]
         f:SetPoint(p, rel, q, rnd(40) - 20, rnd(40) - 20)
         if rnd(4) == 1 then
            -- zweiter Anker auf der Gegenseite bestimmt die Groesse
            f:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", -rnd(10), rnd(10))
            f:SetPoint("TOPLEFT", rel, "TOPLEFT", rnd(10), -rnd(10))
         end
         objects[#objects + 1] = f
         frames[#frames + 1] = f
         if rnd(3) == 1 then
            local t = f:CreateTexture(nil, "ARTWORK")
            t:SetWidth(rnd(30))
            t:SetHeight(rnd(30))
            t:SetPoint(POINT_NAMES[rnd(9)], f, POINT_NAMES[rnd(9)], rnd(10), -rnd(10))
            t:SetTexture(1, 1, 1, 1)
            objects[#objects + 1] = t
            frames[#frames + 1] = t
         end
      end
      local e = Layout.Rects(UIParent)
      local compared = 0
      for _, o in ipairs(frames) do
         local entry = entryOf(e, o)
         local l, r, t, b = o:GetLeft(), o:GetRight(), o:GetTop(), o:GetBottom()
         if entry and l and r and t and b and r >= l and t >= b then
            local eff = (o:GetObjectType() == "Texture") and o:GetParent():GetEffectiveScale() or o:GetEffectiveScale()
            H.truthy(entry.resolved, "aufloesbar")
            H.near(entry.x, l * eff, 1e-6, "x")
            H.near(entry.w, (r - l) * eff, 1e-6, "w")
            H.near(entry.y, 900 - t * eff, 1e-6, "y")
            H.near(entry.h, (t - b) * eff, 1e-6, "h")
            compared = compared + 1
         end
      end
      H.truthy(compared >= 60, "genug Objekte verglichen: " .. compared)
   end)

   -- ======================================================================
   H.section("Layout.Check")
   -- ======================================================================

   H.test("Check: ueberlappende Buttons, aneinanderstossende und 1-px-Ueberlappung nicht", function()
      local _, Skin = boot()
      local root = box(UIParent, 400, 200, "CENTER", UIParent, "CENTER", 0, 0)
      local a = btn(Skin, root, 100, 24, "A")
      a:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
      local touch = btn(Skin, root, 100, 24, "B")
      touch:SetPoint("TOPLEFT", a, "TOPRIGHT", 0, 0)                -- gleiche Kante
      local onePx = btn(Skin, root, 100, 24, "C")
      onePx:SetPoint("TOPLEFT", touch, "TOPRIGHT", -1, 0)           -- 1 px Ueberlappung
      local p = Layout.Check(root)
      H.eq(#kinds(p, "overlap"), 0)
      -- jetzt echte Ueberlappung
      local c = btn(Skin, root, 100, 24, "D")
      c:SetPoint("TOPLEFT", a, "TOPLEFT", 60, -4)
      p = Layout.Check(root)
      local o = kinds(p, "overlap")
      H.truthy(#o >= 1, "Ueberlappung gemeldet")
      H.eq(o[1].severity, "error")
      H.truthy(o[1].otherPath ~= nil)
      H.truthy(o[1].w > 1 and o[1].h > 1)
   end)

   H.test("Check: absichtliche Ueberlagerung (__overlay, Name mit Overlay, Nachfahren) und Nachkommen-Beziehung", function()
      local _, Skin = boot()
      local root = box(UIParent, 400, 200, "CENTER", UIParent, "CENTER", 0, 0)
      local base = btn(Skin, root, 100, 40, "Base")
      base:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
      -- Kind-Button ueber dem Eltern-Button: kein Befund
      local kid = btn(Skin, base, 20, 20, "x")
      kid:SetPoint("TOPRIGHT", base, "TOPRIGHT", -2, -2)
      -- markierte Ueberlagerung
      local flagged = btn(Skin, root, 40, 20, "f")
      flagged:SetPoint("TOPLEFT", base, "TOPLEFT", 5, -5)
      flagged.__overlay = true
      -- Name mit Overlay
      local named = CreateFrame("Button", "TransmogBadgeOverlay", root)
      named:SetWidth(30)
      named:SetHeight(30)
      named:SetPoint("TOPLEFT", base, "TOPLEFT", 50, -5)
      -- Kind einer markierten Ueberlagerung erbt die Ausnahme
      local inherit = btn(Skin, flagged, 20, 10, "i")
      inherit:SetPoint("TOPLEFT", flagged, "TOPLEFT", 0, 0)
      local sibling = btn(Skin, root, 30, 30, "s")
      sibling:SetPoint("TOPLEFT", base, "TOPLEFT", 60, -10)
      local p = Layout.Check(root)
      -- nur das echte Geschwister "sibling" ueberlappt "base" -- und "named"/"flagged" sind ausgenommen
      local o = kinds(p, "overlap")
      for _, x in ipairs(o) do
         H.truthy(x.frame == sibling or x.other == sibling, "nur sibling ueberlappt: " .. x.path .. " / " .. tostring(x.otherPath))
      end
      H.truthy(#o >= 1)
   end)

   H.test("Check: Ueberlappung nur innerhalb einer Wurzel (Menues/Dialoge liegen absichtlich davor)", function()
      local _, Skin = boot()
      local win = box(UIParent, 300, 200, "CENTER", UIParent, "CENTER", 0, 0)
      local a = btn(Skin, win, 100, 24, "A")
      a:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -10)
      local top = box(UIParent, 200, 100, "TOPLEFT", a, "TOPLEFT", 0, 0)
      top:SetFrameStrata("FULLSCREEN_DIALOG")
      local b = btn(Skin, top, 100, 24, "B")
      b:SetPoint("TOPLEFT", top, "TOPLEFT", 5, -5)
      local p = Layout.Check({ win, top })
      H.eq(#kinds(p, "overlap"), 0)
      H.eq(#kinds(p, "covered"), 0)
   end)

   H.test("Check: Kind ueber Eltern-Frame, ueber das Fenster, bewusst ausserhalb verankert, Scroll-Inhalt", function()
      local _, Skin = boot()
      local root = box(UIParent, 300, 200, "CENTER", UIParent, "CENTER", 0, 0)
      Skin.Backdrop(root)
      local panel = box(root, 100, 100, "TOPLEFT", root, "TOPLEFT", 10, -10)
      Skin.Backdrop(panel)
      -- ragt rechts 20 px aus dem Panel (aber im Fenster)
      local wide = CreateFrame("Frame", nil, panel)
      wide:SetWidth(120)
      wide:SetHeight(20)
      wide:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
      Skin.Backdrop(wide)
      -- ragt aus dem Fenster
      local out = CreateFrame("Frame", nil, root)
      out:SetWidth(50)
      out:SetHeight(30)
      out:SetPoint("TOPLEFT", root, "TOPRIGHT", -20, -10)
      out:SetPoint("TOPLEFT", root, "TOPLEFT", 280, -10)
      Skin.Backdrop(out)
      local inside = CreateFrame("Frame", nil, out)
      inside:SetWidth(10)
      inside:SetHeight(10)
      inside:SetPoint("TOPLEFT", out, "TOPLEFT", 2, -2)
      Skin.Backdrop(inside)
      -- bewusst ausserhalb verankert (rechts neben dem Panel): nur "outside-root" moeglich
      local side = CreateFrame("Frame", nil, panel)
      side:SetWidth(30)
      side:SetHeight(30)
      side:SetPoint("LEFT", panel, "RIGHT", 4, 0)
      Skin.Backdrop(side)
      -- Scroll-Frame mit hohem Inhalt: Kind des Scroll-Frames ist ausgenommen
      local sf = CreateFrame("ScrollFrame", nil, root)
      sf:SetWidth(100)
      sf:SetHeight(50)
      sf:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 10, 10)
      local content = CreateFrame("Frame", nil, sf)
      content:SetWidth(100)
      content:SetHeight(500)
      sf:SetScrollChild(content)
      Skin.Backdrop(content)
      local p = Layout.Check(root)
      local parentProblems = kinds(p, "outside-parent")
      local found = {}
      for _, x in ipairs(parentProblems) do found[x.frame] = true end
      H.truthy(found[wide], "wide ragt ueber das Panel")
      H.falsy(found[side], "bewusst ausserhalb verankert")
      H.falsy(found[content], "Scroll-Kind ausgenommen")
      local rootProblems = kinds(p, "outside-root")
      local roots = {}
      for _, x in ipairs(rootProblems) do roots[x.frame] = x end
      H.truthy(roots[out], "out ragt aus dem Fenster")
      H.falsy(roots[inside], "nur das oberste Element melden")
      H.eq(roots[out].severity, "error")
   end)

   H.test("Check: Text - Button-Beschriftung zu lang, passender Text, unteilbares Wort, absichtliches Abschneiden", function()
      local _, Skin = boot()
      local root = box(UIParent, 400, 200, "CENTER", UIParent, "CENTER", 0, 0)
      local ok = btn(Skin, root, 100, 24, "OK")
      ok:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
      local long = btn(Skin, root, 100, 24, "A very long caption that cannot fit")
      long:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -50)
      local word = btn(Skin, root, 60, 24, "Supercalifragilisticexpialidocious")
      word:SetPoint("TOPLEFT", root, "TOPLEFT", 150, -10)
      local fixed = root:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      fixed:SetWidth(60)
      fixed:SetHeight(12)
      fixed:SetPoint("TOPLEFT", root, "TOPLEFT", 150, -60)
      fixed:SetText("Truncated name of an item")
      local free = root:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      free:SetWidth(60)
      free:SetPoint("TOPLEFT", root, "TOPLEFT", 150, -90)
      free:SetText("Paragraph text may grow downwards freely")
      local p = Layout.Check(root)
      local byFrame = {}
      for _, x in ipairs(p) do
         if x.kind == "text-clipped" or x.kind == "text-too-wide" then byFrame[x.frame] = x end
      end
      H.falsy(byFrame[ok.label], "kurzer Text passt")
      H.truthy(byFrame[long.label], "lange Beschriftung")
      H.eq(byFrame[long.label].kind, "text-clipped")
      H.eq(byFrame[long.label].text, "A very long caption that cannot fit")
      H.eq(byFrame[long.label].severity, "warning")
      H.truthy(byFrame[word.label], "unteilbares Wort")
      H.truthy(byFrame[fixed], "feste Hoehe: abgeschnitten")
      H.falsy(byFrame[free], "freie Hoehe darf wachsen")
      -- absichtlich abgeschnitten: nur info
      fixed.__truncate = true
      p = Layout.Check(root)
      local info
      for _, x in ipairs(p) do
         if x.frame == fixed then info = x end
      end
      H.eq(info.severity, "info")
      H.eq(p.counts.info >= 1, true)
      -- Pfadmuster
      fixed.__truncate = nil
      p = Layout.Check(root, { truncateOk = { "FontString#1$" } })
      for _, x in ipairs(p) do
         if x.frame == fixed then info = x end
      end
      H.eq(info.severity, "info")
   end)

   H.test("Check: Groesse null, ohne Anker, unaufloesbar, unsichtbar nicht", function()
      local _, Skin = boot()
      local root = box(UIParent, 300, 200, "CENTER", UIParent, "CENTER", 0, 0)
      local zero = CreateFrame("Button", nil, root)
      zero:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
      local noAnchor = CreateFrame("Frame", nil, root)
      noAnchor:SetWidth(50)
      noAnchor:SetHeight(50)
      Skin.Backdrop(noAnchor)
      local hidden = CreateFrame("Button", nil, root)
      hidden:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -40)
      hidden:Hide()
      local tex = root:CreateTexture(nil, "ARTWORK")
      tex:SetTexture(1, 0, 0, 1)
      tex:SetPoint("TOPLEFT", root, "TOPLEFT", 100, -10)
      local dead = CreateFrame("Frame", nil, UIParent)
      local dependent = CreateFrame("Frame", nil, root)
      dependent:SetWidth(10)
      dependent:SetHeight(10)
      dependent:SetPoint("TOPLEFT", dead, "TOPLEFT", 0, 0)
      Skin.Backdrop(dependent)
      local p = Layout.Check(root)
      local z, u, r = {}, {}, {}
      for _, x in ipairs(p) do
         if x.kind == "zero-size" then z[x.frame] = x end
         if x.kind == "unanchored" then u[x.frame] = x end
         if x.kind == "unresolved" then r[x.frame] = x end
      end
      H.truthy(z[zero], "Button ohne Groesse")
      H.eq(z[zero].severity, "error")
      H.truthy(u[noAnchor], "sichtbarer Frame ohne Anker")
      H.falsy(z[hidden] or u[hidden], "unsichtbar wird nicht geprueft")
      H.truthy(z[tex], "Textur ohne Groesse")
      H.truthy(r[dependent], "Anker auf unaufloesbares Ziel")
   end)

   H.test("Check: mausaktiver Frame ueber einem Widget (covered), darunter nicht", function()
      local _, Skin = boot()
      local root = box(UIParent, 300, 200, "CENTER", UIParent, "CENTER", 0, 0)
      local b = btn(Skin, root, 100, 24, "Below")
      b:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
      local blocker = CreateFrame("Frame", nil, root)
      blocker:SetWidth(120)
      blocker:SetHeight(40)
      blocker:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
      blocker:EnableMouse(true)
      blocker:SetFrameLevel(b:GetFrameLevel() + 5)
      Skin.Backdrop(blocker)
      local p = Layout.Check(root)
      local c = firstOf(p, "covered")
      H.truthy(c, "verdeckt")
      H.eq(c.frame, b)
      H.eq(c.other, blocker)
      -- darunter: kein Befund
      blocker:SetFrameLevel(1)
      b:SetFrameLevel(5)
      p = Layout.Check(root)
      H.eq(#kinds(p, "covered"), 0)
      -- ohne Maus: kein Befund
      blocker:SetFrameLevel(b:GetFrameLevel() + 5)
      blocker:EnableMouse(false)
      p = Layout.Check(root)
      H.eq(#kinds(p, "covered"), 0)
   end)

   H.test("Check: Wurzel ausserhalb des Bildschirms; Zaehler und Format", function()
      local _, Skin = boot({ screenWidth = 800, screenHeight = 600 })
      local root = box(UIParent, 900, 400, "TOPLEFT", UIParent, "TOPLEFT", 0, 0)
      Skin.Backdrop(root)
      local p = Layout.Check(root)
      local o = firstOf(p, "offscreen")
      H.truthy(o)
      H.eq(o.severity, "warning")
      H.eq(p.counts.warning >= 1, true)
      local text = Layout.Format(p)
      H.truthy(text:find("offscreen", 1, true))
      H.eq(Layout.Format({}), "")
   end)

   H.test("Check: eine saubere Skin-Oberflaeche liefert keine Befunde", function()
      local _, Skin = boot()
      local root = box(UIParent, 500, 300, "CENTER", UIParent, "CENTER", 0, 0)
      Skin.Backdrop(root)
      local head = Skin.Header(root, "Transmog")
      local a = btn(Skin, root, 100, 24, "Apply")
      a:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)
      local b = btn(Skin, root, 100, 24, "Cancel")
      b:SetPoint("RIGHT", a, "LEFT", -6, 0)
      local c = Skin.Check(root, "Hide duplicates", function() end)
      c:SetPoint("TOPLEFT", root, "TOPLEFT", 12, -50)
      local e = Skin.EditBox(root, 180, 22, "Search...", function() end)
      e:SetPoint("TOPLEFT", root, "TOPLEFT", 12, -80)
      local s = Skin.Slider(root, 150, 0.6, 1.5, 0.1, function() end)
      s:SetPoint("TOPLEFT", root, "TOPLEFT", 12, -120)
      s:SetValueQuiet(1.2)
      head.title:SetText("Transmog")
      local p = Layout.Check(root)
      H.eq(#p, 0, Layout.Format(p))
      H.eq(p.counts.error, 0)
   end)

   -- ======================================================================
   H.section("Layout.Render und SVG")
   -- ======================================================================

   local function sampleTree(Skin)
      local root = CreateFrame("Frame", "TransmogWindow", UIParent)
      root:SetWidth(420)
      root:SetHeight(260)
      root:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      Skin.Backdrop(root)
      Skin.Header(root, "Transmog <&> \"test\"")
      local a = Skin.Button(root, 100, 24, "Apply", function() end)
      a:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 10)
      a:SetTheme("primary")
      local c = Skin.Check(root, "Hide duplicates", function() end)
      c:SetPoint("TOPLEFT", root, "TOPLEFT", 12, -50)
      c:SetChecked(true)
      local e = Skin.EditBox(root, 180, 22, "Search...", function() end)
      e:SetPoint("TOPLEFT", root, "TOPLEFT", 12, -80)
      e:SetText("caf\195\169 <b>")
      local m = CreateFrame("DressUpModel", nil, root)
      m:SetWidth(100)
      m:SetHeight(160)
      m:SetPoint("TOPRIGHT", root, "TOPRIGHT", -10, -40)
      m:SetUnit("player")
      local icon = root:CreateTexture(nil, "ARTWORK")
      icon:SetWidth(32)
      icon:SetHeight(32)
      icon:SetPoint("TOPLEFT", root, "TOPLEFT", 12, -120)
      icon:SetTexture("Interface\\Icons\\INV_Helmet_08")
      local tint = root:CreateTexture(nil, "OVERLAY")
      tint:SetWidth(20)
      tint:SetHeight(20)
      tint:SetPoint("LEFT", icon, "RIGHT", 6, 0)
      tint:SetTexture("Interface\\Buttons\\WHITE8X8")
      tint:SetVertexColor(1, 0, 0, 0.5)
      local money = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      money:SetPoint("TOPLEFT", root, "TOPLEFT", 12, -170)
      money:SetText("|cff53d17aCost:|r 12|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t 30")
      return root, { apply = a, check = c, edit = e, model = m, icon = icon, tint = tint, money = money }
   end

   H.test("Render: gueltiges SVG mit Backdrop, Text, Titeln, Modell, Symbol-Platzhalter und Escapes", function()
      local _, Skin = boot()
      local root, parts = sampleTree(Skin)
      local svg, info = Layout.Render(root)
      local ok, msg = Layout.ValidateSvg(svg)
      H.truthy(ok, tostring(msg))
      H.truthy(svg:find("^<svg "), "beginnt mit svg")
      H.truthy(svg:find("</svg>", 1, true))
      H.truthy(svg:find("viewBox=", 1, true))
      H.truthy(svg:find("<title>TransmogWindow", 1, true), "Frame-Pfad als Titel")
      H.truthy(svg:find("TransmogWindow/", 1, true))
      H.truthy(svg:find("Apply", 1, true), "Button-Text")
      H.truthy(svg:find("&lt;&amp;&gt;", 1, true), "Escapes im Titel/Text")
      H.truthy(svg:find("&quot;test&quot;", 1, true))
      H.truthy(svg:find("caf\195\169", 1, true), "UTF-8 bleibt")
      H.truthy(svg:find("INV_Helmet_08", 1, true), "Symbol-Dateiname im Titel")
      H.truthy(svg:find("url(#tmhatch)", 1, true), "Modell schraffiert")
      H.truthy(svg:find("model: player", 1, true) or svg:find(">player<", 1, true), "Modell-Einheit als Beschriftung")
      H.truthy(svg:find("#ff0000", 1, true), "Vertexfarbe")
      H.truthy(svg:find("polyline", 1, true), "Haken als Linienzug")
      H.truthy(info.drawn > 10)
      H.eq(info.w >= 420, true)
      -- deterministisch
      local again = Layout.Render(root)
      H.eq(again, svg)
   end)

   H.test("Render: Zeichenreihenfolge, Hintergrund vor Text, Alpha, verborgene Elemente fehlen", function()
      local _, Skin = boot()
      local root = CreateFrame("Frame", "TransmogWindow", UIParent)
      root:SetWidth(200)
      root:SetHeight(100)
      root:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      Skin.Backdrop(root, { 0.1, 0.2, 0.3, 1 }, { 0.9, 0.8, 0.7, 1 })
      local t = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      t:SetPoint("CENTER", root, "CENTER", 0, 0)
      t:SetText("VISIBLE")
      local hidden = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      hidden:SetPoint("TOP", root, "TOP", 0, -2)
      hidden:SetText("HIDDEN")
      hidden:Hide()
      local faint = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      faint:SetPoint("BOTTOM", root, "BOTTOM", 0, 2)
      faint:SetText("FAINT")
      faint:SetAlpha(0.5)
      local svg = Layout.Render(root)
      local iBg = svg:find('fill="#1a334d"', 1, true)
      local iText = svg:find("VISIBLE", 1, true)
      H.truthy(iBg and iText and iBg < iText, "Backdrop vor Text")
      H.falsy(svg:find("HIDDEN", 1, true))
      H.truthy(svg:find('opacity="0.5"', 1, true), "Alpha")
      H.truthy(svg:find('stroke="#e6ccb3"', 1, true), "Rand")
   end)

   H.test("Render: Befunde werden markiert und unten aufgelistet; info nicht; Platz fuer die Legende", function()
      local _, Skin = boot()
      local root = box(UIParent, 200, 100, "CENTER", UIParent, "CENTER", 0, 0)
      Skin.Backdrop(root)
      local a = btn(Skin, root, 80, 24, "One")
      a:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
      local b = btn(Skin, root, 80, 24, "Two")
      b:SetPoint("TOPLEFT", root, "TOPLEFT", 40, -10)
      local p = Layout.Check(root)
      H.truthy(#p >= 1)
      local svg, info = Layout.Render(root, { problems = p })
      H.truthy(svg:find("problem(s)", 1, true))
      H.truthy(svg:find("overlap:", 1, true))
      H.truthy(svg:find('stroke-dasharray="4 2"', 1, true))
      H.truthy(info.h > info.view.h, "Legende vergroessert das Bild")
      local ok, msg = Layout.ValidateSvg(svg)
      H.truthy(ok, tostring(msg))
      -- info-Befunde nicht markiert
      local plain = Layout.Render(root, { problems = { counts = { error = 0, warning = 0, info = 1 },
         { kind = "text-clipped", severity = "info", message = "x", path = "p", x = 0, y = 0, w = 10, h = 10 } } })
      H.falsy(plain:find("text%-clipped"))
   end)

   H.test("Render: Tooltip-Zeilen des GameTooltip erscheinen im Bild", function()
      local _, Skin = boot()
      local root = box(UIParent, 200, 100, "CENTER", UIParent, "CENTER", 0, 0)
      Skin.Backdrop(root)
      local b = btn(Skin, root, 80, 24, "Hover")
      b:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)
      Skin.Tooltip(b, "ANCHOR_RIGHT", { "Item name", { "Second line", 0.5, 1, 0.5 } })
      local svg = Layout.Render(Layout.TopLevel())
      H.truthy(svg:find("Item name", 1, true), "Tooltip-Text im Bild")
      H.truthy(svg:find("Second line", 1, true))
      H.truthy(Layout.ValidateSvg(svg))
   end)

   H.test("Render: mehrere SVGs mit eigenem idPrefix haben keine doppelten ids (inline in einer Seite)", function()
      local _, Skin = boot()
      local root, _ = sampleTree(Skin)
      local s1 = Layout.Render(root, { idPrefix = "a_" })
      local s2 = Layout.Render(root, { idPrefix = "b_" })
      local seen, dup = {}, nil
      for _, s in ipairs({ s1, s2 }) do
         for id in s:gmatch(' id="([^"]+)"') do
            if seen[id] then dup = id end
            seen[id] = true
         end
      end
      H.eq(dup, nil)
      H.truthy(seen["a_hatch"] and seen["b_hatch"])
   end)

   H.test("ValidateSvg: erkennt kaputte Dokumente", function()
      local ok = Layout.ValidateSvg
      H.truthy(ok('<svg a="1"><g><rect x="1"/></g><!-- c --></svg>'))
      H.truthy(ok('<?xml version="1.0"?><svg><text>a &amp; b &#9679;</text></svg>'))
      local cases = {
         { "", "empty" },
         { "<svg><g></svg>", "unbalanced" },
         { "<svg></g></svg>", "closing without open" },
         { "<svg><text>a & b</text></svg>", "bare ampersand" },
         { "<svg><text>a &foo; b</text></svg>", "unknown entity" },
         { "<svg a=1></svg>", "unquoted attribute" },
         { '<svg a="1" a="2"></svg>', "duplicate attribute" },
         { '<svg a="<"></svg>', "lt in attribute" },
         { "<svg></svg><svg></svg>", "two roots" },
         { "<svg><g", "unterminated tag" },
         { "<svg>\1</svg>", "control character" },
         { "<svg><!-- x </svg>", "unterminated comment" },
      }
      for _, c in ipairs(cases) do
         local good, msg = Layout.ValidateSvg(c[1])
         H.eq(good, false, c[2])
         H.truthy(type(msg) == "string" and #msg > 0, c[2] .. ": message")
      end
   end)

   H.test("Escape: Steuerzeichen entfernt, Sonderzeichen ersetzt", function()
      H.eq(Layout.Escape("a<b>&\"c\1d"), "a&lt;b&gt;&amp;&quot;cd")
   end)

   H.test("TopLevel: sichtbare Addon-Frames unter UIParent (unbenannt oder Transmog...)", function()
      boot()
      local named = CreateFrame("Frame", "TransmogWindow", UIParent)
      local anon = CreateFrame("Frame", nil, UIParent)
      local hidden = CreateFrame("Frame", "TransmogHidden", UIParent)
      hidden:Hide()
      CreateFrame("Frame", "SomeOtherAddonFrame", UIParent)
      local top = Layout.TopLevel()
      local set = {}
      for _, f in ipairs(top) do set[f] = true end
      H.truthy(set[named])
      H.truthy(set[anon])
      H.falsy(set[hidden])
      H.falsy(set[rawget(_G, "SomeOtherAddonFrame")])
      H.falsy(set[rawget(_G, "ChatFrame1")])
   end)

   -- ======================================================================
   H.section("Fixtures")
   -- ======================================================================

   local function fixtureBoot(opts)
      local T = Fixtures.Boot(H, opts)
      H.truthy(T and T.State, "Addon geladen")
      return T
   end

   H.test("Fixtures.Boot: Katalog ~150 Items, Qualitaeten 0-7, Ausruestung der 14 Slots, Welt", function()
      local T = fixtureBoot({ screen = { w = 1920, h = 1080 }, money = 123456789, race = "Orc", class = "SHAMAN" })
      local cat = Fixtures.Catalog(T)
      H.truthy(cat.count >= 140 and cat.count <= 200, "Katalogumfang " .. cat.count)
      local seen = {}
      for _, rec in ipairs(cat.list) do seen[rec.quality] = true end
      for q = 0, 7 do H.truthy(seen[q], "Qualitaet " .. q) end
      H.eq(M.world.screenWidth, 1920)
      H.eq(M.world.screenHeight, 1080)
      H.eq(GetMoney(), 123456789)
      H.eq(select(2, UnitRace("player")), "Orc")
      H.eq(select(2, UnitClass("player")), "SHAMAN")
      for _, slot in ipairs(Fixtures.SERVER_SLOTS) do
         H.eq(T.State.SlotState(slot), "READY", "Slot " .. slot)
         local eq = T.State.Equipped(slot)
         H.truthy(eq and eq.id, "Ausruestung " .. slot)
         H.truthy(eq.icon and eq.icon:find("Interface\\Icons\\", 1, true), "echter Symbolpfad")
      end
      H.eq(GetInventoryItemLink("player", 2) ~= nil, true, "Hals angelegt")
      -- typeKey: Platte
      H.eq(T.State.Equipped(0).typeKey, 404)
      H.eq(T.State.Equipped(15).typeKey, 207)
      H.eq(T.State.Equipped(16).typeKey, 406)
      H.eq(#M.errors, 0)
   end)

   H.test("Fixtures.Boot: deDE mit deutschen Typnamen, Itemnamen und Auktionslisten", function()
      local T = fixtureBoot({ locale = "deDE", equipmentSet = "cloth" })
      H.eq(GetLocale(), "deDE")
      local eq = T.State.Equipped(0)
      H.eq(eq.name, "Kapuze des umherziehenden Magisters")
      local info = T.Items.Info(eq.id)
      H.eq(info.typeName, "R\195\188stung")
      H.eq(info.subtypeName, "Stoff")
      H.eq(info.typeKey, 401)
      H.eq(T.Items.TypeLabel(404), "Platte")
      -- Mage: Stab in der Haupthand, Nebenhand leer
      H.eq(T.State.SlotState(16), "EMPTY")
      H.eq(T.State.Equipped(15).typeKey, 210)
      H.eq(select(2, UnitClass("player")), "MAGE")
   end)

   H.test("Fixtures.Boot: equipmentSet dualwield und ungueltige Argumente", function()
      local T = fixtureBoot({ equipmentSet = "dualwield" })
      H.eq(T.State.Equipped(15).equipLoc, "INVTYPE_WEAPONMAINHAND")
      H.eq(T.State.Equipped(16).equipLoc, "INVTYPE_WEAPONOFFHAND")
      H.throws(function() Fixtures.Boot(H, { locale = "frFR" }) end, "locale")
      H.throws(function() Fixtures.Boot(H, { equipmentSet = "nope" }) end, "equipmentSet")
   end)

   H.test("Fixtures laufen mit dem Kern allein (ohne UI, Features und Boot)", function()
      local T = Fixtures.Boot(H, { upTo = "Core\\Outfits.lua" })
      H.eq(T.UI and T.UI.Window, nil)
      H.eq(T.Boot, nil)
      H.truthy(T.DB.global and T.DB.char, "Ablauf von Boot nachgebildet")
      H.eq(#T.Slots.LIST, 14)
      local srv = Fixtures.ServerHello(T)
      H.truthy(T.State.ListsReady())
      H.eq(T.Net.state, "OK")
      H.truthy(T.State.Applied(0) ~= 0)
      Fixtures.ServerAutoReply(T)
      T.Net.RequestStatus()
      Fixtures.Settle(T, 0.3)
      H.truthy(#srv.log >= 1)
      H.eq(Fixtures.OpenAtNpc(T), nil)
      H.eq(#M.errors, 0)
   end)

   H.test("Fixtures.ServerHello: Status (angewendet, verborgen, inaktiv) und 14 Listenstroeme", function()
      local T = fixtureBoot()
      local srv = Fixtures.ServerHello(T)
      H.eq(T.Net.state, "OK")
      H.eq(T.State.StatusKnown(), true)
      H.truthy(T.State.ListsReady(), "alle 14 Listen fertig")
      H.eq(#M.errors, 0)
      -- angewendet
      H.truthy(T.State.Applied(0) ~= 0 and T.State.Applied(0) ~= 999999)
      H.truthy(T.State.Applied(2) ~= 0)
      H.eq(T.State.Applied(14), 999999, "Ruecken verborgen")
      -- inaktiv: gespeichert, aber nicht in der Liste
      H.truthy(T.State.Applied(6) ~= 0)
      H.eq(T.State.IsInactive(6), true)
      H.eq(T.State.Baseline(6), 0)
      H.eq(T.State.IsInactive(0), false)
      -- Listen = Serverliste; Qualitaet absteigend, dann englischer Name; Bucket Klasse+Unterklasse
      local cat = Fixtures.Catalog(T)
      for _, slot in ipairs(Fixtures.SERVER_SLOTS) do
         local ids, bucket = Fixtures.List(T, slot)
         local list = T.State.List(slot)
         H.deepEq(list.ids, ids, "Liste Slot " .. slot)
         H.eq(list.bucket, bucket)
         H.eq(list.amount, #ids)
         H.eq(list.ready, true)
         for i = 2, #ids do
            local a, b = cat.byId[ids[i - 1]], cat.byId[ids[i]]
            H.truthy(a.quality > b.quality or (a.quality == b.quality and a.nameEN <= b.nameEN), "Sortierung")
         end
         local eqId = M.world.equipment[slot + 1]
         for _, id in ipairs(ids) do
            H.truthy(id ~= eqId, "nicht der angelegte Gegenstand")
            H.truthy(cat.byId[id].icon ~= cat.byId[eqId].icon, "nicht dasselbe Aussehen")
         end
      end
      H.eq(T.State.List(0).bucket, 4 + 4)          -- Platte: Ruestung 4 + Unterklasse 4
      H.eq(T.State.List(15).bucket, 2 + 7)         -- Einhandschwert
      -- Stroeme in Stuecken zu hoechstens 20 IDs: Kopf hat mehr als 20? sonst Teilstueck pruefen
      for _, m in ipairs(srv.StreamMessages(0)) do
         local chunk = m:match("^AvailableTransmogs:0:%d+:%d+:(.*)$")
         H.truthy(chunk, "Format")
         if chunk ~= "start" and chunk ~= "end" then
            local n = 0
            for _ in chunk:gmatch("%d+") do n = n + 1 end
            H.truthy(n <= 20)
         end
      end
   end)

   H.test("Fixtures.ServerHello: Strom in Stuecken zu 20 (grosse Liste) und Optionen", function()
      local T = fixtureBoot({ equipmentSet = "dualwield" })
      local srv = Fixtures.ServerHello(T, { rules = { mixedWeapons = 2, mixedHandedness = true },
         applied = { [15] = 1 }, hidden = {}, inactive = {} })
      local msgs = srv.StreamMessages(15)
      local chunks = 0
      for _, m in ipairs(msgs) do
         local c = m:match("^AvailableTransmogs:15:%d+:%d+:(.*)$")
         if c ~= "start" and c ~= "end" then chunks = chunks + 1 end
      end
      local ids = Fixtures.List(T, 15)
      H.truthy(#ids > 20, "mehr als 20 Eintraege: " .. #ids)
      H.eq(chunks, math.ceil(#ids / 20))
      H.eq(T.State.List(15).amount, #ids)
      H.eq(T.State.Applied(14), 0, "kein verborgener Slot bei hidden = {}")
      H.eq(T.State.Applied(15), ids[1])
      H.eq(#M.errors, 0)
   end)

   H.test("Server-Regeln: Stufen, Klassen, Fraktion, Aussehen, Fernkampf, Brust/Robe", function()
      local T = fixtureBoot({ race = "Human", class = "WARRIOR" })
      local cat = Fixtures.Catalog(T)
      local function names(slot)
         local out = {}
         for _, id in ipairs((Fixtures.List(T, slot))) do out[cat.byId[id].subName .. "/" .. cat.byId[id].inv] = true end
         return out
      end
      -- niedrigere Stufen erlaubt (Standard): Kopf enthaelt alle vier Stufen
      local head = names(0)
      H.truthy(head["Plate/INVTYPE_HEAD"] and head["Mail/INVTYPE_HEAD"] and head["Leather/INVTYPE_HEAD"]
         and head["Cloth/INVTYPE_HEAD"], "alle Stufen")
      -- ohne niedrigere Stufen nur Platte
      Fixtures.ServerHello(T, { rules = { lowerTiers = false } })
      for _, id in ipairs((Fixtures.List(T, 0))) do H.eq(cat.byId[id].sub, "plate") end
      -- Klassengebundene Krone nur fuer Paladine
      local crown = Fixtures.Item(T, "e_head_plate") and nil
      local function hasCrown(list)
         for _, id in ipairs(list) do
            if cat.byId[id].nameEN == "Crown of the Fallen Paladin" then return true end
         end
         return false
      end
      H.falsy(hasCrown((Fixtures.List(T, 0))))
      local P = fixtureBoot({ class = "PALADIN", rules = nil })
      Fixtures.ServerHello(P, { rules = { lowerTiers = false } })
      local catP = Fixtures.Catalog(P)
      local found = false
      for _, id in ipairs((Fixtures.List(P, 0))) do
         if catP.byId[id].nameEN == "Crown of the Fallen Paladin" then found = true end
      end
      H.truthy(found, "Paladin sieht die Krone")
      -- Fraktion: Wappenrock von Orgrimmar nur fuer die Horde
      local O = fixtureBoot({ race = "Orc" })
      local catO = Fixtures.Catalog(O)
      local hordeTabard, allyTabard = false, false
      for _, id in ipairs((Fixtures.List(O, 18))) do
         if catO.byId[id].faction == "H" then hordeTabard = true end
         if catO.byId[id].faction == "A" then allyTabard = true end
      end
      H.truthy(hordeTabard)
      H.falsy(allyTabard)
      -- Fernkampf: Bogen/Schusswaffen/Armbrust, keine Zauberstaebe oder Wurfwaffen
      local Wt = fixtureBoot({})
      local catW = Fixtures.Catalog(Wt)
      local subs = {}
      for _, id in ipairs((Fixtures.List(Wt, 17))) do subs[catW.byId[id].sub] = true end
      H.truthy(subs.bow and subs.gun and subs.crossbow)
      H.falsy(subs.wand or subs.thrown)
      -- ein Magier sieht keine Platte, auch ohne niedrigere Stufen (Fertigkeit fehlt)
      local Mg = fixtureBoot({ equipmentSet = "cloth" })
      local catM = Fixtures.Catalog(Mg)
      for _, id in ipairs((Fixtures.List(Mg, 0))) do H.eq(catM.byId[id].sub, "cloth") end
      local ids = Fixtures.List(Mg, 0)
      H.truthy(#ids >= 1)
      H.falsy(crown)
   end)

   H.test("Fixtures.ServerAutoReply: Status, Listen, Kosten, Apply/Remove/RemoveAll, Sammlung", function()
      local T = fixtureBoot()
      local srv = Fixtures.ServerAutoReply(T, { price = 25000 })
      local events = {}
      local function on(name)
         T.Events.On(name, function(...) events[#events + 1] = { name = name, ... } end, events)
      end
      for _, n in ipairs({ "APPLY_PROGRESS", "APPLY_DONE", "COST_CHANGED", "STATUS_CHANGED", "LIST_READY" }) do on(n) end
      T.State.chatMessages = false
      T.State.SetVendor(true)

      -- Anfrage -> Antwort mit Latenz
      T.Net.RequestStatus()
      T.Net.RequestLists()
      H.eq(T.State.StatusKnown(), false, "noch keine Antwort ohne Zeit")
      Fixtures.Settle(T, 0.5)
      H.eq(T.State.StatusKnown(), true)
      H.truthy(T.State.ListsReady())
      H.eq(T.Net.state, "OK")
      H.truthy(M.CountSent("GetAvailableTransmogs") >= 1)

      -- Auswahl, Kosten, Anwenden
      local ids = Fixtures.List(T, 0)
      H.truthy(T.State.Select(0, ids[1]))
      H.truthy(T.State.Select(2, (Fixtures.List(T, 2))[1]))
      Fixtures.Settle(T, 0.6)
      local cost = T.State.Cost()
      H.eq(cost.valid, true)
      H.eq(cost.copper, 50000)
      H.eq(cost.canPurchase, true)
      local before = GetMoney()
      H.truthy(T.State.Apply())
      Fixtures.Settle(T, 1.0)
      H.eq(GetMoney(), before - 50000)
      H.eq(T.State.Applied(0), ids[1])
      H.eq(T.State.PendingCount(), 0)
      H.eq(srv.stored[0], ids[1])
      H.eq(#M.errors, 0)

      -- konfigurierbarer Fehlschlag: Auswahl bleibt, Geld unveraendert
      local ids2 = Fixtures.List(T, 4)
      H.truthy(T.State.Select(4, ids2[1]))
      Fixtures.Settle(T, 0.6)
      srv.failApply = 1
      before = GetMoney()
      H.truthy(T.State.Apply())
      Fixtures.Settle(T, 1.0)
      H.eq(GetMoney(), before)
      H.eq(T.State.HasPending(4), true)
      local failed = false
      for _, ev in ipairs(events) do
         if ev.name == "APPLY_PROGRESS" and ev[1] == 4 and ev[2] == false then failed = true end
      end
      H.truthy(failed, "APPLY_PROGRESS(4, false)")

      -- abgelehntes Aussehen
      srv.reject[ids2[1]] = true
      H.truthy(T.State.Apply())
      Fixtures.Settle(T, 1.0)
      H.eq(T.State.HasPending(4), true)
      srv.reject[ids2[1]] = nil

      -- verborgen kostet nichts
      T.State.DiscardAll()
      H.truthy(T.State.Select(5, 999999))
      Fixtures.Settle(T, 0.6)
      H.eq(T.State.Cost().copper, 0)
      before = GetMoney()
      H.truthy(T.State.Apply())
      Fixtures.Settle(T, 1.0)
      H.eq(GetMoney(), before)
      H.eq(T.State.Applied(5), 999999)

      -- Entfernen (Auswahl 0) und alles entfernen
      T.State.DiscardAll()
      H.truthy(T.State.Select(0, 0))
      H.truthy(T.State.Apply())
      Fixtures.Settle(T, 1.0)
      H.eq(T.State.Applied(0), 0)
      H.truthy(T.State.RemoveAll())
      Fixtures.Settle(T, 1.0)
      H.eq(T.State.Applied(2), 0)
      H.eq(T.State.Applied(5), 0)
      H.eq(next(srv.stored), nil)

      -- Sammlungsstatus
      local collected = ids[1]
      local uncollected
      T.Net.QueryCollection(collected)
      Fixtures.Settle(T, 0.3)
      H.eq(T.Net.CollectionState(collected), 1)
      local cat = Fixtures.Catalog(T)
      for _, rec in ipairs(cat.list) do
         if rec.uncollected then uncollected = rec.id break end
      end
      T.Net.QueryCollection(uncollected)
      T.Net.QueryCollection(49000)
      Fixtures.Settle(T, 0.3)
      H.eq(T.Net.CollectionState(uncollected), 0)
      H.eq(T.Net.CollectionState(49000), 2, "nicht transmogbar")
      H.eq(#M.errors, 0)
   end)

   H.test("Fixtures.ServerAutoReply: stummer Server -> ABSENT nach 8 s; ServerStop; Mute-Option", function()
      local T = fixtureBoot()
      local srv = Fixtures.ServerAutoReply(T, { mute = true })
      T.Net.RequestStatus()
      Fixtures.Settle(T, 9)
      H.eq(T.Net.state, "ABSENT")
      H.truthy(#srv.log >= 1)
      H.eq(srv.log[1], "GetTransmogStatus")
      -- Server meldet sich wieder
      srv.mute = false
      T.Net.RequestStatus()
      Fixtures.Settle(T, 0.5)
      H.eq(T.Net.state, "OK")
      -- ServerStop: keine Antworten mehr
      Fixtures.ServerStop(T)
      local n = #srv.log
      T.Net.RequestStatus()
      Fixtures.Settle(T, 0.5)
      H.eq(#srv.log, n)
      H.eq(#M.errors, 0)
   end)

   H.test("Fixtures.OpenAtNpc: Open + GOSSIP_SHOW; Equip/Unequip/Collect/Cost/Uncache/Looks", function()
      local T = fixtureBoot()
      Fixtures.ServerAutoReply(T)
      local window = Fixtures.OpenAtNpc(T)
      H.truthy(T.State.serverOpenAt ~= nil or T.State.openedByNpc, "Open wurde verarbeitet")
      if T.UI.Window then
         H.truthy(window ~= nil, "Fenster geoeffnet")
         H.eq(T.UI.Window.IsShown() and true or false, true)
         H.eq(T.State.atVendor, true)
      else
         H.eq(window, nil)
      end

      -- Ausruestung wechseln und leeren
      local tabard = T.State.Equipped(18).id
      Fixtures.Unequip(T, 18)
      H.eq(T.State.SlotState(18), "EMPTY")
      Fixtures.Equip(T, 18, tabard)
      H.eq(T.State.SlotState(18), "READY")
      Fixtures.Equip(T, 0, "e_head_cloth")
      H.eq(T.State.Equipped(0).id, Fixtures.Item(T, "e_head_cloth"))

      -- Sammeln: CollectionUpdated erreicht die Bus-Ereignisse
      local got
      T.Events.On("COLLECTION_UPDATED", function(id) got = id end, T)
      local cat = Fixtures.Catalog(T)
      local unc
      for _, rec in ipairs(cat.list) do
         if rec.uncollected then unc = rec.id break end
      end
      Fixtures.Collect(T, unc)
      H.eq(got, unc)
      H.eq(Fixtures.Server(T).collected[unc], true)
      H.eq(Fixtures.CollectionStatus(T, unc), 1)

      -- Kosten abspielen: Verborgen kostet 0
      local msg = Fixtures.Cost(T, { { 0, 41000 }, { 2, 999999 } })
      H.eq(msg, "TransmogCost:100000:1")

      -- Looks und Uncache
      local looks = Fixtures.Looks(T, 1)
      H.truthy(looks[0] and looks[15])
      local n, total = Fixtures.Uncache(T, 1)
      H.eq(n, total)
      H.eq(M.IsCached(41000), false)
      H.eq(#M.errors, 0)
   end)

   -- ======================================================================
   H.section("render_ui")
   -- ======================================================================

   local function loadRenderUi()
      return dofile(TESTS_DIR .. "/render_ui.lua")
   end

   H.test("render_ui als Modul: Szenarien vollstaendig und benannt", function()
      local R = loadRenderUi()
      local want = { "default", "min", "large", "scale15", "german", "outfits-tab", "options", "menu-type",
                     "loading", "empty-slot", "preview-mode", "server-absent", "toast" }
      for _, n in ipairs(want) do
         H.truthy(R.Scenarios[n], "Szenario " .. n)
         H.eq(type(R.Scenarios[n].run), "function")
         H.eq(type(R.Scenarios[n].title), "string")
      end
      H.truthy(R.Scenarios["skin-demo"])
      H.eq(#R.Order >= #want + 1, true)
   end)

   H.test("render_ui: skin-demo rendert ohne Fenster-Module (gueltiges SVG, Befunde, Elementzahl)", function()
      local R = loadRenderUi()
      local res = R.RunScenario("skin-demo", { H = H, Fixtures = Fixtures, Layout = Layout })
      H.eq(res.status, "ok", tostring(res.reason))
      H.truthy(Layout.ValidateSvg(res.svg))
      H.truthy(res.info.drawn > 100, "viele Elemente: " .. tostring(res.info.drawn))
      H.eq(res.problems.counts.error, 0, Layout.Format(res.problems))
      H.eq(res.handlerErrors, 0)
      H.truthy(res.svg:find("Apply", 1, true))
      H.truthy(res.svg:find("TransmogSkinDemo", 1, true))
      -- das Menue (zweite Wurzel) ist mit im Bild
      H.truthy(res.svg:find("Item level", 1, true))
   end)

   H.test("render_ui: fehlende Module ergeben SKIP statt Fehler; unbekanntes Szenario", function()
      local R = loadRenderUi()
      R.Scenarios["x-needs-window"] = {
         title = "needs UI.Window", needs = { "UI.Window" },
         run = function(c)
            c.boot({ skip = { ["UI\\Window.lua"] = true }, hello = false, reply = false })
            c.need("UI.Window")
         end,
      }
      local res = R.RunScenario("x-needs-window", { H = H, Fixtures = Fixtures, Layout = Layout })
      H.eq(res.status, "skip")
      H.truthy(res.reason:find("module missing", 1, true))
      H.truthy(res.reason:find("UI.Window", 1, true))
      R.Scenarios["x-needs-window"] = nil
      local unknown = R.RunScenario("no-such-scenario", { H = H, Fixtures = Fixtures, Layout = Layout })
      H.eq(unknown.status, "error")
      -- Fehler im Szenario werden gemeldet, nicht geworfen
      R.Scenarios["x-boom"] = { title = "boom", run = function() error("kaputt") end }
      local boom = R.RunScenario("x-boom", { H = H, Fixtures = Fixtures, Layout = Layout })
      H.eq(boom.status, "error")
      H.truthy(boom.reason:find("kaputt", 1, true))
      R.Scenarios["x-boom"] = nil
   end)

   H.test("render_ui: Szenarien mit Fenster laufen oder werden uebersprungen (nie ein Fehler)", function()
      local R = loadRenderUi()
      for _, name in ipairs({ "default", "min", "german", "preview-mode", "loading", "toast", "options" }) do
         local res = R.RunScenario(name, { H = H, Fixtures = Fixtures, Layout = Layout })
         H.truthy(res.status == "ok" or res.status == "skip", name .. ": " .. tostring(res.status) .. " " .. tostring(res.reason))
         if res.status == "ok" then
            H.truthy(Layout.ValidateSvg(res.svg), name .. ": SVG")
            H.eq(res.handlerErrors, 0, name .. ": Handlerfehler " .. tostring(res.firstHandlerError))
         end
      end
   end)

   H.test("render_ui: index.html bettet die SVGs ein und nennt Befunde und uebersprungene Szenarien", function()
      local R = loadRenderUi()
      local dir = os.tmpname()
      os.remove(dir)
      os.execute('mkdir -p "' .. dir .. '"')
      local res = R.RunScenario("skin-demo", { H = H, Fixtures = Fixtures, Layout = Layout })
      H.eq(res.status, "ok")
      local f = assert(io.open(dir .. "/skin-demo.svg", "wb"))
      f:write(res.svg)
      f:close()
      local skipped = { name = "toast", status = "skip", reason = "module missing (Toasts)" }
      H.truthy(R.WriteIndex(dir, { res, skipped }, "test"))
      local idx = assert(io.open(dir .. "/index.html", "rb"))
      local html = idx:read("*a")
      idx:close()
      H.truthy(html:find("<svg ", 1, true), "SVG eingebettet")
      H.truthy(html:find('id="skin-demo"', 1, true))
      H.truthy(html:find("module missing (Toasts)", 1, true))
      H.truthy(html:find("layout check: 0 error(s), 0 warning(s)", 1, true))
      os.execute('rm -rf "' .. dir .. '"')
   end)

   H.test("render_ui: --root rendert nur den benannten Frame", function()
      local R = loadRenderUi()
      local res = R.RunScenario("skin-demo", { H = H, Fixtures = Fixtures, Layout = Layout, rootName = "TransmogSkinDemo" })
      H.eq(res.status, "ok", tostring(res.reason))
      H.falsy(res.svg:find("Item level", 1, true), "das Menue gehoert nicht zur Wurzel")
      H.truthy(res.svg:find("Apply", 1, true))
      local bad = R.RunScenario("skin-demo", { H = H, Fixtures = Fixtures, Layout = Layout, rootName = "NoSuchFrame" })
      H.eq(bad.status, "error")
      H.truthy(bad.reason:find("NoSuchFrame", 1, true))
   end)

   H.test("render_ui als Skript: --list, ein Szenario in ein Verzeichnis, index.html, Exit-Code 0", function()
      local exe = (arg and arg[-1]) or "luajit"
      local script = TESTS_DIR .. "/render_ui.lua"
      local dir = os.tmpname()
      os.remove(dir)
      os.execute('mkdir -p "' .. dir .. '"')
      local p = io.popen('"' .. exe .. '" "' .. script .. '" --list 2>&1')
      local listing = p:read("*a")
      p:close()
      H.truthy(listing:find("skin%-demo"), "Liste: " .. listing:sub(1, 80))
      H.truthy(listing:find("default"))
      p = io.popen('"' .. exe .. '" "' .. script .. '" skin-demo --out "' .. dir .. '" 2>&1; echo "exit=$?"')
      local out = p:read("*a")
      p:close()
      H.truthy(out:find("OK   skin%-demo"), out)
      H.truthy(out:find("exit=0", 1, true), out)
      local svg = io.open(dir .. "/skin-demo.svg", "rb")
      H.truthy(svg, "SVG geschrieben")
      if svg then
         local text = svg:read("*a")
         svg:close()
         H.truthy(Layout.ValidateSvg(text))
      end
      local idx = io.open(dir .. "/index.html", "rb")
      H.truthy(idx, "index.html geschrieben")
      if idx then idx:close() end
      p = io.popen('"' .. exe .. '" "' .. script .. '" no-such-scenario 2>&1; echo "exit=$?"')
      out = p:read("*a")
      p:close()
      H.truthy(out:find("exit=2", 1, true), out)
      os.execute('rm -rf "' .. dir .. '"')
   end)
end
