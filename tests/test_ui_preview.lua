-- tests/test_ui_preview.lua
-- ---------------------------------------------------------------------------
-- Tests fuer UI/Preview.lua (T.UI.Preview) mit dem ECHTEN Kern (State, Items,
-- Net, Slots) und der strengen Attrappe, deren DressUpModel jeden Aufruf
-- protokolliert (M.Model(frame): calls, names(), log(), tried, facing ...).
--
-- Der Test laedt die TOC nur bis UI\Preview.lua und bildet Core\Boot.lua nach;
-- er haengt von keiner anderen UI-Datei ab. Serverantworten laufen ueber
-- T.Net.Handle im echten Drahtformat.
--
-- Geprueft wird:
--   * Aufbau: Vorlage 221x362/Scale 2.0, Layout mit festem Seitenverhaeltnis
--   * Ankleiden: normale Auswahl, Verborgen (Undress-Weg), Doppelwaffen
--     (Nebenhand; bei Bearbeitung der Nebenhand liegt eine ausstehende
--     einhaendige Waffe in der Haupthand, mit Hinweis, Neuaufbau beim
--     Verlassen), Fernkampf bearbeiten/verlassen, zurueck zum Original,
--     inaktive Aussehen, nicht gecachte Gegenstaende, Ausruestungswechsel
--   * nur Unterschiede werden angewendet; SetUnit nur wo noetig
--   * Rebuild bewahrt Facing und Position; Groessenaenderung laedt neu
--   * Maus: Ziehen dreht/verschiebt, Rad zoomt (begrenzt), OnUpdate nur
--     waehrend des Drueckens; Drehknoepfe; Reset; Fokus Umhang
--   * Ereignisse entprellt, nur sichtbar; Hygiene
--
-- Verifikation (zweiter Teil der Datei):
--   * Ergebnisbild: eine Nachbildung der DressUpModel-Semantik (SetUnit/Undress/
--     TryOn, Haende) verfolgt, was der Spieler sieht; es wird gegen den Wunsch
--     aus dem State geprueft (Szenarien und Zufallsfolgen mit Ausruestungs-
--     wechseln und nachladenden Gegenstaenden)
--   * alter Algorithmus (OLD/ui/slots_model.lua, wortgetreu portiert) laeuft
--     daneben: gleiche Aufrufe wo es sie gleich geben soll, benannte
--     Abweichungen (Fehler des alten Codes) ausdruecklich
--   * Ansicht in beiden Deutungen der Engine (Rotation/Facing getrennt oder ein
--     Winkel), verlorenes OnMouseUp, Ereignisbuendel
--   * im echten Fenster (Fixtures): Spielerablaeufe, Groesse/Scale, Layoutpruefung
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   local ORDER = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }
   local SLOT = {
      HEAD = 0, SHOULDER = 2, SHIRT = 3, CHEST = 4, WAIST = 5, LEGS = 6, FEET = 7,
      WRIST = 8, HANDS = 9, BACK = 14, MAINHAND = 15, OFFHAND = 16, RANGED = 17, TABARD = 18,
   }
   local HIDDEN = 999999

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

   -- Sitzung: Attrappe, TOC bis Preview, Boot nachgebildet.
   --   opts.equip   [slot] = id | false
   --   opts.items   zusaetzliche/ueberschriebene Gegenstandsdaten
   --   opts.cache   false: Aussehen bleiben ungecacht (angelegte gelten immer als gecacht)
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
         upTo = "Preview.lua",
         world = { equipment = equipment, locale = opts.locale or "enUS" },
         items = items,
         enterWorld = false,
      })
      H.assert(type(T) == "table" and T.UI and T.UI.Preview, "Preview wurde nicht geladen")
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

   local function sendAllLists(T)
      for _, slot in ipairs(ORDER) do
         local ids = {}
         for i = 1, 5 do ids[i] = lookId(slot, i) end
         sendList(T, slot, ids)
      end
   end

   local function settle(t)
      M.Advance(t or 0.1, 0.05)
   end

   local function setCursor(x, y)
      M.world.cursor[1], M.world.cursor[2] = x, y
   end

   -- Maustaste druecken/loslassen: wie der Client haelt IsMouseButtonDown den Zustand
   local function mouseDown(frame, button)
      M.world.mouseDown = M.world.mouseDown or {}
      M.world.mouseDown[button or "LeftButton"] = true
      M.MouseDown(frame, button)
   end
   local function mouseUp(frame, button)
      if M.world.mouseDown then M.world.mouseDown[button or "LeftButton"] = nil end
      M.MouseUp(frame, button)
   end

   -- Sitzung mit sichtbarem Container, aufgebautem Modell und leerem Aufrufprotokoll.
   --   opts.status   Status vor dem Aufbau ({ [slot] = fake })
   --   opts.noLists  true: Listen nicht senden
   --   opts.focus    Slot, der beim Aufbau schon bearbeitet wird
   local function make(opts)
      opts = opts or {}
      local T = boot(opts)
      sendStatus(T, opts.status or {})
      if not opts.noLists then sendAllLists(T) end

      local parent = CreateFrame("Frame", nil, UIParent)
      parent:SetWidth(320)
      parent:SetHeight(480)
      parent:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      local P = T.UI.Preview
      local frame = P.Create(parent)
      frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
      P.Layout(230, 400)
      if opts.focus ~= nil then P.SetFocusSlot(opts.focus) end
      if not opts.noBuild then
         P.Refresh()
         settle(0.2)
      end
      local view = M.Model(P.model)
      view.clear()
      return T, P, view, parent, frame
   end

   -- Angezeigter Winkel: die Attrappe fuehrt SetRotation und SetFacing als getrennte
   -- Anteile (die unguenstigere der beiden moeglichen Engine-Deutungen); die Summe
   -- ist, was der Spieler sieht. (Die Deutung "ein Winkel" prueft ein eigener Test.)
   local function angle(view)
      return (view.rotation or 0) + (view.facing or 0)
   end

   -- IDs aller TryOn-Aufrufe in Reihenfolge
   local function tryIds(view)
      local out = {}
      for _, c in ipairs(view.calls) do
         if c[1] == "TryOn" then out[#out + 1] = c[2] end
      end
      return out
   end

   local function indexOf(list, value)
      for i, v in ipairs(list) do
         if v == value then return i end
      end
      return nil
   end

   -- Knoepfe der Steuerzeile nach Beschriftung
   local function buttonByLabel(frame, text)
      for _, b in ipairs(M.Find(frame, "Button")) do
         if b.label and b.label:GetText() == text then return b end
      end
      return nil
   end

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

   -- Sichtbare Frames mit OnUpdate unterhalb von root
   local function updateFramesUnder(root)
      local n = 0
      for _, f in ipairs(M.UpdateFrames()) do
         local p = f
         while p do
            if p == root then
               n = n + 1
               break
            end
            p = p:GetParent()
         end
      end
      return n
   end

   -- ======================================================================
   H.section("Aufbau und Layout")
   -- ======================================================================

   H.test("Create: DressUpModel aus der Vorlage (221x362, Scale 2.0), Maus an, Steuerzeile", function()
      local T = boot()
      local parent = CreateFrame("Frame", nil, UIParent)
      parent:SetWidth(300)
      parent:SetHeight(450)
      local P = T.UI.Preview
      local frame = P.Create(parent)
      H.truthy(frame, "Container")
      H.eq(P.model:GetObjectType(), "DressUpModel")
      H.eq(P.model:GetModelScale(), 2.0, "Modell-Scale aus der Vorlage")
      H.truthy(P.model:IsMouseEnabled())
      -- Knoepfe
      H.truthy(buttonByLabel(frame, "<"), "Knopf <")
      H.truthy(buttonByLabel(frame, ">"), "Knopf >")
      H.truthy(buttonByLabel(frame, "Reset view"), "Reset-Knopf")
      -- Singleton
      H.eq(P.Create(parent), frame)
      H.eq(#M.Find(frame, "DressUpModel"), 1, "nur ein Modell")
      -- Vor dem Zeigen/Aufbau passiert am Modell nichts
      H.eq(#M.Model(P.model).calls, 0)
   end)

   H.test("Layout: Seitenverhaeltnis 221:362, passt in die Flaeche ueber der Steuerzeile, mittig", function()
      local T, P, view, _, frame = make()
      local ratio = 221 / 362
      for _, size in ipairs({ { 230, 400 }, { 318, 508 }, { 200, 300 }, { 420, 300 }, { 150, 600 }, { 460, 756 } }) do
         P.Layout(size[1], size[2])
         local mw, mh = P.model:GetWidth(), P.model:GetHeight()
         H.near(mw / mh, ratio, 1e-6, "Seitenverhaeltnis bei " .. size[1] .. "x" .. size[2])
         H.truthy(mw <= size[1] + 1e-6, "Breite passt")
         H.truthy(mh <= size[2] - P.CONTROLS_HEIGHT + 1e-6, "Hoehe passt ueber der Steuerzeile")
         H.near(frame:GetWidth(), size[1], 1e-6)
         H.near(frame:GetHeight(), size[2], 1e-6)
         -- ein Mass fuellt die Flaeche bis auf den Rand
         local fitW = (size[1] - 8) / 221
         local fitH = (size[2] - P.CONTROLS_HEIGHT - 8) / 362
         H.near(mw, 221 * math.min(fitW, fitH), 1e-6, "so gross wie passt")
         local point, rel = P.model:GetPoint()
         H.eq(point, "CENTER")
         H.truthy(rel ~= nil)
      end
   end)

   H.test("Layout: Steuerzeile unten: '<' links, '>' rechts, Reset dazwischen (Breite explizit)", function()
      local T, P, view, _, frame = make()
      P.Layout(300, 400)
      local l, r, reset = buttonByLabel(frame, "<"), buttonByLabel(frame, ">"), buttonByLabel(frame, "Reset view")
      H.eq(l:GetWidth(), 26)
      H.eq(r:GetWidth(), 26)
      H.eq(l:GetHeight(), 22)
      local lp, _, _, lx, ly = l:GetPoint()
      H.eq(lp, "BOTTOMLEFT")
      H.eq(lx, 0)
      H.eq(ly, 0)
      local rp = r:GetPoint()
      H.eq(rp, "BOTTOMRIGHT")
      H.eq(reset:GetWidth(), 300 - 52 - 12)
      H.eq((reset:GetPoint()), "BOTTOM")
      H.eq(P.CONTROLS_HEIGHT, 28)
   end)

   -- ======================================================================
   H.section("Aufbau des Modells")
   -- ======================================================================

   H.test("Unsichtbar: nichts am Modell; beim Zeigen: SetUnit, Startrotation 0.61, danach Ruhe", function()
      local T, P, view, parent = make({ noBuild = true })
      parent:Hide()
      P.Refresh()
      P.Rebuild()
      settle(0.2)
      H.eq(#view.calls, 0, "unsichtbar: keine Modellaufrufe")

      parent:Show()
      settle(0.2)
      local names = view.names()
      H.eq(names[1], "SetUnit")
      H.eq(view.calls[1][2], "player")
      H.eq(view.last("SetRotation")[2], 0.61)
      H.eq(view.count("SetFacing"), 0, "Startrotation nur per SetRotation (SPEC 9.1), kein zweiter Winkel")
      H.eq(angle(view), 0.61)
      H.eq(view.count("SetUnit"), 1)
      H.eq(view.count("TryOn"), 0, "ohne Aussehen nichts anzuprobieren")
      H.eq(view.count("Undress"), 0)
   end)

   H.test("Erster Aufbau mit angewendeten Aussehen: jedes wird einmal angeprobiert (Modell kann nachhinken)", function()
      local T, P, view = make({
         noBuild = true,
         status = { [SLOT.HEAD] = lookId(SLOT.HEAD, 2), [SLOT.BACK] = lookId(SLOT.BACK, 1) },
      })
      P.Refresh()
      settle(0.2)
      H.deepEq(tryIds(view), { lookId(SLOT.HEAD, 2), lookId(SLOT.BACK, 1) })
      view.clear()
      P.Refresh()
      settle(0.1)
      H.eq(#view.calls, 0, "ein zweites Refresh aendert nichts")
   end)

   H.test("Normale Auswahl: nur der geaenderte Platz wird angeprobiert, nie SetUnit/Undress", function()
      local T, P, view = make()
      local State = T.State
      State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      H.eq(#view.calls, 0, "entprellt: nicht sofort")
      settle()
      H.deepEq(view.names(), { "TryOn" })
      H.eq(view.calls[1][2], lookId(SLOT.HEAD, 1))

      view.clear()
      State.Select(SLOT.SHOULDER, lookId(SLOT.SHOULDER, 3))
      settle()
      H.deepEq(view.names(), { "TryOn" }, "Kopf wird nicht noch einmal angeprobiert")
      H.eq(view.calls[1][2], lookId(SLOT.SHOULDER, 3))

      -- derselbe Platz noch einmal anders
      view.clear()
      State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 4))
      settle()
      H.deepEq(tryIds(view), { lookId(SLOT.HEAD, 4) })
      H.eq(view.count("SetUnit"), 0)
      H.eq(view.count("Undress"), 0)
   end)

   H.test("Zurueck zum Original (Auswahl verwerfen): das echte Item wird wieder angeprobiert", function()
      local T, P, view = make()
      local State = T.State
      State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      settle()
      view.clear()
      State.Discard(SLOT.HEAD)
      settle()
      H.deepEq(tryIds(view), { equipId(SLOT.HEAD) })
      H.eq(view.count("SetUnit"), 0)
      -- erneut Refresh: nichts mehr
      view.clear()
      P.Refresh()
      H.eq(#view.calls, 0)
   end)

   H.test("Angewendetes Aussehen zuruecksetzen (Toggle) und wieder verwerfen", function()
      local T, P, view = make({ status = { [SLOT.HEAD] = lookId(SLOT.HEAD, 2) } })
      local State = T.State
      -- beim Aufbau wurde das angewendete Aussehen angeprobiert (im make verworfen)
      H.eq(State.Wanted(SLOT.HEAD), lookId(SLOT.HEAD, 2))
      State.Toggle(SLOT.HEAD)             -- Auswahl 0 = Original
      settle()
      H.deepEq(tryIds(view), { equipId(SLOT.HEAD) }, "Original anprobiert")
      view.clear()
      State.Toggle(SLOT.HEAD)             -- verwerfen -> wieder das angewendete
      settle()
      H.deepEq(tryIds(view), { lookId(SLOT.HEAD, 2) })
      H.eq(view.count("SetUnit"), 0)
   end)

   H.test("Nicht gecachtes Aussehen geht nie an TryOn: Abfrage, spaeter ITEMS_RESOLVED -> angeprobiert", function()
      local T, P, view = make({ cache = false })
      local State, Items = T.State, T.Items
      local id = lookId(SLOT.HEAD, 3)
      H.eq(Items.Info(id), nil, "Aussehen nicht im Cache")
      State.Select(SLOT.HEAD, id)
      settle()
      H.eq(view.count("TryOn"), 0, "ungecacht: nicht angeprobiert")
      H.truthy(Items.PendingCount() >= 1, "Abfrage wurde angestossen")

      M.CacheAll()
      M.Advance(1.0, 0.05)
      H.deepEq(tryIds(view), { id }, "nach ITEMS_RESOLVED angeprobiert")
   end)

   H.test("ITEMS_RESOLVED ohne zurueckgestellte Gegenstaende loest kein Ankleiden aus", function()
      local T, P, view = make()
      view.clear()
      T.Events.Fire("ITEMS_RESOLVED", 5)
      settle(0.3)
      H.eq(#view.calls, 0)
      H.eq(T.Util.Cancel("ui-preview"), false)
   end)

   -- ======================================================================
   H.section("Verborgen (Undress-Weg)")
   -- ======================================================================

   H.test("Neu gewaehltes Verborgen: Undress, Fernkampf zuerst, dann aufsteigend, Verborgenes uebersprungen", function()
      local T, P, view = make()
      T.State.Select(SLOT.HEAD, HIDDEN)
      settle()
      local names = view.names()
      H.eq(names[1], "Undress")
      H.eq(view.count("Undress"), 1)
      H.eq(view.count("SetUnit"), 0, "Undress braucht kein SetUnit")
      H.deepEq(tryIds(view), {
         equipId(SLOT.RANGED),                     -- Fernkampf zuerst (Nahkampf gewinnt)
         equipId(SLOT.SHOULDER), equipId(SLOT.SHIRT), equipId(SLOT.CHEST), equipId(SLOT.WAIST),
         equipId(SLOT.LEGS), equipId(SLOT.FEET), equipId(SLOT.WRIST), equipId(SLOT.HANDS),
         equipId(SLOT.BACK), equipId(SLOT.MAINHAND), equipId(SLOT.OFFHAND), equipId(SLOT.TABARD),
      })
   end)

   H.test("Verborgen + Auswahl in einem anderen Platz: dessen Aussehen statt des Originals", function()
      local T, P, view = make()
      T.State.Select(SLOT.SHOULDER, lookId(SLOT.SHOULDER, 2))
      settle()
      view.clear()
      T.State.Select(SLOT.HEAD, HIDDEN)
      settle()
      local ids = tryIds(view)
      H.truthy(indexOf(ids, lookId(SLOT.SHOULDER, 2)), "Schulter-Aussehen angeprobiert")
      H.falsy(indexOf(ids, equipId(SLOT.SHOULDER)), "nicht das Original der Schulter")
      H.eq(view.names()[1], "Undress")
   end)

   H.test("Fernkampf wird im Undress-Weg bei Bearbeitung zuletzt angeprobiert", function()
      local T, P, view = make({ focus = SLOT.RANGED })
      T.State.Select(SLOT.HEAD, HIDDEN)
      settle()
      local ids = tryIds(view)
      H.eq(ids[#ids], equipId(SLOT.RANGED), "Fernkampf zuletzt")
   end)

   H.test("Im Undress-Weg aendert eine weitere Auswahl nur den betroffenen Platz (kein erneutes Undress)", function()
      local T, P, view = make()
      T.State.Select(SLOT.HEAD, HIDDEN)
      settle()
      view.clear()
      T.State.Select(SLOT.CHEST, lookId(SLOT.CHEST, 3))
      settle()
      H.deepEq(view.names(), { "TryOn" })
      H.eq(view.calls[1][2], lookId(SLOT.CHEST, 3))
      -- ein zweites Verborgen braucht ein neues Undress
      view.clear()
      T.State.Select(SLOT.WAIST, HIDDEN)
      settle()
      H.eq(view.names()[1], "Undress")
      local ids = tryIds(view)
      H.truthy(indexOf(ids, lookId(SLOT.CHEST, 3)), "Auswahl der Brust bleibt")
      H.falsy(indexOf(ids, equipId(SLOT.WAIST)), "Taille ist verborgen")
      H.falsy(indexOf(ids, equipId(SLOT.HEAD)), "Kopf bleibt verborgen")
   end)

   H.test("Verborgen verwerfen: SetUnit(player) mit erhaltener Drehung/Position, dann nur Unterschiede", function()
      local T, P, view = make()
      T.State.Select(SLOT.CHEST, lookId(SLOT.CHEST, 2))
      T.State.Select(SLOT.HEAD, HIDDEN)
      settle()
      -- Kamera aendern
      P.model:SetFacing(2.25)
      P.model:SetPosition(3, 0.5, -0.5)
      view.clear()

      T.State.Discard(SLOT.HEAD)
      settle()
      H.deepEq(view.names(), { "SetUnit", "SetRotation", "SetFacing", "SetPosition", "TryOn" })
      H.eq(view.calls[1][2], "player")
      H.eq(view.facing, 2.25, "Facing erhalten")
      H.eq(view.rotation, 0.61, "Rotation wieder gesetzt (SetUnit kann sie verwerfen)")
      H.deepEq(view.position, { 3, 0.5, -0.5 })
      H.eq(view.calls[5][2], lookId(SLOT.CHEST, 2), "die Auswahl der Brust bleibt sichtbar")
   end)

   H.test("Bereits angewendetes Verborgen braucht keinen Undress-Weg", function()
      local T, P, view = make({ status = { [SLOT.CHEST] = HIDDEN } })
      H.eq(view.count("Undress"), 0)
      T.State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      settle()
      H.deepEq(view.names(), { "TryOn" })
      -- Aussehen im verborgenen Platz waehlen und verwerfen: wieder verborgen -> neu laden
      view.clear()
      T.State.Select(SLOT.CHEST, lookId(SLOT.CHEST, 1))
      settle()
      H.deepEq(tryIds(view), { lookId(SLOT.CHEST, 1) })
      view.clear()
      T.State.Discard(SLOT.CHEST)
      settle()
      H.eq(view.count("SetUnit"), 1, "Verborgen laesst sich nur per SetUnit wieder zeigen")
      H.eq(view.count("Undress"), 0)
   end)

   H.test("Verborgen waehlen, dann auf Original zuruecksetzen (Auswahl 0 auf angewendetem Verborgen)", function()
      local T, P, view = make({ status = { [SLOT.CHEST] = HIDDEN } })
      T.State.Toggle(SLOT.CHEST)            -- Auswahl 0: echtes Item wieder zeigen
      settle()
      H.eq(T.State.Wanted(SLOT.CHEST), 0)
      H.deepEq(tryIds(view), { equipId(SLOT.CHEST) })
   end)

   -- ======================================================================
   H.section("Waffen")
   -- ======================================================================

   -- Doppelwaffentraeger: Nebenhand haelt eine einhaendige Waffe
   local DUAL = {
      equip = { [SLOT.OFFHAND] = 1116 },
      items = {
         [1116] = { name = "Equipped Dagger", quality = 3, ilvl = 100, equipLoc = "INVTYPE_WEAPON",
                    class = "Weapon", subclass = "Daggers", icon = "Interface\\Icons\\INV_Dagger_1" },
         [2161] = { name = "Offhand One-Hand Sword", quality = 3, ilvl = 100, equipLoc = "INVTYPE_WEAPON",
                    class = "Weapon", subclass = "Daggers", icon = "Interface\\Icons\\INV_Sword_9" },
         [2162] = { name = "Offhand Only Dagger", quality = 3, ilvl = 100, equipLoc = "INVTYPE_WEAPONOFFHAND",
                    class = "Weapon", subclass = "Daggers", icon = "Interface\\Icons\\INV_Dagger_9" },
         [2163] = { name = "Held Orb", quality = 3, ilvl = 100, equipLoc = "INVTYPE_HOLDABLE",
                    class = "Armor", subclass = "Miscellaneous", icon = "Interface\\Icons\\INV_Misc_Orb_01" },
         [2164] = { name = "Round Shield", quality = 3, ilvl = 100, equipLoc = "INVTYPE_SHIELD",
                    class = "Armor", subclass = "Shields", icon = "Interface\\Icons\\INV_Shield_01" },
         [2165] = { name = "Second One-Hand Axe", quality = 3, ilvl = 100, equipLoc = "INVTYPE_WEAPONMAINHAND",
                    class = "Weapon", subclass = "One-Handed Axes", icon = "Interface\\Icons\\INV_Axe_02" },
      },
   }

   local function sendOffhandList(T, ids)
      sendList(T, SLOT.OFFHAND, ids)
   end

   H.test("Doppelwaffen ohne Fokus auf der Nebenhand: eine Waffe dort wird nicht angeprobiert (landete rechts), alter Hinweis", function()
      local T, P, view, _, frame = make(DUAL)
      sendOffhandList(T, { 2161, 2162, 2163, 2164 })
      view.clear()
      T.State.Select(SLOT.OFFHAND, 2161)
      settle()
      H.eq(view.count("TryOn"), 0, "keine Waffe in der Nebenhand anprobiert")
      H.eq(view.count("Undress"), 0)
      H.eq(view.count("SetUnit"), 0)
      local texts = M.Texts(frame)
      H.truthy(M.HasText(frame, "One-handed weapons in the off hand are not shown in this preview."), "Hinweis sichtbar")

      -- Nebenhandwaffe, Schildhandgegenstand und Schild werden gezeigt (Hinweis verschwindet)
      for _, id in ipairs({ 2162, 2163, 2164 }) do
         view.clear()
         T.State.Select(SLOT.OFFHAND, id)
         settle()
         H.deepEq(tryIds(view), { id }, "Nebenhand-Typ " .. id)
         H.falsy(M.HasText(frame, "One-handed weapons in the off hand are not shown in this preview."))
      end
   end)

   H.test("Doppelwaffen: Haupthandwaffe wird angeprobiert, echte Nebenhandwaffe bleibt unberuehrt", function()
      local T, P, view = make(DUAL)
      T.State.Select(SLOT.MAINHAND, lookId(SLOT.MAINHAND, 2))
      settle()
      H.deepEq(view.names(), { "TryOn" })
      H.eq(view.calls[1][2], lookId(SLOT.MAINHAND, 2))
      H.eq(view.count("SetUnit"), 0, "SetUnit nicht bei jedem Klick (verlor sonst die zweite Waffe)")
      H.eq(view.count("Undress"), 0)
   end)

   H.test("Doppelwaffen im Undress-Weg (kein Fokus auf der Nebenhand): Haupthand wird gezeigt, die einhaendige Nebenhandwaffe nicht", function()
      local T, P, view = make(DUAL)
      T.State.Select(SLOT.HEAD, HIDDEN)
      settle()
      local ids = tryIds(view)
      H.truthy(indexOf(ids, equipId(SLOT.MAINHAND)), "Haupthand")
      H.falsy(indexOf(ids, 1116), "einhaendige Nebenhandwaffe wuerde die Haupthand ersetzen")
      H.falsy(M.HasText(T.UI.Preview.frame, "One-handed weapons in the off hand are not shown in this preview."),
         "kein Hinweis ohne Auswahl in der Nebenhand")
   end)

   -- ----------------------------------------------------------------------
   -- Nebenhand bearbeiten: eine einhaendige Waffe wird in der Haupthand gezeigt
   -- (die Engine zeichnet sie nur rechts; eine zweite Anprobe ersetzt die erste)
   -- ----------------------------------------------------------------------
   local NOTE_SKIP = "One-handed weapons in the off hand are not shown in this preview."
   local NOTE_MAIN = "This one-handed weapon is shown in the main hand (client limitation)."
   local WEAPON_C, WEAPON_C2 = 2161, 2165            -- einhaendig (INVTYPE_WEAPON / WEAPONMAINHAND)
   local OFF_DAGGER, OFF_HOLD, OFF_SHIELD = 2162, 2163, 2164

   -- Doppelwaffentraeger, Fokus (Standard: Nebenhand) schon beim Aufbau
   local function makeDual(focus)
      local T, P, view, parent, frame = make({
         equip = DUAL.equip, items = DUAL.items, focus = focus == nil and SLOT.OFFHAND or focus,
      })
      sendOffhandList(T, { 2161, 2162, 2163, 2164, 2165 })
      view.clear()
      return T, P, view, parent, frame
   end

   -- Welche der beiden Hinweise sind sichtbar? (Rueckgabe: skip, main)
   local function notes(frame)
      return M.HasText(frame, NOTE_SKIP), M.HasText(frame, NOTE_MAIN)
   end

   -- Anzahl sichtbarer Hinweise (egal in welcher Sprache: das Hinweisfeld liegt in
   -- der Buehne und ist der einzige sichtbare Text dort ausser den Knopfbeschriftungen)
   local function noteCount(frame)
      local n = 0
      for _, o in ipairs(M.Find(frame, "FontString")) do
         local t = o:GetText()
         if o:IsVisible() and t and t ~= "" and t ~= "<" and t ~= ">" and t ~= "Reset view"
            and t ~= "Ansicht zuruecksetzen" then
            n = n + 1
         end
      end
      return n
   end

   H.test("Nebenhand bearbeiten: ausstehende einhaendige Waffe wird einmal angeprobiert, Hinweis 'in der Haupthand'", function()
      local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      settle()
      H.deepEq(view.names(), { "TryOn" }, "genau eine Anprobe, kein SetUnit/Undress")
      H.eq(view.calls[1][2], WEAPON_C)
      local skip, main = notes(frame)
      H.eq(main, true, "Hinweis: in der Haupthand")
      H.eq(skip, false, "alter Hinweis (uebersprungen) ist weg")
      H.eq(noteCount(frame), 1, "genau ein Hinweis")

      -- unveraendert: ein weiteres Ankleiden aendert weder das Modell noch den Hinweis
      view.clear()
      P.Refresh()
      P.Refresh()
      settle(0.2)
      H.eq(#view.calls, 0)
      skip, main = notes(frame)
      H.eq(main, true)
      H.eq(skip, false)
      H.eq(#M.errors, 0)
   end)

   H.test("Nebenhand bearbeiten: auch WEAPONMAINHAND und eine zweite Waffe (ersetzt die erste ohne SetUnit)", function()
      local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      settle()
      view.clear()
      T.State.Select(SLOT.OFFHAND, WEAPON_C2)
      settle()
      H.deepEq(view.names(), { "TryOn" }, "die zweite Anprobe ersetzt die erste, kein Neuaufbau")
      H.eq(view.calls[1][2], WEAPON_C2)
      local skip, main = notes(frame)
      H.eq(main, true)
      H.eq(skip, false)
      -- zurueck zur ersten
      view.clear()
      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      settle()
      H.deepEq(tryIds(view), { WEAPON_C })
      H.eq(view.count("SetUnit"), 0)
   end)

   H.test("Fokus verlassen: SetUnit, die Haupthand kehrt zurueck, die Waffe wird nicht mehr angeprobiert (alter Hinweis)", function()
      local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      settle()
      view.clear()

      P.SetFocusSlot(SLOT.MAINHAND)
      settle()
      H.eq(view.count("SetUnit"), 1, "Neuaufbau stellt die Haupthand wieder her")
      H.eq(view.count("TryOn"), 0, "die echte Haupthand ist das Ziel: keine Anprobe noetig, die Waffe nicht mehr")
      H.eq(view.count("Undress"), 0)
      local skip, main = notes(frame)
      H.eq(skip, true, "alter Hinweis: solange die Nebenhandauswahl aussteht")
      H.eq(main, false, "Hinweis 'in der Haupthand' ist weg")

      -- und wieder zur Nebenhand: nur die Anprobe, kein Neuaufbau
      view.clear()
      P.SetFocusSlot(SLOT.OFFHAND)
      settle()
      H.deepEq(view.names(), { "TryOn" })
      H.eq(view.calls[1][2], WEAPON_C)
      skip, main = notes(frame)
      H.eq(main, true)
      H.eq(skip, false)
   end)

   H.test("Fokus verlassen ueber Window.currentSlot (kein SetFocusSlot): ebenfalls Neuaufbau", function()
      local T, P, view = make({ equip = DUAL.equip, items = DUAL.items })
      T.UI.Window = { currentSlot = SLOT.OFFHAND }
      sendOffhandList(T, { 2161, 2162, 2163, 2164, 2165 })
      view.clear()
      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      settle()
      H.deepEq(tryIds(view), { WEAPON_C })
      view.clear()
      T.UI.Window.currentSlot = SLOT.HEAD
      T.Events.Fire("STATUS_CHANGED")
      settle()
      H.eq(view.count("SetUnit"), 1)
      H.eq(view.count("TryOn"), 0)
   end)

   H.test("Nebenhand bearbeiten: Waffe, dann Schild / Nebenhandwaffe / Held-in-der-Hand: Neuaufbau, danach die neue Anprobe, kein Hinweis", function()
      for _, id in ipairs({ OFF_SHIELD, OFF_DAGGER, OFF_HOLD }) do
         local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
         T.State.Select(SLOT.OFFHAND, WEAPON_C)
         settle()
         view.clear()
         T.State.Select(SLOT.OFFHAND, id)
         settle()
         local names = view.names()
         H.eq(names[1], "SetUnit", "Neuaufbau zuerst (" .. id .. ")")
         H.eq(view.count("SetUnit"), 1)
         H.deepEq(tryIds(view), { id }, "danach die neue Anprobe (" .. id .. ")")
         H.eq(view.count("Undress"), 0)
         H.eq(noteCount(frame), 0, "kein Hinweis (" .. id .. ")")
      end
   end)

   H.test("Nebenhand bearbeiten: Waffe, dann Original/Verwerfen: Neuaufbau ohne Anprobe, kein Hinweis", function()
      -- Original (Auswahl 0 = Baseline) und Verwerfen
      for _, how in ipairs({ "select0", "discard" }) do
         local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
         T.State.Select(SLOT.OFFHAND, WEAPON_C)
         settle()
         view.clear()
         if how == "select0" then
            T.State.Select(SLOT.OFFHAND, 0)
         else
            T.State.Discard(SLOT.OFFHAND)
         end
         settle()
         H.eq(T.State.HasPending(SLOT.OFFHAND), false)
         H.eq(view.count("SetUnit"), 1, how)
         H.eq(view.count("TryOn"), 0, how .. ": Original = das Modell nach SetUnit")
         H.eq(noteCount(frame), 0, how .. ": kein Hinweis")
      end
   end)

   H.test("Nebenhand bearbeiten: Schild, dann einhaendige Waffe: Neuaufbau, dann TryOn, Hinweis 'in der Haupthand'", function()
      local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
      T.State.Select(SLOT.OFFHAND, OFF_SHIELD)
      settle()
      H.deepEq(tryIds(view), { OFF_SHIELD })
      H.eq(noteCount(frame), 0)
      view.clear()

      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      settle()
      local names = view.names()
      H.eq(names[1], "SetUnit", "der Schild links muss weg")
      H.eq(view.count("SetUnit"), 1)
      H.deepEq(tryIds(view), { WEAPON_C })
      local skip, main = notes(frame)
      H.eq(main, true)
      H.eq(skip, false)
   end)

   H.test("Ausstehende Haupthand A' und Nebenhandwaffe C: bei Fokus Nebenhand A' dann C, bei Fokus Haupthand nur A'", function()
      local A = lookId(SLOT.MAINHAND, 2)
      -- Fokus Nebenhand: C gewinnt in der rechten Hand (aufsteigende Reihenfolge)
      do
         local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
         T.State.Select(SLOT.OFFHAND, WEAPON_C)      -- zuerst gewaehlt, trotzdem zuletzt angeprobiert
         T.State.Select(SLOT.MAINHAND, A)
         settle()
         H.deepEq(tryIds(view), { A, WEAPON_C }, "Haupthand zuerst, Nebenhand zuletzt")
         H.eq(view.count("SetUnit"), 0)
         local skip, main = notes(frame)
         H.eq(main, true)
         H.eq(skip, false)
      end
      -- Fokus Haupthand: nur A', C uebersprungen (alter Hinweis)
      do
         local T, P, view, _, frame = makeDual(SLOT.MAINHAND)
         T.State.Select(SLOT.OFFHAND, WEAPON_C)
         T.State.Select(SLOT.MAINHAND, A)
         settle()
         H.deepEq(tryIds(view), { A }, "nur die Haupthand")
         local skip, main = notes(frame)
         H.eq(skip, true)
         H.eq(main, false)
      end
   end)

   H.test("Haupthand wechselt, waehrend die Nebenhandwaffe gezeigt wird: Haupthand, dann die Nebenhandwaffe erneut", function()
      local A, A2 = lookId(SLOT.MAINHAND, 2), lookId(SLOT.MAINHAND, 3)
      local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      settle()
      view.clear()
      T.State.Select(SLOT.MAINHAND, A)
      settle()
      H.deepEq(tryIds(view), { A, WEAPON_C }, "die Nebenhandwaffe bleibt zuletzt (sonst verdeckte die Haupthand sie)")
      H.eq(view.count("SetUnit"), 0)
      view.clear()
      T.State.Select(SLOT.MAINHAND, A2)
      settle()
      H.deepEq(tryIds(view), { A2, WEAPON_C })
      -- Haupthand zurueck auf das Original: ebenso
      view.clear()
      T.State.Discard(SLOT.MAINHAND)
      settle()
      H.deepEq(tryIds(view), { equipId(SLOT.MAINHAND), WEAPON_C })
      -- ein Schild ersetzt die Waffe: Neuaufbau, die Haupthand ist wieder sie selbst
      view.clear()
      T.State.Select(SLOT.OFFHAND, OFF_SHIELD)
      settle()
      H.eq(view.count("SetUnit"), 1)
      H.deepEq(tryIds(view), { OFF_SHIELD })
      H.eq(noteCount(frame), 0)
   end)

   H.test("Undress-Weg mit Fokus Nebenhand: die ausstehende Waffe wird nach den Ruestungsteilen angeprobiert", function()
      local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      T.State.Select(SLOT.HEAD, HIDDEN)             -- neu verborgen: Undress-Weg
      settle()
      H.eq(view.names()[1], "Undress")
      H.eq(view.count("Undress"), 1)
      H.eq(view.count("SetUnit"), 0)
      H.deepEq(tryIds(view), {
         equipId(SLOT.RANGED),                       -- Fernkampf zuerst
         equipId(SLOT.SHOULDER), equipId(SLOT.SHIRT), equipId(SLOT.CHEST), equipId(SLOT.WAIST),
         equipId(SLOT.LEGS), equipId(SLOT.FEET), equipId(SLOT.WRIST), equipId(SLOT.HANDS),
         equipId(SLOT.BACK), equipId(SLOT.MAINHAND),
         WEAPON_C,                                   -- nach der Haupthand: gewinnt rechts
         equipId(SLOT.TABARD),
      })
      local skip, main = notes(frame)
      H.eq(main, true)
      H.eq(skip, false)

      -- ohne Aenderung: Ruhe
      view.clear()
      P.Refresh()
      H.eq(#view.calls, 0)

      -- Fokus verlassen: wieder voller Undress-Durchlauf ohne die Waffe, alter Hinweis
      view.clear()
      P.SetFocusSlot(SLOT.CHEST)
      settle()
      H.eq(view.names()[1], "Undress")
      H.falsy(indexOf(tryIds(view), WEAPON_C), "nicht mehr angeprobiert")
      H.truthy(indexOf(tryIds(view), equipId(SLOT.MAINHAND)), "die Haupthand ist wieder da")
      skip, main = notes(frame)
      H.eq(skip, true)
      H.eq(main, false)
   end)

   H.test("Undress-Weg: Waffe -> Schild bei Fokus Nebenhand baut den Undress-Zustand neu auf", function()
      local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
      T.State.Select(SLOT.HEAD, HIDDEN)
      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      settle()
      view.clear()
      T.State.Select(SLOT.OFFHAND, OFF_SHIELD)
      settle()
      H.eq(view.names()[1], "Undress", "die Waffe in der Haupthand laesst sich nur per Undress loswerden")
      local ids = tryIds(view)
      H.eq(ids[#ids - 1], OFF_SHIELD, "Schild vor dem Wappenrock")
      H.falsy(indexOf(ids, WEAPON_C))
      H.truthy(indexOf(ids, equipId(SLOT.MAINHAND)))
      H.eq(noteCount(frame), 0)
   end)

   H.test("Angewendete (nicht ausstehende) einhaendige Nebenhandwaffe: auch bei Fokus Nebenhand nicht angeprobiert, kein Hinweis", function()
      -- SetUnit zeichnet das angewendete Aussehen ohnehin links; ein TryOn wuerde die echte Haupthand ersetzen
      local T, P, view, _, frame = make({
         equip = DUAL.equip, items = DUAL.items, focus = SLOT.OFFHAND,
         status = { [SLOT.OFFHAND] = WEAPON_C },
      })
      H.eq(T.State.Baseline(SLOT.OFFHAND), WEAPON_C)
      H.eq(T.State.HasPending(SLOT.OFFHAND), false)
      view.clear()
      P.Rebuild()
      settle(0.2)
      H.eq(view.count("TryOn"), 0, "nichts angeprobiert")
      H.eq(noteCount(frame), 0, "kein Hinweis")

      -- eine Auswahl ersetzt sie: nun ausstehend, in der Haupthand gezeigt
      view.clear()
      T.State.Select(SLOT.OFFHAND, WEAPON_C2)
      settle()
      H.deepEq(tryIds(view), { WEAPON_C2 })
      H.eq(view.count("SetUnit"), 0)
      H.eq(M.HasText(frame, NOTE_MAIN), true)

      -- verworfen: Baseline gilt wieder (nicht gezeigt) -> Neuaufbau, Haupthand zurueck
      view.clear()
      T.State.Discard(SLOT.OFFHAND)
      settle()
      H.eq(view.count("SetUnit"), 1)
      H.eq(view.count("TryOn"), 0)
      H.eq(noteCount(frame), 0)
      H.eq(#M.errors, 0)
   end)

   H.test("Normaler Doppelwaffentraeger-Fokus Haupthand/Kopf: einhaendige Nebenhandwaffe bleibt uebersprungen (alter Hinweis)", function()
      for _, focus in ipairs({ SLOT.MAINHAND, SLOT.HEAD, SLOT.RANGED, SLOT.BACK }) do
         local T, P, view, _, frame = makeDual(focus)
         T.State.Select(SLOT.OFFHAND, WEAPON_C)
         settle()
         H.eq(view.count("TryOn"), 0, "Fokus " .. focus .. ": nicht angeprobiert")
         local skip, main = notes(frame)
         H.eq(skip, true, "Fokus " .. focus)
         H.eq(main, false, "Fokus " .. focus)
      end
   end)

   H.test("Hinweis folgt dem Sprachwechsel: der gezeigte Hinweis wird neu gesetzt, ohne Neuaufbau", function()
      local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
      T.Locale.Add("xxXX", {
         PREVIEW_OFFHAND_NOTE = "Hinweis uebersprungen",
         PREVIEW_OFFHAND_NOTE_MAINHAND = "Hinweis Haupthand",
      })
      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      settle()
      H.eq(M.HasText(frame, NOTE_MAIN), true)
      view.clear()

      T.Locale.Set("xxXX")
      settle(0.3)
      H.eq(M.HasText(frame, "Hinweis Haupthand"), true, "Haupthand-Hinweis uebersetzt")
      H.eq(M.HasText(frame, NOTE_MAIN), false)
      H.eq(M.HasText(frame, "Hinweis uebersprungen"), false, "nicht der andere Hinweis")
      H.eq(#view.calls, 0, "kein Neuaufbau")

      -- Fokuswechsel: der alte Hinweis in der neuen Sprache
      P.SetFocusSlot(SLOT.MAINHAND)
      settle()
      H.eq(M.HasText(frame, "Hinweis uebersprungen"), true)
      H.eq(M.HasText(frame, "Hinweis Haupthand"), false)

      -- Sprache zurueck: der sichtbare (alte) Hinweis wird englisch
      T.Locale.Set("enUS")
      settle(0.3)
      H.eq(M.HasText(frame, NOTE_SKIP), true)
      H.eq(noteCount(frame), 1)

      -- und wieder die Waffe: Haupthand-Hinweis englisch
      P.SetFocusSlot(SLOT.OFFHAND)
      settle()
      H.eq(M.HasText(frame, NOTE_MAIN), true)
      -- ohne Hinweis bleibt ApplyLocale still
      T.State.Discard(SLOT.OFFHAND)
      settle()
      H.eq(noteCount(frame), 0)
      T.Locale.Set("xxXX")
      T.Locale.Set("enUS")
      settle(0.3)
      H.eq(noteCount(frame), 0)
      H.eq(#M.errors, 0)
   end)

   H.test("Hinweisfeld bleibt 36 px hoch (3 Zeilen), unveraendert fuer beide Hinweise; kein OnUpdate in der Vorschau", function()
      local T, P, view, _, frame = makeDual(SLOT.OFFHAND)
      local function noteFs()
         for _, o in ipairs(M.Find(frame, "FontString")) do
            local t = o:GetText()
            if t == NOTE_MAIN or t == NOTE_SKIP then return o end
         end
         return nil
      end
      T.State.Select(SLOT.OFFHAND, WEAPON_C)
      settle()
      local fs = noteFs()
      H.truthy(fs, "Hinweisfeld")
      H.eq(fs:GetHeight(), 36)
      P.SetFocusSlot(SLOT.MAINHAND)
      settle()
      local fs2 = noteFs()
      H.eq(fs2, fs, "dasselbe Feld")
      H.eq(fs2:GetHeight(), 36)
      H.eq(fs2:GetText(), NOTE_SKIP)

      -- ein Durchlauf aller Wege: Fokuswechsel, Waffen, Schild, Undress, Neuaufbau
      local A = lookId(SLOT.MAINHAND, 2)
      P.SetFocusSlot(SLOT.OFFHAND)
      T.State.Select(SLOT.MAINHAND, A)
      T.State.Select(SLOT.OFFHAND, OFF_SHIELD)
      settle()
      T.State.Select(SLOT.OFFHAND, WEAPON_C2)
      settle()
      T.State.Select(SLOT.HEAD, HIDDEN)
      settle()
      P.SetFocusSlot(SLOT.BACK)
      settle()
      T.State.Discard(SLOT.HEAD)
      P.SetFocusSlot(SLOT.OFFHAND)
      P.Rebuild()
      settle(0.5)
      H.eq(updateFramesUnder(frame), 0, "kein OnUpdate-Frame uebrig")
      local missing = {}
      for key in pairs(T.L.__missing) do
         if string.find(key, "^PREVIEW_") then missing[#missing + 1] = key end
      end
      H.deepEq(missing, {}, "fehlende PREVIEW_-Schluessel")
      H.eq(#M.errors, 0)
   end)

   H.test("Fernkampf: ohne Bearbeitung nie angeprobiert; bei Bearbeitung ja; beim Verlassen Nahkampf wieder frei", function()
      local T, P, view = make()
      local State = T.State
      State.Select(SLOT.RANGED, lookId(SLOT.RANGED, 1))
      settle()
      H.eq(view.count("TryOn"), 0, "Fernkampf deckte sonst die Nahkampfwaffe")

      P.SetFocusSlot(SLOT.RANGED)
      settle()
      H.deepEq(tryIds(view), { lookId(SLOT.RANGED, 1) }, "bei Bearbeitung angeprobiert")
      H.eq(view.count("SetUnit"), 0)

      -- anderen Platz bearbeiten: der Fernkampf-Look liegt auf der Hand -> neu laden
      view.clear()
      P.SetFocusSlot(SLOT.SHOULDER)
      settle()
      H.eq(view.count("SetUnit"), 1, "SetUnit stellt die Haupthand wieder her")
      H.eq(view.count("TryOn"), 0, "Fernkampf nicht angeprobiert")
      H.eq(view.count("Undress"), 0)
   end)

   H.test("Fernkampf-Fokus kommt auch ueber Window.currentSlot an", function()
      local T, P, view = make()
      T.UI.Window = { currentSlot = SLOT.RANGED }
      T.State.Select(SLOT.RANGED, lookId(SLOT.RANGED, 2))
      settle()
      H.deepEq(tryIds(view), { lookId(SLOT.RANGED, 2) })
   end)

   -- ======================================================================
   H.section("Zustand der Plaetze")
   -- ======================================================================

   H.test("Inaktives Aussehen: Modell zeigt das echte Item, nichts wird angeprobiert", function()
      local T, P, view = make({ noBuild = true, status = { [SLOT.LEGS] = 2999 } })
      H.eq(T.State.IsInactive(SLOT.LEGS), true)
      P.Refresh()
      settle(0.2)
      H.eq(view.count("TryOn"), 0)
      H.eq(view.count("SetUnit"), 1)
   end)

   H.test("Liste wird fertig und macht ein angewendetes Aussehen inaktiv: Original wird wieder angeprobiert", function()
      local T, P, view = make({
         noBuild = true, noLists = true, status = { [SLOT.LEGS] = lookId(SLOT.LEGS, 4) },
      })
      -- Liste noch nicht da: Aussehen gilt als aktiv, wird angeprobiert
      P.Refresh()
      settle(0.2)
      H.deepEq(tryIds(view), { lookId(SLOT.LEGS, 4) })
      view.clear()
      -- Liste kommt ohne dieses Aussehen: inaktiv, Server zeigt das echte Item
      sendList(T, SLOT.LEGS, { lookId(SLOT.LEGS, 1), lookId(SLOT.LEGS, 2) })
      settle()
      H.eq(T.State.IsInactive(SLOT.LEGS), true)
      H.deepEq(tryIds(view), { equipId(SLOT.LEGS) })
   end)

   H.test("Leerer und nie transmogbarer Platz: keine Anproben, keine Fehler (auch im Undress-Weg)", function()
      local T, P, view = make({
         equip = { [SLOT.TABARD] = false, [SLOT.RANGED] = 1117 },
         items = { [1117] = { name = "Idol", quality = 3, equipLoc = "INVTYPE_RELIC", class = "Armor",
                              subclass = "Idols", icon = "Interface\\Icons\\INV_Misc_Idol" } },
      })
      H.eq(T.State.SlotState(SLOT.TABARD), "EMPTY")
      H.eq(T.State.SlotState(SLOT.RANGED), "NEVER")
      T.State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      settle()
      H.deepEq(tryIds(view), { lookId(SLOT.HEAD, 1) })
      view.clear()
      T.State.Select(SLOT.SHOULDER, HIDDEN)
      settle()
      local ids = tryIds(view)
      H.falsy(indexOf(ids, equipId(SLOT.TABARD)), "leerer Platz")
      H.eq(#M.errors, 0)
   end)

   H.test("Ausruestung wechselt: Modell wird neu geladen und das Aussehen der anderen Plaetze bleibt", function()
      local T, P, view = make({
         items = { [1100] = { name = "New Helm", quality = 4, ilvl = 120, equipLoc = "INVTYPE_HEAD",
                              class = "Armor", subclass = "Plate", icon = "Interface\\Icons\\INV_Helmet_99" } },
      })
      T.State.Select(SLOT.SHOULDER, lookId(SLOT.SHOULDER, 2))
      settle()
      view.clear()
      M.world.equipment[SLOT.HEAD + 1] = 1100
      M.CacheAll()
      M.Fire("PLAYER_EQUIPMENT_CHANGED", SLOT.HEAD + 1)
      settle()
      H.eq(view.count("SetUnit"), 1, "neuer Gegenstand: SetUnit")
      H.truthy(indexOf(tryIds(view), lookId(SLOT.SHOULDER, 2)), "ausstehende Auswahl bleibt zu sehen")
   end)

   -- ======================================================================
   H.section("Kamera und Maus")
   -- ======================================================================

   H.test("Linksziehen dreht (SetFacing + dx/34), OnUpdate nur waehrend des Haltens", function()
      local T, P, view, _, frame = make()
      local model = P.model
      H.eq(angle(view), 0.61)
      H.eq(updateFramesUnder(frame), 0, "Leerlauf: kein OnUpdate")

      setCursor(100, 200)
      mouseDown(model, "LeftButton")
      H.eq(updateFramesUnder(frame), 1, "waehrend des Drueckens laeuft OnUpdate")
      setCursor(134, 200)
      M.Advance(0.05, 0.05)
      H.near(angle(view), 0.61 + 1.0, 1e-9, "34 px = 1 rad")
      setCursor(100, 200)
      M.Advance(0.05, 0.05)
      H.near(angle(view), 0.61, 1e-9, "zurueck")
      mouseUp(model, "LeftButton")
      H.eq(updateFramesUnder(frame), 0, "nach dem Loslassen kein OnUpdate")
      setCursor(500, 500)
      M.Advance(0.1, 0.05)
      H.near(angle(view), 0.61, 1e-9, "nach dem Loslassen keine Drehung")
   end)

   H.test("Rechtsziehen verschiebt (SetPosition + dx/45, dy/45), begrenzt um die Ausgangslage", function()
      local T, P, view = make()
      local model = P.model
      local z0, x0, y0 = model:GetPosition()
      setCursor(100, 100)
      mouseDown(model, "RightButton")
      setCursor(145, 190)
      M.Advance(0.05, 0.05)
      local z, x, y = model:GetPosition()
      H.near(z, z0, 1e-9, "Tiefe bleibt")
      H.near(x, x0 + 1, 1e-9, "45 px = 1 Einheit")
      H.near(y, y0 + 2, 1e-9, "90 px = 2 Einheiten")
      -- weit ueber den Rand hinaus
      setCursor(100000, 100000)
      M.Advance(0.05, 0.05)
      local _, x2, y2 = model:GetPosition()
      H.near(x2, x0 + 8, 1e-9, "Verschiebung begrenzt")
      H.near(y2, y0 + 8, 1e-9)
      mouseUp(model, "RightButton")
      H.eq(angle(view), 0.61, "Rechtsziehen dreht nicht")
   end)

   H.test("Mausrad zoomt um 1 je Rastung, begrenzt", function()
      local T, P, view = make()
      local model = P.model
      local z0 = model:GetPosition()
      M.Wheel(model, 1)
      H.eq((model:GetPosition()), z0 + 1)
      M.Wheel(model, -1)
      M.Wheel(model, -1)
      H.eq((model:GetPosition()), z0 - 1)
      for _ = 1, 40 do M.Wheel(model, 1) end
      H.eq((model:GetPosition()), z0 + 16, "obere Grenze")
      for _ = 1, 40 do M.Wheel(model, -1) end
      H.eq((model:GetPosition()), z0 - 10, "untere Grenze")
      H.eq(view.count("SetUnit"), 0, "Zoomen laedt nicht neu")
   end)

   H.test("Drehknoepfe: Druecken dreht sofort einen Schritt und stetig, Loslassen/Verlassen beendet", function()
      local T, P, view, _, frame = make()
      local model = P.model
      local left, right = buttonByLabel(frame, "<"), buttonByLabel(frame, ">")
      H.eq(updateFramesUnder(frame), 0)

      -- kurzer Klick: ein kleiner Schritt (auch ohne OnUpdate)
      M.Click(left, "LeftButton")
      H.near(angle(view), 0.61 - 0.1, 1e-9)
      H.eq(updateFramesUnder(frame), 0)

      -- gehalten: sofort 0,1 rad, danach 10 Takte zu 0,05 s mit 1,6 rad/s
      local f0 = view.facing
      mouseDown(right, "LeftButton")
      H.eq(updateFramesUnder(frame), 1, "OnUpdate nur waehrend des Haltens")
      H.near(view.facing - f0, 0.1, 1e-9, "sofortiger Schritt")
      M.Advance(0.5, 0.05)
      H.near(view.facing - f0, 0.1 + 0.8, 1e-9)
      mouseUp(right, "LeftButton")
      H.eq(updateFramesUnder(frame), 0)
      local f1 = view.facing
      M.Advance(0.3, 0.05)
      H.near(view.facing, f1, 1e-9, "nach dem Loslassen Ruhe")

      -- Zeiger verlaesst den Knopf: Drehen endet
      M.Enter(left)
      mouseDown(left, "LeftButton")
      M.Advance(0.2, 0.05)
      M.Leave(left)
      H.eq(updateFramesUnder(frame), 0)
      local f2 = view.facing
      M.Advance(0.3, 0.05)
      H.near(view.facing, f2, 1e-9)
      mouseUp(left, "LeftButton")
      H.eq(model:GetFacing(), view.facing)
   end)

   H.test("Reset: Drehung 0.61 und Ausgangsposition, ohne SetUnit", function()
      local T, P, view, _, frame = make()
      local model = P.model
      setCursor(0, 0)
      mouseDown(model, "LeftButton")
      setCursor(300, 0)
      M.Advance(0.05, 0.05)
      mouseUp(model, "LeftButton")
      M.Wheel(model, 1)
      M.Wheel(model, 1)
      H.truthy(math.abs(angle(view) - 0.61) > 0.1)
      view.clear()

      M.Click(buttonByLabel(frame, "Reset view"), "LeftButton")
      H.eq(angle(view), 0.61)
      H.eq(view.last("SetRotation")[2], 0.61)
      H.deepEq(view.position, { 0, 0, 0 })
      H.eq(view.count("SetUnit"), 0)
   end)

   H.test("Fokus Umhang: dreht nach hinten, anderer Platz zurueck; manuelle Drehung beendet das Zurueckschnappen", function()
      local T, P, view = make()
      P.SetFocusSlot(SLOT.BACK)
      H.eq(angle(view), 3.2, "Umhang von hinten (Cameras: BACK 3.2)")
      H.eq(view.count("SetFacing"), 0, "Umhangansicht per SetRotation wie die Zellenmodelle")
      P.SetFocusSlot(SLOT.HEAD)
      H.eq(angle(view), 0.61, "zurueck zur vorherigen Drehung")

      -- nach manueller Drehung kein Zurueckschnappen
      P.SetFocusSlot(SLOT.BACK)
      H.eq(angle(view), 3.2)
      setCursor(0, 0)
      mouseDown(P.model, "LeftButton")
      setCursor(34, 0)
      M.Advance(0.05, 0.05)
      mouseUp(P.model, "LeftButton")
      H.near(angle(view), 4.2, 1e-9)
      P.SetFocusSlot(SLOT.HEAD)
      H.near(angle(view), 4.2, 1e-9, "vom Spieler gedreht: bleibt")

      -- Rebuild bewahrt die Drehung
      P.Rebuild()
      H.near(angle(view), 4.2, 1e-9)
   end)

   H.test("Fokus Umhang schon vor dem ersten Aufbau: das Modell startet von hinten", function()
      local T, P, view = make({ noBuild = true })
      P.SetFocusSlot(SLOT.BACK)
      H.eq(#view.calls, 0, "vor dem Aufbau nichts am Modell")
      P.Refresh()
      H.eq(angle(view), 3.2)
      P.SetFocusSlot(SLOT.HEAD)
      H.eq(angle(view), 0.61)
   end)

   H.test("Fokus Umhang laesst sich abschalten (Preview.autoFocus = false)", function()
      local T, P, view = make()
      P.autoFocus = false
      P.SetFocusSlot(SLOT.BACK)
      H.eq(angle(view), 0.61)
   end)

   -- ======================================================================
   H.section("Rebuild und Groesse")
   -- ======================================================================

   H.test("Rebuild: SetUnit erneut, Facing und Position bleiben, Verfolgung wird neu aufgebaut", function()
      local T, P, view = make()
      local State = T.State
      State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      settle()
      -- Kamera aendern: Ziehen, Rechtsziehen, Rad
      setCursor(0, 0)
      mouseDown(P.model, "LeftButton")
      setCursor(68, 0)
      M.Advance(0.05, 0.05)
      mouseUp(P.model, "LeftButton")
      mouseDown(P.model, "RightButton")
      setCursor(113, 45)
      M.Advance(0.05, 0.05)
      mouseUp(P.model, "RightButton")
      M.Wheel(P.model, 1)
      local facing = angle(view)
      local pos = { P.model:GetPosition() }
      H.near(facing, 0.61 + 2, 1e-9)
      view.clear()

      P.Rebuild()
      H.eq(view.names()[1], "SetUnit")
      H.eq(view.count("SetUnit"), 1)
      H.near(angle(view), facing, 1e-9, "Drehung erhalten")
      H.deepEq(view.position, pos, "Position erhalten")
      -- das ausstehende Aussehen liegt wieder auf dem frisch geladenen Modell
      H.deepEq(tryIds(view), { lookId(SLOT.HEAD, 1) })
      -- und danach ist wieder Ruhe
      view.clear()
      P.Refresh()
      H.eq(#view.calls, 0)
   end)

   H.test("Rebuild unsichtbar: wird beim Zeigen nachgeholt (einmal)", function()
      local T, P, view, parent = make()
      parent:Hide()
      P.Rebuild()
      settle(0.3)
      H.eq(#view.calls, 0)
      parent:Show()
      settle(0.3)
      H.eq(view.count("SetUnit"), 1)
   end)

   H.test("Verstecken und Zeigen: einmal SetUnit mit erhaltener Kamera, Aussehen wieder aufgelegt", function()
      local T, P, view, parent = make()
      T.State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 2))
      settle()
      P.model:SetFacing(2.0)
      P.model:SetPosition(2, 0.25, -0.25)
      view.clear()

      parent:Hide()
      settle(0.3)
      H.eq(#view.calls, 0, "versteckt: keine Modellaufrufe")
      parent:Show()
      settle(0.3)
      H.eq(view.count("SetUnit"), 1)
      H.eq(view.facing, 2.0)
      H.deepEq(view.position, { 2, 0.25, -0.25 })
      H.deepEq(tryIds(view), { lookId(SLOT.HEAD, 2) })

      -- ein Wechsel waehrend das Fenster zu ist, wird beim Zeigen beruecksichtigt
      parent:Hide()
      T.State.Select(SLOT.SHOULDER, lookId(SLOT.SHOULDER, 1))
      settle(0.3)
      view.clear()
      parent:Show()
      settle(0.3)
      H.eq(view.count("SetUnit"), 1)
      H.deepEq(tryIds(view), { lookId(SLOT.HEAD, 2), lookId(SLOT.SHOULDER, 1) })
   end)

   H.test("Groessenaenderung: SetUnit nach Ruhe; ruft das Fenster Rebuild, bleibt es bei einem SetUnit", function()
      local T, P, view = make()
      P.Layout(260, 440)
      H.eq(view.count("SetUnit"), 0, "nicht mitten in der Groessenaenderung")
      P.Layout(280, 460)
      settle(0.2)
      H.eq(view.count("SetUnit"), 0)
      settle(0.3)
      H.eq(view.count("SetUnit"), 1, "nach Ruhe: Projektion neu")

      view.clear()
      P.Layout(300, 480)
      P.Rebuild()                 -- wie Window nach OnMouseUp
      settle(1.0)
      H.eq(view.count("SetUnit"), 1, "Rebuild des Fensters verbraucht die Groessenmarke")

      view.clear()
      P.Layout(300, 480)          -- gleiche Groesse: nichts
      settle(1.0)
      H.eq(view.count("SetUnit"), 0)
   end)

   -- ======================================================================
   H.section("Ereignisse")
   -- ======================================================================

   H.test("WANTED_CHANGED/STATUS_CHANGED/EQUIPMENT_CHANGED/LIST_READY: ein entprellter Durchlauf", function()
      local T, P, view = make()
      T.State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      for _ = 1, 10 do
         T.Events.Fire("WANTED_CHANGED", SLOT.HEAD)
         T.Events.Fire("STATUS_CHANGED")
      end
      H.eq(#view.calls, 0)
      settle()
      H.deepEq(view.names(), { "TryOn" })

      -- Status ueber die Leitung: angewendetes Aussehen taucht auf
      view.clear()
      sendStatus(T, { [SLOT.WAIST] = lookId(SLOT.WAIST, 2) })
      settle()
      H.deepEq(tryIds(view), { lookId(SLOT.WAIST, 2) })
   end)

   H.test("Unsichtbar: Ereignisse laden nichts; beim Zeigen wird nachgeholt", function()
      local T, P, view, parent = make()
      parent:Hide()
      T.State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 2))
      settle(0.3)
      H.eq(#view.calls, 0)
      H.eq(T.Util.Cancel("ui-preview"), false, "kein Timer haengt")
      parent:Show()
      settle(0.3)
      H.deepEq(tryIds(view), { lookId(SLOT.HEAD, 2) })
   end)

   -- ======================================================================
   H.section("Tooltips, Texte, Hygiene")
   -- ======================================================================

   H.test("Tooltips der Knoepfe: Drehen links/rechts, Reset mit Bedienhilfe", function()
      local T, P, view, _, frame = make()
      local left, right, reset = buttonByLabel(frame, "<"), buttonByLabel(frame, ">"), buttonByLabel(frame, "Reset view")
      M.Enter(left)
      H.truthy(hasLine(tipLines(), "Rotate left"))
      M.Leave(left)
      M.Enter(right)
      H.truthy(hasLine(tipLines(), "Rotate right"))
      M.Leave(right)
      M.Enter(reset)
      local lines = tipLines()
      H.truthy(hasLine(lines, "Reset view"))
      H.truthy(hasLine(lines, "Drag with the left mouse button: rotate"))
      H.truthy(hasLine(lines, "Mouse wheel: zoom"))
      M.Leave(reset)
   end)

   H.test("Sprachwechsel: ApplyLocale ohne Fehler, Beschriftung bleibt Englisch ohne Uebersetzung", function()
      local T, P, view, _, frame = make()
      T.Locale.Add("xxXX", { T_ONLY = "x" })   -- Pruefsprache ohne Texte der Vorschau
      T.Locale.Set("xxXX")
      settle()
      H.truthy(buttonByLabel(frame, "Reset view"))
      H.eq(#M.errors, 0)
   end)

   H.test("Hygiene: keine fehlenden Locale-Schluessel, kein OnUpdate im Leerlauf, keine Handlerfehler", function()
      local T, P, view, _, frame = make()
      T.State.Select(SLOT.HEAD, HIDDEN)
      T.State.Select(SLOT.OFFHAND, lookId(SLOT.OFFHAND, 1))
      settle(0.3)
      P.SetFocusSlot(SLOT.BACK)
      P.SetFocusSlot(SLOT.RANGED)
      P.SetFocusSlot(nil)
      P.ResetCamera()
      P.Rebuild()
      settle(0.5)
      for _, b in ipairs(M.Find(frame, "Button")) do
         M.Enter(b)
         M.Leave(b)
      end
      local missing = {}
      for key in pairs(T.L.__missing) do
         if string.find(key, "^PREVIEW_") then missing[#missing + 1] = key end
      end
      H.deepEq(missing, {}, "fehlende PREVIEW_-Schluessel")
      H.eq(updateFramesUnder(frame), 0)
      H.eq(#M.errors, 0)
   end)

   H.test("Zufallsfolge: beliebige Auswahlen, Verborgen, Fokuswechsel und Rebuilds werfen nie", function()
      local T, P, view = make({ focus = SLOT.MAINHAND })
      local State = T.State
      local seed = 12345
      local function rnd(n)
         seed = (seed * 1103515245 + 12345) % 2147483648
         return (seed % n) + 1
      end
      for _ = 1, 150 do
         local slot = ORDER[rnd(#ORDER)]
         local what = rnd(8)
         if what == 1 then
            State.Select(slot, HIDDEN)
         elseif what == 2 then
            State.Select(slot, 0)
         elseif what <= 4 then
            State.Select(slot, lookId(slot, rnd(5)))
         elseif what == 5 then
            State.Discard(slot)
         elseif what == 6 then
            P.SetFocusSlot(ORDER[rnd(#ORDER)])
         elseif what == 7 then
            P.Rebuild()
         else
            State.DiscardAll()
         end
         M.Advance(0.05, 0.05)
      end
      settle(0.5)
      H.eq(#M.errors, 0)

      -- Endzustand: Modell entspricht dem Wunsch, ein weiteres Refresh aendert nichts
      view.clear()
      P.Refresh()
      H.eq(#view.calls, 0, "Zustand stabil")
   end)

   -- ======================================================================
   H.section("Verifikation: Ergebnisbild gegen Wunschzustand und alten Algorithmus")
   -- ======================================================================

   -- Was zeigt das Modell? Nachbildung der DressUpModel-Semantik von 3.3.5a
   -- (nur das, worauf sich der alte Code stuetzt):
   --   SetUnit("player")  echte Ausruestung plus die vom Server angewendeten Aussehen
   --   Undress()          leert ALLE Plaetze, auch beide Haende
   --   TryOn(id)          legt id auf den Platz ihres INVTYPE; jede einhaendige Waffe
   --                      und jede Fernkampfwaffe landet in der RECHTEN Hand
   --                      (zuletzt angeprobiert gewinnt), nur Schild/Held/Nebenhand links
   -- TryOn eines nicht gecachten Gegenstands ist ein Fehler der Nachbildung (der
   -- Client kann dabei haengen): so faellt jede solche Anprobe sofort auf.
   local SIM_ARMOR = {
      INVTYPE_HEAD = 0, INVTYPE_SHOULDER = 2, INVTYPE_BODY = 3, INVTYPE_CHEST = 4,
      INVTYPE_ROBE = 4, INVTYPE_WAIST = 5, INVTYPE_LEGS = 6, INVTYPE_FEET = 7,
      INVTYPE_WRIST = 8, INVTYPE_HAND = 9, INVTYPE_CLOAK = 14, INVTYPE_TABARD = 18,
   }
   local SIM_LEFT = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }
   local ARMOR_SLOTS = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 18 }

   -- Gegenstandsdaten (equipLoc) ueber den Cache des Addons
   local function locOf(T, id)
      local info = T.Items.Info(id)
      return info and info.equipLoc or nil
   end

   -- Was zeigt SetUnit("player")? (echtes Aussehen laut Server)
   local function unitLook(T, slot)
      if T.State.SlotState(slot) == "EMPTY" then return nil end
      local base = T.State.Baseline(slot)
      if base == HIDDEN then return nil end
      if base ~= 0 then return base end
      local eq = T.State.Equipped(slot)
      return eq and eq.id or nil
   end

   local function newSim(T, lenient)
      local sim = { armor = {}, R = nil, L = nil, tries = 0, uncached = 0 }
      function sim.setUnit()
         sim.armor = {}
         for _, s in ipairs(ARMOR_SLOTS) do sim.armor[s] = unitLook(T, s) end
         sim.R = unitLook(T, SLOT.MAINHAND)
         sim.L = unitLook(T, SLOT.OFFHAND)
      end
      function sim.undress()
         sim.armor, sim.R, sim.L = {}, nil, nil
      end
      function sim.tryOn(id)
         local loc = locOf(T, id)
         if loc == nil then
            if lenient then
               sim.uncached = sim.uncached + 1      -- der alte Algorithmus fragt den Cache nie
               return
            end
            error("Sim: TryOn mit nicht gecachtem Gegenstand " .. tostring(id))
         end
         sim.tries = sim.tries + 1
         if SIM_ARMOR[loc] ~= nil then
            sim.armor[SIM_ARMOR[loc]] = id
         elseif SIM_LEFT[loc] then
            sim.L = id
         else
            sim.R = id          -- Waffen und Fernkampf: rechte Hand
         end
      end
      -- Aufrufprotokoll abspielen (nur die Aufrufe, die das Bild aendern)
      function sim.replay(calls)
         for _, c in ipairs(calls) do
            if c[1] == "SetUnit" then sim.setUnit()
            elseif c[1] == "Undress" then sim.undress()
            elseif c[1] == "TryOn" then sim.tryOn(c[2])
            end
         end
      end
      return sim
   end

   -- Wunsch des Spielers fuer einen Platz (nil = nichts zu sehen)
   local function wantLook(T, slot)
      local st = T.State.SlotState(slot)
      if st == "EMPTY" then return nil end
      local eq = T.State.Equipped(slot)
      local id = eq and eq.id or nil
      if st == "NEVER" then return id end
      local want = T.State.Wanted(slot)
      if want == HIDDEN then return nil end
      if want ~= 0 then return want end
      return id
   end

   -- Soll-Bild: focus = bearbeiteter Slot (Fernkampf nur bei Bearbeitung in der Hand;
   -- eine ausstehende einhaendige Nebenhandwaffe nur bei Bearbeitung der Nebenhand,
   -- dann liegt sie in der rechten Hand: zuletzt angeprobiert gewinnt).
   -- Rs = zulaessige Werte der rechten Hand; LOK = linke Hand ist beurteilbar
   local function ideal(T, focus)
      local out = { armor = {} }
      for _, s in ipairs(ARMOR_SLOTS) do out.armor[s] = wantLook(T, s) end
      local main, ranged = wantLook(T, SLOT.MAINHAND), wantLook(T, SLOT.RANGED)
      local eqR = T.State.Equipped(SLOT.RANGED)
      out.Rs = { [main or 0] = true }
      out.R = main
      out.RANY = (main == nil)        -- ohne Nahkampfwaffe darf (Undress-Weg, SPEC 9.1) ein Fernkampf liegen
      if focus == SLOT.RANGED and ranged ~= nil and T.State.SlotState(SLOT.RANGED) == "READY" then
         if eqR and ranged ~= eqR.id then
            out.Rs = { [ranged] = true }       -- ein vom Original abweichender Look liegt in der Hand
            out.R = ranged
         else
            out.Rs[ranged] = true              -- unveraendert: beides ist in Ordnung
         end
      end
      out.L = wantLook(T, SLOT.OFFHAND)
      local loc = out.L and locOf(T, out.L) or nil
      out.LOK = (out.L == nil) or SIM_LEFT[loc] == true
      if focus == SLOT.OFFHAND and out.L ~= nil and loc ~= nil and not SIM_LEFT[loc]
         and T.State.HasPending(SLOT.OFFHAND) then
         -- Nebenhandwaffe in Bearbeitung: sie ersetzt die Haupthand in der Vorschau
         out.Rs = { [out.L] = true }
         out.R = out.L
         out.RANY = false
      end
      return out
   end

   -- Vergleich; Rueckgabe: nil (gleich) oder Text der ersten Abweichung
   local function diffLook(sim, want)
      for _, s in ipairs(ARMOR_SLOTS) do
         if sim.armor[s] ~= want.armor[s] then
            return string.format("Platz %d zeigt %s, gewollt %s", s, tostring(sim.armor[s]), tostring(want.armor[s]))
         end
      end
      if not want.RANY and not want.Rs[sim.R or 0] then
         return string.format("rechte Hand zeigt %s, gewollt %s", tostring(sim.R), tostring(want.R))
      end
      if want.LOK and sim.L ~= want.L then
         return string.format("linke Hand zeigt %s, gewollt %s", tostring(sim.L), tostring(want.L))
      end
      return nil
   end

   -- Wortgetreue Portierung von OLD/ui/slots_model.lua RefreshPreviewModel
   -- (Client-Slots durch Server-Slots ersetzt; gleiche Reihenfolge, gleiche Regeln).
   local OLD_ORDER = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }
   local function oldRefresh(st, calls)
      local hidden = false
      for slotId, id in pairs(st.toServer) do
         if id == HIDDEN and st.fromServer[slotId] ~= HIDDEN then hidden = true end
      end
      if not hidden then
         if st.undressed then
            calls[#calls + 1] = { "SetUnit", "player" }
            st.undressed = false
            st.tried = {}
         end
         st.tried = st.tried or {}
         for _, slotId in ipairs(OLD_ORDER) do
            local effective = st.toServer[slotId]
            if not effective or effective == 0 then effective = st.equipped[slotId] end
            local differs
            local tried = st.tried[slotId]
            if tried then
               differs = effective ~= tried
            else
               local applied = st.fromServer[slotId]
               differs = effective ~= st.equipped[slotId] or (applied and applied ~= 0 and applied ~= effective)
            end
            if effective and effective ~= 0 and differs and effective ~= HIDDEN then
               local skip = slotId == SLOT.RANGED and st.current ~= SLOT.RANGED
               if slotId == SLOT.OFFHAND then
                  local loc = st.locOf(effective)
                  if loc ~= "INVTYPE_SHIELD" and loc ~= "INVTYPE_HOLDABLE" and loc ~= "INVTYPE_WEAPONOFFHAND" then
                     skip = true
                  end
               end
               if not skip then
                  calls[#calls + 1] = { "TryOn", effective }
                  st.tried[slotId] = effective
               end
            end
         end
         return
      end
      st.undressed = true
      calls[#calls + 1] = { "Undress" }
      local order = {}
      for _, slotId in ipairs(OLD_ORDER) do
         if slotId ~= SLOT.RANGED then order[#order + 1] = slotId end
      end
      if st.current == SLOT.RANGED then
         order[#order + 1] = SLOT.RANGED
      else
         table.insert(order, 1, SLOT.RANGED)
      end
      for _, slotId in ipairs(order) do
         local effective = st.toServer[slotId]
         if not effective or effective == 0 then effective = st.equipped[slotId] end
         if effective and effective ~= 0 and effective ~= HIDDEN then
            calls[#calls + 1] = { "TryOn", effective }
         end
      end
   end

   -- nur die Aufrufe, die das Bild bestimmen, als Text: "Undress TryOn(1017) ..."
   local function callsText(calls)
      local out = {}
      for _, c in ipairs(calls) do
         if c[1] == "TryOn" then
            out[#out + 1] = "TryOn(" .. tostring(c[2]) .. ")"
         elseif c[1] == "SetUnit" or c[1] == "Undress" then
            out[#out + 1] = c[1]
         end
      end
      return table.concat(out, " ")
   end

   -- Sitzung mit Bildverfolgung: neues Addon (echte Ereignisse) und alter Algorithmus
   -- (einmal je Aktion, wie das alte Addon) laufen nebeneinander.
   --   opts wie make(); opts.focus = bearbeiteter Slot beim Aufbau
   local function simSession(opts)
      opts = opts or {}
      local o = {}
      for k, v in pairs(opts) do o[k] = v end
      o.noBuild = true
      local T, P, view, parent, frame = make(o)
      if opts.cache == false then
         M.world.itemCacheDelay = 100000      -- Gegenstaende treffen nur per M.CacheItem ein
      end
      local S = { T = T, P = P, view = view, parent = parent, frame = frame, focus = opts.focus }
      S.sim = newSim(T)
      S.oldSim = newSim(T, true)
      S.old = { toServer = {}, fromServer = {}, equipped = {}, tried = {}, undressed = false,
                current = opts.focus, locOf = function(id) return locOf(T, id) end }

      -- der alte Algorithmus bekommt den State wie das alte Addon seine Tabellen
      local function syncOld()
         for _, slot in ipairs(ORDER) do
            S.old.toServer[slot] = T.State.Wanted(slot)
            S.old.fromServer[slot] = T.State.Applied(slot)
            local eq = T.State.Equipped(slot)
            S.old.equipped[slot] = eq and eq.id or 0
         end
         S.old.current = S.focus
      end

      -- Eine Aktion ausfuehren, zur Ruhe kommen, beide Bilder nachfuehren.
      -- Rueckgabe: Aufrufe neu (Text), Aufrufe alt (Text)
      --   afterShow: das Fenster wurde neu gezeigt (alt: Reset() = SetUnit, Verfolgung leer)
      function S.step(fn, afterShow)
         if fn then fn() end
         settle(S.quiet or 0.3)
         local newText = callsText(view.calls)
         S.sim.replay(view.calls)
         view.clear()
         syncOld()
         local calls = {}
         if afterShow then
            calls[#calls + 1] = { "SetUnit", "player" }
            S.old.undressed = false
            S.old.tried = {}
         end
         oldRefresh(S.old, calls)
         S.oldSim.replay(calls)
         return newText, callsText(calls)
      end

      function S.setFocus(slot)
         S.focus = slot
         P.SetFocusSlot(slot)
      end

      -- erster Aufbau (Fenster geoeffnet)
      function S.open()
         return S.step(function() P.Refresh() end, true)
      end

      -- Bild des neuen Addons gegen das Wunschbild; nil oder Abweichung
      function S.check()
         return diffLook(S.sim, ideal(T, S.focus))
      end
      function S.checkOld()
         return diffLook(S.oldSim, ideal(T, S.focus))
      end
      return S
   end

   -- ---------------------------------------------------------------------
   -- 8+ Szenarien: Aufrufe gegen den alten Algorithmus
   -- ---------------------------------------------------------------------

   -- Waffen und Nebenhand-Gegenstaende fuer die Szenarien
   local WEAPONS = {
      [3001] = { name = "Great Axe", quality = 4, ilvl = 120, equipLoc = "INVTYPE_2HWEAPON",
                 class = "Weapon", subclass = "Two-Handed Axes", icon = "Interface\\Icons\\INV_Axe_09" },
      [3002] = { name = "Longbow", quality = 3, ilvl = 100, equipLoc = "INVTYPE_RANGED",
                 class = "Weapon", subclass = "Bows", icon = "Interface\\Icons\\INV_Weapon_Bow_05" },
      [3003] = { name = "Crossbow", quality = 3, ilvl = 100, equipLoc = "INVTYPE_RANGEDRIGHT",
                 class = "Weapon", subclass = "Crossbows", icon = "Interface\\Icons\\INV_Weapon_Crossbow_02" },
      [3004] = { name = "Spare Sword", quality = 3, ilvl = 100, equipLoc = "INVTYPE_WEAPON",
                 class = "Weapon", subclass = "One-Handed Swords", icon = "Interface\\Icons\\INV_Sword_27" },
      [3005] = { name = "Spare Shield", quality = 3, ilvl = 100, equipLoc = "INVTYPE_SHIELD",
                 class = "Armor", subclass = "Shields", icon = "Interface\\Icons\\INV_Shield_05" },
      [3006] = { name = "Spare Dagger", quality = 3, ilvl = 100, equipLoc = "INVTYPE_WEAPONOFFHAND",
                 class = "Weapon", subclass = "Daggers", icon = "Interface\\Icons\\INV_Weapon_ShortBlade_05" },
      [3007] = { name = "Spare Robe", quality = 3, ilvl = 100, equipLoc = "INVTYPE_ROBE",
                 class = "Armor", subclass = "Cloth", icon = "Interface\\Icons\\INV_Chest_Cloth_17" },
      [1116] = { name = "Equipped Dagger", quality = 3, ilvl = 100, equipLoc = "INVTYPE_WEAPON",
                 class = "Weapon", subclass = "Daggers", icon = "Interface\\Icons\\INV_Dagger_1" },
   }
   local function weaponLists(T)
      sendList(T, SLOT.MAINHAND, { 3001, 3004, lookId(SLOT.MAINHAND, 1), lookId(SLOT.MAINHAND, 2) })
      sendList(T, SLOT.OFFHAND, { 3004, 3005, 3006, lookId(SLOT.OFFHAND, 1) })
      sendList(T, SLOT.RANGED, { 3002, 3003, lookId(SLOT.RANGED, 1), lookId(SLOT.RANGED, 2) })
      sendList(T, SLOT.CHEST, { 3007, lookId(SLOT.CHEST, 1), lookId(SLOT.CHEST, 2) })
   end

   local function scenarioSession(opts)
      local o = {}
      for k, v in pairs(opts or {}) do o[k] = v end
      local items = {}
      for id, def in pairs(WEAPONS) do items[id] = def end
      for id, def in pairs((opts or {}).items or {}) do items[id] = def end
      o.items = items
      local S = simSession(o)
      weaponLists(S.T)
      return S
   end

   H.test("Szenario 1: Ruestungsteil waehlen: eine Anprobe, wie das alte Addon", function()
      local S = scenarioSession({ status = { [SLOT.CHEST] = lookId(SLOT.CHEST, 2) } })
      local n, o = S.open()
      H.eq(n, o, "Aufbau")
      H.eq(n, "SetUnit TryOn(" .. lookId(SLOT.CHEST, 2) .. ")", "SetUnit, dann das angewendete Aussehen einmal")
      H.eq(S.check(), nil)

      n, o = S.step(function() S.T.State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 3)) end)
      H.eq(n, "TryOn(" .. lookId(SLOT.HEAD, 3) .. ")")
      H.eq(n, o, "wie das alte Addon")
      H.eq(S.check(), nil)

      -- zweite Auswahl im selben Platz ersetzt die erste
      n, o = S.step(function() S.T.State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 5)) end)
      H.eq(n, "TryOn(" .. lookId(SLOT.HEAD, 5) .. ")")
      H.eq(n, o)
      H.eq(S.check(), nil)
   end)

   H.test("Szenario 2: zurueck zum Original (Verwerfen, Toggle, Auswahl 0): das echte Item wird angeprobiert", function()
      local S = scenarioSession({ status = { [SLOT.HEAD] = lookId(SLOT.HEAD, 2) } })
      S.open()
      local State = S.T.State
      -- ohne angewendetes Aussehen: Auswahl, dann Verwerfen
      local n, o = S.step(function() State.Select(SLOT.SHOULDER, lookId(SLOT.SHOULDER, 4)) end)
      H.eq(n, o)
      n, o = S.step(function() State.Discard(SLOT.SHOULDER) end)
      H.eq(n, "TryOn(" .. equipId(SLOT.SHOULDER) .. ")")
      H.eq(n, o, "Verwerfen")
      H.eq(S.check(), nil)

      -- angewendetes Aussehen entfernen vormerken (Rechtsklick)
      n, o = S.step(function() State.Toggle(SLOT.HEAD) end)
      H.eq(n, "TryOn(" .. equipId(SLOT.HEAD) .. ")")
      H.eq(n, o, "Toggle")
      H.eq(S.check(), nil)

      -- und wieder verwerfen: das angewendete Aussehen kommt zurueck
      n, o = S.step(function() State.Toggle(SLOT.HEAD) end)
      H.eq(n, "TryOn(" .. lookId(SLOT.HEAD, 2) .. ")")
      H.eq(n, o)
      H.eq(S.check(), nil)
   end)

   H.test("Szenario 3: einen Platz verbergen: Undress, Fernkampf zuerst, aufsteigend - exakt wie alt", function()
      local S = scenarioSession()
      S.open()
      local State = S.T.State
      local n, o = S.step(function() State.Select(SLOT.HEAD, HIDDEN) end)
      H.eq(n, o, "Aufrufe")
      H.truthy(string.find(n, "^Undress TryOn%(" .. equipId(SLOT.RANGED) .. "%)"), "Fernkampf zuerst: " .. n)
      H.eq(S.check(), nil)
      H.eq(S.checkOld(), nil)
      H.eq(S.sim.armor[SLOT.HEAD], nil, "Kopf ist leer")

      -- eine Auswahl im Undress-Weg: nur der geaenderte Platz (das alte Addon zog alles neu an)
      n, o = S.step(function()
         State.Select(SLOT.CHEST, lookId(SLOT.CHEST, 1))
      end)
      H.eq(n, "TryOn(" .. lookId(SLOT.CHEST, 1) .. ")", "im Undress-Weg nur der geaenderte Platz")
      H.truthy(string.find(o, "^Undress"), "alt: erneut Undress und alles")
      H.eq(S.check(), nil)
      H.eq(S.checkOld(), nil, "dasselbe Bild")
      -- ein zweiter verborgener Platz braucht ein neues Undress (wie alt)
      n, o = S.step(function() State.Select(SLOT.WAIST, HIDDEN) end)
      H.eq(n, o, "zweites Verborgen: erneut Undress")
      H.eq(S.check(), nil)
      H.eq(S.sim.armor[SLOT.WAIST], nil)
      H.eq(S.sim.armor[SLOT.HEAD], nil)
      H.eq(S.sim.armor[SLOT.CHEST], lookId(SLOT.CHEST, 1))
   end)

   H.test("Szenario 4: Verborgen wieder aufheben: SetUnit(player) und nur die Unterschiede - wie alt", function()
      local S = scenarioSession()
      S.open()
      local State = S.T.State
      S.step(function()
         State.Select(SLOT.CHEST, lookId(SLOT.CHEST, 2))
         State.Select(SLOT.HEAD, HIDDEN)
      end)
      H.eq(S.check(), nil)
      local n, o = S.step(function() State.Discard(SLOT.HEAD) end)
      H.eq(n, o, "Aufrufe")
      H.eq(n, "SetUnit TryOn(" .. lookId(SLOT.CHEST, 2) .. ")")
      H.eq(S.check(), nil)
      H.eq(S.sim.armor[SLOT.HEAD], equipId(SLOT.HEAD), "Kopf wieder da")
      -- danach Ruhe
      n = S.step(function() S.P.Refresh() end)
      H.eq(n, "")
   end)

   H.test("Szenario 5: einhaendige Waffe in der Nebenhand: nicht anprobiert (landete rechts), Hinweis", function()
      local S = scenarioSession(DUAL)
      S.open()
      local State = S.T.State
      local n, o = S.step(function() State.Select(SLOT.OFFHAND, 3004) end)
      H.eq(n, "", "keine Anprobe")
      H.eq(n, o, "wie das alte Addon")
      H.truthy(M.HasText(S.frame, "One-handed weapons in the off hand are not shown in this preview."), "Hinweis")
      H.eq(S.sim.R, equipId(SLOT.MAINHAND), "Haupthand bleibt")
      H.eq(S.check(), nil)

      -- ein Schild wird links gezeigt, die Haupthand bleibt
      n, o = S.step(function() State.Select(SLOT.OFFHAND, 3005) end)
      H.eq(n, "TryOn(3005)")
      H.eq(n, o)
      H.eq(S.sim.L, 3005)
      H.eq(S.sim.R, equipId(SLOT.MAINHAND))
      H.falsy(M.HasText(S.frame, "One-handed weapons in the off hand are not shown in this preview."))
      H.eq(S.check(), nil)

      -- danach wieder eine nicht darstellbare Waffe: der Schild bleibt nicht als Auswahl stehen
      n, o = S.step(function() State.Select(SLOT.OFFHAND, 3004) end)
      H.eq(n, "SetUnit", "neu laden statt veralteten Schild zu zeigen")
      H.eq(o, "", "alt: der Schild blieb stehen")
      H.neq(S.sim.L, 3005, "Schild ist weg")
      H.eq(S.sim.L, 1116, "die echte Nebenhandwaffe des Spielers")
      H.eq(S.sim.R, equipId(SLOT.MAINHAND))
      H.truthy(M.HasText(S.frame, "One-handed weapons in the off hand are not shown in this preview."))
      H.eq(S.check(), nil)
      H.eq(S.oldSim.L, 3005, "alt zeigt weiter den Schild")
   end)

   H.test("Szenario 5b: Nebenhand bearbeiten: die einhaendige Waffe liegt in der Haupthand (alt: nichts), Fokus verlassen holt die Haupthand zurueck", function()
      local S = scenarioSession(DUAL)
      S.open()
      local State = S.T.State
      local n, o = S.step(function() S.setFocus(SLOT.OFFHAND) end)
      H.eq(n, "", "Fokuswechsel ohne Auswahl aendert nichts")
      H.eq(o, "")

      n, o = S.step(function() State.Select(SLOT.OFFHAND, 3004) end)
      H.eq(n, "TryOn(3004)", "die Auswahl ist in der Vorschau zu sehen")
      H.eq(o, "", "alt: keine Anprobe")
      H.eq(S.sim.R, 3004, "die Waffe liegt in der Haupthand")
      H.eq(S.sim.L, 1116, "die echte Nebenhandwaffe bleibt links")
      H.truthy(M.HasText(S.frame, NOTE_MAIN), "Hinweis: in der Haupthand")
      H.falsy(M.HasText(S.frame, NOTE_SKIP))
      H.eq(S.check(), nil)

      -- Haupthand auch ausgewaehlt: die Nebenhandwaffe gewinnt (zuletzt angeprobiert)
      n = S.step(function() State.Select(SLOT.MAINHAND, lookId(SLOT.MAINHAND, 2)) end)
      H.eq(n, "TryOn(" .. lookId(SLOT.MAINHAND, 2) .. ") TryOn(3004)")
      H.eq(S.sim.R, 3004)
      H.eq(S.check(), nil)

      -- Fokus verlassen: SetUnit, die ausgewaehlte Haupthand kommt zurueck
      n = S.step(function() S.setFocus(SLOT.CHEST) end)
      H.eq(n, "SetUnit TryOn(" .. lookId(SLOT.MAINHAND, 2) .. ")")
      H.eq(S.sim.R, lookId(SLOT.MAINHAND, 2))
      H.eq(S.sim.L, 1116)
      H.truthy(M.HasText(S.frame, NOTE_SKIP), "alter Hinweis")
      H.falsy(M.HasText(S.frame, NOTE_MAIN))
      H.eq(S.check(), nil)

      -- zurueck zur Nebenhand: nur die Anprobe, Waffe wieder rechts
      n = S.step(function() S.setFocus(SLOT.OFFHAND) end)
      H.eq(n, "TryOn(3004)")
      H.eq(S.sim.R, 3004)
      H.eq(S.check(), nil)

      -- Schild: Neuaufbau, danach Schild links, Haupthand zurueck
      n = S.step(function() State.Select(SLOT.OFFHAND, 3005) end)
      H.eq(n, "SetUnit TryOn(" .. lookId(SLOT.MAINHAND, 2) .. ") TryOn(3005)")
      H.eq(S.sim.L, 3005)
      H.eq(S.sim.R, lookId(SLOT.MAINHAND, 2))
      H.eq(S.check(), nil)
   end)

   H.test("Szenario 5c: Nebenhand bearbeiten im Undress-Weg: Waffe nach der Haupthand, Fokus verlassen: voller Durchlauf ohne sie", function()
      local S = scenarioSession(DUAL)
      S.open()
      local State = S.T.State
      S.step(function() S.setFocus(SLOT.OFFHAND) end)
      S.step(function() State.Select(SLOT.OFFHAND, 3004) end)
      local n = S.step(function() State.Select(SLOT.HEAD, HIDDEN) end)
      H.truthy(string.find(n, "^Undress"), n)
      H.truthy(string.find(n, "TryOn%(" .. equipId(SLOT.MAINHAND) .. "%) TryOn%(3004%)"),
         "Haupthand, dann die Nebenhandwaffe: " .. n)
      H.eq(S.sim.R, 3004)
      H.eq(S.sim.armor[SLOT.HEAD], nil, "Kopf ist leer")
      H.eq(S.check(), nil)

      n = S.step(function() S.setFocus(SLOT.CHEST) end)
      H.truthy(string.find(n, "^Undress"), n)
      H.falsy(string.find(n, "TryOn%(3004%)"), "nicht mehr angeprobiert")
      H.eq(S.sim.R, equipId(SLOT.MAINHAND))
      H.eq(S.check(), nil)
   end)

   H.test("Szenario 6: Zweihandwaffe in der Haupthand: eine Anprobe, Nebenhand wird nicht angefasst", function()
      local S = scenarioSession()
      S.open()
      local State = S.T.State
      local n, o = S.step(function() State.Select(SLOT.MAINHAND, 3001) end)
      H.eq(n, "TryOn(3001)")
      H.eq(n, o)
      H.eq(S.sim.R, 3001)
      H.eq(S.check(), nil)
      -- zurueck zum Original
      n, o = S.step(function() State.Discard(SLOT.MAINHAND) end)
      H.eq(n, "TryOn(" .. equipId(SLOT.MAINHAND) .. ")")
      H.eq(n, o)
      H.eq(S.check(), nil)
   end)

   H.test("Szenario 7: Fernkampf bearbeiten: nur bei Fokus angeprobiert, beim Verlassen ist die Haupthand frei", function()
      local S = scenarioSession()
      S.open()
      local State = S.T.State
      -- ohne Fokus: nichts (Fernkampf deckte die Nahkampfwaffe)
      local n, o = S.step(function() State.Select(SLOT.RANGED, 3002) end)
      H.eq(n, "")
      H.eq(n, o)
      H.eq(S.sim.R, equipId(SLOT.MAINHAND))

      -- Fokus: der Bogen liegt in der Hand
      n, o = S.step(function() S.setFocus(SLOT.RANGED) end)
      H.eq(n, "TryOn(3002)")
      H.eq(n, o)
      H.eq(S.sim.R, 3002)
      H.eq(S.check(), nil)

      -- die Haupthand aendert sich (Outfit/Rechtsklick): der Bogen bleibt sichtbar (zuletzt gewinnt)
      n = S.step(function() State.Select(SLOT.MAINHAND, lookId(SLOT.MAINHAND, 2)) end)
      H.eq(n, "TryOn(" .. lookId(SLOT.MAINHAND, 2) .. ") TryOn(3002)", "Fernkampf kommt erneut")
      H.eq(S.sim.R, 3002)
      H.eq(S.check(), nil)

      -- Fokus verlassen: SetUnit, die Haupthandwaffe ist wieder frei
      n = S.step(function() S.setFocus(SLOT.HEAD) end)
      H.eq(n, "SetUnit TryOn(" .. lookId(SLOT.MAINHAND, 2) .. ")")
      H.eq(S.sim.R, lookId(SLOT.MAINHAND, 2))
      H.eq(S.check(), nil)
   end)

   H.test("Szenario 7b: Fernkampf bearbeitet und verlassen: der Bogen liegt nicht mehr in der Hand (alt: blieb)", function()
      local S = scenarioSession()
      S.open()
      S.step(function()
         S.T.State.Select(SLOT.RANGED, 3002)
         S.setFocus(SLOT.RANGED)
      end)
      H.eq(S.sim.R, 3002)
      local n, o = S.step(function() S.setFocus(SLOT.SHOULDER) end)
      H.eq(n, "SetUnit")
      H.eq(o, "")
      H.eq(S.sim.R, equipId(SLOT.MAINHAND), "die Nahkampfwaffe ist wieder zu sehen")
      H.eq(S.oldSim.R, 3002, "alt: der Bogen verdeckt die Haupthand weiter")
      H.eq(S.check(), nil)
   end)

   H.test("Szenario 8: nicht gecachtes Aussehen: erst Abfrage, nach ITEMS_RESOLVED die Anprobe", function()
      local S = scenarioSession({ cache = false })
      S.open()
      local State, Items = S.T.State, S.T.Items
      local id = lookId(SLOT.HEAD, 3)
      H.eq(Items.Info(id), nil)
      local n = S.step(function() State.Select(SLOT.HEAD, id) end)
      H.eq(n, "", "ungecacht: keine Anprobe")
      H.truthy(Items.PendingCount() >= 1)
      M.CacheItem(id)
      n = S.step(function() M.Advance(1.0, 0.05) end)
      H.eq(n, "TryOn(" .. id .. ")")
      H.eq(S.check(), nil)
   end)

   H.test("Szenario 9: Doppelwaffentraeger: Haupthandwechsel fasst die Nebenhand nie an", function()
      local S = scenarioSession(DUAL)
      S.open()
      local State = S.T.State
      local n, o = S.step(function() State.Select(SLOT.MAINHAND, lookId(SLOT.MAINHAND, 1)) end)
      H.eq(n, "TryOn(" .. lookId(SLOT.MAINHAND, 1) .. ")")
      H.eq(n, o)
      H.eq(S.sim.L, 1116, "Nebenhandwaffe bleibt")
      H.eq(S.check(), nil)
      -- Verborgen irgendwo: die einhaendige Nebenhandwaffe geht im Undress-Weg verloren (bekannte Grenze)
      n, o = S.step(function() State.Select(SLOT.SHOULDER, HIDDEN) end)
      H.eq(S.sim.R, lookId(SLOT.MAINHAND, 1), "die Haupthand bleibt")
      H.eq(S.check(), nil)
      H.truthy(string.find(o, "TryOn%(1116%)"), "alt: die Nebenhandwaffe wurde angeprobiert ...")
      H.eq(S.oldSim.R, 1116, "... und ersetzte die Haupthand")
   end)

   H.test("Szenario 10: angewendetes Verborgen: ein anderes Aussehen waehlen und verwerfen zeigt es wieder verborgen", function()
      local S = scenarioSession({ status = { [SLOT.CHEST] = HIDDEN } })
      S.open()
      local State = S.T.State
      H.eq(S.sim.armor[SLOT.CHEST], nil, "Server zeigt die Brust verborgen")
      S.step(function() State.Select(SLOT.CHEST, lookId(SLOT.CHEST, 1)) end)
      H.eq(S.sim.armor[SLOT.CHEST], lookId(SLOT.CHEST, 1))
      local n, o = S.step(function() State.Discard(SLOT.CHEST) end)
      H.eq(n, "SetUnit", "nur SetUnit zeigt das angewendete Verborgen wieder")
      H.eq(S.sim.armor[SLOT.CHEST], nil)
      H.eq(S.check(), nil)
      H.eq(o, "", "alt: die Brust bliebe sichtbar")
      H.eq(S.checkOld() ~= nil, true)
   end)

   H.test("Szenario 11: Status vom Server (Alles entfernen): Modell zeigt die echten Gegenstaende wieder", function()
      local S = scenarioSession({ status = { [SLOT.HEAD] = lookId(SLOT.HEAD, 2), [SLOT.LEGS] = HIDDEN } })
      S.open()
      H.eq(S.sim.armor[SLOT.HEAD], lookId(SLOT.HEAD, 2))
      H.eq(S.sim.armor[SLOT.LEGS], nil)
      S.step(function() sendStatus(S.T, {}) end)
      H.eq(S.sim.armor[SLOT.HEAD], equipId(SLOT.HEAD))
      H.eq(S.sim.armor[SLOT.LEGS], equipId(SLOT.LEGS), "verborgene Beine kommen zurueck")
      H.eq(S.check(), nil)
   end)

   H.test("Szenario 12: Robe in der Brust: eine Anprobe, Beine bleiben unberuehrt", function()
      local S = scenarioSession()
      S.open()
      local n, o = S.step(function() S.T.State.Select(SLOT.CHEST, 3007) end)
      H.eq(n, "TryOn(3007)")
      H.eq(n, o)
      H.eq(S.sim.armor[SLOT.LEGS], equipId(SLOT.LEGS))
      H.eq(S.check(), nil)
   end)

   H.test("Szenario 13: Platz wird verborgen, der Spieler legt dort einen anderen Gegenstand an", function()
      local items = {}
      for id, def in pairs(WEAPONS) do items[id] = def end
      items[1100] = { name = "New Helm", quality = 4, ilvl = 120, equipLoc = "INVTYPE_HEAD",
                      class = "Armor", subclass = "Plate", icon = "Interface\\Icons\\INV_Helmet_99" }
      local S = scenarioSession({ items = items })
      S.open()
      local State = S.T.State
      S.step(function() State.Select(SLOT.SHOULDER, HIDDEN) end)
      H.eq(S.sim.armor[SLOT.SHOULDER], nil)
      -- neuer Helm: das Modell wird mit dem neuen Gegenstand neu geladen, die Schulter bleibt verborgen
      S.step(function()
         M.world.equipment[SLOT.HEAD + 1] = 1100
         M.CacheAll()
         M.Fire("PLAYER_EQUIPMENT_CHANGED", SLOT.HEAD + 1)
      end)
      H.eq(S.sim.armor[SLOT.HEAD], 1100, "neuer Helm sichtbar")
      H.eq(S.sim.armor[SLOT.SHOULDER], nil, "Schulter bleibt verborgen")
      H.eq(S.check(), nil)
   end)

   -- ---------------------------------------------------------------------
   -- Zufallsfolgen: nach jeder Ruhephase muss das Bild dem Wunsch entsprechen
   -- ---------------------------------------------------------------------

   -- Eine Zufallsfolge; Rueckgabe: Liste der Abweichungen vom Wunschbild.
   --   opts.uncached  Gegenstaende laufen erst nach und nach ein
   --   opts.equip     Ausruestungswechsel mischen sich ein
   local function randomRun(seed, steps, opts)
      opts = opts or {}
      local sess = {}
      if opts.uncached then sess.cache = false end
      sess.items = WEAPONS
      local S = simSession(sess)
      weaponLists(S.T)
      -- Anfragen verfallen nach 20 s (Items): kurze Schritte, damit nichts aufgegeben wird
      if opts.uncached then S.quiet = 0.12 end
      local T, P = S.T, S.P
      local State = T.State
      local rs = seed
      local function rnd(n)
         rs = (rs * 1103515245 + 12345) % 2147483648
         return (math.floor(rs / 65536) % n) + 1
      end
      local hideable = { [0]=1, [2]=1, [3]=1, [4]=1, [5]=1, [6]=1, [7]=1, [8]=1, [9]=1, [14]=1, [18]=1 }
      local bad = {}
      local function lookFor(slot)
         if slot == SLOT.MAINHAND then
            local pool = { lookId(slot, 1), lookId(slot, 2), 3001, 3004 }
            return pool[rnd(#pool)]
         elseif slot == SLOT.OFFHAND then
            local pool = { lookId(slot, 1), 3004, 3005, 3006 }
            return pool[rnd(#pool)]
         elseif slot == SLOT.RANGED then
            local pool = { lookId(slot, 1), lookId(slot, 2), 3002, 3003 }
            return pool[rnd(#pool)]
         end
         return lookId(slot, rnd(5))
      end
      S.open()
      for step = 1, steps do
         local slot = ORDER[rnd(#ORDER)]
         if S.focus ~= nil and rnd(10) <= 7 then slot = S.focus end
         local what = rnd(24)
         local desc
         local afterShow = false
         local fn
         if what <= 8 then
            desc = "Select " .. slot .. " Aussehen"
            fn = function() State.Select(slot, lookFor(slot)) end
         elseif what <= 10 then
            if hideable[slot] then
               desc = "Select " .. slot .. " Verborgen"
               fn = function() State.Select(slot, HIDDEN) end
            else
               desc = "Select " .. slot .. " Original"
               fn = function() State.Select(slot, 0) end
            end
         elseif what == 11 then
            desc = "Select " .. slot .. " Original"
            fn = function() State.Select(slot, 0) end
         elseif what <= 13 then
            desc = "Discard " .. slot
            fn = function() State.Discard(slot) end
         elseif what == 14 then
            desc = "Toggle " .. slot
            fn = function() State.Toggle(slot) end
         elseif what == 15 then
            desc = "DiscardAll"
            fn = function() State.DiscardAll() end
         elseif what <= 18 then
            local f = ORDER[rnd(#ORDER)]
            desc = "Fokus " .. f
            fn = function() S.setFocus(f) end
         elseif what == 19 then
            local map = {}
            for _ = 1, rnd(4) do
               local sl = ORDER[rnd(#ORDER)]
               if rnd(6) == 1 and hideable[sl] then map[sl] = HIDDEN else map[sl] = lookFor(sl) end
            end
            desc = "Status"
            fn = function() sendStatus(T, map) end
         elseif what == 20 then
            desc = "Fenster zu/auf"
            afterShow = true
            fn = function()
               S.parent:Hide()
               settle(0.1)
               S.parent:Show()
            end
         elseif what == 21 then
            desc = "Rebuild"
            afterShow = true
            fn = function() P.Rebuild() end
         elseif what == 22 and opts.equip then
            local pick = rnd(3)
            desc = "Ausruestung " .. slot .. " " .. pick
            fn = function()
               if pick == 1 then
                  M.world.equipment[slot + 1] = nil
               elseif pick == 2 then
                  M.world.equipment[slot + 1] = equipId(slot)
               else
                  M.world.equipment[slot + 1] = lookId(slot, 5)
               end
               M.CacheItem(lookId(slot, 5))
               M.Fire("PLAYER_EQUIPMENT_CHANGED", slot + 1)
            end
         elseif opts.uncached then
            desc = "Gegenstaende laufen ein"
            fn = function()
               for _ = 1, rnd(6) do
                  M.CacheItem(lookFor(ORDER[rnd(#ORDER)]))
               end
            end
         else
            desc = "Liste " .. slot
            fn = function()
               local ids = {}
               for i = 1, 5 do ids[i] = lookId(slot, i) end
               if slot == SLOT.MAINHAND then ids[#ids + 1] = 3001; ids[#ids + 1] = 3004 end
               sendList(T, slot, ids)
            end
         end
         S.step(fn, afterShow)
         if not opts.uncached then
            local d = S.check()
            if d then bad[#bad + 1] = string.format("Folge %d Schritt %d (%s): %s", seed, step, desc, d) end
         end
      end
      if opts.uncached then
         -- alles trifft ein: danach muss das Bild stimmen
         S.step(function()
            M.CacheAll()
            M.Advance(2.0, 0.05)
         end)
         local d = S.check()
         if d then bad[#bad + 1] = string.format("Folge %d am Ende: %s", seed, d) end
      end
      return bad, S
   end

   H.test("Zufallsfolgen: Auswahl, Verborgen, Fokus, Status, Fenster zu/auf - das Bild entspricht stets dem Wunsch", function()
      local all = {}
      for seed = 1, 30 do
         local bad = randomRun(seed * 7919, 70)
         for _, m in ipairs(bad) do all[#all + 1] = m end
      end
      H.deepEq(all, {}, "Abweichungen vom Wunschbild")
   end)

   H.test("Zufallsfolgen mit Ausruestungswechseln: das Bild entspricht stets dem Wunsch", function()
      local all = {}
      for seed = 1, 20 do
         local bad = randomRun(seed * 104729, 70, { equip = true })
         for _, m in ipairs(bad) do all[#all + 1] = m end
      end
      H.deepEq(all, {}, "Abweichungen vom Wunschbild")
   end)

   H.test("Zufallsfolgen mit nachladenden Gegenstaenden: nie ein TryOn ohne Cache, am Ende stimmt das Bild", function()
      local all = {}
      for seed = 1, 15 do
         local bad = randomRun(seed * 15485863, 60, { uncached = true })
         for _, m in ipairs(bad) do all[#all + 1] = m end
      end
      H.deepEq(all, {}, "Abweichungen vom Wunschbild")
      H.eq(#M.errors, 0)
   end)

   -- ---------------------------------------------------------------------
   -- Ansicht (Drehung/Position) in beiden Deutungen der Engine
   -- ---------------------------------------------------------------------

   -- Die Attrappe fuehrt Rotation und Facing getrennt. Hier wird sie so
   -- umgestellt, dass SetRotation das Facing ueberschreibt (ein Winkel) und
   -- SetUnit beide verwirft: jeder sichtbare Winkel muss in beiden Deutungen
   -- derselbe sein.
   local function aliasedModel(model)
      local rawSetRotation = model.SetRotation
      model.SetRotation = function(self, r)
         rawSetRotation(self, r)
         self.__facing = r
      end
   end

   for _, mode in ipairs({ "getrennt", "ein Winkel" }) do
      H.test("Ansicht (" .. mode .. "): Start 0.61, Ziehen, Rebuild, Umhang hinten, Zurueck, Reset", function()
         local T, P, view = make({ noBuild = true })
         if mode == "ein Winkel" then aliasedModel(P.model) end
         local function shown()
            if mode == "ein Winkel" then return view.facing end
            return angle(view)
         end
         P.Refresh()
         settle(0.2)
         H.near(shown(), 0.61, 1e-9, "Start")

         -- ziehen
         setCursor(0, 0)
         mouseDown(P.model, "LeftButton")
         setCursor(68, 0)
         M.Advance(0.05, 0.05)
         mouseUp(P.model, "LeftButton")
         H.near(shown(), 0.61 + 2, 1e-9, "gezogen")

         -- Rebuild: SetUnit verwirft beides, die Ansicht bleibt
         P.Rebuild()
         H.near(shown(), 0.61 + 2, 1e-9, "nach Rebuild")

         -- Reset
         P.ResetCamera()
         H.near(shown(), 0.61, 1e-9, "nach Reset")

         -- Umhang: von hinten, danach zurueck zur vorherigen Ansicht
         mouseDown(P.model, "LeftButton")
         setCursor(102, 0)
         M.Advance(0.05, 0.05)
         mouseUp(P.model, "LeftButton")
         local before = shown()
         P.SetFocusSlot(SLOT.BACK)
         if mode == "ein Winkel" then
            H.near(view.facing, 3.2, 1e-9, "Umhang von hinten")
         else
            H.near(view.rotation, 3.2, 1e-9, "Umhang von hinten (die Drehung des Spielers bleibt als Anteil)")
         end
         P.SetFocusSlot(SLOT.CHEST)
         H.near(shown(), before, 1e-9, "zurueck zur vorherigen Ansicht")
         H.eq(#M.errors, 0)
      end)
   end

   -- ---------------------------------------------------------------------
   -- Maus: ein verlorenes OnMouseUp darf das Modell nicht weiterdrehen
   -- ---------------------------------------------------------------------

   H.test("Maus: wird die Taste ausserhalb losgelassen (OnMouseUp bleibt aus), endet das Ziehen von selbst", function()
      local T, P, view, _, frame = make()
      setCursor(0, 0)
      mouseDown(P.model, "LeftButton")
      setCursor(34, 0)
      M.Advance(0.05, 0.05)
      H.near(angle(view), 1.61, 1e-9)
      H.eq(updateFramesUnder(frame), 1)
      -- Taste ist nicht mehr gedrueckt, aber das Modell hat kein OnMouseUp bekommen
      M.world.mouseDown = nil
      setCursor(200, 0)
      M.Advance(0.05, 0.05)
      H.near(angle(view), 1.61, 1e-9, "keine weitere Drehung")
      H.eq(updateFramesUnder(frame), 0, "OnUpdate ist weg")
      setCursor(400, 0)
      M.Advance(0.2, 0.05)
      H.near(angle(view), 1.61, 1e-9)
   end)

   H.test("Maus: Rechtsklick-Ziehen dreht nicht; die falsche Taste beendet das Ziehen nicht", function()
      local T, P, view = make()
      setCursor(0, 0)
      mouseDown(P.model, "RightButton")
      M.world.mouseDown.LeftButton = true       -- eine zweite Taste kommt dazu
      setCursor(45, 0)
      M.Advance(0.05, 0.05)
      local _, x = P.model:GetPosition()
      H.near(x, 1, 1e-9, "verschoben")
      H.near(angle(view), 0.61, 1e-9, "nicht gedreht")
      mouseUp(P.model, "RightButton")
   end)

   -- ---------------------------------------------------------------------
   -- Ereignisse: Buendel, nur sichtbar, kein Leerlauf
   -- ---------------------------------------------------------------------

   H.test("Ereignisbuendel: 300 Ereignisse in einer Ruhephase ergeben genau einen Durchlauf", function()
      local T, P, view = make()
      local State = T.State
      State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      State.Select(SLOT.SHOULDER, lookId(SLOT.SHOULDER, 2))
      for i = 1, 100 do
         T.Events.Fire("WANTED_CHANGED", nil)
         T.Events.Fire("STATUS_CHANGED")
         T.Events.Fire("LIST_READY", SLOT.HEAD)
      end
      H.eq(#view.calls, 0, "nichts sofort")
      settle(0.2)
      H.deepEq(tryIds(view), { lookId(SLOT.HEAD, 1), lookId(SLOT.SHOULDER, 2) }, "ein Durchlauf, jede Anprobe einmal")
      view.clear()
      settle(0.5)
      H.eq(#view.calls, 0, "danach Ruhe")
      H.eq(T.Util.Cancel("ui-preview"), false, "kein Timer haengt")
   end)

   H.test("Wiederholtes Create und Layout: idempotent, kein zweites Modell, keine Frames sammeln sich", function()
      local T, P, view, parent, frame = make()
      local before = #M.Find(frame, "Button") + #M.Find(frame, "DressUpModel") + #M.Find(frame, "Frame")
      for _ = 1, 5 do
         H.eq(P.Create(parent), frame)
         P.Layout(230, 400)
         frame:Layout(230, 400)
      end
      local after = #M.Find(frame, "Button") + #M.Find(frame, "DressUpModel") + #M.Find(frame, "Frame")
      H.eq(after, before)
   end)

   H.test("Sprachwechsel: Reset-Knopf, Hinweis und Tooltips erscheinen in der neuen Sprache, ohne Neuaufbau", function()
      local T, P, view, _, frame = make(DUAL)
      T.Locale.Add("xxXX", {
         PREVIEW_RESET = "Ansicht zuruecksetzen",
         PREVIEW_RESET_TIP = "Setzt Drehung, Position und Zoom zurueck.",
         PREVIEW_OFFHAND_NOTE = "Nebenhandwaffen werden in dieser Vorschau nicht gezeigt.",
         PREVIEW_ROTATE_LEFT = "Nach links drehen",
      })
      sendList(T, SLOT.OFFHAND, { 2161, 2162, 2163, 2164 })
      T.State.Select(SLOT.OFFHAND, 2161)
      settle()
      H.truthy(M.HasText(frame, "One-handed weapons in the off hand are not shown in this preview."))
      H.truthy(buttonByLabel(frame, "Reset view"))
      view.clear()

      T.Locale.Set("xxXX")
      settle(0.3)
      H.truthy(buttonByLabel(frame, "Ansicht zuruecksetzen"), "Reset-Knopf uebersetzt")
      H.falsy(buttonByLabel(frame, "Reset view"))
      H.truthy(M.HasText(frame, "Nebenhandwaffen werden in dieser Vorschau nicht gezeigt."), "Hinweis uebersetzt")
      H.eq(#view.calls, 0, "ein Sprachwechsel laedt das Modell nicht neu")

      -- Tooltips entstehen beim Zeigen in der aktuellen Sprache
      M.Enter(buttonByLabel(frame, "<"))
      H.truthy(hasLine(tipLines(), "Nach links drehen"))
      M.Leave(buttonByLabel(frame, "<"))
      M.Enter(buttonByLabel(frame, "Ansicht zuruecksetzen"))
      H.truthy(hasLine(tipLines(), "Setzt Drehung, Position und Zoom zurueck."))
      -- fehlende Uebersetzung: Rueckfall auf Englisch statt Schluessel
      H.truthy(hasLine(tipLines(), "Mouse wheel: zoom"))
      M.Leave(buttonByLabel(frame, "Ansicht zuruecksetzen"))

      -- und zurueck
      T.Locale.Set("enUS")
      settle(0.3)
      H.truthy(buttonByLabel(frame, "Reset view"))
      H.eq(#M.errors, 0)
   end)

   H.test("Nackter Charakter und stummer Server: nur SetUnit, keine Anprobe, Auswahlen werden abgelehnt", function()
      local naked = {}
      for _, slot in ipairs(ORDER) do naked[slot] = false end
      local T, P, view = make({ equip = naked, noLists = true })
      H.eq(view.count("TryOn"), 0)
      for _, slot in ipairs(ORDER) do
         H.eq(T.State.SlotState(slot), "EMPTY")
         H.falsy(T.State.Select(slot, lookId(slot, 1)), "leerer Platz " .. slot)
         H.falsy(T.State.Select(slot, HIDDEN))
      end
      P.SetFocusSlot(SLOT.RANGED)
      P.SetFocusSlot(SLOT.BACK)
      settle(0.3)
      H.eq(view.count("TryOn"), 0)
      H.eq(view.count("Undress"), 0)
      H.eq(#M.errors, 0)
      -- nach dem Anlegen eines Gegenstands wird er (als Teil von SetUnit) gezeigt, nichts angeprobiert
      M.world.equipment[SLOT.HEAD + 1] = equipId(SLOT.HEAD)
      M.Fire("PLAYER_EQUIPMENT_CHANGED", SLOT.HEAD + 1)
      settle(0.4)
      H.eq(view.count("SetUnit"), 1)
      H.eq(view.count("TryOn"), 0)
   end)

   H.test("Fehlerrobustheit: ein Fehler in einer Anprobe stoert weder Ereignisse noch spaetere Durchlaeufe", function()
      local T, P, view = make()
      local State = T.State
      -- TryOn schlaegt einmal fehl (z. B. Client-Fehler): der naechste Durchlauf laeuft normal
      local model = P.model
      local original = model.TryOn
      local failures = 1
      model.TryOn = function(self, id)
         if failures > 0 then
            failures = failures - 1
            error("TryOn kaputt")
         end
         return original(self, id)
      end
      State.Select(SLOT.HEAD, lookId(SLOT.HEAD, 1))
      settle(0.2)
      local errs = H.takeErrors()
      H.truthy(#errs >= 1, "der Fehler wurde gemeldet, nicht verschluckt")
      model.TryOn = original
      State.Select(SLOT.SHOULDER, lookId(SLOT.SHOULDER, 2))
      settle(0.2)
      H.truthy(indexOf(tryIds(view), lookId(SLOT.SHOULDER, 2)), "der naechste Durchlauf laeuft")
   end)

   -- ---------------------------------------------------------------------
   -- Im echten Fenster (Fixtures: Katalog, Server, alle Komponenten)
   -- ---------------------------------------------------------------------

   -- Alle bisherigen Modellaufrufe nachfuehren (das Modell entstand mit dem Fenster)
   local function followModel(FX)
      local view = M.Model(FX.UI.Preview.model)
      local sim = newSim(FX)
      local function sync()
         sim.replay(view.calls)
         view.clear()
      end
      return sim, view, sync
   end

   H.test("Im Fenster: Slot waehlen, Aussehen klicken, Rechtsklick, Umhang, Anwenden - die Vorschau zeigt stets den Wunsch", function()
      local Fixtures = require("fixtures")
      local FX = Fixtures.Boot(H, { locale = "enUS", equipmentSet = "dualwield" })
      Fixtures.ServerHello(FX)
      local srv = Fixtures.ServerAutoReply(FX)
      local Win, State = FX.UI.Window, FX.State
      Fixtures.OpenAtNpc(FX)
      Fixtures.Settle(FX, 1.0)
      H.truthy(Win.IsShown())
      local sim, view, sync = followModel(FX)
      sync()
      local function expectWanted(label)
         Fixtures.Settle(FX, 0.6)
         sync()
         H.eq(diffLook(sim, ideal(FX, Win.currentSlot)), nil, label)
      end
      expectWanted("nach dem Oeffnen")
      H.eq(view.count("Undress"), 0)

      -- Aussehen im Raster waehlen
      local grid = FX.UI.Grid
      -- erste Zelle mit einem Aussehen, das nicht schon angewendet ist
      local function firstCell()
         for _, cell in ipairs(grid.cells or {}) do
            if cell:IsShown() and cell.kind == "item" and cell.itemId
               and cell.itemId ~= State.Baseline(Win.currentSlot) then
               return cell
            end
         end
         return nil
      end
      local cell = firstCell()
      H.truthy(cell, "eine Zelle")
      local id = cell.itemId
      M.Click(cell)
      H.eq(State.Wanted(Win.currentSlot), id)
      expectWanted("Aussehen gewaehlt")
      H.truthy(sim.armor[Win.currentSlot] == id or sim.R == id, "das gewaehlte Aussehen ist zu sehen")

      -- Slot der Brust waehlen und dort ebenso
      local bar = FX.UI.SlotBar.Get()
      M.Click(bar.buttons[SLOT.CHEST])
      H.eq(Win.currentSlot, SLOT.CHEST)
      cell = firstCell()
      M.Click(cell)
      expectWanted("Brust")
      H.eq(State.PendingCount(), 2)

      -- Rechtsklick auf den Kopf-Knopf verwirft die Auswahl des Kopfes
      M.Click(bar.buttons[SLOT.HEAD], "RightButton")
      expectWanted("Kopf verworfen")
      H.eq(State.PendingCount(), 1)

      -- Verborgen auf der Schulter (Undress-Weg), dann verwerfen
      M.Click(bar.buttons[SLOT.SHOULDER])
      State.Select(SLOT.SHOULDER, HIDDEN)
      expectWanted("Schulter verborgen")
      H.eq(sim.armor[SLOT.SHOULDER], nil)
      State.Discard(SLOT.SHOULDER)
      expectWanted("Schulter wieder da")
      H.truthy(sim.armor[SLOT.SHOULDER] ~= nil)

      -- Umhang: Ansicht von hinten (Rotation 3.2), Rechtsklick hat die Auswahl nicht veraendert
      M.Click(bar.buttons[SLOT.BACK])
      Fixtures.Settle(FX, 0.3)
      H.eq(view.rotation, 3.2, "Umhang von hinten")
      M.Click(bar.buttons[SLOT.HEAD])
      Fixtures.Settle(FX, 0.3)
      H.eq(view.rotation, 0.61, "zurueck")

      -- Alles anwenden: der Server antwortet, das Bild bleibt, nichts wird neu gezogen
      local f = Win.frame
      local before = view.count("SetUnit")
      M.Click(f.btnApply)
      Fixtures.Settle(FX, 2.0)
      sync()
      H.eq(State.PendingCount(), 0)
      H.eq(diffLook(sim, ideal(FX, Win.currentSlot)), nil, "nach dem Anwenden")
      H.eq(#M.errors, 0)

      -- Fenster zu und wieder auf: SetUnit, danach dasselbe Bild
      Win.Close()
      Fixtures.Settle(FX, 0.5)
      Win.Open({ fromNpc = true })
      expectWanted("wieder geoeffnet")
      H.truthy(srv ~= nil)
   end)

   H.test("Im Fenster: Groessenaenderung und Scale - ein SetUnit nach Ruhe, Seitenverhaeltnis und Kamera bleiben", function()
      local Fixtures = require("fixtures")
      local FX = Fixtures.Boot(H, { locale = "enUS", screen = { w = 1920, h = 1080 } })
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX)
      local Win = FX.UI.Window
      Win.Open({ fromNpc = true, slot = SLOT.HEAD })
      Fixtures.Settle(FX, 1.0)
      local model = FX.UI.Preview.model
      local view = M.Model(model)
      -- Kamera veraendern
      setCursor(0, 0)
      mouseDown(model, "LeftButton")
      setCursor(68, 0)
      M.Advance(0.05, 0.05)
      mouseUp(model, "LeftButton")
      M.Wheel(model, 1)
      local total = angle(view)
      local pos = { model:GetPosition() }
      view.clear()

      for _, size in ipairs({ { 740, 520 }, { 1000, 700 }, { 880, 600 } }) do
         FX.DB.Set("width", size[1])
         FX.DB.Set("height", size[2])
         Fixtures.Settle(FX, 1.0)
         H.truthy(view.count("SetUnit") >= 1, "Modell neu geladen bei " .. size[1] .. "x" .. size[2])
         H.truthy(view.count("SetUnit") <= 2, "nicht mehrfach: " .. view.count("SetUnit"))
         view.clear()
         H.near(model:GetWidth() / model:GetHeight(), 221 / 362, 1e-6, "Seitenverhaeltnis")
         H.near(angle(view), total, 1e-9, "Drehung bleibt")
         H.deepEq({ model:GetPosition() }, pos, "Position bleibt")
      end
      FX.DB.Set("scale", 1.3)
      Fixtures.Settle(FX, 1.0)
      H.truthy(view.count("SetUnit") >= 1, "Scale: neu geladen")
      H.near(angle(view), total, 1e-9)
      H.eq(#M.errors, 0)
   end)

   H.test("Im Fenster: beide Nebenhand-Hinweise passen in allen Sprachen in ihr Feld (3 Zeilen, 36 px), nichts ragt heraus", function()
      local Fixtures = require("fixtures")
      local Layout = require("layout")
      local langs = { "enUS", "deDE", "frFR", "esES", "ruRU", "koKR", "zhCN", "zhTW" }
      for _, code in ipairs(langs) do
         local FX = Fixtures.Boot(H, { locale = "enUS", addonLocale = code, equipmentSet = "dualwield",
                                       screen = { w = 1920, h = 1080 } })
         Fixtures.ServerHello(FX)
         Fixtures.ServerAutoReply(FX)
         local Win, Pv = FX.UI.Window, FX.UI.Preview
         FX.DB.Set("width", 740)                 -- Mindestgroesse: die schmalste Vorschau
         FX.DB.Set("height", 520)
         Win.Open({ fromNpc = false, slot = SLOT.OFFHAND })
         Fixtures.Settle(FX, 0.8)

         -- eine einhaendige Waffe der Nebenhandliste (kein Schild/Held/Nebenhandwaffe)
         local weapon
         for _, id in ipairs(FX.State.List(SLOT.OFFHAND).ids) do
            local info = FX.Items.Info(id)
            local loc = info and info.equipLoc or ""
            if loc ~= "INVTYPE_SHIELD" and loc ~= "INVTYPE_HOLDABLE" and loc ~= "INVTYPE_WEAPONOFFHAND" then
               weapon = id
               break
            end
         end
         H.truthy(weapon, code .. ": eine einhaendige Waffe in der Nebenhandliste")
         if weapon then
            H.truthy(FX.State.Select(SLOT.OFFHAND, weapon), code .. ": Auswahl")
            Fixtures.Settle(FX, 0.5)
            local mainText = FX.L.PREVIEW_OFFHAND_NOTE_MAINHAND
            H.truthy(M.HasText(Pv.frame, mainText), code .. ": Hinweis 'in der Haupthand' sichtbar")
            H.neq(mainText, "PREVIEW_OFFHAND_NOTE_MAINHAND", code .. ": uebersetzt")

            local function check(label)
               local entries = Layout.Rects(Win.frame)
               local problems = Layout.Check(entries, {})
               for _, p in ipairs(problems) do
                  local path = p.path or ""
                  if string.find(path, "/left/") and p.severity ~= "info" then
                     H.fail(string.format("%s %s: %s %s %s", code, label, tostring(p.severity), tostring(p.kind), path))
                  end
               end
               local note = nil
               for _, o in ipairs(M.Find(Pv.frame, "FontString")) do
                  local t = o:GetText()
                  if o:IsVisible() and (t == FX.L.PREVIEW_OFFHAND_NOTE_MAINHAND or t == FX.L.PREVIEW_OFFHAND_NOTE) then
                     note = o
                  end
               end
               H.truthy(note, code .. " " .. label .. ": Hinweisfeld")
               if note then
                  H.eq(note:GetHeight(), 36, code .. " " .. label .. ": Hoehe")
                  -- das Feld gehoert zur geprueften Flaeche (text-clipped/text-too-wide wuerden es melden)
                  local e = Layout.Find(entries, note)
                  H.truthy(e and string.find(e.path or "", "/left/", 1, true), code .. " " .. label .. ": im Layout erfasst")
               end
            end
            check("in der Haupthand")

            -- Fokus woanders: der alte Hinweis (Auswahl steht aus)
            Pv.SetFocusSlot(SLOT.HEAD)
            Fixtures.Settle(FX, 0.5)
            H.truthy(M.HasText(Pv.frame, FX.L.PREVIEW_OFFHAND_NOTE), code .. ": alter Hinweis sichtbar")
            check("uebersprungen")
         end
      end
      H.eq(#M.errors, 0)
   end)

   H.test("Im Fenster: Layoutpruefung der Vorschau (deDE, Minimum/Standard/gross): nichts ragt heraus, keine Textueberlaeufe", function()
      local Fixtures = require("fixtures")
      local Layout = require("layout")
      local FX = Fixtures.Boot(H, { locale = "deDE", equipmentSet = "dualwield", screen = { w = 1920, h = 1080 } })
      Fixtures.ServerHello(FX)
      Fixtures.ServerAutoReply(FX)
      local Win = FX.UI.Window
      for _, size in ipairs({ { 740, 520 }, { 880, 600 }, { 1200, 800 } }) do
         FX.DB.Set("width", size[1])
         FX.DB.Set("height", size[2])
         Win.Close()
         Win.Open({ fromNpc = false, slot = SLOT.OFFHAND })
         Fixtures.Settle(FX, 0.8)
         -- ausstehende Nebenhandwaffe: der Hinweis ist sichtbar (lange Texte)
         local ids = FX.State.List(SLOT.OFFHAND).ids
         if #ids > 0 then FX.State.Select(SLOT.OFFHAND, ids[1]) end
         Fixtures.Settle(FX, 0.5)
         local entries = Layout.Rects(Win.frame)
         local problems = Layout.Check(entries, {})
         for _, p in ipairs(problems) do
            local path = p.path or ""
            if string.find(path, "/left/") and p.severity ~= "info" then
               H.fail(string.format("%dx%d: %s %s %s", size[1], size[2], tostring(p.severity), tostring(p.kind), path))
            end
         end
         -- das Modell liegt in der Buehne, die Knoepfe darunter
         local pv = Layout.Find(entries, FX.UI.Preview.frame)
         local md = Layout.Find(entries, FX.UI.Preview.model)
         H.truthy(pv and md, "Eintraege")
         if pv and md then
            H.truthy(md.x >= pv.x - 1e-6 and md.x + md.w <= pv.x + pv.w + 1e-6, "Breite innerhalb")
            H.truthy(md.y >= pv.y - 1e-6 and md.y + md.h <= pv.y + pv.h - FX.UI.Preview.CONTROLS_HEIGHT * pv.scale + 1e-6,
               "Hoehe innerhalb der Buehne")
         end
      end
      H.eq(#M.errors, 0)
   end)
end
