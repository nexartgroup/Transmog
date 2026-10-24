-- UI\Cameras.lua
-- ---------------------------------------------------------------------------
-- Kameraeinstellungen der Vorschau-Zellen (80x107-DressUpModel, Modell-Scale 4.0
-- aus dem XML-Template TransmogCellModelTemplate).
--
-- Die Zahlen (Verschiebungen und Drehwinkel) stammen 1:1 aus dem alten Addon
-- (ui/appearance_list.lua, renderAvailableTransmogs; mitgeliefert im Servermodul
-- mod-transmog-plus, AGPL-3.0) und wurden dort im laufenden Spiel von Hand
-- abgestimmt. Die Datenstruktur und der gesamte Code hier sind neu geschrieben;
-- nur die Kalibrierwerte sind uebernommen (Herkunft und Lizenz: NOTICE).
-- Sie duerfen NICHT "bereinigt" oder zusammengefasst werden.
-- tests/test_cameras.lua prueft sie gegen handgerechnete Sollwerte (alle
-- Rassen x Slots x Fernkampf-Fall) und die Folge der Modellaufrufe.
--
-- Koordinaten (Benennung wie im alten Code): model:GetPosition() liefert und
-- model:SetPosition(Z, X, Y) erwartet
--    Z = Tiefe (Abstand zur Kamera), X = horizontal, Y = vertikal.
--
-- Ablauf je Zelle (Reihenfolge der Aufrufe exakt wie vorher):
--    SetUnit("player")            -- Aufrufer bzw. Cameras.Dress
--    SetRotation(0.61)            -- Grundrotation
--    GetPosition()                -- Position NACH SetUnit
--    [Rasse: Z/X/Y verschieben]   -- nur Rechnung, kein Modellaufruf
--    [Slot-Block: SetRotation*, Z/X/Y je Rasse verschieben]
--    SetPosition(Z+dz, X+dx, Y+dy)
--    Undress()                    -- nicht bei Hand-Slots
--    TryOn(itemId)                -- nicht bei Verborgen/0/nil
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.UI = T.UI or {}
local Cameras = T.UI.Cameras or {}
T.UI.Cameras = Cameras

-- Grundrotation, die der alte Code vor jedem Slot-Block setzt.
local BASE_ROTATION = 0.61
Cameras.BASE_ROTATION = BASE_ROTATION

-- Fernkampf-Sonderfall: nur INVTYPE_RANGEDRIGHT (Gewehre, Armbrueste und
-- Zauberstaebe liegen in der rechten Hand; Boegen/Wurfwaffen sind
-- INVTYPE_RANGED bzw. INVTYPE_THROWN) dreht das Modell nach links.
local RANGED_RIGHT = "INVTYPE_RANGEDRIGHT"

-- ---------------------------------------------------------------------------
-- Daten
-- ---------------------------------------------------------------------------
-- Verschiebung = { z = dz, x = dx, y = dy }; fehlende Felder bedeuten "keine
-- Aenderung" (es wird dann gar nicht gerechnet, wie im alten Code). Alle
-- Verschiebungen werden ADDIERT; "Z - 3" des alten Codes steht hier als z = -3
-- (IEEE-754: a - b ist exakt a + (-b), das Ergebnis ist bitgleich).

-- Rassen-Grundverschiebung: gilt fuer ALLE Slots und wird VOR dem Slot-Block
-- angewendet. Rassen ohne Eintrag (human, draenei, orc, scourge, bloodelf,
-- tauren) bekommen hier nichts.
local RACE_BASE = {
   nightelf = { z = 3 },
   gnome    = { z = -3, y = 1.5 },
   dwarf    = { y = 1, z = -1 },
   troll    = { z = 2 },
   goblin   = { z = -0.5 },
}

