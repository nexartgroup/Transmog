-- tests/lint_locale.lua
-- ---------------------------------------------------------------------------
-- Locale-Linter fuer das Transmog-Addon (WoW 3.3.5a, Lua 5.1).
--
-- Laedt Locales/Locale.lua und alle Locales/*.lua in einer minimalen Umgebung
-- (GetLocale-Attrappe, kein WoW) und prueft:
--   (a) jeder im Code benutzte Schluessel (L.KEY, L["KEY"], auch ueber
--       "local L = T.L" und T.L.KEY) existiert in enUS; dynamische Schluessel
--       (L[expr]) werden als Warnung gemeldet
--   (b) jeder enUS-Schluessel existiert in jeder vorhandenen Sprachdatei
--       (fehlende werden je Sprache gelistet; unvollstaendige Datei = Fehler)
--   (c) Platzhalter-Paritaet: Folge der %d/%s/... ist in jeder Uebersetzung
--       identisch zu enUS (keine %1$s, kein %i; einzelnes % als Warnung)
--   (d) kein BOM, gueltiges UTF-8, kein CRLF in allen Locale-Dateien
--   (e) Schluessel bestehen nur aus A-Z 0-9 _
--   (f) unbenutzte enUS-Schluessel (Warnung)
-- und zusaetzlich: doppelte Schluessel, Nicht-String-Werte, Escape-Paritaet
-- (|c |r |T |t |n), Rauchtest der Locale-API (Add/Set/Current/List, Fallback-Kette,
-- stabile Tabelle L, fehlender Schluessel liefert sich selbst) und eine
-- Heuristik fuer fest einprogrammierte Anzeigetexte (SetText("English")).
--
-- Aufruf (aus dem Addon-Verzeichnis, mit luajit):
--    luajit tests/lint_locale.lua [Optionen]
--
-- Optionen:
--    --root DIR         Addon-Verzeichnis (Standard: Elternverzeichnis von tests/)
--    --strict-locales   fehlende erwartete Sprachdateien (deDE frFR esES ruRU koKR
--                       zhCN zhTW) sind Fehler statt Warnung
--    -v                 alle Meldungen und vollstaendige Schluessellisten
--    -q                 nur Fehler und Summe
--    -h, --help         diese Hilfe
--
-- Exit-Code: 0 = keine Fehler (Warnungen moeglich), 1 = Fehler, 2 = Aufrufproblem.
-- ---------------------------------------------------------------------------

local function die(msg)
   io.stderr:write("lint_locale: " .. msg .. "\n")
   os.exit(2)
end

-- ---------------------------------------------------------------------------
-- Aufruf
-- ---------------------------------------------------------------------------

local opt = { root = nil, strict = false, verbose = false, quiet = false }

do
   local i = 1
   while arg[i] do
      local a = arg[i]
      if a == "--root" then
         i = i + 1
         opt.root = arg[i] or die("--root braucht ein Verzeichnis")
      elseif a == "--strict-locales" then
         opt.strict = true
      elseif a == "-v" or a == "--verbose" then
         opt.verbose = true
      elseif a == "-q" or a == "--quiet" then
         opt.quiet = true
      elseif a == "-h" or a == "--help" then
         local f = io.open(arg[0], "r")
         if f then
            for line in f:lines() do
               if not line:find("^%-%-") then break end
               print((line:gsub("^%-%- ?", "")))
            end
            f:close()
         end
         os.exit(0)
      else
         die("unbekannte Option: " .. a)
      end
      i = i + 1
   end
end

local SCRIPT_DIR = (arg[0] or ""):match("^(.*)/[^/]*$") or "."
local ROOT = opt.root or (SCRIPT_DIR .. "/..")
local LIST_MAX = opt.verbose and 1000000 or 12

-- erwartete Sprachdateien laut Spezifikation (esMX/enGB fallen auf esES/enUS zurueck)
local EXPECTED = { "deDE", "frFR", "esES", "ruRU", "koKR", "zhCN", "zhTW" }
local KNOWN_CODES = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true,
                      ruRU = true, koKR = true, zhCN = true, zhTW = true }

-- Zeichenketten mit diesen Praefixen sind Schluessel, die per L[key] aufgeloest werden
-- (Gruende aus State.CanApply bzw. Outfits.ValidateName): muessen in enUS existieren.
local STRICT_PREFIXES = { "APPLY_REASON_", "OUTFIT_ERR_" }

-- ---------------------------------------------------------------------------
-- Helfer
-- ---------------------------------------------------------------------------

local function shq(s)
   return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

local function read_file(path)
   local f = io.open(path, "rb")
   if not f then return nil end
   local s = f:read("*a")
   f:close()
   return s
end

local function list_files(dir, pattern, maxdepth)
   local out = {}
   local cmd = "cd " .. shq(ROOT) .. " && find " .. shq(dir) .. " " ..
      (maxdepth and ("-maxdepth " .. maxdepth .. " ") or "") .. "-type f -name " .. shq(pattern) .. " 2>/dev/null"
   local p = io.popen(cmd)
   if not p then return out end
   for line in p:lines() do
      out[#out + 1] = (line:gsub("^%./", ""))
   end
   p:close()
   table.sort(out)
   return out
end

local function excluded(rel)
   if rel:find("^tests/") then return true end
   for seg in rel:gmatch("[^/]+") do
      if seg:sub(1, 1) == "." or seg == "_lintfixtures" or seg:find("^lint_fixture_") then
         return true
      end
   end
   return false
end

local function utf8_error(s)
   local i, n = 1, #s
   while i <= n do
      local c = s:byte(i)
      if c < 0x80 then
         i = i + 1
      else
         local need, min
         if c >= 0xC2 and c <= 0xDF then
            need, min = 1, 0x80
         elseif c >= 0xE0 and c <= 0xEF then
            need, min = 2, 0x800
         elseif c >= 0xF0 and c <= 0xF4 then
            need, min = 3, 0x10000
         else
            return i
         end
         local cp = c % (need == 1 and 0x20 or (need == 2 and 0x10 or 0x08))
         for k = 1, need do
            local b = s:byte(i + k)
            if not b or b < 0x80 or b > 0xBF then return i end
            cp = cp * 64 + (b - 0x80)
         end
         if cp < min or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then return i end
         i = i + need + 1
      end
   end
   return nil
end

local function line_of(s, pos)
   local line = 1
   for _ in s:sub(1, pos - 1):gmatch("\n") do line = line + 1 end
   return line
end

-- ---------------------------------------------------------------------------
-- Meldungen
-- ---------------------------------------------------------------------------

local issues = {}
local n_error, n_warn = 0, 0

-- sev: "error" | "warn" | "info" (info wird nur mit -v ausgegeben und nicht gezaehlt)
local function report(file, line, sev, rule, msg)
   issues[#issues + 1] = { file = file, line = line or 0, sev = sev, rule = rule, msg = msg, seq = #issues + 1 }
   if sev == "error" then
      n_error = n_error + 1
   elseif sev == "warn" then
      n_warn = n_warn + 1
   end
end

local function key_list(keys)
   local n = #keys
   local parts = {}
   for i = 1, math.min(n, LIST_MAX) do parts[i] = keys[i] end
   local s = table.concat(parts, ", ")
   if n > LIST_MAX then s = s .. (", ... and %d more"):format(n - LIST_MAX) end
   return s
end

-- ---------------------------------------------------------------------------
-- Tokenizer (wie in lint_style.lua, ohne die Lua-5.2-Pruefungen)
-- ---------------------------------------------------------------------------

local KEYWORDS = {}
for w in ([[and break do else elseif end false for function if in local nil not
            or repeat return then true until while]]):gmatch("%S+") do
   KEYWORDS[w] = true
end

-- Rueckgabe: toks = Array { t = name|kw|num|str|op, v = Text, line = n }
local function lex(src)
   local toks = {}
   local i, n, line = 1, #src, 1
   if src:sub(1, 1) == "#" then i = src:find("\n", 1, true) or n end
   while i <= n do
      local c = src:sub(i, i)
      if c == "\n" then
         line = line + 1
         i = i + 1
      elseif c == "\r" then
         if src:sub(i + 1, i + 1) == "\n" then i = i + 1 end
         line = line + 1
         i = i + 1
      elseif c == " " or c == "\t" or c == "\f" or c == "\v" then
         i = i + 1
      elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
         local eq = src:match("^%-%-%[(=*)%[", i)
         if eq then
            local s, e = src:find("]" .. eq .. "]", i + 4 + #eq, true)
            e = e or n
            for _ in src:sub(i, e):gmatch("\n") do line = line + 1 end
            i = e + 1
         else
            i = src:find("[\r\n]", i) or (n + 1)
         end
      elseif c == '"' or c == "'" then
         local start_line = line
         local j = i + 1
         while j <= n do
            local d = src:sub(j, j)
            if d == c or d == "\n" then
               break
            elseif d == "\\" then
               local e = src:sub(j + 1, j + 1)
               if e == "\n" then line = line + 1 end
               if e == "\r" then
                  line = line + 1
                  if src:sub(j + 2, j + 2) == "\n" then j = j + 1 end
               end
               j = j + 2
            else
               j = j + 1
            end
         end
         toks[#toks + 1] = { t = "str", v = src:sub(i + 1, j - 1), line = start_line }
         i = j + 1
      elseif c == "[" and src:find("^%[=*%[", i) then
         local eq = src:match("^%[(=*)%[", i)
         local s, e = src:find("]" .. eq .. "]", i + 2 + #eq, true)
         s, e = s or (n + 1), e or n
         toks[#toks + 1] = { t = "str", v = src:sub(i + 2 + #eq, s - 1), line = line }
         for _ in src:sub(i, e):gmatch("\n") do line = line + 1 end
         i = e + 1
      elseif c:find("^%d") or (c == "." and src:find("^%.%d", i)) then
         local s, e = src:find("^0[xX][%w_.]*", i)
         if not s then s, e = src:find("^%.?%d[%w_.]*", i) end
         local text = src:sub(s, e)
         local last = text:sub(-1)
         if (last == "e" or last == "E" or last == "p" or last == "P") and src:sub(e + 1, e + 1):find("^[%+%-]") then
            local s2, e2 = src:find("^[%+%-][%w_]*", e + 1)
            if s2 then text = text .. src:sub(s2, e2); e = e2 end
         end
         toks[#toks + 1] = { t = "num", v = text, line = line }
         i = e + 1
      elseif c:find("^[%a_]") then
         local s, e = src:find("^[%a_][%w_]*", i)
         local word = src:sub(s, e)
         toks[#toks + 1] = { t = KEYWORDS[word] and "kw" or "name", v = word, line = line }
         i = e + 1
      else
         local three, two = src:sub(i, i + 2), src:sub(i, i + 1)
         local op
         if three == "..." then
            op = three
         elseif two == "==" or two == "~=" or two == "<=" or two == ">=" or two == ".." or two == "::" then
            op = two
         else
            op = c
         end
         toks[#toks + 1] = { t = "op", v = op, line = line }
         i = i + #op
      end
   end
   return toks
end

-- ---------------------------------------------------------------------------
-- Platzhalter
-- ---------------------------------------------------------------------------

local VALID_CONV = { c = true, d = true, E = true, e = true, f = true, g = true, G = true, i = true,
                     o = true, q = true, s = true, u = true, X = true, x = true }

-- Zerlegt einen Formatstring. Rueckgabe: convs (Array der Umwandlungszeichen),
-- specs (Array der vollen Angaben), problems (Array Texte)
local function parse_placeholders(s)
   local convs, specs, problems = {}, {}, {}
   local p = 1
   while true do
      local pos = s:find("%", p, true)
      if not pos then break end
      if s:sub(pos + 1, pos + 1) == "%" then
         p = pos + 2
      elseif s:find("^%d+%$", pos + 1) then
         problems[#problems + 1] = "positional placeholder (%n$) is not allowed"
         p = pos + 2
      else
         local flags, width, prec, conv = s:match("^([%-%+ #0]*)(%d*)(%.?%d*)(%a)", pos + 1)
         if conv and VALID_CONV[conv] then
            convs[#convs + 1] = conv
            specs[#specs + 1] = "%" .. flags .. width .. prec .. conv
            if conv == "i" then
               problems[#problems + 1] = "placeholder %i is not allowed (use %d)"
            end
            p = pos + 1 + #flags + #width + #prec + 1
         else
            problems[#problems + 1] = "lone '%' (write %% if the text is passed through format)"
            p = pos + 1
         end
      end
   end
   return convs, specs, problems
end

local function count_escape(s, pat)
   local n = 0
   for _ in s:gmatch(pat) do n = n + 1 end
   return n
end

-- ---------------------------------------------------------------------------
-- Dateien erfassen
-- ---------------------------------------------------------------------------

local locale_files = list_files("Locales", "*.lua", 1)
local framework_rel = "Locales/Locale.lua"
local has_framework = false
local en_files, tr_files, other_files = {}, {}, {}   -- tr_files: { rel, code }
for _, rel in ipairs(locale_files) do
   local base = rel:match("([^/]+)%.lua$")
   if rel == framework_rel then
      has_framework = true
   elseif base:find("^enUS") then
      en_files[#en_files + 1] = rel
   elseif KNOWN_CODES[base] then
      tr_files[#tr_files + 1] = { rel = rel, code = base }
   else
      other_files[#other_files + 1] = rel
   end
end

for _, rel in ipairs(other_files) do
   report(rel, 0, "warn", "locale-file", "unrecognized file in Locales/ (expected Locale.lua, enUS*.lua or <code>.lua)")
end

-- Datei-Hygiene (d)
for _, rel in ipairs(locale_files) do
   local src = read_file(ROOT .. "/" .. rel) or ""
   if src:sub(1, 3) == "\239\187\191" then
      report(rel, 1, "error", "bom", "file starts with a UTF-8 BOM")
   end
   local bad = utf8_error(src)
   if bad then
      report(rel, line_of(src, bad), "error", "utf8", "invalid UTF-8 byte sequence (byte offset " .. bad .. ")")
   end
   if src:find("\r", 1, true) then
      report(rel, line_of(src, src:find("\r", 1, true)), "error", "crlf", "CR/CRLF line ending (use LF)")
   end
   if src:find("\239\191\189", 1, true) then
      report(rel, line_of(src, src:find("\239\191\189", 1, true)), "warn", "utf8",
         "contains U+FFFD (replacement character): text was damaged by a wrong encoding")
   end
end

if not has_framework then
   report(framework_rel, 0, "error", "locale-framework", "Locales/Locale.lua not found")
end
if #en_files == 0 then
   report("Locales", 0, "error", "locale-enus", "no enUS file found (Locales/enUS_*.lua)")
end

-- ---------------------------------------------------------------------------
-- Minimale Umgebung und Laden
-- ---------------------------------------------------------------------------

local client_locale = { value = "enUS" }
local env_missing = {}      -- globaler Name -> true (von Locale-Dateien gelesen, aber nicht vorhanden)
local current_file = nil

local env = {}
do
   local passthrough = { "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "setmetatable",
                         "getmetatable", "rawget", "rawset", "rawequal", "tonumber", "tostring", "type", "unpack",
                         "xpcall", "string", "table", "math", "loadstring" }
   for _, k in ipairs(passthrough) do env[k] = _G[k] end
   env._G = env
   env.GetLocale = function() return client_locale.value end
   env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
   env.tinsert, env.tremove = table.insert, table.remove
   env.format, env.gsub, env.gmatch = string.format, string.gsub, string.gmatch
   env.strlen, env.strlower, env.strupper = string.len, string.lower, string.upper
   env.strsub, env.strfind, env.strmatch = string.sub, string.find, string.match
   env.strbyte, env.strchar, env.strrep = string.byte, string.char, string.rep
   env.floor, env.ceil, env.abs, env.min, env.max = math.floor, math.ceil, math.abs, math.min, math.max
   env.mod, env.sqrt = math.fmod, math.sqrt
   env.date, env.time = os.date, os.time
   env.GetTime = os.clock
   env.geterrorhandler = function() return function() end end
   env.strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
   env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
   env.strsplit = function(sep, s)
      local out, pos = {}, 1
      s = tostring(s)
      while true do
         local a, b = s:find(sep, pos, true)
         if not a then out[#out + 1] = s:sub(pos); break end
         out[#out + 1] = s:sub(pos, a - 1)
         pos = b + 1
      end
      return unpack(out)
   end
   setmetatable(env, { __index = function(_, k)
      if type(k) == "string" and k ~= "Transmog" then env_missing[k] = current_file or true end
      return nil
   end })
end

-- erfasste Daten
local captured = {}      -- code -> { values = {key=value}, origin = {key=file}, files = {file=true} }
local per_file_keys = {} -- rel -> Array { key, line } (aus dem Quelltext)

local function capture(code, tbl, rel)
   if type(code) ~= "string" or type(tbl) ~= "table" then
      report(rel or "?", 0, "error", "locale-add", "Locale.Add(code, tbl) called with invalid arguments ("
         .. type(code) .. ", " .. type(tbl) .. ")")
      return
   end
   local set = captured[code]
   if not set then
      set = { values = {}, origin = {}, files = {} }
      captured[code] = set
   end
   set.files[rel] = true
   for k, v in pairs(tbl) do
      if set.values[k] ~= nil and set.origin[k] ~= rel then
         if set.values[k] == v then
            report(rel, 0, "warn", "duplicate-key", ("key %s (%s) is already defined in %s with the same text"):format(
               tostring(k), code, set.origin[k]))
         else
            report(rel, 0, "error", "duplicate-key", ("key %s (%s) is already defined in %s with a different text"):format(
               tostring(k), code, set.origin[k]))
         end
      end
      set.values[k] = v
      set.origin[k] = rel
   end
end

local function run_chunk(rel)
   local path = ROOT .. "/" .. rel
   local fn, err = loadfile(path)
   if not fn then
      report(rel, 0, "error", "syntax", tostring(err))
      return false
   end
   setfenv(fn, env)
   current_file = rel
   local ok, e = pcall(fn)
   current_file = nil
   if not ok then
      report(rel, 0, "error", "load", "error while loading: " .. tostring(e))
      return false
   end
   return true
end

local framework_ok = false
local T
if has_framework then
   framework_ok = run_chunk(framework_rel)
   T = rawget(env, "Transmog")
   if framework_ok and (type(T) ~= "table" or type(T.Locale) ~= "table") then
      report(framework_rel, 0, "error", "locale-framework", "Locale.lua must define the global table Transmog.Locale")
      framework_ok = false
   end
end

local original_add
if framework_ok then
   original_add = T.Locale.Add
   if type(original_add) ~= "function" then
      report(framework_rel, 0, "error", "locale-framework", "Transmog.Locale.Add is missing")
      framework_ok = false
   end
end
if not framework_ok then
   -- Ersatz, damit die Datenpruefungen trotzdem laufen
   T = { Locale = {} }
   env.Transmog = T
   original_add = nil
end

T.Locale.Add = function(code, tbl)
   capture(code, tbl, current_file)
   if original_add then return original_add(code, tbl) end
end

local function load_files(list)
   for _, rel in ipairs(list) do run_chunk(rel) end
end
load_files(en_files)
for _, f in ipairs(tr_files) do run_chunk(f.rel) end
-- Dateien mit unbekanntem Namen nicht laden (nur gemeldet)

for name, where in pairs(env_missing) do
   report(type(where) == "string" and where or "Locales", 0, "warn", "locale-global",
      "locale file reads global '" .. name .. "' which does not exist in the minimal environment")
end

-- ---------------------------------------------------------------------------
-- Schluessel im Quelltext der Locale-Dateien (Zeilen, Duplikate in einer Datei)
-- ---------------------------------------------------------------------------

local KEY_PATTERN = "^[A-Z0-9_]+$"
local key_line = {}      -- rel -> { key = line }

for _, rel in ipairs(locale_files) do
   if rel ~= framework_rel then
      local src = read_file(ROOT .. "/" .. rel) or ""
      local toks = lex(src)
      local seen, lines = {}, {}
      local depth = 0
      for i, tk in ipairs(toks) do
         if tk.t == "op" then
            if tk.v == "{" then depth = depth + 1 elseif tk.v == "}" then depth = depth - 1 end
         end
         local key
         local prev = toks[i - 1]
         if depth >= 1 and prev and prev.t == "op" and (prev.v == "{" or prev.v == "," or prev.v == ";") then
            if tk.t == "name" and toks[i + 1] and toks[i + 1].v == "=" then
               key = tk.v
            elseif tk.t == "op" and tk.v == "[" and toks[i + 1] and toks[i + 1].t == "str"
               and toks[i + 2] and toks[i + 2].v == "]" and toks[i + 3] and toks[i + 3].v == "=" then
               key = toks[i + 1].v
            end
         end
         if key then
            if seen[key] then
               report(rel, tk.line, "error", "duplicate-key", ("key %s is defined twice in this file (first at line %d)"):format(
                  key, seen[key]))
            else
               seen[key] = tk.line
               lines[key] = tk.line
            end
         end
      end
      key_line[rel] = lines
   end
end

-- ---------------------------------------------------------------------------
-- Pruefung enUS: Schluesselnamen, Werttypen
-- ---------------------------------------------------------------------------

local en = captured["enUS"] and captured["enUS"].values or {}
local en_keys = {}
for k in pairs(en) do en_keys[#en_keys + 1] = tostring(k) end
table.sort(en_keys)

local function where(code, key)
   local set = captured[code]
   local rel = set and set.origin[key]
   local line = rel and key_line[rel] and key_line[rel][key] or 0
   return rel or ("Locales/" .. code .. ".lua"), line
end

for code, set in pairs(captured) do
   for k, v in pairs(set.values) do
      local rel, line = where(code, k)
      if type(k) ~= "string" or not k:find(KEY_PATTERN) then
         report(rel, line, "error", "key-charset", ("key '%s' (%s) must consist of A-Z 0-9 _ only"):format(tostring(k), code))
      elseif k:find("^%d") then
         report(rel, line, "warn", "key-charset", ("key '%s' starts with a digit and cannot be used as L.%s"):format(k, k))
      end
      if type(v) ~= "string" then
         report(rel, line, "error", "value-type", ("value of %s (%s) must be a string, got %s"):format(tostring(k), code, type(v)))
      elseif code == "enUS" and v == "" and k ~= "THOUSANDS_SEP" then
         report(rel, line, "warn", "empty-value", ("value of %s (enUS) is empty"):format(k))
      end
   end
end

-- ---------------------------------------------------------------------------
-- (b)/(c): Vollstaendigkeit und Platzhalter je Sprache
-- ---------------------------------------------------------------------------

local en_ph = {}
for _, k in ipairs(en_keys) do
   local v = en[k]
   if type(v) == "string" then
      local convs, specs, problems = parse_placeholders(v)
      en_ph[k] = { convs = convs, specs = specs }
      local rel, line = where("enUS", k)
      for _, p in ipairs(problems) do
         report(rel, line, p:find("lone") and "warn" or "error", "placeholder", ("key %s (enUS): %s"):format(k, p))
      end
   end
end

local summary = {}   -- Zeilen fuer die Abschlussuebersicht
local complete_codes = {}

local function present_translations()
   local arr = {}
   for _, f in ipairs(tr_files) do arr[#arr + 1] = f end
   return arr
end

for _, f in ipairs(present_translations()) do
   local code, rel = f.code, f.rel
   local set = captured[code]
   if not set then
      report(rel, 0, "error", "locale-empty", ("%s does not register any texts (Transmog.Locale.Add(\"%s\", {...}) missing)"):format(rel, code))
      summary[#summary + 1] = ("%-5s 0/%d keys (%s adds nothing)"):format(code, #en_keys, rel)
   else
      local missing, identical, extra = {}, {}, {}
      local counted = 0
      for _, k in ipairs(en_keys) do
         local v = set.values[k]
         if v == nil then
            missing[#missing + 1] = k
         else
            counted = counted + 1
            local ev = en[k]
            if type(v) == "string" and type(ev) == "string" then
               if v == "" and ev ~= "" then
                  report(rel, select(2, where(code, k)), "error", "locale-empty",
                     ("key %s is an empty string in %s (enUS: '%s')"):format(k, code, ev))
               end
               -- Platzhalter-Paritaet
               local convs, specs, problems = parse_placeholders(v)
               local ref = en_ph[k]
               local line = select(2, where(code, k))
               for _, p in ipairs(problems) do
                  report(rel, line, p:find("lone") and "warn" or "error", "placeholder", ("key %s (%s): %s"):format(k, code, p))
               end
               if ref then
                  local a, b = table.concat(ref.convs, ","), table.concat(convs, ",")
                  if a ~= b then
                     report(rel, line, "error", "placeholder",
                        ("key %s: enUS has (%s) but %s has (%s)"):format(k, table.concat(ref.specs, " "), code,
                           table.concat(specs, " ")))
                  elseif table.concat(ref.specs, ",") ~= table.concat(specs, ",") then
                     report(rel, line, "warn", "placeholder",
                        ("key %s: placeholder details differ: enUS (%s) vs %s (%s)"):format(k,
                           table.concat(ref.specs, " "), code, table.concat(specs, " ")))
                  end
               end
               -- Escape-Paritaet (Farbcodes, Texturen, Zeilenumbrueche)
               for _, esc in ipairs({ "|c", "|r", "|T", "|t", "|n", "|H", "|h" }) do
                  local pat = esc:gsub("%|", "%%|")
                  if count_escape(ev, pat) ~= count_escape(v, pat) then
                     report(rel, line, "warn", "escape-parity",
                        ("key %s: '%s' occurs %d x in enUS but %d x in %s"):format(k, esc, count_escape(ev, pat),
                           count_escape(v, pat), code))
                     break
                  end
               end
               if v == ev and #v >= 4 and v:find("%a%a%a") then
                  identical[#identical + 1] = k
               end
            end
         end
      end
      for k in pairs(set.values) do
         if en[k] == nil then extra[#extra + 1] = tostring(k) end
      end
      table.sort(extra)

      if #missing > 0 then
         report(rel, 0, "error", "locale-missing",
            ("%d of %d enUS key(s) missing in %s: %s"):format(#missing, #en_keys, code, key_list(missing)))
      else
         complete_codes[code] = true
      end
      if #extra > 0 then
         report(rel, 0, "warn", "locale-extra",
            ("%d key(s) in %s that do not exist in enUS: %s"):format(#extra, code, key_list(extra)))
      end
      if #identical > 0 and #en_keys > 0 and (#identical / #en_keys) > 0.25 then
         report(rel, 0, "warn", "untranslated",
            ("%d of %d strings are identical to enUS (untranslated?): %s"):format(#identical, #en_keys, key_list(identical)))
      end
      summary[#summary + 1] = ("%-5s %d/%d keys%s"):format(code, counted, #en_keys,
         #missing == 0 and "" or ("  (" .. #missing .. " missing)"))
   end
end

-- Dateien registrieren Texte nur fuer ihre eigene Sprache
for _, f in ipairs(tr_files) do
   for code, set in pairs(captured) do
      if code ~= f.code and set.files[f.rel] then
         report(f.rel, 0, "warn", "locale-code",
            ("%s registers texts for '%s' (expected only '%s')"):format(f.rel, code, f.code))
      end
   end
end

-- erwartete, aber fehlende Sprachdateien
local have = {}
for _, f in ipairs(tr_files) do have[f.code] = true end
local absent = {}
for _, code in ipairs(EXPECTED) do
   if not have[code] then absent[#absent + 1] = code end
end
if #absent > 0 then
   report("Locales", 0, opt.strict and "error" or "warn", "locale-absent",
      "no locale file yet for: " .. table.concat(absent, ", "))
end

-- ---------------------------------------------------------------------------
-- (a)/(f): Benutzung im Code
-- ---------------------------------------------------------------------------

local code_files = {}
for _, rel in ipairs(list_files(".", "*.lua")) do
   if not excluded(rel) and not rel:find("^Locales/") then code_files[#code_files + 1] = rel end
end

local used = {}            -- Schluessel -> true (statisch referenziert)
local referenced = {}      -- Schluessel -> true (auch als Stringliteral)
local dynamic_uses = {}    -- { rel, line }
local dyn_prefixes = {}    -- Praefix aus L["PREFIX_" .. x] -> { rel, line }
local odd_keys = {}        -- { rel, line, key }: L.klein (kein gueltiger Schluessel)
local hard_texts = {}      -- { rel, line, text }
local KEYED = "^[A-Z][A-Z0-9_]*$"

local UI_TEXT_METHODS = { SetText = true, SetLabel = true, SetPlaceholder = true, AddLine = true,
                          AddDoubleLine = true, SetFormattedText = true, SetTitle = true }
local PRINT_FUNCS = { Print = true, Error = true }

local function visible_letters(s)
   s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("%%[%-%+ #0]*%d*%.?%d*%a", "")
   s = s:gsub("\\n", ""):gsub("|n", "")
   local n = 0
   for _ in s:gmatch("%a%a") do n = n + 1 end
   return n
end

for _, rel in ipairs(code_files) do
   local src = read_file(ROOT .. "/" .. rel)
   if src then
      local toks = lex(src)
      -- Aliasse fuer die Locale-Tabelle: L, plus "local X = T.L" / "Transmog.L"
      local alias = { L = true }
      for i, tk in ipairs(toks) do
         if tk.v == "local" and toks[i + 1] and toks[i + 1].t == "name" and toks[i + 2] and toks[i + 2].v == "="
            and toks[i + 3] and (toks[i + 3].v == "T" or toks[i + 3].v == "Transmog")
            and toks[i + 4] and toks[i + 4].v == "." and toks[i + 5] and toks[i + 5].v == "L" then
            local after = toks[i + 6]
            if not after or not (after.v == "." or after.v == "[") then
               alias[toks[i + 1].v] = true
            end
         end
      end

      local function check_ref(idx, line)
         -- toks[idx] ist der Alias/L-Name; naechstes Token bestimmt die Art des Zugriffs
         local nx = toks[idx + 1]
         if not nx then return end
         if nx.v == "." and toks[idx + 2] and toks[idx + 2].t == "name" then
            local key = toks[idx + 2].v
            if key:find(KEYED) then
               used[key] = used[key] or { rel = rel, line = line }
            elseif not key:find("^__") then
               odd_keys[#odd_keys + 1] = { rel = rel, line = line, key = key }
            end
         elseif nx.v == "[" then
            local s, close = toks[idx + 2], toks[idx + 3]
            if s and s.t == "str" and close and close.v == "]" then
               local key = s.v
               if key:find("^__") then return end
               used[key] = used[key] or { rel = rel, line = line }
            elseif s and s.t == "str" and close and close.v == ".." then
               -- L["SORT_" .. key]: der feste Teil ist ein Praefix, dessen Schluessel zaehlen als benutzt
               dyn_prefixes[s.v] = dyn_prefixes[s.v] or { rel = rel, line = line }
            else
               dynamic_uses[#dynamic_uses + 1] = { rel = rel, line = line }
            end
         end
      end

      for i, tk in ipairs(toks) do
         local prev = toks[i - 1]
         local after_dot = prev and prev.t == "op" and (prev.v == "." or prev.v == ":")
         if tk.t == "name" then
            if alias[tk.v] and not after_dot then
               check_ref(i, tk.line)
            elseif (tk.v == "T" or tk.v == "Transmog") and not after_dot
               and toks[i + 1] and toks[i + 1].v == "." and toks[i + 2] and toks[i + 2].v == "L" then
               check_ref(i + 2, tk.line)
            end
            -- Hartkodierte Anzeigetexte: obj:SetText("English")  /  Util.Print("English")
            if (UI_TEXT_METHODS[tk.v] and prev and prev.v == ":") or (PRINT_FUNCS[tk.v] and prev and prev.v == ".") then
               local open, s = toks[i + 1], toks[i + 2]
               if open and open.v == "(" and s and s.t == "str" then
                  local after = toks[i + 3]
                  -- nur reine Literale, keine Verkettung ("a" .. x) bewerten
                  if visible_letters(s.v) >= 1 and after and (after.v == ")" or after.v == ",") then
                     hard_texts[#hard_texts + 1] = { rel = rel, line = tk.line, text = s.v }
                  end
               end
            end
         elseif tk.t == "str" then
            local v = tk.v
            if v:find("^[A-Z][A-Z0-9_]+$") then
               referenced[v] = true
               for _, pre in ipairs(STRICT_PREFIXES) do
                  if v:sub(1, #pre) == pre and en[v] == nil then
                     report(rel, tk.line, "error", "key-undefined",
                        ("string \"%s\" looks like a locale key (prefix %s) but does not exist in enUS"):format(v, pre))
                  end
               end
            end
         end
      end
   end
end

-- (a) benutzte Schluessel muessen in enUS existieren
local missing_used = {}
for key, where_ in pairs(used) do
   if en[key] == nil then missing_used[#missing_used + 1] = { key = key, rel = where_.rel, line = where_.line } end
end
table.sort(missing_used, function(a, b)
   if a.rel ~= b.rel then return a.rel < b.rel end
   if a.line ~= b.line then return a.line < b.line end
   return a.key < b.key
end)
for _, m in ipairs(missing_used) do
   report(m.rel, m.line, "error", "key-undefined", ("locale key L.%s is used but not defined in enUS"):format(m.key))
end

-- dynamische Zugriffe
table.sort(dynamic_uses, function(a, b)
   if a.rel ~= b.rel then return a.rel < b.rel end
   return a.line < b.line
end)
for _, d in ipairs(dynamic_uses) do
   report(d.rel, d.line, "warn", "key-dynamic", "dynamic L[...] key cannot be verified statically")
end

-- harte Texte
table.sort(hard_texts, function(a, b)
   if a.rel ~= b.rel then return a.rel < b.rel end
   return a.line < b.line
end)
for _, h in ipairs(hard_texts) do
   if visible_letters(h.text) >= 1 then
      report(h.rel, h.line, "warn", "hardcoded-text",
         ("string literal \"%s\" in UI text: move it to the locale files"):format(h.text:sub(1, 40)))
   end
end

-- Schluessel mit Praefix-Zugriff: der Praefix muss mindestens einen enUS-Schluessel treffen
local prefix_used = {}
do
   local plist = {}
   for pre in pairs(dyn_prefixes) do plist[#plist + 1] = pre end
   table.sort(plist)
   for _, pre in ipairs(plist) do
      local hits = 0
      for _, k in ipairs(en_keys) do
         if k:sub(1, #pre) == pre then
            hits = hits + 1
            prefix_used[k] = true
         end
      end
      local where_ = dyn_prefixes[pre]
      if hits == 0 then
         report(where_.rel, where_.line, "warn", "key-dynamic",
            ("dynamic key L[\"%s\" .. ...]: no enUS key starts with '%s'"):format(pre, pre))
      else
         report(where_.rel, where_.line, "info", "key-dynamic",
            ("dynamic key L[\"%s\" .. ...] matches %d enUS key(s)"):format(pre, hits))
      end
   end
end

-- L.klein: wird nie gefunden (Schluessel sind GROSS), liefert den Namen selbst als Text
table.sort(odd_keys, function(a, b)
   if a.rel ~= b.rel then return a.rel < b.rel end
   if a.line ~= b.line then return a.line < b.line end
   return a.key < b.key
end)
for _, o in ipairs(odd_keys) do
   report(o.rel, o.line, "warn", "key-style",
      ("L.%s: locale keys are upper case (A-Z 0-9 _); this access returns the key itself"):format(o.key))
end

-- (f) unbenutzte Schluessel
local unused = {}
for _, k in ipairs(en_keys) do
   if not used[k] and not referenced[k] and not prefix_used[k] then unused[#unused + 1] = k end
end
if #unused > 0 and #code_files > 0 then
   report("Locales", 0, "warn", "key-unused",
      ("%d enUS key(s) are not referenced from code: %s"):format(#unused, key_list(unused)))
end

-- ---------------------------------------------------------------------------
-- Rauchtest der Locale-Framework-API
-- ---------------------------------------------------------------------------

local function smoke_tests()
   local Loc = T.Locale
   local rel = framework_rel
   local function fail(msg) report(rel, 0, "error", "locale-api", msg) end
   local function try(fn, ...)
      local ok, a, b = pcall(fn, ...)
      if not ok then
         fail("call failed: " .. tostring(a))
         return nil
      end
      return a, b
   end

   for _, fname in ipairs({ "Add", "Set", "Current", "List" }) do
      if type(Loc[fname]) ~= "function" then
         fail("Transmog.Locale." .. fname .. " is missing (see SPEC section 4)")
         return
      end
   end
   if type(T.L) ~= "table" then
      fail("Transmog.L must be a table")
      return
   end

   local L0 = T.L
   client_locale.value = "enUS"

   -- enUS
   try(Loc.Set, "enUS")
   if try(Loc.Current) ~= "enUS" then fail("Locale.Set('enUS'): Current() must return 'enUS'") end
   if T.L ~= L0 then fail("Transmog.L must be a stable table (it was replaced by Set)") end
   local sample
   for _, k in ipairs(en_keys) do
      if type(en[k]) == "string" and k:find("^[A-Z][A-Z0-9_]*$") then sample = k; break end
   end
   if sample and T.L[sample] ~= en[sample] then
      fail(("L.%s after Set('enUS') is '%s' (expected '%s')"):format(sample, tostring(T.L[sample]), en[sample]))
   end
   local probe = "NO_SUCH_KEY_ZZZ_LINT"
   if T.L[probe] ~= probe then
      fail("a missing key must return the key itself (L." .. probe .. " returned " .. tostring(T.L[probe]) .. ")")
   end

   -- jede geladene Uebersetzung: Werte und Fallback auf enUS
   for _, f in ipairs(tr_files) do
      local code = f.code
      local set = captured[code]
      if set and code ~= "enUS" then
         try(Loc.Set, code)
         local cur = try(Loc.Current)
         if cur ~= code then
            fail(("Locale.Set('%s'): Current() returned '%s'"):format(code, tostring(cur)))
         end
         local bad, shown = 0, 0
         for _, k in ipairs(en_keys) do
            local expect = set.values[k]
            if expect == nil then expect = en[k] end    -- Fallback
            if k:find(KEY_PATTERN) and type(expect) == "string" and T.L[k] ~= expect then
               bad = bad + 1
               if shown < 3 then
                  shown = shown + 1
                  fail(("after Set('%s'): L.%s is '%s' (expected '%s')"):format(code, k, tostring(T.L[k]), tostring(expect)))
               end
            end
         end
         if bad > shown then fail(("... %d more wrong values after Set('%s')"):format(bad - shown, code)) end
         if T.L ~= L0 then fail("Transmog.L was replaced by Set('" .. code .. "')") end
      end
   end

   -- esMX -> esES, enGB -> enUS: Current() liefert den aufgeloesten Code, also
   -- den Code selbst (eigene Texte) oder den Alias bzw. enUS.
   local function chain_test(code, alias)
      try(Loc.Set, code)
      local cur = try(Loc.Current)
      if cur ~= code and cur ~= alias and cur ~= "enUS" then
         fail(("Locale.Set('%s'): Current() returned '%s' (expected '%s', '%s' or 'enUS')"):format(
            code, tostring(cur), code, alias))
      end
      if sample and not captured[code] then
         local ref = captured[cur] and captured[cur].values
         local expect = (ref and ref[sample]) or en[sample]
         if T.L[sample] ~= expect then
            fail(("Set('%s') must fall back to %s: L.%s is '%s' (expected '%s')"):format(
               code, tostring(cur), sample, tostring(T.L[sample]), tostring(expect)))
         end
      end
   end
   chain_test("esMX", "esES")
   chain_test("enGB", "enUS")

   -- "auto" folgt dem Client
   for _, code in ipairs({ "deDE", "frFR" }) do
      if captured[code] then
         client_locale.value = code
         try(Loc.Set, "auto")
         local cur = try(Loc.Current)
         if cur ~= code then
            fail(("Locale.Set('auto') with GetLocale()=='%s': Current() returned '%s'"):format(code, tostring(cur)))
         end
         break
      end
   end
   client_locale.value = "enUS"
   try(Loc.Set, "auto")
   local cur = try(Loc.Current)
   if cur == "auto" or type(cur) ~= "string" then
      fail("Locale.Current() must never return 'auto'")
   end

   -- Liste der Sprachen
   local list = try(Loc.List)
   if type(list) ~= "table" then
      fail("Locale.List() must return an array of { code=, name= }")
   else
      local names = {}
      for _, e in ipairs(list) do
         if type(e) == "table" and type(e.code) == "string" then names[e.code] = e.name end
      end
      local native = { enUS = "English", deDE = "Deutsch", frFR = "Fran\195\167ais", esES = "Espa\195\177ol",
                       ruRU = "\208\160\209\131\209\129\209\129\208\186\208\184\208\185",
                       koKR = "\237\149\156\234\181\173\236\150\180",
                       zhCN = "\231\174\128\228\189\147\228\184\173\230\150\135",
                       zhTW = "\231\185\129\233\171\148\228\184\173\230\150\135" }
      for code, nm in pairs(native) do
         if names[code] == nil then
            fail("Locale.List() has no entry for " .. code)
         elseif names[code] ~= nm then
            report(rel, 0, "warn", "locale-api", ("Locale.List(): name of %s is '%s' (SPEC: native name '%s')"):format(
               code, tostring(names[code]), nm))
         end
      end
   end

   -- Zustand zuruecksetzen
   try(Loc.Set, "enUS")
end

if framework_ok then
   smoke_tests()
end

-- ---------------------------------------------------------------------------
-- Ausgabe
-- ---------------------------------------------------------------------------

table.sort(issues, function(a, b)
   if a.file ~= b.file then return a.file < b.file end
   if a.line ~= b.line then return a.line < b.line end
   if a.rule ~= b.rule then return a.rule < b.rule end
   return a.seq < b.seq
end)

local MAX_PER_RULE = opt.verbose and 1000000 or 8
local totals, running = {}, {}
for _, it in ipairs(issues) do
   local key = it.file .. "\0" .. it.rule
   totals[key] = (totals[key] or 0) + 1
end
for _, it in ipairs(issues) do
   local key = it.file .. "\0" .. it.rule
   running[key] = (running[key] or 0) + 1
   local hidden = (opt.quiet and it.sev ~= "error") or (it.sev == "info" and not opt.verbose)
   if running[key] <= MAX_PER_RULE and not hidden then
      local loc = it.line > 0 and (it.file .. ":" .. it.line) or it.file
      print(("%s: %s [%s] %s"):format(loc, it.sev == "error" and "error" or (it.sev == "info" and "info " or "warn "),
         it.rule, it.msg))
      if running[key] == MAX_PER_RULE and totals[key] > MAX_PER_RULE then
         print(("%s: ...    [%s] and %d more (use -v to list all)"):format(it.file, it.rule, totals[key] - MAX_PER_RULE))
      end
   end
end

if not opt.quiet then
   local n_en = #en_keys
   print(("lint_locale: enUS %d keys in %d file(s)%s"):format(n_en, #en_files,
      framework_ok and "" or "  [framework not loaded]"))
   for _, line in ipairs(summary) do print("             " .. line) end
end
print(("lint_locale: %d error(s), %d warning(s)"):format(n_error, n_warn))

os.exit(n_error == 0 and 0 or 1)
