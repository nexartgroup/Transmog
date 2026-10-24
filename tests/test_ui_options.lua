-- tests/test_ui_options.lua
-- ---------------------------------------------------------------------------
-- Tests fuer UI\Options.lua (Optionsfenster) gegen die ECHTEN Kernmodule
-- (Locale, Util, Events, DB) und das echte Skin auf der strengen Attrappe.
--
-- Geprueft wird das Verhalten (SPEC 6.10 / 11):
--   * Fenster: Name, ESC, Strata, mittig, ziehbar, Oeffnen/Schliessen/Umschalten
--   * Die Steuerelemente spiegeln DB.global beim Oeffnen und bei SETTINGS_CHANGED
--   * Rundlauf Steuerelement -> DB.Set (Haken, Regler, Vorschaugroesse, Sprache)
--   * Knoepfe rufen Window.ResetLayout / Toasts.ShowAnchor / Toasts.Test, und
--     fehlen diese Module, passiert nichts (kein Fehler)
--   * Sprachmenue: Auto + native Namen, Wechsel ueber DB.Set + Locale.Set
--   * Sprachwechsel setzt alle Texte neu; nie ein Schluessel als Text
--   * (Verifizierer) Skalierung des Optionsfensters, Werte ausserhalb des Bereichs,
--     Lesbarkeit von Sprachen auf dem Client, und das Zusammenspiel mit dem
--     echten Fenster (Regler -> Window genau einmal je Stufe, Zuruecksetzen,
--     Vorschaugroesse, Sprachwechsel in Optionen UND Outfit-Reiter, ESC,
--     Toast-Anker ueber dem Optionsfenster, Layout in drei Sprachen)
--
-- Aufruf (im Hauptverzeichnis):  luajit tests/run.lua ui_options
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   -- -------------------------------------------------------------------------
   -- Hilfen
   -- -------------------------------------------------------------------------

   -- Kernmodule laden (ohne Window/Toasts) und DB bereitstellen.
   -- spec.locale: Sprache des Clients (GetLocale); spec.db: Vorbelegung vor dem ersten Oeffnen
   -- spec.noSeed: true = echte Vorgaben seit 2.1 (Neuinstallation); ohne: "Anwenden auch ohne Transmogrifizierer" aus
   local function boot(spec)
      spec = spec or {}
      local world = { locale = spec.locale or "enUS" }
      local T = H.boot({ upTo = "UI\\Options.lua", login = false, world = world, noSeed = spec.noSeed })
      T.DB.Init()
      T.Locale.Set("auto")
      for k, v in pairs(spec.db or {}) do T.DB.Set(k, v) end
      return T, T.UI.Options
   end

   -- Ersatz fuer Window und Toasts, die andere Bearbeiter liefern
   local function stubs(T)
      local calls = { reset = 0, scale = 0, anchor = 0, test = 0, scaleSeen = {} }
      T.UI.Window = {
         ResetLayout = function() calls.reset = calls.reset + 1 end,
         ApplyScale = function()
            calls.scale = calls.scale + 1
            calls.scaleSeen[#calls.scaleSeen + 1] = T.DB.global.scale
         end,
      }
      T.Toasts = {
         ShowAnchor = function() calls.anchor = calls.anchor + 1 end,
         Test = function() calls.test = calls.test + 1 end,
      }
      return calls
   end

   local function menuRows()
      local out = {}
      local f = rawget(_G, "TransmogMenuFrame")
      if not f then return out end
      for _, b in ipairs(M.Find(f, "Button")) do
         if b:IsShown() and b.item then out[#out + 1] = b end
      end
      return out
   end

   local function menuTexts()
      local out = {}
      for i, r in ipairs(menuRows()) do out[i] = r.text:GetText() end
      return out
   end

   local function tipText()
      local parts = {}
      for i = 1, GameTooltip:NumLines() do
         local l = rawget(_G, "GameTooltipTextLeft" .. i)
         parts[#parts + 1] = l and l:GetText() or ""
      end
      return table.concat(parts, "\n")
   end

   local CHECK_KEYS = { "sound", "toasts", "tooltipCollected", "tooltipApplied", "allowAnywhere" }

   -- -------------------------------------------------------------------------
   H.section("Fenster")
   -- -------------------------------------------------------------------------

   H.test("Open baut TransmogOptionsFrame: Name, ESC, Strata, mittig, 400 breit, Kopf", function()
      local T, O = boot()
      H.eq(O.IsShown(), false)
      H.eq(rawget(_G, "TransmogOptionsFrame"), nil, "lazy: erst beim Oeffnen gebaut")
      O.Open()
      local f = TransmogOptionsFrame
      H.truthy(f)
      H.eq(O.frame, f)
      H.truthy(f:IsShown())
      H.truthy(O.IsShown())
      H.eq(f:GetFrameStrata(), "DIALOG")
      H.eq(f:GetWidth(), 400)
      H.truthy(f:GetHeight() >= 380 and f:GetHeight() <= 560, "Hoehe " .. f:GetHeight())
      local point, rel, relPoint, x, y = f:GetPoint()
      H.eq(point, "CENTER")
      H.eq(rel, UIParent)
      H.eq(relPoint, "CENTER")
      H.eq(x, 0)
      H.eq(y, 0)
      local found = false
      for _, n in ipairs(UISpecialFrames) do
         if n == "TransmogOptionsFrame" then found = true end
      end
      H.truthy(found, "in UISpecialFrames")
      H.truthy(M.HasText(f, "Transmog options"), "Titel")
      H.truthy(f:IsMovable())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Close, Toggle, wiederholtes Open; ESC schliesst; Schliessen-Knopf", function()
      local T, O = boot()
      O.Open()
      O.Open()
      H.truthy(O.IsShown())
      O.Close()
      H.falsy(O.IsShown())
      O.Toggle()
      H.truthy(O.IsShown())
      O.Toggle()
      H.falsy(O.IsShown())
      O.Open()
      H.truthy(M.Escape(), "ESC")
      H.falsy(O.IsShown())
      O.Open()
      M.Click(O.controls.close)
      H.falsy(O.IsShown())
      O.Close()          -- ohne Fenster/zweimal: kein Fehler
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Close ohne vorheriges Open wirft nicht; Toggle baut das Fenster", function()
      local T, O = boot()
      O.Close()
      H.falsy(O.IsShown())
      O.Toggle()
      H.truthy(O.IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ziehen verschiebt das Fenster; die Position bleibt beim erneuten Oeffnen", function()
      local T, O = boot()
      O.Open()
      local f = TransmogOptionsFrame
      M.Drag(f, 60, -40)
      local _, _, _, x, y = f:GetPoint()
      H.near(x, 60, 0.001)
      H.near(y, -40, 0.001)
      O.Close()
      O.Open()
      local _, _, _, x2, y2 = f:GetPoint()
      H.near(x2, 60, 0.001)
      H.near(y2, -40, 0.001)
   end)

   -- -------------------------------------------------------------------------
   H.section("Anzeige spiegelt DB")
   -- -------------------------------------------------------------------------

   H.test("Beim Oeffnen: Haken, Regler, Vorschaugroesse und Sprache zeigen DB.global", function()
      local T, O = boot({ locale = "deDE", db = {
         sound = false, toasts = false, tooltipCollected = false, tooltipApplied = true,
         allowAnywhere = true, scale = 0.8, previewSize = 1.25, locale = "deDE",
      } })
      T.Locale.Set("enUS")
      O.Open()
      local c = O.controls
      H.eq(c.checks.sound:GetChecked(), false)
      H.eq(c.checks.toasts:GetChecked(), false)
      H.eq(c.checks.tooltipCollected:GetChecked(), false)
      H.eq(c.checks.tooltipApplied:GetChecked(), true)
      H.eq(c.checks.allowAnywhere:GetChecked(), true)
      H.eq(c.scale:GetValue(), 80)
      H.eq(c.scale.valueText:GetText(), "80%")
      for _, b in ipairs(c.sizes) do
         H.eq(b:IsSelected(), b.value == 1.25, "Groesse " .. b.value)
      end
      H.eq(c.language:GetText(), "Deutsch")
   end)

   H.test("Standardwerte: Auto-Skalierung am linken Ende, Mittel gewaehlt, Sprache Auto mit Clientname", function()
      local T, O = boot({ locale = "frFR", noSeed = true })      -- Neuinstallation: die echten Vorgaben
      O.Open()
      local c = O.controls
      H.eq(c.scale:GetValue(), 55)
      H.eq(c.scale.valueText:GetText(), "Auto")
      H.eq(c.sizes[2]:IsSelected(), true)
      H.eq(c.sizes[1]:IsSelected(), false)
      H.eq(c.language:GetText(), string.format(T.L.OPT_LANG_AUTO, "Fran\195\167ais"))
      H.eq(c.checks.sound:GetChecked(), true)
      H.eq(c.checks.allowAnywhere:GetChecked(), true, "seit 2.1 standardmaessig an")
   end)

   H.test("Haken 'Anwenden auch ohne Transmogrifizierer': Neuinstallation an, Datei aus 2.0 (false) einmalig an, danach die Wahl", function()
      -- Neuinstallation
      local T, O = boot({ noSeed = true })
      O.Open()
      H.eq(O.controls.checks.allowAnywhere:GetChecked(), true)
      H.eq(T.DB.global.allowAnywhere, true)
      -- der Spieler schaltet aus; Neuanmeldung (SavedVariables): bleibt aus und zeigt es an
      M.Click(O.controls.checks.allowAnywhere)
      H.eq(T.DB.global.allowAnywhere, false)
      H.eq(O.controls.checks.allowAnywhere:GetChecked(), false)
      local sv = M.SavedVariables()
      O.Close()
      T = H.boot({ upTo = "UI\\Options.lua", login = false, world = { locale = "enUS" }, globals = sv })
      T.DB.Init()
      O = T.UI.Options
      O.Open()
      H.eq(T.DB.global.allowAnywhere, false)
      H.eq(O.controls.checks.allowAnywhere:GetChecked(), false, "Wahl des Spielers bleibt")
      O.Close()
      -- Datei aus 2.0: allowAnywhere = false ohne Marke -> einmalig an, im Haken sichtbar
      T = H.boot({ upTo = "UI\\Options.lua", login = false, world = { locale = "enUS" },
                   globals = { TransmogGlobalDB = { version = 2, allowAnywhere = false, scale = 1.1 } } })
      T.DB.Init()
      O = T.UI.Options
      O.Open()
      H.eq(O.controls.checks.allowAnywhere:GetChecked(), true, "Datei aus 2.0: einmalig an")
      H.eq(T.DB.global.scale, 1.1, "uebrige Einstellungen bleiben")
      -- und mit "aus" + Marke (spaetere Datei) bleibt es aus
      O.Close()
      T = H.boot({ upTo = "UI\\Options.lua", login = false, world = { locale = "enUS" },
                   globals = { TransmogGlobalDB = { version = 2, allowAnywhere = false, noNpcDefault = true } } })
      T.DB.Init()
      T.UI.Options.Open()
      H.eq(T.UI.Options.controls.checks.allowAnywhere:GetChecked(), false)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Clientsprachen ohne eigenen Eintrag (enGB, esMX) nennen die Ersatzsprache", function()
      local T, O = boot({ locale = "enGB" })
      O.Open()
      H.eq(O.controls.language:GetText(), "Auto (client language: English)")
      O.Close()
      T, O = boot({ locale = "esMX", db = { locale = "esMX" } })
      O.Open()
      H.eq(O.controls.language:GetText(), "Espa\195\177ol")
   end)

   H.test("SETTINGS_CHANGED waehrend es offen ist aktualisiert die Anzeige; verborgen: beim Oeffnen", function()
      local T, O = boot()
      O.Open()
      local c = O.controls
      T.DB.Set("sound", false)
      H.eq(c.checks.sound:GetChecked(), false)
      T.DB.Set("scale", 1.25)
      H.eq(c.scale:GetValue(), 125)
      H.eq(c.scale.valueText:GetText(), "125%")
      T.DB.Set("previewSize", 0.8)
      H.eq(c.sizes[1]:IsSelected(), true)
      H.eq(c.sizes[2]:IsSelected(), false)
      O.Close()
      T.DB.Set("toasts", false)
      T.DB.Set("scale", 0)
      O.Open()
      H.eq(c.checks.toasts:GetChecked(), false)
      H.eq(c.scale:GetValue(), 55)
      H.eq(c.scale.valueText:GetText(), "Auto")
   end)

   -- -------------------------------------------------------------------------
   H.section("Rundlauf Steuerelement -> DB")
   -- -------------------------------------------------------------------------

   H.test("Haken: jeder Klick setzt DB.Set(key, bool) und feuert SETTINGS_CHANGED(key)", function()
      local T, O = boot()
      O.Open()
      local changed = {}
      T.Events.On("SETTINGS_CHANGED", function(key) changed[#changed + 1] = key end, changed)
      for _, key in ipairs(CHECK_KEYS) do
         local c = O.controls.checks[key]
         H.truthy(c, key)
         local before = T.DB.global[key]
         M.Click(c)
         H.eq(T.DB.global[key], not before, key .. " umgeschaltet")
         H.eq(c:GetChecked(), not before)
         M.Click(c)
         H.eq(T.DB.global[key], before, key .. " zurueck")
      end
      H.eq(#changed, 2 * #CHECK_KEYS)
      H.eq(changed[1], "sound")
      H.eq(changed[3], "toasts")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Regler: Auto am linken Ende, dann 60 bis 150 Prozent in 5er-Schritten, jede Stufe ein SETTINGS_CHANGED(scale)", function()
      local T, O = boot()
      local calls = stubs(T)
      O.Open()
      -- das Fenster (hier ein Ersatz) hoert auf SETTINGS_CHANGED und wendet den Wert an (SPEC 11.3)
      local seen = {}
      T.Events.On("SETTINGS_CHANGED", function(key)
         if key == "scale" then seen[#seen + 1] = T.DB.global.scale end
      end, seen)
      local s = O.controls.scale
      H.eq(s.minV, 55)
      H.eq(s.maxV, 150)
      H.eq(s.stepV, 5)
      s:SetValue(100)
      H.near(T.DB.global.scale, 1.0, 1e-9)
      H.eq(#seen, 1)
      H.near(seen[1], 1.0, 1e-9, "Hoerer sieht den neuen Wert")
      H.eq(s.valueText:GetText(), "100%")
      s:SetValue(65)
      H.near(T.DB.global.scale, 0.65, 1e-9)
      H.eq(s.valueText:GetText(), "65%")
      s:SetValue(150)
      H.near(T.DB.global.scale, 1.5, 1e-9)
      s:SetValue(60)
      H.near(T.DB.global.scale, 0.6, 1e-9)
      s:SetValue(55)
      H.eq(T.DB.global.scale, 0, "Auto")
      H.eq(s.valueText:GetText(), "Auto")
      H.eq(#seen, 5)
      H.eq(calls.scale, 0, "Options ruft Window.ApplyScale nicht selbst (sonst doppelte Anordnung je Stufe)")
      -- Mausrad wie ein Pfeil: ein Schritt
      M.Wheel(s, 1)
      H.near(T.DB.global.scale, 0.6, 1e-9)
      -- programmatisches Setzen loest nichts aus
      local n = #seen
      s:SetValueQuiet(120)
      H.eq(#seen, n)
      H.eq(T.DB.global.scale, 0.6)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Regler ohne Window-Modul: DB wird gesetzt, kein Fehler", function()
      local T, O = boot()
      H.eq(T.UI.Window, nil)
      O.Open()
      O.controls.scale:SetValue(80)
      H.near(T.DB.global.scale, 0.8, 1e-9)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Vorschaugroesse: vier Knoepfe 0.8 / 1.0 / 1.25 / 1.5 setzen DB.previewSize", function()
      local T, O = boot()
      O.Open()
      local sizes = O.controls.sizes
      H.len(sizes, 4)
      local want = { 0.8, 1.0, 1.25, 1.5 }
      local labels = { "Small", "Medium", "Large", "Extra large" }
      for i = 1, 4 do
         H.eq(sizes[i]:GetText(), labels[i])
         M.Click(sizes[i])
         H.near(T.DB.global.previewSize, want[i], 1e-9)
         for j = 1, 4 do
            H.eq(sizes[j]:IsSelected(), i == j, "Auswahl " .. i .. "/" .. j)
         end
      end
   end)

   H.test("Knoepfe: Fenster zuruecksetzen, Benachrichtigungen verschieben, Testbenachrichtigung", function()
      local T, O = boot()
      local calls = stubs(T)
      O.Open()
      local c = O.controls
      H.eq(c.reset:GetText(), "Reset window position and size")
      M.Click(c.reset)
      H.eq(calls.reset, 1)
      M.Click(c.moveToasts)
      H.eq(calls.anchor, 1)
      M.Click(c.testToast)
      H.eq(calls.test, 1)
      H.eq(calls.scale, 0, "kein ApplyScale durch die Knoepfe")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Knoepfe ohne Window/Toasts: Klicks sind harmlos", function()
      local T, O = boot()
      O.Open()
      local c = O.controls
      M.Click(c.reset)
      M.Click(c.moveToasts)
      M.Click(c.testToast)
      H.deepEq(H.takeErrors(), {})
      H.truthy(O.IsShown())
   end)

   H.test("allowAnywhere-Tooltip erklaert, dass der Server den Abstand nicht prueft, die Vorgabe und den Vorschau-Modus", function()
      local T, O = boot({ noSeed = true })
      O.Open()
      local c = O.controls.checks.allowAnywhere
      H.eq(c:GetChecked(), true)
      M.Enter(c)
      local text = tipText()
      H.truthy(text:find("does not check your distance", 1, true), text)
      H.truthy(text:find("(the default)", 1, true), "an ist die Vorgabe: " .. text)
      H.truthy(text:find("preview mode", 1, true), "aus = Vorschau-Modus: " .. text)
      H.truthy(text:find("/transmog", 1, true), text)
      H.truthy(text:find("Allow applying without a transmogrifier", 1, true), "Titel der Zeile: " .. text)
      M.Leave(c)
      M.Enter(O.controls.scale)
      H.truthy(tipText():find("Auto fits the window", 1, true))
      M.Leave(O.controls.scale)
   end)

   -- -------------------------------------------------------------------------
   H.section("Sprache")
   -- -------------------------------------------------------------------------

   H.test("Sprachmenue: Auto (Clientsprache) + native Namen, aktuelle Auswahl markiert", function()
      local T, O = boot({ locale = "deDE" })
      O.Open()
      M.Click(O.controls.language)
      H.truthy(Transmog.UI.Skin.Menu.IsOpen())
      -- Kyrillisch und CJK kann die lateinische Clientschrift nicht zeichnen: dort steht der Code dahinter
      H.deepEq(menuTexts(), {
         string.format(T.L.OPT_LANG_AUTO, "Deutsch"), "English", "Deutsch", "Fran\195\167ais", "Espa\195\177ol",
         "\208\160\209\131\209\129\209\129\208\186\208\184\208\185 (ruRU)",
         "\237\149\156\234\181\173\236\150\180 (koKR)",
         "\231\174\128\228\189\147\228\184\173\230\150\135 (zhCN)",
         "\231\185\129\233\171\148\228\184\173\230\150\135 (zhTW)",
      })
      local rows = menuRows()
      H.truthy(rows[1].item.checked, "Auto ist gewaehlt")
      H.truthy(rows[1].item.radio)
      H.falsy(rows[3].item.checked)
      Transmog.UI.Skin.Menu.Close()
   end)

   H.test("Sprache waehlen: DB.Set(locale) UND Locale.Set; Menue schliesst; Texte folgen", function()
      local T, O = boot()
      T.Locale.Add("deDE", { OPT_TITLE = "Transmog-Optionen", OPT_SOUND = "Ton beim Anwenden" })
      O.Open()
      H.truthy(M.HasText(TransmogOptionsFrame, "Transmog options"))
      local setCalls = {}
      local origSet = T.Locale.Set
      T.Locale.Set = function(code)
         setCalls[#setCalls + 1] = code
         return origSet(code)
      end
      M.Click(O.controls.language)
      local rows = menuRows()
      H.eq(rows[3].text:GetText(), "Deutsch")
      M.Click(rows[3])
      H.falsy(Transmog.UI.Skin.Menu.IsOpen())
      H.eq(T.DB.global.locale, "deDE")
      H.deepEq(setCalls, { "deDE" })
      H.eq(T.Locale.Current(), "deDE")
      H.eq(O.controls.head.title:GetText(), "Transmog-Optionen")
      H.eq(O.controls.checks.sound.label:GetText(), "Ton beim Anwenden")
      H.eq(O.controls.language:GetText(), "Deutsch")
      -- zurueck auf Auto
      M.Click(O.controls.language)
      M.Click(menuRows()[1])
      H.eq(T.DB.global.locale, "auto")
      H.deepEq(setCalls, { "deDE", "auto" })
      H.eq(O.controls.head.title:GetText(), "Transmog options")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Schrifthinweis: gelb, wenn die Zielsprache eine andere Schrift braucht als der Client", function()
      local T, O = boot({ locale = "enUS" })
      O.Open()
      local note = O.controls.note
      H.truthy(M.HasText(TransmogOptionsFrame, "the font may lack some characters"))
      local function color() return { note:GetTextColor() } end
      -- gleiche Schriftgruppe: grau
      T.DB.Set("locale", "deDE")
      T.Locale.Set("deDE")
      H.near(color()[1], 0.50, 0.02, "latin -> latin: grau")
      -- kyrillisch auf lateinischem Client: gelb
      T.DB.Set("locale", "ruRU")
      T.Locale.Set("ruRU")
      H.near(color()[1], 0.91, 0.02, "cyrillic: gelb")
      T.DB.Set("locale", "auto")
      T.Locale.Set("auto")
      H.near(color()[1], 0.50, 0.02, "auto: grau")
   end)

   H.test("Sprachwechsel setzt ALLE Texte des Fensters neu (kein Schluessel bleibt stehen)", function()
      local T, O = boot()
      -- Teststrings: alle OPT_*-Schluessel mit Marker in "deDE"
      local de = {}
      for key, text in pairs(T.L) do
         if type(key) == "string" and key:find("^OPT_") then
            de[key] = "DE " .. text
         end
      end
      H.truthy(next(de), "OPT_-Schluessel vorhanden")
      T.Locale.Add("deDE", de)
      O.Open()
      T.Locale.Set("deDE")
      local f = TransmogOptionsFrame
      for _, t in ipairs(M.Texts(f, true)) do
         H.falsy(t:find("^OPT_[A-Z_]+$"), "Schluessel als Text: " .. t)
      end
      local c = O.controls
      H.eq(c.head.title:GetText(), "DE Transmog options")
      H.eq(c.reset:GetText(), "DE Reset window position and size")
      H.eq(c.moveToasts:GetText(), "DE Move notifications")
      H.eq(c.testToast:GetText(), "DE Test notification")
      H.eq(c.sizes[4]:GetText(), "DE Extra large")
      H.eq(c.checks.sound.label:GetText(), "DE Sound when applying")
      H.eq(c.checks.allowAnywhere.label:GetText(), "DE Allow applying without a transmogrifier")
      H.eq(c.scale.valueText:GetText(), "DE Auto")
      H.truthy(M.HasText(f, "DE Language"))
      H.truthy(M.HasText(f, "DE Window"))
      H.truthy(M.HasText(f, "DE General"))
      H.truthy(M.HasText(f, "DE Preview size"))
      H.truthy(M.HasText(f, "DE If the language differs"))
      -- Tooltip folgt der Sprache
      M.Enter(c.checks.toasts)
      H.truthy(tipText():find("DE Notifications for new appearances", 1, true))
      M.Leave(c.checks.toasts)
      T.Locale.Set("enUS")
      H.eq(c.head.title:GetText(), "Transmog options")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Alle Optionstexte stehen in enUS: keine fehlenden Schluessel mit Praefix OPT_", function()
      local T, O = boot()
      O.Open()
      for _, c in pairs(O.controls.checks) do
         M.Enter(c)
         M.Leave(c)
      end
      M.Enter(O.controls.language)
      M.Leave(O.controls.language)
      for key in pairs(T.L.__missing) do
         H.falsy(key:find("^OPT_"), "fehlender Schluessel: " .. key)
      end
   end)

   -- -------------------------------------------------------------------------
   H.section("Aufraeumen")
   -- -------------------------------------------------------------------------

   H.test("Schliessen des Fensters schliesst das Sprachmenue; kein haengendes OnUpdate", function()
      local T, O = boot()
      O.Open()
      M.Click(O.controls.language)
      H.truthy(Transmog.UI.Skin.Menu.IsOpen())
      O.Close()
      H.falsy(Transmog.UI.Skin.Menu.IsOpen())
      M.Advance(2)
      H.len(M.UpdateFrames(), 0, "kein sichtbarer OnUpdate-Frame")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Layout: alle Steuerelemente liegen innerhalb des Fensters, nichts ueberlappt senkrecht", function()
      local T, O = boot()
      O.Open()
      local f = TransmogOptionsFrame
      local c = O.controls
      local boxes = {}
      local function add(name, w)
         local _, _, _, x, y = w:GetPoint()
         boxes[#boxes + 1] = { name = name, x = x, top = -y, w = w:GetWidth(), h = w:GetHeight() }
      end
      add("language", c.language)
      add("scale", c.scale)
      for i, b in ipairs(c.sizes) do add("size" .. i, b) end
      add("reset", c.reset)
      for _, key in ipairs(CHECK_KEYS) do add(key, c.checks[key]) end
      add("moveToasts", c.moveToasts)
      add("testToast", c.testToast)
      for _, b in ipairs(boxes) do
         H.truthy(b.x >= 0 and b.x + b.w <= f:GetWidth() + 0.001, b.name .. " horizontal im Fenster")
         H.truthy(b.top + b.h <= f:GetHeight() + 0.001, b.name .. " vertikal im Fenster")
      end
      -- gleiche Zeile nur bei den Vorschau-/Toast-Knoepfen: sonst keine senkrechte Ueberlappung
      table.sort(boxes, function(a, b)
         if a.top ~= b.top then return a.top < b.top end
         return a.x < b.x
      end)
      for i = 2, #boxes do
         local a, b = boxes[i - 1], boxes[i]
         if a.top ~= b.top then
            H.truthy(a.top + a.h <= b.top + 0.001, a.name .. " / " .. b.name .. " ueberlappen senkrecht")
         else
            H.truthy(a.x + a.w <= b.x + 0.001, a.name .. " / " .. b.name .. " ueberlappen waagerecht")
         end
      end
   end)

   -- -------------------------------------------------------------------------
   H.section("Skalierung des Optionsfensters")
   -- -------------------------------------------------------------------------

   H.test("Optionsfenster folgt der Fensterskalierung (Window.ComputeScale), sonst DB.scale, sonst 1.0", function()
      local T, O = boot()
      O.Open()
      local f = TransmogOptionsFrame
      H.near(f:GetScale(), 1.0, 1e-6, "ohne Window, Auto: 1.0")
      O.Close()
      T.DB.Set("scale", 0.8)
      O.Open()
      H.near(f:GetScale(), 0.8, 1e-6, "ohne Window: DB.scale")
      O.Close()
      -- mit Window.ComputeScale (auch der Wert fuer "Auto")
      T.UI.Window = { ComputeScale = function() return 1.35 end }
      O.Open()
      H.near(f:GetScale(), 1.35, 1e-6)
      -- bei geoeffnetem Fenster bleibt es: der Regler darunter soll beim Ziehen nicht wandern
      T.UI.Window.ComputeScale = function() return 0.9 end
      O.Open()
      H.near(f:GetScale(), 1.35, 1e-6, "offen: unveraendert")
      O.Close()
      O.Open()
      H.near(f:GetScale(), 0.9, 1e-6, "beim naechsten Oeffnen")
      -- Unsinn wird geklemmt, ein werfendes ComputeScale nicht weitergereicht
      O.Close()
      T.UI.Window.ComputeScale = function() return 7 end
      O.Open()
      H.near(f:GetScale(), 1.5, 1e-6, "oben geklemmt")
      O.Close()
      T.UI.Window.ComputeScale = function() error("kaputt") end
      O.Open()
      H.near(f:GetScale(), 0.8, 1e-6, "Fehler: Rueckfall auf DB.scale")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Optionsfenster bleibt bei jedem Fensterscale auf dem Bildschirm (400 x Hoehe x Scale)", function()
      for _, sc in ipairs({ 0.7, 1.0, 1.5 }) do
         local T, O = boot()
         T.UI.Window = { ComputeScale = function() return sc end }
         O.Open()
         local f = TransmogOptionsFrame
         local sw, sh = GetScreenWidth(), GetScreenHeight()
         H.truthy(f:GetWidth() * f:GetScale() <= sw, "Breite bei Scale " .. sc)
         H.truthy(f:GetHeight() * f:GetScale() <= sh, "Hoehe bei Scale " .. sc)
      end
   end)

   -- -------------------------------------------------------------------------
   H.section("Werte ausserhalb des Bereichs")
   -- -------------------------------------------------------------------------

   H.test("DB bereinigt Werte, die Anzeige zeigt die bereinigten (Regler geklemmt, Groesse eingerastet)", function()
      local T, O = boot()
      O.Open()
      local c = O.controls
      T.DB.Set("scale", 9)
      H.eq(T.DB.global.scale, 1.5)
      H.eq(c.scale:GetValue(), 150)
      H.eq(c.scale.valueText:GetText(), "150%")
      T.DB.Set("scale", 0.3)
      H.eq(T.DB.global.scale, 0.6)
      H.eq(c.scale:GetValue(), 60)
      H.eq(c.scale.valueText:GetText(), "60%")
      T.DB.Set("scale", -3)
      H.eq(T.DB.global.scale, 0)
      H.eq(c.scale:GetValue(), 55)
      H.eq(c.scale.valueText:GetText(), "Auto")
      T.DB.Set("previewSize", 1.1)
      H.eq(T.DB.global.previewSize, 1.0)
      H.eq(c.sizes[2]:IsSelected(), true, "1.1 rastet auf Mittel")
      T.DB.Set("previewSize", 3)
      H.eq(c.sizes[4]:IsSelected(), true, "3 rastet auf Sehr gross")
      H.eq(c.sizes[2]:IsSelected(), false)
      T.DB.Set("sound", "ja")
      H.eq(T.DB.global.sound, true, "kein Boolean: Standard")
      H.eq(c.checks.sound:GetChecked(), true)
      T.DB.Set("locale", "xx")
      H.eq(T.DB.global.locale, "auto")
      H.eq(c.language:GetText(), "Auto (client language: English)")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Von Hand zerstoerte DB.global (ohne DB.Set): Anzeige wirft nicht und zeigt Standardwerte", function()
      local T, O = boot()
      O.Open()
      local g = T.DB.global
      g.scale, g.previewSize, g.locale = "abc", nil, 5
      O.Close()
      O.Open()
      local c = O.controls
      H.eq(c.scale:GetValue(), 55)
      H.eq(c.scale.valueText:GetText(), "Auto")
      H.eq(c.sizes[2]:IsSelected(), true, "previewSize nil: Mittel")
      H.eq(c.language:GetText(), "5", "unbekannter Code: wird als Text gezeigt")
      g.scale = 0.97
      T.Events.Fire("SETTINGS_CHANGED", "scale")
      H.eq(c.scale:GetValue(), 95, "0.97 -> 95 %")
      g.scale = 0.125
      T.Events.Fire("SETTINGS_CHANGED", "scale")
      H.eq(c.scale:GetValue(), 60, "unter 0.6 -> 60 %, nicht Auto")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("SETTINGS_CHANGED bei geschlossenem Fenster rechnet nichts (Regler, Haken bleiben unberuehrt)", function()
      local T, O = boot()
      O.Open()
      O.Close()
      local n = 0
      local scale = O.controls.scale
      local orig = scale.SetValueQuiet
      scale.SetValueQuiet = function(...) n = n + 1 return orig(...) end
      for i = 1, 50 do T.DB.SetChar("lastSlot", 0) end
      T.DB.Set("width", 900)
      H.eq(n, 0)
      scale.SetValueQuiet = orig
   end)

   H.test("Wertetext des Reglers hat feste Breite: auch 'Automatisch' bleibt im Fenster", function()
      local T, O = boot()
      T.Locale.Add("deDE", { OPT_SCALE_AUTO = "Automatisch" })
      T.Locale.Set("deDE")
      O.Open()
      local c = O.controls
      H.eq(c.scale.valueText:GetText(), "Automatisch")
      local _, _, _, sx = c.scale:GetPoint()
      local vt = c.scale.valueText
      H.truthy(vt:GetWidth() > 0 and vt:GetWidth() <= 72, "feste Breite " .. tostring(vt:GetWidth()))
      -- rechter Rand des Wertetexts: Regler + 8 + Breite <= Fensterbreite - Rand
      H.truthy(sx + c.scale:GetWidth() + 8 + vt:GetWidth() <= 400 - 16 + 0.001,
         "Wertetext endet vor dem rechten Rand")
      -- der Text passt in seine Breite (Schaetzung der Attrappe 5.5 px je Zeichen bei 10 pt)
      H.truthy(vt:GetStringWidth() <= vt:GetWidth() + 0.001)
   end)

   -- -------------------------------------------------------------------------
   H.section("Sprache: Lesbarkeit")
   -- -------------------------------------------------------------------------

   local function texts(clientLocale)
      local T, O = boot({ locale = clientLocale })
      O.Open()
      M.Click(O.controls.language)
      local t = menuTexts()
      Transmog.UI.Skin.Menu.Close()
      return t, T, O
   end

   H.test("Sprachmenue: Code nur hinter Eintraegen, die die Schrift des Clients nicht darstellt", function()
      local ru = "\208\160\209\131\209\129\209\129\208\186\208\184\208\185"
      local ko = "\237\149\156\234\181\173\236\150\180"
      local zhs = "\231\174\128\228\189\147\228\184\173\230\150\135"
      local zht = "\231\185\129\233\171\148\228\184\173\230\150\135"
      -- ruRU-Client: Kyrillisch lesbar, CJK nicht
      local t = texts("ruRU")
      H.eq(t[6], ru, "Kyrillisch auf ruRU-Client")
      H.eq(t[7], ko .. " (koKR)")
      H.eq(t[8], zhs .. " (zhCN)")
      -- koKR-Client: Hangul lesbar; Lateinisch ist auf jedem Client lesbar
      t = texts("koKR")
      H.eq(t[2], "English")
      H.eq(t[3], "Deutsch")
      H.eq(t[6], ru .. " (ruRU)")
      H.eq(t[7], ko)
      H.eq(t[9], zht .. " (zhTW)")
      -- zhTW-Client
      t = texts("zhTW")
      H.eq(t[8], zhs .. " (zhCN)")
      H.eq(t[9], zht)
   end)

   H.test("Sprachknopf nennt eine unlesbare Sprache mit Code; Schrifthinweis nur bei echter Abweichung", function()
      local ko = "\237\149\156\234\181\173\236\150\180"
      local T, O = boot({ locale = "enUS", db = { locale = "koKR" } })
      T.Locale.Set("koKR")
      O.Open()
      H.eq(O.controls.language:GetText(), ko .. " (koKR)")
      local note = O.controls.note
      H.near(({ note:GetTextColor() })[1], 0.91, 0.02, "Hangul auf lateinischem Client: gelb")
      O.Close()
      -- koKR-Client mit englischem Addon: Lateinisch kann jeder Client, kein Fehlalarm
      T, O = boot({ locale = "koKR", db = { locale = "enUS" } })
      T.Locale.Set("enUS")
      O.Open()
      H.eq(O.controls.language:GetText(), "English")
      H.near(({ O.controls.note:GetTextColor() })[1], 0.50, 0.02, "Latin auf koKR-Client: grau")
      O.Close()
      -- ruRU-Client mit koreanischem Addon: gelb
      T, O = boot({ locale = "ruRU", db = { locale = "koKR" } })
      T.Locale.Set("koKR")
      O.Open()
      H.near(({ O.controls.note:GetTextColor() })[1], 0.91, 0.02, "Hangul auf ruRU-Client: gelb")
      O.Close()
      -- ruRU-Client mit russischem Addon: grau
      T, O = boot({ locale = "ruRU", db = { locale = "ruRU" } })
      T.Locale.Set("ruRU")
      O.Open()
      H.near(({ O.controls.note:GetTextColor() })[1], 0.50, 0.02, "Kyrillisch auf ruRU-Client: grau")
   end)

   -- -------------------------------------------------------------------------
   H.section("Zusammenspiel mit dem echten Fenster")
   -- -------------------------------------------------------------------------

   local Fixtures = require("fixtures")

   -- Kompletter Start (echte TOC, Serverattrappe), Fenster am NPC geoeffnet. Rueckgabe: T, Window, Options
   local function bootAll(opts)
      opts = opts or {}
      local T = Fixtures.Boot(H, { locale = opts.locale or "enUS", screen = opts.screen or { w = 1366, h = 768 },
                                   noSeed = opts.noSeed })
      Fixtures.ServerHello(T)
      Fixtures.ServerAutoReply(T)
      if opts.open ~= false then
         Fixtures.OpenAtNpc(T)
         Fixtures.Settle(T, 1.0)
      end
      return T, T.UI.Window, T.UI.Options
   end

   H.test("Regler: das Fenster uebernimmt den Wert genau einmal je Stufe; Optionsfenster wandert nicht", function()
      local T, W, O = bootAll({ screen = { w = 1920, h = 1080 } })
      O.Open()
      local f = TransmogOptionsFrame
      local before = f:GetScale()
      local applied, layouts = 0, 0
      local origA, origL = W.ApplyScale, W.Layout
      W.ApplyScale = function(...) applied = applied + 1 return origA(...) end
      W.Layout = function(...) layouts = layouts + 1 return origL(...) end
      O.controls.scale:SetValue(120)
      H.near(T.DB.global.scale, 1.2, 1e-9)
      H.near(TransmogWindow:GetScale(), 1.2, 1e-6, "Fenster skaliert")
      H.eq(applied, 1, "ApplyScale je Stufe einmal")
      H.eq(layouts, 1, "Layout je Stufe einmal")
      H.eq(f:GetScale(), before, "Optionsfenster bleibt, solange es offen ist")
      O.controls.scale:SetValue(55)
      H.eq(T.DB.global.scale, 0)
      H.eq(applied, 2)
      -- Auto: der berechnete Wert (nicht 0 oder 1)
      H.near(TransmogWindow:GetScale(), W.ComputeScale(), 1e-6)
      H.truthy(TransmogWindow:GetScale() > 1.0, "auf 1920x1080 ist Auto groesser als 1")
      W.ApplyScale, W.Layout = origA, origL
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Optionsfenster oeffnet beim naechsten Mal in der Fensterskalierung (auch bei Auto)", function()
      local T, W, O = bootAll({ screen = { w = 1920, h = 1080 } })
      O.Open()
      H.near(TransmogOptionsFrame:GetScale(), W.ComputeScale(), 1e-6)
      O.controls.scale:SetValue(90)
      O.Close()
      O.Open()
      H.near(TransmogOptionsFrame:GetScale(), 0.9, 1e-6)
   end)

   H.test("Zuruecksetzen: Fenstergroesse und Position gehen zurueck, Skalierung und Optionen bleiben", function()
      local T, W, O = bootAll()
      T.DB.Set("scale", 1.1)
      T.DB.Set("width", 1000)
      T.DB.Set("height", 700)
      O.Open()
      M.Click(O.controls.reset)
      H.eq(T.DB.global.width, 880)
      H.eq(T.DB.global.height, 600)
      H.eq(T.DB.global.point, nil)
      H.near(T.DB.global.scale, 1.1, 1e-9, "Skalierung gehoert nicht dazu")
      H.truthy(O.IsShown(), "Optionen bleiben offen")
      H.eq(O.controls.scale:GetValue(), 110)
      local last = M.messages[#M.messages]
      H.truthy(last:find(T.L.OPT_RESET_DONE, 1, true), "Meldung im Chat")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Vorschaugroesse: Knopf aendert die Zellen des Rasters sofort", function()
      local T, W, O = bootAll()
      local Grid = T.UI.Grid
      O.Open()
      local before = Grid.cellW
      M.Click(O.controls.sizes[4])
      Fixtures.Settle(T, 0.3)
      H.eq(Grid.scale, 1.5)
      H.truthy(Grid.cellW > before, "Zelle breiter als vorher")
      M.Click(O.controls.sizes[1])
      Fixtures.Settle(T, 0.3)
      H.eq(Grid.scale, 0.8)
      H.truthy(Grid.cellW < before)
   end)

   H.test("Haken: Wirkung auf die Module (Ton, Tooltips, Toasts, 'ohne Transmogrifizierer')", function()
      local T, W, O = bootAll({ noSeed = true })          -- Neuinstallation: "ohne Transmogrifizierer" ist an
      O.Open()
      local g = T.DB.global
      -- allowAnywhere: Anwenden-Grund VENDOR kommt beim Ausschalten und verschwindet beim Einschalten
      T.State.SetVendor(false)
      T.State.Select(0, Fixtures.List(T, 0)[1])
      H.eq(g.allowAnywhere, true, "Vorgabe seit 2.1")
      H.eq(O.controls.checks.allowAnywhere:GetChecked(), true, "Haken steht an")
      local ok, why = T.State.CanApply()
      H.neq(why, "APPLY_REASON_VENDOR", "Vorgabe an: kein Vendor-Grund")
      M.Click(O.controls.checks.allowAnywhere)
      H.eq(g.allowAnywhere, false)
      ok, why = T.State.CanApply()
      H.eq(why, "APPLY_REASON_VENDOR", "ausgeschaltet: Vorschau-Modus")
      M.Click(O.controls.checks.allowAnywhere)
      H.eq(g.allowAnywhere, true)
      ok, why = T.State.CanApply()
      H.neq(why, "APPLY_REASON_VENDOR", "allowAnywhere hebt den Vendor-Grund auf")
      -- toasts: aus -> Test-Knopf zeigt trotzdem eine Karte (Probe)
      M.Click(O.controls.checks.toasts)
      H.eq(g.toasts, false)
      M.Click(O.controls.testToast)
      Fixtures.Settle(T, 0.5)
      H.truthy(T.Toasts.Stats().visible + T.Toasts.Stats().queued >= 1, "Probekarte")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Verschieben/Testkarte: Anker und Karte liegen ueber dem Optionsfenster (nicht dahinter)", function()
      local T, W, O = bootAll({ screen = { w = 1366, h = 768 } })
      O.Open()
      local f = TransmogOptionsFrame
      M.Click(O.controls.moveToasts)
      Fixtures.Settle(T, 0.3)
      local anchor = rawget(_G, "TransmogToastAnchor")
      H.truthy(anchor and anchor:IsShown(), "Anker sichtbar")
      H.eq(anchor:GetFrameStrata(), f:GetFrameStrata())
      H.truthy(anchor:GetFrameLevel() > f:GetFrameLevel(), "Anker liegt ueber dem Optionsfenster")
      T.Toasts.HideAnchor()
      Fixtures.Settle(T, 1)
      O.Open()          -- hebt es wieder an
      M.Click(O.controls.testToast)
      Fixtures.Settle(T, 0.5)
      local card
      for _, o in ipairs({ UIParent:GetChildren() }) do
         if o ~= f and o:IsVisible() and M.HasText(o, T.L.TOAST_TITLE) then card = card or o end
      end
      H.truthy(card, "Probekarte sichtbar")
      H.eq(card:GetFrameStrata(), f:GetFrameStrata())
      H.truthy(card:GetFrameLevel() > f:GetFrameLevel(), "Karte liegt ueber dem Optionsfenster")
      H.truthy(O.IsShown(), "Optionen bleiben offen")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Sprachwechsel ueber das Menue: Optionsfenster UND Outfit-Reiter UND Fenster zugleich", function()
      local T, W, O = bootAll()
      -- jede Beschriftung der Komponenten in "deDE" mit Marker "DE " (die Texte stammen aus enUS)
      local de, enOpt = {}, {}
      for key, text in pairs(T.L) do
         if type(key) == "string" and type(text) == "string" and key:find("^OPT_") then
            de[key] = "DE " .. text
            enOpt[text] = true
         elseif type(key) == "string" and type(text) == "string" and (key:find("^OUTFITS_") or key:find("^WIN_")) then
            de[key] = "DE " .. text
         end
      end
      T.Locale.Add("deDE", de)
      T.Outfits.Save("Alpha", Fixtures.Looks(T, 1))
      W.SetTab("outfits")
      O.Open()
      Fixtures.Settle(T, 0.5)
      local OT = T.UI.OutfitsTab
      H.eq(OT.parts.save:GetText(), T.L.OUTFITS_SAVE)
      local before = OT.parts.save:GetText()
      local enTab = TransmogWindow.tabOutfits:GetText()
      M.Click(O.controls.language)
      local rows = menuRows()
      H.eq(rows[3].text:GetText(), "Deutsch")
      M.Click(rows[3])
      Fixtures.Settle(T, 0.3)
      H.eq(T.Locale.Current(), "deDE")
      H.eq(OT.parts.save:GetText(), "DE " .. before, "Outfit-Reiter")
      H.eq(OT.rows[1].load:GetText(), "DE Load")
      H.eq(OT.parts.pageText:GetText(), "DE Page 1 / 1")
      H.eq(O.controls.head.title:GetText(), "DE Transmog options", "Optionen")
      H.eq(O.controls.reset:GetText(), "DE Reset window position and size")
      H.eq(TransmogWindow.tabOutfits:GetText(), "DE " .. enTab, "Fenster-Reiter")
      -- kein sichtbarer Text des Optionsfensters und des Reiters bleibt Englisch
      local function check(root, label)
         for _, t in ipairs(M.Texts(root)) do
            H.falsy(enOpt[t], label .. ": englischer Text uebrig: " .. t)
            H.falsy(t:find("^OPT_[A-Z_]+$") or t:find("^OUTFITS?_[A-Z_]+$"), label .. ": Schluessel als Text: " .. t)
         end
      end
      check(TransmogOptionsFrame, "Optionen")
      check(OT.frame, "Outfits")
      -- und wieder zurueck
      M.Click(O.controls.language)
      M.Click(menuRows()[1])
      Fixtures.Settle(T, 0.3)
      H.eq(OT.parts.save:GetText(), before)
      H.eq(O.controls.head.title:GetText(), "Transmog options")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("ESC: erst das Sprachmenue, dann Optionen UND Fenster (UISpecialFrames schliesst alles auf einmal)", function()
      local T, W, O = bootAll()
      O.Open()
      M.Click(O.controls.language)
      H.truthy(Transmog.UI.Skin.Menu.IsOpen())
      M.Escape()
      H.falsy(Transmog.UI.Skin.Menu.IsOpen(), "ESC schliesst zuerst das Menue")
      H.truthy(O.IsShown(), "Optionen bleiben")
      H.truthy(W.IsShown(), "Fenster bleibt")
      M.Escape()
      H.falsy(O.IsShown())
      H.falsy(W.IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Fenster schliessen schliesst Optionen und Sprachmenue mit", function()
      local T, W, O = bootAll()
      O.Open()
      M.Click(O.controls.language)
      W.Close()
      H.falsy(O.IsShown())
      H.falsy(Transmog.UI.Skin.Menu.IsOpen())
      M.Advance(2)
      H.len(M.UpdateFrames(), 0, "kein haengendes OnUpdate")
   end)

   H.test("/transmog options ohne gebautes Fenster: Optionen oeffnen, das Fenster wird nicht gebaut", function()
      local T, W, O = bootAll({ open = false })
      H.eq(rawget(_G, "TransmogWindow"), nil)
      M.Slash("/transmog options")
      H.truthy(O.IsShown())
      H.eq(rawget(_G, "TransmogWindow"), nil, "Fenster nicht gebaut")
      H.near(TransmogOptionsFrame:GetScale(), W.ComputeScale(), 1e-6)
      -- Regler ohne gebautes Fenster: DB wird gesetzt, nichts geht kaputt
      O.controls.scale:SetValue(70)
      H.near(T.DB.global.scale, 0.7, 1e-9)
      H.eq(rawget(_G, "TransmogWindow"), nil)
      M.Click(O.controls.reset)
      H.deepEq(H.takeErrors(), {})
   end)

   -- -------------------------------------------------------------------------
   H.section("Layout in allen Sprachen, Robustheit")
   -- -------------------------------------------------------------------------

   H.test("Layout-Pruefung: keine Ueberlappung, kein zu breiter Text (englisch, lange deutsche und russische Texte)", function()
      local Layout = require("layout")
      local DE = {
         OPT_TITLE = "Transmog-Optionen",
         OPT_LANG_AUTO = "Automatisch (Clientsprache: %s)",
         OPT_LANG_NOTE = "Weicht die Sprache von deinem Spielclient ab, fehlen der Schrift eventuell einige Zeichen.",
         OPT_SECTION_WINDOW = "Fenster", OPT_SCALE = "Fensterskalierung", OPT_SCALE_AUTO = "Automatisch",
         OPT_PREVIEW_SIZE = "Vorschaugroesse", OPT_PREVIEW_LARGE = "Gross", OPT_PREVIEW_XLARGE = "Sehr gross",
         OPT_RESET_WINDOW = "Fensterposition und -groesse zuruecksetzen",
         OPT_SOUND = "Ton beim Anwenden",
         OPT_TOASTS = "Benachrichtigungen fuer neue Aussehen",
         OPT_TOOLTIP_COLLECTED = "Tooltip: \"Aussehen nicht gesammelt\" anzeigen",
         OPT_TOOLTIP_APPLIED = "Tooltip: \"Transmogrifiziert zu\" anzeigen",
         OPT_ALLOW_ANYWHERE = "Anwenden auch ohne Transmogrifizierer erlauben",
         OPT_MOVE_TOASTS = "Benachrichtigungen verschieben", OPT_TEST_TOAST = "Testbenachrichtigung",
      }
      local RU = {
         OPT_TITLE = "Настройки Transmog",
         OPT_LANG_AUTO = "Авто (язык клиента: %s)",
         OPT_LANG_NOTE = "Если язык отличается от языка клиента игры, в шрифте могут отсутствовать некоторые символы.",
         OPT_SCALE = "Масштаб окна", OPT_SCALE_AUTO = "Авто",
         OPT_PREVIEW_SIZE = "Размер предпросмотра", OPT_PREVIEW_SMALL = "Малый", OPT_PREVIEW_MEDIUM = "Средний",
         OPT_PREVIEW_LARGE = "Большой", OPT_PREVIEW_XLARGE = "Очень большой",
         OPT_RESET_WINDOW = "Сбросить положение и размер окна",
         OPT_SOUND = "Звук при применении",
         OPT_TOASTS = "Уведомления о новых образах",
         OPT_TOOLTIP_COLLECTED = "Подсказка: показывать \"образ не собран\"",
         OPT_TOOLTIP_APPLIED = "Подсказка: показывать \"трансмогрифицировано в\"",
         OPT_ALLOW_ANYWHERE = "Применять без трансмогрификатора",
         OPT_MOVE_TOASTS = "Переместить уведомления", OPT_TEST_TOAST = "Проверить уведомление",
      }
      for _, set in ipairs({ { "enUS", nil }, { "deDE", DE }, { "ruRU", RU } }) do
         local T, O = boot()
         if set[2] then T.Locale.Add(set[1], set[2]) end
         T.Locale.Set(set[1])
         O.Open()
         local entries = Layout.Rects(TransmogOptionsFrame)
         local problems = Layout.Check(entries)
         local bad = {}
         for _, p in ipairs(problems) do
            if p.severity ~= "info" then bad[#bad + 1] = p.kind .. " " .. tostring(p.path) end
         end
         H.deepEq(bad, {}, "Layout-Befunde in " .. set[1])
         O.Close()
      end
   end)

   H.test("Oeffnen/Schliessen/Umschalten 40 mal: keine neuen Frames, ein Satz Ereignishoerer", function()
      local T, O = boot()
      O.Open()
      local frames = #M.frames
      local fired = 0
      local origRefresh = O.Refresh
      for i = 1, 40 do
         O.Close()
         O.Toggle()
         O.Open()
      end
      H.eq(#M.frames, frames, "keine neuen Frames")
      -- ein SETTINGS_CHANGED aktualisiert die Anzeige genau einmal (kein doppelter Hoerer)
      local n = 0
      local scale = O.controls.scale
      local orig = scale.SetValueQuiet
      scale.SetValueQuiet = function(...) n = n + 1 return orig(...) end
      T.DB.Set("sound", false)
      H.eq(n, 1, "ein Hoerer")
      scale.SetValueQuiet = orig
   end)

   H.test("Regler: viele schnelle Eingaben enden im letzten Wert; DB und Anzeige stimmen, keine Fehler", function()
      local T, O = boot()
      O.Open()
      local s = O.controls.scale
      local last
      for i = 1, 200 do
         last = 55 + 5 * ((i * 7) % 20)
         s:SetValue(last)
      end
      local want = last < 60 and 0 or last / 100
      H.near(T.DB.global.scale, want, 1e-9)
      H.eq(s:GetValue(), last)
      H.eq(s.valueText:GetText(), last < 60 and "Auto" or string.format("%d%%", last))
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zufallsfolgen (fester Startwert): Oeffnen, Haken, Regler, Menue, ESC, Fenster, Sprache - Anzeige folgt der DB", function()
      local function lcg(seed)
         local v = seed
         return function(n)
            v = (v * 1103515245 + 12345) % 2147483648
            return (v % n) + 1
         end
      end
      local KEYS = { "sound", "toasts", "tooltipCollected", "tooltipApplied", "allowAnywhere" }
      for seed = 1, 6 do
         local T, W, O = bootAll({ open = false })
         T.Locale.Add("deDE", { OPT_TITLE = "Transmog-Optionen", OPT_SOUND = "Ton" })
         local rnd = lcg(seed * 7919)
         local Menu = Transmog.UI.Skin.Menu
         for step = 1, 60 do
            local op = rnd(14)
            local ctx = "Folge " .. seed .. " Schritt " .. step .. " Aktion " .. op
            if op == 1 then
               Fixtures.OpenAtNpc(T)
            elseif op == 2 then
               W.Close()
            elseif op == 3 then
               O.Open()
            elseif op == 4 then
               O.Close()
            elseif op == 5 then
               O.Toggle()
            elseif op == 6 and O.IsShown() then
               M.Click(O.controls.checks[KEYS[rnd(#KEYS)]])
            elseif op == 7 and O.IsShown() then
               O.controls.scale:SetValue(55 + 5 * (rnd(20) - 1))
            elseif op == 8 and O.IsShown() then
               M.Click(O.controls.sizes[rnd(4)])
            elseif op == 9 and O.IsShown() then
               M.Click(O.controls.language)
            elseif op == 10 and Menu.IsOpen() then
               local rows = menuRows()
               if #rows > 0 then M.Click(rows[rnd(math.min(#rows, 3))]) end
            elseif op == 11 then
               M.Escape()
            elseif op == 12 and O.IsShown() then
               M.Click(O.controls.reset)
            elseif op == 13 then
               T.DB.Set("scale", ({ 0, 0.6, 1.0, 1.5 })[rnd(4)])
            elseif op == 14 then
               T.Locale.Set(rnd(2) == 1 and "deDE" or "enUS")
            end
            Fixtures.Settle(T, 0.1)
            local errs = H.takeErrors()
            H.eq(#errs, 0, ctx .. ": " .. tostring(errs[1]))
            if O.IsShown() then
               local g = T.DB.global
               H.eq(O.controls.scale:GetValue(), g.scale == 0 and 55 or math.floor(g.scale * 100 + 0.5), ctx .. ": Regler")
               for _, k in ipairs(KEYS) do
                  H.eq(O.controls.checks[k]:GetChecked(), g[k] and true or false, ctx .. ": " .. k)
               end
               for i, b in ipairs(O.controls.sizes) do
                  H.eq(b:IsSelected(), math.abs(b.value - g.previewSize) < 0.001, ctx .. ": Groesse " .. i)
               end
            end
         end
      end
   end)
end
