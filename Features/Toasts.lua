-- Toasts.lua  (T.Toasts)
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Meldekarten fuer neu freigeschaltete Aussehen.
--
-- Eine Karte (260 x 52, flach): Qualitaetsstreifen links, Symbol 36 x 36,
-- Titelzeile "Neues Aussehen freigeschaltet" (Akzentfarbe) und der Name in
-- Qualitaetsfarbe. Einblenden 0,2 s, Stehen 4 s, Ausblenden 0,4 s. Die Karten
-- haengen untereinander an einem Anker; hoechstens 3 sind gleichzeitig zu
-- sehen, der Rest wartet in einer Warteschlange. Karten werden wiederverwendet.
--
-- Ausloeser: COLLECTION_UPDATED(id). Nicht beachtet wird es bei abgeschalteter
-- Einstellung (DB.global.toasts) und waehrend des Login-Sweeps (T.IsLoginSweep).
--
-- Warten auf Iteninfo: Items.Request(id); die Karte erscheint, sobald die Info
-- da ist, spaetestens nach 3 s (dann mit "Item <id>"; ein spaeter eintreffender
-- Name wird in die sichtbare Karte nachgetragen). Ein kurzes Sammelfenster
-- (0,25 s) vor dem ersten Zeigen faengt Bursts auf, ohne dass Karten flackern.
--
-- Bursts: kommen innerhalb von 2 s mindestens 4 Ereignisse, werden die noch
-- nicht gezeigten Einzelkarten verworfen, sichtbare Einzelkarten blenden
-- schnell aus, und EINE Sammelkarte "Aussehen: n" ersetzt sie. Weitere
-- Ereignisse, die jeweils innerhalb von 2 s nach dem vorigen kommen, zaehlen
-- in dieser Karte hoch.
--
-- Iteninfo: nur Einzelkarten fordern sie an; Ereignisse, die in einer
-- Sammelkarte aufgehen, kosten keine Abfrage (grosse Sweeps).
--
-- OnUpdate: nur ein Treiberframe, und der ist versteckt, solange weder Karten
-- zu sehen noch welche in der Warteschlange sind. Ein Fehler im Takt legt ihn
-- schlafen, meldet ihn einmal und raeumt alle Karten weg (nichts bleibt halb
-- animiert stehen); der naechste Toast weckt ihn wieder.
--
-- Anker: kleiner Rahmen (140 x 24), per Ziehen verschiebbar; die Position steht
-- in DB.global.toastPoint = { point, relPoint, x, y }. Standard: TOP von
-- UIParent, 120 nach unten. Rechtsklick auf den Anker setzt die Position zurueck.
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog
T.Toasts = T.Toasts or {}
local Toasts = T.Toasts

local L = T.L

local min, abs = math.min, math.abs
local tremove = table.remove
local type, pairs, pcall, tonumber = type, pairs, pcall, tonumber

-- ---------------------------------------------------------------------------
-- Konstanten
-- ---------------------------------------------------------------------------

local WHITE = "Interface\\Buttons\\WHITE8X8"
local STAR_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Karte
local CARD_W, CARD_H = 260, 52
local ICON_SIZE = 36
local STRIPE_W = 3
local PAD = 8
local CARD_GAP = 6                     -- Abstand zwischen zwei Karten
local TOP_GAP = 6                      -- Abstand der ersten Karte unter dem Anker
local TEXT_X = 1 + STRIPE_W + PAD + ICON_SIZE + PAD
local TEXT_W = CARD_W - TEXT_X - PAD - 1

-- Anker
local ANCHOR_W, ANCHOR_H = 140, 24
local DEFAULT_POINT, DEFAULT_Y = "TOP", -120

