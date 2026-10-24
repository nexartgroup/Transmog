-- Boot.lua  (T.Boot)
-- ---------------------------------------------------------------------------
-- Start des Addons, Slash-Befehle, Gossip-Ablauf, Namen der Tastenbelegung.
--
-- Ablauf (SPEC 3 / 6.13):
--
--   ADDON_LOADED("Transmog")  DB.Init, Locale.Set(DB.global.locale)
--   PLAYER_LOGIN              RefreshPlayerInfo, Slots.Init, Items.Init, Net.Init,
--                             State.Init, Outfits.Init, Tooltips.Init, Toasts.Init,
--                             Window.Init -- jeder Schritt geschuetzt: faellt
--                             einer aus, laufen die uebrigen trotzdem (der
--                             Fehler geht an den Fehlerbehandler und eine
--                             Zeile in den Chat). Danach EINE Zeile "geladen".
--   PLAYER_ENTERING_WORLD     T.enteredWorldAt nur beim ERSTEN Mal der Sitzung
--                             (Zonenwechsel schicken keinen Login-Sweep);
--                             State.Refresh entprellt (2 s) bei jedem Mal
--   GOSSIP_SHOW / _CLOSED     siehe OnGossipShow / OnGossipClosed: das Fenster wird
--                             VOR dem Verstecken des Gossip-Fensters gebaut (gelingt
--                             es nicht, bleibt das Gossip-Fenster); das synchrone
--                             GOSSIP_CLOSED dieses Ersetzens schliesst nichts (auch
--                             nicht bei erneutem Ansprechen des NPCs); ein Gossip-
--                             Fenster, das erst nach unserem Handler erscheint,
--                             wird nach 0,15 s wieder versteckt. Ersetzt ein
--                             Gossip-Ersatz-Addon (Immersion u. a.) das Blizzard-
--                             Fenster, schliesst dieselbe Nachpruefung das
--                             Gespraech per CloseGossip(), damit dessen Fenster
--                             und Tastenbelegung sich ueber GOSSIP_CLOSED abbauen.
--
-- Alle Ereignisse laufen ueber T.Events.Game; es entsteht kein eigener Frame.
-- Die Module werden bei jedem Aufruf frisch aus T gelesen (nie zwischengespeichert),
-- damit fehlende Teile (Teilstaende, Tests) nichts verhindern.
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.Boot = T.Boot or {}
local Boot = T.Boot

local L = T.L

local format = string.format

local ADDON_NAME = "Transmog"

local GOSSIP_WINDOW = 3         -- s nach "Open" gilt ein GOSSIP_SHOW als das des Transmogrifizierers
local GOSSIP_CLOSE_GRACE = 1    -- s nach dem Oeffnen, in denen GOSSIP_CLOSED das Fenster nicht schliesst
local GOSSIP_RECHECK = 0.15      -- s nach dem Ersetzen: Gossip-Fenster nochmals pruefen (siehe HideGossipAgain)

-- Anzeigereihenfolge der Module beim Anmelden: { Name, Funktion die das Modul liefert }.
local LOGIN_STEPS = {
   { "Slots",    function() return T.Slots end },
   { "Items",    function() return T.Items end },
   { "Net",      function() return T.Net end },
   { "State",    function() return T.State end },
   { "Outfits",  function() return T.Outfits end },
   { "Tooltips", function() return T.Tooltips end },
   { "Toasts",   function() return T.Toasts end },
   { "Window",   function() return T.UI and T.UI.Window end },
}

-- Zustand der Sitzung (beim Laden der Datei neu)
local session = {
   worldSeen = false,    -- PLAYER_ENTERING_WORLD schon gesehen?
   inited = false,       -- Boot.Init gelaufen
   loginDone = false,    -- PLAYER_LOGIN abgearbeitet
   takingOver = false,   -- OnGossipShow ersetzt gerade das Gossip-Fenster (GOSSIP_CLOSED ignorieren)
}

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------

-- Aktuelle Spielzeit.
local function Now()
   if type(GetTime) == "function" then
      return GetTime()
   end
   return 0
end

-- Hauptfenster (kann fehlen oder von Tests ersetzt sein; immer frisch lesen).
local function Win()
   return T.UI and T.UI.Window or nil
end

