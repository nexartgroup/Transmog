-- Window.lua  (T.UI.Window)
-- ---------------------------------------------------------------------------
-- Hauptfenster "TransmogWindow" (SPEC 6.3, 11.4).
--
--   +---------------------------------------------------------------------+
--   | Transmog  [Items] [Outfits]                           [*] [x]       |  Kopf 30
--   +---------------------------------------------------------------------+
--   | (optionale Hinweisleiste 22: Vorschau-Modus gelb, Server fehlt rot) |
--   +-------------------------+-------------------------------------------+
--   | SlotBar | Vorschau | Slot | FilterBar (58)                           |
--   |  44     |          |  44  | Grid  ODER  OutfitsTab                   |
--   +-------------------------+-------------------------------------------+
--   | [Verwerfen] [Alles entfernen]  Status        Kosten      [Anwenden]  |  Fuss 46
--   +---------------------------------------------------------------------+
--
-- Alle Masse werden EXPLIZIT berechnet (Window.Metrics) und per SetWidth /
-- SetHeight / SetPoint gesetzt; nichts wird aus der Anker-Aufloesung gelesen.
-- Die Unterkomponenten (SlotBar, Preview, Grid, FilterBar, OutfitsTab, Options)
-- werden ueber den Vertrag aus SPEC 11.2 gerufen und duerfen fehlen oder
-- werfen: jeder Aufruf ist geschuetzt, ein Fehler geht an den Fehlerbehandler.
--
-- Groesse und Scale
--
--   DB.global.width/height sind Fenster-Einheiten (vor dem Scale). Der Scale
--   ist DB.global.scale (0 = automatisch, siehe Window.ComputeScale). Die
--   Groesse wird angezeigt, ohne den gespeicherten Wunsch zu ueberschreiben:
--   auf einem kleineren Bildschirm wird sie nur geklemmt, auf einem groesseren
--   kommt der alte Wert zurueck. Die Position steht in DB.global.point als
--   { "TOPLEFT", "BOTTOMLEFT", x, y } in UIParent-Einheiten (unabhaengig vom
--   Scale) und wird beim Anwenden an den Bildschirm geklemmt.
--
-- Oeffnen und Schliessen: siehe Window.Open und das OnHide-Skript. Das Fenster
-- wird erst beim ersten Oeffnen gebaut.
--
-- Fuss
--
--   Knoepfe, Statuszeile und Kosten werden nach der Breite ihrer Texte angeordnet
--   (LayoutFooter): das Kostenfeld waechst mit seinem Text (bis COST_MAX), reicht
--   der Platz nicht, schrumpfen zuerst die Kosten, dann die Knoepfe; als letztes
--   entfaellt die Beschriftung "Kosten:". Die Statuszeile bekommt den Rest und
--   zeigt waehrend eines laufenden Stapels (State.Busy) den Fortschritt, auch
--   wenn die zeitlich begrenzte Meldung laengst abgelaufen ist. Wird das Fenster
--   waehrend des Anwendens geschlossen, steht das Ergebnis im Chat.
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.UI = T.UI or {}
T.UI.Window = T.UI.Window or {}
local Window = T.UI.Window

local L = T.L

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local format, tinsert = string.format, table.insert

-- ---------------------------------------------------------------------------
-- Masse (SPEC 6.3 / 11.4), Fenster-Einheiten bei Scale 1.0
-- ---------------------------------------------------------------------------

local MIN_W, MIN_H = 740, 520          -- kleinste Fenstergroesse
local DEF_W, DEF_H = 880, 600          -- Standardgroesse
local HEADER_H = 30                    -- Kopf
local NOTICE_H = 22                    -- Hinweisleiste (nur bei Bedarf)
local FOOTER_H = 46                    -- Fuss
local PAD = 8                          -- Rand und Abstand der Panels
local LEFT_W = 318                     -- linkes Panel
local COLUMN_W = 44                    -- eine Spalte der SlotBar
local FILTER_H = 58                    -- FilterBar.HEIGHT (Vorgabe)
local GRID_GAP = 6                     -- Abstand FilterBar - Raster
local BUTTON_H = 26                    -- Knopfhoehe im Fuss
local BUTTON_TOP = 8                   -- Abstand der Knoepfe von der Fussoberkante
local GRIP_SIZE = 12                   -- Groessengriff unten rechts
local COST_MAX = 320                   -- breiteste Kostenanzeige im Fuss
local AUTO_FRACTION = 0.82             -- Anteil des Bildschirms bei automatischem Scale
local SCALE_AUTO_MIN, SCALE_AUTO_MAX = 0.7, 1.5
local SCALE_MIN, SCALE_MAX = 0.6, 1.5  -- manueller Scale
local LAYOUT_THROTTLE = 0.05           -- s zwischen zwei Layouts beim Ziehen
local STATUS_SECONDS = 6               -- Anzeigedauer einer Statusmeldung
local WATCH_SECONDS = 1                -- Abfrage der Bildschirmgroesse

-- Ton nach erfolgreichem Anwenden: ein Standardton des 3.3.5a-Clients (Muenzgeraeusch);
-- das Addon bringt keine eigenen Mediendateien mit. Unbekannte Namen bleiben stumm.
local SOUND_APPLY = "LOOTWINDOWCOINSOUND"
local GRIP_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local GRIP_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down"
local GRIP_HIGHLIGHT = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"

Window.MIN_WIDTH = MIN_W
Window.MIN_HEIGHT = MIN_H
Window.DEFAULT_WIDTH = DEF_W
Window.DEFAULT_HEIGHT = DEF_H
Window.HEADER_HEIGHT = HEADER_H
Window.NOTICE_HEIGHT = NOTICE_H
Window.FOOTER_HEIGHT = FOOTER_H
Window.PADDING = PAD
Window.LEFT_WIDTH = LEFT_W
Window.COLUMN_WIDTH = COLUMN_W

-- Rueckfall, falls T.Slots fehlt (Test): die 14 Server-Slots in Anzeigereihenfolge
local FALLBACK_SLOTS = { 0, 2, 14, 4, 3, 18, 8, 9, 5, 6, 7, 15, 16, 17 }

-- Ankerbruchteile eines der 9 Ankerpunkte (x von links, y von unten)
local ANCHOR_X = {
   LEFT = 0, CENTER = 0.5, RIGHT = 1, TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1,
   BOTTOMLEFT = 0, BOTTOM = 0.5, BOTTOMRIGHT = 1,
}
local ANCHOR_Y = {
   BOTTOM = 0, CENTER = 0.5, TOP = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 0,
   LEFT = 0.5, RIGHT = 0.5, TOPLEFT = 1, TOPRIGHT = 1,
}

-- ---------------------------------------------------------------------------
-- Zustand
-- ---------------------------------------------------------------------------

local S = {
   built = false,         -- Fenster gebaut
   failed = false,        -- Aufbau ist fehlgeschlagen (nicht erneut versuchen)
   tab = nil,             -- "items" | "outfits"
   noticeKind = nil,      -- nil | "preview" | "server"
   statusText = nil,      -- zeitlich begrenzte Meldung
   statusColor = nil,
   statusToken = 0,
   applyTotal = 0,        -- Anzahl Operationen des laufenden Stapels (Leerlauftext waehrend Busy)
   applying = false,      -- Fenster setzt selbst seine Groesse (kein OnSizeChanged-Layout)
   inLayout = false,
   sizing = false,        -- Groessengriff gezogen
   savingSize = false,    -- eigene DB.Set-Aufrufe nicht als fremde Aenderung werten
   savingPoint = false,
   lastLayoutAt = -1000,
   screenSig = nil,
   everShown = false,     -- Fenster war schon einmal sichtbar
   rebuildPending = false, -- Groesse/Scale aenderte sich im verborgenen Zustand: Modelle beim Zeigen neu
   costNeed = 0,          -- Breite, die der Kostentext braucht (0 = leer)
   slotList = nil,        -- Zwischenspeicher der Slotreihenfolge
   metrics = nil,         -- letzte Metrik (Diagnose)
}

-- ---------------------------------------------------------------------------
-- Kleine Helfer
-- ---------------------------------------------------------------------------

-- Meldet einen Fehler an den Fehlerbehandler des Spiels (wirft nie).
local function ReportError(msg)
   local getter = _G.geterrorhandler
   local handler = type(getter) == "function" and getter() or nil
   if type(handler) == "function" then
      pcall(handler, "Transmog Window: " .. tostring(msg))
   end
end

-- Rote Chatzeile (Util.Error). Der Fehlerbehandler des Spiels zeigt ohne
-- Zusatzaddon nichts (scriptErrors ist standardmaessig aus): ein Ausfall des
-- Fensters braucht deshalb auch eine Zeile fuer den Spieler. Ohne Util stumm.
local function PrintError(fmt, ...)
   local util = T.Util
   if util and util.Error then
      util.Error(fmt, ...)
   end
end

-- Wie string.format, wirft aber nie (Util.Format).
local function Fmt(fmt, ...)
   local util = T.Util
   if util and util.Format then
      return util.Format(fmt, ...)
   end
   local ok, text = pcall(format, fmt, ...)
   return ok and text or tostring(fmt)