-- Zeiten und Grenzen
local MAX_VISIBLE = 3
local MAX_QUEUE = 8                    -- darueber wird die Warteschlange zusammengefasst
local FADE_IN = 0.2
local STAY = 4
local FADE_OUT = 0.4
local FAST_OUT = 0.15                  -- ersetzte oder weggeklickte Karte
local SLIDE_RATE = 14                  -- 1/s: Geschwindigkeit beim Aufruecken
local INFO_WAIT = 3                    -- s Wartezeit auf die Iteninfo
local SETTLE = 0.25                    -- s Sammelfenster vor dem ersten Zeigen
local BURST_COUNT = 4                  -- ab so vielen Ereignissen ...
local BURST_WINDOW = 2                 -- ... innerhalb so vieler Sekunden: Sammelkarte
local TEST_ID = 19019                  -- bekannter Gegenstand fuer Probekarten

-- Farben, soweit nicht aus T.COLORS
local BG = { 0.055, 0.062, 0.075, 0.94 }
local BORDER = { 0.22, 0.25, 0.30, 1 }

-- ---------------------------------------------------------------------------
-- Zustand
-- ---------------------------------------------------------------------------

local queue = {}       -- wartende Eintraege { id=|burst=true, count=, showAt=, deadline=, stamp=, sticky= }
local active = {}      -- sichtbare Karten, die oberste zuerst
local pool = {}        -- freie Karten
local created = 0      -- bisher gebaute Karten
local stamps = {}      -- Zeitpunkte der letzten Einzelereignisse
local burst = nil      -- laufende Sammelkarte { count=, last=, entry= }
local driver = nil     -- Treiberframe (OnUpdate nur solange etwas zu tun ist)
local anchor = nil     -- Ankerrahmen

-- ---------------------------------------------------------------------------
-- Kleine Helfer
-- ---------------------------------------------------------------------------

-- Farbe {r, g, b} aus T.COLORS, sonst der angegebene Ersatz.
local function Color(name, fallback)
   local c = type(T.COLORS) == "table" and T.COLORS[name] or nil
   if type(c) == "table" and type(c[1]) == "number" then
      return c
   end
   return fallback
end

-- true, solange die Benachrichtigungen nicht abgeschaltet sind (ohne DB: false).
local function Enabled()
   local db = T.DB
   local g = type(db) == "table" and db.global or nil
   return type(g) == "table" and g.toasts ~= false
end

-- Flachrahmen aus Skin.Backdrop; ohne Skin ein gleichwertiger eigener.
local function Flat(frame, bg, border)
   local skin = T.UI and T.UI.Skin
   if skin and skin.Backdrop then
      skin.Backdrop(frame, bg, border)
      return
   end
   frame:SetBackdrop({
      bgFile = WHITE, edgeFile = WHITE, tile = false, edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
   })
   frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
   frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

-- Symbol setzen: beschnitten (Skin.TrimIcon) oder, mit noTrim, ganz.
local function SetIcon(texture, path, noTrim)
   texture:SetTexture(path)
   local skin = T.UI and T.UI.Skin
   if noTrim then
      texture:SetTexCoord(0, 1, 0, 1)
   elseif skin and skin.TrimIcon then
      skin.TrimIcon(texture)
   else
      texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
   end
end

-- Tooltips des GameTooltip zeigen/verbergen (nur wenn er dem Rahmen gehoert).
local function ShowTip(owner, where, lines)
   if not GameTooltip then
      return
   end
   GameTooltip:SetOwner(owner, where)
   for i = 1, #lines do
      local line = lines[i]
      if i == 1 then
         GameTooltip:AddLine(line, 1, 1, 1)
      else
         GameTooltip:AddLine(line, 0.78, 0.81, 0.86, true)
      end
   end
   GameTooltip:Show()
end

local function HideTip(owner)
   if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then
      GameTooltip:Hide()
   end
end

-- ---------------------------------------------------------------------------
-- Anker
-- ---------------------------------------------------------------------------

