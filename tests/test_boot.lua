-- tests/test_boot.lua
-- ---------------------------------------------------------------------------
-- Verhaltenstests fuer Core/Boot.lua (T.Boot): Start, Slash-Befehle, Gossip.
--
--   * ADDON_LOADED("Transmog"): DB.Init, Locale.Set; fremde Addons werden ignoriert
--   * PLAYER_LOGIN: feste Reihenfolge der Init-Aufrufe, jeder Schritt geschuetzt,
--     genau EINE Zeile "geladen"
--   * PLAYER_ENTERING_WORLD: enteredWorldAt nur beim ersten Mal, entprelltes Refresh
--   * GOSSIP_SHOW/GOSSIP_CLOSED mit dem synchronen GOSSIP_CLOSED der Attrappe
--     (erst HideUIPanel, dann Window.Open; Schliessen nur nach > 1 s)
--   * /transmog, /xmog und die Unterbefehle, /transmogdebug, /transmogreset
--   * Namen der Tastenbelegung, keine fremden Globals/Frames
--
-- Die Attrappe setzt IsShown() & Co. auf 1/nil: deshalb H.truthy/H.falsy.
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   local HEAD = 0

   -- -----------------------------------------------------------------------
   -- Hilfen
   -- -----------------------------------------------------------------------

   local T
   local log = {}

   local function clearLog()
      for i = #log, 1, -1 do log[i] = nil end
   end

   local function count(name)
      local n = 0
      for _, e in ipairs(log) do
         if e == name or (type(e) == "table" and e.name == name) then n = n + 1 end
      end
      return n
   end

   local function items()
      return {
         [101] = { name = "Plate Helm", quality = 4, equipLoc = "INVTYPE_HEAD", class = "Armor", subclass = "Plate",
                   icon = "Interface\\Icons\\INV_Test_101", ilvl = 100 },
         [200] = { name = "Look 200", quality = 3, equipLoc = "INVTYPE_HEAD", class = "Armor", subclass = "Plate",
                   icon = "Interface\\Icons\\INV_Test_200", ilvl = 100 },
      }
   end

   -- Startet Attrappe und TOC. opts.login = false: nur ADDON_LOADED; opts.saved: SavedVariables;
   -- opts.noSeed = true: Neuinstallation mit der Vorgabe seit 2.1 (sonst "ohne Transmogrifizierer anwenden" aus).
   local function boot(opts)
      opts = opts or {}
      clearLog()
      T = H.boot({
         items = items(), login = opts.login, globals = opts.saved, noSeed = opts.noSeed,
         world = { equipment = { [1] = 101 }, locale = opts.locale or "enUS" },
      })
      H.assert(type(T) == "table", "Transmog wurde nicht geladen")
      return T
   end

   -- Ein Fenster-Ersatz, der die Aufrufe mitschreibt
   local function fakeWindow(extra)
      local w = { shown = false, openedAt = nil }
      function w.Open(opts)
         log[#log + 1] = { name = "Open", fromNpc = opts and opts.fromNpc }
         w.shown = true
         w.openedAt = GetTime()
      end
      function w.Close()
         log[#log + 1] = "Close"
         w.shown = false
      end
      function w.Toggle() log[#log + 1] = "Toggle" end
      function w.IsShown() return w.shown end
      function w.ResetLayout() log[#log + 1] = "ResetLayout" end
      function w.Init() log[#log + 1] = "Window.Init" end
      for k, v in pairs(extra or {}) do w[k] = v end
      T.UI.Window = w
      return w
   end

   -- Nachrichten im Chat (Teilstring, plain)
   local function chatHas(text)
      for _, line in ipairs(M.messages) do
         if string.find(line, text, 1, true) then return true end
      end
      return false
   end

   local function chatCount(text)
      local n = 0
      for _, line in ipairs(M.messages) do
         if string.find(line, text, 1, true) then n = n + 1 end
      end
      return n
   end

   -- Setzt den Chat zurueck
   local function clearChat()
      for i = #M.messages, 1, -1 do M.messages[i] = nil end
   end

   -- ======================================================================
   H.section("Start")
   -- ======================================================================

   H.test("ADDON_LOADED: DB.Init und Locale.Set mit der gespeicherten Sprache", function()
      boot({ login = false, saved = { TransmogGlobalDB = { locale = "deDE", width = 900 } } })
      H.truthy(T.DB.global, "DB.Init gelaufen")
      H.eq(T.DB.global.width, 900)
      H.eq(T.DB.global.height, 600, "Vorgaben ergaenzt")
      H.eq(T.Locale.Current(), "deDE")
      H.truthy(T.DB.char)
      -- noch kein PLAYER_LOGIN: keine Modul-Init, kein Fenster
      H.eq(rawget(_G, "TransmogWindow"), nil)
   end)

   H.test("ADDON_LOADED fremder Addons wird ignoriert", function()
      boot({ login = false })
      T.DB.global = nil
      T.DB.char = nil
      M.Fire("ADDON_LOADED", "SomeOtherAddon")
      H.eq(T.DB.global, nil)
      M.Fire("ADDON_LOADED", "Transmog")
      H.truthy(T.DB.global)
   end)

   H.test("PLAYER_LOGIN: Init-Reihenfolge laut SPEC 6.13, danach genau eine Zeile 'geladen'", function()
      boot({ login = false })
      local order = {}
      local function wrap(label, tbl, fname)
         local orig = tbl[fname]
         tbl[fname] = function(...)
            order[#order + 1] = label
            return orig(...)
         end
      end
      wrap("RefreshPlayerInfo", T, "RefreshPlayerInfo")
      wrap("Slots", T.Slots, "Init")
      wrap("Items", T.Items, "Init")
      wrap("Net", T.Net, "Init")
      wrap("State", T.State, "Init")
      wrap("Outfits", T.Outfits, "Init")
      wrap("Tooltips", T.Tooltips, "Init")
      wrap("Toasts", T.Toasts, "Init")
      wrap("Window", T.UI.Window, "Init")
      clearChat()
      M.Fire("PLAYER_LOGIN")
      H.deepEq(order, { "RefreshPlayerInfo", "Slots", "Items", "Net", "State", "Outfits", "Tooltips", "Toasts", "Window" })
      H.eq(chatCount(" loaded"), 1, "genau eine Zeile")
      H.truthy(chatHas("Transmog 2.1 loaded"))
      -- ein zweites PLAYER_LOGIN tut nichts
      M.Fire("PLAYER_LOGIN")
      H.eq(#order, 9)
      H.eq(chatCount(" loaded"), 1)
   end)

   H.test("PLAYER_LOGIN: ein ausfallendes Modul stoppt die uebrigen nicht; Fehler wird gemeldet", function()
      boot({ login = false })
      H.allowErrors()
      local called = {}
      T.Items.Init = function() error("Items kaputt") end
      local netInit = T.Net.Init
      T.Net.Init = function(...)
         called[#called + 1] = "Net"
         return netInit(...)
      end
      local winInit = T.UI.Window.Init
      T.UI.Window.Init = function(...)
         called[#called + 1] = "Window"
         return winInit(...)
      end
      clearChat()
      M.Fire("PLAYER_LOGIN")
      H.deepEq(called, { "Net", "Window" })
      local errs = M.TakeErrors()
      H.eq(#errs, 1)
      H.contains(errs[1], "Items kaputt")
      H.truthy(chatHas("Items"), "Chatzeile nennt das Modul")
      H.truthy(chatHas(" loaded"), "die Anmeldezeile kommt trotzdem")
      -- die uebrigen Module sind in Betrieb
      H.eq(T.State.chatMessages, false)
   end)

   H.test("PLAYER_LOGIN ohne vorheriges ADDON_LOADED holt DB und Sprache nach", function()
      boot({ login = false })
      T.DB.global = nil
      T.DB.char = nil
      M.Fire("PLAYER_LOGIN")
      H.truthy(T.DB.global)
      H.truthy(T.DB.char)
   end)

   H.test("Fehlende optionale Module (Tooltips, Toasts, Fenster) verhindern den Start nicht", function()
      boot({ login = false })
      T.Tooltips = nil
      T.Toasts = nil
      T.UI.Window = nil
      clearChat()
      M.Fire("PLAYER_LOGIN")
      H.truthy(chatHas(" loaded"))
      -- /transmog meldet es, statt zu werfen
      M.Slash("/transmog")
      H.truthy(chatHas(T.L.BOOT_UNAVAILABLE))
   end)

   H.test("Login-Ablauf mit dem echten Fenster: Window.Init schaltet State-Chat ab, Fenster noch nicht gebaut", function()
      boot()
      H.eq(T.State.chatMessages, false)
      H.eq(rawget(_G, "TransmogWindow"), nil)
      H.truthy(T.UI.Window.Open)
   end)

   -- ======================================================================
   H.section("PLAYER_ENTERING_WORLD")
   -- ======================================================================

   H.test("enteredWorldAt nur beim ersten Mal der Sitzung; Refresh entprellt (2 s)", function()
      boot()
      local refreshes = 0
      local orig = T.State.Refresh
      T.State.Refresh = function(...)
         refreshes = refreshes + 1
         return orig(...)
      end
      H.eq(T.enteredWorldAt, nil)
      H.truthy(T.IsLoginSweep(), "vor dem ersten Betreten gilt der Login-Sweep")
      M.Fire("PLAYER_ENTERING_WORLD")
      local first = T.enteredWorldAt
      H.eq(first, GetTime())
      M.Advance(1)
      M.Fire("PLAYER_ENTERING_WORLD")
      M.Advance(0.5)
      M.Fire("PLAYER_ENTERING_WORLD")
      H.eq(refreshes, 0, "noch in der Entprellung")
      M.Advance(2.1)
      H.eq(refreshes, 1, "ein Refresh nach 2 s Ruhe")
      -- Zonenwechsel spaeter: enteredWorldAt bleibt, das Refresh kommt wieder
      M.Advance(60)
      M.Fire("PLAYER_ENTERING_WORLD")
      H.eq(T.enteredWorldAt, first, "nicht neu gesetzt")
      H.falsy(T.IsLoginSweep(), "kein Login-Sweep nach einem Zonenwechsel")
      M.Advance(2.1)
      H.eq(refreshes, 2)
   end)

   -- ======================================================================
   H.section("Gossip")
   -- ======================================================================

   -- Echtes Fenster ohne Unterkomponenten (die Gossip-Logik braucht nur das Fenster)
   local function realWindowOnly()
      boot()
      for _, n in ipairs({ "SlotBar", "Preview", "Grid", "FilterBar", "OutfitsTab", "Options" }) do
         T.UI[n] = nil
      end
      M.ServerMessage("TransmogStatus:0")
      M.Advance(1)
      return T.UI.Window
   end

   H.test("Open + GOSSIP_SHOW: Gossip-Fenster weg, Transmog-Fenster per NPC offen (erst Hide, dann Open)", function()
      local W = realWindowOnly()
      local order = {}
      T.Events.On("VENDOR_CHANGED", function(v) order[#order + 1] = "vendor:" .. tostring(v) end, order)
      H.falsy(GossipFrame:IsShown())
      M.OpenNpc()
      H.falsy(GossipFrame:IsShown(), "GossipFrame versteckt")
      H.eq(M.world.gossipOpen, false, "CloseGossip lief (synchrones GOSSIP_CLOSED)")
      H.truthy(W.IsShown(), "das Fenster ist trotz des synchronen GOSSIP_CLOSED offen")
      H.eq(T.State.openedByNpc, true)
      H.eq(T.State.atVendor, true)
      H.eq(T.State.serverOpenAt, nil, "serverOpenAt verbraucht")
      H.deepEq(order, { "vendor:true" })
      H.eq(W.openedAt, GetTime())
   end)

   H.test("GOSSIP_SHOW ohne vorheriges 'Open' (oder zu spaet): nichts passiert", function()
      local W = realWindowOnly()
      M.GossipShow()
      H.truthy(GossipFrame:IsShown(), "normales NPC-Gossip bleibt")
      H.falsy(W.IsShown())
      M.world.gossipOpen = false
      GossipFrame:Hide()
      -- "Open" ist laenger als 3 s her
      M.ServerMessage("Open")
      M.Advance(3.5)
      M.GossipShow()
      H.truthy(GossipFrame:IsShown())
      H.falsy(W.IsShown())
      H.truthy(T.State.serverOpenAt, "serverOpenAt bleibt unveraendert stehen")
   end)

   H.test("Ein 'Open' genuegt fuer genau ein GOSSIP_SHOW", function()
      local W = realWindowOnly()
      M.OpenNpc()
      H.truthy(W.IsShown())
      W.Close()
      H.falsy(W.IsShown())
      M.GossipShow()
      H.falsy(W.IsShown(), "zweites GOSSIP_SHOW ohne neues Open")
      H.truthy(GossipFrame:IsShown())
   end)

   H.test("GOSSIP_CLOSED: schliesst nur bei NPC-Oeffnung, sichtbar und nach mehr als 1 s", function()
      local W = realWindowOnly()
      M.OpenNpc()
      H.truthy(W.IsShown())
      -- GOSSIP_CLOSED innerhalb der Schonfrist: bleibt offen
      M.Advance(0.5)
      M.Fire("GOSSIP_CLOSED")
      H.truthy(W.IsShown())
      -- spaeter: schliesst, ruft aber nicht noch einmal CloseGossip (kein Gossip offen)
      M.Advance(1)
      M.Fire("GOSSIP_CLOSED")
      H.falsy(W.IsShown())
      H.eq(T.State.openedByNpc, false)
      H.eq(T.State.atVendor, false)

      -- per /transmog geoeffnet: GOSSIP_CLOSED aendert nichts
      W.Open({ fromNpc = false })
      M.Advance(5)
      M.Fire("GOSSIP_CLOSED")
      H.truthy(W.IsShown())
      W.Close()
      -- Fenster zu: GOSSIP_CLOSED ohne Folgen und ohne Fehler
      M.Fire("GOSSIP_CLOSED")
      H.falsy(W.IsShown())
   end)

   H.test("GOSSIP_CLOSED mit Fenster-Ersatz: Close genau einmal, nur unter den drei Bedingungen", function()
      boot()
      local w = fakeWindow()
      T.State.openedByNpc = true
      w.shown, w.openedAt = true, GetTime()
      M.Advance(0.9)
      M.Fire("GOSSIP_CLOSED")
      H.eq(count("Close"), 0)
      M.Advance(0.2)
      M.Fire("GOSSIP_CLOSED")
      H.eq(count("Close"), 1)
      -- nicht sichtbar
      w.shown = false
      M.Fire("GOSSIP_CLOSED")
      H.eq(count("Close"), 1)
      -- nicht per NPC
      w.shown = true
      T.State.openedByNpc = false
      M.Fire("GOSSIP_CLOSED")
      H.eq(count("Close"), 1)
      -- ohne openedAt (nie geoeffnet) wird nicht geworfen
      T.State.openedByNpc = true
      w.openedAt = nil
      M.Advance(2)
      M.Fire("GOSSIP_CLOSED")
      H.eq(count("Close"), 2)
   end)

   H.test("GOSSIP_SHOW ohne Fenster: das Gossip-Fenster bleibt, 'Open' bleibt gemerkt", function()
      boot()
      T.UI.Window = nil
      M.ServerMessage("Open")
      H.truthy(T.State.serverOpenAt)
      M.GossipShow()
      H.truthy(GossipFrame:IsShown(), "ohne Fenster nicht verstecken")
      H.truthy(T.State.serverOpenAt)
   end)

   H.test("GOSSIP_SHOW: HideUIPanel(GossipFrame) kommt VOR Window.Open", function()
      boot()
      local events = {}
      local w = fakeWindow()
      local origOpen = w.Open
      w.Open = function(opts)
         events[#events + 1] = "Open:" .. tostring(GossipFrame:IsShown())
         return origOpen(opts)
      end
      M.ServerMessage("Open")
      H.truthy(T.State.serverOpenAt)
      M.GossipShow()
      H.deepEq(events, { "Open:nil" }, "beim Open ist das Gossip-Fenster schon versteckt")
      H.eq(count("Open"), 1)
      H.eq(log[#log].fromNpc, true)
   end)

   -- ======================================================================
   H.section("Slash-Befehle")
   -- ======================================================================

   H.test("Globals: /transmog und /xmog, SlashCmdList, Kompatibilitaetsbefehle", function()
      boot()
      H.eq(SLASH_TRANSMOG1, "/transmog")
      H.eq(SLASH_TRANSMOG2, "/xmog")
      H.eq(type(SlashCmdList["TRANSMOG"]), "function")
      H.eq(M.Slash("/transmog"), true)
      H.eq(M.Slash("/xmog"), true)
      H.eq(M.Slash("/transmogdebug"), true)
      H.eq(M.Slash("/transmogreset"), true)
      H.eq(M.Slash("/gibtesnicht"), false)
   end)

   H.test("/transmog und /xmog: Fenster umschalten", function()
      boot()
      fakeWindow()
      M.Slash("/transmog")
      M.Slash("/xmog")
      M.Slash("/transmog   ")
      H.eq(count("Toggle"), 3)
   end)

   H.test("/transmog options und optionen: Optionsfenster oeffnen", function()
      boot()
      fakeWindow()
      local opened = 0
      T.UI.Options = { Open = function() opened = opened + 1 end }
      M.Slash("/transmog options")
      M.Slash("/transmog optionen")
      M.Slash("/xmog OPTIONS")
      H.eq(opened, 3)
      -- ohne Options: Meldung statt Fehler
      T.UI.Options = nil
      clearChat()
      M.Slash("/transmog options")
      H.truthy(chatHas(T.L.BOOT_UNAVAILABLE))
   end)

   H.test("/transmog reset und /transmogreset: Fenster zuruecksetzen, Meldung", function()
      boot()
      fakeWindow()
      clearChat()
      M.Slash("/transmog reset")
      H.eq(count("ResetLayout"), 1)
      H.truthy(chatHas(T.L.BOOT_RESET_DONE))
      M.Slash("/transmogreset")
      H.eq(count("ResetLayout"), 2)
   end)

   H.test("/transmog toast: Verschiebe-Anker der Benachrichtigungen", function()
      boot()
      local shown = 0
      T.Toasts.ShowAnchor = function() shown = shown + 1 end
      M.Slash("/transmog toast")
      H.eq(shown, 1)
   end)

   H.test("/transmog lang: setzt DB und Sprache; auto, Kurzformen, Fehler, Anzeige", function()
      boot()
      T.Locale.Add("deDE", { LOADED = "%s %s geladen." })
      local changed = 0
      T.Events.On("LOCALE_CHANGED", function() changed = changed + 1 end, log)
      clearChat()
      M.Slash("/transmog lang deDE")
      H.eq(T.DB.global.locale, "deDE")
      H.eq(T.Locale.Current(), "deDE")
      H.truthy(changed >= 1, "LOCALE_CHANGED")
      H.truthy(chatHas("deDE"))
      M.Slash("/transmog lang auto")
      H.eq(T.DB.global.locale, "auto")
      H.eq(T.Locale.Current(), "enUS")
      M.Slash("/transmog lang FR")
      H.eq(T.DB.global.locale, "frFR", "Gross-/Kleinschreibung und Kurzform")
      M.Slash("/transmog lang ru")
      H.eq(T.DB.global.locale, "ruRU")
      M.Slash("/transmog lang koKR")
      H.eq(T.DB.global.locale, "koKR")
      -- Fehler: unbekannt und mehrdeutig; der Wert bleibt
      clearChat()
      M.Slash("/transmog lang klingon")
      H.eq(T.DB.global.locale, "koKR")
      H.truthy(chatHas("klingon"))
      M.Slash("/transmog lang zh")
      H.eq(T.DB.global.locale, "koKR", "zh ist mehrdeutig (zhCN/zhTW)")
      -- ohne Argument: aktuelle Sprache nennen
      clearChat()
      M.Slash("/transmog lang")
      H.truthy(chatHas("koKR"))
      H.truthy(chatHas("auto"))
      M.Slash("/transmog lang zhTW")
      H.eq(T.DB.global.locale, "zhTW")
      -- Aliase der Fallbackkette
      M.Slash("/transmog lang esMX")
      H.eq(T.DB.global.locale, "esMX")
      M.Slash("/transmog lang enGB")
      H.eq(T.DB.global.locale, "enGB")
      H.eq(T.Locale.Current(), "enUS", "enGB faellt ohne eigene Texte auf enUS zurueck")
   end)

   H.test("/transmog debug und /transmogdebug: umschalten, Zustand mit Net-Zaehlern und Typtabelle", function()
      boot()
      T.Items.DumpTypes = function() return { "locale=enUS ah=true", "401 = Cloth", "402 = Leather" } end
      H.eq(T.debug, false)
      clearChat()
      M.Slash("/transmog debug")
      H.eq(T.debug, true)
      H.truthy(chatHas(T.L.BOOT_DEBUG_ON))
      H.truthy(chatHas("401 = Cloth"), "Items.DumpTypes ausgegeben")
      H.truthy(chatHas("messages sent"), "Net-Zaehler")
      H.truthy(chatHas("Version 2.1"))
      clearChat()
      M.Slash("/transmogdebug")
      H.eq(T.debug, false)
      H.truthy(chatHas(T.L.BOOT_DEBUG_OFF))
      H.falsy(chatHas("401 = Cloth"), "beim Ausschalten keine Tabelle")
   end)

   H.test("/transmog help und unbekannte Unterbefehle: Befehlsliste", function()
      boot()
      clearChat()
      M.Slash("/transmog help")
      H.truthy(chatHas(T.L.BOOT_HELP_TITLE))
      H.truthy(chatHas("/transmog options"))
      H.truthy(chatHas("/transmog lang"))
      local n = #M.messages
      H.truthy(n >= 8)
      clearChat()
      M.Slash("/transmog unsinn")
      H.truthy(chatHas(T.L.BOOT_HELP_TITLE))
   end)

   H.test("Ein werfender Befehl wird gemeldet und bricht die Eingabe nicht ab", function()
      boot()
      H.allowErrors()
      fakeWindow({ Toggle = function() error("Toggle kaputt") end })
      clearChat()
      H.eq(M.Slash("/transmog"), true)
      local errs = M.TakeErrors()
      H.eq(#errs, 1)
      H.contains(errs[1], "Toggle kaputt")
   end)

   -- ======================================================================
   H.section("Tastenbelegung, Hygiene")
   -- ======================================================================

   H.test("Anzeigenamen der Tastenbelegung aus L, bei Sprachwechsel aktualisiert", function()
      boot()
      H.eq(BINDING_HEADER_TRANSMOG, T.L.BOOT_BINDING_HEADER)
      H.eq(BINDING_NAME_TRANSMOG_TOGGLE, T.L.BOOT_BINDING_TOGGLE)
      H.eq(BINDING_NAME_TRANSMOG_TOGGLE, "Open or close the transmog window")
      T.Locale.Add("deDE", { BOOT_BINDING_TOGGLE = "Transmog-Fenster umschalten" })
      T.Locale.Set("deDE")
      H.eq(BINDING_NAME_TRANSMOG_TOGGLE, "Transmog-Fenster umschalten")
      T.Locale.Set("enUS")
      H.eq(BINDING_NAME_TRANSMOG_TOGGLE, "Open or close the transmog window")
   end)

   H.test("Taste TRANSMOG_TOGGLE ruft Window.Toggle", function()
      boot()
      fakeWindow()
      M.RunBinding("TRANSMOG_TOGGLE")
      H.eq(count("Toggle"), 1)
   end)

   H.test("Hygiene: Boot legt keine Frames und keine fremden Globals an", function()
      boot()
      M.Slash("/transmog")
      M.Slash("/transmog help")
      M.Slash("/transmog debug")
      M.Slash("/transmog debug")
      H.eq(#M.errors, 0)
      H.deepEq(M.StrayGlobals(), {})
      H.deepEq(M.StrayFrameNames(), {})
      -- Boot registriert nur ueber Events.Game: der Bus ist erreichbar, Boot hat keinen eigenen Frame
      H.eq(type(T.Boot), "table")
      H.eq(type(T.Boot.Init), "function")
      H.eq(rawget(_G, "TransmogBootFrame"), nil)
   end)

   -- ======================================================================
   H.section("Unabhaengige Pruefung: Gossip-Ersatz, Ausfaelle, echte Befehle")
   -- ======================================================================

   H.test("Der NPC wird bei offenem Fenster erneut angesprochen: kein Schliessen und Wiederoeffnen", function()
      local W = realWindowOnly()
      M.OpenNpc()
      H.truthy(W.IsShown())
      local frame = W.frame
      local hides, shows = 0, 0
      frame:HookScript("OnHide", function() hides = hides + 1 end)
      frame:HookScript("OnShow", function() shows = shows + 1 end)
      local vendor = {}
      T.Events.On("VENDOR_CHANGED", function(v) vendor[#vendor + 1] = v end, vendor)
      M.Advance(10)                          -- weit nach der Schonfrist von 1 s
      local before = W.openedAt
      M.OpenNpc()
      H.truthy(W.IsShown())
      H.eq(hides, 0, "nicht verborgen (das synchrone GOSSIP_CLOSED gehoert zum Ersetzen)")
      H.eq(shows, 0)
      H.deepEq(vendor, { true }, "der Zustand wird nie kurz auf 'kein Transmogrifizierer' gesetzt")
      H.eq(T.State.openedByNpc, true)
      H.truthy(W.openedAt > before, "Zeitpunkt des Oeffnens aktualisiert")
      H.falsy(GossipFrame:IsShown())
      -- danach schliesst GOSSIP_CLOSED wieder wie gewohnt (Weggehen)
      M.Advance(2)
      M.Fire("GOSSIP_CLOSED")
      H.falsy(W.IsShown())
   end)

   H.test("Fenster laesst sich nicht bauen: das normale Gossip-Fenster bleibt, 'Open' bleibt gemerkt", function()
      local W = realWindowOnly()
      T.UI.Skin = nil                       -- Aufbau scheitert (siehe Window.Create)
      M.OpenNpc()
      H.truthy(GossipFrame:IsShown(), "Gossip nicht versteckt")
      H.eq(M.world.gossipOpen, true)
      H.falsy(W.IsShown())
      H.eq(W.frame, nil)
      H.truthy(T.State.serverOpenAt)
      H.eq(#M.errors, 0)
   end)

   H.test("Window.Create wirft: Fehler gemeldet, Gossip-Fenster bleibt", function()
      boot()
      H.allowErrors()
      local w = fakeWindow({ Create = function() error("Aufbau kaputt") end })
      M.ServerMessage("Open")
      M.GossipShow()
      H.truthy(GossipFrame:IsShown())
      H.eq(count("Open"), 0)
      local errs = M.TakeErrors()
      H.eq(#errs, 1)
      H.contains(errs[1], "Aufbau kaputt")
      H.truthy(chatHas("Window"), "Chatzeile nennt das Modul")
      H.truthy(w ~= nil)
   end)

   H.test("ADDON_LOADED: faellt DB.Init aus, laufen Sprache und Tastenbelegung trotzdem; Fehler gemeldet", function()
      boot({ login = false })
      H.allowErrors()
      T.DB.Init = function() error("DB kaputt") end
      T.DB.global = nil
      BINDING_HEADER_TRANSMOG = nil
      M.Fire("ADDON_LOADED", "Transmog")
      local errs = M.TakeErrors()
      H.truthy(#errs >= 1)
      H.contains(errs[1], "DB kaputt")
      H.eq(BINDING_HEADER_TRANSMOG, T.L.BOOT_BINDING_HEADER, "Bindings gesetzt")
      H.eq(T.Locale.Current(), "enUS")
   end)

   H.test("PLAYER_LOGIN: jedes Modul faellt einzeln aus, alle uebrigen laufen (jedes der acht)", function()
      local mods = {
         { "Slots", function() return T.Slots end },
         { "Items", function() return T.Items end },
         { "Net", function() return T.Net end },
         { "State", function() return T.State end },
         { "Outfits", function() return T.Outfits end },
         { "Tooltips", function() return T.Tooltips end },
         { "Toasts", function() return T.Toasts end },
         { "Window", function() return T.UI.Window end },
      }
      for failing = 1, #mods do
         boot({ login = false })
         H.allowErrors()
         local called = {}
         for i, entry in ipairs(mods) do
            local mod = entry[2]()
            local orig = mod.Init
            mod.Init = function(...)
               called[#called + 1] = entry[1]
               if i == failing then error(entry[1] .. " kaputt") end
               return orig(...)
            end
         end
         clearChat()
         M.Fire("PLAYER_LOGIN")
         H.eq(#called, 8, "alle acht Init-Aufrufe (ohne " .. mods[failing][1] .. ")")
         local errs = M.TakeErrors()
         H.eq(#errs, 1)
         H.contains(errs[1], mods[failing][1] .. " kaputt")
         H.eq(chatCount(" loaded"), 1, "Anmeldezeile trotzdem")
         clearChat()
      end
   end)

   H.test("Befehle mit dem echten Fenster: /transmog schaltet um, /transmog reset setzt Groesse und Position zurueck", function()
      boot()
      H.eq(rawget(_G, "TransmogWindow"), nil)
      M.Slash("/transmog")
      local W = T.UI.Window
      H.truthy(W.IsShown())
      H.eq(T.State.atVendor, false, "Vorschau-Modus")
      M.Slash("/xmog")
      H.falsy(W.IsShown())
      T.DB.Set("width", 1000)
      T.DB.Set("height", 700)
      T.DB.Set("point", { "TOPLEFT", "BOTTOMLEFT", 20, 700 })
      W.Open({ fromNpc = true })
      H.eq(W.frame:GetWidth(), 1000)
      clearChat()
      M.Slash("/transmog reset")
      H.eq(T.DB.global.width, 880)
      H.eq(T.DB.global.height, 600)
      H.eq(T.DB.global.point, nil)
      H.eq(W.frame:GetWidth(), 880)
      H.eq(W.frame:GetHeight(), 600)
      H.truthy(chatHas(T.L.BOOT_RESET_DONE))
      -- /transmogreset vor dem ersten Oeffnen: nur die Werte
      T.DB.Set("width", 1000)
      W.Close()
      M.Slash("/transmogreset")
      H.eq(T.DB.global.width, 880)
   end)

   H.test("/transmog lang mit gebautem Fenster: Reiter, Knoepfe und Tastenbelegung wechseln sofort", function()
      boot()
      T.Locale.Add("deDE", {
         WIN_TAB_ITEMS = "Gegenstaende", WIN_DISCARD = "Verwerfen", WIN_APPLY = "Anwenden",
         BOOT_BINDING_TOGGLE = "Transmog-Fenster umschalten",
      })
      M.Slash("/transmog")
      local f = T.UI.Window.frame
      H.eq(f.tabItems.label:GetText(), "Items")
      M.Slash("/transmog lang deDE")
      H.eq(f.tabItems.label:GetText(), "Gegenstaende")
      H.eq(f.btnDiscard.label:GetText(), "Verwerfen")
      H.eq(f.btnApply.label:GetText(), "Anwenden")
      H.eq(BINDING_NAME_TRANSMOG_TOGGLE, "Transmog-Fenster umschalten")
      M.Slash("/transmog lang auto")
      H.eq(f.tabItems.label:GetText(), "Items")
      H.eq(#M.errors, 0)
   end)

   H.test("PLAYER_ENTERING_WORLD bei offenem Fenster (Zonenwechsel): nichts schliesst, der Status wird neu gelesen", function()
      boot()
      M.Slash("/transmog")
      local W = T.UI.Window
      M.Fire("PLAYER_ENTERING_WORLD")
      M.Advance(3)
      H.truthy(W.IsShown())
      H.eq(#M.errors, 0)
      H.truthy(M.CountSent("GetTransmogStatus") >= 1)
   end)

   H.test("Ein 'Open' wenige Sekunden vor dem GOSSIP_SHOW (knapp unter 3 s) gilt noch", function()
      local W = realWindowOnly()
      M.ServerMessage("Open")
      M.Advance(2.9)
      M.GossipShow()
      H.truthy(W.IsShown())
      H.falsy(GossipFrame:IsShown())
   end)

   H.test("Kommt das Gossip-Fenster erst NACH unserem Handler (Reihenfolge der Rahmen), wird es wieder versteckt", function()
      local W = realWindowOnly()
      M.ServerMessage("Open")
      M.GossipShow()                         -- Standardreihenfolge: Gossip erst, dann wir
      H.truthy(W.IsShown())
      -- anderes Verhalten des Spiels: GossipFrame wird nach uns gezeigt
      M.world.gossipOpen = true
      GossipFrame:Show()
      H.truthy(GossipFrame:IsShown())
      M.Advance(0.3)
      H.falsy(GossipFrame:IsShown(), "wieder versteckt")
      H.truthy(W.IsShown(), "unser Fenster bleibt (kein Schliessen durch das synchrone GOSSIP_CLOSED)")
      H.eq(T.State.openedByNpc, true)
      -- ein Gossip-Fenster, das sich viel spaeter zeigt (anderer NPC), bleibt in Ruhe
      M.Advance(5)
      M.world.gossipOpen = true
      GossipFrame:Show()
      M.Advance(0.5)
      H.truthy(GossipFrame:IsShown())
   end)
end