-- Chatzeile (Util.Print) mit Format; ohne Util faellt sie still aus.
local function Print(fmt, ...)
   local u = T.Util
   if u and u.Print then
      u.Print(fmt, ...)
   end
end

-- Fehlerzeile im Chat (rot).
local function PrintError(fmt, ...)
   local u = T.Util
   if u and u.Error then
      u.Error(fmt, ...)
   end
end

-- Meldet den Ausfall eines Schritts: Fehlerbehandler des Spiels (mit der
-- genauen Meldung) und eine kurze Zeile im Chat.
local function Report(step, err)
   local getter = _G.geterrorhandler
   local handler = type(getter) == "function" and getter() or nil
   if type(handler) == "function" then
      pcall(handler, format("Transmog: %s: %s", tostring(step), tostring(err)))
   end
   PrintError(L.BOOT_INIT_FAILED, tostring(step))
end

-- Fuehrt fn geschuetzt aus; bei einem Fehler wird er gemeldet. Rueckgabe: ok.
local function Step(name, fn, ...)
   local ok, err = pcall(fn, ...)
   if not ok then
      Report(name, err)
   end
   return ok
end

-- ---------------------------------------------------------------------------
-- Tastenbelegung
-- ---------------------------------------------------------------------------

-- Setzt die Anzeigenamen der Tastenbelegung aus L (Bindings.xml: TRANSMOG_TOGGLE).
function Boot.SetBindingNames()
   BINDING_HEADER_TRANSMOG = L.BOOT_BINDING_HEADER
   BINDING_NAME_TRANSMOG_TOGGLE = L.BOOT_BINDING_TOGGLE
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

-- ADDON_LOADED: gespeicherte Daten und Sprache (erst jetzt gibt es die SavedVariables).
function Boot.OnAddonLoaded(event, name)
   if name ~= ADDON_NAME and name ~= T.ADDON then
      return
   end
   Step("DB", function()
      T.DB.Init()
   end)
   Step("Locale", function()
      local db = T.DB
      local code = db and db.global and db.global.locale or "auto"
      T.Locale.Set(code)
   end)
   Step("Bindings", Boot.SetBindingNames)
end

-- PLAYER_LOGIN: Module in fester Reihenfolge starten, eine Zeile in den Chat.
function Boot.OnLogin()
   if session.loginDone then
      return
   end
   session.loginDone = true

   -- Kam ADDON_LOADED nicht vorher (Sonderfall): DB und Sprache nachholen.
   local db = T.DB
   if db and not db.global then
      Boot.OnAddonLoaded("ADDON_LOADED", ADDON_NAME)
   end

   Step("Player", function()
      T.RefreshPlayerInfo()
   end)
   for i = 1, #LOGIN_STEPS do
      local name, getter = LOGIN_STEPS[i][1], LOGIN_STEPS[i][2]
      local mod = getter()
      if type(mod) == "table" and type(mod.Init) == "function" then
         Step(name, mod.Init)
      end
   end

   Print(L.LOADED, T.ADDON or ADDON_NAME, T.VERSION or "?")
end

-- Entprelltes Refresh (2 s nach dem Laden einer Zone).
local function DelayedRefresh()
   local state = T.State
   if state and state.Refresh then
      state.Refresh()
   end
end

-- PLAYER_ENTERING_WORLD: Login-Sweep-Fenster nur beim ersten Mal der Sitzung.
function Boot.OnEnterWorld()
   if not session.worldSeen then
      session.worldSeen = true
      T.enteredWorldAt = Now()
   end
   local u = T.Util
   if u and u.Debounce then
      u.Debounce("boot-refresh", 2, DelayedRefresh)
   end
end

