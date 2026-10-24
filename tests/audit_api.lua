-- tests/audit_api.lua
-- ---------------------------------------------------------------------------
-- Statische Querpruefung der Modulschnittstellen (SPEC 5 und 6).
--
--    luajit tests/audit_api.lua [-v] [--strict] [--root DIR]
--                                                   (im Hauptverzeichnis des Addons)
--
-- Liest die Lua-Dateien der TOC (Reihenfolge egal) und prueft:
--
--   1. Aufrufe/Feldzugriffe  Modul.Name  (Modul = T.Util, T.State, T.UI.Skin ...,
--      auch ueber lokale Aliase wie  local State = T.State):  jeder Name muss
--      irgendwo definiert sein (function Modul.Name / Modul.Name = ...).
--   2. Aufrufe mit MEHR Argumenten als die Definition Parameter hat (die
--      ueberzaehligen Argumente verpuffen still -> fast immer ein Fehler).
--      Funktionen mit "..." und Doppelpunkt-Methoden werden nicht geprueft.
--   3. Ereignisnamen: jedes Events.Fire/On("NAME") muss in SPEC 5.3 stehen;
--      Ereignisse der Liste, die nirgends gefeuert werden, sind Warnungen.
--
-- Module, deren Datei noch nicht existiert (Window, Grid, Boot ...), erzeugen
-- nur Warnungen ("ausstehend"); mit --strict sind sie Fehler (Endabnahme).
-- Exit-Code 0 = keine Fehler, 1 = mindestens ein Fehler.
-- ---------------------------------------------------------------------------

local scriptPath = (arg and arg[0]) or "tests/audit_api.lua"
local ROOT = scriptPath:match("^(.*)[/\\]tests[/\\][^/\\]*$") or "."

local verbose, strict = false, false
local args = arg or {}
local ai = 1
while ai <= #args do
   local a = args[ai]
   if a == "-v" or a == "--verbose" then
      verbose = true
   elseif a == "--strict" then
      strict = true
   elseif a == "--root" then
      ai = ai + 1
      ROOT = args[ai] or ROOT
   end
   ai = ai + 1
end

-- Alle Module der SPEC (Pfade relativ zu T); fehlt ein Modul ganz, ist es
-- "ausstehend" und kein Fehler im Arbeitsstand.
local SPEC_MODULES = {
   "Util", "Events", "DB", "Slots", "Items", "Net", "State", "Filter", "Outfits",
   "Locale", "Tooltips", "Toasts", "Boot",
   "UI.Skin", "UI.Cameras", "UI.Preview", "UI.SlotBar", "UI.Grid", "UI.FilterBar",
   "UI.OutfitsTab", "UI.Options", "UI.Window",
}

-- Ereignisse des internen Busses (SPEC 5.3)
local BUS_EVENTS = {
   "LOCALE_CHANGED", "SETTINGS_CHANGED", "ITEMS_RESOLVED", "STATUS_CHANGED",
   "LIST_PROGRESS", "LIST_READY", "EQUIPMENT_CHANGED", "WANTED_CHANGED", "COST_CHANGED",
   "APPLY_STARTED", "APPLY_PROGRESS", "APPLY_DONE", "COLLECTION_UPDATED",
   "COLLECTION_STATUS", "SERVER_OPEN", "SERVER_STATE", "VENDOR_CHANGED",
   "OUTFITS_CHANGED", "FAVORITES_CHANGED", "FILTER_CHANGED",
}

-- Felder, die bewusst zur Laufzeit entstehen (nicht als "T.x =" im Code stehen)
local DYNAMIC = {
   ["enteredWorldAt"] = "von Boot gesetzt",
   ["Filter.state"] = "ueber __index geliefert",
   ["L.__missing"] = "Locale-Fuehrung",
}

-- ---------------------------------------------------------------------------
-- Dateien
-- ---------------------------------------------------------------------------

local function readFile(path)
   local f = io.open(path, "rb")
   if not f then return nil end
   local s = f:read("*a")
   f:close()
   return s
end

