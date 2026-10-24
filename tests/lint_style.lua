-- tests/lint_style.lua
-- ---------------------------------------------------------------------------
-- Stil-/Kompatibilitaets-Linter fuer das Transmog-Addon (WoW 3.3.5a, Lua 5.1).
--
-- LuaJIT (und damit jedes `luajit -bl`) akzeptiert mehr als Lua 5.1 in WoW:
-- goto, Bit-Operatoren, \x-Escapes, 0b101, 1ULL ... Dieser Linter zerlegt jede
-- Datei mit einem kleinen Tokenizer (Kommentare und Strings sind damit
-- ausgeblendet) und meldet alles, was in WoW 3.3.5a nicht laeuft:
--   * Lua-5.2+-Syntax: goto, ::label::, //, & | ~ << >>, \x \z \u, 0b/ULL/Hex-Float
--   * Lua-5.2+-Bibliothek: table.unpack/pack/move, math.type, utf8, _ENV, string.pack
--   * nicht vorhandenes 3.3.5a-API: SetSize, SetShown, SetColorTexture, C_Timer,
--     Mixin, BackdropTemplate, GET_ITEM_INFO_RECEIVED ...
--   * implizite Handler-Globals (this, arg1..arg9), xpcall mit Argumenten,
--     RegisterAddonMessagePrefix ohne Guard, string.format("%i"), "%1$s"
--   * Datei-Hygiene: BOM, CRLF, Tabs, Leerraum am Zeilenende, ungueltiges UTF-8,
--     Zeilen > 160 Zeichen (Warnung), fehlender Zeilenumbruch am Ende (Warnung)
--   * TOC: jede gelistete Datei existiert (Gross-/Kleinschreibung exakt), jede
--     Lua-Datei ausser tests/ steht in der TOC, SavedVariables, Reihenfolge
--   * XML: Transmog.xml und Bindings.xml sind wohlgeformt
--
-- Aufruf (aus dem Addon-Verzeichnis, mit luajit):
--    luajit tests/lint_style.lua [Optionen] [Datei.lua ...]
--
-- Optionen:
--    --root DIR   Addon-Verzeichnis (Standard: Elternverzeichnis von tests/)
--    --no-toc     TOC- und XML-Pruefungen auslassen
--    --partial    Arbeitsstand: in der TOC gelistete, aber noch fehlende Dateien
--                 sind nur Warnungen (fuer parallel entstehende Module)
--    -v           alle Meldungen ausgeben (sonst je Regel und Datei gekuerzt)
--    -q           nur Fehler und Summe
--    -h, --help   diese Hilfe
-- Mit expliziten Dateien (auch aus tests/) werden nur die Dateipruefungen gemacht.
--
-- Unterdrueckung (nur in begruendeten Ausnahmefaellen): ein Kommentar in der
-- selben Zeile mit  lint:allow(regel1, regel2)  schaltet diese Regeln fuer die
-- Zeile ab. Regelnamen stehen in eckigen Klammern in der Ausgabe.
--
-- Exit-Code: 0 = keine Fehler (Warnungen moeglich), 1 = Fehler, 2 = Aufrufproblem.
-- ---------------------------------------------------------------------------

local function die(msg)
   io.stderr:write("lint_style: " .. msg .. "\n")
   os.exit(2)
end

-- ---------------------------------------------------------------------------
-- Aufruf
-- ---------------------------------------------------------------------------

local opt = { root = nil, toc = true, verbose = false, quiet = false, partial = false }
local explicit = {}

