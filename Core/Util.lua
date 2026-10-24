-- Util.lua
-- ---------------------------------------------------------------------------
-- Transmog 2.0  --  Hilfsfunktionen (T.Util): Chat, Text, Zahlen, Timer.
--
-- Alles hier ist frei von Spielzustand und laeuft auch ohne die Oberflaeche.
-- Timer: EIN gemeinsamer Frame; sein OnUpdate laeuft nur, solange Timer
-- anstehen (sonst Hide). Die Uhr des Treibers zaehlt je OnUpdate um das
-- Groessere aus elapsed und der GetTime()-Differenz weiter (siehe OnUpdate);
-- Timer im Leerlauf kosten nichts.
-- ---------------------------------------------------------------------------

Transmog = Transmog or {}
local T = Transmog

T.Util = T.Util or {}
local Util = T.Util

local format, floor, abs = string.format, math.floor, math.abs
local strfind, strsub, strmatch, gsub = string.find, string.sub, string.match, string.gsub
local strchar = string.char

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------

local CHAT_PREFIX = "|cff33a0ea[Transmog]|r "

-- Farbcodes fuer Fehler/Debug-Zeilen (T.HEX kommt aus Init.lua; die festen
-- Werte sind der Ersatz, falls Util allein geladen wird)
local HEX_RED = "|cffe8654a"
local HEX_DIM = "|cff808a99"

-- Liefert den Farbcode aus T.HEX oder den Ersatz.
local function Hex(name, fallback)
   local hex = type(T.HEX) == "table" and T.HEX[name] or nil
   if type(hex) == "string" and hex ~= "" then
      return hex
   end
   return fallback
end

-- Wie string.format, wirft aber nie: bei Formatfehler kommt der rohe Text
-- samt Argumenten zurueck. nil/boolean/table-Argumente werden zu Text.
local function SafeFormat(fmt, ...)
   if fmt == nil then
      return ""
   end
   fmt = tostring(fmt)
   local n = select("#", ...)
   if n == 0 then
      return fmt
   end

   local args = { ... }
   for i = 1, n do
      local a = args[i]
      local ta = type(a)
      if ta ~= "string" and ta ~= "number" then
         args[i] = tostring(a)
      end
   end

   local ok, text = pcall(format, fmt, unpack(args, 1, n))
   if ok then
      return text
   end

   local parts = {}
   for i = 1, n do
      parts[i] = tostring(args[i])
   end
   return fmt .. " (" .. table.concat(parts, ", ") .. ")"
end

-- Schreibt eine fertige Zeile in den Standard-Chat.
local function Out(text)
   local frame = DEFAULT_CHAT_FRAME
   if frame and type(frame.AddMessage) == "function" then
      frame:AddMessage(text)
   elseif type(print) == "function" then
      print(text)
   end
end

-- Wie string.format, aber ohne Fehlermoeglichkeit; ohne Argumente wird der Text
-- unveraendert zurueckgegeben (Prozentzeichen bleiben).
function Util.Format(fmt, ...)
   return SafeFormat(fmt, ...)
end

-- Chat-Ausgabe mit Praefix "[Transmog]"; mit Argumenten per format.
function Util.Print(fmt, ...)
   Out(CHAT_PREFIX .. SafeFormat(fmt, ...))
end

-- Wie Print, aber der Text ist rot (Fehlermeldung an den Spieler).
function Util.Error(fmt, ...)
   Out(CHAT_PREFIX .. Hex("red", HEX_RED) .. SafeFormat(fmt, ...) .. "|r")
end

-- Wie Print, aber nur wenn T.debug gesetzt ist (grau).
function Util.Debug(fmt, ...)
   if not T.debug then
      return
   end
   Out(CHAT_PREFIX .. Hex("dim", HEX_DIM) .. SafeFormat(fmt, ...) .. "|r")
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

-- Blizzard-Globalstring (z.B. "HEADSLOT") oder fallback; nie nil.
function Util.G(globalName, fallback)
   local value = _G[globalName]
   if type(value) == "string" and value ~= "" then
      return value
   end
   if fallback ~= nil then
      return tostring(fallback)
   end
   return tostring(globalName)
