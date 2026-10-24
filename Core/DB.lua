-- DB.lua
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Gespeicherte Einstellungen (T.DB).
--
--   TransmogGlobalDB   (SavedVariables)               DB.global  - kontoweit
--   TransmogDB         (SavedVariablesPerCharacter)   DB.char    - je Charakter
--
-- Ablauf von DB.Init() (Boot, bei ADDON_LOADED -- erst dann sind die
-- gespeicherten Variablen da):
--   1. Tabellen anlegen bzw. uebernehmen
--   1b. (seit 2.1) einmalig: global.allowAnywhere auf true setzen, solange die
--      Marke global.noNpcDefault fehlt, und die Marke setzen. Gespeicherte Dateien
--      der Version 2.0 tragen dort den frueheren Standard false; ab der Marke
--      gilt die Wahl des Spielers (auch ein bewusstes false). Laeuft VOR 2.
--   2. Vorgaben rekursiv ergaenzen (vorhandene Werte werden nie ueberschrieben)
--   3. Altdaten einmalig uebernehmen (char.migrated < 2): transmogOutfits und
--      transmogSettings der Version 1.x; die Altvariablen bleiben unberuehrt
--   4. Werte pruefen und auf gueltige Bereiche bringen
-- Alles ist idempotent; DB.Init() darf beliebig oft laufen.
--
-- Schluessel: siehe SPEC 5.4 / 7. Nur DB.Set / DB.SetChar aendern Werte mit
-- Benachrichtigung (SETTINGS_CHANGED).
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog

T.DB = T.DB or {}
local DB = T.DB

local DB_VERSION = 2
local MAX_OUTFIT_NAME = 32   -- UTF-8-Zeichen (wie Outfits.MAX_NAME)
local MAX_OUTFITS = 50

-- Die 14 transmogbaren Server-Slots (Protokoll, siehe SPEC 2)
local SERVER_SLOTS = {
   [0] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
   [7] = true, [8] = true, [9] = true, [14] = true, [15] = true,
   [16] = true, [17] = true, [18] = true,
}

local VALID_LOCALES = {
   auto = true, enUS = true, enGB = true, deDE = true, frFR = true,
   esES = true, esMX = true, ruRU = true, koKR = true, zhCN = true,
   zhTW = true,
}

local PREVIEW_SIZES = { 0.8, 1.0, 1.25, 1.5 }

local SORT_KEYS = { QUALITY = true, NAME = true, ILEVEL = true }

