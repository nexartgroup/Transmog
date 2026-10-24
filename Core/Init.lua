-- Init.lua
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Grunddaten: Version, Spielerinfo, Farben.
--
-- Beim Laden passiert hier nichts Spielabhaengiges ausser dem (geschuetzten)
-- Lesen von Rasse/Klasse; Core\Boot.lua ruft T.RefreshPlayerInfo() nach
-- PLAYER_LOGIN erneut.
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog

T.ADDON     = "Transmog"
T.VERSION   = "2.1"
T.PREFIX    = "transmog"   -- Praefix der Addon-Nachrichten (SendAddonMessage)
T.HIDDEN_ID = 999999       -- Server: HIDDEN_ITEM_ID ("verborgen")
T.debug     = false

-- Farben (r, g, b) und Farbcodes (|cffRRGGBB) -- gemeinsam fuer alle Module.
T.COLORS = {
   accent = { 0.20, 0.62, 0.92 },
   text   = { 0.86, 0.88, 0.92 },
   dim    = { 0.50, 0.54, 0.60 },
   yellow = { 0.91, 0.77, 0.29 },
   green  = { 0.33, 0.82, 0.48 },
   red    = { 0.91, 0.40, 0.29 },
   blue   = { 0.35, 0.71, 0.91 },
   grey   = { 0.35, 0.38, 0.44 },
   pink   = { 0.96, 0.44, 0.96 },
}

T.HEX = {
   accent = "|cff339eeb",
   text   = "|cffdbe0eb",
   dim    = "|cff808a99",
   yellow = "|cffe8c44a",
   green  = "|cff53d17a",
   red    = "|cffe8654a",
   blue   = "|cff58b6e8",
   grey   = "|cff9099a8",
   pink   = "|cfff471f5",
   white  = "|cffffffff",
}

-- Rassen-Token (klein) -> Fraktion
local ALLIANCE = {
   human = true, dwarf = true, nightelf = true, gnome = true,
   draenei = true, worgen = true,
}
local HORDE = {
   orc = true, scourge = true, undead = true, tauren = true, troll = true,
   bloodelf = true, goblin = true,
}

-- Vorbelegung, falls die Abfrage fehlschlaegt
T.race = "human"
T.class = "warrior"
T.faction = "A"

-- Liest Rasse, Klasse und Fraktion des Spielers neu ein; keine Rueckgabe.
function T.RefreshPlayerInfo()
   local race = "human"
   if type(UnitRace) == "function" then
      local ok, _, token = pcall(UnitRace, "player")
      if ok and type(token) == "string" and token ~= "" then
         race = string.lower(token)
      end
   end
   T.race = race

   local class = T.class or "warrior"
   if type(UnitClass) == "function" then
      local ok, _, token = pcall(UnitClass, "player")
      if ok and type(token) == "string" and token ~= "" then
         class = string.lower(token)
      end
   end
   T.class = class

   local faction
   if ALLIANCE[race] then
      faction = "A"
   elseif HORDE[race] then
      faction = "H"
   else
      -- unbekanntes Token: die Fraktionsabfrage des Spiels entscheiden lassen
      faction = "A"
      if type(UnitFactionGroup) == "function" then
         local ok, group = pcall(UnitFactionGroup, "player")
         if ok and group == "Horde" then
            faction = "H"
         end
      end
   end
   T.faction = faction
end

-- Liefert true, solange PLAYER_ENTERING_WORLD noch nicht oder weniger als
-- 10 Sekunden her ist (Login-Sweep des Servers: CollectionUpdated fuer alles).
function T.IsLoginSweep()
   local at = T.enteredWorldAt
   if not at then
      return true
   end
   if type(GetTime) ~= "function" then
      return false
   end
   return (GetTime() - at) < 10
end

T.RefreshPlayerInfo()
