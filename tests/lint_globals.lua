-- tests/lint_globals.lua
-- ---------------------------------------------------------------------------
-- Globals-Linter fuer das Transmog-Addon (WoW 3.3.5a, Lua 5.1, Interface 30300).
--
-- Findet ueber das Bytecode-Listing (GGET = Lesen, GSET = Schreiben) jeden Zugriff
-- auf eine globale Variable, auch in verschachtelten Funktionen, und vergleicht
-- den Namen mit:
--   * Lua-5.1-Basis- und Standardbibliothek (nur, was WoW wirklich bereitstellt)
--   * tests/wow_api_allowlist.txt  (echtes 3.3.5a-API, Blizzard-Globalstrings)
--   * den Globals des Addons selbst (Transmog, TransmogDB, TransmogWindow, ...)
-- Alles andere ist ein Fehler: Lesen = unbekanntes Global / kein 3.3.5a-API,
-- Schreiben = versehentliches Global (nur Addon-eigene Namen duerfen geschrieben
-- werden).
--
-- Aufruf (aus dem Addon-Verzeichnis, mit luajit):
--    luajit tests/lint_globals.lua [Optionen] [Datei.lua ...]
--
-- Optionen:
--    --explain      alle benutzten Globals je Datei auflisten (statt nur Verstoesse)
--    --listing      Auswertung ueber das Textlisting von `luajit -bl` statt ueber
--                   jit.util; Zeilenangabe ist dann der Funktionsanfang
--    --root DIR     Addon-Verzeichnis (Standard: Elternverzeichnis von tests/)
--    --allowlist F  andere Allowlist-Datei (Standard: tests/wow_api_allowlist.txt)
--    -q             keine Fortschrittszeilen, nur Verstoesse und Summe
--    -h, --help     diese Hilfe
-- Ohne Dateiangaben werden alle *.lua unter DIR geprueft, ausser tests/,
-- Ordnern mit Punkt oder _lintfixtures und Dateien lint_fixture_*.lua.
--
-- Exit-Code: 0 = sauber, 1 = Verstoesse oder Syntaxfehler, 2 = Aufruf-/Umgebungsfehler.
-- ---------------------------------------------------------------------------

local function die(msg)
   io.stderr:write("lint_globals: " .. msg .. "\n")
   os.exit(2)
end

-- ---------------------------------------------------------------------------
-- Aufruf
-- ---------------------------------------------------------------------------

local opt = { explain = false, listing = false, quiet = false, root = nil, allowlist = nil }
local explicit = {}

do
   local i = 1
   while arg[i] do
      local a = arg[i]
      if a == "--explain" then
         opt.explain = true
      elseif a == "--listing" then
         opt.listing = true
      elseif a == "-q" or a == "--quiet" then
         opt.quiet = true
      elseif a == "--root" then
         i = i + 1
         opt.root = arg[i] or die("--root braucht ein Verzeichnis")
      elseif a == "--allowlist" then
         i = i + 1
         opt.allowlist = arg[i] or die("--allowlist braucht eine Datei")
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
local ALLOWLIST_PATH = opt.allowlist or (SCRIPT_DIR .. "/wow_api_allowlist.txt")
local LUAJIT = arg[-1] or "luajit"

-- ---------------------------------------------------------------------------
-- LuaJIT-Bytecode-Zugriff
-- ---------------------------------------------------------------------------

-- Genaue Zeilenangaben brauchen jit.util/jit.vmdef; fehlen sie (abgespeckte
-- LuaJIT-Pakete), wird automatisch das Textlisting von `luajit -bl` ausgewertet.
local okU, jutil = pcall(require, "jit.util")
local okV, vmdef = pcall(require, "jit.vmdef")
local okB, bit = pcall(require, "bit")
local INPROCESS = okU and okV and okB and type(jutil) == "table" and type(vmdef) == "table"
if not INPROCESS then
   if type(jit) ~= "table" then
      die("braucht LuaJIT. Aufruf: luajit tests/lint_globals.lua")
   end
   opt.listing = true