local ANCHORS = {
   TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
   RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- ---------------------------------------------------------------------------
-- Vorgaben
-- ---------------------------------------------------------------------------

-- Liefert frische Vorgabetabellen (nie geteilte Referenzen).
local function GlobalDefaults()
   return {
      version = DB_VERSION,
      locale = "auto",
      scale = 0,               -- 0 = automatisch
      width = 880,
      height = 600,
      -- point = nil           -- { point, relPoint, x, y }
      previewSize = 1.0,
      sound = true,
      toasts = true,
      -- toastPoint = nil
      tooltipCollected = true,
      tooltipApplied = true,
      allowAnywhere = true,    -- seit 2.1 an: der Server prueft den Abstand zum Transmogrifizierer nicht
      lastTab = "items",
   }
end

local function CharDefaults()
   return {
      version = DB_VERSION,
      outfits = {},            -- Array { name=, slots={[server]=id}, time= }
      favorites = {},          -- [itemId] = true
      filter = {
         qualities = {},       -- [0..7] = false: ausgeblendet (nil = sichtbar)
         typesOff = {},        -- [typeKey] = true: ausgeblendet
         hideDuplicates = true,
         sort = "QUALITY",
         favoritesOnly = false,
         newOnly = false,
      },
      -- lastSlot = nil
      migrated = 0,
   }
end

-- Ergaenzt target rekursiv um fehlende Werte aus defaults. Vorhandene Werte
-- bleiben; nur wenn ein Wert eine Tabelle sein soll und keine ist, wird er
-- durch die Vorgabe ersetzt.
local function MergeDefaults(target, defaults)
   for key, def in pairs(defaults) do
      local cur = target[key]
      if type(def) == "table" then
         if type(cur) ~= "table" then
            target[key] = def
         else
            MergeDefaults(cur, def)
         end
      elseif cur == nil then
         target[key] = def
      end
   end
end

-- ---------------------------------------------------------------------------
-- Pruefung einzelner Werte
-- ---------------------------------------------------------------------------

-- true bei einer endlichen Zahl.
local function IsNumber(v)
   return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Liefert eine Pruefung "boolean oder Vorgabe".
local function BoolOr(default)
   return function(v)
      if type(v) == "boolean" then
         return v
      end
      return default
   end
end

-- Liefert eine Pruefung "Pixelmass: positive Zahl, nach oben begrenzt"; alles
-- andere (Text, NaN, 0, negativ) ergibt die Vorgabe.
local function SizeOr(default)
   return function(v)
      if not IsNumber(v) or v <= 0 then
         return default
      end
      if v > 8192 then
         return 8192
      end
      return v
   end
end

-- Fensterposition { point, relPoint, x, y } (auch benannte Felder point/x/y
-- oder die 5-teilige Form von GetPoint). Gueltig, wenn zwei Zahlen (x, y)
-- dabei sind und ein vorhandener Ankerpunkt (Eintrag 1 bzw. .point) ein
-- bekannter Name ist; ein Unsinns-Anker ergibt nil. Sonst wird die Tabelle
-- unveraendert zurueckgegeben (nie umgebaut: die Besitzer lesen ihre Form).
local function SanePoint(v)
   if type(v) ~= "table" then
      return nil
   end
   local anchor = v[1]
   if anchor == nil then
      anchor = v.point
   end
   if anchor ~= nil and (type(anchor) ~= "string" or not ANCHORS[anchor]) then
      return nil
   end
   local numbers = 0
   for i = 2, 5 do
      if IsNumber(v[i]) then
         numbers = numbers + 1
      end
   end
   if IsNumber(v.x) and IsNumber(v.y) then
      numbers = 2
   end
   if numbers < 2 then
      return nil
   end
   return v
end

-- Pruefungen fuer DB.global (Schluessel -> function(wert) -> gueltiger Wert).
local GLOBAL_CHECKS = {
   locale = function(v)
      if type(v) == "string" and VALID_LOCALES[v] then
         return v
      end
      return "auto"
   end,
   scale = function(v)
      if not IsNumber(v) or v <= 0 then
         return 0
      end
      if v < 0.6 then
         return 0.6
      elseif v > 1.5 then
         return 1.5
      end
      return v
   end,
   width = SizeOr(880),
   height = SizeOr(600),
   point = SanePoint,
   previewSize = function(v)
      if not IsNumber(v) then
         return 1.0
      end
      local best, bestDist = 1.0, math.huge
      for i = 1, #PREVIEW_SIZES do
         local dist = math.abs(PREVIEW_SIZES[i] - v)
         if dist < bestDist then
            best, bestDist = PREVIEW_SIZES[i], dist
         end
      end
      return best
   end,
   sound = BoolOr(true),
   toasts = BoolOr(true),
   toastPoint = SanePoint,
   tooltipCollected = BoolOr(true),
   tooltipApplied = BoolOr(true),
   allowAnywhere = BoolOr(true),
   lastTab = function(v)
      if v == "items" or v == "outfits" then
         return v
      end
      return "items"
   end,
}

-- Pruefungen fuer einzelne Felder von DB.char, die per SetChar geaendert werden.
local CHAR_CHECKS = {
   lastSlot = function(v)
      if type(v) == "number" and SERVER_SLOTS[v] then
         return v
      end
      return nil
   end,
}

-- ---------------------------------------------------------------------------
-- Altdaten (Version 1.x)
-- ---------------------------------------------------------------------------

-- Bereinigt einen Outfit-Namen wie Outfits.NormalizeName: Farbcodes (|cAARRGGBB,
-- |r) und uebrige "|" sowie Steuerzeichen entfernen, Leerraum zusammenfassen,
-- trimmen.
local function CleanName(name)
   name = string.gsub(name, "|c%x%x%x%x%x%x%x%x", "")
   name = string.gsub(name, "|r", "")
   name = string.gsub(name, "[%c|]", "")
   name = string.gsub(name, "%s+", " ")
   return (string.match(name, "^%s*(.-)%s*$"))
end

-- Kuerzt s auf hoechstens maxChars UTF-8-Zeichen (nie mitten im Zeichen);
-- Fortsetzungsbytes (0x80..0xBF) zaehlen nicht mit.
local function TruncateChars(s, maxChars)
   local count = 0
   for i = 1, #s do
      local b = string.byte(s, i)
      if b < 0x80 or b >= 0xC0 then
         count = count + 1
         if count > maxChars then
            return string.sub(s, 1, i - 1)
         end
      end
   end
   return s
end

-- Kleinschreibung fuer den Namensvergleich (wie Outfits: Util.Lower).
local function LowerName(s)
   local util = T.Util
   if type(util) == "table" and type(util.Lower) == "function" then
      return util.Lower(s)
   end
   return string.lower(s)
end

-- Nimmt transmogOutfits und transmogSettings in char auf und setzt
-- char.migrated. Rueckgabe: Anzahl uebernommener Outfits (0 wenn nichts
-- oder bereits erledigt).
local function MigrateLegacy(char)
   -- Kein endlicher Zahlenwert (Text, NaN, unendlich) zaehlt als "nie migriert";
   -- unendlich darf nicht als "schon erledigt" durchgehen und danach auf 0
   -- zurueckgesetzt werden (sonst liefe die Uebernahme bei jedem Start erneut).
   if not IsNumber(char.migrated) then
      char.migrated = 0
   end
   if char.migrated >= DB_VERSION then
      return 0
   end

   local imported = 0

   -- --- Outfits: Name -> { [clientSlot] = itemId } ----------------------
   local old = _G["transmogOutfits"]
   if type(old) == "table" then
      -- feste Reihenfolge (pairs ist beliebig): nach Name sortiert
      local names = {}
      for name, data in pairs(old) do
         if type(name) == "string" and type(data) == "table" then
            names[#names + 1] = name
         end
      end
      table.sort(names)

      -- schon vorhandene Namen (ohne Beachtung der Gross-/Kleinschreibung)
      local taken = {}
      for i = 1, #char.outfits do
         local o = char.outfits[i]
         if type(o) == "table" and type(o.name) == "string" then
            taken[LowerName(o.name)] = true
         end
      end

      local limit = MAX_OUTFITS
      local maxName = MAX_OUTFIT_NAME
      if type(T.Outfits) == "table" then
         if type(T.Outfits.MAX) == "number" then
            limit = T.Outfits.MAX
         end
         if type(T.Outfits.MAX_NAME) == "number" then
            maxName = T.Outfits.MAX_NAME
         end
      end

      local now = type(time) == "function" and time() or 0

      for _, rawName in ipairs(names) do
         if #char.outfits >= limit then
            break
         end
         local name = CleanName(rawName)
         name = CleanName(TruncateChars(name, maxName))
         if name ~= "" then
            -- Namenskollision (auch nach dem Kuerzen): " (2)", " (3)" ...
            local candidate, n = name, 1
            while taken[LowerName(candidate)] and n < 99 do
               n = n + 1
               local suffix = " (" .. n .. ")"
               candidate = CleanName(TruncateChars(name, maxName - #suffix)) .. suffix
            end
            if not taken[LowerName(candidate)] then
               local slots = {}
               for clientSlot, itemId in pairs(old[rawName]) do
                  local id = tonumber(itemId)
                  if type(clientSlot) == "number" and id and id > 0
                     and id == math.floor(id) then
                     local server = clientSlot - 1
                     if SERVER_SLOTS[server] then
                        slots[server] = id
                     end
                  end
               end
               char.outfits[#char.outfits + 1] = {
                  name = candidate,
                  slots = slots,
                  time = now,
               }
               taken[LowerName(candidate)] = true
               imported = imported + 1
            end
         end
      end
   end

   -- --- Einstellungen -----------------------------------------------------
   local settings = _G["transmogSettings"]
   if type(settings) == "table" then
      if type(settings.hideDuplicates) == "boolean" then
         char.filter.hideDuplicates = settings.hideDuplicates
      end

      -- armorTypes: Schluessel 5..8 = Stoff/Leder/Kette/Platte. Ein fehlender
      -- Schluessel galt als "aus", ausser Kette (7). Jede ausgeschaltete Stufe
      -- wird zum ausgeblendeten Typ 401..404.
      local armor = settings.armorTypes
      if type(armor) == "table" then
         for key = 5, 8 do
            local on = armor[key]
            if on == nil then
               on = (key == 7)
            end
            if not on then
               char.filter.typesOff[400 + (key - 4)] = true
            end
         end
      end
   end

   char.migrated = DB_VERSION
   return imported
end

-- ---------------------------------------------------------------------------
-- Aufraeumen geladener Daten
-- ---------------------------------------------------------------------------

-- Bringt DB.global auf gueltige Werte.
local function SanitizeGlobal(g)
   for key, check in pairs(GLOBAL_CHECKS) do
      local value = check(g[key])
      if g[key] ~= value then
         g[key] = value
      end
   end
   if not IsNumber(g.version) or g.version < DB_VERSION then
      g.version = DB_VERSION
   end
end

-- Entfernt ungueltige Eintraege einer Menge { [zahl] = wert }; keep(k, v)
-- entscheidet, ob ein Eintrag bleibt.
local function PruneSet(set, keep)
   for k, v in pairs(set) do
      if not keep(k, v) then
         set[k] = nil
      end
   end
end

-- Bringt DB.char auf gueltige Werte.
local function SanitizeChar(c)
   local f = c.filter

   -- Qualitaeten: nur 0..7, nur "false" (ausgeblendet) ist sinnvoll
   PruneSet(f.qualities, function(k, v)
      return type(k) == "number" and k >= 0 and k <= 7 and k == math.floor(k)
         and v == false
   end)
   -- Typen: nur Zahlenschluessel mit true
   PruneSet(f.typesOff, function(k, v)
      return type(k) == "number" and k == math.floor(k) and v == true
   end)
   f.hideDuplicates = BoolOr(true)(f.hideDuplicates)
   f.favoritesOnly = BoolOr(false)(f.favoritesOnly)
   f.newOnly = BoolOr(false)(f.newOnly)
   if type(f.sort) ~= "string" or not SORT_KEYS[f.sort] then
      f.sort = "QUALITY"
   end

   -- Favoriten: [itemId] = true
   PruneSet(c.favorites, function(k, v)
      return type(k) == "number" and k >= 1 and k == math.floor(k) and v == true
   end)

   -- Outfits: nur wohlgeformte Eintraege behalten (Array an Ort und Stelle
   -- verdichten, damit Referenzen auf die Tabelle gueltig bleiben)
   local list = c.outfits
   local kept = {}
   for i = 1, #list do
      local o = list[i]
      if type(o) == "table" and type(o.name) == "string" and o.name ~= ""
         and type(o.slots) == "table" then
         PruneSet(o.slots, function(k, v)
            return type(k) == "number" and SERVER_SLOTS[k] == true
               and type(v) == "number" and v >= 1 and v == math.floor(v)
         end)
         if not IsNumber(o.time) then
            o.time = 0
         end
         kept[#kept + 1] = o
      end
   end
   for i = #list, 1, -1 do
      list[i] = nil
   end
   for i = 1, #kept do
      list[i] = kept[i]
   end

   -- Sonstiges
   if type(c.lastSlot) ~= "number" or not SERVER_SLOTS[c.lastSlot] then
      c.lastSlot = nil
   end
   if not IsNumber(c.version) or c.version < DB_VERSION then
      c.version = DB_VERSION
   end
   if not IsNumber(c.migrated) then
      c.migrated = 0
   end
end

-- ---------------------------------------------------------------------------
-- Oeffentliche API
-- ---------------------------------------------------------------------------

-- Legt TransmogGlobalDB/TransmogDB an, ergaenzt Vorgaben, uebernimmt Altdaten
-- (einmalig) und prueft die Werte. Rueckgabe: DB.global, DB.char.
function DB.Init()
   local g = TransmogGlobalDB
   if type(g) ~= "table" then
      g = {}
      TransmogGlobalDB = g
   end
   local c = TransmogDB
   if type(c) ~= "table" then
      c = {}
      TransmogDB = c
   end

   -- Seit 2.1 ist "Anwenden auch ohne Transmogrifizierer" standardmaessig an. Gespeicherte Dateien aelterer Staende tragen dort
   -- noch den frueheren Standardwert false: einmalig (Marke noNpcDefault) auf true setzen, danach gilt die Wahl des Spielers.
   -- Muss VOR dem Ergaenzen der Vorgaben laufen (sonst waere die Marke schon "gesetzt").
   if g.noNpcDefault ~= true then
      g.allowAnywhere = true
      g.noNpcDefault = true
   end

   MergeDefaults(g, GlobalDefaults())
   MergeDefaults(c, CharDefaults())

   local imported = MigrateLegacy(c)

   SanitizeGlobal(g)
   SanitizeChar(c)

   DB.global = g
   DB.char = c

   -- Einmalige Meldung; verzoegert, damit Chat und Sprache bereit sind.
   if imported > 0 and T.Util and T.Util.After then
      T.Util.After(4, function()
         T.Util.Print(T.L.MIGRATED_OUTFITS, imported)
      end)
   end

   return g, c
end

-- Stellt sicher, dass DB.Init gelaufen ist (Schutz gegen falsche Reihenfolge).
local function EnsureInit()
   if not DB.global or not DB.char then
      DB.Init()
   end
end

-- Meldet SETTINGS_CHANGED(key), falls der Bus existiert.
local function Changed(key)
   local events = T.Events
   if events and type(events.Fire) == "function" then
      events.Fire("SETTINGS_CHANGED", key)
   end
end

-- Setzt DB.global[key] (bekannte Schluessel werden auf gueltige Werte gebracht)
-- und feuert SETTINGS_CHANGED(key).
function DB.Set(key, value)
   if key == nil then
      return
   end
   EnsureInit()
   local check = GLOBAL_CHECKS[key]
   if check then
      value = check(value)
   end
   DB.global[key] = value
   Changed(key)
end

-- Setzt DB.char[key] und feuert SETTINGS_CHANGED(key).
function DB.SetChar(key, value)
   if key == nil then
      return
   end
   EnsureInit()
   local check = CHAR_CHECKS[key]
   if check then
      value = check(value)
   end
   DB.char[key] = value
   Changed(key)
end
