-- tests/test_items.lua
-- ---------------------------------------------------------------------------
-- Tests fuer Core/Items.lua (T.Items): Item-Cache, gedrosselte Abfragen ueber
-- den Scan-Tooltip, ITEMS_RESOLVED-Buendelung und die locale-unabhaengige
-- Typ-Ermittlung (typeKey = Klasse * 100 + Unterklasse).
--
-- Geprueft wird das VERHALTEN aus SPEC 5.6, nicht die Implementierung:
--   * Info/Get/Request/RequestMany/IsResolved/PendingCount/Link
--   * Drosselung (hoechstens 25 SetHyperlink je 0.1 s), FIFO, Idempotenz
--   * Aufgeben nach 20 s, erneuter Versuch nach 60 s, Nachzuegler
--   * ITEMS_RESOLVED (max ~5/s, Summe der Zaehler stimmt)
--   * der Poll-Frame versteckt sich im Leerlauf (SPEC Regel 9)
--   * typeKey/TypeLabel mit enUS- und deDE-Auktionshaus-Listen, Laengenpruefung,
--     Rueckfalltabellen, unbekannte Namen (kein Chat-Spam), IsNever
--   * Ids als Strings/Links, ungueltige Eingaben, HIDDEN_ID
--
-- Aufruf (im Hauptverzeichnis):  luajit tests/run.lua items
-- ---------------------------------------------------------------------------

