-- Items.lua
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Item-Informationen: eigener Cache, gedrosselte
-- Server-Abfragen ueber einen Scan-Tooltip und die locale-unabhaengige
-- Typ-Ermittlung (typeKey = Klasse * 100 + Unterklasse).
--
-- Ablauf:
--   Info(id)      reiner Cache-Lookup (GetItemInfo), loest NIE eine Abfrage aus
--   Request(id)   stellt die ID in eine FIFO-Warteschlange (idempotent, billig)
--   Poll-Frame    alle 0.1 s: offene Abfragen per GetItemInfo pruefen, danach
--                 hoechstens 25 neue per SetHyperlink senden; versteckt sich,
--                 sobald nichts mehr aussteht
--   ITEMS_RESOLVED  hoechstens alle 0.2 s, mit der Zahl der seit dem letzten
--                 Feuern neu aufgeloesten Items (gebuendelt)
--
-- 3.3.5a hat kein GET_ITEM_INFO_RECEIVED: ob die Antwort des Servers da ist,
-- sieht man nur daran, dass GetItemInfo(id) irgendwann Werte liefert.
-- ---------------------------------------------------------------------------

local T = Transmog
local Items = T.Items or {}
T.Items = Items

local floor = math.floor
local strmatch = string.match
local tsort = table.sort
local type, tonumber, pairs, ipairs, pcall = type, tonumber, pairs, ipairs, pcall
local tostring = tostring

-- ---------------------------------------------------------------------------
-- Konstanten
-- ---------------------------------------------------------------------------

local POLL_INTERVAL = 0.1       -- Sekunden zwischen zwei Poll-Takten
local MAX_SEND_PER_TICK = 25    -- hoechstens so viele SetHyperlink je Takt
local MAX_POP_PER_TICK = 200    -- hoechstens so viele Warteschlangen-Eintraege je Takt (Arbeitsgrenze)
local GIVE_UP_AFTER = 20        -- Sekunden nach dem Senden, dann "failed"
local RETRY_AFTER = 60          -- Sekunden, nach denen Request ein failed-Item erneut versucht
local FIRE_INTERVAL = 0.2       -- Mindestabstand zweier ITEMS_RESOLVED
local MAX_BUILD_TRIES = 5       -- Versuche, die AH-Listen zu lesen (falls anfangs leer)
local MAX_ID = 2147483647

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local CLASS_WEAPON = 2
local CLASS_ARMOR = 4

-- Indizes der beiden Klassen in GetAuctionItemClasses()
local AH_CLASS_INDEX = {
   { classId = CLASS_WEAPON, ahIndex = 1 },
   { classId = CLASS_ARMOR,  ahIndex = 2 },
}

-- Reihenfolge der AH-Unterklassen -> echte ITEM_SUBCLASS_*-Werte.
-- Die Liste ueberspringt die veralteten Eintraege (Waffe 9, 11, 12, 17,
-- Ruestung 5), deshalb ist es nicht einfach 0..n.
local AH_IDS = {
   [CLASS_WEAPON] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 14, 15, 16, 18, 19, 20 },   -- 17
   [CLASS_ARMOR]  = { 0, 1, 2, 3, 4, 6, 7, 8, 9, 10 },                              -- 10
}

-- Ausruestungsplaetze, aus denen sich die Klasse ableiten laesst (nur als
-- Rueckfall, wenn der lokalisierte Klassenname unbekannt ist)
local LOC_CLASS = {
   INVTYPE_WEAPON = CLASS_WEAPON, INVTYPE_2HWEAPON = CLASS_WEAPON,
   INVTYPE_WEAPONMAINHAND = CLASS_WEAPON, INVTYPE_WEAPONOFFHAND = CLASS_WEAPON,
   INVTYPE_RANGED = CLASS_WEAPON, INVTYPE_RANGEDRIGHT = CLASS_WEAPON,
   INVTYPE_THROWN = CLASS_WEAPON,
   INVTYPE_HEAD = CLASS_ARMOR, INVTYPE_SHOULDER = CLASS_ARMOR, INVTYPE_BODY = CLASS_ARMOR,
   INVTYPE_CHEST = CLASS_ARMOR, INVTYPE_ROBE = CLASS_ARMOR, INVTYPE_WAIST = CLASS_ARMOR,
   INVTYPE_LEGS = CLASS_ARMOR, INVTYPE_FEET = CLASS_ARMOR, INVTYPE_WRIST = CLASS_ARMOR,
   INVTYPE_HAND = CLASS_ARMOR, INVTYPE_CLOAK = CLASS_ARMOR, INVTYPE_SHIELD = CLASS_ARMOR,
   INVTYPE_HOLDABLE = CLASS_ARMOR, INVTYPE_TABARD = CLASS_ARMOR,
   INVTYPE_NECK = CLASS_ARMOR, INVTYPE_FINGER = CLASS_ARMOR,
   INVTYPE_TRINKET = CLASS_ARMOR, INVTYPE_RELIC = CLASS_ARMOR,
}