local toc = readFile(ROOT .. "/Transmog.toc")
if not toc then
   io.write("audit_api: Transmog.toc nicht gefunden (" .. ROOT .. ")\n")
   os.exit(2)
end

local files = {}
for line in (toc .. "\n"):gmatch("(.-)\r?\n") do
   line = line:match("^%s*(.-)%s*$")
   if line ~= "" and line:sub(1, 1) ~= "#" and line:lower():match("%.lua$") then
      files[#files + 1] = (line:gsub("\\", "/"))
   end
end

-- Entfernt Kommentare (und, mit blank, den Inhalt von Zeichenketten); Zeilen-
-- umbrueche bleiben erhalten, damit Zeilennummern stimmen.
local function strip(src, blankStrings)
   local out, n, i = {}, #src, 1
   while i <= n do
      local c = src:sub(i, i)
      if c == "-" and src:sub(i + 1, i + 1) == "-" then
         local eq = src:match("^%[(=*)%[", i + 2)
         if eq then
            local close = "]" .. eq .. "]"
            local _, e = src:find(close, i + 4 + #eq, true)
            e = e or n
            out[#out + 1] = (src:sub(i, e):gsub("[^\n]", ""))
            i = e + 1
         else
            local e = src:find("\n", i, true)
            i = e or (n + 1)
         end
      elseif c == '"' or c == "'" then
         local j = i + 1
         local nl = 0
         while j <= n do
            local d = src:sub(j, j)
            if d == "\\" then
               if src:sub(j + 1, j + 1) == "\n" then nl = nl + 1 end
               j = j + 2
            elseif d == c or d == "\n" then
               break
            else
               j = j + 1
            end
         end
         if blankStrings then
            out[#out + 1] = c .. c .. string.rep("\n", nl)
         else
            out[#out + 1] = src:sub(i, j)
         end
         i = j + 1
      elseif c == "[" and src:match("^%[=*%[", i) then
         local eq = src:match("^%[(=*)%[", i)
         local close = "]" .. eq .. "]"
         local _, e = src:find(close, i + #eq + 2, true)
         e = e or n
         if blankStrings then
            out[#out + 1] = '""' .. (src:sub(i, e):gsub("[^\n]", ""))
         else
            out[#out + 1] = src:sub(i, e)
         end
         i = e + 1
      else
         out[#out + 1] = c
         i = i + 1
      end
   end
   return table.concat(out)
end

-- Zeilennummer zu einer Textposition (Positionen werden aufsteigend erfragt)
local function lineMapper(text)
   local starts = { 1 }
   for p in text:gmatch("()\n") do starts[#starts + 1] = p + 1 end
   return function(pos)
      local lo, hi = 1, #starts
      while lo < hi do
         local mid = math.ceil((lo + hi) / 2)
         if starts[mid] <= pos then lo = mid else hi = mid - 1 end
      end
      return lo
   end
end

local function split(path)
   local out = {}
   for seg in path:gmatch("[^%.]+") do out[#out + 1] = seg end
   return out
end

local function join(a, b)
   if a == "" then return b end
   if b == "" then return a end
   return a .. "." .. b
end

-- ---------------------------------------------------------------------------
-- Einlesen: Aliase und Definitionen
-- ---------------------------------------------------------------------------

local sources = {}   -- [i] = { file=, code=, kept=, alias={}, line=fn }
local defs = {}      -- [pfad] = { params=n, vararg=bool, method=bool, file=, line= }
local isParent = {}  -- [pfad] = true, wenn Eintraege darunter definiert sind

local function paramInfo(list)
   list = list or ""
   local n, vararg = 0, false
   for item in list:gmatch("[^,]+") do
      local p = item:match("^%s*(.-)%s*$")
      if p == "..." then
         vararg = true
      elseif p ~= "" then
         n = n + 1
      end
   end
   return n, vararg
end

local function addDef(path, info)
   if path == "" then return end
   local cur = defs[path]
   if not cur then
      defs[path] = info
   elseif info.params and cur.params and info.params > cur.params then
      cur.params = info.params   -- mehrere Definitionen: der groesste Wert gilt
   end
   local segs = split(path)
   local acc = ""
   for i = 1, #segs - 1 do
      acc = join(acc, segs[i])
      isParent[acc] = true
   end
end

for _, rel in ipairs(files) do
   local text = readFile(ROOT .. "/" .. rel)
   if text then
      local code = strip(text, true)
      sources[#sources + 1] = {
         file = rel, code = code, kept = strip(text, false), line = lineMapper(code),
         alias = {},
      }
   end
end

-- Aliase je Datei (mehrere Durchlaeufe, damit Aliase von Aliasen aufloesen)
local function resolveRoot(src, name)
   if name == "T" or name == "Transmog" then return "" end
   return src.alias[name]
end

for _, src in ipairs(sources) do
   for pass = 1, 3 do
      for rawLine in (src.code .. "\n"):gmatch("(.-)\n") do
         -- local X = T.A.B  /  local X = Alias.B  (nur, wenn der Pfad die ganze
         -- rechte Seite ist, ggf. mit "or {}")
         local name, rhs, tail = rawLine:match("^%s*local%s+([%a_][%w_]*)%s*=%s*([%a_][%w_%.]*)(.-)%s*$")
         if tail ~= "" and tail ~= " or {}" and not (tail and tail:match("^%s*or%s*{%s*}$")) then
            name, rhs = nil, nil
         end
         if name and rhs then
            local segs = split(rhs)
            local base = resolveRoot(src, segs[1])
            if base ~= nil and #segs >= 2 then
               local rest = table.concat(segs, ".", 2)
               src.alias[name] = join(base, rest)
            end
         end
         -- T.A.B = X  (X lokale Tabelle)
         local lhs, name2 = rawLine:match("^%s*([%a_][%w_%.]*)%s*=%s*([%a_][%w_]*)%s*$")
         if lhs and name2 and not src.alias[name2] then
            local segs = split(lhs)
            local base = resolveRoot(src, segs[1])
            if base ~= nil and #segs >= 2 then
               -- X ist nur dann ein Alias, wenn es eine lokale Tabelle derselben Datei ist
               if src.code:find("local%s+" .. name2 .. "%s*=%s*{") then
                  src.alias[name2] = join(base, table.concat(segs, ".", 2))
               end
            end
         end
      end
   end
end

for _, src in ipairs(sources) do
   local ln = 0
   for rawLine in (src.code .. "\n"):gmatch("(.-)\n") do
      ln = ln + 1
      -- function A.B.C(p1, p2)  /  function A.B:C(p1)
      local fbase, frest, plist = rawLine:match("^%s*function%s+([%a_][%w_]*)([%.:][%w_%.:]+)%s*%(([^)]*)%)")
      if fbase then
         local base = resolveRoot(src, fbase)
         if base ~= nil then
            local method = frest:find(":", 1, true) ~= nil
            local rest = frest:gsub("^[%.:]", ""):gsub(":", ".")
            local n, vararg = paramInfo(plist)
            addDef(join(base, rest), { params = n, vararg = vararg, method = method,
               file = src.file, line = ln })
         end
      else
         -- A.B.C = ...   (kein ==)
         local lhs, rhs = rawLine:match("^%s*([%a_][%w_%.]*)%s*=%s*([^=].*)$")
         if lhs and not lhs:find("%.$") then
            local segs = split(lhs)
            local base = resolveRoot(src, segs[1])
            if base ~= nil and #segs >= 2 then
               local rest = table.concat(segs, ".", 2)
               local plist2 = rhs:match("^%s*function%s*%(([^)]*)%)")
               local info = { file = src.file, line = ln }
               if plist2 then
                  info.params, info.vararg = paramInfo(plist2)
               end
               -- "X = {}" oder "X = T.X or {}": Modul-Tabelle (Kinder werden geprueft)
               if rhs:match("^%s*{%s*}%s*$") or rhs:match("or%s*{%s*}%s*$") then
                  info.module = true
               end
               -- "T.X = lokal" mit  local lokal = {}  : ebenfalls ein Modul
               local ident = rhs:match("^%s*([%a_][%w_]*)%s*$")
               if ident and src.code:find("local%s+" .. ident .. "%s*=%s*{%s*}") then
                  info.module = true
               end
               addDef(join(base, rest), info)
            end
         end
      end
   end
end

-- Module "T.UI" usw. gelten als definiert, sobald darunter etwas steht
-- (isParent). Zusaetzlich: reine Zuweisungen "T.X = ..." sind Definitionen.

-- ---------------------------------------------------------------------------
-- Pruefung der Verwendungen
-- ---------------------------------------------------------------------------

local errors, warnings = {}, {}
local pendingSeen = {}

local specModule = {}
for _, m in ipairs(SPEC_MODULES) do specModule[m] = true end

-- Kennzeichnet einen Pfad, der zu einem (noch) nicht vorhandenen SPEC-Modul gehoert
local function pendingModule(path)
   local acc = ""
   for _, seg in ipairs(split(path)) do
      acc = join(acc, seg)
      if specModule[acc] and not defs[acc] and not isParent[acc] then
         return acc
      end
   end
   return nil
end

-- Ist der Pfad eine Modul-Tabelle (deren Kinder vollstaendig im Code stehen)?
-- Datentabellen mit Inhalt (Farben, Vorgaben ...) werden nicht geprueft.
local function isModule(path)
   if path == "" or specModule[path] or path == "UI" then return true end
   local d = defs[path]
   return d ~= nil and d.module == true
end

-- Sucht den ersten nicht definierten Teil des Pfads; nil = in Ordnung.
local function firstUndefined(segs)
   local cur = ""
   for i = 1, #segs do
      local nxt = join(cur, segs[i])
      if defs[nxt] or isParent[nxt] or DYNAMIC[nxt] then
         cur = nxt
      else
         if isModule(cur) then
            return nxt
         end
         return nil   -- Blatt: Datenfeld, darunter wird nicht geprueft
      end
   end
   return nil
end

-- Anzahl der Argumente eines Aufrufs; text[pos] == "(" (Code ohne Strings).
local OPEN_WORDS = { ["function"] = true, ["if"] = true, ["do"] = true, ["repeat"] = true }
local CLOSE_WORDS = { ["end"] = true, ["until"] = true }

local function countArgs(code, pos)
   local depth, block = 1, 0
   local commas, any = 0, false
   local i, n = pos + 1, #code
   while i <= n do
      local c = code:sub(i, i)
      if c == "(" or c == "{" or c == "[" then
         depth = depth + 1
         any = true
         i = i + 1
      elseif c == ")" or c == "}" or c == "]" then
         depth = depth - 1
         if depth == 0 then
            return any and (commas + 1) or 0
         end
         i = i + 1
      elseif c == "," then
         if depth == 1 and block == 0 then commas = commas + 1 end
         any = true
         i = i + 1
      elseif c:match("[%a_]") then
         local word = code:match("^[%w_]+", i)
         if OPEN_WORDS[word] then block = block + 1 end
         if CLOSE_WORDS[word] then block = block - 1 end
         any = true
         i = i + #word
      else
         if not c:match("%s") then any = true end
         i = i + 1
      end
   end
   return nil
end

for _, src in ipairs(sources) do
   local code = src.code
   local pos = 1
   while true do
      local s, e = code:find("[%a_][%w_]*", pos)
      if not s then break end
      local prev = s > 1 and code:sub(s - 1, s - 1) or ""
      local segs = { code:sub(s, e) }
      local cur = e
      while true do
         local s2, e2 = code:find("^%.([%a_][%w_]*)", cur + 1)
         if not s2 then break end
         segs[#segs + 1] = code:sub(s2 + 1, e2)
         cur = e2
      end
      pos = cur + 1

      if prev ~= "." and prev ~= ":" and #segs >= 2 then
         local base = resolveRoot(src, segs[1])
         if base ~= nil then
            local full = {}
            for _, seg in ipairs(split(base)) do full[#full + 1] = seg end
            for i = 2, #segs do full[#full + 1] = segs[i] end
            local path = table.concat(full, ".")
            local lineNo = src.line(s)
            local bad = firstUndefined(full)
            if bad then
               local pend = pendingModule(bad)
               if pend then
                  pendingSeen[pend] = pendingSeen[pend] or (src.file .. ":" .. lineNo)
               else
                  errors[#errors + 1] = string.format("%s:%d: T.%s ist nirgends definiert",
                     src.file, lineNo, bad)
               end
            else
               -- Arity: nur bei bekannter Funktion und direktem Aufruf
               local d = defs[path]
               if d and d.params and not d.vararg and not d.method then
                  local after = code:match("^%s*%(", cur + 1)
                  if after then
                     local open = code:find("(", cur + 1, true)
                     local argc = countArgs(code, open)
                     if argc and argc > d.params then
                        errors[#errors + 1] = string.format(
                           "%s:%d: T.%s mit %d Argument(en) gerufen, Definition (%s:%d) hat %d Parameter",
                           src.file, lineNo, path, argc, d.file, d.line, d.params)
                     end
                  end
               end
            end
         end
      end
   end
end

-- ---------------------------------------------------------------------------
-- Ereignisnamen
-- ---------------------------------------------------------------------------

local known = {}
for _, name in ipairs(BUS_EVENTS) do known[name] = true end
local fired, handled = {}, {}

for _, src in ipairs(sources) do
   local ln = 0
   for rawLine in (src.kept .. "\n"):gmatch("(.-)\n") do
      ln = ln + 1
      for name in rawLine:gmatch("[%a_%.]*Fire%(%s*\"([%w_]+)\"") do
         fired[name] = fired[name] or (src.file .. ":" .. ln)
         if not known[name] then
            errors[#errors + 1] = string.format("%s:%d: unbekanntes Ereignis \"%s\" (Fire)",
               src.file, ln, name)
         end
      end
      for name in rawLine:gmatch("[%a_%.]*[Ee]vents%.On%(%s*\"([%w_]+)\"") do
         handled[name] = handled[name] or (src.file .. ":" .. ln)
         if not known[name] then
            errors[#errors + 1] = string.format("%s:%d: unbekanntes Ereignis \"%s\" (On)",
               src.file, ln, name)
         end
      end
      for name in rawLine:gmatch("ev%.On%(%s*\"([%w_]+)\"") do
         handled[name] = handled[name] or (src.file .. ":" .. ln)
         if not known[name] then
            errors[#errors + 1] = string.format("%s:%d: unbekanntes Ereignis \"%s\" (On)",
               src.file, ln, name)
         end
      end
   end
end

for _, name in ipairs(BUS_EVENTS) do
   if not fired[name] then
      warnings[#warnings + 1] = "Ereignis " .. name .. " wird nirgends gefeuert"
   end
end

for mod in pairs(pendingSeen) do
   local msg = "Modul T." .. mod .. " ist noch nicht vorhanden (erste Verwendung " .. pendingSeen[mod] .. ")"
   if strict then
      errors[#errors + 1] = msg
   else
      warnings[#warnings + 1] = msg
   end
end
for _, m in ipairs(SPEC_MODULES) do
   if strict and not defs[m] and not isParent[m] and not pendingSeen[m] then
      errors[#errors + 1] = "Modul T." .. m .. " fehlt"
   end
end

-- ---------------------------------------------------------------------------
-- Ausgabe
-- ---------------------------------------------------------------------------

table.sort(errors)
table.sort(warnings)

local defCount = 0
for _ in pairs(defs) do defCount = defCount + 1 end
io.write(string.format("audit_api: %d Dateien, %d Definitionen, %d Fehler, %d Warnung(en)\n",
   #sources, defCount, #errors, #warnings))
for _, e in ipairs(errors) do io.write("  FEHLER  " .. e .. "\n") end
if verbose then
   for _, w in ipairs(warnings) do io.write("  Hinweis " .. w .. "\n") end
end
os.exit(#errors > 0 and 1 or 0)
