-- Core\State.lua
-- ---------------------------------------------------------------------------
-- Das Modell des Addons. State ist die EINZIGE veraenderliche Wahrheit; die
-- Oberflaeche liest ueber die Getter und wird ueber Events benachrichtigt.
--
-- Je Server-Slot (die 14 transmogbaren) fuehrt State einen Datensatz:
--
--   itemId    angelegter Gegenstand (0 = leer)
--   applied   was der Server meldet: 0 | itemId | HIDDEN (roh)
--   sel       Auswahl des Spielers: nil = keine, sonst 0 | itemId | HIDDEN
--   list      Liste der verfuegbaren Aussehen (Rohdaten, nur IDs)
--
-- Begriffe
--
--   Inaktiv    Aussehen X ist gespeichert, steht aber nicht (mehr) in der
--              fertigen Liste des Slots: der Server zeigt dann den echten
--              Gegenstand. Nur mit fertiger Liste (list.ready) bestimmbar,
--              HIDDEN ist nie inaktiv.
--   Baseline   Applied, aber 0 wenn inaktiv.
--   Wanted     Auswahl, sonst Baseline. Pending = Auswahl ~= Baseline.
--
-- Listen
--
--   OnListStart ersetzt die Liste des Slots durch eine leere (ready=false),
--   OnListEnd macht sie fertig und feuert LIST_READY. Solange eine Liste nicht
--   fertig ist, gilt Baseline == Applied (nie "inaktiv" ohne fertige Liste).
--   Aendert sich der angelegte Gegenstand, wird die Liste sofort als veraltet
--   (ready=false; die IDs bleiben bis zum neuen Strom stehen) markiert und nach
--   0,5 s neu angefordert. State.Refresh fordert die Listen nur an, wenn sie
--   veraltet/unbekannt/aelter als 60 s sind (oder force) -- das Fenster darf
--   es also bei jedem Oeffnen rufen, ohne 14 Listenstroeme zu erzeugen.
--
-- Auswahl (State.Select)
--
--   Ein Slot muss READY sein (angelegt und nicht NEVER). Bei FERTIGER Liste
--   muss die ID darin stehen; ist die Liste noch nicht fertig, wird optimistisch
--   akzeptiert und beim Listenende bereinigt (nicht enthaltene Auswahlen fallen
--   weg, WANTED_CHANGED). HIDDEN nur in verbergbaren Slots, 0 immer.
--
-- Meldungen
--
--   State schreibt Ergebnisse (Anwenden fertig/Fehlschlag, abgelehnt wegen
--   Server/Transmogrifizierer) in den Chat, solange State.chatMessages wahr ist.
--   Eine Oberflaeche mit eigener Statuszeile setzt es auf false.
--
-- Anwenden (State.Apply)
--
--   Die Operationen entstehen aus PendingSlots() in aufsteigender Slotfolge.
--   Es ist immer genau EINE Operation unterwegs; die naechste geht erst nach
--   der Antwort oder nach 5 s Zeitueberschreitung hinaus. Antworten werden
--   FIFO zugeordnet (Fehlantworten tragen keinen Slot); Erfolge werden
--   zusaetzlich ueber den Slot der Antwort zugeordnet. Eine abgelaufene
--   Operation bleibt als "Geist" in der Warteschlange, damit ihre verspaetete
--   Antwort nicht der naechsten Operation zugeschlagen wird.
--
-- Kosten
--
--   Anfragen und Antworten werden gezaehlt (sent/recv). Nur die Antwort der
--   LETZTEN Anfrage (recv == sent) wird uebernommen. Geht eine Antwort
--   verloren, wird einmal wiederholt und dann aufgegeben (Kosten unbekannt,
--   aber nicht "ausstehend" -- der Knopf bleibt nie ewig gesperrt).
-- ---------------------------------------------------------------------------

local T = Transmog
T.State = T.State or {}
local State = T.State

local sfind, ssub, smatch, sformat = string.find, string.sub, string.match, string.format
local floor = math.floor
local tremove, tconcat, tsort = table.remove, table.concat, table.sort
local tonumber, tostring, type, pairs, ipairs, pcall, select =
   tonumber, tostring, type, pairs, ipairs, pcall, select

local HIDDEN = T.HIDDEN_ID or 999999
local MAX_UINT = 4294967295

local APPLY_TIMEOUT   = 5      -- s je Operation
local COST_TIMEOUT    = 5      -- s je Kostenanfrage
local COST_DEBOUNCE   = 0.25   -- s Ruhe vor der Kostenanfrage
local EQUIP_DEBOUNCE  = 0.5    -- s Ruhe nach Ausruestungswechsel vor Listenanfrage
local DIRTY_DEBOUNCE  = 3      -- s Ruhe nach CollectionUpdated vor Listenanfrage
local LISTS_MAX_AGE   = 60     -- s, danach fordert Refresh die Listen neu an
local LISTS_RETRY_AGE = 10     -- s, danach darf Refresh unfertige Listen erneut anfordern
local GHOST_MAX_AGE   = 30     -- s, danach gilt eine abgelaufene Operation als verloren

-- Rueckfallwerte, falls T.Slots / T.Items beim Laden fehlen (Test).
local FALLBACK_SLOTS = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 14, 15, 16, 17, 18 }
local FALLBACK_HIDEABLE = {
   [0] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
   [7] = true, [8] = true, [9] = true, [14] = true, [18] = true,
}
local FALLBACK_NEVER = {
   INVTYPE_BAG = 1, INVTYPE_RELIC = 1, INVTYPE_FINGER = 1, INVTYPE_TRINKET = 1,
   INVTYPE_AMMO = 1, INVTYPE_QUIVER = 1, INVTYPE_NECK = 1,
}

-- Oeffentliche Felder (beim Laden zurueckgesetzt)
State.atVendor      = false     -- Transmogrifizierer in Reichweite / Fenster per NPC
State.openedByNpc   = false     -- Fenster wurde durch NPC-Gossip geoeffnet
State.new           = {}        -- [itemId] = true: in dieser Sitzung neu gesammelt
State.serverOpenAt  = nil       -- GetTime() der letzten "Open"-Nachricht
State.chatMessages  = true      -- Ergebnismeldungen im Chat (false = die UI uebernimmt)

-- ---------------------------------------------------------------------------
-- Lokaler Zustand
-- ---------------------------------------------------------------------------

