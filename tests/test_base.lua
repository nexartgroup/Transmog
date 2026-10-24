-- tests/test_base.lua
-- ---------------------------------------------------------------------------
-- Tests der Basismodule: Locale, Init, Util, Events, DB, Slots sowie TOC,
-- Transmog.xml und Bindings.xml.
--
--     luajit tests/run.lua base
--
-- Geprueft wird das VERHALTEN laut SPEC (Abschnitte 3, 4, 5.1-5.5), nicht die
-- Implementierung. Die meisten Tests laden nur die Basismodule (die TOC bis
-- Core\Slots.lua) ohne PLAYER_LOGIN; so haengt das Ergebnis nicht von
-- Modulen ab, die parallel entstehen. DB.Init() ruft der Test selbst.
--
-- Aufbau:
--   1. TOC, XML, Dateien        4. Util (Text, Zahlen, Farben, Tabellen)
--   2. Locale                   5. Util (Timer)
--   3. Init                     6. Events, 7. DB, 8. Slots, 9. Zusammenspiel
-- ---------------------------------------------------------------------------

return function(H)
   local mock = H.mock
   local floor, ceil = math.floor, math.ceil

   -- Die Basismodule enden mit dieser Datei (TOC-Schreibweise).
   local BASE_UPTO = "Core\\Slots.lua"

   -- Laedt Locale, Init, Util, Events, DB und Slots; ADDON_LOADED wird gefeuert,
   -- PLAYER_LOGIN nicht (opts.login = true schaltet das ein).
   local function boot(opts)
      opts = opts or {}
      opts.upTo = opts.upTo or BASE_UPTO
      if opts.login == nil then opts.login = false end
      local T = H.boot(opts)
      H.assert(type(T) == "table", "Transmog wurde nicht geladen")
      return T
   end

   -- Letzte Chatzeile (oder nil).
   local function lastMessage()
      return mock.messages[#mock.messages]
   end

   -- Einfacher, wiederholbarer Zufallsgenerator (Park-Miller): rng(n) = 1..n.
   local function newRng(seed)
      local s = seed
      return function(n)
         s = (s * 16807) % 2147483647
         return (s % n) + 1
      end
   end

   -- UTF-8-Kodierung eines Codepoints (bis U+FFFF reicht hier).
   local function utf8char(cp)
      if cp < 0x80 then
         return string.char(cp)
      elseif cp < 0x800 then
         return string.char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
      end
      return string.char(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
   end

   -- Gesamter Dateiinhalt oder nil.
   local function readFile(path)
      local f = io.open(path, "rb")
      if not f then return nil end
      local s = f:read("*a")
      f:close()
      return s
   end

   -- Zeilen einer Datei ohne Zeilenende.
   local function linesOf(text)
      local out = {}
      for line in (text .. "\n"):gmatch("(.-)\r?\n") do out[#out + 1] = line end
      return out
   end

   -- Zahl der Frames, die ein bestimmtes Ereignis registriert haben.
   local function framesRegistered(event)
      local n = 0
      for _, f in ipairs(mock.frames) do
         local evs = rawget(f, "__events")
         if evs and evs[event] then n = n + 1 end
      end
      return n
   end

   -- Zerlegt einen Text unabhaengig von Util.Split (Referenz fuer den Zufallstest):
   -- Zeichen fuer Zeichen von links; passt der Trenner, wird ein Feld abgeschlossen.
   local function refSplit(s, sep)
      local out, cur, i = {}, {}, 1
      local n, m = #s, #sep
      while i <= n do
         if s:sub(i, i + m - 1) == sep then
            out[#out + 1] = table.concat(cur)
            cur = {}
            i = i + m
         else
            cur[#cur + 1] = s:sub(i, i)
            i = i + 1
         end
      end
      out[#out + 1] = table.concat(cur)
      return out
   end

   -- Referenz fuer FormatNumber (ganze Zahlen >= 0).
   local function refFormat(n, sep)
      local digits = string.format("%d", n)
      local out = ""
      local count = 0
      for i = #digits, 1, -1 do
         if count == 3 then
            out = sep .. out
            count = 0
         end
         out = digits:sub(i, i) .. out
         count = count + 1
      end
      return out
   end

   -- =======================================================================
   H.section("TOC, XML, Dateien")
   -- =======================================================================

   -- Reihenfolge laut SPEC 3 (ohne die frei hinzugefuegten Sprachdateien).
   local SPEC_ORDER = {
      "Locales\\Locale.lua", "Locales\\enUS_Core.lua", "Locales\\enUS_Window.lua",
      "Locales\\enUS_Grid.lua", "Locales\\enUS_Outfits.lua", "Locales\\enUS_Options.lua",
      "Locales\\enUS_Features.lua",
      "Locales\\deDE.lua", "Locales\\frFR.lua", "Locales\\esES.lua", "Locales\\ruRU.lua",
      "Locales\\koKR.lua", "Locales\\zhCN.lua", "Locales\\zhTW.lua",
      "Core\\Init.lua", "Core\\Util.lua", "Core\\Events.lua", "Core\\DB.lua", "Core\\Slots.lua",
      "Core\\Items.lua", "Core\\Net.lua", "Core\\State.lua", "Core\\Filter.lua", "Core\\Outfits.lua",
      "UI\\Skin.lua", "UI\\Cameras.lua", "UI\\Preview.lua", "UI\\SlotBar.lua", "UI\\Grid.lua",
      "UI\\FilterBar.lua", "UI\\OutfitsTab.lua", "UI\\Options.lua", "UI\\Window.lua",
      "Features\\Tooltips.lua", "Features\\Toasts.lua",
      "Core\\Boot.lua", "Transmog.xml", "Bindings.xml",
   }

   -- Einlesen der TOC: Kopfzeilen als Map, Dateien als Array.
   local function parseToc()
      local text = readFile(H.root .. "/Transmog.toc")
      H.assert(text, "Transmog.toc fehlt")
      local meta, files = {}, {}
      for _, line in ipairs(linesOf(text)) do
         local k, v = line:match("^##%s*([^:]+):%s*(.-)%s*$")
         if k then
            meta[k] = v
         elseif line:match("%S") and not line:match("^#") then
            files[#files + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""))
         end
      end
      return meta, files, text
   end

   -- Alle Lua-Dateien unterhalb des Addons (ohne tests/), relativ, mit Backslash.
   local function luaFilesOnDisk()
      local out = {}
      local p = io.popen('cd "' .. H.root .. '" && find . -type f -name "*.lua" -not -path "./tests/*" '
         .. '-not -path "./.*" 2>/dev/null')
      if p then
         for line in p:lines() do
            out[#out + 1] = (line:gsub("^%./", ""):gsub("/", "\\"))
         end
         p:close()
      end
      table.sort(out)
      return out
   end

   H.test("TOC: Kopfzeilen laut SPEC", function()
      local meta, _, text = parseToc()
      H.eq(meta.Interface, "30300")
      H.eq(meta.Title, "Transmog")
      H.eq(meta["Title-deDE"], "Transmogrifikation")
      H.eq(meta.Version, "2.1")
      H.eq(meta.Author, "nexartgroup")
      H.eq(meta["X-Website"], "https://github.com/nexartgroup/Transmog")
      -- Lizenz: AGPL-3.0 wie LICENSE und NOTICE (Kalibrierwerte und Klassennamen aus dem AGPL-Modul)
      H.eq(meta["X-License"], "AGPL-3.0-or-later")
      local licence = readFile(H.root .. "/LICENSE")
      H.truthy(licence and licence:find("GNU AFFERO GENERAL PUBLIC LICENSE", 1, true), "LICENSE ist die AGPL")
      local notice = readFile(H.root .. "/NOTICE")
      H.truthy(notice and notice:find("GNU Affero General Public License", 1, true), "NOTICE nennt die AGPL")
      H.truthy(meta.Notes and #meta.Notes > 10, "Notes")
      H.truthy(meta["Notes-deDE"] and #meta["Notes-deDE"] > 10, "Notes-deDE")
      H.eq(meta.SavedVariables, "TransmogGlobalDB")
      H.eq(meta.SavedVariablesPerCharacter, "TransmogDB, transmogOutfits, transmogSettings")
      H.eq(meta["X-Requires-Server-Module"], "mod-transmog-plus")
      H.falsy(text:find("\r", 1, true), "TOC mit LF-Zeilenenden")
      H.falsy(text:find("\239\187\191", 1, true), "TOC ohne BOM")
   end)

   H.test("Medien: kein Verweis auf Dateien im Addon-Ordner (nur Texturen und Toene des Clients)", function()
      -- Das Repository enthaelt bewusst keine Mediendateien (Texturen, Toene, Schriften):
      -- alles kommt aus dem Spielclient. Ein Verweis auf Interface\\AddOns\\Transmog\\...
      -- (Lua oder XML) wuerde eine Datei verlangen, die es nicht gibt.
      local function check(rel)
         local text = readFile(H.root .. "/" .. rel)
         H.truthy(text, rel .. " fehlt")
         if text then
            H.falsy(text:find("[Aa]dd[Oo]ns[\\/]+Transmog", 1), rel .. ": Verweis auf eine Datei im Addon-Ordner")
            H.falsy(text:find("%.ogg", 1), rel .. ": Verweis auf eine Tondatei")
            H.falsy(text:find("PlaySoundFile", 1, true), rel .. ": PlaySoundFile (nur PlaySound mit Standardton)")
         end
      end
      for _, rel in ipairs(luaFilesOnDisk()) do check((rel:gsub("\\", "/"))) end
      check("Transmog.xml")
      check("Bindings.xml")
   end)

   H.test("TOC: Reihenfolge entspricht SPEC, keine Doppelten, nur Backslashes", function()
      local _, files = parseToc()
      local pos = {}
      for i, f in ipairs(SPEC_ORDER) do pos[f] = i end
      local seen = {}
      local lastSpec, lastName = 0, nil
      local localeBlockEnd = nil
      for i, f in ipairs(files) do
         H.falsy(seen[f], "doppelter Eintrag " .. f)
         seen[f] = true
         H.falsy(f:find("/", 1, true), "Schraegstrich statt Backslash: " .. f)
         if pos[f] then
            H.truthy(pos[f] > lastSpec, f .. " steht vor " .. tostring(lastName))
            lastSpec, lastName = pos[f], f
         else
            -- nicht in der SPEC-Liste: nur zusaetzliche Sprachdateien (Texte anderer Module) erlaubt
            H.matches(f, "^Locales\\enUS_%w+%.lua$", "unbekannter TOC-Eintrag " .. f)
         end
         if f == "Core\\Init.lua" then localeBlockEnd = i end
      end
      -- Zusatz-Sprachdateien stehen vor dem ersten Core-Modul (L muss beim Laden gefuellt sein)
      for i, f in ipairs(files) do
         if f:match("^Locales\\") then
            H.truthy(localeBlockEnd and i < localeBlockEnd, f .. " steht hinter Core\\Init.lua")
         end
      end
      -- Uebersetzungen (deDE ... zhTW) stehen hinter ALLEN enUS_*-Dateien, in der Reihenfolge von SPEC_ORDER
      local lastEnUS = 0
      for i, f in ipairs(files) do
         if f:match("^Locales\\enUS_%w+%.lua$") then lastEnUS = i end
      end
      for i, f in ipairs(files) do
         if f:match("^Locales\\%a%a%a%a%.lua$") and not f:match("^Locales\\enUS") then
            H.truthy(i > lastEnUS, f .. " steht vor einer enUS-Datei")
         end
      end
      H.eq(files[1], "Locales\\Locale.lua", "Locale.lua zuerst (legt Transmog an)")
      H.eq(files[#files], "Bindings.xml")
      H.eq(files[#files - 1], "Transmog.xml")
      H.truthy(seen["Locales\\enUS_Core.lua"], "enUS_Core.lua gelistet")
   end)

   H.test("TOC: jede vorhandene Lua-Datei ist gelistet; Eintraege zeigen auf Dateien", function()
      local _, files = parseToc()
      local listed = {}
      for _, f in ipairs(files) do listed[f] = true end
      local onDisk = {}
      for _, f in ipairs(luaFilesOnDisk()) do
         onDisk[f] = true
         H.truthy(listed[f], "Datei " .. f .. " existiert, steht aber nicht in der TOC")
      end
      -- Fehlende Dateien: parallel entstehende Module fehlen im Arbeitsstand noch.
      -- Streng (Endabnahme) mit TRANSMOG_STRICT_TOC=1 in der Umgebung.
      local missing = {}
      for _, f in ipairs(files) do
         if not onDisk[f] and not f:match("%.xml$") then
            missing[#missing + 1] = f
         elseif f:match("%.xml$") then
            if not readFile(H.root .. "/" .. f) then missing[#missing + 1] = f end
         end
      end
      if os.getenv("TRANSMOG_STRICT_TOC") then
         H.len(missing, 0, "in der TOC gelistet, aber nicht vorhanden: " .. table.concat(missing, ", "))
      elseif #missing > 0 then
         mock.warnings[#mock.warnings + 1] = "TOC: noch nicht vorhanden: " .. table.concat(missing, ", ")
      end
      -- Grundstock muss existieren
      for _, f in ipairs({ "Locales\\Locale.lua", "Locales\\enUS_Core.lua", "Core\\Init.lua", "Core\\Util.lua",
                           "Core\\Events.lua", "Core\\DB.lua", "Core\\Slots.lua" }) do
         H.truthy(onDisk[f], f .. " fehlt")
      end
   end)

   H.test("Dateien: UTF-8 ohne BOM, LF, keine Tabs, kein Leerraum am Zeilenende, Syntax gueltig", function()
      local owned = { "Locales/Locale.lua", "Locales/enUS_Core.lua", "Core/Init.lua", "Core/Util.lua",
                      "Core/Events.lua", "Core/DB.lua", "Core/Slots.lua", "Transmog.toc",
                      "Transmog.xml", "Bindings.xml" }
      for _, rel in ipairs(owned) do
         local text = readFile(H.root .. "/" .. rel)
         H.truthy(text, rel .. " fehlt")
         if text then
            H.falsy(text:sub(1, 3) == "\239\187\191", rel .. ": BOM")
            H.falsy(text:find("\r", 1, true), rel .. ": CR")
            H.falsy(text:find("\t", 1, true), rel .. ": Tab")
            H.truthy(text:sub(-1) == "\n", rel .. ": Zeilenumbruch am Ende fehlt")
            for n, line in ipairs(linesOf(text)) do
               if line:match("%s$") then
                  H.fail(rel .. ":" .. n .. ": Leerraum am Zeilenende")
                  break
               end
            end
            if rel:match("%.lua$") then
               local chunk, err = loadfile(H.root .. "/" .. rel)
               H.truthy(chunk, rel .. ": " .. tostring(err))
            end
         end
      end
   end)

   H.test("Transmog.xml: genau die zwei virtuellen DressUpModel-Vorlagen laut SPEC 9.2", function()
      local text = readFile(H.root .. "/Transmog.xml")
      H.truthy(text, "Transmog.xml fehlt")
      text = text:gsub("<!%-%-.-%-%->", "")
      H.matches(text, 'xmlns="http://www.blizzard.com/wow/ui/"')
      H.matches(text, '<DressUpModel name="TransmogCellModelTemplate" virtual="true" scale="4%.0">')
      H.matches(text, '<DressUpModel name="TransmogPreviewModelTemplate" virtual="true" scale="2%.0" enableMouse="true">')
      H.matches(text, '<AbsDimension x="80" y="107"/>')
      H.matches(text, '<AbsDimension x="221" y="362"/>')
      local _, opens = text:gsub("<DressUpModel[%s>]", "")
      local _, closes = text:gsub("</DressUpModel>", "")
      H.eq(opens, 2, "zwei Vorlagen")
      H.eq(closes, 2, "geschlossen")
      -- Mock lernt die Vorlagen schon bei Install (templatesOnly)
      local t1 = mock.S.templates.TransmogCellModelTemplate
      local t2 = mock.S.templates.TransmogPreviewModelTemplate
      H.truthy(t1 and t2, "Vorlagen im Mock bekannt")
      if t1 then
         H.eq(t1.scale, 4.0)
         H.eq(t1.width, 80)
         H.eq(t1.height, 107)
      end
      if t2 then
         H.eq(t2.scale, 2.0)
         H.eq(t2.width, 221)
         H.eq(t2.height, 362)
         H.eq(t2.enableMouse, true)
      end
   end)

   H.test("XML: wohlgeformt (Kommentare ohne doppelten Bindestrich, gleich viele Tags)", function()
      for _, rel in ipairs({ "Transmog.xml", "Bindings.xml" }) do
         local text = readFile(H.root .. "/" .. rel)
         H.truthy(text, rel .. " fehlt")
         if text then
            H.falsy(text:find("\r", 1, true), rel .. ": CR")
            for body in text:gmatch("<!%-%-(.-)%-%->") do
               H.falsy(body:find("--", 1, true), rel .. ": '--' im Kommentar")
            end
            local stripped = text:gsub("<!%-%-.-%-%->", "")
            H.falsy(stripped:find("<!%-%-"), rel .. ": Kommentar nicht geschlossen")
            local root = rel == "Bindings.xml" and "Bindings" or "Ui"
            H.matches(stripped, "^%s*<" .. root .. "[%s>]", rel .. ": Wurzelelement " .. root)
            H.matches(stripped, "</" .. root .. ">%s*$", rel .. ": Wurzelelement geschlossen")
            -- jedes nicht selbstschliessende Element wird geschlossen
            local stack, ok = {}, true
            for slash, name, rest in stripped:gmatch("<(/?)([%a_][%w_]*)([^<>]*)>") do
               if slash == "/" then
                  if stack[#stack] ~= name then ok = false break end
                  stack[#stack] = nil
               elseif rest:sub(-1) ~= "/" then
                  stack[#stack + 1] = name
               end
            end
            H.truthy(ok and #stack == 0, rel .. ": Tags nicht ordentlich verschachtelt")
         end
      end
   end)

   H.test("Bindings.xml: TRANSMOG_TOGGLE ruft Window.Toggle, Kopfzeile TRANSMOG", function()
      local text = readFile(H.root .. "/Bindings.xml")
      H.truthy(text, "Bindings.xml fehlt")
      local _, open = text:gsub("<Bindings>", "")
      local _, close = text:gsub("</Bindings>", "")
      H.eq(open, 1)
      H.eq(close, 1)
      local attrs, code = text:match("<Binding%s+([^>]-)>(.-)</Binding>")
      H.truthy(attrs, "kein Binding")
      H.matches(attrs, 'name="TRANSMOG_TOGGLE"')
      H.matches(attrs, 'header="TRANSMOG"')
      H.matches(code, "Transmog%.UI%.Window%.Toggle%(%)")
      -- der Mock liest dieselbe Datei beim Laden der TOC
      H.boot({ login = false })
      local b = mock.bindings.TRANSMOG_TOGGLE
      H.truthy(b, "Binding im Mock geladen")
      if b then
         H.eq(b.header, "TRANSMOG")
         H.matches(b.code, "Transmog%.UI%.Window%.Toggle%(%)")
      end
   end)

   -- =======================================================================
   H.section("Locale")
   -- =======================================================================

   H.test("Locale: L ist eine stabile Tabelle; ohne Auswahl gilt Englisch", function()
      local T = boot()
      local L = T.L
      H.eq(type(L), "table")
      H.eq(L.THOUSANDS_SEP, ",")
      H.neq(T.Locale.Current(), "auto")
      H.eq(T.Locale.Current(), "enUS")
      T.Locale.Set("deDE")
      H.eq(T.L, L, "L nach Set")
      T.Locale.Add("deDE", { T_STABLE = "x" })
      H.eq(T.L, L, "L nach Add")
      T.Locale.Set("auto")
      H.eq(T.L, L, "L nach Set(auto)")
   end)

   H.test("Locale: fehlender Schluessel liefert den Schluessel und wird in L.__missing gemerkt", function()
      local T = boot()
      local L = T.L
      H.eq(L.NO_SUCH_KEY_X, "NO_SUCH_KEY_X")
      H.eq(rawget(L, "NO_SUCH_KEY_X"), nil, "kein echter Eintrag")
      H.eq(L.__missing.NO_SUCH_KEY_X, true)
      local missing = L.__missing
      T.Locale.Set("deDE")
      H.eq(L.__missing, missing, "__missing bleibt dieselbe Tabelle")
      H.eq(L.__missing.NO_SUCH_KEY_X, true, "Eintrag ueberlebt den Wechsel")
      -- Sobald der Schluessel existiert, gilt er nicht mehr als fehlend
      T.Locale.Add("enUS", { NO_SUCH_KEY_X = "now defined" })
      T.Locale.Set("enUS")
      H.eq(L.NO_SUCH_KEY_X, "now defined")
      H.eq(L.__missing.NO_SUCH_KEY_X, nil)
      -- Schluessel mit Praefix __ und Nicht-Strings werden nicht gemerkt, werfen aber nicht
      H.eq(L.__other, "__other")
      H.eq(L.__missing.__other, nil)
      H.eq(L[5], 5)
      H.eq(L[true], true)
   end)

   H.test("Locale: Fallback-Kette Sprache -> (esMX->esES, enGB->enUS) -> enUS", function()
      local T = boot()
      local Loc, L = T.Locale, T.L
      Loc.Add("enUS", { T_A = "en A", T_B = "en B", T_C = "en C" })
      Loc.Add("deDE", { T_A = "de A", T_B = "de B" })
      Loc.Add("esES", { T_A = "es A" })

      Loc.Set("deDE")
      H.eq(Loc.Current(), "deDE")
      H.eq(L.T_A, "de A")
      H.eq(L.T_B, "de B")
      H.eq(L.T_C, "en C", "fehlt in deDE -> Englisch")

      -- esMX ohne eigene Texte: esES, dann enUS
      Loc.Set("esMX")
      H.neq(Loc.Current(), "auto")
      H.eq(L.T_A, "es A")
      H.eq(L.T_B, "en B")
      H.eq(L.T_C, "en C")

      -- esMX mit eigenen Texten: esMX -> esES -> enUS
      Loc.Add("esMX", { T_B = "mx B" })
      Loc.Set("esMX")
      H.eq(Loc.Current(), "esMX")
      H.eq(L.T_A, "es A")
      H.eq(L.T_B, "mx B")
      H.eq(L.T_C, "en C")

      -- enGB -> enUS
      Loc.Set("enGB")
      H.neq(Loc.Current(), "auto")
      H.eq(L.T_A, "en A")
      H.eq(L.THOUSANDS_SEP, ",")

      -- zurueck: nichts aus deDE/esMX bleibt haengen
      Loc.Set("enUS")
      H.eq(L.T_A, "en A")
      H.eq(L.T_B, "en B")
   end)

   H.test("Locale: Wechsel entfernt Schluessel der vorherigen Sprache", function()
      local T = boot()
      local Loc, L = T.Locale, T.L
      Loc.Add("deDE", { T_ONLY_DE = "nur deutsch" })
      Loc.Set("deDE")
      H.eq(L.T_ONLY_DE, "nur deutsch")
      Loc.Set("enUS")
      H.eq(rawget(L, "T_ONLY_DE"), nil)
      H.eq(L.T_ONLY_DE, "T_ONLY_DE")
      H.eq(L.__missing.T_ONLY_DE, true)
   end)

   H.test("Locale: unbekannte Codes und Sprachen ohne Daten fallen auf Englisch zurueck", function()
      local T = boot()
      local Loc, L = T.Locale, T.L
      Loc.Add("enUS", { T_A = "en A" })
      -- (nur Codes, zu denen es keine Sprachdatei gibt: deDE ... zhTW sind inzwischen echte Sprachen)
      for _, code in ipairs({ "xxXX", "ptBR", "itIT", "enGB", "enCN", "enTW" }) do
         local resolved = Loc.Set(code)
         H.eq(type(resolved), "string")
         H.neq(resolved, "auto", code)
         H.eq(Loc.Current(), resolved, code)
         H.eq(L.T_A, "en A", code)
         H.eq(L.THOUSANDS_SEP, ",", code)
      end
      H.eq(Loc.Set("xxXX"), "enUS", "unbekannt -> enUS")
   end)

   H.test("Locale: auto folgt GetLocale(); Set/Add mit ungueltigen Argumenten werfen nicht", function()
      local T = boot({ world = { locale = "deDE" } })
      local Loc, L = T.Locale, T.L
      Loc.Add("enUS", { T_X = "en" })
      Loc.Add("deDE", { T_X = "de" })
      H.eq(Loc.Set("auto"), "deDE")
      H.eq(Loc.Current(), "deDE")
      H.eq(L.T_X, "de")
      H.eq(Loc.Set("enUS"), "enUS")
      H.eq(L.T_X, "en")
      -- ungueltige Auswahl: kein Fehler, brauchbarer Code (nie "auto")
      for _, bad in ipairs({ 5, true, "" }) do
         local code = Loc.Set(bad)
         H.eq(type(code), "string")
         H.neq(code, "auto")
      end
      H.neq(Loc.Set(nil), "auto")
      Loc.Set("deDE")
      Loc.Add(nil, { A = "x" })
      Loc.Add(5, { A = "x" })
      Loc.Add("deDE", nil)
      Loc.Add("deDE", "text")
      Loc.Add("deDE", { [1] = "x", [true] = "y", T_OK = "ok" })
      Loc.Set("deDE")
      H.eq(L.T_OK, "ok")
      H.eq(rawget(L, 1), nil, "nur String-Schluessel")
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Locale: Add merged mehrfach, Spaeteres ueberschreibt", function()
      local T = boot()
      T.Locale.Add("enUS", { T_ONE = "1", T_TWO = "2" })
      T.Locale.Add("enUS", { T_TWO = "zwei", T_THREE = "3" })
      T.Locale.Set("enUS")
      H.eq(T.L.T_ONE, "1")
      H.eq(T.L.T_TWO, "zwei")
      H.eq(T.L.T_THREE, "3")
      -- die Tabelle des Aufrufers wird nicht festgehalten
      local src = { T_FOUR = "4" }
      T.Locale.Add("enUS", src)
      src.T_FOUR = "geaendert"
      T.Locale.Set("enUS")
      H.eq(T.L.T_FOUR, "4")
   end)

   H.test("Locale: Set feuert LOCALE_CHANGED (Add nicht); Handler sieht die neuen Texte", function()
      local T = boot()
      local seen = {}
      T.Events.On("LOCALE_CHANGED", function() seen[#seen + 1] = T.L.T_WHO end)
      T.Locale.Add("enUS", { T_WHO = "english" })
      T.Locale.Add("deDE", { T_WHO = "deutsch" })
      H.len(seen, 0, "Add feuert nicht")
      T.Locale.Set("deDE")
      H.deepEq(seen, { "deutsch" })
      T.Locale.Set("enUS")
      H.deepEq(seen, { "deutsch", "english" })
   end)

   H.test("Locale.List: acht Sprachen mit nativen Namen, Kopie", function()
      local T = boot()
      local list = T.Locale.List()
      local want = {
         { "enUS", "English" }, { "deDE", "Deutsch" }, { "frFR", "Fran\195\167ais" },
         { "esES", "Espa\195\177ol" }, { "ruRU", "\208\160\209\131\209\129\209\129\208\186\208\184\208\185" },
         { "koKR", "\237\149\156\234\181\173\236\150\180" },
         { "zhCN", "\231\174\128\228\189\147\228\184\173\230\150\135" },
         { "zhTW", "\231\185\129\233\171\148\228\184\173\230\150\135" },
      }
      H.len(list, #want)
      for i, w in ipairs(want) do
         H.eq(list[i] and list[i].code, w[1], "Code " .. i)
         H.eq(list[i] and list[i].name, w[2], "Name " .. w[1])
      end
      -- Aenderungen an der Rueckgabe wirken nicht auf spaetere Aufrufe
      list[1].name = "kaputt"
      table.remove(list, 2)
      local again = T.Locale.List()
      H.len(again, 8)
      H.eq(again[1].name, "English")
      H.eq(again[2].code, "deDE")
   end)

   H.test("enUS_Core: Tausendertrenner und Texte der Basismodule", function()
      local T = boot()
      H.eq(rawget(T.L, "THOUSANDS_SEP"), ",")
      H.eq(type(rawget(T.L, "LOADED")), "string")
      H.eq(type(rawget(T.L, "MIGRATED_OUTFITS")), "string")
      -- Platzhalter: genau die, die der Code fuettert
      H.eq(select(2, T.L.LOADED:gsub("%%s", "")), 2, "LOADED: Name und Version")
      H.eq(select(2, T.L.MIGRATED_OUTFITS:gsub("%%d", "")), 1, "MIGRATED_OUTFITS: Anzahl")
   end)

   -- =======================================================================
   H.section("Init")
   -- =======================================================================

   H.test("Init: Konstanten laut SPEC 5.1", function()
      local T = boot()
      H.eq(T.VERSION, "2.1")
      H.eq(T.ADDON, "Transmog")
      H.eq(T.PREFIX, "transmog")
      H.eq(T.HIDDEN_ID, 999999)
      H.eq(T.debug, false)
      H.eq(type(T.RefreshPlayerInfo), "function")
      H.eq(type(T.IsLoginSweep), "function")
   end)

   H.test("Init: COLORS und HEX vollstaendig, Farben stimmen ueberein", function()
      local T = boot()
      local want = {
         accent = { 0.20, 0.62, 0.92 }, text = { 0.86, 0.88, 0.92 }, dim = { 0.50, 0.54, 0.60 },
         yellow = { 0.91, 0.77, 0.29 }, green = { 0.33, 0.82, 0.48 }, red = { 0.91, 0.40, 0.29 },
         blue = { 0.35, 0.71, 0.91 }, grey = { 0.35, 0.38, 0.44 }, pink = { 0.96, 0.44, 0.96 },
      }
      for name, rgb in pairs(want) do
         local c = T.COLORS[name]
         H.truthy(c, "COLORS." .. name)
         if c then
            for i = 1, 3 do H.near(c[i], rgb[i], 1e-9, name .. "[" .. i .. "]") end
            -- HEX gehoert zur gleichen Farbe (Abweichung hoechstens 1/255). Ausnahme "grey":
            -- die SPEC nennt dort zwei verschiedene Grautoene (Rand 0.35.. / Text |cff9099a8).
            local hex = T.HEX[name]
            H.matches(hex or "", "^|cff%x%x%x%x%x%x$", "HEX." .. name)
            local r, g, b = (hex or ""):match("^|cff(%x%x)(%x%x)(%x%x)$")
            if r and name ~= "grey" then
               H.near(tonumber(r, 16) / 255, c[1], 1.5 / 255, name .. " r")
               H.near(tonumber(g, 16) / 255, c[2], 1.5 / 255, name .. " g")
               H.near(tonumber(b, 16) / 255, c[3], 1.5 / 255, name .. " b")
            end
         end
      end
      H.eq(T.HEX.white, "|cffffffff")
      H.eq(T.HEX.accent, "|cff339eeb")
      H.eq(T.HEX.pink, "|cfff471f5")
      H.eq(T.HEX.grey, "|cff9099a8")
      -- jede Farbe ist ueber Util.Hex in den Farbcode umrechenbar (Rundung: hoechstens eine Stufe daneben)
      for name, c in pairs(T.COLORS) do
         local hex = T.Util.Hex(c[1], c[2], c[3])
         H.matches(hex, "^|cff%x%x%x%x%x%x$", name)
      end
   end)

   H.test("Init: RefreshPlayerInfo fuer alle Rassen (englisches Token, Fraktion)", function()
      local T = boot()
      local cases = {
         { "Human", "human", "A" }, { "Dwarf", "dwarf", "A" }, { "NightElf", "nightelf", "A" },
         { "Gnome", "gnome", "A" }, { "Draenei", "draenei", "A" },
         { "Orc", "orc", "H" }, { "Scourge", "scourge", "H" }, { "Tauren", "tauren", "H" },
         { "Troll", "troll", "H" }, { "BloodElf", "bloodelf", "H" },
      }
      for _, locale in ipairs({ "enUS", "deDE" }) do
         mock.world.locale = locale     -- lokalisierter Name ("Nachtelf") darf nichts aendern
         for _, c in ipairs(cases) do
            mock.world.race = c[1]
            T.RefreshPlayerInfo()
            H.eq(T.race, c[2], locale .. " " .. c[1] .. " race")
            H.eq(T.faction, c[3], locale .. " " .. c[1] .. " faction")
         end
      end
   end)

   H.test("Init: RefreshPlayerInfo Klasse, Fraktion bei unbekannter Rasse, Fehlschlag", function()
      local T = boot()
      mock.world.class = "DEATHKNIGHT"
      T.RefreshPlayerInfo()
      H.eq(T.class, "deathknight")
      mock.world.class = "DRUID"
      T.RefreshPlayerInfo()
      H.eq(T.class, "druid")

      -- unbekanntes Token: UnitFactionGroup entscheidet
      mock.world.race = { "Fremd", "Alien" }
      mock.world.faction = "Horde"
      T.RefreshPlayerInfo()
      H.eq(T.race, "alien")
      H.eq(T.faction, "H")
      mock.world.faction = "Alliance"
      T.RefreshPlayerInfo()
      H.eq(T.faction, "A")
      -- Worgen/Goblin sind in der Tabelle (auch wenn 3.3.5a sie nicht kennt)
      mock.world.race = { "Worgen", "Worgen" }
      mock.world.faction = "Horde"
      T.RefreshPlayerInfo()
      H.eq(T.faction, "A", "worgen zaehlt Allianz")
      mock.world.race = { "Goblin", "Goblin" }
      mock.world.faction = "Alliance"
      T.RefreshPlayerInfo()
      H.eq(T.faction, "H", "goblin zaehlt Horde")

      -- Abfrage liefert nichts / wirft: Rueckfall "human", kein Fehler
      mock.world.race = { nil, nil }
      T.RefreshPlayerInfo()
      H.eq(T.race, "human")
      H.eq(T.faction, "A")
      local real = UnitRace
      UnitRace = function() error("boom") end
      mock.world.race = "Orc"
      T.RefreshPlayerInfo()
      H.eq(T.race, "human")
      H.eq(T.faction, "A")
      UnitRace = real
      T.RefreshPlayerInfo()
      H.eq(T.race, "orc")
      H.eq(T.faction, "H")
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Init: schon beim Laden sind race/class/faction gesetzt", function()
      local T = boot({ world = { race = "BloodElf", class = "PALADIN" } })
      H.eq(T.race, "bloodelf")
      H.eq(T.class, "paladin")
      H.eq(T.faction, "H")
   end)

   H.test("Init: IsLoginSweep (bis 10 s nach PLAYER_ENTERING_WORLD)", function()
      local T = boot()
      H.eq(T.enteredWorldAt, nil)
      H.eq(T.IsLoginSweep(), true, "noch nicht in der Welt")
      T.enteredWorldAt = GetTime()
      H.eq(T.IsLoginSweep(), true, "gerade eingetreten")
      mock.Advance(9.5)
      H.eq(T.IsLoginSweep(), true, "9,5 s")
      mock.Advance(0.6)
      H.eq(T.IsLoginSweep(), false, "10,1 s")
      mock.Advance(100)
      H.eq(T.IsLoginSweep(), false)
      T.enteredWorldAt = GetTime()
      H.eq(T.IsLoginSweep(), true, "neuer Welteintritt")
   end)

   -- =======================================================================
   H.section("Util: Text und Zahlen")
   -- =======================================================================

   H.test("Util.Print/Error/Debug: Praefix, Farben, Formatierung, nie ein Fehler", function()
      local T = boot()
      local U = T.Util
      local prefix = "|cff33a0ea[Transmog]|r "
      U.Print("hallo")
      H.eq(lastMessage(), prefix .. "hallo")
      U.Print("%s hat %d Teile", "Outfit", 7)
      H.eq(lastMessage(), prefix .. "Outfit hat 7 Teile")
      U.Print("100% sicher")
      H.eq(lastMessage(), prefix .. "100% sicher", "ohne Argumente bleibt der Text unveraendert")
      U.Print("%d Teile", "x")
      H.matches(lastMessage(), "^|cff33a0ea%[Transmog%]|r ", "falsches Argument wirft nicht")
      U.Print("%d %s", nil, nil)
      H.matches(lastMessage(), "^|cff33a0ea%[Transmog%]|r ", "nil-Argumente werfen nicht")
      U.Print(nil)
      H.eq(lastMessage(), prefix, "nil als Text")
      U.Print("%s", { })
      H.matches(lastMessage(), "table:", "Tabellenargument als Text")

      U.Error("kaputt %d", 3)
      H.eq(lastMessage(), prefix .. T.HEX.red .. "kaputt 3|r")

      local n = #mock.messages
      U.Debug("still")
      H.eq(#mock.messages, n, "Debug ist aus")
      T.debug = true
      U.Debug("laut %s", "ja")
      H.eq(#mock.messages, n + 1)
      H.contains(lastMessage(), "laut ja")
      H.contains(lastMessage(), "[Transmog]")
      T.debug = false
      U.Debug("wieder still")
      H.eq(#mock.messages, n + 1)
   end)

   H.test("Util.G: Blizzard-Globalstring oder Ersatz, nie nil", function()
      local T = boot()
      local U = T.Util
      H.eq(U.G("HEADSLOT", "Head!"), HEADSLOT)
      H.eq(U.G("TRANSMOG_NO_SUCH_GLOBAL", "Fallback"), "Fallback")
      H.eq(U.G("TRANSMOG_NO_SUCH_GLOBAL"), "TRANSMOG_NO_SUCH_GLOBAL", "ohne Ersatz der Name")
      H.eq(U.G("TRANSMOG_NO_SUCH_GLOBAL", 5), "5", "Ersatz als Text")
      -- vorhanden, aber kein String / leer -> Ersatz
      rawset(_G, "TRANSMOG_TEST_TABLE", {})
      rawset(_G, "TRANSMOG_TEST_EMPTY", "")
      H.eq(U.G("TRANSMOG_TEST_TABLE", "Ersatz"), "Ersatz")
      H.eq(U.G("TRANSMOG_TEST_EMPTY", "Ersatz"), "Ersatz")
      rawset(_G, "TRANSMOG_TEST_TABLE", nil)
      rawset(_G, "TRANSMOG_TEST_EMPTY", nil)
      H.eq(U.G(nil, "x"), "x")
   end)

   H.test("Util.Split: leere Felder, Trennzeichen am Ende, mehrere Zeichen, Klartext", function()
      local T = boot()
      local S = T.Util.Split
      H.deepEq(S("a:b:c", ":"), { "a", "b", "c" })
      H.deepEq(S("a::b", ":"), { "a", "", "b" })
      H.deepEq(S(":a", ":"), { "", "a" })
      H.deepEq(S("a:", ":"), { "a", "" })
      H.deepEq(S(":", ":"), { "", "" })
      H.deepEq(S("::", ":"), { "", "", "" })
      H.deepEq(S("", ":"), { "" })
      H.deepEq(S("abc", ":"), { "abc" })
      H.deepEq(S("a, b,c", ", "), { "a", "b,c" })
      H.deepEq(S("a::b:::c", "::"), { "a", "b", ":c" }, "nicht ueberlappend von links")
      H.deepEq(S("1.2.3", "."), { "1", "2", "3" }, "Punkt ist kein Muster")
      H.deepEq(S("a%b%c", "%"), { "a", "b", "c" })
      H.deepEq(S("a|b", "|"), { "a", "b" })
      H.deepEq(S("[a][b]", "]["), { "[a", "b]" })
      H.deepEq(S("abc", ""), { "abc" }, "leerer Trenner: unverzerrt")
      H.deepEq(S("abc", nil), { "abc" })
      H.deepEq(S(nil, ":"), {})
      H.deepEq(S(12.5, "."), { "12", "5" }, "Zahl als Text")
      -- reale Servernachricht
      H.deepEq(S("AvailableTransmogs:0:105:3:start", ":"), { "AvailableTransmogs", "0", "105", "3", "start" })
      H.deepEq(S("TransmogStatus:2:0,12345,3,999999", ":"), { "TransmogStatus", "2", "0,12345,3,999999" })
   end)

   H.test("Util.Split: Zufallstest gegen unabhaengige Referenz", function()
      local T = boot()
      local rng = newRng(4711)
      local alphabet = { "a", "b", ":", ",", "|", "." }
      local seps = { ":", ",", "::", ",:", "ab", "|", ".", "a" }
      for _ = 1, 600 do
         local len = rng(12) - 1
         local parts = {}
         for i = 1, len do parts[i] = alphabet[rng(#alphabet)] end
         local s = table.concat(parts)
         local sep = seps[rng(#seps)]
         local got = T.Util.Split(s, sep)
         local want = refSplit(s, sep)
         if #got ~= #want then
            H.fail(string.format("Split(%q, %q): %d Felder statt %d", s, sep, #got, #want))
         else
            for i = 1, #want do
               if got[i] ~= want[i] then
                  H.fail(string.format("Split(%q, %q): Feld %d ist %q statt %q", s, sep, i, got[i], want[i]))
                  break
               end
            end
         end
      end
      H.ok(true, "durchgelaufen")
   end)

   H.test("Util.Trim: Leerraum, nil, Zahlen, nur Leerraum", function()
      local T = boot()
      local Trim = T.Util.Trim
      H.eq(Trim("  a b  "), "a b")
      H.eq(Trim("\t\n x \r\n"), "x")
      H.eq(Trim("   "), "")
      H.eq(Trim(""), "")
      H.eq(Trim(nil), "")
      H.eq(Trim(42), "42")
      H.eq(Trim("a  b"), "a  b", "innen unveraendert")
      H.eq(Trim("\195\164 "), "\195\164", "UTF-8 bleibt")
   end)

   H.test("Util.Lower: ASCII, Umlaute, Latin-1, Kyrillisch, alles andere unveraendert", function()
      local T = boot()
      local Lower = T.Util.Lower
      H.eq(Lower("Hello WORLD 123"), "hello world 123")
      H.eq(Lower("\195\132\195\150\195\156"), "\195\164\195\182\195\188", "AE OE UE -> ae oe ue")
      H.eq(Lower("Gro\195\159"), "gro\195\159", "scharfes s bleibt")
      H.eq(Lower("\195\151"), "\195\151", "Malzeichen U+00D7 bleibt")
      H.eq(Lower("\195\150L"), "\195\182l")
      H.eq(Lower("\208\159\208\160\208\152\208\146\208\149\208\162"), "\208\191\209\128\208\184\208\178\208\181\209\130", "ПРИВЕТ")
      H.eq(Lower("\208\129"), "\209\145", "Ё -> ё (U+0401 -> U+0451)")
      H.eq(Lower("\208\175"), "\209\143", "Я -> я")
      H.eq(Lower("\208\144"), "\208\176", "А -> а")
      H.eq(Lower("\208\172\208\171\208\170"), "\209\140\209\139\209\138")
      -- CJK, Hangul, Emoji, Zahlen, Satzzeichen bleiben
      local keep = "\228\184\173\230\150\135 \237\149\156\234\181\173\236\150\180 \240\159\152\128 !?%[]|"
      H.eq(Lower(keep), keep)
      H.eq(Lower("ABC \228\184\173 \195\132 \208\159"), "abc \228\184\173 \195\164 \208\191")
      H.eq(Lower(""), "")
      H.eq(Lower(nil), "")
      H.eq(Lower(12), "12")
      -- abgeschnittene/ungueltige Folgen werden nicht veraendert und werfen nicht
      H.eq(Lower("A\195"), "a\195")
      H.eq(Lower("\208"), "\208")
      H.eq(Lower("\195A"), "\195a")
      H.eq(Lower("\195\195\132"), "\195\195\164")
      -- idempotent
      local once = Lower("\195\132\208\159Z")
      H.eq(Lower(once), once)
   end)

   H.test("Util.Lower: alle Codepoints U+0000..U+04FF gegen die Abbildungsregel", function()
      local T = boot()
      local bad = 0
      for cp = 0, 0x4FF do
         if not (cp >= 0xD800 and cp <= 0xDFFF) then
            local want = cp
            if cp >= 65 and cp <= 90 then
               want = cp + 32
            elseif cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then
               want = cp + 0x20
            elseif cp >= 0x410 and cp <= 0x42F then
               want = cp + 0x20
            elseif cp >= 0x400 and cp <= 0x40F then
               want = cp + 0x50
            end
            local got = T.Util.Lower(utf8char(cp))
            if got ~= utf8char(want) then
               bad = bad + 1
               if bad <= 5 then H.fail(string.format("U+%04X -> erwartet U+%04X", cp, want)) end
            end
         end
      end
      H.eq(bad, 0)
      -- eine lange gemischte Zeichenkette (jedes Zeichen mit Nachbarn) bleibt konsistent
      local parts, wants = {}, {}
      for cp = 0x20, 0x4FF, 7 do
         parts[#parts + 1] = utf8char(cp)
         wants[#wants + 1] = T.Util.Lower(utf8char(cp))
      end
      H.eq(T.Util.Lower(table.concat(parts)), table.concat(wants))
   end)

   H.test("Util.Clamp / Util.Round", function()
      local T = boot()
      local U = T.Util
      H.eq(U.Clamp(5, 1, 10), 5)
      H.eq(U.Clamp(-1, 1, 10), 1)
      H.eq(U.Clamp(11, 1, 10), 10)
      H.eq(U.Clamp(1, 1, 10), 1)
      H.eq(U.Clamp(10, 1, 10), 10)
      H.eq(U.Clamp("7", 1, 10), 7, "Zahlentext")
      H.eq(U.Clamp("x", 1, 10), 1, "kein Zahlenwert -> Untergrenze")
      H.eq(U.Clamp(nil, 2, 10), 2)
      H.eq(U.Clamp(0 / 0, 2, 10), 2, "NaN")
      H.eq(U.Clamp(math.huge, 1, 10), 10)
      H.eq(U.Clamp(-math.huge, 1, 10), 1)
      H.eq(U.Clamp(0.5, 0, 1), 0.5)

      H.eq(U.Round(0.5), 1)
      H.eq(U.Round(1.5), 2)
      H.eq(U.Round(2.5), 3, "kaufmaennisch, nicht Banker")
      H.eq(U.Round(2.4999), 2)
      H.eq(U.Round(-0.5), -1)
      H.eq(U.Round(-1.5), -2)
      H.eq(U.Round(-2.4), -2)
      H.eq(U.Round(0), 0)
      H.eq(U.Round("3.6"), 4)
      H.eq(U.Round(nil), 0)
      H.eq(U.Round(0 / 0), 0)
   end)

   H.test("Util.ItemIdFromLink: Links, Kurzformen, Zahlen, Muell", function()
      local T = boot()
      local Id = T.Util.ItemIdFromLink
      H.eq(Id("item:19019"), 19019)
      H.eq(Id("item:19019:0:0:0:0:0:0:0:80"), 19019)
      H.eq(Id("|cffa335ee|Hitem:19019:0:0:0:0:0:0:0:80|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"), 19019)
      H.eq(Id("|Hitem:41234:3827:3622:0:0:0:0:0:80|h[Name]|h"), 41234, "mit Verzauberung/Edelsteinen")
      H.eq(Id("|cff0070dd|Hitem:1:0:0:0|h[Wuerfel: 12:30]|h|r"), 1)
      H.eq(Id(19019), 19019, "Zahl")
      H.eq(Id("19019"), 19019, "Zahlentext")
      H.eq(Id("  19019 "), 19019, "Zahlentext mit Leerraum")
      H.eq(Id("item:999999"), 999999)
      -- ungueltig
      H.eq(Id(nil), nil)
      H.eq(Id(""), nil)
      H.eq(Id("item:"), nil)
      H.eq(Id("item:abc"), nil)
      H.eq(Id("item:-5"), nil)
      H.eq(Id("quest:123"), nil)
      H.eq(Id("enchant:2564"), nil)
      H.eq(Id(0), nil)
      H.eq(Id(-5), nil)
      H.eq(Id(12.5), nil)
      H.eq(Id("12.5"), nil)
      H.eq(Id("item:0"), nil)
      H.eq(Id({}), nil)
      H.eq(Id(true), nil)
      H.eq(Id(0 / 0), nil)
      H.eq(Id("abc 19019"), nil, "Zahl nur als ganzer Text")
   end)

   H.test("Util.FormatNumber: Tausendertrenner je Sprache, Rundung, Randfaelle", function()
      local T = boot()
      local U = T.Util
      T.Locale.Add("enUS", { THOUSANDS_SEP = "," })
      T.Locale.Add("deDE", { THOUSANDS_SEP = "." })
      T.Locale.Add("frFR", { THOUSANDS_SEP = " " })
      T.Locale.Add("ruRU", { THOUSANDS_SEP = "\194\160" })
      T.Locale.Add("koKR", { THOUSANDS_SEP = "'" })
      local cases = {
         { 0, "0" }, { 7, "7" }, { 12, "12" }, { 999, "999" }, { 1000, "1{s}000" },
         { 12345, "12{s}345" }, { 123456, "123{s}456" }, { 1234567, "1{s}234{s}567" },
         { 1000000000, "1{s}000{s}000{s}000" }, { 100, "100" }, { 10000, "10{s}000" },
      }
      for _, code in ipairs({ "enUS", "deDE", "frFR", "ruRU", "koKR" }) do
         T.Locale.Set(code)
         local sep = rawget(T.L, "THOUSANDS_SEP")
         for _, c in ipairs(cases) do
            local want = c[2]:gsub("{s}", function() return sep end)
            H.eq(U.FormatNumber(c[1]), want, code .. " " .. c[1])
         end
      end
      T.Locale.Set("enUS")
      H.eq(U.FormatNumber(-1234567), "-1,234,567")
      H.eq(U.FormatNumber(-5), "-5")
      H.eq(U.FormatNumber(1234.4), "1,234")
      H.eq(U.FormatNumber(1234.5), "1,235", "gerundet")
      H.eq(U.FormatNumber(999.5), "1,000")
      H.eq(U.FormatNumber(-0.4), "0", "kein Minus vor 0")
      H.eq(U.FormatNumber("1234567"), "1,234,567", "Zahlentext")
      H.eq(U.FormatNumber(nil), "0")
      H.eq(U.FormatNumber("x"), "0")
      H.eq(U.FormatNumber(0 / 0), "0")
      H.eq(U.FormatNumber(math.huge), "0")
      -- Ohne THOUSANDS_SEP in der Sprache gilt der englische Trenner
      T.Locale.Set("deDE")
      T.Locale.Add("deDE", { THOUSANDS_SEP = nil })
      -- Schluessel bleibt (Add loescht nichts); ohne Schluessel waere "," der Rueckfall:
      H.eq(U.FormatNumber(1234), "1.234")
   end)

   H.test("Util.FormatNumber: Zufallstest gegen Referenz", function()
      local T = boot()
      local rng = newRng(99)
      for _, sep in ipairs({ ",", ".", " " }) do
         T.Locale.Add("deDE", { THOUSANDS_SEP = sep })
         T.Locale.Set("deDE")
         for _ = 1, 150 do
            local n = (rng(100000) - 1) * rng(100000) % 4000000000
            H.eq(T.Util.FormatNumber(n), refFormat(n, sep), "n=" .. n)
         end
      end
      T.Locale.Set("enUS")
   end)

   H.test("Util.FormatMoney: Gold/Silber/Kupfer, Nullwerte, Randfaelle", function()
      local T = boot()
      local U = T.Util
      local G = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t"
      local S = "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:2:0|t"
      local C = "|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:2:0|t"
      H.eq(U.FormatMoney(0), "0" .. C)
      H.eq(U.FormatMoney(1), "1" .. C)
      H.eq(U.FormatMoney(99), "99" .. C)
      H.eq(U.FormatMoney(100), "1" .. S, "Kupfer nur wenn > 0")
      H.eq(U.FormatMoney(101), "1" .. S .. " 1" .. C)
      H.eq(U.FormatMoney(9999), "99" .. S .. " 99" .. C)
      H.eq(U.FormatMoney(10000), "1" .. G, "Silber/Kupfer nur wenn > 0")
      H.eq(U.FormatMoney(10001), "1" .. G .. " 1" .. C)
      H.eq(U.FormatMoney(10100), "1" .. G .. " 1" .. S)
      H.eq(U.FormatMoney(120340), "12" .. G .. " 3" .. S .. " 40" .. C, "Beispiel aus der SPEC")
      H.eq(U.FormatMoney(123456), "12" .. G .. " 34" .. S .. " 56" .. C)
      -- Gold ohne Obergrenze, mit Tausendertrenner der Sprache
      H.eq(U.FormatMoney(1000000 * 10000), "1,000,000" .. G)
      H.eq(U.FormatMoney(214748 * 10000 + 3647), "214,748" .. G .. " 36" .. S .. " 47" .. C)
      for _, sep in ipairs({ ".", " ", "'", "\194\160" }) do
         T.Locale.Add("deDE", { THOUSANDS_SEP = sep })
         T.Locale.Set("deDE")
         H.eq(U.FormatMoney(1234 * 10000 + 5), "1" .. sep .. "234" .. G .. " 5" .. C, "Trenner '" .. sep .. "'")
         H.eq(U.FormatMoney(999 * 10000), "999" .. G, "unter 1000 Gold ohne Trenner")
      end
      T.Locale.Set("enUS")
      -- ungueltig -> 0
      H.eq(U.FormatMoney(nil), "0" .. C)
      H.eq(U.FormatMoney(-500), "0" .. C)
      H.eq(U.FormatMoney("x"), "0" .. C)
      H.eq(U.FormatMoney(0 / 0), "0" .. C)
      H.eq(U.FormatMoney("12345"), "1" .. G .. " 23" .. S .. " 45" .. C, "Zahlentext")
      H.eq(U.FormatMoney(100.4), "1" .. S, "gerundet")
   end)

   H.test("Util.CopyTable / Count", function()
      local T = boot()
      local U = T.Util
      local src = { a = 1, b = { c = { d = 2 }, list = { 1, 2, 3 } }, [5] = "x", flag = false }
      local dst = U.CopyTable(src)
      H.deepEq(dst, src)
      H.neq(dst, src)
      H.neq(dst.b, src.b)
      H.neq(dst.b.c, src.b.c)
      dst.b.c.d = 99
      dst.b.list[1] = "neu"
      H.eq(src.b.c.d, 2)
      H.eq(src.b.list[1], 1)
      H.eq(dst.flag, false)
      -- Nicht-Tabellen und Zyklen
      H.eq(U.CopyTable(5), 5)
      H.eq(U.CopyTable("s"), "s")
      H.eq(U.CopyTable(nil), nil)
      local cyc = { name = "z" }
      cyc.self = cyc
      local cp = U.CopyTable(cyc)
      H.eq(cp.name, "z")
      H.eq(cp.self, cp, "Zyklus bleibt ein Zyklus")
      H.neq(cp, cyc)

      H.eq(U.Count({}), 0)
      H.eq(U.Count({ 1, 2, 3 }), 3)
      H.eq(U.Count({ a = 1, b = 2, [10] = 3 }), 3)
      H.eq(U.Count({ [0] = true, [2] = true }), 2, "auch Luecken")
      H.eq(U.Count(nil), 0)
      H.eq(U.Count("abc"), 0)
   end)

   H.test("Util.Hex / Util.QualityColor", function()
      local T = boot()
      local U = T.Util
      H.eq(U.Hex(0, 0, 0), "|cff000000")
      H.eq(U.Hex(1, 1, 1), "|cffffffff")
      H.eq(U.Hex(1, 0.5, 0), "|cffff8000")
      H.eq(U.Hex(0.2, 0.62, 0.92), "|cff339eeb")
      H.eq(U.Hex(-1, 2, 0.5), "|cff00ff80", "ausserhalb 0..1 wird begrenzt")
      H.eq(U.Hex(nil, nil, nil), "|cff000000")

      -- aus dem Spiel (ITEM_QUALITY_COLORS)
      for q = 0, 7 do
         local r, g, b, hex = U.QualityColor(q)
         local c = ITEM_QUALITY_COLORS[q]
         H.eq(r, c.r, "r " .. q)
         H.eq(g, c.g, "g " .. q)
         H.eq(b, c.b, "b " .. q)
         H.matches(hex, "^|cff%x%x%x%x%x%x$", "hex " .. q)
      end
      H.eq(select(4, U.QualityColor(4)), "|cffa335ee")
      H.eq(select(4, U.QualityColor(1)), "|cffffffff")
      -- ausserhalb 0..7 und Muell: begrenzt, nie ein Fehler
      H.eq(select(4, U.QualityColor(99)), select(4, U.QualityColor(7)))
      H.eq(select(4, U.QualityColor(-3)), select(4, U.QualityColor(0)))
      H.eq(select(4, U.QualityColor(nil)), select(4, U.QualityColor(1)))
      H.eq(select(4, U.QualityColor("3")), select(4, U.QualityColor(3)))
      H.eq(select(4, U.QualityColor(2.9)), select(4, U.QualityColor(2)))

      -- ohne ITEM_QUALITY_COLORS: eingebaute Ersatzfarben
      local saved = ITEM_QUALITY_COLORS
      ITEM_QUALITY_COLORS = nil
      local r, g, b, hex = U.QualityColor(4)
      H.eq(hex, "|cffa335ee")
      H.near(r, 0.64, 0.01)
      H.near(g, 0.21, 0.01)
      H.near(b, 0.93, 0.01)
      H.eq(select(4, U.QualityColor(2)), "|cff1eff00")
      H.eq(select(4, U.QualityColor(0)), "|cff9d9d9d")
      -- Eintrag ohne hex: aus r,g,b
      ITEM_QUALITY_COLORS = { [3] = { r = 0, g = 0.5, b = 1 } }
      H.eq(select(4, U.QualityColor(3)), "|cff0080ff")
      -- hex des Spiels in anderer Schreibweise: immer als "|cAARRGGBB" geliefert
      ITEM_QUALITY_COLORS = {
         [0] = { r = 1, g = 1, b = 1, hex = "ff9d9d9d" },
         [1] = { r = 1, g = 1, b = 1, hex = "1eff00" },
         [2] = { r = 0, g = 0, b = 0, hex = "|cff1eff00" },
         [3] = { r = 0, g = 0.5, b = 1, hex = "kein hex" },
         [4] = { r = 0, g = 0.5, b = 1, hex = "" },
      }
      H.eq(select(4, U.QualityColor(0)), "|cff9d9d9d")
      H.eq(select(4, U.QualityColor(1)), "|cff1eff00")
      H.eq(select(4, U.QualityColor(2)), "|cff1eff00")
      H.eq(select(4, U.QualityColor(3)), "|cff0080ff")
      H.eq(select(4, U.QualityColor(4)), "|cff0080ff")
      -- kaputte Eintraege -> Ersatz
      ITEM_QUALITY_COLORS = { [3] = "kaputt" }
      H.eq(select(4, U.QualityColor(3)), "|cff0070dd")
      ITEM_QUALITY_COLORS = saved
   end)

   -- =======================================================================
   H.section("Util: Timer")
   -- =======================================================================

   H.test("Util.After: feuert nach der Verzoegerung, genau einmal, mit Argumenten", function()
      local T = boot()
      local got, calls = nil, 0
      local handle = T.Util.After(0.25, function(...)
         calls = calls + 1
         got = { n = select("#", ...), ... }
      end, "x", nil, 3)
      H.eq(type(handle), "number")
      H.eq(calls, 0, "nicht sofort")
      mock.Advance(0.2)
      H.eq(calls, 0, "nicht zu frueh")
      mock.Advance(0.1)
      H.eq(calls, 1)
      H.eq(got.n, 3)
      H.eq(got[1], "x")
      H.eq(got[2], nil)
      H.eq(got[3], 3)
      mock.Advance(5)
      H.eq(calls, 1, "nur einmal")
      H.eq(T.Util.TimerCount(), 0)
   end)

   H.test("Util.After: Verzoegerung 0/negativ/nil feuert im naechsten Frame, nie synchron", function()
      local T = boot()
      local fired = {}
      T.Util.After(0, function() fired[#fired + 1] = "zero" end)
      T.Util.After(-5, function() fired[#fired + 1] = "neg" end)
      T.Util.After(nil, function() fired[#fired + 1] = "nil" end)
      T.Util.After("abc", function() fired[#fired + 1] = "text" end)
      H.len(fired, 0)
      mock.Advance(0.05, 0.05)
      H.len(fired, 4)
      -- Reihenfolge: gleiche Faelligkeit -> Reihenfolge des Anlegens
      H.deepEq(fired, { "zero", "neg", "nil", "text" })
   end)

   H.test("Util.After: ungueltige Argumente, NaN und unendliche Verzoegerung", function()
      local T = boot()
      H.eq(T.Util.After(1, nil), nil)
      H.eq(T.Util.After(1, "nofunction"), nil)
      H.eq(T.Util.TimerCount(), 0)
      -- NaN darf den Treiber nicht fuer immer wach halten und gilt als sofort
      local ran = 0
      T.Util.After(0 / 0, function() ran = ran + 1 end)
      mock.Advance(0.2)
      H.eq(ran, 1, "NaN wie 0")
      H.eq(T.Util.TimerCount(), 0)
      H.len(mock.UpdateFrames(), 0, "kein OnUpdate im Leerlauf")
   end)

   H.test("Util: Faelligkeit nach Zeit, bei gleicher Zeit nach Anlegereihenfolge", function()
      local T = boot()
      local order = {}
      local function mk(name) return function() order[#order + 1] = name end end
      T.Util.After(1, mk("c"))
      T.Util.After(0.5, mk("b1"))
      T.Util.After(0.25, mk("a"))
      T.Util.After(0.5, mk("b2"))
      T.Util.After(2, mk("d"))
      mock.Advance(3, 0.05)
      H.deepEq(order, { "a", "b1", "b2", "c", "d" })
   end)

   H.test("Util: grosse Frame-Zeit (Ladebildschirm) laesst alle faelligen Timer in Reihenfolge laufen", function()
      local T = boot()
      local order = {}
      T.Util.After(5, function() order[#order + 1] = 5 end)
      T.Util.After(1, function() order[#order + 1] = 1 end)
      T.Util.After(50, function() order[#order + 1] = 50 end)
      T.Util.After(20, function() order[#order + 1] = 20 end)
      local frames = mock.UpdateFrames()
      H.len(frames, 1, "ein Treiber-Frame")
      local fn = frames[1]:GetScript("OnUpdate")
      fn(frames[1], 30)
      H.deepEq(order, { 1, 5, 20 })
      H.eq(T.Util.TimerCount(), 1)
      fn(frames[1], 25)
      H.deepEq(order, { 1, 5, 20, 50 })
      H.eq(T.Util.TimerCount(), 0)
   end)

   H.test("Util.Cancel: verhindert den Lauf; idempotent; Rueckgabewerte", function()
      local T = boot()
      local ran = {}
      local h1 = T.Util.After(0.5, function() ran[#ran + 1] = 1 end)
      local h2 = T.Util.After(0.5, function() ran[#ran + 1] = 2 end)
      H.eq(T.Util.Cancel(h1), true)
      H.eq(T.Util.Cancel(h1), false, "zweites Mal")
      H.eq(T.Util.Cancel(99999), false, "unbekannter Handle")
      H.eq(T.Util.Cancel(nil), false)
      H.eq(T.Util.Cancel({}), false)
      H.eq(T.Util.TimerCount(), 1)
      mock.Advance(1)
      H.deepEq(ran, { 2 })
      H.eq(T.Util.Cancel(h2), false, "schon gelaufen")
   end)

   H.test("Util: Treiber-Frame ist nur sichtbar, solange Timer anstehen", function()
      local T = boot()
      H.len(mock.UpdateFrames(), 0, "vorher nichts")
      local h = T.Util.After(10, function() end)
      H.len(mock.UpdateFrames(), 1, "Timer ansteht")
      T.Util.Cancel(h)
      H.len(mock.UpdateFrames(), 0, "nach Cancel des letzten Timers")
      T.Util.After(0.1, function() end)
      H.len(mock.UpdateFrames(), 1)
      mock.Advance(0.2)
      H.len(mock.UpdateFrames(), 0, "nach dem Lauf")
      T.Util.Debounce("k", 0.5, function() end)
      H.len(mock.UpdateFrames(), 1)
      mock.Advance(0.6)
      H.len(mock.UpdateFrames(), 0)
      -- nach langer Ruhe laeuft ein neuer Timer weiterhin nach seiner eigenen Frist
      mock.Advance(100)
      local ran = 0
      T.Util.After(0.5, function() ran = ran + 1 end)
      mock.Advance(0.4)
      H.eq(ran, 0)
      mock.Advance(0.2)
      H.eq(ran, 1)
   end)

   H.test("Util: Handler duerfen Timer anlegen und abbrechen (Wiedereintritt)", function()
      local T = boot()
      local U = T.Util
      local log = {}

      -- A legt B mit Verzoegerung 0 an: B laeuft erst im NAECHSTEN Frame
      U.After(0.05, function()
         log[#log + 1] = "A"
         U.After(0, function() log[#log + 1] = "B" end)
      end)
      mock.Advance(0.05, 0.05)
      H.deepEq(log, { "A" })
      mock.Advance(0.05, 0.05)
      H.deepEq(log, { "A", "B" })

      -- Folgetimer zaehlt ab dem Aufruf (nicht ab dem Start)
      log = {}
      U.After(0.5, function()
         log[#log + 1] = "first"
         U.After(0.3, function() log[#log + 1] = "second" end)
      end)
      mock.Advance(0.5, 0.05)
      H.deepEq(log, { "first" })
      mock.Advance(0.25, 0.05)
      H.deepEq(log, { "first" }, "zu frueh")
      mock.Advance(0.1, 0.05)
      H.deepEq(log, { "first", "second" })

      -- ein Handler bricht einen anderen faelligen Timer ab
      log = {}
      local h2
      U.After(0.1, function()
         log[#log + 1] = "killer"
         U.Cancel(h2)
      end)
      h2 = U.After(0.1, function() log[#log + 1] = "victim" end)
      mock.Advance(0.5)
      H.deepEq(log, { "killer" })

      -- ein Handler bricht sich selbst ab (schon entfernt): kein Fehler, false
      log = {}
      local self
      self = U.After(0.1, function() log[#log + 1] = tostring(U.Cancel(self)) end)
      mock.Advance(0.5)
      H.deepEq(log, { "false" })

      -- Kette: jeder Handler legt den naechsten an; endlich viele Durchlaeufe
      local count = 0
      local function chain()
         count = count + 1
         if count < 5 then U.After(0.05, chain) end
      end
      U.After(0.05, chain)
      mock.Advance(1)
      H.eq(count, 5)
      H.eq(U.TimerCount(), 0)
      H.len(mock.UpdateFrames(), 0)
   end)

   H.test("Util: Fehler in einem Timer gehen an den Fehlerbehandler, andere Timer laufen weiter", function()
      local T = boot()
      local ran = {}
      T.Util.After(0.1, function() error("timer-boom") end)
      T.Util.After(0.1, function() ran[#ran + 1] = "after" end)
      T.Util.After(0.2, function() ran[#ran + 1] = "later" end)
      mock.Advance(0.5)
      H.deepEq(ran, { "after", "later" })
      local errors = H.takeErrors()
      H.len(errors, 1)
      H.contains(errors[1] or "", "timer-boom")
      H.eq(T.Util.TimerCount(), 0)
      H.len(mock.UpdateFrames(), 0)
   end)

   H.test("Util.Debounce: re-armt, ruft nach Ruhe genau einmal, Schluessel getrennt", function()
      local T = boot()
      local U = T.Util
      local calls = { a = 0, b = 0 }
      local function fa() calls.a = calls.a + 1 end
      local function fb() calls.b = calls.b + 1 end
      local h1 = U.Debounce("a", 1, fa)
      H.eq(type(h1), "number")
      mock.Advance(0.5)
      local h2 = U.Debounce("a", 1, fa)
      H.neq(h2, h1, "neuer Timer")
      U.Debounce("b", 0.25, fb)
      mock.Advance(0.5)
      H.eq(calls.b, 1, "b nach 0,25 s Ruhe")
      H.eq(calls.a, 0, "a zurueckgesetzt (0,5 s seit Neustart)")
      mock.Advance(0.4)
      H.eq(calls.a, 0, "0,9 s Ruhe")
      mock.Advance(0.2)
      H.eq(calls.a, 1, "1,1 s Ruhe")
      mock.Advance(5)
      H.eq(calls.a, 1)
      H.eq(calls.b, 1)
      H.eq(U.TimerCount(), 0)
   end)

   H.test("Util.Debounce: Dauerfeuer feuert erst nach der Ruhe; letzte Funktion gewinnt", function()
      local T = boot()
      local U = T.Util
      local who = {}
      for i = 1, 20 do
         U.Debounce("burst", 1, function() who[#who + 1] = i end)
         mock.Advance(0.3)
      end
      H.len(who, 0, "waehrend des Feuers nichts")
      mock.Advance(0.8)
      H.deepEq(who, { 20 })
      H.eq(U.TimerCount(), 0)
   end)

   H.test("Util.Debounce: Cancel ueber Schluessel und Handle, Neuanlage im eigenen Handler", function()
      local T = boot()
      local U = T.Util
      local ran = 0
      U.Debounce("k", 0.5, function() ran = ran + 1 end)
      H.eq(U.Cancel("k"), true)
      H.eq(U.Cancel("k"), false)
      mock.Advance(1)
      H.eq(ran, 0)
      local h = U.Debounce("k", 0.5, function() ran = ran + 1 end)
      H.eq(U.Cancel(h), true)
      mock.Advance(1)
      H.eq(ran, 0)

      -- im eigenen Handler wieder anmelden: laeuft erneut nach der Frist
      local n = 0
      local function again()
         n = n + 1
         if n < 3 then U.Debounce("self", 0.25, again) end
      end
      U.Debounce("self", 0.25, again)
      mock.Advance(2)
      H.eq(n, 3)
      H.eq(U.TimerCount(), 0)

      -- ein anderer Timer (frueher angelegt, gleiche Faelligkeit) meldet den Schluessel im selben
      -- Durchlauf neu an: die alte, schon "faellige" Funktion darf nicht mehr laufen
      local ranA = 0
      U.After(0.1, function() U.Debounce("x", 0.3, function() ranA = ranA + 10 end) end)
      U.Debounce("x", 0.1, function() ranA = ranA + 1 end)
      mock.Advance(0.2, 0.05)
      H.eq(ranA, 0, "ersetzte Debounce-Funktion laeuft nicht")
      mock.Advance(0.5, 0.05)
      H.eq(ranA, 10)

      -- ungueltige Argumente
      H.eq(U.Debounce(nil, 1, function() end), nil)
      H.eq(U.Debounce("k", 1, nil), nil)
      H.eq(U.TimerCount(), 0)
   end)

   H.test("Util: Timer-Zufallstest gegen ein einfaches Modell", function()
      local T = boot()
      local U = T.Util
      local rng = newRng(20240611)
      local FRAME = 0.05
      local DELAYS = { 0, 0.05, 0.1, 0.2, 0.25, 0.5, 1 }
      local frame = 0            -- Nummer des zuletzt ausgefuehrten Frames
      local nextId = 0
      local due, firedAt, calls = {}, {}, {}   -- [id] = Faelligkeitsframe / Frame des Laufs / Anzahl
      local cancelled = {}
      local handles = {}
      local armed = {}           -- Debounce-Schluessel -> id

      local function framesFor(d)
         return math.max(1, ceil(d / FRAME - 1e-9))
      end
      local function makeFn(id)
         return function()
            calls[id] = (calls[id] or 0) + 1
            firedAt[id] = frame
         end
      end

      for iter = 1, 500 do
         for _ = 1, rng(3) - 1 do
            local kind = rng(6)
            if kind <= 2 then
               local d = DELAYS[rng(#DELAYS)]
               nextId = nextId + 1
               handles[nextId] = U.After(d, makeFn(nextId))
               due[nextId] = frame + framesFor(d)
            elseif kind == 3 or kind == 4 then
               local key = "k" .. rng(3)
               local d = DELAYS[rng(#DELAYS)]
               nextId = nextId + 1
               if armed[key] and not firedAt[armed[key]] then cancelled[armed[key]] = true end
               handles[nextId] = U.Debounce(key, d, makeFn(nextId))
               due[nextId] = frame + framesFor(d)
               armed[key] = nextId
            elseif kind == 5 and nextId > 0 then
               local id = rng(nextId)
               if not firedAt[id] and not cancelled[id] then
                  H.eq(U.Cancel(handles[id]), true, "Cancel eines ausstehenden Timers")
                  cancelled[id] = true
               end
            elseif kind == 6 then
               local key = "k" .. rng(3)
               local id = armed[key]
               if id and not firedAt[id] and not cancelled[id] then
                  H.eq(U.Cancel(key), true, "Cancel per Schluessel")
                  cancelled[id] = true
               end
            end
         end
         frame = frame + 1
         mock.Advance(FRAME, FRAME)
         for id = 1, nextId do
            if not cancelled[id] and due[id] == frame then
               if firedAt[id] ~= frame then
                  H.fail("Timer " .. id .. " haette in Frame " .. frame .. " laufen muessen")
               end
            end
            if firedAt[id] then
               if cancelled[id] then H.fail("abgebrochener Timer " .. id .. " lief") end
               if firedAt[id] ~= due[id] then
                  H.fail("Timer " .. id .. " lief in Frame " .. firedAt[id] .. " statt " .. due[id])
               end
               if calls[id] ~= 1 then H.fail("Timer " .. id .. " lief " .. calls[id] .. "x") end
            end
         end
      end
      mock.Advance(3, FRAME)
      local pendingLeft = 0
      for id = 1, nextId do
         if not cancelled[id] and not firedAt[id] then pendingLeft = pendingLeft + 1 end
      end
      H.eq(pendingLeft, 0, "alle nicht abgebrochenen Timer sind gelaufen")
      H.eq(U.TimerCount(), 0)
      H.len(mock.UpdateFrames(), 0)
      H.truthy(nextId > 300, "genug Timer erzeugt")
   end)

   -- =======================================================================
   H.section("Events")
   -- =======================================================================

   H.test("Events.On/Fire: Argumente, Registrierungsreihenfolge, mehrere Handler", function()
      local T = boot()
      local E = T.Events
      local log = {}
      E.On("T_EVT", function(...) log[#log + 1] = { "h1", select("#", ...), ... } end)
      E.On("T_EVT", function(a, b) log[#log + 1] = { "h2", a, b } end)
      E.On("T_OTHER", function() log[#log + 1] = { "other" } end)
      E.Fire("T_EVT", "x", 5)
      H.len(log, 2)
      H.deepEq(log[1], { "h1", 2, "x", 5 })
      H.deepEq(log[2], { "h2", "x", 5 })
      E.Fire("T_EVT")
      H.deepEq(log[3], { "h1", 0 })
      -- Ereignis ohne Handler / Muell
      E.Fire("T_NOBODY", 1, 2, 3)
      E.Fire(nil)
      E.Fire("")
      H.len(log, 4)
      -- nil-Argumente in der Mitte bleiben erhalten
      local n
      E.On("T_NIL", function(...) n = select("#", ...) end)
      E.Fire("T_NIL", nil, nil, 1)
      H.eq(n, 3)
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Events.On: ungueltige Argumente; dieselbe Funktion nur einmal je Besitzer", function()
      local T = boot()
      local E = T.Events
      local n = 0
      local function fn() n = n + 1 end
      H.eq(E.On("T_X", nil), false)
      H.eq(E.On(nil, fn), false)
      H.eq(E.On("T_X", "keine funktion"), false)
      H.eq(E.On("T_X", fn), true)
      E.On("T_X", fn)           -- Doppelte Anmeldung
      E.Fire("T_X")
      H.eq(n, 1, "Doppelte Anmeldung zaehlt einmal")
      -- gleiche Funktion, anderer Besitzer: eigene Anmeldung
      local ownerA, ownerB = {}, {}
      E.On("T_Y", fn, ownerA)
      E.On("T_Y", fn, ownerB)
      n = 0
      E.Fire("T_Y")
      H.eq(n, 2)
      E.Off("T_Y", ownerA)
      n = 0
      E.Fire("T_Y")
      H.eq(n, 1, "nur der Besitzer A wurde entfernt")
   end)

   H.test("Events.Off: per Funktion und per Besitzer; owner nil tut nichts", function()
      local T = boot()
      local E = T.Events
      local log = {}
      local owner = { name = "modul" }
      local function f1() log[#log + 1] = "f1" end
      local function f2() log[#log + 1] = "f2" end
      local function f3() log[#log + 1] = "f3" end
      E.On("T_E", f1, owner)
      E.On("T_E", f2, owner)
      E.On("T_E", f3)
      H.eq(E.Off("T_E", nil), 0, "nil entfernt nichts")
      E.Fire("T_E")
      H.deepEq(log, { "f1", "f2", "f3" })
      log = {}
      H.eq(E.Off("T_E", owner), 2, "alle Handler des Besitzers")
      E.Fire("T_E")
      H.deepEq(log, { "f3" })
      log = {}
      H.eq(E.Off("T_E", f3), 1, "per Funktion")
      E.Fire("T_E")
      H.deepEq(log, {})
      H.eq(E.Off("T_E", f3), 0, "nochmal")
      H.eq(E.Off("T_UNKNOWN", f3), 0)
      H.eq(E.Off(nil, f3), 0)
      -- wieder anmelden nach vollstaendigem Abmelden
      E.On("T_E", f1)
      E.Fire("T_E")
      H.deepEq(log, { "f1" })
      -- Abmelden eines Handlers mit Besitzer per Funktion
      log = {}
      E.On("T_E2", f2, owner)
      E.Off("T_E2", f2)
      E.Fire("T_E2")
      H.deepEq(log, {})
   end)

   H.test("Events.Fire: Fehler eines Handlers stoppen die anderen nicht; Meldung einmal je Handler/Text", function()
      local T = boot()
      local E = T.Events
      local ran = {}
      E.On("T_ERR", function() ran[#ran + 1] = "first" end)
      E.On("T_ERR", function() error("kaputt-A") end)
      E.On("T_ERR", function() ran[#ran + 1] = "third" end)
      H.eq(pcall(E.Fire, "T_ERR"), true, "Fire wirft nie")
      H.deepEq(ran, { "first", "third" })
      local errors = H.takeErrors()
      H.len(errors, 1)
      H.contains(errors[1] or "", "kaputt-A")
      -- gleiche Meldung nochmal: nicht erneut
      E.Fire("T_ERR")
      E.Fire("T_ERR")
      H.len(H.takeErrors(), 0, "einmal je Handler und Meldung")
      H.len(ran, 6, "die gesunden Handler laufen jedes Mal")

      -- zwei verschiedene Handler mit derselben Meldung: je einmal
      E.On("T_ERR2", function() error("gleich") end)
      E.On("T_ERR2", function() error("gleich") end)
      E.Fire("T_ERR2")
      E.Fire("T_ERR2")
      H.len(H.takeErrors(), 2)

      -- wechselnde Meldungen: jede neue wird gemeldet, aber nicht unbegrenzt
      local k = 0
      E.On("T_ERR3", function() k = k + 1; error("nr " .. k) end)
      for _ = 1, 100 do E.Fire("T_ERR3") end
      local errs = H.takeErrors()
      H.truthy(#errs >= 1, "mindestens die erste Meldung")
      H.truthy(#errs <= 50, "begrenzt (" .. #errs .. ")")

      -- Fehlerwert ist keine Zeichenkette
      E.On("T_ERR4", function() error({ code = 5 }) end)
      H.eq(pcall(E.Fire, "T_ERR4"), true)
      H.len(H.takeErrors(), 1)
      -- Fehler im Fehlerbehandler selbst: Fire bleibt heil
      local real = geterrorhandler()
      seterrorhandler(function() error("handler kaputt") end)
      E.On("T_ERR5", function() error("x") end)
      H.eq(pcall(E.Fire, "T_ERR5"), true)
      seterrorhandler(real)
   end)

   H.test("Events.Fire: Aenderungen waehrend des Durchlaufs", function()
      local T = boot()
      local E = T.Events
      local log = {}
      local function late() log[#log + 1] = "late" end
      local function added() log[#log + 1] = "added" end
      local function remover()
         log[#log + 1] = "remover"
         E.Off("T_MOD", late)
         E.On("T_MOD", added)
      end
      E.On("T_MOD", remover)
      E.On("T_MOD", late)
      E.Fire("T_MOD")
      H.deepEq(log, { "remover" }, "abgemeldeter Handler laeuft nicht mehr; neuer erst beim naechsten Mal")
      log = {}
      E.Fire("T_MOD")
      H.deepEq(log, { "remover", "added" })

      -- Handler meldet sich selbst ab: Rest laeuft weiter, naechstes Mal nicht mehr
      log = {}
      local function once()
         log[#log + 1] = "once"
         E.Off("T_ONCE", once)
      end
      E.On("T_ONCE", once)
      E.On("T_ONCE", function() log[#log + 1] = "stay" end)
      E.Fire("T_ONCE")
      H.deepEq(log, { "once", "stay" })
      log = {}
      E.Fire("T_ONCE")
      H.deepEq(log, { "stay" })

      -- verschachteltes Fire desselben Ereignisses
      log = {}
      local depth = 0
      E.On("T_NEST", function(n)
         log[#log + 1] = n
         if n < 3 then E.Fire("T_NEST", n + 1) end
         depth = depth + 1
      end)
      E.Fire("T_NEST", 1)
      H.deepEq(log, { 1, 2, 3 })
      H.eq(depth, 3)
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Events.Fire: ein Handler, der abmeldet und anmeldet, haelt die Reihenfolge der anderen", function()
      local T = boot()
      local E = T.Events
      local log = {}
      local owner = {}
      for i = 1, 5 do
         E.On("T_ORDER", function() log[#log + 1] = i end, i % 2 == 0 and owner or nil)
      end
      E.Off("T_ORDER", owner)
      E.Fire("T_ORDER")
      H.deepEq(log, { 1, 3, 5 })
   end)

   H.test("Events.Game: ein gemeinsamer Frame, fn(event, ...), Fehlerisolation", function()
      local T = boot()
      local E = T.Events
      H.eq(framesRegistered("PLAYER_MONEY"), 0)
      local log = {}
      H.eq(E.Game("PLAYER_MONEY", function(event, ...) log[#log + 1] = { "m1", event, ... } end), true)
      E.Game("PLAYER_MONEY", function(event, a) log[#log + 1] = { "m2", event, a } end)
      E.Game("UNIT_AURA", function(event, unit) log[#log + 1] = { "aura", event, unit } end)
      H.eq(framesRegistered("PLAYER_MONEY"), 1, "ein Frame fuer alle Handler")
      H.eq(framesRegistered("UNIT_AURA"), 1)
      -- ein Frame fuer alle Ereignisse
      local frame
      for _, f in ipairs(mock.frames) do
         local evs = rawget(f, "__events")
         if evs and evs.PLAYER_MONEY then frame = f end
      end
      H.truthy(frame and rawget(frame, "__events").UNIT_AURA, "gleicher Frame")

      mock.Fire("PLAYER_MONEY", 150)
      H.len(log, 2)
      H.deepEq(log[1], { "m1", "PLAYER_MONEY", 150 })
      H.deepEq(log[2], { "m2", "PLAYER_MONEY", 150 })
      mock.Fire("UNIT_AURA", "player")
      H.deepEq(log[3], { "aura", "UNIT_AURA", "player" })

      -- Fehler: andere Handler laufen, Meldung kommt beim Fehlerbehandler an
      E.Game("PLAYER_LEVEL_UP", function() error("level-boom") end)
      E.Game("PLAYER_LEVEL_UP", function() log[#log + 1] = { "lvl" } end)
      mock.Fire("PLAYER_LEVEL_UP", 80)
      H.deepEq(log[4], { "lvl" })
      local errors = H.takeErrors()
      H.len(errors, 1)
      H.contains(errors[1] or "", "level-boom")
      mock.Fire("PLAYER_LEVEL_UP", 81)
      H.len(H.takeErrors(), 0, "gleiche Meldung nicht nochmal")
   end)

   H.test("Events.Game/UnGame: doppelte Funktion, Abmelden, Frame meldet das Ereignis ab", function()
      local T = boot()
      local E = T.Events
      local n = 0
      local function a() n = n + 1 end
      local function b() n = n + 10 end
      H.eq(E.Game("PLAYER_MONEY", a), true)
      H.eq(E.Game("PLAYER_MONEY", a), false, "doppelt")
      E.Game("PLAYER_MONEY", b)
      mock.Fire("PLAYER_MONEY")
      H.eq(n, 11)

      H.eq(E.UnGame("PLAYER_MONEY", a), true)
      H.eq(E.UnGame("PLAYER_MONEY", a), false)
      n = 0
      mock.Fire("PLAYER_MONEY")
      H.eq(n, 10)
      H.eq(framesRegistered("PLAYER_MONEY"), 1, "b ist noch da")
      H.eq(E.UnGame("PLAYER_MONEY", b), true)
      H.eq(framesRegistered("PLAYER_MONEY"), 0, "letzter Handler weg -> abgemeldet")
      n = 0
      mock.Fire("PLAYER_MONEY")
      H.eq(n, 0)
      -- erneut anmelden
      E.Game("PLAYER_MONEY", a)
      H.eq(framesRegistered("PLAYER_MONEY"), 1)
      mock.Fire("PLAYER_MONEY")
      H.eq(n, 1)
      -- ungueltig
      H.eq(E.Game(nil, a), false)
      H.eq(E.Game("PLAYER_MONEY", nil), false)
      H.eq(E.Game("", a), false)
      H.eq(E.UnGame("NIE_ANGEMELDET", a), false)
      H.eq(E.UnGame("PLAYER_MONEY", nil), false)
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Events.Game: UnGame und Game waehrend der Zustellung", function()
      local T = boot()
      local E = T.Events
      local log = {}
      local function second() log[#log + 1] = "second" end
      local function third() log[#log + 1] = "third" end
      E.Game("PLAYER_MONEY", function()
         log[#log + 1] = "first"
         E.UnGame("PLAYER_MONEY", second)
         E.Game("PLAYER_MONEY", third)
      end)
      E.Game("PLAYER_MONEY", second)
      mock.Fire("PLAYER_MONEY")
      H.deepEq(log, { "first" })
      log = {}
      mock.Fire("PLAYER_MONEY")
      H.deepEq(log, { "first", "third" })
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Events.Game: ein unbekannter oder fremder Ereignisname bricht nicht ab", function()
      local T = boot()
      local E = T.Events
      local ran = 0
      -- dieses Ereignis gibt es in 3.3.5a nicht: RegisterEvent wirft im Mock
      local foreign = "GET_ITEM_INFO" .. "_RECEIVED"
      local ok = pcall(E.Game, foreign, function() ran = ran + 1 end)
      H.eq(ok, true, "kein Fehler nach aussen")
      local ok2 = pcall(E.Game, "TRANSMOG_NOT_AN_EVENT", function() ran = ran + 1 end)
      H.eq(ok2, true)
      mock.Fire("TRANSMOG_NOT_AN_EVENT")
      H.eq(ran, 1)
   end)

   -- =======================================================================
   H.section("DB")
   -- =======================================================================

   -- Vorgaben laut SPEC 5.4
   local function defaultsGlobal()
      return {
         version = 2, locale = "auto", scale = 0, width = 880, height = 600, previewSize = 1.0,
         sound = true, toasts = true, tooltipCollected = true, tooltipApplied = true,
         allowAnywhere = true, lastTab = "items",
         noNpcDefault = true,      -- Marke der einmaligen Uebernahme "Anwenden auch ohne Transmogrifizierer" (2.1)
      }
   end
   local function defaultsChar()
      return {
         version = 2, outfits = {}, favorites = {},
         filter = { qualities = {}, typesOff = {}, hideDuplicates = true, sort = "QUALITY",
                    favoritesOnly = false, newOnly = false },
         migrated = 2,
      }
   end

   H.test("DB.Init: legt beide Tabellen mit den Vorgaben an (ohne Altdaten)", function()
      local T = boot({ noSeed = true })           -- Neuinstallation: die echten Vorgaben (allowAnywhere an)
      local g, c = T.DB.Init()
      H.eq(T.DB.global, g)
      H.eq(T.DB.char, c)
      H.eq(TransmogGlobalDB, g, "SavedVariables-Tabelle")
      H.eq(TransmogDB, c)
      H.deepEq(g, defaultsGlobal())
      H.deepEq(c, defaultsChar())
      H.eq(g.point, nil)
      H.eq(g.toastPoint, nil)
      H.eq(c.lastSlot, nil)
   end)

   H.test("DB.Init: ergaenzt fehlende Werte rekursiv, ueberschreibt nichts", function()
      local T = boot({ globals = {
         TransmogGlobalDB = { locale = "deDE", scale = 1.2, sound = false, extra = "bleibt" },
         TransmogDB = { outfits = { { name = "A", slots = { [0] = 5 }, time = 3 } }, favorites = { [5] = true },
                        filter = { hideDuplicates = false, sort = "NAME", qualities = { [0] = false } },
                        migrated = 2, lastSlot = 4, version = 2 },
      } })
      local g, c = T.DB.Init()
      H.eq(g.locale, "deDE")
      H.eq(g.scale, 1.2)
      H.eq(g.sound, false)
      H.eq(g.extra, "bleibt", "fremde Schluessel bleiben")
      H.eq(g.width, 880, "fehlend -> Vorgabe")
      H.eq(g.toasts, true)
      H.eq(g.lastTab, "items")
      H.eq(#c.outfits, 1)
      H.eq(c.outfits[1].name, "A")
      H.eq(c.favorites[5], true)
      H.eq(c.filter.hideDuplicates, false)
      H.eq(c.filter.sort, "NAME")
      H.eq(c.filter.qualities[0], false)
      H.eq(c.filter.favoritesOnly, false, "fehlend -> Vorgabe")
      H.eq(type(c.filter.typesOff), "table")
      H.eq(c.lastSlot, 4)
   end)

   H.test("DB.Init: bringt ungueltige Werte auf gueltige", function()
      local T = boot({ globals = {
         TransmogGlobalDB = {
            locale = "klingon", scale = "gross", width = -5, height = "x", previewSize = 1.1,
            sound = "ja", toasts = 1, tooltipCollected = {}, tooltipApplied = "false", allowAnywhere = "true",
            lastTab = "nonsense", point = "mitte", toastPoint = { "WUNSCH", "CENTER", 1, 2 }, version = "x",
         },
         TransmogDB = {
            outfits = "kaputt", favorites = 5, version = 0,
            filter = { qualities = "x", typesOff = 7, hideDuplicates = "yes", sort = "WEIRD",
                       favoritesOnly = 1, newOnly = "no" },
            lastSlot = 1, migrated = "alt",
         },
      } })
      local g, c = T.DB.Init()
      H.deepEq(g, defaultsGlobal(), "global")
      H.eq(g.point, nil)
      H.eq(g.toastPoint, nil)
      H.eq(c.migrated, 2)
      H.deepEq(c, defaultsChar(), "char")
      H.eq(c.lastSlot, nil, "Slot 1 (Hals) gibt es nicht")
   end)

   H.test("DB.Init: Wertebereiche (scale, previewSize, Slot, Positionen)", function()
      local T = boot({ globals = { TransmogGlobalDB = { scale = 0.3, previewSize = 1.3 } } })
      local g = T.DB.Init()
      H.eq(g.scale, 0.6, "Skalierung 0,6..1,5")
      H.eq(g.previewSize, 1.25, "naechste gueltige Vorschaugroesse")
      g.scale = 9
      g.previewSize = 5
      T.DB.Init()
      H.eq(g.scale, 1.5)
      H.eq(g.previewSize, 1.5)
      g.scale = 0.75
      g.previewSize = 0.8
      T.DB.Init()
      H.eq(g.scale, 0.75)
      H.eq(g.previewSize, 0.8)
      g.scale = 0
      T.DB.Init()
      H.eq(g.scale, 0, "0 = automatisch")
      g.scale = -2
      T.DB.Init()
      H.eq(g.scale, 0)
      -- gueltige Fensterposition bleibt unveraendert
      g.point = { "CENTER", "CENTER", 10, -20 }
      g.toastPoint = { "TOPRIGHT", "TOPRIGHT", -30, -200 }
      T.DB.Init()
      H.deepEq(g.point, { "CENTER", "CENTER", 10, -20 })
      H.deepEq(g.toastPoint, { "TOPRIGHT", "TOPRIGHT", -30, -200 })
      g.point = { "CENTER", "CENTER" }
      T.DB.Init()
      H.eq(g.point, nil, "ohne Offsets ungueltig")
   end)

   H.test("DB.Init: idempotent, Tabellen bleiben dieselben, Aenderungen bleiben erhalten", function()
      local T = boot()
      local g, c = T.DB.Init()
      c.favorites[123] = true
      c.outfits[1] = { name = "Mein Outfit", slots = { [0] = 1, [4] = 999999 }, time = 5 }
      g.sound = false
      local copyG, copyC = T.Util.CopyTable(g), T.Util.CopyTable(c)
      local g2, c2 = T.DB.Init()
      H.eq(g2, g)
      H.eq(c2, c)
      H.deepEq(g, copyG)
      H.deepEq(c, copyC)
      -- Verweise auf Unterlisten bleiben gueltig (Outfits halten die Tabelle)
      local outfits = c.outfits
      T.DB.Init()
      H.eq(c.outfits, outfits)
      -- nicht geteilt: zwei Aufrufe liefern nie dieselbe Vorgabetabelle
      TransmogDB = nil
      TransmogGlobalDB = nil
      local g3, c3 = T.DB.Init()
      H.neq(c3.favorites, c.favorites)
      H.neq(c3.filter, c.filter)
      c3.filter.typesOff[400] = true
      c3.favorites[1] = true
      H.eq(c.filter.typesOff[400], nil)
   end)


   -- -----------------------------------------------------------------------
   -- "Anwenden auch ohne Transmogrifizierer" (allowAnywhere): seit 2.1 standardmaessig an.
   -- Der Server prueft den Abstand zum NPC nicht (TransmogAddonProtocol.cpp). Dateien aus 2.0 tragen noch den
   -- frueheren Standard false: einmalig auf true (Marke global.noNpcDefault), danach gilt die Wahl des Spielers.
   -- -----------------------------------------------------------------------

   H.test("allowAnywhere: Neuinstallation (keine gespeicherten Variablen) -> an, Marke gesetzt", function()
      local T = boot({ noSeed = true })
      H.eq(rawget(_G, "TransmogGlobalDB"), nil, "wirklich nichts gespeichert")
      local g = T.DB.Init()
      H.eq(g.allowAnywhere, true)
      H.eq(g.noNpcDefault, true, "Marke gesetzt")
      H.eq(TransmogGlobalDB.allowAnywhere, true, "in den SavedVariables")
      H.eq(TransmogGlobalDB.noNpcDefault, true)
      -- das Boot-Seed der Tests (Vorschau-Modus) ist davon getrennt: ohne noSeed beginnt der Test "aus"
      local T2 = boot()
      local g2 = T2.DB.Init()
      H.eq(g2.allowAnywhere, false)
      H.eq(g2.noNpcDefault, true)
   end)

   H.test("allowAnywhere: Datei aus 2.0 (false, ohne Marke) wird genau einmal auf true gesetzt, vor den Vorgaben", function()
      -- so sieht die Datei eines 2.0-Spielers aus (nur Einstellungen, keine Marke)
      local T = boot({ globals = { TransmogGlobalDB = {
         version = 2, locale = "deDE", scale = 1.2, width = 900, height = 600, sound = false, lastTab = "outfits",
         allowAnywhere = false, tooltipApplied = true, toasts = true,
      } } })
      local g = T.DB.Init()
      H.eq(g.allowAnywhere, true, "einmalig uebernommen")
      H.eq(g.noNpcDefault, true)
      -- alles andere bleibt, wie der Spieler es hatte
      H.eq(g.locale, "deDE")
      H.eq(g.scale, 1.2)
      H.eq(g.width, 900)
      H.eq(g.sound, false)
      H.eq(g.lastTab, "outfits")
      -- weitere Laeufe in derselben Sitzung aendern nichts mehr
      T.DB.Init()
      H.eq(g.allowAnywhere, true)
      -- der Spieler schaltet es aus: ein erneutes Init (z. B. spaeter in der Sitzung) macht es nicht wieder an
      T.DB.Set("allowAnywhere", false)
      H.eq(g.allowAnywhere, false)
      T.DB.Init()
      T.DB.Init()
      H.eq(g.allowAnywhere, false, "die Wahl des Spielers gilt")
      H.eq(g.noNpcDefault, true)
   end)

   H.test("allowAnywhere: vom Spieler ausgeschaltet bleibt es ueber Abmelden und Anmelden aus (Marke ist da)", function()
      local T = boot({ noSeed = true })
      local g = T.DB.Init()
      H.eq(g.allowAnywhere, true)
      T.DB.Set("allowAnywhere", false)
      local sv = mock.SavedVariables()
      H.eq(sv.TransmogGlobalDB.allowAnywhere, false, "gespeichert")
      H.eq(sv.TransmogGlobalDB.noNpcDefault, true, "Marke gespeichert")
      for session = 1, 3 do
         local Tn = boot({ globals = sv })
         local gn = Tn.DB.Init()
         H.eq(gn.allowAnywhere, false, "Sitzung " .. session)
         H.eq(gn.noNpcDefault, true)
         sv = mock.SavedVariables()
      end
      -- wieder einschalten und neu anmelden
      local T4 = boot({ globals = sv })
      local g4 = T4.DB.Init()
      T4.DB.Set("allowAnywhere", true)
      local T5 = boot({ globals = mock.SavedVariables() })
      H.eq(T5.DB.Init().allowAnywhere, true)
      H.eq(g4.noNpcDefault, true)
   end)

   H.test("allowAnywhere: Datei mit Marke und false wird nicht angefasst; mit Marke und true bleibt true", function()
      local T = boot({ globals = { TransmogGlobalDB = { version = 2, noNpcDefault = true, allowAnywhere = false } } })
      local g = T.DB.Init()
      H.eq(g.allowAnywhere, false)
      H.eq(g.noNpcDefault, true)
      T.DB.Init()
      H.eq(g.allowAnywhere, false, "auch nach weiteren Laeufen")

      local T2 = boot({ globals = { TransmogGlobalDB = { version = 2, noNpcDefault = true, allowAnywhere = true } } })
      H.eq(T2.DB.Init().allowAnywhere, true)

      -- Marke da, Wert fehlt ganz: die Vorgabe (an) fuellt auf
      local T3 = boot({ globals = { TransmogGlobalDB = { version = 2, noNpcDefault = true } } })
      H.eq(T3.DB.Init().allowAnywhere, true, "fehlender Wert -> Vorgabe an")
   end)

   H.test("allowAnywhere: ungueltige Werte (Text, Zahl, Tabelle, NaN) werden mit Marke zur Vorgabe 'an'", function()
      local garbage = { "false", "nein", "", 0, 1, -1, 0 / 0, math.huge, {}, { false } }
      for i, bad in ipairs(garbage) do
         local T = boot({ globals = { TransmogGlobalDB = { version = 2, noNpcDefault = true, allowAnywhere = bad } } })
         local g = T.DB.Init()
         H.eq(g.allowAnywhere, true, "Fall " .. i .. " (" .. type(bad) .. ")")
         H.eq(g.noNpcDefault, true)
      end
      -- auch ueber DB.Set: kein Boolean -> Vorgabe an; echtes false bleibt false
      local T = boot({ noSeed = true })
      T.DB.Init()
      T.DB.Set("allowAnywhere", false)
      H.eq(T.DB.global.allowAnywhere, false)
      for _, bad in ipairs({ "false", 0, {}, "nein" }) do
         T.DB.Set("allowAnywhere", false)
         T.DB.Set("allowAnywhere", bad)
         H.eq(T.DB.global.allowAnywhere, true, "DB.Set(" .. type(bad) .. ")")
      end
      T.DB.Set("allowAnywhere", false)
      T.DB.Set("allowAnywhere", nil)
      H.eq(T.DB.global.allowAnywhere, true, "nil -> Vorgabe an")
   end)

   H.test("allowAnywhere: unbrauchbare Marke (Text, 1, false, Tabelle) zaehlt als 'nicht gesetzt' und wird zu true", function()
      for i, flag in ipairs({ "ja", "true", 1, 0, false, {}, { true } }) do
         local T = boot({ globals = { TransmogGlobalDB = { version = 2, noNpcDefault = flag, allowAnywhere = false } } })
         local g = T.DB.Init()
         H.eq(g.noNpcDefault, true, "Marke repariert (Fall " .. i .. ")")
         H.eq(g.allowAnywhere, true, "einmalig auf an (Fall " .. i .. ")")
         T.DB.Set("allowAnywhere", false)
         T.DB.Init()
         H.eq(g.allowAnywhere, false, "danach gilt die Wahl (Fall " .. i .. ")")
      end
   end)

   H.test("allowAnywhere: feindliche Formen von TransmogGlobalDB (kein Table, Array, Funktion) werfen nicht", function()
      local shapes = {
         { "Text", "text" }, { "Zahl", 7 }, { "true", true }, { "false", false }, { "Funktion", function() end },
         { "Array", { "a", "b", 3 } }, { "Array mit Loch", { [1] = "x", [5] = "y" } },
         { "verschachtelt", { allowAnywhere = { false }, noNpcDefault = { true }, locale = {} } },
         { "gemischt", { 1, 2, 3, allowAnywhere = false } },
      }
      local T = boot()
      for _, shape in ipairs(shapes) do
         rawset(_G, "TransmogGlobalDB", shape[2])
         rawset(_G, "TransmogDB", nil)
         local ok, g = pcall(T.DB.Init)
         H.truthy(ok, shape[1] .. ": " .. tostring(g))
         if ok then
            H.eq(type(g), "table", shape[1])
            H.eq(g.allowAnywhere, true, shape[1] .. ": an")
            H.eq(g.noNpcDefault, true, shape[1] .. ": Marke")
            H.eq(rawget(_G, "TransmogGlobalDB"), g, shape[1] .. ": SavedVariables-Tabelle")
            if shape[1] == "verschachtelt" then H.eq(g.locale, "auto", "Muell in locale -> auto") end
            -- zweiter Lauf: unveraendert
            local snap = T.Util.CopyTable(g)
            T.DB.Init()
            H.deepEq(g, snap, shape[1] .. ": idempotent")
         end
      end
      rawset(_G, "TransmogGlobalDB", nil)
      rawset(_G, "TransmogDB", nil)
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("allowAnywhere: die Uebernahme laeuft vor Vorgaben und Pruefung (Zusammenspiel mit anderen Altwerten)", function()
      -- Datei aus 2.0 mit weiteren kaputten Werten: die Pruefung bessert sie aus, die Uebernahme setzt allowAnywhere
      local T = boot({ globals = { TransmogGlobalDB = {
         version = 1, allowAnywhere = "false", scale = "gross", sound = "ja", width = -3,
      } } })
      local g = T.DB.Init()
      H.eq(g.allowAnywhere, true)
      H.eq(g.noNpcDefault, true)
      H.eq(g.scale, 0)
      H.eq(g.sound, true)
      H.eq(g.width, 880)
      H.eq(g.version, 2)
      -- die Legacy-Uebernahme der Outfits (char.migrated) bleibt unabhaengig: sie ist nicht an die Marke gebunden
      local T2 = boot({ globals = {
         transmogOutfits = { Tank = { [1] = 111 } },
         TransmogGlobalDB = { version = 2, allowAnywhere = false },
      } })
      local g2, c2 = T2.DB.Init()
      H.eq(g2.allowAnywhere, true)
      H.eq(c2.migrated, 2)
      H.len(c2.outfits, 1)
      -- fehlt nur die Marke, aber Outfits sind schon uebernommen: allowAnywhere wird trotzdem einmalig gesetzt
      local T3 = boot({ globals = {
         TransmogGlobalDB = { version = 2, allowAnywhere = false },
         TransmogDB = { version = 2, migrated = 2 },
      } })
      local g3 = T3.DB.Init()
      H.eq(g3.allowAnywhere, true)
   end)

   H.test("DB.Init: bereinigt Outfits, Favoriten und Filtermengen", function()
      local T = boot({ globals = { TransmogDB = {
         version = 2, migrated = 2,
         outfits = {
            { name = "ok", slots = { [0] = 10, [3] = 999999, [1] = 5, [20] = 6, [2] = "x", [4] = -1, [5] = 2.5 }, time = 7 },
            "kein outfit",
            { name = "", slots = {} },
            { name = "ohne slots" },
            { name = 5, slots = {} },
            { name = "ohne zeit", slots = { [18] = 1 } },
         },
         favorites = { [100] = true, [0] = true, [-1] = true, [5.5] = true, [200] = false, x = true, [300] = "ja" },
         filter = { qualities = { [0] = false, [7] = false, [8] = false, [2] = true, [-1] = false, [1.5] = false },
                    typesOff = { [201] = true, [403] = true, [404] = false, x = true } },
      } } })
      local _, c = T.DB.Init()
      H.eq(#c.outfits, 2)
      H.eq(c.outfits[1].name, "ok")
      H.deepEq(c.outfits[1].slots, { [0] = 10, [3] = 999999 })
      H.eq(c.outfits[1].time, 7)
      H.eq(c.outfits[2].name, "ohne zeit")
      H.eq(c.outfits[2].time, 0)
      H.deepEq(c.favorites, { [100] = true })
      H.deepEq(c.filter.qualities, { [0] = false, [7] = false })
      H.deepEq(c.filter.typesOff, { [201] = true, [403] = true })
   end)

   -- Legacy-Daten im echten gespeicherten Format
   local function legacyOutfits()
      return {
         ["Tank"] = { [1] = 111, [3] = 222, [5] = 999999, [6] = 0, [2] = 777, [19] = 333, [11] = 888, [14] = 9 },
         ["Raid Look"] = { [16] = 4444, [17] = 5555, [18] = 6666, [15] = 1, [10] = 2, [9] = 3, [4] = 4,
                           [7] = 5, [8] = 6 },
         ["Leer"] = { [1] = 0 },
      }
   end

   H.test("Migration: transmogOutfits -> char.outfits (Client-Slot - 1, nur die 14, 0 ignoriert)", function()
      local legacy = legacyOutfits()
      local T = boot({ globals = { transmogOutfits = legacy } })
      local _, c = T.DB.Init()
      H.eq(c.migrated, 2)
      H.len(c.outfits, 3)
      local by = {}
      for _, o in ipairs(c.outfits) do by[o.name] = o end
      H.truthy(by.Tank and by["Raid Look"] and by.Leer, "alle drei Namen")
      -- Tank: 1 -> 0, 3 -> 2, 5 (Brust) -> 4 HIDDEN, 6 -> 0 ignoriert, 2 (Hals) weg, 19 -> 18, 11/14 (Ring/Schmuck) weg
      H.deepEq(by.Tank.slots, { [0] = 111, [2] = 222, [4] = 999999, [18] = 333 })
      -- Raid Look: 16 -> 15, 17 -> 16, 18 -> 17, 15 -> 14, 10 -> 9, 9 -> 8, 4 -> 3, 7 -> 6, 8 -> 7
      H.deepEq(by["Raid Look"].slots, { [15] = 4444, [16] = 5555, [17] = 6666, [14] = 1, [9] = 2, [8] = 3,
                                        [3] = 4, [6] = 5, [7] = 6 })
      H.deepEq(by.Leer.slots, {})
      for _, o in ipairs(c.outfits) do
         H.eq(type(o.time), "number", o.name .. " time")
         H.eq(type(o.name), "string")
      end
      -- Altdaten bleiben unveraendert
      H.deepEq(transmogOutfits, legacyOutfits())
      -- deterministische Reihenfolge (nach Namen)
      H.eq(c.outfits[1].name, "Leer")
      H.eq(c.outfits[2].name, "Raid Look")
      H.eq(c.outfits[3].name, "Tank")
   end)

   H.test("Migration: transmogSettings.hideDuplicates und armorTypes (echtes Format)", function()
      local T = boot({ globals = { transmogSettings = {
         hideDuplicates = false,
         armorTypes = { [7] = false, [5] = false, [8] = false },
      } } })
      local _, c = T.DB.Init()
      H.eq(c.filter.hideDuplicates, false)
      -- Schluessel 5,7,8 aus, 6 fehlt -> galt als aus (nur Kette war ohne Eintrag an)
      H.deepEq(c.filter.typesOff, { [401] = true, [402] = true, [403] = true, [404] = true })
      H.deepEq(transmogSettings, { hideDuplicates = false, armorTypes = { [7] = false, [5] = false, [8] = false } })
   end)

   H.test("Migration: fehlender armorTypes-Schluessel = nur Kette (7) war an", function()
      local cases = {
         { armor = { [5] = true, [6] = false, [8] = true }, off = { [402] = true } },      -- 7 fehlt -> an
         { armor = { [5] = true, [8] = true }, off = { [402] = true } },                   -- 6, 7 fehlen
         { armor = { [8] = true }, off = { [401] = true, [402] = true } },
         { armor = { [5] = true, [6] = true, [7] = true, [8] = true }, off = {} },
         { armor = { [7] = false }, off = { [401] = true, [402] = true, [403] = true, [404] = true } },
         { armor = {}, off = { [401] = true, [402] = true, [404] = true } },               -- leere Tabelle
      }
      for i, case in ipairs(cases) do
         local T = boot({ globals = { transmogSettings = { armorTypes = case.armor } } })
         local _, c = T.DB.Init()
         H.deepEq(c.filter.typesOff, case.off, "Fall " .. i)
         H.eq(c.filter.hideDuplicates, true, "ohne hideDuplicates bleibt die Vorgabe (Fall " .. i .. ")")
      end
   end)

   H.test("Migration: ohne armorTypes-Tabelle wird nichts ausgeblendet; hideDuplicates true", function()
      local T = boot({ globals = { transmogSettings = { hideDuplicates = true } } })
      local _, c = T.DB.Init()
      H.eq(c.filter.hideDuplicates, true)
      H.deepEq(c.filter.typesOff, {})
   end)

   H.test("Migration: einmalig; geloeschte Outfits kommen nicht zurueck", function()
      local T = boot({ globals = { transmogOutfits = legacyOutfits() } })
      local _, c = T.DB.Init()
      H.len(c.outfits, 3)
      table.remove(c.outfits, 1)
      T.DB.Init()
      H.len(c.outfits, 2, "keine zweite Uebernahme")
      -- auch ueber Abmelden/Anmelden hinweg
      local sv = mock.SavedVariables()
      H.eq(sv.TransmogDB.migrated, 2)
      local T2 = boot({ globals = sv })
      local _, c2 = T2.DB.Init()
      H.len(c2.outfits, 2)
      H.deepEq(c2.outfits, c.outfits)
      -- das gespeicherte Format wird ebenfalls beim naechsten Mal nicht noch einmal migriert,
      -- selbst wenn die Altvariablen wieder da sind
      local T3 = boot({ globals = { TransmogDB = sv.TransmogDB, TransmogGlobalDB = sv.TransmogGlobalDB,
                                    transmogOutfits = legacyOutfits() } })
      local _, c3 = T3.DB.Init()
      H.len(c3.outfits, 2)
   end)

   H.test("Migration: unbrauchbares migrated (Text, NaN, unendlich) zaehlt als nie migriert, danach 2", function()
      for i, bad in ipairs({ "alt", 0 / 0, math.huge, -math.huge, -3, true }) do
         local T = boot({ globals = {
            transmogOutfits = { ["Einzig"] = { [1] = 42 } },
            TransmogDB = { migrated = bad },
         } })
         local _, c = T.DB.Init()
         H.eq(c.migrated, 2, "Fall " .. i)
         H.len(c.outfits, 1, "Fall " .. i)
         T.DB.Init()
         H.len(c.outfits, 1, "kein zweites Mal (Fall " .. i .. ")")
      end
      -- ein migrated >= 2 (auch spaeter einmal 3) bleibt unangetastet und blockiert die Uebernahme
      local T = boot({ globals = {
         transmogOutfits = { ["Einzig"] = { [1] = 42 } },
         TransmogDB = { migrated = 3 },
      } })
      local _, c = T.DB.Init()
      H.len(c.outfits, 0)
      H.eq(c.migrated, 3)
   end)

   H.test("Migration: ohne Altdaten nichts uebernommen, migrated = 2; Muell in den Altvariablen", function()
      local T = boot()
      local _, c = T.DB.Init()
      H.eq(c.migrated, 2)
      H.len(c.outfits, 0)
      H.len(mock.messages, 0, "keine Meldung ohne Outfits")
      mock.Advance(10)
      H.len(mock.messages, 0)

      -- Muell als Altvariablen
      local junkSets = {
         { transmogOutfits = "text", transmogSettings = 5 },
         { transmogOutfits = { [1] = { [1] = 5 }, [true] = {}, Name = "x", Gut = { [1] = "7", [2] = "abc",
                                                                                   ["x"] = 3, [3] = 1.5 } },
           transmogSettings = { armorTypes = "x", hideDuplicates = "ja" } },
      }
      for i, globals in ipairs(junkSets) do
         local T2 = boot({ globals = globals })
         local ok, err = pcall(T2.DB.Init)
         H.truthy(ok, "Fall " .. i .. ": " .. tostring(err))
         if ok then H.eq(T2.DB.char.migrated, 2) end
      end
      local _, c2 = T.DB.Init()
      -- im letzten Fall: "Gut" mit Slot 1 -> 0 (Zahlentext 7) ; Slot 2/3 sind Muell oder kein ganzzahliger Wert
      local T3 = boot({ globals = junkSets[2] })
      local _, c3 = T3.DB.Init()
      H.len(c3.outfits, 1)
      H.eq(c3.outfits[1].name, "Gut")
      H.deepEq(c3.outfits[1].slots, { [0] = 7 })
      H.eq(c3.filter.hideDuplicates, true, "kein Boolean -> Vorgabe")
      H.deepEq(c3.filter.typesOff, {})
      H.eq(c2.migrated, 2)
   end)

   H.test("Migration: Namen werden bereinigt, gekuerzt, eindeutig gemacht; Obergrenze 50", function()
      local legacy = {
         ["|cffff0000Rot|r  und   blau"] = { [1] = 2 },
         ["   "] = { [1] = 3 },
         ["Bunt"] = { [1] = 1 },
         ["bunt"] = { [1] = 4 },
         [string.rep("x", 40)] = { [1] = 5 },
         [string.rep("\195\164", 40)] = { [1] = 6 },
      }
      local T = boot({ globals = { transmogOutfits = legacy } })
      local _, c = T.DB.Init()
      local names = {}
      for _, o in ipairs(c.outfits) do names[o.name] = o end
      H.truthy(names["Rot und blau"], "Farbcodes und Leerraum bereinigt")
      H.falsy(names["   "], "leerer Name verworfen")
      H.truthy(names.Bunt and names["bunt (2)"], "Namenskollision ohne Gross/Klein: Suffix")
      H.truthy(names[string.rep("x", 32)], "auf 32 Zeichen gekuerzt")
      H.truthy(names[string.rep("\195\164", 32)], "UTF-8: 32 Zeichen, nie mitten im Zeichen")
      for _, o in ipairs(c.outfits) do
         local len = select(2, o.name:gsub("[^\128-\191]", ""))
         H.truthy(len <= 32, o.name .. " zu lang")
      end

      -- Obergrenze
      local many = {}
      for i = 1, 70 do many[string.format("Outfit %02d", i)] = { [1] = i } end
      local T2 = boot({ globals = { transmogOutfits = many } })
      local _, c2 = T2.DB.Init()
      H.len(c2.outfits, 50)
      H.eq(c2.outfits[1].name, "Outfit 01", "die ersten nach Namen")
      H.eq(c2.outfits[50].name, "Outfit 50")
   end)

   H.test("Migration: Meldung ueber die uebernommenen Outfits (verzoegert)", function()
      local T = boot({ globals = { transmogOutfits = legacyOutfits() } })
      T.DB.Init()
      H.len(mock.messages, 0, "nicht sofort")
      mock.Advance(10)
      H.len(mock.messages, 1)
      H.contains(lastMessage(), "[Transmog]")
      H.contains(lastMessage(), "3")
      H.contains(lastMessage(), "outfits")
      -- zweiter Init: keine zweite Meldung
      T.DB.Init()
      mock.Advance(10)
      H.len(mock.messages, 1)
   end)

   H.test("DB.Set/SetChar: speichern, pruefen, SETTINGS_CHANGED(key) feuern", function()
      local T = boot()
      local g, c = T.DB.Init()
      local log = {}
      T.Events.On("SETTINGS_CHANGED", function(...) log[#log + 1] = { n = select("#", ...), ... } end)
      T.DB.Set("sound", false)
      H.eq(g.sound, false)
      H.deepEq(log[1], { n = 1, "sound" })
      T.DB.Set("previewSize", 1.25)
      H.eq(g.previewSize, 1.25)
      T.DB.Set("scale", 3)
      H.eq(g.scale, 1.5, "geprueft/begrenzt")
      T.DB.Set("locale", "deDE")
      H.eq(g.locale, "deDE")
      T.DB.Set("locale", "tlh")
      H.eq(g.locale, "auto", "ungueltige Sprache -> auto")
      T.DB.Set("point", { "CENTER", "CENTER", 5, 6 })
      H.deepEq(g.point, { "CENTER", "CENTER", 5, 6 })
      T.DB.Set("point", nil)
      H.eq(g.point, nil)
      T.DB.Set("someNewKey", "x")
      H.eq(g.someNewKey, "x", "unbekannte Schluessel werden gespeichert")
      H.len(log, 8)
      H.deepEq(log[8], { n = 1, "someNewKey" })

      log = {}
      T.DB.SetChar("lastSlot", 15)
      H.eq(c.lastSlot, 15)
      H.deepEq(log[1], { n = 1, "lastSlot" })
      T.DB.SetChar("lastSlot", 1)
      H.eq(c.lastSlot, nil, "kein transmogbarer Slot")
      T.DB.SetChar("lastSlot", nil)
      H.eq(c.lastSlot, nil)
      T.DB.SetChar("customKey", 7)
      H.eq(c.customKey, 7)
      H.len(log, 4)

      -- Ungueltiger Schluessel: ignoriert
      log = {}
      T.DB.Set(nil, 1)
      T.DB.SetChar(nil, 1)
      H.len(log, 0)
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("DB.Set: Fehler eines Beobachters stoeren nicht; Set vor Init legt die DB an", function()
      local T = boot()
      T.Events.On("SETTINGS_CHANGED", function() error("watcher-boom") end)
      local ok = pcall(T.DB.Set, "sound", false)
      H.eq(ok, true)
      H.eq(T.DB.global.sound, false, "Set ohne vorheriges Init")
      H.eq(T.DB.char.migrated, 2)
      H.len(H.takeErrors(), 1)
   end)

   H.test("DB: Persistenz ueber Abmelden und Anmelden", function()
      local T = boot()
      local g, c = T.DB.Init()
      T.DB.Set("locale", "deDE")
      T.DB.Set("toasts", false)
      T.DB.Set("point", { "TOPLEFT", "TOPLEFT", 20, -30 })
      c.favorites[777] = true
      c.filter.typesOff[403] = true
      c.filter.qualities[0] = false
      c.filter.sort = "ILEVEL"
      c.outfits[1] = { name = "Gespeichert", slots = { [0] = 11, [9] = 999999 }, time = 12 }
      T.DB.SetChar("lastSlot", 9)
      local sv = mock.SavedVariables()
      H.truthy(sv.TransmogGlobalDB and sv.TransmogDB, "beide Variablen gespeichert")

      local T2 = boot({ globals = sv })
      local g2, c2 = T2.DB.Init()
      H.deepEq(g2, g)
      H.deepEq(c2, c)
      H.eq(g2.locale, "deDE")
      H.eq(g2.toasts, false)
      H.eq(c2.lastSlot, 9)
      H.eq(c2.outfits[1].name, "Gespeichert")
   end)

   H.test("DB.Init: Zufallsdaten werden zu gueltigen Werten; zweiter Lauf aendert nichts", function()
      local rng = newRng(31337)
      local function junk(depth)
         local k = rng(12)
         if k == 1 then return nil
         elseif k == 2 then return true
         elseif k == 3 then return false
         elseif k == 4 then return rng(1000) - 500
         elseif k == 5 then return (rng(1000) - 500) / 7
         elseif k == 6 then return "text" .. rng(5)
         elseif k == 7 then return ""
         elseif k == 8 then return 0 / 0
         elseif k == 9 then return math.huge
         elseif k == 10 and depth < 3 then
            local t = {}
            for _ = 1, rng(4) - 1 do
               local key = junk(depth + 1)
               if key == nil or key ~= key then key = rng(10) end
               t[key] = junk(depth + 1)
            end
            return t
         elseif k == 11 and depth < 3 then
            local t = {}
            for i = 1, rng(4) do t[i] = junk(depth + 1) end
            return t
         end
         return rng(20)
      end
      local GKEYS = { "version", "locale", "scale", "width", "height", "point", "previewSize", "sound", "toasts",
                      "toastPoint", "tooltipCollected", "tooltipApplied", "allowAnywhere", "lastTab",
                      "noNpcDefault" }
      local CKEYS = { "version", "outfits", "favorites", "filter", "lastSlot", "migrated" }
      local FKEYS = { "qualities", "typesOff", "hideDuplicates", "sort", "favoritesOnly", "newOnly" }
      local LOCALES = { auto = true, enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true,
                        ruRU = true, koKR = true, zhCN = true, zhTW = true }
      local SLOTS = { [0] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
                      [8] = true, [9] = true, [14] = true, [15] = true, [16] = true, [17] = true, [18] = true }
      local T = boot()
      local function isNum(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

      for iter = 1, 150 do
         local g, c = {}, {}
         for _, k in ipairs(GKEYS) do g[k] = junk(0) end
         for _, k in ipairs(CKEYS) do c[k] = junk(0) end
         if rng(3) > 1 then
            c.filter = {}
            for _, k in ipairs(FKEYS) do c.filter[k] = junk(1) end
         end
         if rng(2) == 1 then
            c.outfits = {}
            for i = 1, rng(4) do
               c.outfits[i] = rng(3) == 1 and junk(1) or { name = junk(2), slots = junk(2), time = junk(2) }
            end
         end
         if rng(4) == 1 then g.noNpcDefault, g.allowAnywhere = true, false end   -- gezielt: bewusstes "aus"
         -- Vorher merken: ohne gueltige Marke wird allowAnywhere einmalig an; mit Marke bleibt ein echtes false
         local wasMarked = g.noNpcDefault == true
         local keptOff = wasMarked and g.allowAnywhere == false
         rawset(_G, "TransmogGlobalDB", g)
         rawset(_G, "TransmogDB", c)
         rawset(_G, "transmogOutfits", rng(2) == 1 and junk(0) or nil)
         rawset(_G, "transmogSettings", rng(2) == 1 and junk(0) or nil)
         local ok, rg, rc = pcall(T.DB.Init)
         if not ok then
            H.fail("Init warf bei Zufallsdaten " .. iter .. ": " .. tostring(rg))
            break
         end
         -- Invarianten
         local bad
         local function expect(cond, what)
            if not cond and not bad then bad = what end
         end
         expect(type(rg) == "table" and type(rc) == "table", "Rueckgabe")
         expect(type(rg.locale) == "string" and LOCALES[rg.locale], "locale")
         expect(isNum(rg.scale) and (rg.scale == 0 or (rg.scale >= 0.6 and rg.scale <= 1.5)), "scale")
         expect(isNum(rg.width) and rg.width > 0, "width")
         expect(isNum(rg.height) and rg.height > 0, "height")
         expect(rg.previewSize == 0.8 or rg.previewSize == 1.0 or rg.previewSize == 1.25 or rg.previewSize == 1.5,
            "previewSize")
         for _, k in ipairs({ "sound", "toasts", "tooltipCollected", "tooltipApplied", "allowAnywhere" }) do
            expect(type(rg[k]) == "boolean", k)
         end
         expect(rg.lastTab == "items" or rg.lastTab == "outfits", "lastTab")
         expect(rg.noNpcDefault == true, "Marke noNpcDefault")
         if not wasMarked then expect(rg.allowAnywhere == true, "Uebernahme: allowAnywhere an") end
         if keptOff then expect(rg.allowAnywhere == false, "Wahl 'aus' mit Marke bleibt") end
         expect(rg.point == nil or type(rg.point) == "table", "point")
         expect(isNum(rg.version), "version")
         expect(type(rc.outfits) == "table" and type(rc.favorites) == "table" and type(rc.filter) == "table", "char tables")
         local f = rc.filter
         expect(type(f.qualities) == "table" and type(f.typesOff) == "table", "filter tables")
         expect(type(f.hideDuplicates) == "boolean", "hideDuplicates")
         expect(type(f.favoritesOnly) == "boolean" and type(f.newOnly) == "boolean", "favOnly/newOnly")
         expect(f.sort == "QUALITY" or f.sort == "NAME" or f.sort == "ILEVEL", "sort")
         for q, v in pairs(f.qualities) do expect(type(q) == "number" and q >= 0 and q <= 7 and v == false, "qualities") end
         for t, v in pairs(f.typesOff) do expect(isNum(t) and v == true, "typesOff") end
         for id, v in pairs(rc.favorites) do expect(isNum(id) and id >= 1 and v == true, "favorites") end
         for i, o in ipairs(rc.outfits) do
            expect(type(o) == "table" and type(o.name) == "string" and o.name ~= "" and type(o.slots) == "table"
               and isNum(o.time), "outfit " .. i)
            if type(o) == "table" and type(o.slots) == "table" then
               for s, id in pairs(o.slots) do expect(SLOTS[s] and isNum(id) and id >= 1, "outfit slot") end
            end
         end
         expect(rc.lastSlot == nil or SLOTS[rc.lastSlot], "lastSlot")
         expect(isNum(rc.migrated) and rc.migrated >= 2, "migrated")
         expect(isNum(rc.version), "char version")
         if bad then
            H.fail("Zufallsdaten " .. iter .. ": ungueltig: " .. bad .. " (migrated=" .. tostring(rc.migrated) .. ")")
            break
         end
         -- idempotent: ein zweiter Lauf aendert nichts
         local snapG, snapC = T.Util.CopyTable(rg), T.Util.CopyTable(rc)
         T.DB.Init()
         H.deepEq(TransmogGlobalDB, snapG, "zweiter Lauf global " .. iter)
         H.deepEq(TransmogDB, snapC, "zweiter Lauf char " .. iter)
      end
      rawset(_G, "TransmogGlobalDB", nil)
      rawset(_G, "TransmogDB", nil)
      rawset(_G, "transmogOutfits", nil)
      rawset(_G, "transmogSettings", nil)
   end)

   -- =======================================================================
   H.section("Slots")
   -- =======================================================================

   -- (server, key, client, column, index, hideable, weapon, hand) laut SPEC 5.5
   local SPEC_SLOTS = {
      { 0, "HEAD", 1, 1, 1, true, false, false },
      { 2, "SHOULDER", 3, 1, 2, true, false, false },
      { 14, "BACK", 15, 1, 3, true, false, false },
      { 4, "CHEST", 5, 1, 4, true, false, false },
      { 3, "SHIRT", 4, 1, 5, true, false, false },
      { 18, "TABARD", 19, 1, 6, true, false, false },
      { 8, "WRIST", 9, 1, 7, true, false, false },
      { 9, "HANDS", 10, 2, 1, true, false, false },
      { 5, "WAIST", 6, 2, 2, true, false, false },
      { 6, "LEGS", 7, 2, 3, true, false, false },
      { 7, "FEET", 8, 2, 4, true, false, false },
      { 15, "MAINHAND", 16, 2, 5, false, true, true },
      { 16, "OFFHAND", 17, 2, 6, false, true, true },
      { 17, "RANGED", 18, 2, 7, false, true, false },
   }
   local INV_NAMES = {
      HEAD = "HeadSlot", SHOULDER = "ShoulderSlot", BACK = "BackSlot", CHEST = "ChestSlot",
      SHIRT = "ShirtSlot", TABARD = "TabardSlot", WRIST = "WristSlot", HANDS = "HandsSlot",
      WAIST = "WaistSlot", LEGS = "LegsSlot", FEET = "FeetSlot", MAINHAND = "MainHandSlot",
      OFFHAND = "SecondaryHandSlot", RANGED = "RangedSlot",
   }
   local GLOBAL_NAMES = {
      HEAD = "HEADSLOT", SHOULDER = "SHOULDERSLOT", BACK = "BACKSLOT", CHEST = "CHESTSLOT",
      SHIRT = "SHIRTSLOT", TABARD = "TABARDSLOT", WRIST = "WRISTSLOT", HANDS = "HANDSSLOT",
      WAIST = "WAISTSLOT", LEGS = "LEGSSLOT", FEET = "FEETSLOT", MAINHAND = "MAINHANDSLOT",
      OFFHAND = "SECONDARYHANDSLOT", RANGED = "RANGEDSLOT",
   }

   H.test("Slots.LIST: 14 Definitionen in Anzeigereihenfolge mit allen Feldern", function()
      local T = boot()
      local S = T.Slots
      H.eq(S.COUNT, 14)
      H.len(S.LIST, 14)
      for i, w in ipairs(SPEC_SLOTS) do
         local d = S.LIST[i]
         H.truthy(d, "Eintrag " .. i)
         if d then
            H.eq(d.key, w[2], "key " .. i)
            H.eq(d.server, w[1], d.key .. " server")
            H.eq(d.client, w[3], d.key .. " client = server + 1")
            H.eq(d.client, d.server + 1)
            H.eq(d.invName, INV_NAMES[w[2]], d.key .. " invName")
            H.eq(d.globalName, GLOBAL_NAMES[w[2]], d.key .. " globalName")
            H.eq(d.column, w[4], d.key .. " column")
            H.eq(d.index, w[5], d.key .. " index")
            H.eq(d.hideable, w[6], d.key .. " hideable")
            H.eq(d.weapon, w[7], d.key .. " weapon")
            H.eq(d.hand, w[8], d.key .. " hand")
            H.eq(S.BY_SERVER[w[1]], d)
            H.eq(S.BY_KEY[w[2]], d)
            H.eq(S.BY_CLIENT[w[3]], d)
         end
      end
      H.eq(S.BY_SERVER[1], nil, "Hals nicht transmogbar")
      H.eq(S.BY_SERVER[10], nil)
      H.eq(S.BY_SERVER[11], nil)
      H.eq(S.BY_SERVER[12], nil)
      H.eq(S.BY_SERVER[13], nil)
      H.eq(S.BY_CLIENT[2], nil)
      H.eq(T.Util.Count(S.BY_SERVER), 14)
      H.eq(T.Util.Count(S.BY_KEY), 14)
      H.eq(T.Util.Count(S.BY_CLIENT), 14)
      -- Spalte/Zeile ergeben jeden Platz genau einmal
      local seen = {}
      for _, d in ipairs(S.LIST) do
         local k = d.column .. ":" .. d.index
         H.falsy(seen[k], "doppelter Platz " .. k)
         seen[k] = true
      end
   end)

   H.test("Slots.IsHideable: genau 0,2,3,4,5,6,7,8,9,14,18", function()
      local T = boot()
      local want = { [0] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
                     [8] = true, [9] = true, [14] = true, [18] = true }
      for s = -1, 25 do
         H.eq(T.Slots.IsHideable(s), want[s] == true, "Slot " .. s)
      end
      H.eq(T.Slots.IsHideable(nil), false)
      H.eq(T.Slots.IsHideable("0"), false)
   end)

   H.test("Slots.Label: Blizzard-Global, sonst englischer Ersatz, unbekannt -> ?", function()
      local T = boot({ world = { locale = "deDE" } })
      H.eq(T.Slots.Label(0), HEADSLOT)
      H.eq(T.Slots.Label(0), "Kopf")
      H.eq(T.Slots.Label(8), WRISTSLOT)
      H.eq(T.Slots.Label(16), SECONDARYHANDSLOT)
      H.eq(T.Slots.Label(1), "?")
      H.eq(T.Slots.Label(nil), "?")
      H.eq(T.Slots.Label(99), "?")
      -- ohne Globals: englische Namen
      local T2 = boot({ world = { globalStrings = false } })
      H.eq(rawget(_G, "HEADSLOT"), nil)
      local want = {
         [0] = "Head", [2] = "Shoulders", [14] = "Back", [4] = "Chest", [3] = "Shirt", [18] = "Tabard",
         [8] = "Wrist", [9] = "Hands", [5] = "Waist", [6] = "Legs", [7] = "Feet",
         [15] = "Main Hand", [16] = "Off Hand", [17] = "Ranged",
      }
      for s, name in pairs(want) do
         H.eq(T2.Slots.Label(s), name, "Slot " .. s)
      end
   end)

   H.test("Slots.EmptyTexture: aus GetInventorySlotInfo; Ersatz je Slot stimmt mit dem Spiel ueberein", function()
      local T = boot()
      local S = T.Slots
      local fromGame = {}
      for _, d in ipairs(S.LIST) do
         local _, texture = GetInventorySlotInfo(d.invName)
         fromGame[d.server] = texture
         H.eq(S.EmptyTexture(d.server), texture, d.key)
         H.matches(texture, "^Interface\\PaperDoll\\UI%-PaperDoll%-Slot%-", d.key)
      end
      -- unbekannter Slot: allgemeiner Ersatz
      local fallback = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest"
      H.eq(S.EmptyTexture(1), fallback)
      H.eq(S.EmptyTexture(nil), fallback)
      H.eq(S.EmptyTexture(99), fallback)

      -- API wirft/liefert nichts: Ersatz je Slot, gleich der echten Textur
      local real = GetInventorySlotInfo
      GetInventorySlotInfo = function() error("kein API") end
      S.Init()
      for _, d in ipairs(S.LIST) do
         H.eq(S.EmptyTexture(d.server), fromGame[d.server], d.key .. " (Ersatz)")
      end
      GetInventorySlotInfo = function() return nil end
      S.Init()
      for _, d in ipairs(S.LIST) do
         H.eq(S.EmptyTexture(d.server), fromGame[d.server], d.key .. " (nil)")
      end
      GetInventorySlotInfo = real
      S.Init()
      H.eq(S.EmptyTexture(0), fromGame[0])
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Slots.EmptyTexture: Ergebnis wird gemerkt, Init verwirft es", function()
      local T = boot()
      local S = T.Slots
      local calls = 0
      local real = GetInventorySlotInfo
      GetInventorySlotInfo = function(name)
         calls = calls + 1
         return real(name)
      end
      S.EmptyTexture(0)
      S.EmptyTexture(0)
      S.EmptyTexture(0)
      H.eq(calls, 1, "einmal je Slot")
      S.Init()
      S.EmptyTexture(0)
      H.eq(calls, 2, "nach Init erneut")
      GetInventorySlotInfo = real
   end)

   H.test("Slots.EquippedLink: Inventar-ID = Server-Slot + 1", function()
      local T = boot({ world = { equipment = { [1] = 12345, [16] = 5555, [19] = 777 } },
                       items = { [12345] = { name = "Helm", quality = 4 } } })
      local S = T.Slots
      H.contains(S.EquippedLink(0) or "", "item:12345")
      H.contains(S.EquippedLink(15) or "", "item:5555")
      H.contains(S.EquippedLink(18) or "", "item:777")
      H.eq(S.EquippedLink(2), nil, "leer")
      H.eq(S.EquippedLink(1), nil, "kein transmogbarer Slot")
      H.eq(S.EquippedLink(nil), nil)
      H.eq(S.EquippedLink(99), nil)
      H.eq(T.Util.ItemIdFromLink(S.EquippedLink(0)), 12345)
   end)

   H.test("Slots.Next: Anzeigereihenfolge, zyklisch, vor/zurueck, unbekannter Slot", function()
      local T = boot()
      local S = T.Slots
      local order = {}
      for _, w in ipairs(SPEC_SLOTS) do order[#order + 1] = w[1] end
      -- vorwaerts durch alle 14 und zurueck zum Start
      local s = order[1]
      for i = 1, 14 do
         H.eq(s, order[i], "Schritt " .. i)
         s = S.Next(s, 1)
      end
      H.eq(s, order[1], "zyklisch")
      -- rueckwaerts
      s = order[1]
      for i = 14, 1, -1 do
         s = S.Next(s, -1)
         H.eq(s, order[i], "rueckwaerts " .. i)
      end
      -- dir fehlt oder ist groesser als 1: Vorwaertsrichtung; nur das Vorzeichen zaehlt
      H.eq(S.Next(0), 2)
      H.eq(S.Next(0, nil), 2)
      H.eq(S.Next(0, 5), 2)
      H.eq(S.Next(0, -5), 17, "vor dem ersten kommt der letzte")
      H.eq(S.Next(17, 1), 0, "nach dem letzten kommt der erste")
      -- Spaltenwechsel: Handgelenk (Ende Spalte 1) -> Haende (Beginn Spalte 2)
      H.eq(S.Next(8, 1), 9)
      H.eq(S.Next(9, -1), 8)
      -- unbekannt: erster bzw. letzter
      H.eq(S.Next(1, 1), 0)
      H.eq(S.Next(1, -1), 17)
      H.eq(S.Next(nil, 1), 0)
      H.eq(S.Next(nil, -1), 17)
      H.eq(S.Next("x", 1), 0)
      -- Hin und zurueck
      for _, w in ipairs(SPEC_SLOTS) do
         H.eq(S.Next(S.Next(w[1], 1), -1), w[1])
         H.eq(S.Next(S.Next(w[1], -1), 1), w[1])
      end
   end)

   H.test("Slots.Init: laeuft ohne Fehler, auch mehrfach", function()
      local T = boot()
      T.Slots.Init()
      T.Slots.Init()
      H.eq(T.Slots.COUNT, 14)
      H.eq(#H.takeErrors(), 0)
   end)

   -- =======================================================================
   H.section("Zusammenspiel")
   -- =======================================================================

   H.test("Laden: alle vorhandenen TOC-Dateien laufen fehlerfrei; keine fremden Globals", function()
      local T = H.boot({ login = false })
      H.truthy(T, "Transmog")
      for _, mod in ipairs({ "Locale", "Util", "Events", "DB", "Slots" }) do
         H.eq(type(T[mod]), "table", "T." .. mod)
      end
      H.eq(type(T.L), "table")
      H.eq(#H.takeErrors(), 0)
      -- Nichts blockiert die Basis: Locale -> Events -> DB funktionieren zusammen
      T.DB.Init()
      T.Locale.Set(T.DB.global.locale)
      H.eq(T.Locale.Current(), "enUS")
   end)

   H.test("Zusammenspiel: Locale.Set aus DB.global.locale wechselt Zahlenformat und Slotnamen", function()
      local T = boot({ world = { locale = "deDE" }, globals = { TransmogGlobalDB = { locale = "deDE" } } })
      T.Locale.Add("deDE", { THOUSANDS_SEP = "." })
      T.DB.Init()
      T.Locale.Set(T.DB.global.locale)
      H.eq(T.Locale.Current(), "deDE")
      H.eq(T.Util.FormatNumber(1234567), "1.234.567")
      H.eq(T.Slots.Label(0), HEADSLOT)
      -- Auswahl "auto" folgt wieder dem Client
      T.DB.Set("locale", "enUS")
      T.Locale.Set(T.DB.global.locale)
      H.eq(T.Util.FormatNumber(1234567), "1,234,567")
   end)
end
