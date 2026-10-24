-- Preview.lua  (T.UI.Preview)
-- ---------------------------------------------------------------------------
-- Die grosse Charaktervorschau: ein DressUpModel (Vorlage
-- TransmogPreviewModelTemplate, 221x362, Modell-Scale 2.0 aus Transmog.xml)
-- plus eine schmale Steuerzeile darunter ("<" ">" drehen, Reset).
--
-- Bedienung: Linksziehen dreht (SetFacing(facing + dx/34)), Rechtsziehen
-- verschiebt (SetPosition), Mausrad zoomt (Z +-1, begrenzt), "<"/">" drehen,
-- solange die Maustaste gehalten wird (OnUpdate nur waehrend des Haltens).
-- Das Ziehen endet auch, wenn die Taste nicht mehr gedrueckt ist (OnMouseUp
-- kann ausserhalb des Modells verloren gehen).
--
-- Ansicht: Startrotation SetRotation(0.61) wie im alten Addon (kein SetFacing
-- dazu); der Umhang-Fokus nutzt ebenfalls SetRotation (wie die Zellenmodelle).
-- Ob die Engine Rotation und Facing als EINEN Winkel oder als zwei Anteile
-- fuehrt, ist fuer 3.3.5a nicht gesichert: Drehungen laufen deshalb immer als
-- Paar SetRotation(r) + SetFacing(GetFacing()-Wert) (SetView), "Zuruecksetzen"
-- stellt den GetFacing()-Wert nach dem ersten Aufbau wieder her.
--
-- Ankleiden (SPEC 9.1, Portierung von OLD/ui/slots_model.lua RefreshPreviewModel):
--
--   * effektives Aussehen eines Platzes = State.Wanted(s) ~= 0 und Wanted(s),
--     sonst der angelegte Gegenstand; Reihenfolge aufsteigend nach Server-Slot.
--   * DressUpModel:Undress() leert BEIDE Haende; eine danach anprobierte Waffe
--     landet immer rechts. Darum nur Undress, wenn ein NEU gewaehltes
--     "Verborgen" vorliegt (Wanted == HIDDEN, Baseline ~= HIDDEN). Sonst von
--     SetUnit("player") (echte Ausruestung + angewendete Transmogs) ausgehen und
--     nur Plaetze, deren Aussehen vom Modellstand abweicht, mit TryOn aendern.
--   * Nach dem Undress-Weg beim naechsten Nicht-Verborgen-Zustand wieder
--     SetUnit("player"), Facing/Position bleiben erhalten.
--   * Fernkampf wird nur bei Bearbeitung des Fernkampfplatzes angeprobiert
--     (er verdeckt sonst die Nahkampfwaffe); im Undress-Weg zuerst (Nahkampf
--     gewinnt), bei Bearbeitung zuletzt.
--   * Nebenhand: Schild, Nebenhand-Gegenstand und Nebenhandwaffe werden links
--     gezeigt; jede andere einhaendige Waffe landet rechts (die Engine kennt
--     keine Handwahl, eine zweite Anprobe ersetzt die erste). Sie wird darum nur
--     angeprobiert, solange die Nebenhand bearbeitet wird und eine Auswahl aussteht:
--     dann ersetzt sie in der Vorschau die Haupthand (Nebenhand kommt in der
--     Reihenfolge nach der Haupthand, gewinnt also), mit Hinweis
--     PREVIEW_OFFHAND_NOTE_MAINHAND. Sonst wird sie uebersprungen (Hinweis
--     PREVIEW_OFFHAND_NOTE, solange eine Auswahl aussteht). Wird nach einem
--     gezeigten Schild eine Waffe gewaehlt, nach einer Waffe in der Haupthand
--     etwas anderes gewaehlt/verworfen oder der Fokus verlassen, wird neu geladen
--     (sonst bliebe der alte Schild bzw. die Waffe als scheinbare Auswahl stehen).
--   * Fernkampf bei Bearbeitung: wird in demselben Durchlauf die Haupthand neu
--     angeprobiert, kommt der Fernkampf danach erneut (zuletzt angeprobiert
--     gewinnt, beide liegen in derselben Hand).
--   * Nicht gecachte Gegenstaende gehen nie an TryOn: Items.Request, ueberspringen,
--     ITEMS_RESOLVED stoesst das Ankleiden erneut an.
--
-- Was das Modell zeigt, wird je Platz verfolgt (tried): nur Unterschiede werden
-- angewendet. Zusaetzlich zur alten Logik wird neu aufgebaut (SetUnit), wenn die
-- Verfolgung nicht mehr genuegt: ein Platz soll "verborgen"/leer sein, zeigt aber
-- etwas; die Ausruestung hat gewechselt; der Fernkampf wurde verlassen. Ebenso
-- bei jedem Zeigen des Containers (wie das alte Addon: Gestaltwechsel, Projektion).
--
-- Aktualisierung: Ereignisse -> ein entprellter Durchlauf (Util.Debounce
-- "ui-preview"), nur sichtbar; sonst Merker und Nachholen im OnShow.
-- Groessenaenderung (Layout) laedt nach Ruhe neu, falls das Fenster nicht
-- ohnehin Preview.Rebuild ruft.
--
-- Oeffentliche Schnittstelle (SPEC 6.5 / 11.2; Punkt-Aufruf, Create bindet die
-- Methoden zusaetzlich als Frame-Felder fuer den Doppelpunkt-Aufruf):
--   Preview.Create(parent) -> frame     Preview.Layout(w, h)
--   Preview.Refresh()   Preview.Rebuild()   Preview.ResetCamera()
--   Preview.SetFocusSlot(slot|nil)      Preview.model
-- Zusaetzlich: Preview.ApplyLocale(), Preview.frame, Preview.autoFocus (Umhang
-- dreht das Modell nach hinten), Preview.CONTROLS_HEIGHT (28: Steuerzeile unten;
-- die SlotBar richtet ihre Plaetze an der Buehne darueber aus).
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.UI = T.UI or {}

