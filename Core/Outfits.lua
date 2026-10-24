-- Core\Outfits.lua
-- ---------------------------------------------------------------------------
-- Gespeicherte Outfits (Aussehen-Zusammenstellungen) des Charakters.
--
-- Speicher: DB.char.outfits, ein Array { name=, slots={[server]=itemId|999999},
-- time= }. Namen sind ohne Beachtung der Gross-/Kleinschreibung eindeutig,
-- getrimmt und hoechstens 32 Zeichen lang; es gibt hoechstens Outfits.MAX.
--
-- Semantik (Verbesserungen gegenueber dem alten Addon):
--   * Save ueberschreibt NIE stillschweigend; Ueberschreiben nur ueber
--     Outfits.Overwrite (explizit).
--   * Load uebernimmt nur Teile, die fuer den angelegten Gegenstand wirklich
--     verfuegbar sind (State.SlotState == "READY" und State.IsAvailable),
--     setzt sie mit EINEM State.SetMany-Aufruf und meldet uebersprungene Teile
--     samt Grund zurueck. Kein sofortiges Anwenden: der Spieler bestaetigt im
--     Fenster.
--   * CurrentLook beruht auf State.Wanted (Auswahl ODER angewendet) und
--     enthaelt auch "Verborgen".
-- ---------------------------------------------------------------------------

local T = Transmog

local Outfits = {}
T.Outfits = Outfits

local type, tonumber, tostring, pairs, next = type, tonumber, tostring, pairs, next
local floor = math.floor
local sort = table.sort
local gsub, find, format, match = string.gsub, string.find, string.format, string.match
local sub, byte = string.sub, string.byte

Outfits.MAX = 50        -- maximale Anzahl gespeicherter Outfits
Outfits.MAX_NAME = 32   -- maximale Namenslaenge (Zeichen, UTF-8)

-- ---------------------------------------------------------------------------
-- Konstanten (Server-Slots laut Protokoll, siehe SPEC 2)
-- ---------------------------------------------------------------------------

-- Die 14 transmogbaren Server-Slots, aufsteigend
local SERVER_SLOTS = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }

-- Slots, in denen "Verborgen" erlaubt ist (Kopf bis Haende, Ruecken, Wappenrock)
local HIDEABLE = {
   [0] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
   [7] = true, [8] = true, [9] = true, [14] = true, [18] = true,
}

local IS_SLOT = {}
for i = 1, #SERVER_SLOTS do IS_SLOT[SERVER_SLOTS[i]] = true end

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------------

-- Id des "Verborgen"-Aussehens
local function HiddenId()
   return T.HIDDEN_ID or 999999
end

-- Aktuelle Zeit (time), 0 ausserhalb des Spiels
local function Now()
   if type(time) == "function" then return time() end
   return 0
end

-- Feuert ein Bus-Ereignis, falls der Bus existiert
local function Fire(name, ...)
   local ev = T.Events
   if type(ev) == "table" and type(ev.Fire) == "function" then
      ev.Fire(name, ...)
   end
end

-- Kleinschreibung (UTF-8-faehig ueber Util.Lower)
local function Lower(s)
   local Util = T.Util
   if type(Util) == "table" and type(Util.Lower) == "function" then
      return Util.Lower(s)
   end
   return string.lower(s)
end

-- Anzahl Zeichen eines UTF-8-Strings (Fortsetzungsbytes 0x80..0xBF zaehlen nicht)
local function Utf8Len(s)
   local _, n = gsub(s, "[^\128-\191]", "")
   return n
end

-- Kuerzt einen UTF-8-String auf hoechstens max Zeichen (nie mitten in einer
-- Mehrbyte-Folge); danach getrimmt
local function TruncateChars(s, max)
   if Utf8Len(s) <= max then return s end
   local count = 0
   for i = 1, #s do
      local b = byte(s, i)
      if b < 128 or b >= 192 then   -- Folgebytes (128..191) zaehlen nicht
         count = count + 1
         if count > max then
            return (match(sub(s, 1, i - 1), "^(.-)%s*$"))
         end
      end
   end
   return s
end