end

local funcinfo, funcbc, funck, band, shr, bcnames
if INPROCESS then
   funcinfo, funcbc, funck = jutil.funcinfo, jutil.funcbc, jutil.funck
   band, shr = bit.band, bit.rshift
   bcnames = vmdef.bcnames
end

-- ---------------------------------------------------------------------------
-- kleine Helfer
-- ---------------------------------------------------------------------------

local function shq(s)
   return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

-- Alle Dateien unter root, deren Name auf pattern passt (relative Pfade, sortiert).
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

-- true = Datei gehoert nicht zum Addon-Code (Tests, Fixtures, versteckte Ordner).
local function excluded(rel)
   if rel:find("^tests/") then return true end
   for seg in rel:gmatch("[^/]+") do
      if seg:sub(1, 1) == "." or seg == "_lintfixtures" or seg:find("^lint_fixture_") then
         return true
      end
   end
   return false
end

-- ---------------------------------------------------------------------------
-- Namenslisten
-- ---------------------------------------------------------------------------

-- Lua 5.1 Basis/Standardbibliothek, soweit WoW 3.3.5a sie bereitstellt.
-- NICHT dabei (in WoW entfernt): io, os, package, require, dofile, loadfile, load,
-- module, debug, newproxy ...
local LUA_NAMES = {}
for name in ([[
   _G _VERSION assert collectgarbage error gcinfo getfenv getmetatable ipairs
   loadstring next pairs pcall print rawequal rawget rawset select setfenv
   setmetatable tonumber tostring type unpack xpcall
   string table math coroutine bit
]]):gmatch("%S+") do
   LUA_NAMES[name] = true
end

-- Namen, die es in 3.3.5a nicht gibt, mit Hinweis (nur fuer die Fehlermeldung).
local KNOWN_BAD = {
   io = "no io library in WoW",
   os = "no os library in WoW (use date()/time()/GetTime())",
   package = "no package library in WoW",
   require = "no require in WoW (files are loaded via the TOC)",
   dofile = "not available in WoW",
   loadfile = "not available in WoW",
   load = "use loadstring()",
   module = "not available in WoW",
   debug = "no debug library in WoW (use debugstack()/geterrorhandler())",
   newproxy = "do not use newproxy",
   getglobal = "old Lua 4 accessor (does not exist in later clients; use _G[name])",
   setglobal = "old Lua 4 accessor (does not exist in later clients; use _G[name])",
   getn = "deprecated Lua 4 alias (use #t)",
   foreach = "deprecated Lua 4 alias (use pairs)",
   foreachi = "deprecated Lua 4 alias (use ipairs)",
   sort = "use table.sort",
   utf8 = "no utf8 library in Lua 5.1",
   bit32 = "no bit32 in Lua 5.1 (use the bit library)",
   rawlen = "Lua 5.2+ only",
   _ENV = "Lua 5.2+ only",
   this = "implicit global of old UI handlers (use the explicit self parameter)",
   event = "implicit global of old UI handlers (use the explicit event parameter)",
   Mixin = "retail API (not in 3.3.5a)",
   CreateFromMixins = "retail API (not in 3.3.5a)",
   GetItemInfoInstant = "retail API (not in 3.3.5a)",
   BackdropTemplateMixin = "retail API (not in 3.3.5a)",
   RegisterAddonMessagePrefix = "not in 3.3.5a (only with an 'if RegisterAddonMessagePrefix then' guard)",
}

-- Existiert in 3.3.5a NICHT, darf aber gelesen werden (Test auf nil); der Aufruf
-- selbst ist durch lint_style (Guard-Pruefung) geschuetzt.
local OPTIONAL = {
   RegisterAddonMessagePrefix = true,
   SetDesaturation = true,      -- alte globale Funktion; Texture:SetDesaturated ist der Weg, Abfrage genuegt
}