end

-- Zerlegt str an dem Klartext-Trenner sep (beliebig lang); leere Felder
-- bleiben erhalten. Rueckgabe: Array von Strings (nie nil).
function Util.Split(str, sep)
   local out = {}
   if str == nil then
      return out
   end
   str = tostring(str)
   if sep == nil or sep == "" then
      out[1] = str
      return out
   end
   sep = tostring(sep)

   local pos, n = 1, 0
   while true do
      local a, b = strfind(str, sep, pos, true)
      if not a then
         break
      end
      n = n + 1
      out[n] = strsub(str, pos, a - 1)
      pos = b + 1
   end
   out[n + 1] = strsub(str, pos)
   return out
end

-- Entfernt Leerraum am Anfang und Ende; nil ergibt "".
function Util.Trim(s)
   if s == nil then
      return ""
   end
   return (strmatch(tostring(s), "^%s*(.-)%s*$"))
end

-- Tabellen fuer Util.Lower: ASCII und die UTF-8-Zweibytefolgen
local ASCII_LOWER = {}
for b = 65, 90 do
   ASCII_LOWER[strchar(b)] = strchar(b + 32)
end

local UTF8_LOWER = {}
-- Latin-1-Ergaenzung U+00C0..U+00DE (ohne U+00D7) -> U+00E0..U+00FE
-- UTF-8: C3 80..9E -> C3 A0..BE
for b = 0x80, 0x9E do
   if b ~= 0x97 then
      UTF8_LOWER["\195" .. strchar(b)] = "\195" .. strchar(b + 0x20)
   end
end
-- Kyrillisch U+0410..U+041F -> U+0430..U+043F  (D0 90..9F -> D0 B0..BF)
for b = 0x90, 0x9F do
   UTF8_LOWER["\208" .. strchar(b)] = "\208" .. strchar(b + 0x20)
end
-- Kyrillisch U+0420..U+042F -> U+0440..U+044F  (D0 A0..AF -> D1 80..8F)
for b = 0xA0, 0xAF do
   UTF8_LOWER["\208" .. strchar(b)] = "\209" .. strchar(b - 0x20)
end
-- Kyrillisch U+0400..U+040F -> U+0450..U+045F  (D0 80..8F -> D1 90..9F)
for b = 0x80, 0x8F do
   UTF8_LOWER["\208" .. strchar(b)] = "\209" .. strchar(b + 0x10)
end

-- Kleinschreibung: ASCII, Latin-1-Ergaenzung und Kyrillisch (UTF-8);
-- unabhaengig von der C-Locale. nil ergibt "".
function Util.Lower(s)
   if s == nil then
      return ""
   end
   s = tostring(s)
   if strfind(s, "[A-Z]") then
      s = gsub(s, "[A-Z]", ASCII_LOWER)
   end
   -- C3 und D0 sind nur als erstes Byte einer Zweibytefolge moeglich
   -- (Folgebytes liegen immer in 80..BF), die Paarung ist also eindeutig.
   if strfind(s, "[\195\208]") then
      s = gsub(s, "[\195\208][\128-\191]", UTF8_LOWER)
   end
   return s
end

-- ---------------------------------------------------------------------------
-- Zahlen
-- ---------------------------------------------------------------------------

-- Begrenzt v auf lo..hi; nicht-numerische Werte ergeben lo.
function Util.Clamp(v, lo, hi)
   v = tonumber(v)
   if v == nil or v ~= v then
      return lo
   end
   if v < lo then
      return lo
   elseif v > hi then
      return hi
   end
   return v
end

-- Kaufmaennisch gerundet auf eine ganze Zahl (0.5 -> 1, -0.5 -> -1).
function Util.Round(v)
   v = tonumber(v)
   if v == nil or v ~= v then
      return 0
   end
   if v >= 0 then
      return floor(v + 0.5)
   end
   return -floor(-v + 0.5)
end

