-- tests/run.lua
-- ---------------------------------------------------------------------------
-- Runner und kleines Test-Framework fuer das Addon "Transmog".
--
--     luajit tests/run.lua [filter] [-v] [--globals]
--
-- Im Hauptverzeichnis des Addons starten. Der Runner findet tests/test_*.lua
-- (alphabetisch). Jede Datei liefert  function(H) ... end  und meldet ihre
-- Tests ueber H.test(name, fn). Ein fehlschlagender Test beendet den Lauf nicht;
-- am Ende steht eine Zusammenfassung, Exit-Code 1 bei Fehlern.
--
-- filter   nur Tests, deren "datei: name" den Text (ohne Gross/Klein) enthaelt
--          (eine Datei kann auch mit ihrem Kurznamen gewaehlt werden: "cameras")
-- -v       zeigt zusaetzlich Warnungen der Attrappe und alle bestandenen Pruefungen
-- --globals  listet gelesene, aber nie definierte Globals des Addon-Codes
--
-- Automatische Pruefungen am Ende jedes Tests (schlagen den Test fehl):
--   * Fehler in Skript-Handlern/Ereignissen (landen im Fehler-Handler, M.errors)
--     -- ausser der Test hat sie mit H.takeErrors() abgeholt
--   * Verweise auf Addon-Dateien (Texturen/Toene), die es nicht gibt
--   * vom Addon neu angelegte Globals ausserhalb des erlaubten Namensraums
--     (H.allowGlobals{"^Foo"} erweitert; Tests koennen H.allowStrays() nutzen)
--   * Lesezugriffe des Addons auf this/event/arg1..arg9 (Implicit-Globals; H.allowImplicit())
--
-- Jeder Test beginnt mit einer frisch zurueckgesetzten Attrappe (mock.Install()).
-- Das Addon wird IM Test mit H.boot() geladen. Globale Funktionen/Variablen der
-- Testdatei selbst werden beim Zuruecksetzen geloescht: nur lokale Hilfen benutzen.
--
-- Test-API (H):
--   H.test(name, fn)           ein Test; Fehler/Fehlschlaege werden gesammelt, der Lauf geht weiter
--   H.section(name)            Ueberschrift (nur ohne Filter)
--   H.check(cond, msg) / H.ok  weiche Pruefung (der Test laeuft weiter);  H.assert: bricht ab
--   H.eq(a, expected, msg)     Gleichheit (zeigt beide Werte);  H.neq, H.near(a, b, eps)
--   H.deepEq(a, b, msg)        rekursiv (zeigt die erste Abweichung mit Pfad)
--   H.truthy(v) / H.falsy(v)   beachte: IsShown() & Co. liefern in 3.3.5a 1 oder nil
--   H.throws(fn, pattern)      fn muss werfen; Meldung muss auf das Muster passen; liefert die Meldung
--   H.contains(text|liste, x)  H.matches(s, muster)   H.len(t, n)   H.fail(msg)
--   H.boot(opts)               Attrappe zuruecksetzen, TOC laden, ADDON_LOADED/PLAYER_LOGIN feuern;
--                              opts: upTo, skip, skipMissing(=true), toc, world, items, globals,
--                              login(=true), enterWorld(=false); liefert die Tabelle Transmog
--   H.install(opts)            nur zuruecksetzen (ohne TOC)
--   H.beforeEach(fn)           fn() vor jedem weiteren Test dieser Datei (nach dem Zuruecksetzen)
--   H.takeErrors()             Fehler der Fehler-Handler abholen (und damit quittieren)
--   H.allowErrors() H.allowMissingAssets() H.allowGlobals{muster} H.allowStrays() H.allowImplicit()
--   H.mock                     die Attrappe (tests/mock_wow.lua); H.root = Addon-Verzeichnis
-- ---------------------------------------------------------------------------

local realIo, realOs, realDebug = io, os, debug
local sfmt, ssub, sfind, srep = string.format, string.sub, string.find, string.rep

-- Verzeichnis dieser Datei
local scriptPath = (arg and arg[0]) or "tests/run.lua"
local testsDir = scriptPath:match("^(.*)[/\\]run%.lua$") or "tests"

