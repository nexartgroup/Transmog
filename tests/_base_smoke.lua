-- _base_smoke.lua
-- ---------------------------------------------------------------------------
-- Wegwerf-Rauchtest fuer die Basismodule (Locale, Util, Events, DB, Slots).
-- Ein richtiger Test mit tests/mock_wow.lua und run.lua kommt spaeter; dieser
-- hier bringt nur die wenigen noetigen WoW-Globals als Attrappen mit.
--
--   luajit tests/_base_smoke.lua        (im Hauptverzeichnis des Addons)
-- ---------------------------------------------------------------------------

local scriptPath = (arg and arg[0]) or "tests/_base_smoke.lua"
local ROOT = scriptPath:match("^(.*)[/\\]tests[/\\][^/\\]*$") or "."

-- ---------------------------------------------------------------------------
-- Attrappen
-- ---------------------------------------------------------------------------

local chat = {}
local errors = {}
local frames = {}
local fakeTime = 1000
local fakeLocale = "enUS"

DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) chat[#chat + 1] = text end }

function GetLocale() return fakeLocale end
function GetTime() return fakeTime end
function time() return 1700000000 end
function geterrorhandler()
   return function(msg) errors[#errors + 1] = tostring(msg) end
end
function wipe(t)
   for k in pairs(t) do t[k] = nil end
   return t
end
function UnitRace() return "Night Elf", "NightElf" end
function UnitClass() return "Death Knight", "DEATHKNIGHT" end
function UnitFactionGroup() return "Alliance", "Alliance" end
function GetInventoryItemLink(unit, id)
   if unit == "player" and id == 1 then return "|cff0070dd|Hitem:12345:0:0:0:0:0:0:0:80|h[Test Helm]|h|r" end
   return nil
end
function GetInventorySlotInfo(name)
   if name == "HeadSlot" then return 1, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head", false end
   if name == "BogusSlot" then error("Bad slot") end
   return 2, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. name:gsub("Slot$", ""), false
end

ITEM_QUALITY_COLORS = {
   [0] = { r = 0.62, g = 0.62, b = 0.62, hex = "|cff9d9d9d" },
   [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "|cffa335ee" },
}
HEADSLOT = "Kopf"

-- Frame-Attrappe: merkt sich Skripte/Ereignisse/Sichtbarkeit.
function CreateFrame(kind, name)
   local f = { kind = kind, name = name, scripts = {}, events = {}, shown = true }
   function f:SetScript(n, fn) self.scripts[n] = fn end
   function f:GetScript(n) return self.scripts[n] end
   function f:Show() self.shown = true end
   function f:Hide() self.shown = false; self.hides = (self.hides or 0) + 1 end
   function f:IsShown() return self.shown end
   function f:RegisterEvent(e) self.events[e] = true end
   function f:UnregisterEvent(e) self.events[e] = nil end
   frames[#frames + 1] = f
   return f
end

-- Treibt alle sichtbaren Frames mit OnUpdate um dt Sekunden.
local function Tick(dt)
   fakeTime = fakeTime + dt
   for _, f in ipairs(frames) do
      if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
   end
end

-- ---------------------------------------------------------------------------
-- Mini-Testrahmen
-- ---------------------------------------------------------------------------

local passed, failed = 0, 0

local function check(cond, label)
   if cond then
      passed = passed + 1
   else
      failed = failed + 1
      print("  FEHLER: " .. label)
   end
end

local function eq(actual, expected, label)
   if actual == expected then
      passed = passed + 1
   else
      failed = failed + 1
      print(string.format("  FEHLER: %s\n     erwartet: %s\n     erhalten: %s",
         label, tostring(expected), tostring(actual)))
   end
end

-- ---------------------------------------------------------------------------
-- Dateien in TOC-Reihenfolge laden (nur vorhandene .lua-Dateien der Basis)
-- ---------------------------------------------------------------------------

local BASE_ONLY = {
   ["Locales\\Locale.lua"] = true, ["Locales\\enUS_Core.lua"] = true,
   ["Core\\Init.lua"] = true, ["Core\\Util.lua"] = true,
   ["Core\\Events.lua"] = true, ["Core\\DB.lua"] = true,
   ["Core\\Slots.lua"] = true,
}

local globalsBefore = {}
for k in pairs(_G) do globalsBefore[k] = true end

local function LoadFile(rel)
   local path = ROOT .. "/" .. rel:gsub("\\", "/")
   local chunk, err = loadfile(path)
   if not chunk then error("Laden fehlgeschlagen: " .. tostring(err)) end
   chunk()
end

do
   local f = assert(io.open(ROOT .. "/Transmog.toc", "r"))
   local order = {}
   for line in f:lines() do
      line = line:gsub("\r$", "")
      if line ~= "" and not line:match("^##") and line:match("%.lua$") then
         order[#order + 1] = line
      end
   end
   f:close()
   -- Reihenfolge der Basisdateien muss der TOC folgen
   local seenBase = {}
   for _, rel in ipairs(order) do
      if BASE_ONLY[rel] then
         seenBase[#seenBase + 1] = rel
         LoadFile(rel)
      end
   end
   eq(#seenBase, 7, "alle 7 Basisdateien stehen in der TOC")
   eq(seenBase[1], "Locales\\Locale.lua", "Locale.lua wird zuerst geladen")
end

local T = Transmog
check(type(T) == "table", "Transmog-Tabelle existiert")

-- ---------------------------------------------------------------------------
print("== Init")
eq(T.VERSION, "2.1", "VERSION")
eq(T.ADDON, "Transmog", "ADDON")
eq(T.PREFIX, "transmog", "PREFIX")
eq(T.HIDDEN_ID, 999999, "HIDDEN_ID")
eq(T.debug, false, "debug aus")
eq(T.race, "nightelf", "Rasse klein")
eq(T.class, "deathknight", "Klasse klein")
eq(T.faction, "A", "Nachtelf = Allianz")
eq(T.COLORS.accent[3], 0.92, "COLORS.accent")
eq(T.HEX.pink, "|cfff471f5", "HEX.pink")
eq(T.HEX.white, "|cffffffff", "HEX.white")
eq(T.IsLoginSweep(), true, "Login-Sweep ohne PLAYER_ENTERING_WORLD")
T.enteredWorldAt = GetTime()
eq(T.IsLoginSweep(), true, "Login-Sweep direkt nach Betreten")
fakeTime = fakeTime + 9.5
eq(T.IsLoginSweep(), true, "Login-Sweep nach 9.5 s")
fakeTime = fakeTime + 1
eq(T.IsLoginSweep(), false, "Login-Sweep nach 10.5 s vorbei")

do
   local raceFn = UnitRace
   function UnitRace() return "Draenei", "Draenei" end
   T.RefreshPlayerInfo()
   eq(T.faction, "A", "Draenei = Allianz")
   function UnitRace() return "Undead", "Scourge" end
   T.RefreshPlayerInfo()
   eq(T.race, "scourge", "Scourge-Token")
   eq(T.faction, "H", "Scourge = Horde")
   function UnitRace() return "Blood Elf", "BloodElf" end
   T.RefreshPlayerInfo()
   eq(T.faction, "H", "Blutelf = Horde")
   function UnitRace() error("kaputt") end
   T.RefreshPlayerInfo()
   eq(T.race, "human", "Fehlschlag -> human")
   eq(T.faction, "A", "Fehlschlag -> Allianz")
   UnitRace = raceFn
   T.RefreshPlayerInfo()
end

-- ---------------------------------------------------------------------------
print("== Locale")
local L, Locale = T.L, T.Locale
check(type(L) == "table", "T.L existiert")
eq(L.THOUSANDS_SEP, ",", "enUS THOUSANDS_SEP")
eq(L.LOADED, "%s %s loaded - type /transmog to open the window.", "enUS LOADED")
eq(Locale.Current(), "enUS", "auto + enUS -> enUS")

-- Missing-Key-Aufzeichnung
local v = L.NOT_THERE_KEY
eq(v, "NOT_THERE_KEY", "fehlender Schluessel liefert Schluessel")
check(L.__missing.NOT_THERE_KEY == true, "fehlender Schluessel in __missing")
eq(rawget(L, "NOT_THERE_KEY"), nil, "fehlender Schluessel nicht eingetragen")

-- Add / Set / Fallback
Locale.Add("deDE", { LOADED = "%s %s geladen.", ONLY_DE = "nur deutsch" })
Locale.Add("deDE", { EXTRA = "extra" })
Locale.Add("esES", { LOADED = "%s %s cargado." })
Locale.Add("enUS", { SOME_KEY = "Some %d", ONLY_EN = "only english" })

local fired = 0
local lastArgs
T.Events.On("LOCALE_CHANGED", function(...) fired = fired + 1; lastArgs = select("#", ...) end, "smoke")

local Lid = T.L
eq(Locale.Set("deDE"), "deDE", "Set(deDE) liefert Code")
check(T.L == Lid, "L-Identitaet bleibt")
eq(L.LOADED, "%s %s geladen.", "deDE Text")
eq(L.ONLY_EN, "only english", "Fallback auf enUS")
eq(L.EXTRA, "extra", "zweites Add merged")
eq(L.THOUSANDS_SEP, ",", "enUS-Wert durchgereicht")
eq(Locale.Current(), "deDE", "Current deDE")
eq(fired, 1, "LOCALE_CHANGED gefeuert")
eq(lastArgs, 0, "LOCALE_CHANGED ohne Argumente")

fakeLocale = "esMX"
eq(Locale.Set("auto"), "esES", "auto + esMX -> esES")
eq(L.LOADED, "%s %s cargado.", "esES Text via esMX")
fakeLocale = "enGB"
eq(Locale.Set("auto"), "enUS", "auto + enGB -> enUS")
fakeLocale = "xxXX"
eq(Locale.Set("auto"), "enUS", "auto + unbekannt -> enUS")
fakeLocale = "deDE"
eq(Locale.Set("auto"), "deDE", "auto + deDE -> deDE")
eq(Locale.Set("esMX"), "esES", "explizit esMX -> esES")
eq(Locale.Set("zhTW"), "zhTW", "bekannter Code ohne Daten bleibt")
eq(L.LOADED, "%s %s loaded - type /transmog to open the window.", "ohne Daten -> enUS-Text")
eq(Locale.Set(nil), "deDE", "Set(nil) = auto")
eq(Locale.Set("klingon"), "enUS", "unbekannter Code -> enUS")
Locale.Set("enUS")

-- Add nach Set aktualisiert L sofort
Locale.Add("enUS", { LATE_KEY = "late" })
eq(L.LATE_KEY, "late", "Add nach Set wirkt sofort")
check(L.__missing.LATE_KEY == nil, "spaeter hinzugefuegter Schluessel nicht fehlend")
check(L.__missing.NOT_THERE_KEY == true, "alte fehlende Schluessel bleiben vermerkt")

-- kein Fehler bei seltsamen Zugriffen
local ok = pcall(function() local _ = L[1]; local _2 = L[true]; local _3 = L.__nope end)
check(ok, "seltsame Zugriffe auf L werfen nicht")
check(L.__missing.__nope == nil, "__-Schluessel werden nicht vermerkt")

-- Liste
local list = Locale.List()
eq(#list, 8, "8 Sprachen")
eq(list[1].code, "enUS", "erste Sprache enUS")
eq(list[3].name, "Fran\195\167ais", "Francais mit c-cedille")
eq(list[4].name, "Espa\195\177ol", "Espanol mit n-tilde")
eq(list[5].name, "\208\160\209\131\209\129\209\129\208\186\208\184\208\185", "Russisch")
eq(list[6].name, "\237\149\156\234\181\173\236\150\180", "Koreanisch")
eq(list[7].name, "\231\174\128\228\189\147\228\184\173\230\150\135", "Chinesisch (vereinfacht)")
eq(list[8].name, "\231\185\129\233\171\148\228\184\173\230\150\135", "Chinesisch (traditionell)")
list[1].name = "kaputt"
eq(Locale.List()[1].name, "English", "List liefert Kopie")
fired = 0

-- ---------------------------------------------------------------------------
print("== Util: Text")
local Util = T.Util
eq(Util.Trim("  a b \t\n"), "a b", "Trim")
eq(Util.Trim(nil), "", "Trim(nil)")
eq(Util.Trim("   "), "", "Trim nur Leerraum")

local s = Util.Split("a,b,,c,", ",")
eq(#s, 5, "Split Anzahl")
eq(s[3], "", "Split leeres Feld")
eq(s[5], "", "Split letztes leeres Feld")
s = Util.Split("a::b::c", "::")
eq(#s, 3, "Split langer Trenner")
eq(s[2], "b", "Split langer Trenner Inhalt")
s = Util.Split("a.b", ".")
eq(#s, 2, "Split Klartext-Punkt")
s = Util.Split("", ",")
eq(#s, 1, "Split leerer String")
eq(#Util.Split(nil, ","), 0, "Split nil")

eq(Util.Lower("HeLLo World"), "hello world", "Lower ASCII")
eq(Util.Lower("\195\132\195\150\195\156 \195\128 \195\158"), "\195\164\195\182\195\188 \195\160 \195\190", "Lower Latin-1")
eq(Util.Lower("\195\151"), "\195\151", "Lower laesst Malzeichen")
eq(Util.Lower("\195\159\195\164"), "\195\159\195\164", "Lower laesst Kleinbuchstaben")
eq(Util.Lower("\208\160\208\163\208\161\208\161\208\154\208\152\208\153"), "\209\128\209\131\209\129\209\129\208\186\208\184\208\185", "Lower Kyrillisch")
eq(Util.Lower("\208\144\208\145\208\175"), "\208\176\208\177\209\143", "Lower Kyrillisch A B YA")
eq(Util.Lower("\208\128\208\129\208\143"), "\209\144\209\145\209\159", "Lower Kyrillisch U+0400..040F")
eq(Util.Lower("\228\184\173\230\150\135ABC"), "\228\184\173\230\150\135abc", "Lower CJK unveraendert")
eq(Util.Lower("\237\149\156A"), "\237\149\156a", "Lower Hangul unveraendert")
eq(Util.Lower(nil), "", "Lower(nil)")
eq(Util.Lower(12), "12", "Lower(Zahl)")

eq(Util.G("HEADSLOT", "Head"), "Kopf", "G liefert Global")
eq(Util.G("DOES_NOT_EXIST_X", "Fallback"), "Fallback", "G Fallback")
eq(Util.G("DOES_NOT_EXIST_X"), "DOES_NOT_EXIST_X", "G ohne Fallback nie nil")

eq(Util.ItemIdFromLink("item:123:0:0"), 123, "ItemId item:")
eq(Util.ItemIdFromLink("|cff0070dd|Hitem:19019:0:0:0:0:0:0:0:80|h[Thunderfury]|h|r"), 19019, "ItemId Link")
eq(Util.ItemIdFromLink(42), 42, "ItemId Zahl")
eq(Util.ItemIdFromLink("77"), 77, "ItemId Zahlentext")
eq(Util.ItemIdFromLink("abc"), nil, "ItemId ungueltig")
eq(Util.ItemIdFromLink(nil), nil, "ItemId nil")
eq(Util.ItemIdFromLink(0), nil, "ItemId 0")
eq(Util.ItemIdFromLink(-3), nil, "ItemId negativ")

eq(Util.Format("%d/%d", 1, 2), "1/2", "Format")
eq(Util.Format("100%"), "100%", "Format ohne Argumente laesst %")
eq(Util.Format("%d", "x"), "%d (x)", "Format bei Fehler wirft nicht")
eq(Util.Format("%s", nil), "nil", "Format nil-Argument")

-- ---------------------------------------------------------------------------
print("== Util: Zahlen/Farben")
eq(Util.Clamp(5, 1, 3), 3, "Clamp oben")
eq(Util.Clamp(-5, 1, 3), 1, "Clamp unten")
eq(Util.Clamp(2, 1, 3), 2, "Clamp innen")
eq(Util.Round(2.5), 3, "Round 2.5")
eq(Util.Round(-2.5), -3, "Round -2.5")
eq(Util.Round(2.4), 2, "Round 2.4")
eq(Util.Round(0), 0, "Round 0")

eq(Util.FormatNumber(0), "0", "FormatNumber 0")
eq(Util.FormatNumber(999), "999", "FormatNumber 999")
eq(Util.FormatNumber(1000), "1,000", "FormatNumber 1000")
eq(Util.FormatNumber(1234567), "1,234,567", "FormatNumber 1234567")
eq(Util.FormatNumber(-1234), "-1,234", "FormatNumber negativ")
eq(Util.FormatNumber(1e10), "10,000,000,000", "FormatNumber gross")
Locale.Add("enUS", { THOUSANDS_SEP = "." })
eq(Util.FormatNumber(1234567), "1.234.567", "FormatNumber mit Punkt")
Locale.Add("enUS", { THOUSANDS_SEP = " " })
eq(Util.FormatNumber(1234567), "1 234 567", "FormatNumber mit Leerzeichen")
Locale.Add("enUS", { THOUSANDS_SEP = "," })

local G = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t"
local S = "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:2:0|t"
local C = "|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:2:0|t"
eq(Util.FormatMoney(0), "0" .. C, "FormatMoney 0")
eq(Util.FormatMoney(5), "5" .. C, "FormatMoney Kupfer")
eq(Util.FormatMoney(100), "1" .. S, "FormatMoney 1 Silber")
eq(Util.FormatMoney(10000), "1" .. G, "FormatMoney 1 Gold")
eq(Util.FormatMoney(123456), "12" .. G .. " 34" .. S .. " 56" .. C, "FormatMoney 12g 34s 56c")
eq(Util.FormatMoney(12345678900), "1,234,567" .. G .. " 89" .. S, "FormatMoney sehr viel Gold")
eq(Util.FormatMoney(10001), "1" .. G .. " 1" .. C, "FormatMoney Gold + Kupfer")
eq(Util.FormatMoney(nil), "0" .. C, "FormatMoney nil")

eq(Util.Hex(1, 1, 1), "|cffffffff", "Hex weiss")
eq(Util.Hex(0.2, 0.62, 0.92), "|cff339eeb", "Hex akzent")
eq(Util.Hex(2, -1, 0.5), "|cffff0080", "Hex begrenzt")

local r, g, b, hex = Util.QualityColor(4)
eq(hex, "|cffa335ee", "QualityColor 4 aus ITEM_QUALITY_COLORS")
eq(r, 0.64, "QualityColor r")
r, g, b, hex = Util.QualityColor(2)
eq(hex, "|cff1eff00", "QualityColor 2 Fallback")
r, g, b, hex = Util.QualityColor(nil)
eq(hex, "|cffffffff", "QualityColor nil -> weiss")
r, g, b, hex = Util.QualityColor(99)
eq(hex, "|cffe6cc80", "QualityColor 99 -> 7")

-- Tabellen
local orig = { a = 1, b = { c = { d = 2 } }, 7 }
local copy = Util.CopyTable(orig)
check(copy ~= orig and copy.b ~= orig.b and copy.b.c ~= orig.b.c, "CopyTable tief")
eq(copy.b.c.d, 2, "CopyTable Inhalt")
eq(copy[1], 7, "CopyTable Array")
local cyc = {}
cyc.self = cyc
local cyc2 = Util.CopyTable(cyc)
check(cyc2.self == cyc2, "CopyTable Zyklus")
eq(Util.Count({ a = 1, b = 2, 3 }), 3, "Count")
eq(Util.Count(nil), 0, "Count nil")

-- ---------------------------------------------------------------------------
print("== Util: Print/Error/Debug")
chat = {}
Util.Print("hallo %s %d", "welt", 5)
eq(chat[1], "|cff33a0ea[Transmog]|r hallo welt 5", "Print mit Format")
Util.Print("100% sicher")
eq(chat[2], "|cff33a0ea[Transmog]|r 100% sicher", "Print ohne Argumente")
Util.Error("fehler %d", 3)
eq(chat[3], "|cff33a0ea[Transmog]|r |cffe8654afehler 3|r", "Error rot")
Util.Debug("nicht sichtbar")
eq(#chat, 3, "Debug aus")
T.debug = true
Util.Debug("sichtbar %d", 1)
eq(#chat, 4, "Debug an")
check(chat[4]:find("sichtbar 1", 1, true) ~= nil, "Debug Inhalt")
T.debug = false

-- ---------------------------------------------------------------------------
print("== Util: Timer")
local log = {}
local driverFrame
for _, f in ipairs(frames) do
   if f.scripts.OnUpdate then driverFrame = f end
end
check(driverFrame == nil, "Treiber-Frame erst beim ersten Timer")
Util.After(0.01, function() end)
for _, f in ipairs(frames) do
   if f.scripts.OnUpdate then driverFrame = f end
end
check(driverFrame ~= nil, "Treiber-Frame existiert")
eq(driverFrame.shown, true, "Treiber laeuft mit Timer")
Tick(0.02)
eq(driverFrame.shown, false, "Treiber im Leerlauf versteckt")
eq(Util.TimerCount(), 0, "keine Timer")

local h1 = Util.After(1, function(...) log[#log + 1] = { "a", n = select("#", ...), ... } end, "x", nil, 3)
local h2 = Util.After(0.5, function() log[#log + 1] = { "b" } end)
check(type(h1) == "number" and type(h2) == "number" and h1 ~= h2, "After liefert Handles")
eq(driverFrame.shown, true, "Treiber laeuft mit Timern")
eq(Util.TimerCount(), 2, "2 Timer")
Tick(0.4)
eq(#log, 0, "noch nichts faellig")
Tick(0.2)
eq(#log, 1, "b nach 0.6 s")
eq(log[1][1], "b", "b zuerst")
Tick(0.5)
eq(#log, 2, "a nach 1.1 s")
eq(log[2].n, 3, "Argumentanzahl samt nil erhalten")
eq(log[2][2], "x", "erstes Argument")
eq(log[2][3], nil, "zweites Argument nil")
eq(log[2][4], 3, "drittes Argument")
eq(driverFrame.shown, false, "Treiber nach Ablauf versteckt")
eq(Util.TimerCount(), 0, "keine Timer mehr")

-- Cancel
log = {}
local hc = Util.After(1, function() log[#log + 1] = "nie" end)
eq(Util.Cancel(hc), true, "Cancel erfolgreich")
eq(Util.Cancel(hc), false, "Cancel doppelt")
eq(Util.Cancel(nil), false, "Cancel nil")
eq(driverFrame.shown, false, "Treiber nach Cancel versteckt")
Tick(2)
eq(#log, 0, "abgebrochener Timer lief nicht")

-- Debounce
log = {}
Util.Debounce("k", 1, function() log[#log + 1] = "d1" end)
Tick(0.6)
Util.Debounce("k", 1, function() log[#log + 1] = "d2" end)
Tick(0.6)
eq(#log, 0, "Debounce re-armt")
Tick(0.5)
eq(#log, 1, "Debounce feuert einmal")
eq(log[1], "d2", "Debounce nimmt letzte Funktion")
Util.Debounce("k2", 1, function() log[#log + 1] = "x" end)
eq(Util.Cancel("k2"), true, "Cancel per Debounce-Schluessel")
Tick(2)
eq(#log, 1, "per Schluessel abgebrochen")

-- Fehler im Timer: geschuetzt, Fehlerbehandler, Treiber laeuft weiter
errors, log = {}, {}
Util.After(0.1, function() error("timer-boom") end)
Util.After(0.1, function() log[#log + 1] = "danach" end)
Tick(0.2)
eq(#errors, 1, "Timerfehler gemeldet")
check(errors[1]:find("timer-boom", 1, true) ~= nil, "Fehlertext")
eq(#log, 1, "folgender Timer lief trotzdem")

-- Timer aus Timer, Abbruch eines faelligen Timers im gleichen Durchlauf
log = {}
local hLater
Util.After(0.1, function()
   log[#log + 1] = "first"
   Util.Cancel(hLater)
   Util.After(0, function() log[#log + 1] = "nested" end)
end)
hLater = Util.After(0.1, function() log[#log + 1] = "cancelled" end)
Tick(0.2)
eq(table.concat(log, ","), "first", "faelliger Timer abgebrochen, verschachtelter noch nicht")
Tick(0.01)
eq(table.concat(log, ","), "first,nested", "verschachtelter Timer im naechsten Frame")
eq(driverFrame.shown, false, "Leerlauf nach Verschachtelung")

check(Util.After(1, nil) == nil, "After ohne Funktion")

-- Uhr laeuft auch, wenn nur GetTime() weiterzaehlt (elapsed = 0)
log = {}
Util.After(5, function() log[#log + 1] = "gettime" end)
fakeTime = fakeTime + 4
driverFrame.scripts.OnUpdate(driverFrame, 0)
eq(#log, 0, "nach 4 s GetTime noch nicht faellig")
fakeTime = fakeTime + 1.5
driverFrame.scripts.OnUpdate(driverFrame, 0)
eq(#log, 1, "nach 5.5 s GetTime faellig")
eq(driverFrame.shown, false, "Leerlauf nach GetTime-Lauf")

-- lange Pause im Leerlauf darf einen neuen Timer nicht vorzeitig ausloesen
log = {}
fakeTime = fakeTime + 600
Util.After(2, function() log[#log + 1] = "spaet" end)
driverFrame.scripts.OnUpdate(driverFrame, 0.016)
eq(#log, 0, "Leerlaufpause loest neuen Timer nicht vorzeitig aus")
Tick(2.1)
eq(#log, 1, "Timer feuert nach seiner Zeit")

-- ---------------------------------------------------------------------------
print("== Events")
local Events = T.Events
local calls = {}
local function hA(...) calls[#calls + 1] = "A:" .. table.concat({ tostring((...)), tostring((select(2, ...))) }, ",") end
local function hB() calls[#calls + 1] = "B" end
local function hC() calls[#calls + 1] = "C" end
eq(Events.On("T_EVT", hA, "ownerA"), true, "On")
Events.On("T_EVT", hB, "ownerB")
Events.On("T_EVT", hC)
eq(Events.On("T_EVT", hB, "ownerB"), false, "On dedupliziert")
Events.Fire("T_EVT", 1, 2)
eq(table.concat(calls, " "), "A:1,2 B C", "Reihenfolge der Handler")

calls = {}
eq(Events.Off("T_EVT", nil), 0, "Off(nil) tut nichts")
eq(Events.Off("T_EVT", "ownerB"), 1, "Off per owner")
Events.Fire("T_EVT", 5, 6)
eq(table.concat(calls, " "), "A:5,6 C", "ownerB abgemeldet")
calls = {}
eq(Events.Off("T_EVT", hC), 1, "Off per Funktion")
Events.Fire("T_EVT", 7, 8)
eq(table.concat(calls, " "), "A:7,8", "hC abgemeldet")
Events.Fire("UNKNOWN_EVT")   -- darf nicht werfen

-- Fehler im Handler: Rest laeuft, Fehler nur einmal gemeldet
errors, calls = {}, {}
Events.On("T_ERR", function() error("evt-boom") end, "bad")
Events.On("T_ERR", hB, "good")
Events.Fire("T_ERR")
Events.Fire("T_ERR")
Events.Fire("T_ERR")
eq(#errors, 1, "gleicher Fehler nur einmal gemeldet")
eq(#calls, 3, "guter Handler lief jedes Mal")
Events.On("T_ERR2", function() error({ code = 1 }) end)
Events.Fire("T_ERR2")
eq(#errors, 2, "Fehler mit Tabelle als Meldung")

-- Aenderung der Liste waehrend Fire
calls = {}
local function late() calls[#calls + 1] = "late" end
local function selfRemoving()
   calls[#calls + 1] = "once"
   Events.Off("T_MOD", "self")
   Events.Off("T_MOD", "victim")
   Events.On("T_MOD", late, "late")
end
Events.On("T_MOD", selfRemoving, "self")
Events.On("T_MOD", function() calls[#calls + 1] = "victim" end, "victim")
Events.On("T_MOD", function() calls[#calls + 1] = "tail" end, "tail")
Events.Fire("T_MOD")
eq(table.concat(calls, " "), "once tail", "Abgemeldete uebersprungen, neue erst naechstes Mal")
calls = {}
Events.Fire("T_MOD")
eq(table.concat(calls, " "), "tail late", "zweiter Durchlauf")

-- WoW-Ereignisse
local gameFrame
for _, f in ipairs(frames) do
   if f.scripts.OnEvent then gameFrame = f end
end
check(gameFrame == nil, "Ereignis-Frame erst bei Bedarf")
local seen = {}
local function gA(event, a, b) seen[#seen + 1] = event .. ":" .. tostring(a) .. ":" .. tostring(b) end
local function gB() seen[#seen + 1] = "gB" end
eq(Events.Game("CHAT_MSG_ADDON", gA), true, "Game")
eq(Events.Game("CHAT_MSG_ADDON", gA), false, "Game dedupliziert")
Events.Game("CHAT_MSG_ADDON", gB)
Events.Game("PLAYER_LOGIN", gB)
for _, f in ipairs(frames) do
   if f.scripts.OnEvent then gameFrame = f end
end
check(gameFrame ~= nil, "Ereignis-Frame vorhanden")
check(gameFrame.events.CHAT_MSG_ADDON and gameFrame.events.PLAYER_LOGIN, "Ereignisse registriert")
gameFrame.scripts.OnEvent(gameFrame, "CHAT_MSG_ADDON", "transmog", "Open")
eq(table.concat(seen, " "), "CHAT_MSG_ADDON:transmog:Open gB", "Game-Dispatch")
eq(Events.UnGame("CHAT_MSG_ADDON", gA), true, "UnGame")
check(gameFrame.events.CHAT_MSG_ADDON == true, "Ereignis bleibt, solange Handler da sind")
eq(Events.UnGame("CHAT_MSG_ADDON", gB), true, "UnGame zweiter")
check(gameFrame.events.CHAT_MSG_ADDON == nil, "Ereignis abgemeldet, wenn keine Handler mehr")
eq(Events.UnGame("CHAT_MSG_ADDON", gB), false, "UnGame doppelt")
errors = {}
Events.Game("PLAYER_LOGOUT", function() error("game-boom") end)
gameFrame.scripts.OnEvent(gameFrame, "PLAYER_LOGOUT")
eq(#errors, 1, "Game-Handlerfehler gemeldet")

-- ---------------------------------------------------------------------------
print("== Slots")
local Slots = T.Slots
eq(Slots.COUNT, 14, "COUNT")
eq(#Slots.LIST, 14, "LIST")
local order = {}
for i, def in ipairs(Slots.LIST) do order[i] = def.key end
eq(table.concat(order, " "),
   "HEAD SHOULDER BACK CHEST SHIRT TABARD WRIST HANDS WAIST LEGS FEET MAINHAND OFFHAND RANGED",
   "Anzeigereihenfolge")
local serverSet = {}
for _, def in ipairs(Slots.LIST) do
   check(def.client == def.server + 1, "client = server + 1 fuer " .. def.key)
   check(Slots.BY_SERVER[def.server] == def and Slots.BY_KEY[def.key] == def
      and Slots.BY_CLIENT[def.client] == def, "Indizes fuer " .. def.key)
   serverSet[def.server] = true
end
local expected = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }
for _, sv in ipairs(expected) do check(serverSet[sv], "Server-Slot " .. sv .. " vorhanden") end
eq(Slots.BY_KEY.HEAD.invName, "HeadSlot", "invName HEAD")
eq(Slots.BY_KEY.OFFHAND.invName, "SecondaryHandSlot", "invName OFFHAND")
eq(Slots.BY_KEY.OFFHAND.globalName, "SECONDARYHANDSLOT", "globalName OFFHAND")
eq(Slots.BY_KEY.WRIST.client, 9, "WRIST client 9")
eq(Slots.BY_KEY.TABARD.client, 19, "TABARD client 19")
eq(Slots.BY_KEY.MAINHAND.column, 2, "MAINHAND Spalte 2")
eq(Slots.BY_KEY.WRIST.index, 7, "WRIST index 7")
eq(Slots.BY_KEY.RANGED.index, 7, "RANGED index 7")
check(Slots.BY_KEY.MAINHAND.hand and Slots.BY_KEY.OFFHAND.hand and not Slots.BY_KEY.RANGED.hand, "hand-Flags")
check(Slots.BY_KEY.MAINHAND.weapon and Slots.BY_KEY.OFFHAND.weapon and Slots.BY_KEY.RANGED.weapon
   and not Slots.BY_KEY.HEAD.weapon, "weapon-Flags")

local hideable = {}
for sv = 0, 18 do if Slots.IsHideable(sv) then hideable[#hideable + 1] = sv end end
eq(table.concat(hideable, ","), "0,2,3,4,5,6,7,8,9,14,18", "IsHideable-Menge")
eq(Slots.IsHideable(1), false, "Hals nicht hideable")
eq(Slots.IsHideable(nil), false, "IsHideable(nil)")

eq(Slots.Label(0), "Kopf", "Label aus Blizzard-Global")
eq(Slots.Label(15), "Main Hand", "Label englischer Fallback")
eq(Slots.Label(99), "?", "Label unbekannt")
eq(Slots.EmptyTexture(0), "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head", "EmptyTexture HEAD")
eq(Slots.EmptyTexture(2), "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder", "EmptyTexture via GetInventorySlotInfo")
eq(Slots.EmptyTexture(99), "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest", "EmptyTexture unbekannt")
do
   local saved = GetInventorySlotInfo
   function GetInventorySlotInfo() error("nicht da") end
   Slots.Init()
   -- (der Umhang nutzt auch im echten Spiel die Brusttextur)
   eq(Slots.EmptyTexture(14), "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest", "EmptyTexture Fallback bei Fehler")
   eq(Slots.EmptyTexture(8), "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists", "EmptyTexture Fallback Wrists")
   GetInventorySlotInfo = saved
   Slots.Init()
end
eq(Slots.EquippedLink(0), "|cff0070dd|Hitem:12345:0:0:0:0:0:0:0:80|h[Test Helm]|h|r", "EquippedLink")
eq(Slots.EquippedLink(2), nil, "EquippedLink leer")
eq(Slots.EquippedLink(99), nil, "EquippedLink unbekannt")

eq(Slots.Next(0, 1), 2, "Next HEAD -> SHOULDER")
eq(Slots.Next(2, 1), 14, "Next SHOULDER -> BACK")
eq(Slots.Next(8, 1), 9, "Next WRIST -> HANDS (Spaltenwechsel)")
eq(Slots.Next(17, 1), 0, "Next RANGED -> HEAD (zyklisch)")
eq(Slots.Next(0, -1), 17, "Prev HEAD -> RANGED (zyklisch)")
eq(Slots.Next(9, -1), 8, "Prev HANDS -> WRIST")
eq(Slots.Next(15, nil), 16, "Next ohne dir = vorwaerts")
eq(Slots.Next(nil, 1), 0, "Next(nil, +) = erster")
eq(Slots.Next(99, -1), 17, "Next(unbekannt, -) = letzter")
-- 14 Schritte vorwaerts = einmal rum
local sv = 0
for _ = 1, 14 do sv = Slots.Next(sv, 1) end
eq(sv, 0, "14 Schritte = Ausgangspunkt")

-- ---------------------------------------------------------------------------
print("== DB")
local DB = T.DB
TransmogGlobalDB, TransmogDB = nil, nil
transmogOutfits, transmogSettings = nil, nil

local settingsFired = {}
Events.On("SETTINGS_CHANGED", function(key) settingsFired[#settingsFired + 1] = key end, "dbtest")

local g, c = DB.Init()
check(g == DB.global and c == DB.char, "Init liefert Tabellen")
check(TransmogGlobalDB == DB.global and TransmogDB == DB.char, "SavedVariables-Globals gesetzt")
eq(g.version, 2, "global.version")
eq(g.locale, "auto", "global.locale")
eq(g.scale, 0, "global.scale")
eq(g.width, 880, "global.width")
eq(g.height, 600, "global.height")
eq(g.point, nil, "global.point nil")
eq(g.previewSize, 1.0, "global.previewSize")
eq(g.sound, true, "global.sound")
eq(g.toasts, true, "global.toasts")
eq(g.tooltipCollected, true, "global.tooltipCollected")
eq(g.tooltipApplied, true, "global.tooltipApplied")
eq(g.allowAnywhere, true, "global.allowAnywhere (seit 2.1 an)")
eq(g.noNpcDefault, true, "global.noNpcDefault (Marke der einmaligen Uebernahme)")
eq(g.lastTab, "items", "global.lastTab")
eq(c.version, 2, "char.version")
eq(type(c.outfits), "table", "char.outfits")
eq(#c.outfits, 0, "char.outfits leer")
eq(type(c.favorites), "table", "char.favorites")
eq(type(c.filter.qualities), "table", "filter.qualities")
eq(type(c.filter.typesOff), "table", "filter.typesOff")
eq(c.filter.hideDuplicates, true, "filter.hideDuplicates")
eq(c.filter.sort, "QUALITY", "filter.sort")
eq(c.filter.favoritesOnly, false, "filter.favoritesOnly")
eq(c.filter.newOnly, false, "filter.newOnly")
eq(c.lastSlot, nil, "char.lastSlot nil")
eq(c.migrated, 2, "migrated gesetzt auch ohne Altdaten")
eq(Util.TimerCount(), 0, "keine Meldung ohne Altdaten")

-- Idempotenz
local g2, c2 = DB.Init()
check(g2 == g and c2 == c, "zweites Init gleiche Tabellen")
c.filter.hideDuplicates = false
DB.Init()
eq(c.filter.hideDuplicates, false, "Init ueberschreibt vorhandene Werte nicht")

-- Set / SetChar
settingsFired = {}
DB.Set("sound", false)
eq(g.sound, false, "Set sound")
eq(settingsFired[1], "sound", "SETTINGS_CHANGED(sound)")
DB.SetChar("lastSlot", 4)
eq(c.lastSlot, 4, "SetChar lastSlot")
eq(settingsFired[2], "lastSlot", "SETTINGS_CHANGED(lastSlot)")
DB.SetChar("lastSlot", 1)   -- Hals ist nicht transmogbar
eq(c.lastSlot, nil, "SetChar lastSlot ungueltig -> nil")
DB.Set("scale", 3)
eq(g.scale, 1.5, "Set scale begrenzt")
DB.Set("point", { "TOPLEFT", "TOPLEFT", 10, -20 })
eq(g.point[3], 10, "Set point")
DB.Set("point", { "CENTER", "UIParent", "CENTER", 5, 6 })
check(g.point ~= nil and g.point[5] == 6, "Set point 5-teilige Form")
DB.Set("point", { "TOPLEFT" })
eq(g.point, nil, "Set point ohne Zahlen -> nil")
DB.Set("point", { point = "TOP", relPoint = "TOP", x = 1, y = 2 })
check(g.point ~= nil and g.point.x == 1, "Set point benannte Form")
DB.Set("point", "TOPLEFT")
eq(g.point, nil, "Set point Text -> nil")
DB.Set("irgendwas", 5)
eq(g.irgendwas, 5, "Set unbekannter Schluessel")
DB.Set("sound", true)

-- Sanitizing: kaputte gespeicherte Daten
TransmogGlobalDB = {
   locale = "klingon", scale = 0.3, width = "breit", height = -5, previewSize = 1.1,
   sound = "ja", toasts = false, point = { "NOWHERE", "CENTER", 0, 0 },
   toastPoint = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -10, y = -10 },
   lastTab = "bogus", allowAnywhere = true, tooltipCollected = 5,
}
TransmogDB = {
   filter = { sort = "RANDOM", qualities = { [0] = false, [3] = true, [9] = false, x = false },
              typesOff = { [401] = true, [402] = false, foo = true }, hideDuplicates = "yes" },
   favorites = { [100] = true, [200] = false, abc = true },
   lastSlot = 12,
   outfits = {
      { name = "Gut", slots = { [0] = 100, [1] = 5, [4] = 999999, [15] = "x" }, time = 5 },
      "kaputt",
      { name = "", slots = {} },
      { name = "KeineSlots" },
      { name = "OhneZeit", slots = { [2] = 7 } },
   },
}
g, c = DB.Init()
eq(g.locale, "auto", "sanitize locale")
eq(g.scale, 0.6, "sanitize scale 0.3 -> 0.6")
eq(g.width, 880, "sanitize width Text")
eq(g.height, 600, "sanitize height negativ")
eq(g.previewSize, 1.0, "sanitize previewSize 1.1 -> 1.0")
eq(g.sound, true, "sanitize sound Text -> Vorgabe")
eq(g.toasts, false, "toasts bleibt false")
eq(g.point, nil, "sanitize point ungueltig")
eq(g.toastPoint.x, -10, "toastPoint benannte Form bleibt")
eq(g.lastTab, "items", "sanitize lastTab")
eq(g.allowAnywhere, true, "allowAnywhere bleibt")
eq(g.noNpcDefault, true, "Marke gesetzt")
eq(g.tooltipCollected, true, "sanitize tooltipCollected")
eq(c.filter.sort, "QUALITY", "sanitize sort")
eq(c.filter.qualities[0], false, "qualities[0] bleibt")
eq(c.filter.qualities[3], nil, "qualities true entfernt")
eq(c.filter.qualities[9], nil, "qualities ausserhalb entfernt")
eq(c.filter.qualities.x, nil, "qualities Textschluessel entfernt")
eq(c.filter.typesOff[401], true, "typesOff bleibt")
eq(c.filter.typesOff[402], nil, "typesOff false entfernt")
eq(c.filter.typesOff.foo, nil, "typesOff Textschluessel entfernt")
eq(c.filter.hideDuplicates, true, "hideDuplicates Text -> Vorgabe")
eq(c.favorites[100], true, "favorites bleibt")
eq(c.favorites[200], nil, "favorites false entfernt")
eq(c.favorites.abc, nil, "favorites Textschluessel entfernt")
eq(c.lastSlot, nil, "sanitize lastSlot 12")
eq(#c.outfits, 2, "nur wohlgeformte Outfits bleiben")
eq(c.outfits[1].name, "Gut", "Outfit 1")
eq(c.outfits[1].slots[0], 100, "Outfit Slot 0")
eq(c.outfits[1].slots[1], nil, "Outfit Slot 1 (nicht transmogbar) entfernt")
eq(c.outfits[1].slots[4], 999999, "Outfit HIDDEN bleibt")
eq(c.outfits[1].slots[15], nil, "Outfit Text-Id entfernt")
eq(c.outfits[2].name, "OhneZeit", "Outfit 2")
eq(c.outfits[2].time, 0, "Outfit time Vorgabe")
eq(c.migrated, 2, "migrated nach Init")

-- Seit 2.1: false ohne Marke (Datei aus 2.0) wird einmalig true; false MIT Marke ist die Wahl des Spielers
TransmogGlobalDB = { version = 2, allowAnywhere = false }
local g3 = DB.Init()
eq(g3.allowAnywhere, true, "Datei aus 2.0: allowAnywhere einmalig an")
eq(g3.noNpcDefault, true, "Datei aus 2.0: Marke gesetzt")
DB.Set("allowAnywhere", false)
DB.Init()
eq(g3.allowAnywhere, false, "Wahl 'aus' bleibt nach erneutem Init")
TransmogGlobalDB = { version = 2, allowAnywhere = "ja", noNpcDefault = true }
g3 = DB.Init()
eq(g3.allowAnywhere, true, "Text mit Marke -> Vorgabe an")
TransmogGlobalDB = "kaputt"
g3 = DB.Init()
eq(g3.allowAnywhere, true, "kein Table -> Neuinstallation: an")

-- Migration
TransmogGlobalDB, TransmogDB = nil, nil
transmogOutfits = {
   ["Tank"] = { [1] = 111, [3] = 222, [5] = 999999, [6] = 0, [2] = 55, [20] = 66, [19] = 333 },
   ["Raid Look"] = { [16] = 4444, [17] = 5555 },
   ["   "] = { [1] = 1 },
   ["Leer"] = {},
   ["Kaputt"] = "nein",
   [42] = { [1] = 7 },
   [string.rep("x", 40)] = { [1] = 9 },
}
transmogSettings = {
   hideDuplicates = false,
   armorTypes = { [5] = true, [6] = false, [8] = true },   -- 7 fehlt -> an
}
chat = {}
g, c = DB.Init()
eq(c.migrated, 2, "migrated = 2")
local byName = {}
for _, o in ipairs(c.outfits) do byName[o.name] = o end
eq(#c.outfits, 4, "4 Outfits uebernommen (Tank, Raid Look, Leer, langer Name)")
check(byName["Tank"] ~= nil, "Outfit Tank vorhanden")
eq(byName["Tank"].slots[0], 111, "clientSlot 1 -> server 0")
eq(byName["Tank"].slots[2], 222, "clientSlot 3 -> server 2")
eq(byName["Tank"].slots[4], 999999, "HIDDEN bleibt")
eq(byName["Tank"].slots[5], nil, "Eintrag 0 ignoriert")
eq(byName["Tank"].slots[1], nil, "clientSlot 2 (Hals) nicht transmogbar -> verworfen")
eq(byName["Tank"].slots[18], 333, "clientSlot 19 -> server 18 (Wappenrock)")
eq(Util.Count(byName["Tank"].slots), 4, "Tank hat 4 gueltige Slots")
eq(byName["Raid Look"].slots[15], 4444, "clientSlot 16 -> server 15")
eq(byName["Raid Look"].slots[16], 5555, "clientSlot 17 -> server 16")
check(byName["Leer"] ~= nil and Util.Count(byName["Leer"].slots) == 0, "leeres Outfit bleibt erhalten")
check(byName[string.rep("x", 32)] ~= nil, "langer Name auf 32 Bytes gekuerzt")
eq(byName[string.rep("x", 32)].slots[0], 9, "gekuerzter Name behaelt Slots")
eq(byName["Tank"].time, 1700000000, "Outfit time gesetzt")
eq(byName["   "], nil, "leerer Name verworfen")
eq(c.filter.hideDuplicates, false, "hideDuplicates uebernommen")
eq(c.filter.typesOff[401], nil, "Stoff an -> nicht ausgeblendet")
eq(c.filter.typesOff[402], true, "Leder aus -> 402 ausgeblendet")
eq(c.filter.typesOff[403], nil, "Kette fehlt -> an")
eq(c.filter.typesOff[404], nil, "Platte an")
eq(Util.Count(transmogOutfits), 7, "Altvariable transmogOutfits unberuehrt")
eq(transmogSettings.hideDuplicates, false, "Altvariable transmogSettings unberuehrt")
eq(Util.TimerCount(), 1, "Meldung ueber Migration angesetzt")
Tick(4.1)
eq(chat[#chat], "|cff33a0ea[Transmog]|r Imported outfits from the previous Transmog version: 4", "Migrationsmeldung")

-- nicht noch einmal
table.remove(c.outfits, 1)
local before = #c.outfits
g, c = DB.Init()
eq(#c.outfits, before, "Migration laeuft nur einmal")
eq(Util.TimerCount(), 0, "keine zweite Meldung")

-- ohne armorTypes: keine Typen ausblenden; Namenskollision wird aufgeloest
TransmogGlobalDB, TransmogDB = nil, nil
transmogOutfits = { ["A"] = { [1] = 10 } }
transmogSettings = { hideDuplicates = true }
TransmogDB = { outfits = { { name = "A", slots = { [0] = 1 }, time = 1 } }, migrated = 1 }
g, c = DB.Init()
eq(#c.outfits, 2, "Kollision: beide Outfits vorhanden")
eq(c.outfits[1].name, "A", "vorhandenes Outfit unveraendert")
eq(c.outfits[2].name, "A (2)", "neues Outfit mit Suffix")
eq(c.outfits[1].slots[0], 1, "vorhandenes Outfit behaelt Slots")
eq(Util.Count(c.filter.typesOff), 0, "ohne armorTypes nichts ausgeblendet")
eq(c.filter.hideDuplicates, true, "hideDuplicates true uebernommen")
Tick(5)

-- Kuerzung in ZEICHEN (wie Outfits.MAX_NAME), nie mitten im Zeichen
TransmogGlobalDB, TransmogDB = nil, nil
transmogOutfits = {
   [string.rep("x", 31) .. "\195\164\195\164"] = { [1] = 10 },     -- 33 Zeichen
   [string.rep("\195\164", 40)] = { [1] = 11 },                      -- 40 Umlaute (80 Bytes)
   ["Bunt"] = { [1] = 1 },
   ["|cffff0000Rot|r  und   blau"] = { [1] = 2 },
   ["bunt"] = { [1] = 3 },                                           -- Kollision ohne Gross/Klein
   ["BUNT"] = { [1] = 4 },
}
transmogSettings = nil
g, c = DB.Init()
local byN = {}
for _, o in ipairs(c.outfits) do byN[o.name] = o end
check(byN[string.rep("x", 31) .. "\195\164"] ~= nil, "UTF-8-Kuerzung auf 32 Zeichen am Zeichenrand")
check(byN[string.rep("\195\164", 32)] ~= nil, "40 Umlaute -> 32 Zeichen (nicht 16)")
check(byN["Rot und blau"] ~= nil, "Farbcodes entfernt, Leerraum zusammengefasst")
eq(#c.outfits, 6, "alle sechs Outfits uebernommen")
-- Sortierung nach Rohname (Bytes): "BUNT" < "Bunt" < "bunt"
check(byN["BUNT"] ~= nil and byN["BUNT"].slots[0] == 4, "BUNT/Bunt/bunt: erstes behaelt seinen Namen")
check(byN["Bunt (2)"] ~= nil and byN["Bunt (2)"].slots[0] == 1, "Bunt kollidiert -> Bunt (2)")
check(byN["bunt (3)"] ~= nil and byN["bunt (3)"].slots[0] == 3, "bunt kollidiert -> bunt (3)")
check(byN["Bunt"] == nil and byN["bunt"] == nil, "keine zwei Namen, die sich nur in Gross-/Kleinschreibung unterscheiden")
local suffixed = 0
for name in pairs(byN) do
   if name:match("^[Bb][Uu][Nn][Tt] %(%d%)$") then suffixed = suffixed + 1 end
end
eq(suffixed, 2, "beide Kollisionen mit Suffix")
Tick(5)

-- Kollision am Namensende: Suffix passt noch in 32 Zeichen
TransmogGlobalDB, TransmogDB = nil, nil
transmogOutfits = {
   [string.rep("y", 40)] = { [1] = 1 },
   [string.rep("y", 33)] = { [1] = 2 },
}
g, c = DB.Init()
local maxLen = 0
local names = {}
for _, o in ipairs(c.outfits) do
   names[o.name] = true
   if #o.name > maxLen then maxLen = #o.name end
end
eq(#c.outfits, 2, "zwei lange Namen -> zwei Outfits")
check(names[string.rep("y", 32)], "erster auf 32 gekuerzt")
check(names[string.rep("y", 28) .. " (2)"], "zweiter: gekuerzt + Suffix, gesamt 32")
eq(maxLen, 32, "kein Name laenger als 32")
Tick(5)

-- ohne Alt-Variablen und ohne Events/Util (Rueckfall)
TransmogGlobalDB, TransmogDB = nil, nil
transmogOutfits, transmogSettings = nil, nil
g, c = DB.Init()
eq(c.migrated, 2, "Init ohne Altdaten")
eq(#c.outfits, 0, "keine Outfits ohne Altdaten")

-- ---------------------------------------------------------------------------
print("== Robustheit (Zusatz)")

-- Util ohne T.HEX / T.L benutzbar
do
   local hex, lt = T.HEX, T.L
   T.HEX, T.L = nil, nil
   chat = {}
   local ok1 = pcall(Util.Error, "x %d", 1)
   T.debug = true
   local ok2 = pcall(Util.Debug, "y")
   T.debug = false
   local ok3, num = pcall(Util.FormatNumber, 1234567)
   T.HEX, T.L = hex, lt
   check(ok1 and ok2, "Error/Debug ohne T.HEX")
   check(chat[1] and chat[1]:find("x 1", 1, true), "Error ohne T.HEX schreibt trotzdem")
   check(ok3 and num == "1,234,567", "FormatNumber ohne T.L")
end

-- Debounce: Re-Arm wechselt den Treiber nicht zwischen Hide und Show
do
   local drv
   for _, f in ipairs(frames) do
      if f.scripts.OnUpdate then drv = f end
   end
   Util.Debounce("churn", 1, function() end)
   local hides = drv.hides or 0
   for _ = 1, 5 do Util.Debounce("churn", 1, function() end) end
   eq(drv.hides or 0, hides, "Debounce re-armt ohne Hide")
   eq(drv.shown, true, "Treiber laeuft nach Re-Arm")
   eq(Util.TimerCount(), 1, "nur ein Debounce-Timer")
   Util.Cancel("churn")
   eq(drv.shown, false, "Cancel des letzten Timers versteckt den Treiber")
end

-- Bus: gleiche Funktion unter zwei Ownern; Off per Owner trifft nur einen
do
   local n = 0
   local function f() n = n + 1 end
   Events.On("T_OWN", f, "o1")
   Events.On("T_OWN", f, "o2")
   Events.Fire("T_OWN")
   eq(n, 2, "gleiche Funktion, zwei Owner = zwei Aufrufe")
   eq(Events.Off("T_OWN", "o1"), 1, "Off(o1)")
   Events.Fire("T_OWN")
   eq(n, 3, "nur o2 uebrig")
   eq(Events.Off("T_OWN", f), 1, "Off per Funktion entfernt den Rest")
   Events.Fire("T_OWN")
   eq(n, 3, "danach kein Aufruf mehr")
end

-- Bus: Fire aus einem Handler heraus (Verschachtelung) und Abmelden im Handler
do
   local order = {}
   Events.On("T_OUTER", function()
      order[#order + 1] = "outer1"
      Events.Fire("T_INNER", "x")
      order[#order + 1] = "outer2"
   end, "n")
   Events.On("T_INNER", function(v) order[#order + 1] = "inner:" .. tostring(v) end, "n")
   Events.Fire("T_OUTER")
   eq(table.concat(order, " "), "outer1 inner:x outer2", "verschachteltes Fire")
   eq(Events.Off("T_OUTER", "n"), 1, "Off T_OUTER")
   eq(Events.Off("T_INNER", "n"), 1, "Off T_INNER")
end

-- Game: Abmelden waehrend des Durchlaufs
do
   local gf
   for _, f in ipairs(frames) do
      if f.scripts.OnEvent then gf = f end
   end
   local seenG = {}
   local gSecond
   local function gFirst()
      seenG[#seenG + 1] = "first"
      Events.UnGame("PLAYER_REGEN_ENABLED", gSecond)
   end
   gSecond = function() seenG[#seenG + 1] = "second" end
   Events.Game("PLAYER_REGEN_ENABLED", gFirst)
   Events.Game("PLAYER_REGEN_ENABLED", gSecond)
   gf.scripts.OnEvent(gf, "PLAYER_REGEN_ENABLED")
   eq(table.concat(seenG, " "), "first", "im Durchlauf abgemeldeter Game-Handler wird uebersprungen")
   Events.UnGame("PLAYER_REGEN_ENABLED", gFirst)
   check(gf.events.PLAYER_REGEN_ENABLED == nil, "Game-Ereignis nach letztem UnGame abgemeldet")
end

-- DB: Positionen ohne Anker, Unsinns-Anker, Masse bleiben unveraendert
do
   DB.Set("toastPoint", { x = 10, y = 20 })
   check(DB.global.toastPoint ~= nil and DB.global.toastPoint.x == 10, "Position nur mit x/y bleibt")
   DB.Set("toastPoint", { "SOMEWHERE", 1, 2, 3 })
   eq(DB.global.toastPoint, nil, "Unsinns-Anker -> nil")
   DB.Set("toastPoint", nil)
   DB.Set("width", 912.5)
   eq(DB.global.width, 912.5, "width wird nicht gerundet")
   DB.Set("width", 1e9)
   eq(DB.global.width, 8192, "width nach oben begrenzt")
   DB.Set("width", 880)
end

-- Locale: __missing ueberlebt Set und wird bei neuem Text bereinigt
do
   local _ = L.RUNTIME_MISSING_KEY
   check(L.__missing.RUNTIME_MISSING_KEY == true, "Fehlschluessel vermerkt")
   Locale.Set("enUS")
   check(L.__missing.RUNTIME_MISSING_KEY == true, "Fehlschluessel ueberlebt Set")
   Locale.Add("enUS", { RUNTIME_MISSING_KEY = "jetzt da" })
   eq(L.RUNTIME_MISSING_KEY, "jetzt da", "nachgereichter Text")
   check(L.__missing.RUNTIME_MISSING_KEY == nil, "aus __missing entfernt")
end

-- Dateien: TOC-Reihenfolge, XML und Bindings
do
   local function slurp(rel)
      local fh = assert(io.open(ROOT .. "/" .. rel, "rb"))
      local text = fh:read("*a")
      fh:close()
      return text
   end
   local toc = slurp("Transmog.toc")
   local order = {}
   for line in toc:gmatch("[^\n]+") do
      if not line:match("^##") then order[#order + 1] = line end
   end
   local expectedOrder = {
      "Locales\\Locale.lua", "Locales\\enUS_Core.lua", "Locales\\enUS_State.lua",
      "Locales\\enUS_Filter.lua", "Locales\\enUS_Window.lua", "Locales\\enUS_Preview.lua",
      "Locales\\enUS_SlotBar.lua", "Locales\\enUS_Grid.lua", "Locales\\enUS_FilterBar.lua",
      "Locales\\enUS_Outfits.lua", "Locales\\enUS_Options.lua", "Locales\\enUS_Features.lua",
      "Locales\\enUS_Boot.lua", "Locales\\deDE.lua", "Locales\\frFR.lua",
      "Locales\\esES.lua", "Locales\\ruRU.lua", "Locales\\koKR.lua", "Locales\\zhCN.lua",
      "Locales\\zhTW.lua", "Core\\Init.lua", "Core\\Util.lua", "Core\\Events.lua",
      "Core\\DB.lua", "Core\\Slots.lua", "Core\\Items.lua", "Core\\Net.lua",
      "Core\\State.lua", "Core\\Filter.lua", "Core\\Outfits.lua", "UI\\Skin.lua",
      "UI\\Cameras.lua", "UI\\Preview.lua", "UI\\SlotBar.lua", "UI\\Grid.lua",
      "UI\\FilterBar.lua", "UI\\OutfitsTab.lua", "UI\\Options.lua", "UI\\Window.lua",
      "Features\\Tooltips.lua", "Features\\Toasts.lua", "Core\\Boot.lua", "Transmog.xml",
      "Bindings.xml",
   }
   eq(#order, #expectedOrder, "TOC: Anzahl der Dateien")
   for i = 1, #expectedOrder do
      if order[i] ~= expectedOrder[i] then
         check(false, "TOC Zeile " .. i .. ": erwartet " .. expectedOrder[i] .. ", ist " .. tostring(order[i]))
         break
      end
   end
   check(toc:find("## Interface: 30300", 1, true), "TOC Interface 30300")
   check(toc:find("## SavedVariables: TransmogGlobalDB", 1, true), "TOC SavedVariables")
   check(toc:find("## SavedVariablesPerCharacter: TransmogDB, transmogOutfits, transmogSettings", 1, true),
      "TOC SavedVariablesPerCharacter")
   check(not toc:find("\r", 1, true), "TOC ohne CR")

   local xml = slurp("Transmog.xml")
   check(xml:find('name="TransmogCellModelTemplate" virtual="true" scale="4.0"', 1, true), "XML Zellenmodell")
   check(xml:find('name="TransmogPreviewModelTemplate" virtual="true" scale="2.0" enableMouse="true"', 1, true),
      "XML Vorschaumodell")
   check(xml:find('<AbsDimension x="80" y="107"/>', 1, true), "XML Zellengroesse")
   check(xml:find('<AbsDimension x="221" y="362"/>', 1, true), "XML Vorschaugroesse")
   -- in einem XML-Kommentar darf kein doppelter Bindestrich stehen
   local badComment = false
   for body in xml:gmatch("<!%-%-(.-)%-%->") do
      if body:find("--", 1, true) then badComment = true end
   end
   check(not badComment, "XML-Kommentare ohne doppelten Bindestrich")
   local badComment2 = false
   for body in slurp("Bindings.xml"):gmatch("<!%-%-(.-)%-%->") do
      if body:find("--", 1, true) then badComment2 = true end
   end
   check(not badComment2, "Bindings-Kommentare ohne doppelten Bindestrich")

   local bind = slurp("Bindings.xml")
   check(bind:find('name="TRANSMOG_TOGGLE"', 1, true), "Binding Name")
   check(bind:find('header="TRANSMOG"', 1, true), "Binding Header")
   check(bind:find('runOnUp="false"', 1, true), "Binding runOnUp")
   check(bind:find("Transmog.UI.Window.Toggle()", 1, true), "Binding Body")
end

-- ---------------------------------------------------------------------------
print("== Globale Namen")
local allowed = {
   Transmog = true, TransmogDB = true, TransmogGlobalDB = true,
   transmogOutfits = true, transmogSettings = true,
}
local leaked = {}
for k in pairs(_G) do
   if not globalsBefore[k] and not allowed[k] then leaked[#leaked + 1] = tostring(k) end
end
table.sort(leaked)
eq(table.concat(leaked, ","), "", "keine unerwarteten Globals")

-- ---------------------------------------------------------------------------
print(string.format("\n%d bestanden, %d fehlgeschlagen", passed, failed))
if failed > 0 then os.exit(1) end