-- Item-ID aus "item:123:...", "|Hitem:123:...|h[..]|h", Zahl oder Zahlentext;
-- sonst nil.
function Util.ItemIdFromLink(s)
   local n
   if type(s) == "number" then
      n = s
   elseif type(s) == "string" then
      local digits = strmatch(s, "item:(%d+)")
      if not digits then
         digits = strmatch(s, "^%s*(%d+)%s*$")
      end
      n = tonumber(digits)
   end
   if n == nil or n ~= n or n < 1 or n ~= floor(n) then
      return nil
   end
   return n
end

-- Ganze Zahl mit Tausendertrenner aus L.THOUSANDS_SEP ("," wenn nicht gesetzt).
function Util.FormatNumber(n)
   n = tonumber(n)
   if n == nil or n ~= n or n == math.huge or n == -math.huge then
      return "0"
   end

   -- rawget: ein fehlender Schluessel soll nicht in L.__missing landen
   local sep = type(T.L) == "table" and rawget(T.L, "THOUSANDS_SEP") or nil
   if type(sep) ~= "string" then
      sep = ","
   end

   local rounded = floor(abs(n) + 0.5)
   local digits = format("%.0f", rounded)
   local len = #digits
   local parts = {}
   local first = len % 3
   if first > 0 then
      parts[#parts + 1] = strsub(digits, 1, first)
   end
   for i = first + 1, len, 3 do
      parts[#parts + 1] = strsub(digits, i, i + 2)
   end

   local text = table.concat(parts, sep)
   if n < 0 and rounded > 0 then
      text = "-" .. text
   end
   return text
end

local ICON_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t"
local ICON_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:2:0|t"
local ICON_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:2:0|t"

-- Kupfer als Text mit Muenzsymbolen; Gold ohne Obergrenze (mit Tausender-
-- trenner), Silber/Kupfer nur wenn > 0, 0 ergibt "0" mit Kupfersymbol.
function Util.FormatMoney(copper)
   copper = tonumber(copper)
   if copper == nil or copper ~= copper or copper < 0 then
      copper = 0
   end
   copper = floor(copper + 0.5)

   local gold = floor(copper / 10000)
   local silver = floor((copper % 10000) / 100)
   local rest = copper % 100

   local parts = {}
   if gold > 0 then
      parts[#parts + 1] = Util.FormatNumber(gold) .. ICON_GOLD
   end
   if silver > 0 then
      parts[#parts + 1] = silver .. ICON_SILVER
   end
   if rest > 0 then
      parts[#parts + 1] = rest .. ICON_COPPER
   end
   if #parts == 0 then
      return "0" .. ICON_COPPER
   end
   return table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------

-- Tiefe Kopie einer Tabelle (Metatabellen werden nicht kopiert; Zyklen werden
-- ueber eine Merkliste abgefangen).
function Util.CopyTable(t)
   local seen = {}
   local function copy(src)
      if type(src) ~= "table" then
         return src
      end
      if seen[src] then
         return seen[src]
      end
      local dst = {}
      seen[src] = dst
      for k, v in pairs(src) do
         dst[k] = copy(v)
      end
      return dst
   end
   return copy(t)
end

-- Anzahl der Eintraege einer Tabelle (alle Schluessel); keine Tabelle -> 0.
function Util.Count(t)
   if type(t) ~= "table" then
      return 0
   end
   local n = 0
   for _ in pairs(t) do
      n = n + 1
   end
   return n
end

-- ---------------------------------------------------------------------------
-- Farben
-- ---------------------------------------------------------------------------

-- Wandelt 0..1 in 0..255 (begrenzt, gerundet).
local function Byte(v)
   v = tonumber(v) or 0
   if v < 0 then
      v = 0
   elseif v > 1 then
      v = 1
   end
   return floor(v * 255 + 0.5)
end

-- Farbcode "|cffRRGGBB" aus r, g, b (0..1).
function Util.Hex(r, g, b)
   return format("|cff%02x%02x%02x", Byte(r), Byte(g), Byte(b))
end

-- Ersatzfarben, falls ITEM_QUALITY_COLORS fehlt (Werte und Farbcodes aus
-- FrameXML 3.3.5; die Farbcodes sind nicht exakt aus r,g,b abzuleiten)
local QUALITY_FALLBACK = {
   [0] = { 0.62, 0.62, 0.62, "|cff9d9d9d" },
   [1] = { 1.00, 1.00, 1.00, "|cffffffff" },
   [2] = { 0.12, 1.00, 0.00, "|cff1eff00" },
   [3] = { 0.00, 0.44, 0.87, "|cff0070dd" },
   [4] = { 0.64, 0.21, 0.93, "|cffa335ee" },
   [5] = { 1.00, 0.50, 0.00, "|cffff8000" },
   [6] = { 0.90, 0.80, 0.50, "|cffe6cc80" },
   [7] = { 0.90, 0.80, 0.50, "|cffe6cc80" },
}

-- Bringt den hex-Wert aus ITEM_QUALITY_COLORS in die Form "|cAARRGGBB". Das
-- Spiel liefert je nach Quelle "|cffa335ee", "ffa335ee" oder "a335ee"; alles
-- andere (nil, Muell) ergibt nil und fuehrt zur Berechnung aus r, g, b.
local function NormalizeHex(hex)
   if type(hex) ~= "string" then
      return nil
   end
   if strmatch(hex, "^|c%x%x%x%x%x%x%x%x$") then
      return hex
   elseif strmatch(hex, "^%x%x%x%x%x%x%x%x$") then
      return "|c" .. hex
   elseif strmatch(hex, "^%x%x%x%x%x%x$") then
      return "|cff" .. hex
   end
   return nil
end

-- Qualitaetsfarbe 0..7 als r, g, b, hex ("|cffRRGGBB"); ungueltig -> weiss.
function Util.QualityColor(q)
   q = tonumber(q)
   if q == nil or q ~= q then
      q = 1
   end
   q = floor(q)
   if q < 0 then
      q = 0
   elseif q > 7 then
      q = 7
   end

   local r, g, b, hex
   local colors = _G.ITEM_QUALITY_COLORS
   local c = type(colors) == "table" and colors[q] or nil
   if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number"
      and type(c.b) == "number" then
      r, g, b = c.r, c.g, c.b
      hex = NormalizeHex(c.hex)
   else
      local f = QUALITY_FALLBACK[q]
      r, g, b, hex = f[1], f[2], f[3], f[4]
   end
   return r, g, b, hex or Util.Hex(r, g, b)
end

-- ---------------------------------------------------------------------------
-- Timer (ein gemeinsamer Treiber-Frame)
-- ---------------------------------------------------------------------------

local timers = {}       -- [handle] = { at=, fn=, args=, n=, key= }
local timerCount = 0
local nextHandle = 0
local clock = 0         -- aufsummierte Laufzeit des Treibers
local lastReal = nil    -- GetTime() beim letzten OnUpdate (nur waehrend Betrieb)
local running = false   -- Treiber ist angeworfen (sichtbar)
local keyed = {}        -- [key] = handle (Debounce)
local driver = nil      -- Treiber-Frame (erst beim ersten Timer erzeugt)

-- Aktuelle Spielzeit oder nil, wenn GetTime fehlt.
local function RealNow()
   if type(GetTime) == "function" then
      return GetTime()
   end
   return nil
end

-- Meldet einen Handlerfehler an den Fehlerbehandler des Spiels.
local function ReportError(err)
   local getter = _G.geterrorhandler
   local handler = type(getter) == "function" and getter() or nil
   if type(handler) == "function" then
      pcall(handler, err)
   end
end

-- Nimmt einen Timer aus den Tabellen (der Treiber bleibt, wie er ist).
-- Rueckgabe: der Eintrag oder nil, wenn es den Handle nicht (mehr) gibt.
local function Remove(handle)
   local t = timers[handle]
   if not t then
      return nil
   end
   timers[handle] = nil
   timerCount = timerCount - 1
   if t.key ~= nil and keyed[t.key] == handle then
      keyed[t.key] = nil
   end
   return t
end

-- Versteckt den Treiber, sobald kein Timer mehr ansteht (kein OnUpdate im
-- Leerlauf).
local function SleepIfIdle()
   if timerCount <= 0 then
      timerCount = 0
      if driver then
         running = false
         driver:Hide()
      end
   end
end

-- OnUpdate des Treibers: Uhr weiterzaehlen, faellige Timer in Reihenfolge
-- (Zeit, Handle) ausfuehren, bei Leerlauf verstecken.
local function OnUpdate(_, elapsed)
   -- Fortschritt = das Groessere aus elapsed und der GetTime-Differenz (nie
   -- die Summe); so laeuft die Uhr auch, wenn nur eine der beiden Quellen
   -- weiterzaehlt.
   local dt = tonumber(elapsed) or 0
   local real = RealNow()
   if real and lastReal and real - lastReal > dt then
      dt = real - lastReal
   end
   lastReal = real
   if dt < 0 then
      dt = 0
   end
   clock = clock + dt

   -- kleine Toleranz gegen Rundungsfehler beim Aufsummieren
   local limit = clock + 0.000001

   -- die Liste entsteht erst, wenn wirklich etwas faellig ist (kein Muell je Frame)
   local due, n = nil, 0
   for handle, t in pairs(timers) do
      if t.at <= limit then
         if not due then
            due = {}
         end
         n = n + 1
         due[n] = handle
      end
   end

   if n > 1 then
      table.sort(due, function(a, b)
         local ta, tb = timers[a], timers[b]
         if ta.at ~= tb.at then
            return ta.at < tb.at
         end
         return a < b
      end)
   end

   for i = 1, n do
      -- ein frueherer Handler dieses Durchlaufs kann ihn abgebrochen haben
      local t = Remove(due[i])
      if t then
         local ok, err = pcall(t.fn, unpack(t.args, 1, t.n))
         if not ok then
            ReportError(err)
         end
      end
   end

   SleepIfIdle()
end

-- Stellt sicher, dass der Treiber existiert und laeuft.
local function WakeDriver()
   if not driver then
      if type(CreateFrame) ~= "function" then
         return
      end
      driver = CreateFrame("Frame")
      driver:SetScript("OnUpdate", OnUpdate)
   end
   if not running then
      running = true
      lastReal = RealNow()
   end
   driver:Show()
end

-- Legt einen Timer an; Rueckgabe: Handle. Ungueltige Verzoegerungen (nil,
-- Text, NaN, negativ) gelten als 0; ein NaN darf nie in die Faelligkeit
-- gelangen, sonst bliebe der Treiber fuer immer wach.
local function Schedule(delay, fn, key, args, n)
   delay = tonumber(delay) or 0
   if delay ~= delay or delay < 0 then
      delay = 0
   end
   nextHandle = nextHandle + 1
   timers[nextHandle] = {
      at = clock + delay, fn = fn, args = args, n = n, key = key,
   }
   timerCount = timerCount + 1
   WakeDriver()
   return nextHandle
end

-- Einmaliger Timer: ruft fn(...) nach delay Sekunden (geschuetzt, Fehler gehen
-- an den Fehlerbehandler). Rueckgabe: Handle (Zahl) oder nil bei ungueltigem fn.
function Util.After(delay, fn, ...)
   if type(fn) ~= "function" then
      return nil
   end
   return Schedule(delay, fn, nil, { ... }, select("#", ...))
end

-- Bricht einen Timer ab (Handle aus After/Debounce, oder der Debounce-Schluessel
-- als Text). Rueckgabe: true wenn ein Timer entfernt wurde.
function Util.Cancel(handle)
   if type(handle) == "string" then
      handle = keyed[handle]
   end
   if handle == nil or not Remove(handle) then
      return false
   end
   SleepIfIdle()
   return true
end

-- Entprellt: re-armt den Timer zu key; fn() wird nach delay Sekunden Ruhe
-- gerufen. Rueckgabe: Handle des neuen Timers (nil bei ungueltigen Argumenten).
function Util.Debounce(key, delay, fn)
   if key == nil or type(fn) ~= "function" then
      return nil
   end
   local old = keyed[key]
   if old then
      -- ohne SleepIfIdle: gleich folgt der neue Timer (kein Hide/Show-Wechsel)
      Remove(old)
   end
   local handle = Schedule(delay, fn, key, {}, 0)
   keyed[key] = handle
   return handle
end

-- Anzahl der ausstehenden Timer (fuer Tests und Diagnose).
function Util.TimerCount()
   return timerCount
end
