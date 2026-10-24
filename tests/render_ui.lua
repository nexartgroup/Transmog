-- tests/render_ui.lua
-- ---------------------------------------------------------------------------
-- Rendert die Oberflaeche des Addons ohne Spielclient nach SVG.
--
--    cd <Addon>
--    luajit tests/render_ui.lua [Szenario ...] [--out DIR] [Optionen]
--
-- Ohne Szenarioname laufen alle. Je Szenario entsteht tests/out/<name>.svg
-- (Standardverzeichnis, mit --out aenderbar) und eine Seite tests/out/index.html,
-- die alle SVGs eingebettet zeigt (mit den Befunden von Layout.Check darunter).
-- Die Dateien lassen sich im Browser oeffnen; ueber den Objekten stehen die
-- Pfade (Mouseover-Titel), Symbole sind farbige Platzhalter mit Dateinamen.
--
-- Optionen
--    --list             Szenarien auflisten und beenden
--    --lang CODE        Sprache der Addon-Texte (enUS deDE frFR esES ruRU koKR zhCN zhTW) oder "all"
--                       (alle acht, nacheinander); die Dateien heissen dann <name>.<CODE>.svg
--    --out DIR          Ausgabeverzeichnis
--    --no-index         index.html nicht schreiben
--    --root NAME        nur diesen Frame samt Unterbaum rendern (z. B. TransmogWindow); Standard:
--                       alle sichtbaren Addon-Frames (Fenster, Menues, Dialoge, Toasts)
--    --no-problems      Befunde nicht in die SVGs zeichnen
--    --strict           ueberspringen (fehlende Module) gilt als Fehler
--    --fail-on-errors   Befunde der Schwere "error" (Layout.Check) lassen den Aufruf fehlschlagen
--    -v                 alle Befunde ausgeben
--
-- Ein Szenario ist eine Tabelle { title =, needs = { "UI.Window" ... }, run = function(c) }.
-- c bietet (siehe makeContext): boot, openNpc, openPreview, settle, setting, click,
-- findButton, need, T, M. Fehlen Module (needs oder c.need), wird das Szenario
-- uebersprungen:  SKIP <name>: module missing (UI.Window).
-- Szenarien benutzen ausschliesslich die oeffentliche Schnittstelle aus SPEC 11.
--
-- Als Modul (z. B. aus Tests): local R = dofile("tests/render_ui.lua")
--    R.Scenarios, R.Order, R.RunScenario(name, env) -> result, R.WriteIndex(dir, results)
--    R.Languages = { "enUS", "deDE", ... }  (die acht Addon-Sprachen)
--    env = { H = Runner-H (mit .mock und .boot), Fixtures =, Layout =,
--            addonLocale = Sprachcode der Addon-Texte (optional) }.
-- Als Skript wird die Datei erkannt, wenn arg[0] auf render_ui.lua endet.
-- ---------------------------------------------------------------------------

local R = {}

local sfmt, sfind, ssub, sgsub = string.format, string.find, string.sub, string.gsub
local tinsert, tconcat, tsort = table.insert, table.concat, table.sort

local isCli = type(arg) == "table" and type(arg[0]) == "string" and sfind(arg[0], "render_ui%.lua$") ~= nil

-- Verzeichnis dieser Datei (tests/)
local function thisDir()
   local src = debug.getinfo(1, "S").source or ""
   src = sgsub(src, "^@", "")
   return src:match("^(.*)[/\\]render_ui%.lua$") or "."
end
local TESTS_DIR = thisDir()
R.dir = TESTS_DIR

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------

-- Pfad "UI.Window" in der Addon-Tabelle nachschlagen
local function lookup(T, path)
   local o = T
   for part in path:gmatch("[^%.]+") do
      if type(o) ~= "table" then return nil end
      o = o[part]
   end
   return o
end

local function skip(reason)
   error({ skip = reason }, 0)
end