-- Sicherheitsnetz zu OnGossipShow: Die Reihenfolge, in der Rahmen dasselbe Ereignis
-- bekommen, ist nicht garantiert. Kam das GOSSIP_SHOW des Blizzard-Fensters NACH
-- unserem Handler, zeigt sich das Gossip-Fenster erst jetzt: es wird wieder
-- versteckt, solange unser Fenster gerade per NPC geoeffnet wurde.
-- Ersetzt ein Gossip-Ersatz-Addon (Immersion, Storyline, ...) das Blizzard-Fenster,
-- wird GossipFrame nie gezeigt: HideUIPanel tut dann nichts, das OnHide mit
-- CloseGossip() laeuft nie und das Gespraech bliebe samt fremder Oberflaeche und
-- deren Tastenbelegung offen. Deshalb schliesst dieser Aufruf das Gespraech
-- selbst (CloseGossip; alle Addons bekommen ihr GOSSIP_CLOSED und raeumen selbst
-- auf). Er laeuft erst nach allen GOSSIP_SHOW-Handlern; ein sofortiges
-- CloseGossip() in OnGossipShow kaeme vor dem Handler eines spaeteren Addons
-- und liesse dessen Fenster stehen (ein zweites CloseGossip() waere wirkungslos).
local function HideGossipAgain()
   local state, win = T.State, Win()
   if not state or not state.openedByNpc then
      return
   end
   if not (win and win.IsShown and win.IsShown()) then
      return
   end
   if Now() - (tonumber(win.openedAt) or 0) > GOSSIP_CLOSE_GRACE then
      return
   end
   session.takingOver = true
   if GossipFrame and GossipFrame:IsShown() then
      pcall(HideUIPanel, GossipFrame)
   end
   if type(CloseGossip) == "function" then
      pcall(CloseGossip)
   end
   session.takingOver = false
end

-- GOSSIP_SHOW: Hat der Server soeben "Open" gesendet, ersetzt unser Fenster das
-- Gossip-Fenster. WICHTIG: erst HideUIPanel(GossipFrame) -- das ruft ueber das
-- OnHide des GossipFrame CloseGossip() und loest synchron GOSSIP_CLOSED aus --,
-- DANN Window.Open (siehe OnGossipClosed). Hat ein Gossip-Ersatz-Addon das
-- GossipFrame abgekoppelt, ist HideUIPanel wirkungslos; das Gespraech schliesst
-- dann HideGossipAgain (nach 0,15 s, wenn alle Handler gelaufen sind).
function Boot.OnGossipShow()
   local state = T.State
   if not state then
      return
   end
   local at = state.serverOpenAt
   if type(at) ~= "number" or Now() - at >= GOSSIP_WINDOW then
      return
   end
   -- Ohne Fenster bleibt das normale Gossip-Fenster stehen.
   local win = Win()
   if not win or type(win.Open) ~= "function" then
      return
   end
   -- Das Fenster wird VOR dem Verstecken des Gossip-Fensters gebaut: gelingt das
   -- nicht, bleibt dem Spieler das normale Gossip-Fenster (sonst stuende er ohne
   -- jede Oberflaeche am NPC).
   if type(win.Create) == "function" then
      local ok, frame = pcall(win.Create)
      if not ok then
         Report("Window", frame)
         return
      elseif not frame then
         return
      end
   end
   state.serverOpenAt = nil
   -- Das synchrone GOSSIP_CLOSED von HideUIPanel gehoert zu diesem Ersetzen und
   -- darf das Fenster nicht schliessen, auch nicht, wenn es schon (per NPC)
   -- offen ist und der NPC erneut angesprochen wurde.
   session.takingOver = true
   local ok, err = pcall(function()
      if GossipFrame then
         HideUIPanel(GossipFrame)
      end
   end)
   session.takingOver = false
   if not ok then
      Report("Gossip", err)
   end
   win.Open({ fromNpc = true })
   local u = T.Util
   if u and u.After then
      u.After(GOSSIP_RECHECK, HideGossipAgain)
   end
end

-- GOSSIP_CLOSED: schliesst das Fenster nur, wenn es per NPC geoeffnet wurde,
-- sichtbar ist und das Oeffnen laenger als 1 s her ist (sonst wuerde der
-- synchrone Event von HideUIPanel es sofort wieder schliessen).
function Boot.OnGossipClosed()
   if session.takingOver then
      return
   end
   local state, win = T.State, Win()
   if not state or not win or not state.openedByNpc then
      return
   end
   if not (win.IsShown and win.IsShown()) then
      return
   end
   if Now() - (tonumber(win.openedAt) or 0) > GOSSIP_CLOSE_GRACE then
      win.Close()
   end
end

-- ---------------------------------------------------------------------------
-- Slash-Befehle
-- ---------------------------------------------------------------------------

-- Fehlt das Fenster, gibt es eine kurze Meldung statt eines Fehlers.
local function NeedWindow()
   local win = Win()
   if not win then
      PrintError("%s", L.BOOT_UNAVAILABLE)
   end
   return win
end

