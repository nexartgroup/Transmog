-- _items_smoke.lua
-- Wegwerf-Selbsttest fuer Core/Items.lua mit gestubbten Globals.
-- Aufruf im Hauptverzeichnis:  luajit tests/_items_smoke.lua

local scriptDir = (arg and arg[0] or ""):match("^(.*)/tests/[^/]*$") or "."
local ITEMS_FILE = scriptDir .. "/Core/Items.lua"

local failures, checks = 0, 0
local function check(cond, msg)
   checks = checks + 1
   if not cond then
      failures = failures + 1
      print("FAIL: " .. tostring(msg))
   end
end
local function eq(a, b, msg)
   checks = checks + 1
   if a ~= b then
      failures = failures + 1
      print("FAIL: " .. tostring(msg) .. " (erwartet " .. tostring(b) .. ", war " .. tostring(a) .. ")")
   end
end

-- ---------------------------------------------------------------------------
-- Attrappe
-- ---------------------------------------------------------------------------

local env   -- aktuelle Szenario-Umgebung

local WEAPON_ENUS = { "One-Handed Axes", "Two-Handed Axes", "Bows", "Guns", "One-Handed Maces",
   "Two-Handed Maces", "Polearms", "One-Handed Swords", "Two-Handed Swords", "Staves",
   "Fist Weapons", "Miscellaneous", "Daggers", "Thrown", "Crossbows", "Wands", "Fishing Poles" }
local ARMOR_ENUS = { "Miscellaneous", "Cloth", "Leather", "Mail", "Plate", "Shields", "Librams",
   "Idols", "Totems", "Sigils" }
local CLASSES_ENUS = { "Weapon", "Armor", "Container", "Consumable", "Glyph", "Trade Goods",
   "Projectile", "Quiver", "Recipe", "Gem", "Miscellaneous", "Quest" }

local WEAPON_DEDE = { "Einhandäxte", "Zweihandäxte", "Bogen", "Schusswaffen", "Einhandstreitkolben",
   "Zweihandstreitkolben", "Stangenwaffen", "Einhandschwerter", "Zweihandschwerter", "Stäbe",
   "Faustwaffen", "Verschiedenes", "Dolche", "Wurfwaffen", "Armbrüste", "Zauberstäbe", "Angelruten" }
local ARMOR_DEDE = { "Verschiedenes", "Stoff", "Leder", "Schwere Rüstung", "Platte", "Schilde",
   "Buchbände", "Götzen", "Totems", "Siegel" }
local CLASSES_DEDE = { "Waffe", "Rüstung", "Behälter", "Verbrauchbar", "Glyphe", "Handwerkswaren",
   "Projektil", "Köcher", "Rezept", "Edelstein", "Verschiedenes", "Quest" }