-- Sichtbare Buttons unterhalb von root, deren Text zu pattern (Lua-Muster) passt
local function findButtons(M, root, pattern)
   local out = {}
   if not root then return out end
   M.Walk(root, function(o)
      if rawget(o, "__type") == "Button" or rawget(o, "__type") == "CheckButton" then
         if M.U.isVisible(o) then
            -- Skin-Buttons haben GetText() (liefert das Label); sonst der FontString des Buttons
            local ok, text = pcall(function() return o:GetText() end)
            if not ok or text == nil then
               local fs = rawget(o, "__fontString") or rawget(o, "label")
               text = type(fs) == "table" and rawget(fs, "__text") or nil
            end
            if type(text) == "string" and sfind(text, pattern) then out[#out + 1] = o end
         end
      end
   end)
   return out
end

-- Kontext fuer ein Szenario
local function makeContext(env)
   local H, M = env.H, env.H.mock
   local Fixtures, Layout = env.Fixtures, env.Layout
   local c = { H = H, M = M, Fixtures = Fixtures, Layout = Layout, meta = {}, skip = skip }

   -- Addon starten (Fixtures.Boot) und Server anbinden
   --   opts: wie Fixtures.Boot; opts.hello = false (kein ServerHello), opts.reply = false (keine
   --   Antwortschleife), opts.mute = true (Server schweigt)
   function c.boot(opts)
      opts = opts or {}
      if opts.addonLocale == nil then opts.addonLocale = env.addonLocale end
      c.T = Fixtures.Boot(H, opts)
      c.meta.locale = opts.locale or "enUS"
      c.meta.lang = opts.addonLocale
      c.meta.screen = { w = M.world.screenWidth, h = M.world.screenHeight }
      if opts.hello ~= false then Fixtures.ServerHello(c.T, opts.helloOpts) end
      if opts.reply ~= false then Fixtures.ServerAutoReply(c.T, { mute = opts.mute }) end
      return c.T
   end

   -- Modul vorhanden? sonst Szenario ueberspringen
   function c.need(...)
      for i = 1, select("#", ...) do
         local path = select(i, ...)
         if c.T == nil or lookup(c.T, path) == nil then
            skip("module missing (" .. path .. ")")
         end
      end
   end

   function c.settle(seconds)
      Fixtures.Settle(c.T, seconds or 1.0)
   end

   -- Einstellung wie der Spieler (DB.Set feuert SETTINGS_CHANGED)
   function c.setting(key, value)
      c.T.DB.Set(key, value)
   end

   function c.window()
      return rawget(_G, "TransmogWindow")
   end

   -- Fenster wie am Transmogrifizierer oeffnen (Boot-Ablauf), danach Reiter/Slot waehlen
   function c.openNpc(o)
      o = o or {}
      c.need("UI.Window")
      local W = c.T.UI.Window
      Fixtures.OpenAtNpc(c.T)
      if not (W.IsShown and W.IsShown()) then W.Open({ fromNpc = true }) end
      if o.tab and W.SetTab then W.SetTab(o.tab) end
      if o.slot ~= nil and W.SelectSlot then W.SelectSlot(o.slot) end
   end

   -- Fenster wie mit /transmog oeffnen (Vorschau-Modus)
   function c.openPreview(o)
      o = o or {}
      c.need("UI.Window")
      local W = c.T.UI.Window
      W.Open({ fromNpc = false, tab = o.tab, slot = o.slot })
      if o.tab and W.SetTab then W.SetTab(o.tab) end
      if o.slot ~= nil and W.SelectSlot then W.SelectSlot(o.slot) end
   end

   function c.click(frame, button)
      M.Click(frame, button)
   end

   -- Erster sichtbarer Button unter dem Fenster, dessen Text zu pattern passt
   function c.findButton(pattern, root)
      return findButtons(M, root or c.window(), pattern)[1]
   end

   return c
end

-- ---------------------------------------------------------------------------
-- Szenarien
-- ---------------------------------------------------------------------------

R.Scenarios = {}
R.Order = {}

-- Die acht Sprachen des Addons (Reihenfolge wie Locale.List())
R.Languages = { "enUS", "deDE", "frFR", "esES", "ruRU", "koKR", "zhCN", "zhTW" }

-- Pfadmuster der Texte, die die Oberflaeche absichtlich abschneidet (Namen in Rasterzellen usw.);
-- Layout.Check meldet sie nur als "info"
R.truncateOk = { "/name$", "/nameText$", "/nameLabel$" }

local function scenario(name, def)
   def.name = name
   R.Scenarios[name] = def
   R.Order[#R.Order + 1] = name
end

local SLOT = { HEAD = 0, SHOULDER = 2, SHIRT = 3, CHEST = 4, WAIST = 5, LEGS = 6, FEET = 7, WRIST = 8,
               HANDS = 9, BACK = 14, MAINHAND = 15, OFFHAND = 16, RANGED = 17, TABARD = 18 }

scenario("default", {
   title = "Default: 880x600, enUS, head slot selected, page 1",
   needs = { "UI.Window" },
   run = function(c)
      c.boot({ locale = "enUS", screen = { w = 1366, h = 768 } })
      c.need("UI.Window")
      c.setting("width", 880)
      c.setting("height", 600)
      c.openNpc({ slot = SLOT.HEAD })
      c.settle(1.0)
   end,
})

scenario("min", {
   title = "Minimum size 740x520 (scale 1.0)",
   needs = { "UI.Window" },
   run = function(c)
      c.boot({ locale = "enUS", screen = { w = 1366, h = 768 } })
      c.need("UI.Window")
      c.setting("scale", 1.0)
      c.setting("width", 740)
      c.setting("height", 520)
      c.openNpc({ slot = SLOT.HEAD })
      c.settle(1.0)
   end,
})

scenario("large", {
   title = "Large 1400x900 at scale 1.0 on 1920x1080",
   needs = { "UI.Window" },
   run = function(c)
      c.boot({ locale = "enUS", screen = { w = 1920, h = 1080 } })
      c.need("UI.Window")
      c.setting("scale", 1.0)
      c.setting("width", 1400)
      c.setting("height", 900)
      c.openNpc({ slot = SLOT.CHEST })
      c.settle(1.0)
   end,
})

scenario("scale15", {
   title = "Window scale 1.5 (880x600) on 1920x1080",
   needs = { "UI.Window" },
   run = function(c)
      c.boot({ locale = "enUS", screen = { w = 1920, h = 1080 } })
      c.need("UI.Window")
      c.setting("scale", 1.5)
      c.setting("width", 880)
      c.setting("height", 600)
      c.openNpc({ slot = SLOT.SHOULDER })
      c.settle(1.0)
   end,
})

scenario("german", {
   title = "German client (deDE): long names and labels",
   needs = { "UI.Window" },
   run = function(c)
      c.boot({ locale = "deDE", screen = { w = 1366, h = 768 }, equipmentSet = "plate" })
      c.need("UI.Window")
      c.setting("width", 880)
      c.setting("height", 600)
      c.openNpc({ slot = SLOT.LEGS })
      c.settle(1.0)
   end,
})

scenario("outfits-tab", {
   title = "Outfits tab with 3 saved outfits",
   needs = { "UI.Window", "UI.OutfitsTab" },
   run = function(c)
      local T = c.boot({ locale = "enUS", screen = { w = 1366, h = 768 } })
      c.need("UI.Window", "UI.OutfitsTab", "Outfits")
      local F = c.Fixtures
      local hidden = F.HIDDEN
      local one = F.Looks(T, 1)
      local two = F.Looks(T, 2)
      two[SLOT.HEAD], two[SLOT.SHOULDER] = hidden, hidden
      local three = F.Looks(T, 3)
      three[SLOT.BACK] = hidden
      -- (der dritte Name hat die Hoechstlaenge von 32 Zeichen)
      local function save(name, slots)
         local ok, err = T.Outfits.Save(name, slots)
         if not ok then error("Outfits.Save(" .. name .. ") failed: " .. tostring(err), 0) end
      end
      save("Frostbitten Knight", one)
      save("Quiet Night Walk", two)
      save("Argent Tournament Parade Banners", three)
      c.openNpc({ tab = "outfits" })
      c.settle(1.0)
   end,
})

scenario("options", {
   title = "Options panel open",
   needs = { "UI.Window", "UI.Options" },
   run = function(c)
      c.boot({ locale = "enUS", screen = { w = 1366, h = 768 } })
      c.need("UI.Window", "UI.Options")
      c.openNpc({ slot = SLOT.HEAD })
      c.settle(0.8)
      c.T.UI.Options.Open()
      c.settle(0.3)
   end,
})

scenario("menu-type", {
   title = "Type filter menu open",
   needs = { "UI.Window", "UI.Skin" },
   run = function(c)
      local T = c.boot({ locale = "enUS", screen = { w = 1366, h = 768 } })
      c.need("UI.Window", "UI.Skin")
      c.openNpc({ slot = SLOT.HEAD })
      c.settle(1.0)
      local Skin = T.UI.Skin
      -- der Filter-/Typ-Knopf der Filterleiste (Beschriftung beginnt mit "Filter" oder "Typ")
      local btn = c.findButton("^[Ff]ilter") or c.findButton("^[Tt]yp")
      if btn then c.click(btn) end
      if not (Skin.Menu and Skin.Menu.IsOpen and Skin.Menu.IsOpen()) then
         -- Rueckfall: das Menue aus Filter.Types nachbauen und am Fenster verankern
         local items = {}
         for _, t in ipairs(T.Filter.Types(SLOT.HEAD)) do
            items[#items + 1] = { text = (t.label or tostring(t.typeKey)) .. " (" .. tostring(t.count) .. ")",
                                  checked = true, keepOpen = true }
         end
         if #items == 0 then skip("no types for the head slot") end
         Skin.Menu.Open(btn or c.window(), items, {})
         c.meta.note = "Type button not found: menu built from Filter.Types"
      end
      c.settle(0.2)
   end,
})

scenario("loading", {
   title = "Items still loading (uncached)",
   needs = { "UI.Window" },
   run = function(c)
      c.boot({ locale = "enUS", screen = { w = 1366, h = 768 }, cacheItems = false, itemCacheDelay = 30 })
      c.need("UI.Window")
      c.openNpc({ slot = SLOT.HEAD })
      c.settle(0.4)
   end,
})

scenario("empty-slot", {
   title = "Selected slot is empty (no tabard equipped)",
   needs = { "UI.Window" },
   run = function(c)
      local T = c.boot({ locale = "enUS", screen = { w = 1366, h = 768 } })
      c.need("UI.Window")
      c.openNpc({ slot = SLOT.HEAD })
      c.settle(0.5)
      c.Fixtures.Unequip(T, SLOT.TABARD)
      c.settle(1.0)
      c.T.UI.Window.SelectSlot(SLOT.TABARD)
      c.settle(0.5)
   end,
})

scenario("preview-mode", {
   title = "Preview mode (opened with /transmog, not at the NPC)",
   needs = { "UI.Window" },
   run = function(c)
      c.boot({ locale = "enUS", screen = { w = 1366, h = 768 } })
      c.need("UI.Window")
      c.openPreview({ slot = SLOT.SHOULDER })
      c.settle(1.0)
   end,
})

scenario("server-absent", {
   title = "Server module absent (no answers for 9 s)",
   needs = { "UI.Window" },
   run = function(c)
      c.boot({ locale = "enUS", screen = { w = 1366, h = 768 }, hello = false, mute = true })
      c.need("UI.Window")
      c.openPreview({ slot = SLOT.HEAD })
      c.settle(9.5)
   end,
})

scenario("toast", {
   title = "Toast cards for newly collected appearances",
   needs = { "UI.Window", "Toasts" },
   run = function(c)
      local T = c.boot({ locale = "enUS", screen = { w = 1366, h = 768 } })
      c.need("UI.Window", "Toasts")
      c.openNpc({ slot = SLOT.HEAD })
      c.settle(11)   -- Login-Sweep (10 s) ist vorbei
      local F = c.Fixtures
      T.Toasts.Show(F.Item(T, "e_head_plate"))
      T.Toasts.Show(F.Item(T, "e_shoulder_plate"))
      c.settle(0.8)
   end,
})

-- Stand-in, das nur die Kernmodule und Skin braucht: eine Mini-Oberflaeche aus Skin-Widgets
-- mit den Testdaten (zeigt Skin, Fixtures und die Werkzeuge selbst; laeuft immer).
scenario("skin-demo", {
   title = "Skin demo: header, slots, grid, filter row and footer built from Skin widgets",
   needs = { "UI.Skin" },
   run = function(c)
      local T = c.boot({ locale = "enUS", screen = { w = 1366, h = 768 } })
      c.need("UI.Skin")
      local Skin, F = T.UI.Skin, c.Fixtures
      local COL = Skin.COL

      local win = CreateFrame("Frame", "TransmogSkinDemo", UIParent)
      win:SetWidth(880)
      win:SetHeight(600)
      win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      win:SetFrameStrata("HIGH")
      win:EnableMouse(true)
      Skin.Backdrop(win, COL.bg, COL.border)
      local head = Skin.Header(win, "Transmog")
      local tabItems = Skin.Button(win, 100, 22, "Items", function() end)
      tabItems:SetPoint("TOPLEFT", win, "TOPLEFT", 110, -5)
      tabItems:SetSelected(true)
      local tabOutfits = Skin.Button(win, 100, 22, "Outfits", function() end)
      tabOutfits:SetPoint("LEFT", tabItems, "RIGHT", 4, 0)
      local opt = Skin.Button(win, 26, 22, "*", function() end)
      opt:SetPoint("TOPRIGHT", win, "TOPRIGHT", -40, -5)
      local close = Skin.Button(win, 26, 22, "x", function() end)
      close:SetTheme("danger")
      close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -8, -5)

      -- Slotleisten (je 7 Knoepfe, 40 px)
      local slots = { { SLOT.HEAD, SLOT.SHOULDER, SLOT.BACK, SLOT.CHEST, SLOT.SHIRT, SLOT.TABARD, SLOT.WRIST },
                      { SLOT.HANDS, SLOT.WAIST, SLOT.LEGS, SLOT.FEET, SLOT.MAINHAND, SLOT.OFFHAND, SLOT.RANGED } }
      local eqKeys = F.Catalog(T).byId
      for col = 1, 2 do
         for row = 1, 7 do
            local slot = slots[col][row]
            local b = Skin.Button(win, 40, 40, "", function() end)
            b:SetPoint("TOPLEFT", win, "TOPLEFT", col == 1 and 8 or 270, -42 - (row - 1) * 54)
            local id = T.State and T.State.Equipped(slot) and T.State.Equipped(slot).id
            local rec = id and eqKeys[id]
            if rec then b:SetIcon(rec.icon, 32) end
            if slot == SLOT.HEAD then b:SetSelected(true) end
            if slot == SLOT.CHEST then b:SetAccent(COL.yellow[1], COL.yellow[2], COL.yellow[3]) end
         end
      end
      local model = CreateFrame("DressUpModel", nil, win, "TransmogPreviewModelTemplate")
      model:SetWidth(204)
      model:SetHeight(334)
      model:SetPoint("TOPLEFT", win, "TOPLEFT", 58, -42)
      model:SetUnit("player")

      -- rechte Seite: Suche, Sortierung, Filter, Raster
      local search = Skin.EditBox(win, 250, 24, "Search...", function() end)
      search:SetPoint("TOPLEFT", win, "TOPLEFT", 326, -42)
      local sort = Skin.Button(win, 130, 24, "Sort: Quality", function() end)
      sort:SetPoint("LEFT", search, "RIGHT", 6, 0)
      local dup = Skin.Check(win, "Hide duplicates", function() end)
      dup:SetPoint("TOPLEFT", win, "TOPLEFT", 326, -76)
      dup:SetChecked(true)
      for q = 0, 5 do
         local r, g, b = T.Util.QualityColor(q)
         local chip = Skin.Button(win, 18, 18, "", function() end)
         chip:SetPoint("TOPLEFT", win, "TOPLEFT", 480 + q * 22, -74)
         chip:SetTextColor(r, g, b)
         chip:SetLabel("#")
      end
      local list = F.List(T, SLOT.HEAD)
      local cat = F.Catalog(T)
      for i = 1, 12 do
         local rec = cat.byId[list[i]]
         if not rec then break end
         local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
         local cell = Skin.Button(win, 92, 126, "", function() end)
         cell:SetPoint("TOPLEFT", win, "TOPLEFT", 326 + col * 98, -108 - row * 132)
         if i == 2 then cell:SetSelected(true) end
         local icon = cell:CreateTexture(nil, "ARTWORK")
         icon:SetWidth(64)
         icon:SetHeight(64)
         icon:SetPoint("TOP", cell, "TOP", 0, -10)
         Skin.Icon(icon, rec.icon)
         local name = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
         name:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, -84)
         name:SetWidth(84)
         name:SetHeight(28)
         name:SetJustifyH("CENTER")
         local qr, qg, qb = T.Util.QualityColor(rec.quality)
         name:SetTextColor(qr, qg, qb)
         name.__truncate = true   -- Namen werden absichtlich abgeschnitten (Layout.Check: nur info)
         name:SetText(rec.name)
      end

      -- Fuss
      local reset = Skin.Button(win, 100, 26, "Discard", function() end)
      reset:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 8, 10)
      local all = Skin.Button(win, 130, 26, "Remove all", function() end)
      all:SetPoint("LEFT", reset, "RIGHT", 6, 0)
      local apply = Skin.Button(win, 140, 28, "Apply", function() end)
      apply:SetTheme("primary")
      apply:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 9)
      local cost = Skin.Label(win, "Cost: " .. T.Util.FormatMoney(250000))
      cost:SetPoint("RIGHT", apply, "LEFT", -12, 0)
      local status = Skin.Label(win, "3 changes pending")
      status:SetPoint("LEFT", all, "RIGHT", 12, 0)

      -- ein offenes Menue (Typ-Filter)
      Skin.Menu.Open(sort, {
         { text = "Quality", radio = true, checked = true },
         { text = "Name", radio = true },
         { text = "Item level", radio = true },
         { text = "Plate (4)", checked = true },
         { text = "Mail (2)", checked = true },
      }, {})
      c.settle(0.2)
      c.meta.note = "stand-in window built from Skin widgets"
   end,
})