local Preview = T.UI.Preview or {}
T.UI.Preview = Preview

local floor, min, max = math.floor, math.min, math.max
local tsort, tinsert = table.sort, table.insert

local TEMPLATE = "TransmogPreviewModelTemplate"
local BASE_W, BASE_H = 221, 362          -- kalibrierter Bildausschnitt (Vorlage)
local DEFAULT_W, DEFAULT_H = 230, 400    -- bis Layout gerufen wird
local MIN_W, MIN_H = 60, 90
local CONTROL_H = 22                     -- Hoehe der Steuerzeile
local CONTROL_GAP = 6                    -- Abstand Modell <-> Steuerzeile
local BUTTON_W = 26                      -- Breite von "<" und ">"
local PAD = 4                            -- Rand innerhalb der Modellflaeche

local START_ROTATION = 0.61              -- Grundrotation (wie Cameras.BASE_ROTATION)
local ROTATE_DIV = 34                    -- Pixel je Bogenmass beim Ziehen
local PAN_DIV = 45                       -- Pixel je Einheit beim Verschieben
local TURN_RATE = 1.6                    -- rad/s bei gehaltenem Knopf
local TURN_STEP = 0.1                    -- rad sofort beim Druecken (kurzer Klick)
local ZOOM_STEP = 1                      -- je Rastung des Mausrads
-- Die Grenzen verhindern nur das Davonlaufen des Modells ("Ansicht zuruecksetzen"
-- holt es zurueck); sie liegen weit ausserhalb des nutzbaren Bereichs: die
-- Zellenkameras (Cameras) ruecken bis +8,8 (Nachtelf, Kopf) heran, und das alte
-- Addon kannte keine Grenze.
local ZOOM_OUT, ZOOM_IN = 10, 16         -- Spielraum um die Ausgangstiefe
local PAN_LIMIT = 8                      -- Verschiebung um die Ausgangslage
local REFRESH_DELAY = 0.03               -- Entprellung der Ereignisse
local REBUILD_DELAY = 0.35               -- Ruhe nach Groessenaenderung bis SetUnit
local KEY_REFRESH = "ui-preview"
local KEY_SIZE = "ui-preview-size"

local VIEW_BG = { 0.04, 0.045, 0.055, 0.92 }

-- Nebenhand: nur diese Gegenstandstypen werden links gezeichnet
local OFFHAND_OK = {
   INVTYPE_SHIELD = true,
   INVTYPE_HOLDABLE = true,
   INVTYPE_WEAPONOFFHAND = true,
}

-- Server-Slots, die die Logik kennt (aus Slots; Ersatz 14/16/17)
local function ServerOf(key, fallback)
   local def = T.Slots and T.Slots.BY_KEY and T.Slots.BY_KEY[key]
   return def and def.server or fallback
end
local SLOT_BACK = ServerOf("BACK", 14)
local SLOT_MAINHAND = ServerOf("MAINHAND", 15)
local SLOT_OFFHAND = ServerOf("OFFHAND", 16)
local SLOT_RANGED = ServerOf("RANGED", 17)

Preview.CONTROLS_HEIGHT = CONTROL_H + CONTROL_GAP
Preview.autoFocus = true         -- Umhang-Auswahl dreht das Modell nach hinten

-- Zustand des Singletons
local P = {
   frame = nil, viewport = nil, model = nil, note = nil,
   resetButton = nil, leftButton = nil, rightButton = nil, turner = nil,
   built = false,           -- SetUnit wurde mindestens einmal gerufen
   needsRebuild = true,     -- vor dem naechsten Ankleiden SetUnit rufen
   dirty = true,            -- Ankleiden steht aus (nicht sichtbar gewesen)
   undressed = false,       -- Modell steht nach Undress()
   tried = {},              -- [slot] = id, seit SetUnit/Undress anprobiert
   waiting = {},            -- [id] = true: nicht gecacht, ITEMS_RESOLVED neu ankleiden
   builtBase = {},          -- [slot] = Baseline zum Zeitpunkt von SetUnit
   builtEquip = {},         -- [slot] = angelegte ID zum Zeitpunkt von SetUnit
   facing = START_ROTATION, -- zuletzt gesetzte Drehung (Ersatz fuer GetFacing)
   rotation = START_ROTATION, -- zuletzt gesetzter SetRotation-Wert (Grund- bzw. Umhangansicht)
   startFacing = 0,         -- GetFacing() nach dem ersten Aufbau (Ziel von Reset)
   base = nil,              -- { z, x, y } Standardposition nach SetUnit
   focusSlot = nil,         -- vom Fenster gesetzter, bearbeiteter Slot
   focusTurned = false,     -- Modell wurde vom Fokus (Umhang) gedreht
   savedFacing = nil,       -- Drehung vor der Fokus-Drehung
   drag = nil,              -- { button, x, y } waehrend des Ziehens
   turnDir = nil,           -- -1/+1, solange ein Drehknopf gehalten wird
   w = nil, h = nil,        -- Container
   mw = nil, mh = nil,      -- Modellgroesse
   sizeDirty = false,       -- Modellgroesse hat sich seit SetUnit geaendert
   order = nil,             -- Server-Slots aufsteigend
   offhandSkipped = false,  -- eine Nebenhandwaffe wurde nicht gezeigt
   offhandInMain = false,   -- die Nebenhandwaffe ist angeprobiert und liegt in der Haupthand
   noteKey = nil,           -- Schluessel des gezeigten Hinweises (nil = keiner)
}

