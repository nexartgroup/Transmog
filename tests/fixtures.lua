-- tests/fixtures.lua
-- ---------------------------------------------------------------------------
-- Gemeinsame Testdaten und ein Server-Nachbau fuer UI-Tests und die
-- Layout-Werkzeuge (tests/layout.lua, tests/render_ui.lua).
--
-- Das Modul haengt von KEINER UI-Datei ab: es braucht nur die Attrappe
-- (tests/mock_wow.lua, ueber H.mock) und H.boot() des Runners. Es laeuft
-- mit dem Kern allein (Locales, Core\*.lua). Fehlt Core\Boot.lua noch, wird der
-- Ablauf aus SPEC 3/6.13 nachgebildet (DB.Init -> Locale.Set -> Slots/Items/
-- Net/State/Outfits/Tooltips/Toasts/Window.Init).
--
-- Einbinden (der Runner legt tests/ in package.path):
--
--    local Fixtures = require("fixtures")
--    local T = Fixtures.Boot(H, { locale = "deDE", equipmentSet = "cloth" })
--    local srv = Fixtures.ServerHello(T)        -- Status + 14 Listenstroeme sofort
--    Fixtures.ServerAutoReply(T)                -- danach antwortet der Server auf Befehle
--    local window = Fixtures.OpenAtNpc(T)       -- "Open" + GOSSIP_SHOW
--    Fixtures.Settle(T, 1.0)                    -- Zeit vorstellen, Server bedienen
--
-- API
-- ---------------------------------------------------------------------------
-- Fixtures.Boot(H, opts) -> T
--    Startet das Addon ueber H.boot (echte TOC), registriert den Katalog in der
--    Attrappe und legt die Ausruestung der 14 Slots an.
--    opts.locale        "enUS" (Standard) | "deDE"  (Client-Sprache, Typnamen, Itemnamen)
--    opts.addonLocale   Sprache der Addon-Texte: "enUS" | "deDE" | "frFR" | "esES" | "ruRU" | "koKR" |
--                       "zhCN" | "zhTW" | "esMX" | "enGB" | "auto". Unabhaengig von opts.locale (dem
--                       Client): wie die Auswahl in den Optionen (DB.Set("locale") + Locale.Set).
--                       Ohne Angabe gilt "auto" (= Client-Sprache).
--    opts.race          Rassen-Token der Attrappe, Standard "Human"
--    opts.class         Klassen-Token, Standard je Ausruestung (WARRIOR/MAGE)
--    opts.screen        { w =, h = } Bildschirm, Standard 1365 x 768
--    opts.uiScale       UIParent-Skalierung der Attrappe, Standard 1
--    opts.money         Kupfer, Standard 5000000 (500 Gold)
--    opts.equipmentSet  "plate" (Standard) | "cloth" | "dualwield"
--    opts.cacheItems    false: Katalog bleibt ungecacht (Ladezustand), Standard true
--    opts.itemCacheDelay  Sekunden bis eine Abfrage "einlaeuft" (Standard 0.3)
--    opts.enterWorld    false: PLAYER_ENTERING_WORLD nicht feuern
--    opts.skip / opts.upTo / opts.toc   werden an H.boot durchgereicht
--    opts.globals       gespeicherte Variablen (M.SavedVariables() der vorigen Sitzung): Neuanmeldung
--    opts.noSeed        true: TransmogGlobalDB nicht vorbelegen. Ohne eigene TransmogGlobalDB startet H.boot mit
--                       { noNpcDefault = true, allowAnywhere = false } (Vorschau-Modus ausserhalb des NPCs, wie
--                       vor 2.1); mit opts.noSeed = true gilt die echte Vorgabe von 2.1 (Neuinstallation:
--                       "Anwenden auch ohne Transmogrifizierer" an)
--
-- Fixtures.SetLanguage(T, code)
--    Schaltet die Sprache der Addon-Texte um wie der Spieler (DB.Set("locale", code),
--    danach Locale.Set(code): feuert LOCALE_CHANGED). Liefert den aufgeloesten Code.
--
-- Fixtures.ServerHello(T, opts) -> srv
--    Spielt die Serverseite durch T.Net.Handle im echten Drahtformat ab:
--    TransmogStatus (einige Slots angewendet, einer verborgen, einer inaktiv),
--    danach je Slot ein Strom start / Stuecke zu 20 IDs / end fuer alle 14 Slots
--    (Reihenfolge wie der Server: 0,2,3,4,5,6,7,8,9,14,15,16,17,18).
--    opts.applied   { [slot] = itemId | Schluessel | Position in der Liste (Zahl <= 100) }
--    opts.hidden    { slot, ... }   verborgen (999999)
--    opts.inactive  { [slot] = itemId | Schluessel }  gespeichert, aber nicht in der Liste
--    opts.price     Kupfer je Aussehen (Standard 100000)
--    opts.latency   Sekunden bis zur Antwort der Antwortschleife (Standard 0.1)
--    opts.collected { [itemId] = true|false }  Sammlung des Kontos aendern
--    opts.rules     { lowerTiers=, mixedArmor=, mixedOffhand=, mixedWeapons=0|1|2, mixedHandedness= }
--                   Standard: lowerTiers = true, mixedWeapons = 1 (Gruppen Axt/Schwert/Streitkolben und
--                   Zweihand), alles andere false
--    opts.noStatus / opts.noLists   Teile weglassen
--    opts.defaults  false: keine Standardauswahl (nichts angewendet)
--    Standard (ohne applied/hidden/inactive): Kopf = 2. Eintrag der Liste, Schulter, Brust = 1.,
--    Haupthand = 2., Ruecken verborgen, Beine inaktiv (Schluessel "legs_inactive", fehlt in der Liste).
--    Ein zweiter Aufruf spielt Status und Listen erneut ab (der Serverzustand bleibt).
--
-- Fixtures.ServerAutoReply(T, opts) -> srv      (opts: price, latency, rules, collected, mute)
--    Haengt eine Antwortschleife an SendAddonMessage: die Befehle des Addons
--    (GetTransmogStatus, GetAvailableTransmogs, GetCollectionStatus:id,
--    CalculateCost:..., Apply:s:i, Remove:s, RemoveAll) werden mit der
--    Latenz srv.latency (Standard 0.1 s) beantwortet; ausgeliefert wird als
--    CHAT_MSG_ADDON ueber M.ServerMessage (also ueber Net.OnAddonMessage).
--    srv.failApply = n    die naechsten n Apply-Befehle liefern ApplyTransmogResult:0
--    srv.reject[id]=true  dieses Aussehen wird immer abgelehnt
--    srv.mute = true      der Server schweigt (Modul nicht installiert)
--    srv.price            Kupfer je Aussehen (HIDDEN und Entfernen kosten 0)
--    srv.log              alle empfangenen Befehle
--
-- Fixtures.OpenAtNpc(T) -> TransmogWindow | nil
--    M.ServerMessage("Open") und GOSSIP_SHOW wie am NPC; das echte Boot-Verhalten
--    oeffnet das Fenster. Fehlt Core\Boot.lua, bildet die Funktion es nach
--    (HideUIPanel(GossipFrame), danach Window.Open{ fromNpc = true }).
--
-- Fixtures.ServerStop(T)                 Antwortschleife abhaengen (Befehle bleiben danach unbeantwortet)
-- Fixtures.Settle(T, seconds [, step])   Zeit in Schritten vorstellen und den Server bedienen
-- Fixtures.Server(T) -> srv | nil        das Serverobjekt
-- Fixtures.Catalog(T) -> cat             { list, byId, byKey, items, count }
-- Fixtures.Item(T, key) -> id            ID zu einem Katalogschluessel (z. B. "e_head_plate")
-- Fixtures.List(T, slot) -> ids, bucket  was der Server jetzt fuer den Slot senden wuerde
-- Fixtures.Equip(T, slot, idOrKey)       Ausruestung wechseln (feuert PLAYER_EQUIPMENT_CHANGED)
-- Fixtures.Unequip(T, slot)              Slot leeren
-- Fixtures.Collect(T, id)                Aussehen sammeln + CollectionUpdated senden
-- Fixtures.CollectionStatus(T, id)       CollectionStatus-Antwort abspielen
-- Fixtures.Cost(T, pairs)                TransmogCost-Antwort fuer { {slot, id}, ... } abspielen
-- Fixtures.Uncache(T, fraction|fn)       Teil des Katalogs wieder "unbekannt" machen
-- Fixtures.Looks(T, n) -> map            n bekannte Aussehen je Slot (fuer Outfits)
-- Fixtures.EQUIPMENT_SETS                Namen der Ausruestungssaetze
--
-- Katalog (rund 150 Gegenstaende, Qualitaet 0-7): Platte/Kette/Leder/Stoff fuer
-- Kopf, Schulter, Brust (auch Roben), Taille, Beine, Fuesse, Handgelenke, Haende,
-- Ruecken (Umhaenge), Hemden, Wappenroecke, Waffen aller Typen (1H, 2H, Haupt-/
-- Nebenhand, Dolche, Faustwaffen, Stangenwaffen, Staebe, Boegen, Schusswaffen,
-- Armbrueste, Zauberstaebe, Wurfwaffen), Schilde, Nebenhandgegenstaende;
-- einige Paare mit gleichem Aussehen (gleiches Symbol), nicht gesammelte,
-- klassen- und fraktionsgebundene Gegenstaende. Symbole: echte 3.3.5a-Pfade.
-- Die lokalisierten Typnamen stammen aus den Auktionshaus-Listen der Attrappe
-- (M.AUCTION_EN / M.AUCTION_DE), damit Items.TypeKeyFromNames sie aufloest.
--
-- Serverregeln (TransmogRules / TransmogRuleMatching): gleiche Klasse, nicht der
-- angelegte Gegenstand selbst, nicht dasselbe Aussehen, Fernkampf gleich
-- Fernkampf, Unterklasse gleich (oder Ausnahme: niedrigere Stufen, Waffen-
-- gruppen), Platz gleich (oder Ausnahme Brust/Robe, Waffenhand), Fertigkeit der
-- Klasse vorhanden, Klasse/Fraktion passend. Sortierung: Qualitaet absteigend,
-- dann englischer Name. Bucket = Klasse + Unterklasse des angelegten Gegenstands.
-- ---------------------------------------------------------------------------