-- ---------------------------------------------------------------------------
-- Oeffentliche Konstanten
-- ---------------------------------------------------------------------------

-- Ruestungstypen: 401 Stoff, 402 Leder, 403 Kette, 404 Platte
Items.ARMOR_TYPES = { 401, 402, 403, 404 }
Items.ARMOR_ORDER = { 404, 403, 402, 401 }   -- Anzeigereihenfolge Platte -> Stoff

-- Nie transmogbar (Server: CanNeverTransmog)
Items.NEVER = {
   INVTYPE_BAG = 1, INVTYPE_RELIC = 1, INVTYPE_FINGER = 1, INVTYPE_TRINKET = 1,
   INVTYPE_AMMO = 1, INVTYPE_QUIVER = 1, INVTYPE_NECK = 1,
}

-- ---------------------------------------------------------------------------
-- Rueckfall-Tabellen (nur, wenn die AH-Listen nicht nutzbar sind)
--
-- Je Sprache eine Spalte in AH-Reihenfolge (siehe AH_IDS). Ein Eintrag ist ein
-- String, eine Liste von Schreibweisen oder false (unbekannt). enUS und deDE
-- sind verifiziert (deDE gegen einen echten deDE-3.3.5-Client, enUS ist die
-- Quelle; die zusaetzlichen Schreibweisen "Boegen"/"Kette" sind Vorsichtsnamen
-- ohne Pruefung); esES stammt aus dem alten Addon, frFR/ruRU aus der Erinnerung
-- an die Clients und sind nicht live geprueft. Falsche Eintraege sind harmlos:
-- ein Name, der nie vorkommt, wird nie nachgeschlagen.
-- ---------------------------------------------------------------------------

local FB_WEAPON = {
   enUS = {
      "One-Handed Axes", "Two-Handed Axes", "Bows", "Guns", "One-Handed Maces",
      "Two-Handed Maces", "Polearms", "One-Handed Swords", "Two-Handed Swords",
      "Staves", "Fist Weapons", "Miscellaneous", "Daggers", "Thrown", "Crossbows",
      "Wands", "Fishing Poles",
   },
   deDE = {
      "Einhandäxte", "Zweihandäxte", { "Bogen", "Bögen" }, "Schusswaffen", "Einhandstreitkolben",
      "Zweihandstreitkolben", "Stangenwaffen", "Einhandschwerter", "Zweihandschwerter",
      "Stäbe", "Faustwaffen", "Verschiedenes", "Dolche", "Wurfwaffen", "Armbrüste",
      "Zauberstäbe", "Angelruten",
   },
   esES = {
      "Hachas de una mano", "Hachas de dos manos", "Arcos", "Armas de fuego",
      "Mazas de una mano", "Mazas de dos manos", "Armas de asta", "Espadas de una mano",
      "Espadas de dos manos", "Bastones", "Armas de puño", "Misceláneo", "Dagas",
      "Armas arrojadizas", "Ballestas", "Varitas", "Cañas de pescar",
   },
   frFR = {
      "Haches à une main", "Haches à deux mains", "Arcs", "Armes à feu",
      "Masses à une main", "Masses à deux mains", "Armes d'hast",
      { "Épées à une main", "Epées à une main" },
      { "Épées à deux mains", "Epées à deux mains" },
      "Bâtons", "Armes de pugilat", "Divers", "Dagues", "Armes de jet", "Arbalètes",
      "Baguettes", "Cannes à pêche",
   },
   ruRU = {
      "Одноручные топоры", "Двуручные топоры", "Луки", "Огнестрельное оружие",
      "Одноручное дробящее оружие", "Двуручное дробящее оружие", "Древковое оружие",
      "Одноручные мечи", "Двуручные мечи", "Посохи", "Кистевое оружие", "Разное",
      "Кинжалы", "Метательное оружие", "Арбалеты", "Жезлы", "Удочки",
   },
}

