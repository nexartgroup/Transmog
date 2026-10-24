-- Events.lua
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Ereignisbus (T.Events) und Anbindung an WoW-Ereignisse.
--
--   Events.On / Off / Fire     interner Bus (Namen siehe SPEC 5.3)
--   Events.Game / UnGame       WoW-Ereignisse ueber EINEN gemeinsamen Frame
--
-- Aenderungsfest: Die Handlerlisten werden nie an Ort und Stelle veraendert.
-- On/Off bauen jeweils ein NEUES Array und tauschen es aus (copy-on-write);
-- ein laufendes Fire/Dispatch iteriert ueber das alte Array weiter. Ein
-- Handler, der waehrend dieses Durchlaufs abgemeldet wird, ist als "dead"
-- markiert und wird uebersprungen; ein neu angemeldeter kommt erst beim
-- naechsten Mal dran. Das Feuern selbst kopiert nichts (ITEMS_RESOLVED & Co.
-- feuern mehrmals pro Sekunde).
--
-- Jeder Handler laeuft in pcall; ein Fehler geht an geterrorhandler(), und
-- zwar je Handler und Meldung nur einmal (sonst fluten oft feuernde
-- Ereignisse den Fehlerdialog).
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog

T.Events = T.Events or {}
local Events = T.Events

local MAX_DISTINCT_ERRORS = 10   -- verschiedene Meldungen je Handler

local busHandlers = {}    -- [name]  = { {fn=, owner=, dead=}, ... }
local gameHandlers = {}   -- [event] = { {fn=, dead=}, ... }
local gameRegistered = {} -- [event] = true, wenn am Frame angemeldet
local gameFrame = nil     -- gemeinsamer Frame (erst bei Bedarf erzeugt)

-- Meldet einen Handlerfehler genau einmal je Handler und Meldung.
local function Report(entry, err)
   err = tostring(err)
   local seen = entry.errs
   if not seen then
      seen = {}
      entry.errs = seen
      entry.errCount = 0
   end
   if seen[err] or entry.errCount >= MAX_DISTINCT_ERRORS then
      return
   end
   seen[err] = true
   entry.errCount = entry.errCount + 1

   local getter = _G.geterrorhandler
   local handler = type(getter) == "function" and getter() or nil
   if type(handler) == "function" then
      pcall(handler, err)
   end
end

-- Neues Array = alte Eintraege plus (optional) einer am Ende.
local function Appended(old, entry)
   local list = {}
   local n = old and #old or 0
   for i = 1, n do
      list[i] = old[i]
   end
   list[n + 1] = entry
   return list
end

-- Neues Array = alte Eintraege ohne die, fuer die match(entry) wahr ist; die
-- entfernten werden als "dead" markiert. Rueckgabe: Array, Anzahl entfernter.
local function Without(old, match)
   local list, removed = {}, 0
   for i = 1, #old do
      local e = old[i]
      if match(e) then
         e.dead = true
         removed = removed + 1
      else
         list[#list + 1] = e
      end
   end
   return list, removed
end

-- ---------------------------------------------------------------------------
-- Interner Bus
-- ---------------------------------------------------------------------------

-- Meldet fn(...) fuer das Ereignis name an; owner ist ein optionales Token zum
-- Abmelden. Dieselbe Kombination aus fn und owner wird nur einmal eingetragen.
-- Rueckgabe: true wenn eingetragen.
function Events.On(name, fn, owner)
   if name == nil or type(fn) ~= "function" then
      return false
   end
   local old = busHandlers[name]
   if old then
      for i = 1, #old do
         local e = old[i]
         if e.fn == fn and e.owner == owner then
            return false
         end
      end
   end
   busHandlers[name] = Appended(old, { fn = fn, owner = owner })
   return true
end

-- Meldet alle Handler zu name ab, deren owner oder fn gleich ownerOrFn ist.
-- Ohne ownerOrFn passiert nichts. Rueckgabe: Anzahl entfernter Handler.
function Events.Off(name, ownerOrFn)
   if ownerOrFn == nil or name == nil then
      return 0
   end
   local old = busHandlers[name]
   if not old then
      return 0
   end
   local list, removed = Without(old, function(e)
      return e.fn == ownerOrFn or e.owner == ownerOrFn
   end)
   if removed > 0 then
      if #list > 0 then
         busHandlers[name] = list
      else
         busHandlers[name] = nil
      end
   end
   return removed
end

-- Ruft alle Handler zu name in Registrierungsreihenfolge mit (...) auf;
-- jeder geschuetzt. Keine Rueckgabe.
function Events.Fire(name, ...)
   local list = name ~= nil and busHandlers[name] or nil
   if not list then
      return
   end
   for i = 1, #list do
      local e = list[i]
      if not e.dead then
         local ok, err = pcall(e.fn, ...)
         if not ok then
            Report(e, err)
         end
      end
   end
end

-- ---------------------------------------------------------------------------
-- WoW-Ereignisse
-- ---------------------------------------------------------------------------

-- OnEvent des gemeinsamen Frames: verteilt an die Handler des Ereignisses.
local function Dispatch(_, event, ...)
   local list = gameHandlers[event]
   if not list then
      return
   end
   for i = 1, #list do
      local e = list[i]
      if not e.dead then
         local ok, err = pcall(e.fn, event, ...)
         if not ok then
            Report(e, err)
         end
      end
   end
end

-- Erzeugt den gemeinsamen Frame beim ersten Bedarf (nil ohne CreateFrame).
local function EnsureFrame()
   if gameFrame then
      return gameFrame
   end
   if type(CreateFrame) ~= "function" then
      return nil
   end
   gameFrame = CreateFrame("Frame")
   gameFrame:SetScript("OnEvent", Dispatch)
   return gameFrame
end

-- Registriert ein WoW-Ereignis; fn(event, ...) wird gerufen. Dieselbe Funktion
-- wird je Ereignis nur einmal eingetragen. Rueckgabe: true wenn eingetragen.
function Events.Game(event, fn)
   if type(event) ~= "string" or event == "" or type(fn) ~= "function" then
      return false
   end
   local old = gameHandlers[event]
   if old then
      for i = 1, #old do
         if old[i].fn == fn then
            return false
         end
      end
   end
   gameHandlers[event] = Appended(old, { fn = fn })

   if not gameRegistered[event] then
      local frame = EnsureFrame()
      if frame then
         -- pcall: ein unbekannter Ereignisname darf den Start nicht stoeren
         pcall(frame.RegisterEvent, frame, event)
         gameRegistered[event] = true
      end
   end
   return true
end

-- Meldet fn fuer ein WoW-Ereignis ab; sind keine Handler mehr uebrig, wird das
-- Ereignis am Frame abgemeldet. Rueckgabe: true wenn etwas entfernt wurde.
function Events.UnGame(event, fn)
   if type(fn) ~= "function" or event == nil then
      return false
   end
   local old = gameHandlers[event]
   if not old then
      return false
   end
   local list, removed = Without(old, function(e)
      return e.fn == fn
   end)
   if removed == 0 then
      return false
   end
   if #list > 0 then
      gameHandlers[event] = list
   else
      gameHandlers[event] = nil
      if gameFrame and gameRegistered[event] then
         pcall(gameFrame.UnregisterEvent, gameFrame, event)
         gameRegistered[event] = nil
      end
   end
   return true
end
