-- tests/test_locales_layout.lua
-- ---------------------------------------------------------------------------
-- Layout des Fensters in allen acht Sprachen (enUS deDE frFR esES ruRU koKR
-- zhCN zhTW). Die Szenarien kommen aus tests/render_ui.lua; die Sprache der
-- Addon-Texte wird ueber Fixtures.Boot{ addonLocale = code } gewaehlt (wie die
-- Auswahl in den Optionen: DB.Set("locale") + Locale.Set), die Client-Sprache
-- bleibt wie im Szenario.
--
--     luajit tests/run.lua locales_layout
--
-- Massstab ist derselbe wie in den UI-Tests: Layout.Check mit den Standard-
-- Toleranzen (0,75 px) und truncateOk fuer die absichtlich abgeschnittenen
-- Namen in den Rasterzellen (render_ui.truncateOk). Verlangt wird
--   * kein Befund der Schwere "error" (ueberlappende Bedienelemente, Inhalt
--     ausserhalb des Fensters, zu breite einzeilige Texte ...) und
--   * kein Warnbefund "text-too-wide"/"text-clipped": eine Uebersetzung, die
--     im Knopf, im Feld oder in der Zeile abgeschnitten wird, ist ein Fehler.
-- Die Schriftbreiten der Attrappe sind fuer CJK/Kyrillisch geschaetzt
-- (Layout.TextWidth); die Pruefung ist dort ein Hinweis, kein Beweis.
-- ---------------------------------------------------------------------------

return function(H)
   local Layout = require("layout")
   local Fixtures = require("fixtures")

   -- render_ui.lua als Modul laden (laeuft nicht als Skript, weil arg[0] auf run.lua endet)
   local R = dofile(H.root .. "/tests/render_ui.lua")

   -- Die acht Sprachen des Addons
   local LANGS = R.Languages
   H.assert(type(LANGS) == "table" and #LANGS == 8, "render_ui.Languages")

   -- Kernszenarien (muessen fehlerfrei sein) und weitere Zustaende (Dialoge, Meldungen, Menues)
   local CORE = { "default", "min", "outfits-tab", "options" }
   local MORE = { "large", "scale15", "german", "menu-type", "loading", "empty-slot", "preview-mode",
                  "server-absent", "toast" }

   -- Welcher Text beweist, dass das Szenario in der Zielsprache gerendert wurde
   local PROOF = {
      ["outfits-tab"] = "WIN_TAB_OUTFITS", options = "OPT_TITLE", ["server-absent"] = "GRID_ABSENT",
      ["empty-slot"] = "GRID_EMPTY_SLOT", ["preview-mode"] = "MSG_NO_VENDOR", toast = "TOAST_TITLE",
   }

   -- Schluessel als Text darf nirgends auf dem Bildschirm stehen
   local function looksLikeKey(text)
      return type(text) == "string" and text:find("^[A-Z][A-Z0-9]*_[A-Z0-9_]+$") ~= nil
   end

   -- Befunde zusammenfassen: Fehler und abgeschnittene Texte (ohne die erlaubten Namen)
   local function relevant(problems)
      local out = {}
      for _, p in ipairs(problems) do
         if p.severity == "error" then
            out[#out + 1] = p
         elseif p.severity == "warning" and (p.kind == "text-too-wide" or p.kind == "text-clipped") then
            out[#out + 1] = p
         end
      end
      return out
   end

   -- Fuehrt ein Szenario in einer Sprache aus und prueft es; liefert das Ergebnis.
   local function runChecked(name, code)
      local label = name .. " / " .. code
      local res = R.RunScenario(name, { H = H, Fixtures = Fixtures, Layout = Layout, addonLocale = code })
      H.eq(res.status, "ok", label .. ": " .. tostring(res.reason))
      if res.status ~= "ok" then return res end

      local T = rawget(_G, "Transmog")
      H.eq(T.Locale.Current(), code, label .. ": Sprache")
      H.falsy(next(T.L.__missing), label .. ": fehlender Schluessel " .. tostring(next(T.L.__missing)))

      local bad = relevant(res.problems)
      if #bad > 0 then
         H.fail(label .. ": " .. #bad .. " Layoutbefund(e)\n" .. Layout.Format(bad))
      end
      H.eq(res.handlerErrors, 0, label .. ": Fehler in Handlern: " .. tostring(res.firstHandlerError))

      -- die Zielsprache ist wirklich zu sehen, und kein Schluessel steht als Text da
      local proofKey = PROOF[name] or "WIN_TAB_ITEMS"
      local want = rawget(T.L, proofKey)
      local found = false
      for _, e in ipairs(res.entries) do
         if e.text == want then found = true end
         if e.visible and looksLikeKey(e.text) then
            H.fail(label .. ": Schluessel als Text: " .. tostring(e.text) .. " (" .. tostring(e.path) .. ")")
         end
      end
      -- (Toast-Szenario: der Titel steht im Toast; Name des Gegenstands bleibt der Katalogname)
      H.truthy(found, label .. ": Text " .. proofKey .. " = \"" .. tostring(want) .. "\" nicht gerendert")
      return res
   end

   -- =======================================================================
   H.section("Layout je Sprache: default, min, outfits-tab, options")
   -- =======================================================================

   for _, code in ipairs(LANGS) do
      H.test("Layout " .. code .. ": default, min, outfits-tab und options ohne Fehler", function()
         for _, name in ipairs(CORE) do
            runChecked(name, code)
         end
      end)
   end

   -- =======================================================================
   H.section("Layout je Sprache: weitere Zustaende")
   -- =======================================================================

   for _, code in ipairs(LANGS) do
      H.test("Layout " .. code .. ": Skalierung, Menues, Lade-/Leer-/Fehlerzustaende, Vorschau-Modus, Toasts", function()
         for _, name in ipairs(MORE) do
            runChecked(name, code)
         end
      end)
   end

   -- =======================================================================
   H.section("Layout: Sprachwechsel bei offenem Fenster")
   -- =======================================================================

   -- Alle Sprachen nacheinander im selben Fenster (Mindestgroesse): nach jedem Wechsel
   -- darf nichts abgeschnitten sein oder sich ueberlappen (Kopf, Reiter, Knoepfe, Fuss).
   H.test("Sprachwechsel bei offenem Fenster (Mindestgroesse, Items- und Outfit-Reiter): keine Fehler", function()
      local T = Fixtures.Boot(H, { locale = "enUS", screen = { w = 1366, h = 768 } })
      Fixtures.ServerHello(T)
      Fixtures.ServerAutoReply(T)
      T.DB.Set("scale", 1.0)
      T.DB.Set("width", 740)
      T.DB.Set("height", 520)
      Fixtures.OpenAtNpc(T)
      T.UI.Window.SelectSlot(0)
      Fixtures.Settle(T, 1)
      for _, tab in ipairs({ "items", "outfits" }) do
         T.UI.Window.SetTab(tab)
         for _, code in ipairs(LANGS) do
            Fixtures.SetLanguage(T, code)
            Fixtures.Settle(T, 0.4)
            local label = "Reiter " .. tab .. " / " .. code
            local problems = Layout.Check(Layout.Rects(Layout.TopLevel()), { truncateOk = R.truncateOk })
            local bad = relevant(problems)
            if #bad > 0 then
               H.fail(label .. ": " .. #bad .. " Layoutbefund(e)\n" .. Layout.Format(bad))
            end
         end
      end
      H.eq(#H.mock.errors, 0)
   end)
end