-- Kommandozeile
local filter, verbose, showGlobals = nil, false, false
for _, a in ipairs(arg or {}) do
   if a == "-v" or a == "--verbose" then
      verbose = true
   elseif a == "--globals" then
      showGlobals = true
   elseif a:sub(1, 1) ~= "-" and not filter then
      filter = a:lower()
   end
end

-- Hilfsmodule der Tests (require "name") liegen neben den Testdateien
package.path = testsDir .. "/?.lua;" .. package.path

local mock = dofile(testsDir .. "/mock_wow.lua")
local rootAtStart = mock.root        -- Tests duerfen mock.root zeitweise umbiegen; jeder Test startet wieder hier

-- ---------------------------------------------------------------------------
-- Darstellung von Werten
-- ---------------------------------------------------------------------------

local function repr(v, depth)
   depth = depth or 0
   local t = type(v)
   if t == "string" then
      local s = v:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t"):gsub('"', '\\"')
      if #s > 160 then s = s:sub(1, 157) .. "..." end
      return '"' .. s .. '"'
   elseif t == "table" then
      if depth >= 3 then return "{...}" end
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
         local ta, tb = type(a), type(b)
         if ta ~= tb then return ta < tb end
         if ta == "number" or ta == "string" then return a < b end
         return tostring(a) < tostring(b)
      end)
      local parts = {}
      for i, k in ipairs(keys) do
         if i > 12 then
            parts[#parts + 1] = "..."
            break
         end
         local ks = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. repr(k, depth + 1) .. "]")
         parts[#parts + 1] = ks .. "=" .. repr(v[k], depth + 1)
      end
      return "{" .. table.concat(parts, ", ") .. "}"
   end
   return tostring(v)
end

-- Rekursiver Vergleich; liefert nil bei Gleichheit, sonst eine Beschreibung der ersten Abweichung
local function diff(a, b, path, seen)
   if rawequal(a, b) then return nil end
   if type(a) ~= "table" or type(b) ~= "table" then
      if a ~= a and b ~= b then return nil end   -- NaN
      return sfmt("%s: expected %s, got %s", path, repr(b), repr(a))
   end
   seen = seen or {}
   if seen[a] == b then return nil end
   seen[a] = b
   for k, v in pairs(b) do
      local d = diff(a[k], v, path .. "[" .. repr(k) .. "]", seen)
      if d then return d end
   end
   for k in pairs(a) do
      if b[k] == nil then return sfmt("%s[%s]: unexpected key (value %s)", path, repr(k), repr(a[k])) end
   end
   return nil
end

-- ---------------------------------------------------------------------------
-- Zustand des Laufs
-- ---------------------------------------------------------------------------

local headerShown = false     -- Dateiname schon ausgegeben?
local R = {
   tests = 0, passed = 0, failed = 0, skipped = 0,
   checks = 0, failedChecks = 0,
   failures = {},        -- { title, lines = {...} }
   misses = {},          -- Name -> { count, where }
   warnings = {},
   file = "(runner)",
}
local current = nil       -- laufender Test
local fileCtx = nil       -- Pseudo-Test fuer Pruefungen ausserhalb von H.test

local function location(level)
   local info = realDebug.getinfo(level, "Sl")
   if not info then return "?" end
   local src = info.short_src or "?"
   src = src:gsub("^.*[/\\]", "")
   return src .. ":" .. tostring(info.currentline)
end

local function ctx()
   if current then return current end
   if not fileCtx then fileCtx = { name = "(file level)", file = R.file, failures = {}, checks = 0 } end
   return fileCtx
end

-- Passt die laufende Datei zum Filter? (Kurzname ohne test_ und .lua)
local function fileSelected(file)
   if not filter then return true end
   local short = file:gsub("^test_", ""):gsub("%.lua$", "")
   return sfind(short:lower(), filter, 1, true) ~= nil
end

-- Pruefungen ausserhalb von H.test in einer Datei, die der Filter ausschliesst, zaehlen nicht
local function ignored()
   return current == nil and not fileSelected(R.file)
end

local function recordFailure(msg, level)
   if ignored() then return end
   local c = ctx()
   c.failures[#c.failures + 1] = location(level or 4) .. ": " .. msg
   R.failedChecks = R.failedChecks + 1
end

local function countCheck()
   if ignored() then return end
   ctx().checks = ctx().checks + 1
   R.checks = R.checks + 1
end

-- ---------------------------------------------------------------------------
-- Test-API (H)
-- ---------------------------------------------------------------------------

local H = { mock = mock, root = mock.root }

function H.check(cond, msg)
   countCheck()
   if not cond then recordFailure(tostring(msg or "check failed")) end
   return cond and true or false
end
H.ok = H.check

function H.assert(cond, msg)
   countCheck()
   if not cond then error(tostring(msg or "assertion failed"), 2) end
end

function H.fail(msg)
   countCheck()
   recordFailure(tostring(msg or "explicit failure"))
end

function H.eq(actual, expected, msg)
   countCheck()
   if actual == expected or (actual ~= actual and expected ~= expected) then return true end
   local text = sfmt("expected %s, got %s", repr(expected), repr(actual))
   if type(actual) == "table" and type(expected) == "table" then
      text = text .. " (different table objects; use H.deepEq)"
   end
   recordFailure((msg and (tostring(msg) .. ": ") or "") .. text)
   return false
end

function H.neq(actual, unexpected, msg)
   countCheck()
   if actual ~= unexpected then return true end
   recordFailure((msg and (tostring(msg) .. ": ") or "") .. "did not expect " .. repr(unexpected))
   return false
end

function H.near(actual, expected, eps, msg)
   countCheck()
   eps = eps or 1e-6
   if type(actual) == "number" and type(expected) == "number" and math.abs(actual - expected) <= eps then
      return true
   end
   recordFailure((msg and (tostring(msg) .. ": ") or "")
      .. sfmt("expected %s +- %s, got %s", repr(expected), tostring(eps), repr(actual)))
   return false
end

function H.deepEq(a, b, msg)
   countCheck()
   local d = diff(a, b, "value")
   if not d then return true end
   recordFailure((msg and (tostring(msg) .. ": ") or "") .. d)
   return false
end

function H.truthy(v, msg)
   countCheck()
   if v then return true end
   recordFailure((msg and (tostring(msg) .. ": ") or "") .. "expected a truthy value, got " .. repr(v))
   return false
end

function H.falsy(v, msg)
   countCheck()
   if not v then return true end
   recordFailure((msg and (tostring(msg) .. ": ") or "") .. "expected nil/false, got " .. repr(v))
   return false
end

-- fn muss einen Fehler werfen; pattern (Lua-Muster, notfalls plain) muss in der Meldung vorkommen.
-- Rueckgabe: die Fehlermeldung (oder nil).
function H.throws(fn, pattern, msg)
   countCheck()
   local ok, err = pcall(fn)
   local prefix = msg and (tostring(msg) .. ": ") or ""
   if ok then
      recordFailure(prefix .. "expected an error, but the call succeeded")
      return nil
   end
   err = tostring(err)
   if pattern then
      local found
      local okp, r = pcall(sfind, err, pattern)
      if okp then found = r else found = sfind(err, pattern, 1, true) end
      if not found then
         recordFailure(prefix .. sfmt("error message %s does not match %s", repr(err), repr(pattern)))
      end
   end
   return err
end

-- Text (plain) oder Listenelement enthalten?
function H.contains(haystack, needle, msg)
   countCheck()
   local found = false
   if type(haystack) == "string" then
      found = sfind(haystack, tostring(needle), 1, true) ~= nil
   elseif type(haystack) == "table" then
      for _, v in pairs(haystack) do
         if v == needle then found = true break end
      end
   end
   if found then return true end
   recordFailure((msg and (tostring(msg) .. ": ") or "") .. sfmt("%s does not contain %s", repr(haystack), repr(needle)))
   return false
end

function H.matches(s, pattern, msg)
   countCheck()
   if type(s) == "string" and sfind(s, pattern) then return true end
   recordFailure((msg and (tostring(msg) .. ": ") or "") .. sfmt("%s does not match %s", repr(s), repr(pattern)))
   return false
end

function H.len(t, n, msg)
   countCheck()
   local got = type(t) == "table" and #t or nil
   if got == n then return true end
   recordFailure((msg and (tostring(msg) .. ": ") or "") .. sfmt("expected length %s, got %s", repr(n), repr(got)))
   return false
end

-- Dateiname vor der ersten Ausgabe der Datei zeigen (Dateien ohne passende Tests bleiben still)
local function header()
   if not headerShown then
      headerShown = true
      io.write(R.file .. "\n")
   end
end

function H.section(name)
   if filter then return end
   header()
   io.write("\n[" .. tostring(name) .. "]\n")
end

-- Fehler des Fehler-Handlers abholen (und damit quittieren)
function H.takeErrors() return mock.TakeErrors() end
-- Dieser Test erwartet Handler-Fehler und wertet sie selbst aus
function H.allowErrors() ctx().allowErrors = true end
function H.allowMissingAssets() ctx().allowMissing = true end
-- Zusaetzliche Namen, die das Addon als Globals anlegen darf (Lua-Muster)
function H.allowGlobals(patterns)
   local c = ctx()
   c.allowedGlobals = c.allowedGlobals or {}
   for _, p in ipairs(patterns) do c.allowedGlobals[#c.allowedGlobals + 1] = p end
end
function H.allowStrays() ctx().allowStrays = true end
-- Der Test liest bewusst this/arg1/event (z.B. um das Verhalten zu pruefen)
function H.allowImplicit() ctx().allowImplicit = true end

-- Attrappe frisch aufbauen (ohne Addon laden)
function H.install(opts) return mock.Install(opts) end

-- fn() laeuft vor jedem Test der aktuellen Datei, nach dem automatischen Zuruecksetzen
-- (z.B. um immer mit demselben H.boot-Aufruf zu beginnen). H.beforeEach(nil) schaltet ab.
local beforeEachFn = nil
function H.beforeEach(fn) beforeEachFn = fn end

-- Installiert die Attrappe, laedt die TOC und feuert ADDON_LOADED/PLAYER_LOGIN.
--   opts.upTo, opts.skip, opts.skipMissing (Standard true), opts.toc ("Transmog.toc")
--   opts.world   wird vor dem Laden in mock.world gemischt
--   opts.items   wird vor dem Laden in mock.items gemischt
--   opts.globals bzw. opts.savedVariables  Globals, die vor dem Laden existieren (SavedVariables)
--   opts.login = false     PLAYER_LOGIN nicht feuern
--   opts.enterWorld = true PLAYER_ENTERING_WORLD zusaetzlich feuern
--   opts.noSeed = true     TransmogGlobalDB NICHT vorbelegen (siehe H.SeedGlobals): wie eine Neuinstallation
--                          (oder mit der eigenen TransmogGlobalDB aus opts.globals)
-- Ohne eigene TransmogGlobalDB startet jeder Test mit H.SeedGlobals() = dem Zustand "Spieler hat
-- 'Anwenden auch ohne Transmogrifizierer' bewusst ausgeschaltet": so behalten die vielen Tests des
-- Vorschau-Modus (Fenster ausserhalb des NPCs, Anwenden gesperrt) ihre Bedeutung, obwohl die Vorgabe
-- seit 2.1 "an" ist. Tests der neuen Vorgabe nutzen opts.noSeed oder eine eigene TransmogGlobalDB.
-- Rueckgabe: die globale Tabelle Transmog (kann bei fehlender Datei nil sein).
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
   mock.Install({
      world = opts.world, items = opts.items, globals = saved,
   })
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

-- ---------------------------------------------------------------------------
-- Tests ausfuehren
-- ---------------------------------------------------------------------------

local function matchesFilter(file, name)
   if not filter then return true end
   local short = file:gsub("^test_", ""):gsub("%.lua$", "")
   local full = (file .. ": " .. name):lower()
   return sfind(full, filter, 1, true) ~= nil or sfind(short:lower(), filter, 1, true) ~= nil
end

-- Schneidet die Runner-Frames aus einem Traceback
local function cleanTrace(tb)
   local out = {}
   for line in tostring(tb):gmatch("[^\n]+") do
      if not sfind(line, "run.lua", 1, true) and not sfind(line, "[C]: in function 'xpcall'", 1, true)
         and not sfind(line, "stack traceback", 1, true) then
         out[#out + 1] = line
      end
   end
   return out
end

local function mergeMisses()
   -- nur Namen, die auch danach nicht definiert sind (Transmog = Transmog or {} zaehlt nicht)
   for _, m in ipairs(mock.GlobalMisses()) do
      local r = R.misses[m.name]
      if r then
         r.count = r.count + m.count
      else
         R.misses[m.name] = { count = m.count, where = m.where }
      end
   end
end

-- Prueft, was nach dem Test uebrig ist
local function finalChecks(c)
   if #mock.errors > 0 and not c.allowErrors then
      local n = #mock.errors
      local first = mock.errors[1]
      local tr = mock.errorTraces[1]
      c.failures[#c.failures + 1] = sfmt("%d unhandled error(s) in script/event handlers; first: %s", n, first)
      if tr then
         for _, l in ipairs(cleanTrace(tr)) do c.failures[#c.failures + 1] = "      " .. l end
      end
   end
   if #mock.missingAssets > 0 and not c.allowMissing then
      for _, m in ipairs(mock.missingAssets) do
         c.failures[#c.failures + 1] = sfmt("addon %s file does not exist: %s", m.kind, m.path)
      end
   end
   if not c.allowStrays then
      local patterns = c.allowedGlobals or {}
      for _, entry in ipairs(mock.StrayGlobals()) do
         local name = entry:match("^(%S+)")
         local allowed = false
         for _, p in ipairs(patterns) do
            if sfind(name, p) then allowed = true break end
         end
         if not allowed then
            c.failures[#c.failures + 1] = "addon created a stray global: " .. entry
         end
      end
   end
   if not c.allowImplicit then
      for _, entry in ipairs(mock.ImplicitGlobalReads()) do
         c.failures[#c.failures + 1] = "addon read the implicit handler global " .. entry
            .. " (use the explicit handler parameters)"
      end
   end
   for _, w in ipairs(mock.warnings) do R.warnings[#R.warnings + 1] = c.file .. ": " .. c.name .. ": " .. w end
   mergeMisses()
end

function H.test(name, fn)
   if type(name) ~= "string" or type(fn) ~= "function" then
      error("H.test(name, fn): name must be a string and fn a function", 2)
   end
   if not matchesFilter(R.file, name) then
      R.skipped = R.skipped + 1
      return
   end
   header()
   if current then error("H.test must not be nested (test '" .. name .. "' inside '" .. current.name .. "')", 2) end
   R.tests = R.tests + 1
   local c = { name = name, file = R.file, failures = {}, checks = 0 }
   current = c
   mock.root = rootAtStart
   mock.Install()
   local t0 = realOs.clock()
   local handler = function(m) return { msg = m, trace = realDebug.traceback("", 2) } end
   local ok, err = true, nil
   if beforeEachFn then
      ok, err = xpcall(beforeEachFn, handler)
   end
   if ok then
      ok, err = xpcall(fn, handler)
   end
   if not ok then
      local msg = type(err) == "table" and tostring(err.msg) or tostring(err)
      c.failures[#c.failures + 1] = "ERROR: " .. msg
      if type(err) == "table" then
         for _, l in ipairs(cleanTrace(err.trace)) do c.failures[#c.failures + 1] = "      " .. l end
      end
   end
   finalChecks(c)
   current = nil
   local dt = realOs.clock() - t0
   if #c.failures == 0 then
      R.passed = R.passed + 1
      if verbose then
         io.write(sfmt("  ok    %s  (%d checks, %.0f ms)\n", name, c.checks, dt * 1000))
      else
         io.write("  ok    " .. name .. "\n")
      end
   else
      R.failed = R.failed + 1
      io.write("  FAIL  " .. name .. "\n")
      local lines = {}
      for _, f in ipairs(c.failures) do
         for l in tostring(f):gmatch("[^\n]+") do
            io.write("          " .. l .. "\n")
            lines[#lines + 1] = l
         end
      end
      R.failures[#R.failures + 1] = { title = c.file .. ": " .. name, lines = lines }
   end
end

-- Testdateien suchen
local function discover()
   local files = {}
   local p = realIo.popen('ls -1 "' .. testsDir .. '"/test_*.lua 2>/dev/null')
   if p then
      for line in p:lines() do files[#files + 1] = line end
      p:close()
   end
   table.sort(files)
   return files
end

local files = discover()
local t0 = realOs.clock()

for _, path in ipairs(files) do
   local base = path:match("([^/\\]+)$")
   R.file = base
   fileCtx = nil
   headerShown = false
   beforeEachFn = nil
   local chunk, lerr = loadfile(path)
   if not chunk then
      header()
      R.failed = R.failed + 1
      R.failures[#R.failures + 1] = { title = base .. ": LOAD", lines = { tostring(lerr) } }
      io.write("  FAIL  (cannot load file)\n          " .. tostring(lerr) .. "\n")
   else
      local ok, res = xpcall(chunk, function(m) return { msg = m, trace = realDebug.traceback("", 2) } end)
      if not ok then
         header()
         local msg = type(res) == "table" and tostring(res.msg) or tostring(res)
         R.failed = R.failed + 1
         R.failures[#R.failures + 1] = { title = base .. ": LOAD", lines = { msg } }
         io.write("  FAIL  (error while loading file)\n          " .. msg .. "\n")
      elseif type(res) ~= "function" then
         header()
         R.failed = R.failed + 1
         R.failures[#R.failures + 1] = { title = base .. ": LOAD", lines = { "file must return function(H)" } }
         io.write("  FAIL  (file does not return function(H))\n")
      else
         local ok2, err2 = xpcall(function() res(H) end, function(m)
            return { msg = m, trace = realDebug.traceback("", 2) }
         end)
         if not ok2 then
            header()
            local msg = type(err2) == "table" and tostring(err2.msg) or tostring(err2)
            R.failed = R.failed + 1
            R.failures[#R.failures + 1] = { title = base .. ": setup", lines = { msg } }
            io.write("  FAIL  (error in test setup)\n          " .. msg .. "\n")
         end
      end
   end
   -- Pruefungen ausserhalb von H.test (zaehlen nur, wenn die Datei zum Filter passt)
   if fileCtx and fileSelected(base) and (#fileCtx.failures > 0 or fileCtx.checks > 0) then
      header()
      if #fileCtx.failures > 0 then
         R.failed = R.failed + 1
         io.write("  FAIL  (checks outside of H.test)\n")
         local lines = {}
         for _, f in ipairs(fileCtx.failures) do
            io.write("          " .. f .. "\n")
            lines[#lines + 1] = f
         end
         R.failures[#R.failures + 1] = { title = base .. ": (file level)", lines = lines }
      else
         R.passed = R.passed + 1
         R.tests = R.tests + 1
         io.write("  ok    (file level checks: " .. fileCtx.checks .. ")\n")
      end
   end
end

-- ---------------------------------------------------------------------------
-- Zusammenfassung
-- ---------------------------------------------------------------------------

io.write("\n" .. srep("-", 70) .. "\n")
if verbose and #R.warnings > 0 then
   io.write("Warnings of the mock (" .. #R.warnings .. "):\n")
   local seen = {}
   for _, w in ipairs(R.warnings) do
      if not seen[w] then
         seen[w] = true
         io.write("   " .. w .. "\n")
      end
   end
end
if showGlobals or verbose then
   local names = {}
   for n in pairs(R.misses) do names[#names + 1] = n end
   table.sort(names)
   if #names > 0 then
      io.write("Globals read by the addon code but never defined (" .. #names .. "):\n")
      for _, n in ipairs(names) do
         io.write(sfmt("   %-40s x%d  first at %s\n", n, R.misses[n].count, R.misses[n].where))
      end
   end
end

if #R.failures > 0 then
   io.write("\nFAILURES (" .. #R.failures .. "):\n")
   for i, f in ipairs(R.failures) do
      io.write(sfmt("%3d) %s\n", i, f.title))
      for _, l in ipairs(f.lines) do io.write("       " .. l .. "\n") end
   end
   io.write("\n")
end

io.write(sfmt("%d tests: %d passed, %d failed", R.tests, R.passed, R.failed))
if R.skipped > 0 then io.write(sfmt(", %d skipped by filter", R.skipped)) end
io.write(sfmt("   (%d checks, %d failed)   %.2f s\n", R.checks, R.failedChecks, realOs.clock() - t0))

if R.tests == 0 and R.failed == 0 then
   io.write("no tests found" .. (filter and (" for filter '" .. filter .. "'") or "") .. "\n")
   realOs.exit(1)
end
realOs.exit(R.failed > 0 and 1 or 0)