-- Setzt den Anker an die gespeicherte (oder die Standard-)Position.
local function ApplyPosition()
   if not anchor then
      return
   end
   local db = T.DB
   local g = type(db) == "table" and db.global or nil
   local p = type(g) == "table" and g.toastPoint or nil

   local point, relPoint, x, y
   if type(p) == "table" then
      point = p[1] or p.point
      relPoint = p[2] or p.relPoint
      x = p[3] or p.x
      y = p[4] or p.y
   end

   anchor:ClearAllPoints()
   if type(point) == "string" and type(x) == "number" and type(y) == "number" then
      if type(relPoint) ~= "string" then
         relPoint = point
      end
      if pcall(anchor.SetPoint, anchor, point, UIParent, relPoint, x, y) then
         return
      end
      anchor:ClearAllPoints()
   end
   anchor:SetPoint(DEFAULT_POINT, UIParent, DEFAULT_POINT, 0, DEFAULT_Y)
end

-- Merkt sich die Position nach dem Ziehen (DB.global.toastPoint).
local function SavePosition()
   if not anchor then
      return
   end
   local point, rel, relPoint, x, y = anchor:GetPoint(1)
   if type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then
      return
   end
   if rel ~= nil and rel ~= UIParent then
      ApplyPosition()   -- fremder Bezugsrahmen: gespeicherten Stand wiederherstellen
      return
   end
   local util = T.Util
   if util and util.Round then
      x, y = util.Round(x), util.Round(y)
   end
   if T.DB and T.DB.Set then
      T.DB.Set("toastPoint", { point, relPoint or point, x, y })
   end
   ApplyPosition()
end

-- Baut den Anker einmal; er bleibt verborgen, bis ShowAnchor ihn zeigt.
local function EnsureAnchor()
   if anchor then
      return anchor
   end
   if type(CreateFrame) ~= "function" then
      return nil
   end

   local accent = Color("accent", { 0.20, 0.62, 0.92 })
   local text = Color("text", { 0.86, 0.88, 0.92 })

   local f = CreateFrame("Frame", "TransmogToastAnchor", UIParent)
   f:SetFrameStrata("DIALOG")
   f:SetWidth(ANCHOR_W)
   f:SetHeight(ANCHOR_H)
   f:SetClampedToScreen(true)
   f:SetMovable(true)
   f:EnableMouse(true)
   f:RegisterForDrag("LeftButton")
   Flat(f, BG, { accent[1], accent[2], accent[3], 1 })

   local stripe = f:CreateTexture(nil, "ARTWORK")
   stripe:SetTexture(WHITE)
   stripe:SetVertexColor(accent[1], accent[2], accent[3], 1)
   stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
   stripe:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
   stripe:SetWidth(STRIPE_W)

   local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
   label:SetPoint("LEFT", f, "LEFT", 1 + STRIPE_W + PAD, 0)
   label:SetWidth(ANCHOR_W - (1 + STRIPE_W + PAD) - 26)
   label:SetHeight(12)
   label:SetJustifyH("LEFT")
   label:SetTextColor(text[1], text[2], text[3])
   label:SetText(L.TOAST_ANCHOR_LABEL)
   f.label = label

   -- Schliessen: flacher Knopf mit "x"
   local skin = T.UI and T.UI.Skin
   if skin and skin.Button then
      local close = skin.Button(f, 18, 18, "x", function()
         Toasts.HideAnchor()
      end)
      close:SetPoint("RIGHT", f, "RIGHT", -3, 0)
      close.tip = function(tooltip)
         local util = T.Util
         tooltip:AddLine(util and util.G("CLOSE", "Close") or "Close", 1, 1, 1)
      end
      f.close = close
   end

   f:SetScript("OnDragStart", function(self)
      self:StartMoving()
   end)
   f:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      self:SetUserPlaced(false)   -- die Position verwaltet DB.global.toastPoint
      SavePosition()
   end)
   f:SetScript("OnMouseUp", function(_, button)
      if button == "RightButton" then
         Toasts.ResetPosition()
      end
   end)
   f:SetScript("OnEnter", function(self)
      ShowTip(self, "ANCHOR_TOP", {
         L.TOAST_ANCHOR_TIP_TITLE, L.TOAST_ANCHOR_TIP_DRAG, L.TOAST_ANCHOR_TIP_RESET,
      })
   end)
   f:SetScript("OnLeave", function(self)
      HideTip(self)
   end)
   f:SetScript("OnHide", function(self)
      HideTip(self)
   end)

   f:Hide()
   anchor = f
   ApplyPosition()
   return f