-- Globals, die das Addon selbst definiert (lesen UND schreiben erlaubt).
local ADDON_NAMES = {
   Transmog = true, TransmogDB = true, TransmogGlobalDB = true,
   transmogOutfits = true, transmogSettings = true, TransmogWindow = true,
   SLASH_TRANSMOG1 = true, SLASH_TRANSMOG2 = true,
   SLASH_TRANSMOGDEBUG1 = true, SLASH_TRANSMOGRESET1 = true,
   BINDING_HEADER_TRANSMOG = true, BINDING_NAME_TRANSMOG_TOGGLE = true,
}

-- Musterregeln fuer Addon-eigene Namen (benannte Frames, Slash-/Binding-Globals).
local ADDON_PATTERNS = {
   "^Transmog%u",                         -- benannte Frames: TransmogWindow, TransmogScanTooltip ...
   "^SLASH_TRANSMOG%u*%d+$",              -- SLASH_TRANSMOG1, SLASH_TRANSMOGDEBUG1 ...
   "^BINDING_HEADER_TRANSMOG[%u%d_]*$",
   "^BINDING_NAME_TRANSMOG_[%u%d_]+$",
}

local function is_addon_name(name)
   if ADDON_NAMES[name] then return true end
   for _, pat in ipairs(ADDON_PATTERNS) do
      if name:find(pat) then return true end
   end
   return false
end

-- ---------------------------------------------------------------------------
-- Allowlist laden
-- ---------------------------------------------------------------------------

local WOW_NAMES = {}       -- exakte Namen
local WOW_PREFIXES = {}    -- "PREFIX*"-Zeilen
local WOW_LOWER = {}       -- lower(name) -> name (fuer "meinten Sie ...")
local allowlist_count = 0

