-- Locale.lua
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Locale-Framework. Diese Datei wird ZUERST geladen und
-- legt die globale Tabelle "Transmog" an.
--
--   Transmog.Locale.Add(code, tbl)   Texte einer Sprache hinzufuegen (merged)
--   Transmog.Locale.Set(code)        Sprache waehlen ("auto" = GetLocale())
--   Transmog.Locale.Current()        aufgeloester Code (nie "auto")
--   Transmog.Locale.List()           { {code=, name=}, ... } (native Namen)
--   Transmog.L                       die aktive Textetabelle
--
-- Transmog.L ist eine STABILE Tabelle: sie wird nur geleert und neu gefuellt,
-- nie ersetzt, damit Module sie in einer lokalen Variable halten koennen.
-- Ein fehlender Schluessel liefert den Schluessel selbst (nie nil, nie ein
-- Fehler) und wird in L.__missing (Menge) vermerkt; das hilft beim Aufspueren
-- fehlender Uebersetzungen (/transmog debug).
--
-- Fallback-Kette: gewaehlte Sprache -> (esMX->esES, enGB->enUS) -> enUS.
--
-- WICHTIG: Diese Datei ist UTF-8 ohne BOM. Die Sprachnamen unten sind echte
-- UTF-8-Zeichen.
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog

T.Locale = T.Locale or {}
local Locale = T.Locale

-- Alle Textetabellen: data[code] = { SCHLUESSEL = "Text", ... }
local data = {}

-- Bekannte Codes (alles, was GetLocale() in 3.3.5a liefern kann, plus enUS).
local KNOWN = {
   enUS = true, enGB = true, deDE = true, frFR = true, esES = true,
   esMX = true, ruRU = true, koKR = true, zhCN = true, zhTW = true,
   enCN = true, enTW = true,
}

-- Ersatzsprache, wenn fuer den Code keine eigenen Texte geladen sind.
local ALIAS = {
   esMX = "esES",
   enGB = "enUS",
   enCN = "enUS",
   enTW = "enUS",
}

-- Anzeigereihenfolge und native Namen (UTF-8).
local NAMES = {
   { code = "enUS", name = "English" },
   { code = "deDE", name = "Deutsch" },
   { code = "frFR", name = "Français" },
   { code = "esES", name = "Español" },
   { code = "ruRU", name = "Русский" },
   { code = "koKR", name = "한국어" },
   { code = "zhCN", name = "简体中文" },
   { code = "zhTW", name = "繁體中文" },
}

-- Die aktive Tabelle samt Metatabelle. __missing ist ein ECHTES Feld von L.
local missing = {}
local L = T.L
if type(L) ~= "table" then
   L = {}
   T.L = L
end

setmetatable(L, {
   __index = function(_, key)
      if type(key) == "string" and string.sub(key, 1, 2) ~= "__" then
         missing[key] = true
      end
      return key
   end,
})
rawset(L, "__missing", missing)

-- Zuletzt gewuenschter Code ("auto" oder ein Code) und aufgeloester Code.
local wanted = "auto"
local current = nil

-- Leert eine Tabelle (wipe gibt es nur im Spiel).
local function Wipe(t)
   if type(wipe) == "function" then
      wipe(t)
      return
   end
   for k in pairs(t) do
      t[k] = nil
   end
end

-- Loest "auto"/Aliase/unbekannte Codes in einen konkreten Code auf.
local function Resolve(code)
   if code == nil or code == "auto" then
      code = "enUS"
      if type(GetLocale) == "function" then
         local ok, loc = pcall(GetLocale)
         if ok and type(loc) == "string" and loc ~= "" then
            code = loc
         end
      end
   end
   if type(code) ~= "string" then
      return "enUS"
   end
   -- Alias nur, wenn es fuer den Code selbst keine Texte gibt
   if ALIAS[code] and not data[code] then
      code = ALIAS[code]
   end
   -- Unbekannte Sprache ohne Texte -> Englisch
   if not KNOWN[code] and not data[code] then
      code = "enUS"
   end
   return code
end

-- Baut L aus der Fallback-Kette neu auf (niedrigste Prioritaet zuerst).
local function Rebuild()
   current = Resolve(wanted)

   local chain = { current }
   local alias = ALIAS[current]
   if alias and alias ~= current then
      chain[#chain + 1] = alias
   end
   if chain[#chain] ~= "enUS" then
      chain[#chain + 1] = "enUS"
   end

   Wipe(L)
   for i = #chain, 1, -1 do
      local src = data[chain[i]]
      if src then
         for key, text in pairs(src) do
            L[key] = text
         end
      end
   end
   rawset(L, "__missing", missing)

   -- Schluessel, die jetzt vorhanden sind, gelten nicht mehr als fehlend.
   for key in pairs(missing) do
      if rawget(L, key) ~= nil then
         missing[key] = nil
      end
   end
end

-- Fuegt Texte einer Sprache hinzu (mehrfach je Code moeglich, ueberschreibt).
function Locale.Add(code, tbl)
   if type(code) ~= "string" or code == "" or type(tbl) ~= "table" then
      return
   end
   local dest = data[code]
   if not dest then
      dest = {}
      data[code] = dest
   end
   for key, text in pairs(tbl) do
      if type(key) == "string" then
         dest[key] = text
      end
   end
   -- L sofort aktuell halten, auch wenn Set() noch nicht lief
   Rebuild()
end

-- Waehlt die Sprache ("auto" oder Code), baut L neu und meldet LOCALE_CHANGED.
-- Rueckgabe: der aufgeloeste Code.
function Locale.Set(code)
   if type(code) ~= "string" or code == "" then
      code = "auto"
   end
   wanted = code
   Rebuild()
   local events = T.Events
   if events and type(events.Fire) == "function" then
      events.Fire("LOCALE_CHANGED")
   end
   return current
end

-- Liefert den aufgeloesten Sprachcode (nie "auto").
function Locale.Current()
   if not current then
      current = Resolve(wanted)
   end
   return current
end

-- Liefert eine Kopie der Sprachliste { {code=, name=}, ... } (native Namen).
function Locale.List()
   local out = {}
   for i = 1, #NAMES do
      out[i] = { code = NAMES[i].code, name = NAMES[i].name }
   end
   return out
end
