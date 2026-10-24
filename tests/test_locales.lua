-- tests/test_locales.lua
-- ---------------------------------------------------------------------------
-- Tests der Sprachdateien (Locales\<code>.lua) und des Sprachwechsels.
--
--     luajit tests/run.lua locales
--
-- Geprueft wird (SPEC 4):
--   * alle sieben Sprachdateien existieren und stehen in der TOC hinter den
--     enUS_*-Dateien, in der Reihenfolge von Locale.List()
--   * jede Sprache hat GENAU die Schluessel von enUS (nichts fehlt, nichts ist uebrig)
--   * Platzhalter (%s, %d) stimmen in Anzahl und Reihenfolge, string.format laeuft
--   * Werte sind gueltiges UTF-8 ohne Steuerzeichen, ohne Leerraum am Rand
--   * nichts ist unuebersetzt stehen geblieben (ausser Namen/Lehnwoertern auf der Liste)
--   * Typografie je Sprache (Leerzeichen vor Satzzeichen, chinesische Zeichensetzung)
--   * Locale.Set schaltet ALLE Texte um (Stichproben je Sprache, Tausendertrenner)
--   * Rueckfall: esMX -> esES, enGB -> enUS, unbekannt -> enUS, "auto" folgt dem Client
--   * die Tabelle Transmog.L bleibt dieselbe, Tastenbelegungs-Texte folgen der Sprache
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   -- Sprachen in der Reihenfolge von Locale.List() (ohne enUS)
   local CODES = { "deDE", "frFR", "esES", "ruRU", "koKR", "zhCN", "zhTW" }

   -- Stichproben: Schluessel -> erwarteter Text je Sprache (woertlich aus den Dateien)
   local SPOT = {
      enUS = { WIN_APPLY = "Apply", WIN_CLOSE = "Close", OUTFITS_DELETE = "Delete", THOUSANDS_SEP = "," },
      deDE = { WIN_APPLY = "Anwenden", WIN_CLOSE = "Schlie\195\159en", OUTFITS_DELETE = "L\195\182schen", THOUSANDS_SEP = "." },
      frFR = { WIN_APPLY = "Appliquer", WIN_CLOSE = "Fermer", OUTFITS_DELETE = "Supprimer", THOUSANDS_SEP = " " },
      esES = { WIN_APPLY = "Aplicar", WIN_CLOSE = "Cerrar", OUTFITS_DELETE = "Eliminar", THOUSANDS_SEP = "." },
      ruRU = { WIN_APPLY = "\208\159\209\128\208\184\208\188\208\181\208\189\208\184\209\130\209\140",
               WIN_CLOSE = "\208\151\208\176\208\186\209\128\209\139\209\130\209\140",
               OUTFITS_DELETE = "\208\163\208\180\208\176\208\187\208\184\209\130\209\140", THOUSANDS_SEP = " " },
      koKR = { WIN_APPLY = "\236\160\129\236\154\169", WIN_CLOSE = "\235\139\171\234\184\176",
               OUTFITS_DELETE = "\236\130\173\236\160\156", THOUSANDS_SEP = "," },
      zhCN = { WIN_APPLY = "\229\186\148\231\148\168", WIN_CLOSE = "\229\133\179\233\151\173",
               OUTFITS_DELETE = "\229\136\160\233\153\164", THOUSANDS_SEP = "," },
      zhTW = { WIN_APPLY = "\229\165\151\231\148\168", WIN_CLOSE = "\233\151\156\233\150\137",
               OUTFITS_DELETE = "\229\136\170\233\153\164", THOUSANDS_SEP = "," },
   }

   -- Erwartete Ausgabe von Util.FormatNumber(1234567) je Sprache
   local NUMBER = {
      enUS = "1,234,567", deDE = "1.234.567", frFR = "1 234 567", esES = "1.234.567",
      ruRU = "1 234 567", koKR = "1,234,567", zhCN = "1,234,567", zhTW = "1,234,567",
   }

   -- Texte, die in der Zielsprache bewusst wie im Englischen lauten (Namen, Lehnwoerter,
   -- Zahlformate). Alles andere, was gleich ist, gilt als unuebersetzt.
   local SAME_AS_ENGLISH = {
      deDE = { FILTER_BUTTON = true, GRID_ORIGINAL = true, OPT_SCALE_AUTO = true, OUTFIT_DEFAULT_NAME = true,
               SORT_NAME = true, WIN_TAB_OUTFITS = true },
      frFR = { FILTER_TYPE_TITLE = true, GRID_ORIGINAL = true, GRID_PAGE = true, OPT_SCALE_AUTO = true,
               OUTFITS_PAGE = true, WIN_OPTIONS = true },
      esES = { BOOT_NO = true, GRID_ORIGINAL = true, OPT_SCALE_AUTO = true, OPT_SECTION_GENERAL = true },
      ruRU = {}, koKR = {}, zhCN = {}, zhTW = {},
   }

   -- -----------------------------------------------------------------------
   -- Hilfen
   -- -----------------------------------------------------------------------

   local function readFile(path)
      local f = io.open(path, "rb")
      if not f then return nil end
      local s = f:read("*a")
      f:close()
      return s
   end

   local function sortedKeys(t)
      local out = {}
      for k in pairs(t) do out[#out + 1] = k end
      table.sort(out)
      return out
   end

   -- Wohlgeformtes UTF-8 (ohne Ueberlange, ohne Ersatzzeichen)
   local function validUtf8(s)
      local i, n = 1, #s
      while i <= n do
         local b = s:byte(i)
         local len
         if b < 0x80 then
            len = 1
         elseif b >= 0xC2 and b <= 0xDF then
            len = 2
         elseif b >= 0xE0 and b <= 0xEF then
            len = 3
         elseif b >= 0xF0 and b <= 0xF4 then
            len = 4
         else
            return false
         end
         for j = 1, len - 1 do
            local c = s:byte(i + j)
            if not c or c < 0x80 or c > 0xBF then return false end
         end
         if b == 0xE0 and s:byte(i + 1) < 0xA0 then return false end
         if b == 0xED and s:byte(i + 1) > 0x9F then return false end
         i = i + len
      end
      return true
   end

   -- Platzhalterfolge eines Formattexts als Liste ("s", "d", ...) oder nil, wenn etwas anderes
   -- als %s, %d oder %% vorkommt.
   local function placeholders(text)
      local out = {}
      local i = 1
      while true do
         local p = text:find("%", i, true)
         if not p then break end
         local c = text:sub(p + 1, p + 1)
         if c == "s" or c == "d" then
            out[#out + 1] = c
         elseif c ~= "%" then
            return nil, "unzulaessiger Platzhalter %" .. c
         end
         i = p + 2
      end
      return out
   end

   -- Laedt eine Sprachdatei mit einer Attrappe fuer Transmog.Locale.Add und liefert die Texte,
   -- die sie registriert (Schluessel -> Text), sowie die Liste aller Add-Aufrufe.
   local function loadLocaleFile(rel, into)
      local chunk, err = loadfile(H.root .. "/" .. rel)
      H.assert(chunk, "Sprachdatei nicht ladbar: " .. tostring(err))
      local seenCode
      local stub = { Locale = { Add = function(code, tbl)
         seenCode = code
         into[code] = into[code] or {}
         for k, v in pairs(tbl) do into[code][k] = v end
      end } }
      setfenv(chunk, { Transmog = stub })
      chunk()
      return seenCode
   end

   -- Einlesen der TOC: Dateien in Reihenfolge
   local function tocFiles()
      local text = readFile(H.root .. "/Transmog.toc")
      H.assert(text, "Transmog.toc fehlt")
      local files = {}
      for line in (text .. "\n"):gmatch("(.-)\r?\n") do
         if line:match("%S") and not line:match("^#") then
            files[#files + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""))
         end
      end
      return files
   end

   -- Alle Texte je Sprache aus den Dateien: data[code][key]
   local dataCache
   local function allData()
      if dataCache then return dataCache end
      local data = {}
      local files = tocFiles()
      for _, f in ipairs(files) do
         local rel = f:gsub("\\", "/")
         if rel:match("^Locales/enUS_%w+%.lua$") or rel:match("^Locales/%a%a%a%a%.lua$") then
            loadLocaleFile(rel, data)
         end
      end
      dataCache = data
      return data
   end

   -- Fehlermeldung mit den ersten Eintraegen einer Liste
   local function listText(list, max)
      max = max or 8
      local out = {}
      for i = 1, math.min(#list, max) do out[#out + 1] = list[i] end
      if #list > max then out[#out + 1] = "... (+" .. (#list - max) .. ")" end
      return table.concat(out, "; ")
   end

   -- =======================================================================
   H.section("Sprachdateien")
   -- =======================================================================

   H.test("TOC: alle sieben Sprachdateien nach den enUS-Dateien, in der Reihenfolge von Locale.List()", function()
      local files = tocFiles()
      local pos = {}
      for i, f in ipairs(files) do pos[f] = i end
      local lastEnUS, previous = 0, 0
      for i, f in ipairs(files) do
         if f:match("^Locales\\enUS_%w+%.lua$") then lastEnUS = i end
      end
      H.truthy(lastEnUS > 0, "enUS-Dateien in der TOC")
      for _, code in ipairs(CODES) do
         local name = "Locales\\" .. code .. ".lua"
         H.truthy(pos[name], name .. " fehlt in der TOC")
         H.truthy(readFile(H.root .. "/Locales/" .. code .. ".lua"), "Datei fehlt: Locales/" .. code .. ".lua")
         if pos[name] then
            H.truthy(pos[name] > lastEnUS, name .. " steht vor einer enUS-Datei")
            H.truthy(pos[name] > previous, name .. " steht nicht in der Reihenfolge von Locale.List()")
            previous = pos[name]
         end
      end
      -- Locale.List() nennt dieselben Codes in derselben Reihenfolge
      local T = H.boot({ upTo = "Locales\\Locale.lua", login = false })
      local list = T.Locale.List()
      H.eq(#list, #CODES + 1)
      H.eq(list[1].code, "enUS")
      for i, code in ipairs(CODES) do H.eq(list[i + 1].code, code) end
   end)

   H.test("Dateien: UTF-8 ohne BOM, LF, ohne Tabs und Leerraum am Zeilenende", function()
      for _, code in ipairs(CODES) do
         local rel = "Locales/" .. code .. ".lua"
         local text = readFile(H.root .. "/" .. rel)
         H.assert(text, rel .. " fehlt")
         H.falsy(text:sub(1, 3) == "\239\187\191", rel .. ": BOM")
         H.falsy(text:find("\r", 1, true), rel .. ": CR")
         H.falsy(text:find("\t", 1, true), rel .. ": Tab")
         H.falsy(text:find("[ ]+\n"), rel .. ": Leerraum am Zeilenende")
         H.truthy(validUtf8(text), rel .. ": kein gueltiges UTF-8")
         H.eq(text:sub(-1), "\n", rel .. ": Zeilenende am Dateiende")
      end
   end)

   H.test("Jede Sprachdatei registriert genau ihren eigenen Code", function()
      local data = {}
      for _, code in ipairs(CODES) do
         local seen = loadLocaleFile("Locales/" .. code .. ".lua", data)
         H.eq(seen, code, "Locales/" .. code .. ".lua registriert " .. tostring(seen))
      end
   end)

   -- =======================================================================
   H.section("Schluessel, Platzhalter, Werte")
   -- =======================================================================

   H.test("Schluesselmenge: jede Sprache hat genau die Schluessel von enUS", function()
      local data = allData()
      local en = data.enUS
      H.truthy(en, "enUS-Texte geladen")
      local count = 0
      for _ in pairs(en) do count = count + 1 end
      H.truthy(count >= 250, "Anzahl enUS-Schluessel: " .. count)
      for _, code in ipairs(CODES) do
         local loc = data[code]
         H.assert(loc, code .. ": keine Texte registriert")
         local missing, extra = {}, {}
         for _, k in ipairs(sortedKeys(en)) do
            if loc[k] == nil then missing[#missing + 1] = k end
         end
         for _, k in ipairs(sortedKeys(loc)) do
            if en[k] == nil then extra[#extra + 1] = k end
         end
         H.eq(#missing, 0, code .. ": fehlende Schluessel: " .. listText(missing))
         H.eq(#extra, 0, code .. ": ueberzaehlige Schluessel: " .. listText(extra))
      end
   end)

   H.test("Platzhalter: gleiche Anzahl und Reihenfolge wie enUS, string.format laeuft", function()
      local data = allData()
      local en = data.enUS
      for _, code in ipairs(CODES) do
         for _, k in ipairs(sortedKeys(en)) do
            local want, werr = placeholders(en[k])
            H.assert(want, "enUS " .. k .. ": " .. tostring(werr))
            local text = data[code][k]
            if type(text) == "string" then
               local got, gerr = placeholders(text)
               H.truthy(got, code .. " " .. k .. ": " .. tostring(gerr))
               if got then
                  H.eq(table.concat(got, ","), table.concat(want, ","), code .. " " .. k .. ": Platzhalter")
                  local args = {}
                  for i, p in ipairs(got) do args[i] = (p == "d") and 7 or "x" end
                  local ok, res = pcall(string.format, text, unpack(args))
                  H.truthy(ok, code .. " " .. k .. ": string.format: " .. tostring(res))
               end
            end
         end
      end
   end)

   H.test("Werte: nicht leer, gueltiges UTF-8, keine Steuerzeichen, kein Leerraum am Rand", function()
      local data = allData()
      for _, code in ipairs(CODES) do
         local bad = {}
         for _, k in ipairs(sortedKeys(data[code])) do
            local v = data[code][k]
            if type(v) ~= "string" or v == "" then
               bad[#bad + 1] = k .. " (kein Text)"
            else
               if not validUtf8(v) then bad[#bad + 1] = k .. " (UTF-8)" end
               if v:find("[%z\1-\31]") then bad[#bad + 1] = k .. " (Steuerzeichen)" end
               if k ~= "THOUSANDS_SEP" and (v:find("^%s") or v:find("%s$")) then bad[#bad + 1] = k .. " (Leerraum am Rand)" end
               if v:find("  ", 1, true) then bad[#bad + 1] = k .. " (doppeltes Leerzeichen)" end
            end
         end
         H.eq(#bad, 0, code .. ": " .. listText(bad))
      end
   end)

   H.test("THOUSANDS_SEP: nur ein Trennzeichen, je Sprache wie vorgesehen", function()
      local data = allData()
      for code, spot in pairs(SPOT) do
         H.eq(data[code].THOUSANDS_SEP, spot.THOUSANDS_SEP, code)
      end
   end)

   H.test("Nichts unuebersetzt: gleich lautende Texte nur auf der Liste der Lehnwoerter", function()
      local data = allData()
      local en = data.enUS
      for _, code in ipairs(CODES) do
         local allowed = SAME_AS_ENGLISH[code]
         local bad = {}
         for _, k in ipairs(sortedKeys(en)) do
            local v = data[code][k]
            local plain = en[k]:gsub("%%[sd]", "")
            -- nur Zahlen/Satzzeichen (z. B. "%d / %d", "...", "?"): nichts zu uebersetzen
            if v == en[k] and plain:find("%a") and not allowed[k] and k ~= "THOUSANDS_SEP" then
               bad[#bad + 1] = k
            end
         end
         H.eq(#bad, 0, code .. ": unuebersetzt: " .. listText(bad))
      end
   end)

   H.test("Typografie: Leerzeichen vor Satzzeichen nur im Franzoesischen, chinesische Zeichensetzung", function()
      local data = allData()
      for _, code in ipairs(CODES) do
         local bad = {}
         for _, k in ipairs(sortedKeys(data[code])) do
            local v = data[code][k]
            if code == "frFR" then
               -- franzoesische Regel: Leerzeichen vor : ; ! ?
               if v:find("%S[:;!?]%s") or v:find("%S[:;!?]$") then bad[#bad + 1] = k .. " (kein Leerzeichen vor Satzzeichen)" end
            else
               if v:find("%s[:;!?]") and v ~= "?" then bad[#bad + 1] = k .. " (Leerzeichen vor Satzzeichen)" end
            end
            if v:find("%s[,.]%s") or v:find("%s,") then bad[#bad + 1] = k .. " (Leerzeichen vor Komma/Punkt)" end
            if code == "zhCN" or code == "zhTW" then
               if not k:find("^BOOT_HELP") then
                  if v:find("[,;:]%s") then bad[#bad + 1] = k .. " (ASCII-Satzzeichen)" end
                  if v:find("[^.]%.$") then bad[#bad + 1] = k .. " (ASCII-Punkt am Satzende)" end
               end
            end
         end
         H.eq(#bad, 0, code .. ": " .. listText(bad))
      end
   end)

   H.test("Dialogtexte mit Namen: Platzhalter %s steht in Anfuehrungszeichen der Sprache", function()
      local data = allData()
      local keys = { "OUTFITS_SAVED", "OUTFITS_OVERWRITE_TEXT", "OUTFITS_OVERWRITTEN", "OUTFITS_RENAME_TEXT",
                     "OUTFITS_RENAMED", "OUTFITS_DELETE_TEXT", "OUTFITS_DELETED" }
      local quotes = {
         deDE = { "\"%s\"" }, frFR = { "\"%s\"" }, esES = { "\"%s\"" }, ruRU = { "\"%s\"" }, koKR = { "\"%s\"" },
         zhCN = { "\226\128\156%s\226\128\157" },          -- U+201C ... U+201D
         zhTW = { "\227\128\140%s\227\128\141" },          -- U+300C ... U+300D
      }
      for _, code in ipairs(CODES) do
         for _, k in ipairs(keys) do
            local v = data[code][k]
            local ok = false
            for _, q in ipairs(quotes[code]) do
               if v:find(q, 1, true) then ok = true end
            end
            H.truthy(ok, code .. " " .. k .. ": Name nicht in Anfuehrungszeichen: " .. tostring(v))
         end
      end
   end)

   H.test("Laengen: Texte mit Platzbegrenzung (Kommentare in enUS_Outfits/_Options/_Features) bleiben im Rahmen", function()
      local data = allData()
      -- Anzeigebreite grob in Zeichen: ASCII 1, Latin/Kyrillisch 1.1, CJK/Hangul 1.8
      local function width(s)
         local w = 0
         s = s:gsub("%%[sd]", "NNN")
         local i, n = 1, #s
         while i <= n do
            local b = s:byte(i)
            local len = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
            w = w + ((len == 1 and 1) or (len == 2 and 1.1) or 1.8)
            i = i + len
         end
         return w
      end
      local LIMIT = {
         OUTFITS_LOAD = 16, OUTFITS_OVERWRITE = 16, OUTFITS_RENAME = 16, OUTFITS_DELETE = 16,
         OUTFITS_SAVE = 40, OUTFITS_PIECES = 22, OUTFITS_PIECES_PARTIAL = 22,
         OUTFITS_SAVED = 45, OUTFITS_LOADED = 45, OUTFITS_LOADED_PARTIAL = 45, OUTFITS_LOADED_NONE = 45,
         OUTFITS_LOADED_PENDING = 45, OUTFITS_LOADED_WAIT = 45, OUTFITS_LOADED_EMPTY = 45,
         OUTFITS_OVERWRITTEN = 45, OUTFITS_RENAMED = 45, OUTFITS_DELETED = 45,
         OUTFITS_EMPTY_TITLE = 40, OUTFITS_EMPTY_TEXT = 400, OUTFITS_PAGE = 20,
         OPT_TITLE = 40, OPT_SECTION_LANGUAGE = 50, OPT_SECTION_WINDOW = 50, OPT_SECTION_GENERAL = 50,
         OPT_LANG_AUTO = 50, OPT_LANG_NOTE = 120, OPT_SCALE_AUTO = 11,
         OPT_PREVIEW_SMALL = 14, OPT_PREVIEW_MEDIUM = 14, OPT_PREVIEW_LARGE = 14, OPT_PREVIEW_XLARGE = 14,
         OPT_RESET_WINDOW = 60, OPT_SOUND = 55, OPT_TOASTS = 55, OPT_TOOLTIP_COLLECTED = 55,
         OPT_TOOLTIP_APPLIED = 55, OPT_ALLOW_ANYWHERE = 55, OPT_MOVE_TOASTS = 28, OPT_TEST_TOAST = 28,
         TOAST_TITLE = 30, TOAST_BURST_TITLE = 30, TOAST_BURST_COUNT = 30, TOAST_ANCHOR_LABEL = 16,
      }
      for _, code in ipairs(CODES) do
         local bad = {}
         for _, k in ipairs(sortedKeys(LIMIT)) do
            local w = width(data[code][k])
            if w > LIMIT[k] then bad[#bad + 1] = string.format("%s=%.1f>%d", k, w, LIMIT[k]) end
         end
         H.eq(#bad, 0, code .. ": zu lang: " .. listText(bad))
      end
   end)

   -- Seit 2.1 ist "Anwenden auch ohne Transmogrifizierer" an. Der Tooltip erklaert beide Zustaende: den Abstand
   -- prueft der Server nicht, an = ueberall anwenden (Vorgabe), aus = /transmog zeigt nur den Vorschau-Modus und
   -- angewendet wird nur beim Transmogrifizierer. Der Name des Vorschau-Modus muss wie in der gelben Hinweisleiste
   -- (MSG_NO_VENDOR) lauten.
   H.test("OPT_ALLOW_ANYWHERE_TIP: in allen acht Sprachen erklaert er beide Zustaende und nennt den Vorschau-Modus", function()
      local data = allData()
      local MODE = {
         enUS = "preview mode", deDE = "vorschau-modus", frFR = "mode aper\195\167u", esES = "modo de vista previa",
         ruRU = "\208\181\208\182\208\184\208\188 \208\191\209\128\208\181\208\180\208\191\209\128\208\190\209\129\208\188\208\190\209\130\209\128\208\176",   -- (ohne Anfangsbuchstaben: lower() kennt kein Kyrillisch)
         koKR = "\235\175\184\235\166\172\235\179\180\234\184\176 \235\170\168\235\147\156",
         zhCN = "\233\162\132\232\167\136\230\168\161\229\188\143",
         zhTW = "\233\160\144\232\166\189\230\168\161\229\188\143",
      }
      local DEFAULT = {      -- das Wort fuer "Vorgabe/Standard" steht beim Zustand "an"
         enUS = "default", deDE = "vorgabe", frFR = "d\195\169faut", esES = "defecto", ruRU = "\209\131\208\188\208\190\208\187\209\135\208\176\208\189\208\184\209\142",
         koKR = "\234\184\176\235\179\184\234\176\146", zhCN = "\233\187\152\232\174\164", zhTW = "\233\160\144\232\168\173",
      }
      local en = data.enUS.OPT_ALLOW_ANYWHERE_TIP
      H.truthy(en and en:find("does not check your distance", 1, true), "enUS nennt, dass der Server den Abstand nicht prueft")
      for _, code in ipairs({ "enUS", unpack(CODES) }) do
         local tip = data[code].OPT_ALLOW_ANYWHERE_TIP
         H.eq(type(tip), "string", code)
         H.truthy(tip and #tip > 40, code .. ": Text vorhanden")
         if tip then
            H.truthy(tip:find("/transmog", 1, true), code .. ": nennt den Befehl /transmog")
            H.falsy(tip:find("%%"), code .. ": kein Platzhalter")
            H.truthy(tip:lower():find(MODE[code], 1, true), code .. ": nennt den Vorschau-Modus (" .. MODE[code] .. ")")
            H.truthy(data[code].MSG_NO_VENDOR:lower():find(MODE[code], 1, true),
               code .. ": MSG_NO_VENDOR nennt ihn genauso")
            H.truthy(tip:lower():find(DEFAULT[code], 1, true), code .. ": sagt, dass 'an' die Vorgabe ist (" .. DEFAULT[code] .. ")")
            H.truthy(#tip < 520, code .. ": nicht zu lang (" .. #tip .. ")")
            if code ~= "enUS" then
               H.neq(tip, en, code .. ": uebersetzt")
            end
         end
      end
   end)

   -- =======================================================================
   H.section("Sprachwechsel")
   -- =======================================================================

   -- Startet das ganze Addon (TOC) bis nach PLAYER_LOGIN, Client-Sprache wie angegeben.
   local function bootAddon(clientLocale, saved)
      local T = H.boot({ world = { locale = clientLocale or "enUS" }, globals = saved })
      H.assert(type(T) == "table", "Transmog wurde nicht geladen")
      return T
   end

   H.test("Locale.Set: alle Texte jeder Sprache stehen in L (Stichproben, Vollstaendigkeit, Zahlenformat)", function()
      local data = allData()
      local T = bootAddon("enUS")
      local L = T.L
      for _, code in ipairs({ "enUS", unpack(CODES) }) do
         H.eq(T.Locale.Set(code), code, "Set liefert den aufgeloesten Code")
         H.eq(T.Locale.Current(), code)
         -- Stichproben
         for key, want in pairs(SPOT[code]) do
            H.eq(rawget(L, key), want, code .. " " .. key)
         end
         -- Vollstaendig: jeder Schluessel entspricht der Datei
         local diff = {}
         for _, k in ipairs(sortedKeys(data[code])) do
            if rawget(L, k) ~= data[code][k] then diff[#diff + 1] = k end
         end
         H.eq(#diff, 0, code .. ": L weicht von der Datei ab: " .. listText(diff))
         -- Zahlenformat folgt der Sprache
         H.eq(T.Util.FormatNumber(1234567), NUMBER[code], code .. " FormatNumber")
         -- nie ein Schluessel als Text
         H.falsy(next(L.__missing), code .. ": fehlende Schluessel: " .. tostring(next(L.__missing)))
      end
   end)

   H.test("Locale.Set: Sprachen unterscheiden sich (keine zwei Sprachen teilen sich die Hauptknoepfe)", function()
      local T = bootAddon("enUS")
      local seen = {}
      for _, code in ipairs({ "enUS", unpack(CODES) }) do
         T.Locale.Set(code)
         local apply = T.L.WIN_APPLY
         H.falsy(seen[apply], code .. " und " .. tostring(seen[apply]) .. " haben denselben Text fuer WIN_APPLY")
         seen[apply] = code
      end
   end)

   H.test("Rueckfall: esMX -> esES, enGB -> enUS, unbekannt -> enUS", function()
      local T = bootAddon("enUS")
      local L = T.L
      H.eq(T.Locale.Set("esMX"), "esES")
      H.eq(T.Locale.Current(), "esES")
      H.eq(rawget(L, "WIN_APPLY"), SPOT.esES.WIN_APPLY)
      H.eq(T.Util.FormatNumber(1234567), NUMBER.esES)

      H.eq(T.Locale.Set("enGB"), "enUS")
      H.eq(rawget(L, "WIN_APPLY"), SPOT.enUS.WIN_APPLY)

      for _, unknown in ipairs({ "xxXX", "ptBR", "itIT", "frCA" }) do
         H.eq(T.Locale.Set(unknown), "enUS", unknown)
         H.eq(rawget(L, "WIN_APPLY"), SPOT.enUS.WIN_APPLY, unknown)
         H.eq(rawget(L, "WIN_CLOSE"), SPOT.enUS.WIN_CLOSE, unknown)
      end

      -- ein Schluessel, der in der Zielsprache fehlte, faellt auf Englisch zurueck (nicht auf den Schluessel)
      T.Locale.Set("deDE")
      T.Locale.Add("enUS", { T_ONLY_ENGLISH = "english only" })
      T.Locale.Set("deDE")
      H.eq(L.T_ONLY_ENGLISH, "english only")
   end)

   H.test("Auto: folgt GetLocale() des Clients (alle zehn Client-Codes)", function()
      local expect = {
         enUS = "enUS", enGB = "enUS", deDE = "deDE", frFR = "frFR", esES = "esES", esMX = "esES",
         ruRU = "ruRU", koKR = "koKR", zhCN = "zhCN", zhTW = "zhTW",
      }
      for _, client in ipairs(sortedKeys(expect)) do
         local T = bootAddon(client)
         H.eq(T.Locale.Set("auto"), expect[client], "Client " .. client)
         H.eq(T.Locale.Current(), expect[client], "Client " .. client)
         H.eq(rawget(T.L, "WIN_APPLY"), SPOT[expect[client]].WIN_APPLY, "Client " .. client)
      end
   end)

   H.test("Gespeicherte Sprache: Boot setzt sie beim Anmelden, Client-Sprache ist egal", function()
      for _, code in ipairs(CODES) do
         local T = bootAddon("enUS", { TransmogGlobalDB = { version = 2, locale = code } })
         H.eq(T.Locale.Current(), code, "gespeichert " .. code)
         H.eq(rawget(T.L, "WIN_APPLY"), SPOT[code].WIN_APPLY, "gespeichert " .. code)
      end
   end)

   H.test("L bleibt dieselbe Tabelle; Wechsel feuert LOCALE_CHANGED und aktualisiert die Tastenbelegung", function()
      local T = bootAddon("enUS")
      local L = T.L
      local fired = 0
      T.Events.On("LOCALE_CHANGED", function() fired = fired + 1 end, "test_locales")
      local data = allData()
      for _, code in ipairs({ "deDE", "koKR", "enUS", "zhTW", "frFR", "ruRU", "zhCN", "esES" }) do
         local before = fired
         T.Locale.Set(code)
         H.truthy(T.L == L, code .. ": Transmog.L wurde ersetzt")
         H.eq(fired, before + 1, code .. ": LOCALE_CHANGED genau einmal")
         H.eq(rawget(_G, "BINDING_HEADER_TRANSMOG"), data[code].BOOT_BINDING_HEADER, code .. ": Tastenbelegung (Kopf)")
         H.eq(rawget(_G, "BINDING_NAME_TRANSMOG_TOGGLE"), data[code].BOOT_BINDING_TOGGLE, code .. ": Tastenbelegung (Name)")
      end
      T.Events.Off("LOCALE_CHANGED", "test_locales")
   end)

   H.test("Fenster: Sprachwechsel bei offenem Fenster setzt Reiter, Knoepfe und Fuss neu", function()
      local Fixtures = require("fixtures")
      local T = Fixtures.Boot(H, { locale = "enUS" })
      Fixtures.ServerHello(T)
      Fixtures.ServerAutoReply(T)
      Fixtures.OpenAtNpc(T)
      Fixtures.Settle(T, 1)
      local data = allData()
      local function texts()
         local out = {}
         M.Walk(rawget(_G, "TransmogWindow"), function(o)
            local ok, t = pcall(function() return o:GetText() end)
            if ok and type(t) == "string" then out[t] = true end
         end)
         return out
      end
      H.truthy(texts()[data.enUS.WIN_TAB_OUTFITS], "englischer Reiter")
      for _, code in ipairs(CODES) do
         Fixtures.SetLanguage(T, code)
         Fixtures.Settle(T, 0.3)
         local t = texts()
         H.truthy(t[data[code].WIN_TAB_OUTFITS], code .. ": Reiter \"" .. data[code].WIN_TAB_OUTFITS .. "\"")
         H.truthy(t[data[code].WIN_TAB_ITEMS], code .. ": Reiter \"" .. data[code].WIN_TAB_ITEMS .. "\"")
         if code ~= "deDE" then
            H.falsy(t[data.deDE.WIN_TAB_ITEMS], code .. ": deutscher Text bleibt nicht stehen")
         end
      end
      H.eq(#M.errors, 0)
   end)
end