do
   local f = io.open(ALLOWLIST_PATH, "r")
   if not f then die("Allowlist nicht gefunden: " .. ALLOWLIST_PATH) end
   local lineno = 0
   for line in f:lines() do
      lineno = lineno + 1
      line = line:gsub("\r$", ""):gsub("#.*$", "")
      for tok in line:gmatch("%S+") do
         if tok:find("^[%w_]+$") then
            if not WOW_NAMES[tok] then
               WOW_NAMES[tok] = true
               WOW_LOWER[tok:lower()] = tok
               allowlist_count = allowlist_count + 1
            end
         elseif tok:find("^[%w_]+%*$") then
            WOW_PREFIXES[#WOW_PREFIXES + 1] = tok:sub(1, -2)
         else
            io.stderr:write(("lint_globals: %s:%d: ungueltiger Eintrag '%s' ignoriert\n"):format(
               ALLOWLIST_PATH, lineno, tok))
         end
      end
   end
   f:close()
end

local function is_wow_name(name)
   if WOW_NAMES[name] then return true end
   for _, prefix in ipairs(WOW_PREFIXES) do
      if name:sub(1, #prefix) == prefix then return true end
   end
   return false
end

-- Klassifikation eines Namens: "lua" | "wow" | "addon" | "optional" | nil (unbekannt)
local function classify(name)
   if LUA_NAMES[name] then return "lua" end
   if is_addon_name(name) then return "addon" end
   if OPTIONAL[name] then return "optional" end
   if is_wow_name(name) then return "wow" end
   return nil
end

-- ---------------------------------------------------------------------------
-- Bytecode auswerten
-- ---------------------------------------------------------------------------

-- Laeuft rekursiv ueber alle Funktionen (Protos) einer geladenen Datei und sammelt
-- GGET/GSET mit Namen und Quellzeile in hits.
local function walk(proto, hits)
   local n = -1
   while true do
      local k = funck(proto, n)
      if not k then break end
      if type(k) == "proto" then walk(k, hits) end
      n = n - 1
   end
   local fn_line = funcinfo(proto).linedefined or 0
   local pc = 1
   while true do
      local ins = funcbc(proto, pc)
      if not ins then break end
      local o = band(ins, 0xff)
      local opname = bcnames:sub(o * 6 + 1, o * 6 + 6)
      local write
      if opname == "GGET  " then
         write = false
      elseif opname == "GSET  " then
         write = true
      end
      if write ~= nil then
         local name = funck(proto, -shr(ins, 16) - 1)
         if type(name) == "string" then
            local line = funcinfo(proto, pc).currentline
            hits[#hits + 1] = {
               name = name, write = write,
               line = (line and line > 0) and line or fn_line,
               fnline = fn_line,
            }
         end
      end
      pc = pc + 1
   end
end

local function scan_inprocess(path)
   local fn, err = loadfile(path)
   if not fn then return nil, err end
   local hits = {}
   walk(fn, hits)
   return hits
end

-- Variante ueber `luajit -bl` (Textlisting). Das Listing enthaelt keine
-- Zeilennummern je Instruktion, deshalb gilt der Funktionsanfang als Zeile.
local function scan_listing(path)
   local p = io.popen(shq(LUAJIT) .. " -bl " .. shq(path) .. " 2>&1")
   if not p then return nil, "luajit nicht startbar" end
   local hits, fn_line = {}, 0
   local text = {}
   for line in p:lines() do
      text[#text + 1] = line
      local first = line:match("^%-%- BYTECODE %-%- .-:(%d+)%-%d+$")
      if first then
         fn_line = tonumber(first)
      else
         local op, name = line:match('^%d+%s+=?>?%s*(G[GS]ET)%s+%d+%s+%d+%s+; "(.-)"~?$')
         if op then
            hits[#hits + 1] = { name = name, write = (op == "GSET"), line = fn_line, fnline = fn_line }
         end
      end
   end
   local ok = p:close()
   -- ein Syntaxfehler liefert keine "-- BYTECODE --"-Zeile, sondern eine Meldung
   if #hits == 0 and #text > 0 and not text[1]:find("^%-%- BYTECODE") then
      return nil, (text[1]:gsub("^luajit: ", ""))
   end
   if ok == nil then return nil, "luajit -bl fehlgeschlagen" end
   return hits
end

-- ---------------------------------------------------------------------------
-- Hauptlauf
-- ---------------------------------------------------------------------------

local files = {}   -- { rel =, path = }
if #explicit > 0 then
   for _, p in ipairs(explicit) do files[#files + 1] = { rel = p, path = p } end
else
   for _, rel in ipairs(list_files(ROOT, "*.lua")) do
      if not excluded(rel) then
         files[#files + 1] = { rel = rel, path = ROOT .. "/" .. rel }
      end
   end
end

if #files == 0 then
   io.stderr:write("lint_globals: keine Lua-Dateien gefunden unter " .. ROOT .. "\n")
   os.exit(2)
end

local violations = {}     -- { rel, line, msg }
local total_access, total_names = 0, {}
local per_file = {}       -- rel -> { [name] = { r = {lines}, w = {lines}, class = } }

local function add_violation(rel, line, msg)
   violations[#violations + 1] = { rel = rel, line = line, msg = msg }
end

local function suggestion(name)
   local lower = WOW_LOWER[name:lower()]
   if lower and lower ~= name then return " (did you mean '" .. lower .. "'?)" end
   if name:find("^arg%d$") then
      return " - implicit global of old UI handlers (use explicit parameters)"
   end
   return ""
end

for _, file in ipairs(files) do
   local hits, err
   if opt.listing then
      hits, err = scan_listing(file.path)
   else
      hits, err = scan_inprocess(file.path)
   end
   if not hits then
      add_violation(file.rel, 0, "syntax error: " .. tostring(err))
   else
      local seen = {}      -- Doppelmeldungen je (Zeile, Name, Art) vermeiden
      local names = {}
      per_file[file.rel] = names
      for _, h in ipairs(hits) do
         total_access = total_access + 1
         total_names[h.name] = true
         local entry = names[h.name]
         if not entry then
            entry = { r = {}, w = {}, class = classify(h.name) }
            names[h.name] = entry
         end
         local list = h.write and entry.w or entry.r
         list[#list + 1] = h.line

         local key = h.line .. ":" .. h.name .. ":" .. (h.write and "w" or "r")
         if not seen[key] then
            seen[key] = true
            local class = entry.class
            local where = opt.listing and (" [in function starting at line " .. h.fnline .. "]") or ""
            if h.write then
               if class ~= "addon" then
                  local msg
                  if class == nil then
                     msg = ("WRITE to global '%s': accidental global (use 'local' or a Transmog.* field)%s"):format(h.name, where)
                  else
                     msg = ("WRITE to global '%s': overwrites a Lua/WoW name (use hooksecurefunc or a local)%s"):format(h.name, where)
                  end
                  add_violation(file.rel, h.line, msg)
               end
            else
               if class == nil then
                  local hint = KNOWN_BAD[h.name]
                  local msg = ("read of undefined global '%s': not Lua 5.1 / WoW 3.3.5a API / addon global%s"):format(
                     h.name, hint and (" - " .. hint) or suggestion(h.name))
                  if not hint and h.name:find("^C_%u") then
                     msg = msg .. " - retail namespace, does not exist in 3.3.5a"
                  end
                  add_violation(file.rel, h.line, msg .. where)
               end
            end
         end
      end
   end
end

-- Ausgabe ---------------------------------------------------------------------

table.sort(violations, function(a, b)
   if a.rel ~= b.rel then return a.rel < b.rel end
   if a.line ~= b.line then return a.line < b.line end
   return a.msg < b.msg
end)

local function join_lines(list)
   -- eindeutig und aufsteigend
   local set, arr = {}, {}
   for _, l in ipairs(list) do
      if not set[l] then set[l] = true; arr[#arr + 1] = l end
   end
   table.sort(arr)
   local parts = {}
   for i = 1, math.min(#arr, 12) do parts[i] = tostring(arr[i]) end
   if #arr > 12 then parts[#parts + 1] = "..." end
   return table.concat(parts, ",")
end

if opt.explain then
   for _, file in ipairs(files) do
      local names = per_file[file.rel]
      if names then
         local sorted, n_acc = {}, 0
         for name, e in pairs(names) do
            sorted[#sorted + 1] = name
            n_acc = n_acc + #e.r + #e.w
         end
         table.sort(sorted)
         print(("== %s  (%d distinct globals, %d accesses)"):format(file.rel, #sorted, n_acc))
         for _, name in ipairs(sorted) do
            local e = names[name]
            local cls = e.class or "UNKNOWN"
            local acc = {}
            if #e.r > 0 then acc[#acc + 1] = "read " .. join_lines(e.r) end
            if #e.w > 0 then acc[#acc + 1] = "WRITE " .. join_lines(e.w) end
            print(("   %-8s %-34s %s"):format(cls, name, table.concat(acc, "; ")))
         end
      end
   end
   print("")
end

for _, v in ipairs(violations) do
   if v.line > 0 then
      print(("%s:%d: %s"):format(v.rel, v.line, v.msg))
   else
      print(("%s: %s"):format(v.rel, v.msg))
   end
end

local n_names = 0
for _ in pairs(total_names) do n_names = n_names + 1 end
if not opt.quiet or #violations > 0 then
   print(("lint_globals: %d files, %d global accesses, %d distinct names, %d allowlisted API names, %d violation(s)%s"):format(
      #files, total_access, n_names, allowlist_count, #violations, opt.listing and " [listing mode]" or ""))
end

os.exit(#violations == 0 and 0 or 1)
