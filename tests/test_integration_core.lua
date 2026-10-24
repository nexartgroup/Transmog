-- tests/test_integration_core.lua
-- ---------------------------------------------------------------------------
-- Integrationstest der Kernmodule ZUSAMMEN (Locale, Util, Events, DB, Slots,
-- Items, Net, State, Filter, Outfits) gegen einen kleinen Server-Nachbau.
--
-- Die Einzeltests (test_netstate, test_filter ...) pruefen je ein Modul. Hier
-- laeuft ein realistischer Abend durch die ECHTEN Module:
--
--   Anmeldung (14 Slots angelegt, Status, 14 Listenstroeme in Stuecken) ->
--   Gegenstaende laufen ueber die Zeit im Cache ein (Filter folgt) -> Auswahl,
--   Kostenabfrage, Anwenden (Erfolg, Fehlschlag, Verborgen, Entfernen) ->
--   Outfit speichern/laden -> Ausruestungswechsel mitten in der Sitzung ->
--   Sprachwechsel -> Neuanmeldung mit den gespeicherten Variablen.
--
-- Zusaetzlich geprueft: keine Handlerfehler (M.errors), keine fremden Globals
-- (Vergleich von _G vor/nach dem Laden), keine fremden benannten Frames, kein
-- OnUpdate im Leerlauf, keine fehlenden Locale-Schluessel zur Laufzeit.
--
-- Die Oberflaeche (UI\Window ...), Features und Boot duerfen fehlen: dann
-- uebernimmt der Test die Aufgaben von Core\Boot.lua in der Reihenfolge aus
-- SPEC 3 (DB.Init -> Locale.Set -> Slots/Items/Net/State/Outfits.Init).
-- Existiert Boot, laeuft dessen echter Ablauf (ADDON_LOADED/PLAYER_LOGIN).
--
-- Aufruf:  cd <Addon>;  luajit tests/run.lua integration_core
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   -- -----------------------------------------------------------------------
   -- Konstanten
   -- -----------------------------------------------------------------------

   local HEAD, SHOULDER, SHIRT, CHEST, WAIST, LEGS, FEET, WRIST, HANDS = 0, 2, 3, 4, 5, 6, 7, 8, 9
   local BACK, MAINHAND, OFFHAND, RANGED, TABARD = 14, 15, 16, 17, 18
   local SERVER_SLOTS = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }
   local HIDEABLE = {
      [0] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
      [7] = true, [8] = true, [9] = true, [14] = true, [18] = true,
   }
   local HIDDEN = 999999
   local PRICE = 10000   -- 1 Gold je Aussehen

   -- Klassen-/Unterklassen-IDs (Bucket des Servers = Klasse + Unterklasse)
   local CLASS_ID = { Weapon = 2, Armor = 4 }
   local SUB_ID = {
      Armor = { Miscellaneous = 0, Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Shields = 6, Idols = 8 },
      Weapon = { ["One-Handed Swords"] = 7, Bows = 2 },
   }
   -- Ruestungsstufen fuer "niedrigere Stufen erlaubt"
   local TIER = { Cloth = 1, Leather = 2, Mail = 3, Plate = 4 }

   -- Angelegte Gegenstaende je Server-Slot
   local EQUIP = {
      [HEAD]     = { loc = "INVTYPE_HEAD",     class = "Armor",  sub = "Plate" },
      [SHOULDER] = { loc = "INVTYPE_SHOULDER", class = "Armor",  sub = "Plate" },
      [SHIRT]    = { loc = "INVTYPE_BODY",     class = "Armor",  sub = "Miscellaneous" },
      [CHEST]    = { loc = "INVTYPE_CHEST",    class = "Armor",  sub = "Plate" },
      [WAIST]    = { loc = "INVTYPE_WAIST",    class = "Armor",  sub = "Plate" },
      [LEGS]     = { loc = "INVTYPE_LEGS",     class = "Armor",  sub = "Plate" },
      [FEET]     = { loc = "INVTYPE_FEET",     class = "Armor",  sub = "Plate" },
      [WRIST]    = { loc = "INVTYPE_WRIST",    class = "Armor",  sub = "Plate" },
      [HANDS]    = { loc = "INVTYPE_HAND",     class = "Armor",  sub = "Plate" },
      [BACK]     = { loc = "INVTYPE_CLOAK",    class = "Armor",  sub = "Cloth" },
      [MAINHAND] = { loc = "INVTYPE_WEAPON",   class = "Weapon", sub = "One-Handed Swords" },
      [OFFHAND]  = { loc = "INVTYPE_SHIELD",   class = "Armor",  sub = "Shields" },
      [RANGED]   = { loc = "INVTYPE_RANGED",   class = "Weapon", sub = "Bows" },
      [TABARD]   = { loc = "INVTYPE_TABARD",   class = "Armor",  sub = "Miscellaneous" },
   }

   -- Anzahl der Kandidaten je Slot (Kopf hat gemischte Ruestungsstufen)
   local COUNT = {
      [HEAD] = 41, [SHOULDER] = 8, [SHIRT] = 6, [CHEST] = 9, [WAIST] = 8, [LEGS] = 8,
      [FEET] = 8, [WRIST] = 8, [HANDS] = 8, [BACK] = 8, [MAINHAND] = 24, [OFFHAND] = 6,
      [RANGED] = 7, [TABARD] = 5,
   }

   local function equipId(slot) return 1000 + slot end
   local function candId(slot, i) return 2000 + slot * 100 + i end

   -- Kopf: 25 Platte, 6 Kette, 5 Leder, 5 Stoff
   local function headSub(i)
      if i <= 25 then return "Plate" end
      if i <= 31 then return "Mail" end
      if i <= 36 then return "Leather" end
      return "Cloth"
   end

   -- -----------------------------------------------------------------------
   -- Gegenstandsdaten (M.items) und Metadaten fuer den Server-Nachbau
   -- -----------------------------------------------------------------------

   local META = {}          -- [id] = { slot=, class=, sub=, loc=, quality=, name= }
   local CANDIDATES = {}    -- [slot] = { ids }

   local function buildItems()
      local items = {}
      META = {}
      CANDIDATES = {}

      local function add(id, slot, name, quality, class, sub, loc, icon)
         items[id] = {
            name = name, quality = quality, ilvl = 100 + (id % 100), minLevel = 0,
            class = class, subclass = sub, equipLoc = loc,
            icon = icon or ("Interface\\Icons\\INV_Test_" .. id),
         }
         META[id] = { slot = slot, class = class, sub = sub, loc = loc, quality = quality, name = name }
      end

      for _, slot in ipairs(SERVER_SLOTS) do
         local def = EQUIP[slot]
         add(equipId(slot), slot, "Equipped " .. slot, 3, def.class, def.sub, def.loc)
         CANDIDATES[slot] = {}
         for i = 1, COUNT[slot] do
            local id = candId(slot, i)
            local sub = def.sub
            if slot == HEAD then sub = headSub(i) end
            local quality = i % 5            -- 0 (schlecht) .. 4 (episch)
            local icon = nil
            if slot == HEAD and (i == 1 or i == 2) then
               icon = "Interface\\Icons\\INV_Test_Duplicate"   -- gleiches Aussehen
            end
            add(id, slot, string.format("Look %d-%02d", slot, i), quality, def.class, sub, def.loc, icon)
            CANDIDATES[slot][#CANDIDATES[slot] + 1] = id
         end
      end

      -- ein Beinstueck aus Kette: gesammelt, passt aber nicht zu Plattenbeinen
      add(2699, LEGS, "Mail Legs Appearance", 3, "Armor", "Mail", "INVTYPE_LEGS")
      CANDIDATES[LEGS][#CANDIDATES[LEGS] + 1] = 2699

      -- Ersatz-Ausruestung fuer den Wechsel mitten in der Sitzung
      add(1100, HEAD, "Replacement Mail Helm", 4, "Armor", "Mail", "INVTYPE_HEAD")
      add(1102, SHOULDER, "Replacement Mail Pauldrons", 4, "Armor", "Mail", "INVTYPE_SHOULDER")
      add(1117, RANGED, "Idol of Testing", 3, "Armor", "Idols", "INVTYPE_RELIC")

      -- Nicht transmogbare Plaetze (werden von State ignoriert)
      add(1201, 1, "Test Amulet", 3, "Armor", "Miscellaneous", "INVTYPE_NECK")
      add(1202, 10, "Test Ring A", 3, "Armor", "Miscellaneous", "INVTYPE_FINGER")
      add(1203, 11, "Test Ring B", 3, "Armor", "Miscellaneous", "INVTYPE_FINGER")
      add(1204, 12, "Test Trinket A", 3, "Armor", "Miscellaneous", "INVTYPE_TRINKET")
      add(1205, 13, "Test Trinket B", 3, "Armor", "Miscellaneous", "INVTYPE_TRINKET")
      return items
   end

   -- Client-Inventar-ID -> Gegenstand (14 transmogbare Slots + Hals/Ringe/Schmuck)
   local function defaultEquipment()
      local eq = {}
      for _, slot in ipairs(SERVER_SLOTS) do eq[slot + 1] = equipId(slot) end
      eq[2] = 1201
      eq[11], eq[12] = 1202, 1203
      eq[13], eq[14] = 1204, 1205
      return eq
   end

   -- -----------------------------------------------------------------------
   -- Server-Nachbau (spiegelt TransmogAddonProtocol.cpp / Transmog.cpp)
   -- -----------------------------------------------------------------------

   local function newServer()
      local s = {
         stored = {},          -- [slot] = fake (nur Slots mit Aussehen)
         collected = {},       -- [id] = true
         reject = {},          -- [id] = true: Apply liefert 0
         drop = {},            -- [befehl] = n: die naechsten n Antworten gehen verloren
         queue = {},           -- { due=, msg= }
         log = {},             -- alle empfangenen Befehle
         price = PRICE,
         latency = 0.1,        -- Sekunden bis zur Antwort
         lowerTiers = false,   -- AllowLowerTiers
         mute = false,         -- true: das Modul antwortet nie (nicht installiert)
         seen = 0,             -- verarbeitete Eintraege von M.sentAddon
      }

      for _, ids in pairs(CANDIDATES) do
         for _, id in ipairs(ids) do s.collected[id] = true end
      end

      local function equippedId(slot)
         return M.world.equipment[slot + 1]
      end

      -- Passt das Aussehen id zum angelegten Gegenstand des Slots?
      function s.valid(slot, id)
         local eq = equippedId(slot)
         local m, em = META[id], eq and META[eq]
         if not eq or not em or not m then return false end
         if m.slot ~= slot or id == eq then return false end
         if m.class ~= em.class then return false end
         if m.sub == em.sub then return true end
         if s.lowerTiers and TIER[m.sub] and TIER[em.sub] and TIER[m.sub] <= TIER[em.sub] then
            return true
         end
         return false
      end

      -- Liste des Slots (Qualitaet absteigend, dann Name) und Bucket
      function s.list(slot)
         local eq = equippedId(slot)
         if not eq then return {}, 0 end
         local out = {}
         for _, id in ipairs(CANDIDATES[slot] or {}) do
            if s.collected[id] and s.valid(slot, id) then out[#out + 1] = id end
         end
         table.sort(out, function(a, b)
            local qa, qb = META[a].quality, META[b].quality
            if qa ~= qb then return qa > qb end
            if META[a].name ~= META[b].name then return META[a].name < META[b].name end
            return a < b
         end)
         local em = META[eq]
         if not em then return {}, 0 end
         local bucket = (CLASS_ID[em.class] or 0) + ((SUB_ID[em.class] or {})[em.sub] or 0)
         return out, bucket
      end

      -- Antworten. Ein stummer Server verschluckt ALLES ausser Kostenantworten:
      -- State ordnet CalculateCost-Antworten rein ueber Zaehler (FIFO) zu, ein
      -- verlorenes Paket verschiebt die Zaehler bis zur naechsten Zeitueber-
      -- schreitung (siehe test_integration_core, bekannte Grenze). TCP verliert
      -- nichts; das Modell dort ist "Antwort kommt immer".
      local function emit(msg)
         if s.mute and msg:sub(1, 13) ~= "TransmogCost:" then return end
         s.queue[#s.queue + 1] = { due = M.now + s.latency, msg = msg }
      end

      local function statusMsg()
         local parts, n = {}, 0
         for slot = 0, 18 do
            local fake = s.stored[slot]
            if fake and fake ~= 0 then
               parts[#parts + 1] = ":" .. slot .. "," .. fake
               n = n + 1
            end
         end
         if n == 0 then return "TransmogStatus:0" end
         return "TransmogStatus:" .. n .. table.concat(parts)
      end

      local function pay(cost)
         if cost > 0 then
            M.world.money = M.world.money - cost
            M.Fire("PLAYER_MONEY")
         end
      end

      -- Ein Befehl des Clients
      function s.handle(text)
         s.log[#s.log + 1] = text
         local colon = text:find(":", 1, true)
         local cmd = colon and text:sub(1, colon - 1) or text
         local args = colon and text:sub(colon + 1) or ""

         local function reply(msg)
            if s.drop[cmd] and s.drop[cmd] > 0 then
               s.drop[cmd] = s.drop[cmd] - 1
               return
            end
            emit(msg)
         end

         if cmd == "GetTransmogStatus" then
            reply(statusMsg())
         elseif cmd == "GetAvailableTransmogs" then
            for _, slot in ipairs(SERVER_SLOTS) do
               local ids, bucket = s.list(slot)
               local header = "AvailableTransmogs:" .. slot .. ":" .. bucket .. ":" .. #ids .. ":"
               reply(header .. "start")
               local i = 1
               while i <= #ids do
                  local j = math.min(i + 19, #ids)
                  local parts = {}
                  for k = i, j do parts[#parts + 1] = tostring(ids[k]) end
                  reply(header .. table.concat(parts, ":"))
                  i = j + 1
               end
               reply(header .. "end")
            end
         elseif cmd == "GetCollectionStatus" then
            local id = tonumber(args:match("^(%d+)$"))
            if not id or id == 0 then return end
            local m = META[id]
            local state = 0
            if not m then
               state = 2
            elseif s.collected[id] then
               state = 1
            end
            reply("CollectionStatus:" .. id .. ":" .. state)
         elseif cmd == "Apply" then
            local a, b = args:match("^(%d+):(%d+)$")
            local slot, id = tonumber(a), tonumber(b)
            if not slot or not id or slot >= 19 or id == 0 then
               reply("ApplyTransmogResult:0")
               return
            end
            local ok = false
            if s.stored[slot] == id then
               ok = true
            elseif not equippedId(slot) then
               ok = false
            elseif id == HIDDEN then
               ok = HIDEABLE[slot] == true
            elseif s.collected[id] and not s.reject[id] and s.valid(slot, id) then
               if M.world.money >= s.price then
                  pay(s.price)
                  ok = true
               end
            end
            if ok then
               s.stored[slot] = id
               reply("ApplyTransmogResult:1:" .. slot .. "," .. id)
            else
               reply("ApplyTransmogResult:0")
            end
         elseif cmd == "Remove" then
            local slot = tonumber(args:match("^(%d+)$"))
            if not slot or slot >= 19 then
               reply("ApplyTransmogResult:0")
               return
            end
            s.stored[slot] = nil
            reply("ApplyTransmogResult:1:" .. slot .. ",0")
         elseif cmd == "RemoveAll" then
            s.stored = {}
            reply(statusMsg())
         elseif cmd == "CalculateCost" then
            local total = 0
            for pair in args:gmatch("[^,]+") do
               local a, b = pair:match("^(%d+):(%d+)$")
               local slot, id = tonumber(a), tonumber(b)
               if slot and id and slot < 19 and id ~= 0 then
                  total = total + (id == HIDDEN and 0 or s.price)
               end
            end
            reply("TransmogCost:" .. total .. ":" .. (M.world.money >= total and 1 or 0))
         end
      end

      -- Neue Befehle des Clients annehmen, faellige Antworten ausliefern.
      -- Eine Zustellung kann neue Befehle ausloesen: darum in einer Schleife.
      function s.pump()
         for _ = 1, 50 do
            local progressed = false
            local sent = M.sentAddon
            while s.seen < #sent do
               s.seen = s.seen + 1
               local e = sent[s.seen]
               if e.prefix == "transmog" then s.handle(e.msg) end
               progressed = true
            end
            local i = 1
            while i <= #s.queue do
               local q = s.queue[i]
               if q.due <= M.now + 1e-9 then
                  table.remove(s.queue, i)
                  M.ServerMessage(q.msg)
                  progressed = true
               else
                  i = i + 1
               end
            end
            if not progressed then break end
         end
      end

      function s.count(prefix)
         local n = 0
         for _, c in ipairs(s.log) do
            if c:sub(1, #prefix) == prefix then n = n + 1 end
         end
         return n
      end

      return s
   end

   -- -----------------------------------------------------------------------
   -- Sitzung
   -- -----------------------------------------------------------------------

   local T, State, Net, Filter, Outfits, Items, DB, Util, Locale, Events
   local srv = nil
   local log = {}                -- Busereignisse { name=, n=, ... }
   local globalsBefore = nil     -- Menge der _G-Schluessel vor dem Laden

   local BUS = {
      "LOCALE_CHANGED", "SETTINGS_CHANGED", "ITEMS_RESOLVED", "STATUS_CHANGED",
      "LIST_PROGRESS", "LIST_READY", "EQUIPMENT_CHANGED", "WANTED_CHANGED", "COST_CHANGED",
      "APPLY_STARTED", "APPLY_PROGRESS", "APPLY_DONE", "COLLECTION_UPDATED",
      "COLLECTION_STATUS", "SERVER_OPEN", "SERVER_STATE", "VENDOR_CHANGED",
      "OUTFITS_CHANGED", "FAVORITES_CHANGED", "FILTER_CHANGED",
   }

   local function evList(name)
      local out = {}
      for _, e in ipairs(log) do
         if e.name == name then out[#out + 1] = e end
      end
      return out
   end

   local function evCount(name) return #evList(name) end

   local function evLast(name)
      local l = evList(name)
      return l[#l]
   end

   local function clearLog()
      for i = #log, 1, -1 do log[i] = nil end
   end

   local function snapshotGlobals()
      local set = {}
      for k in pairs(_G) do set[k] = true end
      return set
   end

   -- Zeit vorstellen; der Server-Nachbau wird in jedem Schritt bedient.
   local function settle(seconds, step)
      step = step or 0.05
      local t = 0
      srv.pump()
      while t < seconds - 1e-9 do
         local d = math.min(step, seconds - t)
         M.Advance(d, d)
         t = t + d
         srv.pump()
      end
   end

   local function clearSent()
      M.ClearSent()
      srv.seen = 0
   end

   -- Fehler der Handler: der Test schlaegt sonst am Ende ohnehin fehl, aber mit
   -- der Phase im Text findet man die Stelle schneller.
   local function noErrors(where)
      local n = #M.errors
      H.eq(n, 0, (where or "?") .. ": Handlerfehler " .. tostring(M.errors[1]))
   end

   -- Startet eine Sitzung: Attrappe, TOC, Boot (echt oder nachgebildet),
   -- Server-Nachbau, Ereignisprotokoll. opts:
   --   equipment  [Client-Slot] = id   (Standard: alle 14 + Hals/Ringe/Schmuck)
   --   stored     [Server-Slot] = fake (Aussehen am Server)
   --   saved      SavedVariables einer frueheren Sitzung
   --   locale     Client-Sprache
   --   mute       Server antwortet nicht
   --   enterWorld false: PLAYER_ENTERING_WORLD nicht feuern
   local function startSession(opts)
      opts = opts or {}
      local bootOpts = {
         world = {
            equipment = opts.equipment or defaultEquipment(),
            money = opts.money or 50000000,
            locale = opts.locale or "enUS",
         },
         items = buildItems(),
         globals = opts.saved,
         login = true,
         enterWorld = false,
      }
      H.install(bootOpts)                      -- nur, um die Globalliste vorher zu kennen
      globalsBefore = snapshotGlobals()
      T = H.boot(bootOpts)
      H.assert(type(T) == "table", "Transmog wurde nicht geladen")

      DB, Util, Locale, Events = T.DB, T.Util, T.Locale, T.Events
      Net, State, Filter, Outfits, Items = T.Net, T.State, T.Filter, T.Outfits, T.Items

      -- Ohne Core\Boot.lua den Ablauf aus SPEC 3 / 6.13 nachbilden.
      local ownBoot = false
      if not (DB.global and DB.char) then
         ownBoot = true
         DB.Init()
         Locale.Set(DB.global.locale)
         T.RefreshPlayerInfo()
         T.Slots.Init()
         Items.Init()
         Net.Init()
         State.Init()
         Outfits.Init()
         if T.Tooltips and T.Tooltips.Init then T.Tooltips.Init() end
         if T.Toasts and T.Toasts.Init then T.Toasts.Init() end
      end

      State.chatMessages = true                -- (eine Oberflaeche darf es abschalten)

      srv = newServer()
      srv.mute = opts.mute and true or false
      for slot, fake in pairs(opts.stored or {}) do srv.stored[slot] = fake end

      clearLog()
      for _, name in ipairs(BUS) do
         Events.On(name, function(...)
            log[#log + 1] = { name = name, n = select("#", ...), ... }
         end, log)
      end

      if opts.enterWorld ~= false then
         M.Fire("PLAYER_ENTERING_WORLD")
         if ownBoot then
            T.enteredWorldAt = GetTime()
            Util.Debounce("boot-refresh", 2, State.Refresh)
         end
      end
      return ownBoot
   end

   local function allowedGlobal(name)
      -- SPEC 1, Regel 7 (/xmog ist SLASH_TRANSMOG2, kein eigener Name)
      return name:find("^Transmog") or name:find("^SLASH_TRANSMOG%d+$")
         or name == "BINDING_HEADER_TRANSMOG" or name:find("^BINDING_NAME_TRANSMOG_")
         or name == "transmogOutfits" or name == "transmogSettings"
   end

   -- Neue Globals seit vor dem Laden, die nicht erlaubt sind
   local function strayGlobals()
      local out = {}
      for k in pairs(_G) do
         if not globalsBefore[k] and not allowedGlobal(tostring(k)) then
            out[#out + 1] = tostring(k)
         end
      end
      table.sort(out)
      return out
   end

   -- Slots, in denen eine Liste fertig ist, und ihre Eintraege vergleichen
   local function listIds(slot)
      return State.List(slot).ids
   end

   local function idsOf(entries)
      local out = {}
      for i, e in ipairs(entries) do out[i] = e.id end
      return out
   end

   local function contains(list, id)
      for _, v in ipairs(list) do
         if v == id then return true end
      end
      return false
   end

   -- ======================================================================
   -- 1. Das grosse Szenario
   -- ======================================================================

   H.test("Szenario: Anmeldung -> Items -> Auswahl -> Anwenden -> Outfit -> Wechsel -> Sprache -> Neuanmeldung", function()
      startSession({
         stored = { [HEAD] = candId(HEAD, 3), [CHEST] = HIDDEN, [LEGS] = 2699, [MAINHAND] = candId(MAINHAND, 15) },
      })

      -- ----------------------------------------------------------------
      -- A. Anmeldung
      -- ----------------------------------------------------------------
      H.eq(State.StatusKnown(), false, "A: vor der Abfrage kein Status")
      for _, slot in ipairs(SERVER_SLOTS) do
         H.eq(State.SlotState(slot), "READY", "A: SlotState " .. slot)
         local eq = State.Equipped(slot)
         H.truthy(eq, "A: Equipped " .. slot)
         if eq then
            H.eq(eq.id, equipId(slot), "A: Equipped.id " .. slot)
            H.eq(eq.equipLoc, EQUIP[slot].loc, "A: Equipped.equipLoc " .. slot)
            H.eq(eq.name, "Equipped " .. slot, "A: Equipped.name " .. slot)
            H.eq(eq.quality, 3, "A: Equipped.quality " .. slot)
         end
      end
      H.eq(State.Equipped(HEAD).typeKey, 404, "A: Platte = 404")
      H.eq(State.Equipped(MAINHAND).typeKey, 207, "A: Einhandschwert = 207")
      H.eq(State.Equipped(BACK).typeKey, 401, "A: Stoff = 401")
      H.eq(State.Equipped(OFFHAND).typeKey, 406, "A: Schild = 406")
      H.eq(State.Equipped(RANGED).typeKey, 202, "A: Bogen = 202")
      H.eq(State.PendingCount(), 0, "A: nichts ausstehend")
      H.eq(M.CountSent("Get"), 0, "A: unmittelbar nach dem Login wird nichts gesendet")

      -- Die erste Ausruestungslesung (State.Init) plant Status + Listen nach 0,5 s;
      -- der Refresh 2 s nach dem Betreten fragt den Status noch einmal ab, aber
      -- keine zweite Liste (nicht veraltet, juenger als 60 s).
      settle(0.3)
      H.eq(M.CountSent("Get"), 0, "A: nach 0,3 s noch nichts (Entprellung 0,5 s)")
      settle(0.5)
      H.eq(M.CountSent("GetAvailableTransmogs"), 1, "A: nach 0,8 s: Listen angefordert")
      settle(1.5)
      settle(3.0)

      H.truthy(M.CountSent("GetTransmogStatus") <= 2, "A: hoechstens zwei Statusabfragen")
      H.truthy(M.CountSent("GetTransmogStatus") >= 1, "A: Statusabfrage")
      H.eq(M.CountSent("GetAvailableTransmogs"), 1, "A: genau eine Listenabfrage")
      H.eq(Net.state, "OK", "A: Server antwortet")
      H.eq(State.StatusKnown(), true, "A: Status bekannt")
      H.truthy(State.ListsReady(), "A: alle 14 Listen fertig")
      H.eq(evCount("LIST_READY"), 14, "A: LIST_READY je Slot genau einmal")
      H.eq(evCount("SERVER_STATE"), 1, "A: SERVER_STATE einmal (UNKNOWN -> OK)")
      H.eq(evLast("SERVER_STATE")[1], "OK", "A: SERVER_STATE OK")
      noErrors("A")

      for _, slot in ipairs(SERVER_SLOTS) do
         local want, bucket = srv.list(slot)
         local list = State.List(slot)
         H.deepEq(list.ids, want, "A: Liste Slot " .. slot)
         H.eq(list.bucket, bucket, "A: Bucket Slot " .. slot)
         H.eq(list.amount, #want, "A: amount Slot " .. slot)
         H.eq(list.received, #want, "A: received Slot " .. slot)
         H.eq(list.ready, true, "A: ready Slot " .. slot)
         for _, id in ipairs(want) do
            if not list.set[id] then H.fail("A: set fehlt id " .. id) break end
         end
      end
      H.eq(#State.List(HEAD).ids, 25, "A: 25 Plattenkoepfe (zwei Stuecke zu 20 + 5)")
      H.eq(State.List(HEAD).bucket, 8, "A: Platte-Kopf: Bucket 4 + 4")
      H.eq(State.List(MAINHAND).bucket, 9, "A: Schwert: Bucket 2 + 7")

      -- Status: Aussehen, Verborgen, inaktiv
      H.eq(State.Applied(HEAD), candId(HEAD, 3), "A: Kopf angewendet")
      H.eq(State.Baseline(HEAD), candId(HEAD, 3), "A: Kopf Baseline")
      H.eq(State.Wanted(HEAD), candId(HEAD, 3), "A: Kopf Wanted")
      H.eq(State.IsInactive(HEAD), false, "A: Kopf aktiv")
      H.eq(State.Applied(CHEST), HIDDEN, "A: Brust verborgen")
      H.eq(State.Baseline(CHEST), HIDDEN, "A: Brust Baseline HIDDEN")
      H.eq(State.IsInactive(CHEST), false, "A: Verborgen ist nie inaktiv")
      H.eq(State.Applied(LEGS), 2699, "A: Beine Rohwert")
      H.eq(State.IsInactive(LEGS), true, "A: Beine inaktiv (nicht in der Liste)")
      H.eq(State.Baseline(LEGS), 0, "A: Beine Baseline 0")
      H.eq(State.Wanted(LEGS), 0, "A: Beine Wanted 0")
      H.eq(State.HasPending(LEGS), false, "A: inaktiv ist keine Aenderung")
      H.eq(State.Applied(SHOULDER), 0, "A: Schulter ohne Aussehen")
      H.eq(State.PendingCount(), 0, "A: nichts ausstehend")
      H.eq(evCount("EQUIPMENT_CHANGED"), 0, "A: Ausruestung seit dem Start unveraendert")

      -- ----------------------------------------------------------------
      -- B. Gegenstaende laufen ueber die Zeit im Cache ein
      -- ----------------------------------------------------------------
      local entries, stats = Filter.Compute(HEAD)
      H.eq(stats.total, 25, "B: total")
      H.truthy(stats.unresolved > 0, "B: noch nicht alles aufgeloest (" .. stats.unresolved .. ")")
      H.eq(stats.shown + stats.unresolved + stats.hiddenByFilter + stats.hiddenDuplicates, 25,
         "B: Bilanz vor dem Einlaufen")
      H.truthy(Items.PendingCount() > 0, "B: Items hat Abfragen offen")
      clearLog()
      settle(0.15)
      -- gedrosselt: je Takt (0.1 s) hoechstens 25 neue Abfragen
      local queried = 0
      for id, n in pairs(M.itemQueries) do
         if META[id] and META[id].slot == HEAD and id >= 2000 then queried = queried + n end
      end
      H.truthy(queried <= 25, "B: Abfragen gedrosselt (" .. queried .. ")")
      settle(4.0)
      H.eq(Items.PendingCount(), 0, "B: alles aufgeloest")
      H.truthy(evCount("ITEMS_RESOLVED") >= 1, "B: ITEMS_RESOLVED gefeuert")
      local sumResolved = 0
      for _, e in ipairs(evList("ITEMS_RESOLVED")) do sumResolved = sumResolved + e[1] end
      H.truthy(sumResolved >= 22, "B: gebuendelte Zaehler summieren sich (" .. sumResolved .. ")")
      H.truthy(evCount("ITEMS_RESOLVED") <= 12, "B: gebuendelt (" .. evCount("ITEMS_RESOLVED") .. " Ereignisse)")

      entries, stats = Filter.Compute(HEAD)
      H.eq(stats.unresolved, 0, "B: nichts unaufgeloest")
      H.eq(stats.total, 25, "B: total")
      H.eq(stats.hiddenDuplicates, 1, "B: das Duplikatpaar wird zusammengefasst")
      H.eq(stats.shown + stats.hiddenByFilter + stats.hiddenDuplicates, 25, "B: Bilanz")
      H.eq(#entries, stats.shown, "B: Eintraege = shown")
      -- Sortierung: Qualitaet absteigend, dann Name
      local sortedOk = true
      for i = 2, #entries do
         local a, b = entries[i - 1], entries[i]
         if a.quality < b.quality or (a.quality == b.quality and a.nameKey > b.nameKey) then
            sortedOk = false
         end
      end
      H.truthy(sortedOk, "B: Qualitaet absteigend, Name aufsteigend")
      -- Markierungen
      local applied, wanted
      for _, e in ipairs(entries) do
         if e.id == candId(HEAD, 3) then applied, wanted = e.applied, e.wanted end
      end
      H.eq(applied, true, "B: angewendeter Eintrag markiert")
      H.eq(wanted, true, "B: gewuenschter Eintrag markiert")

      -- Filter wirken zusammen mit State
      Filter.SetHideDuplicates(false)
      entries, stats = Filter.Compute(HEAD)
      H.eq(stats.shown, 25, "B: ohne Duplikatfilter alles sichtbar")
      Filter.SetHideDuplicates(true)

      Filter.SetQuality(0, false)
      entries, stats = Filter.Compute(HEAD)
      local anyPoor = false
      for _, e in ipairs(entries) do if e.quality == 0 then anyPoor = true end end
      H.eq(anyPoor, false, "B: schlechte Qualitaet ausgeblendet")
      H.truthy(stats.hiddenByFilter >= 4, "B: ausgeblendet gezaehlt (" .. stats.hiddenByFilter .. ")")
      H.truthy(Filter.IsActive(), "B: Filter aktiv")
      local quals = Filter.Qualities(HEAD)
      H.eq(quals[1].quality, 0, "B: Qualitaeten ungefiltert gezaehlt")
      Filter.Reset()
      H.falsy(Filter.IsActive(), "B: Reset")

      Filter.SetSearch("look 0-1")
      entries, stats = Filter.Compute(HEAD)
      H.truthy(#entries > 0, "B: Suche trifft")
      local searchOk = true
      for _, e in ipairs(entries) do
         if not e.info.name:lower():find("look 0-1", 1, true) then searchOk = false end
      end
      H.truthy(searchOk, "B: nur Namen mit dem Suchtext")
      Filter.SetSearch("#" .. candId(HEAD, 7))
      entries = Filter.Compute(HEAD)
      H.deepEq(idsOf(entries), { candId(HEAD, 7) }, "B: #id findet genau das Item")
      Filter.Reset()

      DB.char.favorites[candId(HEAD, 9)] = true
      Events.Fire("FAVORITES_CHANGED")
      Filter.SetFavoritesOnly(true)
      entries = Filter.Compute(HEAD)
      H.deepEq(idsOf(entries), { candId(HEAD, 9) }, "B: nur Favoriten")
      Filter.SetFavoritesOnly(false)

      -- Weitere Slots: Waffen haben einen eigenen Typ, Listen werden angefordert
      local weapon, wstats = Filter.Compute(MAINHAND)
      H.eq(wstats.total, 24, "B: Waffenliste (2 Stuecke)")
      settle(3.0)
      weapon, wstats = Filter.Compute(MAINHAND)
      H.eq(wstats.unresolved, 0, "B: Waffen aufgeloest")
      local wtypes = Filter.Types(MAINHAND)
      H.eq(#wtypes, 1, "B: ein Waffentyp")
      H.eq(wtypes[1].typeKey, 207, "B: Waffentyp 207")
      H.eq(wtypes[1].own, true, "B: eigener Typ")
      noErrors("B")

      -- ----------------------------------------------------------------
      -- C. Auswahl, Kosten, Anwenden
      -- ----------------------------------------------------------------
      local ok, why = State.CanApply()
      H.eq(ok, false, "C: nichts ausgewaehlt")
      H.eq(why, "APPLY_REASON_NONE", "C: Grund NONE")

      clearLog()
      clearSent()
      H.eq(State.Select(HEAD, candId(HEAD, 10)), true, "C: Auswahl Kopf")
      H.eq(evCount("WANTED_CHANGED"), 1, "C: WANTED_CHANGED")
      H.eq(evLast("WANTED_CHANGED")[1], HEAD, "C: WANTED_CHANGED(slot)")
      H.eq(State.Wanted(HEAD), candId(HEAD, 10), "C: Wanted")
      H.eq(State.HasPending(HEAD), true, "C: Pending")
      H.deepEq(State.PendingSlots(), { HEAD }, "C: PendingSlots")
      H.eq(State.PendingCount(), 1, "C: PendingCount")
      local cost = State.Cost()
      H.eq(cost.valid, false, "C: Kosten noch unbekannt")
      H.eq(cost.pending, true, "C: Kostenabfrage geplant")
      ok, why = State.CanApply()
      H.eq(ok, false, "C: noch nicht beim Transmogrifizierer")
      H.eq(why, "APPLY_REASON_VENDOR", "C: Grund VENDOR")
      H.eq(M.CountSent("CalculateCost"), 0, "C: Kostenabfrage entprellt")

      settle(0.5)
      H.eq(M.CountSent("CalculateCost:" .. HEAD .. ":" .. candId(HEAD, 10)), 1, "C: genau eine Kostenabfrage")
      cost = State.Cost()
      H.eq(cost.valid, true, "C: Kosten gueltig")
      H.eq(cost.pending, false, "C: nicht mehr ausstehend")
      H.eq(cost.copper, PRICE, "C: ein Aussehen = ein Preis")
      H.eq(cost.canPurchase, true, "C: bezahlbar")
      H.truthy(evCount("COST_CHANGED") >= 1, "C: COST_CHANGED")

      -- eine zweite Auswahl kurz NACH der ersten Anfrage: die alte Antwort darf
      -- die neue Auswahl nicht als "gueltig" ausgeben
      H.eq(State.Select(SHOULDER, candId(SHOULDER, 2)), true, "C: Auswahl Schulter")
      cost = State.Cost()
      H.eq(cost.valid, false, "C: Kosten nach neuer Auswahl ungueltig")
      H.eq(cost.pending, true, "C: neue Anfrage geplant")
      settle(0.6)
      cost = State.Cost()
      H.eq(cost.valid, true, "C: Kosten fuer beide gueltig")
      H.eq(cost.copper, 2 * PRICE, "C: zwei Aussehen")

      -- Entfernen vormerken (Brust ist verborgen): 0 kostet nichts
      local requests = M.CountSent("CalculateCost")
      H.eq(State.Select(CHEST, 0), true, "C: Entfernen Brust vormerken")
      H.eq(State.HasPending(CHEST), true, "C: Brust ausstehend")
      settle(0.5)
      H.eq(M.CountSent("CalculateCost"), requests, "C: Entfernen loest keine neue Kostenabfrage aus")
      H.eq(State.Cost().copper, 2 * PRICE, "C: Kosten unveraendert")
      H.deepEq(State.PendingSlots(), { HEAD, SHOULDER, CHEST }, "C: aufsteigende Reihenfolge")

      -- nicht gesammelt/unzulaessig: verweigert
      H.eq(State.Select(WAIST, candId(HEAD, 4)), false, "C: Kopf-Aussehen im Taillen-Slot unzulaessig")
      H.eq(State.Select(MAINHAND, HIDDEN), false, "C: Waffen nie verborgen")
      H.eq(State.PendingCount(), 3, "C: unveraenderte Auswahl")

      -- Transmogrifizierer erreicht
      State.SetVendor(true)
      H.eq(evLast("VENDOR_CHANGED")[1], true, "C: VENDOR_CHANGED(true)")
      ok, why = State.CanApply()
      H.eq(ok, true, "C: Anwenden moeglich " .. tostring(why))

      local moneyBefore = M.world.money
      clearLog()
      clearSent()
      H.eq(State.Apply(), true, "C: Apply gestartet")
      H.eq(State.Busy(), true, "C: beschaeftigt")
      H.eq(evLast("APPLY_STARTED")[1], 3, "C: APPLY_STARTED(3)")
      H.eq(M.CountSent("Apply:"), 1, "C: nur EINE Operation unterwegs")
      H.eq(M.SentCommands()[1], "Apply:" .. HEAD .. ":" .. candId(HEAD, 10), "C: erste Operation = Kopf")
      local okAgain, whyAgain = State.CanApply()
      H.eq(okAgain, false, "C: waehrend des Anwendens gesperrt")
      H.eq(whyAgain, "APPLY_REASON_BUSY", "C: Grund BUSY")
      H.eq(State.Apply(), false, "C: zweiter Apply ignoriert")

      settle(1.5)
      H.eq(State.Busy(), false, "C: fertig")
      local cmds = M.SentCommands()
      H.eq(cmds[1], "Apply:" .. HEAD .. ":" .. candId(HEAD, 10), "C: Reihenfolge 1")
      H.eq(cmds[2], "Apply:" .. SHOULDER .. ":" .. candId(SHOULDER, 2), "C: Reihenfolge 2")
      H.eq(cmds[3], "Remove:" .. CHEST, "C: Reihenfolge 3")
      H.eq(cmds[4], "GetTransmogStatus", "C: danach Resync des Status")
      H.eq(evCount("APPLY_PROGRESS"), 3, "C: drei Fortschrittsmeldungen")
      for i, e in ipairs(evList("APPLY_PROGRESS")) do
         H.eq(e[2], true, "C: Fortschritt " .. i .. " erfolgreich")
      end
      H.eq(evLast("APPLY_DONE")[1], 3, "C: APPLY_DONE nOk")
      H.eq(evLast("APPLY_DONE")[2], 0, "C: APPLY_DONE nFail")
      H.eq(State.Applied(HEAD), candId(HEAD, 10), "C: Kopf angewendet")
      H.eq(State.Applied(SHOULDER), candId(SHOULDER, 2), "C: Schulter angewendet")
      H.eq(State.Applied(CHEST), 0, "C: Brust entfernt")
      H.eq(srv.stored[CHEST], nil, "C: Server hat die Brust entfernt")
      H.eq(State.PendingCount(), 0, "C: Auswahl abgearbeitet")
      H.eq(moneyBefore - M.world.money, 2 * PRICE, "C: zwei Aussehen bezahlt")
      H.eq(State.Cost().copper, 0, "C: keine Kosten ohne Auswahl")
      H.eq(State.Cost().valid, true, "C: ohne Auswahl gueltig")
      H.truthy(H.mock.messages[#H.mock.messages] ~= nil, "C: Chatzeile")
      local sawOk = false
      for _, line in ipairs(M.messages) do
         if line:find(T.L.MSG_APPLY_OK, 1, true) then sawOk = true end
      end
      H.truthy(sawOk, "C: Erfolgsmeldung im Chat")
      noErrors("C")

      -- ----------------------------------------------------------------
      -- D. Fehlschlag: Server lehnt eines von zwei ab
      -- ----------------------------------------------------------------
      srv.reject[candId(BACK, 3)] = true
      H.eq(State.Select(WAIST, candId(WAIST, 1)), true, "D: Taille")
      H.eq(State.Select(BACK, candId(BACK, 3)), true, "D: Ruecken (wird abgelehnt)")
      settle(0.6)
      H.eq(State.Cost().valid, true, "D: Kosten da")
      clearLog()
      clearSent()
      H.eq(State.Apply(), true, "D: Apply")
      settle(1.5)
      H.eq(State.Busy(), false, "D: nicht mehr beschaeftigt (kein ewiges Warten)")
      H.eq(evCount("APPLY_PROGRESS"), 2, "D: zwei Fortschrittsmeldungen")
      local p1, p2 = evList("APPLY_PROGRESS")[1], evList("APPLY_PROGRESS")[2]
      H.eq(p1[1], WAIST, "D: Slot 1")
      H.eq(p1[2], true, "D: Taille ok")
      H.eq(p2[1], BACK, "D: Slot 2")
      H.eq(p2[2], false, "D: Ruecken abgelehnt")
      H.eq(p2[3], candId(BACK, 3), "D: Item-ID im Fehlschlag")
      H.eq(evLast("APPLY_DONE")[1], 1, "D: nOk")
      H.eq(evLast("APPLY_DONE")[2], 1, "D: nFail")
      H.eq(State.Applied(WAIST), candId(WAIST, 1), "D: Taille uebernommen")
      H.eq(State.Applied(BACK), 0, "D: Ruecken nicht angewendet")
      H.eq(State.HasPending(WAIST), false, "D: Taille nicht mehr ausstehend")
      H.eq(State.HasPending(BACK), true, "D: abgelehnte Auswahl bleibt")
      H.eq(State.Wanted(BACK), candId(BACK, 3), "D: Wanted bleibt")
      local sawFail = false
      for _, line in ipairs(M.messages) do
         if line:find("could not be applied", 1, true) then sawFail = true end
      end
      H.truthy(sawFail, "D: Fehlermeldung im Chat")
      H.eq(State.Discard(BACK), true, "D: Auswahl verwerfen")
      H.eq(State.PendingCount(), 0, "D: aufgeraeumt")
      noErrors("D")

      -- ----------------------------------------------------------------
      -- E. Verborgen
      -- ----------------------------------------------------------------
      local costRequests = M.CountSent("CalculateCost")
      clearSent()
      moneyBefore = M.world.money
      H.eq(State.Select(HEAD, HIDDEN), true, "E: Kopf verbergen")
      settle(0.6)
      cost = State.Cost()
      H.eq(cost.valid, true, "E: Verborgen: gueltig")
      H.eq(cost.copper, 0, "E: Verborgen ist kostenlos")
      H.eq(M.CountSent("CalculateCost"), 0, "E: Verborgen braucht keine Kostenabfrage")
      H.eq(State.Apply(), true, "E: Apply")
      settle(1.0)
      H.eq(State.Applied(HEAD), HIDDEN, "E: Kopf verborgen")
      H.eq(State.Baseline(HEAD), HIDDEN, "E: Baseline HIDDEN")
      H.eq(moneyBefore - M.world.money, 0, "E: nichts bezahlt")
      H.eq(srv.stored[HEAD], HIDDEN, "E: Server speichert 999999")
      -- Rechtsklick-Logik: angewendetes Aussehen -> Entfernen vormerken -> verwerfen
      H.eq(State.Toggle(HEAD), true, "E: Toggle merkt Entfernen vor")
      H.eq(State.Wanted(HEAD), 0, "E: Wanted 0")
      H.eq(State.Toggle(HEAD), true, "E: Toggle verwirft")
      H.eq(State.Wanted(HEAD), HIDDEN, "E: Wanted wieder HIDDEN")
      noErrors("E")

      -- ----------------------------------------------------------------
      -- F. Outfits
      -- ----------------------------------------------------------------
      -- Auswahl vor dem Speichern: Kopf = HIDDEN (angewendet), Schulter = 2203 (neu)
      H.eq(State.Select(SHOULDER, candId(SHOULDER, 3)), true, "F: Schulter waehlen")
      local look = Outfits.CurrentLook()
      H.eq(look[HEAD], HIDDEN, "F: Look Kopf verborgen")
      H.eq(look[SHOULDER], candId(SHOULDER, 3), "F: Look Auswahl")
      H.eq(look[WAIST], candId(WAIST, 1), "F: Look angewendet")
      H.eq(look[MAINHAND], candId(MAINHAND, 15), "F: Look Waffe")
      H.eq(look[CHEST], nil, "F: entfernt = nicht im Look")
      H.eq(look[LEGS], nil, "F: inaktiv = nicht im Look")

      clearLog()
      H.eq(Outfits.Save("Raid Set"), true, "F: speichern")
      H.eq(evCount("OUTFITS_CHANGED"), 1, "F: OUTFITS_CHANGED")
      local okSave, errKey = Outfits.Save("raid set")
      H.eq(okSave, false, "F: gleicher Name (Gross/Klein egal) wird nicht ueberschrieben")
      H.eq(errKey, "OUTFIT_ERR_EXISTS", "F: Fehlerschluessel")
      local okName, errName = Outfits.ValidateName("   ")
      H.eq(okName, false, "F: leerer Name")
      H.eq(errName, "OUTFIT_ERR_EMPTY", "F: OUTFIT_ERR_EMPTY")
      okName, errName = Outfits.ValidateName(string.rep("x", 33))
      H.eq(errName, "OUTFIT_ERR_LONG", "F: OUTFIT_ERR_LONG")
      H.eq(#Outfits.List(), 1, "F: ein Outfit")
      H.eq(Outfits.List()[1].count, 4, "F: 4 Teile (Kopf, Schulter, Taille, Haupthand)")

      -- Auswahl aendern, dann Outfit laden: ein einziges WANTED_CHANGED(nil)
      State.DiscardAll()
      H.eq(State.Select(SHOULDER, candId(SHOULDER, 5)), true, "F: andere Schulter")
      H.eq(State.Select(HEAD, candId(HEAD, 12)), true, "F: anderer Kopf")
      clearLog()
      local app, skipped = Outfits.Load("Raid Set")
      H.eq(#skipped, 0, "F: nichts uebersprungen")
      H.truthy(contains(app, SHOULDER), "F: Schulter geladen")
      H.eq(evCount("WANTED_CHANGED"), 1, "F: ein einziges WANTED_CHANGED")
      H.eq(evLast("WANTED_CHANGED")[1], nil, "F: WANTED_CHANGED(nil)")
      H.eq(State.Wanted(SHOULDER), candId(SHOULDER, 3), "F: Schulter aus dem Outfit")
      H.eq(State.Wanted(HEAD), HIDDEN, "F: Kopf aus dem Outfit (= angewendet, keine Auswahl)")
      H.eq(State.HasPending(HEAD), false, "F: Kopf ohne Aenderung")
      H.eq(State.HasPending(SHOULDER), true, "F: Schulter ausstehend")

      -- Ein Outfit mit Teilen, die nicht passen
      H.eq(Outfits.Save("Mischung", {
         [HEAD] = candId(HEAD, 20),            -- passt
         [SHOULDER] = candId(HEAD, 21),        -- Kopf-Aussehen auf der Schulter
         [SHIRT] = candId(SHIRT, 1),           -- passt
         [LEGS] = HIDDEN,                      -- Beine duerfen verborgen werden
         [MAINHAND] = HIDDEN,                  -- Waffe: wird beim Speichern verworfen
         [1] = 5555,                           -- kein transmogbarer Slot
      }), true, "F: Mischung speichern")
      H.eq(Outfits.Get("Mischung").count, 4, "F: unzulaessige Teile gar nicht erst gespeichert")
      State.DiscardAll()
      app, skipped = Outfits.Load("mischung")
      H.deepEq(app, { HEAD, SHIRT, LEGS }, "F: uebernommen")
      H.eq(#skipped, 1, "F: ein Teil uebersprungen")
      H.eq(skipped[1].slot, SHOULDER, "F: Schulter uebersprungen")
      H.eq(skipped[1].reasonKey, "OUTFIT_SKIP_UNAVAILABLE", "F: Grund")
      H.eq(State.Wanted(HEAD), candId(HEAD, 20), "F: Kopf geladen")
      H.eq(State.Wanted(LEGS), HIDDEN, "F: Beine verborgen vorgemerkt")
      H.eq(State.Wanted(SHOULDER), candId(SHOULDER, 2), "F: Schulter unveraendert angewendet")
      local app2, sk2, errLoad = Outfits.Load("gibt es nicht")
      H.eq(#app2, 0, "F: unbekanntes Outfit")
      H.eq(errLoad, "OUTFIT_ERR_MISSING", "F: Fehler MISSING")

      -- Umbenennen / Ueberschreiben / Loeschen
      H.eq(Outfits.Rename("mischung", "Spass"), true, "F: umbenennen")
      H.eq(Outfits.Exists("Mischung"), false, "F: alter Name weg")
      H.eq(Outfits.Exists("SPASS"), true, "F: neuer Name (Gross/Klein egal)")
      local okRen, errRen = Outfits.Rename("Spass", "Raid Set")
      H.eq(okRen, false, "F: Umbenennen auf vorhandenen Namen")
      H.eq(errRen, "OUTFIT_ERR_EXISTS", "F: Fehler EXISTS")
      H.eq(Outfits.Overwrite("Spass", { [HEAD] = candId(HEAD, 22) }), true, "F: ueberschreiben")
      H.eq(Outfits.Get("Spass").count, 1, "F: ein Teil")
      H.eq(Outfits.Delete("Spass"), true, "F: loeschen")
      H.eq(#Outfits.List(), 1, "F: ein Outfit uebrig")
      noErrors("F")

      -- ----------------------------------------------------------------
      -- G. Ausruestungswechsel mitten in der Sitzung
      -- ----------------------------------------------------------------
      State.DiscardAll()
      H.eq(State.Select(HEAD, candId(HEAD, 13)), true, "G: Auswahl Kopf vor dem Wechsel")
      clearLog()
      clearSent()
      M.world.equipment[SHOULDER + 1] = 1102        -- Schulter: Kette statt Platte
      M.world.equipment[HEAD + 1] = 1100            -- Kopf: Kette statt Platte
      M.Fire("PLAYER_EQUIPMENT_CHANGED", SHOULDER + 1, false)
      M.Fire("PLAYER_EQUIPMENT_CHANGED", HEAD + 1, false)
      H.eq(State.Equipped(HEAD).id, 1100, "G: neuer Kopf")
      H.eq(State.Equipped(SHOULDER).id, 1102, "G: neue Schulter")
      H.eq(State.Equipped(HEAD).typeKey, 403, "G: Kette = 403")
      H.eq(evCount("EQUIPMENT_CHANGED"), 2, "G: EQUIPMENT_CHANGED je Slot")
      H.eq(State.HasPending(HEAD), false, "G: Auswahl des Kopfs verworfen")
      H.eq(State.Wanted(HEAD), State.Baseline(HEAD), "G: Wanted = Baseline")
      H.eq(State.List(HEAD).ready, false, "G: Liste ist veraltet")
      H.eq(State.List(SHOULDER).ready, false, "G: Liste ist veraltet (Schulter)")
      H.eq(State.IsInactive(HEAD), false, "G: ohne fertige Liste nie inaktiv")
      -- optimistische Auswahl bei veralteter Liste
      H.eq(State.Select(SHOULDER, candId(SHOULDER, 1)), true, "G: optimistisch akzeptiert")
      settle(1.0)
      H.eq(M.CountSent("GetAvailableTransmogs"), 1, "G: Listen genau einmal neu angefordert (0,5 s entprellt)")
      H.truthy(M.CountSent("GetTransmogStatus") >= 1, "G: Status neu angefordert")
      H.truthy(State.List(HEAD).ready, "G: neue Liste Kopf")
      H.eq(State.List(HEAD).bucket, 7, "G: Kette-Kopf: Bucket 4 + 3")
      H.eq(State.List(HEAD).amount, 6, "G: nur Kettenaussehen")
      H.eq(State.List(SHOULDER).amount, 0, "G: Schulter: keine Kettenaussehen in der Datenbank")
      H.eq(State.HasPending(SHOULDER), false, "G: nicht mehr verfuegbare Auswahl bei Listenende verworfen")
      H.eq(State.Applied(SHOULDER), candId(SHOULDER, 2), "G: gespeichertes Aussehen bleibt Rohwert")
      H.eq(State.IsInactive(SHOULDER), true, "G: Schulter inaktiv")
      H.eq(State.Baseline(SHOULDER), 0, "G: Baseline 0")
      H.eq(State.IsAvailable(HEAD, candId(HEAD, 26)), true, "G: Kettenaussehen verfuegbar")
      H.eq(State.IsAvailable(HEAD, candId(HEAD, 13)), false, "G: Plattenaussehen nicht mehr")
      H.eq(State.IsAvailable(HEAD, HIDDEN), true, "G: Verborgen immer (hideable)")
      H.eq(State.IsAvailable(MAINHAND, HIDDEN), false, "G: Verborgen nicht auf der Waffe")
      -- Filter folgt der neuen Liste
      local hEntries, hStats = Filter.Compute(HEAD)
      H.eq(hStats.total, 6, "G: Filter: neue Liste")
      settle(2.0)
      hEntries, hStats = Filter.Compute(HEAD)
      H.eq(hStats.unresolved, 0, "G: Filter: aufgeloest")
      local mailOnly = true
      for _, e in ipairs(hEntries) do
         if e.info.typeKey ~= 403 then mailOnly = false end
      end
      H.truthy(mailOnly, "G: nur Kettenaussehen")

      -- Hemd ausziehen, Reliktschlag im Fernkampf
      M.world.equipment[SHIRT + 1] = nil
      M.Fire("PLAYER_EQUIPMENT_CHANGED", SHIRT + 1, true)
      H.eq(State.SlotState(SHIRT), "EMPTY", "G: Hemd leer")
      H.eq(State.Equipped(SHIRT), nil, "G: kein Gegenstand")
      H.eq(State.Select(SHIRT, candId(SHIRT, 1)), false, "G: leerer Slot nicht waehlbar")
      M.world.equipment[RANGED + 1] = 1117
      M.Fire("PLAYER_EQUIPMENT_CHANGED", RANGED + 1, false)
      H.eq(State.SlotState(RANGED), "NEVER", "G: Relikt im Fernkampfslot")
      H.eq(State.Select(RANGED, 0), false, "G: NEVER nicht waehlbar")
      settle(1.0)
      H.eq(State.List(SHIRT).amount, 0, "G: leerer Slot: leere Liste")
      noErrors("G")

      -- ----------------------------------------------------------------
      -- H. Sprachwechsel
      -- ----------------------------------------------------------------
      Locale.Add("deDE", { SORT_QUALITY = "Qualitaet (Test)", THOUSANDS_SEP = "." })
      clearLog()
      DB.Set("locale", "deDE")
      H.eq(evLast("SETTINGS_CHANGED")[1], "locale", "H: SETTINGS_CHANGED(locale)")
      H.eq(Locale.Set("deDE"), "deDE", "H: Locale.Set liefert den Code")
      H.eq(evCount("LOCALE_CHANGED"), 1, "H: LOCALE_CHANGED")
      H.eq(Locale.Current(), "deDE", "H: aktuelle Sprache")
      H.eq(T.L.SORT_QUALITY, "Qualitaet (Test)", "H: Text der neuen Sprache")
      H.eq(Filter.SortLabel("QUALITY"), "Qualitaet (Test)", "H: Filter nutzt die neue Sprache")
      H.eq(T.L.APPLY_REASON_VENDOR ~= "APPLY_REASON_VENDOR", true, "H: fehlende Schluessel fallen auf enUS zurueck")
      H.eq(Util.FormatNumber(1234567), "1.234.567", "H: Tausendertrenner folgt der Sprache")
      H.eq(DB.global.locale, "deDE", "H: gespeichert")
      -- Slotnamen folgen dem Client (Blizzard-Globals), nicht der Addon-Sprache
      H.eq(T.Slots.Label(HEAD), "Head", "H: Slotname aus Blizzard-Global")
      noErrors("H")
      H.deepEq(strayGlobals(), {}, "H: keine fremden Globals in der ersten Sitzung")
      H.deepEq(M.StrayFrameNames(), {}, "H: keine fremden benannten Frames in der ersten Sitzung")

      -- ----------------------------------------------------------------
      -- I. Neuanmeldung mit den gespeicherten Variablen
      -- ----------------------------------------------------------------
      DB.SetChar("lastSlot", SHOULDER)
      Filter.SetSort("NAME")
      Filter.SetType(401, false)
      local before = {
         outfits = Util.CopyTable(DB.char.outfits),
         favorites = Util.CopyTable(DB.char.favorites),
         filter = Util.CopyTable(DB.char.filter),
         global = Util.CopyTable(DB.global),
      }
      local savedVars = M.SavedVariables()
      H.truthy(savedVars.TransmogDB, "I: TransmogDB wird gespeichert")
      H.truthy(savedVars.TransmogGlobalDB, "I: TransmogGlobalDB wird gespeichert")
      local storedAtServer = srv.stored
      local equipmentNow = {}
      for k, v in pairs(M.world.equipment) do equipmentNow[k] = v end

      local oldSrv = srv
      startSession({ saved = savedVars, equipment = equipmentNow, stored = storedAtServer })
      -- (derselbe Server-Zustand: der Nachbau fuer die neue Sitzung bekommt ihn mit)
      H.deepEq(DB.char.outfits, before.outfits, "I: Outfits ueberleben")
      H.deepEq(DB.char.favorites, before.favorites, "I: Favoriten ueberleben")
      H.deepEq(DB.char.filter, before.filter, "I: Filtereinstellungen ueberleben")
      H.eq(DB.global.locale, "deDE", "I: Sprache ueberlebt")
      H.eq(DB.char.lastSlot, SHOULDER, "I: lastSlot ueberlebt")
      H.eq(DB.char.migrated, 2, "I: Migration nicht erneut")
      H.eq(Locale.Current(), "deDE", "I: Sprache wird bei der Anmeldung gesetzt")
      H.eq(#Outfits.List(), 1, "I: ein Outfit nach dem Neustart")
      H.eq(Outfits.Exists("raid set"), true, "I: Outfit gefunden")
      H.eq(Filter.state.sort, "NAME", "I: Sortierung")
      H.eq(Filter.state.typesOff[401], true, "I: ausgeblendeter Typ")
      H.eq(State.Equipped(HEAD).id, 1100, "I: neue Ausruestung eingelesen")
      -- der Server kennt das Gesammelte weiter: Status und Listen kommen wieder
      settle(6.0)
      H.truthy(State.ListsReady(), "I: Listen nach der Neuanmeldung")
      H.eq(State.Applied(WAIST), candId(WAIST, 1), "I: Status nach der Neuanmeldung")
      H.eq(State.Applied(HEAD), HIDDEN, "I: Kopf weiter verborgen")
      local app3 = Outfits.Load("Raid Set")
      H.truthy(#app3 >= 1, "I: Outfit laesst sich laden")
      noErrors("I")
      oldSrv = nil

      -- ----------------------------------------------------------------
      -- J. Sauberkeit
      -- ----------------------------------------------------------------
      State.DiscardAll()
      settle(30.0)
      H.deepEq(strayGlobals(), {}, "J: keine fremden Globals")
      H.deepEq(M.StrayFrameNames(), {}, "J: keine fremden benannten Frames")
      H.deepEq(M.StrayGlobals(), {}, "J: Mock: keine fremden Globals")
      H.deepEq(M.ImplicitGlobalReads(), {}, "J: keine this/arg1/event-Zugriffe")
      H.eq(#M.UpdateFrames(), 0, "J: kein OnUpdate im Leerlauf")
      H.eq(Util.TimerCount(), 0, "J: keine liegengebliebenen Timer")
      H.eq(Items.PendingCount(), 0, "J: keine offenen Item-Abfragen")
      local missingKeys = {}
      for k in pairs(T.L.__missing) do missingKeys[#missingKeys + 1] = k end
      table.sort(missingKeys)
      H.deepEq(missingKeys, {}, "J: kein zur Laufzeit gesuchter Locale-Schluessel fehlt")
      noErrors("J")
   end)

   -- ======================================================================
   -- 2. Server fehlt (Modul nicht installiert) und erholt sich
   -- ======================================================================

   H.test("Server stumm: ABSENT nach 8 s, Anwenden gesperrt, spaeter erholt", function()
      startSession({ mute = true })
      settle(2.5)                       -- Refresh (Debounce 2 s) laeuft: Befehle gehen raus
      H.eq(Net.state, "UNKNOWN", "Zustand UNKNOWN innerhalb der Frist")
      H.truthy(M.CountSent("GetTransmogStatus") >= 1, "Status angefragt")
      settle(8.5)
      H.eq(Net.state, "ABSENT", "ABSENT nach 8 s")
      H.eq(evLast("SERVER_STATE")[1], "ABSENT", "SERVER_STATE(ABSENT)")
      H.eq(State.ListsReady(), false, "keine Listen")
      -- optimistische Auswahl ist moeglich, Anwenden aber gesperrt
      H.eq(State.Select(HEAD, candId(HEAD, 4)), true, "Auswahl ohne fertige Liste")
      State.SetVendor(true)
      local ok, why = State.CanApply()
      H.eq(ok, false, "Anwenden gesperrt")
      H.eq(why, "APPLY_REASON_SERVER", "Grund SERVER")
      H.eq(State.Apply(), false, "Apply abgelehnt")
      local said = false
      for _, line in ipairs(M.messages) do
         if line:find(T.L.MSG_SERVER_ABSENT, 1, true) then said = true end
      end
      H.truthy(said, "Meldung im Chat")
      H.eq(M.CountSent("Apply:"), 0, "nichts gesendet")

      -- das Modul antwortet doch: ein neuer Refresh holt alles nach
      srv.mute = false
      clearSent()
      State.Refresh(true)
      settle(3.0)
      H.eq(Net.state, "OK", "wieder OK")
      H.eq(evLast("SERVER_STATE")[1], "OK", "SERVER_STATE(OK)")
      H.truthy(State.ListsReady(), "Listen da")
      H.eq(State.Wanted(HEAD), candId(HEAD, 4), "Auswahl ueberlebt (steht in der Liste)")
      ok = State.CanApply()
      -- Kosten werden nachgeholt
      settle(1.0)
      ok, why = State.CanApply()
      H.eq(ok, true, "Anwenden wieder moeglich " .. tostring(why))
      noErrors("ABSENT")
   end)

   -- ======================================================================
   -- 3. Verlorene Antwort (Zeitueberschreitung)
   -- ======================================================================

   H.test("Anwenden: verlorene Antwort laeuft nach 5 s ab, der Stapel geht weiter, der Resync heilt", function()
      startSession()
      settle(5.0)
      H.truthy(State.ListsReady(), "Listen da")
      State.SetVendor(true)
      H.eq(State.Select(HEAD, candId(HEAD, 5)), true, "Kopf")
      H.eq(State.Select(SHOULDER, candId(SHOULDER, 4)), true, "Schulter")
      settle(0.8)
      H.eq(State.Cost().valid, true, "Kosten")
      srv.drop.Apply = 1                 -- die erste Antwort geht verloren (Server wendet trotzdem an)
      clearLog()
      clearSent()
      H.eq(State.Apply(), true, "Apply")
      settle(4.0)
      H.eq(State.Busy(), true, "nach 4 s wartet die erste Operation noch")
      H.eq(M.CountSent("Apply:"), 1, "zweite Operation noch nicht gesendet")
      settle(1.5)                        -- 5 s Frist
      H.eq(M.CountSent("Apply:"), 2, "nach der Frist geht die zweite Operation raus")
      settle(1.5)
      H.eq(State.Busy(), false, "fertig")
      H.eq(evLast("APPLY_DONE")[1], 1, "eine gelungen")
      H.eq(evLast("APPLY_DONE")[2], 1, "eine als verloren gezaehlt")
      local first = evList("APPLY_PROGRESS")[1]
      H.eq(first[1], HEAD, "Kopf lief ab")
      H.eq(first[2], false, "Kopf als Fehlschlag")
      -- Resync: der Server hat den Kopf doch angewendet
      H.eq(State.Applied(HEAD), candId(HEAD, 5), "Status heilt den Kopf")
      H.eq(State.HasPending(HEAD), false, "Auswahl durch den Status aufgeloest")
      H.eq(State.Applied(SHOULDER), candId(SHOULDER, 4), "Schulter")
      noErrors("Timeout")
   end)

   -- ======================================================================
   -- 4. Niedrigere Ruestungsstufen erlaubt: ein Strom, mehrere Typen
   -- ======================================================================

   H.test("AllowLowerTiers: Typen, Zaehler, Filter, own-Typ nie ausblendbar", function()
      startSession({ enterWorld = false })
      srv.lowerTiers = true
      State.Refresh(true)
      settle(1.0)
      Filter.Compute(HEAD)
      settle(4.0)
      local entries, stats = Filter.Compute(HEAD)
      H.eq(stats.total, 41, "alle Stufen in EINER Liste")
      H.eq(stats.unresolved, 0, "aufgeloest")
      local types = Filter.Types(HEAD)
      local keys, counts = {}, {}
      for i, t in ipairs(types) do keys[i], counts[i] = t.typeKey, t.count end
      H.deepEq(keys, { 404, 403, 402, 401 }, "Reihenfolge Platte -> Stoff")
      H.deepEq(counts, { 25, 6, 5, 5 }, "Zaehler")
      H.eq(types[1].own, true, "Platte ist der eigene Typ")
      H.eq(types[2].own, false, "Kette nicht")
      Filter.SetType(403, false)
      entries = Filter.Compute(HEAD)
      for _, e in ipairs(entries) do
         if e.info.typeKey == 403 then H.fail("Kette trotz Filter sichtbar: " .. e.id) break end
      end
      Filter.SetType(404, false)         -- eigener Typ: bleibt sichtbar
      entries, stats = Filter.Compute(HEAD)
      local plate = 0
      for _, e in ipairs(entries) do
         if e.info.typeKey == 404 then plate = plate + 1 end
      end
      H.truthy(plate > 0, "eigener Typ bleibt trotz Filter sichtbar")
      Filter.Reset()
      entries = Filter.Compute(HEAD)
      H.eq(#entries, 40, "nach Reset (ein Duplikat zusammengefasst)")
      -- Auswahl eines Kettenaussehens auf Plattenkopf ist erlaubt
      H.eq(State.Select(HEAD, candId(HEAD, 27)), true, "Kettenaussehen waehlbar")
      noErrors("lowerTiers")
   end)

   -- ======================================================================
   -- 5. Login-Sweep, neue Aussehen, Sammlungsabfragen
   -- ======================================================================

   H.test("Login-Sweep: CollectionUpdated zaehlt nicht als neu; spaeter schon; Abfragen gecacht", function()
      startSession({ enterWorld = false })
      -- Vor PLAYER_ENTERING_WORLD (Server schickt den Sweep direkt nach dem Login)
      for i = 1, 30 do M.ServerMessage("CollectionUpdated:" .. candId(HEAD, i)) end
      H.eq(evCount("COLLECTION_UPDATED"), 30, "Ereignis je Meldung")
      H.eq(next(State.new), nil, "vor dem Betreten: nichts ist neu")

      M.Fire("PLAYER_ENTERING_WORLD")
      T.enteredWorldAt = GetTime()
      settle(5.0)
      M.ServerMessage("CollectionUpdated:" .. candId(SHOULDER, 1))
      H.eq(State.new[candId(SHOULDER, 1)], nil, "innerhalb von 10 s nach dem Betreten: Sweep")
      settle(6.0)
      M.ServerMessage("CollectionUpdated:" .. candId(SHOULDER, 2))
      H.eq(State.new[candId(SHOULDER, 2)], true, "nach 10 s: neu")
      H.eq(Net.CollectionState(candId(SHOULDER, 2)), 1, "als gesammelt gemerkt")

      -- Abfrage: einmal je Item und Sitzung
      clearSent()
      H.eq(Net.QueryCollection(candId(WAIST, 7)), nil, "Abfrage gesendet")
      H.eq(Net.QueryCollection(candId(WAIST, 7)), nil, "zweite Abfrage (laeuft noch) sendet nicht")
      H.eq(M.CountSent("GetCollectionStatus:" .. candId(WAIST, 7)), 1, "genau eine Abfrage")
      settle(0.5)
      H.eq(Net.CollectionState(candId(WAIST, 7)), 1, "Antwort gecacht (Server hat es gesammelt)")
      H.eq(evLast("COLLECTION_STATUS")[1], candId(WAIST, 7), "COLLECTION_STATUS(id, state)")
      H.eq(evLast("COLLECTION_STATUS")[2], 1, "Zustand 1")
      H.eq(Net.QueryCollection(candId(WAIST, 7)), 1, "danach aus dem Cache")
      H.eq(M.CountSent("GetCollectionStatus:" .. candId(WAIST, 7)), 1, "keine neue Abfrage")

      -- neue Aussehen im Filter
      Filter.Compute(SHOULDER)
      settle(3.0)
      Filter.SetNewOnly(true)
      local entries = Filter.Compute(SHOULDER)
      H.deepEq(idsOf(entries), { candId(SHOULDER, 2) }, "Filter 'neu' findet genau das neue Aussehen")
      Filter.SetNewOnly(false)
      noErrors("Sweep")
   end)

   -- ======================================================================
   -- 5b. Neue Aussehen: Listen werden nur bei Bedarf neu angefordert
   -- ======================================================================

   H.test("Sammlung: CollectionUpdated macht Listen veraltet; Refresh fordert sie genau einmal neu an", function()
      startSession()
      settle(5.0)
      H.truthy(State.ListsReady(), "Listen da")
      local before = #State.List(SHOULDER).ids
      -- ein neues Aussehen wird gesammelt (der Server kennt es ab jetzt)
      local newId = candId(SHOULDER, 9)
      META[newId] = { slot = SHOULDER, class = "Armor", sub = "Plate", loc = "INVTYPE_SHOULDER",
         quality = 3, name = "Look 2-09" }
      M.items[newId] = { name = "Look 2-09", quality = 3, ilvl = 120, minLevel = 0, class = "Armor",
         subclass = "Plate", equipLoc = "INVTYPE_SHOULDER", icon = "Interface\\Icons\\INV_Test_" .. newId }
      CANDIDATES[SHOULDER][#CANDIDATES[SHOULDER] + 1] = newId
      srv.collected[newId] = true

      clearSent()
      M.ServerMessage("CollectionUpdated:" .. newId)
      settle(6.0)
      H.eq(M.CountSent("GetAvailableTransmogs"), 0, "ohne offenes Fenster keine Listenabfrage")
      H.eq(#State.List(SHOULDER).ids, before, "Liste noch alt")

      State.Refresh()                         -- das Fenster oeffnet sich
      settle(2.0)
      H.eq(M.CountSent("GetAvailableTransmogs"), 1, "Refresh fordert die veralteten Listen an")
      H.eq(#State.List(SHOULDER).ids, before + 1, "neues Aussehen in der Liste")
      H.truthy(State.IsAvailable(SHOULDER, newId), "neues Aussehen waehlbar")
      H.eq(State.Select(SHOULDER, newId), true, "und auswaehlbar")
      State.Refresh()                         -- noch einmal: nichts mehr veraltet
      settle(1.0)
      H.eq(M.CountSent("GetAvailableTransmogs"), 1, "zweiter Refresh ohne Grund fragt nicht erneut")
      noErrors("Sammlung")
   end)

   H.test("Sammlung: bei sichtbarem Fenster werden die Listen nach 3 s Ruhe automatisch erneuert", function()
      startSession()
      settle(5.0)
      local oldWindow = T.UI.Window
      T.UI.Window = { IsShown = function() return true end }
      clearSent()
      M.ServerMessage("CollectionUpdated:" .. candId(HEAD, 4))
      M.ServerMessage("CollectionUpdated:" .. candId(HEAD, 5))   -- Salve: Frist beginnt neu
      settle(2.0)
      H.eq(M.CountSent("GetAvailableTransmogs"), 0, "innerhalb der Ruhezeit keine Abfrage")
      settle(3.0)
      H.eq(M.CountSent("GetAvailableTransmogs"), 1, "danach genau eine Abfrage")
      T.UI.Window = oldWindow
      noErrors("Sammlung 2")
   end)

   -- ======================================================================
   -- 6. Migration der Altdaten und Neuanmeldung (Altvariablen bleiben)
   -- ======================================================================

   H.test("Migration: Altdaten einmal uebernommen, auch nach Neuanmeldung nicht doppelt", function()
      local legacyOutfits = {
         ["Alt Set"] = { [1] = candId(HEAD, 1), [5] = candId(CHEST, 2), [16] = candId(MAINHAND, 3), [0] = 0 },
         ["Nur Kopf"] = { [1] = HIDDEN },
      }
      local legacySettings = { hideDuplicates = false, armorTypes = { [7] = true } }
      startSession({ saved = { transmogOutfits = legacyOutfits, transmogSettings = legacySettings },
                     enterWorld = false })
      H.eq(DB.char.migrated, 2, "migriert")
      local list = Outfits.List()
      H.eq(#list, 2, "zwei Outfits uebernommen")
      local alt = Outfits.Get("Alt Set")
      H.truthy(alt, "Alt Set")
      H.eq(alt.slots[HEAD], candId(HEAD, 1), "Kopf (Slot 1 -> 0)")
      H.eq(alt.slots[CHEST], candId(CHEST, 2), "Brust (Slot 5 -> 4)")
      H.eq(alt.slots[MAINHAND], candId(MAINHAND, 3), "Haupthand (Slot 16 -> 15)")
      H.eq(alt.count, 3, "0-Eintraege ignoriert")
      H.eq(Outfits.Get("Nur Kopf").slots[HEAD], HIDDEN, "Verborgen bleibt")
      H.eq(DB.char.filter.hideDuplicates, false, "hideDuplicates uebernommen")
      H.eq(DB.char.filter.typesOff[401], true, "Stoff aus")
      H.eq(DB.char.filter.typesOff[402], true, "Leder aus")
      H.eq(DB.char.filter.typesOff[403], nil, "Kette an")
      H.eq(DB.char.filter.typesOff[404], true, "Platte aus")
      H.eq(M.world.equipment ~= nil, true, "Welt vorhanden")

      -- Neuanmeldung mit denselben Variablen (Altvariablen bleiben bestehen)
      local saved = M.SavedVariables()
      H.truthy(saved.transmogOutfits, "Altvariable bleibt gespeichert")
      startSession({ saved = saved, enterWorld = false })
      H.eq(#Outfits.List(), 2, "nicht doppelt")
      H.eq(DB.char.migrated, 2, "weiter migriert")
      noErrors("Migration")
   end)

   -- ======================================================================
   -- 7. Gossip-Ablauf auf Kernebene: "Open" setzt serverOpenAt
   -- ======================================================================

   H.test("Open-Nachricht: SERVER_OPEN, serverOpenAt, Net ist OK", function()
      startSession()
      settle(3.0)
      clearLog()
      State.serverOpenAt = nil
      M.ServerMessage("Open")
      H.eq(evCount("SERVER_OPEN"), 1, "SERVER_OPEN")
      H.near(State.serverOpenAt, GetTime(), 0.001, "serverOpenAt = jetzt")
      H.eq(Net.state, "OK", "OK")
      noErrors("Open")
   end)

   -- ======================================================================
   -- 8. Robustheit: Muell vom Server und alles auf einmal
   -- ======================================================================

   H.test("Fremdinput: kaputte und fremde Nachrichten stoeren nichts", function()
      startSession()
      settle(3.0)
      local before = {}
      for _, slot in ipairs(SERVER_SLOTS) do
         before[slot] = { State.Applied(slot), #State.List(slot).ids, State.Wanted(slot) }
      end
      local junk = {
         "", ":", "::", "TransmogStatus", "TransmogStatus:x", "TransmogStatus:2:abc",
         "TransmogStatus:1:99,5", "AvailableTransmogs", "AvailableTransmogs:0",
         "AvailableTransmogs:0:0:0", "AvailableTransmogs:xx:1:1:start", "AvailableTransmogs:0:0:0:",
         "AvailableTransmogs:0:0:2:1:2:end", "ApplyTransmogResult", "ApplyTransmogResult:7",
         "ApplyTransmogResult:1:zz", "TransmogCost", "TransmogCost:abc:1", "TransmogCost:5",
         "CollectionUpdated", "CollectionUpdated:", "CollectionUpdated:-4", "CollectionStatus:1",
         "CollectionStatus:5:9", "NewTransmog:123", "Open:extra", "completely unknown",
         string.rep("A", 300), "TransmogStatus:0:", "\0\1\2",
      }
      for _, m in ipairs(junk) do M.ServerMessage(m) end
      M.Fire("CHAT_MSG_ADDON", "other-addon", "TransmogStatus:0", "WHISPER", "x")
      M.Fire("CHAT_MSG_ADDON", nil, nil, nil, nil)
      M.Fire("CHAT_MSG_ADDON", "transmog", nil, "WHISPER", "x")
      noErrors("Muell")
      -- vollstaendig unveraendert (gueltige Teile wie TransmogStatus:0 duerfen den Status leeren)
      for _, slot in ipairs(SERVER_SLOTS) do
         H.eq(#State.List(slot).ids, before[slot][2], "Listenlaenge Slot " .. slot)
      end
   end)

   -- ======================================================================
   -- 9b. Oeffentliche Oberflaeche laut SPEC 5.x (Namen, Arten, Rueckgabeformen)
   -- ======================================================================

   H.test("SPEC 5: alle oeffentlichen Namen und Rueckgabeformen der Kernmodule", function()
      startSession({ stored = { [HEAD] = candId(HEAD, 3) } })
      settle(5.0)
      Filter.Compute(HEAD)
      settle(3.0)

      -- Funktionen je Modul (SPEC 5.2 .. 5.10)
      local FUNCS = {
         Util = { "Print", "Error", "Debug", "G", "Split", "Trim", "Lower", "Clamp", "Round",
                  "ItemIdFromLink", "FormatNumber", "FormatMoney", "After", "Cancel", "Debounce",
                  "CopyTable", "Count", "Hex", "QualityColor" },
         Events = { "On", "Off", "Fire", "Game", "UnGame" },
         DB = { "Init", "Set", "SetChar" },
         Slots = { "Label", "EmptyTexture", "EquippedLink", "IsHideable", "Next", "Init" },
         Items = { "Init", "Info", "Request", "RequestMany", "IsResolved", "PendingCount", "Get",
                   "Link", "TypeKeyFromNames", "TypeLabel", "IsNever" },
         Net = { "Init", "Send", "RequestStatus", "RequestLists", "RequestCost", "SendApply",
                 "SendRemove", "SendRemoveAll", "QueryCollection", "CollectionState", "Handle" },
         State = { "Init", "Refresh", "RefreshEquipment", "Equipped", "SlotState", "Applied",
                   "IsInactive", "Baseline", "Wanted", "HasPending", "PendingSlots", "PendingCount",
                   "Select", "Discard", "DiscardAll", "Toggle", "SetMany", "List", "IsAvailable",
                   "Cost", "RequestCost", "CanApply", "Apply", "RemoveAll", "Busy", "SetVendor",
                   "OnOpen", "OnStatus", "OnListStart", "OnListChunk", "OnListEnd", "OnCost",
                   "OnApplyResult", "OnCollectionUpdated", "OnCollectionStatus" },
         Filter = { "SetSearch", "SetQuality", "SetType", "SetSort", "SetHideDuplicates",
                    "SetFavoritesOnly", "SetNewOnly", "IsActive", "Reset", "Compute", "Types",
                    "Qualities", "Page" },
         Outfits = { "Init", "List", "Get", "Exists", "ValidateName", "CurrentLook", "Save",
                     "Overwrite", "Delete", "Rename", "Load" },
         Locale = { "Add", "Set", "Current", "List" },
      }
      for mod, names in pairs(FUNCS) do
         local tbl = T[mod]
         H.eq(type(tbl), "table", "Modul T." .. mod)
         if type(tbl) == "table" then
            for _, name in ipairs(names) do
               H.eq(type(tbl[name]), "function", "T." .. mod .. "." .. name .. " ist eine Funktion")
            end
         end
      end

      -- Felder und Konstanten
      H.eq(type(T.VERSION), "string", "T.VERSION")
      H.eq(T.ADDON, "Transmog", "T.ADDON")
      H.eq(T.PREFIX, "transmog", "T.PREFIX")
      H.eq(T.HIDDEN_ID, 999999, "T.HIDDEN_ID")
      H.eq(type(T.COLORS), "table", "T.COLORS")
      H.eq(type(T.HEX), "table", "T.HEX")
      for _, k in ipairs({ "accent", "text", "dim", "yellow", "green", "red", "blue", "grey", "pink" }) do
         H.eq(type(T.COLORS[k]), "table", "T.COLORS." .. k)
         H.eq(#T.COLORS[k], 3, "T.COLORS." .. k .. " hat r,g,b")
         H.matches(T.HEX[k], "^|cff%x%x%x%x%x%x$", "T.HEX." .. k)
      end
      H.matches(T.HEX.white, "^|cff%x%x%x%x%x%x$", "T.HEX.white")
      H.eq(type(T.IsLoginSweep), "function", "T.IsLoginSweep")
      H.eq(type(T.RefreshPlayerInfo), "function", "T.RefreshPlayerInfo")
      H.eq(T.race, "human", "T.race (klein, englisches Token)")
      H.eq(T.class, "warrior", "T.class")
      H.eq(T.faction, "A", "T.faction")
      H.eq(T.debug, false, "T.debug")
      H.eq(type(T.L), "table", "T.L")
      H.eq(type(DB.global), "table", "DB.global")
      H.eq(type(DB.char), "table", "DB.char")
      H.eq(T.Slots.COUNT, 14, "Slots.COUNT")
      H.eq(#T.Slots.LIST, 14, "Slots.LIST")
      H.eq(type(T.Slots.BY_SERVER), "table", "Slots.BY_SERVER")
      H.eq(type(T.Slots.BY_KEY), "table", "Slots.BY_KEY")
      H.eq(type(T.Slots.BY_CLIENT), "table", "Slots.BY_CLIENT")
      H.eq(T.Outfits.MAX, 50, "Outfits.MAX")
      H.deepEq(T.Items.ARMOR_TYPES, { 401, 402, 403, 404 }, "Items.ARMOR_TYPES")
      H.deepEq(T.Items.ARMOR_ORDER, { 404, 403, 402, 401 }, "Items.ARMOR_ORDER")
      H.eq(type(T.Items.NEVER), "table", "Items.NEVER")
      H.eq(Net.state, "OK", "Net.state")
      H.eq(type(Filter.state), "table", "Filter.state")
      H.eq(type(Filter.search), "string", "Filter.search")
      H.eq(State.atVendor, false, "State.atVendor")
      H.eq(State.openedByNpc, false, "State.openedByNpc")
      H.eq(type(State.new), "table", "State.new")

      -- Slots.LIST: Anzeigereihenfolge und Felder (SPEC 5.5)
      local order = {}
      for i, def in ipairs(T.Slots.LIST) do
         order[i] = def.key
         H.eq(T.Slots.BY_SERVER[def.server], def, "BY_SERVER " .. def.key)
         H.eq(T.Slots.BY_KEY[def.key], def, "BY_KEY " .. def.key)
         H.eq(T.Slots.BY_CLIENT[def.client], def, "BY_CLIENT " .. def.key)
         H.eq(def.client, def.server + 1, "client = server + 1 " .. def.key)
         H.eq(type(def.invName), "string", "invName " .. def.key)
         H.eq(type(def.globalName), "string", "globalName " .. def.key)
         H.eq(def.hideable, HIDEABLE[def.server] == true, "hideable " .. def.key)
         H.truthy(def.column == 1 or def.column == 2, "column " .. def.key)
         H.eq(type(def.index), "number", "index " .. def.key)
         H.eq(def.hand, def.key == "MAINHAND" or def.key == "OFFHAND", "hand " .. def.key)
         H.eq(def.weapon, def.key == "MAINHAND" or def.key == "OFFHAND" or def.key == "RANGED", "weapon " .. def.key)
      end
      H.deepEq(order, { "HEAD", "SHOULDER", "BACK", "CHEST", "SHIRT", "TABARD", "WRIST",
                        "HANDS", "WAIST", "LEGS", "FEET", "MAINHAND", "OFFHAND", "RANGED" }, "Slots.LIST Reihenfolge")
      H.eq(T.Slots.Next(HEAD, 1), SHOULDER, "Next vorwaerts")
      H.eq(T.Slots.Next(HEAD, -1), RANGED, "Next rueckwaerts, zyklisch")
      H.eq(T.Slots.Next(RANGED, 1), HEAD, "Next zyklisch")
      H.eq(T.Slots.IsHideable(HEAD), true, "IsHideable Kopf")
      H.eq(T.Slots.IsHideable(MAINHAND), false, "IsHideable Haupthand")
      H.eq(type(T.Slots.EmptyTexture(HEAD)), "string", "EmptyTexture")
      H.eq(T.Slots.Label(HEAD), "Head", "Label")

      -- Items.Info / State.Equipped / State.List / State.Cost / Filter.Compute (Formen)
      local info = Items.Info(candId(HEAD, 3))
      H.truthy(info, "Items.Info bekannt")
      for _, k in ipairs({ "id", "name", "link", "quality", "ilvl", "minLevel", "typeName",
                           "subtypeName", "equipLoc", "icon" }) do
         H.neq(info and info[k], nil, "Items.Info." .. k)
      end
      H.eq(info.typeKey, 404, "Items.Info.typeKey")
      H.eq(Items.Link(candId(HEAD, 3)):find("item:", 1, true) ~= nil, true, "Items.Link")
      H.eq(Items.Link(31337), "item:31337", "Items.Link ohne Cache")
      H.eq(Items.TypeKeyFromNames("Armor", "Plate"), 404, "TypeKeyFromNames Platte")
      H.eq(Items.TypeKeyFromNames("Weapon", "Bows"), 202, "TypeKeyFromNames Bogen")
      H.eq(Items.TypeKeyFromNames("Unsinn", "Unsinn"), nil, "TypeKeyFromNames unbekannt")
      H.eq(Items.TypeLabel(404), "Plate", "TypeLabel")
      H.eq(Items.IsNever("INVTYPE_RELIC"), true, "IsNever Relikt")
      H.eq(Items.IsNever("INVTYPE_HEAD"), false, "IsNever Kopf")
      H.eq(Items.IsResolved(candId(HEAD, 3)), true, "IsResolved")
      H.eq(Items.Get(999888) == nil, true, "Items.Get unbekannt -> nil")

      local eq = State.Equipped(HEAD)
      for _, k in ipairs({ "id", "link", "name", "quality", "icon", "equipLoc", "typeKey" }) do
         H.neq(eq[k], nil, "State.Equipped." .. k)
      end
      local list = State.List(HEAD)
      for _, k in ipairs({ "ids", "set", "bucket", "amount", "received", "ready" }) do
         H.neq(list[k], nil, "State.List." .. k)
      end
      local unknown = State.List(1)       -- Slot ohne Eintrag: nie nil
      H.eq(type(unknown), "table", "State.List(unbekannt) ist eine Tabelle")
      H.eq(#unknown.ids, 0, "State.List(unbekannt).ids leer")
      local cost = State.Cost()
      for _, k in ipairs({ "copper", "canPurchase", "valid", "pending" }) do
         H.neq(cost[k], nil, "State.Cost." .. k)
      end
      local entries, stats = Filter.Compute(HEAD)
      H.truthy(#entries > 0, "Compute liefert Eintraege")
      for _, k in ipairs({ "id", "info", "favorite", "isNew", "applied", "wanted" }) do
         H.neq(entries[1][k], nil, "Filter.Compute-Eintrag." .. k)
      end
      for _, k in ipairs({ "total", "shown", "unresolved", "hiddenByFilter" }) do
         H.eq(type(stats[k]), "number", "Filter.Compute stats." .. k)
      end
      local types = Filter.Types(HEAD)
      for _, k in ipairs({ "typeKey", "label", "count", "own" }) do
         H.neq(types[1][k], nil, "Filter.Types-Eintrag." .. k)
      end
      local quals = Filter.Qualities(HEAD)
      for _, k in ipairs({ "quality", "count" }) do
         H.neq(quals[1][k], nil, "Filter.Qualities-Eintrag." .. k)
      end
      local page, pages, clamped = Filter.Page(entries, 99, 4)
      H.eq(clamped, pages, "Filter.Page klemmt")
      H.truthy(#page <= 4, "Filter.Page Seitengroesse")

      -- Util-Formen
      local r, g, b, hex = Util.QualityColor(4)
      H.eq(type(r), "number", "QualityColor r")
      H.matches(hex, "^|cff%x%x%x%x%x%x$", "QualityColor hex")
      H.eq(Util.ItemIdFromLink("|cff0070dd|Hitem:123:0:0|h[X]|h|r"), 123, "ItemIdFromLink Link")
      H.eq(Util.ItemIdFromLink("item:77"), 77, "ItemIdFromLink item:")
      H.eq(Util.ItemIdFromLink(55), 55, "ItemIdFromLink Zahl")
      H.eq(Util.ItemIdFromLink("kein Link"), nil, "ItemIdFromLink Muell")
      H.eq(Util.FormatNumber(1234567), "1,234,567", "FormatNumber enUS")
      H.matches(Util.FormatMoney(1234567), "^123%d*|T.-UI%-GoldIcon.-|t 45|T.-UI%-SilverIcon.-|t 67|T.-UI%-CopperIcon.-|t$",
         "FormatMoney")
      H.matches(Util.FormatMoney(0), "^0|T.-UI%-CopperIcon.-|t$", "FormatMoney 0")
      H.deepEq(Util.Split("a::b", ":"), { "a", "", "b" }, "Split behaelt leere Felder")
      H.eq(Util.Trim("  x  "), "x", "Trim")
      H.eq(Util.Lower("\195\132\195\150 ABC"), "\195\164\195\182 abc", "Lower UTF-8")
      H.eq(Util.Clamp(5, 1, 3), 3, "Clamp")
      H.eq(Util.Round(2.5), 3, "Round")
      H.eq(Util.Hex(1, 0.5, 0), "|cffff8000", "Hex")
      H.eq(Util.Count({ a = 1, b = 2 }), 2, "Count")

      -- Locale
      local langs = T.Locale.List()
      H.eq(#langs, 8, "Locale.List: 8 Sprachen")
      H.eq(langs[1].code, "enUS", "erste Sprache")
      H.eq(langs[2].name, "Deutsch", "native Namen")
      H.eq(T.Locale.Current(), "enUS", "Locale.Current")

      -- Net.Send: Form der Nachricht
      clearSent()
      Net.Send("Apply", "0:123")
      Net.Send("RemoveAll")
      local cmds = M.SentCommands()
      H.eq(cmds[1], "Apply:0:123", "Net.Send mit Argument")
      H.eq(cmds[2], "RemoveAll", "Net.Send ohne Argument")
      H.eq(M.sentAddon[1].prefix, "transmog", "Praefix")
      H.eq(M.sentAddon[1].channel, "WHISPER", "Kanal")
      H.eq(M.sentAddon[1].target, "Testplayer", "Ziel = eigener Name")
      noErrors("SPEC")
   end)

   -- ======================================================================
   -- 10. Zufallsfolge ueber alle Module (feste Startwerte, Invarianten)
   -- ======================================================================

   -- Linearer Kongruenzgenerator (MINSTD); Rueckgabe 1..n
   local function newRng(seed)
      local state = seed
      return function(n)
         state = (state * 48271) % 2147483647
         return (state % n) + 1
      end
   end

   local function randomWalk(seed, steps)
      local rnd = newRng(seed)
      startSession({
         stored = { [HEAD] = candId(HEAD, 3), [CHEST] = HIDDEN, [LEGS] = 2699 },
      })
      settle(5.0)
      local trace = {}
      local function note(text)
         trace[#trace + 1] = text
         if #trace > 25 then table.remove(trace, 1) end
      end
      local function where(step)
         return "Seed " .. seed .. " Schritt " .. step .. " [" .. table.concat(trace, " | ") .. "]"
      end

      local reasons = {}     -- Haeufigkeit der Gruende, warum Anwenden nicht ging
      local names = { "A", "B", "C", "d", "Raid Set", "Alt (2)" }
      local searches = { "", "look", "#2001", "plate", "zzz", "2" }
      local locales = { "enUS", "deDE", "frFR", "auto", "xxYY" }
      local swapSubs = { "Plate", "Mail" }

      -- gemeinsame Invarianten nach jedem Schritt
      local function invariants(step)
         local w = where(step)
         if #M.errors > 0 then
            H.fail("Handlerfehler: " .. tostring(M.errors[1]) .. " bei " .. w)
            return false
         end
         for _, slot in ipairs(SERVER_SLOTS) do
            local st = State.SlotState(slot)
            if State.HasPending(slot) then
               if st ~= "READY" then H.fail("Auswahl in nicht-READY-Slot " .. slot .. " bei " .. w) return false end
               local want = State.Wanted(slot)
               local list = State.List(slot)
               if want ~= 0 and want ~= HIDDEN and list.ready and not list.set[want] then
                  H.fail("Auswahl " .. want .. " nicht in der fertigen Liste von Slot " .. slot .. " bei " .. w)
                  return false
               end
               if want == HIDDEN and not HIDEABLE[slot] then
                  H.fail("HIDDEN in nicht verbergbarem Slot " .. slot .. " bei " .. w)
                  return false
               end
            end
            if State.IsInactive(slot) and not State.List(slot).ready then
               H.fail("inaktiv ohne fertige Liste, Slot " .. slot .. " bei " .. w)
               return false
            end
            if State.Baseline(slot) ~= 0 and State.IsInactive(slot) then
               H.fail("Baseline ~= 0 bei inaktivem Aussehen, Slot " .. slot .. " bei " .. w)
               return false
            end
         end
         local pend = State.PendingSlots()
         if #pend ~= State.PendingCount() then
            H.fail("PendingSlots/PendingCount weichen ab bei " .. w)
            return false
         end
         for i = 2, #pend do
            if pend[i - 1] >= pend[i] then H.fail("PendingSlots nicht aufsteigend bei " .. w) return false end
         end
         local c = State.Cost()
         if type(c.copper) ~= "number" or c.copper < 0 or type(c.valid) ~= "boolean"
            or type(c.pending) ~= "boolean" or type(c.canPurchase) ~= "boolean" then
            H.fail("Cost() ungueltig bei " .. w)
            return false
         end
         local started, done = evCount("APPLY_STARTED"), evCount("APPLY_DONE")
         if State.Busy() then
            if started ~= done + 1 then H.fail("busy, aber Start/Ende-Bilanz " .. started .. "/" .. done .. " bei " .. w) return false end
         else
            if started ~= done then H.fail("nicht busy, aber Start/Ende-Bilanz " .. started .. "/" .. done .. " bei " .. w) return false end
         end
         return true
      end

      local function pickSlot() return SERVER_SLOTS[rnd(#SERVER_SLOTS)] end

      local ops = {}
      local refillAt = nil     -- Schritt, an dem das Geld wieder aufgefuellt wird

      ops[#ops + 1] = function()
         local slot = pickSlot()
         local list = State.List(slot).ids
         local kind = rnd(10)
         local id
         if kind <= 5 and #list > 0 then
            id = list[rnd(#list)]
         elseif kind == 6 then
            id = HIDDEN
         elseif kind == 7 then
            id = 0
         elseif kind == 8 then
            id = candId(pickSlot(), rnd(8))
         elseif kind == 9 then
            id = 1234567
         else
            id = "x"
         end
         note("Select(" .. slot .. "," .. tostring(id) .. ")")
         State.Select(slot, id)
      end
      ops[#ops + 1] = function()
         local slot = pickSlot()
         local kind = rnd(3)
         note("Discard/Toggle " .. slot .. " k" .. kind)
         if kind == 1 then State.Discard(slot) elseif kind == 2 then State.Toggle(slot) else State.DiscardAll() end
      end
      ops[#ops + 1] = function()
         note("Apply")
         if rnd(3) > 1 then State.SetVendor(true) end
         State.Apply()
      end
      -- gezielt: gueltige Auswahlen treffen, Kosten abwarten, anwenden
      local function prepareAndApply()
         local n = rnd(3)
         for _ = 1, n do
            local slot = pickSlot()
            local list = State.List(slot).ids
            if State.SlotState(slot) == "READY" and #list > 0 then
               local id = list[rnd(#list)]
               State.Select(slot, id)
            elseif HIDEABLE[slot] and State.SlotState(slot) == "READY" then
               State.Select(slot, HIDDEN)
            end
         end
         State.SetVendor(true)
         -- Kosten abwarten (Entprellung 0,25 s + Laufzeit des Servers), hoechstens 3 s
         for _ = 1, 60 do
            settle(0.05)
            if not State.Cost().pending then break end
         end
         local okApply, whyApply = State.CanApply()
         reasons[tostring(whyApply)] = (reasons[tostring(whyApply)] or 0) + 1
         note("Vorbereiten+Anwenden (" .. State.PendingCount() .. " Slots, " .. tostring(whyApply) .. ")")
         State.Apply()
      end
      ops[#ops + 1] = prepareAndApply
      ops[#ops + 1] = prepareAndApply
      ops[#ops + 1] = prepareAndApply
      ops[#ops + 1] = function()
         note("RemoveAll")
         State.SetVendor(true)
         State.RemoveAll()
      end
      ops[#ops + 1] = function()
         local slot = pickSlot()
         local kind = rnd(3)
         if kind == 1 then
            local id = 7000 + slot * 10 + rnd(5)
            M.items[id] = {
               name = "Fuzz " .. id, quality = rnd(5) - 1, ilvl = 50, minLevel = 0,
               class = EQUIP[slot].class, subclass = swapSubs[rnd(2)] and EQUIP[slot].sub,
               equipLoc = EQUIP[slot].loc, icon = "Interface\\Icons\\INV_Fuzz_" .. id,
            }
            META[id] = { slot = slot, class = EQUIP[slot].class, sub = EQUIP[slot].sub,
               loc = EQUIP[slot].loc, quality = 2, name = "Fuzz " .. id }
            M.world.equipment[slot + 1] = id
            note("Equip " .. slot .. "=" .. id)
         elseif kind == 2 then
            M.world.equipment[slot + 1] = nil
            note("Unequip " .. slot)
         else
            M.world.equipment[slot + 1] = equipId(slot)
            note("Reequip " .. slot)
         end
         M.Fire("PLAYER_EQUIPMENT_CHANGED", slot + 1, M.world.equipment[slot + 1] == nil)
      end
      ops[#ops + 1] = function()
         local kind = rnd(7)
         if kind == 1 then
            local id = candId(pickSlot(), rnd(8))
            srv.reject[id] = not srv.reject[id] or nil
            note("reject " .. id)
         elseif kind == 2 then
            srv.latency = rnd(12) / 20
            note("latency " .. srv.latency)
         elseif kind == 3 then
            srv.drop.Apply = rnd(3) - 1
            note("drop Apply " .. srv.drop.Apply)
         elseif kind == 4 then
            M.ServerMessage("CollectionUpdated:" .. candId(pickSlot(), rnd(8)))
            note("CollectionUpdated")
         elseif kind == 5 then
            -- knappes Geld nur kurz (siehe unten: wird wieder aufgefuellt)
            M.world.money = (rnd(6) - 1) * 10000
            M.Fire("PLAYER_MONEY")
            note("money " .. M.world.money)
            refillAt = refillAt or -1
         elseif kind == 6 then
            srv.price = rnd(3) * 5000
            note("price " .. srv.price)
         else
            srv.lowerTiers = not srv.lowerTiers
            note("lowerTiers " .. tostring(srv.lowerTiers))
         end
      end
      ops[#ops + 1] = function()
         local kind = rnd(6)
         local name = names[rnd(#names)]
         if kind == 1 then
            note("Save " .. name)
            Outfits.Save(name)
         elseif kind == 2 then
            note("Load " .. name)
            local a, sk = Outfits.Load(name)
            if type(a) ~= "table" or type(sk) ~= "table" then H.fail("Load liefert keine Tabellen") end
         elseif kind == 3 then
            note("Delete " .. name)
            Outfits.Delete(name)
         elseif kind == 4 then
            note("Rename " .. name)
            Outfits.Rename(name, names[rnd(#names)])
         elseif kind == 5 then
            note("Overwrite " .. name)
            Outfits.Overwrite(name)
         else
            note("Save explizit " .. name)
            Outfits.Save(name, { [pickSlot()] = candId(pickSlot(), rnd(8)), [pickSlot()] = HIDDEN })
         end
      end
      ops[#ops + 1] = function()
         local kind = rnd(8)
         local slot = pickSlot()
         if kind == 1 then
            local text = searches[rnd(#searches)]
            note("Search '" .. text .. "'")
            Filter.SetSearch(text)
         elseif kind == 2 then
            note("Quality")
            Filter.SetQuality(rnd(8) - 1, rnd(2) == 1)
         elseif kind == 3 then
            note("Type")
            Filter.SetType(400 + rnd(4), rnd(2) == 1)
         elseif kind == 4 then
            note("Sort")
            Filter.SetSort(Filter.SORTS[rnd(3)])
         elseif kind == 5 then
            note("Flags")
            Filter.SetFavoritesOnly(rnd(4) == 1)
            Filter.SetNewOnly(rnd(4) == 1)
            Filter.SetHideDuplicates(rnd(2) == 1)
         elseif kind == 6 then
            note("Reset")
            Filter.Reset()
         elseif kind == 7 then
            local id = candId(slot, rnd(8))
            DB.char.favorites[id] = (not DB.char.favorites[id]) or nil
            Events.Fire("FAVORITES_CHANGED")
            note("Fav " .. id)
         else
            note("Compute " .. slot)
            local entries, stats = Filter.Compute(slot)
            if #entries ~= stats.shown then H.fail("Compute: shown ~= #entries bei Slot " .. slot) end
            if stats.shown + stats.hiddenByFilter + stats.hiddenDuplicates + stats.unresolved ~= stats.total then
               H.fail("Compute: Bilanz stimmt nicht bei Slot " .. slot .. ": " .. stats.shown .. "+"
                  .. stats.hiddenByFilter .. "+" .. stats.hiddenDuplicates .. "+" .. stats.unresolved
                  .. " ~= " .. stats.total)
            end
            local page, pages, clamped = Filter.Page(entries, rnd(5), 6)
            if #page > 6 or pages < 1 or clamped < 1 or clamped > pages then
               H.fail("Page ungueltig bei Slot " .. slot)
            end
            Filter.Types(slot)
            Filter.Qualities(slot)
         end
      end
      ops[#ops + 1] = function()
         local code = locales[rnd(#locales)]
         note("Locale " .. code)
         Locale.Set(code)
      end
      ops[#ops + 1] = function()
         local force = rnd(2) == 1
         note("Refresh " .. tostring(force))
         State.Refresh(force)
      end
      ops[#ops + 1] = function()
         local id = candId(pickSlot(), rnd(8))
         note("Items.Request " .. id)
         Items.Request(id)
         Net.QueryCollection(id)
      end
      local unmuteAt = nil
      ops[#ops + 1] = function()
         note("Server kurz stumm")
         srv.mute = true
      end

      for step = 1, steps do
         if refillAt == -1 then refillAt = step + rnd(4) end
         if refillAt and step >= refillAt then
            M.world.money = 50000000
            M.Fire("PLAYER_MONEY")
            refillAt = nil
         end
         if srv.mute then
            -- der Server ist nur kurz stumm (sonst gaebe es nie ein Anwenden)
            unmuteAt = unmuteAt or (step + rnd(6))
            if step >= unmuteAt then
               srv.mute = false
               unmuteAt = nil
            end
         end
         ops[rnd(#ops)]()
         -- Zeit vergeht in unterschiedlich langen Stuecken
         local dt = (rnd(8) - 1) * 0.15
         if dt > 0 then
            settle(dt)
         else
            srv.pump()
         end
         if not invariants(step) then return end
      end

      -- Die Folge soll wirklich etwas bewegt haben (keine leere Pruefung)
      local reasonText = {}
      for k, v in pairs(reasons) do reasonText[#reasonText + 1] = k .. "=" .. v end
      table.sort(reasonText)
      local activity = string.format("Anwenden %d/%d, Ausruestung %d, Listen %d, Auswahl %d, Kosten %d, Outfits %d, Gruende %s",
         evCount("APPLY_STARTED"), evCount("APPLY_DONE"), evCount("EQUIPMENT_CHANGED"),
         evCount("LIST_READY"), evCount("WANTED_CHANGED"), evCount("COST_CHANGED"), evCount("OUTFITS_CHANGED"),
         table.concat(reasonText, ","))
      H.truthy(evCount("APPLY_STARTED") >= 2, "Folge wendete an (" .. activity .. ")")
      H.truthy(evCount("EQUIPMENT_CHANGED") >= 4, "Folge wechselte Ausruestung (" .. activity .. ")")
      H.truthy(evCount("LIST_READY") >= 28, "Folge lud Listen (" .. activity .. ")")
      H.truthy(evCount("WANTED_CHANGED") >= 10, "Folge wechselte Auswahl (" .. activity .. ")")
      H.truthy(evCount("OUTFITS_CHANGED") >= 1, "Folge speicherte Outfits (" .. activity .. ")")
      if os.getenv and false then print(activity) end

      -- Ruhe: Server laut, keine Verluste, alles abarbeiten lassen
      srv.mute = false
      srv.drop = {}
      srv.latency = 0.1
      M.world.money = 50000000
      M.Fire("PLAYER_MONEY")
      State.SetVendor(true)
      settle(40.0)
      if not invariants("Ende") then return end
      H.eq(State.Busy(), false, "Ende: nicht beschaeftigt (" .. where("Ende") .. ")")
      H.eq(State.Cost().pending, false, "Ende: Kosten nicht ausstehend (" .. where("Ende") .. ")")
      -- Nach Neuanforderung stimmen die Listen mit dem Server ueberein
      State.Refresh(true)
      settle(10.0)
      for _, slot in ipairs(SERVER_SLOTS) do
         local want = srv.list(slot)
         if State.List(slot).ready then
            H.deepEq(State.List(slot).ids, want, "Ende: Liste Slot " .. slot .. " (" .. where("Ende") .. ")")
         else
            H.fail("Ende: Liste Slot " .. slot .. " nicht fertig (" .. where("Ende") .. ")")
         end
      end
      -- Status stimmt mit dem Server ueberein
      for _, slot in ipairs(SERVER_SLOTS) do
         H.eq(State.Applied(slot), srv.stored[slot] or 0, "Ende: Status Slot " .. slot .. " (" .. where("Ende") .. ")")
      end
      -- Alles leer? (keine Timer ausser der Entprellung nach Sprachwechsel usw.)
      settle(80.0)
      H.eq(Util.TimerCount(), 0, "Ende: keine Timer (" .. where("Ende") .. ")")
      H.eq(#M.UpdateFrames(), 0, "Ende: kein OnUpdate im Leerlauf (" .. where("Ende") .. ")")
      H.deepEq(strayGlobals(), {}, "Ende: keine fremden Globals")
   end

   H.test("Zufallsfolge A: alle Module, 300 Schritte", function() randomWalk(101, 300) end)
   H.test("Zufallsfolge B: alle Module, 300 Schritte", function() randomWalk(20240511, 300) end)
   H.test("Zufallsfolge C: alle Module, 300 Schritte", function() randomWalk(7, 300) end)
   H.test("Zufallsfolge D: alle Module, 300 Schritte", function() randomWalk(31337, 300) end)

   -- Zum Suchen nach Fehlern: TRANSMOG_FUZZ=50 luajit tests/run.lua integration_core
   -- laeuft zusaetzlich so viele Folgen (je 400 Schritte) mit weiteren Startwerten.
   local extra = tonumber(os.getenv and os.getenv("TRANSMOG_FUZZ") or "") or 0
   for i = 1, extra do
      H.test("Zufallsfolge extra " .. i, function() randomWalk(1000 + i * 7919, 400) end)
   end

   -- ======================================================================
   -- 9. Ausruestung: alle 14 Slots einzeln wechseln (je Slot genau ein Ereignis)
   -- ======================================================================

   H.test("Ausruestungswechsel: jeder der 14 Slots meldet genau EQUIPMENT_CHANGED(slot)", function()
      startSession()
      settle(5.0)
      clearLog()
      for _, slot in ipairs(SERVER_SLOTS) do
         local new = 5000 + slot
         M.items[new] = {
            name = "Swap " .. slot, quality = 2, ilvl = 90, minLevel = 0,
            class = EQUIP[slot].class, subclass = EQUIP[slot].sub,
            equipLoc = EQUIP[slot].loc, icon = "Interface\\Icons\\INV_Swap_" .. slot,
         }
         META[new] = { slot = slot, class = EQUIP[slot].class, sub = EQUIP[slot].sub,
            loc = EQUIP[slot].loc, quality = 2, name = "Swap " .. slot }
         M.world.equipment[slot + 1] = new
         M.Fire("PLAYER_EQUIPMENT_CHANGED", slot + 1, false)
      end
      H.eq(evCount("EQUIPMENT_CHANGED"), 14, "14 Ereignisse")
      for i, slot in ipairs(SERVER_SLOTS) do
         local e = evList("EQUIPMENT_CHANGED")[i]
         H.eq(e and e[1], slot, "Reihenfolge Slot " .. slot)
         H.eq(State.Equipped(slot).id, 5000 + slot, "neu eingelesen " .. slot)
      end
      -- ein Wechsel loest EINE entprellte Listenabfrage aus
      clearSent()
      settle(1.0)
      H.eq(M.CountSent("GetAvailableTransmogs"), 1, "eine Listenabfrage fuer alle 14 Wechsel")
      H.truthy(State.ListsReady(), "Listen wieder fertig")
      -- unveraenderte Ausruestung loest nichts aus
      clearLog()
      clearSent()
      M.Fire("PLAYER_EQUIPMENT_CHANGED", HEAD + 1, false)
      settle(1.0)
      H.eq(evCount("EQUIPMENT_CHANGED"), 0, "keine Aenderung, kein Ereignis")
      H.eq(M.CountSent("GetAvailableTransmogs"), 0, "keine Listenabfrage")
      noErrors("Ausruestung")
   end)
end