-- Slot-Kameras, Schluessel = T.Slots-Schluessel.
--   rot  = Rotationsschritte in der Reihenfolge der alten SetRotation-Aufrufe
--          (der LETZTE ausgefuehrte Schritt gewinnt). Schritt = { wert }, optional
--          race = "token" (nur diese Rasse) oder ranged = true (nur bei
--          equipLoc == INVTYPE_RANGEDRIGHT). Ohne Schritte bleibt es bei 0.61.
--   race = [rassenToken] = Verschiebung, die der Slot-Block fuer diese Rasse
--          macht (nach der Rassen-Grundverschiebung, vor dem SetPosition).
--   pos  = Verschiebung, die im SetPosition-Aufruf selbst steht
--          (SetPosition(Z + pos.z, X + pos.x, Y + pos.y)).
local SLOTS = {
   HEAD = {
      rot  = { { 0.3, race = "tauren" } },
      race = {
         tauren = { x = -0.2, y = 0.2 },
         goblin = { y = 1.5 },
         dwarf  = { y = 0.5 },
      },
      pos  = { z = 5.8, y = -2.2 },
   },

   SHOULDER = {
      race = {
         dwarf    = { y = -0.2 },
         goblin   = { y = 1.5, z = -0.5 },
         nightelf = { z = -1 },
      },
      pos  = { z = 5.8, x = 0.5, y = -1.7 },
   },

   BACK = {
      rot = { { 3.2 } },
      pos = { z = 3.8, y = -0.7 },
   },

   -- Hemd: wie die Brust, ein Torso-Teil wirkt im selben Abstand am besten.
   -- Tauren bekommt zuerst 0.3 und danach (unbedingt) wieder 0.61.
   SHIRT = {
      rot  = { { 0.3, race = "tauren" }, { 0.61 } },
      race = {
         tauren = { x = -0.2, y = 0.5 },
         goblin = { y = 1.5, z = -0.5 },
      },
      pos  = { z = 5.8, x = 0.1, y = -1.2 },
   },

   -- Wappenrock haengt bis zur Mitte der Oberschenkel, braucht also eine
   -- weitere Aufnahme als die Brust (sonst wird er auf Taillenhoehe beschnitten).
   TABARD = {
      rot  = { { 0.3, race = "tauren" }, { 0.61 } },
      race = {
         tauren = { x = -0.2 },
         goblin = { y = 1.5, z = -0.5 },
         gnome  = { y = -0.7 },
      },
      pos  = { z = 4.2, y = -0.3 },
   },

   CHEST = {
      rot  = { { 0.3, race = "tauren" }, { 0.61 } },
      race = {
         tauren = { x = -0.2, y = 0.5 },
         goblin = { y = 1.5, z = -0.5 },
      },
      pos  = { z = 5.8, x = 0.1, y = -1.2 },
   },

   WRIST = {
      rot  = { { 1.5 } },
      race = {
         gnome  = { y = -1 },
         tauren = { x = -0.2 },
         dwarf  = { x = -0.3, y = -0.4 },
         troll  = { y = 0.6 },
         goblin = { y = 1.5, z = -0.5 },
      },
      pos  = { z = 5.8, x = 0.4, y = -0.3 },
   },

   HANDS = {
      rot  = { { 1.5 } },
      race = {
         gnome  = { y = -0.7 },
         tauren = { x = -0.2 },
         dwarf  = { z = -0.2, x = -0.3, y = -0.1 },
         troll  = { y = 0.9 },
         goblin = { y = 1.5, z = -0.5 },
      },
      pos  = { z = 5.8, x = 0.4, y = -0.3 },
   },

   WAIST = {
      rot  = { { 0.31 } },
      race = {
         gnome  = { y = -0.7 },
         tauren = { z = 1, y = 0.3 },
         goblin = { y = 1.5, z = -0.5 },
      },
      pos  = { z = 5.8, y = -0.4 },
   },

   LEGS = {
      rot  = { { 0.31 } },
      race = {
         gnome = { z = 2, y = -1.5 },
         dwarf = { y = -0.9 },
      },
      pos  = { z = 3.8, y = 0.9 },
   },

   FEET = {
      rot  = { { 0.61 } },
      race = {
         gnome = { z = 2, y = -1.9 },
         dwarf = { y = -0.6 },
      },
      pos  = { z = 4.8, y = 1.5 },
   },

   MAINHAND = {
      rot  = { { 0.61 } },
      race = {
         gnome = { y = -2 },
         dwarf = { y = -1 },
      },
      pos  = { z = 3.8, y = 0.4 },
   },

   OFFHAND = {
      rot  = { { -0.61 } },
      race = {
         gnome = { y = -1.5 },
         dwarf = { y = -1 },
      },
      pos  = { z = 3.8 },
   },

   -- Fernkampf: erst -0.61, bei INVTYPE_RANGEDRIGHT danach 0.61.
   RANGED = {
      rot  = { { -0.61 }, { 0.61, ranged = true } },
      race = {
         troll  = { y = 1.5 },
         goblin = { y = 1 },
         gnome  = { y = -1.5 },
      },
      pos  = { z = 3.8 },
   },
}

-- ---------------------------------------------------------------------------
-- Interpreter
-- ---------------------------------------------------------------------------

-- Addiert eine Verschiebung auf (z, x, y); nil bzw. fehlende Felder aendern nichts.
local function Shift(shift, z, x, y)
   if shift then
      if shift.z then z = z + shift.z end
      if shift.x then x = x + shift.x end
      if shift.y then y = y + shift.y end
   end
   return z, x, y
end

-- Rassen-Token normalisieren: Kleinschreibung; Nicht-Strings ergeben nil.
local function NormRace(race)
   if type(race) == "string" then
      return string.lower(race)
   end
   return nil
end