-- Die Sprachcodes als Text "auto, enUS, deDE ...".
local function LanguageList()
   local names = { "auto" }
   local loc = T.Locale
   local list = loc and loc.List and loc.List() or {}
   for i = 1, #list do
      names[#names + 1] = list[i].code
   end
   return table.concat(names, ", ")
end

-- Sucht den Sprachcode zu einer Eingabe (ohne Beachtung der Gross-/Kleinschreibung;
-- "de", "fr", "es", "ru", "ko", "en" genuegen). Rueckgabe: Code oder nil.
local function ResolveLanguage(arg)
   local want = string.lower(arg or "")
   if want == "" then
      return nil
   end
   if want == "auto" then
      return "auto"
   end
   local loc = T.Locale
   local list = loc and loc.List and loc.List() or {}
   for i = 1, #list do
      if string.lower(list[i].code) == want then
         return list[i].code
      end
   end
   -- Codes, die es nur als Alias gibt (Fallbackkette der Sprachen)
   if want == "engb" then
      return "enGB"
   elseif want == "esmx" then
      return "esMX"
   end
   -- Kurzformen: zwei Buchstaben, eindeutig am Anfang des Codes
   if #want == 2 then
      local found
      for i = 1, #list do
         if string.lower(string.sub(list[i].code, 1, 2)) == want then
            if found then
               return nil
            end
            found = list[i].code
         end
      end
      return found
   end
   return nil
end

-- /transmog (leer): Fenster umschalten.
local function CmdToggle()
   local win = NeedWindow()
   if win and win.Toggle then
      win.Toggle()
   end
end

-- /transmog options: Einstellungen oeffnen.
local function CmdOptions()
   local opt = T.UI and T.UI.Options
   if opt and opt.Open then
      opt.Open()
   else
      PrintError("%s", L.BOOT_UNAVAILABLE)
   end
end

-- /transmog reset: Fensterposition und -groesse zuruecksetzen.
local function CmdReset()
   local win = NeedWindow()
   if win and win.ResetLayout then
      win.ResetLayout()
      Print("%s", L.BOOT_RESET_DONE)
   end
end

-- /transmog toast: Verschiebe-Anker der Benachrichtigungen zeigen.
local function CmdToast()
   local toasts = T.Toasts
   if toasts and toasts.ShowAnchor then
      toasts.ShowAnchor()
   else
      PrintError("%s", L.BOOT_UNAVAILABLE)
   end
end

-- /transmog lang <code|auto>: Sprache setzen (ohne Argument: aktuelle Sprache).
local function CmdLang(rest)
   local loc = T.Locale
   if not loc then
      PrintError("%s", L.BOOT_UNAVAILABLE)
      return
   end
   rest = T.Util and T.Util.Trim(rest) or rest or ""
   if rest == "" then
      local db = T.DB
      local wanted = db and db.global and db.global.locale or "auto"
      Print(L.BOOT_LANG_CURRENT, tostring(wanted) .. " (" .. tostring(loc.Current()) .. ")", LanguageList())
      return
   end
   local code = ResolveLanguage(rest)
   if not code then
      PrintError(L.BOOT_LANG_UNKNOWN, rest, LanguageList())
      return
   end
   if T.DB and T.DB.Set then
      T.DB.Set("locale", code)
   end
   loc.Set(code)
   Print(L.BOOT_LANG_SET, code == "auto" and ("auto (" .. tostring(loc.Current()) .. ")") or code)
end

-- Text "ja"/"nein" fuer die Diagnose.
local function YesNo(v)
   if v then
      return L.BOOT_YES
   end
   return L.BOOT_NO
end

-- Gibt den Zustand der Module aus (Diagnose, /transmog debug).
function Boot.PrintDebugState()
   local net, state, items, util = T.Net, T.State, T.Items, T.Util
   Print(L.BOOT_DEBUG_INFO, tostring(T.VERSION), tostring(T.Locale and T.Locale.Current() or "?"),
      tostring(net and net.state or "?"), tonumber(net and net.sentCount) or 0,
      tonumber(net and net.receivedCount) or 0)
   if state then
      local lists = state.ListsReady and state.ListsReady()
      Print(L.BOOT_DEBUG_STATE, YesNo(state.atVendor), state.PendingCount and state.PendingCount() or 0,
         YesNo(lists))
   end
   local missing = 0
   if type(L.__missing) == "table" then
      for _ in pairs(L.__missing) do
         missing = missing + 1
      end
   end
   Print(L.BOOT_DEBUG_ITEMS, items and items.PendingCount and items.PendingCount() or 0,
      items and items.FailedCount and items.FailedCount() or 0,
      util and util.TimerCount and util.TimerCount() or 0, missing)
   if items and items.DumpTypes then
      local ok, lines = pcall(items.DumpTypes)
      if ok and type(lines) == "table" then
         for i = 1, #lines do
            Print("%s", lines[i])
         end
      end
   end
end

-- /transmog debug: Diagnoseausgabe umschalten (beim Einschalten mit Zustand).
local function CmdDebug()
   T.debug = not T.debug
   if T.debug then
      Print("%s", L.BOOT_DEBUG_ON)
      Boot.PrintDebugState()
   else
      Print("%s", L.BOOT_DEBUG_OFF)
   end
end

-- /transmog help: Liste der Befehle.
local function CmdHelp()
   Print("%s", L.BOOT_HELP_TITLE)
   Print("%s", L.BOOT_HELP_TOGGLE)
   Print("%s", L.BOOT_HELP_OPTIONS)
   Print("%s", L.BOOT_HELP_RESET)
   Print("%s", L.BOOT_HELP_TOAST)
   Print("%s", L.BOOT_HELP_LANG)
   Print("%s", L.BOOT_HELP_DEBUG)
   Print("%s", L.BOOT_HELP_HELP)
end

-- Befehlstabelle (Kleinschreibung); "optionen" ist das deutsche Wort fuer options.
local COMMANDS = {
   [""] = CmdToggle,
   options = CmdOptions,
   optionen = CmdOptions,
   reset = CmdReset,
   toast = CmdToast,
   lang = CmdLang,
   debug = CmdDebug,
   help = CmdHelp,
}

-- Verarbeitet die Eingabe hinter /transmog (msg ohne den Befehl selbst).
function Boot.Slash(msg)
   msg = tostring(msg or "")
   local cmd, rest = string.match(msg, "^%s*(%S*)%s*(.-)%s*$")
   cmd = string.lower(cmd or "")
   local fn = COMMANDS[cmd]
   if not fn then
      CmdHelp()
      return
   end
   local ok, err = pcall(fn, rest or "")
   if not ok then
      Report("/transmog " .. cmd, err)
   end
end

-- ---------------------------------------------------------------------------
-- Anmeldung der Ereignisse und Befehle
-- ---------------------------------------------------------------------------

-- Registriert Ereignisse, Slash-Befehle und Tastenbelegung (einmalig).
function Boot.Init()
   if session.inited then
      return
   end
   session.inited = true

   local ev = T.Events
   if ev and ev.Game then
      ev.Game("ADDON_LOADED", Boot.OnAddonLoaded)
      ev.Game("PLAYER_LOGIN", Boot.OnLogin)
      ev.Game("PLAYER_ENTERING_WORLD", Boot.OnEnterWorld)
      ev.Game("GOSSIP_SHOW", Boot.OnGossipShow)
      ev.Game("GOSSIP_CLOSED", Boot.OnGossipClosed)
   end
   if ev and ev.On then
      ev.On("LOCALE_CHANGED", Boot.SetBindingNames, Boot)
   end

   SLASH_TRANSMOG1 = "/transmog"
   SLASH_TRANSMOG2 = "/xmog"
   SlashCmdList["TRANSMOG"] = function(msg)
      Boot.Slash(msg)
   end

   -- Kompatibilitaet mit dem alten Addon (/transmogdebug, /transmogreset). Die
   -- Listenschluessel enden auf eine Ziffer, damit auch die zugehoerigen Globals
   -- (SLASH_TRANSMOG31, SLASH_TRANSMOG41) dem Namensraum SLASH_TRANSMOG<Ziffern>
   -- aus SPEC 1 Regel 7 folgen; das Spiel sucht SLASH_<Schluessel><1,2,...>.
   SLASH_TRANSMOG31 = "/transmogdebug"
   SlashCmdList["TRANSMOG3"] = function()
      CmdDebug()
   end
   SLASH_TRANSMOG41 = "/transmogreset"
   SlashCmdList["TRANSMOG4"] = function()
      CmdReset()
   end

   Boot.SetBindingNames()
end

Boot.Init()