end

-- true, solange der Anker sichtbar ist (Positionsmodus).
local function AnchorShown()
   return anchor ~= nil and anchor:IsShown() and true or false
end

-- ---------------------------------------------------------------------------
-- Karten
-- ---------------------------------------------------------------------------

local Step   -- Vorwaertsdeklaration (Treiber)

-- Beschriftung, Farben und Symbol einer Karte aus ihrem Eintrag setzen.
local function Paint(card)
   local e = card.entry
   if not e then
      return
   end

   local util, items = T.Util, T.Items
   local text = Color("text", { 0.86, 0.88, 0.92 })
   local r, g, b
   local nr, ng, nb = text[1], text[2], text[3]
   local title, name, icon, noTrim

   if e.burst then
      local pink = Color("pink", { 0.96, 0.44, 0.96 })
      r, g, b = pink[1], pink[2], pink[3]
      title = L.TOAST_BURST_TITLE
      name = util.Format(L.TOAST_BURST_COUNT, e.count or 0)
      icon, noTrim = STAR_ICON, true
      card.resolved = true
   else
      title = L.TOAST_TITLE
      local info = type(items) == "table" and items.Info and items.Info(e.id) or nil
      if type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
         r, g, b = util.QualityColor(info.quality)
         nr, ng, nb = r, g, b
         name = info.name
         icon = info.icon
         card.resolved = true
      else
         local accent = Color("accent", { 0.20, 0.62, 0.92 })
         r, g, b = accent[1], accent[2], accent[3]
         name = util.Format(L.TOAST_ITEM_UNKNOWN, e.id or 0)
         card.resolved = false
      end
      if type(icon) ~= "string" or icon == "" then
         icon = UNKNOWN_ICON
      end
   end

   card.stripe:SetVertexColor(r, g, b, 1)
   card.iconBack:SetVertexColor(r, g, b, 1)
   SetIcon(card.icon, icon, noTrim)
   card.title:SetText(title)
   card.name:SetText(name)
   card.name:SetTextColor(nr, ng, nb)
end

-- Karte ausblenden lassen (dur Sekunden); beendet die Karte nicht sofort.
local function BeginOut(card, dur)
   if card.state == "out" then
      return
   end
   card.state = "out"
   card.t = 0
   card.dur = dur
   card.fromAlpha = card:GetAlpha() or 1
end

-- Baut eine neue Karte (nur wenn der Pool leer ist).
local function BuildCard()
   local accent = Color("accent", { 0.20, 0.62, 0.92 })
   local text = Color("text", { 0.86, 0.88, 0.92 })

   local card = CreateFrame("Frame", nil, UIParent)
   card:SetFrameStrata("DIALOG")
   card:SetWidth(CARD_W)
   card:SetHeight(CARD_H)
   card:EnableMouse(true)
   Flat(card, BG, BORDER)

   local stripe = card:CreateTexture(nil, "ARTWORK")
   stripe:SetTexture(WHITE)
   stripe:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
   stripe:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
   stripe:SetWidth(STRIPE_W)
   card.stripe = stripe

   -- 1-px-Rahmen in Qualitaetsfarbe hinter dem Symbol
   local iconBack = card:CreateTexture(nil, "BORDER")
   iconBack:SetTexture(WHITE)
   iconBack:SetWidth(ICON_SIZE + 2)
   iconBack:SetHeight(ICON_SIZE + 2)
   iconBack:SetPoint("LEFT", card, "LEFT", TEXT_X - PAD - ICON_SIZE - 1, 0)
   card.iconBack = iconBack

   local icon = card:CreateTexture(nil, "ARTWORK")
   icon:SetWidth(ICON_SIZE)
   icon:SetHeight(ICON_SIZE)
   icon:SetPoint("CENTER", iconBack, "CENTER", 0, 0)
   card.icon = icon

   local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   title:SetPoint("TOPLEFT", card, "TOPLEFT", TEXT_X, -10)
   title:SetWidth(TEXT_W)
   title:SetHeight(12)
   title:SetJustifyH("LEFT")
   title:SetTextColor(accent[1], accent[2], accent[3])
   card.title = title

   local name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
   name:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
   name:SetWidth(TEXT_W)
   name:SetHeight(16)
   name:SetJustifyH("LEFT")
   name:SetTextColor(text[1], text[2], text[3])
   card.name = name

   card:SetScript("OnEnter", function(self)
      self.hover = true
      if self.itemId and GameTooltip then
         GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
         GameTooltip:SetHyperlink("item:" .. self.itemId)
         GameTooltip:Show()
      end
   end)
   card:SetScript("OnLeave", function(self)
      self.hover = false
      HideTip(self)
   end)
   card:SetScript("OnHide", function(self)
      self.hover = false
      HideTip(self)
   end)
   card:SetScript("OnMouseUp", function(self)
      -- ein Klick schliesst die Karte
      if self.entry and self.state ~= "out" then
         BeginOut(self, FAST_OUT)
      end
   end)

   card:Hide()
   created = created + 1
   return card