-- Notfall-Speicher, falls DB.char noch nicht existiert
local volatileStore = {}

-- Liefert das Outfit-Array (DB.char.outfits)
local function Store()
   local db = T.DB
   local char = type(db) == "table" and db.char or nil
   if type(char) ~= "table" then return volatileStore end
   if type(char.outfits) ~= "table" then char.outfits = {} end
   return char.outfits
end

-- Standardname "Outfit n" (aus L.OUTFIT_DEFAULT_NAME, mit sicherem Fallback)
local function DefaultName(n)
   local fmt = T.L and T.L.OUTFIT_DEFAULT_NAME
   if type(fmt) ~= "string" or not find(fmt, "%%d") then
      fmt = "Outfit %d"
   end
   return format(fmt, n)
end

-- Anzahl der belegten Slots einer Slot-Tabelle
local function CountSlots(slots)
   local n = 0
   for i = 1, #SERVER_SLOTS do
      if slots[SERVER_SLOTS[i]] then n = n + 1 end
   end
   return n
end

-- Bereinigte Kopie einer Slot-Tabelle: nur die 14 Slots, nur gueltige Item-IDs
-- (ganze Zahlen > 0) bzw. HIDDEN fuer verbergbare Slots. Rueckgabe: slots, count
local function CleanSlots(src)
   local out, count = {}, 0
   if type(src) ~= "table" then return out, 0 end
   local hidden = HiddenId()
   for i = 1, #SERVER_SLOTS do
      local s = SERVER_SLOTS[i]
      local v = src[s]
      if v == nil then v = src[tostring(s)] end   -- tolerant gegen String-Schluessel
      v = tonumber(v)
      if v and v > 0 and v == floor(v) then
         if v ~= hidden or HIDEABLE[s] then
            out[s] = v
            count = count + 1
         end
      end
   end
   return out, count
end

-- Index und Outfit zu einem (normalisierten) Namen, ohne Beachtung der
-- Gross-/Kleinschreibung. Rueckgabe: index, outfit | nil
local function FindOutfit(list, norm)
   if norm == "" then return nil end
   local key = Lower(norm)
   for i = 1, #list do
      local o = list[i]
      if type(o) == "table" and type(o.name) == "string" and Lower(o.name) == key then
         return i, o
      end
   end
   return nil
end

-- Prueft einen normalisierten Namen. exceptIndex: dieses Outfit zaehlt bei der
-- Eindeutigkeit nicht (Umbenennen). Rueckgabe: ok, errKey
local function CheckName(list, norm, exceptIndex)
   if norm == "" then return false, "OUTFIT_ERR_EMPTY" end
   if Utf8Len(norm) > Outfits.MAX_NAME then return false, "OUTFIT_ERR_LONG" end
   local idx = FindOutfit(list, norm)
   if idx and idx ~= exceptIndex then return false, "OUTFIT_ERR_EXISTS" end
   return true
end

-- Aktualisiert das abgeleitete Feld count und gibt das Outfit zurueck
local function Touch(o)
   if type(o.slots) ~= "table" then o.slots = {} end
   o.count = CountSlots(o.slots)
   return o
end

-- ---------------------------------------------------------------------------
-- Oeffentliche Namensfunktionen
-- ---------------------------------------------------------------------------

-- Outfits.NormalizeName(name) -> bereinigter Name ("" bei nil/Muell):
-- Farbcodes (|cAARRGGBB ... |r) samt Code, uebrige "|" und Steuerzeichen
-- entfernt, Leerraum zusammengefasst, getrimmt. Zahlen gelten als Text.
function Outfits.NormalizeName(name)
   if type(name) == "number" then name = tostring(name) end
   if type(name) ~= "string" then return "" end
   name = (gsub(name, "|c%x%x%x%x%x%x%x%x", ""))
   name = (gsub(name, "|r", ""))
   name = (gsub(name, "%s+", " "))
   name = (gsub(name, "[%c|]", ""))
   name = (gsub(name, " +", " "))   -- nach dem Entfernen erneut zusammenfassen
   local Util = T.Util
   if type(Util) == "table" and type(Util.Trim) == "function" then
      return Util.Trim(name)
   end
   return (match(name, "^%s*(.-)%s*$"))