local recs = {}                 -- [server] = Datensatz
local SERVER_SLOTS = {}         -- aufsteigende Server-Slots der 14
local inited = false
local statusKnown = false
local listsDirty = false
local lastListRequestAt = nil
local equipTimer, dirtyTimer = nil, nil

local apply = { busy = false, ops = {}, index = 0, nOk = 0, nFail = 0 }
local fifo = {}                 -- gesendete, unbeantwortete Operationen (aelteste zuerst)

local cost = {
   sent = 0, recv = 0,          -- Zaehler gesendeter / empfangener Anfragen
   copper = 0, canPurchase = true,
   validSig = nil,              -- Signatur, fuer die copper/canPurchase gelten
   lastSig = nil,               -- Signatur der letzten gesendeten Anfrage
   scheduled = false,           -- Entprellung laeuft
   debounce = nil, timer = nil, retries = 0,
   notifyKey = nil,             -- zuletzt gemeldeter Stand (COST_CHANGED nur bei Aenderung)
}

local EMPTY_LIST = {
   ids = {}, set = {}, bucket = 0, amount = 0, received = 0, ready = false, version = 0,
}

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------

local function Fire(name, ...)
   local E = T.Events
   if E and E.Fire then E.Fire(name, ...) end
end

local function Dbg(fmt, ...)
   local U = T.Util
   if U and U.Debug then U.Debug(fmt, ...) end
end

local function Now()
   if GetTime then return GetTime() end
   return 0
end

local function After(delay, fn, ...)
   local U = T.Util
   if U and U.After then return U.After(delay, fn, ...) end
   return nil
end

local function Cancel(handle)
   local U = T.Util
   if handle and U and U.Cancel then U.Cancel(handle) end
end

-- Text zu einem Meldungsschluessel. Bewusst ausgeschrieben, damit die
-- Locale-Pruefung die Schluessel statisch findet; unbekannt -> der Schluessel.
local function MessageText(key)
   local L = T.L
   if not L then return key end
   if key == "MSG_APPLY_OK" then return L.MSG_APPLY_OK end
   if key == "MSG_APPLY_DONE" then return L.MSG_APPLY_DONE end
   if key == "MSG_APPLY_SLOT_FAILED" then return L.MSG_APPLY_SLOT_FAILED end
   if key == "MSG_SERVER_ABSENT" then return L.MSG_SERVER_ABSENT end
   if key == "MSG_NO_VENDOR" then return L.MSG_NO_VENDOR end
   if key == "APPLY_REASON_COST_PENDING" then return L.APPLY_REASON_COST_PENDING end
   if key == "APPLY_REASON_MONEY" then return L.APPLY_REASON_MONEY end
   return key
end

-- Chatmeldung aus den Locale-Texten (nur wenn State.chatMessages).
local function Say(isError, key, ...)
   if not State.chatMessages then return end
   local text = MessageText(key)
   if select("#", ...) > 0 then
      local ok, res = pcall(sformat, text, ...)
      if ok then text = res end
   end
   local U = T.Util
   if not U then return end
   if isError and U.Error then
      U.Error("%s", text)
   elseif U.Print then
      U.Print("%s", text)
   end
end

-- Nicht negative Ganzzahl aus Zahl oder Ziffernstring, sonst nil.
local function ToUInt(v)
   local n
   if type(v) == "number" then
      n = v
   elseif type(v) == "string" then
      local digits = smatch(v, "^%s*(%d+)%s*$")
      if not digits then return nil end
      n = tonumber(digits)
   else
      return nil
   end
   if not n or n ~= n or n < 0 or n > MAX_UINT or n ~= floor(n) then return nil end
   return n
end

local function IsHideable(slot)
   local S = T.Slots
   if S and S.IsHideable then return S.IsHideable(slot) and true or false end
   return FALLBACK_HIDEABLE[slot] == true
end

local function IsNeverLoc(equipLoc)
   local It = T.Items
   if It and It.IsNever then return It.IsNever(equipLoc) and true or false end
   return FALLBACK_NEVER[equipLoc] ~= nil
end

local function SlotLabel(slot)
   local S = T.Slots
   if S and S.Label then return S.Label(slot) end
   return tostring(slot)
end

local function EquippedLink(slot)
   local S = T.Slots
   if S and S.EquippedLink then return S.EquippedLink(slot) end
   if GetInventoryItemLink then return GetInventoryItemLink("player", slot + 1) end
   return nil
end

local function ItemIdFromLink(link)
   if type(link) ~= "string" then return nil end
   local U = T.Util
   if U and U.ItemIdFromLink then
      local ok, id = pcall(U.ItemIdFromLink, link)
      if ok and tonumber(id) then return tonumber(id) end
   end
   local s = smatch(link, "item:(%d+)")
   return s and tonumber(s) or nil
end

local function NewList()
   return { ids = {}, set = {}, bucket = 0, amount = 0, received = 0, ready = false, version = 0 }
end

