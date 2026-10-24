-- Core\Filter.lua
-- ---------------------------------------------------------------------------
-- Filter, Suche, Sortierung, Duplikat-Erkennung und Seitenaufteilung der
-- Aussehen-Listen. Reine Logik, keine Frames: Grid und FilterBar lesen
-- ausschliesslich hier und in T.State.
--
-- Aufbau:
--   * Der Filterzustand liegt dauerhaft in DB.char.filter (Filter.state), der
--     Suchtext nur fluechtig in Filter.search.
--   * Compute(slot) liefert die sichtbaren, sortierten Eintraege. Das Ergebnis
--     wird je Slot gecacht (Version aus den Bus-Ereignissen + Signatur aus
--     Filter-, Listen- und Auswahlzustand).
--   * Types()/Qualities() liefern die Facetten (Typen, Qualitaeten) fuer die
--     Filterleiste.
--
-- Wichtig fuer die Korrektheit:
--   * Die Sortierung ist eine strenge schwache Ordnung (letzter Tiebreaker ist
--     die Item-ID, IDs sind eindeutig), table.sort wirft also nie
--     "invalid order function".
--   * Es werden nur AUFGELOESTE Items geliefert. Unbekannte IDs werden ueber
--     Items.RequestMany angefordert und in stats.unresolved gezaehlt.
-- ---------------------------------------------------------------------------

local T = Transmog

local Filter = {}
T.Filter = Filter

local type, tonumber, tostring, pairs = type, tonumber, tostring, pairs
local getmetatable, setmetatable, rawset = getmetatable, setmetatable, rawset
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local sort, concat = table.sort, table.concat
local find, sub, match, gmatch = string.find, string.sub, string.match, string.gmatch
local strlow, strup = string.lower, string.upper

-- ---------------------------------------------------------------------------
-- Konstanten
-- ---------------------------------------------------------------------------

-- Gueltige Sortierschluessel in Menue-Reihenfolge
Filter.SORTS = { "QUALITY", "NAME", "ILEVEL" }
local VALID_SORT = { QUALITY = true, NAME = true, ILEVEL = true }