-- ---------------------------------------------------------------------------
-- Lauf
-- ---------------------------------------------------------------------------

local function fileWrite(path, text)
   local f, err = io.open(path, "wb")
   if not f then return false, err end
   f:write(text)
   f:close()
   return true
end

local function fileRead(path)
   local f = io.open(path, "rb")
   if not f then return nil end
   local s = f:read("*a")
   f:close()
   return s
end

-- Fuehrt ein Szenario aus. Ergebnis: { name, title, status = "ok"|"skip"|"error", reason, svg, info,
-- problems, entries, meta, handlerErrors }
function R.RunScenario(name, env)
   local sc = R.Scenarios[name]
   if not sc then return { name = name, status = "error", reason = "unknown scenario" } end
   local Layout = env.Layout
   local result = { name = name, title = sc.title, status = "ok" }
   local ctx = makeContext(env)
   local M = ctx.M

   local ok, err = xpcall(function() sc.run(ctx) end, function(m)
      if type(m) == "table" then return m end
      return { error = tostring(m), trace = debug.traceback("", 2) }
   end)
   if not ok then
      if type(err) == "table" and err.skip then
         result.status = "skip"
         result.reason = err.skip
         return result
      end
      result.status = "error"
      result.reason = type(err) == "table" and (err.error or "error") or tostring(err)
      result.trace = type(err) == "table" and err.trace or nil
      return result
   end

   -- Wurzeln: alles Sichtbare des Addons (Fenster, Menues, Dialoge, Toasts) oder der benannte Frame
   local roots = ctx.roots
   if not roots and env.rootName then
      local named = rawget(_G, env.rootName)
      if type(named) ~= "table" or not rawget(named, "__shown") then
         result.status = "error"
         result.reason = "root frame '" .. env.rootName .. "' does not exist or is hidden"
         return result
      end
      roots = { named }
   end
   roots = roots or Layout.TopLevel()
   if #roots == 0 then
      result.status = "error"
      result.reason = "nothing visible to render (no visible Transmog frame)"
      return result
   end
   local entries = Layout.Rects(roots)
   local problems = Layout.Check(entries, { truncateOk = R.truncateOk })
   result.entries = entries
   result.problems = problems
   result.meta = ctx.meta
   result.handlerErrors = #M.errors
   result.firstHandlerError = M.errors[1]
   result.missingAssets = #M.missingAssets
   local win = rawget(_G, "TransmogWindow") or rawget(_G, "TransmogSkinDemo")
   if win then
      local e = entries.byFrame[win]
      result.meta.window = {
         w = win:GetWidth(), h = win:GetHeight(), scale = win:GetEffectiveScale(),
         shown = e and e.visible or false,
      }
   end
   result.problemsInSvg = env.problemsInSvg ~= false
   result.idPrefix = env.idPrefix or ("s_" .. name:gsub("[^%w]", "") .. "_")
   local svg, info = Layout.Render(entries, {
      problems = result.problemsInSvg and problems or nil,
      title = sc.title or name,
      idPrefix = result.idPrefix,
   })
   result.svg, result.info = svg, info
   local valid, msg = Layout.ValidateSvg(svg)
   if not valid then
      result.status = "error"
      result.reason = "invalid SVG: " .. tostring(msg)
   end
   return result