local FB_ARMOR = {
   enUS = {
      "Miscellaneous", "Cloth", "Leather", "Mail", "Plate", "Shields", "Librams",
      "Idols", "Totems", "Sigils",
   },
   deDE = {
      "Verschiedenes", "Stoff", "Leder", { "Schwere Rüstung", "Kette" }, "Platte", "Schilde",
      "Buchbände", "Götzen", "Totems", "Siegel",
   },
   esES = {
      "Misceláneo", "Tela", "Cuero", "Malla", "Placas", "Escudos", "Tratados",
      "Ídolos", "Tótems", "Sellos",
   },
   frFR = {
      "Divers", "Tissu", "Cuir", "Mailles", "Plaques", "Boucliers", "Librams",
      "Idoles", "Totems", false,
   },
   ruRU = {
      "Разное", "Ткань", "Кожа", "Кольчуга", "Латы", "Щиты", "Манускрипты",
      "Идолы", "Тотемы", "Печати",
   },
}

-- Spalten, die als Gegenprobe der AH-Reihenfolge taugen
local VERIFIED = { enUS = true, deDE = true }

-- Klassennamen (Rueckfall; die AH-Liste liefert die echten Namen des Clients)
local FB_CLASS_NAMES = {
   [CLASS_WEAPON] = { "Weapon", "Waffe", "Waffen", "Arma", "Arme", "Оружие" },
   [CLASS_ARMOR]  = { "Armor", "Rüstung", "Armadura", "Armure", "Доспехи" },
}

-- Aus den Spalten gebaute Nachschlagetabellen
local fbSub = { [CLASS_WEAPON] = {}, [CLASS_ARMOR] = {} }    -- [Klasse][Name] = Unterklasse (alle Spalten)
local verSub = { [CLASS_WEAPON] = {}, [CLASS_ARMOR] = {} }   -- dito, nur verifizierte Spalten
local fbClass = {}                                            -- [Klassenname] = Klasse

local function addFallbackColumns(classId, columns)
   local ids = AH_IDS[classId]
   for code, names in pairs(columns) do
      for i = 1, #ids do
         local entry = names[i]
         if type(entry) == "string" then
            fbSub[classId][entry] = ids[i]
            if VERIFIED[code] then
               verSub[classId][entry] = ids[i]
            end
         elseif type(entry) == "table" then
            for _, spelling in ipairs(entry) do
               fbSub[classId][spelling] = ids[i]
               if VERIFIED[code] then
                  verSub[classId][spelling] = ids[i]
               end
            end
         end
      end
   end
end

addFallbackColumns(CLASS_WEAPON, FB_WEAPON)
addFallbackColumns(CLASS_ARMOR, FB_ARMOR)
for classId, names in pairs(FB_CLASS_NAMES) do
   for _, name in ipairs(names) do
      fbClass[name] = classId
   end
end

-- ---------------------------------------------------------------------------
-- Zustand
-- ---------------------------------------------------------------------------

local cache = {}                  -- [id] = info (aufgeloest)
local seenLabel = {}              -- [typeKey] = subtypeName, wie ein aufgeloestes Item ihn nannte

local queue = {}                  -- FIFO der noch nicht gesendeten IDs
local qHead, qTail = 1, 1         -- naechster Lesezeiger / naechster Schreibzeiger
local queued = {}                 -- [id] = true: steht in queue, noch nicht gesendet
local queuedCount = 0

local flight = {}                 -- Array der gesendeten, noch offenen IDs (evtl. mit veralteten Eintraegen)
local flightN = 0
local flightAt = {}               -- [id] = Sendezeit (gueltige Eintraege)
local flightCount = 0

local failedAt = {}               -- [id] = Zeitpunkt des Aufgebens
local failedCount = 0

local resolvedSince = 0           -- neu aufgeloeste Items seit dem letzten ITEMS_RESOLVED
local lastFire = -1000            -- GetTime() des letzten ITEMS_RESOLVED