end

-- Outfits.ValidateName(name) -> ok, errKey, normalizedName
-- errKey: "OUTFIT_ERR_EMPTY" | "OUTFIT_ERR_LONG" | "OUTFIT_ERR_EXISTS"
function Outfits.ValidateName(name)
   local norm = Outfits.NormalizeName(name)
   local ok, err = CheckName(Store(), norm, nil)
   return ok, err, norm
end

-- Outfits.SuggestName() -> unbenutzter Standardname ("Outfit n")
function Outfits.SuggestName()
   local list = Store()
   local n = #list + 1
   local name = DefaultName(n)
   -- Begrenzte Suche (schuetzt vor einem Fehlschluessel ohne Platzhalter)
   for _ = 1, Outfits.MAX + 2 do
      if not FindOutfit(list, name) then return name end
      n = n + 1
      name = DefaultName(n)
   end
   return name
end

-- ---------------------------------------------------------------------------
-- Abfragen
-- ---------------------------------------------------------------------------

-- Outfits.List() -> Array von { name, slots, count, time } (Referenzen auf die
-- gespeicherten Outfits, in Speicherreihenfolge). Das Array selbst ist neu.
function Outfits.List()
   local list = Store()
   local out = {}
   for i = 1, #list do
      local o = list[i]
      if type(o) == "table" then
         out[#out + 1] = Touch(o)
      end
   end
   return out
end

-- Outfits.Get(name) -> Outfit | nil (Name ohne Beachtung der Gross-/Kleinschreibung)
function Outfits.Get(name)
   local _, o = FindOutfit(Store(), Outfits.NormalizeName(name))
   if o then return Touch(o) end
   return nil
end

-- Outfits.Exists(name) -> bool
function Outfits.Exists(name)
   return FindOutfit(Store(), Outfits.NormalizeName(name)) ~= nil
end

-- Outfits.Count() -> Anzahl gespeicherter Outfits
function Outfits.Count()
   return #Store()
end

-- Outfits.CurrentLook() -> { [server]=itemId|HIDDEN }
-- Effektiver Look: State.Wanted(slot) ~= 0 (nur die 14 Slots, inkl. Verborgen).
function Outfits.CurrentLook()
   local look = {}
   local State = T.State
   if type(State) ~= "table" or type(State.Wanted) ~= "function" then
      return look
   end
   local hidden = HiddenId()
   for i = 1, #SERVER_SLOTS do
      local s = SERVER_SLOTS[i]
      local w = State.Wanted(s)
      if type(w) == "number" and w > 0 then
         if w ~= hidden or HIDEABLE[s] then
            look[s] = w
         end
      end
   end
   return look
end

-- ---------------------------------------------------------------------------
-- Aendern
-- ---------------------------------------------------------------------------

-- Outfits.Save(name, slots) -> ok, errKey
-- Legt ein NEUES Outfit an (slots = nil: aktueller Look). Existiert der Name
-- schon, wird NICHT ueberschrieben (-> "OUTFIT_ERR_EXISTS"); dafuer gibt es
-- Outfits.Overwrite. Weitere Fehler: "OUTFIT_ERR_FULL" (Limit erreicht),
-- "OUTFIT_ERR_NOITEMS" (nichts zu speichern).
function Outfits.Save(name, slots)
   local list = Store()
   local norm = Outfits.NormalizeName(name)
   local ok, err = CheckName(list, norm, nil)
   if not ok then return false, err end
   if #list >= Outfits.MAX then return false, "OUTFIT_ERR_FULL" end

   if type(slots) ~= "table" then slots = Outfits.CurrentLook() end
   local clean, count = CleanSlots(slots)
   if count == 0 then return false, "OUTFIT_ERR_NOITEMS" end

   list[#list + 1] = { name = norm, slots = clean, count = count, time = Now() }
   Fire("OUTFITS_CHANGED")
   return true
end

-- Outfits.Overwrite(name, slots) -> ok, errKey
-- Ersetzt die Teile eines bestehenden Outfits (slots = nil: aktueller Look);
-- der Name bleibt. Fehler: "OUTFIT_ERR_MISSING", "OUTFIT_ERR_NOITEMS".
function Outfits.Overwrite(name, slots)
   local list = Store()
   local _, o = FindOutfit(list, Outfits.NormalizeName(name))
   if not o then return false, "OUTFIT_ERR_MISSING" end

   if type(slots) ~= "table" then slots = Outfits.CurrentLook() end
   local clean, count = CleanSlots(slots)
   if count == 0 then return false, "OUTFIT_ERR_NOITEMS" end

   o.slots = clean
   o.count = count
   o.time = Now()
   Fire("OUTFITS_CHANGED")
   return true
end

-- Outfits.Delete(name) -> ok, errKey ("OUTFIT_ERR_MISSING")
function Outfits.Delete(name)
   local list = Store()
   local idx = FindOutfit(list, Outfits.NormalizeName(name))
   if not idx then return false, "OUTFIT_ERR_MISSING" end
   table.remove(list, idx)
   Fire("OUTFITS_CHANGED")
   return true
end

-- Outfits.Rename(old, new) -> ok, errKey
-- Fehler: "OUTFIT_ERR_MISSING", "OUTFIT_ERR_EMPTY", "OUTFIT_ERR_LONG",
-- "OUTFIT_ERR_EXISTS" (anderes Outfit traegt den Namen). Nur die Schreibweise
-- zu aendern ("foo" -> "Foo") ist erlaubt.
function Outfits.Rename(old, new)
   local list = Store()
   local idx, o = FindOutfit(list, Outfits.NormalizeName(old))
   if not o then return false, "OUTFIT_ERR_MISSING" end

   local norm = Outfits.NormalizeName(new)
   if norm == o.name then return true end
   local ok, err = CheckName(list, norm, idx)
   if not ok then return false, err end

   o.name = norm
   Fire("OUTFITS_CHANGED")
   return true
end

-- ---------------------------------------------------------------------------
-- Laden
-- ---------------------------------------------------------------------------

-- Grund, warum (slot, id) NICHT uebernommen werden kann; nil = uebernehmbar.
-- Entscheidend sind Slot-Zustand "READY" und State.IsAvailable; die Listen-
-- Fertigmeldung dient nur dazu, den Grund genauer zu benennen.
local function SkipReason(State, slot, id)
   local st = nil
   if type(State.SlotState) == "function" then st = State.SlotState(slot) end
   if st == "NEVER" then return "OUTFIT_SKIP_NEVER" end
   if st ~= "READY" then return "OUTFIT_SKIP_EMPTY" end

   local available = false
   if type(State.IsAvailable) == "function" then
      available = State.IsAvailable(slot, id) and true or false
   end

   if id == HiddenId() then
      -- Verborgen braucht keine Liste, nur einen verbergbaren Slot
      if HIDEABLE[slot] and available then return nil end
      return "OUTFIT_SKIP_HIDDEN"
   end

   if available then return nil end
   local list = nil
   if type(State.List) == "function" then list = State.List(slot) end
   if type(list) == "table" and list.ready == false then
      return "OUTFIT_SKIP_LOADING"
   end
   return "OUTFIT_SKIP_UNAVAILABLE"
end

-- Gueltige Item-ID (ganze Zahl > 0, auch HIDDEN) eines Slots oder nil
local function SlotItem(slots, s)
   local v = slots[s]
   if v == nil then v = slots[tostring(s)] end
   v = tonumber(v)
   if v and v > 0 and v == floor(v) then return v end
   return nil
end

-- Wertet ein Outfit gegen den aktuellen Zustand aus (ohne Seiteneffekte).
-- Rueckgabe: applied (Array Slots), skipped (Array {slot,id,reasonKey}), map
local function Evaluate(o)
   local applied, skipped, map = {}, {}, {}
   local State = T.State
   if type(State) ~= "table" then return applied, skipped, map end
   local slots = o.slots
   if type(slots) ~= "table" then return applied, skipped, map end

   -- Deterministisch in aufsteigender Slot-Reihenfolge
   for i = 1, #SERVER_SLOTS do
      local s = SERVER_SLOTS[i]
      local id = SlotItem(slots, s)
      if id then
         local reason = SkipReason(State, s, id)
         if reason then
            skipped[#skipped + 1] = {
               slot = s, id = id, reasonKey = reason,
               [1] = s, [2] = id, [3] = reason,
            }
         else
            applied[#applied + 1] = s
            map[s] = id
         end
      end
   end
   return applied, skipped, map
end

-- Outfits.Check(name) -> applied, skipped
-- Wie Load, aber ohne etwas zu setzen (z. B. fuer Verfuegbarkeits-Anzeigen).
function Outfits.Check(name)
   local o = Outfits.Get(name)
   if not o then return {}, {}, "OUTFIT_ERR_MISSING" end
   local applied, skipped = Evaluate(o)
   return applied, skipped
end

-- Outfits.Load(name) -> applied, skipped
-- Setzt die uebernehmbaren Teile des Outfits als Auswahl (ein State.SetMany).
-- applied: Array der Slots; skipped: Array { slot=, id=, reasonKey= } (auch
-- positionell [1..3]). Unbekanntes Outfit: {}, {}, "OUTFIT_ERR_MISSING".
function Outfits.Load(name)
   local o = Outfits.Get(name)
   if not o then return {}, {}, "OUTFIT_ERR_MISSING" end

   local applied, skipped, map = Evaluate(o)
   local State = T.State
   if next(map) ~= nil and type(State) == "table" and type(State.SetMany) == "function" then
      State.SetMany(map)
   end
   return applied, skipped
end

-- ---------------------------------------------------------------------------
-- Item-Daten vorladen
-- ---------------------------------------------------------------------------

-- Outfits.RequestItems(name) -- fordert die Item-Daten eines Outfits (nil: aller
-- Outfits) bei Items an, damit Icons/Namen in der Liste rasch erscheinen.
function Outfits.RequestItems(name)
   local Items = T.Items
   if type(Items) ~= "table" or type(Items.RequestMany) ~= "function" then return end
   local ids, seen = {}, {}
   local function add(o)
      local clean = CleanSlots(o.slots)
      for i = 1, #SERVER_SLOTS do
         local id = clean[SERVER_SLOTS[i]]
         if id and id ~= HiddenId() and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
         end
      end
   end
   if name ~= nil then
      local o = Outfits.Get(name)
      if o then add(o) end
   else
      local list = Store()
      for i = 1, #list do
         if type(list[i]) == "table" then add(list[i]) end
      end
   end
   if #ids > 0 then Items.RequestMany(ids) end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

-- Outfits.Init() -- bringt gespeicherte Outfits in Form (idempotent):
-- Array ohne Luecken, bereinigte Namen (eindeutig, ohne Beachtung der
-- Schreibweise), nur gueltige Slots/Item-IDs. Es werden keine Outfits geloescht.
function Outfits.Init()
   local list = Store()

   -- Eintraege in Reihenfolge der ganzzahligen Schluessel einsammeln
   local keys = {}
   for k, v in pairs(list) do
      if type(k) == "number" and k >= 1 and type(v) == "table" then
         keys[#keys + 1] = k
      end
   end
   sort(keys)

   local items, used = {}, {}
   for i = 1, #keys do
      local o = list[keys[i]]
      local name = TruncateChars(Outfits.NormalizeName(o.name), Outfits.MAX_NAME)
      if name == "" then name = TruncateChars(DefaultName(i), Outfits.MAX_NAME) end
      local base, n = name, 1
      while used[Lower(name)] do
         n = n + 1
         local suffix = " (" .. n .. ")"
         name = TruncateChars(base, Outfits.MAX_NAME - #suffix) .. suffix
      end
      used[Lower(name)] = true

      local slots, count = CleanSlots(o.slots)
      local when = tonumber(o.time)
      items[#items + 1] = {
         name = name, slots = slots, count = count,
         time = (when and when >= 0) and when or 0,
      }
   end

   -- Erst jetzt in-place ersetzen (die Tabellenreferenz in DB.char bleibt)
   for k in pairs(list) do list[k] = nil end
   for i = 1, #items do list[i] = items[i] end
end
