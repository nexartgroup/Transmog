-- tests/test_cameras.lua
-- ---------------------------------------------------------------------------
-- Tests fuer UI/Cameras.lua (T.UI.Cameras): Kameras der Vorschau-Zellen.
--
-- Zwei Beweisketten, bewusst unabhaengig voneinander:
--
--  A. HANDGERECHNETE Sollwerte (Abschnitt "Sollwerte von Hand"): fuer 34
--     Rasse-x-Slot-Kombinationen (alle 14 Slots, alle 11 Rassen) und acht
--     weitere mit von null verschiedener Ausgangsposition wurde die Kameralogik
--     der Vorgaenger-Fassung des Addons von Hand durchgerechnet und das Ergebnis
--     als Zahl bzw. Aufrufprotokoll hingeschrieben. Die Zahlen stehen woertlich im
--     Test; die Tabellen in Cameras.lua sind daran nicht beteiligt.
--
--  B. AUFRUFREIHENFOLGE von Cameras.Dress auf dem aufzeichnenden Modell der
--     Attrappe (DressUpModel mit TransmogCellModelTemplate): SetUnit,
--     SetRotation(0.61), [Slot-Rotationen], SetPosition, Undress (nicht bei
--     Hand-Slots), TryOn (nicht bei nil/0/Verborgen). Dazu die Selbstkonsistenz:
--     Dress (Aufrufe am Modell) und Describe (reine Rechnung) liefern fuer alle
--     14 Slots x Rassen x equipLoc x Ausgangspositionen denselben Endzustand.
--
--  (Eine woertliche Kopie des Codes der Vorgaenger-Fassung ist bewusst nicht
--  Teil des Repositories: nur die Zahlen der Kalibrierung stammen von dort,
--  siehe NOTICE und docs/MANUAL.de.md, Abschnitt 11.)
--
-- Rechenhinweis: Das Modell liefert nach SetUnit die Position (Z, X, Y) =
-- (GetPosition); die Logik verschiebt Z/X/Y je Rasse und je Slot und ruft
-- SetPosition(Z + dz, X + dx, Y + dy).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Der Test
-- ---------------------------------------------------------------------------