-- ---------------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------------

-- ID des Pseudo-Aussehens "verborgen".
local function HiddenId()
   return T.HIDDEN_ID or 999999
end

-- Kann die ID per TryOn angeprobiert werden? (Zahl, nicht 0, nicht verborgen)
local function Tryable(id)
   return type(id) == "number" and id ~= 0 and id ~= HiddenId()
end

-- Die 14 Server-Slots aufsteigend (entspricht der aufsteigenden Client-ID).
local function ServerOrder()
   if P.order then
      return P.order
   end
   local list = {}
   local defs = T.Slots.LIST
   for i = 1, #defs do
      list[#list + 1] = defs[i].server
   end
   tsort(list)
   P.order = list
   return list
end

-- Bearbeiteter Slot: vom Fenster gemeldet, sonst Window.currentSlot.
local function FocusSlot()
   if P.focusSlot ~= nil then
      return P.focusSlot
   end
   local W = T.UI and T.UI.Window
   if W and type(W.currentSlot) == "number" then
      return W.currentSlot
   end
   return nil
end

-- Ist der Container sichtbar? (IsVisible liefert 1 oder nil)
local function Visible()
   return P.frame ~= nil and P.frame:IsVisible() and true or false
end

-- Plant ein entprelltes Ankleiden (Preview.Refresh).
local function ScheduleRefresh()
   T.Util.Debounce(KEY_REFRESH, REFRESH_DELAY, function()
      Preview.Refresh()
   end)
end

-- Aktuelle Drehung: GetFacing, sonst der gemerkte Wert.
local function CurrentFacing()
   local f = P.model:GetFacing()
   if type(f) ~= "number" then
      f = P.facing
   end
   return f
end

-- ---------------------------------------------------------------------------
-- Kamera
-- ---------------------------------------------------------------------------

-- Dreht das Modell um delta (Bogenmass); eine manuelle Drehung beendet die
-- Fokus-Drehung (kein Zurueckschnappen).
local function Turn(delta)
   local f = CurrentFacing() + delta
   P.model:SetFacing(f)
   P.facing = f
   P.focusTurned = false
   P.savedFacing = nil
end

-- Verschiebt das Modell in der Bildebene (um die Ausgangslage begrenzt).
local function Pan(dx, dy)
   local z, x, y = P.model:GetPosition()
   if type(z) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
      return
   end
   x, y = x + dx, y + dy
   local b = P.base
   if b then
      x = max(b[2] - PAN_LIMIT, min(b[2] + PAN_LIMIT, x))
      y = max(b[3] - PAN_LIMIT, min(b[3] + PAN_LIMIT, y))
   end
   P.model:SetPosition(z, x, y)
end

-- Zoomt um delta (Tiefe Z), begrenzt um die Ausgangstiefe.
local function Zoom(delta)
   local z, x, y = P.model:GetPosition()
   if type(z) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
      return
   end
   z = z + delta
   local b = P.base
   if b then
      z = max(b[1] - ZOOM_OUT, min(b[1] + ZOOM_IN, z))
   end
   P.model:SetPosition(z, x, y)
end

-- Drehung des Umhang-Fokus: Cameras.Describe("BACK") liefert die alte Kamera.
local function BackRotation()
   local C = T.UI.Cameras
   if C and C.Describe then
      local rot = C.Describe("BACK", nil, nil, 0, 0, 0)
      if type(rot) == "number" then
         return rot
      end
   end
   return 3.2
end

-- Stellt die Ansicht ein: SetRotation(rotation) und danach SetFacing(facing).
-- Das Paar ist unabhaengig davon richtig, ob die Engine beide Werte als ein
-- Winkel fuehrt (der zweite Aufruf gewinnt) oder als getrennte Anteile
-- (Summe): facing ist stets der Wert, den GetFacing() geliefert hat.
local function SetView(rotation, facing)
   local model = P.model
   P.rotation = rotation
   model:SetRotation(rotation)
   model:SetFacing(facing)
   P.facing = facing
end

-- Fokus-Kamera: der Umhang wird von hinten gezeigt (SetRotation wie bei den
-- Zellenmodellen, Cameras: BACK), jeder andere Platz holt die vorherige Ansicht
-- zurueck (nur wenn nicht von Hand gedreht wurde).
local function FocusCamera(slot)
   if not Preview.autoFocus or not P.built then
      return
   end
   local model = P.model
   if slot == SLOT_BACK and not P.focusTurned then
      P.savedFacing = CurrentFacing()
      local rot = BackRotation()
      P.rotation = rot
      model:SetRotation(rot)
      local f = model:GetFacing()
      if type(f) == "number" then
         P.facing = f
      end
      P.focusTurned = true
   elseif slot ~= SLOT_BACK and P.focusTurned then
      SetView(START_ROTATION, P.savedFacing or P.startFacing)
      P.focusTurned = false
      P.savedFacing = nil
   end
end

-- Mausdruck auf dem Modell: Ziehen beginnen (OnUpdate nur waehrend des Haltens).
-- Sicherheitsnetz: ging das OnMouseUp verloren (Taste ausserhalb losgelassen,
-- Fenster verdeckt), endet das Ziehen, sobald die Taste nicht mehr gedrueckt ist.
local function OnModelMouseDown(self, button)
   -- jeder Druck aufs Modell nimmt dem Suchfeld der Filterleiste den
   -- Tastaturfokus (Leiste spaet gebunden: sie wird nach der Vorschau geladen)
   local fb = T.UI and T.UI.FilterBar
   if fb and fb.ReleaseFocus then
      fb.ReleaseFocus()
   end
   if button ~= "LeftButton" and button ~= "RightButton" then
      return
   end
   local x, y = GetCursorPosition()
   P.drag = { button = button, x = x, y = y }
   self:SetScript("OnUpdate", function()
      local d = P.drag
      if not d then
         self:SetScript("OnUpdate", nil)
         return
      end
      if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown(d.button) then
         P.drag = nil
         self:SetScript("OnUpdate", nil)
         return
      end
      local cx, cy = GetCursorPosition()
      local dx, dy = cx - d.x, cy - d.y
      d.x, d.y = cx, cy
      if d.button == "LeftButton" then
         if dx ~= 0 then
            Turn(dx / ROTATE_DIV)
         end
      elseif dx ~= 0 or dy ~= 0 then
         Pan(dx / PAN_DIV, dy / PAN_DIV)
      end
   end)
end

-- Maus losgelassen / Modell versteckt: Ziehen beenden, OnUpdate entfernen.
local function OnModelMouseUp(self)
   P.drag = nil
   self:SetScript("OnUpdate", nil)
end

-- Mausrad: zoomen.
local function OnModelWheel(_, delta)
   if type(delta) ~= "number" or delta == 0 then
      return
   end
   Zoom(delta > 0 and ZOOM_STEP or -ZOOM_STEP)
end

-- Beginnt das Drehen mit einem Drehknopf (sofort ein kleiner Schritt, danach
-- stetig, solange die Maustaste gehalten wird).
local function StartTurn(dir)
   P.turnDir = dir
   Turn(dir * TURN_STEP)
   if P.turner then
      P.turner:Show()
   end
end

-- Beendet das Drehen (Maus losgelassen, Zeiger verlassen, Knopf versteckt).
local function StopTurn()
   P.turnDir = nil
   if P.turner then
      P.turner:Hide()
   end
end

-- OnUpdate des Drehtreibers (laeuft nur, solange ein Knopf gehalten wird).
local function TurnUpdate(self, elapsed)
   local dir = P.turnDir
   if not dir then
      self:Hide()
      return
   end
   Turn(dir * TURN_RATE * (elapsed or 0))
end

-- Stellt Drehung und Position auf die Ausgangsansicht zurueck.
function Preview.ResetCamera()
   if not P.model then
      return
   end
   P.focusTurned = false
   P.savedFacing = nil
   if P.built then
      SetView(START_ROTATION, P.startFacing)
      local b = P.base
      if b then
         P.model:SetPosition(b[1], b[2], b[3])
      end
   else
      P.rotation, P.facing = START_ROTATION, P.startFacing
   end
end

-- Fokus-Slot melden (Window.SelectSlot): steuert die Fernkampf-Regel und dreht
-- fuer den Umhang das Modell nach hinten. nil = nichts bearbeitet.
function Preview.SetFocusSlot(slot)
   if type(slot) ~= "number" then
      slot = nil
   end
   local changed = (slot ~= P.focusSlot)
   P.focusSlot = slot
   if not P.model then
      return
   end
   FocusCamera(slot)
   if changed then
      ScheduleRefresh()
   end
end

-- ---------------------------------------------------------------------------
-- Modell neu laden und ankleiden
-- ---------------------------------------------------------------------------

-- Text des Hinweises zum Schluessel (zur Anzeigezeit aufgeloest: sprachfest).
local function NoteText(key)
   local L = T.L
   if key == "PREVIEW_OFFHAND_NOTE_MAINHAND" then
      return L.PREVIEW_OFFHAND_NOTE_MAINHAND
   end
   return L.PREVIEW_OFFHAND_NOTE
end

-- Zeigt den Hinweis zur Nebenhand (key = "PREVIEW_OFFHAND_NOTE" |
-- "PREVIEW_OFFHAND_NOTE_MAINHAND") oder verbirgt ihn (key = nil).
local function ShowNote(key)
   if not P.note then
      return
   end
   P.noteKey = key
   if key then
      P.note:SetText(NoteText(key))
      P.note:Show()
   else
      P.note:Hide()
   end
end

-- SetUnit("player"): setzt Facing/Position zurueck, daher vorher merken und
-- danach wiederherstellen. Beim ersten Mal gilt wie im alten Addon nur die
-- Startrotation SetRotation(0.61) (SPEC 9.1); der Ausgangswert von GetFacing()
-- danach ist das Ziel von "Ansicht zuruecksetzen".
local function RebuildModel()
   local model = P.model
   local State = T.State
   local first = not P.built

   local facing = model:GetFacing()
   if type(facing) ~= "number" then
      facing = P.facing
   end
   local z, x, y = model:GetPosition()

   model:SetUnit("player")

   if first then
      P.rotation = START_ROTATION
      model:SetRotation(START_ROTATION)
      local f = model:GetFacing()
      P.facing = (type(f) == "number") and f or 0
      P.startFacing = P.facing
   else
      -- SetUnit kann die Ansicht verwerfen: Rotation und Drehung wiederherstellen
      SetView(P.rotation, facing)
   end

   local bz, bx, by = model:GetPosition()
   if type(bz) == "number" and type(bx) == "number" and type(by) == "number" then
      P.base = { bz, bx, by }
   end
   if not first and type(z) == "number" and type(x) == "number" and type(y) == "number" then
      model:SetPosition(z, x, y)
   end

   P.built = true
   P.needsRebuild = false
   P.sizeDirty = false
   P.undressed = false
   P.tried = {}
   P.offhandSkipped = false
   P.offhandInMain = false

   -- Momentaufnahme: was das Modell nach SetUnit zeigt (echte Ausruestung und
   -- der bei SetUnit angewendete Zustand)
   P.builtBase, P.builtEquip = {}, {}
   local order = ServerOrder()
   for i = 1, #order do
      local slot = order[i]
      local eq = State.Equipped(slot)
      P.builtBase[slot] = State.Baseline(slot)
      P.builtEquip[slot] = eq and eq.id or 0
   end

   if first then
      FocusCamera(P.focusSlot)
   end
end

-- Zeigt die Vorschau eine Nebenhandwaffe ohne Nebenhandtyp (einhaendig u. ae.)
-- in der Haupthand? Nur bei Bearbeitung der Nebenhand UND ausstehender Auswahl:
-- eine bereits angewendete Waffe zeichnet SetUnit ohnehin richtig links, ein
-- TryOn wuerde dann die echte Haupthand ersetzen.
local function OffhandInMainWanted(focus)
   return focus == SLOT_OFFHAND and T.State.HasPending(SLOT_OFFHAND)
end

-- Probiert ein Aussehen an (mit den Ausnahmen des alten Codes).
--   covered = true: Fernkampf im Undress-Weg (zuerst angeprobiert, vom
--             Nahkampf verdeckt) -- nicht verfolgt
-- Rueckgabe: true, wenn TryOn gerufen wurde.
local function TryTarget(slot, id, focus, covered)
   if slot == SLOT_RANGED and focus ~= SLOT_RANGED and not covered then
      return false      -- Fernkampf verdeckt sonst die Nahkampfwaffe
   end
   local Items = T.Items
   local info = Items.Info(id)
   if not info then
      Items.Request(id)
      P.waiting[id] = true
      return false     -- nicht gecacht: nie an TryOn
   end
   local inMain = false
   if slot == SLOT_OFFHAND and not OFFHAND_OK[info.equipLoc or ""] then
      if not OffhandInMainWanted(focus) then
         P.offhandSkipped = true
         return false  -- einhaendige Waffe landete rechts und ersetzte die Haupthand
      end
      inMain = true    -- Nebenhand wird bearbeitet: Kandidat steht in der Haupthand
   end
   P.model:TryOn(id)
   if not covered then
      P.tried[slot] = id
      if slot == SLOT_OFFHAND then
         P.offhandInMain = inMain
      end
   end
   return true
end

-- Weicht das Wunschaussehen von dem ab, was das Modell zeigt?
-- Verfolgt (tried): Vergleich mit der letzten Anprobe. Sonst gilt: das Modell
-- traegt nach SetUnit die echte Ausruestung; angewendete Transmogs gelten als
-- unsicher (das Modell kann nachhinken) und werden einmal angeprobiert.
local function Differs(slot, target, equippedId)
   local tried = P.tried[slot]
   if tried ~= nil then
      return target ~= tried
   end
   local base = T.State.Baseline(slot)
   return target ~= equippedId or (base ~= 0 and base ~= target) or base ~= P.builtBase[slot]
end

-- Bei Bearbeitung des Fernkampfs liegt dessen Look zuletzt in der Hand: wurde in
-- diesem Durchlauf die Haupthand neu angeprobiert, kommt er erneut (nur wenn er
-- schon angeprobiert ist; ein unveraenderter Fernkampf bleibt unsichtbar).
local function RetryRanged(handTried, target, focus)
   if not handTried or focus ~= SLOT_RANGED then
      return
   end
   local t = target[SLOT_RANGED]
   if Tryable(t) and P.tried[SLOT_RANGED] == t then
      P.model:TryOn(t)
   end
end

-- Bei Bearbeitung der Nebenhand liegt deren Waffe zuletzt in der Haupthand: wurde
-- in diesem Durchlauf die Haupthand neu angeprobiert (und die Nebenhand nicht),
-- kommt die Waffe erneut (zuletzt angeprobiert gewinnt).
local function RetryOffhand(handTried, offTried, target, focus)
   if not handTried or offTried or focus ~= SLOT_OFFHAND or not P.offhandInMain then
      return
   end
   local t = target[SLOT_OFFHAND]
   if Tryable(t) and P.tried[SLOT_OFFHAND] == t then
      P.model:TryOn(t)
   end
end

-- Zeigt das Modell auf diesem Platz eine Anprobe, die das Ziel nicht mehr
-- wuenscht oder nicht darstellen kann? Dann hilft nur SetUnit (bzw. Undress).
--   * Ziel verborgen/leer (nicht anprobierbar)
--   * Nebenhand: das neue Ziel ist eine Waffe, die nicht links gezeigt wird (und
--     nicht in der Haupthand gezeigt werden soll); der zuvor angeprobierte Schild
--     stuende sonst als scheinbare Auswahl da. Das gilt auch umgekehrt: liegt die
--     Nebenhandwaffe in der Haupthand, ersetzt nur eine weitere gezeigte Waffe sie
--     (zweite Anprobe); Schild/Original/verworfen oder ein verlassener Fokus
--     (Waffe gar nicht mehr gezeigt) brauchen SetUnit, damit die Haupthand
--     zurueckkehrt.
local function Stale(slot, target, focus)
   if P.tried[slot] == nil then
      return false
   end
   if not Tryable(target) then
      return true
   end
   if slot == SLOT_OFFHAND then
      local info = T.Items.Info(target)
      local weapon = info ~= nil and not OFFHAND_OK[info.equipLoc or ""]
      if P.offhandInMain then
         return not (weapon and OffhandInMainWanted(focus))
      end
      return weapon
   end
   return false
end

-- Kleidet das Modell gemaess State an (Algorithmus siehe Kopfkommentar).
-- pass 0: darf neu aufbauen (SetUnit); pass 1: direkt nach dem Neuaufbau.
local function DressModel(pass)
   local State = T.State
   local model = P.model
   local hidden = HiddenId()
   local order = ServerOrder()
   local focus = FocusSlot()

   P.waiting = {}
   P.offhandSkipped = false

   -- 1. Ziele: effektives Aussehen je Platz
   local target, equipped = {}, {}
   local hiddenNew, equipChanged = false, false
   for i = 1, #order do
      local slot = order[i]
      local st = State.SlotState(slot)
      local eq = State.Equipped(slot)
      local id = eq and eq.id or 0
      equipped[slot] = id
      local eff = 0
      if st == "READY" then
         local want = State.Wanted(slot)
         eff = (want ~= 0) and want or id
         if want == hidden and State.Baseline(slot) ~= hidden then
            hiddenNew = true
         end
      elseif st == "NEVER" then
         eff = id
      end
      target[slot] = eff
      if P.builtEquip[slot] ~= id then
         equipChanged = true
      end
   end

   if not hiddenNew then
      -- 2a. Normalweg: SetUnit-Zustand + Unterschiede per TryOn
      local redo = P.undressed or equipChanged
      if not redo then
         for i = 1, #order do
            local slot = order[i]
            local t = target[slot]
            if Stale(slot, t, focus) then
               redo = true         -- Platz soll verborgen/leer sein (oder Nebenhandwaffe), zeigt aber etwas
               break
            elseif P.tried[slot] == nil and not Tryable(t)
               and State.Baseline(slot) ~= P.builtBase[slot] then
               redo = true         -- Transmog entfernt/verborgen, Modell zeigt noch den alten
               break
            end
         end
         if not redo and P.tried[SLOT_RANGED] ~= nil and focus ~= SLOT_RANGED then
            redo = true            -- Fernkampf bearbeitet und verlassen: Nahkampf wieder frei
         end
      end
      if redo and pass == 0 then
         RebuildModel()
         return DressModel(1)
      end

      local handTried, offTried = false, false
      for i = 1, #order do
         local slot = order[i]
         local t = target[slot]
         if Tryable(t) and Differs(slot, t, equipped[slot]) then
            if TryTarget(slot, t, focus, false) then
               if slot == SLOT_MAINHAND then
                  handTried = true
               elseif slot == SLOT_OFFHAND then
                  offTried = true
               end
            end
         end
      end
      RetryRanged(handTried, target, focus)
      RetryOffhand(handTried, offTried, target, focus)
   else
      -- 2b. Undress-Weg: ein neu gewaehltes "Verborgen" braucht ein leeres Modell
      local full = (not P.undressed) or equipChanged
      if not full then
         for i = 1, #order do
            local slot = order[i]
            if Stale(slot, target[slot], focus) then
               full = true
               break
            end
         end
         if not full and P.tried[SLOT_RANGED] ~= nil and focus ~= SLOT_RANGED then
            full = true
         end
      end

      if full then
         model:Undress()
         P.undressed = true
         P.tried = {}
         P.offhandInMain = false
         if equipChanged then
            -- Momentaufnahme der Ausruestung nachziehen (Undress leert ohnehin alles)
            for i = 1, #order do
               P.builtEquip[order[i]] = equipped[order[i]]
            end
         end

         -- Fernkampf zuerst (Nahkampf gewinnt), bei Bearbeitung zuletzt
         local seq = {}
         for i = 1, #order do
            if order[i] ~= SLOT_RANGED then
               seq[#seq + 1] = order[i]
            end
         end
         if focus == SLOT_RANGED then
            seq[#seq + 1] = SLOT_RANGED
         else
            tinsert(seq, 1, SLOT_RANGED)
         end

         for i = 1, #seq do
            local slot = seq[i]
            local t = target[slot]
            if Tryable(t) then
               TryTarget(slot, t, focus, slot == SLOT_RANGED and focus ~= SLOT_RANGED)
            end
         end
      else
         local handTried, offTried = false, false
         for i = 1, #order do
            local slot = order[i]
            local t = target[slot]
            if Tryable(t) and P.tried[slot] ~= t then
               if TryTarget(slot, t, focus, false) then
                  if slot == SLOT_MAINHAND then
                     handTried = true
                  elseif slot == SLOT_OFFHAND then
                     offTried = true
                  end
               end
            end
         end
         RetryRanged(handTried, target, focus)
         RetryOffhand(handTried, offTried, target, focus)
      end
   end

   -- 3. Hinweis zur Nebenhandwaffe (nur einer; "in der Haupthand" gewinnt):
   --    sie steht in der Haupthand, oder sie kann nicht gezeigt werden
   local noteKey = nil
   if P.offhandInMain then
      noteKey = "PREVIEW_OFFHAND_NOTE_MAINHAND"
   elseif P.offhandSkipped and State.HasPending(SLOT_OFFHAND) then
      noteKey = "PREVIEW_OFFHAND_NOTE"
   end
   ShowNote(noteKey)
end

-- Kleidet das Modell gemaess State.Wanted an (nur Unterschiede). Unsichtbar:
-- nur merken (OnShow holt nach). Noch nie aufgebaut: erst SetUnit.
function Preview.Refresh()
   if not P.model then
      return
   end
   if not Visible() then
      P.dirty = true
      return
   end
   P.dirty = false
   if not P.built or P.needsRebuild then
      RebuildModel()
      DressModel(1)
      return
   end
   DressModel(0)
end

-- SetUnit("player") erneut (Facing/Position bleiben), Verfolgung zuruecksetzen,
-- danach ankleiden. Noetig nach Groessen-/Scale-Aenderungen, weil das Modell
-- seine Projektion beim Laden berechnet. Unsichtbar: beim Zeigen nachholen.
function Preview.Rebuild()
   if not P.model then
      return
   end
   if not Visible() then
      P.needsRebuild = true
      P.dirty = true
      return
   end
   P.dirty = false
   RebuildModel()
   DressModel(1)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

-- Nach einer Groessenaenderung zur Ruhe gekommen: Projektion neu berechnen.
local function SizeSettled()
   if P.sizeDirty then
      Preview.Rebuild()
   end
end

-- Passt das Modell (Seitenverhaeltnis 221:362, nur uniform skaliert) mittig in
-- die Flaeche oberhalb der Steuerzeile; Knoepfe sitzen unten.
function Preview.Layout(w, h)
   if not P.frame then
      return
   end
   w = max(tonumber(w) or P.w or DEFAULT_W, MIN_W)
   h = max(tonumber(h) or P.h or DEFAULT_H, MIN_H)
   P.w, P.h = w, h

   local frame = P.frame
   frame:SetWidth(w)
   frame:SetHeight(h)

   local areaH = max(h - CONTROL_H - CONTROL_GAP, 1)
   local view = P.viewport
   view:ClearAllPoints()
   view:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
   view:SetWidth(w)
   view:SetHeight(areaH)

   local f = min((w - 2 * PAD) / BASE_W, (areaH - 2 * PAD) / BASE_H)
   f = max(f, 0.1)
   local mw, mh = BASE_W * f, BASE_H * f
   local model = P.model
   model:ClearAllPoints()
   model:SetPoint("CENTER", view, "CENTER", 0, 0)
   model:SetWidth(mw)
   model:SetHeight(mh)

   P.note:ClearAllPoints()
   P.note:SetPoint("BOTTOM", view, "BOTTOM", 0, 6)
   P.note:SetWidth(max(w - 16, 20))
   P.note:SetHeight(36)

   -- Steuerzeile: "<" links, ">" rechts, Reset in der Mitte
   P.leftButton:ClearAllPoints()
   P.leftButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
   P.rightButton:ClearAllPoints()
   P.rightButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
   P.resetButton:ClearAllPoints()
   P.resetButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
   P.resetButton:SetWidth(max(w - 2 * BUTTON_W - 2 * CONTROL_GAP, 40))

   -- die Projektion gehoert zur Groesse: nach Ruhe neu laden (falls das Fenster
   -- nicht ohnehin Rebuild ruft)
   if P.mw ~= mw or P.mh ~= mh then
      P.mw, P.mh = mw, mh
      if P.built then
         P.sizeDirty = true
         T.Util.Debounce(KEY_SIZE, REBUILD_DELAY, SizeSettled)
      end
   end
end

-- ---------------------------------------------------------------------------
-- Texte
-- ---------------------------------------------------------------------------

-- Setzt die statischen Texte neu (Reset-Knopf, Hinweis); Tooltips entstehen bei Bedarf.
function Preview.ApplyLocale()
   if not P.frame then
      return
   end
   local L = T.L
   P.resetButton:SetLabel(L.PREVIEW_RESET)
   if P.note:IsShown() and P.noteKey then
      P.note:SetText(NoteText(P.noteKey))
   end
end

-- Tooltip des Reset-Knopfs: Wirkung plus Bedienhilfe fuer Maus und Rad.
local function ResetTip(tooltip)
   local L = T.L
   tooltip:AddLine(L.PREVIEW_RESET, 1, 1, 1)
   tooltip:AddLine(L.PREVIEW_RESET_TIP, 0.78, 0.81, 0.86, true)
   tooltip:AddLine(L.PREVIEW_HELP_ROTATE, 0.5, 0.54, 0.6, true)
   tooltip:AddLine(L.PREVIEW_HELP_MOVE, 0.5, 0.54, 0.6, true)
   tooltip:AddLine(L.PREVIEW_HELP_ZOOM, 0.5, 0.54, 0.6, true)
end

-- Tooltip eines Drehknopfs; titleKey ist "left" oder "right".
local function TurnTip(which)
   return function(tooltip)
      local L = T.L
      tooltip:AddLine(which == "left" and L.PREVIEW_ROTATE_LEFT or L.PREVIEW_ROTATE_RIGHT, 1, 1, 1)
      tooltip:AddLine(L.PREVIEW_ROTATE_HOLD, 0.78, 0.81, 0.86, true)
   end
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

-- Erstellt einen Drehknopf (dir = -1 links, +1 rechts).
local function BuildTurnButton(parent, label, dir, which)
   local Skin = T.UI.Skin
   local btn = Skin.Button(parent, BUTTON_W, CONTROL_H, label, nil)
   btn.tip = TurnTip(which)
   btn.tipAnchor = "ANCHOR_TOP"
   btn:HookScript("OnMouseDown", function(_, mouseButton)
      if mouseButton == "LeftButton" and P.model then
         StartTurn(dir)
      end
   end)
   btn:HookScript("OnMouseUp", StopTurn)
   btn:HookScript("OnLeave", StopTurn)
   btn:HookScript("OnHide", StopTurn)
   return btn
end

-- Meldet die Ereignisse an (einmalig, Besitzer = Preview).
local function RegisterEvents()
   local E = T.Events
   if not E or not E.On then
      return
   end
   E.On("WANTED_CHANGED", ScheduleRefresh, Preview)
   E.On("STATUS_CHANGED", ScheduleRefresh, Preview)
   E.On("EQUIPMENT_CHANGED", ScheduleRefresh, Preview)
   -- eine fertige Liste kann ein Aussehen inaktiv machen (Wanted aendert sich)
   E.On("LIST_READY", ScheduleRefresh, Preview)
   E.On("ITEMS_RESOLVED", function()
      -- nur wenn ein zurueckgestellter Gegenstand inzwischen bekannt ist
      for id in pairs(P.waiting) do
         if T.Items.Info(id) then
            ScheduleRefresh()
            return
         end
      end
   end, Preview)
   E.On("LOCALE_CHANGED", function()
      Preview.ApplyLocale()
   end, Preview)
end

-- Erstellt Container, Modell und Steuerzeile. Ein weiteres Create liefert
-- denselben Container.
function Preview.Create(parent)
   if P.frame then
      return P.frame
   end
   local Skin = T.UI.Skin
   local COL = Skin.COL
   local L = T.L

   local frame = CreateFrame("Frame", nil, parent)
   frame:SetWidth(DEFAULT_W)
   frame:SetHeight(DEFAULT_H)
   P.frame = frame

   -- Buehne: dunkle Flaeche mit 1-px-Rand
   local view = CreateFrame("Frame", nil, frame)
   Skin.Backdrop(view, VIEW_BG, COL.border)
   P.viewport = view

   -- Modell (Template: 221x362, Modell-Scale 2.0, Maus an)
   local model = CreateFrame("DressUpModel", nil, view, TEMPLATE)
   model:SetFrameLevel(view:GetFrameLevel() + 1)
   model:EnableMouse(true)
   model:EnableMouseWheel(true)
   model:SetScript("OnMouseDown", OnModelMouseDown)
   model:SetScript("OnMouseUp", OnModelMouseUp)
   model:SetScript("OnMouseWheel", OnModelWheel)
   model:SetScript("OnHide", OnModelMouseUp)
   P.model = model
   Preview.model = model
   Preview.frame = frame

   -- Hinweis zur Nebenhand (dezent, unten in der Buehne, ueber dem Modell)
   local noteHolder = CreateFrame("Frame", nil, view)
   noteHolder:SetAllPoints(view)
   noteHolder:SetFrameLevel(model:GetFrameLevel() + 2)
   noteHolder:EnableMouse(false)
   local note = noteHolder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
   note:SetJustifyH("CENTER")
   note:SetJustifyV("BOTTOM")
   if note.SetNonSpaceWrap then note:SetNonSpaceWrap(true) end
   note:SetText("")
   note:Hide()
   P.note = note

   -- Steuerzeile
   P.leftButton = BuildTurnButton(frame, "<", -1, "left")
   P.rightButton = BuildTurnButton(frame, ">", 1, "right")
   local reset = Skin.Button(frame, 100, CONTROL_H, L.PREVIEW_RESET, function()
      Preview.ResetCamera()
   end)
   reset.tip = ResetTip
   reset.tipAnchor = "ANCHOR_TOP"
   P.resetButton = reset

   -- Treiber fuers gehaltene Drehen: versteckt, bis ein Knopf gedrueckt wird
   local turner = CreateFrame("Frame", nil, frame)
   turner:SetScript("OnUpdate", TurnUpdate)
   turner:Hide()
   P.turner = turner

   -- Methoden auch als Frame-Felder (Doppelpunkt-Aufruf)
   frame.Layout = function(_, w, h) return Preview.Layout(w, h) end
   frame.Refresh = function() return Preview.Refresh() end
   frame.Rebuild = function() return Preview.Rebuild() end
   frame.ResetCamera = function() return Preview.ResetCamera() end
   frame.SetFocusSlot = function(_, slot) return Preview.SetFocusSlot(slot) end
   frame.ApplyLocale = function() return Preview.ApplyLocale() end

   Preview.Layout(DEFAULT_W, DEFAULT_H)

   -- sichtbar werden: Modell frisch laden und ankleiden (wie das alte Addon bei
   -- jedem Oeffnen; faengt Gestaltwechsel, Ausruestung und Projektion ab);
   -- verschwinden: Eingabe beenden, Neuaufbau fuers naechste Zeigen vormerken
   frame:HookScript("OnShow", function()
      Preview.Refresh()
   end)
   frame:HookScript("OnHide", function()
      StopTurn()
      P.drag = nil
      model:SetScript("OnUpdate", nil)
      P.needsRebuild = true
      P.dirty = true
   end)

   RegisterEvents()
   return frame
end