end

-- Zielplaetze der Karten neu berechnen (die oberste ist active[1]).
local function Restack()
   for i = 1, #active do
      active[i].ty = -(TOP_GAP + (i - 1) * (CARD_H + CARD_GAP))
   end
end

-- Zeigt einen Eintrag der Warteschlange als Karte (Platz ist garantiert).
local function Spawn(e)
   local a = EnsureAnchor()
   if not a then
      return
   end
   local card = tremove(pool) or BuildCard()
   card.entry = e
   e.card = card
   e.spawned = true
   card.itemId = e.id   -- Sammelkarten haben keine ID
   card.sticky = e.sticky and true or false
   card.hover = false
   card.state, card.t = "in", 0

   active[#active + 1] = card
   Restack()
   card.y = card.ty

   Paint(card)
   card:SetAlpha(0)
   card:ClearAllPoints()
   card:SetPoint("TOP", a, "BOTTOM", 0, card.y)
   card:Show()
end

-- Nimmt die Karte an Stelle index aus der Anzeige und legt sie in den Pool.
local function Release(index)
   local card = tremove(active, index)
   if not card then
      return
   end
   card:Hide()
   local e = card.entry
   if e and e.card == card then
      e.card = nil
   end
   card.entry, card.itemId, card.state = nil, nil, nil
   card.hover, card.sticky = false, false
   pool[#pool + 1] = card
end

-- true, wenn der Eintrag gezeigt werden darf (Sammelzeit um, Info da oder Frist um).
local function Ready(e, now)
   if e.showAt and now < e.showAt then
      return false
   end
   if e.burst or now >= (e.deadline or 0) then
      return true
   end
   local items = T.Items
   return type(items) == "table" and type(items.Info) == "function" and items.Info(e.id) ~= nil
end

-- Bringt bereite Eintraege der Warteschlange auf freie Plaetze (Reihenfolge der
-- Ankunft; ein noch wartender Eintrag haelt die folgenden nicht auf).
local function Pump(now)
   local i = 1
   while i <= #queue and #active < MAX_VISIBLE do
      if Ready(queue[i], now) then
         Spawn(tremove(queue, i))
      else
         i = i + 1
      end
   end
end

-- Schaltet eine Karte um dt Sekunden weiter; true, wenn sie fertig ist.
local function Advance(card, dt)
   local state = card.state
   if state == "in" then
      card.t = card.t + dt
      if card.t >= FADE_IN then
         card.state, card.t = "stay", 0
         card:SetAlpha(1)
      else
         card:SetAlpha(card.t / FADE_IN)
      end
   elseif state == "stay" then
      -- unter der Maus und im Positionsmodus (Probekarte) laeuft die Zeit nicht
      if not (card.hover or (card.sticky and AnchorShown())) then
         card.t = card.t + dt
         if card.t >= STAY then
            BeginOut(card, FADE_OUT)
         end
      end
   elseif state == "out" then
      card.t = card.t + dt
      if card.t >= card.dur then
         return true
      end
      card:SetAlpha(card.fromAlpha * (1 - card.t / card.dur))
   else
      return true   -- ohne Zustand gibt es nichts zu zeigen
   end
   return false
end

-- Schiebt die Karte ihrem Zielplatz entgegen.
local function Slide(card, dt)
   local diff = card.ty - card.y
   if diff == 0 then
      return
   end
   if abs(diff) < 0.5 then
      card.y = card.ty
   else
      card.y = card.y + diff * min(1, dt * SLIDE_RATE)
   end
   card:SetPoint("TOP", anchor, "BOTTOM", 0, card.y)
end

-- Ein Takt des Treibers (dt Sekunden).
Step = function(dt)
   local now = GetTime()

   local released = false
   local i = 1
   while i <= #active do
      if Advance(active[i], dt) then
         Release(i)
         released = true
      else
         i = i + 1
      end
   end
   if released then
      Restack()
   end

   Pump(now)

   for k = 1, #active do
      Slide(active[k], dt)
   end

   if #active == 0 and #queue == 0 and driver then
      driver:Hide()
   end
end

-- Meldet einen Fehler des Treibers einmal je Meldung an den Fehlerbehandler.
local lastError = nil
local function ReportOnce(err)
   err = tostring(err)
   if err == lastError then
      return
   end
   lastError = err
   local getter = _G.geterrorhandler
   local handler = type(getter) == "function" and getter() or nil
   if type(handler) == "function" then
      pcall(handler, err)
   end
end

-- Raeumt alle Karten und die Warteschlange weg (Notbremse nach einem Fehler:
-- nichts darf halb animiert auf dem Bildschirm stehenbleiben).
local function ClearAll()
   for i = #active, 1, -1 do
      pcall(Release, i)
   end
   for i = #queue, 1, -1 do
      queue[i] = nil
   end
   burst = nil
   for i = #stamps, 1, -1 do
      stamps[i] = nil
   end
end

-- Stellt sicher, dass der Treiber laeuft. Ein Fehler in einem Takt legt den
-- Treiber schlafen und raeumt auf (sonst wiederholte er sich in jedem Bild und
-- die Karten blieben stehen); der naechste Wake weckt ihn wieder.
local function Wake()
   if not driver then
      driver = CreateFrame("Frame")
      driver:SetScript("OnUpdate", function(self, elapsed)
         local ok, err = pcall(Step, tonumber(elapsed) or 0)
         if not ok then
            self:Hide()
            ClearAll()
            ReportOnce(err)
         end
      end)
   end
   driver:Show()
end

-- ---------------------------------------------------------------------------
-- Einreihen, Zusammenfassen
-- ---------------------------------------------------------------------------

-- Reiht einen Eintrag ein und versucht ihn sofort zu zeigen.
local function Enqueue(e)
   queue[#queue + 1] = e
   if #queue > MAX_QUEUE then
      -- zu viele Wartende: eine Sammelkarte statt vieler Einzelkarten
      local now = GetTime()
      local total = 0
      for i = 1, #queue do
         local q = queue[i]
         total = total + (q.burst and (q.count or 1) or 1)
      end
      for i = #queue, 1, -1 do
         queue[i] = nil
      end
      local folded = { burst = true, count = total, showAt = now, deadline = now }
      queue[1] = folded
      burst = { count = total, last = now, entry = folded }
   end
   -- erst wecken, dann zeigen: wirft Pump, laeuft der Treiber trotzdem weiter
   -- und der naechste Takt faengt den Fehler ab
   Wake()
   Pump(GetTime())
end

-- true, wenn fuer die ID schon eine Karte wartet oder (nicht ausblendend) zu sehen ist.
local function IsKnown(id)
   for i = 1, #queue do
      if queue[i].id == id then
         return true
      end
   end
   for i = 1, #active do
      local e = active[i].entry
      if e and e.id == id and active[i].state ~= "out" then
         return true
      end
   end
   return false
end

-- Zaehlerstand der Sammelkarte in Eintrag und (falls sichtbar) Karte nachziehen;
-- ist die Karte schon weg, kommt sie noch einmal.
local function TouchBurst(now)
   local e = burst.entry
   e.count = burst.count
   local card = e.card
   if card and card.entry == e then
      Paint(card)
      if card.state ~= "in" then
         card.state, card.t = "stay", 0
         card:SetAlpha(1)
      end
   elseif e.spawned then
      e.spawned, e.card = nil, nil
      e.showAt, e.deadline = now, now
      Enqueue(e)
   end
end

-- Eine Sammelkarte fuer n Ereignisse; ersetzt die Einzelkarten des Zeitfensters.
local function StartBurst(n, now)
   local from = now - BURST_WINDOW
   for i = #queue, 1, -1 do
      local q = queue[i]
      if not q.burst and q.stamp and q.stamp >= from then
         tremove(queue, i)
      end
   end
   for i = 1, #active do
      local card = active[i]
      local e = card.entry
      if e and not e.burst and e.stamp and e.stamp >= from and card.state ~= "out" then
         BeginOut(card, FAST_OUT)
      end
   end
   local e = { burst = true, count = n, showAt = now + SETTLE, deadline = now }
   burst = { count = n, last = now, entry = e }
   Enqueue(e)
end

-- Fordert die Iteninfo fuer eine Einzelkarte an. Ereignisse, die in einer
-- Sammelkarte aufgehen (Burst), brauchen keine: bei einem Sweep mit hunderten
-- Gegenstaenden wuerden sonst hunderte Abfragen fuer Karten entstehen, die nie
-- erscheinen.
local function RequestInfo(id)
   local items = T.Items
   if type(items) == "table" and type(items.Request) == "function" then
      items.Request(id)
   end
end

-- Meldet ein neues Aussehen. opts.immediate: Probekarte (kein Zusammenfassen,
-- kein Warten); opts.sticky: bleibt, solange der Anker sichtbar ist.
-- Rueckgabe: true, wenn etwas eingereiht oder gezaehlt wurde.
local function Add(id, opts)
   local util = T.Util
   if type(util) == "table" and type(util.ItemIdFromLink) == "function" then
      id = util.ItemIdFromLink(id)
   else
      id = tonumber(id)
   end
   if not id or id < 1 then
      return false
   end

   local now = GetTime()
   if opts and opts.immediate then
      RequestInfo(id)
      Enqueue({ id = id, showAt = now, deadline = now, sticky = opts.sticky })
      return true
   end

   if IsKnown(id) then
      return false
   end

   -- laeuft schon eine Sammelkarte, zaehlt das Ereignis dort mit
   if burst and (now - burst.last) <= BURST_WINDOW then
      burst.count = burst.count + 1
      burst.last = now
      TouchBurst(now)
      return true
   end
   burst = nil

   -- Ereignisse der letzten BURST_WINDOW Sekunden (alte fallen heraus)
   local n = 0
   for i = 1, #stamps do
      if now - stamps[i] <= BURST_WINDOW then
         n = n + 1
         stamps[n] = stamps[i]
      end
   end
   for i = #stamps, n + 1, -1 do
      stamps[i] = nil
   end
   n = n + 1
   stamps[n] = now

   if n >= BURST_COUNT then
      StartBurst(n, now)
      return true
   end

   RequestInfo(id)
   Enqueue({ id = id, stamp = now, showAt = now + SETTLE, deadline = now + INFO_WAIT })
   return true
end

-- ---------------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------------

-- COLLECTION_UPDATED(id): neues Aussehen (nicht im Login-Sweep, nur wenn an).
local function OnCollectionUpdated(id)
   if not Enabled() then
      return
   end
   if type(T.IsLoginSweep) == "function" and T.IsLoginSweep() then
      return
   end
   Add(id)
end

-- ITEMS_RESOLVED: Namen in sichtbare Karten nachtragen, wartende freigeben.
local function OnItemsResolved()
   for i = 1, #active do
      local card = active[i]
      if card.entry and not card.resolved then
         Paint(card)
      end
   end
   if #queue > 0 then
      Pump(GetTime())
   end
end

-- SETTINGS_CHANGED(key): Position neu setzen bzw. bei "aus" die Warteschlange leeren.
local function OnSettingsChanged(key)
   if key == "toastPoint" then
      ApplyPosition()
   elseif key == "toasts" and not Enabled() then
      for i = #queue, 1, -1 do
         if not queue[i].sticky then
            tremove(queue, i)
         end
      end
      burst = nil
      for i = #stamps, 1, -1 do
         stamps[i] = nil
      end
   end
end

-- ---------------------------------------------------------------------------
-- Oeffentliche Schnittstelle
-- ---------------------------------------------------------------------------

-- Meldet die Ereignisse an; darf beliebig oft gerufen werden (Rahmen entstehen
-- erst bei Bedarf).
function Toasts.Init()
   local events = T.Events
   if type(events) == "table" and type(events.On) == "function" then
      events.On("COLLECTION_UPDATED", OnCollectionUpdated, Toasts)
      events.On("SETTINGS_CHANGED", OnSettingsChanged, Toasts)
      events.On("ITEMS_RESOLVED", OnItemsResolved, Toasts)
      events.On("LOCALE_CHANGED", Toasts.ApplyLocale, Toasts)
   end
end

-- Reiht eine Karte fuer den Gegenstand itemId ein (ohne Pruefung von Einstellung
-- und Login-Sweep; Bursts werden zusammengefasst). Rueckgabe: true bei Erfolg.
function Toasts.Show(itemId)
   return Add(itemId, nil)
end

-- true, wenn etwas zu sehen ist oder gleich kommt (ausblendende Karten zaehlen
-- nicht: sonst bliebe nach schnellem Verbergen und Zeigen des Ankers keine
-- Probekarte zum Ausrichten).
local function HasLiveCard()
   if #queue > 0 then
      return true
   end
   for i = 1, #active do
      if active[i].state ~= "out" then
         return true
      end
   end
   return false
end

-- Zeigt den Anker (verschiebbar) und, falls gerade nichts zu sehen ist, eine
-- stehenbleibende Probekarte darunter.
function Toasts.ShowAnchor()
   local a = EnsureAnchor()
   if not a then
      return
   end
   a:Show()
   if not HasLiveCard() then
      Add(TEST_ID, { immediate = true, sticky = true })
   end
end

-- Versteckt den Anker; stehengebliebene Probekarten blenden aus.
function Toasts.HideAnchor()
   if anchor then
      anchor:Hide()
   end
   for i = #queue, 1, -1 do
      if queue[i].sticky then
         tremove(queue, i)
      end
   end
   for i = 1, #active do
      local card = active[i]
      if card.sticky then
         BeginOut(card, FADE_OUT)
      end
   end
   if #active > 0 then
      Wake()   -- das Ausblenden braucht den Treiber
   end
end

-- Zeigt eine Probekarte mit einem bekannten Gegenstand (auch ohne Cache, dann
-- mit "Item <id>" und dem Namen, sobald er da ist).
function Toasts.Test()
   return Add(TEST_ID, { immediate = true })
end

-- Setzt die Position des Ankers auf den Standard zurueck (loescht toastPoint).
function Toasts.ResetPosition()
   if T.DB and T.DB.Set then
      T.DB.Set("toastPoint", nil)
   end
   ApplyPosition()
end

-- Setzt die statischen Texte neu (LOCALE_CHANGED).
function Toasts.ApplyLocale()
   if anchor and anchor.label then
      anchor.label:SetText(L.TOAST_ANCHOR_LABEL)
   end
   for i = 1, #active do
      Paint(active[i])
   end
end

-- Zahlen fuer Diagnose und Tests: { visible, queued, pooled, created, burst }.
function Toasts.Stats()
   return {
      visible = #active,
      queued = #queue,
      pooled = #pool,
      created = created,
      burst = burst ~= nil,
      anchorShown = AnchorShown(),
   }
end