end

-- Entprellter Aufruf (Util.Debounce), ohne Util sofort.
local function Debounce(key, delay, fn)
   local util = T.Util
   if util and util.Debounce then
      return util.Debounce(key, delay, fn)
   end
   fn()
end

-- Farbe r, g, b zu einem Schluessel aus T.COLORS (sonst Textfarbe).
local function Rgb(key)
   local c = T.COLORS and key and T.COLORS[key]
   if type(c) ~= "table" then
      c = T.COLORS and T.COLORS.text or { 0.86, 0.88, 0.92 }
   end
   return c[1], c[2], c[3]
end

-- Aktuelle Spielzeit.
local function Now()
   if type(GetTime) == "function" then
      return GetTime()
   end
   return 0
end

-- DB.global (kann vor DB.Init fehlen) und Sicherstellung von DB.Init.
local function Globals()
   local db = T.DB
   return db and db.global or nil
end

local function EnsureDB()
   local db = T.DB
   if db and not db.global and db.Init then
      db.Init()
   end
   return db and db.global or nil
end

-- Komponente (T.UI.<name>) und geschuetzter Aufruf einer ihrer Funktionen
-- (Punktaufruf). Fehlende Komponente/Funktion: nil, ohne Fehler.
local function Comp(name)
   return T.UI and T.UI[name] or nil
end

local function CallComp(name, fn, ...)
   local mod = Comp(name)
   local f = mod and mod[fn]
   if type(f) ~= "function" then
      return nil
   end
   local ok, res = pcall(f, ...)
   if not ok then
      ReportError(name .. "." .. fn .. ": " .. tostring(res))
      return nil
   end
   return res
end

-- Baut eine Komponente (Create) geschuetzt; liefert deren Rahmen/Objekt oder nil.
local function MakeComp(name, ...)
   local mod = Comp(name)
   if not mod or type(mod.Create) ~= "function" then
      return nil
   end
   local ok, res = pcall(mod.Create, ...)
   if not ok then
      ReportError(name .. ".Create: " .. tostring(res))
      PrintError(L.BOOT_INIT_FAILED, name)
      return nil
   end
   return res
end

-- Liste der Server-Slots in Anzeigereihenfolge (die Reihenfolge ist fest: einmal
-- gebaut, dann wiederverwendet; ohne T.Slots der Rueckfall, der nicht gemerkt wird).
local function SlotList()
   if S.slotList then
      return S.slotList
   end
   local slots = T.Slots
   local list = slots and slots.LIST
   if type(list) == "table" and #list > 0 then
      local out = {}
      for i = 1, #list do
         out[i] = list[i].server
      end
      S.slotList = out
      return out
   end
   return FALLBACK_SLOTS
end

-- Ist slot einer der 14 transmogbaren Server-Slots?
local function ValidSlot(slot)
   if type(slot) ~= "number" then
      return false
   end
   local slots = T.Slots
   if slots and slots.BY_SERVER then
      return slots.BY_SERVER[slot] ~= nil
   end
   for i = 1, #FALLBACK_SLOTS do
      if FALLBACK_SLOTS[i] == slot then
         return true
      end
   end
   return false
end

-- Lokalisierter Slotname (nie nil).
local function SlotLabel(slot)
   local slots = T.Slots
   if slots and slots.Label then
      return slots.Label(slot)
   end
   return tostring(slot)
end

-- Text zu einem Grund-Schluessel aus State.CanApply/CanRemoveAll. Bewusst
-- ausgeschrieben, damit die Locale-Pruefung die Schluessel statisch findet.
local function ReasonText(key)
   if key == "APPLY_REASON_NONE" then return L.APPLY_REASON_NONE end
   if key == "APPLY_REASON_VENDOR" then return L.APPLY_REASON_VENDOR end
   if key == "APPLY_REASON_BUSY" then return L.APPLY_REASON_BUSY end
   if key == "APPLY_REASON_COST_PENDING" then return L.APPLY_REASON_COST_PENDING end
   if key == "APPLY_REASON_MONEY" then return L.APPLY_REASON_MONEY end
   if key == "APPLY_REASON_SERVER" then return L.APPLY_REASON_SERVER end
   return tostring(key or "")
end

-- Breite eines Textes in der kleinen Standardschrift (eigener Messer-FontString).
local function TextWidth(text)
   local f = Window.frame
   if not f then
      return 0
   end
   if not S.measure then
      local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
      fs:SetAlpha(0)
      S.measure = fs
   end
   S.measure:SetText(text or "")
   return S.measure:GetStringWidth() or 0
end

-- Breite eines Textes mit eingebetteten Symbolen (|T...|t, z. B. Muenzen): die
-- Symbole werden einzeln gerechnet (14 px + 2 Reserve), den Rest misst die
-- Schrift. Farbcodes brauchen keine Breite.
local ICON_WIDTH = 16
local function RichWidth(text)
   local icons = 0
   local plain = string.gsub(text or "", "|T[^|]*|t", function()
      icons = icons + 1
      return ""
   end)
   return TextWidth(plain) + icons * ICON_WIDTH
end

-- Breite, die ein Knopf fuer seine Beschriftung braucht (gemessen am Messer-
-- FontString: das Feld des Knopfs hat eine feste Breite und meldet nur die
-- umbrochene), zwischen lo und hi.
local function ButtonWidth(btn, extra, lo, hi)
   local w = ceil(TextWidth(btn.label:GetText())) + extra
   if w < lo then w = lo end
   if w > hi then w = hi end
   return w
end

-- Plant das Neuzeichnen des Fusses (entprellt, nur wenn sichtbar); unten definiert.
local ScheduleFooter

-- true, wenn das Fenster gebaut und sichtbar ist.
local function IsUp()
   local f = Window.frame
   return S.built and f ~= nil and f:IsShown() and true or false
end

-- ---------------------------------------------------------------------------
-- Groesse, Scale, Position
-- ---------------------------------------------------------------------------

-- Bildschirmgroesse in UIParent-Einheiten.
local function ScreenSize()
   local w, h
   if UIParent and UIParent.GetWidth then
      w, h = UIParent:GetWidth(), UIParent:GetHeight()
   end
   if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
      if type(GetScreenWidth) == "function" then
         w, h = GetScreenWidth(), GetScreenHeight()
      end
   end
   if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
      w, h = 1024, 768
   end
   return w, h
end

-- Kennung von Bildschirmgroesse und UI-Scale (fuer die Aufloesungsabfrage).
local function ScreenSignature()
   local w, h = ScreenSize()
   local es = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
   return format("%d:%d:%d", floor(w * 100), floor(h * 100), floor((es or 1) * 1000))
end

local function Clamp(v, lo, hi)
   if v < lo then return lo end
   if v > hi then return hi end
   return v
end

-- Scale des Fensters: DB.global.scale (0 = automatisch, sonst 0.6..1.5), so
-- begrenzt, dass die Mindestgroesse auf den Bildschirm passt.
function Window.ComputeScale()
   local g = Globals()
   local sw, sh = ScreenSize()
   local s = g and tonumber(g.scale) or 0
   if s > 0 then
      s = Clamp(s, SCALE_MIN, SCALE_MAX)
   else
      s = Clamp(min(sw * AUTO_FRACTION / DEF_W, sh * AUTO_FRACTION / DEF_H), SCALE_AUTO_MIN, SCALE_AUTO_MAX)
   end
   local fit = min(sw / MIN_W, sh / MIN_H)
   if s > fit then
      s = fit
   end
   return s
end

-- Klemmt eine Fenstergroesse (Fenster-Einheiten) auf [Minimum, Bildschirm/Scale].
-- Rueckgabe: w, h, maxW, maxH.
function Window.ClampSize(w, h, scale)
   local sw, sh = ScreenSize()
   scale = tonumber(scale)
   if not scale or scale <= 0 then
      scale = 1
   end
   local maxW = max(MIN_W, floor(sw / scale))
   local maxH = max(MIN_H, floor(sh / scale))
   w = Clamp(tonumber(w) or DEF_W, MIN_W, maxW)
   h = Clamp(tonumber(h) or DEF_H, MIN_H, maxH)
   return w, h, maxW, maxH
end

-- Alle Masse des Fensters fuer die Groesse w x h (Fenster-Einheiten). Reine
-- Rechnung, keine Frames. Y-Werte zaehlen von der Fensteroberkante nach unten.
function Window.Metrics(w, h, notice)
   w = tonumber(w) or DEF_W
   h = tonumber(h) or DEF_H
   local fb = Comp("FilterBar")
   local filterH = fb and tonumber(fb.HEIGHT) or FILTER_H
   local noticeH = notice and NOTICE_H or 0
   local m = {
      width = w, height = h,
      headerH = HEADER_H, noticeH = noticeH, footerH = FOOTER_H, pad = PAD,
      noticeY = 1 + HEADER_H,
      leftX = PAD, leftW = LEFT_W, columnW = COLUMN_W,
      previewX = COLUMN_W, previewW = LEFT_W - 2 * COLUMN_W,
      filterH = filterH, gridGap = GRID_GAP,
   }
   -- Kopf, Hinweisleiste und Fuss werden vom Fensterrand aus gemessen (SPEC 11.4:
   -- Kopf 30, Leiste 22, Fuss 46, Rand 8); der Rahmen von 1 px liegt darin.
   m.contentY = HEADER_H + noticeH + PAD
   m.contentH = max(0, h - FOOTER_H - PAD - m.contentY)
   m.rightX = PAD + LEFT_W + PAD
   m.rightW = max(0, w - PAD - m.rightX)
   m.gridY = filterH + GRID_GAP
   m.gridH = max(0, m.contentH - m.gridY)
   m.footerY = h - 1 - FOOTER_H
   m.innerW = max(0, w - 2)
   return m
