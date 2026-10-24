-- tests/mock_wow.lua
-- ---------------------------------------------------------------------------
-- Strenge Attrappe der WoW-3.3.5a-Umgebung (Lua 5.1, Interface 30300) fuer
-- widget-lastige Addons. Aufruf ueber den Runner (im Hauptverzeichnis):
--
--     luajit tests/run.lua [filter]
--
-- Was sie leistet
--   * Frames, Buttons, EditBoxes, Slider, ScrollFrames, Modelle, Tooltips ...
--     als echte Objekte mit Eltern/Kindern, Ankern, Groessen, Skripten,
--     Ereignissen, Sichtbarkeit und Zustand.
--   * STRENGES API: jede Methode, die es in 3.3.5a nicht (sicher) gibt
--     (SetSize, SetShown, SetColorTexture, SetWordWrap, GetRect ...), wirft
--     "API not in 3.3.5a: <Typ>:<Methode>". Unbekannte Frame-Typen, Templates,
--     Schriftobjekte, Doppelnamen, fehlende Schrift ("Font not set") usw.
--     werfen ebenfalls Fehler, wie der Client.
--   * Zeit (GetTime/M.Advance/OnUpdate), Ereignisse (M.Fire), Addon-Nachrichten
--     (SendAddonMessage/CHAT_MSG_ADDON), Item-Cache mit Abfrageverzoegerung,
--     Gossip-Fenster mit synchronem GOSSIP_CLOSED, Auktionshaus-Klassenlisten.
--   * Fehler in Skript-Handlern gehen (wie im Spiel) an den Fehler-Handler und
--     landen in M.errors; der Runner laesst solche Tests durchfallen.
--   * Der Addon-Code laeuft in einer Umgebung OHNE io/os/debug/package/require
--     (die gibt es in WoW nicht); gelesene undefinierte Globals und neu
--     angelegte Globals werden mitgeschrieben (M.globalMisses/M.globalWrites).
--
-- Was sie NICHT leistet
--   * Sie rendert nichts. Ob etwas gut aussieht, zeigt nur das Spiel.
--   * Anker-Aufloesung ist vereinfacht (siehe U.rect): GetLeft/GetTop usw.
--     liefern nur etwas, wenn die Anker eindeutig aufloesbar sind.
--
-- Rueckgabewerte wie in 3.3.5a: IsShown/IsVisible/IsEnabled/GetChecked/HasFocus
-- usw. liefern 1 oder nil (nicht true/false) -> in Tests H.truthy/H.falsy.
--
-- ===========================================================================
-- API fuer Tests (Modul liefert die Tabelle M)
-- ===========================================================================
-- Zuruecksetzen / Laden
--   M.Install(opts)             alles zuruecksetzen; opts.world (wird in die Standardwelt gemischt),
--                               opts.items, opts.globals (z.B. SavedVariables)
--   M.LoadToc(dir, "X.toc", o)  TOC laden; o.upTo, o.skip{[datei]=true}, o.skipMissing; .xml nur fuer
--                               virtuelle Templates (+ <Script>/<Include>); Bindings.xml -> M.bindings
--   M.LoadFiles(liste, o)       Lua-Dateien (relativ zum Addon-Verzeichnis M.root) laden
--   Jeder Chunk bekommt ("Transmog", gemeinsame Tabelle); Syntaxfehler/goto/BOM nennen die Datei.
-- Zeit und Ereignisse
--   M.now, GetTime()            Spielzeit in Sekunden; nie rueckwaerts (GetTime wirft sonst)
--   M.Advance(dt [, step])      Zeit in Schritten (0.05) vorstellen, OnUpdate sichtbarer Frames rufen
--   M.AdvanceUntil(fn [, max, step])   bis fn() wahr wird; Rueckgabe Sekunden oder nil
--   M.Fire(event, ...)          Ereignis an alle registrierten Frames (Registrierungsreihenfolge)
--   M.ServerMessage(payload)    CHAT_MSG_ADDON("transmog", payload, "WHISPER", Spielername)
--   M.sentAddon                 { {prefix=, msg=, channel=, target=} ... } von SendAddonMessage
--   M.SentCommands()            msg-Liste fuer Praefix "transmog";  M.CountSent(praefix)
--   M.ClearSent()               gesendete Nachrichten leeren
--   M.errors / M.errorTraces    Fehler, die beim Fehler-Handler ankamen (Skript-Handler-Fehler!)
--   M.TakeErrors() / M.ClearErrors()
--   M.warnings                  Warnungen der Attrappe (z.B. SetHyperlink ohne SetOwner)
--   M.messages                  Chatzeilen (DEFAULT_CHAT_FRAME:AddMessage, print des Addons)
--   M.sounds, M.chatInserts, M.dressUps, M.sentChat, M.popup/M.popups, M.reloads
-- Eingabe
--   M.Click(frame, button, mods)  Maus runter/hoch (mods = {shift=,ctrl=,alt=}); Standard LeftButton
--   M.MouseDown/M.MouseUp       einzeln (Disable() dazwischen verwirft den Klick)
--   M.Enter(frame)/M.Leave(frame)  OnEnter/OnLeave (Hover-Modell fuer IsMouseOver/GetMouseFocus)
--   M.Wheel(frame, delta)       OnMouseWheel;  M.Type(editBox, text)  OnTextChanged(self, true)
--   M.Key(frame, "ENTER"|"ESCAPE"|"TAB"|"SPACE")   M.Escape()  ESC im Spiel (EditBox, UISpecialFrames)
--   M.Drag(frame, dx, dy [, button])  Ziehen; wirkt auf das Objekt, das StartMoving/StartSizing rief
--   M.Slash("/befehl args")     SlashCmdList ausfuehren;  M.RunBinding("NAME")
--   M.GossipShow()              GOSSIP_SHOW (world.gossipOpen = true);  M.OpenNpc() = "Open" + GossipShow
--   M.PopupAccept([text]) / M.PopupCancel()   StaticPopup bestaetigen/abbrechen
-- Items
--   M.items[id] = {name=, quality=, ilvl=, minLevel=, class=, subclass=, equipLoc=, icon=, price=, maxStack=}
--   M.CacheItem(id) / M.CacheAll() / M.UncacheItem(id) / M.IsCached(id)
--   M.itemQueries[id]           Anzahl SetHyperlink("item:id") (nur mit Tooltip-Besitzer)
--   M.world.itemCacheDelay      Sekunden bis "gecacht" (0.3)
-- Abfragen
--   M.FindFrame(name), M.Walk(root, fn), M.Find(root, typ), M.Texts(root [, includeHidden]),
--   M.HasText(root, text), M.Dump(root [, tiefe]), M.Model(frame) (.calls/.names()/.log()/.tried ...)
--   M.StrayGlobals(), M.StrayFrameNames(), M.GlobalMisses(), M.globalWrites, M.missingAssets
-- Welt (M.world; Zuweisung M.world = {...} mischt in die Standardwerte)
--   locale playerName realmName race class faction level sex money screenWidth screenHeight uiScale
--   cursor={x,y} shift ctrl alt equipment[clientSlot]=itemId bags[bag][slot]=itemId itemCounts
--   gossipOpen globalStrings hasUndressSlot hasRegisterAddonMessagePrefix auctionLists units cvars
--   modifiedClick combat dead chatOpen strictApi
--   (Aliase: shiftDown ctrlDown altDown screenW screenH screen={w,h} cursorX cursorY playerRace ...)
-- Erweiterung der Attrappe (bewusst): M.methods.Frame.SetSize = fn; M.AllowField("Name")
-- ---------------------------------------------------------------------------

local M = {}

-- Momentaufnahme der Globals beim Laden: M.Install entfernt spaeter alles,
-- was nicht darin steht (Globals des Addons und der Attrappe selbst).
local BASE = {}
for k in pairs(_G) do BASE[k] = true end

local realOs, realIo, realDebug, realPrint = os, io, debug, print
local type, pairs, ipairs, select, tostring, tonumber = type, pairs, ipairs, select, tostring, tonumber
local error, pcall, xpcall, next = error, pcall, xpcall, next
local setmetatable, getmetatable, rawget, rawset, rawequal = setmetatable, getmetatable, rawget, rawset, rawequal
local unpack = unpack
local sfmt, ssub, sfind, sgsub, smatch, sbyte, schar = string.format, string.sub, string.find, string.gsub, string.match, string.byte, string.char
local slower, supper, srep, slen = string.lower, string.upper, string.rep, string.len
local tinsert, tremove, tsort, tconcat = table.insert, table.remove, table.sort, table.concat
local floor, ceil, max, min, huge = math.floor, math.ceil, math.max, math.min, math.huge

-- Verzeichnis des Addons (Elternverzeichnis von tests/)
local function detectRoot()
   local src = realDebug.getinfo(1, "S").source or ""
   src = sgsub(src, "^@", "")
   local dir = smatch(src, "^(.*)[/\\]tests[/\\]mock_wow%.lua$")
   if dir and dir ~= "" then return dir end
   return "."
end
M.root = detectRoot()

local S = {}   -- interner Zustand (wird von resetState neu aufgebaut)
local U = {}   -- interne Hilfsfunktionen
local G = {}   -- globale WoW-Funktionen (werden von Install nach _G kopiert)

-- M.world ist eine Eigenschaft (S.world): "M.world = { locale = 'deDE' }" verwirft nicht die
-- Standardwerte, sondern setzt die Welt auf die Standardwerte zurueck und mischt die Angaben
-- darueber. Der Zuweisungs-Handler wird weiter unten (nach newWorld/U.merge) eingehaengt.
setmetatable(M, {
   __index = function(_, k)
      if k == "world" then return S.world end
      return nil
   end,
})

-- ---------------------------------------------------------------------------
-- Daten: Rassen, Klassen, Globalstrings, Auktionslisten
-- ---------------------------------------------------------------------------

local RACE_NAMES = {
   enUS = { Human = "Human", Orc = "Orc", Dwarf = "Dwarf", NightElf = "Night Elf", Scourge = "Undead",
            Tauren = "Tauren", Gnome = "Gnome", Troll = "Troll", BloodElf = "Blood Elf", Draenei = "Draenei" },
   deDE = { Human = "Mensch", Orc = "Orc", Dwarf = "Zwerg", NightElf = "Nachtelf", Scourge = "Untoter",
            Tauren = "Taure", Gnome = "Gnom", Troll = "Troll", BloodElf = "Blutelf", Draenei = "Draenei" },
}
local CLASS_NAMES = {
   enUS = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
            DEATHKNIGHT = "Death Knight", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" },
   deDE = { WARRIOR = "Krieger", PALADIN = "Paladin", HUNTER = "J\195\164ger", ROGUE = "Schurke",
            PRIEST = "Priester", DEATHKNIGHT = "Todesritter", SHAMAN = "Schamane", MAGE = "Magier",
            WARLOCK = "Hexenmeister", DRUID = "Druide" },
}
local ALLIANCE_RACES = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true }
local FACTION_NAMES = {
   enUS = { Alliance = "Alliance", Horde = "Horde" },
   deDE = { Alliance = "Allianz", Horde = "Horde" },
}

local GLOBALSTRINGS = {
   enUS = {
      HEADSLOT = "Head", SHOULDERSLOT = "Shoulders", BACKSLOT = "Back", CHESTSLOT = "Chest",
      SHIRTSLOT = "Shirt", TABARDSLOT = "Tabard", WRISTSLOT = "Wrist", HANDSSLOT = "Hands",
      WAISTSLOT = "Waist", LEGSSLOT = "Legs", FEETSLOT = "Feet", MAINHANDSLOT = "Main Hand",
      SECONDARYHANDSLOT = "Off Hand", RANGEDSLOT = "Ranged", NECKSLOT = "Neck",
      FINGER0SLOT = "Finger", FINGER1SLOT = "Finger", TRINKET0SLOT = "Trinket", TRINKET1SLOT = "Trinket",
      ACCEPT = "Accept", CANCEL = "Cancel", OKAY = "Okay", CLOSE = "Close", YES = "Yes", NO = "No",
      SAVE = "Save", RESET = "Reset", APPLY = "Apply", SEARCH = "Search", DELETE = "Delete",
      NAME = "Name", QUALITY = "Quality", ARMOR = "Armor", WEAPON = "Weapon", ENABLE = "Enable",
      DISABLE = "Disable", DEFAULT = "Default", NONE = "None", UNKNOWN = "Unknown", DECLINE = "Decline",
      LEVEL = "Level", FILTER = "Filter", SORT_BY = "Sort by",
      ITEM_QUALITY0_DESC = "Poor", ITEM_QUALITY1_DESC = "Common", ITEM_QUALITY2_DESC = "Uncommon",
      ITEM_QUALITY3_DESC = "Rare", ITEM_QUALITY4_DESC = "Epic", ITEM_QUALITY5_DESC = "Legendary",
      ITEM_QUALITY6_DESC = "Artifact", ITEM_QUALITY7_DESC = "Heirloom",
      INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back",
      INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_BODY = "Shirt", INVTYPE_TABARD = "Tabard",
      INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs",
      INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket",
      INVTYPE_WEAPON = "One-Hand", INVTYPE_2HWEAPON = "Two-Hand", INVTYPE_WEAPONMAINHAND = "Main Hand",
      INVTYPE_WEAPONOFFHAND = "Off Hand", INVTYPE_SHIELD = "Off Hand", INVTYPE_HOLDABLE = "Held In Off-hand",
      INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged", INVTYPE_THROWN = "Thrown",
      INVTYPE_RELIC = "Relic", INVTYPE_AMMO = "Ammo", INVTYPE_BAG = "Bag", INVTYPE_QUIVER = "Quiver",
   },
   deDE = {
      HEADSLOT = "Kopf", SHOULDERSLOT = "Schultern", BACKSLOT = "R\195\188cken", CHESTSLOT = "Brust",
      SHIRTSLOT = "Hemd", TABARDSLOT = "Wappenrock", WRISTSLOT = "Handgelenke", HANDSSLOT = "H\195\164nde",
      WAISTSLOT = "Taille", LEGSSLOT = "Beine", FEETSLOT = "F\195\188\195\159e", MAINHANDSLOT = "Waffenhand",
      SECONDARYHANDSLOT = "Schildhand", RANGEDSLOT = "Distanz", NECKSLOT = "Hals",
      FINGER0SLOT = "Finger", FINGER1SLOT = "Finger", TRINKET0SLOT = "Schmuck", TRINKET1SLOT = "Schmuck",
      ACCEPT = "Annehmen", CANCEL = "Abbrechen", OKAY = "Okay", CLOSE = "Schlie\195\159en", YES = "Ja", NO = "Nein",
      SAVE = "Speichern", RESET = "Zur\195\188cksetzen", APPLY = "Anwenden", SEARCH = "Suche", DELETE = "L\195\182schen",
      NAME = "Name", QUALITY = "Qualit\195\164t", ARMOR = "R\195\188stung", WEAPON = "Waffe", ENABLE = "Aktivieren",
      DISABLE = "Deaktivieren", DEFAULT = "Standard", NONE = "Keine", UNKNOWN = "Unbekannt", DECLINE = "Ablehnen",
      LEVEL = "Stufe", FILTER = "Filter", SORT_BY = "Sortieren nach",
      ITEM_QUALITY0_DESC = "Schlecht", ITEM_QUALITY1_DESC = "Verbreitet", ITEM_QUALITY2_DESC = "Ungew\195\182hnlich",
      ITEM_QUALITY3_DESC = "Selten", ITEM_QUALITY4_DESC = "Episch", ITEM_QUALITY5_DESC = "Legend\195\164r",
      ITEM_QUALITY6_DESC = "Artefakt", ITEM_QUALITY7_DESC = "Erbst\195\188ck",
      INVTYPE_HEAD = "Kopf", INVTYPE_NECK = "Hals", INVTYPE_SHOULDER = "Schultern", INVTYPE_CLOAK = "R\195\188cken",
      INVTYPE_CHEST = "Brust", INVTYPE_ROBE = "Brust", INVTYPE_BODY = "Hemd", INVTYPE_TABARD = "Wappenrock",
      INVTYPE_WRIST = "Handgelenke", INVTYPE_HAND = "H\195\164nde", INVTYPE_WAIST = "Taille", INVTYPE_LEGS = "Beine",
      INVTYPE_FEET = "F\195\188\195\159e", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Schmuck",
      INVTYPE_WEAPON = "Einh\195\164ndig", INVTYPE_2HWEAPON = "Zweih\195\164ndig", INVTYPE_WEAPONMAINHAND = "Waffenhand",
      INVTYPE_WEAPONOFFHAND = "Schildhand", INVTYPE_SHIELD = "Schildhand",
      INVTYPE_HOLDABLE = "In Schildhand gef\195\188hrt", INVTYPE_RANGED = "Distanz", INVTYPE_RANGEDRIGHT = "Distanz",
      INVTYPE_THROWN = "Wurfwaffe", INVTYPE_RELIC = "Relikt", INVTYPE_AMMO = "Munition", INVTYPE_BAG = "Tasche",
      INVTYPE_QUIVER = "K\195\182cher",
   },
}

-- Echte 3.3.5a-enUS-Listen des Auktionshauses (Reihenfolge ist fest)
local AUCTION_EN = {
   classes = { "Weapon", "Armor", "Container", "Consumable", "Trade Goods", "Projectile", "Quiver",
               "Recipe", "Gem", "Miscellaneous", "Quest" },
   subclasses = {
      [1] = { "One-Handed Axes", "Two-Handed Axes", "Bows", "Guns", "One-Handed Maces", "Two-Handed Maces",
              "Polearms", "One-Handed Swords", "Two-Handed Swords", "Staves", "Fist Weapons", "Miscellaneous",
              "Daggers", "Thrown", "Crossbows", "Wands", "Fishing Poles" },
      [2] = { "Miscellaneous", "Cloth", "Leather", "Mail", "Plate", "Shields", "Librams", "Idols", "Totems",
              "Sigils" },
      [3] = { "Bag", "Soul Bag", "Herb Bag", "Enchanting Bag", "Engineering Bag", "Gem Bag", "Mining Bag",
              "Leatherworking Bag", "Inscription Bag" },
      [4] = { "Food & Drink", "Potion", "Elixir", "Flask", "Bandage", "Item Enhancement", "Scroll",
              "Other" },
      [5] = { "Elemental", "Cloth", "Leather", "Metal & Stone", "Meat", "Herb", "Enchanting", "Jewelcrafting",
              "Parts", "Devices", "Explosives", "Materials", "Other" },
      [6] = { "Arrow", "Bullet" },
      [7] = { "Quiver", "Ammo Pouch" },
      [8] = { "Book", "Leatherworking", "Tailoring", "Engineering", "Blacksmithing", "Cooking", "Alchemy",
              "First Aid", "Enchanting", "Fishing", "Jewelcrafting", "Inscription" },
      [9] = { "Red", "Blue", "Yellow", "Purple", "Green", "Orange", "Meta", "Simple", "Prismatic" },
      [10] = { "Junk", "Reagent", "Pet", "Holiday", "Other", "Mount" },
      [11] = {},
   },
}
-- Beispielliste fuer deDE (Tests duerfen eigene Listen in M.world.auctionLists setzen)
local AUCTION_DE = {
   classes = { "Waffe", "R\195\188stung", "Beh\195\164lter", "Verbrauchbar", "Handwerkswaren", "Projektil",
               "K\195\182cher", "Rezepte", "Edelsteine", "Verschiedenes", "Quest" },
   subclasses = {
      [1] = { "Einhand\195\164xte", "Zweihand\195\164xte", "B\195\182gen", "Schusswaffen", "Einhandstreitkolben",
              "Zweihandstreitkolben", "Stangenwaffen", "Einhandschwerter", "Zweihandschwerter", "St\195\164be",
              "Faustwaffen", "Verschiedenes", "Dolche", "Wurfwaffen", "Armbr\195\188ste", "Zauberst\195\164be",
              "Angelruten" },
      [2] = { "Verschiedenes", "Stoff", "Leder", "Kette", "Platte", "Schilde", "Buchb\195\164nde", "G\195\182tzen",
              "Totems", "Siegel" },
   },
}
M.AUCTION_EN = AUCTION_EN
M.AUCTION_DE = AUCTION_DE