local pollFrame = nil             -- Poll-Frame (OnUpdate), versteckt sich bei Leerlauf
local scanTip = nil               -- unsichtbarer GameTooltip
local polling = false             -- Poll-Frame laeuft
local acc = 0                     -- aufgelaufene Zeit seit dem letzten Takt
local lastError = nil             -- letzte gemeldete Fehlermeldung (Spam-Bremse)

-- AH-Karten (werden lazy gebaut, der Client liefert die Namen in seiner Sprache)
local mapsDone = false            -- AH-Klassenliste erfolgreich gelesen
local mapsTries = 0
local classMap = {}               -- [lokalisierter Klassenname] = 2 | 4 | false (andere Klasse)
local subMap = { [CLASS_WEAPON] = {}, [CLASS_ARMOR] = {} }   -- [Klasse][Name] = Unterklasse
local labelByKey = {}             -- [typeKey] = lokalisierter Unterklassenname
local warned = {}                 -- bereits gemeldete unbekannte Namenspaare

local typeKeyFor                  -- Vorwaertsdeklaration

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------------

-- Debug-Ausgabe, nur wenn Util existiert und T.debug gesetzt ist.
local function debugLog(fmt, ...)
   local util = T.Util
   if util and util.Debug then
      util.Debug(fmt, ...)
   end
end

-- Normalisiert eine Item-ID (Zahl, Zahl-String oder "item:123"-Link) auf eine
-- positive Ganzzahl; sonst nil.
local function toId(v)
   local tv = type(v)
   if tv == "string" then
      local n = tonumber(v)
      if not n then
         n = tonumber(strmatch(v, "item:(%d+)"))
      end
      v = n
      tv = type(v)
   end
   if tv ~= "number" then
      return nil
   end
   if not (v >= 1 and v <= MAX_ID) then   -- faengt auch NaN und inf ab
      return nil
   end
   return floor(v)
end

-- Liest alle Rueckgabewerte von fn(...) in eine Liste.
local function listOf(fn, ...)
   return { fn(...) }
end

-- Zaehlt die lueckenlosen nicht-leeren Strings am Anfang einer Liste.
local function countStrings(list)
   local n = 0
   while type(list[n + 1]) == "string" and list[n + 1] ~= "" do
      n = n + 1
   end
   return n
end

-- Meldet einen Fehler (einmal je gleicher Meldung) an den Fehler-Handler.
local function reportError(err)
   if err == lastError then
      return
   end
   lastError = err
   if type(geterrorhandler) == "function" then
      local handler = geterrorhandler()
      if type(handler) == "function" then
         handler(err)
      end
   end
end

-- ---------------------------------------------------------------------------
-- AH-Listen -> Typ-Abbildung
-- ---------------------------------------------------------------------------

