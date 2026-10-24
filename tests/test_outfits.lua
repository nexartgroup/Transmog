-- tests/test_outfits.lua
-- ---------------------------------------------------------------------------
-- Tests fuer Core\Outfits.lua: Namenspruefung, Speichern/Ueberschreiben/
-- Loeschen/Umbenennen, Laden gegen den ECHTEN State, CurrentLook und die
-- Persistenz ueber DB.char.
--
-- Die Tests laufen gegen die echten Module (Locale, Util, Events, DB, Slots,
-- Items, Net, State) auf der WoW-Attrappe; der Server wird ueber Net.Handle im
-- echten Protokollformat gespielt. Boot.lua wird nicht geladen, die Init()-
-- Funktionen werden in der Reihenfolge der SPEC (3) selbst gerufen.
--
-- Aufruf (im Hauptverzeichnis):  luajit tests/run.lua outfits
-- ---------------------------------------------------------------------------

return function(H)
   local mock = H.mock
   local HIDDEN = 999999

   -- -------------------------------------------------------------------------
   -- Hilfen
   -- -------------------------------------------------------------------------

   local function put(defs, id, name, quality, ilvl, class, sub, loc, icon)
      defs[id] = {
         name = name, quality = quality, ilvl = ilvl, class = class, subclass = sub,
         equipLoc = loc,
         icon = icon and ("Interface\\Icons\\" .. icon) or nil,
      }
   end

   -- "0,4,15" aus einem Array von Zahlen
   local function join(t)
      local out = {}
      for i = 1, #t do out[i] = tostring(t[i]) end
      return table.concat(out, ",")
   end

   -- Zaehler fuer Bus-Ereignisse
   local function counter(T, names)
      local c = {}
      for _, name in ipairs(names) do
         T.Events.On(name, function() c[name] = (c[name] or 0) + 1 end, c)
      end
      return c
   end

   -- Namen aller Outfits (Speicherreihenfolge)
   local function names(T)
      local out = {}
      for i, o in ipairs(T.Outfits.List()) do out[i] = o.name end
      return table.concat(out, "|")
   end

   -- Gegenstaende der Welt
   local function items()
      local d = {}
      put(d, 1001, "Helm of Plate", 4, 200, "Armor", "Plate", "INVTYPE_HEAD", "HeadP")
      put(d, 1004, "Chest of Plate", 4, 200, "Armor", "Plate", "INVTYPE_CHEST", "ChestP")
      put(d, 1015, "Sword of Doom", 4, 200, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "SwordD")
      put(d, 1900, "Libram of Doom", 4, 200, "Armor", "Librams", "INVTYPE_RELIC", "Libram")
      put(d, 1950, "Tabard of the Brave", 3, 1, "Armor", "Miscellaneous", "INVTYPE_TABARD", "Tabard")
      put(d, 2101, "Plate Helm Zeta", 3, 150, "Armor", "Plate", "INVTYPE_HEAD", "H1")
      put(d, 2102, "Plate Helm Eta", 2, 100, "Armor", "Plate", "INVTYPE_HEAD", "H2")
      put(d, 2001, "Plate Chest Alpha", 4, 200, "Armor", "Plate", "INVTYPE_CHEST", "A")
      put(d, 2002, "Plate Chest Beta", 3, 150, "Armor", "Plate", "INVTYPE_CHEST", "B")
      put(d, 2003, "Mail Chest Gamma", 3, 140, "Armor", "Mail", "INVTYPE_CHEST", "C")
      put(d, 2201, "Sword Alpha", 3, 100, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "S1")
      put(d, 2202, "Axe Beta", 3, 100, "Weapon", "Two-Handed Axes", "INVTYPE_2HWEAPON", "S2")
      put(d, 2301, "Tabard of Light", 2, 1, "Armor", "Miscellaneous", "INVTYPE_TABARD", "T1")
      return d
   end

   -- Angelegt: kopf(1), brust(5), haupthand(16), fernkampf(18) = Relikt (NEVER),
   -- wappenrock(19). Leer: schulter(3), ruecken(15), nebenhand(17).
   local EQUIP = { [1] = 1001, [5] = 1004, [16] = 1015, [18] = 1900, [19] = 1950 }

   local function boot(spec)
      spec = spec or {}
      local T = H.boot({
         upTo = "Core\\Outfits.lua", login = false,
         items = spec.items or items(), world = { equipment = spec.equip or EQUIP },
         globals = spec.globals,
      })
      T.DB.Init()
      T.Locale.Set("enUS")
      T.Slots.Init()
      T.Items.Init()
      T.Net.Init()
      T.State.Init()
      T.Outfits.Init()
      T.enteredWorldAt = GetTime() - 60
      mock.CacheAll()
      T.State.RefreshEquipment()
      return T
   end

   local function feed(T, slot, list, opts)
      opts = opts or {}
      local n = #list
      T.Net.Handle(string.format("AvailableTransmogs:%d:405:%d:start", slot, n))
      local i = 1
      while i <= n do
         local part = {}
         for j = i, math.min(i + 19, n) do part[#part + 1] = tostring(list[j]) end
         T.Net.Handle(string.format("AvailableTransmogs:%d:405:%d:%s", slot, n, table.concat(part, ":")))
         i = i + 20
      end
      if not opts.noEnd then
         T.Net.Handle(string.format("AvailableTransmogs:%d:405:%d:end", slot, n))
      end
   end

   -- Welt mit eingespielten Listen (Kopf, Brust, Haupthand, Wappenrock)
   local function worldBoot(spec)
      local T = boot(spec)
      feed(T, 0, { 2101, 2102 })
      feed(T, 4, { 2001, 2002, 2003 })
      feed(T, 15, { 2201, 2202 })
      feed(T, 18, { 2301 })
      return T
   end

   -- Beobachter fuer SetMany (Aufrufe und Karten)
   local function spyOnSetMany(T)
      local spy = { calls = 0, maps = {} }
      local orig = T.State.SetMany
      T.State.SetMany = function(map)
         spy.calls = spy.calls + 1
         local copy = {}
         for k, v in pairs(map) do copy[k] = v end
         spy.maps[#spy.maps + 1] = copy
         return orig(map)
      end
      return spy
   end

   -- Alle Schluessel einer Slot-Tabelle (aufsteigend) als "slot=id" Zeilen
   local function slotText(slots)
      local keys = {}
      for k in pairs(slots) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      local out = {}
      for i, k in ipairs(keys) do out[i] = tostring(k) .. "=" .. tostring(slots[k]) end
      return table.concat(out, ",")
   end

   -- -------------------------------------------------------------------------
   H.section("Namen")
   -- -------------------------------------------------------------------------

   H.test("API: Konstanten und Funktionen vorhanden", function()
      local T = boot()
      local O = T.Outfits
      H.eq(O.MAX, 50)
      for _, fn in ipairs({ "Init", "List", "Get", "Exists", "ValidateName", "CurrentLook", "Save",
                            "Overwrite", "Delete", "Rename", "Load" }) do
         H.eq(type(O[fn]), "function", fn)
      end
      H.deepEq(O.List(), {})
      H.eq(O.Exists("x"), false)
      H.eq(O.Get("x"), nil)
   end)

   H.test("ValidateName: leer, zu lang, vorhanden, gueltig (Reihenfolge)", function()
      local T = worldBoot()
      local O = T.Outfits
      local ok, err = O.ValidateName("Raid")
      H.eq(ok, true)
      H.eq(err, nil)
      -- leer
      for _, bad in ipairs({ "", "   ", "\t\n", "|", "|cffff0000|r", false }) do
         ok, err = O.ValidateName(bad)
         H.eq(ok, false, "leer: " .. tostring(bad))
         H.eq(err, "OUTFIT_ERR_EMPTY", "leer: " .. tostring(bad))
      end
      ok, err = O.ValidateName(nil)
      H.eq(err, "OUTFIT_ERR_EMPTY")
      ok, err = O.ValidateName({})
      H.eq(err, "OUTFIT_ERR_EMPTY")
      -- Laenge: 32 Zeichen sind erlaubt, 33 nicht
      ok, err = O.ValidateName(string.rep("a", 32))
      H.eq(ok, true)
      ok, err = O.ValidateName(string.rep("a", 33))
      H.eq(ok, false)
      H.eq(err, "OUTFIT_ERR_LONG")
      -- Mehrbytezeichen zaehlen als ein Zeichen
      ok, err = O.ValidateName(string.rep("\195\164", 32))
      H.eq(ok, true)
      ok, err = O.ValidateName(string.rep("\195\164", 33))
      H.eq(err, "OUTFIT_ERR_LONG")
      -- Leerraum am Rand zaehlt nicht
      ok = O.ValidateName("  " .. string.rep("a", 32) .. "  ")
      H.eq(ok, true)
      -- vorhanden
      H.truthy(O.Save("Raid Look", { [0] = 2101 }))
      ok, err = O.ValidateName("Raid Look")
      H.eq(ok, false)
      H.eq(err, "OUTFIT_ERR_EXISTS")
      ok, err = O.ValidateName("RAID look")
      H.eq(err, "OUTFIT_ERR_EXISTS")
      ok, err = O.ValidateName("  raid    LOOK ")
      H.eq(err, "OUTFIT_ERR_EXISTS")
      ok, err = O.ValidateName("Raid Look 2")
      H.eq(ok, true)
      -- Reihenfolge: leer vor lang vor vorhanden
      ok, err = O.ValidateName(string.rep(" ", 40))
      H.eq(err, "OUTFIT_ERR_EMPTY")
      ok, err = O.ValidateName(string.rep("b", 40))
      H.eq(err, "OUTFIT_ERR_LONG")
   end)

   H.test("Namen: Eindeutigkeit ohne Beachtung der Schreibweise (Umlaute, Kyrillisch)", function()
      local T = worldBoot()
      local O = T.Outfits
      H.truthy(O.Save("\195\132rmel Look", { [0] = 2101 }))        -- "Ärmel Look"
      H.eq(select(2, O.Save("\195\164rmel look", { [0] = 2102 })), "OUTFIT_ERR_EXISTS")
      H.eq(select(2, O.Save("\195\132RMEL LOOK", { [0] = 2102 })), "OUTFIT_ERR_EXISTS")
      H.eq(O.Exists("\195\164RMEL look"), true)
      H.truthy(O.Get("\195\164rmel look"))
      H.truthy(O.Save("\208\160\208\176\208\185\208\180", { [0] = 2101 }))           -- "Райд"
      H.eq(select(2, O.Save("\209\128\208\176\208\185\208\180", { [0] = 2101 })), "OUTFIT_ERR_EXISTS")  -- "райд"
      -- sz ist nicht SS
      H.truthy(O.Save("Gro\195\159", { [0] = 2101 }))
      H.truthy(O.Save("GROSS", { [0] = 2101 }))
      H.eq(O.Count(), 4)
   end)

   H.test("Namen: Bereinigung (Farbcodes, Steuerzeichen, Leerraum)", function()
      local T = worldBoot()
      local O = T.Outfits
      H.truthy(O.Save("  My    Look  ", { [0] = 2101 }))
      H.eq(O.List()[1].name, "My Look")
      H.truthy(O.Save("|cffff0000Red Look|r", { [0] = 2101 }))
      H.eq(O.List()[2].name, "Red Look")
      H.truthy(O.Save("Pipe|Look", { [0] = 2101 }))
      H.eq(O.List()[3].name, "PipeLook")
      H.truthy(O.Save("Tab\tLook\nTwo", { [0] = 2101 }))
      H.eq(O.List()[4].name, "Tab Look Two")
      H.truthy(O.Save("a \1 b", { [0] = 2101 }))            -- Steuerzeichen, kein doppelter Leerraum
      H.eq(O.List()[5].name, "a b")
      H.eq(O.NormalizeName("   "), "")
      H.eq(O.NormalizeName(nil), "")
      H.eq(O.NormalizeName(12), "12")
   end)

   H.test("SuggestName liefert einen unbenutzten Standardnamen", function()
      local T = worldBoot()
      local O = T.Outfits
      H.eq(O.SuggestName(), "Outfit 1")
      H.truthy(O.Save("Outfit 1", { [0] = 2101 }))
      H.eq(O.SuggestName(), "Outfit 2")
      H.truthy(O.Save("OUTFIT 3", { [0] = 2101 }))       -- #list + 1 = 3 ist belegt
      H.eq(O.SuggestName(), "Outfit 4")
      H.eq(O.Exists(O.SuggestName()), false)
   end)

   -- -------------------------------------------------------------------------
   H.section("Speichern, Ueberschreiben, Loeschen, Umbenennen")
   -- -------------------------------------------------------------------------

   H.test("Save: neues Outfit, Speicherort DB.char.outfits, Ereignis, Zeit", function()
      local T = worldBoot()
      local O = T.Outfits
      local c = counter(T, { "OUTFITS_CHANGED" })
      local t0 = time()
      local ok, err = O.Save("Raid", { [0] = 2101, [4] = 2001, [18] = HIDDEN })
      H.eq(ok, true)
      H.eq(err, nil)
      H.eq(c.OUTFITS_CHANGED, 1)
      H.eq(#T.DB.char.outfits, 1)
      local stored = T.DB.char.outfits[1]
      H.eq(stored.name, "Raid")
      H.eq(slotText(stored.slots), "0=2101,18=999999,4=2001")
      H.truthy(stored.time >= t0 and stored.time <= time())
      local list = O.List()
      H.eq(#list, 1)
      H.eq(list[1], stored, "List liefert Referenzen auf die gespeicherten Outfits")
      H.eq(list[1].count, 3)
      H.eq(O.Get("raid"), stored)
      H.eq(O.Exists("RAID"), true)
      H.eq(O.Count(), 1)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Save: ohne Teile = aktueller Look (Momentaufnahme, keine Referenz)", function()
      local T = worldBoot()
      local O = T.Outfits
      T.Net.Handle("TransmogStatus:1:4,2001")
      H.truthy(T.State.Select(0, 2101))
      local look = O.CurrentLook()
      H.eq(slotText(look), "0=2101,4=2001")
      H.truthy(O.Save("Jetzt"))
      H.eq(slotText(O.Get("Jetzt").slots), "0=2101,4=2001")
      -- spaetere Aenderungen beruehren das Outfit nicht
      T.State.Select(0, 2102)
      T.State.Select(15, 2201)
      look[0] = 9
      H.eq(slotText(O.Get("Jetzt").slots), "0=2101,4=2001")
      -- uebergebene Tabelle wird kopiert
      local mine = { [0] = 2102 }
      H.truthy(O.Save("Kopie", mine))
      mine[0] = 5
      mine[4] = 6
      H.eq(slotText(O.Get("Kopie").slots), "0=2102")
   end)

   H.test("Save: ueberschreibt nie stillschweigend, Fehlerschluessel, kein Ereignis", function()
      local T = worldBoot()
      local O = T.Outfits
      H.truthy(O.Save("Raid", { [0] = 2101 }))
      local c = counter(T, { "OUTFITS_CHANGED" })
      local ok, err = O.Save("raid", { [0] = 2102 })
      H.eq(ok, false)
      H.eq(err, "OUTFIT_ERR_EXISTS")
      H.eq(slotText(O.Get("Raid").slots), "0=2101")
      ok, err = O.Save("", { [0] = 2102 })
      H.eq(err, "OUTFIT_ERR_EMPTY")
      ok, err = O.Save(string.rep("x", 33), { [0] = 2102 })
      H.eq(err, "OUTFIT_ERR_LONG")
      ok, err = O.Save("Leer", {})
      H.eq(ok, false)
      H.eq(err, "OUTFIT_ERR_NOITEMS")
      ok, err = O.Save("Leer")                           -- kein Look vorhanden
      H.eq(err, "OUTFIT_ERR_NOITEMS")
      H.eq(O.Count(), 1)
      H.eq(c.OUTFITS_CHANGED, nil)
      -- alle Fehlerschluessel sind lokalisiert
      for _, key in ipairs({ "OUTFIT_ERR_EMPTY", "OUTFIT_ERR_LONG", "OUTFIT_ERR_EXISTS",
                             "OUTFIT_ERR_FULL", "OUTFIT_ERR_NOITEMS", "OUTFIT_ERR_MISSING" }) do
         H.neq(T.L[key], key, key)
      end
   end)

   H.test("Save: ungueltige Teile werden verworfen", function()
      local T = worldBoot()
      local O = T.Outfits
      local ok = O.Save("Gemischt", {
         [0] = 2101,            -- gueltig
         [1] = 2102,            -- Hals: nicht transmogbar
         [11] = 2102,           -- Ring
         [99] = 2102,           -- unbekannt
         [4] = HIDDEN,          -- gueltig (Brust verbergbar)
         [15] = HIDDEN,         -- Haupthand nicht verbergbar
         [16] = HIDDEN,         -- Nebenhand nicht verbergbar
         [17] = HIDDEN,         -- Fernkampf nicht verbergbar
         [3] = 0,               -- 0 = kein Aussehen
         [5] = -5,
         [6] = "abc",
         [7] = 12.5,
         [8] = false,
         ["x"] = 4,
         [9] = "2102",          -- Zahltext wird gelesen
      })
      H.eq(ok, true)
      H.eq(slotText(O.Get("Gemischt").slots), "0=2101,4=999999,9=2102")
      H.eq(O.Get("Gemischt").count, 3)
      -- nur Ungueltiges
      local ok2, err = O.Save("Muell", { [1] = 5, [15] = HIDDEN, [3] = 0 })
      H.eq(ok2, false)
      H.eq(err, "OUTFIT_ERR_NOITEMS")
   end)

   H.test("Save: Obergrenze MAX (50)", function()
      local T = worldBoot()
      local O = T.Outfits
      for i = 1, O.MAX do
         H.truthy(O.Save("Outfit " .. i, { [0] = 2101 }), "Outfit " .. i)
      end
      H.eq(O.Count(), 50)
      local c = counter(T, { "OUTFITS_CHANGED" })
      local ok, err = O.Save("Eins zu viel", { [0] = 2101 })
      H.eq(ok, false)
      H.eq(err, "OUTFIT_ERR_FULL")
      H.eq(O.Count(), 50)
      H.eq(O.Exists("Eins zu viel"), false)
      H.eq(c.OUTFITS_CHANGED, nil)
      -- Ueberschreiben und Umbenennen bleiben moeglich
      H.truthy(O.Overwrite("Outfit 7", { [0] = 2102 }))
      H.truthy(O.Rename("Outfit 8", "Umbenannt"))
      H.eq(O.Count(), 50)
      -- Loeschen macht Platz
      H.truthy(O.Delete("Outfit 1"))
      H.truthy(O.Save("Eins zu viel", { [0] = 2101 }))
      H.eq(O.Count(), 50)
   end)

   H.test("Overwrite: ersetzt die Teile, behaelt Namen und Position", function()
      local T = worldBoot()
      local O = T.Outfits
      O.Save("A", { [0] = 2101 })
      O.Save("B", { [0] = 2102, [4] = 2001 })
      O.Save("C", { [15] = 2201 })
      local c = counter(T, { "OUTFITS_CHANGED" })
      local ok, err = O.Overwrite("b", { [4] = 2002, [18] = HIDDEN })
      H.eq(ok, true)
      H.eq(err, nil)
      H.eq(c.OUTFITS_CHANGED, 1)
      H.eq(names(T), "A|B|C")
      H.eq(slotText(O.Get("B").slots), "18=999999,4=2002")
      H.eq(O.Get("B").count, 2)
      -- ohne Teile: aktueller Look; die Zeit wird aktualisiert
      T.State.Select(0, 2101)
      O.Get("C").time = 1
      local t0 = time()
      H.truthy(O.Overwrite("C"))
      H.eq(slotText(O.Get("C").slots), "0=2101")
      H.truthy(O.Get("C").time >= t0)
      -- Fehler
      ok, err = O.Overwrite("Gibt es nicht", { [0] = 2101 })
      H.eq(ok, false)
      H.eq(err, "OUTFIT_ERR_MISSING")
      ok, err = O.Overwrite("A", {})
      H.eq(err, "OUTFIT_ERR_NOITEMS")
      H.eq(slotText(O.Get("A").slots), "0=2101", "unveraendert nach Fehler")
      H.eq(c.OUTFITS_CHANGED, 2)
      H.eq(select(2, O.Overwrite(nil, { [0] = 2101 })), "OUTFIT_ERR_MISSING")
   end)

   H.test("Delete: entfernt genau eines, Reihenfolge bleibt", function()
      local T = worldBoot()
      local O = T.Outfits
      O.Save("A", { [0] = 2101 })
      O.Save("B", { [0] = 2102 })
      O.Save("C", { [15] = 2201 })
      local c = counter(T, { "OUTFITS_CHANGED" })
      H.eq(O.Delete("b"), true)
      H.eq(names(T), "A|C")
      H.eq(c.OUTFITS_CHANGED, 1)
      H.eq(O.Exists("B"), false)
      local ok, err = O.Delete("B")
      H.eq(ok, false)
      H.eq(err, "OUTFIT_ERR_MISSING")
      H.eq(select(2, O.Delete(nil)), "OUTFIT_ERR_MISSING")
      H.eq(select(2, O.Delete("")), "OUTFIT_ERR_MISSING")
      H.eq(c.OUTFITS_CHANGED, 1)
      -- der Name ist wieder frei
      H.truthy(O.Save("B", { [0] = 2102 }))
      H.eq(names(T), "A|C|B")
      H.truthy(O.Delete("A"))
      H.truthy(O.Delete("C"))
      H.truthy(O.Delete("B"))
      H.deepEq(O.List(), {})
      H.eq(#T.DB.char.outfits, 0)
   end)

   H.test("Rename: Eindeutigkeit, Schreibweise aendern, Fehler", function()
      local T = worldBoot()
      local O = T.Outfits
      O.Save("Alpha", { [0] = 2101 })
      O.Save("Beta", { [0] = 2102, [4] = 2001 })
      local c = counter(T, { "OUTFITS_CHANGED" })
      local before = O.Get("Beta")
      local ok, err = O.Rename("beta", "Gamma")
      H.eq(ok, true)
      H.eq(err, nil)
      H.eq(c.OUTFITS_CHANGED, 1)
      H.eq(names(T), "Alpha|Gamma")
      H.eq(O.Get("Gamma"), before, "dasselbe Outfit-Objekt")
      H.eq(slotText(O.Get("Gamma").slots), "0=2102,4=2001")
      H.eq(O.Exists("Beta"), false)
      -- nur die Schreibweise aendern ist erlaubt
      ok, err = O.Rename("gamma", "GAMMA")
      H.eq(ok, true)
      H.eq(names(T), "Alpha|GAMMA")
      -- unveraendert: kein Fehler, kein Ereignis
      local n = c.OUTFITS_CHANGED
      ok = O.Rename("Alpha", "  Alpha ")
      H.eq(ok, true)
      H.eq(c.OUTFITS_CHANGED, n)
      -- Kollision mit einem anderen Outfit (auch andere Schreibweise)
      ok, err = O.Rename("Alpha", "gamma")
      H.eq(ok, false)
      H.eq(err, "OUTFIT_ERR_EXISTS")
      -- leer / zu lang / fehlend
      H.eq(select(2, O.Rename("Alpha", "   ")), "OUTFIT_ERR_EMPTY")
      H.eq(select(2, O.Rename("Alpha", nil)), "OUTFIT_ERR_EMPTY")
      H.eq(select(2, O.Rename("Alpha", string.rep("z", 33))), "OUTFIT_ERR_LONG")
      H.eq(select(2, O.Rename("Gibt es nicht", "Neu")), "OUTFIT_ERR_MISSING")
      H.eq(select(2, O.Rename(nil, "Neu")), "OUTFIT_ERR_MISSING")
      H.eq(names(T), "Alpha|GAMMA")
      -- Namen werden bereinigt
      H.truthy(O.Rename("Alpha", "  |cff00ff00Neu|r  Name "))
      H.eq(names(T), "Neu Name|GAMMA")
      H.deepEq(H.takeErrors(), {})
   end)

   -- -------------------------------------------------------------------------
   H.section("CurrentLook")
   -- -------------------------------------------------------------------------

   H.test("CurrentLook: Auswahl, angewendet, verborgen; ohne 0 und ohne Inaktive", function()
      local T = worldBoot()
      local O = T.Outfits
      H.deepEq(O.CurrentLook(), {})
      -- Status: Kopf 2101, Brust 2001, Haupthand 5555 (steht nicht in der Liste => inaktiv),
      -- Wappenrock verborgen
      T.Net.Handle("TransmogStatus:4:0,2101:4,2001:15,5555:18," .. HIDDEN)
      H.truthy(T.State.IsInactive(15))
      H.eq(slotText(O.CurrentLook()), "0=2101,18=999999,4=2001")
      -- Auswahl ersetzt angewendet
      H.truthy(T.State.Select(4, 2002))
      H.eq(O.CurrentLook()[4], 2002)
      -- Verborgen auswaehlen
      H.truthy(T.State.Select(0, HIDDEN))
      H.eq(O.CurrentLook()[0], HIDDEN)
      -- "Original" (0) vormerken: Slot verschwindet aus dem Look
      H.truthy(T.State.Select(18, 0))
      local look = O.CurrentLook()
      H.eq(look[18], nil)
      H.eq(slotText(look), "0=999999,4=2002")
      -- nur die 14 Slots, nie 0-Werte
      for slot, id in pairs(look) do
         H.truthy(slot == 0 or slot == 2 or slot == 3 or slot == 4 or slot == 5 or slot == 6 or slot == 7
            or slot == 8 or slot == 9 or slot == 14 or slot == 15 or slot == 16 or slot == 17 or slot == 18)
         H.truthy(id > 0)
      end
      -- Auswahl verwerfen: wieder der angewendete Zustand
      T.State.DiscardAll()
      H.eq(slotText(O.CurrentLook()), "0=2101,18=999999,4=2001")
   end)

   -- -------------------------------------------------------------------------
   H.section("Laden")
   -- -------------------------------------------------------------------------

   -- Ein Outfit mit allen Arten von Eintraegen
   local function mixedOutfit(T)
      local O = T.Outfits
      local ok = O.Save("Gemischt", {
         [0] = 2101,        -- Kopf: verfuegbar
         [2] = 2101,        -- Schulter: leer
         [4] = 2201,        -- Brust: nicht in der Brustliste
         [15] = 2201,       -- Haupthand: verfuegbar
         [16] = 2201,       -- Nebenhand: leer
         [17] = 2201,       -- Fernkampf: Relikt (nie)
         [18] = HIDDEN,     -- Wappenrock verborgen: erlaubt
         [14] = HIDDEN,     -- Ruecken verborgen, aber leer
      })
      H.truthy(ok)
      return O
   end

   H.test("Load: verfuegbar / leer / nie / nicht verfuegbar / verborgen", function()
      local T = worldBoot()
      local O = mixedOutfit(T)
      local applied, skipped = O.Load("gemischt")
      H.eq(join(applied), "0,15,18")
      local reason = {}
      for _, s in ipairs(skipped) do reason[s.slot] = s.reasonKey end
      H.eq(#skipped, 5)
      H.eq(reason[2], "OUTFIT_SKIP_EMPTY")
      H.eq(reason[4], "OUTFIT_SKIP_UNAVAILABLE")
      H.eq(reason[14], "OUTFIT_SKIP_EMPTY")
      H.eq(reason[16], "OUTFIT_SKIP_EMPTY")
      H.eq(reason[17], "OUTFIT_SKIP_NEVER")
      -- Eintraege tragen Slot, id und Grund (benannt und positionell)
      local first = skipped[1]
      H.eq(first.slot, 2)
      H.eq(first.id, 2101)
      H.eq(first[1], 2)
      H.eq(first[2], 2101)
      H.eq(first[3], "OUTFIT_SKIP_EMPTY")
      -- aufsteigend nach Slot
      local slots = {}
      for i, s in ipairs(skipped) do slots[i] = s.slot end
      H.eq(join(slots), "2,4,14,16,17")
      -- Zustand
      H.eq(T.State.Wanted(0), 2101)
      H.eq(T.State.Wanted(15), 2201)
      H.eq(T.State.Wanted(18), HIDDEN)
      H.eq(T.State.Wanted(4), 0)
      H.eq(T.State.PendingCount(), 3)
      -- Lokalisierung der Gruende
      for _, key in ipairs({ "OUTFIT_SKIP_EMPTY", "OUTFIT_SKIP_NEVER", "OUTFIT_SKIP_LOADING",
                             "OUTFIT_SKIP_UNAVAILABLE", "OUTFIT_SKIP_HIDDEN" }) do
         H.neq(T.L[key], key, key)
      end
   end)

   H.test("Load: genau EIN SetMany und EIN WANTED_CHANGED, danach nichts mehr", function()
      local T = worldBoot()
      local O = mixedOutfit(T)
      local spy = spyOnSetMany(T)
      local c = counter(T, { "WANTED_CHANGED", "OUTFITS_CHANGED" })
      local applied = O.Load("Gemischt")
      H.eq(spy.calls, 1)
      H.eq(slotText(spy.maps[1]), "0=2101,15=2201,18=999999")
      H.eq(c.WANTED_CHANGED, 1)
      H.eq(c.OUTFITS_CHANGED, nil, "Laden aendert die Outfits nicht")
      H.eq(join(applied), "0,15,18")
      -- zweites Laden: gleiche Auswahl => State meldet keine Aenderung
      applied = O.Load("Gemischt")
      H.eq(join(applied), "0,15,18")
      H.eq(spy.calls, 2)
      H.eq(c.WANTED_CHANGED, 1)
   end)

   H.test("Load: nicht verbergbarer Slot mit Verborgen (Rohdaten), unbekannte Slots", function()
      local T = worldBoot()
      local O = T.Outfits
      H.truthy(O.Save("Roh", { [0] = 2101, [15] = 2201, [18] = 2301 }))
      local raw = O.Get("Roh").slots
      raw[15] = HIDDEN               -- Haupthand: nicht verbergbar
      raw[1] = 5                     -- Hals (nicht unter den 14)
      raw[99] = 5
      raw["4"] = 2001                -- Schluessel als Text wird gelesen
      raw["x"] = 7
      raw[17] = "abc"                -- kein gueltiger Wert
      raw[16] = 0
      local applied, skipped = O.Load("Roh")
      H.eq(join(applied), "0,4,18")
      H.eq(#skipped, 1)
      H.eq(skipped[1].slot, 15)
      H.eq(skipped[1].reasonKey, "OUTFIT_SKIP_HIDDEN")
      H.eq(T.State.Wanted(0), 2101)
      H.eq(T.State.Wanted(4), 2001)
      H.eq(T.State.Wanted(18), 2301)
      H.eq(T.State.Wanted(15), 0)
   end)

   H.test("Load: unbekanntes Outfit, nichts anwendbar, Ereignisse", function()
      local T = worldBoot()
      local O = T.Outfits
      local spy = spyOnSetMany(T)
      local c = counter(T, { "WANTED_CHANGED" })
      local applied, skipped, err = O.Load("Gibt es nicht")
      H.deepEq(applied, {})
      H.deepEq(skipped, {})
      H.eq(err, "OUTFIT_ERR_MISSING")
      applied, skipped, err = O.Load(nil)
      H.eq(err, "OUTFIT_ERR_MISSING")
      -- nichts anwendbar: leere Nebenhand, Relikt-Fernkampf
      H.truthy(O.Save("Nutzlos", { [2] = 2101, [16] = 2201, [17] = 2201 }))
      applied, skipped = O.Load("Nutzlos")
      H.deepEq(applied, {})
      H.eq(#skipped, 3)
      H.eq(spy.calls, 0, "ohne anwendbare Teile kein SetMany")
      H.eq(c.WANTED_CHANGED, nil)
      H.eq(T.State.PendingCount(), 0)
   end)

   H.test("Load: laufende Liste => LOADING; Verborgen braucht keine Liste", function()
      local T = worldBoot()
      local O = T.Outfits
      H.truthy(O.Save("Mix", { [0] = 2101, [4] = HIDDEN, [15] = 2201 }))
      -- Strom des Kopfes beginnt neu: Teile des Slots sind noch nicht verfuegbar
      T.Net.Handle("AvailableTransmogs:0:405:2:start")
      H.eq(T.State.List(0).ready, false)
      local applied, skipped = O.Load("Mix")
      H.eq(join(applied), "4,15")
      H.eq(#skipped, 1)
      H.eq(skipped[1].slot, 0)
      H.eq(skipped[1].reasonKey, "OUTFIT_SKIP_LOADING")
      -- Teilstrom: 2101 ist schon da (verfuegbar), 2102 noch nicht
      T.State.DiscardAll()
      T.Net.Handle("AvailableTransmogs:0:405:2:2101")
      applied, skipped = O.Load("Mix")
      H.eq(join(applied), "0,4,15")
      H.eq(#skipped, 0)
      -- Strom fertig
      T.Net.Handle("AvailableTransmogs:0:405:2:end")
      T.State.DiscardAll()
      applied = O.Load("Mix")
      H.eq(join(applied), "0,4,15")
   end)

   H.test("Load: Slot wird zu NEVER/EMPTY, wenn Ausruestung wechselt", function()
      local T = worldBoot()
      local O = T.Outfits
      H.truthy(O.Save("Kopf", { [0] = 2101, [4] = 2001 }))
      mock.world.equipment[1] = nil          -- Helm ausgezogen
      T.State.RefreshEquipment()
      local applied, skipped = O.Load("Kopf")
      H.eq(join(applied), "4")
      H.eq(skipped[1].slot, 0)
      H.eq(skipped[1].reasonKey, "OUTFIT_SKIP_EMPTY")
   end)

   H.test("Load: bestehende Auswahl anderer Slots bleibt; gleiche Auswahl wie angewendet", function()
      local T = worldBoot()
      local O = T.Outfits
      T.Net.Handle("TransmogStatus:1:0,2101")
      H.truthy(T.State.Select(15, 2202))
      H.truthy(O.Save("Look", { [0] = 2101, [4] = 2002 }))
      local applied = O.Load("Look")
      H.eq(join(applied), "0,4")
      H.eq(T.State.Wanted(15), 2202, "nicht im Outfit enthaltene Auswahl bleibt")
      H.eq(T.State.Wanted(4), 2002)
      H.eq(T.State.HasPending(4), true)
      H.eq(T.State.HasPending(0), false, "Kopf entspricht dem angewendeten Aussehen")
      H.eq(T.State.PendingCount(), 2)
   end)

   H.test("Check: wie Load, aber ohne Auswahl zu aendern", function()
      local T = worldBoot()
      local O = mixedOutfit(T)
      local spy = spyOnSetMany(T)
      local applied, skipped = O.Check("Gemischt")
      H.eq(join(applied), "0,15,18")
      H.eq(#skipped, 5)
      H.eq(spy.calls, 0)
      H.eq(T.State.PendingCount(), 0)
      local _, _, err = O.Check("Nope")
      H.eq(err, "OUTFIT_ERR_MISSING")
   end)

   H.test("RequestItems: fordert Item-Daten der Outfits (ohne HIDDEN) an", function()
      local T = worldBoot()
      local O = T.Outfits
      O.Save("A", { [0] = 2101, [18] = HIDDEN })
      O.Save("B", { [4] = 2001, [0] = 2101 })
      local requested
      local orig = T.Items.RequestMany
      T.Items.RequestMany = function(list)
         requested = list
         return orig(list)
      end
      O.RequestItems("A")
      table.sort(requested)
      H.eq(join(requested), "2101")
      O.RequestItems()
      table.sort(requested)
      H.eq(join(requested), "2001,2101")
      requested = nil
      O.RequestItems("Gibt es nicht")
      H.eq(requested, nil)
      T.Items.RequestMany = orig
   end)

   -- -------------------------------------------------------------------------
   H.section("Persistenz und Init")
   -- -------------------------------------------------------------------------

   H.test("Outfits ueberleben Neustart (SavedVariables) und DB.Init", function()
      local T = worldBoot()
      local O = T.Outfits
      O.Save("Raid", { [0] = 2101, [4] = 2001, [18] = HIDDEN })
      O.Save("Ärmel", { [15] = 2201 })
      local before = {}
      for i, o in ipairs(O.List()) do
         before[i] = { name = o.name, slots = slotText(o.slots), count = o.count, time = o.time }
      end
      -- DB.Init und Outfits.Init sind idempotent
      T.DB.Init()
      O.Init()
      H.eq(names(T), "Raid|Ärmel")
      -- "Abmeldung": nur einfache Daten ueberleben
      local saved = mock.SavedVariables()
      H.eq(type(saved.TransmogDB), "table")
      local T2 = boot({ globals = saved })
      local after = T2.Outfits.List()
      H.eq(#after, 2)
      for i, o in ipairs(after) do
         H.eq(o.name, before[i].name)
         H.eq(slotText(o.slots), before[i].slots)
         H.eq(o.count, before[i].count)
         H.eq(o.time, before[i].time)
      end
      H.truthy(T2.Outfits.Exists("raid"))
      H.truthy(T2.Outfits.Get("raid").slots[0] == 2101)
      -- und sie sind weiter benutzbar
      feed(T2, 0, { 2101, 2102 })
      feed(T2, 4, { 2001, 2002 })
      local applied = T2.Outfits.Load("Raid")
      H.eq(join(applied), "0,4,18")
      H.truthy(T2.Outfits.Save("Neu", { [0] = 2102 }))
      H.eq(T2.Outfits.Count(), 3)
   end)

   H.test("Altdaten (transmogOutfits) werden uebernommen und sind ladbar", function()
      -- Altes Format: Name -> { [Client-Slot] = itemId }
      local legacy = {
         ["Raid Look"] = { [1] = 2101, [5] = 2001, [16] = 2201, [0] = 5 },
         ["alt"] = { [19] = 999999, [17] = 999999 },
      }
      local T = boot({ globals = { transmogOutfits = legacy } })
      local O = T.Outfits
      local list = O.List()
      H.eq(#list, 2)
      local raid = O.Get("raid look")
      H.truthy(raid, "Raid Look uebernommen")
      H.eq(slotText(raid.slots), "0=2101,15=2201,4=2001")
      -- Verborgen: Wappenrock (Client 19 = Server 18) ja, Nebenhand (Server 16) nein
      local alt = O.Get("alt")
      H.truthy(alt)
      H.eq(slotText(alt.slots), "18=999999")
      -- Altvariable bleibt unberuehrt
      H.eq(legacy["Raid Look"][1], 2101)
   end)

   H.test("Init: bereinigt beschaedigte Daten (Luecken, Doppelte, Muell, lange Namen)", function()
      local T = boot()
      local O = T.Outfits
      T.DB.char.outfits = {
         { name = "  Raid   Look ", slots = { [0] = 2101, [4] = "2001", [1] = 5, [15] = HIDDEN, [18] = HIDDEN }, time = 5 },
         { name = "raid look", slots = { [0] = 2102 } },
         { name = "", slots = { [0] = 2101 } },
         "muell",
         { name = "NoSlots" },
         [7] = { name = string.rep("\195\164", 40), slots = { [0] = 2101 }, time = "x" },
         [9] = { name = string.rep("a", 40), slots = {} },
         [10] = { name = string.rep("a", 40) .. "!", slots = {} },
      }
      O.Init()
      local list = O.List()
      local got = {}
      for i, o in ipairs(list) do got[i] = o.name end
      H.eq(#list, 7)
      H.eq(list[1].name, "Raid Look")
      H.eq(list[2].name, "raid look (2)")
      H.eq(list[3].name, "Outfit 3")
      H.eq(list[4].name, "NoSlots")
      -- Namen sind hoechstens 32 Zeichen lang und eindeutig
      for i, o in ipairs(list) do
         local _, n = string.gsub(o.name, "[^\128-\191]", "")
         H.truthy(n <= 32, "Laenge " .. i)
      end
      H.eq(list[5].name, string.rep("\195\164", 32))
      H.eq(list[6].name, string.rep("a", 32))
      H.neq(list[7].name, list[6].name)
      local seen = {}
      for _, name in ipairs(got) do
         H.eq(seen[string.lower(name)], nil, "doppelt: " .. name)
         seen[string.lower(name)] = true
      end
      -- Teile: nur gueltige Slots/Ids
      H.eq(slotText(list[1].slots), "0=2101,18=999999,4=2001")
      H.eq(list[1].count, 3)
      H.eq(list[1].time, 5)
      H.eq(list[4].count, 0)
      H.eq(list[5].time, 0)
      -- Referenz in DB.char bleibt, Daten dort sind das Array ohne Luecken
      H.eq(#T.DB.char.outfits, 7)
      -- idempotent
      O.Init()
      local again = {}
      for i, o in ipairs(O.List()) do again[i] = o.name end
      H.eq(table.concat(again, "|"), table.concat(got, "|"))
   end)

   H.test("Fehlerrobustheit: keine Fehler in Handlern, keine Seiteneffekte bei Muell", function()
      local T = worldBoot()
      local O = T.Outfits
      H.eq(select(2, O.Save({}, {})), "OUTFIT_ERR_EMPTY")
      H.eq(select(2, O.Save(true, {})), "OUTFIT_ERR_EMPTY")
      H.eq(select(2, O.Save("x", "kein table")), "OUTFIT_ERR_NOITEMS")
      H.eq(O.Exists({}), false)
      H.eq(O.Get(false), nil)
      H.eq(select(3, O.Load({})), "OUTFIT_ERR_MISSING")
      -- gespeicherte Daten ohne slots-Tabelle
      T.DB.char.outfits[1] = { name = "Kaputt" }
      H.eq(O.Get("Kaputt").count, 0)
      local applied, skipped = O.Load("Kaputt")
      H.deepEq(applied, {})
      H.deepEq(skipped, {})
      -- DB.char.outfits fehlt (z. B. Fremdspeicher)
      T.DB.char.outfits = nil
      H.deepEq(O.List(), {})
      H.truthy(O.Save("Neu", { [0] = 2101 }))
      H.eq(#T.DB.char.outfits, 1)
      H.deepEq(H.takeErrors(), {})
   end)

   -- -------------------------------------------------------------------------
   H.section("Zufallsfolgen")
   -- -------------------------------------------------------------------------

   -- Modellbasierter Test: die gespeicherten Outfits werden nach jedem Schritt
   -- mit einem einfachen Modell (geordnete Liste) verglichen; Load wird gegen die
   -- oeffentlichen Getter von State geprueft.
   H.test("Zufallsfolgen: Speichern/Ueberschreiben/Loeschen/Umbenennen/Laden gegen ein Modell", function()
      local state = 99
      local function rnd(n)
         state = (state * 1103515245 + 12345) % 2147483648
         return math.floor(state / 65536) % n
      end
      local T = worldBoot()
      local O = T.Outfits
      local SLOTS = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }
      local VALID = {}
      for _, s in ipairs(SLOTS) do VALID[s] = true end
      local HIDE = { [0] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
                     [8] = true, [9] = true, [14] = true, [18] = true }
      local IDS = { 2101, 2102, 2001, 2002, 2003, 2201, 2202, 2301, HIDDEN, 0, -1, 7.5, "x", 1700000 }
      local NAMES = { "Raid", "raid", "  RAID ", "Pvp", "pvp   look", "PVP LOOK", "Dungeon", "A", "B", "", "   ",
                      string.rep("x", 33), string.rep("y", 32), "|cffff0000Red|r", "Tab\tName", "Look 1" }

      -- Modell
      local model = {}
      local function norm(name)
         if type(name) ~= "string" then return "" end
         name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " "):gsub("[%c|]", ""):gsub(" +", " ")
         return (name:match("^%s*(.-)%s*$"))
      end
      local function find(name)
         local key = string.lower(norm(name))
         if key == "" then return nil end
         for i, o in ipairs(model) do
            if string.lower(o.name) == key then return i end
         end
         return nil
      end
      local function clean(slots)
         local out, n = {}, 0
         for _, s in ipairs(SLOTS) do
            local v = tonumber(slots[s])
            if v and v > 0 and v == math.floor(v) and (v ~= HIDDEN or HIDE[s]) then
               out[s] = v
               n = n + 1
            end
         end
         return out, n
      end
      local filling = false      -- Phase: viele verschiedene Namen, um die Obergrenze zu erreichen
      local function randomName()
         if filling or rnd(3) == 0 then return "N" .. rnd(filling and 140 or 90) end
         return NAMES[1 + rnd(#NAMES)]
      end
      local function randomSlots()
         local t = {}
         for _, s in ipairs(SLOTS) do
            if rnd(3) == 0 then t[s] = IDS[1 + rnd(#IDS)] end
         end
         if rnd(8) == 0 then t[1] = 2101; t[99] = 5 end        -- Fremdschluessel
         return t
      end
      local function nameLen(n) return #n end   -- nur ASCII-Namen in diesem Test

      local function compare(step, what)
         local list = O.List()
         if #list ~= #model then
            H.fail(string.format("Schritt %d (%s): %d Outfits statt %d", step, what, #list, #model))
            return false
         end
         for i, o in ipairs(model) do
            if list[i].name ~= o.name or slotText(list[i].slots) ~= slotText(o.slots)
               or list[i].count ~= o.count then
               H.fail(string.format("Schritt %d (%s): Outfit %d '%s' [%s] statt '%s' [%s]", step, what, i,
                  list[i].name, slotText(list[i].slots), o.name, slotText(o.slots)))
               return false
            end
            if #list[i].name > 32 then
               H.fail("Name zu lang: " .. list[i].name)
               return false
            end
         end
         if #T.DB.char.outfits ~= #model then
            H.fail("DB.char.outfits weicht ab")
            return false
         end
         return true
      end

      local fed = { 0, 4, 15, 18 }
      local seen = {}
      local function tally(key) seen[key] = (seen[key] or 0) + 1 end
      for step = 1, 600 do
         filling = (step >= 150 and step < 330)
         local op = rnd(12)
         if filling and rnd(4) ~= 0 then op = 0 end
         local what
         if op <= 2 then
            local name, slots = randomName(), randomSlots()
            local useLook = rnd(5) == 0
            what = "Save '" .. name .. "'"
            local ok, err = O.Save(name, (not useLook) and slots or nil)
            local n = norm(name)
            local expectOk, expectErr = true, nil
            local cleaned, count
            if useLook then
               cleaned, count = clean(O.CurrentLook())
            else
               cleaned, count = clean(slots)
            end
            if n == "" then expectOk, expectErr = false, "OUTFIT_ERR_EMPTY"
            elseif nameLen(n) > 32 then expectOk, expectErr = false, "OUTFIT_ERR_LONG"
            elseif find(n) then expectOk, expectErr = false, "OUTFIT_ERR_EXISTS"
            elseif #model >= 50 then expectOk, expectErr = false, "OUTFIT_ERR_FULL"
            elseif count == 0 then expectOk, expectErr = false, "OUTFIT_ERR_NOITEMS" end
            if ok ~= expectOk or err ~= expectErr then
               H.fail(string.format("Schritt %d %s: ok=%s err=%s, erwartet ok=%s err=%s", step, what,
                  tostring(ok), tostring(err), tostring(expectOk), tostring(expectErr)))
               return
            end
            tally(expectOk and "save-ok" or ("save-" .. expectErr))
            if expectOk then model[#model + 1] = { name = n, slots = cleaned, count = count } end
         elseif op == 3 then
            local name, slots = randomName(), randomSlots()
            what = "Overwrite '" .. name .. "'"
            local ok, err = O.Overwrite(name, slots)
            local i = find(name)
            local cleaned, count = clean(slots)
            local expectOk, expectErr = true, nil
            if not i then expectOk, expectErr = false, "OUTFIT_ERR_MISSING"
            elseif count == 0 then expectOk, expectErr = false, "OUTFIT_ERR_NOITEMS" end
            if ok ~= expectOk or err ~= expectErr then
               H.fail(string.format("Schritt %d %s: ok=%s err=%s, erwartet ok=%s err=%s", step, what,
                  tostring(ok), tostring(err), tostring(expectOk), tostring(expectErr)))
               return
            end
            tally(expectOk and "overwrite-ok" or ("overwrite-" .. expectErr))
            if expectOk then model[i].slots, model[i].count = cleaned, count end
         elseif op == 4 then
            local name = randomName()
            what = "Delete '" .. name .. "'"
            local ok, err = O.Delete(name)
            local i = find(name)
            if (ok == true) ~= (i ~= nil) or (not ok and err ~= "OUTFIT_ERR_MISSING") then
               H.fail(string.format("Schritt %d %s: ok=%s err=%s", step, what, tostring(ok), tostring(err)))
               return
            end
            tally(i and "delete-ok" or "delete-missing")
            if i then table.remove(model, i) end
         elseif op == 5 or op == 6 then
            local old, new = randomName(), randomName()
            what = "Rename '" .. old .. "' -> '" .. new .. "'"
            local ok, err = O.Rename(old, new)
            local i = find(old)
            local n = norm(new)
            local expectOk, expectErr = true, nil
            if not i then expectOk, expectErr = false, "OUTFIT_ERR_MISSING"
            elseif n == model[i].name then expectOk = true
            elseif n == "" then expectOk, expectErr = false, "OUTFIT_ERR_EMPTY"
            elseif nameLen(n) > 32 then expectOk, expectErr = false, "OUTFIT_ERR_LONG"
            else
               local j = find(n)
               if j and j ~= i then expectOk, expectErr = false, "OUTFIT_ERR_EXISTS" end
            end
            if ok ~= expectOk or err ~= expectErr then
               H.fail(string.format("Schritt %d %s: ok=%s err=%s, erwartet ok=%s err=%s", step, what,
                  tostring(ok), tostring(err), tostring(expectOk), tostring(expectErr)))
               return
            end
            tally(expectOk and "rename-ok" or ("rename-" .. expectErr))
            if expectOk and i then model[i].name = n end
         elseif op == 7 or op == 8 then
            -- Laden gegen die oeffentlichen Getter von State
            local name = randomName()
            what = "Load '" .. name .. "'"
            local i = find(name)
            local S = T.State
            local expectApplied, expectSkipped = {}, {}
            if i then
               for _, slot in ipairs(SLOTS) do
                  local id = model[i].slots[slot]
                  if id then
                     local st = S.SlotState(slot)
                     local reason
                     if st == "NEVER" then reason = "OUTFIT_SKIP_NEVER"
                     elseif st ~= "READY" then reason = "OUTFIT_SKIP_EMPTY"
                     elseif id == HIDDEN then
                        if not HIDE[slot] then reason = "OUTFIT_SKIP_HIDDEN" end
                     elseif not S.IsAvailable(slot, id) then
                        reason = S.List(slot).ready and "OUTFIT_SKIP_UNAVAILABLE" or "OUTFIT_SKIP_LOADING"
                     end
                     if reason then
                        expectSkipped[#expectSkipped + 1] = slot .. ":" .. reason
                     else
                        expectApplied[#expectApplied + 1] = slot
                     end
                  end
               end
            end
            local applied, skipped, err = O.Load(name)
            local gotSkipped = {}
            for k, sk in ipairs(skipped) do gotSkipped[k] = sk.slot .. ":" .. sk.reasonKey end
            if join(applied) ~= join(expectApplied) or table.concat(gotSkipped, ",") ~= table.concat(expectSkipped, ",")
               or (i == nil and err ~= "OUTFIT_ERR_MISSING") then
               H.fail(string.format("Schritt %d %s: applied [%s] skipped [%s], erwartet [%s] [%s]", step, what,
                  join(applied), table.concat(gotSkipped, ","), join(expectApplied), table.concat(expectSkipped, ",")))
               return
            end
            tally(i and ((#applied > 0) and "load-applied" or "load-none") or "load-missing")
            if #skipped > 0 then tally("load-skipped") end
            for _, slot in ipairs(applied) do
               if S.Wanted(slot) ~= model[i].slots[slot] then
                  H.fail(string.format("Schritt %d %s: Slot %d nicht gewaehlt", step, what, slot))
                  return
               end
            end
         elseif op == 9 then
            what = "State"
            local slot = fed[1 + rnd(#fed)]
            local pick = rnd(4)
            if pick == 0 then T.State.Select(slot, 2101 + rnd(2))
            elseif pick == 1 then T.State.DiscardAll()
            elseif pick == 2 then T.Net.Handle("TransmogStatus:1:" .. slot .. "," .. (2001 + rnd(3)))
            else T.Net.Handle("AvailableTransmogs:" .. slot .. ":405:2:start") end
         elseif op == 10 then
            what = "Init"
            T.DB.Init()
            O.Init()
         else
            what = "Liste"
            feed(T, 0, { 2101, 2102 })
            feed(T, 4, { 2001, 2002, 2003 })
         end
         if not compare(step, what) then return end
      end
      -- die Folge hat alle Pfade tatsaechlich durchlaufen
      for _, key in ipairs({ "save-ok", "save-OUTFIT_ERR_EMPTY", "save-OUTFIT_ERR_LONG", "save-OUTFIT_ERR_EXISTS",
                             "save-OUTFIT_ERR_FULL", "save-OUTFIT_ERR_NOITEMS", "overwrite-ok",
                             "overwrite-OUTFIT_ERR_MISSING", "delete-ok", "rename-ok", "rename-OUTFIT_ERR_EXISTS",
                             "load-applied", "load-skipped" }) do
         H.truthy((seen[key] or 0) >= 2, "Pfad nicht erreicht: " .. key)
      end
      H.deepEq(H.takeErrors(), {})
   end)
end
