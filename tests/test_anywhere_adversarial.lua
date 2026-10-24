-- tests/test_anywhere_adversarial.lua
-- ---------------------------------------------------------------------------
-- Gegenprobe zu "Transmoggen ueberall" (seit 2.1): Tests, die die einmalige
-- Umstellung von global.allowAnywhere (Marke global.noNpcDefault) und die Wege
-- drumherum angreifen, statt sie zu bestaetigen.
--
--     luajit tests/run.lua anywhere_adversarial
--
-- Aufbau:
--   1. Umstellung (DB.Init): typische Datei der Version 2.0, Wahrheitstabelle ueber
--      alle Marken x Werte, Zufallsfolgen aus Init / Set / Abmelden / Anmelden,
--      zweiter Charakter, Reihenfolge Set vor Init, Zusammenspiel mit der
--      Altdaten-Uebernahme (char.migrated), DB_VERSION
--   2. Oberflaeche und Zustand: Fenster am NPC und per /transmog, Weglaufen
--      (GOSSIP_CLOSED), Absage des Servers beim Anwenden ohne NPC, Umschalten
--      der Option mitten im Anwenden, Hinweisleiste gegen CanApply/CanRemoveAll
--      ueber alle Zustaende, Versionsangaben, Tooltip-Wahrheit in allen Sprachen
--
-- Alle Tests starten mit noSeed = true (Neuinstallation = die echte Vorgabe 2.1)
-- oder liefern ihre eigene TransmogGlobalDB: das Boot-Seed von H.boot
-- ({ noNpcDefault = true, allowAnywhere = false }) wuerde sonst die Umstellung
-- verdecken.
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local Fixtures = require("fixtures")

   local BASE_UPTO = "Core\\Slots.lua"
   local NAN = 0 / 0

   -- -----------------------------------------------------------------------
   -- Hilfen
   -- -----------------------------------------------------------------------

   local function deepCopy(v)
      if type(v) ~= "table" then return v end
      local out = {}
      for k, x in pairs(v) do out[deepCopy(k)] = deepCopy(x) end
      return out
   end

   -- Laedt die Basismodule (bis Slots) ohne Boot-Seed; DB.Init ruft der Test selbst.
   local function boot(globals)
      local T = H.boot({ upTo = BASE_UPTO, login = false, noSeed = true, globals = deepCopy(globals) })
      H.assert(type(T) == "table", "Transmog wurde nicht geladen")
      return T
   end

   -- Was der Spieler nach einem Init sehen muss: einmalig an (Marke fehlt oder ist unbrauchbar), sonst seine Wahl,
   -- ein unbrauchbarer Wert wird zur Vorgabe (an).
   local function expectedAllow(flag, value)
      if flag ~= true then return true end
      if type(value) == "boolean" then return value end
      return true
   end

   local function describe(v)
      if v ~= v then return "NaN" end
      if type(v) == "table" then return "{}" end
      return type(v) .. ":" .. tostring(v)
   end

   -- Einfacher, wiederholbarer Zufallsgenerator (Park-Miller): rng(n) = 1..n
   local function newRng(seed)
      local s = seed
      return function(n)
         s = (s * 16807) % 2147483647
         return (s % n) + 1
      end
   end

   -- -----------------------------------------------------------------------
   -- 1. Umstellung
   -- -----------------------------------------------------------------------

   -- Nachbau einer typischen Datei der Version 2.0 (kontoweite Einstellungen mit dem
   -- frueheren Standard allowAnywhere = false, dazu die Datei eines Charakters, ohne Marke):
   -- hermetisch, der Test liest nie echte WTF-Dateien.
   local function ownerFiles()
      return {
         TransmogGlobalDB = {
            tooltipApplied = true,
            point = { "TOPLEFT", "BOTTOMLEFT", 40, 900 },
            previewSize = 1,
            lastTab = "items",
            width = 900,
            locale = "auto",
            toasts = true,
            version = 2,
            sound = true,
            height = 600,
            allowAnywhere = false,
            tooltipCollected = true,
            scale = 0,
         },
         TransmogDB = {
            lastSlot = 15,
            version = 2,
            favorites = {},
            filter = {
               hideDuplicates = true, qualities = {}, sort = "QUALITY",
               favoritesOnly = false, newOnly = false, typesOff = {},
            },
            outfits = {},
            migrated = 2,
         },
         transmogOutfits = {},
      }
   end

   H.test("Adversarial: eine typische Datei aus 2.0 (allowAnywhere=false) wird einmal auf an gestellt, sonst bleibt alles", function()
      local files = ownerFiles()
      local T = boot(files)
      local g, c = T.DB.Init()
      H.eq(g.allowAnywhere, true, "einmalig an")
      H.eq(g.noNpcDefault, true, "Marke")
      -- jeder andere Wert ist unveraendert (Position, Groesse, Sprache ...)
      local want = ownerFiles().TransmogGlobalDB
      want.allowAnywhere = true
      want.noNpcDefault = true
      H.deepEq(g, want, "TransmogGlobalDB bis auf die zwei Schluessel unveraendert")
      -- die Charakterdatei: keine Marke dort, nichts neu uebernommen
      H.eq(c.migrated, 2)
      H.eq(c.noNpcDefault, nil, "die Marke gehoert ins kontoweite Global, nicht in den Charakter")
      H.eq(c.lastSlot, 15)
      H.len(c.outfits, 0)

      -- der Spieler schaltet es aus und meldet sich dreimal neu an: bleibt aus
      T.DB.Set("allowAnywhere", false)
      local sv = M.SavedVariables()
      for session = 1, 3 do
         local Tn = boot(sv)
         local gn = Tn.DB.Init()
         H.eq(gn.allowAnywhere, false, "Sitzung " .. session)
         H.eq(gn.noNpcDefault, true)
         sv = M.SavedVariables()
      end
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Adversarial: Wahrheitstabelle Marke x Wert (6 x 8), zweimal Init, danach Set(false) gewinnt immer", function()
      local flags = {
         { "fehlt", nil }, { "true", true }, { "false", false }, { "Text", "true" }, { "1", 1 }, { "Tabelle", {} },
      }
      local values = {
         { "fehlt", nil }, { "true", true }, { "false", false }, { "Text", "x" }, { "0", 0 }, { "1", 1 },
         { "Tabelle", {} }, { "NaN", NAN },
      }
      local cases = 0
      for _, f in ipairs(flags) do
         for _, v in ipairs(values) do
            cases = cases + 1
            local label = "Marke " .. f[1] .. " / Wert " .. v[1]
            local db = { version = 2 }
            db.noNpcDefault = deepCopy(f[2])
            db.allowAnywhere = deepCopy(v[2])
            local T = boot({ TransmogGlobalDB = db })
            local g = T.DB.Init()
            local want = expectedAllow(f[2], v[2])
            H.eq(g.allowAnywhere, want, label .. ": nach Init")
            H.eq(g.noNpcDefault, true, label .. ": Marke danach immer true")
            T.DB.Init()
            H.eq(g.allowAnywhere, want, label .. ": zweiter Init aendert nichts")
            -- die Wahl des Spielers gewinnt gegen jede weitere Init-Runde
            T.DB.Set("allowAnywhere", false)
            T.DB.Init()
            T.DB.Init()
            H.eq(g.allowAnywhere, false, label .. ": Set(false) bleibt")
            -- und ueber das Abmelden hinweg
            local Tn = boot(M.SavedVariables())
            H.eq(Tn.DB.Init().allowAnywhere, false, label .. ": nach Neuanmeldung")
         end
      end
      H.eq(cases, 48)
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Adversarial: Zufallsfolgen aus Init, Set, SetChar, Abmelden/Anmelden, neuer Charakter - die Option kippt nie von selbst", function()
      for seed = 1, 6 do
         local rng = newRng(seed * 7919)
         -- Start: eine typische Datei aus 2.0, eine Neuinstallation oder eine Datei mit Marke und false
         local start = rng(3)
         local files
         local model            -- was der Spieler erwartet
         if start == 1 then
            files = ownerFiles()
            model = true       -- einmalig an
         elseif start == 2 then
            files = {}
            model = true
         else
            files = ownerFiles()
            files.TransmogGlobalDB.noNpcDefault = true
            model = false
         end
         local T = boot(files)
         T.DB.Init()
         H.eq(T.DB.global.allowAnywhere, model, "Seed " .. seed .. ": Start")
         local trace = {}
         for step = 1, 80 do
            local op = rng(9)
            if op == 1 then
               trace[#trace + 1] = "Init"
               T.DB.Init()
            elseif op == 2 then
               trace[#trace + 1] = "Set(false)"
               T.DB.Set("allowAnywhere", false)
               model = false
            elseif op == 3 then
               trace[#trace + 1] = "Set(true)"
               T.DB.Set("allowAnywhere", true)
               model = true
            elseif op == 4 then
               trace[#trace + 1] = "Set(Muell)"
               T.DB.Set("allowAnywhere", ({ "x", 0, {}, NAN, nil })[rng(5)])
               model = true      -- unbrauchbar -> Vorgabe an
            elseif op == 5 then
               trace[#trace + 1] = "Set(scale)"
               T.DB.Set("scale", 0.6 + rng(9) / 10)
            elseif op == 6 then
               trace[#trace + 1] = "SetChar"
               T.DB.SetChar("lastSlot", ({ 0, 2, 15, 99 })[rng(4)])
            elseif op == 7 then
               trace[#trace + 1] = "Abmelden/Anmelden"
               T = boot(M.SavedVariables())
               T.DB.Init()
            elseif op == 8 then
               -- anderer Charakter desselben Kontos: kontoweit geladen, eigene (leere) Charakterdatei
               trace[#trace + 1] = "anderer Charakter"
               local sv = M.SavedVariables()
               T = boot({ TransmogGlobalDB = sv.TransmogGlobalDB })
               T.DB.Init()
            else
               trace[#trace + 1] = "Muell in unbekanntem Schluessel"
               T.DB.Set("irgendwas", { 1, 2, 3 })
            end
            H.eq(T.DB.global.allowAnywhere, model,
               "Seed " .. seed .. " Schritt " .. step .. " nach " .. trace[#trace])
            H.eq(T.DB.global.noNpcDefault, true)
         end
      end
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Adversarial: zweiter Charakter des Kontos: die Umstellung gilt kontoweit, ein Ausschalten bleibt auch dort aus", function()
      -- Charakter A (Datei aus 2.0) meldet sich zuerst an und schaltet die Option aus
      local files = ownerFiles()
      local A = boot(files)
      A.DB.Init()
      A.DB.Set("allowAnywhere", false)
      local svA = M.SavedVariables()
      H.eq(svA.TransmogGlobalDB.allowAnywhere, false)
      -- Charakter B: eigene Charakterdatei (alt oder leer), aber DIESELBE kontoweite Datei
      local variants = {
         { name = "ohne Charakterdatei", char = nil },
         { name = "alte Charakterdatei (migrated = 0)", char = { version = 1, migrated = 0 } },
         { name = "Charakterdatei aus 2.0", char = ownerFiles().TransmogDB },
      }
      for _, v in ipairs(variants) do
         local B = boot({ TransmogGlobalDB = svA.TransmogGlobalDB, TransmogDB = v.char })
         local g, c = B.DB.Init()
         H.eq(g.allowAnywhere, false, v.name .. ": bleibt aus")
         H.eq(c.noNpcDefault, nil, v.name .. ": die Charakterdatei traegt keine Marke")
      end
   end)

   H.test("Adversarial: Set und SetChar VOR Init (EnsureInit): die Umstellung laeuft trotzdem genau einmal, die Wahl bleibt", function()
      -- Set vor Init: die Option wird erst von EnsureInit umgestellt, dann gesetzt
      local T = boot(ownerFiles())
      H.eq(T.DB.global, nil, "noch kein Init")
      T.DB.Set("allowAnywhere", false)
      H.eq(T.DB.global.allowAnywhere, false)
      H.eq(T.DB.global.noNpcDefault, true, "EnsureInit hat die Marke gesetzt")
      T.DB.Init()
      H.eq(T.DB.global.allowAnywhere, false, "ein spaeteres Init (Boot.OnAddonLoaded) macht es nicht wieder an")
      -- SetChar vor Init
      local T2 = boot(ownerFiles())
      T2.DB.SetChar("lastSlot", 0)
      H.eq(T2.DB.global.allowAnywhere, true, "umgestellt durch EnsureInit")
      H.eq(T2.DB.global.noNpcDefault, true)
      T2.DB.Set("allowAnywhere", false)
      T2.DB.Init()
      H.eq(T2.DB.global.allowAnywhere, false)
      -- Set eines anderen Schluessels vor Init und dann die Option
      local T3 = boot({})
      T3.DB.Set("scale", 1.2)
      H.eq(T3.DB.global.noNpcDefault, true)
      T3.DB.Set("allowAnywhere", false)
      T3.DB.Init()
      H.eq(T3.DB.global.allowAnywhere, false)
      H.eq(T3.DB.global.scale, 1.2)
   end)

   H.test("Adversarial: Altdaten-Uebernahme (char.migrated) und Umstellung sind unabhaengig; DB_VERSION bleibt 2", function()
      local legacy = {
         transmogOutfits = { Tank = { [1] = 111, [5] = 222 }, Heiler = { [1] = 333 } },
         transmogSettings = { hideDuplicates = false },
      }
      local migratedValues = { 0, 1, 2, 3, "x", NAN, math.huge }
      local flagValues = { { "fehlt", nil }, { "true", true } }
      for _, f in ipairs(flagValues) do
         for _, mv in ipairs(migratedValues) do
            local label = "Marke " .. f[1] .. " / migrated " .. describe(mv)
            local files = deepCopy(legacy)
            files.TransmogGlobalDB = { version = 2, allowAnywhere = false, noNpcDefault = f[2] }
            files.TransmogDB = { version = 2, migrated = deepCopy(mv) }
            local T = boot(files)
            local g, c = T.DB.Init()
            -- Umstellung nach Wahrheitstabelle (allowAnywhere = false gespeichert): mit Marke bleibt die Wahl (false)
            local wantAllow = true
            if f[2] == true then wantAllow = false end
            H.eq(g.allowAnywhere, wantAllow, label .. ": allowAnywhere")
            -- Uebernahme: nur wenn migrated keine Zahl >= 2 ist
            local shouldImport = not (type(mv) == "number" and mv == mv and mv ~= math.huge and mv >= 2)
            if mv == math.huge then shouldImport = true end   -- unendlich zaehlt als "nie migriert"
            H.eq(#c.outfits, shouldImport and 2 or 0, label .. ": Outfits uebernommen")
            -- (eine Zahl >= 2, etwa von einer spaeteren Version, bleibt unangetastet)
            H.eq(c.migrated, shouldImport and 2 or mv, label .. ": migrated danach")
            H.eq(g.version, 2, label .. ": DB_VERSION unveraendert")
            H.eq(c.version, 2)
            -- zweiter Lauf: nichts doppelt
            T.DB.Init()
            H.eq(#c.outfits, shouldImport and 2 or 0, label .. ": zweiter Init uebernimmt nicht noch einmal")
         end
      end
      H.eq(#H.takeErrors(), 0)
   end)

   H.test("Adversarial: Version 1 der kontoweiten Datei, Muellwerte und leeres Global werden zusammen sauber umgestellt", function()
      local T = boot({ TransmogGlobalDB = { version = 1, allowAnywhere = false } })
      local g = T.DB.Init()
      H.eq(g.version, 2)
      H.eq(g.allowAnywhere, true)
      H.eq(g.noNpcDefault, true)
      -- ein leeres Global (z. B. nach manuellem Loeschen der Datei) ist eine Neuinstallation
      local T2 = boot({ TransmogGlobalDB = {} })
      local g2 = T2.DB.Init()
      H.eq(g2.allowAnywhere, true)
      H.eq(g2.noNpcDefault, true)
      -- die Marke selbst wird nicht von der Pruefung entfernt (SanitizeGlobal kennt nur bekannte Schluessel)
      T2.DB.Set("scale", 99)
      H.eq(g2.scale, 1.5)
      H.eq(g2.noNpcDefault, true)
   end)
   -- -----------------------------------------------------------------------
   -- 2. Oberflaeche und Zustand (echter Kern, echte Komponenten, Server-Nachbau)
   -- -----------------------------------------------------------------------

   local HEAD, SHOULDER = 0, 2

   local FX, srv

   -- Startet Addon und Server als Neuinstallation (Vorgabe 2.1: ueberall anwenden).
   local function bootUi(o)
      o = o or {}
      if o.noSeed == nil then o.noSeed = true end
      FX = Fixtures.Boot(H, o)
      Fixtures.ServerHello(FX)
      srv = Fixtures.ServerAutoReply(FX, { price = o.price })
      return FX
   end

   local function settle(seconds) Fixtures.Settle(FX, seconds or 0.5) end
   local function Win() return FX.UI.Window end
   local function F() return FX.UI.Window.frame end
   local function LL() return FX.L end
   local function status() return F().statusText:GetText() or "" end

   -- n-te sichtbare Item-Zelle des Rasters
   local function itemCell(n)
      local k = 0
      for _, c in ipairs(FX.UI.Grid.cells) do
         if c:IsShown() and c.kind == "item" then
            k = k + 1
            if k == n then return c end
         end
      end
      return nil
   end

   -- Fenster ist zu, kein OnUpdate, kein Timer
   local function assertQuiet(label)
      H.falsy(Win().IsShown(), label .. ": Fenster zu")
      settle(25)
      local names = {}
      for _, f in ipairs(M.UpdateFrames()) do names[#names + 1] = f.__name or M.U.describe(f) end
      H.deepEq(names, {}, label .. ": aktive OnUpdate-Frames")
      H.eq(FX.Util.TimerCount(), 0, label .. ": Timer")
      H.eq(#M.errors, 0, label .. ": Handlerfehler " .. tostring(M.errors[1]))
   end

   H.test("Adversarial: NPC-Ablauf mit Vorgabe an: Fenster ohne Leiste, Weglaufen schliesst; /transmog-Fenster bleibt offen", function()
      bootUi()
      H.eq(FX.DB.global.allowAnywhere, true)
      -- am NPC
      local w = Fixtures.OpenAtNpc(FX)
      settle(1.0)
      H.truthy(w)
      H.truthy(Win().IsShown())
      H.eq(FX.State.openedByNpc, true)
      H.eq(FX.State.atVendor, true)
      H.falsy(F().notice:IsShown(), "keine Leiste am NPC")
      H.falsy(GossipFrame:IsShown(), "das Gossip-Fenster ist ersetzt")
      -- weglaufen: das Gespraech endet, das Fenster schliesst (nach der Schonfrist)
      M.Advance(2)
      M.Fire("GOSSIP_CLOSED")
      H.falsy(Win().IsShown(), "Weglaufen schliesst das NPC-Fenster")
      H.eq(FX.State.openedByNpc, false)
      H.eq(FX.State.atVendor, false)
      H.eq(M.world.gossipOpen, false)

      -- per /transmog geoeffnet: ein fremdes GOSSIP_CLOSED (anderer NPC) schliesst nichts
      M.Slash("/transmog")
      settle(1.0)
      H.truthy(Win().IsShown())
      H.eq(FX.State.openedByNpc, false)
      H.falsy(F().notice:IsShown(), "ohne NPC keine Leiste")
      M.Advance(5)
      M.Fire("GOSSIP_CLOSED")
      H.truthy(Win().IsShown(), "ein /transmog-Fenster bleibt offen")

      -- den NPC ansprechen, waehrend das /transmog-Fenster offen ist: wird zum NPC-Fenster ...
      M.OpenNpc()
      settle(0.5)
      H.truthy(Win().IsShown())
      H.eq(FX.State.openedByNpc, true, "uebernommen")
      H.eq(FX.State.atVendor, true)
      -- ... und schliesst dann beim Weglaufen
      M.Advance(2)
      M.Fire("GOSSIP_CLOSED")
      H.falsy(Win().IsShown())
      H.eq(FX.State.atVendor, false)
      assertQuiet("NPC-Ablauf")
   end)

   H.test("Adversarial: Anwenden ohne NPC, Server lehnt ab (Geld/Regel): Statuszeile meldet es, Stapel endet, Knopf wieder frei", function()
      bootUi({ price = 100000 })
      M.Slash("/transmog")
      settle(1.0)
      H.truthy(Win().IsShown())
      H.eq(FX.State.atVendor, false)
      local c = itemCell(1)
      H.truthy(c)
      local id = c.itemId
      M.Click(c)
      settle(0.8)
      H.eq(FX.State.Wanted(HEAD), id)
      H.eq(F().btnApply.uiOff, false, "Anwenden frei")

      -- der Server lehnt die naechste Anwendung ab (ApplyTransmogResult:0): die Rueckmeldung ist verstaendlich
      srv.failApply = 1
      M.ClearSent()
      M.Click(F().btnApply)
      settle(1.5)
      H.eq(M.CountSent("Apply"), 1, "Apply ging an den Server")
      H.eq(FX.State.Busy(), false, "Stapel beendet, nichts haengt")
      H.eq(FX.State.Applied(HEAD) == id, false, "nicht als angewendet gemerkt")
      H.eq(FX.State.Wanted(HEAD), id, "Auswahl bleibt vorgemerkt")
      local failedPattern = "^" .. LL().MSG_APPLY_SLOT_FAILED:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", ".+") .. "$"
      H.truthy(status():find(failedPattern), "Statuszeile nennt den Fehlschlag (Slot nicht angewendet): " .. status())
      H.eq(F().btnApply.uiOff, false, "Anwenden wieder frei")
      H.eq(#FX.State.PendingSlots(), 1)
      -- ein zweiter Versuch klappt
      M.Click(F().btnApply)
      settle(1.5)
      H.eq(FX.State.Applied(HEAD), id)
      H.eq(FX.State.Busy(), false)
      H.eq(status(), LL().MSG_APPLY_OK)

      -- ein dauerhaft abgelehntes Aussehen (Regel): jede Runde derselbe saubere Fehlschlag, nie ein Haenger
      local c2 = itemCell(2)
      H.truthy(c2)
      srv.reject[c2.itemId] = true
      M.Click(c2)
      settle(0.8)
      for round = 1, 3 do
         M.Click(F().btnApply)
         settle(1.5)
         H.eq(FX.State.Busy(), false, "Runde " .. round)
         H.eq(F().btnApply.uiOff, false, "Runde " .. round)
      end
      H.eq(#M.errors, 0, tostring(M.errors[1]))
      M.Escape()
      assertQuiet("Absage")
   end)

   H.test("Adversarial: Option mitten im Anwenden ausschalten: der Stapel endet sauber, danach gilt die Sperre; wieder an: frei", function()
      bootUi({ price = 100000 })
      M.Slash("/transmog")
      settle(1.0)
      -- zwei Slots vormerken
      local function freshCell()
         for n = 1, 12 do
            local c = itemCell(n)
            if c and not c.applied then return c end
         end
      end
      local cHead = freshCell()
      H.truthy(cHead)
      M.Click(cHead)
      settle(0.5)
      local headId = cHead.itemId
      M.Click(FX.UI.SlotBar.Get().buttons[SHOULDER])
      settle(0.8)
      local cSh = freshCell()
      H.truthy(cSh)
      M.Click(cSh)
      settle(0.5)
      H.eq(#FX.State.PendingSlots(), 2)
      H.eq(F().btnApply.uiOff, false)
      M.Click(F().btnApply)
      H.eq(FX.State.Busy(), true)
      -- mitten im Stapel schaltet der Spieler die Option aus
      FX.DB.Set("allowAnywhere", false)
      settle(2.0)
      H.eq(FX.State.Busy(), false, "Stapel zu Ende")
      H.eq(FX.State.Applied(HEAD), headId, "der laufende Stapel wurde nicht abgebrochen")
      H.eq(#FX.State.PendingSlots(), 0)
      H.truthy(F().notice:IsShown(), "gelbe Leiste")
      H.eq(F().notice.text:GetText(), LL().MSG_NO_VENDOR)
      -- neue Auswahl: gesperrt mit dem Grund VENDOR
      local c3 = freshCell()
      H.truthy(c3)
      M.Click(c3)
      settle(0.8)
      H.eq(#FX.State.PendingSlots(), 1)
      H.eq(F().btnApply.uiOff, true)
      H.eq(F().btnApply.disabledTip, LL().APPLY_REASON_VENDOR)
      H.eq(select(2, FX.State.CanApply()), "APPLY_REASON_VENDOR")
      -- ein Klick auf das gesperrte Anwenden sendet nichts
      M.ClearSent()
      M.Click(F().btnApply)
      settle(0.5)
      H.eq(M.CountSent("Apply"), 0)
      -- wieder an: frei, Leiste weg
      FX.DB.Set("allowAnywhere", true)
      settle(0.3)
      H.falsy(F().notice:IsShown())
      H.eq(F().btnApply.uiOff, false)
      M.Click(F().btnApply)
      settle(1.5)
      H.eq(FX.State.Busy(), false)
      H.eq(#FX.State.PendingSlots(), 0)
      M.Escape()
      assertQuiet("mitten im Anwenden")
   end)

   H.test("Adversarial: Hinweisleiste, CanApply und CanRemoveAll stimmen in allen 16 Zustaenden (Option x NPC x Server x Vormerkung) ueberein", function()
      bootUi({ price = 100000 })
      M.Slash("/transmog")
      settle(1.0)
      local c = itemCell(1)
      M.Click(c)
      settle(0.8)
      H.eq(#FX.State.PendingSlots(), 1)
      local pendingWanted = FX.State.Wanted(HEAD)
      local cases = 0
      for _, anywhere in ipairs({ true, false }) do
         for _, atVendor in ipairs({ true, false }) do
            for _, absent in ipairs({ true, false }) do
               for _, pending in ipairs({ true, false }) do
                  cases = cases + 1
                  local label = ("Option=%s NPC=%s Server=%s Vormerkung=%s"):format(
                     tostring(anywhere), tostring(atVendor), absent and "stumm" or "ok", tostring(pending))
                  -- Zustand herstellen (der Server antwortet im Settle und setzt Net.state auf OK: ABSENT erst danach)
                  FX.Net.state = "OK"
                  FX.DB.Set("allowAnywhere", anywhere)
                  FX.State.SetVendor(atVendor)
                  if pending then
                     if FX.State.Wanted(HEAD) ~= pendingWanted then FX.State.Select(HEAD, pendingWanted) end
                  else
                     FX.State.DiscardAll()
                  end
                  settle(0.6)
                  if absent then FX.Net.state = "ABSENT" end
                  Win().RefreshNotice()
                  Win().RefreshFooter()
                  -- Hinweisleiste
                  local wantNotice
                  if absent then
                     wantNotice = LL().MSG_SERVER_ABSENT
                  elseif not atVendor and not anywhere then
                     wantNotice = LL().MSG_NO_VENDOR
                  end
                  if wantNotice then
                     H.truthy(F().notice:IsShown(), label .. ": Leiste da")
                     H.eq(F().notice.text:GetText(), wantNotice, label .. ": Leistentext")
                  else
                     H.falsy(F().notice:IsShown(), label .. ": keine Leiste")
                  end
                  -- CanApply: Reihenfolge SERVER, NONE, BUSY, VENDOR, ...
                  local ok, reason = FX.State.CanApply()
                  if absent then
                     H.eq(reason, "APPLY_REASON_SERVER", label .. ": CanApply")
                  elseif not pending then
                     H.eq(reason, "APPLY_REASON_NONE", label .. ": CanApply")
                  elseif not atVendor and not anywhere then
                     H.eq(reason, "APPLY_REASON_VENDOR", label .. ": CanApply")
                  else
                     H.eq(ok, true, label .. ": CanApply frei (" .. tostring(reason) .. ")")
                  end
                  -- CanRemoveAll: SERVER, BUSY, VENDOR
                  local rok, rreason = FX.State.CanRemoveAll()
                  if absent then
                     H.eq(rreason, "APPLY_REASON_SERVER", label .. ": CanRemoveAll")
                  elseif not atVendor and not anywhere then
                     H.eq(rreason, "APPLY_REASON_VENDOR", label .. ": CanRemoveAll")
                  else
                     H.eq(rok, true, label .. ": CanRemoveAll frei")
                  end
                  -- Knopf und Tooltip des Knopfs sagen dasselbe wie CanApply
                  H.eq(F().btnApply.uiOff, not ok, label .. ": Knopf Anwenden")
               end
            end
         end
      end
      H.eq(cases, 16)
      H.eq(#M.errors, 0, tostring(M.errors[1]))
   end)

   H.test("Adversarial: 40 x Fenster per /transmog auf und zu mit Vorgabe an: keine Timer, kein OnUpdate, kein Fehler", function()
      bootUi()
      for i = 1, 40 do
         M.Slash("/transmog")
         if i % 3 == 0 then settle(0.2) end
         H.truthy(Win().IsShown(), "auf " .. i)
         H.falsy(F().notice:IsShown(), "keine Leiste " .. i)
         M.Slash("/transmog")
         H.falsy(Win().IsShown(), "zu " .. i)
      end
      assertQuiet("Auf/Zu")
   end)

   -- -----------------------------------------------------------------------
   -- Texte, Versionen
   -- -----------------------------------------------------------------------

   local LOCALES = { "enUS", "deDE", "frFR", "esES", "ruRU", "koKR", "zhCN", "zhTW" }

   -- Der Name des Vorschau-Modus, wie ihn die gelbe Leiste nennt: der Text vor dem ersten Trenner.
   local function previewTerm(msg)
      local cut = #msg + 1
      for _, sep in ipairs({ " - ", ": ", "\239\188\154" }) do   -- U+FF1A (Volle Breite Doppelpunkt)
         local at = msg:find(sep, 1, true)
         if at and at < cut then cut = at end
      end
      return (msg:sub(1, cut - 1))
   end

   H.test("Adversarial: Tooltip der Option in allen 8 Sprachen: Server prueft nicht, Vorgabe an, /transmog, Vorschau-Modus wie die Leiste", function()
      local DEFAULT_WORD = {
         enUS = "default", deDE = "Vorgabe", frFR = "par d\195\169faut", esES = "por defecto",
         ruRU = "\208\191\208\190 \209\131\208\188\208\190\208\187\209\135\208\176\208\189\208\184\209\142",
         koKR = "\234\184\176\235\179\184\234\176\146", zhCN = "\233\187\152\232\174\164", zhTW = "\233\160\144\232\168\173",
      }
      bootUi()
      for _, code in ipairs(LOCALES) do
         Fixtures.SetLanguage(FX, code)
         local L = FX.L
         local tip, bar = L.OPT_ALLOW_ANYWHERE_TIP, L.MSG_NO_VENDOR
         H.eq(type(tip), "string", code)
         H.truthy(#tip > 40, code .. ": Tooltip nicht leer")
         local term = previewTerm(bar)
         H.truthy(#term >= 6, code .. ": Name des Vorschau-Modus gefunden: " .. term)
         H.truthy(FX.Util.Lower(tip):find(FX.Util.Lower(term), 1, true) ~= nil,
            code .. ": Tooltip nennt '" .. term .. "' wie die Leiste")
         H.truthy(tip:find("/transmog", 1, true) ~= nil, code .. ": nennt /transmog")
         H.truthy(tip:find(DEFAULT_WORD[code], 1, true) ~= nil, code .. ": nennt die Vorgabe (" .. DEFAULT_WORD[code] .. ")")
         -- nur der Haken-Text selbst darf die alte Aussage nicht mehr tragen
         H.eq(L.OPT_ALLOW_ANYWHERE_TIP ~= nil and L.OPT_ALLOW_ANYWHERE ~= nil, true)
      end
      H.eq(#M.errors, 0, tostring(M.errors[1]))
   end)

   H.test("Adversarial: Versionsangaben stimmen ueberein (TOC, T.VERSION, Chatzeile, Handbuch, README) und DB_VERSION bleibt 2", function()
      bootUi()
      local toc = M.toc and M.toc.meta and M.toc.meta.Version
      H.eq(toc, "2.1", "TOC")
      H.eq(FX.VERSION, "2.1", "T.VERSION")
      H.eq(toc, FX.VERSION)
      local found
      for _, line in ipairs(M.messages) do
         if tostring(line):find("Transmog 2.1", 1, true) then found = line end
      end
      H.truthy(found, "die Anmeldezeile nennt 2.1")
      for _, line in ipairs(M.messages) do
         H.falsy(tostring(line):find("Transmog 2.0", 1, true), "keine Zeile mit 2.0")
      end
      -- Handbuch (docs/MANUAL.de.md): nennt die aktuelle Version in der Anmeldezeile und die Marke
      local f = io.open(H.root .. "/docs/MANUAL.de.md", "rb")
      H.truthy(f, "Handbuch lesbar")
      if f then
         local text = f:read("*a")
         f:close()
         H.truthy(text:find("Zeile \"Transmog 2.1", 1, true) ~= nil, "Handbuch: Anmeldezeile Transmog 2.1")
         H.falsy(text:find("Zeile \"Transmog 2.0", 1, true), "Handbuch: keine Anmeldezeile mit 2.0 mehr")
         H.truthy(text:find("noNpcDefault", 1, true) ~= nil, "Handbuch nennt die Marke")
      end
      -- kurze README.md: nennt die Version und den Befehl
      local r = io.open(H.root .. "/README.md", "rb")
      H.truthy(r, "README lesbar")
      if r then
         local text = r:read("*a")
         r:close()
         H.truthy(text:find("2.1", 1, true) ~= nil, "README nennt Version 2.1")
         H.truthy(text:find("/transmog", 1, true) ~= nil, "README nennt /transmog")
         H.falsy(text:find("Version 2.0", 1, true), "README: keine veraltete Versionsangabe")
      end
      H.eq(FX.DB.global.version, 2)
      H.eq(FX.DB.char.version, 2)
   end)
end