-- baut eine frische Umgebung und laedt Items.lua neu
local function fresh(opts)
   opts = opts or {}
   env = {
      now = 1000,
      hl = {},            -- Liste aller SetHyperlink-Links
      hlTimes = {},       -- Zeitpunkte der SetHyperlink-Aufrufe
      hlTick = 0,         -- SetHyperlink-Aufrufe seit dem letzten Reset (fuer Takt-Pruefung)
      known = {},         -- [id] = Datensatz im Client-Cache
      server = {},        -- [id] = Datensatz, der nach Abfrage antwortet
      queriedAt = {},     -- [id] = Zeit der Abfrage
      delay = opts.delay or 0.25,
      events = {},        -- gefeuerte Ereignisse { name, count, time }
      frames = {},
      owner = nil,
      debugLines = {},
   }
   local E = env

   function GetTime() return E.now end
   UIParent = { name = "UIParent" }

   function GetItemInfo(id)
      local rec = E.known[id]
      if not rec then
         local srv = E.server[id]
         if srv and E.queriedAt[id] and E.now - E.queriedAt[id] >= E.delay then
            E.known[id] = srv
            rec = srv
         end
      end
      if not rec then return nil end
      if rec.partial then
         return rec.name, nil, nil, nil, nil, rec.class, rec.sub, nil, rec.loc, nil
      end
      return rec.name, rec.link or ("|cffffffff|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. rec.name .. "]|h|r"),
         rec.quality or 2, rec.ilvl or 200, rec.minLevel or 80, rec.class, rec.sub, 1, rec.loc,
         rec.icon or "Interface\\Icons\\INV_Misc_Bag_01", 100
   end

   function CreateFrame(kind, name, parent, template)
      local f = { kind = kind, name = name, parent = parent, template = template,
         shown = true, scripts = {} }
      function f:Hide() self.shown = false end
      function f:Show() self.shown = true end
      function f:IsShown() return self.shown end
      function f:SetScript(n, fn) self.scripts[n] = fn end
      if kind == "GameTooltip" then
         function f:SetOwner(o, a)
            self.owner = o
            self.anchor = a
         end
         function f:SetHyperlink(link)
            E.hl[#E.hl + 1] = link
            E.hlTimes[#E.hlTimes + 1] = E.now
            E.hlTick = E.hlTick + 1
            if not self.owner then error("kein Owner") end
            local id = tonumber(link:match("^item:(%d+)"))
            if id and E.queriedAt[id] == nil then
               E.queriedAt[id] = E.now
            end
         end
         function f:Show() error("Scan-Tooltip darf nie Show() erhalten") end
      end
      E.frames[#E.frames + 1] = f
      if name then _G[name] = f end
      return f
   end

   if not opts.noAuction then
      function GetAuctionItemClasses()
         local list = opts.classes or CLASSES_ENUS
         return unpack(list)
      end
      function GetAuctionItemSubClasses(i)
         if i == 1 then return unpack(opts.weapons or WEAPON_ENUS) end
         if i == 2 then return unpack(opts.armors or ARMOR_ENUS) end
         return
      end
   else
      GetAuctionItemClasses = nil
      GetAuctionItemSubClasses = nil
   end

   function GetLocale() return opts.locale or "enUS" end
   local errors = {}
   E.errors = errors
   function geterrorhandler() return function(msg) errors[#errors + 1] = tostring(msg) end end

   Transmog = {}
   Transmog.debug = true
   Transmog.Util = {
      Debug = function(fmt, ...)
         local ok, s = pcall(string.format, fmt, ...)
         E.debugLines[#E.debugLines + 1] = ok and s or ("FORMATFEHLER " .. tostring(fmt))
      end,
   }
   Transmog.Events = {
      Fire = function(name, ...)
         E.events[#E.events + 1] = { name = name, count = (...), time = E.now }
      end,
   }

   dofile(ITEMS_FILE)
   return Transmog.Items
end

-- simuliert Frames: dt Sekunden in Schritten von 0.05 s
local function advance(dt, step)
   step = step or 0.05
   local n = math.floor(dt / step + 0.5)
   for _ = 1, n do
      env.now = env.now + step
      for _, f in ipairs(env.frames) do
         if f.kind == "Frame" and f.shown and f.scripts.OnUpdate then
            f.scripts.OnUpdate(f, step)
         end
      end
   end
end

local function pollFrame()
   for _, f in ipairs(env.frames) do
      if f.kind == "Frame" then return f end
   end
end

local function serve(id, rec)
   env.server[id] = rec
end

local function sumEvents()
   local s = 0
   for _, e in ipairs(env.events) do s = s + e.count end
   return s
end

-- ---------------------------------------------------------------------------
-- Szenario 1: Grundverhalten, Throttle, Idempotenz, Ereignisbuendelung
-- ---------------------------------------------------------------------------
do
   local Items = fresh()
   -- API vorhanden
   for _, fn in ipairs({ "Init", "Info", "Request", "RequestMany", "IsResolved", "PendingCount", "Get",
      "Link", "TypeKeyFromNames", "TypeLabel", "IsNever" }) do
      check(type(Items[fn]) == "function", "Items." .. fn .. " fehlt")
   end
   eq(#Items.ARMOR_TYPES, 4, "ARMOR_TYPES")
   eq(Items.ARMOR_TYPES[1], 401, "ARMOR_TYPES[1]")
   eq(Items.ARMOR_ORDER[1], 404, "ARMOR_ORDER[1]")
   eq(Items.NEVER.INVTYPE_NECK, 1, "NEVER.INVTYPE_NECK")

   -- Laden erzeugt nichts Spielabhaengiges
   eq(#env.frames, 0, "keine Frames beim Laden")

   Items.Init()
   eq(#env.frames, 2, "Init legt Poll-Frame und Scan-Tooltip an")
   local tip
   for _, f in ipairs(env.frames) do if f.kind == "GameTooltip" then tip = f end end
   check(tip and tip.name == "TransmogScanTooltip", "Tooltip heisst TransmogScanTooltip")
   check(tip and tip.template == "GameTooltipTemplate", "Tooltip-Template")
   check(tip and tip.parent == UIParent, "Tooltip-Parent UIParent")
   check(pollFrame() and pollFrame().shown == false, "Poll-Frame anfangs versteckt")

   -- 100 Server-Items
   for id = 1, 100 do
      serve(id, { name = "Item " .. id, class = "Armor", sub = "Plate", loc = "INVTYPE_CHEST", quality = 4 })
   end

   -- Info() loest nie eine Abfrage aus
   for id = 1, 100 do eq(Items.Info(id), nil, "Info unbekannt " .. id) end
   eq(#env.hl, 0, "Info() ruft kein SetHyperlink")
   check(pollFrame().shown == false, "Info() weckt den Poll-Frame nicht")
   eq(Items.PendingCount(), 0, "PendingCount nach Info")

   -- Request hundertfach: nur eine Abfrage je ID, nichts sofort gesendet
   for rep = 1, 50 do
      for id = 1, 100 do Items.Request(id) end
   end
   eq(#env.hl, 0, "Request sendet nicht synchron")
   eq(Items.PendingCount(), 100, "PendingCount nach Request")
   check(pollFrame().shown, "Poll-Frame laeuft nach Request")

   -- Takt-Pruefung: maximal 25 SetHyperlink je 0.1 s
   local maxPerTick = 0
   local lastLen = 0
   for t = 1, 60 do
      advance(0.1, 0.05)
      local sent = #env.hl - lastLen
      lastLen = #env.hl
      if sent > maxPerTick then maxPerTick = sent end
   end
   check(maxPerTick <= 25, "max 25 SetHyperlink je 0.1 s (war " .. maxPerTick .. ")")
   eq(#env.hl, 100, "genau eine Abfrage je ID")
   local seen, dup = {}, false
   for _, l in ipairs(env.hl) do if seen[l] then dup = true end seen[l] = true end
   check(not dup, "keine doppelten Links")
   eq(env.hl[1], "item:1", "FIFO: erste Abfrage item:1")
   eq(env.hl[100], "item:100", "FIFO: letzte Abfrage item:100")

   -- aufgeloest
   for id = 1, 100 do check(Items.IsResolved(id), "aufgeloest " .. id) end
   eq(Items.PendingCount(), 0, "PendingCount am Ende")
   check(pollFrame().shown == false, "Poll-Frame versteckt sich bei Leerlauf")
   eq(sumEvents(), 100, "ITEMS_RESOLVED Summe = 100")
   local gapOk = true
   for i = 2, #env.events do
      if env.events[i].time - env.events[i - 1].time < 0.2 - 1e-9 then gapOk = false end
   end
   check(gapOk, "ITEMS_RESOLVED hoechstens alle 0.2 s")
   check(#env.events <= 12, "ITEMS_RESOLVED gebuendelt (" .. #env.events .. " Ereignisse)")
   check(#env.events >= 2, "ITEMS_RESOLVED mehrfach gefeuert")
   eq(env.events[1].name, "ITEMS_RESOLVED", "Ereignisname")

   -- info-Feld-Inhalt
   local info = Items.Info(7)
   eq(info.id, 7, "info.id")
   eq(info.name, "Item 7", "info.name")
   eq(info.quality, 4, "info.quality")
   eq(info.ilvl, 200, "info.ilvl")
   eq(info.minLevel, 80, "info.minLevel")
   eq(info.typeName, "Armor", "info.typeName")
   eq(info.subtypeName, "Plate", "info.subtypeName")
   eq(info.equipLoc, "INVTYPE_CHEST", "info.equipLoc")
   eq(info.typeKey, 404, "info.typeKey Platte")
   check(info.link:find("Hitem:7:", 1, true) ~= nil, "info.link ist ein echter Link")
   check(type(info.icon) == "string", "info.icon")
   check(Items.Info("7") == info, "String-ID liefert denselben Eintrag")
   check(Items.Info("item:7:0:0") == info, "Link-ID liefert denselben Eintrag")
   eq(Items.Link(7), info.link, "Link(7) = echter Link")
   eq(Items.Link(555), "item:555", "Link unbekannt = item:ID")
   eq(Items.Link("junk"), "", "Link ungueltig = leer")
   eq(Items.Get(7), info, "Get(7)")
   eq(#env.errors, 0, "keine gemeldeten Fehler")
end

-- ---------------------------------------------------------------------------
-- Szenario 2: Aufgeben nach 20 s, Retry nach 60 s, Fruehantwort
-- ---------------------------------------------------------------------------
do
   local Items = fresh()
   Items.Init()
   -- ID 5000 existiert auf dem Server nicht, 5001 antwortet sehr spaet
   serve(5001, { name = "Spaet", class = "Weapon", sub = "Daggers", loc = "INVTYPE_WEAPON" })
   env.delay = 30
   Items.Request(5000)
   Items.Request(5001)
   advance(1)
   eq(#env.hl, 2, "zwei Abfragen gesendet")
   eq(Items.PendingCount(), 2, "zwei offen")
   advance(18)
   eq(Items.PendingCount(), 2, "nach 19 s noch offen")
   check(not Items.IsFailed(5000), "noch nicht failed")
   advance(2)
   -- 5000 ist nach 20 s aufgegeben; 5001 laeuft bis 20 s ebenfalls aus (delay 30)
   eq(Items.PendingCount(), 0, "nach 21 s aufgegeben")
   check(Items.IsFailed(5000), "5000 failed")
   check(Items.IsFailed(5001), "5001 failed")
   eq(Items.FailedCount(), 2, "FailedCount 2")
   check(pollFrame().shown == false, "Poll-Frame schlaeft nach Aufgeben")
   eq(Items.Info(5000), nil, "Info(5000) nil")

   -- Request innerhalb von 60 s: keine neue Abfrage
   local before = #env.hl
   Items.Request(5000)
   advance(5)
   eq(#env.hl, before, "kein Retry vor 60 s")
   check(Items.IsFailed(5000), "weiterhin failed")

   -- nach 60 s: neuer Versuch
   advance(40)    -- jetzt ca. 46 s nach dem Aufgeben
   Items.Request(5000)
   eq(#env.hl, before, "kein Retry nach 46 s")
   advance(20)    -- ca. 66 s
   Items.Request(5000)
   advance(0.5)
   eq(#env.hl, before + 1, "Retry nach 60 s")
   check(not Items.IsFailed(5000), "nicht mehr failed waehrend Retry")
   eq(Items.PendingCount(), 1, "Retry offen")

   -- spaete Antwort wird bei Info() nachtraeglich uebernommen und gezaehlt
   env.events = {}
   env.known[5001] = env.server[5001]
   local info = Items.Info(5001)
   check(info ~= nil, "spaete Antwort ueber Info() uebernommen")
   check(not Items.IsFailed(5001), "failed zurueckgesetzt")
   eq(Items.FailedCount(), 0, "FailedCount 0")
   advance(0.5)
   eq(sumEvents(), 1, "ITEMS_RESOLVED fuer spaete Antwort")
end

-- ---------------------------------------------------------------------------
-- Szenario 3: Items, die schon im Client-Cache liegen
-- ---------------------------------------------------------------------------
do
   local Items = fresh()
   Items.Init()
   for id = 1, 10 do
      env.known[id] = { name = "Cached " .. id, class = "Weapon", sub = "Bows", loc = "INVTYPE_RANGED" }
   end
   local array = {}
   for id = 1, 10 do array[#array + 1] = id end
   array[#array + 1] = "20"        -- String
   array[#array + 1] = 0           -- ungueltig
   array[#array + 1] = -4          -- ungueltig
   array[#array + 1] = "abc"       -- ungueltig
   array[#array + 1] = 1 / 0       -- ungueltig
   Items.RequestMany(array)
   eq(#env.hl, 0, "bereits bekannte IDs brauchen keine Abfrage")
   eq(Items.PendingCount(), 1, "nur '20' wartet")
   advance(0.5)
   eq(#env.hl, 1, "genau eine Abfrage (fuer 20)")
   eq(env.hl[1], "item:20", "Link der Abfrage")
   eq(sumEvents(), 10, "10 Items sofort aufgeloest und gemeldet")
   check(Items.Info(3).typeKey == 202, "Bogen = 202")
   eq(Items.Request(nil), false, "Request(nil)")
   eq(Items.Info(nil), nil, "Info(nil)")
   eq(Items.Info({}), nil, "Info(table)")
   eq(Items.Info(0), nil, "Info(0)")
end

-- ---------------------------------------------------------------------------
-- Szenario 4: Teilwerte von GetItemInfo
-- ---------------------------------------------------------------------------
do
   local Items = fresh()
   Items.Init()
   env.known[77] = { name = "Teil", partial = true, class = "Armor", sub = "Cloth", loc = "INVTYPE_CLOAK" }
   local info = Items.Info(77)
   check(info ~= nil, "Teilwerte werden uebernommen")
   eq(info.link, "item:77", "fehlender Link -> item:ID")
   eq(info.quality, 1, "fehlende Qualitaet -> 1")
   eq(info.ilvl, 0, "fehlendes ilvl -> 0")
   eq(info.icon, "Interface\\Icons\\INV_Misc_QuestionMark", "fehlendes Icon -> Fragezeichen")
   eq(info.typeKey, 401, "Umhang aus Stoff = 401")
   env.known[78] = { name = "", class = "Armor", sub = "Cloth", loc = "INVTYPE_CLOAK" }
   eq(Items.Info(78), nil, "leerer Name = unbekannt")
end

-- ---------------------------------------------------------------------------
-- Szenario 5: Typ-Ermittlung (enUS-Client, AH-Listen)
-- ---------------------------------------------------------------------------
do
   local Items = fresh()
   Items.Init()
   eq(Items.TypeKeyFromNames("Weapon", "One-Handed Axes"), 200, "1H-Axt 200")
   eq(Items.TypeKeyFromNames("Weapon", "Two-Handed Axes"), 201, "2H-Axt 201")
   eq(Items.TypeKeyFromNames("Weapon", "Bows"), 202, "Bogen 202")
   eq(Items.TypeKeyFromNames("Weapon", "Guns"), 203, "Gewehr 203")
   eq(Items.TypeKeyFromNames("Weapon", "One-Handed Maces"), 204, "1H-Streitkolben 204")
   eq(Items.TypeKeyFromNames("Weapon", "Two-Handed Maces"), 205, "2H-Streitkolben 205")
   eq(Items.TypeKeyFromNames("Weapon", "Polearms"), 206, "Stangenwaffe 206")
   eq(Items.TypeKeyFromNames("Weapon", "One-Handed Swords"), 207, "1H-Schwert 207")
   eq(Items.TypeKeyFromNames("Weapon", "Two-Handed Swords"), 208, "2H-Schwert 208")
   eq(Items.TypeKeyFromNames("Weapon", "Staves"), 210, "Stab 210")
   eq(Items.TypeKeyFromNames("Weapon", "Fist Weapons"), 213, "Faustwaffe 213")
   eq(Items.TypeKeyFromNames("Weapon", "Miscellaneous"), 214, "Waffe Verschiedenes 214")
   eq(Items.TypeKeyFromNames("Weapon", "Daggers"), 215, "Dolch 215")
   eq(Items.TypeKeyFromNames("Weapon", "Thrown"), 216, "Wurfwaffe 216")
   eq(Items.TypeKeyFromNames("Weapon", "Crossbows"), 218, "Armbrust 218")
   eq(Items.TypeKeyFromNames("Weapon", "Wands"), 219, "Zauberstab 219")
   eq(Items.TypeKeyFromNames("Weapon", "Fishing Poles"), 220, "Angelrute 220")
   eq(Items.TypeKeyFromNames("Armor", "Miscellaneous"), 400, "Ruestung Verschiedenes 400")
   eq(Items.TypeKeyFromNames("Armor", "Cloth"), 401, "Stoff 401")
   eq(Items.TypeKeyFromNames("Armor", "Leather"), 402, "Leder 402")
   eq(Items.TypeKeyFromNames("Armor", "Mail"), 403, "Kette 403")
   eq(Items.TypeKeyFromNames("Armor", "Plate"), 404, "Platte 404")
   eq(Items.TypeKeyFromNames("Armor", "Shields"), 406, "Schild 406")
   eq(Items.TypeKeyFromNames("Armor", "Librams"), 407, "Buchband 407")
   eq(Items.TypeKeyFromNames("Armor", "Idols"), 408, "Goetze 408")
   eq(Items.TypeKeyFromNames("Armor", "Totems"), 409, "Totem 409")
   eq(Items.TypeKeyFromNames("Armor", "Sigils"), 410, "Siegel 410")

   -- unbekannt / nicht Waffe oder Ruestung
   eq(Items.TypeKeyFromNames("Weapon", "Banana"), nil, "unbekannte Unterklasse")
   eq(Items.TypeKeyFromNames("Trade Goods", "Cloth"), nil, "Handwerkswaren/Stoff ist KEIN Ruestungstyp")
   eq(Items.TypeKeyFromNames("Container", "Bag"), nil, "Behaelter")
   eq(Items.TypeKeyFromNames("Gizmo", "Cloth"), nil, "unbekannte Klasse ohne Hinweis")
   eq(Items.TypeKeyFromNames(nil, "Cloth"), nil, "Klasse nil ohne Hinweis")
   eq(Items.TypeKeyFromNames("Weapon", nil), nil, "Unterklasse nil")
   eq(Items.TypeKeyFromNames("Weapon", ""), nil, "Unterklasse leer")
   eq(Items.TypeKeyFromNames(12, 34), nil, "Zahlen statt Namen")
   -- Hinweis ueber den Ausruestungsplatz
   eq(Items.TypeKeyFromNames("Gizmo", "Cloth", "INVTYPE_CLOAK"), 401, "unbekannte Klasse + Platz-Hinweis")
   eq(Items.TypeKeyFromNames("Gizmo", "Fishing Poles", "INVTYPE_2HWEAPON"), 220, "Platz-Hinweis Waffe")
   eq(Items.TypeKeyFromNames("Trade Goods", "Cloth", "INVTYPE_CLOAK"), nil, "bekannte andere Klasse gewinnt gegen Hinweis")
   local anyDebug = false
   for _, l in ipairs(env.debugLines) do
      if l:find("FORMATFEHLER", 1, true) then anyDebug = true end
   end
   check(not anyDebug, "Debug-Formatstrings gueltig")

   -- Labels aus den AH-Listen
   eq(Items.TypeLabel(404), "Plate", "Label 404")
   eq(Items.TypeLabel(201), "Two-Handed Axes", "Label 201")
   eq(Items.TypeLabel(214), "Miscellaneous", "Label 214")
   eq(Items.TypeLabel(400), "Miscellaneous", "Label 400")
   eq(Items.TypeLabel(999), nil, "Label unbekannt")
   eq(Items.TypeLabel(nil), nil, "Label nil")
   eq(Items.TypeLabel("401"), "Cloth", "Label String-Key")

   -- NEVER
   check(Items.IsNever("INVTYPE_NECK"), "IsNever NECK")
   check(Items.IsNever("INVTYPE_TRINKET"), "IsNever TRINKET")
   check(not Items.IsNever("INVTYPE_HEAD"), "IsNever HEAD")
   check(not Items.IsNever(""), "IsNever leer")
   check(not Items.IsNever(nil), "IsNever nil")

   local lines = Items.DumpTypes()
   check(#lines >= 28, "DumpTypes liefert Zeilen (" .. #lines .. ")")
end

-- ---------------------------------------------------------------------------
-- Szenario 6: deDE-Client (AH-Listen deutsch, kleine Unterschiede in der Klasse)
-- ---------------------------------------------------------------------------
do
   local Items = fresh({ locale = "deDE", classes = CLASSES_DEDE, weapons = WEAPON_DEDE, armors = ARMOR_DEDE })
   Items.Init()
   eq(Items.TypeKeyFromNames("Waffe", "Zweihandäxte"), 201, "de: 2H-Axt")
   eq(Items.TypeKeyFromNames("Waffe", "Verschiedenes"), 214, "de: Waffe Verschiedenes")
   eq(Items.TypeKeyFromNames("Rüstung", "Verschiedenes"), 400, "de: Ruestung Verschiedenes")
   eq(Items.TypeKeyFromNames("Rüstung", "Schwere Rüstung"), 403, "de: Kette")
   eq(Items.TypeKeyFromNames("Rüstung", "Platte"), 404, "de: Platte")
   eq(Items.TypeKeyFromNames("Handwerkswaren", "Stoff"), nil, "de: Handwerkswaren/Stoff")
   eq(Items.TypeLabel(404), "Platte", "de: Label Platte")
   eq(Items.TypeLabel(220), "Angelruten", "de: Label Angelruten")
   -- Klassenname weicht ab ("Waffen" statt "Waffe" auf dem Item): Rueckfalltabelle
   eq(Items.TypeKeyFromNames("Waffen", "Dolche"), 215, "de: Klasse 'Waffen' per Rueckfall")
end

-- ---------------------------------------------------------------------------
-- Szenario 7: AH-Liste mit falscher Laenge -> Rueckfalltabellen, Labels aus Items
-- ---------------------------------------------------------------------------
do
   local shortWeapons = {}
   for i = 1, 16 do shortWeapons[i] = WEAPON_DEDE[i] end   -- 16 statt 17
   local Items = fresh({ locale = "deDE", classes = CLASSES_DEDE, weapons = shortWeapons, armors = ARMOR_DEDE })
   Items.Init()
   -- Waffen: Rueckfall ueber Namen
   eq(Items.TypeKeyFromNames("Waffe", "Dolche"), 215, "Laenge falsch: Dolch per Namenstabelle")
   eq(Items.TypeKeyFromNames("Waffe", "Stäbe"), 210, "Laenge falsch: Stab per Namenstabelle")
   -- Ruestung: AH-Liste ok
   eq(Items.TypeKeyFromNames("Rüstung", "Leder"), 402, "Ruestung ueber AH")
   eq(Items.TypeLabel(402), "Leder", "Label Ruestung aus AH")
   -- Waffen-Label: nur ueber gesehene Items
   eq(Items.TypeLabel(215), nil, "Label ohne AH und ohne Item = nil")
   env.known[900] = { name = "Dolch", class = "Waffe", sub = "Dolche", loc = "INVTYPE_WEAPONMAINHAND" }
   eq(Items.Info(900).typeKey, 215, "Item-typeKey per Rueckfall")
   eq(Items.TypeLabel(215), "Dolche", "Label aus gesehenem Item")
   local found = false
   for _, l in ipairs(env.debugLines) do
      if l:find("unerwartete AH", 1, true) then found = true end
   end
   check(found, "Laengenabweichung wird per Debug gemeldet")
end

-- ---------------------------------------------------------------------------
-- Szenario 8: gleiche Laenge, aber verdrehte Reihenfolge -> Gegenprobe greift
-- ---------------------------------------------------------------------------
do
   local scrambled = {}
   for i = 1, 17 do scrambled[i] = WEAPON_ENUS[i] end
   scrambled[1], scrambled[2] = scrambled[2], scrambled[1]   -- 1H/2H-Axt vertauscht
   local Items = fresh({ weapons = scrambled })
   Items.Init()
   eq(Items.TypeKeyFromNames("Weapon", "One-Handed Axes"), 200, "Gegenprobe: 1H-Axt bleibt 200 (Namenstabelle)")
   eq(Items.TypeKeyFromNames("Weapon", "Two-Handed Axes"), 201, "Gegenprobe: 2H-Axt bleibt 201")
   eq(Items.TypeLabel(200), nil, "keine AH-Labels fuer verdrehte Klasse")
   eq(Items.TypeLabel(404), "Plate", "Ruestung bleibt ueber AH")
end

-- ---------------------------------------------------------------------------
-- Szenario 9: gar keine Auktionshaus-API
-- ---------------------------------------------------------------------------
do
   local Items = fresh({ noAuction = true })
   Items.Init()
   eq(Items.TypeKeyFromNames("Armor", "Plate"), 404, "ohne AH: Platte per Namenstabelle")
   eq(Items.TypeKeyFromNames("Armor", "Mail"), 403, "ohne AH: Kette")
   eq(Items.TypeKeyFromNames("Weapon", "Wands"), 219, "ohne AH: Zauberstab")
   eq(Items.TypeKeyFromNames("Waffe", "Zweihandschwerter"), 208, "ohne AH: deutsch")
   eq(Items.TypeKeyFromNames("Arma", "Mazas de dos manos"), 205, "ohne AH: spanisch")
   eq(Items.TypeKeyFromNames("Arme", "Arbalètes"), 218, "ohne AH: franzoesisch")
   eq(Items.TypeKeyFromNames("Доспехи", "Латы"), 404, "ohne AH: russisch")
   eq(Items.TypeKeyFromNames("Armor", "Zzz"), nil, "ohne AH: unbekannt")
   eq(Items.TypeLabel(404), nil, "ohne AH: kein Label")
end

-- ---------------------------------------------------------------------------
-- Szenario 10: Rueckfall-Tabellen sind in sich konsistent
-- ---------------------------------------------------------------------------
do
   local f = io.open(ITEMS_FILE, "rb")
   local src = f:read("*a")
   f:close()
   fresh()
   local chunk = assert(loadstring(src .. "\nreturn FB_WEAPON, FB_ARMOR, AH_IDS, fbSub"))
   local FBW, FBA, AH_IDS, fbSub = chunk()
   local expect = { [2] = 17, [4] = 10 }
   eq(#AH_IDS[2], expect[2], "AH_IDS Waffe 17")
   eq(#AH_IDS[4], expect[4], "AH_IDS Ruestung 10")
   for code, names in pairs(FBW) do eq(#names, 17, "FB_WEAPON." .. code .. " hat 17 Eintraege") end
   for code, names in pairs(FBA) do eq(#names, 10, "FB_ARMOR." .. code .. " hat 10 Eintraege") end
   -- kein Name zeigt auf zwei verschiedene IDs innerhalb einer Klasse
   for classId, columns in pairs({ [2] = FBW, [4] = FBA }) do
      local owner = {}
      for code, names in pairs(columns) do
         for i = 1, #names do
            local entries = names[i]
            if type(entries) == "string" then entries = { entries } end
            if type(entries) == "table" then
               for _, name in ipairs(entries) do
                  local id = AH_IDS[classId][i]
                  if owner[name] ~= nil and owner[name] ~= id then
                     check(false, "Namenskollision " .. name .. " in Klasse " .. classId)
                  end
                  owner[name] = id
               end
            end
         end
      end
   end
   -- dieselbe Abbildung wie im alten Addon (deDE verifiziert)
   local old = {
      [2] = { ["Einhandäxte"] = 0, ["Zweihandäxte"] = 1, ["Bogen"] = 2, ["Schusswaffen"] = 3,
         ["Einhandstreitkolben"] = 4, ["Zweihandstreitkolben"] = 5, ["Stangenwaffen"] = 6,
         ["Einhandschwerter"] = 7, ["Zweihandschwerter"] = 8, ["Stäbe"] = 10, ["Faustwaffen"] = 13,
         ["Verschiedenes"] = 14, ["Dolche"] = 15, ["Wurfwaffen"] = 16, ["Armbrüste"] = 18,
         ["Zauberstäbe"] = 19, ["Angelruten"] = 20 },
      [4] = { ["Verschiedenes"] = 0, ["Stoff"] = 1, ["Leder"] = 2, ["Schwere Rüstung"] = 3,
         ["Platte"] = 4, ["Schilde"] = 6, ["Buchbände"] = 7, ["Götzen"] = 8, ["Totems"] = 9,
         ["Siegel"] = 10 },
      }
   for classId, map in pairs(old) do
      for name, id in pairs(map) do
         eq(fbSub[classId][name], id, "Fallback deDE " .. name)
      end
   end
end

-- ---------------------------------------------------------------------------
-- Szenario 11: keine Obergrenze offener Abfragen; alle werden gesendet und laufen aus
-- ---------------------------------------------------------------------------
do
   local Items = fresh({ delay = 1000 })   -- niemand antwortet
   Items.Init()
   for id = 1, 1000 do Items.Request(id) end
   advance(5)   -- 50 Takte * 25 = 1250 moegliche Sendungen, 1000 IDs
   eq(#env.hl, 1000, "alle 1000 Abfragen gesendet (keine Deckelung)")
   eq(Items.PendingCount(), 1000, "alle weiter ausstehend")
   check(pollFrame().shown, "Poll-Frame laeuft solange Abfragen offen sind")
   advance(21)
   eq(Items.PendingCount(), 0, "nach 20 s alle aufgegeben")
   eq(Items.FailedCount(), 1000, "alle 1000 als failed vermerkt")
   check(pollFrame().shown == false, "Poll-Frame schlaeft nach dem Aufgeben")
   -- SetHyperlink-Takt auch hier: nie mehr als 25 je 0.1 s
   local worst = 0
   for i = 1, #env.hlTimes - 25 do
      local span = env.hlTimes[i + 25] - env.hlTimes[i]
      if i == 1 or span < worst then worst = span end
   end
   check(worst >= 0.1 - 1e-9, "26 Abfragen liegen nie innerhalb von 0.1 s (kleinster Abstand " .. worst .. ")")
end

-- ---------------------------------------------------------------------------
-- Szenario 11b: das Pseudo-Item "verborgen" wird nie abgefragt
-- ---------------------------------------------------------------------------
do
   local Items = fresh()
   Items.Init()
   eq(Items.Request(999999), false, "Request(HIDDEN) = false")
   Items.RequestMany({ 999999, "999999" })
   eq(Items.Get(999999), nil, "Get(HIDDEN) = nil")
   eq(Items.PendingCount(), 0, "HIDDEN erzeugt keine ausstehende Abfrage")
   advance(1)
   eq(#env.hl, 0, "HIDDEN wird nie gesendet")
   check(pollFrame().shown == false, "Poll-Frame bleibt versteckt")
   Transmog.HIDDEN_ID = 123456
   Items.Request(123456)
   eq(Items.PendingCount(), 0, "T.HIDDEN_ID wird beachtet")
   Items.Request(999999)
   eq(Items.PendingCount(), 1, "ohne Bezug zu T.HIDDEN_ID ist 999999 eine normale ID")
end

-- ---------------------------------------------------------------------------
-- Szenario 12: Poll-Frame laeuft auch dann sauber weiter, wenn ein Handler Items nachfordert
-- ---------------------------------------------------------------------------
do
   local Items = fresh()
   Items.Init()
   for id = 1, 5 do serve(id, { name = "A" .. id, class = "Armor", sub = "Mail", loc = "INVTYPE_HEAD" }) end
   for id = 6, 10 do serve(id, { name = "B" .. id, class = "Armor", sub = "Mail", loc = "INVTYPE_HEAD" }) end
   local fires = 0
   Transmog.Events.Fire = function(name, count)
      fires = fires + 1
      if fires == 1 then
         for id = 6, 10 do Items.Request(id) end   -- Nachforderung aus dem Handler
      end
   end
   for id = 1, 5 do Items.Request(id) end
   advance(3)
   for id = 1, 10 do check(Items.IsResolved(id), "Handler-Nachforderung aufgeloest " .. id) end
   check(pollFrame().shown == false, "Poll-Frame schlaeft nach Handler-Nachforderung")
   eq(Items.PendingCount(), 0, "nichts mehr offen")
end

-- ---------------------------------------------------------------------------
-- Szenario 13: Scan-Tooltip-Verhalten
-- ---------------------------------------------------------------------------
do
   local Items = fresh()
   serve(42, { name = "X", class = "Armor", sub = "Cloth", loc = "INVTYPE_HEAD" })
   -- ohne Init: Request legt Frame/Tooltip lazy an
   Items.Request(42)
   advance(1)
   check(Items.IsResolved(42), "lazy ohne Init aufgeloest")
   local tip
   for _, f in ipairs(env.frames) do if f.kind == "GameTooltip" then tip = f end end
   check(tip ~= nil, "Tooltip lazy angelegt")
   eq(tip.anchor, "ANCHOR_NONE", "SetOwner mit ANCHOR_NONE")
   eq(tip.owner, UIParent, "Owner = UIParent")
end

-- ---------------------------------------------------------------------------
-- Szenario 14: in der Warteschlange stehendes Item wird ueber Info() aufgeloest
-- ---------------------------------------------------------------------------
do
   local Items = fresh()
   Items.Init()
   for id = 1, 30 do
      serve(id, { name = "Q" .. id, class = "Armor", sub = "Leather", loc = "INVTYPE_LEGS" })
   end
   for id = 1, 30 do Items.Request(id) end
   eq(Items.PendingCount(), 30, "30 wartend")
   env.known[3] = env.server[3]            -- Client kennt Item 3 ploetzlich
   check(Items.Info(3) ~= nil, "Info(3) loest ueber den Client-Cache auf")
   eq(Items.PendingCount(), 29, "29 wartend nach Info(3)")
   advance(2)
   local sent3 = false
   for _, l in ipairs(env.hl) do if l == "item:3" then sent3 = true end end
   check(not sent3, "item:3 wurde nie abgefragt")
   eq(#env.hl, 29, "29 Abfragen")
   eq(sumEvents(), 30, "alle 30 gemeldet (inkl. Item 3)")
   eq(Items.PendingCount(), 0, "nichts offen")
   check(pollFrame().shown == false, "Poll-Frame schlaeft")
end

-- ---------------------------------------------------------------------------
-- Szenario 15: AH-Listen erst spaeter verfuegbar -> typeKey wird nachgezogen
-- ---------------------------------------------------------------------------
do
   local arm = { "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10" }
   local classes = { "Wpn", "Arm", "Cnt" }
   local Items = fresh({ classes = classes, armors = arm })
   local ready = false
   function GetAuctionItemClasses()
      if not ready then return end
      return unpack(classes)
   end
   Items.Init()
   env.known[11] = { name = "Spaet", class = "Arm", sub = "A5", loc = "INVTYPE_CHEST" }
   local info = Items.Info(11)
   eq(info.typeKey, nil, "ohne AH-Liste unbekannter Untertyp")
   ready = true
   eq(Items.TypeLabel(404), "A5", "Label nach spaetem AH-Bau")
   eq(info.typeKey, 404, "typeKey wurde nachgezogen")
   eq(Items.TypeKeyFromNames("Arm", "A2"), 401, "AH-Name ueber Klassenliste")
end

-- ---------------------------------------------------------------------------
-- Szenario 16: Zufallslauf mit Invarianten (Zaehler, Takt, Ereignissumme, Leerlauf)
-- ---------------------------------------------------------------------------
do
   math.randomseed(12345)
   local Items = fresh({ delay = 0 })
   Items.Init()
   -- IDs 1..250 existieren (Antwort nach 0..4 s), 251..300 nie
   local ownDelay = {}
   for id = 1, 250 do
      serve(id, { name = "R" .. id, class = (id % 2 == 0) and "Armor" or "Weapon",
         sub = (id % 2 == 0) and "Leather" or "Daggers", loc = "INVTYPE_HEAD" })
      ownDelay[id] = math.random() * 4
   end
   -- die Attrappe antwortet je ID nach ownDelay: GetItemInfo ueberschreiben
   local baseGet = GetItemInfo
   function GetItemInfo(id)
      local srv = env.server[id]
      if srv and env.queriedAt[id] and env.now - env.queriedAt[id] >= ownDelay[id] then
         env.known[id] = srv
      end
      return baseGet(id)
   end

   local requested = {}
   local frames = 0
   local negative = false
   for step = 1, 1500 do
      local op = math.random(1, 10)
      if op <= 4 then
         local id = math.random(1, 300)
         Items.Request(id); requested[id] = true
      elseif op == 5 then
         local arr = {}
         for i = 1, math.random(1, 40) do
            local id = math.random(1, 300)
            arr[#arr + 1] = (math.random() < 0.2) and tostring(id) or id
            requested[id] = true
         end
         Items.RequestMany(arr)
      elseif op == 6 then
         Items.Info(math.random(1, 300))
      elseif op == 7 then
         local id = math.random(1, 300)
         Items.Get(id); requested[id] = true
      elseif op == 8 then
         Items.IsResolved(math.random(1, 300))
      else
         advance(0.01 + math.random() * 0.24, 0.01 + math.random() * 0.04)
         frames = frames + 1
      end
      if Items.PendingCount() < 0 or Items.FailedCount() < 0 then negative = true end
   end
   check(not negative, "Zaehler nie negativ")

   -- SetHyperlink-Takt: 26 Aufrufe liegen nie innerhalb von 0.1 s
   local bad = false
   for i = 1, #env.hlTimes - 25 do
      if env.hlTimes[i + 25] - env.hlTimes[i] < 0.1 - 1e-9 then bad = true end
   end
   check(not bad, "Zufallslauf: hoechstens 25 SetHyperlink je 0.1 s")

   -- Info() ist nie die Ursache einer Abfrage: jede gesendete ID wurde angefordert
   local ok = true
   for _, l in ipairs(env.hl) do
      local id = tonumber(l:match("^item:(%d+)$"))
      if not id or not requested[id] then ok = false end
   end
   check(ok, "nur angeforderte IDs wurden gesendet")

   -- genug Zeit vergehen lassen: alles ist aufgeloest oder aufgegeben
   advance(30)
   eq(Items.PendingCount(), 0, "Zufallslauf: nichts mehr offen")
   check(pollFrame().shown == false, "Zufallslauf: Poll-Frame schlaeft")
   local nResolved, nFailed, nOther = 0, 0, 0
   for id = 1, 300 do
      if Items.Info(id) then
         nResolved = nResolved + 1
         check(id <= 250, "nur existierende IDs aufgeloest")
      elseif Items.IsFailed(id) then
         nFailed = nFailed + 1
      else
         nOther = nOther + 1
      end
   end
   eq(Items.FailedCount(), nFailed, "FailedCount stimmt mit IsFailed ueberein")
   -- IDs, die nie angefordert wurden, sind weder aufgeloest noch failed
   for id = 1, 300 do
      if not requested[id] and id > 250 then
         check(not Items.IsFailed(id), "nie angeforderte ID " .. id .. " nicht failed")
      end
   end

   -- Ereignissumme: jede ueber Request/Get angeforderte und aufgeloeste ID wurde genau einmal gemeldet
   local expect = 0
   for id = 1, 250 do
      if requested[id] and Items.Info(id) then expect = expect + 1 end
   end
   eq(sumEvents(), expect, "ITEMS_RESOLVED-Summe = Anzahl angeforderter, aufgeloester IDs")
   local gapOk = true
   for i = 2, #env.events do
      if env.events[i].time - env.events[i - 1].time < 0.2 - 1e-9 then gapOk = false end
   end
   check(gapOk, "Zufallslauf: ITEMS_RESOLVED hoechstens alle 0.2 s")
   eq(#env.errors, 0, "Zufallslauf: keine Fehler gemeldet")
end

print(string.format("%d Pruefungen, %d Fehler", checks, failures))
os.exit(failures == 0 and 0 or 1)