-- Datensaetze der 14 Slots anlegen (idempotent; aus Slots.LIST, sonst Rueckfall).
local function BuildSlots()
   local order = {}
   local S = T.Slots
   local list = S and S.LIST
   if type(list) == "table" then
      for i = 1, #list do
         local def = list[i]
         if type(def) == "table" and type(def.server) == "number" then
            order[#order + 1] = def.server
         end
      end
   end
   if #order == 0 then
      for i = 1, #FALLBACK_SLOTS do order[i] = FALLBACK_SLOTS[i] end
   end
   tsort(order)
   SERVER_SLOTS = order
   for i = 1, #order do
      local slot = order[i]
      if not recs[slot] then
         recs[slot] = {
            slot = slot, itemId = 0, link = nil, eq = nil,
            resolved = true, never = false,
            applied = 0, sel = nil,
            list = NewList(), streaming = false,
         }
      end
   end
end
BuildSlots()

local function Rec(slot)
   local n = ToUInt(slot)
   if n == nil then return nil end
   return recs[n]
end

-- Name aus einem Item-Link ("|Hitem:..|h[Name]|h").
local function NameFromLink(link)
   if type(link) ~= "string" then return nil end
   return smatch(link, "%[(.-)%]")
end

-- Qualitaet aus dem Farbcode eines Item-Links (nur Rueckfall, solange die
-- Iteminfo nicht im Cache liegt); nil wenn unbekannt.
local QUALITY_BY_COLOR = {
   ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
   ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6,
}

local function QualityFromLink(link)
   if type(link) ~= "string" then return nil end
   local hex = smatch(link, "^|c%x%x(%x%x%x%x%x%x)")
   if not hex then return nil end
   return QUALITY_BY_COLOR[string.lower(hex)]
end

-- ---------------------------------------------------------------------------
-- Ausruestung
-- ---------------------------------------------------------------------------

-- Liest Iteminfo des angelegten Gegenstands in den Datensatz. Ohne
-- vorliegende Info gilt der Slot als READY und wird bei ITEMS_RESOLVED neu
-- bewertet (resolved=false).
local function ResolveEquipped(rec)
   local id = rec.itemId
   if id == 0 then
      rec.eq, rec.resolved, rec.never = nil, true, false
      return
   end
   local name, quality, icon, equipLoc, typeKey
   local It = T.Items
   local info
   if It then
      if It.Get then info = It.Get(id)
      elseif It.Info then info = It.Info(id) end
   end
   if type(info) == "table" then
      name, quality, icon = info.name, info.quality, info.icon
      equipLoc, typeKey = info.equipLoc, info.typeKey
   elseif GetItemInfo then
      local n, _, q, _, _, itype, subtype, _, loc, tex = GetItemInfo(rec.link or id)
      if n then
         name, quality, icon, equipLoc = n, q, tex, loc
         if It and It.TypeKeyFromNames then typeKey = It.TypeKeyFromNames(itype, subtype) end
      end
   end
   rec.eq = {
      id = id, link = rec.link, name = name or NameFromLink(rec.link),
      quality = quality or QualityFromLink(rec.link),
      icon = icon, equipLoc = equipLoc, typeKey = typeKey,
   }
   if equipLoc ~= nil then
      rec.resolved = true
      rec.never = IsNeverLoc(equipLoc)
   else
      rec.resolved = false
      rec.never = false
   end
end

-- Liest die 14 Slots; bei Aenderung: Auswahl verwerfen, Liste als veraltet
-- markieren, EQUIPMENT_CHANGED feuern, Listen entprellt neu anfordern.
-- Ausloeser sind PLAYER_EQUIPMENT_CHANGED, PLAYER_ENTERING_WORLD und Refresh.
function State.RefreshEquipment()
   local changed, cleared = {}, {}
   for i = 1, #SERVER_SLOTS do
      local slot = SERVER_SLOTS[i]
      local rec = recs[slot]
      local link = EquippedLink(slot)
      local id = 0
      if link then id = ItemIdFromLink(link) or 0 end
      if id ~= rec.itemId then
         rec.itemId = id
         rec.link = (id ~= 0) and link or nil
         ResolveEquipped(rec)
         rec.list.ready = false             -- Liste gehoert zum alten Gegenstand
         rec.list.version = rec.list.version + 1
         if rec.sel ~= nil then
            rec.sel = nil
            cleared[#cleared + 1] = slot
         end
         changed[#changed + 1] = slot
      elseif id ~= 0 and link ~= rec.link then
         rec.link = link                    -- Verzauberung/Edelstein: gleiche ID
         if rec.eq then rec.eq.link = link end
      end
   end
   for i = 1, #changed do Fire("EQUIPMENT_CHANGED", changed[i]) end
   for i = 1, #cleared do Fire("WANTED_CHANGED", cleared[i]) end
   if #changed > 0 then
      State.MarkListsDirty()
      State.ScheduleListRefresh()
      State.RequestCost()
   end
   return #changed
end

-- ITEMS_RESOLVED: Slots, deren Iteminfo fehlte, neu bewerten.
local function OnItemsResolved()
   for i = 1, #SERVER_SLOTS do
      local slot = SERVER_SLOTS[i]
      local rec = recs[slot]
      if rec.itemId ~= 0 and not rec.resolved then
         local wasNever = rec.never
         ResolveEquipped(rec)
         if rec.resolved then
            if rec.never and not wasNever and rec.sel ~= nil then
               rec.sel = nil
               Fire("EQUIPMENT_CHANGED", slot)
               Fire("WANTED_CHANGED", slot)
               State.RequestCost()
            else
               Fire("EQUIPMENT_CHANGED", slot)
            end
         end
      end
   end
end

-- Angelegter Gegenstand: { id, link, name, quality, icon, equipLoc, typeKey } | nil.
-- Felder ausser id/link koennen nil sein, solange die Iteminfo nicht vorliegt.
-- Ein fehlender typeKey wird nachgetragen, sobald Items ihn kennt (die AH-Listen
-- stehen u. U. erst nach dem ersten Ausruesten bereit).
function State.Equipped(slot)
   local rec = Rec(slot)
   if not rec or rec.itemId == 0 then return nil end
   local eq = rec.eq
   if eq and eq.typeKey == nil and eq.equipLoc ~= nil then
      local It = T.Items
      local info = It and It.Info and It.Info(rec.itemId)
      if type(info) == "table" and info.typeKey ~= nil then eq.typeKey = info.typeKey end
   end
   return eq
end

-- "EMPTY" (nichts angelegt) | "NEVER" (nie transmogbar) | "READY".
function State.SlotState(slot)
   local rec = Rec(slot)
   if not rec then return "NEVER" end
   if rec.itemId == 0 then return "EMPTY" end
   if rec.never then return "NEVER" end
   return "READY"
end

-- ---------------------------------------------------------------------------
-- Applied / Baseline / Wanted
-- ---------------------------------------------------------------------------

-- Rohwert vom Server: 0 | itemId | HIDDEN.
function State.Applied(slot)
   local rec = Rec(slot)
   return rec and rec.applied or 0
end

-- true, wenn ein gespeichertes Aussehen nicht (mehr) in der fertigen Liste steht.
function State.IsInactive(slot)
   local rec = Rec(slot)
   if not rec then return false end
   local a = rec.applied
   if a == 0 or a == HIDDEN then return false end
   local list = rec.list
   if not list.ready then return false end
   return list.set[a] ~= true
end

-- Applied, aber 0 wenn inaktiv.
function State.Baseline(slot)
   local rec = Rec(slot)
   if not rec then return 0 end
   if State.IsInactive(rec.slot) then return 0 end
   return rec.applied
end

-- Effektiver Wunsch: Auswahl, sonst Baseline.
function State.Wanted(slot)
   local rec = Rec(slot)
   if not rec then return 0 end
   if rec.sel ~= nil then return rec.sel end
   return State.Baseline(rec.slot)
end

-- Auswahl vorhanden UND ~= Baseline.
function State.HasPending(slot)
   local rec = Rec(slot)
   if not rec or rec.sel == nil then return false end
   return rec.sel ~= State.Baseline(rec.slot)
end

-- Slots mit ausstehender Aenderung, aufsteigend nach Server-Slot.
function State.PendingSlots()
   local out = {}
   for i = 1, #SERVER_SLOTS do
      local slot = SERVER_SLOTS[i]
      if State.HasPending(slot) then out[#out + 1] = slot end
   end
   return out
end

-- Anzahl der Slots mit ausstehender Aenderung.
function State.PendingCount()
   local n = 0
   for i = 1, #SERVER_SLOTS do
      if State.HasPending(SERVER_SLOTS[i]) then n = n + 1 end
   end
   return n
end

-- ---------------------------------------------------------------------------
-- Auswahl
-- ---------------------------------------------------------------------------

-- Darf `id` im Slot gewaehlt werden? Regeln:
--   * Slot muss READY sein (nicht leer, nicht NEVER)
--   * HIDDEN nur in hideable Slots
--   * 0 (Original/Entfernen) immer
--   * sonst: bei FERTIGER Liste muss die id darin stehen; bei noch nicht
--     fertiger Liste wird optimistisch akzeptiert und beim Listenende
--     bereinigt (OnListEnd verwirft Auswahlen, die nicht in der Liste stehen)
local function CanSelect(rec, id)
   if State.SlotState(rec.slot) ~= "READY" then return false end
   if id == HIDDEN then return IsHideable(rec.slot) end
   if id == 0 then return true end
   local list = rec.list
   if list.ready then return list.set[id] == true end
   return true
end

-- Setzt die Auswahl; gleich Baseline entfernt sie. Rueckgabe: ob sich etwas aenderte.
local function StoreSelection(rec, id)
   local new = id
   if id == State.Baseline(rec.slot) then new = nil end
   if rec.sel == new then return false end
   rec.sel = new
   return true
end

-- Waehlt `id` (itemId | HIDDEN | 0) fuer den Slot. Rueckgabe: true wenn die
-- Auswahl gueltig war (auch wenn sie nichts aenderte), sonst false.
function State.Select(slot, id)
   local rec = Rec(slot)
   id = ToUInt(id)
   if not rec or id == nil then return false end
   if not CanSelect(rec, id) then return false end
   if StoreSelection(rec, id) then
      Fire("WANTED_CHANGED", rec.slot)
      State.RequestCost()
   end
   return true
end

-- Verwirft die Auswahl eines Slots. Rueckgabe: true wenn eine bestand.
function State.Discard(slot)
   local rec = Rec(slot)
   if not rec or rec.sel == nil then return false end
   rec.sel = nil
   Fire("WANTED_CHANGED", rec.slot)
   State.RequestCost()
   return true
end

-- Verwirft alle Auswahlen. Rueckgabe: true wenn eine bestand.
function State.DiscardAll()
   local any = false
   for i = 1, #SERVER_SLOTS do
      local rec = recs[SERVER_SLOTS[i]]
      if rec.sel ~= nil then
         rec.sel = nil
         any = true
      end
   end
   if any then
      Fire("WANTED_CHANGED", nil)
      State.RequestCost()
   end
   return any
end

-- Rechtsklick-Logik: Pending -> verwerfen; sonst Aussehen vorhanden -> Entfernen
-- vormerken (Auswahl 0). Rueckgabe: true wenn sich etwas aenderte.
function State.Toggle(slot)
   local rec = Rec(slot)
   if not rec then return false end
   if State.HasPending(rec.slot) then return State.Discard(rec.slot) end
   if State.Baseline(rec.slot) ~= 0 then
      local before = rec.sel
      State.Select(rec.slot, 0)
      return rec.sel ~= before
   end
   return false
end

-- Mehrere Auswahlen auf einmal (Outfits): map[slot] = id. Ungueltige Eintraege
-- werden uebersprungen; EIN WANTED_CHANGED(nil). Rueckgabe: Anzahl geaenderter Slots.
function State.SetMany(map)
   if type(map) ~= "table" then return 0 end
   local changed = 0
   for i = 1, #SERVER_SLOTS do
      local slot = SERVER_SLOTS[i]
      local v = map[slot]
      if v ~= nil then
         local id = ToUInt(v)
         local rec = recs[slot]
         if id ~= nil and CanSelect(rec, id) and StoreSelection(rec, id) then
            changed = changed + 1
         end
      end
   end
   if changed > 0 then
      Fire("WANTED_CHANGED", nil)
      State.RequestCost()
   end
   return changed
end

-- Verwirft Auswahlen eines Slots, die (nach neuer Liste/neuem Status) nicht
-- mehr gelten. Rueckgabe: true wenn etwas verworfen wurde (kein Event hier).
local function PruneSlot(rec)
   local sel = rec.sel
   if sel == nil then return false end
   local drop = false
   if sel == State.Baseline(rec.slot) then
      drop = true
   elseif State.SlotState(rec.slot) ~= "READY" then
      drop = true
   elseif sel ~= 0 and sel ~= HIDDEN and rec.list.ready and rec.list.set[sel] ~= true then
      drop = true
   elseif sel == HIDDEN and not IsHideable(rec.slot) then
      drop = true
   end
   if drop then rec.sel = nil end
   return drop
end

-- ---------------------------------------------------------------------------
-- Listen
-- ---------------------------------------------------------------------------

-- Liste eines Slots: { ids, set, bucket, amount, received, ready, version }; nie nil.
function State.List(slot)
   local rec = Rec(slot)
   if not rec then return EMPTY_LIST end
   return rec.list
end

-- Steht `id` im Slot zur Verfuegung? 0 immer; HIDDEN nur hideable; sonst Liste.
function State.IsAvailable(slot, id)
   local rec = Rec(slot)
   id = ToUInt(id)
   if not rec or id == nil then return false end
   if id == 0 then return true end
   if id == HIDDEN then return IsHideable(rec.slot) end
   return rec.list.set[id] == true
end

-- Ob die Liste des Slots fertig geladen ist.
function State.ListReady(slot)
   local rec = Rec(slot)
   return rec ~= nil and rec.list.ready
end

-- Ob alle 14 Listen fertig sind.
function State.ListsReady()
   for i = 1, #SERVER_SLOTS do
      if not recs[SERVER_SLOTS[i]].list.ready then return false end
   end
   return true
end

-- Ob schon ein TransmogStatus empfangen wurde.
function State.StatusKnown()
   return statusKnown
end

-- Markiert die Listen als veraltet (naechstes Refresh fordert sie an).
function State.MarkListsDirty()
   listsDirty = true
end

-- Fordert die Listen jetzt an und verwirft einen geplanten Aufruf.
local function RequestListsNow()
   if equipTimer then
      Cancel(equipTimer)
      equipTimer = nil
   end
   listsDirty = false
   lastListRequestAt = Now()
   local Net = T.Net
   if Net and Net.RequestLists then Net.RequestLists() end
end

local function OnEquipTimer()
   equipTimer = nil
   RequestListsNow()
   local Net = T.Net
   if Net and Net.RequestStatus then Net.RequestStatus() end
end

-- Plant Listen- und Statusanfrage in 0,5 s (jeder Aufruf setzt die Frist neu).
function State.ScheduleListRefresh()
   if equipTimer then Cancel(equipTimer) end
   equipTimer = After(EQUIP_DEBOUNCE, OnEquipTimer)
end

-- Fenster sichtbar? (nur lesen, nie zwingend vorhanden)
local function WindowShown()
   local UI = T.UI
   local W = UI and UI.Window
   if W and W.IsShown then
      local ok, shown = pcall(W.IsShown)
      return ok and shown and true or false
   end
   return false
end

local function OnDirtyTimer()
   dirtyTimer = nil
   if listsDirty and WindowShown() then State.Refresh() end
end

-- Server: neuer Strom fuer einen Slot beginnt.
function State.OnListStart(slot, bucket, amount)
   local rec = Rec(slot)
   if not rec then return end
   local list = NewList()
   list.bucket = ToUInt(bucket) or 0
   list.amount = ToUInt(amount) or 0
   list.version = rec.list.version + 1
   rec.list = list
   rec.streaming = true
   Fire("LIST_PROGRESS", rec.slot, 0, list.amount)
end

-- Server: weitere IDs des laufenden Stroms (ohne vorheriges "start" ignoriert).
function State.OnListChunk(slot, ids)
   local rec = Rec(slot)
   if not rec or not rec.streaming or type(ids) ~= "table" then return end
   local list = rec.list
   local added = 0
   for i = 1, #ids do
      local id = ToUInt(ids[i])
      if id and id ~= 0 and not list.set[id] then
         list.set[id] = true
         list.ids[#list.ids + 1] = id
         added = added + 1
      end
   end
   if added > 0 then
      list.received = list.received + added
      list.version = list.version + 1
      Fire("LIST_PROGRESS", rec.slot, list.received, list.amount)
   end
end

-- Server: Strom beendet => Liste fertig (ohne vorheriges "start" ignoriert).
function State.OnListEnd(slot)
   local rec = Rec(slot)
   if not rec or not rec.streaming then return end
   rec.streaming = false
   local list = rec.list
   list.ready = true
   list.version = list.version + 1
   if list.amount ~= list.received then
      Dbg("State: Liste %d: %d von %d IDs", rec.slot, list.received, list.amount)
   end
   local dropped = PruneSlot(rec)
   Fire("LIST_READY", rec.slot)
   if dropped then Fire("WANTED_CHANGED", rec.slot) end
   if dropped or rec.sel ~= nil then State.RequestCost() end
end

-- ---------------------------------------------------------------------------
-- Status vom Server
-- ---------------------------------------------------------------------------

-- Server: Gesamtstatus. map[slot] = fakeEntry, nur Slots mit Aussehen.
function State.OnStatus(map)
   if type(map) ~= "table" then return end
   local changed = false
   for i = 1, #SERVER_SLOTS do
      local slot = SERVER_SLOTS[i]
      local rec = recs[slot]
      local v = ToUInt(map[slot]) or 0
      if rec.applied ~= v then
         rec.applied = v
         changed = true
      end
   end
   local first = not statusKnown
   statusKnown = true
   if changed or first then Fire("STATUS_CHANGED") end
   -- Auswahlen, die jetzt der Baseline entsprechen, sind keine mehr
   local pruned = false
   for i = 1, #SERVER_SLOTS do
      if PruneSlot(recs[SERVER_SLOTS[i]]) then pruned = true end
   end
   if pruned then Fire("WANTED_CHANGED", nil) end
   if changed or pruned then State.RequestCost() end
   -- Namen/Icons der angewendeten Aussehen vorwaermen
   local It = T.Items
   if It and It.Request then
      for i = 1, #SERVER_SLOTS do
         local a = recs[SERVER_SLOTS[i]].applied
         if a ~= 0 and a ~= HIDDEN then It.Request(a) end
      end
   end
end

-- Server: das Transmogrifizierer-Fenster soll gleich erscheinen.
function State.OnOpen()
   State.serverOpenAt = Now()
   Fire("SERVER_OPEN")
end

-- ---------------------------------------------------------------------------
-- Sammlung
-- ---------------------------------------------------------------------------

-- Server: ein Aussehen wurde (neu) gesammelt. Der Login-Sweep schickt viele
-- davon; die zaehlen nicht als "neu". Das Event feuert immer.
function State.OnCollectionUpdated(id)
   id = ToUInt(id)
   if not id or id == 0 then return end
   local Net = T.Net
   if Net and Net.SetCollectionState then Net.SetCollectionState(id, 1) end
   local sweep = T.IsLoginSweep and T.IsLoginSweep()
   if not sweep then State.new[id] = true end
   -- neue Aussehen koennen in den Listen auftauchen
   listsDirty = true
   if dirtyTimer then Cancel(dirtyTimer) end
   dirtyTimer = After(DIRTY_DEBOUNCE, OnDirtyTimer)
   Fire("COLLECTION_UPDATED", id)
end

-- Server: Antwort auf GetCollectionStatus.
function State.OnCollectionStatus(id, state)
   id, state = ToUInt(id), ToUInt(state)
   if not id or id == 0 or state == nil or state > 2 then return end
   local Net = T.Net
   if Net and Net.SetCollectionState then
      state = Net.SetCollectionState(id, state) or state
   end
   Fire("COLLECTION_STATUS", id, state)
end

-- ---------------------------------------------------------------------------
-- Kosten
-- ---------------------------------------------------------------------------

-- Paare {slot, wanted} aller ausstehenden Slots mit wanted ~= 0, Signatur
-- ("slot:id,slot:id") und ob mindestens ein kostenpflichtiges (~= HIDDEN) dabei ist.
local function BuildCostPairs()
   local list, parts, paid = {}, {}, false
   for i = 1, #SERVER_SLOTS do
      local slot = SERVER_SLOTS[i]
      local rec = recs[slot]
      if rec.sel ~= nil and State.HasPending(slot) and rec.sel ~= 0 then
         list[#list + 1] = { slot, rec.sel }
         parts[#parts + 1] = slot .. ":" .. rec.sel
         if rec.sel ~= HIDDEN then paid = true end
      end
   end
   return list, tconcat(parts, ","), paid
end

local CostDebounceFired, CostTimeout

-- Plant die Kostenanfrage in 0,25 s.
local function ArmCostRequest()
   cost.scheduled = true
   if cost.debounce then Cancel(cost.debounce) end
   cost.debounce = After(COST_DEBOUNCE, CostDebounceFired)
end

-- Meldet COST_CHANGED, wenn sich der sichtbare Stand geaendert hat.
local function NotifyCost()
   local c = State.Cost()
   local key = sformat("%s|%s|%s|%s", tostring(c.copper), tostring(c.canPurchase),
      tostring(c.valid), tostring(c.pending))
   if key ~= cost.notifyKey then
      cost.notifyKey = key
      Fire("COST_CHANGED")
   end
end

-- Sendet die Kostenanfrage, sofern noetig.
local function SendCostRequest()
   local list, sig, paid = BuildCostPairs()
   if not paid then
      NotifyCost()
      return
   end
   if cost.recv >= cost.sent and cost.validSig == sig then       -- bereits bekannt
      NotifyCost()
      return
   end
   if cost.recv < cost.sent and cost.lastSig == sig then          -- laeuft schon
      NotifyCost()
      return
   end
   cost.sent = cost.sent + 1
   cost.lastSig = sig
   cost.retries = 0
   if cost.timer then Cancel(cost.timer) end
   cost.timer = After(COST_TIMEOUT, CostTimeout, cost.sent)
   local Net = T.Net
   local result = Net and Net.RequestCost and Net.RequestCost(list)
   if result == false then
      -- nicht gesendet: Zaehler zurueck, nichts erwarten
      if cost.recv < cost.sent then cost.sent = cost.sent - 1 end
      if cost.timer then
         Cancel(cost.timer)
         cost.timer = nil
      end
   end
   NotifyCost()
end

CostDebounceFired = function()
   cost.scheduled = false
   cost.debounce = nil
   SendCostRequest()
end

-- Antwort blieb aus: einmal wiederholen, dann aufgeben (Kosten unbekannt,
-- aber nicht ausstehend).
CostTimeout = function(n)
   cost.timer = nil
   if n ~= cost.sent or cost.recv >= cost.sent then return end
   local list, sig, paid = BuildCostPairs()
   if cost.retries < 1 and paid and sig == cost.lastSig then
      cost.retries = cost.retries + 1
      cost.sent = cost.sent + 1
      cost.timer = After(COST_TIMEOUT, CostTimeout, cost.sent)
      local Net = T.Net
      if Net and Net.RequestCost then Net.RequestCost(list) end
      return
   end
   cost.recv = cost.sent
   NotifyCost()
end

-- Fordert die Kosten fuer die aktuelle Auswahl an (entprellt 0,25 s). Ohne
-- kostenpflichtige Pending-Slots wird nichts gesendet (Kosten 0, gueltig).
function State.RequestCost()
   local _, sig, paid = BuildCostPairs()
   if not paid then
      if cost.debounce then
         Cancel(cost.debounce)
         cost.debounce = nil
      end
      cost.scheduled = false
      NotifyCost()
      return
   end
   if cost.recv >= cost.sent and cost.validSig == sig then
      if cost.debounce then
         Cancel(cost.debounce)
         cost.debounce = nil
      end
      cost.scheduled = false
      NotifyCost()
      return
   end
   ArmCostRequest()
   NotifyCost()
end

-- Server: Antwort auf CalculateCost. Nur die Antwort der LETZTEN Anfrage
-- (recv == sent) zaehlt; aeltere werden verworfen.
function State.OnCost(copper, canPurchase)
   copper = ToUInt(copper)
   if copper == nil then return end
   canPurchase = canPurchase and true or false
   if cost.recv >= cost.sent then
      -- nichts ausstehend (z. B. verspaetete Antwort nach dem Aufgeben):
      -- nur uebernehmen, wenn die letzte Anfrage zur Auswahl passt
      local _, sig, paid = BuildCostPairs()
      if paid and cost.lastSig == sig then
         cost.copper, cost.canPurchase, cost.validSig = copper, canPurchase, sig
         NotifyCost()
      end
      return
   end
   cost.recv = cost.recv + 1
   if cost.recv < cost.sent then return end      -- veraltet: verworfen
   if cost.timer then
      Cancel(cost.timer)
      cost.timer = nil
   end
   cost.retries = 0
   cost.copper, cost.canPurchase, cost.validSig = copper, canPurchase, cost.lastSig
   -- Auswahl hat sich seit der Anfrage geaendert?
   local _, sig, paid = BuildCostPairs()
   if paid and sig ~= cost.validSig and not cost.scheduled then ArmCostRequest() end
   NotifyCost()
end

-- Kosten der aktuellen Auswahl: { copper, canPurchase, valid, pending }.
-- valid = Antwort fuer genau die aktuelle Auswahl liegt vor; pending = eine
-- Anfrage ist geplant oder unterwegs. Ohne kostenpflichtige Slots: 0 / gueltig.
function State.Cost()
   local _, sig, paid = BuildCostPairs()
   if not paid then
      return { copper = 0, canPurchase = true, valid = true, pending = false }
   end
   local valid = (cost.validSig == sig)
   local pending = false
   if not valid then
      if cost.scheduled then
         pending = true
      elseif cost.recv < cost.sent and cost.lastSig == sig then
         pending = true
      elseif cost.lastSig ~= sig then
         -- Auswahl geaendert, aber niemand hat angefragt: nachholen
         pending = true
         ArmCostRequest()
      end
   end
   return { copper = cost.copper, canPurchase = cost.canPurchase, valid = valid, pending = pending }
end

-- PLAYER_MONEY: Bezahlbarkeit gegen das aktuelle Geld neu bewerten.
local function OnMoney()
   if cost.validSig == nil or cost.copper <= 0 or not GetMoney then return end
   local money = GetMoney()
   if type(money) ~= "number" then return end
   local can = money >= cost.copper
   if can ~= cost.canPurchase then
      cost.canPurchase = can
      NotifyCost()
   end
end

-- ---------------------------------------------------------------------------
-- Anwenden
-- ---------------------------------------------------------------------------

-- Ob und warum nicht angewendet werden kann. Reihenfolge der Gruende:
-- SERVER, NONE, BUSY, VENDOR, COST_PENDING, MONEY.
function State.CanApply()
   local Net = T.Net
   if Net and Net.state == "ABSENT" then return false, "APPLY_REASON_SERVER" end
   if State.PendingCount() == 0 then return false, "APPLY_REASON_NONE" end
   if apply.busy then return false, "APPLY_REASON_BUSY" end
   local DB = T.DB
   local anywhere = DB and DB.global and DB.global.allowAnywhere
   if not State.atVendor and not anywhere then return false, "APPLY_REASON_VENDOR" end
   local c = State.Cost()
   if c.pending then return false, "APPLY_REASON_COST_PENDING" end
   if c.valid and not c.canPurchase then return false, "APPLY_REASON_MONEY" end
   return true, nil
end

-- Ob "Alles entfernen" moeglich ist (SERVER, BUSY, VENDOR).
function State.CanRemoveAll()
   local Net = T.Net
   if Net and Net.state == "ABSENT" then return false, "APPLY_REASON_SERVER" end
   if apply.busy then return false, "APPLY_REASON_BUSY" end
   local DB = T.DB
   local anywhere = DB and DB.global and DB.global.allowAnywhere
   if not State.atVendor and not anywhere then return false, "APPLY_REASON_VENDOR" end
   return true, nil
end

-- true, solange ein Anwenden-Stapel laeuft.
function State.Busy()
   return apply.busy
end

-- Meldet einen abgelehnten Aufruf im Chat (nur Gruende, die der Spieler
-- beheben kann; NONE und BUSY bleiben still, z. B. bei Doppelklick).
local function Refuse(reason)
   if reason == "APPLY_REASON_VENDOR" then
      Say(false, "MSG_NO_VENDOR")
   elseif reason == "APPLY_REASON_SERVER" then
      Say(true, "MSG_SERVER_ABSENT")
   elseif reason == "APPLY_REASON_MONEY" or reason == "APPLY_REASON_COST_PENDING" then
      Say(false, reason)
   end
end

-- Setzt applied lokal (nach Erfolgsmeldung) und raeumt die Auswahl auf.
local function ApplyLocal(slot, id)
   local rec = recs[slot]
   if not rec then return end
   rec.applied = id
   local selCleared = false
   if rec.sel ~= nil and (rec.sel == id or rec.sel == State.Baseline(slot)) then
      rec.sel = nil
      selCleared = true
   end
   Fire("STATUS_CHANGED")
   if selCleared then Fire("WANTED_CHANGED", slot) end
   State.RequestCost()
end

-- Zaehlt das Ergebnis einer Operation im Stapel und meldet es.
local function CountResult(op, ok, itemId)
   if ok then
      apply.nOk = apply.nOk + 1
   else
      apply.nFail = apply.nFail + 1
      Say(true, "MSG_APPLY_SLOT_FAILED", SlotLabel(op.slot))
   end
   Fire("APPLY_PROGRESS", op.slot, ok, itemId)
end

-- Stapel beendet: Busy aus, APPLY_DONE, Resync von Status und Kosten.
local function FinishBatch()
   apply.busy = false
   apply.ops = {}
   apply.index = 0
   local nOk, nFail = apply.nOk, apply.nFail
   if nFail > 0 then
      Say(false, "MSG_APPLY_DONE", nOk, nFail)
   elseif nOk > 0 then
      Say(false, "MSG_APPLY_OK")
   end
   Fire("APPLY_DONE", nOk, nFail)
   local Net = T.Net
   if Net and Net.RequestStatus then Net.RequestStatus() end
   State.RequestCost()
end

local SendNextOp

-- Zeitueberschreitung einer Operation: als Fehlschlag zaehlen, als "Geist"
-- in der Warteschlange lassen und weitermachen.
local function OnOpTimeout(op)
   if op.state ~= "SENT" then return end
   op.state = "EXPIRED"
   op.timer = nil
   CountResult(op, false, op.id)
   SendNextOp()
end

-- Sendet die naechste Operation des Stapels (oder beendet den Stapel).
-- Wiedereintrittssicher: der Eintrag steht in der Warteschlange und der
-- Timer laeuft, BEVOR gesendet wird.
SendNextOp = function()
   if not apply.busy then return end
   if apply.index >= #apply.ops then
      FinishBatch()
      return
   end
   apply.index = apply.index + 1
   local op = apply.ops[apply.index]
   op.state = "SENT"
   op.sentAt = Now()
   fifo[#fifo + 1] = op
   op.timer = After(APPLY_TIMEOUT, OnOpTimeout, op)
   local Net = T.Net
   local sent
   if Net then
      if op.id == 0 then
         sent = Net.SendRemove and Net.SendRemove(op.slot)
      else
         sent = Net.SendApply and Net.SendApply(op.slot, op.id)
      end
   else
      sent = false
   end
   if sent == false and op.state == "SENT" then
      -- konnte nicht abgeschickt werden: sofort Fehlschlag
      for i = #fifo, 1, -1 do
         if fifo[i] == op then
            tremove(fifo, i)
            break
         end
      end
      Cancel(op.timer)
      op.timer = nil
      op.state = "FAILED"
      CountResult(op, false, op.id)
      SendNextOp()
   end
end

-- Wendet alle ausstehenden Aenderungen an (eine Operation nach der anderen).
-- Rueckgabe: true wenn gestartet, sonst false, reasonKey (siehe CanApply).
-- Ein Aufruf waehrend Busy wird ignoriert.
function State.Apply()
   local ok, reason = State.CanApply()
   if not ok then
      Refuse(reason)
      return false, reason
   end
   -- lange abgelaufene Geister aus der Warteschlange entfernen
   local now = Now()
   for i = #fifo, 1, -1 do
      local g = fifo[i]
      if g.state == "EXPIRED" and (now - (g.sentAt or 0)) > GHOST_MAX_AGE then
         tremove(fifo, i)
      end
   end
   local ops = {}
   local pending = State.PendingSlots()
   for i = 1, #pending do
      ops[#ops + 1] = { slot = pending[i], id = recs[pending[i]].sel, state = "NEW" }
   end
   apply.ops = ops
   apply.index = 0
   apply.nOk, apply.nFail = 0, 0
   apply.busy = true
   Fire("APPLY_STARTED", #ops)
   SendNextOp()
   return true
end

-- Server: Ergebnis einer Apply-/Remove-Operation.
--   ok=false            Fehlschlag ohne Slotangabe (FIFO: aelteste Operation)
--   ok=true, slot, id   Erfolg; ohne slot/id: aelteste Operation (FIFO)
function State.OnApplyResult(ok, slot, itemId)
   slot, itemId = ToUInt(slot), ToUInt(itemId)
   if slot ~= nil and not recs[slot] then return end
   if not ok then
      local op = tremove(fifo, 1)
      if not op then return end                 -- unaufgefordert
      if op.state == "SENT" then
         op.state = "FAILED"
         Cancel(op.timer)
         op.timer = nil
         CountResult(op, false, op.id)
         SendNextOp()
      end
      return
   end
   -- Erfolg: passende Operation suchen (Slot der Antwort, sonst die aelteste)
   local idx
   if slot ~= nil then
      for i = 1, #fifo do
         if fifo[i].slot == slot then
            idx = i
            break
         end
      end
   elseif #fifo > 0 then
      idx = 1
   end
   if not idx then
      -- unaufgefordert oder Spaetantwort einer verworfenen Operation: der
      -- Server hat es angewendet, also lokal uebernehmen; Warteschlange bleibt
      if slot ~= nil then ApplyLocal(slot, itemId or 0) end
      return
   end
   local op = fifo[idx]
   -- aeltere, noch unbeantwortete Eintraege sind verloren
   local lost = {}
   for i = 1, idx - 1 do lost[#lost + 1] = fifo[i] end
   for _ = 1, idx do tremove(fifo, 1) end
   for i = 1, #lost do
      local l = lost[i]
      if l.state == "SENT" then
         l.state = "FAILED"
         Cancel(l.timer)
         l.timer = nil
         CountResult(l, false, l.id)
      end
   end
   local useSlot = slot or op.slot
   local id = itemId
   if slot == nil or id == nil then id = op.id end
   ApplyLocal(useSlot, id)
   if op.state == "SENT" then
      op.state = "DONE"
      Cancel(op.timer)
      op.timer = nil
      CountResult(op, true, id)
      SendNextOp()
   else
      op.state = "DONE"                         -- Spaetantwort einer abgelaufenen Operation
   end
end

-- Entfernt alle Aussehen am Server und verwirft die Auswahl. Rueckgabe: true,
-- oder false, reasonKey (siehe CanRemoveAll).
function State.RemoveAll()
   local ok, reason = State.CanRemoveAll()
   if not ok then
      Refuse(reason)
      return false, reason
   end
   local Net = T.Net
   if Net and Net.SendRemoveAll then Net.SendRemoveAll() end
   -- der Server antwortet mit TransmogStatus; lokal sofort nachziehen
   local changed = false
   for i = 1, #SERVER_SLOTS do
      local rec = recs[SERVER_SLOTS[i]]
      if rec.applied ~= 0 then
         rec.applied = 0
         changed = true
      end
      rec.sel = nil
   end
   if changed then Fire("STATUS_CHANGED") end
   Fire("WANTED_CHANGED", nil)
   State.RequestCost()
   return true
end

-- ---------------------------------------------------------------------------
-- Umgebung
-- ---------------------------------------------------------------------------

-- Merkt, ob ein Transmogrifizierer in Reichweite ist; feuert VENDOR_CHANGED.
function State.SetVendor(atVendor)
   State.atVendor = atVendor and true or false
   Fire("VENDOR_CHANGED", State.atVendor)
end

-- Liest Ausruestung, fordert Status an und (falls noetig) die Listen.
-- Listen werden nur angefordert, wenn sie veraltet sind (Ausruestung oder
-- Sammlung hat sich geaendert), nie geladen wurden, aelter als 60 s sind,
-- der Server noch nicht geantwortet hat, nach 10 s noch unfertig sind
-- oder `force` gesetzt ist.
function State.Refresh(force)
   State.RefreshEquipment()
   local Net = T.Net
   if Net and Net.RequestStatus then Net.RequestStatus() end
   local age = lastListRequestAt and (Now() - lastListRequestAt) or nil
   local need = force or listsDirty or age == nil or age > LISTS_MAX_AGE
   if not need and age > LISTS_RETRY_AGE then
      if (Net and Net.state ~= "OK") or not State.ListsReady() then need = true end
   end
   if need then RequestListsNow() end
end

-- SERVER_STATE: bleibt der Server stumm, wird das nur gemeldet, wenn das
-- Fenster gerade offen ist (sonst erfaehrt der Spieler es beim Oeffnen).
-- Meldet sich der Server nach der Frist doch noch (Modul spaeter geladen,
-- Neustart), ist die erste Listenanfrage verloren: die Listen werden jetzt
-- angefordert, sofern sie nicht schon kommen (juengste Anfrage < 1 s her) --
-- sonst bliebe das Raster bis zum naechsten Oeffnen im Ladezustand.
local wasAbsent = false
local function OnServerState(state)
   if state == "ABSENT" then
      wasAbsent = true
      if WindowShown() then
         Say(true, "MSG_SERVER_ABSENT")
      end
   elseif state == "OK" and wasAbsent then
      wasAbsent = false
      local age = lastListRequestAt and (Now() - lastListRequestAt) or nil
      if not State.ListsReady() and (age == nil or age >= 1) then
         RequestListsNow()
      end
   end
end

-- Spielereignisse anbinden und die Ausruestung einmal lesen.
function State.Init()
   BuildSlots()
   if inited then return end
   inited = true
   local E = T.Events
   if E then
      if E.Game then
         E.Game("PLAYER_EQUIPMENT_CHANGED", function() State.RefreshEquipment() end)
         E.Game("PLAYER_ENTERING_WORLD", function() State.RefreshEquipment() end)
         E.Game("PLAYER_MONEY", OnMoney)
      end
      if E.On then
         E.On("ITEMS_RESOLVED", OnItemsResolved, State)
         E.On("SERVER_STATE", OnServerState, State)
      end
   end
   State.RefreshEquipment()
end
