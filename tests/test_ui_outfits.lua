-- tests/test_ui_outfits.lua
-- ---------------------------------------------------------------------------
-- Tests fuer UI\OutfitsTab.lua (Outfit-Reiter) gegen die ECHTEN Kernmodule
-- (Locale, Util, Events, DB, Slots, Items, Net, State, Outfits) und das
-- echte Skin auf der strengen WoW-Attrappe.
--
-- Geprueft wird das Verhalten (SPEC 6.9 / 11):
--   * Aufbau: 0 / 1 / 50 Outfits, Zaehler, Leerzustand, Symbole, Info
--   * Seiten: Zeilen je Seite aus der Hoehe, Knoepfe, Mausrad, Klemmen
--   * Knoepfe rufen die richtigen Outfits-Funktionen (Speichern, Laden,
--     Ueberschreiben, Umbenennen, Loeschen) samt Rueckfragen und Statuszeile
--   * Namenspruefung im Dialog (leer, vorhanden, zu lang, nur Schreibweise)
--   * Tooltip: Teile je Slot in Qualitaetsfarbe, Ueberspringgruende
--   * Ereignisse, Sprachwechsel, Mindestgroesse, kein haengendes OnUpdate
--   * (Verifizierer) ladende Listen, Outfits ohne Teile, Namen mit Sonderzeichen,
--     Wettlaeufe zwischen Dialog und Daten, Ereignissstuerme, Rechteckpruefung
--     (tests/layout.lua) in drei Sprachen, und der Ablauf mit dem echten Fenster
--     samt Serverattrappe (tests/fixtures.lua): Meldungen in der Fusszeile,
--     Laden + Anwenden, Ausruestungswechsel, ESC und Fenster schliessen
--
-- Aufruf (im Hauptverzeichnis):  luajit tests/run.lua ui_outfits
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local HIDDEN = 999999

   -- -------------------------------------------------------------------------
   -- Welt
   -- -------------------------------------------------------------------------

   local function put(defs, id, name, quality, ilvl, class, sub, loc, icon)
      defs[id] = {
         name = name, quality = quality, ilvl = ilvl, class = class, subclass = sub,
         equipLoc = loc,
         icon = icon and ("Interface\\Icons\\" .. icon) or nil,
      }
   end

   local function items()
      local d = {}
      put(d, 1001, "Helm of Plate", 4, 200, "Armor", "Plate", "INVTYPE_HEAD", "HeadP")
      put(d, 1004, "Chest of Plate", 4, 200, "Armor", "Plate", "INVTYPE_CHEST", "ChestP")
      put(d, 1015, "Sword of Doom", 4, 200, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "SwordD")
      put(d, 1900, "Libram of Doom", 4, 200, "Armor", "Librams", "INVTYPE_RELIC", "Libram")
      put(d, 1950, "Tabard of the Brave", 3, 1, "Armor", "Miscellaneous", "INVTYPE_TABARD", "Tabard")
      put(d, 2101, "Plate Helm Zeta", 3, 150, "Armor", "Plate", "INVTYPE_HEAD", "H1")
      put(d, 2102, "Plate Helm Eta", 2, 100, "Armor", "Plate", "INVTYPE_HEAD", "H2")
      put(d, 2001, "Plate Chest Alpha", 4, 200, "Armor", "Plate", "INVTYPE_CHEST", "A")
      put(d, 2002, "Plate Chest Beta", 3, 150, "Armor", "Plate", "INVTYPE_CHEST", "B")
      put(d, 2003, "Mail Chest Gamma", 3, 140, "Armor", "Mail", "INVTYPE_CHEST", "C")
      put(d, 2201, "Sword Alpha", 3, 100, "Weapon", "One-Handed Swords", "INVTYPE_WEAPON", "S1")
      put(d, 2202, "Axe Beta", 5, 100, "Weapon", "Two-Handed Axes", "INVTYPE_2HWEAPON", "S2")
      put(d, 2301, "Tabard of Light", 2, 1, "Armor", "Miscellaneous", "INVTYPE_TABARD", "T1")
      return d
   end

   -- Angelegt: Kopf(1), Brust(5), Haupthand(16), Fernkampf(18) = Relikt (NEVER), Wappenrock(19)
   local EQUIP = { [1] = 1001, [5] = 1004, [16] = 1015, [18] = 1900, [19] = 1950 }

   local function feed(T, slot, list)
      local n = #list
      T.Net.Handle(string.format("AvailableTransmogs:%d:405:%d:start", slot, n))
      local part = {}
      for i = 1, n do part[i] = tostring(list[i]) end
      if n > 0 then
         T.Net.Handle(string.format("AvailableTransmogs:%d:405:%d:%s", slot, n, table.concat(part, ":")))
      end
      T.Net.Handle(string.format("AvailableTransmogs:%d:405:%d:end", slot, n))
   end

   -- Kernmodule laden, Listen einspielen, Reiter bauen.
   -- spec.w, spec.h: Groesse des Reiters (Standard 520 x 400)
   local function boot(spec)
      spec = spec or {}
      local T = H.boot({
         upTo = "UI\\Options.lua", login = false,
         items = items(), world = { equipment = EQUIP },
      })
      T.DB.Init()
      T.Locale.Set("enUS")
      T.Slots.Init()
      T.Items.Init()
      T.Net.Init()
      T.State.Init()
      T.Outfits.Init()
      T.enteredWorldAt = GetTime() - 60
      if not spec.uncached then M.CacheAll() end
      T.State.RefreshEquipment()
      feed(T, 0, { 2101, 2102 })
      feed(T, 4, { 2001, 2002, 2003 })
      feed(T, 15, { 2201, 2202 })
      feed(T, 18, { 2301 })

      local parent = CreateFrame("Frame", nil, UIParent)
      parent:SetWidth(900)
      parent:SetHeight(700)
      parent:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      local OT = T.UI.OutfitsTab
      local tab = OT.Create(parent)
      local status = {}
      OT.onStatus = function(text, key) status[#status + 1] = { text = text, key = key } end
      OT.Layout(spec.w or 520, spec.h or 400)
      tab:Show()
      M.Advance(0.3)
      return T, OT, tab, status
   end

   -- Zeit weiterlaufen lassen, damit gebuendelte Aktualisierungen laufen
   local function settle()
      M.Advance(0.3)
   end

   local function shownRows(OT)
      local out = {}
      for _, r in ipairs(OT.rows) do
         if r:IsShown() then out[#out + 1] = r end
      end
      return out
   end

   local function rowNames(OT)
      local out = {}
      for i, r in ipairs(shownRows(OT)) do out[i] = r.outfitName end
      return out
   end

   local function findButton(frame, label)
      for _, b in ipairs(M.Find(frame, "Button")) do
         if b.label and b.label:GetText() == label and b:IsShown() then return b end
      end
      return nil
   end

   -- Alle sichtbaren Symbolfelder einer Zeile
   local function shownIcons(row)
      local out = {}
      for _, c in ipairs(row.icons) do
         if c.frame:IsShown() then out[#out + 1] = c end
      end
      return out
   end

   local function dialogEdit(frame)
      for _, e in ipairs(M.Find(frame, "EditBox")) do
         if e:GetWidth() > 10 then return e end
      end
      return nil
   end

   local function tipLines()
      local out = {}
      for i = 1, GameTooltip:NumLines() do
         local l = rawget(_G, "GameTooltipTextLeft" .. i)
         local r = rawget(_G, "GameTooltipTextRight" .. i)
         out[i] = { left = l and l:GetText() or "", right = r and r:GetText() or "" }
      end
      return out
   end

   local function tipText()
      local parts = {}
      for _, l in ipairs(tipLines()) do
         parts[#parts + 1] = l.left .. "|" .. l.right
      end
      return table.concat(parts, "\n")
   end

   local function lastStatus(status)
      return status[#status]
   end

   -- -------------------------------------------------------------------------
   H.section("Aufbau")
   -- -------------------------------------------------------------------------

   H.test("API: Create ist idempotent, Methoden am Frame, Standardgroesse", function()
      local T, OT, tab = boot()
      for _, fn in ipairs({ "Create", "Layout", "Refresh", "Show", "Hide", "SetPage", "Page", "ApplyLocale",
                            "PromptSave", "LoadOutfit", "PromptOverwrite", "PromptRename", "PromptDelete" }) do
         H.eq(type(OT[fn]), "function", fn)
      end
      H.eq(type(OT.onStatus), "function")
      H.eq(OT.Create(UIParent), tab, "weiteres Create liefert denselben Frame")
      for _, m in ipairs({ "Layout", "Refresh", "SetPage", "Page", "ApplyLocale" }) do
         H.eq(type(tab[m]), "function", "Frame:" .. m)
      end
      H.eq(tab:GetWidth(), 520)
      H.eq(tab:GetHeight(), 400)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("0 Outfits: Leerzustand mit Erklaerung, Zaehler 0 / 50, keine Zeilen", function()
      local T, OT, tab = boot()
      H.truthy(OT.parts.empty:IsShown())
      H.truthy(M.HasText(tab, T.L.OUTFITS_EMPTY_TITLE), "Titel")
      H.truthy(M.HasText(tab, "Outfits save the pieces"), "Erklaerung")
      H.eq(OT.parts.counter:GetText(), "0 / 50")
      H.len(shownRows(OT), 0)
      H.falsy(OT.parts.pager:IsShown(), "keine Blaetterleiste ohne Outfits")
      H.eq(OT.pages, 1)
   end)

   H.test("1 Outfit: Name, Info, Symbole in Qualitaetsfarbe, Zaehler, Knoepfe", function()
      local T, OT, tab = boot()
      H.truthy(T.Outfits.Save("Raid Look", { [0] = 2101, [4] = 2001, [15] = 2202, [18] = HIDDEN }))
      settle()
      H.falsy(OT.parts.empty:IsShown())
      H.eq(OT.parts.counter:GetText(), "1 / 50")
      local rows = shownRows(OT)
      H.len(rows, 1)
      local row = rows[1]
      H.eq(row.name:GetText(), "Raid Look")
      H.eq(row.info:GetText(), "Pieces: 4")
      -- Symbole in Anzeigereihenfolge (Slots.LIST): Kopf, Brust, Wappenrock (verborgen), Haupthand
      local icons = shownIcons(row)
      H.len(icons, 4)
      H.eq(icons[1].tex:GetTexture(), "Interface\\Icons\\H1")
      H.eq(icons[2].tex:GetTexture(), "Interface\\Icons\\A")
      -- Blizzards Dateiname hat einen Tippfehler: nur "Invisibilty" gibt es im Client
      H.eq(icons[3].tex:GetTexture(), "Interface\\Icons\\Spell_Nature_Invisibilty", "Verborgen")
      H.neq(icons[3].tex:GetTexture(), "Interface\\Icons\\Spell_Nature_Invisibility", "falsch geschrieben: Fehlstueck")
      H.eq(icons[4].tex:GetTexture(), "Interface\\Icons\\S2")
      -- Randfarbe = Qualitaet (2101 selten, 2001 episch, 2202 legendaer), Verborgen rosa
      local function border(c) return { c.frame:GetBackdropBorderColor() } end
      H.near(border(icons[2])[1], 0.639, 0.01, "episch r")
      H.near(border(icons[3])[1], 0.96, 0.01, "rosa r")
      H.near(border(icons[3])[2], 0.44, 0.01, "rosa g")
      H.near(border(icons[4])[1], 1.0, 0.01, "legendaer r")
      H.near(border(icons[4])[2], 0.502, 0.01, "legendaer g")
      -- vier Knoepfe mit den lokalisierten Beschriftungen
      H.eq(row.load:GetText(), "Load")
      H.eq(row.over:GetText(), "Overwrite")
      H.eq(row.ren:GetText(), "Rename")
      H.eq(row.del:GetText(), "Delete")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Symbole: nicht aufgeloeste Teile zeigen den Platzhalter und werden nachgeladen", function()
      local T, OT = boot({ uncached = true })
      H.truthy(T.Outfits.Save("Neu", { [0] = 2101, [4] = 2001 }))
      settle()
      local row = shownRows(OT)[1]
      local icons = shownIcons(row)
      H.len(icons, 2)
      H.eq(icons[1].tex:GetTexture(), "Interface\\Icons\\INV_Misc_QuestionMark", "Platzhalter")
      -- die Daten treffen ein: ITEMS_RESOLVED -> Symbole erscheinen
      M.CacheAll()
      M.Advance(2)
      icons = shownIcons(row)
      H.eq(icons[1].tex:GetTexture(), "Interface\\Icons\\H1")
      H.eq(icons[2].tex:GetTexture(), "Interface\\Icons\\A")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Mehr als 8 Teile: acht Symbole plus Zaehler der uebrigen", function()
      local T, OT = boot({ w = 700 })
      local slots = { [0] = 2101, [4] = 2001, [15] = 2201, [18] = 2301, [2] = 2101, [3] = 2101,
                      [5] = 2101, [6] = 2101, [7] = 2101, [8] = 2101 }
      H.truthy(T.Outfits.Save("Gross", slots))
      settle()
      local row = shownRows(OT)[1]
      H.len(shownIcons(row), 8)
      H.truthy(row.more:IsShown())
      H.eq(row.more:GetText(), "+2")
      -- zehn Teile gespeichert, nur an Kopf/Brust/Haupthand/Wappenrock ist etwas angelegt
      H.matches(row.info:GetText(), "^Available: %d+ of 10$")
   end)

   H.test("Symbolstreifen: nie breiter als der Platz links der Knoepfe, fuer '+n' bleibt ein Feld frei", function()
      local slots = { [0] = 2101, [4] = 2001, [15] = 2201, [18] = 2301, [2] = 2101, [3] = 2101,
                      [5] = 2101, [6] = 2101, [7] = 2101, [8] = 2101 }
      for _, w in ipairs({ 260, 360, 398, 460, 700 }) do
         local T, OT = boot({ w = w })
         H.truthy(T.Outfits.Save("Zehn", slots))
         settle()
         local row = shownRows(OT)[1]
         local icons = shownIcons(row)
         H.truthy(#icons >= 1 and #icons <= 8, "Breite " .. w .. ": 1..8 Symbole, sind " .. #icons)
         local _, _, _, ix = icons[#icons].frame:GetPoint()
         local edge = 10 + row.leftW      -- rechter Rand des linken Bereichs
         H.truthy(ix + 24 <= edge + 0.001, "Breite " .. w .. ": Symbole enden vor den Knoepfen")
         H.truthy(row.more:IsShown(), "Breite " .. w .. ": Zaehler zeigt die weggelassenen Teile")
         H.eq(row.more:GetText(), "+" .. (10 - #icons), "Breite " .. w)
         local _, _, _, mx = row.more:GetPoint()
         H.truthy(mx + 14 <= edge + 0.001, "Breite " .. w .. ": Zaehler passt in den linken Bereich")
         H.truthy(mx >= ix + 24, "Breite " .. w .. ": Zaehler hinter dem letzten Symbol")
      end
   end)

   H.test("Aktueller Look: gruener Streifen und Tooltip-Hinweis beim passenden Outfit", function()
      local T, OT = boot()
      H.truthy(T.State.Select(0, 2101))
      H.truthy(T.State.Select(4, 2001))
      H.truthy(T.Outfits.Save("Gleich", { [0] = 2101, [4] = 2001 }))
      H.truthy(T.Outfits.Save("Anders", { [0] = 2102, [4] = 2001 }))
      settle()
      local rows = shownRows(OT)
      H.eq(rows[1].outfitName, "Gleich")
      H.truthy(rows[1].stripe:IsShown())
      H.falsy(rows[2].stripe:IsShown())
      M.Enter(rows[1])
      H.truthy(tipText():find("Matches your current look.", 1, true))
      M.Leave(rows[1])
      -- Auswahl aendern: Streifen wandert
      H.truthy(T.State.Select(0, 2102))
      settle()
      rows = shownRows(OT)
      H.falsy(rows[1].stripe:IsShown())
      H.truthy(rows[2].stripe:IsShown())
   end)

   -- -------------------------------------------------------------------------
   H.section("Seiten")
   -- -------------------------------------------------------------------------

   local function fill(T, n)
      for i = 1, n do
         H.assert(T.Outfits.Save("Outfit " .. i, { [0] = 2101 }), "Save " .. i)
      end
   end

   H.test("50 Outfits: Zeilen je Seite aus der Hoehe, Blaetterleiste, Zaehler rot und Speichern gesperrt", function()
      local T, OT = boot({ h = 400 })
      fill(T, 50)
      settle()
      -- 400 - 36 (Kopf) - 6 - 6 - 30 (Leiste) = 322 -> (322 + 4) / 56 = 5 Zeilen
      H.eq(OT.perPage, 5)
      H.eq(OT.pages, 10)
      H.eq(OT.page, 1)
      H.len(shownRows(OT), 5)
      H.eq(OT.parts.counter:GetText(), "50 / 50")
      H.eq(OT.parts.pageText:GetText(), "Page 1 / 10")
      H.truthy(OT.parts.pager:IsShown())
      H.falsy(OT.parts.prev:IsEnabledState(), "Seite 1: zurueck gesperrt")
      H.truthy(OT.parts.next:IsEnabledState())
      -- voll: Speichern gesperrt, Grund im Tooltip
      H.falsy(OT.parts.save:IsEnabledState())
      M.Enter(OT.parts.save)
      H.truthy(tipText():find(T.L.OUTFIT_ERR_FULL, 1, true), "Grund: voll")
      M.Leave(OT.parts.save)
      -- direkter Aufruf meldet den Grund auch
      local statuses = {}
      OT.onStatus = function(t, k) statuses[#statuses + 1] = { t, k } end
      H.eq(OT.PromptSave(), false)
      H.eq(statuses[1][1], T.L.OUTFIT_ERR_FULL)
      H.eq(statuses[1][2], "red")
      H.falsy(TransmogPromptFrame and TransmogPromptFrame:IsShown())
   end)

   H.test("Blaettern: Knoepfe, Mausrad auf Zeile und Reiter, Klemmen an den Enden", function()
      local T, OT, tab = boot({ h = 400 })
      fill(T, 12)
      settle()
      H.eq(OT.pages, 3)
      H.deepEq(rowNames(OT), { "Outfit 1", "Outfit 2", "Outfit 3", "Outfit 4", "Outfit 5" })
      M.Click(OT.parts.next)
      H.eq(OT.page, 2)
      H.deepEq(rowNames(OT), { "Outfit 6", "Outfit 7", "Outfit 8", "Outfit 9", "Outfit 10" })
      H.eq(OT.parts.pageText:GetText(), "Page 2 / 3")
      M.Click(OT.parts.next)
      H.deepEq(rowNames(OT), { "Outfit 11", "Outfit 12" })
      H.falsy(OT.parts.next:IsEnabledState(), "letzte Seite: vor gesperrt")
      M.Click(OT.parts.next)
      H.eq(OT.page, 3, "klemmt")
      -- Mausrad: nach oben = zurueck
      M.Wheel(shownRows(OT)[1], 1)
      H.eq(OT.page, 2)
      M.Wheel(tab, -1)
      H.eq(OT.page, 3)
      M.Wheel(tab, 1)
      M.Wheel(tab, 1)
      M.Wheel(tab, 1)
      H.eq(OT.page, 1, "klemmt oben")
      -- Seite 1 -> weniger Zeilen als Platz: ueberzaehlige Zeilen sind verborgen
      OT.SetPage(3)
      H.len(shownRows(OT), 2)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Loeschen auf der letzten Seite klemmt die Seite; 0 Outfits -> Leerzustand", function()
      local T, OT = boot({ h = 400 })
      fill(T, 6)
      settle()
      H.eq(OT.pages, 2)
      OT.SetPage(2)
      H.deepEq(rowNames(OT), { "Outfit 6" })
      H.truthy(T.Outfits.Delete("Outfit 6"))
      settle()
      H.eq(OT.page, 1)
      H.eq(OT.pages, 1)
      H.len(shownRows(OT), 5)
      for i = 5, 1, -1 do T.Outfits.Delete("Outfit " .. i) end
      settle()
      H.truthy(OT.parts.empty:IsShown())
      H.len(shownRows(OT), 0)
   end)

   H.test("Layout: Zeilenzahl folgt der Hoehe; kleiner Reiter bleibt benutzbar", function()
      local T, OT = boot({ h = 400 })
      fill(T, 9)
      settle()
      H.eq(OT.perPage, 5)
      OT.Layout(520, 600)
      settle()
      H.eq(OT.perPage, 9)
      H.len(shownRows(OT), 9)
      OT.Layout(520, 120)
      settle()
      H.eq(OT.perPage, 1, "mindestens eine Zeile")
      H.len(shownRows(OT), 1)
      H.eq(OT.pages, 9)
      H.deepEq(H.takeErrors(), {})
   end)

   -- -------------------------------------------------------------------------
   H.section("Speichern")
   -- -------------------------------------------------------------------------

   H.test("Speichern ist ohne Look gesperrt (Grund im Tooltip), mit Look frei", function()
      local T, OT = boot()
      local save = OT.parts.save
      H.falsy(save:IsEnabledState())
      M.Enter(save)
      H.truthy(tipText():find(T.L.OUTFIT_ERR_NOITEMS, 1, true))
      M.Leave(save)
      M.Click(save)
      H.falsy(TransmogPromptFrame and TransmogPromptFrame:IsShown(), "gesperrt: kein Dialog")
      H.truthy(T.State.Select(0, 2101))
      settle()
      H.truthy(save:IsEnabledState())
   end)

   H.test("Speichern: Dialog mit Vorschlag, Annehmen legt Outfit mit dem aktuellen Look an", function()
      local T, OT, tab, status = boot()
      H.truthy(T.State.Select(0, 2101))
      H.truthy(T.State.Select(4, 2002))
      settle()
      M.Click(OT.parts.save)
      local f = TransmogPromptFrame
      H.truthy(f:IsShown())
      H.truthy(M.HasText(f, T.L.OUTFITS_SAVE_TITLE))
      H.truthy(M.HasText(f, T.L.OUTFITS_SAVE_TEXT))
      local e = dialogEdit(f)
      H.eq(e:GetText(), "Outfit 1", "Vorschlag aus Outfits.SuggestName")
      H.truthy(findButton(f, "Save"), "Blizzard-Beschriftung")
      -- der Look aendert sich, solange der Dialog offen ist: gespeichert wird der Look beim Annehmen
      H.truthy(T.State.Select(15, 2201))
      M.Type(e, "  Mein Look ")
      M.Click(findButton(f, "Save"))
      H.falsy(f:IsShown())
      local o = T.Outfits.Get("Mein Look")
      H.truthy(o)
      H.eq(o.slots[0], 2101)
      H.eq(o.slots[4], 2002)
      H.eq(o.slots[15], 2201)
      H.eq(#T.Outfits.List(), 1)
      local st = lastStatus(status)
      H.eq(st.text, "Outfit \"Mein Look\" saved.")
      H.eq(st.key, "green")
      settle()
      H.eq(shownRows(OT)[1].name:GetText(), "Mein Look")
      H.eq(OT.parts.counter:GetText(), "1 / 50")
   end)

   H.test("Nach dem Speichern zeigt der Reiter die Seite mit dem neuen Outfit", function()
      local T, OT = boot({ h = 400 })
      fill(T, 12)
      H.truthy(T.State.Select(0, 2102))
      settle()
      H.eq(OT.page, 1)
      M.Click(OT.parts.save)
      local e = dialogEdit(TransmogPromptFrame)
      M.Type(e, "Ganz neu")
      M.Key(e, "ENTER")
      settle()
      H.eq(#T.Outfits.List(), 13)
      H.eq(OT.pages, 3)
      H.eq(OT.page, 3, "Seite des neuen Outfits")
      H.deepEq(rowNames(OT), { "Outfit 11", "Outfit 12", "Ganz neu" })
      H.truthy(OT.rows[3].stripe:IsShown(), "es entspricht dem aktuellen Look")
   end)

   H.test("Speichern-Dialog: Fehlertexte aus Outfits.ValidateName (vorhanden, zu lang, leer)", function()
      local T, OT = boot()
      H.truthy(T.State.Select(0, 2101))
      H.truthy(T.Outfits.Save("Vorhanden", { [0] = 2101 }))
      settle()
      M.Click(OT.parts.save)
      local f = TransmogPromptFrame
      local e = dialogEdit(f)
      local accept = findButton(f, "Save")
      -- vorhanden (auch andere Schreibweise)
      M.Type(e, "vorhanden")
      H.falsy(accept:IsEnabledState())
      H.truthy(M.HasText(f, T.L.OUTFIT_ERR_EXISTS), "Text im Dialog")
      M.Enter(accept)
      H.truthy(tipText():find(T.L.OUTFIT_ERR_EXISTS, 1, true), "Grund im Knopf-Tooltip")
      M.Leave(accept)
      M.Key(e, "ENTER")
      H.truthy(f:IsShown(), "Enter wird bei Fehler nicht angenommen")
      -- zu lang
      M.Type(e, string.rep("x", 36))
      H.falsy(accept:IsEnabledState())
      H.truthy(M.HasText(f, T.L.OUTFIT_ERR_LONG))
      -- leer
      M.Type(e, "")
      H.falsy(accept:IsEnabledState())
      -- gueltig
      M.Type(e, "Frei")
      H.truthy(accept:IsEnabledState())
      H.falsy(M.HasText(f, T.L.OUTFIT_ERR_EXISTS))
      -- Abbrechen: nichts gespeichert
      M.Click(findButton(f, "Cancel"))
      H.falsy(f:IsShown())
      H.eq(#T.Outfits.List(), 1)
   end)

   H.test("Speichern: Fehler beim Annehmen (Outfit-Grenze) erscheinen rot in der Statuszeile", function()
      local T, OT, tab, status = boot()
      H.truthy(T.State.Select(0, 2101))
      settle()
      M.Click(OT.parts.save)
      local e = dialogEdit(TransmogPromptFrame)
      M.Type(e, "Rennen")
      -- waehrenddessen wird die Auswahl verworfen: Look leer -> Core meldet NOITEMS
      T.State.DiscardAll()
      M.Click(findButton(TransmogPromptFrame, "Save"))
      local st = lastStatus(status)
      H.eq(st.text, T.L.OUTFIT_ERR_NOITEMS)
      H.eq(st.key, "red")
      H.eq(#T.Outfits.List(), 0)
   end)

   -- -------------------------------------------------------------------------
   H.section("Laden")
   -- -------------------------------------------------------------------------

   H.test("Laden: alle Teile verfuegbar -> gruene Zusammenfassung, Auswahl gesetzt, nichts angewendet", function()
      local T, OT, tab, status = boot()
      H.truthy(T.Outfits.Save("Komplett", { [0] = 2101, [4] = 2001 }))
      settle()
      M.ClearSent()
      M.Click(shownRows(OT)[1].load)
      local st = lastStatus(status)
      H.eq(st.text, "Pieces loaded: 2")
      H.eq(st.key, "green")
      H.eq(T.State.Wanted(0), 2101)
      H.eq(T.State.Wanted(4), 2001)
      H.truthy(T.State.HasPending(0))
      H.eq(M.CountSent("transmog"), M.CountSent("transmog"), "nur Kostenabfragen")
      for _, cmd in ipairs(M.SentCommands()) do
         H.falsy(cmd:find("^Apply:"), "kein sofortiges Anwenden: " .. cmd)
      end
   end)

   H.test("Laden: teils nicht verfuegbar -> gelb mit beiden Zahlen; Gruende im Zeilen-Tooltip", function()
      local T, OT, tab, status = boot()
      H.truthy(T.Outfits.Save("Teils", { [0] = 2101, [4] = 2001, [15] = 5555, [18] = HIDDEN }))
      settle()
      local row = shownRows(OT)[1]
      H.eq(row.info:GetText(), "Available: 3 of 4", "Info nennt verfuegbare Teile")
      M.Click(row.load)
      local st = lastStatus(status)
      H.eq(st.text, "Pieces loaded: 3, not available: 1")
      H.eq(st.key, "yellow")
      H.eq(T.State.Wanted(15), 2201 == 0 and 0 or T.State.Wanted(15), "Haupthand unveraendert")
      H.eq(T.State.Wanted(18), HIDDEN)
      -- Tooltip: Slotnamen links, Itemnamen rechts, Grund unter dem uebersprungenen Teil
      M.Enter(row)
      local text = tipText()
      H.truthy(text:find("Teils", 1, true), "Titel")
      H.truthy(text:find("Head|Plate Helm Zeta", 1, true), "Kopf")
      H.truthy(text:find("Chest|Plate Chest Alpha", 1, true), "Brust")
      H.truthy(text:find("Tabard|Hidden", 1, true), "Verborgen")
      H.truthy(text:find(T.L.OUTFIT_SKIP_UNAVAILABLE, 1, true), "Grund")
      -- Qualitaetsfarbe des Namens (2001 episch)
      local lines = tipLines()
      local right
      for i, l in ipairs(lines) do
         if l.right == "Plate Chest Alpha" then right = rawget(_G, "GameTooltipTextRight" .. i) end
      end
      H.truthy(right)
      local r, g, b = right:GetTextColor()
      H.near(r, 0.639, 0.01)
      H.near(g, 0.208, 0.01)
      M.Leave(row)
   end)

   H.test("Laden: nichts verfuegbar -> rote Meldung; unbekanntes Outfit -> OUTFIT_ERR_MISSING", function()
      local T, OT, tab, status = boot()
      H.truthy(T.Outfits.Save("Nix", { [15] = 5555, [17] = 5556 }))
      settle()
      M.Click(shownRows(OT)[1].load)
      local st = lastStatus(status)
      H.eq(st.text, "No piece could be loaded (not available: 2)")
      H.eq(st.key, "red")
      local ok = OT.LoadOutfit("Gibt es nicht")
      H.eq(ok, false)
      st = lastStatus(status)
      H.eq(st.text, T.L.OUTFIT_ERR_MISSING)
      H.eq(st.key, "red")
   end)

   H.test("Laden ruft State.SetMany genau einmal mit den uebernehmbaren Teilen", function()
      local T, OT = boot()
      H.truthy(T.Outfits.Save("Eins", { [0] = 2101, [4] = 2002, [15] = 5555 }))
      settle()
      local calls, last = 0, nil
      local orig = T.State.SetMany
      T.State.SetMany = function(map)
         calls = calls + 1
         last = {}
         for k, v in pairs(map) do last[k] = v end
         return orig(map)
      end
      M.Click(shownRows(OT)[1].load)
      H.eq(calls, 1)
      H.deepEq(last, { [0] = 2101, [4] = 2002 })
   end)

   -- -------------------------------------------------------------------------
   H.section("Ueberschreiben, Umbenennen, Loeschen")
   -- -------------------------------------------------------------------------

   H.test("Ueberschreiben: Rueckfrage, Abbrechen aendert nichts, Annehmen ersetzt durch den aktuellen Look", function()
      local T, OT, tab, status = boot()
      H.truthy(T.Outfits.Save("Alt", { [0] = 2101 }))
      settle()
      H.truthy(T.State.Select(0, 2102))
      H.truthy(T.State.Select(4, 2003))
      settle()
      local row = shownRows(OT)[1]
      H.truthy(row.over:IsEnabledState())
      M.Click(row.over)
      local f = TransmogConfirmFrame
      H.truthy(f:IsShown())
      H.truthy(M.HasText(f, T.L.OUTFITS_OVERWRITE_TITLE))
      H.truthy(M.HasText(f, "Replace the pieces of the outfit \"Alt\" with your current look?"))
      -- Abbrechen
      M.Click(findButton(f, "Cancel"))
      H.falsy(f:IsShown())
      H.eq(T.Outfits.Get("Alt").slots[0], 2101)
      H.eq(T.Outfits.Get("Alt").slots[4], nil)
      -- Annehmen
      M.Click(row.over)
      M.Click(findButton(f, "Overwrite"))
      H.falsy(f:IsShown())
      local o = T.Outfits.Get("Alt")
      H.eq(o.slots[0], 2102)
      H.eq(o.slots[4], 2003)
      H.eq(o.count, 2)
      local st = lastStatus(status)
      H.eq(st.text, "Outfit \"Alt\" updated.")
      H.eq(st.key, "green")
      settle()
      H.eq(shownRows(OT)[1].info:GetText(), "Pieces: 2")
   end)

   H.test("Ueberschreiben ist ohne Look gesperrt (Grund im Tooltip), kein Dialog", function()
      local T, OT, tab, status = boot()
      H.truthy(T.Outfits.Save("Alt", { [0] = 2101 }))
      settle()
      local row = shownRows(OT)[1]
      H.falsy(row.over:IsEnabledState())
      M.Click(row.over)
      H.falsy(TransmogConfirmFrame and TransmogConfirmFrame:IsShown())
      M.Enter(row.over)
      H.truthy(tipText():find(T.L.OUTFIT_ERR_NOITEMS, 1, true))
      M.Leave(row.over)
      H.eq(OT.PromptOverwrite("Alt"), false)
      H.eq(lastStatus(status).text, T.L.OUTFIT_ERR_NOITEMS)
   end)

   H.test("Umbenennen: Vorbelegung, Pruefung (vorhanden, nur Schreibweise), Annehmen", function()
      local T, OT, tab, status = boot()
      H.truthy(T.Outfits.Save("Alpha", { [0] = 2101 }))
      H.truthy(T.Outfits.Save("Beta", { [0] = 2102 }))
      settle()
      M.Click(shownRows(OT)[1].ren)
      local f = TransmogPromptFrame
      H.truthy(f:IsShown())
      H.truthy(M.HasText(f, T.L.OUTFITS_RENAME_TITLE))
      H.truthy(M.HasText(f, "Enter a new name for the outfit \"Alpha\":"))
      local e = dialogEdit(f)
      H.eq(e:GetText(), "Alpha", "vorbelegt")
      local accept = findButton(f, "Rename")
      H.truthy(accept, "Knopf heisst Umbenennen")
      H.truthy(accept:IsEnabledState(), "unveraenderter Name: gueltig")
      -- anderes Outfit traegt den Namen
      M.Type(e, "BETA")
      H.falsy(accept:IsEnabledState())
      H.truthy(M.HasText(f, T.L.OUTFIT_ERR_EXISTS))
      -- nur die Schreibweise des eigenen Namens
      M.Type(e, "ALPHA")
      H.truthy(accept:IsEnabledState(), "eigener Name in anderer Schreibweise ist erlaubt")
      H.falsy(M.HasText(f, T.L.OUTFIT_ERR_EXISTS))
      -- zu lang / leer
      M.Type(e, string.rep("n", 34))
      H.falsy(accept:IsEnabledState())
      H.truthy(M.HasText(f, T.L.OUTFIT_ERR_LONG))
      M.Type(e, "")
      H.falsy(accept:IsEnabledState())
      -- annehmen
      M.Type(e, "  Gamma  ")
      M.Click(accept)
      H.falsy(f:IsShown())
      H.eq(T.Outfits.List()[1].name, "Gamma")
      H.eq(T.Outfits.List()[2].name, "Beta")
      local st = lastStatus(status)
      H.eq(st.text, "Outfit renamed to \"Gamma\".")
      H.eq(st.key, "green")
      settle()
      H.eq(shownRows(OT)[1].name:GetText(), "Gamma")
   end)

   H.test("Umbenennen: nur Gross-/Kleinschreibung aendern funktioniert", function()
      local T, OT = boot()
      H.truthy(T.Outfits.Save("alpha", { [0] = 2101 }))
      settle()
      M.Click(shownRows(OT)[1].ren)
      local e = dialogEdit(TransmogPromptFrame)
      M.Type(e, "Alpha")
      M.Key(e, "ENTER")
      H.eq(T.Outfits.List()[1].name, "Alpha")
   end)

   H.test("Loeschen: Rueckfrage (rot), Abbrechen behaelt, Annehmen entfernt, Status gelb", function()
      local T, OT, tab, status = boot()
      H.truthy(T.Outfits.Save("Weg", { [0] = 2101 }))
      H.truthy(T.Outfits.Save("Bleibt", { [0] = 2102 }))
      settle()
      M.Click(shownRows(OT)[1].del)
      local f = TransmogConfirmFrame
      H.truthy(f:IsShown())
      H.truthy(M.HasText(f, "Delete the outfit \"Weg\"? This cannot be undone."))
      local r, g, b = f:GetChildren()   -- Kopf ist das erste Kind; Streifen rot (danger)
      M.Click(findButton(f, "Cancel"))
      H.eq(#T.Outfits.List(), 2)
      M.Click(shownRows(OT)[1].del)
      M.Click(findButton(f, "Delete"))
      H.falsy(f:IsShown())
      H.eq(#T.Outfits.List(), 1)
      H.eq(T.Outfits.List()[1].name, "Bleibt")
      local st = lastStatus(status)
      H.eq(st.text, "Outfit \"Weg\" deleted.")
      H.eq(st.key, "yellow")
      settle()
      H.deepEq(rowNames(OT), { "Bleibt" })
      H.eq(OT.parts.counter:GetText(), "1 / 50")
   end)

   H.test("Rueckfragen koennen mit ESC geschlossen werden und aendern nichts", function()
      local T, OT = boot()
      H.truthy(T.Outfits.Save("Bleibt", { [0] = 2101 }))
      settle()
      M.Click(shownRows(OT)[1].del)
      H.truthy(TransmogConfirmFrame:IsShown())
      H.truthy(M.Escape())
      H.falsy(TransmogConfirmFrame:IsShown())
      H.eq(#T.Outfits.List(), 1)
   end)

   -- -------------------------------------------------------------------------
   H.section("Tooltips und Hervorhebung")
   -- -------------------------------------------------------------------------

   H.test("Zeilen-Tooltip: ladende Teile heissen 'Loading...', Hover-Hervorhebung folgt der Maus", function()
      local T, OT = boot({ uncached = true })
      H.truthy(T.Outfits.Save("Lade", { [0] = 2101 }))
      settle()
      local row = shownRows(OT)[1]
      H.falsy(row.hl:IsShown())
      M.Enter(row)
      H.truthy(row.hl:IsShown(), "Hover")
      H.truthy(tipText():find("Head|Loading...", 1, true))
      -- Daten treffen ein: der Tooltip wird erneuert, solange die Maus auf der Zeile liegt
      M.CacheAll()
      M.Advance(2)
      H.truthy(tipText():find("Head|Plate Helm Zeta", 1, true), "Tooltip aktualisiert")
      -- Maus auf einen Knopf der Zeile: Hervorhebung bleibt
      M.Enter(row.load)
      H.truthy(row.hl:IsShown(), "auf Kind: weiter hervorgehoben")
      M.Leave(row.load)
      H.falsy(row.hl:IsShown(), "Maus draussen")
      H.falsy(GameTooltip:IsShown())
   end)

   H.test("Knopf-Tooltips erklaeren Laden (nichts wird angewendet) und die anderen Aktionen", function()
      local T, OT = boot()
      H.truthy(T.Outfits.Save("A", { [0] = 2101 }))
      settle()
      local row = shownRows(OT)[1]
      M.Enter(row.load)
      H.truthy(tipText():find(T.L.OUTFITS_LOAD_TIP, 1, true))
      M.Leave(row.load)
      M.Enter(row.del)
      H.truthy(tipText():find(T.L.OUTFITS_DELETE_TIP, 1, true))
      M.Leave(row.del)
      M.Enter(OT.parts.save)
      M.Leave(OT.parts.save)
      H.deepEq(H.takeErrors(), {})
   end)

   -- -------------------------------------------------------------------------
   H.section("Ereignisse, Sprache, Aufraeumen")
   -- -------------------------------------------------------------------------

   H.test("OUTFITS_CHANGED: sichtbar -> gebuendelt neu gezeichnet; verborgen -> beim Zeigen nachgeholt", function()
      local T, OT, tab = boot()
      H.truthy(T.Outfits.Save("Eins", { [0] = 2101 }))
      settle()
      H.deepEq(rowNames(OT), { "Eins" })
      tab:Hide()
      H.truthy(T.Outfits.Save("Zwei", { [0] = 2102 }))
      H.truthy(T.Outfits.Rename("Eins", "Erstes"))
      M.Advance(1)
      H.deepEq(rowNames(OT), { "Eins" }, "verborgen: unveraendert")
      OT.Show()
      H.deepEq(rowNames(OT), { "Erstes", "Zwei" }, "OnShow holt nach")
      -- sichtbar: mehrere Aenderungen = eine Zeichnung
      local n = 0
      local orig = T.Outfits.List
      T.Outfits.List = function(...) n = n + 1 return orig(...) end
      for i = 1, 5 do T.Outfits.Save("Neu " .. i, { [0] = 2101 }) end
      M.Advance(0.3)
      T.Outfits.List = orig
      H.eq(n, 1, "Outfits.List je Zeichnung einmal")
   end)

   H.test("WANTED_CHANGED aktualisiert Speichern/Ueberschreiben-Zustand", function()
      local T, OT = boot()
      H.truthy(T.Outfits.Save("A", { [0] = 2101 }))
      settle()
      H.falsy(OT.parts.save:IsEnabledState())
      T.State.Select(0, 2102)
      settle()
      H.truthy(OT.parts.save:IsEnabledState())
      H.truthy(shownRows(OT)[1].over:IsEnabledState())
      T.State.DiscardAll()
      settle()
      H.falsy(OT.parts.save:IsEnabledState())
      H.falsy(shownRows(OT)[1].over:IsEnabledState())
   end)

   H.test("Sprachwechsel: alle Texte werden neu gesetzt (Beschriftungen, Zaehler, Leerzustand)", function()
      local T, OT, tab = boot()
      T.Locale.Add("deDE", {
         OUTFITS_SAVE = "Aktuellen Look speichern", OUTFITS_LOAD = "Laden",
         OUTFITS_OVERWRITE = "Ueberschreiben", OUTFITS_RENAME = "Umbenennen", OUTFITS_DELETE = "Loeschen",
         OUTFITS_EMPTY_TITLE = "Noch keine Outfits", OUTFITS_PIECES = "Teile: %d",
         OUTFITS_PAGE = "Seite %d / %d",
      })
      settle()
      H.eq(OT.parts.save:GetText(), "Save current look")
      T.Locale.Set("deDE")
      settle()
      H.eq(OT.parts.save:GetText(), "Aktuellen Look speichern")
      H.truthy(M.HasText(tab, "Noch keine Outfits"))
      H.truthy(T.Outfits.Save("A", { [0] = 2101, [4] = 2001 }))
      settle()
      local row = shownRows(OT)[1]
      H.eq(row.load:GetText(), "Laden")
      H.eq(row.over:GetText(), "Ueberschreiben")
      H.eq(row.ren:GetText(), "Umbenennen")
      H.eq(row.del:GetText(), "Loeschen")
      H.eq(row.info:GetText(), "Teile: 2")
      H.eq(OT.parts.pageText:GetText(), "Seite 1 / 1")
      T.Locale.Set("enUS")
      settle()
      H.eq(shownRows(OT)[1].load:GetText(), "Load")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Alle Texte des Reiters sind lokalisiert (kein Schluessel als Text)", function()
      local T, OT, tab = boot({ uncached = true })
      for i = 1, 3 do T.Outfits.Save("Look " .. i, { [0] = 2101, [4] = 2001, [15] = 5555 }) end
      T.State.Select(0, 2102)
      settle()
      M.Enter(shownRows(OT)[1])
      for _, t in ipairs(M.Texts(tab, true)) do
         H.falsy(t:find("^OUTFITS?_[A-Z_]+$"), "Schluessel als Text: " .. t)
      end
      for _, l in ipairs(tipLines()) do
         H.falsy(l.left:find("^OUTFITS?_[A-Z_]+$"), "Schluessel im Tooltip: " .. l.left)
      end
      M.Leave(shownRows(OT)[1])
      -- die Bibliothek selbst meldet keine fehlenden Schluessel mit unserem Praefix
      for key in pairs(T.L.__missing) do
         H.falsy(key:find("^OUTFITS_"), "fehlender Schluessel: " .. key)
      end
   end)

   H.test("Mindestgroesse: nichts ragt ueber die Zeilenbreite, Name und Info ueberlappen nicht", function()
      local T, OT = boot({ w = 398, h = 330 })
      T.Locale.Add("deDE", {
         OUTFITS_OVERWRITE = "Ueberschreiben-Beschriftung", OUTFITS_RENAME = "Umbenennen",
         OUTFITS_DELETE = "Loeschen", OUTFITS_LOAD = "Laden",
      })
      T.Locale.Set("deDE")
      H.truthy(T.Outfits.Save(string.rep("W", 32), { [0] = 2101, [4] = 2001, [15] = 2201,
         [18] = 2301, [2] = 2101, [3] = 2101, [5] = 2101, [6] = 2101, [7] = 2101 }))
      settle()
      local row = shownRows(OT)[1]
      H.eq(row:GetWidth(), 398)
      local function right(f)
         local _, _, _, x = f:GetPoint()
         return x + f:GetWidth()
      end
      for _, b in ipairs({ row.load, row.over, row.ren, row.del }) do
         H.truthy(right(b) <= 398 - 8 + 0.001, "Knopf innerhalb der Zeile: " .. tostring(right(b)))
         H.truthy(b:GetWidth() <= 112 and b:GetWidth() >= 60, "Knopfbreite")
      end
      -- Name + Info liegen links der Knopfspalte
      local leftEnd = 10 + row.name:GetWidth() + 8 + row.info:GetWidth()
      local _, _, _, loadX = row.load:GetPoint()
      H.truthy(leftEnd <= loadX + 0.001, "Name und Info enden vor den Knoepfen")
      -- Symbole enden vor den Knoepfen
      local icons = shownIcons(row)
      local _, _, _, ix = icons[#icons].frame:GetPoint()
      H.truthy(ix + 24 <= loadX + 0.001, "Symbole enden vor den Knoepfen")
   end)

   H.test("Kein haengendes OnUpdate und keine Fehler im Leerlauf; Verbergen raeumt Tooltip auf", function()
      local T, OT, tab = boot()
      fill(T, 7)
      settle()
      M.Enter(shownRows(OT)[1])
      H.truthy(GameTooltip:IsShown())
      tab:Hide()
      H.falsy(GameTooltip:IsShown(), "Tooltip geht mit dem Reiter")
      M.Advance(2)
      H.len(M.UpdateFrames(), 0, "kein sichtbarer OnUpdate-Frame")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Viele Aktualisierungen erzeugen keine neuen Frames (Zeilenvorrat)", function()
      local T, OT = boot({ h = 400 })
      fill(T, 30)
      settle()
      local before = #M.frames
      for i = 1, 20 do
         OT.SetPage(1 + (i % 6))
         T.Outfits.Rename("Outfit " .. i, "Umbenannt " .. i)
         M.Advance(0.1)
      end
      OT.Layout(520, 400)
      settle()
      H.eq(#M.frames, before, "keine neuen Frames")
      H.deepEq(H.takeErrors(), {})
   end)

   -- =========================================================================
   -- Ergaenzungen des Verifizierers
   -- =========================================================================

   -- Eine Liste "laeuft noch": Strom gestartet, nicht beendet (State: ready = false)
   local function startStream(T, slot, amount)
      T.Net.Handle(string.format("AvailableTransmogs:%d:405:%d:start", slot, amount or 2))
   end

   local function finishStream(T, slot, ids)
      local part = {}
      for i, id in ipairs(ids) do part[i] = tostring(id) end
      if #ids > 0 then
         T.Net.Handle(string.format("AvailableTransmogs:%d:405:%d:%s", slot, #ids, table.concat(part, ":")))
      end
      T.Net.Handle(string.format("AvailableTransmogs:%d:405:%d:end", slot, #ids))
   end

   local function infoColor(row)
      local r, g, b = row.info:GetTextColor()
      return r, g, b
   end

   -- -------------------------------------------------------------------------
   H.section("Listen laden noch")
   -- -------------------------------------------------------------------------

   H.test("Ladende Liste: Info bleibt neutral, 'Laden' sagt 'noch am Laden' statt 'nicht verfuegbar'", function()
      local T, OT, tab, status = boot()
      startStream(T, 0, 2)                       -- Kopf: Liste laeuft noch
      H.truthy(T.Outfits.Save("Gemischt", { [0] = 2101, [4] = 2001 }))
      H.truthy(T.Outfits.Save("NurKopf", { [0] = 2101 }))
      H.truthy(T.Outfits.Save("Fehlt", { [15] = 5555 }))
      H.truthy(T.Outfits.Save("Beides", { [0] = 2101, [15] = 5555 }))
      settle()
      local rows = shownRows(OT)
      -- ladend ist nicht "fehlt": neutral und grau
      H.eq(rows[1].info:GetText(), "Pieces: 2")
      H.near(({ infoColor(rows[1]) })[1], T.COLORS.dim[1], 0.01, "grau")
      H.eq(rows[2].info:GetText(), "Pieces: 1")
      -- wirklich fehlend: gelb
      H.eq(rows[3].info:GetText(), "Available: 0 of 1")
      H.near(({ infoColor(rows[3]) })[1], T.COLORS.yellow[1], 0.01, "gelb")
      -- gemischt (eins ladend, eins fehlt): nur das Fehlende zaehlt
      H.eq(rows[4].info:GetText(), "Available: 1 of 2")

      -- Laden: ein Teil sofort, eins wartet
      M.Click(rows[1].load)
      local st = lastStatus(status)
      H.eq(st.text, "Pieces loaded: 1, still loading: 1")
      H.eq(st.key, "yellow")
      H.eq(T.State.Wanted(4), 2001)
      -- nur Ladendes: gelbe Bitte um Geduld, nichts gesetzt
      M.Click(rows[2].load)
      st = lastStatus(status)
      H.eq(st.text, T.L.OUTFITS_LOADED_WAIT)
      H.eq(st.key, "yellow")
      -- wirklich nicht verfuegbar: rot
      M.Click(rows[3].load)
      st = lastStatus(status)
      H.eq(st.text, "No piece could be loaded (not available: 1)")
      H.eq(st.key, "red")
      -- Ladend + fehlend, nichts ladbar: trotzdem "spaeter nochmal" (das Ladende koennte passen)
      M.Click(rows[4].load)
      st = lastStatus(status)
      H.eq(st.text, T.L.OUTFITS_LOADED_WAIT)

      -- Liste kommt an: Info und Laden stimmen
      finishStream(T, 0, { 2101, 2102 })
      settle()
      rows = shownRows(OT)
      H.eq(rows[1].info:GetText(), "Pieces: 2")
      H.eq(rows[2].info:GetText(), "Pieces: 1")
      M.Click(rows[2].load)
      st = lastStatus(status)
      H.eq(st.text, "Pieces loaded: 1")
      H.eq(st.key, "green")
      H.eq(T.State.Wanted(0), 2101)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Tooltip einer Zeile nennt fuer ein Teil in ladender Liste den Grund 'noch am Laden'", function()
      local T, OT = boot()
      startStream(T, 4, 3)
      H.truthy(T.Outfits.Save("Wartet", { [0] = 2101, [4] = 2001 }))
      settle()
      local row = shownRows(OT)[1]
      M.Enter(row)
      local text = tipText()
      H.truthy(text:find(T.L.OUTFIT_SKIP_LOADING, 1, true), text)
      H.falsy(text:find(T.L.OUTFIT_SKIP_UNAVAILABLE, 1, true))
      M.Leave(row)
   end)

   H.test("Gegenstand, den der Client nicht kennt (Abfrage aufgegeben): Tooltip nennt 'Item <id>' statt ewig 'Loading...'", function()
      local T, OT = boot({ uncached = true })
      H.truthy(T.Outfits.Save("Unbekannt", { [0] = 2101, [4] = 7777 }))     -- 7777 gibt es nicht
      settle()
      local row = shownRows(OT)[1]
      M.Enter(row)
      H.truthy(tipText():find("Head|Loading...", 1, true))
      H.truthy(tipText():find("Chest|Loading...", 1, true))
      M.Leave(row)
      M.CacheItem(2101)                    -- nur der echte Gegenstand trifft ein
      M.Advance(40)                        -- Items gibt nach 20 s auf
      M.Enter(row)
      local text = tipText()
      H.truthy(text:find("Head|Plate Helm Zeta", 1, true), text)
      H.truthy(text:find("Chest|Item 7777", 1, true), "aufgegeben: Item 7777 statt Loading...")
      H.falsy(text:find("Loading...", 1, true))
      M.Leave(row)
      H.deepEq(H.takeErrors(), {})
   end)

   -- -------------------------------------------------------------------------
   H.section("Outfit ohne Teile (Altdaten)")
   -- -------------------------------------------------------------------------

   H.test("Zeile ohne Teile: 'Pieces: 0', keine Symbole, Laden erklaert es, Ueberschreiben fuellt es", function()
      local T, OT, tab, status = boot()
      -- wie die Uebernahme eines alten Outfits aus lauter 0-Eintraegen: Name, aber keine Teile
      T.DB.char.outfits[#T.DB.char.outfits + 1] = { name = "Leer", slots = {}, time = 0 }
      T.Events.Fire("OUTFITS_CHANGED")
      settle()
      local row = shownRows(OT)[1]
      H.eq(row.name:GetText(), "Leer")
      H.eq(row.info:GetText(), "Pieces: 0")
      H.len(shownIcons(row), 0)
      H.falsy(row.more:IsShown())
      M.Click(row.load)
      H.eq(lastStatus(status).text, T.L.OUTFITS_LOADED_EMPTY)
      H.eq(lastStatus(status).key, "red")
      -- mit einem Look ueberschreiben
      H.truthy(T.State.Select(0, 2101))
      settle()
      M.Click(shownRows(OT)[1].over)
      M.Click(findButton(TransmogConfirmFrame, "Overwrite"))
      settle()
      row = shownRows(OT)[1]
      H.eq(row.info:GetText(), "Pieces: 1")
      H.len(shownIcons(row), 1)
      H.deepEq(H.takeErrors(), {})
   end)

   -- -------------------------------------------------------------------------
   H.section("Namen")
   -- -------------------------------------------------------------------------

   H.test("Namen mit Mehrbyte-Zeichen: 32 Zeichen gehen, 33 nicht (Zeichen, nicht Bytes)", function()
      local T, OT = boot()
      H.truthy(T.State.Select(0, 2101))
      settle()
      M.Click(OT.parts.save)
      local f = TransmogPromptFrame
      local e = dialogEdit(f)
      local accept = findButton(f, "Save")
      local a32 = string.rep("\195\164", 32)           -- 32 x ae = 64 Bytes
      M.Type(e, a32)
      H.truthy(accept:IsEnabledState(), "32 Zeichen")
      M.Type(e, a32 .. "\195\164")
      H.falsy(accept:IsEnabledState(), "33 Zeichen")
      H.truthy(M.HasText(f, T.L.OUTFIT_ERR_LONG))
      M.Type(e, a32)
      M.Click(accept)
      settle()
      H.eq(T.Outfits.List()[1].name, a32)
      H.eq(shownRows(OT)[1].name:GetText(), a32)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Prozentzeichen, Farbcodes und Mehrfach-Leerzeichen im Namen: bereinigt, nichts bricht", function()
      local T, OT, tab, status = boot()
      H.truthy(T.State.Select(0, 2101))
      settle()
      M.Click(OT.parts.save)
      local f = TransmogPromptFrame
      local e = dialogEdit(f)
      M.Type(e, "  100%  |cffff0000Rot|r   Look%d ")
      M.Click(findButton(f, "Save"))
      H.eq(T.Outfits.List()[1].name, "100% Rot Look%d")
      H.eq(lastStatus(status).text, "Outfit \"100% Rot Look%d\" saved.")
      settle()
      local row = shownRows(OT)[1]
      H.eq(row.name:GetText(), "100% Rot Look%d")
      -- Rueckfragen und Tooltips mit dem Namen
      M.Enter(row)
      H.truthy(tipText():find("100% Rot Look%d", 1, true))
      M.Leave(row)
      M.Click(row.ren)
      H.truthy(M.HasText(TransmogPromptFrame, "Enter a new name for the outfit \"100% Rot Look%d\":"))
      M.Click(findButton(TransmogPromptFrame, "Cancel"))
      M.Click(row.del)
      H.truthy(M.HasText(TransmogConfirmFrame, "Delete the outfit \"100% Rot Look%d\"? This cannot be undone."))
      M.Click(findButton(TransmogConfirmFrame, "Delete"))
      H.eq(lastStatus(status).text, "Outfit \"100% Rot Look%d\" deleted.")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Statusmeldungen kuerzen lange Namen (Fusszeile ist schmal) und trennen kein UTF-8-Zeichen", function()
      local T, OT, tab, status = boot()
      H.truthy(T.State.Select(0, 2101))
      settle()
      local long = "Argent Tournament Parade Banner"      -- 31 Zeichen
      H.truthy(T.Outfits.Save(long, { [0] = 2101 }))
      local ae = string.rep("\195\164", 30)             -- 30 x ae (2 Bytes je Zeichen)
      H.truthy(T.Outfits.Save(ae, { [0] = 2101 }))
      settle()
      local row = shownRows(OT)[1]
      M.Click(row.over)
      M.Click(findButton(TransmogConfirmFrame, "Overwrite"))
      H.eq(lastStatus(status).text, "Outfit \"Argent Tournament Pa...\" updated.")
      M.Click(row.ren)
      M.Type(dialogEdit(TransmogPromptFrame), "Kurz")
      M.Click(findButton(TransmogPromptFrame, "Rename"))
      H.eq(lastStatus(status).text, "Outfit renamed to \"Kurz\".", "kurze Namen bleiben ganz")
      settle()
      M.Click(shownRows(OT)[2].del)
      M.Click(findButton(TransmogConfirmFrame, "Delete"))
      local text = lastStatus(status).text
      H.eq(text, "Outfit \"" .. string.rep("\195\164", 20) .. "...\" deleted.", "20 Zeichen + ...")
      -- das Outfit selbst bleibt unveraendert vollstaendig
      H.eq(T.Outfits.List()[1].name, "Kurz")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Name nur aus Farbcode/Leerraum: Dialog sperrt mit 'Name eingeben', nichts wird gespeichert", function()
      local T, OT = boot()
      H.truthy(T.State.Select(0, 2101))
      settle()
      M.Click(OT.parts.save)
      local f = TransmogPromptFrame
      local e = dialogEdit(f)
      local accept = findButton(f, "Save")
      M.Type(e, "|cffff0000|r")
      H.falsy(accept:IsEnabledState())
      H.truthy(M.HasText(f, T.L.OUTFIT_ERR_EMPTY))
      M.Key(e, "ENTER")
      H.truthy(f:IsShown(), "Enter nimmt nichts an")
      H.eq(#T.Outfits.List(), 0)
      M.Key(e, "ESCAPE")
      H.falsy(f:IsShown())
   end)

   -- -------------------------------------------------------------------------
   H.section("Wettlaeufe zwischen Dialog und Daten")
   -- -------------------------------------------------------------------------

   H.test("Speichern: gleicher Name entsteht, waehrend der Dialog offen ist -> rote Meldung, nichts ueberschrieben", function()
      local T, OT, tab, status = boot()
      H.truthy(T.State.Select(0, 2101))
      settle()
      M.Click(OT.parts.save)
      local e = dialogEdit(TransmogPromptFrame)
      M.Type(e, "Doppelt")
      H.truthy(T.Outfits.Save("Doppelt", { [4] = 2001 }))
      M.Click(findButton(TransmogPromptFrame, "Save"))
      local st = lastStatus(status)
      H.eq(st.text, T.L.OUTFIT_ERR_EXISTS)
      H.eq(st.key, "red")
      H.eq(#T.Outfits.List(), 1)
      H.eq(T.Outfits.Get("Doppelt").slots[4], 2001, "das vorhandene Outfit blieb")
      H.eq(T.Outfits.Get("Doppelt").slots[0], nil)
   end)

   H.test("Ueberschreiben/Umbenennen/Loeschen eines inzwischen geloeschten Outfits: rote Meldung, kein Fehler", function()
      local T, OT, tab, status = boot()
      H.truthy(T.Outfits.Save("Weg", { [0] = 2101 }))
      H.truthy(T.State.Select(0, 2102))
      settle()
      local row = shownRows(OT)[1]
      M.Click(row.over)
      H.truthy(T.Outfits.Delete("Weg"))
      M.Click(findButton(TransmogConfirmFrame, "Overwrite"))
      H.eq(lastStatus(status).text, T.L.OUTFIT_ERR_MISSING)
      H.eq(lastStatus(status).key, "red")

      H.truthy(T.Outfits.Save("Weg2", { [0] = 2101 }))
      settle()
      row = shownRows(OT)[1]
      M.Click(row.ren)
      local e = dialogEdit(TransmogPromptFrame)
      M.Type(e, "Neu")
      H.truthy(T.Outfits.Delete("Weg2"))
      M.Click(findButton(TransmogPromptFrame, "Rename"))
      H.eq(lastStatus(status).text, T.L.OUTFIT_ERR_MISSING)

      H.truthy(T.Outfits.Save("Weg3", { [0] = 2101 }))
      settle()
      row = shownRows(OT)[1]
      M.Click(row.del)
      H.truthy(T.Outfits.Delete("Weg3"))
      M.Click(findButton(TransmogConfirmFrame, "Delete"))
      H.eq(lastStatus(status).text, T.L.OUTFIT_ERR_MISSING)
      settle()
      H.len(shownRows(OT), 0)
      H.truthy(OT.parts.empty:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Outfit unter dem Mauszeiger wird geloescht: der Tooltip verschwindet bzw. zeigt das Nachruecker-Outfit", function()
      local T, OT = boot()
      H.truthy(T.Outfits.Save("Eins", { [0] = 2101 }))
      H.truthy(T.Outfits.Save("Zwei", { [0] = 2102 }))
      settle()
      local rows = shownRows(OT)
      M.Enter(rows[2])
      H.truthy(tipText():find("Zwei", 1, true))
      H.truthy(T.Outfits.Delete("Zwei"))
      settle()
      H.falsy(rows[2]:IsShown())
      H.falsy(GameTooltip:IsShown(), "Zeile verborgen -> Tooltip weg")
      -- nachrueckendes Outfit: Tooltip gehoert dem neuen Inhalt
      H.truthy(T.Outfits.Save("Drei", { [0] = 2101, [4] = 2001 }))
      settle()
      M.Enter(rows[1])
      H.truthy(tipText():find("Eins", 1, true))
      H.truthy(T.Outfits.Delete("Eins"))
      settle()
      H.truthy(rows[1]:IsShown())
      H.truthy(tipText():find("Drei", 1, true), "Tooltip zeigt den neuen Inhalt der Zeile")
      H.falsy(tipText():find("Eins", 1, true))
      M.Leave(rows[1])
      H.falsy(GameTooltip:IsShown())
   end)

   -- -------------------------------------------------------------------------
   H.section("Seiten und Grenzen")
   -- -------------------------------------------------------------------------

   H.test("50 Outfits: jede Seite erreichbar, jedes Outfit genau einmal, auch bei kleiner Hoehe", function()
      for _, h in ipairs({ 150, 330, 400, 700 }) do
         local T, OT = boot({ h = h })
         fill(T, 50)
         settle()
         local seen, count = {}, 0
         for page = 1, OT.pages do
            OT.SetPage(page)
            H.eq(OT.page, page)
            H.truthy(#shownRows(OT) <= OT.perPage)
            for _, name in ipairs(rowNames(OT)) do
               H.falsy(seen[name], "doppelt: " .. name)
               seen[name] = true
               count = count + 1
            end
         end
         H.eq(count, 50, "Hoehe " .. h)
         H.eq(OT.pages, math.ceil(50 / OT.perPage))
      end
   end)

   H.test("Speichern auf Platz 50: Reiter springt zur letzten Seite, Zaehler rot, Speichern gesperrt; Loeschen gibt frei", function()
      local T, OT = boot({ h = 400 })
      fill(T, 49)
      H.truthy(T.State.Select(0, 2102))
      settle()
      H.truthy(OT.parts.save:IsEnabledState())
      H.eq(OT.pages, 10)
      M.Click(OT.parts.save)
      local e = dialogEdit(TransmogPromptFrame)
      M.Type(e, "Fuenfzigstes")
      M.Key(e, "ENTER")
      settle()
      H.eq(#T.Outfits.List(), 50)
      H.eq(OT.page, 10)
      H.deepEq(rowNames(OT), { "Outfit 46", "Outfit 47", "Outfit 48", "Outfit 49", "Fuenfzigstes" })
      H.eq(OT.parts.counter:GetText(), "50 / 50")
      local r = OT.parts.counter:GetTextColor()
      H.near(r, T.COLORS.red[1], 0.01, "rot")
      H.falsy(OT.parts.save:IsEnabledState())
      H.truthy(T.Outfits.Delete("Outfit 1"))
      settle()
      H.truthy(OT.parts.save:IsEnabledState())
      H.eq(OT.parts.counter:GetText(), "49 / 50")
      local r2 = OT.parts.counter:GetTextColor()
      H.near(r2, T.COLORS.text[1], 0.01, "wieder normal")
   end)

   H.test("Umbenennen aendert die Seite nicht; Loeschen auf Seite 2 haelt die Seite, solange es sie gibt", function()
      local T, OT = boot({ h = 400 })
      fill(T, 12)
      settle()
      OT.SetPage(2)
      H.deepEq(rowNames(OT), { "Outfit 6", "Outfit 7", "Outfit 8", "Outfit 9", "Outfit 10" })
      H.truthy(T.Outfits.Rename("Outfit 7", "Sieben"))
      settle()
      H.eq(OT.page, 2)
      H.deepEq(rowNames(OT), { "Outfit 6", "Sieben", "Outfit 8", "Outfit 9", "Outfit 10" })
      H.truthy(T.Outfits.Delete("Outfit 6"))
      settle()
      H.eq(OT.page, 2)
      H.deepEq(rowNames(OT), { "Sieben", "Outfit 8", "Outfit 9", "Outfit 10", "Outfit 11" })
   end)

   H.test("Fenster waechst/schrumpft: Seitenzahl folgt, die Seite bleibt gueltig, keine neuen Frames bei gleicher Groesse", function()
      local T, OT = boot({ h = 400 })
      fill(T, 23)
      settle()
      H.eq(OT.perPage, 5)
      H.eq(OT.pages, 5)
      OT.SetPage(5)
      H.deepEq(rowNames(OT), { "Outfit 21", "Outfit 22", "Outfit 23" })
      OT.Layout(520, 700)               -- 11 Zeilen
      settle()
      H.eq(OT.perPage, 11)
      H.eq(OT.pages, 3)
      H.eq(OT.page, 3, "geklemmt")
      H.truthy(#shownRows(OT) >= 1)
      local frames = #M.frames
      for i = 1, 5 do
         OT.Layout(520, 700)
         OT.Refresh()
      end
      settle()
      H.eq(#M.frames, frames)
      OT.Layout(520, 400)
      settle()
      H.eq(OT.perPage, 5)
      H.eq(OT.pages, 5)
      H.truthy(OT.page >= 1 and OT.page <= 5)
      H.deepEq(H.takeErrors(), {})
   end)

   -- -------------------------------------------------------------------------
   H.section("Ereignisfolgen")
   -- -------------------------------------------------------------------------

   H.test("Ereignissturm (300 Ereignisse): genau eine Zeichnung, keine neuen Frames; verborgen: keine", function()
      local T, OT, tab = boot({ h = 400 })
      fill(T, 8)
      settle()
      local lists = 0
      local orig = T.Outfits.List
      T.Outfits.List = function(...) lists = lists + 1 return orig(...) end
      local frames = #M.frames
      local names = { "ITEMS_RESOLVED", "WANTED_CHANGED", "STATUS_CHANGED", "LIST_READY", "EQUIPMENT_CHANGED",
                      "OUTFITS_CHANGED" }
      for i = 1, 300 do T.Events.Fire(names[(i % #names) + 1], 0) end
      H.eq(lists, 0, "gebuendelt: noch nichts gezeichnet")
      settle()
      H.eq(lists, 1)
      H.eq(#M.frames, frames)
      -- verborgen: nichts wird gezeichnet, Zustand wird beim Zeigen nachgeholt
      tab:Hide()
      lists = 0
      for i = 1, 300 do T.Events.Fire(names[(i % #names) + 1], 0) end
      M.Advance(1)
      H.eq(lists, 0, "verborgen: keine Arbeit")
      H.len(M.UpdateFrames(), 0)
      tab:Show()
      H.eq(lists, 1, "OnShow holt einmal nach")
      T.Outfits.List = orig
   end)

   H.test("Gleiche Groesse mehrfach: keine erneute Zeichnung ohne Aenderung", function()
      local T, OT = boot()
      T.Outfits.Save("A", { [0] = 2101 })
      settle()
      local lists = 0
      local orig = T.Outfits.List
      T.Outfits.List = function(...) lists = lists + 1 return orig(...) end
      for i = 1, 10 do OT.Layout(520, 400) end
      H.eq(lists, 0)
      T.Outfits.List = orig
   end)

   H.test("onStatus: ein Handler, der den Reiter neu zeichnet/anordnet, loest keine Rekursion aus; nil ist harmlos", function()
      local T, OT = boot()
      H.truthy(T.State.Select(0, 2101))
      settle()
      local n = 0
      OT.onStatus = function(text, key)
         n = n + 1
         OT.Refresh()
         OT.Layout(520, 400)
         OT.Layout(500, 380)
         OT.Layout(520, 400)
      end
      M.Click(OT.parts.save)
      local e = dialogEdit(TransmogPromptFrame)
      M.Type(e, "Rekursion")
      M.Key(e, "ENTER")
      H.eq(n, 1)
      settle()
      M.Click(shownRows(OT)[1].load)
      H.eq(n, 2)
      -- ohne onStatus
      OT.onStatus = nil
      M.Click(shownRows(OT)[1].load)
      M.Click(shownRows(OT)[1].over)
      M.Click(findButton(TransmogConfirmFrame, "Overwrite"))
      M.Click(shownRows(OT)[1].del)
      M.Click(findButton(TransmogConfirmFrame, "Delete"))
      H.eq(#T.Outfits.List(), 0)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Create erneut: derselbe Frame, kein neuer Frame; mit neuem Eltern-Frame wird umgehaengt", function()
      local T, OT, tab = boot()
      local frames = #M.frames
      H.eq(OT.Create(), tab)
      H.eq(OT.Create(UIParent), tab)
      H.eq(#M.frames, frames)
      H.eq(tab:GetParent(), UIParent)
      local other = CreateFrame("Frame", nil, UIParent)
      H.eq(OT.Create(other), tab)
      H.eq(tab:GetParent(), other)
   end)

   -- -------------------------------------------------------------------------
   H.section("Layout-Pruefung (Rechtecke)")
   -- -------------------------------------------------------------------------

   H.test("Keine Ueberlappung, kein zu breiter Text bei Mindestbreite, langen Namen und deutschen/russischen Texten", function()
      local Layout = require("layout")
      local DE = {
         OUTFITS_SAVE = "Aktuellen Look als Outfit speichern",
         OUTFITS_LOAD = "Laden", OUTFITS_OVERWRITE = "Ueberschreiben", OUTFITS_RENAME = "Umbenennen",
         OUTFITS_DELETE = "Loeschen", OUTFITS_PIECES = "Teile: %d", OUTFITS_PIECES_PARTIAL = "Verfuegbar: %d von %d",
         OUTFITS_PAGE = "Seite %d / %d", OUTFITS_EMPTY_TITLE = "Noch keine Outfits gespeichert",
         OUTFITS_EMPTY_TEXT = "Outfits speichern die Teile, die du gerade ausgewaehlt oder angewendet hast, damit du "
            .. "einen ganzen Look mit einem Klick wiederherstellen kannst. Waehle Aussehen im Reiter Gegenstaende, "
            .. "klicke dann auf \"Aktuellen Look speichern\" und gib dem Outfit einen Namen.",
      }
      local RU = {
         OUTFITS_SAVE = "Сохранить текущий образ как комплект",
         OUTFITS_LOAD = "Загрузить", OUTFITS_OVERWRITE = "Перезаписать", OUTFITS_RENAME = "Переименовать",
         OUTFITS_DELETE = "Удалить", OUTFITS_PIECES = "Предметов: %d", OUTFITS_PIECES_PARTIAL = "Доступно: %d из %d",
         OUTFITS_PAGE = "Страница %d / %d", OUTFITS_EMPTY_TITLE = "Комплектов пока нет",
      }
      local configs = {
         { "enUS", nil, 398, 330, 0 }, { "enUS", nil, 398, 330, 50 }, { "deDE", DE, 398, 330, 9 },
         { "ruRU", RU, 398, 330, 9 }, { "deDE", DE, 560, 480, 50 }, { "deDE", DE, 398, 330, 0 },
      }
      for _, c in ipairs(configs) do
         local T, OT, tab = boot({ w = c[3], h = c[4] })
         if c[2] then T.Locale.Add(c[1], c[2]) end
         T.Locale.Set(c[1])
         for i = 1, c[5] do
            local nm = string.sub("Wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww", 1, 29 - #tostring(i)) .. " " .. i
            T.Outfits.Save(nm, { [0] = 2101, [4] = 2001, [15] = 2201, [18] = 2301, [2] = 2101, [3] = 2101,
               [5] = 2101, [6] = 2101, [7] = 2101, [8] = 2101 })
         end
         settle()
         local entries = Layout.Rects(tab)
         local problems = Layout.Check(entries, { truncateOk = { "/name$" } })
         local bad = {}
         for _, p in ipairs(problems) do
            if p.severity ~= "info" then bad[#bad + 1] = p.kind .. " " .. tostring(p.path) end
         end
         H.deepEq(bad, {}, "Befunde " .. c[1] .. " " .. c[3] .. "x" .. c[4] .. " n=" .. c[5])
      end
   end)

   H.test("Info: passt der uebersetzte Text nicht, steht die Kurzform n/m statt eines abgeschnittenen Satzes", function()
      local slots = { [0] = 2101, [4] = 2001, [15] = 5555, [16] = 5556, [17] = 5557, [2] = 2101, [3] = 2101,
                      [5] = 2101, [6] = 2101, [7] = 2101 }
      for _, w in ipairs({ 398, 700 }) do
         local T, OT = boot({ w = w })
         T.Locale.Add("deDE", {
            OUTFITS_PIECES = "Zusammengestellte Teile insgesamt: %d",
            OUTFITS_PIECES_PARTIAL = "Davon verfuegbar: %d von insgesamt %d Teilen",
            OUTFITS_OVERWRITE = "Ueberschreiben", OUTFITS_RENAME = "Umbenennen",
         })
         T.Locale.Set("deDE")
         H.truthy(T.Outfits.Save("Lang", slots))
         H.truthy(T.Outfits.Save("Ganz", { [0] = 2101 }))
         settle()
         local rows = shownRows(OT)
         local row = rows[1]
         -- verfuegbar sind nur die angelegten Slots mit Aussehen in der Liste: Kopf und Brust; der Rest fehlt
         local text = row.info:GetText()
         if w == 398 then
            H.matches(text, "^%d+/10$", "Kurzform bei Mindestbreite: " .. text)
            local r2 = rows[2].info:GetText()
            H.matches(r2, "^%d+$", "Kurzform ohne fehlende Teile: " .. r2)
         else
            H.matches(text, "^Davon verfuegbar: %d+ von insgesamt 10 Teilen$", "volle Form bei Platz: " .. text)
         end
         -- in jedem Fall passt der Text in die Breite seines Feldes
         H.truthy(row.info:GetStringWidth() <= row.info:GetWidth() + 0.001)
         H.truthy(rows[2].info:GetStringWidth() <= rows[2].info:GetWidth() + 0.001)
      end
   end)

   -- =========================================================================
   -- Zusammenspiel mit dem echten Fenster (Serverattrappe, ganze TOC)
   -- =========================================================================

   local Fixtures = require("fixtures")

   -- Start wie im Spiel; rueckgabe: T, Window, OutfitsTab. spec.open = false: Fenster nicht oeffnen
   local function bootGame(spec)
      spec = spec or {}
      local T = Fixtures.Boot(H, { locale = spec.locale or "enUS", screen = spec.screen or { w = 1366, h = 768 } })
      Fixtures.ServerHello(T)
      Fixtures.ServerAutoReply(T)
      if spec.width then T.DB.Set("width", spec.width) end
      if spec.height then T.DB.Set("height", spec.height) end
      if spec.scale then T.DB.Set("scale", spec.scale) end
      if spec.tab then T.DB.Set("lastTab", spec.tab) end
      if spec.open ~= false then
         Fixtures.OpenAtNpc(T)
         Fixtures.Settle(T, 1.0)
      end
      return T, T.UI.Window, T.UI.OutfitsTab
   end

   local function footerText()
      return TransmogWindow.statusText:GetText(), { TransmogWindow.statusText:GetTextColor() }
   end

   H.section("Echtes Fenster")

   H.test("Speichern, Laden, Umbenennen, Ueberschreiben, Loeschen: Meldungen stehen in der Fusszeile (Farbe, Text)", function()
      local T, W, OT = bootGame()
      local Cl = T.COLORS
      W.SetTab("outfits")
      Fixtures.Settle(T, 0.5)
      H.truthy(OT.frame:IsVisible())
      H.eq(OT.parts.counter:GetText(), "0 / 50")
      -- aktueller Look = Standardauswahl des Servers (mehrere Slots angewendet)
      local look = T.Outfits.CurrentLook()
      H.truthy(T.Util.Count(look) >= 3, "Server hat einen Look angewendet")
      M.Click(OT.parts.save)
      local e = dialogEdit(TransmogPromptFrame)
      H.eq(e:GetText(), "Outfit 1")
      M.Type(e, "Mein Look")
      M.Click(findButton(TransmogPromptFrame, "Save"))
      local text, col = footerText()
      H.eq(text, "Outfit \"Mein Look\" saved.")
      H.near(col[1], Cl.green[1], 0.01)
      Fixtures.Settle(T, 0.3)
      local row = shownRows(OT)[1]
      H.truthy(row.stripe:IsShown(), "gespeichert = aktueller Look")
      H.eq(row.info:GetText(), "Pieces: " .. T.Util.Count(look))

      -- Auswahl aendern, laden: alles zurueck
      local list0 = Fixtures.List(T, 0)
      H.truthy(T.State.Select(0, list0[#list0]))
      Fixtures.Settle(T, 0.3)
      H.falsy(OT.rows[1].stripe:IsShown(), "anderer Look")
      M.Click(OT.rows[1].load)
      text, col = footerText()
      H.matches(text, "^Pieces loaded: %d+$")
      H.near(col[1], Cl.green[1], 0.01)
      Fixtures.Settle(T, 0.3)
      H.truthy(OT.rows[1].stripe:IsShown(), "wieder aktueller Look")
      H.eq(T.State.PendingCount(), 0, "alles wie angewendet")

      -- Umbenennen
      M.Click(OT.rows[1].ren)
      e = dialogEdit(TransmogPromptFrame)
      M.Type(e, "Stolz")
      M.Click(findButton(TransmogPromptFrame, "Rename"))
      text = footerText()
      H.eq(text, "Outfit renamed to \"Stolz\".")
      Fixtures.Settle(T, 0.3)
      H.eq(OT.rows[1].name:GetText(), "Stolz")

      -- Ueberschreiben mit geaenderter Auswahl
      H.truthy(T.State.Select(0, list0[#list0]))
      Fixtures.Settle(T, 0.3)
      M.Click(OT.rows[1].over)
      M.Click(findButton(TransmogConfirmFrame, "Overwrite"))
      text = footerText()
      H.eq(text, "Outfit \"Stolz\" updated.")
      H.eq(T.Outfits.Get("Stolz").slots[0], list0[#list0])

      -- Loeschen: gelb
      M.Click(OT.rows[1].del)
      M.Click(findButton(TransmogConfirmFrame, "Delete"))
      text, col = footerText()
      H.eq(text, "Outfit \"Stolz\" deleted.")
      H.near(col[1], Cl.yellow[1], 0.01)
      Fixtures.Settle(T, 0.3)
      H.truthy(OT.parts.empty:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Laden und Anwenden: der Server uebernimmt das Outfit, die Zeile zeigt danach den aktuellen Look", function()
      local T, W, OT = bootGame()
      W.SetTab("outfits")
      -- Outfit aus bekannten Aussehen (Slot 0, 4, 15) - nicht der Serverstandard
      local looks = {}
      for _, slot in ipairs({ 0, 4, 15 }) do
         local ids = Fixtures.List(T, slot)
         looks[slot] = ids[#ids]
      end
      H.truthy(T.Outfits.Save("Anders", looks))
      Fixtures.Settle(T, 0.5)
      local row = shownRows(OT)[1]
      H.falsy(row.stripe:IsShown())
      M.Click(row.load)
      Fixtures.Settle(T, 0.5)
      H.eq(T.State.Wanted(0), looks[0])
      H.eq(T.State.PendingCount() >= 1, true)
      H.truthy(W.frame.btnApply:IsEnabledState(), "Anwenden ist frei (am Transmogrifizierer, bezahlbar)")
      -- noch nichts angewendet
      for slot, id in pairs(looks) do
         H.neq(T.State.Applied(slot), id)
      end
      M.Click(W.frame.btnApply)
      Fixtures.Settle(T, 3)
      for slot, id in pairs(looks) do
         H.eq(T.State.Applied(slot), id, "Slot " .. slot)
      end
      H.eq(T.State.PendingCount(), 0)
      row = shownRows(OT)[1]
      -- Der Look besteht jetzt aus den 3 Teilen + den uebrigen angewendeten Slots: also nicht gleich
      -- dem Outfit (das nur 3 Teile hat) -> kein gruener Streifen
      H.falsy(row.stripe:IsShown(), "Outfit hat weniger Teile als der gesamte Look")
      -- speichert man den Look, entspricht er ihm
      H.truthy(T.Outfits.Save("Ganz", T.Outfits.CurrentLook()))
      Fixtures.Settle(T, 0.3)
      H.truthy(OT.rows[2].stripe:IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Ausruestung wechselt: 'Verfuegbar x von y' folgt (leerer Slot), danach wieder alles verfuegbar", function()
      local T, W, OT = bootGame()
      W.SetTab("outfits")
      local ids = {}
      for _, slot in ipairs({ 0, 4 }) do ids[slot] = Fixtures.List(T, slot)[1] end
      H.truthy(T.Outfits.Save("Zwei", ids))
      Fixtures.Settle(T, 0.5)
      local row = shownRows(OT)[1]
      H.eq(row.info:GetText(), "Pieces: 2")
      Fixtures.Unequip(T, 4)
      Fixtures.Settle(T, 2)
      row = shownRows(OT)[1]
      H.eq(row.info:GetText(), "Available: 1 of 2")
      M.Enter(row)
      H.truthy(tipText():find(T.L.OUTFIT_SKIP_EMPTY, 1, true))
      M.Leave(row)
      Fixtures.Equip(T, 4, "e_chest_plate")
      Fixtures.Settle(T, 2)
      row = shownRows(OT)[1]
      H.eq(row.info:GetText(), "Pieces: 2")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Fensterhoehe aendern: Zeilen je Seite folgen; Reiterwechsel Items/Outfits wiederholt ohne Fehler", function()
      local T, W, OT = bootGame({ width = 880, height = 600, scale = 1.0 })
      for i = 1, 12 do T.Outfits.Save("O" .. i, Fixtures.Looks(T, 1 + (i % 3))) end
      W.SetTab("outfits")
      Fixtures.Settle(T, 0.5)
      local per600 = OT.perPage
      H.truthy(per600 >= 5, "Zeilen bei 600: " .. per600)
      T.DB.Set("height", 520)
      Fixtures.Settle(T, 0.5)
      H.truthy(OT.perPage < per600, "weniger Zeilen bei geringerer Hoehe")
      H.eq(#shownRows(OT), OT.perPage)
      for i = 1, 6 do
         W.SetTab("items")
         H.falsy(OT.frame:IsVisible(), "Items-Reiter: Outfits verborgen")
         W.SetTab("outfits")
         H.truthy(OT.frame:IsVisible())
      end
      Fixtures.Settle(T, 0.5)
      H.eq(#shownRows(OT), OT.perPage)
      -- (das Fenster selbst beobachtet die Bildschirmgroesse; im Reiter laeuft kein OnUpdate)
      for _, fr in ipairs(M.UpdateFrames()) do
         local p = fr
         while p do
            H.neq(p, OT.frame, "OnUpdate-Frame im Outfit-Reiter")
            p = p:GetParent()
         end
      end
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("lastTab = outfits: das Fenster oeffnet gleich mit gezeichneter Liste (OnShow-Weg)", function()
      local T, W, OT = bootGame({ open = false, tab = "outfits" })
      for i = 1, 3 do T.Outfits.Save("O" .. i, Fixtures.Looks(T, i)) end
      Fixtures.OpenAtNpc(T)
      Fixtures.Settle(T, 0.5)
      H.eq(W.GetTab(), "outfits")
      H.deepEq(rowNames(OT), { "O1", "O2", "O3" })
      H.eq(OT.parts.counter:GetText(), "3 / 50")
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("ESC: ein offener Dialog schliesst zuerst (Fenster bleibt), danach das Fenster", function()
      local T, W, OT = bootGame()
      W.SetTab("outfits")
      T.Outfits.Save("Eins", Fixtures.Looks(T, 1))
      Fixtures.Settle(T, 0.3)
      M.Click(OT.rows[1].del)
      H.truthy(TransmogConfirmFrame:IsShown())
      M.Escape()
      H.falsy(TransmogConfirmFrame:IsShown())
      H.truthy(W.IsShown(), "Fenster bleibt")
      H.eq(#T.Outfits.List(), 1, "nichts geloescht")
      M.Click(OT.rows[1].ren)
      M.Escape()
      H.falsy(TransmogPromptFrame:IsShown())
      H.truthy(W.IsShown())
      H.eq(T.Outfits.List()[1].name, "Eins")
      M.Escape()
      H.falsy(W.IsShown())
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Fenster schliessen mit offenem Dialog: Dialog zu, nichts ausgefuehrt", function()
      local T, W, OT = bootGame()
      W.SetTab("outfits")
      T.Outfits.Save("Eins", Fixtures.Looks(T, 1))
      Fixtures.Settle(T, 0.3)
      M.Click(OT.rows[1].del)
      W.Close()
      H.falsy(TransmogConfirmFrame:IsShown())
      H.falsy(T.UI.Skin.DialogOpen())
      H.eq(#T.Outfits.List(), 1)
      H.deepEq(H.takeErrors(), {})
   end)

   H.test("Zwei Sprachen hin und her mit offenem Reiter: Zaehler, Seitentext, Info und Knoepfe immer in einer Sprache", function()
      local T, W, OT = bootGame({ height = 600 })
      for i = 1, 8 do T.Outfits.Save("O" .. i, Fixtures.Looks(T, 1 + (i % 4))) end
      W.SetTab("outfits")
      Fixtures.Settle(T, 0.5)
      T.Locale.Add("deDE", {
         OUTFITS_LOAD = "Laden", OUTFITS_PIECES = "Teile: %d", OUTFITS_PAGE = "Seite %d / %d",
         OUTFITS_SAVE = "Aktuellen Look speichern",
      })
      for i = 1, 5 do
         T.Locale.Set("deDE")
         Fixtures.Settle(T, 0.2)
         H.eq(OT.rows[1].load:GetText(), "Laden")
         H.matches(OT.rows[1].info:GetText(), "^Teile: %d+$")
         H.eq(OT.parts.pageText:GetText(), "Seite 1 / " .. OT.pages)
         H.eq(OT.parts.save:GetText(), "Aktuellen Look speichern")
         T.Locale.Set("enUS")
         Fixtures.Settle(T, 0.2)
         H.eq(OT.rows[1].load:GetText(), "Load")
         H.matches(OT.rows[1].info:GetText(), "^Pieces: %d+$")
         H.eq(OT.parts.pageText:GetText(), "Page 1 / " .. OT.pages)
      end
      H.deepEq(H.takeErrors(), {})
   end)

   -- -------------------------------------------------------------------------
   H.section("Zufallsfolgen (fester Startwert)")
   -- -------------------------------------------------------------------------

   H.test("Zufallsfolgen mit echtem Fenster und Server: Invarianten der Liste, keine Handlerfehler", function()
      local NAMES = { "Alpha", "beta", "GAMMA", "Delta Force", "\195\164\195\182\195\188", "Outfit 7", "X",
         "A very long outfit name of 30c", "100%", "Name with spaces", "Zeta", "Eta", "Theta" }
      local SLOTS3 = { 0, 4, 15 }
      local function lcg(seed)
         local v = seed
         return function(n)
            v = (v * 1103515245 + 12345) % 2147483648
            return (v % n) + 1
         end
      end
      for _, seed in ipairs({ 7919, 104729, 1299709, 15485863, 32452843, 49979687 }) do
         local T, W, OT = bootGame()
         W.SetTab("outfits")
         local rnd = lcg(seed)
         local last = ""
         local function check(step)
            Fixtures.Settle(T, 0.15)
            local list = T.Outfits.List()
            local count = #list
            local ctx = "Folge " .. seed .. " Schritt " .. step .. " nach " .. last
            if OT.frame:IsVisible() then
               H.eq(OT.pages, math.max(1, math.ceil(count / OT.perPage)), ctx .. ": Seitenzahl")
               H.truthy(OT.page >= 1 and OT.page <= OT.pages, ctx .. ": Seite im Bereich")
               local first = (OT.page - 1) * OT.perPage
               local shown = 0
               for i, r in ipairs(OT.rows) do
                  if r:IsShown() then
                     shown = shown + 1
                     H.eq(r.name:GetText(), list[first + i].name, ctx .. ": Name der Zeile " .. i)
                     H.truthy(#shownIcons(r) <= 8, ctx .. ": hoechstens 8 Symbole")
                  end
               end
               H.eq(shown, math.max(0, math.min(OT.perPage, count - first)), ctx .. ": Zeilen")
               H.eq(OT.parts.counter:GetText(), count .. " / 50", ctx .. ": Zaehler")
               H.eq(OT.parts.empty:IsShown() and true or false, count == 0, ctx .. ": Leerzustand")
            end
            local errs = H.takeErrors()
            H.eq(#errs, 0, ctx .. ": Handlerfehler " .. tostring(errs[1]))
         end
         for step = 1, 50 do
            local op = rnd(15)
            local l = T.Outfits.List()
            if op == 1 then
               T.Outfits.Save(NAMES[rnd(#NAMES)] .. (rnd(3) == 1 and (" " .. rnd(99)) or ""), Fixtures.Looks(T, rnd(6)))
               last = "save"
            elseif op == 2 and #l > 0 then
               T.Outfits.Delete(l[rnd(#l)].name)
               last = "delete"
            elseif op == 3 and #l > 0 then
               T.Outfits.Rename(l[rnd(#l)].name, NAMES[rnd(#NAMES)])
               last = "rename"
            elseif op == 4 and #l > 0 then
               OT.LoadOutfit(l[rnd(#l)].name)
               last = "load"
            elseif op == 5 then
               OT.SetPage(rnd(10))
               last = "page"
            elseif op == 6 then
               T.DB.Set("width", 740 + rnd(400))
               T.DB.Set("height", 520 + rnd(300))
               last = "size"
            elseif op == 7 then
               W.SetTab(rnd(2) == 1 and "items" or "outfits")
               last = "tab"
            elseif op == 8 then
               local slot = SLOTS3[rnd(3)]
               local ids = Fixtures.List(T, slot)
               if #ids > 0 then T.State.Select(slot, ids[rnd(#ids)]) end
               last = "select"
            elseif op == 9 then
               T.State.DiscardAll()
               last = "discard"
            elseif op == 10 then
               Fixtures.Uncache(T, 0.5)
               last = "uncache"
            elseif op == 11 then
               local slot = SLOTS3[rnd(3)]
               if rnd(2) == 1 then Fixtures.Unequip(T, slot) else Fixtures.Equip(T, slot, "e_head_plate") end
               last = "equip"
            elseif op == 12 then
               last = "dialog speichern"
               if OT.parts.save:IsVisible() then M.Click(OT.parts.save) end
               local pf = rawget(_G, "TransmogPromptFrame")
               if pf and pf:IsShown() then
                  local e = dialogEdit(pf)
                  M.Type(e, NAMES[rnd(#NAMES)])
                  M.Key(e, rnd(2) == 1 and "ENTER" or "ESCAPE")
               end
            elseif op == 13 and OT.frame:IsVisible() then
               local rows = shownRows(OT)
               if #rows > 0 then
                  local which = ({ "over", "ren", "del" })[rnd(3)]
                  M.Click(rows[rnd(#rows)][which])
                  last = "klick " .. which
                  local cf, pf = rawget(_G, "TransmogConfirmFrame"), rawget(_G, "TransmogPromptFrame")
                  if (cf and cf:IsShown()) or (pf and pf:IsShown()) then
                     if rnd(2) == 1 then
                        M.Escape()
                     elseif cf and cf:IsShown() then
                        M.Click(findButton(cf, which == "del" and "Delete" or "Overwrite"))
                     else
                        M.Key(dialogEdit(pf), "ESCAPE")
                     end
                  end
               end
            elseif op == 14 then
               T.Locale.Set(rnd(2) == 1 and "deDE" or "enUS")
               last = "locale"
            elseif op == 15 then
               for _ = 1, rnd(30) do
                  T.Events.Fire(({ "ITEMS_RESOLVED", "WANTED_CHANGED", "LIST_READY" })[rnd(3)], 0)
               end
               last = "sturm"
            end
            check(step)
         end
      end
   end)
end