do
   local i = 1
   while arg[i] do
      local a = arg[i]
      if a == "--root" then
         i = i + 1
         opt.root = arg[i] or die("--root braucht ein Verzeichnis")
      elseif a == "--no-toc" then
         opt.toc = false
      elseif a == "--partial" then
         opt.partial = true
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
      elseif a:sub(1, 1) == "-" then
         die("unbekannte Option: " .. a)
      else
         explicit[#explicit + 1] = a
      end
      i = i + 1
   end
end

local SCRIPT_DIR = (arg[0] or ""):match("^(.*)/[^/]*$") or "."
local ROOT = opt.root or (SCRIPT_DIR .. "/..")
local MAX_PER_RULE = opt.verbose and 1000000 or 6   -- Meldungen je Regel und Datei

-- ---------------------------------------------------------------------------
-- kleine Helfer
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

local function list_files(root, pattern)
   local out = {}
   local p = io.popen("cd " .. shq(root) .. " && find . -type f -name " .. shq(pattern) .. " 2>/dev/null")
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

local function shell_ok(cmd)
   local r = os.execute(cmd)
   return r == 0 or r == true
end

-- ---------------------------------------------------------------------------
-- Meldungen
-- ---------------------------------------------------------------------------

local issues = {}      -- { file, line, sev, rule, msg }
local n_error, n_warn = 0, 0

local function report(file, line, sev, rule, msg)
   issues[#issues + 1] = { file = file, line = line or 0, sev = sev, rule = rule, msg = msg }
   if sev == "error" then n_error = n_error + 1 else n_warn = n_warn + 1 end
end

-- ---------------------------------------------------------------------------
-- UTF-8-Pruefung (strikt: keine Ueberlaenge, keine Surrogate, <= U+10FFFF)
-- ---------------------------------------------------------------------------

-- Gibt nil zurueck, wenn gueltig, sonst Bytezeiger des ersten Fehlers.
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
-- Tokenizer (Lua 5.1-Lexik; erkennt zusaetzlich, was 5.1 nicht kennt)
-- ---------------------------------------------------------------------------

local KEYWORDS = {}
for w in ([[and break do else elseif end false for function if in local nil not
            or repeat return then true until while]]):gmatch("%S+") do
   KEYWORDS[w] = true
end

local SIMPLE_ESCAPES = { a = true, b = true, f = true, n = true, r = true, t = true,
                         v = true, ["\\"] = true, ['"'] = true, ["'"] = true }

-- Rueckgabe: toks, comments, problems
--   toks      Array { t = "name"|"kw"|"num"|"str"|"op", v = Text, line = n, raw = Rohtext(str) }
--   comments  Array { line = n, text = ... }
--   problems  Array { line = n, rule = ..., msg = ..., sev = ... }
local function lex(src)
   local toks, comments, problems = {}, {}, {}
   local i, n, line = 1, #src, 1
   local skip_lines = {}   -- Zeilen innerhalb von Langstrings/Langkommentaren (fuer Einrueckung)

   local function problem(ln, rule, msg, sev)
      problems[#problems + 1] = { line = ln, rule = rule, msg = msg, sev = sev or "error" }
   end

   local function mark_lines(from, to)
      for l = from + 1, to do skip_lines[l] = true end
   end

   -- BOM ueberspringen (wird in lint_hygiene gemeldet) und Shebang-Zeile
   if src:sub(1, 3) == "\239\187\191" then i = 4 end
   if src:sub(i, i) == "#" then
      local e = src:find("\n", 1, true) or n
      i = e
   end

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
         -- Kommentar
         local eq = src:match("^%-%-%[(=*)%[", i)
         if eq then
            local close = "]" .. eq .. "]"
            local s, e = src:find(close, i + 4 + #eq, true)
            if not s then
               problem(line, "syntax", "unfinished long comment")
               e = n
            end
            local body = src:sub(i, e)
            comments[#comments + 1] = { line = line, text = body }
            local lines = 0
            for _ in body:gmatch("\n") do lines = lines + 1 end
            mark_lines(line, line + lines)
            line = line + lines
            i = e + 1
         else
            local e = src:find("[\r\n]", i) or (n + 1)
            comments[#comments + 1] = { line = line, text = src:sub(i, e - 1) }
            i = e
         end

      elseif c == '"' or c == "'" then
         -- kurzer String
         local start_line = line
         local j = i + 1
         local closed = false
         while j <= n do
            local d = src:sub(j, j)
            if d == c then
               closed = true
               break
            elseif d == "\\" then
               local e = src:sub(j + 1, j + 1)
               if e == "\n" then
                  line = line + 1
                  j = j + 2
               elseif e == "\r" then
                  if src:sub(j + 2, j + 2) == "\n" then j = j + 1 end
                  line = line + 1
                  j = j + 2
               elseif e:find("^%d") then
                  local digits = src:match("^%d%d?%d?", j + 1)
                  if tonumber(digits) > 255 then
                     problem(line, "escape", "decimal escape \\" .. digits .. " too large")
                  end
                  j = j + 1 + #digits
               elseif e == "x" or e == "z" or e == "u" then
                  problem(line, "escape", "escape \\" .. e .. " is not valid in Lua 5.1 (WoW yields the plain letter '" .. e .. "')")
                  j = j + 2
               elseif SIMPLE_ESCAPES[e] then
                  j = j + 2
               elseif e == "" then
                  j = j + 1
               else
                  problem(line, "escape", "unknown escape \\" .. e .. " (invalid in LuaJIT, a plain '" .. e .. "' in Lua 5.1)")
                  j = j + 2
               end
            elseif d == "\n" or d == "\r" then
               break
            else
               j = j + 1
            end
         end
         if not closed then
            problem(start_line, "syntax", "unfinished string")
            j = math.min(j, n)
         end
         toks[#toks + 1] = { t = "str", v = src:sub(i + 1, j - 1), raw = src:sub(i + 1, j - 1), line = start_line }
         i = j + 1

      elseif c == "[" and src:find("^%[=*%[", i) then
         -- Langstring
         local eq = src:match("^%[(=*)%[", i)
         local close = "]" .. eq .. "]"
         local s, e = src:find(close, i + 2 + #eq, true)
         if not s then
            problem(line, "syntax", "unfinished long string")
            s, e = n + 1, n
         end
         local body = src:sub(i + 2 + #eq, s - 1)
         toks[#toks + 1] = { t = "str", v = body, raw = body, line = line, long = true }
         local lines = 0
         for _ in src:sub(i, e):gmatch("\n") do lines = lines + 1 end
         mark_lines(line, line + lines)
         line = line + lines
         i = e + 1

      elseif c:find("^%d") or (c == "." and src:find("^%.%d", i)) then
         -- Zahl
         local s, e = src:find("^0[xX][%w_.]*", i)
         local hex = s ~= nil
         if not s then s, e = src:find("^%.?%d[%w_.]*", i) end
         local text = src:sub(s, e)
         -- Exponent mit Vorzeichen (1e+5, 0x1p-3)
         local last = text:sub(-1)
         if ((not hex and (last == "e" or last == "E")) or (hex and (last == "p" or last == "P")))
            and src:sub(e + 1, e + 1):find("^[%+%-]") then
            local s2, e2 = src:find("^[%+%-][%w_]*", e + 1)
            if s2 then
               text = text .. src:sub(s2, e2)
               e = e2
            end
         end
         local ok51 = text:find("^%d+%.?%d*$") or text:find("^%.%d+$")
            or text:find("^%d+%.?%d*[eE][%+%-]?%d+$") or text:find("^%.%d+[eE][%+%-]?%d+$")
            or text:find("^0[xX]%x+$")
         if not ok51 then
            problem(line, "number", "number literal '" .. text .. "' is not valid in Lua 5.1 (0b.., LL/ULL, i, hex floats, '_')")
         end
         toks[#toks + 1] = { t = "num", v = text, line = line }
         i = e + 1

      elseif c:find("^[%a_]") then
         local s, e = src:find("^[%a_][%w_]*", i)
         local word = src:sub(s, e)
         toks[#toks + 1] = { t = KEYWORDS[word] and "kw" or "name", v = word, line = line }
         i = e + 1

      else
         -- Operatoren
         local three = src:sub(i, i + 2)
         local two = src:sub(i, i + 1)
         local op
         if three == "..." then
            op = three
         elseif two == "==" or two == "~=" or two == "<=" or two == ">=" or two == ".."
            or two == "::" or two == "//" or two == "<<" or two == ">>" then
            op = two
         elseif c:find("^[%+%-%*/%%%^#<>=%(%){}%[%];:,%.&|~]") then
            op = c
         end
         if op then
            toks[#toks + 1] = { t = "op", v = op, line = line }
            i = i + #op
         else
            if c:byte() >= 0x80 then
               problem(line, "nonascii-code", "non-ASCII character outside of strings/comments")
               -- gesamte UTF-8-Folge ueberspringen
               local _, e = src:find("^[\128-\191]*", i + 1)
               i = (e or i) + 1
            else
               problem(line, "syntax", ("illegal character '%s' (byte %d)"):format(c, c:byte()))
               i = i + 1
            end
         end
      end
   end

   return toks, comments, problems, skip_lines
end

-- ---------------------------------------------------------------------------
-- Regeltabellen
-- ---------------------------------------------------------------------------

-- Namen, die es in 3.3.5a nicht gibt (Treffer an jeder Stelle im Code, auch als
-- Methode/Feld).
local NO_API = {
   SetSize = "Frame:SetSize does not exist in 3.3.5a (use SetWidth + SetHeight)",
   GetSize = "Region:GetSize does not exist in 3.3.5a (use GetWidth/GetHeight)",
   SetShown = "Frame:SetShown does not exist in 3.3.5a (use Show()/Hide())",
   SetColorTexture = "Texture:SetColorTexture does not exist in 3.3.5a (use SetTexture(r, g, b, a))",
   SetWordWrap = "FontString:SetWordWrap does not exist in 3.3.5a",
   SetMaxLines = "FontString:SetMaxLines does not exist in 3.3.5a",
   GetRect = "Region:GetRect does not exist in 3.3.5a (use GetLeft/GetBottom/GetWidth/GetHeight)",
   C_Timer = "C_Timer does not exist in 3.3.5a (use Util.After)",
   C_Item = "C_Item does not exist in 3.3.5a",
   Mixin = "Mixin does not exist in 3.3.5a",
   CreateFromMixins = "CreateFromMixins does not exist in 3.3.5a",
   GetItemInfoInstant = "GetItemInfoInstant does not exist in 3.3.5a (use Items.Info)",
   BackdropTemplateMixin = "BackdropTemplateMixin does not exist in 3.3.5a (SetBackdrop is native)",
   BackdropTemplate = "BackdropTemplate does not exist in 3.3.5a (SetBackdrop is native)",
   GET_ITEM_INFO_RECEIVED = "GET_ITEM_INFO_RECEIVED does not exist in 3.3.5a (poll GetItemInfo)",
   utf8 = "no utf8 library in Lua 5.1",
   _ENV = "_ENV does not exist in Lua 5.1",
   bit32 = "no bit32 in Lua 5.1 (WoW provides the bit library)",
   rawlen = "rawlen does not exist in Lua 5.1",
}

-- Retail-/Lua-5.2-Namen, die nur als GLOBALE Namen verboten sind. Ein Feld gleichen
-- Namens in einer eigenen Tabelle (Util.Mixin) waere erlaubt, ausser es ist _G.Name.
local GLOBAL_ONLY = {
   C_Timer = true, C_Item = true, Mixin = true, CreateFromMixins = true, GetItemInfoInstant = true,
   BackdropTemplateMixin = true, BackdropTemplate = true, utf8 = true, _ENV = true, bit32 = true,
   rawlen = true, GET_ITEM_INFO_RECEIVED = true,
}

-- Davon werden auch String-Literale geprueft (RegisterEvent-Name, Template-Name).
local STRING_NO_API = { "GET_ITEM_INFO_RECEIVED", "BackdropTemplate" }

-- Wahrscheinlich nicht in 3.3.5a (Cataclysm oder neuer): nur Warnung.
local MAYBE_NO_API = {
   SetEnabled = "Button:SetEnabled is not in 3.3.5a (use Enable()/Disable() or Skin's SetEnabledState)",
   SetAtlas = "atlases do not exist in 3.3.5a",
   SetPropagateKeyboardInput = "SetPropagateKeyboardInput is not in 3.3.5a",
   SetIgnoreParentScale = "SetIgnoreParentScale is not in 3.3.5a",
   SetIgnoreParentAlpha = "SetIgnoreParentAlpha is not in 3.3.5a",
   SetFixedFrameStrata = "SetFixedFrameStrata is not in 3.3.5a",
   SetFixedFrameLevel = "SetFixedFrameLevel is not in 3.3.5a",
   SetResizeBounds = "SetResizeBounds is not in 3.3.5a (use SetMinResize/SetMaxResize)",
   SetObeyStepOnDrag = "Slider:SetObeyStepOnDrag is not in 3.3.5a",
   SetClipsChildren = "Frame:SetClipsChildren is not in 3.3.5a (clip with a ScrollFrame)",
   GetUnboundedStringWidth = "GetUnboundedStringWidth is not in 3.3.5a",
   SetSnapToPixelGrid = "SetSnapToPixelGrid is not in 3.3.5a",
   SetTexelSnappingBias = "SetTexelSnappingBias is not in 3.3.5a",
   CreateAtlasMarkup = "CreateAtlasMarkup is not in 3.3.5a",
   CreateTextureMarkup = "CreateTextureMarkup is not in 3.3.5a",
}

-- table.xxx / math.xxx / string.xxx / coroutine.xxx, die erst ab Lua 5.2/5.3 existieren.
local NO_LIB_FUNC = {
   table = { unpack = "table.unpack (use the global unpack)", pack = "table.pack (use { ... } and select('#', ...))",
             move = "table.move", },
   math = { type = "math.type", tointeger = "math.tointeger", ult = "math.ult" },
   string = { pack = "string.pack", unpack = "string.unpack", packsize = "string.packsize" },
   coroutine = { isyieldable = "coroutine.isyieldable", close = "coroutine.close" },
}

-- WoW-eigene Stringhelfer: als Methode auf Strings gibt es sie in 3.3.5a nicht.
local NO_STRING_METHOD = { split = "strsplit/Util.Split", join = "strjoin", trim = "strtrim/Util.Trim",
                           strsplit = "strsplit", strjoin = "strjoin", strtrim = "strtrim" }

-- ---------------------------------------------------------------------------
-- Pruefungen je Datei
-- ---------------------------------------------------------------------------

-- Zaehlt Argumente des Aufrufs, dessen "(" bei toks[open] steht. Rueckgabe: Anzahl
-- oberster Argumente (0 bei "()") oder nil, wenn die Klammer nicht schliesst.
local function count_call_args(toks, open)
   local depth, block = 0, 0
   local args = 0
   local seen_any = false
   local j = open + 1
   while toks[j] do
      local tk = toks[j]
      local v = tk.v
      if tk.t == "op" then
         if v == "(" or v == "{" or v == "[" then
            depth = depth + 1
            seen_any = true
         elseif v == ")" or v == "}" or v == "]" then
            if depth == 0 and v == ")" then
               return seen_any and (args + 1) or 0
            end
            depth = depth - 1
         elseif v == "," and depth == 0 and block == 0 then
            args = args + 1
         else
            seen_any = true
         end
      elseif tk.t == "kw" then
         if v == "function" or v == "if" or v == "do" or v == "repeat" then
            block = block + 1
         elseif v == "end" or v == "until" then
            block = block - 1
         end
         seen_any = true
      else
         seen_any = true
      end
      j = j + 1
   end
   return nil
end

-- true, wenn toks[i] ("RegisterAddonMessagePrefix") eine reine Abfrage ist
-- (if X then / if not X / and / or / type(X)==...) und kein Aufruf/Wert.
local function is_guard_test(toks, i)
   local prev, prev2 = toks[i - 1], toks[i - 2]
   local nxt = toks[i + 1]
   if prev and prev.t == "kw" and (prev.v == "if" or prev.v == "elseif" or prev.v == "not" or prev.v == "and"
      or prev.v == "or" or prev.v == "while") then
      return true
   end
   if prev and prev.v == "(" and prev2 and (prev2.v == "type" or prev2.v == "pcall") then return true end
   if prev and prev.v == "." and prev2 and prev2.v == "_G" then
      local p3 = toks[i - 3]
      if p3 and p3.t == "kw" then return true end
      return false
   end
   if nxt and nxt.t == "kw" and (nxt.v == "then" or nxt.v == "and" or nxt.v == "or") then return true end
   if nxt and nxt.t == "op" and (nxt.v == "==" or nxt.v == "~=") then return true end
   return false
end

local function lint_tokens(file, toks, allow)
   local function add(line, sev, rule, msg)
      if allow[line] and (allow[line][rule] or allow[line]["*"]) then return end
      report(file, line, sev, rule, msg)
   end

   local guard_lines = {}   -- Zeilen, in denen eine RegisterAddonMessagePrefix-Abfrage steht
   local in_label = false   -- zwischen den beiden "::" eines Labels (nur einmal melden)

   -- erster Durchlauf: Guard-Abfragen sammeln
   for i, tk in ipairs(toks) do
      if tk.t == "name" and tk.v == "RegisterAddonMessagePrefix" and is_guard_test(toks, i) then
         guard_lines[tk.line] = true
      end
   end

   local stack = {}         -- offene Klammern: "(" "{" "["
   for i, tk in ipairs(toks) do
      local t, v, line = tk.t, tk.v, tk.line
      local prev, nxt = toks[i - 1], toks[i + 1]
      local after_dot = prev and prev.t == "op" and (prev.v == "." or prev.v == ":")
      -- Schluessel eines Tabellenkonstruktors ({ Mixin = 1 }) ist ein Feldname, kein Global
      local is_key = t == "name" and stack[#stack] == "{" and nxt and nxt.v == "=" and prev
         and (prev.v == "{" or prev.v == "," or prev.v == ";")
      local field = after_dot or is_key

      if t == "op" then
         if v == "(" or v == "{" or v == "[" then
            stack[#stack + 1] = v
         elseif v == ")" or v == "}" or v == "]" then
            stack[#stack] = nil
         end
         if v == "::" then
            if not in_label then
               add(line, "error", "label", "'::' labels (goto) do not exist in Lua 5.1")
            end
            in_label = not in_label
         elseif v == "//" then
            add(line, "error", "intdiv", "'//' (integer division) does not exist in Lua 5.1")
         elseif v == "&" or v == "|" or v == "<<" or v == ">>" then
            add(line, "error", "bitop", "bit operator '" .. v .. "' does not exist in Lua 5.1 (use the bit library: bit.band, bit.bor ...)")
         elseif v == "~" then
            add(line, "error", "bitop", "'~' (xor/not operator) does not exist in Lua 5.1 (use bit.bxor/bit.bnot; '~=' is fine)")
         end

      elseif t == "name" then
         if v == "goto" and not after_dot then
            add(line, "error", "goto", "'goto' does not exist in Lua 5.1")
         end

         local via_g = after_dot and prev.v == "." and toks[i - 2] and toks[i - 2].v == "_G"
         local api = NO_API[v]
         if api and GLOBAL_ONLY[v] and field and not via_g then api = nil end
         if api then
            add(line, "error", "no-api", api)
         end
         if v:find("^C_%u") and not api and (not field or via_g) then
            add(line, "error", "no-api", v .. ": retail 'C_*' namespaces do not exist in 3.3.5a")
         end
         local maybe = MAYBE_NO_API[v]
         if maybe then
            add(line, "warn", "maybe-no-api", maybe)
         end

         if not field and (v == "this" or v:find("^arg%d$")) then
            add(line, "error", "implicit-global", "'" .. v .. "' is the implicit global of old UI handlers; use explicit parameters (self, event, ...)")
         end

         -- table.unpack, math.type ...
         if nxt and nxt.v == "." and toks[i + 2] and toks[i + 2].t == "name" and not after_dot then
            local lib = NO_LIB_FUNC[v]
            local fname = toks[i + 2].v
            if lib and lib[fname] then
               add(line, "error", "lua52-lib", lib[fname] .. " does not exist in Lua 5.1")
            end
         end

         -- Methodenaufruf auf WoW-eigenen Stringhelfern
         if prev and prev.v == ":" and NO_STRING_METHOD[v] and nxt and nxt.v == "(" then
            add(line, "error", "string-method",
               "string method ':" .. v .. "()' does not exist in 3.3.5a; use " .. NO_STRING_METHOD[v])
         end

         -- Guard fuer RegisterAddonMessagePrefix
         if v == "RegisterAddonMessagePrefix" and not is_guard_test(toks, i) then
            if not (guard_lines[line] or guard_lines[line - 1]) then
               add(line, "error", "prefix-guard",
                  "RegisterAddonMessagePrefix does not exist in 3.3.5a; guard it with 'if RegisterAddonMessagePrefix then'")
            end
         end

         -- xpcall mit Argumenten: Lua 5.1 reicht sie nicht an die Funktion weiter
         if v == "xpcall" and nxt and nxt.v == "(" and not after_dot then
            local n = count_call_args(toks, i + 1)
            if n and n > 2 then
               add(line, "error", "xpcall-args",
                  "xpcall with extra arguments: Lua 5.1 drops them (wrap the call in a closure)")
            end
         end

         -- dynamische Global-Schreibzugriffe: _G.x = ..., _G["x"] = ..., rawset(_G, ...)
         if v == "_G" and not after_dot and nxt and nxt.t == "op" then
            if nxt.v == "." and toks[i + 2] and toks[i + 3] and toks[i + 3].v == "=" then
               add(line, "warn", "dyn-global-write", "assignment to _G." .. toks[i + 2].v .. " creates a global (allowed only for Blizzard-defined names)")
            elseif nxt.v == "[" then
               -- passende "]" suchen
               local depth, j = 0, i + 1
               while toks[j] do
                  if toks[j].v == "[" then depth = depth + 1
                  elseif toks[j].v == "]" then
                     depth = depth - 1
                     if depth == 0 then break end
                  end
                  j = j + 1
               end
               if toks[j] and toks[j + 1] and toks[j + 1].v == "=" then
                  add(line, "warn", "dyn-global-write", "assignment to _G[...] creates a global dynamically")
               end
            end
         end
         if v == "rawset" and nxt and nxt.v == "(" and toks[i + 2] and toks[i + 2].v == "_G" then
            add(line, "warn", "dyn-global-write", "rawset(_G, ...) creates a global dynamically")
         end
         if (v == "setfenv" or v == "getfenv") and not after_dot then
            add(line, "warn", "setfenv", v .. " changes/inspects function environments; avoid in addon code")
         end

      elseif t == "str" then
         local s = tk.raw
         -- Strings, die auf nicht vorhandene Namen zeigen (RegisterEvent, CreateFrame-Template)
         for _, name in ipairs(STRING_NO_API) do
            if s:find(name, 1, true) then
               add(line, "error", "no-api", "string '" .. name .. "': " .. NO_API[name])
            end
         end
         -- Formatplatzhalter
         local p = 1
         while true do
            local pos = s:find("%", p, true)
            if not pos then break end
            local nextc = s:sub(pos + 1, pos + 1)
            if nextc == "%" then
               p = pos + 2
            else
               local spec = s:match("^[%-%+ #0]*%d*%.?%d*(%a?)", pos + 1)
               if s:find("^%d+%$", pos + 1) then
                  add(line, "error", "format-positional", "positional placeholder (%n$) is not allowed; use sequential %s/%d")
               elseif spec == "i" then
                  add(line, "error", "format-i", "format placeholder '%i' is not allowed (use %d)")
               end
               p = pos + 1
            end
         end
      end
   end
end

-- Dateiebene: Bytes, Zeilen, Whitespace -------------------------------------------

local function lint_hygiene(file, src, skip_lines, toks_first_on_line)
   local function add(line, sev, rule, msg) report(file, line, sev, rule, msg) end

   if src:sub(1, 3) == "\239\187\191" then
      add(1, "error", "bom", "file starts with a UTF-8 BOM (WoW's Lua does not skip it)")
   end

   local bad = utf8_error(src)
   if bad then
      add(line_of(src, bad), "error", "utf8", "invalid UTF-8 byte sequence (byte offset " .. bad .. ")")
   end

   if src:find("\r", 1, true) then
      local pos = src:find("\r", 1, true)
      add(line_of(src, pos), "error", "crlf", "CR/CRLF line ending (use LF)")
   end

   if #src > 0 and src:sub(-1) ~= "\n" then
      add(line_of(src, #src), "warn", "final-newline", "file does not end with a newline")
   end

   local lineno = 0
   for text in (src .. (src:sub(-1) == "\n" and "" or "\n")):gmatch("([^\n]*)\n") do
      lineno = lineno + 1
      local body = text:gsub("\r$", "")
      if body:find("\t", 1, true) then
         add(lineno, "error", "tab", "tab character (use 3 spaces; \\t inside strings)")
      end
      if body:find("[ \t]+$") then
         add(lineno, "error", "trailing-ws", "trailing whitespace")
      end
      -- Zeichen (nicht Bytes) zaehlen
      local _, cont = body:gsub("[\128-\191]", "")
      local chars = #body - cont
      if chars > 160 then
         add(lineno, "warn", "line-length", "line has " .. chars .. " characters (> 160)")
      end
      if not skip_lines[lineno] then
         local first = toks_first_on_line[lineno]
         if first and (first == "end" or first == "else" or first == "elseif" or first == "until") then
            local lead = #(body:match("^( *)") or "")
            if lead % 3 ~= 0 and not body:find("^\t") then
               add(lineno, "warn", "indent", "indentation of " .. lead .. " spaces is not a multiple of 3")
            end
         end
      end
   end
end

local function lint_file(rel, path)
   local src = read_file(path)
   if not src then
      report(rel, 0, "error", "io", "file not readable")
      return
   end
   local toks, comments, problems, skip_lines = lex(src)

   -- erlaubte Ausnahmen je Zeile
   local allow = {}
   for _, cm in ipairs(comments) do
      local list = cm.text:match("lint:allow%(([^)]*)%)")
      if list then
         allow[cm.line] = allow[cm.line] or {}
         for rule in list:gmatch("[%w%-%*_]+") do allow[cm.line][rule] = true end
      end
   end

   for _, p in ipairs(problems) do
      if not (allow[p.line] and (allow[p.line][p.rule] or allow[p.line]["*"])) then
         report(rel, p.line, p.sev, p.rule, p.msg)
      end
   end

   local first_on_line = {}
   for _, tk in ipairs(toks) do
      if first_on_line[tk.line] == nil then first_on_line[tk.line] = tk.v end
   end

   lint_hygiene(rel, src, skip_lines, first_on_line)
   lint_tokens(rel, toks, allow)
   return src
end

-- ---------------------------------------------------------------------------
-- TOC- und XML-Pruefungen
-- ---------------------------------------------------------------------------

local function xml_wellformed(path)
   if shell_ok("command -v xmllint >/dev/null 2>&1") then
      local p = io.popen("xmllint --noout " .. shq(path) .. " 2>&1")
      if p then
         local out = p:read("*a")
         p:close()
         if out and out:find("%S") then
            return false, (out:match("[^\n]+") or out)
         end
         return true
      end
   end
   if shell_ok("command -v python3 >/dev/null 2>&1") then
      local p = io.popen("python3 -I -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' " .. shq(path) .. " 2>&1")
      if p then
         local out = p:read("*a")
         p:close()
         if out and out:find("%S") then
            local last
            for l in out:gmatch("[^\n]+") do last = l end
            return false, last or out
         end
         return true
      end
   end
   return nil, "neither xmllint nor python3 available"
end

local function lint_toc(lua_files, all_files)
   local toc_rel = "Transmog.toc"
   local toc_path = ROOT .. "/" .. toc_rel
   local text = read_file(toc_path)
   if not text then
      report(toc_rel, 0, "error", "toc-missing", "Transmog.toc not found in " .. ROOT)
      return
   end

   if text:sub(1, 3) == "\239\187\191" then
      report(toc_rel, 1, "error", "bom", "TOC starts with a UTF-8 BOM (first '## Interface' line is lost)")
   end
   if text:find("\r", 1, true) then
      report(toc_rel, line_of(text, text:find("\r", 1, true)), "warn", "crlf", "CR/CRLF line ending in TOC (use LF)")
   end

   -- Dateisystem in Kleinschreibung (fuer Gross-/Kleinschreibungs-Pruefung)
   local on_disk, on_disk_lower = {}, {}
   for _, f in ipairs(all_files) do
      on_disk[f] = true
      on_disk_lower[f:lower()] = f
   end

   local meta, entries = {}, {}
   local lineno = 0
   for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
      lineno = lineno + 1
      local l = raw:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if l:sub(1, 2) == "##" then
         local k, val = l:match("^##%s*([^:]-)%s*:%s*(.-)%s*$")
         if k then meta[k] = val end
      elseif l ~= "" and l:sub(1, 1) ~= "#" then
         entries[#entries + 1] = { name = l, line = lineno }
      end
   end

   if meta["Interface"] ~= "30300" then
      report(toc_rel, 0, "error", "toc-interface", "## Interface must be 30300 (found: " .. tostring(meta["Interface"]) .. ")")
   end
   if not meta["Title"] or meta["Title"] == "" then
      report(toc_rel, 0, "error", "toc-title", "## Title is missing")
   end

   local function has_var(key, var)
      for v in (meta[key] or ""):gmatch("[^,%s]+") do
         if v == var then return true end
      end
      return false
   end
   if not has_var("SavedVariables", "TransmogGlobalDB") then
      report(toc_rel, 0, "error", "toc-savedvars", "## SavedVariables must list TransmogGlobalDB")
   end
   for _, var in ipairs({ "TransmogDB", "transmogOutfits", "transmogSettings" }) do
      if not has_var("SavedVariablesPerCharacter", var) then
         report(toc_rel, 0, "error", "toc-savedvars", "## SavedVariablesPerCharacter must list " .. var)
      end
   end

   -- Eintraege pruefen
   local listed = {}          -- normalisierter Pfad -> Zeile
   local lua_order = {}       -- alle gelisteten Lua-Dateien in TOC-Reihenfolge
   for _, e in ipairs(entries) do
      local norm = e.name:gsub("\\", "/")
      if e.name:find("/", 1, true) then
         report(toc_rel, e.line, "warn", "toc-slash", "use backslashes in TOC paths: " .. e.name)
      end
      if listed[norm] then
         report(toc_rel, e.line, "error", "toc-duplicate", "listed twice: " .. e.name)
      end
      listed[norm] = e.line
      if norm:lower():find("%.lua$") then lua_order[#lua_order + 1] = norm end
      if on_disk[norm] then
         -- vorhanden, alles in Ordnung
      elseif on_disk_lower[norm:lower()] then
         report(toc_rel, e.line, "error", "toc-case",
            ("case mismatch: TOC '%s' vs file '%s' (breaks on case-sensitive file systems)"):format(e.name, on_disk_lower[norm:lower()]))
      else
         report(toc_rel, e.line, opt.partial and "warn" or "error", "toc-missing",
            "listed file does not exist: " .. e.name)
      end
   end

   -- jede Lua-Datei muss in der TOC stehen
   for _, rel in ipairs(lua_files) do
      if not listed[rel] then
         report(rel, 0, "error", "toc-unlisted", "Lua file is not listed in Transmog.toc")
      end
   end
   -- XML-Dateien (Bindings.xml wird auch ohne TOC geladen, die Spezifikation listet sie trotzdem)
   for _, rel in ipairs(all_files) do
      if rel:lower():find("%.xml$") and not excluded(rel) and not listed[rel] then
         report(rel, 0, "warn", "toc-unlisted", "XML file is not listed in Transmog.toc")
      end
   end

   -- Reihenfolge-Invarianten
   if #lua_order > 0 and listed["Locales/Locale.lua"] and lua_order[1] ~= "Locales/Locale.lua" then
      report(toc_rel, listed["Locales/Locale.lua"], "error", "toc-order",
         "Locales\\Locale.lua creates the Transmog table and must be the first Lua file (first is " .. lua_order[1] .. ")")
   end
   if #lua_order > 0 and listed["Core/Boot.lua"] and lua_order[#lua_order] ~= "Core/Boot.lua" then
      report(toc_rel, listed["Core/Boot.lua"], "warn", "toc-order",
         "Core\\Boot.lua should be the last Lua file (last is " .. lua_order[#lua_order] .. ")")
   end
   if listed["Core/Init.lua"] and listed["Core/Util.lua"] and listed["Core/Util.lua"] < listed["Core/Init.lua"] then
      report(toc_rel, listed["Core/Util.lua"], "error", "toc-order", "Core\\Init.lua must come before Core\\Util.lua")
   end
end

local function lint_xml(all_files)
   local lua_text_cache
   local function all_lua_text()
      if lua_text_cache then return lua_text_cache end
      local parts = {}
      for _, rel in ipairs(all_files) do
         if rel:lower():find("%.lua$") and not excluded(rel) then
            parts[#parts + 1] = read_file(ROOT .. "/" .. rel) or ""
         end
      end
      lua_text_cache = table.concat(parts, "\n")
      return lua_text_cache
   end

   local warned_skip = false
   for _, rel in ipairs(all_files) do
      if rel:lower():find("%.xml$") and not excluded(rel) then
         local path = ROOT .. "/" .. rel
         local xml = read_file(path) or ""
         if xml:sub(1, 3) == "\239\187\191" then
            report(rel, 1, "error", "bom", "XML starts with a UTF-8 BOM")
         end
         local ok, err = xml_wellformed(path)
         if ok == false then
            report(rel, 0, "error", "xml", "not well-formed: " .. tostring(err))
         elseif ok == nil and not warned_skip then
            warned_skip = true
            report(rel, 0, "warn", "xml-skipped", "well-formedness not checked: " .. tostring(err))
         end
         if ok ~= false then
            local base = rel:match("([^/]+)$")
            if base == "Transmog.xml" then
               if not xml:find("<Ui[%s>]") then
                  report(rel, 0, "error", "xml-root", "root element must be <Ui>")
               end
               for _, tpl in ipairs({ "TransmogCellModelTemplate", "TransmogPreviewModelTemplate" }) do
                  if not xml:find('name="' .. tpl .. '"', 1, true) then
                     report(rel, 0, "error", "xml-template", "template " .. tpl .. " is not defined")
                  end
               end
            elseif base == "Bindings.xml" then
               if not xml:find("<Bindings", 1, true) then
                  report(rel, 0, "error", "xml-root", "root element must be <Bindings>")
               end
               if not xml:find('name="TRANSMOG_TOGGLE"', 1, true) then
                  report(rel, 0, "error", "xml-binding", "binding TRANSMOG_TOGGLE is not defined")
               end
               -- Anzeigenamen: BINDING_NAME_<name> / BINDING_HEADER_<header> irgendwo im Code
               local code = all_lua_text()
               for name in xml:gmatch('<Binding[^>]-name="([^"]+)"') do
                  if not code:find("BINDING_NAME_" .. name, 1, true) then
                     report(rel, 0, "warn", "binding-name", "no BINDING_NAME_" .. name .. " defined in the Lua files")
                  end
               end
               for header in xml:gmatch('<Binding[^>]-header="([^"]+)"') do
                  if not code:find("BINDING_HEADER_" .. header, 1, true) then
                     report(rel, 0, "warn", "binding-header", "no BINDING_HEADER_" .. header .. " defined in the Lua files")
                  end
               end
            end
         end
      end
   end
end

-- ---------------------------------------------------------------------------
-- Hauptlauf
-- ---------------------------------------------------------------------------

local files = {}
local use_toc = false
if #explicit > 0 then
   for _, p in ipairs(explicit) do files[#files + 1] = { rel = p, path = p } end
else
   for _, rel in ipairs(list_files(ROOT, "*.lua")) do
      if not excluded(rel) then
         files[#files + 1] = { rel = rel, path = ROOT .. "/" .. rel }
      end
   end
   use_toc = opt.toc
end

for _, f in ipairs(files) do
   lint_file(f.rel, f.path)
end

if use_toc then
   local all_files = {}
   do
      local p = io.popen("cd " .. shq(ROOT) .. " && find . -type f 2>/dev/null")
      if p then
         for l in p:lines() do all_files[#all_files + 1] = (l:gsub("^%./", "")) end
         p:close()
      end
      table.sort(all_files)
   end
   local lua_rel = {}
   for _, f in ipairs(files) do lua_rel[#lua_rel + 1] = f.rel end
   lint_toc(lua_rel, all_files)
   lint_xml(all_files)
end

-- Ausgabe ---------------------------------------------------------------------

table.sort(issues, function(a, b)
   if a.file ~= b.file then return a.file < b.file end
   if a.line ~= b.line then return a.line < b.line end
   if a.rule ~= b.rule then return a.rule < b.rule end
   return a.msg < b.msg
end)

-- je (Datei, Regel) auf MAX_PER_RULE Meldungen kuerzen
local totals = {}
for _, it in ipairs(issues) do
   local key = it.file .. "\0" .. it.rule
   totals[key] = (totals[key] or 0) + 1
end

local running = {}
for _, it in ipairs(issues) do
   local key = it.file .. "\0" .. it.rule
   running[key] = (running[key] or 0) + 1
   -- Meldungen zur TOC werden nie gekuerzt (fehlende Dateien sollen vollstaendig erscheinen)
   local limit = it.rule:find("^toc%-") and 1000000 or MAX_PER_RULE
   if running[key] <= limit and not (opt.quiet and it.sev ~= "error") then
      local loc = it.line > 0 and (it.file .. ":" .. it.line) or it.file
      print(("%s: %s [%s] %s"):format(loc, it.sev == "error" and "error" or "warn ", it.rule, it.msg))
      if running[key] == limit and totals[key] > limit then
         print(("%s: ...    [%s] and %d more (use -v to list all)"):format(
            it.file, it.rule, totals[key] - limit))
      end
   end
end

if not opt.quiet or n_error > 0 then
   print(("lint_style: %d Lua files, %d error(s), %d warning(s)"):format(#files, n_error, n_warn))
end

os.exit(n_error == 0 and 0 or 1)
