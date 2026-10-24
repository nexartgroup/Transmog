-- tests/test_ui_toasts.lua
-- ---------------------------------------------------------------------------
-- Tests fuer Features/Toasts.lua (T.Toasts) mit den ECHTEN Kernmodulen
-- (Items, Net, State, DB): ein "CollectionUpdated" des Servers laeuft ueber
-- Net.Handle -> State -> COLLECTION_UPDATED -> Toast. Die Zeit stellt
-- M.Advance vor (GetTime, OnUpdate, Util-Timer, Item-Poll).
--
--   Lebenszyklus   Einblenden 0,2 s, Stehen 4 s, Ausblenden 0,4 s, Karte
--                  zurueck in den Pool, danach kein OnUpdate mehr
--   Ausloeser      Einstellung aus, Login-Sweep, doppelte IDs
--   Stapel         hoechstens 3 sichtbar, Rest wartet, Reihenfolge, Plaetze
--   Bursts         >= 4 Ereignisse in 2 s -> EINE Sammelkarte, zaehlt weiter
--   Iteninfo       Warten bis aufgeloest / 3 s, Name wird nachgetragen
--   Anker          Standardposition, Ziehen speichert toastPoint, Wiederherstellung,
--                  Rechtsklick setzt zurueck, Probekarte bleibt solange er sichtbar ist
--   Sonstiges      Pool, Idempotenz, Sprache, Hover/Klick, Robustheit
--   Verifikation   Lebensdauer bei 5-144 Bildern/s, gleichmaessiges Ein-/Aus-
--                  blenden, Falten der Warteschlange ohne Verlust, keine
--                  Iteninfo-Abfragen fuer Sammelereignisse, Positionsmodus,
--                  Fehler im Takt (einmal melden, aufraeumen), beschaedigte
--                  Position, Spielersicht (deDE, Katalog, Server), Layout,
--                  Zufallsfolgen mit festen Startwerten
--
-- Aufruf:  cd <Addon>;  luajit tests/run.lua ui_toasts
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   local TEST_ID = 19019

   -- -----------------------------------------------------------------------
   -- Gegenstaende und Sitzung
   -- -----------------------------------------------------------------------

   local function item(name, quality, icon)
      return {
         name = name, quality = quality, ilvl = 100, minLevel = 0,
         class = "Armor", subclass = "Plate", equipLoc = "INVTYPE_CHEST",
         icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
      }
   end

   local function itemTable()
      local t = {}
      for i = 1, 30 do
         t[5000 + i] = item("Appearance " .. i, (i % 2 == 0) and 4 or 3, "Interface\\Icons\\INV_Test_" .. i)
      end
      t[TEST_ID] = item("Thunderfury, Blessed Blade of the Windseeker", 5, "Interface\\Icons\\INV_Sword_39")
      return t
   end

   -- Startet eine Sitzung. opts: globals (gespeicherte Variablen), sweep (true:
   -- der Login-Sweep laeuft noch), uncached (Liste von IDs, die nicht im
   -- Client-Cache liegen sollen; Standard: alles ausser TEST_ID ist gecacht).
   local function start(opts)
      opts = opts or {}
      local T = H.boot({
         world = { locale = opts.locale or "enUS", equipment = {} },
         items = itemTable(),
         globals = opts.globals,
         login = true,
         enterWorld = false,
      })
      H.assert(type(T) == "table" and type(T.Toasts) == "table", "Features\\Toasts.lua wurde nicht geladen")

      if not (T.DB.global and T.DB.char) then
         T.DB.Init()
         T.Locale.Set(T.DB.global.locale)
         T.RefreshPlayerInfo()
         T.Slots.Init()
         T.Items.Init()
         T.Net.Init()
         T.State.Init()
         T.Outfits.Init()
      end
      T.Tooltips.Init()
      T.Toasts.Init()

      M.CacheAll()
      M.UncacheItem(TEST_ID)
      for _, id in ipairs(opts.uncached or {}) do M.UncacheItem(id) end

      if opts.sweep then
         T.enteredWorldAt = GetTime()
      else
         T.enteredWorldAt = GetTime() - 60
      end
      return T
   end

   local function settle(seconds)
      M.Advance(seconds, 0.05)
   end

   -- Server meldet ein neu gesammeltes Aussehen
   local function emit(T, id)
      return T.Net.Handle("CollectionUpdated:" .. id)
   end

   -- Alle sichtbaren Karten (Frames, die einen Titel zeigen), oberste zuerst
   local function cards()
      local out = {}
      local T = _G.Transmog
      M.Walk(UIParent, function(o)
         if o:GetObjectType() == "FontString" and o:IsVisible() then
            local t = o:GetText()
            if t == T.L.TOAST_TITLE or t == T.L.TOAST_BURST_TITLE then
               out[#out + 1] = o:GetParent()
            end
         end
      end)
      table.sort(out, function(a, b) return (a.ty or 0) > (b.ty or 0) end)
      return out
   end

   local function nameOf(card) return card.name:GetText() end
   local function titleOf(card) return card.title:GetText() end

   local function stats(T) return T.Toasts.Stats() end

   -- Ankerrahmen der Toasts (nur nach ShowAnchor/erster Karte vorhanden)
   local function anchorFrame() return _G.TransmogToastAnchor end

   -- ======================================================================
   -- Lebenszyklus
   -- ======================================================================

   H.test("Lebenszyklus: Sammelzeit, Einblenden, Stehen, Ausblenden, danach leer und ohne OnUpdate", function()
      local T = start()
      emit(T, 5002)                           -- Qualitaet 4 (episch)
      H.eq(#cards(), 0, "sofort noch keine Karte (kurze Sammelzeit gegen Bursts)")

      settle(0.1)
      H.eq(#cards(), 0, "nach 0,1 s noch nicht")
      settle(0.25)
      local list = cards()
      H.eq(#list, 1, "nach 0,35 s ist die Karte da")
      local card = list[1]

      -- Inhalt
      H.eq(T.L.TOAST_TITLE, "New appearance unlocked")
      H.eq(titleOf(card), "New appearance unlocked")
      H.eq(nameOf(card), "Appearance 2")
      local r, g, b = T.Util.QualityColor(4)
      local nr, ng, nb = card.name:GetTextColor()
      H.near(nr, r, 0.01, "Name in Qualitaetsfarbe r")
      H.near(ng, g, 0.01, "Name in Qualitaetsfarbe g")
      H.near(nb, b, 0.01, "Name in Qualitaetsfarbe b")
      H.eq(card.icon:GetTexture(), "Interface\\Icons\\INV_Test_2", "Symbol des Gegenstands")
      local ulx = card.icon:GetTexCoord()
      H.near(ulx, 0.07, 0.001, "Symbol beschnitten (Skin.TrimIcon)")
      H.eq(card:GetWidth(), 260)
      H.eq(card:GetHeight(), 52)
      H.eq(card.icon:GetWidth(), 36)
      H.eq(card.icon:GetHeight(), 36)

      local tr, tg, tb = card.title:GetTextColor()
      H.near(tr, T.COLORS.accent[1], 0.01, "Titel in Akzentfarbe")
      H.near(tg, T.COLORS.accent[2], 0.01)
      H.near(tb, T.COLORS.accent[3], 0.01)
      H.eq(card.title:GetWidth(), card.name:GetWidth(), "Textfelder gleich breit (geklemmt)")
      H.truthy(card.name:GetHeight() > 0 and card.title:GetHeight() > 0, "Hoehen gesetzt")

      -- Einblenden: nach insgesamt ~0,6 s voll deckend
      settle(0.3)
      H.near(card:GetAlpha(), 1, 0.001, "voll sichtbar")

      -- Stehen
      settle(3.7)       -- ~4,35 s nach dem Ereignis
      H.eq(#cards(), 1, "noch da")
      H.near(card:GetAlpha(), 1, 0.001, "noch voll sichtbar")

      -- Ausblenden
      settle(0.35)      -- ~4,70 s
      local a = card:GetAlpha()
      H.truthy(a < 1 and a >= 0, "blendet aus, alpha=" .. tostring(a))

      settle(0.5)       -- ~5,2 s
      H.eq(#cards(), 0, "weg")
      H.eq(stats(T).visible, 0)
      H.eq(stats(T).queued, 0)
      H.eq(#M.UpdateFrames(), 0, "kein OnUpdate im Leerlauf")
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Zeiten der Probekarte (ohne Sammelzeit): 0,2 s ein, 4 s stehen, 0,4 s aus", function()
      local T = start()
      T.Toasts.Test()
      local card = cards()[1]
      H.truthy(card, "sofort da")
      H.near(card:GetAlpha(), 0, 0.001, "beginnt unsichtbar")
      settle(0.1)
      H.near(card:GetAlpha(), 0.5, 0.15, "halb eingeblendet nach 0,1 s")
      settle(0.15)                                    -- 0,25 s
      H.near(card:GetAlpha(), 1, 0.001, "nach 0,2 s voll sichtbar")
      settle(3.85)                                    -- 4,10 s
      H.near(card:GetAlpha(), 1, 0.001, "steht bis 4,2 s")
      settle(0.3)                                     -- 4,40 s: 0,2 s im Ausblenden
      local a = card:GetAlpha()
      H.truthy(a > 0.3 and a < 0.7, "mitten im Ausblenden: " .. tostring(a))
      settle(0.3)                                     -- 4,70 s
      H.eq(#cards(), 0, "nach 4,6 s weg")
      H.eq(stats(T).visible, 0)
   end)

   H.test("Layout: Text bleibt im Rahmen (feste Breite/Hoehe), Symbol links, Anker-Knopf neben dem Text", function()
      local T = start()
      -- sehr langer Name (Deutsch/Russisch koennen noch laenger sein)
      M.items[5001].name = "Hammer of the Ancient Forgotten Titan Kings of the Windseeker Peaks"
      emit(T, 5001)
      settle(0.6)
      local card = cards()[1]
      H.truthy(card)

      local function leftOf(region)
         local _, _, _, x = region:GetPoint(1)
         return x
      end
      local nameLeft = leftOf(card.title)
      H.truthy(nameLeft + card.title:GetWidth() <= card:GetWidth() - 4, "Titel im Rahmen")
      H.eq(card.name:GetWidth(), card.title:GetWidth(), "Name gleich breit wie Titel")
      H.truthy(card.name:GetHeight() > 0, "Name hat feste Hoehe")
      H.truthy(nameLeft >= 12 + card.icon:GetWidth(), "Text beginnt rechts vom Symbol")
      H.truthy(card.name:GetHeight() + card.title:GetHeight() <= card:GetHeight() - 16, "Zeilen passen in die Karte")
      local sx = leftOf(card.stripe)
      H.eq(sx, 1, "Streifen am linken Rand innerhalb des 1-px-Rahmens")
      H.eq(card.stripe:GetWidth(), 3)

      T.Toasts.ShowAnchor()
      local anchor = anchorFrame()
      local label = anchor.label
      local lx = leftOf(label)
      local _, _, _, cx = anchor.close:GetPoint(1)
      -- Knopf sitzt rechts: sein linker Rand = Rahmenbreite + cx - Knopfbreite
      local closeLeft = anchor:GetWidth() + cx - anchor.close:GetWidth()
      H.truthy(lx + label:GetWidth() <= closeLeft, "Beschriftung ueberlappt den Schliessen-Knopf nicht")
   end)

   H.test("Anordnung: Karte haengt unter dem Anker (TOP/BOTTOM), Standardanker oben Mitte 120 nach unten", function()
      local T = start()
      emit(T, 5001)
      settle(0.5)
      local card = cards()[1]
      H.truthy(card, "Karte")
      local anchor = anchorFrame()
      H.truthy(anchor, "Anker wurde angelegt")
      H.falsy(anchor:IsShown(), "der Anker bleibt verborgen")

      local p, rel, relPoint, x, y = card:GetPoint(1)
      H.eq(p, "TOP")
      H.eq(rel, anchor)
      H.eq(relPoint, "BOTTOM")
      H.eq(x, 0)
      H.truthy(y < 0, "unterhalb des Ankers")

      local ap, arel, arelPoint, ax, ay = anchor:GetPoint(1)
      H.eq(ap, "TOP")
      H.eq(arel, UIParent)
      H.eq(arelPoint, "TOP")
      H.eq(ax, 0)
      H.eq(ay, -120)
      H.eq(anchor:GetWidth(), 140)
      H.eq(anchor:GetHeight(), 24)
   end)

   -- ======================================================================
   -- Ausloeser
   -- ======================================================================

   H.test("Einstellung toasts = false: keine Karte; wieder an: Karte", function()
      local T = start()
      T.DB.Set("toasts", false)
      emit(T, 5001)
      settle(1)
      H.eq(#cards(), 0)
      H.eq(stats(T).queued, 0, "auch nichts in der Warteschlange")
      H.eq(stats(T).visible, 0)
      H.eq(stats(T).created, 0, "es wurde nicht einmal eine Karte gebaut")
      settle(4)        -- der Aktualisierungstimer von State (3 s) ist durch
      H.eq(#M.UpdateFrames(), 0, "kein OnUpdate")

      T.DB.Set("toasts", true)
      emit(T, 5002)
      settle(1)
      H.eq(#cards(), 1)
   end)

   H.test("Login-Sweep: waehrend der ersten 10 s nach dem Betreten keine Karten, danach schon", function()
      local T = start({ sweep = true })
      H.eq(T.IsLoginSweep(), true)
      for id = 5001, 5012 do emit(T, id) end
      settle(1)
      H.eq(#cards(), 0, "Sweep: keine Karte")
      H.eq(stats(T).queued, 0)
      H.eq(stats(T).burst, false, "auch keine Sammelkarte")

      settle(10)
      H.eq(T.IsLoginSweep(), false)
      emit(T, 5013)
      settle(0.6)
      local list = cards()
      H.eq(#list, 1, "nach dem Sweep geht es")
      H.eq(nameOf(list[1]), "Appearance 13")
   end)

   H.test("Doppelte Meldung derselben ID ergibt eine Karte", function()
      local T = start()
      emit(T, 5001)
      emit(T, 5001)
      settle(0.5)
      emit(T, 5001)        -- jetzt sichtbar: ebenfalls ignoriert
      settle(0.5)
      H.eq(#cards(), 1)
      H.eq(stats(T).queued, 0)
   end)

   H.test("Init ist idempotent: dreimal gerufen, trotzdem eine Karte je Ereignis", function()
      local T = start()
      T.Toasts.Init()
      T.Toasts.Init()
      emit(T, 5003)
      settle(0.6)
      H.eq(#cards(), 1)
      H.eq(#M.TakeErrors(), 0)
   end)

   -- ======================================================================
   -- Stapel und Warteschlange
   -- ======================================================================

   H.test("Hoechstens 3 sichtbar, die vierte wartet und rueckt nach; Plaetze untereinander", function()
      local T = start()
      -- 0,7 s Abstand: nie 4 Ereignisse innerhalb von 2 s (kein Burst)
      for i = 1, 4 do
         emit(T, 5000 + i)
         settle(0.7)
      end
      -- ~2,8 s: drei sichtbar, einer wartet
      local list = cards()
      H.eq(#list, 3, "drei sichtbar")
      H.eq(stats(T).queued, 1, "eine wartet")
      H.eq(nameOf(list[1]), "Appearance 1", "aelteste oben")
      H.eq(nameOf(list[2]), "Appearance 2")
      H.eq(nameOf(list[3]), "Appearance 3")

      -- gleichmaessig 58 px (52 + 6) untereinander, erste 6 px unter dem Anker
      local _, _, _, _, y1 = list[1]:GetPoint(1)
      local _, _, _, _, y2 = list[2]:GetPoint(1)
      local _, _, _, _, y3 = list[3]:GetPoint(1)
      H.near(y1, -6, 0.6)
      H.near(y2, -64, 0.6)
      H.near(y3, -122, 0.6)

      -- die erste laeuft aus (ca. 4,9 s nach dem ersten Ereignis); danach ist die vierte da
      settle(2.8)
      local after = cards()
      H.eq(#after, 3, "wieder drei")
      H.eq(stats(T).queued, 0, "Warteschlange leer")
      local names = {}
      for i, c in ipairs(after) do names[i] = nameOf(c) end
      H.eq(names[3], "Appearance 4", "die vierte ist unten angekommen")
      local _, _, _, _, ny1 = after[1]:GetPoint(1)
      H.near(ny1, -6, 0.6, "die uebrigen sind nachgerueckt")

      settle(12)
      H.eq(#cards(), 0)
      H.eq(#M.UpdateFrames(), 0)
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Karten werden wiederverwendet (Pool): nie mehr als drei gebaut", function()
      local T = start()
      for round = 1, 6 do
         emit(T, 5000 + round)
         settle(6)             -- jede Karte laeuft ganz aus
      end
      H.eq(stats(T).visible, 0)
      H.eq(stats(T).created, 1, "eine einzige Karte fuer sechs aufeinanderfolgende Meldungen")
      H.eq(stats(T).pooled, 1)

      -- drei gleichzeitig
      for i = 1, 3 do
         emit(T, 5010 + i)
         settle(0.7)
      end
      settle(0.5)
      H.eq(stats(T).visible, 3)
      H.eq(stats(T).created, 3)
      settle(12)
      for i = 1, 3 do
         emit(T, 5020 + i)
         settle(0.7)
      end
      settle(0.5)
      H.eq(stats(T).created, 3, "wieder dieselben drei Karten")
   end)

   -- ======================================================================
   -- Bursts
   -- ======================================================================

   H.test("Burst: 5 Ereignisse in 0,5 s ergeben EINE Sammelkarte ohne Gegenstand", function()
      local T = start()
      for i = 1, 5 do
         emit(T, 5000 + i)
         settle(0.1)
      end
      settle(0.5)
      local list = cards()
      H.eq(#list, 1, "genau eine Karte")
      H.eq(titleOf(list[1]), T.L.TOAST_BURST_TITLE)
      H.eq(nameOf(list[1]), "Appearances: 5")
      H.eq(T.L.TOAST_BURST_TITLE, "New appearances unlocked")
      H.eq(stats(T).queued, 0)
      H.eq(stats(T).burst, true)
      H.falsy(list[1].itemId, "kein Gegenstand")
   end)

   H.test("Burst im selben Frame (ein Sweep des Servers): eine Karte, nie ein Einzelkartenflackern", function()
      local T = start()
      for id = 5001, 5012 do emit(T, id) end
      -- nichts Einzelnes wurde je gezeigt
      H.eq(stats(T).visible, 0)
      settle(0.5)
      local list = cards()
      H.eq(#list, 1)
      H.eq(nameOf(list[1]), "Appearances: 12")
   end)

   H.test("Burst: bereits gezeigte Einzelkarten werden durch die Sammelkarte ersetzt", function()
      local T = start()
      emit(T, 5001)
      settle(0.4)
      emit(T, 5002)
      settle(0.4)
      emit(T, 5003)
      settle(0.4)
      H.eq(#cards(), 3, "drei Einzelkarten (je 0,4 s Abstand)")
      emit(T, 5004)                 -- vierte innerhalb von 2 s
      settle(0.2)
      -- die Einzelkarten blenden schnell aus, die Sammelkarte erscheint
      settle(0.5)
      local list = cards()
      H.eq(#list, 1, "nur noch die Sammelkarte")
      H.eq(titleOf(list[1]), T.L.TOAST_BURST_TITLE)
      H.eq(nameOf(list[1]), "Appearances: 4")
      H.eq(stats(T).visible, 1)
   end)

   H.test("Burst: weitere Ereignisse im 2-s-Abstand zaehlen in derselben Karte weiter, danach wieder Einzelkarten", function()
      local T = start()
      for i = 1, 4 do emit(T, 5000 + i) end      -- t = 0
      settle(0.6)
      H.eq(nameOf(cards()[1]), "Appearances: 4")

      settle(1.0)                                 -- t = 1,6: 1,6 s nach dem letzten Ereignis
      emit(T, 5005)
      settle(0.1)
      local list = cards()
      H.eq(#list, 1, "weiterhin eine Karte")
      H.eq(nameOf(list[1]), "Appearances: 5")

      settle(1.5)                                 -- t = 3,2: wieder 1,6 s nach dem letzten
      emit(T, 5006)
      settle(0.1)
      H.eq(#cards(), 1)
      H.eq(nameOf(cards()[1]), "Appearances: 6")

      -- Stehzeit wird mit jedem Ereignis neu gestartet (zuletzt bei t = 3,2)
      settle(3.0)                                 -- t = 6,3
      H.eq(#cards(), 1, "Sammelkarte steht noch")
      H.near(cards()[1]:GetAlpha(), 1, 0.001)

      -- laenger als 2 s Ruhe -> Burst beendet; neues Ereignis ist wieder eine Einzelkarte
      emit(T, 5007)
      settle(0.6)
      local names = {}
      for _, c in ipairs(cards()) do names[#names + 1] = nameOf(c) end
      H.contains(names, "Appearance 7", "Einzelkarte nach dem Burst")
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Warteschlange ueber 8: wird zu einer Sammelkarte zusammengefasst, nichts geht verloren", function()
      local T = start()
      -- 0,7-s-Abstand: kein Zeitfenster-Burst; die Karten laufen langsamer aus als sie kommen
      for i = 1, 20 do
         emit(T, 5000 + i)
         settle(0.7)
         H.truthy(stats(T).queued <= 8, "Warteschlange begrenzt (" .. stats(T).queued .. ")")
         H.truthy(stats(T).visible <= 3, "hoechstens drei sichtbar")
      end
      settle(60)
      H.eq(stats(T).visible, 0)
      H.eq(stats(T).queued, 0)
      H.eq(#M.UpdateFrames(), 0)
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Einstellung aus, waehrend Eintraege warten: Warteschlange wird geleert, sichtbare laufen aus", function()
      local T = start()
      for i = 1, 4 do
         emit(T, 5000 + i)
         settle(0.7)
      end
      H.eq(stats(T).queued, 1)
      T.DB.Set("toasts", false)
      H.eq(stats(T).queued, 0)
      settle(12)
      H.eq(#cards(), 0)
   end)

   -- ======================================================================
   -- Iteninfo
   -- ======================================================================

   H.test("Iteninfo: Karte wartet auf die Aufloesung und zeigt dann den echten Namen", function()
      local T = start({ uncached = { 5005 } })
      emit(T, 5005)
      settle(0.2)
      H.eq(#cards(), 0, "noch nicht im Cache: noch keine Karte")
      settle(1)         -- Cache-Verzoegerung 0,3 s + Poll
      local list = cards()
      H.eq(#list, 1, "nach der Aufloesung")
      H.eq(nameOf(list[1]), "Appearance 5", "echter Name, nicht der Ersatz")
   end)

   H.test("Iteninfo: kommt keine Antwort, erscheint nach 3 s eine Karte mit 'Item <id>'", function()
      local T = start()
      emit(T, 777777)       -- nicht in M.items: wird nie bekannt
      settle(2.5)
      H.eq(#cards(), 0, "nach 2,5 s noch nichts")
      settle(0.9)
      local list = cards()
      H.eq(#list, 1, "nach 3 s")
      H.eq(nameOf(list[1]), "Item 777777")
      H.eq(T.L.TOAST_ITEM_UNKNOWN, "Item %d")
      -- Ersatzdarstellung: Akzentfarbe, Fragezeichen
      H.eq(list[1].icon:GetTexture(), "Interface\\Icons\\INV_Misc_QuestionMark")
      settle(10)
      H.eq(#cards(), 0)
   end)

   H.test("Test(): sofort eine Karte, auch ungecacht (Ersatzname), Name wird nachgetragen", function()
      local T = start()
      H.eq(M.IsCached(TEST_ID), false, "Voraussetzung: ungecacht")
      T.Toasts.Test()
      local list = cards()
      H.eq(#list, 1, "sofort sichtbar")
      H.eq(nameOf(list[1]), "Item 19019", "generischer Name")
      settle(1.2)
      list = cards()
      H.eq(#list, 1)
      H.eq(nameOf(list[1]), "Thunderfury, Blessed Blade of the Windseeker", "echter Name nachgetragen")
      local r = list[1].name:GetTextColor()
      H.near(r, (T.Util.QualityColor(5)), 0.01, "Qualitaetsfarbe nach dem Nachtragen")
      H.eq(list[1].icon:GetTexture(), "Interface\\Icons\\INV_Sword_39")
   end)

   H.test("Test(): ignoriert Einstellung und Login-Sweep, fasst nichts zusammen", function()
      local T = start({ sweep = true })
      T.DB.Set("toasts", false)
      for _ = 1, 3 do T.Toasts.Test() end
      H.eq(#cards(), 3, "drei Probekarten, kein Sammeln")
      H.eq(stats(T).burst, false)
      T.Toasts.Test()
      T.Toasts.Test()
      settle(0.3)
      H.eq(stats(T).visible, 3, "hoechstens drei")
      H.eq(stats(T).queued, 2)
   end)

   H.test("Show(id): reiht ohne Pruefung von Einstellung und Sweep ein", function()
      local T = start({ sweep = true })
      T.DB.Set("toasts", false)
      H.eq(T.Toasts.Show(5001), true)
      H.eq(T.Toasts.Show("nope"), false, "ungueltige ID")
      H.eq(T.Toasts.Show(0), false)
      H.eq(T.Toasts.Show("|cff0070dd|Hitem:5003:0:0:0:0:0:0:0:0|h[Appearance 3]|h|r"), true, "auch ein Item-Link")
      settle(0.6)
      H.eq(#cards(), 2)
      H.eq(nameOf(cards()[2]), "Appearance 3")
   end)

   -- ======================================================================
   -- Anker
   -- ======================================================================

   H.test("ShowAnchor: Anker sichtbar, Probekarte bleibt stehen, HideAnchor blendet sie aus", function()
      local T = start()
      T.Toasts.ShowAnchor()
      local anchor = anchorFrame()
      H.truthy(anchor, "Anker existiert")
      H.truthy(anchor:IsShown(), "Anker sichtbar")
      H.eq(#cards(), 1, "Probekarte")
      H.eq(stats(T).anchorShown, true)

      -- ein zweiter Aufruf legt keine weitere Probekarte an
      T.Toasts.ShowAnchor()
      H.eq(#cards(), 1)

      settle(8)
      H.eq(#cards(), 1, "bleibt, solange der Anker sichtbar ist")
      H.near(cards()[1]:GetAlpha(), 1, 0.001)

      T.Toasts.HideAnchor()
      H.falsy(anchor:IsShown(), "Anker versteckt")
      settle(1)
      H.eq(#cards(), 0, "Probekarte ausgeblendet")
      settle(0.2)
      H.eq(#M.UpdateFrames(), 0)
   end)

   H.test("Anker: Beschriftung 'Move me', Rahmen 140 x 24, Schliessen-Knopf", function()
      local T = start()
      T.Toasts.ShowAnchor()
      local anchor = anchorFrame()
      H.truthy(M.HasText(anchor, "Move me"), "Beschriftung")
      H.eq(T.L.TOAST_ANCHOR_LABEL, "Move me")
      H.truthy(anchor.close, "Schliessen-Knopf")
      M.Click(anchor.close)
      H.falsy(anchor:IsShown(), "Knopf schliesst den Anker")
   end)

   H.test("Anker ziehen: Position wird in DB.global.toastPoint gespeichert und angewendet", function()
      local T = start()
      T.Toasts.ShowAnchor()
      local anchor = anchorFrame()
      H.eq(T.DB.global.toastPoint, nil, "vorher keine gespeicherte Position")

      M.Drag(anchor, 100, -40)
      local saved = T.DB.global.toastPoint
      H.truthy(type(saved) == "table", "toastPoint gespeichert")
      H.eq(#saved, 4, "{point, relPoint, x, y}")
      H.eq(saved[1], "TOP")
      H.eq(saved[2], "TOP")
      local scale = anchor:GetEffectiveScale()
      H.near(saved[3], 100 / scale, 1, "x")
      H.near(saved[4], -120 - 40 / scale, 1, "y")

      local p, rel, relPoint, x, y = anchor:GetPoint(1)
      H.eq(p, saved[1])
      H.eq(rel, UIParent)
      H.eq(relPoint, saved[2])
      H.eq(x, saved[3])
      H.eq(y, saved[4])

      -- die Probekarte folgt dem Anker (an ihn gebunden)
      local _, crel = cards()[1]:GetPoint(1)
      H.eq(crel, anchor)
   end)

   H.test("Anker: gespeicherte Position ueberlebt eine neue Sitzung, Rechtsklick setzt zurueck", function()
      local T = start()
      T.Toasts.ShowAnchor()
      M.Drag(anchorFrame(), -60, 25)
      local copy = T.Util.CopyTable(T.DB.global)
      local sx, sy = copy.toastPoint[3], copy.toastPoint[4]

      -- neue Sitzung mit den gespeicherten Variablen
      local T2 = start({ globals = { TransmogGlobalDB = copy } })
      emit(T2, 5001)
      settle(0.6)
      local p, rel, relPoint, x, y = anchorFrame():GetPoint(1)
      H.eq(p, "TOP")
      H.eq(rel, UIParent)
      H.eq(relPoint, "TOP")
      H.eq(x, sx, "x wiederhergestellt")
      H.eq(y, sy, "y wiederhergestellt")
      H.eq(#cards(), 1)

      -- Rechtsklick auf den Anker: Standard
      T2.Toasts.ShowAnchor()
      M.Click(anchorFrame(), "RightButton")
      H.eq(T2.DB.global.toastPoint, nil, "gespeicherte Position geloescht")
      local _, _, _, x2, y2 = anchorFrame():GetPoint(1)
      H.eq(x2, 0)
      H.eq(y2, -120)
   end)

   H.test("Anker: unsinnige gespeicherte Position faellt auf den Standard zurueck", function()
      local T = start({ globals = { TransmogGlobalDB = { toastPoint = { "NOWHERE", "TOP", 5, 5 } } } })
      T.Toasts.ShowAnchor()
      local p, _, _, x, y = anchorFrame():GetPoint(1)
      H.eq(p, "TOP")
      H.eq(x, 0)
      H.eq(y, -120)

      -- gueltiger Anker, aber unbekannter relPoint: kein Fehler, Standard
      T.DB.Set("toastPoint", { "CENTER", "SOMEWHERE", 10, 20 })
      local p2, _, _, x2, y2 = anchorFrame():GetPoint(1)
      H.eq(p2, "TOP")
      H.eq(x2, 0)
      H.eq(y2, -120)
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Anker: DB.Set('toastPoint') von aussen verschiebt den Anker sofort", function()
      local T = start()
      T.Toasts.ShowAnchor()
      T.DB.Set("toastPoint", { "CENTER", "CENTER", 30, -10 })
      local p, _, rp, x, y = anchorFrame():GetPoint(1)
      H.eq(p, "CENTER")
      H.eq(rp, "CENTER")
      H.eq(x, 30)
      H.eq(y, -10)
   end)

   H.test("Toasts.ResetPosition: setzt auf Standard zurueck", function()
      local T = start()
      T.Toasts.ShowAnchor()
      T.DB.Set("toastPoint", { "CENTER", "CENTER", 30, -10 })
      T.Toasts.ResetPosition()
      H.eq(T.DB.global.toastPoint, nil)
      local p, _, _, x, y = anchorFrame():GetPoint(1)
      H.eq(p, "TOP")
      H.eq(x, 0)
      H.eq(y, -120)
   end)

   -- ======================================================================
   -- Hover und Klick
   -- ======================================================================

   H.test("Hover: Tooltip des Gegenstands, Zeit steht still; danach laeuft sie weiter", function()
      local T = start()
      emit(T, 5002)
      settle(0.7)
      local card = cards()[1]
      M.Enter(card)
      H.eq(GameTooltip:GetOwner(), card, "Tooltip gehoert der Karte")
      local _, link = GameTooltip:GetItem()
      H.truthy(link and link:find("item:5002", 1, true), "zeigt den Gegenstand")
      H.eq(GameTooltip:NumLines() > 0, true)

      settle(10)
      H.eq(#cards(), 1, "unter der Maus bleibt die Karte stehen")
      H.near(card:GetAlpha(), 1, 0.001)

      M.Leave(card)
      H.falsy(GameTooltip:IsShown(), "Tooltip weg")
      settle(5.2)
      H.eq(#cards(), 0, "nach dem Verlassen laeuft sie aus")
   end)

   H.test("Klick schliesst die Karte schnell; die naechste rueckt nach", function()
      local T = start()
      for i = 1, 4 do
         emit(T, 5000 + i)
         settle(0.7)
      end
      H.eq(stats(T).queued, 1)
      local first = cards()[1]
      M.Click(first)
      settle(0.3)
      local list = cards()
      H.eq(#list, 3)
      H.eq(stats(T).queued, 0, "die wartende ist nachgerueckt")
      local names = {}
      for i, c in ipairs(list) do names[i] = nameOf(c) end
      H.deepEq(names, { "Appearance 2", "Appearance 3", "Appearance 4" })
   end)

   -- ======================================================================
   -- Zusammenspiel mit Boot und Optionen (nur, wenn diese Teile vorhanden sind)
   -- ======================================================================

   H.test("Boot: Login-Sweep nach PLAYER_ENTERING_WORLD wird unterdrueckt, danach kommen Karten", function()
      local T = start()
      T.enteredWorldAt = nil          -- wie vor dem ersten Betreten
      M.Fire("PLAYER_ENTERING_WORLD")
      if T.enteredWorldAt == nil then
         T.enteredWorldAt = GetTime()   -- ohne Core\Boot.lua nachbilden
      end
      for id = 5001, 5010 do emit(T, id) end    -- der Sweep des Servers
      settle(2)
      H.eq(#cards(), 0, "waehrend des Sweeps keine Karten")
      H.eq(stats(T).burst, false)

      -- Zonenwechsel (erneutes PLAYER_ENTERING_WORLD) verlaengert das Fenster nicht
      settle(9)
      M.Fire("PLAYER_ENTERING_WORLD")
      emit(T, 5011)
      settle(0.6)
      H.eq(#cards(), 1, "nach 10 s: neues Aussehen wird gemeldet")
      H.eq(nameOf(cards()[1]), "Appearance 11")
   end)

   H.test("Boot/Optionen: '/transmog toast' zeigt den Anker, 'Test'-Knopf der Optionen eine Karte", function()
      local T = start()
      if not (T.Boot and T.UI and T.UI.Options) then
         return     -- Teilstand ohne Boot/Optionen
      end
      H.eq(M.Slash("/transmog toast"), true, "Slash-Befehl vorhanden")
      H.truthy(anchorFrame() and anchorFrame():IsShown(), "Anker sichtbar")
      T.Toasts.HideAnchor()
      settle(1)

      T.UI.Options.Open()
      local test, move
      for _, b in ipairs(M.Find(UIParent, "Button")) do
         if b.label and b:IsVisible() then
            local text = b.label:GetText()
            if text == T.L.OPT_TEST_TOAST then test = b end
            if text == T.L.OPT_MOVE_TOASTS then move = b end
         end
      end
      H.truthy(test and move, "Knoepfe der Optionen gefunden")
      if test and move then
         M.Click(test)
         H.eq(#cards(), 1, "Probekarte ueber den Optionsknopf")
         settle(6)
         H.eq(#cards(), 0)
         M.Click(move)
         H.truthy(anchorFrame():IsShown(), "Anker ueber den Optionsknopf")
         H.eq(#cards(), 1, "mit Probekarte")
      end
      H.eq(#M.TakeErrors(), 0)
   end)

   -- ======================================================================
   -- Sprache, Robustheit, Hygiene
   -- ======================================================================

   H.test("Sprachwechsel: Titel, Sammelkarte und Anker-Beschriftung folgen", function()
      local T = start()
      T.Locale.Add("deDE", {
         TOAST_TITLE = "Neues Aussehen freigeschaltet",
         TOAST_BURST_TITLE = "Neue Aussehen freigeschaltet",
         TOAST_BURST_COUNT = "Aussehen: %d",
         TOAST_ANCHOR_LABEL = "Verschiebe mich",
      })
      emit(T, 5001)
      settle(0.6)
      T.Toasts.ShowAnchor()
      local card = cards()[1]
      T.Locale.Set("deDE")
      H.eq(titleOf(card), "Neues Aussehen freigeschaltet")
      H.truthy(M.HasText(anchorFrame(), "Verschiebe mich"), "Anker")

      -- vier weitere Ereignisse: zusammen mit der sichtbaren Einzelkarte sind es 5 in 2 s
      for i = 1, 4 do emit(T, 5010 + i) end
      settle(0.6)
      local burstCard
      for _, c in ipairs(cards()) do
         if titleOf(c) == "Neue Aussehen freigeschaltet" then burstCard = c end
      end
      H.truthy(burstCard, "Sammelkarte deutsch")
      if burstCard then H.eq(nameOf(burstCard), "Aussehen: 5") end
   end)

   H.test("Robustheit: ohne Items und ohne DB keine Fehler", function()
      local T = start()
      local items = T.Items
      T.Items = nil
      emit(T, 5001)
      settle(3.5)           -- Frist von 3 s: generische Karte
      H.eq(#cards(), 1)
      H.eq(nameOf(cards()[1]), "Item 5001")
      T.Items = items

      local g = T.DB.global
      T.DB.global = nil
      emit(T, 5002)
      settle(1)
      T.DB.global = g
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Hygiene: Frames/Globals sauber, im Leerlauf nichts aktiv", function()
      local T = start()
      for i = 1, 6 do
         emit(T, 5000 + i)
         settle(0.3)
      end
      T.Toasts.ShowAnchor()
      settle(2)
      T.Toasts.HideAnchor()
      settle(12)
      H.eq(#cards(), 0)
      H.eq(stats(T).visible, 0)
      H.eq(stats(T).queued, 0)
      H.eq(#M.UpdateFrames(), 0, "kein sichtbarer Frame mit OnUpdate")
      H.eq(#M.TakeErrors(), 0)
   end)

   -- ======================================================================
   -- Zeitverhalten, Zusammenfassen, Fehlerfall (Verifikation)
   -- ======================================================================

   for _, fps in ipairs({ 144, 60, 20, 5 }) do
      H.test(("Lebensdauer einer Probekarte bei %d Bildern/s: 4,6 s (0,2 + 4 + 0,4), danach kein OnUpdate"):format(fps), function()
         local T = start()
         local step = 1 / fps
         T.Toasts.Test()
         H.eq(stats(T).visible, 1)
         local t = M.AdvanceUntil(function() return stats(T).visible == 0 end, 10, step)
         H.truthy(t, "die Karte verschwindet")
         if t then
            H.near(t, 4.6, 2 * step + 0.05, "Dauer bei " .. fps .. " fps")
         end
         H.eq(#M.UpdateFrames(), 0, "kein OnUpdate")
         H.eq(#M.TakeErrors(), 0)
      end)
   end

   H.test("Einblenden steigt gleichmaessig an, Ausblenden faellt gleichmaessig ab (kein Springen)", function()
      local T = start()
      T.Toasts.Test()
      local card = cards()[1]
      local last = card:GetAlpha()
      H.near(last, 0, 0.001, "beginnt unsichtbar")
      for i = 1, 4 do
         settle(0.05)
         local a = card:GetAlpha()
         H.truthy(a >= last - 1e-6, "monoton steigend (Schritt " .. i .. ")")
         H.truthy(a - last <= 0.3, "kein Sprung (Schritt " .. i .. ")")
         last = a
      end
      H.near(last, 1, 0.001, "nach 0,2 s voll sichtbar")
      settle(3.9)          -- 4,1 s: das Stehen (4 s) ist gerade vorbei
      local prev = card:GetAlpha()
      for i = 1, 9 do
         settle(0.05)
         local a = card:GetAlpha()
         H.truthy(a <= prev + 1e-6, "monoton fallend (Schritt " .. i .. ")")
         H.truthy(prev - a <= 0.3, "kein Sprung (Schritt " .. i .. ")")
         prev = a
      end
      H.truthy(prev < 0.5, "nach 0,45 s im Ausblenden fast weg, alpha=" .. tostring(prev))
   end)

   H.test("Warteschlange ueber 8: gefaltet ohne Verlust (3 sichtbar + Sammelzahl = Ereignisse), Karte ruecke nach", function()
      local T = start()
      for _ = 1, 12 do T.Toasts.Test() end
      local st = stats(T)
      H.eq(st.visible, 3, "drei sichtbar")
      H.eq(st.queued, 1, "die neun Wartenden sind eine Karte")
      H.eq(st.burst, true)
      settle(5)
      local list = cards()
      H.eq(#list, 1, "die drei sind weg, die Sammelkarte ist da")
      H.eq(nameOf(list[1]), "Appearances: 9", "3 + 9 = 12 Ereignisse")
      settle(8)
      H.eq(stats(T).visible, 0)
      H.eq(#M.UpdateFrames(), 0)
   end)

   H.test("Sammelereignisse fordern keine Iteninfo an (kein Abfragesturm bei grossen Sweeps)", function()
      local T = start()
      local requested = 0
      local real = T.Items.Request
      T.Items.Request = function(id)
         requested = requested + 1
         return real(id)
      end
      for id = 5001, 5030 do emit(T, id) end
      T.Items.Request = real
      H.truthy(requested <= 3, "Anfragen nur fuer die ersten Einzelkarten, war " .. requested)
      settle(0.6)
      H.eq(nameOf(cards()[1]), "Appearances: 30")
   end)

   H.test("Positionsmodus: Probekarte bleibt stehen, echte Meldungen reihen sich ein und laufen aus", function()
      local T = start()
      T.Toasts.ShowAnchor()
      emit(T, 5001)
      settle(0.6)
      emit(T, 5002)
      settle(0.6)
      H.eq(#cards(), 3, "Probekarte + zwei echte")
      emit(T, 5003)
      settle(0.6)
      H.eq(stats(T).queued, 1, "die dritte echte wartet auf einen Platz")
      settle(12)
      local list = cards()
      H.eq(#list, 1, "nur die Probekarte bleibt")
      H.falsy(nameOf(list[1]):find("^Appearance %d"), "es ist die Probekarte, keine echte Meldung")
      T.Toasts.HideAnchor()
      settle(1)
      H.eq(#cards(), 0)
      H.eq(#M.UpdateFrames(), 0)
   end)

   H.test("Anker schnell verbergen und wieder zeigen: es bleibt eine Probekarte zum Ausrichten", function()
      local T = start()
      T.Toasts.ShowAnchor()
      settle(0.5)
      T.Toasts.HideAnchor()
      settle(0.1)                     -- die alte Probekarte blendet noch aus
      T.Toasts.ShowAnchor()
      settle(0.6)                     -- die alte ist weg
      local list = cards()
      H.eq(#list, 1, "genau eine Probekarte")
      settle(10)
      H.eq(#cards(), 1, "und sie bleibt, solange der Anker sichtbar ist")
      T.Toasts.ShowAnchor()
      H.eq(#cards(), 1, "ein weiteres Zeigen legt keine zweite an")
      T.Toasts.HideAnchor()
      settle(1)
      H.eq(#cards(), 0)
      H.eq(#M.UpdateFrames(), 0)
   end)

   H.test("Fehler im Takt: einmal gemeldet, Karten und Warteschlange weggeraeumt, danach funktioniert alles wieder", function()
      local T = start()
      emit(T, 5001)
      settle(0.1)
      local real = T.Util.QualityColor
      T.Util.QualityColor = function() error("boom-quality") end
      settle(1.5)
      local errs = M.TakeErrors()
      local boom = 0
      for _, e in ipairs(errs) do
         if tostring(e):find("boom-quality", 1, true) then boom = boom + 1 end
      end
      H.eq(boom, 1, "der Fehler wird einmal gemeldet, nicht in jedem Bild")
      H.eq(stats(T).visible, 0, "keine halbfertige Karte")
      H.eq(stats(T).queued, 0)
      H.eq(#cards(), 0)
      settle(4)            -- der Aktualisierungstimer von State (3 s) ist durch
      H.eq(#M.UpdateFrames(), 0, "der Treiber schlaeft")

      T.Util.QualityColor = real
      emit(T, 5002)
      settle(0.6)
      H.eq(#cards(), 1, "der naechste Toast kommt")
      H.eq(nameOf(cards()[1]), "Appearance 2")
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Gespeicherte Position in Kurzform, mit Namen oder beschaedigt: nie ein Fehler, Standard als Rueckfall", function()
      local cases = {
         { saved = { "TOP", "TOP" }, want = { "TOP", 0, -120 } },
         { saved = { point = "CENTER", relPoint = "CENTER", x = 5, y = 6 }, want = nil },
         { saved = "unsinn", want = { "TOP", 0, -120 } },
         { saved = { "CENTER", "CENTER", "7", 8 }, want = { "TOP", 0, -120 } },
         { saved = { "CENTER", "CENTER", 7, 8 }, want = { "CENTER", 7, 8 } },
      }
      for i, c in ipairs(cases) do
         local T = start({ globals = { TransmogGlobalDB = { toastPoint = c.saved } } })
         T.Toasts.ShowAnchor()
         local p, rel, _, x, y = anchorFrame():GetPoint(1)
         H.eq(type(p), "string", "Fall " .. i .. ": Ankerpunkt")
         H.eq(rel, UIParent, "Fall " .. i .. ": an UIParent")
         H.eq(type(x) == "number" and type(y) == "number", true, "Fall " .. i .. ": Zahlen")
         if c.want then
            H.eq(p, c.want[1], "Fall " .. i)
            H.eq(x, c.want[2], "Fall " .. i)
            H.eq(y, c.want[3], "Fall " .. i)
         end
         H.eq(#M.TakeErrors(), 0, "Fall " .. i)
      end
   end)

   -- ======================================================================
   -- Spielersicht: deutscher Client, Katalog, Serverattrappe
   -- ======================================================================

   local Fixtures = require("fixtures")

   H.test("Spielersicht (deDE): Server sammelt ein Aussehen -> Karte mit deutschem Namen; langer Name passt ins Layout", function()
      local Layout = require("layout")
      local T = Fixtures.Boot(H, { locale = "deDE" })
      T.Locale.Add("deDE", {
         TOAST_TITLE = "Neues Aussehen freigeschaltet",
         TOAST_BURST_TITLE = "Neue Aussehen freigeschaltet",
         TOAST_BURST_COUNT = "Aussehen: %d",
         TOAST_ANCHOR_LABEL = "Verschiebe mich",
         TOAST_ANCHOR_TIP_TITLE = "Position der Benachrichtigungen",
         TOAST_ANCHOR_TIP_DRAG = "Ziehen, um die Benachrichtigungen zu verschieben.",
         TOAST_ANCHOR_TIP_RESET = "Rechtsklick: Position zuruecksetzen.",
      })
      T.Locale.Set("deDE")
      Fixtures.ServerHello(T)
      Fixtures.ServerAutoReply(T)
      -- waehrend der ersten 10 s nach dem Betreten (Sweep) bleibt es still
      local early = Fixtures.Item(T, "e_head_cloth")
      Fixtures.Collect(T, early)
      Fixtures.Settle(T, 1)
      H.eq(#cards(), 0, "Sweep: keine Karte")
      Fixtures.Settle(T, 10)

      local id = Fixtures.Item(T, "e_legs_cloth")
      local long = M.items[id].name
      H.truthy(#long > 55, "Voraussetzung: langer Name")
      Fixtures.Collect(T, id)
      Fixtures.Settle(T, 0.6)
      local list = cards()
      H.eq(#list, 1)
      H.eq(titleOf(list[1]), "Neues Aussehen freigeschaltet")
      H.eq(nameOf(list[1]), long, "voller deutscher Name (die Karte kuerzt nur beim Zeichnen)")

      T.Toasts.ShowAnchor()
      local problems = Layout.Check(Layout.Rects(Layout.TopLevel()), { truncateOk = { "/name$" } })
      for _, p in ipairs(problems) do
         if p.severity ~= "info" then
            H.fail(tostring(p.kind) .. " " .. tostring(p.path) .. ": " .. tostring(p.message))
         end
      end
      H.eq(#M.TakeErrors(), 0)
   end)

   H.test("Spielersicht: der Server meldet 30 Aussehen in einem Rutsch nach dem Sweep -> eine Sammelkarte", function()
      local T = Fixtures.Boot(H, { locale = "deDE" })
      Fixtures.ServerHello(T)
      Fixtures.ServerAutoReply(T)
      Fixtures.Settle(T, 11)
      local n = 0
      for _, rec in ipairs(Fixtures.Catalog(T).list) do
         if not rec.nonTransmog and n < 30 then
            Fixtures.Collect(T, rec.id)
            n = n + 1
         end
      end
      Fixtures.Settle(T, 0.6)
      local list = cards()
      H.eq(#list, 1, "genau eine Karte")
      H.eq(nameOf(list[1]), string.format(T.L.TOAST_BURST_COUNT, n))
      Fixtures.Settle(T, 8)
      H.eq(#cards(), 0)
      H.eq(#M.UpdateFrames(), 0)
   end)

   -- ======================================================================
   -- Zufallsfolgen (feste Startwerte)
   -- ======================================================================

   H.test("Zufallsfolgen: Grenzen und Alphawerte halten, keine Fehler, am Ende ist alles still", function()
      for seed = 1, 40 do
         math.randomseed(seed)
         local T = start()
         local log = {}
         for step = 1, 250 do
            local r = math.random(1, 100)
            local op
            if r <= 35 then
               op = "emit"
               emit(T, 5000 + math.random(1, 30))
            elseif r <= 60 then
               op = "time"
               settle(math.random() * 1.5)
            elseif r <= 66 then
               op = "test"
               T.Toasts.Test()
            elseif r <= 70 then
               op = "showanchor"
               T.Toasts.ShowAnchor()
            elseif r <= 74 then
               op = "hideanchor"
               T.Toasts.HideAnchor()
            elseif r <= 80 then
               op = "hover"
               local c = cards()
               if #c > 0 then M.Enter(c[math.random(1, #c)]) end
            elseif r <= 85 then
               op = "leave"
               local c = cards()
               if #c > 0 then M.Leave(c[math.random(1, #c)]) end
            elseif r <= 90 then
               op = "click"
               local c = cards()
               if #c > 0 then M.Click(c[math.random(1, #c)]) end
            elseif r <= 94 then
               op = "toggle"
               T.DB.Set("toasts", math.random() > 0.4)
            elseif r <= 97 then
               op = "show"
               T.Toasts.Show(5000 + math.random(1, 30))
            else
               op = "sweep"
               T.enteredWorldAt = GetTime() - math.random(0, 12)
            end
            log[#log + 1] = op
            local st = stats(T)
            if st.visible > 3 or st.created > 3 or st.queued > 9 then
               H.fail(("Startwert %d Schritt %d (%s): visible=%d queued=%d created=%d"):format(
                  seed, step, op, st.visible, st.queued, st.created))
               return
            end
            for _, c in ipairs(cards()) do
               local a = c:GetAlpha()
               if a < -0.001 or a > 1.001 then
                  H.fail(("Startwert %d Schritt %d: Alpha %s"):format(seed, step, tostring(a)))
                  return
               end
            end
            local errs = M.TakeErrors()
            if #errs > 0 then
               H.fail(("Startwert %d Schritt %d (%s): %s"):format(seed, step, op, tostring(errs[1])))
               return
            end
         end
         T.Toasts.HideAnchor()
         for _, c in ipairs(cards()) do M.Leave(c) end
         settle(40)
         local st = stats(T)
         if st.visible ~= 0 or st.queued ~= 0 or #M.UpdateFrames() ~= 0 then
            H.fail(("Startwert %d: nicht still, visible=%d queued=%d OnUpdate=%d"):format(
               seed, st.visible, st.queued, #M.UpdateFrames()))
            return
         end
      end
   end)

end