end

-- Setzt Position (aus DB.global.point, geklemmt) oder zentriert das Fenster.
-- Gerechnet wird in UIParent-Einheiten; der Anker ist immer TOPLEFT/BOTTOMLEFT.
function Window.RestorePosition()
   local f = Window.frame
   if not f then
      return
   end
   local sw, sh = ScreenSize()
   local scale = f:GetScale() or 1
   local wUI, hUI = (f:GetWidth() or DEF_W) * scale, (f:GetHeight() or DEF_H) * scale
   local g = Globals()
   local p = g and g.point
   local left, top

   if type(p) == "table" then
      local pt = p[1] or p.point
      local rel, x, y
      if type(p[3]) == "string" then
         rel, x, y = p[3], p[4], p[5]            -- Form von GetPoint
      else
         rel, x, y = p[2] or p.relPoint, p[3] or p.x, p[4] or p.y
      end
      x, y = tonumber(x), tonumber(y)
      if ANCHOR_X[pt] and ANCHOR_X[rel] and x and y then
         left = ANCHOR_X[rel] * sw + x - ANCHOR_X[pt] * wUI
         top = ANCHOR_Y[rel] * sh + y + (1 - ANCHOR_Y[pt]) * hUI
      end
   end
   if not left then
      left = (sw - wUI) / 2
      top = (sh + hUI) / 2
   end

   left = Clamp(left, 0, max(0, sw - wUI))
   top = Clamp(top, min(hUI, sh), sh)
   f:ClearAllPoints()
   f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
end

-- Merkt die aktuelle Position in DB.global.point (nach dem Ziehen) und
-- verankert das Fenster sauber neu.
function Window.SavePosition()
   local f = Window.frame
   if not f then
      return
   end
   local left, top = f:GetLeft(), f:GetTop()
   if not left or not top then
      return
   end
   local es = f:GetEffectiveScale() or 1
   local ps = UIParent and UIParent:GetEffectiveScale() or 1
   if not ps or ps <= 0 then
      ps = 1
   end
   local ratio = es / ps
   local sw, sh = ScreenSize()
   local wUI, hUI = (f:GetWidth() or DEF_W) * ratio, (f:GetHeight() or DEF_H) * ratio
   local x = Clamp(left * ratio, 0, max(0, sw - wUI))
   local y = Clamp(top * ratio, min(hUI, sh), sh)
   x = floor(x * 10 + 0.5) / 10
   y = floor(y * 10 + 0.5) / 10

   local db = T.DB
   if db and db.Set then
      S.savingPoint = true
      db.Set("point", { "TOPLEFT", "BOTTOMLEFT", x, y })
      S.savingPoint = false
   end
   f:ClearAllPoints()
   f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / (ratio > 0 and ratio or 1), y / (ratio > 0 and ratio or 1))
end

-- ---------------------------------------------------------------------------
-- Modelle neu aufbauen (nach Groessen-/Scale-Aenderung)
-- ---------------------------------------------------------------------------

-- Ein Durchlauf: Vorschau neu laden, Raster neu zeichnen. Das Raster auch im
-- Outfit-Reiter: Grid.Rebuild verwirft die Schluessel der Zellen, und ein
-- verborgenes Raster merkt sich nur "schmutzig" und zeichnet beim Zurueckwechseln
-- mit leeren Schluesseln neu. Ohne das behielten die Zellmodelle ihre alte
-- Projektion (die beim SetUnit berechnet wird, SPEC 9.2), weil die Zelle bei
-- gleichem Schluessel nur Show() ruft.
local function RebuildModels()
   local f = Window.frame
   if not S.built or not f or not f:IsVisible() then
      return
   end
   CallComp("Preview", "Rebuild")
   -- Grid.Rebuild kleidet alle Zellmodelle neu an (SetUnit), Refresh nur bei
   -- geaenderten Schluesseln; fehlt Rebuild, bleibt Refresh (SPEC 11.2).
   local grid = Comp("Grid")
   if grid and type(grid.Rebuild) == "function" then
      CallComp("Grid", "Rebuild")
   else
      CallComp("Grid", "Refresh")
   end
end

-- Plant den Neuaufbau entprellt (hoechstens einmal je Ruhephase). Ein
-- verborgenes Fenster merkt ihn sich (rebuildPending) und holt ihn beim Zeigen
-- nach: Scale und Groesse koennen sich aendern, solange es zu ist (Optionen,
-- Aufloesung), und die Projektion der Modelle haengt daran (SPEC 9.2). Vor dem
-- ersten Zeigen gibt es nichts nachzuholen, die Modelle entstehen dann ohnehin.
local function ScheduleRebuild(delay)
   local f = Window.frame
   if not S.built or not f then
      return
   end
   if not f:IsVisible() then
      if S.everShown then
         S.rebuildPending = true
      end
      return
   end
   S.rebuildPending = false
   Debounce("ui-window-rebuild", tonumber(delay) or 0.05, RebuildModels)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

-- Ordnet die Bedienelemente des Fusses an: Verwerfen und Alles entfernen links,
-- Anwenden rechts, dazwischen Statuszeile und Kosten. Breiten zuerst (nach den
-- Texten), damit sich nichts ueberlappt: die Kosten bekommen, was ihr Text
-- braucht (S.costNeed, 0 = leer); reicht der Platz nicht, schrumpfen zuerst die
-- Kosten, dann die Knoepfe. Die Statuszeile bekommt den Rest.
local function LayoutFooter(f, m)
   local foot = f.footer
   local wDiscard = ButtonWidth(f.btnDiscard, 24, 84, 160)
   local wRemove = ButtonWidth(f.btnRemoveAll, 24, 96, 180)
   -- Anwenden: Breite fuer den laengeren der beiden Texte, damit sie nicht springt
   local applyW = max(TextWidth(L.WIN_APPLY), TextWidth(L.WIN_APPLY_RESET))
   applyW = Clamp(ceil(applyW) + 36, 120, 200)
   local costW = 0
   if S.costNeed > 0 then
      costW = Clamp(S.costNeed, 60, COST_MAX)
   end
   local statusMin = 70
   local avail = m.innerW - 2 * PAD - 44          -- 44 = 6 + 14 + 12 + 12 (Abstaende)
   local buttons = wDiscard + wRemove + applyW
   if buttons + costW + statusMin > avail then
      costW = Clamp(avail - buttons - statusMin, min(costW, 110), costW)
      local room = avail - costW - statusMin
      if buttons > room then
         local k = max(0.3, room / buttons)
         wDiscard = max(56, floor(wDiscard * k))
         wRemove = max(64, floor(wRemove * k))
         applyW = max(88, floor(applyW * k))
      end
   end
   local statusW = max(0, avail - wDiscard - wRemove - applyW - costW)
   S.costW = costW

   local fx = PAD
   f.btnDiscard:SetWidth(wDiscard)
   f.btnDiscard:ClearAllPoints()
   f.btnDiscard:SetPoint("TOPLEFT", foot, "TOPLEFT", fx, -BUTTON_TOP)
   fx = fx + wDiscard + 6
   f.btnRemoveAll:SetWidth(wRemove)
   f.btnRemoveAll:ClearAllPoints()
   f.btnRemoveAll:SetPoint("TOPLEFT", foot, "TOPLEFT", fx, -BUTTON_TOP)
   fx = fx + wRemove + 14

   f.statusText:SetWidth(max(1, statusW))
   f.statusText:ClearAllPoints()
   f.statusText:SetPoint("TOPLEFT", foot, "TOPLEFT", fx, -14)

   f.btnApply:SetWidth(applyW)
   f.btnApply:ClearAllPoints()
   f.btnApply:SetPoint("TOPRIGHT", foot, "TOPRIGHT", -PAD, -BUTTON_TOP)

   -- (Breite 0 hiesse im Spiel "ohne Begrenzung": mindestens 1)
   f.costText:SetWidth(max(1, costW))
   f.costText:ClearAllPoints()
   f.costText:SetPoint("TOPRIGHT", foot, "TOPRIGHT", -(PAD + applyW + 12), -14)
end