-- Baut die Abbildung fuer eine Klasse aus GetAuctionItemSubClasses(ahIndex).
local function buildClassMap(classId, ahIndex)
   local ids = AH_IDS[classId]
   local ok, subs = pcall(listOf, GetAuctionItemSubClasses, ahIndex)
   if not ok or type(subs) ~= "table" then
      debugLog("Items: GetAuctionItemSubClasses(%d) fehlgeschlagen", ahIndex)
      return
   end

   local n = countStrings(subs)
   if n ~= #ids or #subs ~= n then
      -- Die Reihenfolge-Annahme waere falsch: lieber die Namenstabellen nehmen
      debugLog("Items: unerwartete AH-Unterklassenzahl fuer Klasse %d (%d statt %d)",
         classId, #subs, #ids)
      return
   end

   -- Gegenprobe: kennen die verifizierten Spalten einen der Namen, muss die
   -- Reihenfolge dasselbe ergeben, sonst ist die Annahme fuer diesen Client falsch.
   local verified = verSub[classId]
   for i = 1, n do
      local known = verified[subs[i]]
      if known ~= nil and known ~= ids[i] then
         debugLog("Items: AH-Reihenfolge fuer Klasse %d widerspricht der Namenstabelle (%s)",
            classId, subs[i])
         return
      end
   end

   local map = subMap[classId]
   for i = 1, n do
      map[subs[i]] = ids[i]
      labelByKey[classId * 100 + ids[i]] = subs[i]
   end
end

-- Baut die AH-Abbildungen genau einmal (bei leerer Klassenliste hoechstens
-- MAX_BUILD_TRIES Mal). Die Namen folgen dem CLIENT, nicht der Addon-Sprache.
local function buildMaps()
   if mapsDone or mapsTries >= MAX_BUILD_TRIES then
      return
   end
   mapsTries = mapsTries + 1

   if type(GetAuctionItemClasses) ~= "function" or type(GetAuctionItemSubClasses) ~= "function" then
      mapsTries = MAX_BUILD_TRIES
      debugLog("Items: Auktionshaus-API fehlt, Rueckfall-Tabellen werden benutzt")
      return
   end

   local ok, names = pcall(listOf, GetAuctionItemClasses)
   if not ok or type(names) ~= "table" or #names == 0 then
      return   -- noch nicht verfuegbar, spaeter erneut versuchen
   end

   mapsDone = true

   for i = 1, #names do
      local name = names[i]
      if type(name) == "string" and name ~= "" then
         local classId = false
         for _, entry in ipairs(AH_CLASS_INDEX) do
            if entry.ahIndex == i then
               classId = entry.classId
            end
         end
         classMap[name] = classId
      end
   end

   for _, entry in ipairs(AH_CLASS_INDEX) do
      buildClassMap(entry.classId, entry.ahIndex)
   end

   -- Items, die vor dem erfolgreichen Bau aufgeloest wurden, neu einstufen (die
   -- AH-Listen sind massgeblich; zuvor galt hoechstens die Namenstabelle)
   for _, info in pairs(cache) do
      info.typeKey = typeKeyFor(info.typeName, info.subtypeName, info.equipLoc)
      if info.typeKey and info.subtypeName ~= "" and seenLabel[info.typeKey] == nil then
         seenLabel[info.typeKey] = info.subtypeName
      end
   end
end

-- Leitet die Klasse (2 Waffe | 4 Ruestung) aus Klassenname bzw. Ausruestungsplatz
-- ab; nil, wenn es keine Waffe/Ruestung ist oder unklar bleibt.
local function resolveClass(typeName, equipLoc)
   if type(typeName) == "string" and typeName ~= "" then
      local classId = classMap[typeName]
      if classId == nil then
         classId = fbClass[typeName]
      end
      if classId == false then
         return nil   -- bekannte andere Klasse (Behaelter, Handwerkswaren ...)
      end
      if classId then
         return classId
      end
   end
   if type(equipLoc) == "string" then
      return LOC_CLASS[equipLoc]
   end
   return nil
end

-- Rechnet lokalisierte Klassen-/Unterklassennamen in typeKey um (siehe
-- Items.TypeKeyFromNames).
typeKeyFor = function(typeName, subtypeName, equipLoc)
   if type(subtypeName) ~= "string" or subtypeName == "" then
      return nil
   end
   buildMaps()

   local classId = resolveClass(typeName, equipLoc)
   if not classId then
      if type(typeName) == "string" and typeName ~= "" and classMap[typeName] == nil
         and fbClass[typeName] == nil then
         local key = tostring(typeName) .. "|" .. subtypeName
         if not warned[key] then
            warned[key] = true
            debugLog("Items: unbekannte Item-Klasse '%s' (%s)", typeName, subtypeName)
         end
      end
      return nil
   end

   local subId = subMap[classId][subtypeName]
   if subId == nil then
      subId = fbSub[classId][subtypeName]
   end
   if subId == nil then
      local key = classId .. "|" .. subtypeName
      if not warned[key] then
         warned[key] = true
         debugLog("Items: unbekannte Unterklasse '%s' (Klasse %d)", subtypeName, classId)
      end
      return nil
   end
   return classId * 100 + subId
end

-- ---------------------------------------------------------------------------
-- Poll-Frame und Scan-Tooltip
-- ---------------------------------------------------------------------------

local onUpdate   -- Vorwaertsdeklaration

-- Legt den (versteckten) Poll-Frame einmalig an; nil, wenn CreateFrame fehlt.
local function ensureFrame()
   if pollFrame then
      return pollFrame
   end
   if type(CreateFrame) ~= "function" then
      return nil
   end
   pollFrame = CreateFrame("Frame")
   pollFrame:Hide()
   pollFrame:SetScript("OnUpdate", onUpdate)
   return pollFrame
end

-- Legt den Scan-Tooltip einmalig an; nil bei Fehlschlag.
local function ensureTooltip()
   if scanTip then
      return scanTip
   end
   if type(CreateFrame) ~= "function" then
      return nil
   end
   local ok, tip = pcall(CreateFrame, "GameTooltip", "TransmogScanTooltip", UIParent, "GameTooltipTemplate")
   if ok and tip then
      scanTip = tip
   end
   return scanTip
end

-- Weckt den Poll-Frame auf (billig, wenn er schon laeuft).
local function startPolling()
   if polling then
      return
   end
   local frame = ensureFrame()
   if not frame then
      return
   end
   polling = true
   acc = POLL_INTERVAL   -- erster Takt schon im naechsten Frame
   frame:Show()
end

-- ---------------------------------------------------------------------------
-- Aufloesung
-- ---------------------------------------------------------------------------

-- Liest GetItemInfo(n) und legt bei Erfolg den Cache-Eintrag an; liefert info
-- oder nil. IDs, die in der Warteschlange/in Abfrage/als failed vermerkt waren
-- (oder bei countIt), zaehlen als neu aufgeloest und wecken den Poll-Frame, damit
-- ITEMS_RESOLVED zugestellt wird.
local function fetch(n, countIt)
   if type(GetItemInfo) ~= "function" then
      return nil
   end
   local name, link, quality, ilvl, minLevel, typeName, subtypeName, _, equipLoc, icon = GetItemInfo(n)
   if type(name) ~= "string" or name == "" then
      return nil
   end

   if type(typeName) ~= "string" then typeName = "" end
   if type(subtypeName) ~= "string" then subtypeName = "" end
   if type(equipLoc) ~= "string" then equipLoc = "" end
   if type(link) ~= "string" or link == "" then link = "item:" .. n end
   if type(icon) ~= "string" or icon == "" then icon = FALLBACK_ICON end

   local info = {
      id = n,
      name = name,
      link = link,
      quality = tonumber(quality) or 1,
      ilvl = tonumber(ilvl) or 0,
      minLevel = tonumber(minLevel) or 0,
      typeName = typeName,
      subtypeName = subtypeName,
      equipLoc = equipLoc,
      icon = icon,
      typeKey = typeKeyFor(typeName, subtypeName, equipLoc),
   }
   cache[n] = info

   if info.typeKey and subtypeName ~= "" and seenLabel[info.typeKey] == nil then
      seenLabel[info.typeKey] = subtypeName
   end

   -- Buchfuehrung
   local tracked = countIt and true or false
   if queued[n] then
      queued[n] = nil
      queuedCount = queuedCount - 1
      tracked = true
   end
   if flightAt[n] then
      flightAt[n] = nil
      flightCount = flightCount - 1
      tracked = true
   end
   if failedAt[n] then
      failedAt[n] = nil
      failedCount = failedCount - 1
      tracked = true
   end
   if tracked then
      resolvedSince = resolvedSince + 1
      startPolling()
   end
   return info
end

-- Reiht die ID in die Warteschlange ein bzw. loest sie sofort auf, wenn sie schon
-- im Client-Cache liegt. skipFetch: GetItemInfo wurde gerade erst negativ befragt.
-- Rueckgabe: true, wenn die ID aufgeloest ist.
local function requestId(n, skipFetch)
   if cache[n] then
      return true
   end
   if queued[n] or flightAt[n] then
      return false
   end
   if n == (T.HIDDEN_ID or 999999) then
      return false   -- Pseudo-Item "verborgen": kein echter Gegenstand, nie abfragen
   end

   local failTime = failedAt[n]
   if failTime then
      if GetTime() - failTime < RETRY_AFTER then
         return false
      end
      failedAt[n] = nil
      failedCount = failedCount - 1
   end

   if not skipFetch and fetch(n, true) then
      return true
   end

   queued[n] = true
   queuedCount = queuedCount + 1
   queue[qTail] = n
   qTail = qTail + 1
   startPolling()
   return false
end

-- ---------------------------------------------------------------------------
-- Poll-Takt
-- ---------------------------------------------------------------------------

-- Prueft alle offenen Abfragen: aufgeloeste uebernehmen, zu alte aufgeben.
local function pollFlight(now)
   local i = flightN
   local gaveUp, firstGaveUp = 0, nil
   while i >= 1 do
      local id = flight[i]
      local sentAt = flightAt[id]
      local drop = false
      if not sentAt then
         drop = true   -- zwischenzeitlich anderweitig aufgeloest
      elseif fetch(id) then
         drop = true   -- fetch hat flightAt/Zaehler bereits bereinigt
      elseif now - sentAt >= GIVE_UP_AFTER then
         flightAt[id] = nil
         flightCount = flightCount - 1
         failedAt[id] = now
         failedCount = failedCount + 1
         drop = true
         gaveUp = gaveUp + 1
         firstGaveUp = firstGaveUp or id
      end
      if drop then
         flight[i] = flight[flightN]
         flight[flightN] = nil
         flightN = flightN - 1
      end
      i = i - 1
   end
   if gaveUp > 0 then
      -- eine Zeile je Takt (nicht je Item), sonst flutet der Debug-Modus den Chat
      debugLog("Items: %d Abfragen nach %d s aufgegeben (z.B. Item %d)", gaveUp, GIVE_UP_AFTER, firstGaveUp)
   end
end

-- Sendet hoechstens MAX_SEND_PER_TICK neue Abfragen aus der Warteschlange.
local function dispatch(now)
   local sent, popped = 0, 0
   local tip = nil
   while qHead < qTail and sent < MAX_SEND_PER_TICK and popped < MAX_POP_PER_TICK do
      local id = queue[qHead]
      queue[qHead] = nil
      qHead = qHead + 1
      popped = popped + 1

      -- queued[id] == nil: zwischenzeitlich aufgeloest (lazy geloescht)
      if queued[id] and not fetch(id) then
         queued[id] = nil
         queuedCount = queuedCount - 1
         flightAt[id] = now
         flightCount = flightCount + 1
         flightN = flightN + 1
         flight[flightN] = id

         if not tip then
            -- Besitzer je Takt neu setzen (geht verloren, wenn der alte Besitzer
            -- versteckt wurde); UIParent + ANCHOR_NONE, der Tooltip wird nie gezeigt
            tip = ensureTooltip()
            if tip then
               local ok, err = pcall(tip.SetOwner, tip, UIParent, "ANCHOR_NONE")
               if not ok then
                  debugLog("Items: SetOwner fehlgeschlagen: %s", tostring(err))
               end
            end
         end
         if tip then
            local ok, err = pcall(tip.SetHyperlink, tip, "item:" .. id)
            if not ok then
               debugLog("Items: SetHyperlink(%d) fehlgeschlagen: %s", id, tostring(err))
            end
         end
         sent = sent + 1
      end
   end

   if qHead >= qTail then
      -- Warteschlange leer: Zeiger zuruecksetzen (kein Wachstum ueber die Zeit)
      qHead, qTail = 1, 1
   end
end

-- Feuert ITEMS_RESOLVED, hoechstens alle FIRE_INTERVAL Sekunden gebuendelt.
local function flushEvent(now)
   if resolvedSince > 0 and now - lastFire >= FIRE_INTERVAL then
      local count = resolvedSince
      resolvedSince = 0
      lastFire = now
      local events = T.Events
      if events and events.Fire then
         events.Fire("ITEMS_RESOLVED", count)
      end
   end
end

-- Ein Takt: offene Abfragen pruefen, neue senden, Ereignis feuern.
local function tick(now)
   pollFlight(now)
   dispatch(now)
   flushEvent(now)
end

-- OnUpdate des Poll-Frames; versteckt den Frame, wenn nichts mehr ansteht.
onUpdate = function(self, elapsed)
   acc = acc + (elapsed or 0)
   if acc < POLL_INTERVAL then
      return
   end
   acc = 0

   local ok, err = pcall(tick, GetTime())
   if not ok then
      reportError(err)
   end

   if queuedCount <= 0 and flightCount <= 0 and resolvedSince <= 0 then
      -- Leerlauf: Leichen wegraeumen und schlafen legen
      if flightN > 0 then
         flight = {}
         flightN = 0
      end
      if qHead ~= qTail then
         queue = {}
         qHead, qTail = 1, 1
      end
      queuedCount, flightCount = 0, 0
      polling = false
      self:Hide()
   end
end

-- ---------------------------------------------------------------------------
-- Oeffentliche API
-- ---------------------------------------------------------------------------

-- Legt Poll-Frame und Scan-Tooltip an und liest die AH-Listen; keine Rueckgabe.
function Items.Init()
   ensureFrame()
   ensureTooltip()
   buildMaps()
end

-- Cache-Lookup: info-Tabelle oder nil (noch unbekannt); loest nie eine Abfrage aus.
function Items.Info(id)
   local n = toId(id)
   if not n then
      return nil
   end
   return cache[n] or fetch(n, false)
end

-- Stellt eine Abfrage in die Warteschlange (idempotent, billig); true, wenn die
-- Daten bereits vorliegen.
function Items.Request(id)
   local n = toId(id)
   if not n then
      return false
   end
   return requestId(n, false)
end

-- Fragt viele IDs an (Array); gedrosselt abgearbeitet; keine Rueckgabe.
function Items.RequestMany(array)
   if type(array) ~= "table" then
      return
   end
   for i = 1, #array do
      local n = toId(array[i])
      if n then
         requestId(n, false)
      end
   end
end

-- true, wenn die Item-Daten bekannt sind.
function Items.IsResolved(id)
   return Items.Info(id) ~= nil
end

-- Anzahl noch ausstehender Abfragen (wartend + gesendet).
function Items.PendingCount()
   return queuedCount + flightCount
end

-- true, wenn die ID aufgegeben wurde und noch nicht erneut versucht werden darf.
function Items.IsFailed(id)
   local n = toId(id)
   if not n or cache[n] then
      return false
   end
   return failedAt[n] ~= nil
end

-- Anzahl aufgegebener (failed) IDs, die noch nicht aufgeloest wurden.
function Items.FailedCount()
   return failedCount
end

-- Info(id); ist sie unbekannt, wird zusaetzlich Request(id) gestellt. Rueckgabe: info | nil.
function Items.Get(id)
   local n = toId(id)
   if not n then
      return nil
   end
   local info = cache[n] or fetch(n, false)
   if info then
      return info
   end
   requestId(n, true)
   return nil
end

-- Item-Link: der echte Link aus GetItemInfo, sonst "item:ID" (leer bei ungueltiger ID).
function Items.Link(id)
   local n = toId(id)
   if not n then
      return ""
   end
   local info = cache[n] or fetch(n, false)
   if info and info.link then
      return info.link
   end
   return "item:" .. n
end

-- Rechnet lokalisierte Klassen-/Unterklassennamen in den typeKey um
-- (Klasse*100 + Unterklasse; Waffe 2xx, Ruestung 4xx); nil bei unbekannten
-- Namen. equipLoc ist optional und dient nur als Rueckfall fuer die Klasse.
function Items.TypeKeyFromNames(typeName, subtypeName, equipLoc)
   return typeKeyFor(typeName, subtypeName, equipLoc)
end

-- Lokalisierter Typname (aus den AH-Listen des Clients), sonst der zuletzt
-- gesehene subtypeName dieses typeKey, sonst nil.
function Items.TypeLabel(typeKey)
   local key = tonumber(typeKey)
   if not key then
      return nil
   end
   buildMaps()
   return labelByKey[key] or seenLabel[key]
end

-- true, wenn der Ausruestungsplatz nie transmogbar ist (Items.NEVER).
function Items.IsNever(equipLoc)
   return type(equipLoc) == "string" and Items.NEVER[equipLoc] ~= nil
end

-- Diagnose: Liste von Textzeilen ueber die gelesene Typ-Abbildung (zum Ausgeben
-- durch den Aufrufer, z.B. /transmog debug).
function Items.DumpTypes()
   buildMaps()
   local lines = {}
   local locale = "?"
   if type(GetLocale) == "function" then
      locale = tostring(GetLocale())
   end
   lines[#lines + 1] = "locale=" .. locale .. " ah=" .. tostring(mapsDone)
   local keys = {}
   for key in pairs(labelByKey) do
      keys[#keys + 1] = key
   end
   tsort(keys)
   for _, key in ipairs(keys) do
      lines[#lines + 1] = key .. " = " .. labelByKey[key]
   end
   return lines
end