local Fixtures = {}

local floor, max, min = math.floor, math.max, math.min
local sfmt = string.format
local tinsert, tsort, tconcat = table.insert, table.sort, table.concat

local HIDDEN = 999999
local DEFAULT_PRICE = 100000

-- Slots (Server, 0-basiert) in der Reihenfolge, in der der Server die Stroeme sendet
local SERVER_SLOTS = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }
local SLOT = {
   HEAD = 0, SHOULDER = 2, SHIRT = 3, CHEST = 4, WAIST = 5, LEGS = 6, FEET = 7,
   WRIST = 8, HANDS = 9, BACK = 14, MAINHAND = 15, OFFHAND = 16, RANGED = 17, TABARD = 18,
}
Fixtures.SLOT = SLOT
Fixtures.SERVER_SLOTS = SERVER_SLOTS

-- ---------------------------------------------------------------------------
-- Unterklassen: Schluessel -> { ITEM_SUBCLASS_*, Position in GetAuctionItemSubClasses }
-- ---------------------------------------------------------------------------

local WEAPON_SUB = {
   axe1 = { 0, 1 }, axe2 = { 1, 2 }, bow = { 2, 3 }, gun = { 3, 4 }, mace1 = { 4, 5 }, mace2 = { 5, 6 },
   polearm = { 6, 7 }, sword1 = { 7, 8 }, sword2 = { 8, 9 }, staff = { 10, 10 }, fist = { 13, 11 },
   misc = { 14, 12 }, dagger = { 15, 13 }, thrown = { 16, 14 }, crossbow = { 18, 15 }, wand = { 19, 16 },
   fishing = { 20, 17 },
}
local ARMOR_SUB = {
   misc = { 0, 1 }, cloth = { 1, 2 }, leather = { 2, 3 }, mail = { 3, 4 }, plate = { 4, 5 },
   shield = { 6, 6 }, libram = { 7, 7 }, idol = { 8, 8 }, totem = { 9, 9 }, sigil = { 10, 10 },
}
local CLASS_ID = { weapon = 2, armor = 4 }

-- Ausruestungsplaetze (INVTYPE_*)
local I = {
   head = "INVTYPE_HEAD", shoulder = "INVTYPE_SHOULDER", chest = "INVTYPE_CHEST", robe = "INVTYPE_ROBE",
   waist = "INVTYPE_WAIST", legs = "INVTYPE_LEGS", feet = "INVTYPE_FEET", wrist = "INVTYPE_WRIST",
   hands = "INVTYPE_HAND", back = "INVTYPE_CLOAK", shirt = "INVTYPE_BODY", tabard = "INVTYPE_TABARD",
   w1h = "INVTYPE_WEAPON", w2h = "INVTYPE_2HWEAPON", wmain = "INVTYPE_WEAPONMAINHAND",
   woff = "INVTYPE_WEAPONOFFHAND", shield = "INVTYPE_SHIELD", held = "INVTYPE_HOLDABLE",
   ranged = "INVTYPE_RANGED", rranged = "INVTYPE_RANGEDRIGHT", thrown = "INVTYPE_THROWN",
   neck = "INVTYPE_NECK", finger = "INVTYPE_FINGER", trinket = "INVTYPE_TRINKET",
}

-- Nie transmogbar (Server: CanNeverTransmog)
local NEVER_INV = {
   INVTYPE_BAG = true, INVTYPE_RELIC = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true,
   INVTYPE_AMMO = true, INVTYPE_QUIVER = true, INVTYPE_NECK = true,
}

-- ---------------------------------------------------------------------------
-- Katalogdaten (englisch, deutsch). Zeile: inv, sub, en, de, quality, ilvl, icon [, extra]
-- extra: Schluessel (String) oder { key=, unc=true (nicht gesammelt), cls="PALADIN" (nur diese Klasse),
--        faction="H"|"A" }
-- ---------------------------------------------------------------------------

local ARMOR_ROWS = {}
local WEAPON_ROWS = {}

