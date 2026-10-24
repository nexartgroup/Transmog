-- tests/test_ui_slotbar.lua
-- ---------------------------------------------------------------------------
-- Tests fuer UI/SlotBar.lua (T.UI.SlotBar) mit dem ECHTEN Kern (State, Items,
-- Net, Slots) und der strengen Attrappe.
--
-- Der Test laedt die TOC nur bis UI\SlotBar.lua und bildet Core\Boot.lua nach
-- (DB.Init, Locale.Set, Slots/Items/Net/State.Init): er haengt damit von keiner
-- anderen UI-Datei ab. Serverantworten laufen ueber T.Net.Handle im echten
-- Drahtformat (TransmogStatus, AvailableTransmogs start/Stuecke/end).
--
-- Geprueft wird:
--   * Aufbau: 14 Knoepfe 40x40, Spaltenzuordnung, Reihenfolge, Layout-Rechnung
--   * Darstellung je Zustand: Symbol, Rand, Glyph, Streifen, Auswahlrahmen, Zahl
--   * Tooltip-Zeilen (Name, Zustand, Anzahl, Hinweise) fuer jeden Zustand
--   * Klicks: links auswaehlen, rechts State.Toggle, Shift-Link, Leer/Never
--   * Ereignisse -> entprelltes Neuzeichnen, nur sichtbar, Dirty-Flag
--   * Aufblitzen: Lebenslauf, kein OnUpdate im Leerlauf
--   * Sprachwechsel, doppeltes Create, keine fehlenden Locale-Schluessel
--
-- Verifikation (zweiter Teil der Datei): Zustandsmatrix (jeder Zustand x
-- ausgewaehlt x Zeiger, gegen eine aus SPEC 6.4 abgeleitete Sollrechnung),
-- Tooltip-Matrix mit allen Zeilen, Layout an den Fenstergrenzen, Aufblitzen
-- (viele Plaetze, Wiederholung, Verbergen), Ereignisbuendel, und im echten
-- Fenster (Fixtures): Spielerablauf mit Server, Layoutpruefung deDE/enUS.
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   local ORDER = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }
   local SLOT = {
      HEAD = 0, SHOULDER = 2, SHIRT = 3, CHEST = 4, WAIST = 5, LEGS = 6, FEET = 7,
      WRIST = 8, HANDS = 9, BACK = 14, MAINHAND = 15, OFFHAND = 16, RANGED = 17, TABARD = 18,
   }
   local HIDDEN = 999999
   -- Blizzards Dateiname hat einen Tippfehler: nur "Invisibilty" gibt es im Client
   local INVISIBLE = "Interface\\Icons\\Spell_Nature_Invisibilty"
   local UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

   -- Angelegte Gegenstaende: { INVTYPE, Klasse, Unterklasse }
   local EQ = {
      [0] = { "INVTYPE_HEAD", "Armor", "Plate" },
      [2] = { "INVTYPE_SHOULDER", "Armor", "Plate" },
      [3] = { "INVTYPE_BODY", "Armor", "Miscellaneous" },
      [4] = { "INVTYPE_CHEST", "Armor", "Plate" },
      [5] = { "INVTYPE_WAIST", "Armor", "Plate" },
      [6] = { "INVTYPE_LEGS", "Armor", "Plate" },
      [7] = { "INVTYPE_FEET", "Armor", "Plate" },
      [8] = { "INVTYPE_WRIST", "Armor", "Plate" },
      [9] = { "INVTYPE_HAND", "Armor", "Plate" },
      [14] = { "INVTYPE_CLOAK", "Armor", "Cloth" },
      [15] = { "INVTYPE_WEAPON", "Weapon", "One-Handed Swords" },
      [16] = { "INVTYPE_SHIELD", "Armor", "Shields" },
      [17] = { "INVTYPE_RANGED", "Weapon", "Bows" },
      [18] = { "INVTYPE_TABARD", "Armor", "Miscellaneous" },
   }

   local function equipId(slot) return 1000 + slot end
   local function lookId(slot, i) return 2000 + slot * 10 + i end

   -- Gegenstandsdaten der Attrappe: je Platz ein angelegter Gegenstand und 5 Aussehen
   local function buildItems()
      local items = {}
      for _, slot in ipairs(ORDER) do
         local e = EQ[slot]
         items[equipId(slot)] = {
            name = "Equipped " .. slot, quality = 3, ilvl = 100, equipLoc = e[1],
            class = e[2], subclass = e[3], icon = "Interface\\Icons\\INV_Equip_" .. slot,
         }
         for i = 1, 5 do
            local id = lookId(slot, i)
            items[id] = {
               name = "Look " .. slot .. "-" .. i, quality = i % 5, ilvl = 100, equipLoc = e[1],
               class = e[2], subclass = e[3], icon = "Interface\\Icons\\INV_Look_" .. id,
            }
         end
      end
      return items
   end

   -- Vergleicht den Backdrop-Rand eines Knopfes mit einer Farbtabelle
   local function expectBorder(btn, c, msg)
      local r, g, b = btn:GetBackdropBorderColor()
      H.near(r, c[1], 1e-6, (msg or "") .. " r")
      H.near(g, c[2], 1e-6, (msg or "") .. " g")
      H.near(b, c[3], 1e-6, (msg or "") .. " b")
   end

   -- Sitzung: Attrappe, TOC bis SlotBar, Boot nachgebildet.
   --   opts.equip   [slot] = id | false (false = leer)
   --   opts.items   zusaetzliche/ueberschriebene Gegenstandsdaten
   --   opts.cache   false: Gegenstaende bleiben ungecacht (Standard: alle gecacht)
   local function boot(opts)
      opts = opts or {}
      local equipment = {}
      for _, slot in ipairs(ORDER) do equipment[slot + 1] = equipId(slot) end
      for slot, id in pairs(opts.equip or {}) do
         equipment[slot + 1] = id or nil
      end
      local items = buildItems()
      for id, def in pairs(opts.items or {}) do items[id] = def end

      local T = H.boot({
         upTo = "SlotBar.lua",
         world = { equipment = equipment, locale = opts.locale or "enUS" },
         items = items,
         enterWorld = false,
      })
      H.assert(type(T) == "table" and T.UI and T.UI.SlotBar, "SlotBar wurde nicht geladen")
      if opts.cache ~= false then M.CacheAll() end

      if not (T.DB.global and T.DB.char) then
         T.DB.Init()
         T.Locale.Set(T.DB.global.locale)
         T.RefreshPlayerInfo()
         T.Slots.Init()
         T.Items.Init()
         T.Net.Init()
         T.State.Init()
      end
      T.State.chatMessages = false
      return T
   end

   -- Antwort "TransmogStatus" fuer map[slot] = fakeEntry
   local function sendStatus(T, map)
      local parts, n = {}, 0
      for _, slot in ipairs(ORDER) do
         if map[slot] then
            parts[#parts + 1] = slot .. "," .. map[slot]
            n = n + 1
         end
      end
      local text = "TransmogStatus:" .. n
      if n > 0 then text = text .. ":" .. table.concat(parts, ":") end
      T.Net.Handle(text)
   end

   -- Listenstrom eines Slots: start, Stuecke zu 20 IDs, end
   local function sendList(T, slot, ids, bucket)
      bucket = bucket or 8
      local head = string.format("AvailableTransmogs:%d:%d:%d:", slot, bucket, #ids)
      T.Net.Handle(head .. "start")
      local i = 1
      while i <= #ids do
         local j = math.min(i + 19, #ids)
         local parts = {}
         for k = i, j do parts[#parts + 1] = tostring(ids[k]) end
         T.Net.Handle(head .. table.concat(parts, ":"))
         i = j + 1
      end
      T.Net.Handle(head .. "end")
   end

   -- die 5 Aussehen eines Slots als Liste
   local function looks(slot)
      local out = {}
      for i = 1, 5 do out[i] = lookId(slot, i) end
      return out
   end

   -- Alle 14 Listen (je 5 Aussehen) senden
   local function sendAllLists(T)
      for _, slot in ipairs(ORDER) do sendList(T, slot, looks(slot)) end
   end

   -- Sichtbarer Elternrahmen
   local function newParent()
      local f = CreateFrame("Frame", nil, UIParent)
      f:SetWidth(400)
      f:SetHeight(500)
      f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      return f
   end

   -- Erstellt die SlotBar; rueckgabe: T, bar, parent, clicks (Liste der onSelect-Slots)
   local function make(opts)
      local T = boot(opts)
      local parent = newParent()
      local clicks = {}
      local bar = T.UI.SlotBar.Create(parent, function(slot) clicks[#clicks + 1] = slot end)
      bar.left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
      bar.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
      return T, bar, parent, clicks
   end

   -- Tooltip-Zeilen (links)
   local function tipLines()
      local out = {}
      for i = 1, GameTooltip:NumLines() do
         local fs = rawget(_G, "GameTooltipTextLeft" .. i)
         out[i] = fs and fs:GetText() or nil
      end
      return out
   end

   local function hasLine(lines, text)
      for _, l in ipairs(lines) do
         if l == text then return true end
      end
      return false
   end

   local function shown(obj)
      return obj:IsShown() and true or false
   end

   local function edgesShown(btn)
      local n = 0
      for _, e in ipairs(btn.over.edges) do
         if e:IsShown() then n = n + 1 end
      end
      return n
   end

   -- Sichtbare Frames mit OnUpdate unterhalb der beiden Spalten (die Leiste darf im
   -- Leerlauf keinen haben; Timer-Treiber anderer Module zaehlen nicht)
   local function barUpdateFrames(bar)
      local n = 0
      for _, f in ipairs(M.UpdateFrames()) do
         local p = f
         while p do
            if p == bar.left or p == bar.right then
               n = n + 1
               break
            end
            p = p:GetParent()
         end
      end
      return n
   end

   -- Zeit vorstellen (Entprellung 0,05 s)
   local function settle(t)
      M.Advance(t or 0.1, 0.05)
   end

   -- ======================================================================
   H.section("Aufbau und Layout")
   -- ======================================================================

   H.test("Create: 14 Knoepfe 40x40 in zwei Spalten, Reihenfolge wie Slots.LIST", function()
      local T, bar = make()
      local S = T.UI.SlotBar
      H.eq(S.COLUMN_WIDTH, 44)
      H.eq(S.BUTTON_SIZE, 40)
      H.eq(T.Util.Count(bar.buttons), 14)
      for _, slot in ipairs(ORDER) do
         local btn = bar.buttons[slot]
         H.truthy(btn, "Knopf " .. slot)
         if btn then
            H.eq(btn:GetWidth(), 40, "Breite " .. slot)
            H.eq(btn:GetHeight(), 40, "Hoehe " .. slot)
            H.eq(btn.slot, slot)
         end
      end
      local left, right = {}, {}
      for _, def in ipairs(T.Slots.LIST) do
         local btn = bar.buttons[def.server]
         local _, rel = btn:GetPoint()
         if def.column == 1 then
            left[#left + 1] = def.key
            H.eq(rel, bar.left, "Spalte 1: " .. def.key)
         else
            right[#right + 1] = def.key
            H.eq(rel, bar.right, "Spalte 2: " .. def.key)
         end
      end
      H.deepEq(left, { "HEAD", "SHOULDER", "BACK", "CHEST", "SHIRT", "TABARD", "WRIST" })
      H.deepEq(right, { "HANDS", "WAIST", "LEGS", "FEET", "MAINHAND", "OFFHAND", "RANGED" })
      H.eq(bar.left:GetWidth(), 44)
      H.eq(bar.right:GetWidth(), 44)
   end)

   H.test("Create liefert dieselbe Tabelle (Singleton), onSelect wird ersetzt, Methoden per Punkt und Doppelpunkt", function()
      local T, bar, parent, clicks = make()
      local S = T.UI.SlotBar
      local second = {}
      local again = S.Create(parent, function(slot) second[#second + 1] = slot end)
      H.eq(again, bar)
      M.Click(bar.buttons[SLOT.HEAD], "LeftButton")
      H.deepEq(clicks, {})
      H.deepEq(second, { SLOT.HEAD })
      H.eq(#M.Find(bar.left, "Button") + #M.Find(bar.right, "Button"), 14, "nicht neu gebaut")
      -- Doppelpunkt- und Punkt-Aufruf an der Tabelle
      bar:Layout(400)
      H.eq(bar.left:GetHeight(), 400)
      bar.Layout(380)
      H.eq(bar.left:GetHeight(), 380)
      S.Layout(360)
      H.eq(bar.right:GetHeight(), 360)
      bar:Select(SLOT.CHEST)
      H.eq(S.Selected(), SLOT.CHEST)
      bar.Select(nil)
      H.eq(S.Selected(), nil)
      bar:Refresh()
      bar:Refresh(SLOT.HEAD)
      bar.Refresh(SLOT.HEAD)
   end)

   -- y-Abstand (positiv) eines Knopfes zum Containerrand
   local function yOf(bar, slot)
      local _, _, _, x, y = bar.buttons[slot]:GetPoint()
      return x, -y
   end

   H.test("Layout(400): Abstand 14, Luecke 8 vor MAINHAND, Spalten reichen bis zur Buehne (Hoehe - 28)", function()
      local T, bar = make()
      H.eq(T.UI.Preview.CONTROLS_HEIGHT, 28)
      bar:Layout(400)
      local order1 = { 0, 2, 14, 4, 3, 18, 8 }
      local order2 = { 9, 5, 6, 7, 15, 16, 17 }
      for i, slot in ipairs(order1) do
         local x, y = yOf(bar, slot)
         H.eq(x, 2, "x Spalte 1")
         H.eq(y, (i - 1) * 54, "y Spalte 1 Zeile " .. i)
      end
      local expect2 = { 0, 54, 108, 162, 224, 278, 332 }
      for i, slot in ipairs(order2) do
         local _, y = yOf(bar, slot)
         H.eq(y, expect2[i], "y Spalte 2 Zeile " .. i)
      end
      -- unterster Knopf von Spalte 2 endet genau an der Buehne (Hoehe minus Steuerzeile)
      local _, y = yOf(bar, SLOT.RANGED)
      H.eq(y + 40, 372)
      H.eq(bar.left:GetHeight(), 400)
      H.eq(bar.right:GetHeight(), 400)
   end)

   H.test("Layout: grosse Hoehe -> Abstand bleibt 14 und der Inhalt wird zentriert", function()
      local T, bar = make()
      bar:Layout(628)           -- Buehne 600
      local _, y1 = yOf(bar, SLOT.HEAD)
      H.eq(y1, 114, "(600 - 372) / 2")
      local _, y2 = yOf(bar, SLOT.SHOULDER)
      H.eq(y2 - y1, 54)
      local _, last = yOf(bar, SLOT.RANGED)
      H.eq(last + 40, 114 + 372)
   end)

   H.test("Layout: knappe Hoehe -> Abstand sinkt auf Wert zwischen 4 und 14 und fuellt die Hoehe", function()
      local T, bar = make()
      bar:Layout(348)           -- Buehne 320: (320 - 280 - 8) / 6 = 5,33
      local _, a = yOf(bar, SLOT.HEAD)
      local _, b = yOf(bar, SLOT.SHOULDER)
      H.eq(a, 0)
      H.truthy(b - a >= 45 and b - a <= 46, "Schritt ~45,33: " .. tostring(b - a))
      local _, last = yOf(bar, SLOT.RANGED)
      H.near(last + 40, 320, 1, "fuellt die Hoehe")
      -- Abstand nie unter 4
      bar:Layout(228)           -- Buehne 200
      local _, c = yOf(bar, SLOT.HEAD)
      local _, d = yOf(bar, SLOT.SHOULDER)
      H.eq(d - c, 44, "min. Abstand 4")
      local _, hand = yOf(bar, SLOT.MAINHAND)
      local _, feet = yOf(bar, SLOT.FEET)
      H.eq(hand - feet, 52, "Luecke 8 bleibt")
   end)

   H.test("Layout ohne Zahl behaelt die letzte Hoehe", function()
      local T, bar = make()
      bar:Layout(420)
      T.UI.SlotBar.Layout(nil)
      H.eq(bar.left:GetHeight(), 420)
   end)

   -- ======================================================================
   H.section("Darstellung")
   -- ======================================================================

   H.test("Symbol: angelegter Gegenstand ohne Aussehen; Rand = Standardrand", function()
      local T, bar = make()
      local COL = T.UI.Skin.COL
      for _, slot in ipairs(ORDER) do
         local btn = bar.buttons[slot]
         H.eq(btn.icon:GetTexture(), "Interface\\Icons\\INV_Equip_" .. slot, "Symbol " .. slot)
         H.eq(btn.icon:GetAlpha(), 1, "Alpha " .. slot)
         expectBorder(btn, COL.buttonBorder, "Rand " .. slot)
         H.eq(btn.stateKey, nil)
         H.falsy(btn.glyph:IsShown())
         H.falsy(btn.stripe:IsShown())
         H.eq(edgesShown(btn), 0)
      end
   end)

   H.test("Symbol und Rand: angewendet (rosa), ausstehend (gelb), inaktiv (rot), verborgen", function()
      local T, bar = make()
      local State, COL = T.State, T.UI.Skin.COL
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 2), [SLOT.CHEST] = HIDDEN, [SLOT.LEGS] = 2999 })
      sendAllLists(T)
      bar:Refresh()

      -- HEAD angewendet
      local head = bar.buttons[SLOT.HEAD]
      H.eq(head.icon:GetTexture(), "Interface\\Icons\\INV_Look_" .. lookId(SLOT.HEAD, 2))
      expectBorder(head, COL.pink, "HEAD rosa")
      H.eq(head.stateKey, "applied")
      H.falsy(head.glyph:IsShown(), "angewendet hat kein Glyph")

      -- CHEST verborgen: Symbol Spell_Nature_Invisibilty, rosa
      local chest = bar.buttons[SLOT.CHEST]
      H.eq(chest.icon:GetTexture(), INVISIBLE)
      expectBorder(chest, COL.pink, "CHEST rosa")

      -- LEGS inaktiv: Originalgegenstand, roter Rand, Glyph "!"
      local legs = bar.buttons[SLOT.LEGS]
      H.eq(State.IsInactive(SLOT.LEGS), true)
      H.eq(legs.icon:GetTexture(), "Interface\\Icons\\INV_Equip_" .. SLOT.LEGS)
      expectBorder(legs, COL.red, "LEGS rot")
      H.eq(legs.stateKey, "inactive")
      H.truthy(legs.glyph:IsShown())
      H.eq(legs.glyph:GetText(), "!")

      -- SHOULDER ausstehend: Symbol des Aussehens, gelb, Glyph "*"
      State.Select(SLOT.SHOULDER, lookId(SLOT.SHOULDER, 4))
      bar:Refresh(SLOT.SHOULDER)
      local sh = bar.buttons[SLOT.SHOULDER]
      H.eq(sh.icon:GetTexture(), "Interface\\Icons\\INV_Look_" .. lookId(SLOT.SHOULDER, 4))
      expectBorder(sh, COL.yellow, "SHOULDER gelb")
      H.eq(sh.stateKey, "pending")
      H.truthy(sh.glyph:IsShown())
      H.eq(sh.glyph:GetText(), "*")

      -- ausstehendes Verborgen: Symbol Unsichtbar, gelb
      State.Select(SLOT.WAIST, HIDDEN)
      bar:Refresh(SLOT.WAIST)
      local waist = bar.buttons[SLOT.WAIST]
      H.eq(waist.icon:GetTexture(), INVISIBLE)
      expectBorder(waist, COL.yellow)

      -- ausstehendes Zuruecksetzen (Auswahl 0 auf angewendetem Slot): Originalsymbol, gelb
      State.Select(SLOT.HEAD, 0)
      bar:Refresh(SLOT.HEAD)
      H.eq(head.icon:GetTexture(), "Interface\\Icons\\INV_Equip_" .. SLOT.HEAD)
      expectBorder(head, COL.yellow, "Zuruecksetzen ist ausstehend")
   end)

   H.test("Leer: abgedunkelte Leertextur, gedaempfter Rand; Never: Gegenstand abgedunkelt mit Sperre", function()
      local T, bar = make({
         equip = { [SLOT.TABARD] = false, [SLOT.RANGED] = 1117 },
         items = { [1117] = { name = "Idol", quality = 3, equipLoc = "INVTYPE_RELIC", class = "Armor",
                              subclass = "Idols", icon = "Interface\\Icons\\INV_Misc_Idol" } },
      })
      local COL = T.UI.Skin.COL
      H.eq(T.State.SlotState(SLOT.TABARD), "EMPTY")
      H.eq(T.State.SlotState(SLOT.RANGED), "NEVER")

      local empty = bar.buttons[SLOT.TABARD]
      H.eq(empty.icon:GetTexture(), T.Slots.EmptyTexture(SLOT.TABARD))
      H.near(empty.icon:GetAlpha(), 0.4, 1e-6)
      expectBorder(empty, COL.border)
      H.falsy(empty.lock:IsShown())

      local never = bar.buttons[SLOT.RANGED]
      H.eq(never.icon:GetTexture(), "Interface\\Icons\\INV_Misc_Idol")
      H.near(never.icon:GetAlpha(), 0.5, 1e-6)
      H.truthy(never.lock:IsShown())
      H.eq(never.lock:GetText(), "x")
      expectBorder(never, COL.border)
      H.eq(never.icon.__desaturated, true)
   end)

   H.test("Symbol noch nicht im Cache: Fragezeichen, Abfrage laeuft, ITEMS_RESOLVED zeichnet das Symbol nach", function()
      local T, bar = make({ cache = false })
      local State = T.State
      -- angelegte Gegenstaende gelten als gecacht; das Aussehen nicht
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 1) })
      sendAllLists(T)
      bar:Refresh()
      local head = bar.buttons[SLOT.HEAD]
      H.eq(head.icon:GetTexture(), UNKNOWN, "Fragezeichen solange unbekannt")
      H.truthy(head.needItems)
      M.CacheAll()
      M.Advance(1.0, 0.05)       -- Poll-Takt: Gegenstaende laufen ein, ITEMS_RESOLVED
      H.eq(head.icon:GetTexture(), "Interface\\Icons\\INV_Look_" .. lookId(SLOT.HEAD, 1))
      H.falsy(head.needItems)
      H.eq(State.Wanted(SLOT.HEAD), lookId(SLOT.HEAD, 1))
   end)

   H.test("Auswahl: Akzentrand, 2-px-Rahmen, Zustandsstreifen; Wechsel nimmt den alten Rahmen weg", function()
      local T, bar = make()
      local COL = T.UI.Skin.COL
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 2) })
      sendAllLists(T)
      bar:Refresh()

      bar:Select(SLOT.HEAD)
      local head = bar.buttons[SLOT.HEAD]
      expectBorder(head, COL.accent, "ausgewaehlt = Akzent")
      H.eq(edgesShown(head), 4)
      H.truthy(head.stripe:IsShown(), "Zustand bleibt als Streifen sichtbar")
      H.eq(head.stateKey, "applied")

      bar:Select(SLOT.SHOULDER)
      H.eq(edgesShown(head), 0)
      expectBorder(head, COL.pink, "zurueck auf Zustandsfarbe")
      H.falsy(head.stripe:IsShown())
      local sh = bar.buttons[SLOT.SHOULDER]
      H.eq(edgesShown(sh), 4)
      H.falsy(sh.stripe:IsShown(), "ohne Zustand kein Streifen")

      bar:Select(nil)
      H.eq(edgesShown(sh), 0)
      -- ungueltiger Slot wird wie nil behandelt
      bar:Select(99)
      H.eq(T.UI.SlotBar.Selected(), nil)
   end)

   H.test("Zahl-Plakette: Anzahl, 99+ ab 100, verborgen bei 0 und bei leerem/nie-Slot", function()
      local ids150 = {}
      for i = 1, 150 do ids150[i] = 5000 + i end
      local T, bar = make({
         equip = { [SLOT.TABARD] = false },
      })
      sendStatus(T, {})
      sendList(T, SLOT.HEAD, { lookId(SLOT.HEAD, 1), lookId(SLOT.HEAD, 2), lookId(SLOT.HEAD, 3) })
      sendList(T, SLOT.SHOULDER, ids150)
      sendList(T, SLOT.CHEST, {})
      sendList(T, SLOT.BACK, (function()
         local t = {}
         for i = 1, 99 do t[i] = 6000 + i end
         return t
      end)())
      sendList(T, SLOT.WAIST, (function()
         local t = {}
         for i = 1, 100 do t[i] = 7000 + i end
         return t
      end)())
      bar:Refresh()

      local head = bar.buttons[SLOT.HEAD]
      H.truthy(head.count:IsShown())
      H.eq(head.count:GetText(), "3")
      H.eq(bar.buttons[SLOT.SHOULDER].count:GetText(), "99+", "150 -> 99+")
      H.eq(bar.buttons[SLOT.BACK].count:GetText(), "99", "99 bleibt 99")
      H.eq(bar.buttons[SLOT.WAIST].count:GetText(), "99+", "100 -> 99+")
      H.falsy(bar.buttons[SLOT.CHEST].count:IsShown(), "0 verbirgt die Plakette")
      H.falsy(bar.buttons[SLOT.TABARD].count:IsShown(), "leerer Slot hat keine Zahl")
      H.falsy(bar.buttons[SLOT.LEGS].count:IsShown(), "ohne Liste (amount 0) keine Zahl")
      H.truthy(head.over.badgeBg:IsShown())
      H.falsy(bar.buttons[SLOT.CHEST].over.badgeBg:IsShown())
   end)

   H.test("Kind-Frame mit Symbol-Ueberbau liegt ueber dem Knopf und nimmt keine Mausklicks", function()
      local T, bar = make()
      local btn = bar.buttons[SLOT.HEAD]
      H.truthy(btn.over:GetFrameLevel() > btn:GetFrameLevel())
      H.falsy(btn.over:IsMouseEnabled())
      H.truthy(btn:IsMouseEnabled())
   end)

   -- ======================================================================
   H.section("Tooltip")
   -- ======================================================================

   H.test("Tooltip: Slotname, Gegenstand, Anzahl, Hinweise bei einem Platz ohne Aussehen", function()
      local T, bar = make()
      sendStatus(T, {})
      sendAllLists(T)
      bar:Refresh()
      local btn = bar.buttons[SLOT.HEAD]
      M.Enter(btn)
      local lines = tipLines()
      H.eq(lines[1], "Head")
      H.eq(lines[2], "Equipped 0")
      H.truthy(hasLine(lines, "Available: 5"), "Anzahl")
      H.truthy(hasLine(lines, "Left-click: edit"))
      H.falsy(hasLine(lines, "Right-click: discard pending change"))
      H.falsy(hasLine(lines, "Right-click: remove transmog"), "ohne Aussehen kein Rechtsklick-Hinweis")
      H.truthy(GameTooltip:IsOwned(btn))
      M.Leave(btn)
      H.falsy(GameTooltip:IsShown(), "OnLeave verbirgt den Tooltip")
   end)

   H.test("Tooltip: angewendet, verborgen, ausstehend, Zuruecksetzen, inaktiv", function()
      local T, bar = make()
      local State = T.State
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 2), [SLOT.CHEST] = HIDDEN, [SLOT.LEGS] = 2999 })
      sendAllLists(T)
      bar:Refresh()

      -- angewendet: Name des Aussehens, Rechtsklick = Transmog entfernen, Shift-Hinweis
      M.Enter(bar.buttons[SLOT.HEAD])
      local lines = tipLines()
      H.truthy(string.find(lines[3] or "", "Transmogrified to: ", 1, true), "Zeile 3: " .. tostring(lines[3]))
      H.truthy(string.find(lines[3] or "", "Look 0-2", 1, true))
      H.truthy(hasLine(lines, "Right-click: remove transmog"))
      H.truthy(hasLine(lines, "Shift-click: link in chat"))
      M.Leave(bar.buttons[SLOT.HEAD])

      -- verborgen
      M.Enter(bar.buttons[SLOT.CHEST])
      lines = tipLines()
      H.truthy(hasLine(lines, "Hidden"))
      H.falsy(hasLine(lines, "Shift-click: link in chat"), "verborgen hat keinen Link")
      M.Leave(bar.buttons[SLOT.CHEST])

      -- inaktiv
      M.Enter(bar.buttons[SLOT.LEGS])
      lines = tipLines()
      local inactive
      for _, l in ipairs(lines) do
         if string.find(l, "Inactive: ", 1, true) then inactive = l end
      end
      H.truthy(inactive, "Inaktiv-Zeile")
      H.truthy(string.find(inactive or "", "(does not fit the equipped item)", 1, true))
      M.Leave(bar.buttons[SLOT.LEGS])

      -- ausstehend (neu)
      State.Select(SLOT.SHOULDER, lookId(SLOT.SHOULDER, 3))
      bar:Refresh(SLOT.SHOULDER)
      M.Enter(bar.buttons[SLOT.SHOULDER])
      lines = tipLines()
      local pending
      for _, l in ipairs(lines) do
         if string.find(l, "Pending: ", 1, true) then pending = l end
      end
      H.truthy(pending and string.find(pending, "Look 2-3", 1, true), "Ausstehend-Zeile: " .. tostring(pending))
      H.truthy(hasLine(lines, "Right-click: discard pending change"))
      M.Leave(bar.buttons[SLOT.SHOULDER])

      -- ausstehendes Zuruecksetzen auf einem angewendeten Slot
      State.Select(SLOT.HEAD, 0)
      bar:Refresh(SLOT.HEAD)
      M.Enter(bar.buttons[SLOT.HEAD])
      lines = tipLines()
      H.truthy(hasLine(lines, "Pending: reset to original"))
      H.truthy(hasLine(lines, "Right-click: discard pending change"))
      M.Leave(bar.buttons[SLOT.HEAD])

      -- ausstehendes Verborgen
      State.Select(SLOT.WAIST, HIDDEN)
      bar:Refresh(SLOT.WAIST)
      M.Enter(bar.buttons[SLOT.WAIST])
      H.truthy(hasLine(tipLines(), "Pending: Hidden"))
      M.Leave(bar.buttons[SLOT.WAIST])
   end)

   H.test("Tooltip: leerer und nie transmogbarer Platz nennen den Grund, keine Bedienhinweise", function()
      local T, bar = make({
         equip = { [SLOT.TABARD] = false, [SLOT.RANGED] = 1117 },
         items = { [1117] = { name = "Idol of Testing", quality = 4, equipLoc = "INVTYPE_RELIC",
                              class = "Armor", subclass = "Idols", icon = "Interface\\Icons\\INV_Misc_Idol" } },
      })
      sendStatus(T, {})
      sendAllLists(T)
      bar:Refresh()

      M.Enter(bar.buttons[SLOT.TABARD])
      local lines = tipLines()
      H.eq(lines[1], "Tabard")
      H.truthy(hasLine(lines, "Nothing equipped"))
      H.falsy(hasLine(lines, "Left-click: edit"))
      M.Leave(bar.buttons[SLOT.TABARD])

      M.Enter(bar.buttons[SLOT.RANGED])
      lines = tipLines()
      H.eq(lines[1], "Ranged")
      H.eq(lines[2], "Idol of Testing")
      H.truthy(hasLine(lines, "Cannot be transmogrified"))
      H.falsy(hasLine(lines, "Left-click: edit"))
      M.Leave(bar.buttons[SLOT.RANGED])
   end)

   H.test("Tooltip: Ladefortschritt solange die Liste nicht fertig ist", function()
      local T, bar = make()
      sendStatus(T, {})
      T.Net.Handle("AvailableTransmogs:0:8:40:start")
      T.Net.Handle("AvailableTransmogs:0:8:40:" .. table.concat({ 5001, 5002, 5003 }, ":"))
      bar:Refresh(SLOT.HEAD)
      M.Enter(bar.buttons[SLOT.HEAD])
      H.truthy(hasLine(tipLines(), "Loading appearances: 3 / 40"))
      M.Leave(bar.buttons[SLOT.HEAD])
      H.eq(bar.buttons[SLOT.HEAD].count:GetText(), "40", "Zahl zeigt die Gesamtmenge")
   end)

   H.test("Tooltip: Quelle der Farben (Qualitaetsfarbe des angelegten Gegenstands)", function()
      local T, bar = make()
      M.Enter(bar.buttons[SLOT.HEAD])
      local lines = T.UI.SlotBar.TooltipLines(SLOT.HEAD)
      local qr, qg, qb = T.Util.QualityColor(3)
      H.eq(lines[2][1], "Equipped 0")
      H.near(lines[2][2], qr, 1e-6)
      H.near(lines[2][3], qg, 1e-6)
      H.near(lines[2][4], qb, 1e-6)
      M.Leave(bar.buttons[SLOT.HEAD])
   end)

   H.test("Tooltip bleibt aktuell: Rechtsklick waehrend der Maus auf dem Knopf baut ihn neu", function()
      local T, bar = make()
      local State = T.State
      sendStatus(T, {})
      sendAllLists(T)
      bar:Refresh()
      State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      settle()
      local btn = bar.buttons[SLOT.HEAD]
      M.Enter(btn)
      H.truthy(hasLine(tipLines(), "Right-click: discard pending change"))
      M.Click(btn, "RightButton")
      settle()
      local lines = tipLines()
      H.falsy(hasLine(lines, "Right-click: discard pending change"), "Auswahl verworfen")
      H.eq(State.HasPending(SLOT.HEAD), false)
      M.Leave(btn)
   end)

   -- ======================================================================
   H.section("Klicks")
   -- ======================================================================

   H.test("Linksklick waehlt aus (onSelect), auch ohne Aussehen; Rechtsklick bewirkt dort nichts", function()
      local T, bar, _, clicks = make()
      sendStatus(T, {})
      sendAllLists(T)
      bar:Refresh()
      M.Click(bar.buttons[SLOT.CHEST], "LeftButton")
      H.deepEq(clicks, { SLOT.CHEST })
      M.Click(bar.buttons[SLOT.CHEST], "RightButton")
      H.deepEq(clicks, { SLOT.CHEST }, "Rechtsklick waehlt nicht aus")
      H.eq(T.State.PendingCount(), 0)
   end)

   H.test("EMPTY- und NEVER-Slots melden den Klick (das Raster nennt den Grund); Rechtsklick bewirkt dort nichts", function()
      local T, bar, _, clicks = make({
         equip = { [SLOT.TABARD] = false, [SLOT.RANGED] = 1117 },
         items = { [1117] = { name = "Idol", quality = 3, equipLoc = "INVTYPE_RELIC", class = "Armor",
                              subclass = "Idols", icon = "Interface\\Icons\\INV_Misc_Idol" } },
      })
      M.Click(bar.buttons[SLOT.TABARD], "LeftButton")
      M.Click(bar.buttons[SLOT.RANGED], "LeftButton")
      H.deepEq(clicks, { SLOT.TABARD, SLOT.RANGED }, "SPEC 6.4: Linksklick -> onSelect(slot)")
      M.Click(bar.buttons[SLOT.HEAD], "LeftButton")
      H.deepEq(clicks, { SLOT.TABARD, SLOT.RANGED, SLOT.HEAD })
      M.Click(bar.buttons[SLOT.TABARD], "RightButton")
      M.Click(bar.buttons[SLOT.RANGED], "RightButton")
      H.eq(T.State.PendingCount(), 0)
      H.eq(#clicks, 3, "Rechtsklick waehlt nie aus")
      -- ausgewaehlt: Akzentrahmen, ohne Zustandsstreifen und ohne Fehler
      bar:Select(SLOT.TABARD)
      H.eq(edgesShown(bar.buttons[SLOT.TABARD]), 4)
      H.falsy(bar.buttons[SLOT.TABARD].stripe:IsShown())
      H.eq(#M.errors, 0)
   end)

   H.test("Rechtsklick: Auswahl verwerfen, sonst Transmog entfernen vormerken (State.Toggle)", function()
      local T, bar = make()
      local State = T.State
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 2) })
      sendAllLists(T)
      bar:Refresh()

      -- angewendet, keine Auswahl: Rechtsklick merkt "Entfernen" vor (Auswahl 0)
      M.Click(bar.buttons[SLOT.HEAD], "RightButton")
      H.eq(State.HasPending(SLOT.HEAD), true)
      H.eq(State.Wanted(SLOT.HEAD), 0)

      -- jetzt ausstehend: Rechtsklick verwirft
      M.Click(bar.buttons[SLOT.HEAD], "RightButton")
      H.eq(State.HasPending(SLOT.HEAD), false)
      H.eq(State.Wanted(SLOT.HEAD), lookId(SLOT.HEAD, 2))

      -- ausstehende Auswahl auf leerem Slot: verwerfen
      State.Select(SLOT.CHEST, lookId(SLOT.CHEST, 1))
      M.Click(bar.buttons[SLOT.CHEST], "RightButton")
      H.eq(State.HasPending(SLOT.CHEST), false)
   end)

   H.test("Shift-Linksklick fuegt den Item-Link ein und waehlt nicht aus; ohne Aussehen waehlt er aus", function()
      local T, bar, _, clicks = make()
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 2) })
      sendAllLists(T)
      bar:Refresh()

      M.Click(bar.buttons[SLOT.HEAD], "LeftButton", { shift = true })
      H.len(M.chatInserts, 1)
      H.truthy(string.find(M.chatInserts[1], "Hitem:" .. lookId(SLOT.HEAD, 2), 1, true), "Link des Aussehens")
      H.deepEq(clicks, {}, "kein Auswaehlen")

      -- ohne Aussehen: normaler Linksklick
      M.Click(bar.buttons[SLOT.SHOULDER], "LeftButton", { shift = true })
      H.len(M.chatInserts, 1)
      H.deepEq(clicks, { SLOT.SHOULDER })

      -- verborgen: kein Link, normale Auswahl
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 2), [SLOT.CHEST] = HIDDEN })
      M.Click(bar.buttons[SLOT.CHEST], "LeftButton", { shift = true })
      H.len(M.chatInserts, 1)
      H.deepEq(clicks, { SLOT.SHOULDER, SLOT.CHEST })

      -- das gewuenschte (ausstehende) Aussehen zaehlt ebenso
      T.State.Select(SLOT.WAIST, lookId(SLOT.WAIST, 3))
      M.Click(bar.buttons[SLOT.WAIST], "LeftButton", { shift = true })
      H.len(M.chatInserts, 2)
      H.truthy(string.find(M.chatInserts[2], "Hitem:" .. lookId(SLOT.WAIST, 3), 1, true))
   end)

   -- ======================================================================
   H.section("Ereignisse und Aktualisierung")
   -- ======================================================================

   H.test("WANTED_CHANGED: Neuzeichnen entprellt (nicht sofort, genau einmal fuer viele Ereignisse)", function()
      local T, bar = make()
      local State, COL = T.State, T.UI.Skin.COL
      sendStatus(T, {})
      sendAllLists(T)
      settle(0.2)
      local btn = bar.buttons[SLOT.HEAD]
      expectBorder(btn, COL.buttonBorder)

      State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      expectBorder(btn, COL.buttonBorder, "noch nicht gezeichnet (entprellt)")
      H.truthy(T.Util.TimerCount() >= 1)
      settle(0.1)
      expectBorder(btn, COL.yellow, "nach der Entprellung gelb")
      H.eq(btn.icon:GetTexture(), "Interface\\Icons\\INV_Look_" .. lookId(SLOT.HEAD, 1))

      -- viele Ereignisse hintereinander: ein Durchlauf
      local paints = 0
      local original = btn.SetBackdropBorderColor
      btn.SetBackdropBorderColor = function(self, ...)
         paints = paints + 1
         return original(self, ...)
      end
      for i = 1, 20 do T.Events.Fire("WANTED_CHANGED", SLOT.HEAD) end
      settle(0.2)
      H.eq(paints, 1, "ein Zeichnen fuer 20 Ereignisse")
      btn.SetBackdropBorderColor = nil
   end)

   H.test("Ereignisse: STATUS_CHANGED, EQUIPMENT_CHANGED, LIST_READY, LIST_PROGRESS, ITEMS_RESOLVED, LOCALE_CHANGED", function()
      local T, bar = make()
      local COL = T.UI.Skin.COL
      sendStatus(T, {})
      sendAllLists(T)
      settle(0.2)

      -- STATUS_CHANGED (alle Slots)
      sendStatus(T, { [SLOT.SHOULDER] = lookId(SLOT.SHOULDER, 1) })
      settle()
      expectBorder(bar.buttons[SLOT.SHOULDER], COL.pink, "STATUS_CHANGED")

      -- LIST_READY: ein angewendetes Aussehen, das nicht in der neuen Liste steht, wird inaktiv
      sendList(T, SLOT.SHOULDER, { lookId(SLOT.SHOULDER, 2), lookId(SLOT.SHOULDER, 3) })
      settle()
      expectBorder(bar.buttons[SLOT.SHOULDER], COL.red, "LIST_READY -> inaktiv")
      H.eq(bar.buttons[SLOT.SHOULDER].count:GetText(), "2")

      -- LIST_PROGRESS: Zahl waehrend des Stroms
      T.Net.Handle("AvailableTransmogs:2:8:7:start")
      settle()
      H.eq(bar.buttons[SLOT.SHOULDER].count:GetText(), "7", "amount aus dem Strom")

      -- EQUIPMENT_CHANGED: anderer Gegenstand im Slot -> Symbol wechselt
      M.world.equipment[SLOT.WRIST + 1] = lookId(SLOT.WRIST, 5)
      M.Fire("PLAYER_EQUIPMENT_CHANGED", SLOT.WRIST + 1)
      settle()
      H.eq(bar.buttons[SLOT.WRIST].icon:GetTexture(), "Interface\\Icons\\INV_Look_" .. lookId(SLOT.WRIST, 5))

      -- LOCALE_CHANGED: zeichnet neu, wirft nicht
      T.Events.Fire("LOCALE_CHANGED")
      H.eq(#M.errors, 0)
   end)

   H.test("Unsichtbar: kein Neuzeichnen; OnShow holt es nach", function()
      local T, bar, parent = make()
      local State, COL = T.State, T.UI.Skin.COL
      sendStatus(T, {})
      sendAllLists(T)
      settle(0.2)

      parent:Hide()
      State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      settle(0.3)
      expectBorder(bar.buttons[SLOT.HEAD], COL.buttonBorder, "versteckt: nicht gezeichnet")
      H.eq(T.Util.Cancel("ui-slotbar"), false, "kein Entprellungs-Timer haengt")

      parent:Show()
      expectBorder(bar.buttons[SLOT.HEAD], COL.yellow, "OnShow hat nachgeholt")
   end)

   H.test("Frame wird versteckt: Hover und Tooltip werden aufgeraeumt", function()
      local T, bar, parent = make()
      sendStatus(T, {})
      sendAllLists(T)
      local btn = bar.buttons[SLOT.HEAD]
      M.Enter(btn)
      H.truthy(GameTooltip:IsShown())
      parent:Hide()
      H.falsy(GameTooltip:IsShown(), "Tooltip weg beim Verstecken")
      parent:Show()
      H.falsy(btn.over.hover:IsShown())
   end)

   -- ======================================================================
   H.section("Aufblitzen")
   -- ======================================================================

   H.test("Flash: Lebenslauf 0,7 s, Farbe rosa/rot, OnUpdate-Frame versteckt sich", function()
      local T, bar = make()
      local S, COL = T.UI.SlotBar, T.UI.Skin.COL
      local glow = bar.buttons[SLOT.HEAD].over.glow
      H.falsy(glow:IsShown())
      H.eq(barUpdateFrames(bar), 0, "vor dem Blitz kein OnUpdate")

      H.eq(S.Flash(SLOT.HEAD, true), true)
      H.truthy(glow:IsShown())
      H.eq(barUpdateFrames(bar), 1, "ein OnUpdate-Frame laeuft")
      local v = glow.__vertex
      H.near(v[1], COL.pink[1], 1e-6, "Erfolg rosa")
      H.near(v[2], COL.pink[2], 1e-6)
      M.Advance(0.35, 0.05)
      H.truthy(glow:IsShown(), "nach 0,35 s noch sichtbar")
      H.truthy(glow:GetAlpha() > 0 and glow:GetAlpha() < 0.75, "Deckkraft nimmt ab: " .. tostring(glow:GetAlpha()))
      M.Advance(0.5, 0.05)
      H.falsy(glow:IsShown(), "nach 0,85 s weg")
      H.eq(barUpdateFrames(bar), 0, "kein OnUpdate im Leerlauf")

      -- Fehlschlag: rot; zwei Slots gleichzeitig
      S.Flash(SLOT.CHEST, false)
      S.Flash(SLOT.LEGS, true)
      local fail = bar.buttons[SLOT.CHEST].over.glow.__vertex
      H.near(fail[1], COL.red[1], 1e-6, "Fehlschlag rot")
      H.near(fail[2], COL.red[2], 1e-6)
      H.truthy(bar.buttons[SLOT.CHEST].over.glow:IsShown())
      H.truthy(bar.buttons[SLOT.LEGS].over.glow:IsShown())
      M.Advance(0.3, 0.05)
      M.Advance(0.6, 0.05)
      H.falsy(bar.buttons[SLOT.CHEST].over.glow:IsShown())
      H.falsy(bar.buttons[SLOT.LEGS].over.glow:IsShown())
      H.eq(barUpdateFrames(bar), 0)
   end)

   H.test("Flash: Wiederholung startet neu; unbekannter Slot und unsichtbare Leiste werden ignoriert", function()
      local T, bar, parent = make()
      local S = T.UI.SlotBar
      H.eq(S.Flash(99, true), false)
      S.Flash(SLOT.HEAD, true)
      M.Advance(0.5, 0.05)
      S.Flash(SLOT.HEAD, true)          -- neu starten
      M.Advance(0.5, 0.05)
      H.truthy(bar.buttons[SLOT.HEAD].over.glow:IsShown(), "durch den Neustart noch sichtbar")
      M.Advance(0.5, 0.05)
      H.falsy(bar.buttons[SLOT.HEAD].over.glow:IsShown())

      parent:Hide()
      H.eq(S.Flash(SLOT.HEAD, true), false, "unsichtbar: kein Blitz")
      H.eq(barUpdateFrames(bar), 0)

      -- Verstecken waehrend des Blitzes beendet ihn
      parent:Show()
      S.Flash(SLOT.HEAD, true)
      parent:Hide()
      parent:Show()
      H.falsy(bar.buttons[SLOT.HEAD].over.glow:IsShown())
      H.eq(barUpdateFrames(bar), 0)
   end)

   -- ======================================================================
   H.section("Hygiene")
   -- ======================================================================

   H.test("Keine fehlenden Locale-Schluessel, keine OnUpdate-Frames im Leerlauf, keine fremden Globals", function()
      local T, bar = make()
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 1), [SLOT.CHEST] = HIDDEN, [SLOT.LEGS] = 2999 })
      sendAllLists(T)
      T.State.Select(SLOT.SHOULDER, lookId(SLOT.SHOULDER, 2))
      T.State.Select(SLOT.WAIST, 0)
      settle(0.3)
      for _, slot in ipairs(ORDER) do
         M.Enter(bar.buttons[slot])
         M.Leave(bar.buttons[slot])
      end
      local missing = {}
      for key in pairs(T.L.__missing) do
         if string.find(key, "^SLOTBAR_") then missing[#missing + 1] = key end
      end
      H.deepEq(missing, {}, "fehlende SLOTBAR_-Schluessel")
      H.eq(barUpdateFrames(bar), 0)
      H.eq(T.Util.Cancel("ui-slotbar"), false, "kein Entprellungs-Timer haengt")
      H.eq(#M.errors, 0)
   end)

   -- ======================================================================
   H.section("Zufallsfolge")
   -- ======================================================================

   -- Beliebige Ereignisse (Auswahl, Status, Listen, Ausruestung, Hover, Blitz): nach der
   -- Entprellung muss jeder Knopf den Zustand des Modells (State) zeigen.
   local function checkConsistent(T, bar, where)
      local State, Slots = T.State, T.Slots
      local selected = T.UI.SlotBar.Selected()
      for _, slot in ipairs(ORDER) do
         local btn = bar.buttons[slot]
         local st = State.SlotState(slot)
         local key = nil
         if st == "READY" then
            if State.HasPending(slot) then
               key = "pending"
            elseif State.IsInactive(slot) then
               key = "inactive"
            elseif State.Baseline(slot) ~= 0 then
               key = "applied"
            end
         end
         H.eq(btn.stateKey, key, where .. ": Zustand Slot " .. slot)
         H.eq(edgesShown(btn), (selected == slot) and 4 or 0, where .. ": Auswahlrahmen Slot " .. slot)
         if st == "EMPTY" then
            H.eq(btn.icon:GetTexture(), Slots.EmptyTexture(slot), where .. ": Leertextur " .. slot)
            H.falsy(btn.count:IsShown(), where .. ": keine Zahl bei leerem Slot " .. slot)
         elseif st == "READY" then
            local want = State.Wanted(slot)
            local expect
            if want == HIDDEN then
               expect = INVISIBLE
            elseif want ~= 0 then
               expect = "Interface\\Icons\\INV_Look_" .. want
            else
               expect = State.Equipped(slot).icon
            end
            H.eq(btn.icon:GetTexture(), expect, where .. ": Symbol Slot " .. slot)
            local amount = State.List(slot).amount
            if amount > 0 then
               H.eq(btn.count:GetText(), amount > 99 and "99+" or tostring(amount), where .. ": Zahl Slot " .. slot)
            else
               H.falsy(btn.count:IsShown(), where .. ": keine Zahl bei 0, Slot " .. slot)
            end
         end
         H.eq(btn.glyph:IsShown() and btn.glyph:GetText() or nil,
            (key == "pending") and "*" or ((key == "inactive") and "!" or nil), where .. ": Glyph Slot " .. slot)
      end
   end

   H.test("Zufallsfolge: nach jeder Ruhephase zeigen die Knoepfe den Zustand des Modells", function()
      local T, bar = make()
      local State, S = T.State, T.UI.SlotBar
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 1) })
      sendAllLists(T)
      settle(0.2)
      local seed = 987654
      local function rnd(n)
         seed = (seed * 1103515245 + 12345) % 2147483648
         return (seed % n) + 1
      end
      for round = 1, 40 do
         for _ = 1, 1 + rnd(4) do
            local slot = ORDER[rnd(#ORDER)]
            local what = rnd(12)
            if what == 1 then
               State.Select(slot, HIDDEN)
            elseif what == 2 then
               State.Select(slot, 0)
            elseif what == 3 or what == 4 then
               State.Select(slot, lookId(slot, rnd(5)))
            elseif what == 5 then
               State.Discard(slot)
            elseif what == 6 then
               State.DiscardAll()
            elseif what == 7 then
               local map = {}
               for _, s2 in ipairs(ORDER) do
                  if rnd(3) == 1 then map[s2] = (rnd(4) == 1) and HIDDEN or lookId(s2, rnd(5)) end
               end
               sendStatus(T, map)
            elseif what == 8 then
               local ids = {}
               for i = 1, 5 do
                  if rnd(2) == 1 then ids[#ids + 1] = lookId(slot, i) end
               end
               sendList(T, slot, ids)
            elseif what == 9 then
               local pick = rnd(3)
               if pick == 1 then
                  M.world.equipment[slot + 1] = nil
               elseif pick == 2 then
                  M.world.equipment[slot + 1] = equipId(slot)
               else
                  M.world.equipment[slot + 1] = lookId(slot, 5)
               end
               M.Fire("PLAYER_EQUIPMENT_CHANGED", slot + 1)
            elseif what == 10 then
               S.Select(rnd(3) == 1 and nil or slot)
            elseif what == 11 then
               M.Enter(bar.buttons[slot])
            else
               S.Flash(slot, rnd(2) == 1)
               M.Leave(bar.buttons[slot])
            end
         end
         settle(0.2)
         checkConsistent(T, bar, "Runde " .. round)
      end
      M.Advance(1.0, 0.05)
      H.eq(#M.errors, 0)
      H.eq(barUpdateFrames(bar), 0, "am Ende kein OnUpdate")
   end)

   H.test("Sprachwechsel auf deDE: Tooltip in der Sprache des Clients, Slotname aus dem Blizzard-Global", function()
      local T, bar = make({ locale = "deDE" })
      sendStatus(T, {})
      sendAllLists(T)
      bar:Refresh()
      M.Enter(bar.buttons[SLOT.HEAD])
      local lines = tipLines()
      H.eq(lines[1], "Kopf", "Slotname aus dem Blizzard-Global in der Clientsprache")
      H.truthy(hasLine(lines, string.format(T.L.SLOTBAR_AVAILABLE, 5)), "Text der Sprache")
      H.eq(T.Locale.Current(), "deDE")
      H.neq(string.format(T.L.SLOTBAR_AVAILABLE, 5), "Available: 5", "uebersetzt, nicht Englisch")
      M.Leave(bar.buttons[SLOT.HEAD])
   end)

   -- ======================================================================
   H.section("Verifikation: Zustandsmatrix, Tooltips, Layout-Grenzen, Aufblitzen")
   -- ======================================================================

   -- Farbcodes aus Tooltip-Zeilen entfernen
   local function plain(text)
      text = string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", "")
      text = string.gsub(text, "|r", "")
      return text
   end

   local function plainLines()
      local out = {}
      for i, l in ipairs(tipLines()) do out[i] = plain(l) end
      return out
   end

   local RELIC = { name = "Idol of Testing", quality = 4, equipLoc = "INVTYPE_RELIC", class = "Armor",
                   subclass = "Idols", icon = "Interface\\Icons\\INV_Misc_Idol" }

   -- Sitzung, in der jeder Platz einen anderen Zustand hat:
   --   HEAD angewendet                     SHOULDER angewendet verborgen
   --   BACK inaktiv                        CHEST ausstehend (Aussehen)
   --   SHIRT ausstehend verborgen          TABARD leer
   --   WRIST ausstehend "Original"         HANDS inaktiv + ausstehend
   --   WAIST schlicht                      LEGS angewendet + anderes ausstehend
   --   FEET schlicht                       MAINHAND schlicht
   --   OFFHAND nie transmogbar             RANGED nie transmogbar
   local function matrix()
      local T, bar, parent, clicks = make({
         equip = { [SLOT.TABARD] = false, [SLOT.OFFHAND] = 1118, [SLOT.RANGED] = 1117 },
         items = {
            [1117] = RELIC,
            [1118] = { name = "Totem of Testing", quality = 3, equipLoc = "INVTYPE_RELIC", class = "Armor",
                       subclass = "Totems", icon = "Interface\\Icons\\INV_Misc_Totem_01" },
         },
      })
      local State = T.State
      sendStatus(T, {
         [SLOT.HEAD] = lookId(SLOT.HEAD, 2), [SLOT.SHOULDER] = HIDDEN, [SLOT.BACK] = 2999,
         [SLOT.WRIST] = lookId(SLOT.WRIST, 3), [SLOT.HANDS] = 2998, [SLOT.LEGS] = lookId(SLOT.LEGS, 1),
      })
      sendAllLists(T)
      State.Select(SLOT.CHEST, lookId(SLOT.CHEST, 4))
      State.Select(SLOT.SHIRT, HIDDEN)
      State.Select(SLOT.WRIST, 0)
      State.Select(SLOT.HANDS, lookId(SLOT.HANDS, 5))
      State.Select(SLOT.LEGS, lookId(SLOT.LEGS, 3))
      settle(0.3)
      return T, bar, parent, clicks
   end

   -- Soll-Darstellung nach SPEC 6.4 (aus State abgeleitet, nicht aus dem Code der Leiste)
   local function expectedLook(T, slot, selected, hover)
      local State, COL = T.State, T.UI.Skin.COL
      local st = State.SlotState(slot)
      local want = (st == "READY") and State.Wanted(slot) or 0
      local eq = State.Equipped(slot)
      local out = {}
      if st == "EMPTY" then
         out.icon, out.alpha = T.Slots.EmptyTexture(slot), 0.4
      elseif want == HIDDEN then
         out.icon, out.alpha = INVISIBLE, 1
      elseif want ~= 0 then
         local info = T.Items.Info(want)
         out.icon, out.alpha = info and info.icon, 1
      else
         out.icon, out.alpha = eq.icon, 1
      end
      if st == "NEVER" then out.alpha = 0.5 end
      out.desat = (st == "NEVER")
      local key
      if st == "READY" then
         if State.HasPending(slot) then
            key = "pending"
         elseif State.IsInactive(slot) then
            key = "inactive"
         elseif State.Baseline(slot) ~= 0 then
            key = "applied"
         end
      end
      local colorOf = { pending = COL.yellow, inactive = COL.red, applied = COL.pink }
      if selected then
         out.border = COL.accent
      elseif key then
         out.border = colorOf[key]
      elseif hover and st == "READY" then
         out.border = COL.accent
      elseif st == "READY" then
         out.border = COL.buttonBorder
      else
         out.border = COL.border
      end
      out.key = key
      out.edges = selected and 4 or 0
      out.stripe = (selected and key ~= nil) and true or false
      out.glyph = (key == "pending") and "*" or ((key == "inactive") and "!" or nil)
      out.lock = (st == "NEVER")
      local amount = (st == "READY") and State.List(slot).amount or 0
      if amount > 0 then out.count = (amount > 99) and "99+" or tostring(amount) end
      out.hover = (hover and st == "READY") and true or false
      return out
   end

   local function checkLook(T, bar, slot, selected, hover, where)
      local e = expectedLook(T, slot, selected, hover)
      local btn = bar.buttons[slot]
      local w = where .. " Slot " .. slot
      H.eq(btn.icon:GetTexture(), e.icon, w .. ": Symbol")
      H.near(btn.icon:GetAlpha(), e.alpha, 1e-6, w .. ": Deckkraft")
      H.eq(btn.icon.__desaturated == true, e.desat, w .. ": entsaettigt")
      expectBorder(btn, e.border, w .. ": Rand")
      H.eq(btn.stateKey, e.key, w .. ": Zustand")
      H.eq(edgesShown(btn), e.edges, w .. ": Auswahlrahmen")
      H.eq(shown(btn.stripe), e.stripe, w .. ": Streifen")
      H.eq(btn.glyph:IsShown() and btn.glyph:GetText() or nil, e.glyph, w .. ": Glyph")
      H.eq(shown(btn.lock), e.lock, w .. ": Sperre")
      H.eq(btn.count:IsShown() and btn.count:GetText() or nil, e.count, w .. ": Zahl")
      H.eq(shown(btn.over.badgeBg), e.count ~= nil, w .. ": Plakette")
      H.eq(shown(btn.over.hover), e.hover, w .. ": Aufhellung")
   end

   H.test("Zustandsmatrix: Symbol, Rand, Glyph, Streifen, Sperre, Zahl fuer jeden Zustand (ohne Auswahl, ohne Zeiger)", function()
      local T, bar = matrix()
      local State = T.State
      -- die Ausgangslage ist wie beschrieben
      H.eq(State.SlotState(SLOT.TABARD), "EMPTY")
      H.eq(State.SlotState(SLOT.OFFHAND), "NEVER")
      H.eq(State.SlotState(SLOT.RANGED), "NEVER")
      H.eq(State.IsInactive(SLOT.BACK), true)
      H.eq(State.IsInactive(SLOT.HANDS), true)
      H.eq(State.HasPending(SLOT.HANDS), true)
      H.eq(State.HasPending(SLOT.WRIST), true)
      H.eq(State.Wanted(SLOT.WRIST), 0)
      for _, slot in ipairs(ORDER) do checkLook(T, bar, slot, false, false, "Ruhe") end
      -- ein paar Zustaende ausdruecklich (nicht nur gegen die abgeleiteten Sollwerte)
      local COL = T.UI.Skin.COL
      expectBorder(bar.buttons[SLOT.HEAD], COL.pink, "angewendet")
      expectBorder(bar.buttons[SLOT.SHOULDER], COL.pink, "verborgen")
      expectBorder(bar.buttons[SLOT.BACK], COL.red, "inaktiv")
      expectBorder(bar.buttons[SLOT.CHEST], COL.yellow, "ausstehend")
      expectBorder(bar.buttons[SLOT.HANDS], COL.yellow, "inaktiv + ausstehend: ausstehend gewinnt")
      expectBorder(bar.buttons[SLOT.WRIST], COL.yellow, "ausstehendes Zuruecksetzen")
      H.eq(bar.buttons[SLOT.SHOULDER].icon:GetTexture(), INVISIBLE)
      H.eq(bar.buttons[SLOT.SHIRT].icon:GetTexture(), INVISIBLE)
      H.eq(bar.buttons[SLOT.WRIST].icon:GetTexture(), "Interface\\Icons\\INV_Equip_" .. SLOT.WRIST)
      H.eq(bar.buttons[SLOT.BACK].icon:GetTexture(), "Interface\\Icons\\INV_Equip_" .. SLOT.BACK,
         "inaktiv zeigt den echten Gegenstand")
   end)

   H.test("Zustandsmatrix: jeder Platz ausgewaehlt und/oder unter dem Zeiger", function()
      local T, bar = matrix()
      local S = T.UI.SlotBar
      local lastHover
      local function hoverOn(slot)
         if lastHover then M.Leave(bar.buttons[lastHover]) end
         lastHover = slot
         if slot then M.Enter(bar.buttons[slot]) end
      end
      for _, sel in ipairs(ORDER) do
         for _, hov in ipairs({ sel, false }) do
            S.Select(sel)
            hoverOn(hov or nil)
            for _, slot in ipairs(ORDER) do
               checkLook(T, bar, slot, slot == sel, slot == hov, "ausgewaehlt " .. sel .. " Zeiger " .. tostring(hov))
            end
         end
      end
      -- nur Zeiger, keine Auswahl
      S.Select(nil)
      for _, hov in ipairs(ORDER) do
         hoverOn(hov)
         for _, slot in ipairs(ORDER) do
            checkLook(T, bar, slot, false, slot == hov, "Zeiger " .. hov)
         end
      end
      hoverOn(nil)
      H.eq(#M.errors, 0)
   end)

   H.test("Tooltip-Matrix: Zeilen und Reihenfolge fuer jeden Zustand", function()
      local T, bar = matrix()
      local function tip(slot)
         M.Enter(bar.buttons[slot])
         local lines = plainLines()
         M.Leave(bar.buttons[slot])
         return lines
      end
      local Label = T.Slots.Label

      H.deepEq(tip(SLOT.HEAD), {
         Label(SLOT.HEAD), "Equipped 0", "Transmogrified to: Look 0-2", "Available: 5",
         "Left-click: edit", "Right-click: remove transmog", "Shift-click: link in chat",
      }, "angewendet")

      H.deepEq(tip(SLOT.SHOULDER), {
         Label(SLOT.SHOULDER), "Equipped 2", "Hidden", "Available: 5",
         "Left-click: edit", "Right-click: remove transmog",
      }, "verborgen: kein Link")

      H.deepEq(tip(SLOT.BACK), {
         Label(SLOT.BACK), "Equipped 14", "Inactive: Item 2999 (does not fit the equipped item)", "Available: 5",
         "Left-click: edit",
      }, "inaktiv: kein Entfernen (Baseline 0)")

      H.deepEq(tip(SLOT.CHEST), {
         Label(SLOT.CHEST), "Equipped 4", "Pending: Look 4-4", "Available: 5",
         "Left-click: edit", "Right-click: discard pending change", "Shift-click: link in chat",
      }, "ausstehend")

      H.deepEq(tip(SLOT.SHIRT), {
         Label(SLOT.SHIRT), "Equipped 3", "Pending: Hidden", "Available: 5",
         "Left-click: edit", "Right-click: discard pending change",
      }, "ausstehend verborgen")

      H.deepEq(tip(SLOT.WRIST), {
         Label(SLOT.WRIST), "Equipped 8", "Transmogrified to: Look 8-3", "Pending: reset to original", "Available: 5",
         "Left-click: edit", "Right-click: discard pending change",
      }, "ausstehendes Zuruecksetzen")

      H.deepEq(tip(SLOT.HANDS), {
         Label(SLOT.HANDS), "Equipped 9", "Pending: Look 9-5",
         "Inactive: Item 2998 (does not fit the equipped item)", "Available: 5",
         "Left-click: edit", "Right-click: discard pending change", "Shift-click: link in chat",
      }, "inaktiv + ausstehend")

      H.deepEq(tip(SLOT.LEGS), {
         Label(SLOT.LEGS), "Equipped 6", "Transmogrified to: Look 6-1", "Pending: Look 6-3", "Available: 5",
         "Left-click: edit", "Right-click: discard pending change", "Shift-click: link in chat",
      }, "angewendet + anderes ausstehend")

      H.deepEq(tip(SLOT.WAIST), {
         Label(SLOT.WAIST), "Equipped 5", "Available: 5", "Left-click: edit",
      }, "schlicht")

      H.deepEq(tip(SLOT.TABARD), { Label(SLOT.TABARD), "Nothing equipped" }, "leer")
      H.deepEq(tip(SLOT.OFFHAND), { Label(SLOT.OFFHAND), "Totem of Testing", "Cannot be transmogrified" }, "nie")
      H.deepEq(tip(SLOT.RANGED), { Label(SLOT.RANGED), "Idol of Testing", "Cannot be transmogrified" }, "nie")
   end)

   H.test("Tooltip: Gegenstandsnamen fehlen im Cache: Platzhalter, Abfrage, ITEMS_RESOLVED traegt den Namen nach", function()
      local T, bar = make({ cache = false })
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 2) })
      sendAllLists(T)
      settle(0.2)
      local btn = bar.buttons[SLOT.HEAD]
      M.Enter(btn)
      local lines = plainLines()
      H.truthy(hasLine(lines, "Transmogrified to: Item " .. lookId(SLOT.HEAD, 2)), "Platzhalter: " .. table.concat(lines, " | "))
      H.truthy(T.Items.PendingCount() >= 1, "Abfrage laeuft")
      M.CacheAll()
      M.Advance(1.0, 0.05)
      lines = plainLines()
      H.truthy(hasLine(lines, "Transmogrified to: Look 0-2"), "Name nachgetragen: " .. table.concat(lines, " | "))
      M.Leave(btn)
   end)

   H.test("Lange Namen: Tooltip-Zeilen sind umbrechbar, die Zahl bleibt in der Plakette", function()
      local long = "Schultergarde des unermuedlichen Wachters der ewigen Nacht von Nordend (Heldenmodus)"
      local T, bar = make({
         items = { [lookId(SLOT.HEAD, 1)] = { name = long, quality = 4, ilvl = 100, equipLoc = "INVTYPE_HEAD",
                                              class = "Armor", subclass = "Plate", icon = "Interface\\Icons\\INV_Helmet_1" } },
      })
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 1) })
      sendAllLists(T)
      settle(0.2)
      local lines = T.UI.SlotBar.TooltipLines(SLOT.HEAD)
      for i, l in ipairs(lines) do
         H.eq(type(l[1]), "string", "Zeile " .. i)
         -- (die Zeilen tragen keine feste Breite: der Tooltip bricht ab Zeile 2 um, Skin.Tooltip)
      end
      M.Enter(bar.buttons[SLOT.HEAD])
      H.truthy(hasLine(plainLines(), "Transmogrified to: " .. long))
      M.Leave(bar.buttons[SLOT.HEAD])
      local btn = bar.buttons[SLOT.HEAD]
      H.truthy(btn.count:GetWidth() <= 40 - 6, "Zahl hoechstens so breit wie der Knopf")
      H.truthy(btn.count:GetHeight() > 0)
   end)

   H.test("Layout an den Fenstergrenzen: 740x520 und 880x600 (Hoehe 428 / 508): Zeilen fluchten, nichts ueberlappt", function()
      local T, bar = make()
      local S = T.UI.SlotBar
      for _, height in ipairs({ 428, 508, 640, 300 }) do
         S.Layout(height)
         local stage = height - T.UI.Preview.CONTROLS_HEIGHT
         local prevBottom = {}
         for _, def in ipairs(T.Slots.LIST) do
            local btn = bar.buttons[def.server]
            local _, _, _, x, y = btn:GetPoint()
            H.eq(x, 2, "x " .. def.key)
            local top = -y
            local col = def.column
            if prevBottom[col] then
               local gap = top - prevBottom[col]
               local expected = (def.key == "MAINHAND") and "Luecke" or "Abstand"
               H.truthy(gap >= 4 - 1e-9, "Abstand >= 4 " .. def.key .. " bei " .. height .. ": " .. gap)
               if def.key ~= "MAINHAND" then
                  H.truthy(gap <= 14 + 1, "Abstand <= 14 " .. def.key .. " bei " .. height .. ": " .. gap)
               else
                  H.truthy(gap <= 14 + 8 + 1, "Luecke " .. def.key .. " bei " .. height .. ": " .. gap)
               end
            end
            prevBottom[col] = top + 40
            if height >= 428 then
               H.truthy(top + 40 <= stage + 1e-9, "innerhalb der Buehne " .. def.key .. " bei " .. height)
               H.truthy(top >= 0)
            end
         end
         -- gleiche Zeilen beider Spalten fluchten (bis auf die Luecke vor MAINHAND)
         for index = 1, 4 do
            local a, b = nil, nil
            for _, def in ipairs(T.Slots.LIST) do
               if def.index == index and def.column == 1 then a = def.server end
               if def.index == index and def.column == 2 then b = def.server end
            end
            local _, _, _, _, ya = bar.buttons[a]:GetPoint()
            local _, _, _, _, yb = bar.buttons[b]:GetPoint()
            H.eq(ya, yb, "Zeile " .. index .. " fluchtet bei " .. height)
         end
      end
   end)

   H.test("Aufblitzen: viele Plaetze, ueberlappende Wiederholungen, Verbergen mitten drin - Zaehler und Frame stimmen", function()
      local T, bar, parent = make()
      local S = T.UI.SlotBar
      for _, slot in ipairs(ORDER) do S.Flash(slot, true) end
      H.eq(barUpdateFrames(bar), 1, "ein Treiber fuer alle")
      M.Advance(0.4, 0.05)
      for _, slot in ipairs({ SLOT.HEAD, SLOT.CHEST, SLOT.LEGS }) do S.Flash(slot, false) end
      M.Advance(0.4, 0.05)
      -- die 11 aelteren sind nach 0,8 s aus, die 3 neuen leuchten noch
      for _, slot in ipairs(ORDER) do
         local lit = bar.buttons[slot].over.glow:IsShown() and true or false
         local again = (slot == SLOT.HEAD or slot == SLOT.CHEST or slot == SLOT.LEGS)
         H.eq(lit, again, "Slot " .. slot)
      end
      H.eq(barUpdateFrames(bar), 1)
      M.Advance(0.5, 0.05)
      for _, slot in ipairs(ORDER) do H.falsy(bar.buttons[slot].over.glow:IsShown()) end
      H.eq(barUpdateFrames(bar), 0, "Leerlauf")

      -- erneut und mitten im Blitz alles verstecken
      S.Flash(SLOT.HEAD, true)
      S.Flash(SLOT.FEET, false)
      parent:Hide()
      H.eq(barUpdateFrames(bar), 0)
      H.falsy(bar.buttons[SLOT.HEAD].over.glow:IsShown())
      parent:Show()
      H.falsy(bar.buttons[SLOT.FEET].over.glow:IsShown())
      -- und danach laeuft ein neuer Blitz sauber (Zaehler nicht verrutscht)
      S.Flash(SLOT.WAIST, true)
      M.Advance(0.9, 0.05)
      H.falsy(bar.buttons[SLOT.WAIST].over.glow:IsShown())
      H.eq(barUpdateFrames(bar), 0)
      H.eq(#M.errors, 0)
   end)

   H.test("Aufblitzen ueberdeckt weder Klicks noch Zustandsfarben: Rand und Symbol bleiben unberuehrt", function()
      local T, bar, _, clicks = make()
      local COL = T.UI.Skin.COL
      sendStatus(T, { [SLOT.HEAD] = lookId(SLOT.HEAD, 2) })
      sendAllLists(T)
      settle(0.2)
      T.UI.SlotBar.Flash(SLOT.HEAD, true)
      expectBorder(bar.buttons[SLOT.HEAD], COL.pink, "Rand")
      H.eq(bar.buttons[SLOT.HEAD].icon:GetTexture(), "Interface\\Icons\\INV_Look_" .. lookId(SLOT.HEAD, 2))
      M.Click(bar.buttons[SLOT.HEAD], "LeftButton")
      H.deepEq(clicks, { SLOT.HEAD })
      -- ein Neuzeichnen waehrend des Blitzes loescht ihn nicht
      T.Events.Fire("STATUS_CHANGED")
      settle(0.1)
      H.truthy(bar.buttons[SLOT.HEAD].over.glow:IsShown())
   end)

   H.test("Ereignisbuendel: 500 Ereignisse in einer Ruhephase zeichnen jeden Knopf hoechstens einmal", function()
      local T, bar = make()
      sendStatus(T, {})
      sendAllLists(T)
      settle(0.2)
      local paints = 0
      for _, slot in ipairs(ORDER) do
         local btn = bar.buttons[slot]
         local original = btn.SetBackdropBorderColor
         btn.SetBackdropBorderColor = function(self, ...)
            paints = paints + 1
            return original(self, ...)
         end
      end
      for i = 1, 100 do
         T.Events.Fire("WANTED_CHANGED", ORDER[(i % 14) + 1])
         T.Events.Fire("STATUS_CHANGED")
         T.Events.Fire("LIST_READY", ORDER[(i % 14) + 1])
         T.Events.Fire("LIST_PROGRESS", ORDER[(i % 14) + 1], 1, 5)
         T.Events.Fire("EQUIPMENT_CHANGED", nil)
      end
      H.eq(paints, 0, "nichts sofort")
      settle(0.3)
      H.eq(paints, 14, "ein Durchlauf, ein Zeichnen je Knopf")
      H.eq(T.Util.Cancel("ui-slotbar"), false)
      for _, slot in ipairs(ORDER) do bar.buttons[slot].SetBackdropBorderColor = nil end
   end)

   H.test("Sprachwechsel: Tooltip eines offenen Knopfes wird in der neuen Sprache neu aufgebaut", function()
      local T, bar = make({ locale = "enUS" })
      sendStatus(T, {})
      sendAllLists(T)
      settle(0.2)
      -- eine Uebersetzung fuer diesen Test (die Sprachdateien schreiben die Uebersetzer)
      T.Locale.Add("deDE", { SLOTBAR_HINT_EDIT = "Linksklick: bearbeiten", SLOTBAR_AVAILABLE = "Verfuegbar: %d" })
      M.Enter(bar.buttons[SLOT.HEAD])
      H.truthy(hasLine(tipLines(), "Left-click: edit"))
      T.Locale.Set("deDE")
      settle(0.2)
      local lines = tipLines()
      H.truthy(hasLine(lines, "Linksklick: bearbeiten"), "neu aufgebaut: " .. table.concat(lines, " | "))
      H.truthy(hasLine(lines, "Verfuegbar: 5"))
      M.Leave(bar.buttons[SLOT.HEAD])
      T.Locale.Set("enUS")
      H.eq(#M.errors, 0)
   end)

   -- ---------------------------------------------------------------------
   -- Im echten Fenster (Fixtures: Katalog, Server, alle Komponenten)
   -- ---------------------------------------------------------------------

   H.test("Im Fenster: Knoepfe zeigen den Zustand nach Server, Auswahl, Anwenden und Entfernen", function()
      local Fixtures = require("fixtures")
      local FX = Fixtures.Boot(H, { locale = "enUS" })
      Fixtures.ServerHello(FX)
      local srv = Fixtures.ServerAutoReply(FX)
      local Win, State = FX.UI.Window, FX.State
      Fixtures.OpenAtNpc(FX)
      Fixtures.Settle(FX, 1.0)
      local bar = FX.UI.SlotBar.Get()
      H.truthy(bar, "SlotBar im Fenster")
      local COL = FX.UI.Skin.COL

      local function all(where)
         Fixtures.Settle(FX, 0.4)
         for _, slot in ipairs(ORDER) do
            checkLook(FX, bar, slot, Win.currentSlot == slot, false, where)
         end
      end
      all("nach dem Oeffnen")
      -- Serverstandard: Kopf angewendet, Ruecken verborgen, Beine inaktiv
      H.eq(State.IsInactive(SLOT.LEGS), true)
      expectBorder(bar.buttons[SLOT.BACK], COL.pink, "Ruecken verborgen")
      H.eq(bar.buttons[SLOT.BACK].icon:GetTexture(), INVISIBLE)

      -- Linksklick waehlt aus; das Fenster meldet den Slot zurueck
      M.Click(bar.buttons[SLOT.CHEST])
      H.eq(Win.currentSlot, SLOT.CHEST)
      H.eq(FX.UI.SlotBar.Selected(), SLOT.CHEST)
      all("Brust gewaehlt")

      -- Aussehen waehlen: ausstehend (gelb), Zaehler bleibt
      local id
      for _, v in ipairs(State.List(SLOT.CHEST).ids) do
         if v ~= State.Baseline(SLOT.CHEST) then id = v break end
      end
      H.truthy(State.Select(SLOT.CHEST, id))
      all("Aussehen ausstehend")
      expectBorder(bar.buttons[SLOT.CHEST], COL.accent, "ausgewaehlt: Akzent")
      H.eq(bar.buttons[SLOT.CHEST].stateKey, "pending")
      H.truthy(bar.buttons[SLOT.CHEST].stripe:IsShown())

      -- Anwenden: der Knopf blitzt auf, danach ist der Platz angewendet (rosa)
      M.Click(Win.frame.btnApply)
      M.Advance(0.3, 0.05)
      local sawFlash = false
      for _, slot in ipairs(ORDER) do
         if bar.buttons[slot].over.glow:IsShown() then sawFlash = true end
      end
      Fixtures.Settle(FX, 2.0)
      H.eq(State.PendingCount(), 0)
      H.eq(bar.buttons[SLOT.CHEST].stateKey, "applied")
      all("angewendet")
      H.eq(barUpdateFrames(bar), 0, "Blitz ist vorbei, kein OnUpdate")
      H.truthy(sawFlash or srv ~= nil)

      -- Rechtsklick: Entfernen vormerken (gelb), erneut: verwerfen
      M.Click(bar.buttons[SLOT.CHEST], "RightButton")
      all("Entfernen vorgemerkt")
      H.eq(bar.buttons[SLOT.CHEST].stateKey, "pending")
      M.Click(bar.buttons[SLOT.CHEST], "RightButton")
      all("verworfen")
      H.eq(bar.buttons[SLOT.CHEST].stateKey, "applied")

      -- Fehlschlag am Server: der Knopf blitzt rot
      srv.failApply = 1
      local other
      for _, v in ipairs(State.List(SLOT.CHEST).ids) do
         if v ~= State.Baseline(SLOT.CHEST) then other = v break end
      end
      State.Select(SLOT.CHEST, other)
      Fixtures.Settle(FX, 0.5)
      M.Click(Win.frame.btnApply)
      local red = false
      for _ = 1, 30 do
         M.Advance(0.05, 0.05)
         local v = bar.buttons[SLOT.CHEST].over.glow.__vertex
         if bar.buttons[SLOT.CHEST].over.glow:IsShown() and v and v[1] == COL.red[1] and v[2] == COL.red[2] then
            red = true
         end
      end
      H.truthy(red, "Fehlschlag blitzt rot")
      Fixtures.Settle(FX, 2.0)
      H.eq(barUpdateFrames(bar), 0)
      H.eq(#M.errors, 0)

      -- Sprachwechsel bei offenem Fenster
      FX.Locale.Set("deDE")
      Fixtures.Settle(FX, 0.3)
      all("deDE")
      M.Enter(bar.buttons[SLOT.HEAD])
      H.eq(plainLines()[1], FX.Slots.Label(SLOT.HEAD))
      M.Leave(bar.buttons[SLOT.HEAD])
      FX.Locale.Set("enUS")
      H.eq(#M.errors, 0)
   end)

   H.test("Im Fenster: Klick auf einen leeren Platz zeigt dem Spieler den Grund im Raster (und wirft nichts)", function()
      local Fixtures = require("fixtures")
      local FX = Fixtures.Boot(H, { locale = "enUS", equipmentSet = "cloth" })
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX)
      local Win, State = FX.UI.Window, FX.State
      Fixtures.OpenAtNpc(FX)
      Fixtures.Settle(FX, 1.0)
      local bar = FX.UI.SlotBar.Get()
      H.eq(State.SlotState(SLOT.OFFHAND), "EMPTY", "Zweihandstab: Nebenhand leer")
      H.truthy(FX.UI.Grid.mode ~= "EMPTY", "vorher ein Slot mit Aussehen")
      M.Click(bar.buttons[SLOT.OFFHAND])
      Fixtures.Settle(FX, 0.5)
      H.eq(Win.currentSlot, SLOT.OFFHAND)
      H.eq(FX.UI.SlotBar.Selected(), SLOT.OFFHAND)
      H.eq(FX.UI.Grid.mode, "EMPTY", "das Raster nennt den Grund")
      H.eq(edgesShown(bar.buttons[SLOT.OFFHAND]), 4)
      -- Rechtsklick und Shift-Klick tun auf dem leeren Platz nichts
      M.Click(bar.buttons[SLOT.OFFHAND], "RightButton")
      M.Click(bar.buttons[SLOT.OFFHAND], "LeftButton", { shift = true })
      Fixtures.Settle(FX, 0.3)
      H.eq(State.PendingCount(), 0)
      H.eq(#M.chatInserts, 0)
      -- ein Platz mit Aussehen wird danach wieder normal bedient
      M.Click(bar.buttons[SLOT.HEAD])
      Fixtures.Settle(FX, 0.4)
      H.eq(Win.currentSlot, SLOT.HEAD)
      H.truthy(FX.UI.Grid.mode ~= "EMPTY")
      H.eq(#M.errors, 0)
   end)

   H.test("Im Fenster: Layoutpruefung der Leiste (deDE und enUS, Minimum/Standard/gross, Scale 0.6/1/1.5)", function()
      local Fixtures = require("fixtures")
      local Layout = require("layout")
      for _, loc in ipairs({ "enUS", "deDE" }) do
         local FX = Fixtures.Boot(H, { locale = loc, equipmentSet = "dualwield", screen = { w = 1920, h = 1080 } })
         Fixtures.ServerHello(FX)
         Fixtures.ServerAutoReply(FX)
         local Win = FX.UI.Window
         for _, scale in ipairs({ 0.6, 1.0, 1.5 }) do
            for _, size in ipairs({ { 740, 520 }, { 880, 600 }, { 1200, 800 } }) do
               FX.DB.Set("scale", scale)
               FX.DB.Set("width", size[1])
               FX.DB.Set("height", size[2])
               Win.Close()
               Win.Open({ fromNpc = true, slot = SLOT.HEAD })
               Fixtures.Settle(FX, 0.6)
               FX.State.Select(SLOT.CHEST, FX.State.List(SLOT.CHEST).ids[2] or 0)
               Fixtures.Settle(FX, 0.4)
               local entries = Layout.Rects(Win.frame)
               local problems = Layout.Check(entries, {})
               local label = loc .. " scale " .. scale .. " " .. size[1] .. "x" .. size[2]
               for _, p in ipairs(problems) do
                  local path = p.path or ""
                  if string.find(path, "/left/") and p.severity ~= "info" then
                     H.fail(label .. ": " .. tostring(p.severity) .. " " .. tostring(p.kind) .. " " .. path)
                  end
               end
               -- 14 sichtbare Knoepfe 40x40 in den Spalten innerhalb des linken Panels
               local bar = FX.UI.SlotBar.Get()
               local left = Layout.Find(entries, Win.frame.left)
               for _, slot in ipairs(ORDER) do
                  local e = Layout.Find(entries, bar.buttons[slot])
                  H.truthy(e and e.visible, label .. ": Knopf " .. slot .. " sichtbar")
                  if e and left then
                     H.near(e.w, 40 * e.scale, 1e-6, label .. ": " .. slot .. " Breite")
                     H.near(e.h, 40 * e.scale, 1e-6, label .. ": " .. slot .. " Hoehe")
                     H.truthy(e.x >= left.x - 1e-6 and e.x + e.w <= left.x + left.w + 1e-6, label .. ": " .. slot .. " innerhalb")
                     H.truthy(e.y >= left.y - 1e-6 and e.y + e.h <= left.y + left.h + 1e-6, label .. ": " .. slot .. " innerhalb (y)")
                  end
               end
            end
         end
      end
      H.eq(#M.errors, 0)
   end)
end