return function(H)
   local M = H.mock

   local SLOT_KEYS = {
      "HEAD", "SHOULDER", "BACK", "CHEST", "SHIRT", "TABARD", "WRIST",
      "HANDS", "WAIST", "LEGS", "FEET", "MAINHAND", "OFFHAND", "RANGED",
   }

   local RACES = {
      "human", "dwarf", "nightelf", "gnome", "draenei", "orc",
      "scourge", "tauren", "troll", "bloodelf", "goblin",
   }

   -- Tokens, die der alte Code nicht kennt (keine Anpassung), und leer
   local EXTRA_RACES = { "undead", "worgen", "" }

   -- false steht fuer nil (die Tabelle darf kein Loch haben)
   local EQUIP_LOCS = { false, "INVTYPE_RANGEDRIGHT", "INVTYPE_RANGED", "INVTYPE_THROWN" }

   local POSITIONS = {
      { 0, 0, 0 },
      { 1, 2, 3 },
      { -4.5, 0.25, 7 },
   }

   local HAND_SLOTS = { MAINHAND = true, OFFHAND = true }

   -- Cameras und Slots laden (Init liefert T.race/T.HIDDEN_ID)
   local function boot()
      H.install()
      M.LoadFiles({ "Core/Init.lua", "Core/Slots.lua", "UI/Cameras.lua" })
      local T = rawget(_G, "Transmog")
      return T, T.UI.Cameras
   end

   -- Zellenmodell der strengen Attrappe: zeichnet SetUnit/SetRotation/SetPosition/
   -- Undress/TryOn mit Argumenten auf (view.log() = "SetUnit(player) ...").
   local function newCellModel()
      local f = CreateFrame("DressUpModel", nil, UIParent, "TransmogCellModelTemplate")
      return f, M.Model(f)
   end

   -- Kleines Modell-Double mit frei waehlbarer Ausgangsposition; protokolliert auch
   -- GetPosition. Eintrag: { name, a, b, c }.
   local function newDouble(z, x, y)
      local m = { trace = {} }
      local function rec(...) m.trace[#m.trace + 1] = { ... } end
      function m:SetUnit(u) rec("SetUnit", u) end
      function m:SetRotation(r) rec("SetRotation", r) end
      function m:GetPosition() rec("GetPosition"); return z, x, y end
      function m:SetPosition(a, b, c) rec("SetPosition", a, b, c) end
      function m:Undress() rec("Undress") end
      function m:TryOn(id) rec("TryOn", id) end
      return m
   end

   local function traceNames(m)
      local t = {}
      for i, c in ipairs(m.trace) do t[i] = c[1] end
      return table.concat(t, ",")
   end

   -- Letzte Rotation und letzte Position eines Protokolls (nil, wenn nie gerufen)
   local function finalState(trace)
      local rot, pos
      for _, c in ipairs(trace) do
         if c[1] == "SetRotation" then rot = c[2] end
         if c[1] == "SetPosition" then pos = { c[2], c[3], c[4] } end
      end
      return rot, pos
   end

   -- ======================================================================
   H.section("Voraussetzungen")
   -- ======================================================================

   H.test("Zellen-Template ist 80x107 mit Modell-Scale 4.0 (Basis der Kalibrierung)", function()
      boot()
      local f = CreateFrame("DressUpModel", nil, UIParent, "TransmogCellModelTemplate")
      H.eq(f:GetWidth(), 80)
      H.eq(f:GetHeight(), 107)
      H.eq(f:GetModelScale(), 4.0)
   end)

   H.test("Cameras laedt allein; Oberflaeche und Grundrotation", function()
      H.install()
      M.LoadFiles({ "UI/Cameras.lua" })
      local C = rawget(_G, "Transmog").UI.Cameras
      H.eq(type(C.Apply), "function")
      H.eq(type(C.Dress), "function")
      H.eq(C.BASE_ROTATION, 0.61)
   end)

   H.test("T.Slots hat genau die 14 Kamera-Schluessel; Hand-Flag nur MAINHAND/OFFHAND", function()
      local T, C = boot()
      H.len(T.Slots.LIST, 14)
      for _, def in ipairs(T.Slots.LIST) do
         local _, _, _, _, positioned = C.Describe(def.key, "human", nil, 0, 0, 0)
         H.eq(positioned, true, "Kameraeintrag fuer " .. def.key)
         H.eq(def.hand and true or false, HAND_SLOTS[def.key] and true or false, "hand-Flag " .. def.key)
      end
      for _, key in ipairs(SLOT_KEYS) do
         H.truthy(T.Slots.BY_KEY[key], "Slot " .. key)
      end
   end)

   -- ======================================================================
   H.section("Sollwerte von Hand (aus der Kameralogik der Vorgaenger-Fassung durchgerechnet)")
   -- ======================================================================

   -- { Rasse, Slot, Gegenstand, equipLoc, erwartetes Aufrufprotokoll }
   -- Ausgangsposition des Modells nach SetUnit: (0, 0, 0). Rechnung je Zeile
   -- (Z = Tiefe = erstes Argument von SetPosition, X, Y):
   --   Rassen-Grundverschiebung -> Slot-Rasse -> SetPosition(Z+a, X+b, Y+c)
   local HAND_CASES = {
      -- Kopf: Zwerg Y+1,Z-1 | Y+0.5 -> (-1+5.8, 0, 1.5-2.2)
      { "human",    "HEAD",     4711, nil, "SetUnit(player) SetRotation(0.61) SetPosition(5.8,0,-2.2) Undress() TryOn(4711)" },
      { "tauren",   "HEAD",     4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.3) SetPosition(5.8,-0.2,-2) Undress() TryOn(4711)" },
      { "dwarf",    "HEAD",     4711, nil, "SetUnit(player) SetRotation(0.61) SetPosition(4.8,0,-0.7) Undress() TryOn(4711)" },
      -- Schulter: Nachtelf Z+3 | Z-1 -> 3-1+5.8 = 7.8; Goblin Z-0.5 | Y+1.5,Z-0.5
      { "nightelf", "SHOULDER", 4711, nil, "SetUnit(player) SetRotation(0.61) SetPosition(7.8,0.5,-1.7) Undress() TryOn(4711)" },
      { "goblin",   "SHOULDER", 4711, nil, "SetUnit(player) SetRotation(0.61) SetPosition(4.8,0.5,-0.2) Undress() TryOn(4711)" },
      -- Ruecken: Rotation 3.2, keine Rassenanpassung ausser der Grundverschiebung
      { "human",    "BACK",     4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(3.2) SetPosition(3.8,0,-0.7) Undress() TryOn(4711)" },
      -- Hemd: bedingt 0.3 (Taure), dann UNBEDINGT 0.61
      { "human",    "SHIRT",    4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(5.8,0.1,-1.2) Undress() TryOn(4711)" },
      { "tauren",   "SHIRT",    4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.3) SetRotation(0.61) SetPosition(5.8,-0.1,-0.7) Undress() TryOn(4711)" },
      -- Wappenrock: Gnom Z-3,Y+1.5 | Y-0.7 -> (-3+4.2, 0, 1.5-0.7-0.3)
      { "gnome",    "TABARD",   4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(1.2,0,0.5) Undress() TryOn(4711)" },
      { "tauren",   "TABARD",   4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.3) SetRotation(0.61) SetPosition(4.2,-0.2,-0.3) Undress() TryOn(4711)" },
      -- Brust: wie Hemd, Goblin Y+1.5,Z-0.5 zusaetzlich zur Grundverschiebung
      { "tauren",   "CHEST",    4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.3) SetRotation(0.61) SetPosition(5.8,-0.1,-0.7) Undress() TryOn(4711)" },
      { "goblin",   "CHEST",    4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(4.8,0.1,0.3) Undress() TryOn(4711)" },
      -- Handgelenk: Rotation 1.5 (vor den Rassenanpassungen)
      { "goblin",   "WRIST",    4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(1.5) SetPosition(4.8,0.4,1.2) Undress() TryOn(4711)" },
      { "dwarf",    "WRIST",    4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(1.5) SetPosition(4.8,0.1,0.3) Undress() TryOn(4711)" },
      -- Haende: Zwerg Z-1,Y+1 | Z-0.2,X-0.3,Y-0.1 -> (-1.2+5.8, -0.3+0.4, 0.9-0.3)
      { "dwarf",    "HANDS",    4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(1.5) SetPosition(4.6,0.1,0.6) Undress() TryOn(4711)" },
      { "troll",    "HANDS",    4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(1.5) SetPosition(7.8,0.4,0.6) Undress() TryOn(4711)" },
      -- Taille: Rotation 0.31; Taure Z+1,Y+0.3
      { "tauren",   "WAIST",    4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.31) SetPosition(6.8,0,-0.1) Undress() TryOn(4711)" },
      -- Beine: Gnom Z-3,Y+1.5 | Z+2,Y-1.5 -> (-1+3.8, 0, 0+0.9)
      { "gnome",    "LEGS",     4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.31) SetPosition(2.8,0,0.9) Undress() TryOn(4711)" },
      { "dwarf",    "LEGS",     4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.31) SetPosition(2.8,0,1) Undress() TryOn(4711)" },
      -- Fuesse: Gnom Z+2,Y-1.9 -> (-3+2+4.8, 0, 1.5-1.9+1.5)
      { "gnome",    "FEET",     4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(3.8,0,1.1) Undress() TryOn(4711)" },
      { "dwarf",    "FEET",     4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(3.8,0,1.9) Undress() TryOn(4711)" },
      { "scourge",  "FEET",     4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(4.8,0,1.5) Undress() TryOn(4711)" },
      -- Haupthand: KEIN Undress (echte Ausruestung bleibt)
      { "human",    "MAINHAND", 4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(3.8,0,0.4) TryOn(4711)" },
      { "gnome",    "MAINHAND", 4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(0.8,0,-0.1) TryOn(4711)" },
      -- Nebenhand: Rotation -0.61, KEIN Undress
      { "dwarf",    "OFFHAND",  4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(-0.61) SetPosition(2.8,0,0) TryOn(4711)" },
      { "gnome",    "OFFHAND",  4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(-0.61) SetPosition(0.8,0,0) TryOn(4711)" },
      -- Fernkampf: -0.61, bei RANGEDRIGHT danach 0.61; Undress wie bei Ruestung
      { "troll",    "RANGED",   4711, "INVTYPE_RANGEDRIGHT", "SetUnit(player) SetRotation(0.61) SetRotation(-0.61) SetRotation(0.61) SetPosition(5.8,0,1.5) Undress() TryOn(4711)" },
      { "troll",    "RANGED",   4711, "INVTYPE_RANGED", "SetUnit(player) SetRotation(0.61) SetRotation(-0.61) SetPosition(5.8,0,1.5) Undress() TryOn(4711)" },
      { "goblin",   "RANGED",   4711, "INVTYPE_THROWN", "SetUnit(player) SetRotation(0.61) SetRotation(-0.61) SetPosition(3.3,0,1) Undress() TryOn(4711)" },
      { "gnome",    "RANGED",   4711, "INVTYPE_RANGEDRIGHT", "SetUnit(player) SetRotation(0.61) SetRotation(-0.61) SetRotation(0.61) SetPosition(0.8,0,0) Undress() TryOn(4711)" },
      { "human",    "RANGED",   4711, nil, "SetUnit(player) SetRotation(0.61) SetRotation(-0.61) SetPosition(3.8,0,0) Undress() TryOn(4711)" },
      -- Verborgen und leer: kein TryOn
      { "draenei",  "CHEST",    999999, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(5.8,0.1,-1.2) Undress()" },
      { "orc",      "HEAD",     0, nil, "SetUnit(player) SetRotation(0.61) SetPosition(5.8,0,-2.2) Undress()" },
      { "bloodelf", "MAINHAND", 999999, nil, "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(3.8,0,0.4)" },
   }

   H.test("Dress: " .. #HAND_CASES .. " von Hand abgeleitete Aufrufprotokolle (alle Slots, alle Rassen)", function()
      local T, C = boot()
      local covered, racesSeen = {}, {}
      for i, c in ipairs(HAND_CASES) do
         local race, slot, itemId, equipLoc, expected = c[1], c[2], c[3], c[4], c[5]
         local model, view = newCellModel()
         C.Dress(model, T.Slots.BY_KEY[slot], itemId, equipLoc, race)
         H.eq(view.log(), expected, "#" .. i .. " " .. race .. "/" .. slot .. "/" .. tostring(equipLoc))
         covered[slot] = true
         racesSeen[race] = true
      end
      for _, key in ipairs(SLOT_KEYS) do
         H.truthy(covered[key], "Slot " .. key .. " abgedeckt")
      end
      for _, race in ipairs(RACES) do
         H.truthy(racesSeen[race], "Rasse " .. race .. " abgedeckt")
      end
   end)

   -- { Rasse, Slot, equipLoc, Rotation, dz, dx, dy }  (Ausgangsposition (1.5, -0.25, 2))
   local OFFSET_CASES = {
      { "nightelf", "SHOULDER", nil, 0.61, 9.3, 0.25, 0.3 },     -- 1.5+3-1+5.8 | -0.25+0.5 | 2-1.7
      { "dwarf",    "HANDS",    nil, 1.5, 6.1, -0.15, 2.6 },     -- 1.5-1-0.2+5.8 | -0.25-0.3+0.4 | 2+1-0.1-0.3
      { "gnome",    "FEET",     nil, 0.61, 5.3, -0.25, 3.1 },    -- 1.5-3+2+4.8 | -0.25 | 2+1.5-1.9+1.5
      { "tauren",   "HEAD",     nil, 0.3, 7.3, -0.45, 0 },       -- 1.5+5.8 | -0.25-0.2 | 2+0.2-2.2
      { "goblin",   "RANGED",   "INVTYPE_THROWN", -0.61, 4.8, -0.25, 3 },   -- 1.5-0.5+3.8 | 2+1
      { "human",    "OFFHAND",  nil, -0.61, 5.3, -0.25, 2 },     -- 1.5+3.8 | 2
      { "troll",    "WRIST",    nil, 1.5, 9.3, 0.15, 2.3 },      -- 1.5+2+5.8 | -0.25+0.4 | 2+0.6-0.3
      { "tauren",   "WAIST",    nil, 0.31, 8.3, -0.25, 2.2 },    -- 1.5+1+5.8 | | 2+0.3-0.4... (siehe unten)
   }
   -- Waist/Tauren: Y = 2 + 0.3 (Taure) - 0.4 = 1.9; Zeile oben korrigieren
   OFFSET_CASES[8][7] = 1.9

   H.test("Describe/Apply: Position wird auf die Modellposition nach SetUnit aufgerechnet (Handwerte)", function()
      local _, C = boot()
      for i, c in ipairs(OFFSET_CASES) do
         local race, slot, loc, erot, ez, ex, ey = c[1], c[2], c[3], c[4], c[5], c[6], c[7]
         local tag = "#" .. i .. " " .. race .. "/" .. slot
         local rot, z, x, y, positioned = C.Describe(slot, race, loc, 1.5, -0.25, 2)
         H.near(rot, erot, 1e-9, tag .. " Rotation")
         H.near(z, ez, 1e-9, tag .. " Z")
         H.near(x, ex, 1e-9, tag .. " X")
         H.near(y, ey, 1e-9, tag .. " Y")
         H.eq(positioned, true, tag .. " positioned")

         -- dasselbe ueber Apply auf dem Modell-Double
         local m = newDouble(1.5, -0.25, 2)
         H.eq(C.Apply(m, slot, race, loc), true)
         local lastRot, pos = finalState(m.trace)
         H.near(lastRot, erot, 1e-9, tag .. " Apply-Rotation")
         H.near(pos[1], ez, 1e-9, tag .. " Apply-Z")
         H.near(pos[2], ex, 1e-9, tag .. " Apply-X")
         H.near(pos[3], ey, 1e-9, tag .. " Apply-Y")
      end
   end)

   -- ======================================================================
   H.section("Aufrufreihenfolge")
   -- ======================================================================

   H.test("Dress: SetUnit, SetRotation(0.61), GetPosition, [Rotationen], SetPosition, Undress, TryOn", function()
      local T, C = boot()
      local m = newDouble(0, 0, 0)
      C.Dress(m, T.Slots.BY_KEY.HEAD, 4711, nil, "human")
      H.eq(traceNames(m), "SetUnit,SetRotation,GetPosition,SetPosition,Undress,TryOn")
      H.deepEq(m.trace[1], { "SetUnit", "player" })
      H.deepEq(m.trace[2], { "SetRotation", 0.61 })
      H.deepEq(m.trace[6], { "TryOn", 4711 })

      m = newDouble(0, 0, 0)
      C.Dress(m, T.Slots.BY_KEY.CHEST, 4711, nil, "tauren")
      H.eq(traceNames(m), "SetUnit,SetRotation,GetPosition,SetRotation,SetRotation,SetPosition,Undress,TryOn")
      H.near(m.trace[4][2], 0.3)
      H.near(m.trace[5][2], 0.61)

      m = newDouble(0, 0, 0)
      C.Dress(m, T.Slots.BY_KEY.MAINHAND, 4711, nil, "human")
      H.eq(traceNames(m), "SetUnit,SetRotation,GetPosition,SetRotation,SetPosition,TryOn", "Hand-Slot ohne Undress")

      m = newDouble(0, 0, 0)
      C.Dress(m, T.Slots.BY_KEY.RANGED, 4711, "INVTYPE_RANGEDRIGHT", "human")
      H.eq(traceNames(m), "SetUnit,SetRotation,GetPosition,SetRotation,SetRotation,SetPosition,Undress,TryOn")
      H.near(m.trace[4][2], -0.61)
      H.near(m.trace[5][2], 0.61)
   end)

   H.test("Dress ruft ausser SetUnit/SetRotation/GetPosition/SetPosition/Undress/TryOn nichts am Modell", function()
      local T, C = boot()
      local model, view = newCellModel()
      for _, key in ipairs(SLOT_KEYS) do
         C.Dress(model, T.Slots.BY_KEY[key], 4711, nil, "gnome")
      end
      local allowed = { SetUnit = true, SetRotation = true, SetPosition = true, Undress = true, TryOn = true }
      for _, name in ipairs(view.names()) do
         H.truthy(allowed[name], "unerwarteter Modellaufruf " .. name)
      end
      H.eq(view.count("SetUnit"), 14, "SetUnit je Aufruf genau einmal")
      H.eq(view.count("SetPosition"), 14)
      H.eq(view.count("Undress"), 12, "Undress bei 12 von 14 Slots (nicht MAINHAND/OFFHAND)")
      H.eq(view.count("TryOn"), 14)
   end)

   H.test("Dress: TryOn nur fuer echte Gegenstaende (nicht nil, 0, Verborgen), ID unveraendert", function()
      local T, C = boot()
      for _, id in ipairs({ 0, 999999 }) do
         local model, view = newCellModel()
         C.Dress(model, T.Slots.BY_KEY.LEGS, id, nil, "human")
         H.eq(view.count("TryOn"), 0, "id " .. id)
         H.eq(view.count("Undress"), 1)
      end
      local model, view = newCellModel()
      C.Dress(model, T.Slots.BY_KEY.LEGS, nil, nil, "human")
      H.eq(view.count("TryOn"), 0, "nil")
      model, view = newCellModel()
      C.Dress(model, T.Slots.BY_KEY.LEGS, 52019, nil, "human")
      H.deepEq(view.last("TryOn"), { "TryOn", 52019 })
      -- Item-Link als String bleibt unveraendert
      model, view = newCellModel()
      C.Dress(model, T.Slots.BY_KEY.LEGS, "item:52019", nil, "human")
      H.deepEq(view.last("TryOn"), { "TryOn", "item:52019" })
      -- eigenes Verborgen-ID ueber T.HIDDEN_ID
      T.HIDDEN_ID = 888888
      model, view = newCellModel()
      C.Dress(model, T.Slots.BY_KEY.LEGS, 888888, nil, "human")
      H.eq(view.count("TryOn"), 0)
   end)

   H.test("Dress: Slot als Definition, als Schluessel-String, unbekannt oder nil", function()
      local T, C = boot()
      local model, view = newCellModel()
      C.Dress(model, T.Slots.BY_KEY.MAINHAND, 4711, nil, "human")
      H.eq(view.count("Undress"), 0)
      model, view = newCellModel()
      C.Dress(model, "OFFHAND", 4711, nil, "human")
      H.eq(view.count("Undress"), 0, "String-Schluessel")
      H.near(view.last("SetRotation")[2], -0.61)
      model, view = newCellModel()
      C.Dress(model, { key = "HEAD", hand = false }, 4711, nil, "human")
      H.eq(view.count("Undress"), 1)
      -- unbekannter Slot / nil: Grundrotation, kein SetPosition (wie der alte Code ohne passenden Block)
      model, view = newCellModel()
      C.Dress(model, "NOPE", 4711, nil, "tauren")
      H.eq(view.log(), "SetUnit(player) SetRotation(0.61) Undress() TryOn(4711)")
      model, view = newCellModel()
      C.Dress(model, nil, 4711, nil, "tauren")
      H.eq(view.log(), "SetUnit(player) SetRotation(0.61) Undress() TryOn(4711)")
   end)

   H.test("Dress: Rasse aus T.race, wenn nicht uebergeben; Gross-/Kleinschreibung egal", function()
      local T, C = boot()
      T.race = "gnome"
      local model, view = newCellModel()
      C.Dress(model, T.Slots.BY_KEY.FEET, 1)
      H.eq(view.log(), "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(3.8,0,1.1) Undress() TryOn(1)")
      -- ausdruecklich uebergebene Rasse gewinnt
      model, view = newCellModel()
      C.Dress(model, T.Slots.BY_KEY.FEET, 1, nil, "human")
      H.eq(view.log(), "SetUnit(player) SetRotation(0.61) SetRotation(0.61) SetPosition(4.8,0,1.5) Undress() TryOn(1)")
      -- Token wie von UnitRace: "NightElf"
      model, view = newCellModel()
      C.Dress(model, T.Slots.BY_KEY.SHOULDER, 1, nil, "NightElf")
      H.eq(view.log(), "SetUnit(player) SetRotation(0.61) SetPosition(7.8,0.5,-1.7) Undress() TryOn(1)")
      -- Describe: nil/leer/unbekannt = keine Anpassung
      local _, z1 = C.Describe("HEAD", nil, nil, 0, 0, 0)
      local _, z2 = C.Describe("HEAD", "", nil, 0, 0, 0)
      local _, z3 = C.Describe("HEAD", "worgen", nil, 0, 0, 0)
      local _, z4 = C.Describe("HEAD", 42, nil, 0, 0, 0)
      H.eq(z1, 5.8)
      H.eq(z2, 5.8)
      H.eq(z3, 5.8)
      H.eq(z4, 5.8, "Nicht-String-Rasse wird ignoriert")
   end)

   H.test("Describe ist rein und unabhaengig vom Aufrufzustand; nil-Position zaehlt als 0", function()
      local _, C = boot()
      local first = {}
      for _, key in ipairs(SLOT_KEYS) do
         for _, race in ipairs(RACES) do
            local r, z, x, y = C.Describe(key, race, "INVTYPE_RANGEDRIGHT", 1, 2, 3)
            first[key .. "/" .. race] = { r, z, x, y }
         end
      end
      for si = #SLOT_KEYS, 1, -1 do
         for ri = #RACES, 1, -1 do
            C.Describe("RANGED", "troll", "INVTYPE_RANGEDRIGHT", -9, -9, -9)   -- Stoeraufruf
            local r, z, x, y = C.Describe(SLOT_KEYS[si], RACES[ri], "INVTYPE_RANGEDRIGHT", 1, 2, 3)
            local f = first[SLOT_KEYS[si] .. "/" .. RACES[ri]]
            H.truthy(r == f[1] and z == f[2] and x == f[3] and y == f[4], SLOT_KEYS[si] .. "/" .. RACES[ri])
         end
      end
      local a = { C.Describe("HEAD", "human", nil, nil, nil, nil) }
      local b = { C.Describe("HEAD", "human", nil, 0, 0, 0) }
      H.deepEq(a, b)
   end)

   H.test("Apply: ohne Modell false; unbekannter Slot nur Grundrotation (kein SetPosition)", function()
      local _, C = boot()
      H.eq(C.Apply(nil, "HEAD", "human", nil), false)
      local m = newDouble(1, 2, 3)
      H.eq(C.Apply(m, "NOPE", "tauren", nil), false)
      H.eq(traceNames(m), "SetRotation,GetPosition")
      H.near(m.trace[1][2], 0.61)
      local rot, z, x, y, positioned = C.Describe("NOPE", "tauren", nil, 1, 2, 3)
      H.near(rot, 0.61)
      H.eq(z, 1)
      H.eq(x, 2)
      H.eq(y, 3)
      H.eq(positioned, false)
      -- Modell ohne Position (noch nicht geladen): wie (0, 0, 0)
      local np = { trace = {} }
      function np:SetRotation(r) np.trace[#np.trace + 1] = { "SetRotation", r } end
      function np:GetPosition() return nil end
      function np:SetPosition(a, b, c) np.trace[#np.trace + 1] = { "SetPosition", a, b, c } end
      H.eq(C.Apply(np, "HEAD", "human", nil), true)
      H.deepEq(np.trace[2], { "SetPosition", 5.8, 0, -2.2 })
      -- Dress mit nil-Modell
      C.Dress(nil, "HEAD", 1)
   end)

   -- ======================================================================
   H.section("Fernkampf: equipLoc ermitteln")
   -- ======================================================================

   H.test("RANGED: ohne equipLoc schlaegt Dress den Gegenstand im Cache nach", function()
      local T, C = boot()
      M.items[700] = { name = "Gewehr", quality = 3, class = "Weapon", subclass = "Guns", equipLoc = "INVTYPE_RANGEDRIGHT" }
      M.items[701] = { name = "Wurfmesser", quality = 3, class = "Weapon", subclass = "Thrown", equipLoc = "INVTYPE_THROWN" }
      M.items[702] = { name = "Bogen", quality = 3, class = "Weapon", subclass = "Bows", equipLoc = "INVTYPE_RANGED" }
      M.CacheAll()
      local function lastRot(id, loc)
         local model, view = newCellModel()
         C.Dress(model, T.Slots.BY_KEY.RANGED, id, loc, "human")
         return view.last("SetRotation")[2]
      end
      H.near(lastRot(700), 0.61, 1e-9, "Gewehr: nach links")
      H.near(lastRot(701), -0.61, 1e-9, "Wurfwaffe")
      H.near(lastRot(702), -0.61, 1e-9, "Bogen")
      H.near(lastRot(703), -0.61, 1e-9, "unbekannt/nicht im Cache")
      H.near(lastRot(701, "INVTYPE_RANGEDRIGHT"), 0.61, 1e-9, "uebergebenes equipLoc gewinnt")
      H.near(lastRot(700, "INVTYPE_THROWN"), -0.61, 1e-9, "uebergebenes equipLoc gewinnt (2)")
   end)

   H.test("RANGED: GetItemInfo wird nur fuer den Fernkampf-Slot und nur ohne equipLoc gefragt", function()
      local T, C = boot()
      local asked = 0
      local real = rawget(_G, "GetItemInfo")
      _G.GetItemInfo = function(...)   -- lint:allow(dyn-global-write)
         asked = asked + 1
         return real(...)
      end
      local model = newCellModel()
      for _, key in ipairs(SLOT_KEYS) do
         if key ~= "RANGED" then C.Dress(model, T.Slots.BY_KEY[key], 4711, nil, "human") end
      end
      H.eq(asked, 0, "keine Abfrage ausserhalb des Fernkampf-Slots")
      C.Dress(model, T.Slots.BY_KEY.RANGED, 4711, "INVTYPE_RANGED", "human")
      H.eq(asked, 0, "keine Abfrage mit equipLoc")
      C.Dress(model, T.Slots.BY_KEY.RANGED, 999999, nil, "human")
      H.eq(asked, 0, "keine Abfrage fuer Verborgen")
      C.Dress(model, T.Slots.BY_KEY.RANGED, 4711, nil, "human")
      H.eq(asked, 1)
      _G.GetItemInfo = real   -- lint:allow(dyn-global-write)
   end)

   H.test("RANGED: nur INVTYPE_RANGEDRIGHT dreht; andere Slots ignorieren equipLoc", function()
      local _, C = boot()
      local function rot(slot, loc) return (C.Describe(slot, "human", loc, 0, 0, 0)) end
      H.near(rot("RANGED", "INVTYPE_RANGEDRIGHT"), 0.61)
      H.near(rot("RANGED", "INVTYPE_RANGED"), -0.61)
      H.near(rot("RANGED", "INVTYPE_THROWN"), -0.61)
      H.near(rot("RANGED", nil), -0.61)
      H.near(rot("RANGED", ""), -0.61)
      H.near(rot("HEAD", "INVTYPE_RANGEDRIGHT"), 0.61)
      H.near(rot("OFFHAND", "INVTYPE_RANGEDRIGHT"), -0.61)
      H.near(rot("MAINHAND", "INVTYPE_RANGEDRIGHT"), 0.61)
   end)

   -- ======================================================================
   H.section("Selbstkonsistenz: Dress (Modellaufrufe) == Describe (reine Rechnung)")
   -- ======================================================================

   H.test("alle 14 Slots x Rassen x equipLoc x Positionen: Dress und Describe ergeben denselben Endzustand", function()
      local T, C = boot()
      local raceList = {}
      for _, r in ipairs(RACES) do raceList[#raceList + 1] = r end
      for _, r in ipairs(EXTRA_RACES) do raceList[#raceList + 1] = r end
      raceList[#raceList + 1] = false   -- false = nil

      local combos, bad, firstBad = 0, 0, nil
      local savedRace = T.race
      for _, slotKey in ipairs(SLOT_KEYS) do
         local def = T.Slots.BY_KEY[slotKey]
         for _, raceEntry in ipairs(raceList) do
            local race = raceEntry or nil
            -- Rasse nil: Dress faellt auf T.race zurueck -> hier ein Token ohne Sonderbehandlung
            T.race = "human"
            for _, locEntry in ipairs(EQUIP_LOCS) do
               local equipLoc = locEntry or nil
               for _, p in ipairs(POSITIONS) do
                  for _, itemId in ipairs({ 12345, 999999 }) do
                     combos = combos + 1
                     local m = newDouble(p[1], p[2], p[3])
                     C.Dress(m, def, itemId, equipLoc, race)
                     local names = traceNames(m)
                     local tail = "SetPosition" .. (HAND_SLOTS[slotKey] and "" or ",Undress")
                        .. (itemId == 999999 and "" or ",TryOn")
                     -- zwischen GetPosition und SetPosition stehen nur zusaetzliche Rotationen
                     -- (Tauren, Fernkampf); alles andere hat eine feste Reihenfolge
                     local mid = names:match("^SetUnit,SetRotation,GetPosition,(.*)" .. tail .. "$")
                     if not mid or mid:gsub("SetRotation,", "") ~= "" then
                        bad = bad + 1
                        firstBad = firstBad or (slotKey .. "/" .. tostring(race) .. ": Reihenfolge " .. names)
                     end
                     -- reine Sicht: Describe == Endzustand des Protokolls
                     if itemId == 12345 then
                        local oRot, oPos = finalState(m.trace)
                        local rot, z, x, y, positioned = C.Describe(slotKey, race, equipLoc, p[1], p[2], p[3])
                        if not (oPos and rot == oRot and positioned == true and z == oPos[1] and x == oPos[2]
                           and y == oPos[3]) then
                           bad = bad + 1
                           firstBad = firstBad or ("Describe " .. slotKey .. "/" .. tostring(race))
                        end
                     end
                  end
               end
            end
         end
      end
      T.race = savedRace
      H.eq(combos, 14 * (#RACES + #EXTRA_RACES + 1) * 4 * 3 * 2, "Kombinationsanzahl")
      H.eq(bad, 0, "Abweichungen: " .. tostring(firstBad))
   end)

   H.test("Rassenabdeckung: Sonderrassen weichen ab, die uebrigen rechnen exakt wie human", function()
      local _, C = boot()
      for _, race in ipairs({ "nightelf", "gnome", "dwarf", "troll", "goblin", "tauren" }) do
         local hits = 0
         for _, slotKey in ipairs(SLOT_KEYS) do
            local r1, z1, x1, y1 = C.Describe(slotKey, "human", nil, 0, 0, 0)
            local r2, z2, x2, y2 = C.Describe(slotKey, race, nil, 0, 0, 0)
            if not (r1 == r2 and z1 == z2 and x1 == x2 and y1 == y2) then hits = hits + 1 end
         end
         H.truthy(hits > 0, "Rasse " .. race .. " wird behandelt")
      end
      for _, race in ipairs({ "draenei", "orc", "scourge", "bloodelf", "undead", "worgen" }) do
         for _, slotKey in ipairs(SLOT_KEYS) do
            local a = { C.Describe(slotKey, "human", nil, 1, 2, 3) }
            local b = { C.Describe(slotKey, race, nil, 1, 2, 3) }
            H.deepEq(b, a, race .. "/" .. slotKey)
         end
      end
   end)

   -- ======================================================================
   H.section("Hygiene")
   -- ======================================================================

   H.test("Cameras legt keine Globals an und liest keine Implicit-Globals", function()
      local T, C = boot()
      local model = newCellModel()
      for _, key in ipairs(SLOT_KEYS) do
         C.Dress(model, T.Slots.BY_KEY[key], 4711, nil, "tauren")
      end
      H.len(M.StrayGlobals(), 0)
      H.len(M.ImplicitGlobalReads(), 0)
   end)
end