end

-- ---------------------------------------------------------------------------
-- index.html
-- ---------------------------------------------------------------------------

local function htmlEsc(s)
   s = tostring(s)
   s = sgsub(s, "&", "&amp;")
   s = sgsub(s, "<", "&lt;")
   s = sgsub(s, ">", "&gt;")
   s = sgsub(s, '"', "&quot;")
   return s
end

-- Liste der SVG-Dateien eines Verzeichnisses (ohne Unterordner)
local function listSvgs(dir)
   local out = {}
   local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
   if not p then return out end
   for line in p:lines() do
      if line:match("%.svg$") then out[#out + 1] = line end
   end
   p:close()
   tsort(out)
   return out
end

-- Schreibt index.html: alle SVGs des Verzeichnisses eingebettet; dieser Lauf mit Metadaten
function R.WriteIndex(dir, results, stamp)
   local byName = {}
   for _, r in ipairs(results or {}) do
      if r.svg then byName[(r.fileBase or r.name) .. ".svg"] = r end
   end
   local files = listSvgs(dir)
   -- Reihenfolge: bekannte Szenarien in Definitionsreihenfolge, danach der Rest
   local order, seen = {}, {}
   for _, name in ipairs(R.Order) do
      local f = name .. ".svg"
      for _, existing in ipairs(files) do
         if existing == f then
            order[#order + 1] = f
            seen[f] = true
         end
      end
   end
   for _, f in ipairs(files) do
      if not seen[f] then order[#order + 1] = f end
   end

   local out = {}
   local function add(s) out[#out + 1] = s end
   add("<!DOCTYPE html>")
   add('<html lang="en"><head><meta charset="utf-8"><title>Transmog UI renders</title>')
   add("<style>")
   add("body{margin:0;padding:16px 24px;background:#14161a;color:#d8dce4;font:14px/1.45 system-ui,Segoe UI,Arial,sans-serif}")
   add("h1{font-size:20px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 4px;color:#7cc4ff}")
   add("a{color:#7cc4ff}nav a{margin-right:12px}.meta{color:#9aa3b2;font-size:12px;margin:0 0 8px}")
   add(".svgwrap{background:#0c0d10;border:1px solid #2b2f36;display:inline-block;max-width:100%;overflow:auto}")
   add(".svgwrap svg{display:block;max-width:100%;height:auto}")
   add("ul.problems{margin:6px 0 0;padding-left:20px;font-size:12px;font-family:ui-monospace,Menlo,monospace}")
   add("li.error{color:#ff8a96}li.warning{color:#ffcf6b}li.info{color:#8fc3ff}")
   add(".skip{color:#9aa3b2}.err{color:#ff8a96}")
   add("</style></head><body>")
   add("<h1>Transmog UI renders</h1>")
   add('<p class="meta">Generated by tests/render_ui.lua ' .. htmlEsc(stamp or "") ..
      ". Hover over objects for their frame paths; icons are colored placeholders.</p>")
   add("<nav>")
   for _, f in ipairs(order) do
      local n = f:gsub("%.svg$", "")
      add('<a href="#' .. htmlEsc(n) .. '">' .. htmlEsc(n) .. "</a>")
   end
   -- Szenarien ohne SVG (uebersprungen/fehlgeschlagen)
   local notes = {}
   for _, r in ipairs(results or {}) do
      if r.status == "skip" or (r.status == "error" and not r.svg) then notes[#notes + 1] = r end
   end
   add("</nav>")
   for _, f in ipairs(order) do
      local n = f:gsub("%.svg$", "")
      local r = byName[f]
      local title = (r and r.title) or (R.Scenarios[n] and R.Scenarios[n].title) or n
      add('<section id="' .. htmlEsc(n) .. '"><h2>' .. htmlEsc(n) .. "</h2>")
      add('<p class="meta">' .. htmlEsc(title))
      if r then
         local m = r.meta or {}
         local bits = {}
         if m.locale then bits[#bits + 1] = "client locale " .. m.locale end
         if m.lang then bits[#bits + 1] = "addon language " .. m.lang end
         if m.screen then bits[#bits + 1] = "screen " .. m.screen.w .. "x" .. m.screen.h end
         if m.window then
            bits[#bits + 1] = sfmt("window %dx%d, effective scale %.2f", m.window.w, m.window.h, m.window.scale)
         end
         if r.info then bits[#bits + 1] = r.info.drawn .. " elements drawn" end
         if r.handlerErrors and r.handlerErrors > 0 then
            bits[#bits + 1] = r.handlerErrors .. " handler error(s): " .. tostring(r.firstHandlerError)
         end
         if m.note then bits[#bits + 1] = m.note end
         if #bits > 0 then add("<br>" .. htmlEsc(tconcat(bits, " | "))) end
      end
      add("</p>")
      local svg = r and r.svg or fileRead(dir .. "/" .. f) or ""
      add('<div class="svgwrap">' .. svg .. "</div>")
      if r and r.problems and #r.problems > 0 then
         local c = r.problems.counts
         add('<p class="meta">layout check: ' .. c.error .. " error(s), " .. c.warning .. " warning(s), " ..
            c.info .. " info</p><ul class=\"problems\">")
         for i, p in ipairs(r.problems) do
            if i > 40 then
               add("<li>... and " .. (#r.problems - 40) .. " more</li>")
               break
            end
            add('<li class="' .. p.severity .. '">' .. htmlEsc(p.kind .. ": " .. p.path .. " - " .. p.message) .. "</li>")
         end
         add("</ul>")
      elseif r then
         add('<p class="meta">no layout problems</p>')
      end
      add("</section>")
   end
   if #notes > 0 then
      add("<h2>Not rendered</h2><ul>")
      for _, r in ipairs(notes) do
         if r.status == "skip" then
            add('<li class="skip">' .. htmlEsc(r.name) .. ": skipped - " .. htmlEsc(r.reason) .. "</li>")
         else
            add('<li class="err">' .. htmlEsc(r.name) .. ": " .. htmlEsc(r.reason) .. "</li>")
         end
      end
      add("</ul>")
   end
   add("</body></html>")
   return fileWrite(dir .. "/index.html", tconcat(out, "\n") .. "\n")
end

-- ---------------------------------------------------------------------------
-- Kommandozeile
-- ---------------------------------------------------------------------------

-- Minimaler Ersatz fuer das H des Runners (die Datei laeuft ausserhalb von run.lua)
local function newHarness(mock)
   local H = { mock = mock, root = mock.root }
   function H.install(opts) return mock.Install(opts) end
   -- Wie run.lua: ohne eigene TransmogGlobalDB startet die Darstellung im Zustand "ohne Transmogrifizierer
   -- anwenden ist aus" (Vorschau-Modus), den die Szenarien zeigen; opts.noSeed = true schaltet das ab.
   function H.SeedGlobals(globals)
      local out = {}
      for k, v in pairs(globals or {}) do out[k] = v end
      if out.TransmogGlobalDB == nil then
         out.TransmogGlobalDB = { noNpcDefault = true, allowAnywhere = false }
      end
      return out
   end
   function H.boot(opts)
      opts = opts or {}
      local saved = opts.globals or opts.savedVariables
      if not opts.noSeed then saved = H.SeedGlobals(saved) end
      mock.Install({ world = opts.world, items = opts.items, globals = saved })
      local skipMissing = opts.skipMissing
      if skipMissing == nil then skipMissing = true end
      local loaded, info = mock.LoadToc(mock.root, opts.toc or "Transmog.toc", {
         upTo = opts.upTo, skip = opts.skip, skipMissing = skipMissing,
      })
      H.loaded, H.loadInfo = loaded, info
      mock.Fire("ADDON_LOADED", "Transmog")
      if opts.login ~= false then
         mock.Fire("VARIABLES_LOADED")
         mock.Fire("PLAYER_LOGIN")
         if opts.enterWorld then mock.Fire("PLAYER_ENTERING_WORLD") end
      end
      return rawget(_G, "Transmog")
   end
   return H
end

function R.main(argv)
   local names, outDir = {}, nil
   local opt = { index = true, problems = true }
   local i = 1
   while argv[i] do
      local a = argv[i]
      if a == "--out" then
         i = i + 1
         outDir = argv[i]
      elseif a == "--list" then
         opt.list = true
      elseif a == "--lang" then
         i = i + 1
         opt.lang = argv[i]
      elseif a == "--root" then
         i = i + 1
         opt.root = argv[i]
      elseif a == "--no-index" then
         opt.index = false
      elseif a == "--no-problems" then
         opt.problems = false
      elseif a == "--strict" then
         opt.strict = true
      elseif a == "--fail-on-errors" then
         opt.failOnErrors = true
      elseif a == "-v" then
         opt.verbose = true
      elseif a == "-h" or a == "--help" then
         opt.help = true
      elseif ssub(a, 1, 1) == "-" then
         io.stderr:write("render_ui: unknown option " .. a .. "\n")
         return 2
      else
         names[#names + 1] = a
      end
      i = i + 1
   end
   if opt.help then
      io.write("luajit tests/render_ui.lua [scenario ...] [--out DIR] [--list] [--root FRAME] [--no-index] "
         .. "[--lang CODE|all] [--no-problems] [--strict] [--fail-on-errors] [-v]\n")
      return 0
   end
   if opt.list then
      for _, n in ipairs(R.Order) do
         io.write(sfmt("%-14s %s\n", n, R.Scenarios[n].title or ""))
      end
      return 0
   end
   local langs = nil
   if opt.lang == "all" then
      langs = R.Languages
   elseif opt.lang then
      local known = false
      for _, code in ipairs(R.Languages) do
         if code == opt.lang then known = true end
      end
      if not known then
         io.stderr:write("render_ui: unknown language '" .. tostring(opt.lang) .. "' (enUS deDE frFR esES ruRU koKR zhCN zhTW)\n")
         return 2
      end
      langs = { opt.lang }
   end
   for _, n in ipairs(names) do
      if not R.Scenarios[n] then
         io.stderr:write("render_ui: unknown scenario '" .. n .. "' (see --list)\n")
         return 2
      end
   end
   if #names == 0 then
      for _, n in ipairs(R.Order) do names[#names + 1] = n end
   end

   package.path = TESTS_DIR .. "/?.lua;" .. package.path
   local mock = dofile(TESTS_DIR .. "/mock_wow.lua")
   local H = newHarness(mock)
   local Fixtures = require("fixtures")
   local Layout = require("layout")

   outDir = outDir or (TESTS_DIR .. "/out")
   os.execute('mkdir -p "' .. outDir .. '"')

   local results = {}
   local failures, counts = 0, { ok = 0, skip = 0, error = 0 }
   local jobs = {}
   for _, lang in ipairs(langs or { false }) do
      for _, name in ipairs(names) do
         jobs[#jobs + 1] = { name = name, lang = lang or nil }
      end
   end
   for _, job in ipairs(jobs) do
      local name, lang = job.name, job.lang
      local label = lang and (name .. "." .. lang) or name
      local r = R.RunScenario(name, { H = H, Fixtures = Fixtures, Layout = Layout, problemsInSvg = opt.problems,
         rootName = opt.root, addonLocale = lang })
      r.fileBase = label
      if lang and r.title then r.title = r.title .. " [" .. lang .. "]" end
      results[#results + 1] = r
      if r.status == "skip" then
         counts.skip = counts.skip + 1
         io.write(sfmt("SKIP %s: %s\n", label, r.reason or "module missing"))
         if opt.strict then failures = failures + 1 end
      elseif r.status == "error" then
         counts.error = counts.error + 1
         failures = failures + 1
         io.write(sfmt("FAIL %s: %s\n", label, tostring(r.reason)))
         if r.trace then io.write(r.trace .. "\n") end
         if r.svg then fileWrite(outDir .. "/" .. label .. ".svg", r.svg) end
      else
         counts.ok = counts.ok + 1
         local path = outDir .. "/" .. label .. ".svg"
         local okw, werr = fileWrite(path, r.svg)
         if not okw then
            failures = failures + 1
            io.write(sfmt("FAIL %s: cannot write %s (%s)\n", label, path, tostring(werr)))
         else
            local c = r.problems.counts
            io.write(sfmt("OK   %s: %d elements, %d error(s), %d warning(s) -> %s\n",
               label, r.info.drawn, c.error, c.warning, path))
            if r.handlerErrors > 0 then
               io.write(sfmt("     WARN %d handler error(s), first: %s\n", r.handlerErrors, tostring(r.firstHandlerError)))
            end
            if r.missingAssets > 0 then io.write(sfmt("     WARN %d missing addon asset(s)\n", r.missingAssets)) end
            if opt.verbose and #r.problems > 0 then io.write(Layout.Format(r.problems) .. "\n") end
            if opt.failOnErrors and c.error > 0 then failures = failures + 1 end
         end
      end
   end
   if opt.index then
      local okw, werr = R.WriteIndex(outDir, results, os.date("%Y-%m-%d %H:%M:%S"))
      if okw then
         io.write("index: " .. outDir .. "/index.html\n")
      else
         io.write("FAIL index.html: " .. tostring(werr) .. "\n")
         failures = failures + 1
      end
   end
   io.write(sfmt("%d rendered, %d skipped, %d failed\n", counts.ok, counts.skip, counts.error))
   return failures > 0 and 1 or 0
end

if isCli then
   os.exit(R.main(arg))
end

return R