local Q_MAX = 7   -- hoechste Qualitaet (Heirloom)
local QUALITY_FALLBACK = {
   [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare",
   [4] = "Epic", [5] = "Legendary", [6] = "Artifact", [7] = "Heirloom",
}

local ARMOR_ORDER_FALLBACK = { 404, 403, 402, 401 }

local EMPTY = {}   -- gemeinsamer Nur-Lesen-Platzhalter, wird nie beschrieben

-- Sekunden zwischen erneuten Anforderungen unbekannter Items bei Cache-Treffern
local REQUEST_RETRY = 5

-- Mindestabstand (Sekunden) der Selbstheilungs-Pruefung "ist inzwischen eines
-- der unbekannten Items aufgeloest?" (je Cache-Eintrag); die Pruefung fragt
-- jede unbekannte ID einzeln ab und soll nicht bei jedem Compute laufen.
local HEAL_INTERVAL = 0.25

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------------

-- Zahl oder 0 (nil/NaN/Fremdtyp -> 0)
local function Num(v)
   if type(v) == "number" and v == v then return v end
   return 0
end

-- Gueltiger Server-Slot (ganze Zahl 0..18)? Haelt NaN, Bruchzahlen und
-- Fremdwerte aus den Cache-Tabellen heraus ("table index is NaN").
local function ValidSlot(slot)
   return type(slot) == "number" and slot >= 0 and slot <= 18 and slot == floor(slot)
end

-- Anzahl Eintraege einer Tabelle
local function CountKeys(t)
   local n = 0
   for _ in pairs(t) do n = n + 1 end
   return n
end

-- Feuert ein Bus-Ereignis, falls der Bus existiert
local function Fire(name, ...)
   local ev = T.Events
   if type(ev) == "table" and type(ev.Fire) == "function" then
      ev.Fire(name, ...)
   end
end

-- Aktuelle Zeit (GetTime), 0 ausserhalb des Spiels
local function Now()
   if type(GetTime) == "function" then return GetTime() end
   return 0
end

-- Meldet unbekannte Item-IDs bei Items an (Kopie: Items darf die Liste
-- verbrauchen; Items drosselt und ist idempotent)
local function RequestIds(ids)
   local Items = T.Items
   if type(Items) ~= "table" then return end
   local copy = {}
   for i = 1, #ids do copy[i] = ids[i] end
   if type(Items.RequestMany) == "function" then
      Items.RequestMany(copy)
   elseif type(Items.Request) == "function" then
      for i = 1, #copy do Items.Request(copy[i]) end
   end
end

-- true, sobald mindestens eine der (zuvor unbekannten) IDs aufgeloest ist.
-- Macht gecachte Ergebnisse selbstheilend, auch wenn ein ITEMS_RESOLVED fehlt.
local function AnyResolved(ids)
   local Items = T.Items
   if type(Items) ~= "table" or type(Items.Info) ~= "function" then return false end
   local Info = Items.Info
   for i = 1, #ids do
      if Info(ids[i]) ~= nil then return true end
   end
   return false
end

-- true, wenn der Cache-Eintrag `hit` unbekannte Items vormerkt und eines davon
-- inzwischen aufgeloest ist. Hoechstens alle HEAL_INTERVAL Sekunden geprueft
-- (hit.checkedAt), sonst false.
local function ResolvedSince(hit)
   local ids = hit.unresolvedIds
   if ids == nil then return false end
   local now = Now()
   if now - (hit.checkedAt or 0) < HEAL_INTERVAL then return false end
   hit.checkedAt = now
   return AnyResolved(ids)
end

-- Ruft State.<name>(slot), falls vorhanden; sonst nil (State darf unvollstaendig
-- oder noch nicht geladen sein)
local function StateGet(State, name, slot)
   local fn = State[name]
   if type(fn) == "function" then return fn(slot) end
   return nil
end

-- ---------------------------------------------------------------------------
-- Filterzustand (DB.char.filter) und Suchtext
-- ---------------------------------------------------------------------------

-- Notfall-Zustand, solange DB.char noch nicht existiert
local fallbackState = {
   qualities = {}, typesOff = {}, hideDuplicates = true,
   sort = "QUALITY", favoritesOnly = false, newOnly = false,
}

Filter.search = ""   -- Suchtext (roh, wie getippt), nicht persistent

-- Komfort: Filter.state.search liest/schreibt den fluechtigen Suchtext, ohne
-- ihn in die gespeicherte Tabelle zu legen (die Schluessel bleiben leer)
local stateMeta = {
   __index = function(_, key)
      if key == "search" then return Filter.search end
      return nil
   end,
   __newindex = function(t, key, value)
      if key == "search" then
         Filter.SetSearch(value)
      else
         rawset(t, key, value)
      end
   end,
}

-- Liefert den (lebenden) Filterzustand; ergaenzt fehlende Untertabellen
local function GetState()
   local db = T.DB
   local char = type(db) == "table" and db.char or nil
   local f = type(char) == "table" and char.filter or nil
   if type(f) ~= "table" then
      f = fallbackState
   end
   if type(f.qualities) ~= "table" then f.qualities = {} end
   if type(f.typesOff) ~= "table" then f.typesOff = {} end
   if getmetatable(f) == nil then setmetatable(f, stateMeta) end
   return f
end

-- Filter.state ist immer die aktuelle Referenz auf DB.char.filter (die
-- Tabelle entsteht erst in DB.Init, also nicht beim Dateiladen)
setmetatable(Filter, {
   __index = function(_, key)
      if key == "state" then return GetState() end
      return nil
   end,
})

-- Zerlegter Suchtext. tokens[i] = { text=, num=|nil, idOnly=bool }
--   num    Item-ID, wenn der Begriff "#123" oder eine reine Zahl ist
--   idOnly nur "#123": trifft ausschliesslich die Item-ID, nie Name/Typ
local tokenSource = nil   -- Suchtext, aus dem tokens gebaut wurden
local tokens = {}
local searchKey = ""      -- normalisierte Form (Begriffe durch " " getrennt)

-- Baut tokens/searchKey neu, falls sich Filter.search geaendert hat
local function RebuildTokens()
   local src = Filter.search
   if type(src) ~= "string" then src = "" end
   if src == tokenSource then return end
   tokenSource = src
   local list, keys = {}, {}
   local Util = T.Util
   local low = Util.Lower(Util.Trim(src))
   for word in gmatch(low, "%S+") do
      local tok = nil
      local digits = match(word, "^#(%d+)$")
      if digits then
         -- "#123": nur die Item-ID (ganze ID, kein Praefix)
         tok = { text = word, num = tonumber(digits), idOnly = true }
      elseif word == "#" then
         tok = nil   -- einzelnes "#" waehrend des Tippens: ignorieren
      elseif match(word, "^%d+$") then
         -- reine Zahl: Item-ID ODER Namens-/Typ-Teilstring
         tok = { text = word, num = tonumber(word), idOnly = false }
      else
         tok = { text = word, idOnly = false }
      end
      if tok then
         list[#list + 1] = tok
         keys[#keys + 1] = tok.text
      end
   end
   tokens = list
   searchKey = concat(keys, " ")
end

-- ---------------------------------------------------------------------------
-- Abgeleitete Daten je Item (Kleinschreibung, Duplikat-Schluessel)
-- ---------------------------------------------------------------------------
-- Itemdaten aendern sich in einer Sitzung nicht; die Ableitungen (Util.Lower
-- ist teuer) werden je Item-ID einmal berechnet und an die Info-Tabelle
-- gebunden (anderes info => neu).

local derived = {}   -- [id] = { info=, nameKey=, typeLow=, dupKey=, dupTk= }
local derivedCount = 0

-- Obergrenze der Ableitungs-Tabelle (Eintraege). Wird sie ueberschritten, wirft
-- Compute die Tabelle vor der naechsten Berechnung weg; sie baut sich lazy neu
-- auf. So waechst der Speicher nie unbegrenzt (Lesezugriff je Compute, damit
-- Tests einen kleinen Wert setzen koennen).
Filter.DERIVED_LIMIT = 20000

-- Liefert den Ableitungs-Datensatz zu (id, info)
local function Derived(id, info)
   local d = derived[id]
   if d == nil then
      derivedCount = derivedCount + 1
      d = { info = info }
      derived[id] = d
   elseif d.info ~= info then
      d = { info = info }
      derived[id] = d
   end
   return d
end

-- Kleingeschriebener Name (fuer Suche und Namenssortierung)
local function NameKey(d)
   local k = d.nameKey
   if k == nil then
      local n = d.info.name
      if type(n) == "string" and n ~= "" then
         k = T.Util.Lower(n)
      else
         k = ""
      end
      d.nameKey = k
   end
   return k
end

-- Kleingeschriebener "Typ Untertyp" (fuer die Suche)
local function TypeLow(d)
   local k = d.typeLow
   if k == nil then
      local info = d.info
      local a, b = info.typeName, info.subtypeName
      if type(a) ~= "string" then a = "" end
      if type(b) ~= "string" then b = "" end
      k = T.Util.Lower(a .. " " .. b)
      d.typeLow = k
   end
   return k
end

-- Duplikat-Schluessel: Icon | Typ (typeKey, sonst Untertypname) | Ausruestungsplatz.
-- Das 3.3.5a-Client-API kennt keine DisplayInfo-ID; das Inventar-Icon stammt
-- aus derselben DisplayInfo-Zeile wie das Modell, gleiches Aussehen => gleiches
-- Icon. Ohne Icon (oder mit dem Platzhalter-Fragezeichen, den Items fuer
-- fehlende Texturen einsetzt) ist der Gegenstand einzigartig: ein Platzhalter
-- darf nie verschiedene Aussehen zusammenfassen.
-- Der typeKey kann sich nachtraeglich aendern (Items stuft bei spaet
-- verfuegbaren AH-Listen neu ein); der Schluessel wird dann neu gebildet.
local PLACEHOLDER_ICON = "interface\\icons\\inv_misc_questionmark"

local function DupKey(d, id)
   local info = d.info
   local tk = info.typeKey
   local k = d.dupKey
   if k ~= nil and d.dupTk == tk then return k end
   local icon = info.icon
   if type(icon) ~= "string" or icon == "" then
      k = "id:" .. id
   else
      icon = strlow(icon)
      if icon == PLACEHOLDER_ICON then
         k = "id:" .. id
      else
         local sk = tk
         if sk == nil then sk = info.subtypeName end
         if sk == nil then sk = "" end
         local el = info.equipLoc
         if el == nil then el = "" end
         k = icon .. "|" .. tostring(sk) .. "|" .. tostring(el)
      end
   end
   d.dupKey = k
   d.dupTk = tk
   return k
end

-- ---------------------------------------------------------------------------
-- Cache und Ereignisse
-- ---------------------------------------------------------------------------

local viewVersion = 0   -- wird bei jeder relevanten Aenderung erhoeht
local dataVersion = 0   -- nur bei Listen-/Item-/Ausruestungsaenderung
local cache = {}        -- [slot] = { version, sig, entries, stats }
local facetCache = {}   -- [slot] = { version, sig, types, qualities }

local function InvalidateView()
   viewVersion = viewVersion + 1
end

local function InvalidateData()
   viewVersion = viewVersion + 1
   dataVersion = dataVersion + 1
end

local hooked = false

-- Meldet die Cache-Invalidierung am Bus an (einmalig, idempotent)
local function HookEvents()
   if hooked then return end
   local ev = T.Events
   if type(ev) ~= "table" or type(ev.On) ~= "function" then return end
   hooked = true
   ev.On("FILTER_CHANGED", InvalidateView, Filter)
   ev.On("FAVORITES_CHANGED", InvalidateView, Filter)
   ev.On("WANTED_CHANGED", InvalidateView, Filter)
   ev.On("STATUS_CHANGED", InvalidateView, Filter)
   ev.On("COLLECTION_UPDATED", InvalidateView, Filter)
   ev.On("LIST_READY", InvalidateData, Filter)
   ev.On("ITEMS_RESOLVED", InvalidateData, Filter)
   ev.On("EQUIPMENT_CHANGED", InvalidateData, Filter)
   ev.On("LOCALE_CHANGED", InvalidateData, Filter)
end

-- Filter.Init() -- haengt den Cache an den Ereignisbus (wird auch lazy erledigt)
function Filter.Init()
   HookEvents()
end

-- Filter.Invalidate() -- verwirft alle gecachten Ergebnisse
function Filter.Invalidate()
   InvalidateData()
end

-- Filter.CacheSize() -> Anzahl der abgeleiteten Itemdatensaetze (Diagnose/Tests)
function Filter.CacheSize()
   return derivedCount
end

HookEvents()

-- ---------------------------------------------------------------------------
-- Signatur
-- ---------------------------------------------------------------------------

-- Sortierte, kommagetrennte Liste der ausgeblendeten Typen ("" wenn keine)
local function TypesOffSignature(typesOff)
   local keys, n = nil, 0
   for k, v in pairs(typesOff) do
      if v and type(k) == "number" then
         if keys == nil then keys = {} end
         n = n + 1
         keys[n] = k
      end
   end
   if n == 0 then return "" end
   sort(keys)
   return concat(keys, ",")
end

-- Aktiver, gueltiger Sortierschluessel
local function SortKeyOf(f)
   local s = f.sort
   if type(s) == "string" and VALID_SORT[s] then return s end
   return "QUALITY"
end

-- ---------------------------------------------------------------------------
-- Vergleichsfunktionen (strenge schwache Ordnung, Tiebreaker = id)
-- ---------------------------------------------------------------------------

-- Qualitaet absteigend, Name aufsteigend, id aufsteigend
local function CmpQuality(a, b)
   local qa, qb = a.quality, b.quality
   if qa ~= qb then return qa > qb end
   local na, nb = a.nameKey, b.nameKey
   if na ~= nb then return na < nb end
   return a.id < b.id
end

-- Name aufsteigend, id aufsteigend
local function CmpName(a, b)
   local na, nb = a.nameKey, b.nameKey
   if na ~= nb then return na < nb end
   return a.id < b.id
end

-- Itemlevel absteigend, Qualitaet absteigend, Name aufsteigend, id aufsteigend
local function CmpILevel(a, b)
   local la, lb = a.ilvl, b.ilvl
   if la ~= lb then return la > lb end
   local qa, qb = a.quality, b.quality
   if qa ~= qb then return qa > qb end
   local na, nb = a.nameKey, b.nameKey
   if na ~= nb then return na < nb end
   return a.id < b.id
end

local COMPARATORS = { QUALITY = CmpQuality, NAME = CmpName, ILEVEL = CmpILevel }

-- Besser als Duplikat-Repraesentant: wanted > applied > favorite > Qualitaet
-- (hoeher) > niedrigere id. Alle Flags sind echte Booleans.
local function IsBetter(a, b)
   if a.wanted ~= b.wanted then return a.wanted end
   if a.applied ~= b.applied then return a.applied end
   if a.favorite ~= b.favorite then return a.favorite end
   if a.quality ~= b.quality then return a.quality > b.quality end
   return a.id < b.id
end

-- ---------------------------------------------------------------------------
-- Compute
-- ---------------------------------------------------------------------------

-- Leere Statistik
local function NewStats(total)
   return {
      total = total, shown = 0, unresolved = 0, hiddenByFilter = 0,
      hiddenDuplicates = 0, resolved = 0, ready = false, version = 0,
   }
end

-- Prueft alle Suchbegriffe gegen ein Item; true wenn ALLE passen
local function MatchesSearch(toks, nTok, d, id)
   for i = 1, nTok do
      local tok = toks[i]
      local hit = false
      if not tok.idOnly then
         hit = find(NameKey(d), tok.text, 1, true) ~= nil
            or find(TypeLow(d), tok.text, 1, true) ~= nil
      end
      if not hit and tok.num then
         hit = (tok.num == id)
      end
      if not hit then return false end
   end
   return true
end

-- Erster Durchlauf: Aufloesung, Qualitaet/Typ/Favorit/Neu/Suche.
-- Rueckgabe: entries, nEntries, unresolved, unresolvedIds, hiddenByFilter
local function Collect(c)
   local Info = T.Items.Info
   local ids = c.list.ids
   if type(ids) ~= "table" then ids = EMPTY end
   local qualOff, typesOff = c.f.qualities, c.f.typesOff
   local ownType = c.ownType
   local favorites, newSet = c.favorites, c.newSet
   local favOnly, newOnly = c.favOnly, c.newOnly
   local wantedId, baseId, rawId = c.wantedId, c.baseId, c.rawId
   local toks, nTok = c.tokens, #c.tokens
   local entries, n = {}, 0
   local unresolved, unresolvedIds = 0, nil
   local hidden = 0
   local seen = {}
   local hiddenId = T.HIDDEN_ID or 999999

   for i = 1, #ids do
      local id = tonumber(ids[i])
      if id and id > 0 and id ~= hiddenId and not seen[id] then
         seen[id] = true
         local info = Info(id)
         if type(info) ~= "table" then
            unresolved = unresolved + 1
            if unresolvedIds == nil then unresolvedIds = {} end
            unresolvedIds[unresolved] = id
         else
            local q = info.quality
            if type(q) ~= "number" then q = 1 end
            local fav = favorites[id] and true or false
            local isNew = newSet[id] and true or false
            local show = true

            if qualOff[q] == false then
               show = false
            else
               local tk = info.typeKey
               if tk ~= nil and typesOff[tk] and tk ~= ownType then
                  show = false
               elseif favOnly and not fav then
                  show = false
               elseif newOnly and not isNew then
                  show = false
               end
            end

            local d = nil
            if show then
               d = Derived(id, info)
               if nTok > 0 and not MatchesSearch(toks, nTok, d, id) then
                  show = false
               end
            end

            if show then
               n = n + 1
               entries[n] = {
                  id = id,
                  info = info,
                  favorite = fav,
                  isNew = isNew,
                  applied = (id == baseId) or (id == rawId),
                  wanted = (id == wantedId),
                  quality = q,
                  ilvl = Num(info.ilvl),
                  nameKey = NameKey(d),
               }
            else
               hidden = hidden + 1
            end
         end
      end
   end
   return entries, n, unresolved, unresolvedIds, hidden
end

-- Zweiter Durchlauf: je Duplikat-Gruppe bleibt nur der Repraesentant.
-- Rueckgabe: entries, nEntries (Reihenfolge bleibt erhalten)
local function Collapse(entries, n)
   if n < 2 then return entries, n end
   local rep, keys = {}, {}
   for i = 1, n do
      local e = entries[i]
      local key = DupKey(derived[e.id], e.id)
      keys[i] = key
      local cur = rep[key]
      if cur == nil or IsBetter(e, cur) then rep[key] = e end
   end
   local out, m = {}, 0
   for i = 1, n do
      local e = entries[i]
      if rep[keys[i]] == e then
         m = m + 1
         out[m] = e
      end
   end
   return out, m
end

local computeCounter = 0   -- zaehlt tatsaechliche Neuberechnungen (stats.version)

-- Gibt dem Aufrufer eigene Kopien des gecachten Ergebnisses: ein neues Array
-- (gleiche Eintrags-Tabellen) und eine neue stats-Tabelle. So kann die
-- Oberflaeche das Array veraendern (z. B. synthetische Kacheln einfuegen),
-- ohne den Cache zu beschaedigen.
local function Deliver(hit)
   local src, out = hit.entries, {}
   for i = 1, hit.count do out[i] = src[i] end
   local stats = {}
   for k, v in pairs(hit.stats) do stats[k] = v end
   return out, stats
end

-- Filter.Compute(slot) -> entries, stats
-- entries: Array { id, info, favorite, isNew, applied, wanted, quality, ilvl, nameKey }
--   (nur aufgeloeste Items, sortiert gemaess Filter.state.sort). Das Array und
--   stats sind Kopien (frei veraenderbar); die Eintrags-Tabellen darin sind
--   gecacht und geteilt: Felder nicht veraendern.
-- stats: { total, shown, unresolved, hiddenByFilter, hiddenDuplicates,
--          resolved, ready, version }; version steigt bei jeder echten
--          Neuberechnung (gleiche version = gleiches Ergebnis).
function Filter.Compute(slot)
   HookEvents()
   local State, Items = T.State, T.Items
   if not ValidSlot(slot) or type(State) ~= "table" or type(Items) ~= "table"
      or type(State.List) ~= "function" or type(Items.Info) ~= "function" then
      return {}, NewStats(0)
   end

   local f = GetState()
   RebuildTokens()

   local list = State.List(slot)
   if type(list) ~= "table" then list = EMPTY end
   local ids = list.ids
   local nIds = type(ids) == "table" and #ids or 0

   local eq = StateGet(State, "Equipped", slot)
   local ownType = nil
   if type(eq) == "table" then ownType = eq.typeKey end

   local db = T.DB
   local char = type(db) == "table" and db.char or nil
   local favorites = type(char) == "table" and char.favorites or nil
   if type(favorites) ~= "table" then favorites = EMPTY end
   local newSet = State.new
   if type(newSet) ~= "table" then newSet = EMPTY end

   local wantedId = Num(StateGet(State, "Wanted", slot))
   local baseId = Num(StateGet(State, "Baseline", slot))
   local rawId = Num(StateGet(State, "Applied", slot))

   local sortKey = SortKeyOf(f)
   local hideDup = f.hideDuplicates ~= false
   local favOnly = f.favoritesOnly and true or false
   local newOnly = f.newOnly and true or false

   local qmask = 0
   local qo = f.qualities
   for q = 0, Q_MAX do
      if qo[q] == false then qmask = qmask + 2 ^ q end
   end

   -- Signatur: alles, was das Ergebnis bestimmt (einmal je Aufruf gebaut)
   local sig = searchKey .. "\1" .. sortKey .. "\1"
      .. (hideDup and "d" or "-") .. (favOnly and "f" or "-") .. (newOnly and "n" or "-")
      .. "\1" .. qmask .. "\1" .. TypesOffSignature(f.typesOff)
      .. "\1" .. nIds .. ":" .. Num(list.received) .. ":" .. (list.ready and 1 or 0)
      .. ":" .. Num(list.version)
      .. "\1" .. Num(ownType) .. ":" .. wantedId .. ":" .. baseId .. ":" .. rawId
      .. "\1" .. CountKeys(favorites) .. ":" .. CountKeys(newSet)

   local version = viewVersion
   local hit = cache[slot]
   if hit and hit.version == version and hit.sig == sig then
      if hit.unresolvedIds == nil then
         return Deliver(hit)
      end
      -- Ist inzwischen eines der unbekannten Items aufgeloest, ist das
      -- Ergebnis veraltet (faellt durch zur Neuberechnung). Sonst werden die
      -- Items, die Items aufgegeben hat, gelegentlich erneut angemeldet.
      if not ResolvedSince(hit) then
         if Now() - hit.requestedAt >= REQUEST_RETRY then
            hit.requestedAt = Now()
            RequestIds(hit.unresolvedIds)
         end
         return Deliver(hit)
      end
   end

   -- Ableitungen begrenzen (nie mitten in einer Berechnung: Collapse liest sie)
   local limit = tonumber(Filter.DERIVED_LIMIT) or 20000
   if derivedCount > limit then
      derived, derivedCount = {}, 0
   end

   local ctx = {
      f = f, list = list, ownType = ownType, favorites = favorites, newSet = newSet,
      favOnly = favOnly, newOnly = newOnly, wantedId = wantedId, baseId = baseId,
      rawId = rawId, tokens = tokens,
   }
   local entries, n, unresolved, unresolvedIds, hidden = Collect(ctx)
   local resolved = n + hidden   -- vor dem Zusammenfassen von Duplikaten

   local hiddenDup = 0
   if hideDup then
      local before = n
      entries, n = Collapse(entries, n)
      hiddenDup = before - n
   end
   if n > 1 then
      sort(entries, COMPARATORS[sortKey])
   end

   computeCounter = computeCounter + 1
   local stats = {
      total = nIds,
      shown = n,
      unresolved = unresolved,
      hiddenByFilter = hidden,
      hiddenDuplicates = hiddenDup,
      resolved = resolved,
      ready = list.ready == true,
      version = computeCounter,
   }

   local now = Now()
   local fresh = {
      version = version, sig = sig, entries = entries, count = n, stats = stats,
      unresolvedIds = unresolvedIds, requestedAt = now, checkedAt = now,
   }
   cache[slot] = fresh

   -- Unbekannte Items zur Aufloesung anmelden (gedrosselt/idempotent in Items)
   if unresolvedIds then
      RequestIds(unresolvedIds)
   end

   return Deliver(fresh)
end

-- ---------------------------------------------------------------------------
-- Facetten: Typen und Qualitaeten des Slots (ungefiltert gezaehlt)
-- ---------------------------------------------------------------------------

local armorRank = {}   -- typeKey -> Rang (Platte zuerst), je Aufruf gesetzt

-- Reihenfolge der Typen: Ruestungsstufen Platte->Stoff, danach nach typeKey
local function TypeBefore(a, b)
   local ra = armorRank[a.typeKey] or (1000 + a.typeKey)
   local rb = armorRank[b.typeKey] or (1000 + b.typeKey)
   return ra < rb
end

-- Anzeigename eines Typs (Items.TypeLabel, sonst Untertypname, sonst Zahl)
local function TypeLabelOf(typeKey, fallback)
   local Items = T.Items
   local label = nil
   if type(Items) == "table" and type(Items.TypeLabel) == "function" then
      label = Items.TypeLabel(typeKey)
   end
   if type(label) ~= "string" or label == "" then
      if type(fallback) == "string" and fallback ~= "" then
         label = fallback
      else
         label = tostring(typeKey)
      end
   end
   return label
end

-- Baut die Facetten eines Slots. Rueckgabe: types, qualities, unresolvedIds|nil
local function BuildFacets(list, ownType)
   local Items = T.Items
   local Info = Items.Info
   local ids = list.ids
   if type(ids) ~= "table" then ids = EMPTY end
   local qCount, tCount, tFallback, seen = {}, {}, {}, {}
   local unresolvedIds, nUnres = nil, 0
   local hiddenId = T.HIDDEN_ID or 999999

   for i = 1, #ids do
      local id = tonumber(ids[i])
      if id and id > 0 and id ~= hiddenId and not seen[id] then
         seen[id] = true
         local info = Info(id)
         if type(info) ~= "table" then
            if unresolvedIds == nil then unresolvedIds = {} end
            nUnres = nUnres + 1
            unresolvedIds[nUnres] = id
         else
            local q = info.quality
            if type(q) ~= "number" then q = 1 end
            qCount[q] = (qCount[q] or 0) + 1
            local tk = info.typeKey
            if tk ~= nil then
               tCount[tk] = (tCount[tk] or 0) + 1
               if tFallback[tk] == nil then
                  tFallback[tk] = info.subtypeName or info.typeName
               end
            end
         end
      end
   end

   -- Typen
   local types = {}
   for tk, count in pairs(tCount) do
      types[#types + 1] = {
         typeKey = tk, label = TypeLabelOf(tk, tFallback[tk]),
         count = count, own = (tk == ownType),
      }
   end
   local order = Items.ARMOR_ORDER
   if type(order) ~= "table" then order = ARMOR_ORDER_FALLBACK end
   for k in pairs(armorRank) do armorRank[k] = nil end
   for i = 1, #order do armorRank[order[i]] = i end
   if #types > 1 then sort(types, TypeBefore) end

   -- Qualitaeten aufsteigend
   local qualities = {}
   local qkeys = {}
   for q in pairs(qCount) do qkeys[#qkeys + 1] = q end
   sort(qkeys)
   for i = 1, #qkeys do
      qualities[i] = { quality = qkeys[i], count = qCount[qkeys[i]] }
   end
   return types, qualities, unresolvedIds
end

-- Flache Kopie eines Arrays (die Eintraege darin bleiben geteilt)
local function CopyArray(src)
   local out = {}
   for i = 1, #src do out[i] = src[i] end
   return out
end

-- Liefert (gecacht) die Facetten des Slots: types, qualities (interne Tabellen)
local function GetFacets(slot)
   HookEvents()
   local State, Items = T.State, T.Items
   if not ValidSlot(slot) or type(State) ~= "table" or type(Items) ~= "table"
      or type(State.List) ~= "function" or type(Items.Info) ~= "function" then
      return EMPTY, EMPTY
   end
   local list = State.List(slot)
   if type(list) ~= "table" then list = EMPTY end
   local ids = list.ids
   local nIds = type(ids) == "table" and #ids or 0
   local eq = StateGet(State, "Equipped", slot)
   local ownType = nil
   if type(eq) == "table" then ownType = eq.typeKey end

   local sig = nIds .. ":" .. Num(list.received) .. ":" .. (list.ready and 1 or 0)
      .. ":" .. Num(list.version) .. ":" .. Num(ownType)
   local version = dataVersion
   local hit = facetCache[slot]
   if hit and hit.version == version and hit.sig == sig and not ResolvedSince(hit) then
      return hit.types, hit.qualities
   end
   local types, qualities, unresolvedIds = BuildFacets(list, ownType)
   facetCache[slot] = {
      version = version, sig = sig, types = types, qualities = qualities,
      unresolvedIds = unresolvedIds, checkedAt = Now(),
   }
   return types, qualities
end

-- Filter.Types(slot) -> Array { typeKey, label, count, own }
-- Typen, die in der Liste des Slots vorkommen (aufgeloeste Items); own = Typ des
-- angelegten Gegenstands (nicht ausblendbar). Neues Array je Aufruf; die
-- Eintraege darin sind geteilt (nicht veraendern).
function Filter.Types(slot)
   local types = GetFacets(slot)
   return CopyArray(types)
end

-- Filter.Qualities(slot) -> Array { quality, count } (aufsteigend, ungefiltert)
-- Neues Array je Aufruf; die Eintraege darin sind geteilt (nicht veraendern).
function Filter.Qualities(slot)
   local _, qualities = GetFacets(slot)
   return CopyArray(qualities)
end

-- ---------------------------------------------------------------------------
-- Zustandsaenderungen
-- ---------------------------------------------------------------------------

-- Filter.SetSearch(text) -- Suchtext setzen; feuert FILTER_CHANGED bei Aenderung
function Filter.SetSearch(text)
   if type(text) ~= "string" then text = "" end
   RebuildTokens()
   local old = searchKey
   Filter.search = text
   RebuildTokens()
   if searchKey ~= old then
      Fire("FILTER_CHANGED")
   end
end

-- Filter.SetQuality(q, visible) -- Qualitaet 0..7 ein-/ausblenden
function Filter.SetQuality(q, visible)
   q = tonumber(q)
   if not q then return end
   q = floor(q)
   if q < 0 or q > Q_MAX then return end
   local f = GetState()
   local wasHidden = f.qualities[q] == false
   local hide = not visible
   if hide == wasHidden then return end
   if hide then
      f.qualities[q] = false
   else
      f.qualities[q] = nil
   end
   Fire("FILTER_CHANGED")
end

-- Filter.SetType(typeKey, visible) -- Typ ein-/ausblenden (own-Typ bleibt sichtbar)
function Filter.SetType(typeKey, visible)
   typeKey = tonumber(typeKey)
   if not typeKey then return end
   local f = GetState()
   local wasHidden = f.typesOff[typeKey] == true
   local hide = not visible
   if hide == wasHidden then return end
   if hide then
      f.typesOff[typeKey] = true
   else
      f.typesOff[typeKey] = nil
   end
   Fire("FILTER_CHANGED")
end

-- Filter.SetSort(key) -- "QUALITY" | "NAME" | "ILEVEL" (Gross-/Kleinschreibung egal)
function Filter.SetSort(key)
   if type(key) ~= "string" then return end
   key = strup(key)
   if not VALID_SORT[key] then return end
   local f = GetState()
   if f.sort == key then return end
   f.sort = key
   Fire("FILTER_CHANGED")
end

-- Filter.SetHideDuplicates(b) -- Duplikate ausblenden
function Filter.SetHideDuplicates(b)
   local f = GetState()
   local v = b and true or false
   if (f.hideDuplicates ~= false) == v then return end
   f.hideDuplicates = v
   Fire("FILTER_CHANGED")
end

-- Filter.SetFavoritesOnly(b) -- nur Favoriten
function Filter.SetFavoritesOnly(b)
   local f = GetState()
   local v = b and true or false
   if (f.favoritesOnly and true or false) == v then return end
   f.favoritesOnly = v
   Fire("FILTER_CHANGED")
end

-- Filter.SetNewOnly(b) -- nur neue Aussehen
function Filter.SetNewOnly(b)
   local f = GetState()
   local v = b and true or false
   if (f.newOnly and true or false) == v then return end
   f.newOnly = v
   Fire("FILTER_CHANGED")
end

-- Filter.IsActive() -> bool
-- true, wenn Suche, Qualitaet, Typen, Favoriten oder Neu vom Standard abweichen
function Filter.IsActive()
   local f = GetState()
   RebuildTokens()
   if searchKey ~= "" then return true end
   if f.favoritesOnly or f.newOnly then return true end
   for _, v in pairs(f.qualities) do
      if v == false then return true end
   end
   for _, v in pairs(f.typesOff) do
      if v then return true end
   end
   return false
end

-- Filter.Reset() -- Suche, Qualitaeten, Typen, Favoriten, Neu zuruecksetzen
-- (hideDuplicates und sort bleiben); feuert hoechstens ein FILTER_CHANGED
function Filter.Reset()
   local f = GetState()
   RebuildTokens()
   local changed = searchKey ~= ""
   Filter.search = ""
   RebuildTokens()

   for k, v in pairs(f.qualities) do
      if v == false then changed = true end
      f.qualities[k] = nil
   end
   for k, v in pairs(f.typesOff) do
      if v then changed = true end
      f.typesOff[k] = nil
   end
   if f.favoritesOnly then changed = true end
   if f.newOnly then changed = true end
   f.favoritesOnly = false
   f.newOnly = false

   if changed then
      Fire("FILTER_CHANGED")
   end
end

-- ---------------------------------------------------------------------------
-- Seiten
-- ---------------------------------------------------------------------------

-- Filter.Page(entries, page, perPage) -> pageEntries, totalPages, clampedPage
-- totalPages >= 1 (auch bei leerer Liste); page wird in [1, totalPages] geklemmt.
function Filter.Page(entries, page, perPage)
   if type(entries) ~= "table" then entries = EMPTY end
   perPage = floor(Num(tonumber(perPage)))
   if perPage < 1 then perPage = 1 end
   local total = #entries
   if perPage > total then perPage = max(1, total) end   -- (auch math.huge)
   local totalPages = max(1, ceil(total / perPage))
   page = floor(Num(tonumber(page)))
   if page < 1 then page = 1 end
   if page > totalPages then page = totalPages end

   local out, m = {}, 0
   local first = (page - 1) * perPage + 1
   local last = min(total, page * perPage)
   for i = first, last do
      m = m + 1
      out[m] = entries[i]
   end
   return out, totalPages, page
end

-- ---------------------------------------------------------------------------
-- Beschriftungen (fuer FilterBar)
-- ---------------------------------------------------------------------------

-- Filter.QualityLabel(q) -> lokalisierter Qualitaetsname (Blizzard-Global)
function Filter.QualityLabel(q)
   q = floor(Num(tonumber(q)))
   if q < 0 or q > Q_MAX then q = 1 end
   return T.Util.G("ITEM_QUALITY" .. q .. "_DESC", QUALITY_FALLBACK[q])
end

-- Filter.SortLabel(key) -> lokalisierter Name des Sortierschluessels
-- (unbekannter Schluessel: der Schluessel selbst)
function Filter.SortLabel(key)
   local L = T.L
   if key == "QUALITY" then return L.SORT_QUALITY end
   if key == "NAME" then return L.SORT_NAME end
   if key == "ILEVEL" then return L.SORT_ILEVEL end
   return tostring(key)
end