-- Ordnet Kopf, Hinweisleiste, Panels, Komponenten und Fuss nach Window.Metrics.
local function LayoutBody(f)
   local w, h = f:GetWidth() or DEF_W, f:GetHeight() or DEF_H
   local m = Window.Metrics(w, h, S.noticeKind ~= nil)
   S.metrics = m

   -- Kopf: Reiter hinter dem Titel
   local titleW = ceil(f.head.title:GetStringWidth() or 0)
   local x = 12 + titleW + 22
   local wItems = ButtonWidth(f.tabItems, 28, 84, 170)
   f.tabItems:SetWidth(wItems)
   f.tabItems:ClearAllPoints()
   f.tabItems:SetPoint("TOPLEFT", f.head, "TOPLEFT", x, -4)
   x = x + wItems + 4
   f.tabOutfits:SetWidth(ButtonWidth(f.tabOutfits, 28, 84, 170))
   f.tabOutfits:ClearAllPoints()
   f.tabOutfits:SetPoint("TOPLEFT", f.head, "TOPLEFT", x, -4)

   -- Hinweisleiste
   local n = f.notice
   n:ClearAllPoints()
   n:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -m.noticeY)
   n:SetWidth(m.innerW)
   n:SetHeight(NOTICE_H)
   n.text:SetWidth(max(0, m.innerW - 24))

   -- linkes Panel mit SlotBar-Spalten und Vorschau
   local left = f.left
   left:ClearAllPoints()
   left:SetPoint("TOPLEFT", f, "TOPLEFT", m.leftX, -m.contentY)
   left:SetWidth(m.leftW)
   left:SetHeight(m.contentH)

   local bar = S.bar
   if type(bar) == "table" and bar.left and bar.right then
      bar.left:ClearAllPoints()
      bar.left:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
      bar.left:SetWidth(COLUMN_W)
      bar.left:SetHeight(m.contentH)
      bar.right:ClearAllPoints()
      bar.right:SetPoint("TOPRIGHT", left, "TOPRIGHT", 0, 0)
      bar.right:SetWidth(COLUMN_W)
      bar.right:SetHeight(m.contentH)
      CallComp("SlotBar", "Layout", m.contentH)
   end
   if S.preview then
      S.preview:ClearAllPoints()
      S.preview:SetPoint("TOPLEFT", left, "TOPLEFT", m.previewX, 0)
      S.preview:SetWidth(m.previewW)
      S.preview:SetHeight(m.contentH)
      CallComp("Preview", "Layout", m.previewW, m.contentH)
   end

   -- rechtes Panel
   local right = f.right
   right:ClearAllPoints()
   right:SetPoint("TOPLEFT", f, "TOPLEFT", m.rightX, -m.contentY)
   right:SetWidth(m.rightW)
   right:SetHeight(m.contentH)

   if S.tab == "outfits" then
      if S.outfitsFrame then
         S.outfitsFrame:ClearAllPoints()
         S.outfitsFrame:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
         S.outfitsFrame:SetWidth(m.rightW)
         S.outfitsFrame:SetHeight(m.contentH)
         CallComp("OutfitsTab", "Layout", m.rightW, m.contentH)
      end
   else
      if S.filterFrame then
         S.filterFrame:ClearAllPoints()
         S.filterFrame:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
         S.filterFrame:SetWidth(m.rightW)
         S.filterFrame:SetHeight(m.filterH)
         CallComp("FilterBar", "Layout", m.rightW)
      end
      if S.gridFrame then
         S.gridFrame:ClearAllPoints()
         S.gridFrame:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -m.gridY)
         S.gridFrame:SetWidth(m.rightW)
         S.gridFrame:SetHeight(m.gridH)
         CallComp("Grid", "Layout", m.rightW, m.gridH)
      end
   end

   -- Fuss
   local foot = f.footer
   foot:ClearAllPoints()
   foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
   foot:SetWidth(m.innerW)
   foot:SetHeight(FOOTER_H)
   LayoutFooter(f, m)

   -- Griff
   f.grip:ClearAllPoints()
   f.grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

   S.lastLayoutAt = Now()
   -- der Platz im Fuss hat sich evtl. geaendert: Kostentext (Beschriftung ja/nein) neu
   ScheduleFooter()
end

-- Berechnet alle Groessen und ruft die Layouts der Komponenten.
function Window.Layout()
   local f = Window.frame
   if not f or not S.built or S.inLayout then
      return
   end
   S.inLayout = true
   local ok, err = pcall(LayoutBody, f)
   S.inLayout = false
   if not ok then
      ReportError("Layout: " .. tostring(err))
   end
end

-- Groessenaenderung des Fensters (Ziehen am Griff): gedrosselt neu anordnen.
local function OnSizeChanged()
   if S.applying or not S.built then
      return
   end
   if Now() - S.lastLayoutAt >= LAYOUT_THROTTLE then
      Window.Layout()
   else
      Debounce("ui-window-layout", LAYOUT_THROTTLE, Window.Layout)
   end
end

-- Wendet Scale, Fenstergroesse und Position an (nach DB-Aenderung und bei
-- Aenderung der Aufloesung) und plant den Neuaufbau der Modelle.
function Window.ApplyScale()
   local f = Window.frame
   if not f or not S.built then
      return
   end
   local g = EnsureDB()
   if not g then
      return
   end
   local scale = Window.ComputeScale()
   local w, h, maxW, maxH = Window.ClampSize(g.width, g.height, scale)
   S.applying = true
   f:SetScale(scale)
   f:SetMinResize(MIN_W, MIN_H)
   f:SetMaxResize(maxW, maxH)
   f:SetWidth(w)
   f:SetHeight(h)
   S.applying = false
   S.screenSig = ScreenSignature()
   Window.RestorePosition()
   Window.Layout()
   ScheduleRebuild()
end

-- Setzt Position und Groesse auf den Standard (der Scale bleibt).
function Window.ResetLayout()
   local db = T.DB
   if db and db.Set and EnsureDB() then
      S.savingSize = true
      S.savingPoint = true
      db.Set("width", DEF_W)
      db.Set("height", DEF_H)
      db.Set("point", nil)
      S.savingSize = false
      S.savingPoint = false
   end
   if Window.frame and S.built then
      Window.ApplyScale()
   end
end

-- ---------------------------------------------------------------------------
-- Hinweisleiste
-- ---------------------------------------------------------------------------

-- Welcher Hinweis gilt jetzt? "server" (rot) vor "preview" (gelb), sonst nil.
local function NoticeKind()
   local net, state = T.Net, T.State
   if net and net.state == "ABSENT" then
      return "server"
   end
   local g = Globals()
   if state and not state.atVendor and not (g and g.allowAnywhere) then
      return "preview"
   end
   return nil
end

-- Hinweisleiste aktualisieren; bei Wechsel von sichtbar/unsichtbar neu anordnen.
function Window.RefreshNotice()
   local f = Window.frame
   if not f or not S.built then
      return
   end
   local kind = NoticeKind()
   local n = f.notice
   if kind == "server" then
      n.text:SetText(L.MSG_SERVER_ABSENT)
      local r, g, b = Rgb("red")
      n.text:SetTextColor(r, g, b)
      n.stripe:SetVertexColor(r, g, b, 1)
      n:SetBackdropColor(r, g, b, 0.16)
   elseif kind == "preview" then
      n.text:SetText(L.MSG_NO_VENDOR)
      local r, g, b = Rgb("yellow")
      n.text:SetTextColor(r, g, b)
      n.stripe:SetVertexColor(r, g, b, 1)
      n:SetBackdropColor(r, g, b, 0.14)
   end
   if kind ~= S.noticeKind then
      S.noticeKind = kind
      if kind then n:Show() else n:Hide() end
      Window.Layout()
   end
end

-- ---------------------------------------------------------------------------
-- Statuszeile
-- ---------------------------------------------------------------------------

-- Text und Farbschluessel der Statuszeile im Leerlauf.
local function IdleStatus()
   local state = T.State
   -- laeuft ein Stapel (laenger als die Frist einer Meldung), steht das da
   if state and state.Busy and state.Busy() then
      return Fmt(L.WIN_STATUS_APPLYING, S.applyTotal), "blue"
   end
   local n = state and state.PendingCount and state.PendingCount() or 0
   if n > 0 then
      return Fmt(L.WIN_STATUS_PENDING, n), "dim"
   end
   return "", "dim"
end

-- Zeichnet die Statuszeile (Meldung oder Leerlauftext).
local function PaintStatus()
   local f = Window.frame
   if not f or not S.built then
      return
   end
   local text, key = S.statusText, S.statusColor
   if text == nil or text == "" then
      text, key = IdleStatus()
   end
   local r, g, b = Rgb(key)
   f.statusText:SetTextColor(r, g, b)
   f.statusText:SetText(text)
end

-- Loescht die Meldung, sofern es noch dieselbe ist (Token).
local function ClearStatus(token)
   if token ~= S.statusToken then
      return
   end
   S.statusText, S.statusColor = nil, nil
   PaintStatus()
end

-- Zeigt eine zeitlich begrenzte Meldung in der Fusszeile (colorKey aus T.COLORS,
-- z. B. "green", "red", "yellow", "dim"); nach duration s (Standard 6) folgt
-- wieder der Leerlauftext. text = nil/"" nimmt die Meldung sofort weg.
function Window.SetStatus(text, colorKey, duration)
   S.statusToken = S.statusToken + 1
   if text == nil or text == "" then
      S.statusText, S.statusColor = nil, nil
   else
      S.statusText, S.statusColor = tostring(text), colorKey or "text"
      local util = T.Util
      if util and util.After then
         util.After(tonumber(duration) or STATUS_SECONDS, ClearStatus, S.statusToken)
      end
   end
   PaintStatus()
