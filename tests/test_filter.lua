-- tests/test_filter.lua
-- ---------------------------------------------------------------------------
-- Tests fuer Core\Filter.lua: Suche, Filter, Duplikate, Sortierung, Seiten,
-- Facetten, Cache und Persistenz.
--
-- Die Tests laufen gegen die ECHTEN Module (Locale, Util, Events, DB, Slots,
-- Items, Net, State) auf der WoW-Attrappe. Der Server wird ueber Net.Handle
-- im echten Protokollformat gespielt (AvailableTransmogs, TransmogStatus,
-- CollectionUpdated); Boot.lua wird nicht geladen, die Init()-Funktionen
-- werden in der Reihenfolge der SPEC (3) selbst gerufen.
--
-- Aufruf (im Hauptverzeichnis):  luajit tests/run.lua filter
-- ---------------------------------------------------------------------------

return function(H)
   local mock = H.mock
   local HIDDEN = 999999

   -- -------------------------------------------------------------------------
   -- Hilfen
   -- -------------------------------------------------------------------------

   -- Legt eine Gegenstandsdefinition (fuer mock.items) an
   local function put(defs, id, name, quality, ilvl, class, sub, loc, icon)
      defs[id] = {
         name = name, quality = quality, ilvl = ilvl, class = class, subclass = sub,
         equipLoc = loc,
         icon = icon and ("Interface\\Icons\\" .. icon) or nil,
      }
   end

   -- "2001,2003,..." aus einem Array von Eintraegen (oder Zahlen)
   local function idsOf(entries)
      local out = {}
      for i = 1, #entries do
         local e = entries[i]
         out[i] = tostring(type(e) == "table" and e.id or e)
      end
      return table.concat(out, ",")
   end

   -- Eintrag zu einer id (oder nil)
   local function entryOf(entries, id)
      for i = 1, #entries do
         if entries[i].id == id then return entries[i] end
      end
      return nil
   end

   -- Zaehler fuer Bus-Ereignisse
   local function counter(T, names)
      local c = {}
      for _, name in ipairs(names) do
         T.Events.On(name, function() c[name] = (c[name] or 0) + 1 end, c)
      end
      return c
   end

   -- Laedt das Addon bis einschliesslich Outfits.lua und initialisiert die
   -- Module wie Boot (DB -> Locale -> Slots -> Items -> Net -> State -> Outfits).
   --   spec.items   Gegenstandsdefinitionen (put)
   --   spec.equip   [Client-Slot-ID] = itemId
   --   spec.globals SavedVariables
   --   spec.cache   false: Gegenstaende NICHT in den Client-Cache legen
   local function boot(spec)
      spec = spec or {}
      local T = H.boot({
         upTo = "Core\\Outfits.lua", login = false,
         items = spec.items, world = { equipment = spec.equip or {} },
         globals = spec.globals,
      })
      T.DB.Init()
      T.Locale.Set("enUS")
      T.Slots.Init()
      T.Items.Init()
      T.Net.Init()
      T.State.Init()
      T.Outfits.Init()
      T.enteredWorldAt = GetTime() - 60   -- kein Login-Sweep mehr
      if spec.cache ~= false then mock.CacheAll() end
      T.State.RefreshEquipment()
      return T
   end

   -- Spielt einen Listenstrom des Servers (start, Chunks zu 20, end) ein
   local function feed(T, slot, list, opts)
      opts = opts or {}
      local bucket, n = opts.bucket or 0, #list
      T.Net.Handle(string.format("AvailableTransmogs:%d:%d:%d:start", slot, bucket, n))
      local i = 1
      while i <= n do
         local part = {}
         for j = i, math.min(i + 19, n) do part[#part + 1] = tostring(list[j]) end
         T.Net.Handle(string.format("AvailableTransmogs:%d:%d:%d:%s", slot, bucket, n,
            table.concat(part, ":")))
         i = i + 20
      end
      if not opts.noEnd then
         T.Net.Handle(string.format("AvailableTransmogs:%d:%d:%d:end", slot, bucket, n))
      end
   end

   -- Standard-Gegenstaende: angelegt + Brustliste (Slot 4)
   --   2001 Plate Chest Alpha  q4 il200 Plate  icon A
   --   2002 Plate Chest Beta   q3 il150 Plate  icon B
   --   2003 Mail Chest Gamma   q3 il140 Mail   icon C
   --   2004 Cloth Robe Delta   q2 il100 Cloth  icon D (ROBE)
   --   2005 Leather Epsilon    q2 il90  Leather icon E
   --   2006 Plate Chest Beta Copy q2 il80 Plate icon B (Duplikat von 2002)
   --   2007 Rag of Doom        q0 il5   Cloth  icon G
   --   2008 Strange Thing      q1 il10  kein typeKey (Verbrauchsgut) icon H
   local CHEST_LIST = { 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008 }

   local function baseItems()
      local d = {}
      put(d, 1001, "Helm of Plate", 4, 200, "Armor", "Plate", "INVTYPE_HEAD", "HeadP")
      put(d, 1004, "Chest of Plate", 4, 200, "Armor", "Plate", "INVTYPE_CHEST", "ChestP")
      put(d, 1005, "Chest of Mail", 4, 200, "Armor", "Mail", "INVTYPE_CHEST", "ChestM")
      put(d, 1015, "Sword of Doom", 4, 200, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "SwordD")
      put(d, 2001, "Plate Chest Alpha", 4, 200, "Armor", "Plate", "INVTYPE_CHEST", "A")
      put(d, 2002, "Plate Chest Beta", 3, 150, "Armor", "Plate", "INVTYPE_CHEST", "B")
      put(d, 2003, "Mail Chest Gamma", 3, 140, "Armor", "Mail", "INVTYPE_CHEST", "C")
      put(d, 2004, "Cloth Robe Delta", 2, 100, "Armor", "Cloth", "INVTYPE_ROBE", "D")
      put(d, 2005, "Leather Epsilon", 2, 90, "Armor", "Leather", "INVTYPE_CHEST", "E")
      put(d, 2006, "Plate Chest Beta Copy", 2, 80, "Armor", "Plate", "INVTYPE_CHEST", "B")
      put(d, 2007, "Rag of Doom", 0, 5, "Armor", "Cloth", "INVTYPE_CHEST", "G")
      put(d, 2008, "Strange Thing", 1, 10, "Consumable", "Other", "INVTYPE_CHEST", "H")
      return d
   end

   -- Brust angelegt (1004 Platte), Liste eingespielt
   local function chestBoot(extra, equip)
      local d = baseItems()
      if extra then extra(d) end
      local T = boot({ items = d, equip = equip or { [5] = 1004 } })
      feed(T, 4, CHEST_LIST, { bucket = 405 })
      return T
   end

   -- Zufallszahlen (reproduzierbar)
   local function newRng(seed)
      local s = seed
      return function(n)
         s = (s * 1103515245 + 12345) % 2147483648
         return math.floor(s / 65536) % n
      end
   end

   -- -------------------------------------------------------------------------
   H.section("Grundverhalten")
   -- -------------------------------------------------------------------------

   H.test("Compute: Standardansicht, Sortierung, Statistik, Eintragsfelder", function()
      local T = chestBoot()
      local F = T.Filter
      local entries, stats = F.Compute(4)
      -- Qualitaet absteigend, Name aufsteigend; Duplikat 2006 weg
      H.eq(idsOf(entries), "2001,2003,2002,2004,2005,2008,2007")
      H.eq(stats.total, 8)
      H.eq(stats.shown, 7)
      H.eq(stats.unresolved, 0)
      H.eq(stats.hiddenByFilter, 0)
      local e = entries[1]
      H.eq(e.id, 2001)
      H.eq(e.info.name, "Plate Chest Alpha")
      H.eq(e.info.quality, 4)
      H.eq(e.favorite, false)
      H.eq(e.isNew, false)
      H.eq(e.applied, false)
      H.eq(e.wanted, false)
      H.eq(#F.Compute(4), 7)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Compute: Slot ohne Liste, ungueltige Slots, Fremdtypen", function()
      local T = chestBoot()
      local F = T.Filter
      -- (NaN/unendlich/Bruchzahl waren ein Fehler: "table index is NaN")
      for _, slot in ipairs({ 0, 15, 11, 99, -1, 19, 4.5, 0 / 0, 1 / 0, -1 / 0 }) do
         local entries, stats = F.Compute(slot)
         H.eq(#entries, 0, "slot " .. tostring(slot))
         H.eq(#F.Types(slot), 0, "Types " .. tostring(slot))
         H.eq(#F.Qualities(slot), 0, "Qualities " .. tostring(slot))
         H.eq(stats.total, 0)
         H.eq(stats.shown, 0)
         H.eq(stats.unresolved, 0)
      end
      for _, bad in ipairs({ "4", true, {} }) do
         local entries, stats = F.Compute(bad)
         H.eq(#entries, 0)
         H.eq(stats.total, 0)
      end
      local entries, stats = F.Compute(nil)
      H.eq(#entries, 0)
      H.eq(stats.total, 0)
      H.eq(#F.Types(99), 0)
      H.eq(#F.Qualities(99), 0)
      H.eq(#F.Types(nil), 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Compute: ids der Liste werden bereinigt (HIDDEN, doppelt)", function()
      -- Der Server schickt nie 0/HIDDEN in Listen; Filter ignoriert sie trotzdem
      local T = chestBoot()
      local F = T.Filter
      feed(T, 4, { 2001, HIDDEN, 2002, 2001 })
      local entries, stats = F.Compute(4)
      H.eq(idsOf(entries), "2001,2002")
      H.eq(stats.unresolved, 0)
   end)

   H.test("Compute: Liste waehrend des Ladens (nicht fertig) liefert Teilergebnis", function()
      local T = chestBoot()
      local F = T.Filter
      feed(T, 4, { 2001, 2002, 2003 }, { noEnd = true })
      local entries, stats = F.Compute(4)
      H.eq(idsOf(entries), "2001,2003,2002")
      H.eq(stats.total, 3)
      H.eq(stats.ready, false)
      T.Net.Handle("AvailableTransmogs:4:405:3:end")
      entries, stats = F.Compute(4)
      H.eq(stats.ready, true)
      H.eq(idsOf(entries), "2001,2003,2002")
   end)

   -- -------------------------------------------------------------------------
   H.section("Suche")
   -- -------------------------------------------------------------------------

   H.test("Suche: Namensteil, Gross-/Kleinschreibung, mehrere Begriffe (UND)", function()
      local T = chestBoot()
      local F = T.Filter
      F.SetSearch("plate")
      H.eq(idsOf((F.Compute(4))), "2001,2002")        -- 2006 ist Duplikat von 2002
      F.SetSearch("PLATE CHEST")
      H.eq(idsOf((F.Compute(4))), "2001,2002")
      F.SetSearch("  plate    alpha ")
      H.eq(idsOf((F.Compute(4))), "2001")
      F.SetSearch("alpha plate")                       -- Reihenfolge egal
      H.eq(idsOf((F.Compute(4))), "2001")
      F.SetSearch("chest")
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002")
      F.SetSearch("lph")                               -- Teilstring mitten im Wort
      H.eq(idsOf((F.Compute(4))), "2001")
      F.SetSearch("plate zzz")
      H.eq(#F.Compute(4), 0)
      F.SetSearch("")
      H.eq(#F.Compute(4), 7)
   end)

   H.test("Suche: lokalisierter Typ (Klasse und Unterklasse)", function()
      local T = chestBoot()
      local F = T.Filter
      F.SetSearch("armor")                             -- Klasse
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002,2004,2005,2007")
      F.SetSearch("leather")                           -- Unterklasse (Typ)
      H.eq(idsOf((F.Compute(4))), "2005")
      F.SetSearch("consumable")
      H.eq(idsOf((F.Compute(4))), "2008")
      F.SetSearch("mail chest")                        -- Typ-Begriff + Name-Begriff
      H.eq(idsOf((F.Compute(4))), "2003")
   end)

   H.test("Suche: Umlaute sind ohne Beachtung der Schreibweise gleich", function()
      local d = {}
      put(d, 1001, "Helm of Plate", 4, 200, "Armor", "Plate", "INVTYPE_HEAD", "HeadP")
      put(d, 3001, "Sch\195\164del des Verderbers", 3, 100, "Armor", "Plate", "INVTYPE_HEAD", "S1")
      put(d, 3002, "SCH\195\132DELSPALTER", 3, 100, "Armor", "Plate", "INVTYPE_HEAD", "S2")
      put(d, 3003, "\195\132rmelschoner", 2, 100, "Armor", "Plate", "INVTYPE_HEAD", "S3")
      put(d, 3004, "\195\156berwurf der Nacht", 2, 100, "Armor", "Plate", "INVTYPE_HEAD", "S4")
      put(d, 3005, "Ma\195\159anzug", 2, 100, "Armor", "Plate", "INVTYPE_HEAD", "S5")
      put(d, 3006, "\208\168\208\187\208\181\208\188 \208\159\208\190\208\178\208\181\208\187\208\184\209\130\208\181\208\187\209\143",
         2, 100, "Armor", "Plate", "INVTYPE_HEAD", "S6")   -- "Шлем Повелителя"
      put(d, 3007, "Schaedel ohne Umlaut", 2, 100, "Armor", "Plate", "INVTYPE_HEAD", "S7")
      local T = boot({ items = d, equip = { [1] = 1001 } })
      local F = T.Filter
      feed(T, 0, { 3001, 3002, 3003, 3004, 3005, 3006, 3007 })

      local function find(text)
         F.SetSearch(text)
         local entries = F.Compute(0)
         table.sort(entries, function(a, b) return a.id < b.id end)
         return idsOf(entries)
      end
      -- kleingeschriebene Suche findet "Sch\195\164del" und "SCH\195\132DEL..."
      H.eq(find("sch\195\164del"), "3001,3002")
      H.eq(find("SCH\195\132DEL"), "3001,3002")
      H.eq(find("Sch\195\164del"), "3001,3002")
      H.eq(find("sch\195\164delspalter"), "3002")
      -- grosses Ae am Wortanfang
      H.eq(find("\195\164rmel"), "3003")
      H.eq(find("\195\132RMEL"), "3003")
      H.eq(find("\195\188berwurf"), "3004")
      H.eq(find("\195\156BERWURF"), "3004")
      -- sz bleibt unveraendert
      H.eq(find("ma\195\159anzug"), "3005")
      H.eq(find("MA\195\159ANZUG"), "3005")
      -- ae ist nicht ae-Umlaut
      H.eq(find("schaedel"), "3007")
      -- Kyrillisch
      H.eq(find("\209\136\208\187\208\181\208\188"), "3006")                 -- "шлем"
      H.eq(find("\208\168\208\155\208\149\208\156"), "3006")                 -- "ШЛЕМ"
      H.eq(find("\208\191\208\190\208\178\208\181\208\187\208\184\209\130"), "3006")   -- "повелит"
      F.SetSearch("")
   end)

   H.test("Suche: Item-ID (#id und reine Zahl), nur ganze ID", function()
      local T = chestBoot()
      local F = T.Filter
      F.SetSearch("#2003")
      H.eq(idsOf((F.Compute(4))), "2003")
      F.SetSearch("2003")
      H.eq(idsOf((F.Compute(4))), "2003")
      F.SetSearch("  #2003  ")
      H.eq(idsOf((F.Compute(4))), "2003")
      -- Teilziffern sind keine Item-ID
      F.SetSearch("#200")
      H.eq(#F.Compute(4), 0)
      F.SetSearch("#20033")
      H.eq(#F.Compute(4), 0)
      F.SetSearch("#99999")
      H.eq(#F.Compute(4), 0)
      -- #id kombiniert mit Textbegriff (UND)
      F.SetSearch("#2003 mail")
      H.eq(idsOf((F.Compute(4))), "2003")
      F.SetSearch("#2003 plate")
      H.eq(#F.Compute(4), 0)
      -- #id sucht NUR die ID, nie im Namen
      F.SetSearch("#abc")
      H.eq(#F.Compute(4), 0)
   end)

   H.test("Suche: Zahl im Namen wird auch als Text gefunden", function()
      local T = chestBoot(function(d)
         put(d, 2020, "Tier 10 Helm", 3, 100, "Armor", "Plate", "INVTYPE_CHEST", "T10")
      end)
      feed(T, 4, { 2001, 2020 })
      T.Filter.SetSearch("10")
      H.eq(idsOf((T.Filter.Compute(4))), "2020")
      T.Filter.SetSearch("#10")        -- ID 10 gibt es nicht, Namen zaehlen bei #id nicht
      H.eq(#T.Filter.Compute(4), 0)
   end)

   H.test("Suche: #id trifft nur die ID, reine Zahl auch den Namen", function()
      local T = chestBoot(function(d)
         put(d, 2030, "Relic #2031 Special", 3, 100, "Armor", "Plate", "INVTYPE_CHEST", "R1")
         put(d, 2031, "Ordinary Plate", 3, 100, "Armor", "Plate", "INVTYPE_CHEST", "R2")
      end)
      local F = T.Filter
      feed(T, 4, { 2030, 2031 })
      F.SetSearch("#2031")
      H.eq(idsOf((F.Compute(4))), "2031")
      F.SetSearch("#2030")
      H.eq(idsOf((F.Compute(4))), "2030")
      F.SetSearch("2031")                  -- ID 2031 und der Name von 2030
      H.eq(idsOf((F.Compute(4))), "2031,2030")
      F.SetSearch("#0002031")              -- fuehrende Nullen: gleiche Zahl
      H.eq(idsOf((F.Compute(4))), "2031")
   end)

   H.test("Suche: leere Eingaben, einzelnes #, Muster-Sonderzeichen", function()
      local T = chestBoot(function(d)
         put(d, 2021, "Helm (Rare) 100%", 3, 100, "Armor", "Plate", "INVTYPE_CHEST", "P1")
      end)
      local F = T.Filter
      feed(T, 4, { 2001, 2021 })
      F.SetSearch("#")
      H.eq(#F.Compute(4), 2)
      H.falsy(F.IsActive())
      F.SetSearch("   ")
      H.falsy(F.IsActive())
      F.SetSearch("(rare)")
      H.eq(idsOf((F.Compute(4))), "2021")
      F.SetSearch("100%")
      H.eq(idsOf((F.Compute(4))), "2021")
      F.SetSearch("%")
      H.eq(idsOf((F.Compute(4))), "2021")
      F.SetSearch("[")
      H.eq(#F.Compute(4), 0)
      F.SetSearch(".")
      H.eq(#F.Compute(4), 0)
      F.SetSearch("|cffff0000")
      H.eq(#F.Compute(4), 0)
      F.SetSearch(nil)                -- nil leert
      H.eq(#F.Compute(4), 2)
      F.SetSearch(string.rep("x", 5000))
      H.eq(#F.Compute(4), 0)
      F.SetSearch("")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Suche: FILTER_CHANGED nur bei echter Aenderung; Filter.state.search", function()
      local T = chestBoot()
      local F = T.Filter
      local c = counter(T, { "FILTER_CHANGED" })
      F.SetSearch("plate")
      H.eq(c.FILTER_CHANGED, 1)
      F.SetSearch("PLATE ")            -- gleiche Begriffe
      H.eq(c.FILTER_CHANGED, 1)
      F.SetSearch("plate alpha")
      H.eq(c.FILTER_CHANGED, 2)
      H.truthy(F.IsActive())
      F.SetSearch("")
      H.eq(c.FILTER_CHANGED, 3)
      H.falsy(F.IsActive())
      -- Komfortzugriff: nie in der gespeicherten Tabelle
      F.state.search = "gamma"
      H.eq(F.search, "gamma")
      H.eq(F.state.search, "gamma")
      H.eq(rawget(T.DB.char.filter, "search"), nil)
      H.eq(idsOf((F.Compute(4))), "2003")
      F.SetSearch("")
   end)

   H.test("Suche: wirkt vor der Duplikat-Zusammenfassung", function()
      local T = chestBoot()
      local F = T.Filter
      F.SetSearch("beta copy")         -- trifft nur das Duplikat 2006
      H.eq(idsOf((F.Compute(4))), "2006")
      F.SetSearch("beta")              -- beide; Repraesentant 2002 (Qualitaet)
      H.eq(idsOf((F.Compute(4))), "2002")
   end)

   -- -------------------------------------------------------------------------
   H.section("Qualitaet, Typ, Favoriten, Neu")
   -- -------------------------------------------------------------------------

   H.test("Qualitaetsfilter: ein-/ausblenden, Statistik, Ereignisse", function()
      local T = chestBoot()
      local F = T.Filter
      local c = counter(T, { "FILTER_CHANGED" })
      F.SetQuality(0, false)
      H.eq(c.FILTER_CHANGED, 1)
      F.SetQuality(0, false)           -- keine Aenderung
      H.eq(c.FILTER_CHANGED, 1)
      local entries, stats = F.Compute(4)
      H.eq(idsOf(entries), "2001,2003,2002,2004,2005,2008")
      H.eq(stats.hiddenByFilter, 1)
      H.eq(T.DB.char.filter.qualities[0], false)
      H.truthy(F.IsActive())
      F.SetQuality(0, true)
      H.eq(c.FILTER_CHANGED, 2)
      H.eq(T.DB.char.filter.qualities[0], nil)
      H.falsy(F.IsActive())
      H.eq(#F.Compute(4), 7)
   end)

   H.test("Qualitaetsfilter: mehrere, ungueltige Werte, Duplikat rueckt nach", function()
      local T = chestBoot()
      local F = T.Filter
      local c = counter(T, { "FILTER_CHANGED" })
      F.SetQuality(-1, false)
      F.SetQuality(8, false)
      F.SetQuality("x", false)
      F.SetQuality(nil, false)
      H.eq(c.FILTER_CHANGED, nil)
      H.falsy(F.IsActive())
      F.SetQuality("2", false)         -- Zahltext
      H.eq(T.DB.char.filter.qualities[2], false)
      F.SetQuality(2, true)
      -- q3 aus: 2002 weg -> Duplikat 2006 (q2) wird Repraesentant seiner Gruppe
      F.SetQuality(3, false)
      local entries, stats = F.Compute(4)
      H.eq(idsOf(entries), "2001,2004,2005,2006,2008,2007")
      H.eq(stats.hiddenByFilter, 2)    -- 2002, 2003
      F.SetQuality(3, true)
      F.SetQuality(2, false)
      entries, stats = F.Compute(4)
      H.eq(idsOf(entries), "2001,2003,2002,2008,2007")
      H.eq(stats.hiddenByFilter, 3)    -- 2004, 2005, 2006
      H.eq(stats.shown + stats.hiddenByFilter + stats.hiddenDuplicates + stats.unresolved, stats.total)
   end)

   H.test("Typfilter: ausblenden, typeKey nil bleibt, Ereignisse, Statistik", function()
      local T = chestBoot()
      local F = T.Filter
      local c = counter(T, { "FILTER_CHANGED" })
      F.SetType(401, false)                    -- Stoff
      H.eq(c.FILTER_CHANGED, 1)
      F.SetType(401, false)
      H.eq(c.FILTER_CHANGED, 1)
      local entries, stats = F.Compute(4)
      H.eq(idsOf(entries), "2001,2003,2002,2005,2008")   -- 2004, 2007 (Stoff) weg; 2008 ohne typeKey bleibt
      H.eq(stats.hiddenByFilter, 2)
      H.eq(T.DB.char.filter.typesOff[401], true)
      H.truthy(F.IsActive())
      F.SetType(403, false)                    -- Kette zusaetzlich
      H.eq(idsOf((F.Compute(4))), "2001,2002,2005,2008")
      F.SetType(401, true)
      F.SetType(403, true)
      H.eq(T.DB.char.filter.typesOff[401], nil)
      H.eq(#F.Compute(4), 7)
      F.SetType(nil, false)
      F.SetType("abc", false)
      H.eq(c.FILTER_CHANGED, 4)
      H.falsy(F.IsActive())
   end)

   H.test("Typfilter: eigener Typ (angelegter Gegenstand) wird nie ausgeblendet", function()
      local T = chestBoot()
      local F = T.Filter
      F.SetType(404, false)            -- Platte = angelegte Brust
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002,2004,2005,2008,2007")
      F.SetType(401, false)
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002,2005,2008")
      -- Brust wechselt auf Kette (1005): Kette ist jetzt eigener Typ, Platte kann ausgeblendet werden
      mock.world.equipment[5] = 1005
      T.State.RefreshEquipment()
      H.eq(T.State.Equipped(4).typeKey, 403)
      F.SetType(403, false)
      local entries = F.Compute(4)
      H.eq(idsOf(entries), "2003,2005,2008")          -- Platte+Stoff aus, Kette (own) bleibt
      for _, t in ipairs(F.Types(4)) do
         H.eq(t.own, t.typeKey == 403, "own " .. t.typeKey)
      end
   end)

   H.test("Favoriten: nur Favoriten, favorite-Flag, FAVORITES_CHANGED", function()
      local T = chestBoot()
      local F = T.Filter
      T.DB.char.favorites[2003] = true
      T.Events.Fire("FAVORITES_CHANGED")
      local entries = F.Compute(4)
      H.eq(entryOf(entries, 2003).favorite, true)
      H.eq(entryOf(entries, 2001).favorite, false)
      F.SetFavoritesOnly(true)
      H.truthy(F.IsActive())
      H.eq(idsOf((F.Compute(4))), "2003")
      -- Favorit wechselt (Anzahl gleich): nur das Ereignis meldet es
      T.DB.char.favorites[2003] = nil
      T.DB.char.favorites[2004] = true
      T.Events.Fire("FAVORITES_CHANGED")
      H.eq(idsOf((F.Compute(4))), "2004")
      T.DB.char.favorites = {}
      T.Events.Fire("FAVORITES_CHANGED")
      local e, stats = F.Compute(4)
      H.eq(#e, 0)
      H.eq(stats.hiddenByFilter, 7 + 1)          -- alle 8 aufgeloesten
      F.SetFavoritesOnly(false)
      H.eq(#F.Compute(4), 7)
   end)

   H.test("Neu: isNew-Flag, nur Neue, Login-Sweep zaehlt nicht", function()
      local T = chestBoot()
      local F = T.Filter
      -- innerhalb der ersten 10 s nach PLAYER_ENTERING_WORLD: kein "neu"
      T.enteredWorldAt = GetTime()
      T.Net.Handle("CollectionUpdated:2005")
      H.eq(T.State.new[2005], nil)
      mock.Advance(11)
      T.Net.Handle("CollectionUpdated:2004")
      H.eq(T.State.new[2004], true)
      local entries = F.Compute(4)
      H.eq(entryOf(entries, 2004).isNew, true)
      H.eq(entryOf(entries, 2005).isNew, false)
      F.SetNewOnly(true)
      H.truthy(F.IsActive())
      H.eq(idsOf((F.Compute(4))), "2004")
      F.SetNewOnly(false)
      H.falsy(F.IsActive())
   end)

   H.test("Favoriten und Neu zusammen (UND), Reset stellt Standard her", function()
      local T = chestBoot()
      local F = T.Filter
      T.Net.Handle("CollectionUpdated:2004")
      T.Net.Handle("CollectionUpdated:2005")
      T.DB.char.favorites[2005] = true
      T.DB.char.favorites[2003] = true
      T.Events.Fire("FAVORITES_CHANGED")
      F.SetNewOnly(true)
      F.SetFavoritesOnly(true)
      H.eq(idsOf((F.Compute(4))), "2005")
      local c = counter(T, { "FILTER_CHANGED" })
      F.SetSearch("leather")
      F.SetQuality(3, false)
      F.SetType(401, false)
      H.eq(c.FILTER_CHANGED, 3)
      F.SetHideDuplicates(false)
      F.SetSort("NAME")
      c.FILTER_CHANGED = 0
      F.Reset()
      H.eq(c.FILTER_CHANGED, 1, "genau ein Ereignis")
      H.falsy(F.IsActive())
      local f = T.DB.char.filter
      H.eq(f.favoritesOnly, false)
      H.eq(f.newOnly, false)
      H.eq(next(f.qualities), nil)
      H.eq(next(f.typesOff), nil)
      H.eq(F.search, "")
      -- hideDuplicates und sort bleiben
      H.eq(f.hideDuplicates, false)
      H.eq(f.sort, "NAME")
      -- Reset ohne etwas zu aendern: kein Ereignis
      F.Reset()
      H.eq(c.FILTER_CHANGED, 1)
   end)

   H.test("Filter: Wechselwirkung, Statistik zerlegt die Liste vollstaendig", function()
      local T = chestBoot()
      local F = T.Filter
      F.SetSearch("chest")
      F.SetQuality(4, false)
      local entries, stats = F.Compute(4)
      -- "chest": 2001(q4, aus), 2002, 2003, 2006 -> Duplikatgruppe B: 2002 bleibt
      H.eq(idsOf(entries), "2003,2002")
      H.eq(stats.total, 8)
      H.eq(stats.shown, 2)
      H.eq(stats.shown + stats.hiddenByFilter + stats.hiddenDuplicates + stats.unresolved, stats.total)
      H.eq(stats.hiddenDuplicates, 1)
      H.eq(stats.hiddenByFilter, 5)
   end)

   -- -------------------------------------------------------------------------
   H.section("Duplikate")
   -- -------------------------------------------------------------------------

   -- Kopfliste (Slot 0, angelegt 1001 Platte) mit Gruppen gleicher Icons
   local function dupBoot()
      local d = baseItems()
      put(d, 4101, "Twin Low", 2, 100, "Armor", "Plate", "INVTYPE_HEAD", "G1")
      put(d, 4102, "Twin High", 4, 100, "Armor", "Plate", "INVTYPE_HEAD", "G1")
      put(d, 4103, "Twin High Too", 4, 100, "Armor", "Plate", "INVTYPE_HEAD", "G1")
      put(d, 4201, "Same Icon Plate", 3, 100, "Armor", "Plate", "INVTYPE_HEAD", "SAME")
      put(d, 4202, "Same Icon Mail", 3, 100, "Armor", "Mail", "INVTYPE_HEAD", "SAME")
      put(d, 4301, "Case A", 3, 100, "Armor", "Cloth", "INVTYPE_HEAD", "Case")
      put(d, 4302, "Case B", 3, 100, "Armor", "Cloth", "INVTYPE_HEAD", nil)
      d[4302].icon = "interface\\icons\\CASE"
      local T = boot({ items = d, equip = { [1] = 1001 } })
      feed(T, 0, { 4101, 4102, 4103, 4201, 4202, 4301, 4302 })
      return T
   end

   H.test("Duplikate: Gruppen nach Icon, Typ und Platz; Repraesentant Qualitaet/niedrige id", function()
      local T = dupBoot()
      local F = T.Filter
      local entries, stats = F.Compute(0)
      -- G1: 4102 (q4, niedrigere id als 4103); SAME: Platte und Kette bleiben getrennt;
      -- Case: Icon-Schreibweise egal -> 4301 (niedrigere id).
      -- Reihenfolge (QUALITY): q4 zuerst, dann q3 nach Name:
      -- "case a" < "same icon mail" < "same icon plate"
      H.eq(idsOf(entries), "4102,4301,4202,4201")
      H.eq(stats.hiddenDuplicates, 3)
      H.eq(stats.shown, 4)
      F.SetHideDuplicates(false)
      entries = F.Compute(0)
      H.eq(#entries, 7)
      local c = counter(T, { "FILTER_CHANGED" })
      F.SetHideDuplicates(false)
      H.eq(c.FILTER_CHANGED, nil)
      F.SetHideDuplicates(true)
      H.eq(c.FILTER_CHANGED, 1)
      H.eq(T.DB.char.filter.hideDuplicates, true)
   end)

   H.test("Duplikate: Repraesentant favorite > Qualitaet, applied > favorite, wanted > applied", function()
      local T = dupBoot()
      local F = T.Filter
      local function group()
         local out = {}
         for _, e in ipairs((F.Compute(0))) do
            if e.id >= 4101 and e.id <= 4103 then out[#out + 1] = e.id end
         end
         return table.concat(out, ",")
      end
      H.eq(group(), "4102")
      -- Favorit schlaegt Qualitaet
      T.DB.char.favorites[4103] = true
      T.Events.Fire("FAVORITES_CHANGED")
      H.eq(group(), "4103")
      T.DB.char.favorites[4103] = nil
      T.DB.char.favorites[4101] = true
      T.Events.Fire("FAVORITES_CHANGED")
      H.eq(group(), "4101")
      -- applied schlaegt Favorit
      T.Net.Handle("TransmogStatus:1:0,4103")
      H.eq(T.State.Applied(0), 4103)
      H.eq(group(), "4103")
      local e = entryOf((F.Compute(0)), 4103)
      H.eq(e.applied, true)
      H.eq(e.wanted, true)      -- ohne Auswahl ist wanted = Baseline
      -- wanted (Auswahl) schlaegt applied
      H.truthy(T.State.Select(0, 4102))
      H.eq(group(), "4102")
      e = entryOf((F.Compute(0)), 4102)
      H.eq(e.wanted, true)
      H.eq(e.applied, false)
      H.eq(entryOf((F.Compute(0)), 4101), nil)
      -- Auswahl verwerfen: wieder applied
      T.State.DiscardAll()
      H.eq(group(), "4103")
      -- Favorit entfernen, Status leeren: Qualitaet/id
      T.DB.char.favorites[4101] = nil
      T.Events.Fire("FAVORITES_CHANGED")
      T.Net.Handle("TransmogStatus:0")
      H.eq(group(), "4102")
   end)

   H.test("Duplikate: applied schlaegt Favorit und Qualitaet, wenn die Auswahl in einer anderen Gruppe liegt", function()
      local T = dupBoot()
      local F = T.Filter
      T.DB.char.favorites[4101] = true
      T.Events.Fire("FAVORITES_CHANGED")
      T.Net.Handle("TransmogStatus:1:0,4103")
      H.truthy(T.State.Select(0, 4201))          -- Auswahl liegt in der Gruppe SAME
      local entries = F.Compute(0)
      local out = {}
      for _, e in ipairs(entries) do
         if e.id >= 4101 and e.id <= 4103 then out[#out + 1] = e.id end
      end
      H.eq(table.concat(out, ","), "4103")        -- weder Favorit 4101 noch 4102 (gleiche Qualitaet, kleinere id)
      H.eq(entryOf(entries, 4103).applied, true)
      H.eq(entryOf(entries, 4103).wanted, false)
      H.eq(entryOf(entries, 4201).wanted, true)
   end)

   H.test("Duplikate: nachtraeglich geaenderter typeKey bildet die Gruppen neu", function()
      local T = chestBoot()
      local F = T.Filter
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002,2004,2005,2008,2007")   -- 2006 ist Duplikat von 2002
      -- Items stuft einen Gegenstand um, sobald die AH-Listen verfuegbar sind
      T.Items.Info(2006).typeKey = 403
      F.Invalidate()
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002,2004,2005,2006,2008,2007")
   end)

   H.test("Duplikate: Gleichstand aller Kriterien -> niedrigere id, unabhaengig von der Eingabe", function()
      local d = baseItems()
      put(d, 4401, "Twin A", 3, 100, "Armor", "Plate", "INVTYPE_HEAD", "TWIN")
      put(d, 4402, "Twin B", 3, 100, "Armor", "Plate", "INVTYPE_HEAD", "TWIN")
      put(d, 4403, "Twin C", 3, 100, "Armor", "Plate", "INVTYPE_HEAD", "TWIN")
      local T = boot({ items = d, equip = { [1] = 1001 } })
      for _, order in ipairs({ { 4401, 4402, 4403 }, { 4403, 4402, 4401 }, { 4402, 4403, 4401 } }) do
         feed(T, 0, order)
         H.eq(idsOf((T.Filter.Compute(0))), "4401")
      end
   end)

   H.test("Duplikate: gleiches Icon mit anderem Platz bleibt getrennt; Platzhalter-Icon ist einzigartig", function()
      local d = baseItems()
      -- gleiches Icon, gleicher Typ, aber anderer Ausruestungsplatz
      put(d, 4501, "Plate Head Look", 3, 100, "Armor", "Plate", "INVTYPE_HEAD", "X")
      put(d, 4502, "Plate Chest Look", 3, 100, "Armor", "Plate", "INVTYPE_CHEST", "X")
      put(d, 4503, "Odd One", 3, 100, "Armor", "Plate", "INVTYPE_ROBE", "X")
      -- ohne Icon liefert Items das Fragezeichen: nie zusammenfassen
      put(d, 4601, "Mystery A", 3, 100, "Armor", "Plate", "INVTYPE_HEAD", nil)
      put(d, 4602, "Mystery B", 3, 100, "Armor", "Plate", "INVTYPE_HEAD", nil)
      local T = boot({ items = d, equip = { [1] = 1001 } })
      feed(T, 0, { 4501, 4502, 4503, 4601, 4602 })
      local entries, stats = T.Filter.Compute(0)
      table.sort(entries, function(a, b) return a.id < b.id end)
      H.eq(idsOf(entries), "4501,4502,4503,4601,4602")
      H.eq(stats.hiddenDuplicates, 0)
   end)

   -- -------------------------------------------------------------------------
   H.section("Sortierung")
   -- -------------------------------------------------------------------------

   H.test("Sortierung: QUALITY, NAME, ILEVEL; Schluessel ungueltig/gross-klein", function()
      local T = chestBoot()
      local F = T.Filter
      local c = counter(T, { "FILTER_CHANGED" })
      H.eq(T.DB.char.filter.sort, "QUALITY")
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002,2004,2005,2008,2007")
      F.SetSort("NAME")
      H.eq(c.FILTER_CHANGED, 1)
      H.eq(idsOf((F.Compute(4))), "2004,2005,2003,2001,2002,2007,2008")
      F.SetSort("name")                -- gleicher Schluessel
      H.eq(c.FILTER_CHANGED, 1)
      F.SetSort("ILEVEL")
      H.eq(idsOf((F.Compute(4))), "2001,2002,2003,2004,2005,2008,2007")
      F.SetSort("BOGUS")
      F.SetSort(nil)
      F.SetSort(5)
      H.eq(T.DB.char.filter.sort, "ILEVEL")
      H.eq(c.FILTER_CHANGED, 2)
      F.SetSort("Quality")
      H.eq(T.DB.char.filter.sort, "QUALITY")
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002,2004,2005,2008,2007")
      -- ungueltiger gespeicherter Schluessel faellt auf QUALITY zurueck
      T.DB.char.filter.sort = "WHATEVER"
      F.Invalidate()
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002,2004,2005,2008,2007")
   end)

   -- Erzeugt N Gegenstaende mit vielen Gleichstaenden fuer Slot 4
   local function tieItems(n, seed)
      local rnd = newRng(seed or 7)
      local d = baseItems()
      local list = {}
      for i = 1, n do
         local id = 6000 + i
         local sub = ({ "Plate", "Mail", "Leather", "Cloth" })[1 + rnd(4)]
         -- wenige Namen/Qualitaeten/Itemlevel, jedes Item mit eigenem Icon (keine Duplikate)
         put(d, id, "Name " .. rnd(6), rnd(5), 100 + 10 * rnd(3), "Armor", sub, "INVTYPE_CHEST", "T" .. id)
         list[i] = id
      end
      return d, list
   end

   H.test("Sortierung: bei jeder Eingabereihenfolge dasselbe Ergebnis (deterministisch)", function()
      local d, list = tieItems(60, 11)
      local T = boot({ items = d, equip = { [5] = 1004 } })
      local F = T.Filter
      local rnd = newRng(99)
      for _, key in ipairs({ "QUALITY", "NAME", "ILEVEL" }) do
         F.SetSort(key)
         feed(T, 4, list)
         local baseline = idsOf((F.Compute(4)))
         H.eq(#F.Compute(4), 60)
         for round = 1, 6 do
            -- Fisher-Yates
            local shuffled = {}
            for i = 1, #list do shuffled[i] = list[i] end
            for i = #shuffled, 2, -1 do
               local j = 1 + rnd(i)
               shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
            end
            feed(T, 4, shuffled)
            H.eq(idsOf((F.Compute(4))), baseline, key .. " Durchgang " .. round)
         end
      end
   end)

   H.test("Sortierung: Primaer-/Sekundaerschluessel eingehalten, Gleichstand nach id", function()
      local d, list = tieItems(120, 3)
      local T = boot({ items = d, equip = { [5] = 1004 } })
      local F = T.Filter
      feed(T, 4, list)
      local function lowerName(e) return string.lower(e.info.name) end
      F.SetSort("QUALITY")
      local e = F.Compute(4)
      for i = 2, #e do
         local a, b = e[i - 1], e[i]
         H.truthy(a.info.quality >= b.info.quality, "Qualitaet absteigend")
         if a.info.quality == b.info.quality then
            H.truthy(lowerName(a) <= lowerName(b), "Name aufsteigend")
            if lowerName(a) == lowerName(b) then H.truthy(a.id < b.id, "id aufsteigend") end
         end
      end
      F.SetSort("NAME")
      e = F.Compute(4)
      for i = 2, #e do
         local a, b = e[i - 1], e[i]
         H.truthy(lowerName(a) <= lowerName(b), "Name aufsteigend")
         if lowerName(a) == lowerName(b) then H.truthy(a.id < b.id, "id aufsteigend (NAME)") end
      end
      F.SetSort("ILEVEL")
      e = F.Compute(4)
      for i = 2, #e do
         local a, b = e[i - 1], e[i]
         H.truthy(a.info.ilvl >= b.info.ilvl, "Itemlevel absteigend")
      end
      H.eq(#e, 120)
   end)

   H.test("Sortierung: vollstaendiger Gleichstand (Name/Qualitaet/Itemlevel) -> id aufsteigend", function()
      local d = baseItems()
      local list = {}
      for i = 1, 8 do
         local id = 7000 + i
         put(d, id, "Same Name", 3, 100, "Armor", "Plate", "INVTYPE_CHEST", "U" .. id)
         list[i] = id
      end
      local T = boot({ items = d, equip = { [5] = 1004 } })
      local F = T.Filter
      local shuffled = { 7005, 7002, 7008, 7001, 7007, 7003, 7006, 7004 }
      feed(T, 4, shuffled)
      for _, key in ipairs({ "QUALITY", "NAME", "ILEVEL" }) do
         F.SetSort(key)
         H.eq(idsOf((F.Compute(4))), "7001,7002,7003,7004,7005,7006,7007,7008", key)
      end
   end)

   H.test("Sortierung: Namensvergleich ohne Beachtung der Schreibweise (auch Umlaute)", function()
      local d = {}
      put(d, 1001, "Helm of Plate", 4, 200, "Armor", "Plate", "INVTYPE_HEAD", "HeadP")
      put(d, 8001, "beta", 3, 1, "Armor", "Plate", "INVTYPE_HEAD", "N1")
      put(d, 8002, "Alpha", 3, 1, "Armor", "Plate", "INVTYPE_HEAD", "N2")
      put(d, 8003, "ALPHA", 3, 1, "Armor", "Plate", "INVTYPE_HEAD", "N3")
      put(d, 8004, "Gamma", 3, 1, "Armor", "Plate", "INVTYPE_HEAD", "N4")
      local T = boot({ items = d, equip = { [1] = 1001 } })
      feed(T, 0, { 8004, 8001, 8003, 8002 })
      T.Filter.SetSort("NAME")
      -- "Alpha"/"ALPHA" sind gleich (-> id), danach beta, Gamma
      H.eq(idsOf((T.Filter.Compute(0))), "8002,8003,8001,8004")
   end)

   -- -------------------------------------------------------------------------
   H.section("Seiten")
   -- -------------------------------------------------------------------------

   H.test("Page: Aufteilung, Klemmen, leere Liste, ungueltige Eingaben", function()
      local T = chestBoot()
      local F = T.Filter
      local list = {}
      for i = 1, 25 do list[i] = { id = i } end
      local page, total, cur = F.Page(list, 1, 10)
      H.eq(#page, 10)
      H.eq(total, 3)
      H.eq(cur, 1)
      H.eq(page[1].id, 1)
      H.eq(page[10].id, 10)
      H.eq(page[1], list[1], "Eintraege werden durchgereicht")
      page, total, cur = F.Page(list, 3, 10)
      H.eq(#page, 5)
      H.eq(page[1].id, 21)
      H.eq(page[5].id, 25)
      H.eq(cur, 3)
      -- Klemmen
      page, total, cur = F.Page(list, 99, 10)
      H.eq(cur, 3)
      H.eq(#page, 5)
      page, total, cur = F.Page(list, 0, 10)
      H.eq(cur, 1)
      page, total, cur = F.Page(list, -7, 10)
      H.eq(cur, 1)
      H.eq(#page, 10)
      page, total, cur = F.Page(list, 2.9, 10)     -- Bruchteil: abgerundet
      H.eq(cur, 2)
      page, total, cur = F.Page(list, nil, 10)
      H.eq(cur, 1)
      page, total, cur = F.Page(list, "2", 10)
      H.eq(cur, 2)
      page, total, cur = F.Page(list, 0 / 0, 10)
      H.eq(cur, 1)
      -- exakte Vielfache
      page, total, cur = F.Page(list, 5, 5)
      H.eq(total, 5)
      H.eq(#page, 5)
      page, total, cur = F.Page(list, 6, 5)
      H.eq(cur, 5)
      -- leere Liste: 1 Seite, Seite 1, leere Seite
      page, total, cur = F.Page({}, 5, 10)
      H.eq(#page, 0)
      H.eq(total, 1)
      H.eq(cur, 1)
      page, total, cur = F.Page(nil, 1, 10)
      H.eq(#page, 0)
      H.eq(total, 1)
      -- perPage ungueltig -> mindestens 1
      page, total, cur = F.Page(list, 1, 0)
      H.eq(#page, 1)
      H.eq(total, 25)
      page, total, cur = F.Page(list, 1, nil)
      H.eq(total, 25)
      page, total, cur = F.Page(list, 1, -3)
      H.eq(total, 25)
      -- groesser als die Liste
      page, total, cur = F.Page(list, 1, 1000)
      H.eq(#page, 25)
      H.eq(total, 1)
      -- unendlich viele je Seite: eine Seite mit allem (kein NaN-Bereich)
      page, total, cur = F.Page(list, 1, math.huge)
      H.eq(#page, 25)
      H.eq(total, 1)
      page, total, cur = F.Page(list, math.huge, 10)
      H.eq(cur, 3)
      page, total, cur = F.Page(list, -math.huge, 10)
      H.eq(cur, 1)
      -- die Eingabe bleibt unveraendert
      H.eq(#list, 25)
   end)

   H.test("Page: mit echten Compute-Ergebnissen, Seite nach Filteraenderung klemmen", function()
      local d, list = tieItems(45, 5)
      local T = boot({ items = d, equip = { [5] = 1004 } })
      local F = T.Filter
      feed(T, 4, list)
      local entries = F.Compute(4)
      H.eq(#entries, 45)
      local page, total, cur = F.Page(entries, 5, 10)
      H.eq(total, 5)
      H.eq(cur, 5)
      H.eq(#page, 5)
      F.SetSearch("name 1")
      entries = F.Compute(4)
      H.truthy(#entries < 45)
      page, total, cur = F.Page(entries, 5, 10)
      H.eq(cur, total, "Seite 5 wird auf die letzte Seite geklemmt")
      -- Seiten decken die Liste genau ab
      local seen, pages = {}, select(2, F.Page(entries, 1, 7))
      for p = 1, pages do
         for _, e in ipairs((F.Page(entries, p, 7))) do seen[#seen + 1] = e.id end
      end
      H.eq(#seen, #entries)
      H.eq(table.concat(seen, ","), idsOf(entries))
   end)

   -- -------------------------------------------------------------------------
   H.section("Facetten")
   -- -------------------------------------------------------------------------

   H.test("Types: Typen der Liste, Zaehler, Reihenfolge, Label, own", function()
      local T = chestBoot()
      local F = T.Filter
      local types = F.Types(4)
      local keys, counts = {}, {}
      for i, t in ipairs(types) do
         keys[i], counts[i] = t.typeKey, t.count
      end
      H.eq(table.concat(keys, ","), "404,403,402,401")      -- Platte -> Stoff
      H.eq(table.concat(counts, ","), "3,1,1,2")             -- ungefiltert, inkl. Duplikat 2006
      H.eq(types[1].label, "Plate")
      H.eq(types[4].label, "Cloth")
      H.eq(types[1].own, true)
      H.eq(types[2].own, false)
      -- ungefiltert: Filter aendern die Facetten nicht
      F.SetType(401, false)
      F.SetQuality(4, false)
      F.SetSearch("zzz")
      H.eq(#F.Types(4), 4)
      H.eq(F.Types(4)[1].count, 3)
      F.Reset()
      -- Kopie: Veraendern wirkt nicht zurueck
      local a = F.Types(4)
      a[#a + 1] = { typeKey = 1 }
      a[1] = nil
      H.eq(#F.Types(4), 4)
   end)

   H.test("Types: nur Typen, die in der Liste vorkommen (auch der eigene)", function()
      local T = chestBoot()
      local F = T.Filter
      -- Liste nur mit Stoff und Leder; angelegt ist Platte (404)
      feed(T, 4, { 2004, 2005, 2007 })
      local keys = {}
      for i, t in ipairs(F.Types(4)) do keys[i] = t.typeKey .. (t.own and "*" or "") end
      H.eq(table.concat(keys, ","), "402,401")
      -- Waffen: Typen nach Schluessel, own = Einhandschwert (207)
      local d = baseItems()
      put(d, 5001, "Axe", 3, 100, "Weapon", "Two-Handed Axes", "INVTYPE_2HWEAPON", "Ax")
      put(d, 5002, "Sword", 3, 100, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "Sw")
      put(d, 5003, "Shield", 3, 100, "Armor", "Shields", "INVTYPE_SHIELD", "Sh")
      T = boot({ items = d, equip = { [16] = 1015 } })
      feed(T, 15, { 5003, 5002, 5001 })
      keys = {}
      for i, t in ipairs(T.Filter.Types(15)) do keys[i] = t.typeKey .. (t.own and "*" or "") end
      H.eq(table.concat(keys, ","), "201,207*,406")
   end)

   H.test("Qualities: aufsteigend, ungefiltert, nur aufgeloeste", function()
      local d = baseItems()
      local T = boot({ items = d, equip = { [5] = 1004 } })
      feed(T, 4, { 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 9998, 9999 })   -- 9998/9999 unbekannt
      local F = T.Filter
      local q = F.Qualities(4)
      local out = {}
      for i, e in ipairs(q) do out[i] = e.quality .. "x" .. e.count end
      H.eq(table.concat(out, ","), "0x1,1x1,2x3,3x2,4x1")
      F.SetQuality(2, false)
      H.eq(#F.Qualities(4), 5, "Filter aendern die Zaehlung nicht")
      F.SetSearch("zzz")
      H.eq(#F.Qualities(4), 5)
      local copy = F.Qualities(4)
      copy[#copy + 1] = { quality = 9, count = 1 }
      H.eq(#F.Qualities(4), 5)
   end)

   H.test("Facetten: nicht aufgeloeste Items werden erst nach ITEMS_RESOLVED gezaehlt", function()
      local d = baseItems()
      local T = boot({ items = d, equip = { [5] = 1004 }, cache = false })
      local F = T.Filter
      feed(T, 4, { 2001, 2003, 2005 })
      local entries, stats = F.Compute(4)
      H.eq(#entries, 0)
      H.eq(stats.unresolved, 3)
      H.eq(stats.total, 3)
      H.eq(stats.shown, 0)
      H.eq(#F.Types(4), 0)
      H.eq(#F.Qualities(4), 0)
      H.truthy(T.Items.PendingCount() > 0, "Filter hat die Items bei Items angemeldet")
      -- Items werden vom Spiel nachgeliefert
      local c = counter(T, { "ITEMS_RESOLVED" })
      mock.Advance(2)
      H.truthy((c.ITEMS_RESOLVED or 0) >= 1)
      entries, stats = F.Compute(4)
      H.eq(stats.unresolved, 0)
      H.eq(idsOf(entries), "2001,2003,2005")
      H.eq(#F.Types(4), 3)
      H.eq(#F.Qualities(4), 3)
   end)

   -- -------------------------------------------------------------------------
   H.section("Cache und Ereignisse")
   -- -------------------------------------------------------------------------

   H.test("Cache: wiederholtes Compute teilt Eintraege, liefert aber eigene Arrays", function()
      local T = chestBoot()
      local F = T.Filter
      local e1, s1 = F.Compute(4)
      local e2, s2 = F.Compute(4)
      H.neq(e1, e2)
      H.neq(s1, s2)
      H.eq(e1[1], e2[1], "gleiche Eintragstabellen (Cache-Treffer)")
      H.eq(idsOf(e1), idsOf(e2))
      -- Veraendern der Kopien beschaedigt den Cache nicht
      table.insert(e2, 1, { id = -1 })
      e2[2] = nil
      s2.shown = 999
      local e3, s3 = F.Compute(4)
      H.eq(idsOf(e3), "2001,2003,2002,2004,2005,2008,2007")
      H.eq(s3.shown, 7)
   end)

   H.test("Cache: Ergebnis wird je Slot gehalten", function()
      local T = chestBoot()
      local F = T.Filter
      feed(T, 0, { 2001, 2002 })
      local c4 = F.Compute(4)
      local c0 = F.Compute(0)
      H.eq(idsOf(c4), "2001,2003,2002,2004,2005,2008,2007")
      H.eq(idsOf(c0), "2001,2002")
      -- Suche gilt fuer alle Slots
      F.SetSearch("beta")
      H.eq(idsOf((F.Compute(4))), "2002")
      H.eq(idsOf((F.Compute(0))), "2002")
   end)

   H.test("Cache: LIST_READY, STATUS_CHANGED, WANTED_CHANGED liefern frische Daten", function()
      local T = chestBoot()
      local F = T.Filter
      -- Beobachter NACH Filter (wie Grid): sieht in jedem Ereignis schon frische Daten
      local seen = {}
      for _, name in ipairs({ "LIST_READY", "STATUS_CHANGED", "WANTED_CHANGED", "FILTER_CHANGED" }) do
         T.Events.On(name, function()
            local entries = F.Compute(4)
            local e2001 = entryOf(entries, 2001)
            seen[name] = { ids = idsOf(entries), applied = e2001 and e2001.applied,
                           wanted = e2001 and e2001.wanted }
         end, seen)
      end
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002,2004,2005,2008,2007")
      -- LIST_READY: neue Liste
      feed(T, 4, { 2001, 2007 })
      H.eq(seen.LIST_READY.ids, "2001,2007")
      -- STATUS_CHANGED
      T.Net.Handle("TransmogStatus:1:4,2001")
      H.eq(seen.STATUS_CHANGED.applied, true)
      T.Net.Handle("TransmogStatus:0")
      H.eq(seen.STATUS_CHANGED.applied, false)
      -- WANTED_CHANGED
      H.truthy(T.State.Select(4, 2001))
      H.eq(seen.WANTED_CHANGED.wanted, true)
      T.State.Discard(4)
      H.eq(seen.WANTED_CHANGED.wanted, false)
      -- FILTER_CHANGED
      F.SetSearch("rag")
      H.eq(seen.FILTER_CHANGED.ids, "2007")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Cache: ITEMS_RESOLVED und EQUIPMENT_CHANGED liefern frische Daten", function()
      local d = baseItems()
      local T = boot({ items = d, equip = { [5] = 1004 }, cache = false })
      local F = T.Filter
      feed(T, 4, CHEST_LIST)
      local seenResolved
      T.Events.On("ITEMS_RESOLVED", function()
         seenResolved = idsOf((F.Compute(4)))
      end, F)
      local _, stats = F.Compute(4)
      H.eq(stats.unresolved, 8)
      mock.Advance(3)
      H.eq(seenResolved, "2001,2003,2002,2004,2005,2008,2007")
      _, stats = F.Compute(4)
      H.eq(stats.unresolved, 0)
      -- EQUIPMENT_CHANGED: eigener Typ wechselt
      F.SetType(403, false)
      H.eq(idsOf((F.Compute(4))), "2001,2002,2004,2005,2008,2007")
      mock.world.equipment[5] = 1005
      T.State.RefreshEquipment()
      H.eq(idsOf((F.Compute(4))), "2001,2003,2002,2004,2005,2008,2007")   -- 2003 (Kette) = own
   end)

   H.test("Cache: LOCALE_CHANGED und Filter.Invalidate verwerfen Ergebnisse", function()
      local T = chestBoot()
      local F = T.Filter
      local before = F.Compute(4)
      T.Events.Fire("LOCALE_CHANGED")
      local after = F.Compute(4)
      H.neq(before[1], after[1], "neu berechnet (neue Eintragstabellen)")
      H.eq(idsOf(before), idsOf(after))
      F.Invalidate()
      local again = F.Compute(4)
      H.neq(after[1], again[1])
      H.eq(idsOf(after), idsOf(again))
   end)

   H.test("Cache: nicht aufgeloeste Items werden gedrosselt erneut angemeldet", function()
      local d = baseItems()
      local T = boot({ items = d, equip = { [5] = 1004 } })
      feed(T, 4, { 2001, 9001, 9002 })      -- 9001/9002 gibt es nirgends
      local F = T.Filter
      local requests = 0
      local orig = T.Items.RequestMany
      T.Items.RequestMany = function(list)
         requests = requests + 1
         return orig(list)
      end
      local entries, stats = F.Compute(4)
      H.eq(idsOf(entries), "2001")
      H.eq(stats.unresolved, 2)
      H.eq(requests, 1)
      F.Compute(4)
      H.eq(requests, 1, "Cache-Treffer innerhalb der Drosselung")
      mock.Advance(6)
      F.Compute(4)
      H.truthy(requests >= 2, "nach einigen Sekunden erneut angemeldet")
      T.Items.RequestMany = orig
   end)

   H.test("Cache: gleichzeitige Aufloesung ohne Ereignis wird bemerkt (Selbstheilung)", function()
      local d = baseItems()
      local T = boot({ items = d, equip = { [5] = 1004 }, cache = false })
      local F = T.Filter
      feed(T, 4, { 2001, 2003 })
      local _, stats = F.Compute(4)
      H.eq(stats.unresolved, 2)
      -- Der Client liefert die Daten, ohne dass die Poll-Frames laufen
      mock.CacheItem(2001)
      mock.CacheItem(2003)
      mock.Advance(0.5)     -- das ITEMS_RESOLVED-Ereignis wird zusaetzlich gefeuert; Ergebnis stimmt in jedem Fall
      local entries
      entries, stats = F.Compute(4)
      H.eq(stats.unresolved, 0)
      H.eq(idsOf(entries), "2001,2003")
   end)

   H.test("Cache: jedes dokumentierte Ereignis verwirft die gecachten Ergebnisse", function()
      local T = chestBoot()
      local F = T.Filter
      for _, name in ipairs({ "FILTER_CHANGED", "LIST_READY", "ITEMS_RESOLVED", "FAVORITES_CHANGED",
                              "WANTED_CHANGED", "STATUS_CHANGED", "EQUIPMENT_CHANGED",
                              "COLLECTION_UPDATED", "LOCALE_CHANGED" }) do
         local before = F.Compute(4)
         local again = F.Compute(4)
         H.eq(before[1], again[1], name .. ": vor dem Ereignis Cache-Treffer")
         T.Events.Fire(name, 4)
         local after = F.Compute(4)
         H.neq(before[1], after[1], name .. ": nach dem Ereignis neu berechnet")
         H.eq(idsOf(before), idsOf(after), name .. ": gleicher Inhalt")
      end
   end)

   H.test("Cache: ITEMS_RESOLVED wirkt sofort, ohne die Selbstheilung abzuwarten", function()
      local T = boot({ items = baseItems(), equip = { [5] = 1004 }, cache = false })
      local F = T.Filter
      feed(T, 4, { 2001, 2003 })
      local _, stats = F.Compute(4)
      H.eq(stats.unresolved, 2)
      mock.CacheItem(2001)
      mock.CacheItem(2003)
      -- ein Poll-Takt von Items (feuert ITEMS_RESOLVED) ist kuerzer als die Heilungsdrosselung
      mock.Advance(0.05)
      local entries
      entries, stats = F.Compute(4)
      H.eq(stats.unresolved, 0)
      H.eq(idsOf(entries), "2001,2003")
   end)

   H.test("Cache: Aufloesung ohne Ereignis wird nach kurzer Zeit bemerkt (Selbstheilung)", function()
      local T = chestBoot()
      local F = T.Filter
      feed(T, 4, { 2001, 9001 })
      local entries, stats = F.Compute(4)
      H.eq(stats.unresolved, 1)
      H.eq(#F.Types(4), 1)
      -- 9001 wird ohne ITEMS_RESOLVED aufloesbar
      local orig = T.Items.Info
      T.Items.Info = function(id)
         if id == 9001 then
            return { id = 9001, name = "Late One", quality = 3, ilvl = 10, minLevel = 0,
                     typeName = "Armor", subtypeName = "Mail", typeKey = 403,
                     equipLoc = "INVTYPE_CHEST", icon = "Interface\\Icons\\Late", link = "item:9001" }
         end
         return orig(id)
      end
      mock.Advance(0.3)
      entries, stats = F.Compute(4)
      H.eq(stats.unresolved, 0)
      H.eq(idsOf(entries), "2001,9001")
      H.eq(#F.Types(4), 2)
      H.eq(#F.Qualities(4), 2)
      T.Items.Info = orig
   end)

   H.test("Cache: Signatur erkennt Aenderungen auch ohne Bus-Ereignisse", function()
      local T = chestBoot()
      local F = T.Filter
      -- Filter hoert nicht mehr auf den Bus: nur die Signatur bleibt
      for _, name in ipairs({ "FILTER_CHANGED", "LIST_READY", "ITEMS_RESOLVED", "FAVORITES_CHANGED",
                              "WANTED_CHANGED", "STATUS_CHANGED", "EQUIPMENT_CHANGED",
                              "COLLECTION_UPDATED", "LOCALE_CHANGED" }) do
         T.Events.Off(name, F)
      end
      local f = T.DB.char.filter
      local function now() return idsOf((F.Compute(4))) end
      H.eq(now(), "2001,2003,2002,2004,2005,2008,2007")
      -- gespeicherter Filterzustand
      f.sort = "NAME"
      H.eq(now(), "2004,2005,2003,2001,2002,2007,2008")
      f.sort = "ILEVEL"
      H.eq(now(), "2001,2002,2003,2004,2005,2008,2007")
      f.sort = "QUALITY"
      f.hideDuplicates = false
      H.eq(#F.Compute(4), 8)
      f.hideDuplicates = true
      f.qualities[0] = false
      H.eq(now(), "2001,2003,2002,2004,2005,2008")
      f.qualities[0] = nil
      f.typesOff[401] = true
      H.eq(now(), "2001,2003,2002,2005,2008")
      f.typesOff[401] = nil
      F.search = "rag"
      H.eq(now(), "2007")
      F.search = ""
      f.favoritesOnly = true
      H.eq(now(), "")
      T.DB.char.favorites[2005] = true
      H.eq(now(), "2005")
      f.favoritesOnly = false
      f.newOnly = true
      H.eq(now(), "")
      T.Net.Handle("CollectionUpdated:2004")
      H.eq(now(), "2004")
      f.newOnly = false
      H.eq(#F.Compute(4), 7)
      -- State: Auswahl, Status
      H.truthy(T.State.Select(4, 2002))
      H.eq(entryOf((F.Compute(4)), 2002).wanted, true)
      T.State.Discard(4)
      H.eq(entryOf((F.Compute(4)), 2002).wanted, false)
      T.Net.Handle("TransmogStatus:1:4,2003")
      H.eq(entryOf((F.Compute(4)), 2003).applied, true)
      T.Net.Handle("TransmogStatus:0")
      H.eq(entryOf((F.Compute(4)), 2003).applied, false)
      -- Liste
      feed(T, 4, { 2001, 2007 })
      H.eq(now(), "2001,2007")
      feed(T, 4, CHEST_LIST)
      -- Ausruestung: eigener Typ wechselt (Kette ausgeblendet, aber nun angelegt)
      f.typesOff[403] = true
      H.eq(now(), "2001,2002,2004,2005,2008,2007")
      mock.world.equipment[5] = 1005
      T.State.RefreshEquipment()
      H.eq(now(), "2001,2003,2002,2004,2005,2008,2007")
   end)

   H.test("Ableitungen: Zaehler waechst nur bis zur Obergrenze, dann Neuaufbau", function()
      local T = chestBoot()
      local F = T.Filter
      H.eq(F.CacheSize(), 0)
      feed(T, 4, { 2001, 2002 })
      F.Compute(4)
      H.eq(F.CacheSize(), 2)
      feed(T, 4, { 2003 })
      F.Compute(4)
      H.eq(F.CacheSize(), 3, "Vereinigung bleibt unterhalb der Grenze")
      F.DERIVED_LIMIT = 3
      feed(T, 4, { 2004 })
      F.Compute(4)
      H.eq(F.CacheSize(), 4, "Grenze wird erst bei der naechsten Berechnung durchgesetzt")
      feed(T, 4, { 2005 })
      F.Compute(4)
      H.eq(F.CacheSize(), 1, "ueber der Grenze: verworfen und nur das Noetige neu aufgebaut")
      H.eq(idsOf((F.Compute(4))), "2005")
   end)

   H.test("Ableitungen sind begrenzt (DERIVED_LIMIT); Ergebnisse bleiben richtig", function()
      local T = chestBoot()
      local F = T.Filter
      local terms = { "", "plate", "mail", "chest", "robe", "", "alpha", "beta copy", "armor", "rag" }
      local expected = {}
      for i, term in ipairs(terms) do
         F.SetSearch(term)
         expected[i] = idsOf((F.Compute(4)))
      end
      F.DERIVED_LIMIT = 3
      for round = 1, 3 do
         for i, term in ipairs(terms) do
            F.SetSearch(term)
            F.Invalidate()
            H.eq(idsOf((F.Compute(4))), expected[i], "Durchgang " .. round .. " '" .. term .. "'")
         end
      end
      F.SetSort("NAME")
      F.SetSearch("")
      H.eq(idsOf((F.Compute(4))), "2004,2005,2003,2001,2002,2007,2008")
   end)

   -- -------------------------------------------------------------------------
   H.section("Persistenz und Zustand")
   -- -------------------------------------------------------------------------

   H.test("Zustand liegt in DB.char.filter und ueberlebt Neustart (SavedVariables)", function()
      local T = chestBoot()
      local F = T.Filter
      H.eq(F.state, T.DB.char.filter)
      F.SetQuality(0, false)
      F.SetType(401, false)
      F.SetSort("NAME")
      F.SetHideDuplicates(false)
      F.SetFavoritesOnly(true)
      F.SetNewOnly(true)
      local saved = T.Util.CopyTable(T.DB.char)
      H.eq(saved.filter.qualities[0], false)
      H.eq(saved.filter.typesOff[401], true)
      H.eq(saved.filter.sort, "NAME")
      H.eq(saved.filter.hideDuplicates, false)
      H.eq(saved.filter.favoritesOnly, true)
      H.eq(saved.filter.newOnly, true)
      H.eq(saved.filter.search, nil, "Suchtext wird nicht gespeichert")

      -- "Neustart": gleiche Daten als SavedVariables in einer frischen Umgebung
      local d = baseItems()
      local T2 = boot({ items = d, equip = { [5] = 1004 }, globals = { TransmogDB = saved } })
      local F2 = T2.Filter
      H.eq(F2.state.qualities[0], false)
      H.eq(F2.state.typesOff[401], true)
      H.eq(F2.state.sort, "NAME")
      H.eq(F2.state.hideDuplicates, false)
      H.eq(F2.state.favoritesOnly, true)
      H.truthy(F2.IsActive())
      H.eq(F2.search, "")
      F2.Reset()
      H.falsy(F2.IsActive())
      H.eq(F2.state.sort, "NAME")
   end)

   H.test("Filter ohne DB.Init: kein Fehler, Notfallzustand", function()
      local T = H.boot({ upTo = "Core\\Outfits.lua", login = false, items = baseItems() })
      -- DB.char existiert noch nicht
      local F = T.Filter
      H.eq(type(F.state), "table")
      F.SetQuality(2, false)
      F.SetSearch("x")
      H.truthy(F.IsActive())
      F.Reset()
      H.falsy(F.IsActive())
      H.eq(#F.Compute(4), 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Beschriftungen: QualityLabel, SortLabel", function()
      local T = chestBoot()
      local F = T.Filter
      H.eq(F.QualityLabel(0), "Poor")
      H.eq(F.QualityLabel(4), "Epic")
      H.eq(F.QualityLabel(7), "Heirloom")
      H.eq(F.QualityLabel(99), "Common")        -- ungueltig -> Qualitaet 1
      H.eq(F.SortLabel("QUALITY"), "Quality")
      H.eq(F.SortLabel("NAME"), "Name")
      H.eq(F.SortLabel("ILEVEL"), "Item level")
      H.eq(F.SortLabel("XYZ"), "XYZ")
   end)

   -- -------------------------------------------------------------------------
   H.section("Referenzmodell (Zufallskonfigurationen)")
   -- -------------------------------------------------------------------------

   -- Unabhaengige Nachbildung der Filterregeln aus der SPEC; verglichen wird
   -- das Ergebnis des Moduls fuer viele Zufallskonfigurationen.
   H.test("Zufallskonfigurationen stimmen mit dem Referenzmodell ueberein", function()
      local rnd = newRng(2024)
      local N = 70
      local d = baseItems()
      local TYPES = {
         { "Plate", 404 }, { "Mail", 403 }, { "Leather", 402 }, { "Cloth", 401 },
      }
      local NAMES = { "Alpha", "Beta", "Gamma", "Delta", "Shadow", "Flame", "Frost", "Ancient" }
      local ICONS = 14
      local meta = {}
      local list, unresolved = {}, {}
      for i = 1, N do
         local id = 5000 + i
         local ty = TYPES[1 + rnd(#TYPES)]
         local name = NAMES[1 + rnd(#NAMES)] .. " " .. NAMES[1 + rnd(#NAMES)]
         local loc = (rnd(4) == 0) and "INVTYPE_ROBE" or "INVTYPE_CHEST"
         local icon = "R" .. rnd(ICONS)
         local m = { id = id, name = name, q = rnd(6), il = 10 * (1 + rnd(4)), sub = ty[1], tk = ty[2],
                     loc = loc, icon = "interface\\icons\\" .. string.lower(icon) }
         if i % 7 == 0 then
            m.unresolved = true
            unresolved[#unresolved + 1] = id
         else
            put(d, id, name, m.q, m.il, "Armor", ty[1], loc, icon)
         end
         meta[id] = m
         list[i] = id
      end
      local T = boot({ items = d, equip = { [5] = 1004 } })
      local F = T.Filter
      feed(T, 4, list)

      -- feste "Neu"-Menge
      local newSet = {}
      for _ = 1, 12 do
         local id = list[1 + rnd(N)]
         newSet[id] = true
         T.Net.Handle("CollectionUpdated:" .. id)
      end
      H.eq(T.State.new[next(newSet)], true)

      local function referenceIds(cfg, favs, applied, wanted)
         local rows = {}
         local hidden, unres = 0, 0
         for _, id in ipairs(list) do
            local m = meta[id]
            if m.unresolved then
               unres = unres + 1
            else
               local show = true
               if cfg.qualOff[m.q] then show = false end
               if show and cfg.typesOff[m.tk] and m.tk ~= 404 then show = false end
               if show and cfg.favOnly and not favs[id] then show = false end
               if show and cfg.newOnly and not newSet[id] then show = false end
               if show and cfg.search ~= "" then
                  local hay = string.lower(m.name) .. " armor " .. string.lower(m.sub)
                  for term in string.gmatch(string.lower(cfg.search), "%S+") do
                     local ok
                     local digits = string.match(term, "^#(%d+)$")
                     if digits then
                        ok = tonumber(digits) == id
                     elseif string.find(hay, term, 1, true) then
                        ok = true
                     elseif string.match(term, "^%d+$") then
                        ok = tonumber(term) == id
                     end
                     if term == "#" then ok = true end
                     if not ok then show = false break end
                  end
               end
               if show then
                  rows[#rows + 1] = { id = id, q = m.q, il = m.il, name = string.lower(m.name),
                                      fav = favs[id] and true or false,
                                      applied = (id == applied), wanted = (id == wanted),
                                      key = m.icon .. "|" .. m.tk .. "|" .. m.loc }
               else
                  hidden = hidden + 1
               end
            end
         end
         local dupHidden = 0
         if cfg.hideDup then
            local best = {}
            for _, r in ipairs(rows) do
               local cur = best[r.key]
               local better = false
               if cur == nil then
                  better = true
               elseif r.wanted ~= cur.wanted then better = r.wanted
               elseif r.applied ~= cur.applied then better = r.applied
               elseif r.fav ~= cur.fav then better = r.fav
               elseif r.q ~= cur.q then better = r.q > cur.q
               else better = r.id < cur.id end
               if better then best[r.key] = r end
            end
            local kept = {}
            for _, r in ipairs(rows) do
               if best[r.key] == r then kept[#kept + 1] = r end
            end
            dupHidden = #rows - #kept
            rows = kept
         end
         table.sort(rows, function(a, b)
            if cfg.sort == "QUALITY" then
               if a.q ~= b.q then return a.q > b.q end
               if a.name ~= b.name then return a.name < b.name end
            elseif cfg.sort == "NAME" then
               if a.name ~= b.name then return a.name < b.name end
            else
               if a.il ~= b.il then return a.il > b.il end
               if a.q ~= b.q then return a.q > b.q end
               if a.name ~= b.name then return a.name < b.name end
            end
            return a.id < b.id
         end)
         local out = {}
         for i, r in ipairs(rows) do out[i] = r.id end
         return table.concat(out, ","), { shown = #rows, hiddenByFilter = hidden,
                                          hiddenDuplicates = dupHidden, unresolved = unres }
      end

      local SEARCHES = { "", "", "", "alpha", "frost shadow", "plate", "cloth", "armor beta",
                         "#5003", "5010", "#5014 alpha", "zzz", "a", "ancient flame", "mail leather" }
      local SORTS = { "QUALITY", "NAME", "ILEVEL" }
      for round = 1, 160 do
         F.Reset()
         local cfg = { qualOff = {}, typesOff = {}, hideDup = rnd(4) ~= 0,
                       favOnly = rnd(5) == 0, newOnly = rnd(6) == 0,
                       sort = SORTS[1 + rnd(3)], search = SEARCHES[1 + rnd(#SEARCHES)] }
         for q = 0, 5 do
            if rnd(5) == 0 then
               cfg.qualOff[q] = true
               F.SetQuality(q, false)
            end
         end
         for _, ty in ipairs(TYPES) do
            if rnd(4) == 0 then
               cfg.typesOff[ty[2]] = true
               F.SetType(ty[2], false)
            end
         end
         F.SetHideDuplicates(cfg.hideDup)
         F.SetFavoritesOnly(cfg.favOnly)
         F.SetNewOnly(cfg.newOnly)
         F.SetSort(cfg.sort)
         F.SetSearch(cfg.search)

         -- Favoriten, angewendet, ausgewaehlt
         local favs = {}
         T.DB.char.favorites = {}
         for _ = 1, 8 do
            local id = list[1 + rnd(N)]
            favs[id] = true
            T.DB.char.favorites[id] = true
         end
         T.Events.Fire("FAVORITES_CHANGED")
         local applied, wanted = 0, 0
         T.State.DiscardAll()
         T.Net.Handle("TransmogStatus:0")
         if rnd(2) == 0 then
            applied = list[1 + rnd(N)]
            T.Net.Handle("TransmogStatus:1:4," .. applied)
            wanted = applied
         end
         if rnd(2) == 0 then
            local id = list[1 + rnd(N)]
            if T.State.Select(4, id) then wanted = id end
         end
         if T.State.Wanted(4) ~= wanted then wanted = T.State.Wanted(4) end

         local expectIds, expectStats = referenceIds(cfg, favs, applied, wanted)
         local entries, stats = F.Compute(4)
         local label = string.format("Durchgang %d (%s, dup=%s, fav=%s, new=%s, '%s')", round, cfg.sort,
            tostring(cfg.hideDup), tostring(cfg.favOnly), tostring(cfg.newOnly), cfg.search)
         H.eq(idsOf(entries), expectIds, label)
         H.eq(stats.shown, expectStats.shown, label .. " shown")
         H.eq(stats.hiddenByFilter, expectStats.hiddenByFilter, label .. " hiddenByFilter")
         H.eq(stats.hiddenDuplicates, expectStats.hiddenDuplicates, label .. " hiddenDuplicates")
         H.eq(stats.unresolved, expectStats.unresolved, label .. " unresolved")
         H.eq(stats.total, N, label .. " total")
         -- Flags
         for _, e in ipairs(entries) do
            if e.favorite ~= (favs[e.id] and true or false) then H.fail("favorite " .. e.id .. " " .. label) end
            if e.isNew ~= (newSet[e.id] and true or false) then H.fail("isNew " .. e.id .. " " .. label) end
            if e.wanted ~= (e.id == wanted) then H.fail("wanted " .. e.id .. " " .. label) end
         end
      end
      H.deepEq(H.takeErrors(), {})
   end)

   -- Zufallsfolgen ueber ALLE Eingaben (Listen, Status, Auswahl, Ausruestung,
   -- Filter, Favoriten, Items): nach jedem Schritt muss das gecachte Ergebnis dem
   -- Referenzmodell entsprechen, das nur die oeffentlichen Getter liest.
   H.test("Zufallsfolgen: gecachte Ergebnisse stimmen nach jedem Schritt mit dem Referenzmodell", function()
      local rnd = newRng(31337)
      local d = baseItems()
      local SUBS = { { "Plate", 404 }, { "Mail", 403 }, { "Leather", 402 }, { "Cloth", 401 } }
      local W1 = { "Alpha", "Beta", "Gamma", "Delta", "Omega" }
      local W2 = { "Helm", "Cowl", "Crown", "Hood" }
      local pools = { [0] = {}, [4] = {} }
      local LOC = { [0] = "INVTYPE_HEAD", [4] = "INVTYPE_CHEST" }
      local undefined = {}
      for _, slot in ipairs({ 0, 4 }) do
         for i = 1, 24 do
            local id = 6000 + slot * 100 + i
            pools[slot][i] = id
            if i % 8 == 0 then
               undefined[id] = true                   -- nie bekannt
            else
               local sub = SUBS[1 + rnd(4)]
               put(d, id, W1[1 + rnd(5)] .. " " .. W2[1 + rnd(4)], rnd(6), 10 * (1 + rnd(4)),
                  "Armor", sub[1], LOC[slot], "F" .. slot .. "_" .. rnd(7))
            end
         end
      end
      local T = boot({ items = d, equip = { [1] = 1001, [5] = 1004 }, cache = false })
      local F = T.Filter
      local State, DB = T.State, T.DB

      local function lower(s) return string.lower(s) end

      -- Referenz aus den oeffentlichen Gettern
      local function reference(slot)
         local list = State.List(slot)
         local eq = State.Equipped(slot)
         local own = eq and eq.typeKey or nil
         local wanted, base = State.Wanted(slot), State.Baseline(slot)
         local f = DB.char.filter
         local terms = {}
         for term in string.gmatch(lower(F.search), "%S+") do
            if term ~= "#" then terms[#terms + 1] = term end
         end
         local rows, hidden, unres, seen = {}, 0, 0, {}
         for _, id in ipairs(list.ids) do
            if not seen[id] then
               seen[id] = true
               local info = T.Items.Info(id)
               if not info then
                  unres = unres + 1
               else
                  local show = true
                  if f.qualities[info.quality] == false then show = false end
                  if show and info.typeKey and f.typesOff[info.typeKey] and info.typeKey ~= own then show = false end
                  if show and f.favoritesOnly and not DB.char.favorites[id] then show = false end
                  if show and f.newOnly and not State.new[id] then show = false end
                  if show then
                     local hay = lower(info.name)
                     local ty = lower(info.typeName .. " " .. info.subtypeName)
                     for _, term in ipairs(terms) do
                        local digits = string.match(term, "^#(%d+)$")
                        local ok = false
                        if digits then
                           ok = tonumber(digits) == id
                        else
                           ok = string.find(hay, term, 1, true) ~= nil or string.find(ty, term, 1, true) ~= nil
                           if not ok and string.match(term, "^%d+$") then ok = tonumber(term) == id end
                        end
                        if not ok then show = false break end
                     end
                  end
                  if show then
                     local key
                     if info.icon == "" or lower(info.icon) == "interface\\icons\\inv_misc_questionmark" then
                        key = "id:" .. id
                     else
                        key = lower(info.icon) .. "|" .. tostring(info.typeKey or info.subtypeName)
                           .. "|" .. tostring(info.equipLoc)
                     end
                     rows[#rows + 1] = { id = id, q = info.quality, il = info.ilvl, name = lower(info.name),
                        fav = DB.char.favorites[id] and true or false, applied = (id == base),
                        wanted = (id == wanted), key = key }
                  else
                     hidden = hidden + 1
                  end
               end
            end
         end
         local dup = 0
         if f.hideDuplicates ~= false then
            local best = {}
            for _, r in ipairs(rows) do
               local c = best[r.key]
               local better
               if c == nil then better = true
               elseif r.wanted ~= c.wanted then better = r.wanted
               elseif r.applied ~= c.applied then better = r.applied
               elseif r.fav ~= c.fav then better = r.fav
               elseif r.q ~= c.q then better = r.q > c.q
               else better = r.id < c.id end
               if better then best[r.key] = r end
            end
            local kept = {}
            for _, r in ipairs(rows) do
               if best[r.key] == r then kept[#kept + 1] = r end
            end
            dup = #rows - #kept
            rows = kept
         end
         local sortKey = f.sort
         table.sort(rows, function(a, b)
            if sortKey == "NAME" then
               if a.name ~= b.name then return a.name < b.name end
            elseif sortKey == "ILEVEL" then
               if a.il ~= b.il then return a.il > b.il end
               if a.q ~= b.q then return a.q > b.q end
               if a.name ~= b.name then return a.name < b.name end
            else
               if a.q ~= b.q then return a.q > b.q end
               if a.name ~= b.name then return a.name < b.name end
            end
            return a.id < b.id
         end)
         local out = {}
         for i, r in ipairs(rows) do out[i] = r.id end
         return table.concat(out, ","), #rows, hidden, dup, unres
      end

      local SEARCH = { "", "", "", "alpha", "helm", "plate", "armor", "beta crown", "omega", "#6103",
                       "6204", "zzz", "o", "mail cowl", "gamma hood" }
      local SORTS = { "QUALITY", "NAME", "ILEVEL" }
      local log = {}
      local function check(step)
         for _, slot in ipairs({ 0, 4 }) do
            local entries, stats = F.Compute(slot)
            local ids, shown, hidden, dup, unres = reference(slot)
            local got = idsOf(entries)
            if got ~= ids or stats.shown ~= shown or stats.hiddenByFilter ~= hidden
               or stats.hiddenDuplicates ~= dup or stats.unresolved ~= unres
               or stats.total ~= #State.List(slot).ids then
               H.fail(string.format("Schritt %d (%s) Slot %d:\n   erwartet %s [%d/%d/%d/%d]\n   erhalten %s [%d/%d/%d/%d]",
                  step, log[#log] or "?", slot, ids, shown, hidden, dup, unres,
                  got, stats.shown, stats.hiddenByFilter, stats.hiddenDuplicates, stats.unresolved))
               return false
            end
            -- Flags der Eintraege muessen dem aktuellen Zustand entsprechen
            local wantedId, baseId = State.Wanted(slot), State.Baseline(slot)
            for _, e in ipairs(entries) do
               if e.wanted ~= (e.id == wantedId) or e.applied ~= (e.id == baseId)
                  or e.favorite ~= (DB.char.favorites[e.id] and true or false)
                  or e.isNew ~= (State.new[e.id] and true or false) then
                  H.fail(string.format("Schritt %d (%s) Slot %d: veraltete Flags bei %d", step,
                     log[#log] or "?", slot, e.id))
                  return false
               end
            end
         end
         return true
      end

      local chestChoice = { 1004, 1005 }
      local chestIdx = 1
      local headOn = true
      for step = 1, 450 do
         local op = rnd(17)
         local slot = (rnd(2) == 0) and 0 or 4
         if op == 0 or op == 1 then
            -- Liste einspielen (Teilmenge in zufaelliger Reihenfolge, evtl. unfertig)
            local list = {}
            for _, id in ipairs(pools[slot]) do
               if rnd(4) ~= 0 then list[#list + 1] = id end
            end
            for i = #list, 2, -1 do
               local j = 1 + rnd(i)
               list[i], list[j] = list[j], list[i]
            end
            feed(T, slot, list, { noEnd = rnd(6) == 0 })
            log[#log + 1] = "Liste " .. slot
         elseif op == 2 then
            local id = pools[slot][1 + rnd(24)]
            if rnd(4) == 0 then id = 0 end
            if id == 0 then
               T.Net.Handle("TransmogStatus:0")
            else
               T.Net.Handle("TransmogStatus:1:" .. slot .. "," .. id)
            end
            log[#log + 1] = "Status " .. slot .. "=" .. id
         elseif op == 3 then
            local id = pools[slot][1 + rnd(24)]
            if rnd(5) == 0 then id = 0 elseif rnd(8) == 0 then id = HIDDEN end
            State.Select(slot, id)
            log[#log + 1] = "Select " .. slot .. "=" .. id
         elseif op == 4 then
            local which = rnd(3)
            if which == 0 then State.Discard(slot) elseif which == 1 then State.DiscardAll() else State.Toggle(slot) end
            log[#log + 1] = "Discard/Toggle"
         elseif op == 5 then
            F.SetSearch(SEARCH[1 + rnd(#SEARCH)])
            log[#log + 1] = "Suche '" .. F.search .. "'"
         elseif op == 6 then
            F.SetQuality(rnd(6), rnd(2) == 0)
            log[#log + 1] = "Qualitaet"
         elseif op == 7 then
            F.SetType(401 + rnd(4), rnd(2) == 0)
            log[#log + 1] = "Typ"
         elseif op == 8 then
            F.SetSort(SORTS[1 + rnd(3)])
            log[#log + 1] = "Sort"
         elseif op == 9 then
            local which = rnd(3)
            if which == 0 then F.SetHideDuplicates(rnd(2) == 0)
            elseif which == 1 then F.SetFavoritesOnly(rnd(3) == 0)
            else F.SetNewOnly(rnd(3) == 0) end
            log[#log + 1] = "Schalter"
         elseif op == 10 then
            if rnd(3) == 0 then F.Reset() end
            log[#log + 1] = "Reset"
         elseif op == 11 then
            local id = pools[slot][1 + rnd(24)]
            if DB.char.favorites[id] then DB.char.favorites[id] = nil else DB.char.favorites[id] = true end
            T.Events.Fire("FAVORITES_CHANGED")
            log[#log + 1] = "Favorit " .. id
         elseif op == 12 then
            T.Net.Handle("CollectionUpdated:" .. pools[slot][1 + rnd(24)])
            log[#log + 1] = "CollectionUpdated"
         elseif op == 13 or op == 14 then
            -- ein paar Gegenstaende erreichen den Client-Cache
            for _ = 1, 1 + rnd(5) do
               local id = pools[slot][1 + rnd(24)]
               if not undefined[id] then mock.CacheItem(id) end
            end
            mock.Advance(0.3)
            log[#log + 1] = "Items"
         elseif op == 15 then
            chestIdx = 3 - chestIdx
            mock.world.equipment[5] = chestChoice[chestIdx]
            State.RefreshEquipment()
            log[#log + 1] = "Brust " .. chestChoice[chestIdx]
         elseif op == 16 then
            headOn = not headOn
            mock.world.equipment[1] = headOn and 1001 or nil
            State.RefreshEquipment()
            log[#log + 1] = "Kopf " .. tostring(headOn)
         end
         if not check(step) then return end
      end
      H.deepEq(H.takeErrors(), {})
   end)

   -- -------------------------------------------------------------------------
   H.section("Leistung")
   -- -------------------------------------------------------------------------

   H.test("3000 Eintraege: Compute/Types/Qualities unter 1 s, Cache-Treffer billig", function()
      local N = 3000
      local rnd = newRng(4711)
      local d = baseItems()
      local list = {}
      for i = 1, N do
         local id = 20000 + i
         local sub = ({ "Plate", "Mail", "Leather", "Cloth" })[1 + rnd(4)]
         put(d, id, "Name " .. rnd(60), rnd(6), 100 + 5 * rnd(8), "Armor", sub,
            "INVTYPE_CHEST", "I" .. rnd(900))      -- viele Duplikate
         list[i] = id
      end
      local T = boot({ items = d, equip = { [5] = 1004 } })
      local F = T.Filter
      local t0 = os.clock()
      feed(T, 4, list)
      local feedTime = os.clock() - t0

      for _, key in ipairs({ "QUALITY", "NAME", "ILEVEL" }) do
         F.SetSort(key)
         t0 = os.clock()
         local entries, stats = F.Compute(4)
         local dt = os.clock() - t0
         H.truthy(dt < 1, key .. " Compute dauerte " .. dt .. " s")
         H.truthy(#entries > 0 and #entries < N)
         H.eq(stats.total, N)
         H.eq(stats.shown + stats.hiddenDuplicates, N)
      end
      -- ohne Duplikatfilter: alle 3000
      F.SetHideDuplicates(false)
      t0 = os.clock()
      local entries, stats = F.Compute(4)
      H.truthy(os.clock() - t0 < 1)
      H.eq(#entries, N)
      -- Suche
      F.SetSearch("name 17")
      t0 = os.clock()
      entries = F.Compute(4)
      H.truthy(os.clock() - t0 < 1)
      H.truthy(#entries > 0 and #entries < N)
      for _, e in ipairs(entries) do H.eq(string.lower(e.info.name), "name 17") end
      F.SetSearch("")
      -- Cache-Treffer
      t0 = os.clock()
      for _ = 1, 50 do F.Compute(4) end
      H.truthy(os.clock() - t0 < 1, "50 Cache-Treffer")
      -- Facetten
      t0 = os.clock()
      H.eq(#F.Types(4), 4)
      H.truthy(#F.Qualities(4) > 0)
      H.truthy(os.clock() - t0 < 1)
      H.truthy(feedTime < 5)
   end)

   H.test("3000 nicht aufgeloeste Items: Compute bleibt schnell, Anmeldung gedrosselt", function()
      local N = 3000
      local list = {}
      for i = 1, N do list[i] = 30000 + i end     -- keiner davon ist bekannt
      local T = boot({ items = baseItems(), equip = { [5] = 1004 } })
      local F = T.Filter
      feed(T, 4, list)
      local t0 = os.clock()
      local entries, stats = F.Compute(4)
      local dt = os.clock() - t0
      H.truthy(dt < 1, "Compute dauerte " .. dt .. " s")
      H.eq(#entries, 0)
      H.eq(stats.unresolved, N)
      H.eq(stats.total, N)
      t0 = os.clock()
      for _ = 1, 20 do F.Compute(4) end
      H.truthy(os.clock() - t0 < 1)
      -- Items arbeitet gedrosselt ab (nie mehr als 25 Anfragen je Takt)
      mock.Advance(0.2)
      H.truthy(T.Items.PendingCount() > 0)
      H.deepEq(H.takeErrors(), {})
   end)
end