-- Slot-Namen von GetInventorySlotInfo: Name -> { id, Textur }
local INV_SLOTS = {
   AmmoSlot = { 0, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ammo" },
   HeadSlot = { 1, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head" },
   NeckSlot = { 2, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck" },
   ShoulderSlot = { 3, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder" },
   ShirtSlot = { 4, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shirt" },
   ChestSlot = { 5, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" },
   WaistSlot = { 6, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist" },
   LegsSlot = { 7, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs" },
   FeetSlot = { 8, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet" },
   WristSlot = { 9, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists" },
   HandsSlot = { 10, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands" },
   Finger0Slot = { 11, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger" },
   Finger1Slot = { 12, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger" },
   Trinket0Slot = { 13, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket" },
   Trinket1Slot = { 14, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket" },
   BackSlot = { 15, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest" },
   MainHandSlot = { 16, "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand" },
   SecondaryHandSlot = { 17, "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand" },
   RangedSlot = { 18, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Ranged" },
   TabardSlot = { 19, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Tabard" },
   Bag0Slot = { 20, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag" },
   Bag1Slot = { 21, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag" },
   Bag2Slot = { 22, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag" },
   Bag3Slot = { 23, "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag" },
}

-- Qualitaetsfarben (ITEM_QUALITY_COLORS / GetItemQualityColor)
local QUALITY_RGB = {
   [0] = { 0.616, 0.616, 0.616 }, [1] = { 1, 1, 1 }, [2] = { 0.118, 1, 0 }, [3] = { 0, 0.439, 0.867 },
   [4] = { 0.639, 0.208, 0.933 }, [5] = { 1, 0.502, 0 }, [6] = { 0.898, 0.8, 0.502 },
   [7] = { 0.898, 0.8, 0.502 },
}
local QUALITY_HEX = {
   [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000",
   [6] = "e5cc80", [7] = "e5cc80",
}

-- Standardschriften je Client-Sprache (STANDARD_TEXT_FONT)
local LOCALE_FONT = {
   ruRU = "Fonts\\FRIZQT___CYR.TTF", koKR = "Fonts\\2002.TTF", zhCN = "Fonts\\ARKai_T.ttf",
   zhTW = "Fonts\\bLEI00D.ttf",
}
local LATIN_ONLY_FONTS = {
   ["fonts\\frizqt__.ttf"] = true, ["fonts\\arialn.ttf"] = true, ["fonts\\morpheus.ttf"] = true,
   ["fonts\\skurri.ttf"] = true,
}
local NON_LATIN_LOCALES = { ruRU = true, koKR = true, zhCN = true, zhTW = true }

-- Ereignisse, die es in 3.3.5a nicht gibt (Retail/spaeter) -> RegisterEvent wirft
local FOREIGN_EVENTS = {
   GET_ITEM_INFO_RECEIVED = true, ITEM_DATA_LOAD_RESULT = true, TRANSMOG_COLLECTION_UPDATED = true,
   TRANSMOG_COLLECTION_ITEM_UPDATE = true, TRANSMOGRIFY_UPDATE = true, TRANSMOGRIFY_OPEN = true,
   TRANSMOGRIFY_CLOSE = true, TRANSMOGRIFY_SUCCESS = true, UNIT_POWER_UPDATE = true,
   PLAYER_SPECIALIZATION_CHANGED = true, NEW_TOY_ADDED = true,
}

-- ---------------------------------------------------------------------------
-- Welt (vom Test konfigurierbar)
-- ---------------------------------------------------------------------------

-- Alternative Schluesselnamen fuer M.world (Lesen und Schreiben werden auf den Hauptnamen umgeleitet),
-- damit Tests, die den Namen anders raten, trotzdem wirken.
local WORLD_ALIASES = {
   screenW = "screenWidth", screenH = "screenHeight",
   shiftDown = "shift", ctrlDown = "ctrl", altDown = "alt",
   isShiftDown = "shift", isControlDown = "ctrl", isAltDown = "alt",
   name = "playerName", characterName = "playerName",
   playerRace = "race", raceToken = "race", playerClass = "class", classToken = "class",
   playerLevel = "level", playerFaction = "faction", playerMoney = "money", copper = "money",
   equipped = "equipment", inCombat = "combat", isDead = "dead",
}

local function wrapWorld(w)
   return setmetatable(w, {
      __index = function(_, k)
         local p = WORLD_ALIASES[k]
         if p then return rawget(w, p) end
         if k == "cursorX" then return w.cursor[1] end
         if k == "cursorY" then return w.cursor[2] end
         if k == "screen" then
            local sw, sh = rawget(w, "screenWidth"), rawget(w, "screenHeight")
            return { w = sw, h = sh, width = sw, height = sh }
         end
         return nil
      end,
      __newindex = function(t, k, v)
         local p = WORLD_ALIASES[k]
         if p then
            rawset(t, p, v)
         elseif k == "cursorX" then
            rawget(t, "cursor")[1] = v
         elseif k == "cursorY" then
            rawget(t, "cursor")[2] = v
         elseif k == "screen" and type(v) == "table" then
            rawset(t, "screenWidth", v.w or v.width or v[1] or rawget(t, "screenWidth"))
            rawset(t, "screenHeight", v.h or v.height or v[2] or rawget(t, "screenHeight"))
         else
            rawset(t, k, v)
         end
      end,
   })
end

local function newWorld()
   return wrapWorld({
      locale = "enUS", playerName = "Testplayer", realmName = "Testrealm",
      race = "Human",          -- englisches Token (UnitRace 2. Rueckgabe); Tabelle {lokal, token} erlaubt
      class = "WARRIOR",       -- englisches Token in Grossbuchstaben (UnitClass 2. Rueckgabe)
      faction = nil,           -- "Alliance"/"Horde"; nil = aus der Rasse abgeleitet
      level = 80, sex = 2,
      money = 10000000,
      screenWidth = 1365, screenHeight = 768, uiScale = 1,
      cursor = { 683, 384 },
      shift = false, ctrl = false, alt = false,
      equipment = {},          -- [Client-Slot-ID] = itemId
      bags = {},               -- [bag][slot] = itemId
      itemCounts = {},         -- [itemId] = Anzahl (GetItemCount)
      equipmentCached = true,  -- angelegte Gegenstaende gelten immer als im Cache
      itemCacheDelay = 0.3,    -- Sekunden zwischen SetHyperlink und "gecacht"
      gossipOpen = false,
      globalStrings = true,    -- false = Blizzard-Globalstrings (HEADSLOT ...) fehlen
      hasUndressSlot = false,  -- DressUpModel:UndressSlot vorhanden?
      hasRegisterAddonMessagePrefix = false,
      auctionLists = nil,      -- { classes = {...}, subclasses = { [i] = {...} } }
      combat = false, dead = false, chatOpen = false,
      units = {},              -- [unit] = { name = ..., exists = true }
      cvars = {},
      modifiedClick = {},      -- [aktion] = bool, ueberschreibt IsModifiedClick
      loggedIn = false,
      strictApi = true,        -- false = unbekannte Methoden liefern nil statt Fehler
   })
end

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------------

-- Tiefe Kopie (Zyklen werden nicht erwartet)
function U.copy(v)
   if type(v) ~= "table" then return v end
   local t = {}
   for k, x in pairs(v) do t[k] = U.copy(x) end
   return t
end

-- Fuehrt src rekursiv in dst ein (Tabellen werden zusammengefuehrt)
function U.merge(dst, src)
   for k, v in pairs(src) do
      if type(v) == "table" and type(dst[k]) == "table" and k ~= "auctionLists" then
         U.merge(dst[k], v)
      else
         dst[k] = U.copy(v)
      end
   end
end

-- Meldung fuer Tests und Runner (kein Fehler)
function U.warn(msg)
   M.warnings[#M.warnings + 1] = msg
end

-- Ist o ein Objekt der Attrappe (Frame oder Region)? Gibt den Typnamen zurueck.
function U.typeOf(o)
   if type(o) == "table" then return rawget(o, "__type") end
   return nil
end

local REGION_TYPES = { Texture = true, FontString = true }
function U.isRegion(o) return REGION_TYPES[U.typeOf(o) or ""] == true end
function U.isFrame(o)
   local t = U.typeOf(o)
   return t ~= nil and not REGION_TYPES[t] and t ~= "Font"
end
function U.isObject(o)
   local t = U.typeOf(o)
   return t ~= nil and t ~= "Font"
end

-- Typ-Hierarchie
local PARENT_TYPE = {
   Button = "Frame", CheckButton = "Button", EditBox = "Frame", Slider = "Frame", StatusBar = "Frame",
   ScrollFrame = "Frame", Model = "Frame", PlayerModel = "Model", DressUpModel = "PlayerModel",
   GameTooltip = "Frame", ScrollingMessageFrame = "Frame",
}
function U.isA(typeName, base)
   local t = typeName
   while t do
      if t == base then return true end
      t = PARENT_TYPE[t]
   end
   return false
end

-- Argumentpruefungen (Fehlerstelle = aufrufender Addon-Code, Ebene 3)
function U.badArg(n, fname, expected, got)
   error(sfmt("bad argument #%d to '%s' (%s expected, got %s)", n, fname, expected, type(got)), 3)
end
function U.num(v, n, fname)
   if type(v) ~= "number" then U.badArg(n, fname, "number", v) end
   if v ~= v or v == huge or v == -huge then
      error(sfmt("bad argument #%d to '%s' (number is NaN or infinite)", n, fname), 3)
   end
   return v
end
function U.str(v, n, fname)
   if type(v) ~= "string" then U.badArg(n, fname, "string", v) end
   return v
end

-- Bildet ein Argumentpaket (mit n) und ruft fn geschuetzt; Fehler gehen an den
-- Fehler-Handler (wie bei Skript-Handlern im Spiel). Gibt true zurueck, wenn kein Fehler.
function U.protected(fn, ...)
   local args = { n = select("#", ...), ... }
   local ok, err = xpcall(function() return fn(unpack(args, 1, args.n)) end, function(m)
      return { msg = m, trace = realDebug.traceback(tostring(m), 2) }
   end)
   if not ok then
      U.reportError(err.msg, err.trace)
      return false
   end
   return true
end

-- Gibt einen Fehler an den aktuellen Fehler-Handler weiter
function U.reportError(msg, trace)
   local h = S.errorHandler
   if h == nil or h == S.defaultHandler then
      M.errors[#M.errors + 1] = tostring(msg)
      M.errorTraces[#M.errors] = trace or realDebug.traceback(tostring(msg), 2)
   else
      pcall(h, msg)
   end
end

-- ---------------------------------------------------------------------------
-- Zustand
-- ---------------------------------------------------------------------------

local function resetState()
   S.nextId = 0
   S.lastTime = nil
   S.eventFrames = {}
   S.templates = {}
   S.fonts = {}
   S.cached = {}
   S.pending = {}
   S.fades = {}
   S.hover = nil
   S.focus = nil
   S.focusQueue = {}
   S.drag = nil
   S.popupFrames = {}
   S.allowedFields = {}
   S.strictApi = true
   S.UIParent = nil
   S.assetSeen = {}
   S.defaultHandler = function(msg)
      M.errors[#M.errors + 1] = tostring(msg)
      M.errorTraces[#M.errors] = realDebug.traceback(tostring(msg), 2)
   end
   S.errorHandler = S.defaultHandler
   S.xmlFrames = {}
   M.now = 1000.0
   M.frames = {}
   M.messages = {}
   M.sentAddon = {}
   M.sentChat = {}
   M.errors = {}
   M.errorTraces = {}
   M.warnings = {}
   M.sounds = {}
   M.chatInserts = {}
   M.dressUps = {}
   M.popups = {}
   M.popup = nil
   M.itemQueries = {}
   M.items = {}
   M.missingAssets = {}
   M.globalMisses = {}
   M.globalWrites = {}
   M.registeredPrefixes = {}
   M.reloads = 0
   M.toc = nil
   M.bindings = {}
   M.addonTable = nil
   S.world = newWorld()
end
resetState()

-- Zuweisung M.world = {...}: auf Standardwerte zuruecksetzen und mischen (siehe Metatabelle von M)
do
   local mt = getmetatable(M)
   mt.__newindex = function(t, k, v)
      if k == "world" then
         local w = newWorld()
         if type(v) == "table" then U.merge(w, v) end
         S.world = w
         return
      end
      rawset(t, k, v)
   end
end

-- ---------------------------------------------------------------------------
-- Objektmodell: Methodentabellen, Skripte, Sichtbarkeit, Layout
-- ---------------------------------------------------------------------------

local RegionM, FrameM, TextureM, FontStringM = {}, {}, {}, {}
local ButtonM, CheckButtonM, EditBoxM, SliderM, StatusBarM, ScrollFrameM = {}, {}, {}, {}, {}, {}
local ModelM, PlayerModelM, DressUpModelM, TooltipM, MsgFrameM, FontM = {}, {}, {}, {}, {}, {}

-- Anker: Name -> { Anteil horizontal, Anteil vertikal } (0/0 = links unten)
local POINTS = {
   TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
   LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
   BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
local STRATA = {
   WORLD = true, BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
   FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true,
}
local LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true, HIGHLIGHT = true }
local BLEND = { DISABLE = true, BLEND = true, ALPHAKEY = true, ADD = true, MOD = true }
local DRAG_BUTTONS = { LeftButton = true, RightButton = true, MiddleButton = true, Button4 = true, Button5 = true }
local CLICK_TOKENS = {
   LeftButtonUp = true, LeftButtonDown = true, RightButtonUp = true, RightButtonDown = true,
   MiddleButtonUp = true, MiddleButtonDown = true, Button4Up = true, Button4Down = true,
   Button5Up = true, Button5Down = true, AnyUp = true, AnyDown = true,
}
-- Elemente, die von sich aus Mausereignisse annehmen (CreateFrame-Standard)
local MOUSE_DEFAULT = { Button = true, CheckButton = true, EditBox = true, Slider = true }

-- Gueltige Skriptnamen je Typ (3.3.5a); Untertypen erben
local function toSet(list)
   local s = {}
   for _, n in ipairs(list) do s[n] = true end
   return s
end
local SCRIPTS = {
   Frame = toSet({ "OnLoad", "OnUpdate", "OnEvent", "OnShow", "OnHide", "OnSizeChanged", "OnEnter", "OnLeave",
                   "OnMouseDown", "OnMouseUp", "OnMouseWheel", "OnDragStart", "OnDragStop", "OnReceiveDrag",
                   "OnKeyDown", "OnKeyUp", "OnChar", "OnEnable", "OnDisable", "OnAttributeChanged" }),
   Button = toSet({ "OnClick", "OnDoubleClick", "PreClick", "PostClick" }),
   EditBox = toSet({ "OnTextChanged", "OnTextSet", "OnEditFocusGained", "OnEditFocusLost", "OnEnterPressed",
                     "OnEscapePressed", "OnTabPressed", "OnSpacePressed", "OnCursorChanged",
                     "OnInputLanguageChanged", "OnArrowPressed" }),
   Slider = toSet({ "OnValueChanged", "OnMinMaxChanged" }),
   StatusBar = toSet({ "OnValueChanged", "OnMinMaxChanged" }),
   ScrollFrame = toSet({ "OnScrollRangeChanged", "OnVerticalScroll", "OnHorizontalScroll" }),
   Model = toSet({ "OnUpdateModel", "OnAnimFinished", "OnModelLoaded", "OnModelCleared" }),
   GameTooltip = toSet({ "OnTooltipSetItem", "OnTooltipSetUnit", "OnTooltipSetSpell", "OnTooltipCleared",
                         "OnTooltipAddMoney", "OnTooltipSetQuest", "OnTooltipSetAchievement",
                         "OnTooltipSetEquipmentSet", "OnTooltipSetFramestack", "OnTooltipSetDefaultAnchor" }),
}
function U.validScript(typeName, name)
   local t = typeName
   while t do
      local set = SCRIPTS[t]
      if set and set[name] then return true end
      t = PARENT_TYPE[t]
   end
   return false
end

-- ---------------------------------------------------------------------------
-- Sichtbarkeit, Skripte
-- ---------------------------------------------------------------------------

-- IsVisible: eigener Schalter und alle Eltern
function U.isVisible(o)
   local p = o
   while p do
      if not p.__shown then return false end
      p = p.__parent
   end
   return true
end

-- Ruft Skript und Hooks (Hooks nach dem Skript); Fehler gehen an den Fehler-Handler
function U.runScript(o, name, ...)
   local scripts = o.__scripts
   if not scripts then return end
   local fn = scripts[name]
   local hooks = o.__hooks and o.__hooks[name]
   if not fn and not hooks then return end
   if fn then U.protected(fn, o, ...) end
   if hooks then
      local snap = {}
      for i = 1, #hooks do snap[i] = hooks[i] end
      for i = 1, #snap do U.protected(snap[i], o, ...) end
   end
end

function U.hasHandler(o, name)
   if not o.__scripts then return false end
   if o.__scripts[name] then return true end
   local hooks = o.__hooks and o.__hooks[name]
   return hooks ~= nil and #hooks > 0
end

-- Wird gerufen, wenn sich die tatsaechliche Sichtbarkeit von o geaendert hat
function U.visibilityChanged(o, visible)
   U.runScript(o, visible and "OnShow" or "OnHide")
   if U.isVisible(o) ~= visible then return end   -- Handler hat es wieder umgestellt
   if o.__type == "EditBox" then
      if visible then
         if o.__autoFocus ~= false then U.queueFocus(o) end
      elseif S.focus == o then
         U.clearFocus(o)
      end
   elseif o.__type == "GameTooltip" and not visible then
      o.__owner = nil
   end
   local kids = o.__children
   if kids and #kids > 0 then
      local snap = {}
      for i = 1, #kids do snap[i] = kids[i] end
      for i = 1, #snap do
         local c = snap[i]
         if c.__shown and c.__parent == o then U.visibilityChanged(c, visible) end
      end
   end
end

function U.setShown(o, flag)
   flag = flag and true or false
   if o.__shown == flag then return end
   local before = U.isVisible(o)
   o.__shown = flag
   if not U.isFrame(o) then return end
   local after = U.isVisible(o)
   if before ~= after then U.visibilityChanged(o, after) end
end

-- ---------------------------------------------------------------------------
-- Fokus (EditBox)
-- ---------------------------------------------------------------------------

-- AutoFocus wird erst im naechsten Frame wirksam (deshalb funktioniert das Muster
-- CreateFrame(...) gefolgt von SetAutoFocus(false) ohne ClearFocus): Warteschlange, die
-- M.Advance abarbeitet; dabei zaehlt der Zustand zu diesem Zeitpunkt.
function U.queueFocus(e)
   S.focusQueue[#S.focusQueue + 1] = e
end

function U.processFocusQueue()
   local q = S.focusQueue
   if #q == 0 then return end
   S.focusQueue = {}
   for _, e in ipairs(q) do
      if e.__autoFocus ~= false and U.isVisible(e) then U.setFocus(e) end
   end
end

function U.setFocus(e)
   if S.focus == e then return end
   if not U.isVisible(e) then return end
   local old = S.focus
   if old then U.clearFocus(old) end
   S.focus = e
   U.runScript(e, "OnEditFocusGained")
end

function U.clearFocus(e)
   if S.focus ~= e then return end
   S.focus = nil
   U.runScript(e, "OnEditFocusLost")
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

-- Effektiver Scale (Produkt der Scales von o und allen Eltern; Regionen: ihres Elternframes)
function U.effScale(o)
   local s = 1
   local p = o
   if U.isRegion(o) then p = o.__parent end
   while p do
      s = s * (p.__scale or 1)
      p = p.__parent
   end
   return s
end

-- Zeichenbreite (grob): ASCII 0.55 * Schriftgroesse, Mehrbyte-Zeichen 1.0 * Schriftgroesse
function U.fontSize(fs)
   local f = fs.__font
   if not f and fs.__fontObject then f = fs.__fontObject.__font end
   return f and f.size or 12
end

function U.stripEscapes(s)
   s = sgsub(s, "|c%x%x%x%x%x%x%x%x", "")
   s = sgsub(s, "|r", "")
   s = sgsub(s, "|T[^|]*|t", "  ")
   s = sgsub(s, "|H[^|]*|h", "")
   s = sgsub(s, "|h", "")
   s = sgsub(s, "||", "|")
   return s
end

function U.lineWidth(line, size)
   local w = 0
   local i, n = 1, #line
   while i <= n do
      local b = sbyte(line, i)
      if b < 0x80 then
         w = w + size * 0.55
         i = i + 1
      elseif b < 0xE0 then
         w = w + size * 0.6
         i = i + 2
      else
         w = w + size
         i = i + (b < 0xF0 and 3 or 4)
      end
   end
   return w
end

function U.textLines(fs)
   local text = fs.__text
   if text == nil or text == "" then return {} end
   text = U.stripEscapes(text)
   local lines = {}
   for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
   return lines
end

function U.textWidth(fs)
   local size = U.fontSize(fs)
   local wmax = 0
   for _, line in ipairs(U.textLines(fs)) do
      local w = U.lineWidth(line, size)
      if w > wmax then wmax = w end
   end
   return wmax
end

function U.explicitWidth(o)
   if o.__isScreen then return M.world.screenWidth end
   local w = o.__width
   if (w == nil or w == 0) and o.__type == "FontString" then return U.textWidth(o) end
   return w or 0
end

function U.explicitHeight(o)
   if o.__isScreen then return M.world.screenHeight end
   local h = o.__height
   if (h == nil or h == 0) and o.__type == "FontString" then
      return U.fontSize(o) * max(1, #U.textLines(o))
   end
   return h or 0
end

-- Loest eine Achse aus Gleichungen { Anteil, Position }: liefert Start und Groesse
function U.solveAxis(eqs, explicit)
   local a = eqs[1]
   for i = 2, #eqs do
      local b = eqs[i]
      if b[1] ~= a[1] then
         local size = (b[2] - a[2]) / (b[1] - a[1])
         return a[2] - a[1] * size, size
      end
   end
   return a[2] - a[1] * explicit, explicit
end

-- Rechteck in "Effektiv-Scale-Raum": links, unten, Breite, Hoehe; nil, wenn nicht aufloesbar
-- (kein Anker, oder ein Anker-Ziel ist selbst nicht aufloesbar).
function U.rect(o, depth)
   depth = depth or 0
   if depth > 40 then return nil end
   if o.__isScreen then
      local sc = o.__scale or 1
      return 0, 0, M.world.screenWidth * sc, M.world.screenHeight * sc
   end
   local pts = o.__points
   if #pts == 0 then return nil end
   local eff = U.effScale(o)
   local hx, vy = {}, {}
   for i = 1, #pts do
      local p = pts[i]
      local rel = p.rel or o.__parent or S.UIParent
      if not rel then return nil end
      local rl, rb, rw, rh = U.rect(rel, depth + 1)
      if not rl then return nil end
      local fr, fo = POINTS[p.relPoint], POINTS[p.point]
      hx[#hx + 1] = { fo[1], rl + fr[1] * rw + p.x * eff }
      vy[#vy + 1] = { fo[2], rb + fr[2] * rh + p.y * eff }
   end
   local left, width = U.solveAxis(hx, U.explicitWidth(o) * eff)
   local bottom, height = U.solveAxis(vy, U.explicitHeight(o) * eff)
   return left, bottom, width, height
end

-- Haengt a (ueber Anker, auch den impliziten zum Elternframe) von b ab?
function U.dependsOn(a, b, depth)
   if a == b then return true end
   depth = depth or 0
   if depth > 40 then return false end
   for _, p in ipairs(a.__points or {}) do
      local rel = p.rel or a.__parent
      if rel and U.dependsOn(rel, b, depth + 1) then return true end
   end
   return false
end

-- ---------------------------------------------------------------------------
-- Methoden: Region (gemeinsam fuer Frames, Texturen, FontStrings)
-- ---------------------------------------------------------------------------

function RegionM.GetName(self) return self.__name end
function RegionM.GetObjectType(self) return self.__type end
function RegionM.IsObjectType(self, t)
   if type(t) ~= "string" then U.badArg(1, "IsObjectType", "string", t) end
   if U.isA(self.__type, t) or t == "Region" or t == "LayoutFrame" or t == "Object" then return 1 end
   return nil
end
function RegionM.GetParent(self) return self.__parent end

function RegionM.SetParent(self, parent)
   if parent ~= nil and not U.isFrame(parent) then
      error("SetParent(): the parent must be a frame (or nil)", 2)
   end
   local p = parent
   while p do
      if p == self then error("SetParent(): would create a parent loop", 2) end
      p = p.__parent
   end
   local old = self.__parent
   if old == parent then return end
   local frame = U.isFrame(self)
   local before = frame and U.isVisible(self)
   if old then
      local list = frame and old.__children or old.__regions
      for i = #list, 1, -1 do
         if list[i] == self then tremove(list, i) break end
      end
   end
   self.__parent = parent
   if parent then
      local list = frame and parent.__children or parent.__regions
      list[#list + 1] = self
      if frame then
         if not self.__strataSet then self.__strata = parent.__strata end
         if not self.__levelSet then self.__level = parent.__level + 1 end
      end
   end
   if frame and self.__shown then
      local after = U.isVisible(self)
      if before ~= after then U.visibilityChanged(self, after) end
   end
end

function RegionM.GetAlpha(self) return self.__alpha end
function RegionM.SetAlpha(self, a)
   U.num(a, 1, "SetAlpha")
   if a < 0 then a = 0 elseif a > 1 then a = 1 end
   self.__alpha = a
end

function RegionM.Show(self) U.setShown(self, true) end
function RegionM.Hide(self) U.setShown(self, false) end
function RegionM.IsShown(self) return self.__shown and 1 or nil end
function RegionM.IsVisible(self) return U.isVisible(self) and 1 or nil end

-- SetPoint(point [, relativeTo [, relativePoint]] [, x, y])
function RegionM.SetPoint(self, point, a2, a3, a4, a5)
   if type(point) ~= "string" or not POINTS[point] then
      error("SetPoint(): unknown anchor point " .. tostring(point), 2)
   end
   local rel, relPoint, x, y
   if type(a2) == "number" then
      x, y = a2, a3
   elseif a2 == nil and type(a3) ~= "string" then
      x, y = a3, a4
   else
      rel = a2
      if type(a3) == "string" then
         relPoint = a3
         x, y = a4, a5
      else
         x, y = a3, a4
      end
   end
   if type(rel) == "string" then
      local named = rawget(_G, rel)
      if not U.isObject(named) then
         error("SetPoint(): couldn't find a region named '" .. rel .. "'", 2)
      end
      rel = named
   end
   if rel ~= nil then
      if not U.isObject(rel) then
         error("SetPoint(): relativeTo must be a frame or region, got " .. type(rel), 2)
      end
      if rel == self then error("SetPoint(): cannot anchor to itself", 2) end
      if U.dependsOn(rel, self) then
         error("SetPoint(): cannot anchor to a region that depends on it (anchor loop)", 2)
      end
   end
   if relPoint ~= nil and not POINTS[relPoint] then
      error("SetPoint(): unknown relative anchor point " .. tostring(relPoint), 2)
   end
   if x ~= nil then U.num(x, 3, "SetPoint") end
   if y ~= nil then U.num(y, 4, "SetPoint") end
   local entry = { point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 }
   local pts = self.__points
   for i = 1, #pts do
      if pts[i].point == point then
         pts[i] = entry
         return
      end
   end
   pts[#pts + 1] = entry
end

function RegionM.GetPoint(self, i)
   i = i or 1
   local p = self.__points[i]
   if not p then return nil end
   return p.point, p.rel or self.__parent, p.relPoint, p.x, p.y
end
function RegionM.GetNumPoints(self) return #self.__points end
function RegionM.ClearAllPoints(self) self.__points = {} end

function RegionM.SetAllPoints(self, target)
   local rel
   if target == nil or target == true then
      rel = nil
   elseif type(target) == "string" then
      rel = rawget(_G, target)
      if not U.isObject(rel) then error("SetAllPoints(): couldn't find a region named '" .. target .. "'", 2) end
   elseif U.isObject(target) then
      rel = target
   else
      error("SetAllPoints(): invalid argument", 2)
   end
   if rel == self then error("SetAllPoints(): cannot anchor to itself", 2) end
   if rel and U.dependsOn(rel, self) then error("SetAllPoints(): anchor loop", 2) end
   self.__points = {
      { point = "TOPLEFT", rel = rel, relPoint = "TOPLEFT", x = 0, y = 0 },
      { point = "BOTTOMRIGHT", rel = rel, relPoint = "BOTTOMRIGHT", x = 0, y = 0 },
   }
end

function RegionM.GetLeft(self)
   local l = U.rect(self)
   if not l then return nil end
   return l / U.effScale(self)
end
function RegionM.GetRight(self)
   local l, _, w = U.rect(self)
   if not l then return nil end
   return (l + w) / U.effScale(self)
end
function RegionM.GetBottom(self)
   local _, b = U.rect(self)
   if not b then return nil end
   return b / U.effScale(self)
end
function RegionM.GetTop(self)
   local _, b, _, h = U.rect(self)
   if not b then return nil end
   return (b + h) / U.effScale(self)
end
function RegionM.GetCenter(self)
   local l, b, w, h = U.rect(self)
   if not l then return nil end
   local e = U.effScale(self)
   return (l + w / 2) / e, (b + h / 2) / e
end

-- GetWidth/GetHeight: der EXPLIZIT gesetzte Wert oder 0 (nie aus Ankern abgeleitet)
function RegionM.GetWidth(self) return U.explicitWidth(self) end
function RegionM.GetHeight(self) return U.explicitHeight(self) end

function U.sizeChanged(o)
   if not U.isFrame(o) then return end
   U.runScript(o, "OnSizeChanged", U.explicitWidth(o), U.explicitHeight(o))
   local p = o.__parent
   if p and p.__type == "ScrollFrame" and p.__scrollChild == o then U.updateScrollRange(p) end
   if o.__type == "ScrollFrame" then U.updateScrollRange(o) end
end

function RegionM.SetWidth(self, w)
   U.num(w, 1, "SetWidth")
   if w < 0 then error("SetWidth(): negative width " .. tostring(w), 2) end
   local old = self.__width or 0
   self.__width = w
   if old ~= w then U.sizeChanged(self) end
end
function RegionM.SetHeight(self, h)
   U.num(h, 1, "SetHeight")
   if h < 0 then error("SetHeight(): negative height " .. tostring(h), 2) end
   local old = self.__height or 0
   self.__height = h
   if old ~= h then U.sizeChanged(self) end
end

-- ---------------------------------------------------------------------------
-- Methoden: Frame
-- ---------------------------------------------------------------------------

function FrameM.GetEffectiveAlpha(self)
   local a = 1
   local p = self
   while p do
      a = a * (p.__alpha or 1)
      p = p.__parent
   end
   return a
end

function FrameM.GetScale(self) return self.__scale end
function FrameM.SetScale(self, s)
   U.num(s, 1, "SetScale")
   if s <= 0 then error("SetScale(): scale must be greater than 0 (got " .. tostring(s) .. ")", 2) end
   self.__scale = s
end
function FrameM.GetEffectiveScale(self) return U.effScale(self) end

function U.eachDescendant(o, fn)
   for _, c in ipairs(o.__children) do
      fn(c)
      U.eachDescendant(c, fn)
   end
end

function FrameM.GetFrameStrata(self) return self.__strata end
function FrameM.SetFrameStrata(self, s)
   if type(s) ~= "string" or not STRATA[s] then
      error("SetFrameStrata(): invalid strata " .. tostring(s), 2)
   end
   self.__strata = s
   self.__strataSet = true
   U.eachDescendant(self, function(c)
      if not c.__strataSet then c.__strata = s end
   end)
end

function FrameM.GetFrameLevel(self) return self.__level end
function FrameM.SetFrameLevel(self, n)
   U.num(n, 1, "SetFrameLevel")
   if n < 0 then n = 0 end
   local delta = n - self.__level
   self.__level = n
   self.__levelSet = true
   if delta ~= 0 then
      U.eachDescendant(self, function(c) c.__level = max(0, c.__level + delta) end)
   end
end

function FrameM.GetID(self) return self.__idValue or 0 end
function FrameM.SetID(self, id)
   U.num(id, 1, "SetID")
   self.__idValue = id
end

function FrameM.EnableMouse(self, flag) self.__mouse = flag and true or false end
function FrameM.IsMouseEnabled(self) return self.__mouse and 1 or nil end
function FrameM.EnableMouseWheel(self, flag) self.__mouseWheel = flag and true or false end
function FrameM.EnableKeyboard(self, flag) self.__keyboard = flag and true or false end
function FrameM.IsKeyboardEnabled(self) return self.__keyboard and 1 or nil end

function FrameM.SetMovable(self, flag) self.__movable = flag and true or false end
function FrameM.IsMovable(self) return self.__movable and 1 or nil end
function FrameM.SetResizable(self, flag) self.__resizable = flag and true or false end
function FrameM.IsResizable(self) return self.__resizable and 1 or nil end
function FrameM.SetUserPlaced(self, flag) self.__userPlaced = flag and true or false end
function FrameM.IsUserPlaced(self) return self.__userPlaced and 1 or nil end
function FrameM.SetClampedToScreen(self, flag) self.__clamped = flag and true or false end
function FrameM.SetClampRectInsets(self, l, r, t, b)
   U.num(l, 1, "SetClampRectInsets") U.num(r, 2, "SetClampRectInsets")
   U.num(t, 3, "SetClampRectInsets") U.num(b, 4, "SetClampRectInsets")
   self.__clampInsets = { l, r, t, b }
end
function FrameM.SetMinResize(self, w, h)
   U.num(w, 1, "SetMinResize") U.num(h, 2, "SetMinResize")
   self.__minResize = { w, h }
end
function FrameM.SetMaxResize(self, w, h)
   U.num(w, 1, "SetMaxResize") U.num(h, 2, "SetMaxResize")
   self.__maxResize = { w, h }
end
function FrameM.SetHitRectInsets(self, l, r, t, b)
   U.num(l, 1, "SetHitRectInsets") U.num(r, 2, "SetHitRectInsets")
   U.num(t, 3, "SetHitRectInsets") U.num(b, 4, "SetHitRectInsets")
   self.__hitInsets = { l, r, t, b }
end

function FrameM.StartMoving(self)
   if not self.__movable then
      error("StartMoving(): the frame is not movable (SetMovable(true) missing)", 2)
   end
   S.drag = { frame = self, mode = "move" }
end
function FrameM.StartSizing(self, point)
   if not self.__resizable then
      error("StartSizing(): the frame is not resizable (SetResizable(true) missing)", 2)
   end
   if point ~= nil and (type(point) ~= "string" or not POINTS[point]) then
      error("StartSizing(): unknown anchor point " .. tostring(point), 2)
   end
   S.drag = { frame = self, mode = "size", point = point or "BOTTOMRIGHT" }
end
function FrameM.StopMovingOrSizing(self)
   local d = S.drag
   if d and d.mode == "move" and d.frame.__movable then d.frame.__userPlaced = true end
   S.drag = nil
end

function FrameM.RegisterForDrag(self, ...)
   local set = {}
   for i = 1, select("#", ...) do
      local b = select(i, ...)
      if type(b) ~= "string" or not DRAG_BUTTONS[b] then
         error("RegisterForDrag(): invalid mouse button " .. tostring(b), 2)
      end
      set[b] = true
   end
   self.__drag = set
end

function FrameM.SetToplevel(self, flag) self.__toplevel = flag and true or false end
function FrameM.Raise(self)
   local hi = self.__level
   local p = self.__parent
   if p then
      for _, c in ipairs(p.__children) do
         if c ~= self and c.__strata == self.__strata and c.__level > hi then hi = c.__level end
      end
   end
   local delta = (hi + 1) - self.__level
   if self.__level < hi + 1 then
      self.__level = hi + 1
      U.eachDescendant(self, function(c) c.__level = c.__level + delta end)
   end
end
function FrameM.Lower(self)
   local lo = self.__level
   local p = self.__parent
   if p then
      for _, c in ipairs(p.__children) do
         if c ~= self and c.__strata == self.__strata and c.__level < lo then lo = c.__level end
      end
   end
   if lo > 0 and self.__level > lo - 1 then
      local delta = (lo - 1) - self.__level
      self.__level = lo - 1
      U.eachDescendant(self, function(c) c.__level = max(0, c.__level + delta) end)
   end
end

function FrameM.GetChildren(self) return unpack(self.__children) end
function FrameM.GetNumChildren(self) return #self.__children end
function FrameM.GetRegions(self) return unpack(self.__regions) end
function FrameM.GetNumRegions(self) return #self.__regions end

function FrameM.SetAttribute(self, name, value)
   U.str(name, 1, "SetAttribute")
   local old = self.__attrs[name]
   self.__attrs[name] = value
   if old ~= value then U.runScript(self, "OnAttributeChanged", name, value) end
end
function FrameM.GetAttribute(self, name)
   U.str(name, 1, "GetAttribute")
   return self.__attrs[name]
end

-- Ob die Maus ueber dem Frame ist: bestimmt allein M.Enter/M.Leave (Hover-Modell)
function FrameM.IsMouseOver(self)
   local h = S.hover
   if not h or not U.isVisible(h) then return nil end
   local p = h
   while p do
      if p == self then return 1 end
      p = p.__parent
   end
   return nil
end

-- Backdrop
function FrameM.SetBackdrop(self, bd)
   if bd ~= nil and type(bd) ~= "table" then U.badArg(1, "SetBackdrop", "table", bd) end
   self.__backdrop = bd
end
function FrameM.GetBackdrop(self) return self.__backdrop end
local function colorArgs(fname, r, g, b, a)
   U.num(r, 1, fname) U.num(g, 2, fname) U.num(b, 3, fname)
   if a ~= nil then U.num(a, 4, fname) end
   return { r, g, b, a or 1 }
end
function FrameM.SetBackdropColor(self, r, g, b, a)
   self.__backdropColor = colorArgs("SetBackdropColor", r, g, b, a)
end
function FrameM.GetBackdropColor(self)
   local c = self.__backdropColor or { 1, 1, 1, 1 }
   return c[1], c[2], c[3], c[4]
end
function FrameM.SetBackdropBorderColor(self, r, g, b, a)
   self.__backdropBorderColor = colorArgs("SetBackdropBorderColor", r, g, b, a)
end
function FrameM.GetBackdropBorderColor(self)
   local c = self.__backdropBorderColor or { 1, 1, 1, 1 }
   return c[1], c[2], c[3], c[4]
end

-- Skripte
function FrameM.SetScript(self, name, fn)
   U.str(name, 1, "SetScript")
   if fn ~= nil and type(fn) ~= "function" then U.badArg(2, "SetScript", "function", fn) end
   if not U.validScript(self.__type, name) then
      error(self.__type .. ":SetScript(): unknown script '" .. name .. "' for a " .. self.__type, 2)
   end
   self.__scripts[name] = fn
end
function FrameM.GetScript(self, name)
   U.str(name, 1, "GetScript")
   if not U.validScript(self.__type, name) then
      error(self.__type .. ":GetScript(): unknown script '" .. name .. "' for a " .. self.__type, 2)
   end
   return self.__scripts[name]
end
function FrameM.HookScript(self, name, fn)
   U.str(name, 1, "HookScript")
   if type(fn) ~= "function" then U.badArg(2, "HookScript", "function", fn) end
   if not U.validScript(self.__type, name) then
      error(self.__type .. ":HookScript(): unknown script '" .. name .. "' for a " .. self.__type, 2)
   end
   local list = self.__hooks[name]
   if not list then
      list = {}
      self.__hooks[name] = list
   end
   list[#list + 1] = fn
end
function FrameM.HasScript(self, name)
   U.str(name, 1, "HasScript")
   return U.validScript(self.__type, name) and 1 or nil
end

-- Ereignisse
function FrameM.RegisterEvent(self, ev)
   U.str(ev, 1, "RegisterEvent")
   if FOREIGN_EVENTS[ev] then
      error("API not in 3.3.5a: event '" .. ev .. "' does not exist in 3.3.5a", 2)
   end
   if self.__events[ev] then return end
   self.__events[ev] = true
   local list = S.eventFrames[ev]
   if not list then
      list = {}
      S.eventFrames[ev] = list
   end
   list[#list + 1] = self
end
function FrameM.UnregisterEvent(self, ev)
   U.str(ev, 1, "UnregisterEvent")
   if not self.__events[ev] then return end
   self.__events[ev] = nil
   local list = S.eventFrames[ev]
   if list then
      for i = #list, 1, -1 do
         if list[i] == self then tremove(list, i) break end
      end
   end
end
function FrameM.UnregisterAllEvents(self)
   for ev in pairs(self.__events) do FrameM.UnregisterEvent(self, ev) end
end
function FrameM.IsEventRegistered(self, ev)
   U.str(ev, 1, "IsEventRegistered")
   return self.__events[ev] and 1 or nil
end

-- Regionen anlegen
function FrameM.CreateTexture(self, name, layer, inherits)
   if name ~= nil then U.str(name, 1, "CreateTexture") end
   if layer ~= nil and (type(layer) ~= "string" or not LAYERS[layer]) then
      error("CreateTexture(): invalid draw layer " .. tostring(layer), 2)
   end
   if inherits ~= nil and type(inherits) ~= "string" then U.badArg(3, "CreateTexture", "string", inherits) end
   return U.newRegion("Texture", name, self, layer or "ARTWORK")
end
function FrameM.CreateFontString(self, name, layer, inherits)
   if name ~= nil then U.str(name, 1, "CreateFontString") end
   if layer ~= nil and (type(layer) ~= "string" or not LAYERS[layer]) then
      error("CreateFontString(): invalid draw layer " .. tostring(layer), 2)
   end
   local fs = U.newRegion("FontString", name, self, layer or "ARTWORK")
   if inherits ~= nil then
      if type(inherits) ~= "string" then U.badArg(3, "CreateFontString", "string", inherits) end
      local font = S.fonts[inherits]
      if not font then
         error("CreateFontString(): couldn't find inherited font '" .. inherits .. "'", 2)
      end
      fs.__fontObject = font
   end
   return fs
end

-- ---------------------------------------------------------------------------
-- Regionen: Texture, FontString, Schriftobjekte
-- ---------------------------------------------------------------------------

local META = {}   -- META[Typname] = Metatabelle (wird in buildMeta gefuellt)

-- Legt eine Region (Texture/FontString) an und haengt sie an den Elternframe
function U.newRegion(typeName, name, parent, layer)
   local o = setmetatable({}, META[typeName])
   S.nextId = S.nextId + 1
   o.__id = S.nextId
   o.__type = typeName
   o.__name = name
   o.__shown = true
   o.__alpha = 1
   o.__points = {}
   o.__parent = parent
   o.__layer = layer or "ARTWORK"
   o.__sub = 0
   parent.__regions[#parent.__regions + 1] = o
   if name then
      if rawget(_G, name) ~= nil then
         U.warn("region name '" .. name .. "' overwrites an existing global")
      end
      rawset(_G, name, o)
   end
   return o
end

-- Prueft einen Pfad auf Addon-Dateien, die es nicht gibt (Textur/Ton)
function U.checkAsset(path, kind)
   if type(path) ~= "string" then return end
   local rest = smatch(path, "^[Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee][\\/][Aa][Dd][Dd][Oo][Nn][Ss][\\/]Transmog[\\/](.+)$")
   if not rest then return end
   if S.assetSeen[path] ~= nil then return end
   local file = M.root .. "/" .. sgsub(rest, "\\", "/")
   local f = realIo.open(file, "rb")
   if f then
      f:close()
      S.assetSeen[path] = true
   else
      S.assetSeen[path] = false
      M.missingAssets[#M.missingAssets + 1] = { kind = kind, path = path, file = file }
   end
end

-- ---- Texture --------------------------------------------------------------

function TextureM.SetTexture(self, a, g, b, al)
   if a == nil then
      self.__texture, self.__color = nil, nil
      return
   end
   if type(a) == "number" then
      U.num(a, 1, "SetTexture") U.num(g, 2, "SetTexture") U.num(b, 3, "SetTexture")
      if al ~= nil then U.num(al, 4, "SetTexture") end
      self.__texture, self.__color = nil, { a, g, b, al or 1 }
      return
   end
   if type(a) ~= "string" then U.badArg(1, "SetTexture", "string", a) end
   self.__texture, self.__color = a, nil
   U.checkAsset(a, "texture")
end
function TextureM.GetTexture(self) return self.__texture end

function TextureM.SetTexCoord(self, ...)
   local n = select("#", ...)
   local a = { ... }
   if n ~= 4 and n ~= 8 then error("SetTexCoord(): expected 4 or 8 numbers, got " .. n, 2) end
   for i = 1, n do U.num(a[i], i, "SetTexCoord") end
   if n == 4 then
      local l, r, t, b = a[1], a[2], a[3], a[4]
      self.__texcoord = { l, t, l, b, r, t, r, b }
   else
      self.__texcoord = a
   end
end
function TextureM.GetTexCoord(self)
   local c = self.__texcoord or { 0, 0, 0, 1, 1, 0, 1, 1 }
   return unpack(c, 1, 8)
end

function TextureM.SetVertexColor(self, r, g, b, a)
   self.__vertex = colorArgs("SetVertexColor", r, g, b, a)
end
function TextureM.SetBlendMode(self, mode)
   if type(mode) ~= "string" or not BLEND[mode] then
      error("SetBlendMode(): invalid blend mode " .. tostring(mode), 2)
   end
   self.__blend = mode
end
function TextureM.SetDesaturated(self, flag)
   self.__desaturated = flag and true or false
   return 1
end
function TextureM.SetGradient(self, orientation, r1, g1, b1, r2, g2, b2)
   if orientation ~= "HORIZONTAL" and orientation ~= "VERTICAL" then
      error("SetGradient(): orientation must be HORIZONTAL or VERTICAL", 2)
   end
   U.num(r1, 2, "SetGradient") U.num(g1, 3, "SetGradient") U.num(b1, 4, "SetGradient")
   U.num(r2, 5, "SetGradient") U.num(g2, 6, "SetGradient") U.num(b2, 7, "SetGradient")
   self.__gradient = { orientation, r1, g1, b1, 1, r2, g2, b2, 1 }
end
function TextureM.SetGradientAlpha(self, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
   if orientation ~= "HORIZONTAL" and orientation ~= "VERTICAL" then
      error("SetGradientAlpha(): orientation must be HORIZONTAL or VERTICAL", 2)
   end
   U.num(r1, 2, "SetGradientAlpha") U.num(g1, 3, "SetGradientAlpha") U.num(b1, 4, "SetGradientAlpha")
   U.num(a1, 5, "SetGradientAlpha") U.num(r2, 6, "SetGradientAlpha") U.num(g2, 7, "SetGradientAlpha")
   U.num(b2, 8, "SetGradientAlpha") U.num(a2, 9, "SetGradientAlpha")
   self.__gradient = { orientation, r1, g1, b1, a1, r2, g2, b2, a2 }
end
function TextureM.SetRotation(self, rad)
   U.num(rad, 1, "SetRotation")
   self.__rotation = rad
end

-- DrawLayer: fuer Texture und FontString
local function setDrawLayer(self, layer, sub)
   if type(layer) ~= "string" or not LAYERS[layer] then
      error("SetDrawLayer(): invalid draw layer " .. tostring(layer), 3)
   end
   if sub ~= nil then U.num(sub, 2, "SetDrawLayer") end
   self.__layer, self.__sub = layer, sub or 0
end
function TextureM.SetDrawLayer(self, layer, sub) setDrawLayer(self, layer, sub) end
function TextureM.GetDrawLayer(self) return self.__layer, self.__sub end
function FontStringM.SetDrawLayer(self, layer, sub) setDrawLayer(self, layer, sub) end
function FontStringM.GetDrawLayer(self) return self.__layer, self.__sub end

-- ---- Schriftobjekte ---------------------------------------------------------

-- Prueft SetFont-Argumente; Latin-only-Schriften in nicht-lateinischen Clients sind ein Fehler
function U.checkFont(path, size, flags, fname)
   U.str(path, 1, fname)
   U.num(size, 2, fname)
   if size <= 0 then error(fname .. "(): font size must be positive", 3) end
   if flags ~= nil then
      if type(flags) ~= "string" then U.badArg(3, fname, "string", flags) end
      for token in flags:gmatch("[^,%s]+") do
         if token ~= "OUTLINE" and token ~= "THICKOUTLINE" and token ~= "MONOCHROME" then
            error(fname .. "(): invalid font flag '" .. token .. "'", 3)
         end
      end
   end
   if NON_LATIN_LOCALES[M.world.locale] and LATIN_ONLY_FONTS[slower(path)] then
      error(fname .. "(): hard-coded Latin-only font '" .. path .. "' in client locale " .. M.world.locale
         .. " (use STANDARD_TEXT_FONT or the GetFont() of a font object)", 3)
   end
end

-- Schriftobjekt (Font) aufloesen: Objekt oder Name
function U.resolveFont(obj, fname)
   if type(obj) == "string" then
      local f = S.fonts[obj]
      if not f then error(fname .. "(): unknown font object '" .. obj .. "'", 3) end
      return f
   end
   if U.typeOf(obj) == "Font" then return obj end
   error(fname .. "(): expected a font object, got " .. type(obj), 3)
end

function U.newFont(name, path, size, flags, r, g, b)
   local f = setmetatable({}, META.Font)
   S.nextId = S.nextId + 1
   f.__id = S.nextId
   f.__type = "Font"
   f.__name = name
   f.__font = { path = path, size = size, flags = flags }
   f.__color = { r or 1, g or 1, b or 1, 1 }
   f.__justifyH, f.__justifyV = "CENTER", "MIDDLE"
   if name then
      S.fonts[name] = f
      rawset(_G, name, f)
   end
   return f
end

function U.currentFont(o)
   if o.__font then return o.__font end
   if o.__fontObject then return U.currentFont(o.__fontObject) end
   return nil
end

-- gemeinsame Methoden von FontString, EditBox (Teil) und Font
local function fontSetFont(self, path, size, flags)
   U.checkFont(path, size, flags, "SetFont")
   self.__font = { path = path, size = size, flags = flags }
   return 1
end
local function fontGetFont(self)
   local f = U.currentFont(self)
   if not f then return nil end
   return f.path, f.size, f.flags
end
local function fontSetObject(self, obj)
   self.__fontObject = U.resolveFont(obj, "SetFontObject")
   self.__font = nil
end
local function fontSetColor(self, r, g, b, a)
   self.__color = colorArgs("SetTextColor", r, g, b, a)
end
local function fontGetColor(self)
   local c = self.__color or { 1, 1, 1, 1 }
   return c[1], c[2], c[3], c[4]
end
local function justifyH(self, v)
   if v ~= "LEFT" and v ~= "CENTER" and v ~= "RIGHT" then
      error("SetJustifyH(): invalid value " .. tostring(v), 3)
   end
   self.__justifyH = v
end
local function justifyV(self, v)
   if v ~= "TOP" and v ~= "MIDDLE" and v ~= "BOTTOM" then
      error("SetJustifyV(): invalid value " .. tostring(v), 3)
   end
   self.__justifyV = v
end
local function shadowColor(self, r, g, b, a) self.__shadowColor = colorArgs("SetShadowColor", r, g, b, a) end
local function shadowOffset(self, x, y)
   U.num(x, 1, "SetShadowOffset") U.num(y, 2, "SetShadowOffset")
   self.__shadowOffset = { x, y }
end
local function setSpacing(self, n)
   U.num(n, 1, "SetSpacing")
   self.__spacing = n
end

-- ---- FontString -------------------------------------------------------------

function FontStringM.SetText(self, text)
   if not (self.__font or self.__fontObject) then error("Font not set", 2) end
   if text == nil then
      text = ""
   elseif type(text) == "number" then
      text = tostring(text)
   elseif type(text) ~= "string" then
      U.badArg(1, "SetText", "string", text)
   end
   self.__text = text
end
function FontStringM.GetText(self) return self.__text end
FontStringM.SetFont = fontSetFont
FontStringM.GetFont = fontGetFont
FontStringM.SetFontObject = fontSetObject
function FontStringM.GetFontObject(self) return self.__fontObject end
FontStringM.SetTextColor = fontSetColor
FontStringM.GetTextColor = fontGetColor
function FontStringM.SetJustifyH(self, v) justifyH(self, v) end
function FontStringM.SetJustifyV(self, v) justifyV(self, v) end
function FontStringM.SetShadowColor(self, ...) shadowColor(self, ...) end
function FontStringM.SetShadowOffset(self, x, y) shadowOffset(self, x, y) end
function FontStringM.SetSpacing(self, n) setSpacing(self, n) end
function FontStringM.SetTextHeight(self, h)
   U.num(h, 1, "SetTextHeight")
   if h <= 0 then error("SetTextHeight(): height must be positive", 2) end
   local f = U.currentFont(self)
   if not f then error("Font not set", 2) end
   self.__font = { path = f.path, size = h, flags = f.flags }
end
function FontStringM.SetNonSpaceWrap(self, flag) self.__nonSpaceWrap = flag and true or false end
function FontStringM.SetIndentedWordWrap(self, flag) self.__indentedWrap = flag and true or false end
function FontStringM.GetStringWidth(self)
   local w = U.textWidth(self)
   local explicit = self.__width
   if explicit and explicit > 0 and w > explicit then return explicit end
   return w
end
function FontStringM.GetStringHeight(self)
   local size = U.fontSize(self)
   local ew = self.__width
   local n = 0
   for _, line in ipairs(U.textLines(self)) do
      if ew and ew > 0 then
         n = n + max(1, ceil(U.lineWidth(line, size) / ew))
      else
         n = n + 1
      end
   end
   return n * size
end

-- ---- Font (Schriftobjekt) ---------------------------------------------------

function FontM.GetName(self) return self.__name end
function FontM.GetObjectType(self) return "Font" end
FontM.SetFont = fontSetFont
FontM.GetFont = fontGetFont
FontM.SetTextColor = fontSetColor
FontM.GetTextColor = fontGetColor
function FontM.SetJustifyH(self, v) justifyH(self, v) end
function FontM.GetJustifyH(self) return self.__justifyH end
function FontM.SetJustifyV(self, v) justifyV(self, v) end
function FontM.GetJustifyV(self) return self.__justifyV end
function FontM.SetShadowColor(self, ...) shadowColor(self, ...) end
function FontM.SetShadowOffset(self, x, y) shadowOffset(self, x, y) end
function FontM.SetSpacing(self, n) setSpacing(self, n) end
function FontM.SetFontObject(self, obj)
   local f = U.resolveFont(obj, "SetFontObject")
   self.__font = { path = f.__font.path, size = f.__font.size, flags = f.__font.flags }
end

-- ---------------------------------------------------------------------------
-- Button / CheckButton
-- ---------------------------------------------------------------------------

-- Gibt dem Button (falls noetig) einen FontString (ohne Schrift)
function U.ensureButtonFontString(btn)
   local fs = btn.__fontString
   if not fs then
      fs = U.newRegion("FontString", nil, btn, "ARTWORK")
      btn.__fontString = fs
   end
   return fs
end

function ButtonM.SetText(self, text)
   local fs = self.__fontString
   if not fs or not (fs.__font or fs.__fontObject) then
      error("Font not set (Button has no font string/font object: use a template, SetNormalFontObject or SetFontString)", 2)
   end
   FontStringM.SetText(fs, text)
end
function ButtonM.GetText(self)
   local fs = self.__fontString
   return fs and fs.__text or nil
end
function ButtonM.GetFontString(self) return self.__fontString end
function ButtonM.SetFontString(self, fs)
   if U.typeOf(fs) ~= "FontString" then
      error("SetFontString(): expected a FontString, got " .. type(fs), 2)
   end
   if fs.__parent ~= self then RegionM.SetParent(fs, self) end
   self.__fontString = fs
end
function ButtonM.SetNormalFontObject(self, obj)
   local f = U.resolveFont(obj, "SetNormalFontObject")
   local fs = U.ensureButtonFontString(self)
   fs.__fontObject = f
   fs.__font = nil
   self.__normalFont = f
end
function ButtonM.SetHighlightFontObject(self, obj)
   self.__highlightFont = U.resolveFont(obj, "SetHighlightFontObject")
end
function ButtonM.SetDisabledFontObject(self, obj)
   self.__disabledFont = U.resolveFont(obj, "SetDisabledFontObject")
end

function ButtonM.Enable(self)
   if self.__enabled ~= false then return end
   self.__enabled = true
   U.runScript(self, "OnEnable")
end
function ButtonM.Disable(self)
   if self.__enabled == false then return end
   self.__enabled = false
   self.__downButton = nil     -- ein laufender Klick geht verloren (wie im Spiel)
   U.runScript(self, "OnDisable")
end
function ButtonM.IsEnabled(self) return self.__enabled ~= false and 1 or nil end

function ButtonM.RegisterForClicks(self, ...)
   local set = {}
   for i = 1, select("#", ...) do
      local t = select(i, ...)
      if type(t) ~= "string" or not CLICK_TOKENS[t] then
         error("RegisterForClicks(): invalid click type " .. tostring(t), 2)
      end
      if t == "AnyUp" then
         for _, b in ipairs({ "Left", "Right", "Middle", "Button4", "Button5" }) do
            set[(b == "Button4" or b == "Button5") and (b .. "Up") or (b .. "ButtonUp")] = true
         end
      elseif t == "AnyDown" then
         for _, b in ipairs({ "Left", "Right", "Middle", "Button4", "Button5" }) do
            set[(b == "Button4" or b == "Button5") and (b .. "Down") or (b .. "ButtonDown")] = true
         end
      else
         set[t] = true
      end
   end
   self.__clicks = set
end

-- Wirkung eines Klicks: CheckButton schaltet um, dann PreClick/OnClick/PostClick
function U.performClick(btn, button, down)
   if btn.__type == "CheckButton" then btn.__checked = not btn.__checked end
   U.runScript(btn, "PreClick", button, down)
   U.runScript(btn, "OnClick", button, down)
   U.runScript(btn, "PostClick", button, down)
end

function ButtonM.Click(self, button)
   if self.__enabled == false then return end
   U.performClick(self, button or "LeftButton", false)
end

function ButtonM.SetButtonState(self, state, lock)
   if state ~= "NORMAL" and state ~= "PUSHED" then
      error("SetButtonState(): state must be NORMAL or PUSHED", 2)
   end
   self.__buttonState = state
   self.__stateLocked = lock and true or false
end
function ButtonM.GetButtonState(self) return self.__buttonState or "NORMAL" end
function ButtonM.LockHighlight(self) self.__highlightLocked = true end
function ButtonM.UnlockHighlight(self) self.__highlightLocked = false end
function ButtonM.SetPushedTextOffset(self, x, y)
   U.num(x, 1, "SetPushedTextOffset") U.num(y, 2, "SetPushedTextOffset")
   self.__pushedOffset = { x, y }
end

-- Textur eines Buttons setzen (Pfad oder Texture-Objekt)
function U.setButtonTexture(btn, key, tex, layer, blend)
   if tex == nil then
      btn[key] = nil
      return
   end
   if type(tex) == "string" then
      local t = rawget(btn, key)
      if not t then
         t = U.newRegion("Texture", nil, btn, layer)
         btn[key] = t
      end
      TextureM.SetTexture(t, tex)
      if blend then t.__blend = blend end
   elseif U.typeOf(tex) == "Texture" then
      if tex.__parent ~= btn then RegionM.SetParent(tex, btn) end
      btn[key] = tex
      if blend then tex.__blend = blend end
   else
      error("expected a texture path or Texture object, got " .. type(tex), 3)
   end
end
function ButtonM.SetNormalTexture(self, tex) U.setButtonTexture(self, "__normalTex", tex, "ARTWORK") end
function ButtonM.GetNormalTexture(self) return self.__normalTex end
function ButtonM.SetPushedTexture(self, tex) U.setButtonTexture(self, "__pushedTex", tex, "ARTWORK") end
function ButtonM.GetPushedTexture(self) return self.__pushedTex end
function ButtonM.SetHighlightTexture(self, tex, blend)
   if blend ~= nil and (type(blend) ~= "string" or not BLEND[blend]) then
      error("SetHighlightTexture(): invalid blend mode " .. tostring(blend), 2)
   end
   U.setButtonTexture(self, "__highlightTex", tex, "HIGHLIGHT", blend or "ADD")
end
function ButtonM.GetHighlightTexture(self) return self.__highlightTex end
function ButtonM.SetDisabledTexture(self, tex) U.setButtonTexture(self, "__disabledTex", tex, "ARTWORK") end
function ButtonM.GetDisabledTexture(self) return self.__disabledTex end

function CheckButtonM.SetChecked(self, flag) self.__checked = flag and true or false end
function CheckButtonM.GetChecked(self) return self.__checked and 1 or nil end
function CheckButtonM.SetCheckedTexture(self, tex) U.setButtonTexture(self, "__checkedTex", tex, "ARTWORK") end
function CheckButtonM.GetCheckedTexture(self) return self.__checkedTex end
function CheckButtonM.SetDisabledCheckedTexture(self, tex)
   U.setButtonTexture(self, "__disabledCheckedTex", tex, "ARTWORK")
end

-- ---------------------------------------------------------------------------
-- EditBox
-- ---------------------------------------------------------------------------

-- Anzahl der UTF-8-Zeichen und Abschneiden auf n Zeichen
local function utf8Length(s)
   local n = 0
   for i = 1, #s do
      local b = sbyte(s, i)
      if b < 0x80 or b >= 0xC0 then n = n + 1 end
   end
   return n
end
local function utf8Truncate(s, n)
   local count = 0
   for i = 1, #s do
      local b = sbyte(s, i)
      if b < 0x80 or b >= 0xC0 then
         count = count + 1
         if count > n then return ssub(s, 1, i - 1) end
      end
   end
   return s
end

function EditBoxM.SetText(self, text)
   if not (self.__font or self.__fontObject) then error("Font not set", 2) end
   if text == nil then
      text = ""
   elseif type(text) == "number" then
      text = tostring(text)
   elseif type(text) ~= "string" then
      U.badArg(1, "SetText", "string", text)
   end
   local max_ = self.__maxLetters or 0
   if max_ > 0 and utf8Length(text) > max_ then text = utf8Truncate(text, max_) end
   local changed = (text ~= self.__text)
   self.__text = text
   self.__cursor = utf8Length(text)
   U.runScript(self, "OnTextSet")
   if changed then U.runScript(self, "OnTextChanged", false) end
end
function EditBoxM.GetText(self) return self.__text end
EditBoxM.SetFont = fontSetFont
EditBoxM.SetFontObject = fontSetObject
EditBoxM.SetTextColor = fontSetColor
function EditBoxM.SetJustifyH(self, v) justifyH(self, v) end
function EditBoxM.SetMaxLetters(self, n)
   U.num(n, 1, "SetMaxLetters")
   self.__maxLetters = n
end
function EditBoxM.SetNumeric(self, flag) self.__numeric = flag and true or false end
function EditBoxM.SetAutoFocus(self, flag) self.__autoFocus = flag and true or false end
function EditBoxM.SetFocus(self) U.setFocus(self) end
function EditBoxM.ClearFocus(self) U.clearFocus(self) end
function EditBoxM.HasFocus(self) return S.focus == self and 1 or nil end
function EditBoxM.HighlightText(self, s, e)
   if s ~= nil then U.num(s, 1, "HighlightText") end
   if e ~= nil then U.num(e, 2, "HighlightText") end
   self.__highlight = { s or 0, e or -1 }
end
function EditBoxM.Insert(self, text)
   U.str(text, 1, "Insert")
   local cur = self.__cursor or utf8Length(self.__text)
   local s = self.__text
   local before = utf8Truncate(s, cur)
   local new = before .. text .. ssub(s, #before + 1)
   local max_ = self.__maxLetters or 0
   if max_ > 0 and utf8Length(new) > max_ then new = utf8Truncate(new, max_) end
   if new ~= s then
      self.__text = new
      self.__cursor = cur + utf8Length(text)
      U.runScript(self, "OnTextChanged", false)
   end
end
function EditBoxM.SetMultiLine(self, flag) self.__multiLine = flag and true or false end
function EditBoxM.SetTextInsets(self, l, r, t, b)
   U.num(l, 1, "SetTextInsets") U.num(r, 2, "SetTextInsets")
   U.num(t, 3, "SetTextInsets") U.num(b, 4, "SetTextInsets")
   self.__textInsets = { l, r, t, b }
end
function EditBoxM.GetNumber(self) return tonumber(self.__text) or 0 end
function EditBoxM.SetCursorPosition(self, n)
   U.num(n, 1, "SetCursorPosition")
   self.__cursor = n
end
function EditBoxM.GetCursorPosition(self) return self.__cursor or 0 end
function EditBoxM.AddHistoryLine(self, text)
   U.str(text, 1, "AddHistoryLine")
   self.__history = self.__history or {}
   self.__history[#self.__history + 1] = text
end
function EditBoxM.SetPassword(self, flag) self.__password = flag and true or false end
function EditBoxM.SetBlinkSpeed(self, n)
   U.num(n, 1, "SetBlinkSpeed")
   self.__blinkSpeed = n
end

-- ---------------------------------------------------------------------------
-- Slider / StatusBar
-- ---------------------------------------------------------------------------

local function clampValue(v, lo, hi)
   if v < lo then return lo end
   if v > hi then return hi end
   return v
end

function SliderM.SetMinMaxValues(self, lo, hi)
   U.num(lo, 1, "SetMinMaxValues") U.num(hi, 2, "SetMinMaxValues")
   if lo > hi then error("SetMinMaxValues(): min (" .. lo .. ") is greater than max (" .. hi .. ")", 2) end
   self.__min, self.__max = lo, hi
   U.runScript(self, "OnMinMaxChanged", lo, hi)
   local v = clampValue(self.__value, lo, hi)
   if v ~= self.__value then
      self.__value = v
      U.runScript(self, "OnValueChanged", v)
   end
end
function SliderM.GetMinMaxValues(self) return self.__min, self.__max end
function SliderM.SetValue(self, v)
   U.num(v, 1, "SetValue")
   local lo, hi, step = self.__min, self.__max, self.__step or 0
   v = clampValue(v, lo, hi)
   if step > 0 then
      v = lo + floor((v - lo) / step + 0.5) * step
      v = clampValue(v, lo, hi)
   end
   if v ~= self.__value then
      self.__value = v
      U.runScript(self, "OnValueChanged", v)
   end
end
function SliderM.GetValue(self) return self.__value end
function SliderM.SetValueStep(self, s)
   U.num(s, 1, "SetValueStep")
   if s < 0 then error("SetValueStep(): negative step", 2) end
   self.__step = s
end
function SliderM.GetValueStep(self) return self.__step or 0 end
function SliderM.SetOrientation(self, o)
   if o ~= "HORIZONTAL" and o ~= "VERTICAL" then
      error("SetOrientation(): must be HORIZONTAL or VERTICAL", 2)
   end
   self.__orientation = o
end
function SliderM.SetThumbTexture(self, tex) U.setButtonTexture(self, "__thumbTex", tex, "ARTWORK") end
function SliderM.GetThumbTexture(self) return self.__thumbTex end
function SliderM.Enable(self)
   if self.__enabled ~= false then return end
   self.__enabled = true
   U.runScript(self, "OnEnable")
end
function SliderM.Disable(self)
   if self.__enabled == false then return end
   self.__enabled = false
   U.runScript(self, "OnDisable")
end
function SliderM.IsEnabled(self) return self.__enabled ~= false and 1 or nil end

function StatusBarM.SetStatusBarTexture(self, tex) U.setButtonTexture(self, "__barTex", tex, "ARTWORK") end
function StatusBarM.GetStatusBarTexture(self) return self.__barTex end
function StatusBarM.SetStatusBarColor(self, r, g, b, a)
   self.__barColor = colorArgs("SetStatusBarColor", r, g, b, a)
end
function StatusBarM.GetStatusBarColor(self)
   local c = self.__barColor or { 1, 1, 1, 1 }
   return c[1], c[2], c[3], c[4]
end
function StatusBarM.SetMinMaxValues(self, lo, hi)
   U.num(lo, 1, "SetMinMaxValues") U.num(hi, 2, "SetMinMaxValues")
   if lo > hi then error("SetMinMaxValues(): min is greater than max", 2) end
   self.__min, self.__max = lo, hi
   U.runScript(self, "OnMinMaxChanged", lo, hi)
   local v = clampValue(self.__value, lo, hi)
   if v ~= self.__value then
      self.__value = v
      U.runScript(self, "OnValueChanged", v)
   end
end
function StatusBarM.GetMinMaxValues(self) return self.__min, self.__max end
function StatusBarM.SetValue(self, v)
   U.num(v, 1, "SetValue")
   v = clampValue(v, self.__min, self.__max)
   if v ~= self.__value then
      self.__value = v
      U.runScript(self, "OnValueChanged", v)
   end
end
function StatusBarM.GetValue(self) return self.__value end
function StatusBarM.SetOrientation(self, o)
   if o ~= "HORIZONTAL" and o ~= "VERTICAL" then
      error("SetOrientation(): must be HORIZONTAL or VERTICAL", 2)
   end
   self.__orientation = o
end

-- ---------------------------------------------------------------------------
-- ScrollFrame
-- ---------------------------------------------------------------------------

function U.scrollRanges(sf)
   local child = sf.__scrollChild
   if not child then return 0, 0 end
   local xr = max(0, U.explicitWidth(child) - U.explicitWidth(sf))
   local yr = max(0, U.explicitHeight(child) - U.explicitHeight(sf))
   return xr, yr
end

function U.updateScrollRange(sf)
   local xr, yr = U.scrollRanges(sf)
   local last = sf.__lastRange
   if not last or last[1] ~= xr or last[2] ~= yr then
      sf.__lastRange = { xr, yr }
      U.runScript(sf, "OnScrollRangeChanged", xr, yr)
   end
end

function ScrollFrameM.SetScrollChild(self, child)
   if not U.isFrame(child) then error("SetScrollChild(): expected a frame", 2) end
   if child.__parent ~= self then RegionM.SetParent(child, self) end
   self.__scrollChild = child
   U.updateScrollRange(self)
end
function ScrollFrameM.GetScrollChild(self) return self.__scrollChild end
function ScrollFrameM.SetVerticalScroll(self, v)
   U.num(v, 1, "SetVerticalScroll")
   local old = self.__vscroll or 0
   self.__vscroll = v
   if v ~= old then U.runScript(self, "OnVerticalScroll", v) end
end
function ScrollFrameM.GetVerticalScroll(self) return self.__vscroll or 0 end
function ScrollFrameM.GetVerticalScrollRange(self)
   local _, yr = U.scrollRanges(self)
   return yr
end
function ScrollFrameM.SetHorizontalScroll(self, v)
   U.num(v, 1, "SetHorizontalScroll")
   local old = self.__hscroll or 0
   self.__hscroll = v
   if v ~= old then U.runScript(self, "OnHorizontalScroll", v) end
end
function ScrollFrameM.GetHorizontalScroll(self) return self.__hscroll or 0 end
function ScrollFrameM.GetHorizontalScrollRange(self)
   local xr = U.scrollRanges(self)
   return xr
end
function ScrollFrameM.UpdateScrollChildRect(self) U.updateScrollRange(self) end

-- ---------------------------------------------------------------------------
-- Modelle
-- ---------------------------------------------------------------------------

-- Eintraege von model.__calls sind reine Arrays { "TryOn", 12345 } (Methodenname, dann die
-- Argumente), damit H.deepEq(calls, { {"SetUnit","player"}, {"Undress"} }) funktioniert.
-- Zusaetzlich lesbar (nicht in pairs): entry.name/.method = Name, entry.args = Argumentliste,
-- entry.n = Anzahl der Argumente.
local CALL_MT = {
   __index = function(t, k)
      if k == "name" or k == "method" then return rawget(t, 1) end
      if k == "args" then return { unpack(t, 2) } end
      if k == "n" then return #t - 1 end
      return nil
   end,
}
function U.logCall(model, name, ...)
   local entry = setmetatable({ name, ... }, CALL_MT)
   model.__calls[#model.__calls + 1] = entry
end

function U.modelReset(m)
   m.__facing = 0
   m.__position = { 0, 0, 0 }
   m.__rotation = 0
   m.__tried = {}
   m.__undressed = false
end

function ModelM.SetModel(self, path)
   U.str(path, 1, "SetModel")
   U.logCall(self, "SetModel", path)
   self.__modelPath = path
   self.__unit = nil
   U.modelReset(self)
end
function ModelM.GetModel(self) return self.__modelPath end
function ModelM.SetModelScale(self, s)
   U.num(s, 1, "SetModelScale")
   if s <= 0 then error("SetModelScale(): scale must be greater than 0", 2) end
   U.logCall(self, "SetModelScale", s)
   self.__modelScale = s
end
function ModelM.GetModelScale(self) return self.__modelScale or 1 end
function ModelM.SetPosition(self, x, y, z)
   U.num(x, 1, "SetPosition") U.num(y, 2, "SetPosition") U.num(z, 3, "SetPosition")
   U.logCall(self, "SetPosition", x, y, z)
   self.__position = { x, y, z }
end
function ModelM.GetPosition(self)
   local p = self.__position
   return p[1], p[2], p[3]
end
function ModelM.SetFacing(self, r)
   U.num(r, 1, "SetFacing")
   U.logCall(self, "SetFacing", r)
   self.__facing = r
end
function ModelM.GetFacing(self) return self.__facing end
function ModelM.SetRotation(self, r)
   U.num(r, 1, "SetRotation")
   U.logCall(self, "SetRotation", r)
   self.__rotation = r
end
function ModelM.SetCamera(self, i)
   U.num(i, 1, "SetCamera")
   U.logCall(self, "SetCamera", i)
end
function ModelM.SetLight(self, ...)
   U.logCall(self, "SetLight", ...)
end
function ModelM.ClearModel(self)
   U.logCall(self, "ClearModel")
   self.__unit, self.__modelPath = nil, nil
   U.modelReset(self)
end
function ModelM.SetSequence(self, n)
   U.num(n, 1, "SetSequence")
   U.logCall(self, "SetSequence", n)
end
function ModelM.SetSequenceTime(self, a, b)
   U.num(a, 1, "SetSequenceTime") U.num(b, 2, "SetSequenceTime")
   U.logCall(self, "SetSequenceTime", a, b)
end

function PlayerModelM.SetUnit(self, unit)
   U.str(unit, 1, "SetUnit")
   U.logCall(self, "SetUnit", unit)
   self.__unit = unit
   self.__modelPath = nil
   U.modelReset(self)
end
function PlayerModelM.SetCreature(self, id)
   U.num(id, 1, "SetCreature")
   U.logCall(self, "SetCreature", id)
   self.__unit, self.__modelPath = nil, nil
   self.__creature = id
   U.modelReset(self)
end

function DressUpModelM.TryOn(self, item)
   if type(item) ~= "number" and type(item) ~= "string" then U.badArg(1, "TryOn", "number or string", item) end
   if not self.__unit and not self.__modelPath and not self.__creature then
      error("DressUpModel:TryOn(): no model loaded (call SetUnit first)", 2)
   end
   U.logCall(self, "TryOn", item)
   self.__tried[#self.__tried + 1] = item
end
function DressUpModelM.Dress(self)
   U.logCall(self, "Dress")
   self.__tried = {}
   self.__undressed = false
end
function DressUpModelM.Undress(self)
   U.logCall(self, "Undress")
   self.__tried = {}
   self.__undressed = true
end
-- UndressSlot gibt es nur, wenn M.world.hasUndressSlot gesetzt ist (siehe buildMeta)
function DressUpModelM.UndressSlot(self, slotId)
   U.num(slotId, 1, "UndressSlot")
   U.logCall(self, "UndressSlot", slotId)
   self.__undressedSlots = self.__undressedSlots or {}
   self.__undressedSlots[slotId] = true
end

-- ---------------------------------------------------------------------------
-- Item-Daten, Cache und Links
-- ---------------------------------------------------------------------------

-- Gegenstandsdaten mit Rueckfall fuer unbekannte IDs (z.B. angelegt, aber nicht in M.items)
function U.itemData(id)
   local it = M.items[id]
   if it then return it end
   return { name = "Item " .. tostring(id), quality = 1 }
end

function U.itemLink(id)
   local it = U.itemData(id)
   local q = it.quality or 1
   return sfmt("|cff%s|Hitem:%d:0:0:0:0:0:0:0:0|h[%s]|h|r", QUALITY_HEX[q] or "ffffff", id, it.name or ("Item " .. id))
end

-- Item-ID aus Zahl, "item:123", Link; sonst nil
function U.itemIdFromAny(v)
   if type(v) == "number" then return v end
   if type(v) == "string" then
      local n = smatch(v, "item:(%d+)")
      if n then return tonumber(n) end
      return tonumber(v)
   end
   return nil
end

function U.equipped(id)
   if M.world.equipmentCached == false then return false end
   for _, v in pairs(M.world.equipment) do
      if v == id then return true end
   end
   return false
end

-- Ist der Gegenstand im Client-Cache? (Abfragen laufen nach itemCacheDelay Sekunden ein)
function U.itemCached(id)
   if not M.items[id] then return false end
   if S.cached[id] then return true end
   local due = S.pending[id]
   if due and M.now >= due then
      S.pending[id] = nil
      S.cached[id] = true
      return true
   end
   if U.equipped(id) then return true end
   return false
end

-- Eine Abfrage (SetHyperlink) zaehlt und stoesst das Einlaufen in den Cache an
function U.queryItem(id)
   M.itemQueries[id] = (M.itemQueries[id] or 0) + 1
   if M.items[id] and not S.cached[id] and not S.pending[id] then
      S.pending[id] = M.now + (M.world.itemCacheDelay or 0.3)
   end
end

function M.CacheItem(id)
   if M.items[id] then
      S.cached[id] = true
      S.pending[id] = nil
      return true
   end
   return false
end
function M.CacheAll()
   for id in pairs(M.items) do
      S.cached[id] = true
      S.pending[id] = nil
   end
end
function M.UncacheItem(id)
   S.cached[id] = nil
   S.pending[id] = nil
end
function M.IsCached(id) return U.itemCached(id) end

-- ---------------------------------------------------------------------------
-- GameTooltip
-- ---------------------------------------------------------------------------

local TIP_ANCHORS = toSet({
   "ANCHOR_NONE", "ANCHOR_RIGHT", "ANCHOR_LEFT", "ANCHOR_TOP", "ANCHOR_BOTTOM", "ANCHOR_TOPRIGHT",
   "ANCHOR_TOPLEFT", "ANCHOR_BOTTOMRIGHT", "ANCHOR_BOTTOMLEFT", "ANCHOR_CURSOR", "ANCHOR_PRESERVE",
})
local LINK_KINDS = toSet({ "item", "spell", "quest", "achievement", "enchant", "talent", "trade", "glyph",
                           "unit", "instancelock", "currency", "player", "channel", "raid", "battlepet" })

function U.childName(o, suffix)
   if o.__name then return o.__name .. suffix end
   return nil
end

-- Stellt sicher, dass die FontStrings fuer Zeile 1..n existieren
function U.tipEnsure(tip, n)
   tip.__fsL = tip.__fsL or {}
   tip.__fsR = tip.__fsR or {}
   while #tip.__fsL < n do
      local i = #tip.__fsL + 1
      local fl = U.newRegion("FontString", U.childName(tip, "TextLeft" .. i), tip, "ARTWORK")
      local fr = U.newRegion("FontString", U.childName(tip, "TextRight" .. i), tip, "ARTWORK")
      local font = S.fonts[i == 1 and "GameTooltipHeaderText" or "GameTooltipText"]
      fl.__fontObject, fr.__fontObject = font, font
      fl.__shown, fr.__shown = false, false
      fl.__justifyH, fr.__justifyH = "LEFT", "RIGHT"
      tip.__fsL[i], tip.__fsR[i] = fl, fr
   end
end

-- Zeilen in die FontStrings uebernehmen
function U.tipRefresh(tip)
   local n = #tip.__lines
   if n > 0 then U.tipEnsure(tip, n) end
   for i = 1, #tip.__fsL do
      local fl, fr = tip.__fsL[i], tip.__fsR[i]
      local line = tip.__lines[i]
      if line then
         fl.__text, fl.__shown = line.left, true
         fl.__color = { line.r or 1, line.g or 1, line.b or 1, 1 }
         if line.right ~= nil then
            fr.__text, fr.__shown = line.right, true
            fr.__color = { line.rr or 1, line.rg or 1, line.rb or 1, 1 }
         else
            fr.__text, fr.__shown = nil, false
         end
      else
         fl.__text, fl.__shown = nil, false
         fr.__text, fr.__shown = nil, false
      end
   end
end

function U.tipClear(tip)
   tip.__lines = {}
   tip.__item = nil
   U.tipRefresh(tip)
   U.runScript(tip, "OnTooltipCleared")
end

-- Fuellt den Tooltip mit den Zeilen eines (gecachten) Gegenstands
function U.tipFillItem(tip, id)
   local it = U.itemData(id)
   local c = QUALITY_RGB[it.quality or 1] or QUALITY_RGB[1]
   local lines = {}
   lines[1] = { left = it.name or ("Item " .. id), r = c[1], g = c[2], b = c[3] }
   if it.ilvl and it.ilvl > 0 then
      lines[#lines + 1] = { left = "Item Level " .. it.ilvl, r = 1, g = 0.82, b = 0 }
   end
   if it.equipLoc and it.equipLoc ~= "" then
      local gs = rawget(_G, it.equipLoc)
      lines[#lines + 1] = { left = (type(gs) == "string" and gs) or it.equipLoc, right = it.subclass,
                            r = 1, g = 1, b = 1, rr = 1, rg = 1, rb = 1 }
   elseif it.class and it.class ~= "" then
      lines[#lines + 1] = { left = it.class, r = 1, g = 1, b = 1 }
   end
   if it.minLevel and it.minLevel > 1 then
      lines[#lines + 1] = { left = "Requires Level " .. it.minLevel, r = 1, g = 1, b = 1 }
   end
   tip.__lines = lines
   tip.__item = { id = id, name = it.name, link = U.itemLink(id) }
   U.tipRefresh(tip)
   U.setShown(tip, true)
   U.runScript(tip, "OnTooltipSetItem")
end

function TooltipM.SetOwner(self, owner, anchor, x, y)
   if not U.isObject(owner) then
      error("SetOwner(): owner must be a frame, got " .. type(owner), 2)
   end
   if anchor ~= nil and (type(anchor) ~= "string" or not TIP_ANCHORS[anchor]) then
      error("SetOwner(): invalid anchor '" .. tostring(anchor) .. "'", 2)
   end
   if x ~= nil then U.num(x, 3, "SetOwner") end
   if y ~= nil then U.num(y, 4, "SetOwner") end
   self.__owner = owner
   self.__anchorType = anchor or "ANCHOR_RIGHT"
   U.tipClear(self)
end
function TooltipM.GetOwner(self) return self.__owner end
function TooltipM.IsOwned(self, frame)
   if frame ~= nil and self.__owner == frame then return 1 end
   return nil
end

function TooltipM.ClearLines(self) U.tipClear(self) end
function TooltipM.NumLines(self) return #self.__lines end

function TooltipM.SetText(self, text, r, g, b, a, wrap)
   if text ~= nil and type(text) ~= "string" and type(text) ~= "number" then
      U.badArg(1, "SetText", "string", text)
   end
   if not self.__owner then
      U.warn("GameTooltip:SetText without SetOwner")
   end
   U.tipClear(self)
   self.__lines[1] = { left = tostring(text or ""), r = r, g = g, b = b, wrap = wrap }
   U.tipRefresh(self)
end
function TooltipM.AddLine(self, text, r, g, b, wrap)
   if type(text) ~= "string" and type(text) ~= "number" then U.badArg(1, "AddLine", "string", text) end
   self.__lines[#self.__lines + 1] = { left = tostring(text), r = r, g = g, b = b, wrap = wrap }
   U.tipRefresh(self)
end
function TooltipM.AddDoubleLine(self, left, right, lr, lg, lb, rr, rg, rb)
   if type(left) ~= "string" and type(left) ~= "number" then U.badArg(1, "AddDoubleLine", "string", left) end
   if type(right) ~= "string" and type(right) ~= "number" then U.badArg(2, "AddDoubleLine", "string", right) end
   self.__lines[#self.__lines + 1] = { left = tostring(left), right = tostring(right),
                                       r = lr, g = lg, b = lb, rr = rr, rg = rg, rb = rb }
   U.tipRefresh(self)
end

function TooltipM.SetHyperlink(self, link)
   U.str(link, 1, "SetHyperlink")
   local kind = smatch(link, "|H(%a+):") or smatch(link, "^(%a+):")
   if not kind or not LINK_KINDS[kind] then
      error("SetHyperlink(): unknown link type in '" .. link .. "'", 2)
   end
   local id = (kind == "item") and tonumber(smatch(link, "item:(%d+)")) or nil
   if kind == "item" and not id then
      error("SetHyperlink(): item link without item id: '" .. link .. "'", 2)
   end
   if not self.__owner then
      -- ohne SetOwner bleibt der Tooltip im Client leer (bekannte Falle) -> hier ein Fehler
      error("GameTooltip:SetHyperlink(): the tooltip has no owner (call SetOwner first; the real client "
         .. "leaves it empty and the item is never queried): " .. link, 2)
   end
   U.tipClear(self)
   if id then
      U.queryItem(id)
      if U.itemCached(id) then U.tipFillItem(self, id) end
   else
      local name = smatch(link, "|h%[(.-)%]|h")
      self.__lines[1] = { left = name or link, r = 1, g = 1, b = 1 }
      U.tipRefresh(self)
      U.setShown(self, true)
   end
end

-- gemeinsame Ausgabe fuer SetInventoryItem/SetBagItem
local function tipSetEquipped(self, id, fname)
   if not self.__owner then
      error("GameTooltip:" .. fname .. "(): the tooltip has no owner (call SetOwner first; the real client "
         .. "leaves it empty)", 3)
   end
   U.tipClear(self)
   if not id then return nil end
   U.tipFillItem(self, id)
   return 1, nil, 0
end
function TooltipM.SetInventoryItem(self, unit, slot)
   U.str(unit, 1, "SetInventoryItem")
   U.num(slot, 2, "SetInventoryItem")
   local id = nil
   if unit == "player" then id = M.world.equipment[slot] end
   return tipSetEquipped(self, id, "SetInventoryItem")
end
function TooltipM.SetBagItem(self, bag, slot)
   U.num(bag, 1, "SetBagItem")
   U.num(slot, 2, "SetBagItem")
   local b = M.world.bags[bag]
   return tipSetEquipped(self, b and b[slot] or nil, "SetBagItem")
end
function TooltipM.GetItem(self)
   local it = self.__item
   if it then return it.name, it.link end
   return nil
end
function TooltipM.GetUnit(self) return nil end
function TooltipM.FadeOut(self) U.setShown(self, false) end

-- ---------------------------------------------------------------------------
-- Chatfenster (ScrollingMessageFrame, nur fuer DEFAULT_CHAT_FRAME)
-- ---------------------------------------------------------------------------

function MsgFrameM.AddMessage(self, text, r, g, b, id)
   M.messages[#M.messages + 1] = tostring(text)
end
function MsgFrameM.Clear(self) end
function MsgFrameM.GetNumMessages(self) return #M.messages end

-- ---------------------------------------------------------------------------
-- Metatabellen
-- ---------------------------------------------------------------------------

local function flat(...)
   local t = {}
   for i = 1, select("#", ...) do
      for k, v in pairs((select(i, ...))) do t[k] = v end
   end
   return t
end

local function makeMeta(typeName, methods)
   local mt = {}
   mt.__index = function(t, k)
      local m = methods[k]
      if m ~= nil then
         if k == "UndressSlot" and not M.world.hasUndressSlot then return nil end
         return m
      end
      if type(k) == "string" and sfind(k, "^%u") and M.world.strictApi ~= false and not S.allowedFields[k] then
         error("API not in 3.3.5a: " .. typeName .. ":" .. k, 2)
      end
      return nil
   end
   mt.__tostring = function(t)
      return typeName .. ": 0x" .. sfmt("%08X", 0x20000000 + (rawget(t, "__id") or 0) * 16)
   end
   return mt
end

do
   local m = {}
   m.Texture = flat(RegionM, TextureM)
   m.FontString = flat(RegionM, FontStringM)
   m.Frame = flat(RegionM, FrameM)
   m.Button = flat(m.Frame, ButtonM)
   m.CheckButton = flat(m.Button, CheckButtonM)
   m.EditBox = flat(m.Frame, EditBoxM)
   m.Slider = flat(m.Frame, SliderM)
   m.StatusBar = flat(m.Frame, StatusBarM)
   m.ScrollFrame = flat(m.Frame, ScrollFrameM)
   m.Model = flat(m.Frame, ModelM)
   m.PlayerModel = flat(m.Model, PlayerModelM)
   m.DressUpModel = flat(m.PlayerModel, DressUpModelM)
   m.GameTooltip = flat(m.Frame, TooltipM)
   m.ScrollingMessageFrame = flat(m.Frame, MsgFrameM)
   m.Font = FontM
   for typeName, methods in pairs(m) do META[typeName] = makeMeta(typeName, methods) end
   M.methods = m   -- fuer Tests: M.methods.Frame.SetSize = fn erweitert die Attrappe bewusst
end

-- Tests duerfen bewusst Felder freigeben, die grossgeschrieben und noch nicht gesetzt sind
function M.AllowField(name) S.allowedFields[name] = true end

-- ---------------------------------------------------------------------------
-- Frames anlegen, Templates
-- ---------------------------------------------------------------------------

local CREATABLE = toSet({ "Frame", "Button", "CheckButton", "EditBox", "Slider", "StatusBar", "ScrollFrame",
                          "Model", "PlayerModel", "DressUpModel", "GameTooltip" })

-- Legt das nackte Frame-Objekt an (ohne Template, ohne Typ-Standardwerte)
function U.newFrame(typeName, name, parent)
   local o = setmetatable({}, META[typeName])
   S.nextId = S.nextId + 1
   o.__id = S.nextId
   o.__type = typeName
   o.__name = name
   o.__shown = true
   o.__alpha = 1
   o.__scale = 1
   o.__points = {}
   o.__children = {}
   o.__regions = {}
   o.__scripts = {}
   o.__hooks = {}
   o.__events = {}
   o.__attrs = {}
   o.__strata = parent and parent.__strata or "MEDIUM"
   o.__level = parent and (parent.__level + 1) or 0
   o.__mouse = MOUSE_DEFAULT[typeName] and true or false
   o.__mouseWheel = false
   o.__keyboard = false
   o.__movable, o.__resizable, o.__userPlaced, o.__clamped = false, false, false, false
   o.__parent = parent
   if parent then parent.__children[#parent.__children + 1] = o end
   if name then rawset(_G, name, o) end
   M.frames[#M.frames + 1] = o
   return o
end

-- Standardzustand je Typ
function U.initType(o, typeName)
   if U.isA(typeName, "Button") then
      o.__enabled = true
      o.__clicks = { LeftButtonUp = true }
      o.__buttonState = "NORMAL"
      o.__checked = false
   end
   if typeName == "EditBox" then
      o.__text, o.__cursor, o.__maxLetters = "", 0, 0
   elseif typeName == "Slider" then
      o.__min, o.__max, o.__value, o.__step = 0, 0, 0, 0
      o.__orientation = "HORIZONTAL"
      o.__enabled = true
   elseif typeName == "StatusBar" then
      o.__min, o.__max, o.__value = 0, 1, 0
      o.__orientation = "HORIZONTAL"
   elseif typeName == "ScrollFrame" then
      o.__vscroll, o.__hscroll = 0, 0
   elseif U.isA(typeName, "Model") then
      o.__calls = {}
      o.__modelScale = 1
      U.modelReset(o)
   elseif typeName == "GameTooltip" then
      o.__lines = {}
      o.__shown = false
      o.__strata = "TOOLTIP"
   end
end

-- Eingebaute Blizzard-Templates (nur der bewusst unterstuetzte Ausschnitt)
local TEMPLATES = {}

local function textFS(o, suffix, fontName)
   local fs = U.newRegion("FontString", U.childName(o, suffix), o, "ARTWORK")
   fs.__fontObject = S.fonts[fontName]
   return fs
end

TEMPLATES.GameTooltipTemplate = { kind = "GameTooltip", apply = function(o)
   o.__shown = false
   o.__strata = "TOOLTIP"
   o.__backdrop = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
                    edgeSize = 16, insets = { left = 5, right = 5, top = 5, bottom = 5 } }
   U.tipEnsure(o, 2)
end }

TEMPLATES.UIPanelButtonTemplate = { kind = "Button", apply = function(o)
   o.__width, o.__height = 40, 22
   local fs = textFS(o, "Text", "GameFontNormal")
   o.__fontString = fs
   o.__normalFont = S.fonts.GameFontNormal
   o.__highlightFont = S.fonts.GameFontHighlight
   o.__disabledFont = S.fonts.GameFontDisable
   for _, side in ipairs({ "Left", "Right", "Middle" }) do
      local t = U.newRegion("Texture", U.childName(o, side), o, "BACKGROUND")
      t.__texture = "Interface\\Buttons\\UI-Panel-Button-Up"
   end
   U.setButtonTexture(o, "__normalTex", "Interface\\Buttons\\UI-Panel-Button-Up", "ARTWORK")
   U.setButtonTexture(o, "__pushedTex", "Interface\\Buttons\\UI-Panel-Button-Down", "ARTWORK")
   U.setButtonTexture(o, "__disabledTex", "Interface\\Buttons\\UI-Panel-Button-Disabled", "ARTWORK")
   U.setButtonTexture(o, "__highlightTex", "Interface\\Buttons\\UI-Panel-Button-Highlight", "HIGHLIGHT", "ADD")
end }

TEMPLATES.UIPanelCloseButton = { kind = "Button", apply = function(o)
   o.__width, o.__height = 32, 32
   U.setButtonTexture(o, "__normalTex", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", "ARTWORK")
   U.setButtonTexture(o, "__pushedTex", "Interface\\Buttons\\UI-Panel-MinimizeButton-Down", "ARTWORK")
   U.setButtonTexture(o, "__highlightTex", "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "HIGHLIGHT", "ADD")
   o.__scripts.OnClick = function(self)
      local p = self.__parent
      if p then p:Hide() end
   end
end }

TEMPLATES.UICheckButtonTemplate = { kind = "CheckButton", apply = function(o)
   o.__width, o.__height = 32, 32
   local fs = textFS(o, "Text", "GameFontNormal")
   fs.__points = { { point = "LEFT", rel = o, relPoint = "RIGHT", x = 0, y = 1 } }
   o.__fontString = fs
   U.setButtonTexture(o, "__normalTex", "Interface\\Buttons\\UI-CheckBox-Up", "ARTWORK")
   U.setButtonTexture(o, "__pushedTex", "Interface\\Buttons\\UI-CheckBox-Down", "ARTWORK")
   U.setButtonTexture(o, "__highlightTex", "Interface\\Buttons\\UI-CheckBox-Highlight", "HIGHLIGHT", "ADD")
   U.setButtonTexture(o, "__checkedTex", "Interface\\Buttons\\UI-CheckBox-Check", "ARTWORK")
   U.setButtonTexture(o, "__disabledCheckedTex", "Interface\\Buttons\\UI-CheckBox-Check-Disabled", "ARTWORK")
end }

TEMPLATES.OptionsSliderTemplate = { kind = "Slider", apply = function(o)
   o.__width, o.__height = 144, 17
   o.__orientation = "HORIZONTAL"
   o.__mouse = true
   textFS(o, "Text", "GameFontNormal")
   textFS(o, "Low", "GameFontHighlightSmall")
   textFS(o, "High", "GameFontHighlightSmall")
   U.setButtonTexture(o, "__thumbTex", "Interface\\Buttons\\UI-SliderBar-Button-Horizontal", "ARTWORK")
end }

TEMPLATES.InputBoxTemplate = { kind = "EditBox", apply = function(o)
   o.__fontObject = S.fonts.ChatFontNormal
   o.__height = 20
   for _, side in ipairs({ "Left", "Right", "Middle" }) do
      local t = U.newRegion("Texture", U.childName(o, side), o, "BACKGROUND")
      t.__texture = "Interface\\Common\\Common-Input-Border"
   end
   o.__scripts.OnEscapePressed = function(self) self:ClearFocus() end
end }

TEMPLATES.UIPanelScrollFrameTemplate = { kind = "ScrollFrame", apply = function(o)
   if not o.__name then
      error("CreateFrame: UIPanelScrollFrameTemplate needs a NAMED frame (its OnLoad concatenates GetName() .. \"ScrollBar\")", 4)
   end
   local bar = U.newFrame("Slider", o.__name .. "ScrollBar", o)
   U.initType(bar, "Slider")
   bar.__width = 16
   bar.__orientation = "VERTICAL"
   local up = U.newFrame("Button", o.__name .. "ScrollBarScrollUpButton", bar)
   U.initType(up, "Button")
   up.__width, up.__height = 18, 16
   local down = U.newFrame("Button", o.__name .. "ScrollBarScrollDownButton", bar)
   U.initType(down, "Button")
   down.__width, down.__height = 18, 16
   local thumb = U.newRegion("Texture", o.__name .. "ScrollBarThumbTexture", bar, "OVERLAY")
   thumb.__texture = "Interface\\Buttons\\UI-ScrollBar-Knob"
   bar.__thumbTex = thumb
   bar.__scripts.OnValueChanged = function(self, value)
      o:SetVerticalScroll(value)
   end
   o.__scripts.OnVerticalScroll = function(self, offset)
      bar:SetValue(offset)
   end
   o.__scripts.OnScrollRangeChanged = function(self, xr, yr)
      bar:SetMinMaxValues(0, yr)
   end
   o.__mouseWheel = true
   o.__scripts.OnMouseWheel = function(self, delta)
      local _, hi = bar:GetMinMaxValues()
      bar:SetValue(max(0, min(hi, bar:GetValue() - delta * 20)))
   end
end }

-- Templates aus Transmog.xml (virtual="true"): Daten statt Funktion
function U.applyTemplate(o, t, seen)
   if t.apply then
      t.apply(o)
      return
   end
   seen = seen or {}
   if t.inherits then
      for base in t.inherits:gmatch("[^,%s]+") do
         if not seen[base] then
            seen[base] = true
            local bt = TEMPLATES[base] or S.templates[base]
            if bt then U.applyTemplate(o, bt, seen) end
         end
      end
   end
   if t.width then o.__width = t.width end
   if t.height then o.__height = t.height end
   if t.scale then
      if U.isA(o.__type, "Model") then o.__modelScale = t.scale else o.__scale = t.scale end
   end
   if t.enableMouse ~= nil then o.__mouse = t.enableMouse end
   if t.hidden then o.__shown = false end
end

local function templateKind(t)
   return t.kind
end

function U.createFrame(typeName, name, parent, template)
   if type(typeName) ~= "string" then U.badArg(1, "CreateFrame", "string", typeName) end
   if not CREATABLE[typeName] then
      error("CreateFrame: unknown frame type '" .. typeName .. "'", 3)
   end
   if name ~= nil and type(name) ~= "string" then U.badArg(2, "CreateFrame", "string", name) end
   if name == "" then name = nil end
   if name and rawget(_G, name) ~= nil then
      error("CreateFrame: Frame named '" .. name .. "' already exists", 3)
   end
   if parent ~= nil and not U.isFrame(parent) then
      error("CreateFrame: the parent must be a frame (or nil), got " .. type(parent), 3)
   end
   if template ~= nil and type(template) ~= "string" then U.badArg(4, "CreateFrame", "string", template) end

   -- Templates aufloesen, bevor etwas angelegt wird
   local list = {}
   if template then
      for t in template:gmatch("[^,%s]+") do
         local def = TEMPLATES[t] or S.templates[t]
         if not def then
            error("CreateFrame: unknown template '" .. t .. "' (neither a supported Blizzard template nor a"
               .. " virtual template declared in an XML file listed in the TOC)", 3)
         end
         local kind = templateKind(def)
         if kind and not U.isA(typeName, kind) then
            error("CreateFrame: template '" .. t .. "' is a " .. kind .. " template and cannot be used for a "
               .. typeName, 3)
         end
         list[#list + 1] = def
      end
   end

   local o = U.newFrame(typeName, name, parent)
   U.initType(o, typeName)
   for _, def in ipairs(list) do U.applyTemplate(o, def) end
   -- Ein sichtbarer EditBox mit AutoFocus holt sich im naechsten Frame den Tastaturfokus
   if typeName == "EditBox" then U.queueFocus(o) end
   return o
end

-- ---------------------------------------------------------------------------
-- Globale WoW-Funktionen (G); Install kopiert sie nach _G
-- ---------------------------------------------------------------------------

-- Lua-Aliase, die WoW als Globals bereitstellt
G.abs, G.acos, G.asin, G.atan, G.atan2 = math.abs, math.acos, math.asin, math.atan, math.atan2
G.ceil, G.cos, G.deg, G.exp, G.floor = math.ceil, math.cos, math.deg, math.exp, math.floor
G.frexp, G.ldexp, G.log, G.log10 = math.frexp, math.ldexp, math.log, math.log10
G.max, G.min, G.rad, G.random, G.randomseed = math.max, math.min, math.rad, math.random, math.randomseed
G.sin, G.sqrt, G.tan = math.sin, math.sqrt, math.tan
G.mod = math.fmod                       -- WoW: mod == math.fmod (Vorzeichen des Dividenden)
G.format, G.gmatch, G.gsub = string.format, string.gmatch, string.gsub
G.strbyte, G.strchar, G.strfind, G.strlen = string.byte, string.char, string.find, string.len
G.strlower, G.strmatch, G.strrep, G.strrev = string.lower, string.match, string.rep, string.reverse
G.strsub, G.strupper = string.sub, string.upper
G.tinsert, G.tremove = table.insert, table.remove
G.date, G.time = realOs.date, realOs.time

-- strsplit: die Trennzeichen sind EINZELNE Zeichen (Menge), nicht eine Zeichenkette
function G.strsplit(delim, str, pieces)
   U.str(delim, 1, "strsplit")
   if type(str) ~= "string" then U.badArg(2, "strsplit", "string", str) end
   if pieces ~= nil then U.num(pieces, 3, "strsplit") end
   local set = {}
   for i = 1, #delim do set[sbyte(delim, i)] = true end
   local out, start = {}, 1
   for i = 1, #str do
      if set[sbyte(str, i)] and not (pieces and #out >= pieces - 1) then
         out[#out + 1] = ssub(str, start, i - 1)
         start = i + 1
      end
   end
   out[#out + 1] = ssub(str, start)
   return unpack(out)
end

function G.strjoin(delim, ...)
   U.str(delim, 1, "strjoin")
   local t = {}
   for i = 1, select("#", ...) do
      local v = select(i, ...)
      if type(v) == "number" then
         v = tostring(v)
      elseif type(v) ~= "string" then
         U.badArg(i + 1, "strjoin", "string", v)
      end
      t[i] = v
   end
   return tconcat(t, delim)
end

function G.strconcat(...)
   return G.strjoin("", ...)
end

function G.strtrim(s, chars)
   U.str(s, 1, "strtrim")
   local set = {}
   if chars ~= nil then
      U.str(chars, 2, "strtrim")
      for i = 1, #chars do set[ssub(chars, i, i)] = true end
   else
      for _, c in ipairs({ " ", "\t", "\r", "\n", "\f", "\v" }) do set[c] = true end
   end
   local i, j = 1, #s
   while i <= j and set[ssub(s, i, i)] do i = i + 1 end
   while j >= i and set[ssub(s, j, j)] do j = j - 1 end
   return ssub(s, i, j)
end

function G.wipe(t)
   if type(t) ~= "table" then U.badArg(1, "wipe", "table", t) end
   for k in pairs(t) do t[k] = nil end
   return t
end

function G.getglobal(name) return rawget(_G, name) end
function G.setglobal(name, value) rawset(_G, name, value) end

-- Fehler-Handler, Hooks, Sicherheit
function G.geterrorhandler() return S.errorHandler end
function G.seterrorhandler(fn)
   if type(fn) ~= "function" then U.badArg(1, "seterrorhandler", "function", fn) end
   S.errorHandler = fn
end

local function pack(...) return { n = select("#", ...), ... } end

function G.hooksecurefunc(a, b, c)
   local tbl, name, hook
   if type(a) == "string" then
      tbl, name, hook = _G, a, b
   else
      tbl, name, hook = a, b, c
   end
   if type(tbl) ~= "table" then U.badArg(1, "hooksecurefunc", "table", a) end
   if type(name) ~= "string" then U.badArg(2, "hooksecurefunc", "string", name) end
   if type(hook) ~= "function" then U.badArg(3, "hooksecurefunc", "function", hook) end
   local orig = tbl[name]     -- bei Objekten: Klassenmethode (unbekannte API wirft hier)
   if type(orig) ~= "function" then
      error("hooksecurefunc(): attempt to hook a non-existing function '" .. name .. "'", 2)
   end
   rawset(tbl, name, function(...)
      local res = pack(orig(...))
      U.protected(hook, ...)
      return unpack(res, 1, res.n)
   end)
end

function G.securecall(fn, ...)
   if type(fn) == "string" then fn = rawget(_G, fn) end
   if type(fn) ~= "function" then U.badArg(1, "securecall", "function", fn) end
   local args = pack(...)
   local res
   local ok = xpcall(function() res = pack(fn(unpack(args, 1, args.n))) end, function(m)
      U.reportError(m, realDebug.traceback(tostring(m), 2))
   end)
   if ok and res then return unpack(res, 1, res.n) end
end

function G.issecurevariable() return true end
function G.InCombatLockdown() return M.world.combat and 1 or nil end
function G.debugstack() return realDebug.traceback("", 2) end
function G.debugprofilestart() S.profileStart = realOs.clock() end
function G.debugprofilestop() return (realOs.clock() - (S.profileStart or 0)) * 1000 end

-- Zeit
function G.GetTime()
   if S.lastTime and M.now < S.lastTime then
      error(sfmt("GetTime(): time went backwards (%.3f < %.3f); use M.Advance, never lower M.now", M.now, S.lastTime), 2)
   end
   S.lastTime = M.now
   return M.now
end
function G.GetFramerate() return 60 end
function G.GetGameTime()
   return tonumber(realOs.date("%H")), tonumber(realOs.date("%M"))
end

-- Umgebung
function G.GetLocale() return M.world.locale end
function G.GetRealmName() return M.world.realmName end
function G.GetBuildInfo() return "3.3.5", "12340", "Mar 15 2010", 30300 end
function G.IsLoggedIn() return M.world.loggedIn and 1 or nil end
function G.ReloadUI() M.reloads = M.reloads + 1 end
function G.GetScreenWidth() return M.world.screenWidth end
function G.GetScreenHeight() return M.world.screenHeight end
function G.GetCursorPosition() return M.world.cursor[1], M.world.cursor[2] end
function G.GetCVar(name) return M.world.cvars[name] end
function G.GetCVarBool(name)
   local v = M.world.cvars[name]
   return (v == "1" or v == 1) and 1 or nil
end
function G.SetCVar(name, value) M.world.cvars[name] = tostring(value) end
function G.GetAddOnMetadata(addon, field)
   local toc = M.toc
   if not toc or addon ~= toc.name then return nil end
   return toc.meta[field .. "-" .. M.world.locale] or toc.meta[field]
end
function G.IsAddOnLoaded(addon)
   if M.toc and M.toc.name == addon and M.toc.loaded then return 1 end
   return nil
end
function G.LoadAddOn() return nil, "MISSING" end
function G.GetNumAddOns() return 0 end

-- Eingabe
function G.IsShiftKeyDown() return M.world.shift and 1 or nil end
function G.IsControlKeyDown() return M.world.ctrl and 1 or nil end
function G.IsAltKeyDown() return M.world.alt and 1 or nil end
function G.IsModifierKeyDown()
   return (M.world.shift or M.world.ctrl or M.world.alt) and 1 or nil
end
function G.IsModifiedClick(action)
   U.str(action, 1, "IsModifiedClick")
   local o = M.world.modifiedClick[action]
   if o ~= nil then return o and 1 or nil end
   local w = M.world
   if action == "CHATLINK" or action == "SPLITSTACK" or action == "COMPAREITEMS" or action == "PICKUPACTION"
      or action == "OPENALLBAGS" or action == "QUESTWATCHTOGGLE" then
      return w.shift and 1 or nil
   elseif action == "DRESSUP" or action == "STICKYCAMERA" then
      return w.ctrl and 1 or nil
   elseif action == "SELFCAST" then
      return w.alt and 1 or nil
   end
   return nil
end
function G.IsMouseButtonDown(button)
   return M.world.mouseDown and M.world.mouseDown[button] and 1 or nil
end

-- Einheiten
local function unitKnown(unit)
   if unit == "player" then return true end
   local u = M.world.units[unit]
   return u ~= nil and u.exists ~= false
end
function G.UnitName(unit)
   if unit == "player" then return M.world.playerName, nil end
   local u = M.world.units[unit]
   if u and u.exists ~= false then return u.name, nil end
   return nil
end
function G.UnitExists(unit) return unitKnown(unit) and 1 or nil end
function G.UnitIsPlayer(unit)
   if unit == "player" then return 1 end
   local u = M.world.units[unit]
   return (u and u.isPlayer) and 1 or nil
end
function G.UnitIsUnit(a, b)
   if a == b then return unitKnown(a) and 1 or nil end
   local ua, ub = M.world.units[a], M.world.units[b]
   if ua and ub and ua.name and ua.name == ub.name then return 1 end
   if (a == "player" and ub and ub.name == M.world.playerName)
      or (b == "player" and ua and ua.name == M.world.playerName) then
      return 1
   end
   return nil
end
function G.UnitLevel(unit)
   if unit == "player" then return M.world.level end
   local u = M.world.units[unit]
   return u and u.level or nil
end
function G.UnitSex(unit)
   if unit == "player" then return M.world.sex end
   local u = M.world.units[unit]
   return u and u.sex or nil
end
function G.UnitGUID(unit)
   if unit == "player" then return "0x0000000000000001" end
   local u = M.world.units[unit]
   return u and u.guid or nil
end
function G.UnitIsDeadOrGhost(unit)
   if unit == "player" then return M.world.dead and 1 or nil end
   return nil
end
function G.UnitAffectingCombat(unit)
   if unit == "player" then return M.world.combat and 1 or nil end
   return nil
end
-- Rassen-/Klassenangaben des Tests auf das Client-Token abbilden ("night elf", "NightElf",
-- "Undead" ... -> "NightElf"/"Scourge"); unbekannte Werte bleiben unveraendert
local RACE_TOKENS = {
   human = "Human", orc = "Orc", dwarf = "Dwarf", nightelf = "NightElf", scourge = "Scourge",
   undead = "Scourge", tauren = "Tauren", gnome = "Gnome", troll = "Troll", bloodelf = "BloodElf",
   draenei = "Draenei",
}
local CLASS_TOKENS = {
   WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, DEATHKNIGHT = true,
   SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true,
}
local function raceToken(r)
   if type(r) ~= "string" then return r end
   return RACE_TOKENS[slower((sgsub(r, "[%s_%-]", "")))] or r
end
local function classToken(c)
   if type(c) ~= "string" then return c end
   local up = supper((sgsub(c, "[%s_%-]", "")))
   if CLASS_TOKENS[up] then return up end
   return c
end

function G.UnitRace(unit)
   if unit ~= "player" then return nil end
   local r = M.world.race
   if type(r) == "table" then return r[1], r[2] end
   local token = raceToken(r)
   local names = RACE_NAMES[M.world.locale] or RACE_NAMES.enUS
   return names[token] or M.world.raceName or token, token
end
function G.UnitClass(unit)
   if unit ~= "player" then return nil end
   local c = M.world.class
   if type(c) == "table" then return c[1], c[2] end
   local token = classToken(c)
   local names = CLASS_NAMES[M.world.locale] or CLASS_NAMES.enUS
   return names[token] or M.world.className or token, token
end
function G.UnitFactionGroup(unit)
   if unit ~= "player" then return nil end
   local f = M.world.faction
   if f == "A" then f = "Alliance" elseif f == "H" then f = "Horde" end
   if not f then
      local token = M.world.race
      if type(token) == "table" then token = token[2] end
      f = ALLIANCE_RACES[raceToken(token)] and "Alliance" or "Horde"
   end
   local names = FACTION_NAMES[M.world.locale] or FACTION_NAMES.enUS
   return f, names[f] or f
end

-- Gegenstaende und Ausruestung
function G.GetItemInfo(v)
   if type(v) ~= "number" and type(v) ~= "string" then
      error("Usage: GetItemInfo(itemID|\"name\"|\"itemLink\")", 2)
   end
   local id
   if type(v) == "number" then
      id = v
   else
      id = tonumber(smatch(v, "item:(%d+)"))
      if not id then
         id = tonumber(v)
         if not id then
            for iid, it in pairs(M.items) do
               if it.name == v and U.itemCached(iid) then
                  id = iid
                  break
               end
            end
         end
      end
   end
   if not id or not M.items[id] or not U.itemCached(id) then return end
   local it = M.items[id]
   return it.name, U.itemLink(id), it.quality or 1, it.ilvl or 1, it.minLevel or 0, it.class or "",
          it.subclass or "", it.maxStack or 1, it.equipLoc or "",
          it.icon or "Interface\\Icons\\INV_Misc_QuestionMark", it.price or 0
end
function G.GetItemIcon(v)
   local id = U.itemIdFromAny(v)
   local it = id and M.items[id]
   return it and (it.icon or "Interface\\Icons\\INV_Misc_QuestionMark") or nil
end
function G.GetItemCount(v)
   local id = U.itemIdFromAny(v)
   return id and M.world.itemCounts[id] or 0
end
function G.GetItemQualityColor(q)
   U.num(q, 1, "GetItemQualityColor")
   local c = QUALITY_RGB[q]
   if not c then error("GetItemQualityColor(): invalid quality " .. tostring(q), 2) end
   return c[1], c[2], c[3], "|cff" .. QUALITY_HEX[q]
end
function G.GetInventorySlotInfo(name)
   if type(name) ~= "string" then
      error("Usage: GetInventorySlotInfo(\"slotName\")", 2)
   end
   local s = INV_SLOTS[name]
   if not s then error("GetInventorySlotInfo(): unknown slot name '" .. name .. "'", 2) end
   return s[1], s[2], false
end
function G.GetInventoryItemLink(unit, slot)
   U.str(unit, 1, "GetInventoryItemLink")
   U.num(slot, 2, "GetInventoryItemLink")
   if unit ~= "player" then return nil end
   local id = M.world.equipment[slot]
   if not id then return nil end
   return U.itemLink(id)
end
function G.GetInventoryItemID(unit, slot)
   if unit ~= "player" then return nil end
   return M.world.equipment[slot]
end
function G.GetInventoryItemTexture(unit, slot)
   if unit ~= "player" then return nil end
   local id = M.world.equipment[slot]
   if not id then return nil end
   return U.itemData(id).icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
function G.GetInventoryItemQuality(unit, slot)
   if unit ~= "player" then return nil end
   local id = M.world.equipment[slot]
   if not id then return nil end
   return U.itemData(id).quality or 1
end
function G.GetMoney() return M.world.money end
function G.DressUpItemLink(link)
   M.dressUps[#M.dressUps + 1] = link
   local f = rawget(_G, "DressUpFrame")
   if f and not f:IsShown() then f:Show() end
   return true
end
function G.GetAuctionItemClasses()
   local l = M.world.auctionLists or AUCTION_EN
   return unpack(l.classes)
end
function G.GetAuctionItemSubClasses(i)
   U.num(i, 1, "GetAuctionItemSubClasses")
   local l = M.world.auctionLists or AUCTION_EN
   local s = l.subclasses and l.subclasses[i]
   if not s then return end
   return unpack(s)
end
function G.ClearCursor() end
function G.CursorHasItem() return nil end
function G.GetCursorInfo() return nil end

-- Fenster, Frames
function G.CreateFrame(typeName, name, parent, template)
   return U.createFrame(typeName, name, parent, template)
end
function G.CreateFont(name)
   U.str(name, 1, "CreateFont")
   local existing = S.fonts[name]
   if existing then
      U.warn("CreateFont('" .. name .. "'): font already exists")
      return existing
   end
   return U.newFont(name, rawget(_G, "STANDARD_TEXT_FONT") or "Fonts\\FRIZQT__.TTF", 12, nil, 1, 1, 1)
end
function G.GetMouseFocus() return S.hover end
function G.MouseIsOver(frame)
   if not U.isFrame(frame) then U.badArg(1, "MouseIsOver", "frame", frame) end
   return frame:IsMouseOver()
end
function G.ShowUIPanel(frame)
   if not U.isFrame(frame) then return end
   if not frame.__shown then frame:Show() end
end
function G.HideUIPanel(frame)
   if not U.isFrame(frame) then return end
   if not frame:IsShown() then return end
   frame:Hide()
end
function G.ToggleFrame(frame)
   if not U.isFrame(frame) then U.badArg(1, "ToggleFrame", "frame", frame) end
   if frame:IsShown() then G.HideUIPanel(frame) else G.ShowUIPanel(frame) end
end
function G.CloseSpecialWindows()
   local found
   for _, name in pairs(rawget(_G, "UISpecialFrames") or {}) do
      local f = rawget(_G, name)
      if U.isFrame(f) and f:IsShown() then
         f:Hide()
         found = 1
      end
   end
   return found
end
-- CloseGossip: schliesst das Gossip und loest GOSSIP_CLOSED SYNCHRON aus
function G.CloseGossip()
   if M.world.gossipOpen then
      M.world.gossipOpen = false
      M.Fire("GOSSIP_CLOSED")
   end
end

function G.UIFrameFade(frame, fadeInfo)
   if not frame then return end
   fadeInfo.mode = fadeInfo.mode or "IN"
   if fadeInfo.mode == "IN" then
      fadeInfo.startAlpha = fadeInfo.startAlpha or 0
      fadeInfo.endAlpha = fadeInfo.endAlpha or 1
   else
      fadeInfo.startAlpha = fadeInfo.startAlpha or 1
      fadeInfo.endAlpha = fadeInfo.endAlpha or 0
   end
   frame:SetAlpha(fadeInfo.startAlpha)
   frame.fadeInfo = fadeInfo
   fadeInfo.fadeTimer = 0
   for i = #S.fades, 1, -1 do
      if S.fades[i] == frame then tremove(S.fades, i) end
   end
   S.fades[#S.fades + 1] = frame
end
function G.UIFrameFadeIn(frame, timeToFade, startAlpha, endAlpha)
   G.UIFrameFade(frame, { mode = "IN", timeToFade = timeToFade, startAlpha = startAlpha, endAlpha = endAlpha })
end
function G.UIFrameFadeOut(frame, timeToFade, startAlpha, endAlpha)
   G.UIFrameFade(frame, { mode = "OUT", timeToFade = timeToFade, startAlpha = startAlpha, endAlpha = endAlpha })
end
function G.UIFrameFadeRemoveFrame(frame)
   for i = #S.fades, 1, -1 do
      if S.fades[i] == frame then tremove(S.fades, i) end
   end
end

-- Fortschritt der Faden-Animationen (wird von M.Advance je Schritt gerufen)
function U.stepFades(dt)
   if #S.fades == 0 then return end
   local list = {}
   for i = 1, #S.fades do list[i] = S.fades[i] end
   for _, frame in ipairs(list) do
      local info = frame.fadeInfo
      if info then
         info.fadeTimer = (info.fadeTimer or 0) + dt
         local total = info.timeToFade or 0
         if total <= 0 or info.fadeTimer >= total then
            frame:SetAlpha(info.endAlpha)
            G.UIFrameFadeRemoveFrame(frame)
            if info.finishedFunc then
               U.protected(info.finishedFunc, info.finishedArg1, info.finishedArg2, info.finishedArg3,
                  info.finishedArg4)
            end
         else
            local a = info.startAlpha + (info.endAlpha - info.startAlpha) * (info.fadeTimer / total)
            frame:SetAlpha(a)
         end
      end
   end
end

-- Tooltips
function G.GameTooltip_Hide()
   local t = rawget(_G, "GameTooltip")
   if t then t:Hide() end
end
function G.GameTooltip_SetDefaultAnchor(tooltip, parent)
   tooltip:SetOwner(parent, "ANCHOR_NONE")
end

-- Chat und Kommunikation
local CHAT_TYPES = toSet({ "SAY", "YELL", "EMOTE", "PARTY", "RAID", "GUILD", "OFFICER", "BATTLEGROUND",
                           "WHISPER", "CHANNEL", "RAID_WARNING" })
function G.SendAddonMessage(prefix, msg, channel, target)
   U.str(prefix, 1, "SendAddonMessage")
   U.str(msg, 2, "SendAddonMessage")
   if prefix == "" then error("SendAddonMessage(): empty prefix", 2) end
   if type(channel) ~= "string" or not CHAT_TYPES[channel] then
      error("SendAddonMessage(): invalid chat type '" .. tostring(channel) .. "'", 2)
   end
   if channel == "WHISPER" and (type(target) ~= "string" or target == "") then
      error("SendAddonMessage(): WHISPER needs a target player name", 2)
   end
   if #prefix + #msg > 254 then
      error(sfmt("SendAddonMessage(): message too long (%d bytes, max 254 incl. prefix)", #prefix + #msg), 2)
   end
   M.sentAddon[#M.sentAddon + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
end
function G.RegisterAddonMessagePrefix(prefix)   -- lint:allow(prefix-guard)
   U.str(prefix, 1, "RegisterAddonMessagePrefix")
   M.registeredPrefixes[prefix] = true
   return true
end
function G.SendChatMessage(text, chatType, language, target)
   M.sentChat[#M.sentChat + 1] = { text = text, chatType = chatType, language = language, target = target }
end
function G.ChatEdit_GetActiveWindow()
   if M.world.chatOpen then return rawget(_G, "ChatFrame1EditBox") end
   return nil
end
function G.ChatEdit_InsertLink(text)
   if type(text) ~= "string" then return false end
   M.chatInserts[#M.chatInserts + 1] = text
   return true
end
function G.ChatFrame_AddMessageEventFilter(event, fn)
   S.chatFilters = S.chatFilters or {}
   S.chatFilters[event] = S.chatFilters[event] or {}
   tinsert(S.chatFilters[event], fn)
end
function G.ChatFrame_RemoveMessageEventFilter(event, fn)
   local l = S.chatFilters and S.chatFilters[event]
   if not l then return end
   for i = #l, 1, -1 do
      if l[i] == fn then tremove(l, i) end
   end
end
function G.SetItemRef(link, text, button, chatFrame)
   M.itemRefs = M.itemRefs or {}
   M.itemRefs[#M.itemRefs + 1] = { link = link, text = text, button = button }
end
function G.HandleModifiedItemClick(link)
   if not link then return false end
   if G.IsModifiedClick("CHATLINK") and G.ChatEdit_InsertLink(link) then return true end
   if G.IsModifiedClick("DRESSUP") then
      G.DressUpItemLink(link)
      return true
   end
   return false
end

-- Toene
function G.PlaySound(name)
   if name == nil then U.badArg(1, "PlaySound", "string", name) end
   M.sounds[#M.sounds + 1] = { kind = "sound", name = name }
end
function G.PlaySoundFile(path)
   U.str(path, 1, "PlaySoundFile")
   U.checkAsset(path, "sound")
   M.sounds[#M.sounds + 1] = { kind = "file", name = path }
end

-- Statische Popups: einfaches Modell (M.popup = letzter Dialog, M.PopupAccept/M.PopupCancel)
function G.StaticPopup_Show(which, text1, text2, data)
   U.str(which, 1, "StaticPopup_Show")
   local info = rawget(_G, "StaticPopupDialogs")[which]
   if not info then return nil end
   local dialog
   for i = 1, 4 do
      local f = rawget(_G, "StaticPopup" .. i)
      if f and not f.__shown then
         dialog = f
         break
      end
   end
   dialog = dialog or rawget(_G, "StaticPopup4")
   dialog.which, dialog.data = which, data
   local text = info.text
   if type(text) == "string" then
      local ok, res = pcall(sfmt, text, text1 or "", text2 or "")
      text = ok and res or text
   end
   dialog.text = text
   local eb = rawget(_G, dialog.__name .. "EditBox")
   if eb then
      eb.__shown = info.hasEditBox and true or false
      eb.__text = ""
      if info.maxLetters then eb.__maxLetters = info.maxLetters end
   end
   dialog:Show()
   if info.OnShow then U.protected(info.OnShow, dialog, data) end
   local rec = { which = which, text = text, data = data, dialog = dialog, editBox = eb }
   M.popup = rec
   M.popups[#M.popups + 1] = rec
   return dialog
end
function G.StaticPopup_Hide(which)
   for i = 1, 4 do
      local f = rawget(_G, "StaticPopup" .. i)
      if f and f.__shown and f.which == which then f:Hide() end
   end
end

-- Aufloesung gelesener/geschriebener Globals im Addon-Code siehe M.LoadFiles (Umgebung)

-- ---------------------------------------------------------------------------
-- Globalstrings, Schriften, Standard-Frames
-- ---------------------------------------------------------------------------

-- Installiert (oder entfernt) die Blizzard-Globalstrings gemaess M.world.globalStrings/locale
function M.ApplyGlobalStrings()
   for _, set in pairs(GLOBALSTRINGS) do
      for k in pairs(set) do rawset(_G, k, nil) end
   end
   if M.world.globalStrings == false then return end
   local set = GLOBALSTRINGS[M.world.locale] or GLOBALSTRINGS.enUS
   for k, v in pairs(GLOBALSTRINGS.enUS) do rawset(_G, k, set[k] or v) end
end

local FONT_DEFS = {
   { "GameFontNormal", 12, 1, 0.82, 0 }, { "GameFontNormalSmall", 10, 1, 0.82, 0 },
   { "GameFontNormalLarge", 16, 1, 0.82, 0 },
   { "GameFontHighlight", 12, 1, 1, 1 }, { "GameFontHighlightSmall", 10, 1, 1, 1 },
   { "GameFontHighlightLarge", 16, 1, 1, 1 },
   { "GameFontDisable", 12, 0.5, 0.5, 0.5 }, { "GameFontDisableSmall", 10, 0.5, 0.5, 0.5 },
   { "GameFontDisableLarge", 16, 0.5, 0.5, 0.5 },
   { "ChatFontNormal", 14, 1, 1, 1 }, { "ChatFontSmall", 12, 1, 1, 1 }, { "NumberFontNormal", 14, 1, 1, 1 },
   { "GameTooltipText", 12, 1, 1, 1 }, { "GameTooltipTextSmall", 10, 1, 1, 1 },
   { "GameTooltipHeaderText", 14, 1, 1, 1 },
}

function U.installFonts()
   local path = LOCALE_FONT[M.world.locale] or "Fonts\\FRIZQT__.TTF"
   rawset(_G, "STANDARD_TEXT_FONT", path)
   rawset(_G, "UNIT_NAME_FONT", path)
   rawset(_G, "NAMEPLATE_FONT", path)
   rawset(_G, "DAMAGE_TEXT_FONT", path)
   for _, d in ipairs(FONT_DEFS) do U.newFont(d[1], path, d[2], nil, d[3], d[4], d[5]) end
end

local HIDDEN_FRAMES = {
   "GameMenuFrame", "CharacterFrame", "SpellBookFrame", "MerchantFrame", "QuestFrame", "TaxiFrame",
   "LootFrame", "BankFrame", "MailFrame", "TradeFrame", "AuctionFrame", "DressUpFrame", "WorldMapFrame",
   "InterfaceOptionsFrame", "FriendsFrame", "QuestLogFrame", "PlayerTalentFrame",
}

function U.installFrames()
   local ui = U.newFrame("Frame", "UIParent", nil)
   ui.__isScreen = true
   ui.__scale = M.world.uiScale or 1
   S.UIParent = ui
   local wf = U.newFrame("Frame", "WorldFrame", nil)
   wf.__isScreen = true

   -- Tooltips
   for _, n in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                        "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
      U.createFrame("GameTooltip", n, ui, "GameTooltipTemplate")
   end

   -- Chatfenster
   local chat = U.newFrame("ScrollingMessageFrame", "ChatFrame1", ui)
   rawset(_G, "DEFAULT_CHAT_FRAME", chat)
   local edit = U.newFrame("EditBox", "ChatFrame1EditBox", chat)
   U.initType(edit, "EditBox")
   edit.__fontObject = S.fonts.ChatFontNormal
   edit.__autoFocus = false
   edit.__shown = false

   -- versteckte Blizzard-Fenster
   for _, n in ipairs(HIDDEN_FRAMES) do
      local f = U.createFrame("Frame", n, ui)
      f.__shown = false
   end
   for i = 1, 4 do
      local d = U.createFrame("Frame", "StaticPopup" .. i, ui)
      d.__shown = false
      d.__strata = "DIALOG"
      local t = U.newRegion("FontString", "StaticPopup" .. i .. "Text", d, "ARTWORK")
      t.__fontObject = S.fonts.GameFontHighlight
      local eb = U.newFrame("EditBox", "StaticPopup" .. i .. "EditBox", d)
      U.initType(eb, "EditBox")
      eb.__fontObject = S.fonts.ChatFontNormal
      eb.__autoFocus = false
      eb.__shown = false
      U.createFrame("Button", "StaticPopup" .. i .. "Button1", d)
      U.createFrame("Button", "StaticPopup" .. i .. "Button2", d)
   end

   -- Gossip-Fenster: zeigt sich bei GOSSIP_SHOW, versteckt sich bei GOSSIP_CLOSED und
   -- ruft beim Verstecken CloseGossip() (wie GossipFrame_OnHide im Original)
   local gf = U.createFrame("Frame", "GossipFrame", ui)
   gf.__shown = false
   FrameM.RegisterEvent(gf, "GOSSIP_SHOW")
   FrameM.RegisterEvent(gf, "GOSSIP_CLOSED")
   gf.__scripts.OnEvent = function(self, event)
      if event == "GOSSIP_SHOW" then
         G.ShowUIPanel(self)
      else
         G.HideUIPanel(self)
      end
   end
   gf.__scripts.OnHide = function()
      G.CloseGossip()
   end

   rawset(_G, "SlashCmdList", {})
   rawset(_G, "StaticPopupDialogs", {})
   rawset(_G, "UISpecialFrames", {})
   rawset(_G, "UIPanelWindows", {})

   -- Farben
   local qc = {}
   for q = 0, 7 do
      qc[q] = { r = QUALITY_RGB[q][1], g = QUALITY_RGB[q][2], b = QUALITY_RGB[q][3], hex = "|cff" .. QUALITY_HEX[q] }
   end
   rawset(_G, "ITEM_QUALITY_COLORS", qc)
   rawset(_G, "RAID_CLASS_COLORS", {
      WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
      HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
      PRIEST = { r = 1, g = 1, b = 1 }, DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
      SHAMAN = { r = 0, g = 0.44, b = 0.87 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 },
      WARLOCK = { r = 0.58, g = 0.51, b = 0.79 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
   })
   rawset(_G, "NORMAL_FONT_COLOR", { r = 1, g = 0.82, b = 0 })
   rawset(_G, "HIGHLIGHT_FONT_COLOR", { r = 1, g = 1, b = 1 })
   rawset(_G, "GRAY_FONT_COLOR", { r = 0.5, g = 0.5, b = 0.5 })
   rawset(_G, "NORMAL_FONT_COLOR_CODE", "|cffffd200")
   rawset(_G, "HIGHLIGHT_FONT_COLOR_CODE", "|cffffffff")
   rawset(_G, "FONT_COLOR_CODE_CLOSE", "|r")
end

-- ---------------------------------------------------------------------------
-- Install / Zuruecksetzen
-- ---------------------------------------------------------------------------

-- Setzt ALLES zurueck: entfernt alle Globals, die nicht schon beim Laden der Attrappe
-- existierten (Transmog, TransmogDB, TransmogWindow ...), baut Welt, Zeit, Frames, Fonts,
-- Globalstrings und WoW-Funktionen neu auf.
--   opts.world    Tabelle, wird (rekursiv) in M.world gemischt
--   opts.items    Tabelle id -> Item-Daten
--   opts.globals  Tabelle name -> Wert (z.B. SavedVariables), nach dem Zuruecksetzen gesetzt
function M.Install(opts)
   opts = opts or {}
   for k in pairs(_G) do
      if not BASE[k] then _G[k] = nil end
   end
   resetState()
   if opts.world then U.merge(M.world, opts.world) end
   if opts.items then
      for id, it in pairs(opts.items) do M.items[id] = U.copy(it) end
   end
   for k, v in pairs(G) do rawset(_G, k, v) end
   if not M.world.hasRegisterAddonMessagePrefix then rawset(_G, "RegisterAddonMessagePrefix", nil) end
   U.installFonts()
   U.installFrames()
   M.ApplyGlobalStrings()
   -- virtuelle Templates aus Transmog.xml sind immer bekannt (auch ohne LoadToc)
   pcall(U.loadXmlFile, "Transmog.xml", "Transmog", {}, {}, { templatesOnly = true })
   if opts.globals then
      for k, v in pairs(opts.globals) do rawset(_G, k, U.copy(v)) end
   end
   return M
end

-- ---------------------------------------------------------------------------
-- Ausfuehrungsumgebung des Addon-Codes
-- ---------------------------------------------------------------------------

-- Diese Globals gibt es in WoW nicht; der Addon-Code sieht sie nicht
local HIDDEN_GLOBALS = toSet({ "io", "os", "debug", "package", "require", "dofile", "loadfile", "module",
                               "jit", "ffi", "newproxy", "arg" })

local function mockPrint(...)
   local parts = {}
   for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
   M.messages[#M.messages + 1] = tconcat(parts, " ")
end

-- Lua 5.1 / WoW: xpcall(f, errh) uebergibt KEINE Argumente (LuaJIT 2.1 taete es still)
local function strictXpcall(f, errh, ...)
   if select("#", ...) > 0 then
      error("xpcall(): extra arguments are not supported by Lua 5.1 / WoW 3.3.5a (wrap the call in a closure)", 2)
   end
   return xpcall(f, errh)
end

local function strictLoad(chunk, name)
   if type(chunk) == "string" then
      error("load(): loading a string is Lua 5.2 behaviour; use loadstring() in 3.3.5a", 2)
   end
   return load(chunk, name)
end

local OVERRIDES = { print = mockPrint, xpcall = strictXpcall, load = strictLoad }

-- Fundstelle des aufrufenden Addon-Codes (Ebene 3 ab hier: __index -> Aufrufer)
local function callerLocation(level)
   local info = realDebug.getinfo(level, "Sl")
   if not info then return "?" end
   return tostring(info.short_src) .. ":" .. tostring(info.currentline)
end

-- Umgebung fuer Addon-Chunks: verbirgt io/os/..., schreibt gelesene undefinierte und
-- neu angelegte Globals mit (M.globalMisses / M.globalWrites).
local function makeEnv()
   local env = {}
   setmetatable(env, {
      __index = function(_, k)
         if HIDDEN_GLOBALS[k] then return nil end
         local o = OVERRIDES[k]
         if o ~= nil then return o end
         local v = _G[k]
         if v == nil and type(k) == "string" then
            local m = M.globalMisses[k]
            if m then
               m.count = m.count + 1
            else
               M.globalMisses[k] = { count = 1, where = callerLocation(3) }
            end
         end
         return v
      end,
      __newindex = function(_, k, v)
         if type(k) == "string" and rawget(_G, k) == nil and not M.globalWrites[k] then
            M.globalWrites[k] = callerLocation(3)
         end
         rawset(_G, k, v)
      end,
   })
   return env
end

-- Namen, die der Addon-Code als Globals anlegen darf (SPEC Abschnitt 1, Regel 7)
local ALLOWED_GLOBAL_PATTERNS = {
   "^Transmog", "^transmogOutfits$", "^transmogSettings$", "^SLASH_TRANSMOG", "^SLASH_XMOG",
   "^BINDING_HEADER_TRANSMOG", "^BINDING_NAME_TRANSMOG",
}
M.allowedGlobalPatterns = ALLOWED_GLOBAL_PATTERNS

-- Vom Addon neu angelegte Globals, die nicht zu den erlaubten Namen passen
function M.StrayGlobals()
   local out = {}
   for name, where in pairs(M.globalWrites) do
      local ok = false
      for _, pat in ipairs(ALLOWED_GLOBAL_PATTERNS) do
         if sfind(name, pat) then ok = true break end
      end
      if not ok then out[#out + 1] = name .. " (" .. tostring(where) .. ")" end
   end
   tsort(out)
   return out
end

-- Benannte Frames, die nicht mit "Transmog" beginnen (Namensraum sauber halten)
function M.StrayFrameNames(allowed)
   local out = {}
   for _, f in ipairs(M.frames) do
      local n = f.__name
      if n and not sfind(n, "^Transmog") and not (allowed and allowed[n]) and not S.blizzardNames[n] then
         out[#out + 1] = n
      end
   end
   tsort(out)
   return out
end

-- Gelesene Implicit-Globals alter Handler (this, event, arg1..arg9): immer ein Fehler im Addon
-- (SPEC Abschnitt 1, Regel 3). Rueckgabe: Liste "name (datei:zeile)".
local IMPLICIT = toSet({ "this", "event", "arg1", "arg2", "arg3", "arg4", "arg5", "arg6", "arg7", "arg8", "arg9" })
function M.ImplicitGlobalReads()
   local out = {}
   for name, m in pairs(M.globalMisses) do
      if IMPLICIT[name] and rawget(_G, name) == nil then
         out[#out + 1] = name .. " (" .. tostring(m.where) .. ")"
      end
   end
   tsort(out)
   return out
end

-- Sichtbare Frames mit OnUpdate-Skript oder -Hook (SPEC Regel 9: im Leerlauf soll es keine geben)
function M.UpdateFrames()
   local out = {}
   for _, f in ipairs(M.frames) do
      if U.hasHandler(f, "OnUpdate") and U.isVisible(f) then out[#out + 1] = f end
   end
   return out
end

-- Gelesene, aber nicht definierte Globals (Name, Anzahl, erste Fundstelle)
function M.GlobalMisses()
   local out = {}
   for name, m in pairs(M.globalMisses) do
      -- inzwischen definierte Namen (z.B. Transmog vor "Transmog = Transmog or {}") sind keine Fehlgriffe
      if rawget(_G, name) == nil then
         out[#out + 1] = { name = name, count = m.count, where = m.where }
      end
   end
   tsort(out, function(a, b) return a.name < b.name end)
   return out
end

-- ---------------------------------------------------------------------------
-- Lua-5.1-Pruefung des Quelltexts (das, was luajit -bl nicht merkt)
-- ---------------------------------------------------------------------------

-- Sucht goto-Anweisungen und ::label:: ausserhalb von Strings/Kommentaren.
-- Liefert eine Liste von Meldungen "Zeile n: ...".
function U.scanLua51(src)
   local problems = {}
   local i, n, line = 1, #src, 1
   local function longBracket(pos)
      -- erkennt [[ oder [=[ ab pos; liefert Level und Ende des Oeffners
      local eq = smatch(src, "^%[(=*)%[", pos)
      if eq then return #eq, pos + #eq + 2 end
      return nil
   end
   local function skipLong(level, from)
      local close = "]" .. srep("=", level) .. "]"
      local s, e = sfind(src, close, from, true)
      local text = ssub(src, from, (e or n))
      for _ in text:gmatch("\n") do line = line + 1 end
      return (e or n) + 1
   end
   while i <= n do
      local c = ssub(src, i, i)
      if c == "\n" then
         line = line + 1
         i = i + 1
      elseif c == "-" and ssub(src, i + 1, i + 1) == "-" then
         local lvl, after = longBracket(i + 2)
         if lvl then
            i = skipLong(lvl, after)
         else
            local e = sfind(src, "\n", i, true)
            i = e or (n + 1)
         end
      elseif c == '"' or c == "'" then
         local j = i + 1
         while j <= n do
            local d = ssub(src, j, j)
            if d == "\\" then
               if ssub(src, j + 1, j + 1) == "\n" then line = line + 1 end
               j = j + 2
            elseif d == c or d == "\n" then
               break
            else
               j = j + 1
            end
         end
         i = j + 1
      elseif c == "[" and longBracket(i) then
         local lvl, after = longBracket(i)
         i = skipLong(lvl, after)
      elseif c == ":" and ssub(src, i + 1, i + 1) == ":" then
         problems[#problems + 1] = "line " .. line .. ": '::' label (goto labels are not Lua 5.1)"
         i = i + 2
      elseif sfind(c, "[%a_]") then
         local word = smatch(src, "^[%w_]+", i)
         if word == "goto" then
            local prev = ssub(src, max(1, i - 1), i - 1)
            local nxt = smatch(src, "^%s+([%a_][%w_]*)", i + 4)
            if prev ~= "." and prev ~= ":" and nxt then
               problems[#problems + 1] = "line " .. line .. ": 'goto " .. nxt .. "' (goto is not Lua 5.1)"
            end
         end
         i = i + #word
      else
         i = i + 1
      end
   end
   return problems
end

-- ---------------------------------------------------------------------------
-- Dateien laden
-- ---------------------------------------------------------------------------

local function readFile(path)
   local f = realIo.open(path, "rb")
   if not f then return nil end
   local s = f:read("*a")
   f:close()
   return s
end

local function resolvePath(rel)
   rel = sgsub(rel, "\\", "/")
   if ssub(rel, 1, 1) == "/" or M.root == "." then return rel end
   return M.root .. "/" .. rel
end

-- Laedt EINE Lua-Datei in die Addon-Umgebung. Rueckgabe: true (geladen) oder false (fehlt).
function U.loadLuaFile(rel, addonName, addonTable, displayName)
   local path = resolvePath(rel)
   local src = readFile(path)
   if not src then return false end
   if ssub(src, 1, 3) == "\239\187\191" then
      error("File " .. rel .. " has a UTF-8 BOM (WoW cannot load it)", 0)
   end
   local problems = U.scanLua51(src)
   if #problems > 0 then
      error("File " .. rel .. " is not Lua 5.1: " .. problems[1], 0)
   end
   local chunk, err = loadstring(src, "@" .. (displayName or sgsub(rel, "\\", "/")))
   if not chunk then error("Syntax error in " .. rel .. ": " .. tostring(err), 0) end
   setfenv(chunk, makeEnv())
   local ok, e = xpcall(function() chunk(addonName, addonTable) end, function(m)
      return realDebug.traceback(tostring(m), 2)
   end)
   if not ok then error("Error while loading " .. rel .. ":\n" .. tostring(e), 0) end
   return true
end

-- Laedt Lua-Dateien (Pfade relativ zum Addon-Verzeichnis) in dieser Reihenfolge;
-- jeder Chunk wird wie in WoW mit (Addonname, gemeinsame Addon-Tabelle) gerufen.
--   opts.addon         Name (Standard "Transmog")
--   opts.skipMissing   fehlende Dateien ueberspringen statt Fehler
function M.LoadFiles(list, opts)
   opts = opts or {}
   local name = opts.addon or "Transmog"
   M.addonTable = M.addonTable or {}
   local loaded, missing = {}, {}
   for _, rel in ipairs(list) do
      local ok = U.loadLuaFile(rel, name, M.addonTable)
      if ok then
         loaded[#loaded + 1] = rel
      elseif opts.skipMissing then
         missing[#missing + 1] = rel
      else
         error("File not found: " .. rel, 2)
      end
   end
   return loaded, missing
end

-- ---------------------------------------------------------------------------
-- XML (nur virtuelle Templates, Script/Include) und Bindings
-- ---------------------------------------------------------------------------

local function xmlAttr(attrs, key)
   return smatch(attrs, "[%s]" .. key .. '%s*=%s*"([^"]*)"') or smatch(attrs, "^" .. key .. '%s*=%s*"([^"]*)"')
end

-- Liest eine XML-Datei: virtuelle Templates -> S.templates; <Script file>/<Include file> werden
-- ausgefuehrt. Rueckgabe: Liste der geladenen Lua-Dateien.
function U.loadXmlFile(rel, addonName, addonTable, loadedLua, opts)
   local path = resolvePath(rel)
   local text = readFile(path)
   if not text then return false end
   text = sgsub(text, "<!%-%-.-%-%->", "")
   local dir = smatch(sgsub(rel, "\\", "/"), "^(.*)/[^/]*$")
   local pos = 1
   while true do
      local s, e, tag, attrs = sfind(text, "<([%a_][%w_]*)%s+([^<>]-)>", pos)
      if not s then break end
      pos = e + 1
      attrs = " " .. attrs
      if tag == "Script" then
         local file = xmlAttr(attrs, "file")
         if file and not (opts and opts.templatesOnly) then
            local r = (dir and (dir .. "/") or "") .. file
            if U.loadLuaFile(r, addonName, addonTable) then loadedLua[#loadedLua + 1] = r end
         end
      elseif tag == "Include" then
         local file = xmlAttr(attrs, "file")
         if file and not (opts and opts.templatesOnly) then
            U.loadXmlFile((dir and (dir .. "/") or "") .. file, addonName, addonTable, loadedLua, opts)
         end
      else
         local virtual = xmlAttr(attrs, "virtual")
         local nm = xmlAttr(attrs, "name")
         if virtual and slower(virtual) == "true" and nm then
            local body = ""
            if not sfind(attrs, "/%s*$") then
               local cs = sfind(text, "</" .. tag .. ">", e + 1, true)
               if cs then body = ssub(text, e + 1, cs - 1) end
            end
            local t = { kind = tag, name = nm, inherits = xmlAttr(attrs, "inherits") }
            local x, y = smatch(body, '<Size[^>]*>%s*<AbsDimension%s+x="([%d%.%-]+)"%s+y="([%d%.%-]+)"')
            if x then t.width, t.height = tonumber(x), tonumber(y) end
            local sc = xmlAttr(attrs, "scale")
            if sc then t.scale = tonumber(sc) end
            local em = xmlAttr(attrs, "enableMouse")
            if em then t.enableMouse = (slower(em) == "true") end
            local hid = xmlAttr(attrs, "hidden")
            if hid then t.hidden = (slower(hid) == "true") end
            S.templates[nm] = t
         elseif nm and tag ~= "Anchor" and tag ~= "Size" and tag ~= "Binding" then
            local lname = slower(tag)
            if lname == "frame" or lname == "button" or lname == "checkbutton" or lname == "editbox"
               or lname == "slider" or lname == "scrollframe" or lname == "dressupmodel" then
               U.warn("XML '" .. rel .. "' declares the non-virtual frame '" .. nm .. "' (not instantiated by the mock)")
            end
         end
      end
   end
   return true
end

-- Bindings.xml: <Binding name="X" ...>code</Binding>; M.RunBinding(name) fuehrt den Code aus
function U.loadBindings(rel)
   local text = readFile(resolvePath(rel))
   if not text then return false end
   text = sgsub(text, "<!%-%-.-%-%->", "")
   for attrs, code in text:gmatch("<Binding%s+([^>]-)>(.-)</Binding>") do
      local nm = xmlAttr(" " .. attrs, "name")
      if nm then M.bindings[nm] = { code = code, header = xmlAttr(" " .. attrs, "header"),
                                    runOnUp = xmlAttr(" " .. attrs, "runOnUp") } end
   end
   return true
end

function M.RunBinding(name)
   local b = M.bindings[name]
   if not b then error("RunBinding: unknown binding " .. tostring(name), 2) end
   local chunk, err = loadstring(b.code, "=binding:" .. name)
   if not chunk then error("RunBinding: syntax error in binding '" .. name .. "': " .. tostring(err), 2) end
   setfenv(chunk, makeEnv())
   return U.protected(chunk)
end

-- ---------------------------------------------------------------------------
-- TOC
-- ---------------------------------------------------------------------------

local function trim(s) return (sgsub(sgsub(s, "^%s+", ""), "%s+$", "")) end

-- Laedt ein Addon anhand seiner TOC-Datei.
--   dir          Verzeichnis des Addons (Standard M.root)
--   opts.upTo    nach dieser Datei aufhoeren (Name wie in der TOC, auch nur der Dateiname)
--   opts.skip    Menge { ["Core\\Boot.lua"] = true } (mit / oder \ moeglich)
--   opts.skipMissing  fehlende Dateien ueberspringen
-- .xml-Dateien werden nur auf virtuelle Templates (und <Script>/<Include>) geprueft.
-- Rueckgabe: Liste der geladenen Dateien, Info-Tabelle { missing, skipped, meta, files }.
function M.LoadToc(dir, tocName, opts)
   opts = opts or {}
   dir = dir or M.root
   tocName = tocName or "Transmog.toc"
   local tocPath = (dir == "." and "" or (dir .. "/")) .. tocName
   local text = readFile(resolvePath(tocPath))
   if not text then error("TOC file not found: " .. tocPath, 2) end
   local meta, files = {}, {}
   for line in (text .. "\n"):gmatch("(.-)\r?\n") do
      line = trim(line)
      if line ~= "" then
         if ssub(line, 1, 2) == "##" then
            local k, v = smatch(line, "^##%s*([^:]+):%s*(.*)$")
            if k then meta[trim(k)] = trim(v) end
         elseif ssub(line, 1, 1) ~= "#" then
            files[#files + 1] = sgsub(line, "\\", "/")
         end
      end
   end
   if meta.Interface ~= "30300" then
      error("TOC: '## Interface' must be 30300 for WoW 3.3.5a, found " .. tostring(meta.Interface), 2)
   end
   local addonName = smatch(tocName, "^(.-)%.toc$") or tocName
   M.toc = { name = addonName, meta = meta, files = files, dir = dir, loaded = false }
   M.addonTable = {}
   local skip = {}
   for k, v in pairs(opts.skip or {}) do
      if v then skip[sgsub(k, "\\", "/")] = true end
   end
   local upTo = opts.upTo and sgsub(opts.upTo, "\\", "/") or nil
   local loaded, missing, skipped = {}, {}, {}
   local prefix = (dir == "." or dir == M.root) and "" or (dir .. "/")
   if upTo then
      local found = false
      for _, f in ipairs(files) do
         if f == upTo or ssub(f, -#upTo - 1) == "/" .. upTo then found = true break end
      end
      if not found then error("LoadToc: upTo file '" .. upTo .. "' is not listed in " .. tocName, 2) end
   end
   for _, f in ipairs(files) do
      local rel = prefix .. f
      if skip[f] then
         skipped[#skipped + 1] = f
      else
         local lower = slower(f)
         if sfind(lower, "%.lua$") then
            if U.loadLuaFile(rel, addonName, M.addonTable, f) then
               loaded[#loaded + 1] = f
            elseif opts.skipMissing then
               missing[#missing + 1] = f
            else
               error("TOC lists a file that does not exist: " .. f, 2)
            end
         elseif sfind(lower, "%.xml$") then
            local isBindings = (lower == "bindings.xml")
            local ok
            if isBindings then
               ok = U.loadBindings(rel)
            else
               ok = U.loadXmlFile(rel, addonName, M.addonTable, loaded, opts)
            end
            if ok then
               loaded[#loaded + 1] = f
            elseif opts.skipMissing then
               missing[#missing + 1] = f
            else
               error("TOC lists a file that does not exist: " .. f, 2)
            end
         end
      end
      if upTo and (f == upTo or ssub(f, -#upTo - 1) == "/" .. upTo) then break end
   end
   M.toc.loaded = true
   return loaded, { missing = missing, skipped = skipped, meta = meta, files = files }
end

-- ---------------------------------------------------------------------------
-- Zeit und Ereignisse
-- ---------------------------------------------------------------------------

-- Beschreibung eines Objekts fuer Fehlermeldungen
function U.describe(o)
   local t = U.typeOf(o) or type(o)
   local n = type(o) == "table" and rawget(o, "__name") or nil
   return t .. " " .. (n and ("'" .. n .. "'") or "<anonymous>")
end

-- Zustellung eines Ereignisses an alle Frames, die es registriert haben (in
-- Registrierungsreihenfolge, wie das Spiel), auch an versteckte.
function M.Fire(event, ...)
   if type(event) ~= "string" then error("M.Fire: event name expected", 2) end
   if event == "PLAYER_LOGIN" then M.world.loggedIn = true end
   local list = S.eventFrames[event]
   if not list then return end
   local snap = {}
   for i = 1, #list do snap[i] = list[i] end
   for i = 1, #snap do
      local f = snap[i]
      if f.__events[event] then U.runScript(f, "OnEvent", event, ...) end
   end
end

-- Nachricht des Servers wie als CHAT_MSG_ADDON empfangen (prefix "transmog")
function M.ServerMessage(payload)
   M.Fire("CHAT_MSG_ADDON", "transmog", payload, "WHISPER", M.world.playerName)
end

-- Alle gesendeten Addon-Nachrichten (nur Praefix "transmog") als Array von Strings
function M.SentCommands()
   local out = {}
   for _, s in ipairs(M.sentAddon) do
      if s.prefix == "transmog" then out[#out + 1] = s.msg end
   end
   return out
end
function M.ClearSent()
   M.sentAddon = {}
   M.sentChat = {}
end
-- Wie oft wurde ein Befehl (Praefix-Vergleich des msg) gesendet?
function M.CountSent(prefix)
   local n = 0
   for _, c in ipairs(M.SentCommands()) do
      if ssub(c, 1, #prefix) == prefix then n = n + 1 end
   end
   return n
end

-- Zeit um dt Sekunden vorstellen (in Schritten von step, Standard 0.05) und OnUpdate
-- aller sichtbaren Frames rufen. Versteckte Frames und Kinder versteckter Eltern bekommen nichts.
function M.Advance(dt, step)
   if type(dt) ~= "number" or dt < 0 then error("M.Advance: dt must be a number >= 0", 2) end
   step = step or 0.05
   if step <= 0 then error("M.Advance: step must be > 0", 2) end
   local done = 0
   while done < dt - 1e-9 do
      local d = min(step, dt - done)
      done = done + d
      M.now = M.now + d
      U.processFocusQueue()
      U.stepFades(d)
      local snap = {}
      local frames = M.frames
      for i = 1, #frames do
         local f = frames[i]
         if U.hasHandler(f, "OnUpdate") then snap[#snap + 1] = f end
      end
      for i = 1, #snap do
         local f = snap[i]
         if U.isVisible(f) then U.runScript(f, "OnUpdate", d) end
      end
   end
end

-- Meldung ausgeben, die der Test pruefen kann (nur noetig fuer Debugzwecke)
function M.TakeErrors()
   local out = M.errors
   M.errors = {}
   M.errorTraces = {}
   return out
end
function M.ClearErrors()
   M.errors = {}
   M.errorTraces = {}
end

function M.SetScreen(w, h)
   M.world.screenWidth, M.world.screenHeight = w, h
end

-- Eine Zeile durch die Chatfilter schicken (true = verborgen)
function M.Filtered(event, msg, ...)
   local list = S.chatFilters and S.chatFilters[event]
   if not list then return false end
   for _, fn in ipairs(list) do
      if fn(rawget(_G, "ChatFrame1"), event, msg, ...) then return true end
   end
   return false
end

-- Slash-Befehl wie getippt ausfuehren: M.Slash("/transmog options"). true, wenn gefunden.
function M.Slash(text)
   local cmd, args = smatch(text, "^(/%S+)%s*(.*)$")
   if not cmd then error("M.Slash: expected '/command args'", 2) end
   cmd = slower(cmd)
   local list = rawget(_G, "SlashCmdList")
   for k, v in pairs(_G) do
      if type(k) == "string" and type(v) == "string" then
         local name = smatch(k, "^SLASH_(.+)%d+$")
         if name and slower(v) == cmd and type(list[name]) == "function" then
            U.protected(list[name], args, rawget(_G, "ChatFrame1EditBox"))
            return true
         end
      end
   end
   return false
end

-- Gossip: Server schickt "Open", danach zeigt der Client das Gossip-Fenster (GOSSIP_SHOW)
function M.GossipShow()
   M.world.gossipOpen = true
   M.Fire("GOSSIP_SHOW")
end
function M.OpenNpc()
   M.ServerMessage("Open")
   M.GossipShow()
end

-- ---------------------------------------------------------------------------
-- Eingabe-Simulation
-- ---------------------------------------------------------------------------

-- Prueft, dass ein Frame ueberhaupt Mausereignisse bekommen koennte
local function needInteractive(frame, what, noMouseNeeded)
   if not U.isFrame(frame) then error(what .. ": not a frame (" .. type(frame) .. ")", 3) end
   if not U.isVisible(frame) then
      error(what .. ": " .. U.describe(frame) .. " is not visible (hidden or has a hidden parent)", 3)
   end
   if not frame.__mouse and not noMouseNeeded then
      error(what .. ": " .. U.describe(frame) .. " is not mouse-enabled (EnableMouse(true) missing)", 3)
   end
end

-- Aendert Modifikatortasten fuer die Dauer von fn (mods = { shift=, ctrl=, alt= })
local function withMods(mods, fn)
   if not mods then return fn() end
   local w = M.world
   local s, c, a = w.shift, w.ctrl, w.alt
   if mods.shift ~= nil then w.shift = mods.shift end
   if mods.ctrl ~= nil then w.ctrl = mods.ctrl end
   if mods.alt ~= nil then w.alt = mods.alt end
   local ok, err = pcall(fn)
   w.shift, w.ctrl, w.alt = s, c, a
   if not ok then error(err, 0) end
end

local function isDisabledButton(frame)
   return U.isA(frame.__type, "Button") and frame.__enabled == false
end

function M.MouseDown(frame, button, mods)
   needInteractive(frame, "M.MouseDown")
   button = button or "LeftButton"
   if isDisabledButton(frame) then return end
   withMods(mods, function()
      frame.__downButton = button
      U.runScript(frame, "OnMouseDown", button)
      if frame.__clicks and frame.__clicks[button .. "Down"] then
         U.performClick(frame, button, true)
      end
   end)
end

function M.MouseUp(frame, button, mods)
   needInteractive(frame, "M.MouseUp")
   button = button or "LeftButton"
   if isDisabledButton(frame) then
      frame.__downButton = nil
      return
   end
   withMods(mods, function()
      local pressed = frame.__downButton
      frame.__downButton = nil
      U.runScript(frame, "OnMouseUp", button)
      if pressed == button and frame.__clicks and frame.__clicks[button .. "Up"] then
         U.performClick(frame, button, false)
      end
   end)
end

-- Klick (Maustaste druecken und loslassen). Verhaelt sich wie der Client:
--   * nur sichtbare, mausaktive Frames; deaktivierte Buttons loesen nichts aus
--   * OnClick kommt nur fuer Tasten, die per RegisterForClicks angemeldet sind (Standard: LeftButtonUp)
--   * CheckButtons schalten vor OnClick um
-- mods = { shift = true } usw. fuer IsShiftKeyDown() waehrend des Klicks.
function M.Click(frame, button, mods)
   M.MouseDown(frame, button, mods)
   if not U.isVisible(frame) then
      -- der Handler hat den Frame beim Druecken versteckt: das Loslassen geht ins Leere
      frame.__downButton = nil
      return
   end
   M.MouseUp(frame, button, mods)
end

function M.Enter(frame)
   needInteractive(frame, "M.Enter")
   local old = S.hover
   if old == frame then return end
   S.hover = frame
   if old and U.isVisible(old) then U.runScript(old, "OnLeave") end
   U.runScript(frame, "OnEnter")
end

function M.Leave(frame)
   if S.hover ~= frame then return end
   S.hover = nil
   U.runScript(frame, "OnLeave")
end

function M.Wheel(frame, delta)
   needInteractive(frame, "M.Wheel", true)
   if not frame.__mouseWheel then
      error("M.Wheel: " .. U.describe(frame) .. " has no EnableMouseWheel(true): OnMouseWheel would never fire", 2)
   end
   U.num(delta, 2, "M.Wheel")
   U.runScript(frame, "OnMouseWheel", delta)
end

-- Text eintippen: setzt den Text und feuert OnTextChanged(self, true)
function M.Type(editBox, text)
   if U.typeOf(editBox) ~= "EditBox" then error("M.Type: not an EditBox", 2) end
   if not U.isVisible(editBox) then
      error("M.Type: " .. U.describe(editBox) .. " is not visible", 2)
   end
   if type(text) == "number" then text = tostring(text) end
   U.str(text, 2, "M.Type")
   U.setFocus(editBox)
   if editBox.__numeric then text = sgsub(text, "[^%d]", "") end
   local max_ = editBox.__maxLetters or 0
   if max_ > 0 and utf8Length(text) > max_ then text = utf8Truncate(text, max_) end
   editBox.__text = text
   editBox.__cursor = utf8Length(text)
   U.runScript(editBox, "OnTextChanged", true)
end

-- Taste im EditBox bzw. in einem tastaturaktiven Frame: "ENTER", "ESCAPE", "TAB", "SPACE" oder Zeichen
function M.Key(frame, key)
   if not U.isFrame(frame) then error("M.Key: not a frame", 2) end
   if not U.isVisible(frame) then error("M.Key: " .. U.describe(frame) .. " is not visible", 2) end
   if frame.__type == "EditBox" then
      if S.focus ~= frame then error("M.Key: " .. U.describe(frame) .. " has no keyboard focus", 2) end
      if key == "ENTER" then
         U.runScript(frame, "OnEnterPressed")
      elseif key == "ESCAPE" then
         U.runScript(frame, "OnEscapePressed")
      elseif key == "TAB" then
         U.runScript(frame, "OnTabPressed")
      elseif key == "SPACE" then
         U.runScript(frame, "OnSpacePressed")
      end
      return
   end
   if not frame.__keyboard then
      error("M.Key: " .. U.describe(frame) .. " has no EnableKeyboard(true)", 2)
   end
   U.runScript(frame, "OnKeyDown", key)
   U.runScript(frame, "OnKeyUp", key)
end

-- ESC-Taste im Spiel: fokussierte EditBox zuerst, dann UISpecialFrames. true, wenn etwas geschah.
function M.Escape()
   local f = S.focus
   if f and U.isVisible(f) then
      U.runScript(f, "OnEscapePressed")
      return true
   end
   return G.CloseSpecialWindows() ~= nil
end

-- Ziehen: Maus runter, Drag-Start, Bewegung (dx,dy in Pixeln), Drag-Stop, Maus hoch.
-- Wirkt auf das Objekt, das im Handler StartMoving/StartSizing gerufen hat.
function M.Drag(frame, dx, dy, button)
   needInteractive(frame, "M.Drag")
   button = button or "LeftButton"
   dx, dy = dx or 0, dy or 0
   M.MouseDown(frame, button)
   local registered = frame.__drag and frame.__drag[button]
   if registered then U.runScript(frame, "OnDragStart", button) end
   local d = S.drag
   if d then
      local target = d.frame
      local eff = U.effScale(target)
      if d.mode == "move" then
         local p = target.__points[1]
         if p then
            p.x = p.x + dx / eff
            p.y = p.y + dy / eff
         end
      else
         local w, h = U.explicitWidth(target), U.explicitHeight(target)
         local pt = d.point or "BOTTOMRIGHT"
         if sfind(pt, "RIGHT") then w = w + dx / eff elseif sfind(pt, "LEFT") then w = w - dx / eff end
         if sfind(pt, "BOTTOM") then h = h - dy / eff elseif sfind(pt, "TOP") then h = h + dy / eff end
         local mn, mx = target.__minResize, target.__maxResize
         if mn then w, h = max(w, mn[1]), max(h, mn[2]) end
         if mx then w, h = min(w, mx[1]), min(h, mx[2]) end
         target:SetWidth(max(0, w))
         target:SetHeight(max(0, h))
      end
   end
   if registered then U.runScript(frame, "OnDragStop") end
   if U.isVisible(frame) then
      M.MouseUp(frame, button)
   else
      frame.__downButton = nil
   end
   if S.drag then FrameM.StopMovingOrSizing(S.drag.frame) end
end

-- ---------------------------------------------------------------------------
-- Abfragen fuer Tests
-- ---------------------------------------------------------------------------

function M.FindFrame(name)
   local o = rawget(_G, name)
   if U.isObject(o) then return o end
   return nil
end

-- Besucht frame und alle Nachfahren (Regionen zuerst, dann Kinder). fn(obj, tiefe);
-- liefert fn false, werden die Nachfahren dieses Objekts uebersprungen.
function M.Walk(root, fn)
   local function visit(o, depth)
      if fn(o, depth) == false then return end
      if U.isFrame(o) then
         for _, r in ipairs(o.__regions) do visit(r, depth + 1) end
         for _, c in ipairs(o.__children) do visit(c, depth + 1) end
      end
   end
   visit(root, 0)
end

-- Alle sichtbaren, nichtleeren FontString-Texte unter root (includeHidden = auch versteckte)
function M.Texts(root, includeHidden)
   local out = {}
   M.Walk(root, function(o)
      if o.__type == "FontString" and o.__text and o.__text ~= "" then
         if includeHidden or U.isVisible(o) then out[#out + 1] = o.__text end
      end
   end)
   return out
end

-- Kommt in den sichtbaren Texten unter root der Teilstring (plain) vor?
function M.HasText(root, needle, includeHidden)
   for _, t in ipairs(M.Texts(root, includeHidden)) do
      if sfind(t, needle, 1, true) then return true end
   end
   return false
end

-- Alle Frames/Regionen unter root eines Typs
function M.Find(root, typeName)
   local out = {}
   M.Walk(root, function(o)
      if o.__type == typeName then out[#out + 1] = o end
   end)
   return out
end

-- Zugriff auf Zustand und Aufrufprotokoll eines Modells
function M.Model(frame)
   if not U.isA(U.typeOf(frame) or "", "Model") then
      error("M.Model: not a Model/PlayerModel/DressUpModel frame", 2)
   end
   local view = {}
   local function ids()
      local out = {}
      for _, v in ipairs(frame.__tried) do
         if type(v) == "number" then
            out[#out + 1] = v
         else
            out[#out + 1] = tonumber(smatch(v, "item:(%d+)")) or v
         end
      end
      return out
   end
   setmetatable(view, { __index = function(_, k)
      if k == "calls" then return frame.__calls end
      if k == "unit" then return frame.__unit end
      if k == "facing" then return frame.__facing end
      if k == "position" then return frame.__position end
      if k == "rotation" then return frame.__rotation end
      if k == "undressed" then return frame.__undressed end
      if k == "tried" then return ids() end
      if k == "triedRaw" then return frame.__tried end
      if k == "modelPath" then return frame.__modelPath end
      return nil
   end })
   -- Namen aller Aufrufe in Reihenfolge
   function view.names()
      local out = {}
      for i, c in ipairs(frame.__calls) do out[i] = c[1] end
      return out
   end
   function view.count(name)
      local n = 0
      for _, c in ipairs(frame.__calls) do
         if c[1] == name then n = n + 1 end
      end
      return n
   end
   -- letzter Aufruf dieses Namens als { name, arg1, arg2 ... } oder nil
   function view.last(name)
      for i = #frame.__calls, 1, -1 do
         if frame.__calls[i][1] == name then return frame.__calls[i] end
      end
      return nil
   end
   function view.clear()
      local calls = frame.__calls
      for i = #calls, 1, -1 do calls[i] = nil end
   end
   -- "SetUnit(player) Undress() TryOn(123)"
   function view.log()
      local parts = {}
      for i, c in ipairs(frame.__calls) do
         local args = {}
         for j = 2, #c do args[j - 1] = tostring(c[j]) end
         parts[i] = tostring(c[1]) .. "(" .. tconcat(args, ",") .. ")"
      end
      return tconcat(parts, " ")
   end
   return view
end

-- Statischer Dialog: bestaetigen/abbrechen wie ein Klick auf den Knopf
function M.PopupAccept(text)
   local rec = M.popup
   if not rec then error("M.PopupAccept: no StaticPopup shown", 2) end
   local info = rawget(_G, "StaticPopupDialogs")[rec.which]
   if text ~= nil and rec.editBox then rec.editBox.__text = text end
   rec.dialog:Hide()
   if info and info.OnAccept then U.protected(info.OnAccept, rec.dialog, rec.data) end
   M.popup = nil
   return true
end
function M.PopupCancel()
   local rec = M.popup
   if not rec then error("M.PopupCancel: no StaticPopup shown", 2) end
   local info = rawget(_G, "StaticPopupDialogs")[rec.which]
   rec.dialog:Hide()
   if info and info.OnCancel then U.protected(info.OnCancel, rec.dialog, rec.data, "clicked") end
   M.popup = nil
   return true
end

-- Kopie dessen, was WoW bei Abmeldung speichern wuerde: nur einfache Daten (Funktionen,
-- Frames und andere Objekte fallen weg), Tabellenzyklen werden nicht unterstuetzt.
function U.plainCopy(v)
   local t = type(v)
   if t == "table" then
      if rawget(v, "__type") then return nil end     -- Frame/Region/Font
      local out = {}
      for k, x in pairs(v) do
         local kt = type(k)
         if kt == "string" or kt == "number" or kt == "boolean" then
            local c = U.plainCopy(x)
            if c ~= nil then out[k] = c end
         end
      end
      return out
   elseif t == "string" or t == "number" or t == "boolean" then
      return v
   end
   return nil
end

-- Die SavedVariables(PerCharacter) der TOC wie nach einer Abmeldung: { Name = Kopie }.
-- Danach z.B. H.boot({ globals = M.SavedVariables() }) = Neuanmeldung mit gespeicherten Daten
-- (die Kopie muss VOR dem naechsten Install/H.boot gezogen werden).
function M.SavedVariables()
   if not M.toc then error("M.SavedVariables: no TOC loaded", 2) end
   local out = {}
   for _, key in ipairs({ "SavedVariables", "SavedVariablesPerCharacter" }) do
      local list = M.toc.meta[key]
      if list then
         for name in list:gmatch("[^,%s]+") do
            local v = rawget(_G, name)
            if v ~= nil then out[name] = U.plainCopy(v) end
         end
      end
   end
   return out
end

-- Wartet (in Advance-Schritten), bis cond() wahr wird. Rueckgabe: vergangene Sekunden oder nil (Zeitlimit).
function M.AdvanceUntil(cond, maxSeconds, step)
   maxSeconds = maxSeconds or 10
   step = step or 0.05
   local t = 0
   while t <= maxSeconds + 1e-9 do
      if cond() then return t end
      M.Advance(step, step)
      t = t + step
   end
   return nil
end

-- Textuelle Baumdarstellung (zum Debuggen von Tests): Typ, Name, Text, Groesse, Sichtbarkeit
function M.Dump(root, maxDepth)
   local lines = {}
   M.Walk(root, function(o, depth)
      if maxDepth and depth > maxDepth then return false end
      local d = o.__type .. (o.__name and (" '" .. o.__name .. "'") or "")
      if o.__type == "FontString" and o.__text then d = d .. sfmt(" %q", o.__text) end
      if o.__width or o.__height then d = d .. sfmt(" %sx%s", tostring(o.__width or 0), tostring(o.__height or 0)) end
      if o.__shown == false then d = d .. " [hidden]" end
      lines[#lines + 1] = srep("  ", depth) .. d
   end)
   return tconcat(lines, "\n")
end

-- Fuer Tests, die intern nachsehen wollen
M.U = U
M.S = S

-- Zeitpunkt, ab dem GetItemInfo(id) Werte liefert (nil = nicht in Abfrage / nie)
function M.ItemDueAt(id)
   if S.cached[id] then return M.now end
   return S.pending[id]
end

-- Namen der Blizzard-Frames, die Install anlegt (fuer StrayFrameNames)
S.blizzardNames = {}
do
   local names = { "UIParent", "WorldFrame", "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1",
                   "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "ChatFrame1",
                   "ChatFrame1EditBox", "GossipFrame" }
   for _, n in ipairs(names) do S.blizzardNames[n] = true end
   for _, n in ipairs(HIDDEN_FRAMES) do S.blizzardNames[n] = true end
   for i = 1, 4 do
      for _, suffix in ipairs({ "", "Text", "EditBox", "Button1", "Button2" }) do
         S.blizzardNames["StaticPopup" .. i .. suffix] = true
      end
   end
   for _, base in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                           "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
      for i = 1, 40 do
         S.blizzardNames[base .. "TextLeft" .. i] = true
         S.blizzardNames[base .. "TextRight" .. i] = true
      end
   end
end

-- Zeigt, ob der Test nach dem Laden etwas unausgeglichenes hinterlassen hat
function M.Unhandled()
   local out = {}
   if #M.errors > 0 then out[#out + 1] = #M.errors .. " error(s) in the error handler: " .. M.errors[1] end
   if #M.missingAssets > 0 then
      out[#out + 1] = #M.missingAssets .. " missing addon file(s): " .. M.missingAssets[1].path
   end
   return out
end

return M