end

-- ---------------------------------------------------------------------------
-- Fuss: Anwenden, Verwerfen, Alles entfernen, Kosten
-- ---------------------------------------------------------------------------

-- Tooltip des Anwenden-Knopfs: Anzahl und je Slot das gewuenschte Aussehen.
local function ApplyTip(tooltip)
   local state = T.State
   if not state then
      return
   end
   local list = state.PendingSlots()
   tooltip:AddLine(Fmt(L.WIN_APPLY_TIP, #list), 1, 1, 1)
   local items = T.Items
   local util = T.Util
   for i = 1, #list do
      local slot = list[i]
      local want = state.Wanted(slot)
      local text, r, g, b
      if want == 0 then
         text = L.WIN_TIP_REMOVE
         r, g, b = Rgb("dim")
      elseif want == (T.HIDDEN_ID or 999999) then
         text = L.WIN_TIP_HIDDEN
         r, g, b = Rgb("pink")
      else
         local info = items and items.Info and items.Info(want)
         text = info and info.name or ("#" .. tostring(want))
         if info and util and util.QualityColor then
            r, g, b = util.QualityColor(info.quality)
         else
            r, g, b = Rgb("text")
         end
      end
      tooltip:AddDoubleLine(SlotLabel(slot), text, 0.78, 0.81, 0.86, r or 1, g or 1, b or 1)
   end
end

-- Kostentext der Fusszeile (leer, wenn nichts aussteht). short = ohne die
-- Beschriftung "Kosten:" (wenn der Platz nicht reicht).
local function CostText(pending, short)
   if pending <= 0 then
      return ""
   end
   local state, util, hex = T.State, T.Util, T.HEX
   local label = short and "" or (hex.dim .. L.WIN_COST .. "|r ")
   local c = state.Cost()
   if c.pending then
      return label .. hex.dim .. L.WIN_COST_PENDING .. "|r"
   end
   if not c.valid then
      return label .. hex.dim .. L.WIN_COST_UNKNOWN .. "|r"
   end
   if c.copper == 0 then
      return label .. hex.green .. L.WIN_COST_FREE .. "|r"
   end
   local color = c.canPurchase and hex.green or hex.red
   return label .. color .. util.FormatMoney(c.copper) .. "|r"
end

-- Gibt es irgendein angewendetes Aussehen (roh vom Server)?
local function AnyApplied()
   local state = T.State
   local list = SlotList()
   for i = 1, #list do
      if state.Applied(list[i]) ~= 0 then
         return true
      end
   end
   return false
end

-- Zeichnet den Fuss neu: Knopfzustaende, Beschriftung, Kosten, Statuszeile.
function Window.RefreshFooter()
   local f = Window.frame
   local state = T.State
   if not f or not S.built or not state then
      return
   end

   local pending = state.PendingCount()

   -- Anwenden
   local ok, reason = state.CanApply()
   local removalsOnly = false
   if pending > 0 then
      removalsOnly = true
      local list = state.PendingSlots()
      for i = 1, #list do
         if state.Wanted(list[i]) ~= 0 then
            removalsOnly = false
            break
         end
      end
   end
   f.btnApply:SetLabel(removalsOnly and L.WIN_APPLY_RESET or L.WIN_APPLY)
   if ok then
      f.btnApply:SetEnabledState(true)
   else
      f.btnApply:SetEnabledState(false, ReasonText(reason))
   end

   -- Verwerfen
   if state.Busy() then
      f.btnDiscard:SetEnabledState(false, L.APPLY_REASON_BUSY)
   elseif pending == 0 then
      f.btnDiscard:SetEnabledState(false, L.WIN_DISCARD_NONE)
   else
      f.btnDiscard:SetEnabledState(true)
   end

   -- Alles entfernen
   local rok, rreason = true, nil
   if state.CanRemoveAll then
      rok, rreason = state.CanRemoveAll()
   end
   if not rok then
      f.btnRemoveAll:SetEnabledState(false, ReasonText(rreason))
   elseif not AnyApplied() then
      f.btnRemoveAll:SetEnabledState(false, L.WIN_REMOVE_ALL_NONE)
   else
      f.btnRemoveAll:SetEnabledState(true)
   end

   -- Kosten: das Feld bekommt die Breite seines Textes (Fuss neu anordnen, wenn
   -- sie sich aendert); reicht der Platz trotzdem nicht, entfaellt die Beschriftung
   local text = CostText(pending, false)
   local need = 0
   if text ~= "" then
      need = ceil(RichWidth(text)) + 6
   end
   if need ~= S.costNeed then
      S.costNeed = need
      if S.metrics then
         LayoutFooter(f, S.metrics)
      end
   end
   if need > 0 and S.costW and need > S.costW then
      text = CostText(pending, true)
   end
   f.costText:SetText(text)

   -- Statuszeile
   PaintStatus()
end

-- Plant das Neuzeichnen des Fusses (entprellt, nur wenn sichtbar; ein
-- verstecktes Fenster zeichnet ihn beim Zeigen, siehe OnShow).
ScheduleFooter = function()
   local f = Window.frame
   if not S.built or not f or not f:IsVisible() then
      return
   end
   Debounce("ui-window", 0.03, Window.RefreshFooter)
end

-- "Verwerfen": alle ausstehenden Aenderungen verwerfen.
local function OnDiscard()
   local state = T.State
   if state then
      state.DiscardAll()
   end
end

-- "Anwenden": State.Apply; ein Fehlschlag erscheint in der Statuszeile.
local function OnApply()
   local state = T.State
   if not state then
      return
   end
   local ok, reason = state.Apply()
   if ok == false and reason then
      Window.SetStatus(ReasonText(reason), "yellow")
   end
end

-- "Alles entfernen": nach Rueckfrage State.RemoveAll.
local function OnRemoveAll()
   local state, skin = T.State, T.UI.Skin
   if not state or not skin then
      return
   end
   local ok, reason = state.CanRemoveAll()
   if not ok then
      Window.SetStatus(ReasonText(reason), "yellow")
      return
   end
   skin.Confirm({
      title = L.WIN_REMOVE_ALL_TITLE,
      text = L.WIN_REMOVE_ALL_TEXT,
      accept = L.WIN_REMOVE_ALL,
      cancel = L.WIN_CANCEL,
      danger = true,
      owner = Window.frame,
      onAccept = function()
         local done, why = state.RemoveAll()
         if done then
            Window.SetStatus(L.WIN_REMOVED_ALL, "green")
         elseif why then
            Window.SetStatus(ReasonText(why), "yellow")
         end
      end,
   })
end

-- Optionsfenster umschalten (Kopfknopf "*").
local function ToggleOptions()
   local opt = Comp("Options")
   if not opt then
      return
   end
   if type(opt.Toggle) == "function" then
      CallComp("Options", "Toggle")
   else
      CallComp("Options", "Open")
   end
end

-- ---------------------------------------------------------------------------
-- Reiter, Slotwahl
-- ---------------------------------------------------------------------------

-- Zeigt/versteckt die Komponenten des rechten Panels gemaess S.tab.
local function ApplyTabVisibility()
   local f = Window.frame
   if not f or not S.built then
      return
   end
   local outfits = S.tab == "outfits"
   f.tabItems:SetSelected(not outfits)
   f.tabOutfits:SetSelected(outfits)

   local function setShown(frame, shown)
      if not frame then return end
      if shown then frame:Show() else frame:Hide() end
   end
   setShown(S.filterFrame, not outfits)
   setShown(S.gridFrame, not outfits)
   local ot = Comp("OutfitsTab")
   if outfits then
      setShown(S.outfitsFrame, true)
      if ot and type(ot.Show) == "function" then
         CallComp("OutfitsTab", "Show")
      end
   else
      if ot and type(ot.Hide) == "function" then
         CallComp("OutfitsTab", "Hide")
      end
      setShown(S.outfitsFrame, false)
   end
end

-- Liefert den aktiven Reiter ("items" | "outfits").
function Window.GetTab()
   return S.tab or "items"
end

-- Wechselt den Reiter (speichert DB.global.lastTab).
function Window.SetTab(tab)
   if tab ~= "outfits" then
      tab = "items"
   end
   local wasItems = (S.tab == "items")
   S.tab = tab
   local g = EnsureDB()
   if g and g.lastTab ~= tab and T.DB.Set then
      T.DB.Set("lastTab", tab)
   end
   if not S.built then
      return
   end
   -- Beim Zurueckwechseln zu "Items": die Zellmodelle verlieren beim Verbergen ihren
   -- Zustand (Spieltest), also unabhaengig vom OnShow-Weg neu ankleiden lassen. Wer schon
   -- auf "Items" steht (Klick auf den aktiven Reiter, Open bei offenem Fenster), behaelt
   -- seine angekleideten Modelle: Neuladen waere nur Flackern und Last.
   if tab == "items" and not wasItems then
      CallComp("Grid", "InvalidateModels")
   end
   ApplyTabVisibility()
   Window.Layout()
   -- Ein verstecktes Fenster holt das beim Zeigen nach (OnShow der Komponenten).
   if Window.frame:IsVisible() then
      if tab == "outfits" then
         CallComp("OutfitsTab", "Refresh")
      else
         CallComp("FilterBar", "Refresh", Window.currentSlot)
         CallComp("Grid", "Refresh")
      end
   end
end

-- Waehlt den Slot (Server-Slot oder nil); gibt Grid, SlotBar, Vorschau und
-- FilterBar Bescheid und merkt ihn in DB.char.lastSlot. Rueckgabe: ob gueltig.
function Window.SelectSlot(slot)
   if slot ~= nil and not ValidSlot(slot) then
      return false
   end
   Window.currentSlot = slot
   local db = T.DB
   if slot ~= nil and db and db.SetChar and db.char and db.char.lastSlot ~= slot then
      db.SetChar("lastSlot", slot)
   end
   if not S.built then
      return true
   end
   CallComp("SlotBar", "Select", slot)
   CallComp("Grid", "SetSlot", slot)
   CallComp("FilterBar", "Refresh", slot)
   CallComp("Preview", "SetFocusSlot", slot)
   return true
end

-- Klick auf einen Slot der SlotBar: Slot waehlen, im Outfit-Reiter zurueck zu "Items".
local function OnSlotClicked(slot)
   Window.SelectSlot(slot)
   if S.tab == "outfits" then
      Window.SetTab("items")
   end
end

-- Die FilterBar meldet eine Aenderung: nur das Layout nachziehen (entprellt).
local function OnFilterChanged()
   Debounce("ui-window-layout", LAYOUT_THROTTLE, Window.Layout)
end

-- ---------------------------------------------------------------------------
-- Groessengriff, Aufloesungsabfrage
-- ---------------------------------------------------------------------------

-- Beendet das Ziehen am Griff: Groesse runden, speichern, Modelle neu laden.
local function StopSizing()
   local f = Window.frame
   if not S.sizing or not f then
      return
   end
   S.sizing = false
   f.grip:SetScript("OnUpdate", nil)
   f:StopMovingOrSizing()
   f:SetUserPlaced(false)

   local g = EnsureDB()
   local w, h = floor((f:GetWidth() or DEF_W) + 0.5), floor((f:GetHeight() or DEF_H) + 0.5)
   local scale = f:GetScale() or 1
   w, h = Window.ClampSize(w, h, scale)
   S.applying = true
   f:SetWidth(w)
   f:SetHeight(h)
   S.applying = false
   if g and (g.width ~= w or g.height ~= h) then
      S.savingSize = true
      T.DB.Set("width", w)
      T.DB.Set("height", h)
      S.savingSize = false
   end
   -- Wuchs das Fenster ueber den Rand, rutscht es zurueck ins Bild (und die
   -- Position wird mitgespeichert).
   Window.SavePosition()
   if T.Util and T.Util.Cancel then
      T.Util.Cancel("ui-window-layout")
      T.Util.Cancel("ui-window-rebuild")
   end
   Window.Layout()
   RebuildModels()
end

-- Beginnt das Ziehen am Griff (StartSizing "BOTTOMRIGHT").
local function StartSizing()
   local f = Window.frame
   if S.sizing or not f then
      return
   end
   S.sizing = true
   f:StartSizing("BOTTOMRIGHT")
   -- Sicherheitsnetz: ein verpasstes OnMouseUp (Alt-Tab) beendet das Ziehen.
   f.grip:SetScript("OnUpdate", function()
      if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
         StopSizing()
      end
   end)
end

-- Fragt die Bildschirmgroesse einmal je Sekunde ab (OnUpdate des Beobachters
-- existiert nur, solange das Fenster sichtbar ist).
local function WatchUpdate(self, elapsed)
   S.watchAcc = (S.watchAcc or 0) + (tonumber(elapsed) or 0)
   if S.watchAcc < WATCH_SECONDS then
      return
   end
   S.watchAcc = 0
   if ScreenSignature() ~= S.screenSig then
      Window.ApplyScale()
   end
end

-- ---------------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------------

-- Texte, die von der Sprache abhaengen (bei Aufbau und LOCALE_CHANGED).
local function ApplyLocale()
   local f = Window.frame
   if not f or not S.built then
      return
   end
   f.head:SetTitle(L.WIN_TITLE)
   f.tabItems:SetLabel(L.WIN_TAB_ITEMS)
   f.tabOutfits:SetLabel(L.WIN_TAB_OUTFITS)
   f.btnOptions.tip = L.WIN_OPTIONS
   f.btnClose.tip = L.WIN_CLOSE
   f.btnDiscard:SetLabel(L.WIN_DISCARD)
   f.btnDiscard.tip = L.WIN_DISCARD_TIP
   f.btnRemoveAll:SetLabel(L.WIN_REMOVE_ALL)
   f.btnRemoveAll.tip = L.WIN_REMOVE_ALL_TIP
   f.grip.tipText = L.WIN_RESIZE_TIP
   S.noticeKind = nil
   Window.RefreshNotice()
   Window.Layout()
   Window.RefreshFooter()
end
Window.ApplyLocale = ApplyLocale

-- Nimmt dem Suchfeld der Filterleiste den Tastaturfokus (3.3.5a laesst ihn bei
-- Klicks auf andere Frames stehen). Die Leiste wird nach diesem Modul geladen:
-- darum spaet gebunden; ohne Leiste oder ohne Fokus tut es nichts.
local function ReleaseSearchFocus()
   local ui = T.UI
   local fb = ui and ui.FilterBar
   if fb and fb.ReleaseFocus then
      fb.ReleaseFocus()
   end
end

-- Kopfzeile: Titel, Reiter, Options- und Schliessen-Knopf.
local function BuildHeader(f, skin)
   local head = skin.Header(f, L.WIN_TITLE, HEADER_H)
   f.head = head

   -- Ziehen am Kopf verschiebt das Fenster
   head:EnableMouse(true)
   head:SetScript("OnMouseDown", ReleaseSearchFocus)
   head:RegisterForDrag("LeftButton")
   head:SetScript("OnDragStart", function()
      f:StartMoving()
   end)
   head:SetScript("OnDragStop", function()
      f:StopMovingOrSizing()
      -- die Position verwaltet das Addon selbst (DB.global.point), nicht das Layout-Cache des Clients
      f:SetUserPlaced(false)
      Window.SavePosition()
   end)

   f.tabItems = skin.Button(head, 90, 22, L.WIN_TAB_ITEMS, function()
      Window.SetTab("items")
   end)
   f.tabOutfits = skin.Button(head, 90, 22, L.WIN_TAB_OUTFITS, function()
      Window.SetTab("outfits")
   end)

   f.btnClose = skin.Button(head, 26, 22, "x", function()
      Window.Close()
   end)
   f.btnClose:SetPoint("TOPRIGHT", head, "TOPRIGHT", -5, -4)
   f.btnClose.tip = L.WIN_CLOSE

   f.btnOptions = skin.Button(head, 26, 22, "*", ToggleOptions)
   f.btnOptions:SetPoint("RIGHT", f.btnClose, "LEFT", -4, 0)
   f.btnOptions.tip = L.WIN_OPTIONS
end

-- Hinweisleiste unter dem Kopf (versteckt, bis sie gebraucht wird).
local function BuildNotice(f, skin)
   local n = CreateFrame("Frame", nil, f)
   n:SetHeight(NOTICE_H)
   n:SetBackdrop({ bgFile = skin.WHITE })
   n:SetBackdropColor(0.91, 0.77, 0.29, 0.14)

   local stripe = n:CreateTexture(nil, "OVERLAY")
   stripe:SetTexture(skin.WHITE)
   stripe:SetPoint("TOPLEFT", n, "TOPLEFT", 0, 0)
   stripe:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", 0, 0)
   stripe:SetWidth(3)
   n.stripe = stripe

   local text = n:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   text:SetPoint("TOPLEFT", n, "TOPLEFT", 12, -4)
   text:SetWidth(400)
   text:SetHeight(14)
   text:SetJustifyH("LEFT")
   n.text = text

   n:Hide()
   f.notice = n
end

-- Panels und Komponenten (SlotBar, Vorschau, FilterBar, Raster, Outfits).
local function BuildPanels(f, skin)
   local col = skin.COL
   local left = skin.Panel(f, { 0.075, 0.085, 0.10, 1 }, col.border)
   f.left = left
   local right = CreateFrame("Frame", nil, f)
   f.right = right

   -- Meldungen des Outfit-Reiters in der Fusszeile
   local ot = Comp("OutfitsTab")
   if ot then
      ot.onStatus = function(text, colorKey)
         Window.SetStatus(text, colorKey)
      end
   end

   S.bar = MakeComp("SlotBar", left, OnSlotClicked)
   S.preview = MakeComp("Preview", left)
   S.filterFrame = MakeComp("FilterBar", right, OnFilterChanged)
   S.gridFrame = MakeComp("Grid", right)
   S.outfitsFrame = MakeComp("OutfitsTab", right)
end

-- Fuss: Verwerfen, Alles entfernen, Status, Kosten, Anwenden.
local function BuildFooter(f, skin)
   local col = skin.COL
   local foot = CreateFrame("Frame", nil, f)
   foot:SetBackdrop({ bgFile = skin.WHITE })
   foot:SetBackdropColor(col.head[1], col.head[2], col.head[3], 1)
   local line = skin.Divider(foot, col.border[1], col.border[2], col.border[3], 0.9)
   line:SetPoint("TOPLEFT", foot, "TOPLEFT", 0, 0)
   line:SetPoint("TOPRIGHT", foot, "TOPRIGHT", 0, 0)
   f.footer = foot

   f.btnDiscard = skin.Button(foot, 90, BUTTON_H, L.WIN_DISCARD, OnDiscard)
   f.btnDiscard.tip = L.WIN_DISCARD_TIP
   f.btnRemoveAll = skin.Button(foot, 110, BUTTON_H, L.WIN_REMOVE_ALL, OnRemoveAll)
   f.btnRemoveAll.tip = L.WIN_REMOVE_ALL_TIP

   f.btnApply = skin.Button(foot, 150, BUTTON_H, L.WIN_APPLY, OnApply)
   f.btnApply:SetTheme("primary")
   f.btnApply.tip = ApplyTip

   local status = foot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   status:SetWidth(200)
   status:SetHeight(14)
   status:SetJustifyH("LEFT")
   f.statusText = status

   local cost = foot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   cost:SetWidth(170)
   cost:SetHeight(14)
   cost:SetJustifyH("RIGHT")
   cost:SetText("")
   f.costText = cost
end

-- Griff zum Aendern der Groesse (unten rechts).
local function BuildGrip(f)
   local grip = CreateFrame("Button", nil, f)
   grip:SetWidth(GRIP_SIZE)
   grip:SetHeight(GRIP_SIZE)
   grip:SetFrameLevel(f:GetFrameLevel() + 40)
   grip:EnableMouse(true)
   grip:SetNormalTexture(GRIP_UP)
   grip:SetPushedTexture(GRIP_DOWN)
   grip:SetHighlightTexture(GRIP_HIGHLIGHT, "ADD")
   f.grip = grip

   grip:SetScript("OnMouseDown", function(_, button)
      if button == "LeftButton" then
         StartSizing()
      end
   end)
   grip:SetScript("OnMouseUp", function(_, button)
      if button == "LeftButton" or S.sizing then
         StopSizing()
      end
   end)
   grip:SetScript("OnHide", function()
      StopSizing()
   end)
   grip:SetScript("OnEnter", function(self)
      local skin = T.UI.Skin
      if skin and self.tipText then
         skin.Tooltip(self, "ANCHOR_TOPLEFT", { self.tipText })
      end
   end)
   grip:SetScript("OnLeave", function(self)
      local skin = T.UI.Skin
      if skin then
         skin.HideTooltip(self)
      end
   end)
end

-- Fenster verbergen: NPC-Gossip schliessen, Zustand zuruecksetzen, Menues/Dialoge zu.
local function OnHide()
   local f = Window.frame
   local state = T.State
   S.watchAcc = 0
   if f and f.watcher then
      f.watcher:SetScript("OnUpdate", nil)
   end
   StopSizing()

   -- Versteckt nur der Elternrahmen (UI mit Alt-Z ausgeblendet), ist das Fenster
   -- selbst weiter "gezeigt": der Zustand (NPC, Transmogrifizierer) bleibt.
   if f and f:IsShown() then
      return
   end

   local byNpc = state and state.openedByNpc
   if state then
      state.openedByNpc = false
   end
   if byNpc and type(CloseGossip) == "function" then
      local ok, err = pcall(CloseGossip)
      if not ok then
         ReportError("CloseGossip: " .. tostring(err))
      end
   end
   if state and state.SetVendor then
      state.SetVendor(false)
   end

   local skin = T.UI.Skin
   if skin then
      if skin.Menu and skin.Menu.Close then skin.Menu.Close() end
      if skin.CloseDialog then skin.CloseDialog() end
   end
   CallComp("Options", "Close")
end

-- Fenster zeigen: Beobachter starten, Fuss/Hinweis aktualisieren.
local function OnShow()
   local f = Window.frame
   if not f or not S.built then
      return
   end
   S.watchAcc = 0
   f.watcher:SetScript("OnUpdate", WatchUpdate)
   if S.screenSig ~= ScreenSignature() then
      Window.ApplyScale()
   end
   -- Scale/Groesse haben sich im verborgenen Zustand geaendert: Modelle neu laden
   if S.rebuildPending then
      ScheduleRebuild()
   end
   S.everShown = true
   Window.RefreshNotice()
   Window.RefreshFooter()
end

-- Baut das gesamte Fenster (einmalig). Rueckgabe: der Rahmen oder nil.
local function Build()
   local skin = T.UI.Skin
   if S.built then
      return Window.frame
   end
   if S.failed or not skin or type(CreateFrame) ~= "function" or not UIParent then
      return nil
   end

   -- Alles, was beim Aufbau werfen kann, steht im pcall: auch der Rahmen selbst
   -- und sein Hintergrund. Ein Fehler setzt S.failed (der Aufbau wird nicht
   -- wiederholt: der halbe Rahmen und seine Komponenten blieben sonst stehen,
   -- und die Create-Funktionen sind nicht wiederholbar).
   local f
   local ok, err = pcall(function()
      f = CreateFrame("Frame", "TransmogWindow", UIParent)
      Window.frame = f
      f:Hide()
      f:SetFrameStrata("HIGH")
      f:SetToplevel(true)
      f:SetClampedToScreen(true)
      f:SetMovable(true)
      f:SetResizable(true)
      f:EnableMouse(true)
      -- Klick auf die nackte Flaeche des Fensters: Suchfeld verliert den Fokus
      f:SetScript("OnMouseDown", ReleaseSearchFocus)
      f:SetWidth(DEF_W)
      f:SetHeight(DEF_H)
      f:SetMinResize(MIN_W, MIN_H)
      skin.Backdrop(f, skin.COL.bg, skin.COL.border)
      BuildHeader(f, skin)
      BuildNotice(f, skin)
      BuildPanels(f, skin)
      BuildFooter(f, skin)
      BuildGrip(f)
      f.watcher = CreateFrame("Frame", nil, f)
   end)
   if not ok then
      S.failed = true
      ReportError("Aufbau: " .. tostring(err))
      -- einmal je Sitzung (S.failed haelt), auch beim NPC-Besuch, wo Boot nur
      -- das nil sieht und das normale Gossip-Fenster stehen laesst
      PrintError(L.BOOT_INIT_FAILED, "Window")
      return nil
   end

   -- ESC schliesst das Fenster
   if type(UISpecialFrames) == "table" then
      local found = false
      for i = 1, #UISpecialFrames do
         if UISpecialFrames[i] == "TransmogWindow" then
            found = true
         end
      end
      if not found then
         tinsert(UISpecialFrames, "TransmogWindow")
      end
   end

   f:SetScript("OnSizeChanged", OnSizeChanged)
   f:SetScript("OnShow", OnShow)
   f:SetScript("OnHide", OnHide)

   -- Methoden auch als Frame-Felder (Doppelpunkt-Aufruf, SPEC 11.1); die
   -- Standardmethoden des Frames (IsShown, Show, Hide ...) bleiben unberuehrt.
   f.Open = function(_, opts) return Window.Open(opts) end
   f.Close = function() return Window.Close() end
   f.Toggle = function() return Window.Toggle() end
   f.Layout = function() return Window.Layout() end
   f.SetTab = function(_, tab) return Window.SetTab(tab) end
   f.SelectSlot = function(_, slot) return Window.SelectSlot(slot) end
   f.RefreshAll = function() return Window.RefreshAll() end
   f.SetStatus = function(_, text, colorKey, duration) return Window.SetStatus(text, colorKey, duration) end
   f.ApplyScale = function() return Window.ApplyScale() end
   f.ResetLayout = function() return Window.ResetLayout() end

   S.built = true
   ApplyTabVisibility()
   Window.ApplyScale()
   ApplyLocale()
   return f
end

-- Baut das Fenster, falls noch nicht geschehen (Rueckgabe: Rahmen oder nil).
function Window.Create()
   EnsureDB()
   return Build()
end

-- ---------------------------------------------------------------------------
-- Oeffnen, Schliessen
-- ---------------------------------------------------------------------------

-- Ist der Slot bereit (angelegt und transmogbar)?
local function SlotReady(slot)
   local state = T.State
   return ValidSlot(slot) and state ~= nil and state.SlotState(slot) == "READY"
end

-- Waehlt den Startslot: opts.slot, sonst DB.char.lastSlot (wenn bereit), sonst
-- der erste bereite Slot in Anzeigereihenfolge, sonst nil.
local function PickSlot(opts)
   if opts.slot ~= nil and ValidSlot(opts.slot) then
      return opts.slot
   end
   local db = T.DB
   local last = db and db.char and db.char.lastSlot
   if last ~= nil and SlotReady(last) then
      return last
   end
   local list = SlotList()
   for i = 1, #list do
      if SlotReady(list[i]) then
         return list[i]
      end
   end
   return nil
end

-- Oeffnet das Fenster. opts = { fromNpc = bool, tab = "items"|"outfits", slot = server }.
-- fromNpc: Fenster per NPC-Gossip geoeffnet (Transmogrifizierer in Reichweite);
-- sonst ohne NPC: Vorschau-Modus nur bei ausgeschalteter Option allowAnywhere (seit 2.1
-- standardmaessig an, dann wendet das Fenster auch ohne NPC an). Rueckgabe: true wenn offen.
function Window.Open(opts)
   if type(opts) ~= "table" then
      opts = {}
   end
   local wasFailed = S.failed
   local f = Window.Create()
   if not f then
      -- Ohne Fenster bliebe /transmog stumm. Der Aufbaufehler selbst ist beim
      -- ersten Mal schon gemeldet (Build); jeder weitere Versuch bekommt die
      -- kurze Zeile, ebenso ein Fenster, das gar nicht erst gebaut werden kann.
      if wasFailed or not S.failed then
         PrintError("%s", L.BOOT_UNAVAILABLE)
      end
      return false
   end
   local state = T.State
   local fromNpc = opts.fromNpc and true or false
   if state then
      state.openedByNpc = fromNpc
      if state.SetVendor then
         state.SetVendor(fromNpc)
      end
   end
   Window.openedAt = Now()
   if state and state.Refresh then
      state.Refresh()
   end

   local slot = PickSlot(opts)
   local g = Globals()
   local tab = opts.tab or (g and g.lastTab) or "items"
   Window.SetTab(tab)
   Window.SelectSlot(slot)
   Window.RefreshNotice()
   if not f:IsShown() then
      CallComp("Grid", "InvalidateModels")
      f:Show()
   else
      Window.RefreshFooter()
   end
   return true
end

-- Schliesst das Fenster (OnHide raeumt auf).
function Window.Close()
   local f = Window.frame
   if f and f:IsShown() then
      f:Hide()
   end
end

-- Schaltet das Fenster um; geoeffnet wird ohne NPC (fromNpc = false; Vorschau-Modus nur bei ausgeschalteter Option allowAnywhere).
function Window.Toggle()
   if Window.IsShown() then
      Window.Close()
   else
      Window.Open({ fromNpc = false })
   end
end

-- true, wenn das Fenster gebaut und sichtbar ist.
function Window.IsShown()
   local f = Window.frame
   return f ~= nil and f:IsShown() and true or false
end

-- Zeichnet alle Komponenten neu (Layout, SlotBar, Vorschau, aktiver Reiter, Fuss).
function Window.RefreshAll()
   if not S.built then
      return
   end
   Window.Layout()
   Window.RefreshNotice()
   CallComp("SlotBar", "Refresh", nil)
   CallComp("Preview", "Refresh")
   if S.tab == "outfits" then
      CallComp("OutfitsTab", "Refresh")
   else
      CallComp("FilterBar", "Refresh", Window.currentSlot)
      CallComp("Grid", "Refresh")
   end
   Window.RefreshFooter()
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

-- Kosten, Auswahl oder Status haben sich geaendert: Fuss entprellt neu zeichnen.
local function OnFooterEvent()
   ScheduleFooter()
end

-- Transmogrifizierer in Reichweite / Server-Zustand: Hinweis und Fuss.
local function OnNoticeEvent()
   if not S.built then
      return
   end
   Window.RefreshNotice()
   ScheduleFooter()
end

-- Ein Stapel wird angewendet: Status und Fuss (Anwenden gesperrt).
local function OnApplyStarted(total)
   S.applyTotal = tonumber(total) or 0
   S.failedSlot = nil
   if not IsUp() then
      return
   end
   Window.SetStatus(Fmt(L.WIN_STATUS_APPLYING, S.applyTotal), "blue")
   ScheduleFooter()
end

-- Ergebnis einer Operation: Slot blinkt, Fehlschlag steht in der Statuszeile.
local function OnApplyProgress(slot, ok)
   if not ok then
      S.failedSlot = slot
   end
   if not IsUp() then
      return
   end
   CallComp("SlotBar", "Flash", slot, ok and true or false)
   if not ok then
      Window.SetStatus(Fmt(L.MSG_APPLY_SLOT_FAILED, SlotLabel(slot)), "red")
   end
   ScheduleFooter()
end

-- Text und Farbschluessel der Zusammenfassung eines Stapels (nil: nichts geschah).
-- Scheitert genau die eine Operation, nennt die Meldung den Slot.
local function ResultText(nOk, nFail)
   if nFail > 0 then
      if nOk == 0 and nFail == 1 and S.failedSlot ~= nil then
         return Fmt(L.MSG_APPLY_SLOT_FAILED, SlotLabel(S.failedSlot)), "red"
      end
      return Fmt(L.MSG_APPLY_DONE, nOk, nFail), nOk > 0 and "yellow" or "red"
   elseif nOk > 0 then
      return L.MSG_APPLY_OK, "green"
   end
   return nil, nil
end

-- Stapel beendet: Ton (bei Erfolg und DB.global.sound), Zusammenfassung.
local function OnApplyDone(nOk, nFail)
   nOk, nFail = tonumber(nOk) or 0, tonumber(nFail) or 0
   -- Das Spielermodell aendert sich erst, wenn die Aktualisierung des Servers
   -- eintrifft (meist vor, manchmal nach dem Ergebnis): nach dem Anwenden alle
   -- Modelle noch einmal neu laden (zusaetzlich zu UNIT_MODEL_CHANGED).
   if nOk > 0 then
      ScheduleRebuild(0.8)
   end
   local g = Globals()
   if nOk > 0 and g and g.sound and type(PlaySound) == "function" then
      pcall(PlaySound, SOUND_APPLY)
   end
   local text, key = ResultText(nOk, nFail)
   S.failedSlot = nil
   if not IsUp() then
      -- Das Fenster wurde waehrend des Anwendens geschlossen: State schreibt dann
      -- nicht in den Chat (Window.Init setzt chatMessages = false), das Ergebnis
      -- soll aber nicht verloren gehen. Schreibt State selbst, bleibt es dabei.
      local util, state = T.Util, T.State
      if text and util and util.Print and not (state and state.chatMessages) then
         util.Print("%s", text)
      end
      return
   end
   Window.SetStatus(text, key)         -- ohne Ergebnis: "Wird angewendet" nicht stehen lassen
   ScheduleFooter()
end

-- Das Modell des Spielers hat sich geaendert (angelegte Gegenstaende, Transmogrifikation
-- vom Server, Verwandlung). Ein DressUpModel mit SetUnit("player") laedt dann nicht von
-- selbst nach; Blizzards Charakterfenster ruft bei UNIT_MODEL_CHANGED deshalb erneut
-- SetUnit("player"). Ohne das zeigten grosse Vorschau und Handslot-Kacheln Aenderungen
-- erst nach dem naechsten Oeffnen richtig (Spieltest 2026-10-12).
local function OnUnitModelChanged(_, unit)
   if unit ~= nil and unit ~= "player" then
      return
   end
   ScheduleRebuild(0.35)
end

-- Einstellungen: Scale/Groesse/Position neu anwenden, allowAnywhere -> Hinweis.
local function OnSettings(key)
   if key == "scale" or key == "width" or key == "height" then
      if not S.savingSize and S.built then
         Window.ApplyScale()
      end
   elseif key == "point" then
      if not S.savingPoint and S.built then
         Window.RestorePosition()
      end
   elseif key == "allowAnywhere" then
      if S.built then
         Window.RefreshNotice()
         ScheduleFooter()
      end
   end
end

-- Sprachwechsel: statische Texte neu setzen.
local function OnLocaleChanged()
   ApplyLocale()
end

-- Registriert die Ereignisse und schaltet die Chatmeldungen von State ab (die
-- Oberflaeche zeigt Ergebnisse in der Statuszeile). Baut das Fenster NICHT.
function Window.Init()
   local state = T.State
   if state then
      state.chatMessages = false
   end
   local ev = T.Events
   if not ev or not ev.On then
      return
   end
   ev.On("COST_CHANGED", OnFooterEvent, Window)
   ev.On("WANTED_CHANGED", OnFooterEvent, Window)
   ev.On("STATUS_CHANGED", OnFooterEvent, Window)
   ev.On("VENDOR_CHANGED", OnNoticeEvent, Window)
   ev.On("SERVER_STATE", OnNoticeEvent, Window)
   ev.On("APPLY_STARTED", OnApplyStarted, Window)
   ev.On("APPLY_PROGRESS", OnApplyProgress, Window)
   ev.On("APPLY_DONE", OnApplyDone, Window)
   ev.On("SETTINGS_CHANGED", OnSettings, Window)
   ev.On("LOCALE_CHANGED", OnLocaleChanged, Window)
   if ev.Game then
      ev.Game("UNIT_MODEL_CHANGED", OnUnitModelChanged)
   end
end