local function A(inv, sub, en, de, q, ilvl, icon, extra)
   ARMOR_ROWS[#ARMOR_ROWS + 1] = { inv = inv, sub = sub, en = en, de = de, q = q, ilvl = ilvl, icon = icon, x = extra }
end
local function W(inv, sub, en, de, q, ilvl, icon, extra)
   WEAPON_ROWS[#WEAPON_ROWS + 1] = { inv = inv, sub = sub, en = en, de = de, q = q, ilvl = ilvl, icon = icon, x = extra }
end

-- Kopf ------------------------------------------------------------------------
A(I.head, "plate", "Helm of the Fallen Champion", "Helm des gefallenen Champions", 4, 200, "INV_Helmet_08", "e_head_plate")
A(I.head, "plate", "Helm of the Fallen Champion", "Helm des gefallenen Champions", 4, 213, "INV_Helmet_08")
A(I.head, "plate", "Battleplate Greathelm", "Schlachtplatten-Gro\195\159helm", 3, 130, "INV_Helmet_05")
A(I.head, "plate", "Ironforge Guard's Helmet", "Helm der Eisenschmiedewache", 2, 60, "INV_Helmet_23")
A(I.head, "plate", "Rusty Dented Helm", "Rostiger verbeulter Helm", 0, 20, "INV_Helmet_01")
A(I.head, "plate", "Visage of the Dread Conqueror", "Antlitz des Schreckenseroberers", 4, 232, "INV_Helmet_70", { unc = true })
A(I.head, "plate", "Crown of the Fallen Paladin", "Krone des gefallenen Paladins", 4, 226, "INV_Helmet_74", { cls = "PALADIN" })
A(I.head, "mail", "Coif of the Wild Hunt", "Kapuze der Wilden Jagd", 3, 138, "INV_Helmet_17")
A(I.head, "mail", "Chainmail Helm of the Marshal", "Kettenhelm des Marschalls", 2, 71, "INV_Helmet_29")
A(I.head, "mail", "Ringmail Coif", "Ringkettenhaube", 1, 19, "INV_Helmet_46")
A(I.head, "mail", "Stormcaller's Greathelm", "Gro\195\159helm des Sturmrufers", 4, 219, "INV_Helmet_93")
A(I.head, "leather", "Hood of the Shadow Prowler", "Kapuze des Schattenpirschers", 4, 205, "INV_Helmet_66")
A(I.head, "leather", "Studded Leather Cap", "Beschlagene Lederkappe", 1, 16, "INV_Helmet_14")
A(I.head, "leather", "Wolfskin Cowl", "Wolfsfellkapuze", 2, 55, "INV_Helmet_30")
A(I.head, "cloth", "Hood of Sublime Arcana", "Kapuze erhabener Arkana", 4, 213, "INV_Helmet_52", { unc = true })
A(I.head, "cloth", "Apprentice's Cap", "M\195\188tze des Lehrlings", 1, 12, "INV_Helmet_12")
A(I.head, "cloth", "Cowl of the Void Seer", "Kapuze des Leerenehers", 3, 136, "INV_Helmet_37")
A(I.head, "cloth", "Hood of the Wandering Magister", "Kapuze des umherziehenden Magisters", 3, 120, "INV_Helmet_55", "e_head_cloth")

-- Schulter --------------------------------------------------------------------
A(I.shoulder, "plate", "Pauldrons of Unyielding Resolve", "Schulterst\195\188cke des unbeugsamen Willens", 4, 213, "INV_Shoulder_62", "e_shoulder_plate")
A(I.shoulder, "plate", "Pauldrons of Unyielding Resolve", "Schulterst\195\188cke des unbeugsamen Willens", 4, 226, "INV_Shoulder_62")
A(I.shoulder, "plate", "Soldier's Plate Spaulders", "Plattenschulterst\195\188cke des Soldaten", 2, 40, "INV_Shoulder_07")
A(I.shoulder, "plate", "Heirloom Pauldrons of the Elder", "Erbst\195\188ck-Schulterst\195\188cke des \195\132ltesten", 7, 80, "INV_Shoulder_05")
A(I.shoulder, "mail", "Mantle of the Windfury", "Mantel der Windfurie", 3, 128, "INV_Shoulder_24")
A(I.shoulder, "mail", "Chain Spaulders of the Vanguard", "Kettenschulterst\195\188cke der Vorhut", 2, 50, "INV_Shoulder_16")
A(I.shoulder, "mail", "Pauldrons of the Stormforged", "Schulterst\195\188cke der Sturmgeschmiedeten", 4, 200, "INV_Shoulder_36")
A(I.shoulder, "leather", "Spaulders of the Night Stalker", "Schulterpolster des Nachtpirschers", 3, 125, "INV_Shoulder_29")
A(I.shoulder, "leather", "Padded Leather Shoulders", "Gepolsterte Lederschultern", 1, 15, "INV_Shoulder_09")
A(I.shoulder, "leather", "Mantle of Wild Growth", "Mantel des wilden Wachstums", 4, 213, "INV_Shoulder_58")
A(I.shoulder, "cloth", "Amice of the Magister", "Amikt des Magisters", 4, 200, "INV_Shoulder_88", "e_shoulder_cloth")
A(I.shoulder, "cloth", "Spaulders of Sorcery", "Schulterst\195\188cke der Zauberei", 2, 48, "INV_Shoulder_40")
A(I.shoulder, "cloth", "Frayed Epaulets", "Zerschlissene Epauletten", 0, 11, "INV_Shoulder_03")

-- Brust -----------------------------------------------------------------------
A(I.chest, "plate", "Breastplate of Eternal Vigilance", "Brustplatte der ewigen Wachsamkeit", 4, 213, "INV_Chest_Plate24", "e_chest_plate")
A(I.chest, "plate", "Battleworn Cuirass", "Abgenutzter K\195\188ra\195\159", 1, 30, "INV_Chest_Plate03")
A(I.chest, "plate", "Gladiator's Plate Chestpiece", "Plattenbrustschutz des Gladiators", 4, 232, "INV_Chest_Plate16")
A(I.chest, "mail", "Hauberk of the Tidecaller", "Kettenhemd der Gezeitenruferin", 3, 138, "INV_Chest_Chain_15")
A(I.chest, "mail", "Scale Vest", "Schuppenweste", 1, 17, "INV_Chest_Chain")
A(I.chest, "leather", "Tunic of the Silent Blade", "Tunika der stillen Klinge", 4, 200, "INV_Chest_Leather_08")
A(I.chest, "leather", "Worn Leather Vest", "Abgetragene Lederweste", 0, 8, "INV_Chest_Leather_01")
A(I.chest, "cloth", "Vestments of the Pious", "Gew\195\164nder der Frommen", 3, 134, "INV_Chest_Cloth_17")
A(I.robe, "cloth", "Robe of the Archmage", "Robe des Erzmagiers", 4, 226, "INV_Chest_Cloth_49", "e_chest_cloth")
A(I.robe, "cloth", "Initiate's Robe", "Robe des Initiaten", 1, 10, "INV_Chest_Cloth_03")
A(I.robe, "cloth", "Heirloom Robe of the Scholar", "Erbst\195\188ck-Robe des Gelehrten", 7, 80, "INV_Chest_Cloth_09")

-- Taille ----------------------------------------------------------------------
A(I.waist, "plate", "Girdle of the Unbroken", "G\195\188rtel der Ungebrochenen", 4, 213, "INV_Belt_32", "e_waist_plate")
A(I.waist, "plate", "Forged Iron Belt", "Geschmiedeter Eisengurt", 2, 38, "INV_Belt_14")
A(I.waist, "mail", "Chain Cinch of the Wayfarer", "Kettengurt des Wanderers", 3, 126, "INV_Belt_26")
A(I.waist, "mail", "Studded Mail Belt", "Beschlagener Kettengurt", 1, 14, "INV_Belt_04")
A(I.waist, "leather", "Cord of the Moonlit Grove", "Kordel des mondbeschienenen Hains", 4, 200, "INV_Belt_41")
A(I.waist, "leather", "Cured Leather Belt", "Gegerbter Ledergurt", 1, 9, "INV_Belt_02")
A(I.waist, "cloth", "Sash of the Arcane Scholar", "Sch\195\164rpe des arkanen Gelehrten", 3, 118, "INV_Belt_20", "e_waist_cloth")
A(I.waist, "cloth", "Rope Belt", "Seilgurt", 1, 5, "INV_Belt_01")
A(I.waist, "cloth", "Cord of the Silent Scribe", "Kordel des stillen Schreibers", 2, 45, "INV_Belt_06")

-- Beine -----------------------------------------------------------------------
A(I.legs, "plate", "Legplates of the Eternal Bastion", "Beinplatten der ewigen Bastion", 4, 213, "INV_Pants_Plate_26", "e_legs_plate")
A(I.legs, "plate", "Greaves of the Iron Vanguard", "Beinschienen der eisernen Vorhut", 2, 42, "INV_Pants_Plate_08")
A(I.legs, "mail", "Leggings of the Tempest", "Beinkleider des Sturms", 3, 130, "INV_Pants_Mail_14")
A(I.legs, "mail", "Mail Pants", "Kettenhose", 1, 18, "INV_Pants_Mail_03")
A(I.legs, "leather", "Breeches of the Forest Warden", "Kniehosen des Waldw\195\164chters", 4, 205, "INV_Pants_Leather_22")
A(I.legs, "leather", "Hide Pants", "Fellhose", 1, 10, "INV_Pants_Leather_03")
A(I.legs, "cloth", "Leggings of the Departed", "Gamaschen der Dahingeschiedenen", 3, 128, "INV_Pants_Cloth_14", "legs_inactive")
A(I.legs, "cloth", "Linen Pants", "Leinenhose", 1, 6, "INV_Pants_Cloth_02")
A(I.legs, "cloth", "Trousers of the Initiate", "Hose des Initiaten", 2, 40, "INV_Pants_Cloth_05")
A(I.legs, "cloth", "Leggings of the Relentless Guardian of the Eternal Watch of Northrend",
   "Gamaschen des unerm\195\188dlichen H\195\188ters der ewigen Wacht von Nordend", 4, 219, "INV_Pants_Cloth_25", "e_legs_cloth")

-- Fuesse ----------------------------------------------------------------------
A(I.feet, "plate", "Sabatons of the Crusader", "Eisenschuhe des Kreuzfahrers", 4, 213, "INV_Boots_Plate_08", "e_feet_plate")
A(I.feet, "plate", "Plate Boots", "Plattenstiefel", 1, 28, "INV_Boots_Plate_03")
A(I.feet, "mail", "Treads of the Mountain King", "Tritte des Bergk\195\182nigs", 3, 132, "INV_Boots_Chain_16")
A(I.feet, "mail", "Chain Boots", "Kettenstiefel", 1, 13, "INV_Boots_Chain_02")
A(I.feet, "leather", "Footpads of the Whisper", "Fu\195\159polster des Fl\195\188sterns", 4, 200, "INV_Boots_08")
A(I.feet, "leather", "Leather Boots", "Lederstiefel", 1, 8, "INV_Boots_05")
A(I.feet, "cloth", "Slippers of the Magi", "Pantoffeln der Magi", 3, 120, "INV_Boots_Cloth_14", "e_feet_cloth")
A(I.feet, "cloth", "Cloth Shoes", "Stoffschuhe", 1, 4, "INV_Boots_Cloth_01")
A(I.feet, "cloth", "Boots of the Dusk Walker", "Stiefel des D\195\164mmerwandlers", 4, 200, "INV_Boots_Cloth_08")

-- Handgelenke -----------------------------------------------------------------
A(I.wrist, "plate", "Bracers of the Fallen King", "Armschienen des gefallenen K\195\182nigs", 4, 213, "INV_Bracer_19", "e_wrist_plate")
A(I.wrist, "plate", "Iron Bracers", "Eisenarmschienen", 1, 20, "INV_Bracer_01")
A(I.wrist, "mail", "Bindings of the Wild", "Fesseln der Wildnis", 3, 126, "INV_Bracer_13")
A(I.wrist, "mail", "Mail Wristguards", "Kettenarmschutz", 2, 33, "INV_Bracer_07")
A(I.wrist, "leather", "Wristwraps of the Hunter", "Handgelenkwickel des J\195\164gers", 4, 200, "INV_Bracer_23")
A(I.wrist, "leather", "Leather Bracers", "Lederarmschienen", 1, 7, "INV_Bracer_02")
A(I.wrist, "cloth", "Cuffs of the Archivist", "Manschetten des Archivars", 3, 118, "INV_Bracer_16", "e_wrist_cloth")
A(I.wrist, "cloth", "Linen Cuffs", "Leinenmanschetten", 1, 3, "INV_Bracer_03")
A(I.wrist, "cloth", "Bracers of the Moonweaver", "Armschienen der Mondweberin", 2, 44, "INV_Bracer_09")

-- Haende ----------------------------------------------------------------------
A(I.hands, "plate", "Gauntlets of the Fallen Hero", "Stulpen des gefallenen Helden", 4, 213, "INV_Gauntlets_58", "e_hands_plate")
A(I.hands, "plate", "Steel Gauntlets", "Stahlstulpen", 2, 36, "INV_Gauntlets_14")
A(I.hands, "mail", "Handguards of the Tempest", "Handsch\195\188tzer des Sturms", 3, 130, "INV_Gauntlets_26")
A(I.hands, "mail", "Mail Gloves", "Kettenhandschuhe", 1, 15, "INV_Gauntlets_09")
A(I.hands, "leather", "Gloves of the Shadowblade", "Handschuhe der Schattenklinge", 4, 205, "INV_Gauntlets_44")
A(I.hands, "leather", "Leather Gloves", "Lederhandschuhe", 1, 8, "INV_Gauntlets_05")
A(I.hands, "cloth", "Mitts of the Archivist", "F\195\164ustlinge des Archivars", 3, 118, "INV_Gauntlets_21", "e_hands_cloth")
A(I.hands, "cloth", "Linen Gloves", "Leinenhandschuhe", 1, 3, "INV_Gauntlets_02")
A(I.hands, "cloth", "Gloves of the Nightweaver", "Handschuhe der Nachtweberin", 4, 205, "INV_Gauntlets_30")

-- Ruecken (Umhaenge sind Stoff) ------------------------------------------------
A(I.back, "cloth", "Cloak of the Fallen Champion", "Umhang des gefallenen Champions", 4, 213, "INV_Misc_Cape_20", "e_back")
A(I.back, "cloth", "Drape of the Shattered Sun", "Mantel der zerschmetterten Sonne", 4, 200, "INV_Misc_Cape_18")
A(I.back, "cloth", "Heirloom Cloak of the Explorer", "Erbst\195\188ck-Umhang des Entdeckers", 7, 80, "INV_Misc_Cape_14")
A(I.back, "cloth", "Greater Fireproof Cape", "Gro\195\159er feuerfester Umhang", 3, 120, "INV_Misc_Cape_08")
A(I.back, "cloth", "Linen Cloak", "Leinenumhang", 1, 5, "INV_Misc_Cape_01")
A(I.back, "cloth", "Shadowcloak of Dalaran", "Schattenumhang von Dalaran", 5, 245, "INV_Misc_Cape_21")
A(I.back, "cloth", "Tattered Cape", "Zerlumpter Umhang", 0, 3, "INV_Misc_Cape_05")
A(I.back, "cloth", "Wing of the Dawnbringer", "Schwinge des Morgenbringers", 6, 250, "INV_Misc_Cape_22", { unc = true })

-- Hemden ----------------------------------------------------------------------
A(I.shirt, "misc", "Black Swashbuckler's Shirt", "Schwarzes Freibeuterhemd", 1, 1, "INV_Shirt_05", "e_shirt")
A(I.shirt, "misc", "Red Linen Shirt", "Rotes Leinenhemd", 1, 1, "INV_Shirt_Red_01")
A(I.shirt, "misc", "Formal White Shirt", "Festliches wei\195\159es Hemd", 1, 1, "INV_Shirt_White_01")
A(I.shirt, "misc", "Champion's Tunic", "Tunika des Champions", 2, 1, "INV_Shirt_Blue_01")
A(I.shirt, "misc", "Frayed Peasant Shirt", "Ausgefranstes Bauernhemd", 0, 1, "INV_Shirt_01")

-- Wappenroecke ----------------------------------------------------------------
A(I.tabard, "misc", "Tabard of the Argent Crusade", "Wappenrock des Argentumkreuzzugs", 2, 1, "INV_Misc_Tabard_ArgentCrusade", "e_tabard")
A(I.tabard, "misc", "Tabard of the Explorer", "Wappenrock des Entdeckers", 1, 1, "INV_Misc_Tabard_Explorer")
A(I.tabard, "misc", "Stormwind Tabard", "Wappenrock von Sturmwind", 1, 1, "INV_Misc_TabardPVP_01", { faction = "A" })
A(I.tabard, "misc", "Orgrimmar Tabard", "Wappenrock von Orgrimmar", 1, 1, "INV_Misc_TabardPVP_02", { faction = "H" })
A(I.tabard, "misc", "Tabard of Flame", "Wappenrock der Flamme", 3, 1, "INV_Shirt_GuildTabard_01")

-- Schilde und Nebenhand --------------------------------------------------------
A(I.shield, "shield", "Bulwark of the Dawnbringer", "Bollwerk des Morgenbringers", 4, 213, "INV_Shield_58", "e_shield")
A(I.shield, "shield", "Buckler of the Squire", "Tartsche des Knappen", 1, 12, "INV_Shield_01")
A(I.shield, "shield", "Kite Shield of the Vanguard", "Drachenschild der Vorhut", 3, 128, "INV_Shield_27")
A(I.shield, "shield", "Heirloom Shield of the Ancestor", "Erbst\195\188ck-Schild des Vorfahren", 7, 80, "INV_Shield_12")
A(I.shield, "shield", "Battered Wooden Shield", "Zerschlagener Holzschild", 0, 6, "INV_Shield_05")
A(I.held, "misc", "Tome of Forgotten Lore", "Foliant des vergessenen Wissens", 3, 125, "INV_Misc_Book_11")
A(I.held, "misc", "Orb of the Shattered Sun", "Kugel der zerschmetterten Sonne", 4, 200, "INV_Misc_Orb_03")
A(I.held, "misc", "Worn Spellbook", "Abgegriffenes Zauberbuch", 1, 8, "INV_Misc_Book_09")

-- Waffen ----------------------------------------------------------------------
W(I.w1h, "sword1", "Blade of the Ancient Flame", "Klinge der uralten Flamme", 5, 264, "INV_Sword_61")
W(I.w1h, "sword1", "Iron Shortsword", "Eiserner Kurzschwert", 1, 8, "INV_Sword_01")
W(I.w1h, "sword1", "Rusty Cutlass", "Rostiger Enters\195\164bel", 0, 5, "INV_Sword_07")
W(I.w1h, "sword1", "Heirloom Sword of the Squire", "Erbst\195\188ck-Schwert des Knappen", 7, 80, "INV_Sword_32")
W(I.w1h, "sword1", "Longsword of the Righteous Cause", "Langschwert der gerechten Sache", 4, 213, "INV_Sword_48", "e_sword")
W(I.wmain, "sword1", "Frostbitten Mainhand Blade", "Frostgebissene Haupthandklinge", 4, 200, "INV_Sword_38", "e_sword_mh")
W(I.woff, "sword1", "Frostbitten Offhand Blade", "Frostgebissene Nebenhandklinge", 4, 200, "INV_Sword_39", "e_sword_oh")
W(I.w1h, "axe1", "Hatchet of the Berserker", "Beil des Berserkers", 3, 130, "INV_Axe_18")
W(I.w1h, "axe1", "Woodcutter's Axe", "Axt des Holzf\195\164llers", 1, 11, "INV_Axe_05")
W(I.w1h, "axe1", "Cleaver of the Blood Court", "Hackbeil des Bluthofs", 4, 219, "INV_Axe_33")
W(I.w1h, "mace1", "Hammer of the Silent Vow", "Hammer des stillen Schwurs", 3, 127, "INV_Mace_22")
W(I.w1h, "mace1", "Smooth Club", "Glatte Keule", 1, 4, "INV_Mace_01")
W(I.wmain, "mace1", "Mace of Sacred Dawn", "Streitkolben der heiligen Morgenr\195\182te", 4, 205, "INV_Mace_29")
W(I.w1h, "dagger", "Kris of the Silent Night", "Kris der stillen Nacht", 4, 213, "INV_Weapon_ShortBlade_62")
W(I.w1h, "dagger", "Rusty Dirk", "Rostiger Dolch", 0, 3, "INV_Weapon_ShortBlade_05")
W(I.wmain, "dagger", "Stiletto of the Void", "Stilett der Leere", 3, 128, "INV_Weapon_ShortBlade_47")
W(I.w1h, "fist", "Claws of the Wild Beast", "Klauen der wilden Bestie", 3, 125, "INV_Weapon_Hand_15")
W(I.w1h, "fist", "Brass Knuckles", "Messingschlagring", 1, 9, "INV_Weapon_Hand_01")
W(I.w2h, "sword2", "Greatsword of the Titan Slayer", "Zweihandschwert des Titanenschl\195\164chters", 4, 232, "INV_Sword_62", { unc = true })
W(I.w2h, "sword2", "Executioner's Claymore", "Claymore des Scharfrichters", 3, 135, "INV_Sword_40")
W(I.w2h, "sword2", "Rough Broadsword", "Grobes Breitschwert", 1, 12, "INV_Sword_05")
W(I.w2h, "axe2", "Axe of the Mountain King", "Axt des Bergk\195\182nigs", 4, 219, "INV_Axe_60")
W(I.w2h, "axe2", "Two-Handed Battle Axe", "Zweihandstreitaxt", 1, 14, "INV_Axe_09")
W(I.w2h, "mace2", "Maul of the Earthen Ring", "Hammer des Irdenen Rings", 4, 213, "INV_Mace_49")
W(I.w2h, "mace2", "Gnarled Club", "Knorrige Keule", 1, 7, "INV_Mace_06")
W(I.w2h, "polearm", "Halberd of the Wardens", "Hellebarde der W\195\164chter", 3, 130, "INV_Weapon_Halberd_21")
W(I.w2h, "polearm", "Wooden Spear", "Holzspeer", 0, 4, "INV_Spear_01")
W(I.w2h, "staff", "Staff of the Arcane Conclave", "Stab des arkanen Konklaves", 6, 277, "INV_Staff_30", "e_staff")
W(I.w2h, "staff", "Gnarled Walking Staff", "Knorriger Wanderstab", 1, 6, "INV_Staff_08")
W(I.w2h, "staff", "Staff of the Forest Warden", "Stab des Waldw\195\164chters", 4, 200, "INV_Staff_53")
W(I.ranged, "bow", "Bow of the Silverwing Sentinel", "Bogen der Silberschwingenwache", 4, 213, "INV_Weapon_Bow_28", "e_bow")
W(I.ranged, "bow", "Short Bow", "Kurzbogen", 1, 7, "INV_Weapon_Bow_02")
W(I.ranged, "bow", "Longbow of the Windrunner", "Langbogen der Windl\195\164uferin", 3, 125, "INV_Weapon_Bow_12")
W(I.rranged, "gun", "Rifle of the Dwarven Marksman", "Gewehr des Zwergensch\195\188tzen", 4, 213, "INV_Weapon_Rifle_28")
W(I.rranged, "gun", "Hunting Rifle", "Jagdgewehr", 1, 6, "INV_Weapon_Rifle_01")
W(I.rranged, "crossbow", "Crossbow of the Gilneas Watch", "Armbrust der Wache von Gilneas", 3, 128, "INV_Weapon_Crossbow_12")
W(I.rranged, "crossbow", "Light Crossbow", "Leichte Armbrust", 1, 5, "INV_Weapon_Crossbow_04")
W(I.rranged, "wand", "Wand of the Archivist", "Zauberstab des Archivars", 3, 118, "INV_Wand_15", "e_wand")
W(I.rranged, "wand", "Apprentice's Wand", "Zauberstab des Lehrlings", 1, 4, "INV_Wand_01")
W(I.thrown, "thrown", "Throwing Dagger of the Shadow Court", "Wurfdolch des Schattenhofs", 3, 120, "INV_ThrowingKnife_06", "e_thrown")
W(I.thrown, "thrown", "Throwing Axe", "Wurfaxt", 1, 7, "INV_ThrowingAxe_01")

-- ---------------------------------------------------------------------------
-- Nicht transmogbare Plaetze (Hals, Ringe, Schmuck): nur als Ausruestung
-- ---------------------------------------------------------------------------

local EXTRA_ROWS = {
   { inv = I.neck, sub = "misc", en = "Pendant of the Wandering Star", de = "Anh\195\164nger des wandernden Sterns",
     q = 4, ilvl = 213, icon = "INV_Jewelry_Necklace_30", key = "e_neck" },
   { inv = I.finger, sub = "misc", en = "Band of the Silver Hand", de = "Band der Silbernen Hand",
     q = 4, ilvl = 213, icon = "INV_Jewelry_Ring_61", key = "e_ring1" },
   { inv = I.finger, sub = "misc", en = "Signet of the Mountain Kings", de = "Siegelring der Bergk\195\182nige",
     q = 3, ilvl = 130, icon = "INV_Jewelry_Ring_41", key = "e_ring2" },
   { inv = I.trinket, sub = "misc", en = "Charm of the Lost Legion", de = "Talisman der verlorenen Legion",
     q = 4, ilvl = 213, icon = "INV_Misc_Gem_Variety_02", key = "e_trinket1" },
   { inv = I.trinket, sub = "misc", en = "Idol of Fading Light", de = "G\195\182tze des schwindenden Lichts",
     q = 3, ilvl = 130, icon = "INV_Misc_Idol_02", key = "e_trinket2" },
}

-- ---------------------------------------------------------------------------
-- Ausruestungssaetze: Server-Slot -> Katalogschluessel
-- ---------------------------------------------------------------------------

local COMMON_ACCESSORIES = {
   neck = "e_neck", ring1 = "e_ring1", ring2 = "e_ring2", trinket1 = "e_trinket1", trinket2 = "e_trinket2",
}

local EQUIPMENT_SETS = {
   plate = {
      class = "WARRIOR",
      slots = {
         [SLOT.HEAD] = "e_head_plate", [SLOT.SHOULDER] = "e_shoulder_plate", [SLOT.SHIRT] = "e_shirt",
         [SLOT.CHEST] = "e_chest_plate", [SLOT.WAIST] = "e_waist_plate", [SLOT.LEGS] = "e_legs_plate",
         [SLOT.FEET] = "e_feet_plate", [SLOT.WRIST] = "e_wrist_plate", [SLOT.HANDS] = "e_hands_plate",
         [SLOT.BACK] = "e_back", [SLOT.MAINHAND] = "e_sword", [SLOT.OFFHAND] = "e_shield",
         [SLOT.RANGED] = "e_bow", [SLOT.TABARD] = "e_tabard",
      },
   },
   cloth = {
      class = "MAGE",
      slots = {
         [SLOT.HEAD] = "e_head_cloth", [SLOT.SHOULDER] = "e_shoulder_cloth", [SLOT.SHIRT] = "e_shirt",
         [SLOT.CHEST] = "e_chest_cloth", [SLOT.WAIST] = "e_waist_cloth", [SLOT.LEGS] = "e_legs_cloth",
         [SLOT.FEET] = "e_feet_cloth", [SLOT.WRIST] = "e_wrist_cloth", [SLOT.HANDS] = "e_hands_cloth",
         [SLOT.BACK] = "e_back", [SLOT.MAINHAND] = "e_staff", [SLOT.RANGED] = "e_wand",
         [SLOT.TABARD] = "e_tabard",
         -- Nebenhand bleibt leer (Zweihandstab)
      },
   },
   dualwield = {
      class = "WARRIOR",
      slots = {
         [SLOT.HEAD] = "e_head_plate", [SLOT.SHOULDER] = "e_shoulder_plate", [SLOT.SHIRT] = "e_shirt",
         [SLOT.CHEST] = "e_chest_plate", [SLOT.WAIST] = "e_waist_plate", [SLOT.LEGS] = "e_legs_plate",
         [SLOT.FEET] = "e_feet_plate", [SLOT.WRIST] = "e_wrist_plate", [SLOT.HANDS] = "e_hands_plate",
         [SLOT.BACK] = "e_back", [SLOT.MAINHAND] = "e_sword_mh", [SLOT.OFFHAND] = "e_sword_oh",
         [SLOT.RANGED] = "e_thrown", [SLOT.TABARD] = "e_tabard",
      },
   },
}
Fixtures.EQUIPMENT_SETS = { "plate", "cloth", "dualwield" }

-- Client-Inventar-IDs der Zubehoerplaetze
local ACCESSORY_CLIENT = { neck = 2, ring1 = 11, ring2 = 12, trinket1 = 13, trinket2 = 14 }

-- ---------------------------------------------------------------------------
-- Klassen: Hoechste Ruestungsstufe und Fertigkeiten (Spielerwissen des Servers)
-- ---------------------------------------------------------------------------

local TIER_ORDER = { cloth = 1, leather = 2, mail = 3, plate = 4 }
local HIGHEST_TIER = {
   WARRIOR = "plate", PALADIN = "plate", DEATHKNIGHT = "plate", HUNTER = "mail", SHAMAN = "mail",
   ROGUE = "leather", DRUID = "leather", MAGE = "cloth", PRIEST = "cloth", WARLOCK = "cloth",
}

local function set(list)
   local s = {}
   for _, k in ipairs(list) do s[k] = true end
   return s
end

-- Fertigkeiten je Klasse (Waffenarten und Ruestungsarten). "misc" (Unterklasse 0) braucht keine.
local PROFICIENCY = {
   WARRIOR = set({ "axe1", "axe2", "mace1", "mace2", "sword1", "sword2", "polearm", "staff", "fist", "dagger",
                   "bow", "gun", "crossbow", "thrown", "cloth", "leather", "mail", "plate", "shield" }),
   PALADIN = set({ "axe1", "axe2", "mace1", "mace2", "sword1", "sword2", "polearm", "cloth", "leather", "mail",
                   "plate", "shield", "libram" }),
   HUNTER = set({ "axe1", "axe2", "sword1", "sword2", "polearm", "staff", "fist", "dagger", "bow", "gun",
                  "crossbow", "thrown", "cloth", "leather", "mail" }),
   ROGUE = set({ "axe1", "mace1", "sword1", "fist", "dagger", "bow", "gun", "crossbow", "thrown", "cloth",
                 "leather" }),
   PRIEST = set({ "mace1", "staff", "dagger", "wand", "cloth" }),
   DEATHKNIGHT = set({ "axe1", "axe2", "mace1", "mace2", "sword1", "sword2", "polearm", "cloth", "leather",
                       "mail", "plate", "sigil" }),
   SHAMAN = set({ "axe1", "axe2", "mace1", "mace2", "staff", "fist", "dagger", "cloth", "leather", "mail",
                  "shield", "totem" }),
   MAGE = set({ "sword1", "staff", "dagger", "wand", "cloth" }),
   WARLOCK = set({ "sword1", "staff", "dagger", "wand", "cloth" }),
   DRUID = set({ "mace1", "mace2", "staff", "fist", "dagger", "polearm", "cloth", "leather", "idol" }),
}

local ALLIANCE_RACES = { human = true, dwarf = true, nightelf = true, gnome = true, draenei = true }

-- ---------------------------------------------------------------------------
-- Katalog bauen
-- ---------------------------------------------------------------------------

-- Auktionshaus-Listen der gewaehlten Sprache (aus der Attrappe)
local function ahLists(M, locale)
   if locale == "deDE" then return M.AUCTION_DE end
   return M.AUCTION_EN
end

local function iconPath(base)
   return "Interface\\Icons\\" .. base
end

-- Legt einen Katalogeintrag an; cls = "armor" | "weapon"
local function makeRecord(cat, row, cls, id, ah, locale)
   local subTable = (cls == "weapon") and WEAPON_SUB or ARMOR_SUB
   local sub = subTable[row.sub]
   assert(sub, "Fixtures: unbekannte Unterklasse " .. tostring(row.sub))
   local x = row.x
   local key, flags = nil, {}
   if type(x) == "string" then
      key = x
   elseif type(x) == "table" then
      key = x.key
      flags = x
   end
   if row.key then key = row.key end
   local classIndex = (cls == "weapon") and 1 or 2
   local rec = {
      id = id, key = key, cls = cls, sub = row.sub, subId = sub[1], ahIndex = sub[2], inv = row.inv,
      quality = row.q, ilvl = row.ilvl, nameEN = row.en, nameDE = row.de,
      name = (locale == "deDE") and row.de or row.en,
      icon = iconPath(row.icon), uncollected = flags.unc == true, onlyClass = flags.cls,
      faction = flags.faction,
      className = ah.classes[classIndex],
      subName = ah.subclasses[classIndex] and ah.subclasses[classIndex][sub[2]] or row.sub,
      minLevel = (row.ilvl >= 200) and 80 or max(0, floor(row.ilvl / 3)),
   }
   cat.list[#cat.list + 1] = rec
   cat.byId[id] = rec
   if key then
      assert(not cat.byKey[key], "Fixtures: doppelter Schluessel " .. key)
      cat.byKey[key] = rec
   end
   cat.items[id] = {
      name = rec.name, quality = rec.quality, ilvl = rec.ilvl, minLevel = rec.minLevel,
      class = rec.className, subclass = rec.subName, equipLoc = rec.inv, icon = rec.icon,
      price = rec.ilvl * 100, maxStack = 1,
   }
   return rec
end

local function buildCatalog(M, locale)
   local ah = ahLists(M, locale)
   local cat = { list = {}, byId = {}, byKey = {}, items = {}, locale = locale }
   local nextId = 41000
   for _, row in ipairs(ARMOR_ROWS) do
      makeRecord(cat, row, "armor", nextId, ah, locale)
      nextId = nextId + 1
   end
   nextId = 42000
   for _, row in ipairs(WEAPON_ROWS) do
      makeRecord(cat, row, "weapon", nextId, ah, locale)
      nextId = nextId + 1
   end
   nextId = 49000
   for _, row in ipairs(EXTRA_ROWS) do
      local rec = makeRecord(cat, row, "armor", nextId, ah, locale)
      rec.nonTransmog = true
      nextId = nextId + 1
   end
   cat.count = #cat.list
   return cat
end

-- ---------------------------------------------------------------------------
-- Serverregeln
-- ---------------------------------------------------------------------------

local function defaultRules()
   return { lowerTiers = true, mixedArmor = false, mixedOffhand = false, mixedWeapons = 1, mixedHandedness = false }
end

local function isRanged(rec)
   return rec.cls == "weapon" and (rec.sub == "bow" or rec.sub == "gun" or rec.sub == "crossbow")
end

-- Passt der Gegenstand fuer Spieler (Klasse/Fraktion/Fertigkeit)? (SuitableForTransmogrification)
local function suitable(srv, rec)
   if rec.onlyClass and rec.onlyClass ~= srv.player.class then return false end
   if rec.faction and rec.faction ~= srv.player.faction then return false end
   if rec.sub ~= "misc" then
      local prof = PROFICIENCY[srv.player.class] or PROFICIENCY.WARRIOR
      if not prof[rec.sub] then
         if rec.cls == "armor" and not srv.rules.mixedArmor then return false end
         if rec.cls == "weapon" and srv.rules.mixedWeapons ~= 2 then return false end
      end
   end
   return true
end

-- Ruestungsstufe verfuegbar? (TierAvailable)
local function tierAvailable(srv, sub)
   if not TIER_ORDER[sub] then return false end
   local highest = HIGHEST_TIER[srv.player.class] or "cloth"
   if highest == "plate" then return true end
   if highest == "mail" then return sub ~= "plate" end
   if highest == "leather" then return sub == "leather" or sub == "cloth" end
   return sub == "cloth"
end

local WEAPON_GROUP_1H = set({ "axe1", "sword1", "mace1" })
local WEAPON_GROUP_2H = set({ "axe2", "sword2", "mace2", "staff", "polearm" })

-- Ausnahmen fuer abweichende Unterklassen (IsSubclassMismatchAllowed)
local function subclassMismatchAllowed(srv, source, target)
   local rules = srv.rules
   if target.cls == "weapon" then
      if isRanged(source) then return true end
      if rules.mixedWeapons == 1 then
         if WEAPON_GROUP_1H[target.sub] then return WEAPON_GROUP_1H[source.sub] == true end
         if WEAPON_GROUP_2H[target.sub] then return WEAPON_GROUP_2H[source.sub] == true end
      elseif rules.mixedWeapons == 2 then
         return true
      end
      if source.sub == "misc" then return source.inv == target.inv end
   else
      if rules.mixedArmor then return true end
      if rules.mixedOffhand then
         local function offhandArmor(r)
            return r.sub == "shield" or (r.sub == "misc" and r.inv == I.held)
         end
         if offhandArmor(target) and offhandArmor(source) then return true end
      end
      if rules.lowerTiers and TIER_ORDER[target.sub] and tierAvailable(srv, source.sub) then return true end
      if source.sub == "misc" then return source.inv == target.inv end
   end
   return false
end

-- Ausnahmen fuer abweichende Plaetze (IsInvTypeMismatchAllowed)
local function invMismatchAllowed(srv, source, target)
   local rules = srv.rules
   if target.cls == "weapon" then
      if isRanged(source) then return true end
      if rules.mixedWeapons == 2 then return true end
      if target.inv == I.wmain or target.inv == I.woff then
         if source.inv == I.wmain or source.inv == I.woff then return rules.mixedHandedness == true end
         if source.inv == I.w1h then return true end
      elseif target.inv == I.w1h then
         return source.inv == I.wmain or (rules.mixedHandedness == true and source.inv == I.woff)
      end
   else
      if target.inv == I.chest or target.inv == I.robe then
         return source.inv == I.chest or source.inv == I.robe
      end
   end
   return false
end

-- TransmogRules_CanTransmogrifyItemWithItem
local function canTransmog(srv, target, source)
   if source.id == target.id then return false end
   if source.icon == target.icon then return false end          -- gleiche DisplayInfo
   if source.cls ~= target.cls then return false end
   if NEVER_INV[source.inv] or NEVER_INV[target.inv] then return false end
   if not suitable(srv, target) or not suitable(srv, source) then return false end
   if isRanged(source) ~= isRanged(target) then return false end
   if source.sub ~= target.sub and not subclassMismatchAllowed(srv, source, target) then return false end
   if source.inv ~= target.inv and not invMismatchAllowed(srv, source, target) then return false end
   return true
end

-- ---------------------------------------------------------------------------
-- Serverobjekt
-- ---------------------------------------------------------------------------

local sessions = setmetatable({}, { __mode = "k" })
local lastSession = nil

local function session(T)
   local s = (T ~= nil and sessions[T]) or lastSession
   if not s then error("Fixtures: no session (Fixtures.Boot was not called)", 3) end
   return s
end

local function equippedId(S, slot)
   return S.M.world.equipment[slot + 1]
end

-- Liste und Bucket des Slots nach den Regeln des Servers
local function serverList(S, srv, slot)
   local eq = equippedId(S, slot)
   local target = eq and S.cat.byId[eq] or nil
   if not target then return {}, 0 end
   local out = {}
   for _, rec in ipairs(S.cat.list) do
      if srv.collected[rec.id] and not rec.nonTransmog and canTransmog(srv, target, rec) then
         out[#out + 1] = rec
      end
   end
   tsort(out, function(a, b)
      if a.quality ~= b.quality then return a.quality > b.quality end
      if a.nameEN ~= b.nameEN then return a.nameEN < b.nameEN end
      return a.id < b.id
   end)
   local ids = {}
   for i, rec in ipairs(out) do ids[i] = rec.id end
   local bucket = (CLASS_ID[target.cls] or 0) + (target.subId or 0)
   return ids, bucket
end

-- Entfernt eine inaktive ID aus der Liste des Slots (damit sie wirklich fehlt)
local function stripInactive(srv, slot, ids)
   local fake = srv.stored[slot]
   if not fake or not srv.inactive[slot] then return ids end
   local out = {}
   for _, id in ipairs(ids) do
      if id ~= fake then out[#out + 1] = id end
   end
   return out
end

local function newServer(S, opts)
   opts = opts or {}
   local M = S.M
   local srv = {
      stored = {}, inactive = {}, collected = {}, reject = {}, failApply = 0, drop = {},
      queue = {}, log = {}, price = opts.price or DEFAULT_PRICE, latency = 0.1, mute = false,
      chunk = 20, rules = defaultRules(), sent = 0,
   }
   srv.player = { class = S.class, faction = S.faction }
   for _, rec in ipairs(S.cat.list) do
      if not rec.uncollected and not rec.nonTransmog then srv.collected[rec.id] = true end
   end

   -- Liste des Slots: ids, bucket (mit inaktiver Ausnahme)
   function srv.List(slot)
      local ids, bucket = serverList(S, srv, slot)
      return stripInactive(srv, slot, ids), bucket
   end

   -- Status als Nachricht
   function srv.StatusMessage()
      local parts, n = {}, 0
      for slot = 0, 18 do
         local fake = srv.stored[slot]
         if fake and fake ~= 0 then
            parts[#parts + 1] = ":" .. slot .. "," .. fake
            n = n + 1
         end
      end
      if n == 0 then return "TransmogStatus:0" end
      return "TransmogStatus:" .. n .. tconcat(parts)
   end

   -- Alle Nachrichten des Stroms eines Slots: start, Stuecke zu 20, end
   function srv.StreamMessages(slot)
      local ids, bucket = srv.List(slot)
      local header = "AvailableTransmogs:" .. slot .. ":" .. bucket .. ":" .. #ids .. ":"
      local msgs = { header .. "start" }
      local i = 1
      while i <= #ids do
         local j = min(i + srv.chunk - 1, #ids)
         local part = {}
         for k = i, j do part[#part + 1] = tostring(ids[k]) end
         msgs[#msgs + 1] = header .. tconcat(part, ":")
         i = j + 1
      end
      msgs[#msgs + 1] = header .. "end"
      return msgs
   end

   -- Alle Stroeme aller 14 Slots (Reihenfolge wie der Server)
   function srv.AllStreams()
      local msgs = {}
      for _, slot in ipairs(SERVER_SLOTS) do
         for _, m in ipairs(srv.StreamMessages(slot)) do msgs[#msgs + 1] = m end
      end
      return msgs
   end

   -- Kosten fuer eine Liste {slot, id}
   function srv.CostOf(list)
      local total = 0
      for _, p in ipairs(list) do
         local id = tonumber(p[2])
         if id and id ~= 0 then total = total + ((id == HIDDEN) and 0 or srv.price) end
      end
      return total
   end

   function srv.CostMessage(list)
      local total = srv.CostOf(list)
      return "TransmogCost:" .. total .. ":" .. ((M.world.money >= total) and 1 or 0)
   end

   -- Sammlungsstand: 0 nicht gesammelt, 1 gesammelt, 2 nicht anwendbar
   function srv.CollectionState(id)
      local rec = S.cat.byId[id]
      if not rec or rec.nonTransmog then return 2 end
      return srv.collected[id] and 1 or 0
   end

   -- Antwort in die Warteschlange (Latenz)
   function srv.Emit(msg, delay)
      srv.queue[#srv.queue + 1] = { due = M.now + (delay or srv.latency), msg = msg }
      if S.driver then S.driver:Show() end
   end

   local function pay(cost)
      if cost > 0 then
         M.world.money = M.world.money - cost
         M.Fire("PLAYER_MONEY")
      end
   end

   -- Ein Befehl des Clients ("Apply:15:4711")
   function srv.Handle(text)
      srv.log[#srv.log + 1] = text
      if srv.mute then return end
      local colon = text:find(":", 1, true)
      local cmd = colon and text:sub(1, colon - 1) or text
      local args = colon and text:sub(colon + 1) or ""

      local function reply(msg)
         if srv.drop[cmd] and srv.drop[cmd] > 0 then
            srv.drop[cmd] = srv.drop[cmd] - 1
            return
         end
         srv.Emit(msg)
      end

      if cmd == "GetTransmogStatus" then
         reply(srv.StatusMessage())
      elseif cmd == "GetAvailableTransmogs" then
         for _, m in ipairs(srv.AllStreams()) do reply(m) end
      elseif cmd == "GetCollectionStatus" then
         local id = tonumber(args:match("^(%d+)$"))
         if not id or id == 0 then return end
         reply("CollectionStatus:" .. id .. ":" .. srv.CollectionState(id))
      elseif cmd == "Apply" then
         local a, b = args:match("^(%d+):(%d+)$")
         local slot, id = tonumber(a), tonumber(b)
         if not slot or not id or slot >= 19 or id == 0 then
            reply("ApplyTransmogResult:0")
            return
         end
         local ok = false
         if srv.failApply > 0 then
            srv.failApply = srv.failApply - 1
         elseif srv.stored[slot] == id then
            ok = true
         elseif not equippedId(S, slot) then
            ok = false
         elseif srv.reject[id] then
            ok = false
         elseif id == HIDDEN then
            ok = (S.hideable[slot] == true)
         else
            local list = srv.List(slot)
            local inList = false
            for _, v in ipairs(list) do
               if v == id then inList = true break end
            end
            if inList and srv.collected[id] and M.world.money >= srv.price then
               pay(srv.price)
               ok = true
            end
         end
         if ok then
            srv.stored[slot] = id
            srv.inactive[slot] = nil
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
         srv.stored[slot] = nil
         srv.inactive[slot] = nil
         reply("ApplyTransmogResult:1:" .. slot .. ",0")
      elseif cmd == "RemoveAll" then
         srv.stored = {}
         srv.inactive = {}
         reply(srv.StatusMessage())
      elseif cmd == "CalculateCost" then
         local list = {}
         for pair in args:gmatch("[^,]+") do
            local a, b = pair:match("^(%d+):(%d+)$")
            local slot, id = tonumber(a), tonumber(b)
            if slot and id and slot < 19 and id ~= 0 then list[#list + 1] = { slot, id } end
         end
         reply(srv.CostMessage(list))
      end
   end

   -- Befehl vom Client annehmen (aus dem SendAddonMessage-Haken)
   function srv.Receive(text)
      srv.sent = srv.sent + 1
      srv.Handle(text)
   end

   -- Faellige Antworten ausliefern (auch solche, die dabei neu entstehen)
   function srv.Pump()
      for _ = 1, 200 do
         local progressed = false
         local i = 1
         while i <= #srv.queue do
            local q = srv.queue[i]
            if q.due <= M.now + 1e-9 then
               table.remove(srv.queue, i)
               M.ServerMessage(q.msg)
               progressed = true
            else
               i = i + 1
            end
         end
         if not progressed then break end
      end
      if #srv.queue == 0 and S.driver then S.driver:Hide() end
   end

   return srv
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

local function hideableSlots()
   local h = {}
   for _, s in ipairs({ 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 18 }) do h[s] = true end
   return h
end

-- Client-Ausruestung (Inventar-ID -> Gegenstand) aus einem Satz
local function buildEquipment(cat, setName)
   local set_ = EQUIPMENT_SETS[setName]
   assert(set_, "Fixtures: unbekannter equipmentSet '" .. tostring(setName) .. "'")
   local eq = {}
   for slot, key in pairs(set_.slots) do
      local rec = cat.byKey[key]
      assert(rec, "Fixtures: Katalogschluessel fehlt: " .. key)
      eq[slot + 1] = rec.id
   end
   for name, key in pairs(COMMON_ACCESSORIES) do
      eq[ACCESSORY_CLIENT[name]] = cat.byKey[key].id
   end
   return eq, set_.class
end

-- Ablauf von Core\Boot.lua nachbilden, falls die Datei (noch) fehlt
local function ownBoot(T, M)
   local DB = T.DB
   if DB and DB.global and DB.char then return false end
   if not DB then return false end
   DB.Init()
   if T.Locale and T.Locale.Set then T.Locale.Set(DB.global.locale) end
   if T.RefreshPlayerInfo then T.RefreshPlayerInfo() end
   if T.Slots and T.Slots.Init then T.Slots.Init() end
   if T.Items and T.Items.Init then T.Items.Init() end
   if T.Net and T.Net.Init then T.Net.Init() end
   if T.State and T.State.Init then T.State.Init() end
   if T.Outfits and T.Outfits.Init then T.Outfits.Init() end
   if T.Tooltips and T.Tooltips.Init then T.Tooltips.Init() end
   if T.Toasts and T.Toasts.Init then T.Toasts.Init() end
   if T.UI and T.UI.Window and T.UI.Window.Init then T.UI.Window.Init() end
   T.enteredWorldAt = M.now
   return true
end

-- Schaltet die Addon-Sprache um (siehe Kopf).
function Fixtures.SetLanguage(T, code)
   if T.DB and T.DB.Set then T.DB.Set("locale", code) end
   if T.Locale and T.Locale.Set then return T.Locale.Set(code) end
   return code
end

-- Startet das Addon und liefert die Tabelle Transmog (siehe Kopf).
function Fixtures.Boot(H, opts)
   opts = opts or {}
   local M = H.mock
   local locale = opts.locale or "enUS"
   if locale ~= "enUS" and locale ~= "deDE" then
      error("Fixtures.Boot: locale must be enUS or deDE (got " .. tostring(locale) .. ")", 2)
   end
   local setName = opts.equipmentSet or "plate"
   local cat = buildCatalog(M, locale)
   local equipment, defaultClass = buildEquipment(cat, setName)
   local class = opts.class or defaultClass
   local race = opts.race or "Human"
   local screen = opts.screen or {}
   local world = {
      locale = locale, race = race, class = class,
      money = opts.money or 5000000,
      screenWidth = screen.w or screen.width or screen[1] or 1365,
      screenHeight = screen.h or screen.height or screen[2] or 768,
      equipment = equipment,
   }
   if locale == "deDE" then world.auctionLists = M.AUCTION_DE end
   if opts.uiScale then world.uiScale = opts.uiScale end
   if opts.itemCacheDelay then world.itemCacheDelay = opts.itemCacheDelay end
   if opts.playerName then world.playerName = opts.playerName end

   local T = H.boot({
      world = world, items = cat.items, login = true, enterWorld = opts.enterWorld ~= false,
      skip = opts.skip, upTo = opts.upTo, toc = opts.toc, skipMissing = true,
      globals = opts.globals or opts.savedVariables, noSeed = opts.noSeed,
   })
   assert(type(T) == "table", "Fixtures.Boot: Transmog was not loaded")
   if opts.cacheItems ~= false then M.CacheAll() end

   local own = ownBoot(T, M)
   if opts.addonLocale then Fixtures.SetLanguage(T, opts.addonLocale) end

   local raceKey = string.lower((tostring(race):gsub("[%s_%-]", "")))
   local S = {
      T = T, H = H, M = M, cat = cat, locale = locale, class = string.upper(class),
      faction = ALLIANCE_RACES[raceKey] and "A" or "H",
      setName = setName, hideable = hideableSlots(), ownBoot = own,
      itemKeys = cat.byKey,
   }
   sessions[T] = S
   lastSession = S
   return T
end

-- ---------------------------------------------------------------------------
-- Server: Hallo, Antwortschleife, Hilfen
-- ---------------------------------------------------------------------------

local function getServer(S, opts)
   if not S.server then S.server = newServer(S, opts) end
   local srv = S.server
   opts = opts or {}
   if opts.price then srv.price = opts.price end
   if opts.latency then srv.latency = opts.latency end
   if opts.rules then
      for k, v in pairs(opts.rules) do srv.rules[k] = v end
   end
   if opts.collected then
      for id, v in pairs(opts.collected) do srv.collected[id] = v and true or nil end
   end
   return srv
end

-- Katalogschluessel oder ID -> ID
local function resolveId(S, v)
   if type(v) == "number" then return v end
   local rec = S.cat.byKey[v]
   if not rec then error("Fixtures: unknown item key " .. tostring(v), 3) end
   return rec.id
end

-- Liefert das Serverobjekt (nil, wenn noch keines angelegt wurde).
function Fixtures.Server(T)
   return session(T).server
end

-- Liefert den Katalog { list, byId, byKey, items, count }.
function Fixtures.Catalog(T)
   return session(T).cat
end

-- ID zu einem Katalogschluessel.
function Fixtures.Item(T, key)
   return resolveId(session(T), key)
end

-- Liste und Bucket, wie der Server sie jetzt fuer den Slot sendet.
function Fixtures.List(T, slot)
   local S = session(T)
   local srv = getServer(S)
   return srv.List(slot)
end

-- Standardauswahl fuer ServerHello: Position in der Liste je Slot
local DEFAULT_APPLIED = {
   [SLOT.HEAD] = 2, [SLOT.SHOULDER] = 1, [SLOT.CHEST] = 1, [SLOT.MAINHAND] = 2,
}
local DEFAULT_HIDDEN = { SLOT.BACK }
local DEFAULT_INACTIVE = { [SLOT.LEGS] = "legs_inactive" }

-- Stellt den gespeicherten Zustand des Servers ein: angewendet (Position in der Liste <= 100
-- oder ID/Schluessel), verborgen, inaktiv (gespeichert, aber nicht in der Liste).
local function configureStatus(S, srv, applied, hidden, inactive)
   for slot, v in pairs(applied or {}) do
      if equippedId(S, slot) then
         local id
         if type(v) == "number" and v <= 100 then
            local ids = srv.List(slot)
            id = ids[min(v, #ids)]
         else
            id = resolveId(S, v)
         end
         if id then
            srv.stored[slot] = id
            srv.inactive[slot] = nil
         end
      end
   end
   for _, slot in ipairs(hidden or {}) do
      if equippedId(S, slot) and S.hideable[slot] then
         srv.stored[slot] = HIDDEN
         srv.inactive[slot] = nil
      end
   end
   for slot, v in pairs(inactive or {}) do
      if equippedId(S, slot) then
         srv.stored[slot] = resolveId(S, v)
         srv.inactive[slot] = true
      end
   end
end

-- Spielt Status und alle Listenstroeme ueber T.Net.Handle ab (siehe Kopf).
function Fixtures.ServerHello(T, opts)
   opts = opts or {}
   local S = session(T)
   local srv = getServer(S, opts)
   local Net = T.Net
   assert(Net and Net.Handle, "Fixtures.ServerHello: Net.Handle fehlt")

   local explicit = opts.applied ~= nil or opts.hidden ~= nil or opts.inactive ~= nil
   if not S.helloConfigured or explicit then
      S.helloConfigured = true
      local useDefaults = opts.defaults ~= false
      configureStatus(S, srv,
         opts.applied or (useDefaults and DEFAULT_APPLIED or nil),
         opts.hidden or (useDefaults and DEFAULT_HIDDEN or nil),
         opts.inactive or (useDefaults and DEFAULT_INACTIVE or nil))
   end

   if not opts.noStatus then Net.Handle(srv.StatusMessage()) end
   if not opts.noLists then
      for _, m in ipairs(srv.AllStreams()) do Net.Handle(m) end
   end
   return srv
end

-- Haengt die Antwortschleife an SendAddonMessage (siehe Kopf).
function Fixtures.ServerAutoReply(T, opts)
   opts = opts or {}
   local S = session(T)
   local srv = getServer(S, opts)
   if opts.mute ~= nil then srv.mute = opts.mute and true or false end
   if not S.driver then
      local driver = CreateFrame("Frame")
      driver:SetScript("OnUpdate", function() srv.Pump() end)
      driver:Hide()
      S.driver = driver
   end
   if rawget(_G, "SendAddonMessage") ~= S.sendHook then
      local original = rawget(_G, "SendAddonMessage")
      S.sendHook = function(prefix, msg, channel, target)
         original(prefix, msg, channel, target)
         if prefix == "transmog" and S.server and S.hookActive then S.server.Receive(msg) end
      end
      rawset(_G, "SendAddonMessage", S.sendHook)   -- lint:allow(dyn-global-write)
   end
   S.hookActive = true
   return srv
end

-- Antwortschleife wieder abhaengen (Befehle werden danach nicht mehr beantwortet).
function Fixtures.ServerStop(T)
   local S = session(T)
   S.hookActive = false
   if S.driver then S.driver:Hide() end
end

-- Zeit vorstellen und den Server bedienen.
function Fixtures.Settle(T, seconds, step)
   local S = session(T)
   local M = S.M
   local srv = S.server
   step = step or 0.05
   if srv then srv.Pump() end
   local t = 0
   while t < (seconds or 0) - 1e-9 do
      local d = min(step, seconds - t)
      M.Advance(d, d)
      t = t + d
      if srv then srv.Pump() end
   end
end

-- "Open" und GOSSIP_SHOW wie am NPC; liefert TransmogWindow (nil, wenn nichts oeffnete).
function Fixtures.OpenAtNpc(T)
   local S = session(T)
   local M = S.M
   M.OpenNpc()
   local window = rawget(_G, "TransmogWindow")
   local W = T.UI and T.UI.Window
   if not T.Boot and W and W.Open and not (W.IsShown and W.IsShown()) then
      -- ohne Core\Boot.lua: HideUIPanel(GossipFrame), danach Window.Open (SPEC 6.13)
      local gossip = rawget(_G, "GossipFrame")
      if gossip and HideUIPanel then HideUIPanel(gossip) end
      W.Open({ fromNpc = true })
      window = rawget(_G, "TransmogWindow") or W.frame
   end
   return window
end

-- Ausruestung wechseln.
function Fixtures.Equip(T, slot, idOrKey)
   local S = session(T)
   local id = resolveId(S, idOrKey)
   S.M.world.equipment[slot + 1] = id
   S.M.Fire("PLAYER_EQUIPMENT_CHANGED", slot + 1)
end

-- Slot leeren.
function Fixtures.Unequip(T, slot)
   local S = session(T)
   S.M.world.equipment[slot + 1] = nil
   S.M.Fire("PLAYER_EQUIPMENT_CHANGED", slot + 1)
end

-- Aussehen sammeln und dem Client melden (CollectionUpdated).
function Fixtures.Collect(T, idOrKey)
   local S = session(T)
   local srv = getServer(S)
   local id = resolveId(S, idOrKey)
   srv.collected[id] = true
   srv.Emit("CollectionUpdated:" .. id, 0)
   srv.Pump()
   return id
end

-- CollectionStatus-Antwort abspielen (direkt ueber Net.Handle).
function Fixtures.CollectionStatus(T, idOrKey)
   local S = session(T)
   local srv = getServer(S)
   local id = resolveId(S, idOrKey)
   S.T.Net.Handle("CollectionStatus:" .. id .. ":" .. srv.CollectionState(id))
   return srv.CollectionState(id)
end

-- TransmogCost-Antwort fuer { {slot, id}, ... } abspielen.
function Fixtures.Cost(T, list)
   local S = session(T)
   local srv = getServer(S)
   local msg = srv.CostMessage(list or {})
   S.T.Net.Handle(msg)
   return msg
end

-- Einen Teil des Katalogs wieder "unbekannt" machen. fraction (0..1) oder fn(rec) -> bool.
-- Ausgeruestete Gegenstaende bleiben bekannt (die Attrappe gilt sie immer als gecacht).
function Fixtures.Uncache(T, spec)
   local S = session(T)
   local n, total = 0, 0
   for i, rec in ipairs(S.cat.list) do
      total = total + 1
      local drop
      if type(spec) == "function" then
         drop = spec(rec, i)
      else
         local fraction = tonumber(spec) or 1
         drop = ((i * 37) % 100) < floor(fraction * 100)
      end
      if drop then
         S.M.UncacheItem(rec.id)
         n = n + 1
      end
   end
   return n, total
end

-- n bekannte Aussehen je Slot (erste n Eintraege der Serverliste): { [slot] = id }
function Fixtures.Looks(T, n, offset)
   local S = session(T)
   local srv = getServer(S)
   local out = {}
   for _, slot in ipairs(SERVER_SLOTS) do
      local ids = srv.List(slot)
      local id = ids[(offset or 0) + (n or 1)]
      if id then out[slot] = id end
   end
   return out
end

Fixtures.HIDDEN = HIDDEN

return Fixtures