-- Rechnet die Kamera eines Slots durch; Rueckgabe: rotations, z, x, y, positioned.
--   rotations  Array der SetRotation-Aufrufe NACH der Grundrotation (Reihenfolge)
--   z, x, y    Endposition fuer SetPosition
--   positioned true, wenn der alte Code SetPosition gerufen haette; bei
--              unbekanntem Slot false (z, x, y sind dann die unveraenderten Eingaben)
local function Plan(slotKey, race, equipLoc, z, x, y)
   local rotations = {}
   local def = slotKey and SLOTS[slotKey]
   if not def then
      return rotations, z, x, y, false
   end

   -- 1. Rassen-Grundverschiebung (vor jedem Slot-Block)
   if race then
      z, x, y = Shift(RACE_BASE[race], z, x, y)
   end

   -- 2. Slot-Block: rassenspezifische Verschiebung ...
   if race and def.race then
      z, x, y = Shift(def.race[race], z, x, y)
   end

   -- ... und die SetRotation-Aufrufe in ihrer Reihenfolge
   local steps = def.rot
   if steps then
      for i = 1, #steps do
         local step = steps[i]
         local raceOk = (step.race == nil) or (step.race == race)
         local rangedOk = (not step.ranged) or (equipLoc == RANGED_RIGHT)
         if raceOk and rangedOk then
            rotations[#rotations + 1] = step[1]
         end
      end
   end

   -- 3. Endposition: SetPosition(Z + dz, X + dx, Y + dy)
   z, x, y = Shift(def.pos, z, x, y)
   return rotations, z, x, y, true
end

-- Loest eine Slot-Angabe auf; Rueckgabe: slotKey|nil, isHand (bool).
-- slotDef = Eintrag aus T.Slots ({key=, hand=}) oder reiner Schluessel-String.
local function ResolveSlot(slotDef)
   if type(slotDef) == "string" then
      return slotDef, (slotDef == "MAINHAND" or slotDef == "OFFHAND")
   end
   if type(slotDef) == "table" then
      return slotDef.key, (slotDef.hand and true or false)
   end
   return nil, false
end

-- Liefert true, wenn der Gegenstand anprobiert werden soll (nicht nil, 0, Verborgen).
local function IsTryable(itemId)
   if itemId == nil or itemId == false then
      return false
   end
   local n = tonumber(itemId)
   if n and (n == 0 or n == (T.HIDDEN_ID or 999999)) then
      return false
   end
   return true
end

-- ---------------------------------------------------------------------------
-- Oeffentliche API
-- ---------------------------------------------------------------------------

-- Rechnet die Kamera ohne Modell; Rueckgabe: rotation, z', x', y', positioned.
--   rotation   letztes SetRotation; z', x', y' = Endposition (SetPosition-Argumente)
--   positioned false = der alte Code haette SetPosition nicht gerufen (unbekannter Slot)
-- z/x/y sind die Werte aus model:GetPosition() nach SetUnit (nil zaehlt als 0);
-- race ist ein Token ("tauren", Gross-/Kleinschreibung egal), nil = keine Anpassung.
function Cameras.Describe(slotKey, race, equipLoc, z, x, y)
   local rotations, nz, nx, ny, positioned =
      Plan(slotKey, NormRace(race), equipLoc, z or 0, x or 0, y or 0)
   return rotations[#rotations] or BASE_ROTATION, nz, nx, ny, positioned
end

-- Setzt Rotation und Position eines Zellenmodells; Rueckgabe: true, wenn SetPosition gerufen wurde.
-- SetUnit("player") muss der Aufrufer vorher gerufen haben. Ohne race gilt T.race.
function Cameras.Apply(model, slotKey, race, equipLoc)
   if not model then
      return false
   end
   model:SetRotation(BASE_ROTATION)
   local z, x, y = model:GetPosition()
   local rotations, nz, nx, ny, positioned =
      Plan(slotKey, NormRace(race or T.race), equipLoc, z or 0, x or 0, y or 0)
   for i = 1, #rotations do
      model:SetRotation(rotations[i])
   end
   if positioned then
      model:SetPosition(nz, nx, ny)
   end
   return positioned
end

-- Kleidet ein Zellenmodell an (SetUnit, Kamera, ggf. Undress, TryOn); keine Rueckgabe.
-- slotDef = Eintrag aus T.Slots (oder reiner Schluessel); Undress nur bei Nicht-Hand-
-- Slots; TryOn nicht bei nil/0/Verborgen. race optional (sonst T.race); equipLoc
-- optional (beim Fernkampf-Slot sonst per GetItemInfo aus dem Cache ermittelt).
function Cameras.Dress(model, slotDef, itemId, equipLoc, race)
   if not model then
      return
   end
   local slotKey, isHand = ResolveSlot(slotDef)

   -- Fernkampf haengt vom Gegenstandstyp ab; fehlt equipLoc, aus dem Cache holen.
   if equipLoc == nil and slotKey == "RANGED" and IsTryable(itemId)
      and type(GetItemInfo) == "function" then
      local _, _, _, _, _, _, _, _, loc = GetItemInfo(itemId)
      equipLoc = loc
   end

   model:SetUnit("player")
   Cameras.Apply(model, slotKey, race, equipLoc)

   -- Hand-Slots behalten die echte Ausruestung: Undress() leert BEIDE Haende
   -- und eine danach anprobierte Waffe landet immer rechts.
   if not isHand then
      model:Undress()
   end

   if IsTryable(itemId) then
      model:TryOn(itemId)
   end
end