return function(H)
   local mock = H.mock

   -- -------------------------------------------------------------------------
   -- Daten
   -- -------------------------------------------------------------------------

   -- echte ITEM_SUBCLASS-Werte in Reihenfolge der AH-Listen (siehe SPEC 5.6)
   local WEAPON_KEYS = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 210, 213, 214, 215, 216, 218, 219, 220 }
   local ARMOR_KEYS = { 400, 401, 402, 403, 404, 406, 407, 408, 409, 410 }

   local EN = {
      classes = { "Weapon", "Armor" },
      weapon = { "One-Handed Axes", "Two-Handed Axes", "Bows", "Guns", "One-Handed Maces",
                 "Two-Handed Maces", "Polearms", "One-Handed Swords", "Two-Handed Swords", "Staves",
                 "Fist Weapons", "Miscellaneous", "Daggers", "Thrown", "Crossbows", "Wands",
                 "Fishing Poles" },
      armor = { "Miscellaneous", "Cloth", "Leather", "Mail", "Plate", "Shields", "Librams", "Idols",
                "Totems", "Sigils" },
   }
   -- deDE: an einem echten deDE-3.3.5-Client verifiziert
   local DE = {
      classes = { "Waffe", "Rüstung" },
      weapon = { "Einhandäxte", "Zweihandäxte", "Bogen", "Schusswaffen", "Einhandstreitkolben",
                 "Zweihandstreitkolben", "Stangenwaffen", "Einhandschwerter", "Zweihandschwerter",
                 "Stäbe", "Faustwaffen", "Verschiedenes", "Dolche", "Wurfwaffen", "Armbrüste",
                 "Zauberstäbe", "Angelruten" },
      armor = { "Verschiedenes", "Stoff", "Leder", "Schwere Rüstung", "Platte", "Schilde",
                "Buchbände", "Götzen", "Totems", "Siegel" },
   }
   -- Namen anderer Sprachen (nur ueber die Rueckfalltabellen erreichbar)
   local ES = {
      classes = { "Arma", "Armadura" },
      weapon = { "Hachas de una mano", "Hachas de dos manos", "Arcos", "Armas de fuego",
                 "Mazas de una mano", "Mazas de dos manos", "Armas de asta", "Espadas de una mano",
                 "Espadas de dos manos", "Bastones", "Armas de puño", "Misceláneo", "Dagas",
                 "Armas arrojadizas", "Ballestas", "Varitas", "Cañas de pescar" },
      armor = { "Misceláneo", "Tela", "Cuero", "Malla", "Placas", "Escudos", "Tratados", "Ídolos",
                "Tótems", "Sellos" },
   }
   local RU = {
      classes = { "Оружие", "Доспехи" },
      weapon = { "Одноручные топоры", "Двуручные топоры", "Луки", "Огнестрельное оружие",
                 "Одноручное дробящее оружие", "Двуручное дробящее оружие", "Древковое оружие",
                 "Одноручные мечи", "Двуручные мечи", "Посохи", "Кистевое оружие", "Разное",
                 "Кинжалы", "Метательное оружие", "Арбалеты", "Жезлы", "Удочки" },
      armor = { "Разное", "Ткань", "Кожа", "Кольчуга", "Латы", "Щиты", "Манускрипты", "Идолы",
                "Тотемы", "Печати" },
   }

   -- Baut die AH-Listenstruktur der Attrappe: { classes = {...}, subclasses = { [1]=, [2]= } }
   -- Es werden alle 12 Klassen der echten 3.3.5-Liste geliefert (Index 1 Waffe, 2 Ruestung).
   local function ahLists(def, classNames)
      local classes = classNames or { def.classes[1], def.classes[2], "Container", "Consumable", "Glyph",
                                      "Trade Goods", "Projectile", "Quiver", "Recipe", "Gem",
                                      "Miscellaneous", "Quest" }
      return {
         classes = classes,
         subclasses = { [1] = def.weapon, [2] = def.armor, [3] = { "Bag" } },
      }
   end

   local function copyList(t)
      local out = {}
      for i = 1, #t do out[i] = t[i] end
      return out
   end

   -- Orakel fuer den Namens-Rueckfall, unabhaengig von Core/Items.lua aus den AH-Spalten EN/DE/ES
   -- oben (Namen in AH-Reihenfolge) und den festen Unterklassen-IDs der Spieldatenbank abgeleitet.
   -- ORACLE[Klasse][Name] = Unterklasse
   local WEAPON_SUB = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 14, 15, 16, 18, 19, 20 }
   local ARMOR_SUB = { 0, 1, 2, 3, 4, 6, 7, 8, 9, 10 }
   local ORACLE = { [2] = {}, [4] = {} }
   for _, def in ipairs({ EN, DE, ES }) do
      for i, name in ipairs(def.weapon) do ORACLE[2][name] = WEAPON_SUB[i] end
      for i, name in ipairs(def.armor) do ORACLE[4][name] = ARMOR_SUB[i] end
   end
   local CLASS_IDS = {
      ["Weapon"] = 2, ["Waffe"] = 2, ["Waffen"] = 2, ["Arma"] = 2,
      ["Armor"] = 4, ["Rüstung"] = 4, ["Armadura"] = 4,
   }

   -- -------------------------------------------------------------------------
   -- Hilfen
   -- -------------------------------------------------------------------------

   -- Legt einen Gegenstand in der Attrappe an (nur im Server/Client-Datenbestand,
   -- noch NICHT im Client-Cache).
   local function put(id, name, class, subclass, equipLoc, extra)
      local it = {
         name = name or ("Item " .. id), class = class or "Armor", subclass = subclass or "Plate",
         equipLoc = equipLoc or "INVTYPE_HEAD", quality = 3, ilvl = 200, minLevel = 70,
         icon = "Interface\\Icons\\INV_Test_" .. id,
      }
      if extra then
         for k, v in pairs(extra) do it[k] = v end
      end
      mock.items[id] = it
      return it
   end

   -- Viele gleichartige Gegenstaende first..last
   local function putRange(first, last)
      for id = first, last do put(id) end
   end

   -- Bootet bis einschliesslich Core\Items.lua. opts.world / opts.items wie H.boot,
   -- opts.init = false: Items.Init() nicht rufen, opts.skip: Dateien auslassen.
   -- Liefert env mit T, Items und einem Ereignisprotokoll fuer ITEMS_RESOLVED.
   local function setup(opts)
      opts = opts or {}
      local T = H.boot({ upTo = "Core\\Items.lua", world = opts.world, items = opts.items, skip = opts.skip })
      H.assert(type(T) == "table" and type(T.Items) == "table", "Transmog.Items fehlt nach dem Laden")
      local env = { T = T, Items = T.Items, events = {} }
      function env.total()
         local sum = 0
         for _, e in ipairs(env.events) do sum = sum + e.count end
         return sum
      end
      if T.Events and T.Events.On then
         T.Events.On("ITEMS_RESOLVED", function(count)
            env.events[#env.events + 1] = { count = count, at = mock.now }
         end, env)
      end
      if opts.init ~= false then
         T.Items.Init()
      end
      return env
   end

   -- Haengt sich in SetHyperlink des Scan-Tooltips ein und protokolliert (link, Zeit).
   local function recordLinks()
      local tip = rawget(_G, "TransmogScanTooltip")
      H.assert(tip ~= nil, "TransmogScanTooltip existiert nicht")
      local log = {}
      local orig = tip.SetHyperlink
      tip.SetHyperlink = function(self, link)
         log[#log + 1] = { link = link, at = mock.now }
         return orig(self, link)
      end
      return log
   end

   -- Entfernt die Auktionshaus-API (wie ein Client, dem sie fehlt); vor Items.Init rufen.
   local function removeAuctionApi()
      local g = _G
      g.GetAuctionItemClasses = nil
      g.GetAuctionItemSubClasses = nil
   end

   -- Wie oft wurde irgendetwas abgefragt?
   local function totalQueries()
      local n = 0
      for _, c in pairs(mock.itemQueries) do n = n + c end
      return n
   end

   local function idle()
      return #mock.UpdateFrames() == 0
   end

   -- Zeit vorstellen (kleine Schritte wie ein 20-fps-Client)
   local function advance(seconds, step)
      mock.Advance(seconds, step or 0.05)
   end

   -- Bis bedingung wahr wird (max. Sekunden); Rueckgabe: vergangene Sekunden oder nil
   local function advanceUntil(cond, max)
      return mock.AdvanceUntil(cond, max or 30, 0.05)
   end

   -- =========================================================================
   H.section("Schnittstelle und Laden")
   -- =========================================================================

   H.test("API: Funktionen und Konstanten wie in SPEC 5.6", function()
      local env = setup({ init = false })
      local Items = env.Items
      for _, fn in ipairs({ "Init", "Info", "Request", "RequestMany", "IsResolved", "PendingCount", "Get",
                            "Link", "TypeKeyFromNames", "TypeLabel", "IsNever" }) do
         H.eq(type(Items[fn]), "function", "Items." .. fn)
      end
      H.deepEq(Items.ARMOR_TYPES, { 401, 402, 403, 404 })
      H.deepEq(Items.ARMOR_ORDER, { 404, 403, 402, 401 })
      local count = 0
      for _, loc in ipairs({ "INVTYPE_BAG", "INVTYPE_RELIC", "INVTYPE_FINGER", "INVTYPE_TRINKET",
                             "INVTYPE_AMMO", "INVTYPE_QUIVER", "INVTYPE_NECK" }) do
         H.truthy(Items.NEVER[loc], "NEVER." .. loc)
      end
      for _ in pairs(Items.NEVER) do count = count + 1 end
      H.eq(count, 7, "genau 7 NEVER-Eintraege")
   end)

   H.test("Laden: keine Frames, keine Abfragen, nichts Spielabhaengiges", function()
      local env = setup({ init = false })
      H.eq(rawget(_G, "TransmogScanTooltip"), nil, "Scan-Tooltip erst bei Init/Bedarf")
      H.eq(env.Items.PendingCount(), 0)
      H.eq(totalQueries(), 0)
      H.truthy(idle(), "kein OnUpdate-Frame aktiv")
      advance(2)
      H.eq(totalQueries(), 0)
   end)

   H.test("Init: legt Scan-Tooltip + versteckten Poll-Frame an, ist idempotent", function()
      local env = setup({ init = false })
      env.Items.Init()
      env.Items.Init()
      env.Items.Init()
      local tip = rawget(_G, "TransmogScanTooltip")
      H.truthy(tip, "TransmogScanTooltip")
      H.eq(tip:GetObjectType(), "GameTooltip")
      H.eq(tip:GetParent(), UIParent)
      H.truthy(idle(), "Poll-Frame laeuft nicht ohne Arbeit")
      advance(1)
      H.truthy(idle())
      -- genau ein benannter Scan-Tooltip
      local n = 0
      for _, f in ipairs(mock.frames) do
         if f.__name == "TransmogScanTooltip" then n = n + 1 end
      end
      H.eq(n, 1, "ein Scan-Tooltip")
   end)

   H.test("Funktioniert ohne Util/Events (einzeln geladen)", function()
      local env = setup({ skip = { ["Core\\Util.lua"] = true, ["Core\\Events.lua"] = true,
                                    ["Core\\DB.lua"] = true, ["Core\\Slots.lua"] = true } })
      local Items = env.Items
      put(11, "Alone", "Armor", "Plate", "INVTYPE_HEAD")
      Items.Request(11)
      advance(1)
      H.truthy(Items.IsResolved(11))
      H.eq(Items.TypeKeyFromNames("Armor", "Plate"), 404)
      H.eq(Items.TypeKeyFromNames("Armor", "ZZZ"), nil)
   end)

   -- =========================================================================
   H.section("Info / Get / Request")
   -- =========================================================================

   H.test("Info: reiner Cache-Lookup, loest nie eine Abfrage aus", function()
      local env = setup()
      local Items = env.Items
      put(101)
      H.eq(Items.Info(101), nil)
      H.eq(Items.IsResolved(101), false)
      H.eq(Items.PendingCount(), 0)
      advance(2)
      H.eq(mock.itemQueries[101], nil, "keine SetHyperlink-Abfrage durch Info")
      H.eq(Items.PendingCount(), 0)
      H.eq(env.total(), 0)
   end)

   H.test("Info: vollstaendiger Datensatz laut SPEC", function()
      local env = setup()
      local Items = env.Items
      put(102, "Helm of Testing", "Armor", "Plate", "INVTYPE_HEAD",
         { quality = 4, ilvl = 213, minLevel = 80, icon = "Interface\\Icons\\INV_Helmet_70" })
      mock.CacheItem(102)
      local info = Items.Info(102)
      H.truthy(info, "Info liefert nach CacheItem einen Datensatz")
      H.eq(info.id, 102)
      H.eq(info.name, "Helm of Testing")
      H.eq(info.link, select(2, GetItemInfo(102)), "echter Link")
      H.eq(info.quality, 4)
      H.eq(info.ilvl, 213)
      H.eq(info.minLevel, 80)
      H.eq(info.typeName, "Armor")
      H.eq(info.subtypeName, "Plate")
      H.eq(info.equipLoc, "INVTYPE_HEAD")
      H.eq(info.icon, "Interface\\Icons\\INV_Helmet_70")
      H.eq(info.typeKey, 404)
      H.eq(Items.IsResolved(102), true)
      -- reiner Lookup: weder Abfrage noch Warteschlange
      H.eq(mock.itemQueries[102], nil)
      H.eq(Items.PendingCount(), 0)
   end)

   H.test("Info: eigener Cache - Ergebnis bleibt, auch wenn der Client es vergisst", function()
      local env = setup()
      local Items = env.Items
      put(103, "Keeper")
      mock.CacheItem(103)
      local a = Items.Info(103)
      mock.UncacheItem(103)
      H.eq(Items.Info(103), a, "gleiche Tabelle aus dem eigenen Cache")
      H.eq(Items.IsResolved(103), true)
   end)

   H.test("Info: fehlende optionale Felder werden aufgefuellt (Typ-Strings, Link, Icon)", function()
      local env = setup()
      local Items = env.Items
      -- Attrappe liefert "" fuer fehlende Klasse; Icon fehlt -> Fragezeichen
      mock.items[104] = { name = "Bare", quality = 1 }
      mock.CacheItem(104)
      local info = Items.Info(104)
      H.truthy(info)
      H.eq(info.typeName, "")
      H.eq(info.subtypeName, "")
      H.eq(info.equipLoc, "")
      H.eq(info.typeKey, nil)
      H.eq(type(info.icon), "string")
      H.neq(info.icon, "")
      H.eq(type(info.link), "string")
   end)

   H.test("Request: stellt in Warteschlange, sendet per SetHyperlink (Besitzer gesetzt), loest auf, feuert genau einmal", function()
      local env = setup()
      local Items = env.Items
      local log = recordLinks()
      put(201, "Queried Item", "Weapon", "Daggers", "INVTYPE_WEAPON")
      H.eq(Items.Request(201), false, "noch nicht aufgeloest")
      H.eq(Items.PendingCount(), 1)
      H.eq(Items.IsResolved(201), false)
      H.falsy(idle(), "Poll-Frame laeuft, solange etwas aussteht")
      advance(0.2)
      H.eq(mock.itemQueries[201], 1, "genau eine Abfrage")
      H.eq(#log, 1)
      H.eq(log[1].link, "item:201", "SetHyperlink('item:'..id)")
      local tip = rawget(_G, "TransmogScanTooltip")
      H.eq(tip:GetOwner(), UIParent, "SetOwner(UIParent, ...)")
      if tip.__anchorType ~= nil then      -- Interna der Attrappe: nur pruefen, wenn vorhanden
         H.eq(tip.__anchorType, "ANCHOR_NONE")
      end
      H.eq(Items.PendingCount(), 1, "gesendet, aber noch ohne Antwort")
      advance(1)
      H.eq(Items.IsResolved(201), true)
      H.eq(Items.PendingCount(), 0)
      H.eq(#env.events, 1, "ein ITEMS_RESOLVED")
      H.eq(env.events[1].count, 1)
      H.eq(Items.Info(201).typeKey, 215)
      H.truthy(idle(), "Poll-Frame versteckt sich")
      H.eq(#mock.TakeErrors(), 0)
   end)

   H.test("Request: idempotent (mehrfach, als String, in RequestMany) -> eine Abfrage", function()
      local env = setup()
      local Items = env.Items
      put(301)
      for _ = 1, 10 do
         Items.Request(301)
      end
      Items.Request("301")
      Items.RequestMany({ 301, 301, "301" })
      H.eq(Items.PendingCount(), 1)
      advance(0.3)
      H.eq(Items.PendingCount(), 1, "in Abfrage (Antwort noch nicht da)")
      Items.Request(301)
      Items.Get(301)
      H.eq(Items.PendingCount(), 1, "auch waehrend der Abfrage idempotent")
      advance(2)
      H.eq(mock.itemQueries[301], 1, "genau eine Abfrage insgesamt")
      H.eq(Items.PendingCount(), 0)
      -- aufgeloest: weiteres Request ist kostenlos
      H.eq(Items.Request(301), true)
      advance(1)
      H.eq(mock.itemQueries[301], 1)
      H.eq(env.total(), 1, "kein zweites ITEMS_RESOLVED")
   end)

   H.test("Request: liegt der Gegenstand schon im Client-Cache -> keine Abfrage, aber ITEMS_RESOLVED", function()
      local env = setup()
      local Items = env.Items
      put(401)
      mock.CacheItem(401)
      H.eq(Items.Request(401), true)
      H.truthy(Items.Info(401))
      advance(1)
      H.eq(mock.itemQueries[401], nil, "kein SetHyperlink")
      H.eq(Items.PendingCount(), 0)
      H.eq(env.total(), 1, "Aufloesung wird gemeldet (Aufrufer warten auf das Ereignis)")
      H.truthy(idle())
   end)

   H.test("Get: Info, sonst Request (ohne doppelt anzustellen)", function()
      local env = setup()
      local Items = env.Items
      put(501)
      put(502)
      H.eq(Items.Get(501), nil)
      H.eq(Items.PendingCount(), 1)
      H.eq(Items.Get(501), nil)
      H.eq(Items.PendingCount(), 1, "zweites Get stellt nicht erneut an")
      mock.CacheItem(502)
      local info = Items.Get(502)
      H.truthy(info)
      H.eq(info.id, 502)
      H.eq(Items.PendingCount(), 1, "bekannter Gegenstand wird nicht angefragt")
      advance(2)
      H.eq(mock.itemQueries[501], 1)
      H.eq(mock.itemQueries[502], nil)
      H.truthy(Items.Get(501))
   end)

   H.test("Info auf einen wartenden Gegenstand, den der Client inzwischen kennt: zaehlt als aufgeloest", function()
      local env = setup()
      local Items = env.Items
      put(601)
      putRange(602, 640)
      Items.Request(601)
      Items.Request(602)
      mock.CacheItem(601)        -- Antwort kam anderweitig (z.B. durch einen Tooltip)
      H.truthy(Items.Info(601))
      H.eq(Items.PendingCount(), 1, "601 ist nicht mehr ausstehend")
      advance(2)
      H.eq(mock.itemQueries[601], nil, "bereits bekannt -> nie gesendet")
      H.eq(env.total(), 2, "601 und 602 gemeldet")
      H.eq(Items.PendingCount(), 0)
      H.truthy(idle())
   end)

   H.test("Warteschlange: im Client-Cache auftauchende Eintraege werden uebersprungen (lazy), nichts geht verloren", function()
      local env = setup()
      local Items = env.Items
      putRange(700, 739)
      local ids = {}
      for id = 700, 739 do ids[#ids + 1] = id end
      Items.RequestMany(ids)
      mock.CacheItem(703)
      mock.CacheItem(725)
      advance(10)
      H.eq(mock.itemQueries[703], nil)
      H.eq(mock.itemQueries[725], nil)
      H.eq(totalQueries(), 38)
      for id = 700, 739 do
         H.truthy(Items.IsResolved(id), "aufgeloest: " .. id)
      end
      H.eq(env.total(), 40)
      H.eq(Items.PendingCount(), 0)
      H.truthy(idle())
   end)

   H.test("RequestMany: Duplikate, Strings, Links, Muell und Nicht-Tabellen", function()
      local env = setup()
      local Items = env.Items
      putRange(801, 804)
      Items.RequestMany({ 801, 802, "803", "item:804", 0, -1, "x", {}, true, 801 })
      H.eq(Items.PendingCount(), 4)
      Items.RequestMany(nil)
      Items.RequestMany("abc")
      Items.RequestMany(42)
      Items.RequestMany({})
      H.eq(Items.PendingCount(), 4)
      advance(2)
      for id = 801, 804 do
         H.eq(mock.itemQueries[id], 1, "eine Abfrage fuer " .. id)
      end
      H.eq(totalQueries(), 4)
      H.eq(#mock.TakeErrors(), 0)
   end)

   -- =========================================================================
   H.section("Drosselung, Reihenfolge, Zeitverhalten")
   -- =========================================================================

   H.test("Drosselung: nie mehr als 25 SetHyperlink je 0.1 s (gleitendes Fenster)", function()
      local env = setup()
      local Items = env.Items
      local log = recordLinks()
      local ids = {}
      putRange(1000, 1099)
      for id = 1000, 1099 do ids[#ids + 1] = id end
      Items.RequestMany(ids)
      advance(0.5)
      H.eq(#log, 100, "alle 100 sind innerhalb von 0.5 s gesendet (Durchsatz 25 je 0.1 s)")
      for i = 1, #log - 25 do
         if log[i + 25].at - log[i].at < 0.1 - 1e-6 then
            H.fail(("mehr als 25 Abfragen innerhalb 0.1 s (ab Nr. %d: %.3f s)"):format(i,
               log[i + 25].at - log[i].at))
            break
         end
      end
      advance(2)
      H.eq(env.total(), 100)
   end)

   H.test("Drosselung: 1000 Ids werden in ~4 s gesendet, nie mehr als 25 je Takt, auch mit 0.01-s-Schritten", function()
      local env = setup()
      local Items = env.Items
      local log = recordLinks()
      putRange(2000, 2999)
      local ids = {}
      for id = 2000, 2999 do ids[#ids + 1] = id end
      Items.RequestMany(ids)
      mock.Advance(6, 0.01)
      H.eq(#log, 1000)
      H.truthy(log[#log].at - log[1].at >= 3.9 - 1e-6, "1000/25 = 40 Takte = 3.9 s Mindestdauer")
      for i = 1, #log - 25 do
         if log[i + 25].at - log[i].at < 0.1 - 1e-6 then
            H.fail("Drosselung verletzt bei Nr. " .. i)
            break
         end
      end
   end)

   H.test("Drosselung: ein langer Frame (grosses elapsed) schickt trotzdem nur 25", function()
      local env = setup()
      local Items = env.Items
      putRange(3000, 3059)
      local ids = {}
      for id = 3000, 3059 do ids[#ids + 1] = id end
      Items.RequestMany(ids)
      mock.Advance(5, 5)       -- ein einziger OnUpdate mit elapsed = 5
      H.eq(totalQueries(), 25)
   end)

   H.test("Reihenfolge: FIFO, ein erneutes Request ordnet nicht um", function()
      local env = setup()
      local Items = env.Items
      local log = recordLinks()
      for _, id in ipairs({ 55, 33, 99, 11, 77 }) do put(id) end
      Items.RequestMany({ 55, 33, 99 })
      Items.Request(11)
      Items.Request(55)
      Items.Request(77)
      Items.Request(33)
      advance(1)
      local order = {}
      for i, e in ipairs(log) do order[i] = e.link end
      H.deepEq(order, { "item:55", "item:33", "item:99", "item:11", "item:77" })
   end)

   H.test("Aufgeben: nach 20 s failed, kein Dauerpolling, Wiederholung fruehestens nach 60 s", function()
      local env = setup()
      local Items = env.Items
      -- Gegenstand 4001 existiert nicht: der Server antwortet nie
      Items.Request(4001)
      advance(0.2)
      H.eq(mock.itemQueries[4001], 1)
      local sentAt = mock.now
      advance(18)
      H.eq(Items.IsFailed(4001), false, "nach ~18 s noch nicht aufgegeben")
      H.eq(Items.PendingCount(), 1)
      H.falsy(idle(), "wartet noch")
      advance(3)
      H.eq(Items.IsFailed(4001), true, "nach >20 s aufgegeben")
      H.eq(Items.PendingCount(), 0)
      H.eq(Items.FailedCount(), 1)
      H.truthy(mock.now - sentAt >= 20, "nicht frueher als 20 s")
      H.truthy(idle(), "Poll-Frame schlaeft nach dem Aufgeben")
      local failedAt = mock.now

      -- innerhalb von 60 s: kein erneuter Versuch
      advance(30)
      Items.Request(4001)
      Items.Get(4001)
      advance(2)
      H.eq(mock.itemQueries[4001], 1, "noch keine Wiederholung")
      H.eq(Items.PendingCount(), 0)
      H.truthy(idle())

      -- nach 60 s: neuer Versuch
      local rest = failedAt + 61 - mock.now
      if rest > 0 then advance(rest) end
      Items.Request(4001)
      advance(0.3)
      H.eq(mock.itemQueries[4001], 2, "Wiederholung nach 60 s")
      H.eq(Items.IsFailed(4001), false)
      H.eq(Items.PendingCount(), 1)
   end)

   H.test("Aufgeben: Frist von 20 s gilt ab dem Senden, nicht ab Request (lange Warteschlange)", function()
      local env = setup()
      local Items = env.Items
      -- 250 nicht existierende Ids: der letzte wird erst nach 10 Takten (1 s) gesendet
      local ids = {}
      for id = 5000, 5249 do ids[#ids + 1] = id end
      Items.RequestMany(ids)
      advance(1.5)
      H.eq(totalQueries(), 250)
      H.eq(Items.PendingCount(), 250)
      advance(19)             -- ~20.5 s nach Request, aber < 20 s nach dem letzten Senden
      -- die letzten Ids wurden fruehestens bei ~0.95 s gesendet -> noch nicht alle aufgegeben
      local failed = Items.FailedCount()
      H.truthy(failed < 250, "Frist laeuft je Id ab ihrem Senden (failed=" .. failed .. ")")
      advance(3)
      H.eq(Items.FailedCount(), 250)
      H.eq(Items.PendingCount(), 0)
      H.truthy(idle())
   end)

   H.test("Nachzuegler: Antwort nach dem Aufgeben wird bei Info erkannt, failed verschwindet, ITEMS_RESOLVED", function()
      local env = setup({ world = { itemCacheDelay = 40 } })
      local Items = env.Items
      put(4100, "Slow One")
      Items.Request(4100)
      advance(0.2)
      H.eq(advanceUntil(function() return Items.IsFailed(4100) end, 30) ~= nil, true, "wird aufgegeben")
      H.eq(Items.FailedCount(), 1)
      H.eq(Items.Info(4100), nil, "noch nicht angekommen")
      advance(25)
      local info = Items.Info(4100)
      H.truthy(info, "Nachzuegler wird erkannt")
      H.eq(Items.IsFailed(4100), false)
      H.eq(Items.FailedCount(), 0)
      H.eq(Items.PendingCount(), 0)
      advance(0.5)
      H.eq(env.total(), 1, "Aufloesung des Nachzueglers gemeldet")
      H.truthy(idle())
   end)

   H.test("Aufgeben und Wiederholen: kommt die Antwort bei der Wiederholung, ist der Gegenstand da", function()
      local env = setup()
      local Items = env.Items
      put(4200, "Late Bloomer")
      -- erste Runde: Gegenstand ist dem Server (noch) unbekannt
      local saved = mock.items[4200]
      mock.items[4200] = nil
      Items.Request(4200)
      H.truthy(advanceUntil(function() return Items.IsFailed(4200) end, 30))
      local t0 = mock.now
      -- Server kennt ihn jetzt
      mock.items[4200] = saved
      advance(61)
      H.truthy(mock.now - t0 >= 60)
      Items.Request(4200)
      advance(1)
      H.truthy(Items.IsResolved(4200))
      H.eq(Items.FailedCount(), 0)
      H.eq(env.total(), 1)
   end)

   H.test("ITEMS_RESOLVED: gebuendelt (max 5/s), Zaehler summieren sich, nie vor Aufloesung", function()
      local env = setup()
      local Items = env.Items
      putRange(6000, 6299)
      local ids = {}
      for id = 6000, 6299 do ids[#ids + 1] = id end
      Items.RequestMany(ids)
      advance(20)
      H.eq(env.total(), 300, "Summe der Zaehler = Anzahl aufgeloester Items")
      H.truthy(#env.events >= 2, "mehrere Ereignisse")
      H.truthy(#env.events < 60, "gebuendelt, nicht je Item")
      for i = 1, #env.events - 5 do
         if env.events[i + 5].at - env.events[i].at < 1.0 - 1e-6 then
            H.fail(("mehr als 5 ITEMS_RESOLVED je Sekunde (ab Nr. %d)"):format(i))
            break
         end
      end
      for i = 2, #env.events do
         H.truthy(env.events[i].at - env.events[i - 1].at >= 0.2 - 1e-6, "Mindestabstand 0.2 s")
      end
      for _, e in ipairs(env.events) do
         H.truthy(e.count >= 1, "Zaehler >= 1")
      end
      H.eq(Items.PendingCount(), 0)
      H.truthy(idle())
   end)

   H.test("ITEMS_RESOLVED: wird nicht ohne neue Aufloesung wiederholt", function()
      local env = setup()
      local Items = env.Items
      put(6500)
      Items.Request(6500)
      advance(2)
      H.eq(#env.events, 1)
      advance(10)
      H.eq(#env.events, 1)
      Items.Request(6500)
      Items.Info(6500)
      Items.Get(6500)
      advance(2)
      H.eq(#env.events, 1)
   end)

   H.test("Poll-Frame: aktiv nur solange Arbeit ansteht, danach versteckt (SPEC Regel 9)", function()
      local env = setup()
      local Items = env.Items
      H.truthy(idle())
      putRange(7000, 7009)
      Items.Request(7000)
      H.falsy(idle(), "nach Request aktiv")
      advance(0.2)
      H.falsy(idle(), "waehrend der Abfrage aktiv")
      advance(2)
      H.truthy(idle(), "nach Aufloesung und Ereignis versteckt")
      -- erneut aufwecken
      Items.Request(7001)
      H.falsy(idle())
      advance(2)
      H.truthy(idle())
      -- viele Sekunden Leerlauf ohne Frame-Arbeit
      advance(30)
      H.truthy(idle())
      H.eq(#mock.TakeErrors(), 0)
   end)

   H.test("Handler duerfen im Ereignis neue Abfragen stellen: Poll-Frame schlaeft nicht zu frueh ein", function()
      local env = setup()
      local Items = env.Items
      putRange(7100, 7149)
      local nextId = 7101
      env.T.Events.On("ITEMS_RESOLVED", function()
         -- jede Aufloesung loest die naechste Anfrage aus (Kette ueber 49 Items)
         if nextId <= 7149 then
            local id = nextId
            nextId = nextId + 1
            Items.Request(id)
         end
      end, "chain")
      Items.Request(7100)
      advance(60)
      for id = 7100, 7149 do
         H.truthy(Items.IsResolved(id), "Kettenglied " .. id)
      end
      H.eq(Items.PendingCount(), 0)
      H.truthy(idle())
   end)

   H.test("Handler-Fehler stoeren den Poll-Takt nicht", function()
      H.allowErrors()
      local env = setup()
      local Items = env.Items
      env.T.Events.On("ITEMS_RESOLVED", function() error("Handler kaputt") end, "bad")
      putRange(7200, 7210)
      local ids = {}
      for id = 7200, 7210 do ids[#ids + 1] = id end
      Items.RequestMany(ids)
      advance(5)
      for id = 7200, 7210 do
         H.truthy(Items.IsResolved(id))
      end
      H.eq(Items.PendingCount(), 0)
      H.truthy(idle())
      H.truthy(env.total() == 11, "andere Handler bekommen weiter ihre Ereignisse")
      mock.TakeErrors()
   end)

   H.test("SetHyperlink wirft: kein Fehler nach aussen, Gegenstand wird nach 20 s aufgegeben", function()
      local env = setup()
      local Items = env.Items
      put(7300)
      local tip = rawget(_G, "TransmogScanTooltip")
      tip.SetHyperlink = function() error("boom") end
      Items.Request(7300)
      advance(1)
      H.eq(#mock.TakeErrors(), 0)
      H.eq(Items.PendingCount(), 1)
      advance(25)
      H.eq(Items.IsFailed(7300), true)
      H.eq(Items.PendingCount(), 0)
      H.truthy(idle())
      H.eq(#mock.TakeErrors(), 0)
   end)

   H.test("Besitzer des Scan-Tooltips wird bei Verlust neu gesetzt (SetHyperlink braucht einen Besitzer)", function()
      local env = setup()
      local Items = env.Items
      putRange(7400, 7449)
      local tip = rawget(_G, "TransmogScanTooltip")
      -- wie im Spiel: der Besitzer geht verloren (z.B. wird verborgen/neu gesetzt)
      tip.__owner = nil
      local ids = {}
      for id = 7400, 7449 do ids[#ids + 1] = id end
      Items.RequestMany(ids)
      advance(0.2)
      H.eq(#mock.TakeErrors(), 0, "kein 'no owner'-Fehler")
      H.truthy(totalQueries() >= 25, "Abfragen gehen trotzdem raus")
      tip.__owner = nil
      advance(5)
      for id = 7400, 7449 do
         H.truthy(Items.IsResolved(id))
      end
   end)

   -- =========================================================================
   H.section("Ids: Strings, Links, ungueltige Werte, HIDDEN")
   -- =========================================================================

   H.test("Ids als String / item:-String / voller Link werden wie Zahlen behandelt", function()
      local env = setup()
      local Items = env.Items
      put(8001, "By String")
      put(8002, "By Item")
      put(8003, "By Link")
      mock.CacheItem(8001)
      H.truthy(Items.Info("8001"))
      H.eq(Items.Info("8001").id, 8001)
      H.eq(Items.Info("8001"), Items.Info(8001), "dieselbe Tabelle")
      H.eq(Items.IsResolved("8001"), true)
      H.eq(Items.Link("8001"), select(2, GetItemInfo(8001)))

      Items.Request("item:8002:0:0:0")
      local link = "|cff1eff00|Hitem:8003:0:0:0:0:0:0:0:0|h[By Link]|h|r"
      Items.Request(link)
      Items.Get("8002")
      H.eq(Items.PendingCount(), 2)
      advance(2)
      H.eq(mock.itemQueries[8002], 1)
      H.eq(mock.itemQueries[8003], 1)
      H.truthy(Items.Info(8002))
      H.truthy(Items.Info(link))
      H.eq(Items.Info(link).id, 8003)
   end)

   H.test("Ungueltige Ids: nil/leer/0/negativ/NaN/inf/Tabellen -> sicher, nichts angefragt", function()
      local env = setup()
      local Items = env.Items
      local nan = 0 / 0
      local bad = { "nil", "", " ", "abc", "item:", "item:abc", 0, -1, -123456, 0.5, nan, math.huge,
                    -math.huge, 2147483648, 1e300, true, false, {}, print }
      for i, v in ipairs(bad) do
         local ok, err = pcall(function()
            H.eq(Items.Info(v), nil, "Info #" .. i)
            H.eq(Items.IsResolved(v), false, "IsResolved #" .. i)
            H.eq(Items.Get(v), nil, "Get #" .. i)
            Items.Request(v)
            H.eq(Items.Link(v), "", "Link #" .. i)
         end)
         H.truthy(ok, "kein Fehler bei Eingabe #" .. i .. ": " .. tostring(err))
      end
      -- nil als Argument
      H.eq(Items.Info(nil), nil)
      H.eq(Items.IsResolved(nil), false)
      H.eq(Items.Get(nil), nil)
      H.eq(Items.Link(nil), "")
      Items.Request(nil)
      Items.RequestMany({ nan, math.huge, "x" })
      H.eq(Items.PendingCount(), 0)
      advance(2)
      H.eq(totalQueries(), 0)
   end)

   H.test("HIDDEN_ID (999999) ist ein Pseudo-Item: nie abgefragt, nie in der Warteschlange", function()
      local env = setup()
      local Items = env.Items
      H.eq(env.T.HIDDEN_ID, 999999)
      put(999999, "Hidden", "Armor", "Cloth", "INVTYPE_HEAD")
      Items.Request(999999)
      Items.Request("999999")
      Items.RequestMany({ 999999, 999999 })
      H.eq(Items.Get(999999), nil)
      H.eq(Items.PendingCount(), 0)
      advance(2)
      H.eq(mock.itemQueries[999999], nil)
      H.truthy(idle())
   end)

   H.test("Link: echter Link wenn bekannt, sonst item:ID; fragt nie an", function()
      local env = setup()
      local Items = env.Items
      put(8100, "Linked")
      H.eq(Items.Link(8100), "item:8100")
      H.eq(Items.Link("8100"), "item:8100")
      H.eq(mock.itemQueries[8100], nil, "Link loest keine Abfrage aus")
      H.eq(Items.PendingCount(), 0)
      mock.CacheItem(8100)
      H.eq(Items.Link(8100), select(2, GetItemInfo(8100)))
      H.matches(Items.Link(8100), "|Hitem:8100:")
      -- unbekannte, nie angefragte Id
      H.eq(Items.Link(123456), "item:123456")
      H.eq(type(Items.Link(123456)), "string")
   end)

   -- =========================================================================
   H.section("typeKey: Auktionshaus-Listen und Rueckfall")
   -- =========================================================================

   -- Prueft eine komplette Namensliste (Waffe und Ruestung) gegen die erwarteten Schluessel.
   local function checkAllNames(Items, def, label)
      for i, name in ipairs(def.weapon) do
         H.eq(Items.TypeKeyFromNames(def.classes[1], name), WEAPON_KEYS[i], label .. " Waffe " .. name)
      end
      for i, name in ipairs(def.armor) do
         H.eq(Items.TypeKeyFromNames(def.classes[2], name), ARMOR_KEYS[i], label .. " Ruestung " .. name)
      end
   end

   H.test("enUS-AH-Liste: alle 17 Waffen- und 10 Ruestungstypen -> echte Schluessel", function()
      local env = setup()      -- Attrappe liefert standardmaessig die enUS-Liste
      checkAllNames(env.Items, EN, "enUS")
      -- Miscellaneous: Waffe 214, Ruestung 400
      H.eq(env.Items.TypeKeyFromNames("Weapon", "Miscellaneous"), 214)
      H.eq(env.Items.TypeKeyFromNames("Armor", "Miscellaneous"), 400)
   end)

   H.test("deDE-AH-Liste (echte Namen, 'Schwere Rüstung'): alle Typen, Verschiedenes je Klasse", function()
      local env = setup({ world = { locale = "deDE", auctionLists = ahLists(DE) } })
      checkAllNames(env.Items, DE, "deDE")
      H.eq(env.Items.TypeKeyFromNames("Waffe", "Verschiedenes"), 214)
      H.eq(env.Items.TypeKeyFromNames("Rüstung", "Verschiedenes"), 400)
      H.eq(env.Items.TypeKeyFromNames("Rüstung", "Schwere Rüstung"), 403)
      H.eq(env.Items.TypeKeyFromNames("Rüstung", "Platte"), 404)
      -- englische Namen auf einem deutschen Client sind trotzdem eindeutig (Namenstabelle)
      H.eq(env.Items.TypeKeyFromNames("Armor", "Plate"), 404)
   end)

   H.test("deDE mit der Attrappen-Liste ('Kette' statt 'Schwere Rüstung', 'Bögen'): Position entscheidet", function()
      local env = setup({ world = { locale = "deDE", auctionLists = mock.AUCTION_DE } })
      local Items = env.Items
      H.eq(Items.TypeKeyFromNames("Rüstung", "Kette"), 403)
      H.eq(Items.TypeKeyFromNames("Rüstung", "Platte"), 404)
      H.eq(Items.TypeKeyFromNames("Waffe", "Bögen"), 202)
      H.eq(Items.TypeKeyFromNames("Waffe", "Verschiedenes"), 214)
      H.eq(Items.TypeKeyFromNames("Rüstung", "Verschiedenes"), 400)
   end)

   H.test("fremde Sprache (Namen unbekannt): die AH-Position liefert die Schluessel", function()
      local weapon, armor = {}, {}
      for i = 1, 17 do weapon[i] = "KR_W" .. i end
      for i = 1, 10 do armor[i] = "KR_A" .. i end
      local KR = { classes = { "KR_Weapon", "KR_Armor" }, weapon = weapon, armor = armor }
      local env = setup({ world = { locale = "koKR", auctionLists = ahLists(KR) } })
      checkAllNames(env.Items, KR, "koKR")
      H.eq(env.Items.TypeLabel(403), "KR_A4")
      H.eq(env.Items.TypeLabel(214), "KR_W12")
      H.eq(env.Items.TypeKeyFromNames("KR_Container", "Bag"), nil)
   end)

   H.test("Ende-zu-Ende: aufgeloeste Gegenstaende erhalten den typeKey (enUS und deDE)", function()
      local env = setup({ world = { locale = "deDE", auctionLists = ahLists(DE) } })
      local Items = env.Items
      put(9001, "Plattenhelm", "Rüstung", "Platte", "INVTYPE_HEAD")
      put(9002, "Kettenhemd", "Rüstung", "Schwere Rüstung", "INVTYPE_CHEST")
      put(9003, "Hemd", "Rüstung", "Verschiedenes", "INVTYPE_BODY")
      put(9004, "Angel", "Waffe", "Verschiedenes", "INVTYPE_2HWEAPON")
      put(9005, "Dolch", "Waffe", "Dolche", "INVTYPE_WEAPON")
      put(9006, "Tasche", "Behälter", "Tasche", "INVTYPE_BAG")
      put(9007, "Pfeil", "Projektil", "Pfeil", "INVTYPE_AMMO")
      put(9008, "Verschiedenes", "Verschiedenes", "Plunder", "")
      for id = 9001, 9008 do mock.CacheItem(id) end
      H.eq(Items.Info(9001).typeKey, 404)
      H.eq(Items.Info(9002).typeKey, 403)
      H.eq(Items.Info(9003).typeKey, 400)
      H.eq(Items.Info(9004).typeKey, 214)
      H.eq(Items.Info(9005).typeKey, 215)
      H.eq(Items.Info(9006).typeKey, nil, "Behaelter hat keinen typeKey")
      H.eq(Items.Info(9007).typeKey, nil, "Projektil hat keinen typeKey")
      H.eq(Items.Info(9008).typeKey, nil, "Klasse Verschiedenes (Item) ist nicht Ruestung/Waffe")
      H.eq(Items.Info(9001).typeName, "Rüstung", "lokalisierter Name bleibt erhalten")
      H.eq(Items.Info(9001).subtypeName, "Platte")
   end)

   H.test("Rueckfall ohne AH-API: alle bekannten Namen (enUS, deDE, esES, ruRU) ueber die Tabellen", function()
      -- Auktionshaus-API nicht verfuegbar (schon vor Init): nur die Fallback-Tabellen
      local env = setup({ init = false })
      local Items = env.Items
      removeAuctionApi()
      Items.Init()
      checkAllNames(Items, EN, "fallback enUS")
      checkAllNames(Items, DE, "fallback deDE")
      checkAllNames(Items, ES, "fallback esES")
      checkAllNames(Items, RU, "fallback ruRU")
      -- Klassenname fehlt: Ausruestungsplatz entscheidet (Verschiedenes ist mehrdeutig)
      H.eq(Items.TypeKeyFromNames(nil, "Verschiedenes", "INVTYPE_WEAPON"), 214)
      H.eq(Items.TypeKeyFromNames(nil, "Verschiedenes", "INVTYPE_BODY"), 400)
      H.eq(Items.TypeKeyFromNames(nil, "Verschiedenes"), nil, "ohne Klasse und Platz mehrdeutig -> nil")
   end)

   H.test("Rueckfall bei leerer AH-Klassenliste: Items.Init liest nicht, Namen funktionieren trotzdem", function()
      local env = setup({ world = { locale = "deDE", auctionLists = { classes = {}, subclasses = {} } } })
      local Items = env.Items
      checkAllNames(Items, DE, "leere Liste deDE")
      H.eq(Items.TypeKeyFromNames("Rüstung", "Schwere Rüstung"), 403)
      H.eq(Items.TypeKeyFromNames("Waffe", "Verschiedenes"), 214)
      H.eq(Items.TypeKeyFromNames("Rüstung", "Verschiedenes"), 400)
      H.eq(Items.TypeKeyFromNames("Rüstung", "Unbekannt"), nil)
   end)

   H.test("falsche Listenlaenge -> AH-Reihenfolge wird NICHT benutzt, Rueckfall ueber Namen", function()
      -- Waffenliste mit 16 statt 17 Eintraegen (Wands fehlt) und einem erfundenen Namen an
      -- Position 12; Ruestungsliste mit 11 Eintraegen.
      local weapon = copyList(EN.weapon)
      table.remove(weapon, 16)
      weapon[12] = "Zork"
      local armor = copyList(EN.armor)
      armor[#armor + 1] = "Extra"
      local LISTS = ahLists({ classes = EN.classes, weapon = weapon, armor = armor })
      local env = setup({ world = { auctionLists = LISTS } })
      local Items = env.Items
      -- Positionsabbildung waere hier falsch (versetzt); die Namen muessen die echten Schluessel geben
      H.eq(Items.TypeKeyFromNames("Weapon", "Daggers"), 215)
      H.eq(Items.TypeKeyFromNames("Weapon", "Thrown"), 216)
      H.eq(Items.TypeKeyFromNames("Weapon", "Crossbows"), 218)
      H.eq(Items.TypeKeyFromNames("Weapon", "Fishing Poles"), 220)
      H.eq(Items.TypeKeyFromNames("Armor", "Mail"), 403)
      H.eq(Items.TypeKeyFromNames("Armor", "Plate"), 404)
      H.eq(Items.TypeKeyFromNames("Armor", "Sigils"), 410)
      -- unbekannte Namen bleiben nil: keine Reihenfolge-Annahme
      H.eq(Items.TypeKeyFromNames("Weapon", "Zork"), nil)
      H.eq(Items.TypeKeyFromNames("Armor", "Extra"), nil)
      -- Namen aus der fehlerhaften Liste liefern keine Labels der (falschen) Positionen
      H.neq(Items.TypeLabel(214), "Zork")
   end)

   H.test("AH-Reihenfolge widerspricht verifizierten Namen (vertauscht) -> Namenstabelle gewinnt", function()
      local weapon = copyList(EN.weapon)
      weapon[13], weapon[16] = weapon[16], weapon[13]       -- Wands <-> Daggers vertauscht
      weapon[3] = "Zork"                                    -- unbekannter Name an Position 3 (waere 202)
      local env = setup({ world = { auctionLists = ahLists({ classes = EN.classes, weapon = weapon,
                                                             armor = EN.armor }) } })
      local Items = env.Items
      H.eq(Items.TypeKeyFromNames("Weapon", "Daggers"), 215)
      H.eq(Items.TypeKeyFromNames("Weapon", "Wands"), 219)
      H.eq(Items.TypeKeyFromNames("Weapon", "Zork"), nil, "Positionsabbildung nicht angewandt")
      -- die unbeschaedigte Ruestungsliste bleibt nutzbar
      H.eq(Items.TypeKeyFromNames("Armor", "Plate"), 404)
   end)

   H.test("unbekannte Namen -> nil, kein Fehler, kein Chat-Text (auch bei Wiederholung)", function()
      local env = setup()
      local Items = env.Items
      env.T.debug = false
      for _ = 1, 5 do
         H.eq(Items.TypeKeyFromNames("Weapon", "Zork"), nil)
         H.eq(Items.TypeKeyFromNames("Armor", "Zork"), nil)
         H.eq(Items.TypeKeyFromNames("Zork", "Zork"), nil)
         H.eq(Items.TypeKeyFromNames("Weapon", ""), nil)
         H.eq(Items.TypeKeyFromNames("Weapon", nil), nil)
         H.eq(Items.TypeKeyFromNames(nil, nil), nil)
         H.eq(Items.TypeKeyFromNames(12, {}), nil)
      end
      H.eq(#mock.messages, 0, "kein Chat-Text bei unbekannten Namen")
      -- auch ueber aufgeloeste Items
      put(9100, "Mystery", "Zork", "Zork", "")
      put(9101, "Mystery 2", "Weapon", "Zork", "INVTYPE_WEAPON")
      mock.CacheItem(9100)
      mock.CacheItem(9101)
      H.eq(Items.Info(9100).typeKey, nil)
      H.eq(Items.Info(9101).typeKey, nil)
      H.eq(#mock.messages, 0)
      H.eq(#mock.TakeErrors(), 0)
   end)

   H.test("unbekannte Namen im Debug-Modus: hoechstens eine Zeile je Paar, nie Util.Error", function()
      local env = setup()
      local Items = env.Items
      env.T.debug = true
      for _ = 1, 10 do
         Items.TypeKeyFromNames("Weapon", "Zork")
         Items.TypeKeyFromNames("Armor", "Zork")
      end
      H.truthy(#mock.messages <= 2, "hoechstens 2 Debug-Zeilen, war " .. #mock.messages)
      for _, m in ipairs(mock.messages) do
         H.falsy(m:find("|cffe8654a", 1, true), "keine rote Fehlerzeile: " .. m)
      end
   end)

   H.test("Klasse eindeutig anderer Art (Behaelter, Verbrauchbar ...) -> nil, auch mit equipLoc", function()
      local env = setup()
      local Items = env.Items
      H.eq(Items.TypeKeyFromNames("Container", "Bag", "INVTYPE_BAG"), nil)
      H.eq(Items.TypeKeyFromNames("Miscellaneous", "Junk"), nil)
      H.eq(Items.TypeKeyFromNames("Consumable", "Potion", "INVTYPE_HEAD"), nil,
         "bekannte andere Klasse gewinnt gegen den Ausruestungsplatz")
      H.eq(Items.TypeKeyFromNames("Quest", "Quest"), nil)
   end)

   H.test("equipLoc als Rueckfall fuer die Klasse bei unbekanntem Klassennamen", function()
      local env = setup()
      local Items = env.Items
      H.eq(Items.TypeKeyFromNames("Zork", "Cloth", "INVTYPE_ROBE"), 401)
      H.eq(Items.TypeKeyFromNames("Zork", "Daggers", "INVTYPE_WEAPON"), 215)
      H.eq(Items.TypeKeyFromNames("Zork", "Miscellaneous", "INVTYPE_BODY"), 400)
      H.eq(Items.TypeKeyFromNames("Zork", "Miscellaneous", "INVTYPE_THROWN"), 214)
      H.eq(Items.TypeKeyFromNames("Zork", "Cloth", "INVTYPE_BAG"), nil)
      H.eq(Items.TypeKeyFromNames("Zork", "Cloth", ""), nil)
   end)

   H.test("AH-Liste erst spaeter verfuegbar: Namen werden nachgeladen, vorhandene Items neu eingestuft", function()
      local weapon, armor = {}, {}
      for i = 1, 17 do weapon[i] = "KR_W" .. i end
      for i = 1, 10 do armor[i] = "KR_A" .. i end
      local KR = { classes = { "KR_Weapon", "KR_Armor" }, weapon = weapon, armor = armor }
      local env = setup({ world = { locale = "koKR", auctionLists = { classes = {}, subclasses = {} } } })
      local Items = env.Items
      put(9200, "Korean Mail", "KR_Armor", "KR_A4", "INVTYPE_CHEST")
      mock.CacheItem(9200)
      H.eq(Items.Info(9200).typeKey, nil, "ohne AH-Liste und ohne bekannte Namen unbekannt")
      -- Liste wird verfuegbar
      mock.world.auctionLists = ahLists(KR)
      H.eq(Items.TypeLabel(403), "KR_A4", "TypeLabel stoesst den Aufbau erneut an")
      H.eq(Items.Info(9200).typeKey, 403, "bereits aufgeloestes Item wurde neu eingestuft")
   end)

   H.test("Namens-Rueckfall stimmt mit den AH-Spalten EN/DE/ES ueberein (Orakel, ohne AH-API)", function()
      local env = setup({ init = false })
      removeAuctionApi()
      env.Items.Init()
      local n = 0
      for className, classId in pairs(CLASS_IDS) do
         for subName, subId in pairs(ORACLE[classId]) do
            n = n + 1
            H.eq(env.Items.TypeKeyFromNames(className, subName), classId * 100 + subId,
               className .. " / " .. subName)
         end
      end
      H.truthy(n > 100, "Orakel nicht leer")
      -- und mit AH-Listen fuer alle drei Sprachen: dasselbe Ergebnis
      for _, def in ipairs({ EN, DE, ES }) do
         local env2 = setup({ world = { auctionLists = ahLists(def) } })
         for className, classId in pairs(CLASS_IDS) do
            for subName, subId in pairs(ORACLE[classId]) do
               H.eq(env2.Items.TypeKeyFromNames(className, subName), classId * 100 + subId,
                  def.classes[1] .. "-AH " .. className .. " / " .. subName)
            end
         end
      end
   end)

   H.test("Namens-Rueckfall: auch die Schreibweisen der Attrappen-Liste (Kette, Bögen) werden erkannt", function()
      local env = setup({ init = false })
      removeAuctionApi()
      env.Items.Init()
      H.eq(env.Items.TypeKeyFromNames("Rüstung", "Kette"), 403)
      H.eq(env.Items.TypeKeyFromNames("Rüstung", "Schwere Rüstung"), 403)
      H.eq(env.Items.TypeKeyFromNames("Waffe", "Bögen"), 202)
      H.eq(env.Items.TypeKeyFromNames("Waffe", "Bogen"), 202)
   end)

   H.test("Ende-zu-Ende enUS: alle 27 Typnamen ueber GetItemInfo-Datensaetze", function()
      local env = setup()
      local Items = env.Items
      local id = 9400
      local expect = {}
      for i, name in ipairs(EN.weapon) do
         id = id + 1
         put(id, "W " .. name, "Weapon", name, "INVTYPE_WEAPON")
         mock.CacheItem(id)
         expect[id] = WEAPON_KEYS[i]
      end
      for i, name in ipairs(EN.armor) do
         id = id + 1
         put(id, "A " .. name, "Armor", name, "INVTYPE_CHEST")
         mock.CacheItem(id)
         expect[id] = ARMOR_KEYS[i]
      end
      for iid, key in pairs(expect) do
         H.eq(Items.Info(iid).typeKey, key, "Item " .. iid)
      end
   end)

   H.test("RequestMany veraendert das uebergebene Array nicht", function()
      local env = setup()
      local Items = env.Items
      putRange(9500, 9504)
      local arr = { 9500, "9501", 9502, 9500, 9503, 9504 }
      Items.RequestMany(arr)
      H.deepEq(arr, { 9500, "9501", 9502, 9500, 9503, 9504 })
      H.eq(Items.PendingCount(), 5, "5 verschiedene Ids")
      advance(1)
      H.eq(totalQueries(), 5)
   end)

   H.test("Langlauf: gleiche Id nie oefter als alle 80 s abgefragt (20 s Frist + 60 s Sperre), Existierende genau einmal", function()
      local env = setup()
      local Items = env.Items
      local log = recordLinks()
      -- 40000..40049 existieren; 40050..40099 nicht; 40100..40109 erscheinen erst bei t0+100 s
      putRange(40000, 40049)
      local later = {}
      for id = 40100, 40109 do
         later[id] = put(id)
         mock.items[id] = nil
      end
      local t0 = mock.now
      local ids = {}
      for id = 40000, 40109 do ids[#ids + 1] = id end
      local appeared = false
      math.randomseed(777)
      for step = 1, 4000 do            -- 400 s in 0.1-s-Schritten
         advance(0.1, 0.1)
         if not appeared and mock.now - t0 >= 100 then
            appeared = true
            for id, it in pairs(later) do mock.items[id] = it end
         end
         if step % 25 == 0 then       -- alle 2.5 s: alles erneut anfordern (Filter tut das bei jeder Neuberechnung)
            local pick = {}
            for _ = 1, 40 do pick[#pick + 1] = ids[math.random(1, #ids)] end
            Items.RequestMany(pick)
            Items.RequestMany(ids)
         end
      end
      local last, perId = {}, {}
      for _, e in ipairs(log) do
         local id = tonumber(e.link:match("^item:(%d+)$"))
         H.truthy(id, "gueltiger Link " .. e.link)
         perId[id] = (perId[id] or 0) + 1
         if last[id] and e.at - last[id] < 80 - 0.25 then
            H.fail(("Id %d nach nur %.1f s erneut abgefragt"):format(id, e.at - last[id]))
            break
         end
         last[id] = e.at
      end
      for id = 40000, 40049 do
         H.eq(perId[id], 1, "existierende Id " .. id .. " genau einmal abgefragt")
         H.truthy(Items.IsResolved(id))
      end
      for id = 40050, 40099 do
         H.truthy(perId[id] and perId[id] >= 4, "fehlende Id " .. id .. " wird ~alle 80 s wiederholt")
         H.falsy(Items.IsResolved(id))
      end
      for id = 40100, 40109 do
         H.truthy(Items.IsResolved(id), "spaeter erschienene Id " .. id .. " wird durch Wiederholung aufgeloest")
      end
   end)

   -- =========================================================================
   H.section("TypeLabel / IsNever")
   -- =========================================================================

   H.test("TypeLabel: Namen direkt aus den AH-Listen (enUS, deDE)", function()
      local env = setup()
      local Items = env.Items
      H.eq(Items.TypeLabel(403), "Mail")
      H.eq(Items.TypeLabel(404), "Plate")
      H.eq(Items.TypeLabel(401), "Cloth")
      H.eq(Items.TypeLabel(402), "Leather")
      H.eq(Items.TypeLabel(400), "Miscellaneous")
      H.eq(Items.TypeLabel(214), "Miscellaneous")
      H.eq(Items.TypeLabel(201), "Two-Handed Axes")
      H.eq(Items.TypeLabel(220), "Fishing Poles")
      H.eq(Items.TypeLabel("403"), "Mail", "Zahl als String")
      H.eq(Items.TypeLabel(209), nil, "Waffe 9 ist veraltet")
      H.eq(Items.TypeLabel(405), nil, "Ruestung 5 (Buckler) ist veraltet")
      H.eq(Items.TypeLabel(999), nil)
      H.eq(Items.TypeLabel(0), nil)
      H.eq(Items.TypeLabel(nil), nil)
      H.eq(Items.TypeLabel("abc"), nil)
      H.eq(Items.TypeLabel({}), nil)

      local env2 = setup({ world = { locale = "deDE", auctionLists = ahLists(DE) } })
      H.eq(env2.Items.TypeLabel(403), "Schwere Rüstung")
      H.eq(env2.Items.TypeLabel(404), "Platte")
      H.eq(env2.Items.TypeLabel(401), "Stoff")
      H.eq(env2.Items.TypeLabel(214), "Verschiedenes")
      H.eq(env2.Items.TypeLabel(400), "Verschiedenes")
      H.eq(env2.Items.TypeLabel(215), "Dolche")
   end)

   H.test("TypeLabel: ohne AH-Listen -> zuletzt gesehener Untertypname, sonst nil", function()
      local env = setup({ world = { locale = "deDE", auctionLists = { classes = {}, subclasses = {} } } })
      local Items = env.Items
      H.eq(Items.TypeLabel(403), nil, "noch nichts gesehen")
      put(9300, "Kette", "Rüstung", "Schwere Rüstung", "INVTYPE_CHEST")
      mock.CacheItem(9300)
      H.eq(Items.Info(9300).typeKey, 403)
      H.eq(Items.TypeLabel(403), "Schwere Rüstung", "aus dem aufgeloesten Item")
      H.eq(Items.TypeLabel(404), nil)
   end)

   H.test("IsNever: genau die 7 Ausruestungsplaetze des Servers", function()
      local env = setup()
      local Items = env.Items
      for _, loc in ipairs({ "INVTYPE_BAG", "INVTYPE_RELIC", "INVTYPE_FINGER", "INVTYPE_TRINKET",
                             "INVTYPE_AMMO", "INVTYPE_QUIVER", "INVTYPE_NECK" }) do
         H.eq(Items.IsNever(loc), true, loc)
      end
      for _, loc in ipairs({ "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_BODY", "INVTYPE_CHEST",
                             "INVTYPE_ROBE", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
                             "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_CLOAK", "INVTYPE_WEAPON",
                             "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND",
                             "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RANGED",
                             "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_TABARD" }) do
         H.eq(Items.IsNever(loc), false, loc)
      end
      H.eq(Items.IsNever(nil), false)
      H.eq(Items.IsNever(""), false)
      H.eq(Items.IsNever(5), false)
      H.eq(Items.IsNever({}), false)
      H.eq(Items.IsNever("invtype_bag"), false, "exakte Schreibweise")
      H.eq(Items.IsNever("INVTYPE_NOPE"), false)
      -- IsNever liefert wirklich Booleans
      H.eq(Items.IsNever("INVTYPE_BAG"), true)
      H.eq(Items.IsNever("INVTYPE_HEAD"), false)
   end)

   -- =========================================================================
   H.section("Robustheit")
   -- =========================================================================

   H.test("Last: 2000 nicht vorhandene Ids -> alle gegeben auf, keine Rest-Arbeit, Poll-Frame schlaeft", function()
      local env = setup()
      local Items = env.Items
      local ids = {}
      for id = 20000, 21999 do ids[#ids + 1] = id end
      Items.RequestMany(ids)
      advance(9, 0.1)
      H.eq(totalQueries(), 2000)
      advance(30, 0.1)
      H.eq(Items.PendingCount(), 0)
      H.eq(Items.FailedCount(), 2000)
      H.truthy(idle())
      -- erneutes Anfordern innerhalb der Sperrfrist ist billig und wirkungslos
      Items.RequestMany(ids)
      H.eq(Items.PendingCount(), 0)
      advance(1)
      H.eq(totalQueries(), 2000)
      H.truthy(idle())
   end)

   H.test("Zufallsprobe: gemischte Aufrufe halten die Invarianten (Drosselung, Leerlauf, Vollstaendigkeit)", function()
      local env = setup()
      local Items = env.Items
      local log = recordLinks()
      putRange(30000, 30399)
      math.randomseed(20240607)
      local requested = {}
      for step = 1, 400 do
         local r = math.random(1, 10)
         local id = 30000 + math.random(0, 399)
         if r <= 4 then
            Items.Request(id)
            requested[id] = true
         elseif r == 5 then
            Items.Get(id)
            requested[id] = true
         elseif r == 6 then
            Items.Info(id)
         elseif r == 7 then
            local list = {}
            for k = 1, math.random(1, 30) do
               list[k] = 30000 + math.random(0, 399)
               requested[list[k]] = true
            end
            Items.RequestMany(list)
         elseif r == 8 then
            mock.CacheItem(id)
         elseif r == 9 then
            Items.Request(tostring(id))
            requested[id] = true
         else
            Items.Link(id)
         end
         advance(math.random(0, 3) * 0.05)
         H.truthy(Items.PendingCount() >= 0, "PendingCount nie negativ")
      end
      advance(40)
      H.eq(Items.PendingCount(), 0)
      H.eq(Items.FailedCount(), 0)
      H.truthy(idle())
      for id in pairs(requested) do
         H.truthy(Items.IsResolved(id), "aufgeloest: " .. id)
      end
      for i = 1, #log - 25 do
         if log[i + 25].at - log[i].at < 0.1 - 1e-6 then
            H.fail("Drosselung verletzt (Nr. " .. i .. ")")
            break
         end
      end
      -- jede Id hoechstens einmal abgefragt (nie fehlgeschlagen, nie doppelt)
      for id, n in pairs(mock.itemQueries) do
         H.eq(n, 1, "Abfragen fuer " .. id)
      end
      H.eq(#mock.TakeErrors(), 0)
   end)

   H.test("kein Fehler im Spiel: Init ohne GetAuctionItem*-API und ohne Items", function()
      local env = setup({ init = false })
      removeAuctionApi()
      env.Items.Init()
      H.eq(env.Items.TypeKeyFromNames("Armor", "Plate"), 404)
      H.eq(env.Items.TypeLabel(404), nil, "ohne Listen kein Label")
      H.eq(#mock.TakeErrors(), 0)
   end)
end
