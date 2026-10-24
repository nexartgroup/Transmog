-- tests/test_ui_flow.lua
-- ---------------------------------------------------------------------------
-- Ende-zu-Ende-Szenarien der ganzen Oberflaeche: ECHTER Kern (Boot, DB, Net,
-- State, Filter, Outfits), ECHTE Komponenten (Window, SlotBar, Preview, Grid,
-- FilterBar, OutfitsTab, Options, Skin, Tooltips, Toasts) und der Server-
-- Nachbau aus tests/fixtures.lua. Es werden nur die oeffentlichen Wege des
-- Spielers benutzt (Klicks, Eingaben, Slash-Befehle, ESC, Server-Antworten).
--
--   Anmeldung -> NPC-Gossip oeffnet das Fenster -> Slot -> Liste laedt (Items
--   unbekannt, laufen ueber die Zeit ein) -> Aussehen waehlen -> Vorschau ->
--   Kosten -> Anwenden -> Ergebnis/Status
--   Vorschau-Modus per Slash, Verbergen, Alles entfernen (Rueckfrage),
--   Outfit speichern/laden/loeschen/anwenden, Filter/Suche/Sortierung/Favoriten,
--   Groesse und Scale, Sprachwechsel, Ausruestungswechsel, Server schweigt,
--   Schliessen per ESC und per X, Wiederoeffnen mit gemerktem Zustand
--
-- Nach JEDEM Szenario (assertHealthy/assertIdle): keine Handlerfehler, keine
-- fremden Globals oder Frames, keine fehlenden Locale-Schluessel, bei
-- geschlossenem Fenster kein OnUpdate und kein Timer, keine offenen Dialoge,
-- Menues oder Tooltips.
--
-- Aufruf:  cd <Addon>;  luajit tests/run.lua ui_flow
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock
   local Fixtures = require("fixtures")

   -- -----------------------------------------------------------------------
   -- Konstanten
   -- -----------------------------------------------------------------------

   local HEAD, SHOULDER, SHIRT, CHEST, WAIST, LEGS, FEET, WRIST, HANDS = 0, 2, 3, 4, 5, 6, 7, 8, 9
   local BACK, MAINHAND, OFFHAND, RANGED, TABARD = 14, 15, 16, 17, 18
   local HIDDEN = 999999
   local SERVER_SLOTS = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }

   -- -----------------------------------------------------------------------
   -- Zustand und Hilfen
   -- -----------------------------------------------------------------------

   local FX          -- die Addon-Tabelle Transmog (Fixtures.Boot)
   local srv         -- Server-Nachbau

   -- Startet Addon und Server. o: wie Fixtures.Boot; o.hello=false, o.reply=false, o.mute=true,
   -- o.price, o.helloOpts
   local function boot(o)
      o = o or {}
      FX = Fixtures.Boot(H, o)
      srv = nil
      if o.hello ~= false then Fixtures.ServerHello(FX, o.helloOpts) end
      if o.reply ~= false then
         srv = Fixtures.ServerAutoReply(FX, { price = o.price, mute = o.mute })
      end
      return FX
   end

   local function settle(seconds) Fixtures.Settle(FX, seconds or 0.5) end
   local function Win() return FX.UI.Window end
   local function F() return FX.UI.Window.frame end
   local function Grid() return FX.UI.Grid end
   local function LL() return FX.L end

   -- Fenster wie am Transmogrifizierer oeffnen (Open + GOSSIP_SHOW)
   local function openNpc(settleSeconds)
      local w = Fixtures.OpenAtNpc(FX)
      if settleSeconds ~= 0 then settle(settleSeconds or 1.0) end
      return w
   end

   -- Fenster per /transmog (Vorschau-Modus)
   local function openPreview(settleSeconds)
      M.Slash("/transmog")
      if settleSeconds ~= 0 then settle(settleSeconds or 1.0) end
   end

   -- Sichtbare Zelle des Rasters, die den Gegenstand id zeigt (nil: nicht auf dieser Seite)
   local function cellOf(id)
      for _, c in ipairs(Grid().cells) do
         if c:IsShown() and c.kind == "item" and c.itemId == id then return c end
      end
      return nil
   end

   -- Zelle der Art "original" / "hidden"
   local function cellKind(kind)
      for _, c in ipairs(Grid().cells) do
         if c:IsShown() and c.kind == kind then return c end
      end
      return nil
   end

   -- Erste sichtbare Item-Zelle (n-te)
   local function itemCell(n)
      local k = 0
      for _, c in ipairs(Grid().cells) do
         if c:IsShown() and c.kind == "item" then
            k = k + 1
            if k == n then return c end
         end
      end
      return nil
   end

   -- Alle sichtbaren Buttons unter root, deren Beschriftung gleich text ist
   local function buttonsLabelled(root, text)
      local out = {}
      if not root then return out end
      M.Walk(root, function(o)
         if o.__type == "Button" and o.__shown ~= false and o.label and o.label.GetText
            and o.label:GetText() == text then
            out[#out + 1] = o
         end
      end)
      return out
   end

   local function visibleButton(root, text)
      for _, b in ipairs(buttonsLabelled(root, text)) do
         if M.U.isVisible(b) then return b end
      end
      return nil
   end

   -- Knoepfe des Rueckfragedialogs / Eingabedialogs
   local function dialogFrame()
      for _, name in ipairs({ "TransmogConfirmFrame", "TransmogPromptFrame" }) do
         local f = rawget(_G, name)
         if f and f:IsShown() then return f end
      end
      return nil
   end

   local function dialogButton(text)
      return visibleButton(dialogFrame(), text)
   end

   -- Text im Eingabedialog setzen (wie getippt) und bestaetigen
   local function promptType(text)
      local f = rawget(_G, "TransmogPromptFrame")
      H.truthy(f and f:IsShown(), "Eingabedialog offen")
      local edit
      for _, e in ipairs(M.Find(f, "EditBox")) do
         -- (der unsichtbare 2x2-Tastaturfaenger des Dialogs zaehlt nicht)
         if M.U.isVisible(e) and (e:GetWidth() or 0) > 10 then edit = e end
      end
      H.truthy(edit, "Eingabefeld")
      M.Type(edit, text)
      return edit
   end

   local function menuItems()
      local f = rawget(_G, "TransmogMenuFrame")
      local out = {}
      if f and f:IsShown() then
         for _, b in ipairs(M.Find(f, "Button")) do
            if M.U.isVisible(b) and b.item then out[#out + 1] = b end
         end
      end
      return out
   end

   local function menuItem(text)
      for _, b in ipairs(menuItems()) do
         if b.item.text == text then return b end
      end
      return nil
   end

   -- Alle Elemente der Statuszeile/Kosten
   local function status() return F().statusText:GetText() or "" end
   local function costText() return F().costText:GetText() or "" end

   -- Wie viele Modelle haben das Aussehen id anprobiert? (Vorschau)
   local function previewTried(id)
      local view = M.Model(FX.UI.Preview.model)
      for _, v in ipairs(view.tried) do
         if v == id then return true end
      end
      return false
   end

   -- Slotknopf
   local function slotButton(slot)
      return FX.UI.SlotBar.Get().buttons[slot]
   end

   -- Liste (Server) eines Slots
   local function ids(slot) return FX.State.List(slot).ids end

   -- -----------------------------------------------------------------------
   -- Gesundheitspruefungen nach einem Szenario
   -- -----------------------------------------------------------------------

   -- Keine Fehler, keine fremden Globals/Frames, keine fehlenden Locale-Schluessel
   local function assertHealthy(label)
      label = label or ""
      local errs = M.errors
      if #errs > 0 then
         H.fail(label .. ": Handlerfehler: " .. tostring(errs[1]))
         M.ClearErrors()
      else
         H.eq(#errs, 0, label)
      end
      H.deepEq(M.StrayGlobals(), {}, label .. ": fremde Globals")
      H.deepEq(M.StrayFrameNames(), {}, label .. ": fremde benannte Frames")
      local missing = {}
      for k in pairs(FX.L.__missing) do missing[#missing + 1] = k end
      table.sort(missing)
      H.deepEq(missing, {}, label .. ": fehlende Locale-Schluessel")
      H.eq(#M.missingAssets, 0, label .. ": fehlende Dateien")
   end

   -- Fenster zu, Leerlauf: kein OnUpdate, kein Timer, keine Dialoge/Menues/Tooltips
   local function assertIdle(label)
      label = label or ""
      H.falsy(Win().IsShown(), label .. ": Fenster zu")
      settle(25)
      local upd = M.UpdateFrames()
      local names = {}
      for _, f in ipairs(upd) do names[#names + 1] = f.__name or M.U.describe(f) end
      H.deepEq(names, {}, label .. ": aktive OnUpdate-Frames")
      H.eq(FX.Util.TimerCount(), 0, label .. ": Timer")
      H.falsy(FX.UI.Skin.DialogOpen(), label .. ": Dialog offen")
      H.falsy(FX.UI.Skin.Menu.IsOpen(), label .. ": Menue offen")
      H.falsy(rawget(_G, "TransmogMenuFrame") and TransmogMenuFrame:IsShown(), label .. ": Menuefenster")
      H.falsy(rawget(_G, "TransmogPromptFrame") and TransmogPromptFrame:IsShown(), label .. ": Prompt")
      H.falsy(rawget(_G, "TransmogConfirmFrame") and TransmogConfirmFrame:IsShown(), label .. ": Confirm")
      H.falsy(GameTooltip:IsShown(), label .. ": Tooltip")
      H.eq(FX.UI.Options and FX.UI.Options.IsShown() or false, false, label .. ": Optionen")
      H.eq(M.popup, nil, label .. ": StaticPopup")
      assertHealthy(label)
   end

   -- -----------------------------------------------------------------------
   -- 1. Der Hauptablauf
   -- -----------------------------------------------------------------------

   H.test("Ablauf: Anmeldung, NPC oeffnet das Fenster, Liste laedt, Aussehen waehlen, Kosten, Anwenden", function()
      boot({ cacheItems = false, itemCacheDelay = 1.2, price = 100000 })
      -- nach der Anmeldung: nichts gebaut, kein Fenster, kein OnUpdate
      H.eq(Win().frame, nil)
      H.eq(rawget(_G, "TransmogWindow"), nil)
      H.eq(FX.State.atVendor, false)
      H.eq(FX.Net.state, "OK")
      assertHealthy("nach der Anmeldung")

      -- NPC: "Open" + GOSSIP_SHOW -> Gossip weg, Fenster da, per NPC geoeffnet
      local w = openNpc(0)
      H.truthy(w)
      H.eq(w, rawget(_G, "TransmogWindow"))
      H.truthy(Win().IsShown())
      H.falsy(GossipFrame:IsShown(), "das Gossip-Fenster ist ersetzt")
      H.eq(FX.State.openedByNpc, true)
      H.eq(FX.State.atVendor, true)
      H.falsy(F().notice:IsShown(), "keine Vorschau-Hinweisleiste am NPC")
      H.eq(Win().currentSlot, HEAD, "erster bereiter Slot in Anzeigereihenfolge")
      H.eq(Win().GetTab(), "items")

      -- Liste da, Itemdaten fehlen: Ladezustand mit Fortschritt
      H.eq(Grid().mode, "LOADING")
      H.truthy(M.HasText(F(), "Loading"), "Ladetext sichtbar")

      -- ueber die Zeit laufen die Items ein, das Raster entsteht
      settle(0.3)
      H.eq(Grid().mode, "LOADING")
      local t = M.AdvanceUntil(function() return Grid().mode == "GRID" end, 10, 0.1)
      H.truthy(t, "das Raster erscheint, sobald die Itemdaten da sind")
      settle(0.3)
      H.eq(Grid().mode, "GRID")
      H.eq(FX.Items.PendingCount(), 0)
      local first = itemCell(1)
      H.truthy(first and first:IsShown())
      H.truthy(cellKind("original"), "Originalkachel (Kopf hat ein angewendetes Aussehen)")
      H.truthy(cellKind("hidden"), "Verborgen-Kachel (Kopf ist verbergbar)")

      -- Aussehen waehlen
      local id = first.itemId
      H.neq(FX.State.Applied(HEAD), id)
      M.Click(first)
      settle(0.1)
      H.truthy(FX.State.HasPending(HEAD))
      H.eq(FX.State.Wanted(HEAD), id)
      H.truthy(first.selected, "Zelle ist als ausgewaehlt markiert")
      H.eq(FX.State.PendingCount(), 1)
      settle(0.6)
      -- Vorschau angekleidet, Slotknopf markiert, Fuss: Kosten kommen vom Server
      H.truthy(previewTried(id), "die Vorschau probiert das gewaehlte Aussehen an")
      H.eq(slotButton(HEAD).stateKey, "pending")
      H.truthy(FX.State.Cost().valid)
      H.eq(FX.State.Cost().copper, 100000)
      H.contains(costText(), FX.Util.FormatMoney(100000))
      H.contains(status(), "1")
      H.eq(F().btnApply.uiOff, false)
      H.eq(F().btnDiscard.uiOff, false)
      H.eq(F().btnApply.label:GetText(), LL().WIN_APPLY)

      -- Anwenden
      M.Click(F().btnApply)
      settle(0.1)
      H.truthy(FX.State.Busy() or FX.State.Applied(HEAD) == id, "laeuft oder ist schon durch")
      settle(1.0)
      H.eq(FX.State.Applied(HEAD), id)
      H.eq(FX.State.PendingCount(), 0)
      H.eq(status(), LL().MSG_APPLY_OK)
      H.eq(costText(), "")
      H.eq(F().btnApply.uiOff, true)
      H.truthy(cellOf(id).applied, "die Zelle zeigt 'angewendet'")
      H.eq(slotButton(HEAD).stateKey, "applied")
      -- Server hat Apply gesehen
      local sawApply = false
      for _, c in ipairs(srv.log) do
         if c == "Apply:" .. HEAD .. ":" .. id then sawApply = true end
      end
      H.truthy(sawApply, "Apply:0:<id> ging raus")
      assertHealthy("Hauptablauf")

      -- Statuszeile verblasst nach der Frist
      settle(7)
      H.eq(status(), "")

      -- schliessen: ESC
      M.Escape()
      assertIdle("Hauptablauf")
   end)

   -- -----------------------------------------------------------------------
   -- 2. Vorschau-Modus per Slash
   -- -----------------------------------------------------------------------

   H.test("Vorschau-Modus per /transmog: Hinweis, Anwenden gesperrt, NPC macht daraus den Transmogrifizierer", function()
      boot({})
      openPreview(1.0)
      H.truthy(Win().IsShown())
      H.eq(FX.State.openedByNpc, false)
      H.eq(FX.State.atVendor, false)
      H.truthy(F().notice:IsShown(), "Hinweisleiste")
      H.eq(F().notice.text:GetText(), LL().MSG_NO_VENDOR)
      -- die Vorschau geht trotzdem: Aussehen waehlen, Kosten kommen
      local c = itemCell(1)
      H.truthy(c)
      local id = c.itemId
      M.Click(c)
      settle(0.8)
      H.eq(FX.State.Wanted(HEAD), id)
      H.truthy(previewTried(id), "Vorschau zeigt die Auswahl auch ohne Transmogrifizierer")
      H.eq(F().btnApply.uiOff, true)
      H.eq(F().btnApply.disabledTip, LL().APPLY_REASON_VENDOR)
      -- ein Klick auf den gesperrten Knopf sendet nichts
      M.ClearSent()
      M.Click(F().btnApply)
      settle(0.3)
      H.eq(M.CountSent("Apply"), 0)
      H.eq(FX.State.Applied(HEAD) == id, false)
      -- erneut /transmog: schliesst, ein fremdes Gossip-Fenster bleibt in Ruhe
      M.world.gossipOpen = true
      M.Slash("/transmog")
      H.falsy(Win().IsShown())
      H.eq(M.world.gossipOpen, true, "kein CloseGossip im Vorschau-Modus")
      M.world.gossipOpen = false
      -- die Auswahl bleibt beim Wiederoeffnen erhalten
      M.Slash("/xmog")
      settle(0.5)
      H.truthy(Win().IsShown())
      H.eq(FX.State.Wanted(HEAD), id, "Auswahl ueberlebt Schliessen und Oeffnen")
      -- Option "ueberall anwenden": Hinweis weg, Anwenden frei
      FX.DB.Set("allowAnywhere", true)
      settle(0.3)
      H.falsy(F().notice:IsShown())
      H.eq(F().btnApply.uiOff, false)
      FX.DB.Set("allowAnywhere", false)
      settle(0.3)
      H.truthy(F().notice:IsShown())
      H.eq(F().btnApply.uiOff, true)
      -- am NPC wird daraus der Transmogrifizierer: Hinweis weg, Anwenden frei
      openNpc(0.5)
      H.truthy(Win().IsShown())
      H.eq(FX.State.atVendor, true)
      H.eq(FX.State.openedByNpc, true)
      H.falsy(F().notice:IsShown())
      H.eq(F().btnApply.uiOff, false)
      H.eq(FX.State.Wanted(HEAD), id)
      -- Anwenden klappt
      M.Click(F().btnApply)
      settle(1.0)
      H.eq(FX.State.Applied(HEAD), id)
      assertHealthy("Vorschau-Modus")
      M.Click(F().btnClose)
      assertIdle("Vorschau-Modus")
      H.eq(M.world.gossipOpen, false)
   end)

   -- Seit 2.1 gilt "Anwenden auch ohne Transmogrifizierer" standardmaessig (Neuinstallation = noSeed): der Server
   -- prueft den Abstand zum NPC nicht. Der Vorschau-Modus oben bleibt, wenn der Spieler die Option ausschaltet.
   H.test("Ueberall anwenden (Vorgabe seit 2.1): /transmog ohne NPC, Aussehen waehlen, Anwenden und Alles entfernen klappen", function()
      boot({ noSeed = true })
      H.eq(FX.DB.global.allowAnywhere, true)
      H.eq(FX.DB.global.noNpcDefault, true)
      openPreview(1.0)
      H.truthy(Win().IsShown())
      H.eq(FX.State.openedByNpc, false)
      H.eq(FX.State.atVendor, false, "kein Transmogrifizierer in der Naehe")
      H.falsy(F().notice:IsShown(), "keine gelbe Hinweisleiste: das Fenster arbeitet voll")
      -- Aussehen waehlen: Vorschau, Kosten, Anwenden frei
      local c = itemCell(1)
      H.truthy(c)
      local id = c.itemId
      M.Click(c)
      settle(0.8)
      H.eq(FX.State.Wanted(HEAD), id)
      H.truthy(previewTried(id))
      H.eq(F().btnApply.uiOff, false, "Anwenden ist frei, obwohl kein NPC da ist")
      M.ClearSent()
      M.Click(F().btnApply)
      settle(1.0)
      H.eq(M.CountSent("Apply"), 1, "Apply ging an den Server")
      H.eq(FX.State.Applied(HEAD), id)
      H.eq(status(), LL().MSG_APPLY_OK)
      H.truthy(cellOf(id).applied)
      -- Alles entfernen ohne NPC
      H.eq(F().btnRemoveAll.uiOff, false)
      M.Click(F().btnRemoveAll)
      H.truthy(FX.UI.Skin.DialogOpen())
      M.Click(dialogButton(LL().WIN_REMOVE_ALL))
      H.eq(M.CountSent("RemoveAll"), 1)
      settle(1.0)
      for _, slot in ipairs(SERVER_SLOTS) do
         H.eq(FX.State.Applied(slot), 0, "Slot " .. slot)
      end
      -- der Spieler schaltet die Option aus: Vorschau-Modus (gelb, gesperrt), wie vor 2.1
      c = itemCell(2)
      M.Click(c)
      settle(0.8)
      H.eq(F().btnApply.uiOff, false)
      FX.DB.Set("allowAnywhere", false)
      settle(0.3)
      H.truthy(F().notice:IsShown())
      H.eq(F().notice.text:GetText(), LL().MSG_NO_VENDOR)
      H.eq(F().btnApply.uiOff, true)
      H.eq(F().btnApply.disabledTip, LL().APPLY_REASON_VENDOR)
      assertHealthy("Ueberall anwenden")
      M.Escape()
      assertIdle("Ueberall anwenden")
   end)

   -- -----------------------------------------------------------------------
   -- 3. Verbergen
   -- -----------------------------------------------------------------------

   H.test("Verbergen: Kachel waehlen, kostenlos, Vorschau leert den Platz, Anwenden, Rechtsklick auf den Slot", function()
      boot({})
      openNpc()
      -- Schulter ueber den Slotknopf waehlen
      M.Click(slotButton(SHOULDER))
      settle(0.5)
      H.eq(Win().currentSlot, SHOULDER)
      H.eq(FX.UI.SlotBar.Selected(), SHOULDER)
      local hid = cellKind("hidden")
      H.truthy(hid, "Verborgen-Kachel")
      H.eq(hid.applied, false)
      M.Click(hid)
      settle(0.8)
      H.eq(FX.State.Wanted(SHOULDER), HIDDEN)
      H.truthy(FX.State.HasPending(SHOULDER))
      H.truthy(hid.selected)
      H.eq(FX.State.Cost().copper, 0)
      H.truthy(FX.State.Cost().valid)
      H.eq(costText():find(LL().WIN_COST_FREE, 1, true) ~= nil, true, "Kosten: kostenlos")
      -- die Vorschau nimmt den Undress-Weg (neu gewaehltes Verborgen)
      local view = M.Model(FX.UI.Preview.model)
      H.truthy(view.undressed, "Vorschaumodell ist ausgezogen")
      H.eq(slotButton(SHOULDER).stateKey, "pending")
      -- anwenden
      M.Click(F().btnApply)
      settle(1.0)
      H.eq(FX.State.Applied(SHOULDER), HIDDEN)
      H.eq(FX.State.PendingCount(), 0)
      H.truthy(cellKind("hidden").applied, "Verborgen-Kachel als angewendet markiert")
      H.eq(slotButton(SHOULDER).stateKey, "applied")
      -- nach dem Anwenden zeigt SetUnit("player") den echten Zustand (der Server verbirgt die Schulter)
      H.falsy(M.Model(FX.UI.Preview.model).undressed)
      -- Waffen nie verborgen: Haupthand hat keine Verborgen-Kachel
      M.Click(slotButton(MAINHAND))
      settle(0.5)
      H.eq(Win().currentSlot, MAINHAND)
      H.eq(cellKind("hidden"), nil, "Waffen sind nicht verbergbar")
      H.eq(FX.State.Select(MAINHAND, HIDDEN), false)
      -- Rechtsklick auf den Schulter-Slot: Entfernen vormerken, nochmal: verwerfen
      M.Click(slotButton(SHOULDER), "RightButton")
      settle(0.3)
      H.truthy(FX.State.HasPending(SHOULDER))
      H.eq(FX.State.Wanted(SHOULDER), 0)
      H.eq(F().btnApply.label:GetText(), LL().WIN_APPLY_RESET)
      M.Click(slotButton(SHOULDER), "RightButton")
      settle(0.3)
      H.falsy(FX.State.HasPending(SHOULDER))
      H.eq(F().btnApply.label:GetText(), LL().WIN_APPLY)
      assertHealthy("Verbergen")
      M.Escape()
      assertIdle("Verbergen")
   end)

   -- -----------------------------------------------------------------------
   -- 4. Alles entfernen
   -- -----------------------------------------------------------------------

   H.test("Alles entfernen: Rueckfrage (ESC bricht ab), Bestaetigen entfernt alles, Knopf sperrt, Raster aktualisiert", function()
      boot({})
      openNpc()
      H.eq(F().btnRemoveAll.uiOff, false)
      H.truthy(cellKind("original"), "Kopf hat ein angewendetes Aussehen")
      H.falsy(cellKind("original").applied, "... also ist Original nicht der aktuelle Zustand")
      -- Rueckfrage, ESC bricht ab (das Fenster bleibt!)
      M.ClearSent()
      M.Click(F().btnRemoveAll)
      H.truthy(FX.UI.Skin.DialogOpen())
      H.truthy(dialogButton(LL().WIN_REMOVE_ALL))
      M.Escape()
      H.falsy(FX.UI.Skin.DialogOpen(), "ESC schliesst die Rueckfrage")
      H.truthy(Win().IsShown(), "... aber nicht das Fenster")
      H.eq(M.CountSent("RemoveAll"), 0)
      -- Abbrechen-Knopf
      M.Click(F().btnRemoveAll)
      M.Click(dialogButton(LL().WIN_CANCEL))
      H.falsy(FX.UI.Skin.DialogOpen())
      H.eq(M.CountSent("RemoveAll"), 0)
      -- Bestaetigen
      M.Click(F().btnRemoveAll)
      M.Click(dialogButton(LL().WIN_REMOVE_ALL))
      H.eq(M.CountSent("RemoveAll"), 1)
      settle(1.0)
      for _, slot in ipairs(SERVER_SLOTS) do
         H.eq(FX.State.Applied(slot), 0, "Slot " .. slot)
      end
      H.eq(status(), LL().WIN_REMOVED_ALL)
      H.eq(F().btnRemoveAll.uiOff, true)
      H.eq(F().btnRemoveAll.disabledTip, LL().WIN_REMOVE_ALL_NONE)
      -- die Original-Kachel steht immer vorn; ohne angewendetes Aussehen IST sie der aktuelle Zustand
      H.truthy(cellKind("original"), "Originalkachel bleibt")
      H.truthy(cellKind("original").applied, "nichts mehr angewendet: Original ist der aktuelle Zustand")
      H.falsy(cellKind("original").selected)
      H.eq(slotButton(HEAD).stateKey, nil)
      assertHealthy("Alles entfernen")
      M.Click(F().btnClose)
      assertIdle("Alles entfernen")
   end)

   -- -----------------------------------------------------------------------
   -- 5. Outfits: speichern, laden, umbenennen, loeschen, anwenden
   -- -----------------------------------------------------------------------

   -- Zeile (Frame) des Outfits mit dem Namen im Outfit-Reiter
   local function outfitRow(name)
      for _, row in ipairs(FX.UI.OutfitsTab.rows) do
         if row:IsShown() and row.outfitName == name then return row end
      end
      return nil
   end

   H.test("Outfits: Reiter, speichern (Dialog + Pruefung), Look aendern, laden, anwenden, umbenennen, loeschen", function()
      boot({})
      openNpc()
      local save = FX.UI.OutfitsTab.parts.save
      -- Reiter Outfits: Leerzustand
      M.Click(F().tabOutfits)
      settle(0.3)
      H.eq(Win().GetTab(), "outfits")
      H.eq(FX.DB.global.lastTab, "outfits")
      H.truthy(FX.UI.OutfitsTab.frame:IsShown())
      H.falsy(Grid().frame:IsShown())
      H.truthy(FX.UI.OutfitsTab.parts.empty:IsShown())
      H.truthy(M.HasText(F(), LL().OUTFITS_EMPTY_TITLE))
      H.eq(FX.UI.OutfitsTab.parts.counter:GetText(), "0 / 50")
      H.eq(save.uiOff, false, "es gibt einen Look (angewendete Aussehen)")

      -- Look ist: Kopf, Schulter, Brust, Haupthand (Standardstand des Servers), Ruecken verborgen
      local look = FX.Outfits.CurrentLook()
      local headA = look[HEAD]
      H.truthy(headA)
      H.eq(look[BACK], HIDDEN)

      -- speichern: Dialog, leerer Name -> gesperrt, doppelter Name -> Meldung
      M.Click(save)
      H.truthy(FX.UI.Skin.DialogOpen())
      local accept = dialogButton("Save")
      H.truthy(accept, "Speichern-Knopf des Dialogs")
      H.eq(accept.uiOff, false, "Vorschlag ist gueltig")
      promptType("")
      H.eq(accept.uiOff, true, "leerer Name gesperrt")
      promptType("Night Watch")
      H.eq(accept.uiOff, false)
      M.Click(accept)
      settle(0.3)
      H.falsy(FX.UI.Skin.DialogOpen())
      H.truthy(FX.Outfits.Exists("Night Watch"))
      H.eq(FX.Outfits.Count(), 1)
      H.eq(FX.UI.OutfitsTab.parts.counter:GetText(), "1 / 50")
      H.eq(status(), string.format(LL().OUTFITS_SAVED, "Night Watch"))
      local row = outfitRow("Night Watch")
      H.truthy(row, "Zeile erscheint")
      H.truthy(row.stripe:IsShown(), "gruener Streifen: entspricht dem aktuellen Look")
      -- zweiter Versuch mit gleichem Namen: Fehler im Dialog, Knopf gesperrt
      M.Click(save)
      promptType("night watch")
      H.eq(dialogButton("Save").uiOff, true, "Name existiert schon (Gross/Klein egal)")
      M.Escape()
      H.falsy(FX.UI.Skin.DialogOpen())
      H.truthy(Win().IsShown())

      -- Look aendern: anderes Kopfaussehen waehlen und anwenden
      M.Click(F().tabItems)
      settle(0.5)
      local other
      for _, c in ipairs(Grid().cells) do
         if c:IsShown() and c.kind == "item" and c.itemId ~= headA and not c.applied then other = c break end
      end
      H.truthy(other)
      local otherId = other.itemId
      M.Click(other)
      settle(0.6)
      M.Click(F().btnApply)
      settle(1.0)
      H.eq(FX.State.Applied(HEAD), otherId)
      -- Outfit-Reiter: der Streifen ist weg (Look weicht ab), Laden stellt Kopf wieder ein
      M.Click(F().tabOutfits)
      settle(0.3)
      row = outfitRow("Night Watch")
      H.falsy(row.stripe:IsShown())
      M.ClearSent()
      M.Click(visibleButton(row, LL().OUTFITS_LOAD))
      settle(0.5)
      H.eq(FX.State.Wanted(HEAD), headA, "Laden waehlt die Teile des Outfits")
      H.truthy(FX.State.HasPending(HEAD))
      H.eq(M.CountSent("Apply"), 0, "Laden wendet nichts an")
      H.eq(status(), string.format(LL().OUTFITS_LOADED, 5), "Zusammenfassung")
      H.eq(F().btnApply.uiOff, false)
      M.Click(F().btnApply)
      settle(1.2)
      H.eq(FX.State.Applied(HEAD), headA)
      H.truthy(outfitRow("Night Watch").stripe:IsShown())

      -- Umbenennen
      row = outfitRow("Night Watch")
      M.Click(visibleButton(row, LL().OUTFITS_RENAME))
      H.truthy(FX.UI.Skin.DialogOpen())
      promptType("Dawn Patrol")
      M.Click(dialogButton(LL().OUTFITS_RENAME))
      settle(0.3)
      H.falsy(FX.Outfits.Exists("Night Watch"))
      H.truthy(FX.Outfits.Exists("Dawn Patrol"))
      H.truthy(outfitRow("Dawn Patrol"))

      -- Ueberschreiben (Rueckfrage)
      row = outfitRow("Dawn Patrol")
      M.Click(visibleButton(row, LL().OUTFITS_OVERWRITE))
      H.truthy(FX.UI.Skin.DialogOpen())
      M.Click(dialogButton(LL().OUTFITS_OVERWRITE))
      settle(0.3)
      H.eq(status(), string.format(LL().OUTFITS_OVERWRITTEN, "Dawn Patrol"))

      -- Loeschen: Abbrechen behaelt, Bestaetigen loescht; danach wieder der Leerzustand
      row = outfitRow("Dawn Patrol")
      M.Click(visibleButton(row, LL().OUTFITS_DELETE))
      M.Click(dialogButton(LL().WIN_CANCEL) or dialogButton(Util and "Cancel" or "Cancel"))
      H.truthy(FX.Outfits.Exists("Dawn Patrol"))
      M.Click(visibleButton(outfitRow("Dawn Patrol"), LL().OUTFITS_DELETE))
      M.Click(dialogButton(LL().OUTFITS_DELETE))
      settle(0.3)
      H.falsy(FX.Outfits.Exists("Dawn Patrol"))
      H.eq(FX.Outfits.Count(), 0)
      H.truthy(FX.UI.OutfitsTab.parts.empty:IsShown())
      assertHealthy("Outfits")
      M.Click(F().btnClose)
      assertIdle("Outfits")
   end)

   -- -----------------------------------------------------------------------
   -- 6. Filter, Suche, Sortierung, Favoriten, Seiten
   -- -----------------------------------------------------------------------

   -- Namen (Kleinschreibung) aller Item-Kacheln der Seite
   local function pageNames()
      local out = {}
      for _, c in ipairs(Grid().cells) do
         if c:IsShown() and c.kind == "item" then
            local info = FX.Items.Info(c.itemId)
            out[#out + 1] = info and FX.Util.Lower(info.name) or "?"
         end
      end
      return out
   end

   H.test("Filter: Suche (entprellt), Sortierung per Menue, Qualitaet, Favoriten, leeres Ergebnis, Zuruecksetzen", function()
      boot({ screen = { w = 1920, h = 1080 } })
      FX.DB.Set("scale", 1.0)
      FX.DB.Set("width", 1100)
      FX.DB.Set("height", 700)
      openNpc()
      local fb = FX.UI.FilterBar
      local total = Grid().stats.total
      H.truthy(total >= 10)
      H.eq(Grid().mode, "GRID")
      H.eq(fb.resetButton.uiOff, true, "kein Filter aktiv")
      local shown0 = Grid().stats.shown

      -- Suche tippen: wirkt erst nach der Entprellung
      M.Type(fb.search, "helm")
      H.eq(FX.Filter.search or "", "", "noch nicht uebernommen (entprellt)")
      settle(0.5)
      H.eq(FX.Filter.search, "helm")
      H.truthy(FX.Filter.IsActive())
      H.truthy(Grid().stats.shown < shown0)
      H.truthy(Grid().stats.shown >= 1)
      for _, n in ipairs(pageNames()) do
         H.truthy(n:find("helm", 1, true), "Treffer enthaelt den Suchbegriff: " .. n)
      end
      H.eq(fb.resetButton.uiOff, false)
      H.eq(Grid().page, 1)
      -- Suche nach etwas, das es nicht gibt: Meldung + Knopf im Raster
      M.Type(fb.search, "zzzzqq")
      settle(0.5)
      H.eq(Grid().mode, "FILTERED")
      H.truthy(Grid().resetButton:IsShown(), "Raster bietet 'Filter zuruecksetzen' an")
      H.truthy(M.HasText(F(), LL().GRID_FILTERED))
      -- die synthetischen Kacheln bleiben (nicht von Filtern betroffen)
      H.truthy(cellKind("original"))
      H.truthy(cellKind("hidden"))
      M.Click(Grid().resetButton)
      settle(0.5)
      H.eq(FX.Filter.search or "", "")
      H.eq(fb.search:GetText(), "", "Suchfeld folgt dem Zuruecksetzen")
      H.eq(Grid().mode, "GRID")
      H.eq(Grid().stats.shown, shown0)
      H.eq(fb.resetButton.uiOff, true)

      -- Sortierung ueber das Menue: Name
      M.Click(fb.sortButton)
      H.truthy(FX.UI.Skin.Menu.IsOpen())
      local byName = menuItem(FX.Filter.SortLabel("NAME"))
      H.truthy(byName, "Menueeintrag 'Name'")
      M.Click(byName)
      settle(0.4)
      H.falsy(FX.UI.Skin.Menu.IsOpen(), "Auswahl schliesst das Menue")
      H.eq(FX.Filter.state.sort, "NAME")
      H.eq(FX.DB.char.filter.sort, "NAME", "Sortierung wird gespeichert")
      H.contains(fb.sortButton.label:GetText(), FX.Filter.SortLabel("NAME"))
      local entries = FX.Filter.Compute(HEAD)
      for i = 2, #entries do
         H.truthy(entries[i - 1].nameKey <= entries[i].nameKey, "nach Namen sortiert")
      end
      -- zurueck auf Qualitaet
      M.Click(fb.sortButton)
      M.Click(menuItem(FX.Filter.SortLabel("QUALITY")))
      settle(0.3)
      H.eq(FX.Filter.state.sort, "QUALITY")

      -- Qualitaets-Chip: Klick blendet die Qualitaet aus
      local q
      for qq = 0, 7 do
         if fb.chips[qq] and fb.chips[qq]:IsShown() then q = qq end
      end
      H.truthy(q, "mindestens ein Qualitaets-Chip")
      local before = Grid().stats.shown
      M.Click(fb.chips[q])
      settle(0.4)
      H.eq(FX.Filter.state.qualities[q], false)
      H.truthy(Grid().stats.shown < before)
      for _, e in ipairs(FX.Filter.Compute(HEAD)) do
         H.neq(e.quality, q)
      end
      M.Click(fb.chips[q])
      settle(0.4)
      H.eq(Grid().stats.shown, before)

      -- Favorit: Rechtsklick auf eine Kachel, dann nur Favoriten
      local c = itemCell(2)
      local favId = c.itemId
      M.Click(c, "RightButton")
      settle(0.3)
      H.truthy(FX.DB.char.favorites[favId])
      H.truthy(cellOf(favId).favorite)
      M.Click(fb.favChip)
      settle(0.4)
      H.truthy(FX.Filter.state.favoritesOnly)
      H.eq(Grid().stats.shown, 1)
      H.eq(itemCell(1).itemId, favId)
      M.Click(fb.favChip)
      settle(0.4)
      H.falsy(FX.Filter.state.favoritesOnly)
      H.eq(Grid().stats.shown, before)

      -- Filtermenue: Duplikate ausblenden ein/aus, Haken bleibt im offenen Menue
      M.Click(fb.filterButton)
      H.truthy(FX.UI.Skin.Menu.IsOpen())
      local dup = menuItem(LL().FILTER_HIDE_DUPLICATES)
      H.truthy(dup)
      local hadDup = FX.Filter.state.hideDuplicates
      M.Click(dup)
      settle(0.3)
      H.truthy(FX.UI.Skin.Menu.IsOpen(), "Haken lassen das Menue offen")
      H.neq(FX.Filter.state.hideDuplicates, hadDup)
      M.Click(menuItem(LL().FILTER_HIDE_DUPLICATES))
      settle(0.3)
      H.eq(FX.Filter.state.hideDuplicates, hadDup)
      M.Escape()
      H.falsy(FX.UI.Skin.Menu.IsOpen())
      H.truthy(Win().IsShown(), "ESC schliesst nur das Menue")

      -- Typ ausblenden (Kettenruestung), danach alles zuruecksetzen
      local types = FX.Filter.Types(HEAD)
      H.truthy(#types >= 2)
      local victim
      for _, t in ipairs(types) do
         if not t.own then victim = t end
      end
      H.truthy(victim)
      FX.Filter.SetType(victim.typeKey, false)
      settle(0.4)
      H.truthy(Grid().stats.shown < before)
      M.Click(fb.resetButton)
      settle(0.4)
      H.eq(Grid().stats.shown, before)
      H.deepEq(FX.DB.char.filter.typesOff, {})

      -- Seiten: kleines Fenster, damit es mehrere gibt
      FX.DB.Set("width", 740)
      FX.DB.Set("height", 520)
      settle(0.6)
      H.truthy(Grid().pages > 1, "mehrere Seiten im kleinen Fenster")
      local p1 = pageNames()
      M.Click(Grid().pageButtons.next)
      settle(0.2)
      H.eq(Grid().page, 2)
      H.neq(table.concat(pageNames(), "|"), table.concat(p1, "|"))
      M.Wheel(Grid().raster, 1)
      settle(0.2)
      H.eq(Grid().page, 1)
      M.Click(Grid().pageButtons.last)
      settle(0.2)
      H.eq(Grid().page, Grid().pages)
      -- ein Filterwechsel beginnt wieder auf Seite 1
      FX.Filter.SetSort("NAME")
      settle(0.3)
      H.eq(Grid().page, 1)
      assertHealthy("Filter")
      M.Escape()
      assertIdle("Filter")
   end)

   -- -----------------------------------------------------------------------
   -- 7. Groesse und Scale
   -- -----------------------------------------------------------------------

   H.test("Groesse und Scale: Griff ziehen, Optionen (Scale/Vorschaugroesse), Aufloesungswechsel, Zuruecksetzen", function()
      boot({ screen = { w = 1366, h = 768 } })
      FX.DB.Set("scale", 1.0)
      openNpc()
      local f = F()
      H.eq(f:GetWidth(), 880)
      H.eq(f:GetHeight(), 600)
      H.near(f:GetScale(), 1.0, 1e-9)
      local perPage0, cols0 = Grid().perPage, Grid().cols

      -- Ziehen am Griff: Fenster waechst, Raster bekommt mehr Zellen, Groesse wird gespeichert
      M.Drag(f.grip, 120, -60)   -- (Bildschirm-y zeigt nach oben: nach unten ziehen = negativ)
      settle(0.5)
      H.eq(f:GetWidth(), 1000)
      H.eq(f:GetHeight(), 660)
      H.eq(FX.DB.global.width, 1000)
      H.eq(FX.DB.global.height, 660)
      H.truthy(Grid().perPage >= perPage0)
      H.truthy(Grid().cols >= cols0)
      H.eq(F().right:GetWidth(), 1000 - 8 - 318 - 8 - 8)
      -- noch kleiner als das Minimum geht nicht
      M.Drag(f.grip, -600, 400)
      settle(0.5)
      H.eq(f:GetWidth(), 740)
      H.eq(f:GetHeight(), 520)

      -- Scale ueber die Optionen: Regler/Eintrag ruft DB.Set("scale"), das Fenster folgt
      M.Slash("/transmog options")
      settle(0.3)
      H.truthy(FX.UI.Options.IsShown())
      H.truthy(Win().IsShown(), "Optionen oeffnen das Fenster nicht zu")
      FX.DB.Set("scale", 1.25)
      settle(0.5)
      H.near(f:GetScale(), 1.25, 1e-9)
      H.truthy(f:GetWidth() * 1.25 <= 1366 + 1e-6 and f:GetHeight() * 1.25 <= 768 + 1e-6)
      -- Vorschaugroesse: Knopf "Sehr gross" (1.5) macht die Zellen groesser, weniger Zellen je Seite
      local sizes = FX.UI.Options.controls.sizes
      H.eq(#sizes, 4)
      local beforeCell, beforePer = Grid().cellW, Grid().perPage
      M.Click(sizes[4])
      settle(0.5)
      H.eq(FX.DB.global.previewSize, 1.5)
      H.near(Grid().cellW, 92 * 1.5, 1e-9)
      H.truthy(Grid().perPage < beforePer or beforePer == 1)
      M.Click(sizes[1])
      settle(0.5)
      H.near(Grid().cellW, 92 * 0.8, 1e-9)
      M.Click(sizes[2])
      settle(0.5)
      H.near(Grid().cellW, 92, 1e-9)
      -- Scale auf Automatisch (0): 768 * 0.82 / 600 = 1.05 -> nicht ueber den Bildschirm
      FX.DB.Set("scale", 0)
      settle(0.5)
      local auto = f:GetScale()
      H.truthy(auto >= 0.7 and auto <= 1.5, "automatischer Scale " .. tostring(auto))
      H.truthy(f:GetWidth() * auto <= 1366 + 1e-6 and f:GetHeight() * auto <= 768 + 1e-6)

      -- Aufloesungswechsel bei offenem Fenster: Fenster passt sich an (Abfrage 1x je Sekunde)
      FX.DB.Set("scale", 1.0)
      FX.DB.Set("width", 1200)
      FX.DB.Set("height", 700)
      settle(0.5)
      H.eq(f:GetWidth(), 1200)
      M.SetScreen(1024, 768)
      -- UIParent der Attrappe folgt der Bildschirmgroesse nicht von selbst: wie das Spiel
      UIParent:SetWidth(1024)
      UIParent:SetHeight(768)
      settle(1.5)
      H.truthy(f:GetWidth() * f:GetScale() <= 1024 + 1e-6, "Fenster passt auf den kleineren Bildschirm")
      H.truthy(f:GetLeft() >= -1e-6 and f:GetRight() <= 1024 + 1e-6)
      H.eq(FX.DB.global.width, 1200, "der Wunsch bleibt gespeichert (nur geklemmt angezeigt)")

      -- Zuruecksetzen per Slash
      M.Slash("/transmog reset")
      settle(0.5)
      H.eq(FX.DB.global.width, 880)
      H.eq(FX.DB.global.height, 600)
      H.eq(FX.DB.global.point, nil)
      H.eq(f:GetWidth(), 880)
      assertHealthy("Groesse")
      FX.UI.Options.Close()
      M.Escape()
      assertIdle("Groesse")
   end)

   -- -----------------------------------------------------------------------
   -- 8. Sprachwechsel
   -- -----------------------------------------------------------------------

   -- Kleine deutsche Uebersetzung (die vollstaendigen Dateien kommen spaeter; so wird geprueft,
   -- dass jede Komponente LOCALE_CHANGED auswertet)
   local GERMAN = {
      WIN_TAB_ITEMS = "Gegenstaende", WIN_TAB_OUTFITS = "Outfits", WIN_APPLY = "Anwenden",
      WIN_APPLY_RESET = "Zuruecksetzen anwenden", WIN_DISCARD = "Verwerfen", WIN_REMOVE_ALL = "Alles entfernen",
      WIN_COST = "Kosten:", GRID_ORIGINAL = "Original", GRID_HIDDEN = "Verborgen", FILTER_BUTTON = "Filter",
      FILTER_SEARCH_PLACEHOLDER = "Name, Typ oder #id suchen", OUTFITS_SAVE = "Aktuellen Look speichern",
      MSG_NO_VENDOR = "Vorschau-Modus - besuche einen Transmogrifizierer, um Aenderungen anzuwenden.",
      OPT_TITLE = "Einstellungen", SORT_QUALITY = "Qualitaet", FILTER_SORT = "Sortierung: %s",
      GRID_PAGE = "Seite %d / %d", WIN_STATUS_PENDING = "Ausstehende Aenderungen: %d",
      SLOTBAR_AVAILABLE = "Verfuegbar: %d",
   }

   H.test("Sprachwechsel: /transmog lang und Optionsmenue schalten alle Komponenten um und zurueck", function()
      boot({})
      FX.Locale.Add("deDE", GERMAN)
      openPreview()
      M.Click(itemCell(1))
      settle(0.6)
      local fb = FX.UI.FilterBar
      -- Englisch
      H.eq(F().tabItems.label:GetText(), "Items")
      H.eq(F().btnApply.label:GetText(), "Apply")
      H.eq(F().notice.text:GetText(), LL().MSG_NO_VENDOR)
      H.eq(fb.filterButton.label:GetText(), "Filter")
      H.eq(fb.search.placeholderText:GetText(), "Search name, type or #id")
      H.eq(cellKind("original").ov.name:GetText(), "Original")
      H.eq(status(), "Pending changes: 1")

      -- /transmog lang deDE
      M.Slash("/transmog lang deDE")
      settle(0.5)
      H.eq(FX.Locale.Current(), "deDE")
      H.eq(FX.DB.global.locale, "deDE")
      H.eq(F().tabItems.label:GetText(), "Gegenstaende")
      H.eq(F().btnApply.label:GetText(), "Anwenden")
      H.eq(F().btnDiscard.label:GetText(), "Verwerfen")
      H.eq(F().btnRemoveAll.label:GetText(), "Alles entfernen")
      H.eq(F().notice.text:GetText(), GERMAN.MSG_NO_VENDOR)
      H.eq(fb.search.placeholderText:GetText(), GERMAN.FILTER_SEARCH_PLACEHOLDER)
      H.eq(cellKind("hidden").ov.name:GetText(), "Verborgen")
      H.eq(status(), "Ausstehende Aenderungen: 1")
      H.eq(fb.sortButton.label:GetText(), "Sortierung: Qualitaet")
      H.eq(Grid().pageText:GetText(), "Seite 1 / 1")
      -- Outfits-Reiter in Deutsch
      M.Click(F().tabOutfits)
      settle(0.3)
      H.eq(FX.UI.OutfitsTab.parts.save.label:GetText(), "Aktuellen Look speichern")
      -- Auswahl bleibt, der Sprachwechsel verliert nichts
      H.eq(FX.State.PendingCount(), 1)
      M.Click(F().tabItems)
      settle(0.3)

      -- Optionen: Sprachmenue -> English
      M.Slash("/transmog options")
      settle(0.3)
      local ctl = FX.UI.Options.controls
      H.eq(ctl.head.title and ctl.head.title:GetText() or nil, GERMAN.OPT_TITLE)
      M.Click(ctl.language)
      H.truthy(FX.UI.Skin.Menu.IsOpen())
      local english = menuItem("English")
      H.truthy(english, "Sprachliste nennt Sprachen in ihrer eigenen Sprache")
      M.Click(english)
      settle(0.4)
      H.eq(FX.Locale.Current(), "enUS")
      H.eq(FX.DB.global.locale, "enUS")
      H.eq(F().tabItems.label:GetText(), "Items")
      H.eq(F().btnApply.label:GetText(), "Apply")
      H.eq(status(), "Pending changes: 1")
      -- /transmog lang auto: folgt dem Client (hier enUS)
      M.Slash("/transmog lang auto")
      settle(0.2)
      H.eq(FX.DB.global.locale, "auto")
      H.eq(FX.Locale.Current(), "enUS")
      -- unbekannte Sprache aendert nichts
      M.Slash("/transmog lang xx")
      H.eq(FX.DB.global.locale, "auto")
      assertHealthy("Sprachwechsel")
      FX.UI.Options.Close()
      M.Escape()
      assertIdle("Sprachwechsel")
   end)

   -- -----------------------------------------------------------------------
   -- 9. Ausruestung wechselt bei offenem Fenster
   -- -----------------------------------------------------------------------

   H.test("Ausruestung wechselt: Liste laedt neu, Auswahl des Slots faellt weg, leerer Slot, Wiederanlegen", function()
      boot({})
      openNpc()
      -- Kopf-, Schulter- und Brustauswahl vormerken
      H.truthy(FX.State.Select(HEAD, ids(HEAD)[1]))
      H.truthy(FX.State.Select(SHOULDER, ids(SHOULDER)[2]))
      H.truthy(FX.State.Select(CHEST, HIDDEN))
      settle(1.0)
      H.eq(FX.State.PendingCount(), 3)
      H.eq(slotButton(HEAD).stateKey, "pending")
      local oldList = ids(HEAD)

      -- ein Stoffhelm ersetzt den Plattenhelm: die Liste des Kopfes wird neu geladen
      M.ClearSent()
      Fixtures.Equip(FX, HEAD, "e_head_cloth")
      settle(0.2)
      H.falsy(FX.State.HasPending(HEAD), "die Auswahl des Slots faellt sofort weg")
      H.eq(FX.State.PendingCount(), 2)
      settle(1.5)
      H.truthy(M.CountSent("GetAvailableTransmogs") >= 1, "Listen werden neu angefordert")
      H.truthy(FX.State.List(HEAD).ready)
      H.eq(Grid().mode, "GRID")
      H.neq(table.concat(ids(HEAD), ","), table.concat(oldList, ","), "andere Liste (anderer angelegter Gegenstand)")
      H.eq(FX.State.Equipped(HEAD).id, Fixtures.Item(FX, "e_head_cloth"))
      H.eq(FX.State.PendingCount(), 2)
      H.eq(F().btnApply.uiOff, false)

      -- Kopf leeren: Raster zeigt den Leerzustand, Slotknopf ist abgedunkelt, Klick meldet den Grund
      Fixtures.Unequip(FX, HEAD)
      settle(1.5)
      H.eq(FX.State.SlotState(HEAD), "EMPTY")
      H.eq(Win().currentSlot, HEAD)
      H.eq(Grid().mode, "EMPTY")
      H.truthy(M.HasText(F(), LL().GRID_EMPTY_SLOT))
      M.Click(slotButton(HEAD))
      H.eq(Win().currentSlot, HEAD)
      H.eq(FX.State.PendingCount(), 2)
      -- wieder anlegen
      Fixtures.Equip(FX, HEAD, "e_head_plate")
      settle(2.0)
      H.eq(FX.State.SlotState(HEAD), "READY")
      H.eq(Grid().mode, "GRID")
      -- die anderen beiden Auswahlen sind noch da und lassen sich anwenden
      H.eq(FX.State.PendingCount(), 2)
      M.Click(F().btnApply)
      settle(1.5)
      H.eq(FX.State.PendingCount(), 0)
      H.eq(FX.State.Applied(CHEST), HIDDEN)
      assertHealthy("Ausruestung")
      M.Click(F().btnClose)
      assertIdle("Ausruestung")
   end)

   -- -----------------------------------------------------------------------
   -- 10. Server antwortet nicht
   -- -----------------------------------------------------------------------

   H.test("Server schweigt: nach 8 s Hinweis und Meldung im Raster, Anwenden gesperrt; Server kehrt zurueck", function()
      boot({ hello = false, mute = true })
      openPreview(0.5)
      H.eq(FX.Net.state, "UNKNOWN")
      H.eq(Grid().mode, "LOADING")
      settle(9)
      H.eq(FX.Net.state, "ABSENT")
      H.truthy(F().notice:IsShown())
      H.eq(F().notice.text:GetText(), LL().MSG_SERVER_ABSENT, "rote Hinweisleiste statt Vorschau-Hinweis")
      H.eq(Grid().mode, "ABSENT")
      H.truthy(M.HasText(F(), LL().GRID_ABSENT))
      H.eq(F().btnApply.uiOff, true)
      -- der Server kommt zurueck: beim naechsten Oeffnen laeuft alles wieder
      srv.mute = false
      Win().Close()
      settle(0.2)
      Win().Open({ fromNpc = true })
      settle(1.5)
      H.eq(FX.Net.state, "OK")
      H.falsy(F().notice:IsShown())
      H.eq(Grid().mode, "GRID")
      assertHealthy("Server schweigt")
      M.Escape()
      assertIdle("Server schweigt")
   end)

   H.test("Server verstummt mitten im Betrieb: Anwenden laeuft in die Frist, Fehlermeldung, kein ewiges Warten", function()
      boot({})
      openNpc()
      local id = ids(HEAD)[1]
      Fixtures.ServerStop(FX)
      M.Click(slotButton(HEAD))
      H.truthy(FX.State.Select(HEAD, id))
      settle(0.5)
      -- die Kostenantwort bleibt aus: Anwenden zunaechst gesperrt (Kosten werden berechnet)
      H.eq(F().btnApply.uiOff, true)
      H.eq(F().btnApply.disabledTip, LL().APPLY_REASON_COST_PENDING)
      -- nach der Frist ist der Knopf wieder frei (Kosten unbekannt), Anwenden laeuft ins Leere
      local t = M.AdvanceUntil(function() return F().btnApply.uiOff == false end, 20, 0.25)
      H.truthy(t, "der Knopf wird nach der Kostenfrist wieder frei")
      M.ClearSent()
      M.Click(F().btnApply)
      settle(0.2)
      H.truthy(FX.State.Busy())
      H.eq(F().btnApply.uiOff, true)
      H.eq(F().btnApply.disabledTip, LL().APPLY_REASON_BUSY)
      local done = M.AdvanceUntil(function() return not FX.State.Busy() end, 15, 0.25)
      H.truthy(done, "Zeitueberschreitung beendet den Stapel")
      settle(0.3)
      H.eq(status(), string.format(LL().MSG_APPLY_SLOT_FAILED, FX.Slots.Label(HEAD)))
      H.truthy(FX.State.HasPending(HEAD), "die Auswahl bleibt")
      H.eq(F().btnDiscard.uiOff, false)
      M.Click(F().btnDiscard)
      settle(0.3)
      H.eq(FX.State.PendingCount(), 0)
      assertHealthy("Server verstummt")
      M.Click(F().btnClose)
      assertIdle("Server verstummt")
   end)

   -- -----------------------------------------------------------------------
   -- 11. Schliessen per X und ESC, Wiederoeffnen mit gemerktem Zustand
   -- -----------------------------------------------------------------------

   H.test("Schliessen per X und per ESC (mit Gossip), Wiederoeffnen behaelt Filter, Position, Groesse, Slot, Auswahl", function()
      boot({ screen = { w = 1920, h = 1080 } })
      FX.DB.Set("scale", 1.0)
      openNpc()
      local f = F()
      local fb = FX.UI.FilterBar

      -- Fenster verschieben (Kopf ziehen) und vergroessern
      local left0, top0 = f:GetLeft(), f:GetTop()
      M.Drag(f.head, -150, 80)
      settle(0.2)
      H.near(f:GetLeft(), left0 - 150, 1)
      H.near(f:GetTop(), top0 + 80, 1)
      H.truthy(FX.DB.global.point, "Position gespeichert")
      M.Drag(f.grip, 100, -40)
      settle(0.3)
      H.eq(f:GetWidth(), 980)
      H.eq(f:GetHeight(), 640)

      -- Slot, Filter, Suche, Sortierung, Auswahl
      M.Click(slotButton(SHOULDER))
      settle(0.5)
      local q
      for qq = 0, 7 do
         if fb.chips[qq] and fb.chips[qq]:IsShown() then q = qq end
      end
      H.truthy(q)
      M.Click(fb.chips[q])
      FX.Filter.SetSort("NAME")
      M.Type(fb.search, "pauld")
      settle(0.6)
      H.eq(FX.Filter.search, "pauld")
      local sel = itemCell(1).itemId
      M.Click(itemCell(1))
      settle(0.5)
      H.eq(FX.State.Wanted(SHOULDER), sel)
      local left1, top1 = f:GetLeft(), f:GetTop()

      -- X schliesst; CloseGossip ging ans Spiel, kein Rest bleibt
      H.eq(M.world.gossipOpen, false, "das Gossip-Fenster war schon durch das Addon ersetzt")
      M.Click(f.btnClose)
      H.falsy(Win().IsShown())
      assertIdle("nach X")

      -- am NPC wieder auf: alles wie vorher
      openNpc()
      f = F()
      H.truthy(Win().IsShown())
      H.near(f:GetLeft(), left1, 1)
      H.near(f:GetTop(), top1, 1)
      H.eq(f:GetWidth(), 980)
      H.eq(f:GetHeight(), 640)
      H.eq(Win().currentSlot, SHOULDER, "letzter Slot")
      H.eq(FX.State.Wanted(SHOULDER), sel, "Auswahl ueberlebt")
      H.eq(FX.Filter.state.qualities[q], false)
      H.eq(FX.Filter.state.sort, "NAME")
      H.eq(FX.Filter.search, "pauld")
      H.eq(fb.search:GetText(), "pauld")
      H.truthy(cellOf(sel) and cellOf(sel).selected)

      -- ESC schliesst, mit NPC-Gossip: CloseGossip, kein Fehler durch das synchrone GOSSIP_CLOSED
      M.Escape()
      H.falsy(Win().IsShown())
      H.eq(M.world.gossipOpen, false)
      assertIdle("nach ESC")

      -- nochmal: NPC -> /transmog (Vorschau-Modus) -> X: kein CloseGossip, Fenster zu
      openNpc()
      H.truthy(Win().IsShown())
      M.Escape()
      assertIdle("zweites ESC")
   end)

   H.test("Neuanmeldung mit den gespeicherten Variablen: Einstellungen, Filter, Favoriten, Outfits, Position", function()
      boot({ screen = { w = 1920, h = 1080 } })
      FX.DB.Set("scale", 1.0)
      FX.DB.Set("width", 1000)
      FX.DB.Set("height", 650)
      FX.DB.Set("previewSize", 1.25)
      openNpc()
      M.Drag(F().head, 60, -30)
      settle(0.2)
      local left, top = F():GetLeft(), F():GetTop()
      M.Click(slotButton(CHEST))
      settle(0.5)
      FX.Filter.SetHideDuplicates(false)
      FX.Filter.SetSort("ILEVEL")
      settle(0.4)
      local fav = itemCell(1).itemId
      M.Click(itemCell(1), "RightButton")
      settle(0.2)
      H.truthy(FX.DB.char.favorites[fav])
      H.truthy(FX.Outfits.Save("Keeper", FX.Outfits.CurrentLook()))
      Win().SetTab("outfits")
      M.Escape()
      local saved = M.SavedVariables()

      -- neue Sitzung
      boot({ screen = { w = 1920, h = 1080 }, globals = saved })
      H.eq(FX.DB.global.width, 1000)
      H.eq(FX.DB.global.previewSize, 1.25)
      H.eq(FX.DB.global.lastTab, "outfits")
      H.eq(FX.DB.char.lastSlot, CHEST)
      H.eq(FX.Filter.state.sort, "ILEVEL")
      H.eq(FX.Filter.state.hideDuplicates, false)
      H.truthy(FX.DB.char.favorites[fav])
      H.truthy(FX.Outfits.Exists("Keeper"))
      M.Slash("/transmog")
      settle(1.0)
      H.truthy(Win().IsShown())
      H.eq(Win().GetTab(), "outfits", "letzter Reiter")
      H.near(F():GetLeft(), left, 1)
      H.near(F():GetTop(), top, 1)
      H.eq(F():GetWidth(), 1000)
      H.truthy(FX.UI.OutfitsTab.parts.counter:GetText() == "1 / 50")
      M.Click(F().tabItems)
      settle(0.5)
      H.eq(Win().currentSlot, CHEST, "letzter Slot")
      H.near(Grid().cellW, 92 * 1.25, 1e-9)
      assertHealthy("Neuanmeldung")
      M.Escape()
      assertIdle("Neuanmeldung")
   end)

   -- -----------------------------------------------------------------------
   -- 12. Neues Aussehen: Toast, NEU-Marke, Liste waechst, Tooltips
   -- -----------------------------------------------------------------------

   H.test("Neues Aussehen bei offenem Fenster: Toast, Liste waechst, NEU-Marke, Filter 'Neu', Tooltips", function()
      boot({})
      openNpc()
      settle(11)                        -- der Login-Sweep (10 s) ist vorbei
      local rec
      for _, r in ipairs(Fixtures.Catalog(FX).list) do
         if r.uncollected and r.inv == "INVTYPE_HEAD" and r.sub == "plate" then rec = r break end
      end
      H.truthy(rec, "ein nicht gesammelter Plattenhelm im Katalog")
      H.falsy(FX.State.List(HEAD).set[rec.id])
      local n0 = #ids(HEAD)
      H.eq(FX.Net.CollectionState(rec.id), nil)

      -- Tooltip eines nicht gesammelten Gegenstands: Zeile "nicht gesammelt" wird nachgetragen
      GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink("item:" .. rec.id)
      settle(0.5)
      H.truthy(M.HasText(GameTooltip, LL().TIP_NOT_COLLECTED), "Tooltip nennt: Aussehen nicht gesammelt")
      GameTooltip:Hide()

      Fixtures.Collect(FX, rec.id)
      settle(1.0)
      H.truthy(FX.State.new[rec.id], "als neu gemerkt (nicht aus dem Login-Sweep)")
      -- Toast sichtbar
      H.truthy(FX.Toasts.Stats().visible >= 1, "Meldekarte")
      -- die Listen werden nach 3 s Ruhe neu angefordert und enthalten dann das Aussehen
      H.eq(#ids(HEAD), n0, "noch nicht (entprellt)")
      settle(3.5)
      H.eq(#ids(HEAD), n0 + 1)
      H.truthy(FX.State.List(HEAD).set[rec.id])
      local cell = cellOf(rec.id)
      H.truthy(cell, "Kachel im Raster")
      H.truthy(cell.isNew, "NEU-Marke")
      H.truthy(cell.ov.newText:IsShown())
      H.eq(cell.ov.newText:GetText(), LL().GRID_NEW)
      -- Filter 'Neu': nur dieses
      M.Click(FX.UI.FilterBar.newChip)
      settle(0.5)
      H.eq(Grid().stats.shown, 1)
      H.eq(itemCell(1).itemId, rec.id)
      M.Click(FX.UI.FilterBar.newChip)
      settle(0.4)
      H.eq(Grid().stats.shown, n0 + 1)
      -- nach dem Toast: nichts bleibt
      settle(8)
      H.eq(FX.Toasts.Stats().visible, 0)
      assertHealthy("Neues Aussehen")
      M.Escape()
      assertIdle("Neues Aussehen")
   end)
end
