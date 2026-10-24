-- tests/layout.lua
-- ---------------------------------------------------------------------------
-- Layout-Werkzeuge fuer die Widget-Baeume der strengen Attrappe
-- (tests/mock_wow.lua): absolute Rechtecke, Layoutpruefung und SVG-Ausgabe.
-- Es gibt kein WoW zum Hinsehen; mit diesem Modul sieht man das Fenster trotzdem.
--
--    local Layout = require("layout")
--    local entries  = Layout.Rects(TransmogWindow)            -- Rechtecke (Liste)
--    local problems = Layout.Check(entries)                   -- Befunde
--    local svg      = Layout.Render(entries, { problems = problems })
--
-- ---------------------------------------------------------------------------
-- Layout.Rects(roots, opts) -> entries
--    roots: Frame, Liste von Frames oder nil (= Layout.TopLevel()).
--    entries: Array von Eintraegen (Frames UND Regionen: Texturen/FontStrings),
--    in Baumreihenfolge. Zusatzfelder am Array: entries.byFrame[obj] -> Eintrag,
--    entries.screen = { w, h }, entries.roots = Liste der Wurzeln.
--    Eintrag:
--      frame     das Objekt              path   lesbarer Pfad "TransmogWindow/header/title"
--      name      globaler Name | nil     type   "Button", "FontString" ...
--      kind      "frame" "button" "check" "edit" "slider" "status" "scroll" "model" "tooltip"
--                "texture" "text"        region true fuer Texture/FontString
--      x, y, w, h  Rechteck in UIParent-Einheiten, Ursprung oben links (y nach unten);
--                  UIParent ist so gross wie der Bildschirm der Attrappe (GetScreenWidth/Height)
--      resolved  false, wenn kein Anker/Ziel aufloesbar war (Rechteck dann 0)
--      visible   IsVisible (Region: eigener Schalter und Frame sichtbar); shown = eigener Schalter
--      alpha     wirksame Deckkraft (Produkt ueber Eltern)       scale  wirksame Skalierung zu UIParent
--      strata, level   Frame (Regionen erben vom Frame)           layer, sub   Zeichenebene (Regionen)
--      order     Malreihenfolge (1 = ganz hinten), siehe unten
--      text      FontString-Text | EditBox-Text | Beschriftung des Buttons
--      bg, border  {r,g,b,a} Backdrop-Fuell-/Randfarbe (nur Frames mit Backdrop), edgeSize, bgFile, edgeFile
--      texture, color, vertex, gradient, texcoord, desaturated   (Texturen)
--      textColor, fontSize, justifyH, justifyV, lines, constrainedW   (FontStrings/EditBoxes)
--      interactive  Button/Check/EditBox/Slider mit EnableMouse     overlay  absichtliche Ueberlagerung
--      clip      {x,y,w,h}: Ausschnitt durch ein ScrollFrame oberhalb | nil
--      paints    true, wenn das Objekt etwas zeichnet (Backdrop, Textur, Text, Modell)
--      parent    Eintrag des Eltern-Frames | nil           root  Eintrag der obersten Wurzel
--      anchors   Anzahl der Anker (explizit), points = die SetPoint-Liste der Attrappe
--      negative  true, wenn gekreuzte Anker eine negative Groesse ergaben (w/h dann 0)
--      explicitH true, wenn die Hoehe eines FontStrings fest ist (Hoehe/zwei Anker)
--
--    Modell (Grenzen siehe unten): Anker werden wie in der Attrappe (und im Spiel) aus
--    den aufgezeichneten SetPoint-Listen geloest: alle 9 Ankerpunkte, relativeTo
--    (Frames, Regionen, UIParent), relativePoint, Versatz, SetAllPoints, Groesse
--    aus zwei gegenueberliegenden Ankern, sonst explizite Groesse; Versatz und Groesse
--    gelten in den Einheiten des verankerten Objekts (Skalierung = Produkt der
--    SetScale-Werte der Eltern). FontStrings ohne Breite nehmen die Textbreite, mit
--    Breite brechen sie um (Hoehe = Zeilen). Implizite Verankerung wie im Spiel:
--    Text und Texturen eines Buttons, Daumen eines Sliders, Balken einer StatusBar,
--    das Scroll-Kind eines ScrollFrames.
--    Malreihenfolge: nach Strata, dann Frame-Level, dann Erstellung; Regionen eines
--    Frames nach Zeichenebene (BACKGROUND < BORDER < ARTWORK < OVERLAY), Backdrop
--    zuerst. HIGHLIGHT-Texturen (nur bei Maus darueber) werden nicht gezeichnet.
--    opts.includeHidden  auch unsichtbare Teile aufnehmen (Standard: sie fehlen samt Kindern)
--    opts.screen         { w =, h = } statt GetScreenWidth()/UIParent
--    opts.regions        false: nur Frames
--
-- Layout.Check(roots | entries, opts) -> problems
--    Befunde { kind, severity ("error"|"warning"|"info"), message, path, frame, x,y,w,h,
--              other (Gegenstueck), otherPath, text }. problems.counts = { error, warning, info }.
--      zero-size       sichtbares bedienbares Widget (oder Textur mit Inhalt) ohne Breite/Hoehe
--      unanchored      sichtbarer Frame/Region ohne Anker (wird im Spiel nicht gezeichnet)
--      unresolved      Anker zeigt auf ein nicht aufloesbares Ziel
--      outside-root    sichtbarer Inhalt ragt ueber das Fenster (Wurzel) hinaus
--      outside-parent  Kind ragt ueber den Eltern-Frame (Frame mit Groesse) hinaus
--      overlap         bedienbare Widgets (Button/Check/EditBox/Slider) ueberlappen sich
--                      (Schnittflaeche mit beiden Kanten > 1 px; Nachbarn ohne Flaeche nicht)
--      covered         mausaktiver Frame liegt ueber einem Widget und faengt Klicks ab
--                      (overlap/covered nur innerhalb einer Wurzel: Menues, Dialoge und Panels,
--                      die vor dem Fenster liegen, ueberdecken es absichtlich)
--      text-too-wide   Text breiter als die zugewiesene Breite (einzeilig, wird abgeschnitten)
--      text-clipped    Text braucht mehr Zeilen, als die feste Hoehe zulaesst
--      offscreen       Wurzel liegt (teilweise) ausserhalb des Bildschirms
--    Ausnahmen: Frames/Regionen mit __overlay = true (oder overlay == true / isOverlay == true),
--    Namen mit "Overlay" und alle ihre Nachfahren; Kinder von ScrollFrames gegen das
--    ScrollFrame; nicht sichtbare oder voellig durchsichtige Objekte.
--    opts.tolerance (0.75 px)  opts.overlap ("all" | "siblings")  opts.ignore = function(entry) -> true
--    opts.root = {x,y,w,h} Fensterrechteck fuer outside-root (Standard: Rechteck der ersten Wurzel)
--    opts.info = true   zusaetzlich "knapp" belegte Texte (>= 92 % der Breite) als info
--    opts.truncateOk = { "/name$", ... }  Pfadmuster fuer Texte, die absichtlich abgeschnitten werden
--                       (Befund nur als "info"); ebenso FontStrings mit __truncate = true
--
-- Layout.Render(roots | entries, opts) -> svg, info
--    SVG-Text. opts.problems (aus Check) werden markiert und unten aufgelistet;
--    opts.showInfo (info-Befunde ebenfalls markieren), opts.title,
--    opts.idPrefix ("tm", noetig bei mehreren SVGs in einer HTML-Seite),
--    opts.background (#rrggbb), opts.margin (8), opts.view = {x,y,w,h}, opts.fullScreen,
--    opts.maxProblems (24), opts.tooltips (false: GameTooltips auslassen).
--    info = { w, h, view = {x,y,w,h}, drawn, entries }.
--    Gezeichnet werden: Backdrops (Fuellung, 1-px-Rand), Texturen (Farben, WHITE8X8 mit
--    Vertexfarbe, Symbole als farbige Platzhalter mit Dateiname im <title>), FontStrings
--    (Ausrichtung, Umbruch, Farbcodes), Modelle (schraffiert, Einheit als Beschriftung),
--    GameTooltips; jedes Objekt traegt seinen Pfad als <title>.
--
-- Layout.ValidateSvg(svg) -> ok, message   einfache Wohlgeformtheitspruefung (Tags,
--    Anfuehrungszeichen, Entitaeten, Steuerzeichen)
-- Layout.TopLevel() -> Frames           sichtbare Kinder von UIParent, die zum Addon gehoeren
--                                       (unbenannt oder Name beginnt mit "Transmog") und sichtbare Tooltips
-- Layout.Dump(entries, opts) -> string  Textliste (Pfad, Rechteck, Text)
-- Layout.Find(entries, frame | pathPart) -> Eintrag | nil
-- Layout.Intersect(a, b) -> x, y, w, h | nil   Schnitt zweier {x,y,w,h}
-- Layout.Escape(s) -> string            XML-Escape (Steuerzeichen entfernt)
-- Layout.TextWidth(fs) -> number        natuerliche Textbreite in Einheiten des FontStrings
-- Layout.Wrap(text, size, maxWidth [, nonSpaceWrap]) -> lines, widest, overflow
-- Layout.Format(problems) -> string     lesbare Befundliste
--
-- Grenzen des Modells
--   * Schriftbreiten sind geschaetzt wie in der Attrappe (ASCII 0.55, Mehrbyte-Latin 0.6,
--     CJK/Kyrillisch-breit 1.0 mal Schriftgroesse); die Textpruefung ist ein Hinweis, kein
--     Beweis. Die echte Frizqt-Schrift ist bei Grossbuchstaben breiter.
--   * Umbruch: nur an Leerzeichen. Text ohne Leerzeichen (Chinesisch, Japanisch) laesst sich
--     nur umbrechen, wenn der FontString :SetNonSpaceWrap(true) gesetzt hat (so verlangt es
--     3.3.5a, z. B. die Tooltip-Zeilen von Blizzard); dann gelten Schriftzeichen als
--     Umbruchstellen (nicht vor schliessenden, nicht nach oeffnenden Satzzeichen) und zu lange
--     Woerter werden zeichenweise getrennt. Ohne das Flag meldet Layout.Check einen zu
--     langen einzeiligen Text (text-too-wide).
--   * Es gibt kein Pixelraster, keine Textur-Ausschnitte (TexCoord), keine Rotation.
--   * Maus-Hover, Tooltips ausser GameTooltip-Zeilen und Animationen fehlen.
--   * Frame-Level-Gleichstand wird nach Erstellung aufgeloest (im Spiel nicht festgelegt).
-- ---------------------------------------------------------------------------

local Layout = {}

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
local sfmt, sfind, ssub, sgsub, smatch, sbyte, srep, slower =
   string.format, string.find, string.sub, string.gsub, string.match, string.byte, string.rep, string.lower
local tinsert, tconcat, tsort = table.insert, table.concat, table.sort

-- ---------------------------------------------------------------------------
-- Konstanten
-- ---------------------------------------------------------------------------

local POINTS = {
   TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
   LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
   BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

local STRATA = {
   WORLD = 0, BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
   FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local KIND = {
   Texture = "texture", FontString = "text", Frame = "frame", Button = "button", CheckButton = "check",
   EditBox = "edit", Slider = "slider", StatusBar = "status", ScrollFrame = "scroll", Model = "model",
   PlayerModel = "model", DressUpModel = "model", GameTooltip = "tooltip", ScrollingMessageFrame = "frame",
}
local INTERACTIVE = { button = true, check = true, edit = true, slider = true }
local REGION = { Texture = true, FontString = true }

-- Texturen eines Buttons, die die Engine ueber den ganzen Button legt
local BUTTON_TEXTURES = { "__normalTex", "__pushedTex", "__highlightTex", "__disabledTex",
                          "__checkedTex", "__disabledCheckedTex" }
-- Davon zeichnen wir nur den Ruhezustand
local BUTTON_STATE_HIDDEN = { __pushedTex = true, __highlightTex = true, __disabledTex = true,
                              __disabledCheckedTex = true }

local WHITE_TEXTURE = "interface\\buttons\\white8x8"

-- Texturen mit eingebautem Rand (Haken: die Grafik ist groesser als das Feld, so gewollt)
local PADDED_TEXTURES = { "UI%-CheckBox%-Check" }

-- ---------------------------------------------------------------------------
-- Zugriff auf Attrappen-Objekte (nur rawget: kein Fehler bei unbekannten Namen)
-- ---------------------------------------------------------------------------

local function typeOf(o)
   if type(o) ~= "table" then return nil end
   return rawget(o, "__type")
end

local function isRegion(o)
   return REGION[typeOf(o) or ""] == true
end

local function isFrame(o)
   local t = typeOf(o)
   return t ~= nil and not REGION[t] and t ~= "Font"
end

local function isObject(o)
   local t = typeOf(o)
   return t ~= nil and t ~= "Font"
end

-- Frame und alle Eltern sichtbar?
local function frameVisible(f)
   local p = f
   while p do
      if not rawget(p, "__shown") then return false end
      p = rawget(p, "__parent")
   end
   return true
end

local function objectVisible(o)
   if isRegion(o) then
      if not rawget(o, "__shown") then return false end
      local p = rawget(o, "__parent")
      return p ~= nil and frameVisible(p)
   end
   return frameVisible(o)
end

-- Wirksame Skalierung (Regionen: die ihres Eltern-Frames)
local function effScale(o)
   local s = 1
   local p = o
   if isRegion(o) then p = rawget(o, "__parent") end
   while p do
      s = s * (rawget(p, "__scale") or 1)
      p = rawget(p, "__parent")
   end
   return s
end

-- Wirksame Deckkraft
local function effAlpha(o)
   local a = 1
   if isRegion(o) then
      a = rawget(o, "__alpha") or 1
      o = rawget(o, "__parent")
   end
   while o do
      a = a * (rawget(o, "__alpha") or 1)
      o = rawget(o, "__parent")
   end
   return a
end

local function copyColor(c, defaultAlpha)
   if type(c) ~= "table" then return nil end
   return { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or defaultAlpha or 1 }
end

-- ---------------------------------------------------------------------------
-- Text: Escapes, Umbruch, Breite (Formel der Attrappe)
-- ---------------------------------------------------------------------------

-- Breite einer Zeichenfolge (UTF-8) in Einheiten der Schriftgroesse
local function stringWidth(t, size)
   local w, i, n = 0, 1, #t
   while i <= n do
      local b = sbyte(t, i)
      if b < 0x80 then
         w = w + size * 0.55
         i = i + 1
      elseif b < 0xE0 then
         w = w + size * 0.6
         i = i + 2
      else
         w = w + size
         i = i + (b < 0xF0 and 3 or 4)
      end
   end
   return w
end

-- Zeichenklassen fuer den Umbruch ohne Leerzeichen: "ideo" (Schriftzeichen, Kana, Vollbreite-
-- Formen), "open" (kein Umbruch danach) und "close" (kein Umbruch davor), wie die Kinsoku-Regeln.
local CJK_OPEN, CJK_CLOSE = {}, {}
for _, cp in ipairs({ 0x2018, 0x201C, 0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0x3014, 0xFF08, 0xFF3B, 0xFF5B }) do
   CJK_OPEN[cp] = true
end
for _, cp in ipairs({ 0x2019, 0x201D, 0x3001, 0x3002, 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0x3015, 0xFF09,
                      0xFF0C, 0xFF0E, 0xFF01, 0xFF1A, 0xFF1B, 0xFF1F, 0xFF3D, 0xFF5D }) do
   CJK_CLOSE[cp] = true
end

local function cjkClass(ch)
   if #ch ~= 3 then return nil end
   local b1, b2, b3 = sbyte(ch, 1, 3)
   local cp = (b1 % 16) * 4096 + (b2 % 64) * 64 + (b3 % 64)
   if CJK_CLOSE[cp] then return "close" end
   if CJK_OPEN[cp] then return "open" end
   if (cp >= 0x2E80 and cp <= 0x9FFF) or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0xFF00 and cp <= 0xFFEF) then
      return "ideo"
   end
   return nil
end

-- Zerlegt Text mit WoW-Escapes in Atome:
--   { k = "w", t = Wort, c = {r,g,b} | nil }   { k = "s", c = }  Leerzeichen
--   { k = "t", path = , w = , h = }            Inline-Textur   { k = "n" }  Zeilenumbruch
--   { k = "b" }  moegliche Umbruchstelle ohne Leerzeichen (CJK; zaehlt nur bei SetNonSpaceWrap)
local function parseRich(text, size)
   local atoms = {}
   local color = nil
   local word, wordColor = {}, nil
   local prevClass = nil
   local function flush()
      if #word > 0 then
         atoms[#atoms + 1] = { k = "w", t = tconcat(word), c = wordColor }
         word = {}
      end
      prevClass = nil
   end
   local i, n = 1, #text
   while i <= n do
      local c = ssub(text, i, i)
      if c == "|" then
         local nx = ssub(text, i + 1, i + 1)
         if nx == "c" then
            local r, g, b = smatch(text, "^|c%x%x(%x%x)(%x%x)(%x%x)", i)
            if r then
               flush()
               color = { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, 1 }
               i = i + 10
            else
               i = i + 2
            end
         elseif nx == "r" then
            flush()
            color = nil
            i = i + 2
         elseif nx == "T" then
            local body, e = smatch(text, "^|T(.-)|t()", i)
            if body then
               flush()
               local path, h, w = smatch(body, "^([^:]*):?([^:]*):?([^:]*)")
               h = tonumber(h) or 0
               w = tonumber(w) or h
               if h == 0 then h = size end
               if w == 0 then w = h end
               atoms[#atoms + 1] = { k = "t", path = path, w = w, h = h, c = color }
               i = e
            else
               i = i + 2
            end
         elseif nx == "H" then
            local e = sfind(text, "|h", i + 2, true)
            i = e and (e + 2) or (i + 2)
         elseif nx == "h" then
            i = i + 2
         elseif nx == "n" then
            flush()
            atoms[#atoms + 1] = { k = "n" }
            i = i + 2
         elseif nx == "|" then
            if #word == 0 then wordColor = color end
            word[#word + 1] = "|"
            prevClass = nil
            i = i + 2
         else
            if #word == 0 then wordColor = color end
            word[#word + 1] = c
            prevClass = nil
            i = i + 1
         end
      elseif c == "\n" then
         flush()
         atoms[#atoms + 1] = { k = "n" }
         i = i + 1
      elseif c == " " or c == "\t" then
         flush()
         atoms[#atoms + 1] = { k = "s", c = color }
         i = i + 1
      else
         local b = sbyte(c)
         local len = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
         local ch = ssub(text, i, i + len - 1)
         local cc = cjkClass(ch)
         if #word > 0 and (cc or prevClass) then
            local allow = false
            if prevClass == "ideo" or prevClass == "close" then allow = true end
            if cc == "ideo" or cc == "open" then allow = true end
            if prevClass == "open" or cc == "close" then allow = false end
            if allow then
               flush()
               atoms[#atoms + 1] = { k = "b" }
            end
         end
         if #word == 0 then wordColor = color end
         word[#word + 1] = ch
         prevClass = cc
         i = i + len
      end
   end
   flush()
   return atoms
end

local function atomWidth(a, size)
   if a.k == "w" then return stringWidth(a.t, size) end
   if a.k == "s" then return size * 0.55 end
   if a.k == "t" then return a.w end
   return 0
end

-- Schneidet eine Zeile (Atome) auf maxW ab, wie es die Engine bei zu schmalem FontString zeigt
-- (kein Umbruch moeglich): Woerter werden Zeichen fuer Zeichen gekuerzt.
local function cropLine(line, size, maxW)
   if not maxW or line.width <= maxW + 0.01 then return line end
   local out = { width = 0 }
   for _, a in ipairs(line) do
      local aw = atomWidth(a, size)
      if out.width + aw <= maxW + 0.01 then
         out[#out + 1] = a
         out.width = out.width + aw
      else
         if a.k == "w" then
            -- UTF-8-Zeichen einzeln hinzufuegen, bis die Breite erreicht ist
            local kept, i, n = {}, 1, #a.t
            local used = out.width
            while i <= n do
               local b = sbyte(a.t, i)
               local len = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
               local ch = ssub(a.t, i, i + len - 1)
               local cw = stringWidth(ch, size)
               if used + cw > maxW + 0.01 then break end
               kept[#kept + 1] = ch
               used = used + cw
               i = i + len
            end
            if #kept > 0 then
               out[#out + 1] = { k = "w", t = tconcat(kept), c = a.c }
               out.width = used
            end
         end
         break
      end
   end
   return out
end

-- Zeilen umbrechen (Umbruch nur an Leerzeichen; mit nonSpace auch an den "b"-Stellen und
-- innerhalb zu langer Woerter). maxW = nil: nur harte Umbrueche.
-- Rueckgabe: lines = { { atoms..., width = }, ... }, widest, overflow (ein Wort breiter als maxW)
local function layoutAtoms(atoms, size, maxW, nonSpace)
   if nonSpace and maxW then
      -- zu lange Woerter zeichenweise trennen (die Engine bricht sie bei nonspacewrap um)
      local split, changed = {}, false
      for _, a in ipairs(atoms) do
         if a.k == "w" and stringWidth(a.t, size) > maxW + 0.01 then
            changed = true
            local i, n = 1, #a.t
            while i <= n do
               local b = sbyte(a.t, i)
               local len = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
               if i > 1 then split[#split + 1] = { k = "b" } end
               split[#split + 1] = { k = "w", t = ssub(a.t, i, i + len - 1), c = a.c }
               i = i + len
            end
         else
            split[#split + 1] = a
         end
      end
      if changed then atoms = split end
   end
   local lines = {}
   local cur = { width = 0 }
   local widest, overflow = 0, false
   local function endLine()
      while #cur > 0 and cur[#cur].k == "s" do
         cur.width = cur.width - atomWidth(cur[#cur], size)
         cur[#cur] = nil
      end
      if cur.width > widest then widest = cur.width end
      lines[#lines + 1] = cur
      cur = { width = 0 }
   end
   local i, n = 1, #atoms
   while i <= n do
      local a = atoms[i]
      if a.k == "n" then
         endLine()
         i = i + 1
      elseif a.k == "b" then
         i = i + 1
      elseif a.k == "s" then
         if #cur > 0 then
            cur[#cur + 1] = a
            cur.width = cur.width + atomWidth(a, size)
         end
         i = i + 1
      else
         local cluster, cw = {}, 0
         while i <= n and atoms[i].k ~= "s" and atoms[i].k ~= "n" and not (atoms[i].k == "b" and nonSpace) do
            if atoms[i].k ~= "b" then
               cluster[#cluster + 1] = atoms[i]
               cw = cw + atomWidth(atoms[i], size)
            end
            i = i + 1
         end
         if maxW and #cur > 0 and cur.width + cw > maxW + 0.01 then endLine() end
         for _, c in ipairs(cluster) do cur[#cur + 1] = c end
         cur.width = cur.width + cw
         if maxW and cw > maxW + 0.01 then overflow = true end
      end
   end
   if #cur > 0 or #lines == 0 then
      if #cur > 0 then endLine() end
   end
   return lines, widest, overflow
end

-- Schriftgroesse eines FontStrings/EditBox/Font-Objekts
local function fontSizeOf(o)
   local f = rawget(o, "__font")
   if f and f.size then return f.size end
   local fo = rawget(o, "__fontObject")
   if fo then
      local ff = rawget(fo, "__font")
      if ff and ff.size then return ff.size end
   end
   return 12
end

local function fontColorOf(o)
   local c = rawget(o, "__color")
   if c then return copyColor(c) end
   local fo = rawget(o, "__fontObject")
   if fo then
      local fc = rawget(fo, "__color")
      if fc then return copyColor(fc) end
   end
   return { 1, 1, 1, 1 }
end

local function justifyOf(o)
   local j = rawget(o, "__justifyH")
   if not j then
      local fo = rawget(o, "__fontObject")
      j = fo and rawget(fo, "__justifyH") or "CENTER"
   end
   local v = rawget(o, "__justifyV")
   if not v then
      local fo = rawget(o, "__fontObject")
      v = fo and rawget(fo, "__justifyV") or "MIDDLE"
   end
   return j, v
end

-- Natuerliche (unumgebrochene) Textbreite eines FontStrings in seinen eigenen Einheiten.
function Layout.TextWidth(fs, text)
   text = text or rawget(fs, "__text") or ""
   local size = fontSizeOf(fs)
   local _, widest = layoutAtoms(parseRich(text, size), size, nil)
   return widest
end

-- Bricht Text (mit Escapes) fuer maxWidth um; liefert Zeilen als Klartext.
-- nonSpaceWrap = true: Umbruch auch ohne Leerzeichen (CJK, lange Woerter), wie FontString:SetNonSpaceWrap(true).
-- Rueckgabe: lines (Array von Strings), widest, overflow
function Layout.Wrap(text, size, maxWidth, nonSpaceWrap)
   size = size or 12
   local lines, widest, overflow = layoutAtoms(parseRich(tostring(text or ""), size), size, maxWidth,
      nonSpaceWrap and true or false)
   local out = {}
   for i, ln in ipairs(lines) do
      local parts = {}
      for _, a in ipairs(ln) do
         if a.k == "w" then
            parts[#parts + 1] = a.t
         elseif a.k == "s" then
            parts[#parts + 1] = " "
         end
      end
      out[i] = tconcat(parts)
   end
   return out, widest, overflow
end

-- ---------------------------------------------------------------------------
-- Geometrie
-- ---------------------------------------------------------------------------

-- Kontext einer Berechnung: Bildschirm, UIParent, Zwischenspeicher
local function newContext(opts)
   local ctx = { cache = {}, depth = 0 }
   local ui = opts and opts.uiParent or rawget(_G, "UIParent")
   if ui and not rawget(ui, "__isScreen") then ui = nil end
   ctx.uiParent = ui
   local sw, sh
   if opts and opts.screen then
      sw = opts.screen.w or opts.screen.width or opts.screen[1]
      sh = opts.screen.h or opts.screen.height or opts.screen[2]
   end
   if (not sw or not sh) and ui then
      local ok, w, h = pcall(function() return ui:GetWidth(), ui:GetHeight() end)
      if ok and w and w > 0 then sw, sh = sw or w, sh or h end
   end
   if (not sw or not sh) and type(rawget(_G, "GetScreenWidth")) == "function" then
      sw, sh = sw or GetScreenWidth(), sh or GetScreenHeight()
   end
   ctx.sw = sw or 1365
   ctx.sh = sh or 768
   ctx.uiEff = ui and (rawget(ui, "__scale") or 1) or 1
   if ctx.uiEff <= 0 then ctx.uiEff = 1 end
   return ctx
end

-- Implizite Anker: Text/Texturen eines Buttons, Scroll-Kind. Rueckgabe: Punkte, Art
local function implicitPoints(o)
   local parent = rawget(o, "__parent")
   if not parent then return nil end
   local t = typeOf(o)
   if t == "FontString" then
      if rawget(parent, "__fontString") == o then
         return { { point = "CENTER", rel = parent, relPoint = "CENTER", x = 0, y = 0 } }, "button-text"
      end
   elseif t == "Texture" then
      for _, key in ipairs(BUTTON_TEXTURES) do
         if rawget(parent, key) == o then
            return {
               { point = "TOPLEFT", rel = parent, relPoint = "TOPLEFT", x = 0, y = 0 },
               { point = "BOTTOMRIGHT", rel = parent, relPoint = "BOTTOMRIGHT", x = 0, y = 0 },
            }, "button-texture"
         end
      end
   elseif rawget(parent, "__scrollChild") == o then
      return { { point = "TOPLEFT", rel = parent, relPoint = "TOPLEFT",
                 x = -(rawget(parent, "__hscroll") or 0), y = (rawget(parent, "__vscroll") or 0) } }, "scroll-child"
   end
   return nil
end

local resolveRect

-- Zwei-Gleichungs-Loesung einer Achse: { Anteil, Position } -> Start, Groesse
local function solveAxis(eqs, explicit)
   local a = eqs[1]
   for i = 2, #eqs do
      local b = eqs[i]
      if b[1] ~= a[1] then
         local size = (b[2] - a[2]) / (b[1] - a[1])
         return a[2] - a[1] * size, size, true
      end
   end
   return a[2] - a[1] * explicit, explicit, false
end

-- Rechteck eines Objekts im "wirksamen" Raum: l, b, w, h (b = unten) + Hinweise; false wenn offen.
-- Ergebnis: { l, b, w, h, lines = , constrainedW = , sizeFromAnchors = , implicit = , reason = }
resolveRect = function(ctx, o)
   local cached = ctx.cache[o]
   if cached ~= nil then return cached end
   ctx.depth = ctx.depth + 1
   if ctx.depth > 60 then
      ctx.depth = ctx.depth - 1
      return false
   end
   ctx.cache[o] = false      -- Schleifenschutz
   local result = false

   if rawget(o, "__isScreen") then
      local sc = rawget(o, "__scale") or 1
      result = { l = 0, b = 0, w = ctx.sw * sc, h = ctx.sh * sc, screen = true }
   else
      local pts = rawget(o, "__points") or {}
      local implicit
      if #pts == 0 then pts, implicit = implicitPoints(o) end
      local t = typeOf(o)
      local parent = rawget(o, "__parent")
      local eff = effScale(o)

      if (not pts or #pts == 0) and t == "Texture" and parent and rawget(parent, "__thumbTex") == o then
         -- Slider-Daumen: Position folgt dem Wert
         local pr = resolveRect(ctx, parent)
         if pr then
            local tw = (rawget(o, "__width") or 0) * eff
            local th = (rawget(o, "__height") or 0) * eff
            if tw <= 0 then tw = 8 * eff end
            if th <= 0 then th = pr.h end
            local lo, hi = rawget(parent, "__min") or 0, rawget(parent, "__max") or 1
            local v = rawget(parent, "__value") or lo
            local frac = (hi > lo) and max(0, min(1, (v - lo) / (hi - lo))) or 0
            result = { l = pr.l + (pr.w - tw) * frac, b = pr.b + (pr.h - th) / 2, w = tw, h = th, implicit = "slider-thumb" }
         end
      elseif (not pts or #pts == 0) and t == "Texture" and parent and rawget(parent, "__barTex") == o then
         -- StatusBar-Balken: von links, Anteil des Wertes
         local pr = resolveRect(ctx, parent)
         if pr then
            local lo, hi = rawget(parent, "__min") or 0, rawget(parent, "__max") or 1
            local v = rawget(parent, "__value") or lo
            local frac = (hi > lo) and max(0, min(1, (v - lo) / (hi - lo))) or 0
            result = { l = pr.l, b = pr.b, w = pr.w * frac, h = pr.h, implicit = "status-bar" }
         end
      elseif pts and #pts > 0 then
         local hx, vy = {}, {}
         local ok = true
         for i = 1, #pts do
            local p = pts[i]
            local rel = p.rel or parent or ctx.uiParent
            local rr = rel and resolveRect(ctx, rel) or false
            local fr, fo = POINTS[p.relPoint or p.point], POINTS[p.point]
            if not rr or not fr or not fo then
               ok = false
               break
            end
            hx[#hx + 1] = { fo[1], rr.l + fr[1] * rr.w + (p.x or 0) * eff }
            vy[#vy + 1] = { fo[2], rr.b + fr[2] * rr.h + (p.y or 0) * eff }
         end
         if ok then
            local expW = (rawget(o, "__width") or 0)
            local expH = (rawget(o, "__height") or 0)
            local lines, constrainedW = nil, false
            local width, left, fromAnchorsW
            if t == "FontString" then
               local size = fontSizeOf(o)
               local text = rawget(o, "__text") or ""
               local atoms = parseRich(text, size)
               -- Breite: explizit, aus Ankern oder natuerlich
               local l1, w1, f1 = solveAxis(hx, expW * eff)
               if f1 or expW > 0 then
                  constrainedW = true
                  left, width = l1, w1
               else
                  local _, natural = layoutAtoms(atoms, size, nil)
                  width = natural * eff
                  left = hx[1][2] - hx[1][1] * width
               end
               lines = layoutAtoms(atoms, size, constrainedW and (width / eff) or nil,
                  rawget(o, "__nonSpaceWrap") == true)
               fromAnchorsW = f1
               -- Hoehe: explizit, aus Ankern oder Zeilen
               local textH = max(#lines, (text ~= "" and 1 or 0)) * size
               local bottom, height, f2 = solveAxis(vy, (expH > 0 and expH or textH) * eff)
               result = {
                  l = left, b = bottom, w = max(0, width), h = height, lines = lines,
                  constrainedW = constrainedW, textH = textH, sizeFromAnchors = f1, implicit = implicit,
                  hBounded = (expH > 0) or f2,
               }
            else
               local l1, w1, f1 = solveAxis(hx, expW * eff)
               local b1, h1 = solveAxis(vy, expH * eff)
               result = { l = l1, b = b1, w = w1, h = h1, sizeFromAnchors = f1, implicit = implicit }
            end
            -- gekreuzte Anker: die Attrappe rechnet mit der negativen Groesse weiter (Anker an diesem
            -- Objekt); der Eintrag zeigt dann Groesse 0 (siehe toUi) und wird als negativ markiert
            result.negative = (result.w < -0.001 or result.h < -0.001)
         end
      end
   end

   ctx.cache[o] = result
   ctx.depth = ctx.depth - 1
   return result
end

-- Wandelt "wirksamen" Raum (unten-links) in UIParent-Einheiten (oben-links, y nach unten)
local function toUi(ctx, r)
   local u = ctx.uiEff
   local w, h = max(0, r.w) / u, max(0, r.h) / u
   return r.l / u, ctx.sh - (r.b / u + h), w, h
end

-- ---------------------------------------------------------------------------
-- Wurzeln
-- ---------------------------------------------------------------------------

local TOOLTIP_NAMES = {
   GameTooltip = true, ItemRefTooltip = true, ShoppingTooltip1 = true, ShoppingTooltip2 = true,
   ItemRefShoppingTooltip1 = true, ItemRefShoppingTooltip2 = true,
}

-- Sichtbare Kinder von UIParent, die zum Addon gehoeren (unbenannt oder "Transmog..."),
-- und sichtbare Tooltips (GameTooltip & Co.).
function Layout.TopLevel(opts)
   local ui = opts and opts.uiParent or rawget(_G, "UIParent")
   local out = {}
   if not ui then return out end
   for _, c in ipairs(rawget(ui, "__children") or {}) do
      local name = rawget(c, "__name")
      if rawget(c, "__shown") and (name == nil or sfind(name, "^Transmog") or TOOLTIP_NAMES[name]) then
         out[#out + 1] = c
      end
   end
   return out
end

local function toRootList(roots, opts)
   if roots == nil then return Layout.TopLevel(opts) end
   if isObject(roots) then return { roots } end
   if type(roots) == "table" then
      if roots.roots and roots.byFrame then return roots.roots end
      local out = {}
      for _, r in ipairs(roots) do
         if isObject(r) then out[#out + 1] = r end
      end
      return out
   end
   return {}
end

-- ---------------------------------------------------------------------------
-- Eintraege aufbauen
-- ---------------------------------------------------------------------------

-- Schluessel (Feldnamen) eines Frames, unter denen seine Kinder abgelegt sind
local function childKeys(frame)
   local map = {}
   for k, v in pairs(frame) do
      if type(k) == "string" and sfind(k, "^__") == nil and type(v) == "table" and isObject(v) then
         local old = map[v]
         if not old or k < old then map[v] = k end
      end
   end
   return map
end

-- Absichtliche Ueberlagerung? (Markierung am Objekt oder "Overlay" im Namen)
local function flaggedOverlay(o)
   if rawget(o, "__overlay") == true then return true end
   if rawget(o, "overlay") == true or rawget(o, "isOverlay") == true or rawget(o, "noLayoutCheck") == true then
      return true
   end
   local name = rawget(o, "__name")
   if type(name) == "string" and sfind(name, "Overlay", 1, true) then return true end
   return false
end

local function backdropInfo(e, o)
   local bd = rawget(o, "__backdrop")
   if type(bd) ~= "table" then return end
   if bd.bgFile then
      e.bgFile = bd.bgFile
      e.bg = copyColor(rawget(o, "__backdropColor"), 1) or { 1, 1, 1, 1 }
   end
   if bd.edgeFile then
      e.edgeFile = bd.edgeFile
      e.edgeSize = bd.edgeSize or 16
      e.border = copyColor(rawget(o, "__backdropBorderColor"), 1) or { 1, 1, 1, 1 }
   end
end

local function newEntry(ctx, o, parentEntry, pathSegment)
   local t = typeOf(o)
   local region = REGION[t] == true
   local e = {
      frame = o, type = t, kind = KIND[t] or "frame", name = rawget(o, "__name"), region = region,
      parent = parentEntry, id = rawget(o, "__id") or 0,
      shown = rawget(o, "__shown") and true or false,
      anchors = #(rawget(o, "__points") or {}),
      points = rawget(o, "__points"),
   }
   e.path = parentEntry and (parentEntry.path .. "/" .. pathSegment) or pathSegment
   e.root = parentEntry and parentEntry.root or e
   e.visible = objectVisible(o)
   e.alpha = effAlpha(o)
   e.scale = effScale(o) / ctx.uiEff
   e.overlay = flaggedOverlay(o) or (parentEntry ~= nil and parentEntry.overlay == true)

   local frameObj = region and rawget(o, "__parent") or o
   e.strata = rawget(frameObj, "__strata") or "MEDIUM"
   e.level = rawget(frameObj, "__level") or 0
   if region then
      e.layer = rawget(o, "__layer") or "ARTWORK"
      e.sub = rawget(o, "__sub") or 0
   end

   local r = resolveRect(ctx, o)
   if r then
      e.resolved = true
      e.x, e.y, e.w, e.h = toUi(ctx, r)
      e.negative = r.negative
      e.implicit = r.implicit
      e.sizeFromAnchors = r.sizeFromAnchors
   else
      e.resolved = false
      e.x, e.y, e.w, e.h = 0, 0, 0, 0
   end

   if t == "Texture" then
      e.texture = rawget(o, "__texture")
      e.color = copyColor(rawget(o, "__color"), 1)
      e.vertex = copyColor(rawget(o, "__vertex"), 1)
      e.gradient = rawget(o, "__gradient")
      e.desaturated = rawget(o, "__desaturated") and true or false
      e.texcoord = rawget(o, "__texcoord")
      e.paints = (e.texture ~= nil or e.color ~= nil)
   elseif t == "FontString" then
      local text = rawget(o, "__text")
      e.text = text
      e.fontSize = fontSizeOf(o)
      e.textColor = fontColorOf(o)
      e.justifyH, e.justifyV = justifyOf(o)
      e.lines = r and r.lines or nil
      e.constrainedW = r and r.constrainedW or false
      e.textH = r and r.textH or nil
      e.explicitH = (r and r.hBounded) or ((rawget(o, "__height") or 0) > 0)
      e.paints = (text ~= nil and text ~= "")
   else
      backdropInfo(e, o)
      e.paints = (e.bg ~= nil or e.border ~= nil)
      e.mouse = rawget(o, "__mouse") and true or false
      e.interactive = INTERACTIVE[e.kind] == true and e.mouse
      if t == "EditBox" then
         e.text = rawget(o, "__text")
         e.fontSize = fontSizeOf(o)
         e.textColor = fontColorOf(o)
         e.justifyH = rawget(o, "__justifyH") or "LEFT"
         e.insets = rawget(o, "__textInsets")
         if e.text and e.text ~= "" then e.paints = true end
      elseif t == "Button" or t == "CheckButton" then
         local fs = rawget(o, "__fontString")
         e.text = fs and rawget(fs, "__text") or nil
         e.checked = rawget(o, "__checked") and true or false
         e.enabled = rawget(o, "__enabled") ~= false
      elseif e.kind == "model" then
         e.unit = rawget(o, "__unit")
         e.modelPath = rawget(o, "__modelPath")
         e.tried = rawget(o, "__tried")
         e.undressed = rawget(o, "__undressed") and true or false
         e.paints = true
      end
      e.scrollChild = rawget(o, "__scrollChild")
   end
   return e
end

-- Spielt alle Eintraege unterhalb eines Frames ein (Frame, Regionen, Kinder)
local function collect(ctx, opts, frame, parentEntry, segment, entries, seen)
   if seen[frame] then return end
   seen[frame] = true
   if not opts.includeHidden and not rawget(frame, "__shown") then return end
   local e = newEntry(ctx, frame, parentEntry, segment)
   if e.kind == "tooltip" then e.synthetic = true end
   entries[#entries + 1] = e
   entries.byFrame[frame] = e

   if e.kind == "tooltip" then return end
   local keys = childKeys(frame)
   local counters = {}
   local function name(child)
      local n = rawget(child, "__name")
      if n then return n end
      local k = keys[child]
      if k then return k end
      local t = typeOf(child)
      counters[t] = (counters[t] or 0) + 1
      return t .. "#" .. counters[t]
   end

   if opts.regions ~= false then
      for _, region in ipairs(rawget(frame, "__regions") or {}) do
         if not seen[region] and (opts.includeHidden or rawget(region, "__shown")) then
            seen[region] = true
            local re = newEntry(ctx, region, e, name(region))
            entries[#entries + 1] = re
            entries.byFrame[region] = re
         end
      end
   end
   for _, child in ipairs(rawget(frame, "__children") or {}) do
      collect(ctx, opts, child, e, name(child), entries, seen)
   end
end

-- Weist die Malreihenfolge zu (siehe Kopf)
local function assignOrder(entries)
   local frames = {}
   local regionsOf = {}
   for _, e in ipairs(entries) do
      if e.region then
         local pe = e.parent
         if pe then
            regionsOf[pe] = regionsOf[pe] or {}
            tinsert(regionsOf[pe], e)
         end
      else
         frames[#frames + 1] = e
      end
   end
   tsort(frames, function(a, b)
      local sa, sb = STRATA[a.strata] or 3, STRATA[b.strata] or 3
      if sa ~= sb then return sa < sb end
      if a.level ~= b.level then return a.level < b.level end
      return a.id < b.id
   end)
   local n = 0
   for _, f in ipairs(frames) do
      n = n + 1
      f.order = n
      local list = regionsOf[f]
      if list then
         tsort(list, function(a, b)
            local la, lb = LAYER[a.layer] or 3, LAYER[b.layer] or 3
            if la ~= lb then return la < lb end
            if a.sub ~= b.sub then return a.sub < b.sub end
            return a.id < b.id
         end)
         for _, r in ipairs(list) do
            n = n + 1
            r.order = n
         end
      end
   end
   entries.maxOrder = n
end

-- Ausschnitte durch ScrollFrames oberhalb (Schnittmenge)
local function assignClips(entries)
   for _, e in ipairs(entries) do
      local clip = nil
      local p = e.parent
      local child = e
      while p do
         if p.kind == "scroll" and p.resolved and child ~= p then
            local r = { x = p.x, y = p.y, w = p.w, h = p.h }
            if clip then
               local x1, y1 = max(clip.x, r.x), max(clip.y, r.y)
               local x2, y2 = min(clip.x + clip.w, r.x + r.w), min(clip.y + clip.h, r.y + r.h)
               clip = { x = x1, y = y1, w = max(0, x2 - x1), h = max(0, y2 - y1) }
            else
               clip = r
            end
         end
         child = p
         p = p.parent
      end
      e.clip = clip
   end
end

-- GameTooltips: Rechteck aus Zeilen und Besitzer abschaetzen
local function placeTooltip(ctx, e, entries)
   local o = e.frame
   local lines = rawget(o, "__lines") or {}
   local n = #lines
   e.tooltipLines = lines
   local wmax = 0
   for _, ln in ipairs(lines) do
      local w = stringWidth(tostring(ln.left or ""), 12)
      if ln.right then w = w + 20 + stringWidth(tostring(ln.right), 12) end
      wmax = max(wmax, w)
   end
   e.w = ceil(wmax + 20)
   e.h = n * 14 + 16
   e.resolved = true
   e.paints = n > 0
   local owner = rawget(o, "__owner")
   local oe = owner and entries.byFrame[owner]
   local anchor = rawget(o, "__anchorType") or "ANCHOR_RIGHT"
   if not oe then
      local pr = resolveRect(ctx, o)
      if pr then
         local x, y = toUi(ctx, pr)
         e.x, e.y = x, y
      else
         e.x, e.y = ctx.sw - e.w - 8, ctx.sh - e.h - 8
      end
      return
   end
   if anchor == "ANCHOR_LEFT" then
      e.x, e.y = oe.x - e.w, oe.y
   elseif anchor == "ANCHOR_TOP" then
      e.x, e.y = oe.x, oe.y - e.h
   elseif anchor == "ANCHOR_BOTTOM" then
      e.x, e.y = oe.x, oe.y + oe.h
   elseif anchor == "ANCHOR_TOPRIGHT" then
      e.x, e.y = oe.x + oe.w, oe.y - e.h
   elseif anchor == "ANCHOR_TOPLEFT" then
      e.x, e.y = oe.x - e.w, oe.y - e.h
   else
      e.x, e.y = oe.x + oe.w, oe.y
   end
end

-- Layout.Rects: siehe Kopf
function Layout.Rects(roots, opts)
   opts = opts or {}
   local ctx = newContext(opts)
   local list = toRootList(roots, opts)
   local entries = { byFrame = {}, screen = { w = ctx.sw, h = ctx.sh }, roots = list, ctx = ctx }
   local seen = {}
   for _, root in ipairs(list) do
      local n = rawget(root, "__name")
      collect(ctx, opts, root, nil, n or (typeOf(root) .. "#" .. #entries), entries, seen)
   end
   for _, e in ipairs(entries) do
      if e.kind == "tooltip" and e.visible then placeTooltip(ctx, e, entries) end
   end
   assignOrder(entries)
   assignClips(entries)
   return entries
end

-- Eintrag zu Frame oder Pfad (Teilstring, plain)
function Layout.Find(entries, what)
   if isObject(what) then return entries.byFrame[what] end
   for _, e in ipairs(entries) do
      if e.path == what then return e end
   end
   for _, e in ipairs(entries) do
      if sfind(e.path, what, 1, true) then return e end
   end
   return nil
end

-- Schnitt zweier Rechtecke { x, y, w, h }; nil, wenn leer
function Layout.Intersect(a, b)
   local x1, y1 = max(a.x, b.x), max(a.y, b.y)
   local x2, y2 = min(a.x + a.w, b.x + b.w), min(a.y + a.h, b.y + b.h)
   if x2 <= x1 or y2 <= y1 then return nil end
   return x1, y1, x2 - x1, y2 - y1
end

-- Textliste der Eintraege (zum Debuggen)
function Layout.Dump(entries, opts)
   opts = opts or {}
   local out = {}
   for _, e in ipairs(entries) do
      if e.visible or opts.includeHidden then
         local line = sfmt("%-60s %-10s %7.1f %7.1f %7.1f x %-7.1f", e.path, e.kind, e.x, e.y, e.w, e.h)
         if e.text and e.text ~= "" then line = line .. "  \"" .. e.text .. "\"" end
         if not e.visible then line = line .. "  [hidden]" end
         if not e.resolved then line = line .. "  [unresolved]" end
         out[#out + 1] = line
      end
   end
   return tconcat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Pruefungen
-- ---------------------------------------------------------------------------

local function isAncestor(a, b)
   -- ist Eintrag a ein Vorfahre von b (oder b selbst)?
   local p = b
   while p do
      if p == a then return true end
      p = p.parent
   end
   return false
end

local function entriesOf(roots, opts)
   if type(roots) == "table" and roots.byFrame and roots.roots then return roots end
   return Layout.Rects(roots, opts)
end

local function rectOf(e)
   return { x = e.x, y = e.y, w = e.w, h = e.h }
end

local function describe(e)
   local s = e.path
   if e.text and e.text ~= "" then
      local t = e.text
      if #t > 40 then t = ssub(t, 1, 37) .. "..." end
      s = s .. " \"" .. t .. "\""
   end
   return s
end

function Layout.Check(roots, opts)
   opts = opts or {}
   local entries = entriesOf(roots, opts)
   local tol = opts.tolerance or 0.75
   local problems = {}
   local counts = { error = 0, warning = 0, info = 0 }

   local function add(kind, severity, e, message, other, rect)
      local p = {
         kind = kind, severity = severity, message = message, path = e and e.path or "?", frame = e and e.frame,
         other = other and other.frame, otherPath = other and other.path,
         text = e and e.text,
      }
      local r = rect or (e and rectOf(e))
      if r then p.x, p.y, p.w, p.h = r.x, r.y, r.w, r.h end
      problems[#problems + 1] = p
      counts[severity] = counts[severity] + 1
   end

   local function skip(e)
      if not e.visible or e.overlay then return true end
      if e.alpha < 0.01 then return true end
      if opts.ignore and opts.ignore(e) then return true end
      local n = e.name
      if n and (sfind(n, "ScrollBar") or sfind(n, "TextLeft%d") or sfind(n, "TextRight%d")) then return true end
      return false
   end

   -- Absichtlich abgeschnittener Text (z. B. Namen in Rasterzellen): Flag am FontString
   -- (__truncate = true / truncate = true) oder Pfadmuster in opts.truncateOk -> nur "info"
   local function truncatesOk(e)
      if rawget(e.frame, "__truncate") == true or rawget(e.frame, "truncate") == true then return true end
      for _, pat in ipairs(opts.truncateOk or {}) do
         if sfind(e.path, pat) then return true end
      end
      return false
   end

   local live = {}
   for _, e in ipairs(entries) do
      if not skip(e) and e.kind ~= "tooltip" then live[#live + 1] = e end
   end

   -- Wurzel-Eintrag eines Eintrags (oberster Vorfahr)
   local function rootOf(e)
      local p = e
      while p.parent do p = p.parent end
      return p
   end

   -- 1. Groesse, Anker
   for _, e in ipairs(live) do
      if not e.resolved then
         if e.anchors == 0 and not e.implicit then
            if e.region then
               if e.paints then
                  add("unanchored", "error", e, "visible region has no anchor (the game does not draw it)")
               end
            elseif e.paints or e.interactive or e.kind == "model" then
               add("unanchored", "error", e, "visible frame has no anchor (the game does not draw it)")
            end
         else
            add("unresolved", "warning", e, "an anchor points at an unanchored or unresolvable region")
         end
      else
         if e.negative then
            add("zero-size", "warning", e, "anchors cross over: negative size")
         elseif e.interactive and (e.w < 1 or e.h < 1) then
            add("zero-size", "error", e, sfmt("interactive widget has no usable size (%.0f x %.0f)", e.w, e.h))
         elseif e.region and e.kind == "texture" and e.paints and e.w < 0.5 and e.h < 0.5 then
            add("zero-size", "warning", e, "texture has no size (invisible)")
         elseif e.region and e.kind == "texture" and e.paints and (e.w < 0.5 or e.h < 0.5) and e.texture == nil
            and e.color == nil then
            add("zero-size", "warning", e, "texture has no size (invisible)")
         end
      end
   end

   -- 2. ausserhalb des Eltern-Frames / der Wurzel
   local function outside(e, r)
      -- Ueberstand links/rechts/oben/unten in px (>0 = ragt hinaus)
      return r.x - e.x, (e.x + e.w) - (r.x + r.w), r.y - e.y, (e.y + e.h) - (r.y + r.h)
   end
   local rootReported = {}
   for _, e in ipairs(live) do
      if e.resolved and (e.paints or e.interactive) and e.w > 0 and e.h > 0 then
         local pe = e.parent
         -- gegen den Eltern-Frame (nur mit Groesse; Scroll-Kinder und Kinder von Scroll-Frames ausgenommen)
         if pe and pe.resolved and pe.w > 0 and pe.h > 0 and pe.kind ~= "scroll" and not pe.overlay
            and e.kind ~= "tooltip" then
            local l, r2, t, b = outside(e, pe)
            -- bewusst ausserhalb verankert (Rand an Gegenrand des Eltern-Frames)?
            for _, p in ipairs(e.points or {}) do
               if p.rel == nil or p.rel == pe.frame then
                  local fo, fr = POINTS[p.point], POINTS[p.relPoint or p.point]
                  if fo and fr then
                     if fo[1] == 0 and fr[1] == 1 then r2 = 0 end
                     if fo[1] == 1 and fr[1] == 0 then l = 0 end
                     if fo[2] == 0 and fr[2] == 1 then t = 0 end
                     if fo[2] == 1 and fr[2] == 0 then b = 0 end
                  end
               end
            end
            if e.region and e.texture then
               for _, pat in ipairs(PADDED_TEXTURES) do
                  if sfind(e.texture, pat) then l, r2, t, b = 0, 0, 0, 0 end
               end
            end
            local worst = max(l, r2, t, b)
            if worst > tol and not (pe.scrollChild == e.frame) then
               local sides = {}
               if l > tol then sides[#sides + 1] = sfmt("left %.0f", l) end
               if r2 > tol then sides[#sides + 1] = sfmt("right %.0f", r2) end
               if t > tol then sides[#sides + 1] = sfmt("top %.0f", t) end
               if b > tol then sides[#sides + 1] = sfmt("bottom %.0f", b) end
               add("outside-parent", "warning", e,
                  "extends beyond its parent " .. (pe.name or pe.path) .. " by px: " .. tconcat(sides, ", "))
            end
         end
         -- gegen die Wurzel (das Fenster)
         local rootEntry = rootOf(e)
         local rootRect = opts.root
         if not rootRect and rootEntry.resolved and rootEntry.w > 0 and rootEntry.h > 0 then
            rootRect = rectOf(rootEntry)
         end
         if rootRect and rootEntry ~= e and rootEntry.kind ~= "tooltip" then
            local l, r2, t, b = outside(e, rootRect)
            if max(l, r2, t, b) > tol then
               -- nur das oberste betroffene Element melden
               local topmost = true
               local p = e.parent
               while p do
                  if rootReported[p] then
                     topmost = false
                     break
                  end
                  p = p.parent
               end
               if topmost then
                  rootReported[e] = true
                  local parts = {}
                  if l > tol then parts[#parts + 1] = sfmt("left %.0f", l) end
                  if r2 > tol then parts[#parts + 1] = sfmt("right %.0f", r2) end
                  if t > tol then parts[#parts + 1] = sfmt("top %.0f", t) end
                  if b > tol then parts[#parts + 1] = sfmt("bottom %.0f", b) end
                  add("outside-root", "error", e, "content extends beyond the window by px: " .. tconcat(parts, ", "))
               end
            end
         end
      end
   end

   -- 3. Ueberlappung bedienbarer Widgets und verdeckte Widgets
   local inter = {}
   for _, e in ipairs(live) do
      if e.interactive and e.resolved and e.w > 0 and e.h > 0 then inter[#inter + 1] = e end
   end
   local function visibleRect(e)
      local r = rectOf(e)
      if e.clip then
         local x, y, w, h = Layout.Intersect(r, e.clip)
         if not x then return nil end
         r = { x = x, y = y, w = w, h = h }
      end
      return r
   end
   for i = 1, #inter do
      local a = inter[i]
      local ra = visibleRect(a)
      if ra then
         for j = i + 1, #inter do
            local b = inter[j]
            -- nur innerhalb einer Wurzel: Menues, Dialoge und Panels vor dem Fenster liegen absichtlich darueber
            local consider = (a.root == b.root)
            if opts.overlap == "siblings" and a.parent ~= b.parent then consider = false end
            if consider and (isAncestor(a, b) or isAncestor(b, a)) then consider = false end
            if consider then
               local rb = visibleRect(b)
               if rb then
                  local x, y, w, h = Layout.Intersect(ra, rb)
                  if x and w > 1 and h > 1 then
                     add("overlap", "error", a,
                        sfmt("overlaps %s (%.0f x %.0f px)", b.path, w, h), b, { x = x, y = y, w = w, h = h })
                  end
               end
            end
         end
      end
   end
   -- verdeckt: mausaktiver Nicht-Widget-Frame ueber einem Widget (nicht Vorfahre/Nachfahre)
   local blockers = {}
   for _, e in ipairs(live) do
      if not e.region and e.mouse and not INTERACTIVE[e.kind] and e.resolved and e.w > 0 and e.h > 0
         and e.kind ~= "scroll" then
         blockers[#blockers + 1] = e
      end
   end
   for _, a in ipairs(inter) do
      local ra = visibleRect(a)
      if ra then
         local cx, cy = ra.x + ra.w / 2, ra.y + ra.h / 2
         for _, b in ipairs(blockers) do
            if b.root == a.root and b.order > a.order and not isAncestor(b, a) and not isAncestor(a, b) then
               if cx >= b.x and cx <= b.x + b.w and cy >= b.y and cy <= b.y + b.h then
                  add("covered", "warning", a,
                     "center is covered by the mouse-enabled frame " .. b.path .. " (clicks are intercepted)", b)
                  break
               end
            end
         end
      end
   end

   -- 4. Text
   for _, e in ipairs(live) do
      if e.kind == "text" and e.resolved and e.text and e.text ~= "" and e.lines and e.constrainedW then
         local size = e.fontSize
         local allotW = e.w / e.scale
         local allotH = e.h / e.scale
         local needLines = #e.lines
         local widest = 0
         for _, ln in ipairs(e.lines) do widest = max(widest, ln.width) end
         if e.explicitH then
            local fit = max(1, floor(allotH / size + 0.01))
            if needLines > fit then
               add("text-clipped", truncatesOk(e) and "info" or "warning", e,
                  sfmt("text needs %d lines but only %d fit (cut off)", needLines, fit))
            elseif widest > allotW + 0.5 then
               add("text-too-wide", truncatesOk(e) and "info" or "warning", e,
                  sfmt("text is %.0f px wide, allotted %.0f px (cut off)", widest, allotW))
            end
         elseif widest > allotW + 0.5 then
            add("text-too-wide", "warning", e,
               sfmt("a word is %.0f px wide, allotted %.0f px", widest, allotW))
         end
         if opts.info and needLines == 1 and widest > allotW * 0.92 and widest <= allotW + 0.5 then
            add("text-too-wide", "info", e, sfmt("text fills %.0f%% of its width", 100 * widest / allotW))
         end
      end
   end

   -- 5. Wurzel ausserhalb des Bildschirms
   for _, root in ipairs(entries.roots) do
      local e = entries.byFrame[root]
      if e and e.visible and e.resolved and e.w > 0 then
         local sw, sh = entries.screen.w, entries.screen.h
         if e.x < -tol or e.y < -tol or e.x + e.w > sw + tol or e.y + e.h > sh + tol then
            add("offscreen", "warning", e,
               sfmt("window (%.0f x %.0f at %.0f,%.0f) does not fit the %.0f x %.0f screen", e.w, e.h, e.x, e.y, sw, sh))
         end
      end
   end

   problems.counts = counts
   problems.entries = entries
   return problems
end

-- Lesbare Befundliste
function Layout.Format(problems)
   local out = {}
   for i, p in ipairs(problems) do
      out[#out + 1] = sfmt("%2d. [%s] %s: %s -- %s", i, p.severity, p.kind, p.path, p.message)
   end
   return tconcat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- SVG
-- ---------------------------------------------------------------------------

-- XML-Escape (Steuerzeichen entfernt)
local function esc(s)
   s = tostring(s)
   s = sgsub(s, "[%z\1-\8\11\12\14-\31]", "")
   s = sgsub(s, "&", "&amp;")
   s = sgsub(s, "<", "&lt;")
   s = sgsub(s, ">", "&gt;")
   s = sgsub(s, '"', "&quot;")
   return s
end
Layout.Escape = esc

-- Zahl mit hoechstens 2 Nachkommastellen
local function num(v)
   if v ~= v or v == math.huge or v == -math.huge then return "0" end
   local s = sfmt("%.2f", v)
   s = sgsub(s, "(%..-)0+$", "%1")
   s = sgsub(s, "%.$", "")
   return s
end

local function hex2(v)
   v = floor(max(0, min(1, v)) * 255 + 0.5)
   return sfmt("%02x", v)
end

local function colorHex(c)
   return "#" .. hex2(c[1]) .. hex2(c[2]) .. hex2(c[3])
end

-- Farbe aus einem Texturnamen (Platzhalter fuer Symbole): stabil je Pfad
local function hashColor(path)
   local h = 5381
   for i = 1, #path do h = (h * 33 + sbyte(path, i)) % 2147483647 end
   local hue = (h % 360) / 360
   local sat, lig = 0.45, 0.42
   local function f(n)
      local k = (n + hue * 12) % 12
      local a = sat * min(lig, 1 - lig)
      return lig - a * max(-1, min(k - 3, 9 - k, 1))
   end
   return { f(0), f(8), f(4), 1 }
end

local function baseName(path)
   return smatch(path, "([^\\/]+)$") or path
end

-- XML-Wohlgeformtheit (einfach, ausreichend fuer unsere Ausgabe)
function Layout.ValidateSvg(svg)
   if type(svg) ~= "string" or svg == "" then return false, "empty document" end
   local stack = {}
   local roots = 0
   local i, n = 1, #svg
   local function fail(msg, pos)
      local _, nl = sgsub(ssub(svg, 1, pos or i), "\n", "\n")
      return false, sfmt("line %d: %s", nl + 1, msg)
   end
   -- Steuerzeichen
   local bad = sfind(svg, "[%z\1-\8\11\12\14-\31]")
   if bad then return fail("control character", bad) end
   while i <= n do
      local lt = sfind(svg, "<", i, true)
      local text = ssub(svg, i, (lt or n + 1) - 1)
      -- Entitaeten im Text
      for pos in text:gmatch("()&") do
         local rest = ssub(text, pos, pos + 12)
         if not (smatch(rest, "^&amp;") or smatch(rest, "^&lt;") or smatch(rest, "^&gt;") or smatch(rest, "^&quot;")
            or smatch(rest, "^&apos;") or smatch(rest, "^&#%d+;") or smatch(rest, "^&#x%x+;")) then
            return fail("bad entity in text near '" .. ssub(rest, 1, 8) .. "'", i + pos - 1)
         end
      end
      if not lt then break end
      i = lt
      if ssub(svg, i, i + 3) == "<!--" then
         local e = sfind(svg, "-->", i + 4, true)
         if not e then return fail("unterminated comment", i) end
         i = e + 3
      elseif ssub(svg, i, i + 1) == "<?" then
         local e = sfind(svg, "?>", i + 2, true)
         if not e then return fail("unterminated processing instruction", i) end
         i = e + 2
      elseif ssub(svg, i, i + 1) == "</" then
         local name, e = smatch(svg, "^</([%a_][%w_:%.%-]*)%s*>()", i)
         if not name then return fail("malformed closing tag", i) end
         local top = table.remove(stack)
         if top ~= name then
            return fail("closing tag </" .. name .. "> does not match <" .. tostring(top) .. ">", i)
         end
         i = e
      elseif ssub(svg, i, i + 1) == "<!" then
         local e = sfind(svg, ">", i, true)
         if not e then return fail("unterminated declaration", i) end
         i = e + 1
      else
         local name, p = smatch(svg, "^<([%a_][%w_:%.%-]*)()", i)
         if not name then return fail("malformed tag", i) end
         local pos = p
         local selfClose = false
         local attrs = {}
         while true do
            local ws, q = smatch(svg, "^(%s*)()", pos)
            pos = q
            local c = ssub(svg, pos, pos)
            if c == ">" then
               pos = pos + 1
               break
            elseif c == "/" then
               if ssub(svg, pos + 1, pos + 1) ~= ">" then return fail("malformed empty tag", pos) end
               selfClose = true
               pos = pos + 2
               break
            elseif c == "" then
               return fail("unterminated tag <" .. name .. ">", i)
            else
               local an, q2 = smatch(svg, "^([%a_][%w_:%.%-]*)%s*=%s*()", pos)
               if not an then return fail("malformed attribute in <" .. name .. ">", pos) end
               if ws == "" then return fail("missing space before attribute " .. an, pos) end
               local quote = ssub(svg, q2, q2)
               if quote ~= '"' and quote ~= "'" then return fail("attribute " .. an .. " is not quoted", q2) end
               local close = sfind(svg, quote, q2 + 1, true)
               if not close then return fail("unterminated attribute " .. an, q2) end
               local val = ssub(svg, q2 + 1, close - 1)
               if sfind(val, "<", 1, true) then return fail("'<' in attribute " .. an, q2) end
               for vpos in val:gmatch("()&") do
                  local rest = ssub(val, vpos, vpos + 12)
                  if not (smatch(rest, "^&amp;") or smatch(rest, "^&lt;") or smatch(rest, "^&gt;")
                     or smatch(rest, "^&quot;") or smatch(rest, "^&apos;") or smatch(rest, "^&#%d+;")
                     or smatch(rest, "^&#x%x+;")) then
                     return fail("bad entity in attribute " .. an, q2 + vpos)
                  end
               end
               if attrs[an] then return fail("duplicate attribute " .. an .. " in <" .. name .. ">", pos) end
               attrs[an] = true
               pos = close + 1
            end
         end
         if #stack == 0 then
            roots = roots + 1
            if roots > 1 then return fail("more than one root element", i) end
         end
         if not selfClose then stack[#stack + 1] = name end
         i = pos
      end
   end
   if #stack > 0 then return false, "unclosed element <" .. stack[#stack] .. ">" end
   if roots == 0 then return false, "no root element" end
   return true, "ok"
end

-- Bildausschnitt: Vereinigung aller sichtbaren zeichnenden Eintraege
local function boundsOf(entries, screen)
   local x1, y1, x2, y2
   for _, e in ipairs(entries) do
      if e.visible and e.paints and e.resolved and e.w > 0 and e.h > 0 and e.alpha > 0.01 then
         x1 = x1 and min(x1, e.x) or e.x
         y1 = y1 and min(y1, e.y) or e.y
         x2 = x2 and max(x2, e.x + e.w) or (e.x + e.w)
         y2 = y2 and max(y2, e.y + e.h) or (e.y + e.h)
      end
   end
   if not x1 then return { x = 0, y = 0, w = min(screen.w, 400), h = min(screen.h, 300) } end
   x1, y1 = max(0, x1), max(0, y1)
   x2, y2 = min(screen.w, x2), min(screen.h, y2)
   return { x = x1, y = y1, w = max(1, x2 - x1), h = max(1, y2 - y1) }
end

local GOLD_TINTS = { GoldIcon = "#ffd23c", SilverIcon = "#c8ccd4", CopperIcon = "#c8783c" }

-- Rendert die Eintraege nach SVG (siehe Kopf)
function Layout.Render(roots, opts)
   opts = opts or {}
   local entries = entriesOf(roots, opts)
   local prefix = opts.idPrefix or "tm"
   local screen = entries.screen
   local margin = opts.margin or 8

   local view = opts.view
   if opts.fullScreen then
      view = { x = 0, y = 0, w = screen.w, h = screen.h }
   elseif not view then
      local b = boundsOf(entries, screen)
      view = { x = b.x - margin, y = b.y - margin, w = b.w + 2 * margin, h = b.h + 2 * margin }
   end
   view = { x = floor(view.x), y = floor(view.y), w = ceil(view.w), h = ceil(view.h) }

   -- Markierungen und Legende: Fehler und Warnungen (info nur mit opts.showInfo)
   local problems = {}
   local counts = { error = 0, warning = 0, info = 0 }
   for _, p in ipairs(opts.problems or {}) do
      local sev = p.severity or "warning"
      if sev ~= "info" or opts.showInfo then
         problems[#problems + 1] = p
         counts[sev] = (counts[sev] or 0) + 1
      end
   end
   problems.counts = counts
   local maxProblems = opts.maxProblems or 24
   local legendLines = 0
   if #problems > 0 then legendLines = min(#problems, maxProblems) + 1 + (#problems > maxProblems and 1 or 0) end
   local legendH = legendLines > 0 and (legendLines * 14 + 12) or 0
   if legendLines > 0 and view.w < 560 then view.w = 560 end
   local totalW = view.w
   local totalH = view.h + legendH

   local buf = {}
   local function emit(s) buf[#buf + 1] = s end
   local defs = {}
   local clipCount = 0
   local function newClip(x, y, w, h)
      clipCount = clipCount + 1
      local id = prefix .. "c" .. clipCount
      defs[#defs + 1] = sfmt('<clipPath id="%s"><rect x="%s" y="%s" width="%s" height="%s"/></clipPath>',
         id, num(x), num(y), num(w), num(max(0, h)))
      return id
   end
   local hatchId = prefix .. "hatch"
   defs[#defs + 1] = sfmt('<pattern id="%s" patternUnits="userSpaceOnUse" width="8" height="8" '
      .. 'patternTransform="rotate(45)"><rect width="8" height="8" fill="#232a36"/>'
      .. '<line x1="0" y1="0" x2="0" y2="8" stroke="#46546b" stroke-width="3"/></pattern>', hatchId)
   local gradCount = 0

   local bgColor = opts.background or "#2f343d"
   emit(sfmt('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%d %d %d %d" '
      .. 'font-family="Trebuchet MS, Verdana, Arial, sans-serif">',
      totalW, totalH, view.x, view.y, view.w, totalH))
   emit("<title>" .. esc(opts.title or "Transmog layout") .. "</title>")
   local defsIndex = #buf + 1
   emit("")   -- Platz fuer <defs>
   emit(sfmt('<rect x="%d" y="%d" width="%d" height="%d" fill="%s"/>', view.x, view.y, totalW, totalH, bgColor))

   -- Zeichenliste nach Malreihenfolge
   local list = {}
   for _, e in ipairs(entries) do
      if e.visible and e.resolved and e.alpha > 0.01 then list[#list + 1] = e end
   end
   tsort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)

   local drawn = 0

   local function titleOf(e)
      local t = e.path
      if e.region and e.kind == "texture" and e.texture then t = t .. " [" .. e.texture .. "]" end
      return sfmt("%s (%s %s x %s at %s,%s)", t, e.type or "?", num(e.w), num(e.h), num(e.x), num(e.y))
   end

   local function clipAttr(e)
      if not e.clip then return "" end
      return sfmt(' clip-path="url(#%s)"', newClip(e.clip.x, e.clip.y, e.clip.w, e.clip.h))
   end

   local function opacityAttr(a)
      if a >= 0.995 then return "" end
      return sfmt(' opacity="%s"', num(a))
   end

   -- Texturen
   local function drawTexture(e)
      if e.w <= 0 or e.h <= 0 then return end
      local tex = e.texture
      -- Zustandstexturen eines Buttons, die nur bei Hover/Druck erscheinen
      if e.layer == "HIGHLIGHT" then return end
      if e.parent then
         local pf = e.parent.frame
         for key in pairs(BUTTON_STATE_HIDDEN) do
            if rawget(pf, key) == e.frame then return end
         end
         if rawget(pf, "__checkedTex") == e.frame and not e.parent.checked then return end
      end
      local fill, fillOpacity, label
      local vertex = e.vertex or { 1, 1, 1, 1 }
      if e.gradient and (tex == nil or sfind(slower(tex or ""), "white8x8", 1, true)) then
         local g = e.gradient
         gradCount = gradCount + 1
         local id = prefix .. "g" .. gradCount
         local horizontal = (g[1] == "HORIZONTAL")
         defs[#defs + 1] = sfmt('<linearGradient id="%s" x1="0" y1="0" x2="%d" y2="%d">'
            .. '<stop offset="0" stop-color="%s" stop-opacity="%s"/>'
            .. '<stop offset="1" stop-color="%s" stop-opacity="%s"/></linearGradient>',
            id, horizontal and 1 or 0, horizontal and 0 or 1,
            colorHex({ g[2], g[3], g[4] }), num(g[5] or 1), colorHex({ g[6], g[7], g[8] }), num(g[9] or 1))
         fill = "url(#" .. id .. ")"
         fillOpacity = 1
      elseif e.color then
         fill = colorHex(e.color)
         fillOpacity = e.color[4]
      elseif tex then
         local lower = slower(tex)
         if lower == WHITE_TEXTURE then
            fill = colorHex(vertex)
            fillOpacity = vertex[4]
         else
            local tint
            for key, c in pairs(GOLD_TINTS) do
               if sfind(tex, key, 1, true) then tint = c end
            end
            if tint then
               fill = tint
            elseif sfind(lower, "check", 1, true) then
               fill = "none"
            else
               local hc = hashColor(tex)
               fill = colorHex({ hc[1] * vertex[1], hc[2] * vertex[2], hc[3] * vertex[3] })
            end
            fillOpacity = 1
            label = baseName(tex)
         end
      else
         return
      end
      if e.desaturated and fill ~= "none" and sfind(fill, "^#") then
         local r = tonumber(ssub(fill, 2, 3), 16) / 255
         local g = tonumber(ssub(fill, 4, 5), 16) / 255
         local b = tonumber(ssub(fill, 6, 7), 16) / 255
         local y = 0.3 * r + 0.59 * g + 0.11 * b
         fill = colorHex({ y, y, y })
      end
      local title = "<title>" .. esc(titleOf(e)) .. "</title>"
      if tex and fill == "none" then
         -- Haken: als Linienzug in der Vertexfarbe
         local s = sfmt('<g%s%s><polyline points="%s,%s %s,%s %s,%s" fill="none" stroke="%s" stroke-width="2" '
            .. 'stroke-linecap="round" stroke-linejoin="round" stroke-opacity="%s">%s</polyline></g>',
            clipAttr(e), opacityAttr(e.alpha),
            num(e.x + e.w * 0.22), num(e.y + e.h * 0.55), num(e.x + e.w * 0.42), num(e.y + e.h * 0.72),
            num(e.x + e.w * 0.78), num(e.y + e.h * 0.30), colorHex(vertex), num(vertex[4]), title)
         emit(s)
      else
         local extra = ""
         if label then extra = ' stroke="#00000066" stroke-width="1"' end
         emit(sfmt('<rect x="%s" y="%s" width="%s" height="%s" fill="%s" fill-opacity="%s"%s%s%s>%s</rect>',
            num(e.x), num(e.y), num(e.w), num(e.h), fill, num(fillOpacity or 1), extra, clipAttr(e),
            opacityAttr(e.alpha), title))
      end
      if label and e.w >= 30 and e.h >= 14 then
         local maxChars = floor(e.w / 5.2)
         local shown = label
         if #shown > maxChars then shown = ssub(shown, 1, max(1, maxChars - 1)) .. "~" end
         emit(sfmt('<text x="%s" y="%s" font-size="9" fill="#ffffff" fill-opacity="0.75" text-anchor="middle"%s%s>%s</text>',
            num(e.x + e.w / 2), num(e.y + e.h / 2 + 3), clipAttr(e), opacityAttr(e.alpha), esc(shown)))
      end
      drawn = drawn + 1
   end

   -- Text (Zeilen aus Atomen)
   local function drawLines(e, lines, size, color, justify, vjustify, x, y, w, h, clipId, extraAttr)
      local lh = size
      local nLines = #lines
      local top
      if nLines * lh > h + 0.5 or vjustify == "TOP" then
         top = y
      elseif vjustify == "BOTTOM" then
         top = y + h - nLines * lh
      else
         top = y + (h - nLines * lh) / 2
      end
      for i, ln in ipairs(lines) do
         local base = top + (i - 1) * lh + size * 0.8
         local ax, anchor
         if justify == "LEFT" then
            ax, anchor = x, "start"
         elseif justify == "RIGHT" then
            ax, anchor = x + w, "end"
         else
            ax, anchor = x + w / 2, "middle"
         end
         local spans = {}
         -- gleichfarbige Woerter/Leerzeichen zu einem Abschnitt zusammenfassen (Text bleibt durchsuchbar)
         local runText, runColor = {}, nil
         local function flushRun()
            if #runText > 0 then
               spans[#spans + 1] = sfmt('<tspan fill="%s">%s</tspan>', runColor, esc(tconcat(runText)))
               runText = {}
            end
         end
         for _, a in ipairs(ln) do
            if a.k == "w" or a.k == "s" then
               local hex = colorHex(a.c or color)
               if hex ~= runColor then
                  flushRun()
                  runColor = hex
               end
               runText[#runText + 1] = (a.k == "s") and " " or a.t
            elseif a.k == "t" then
               flushRun()
               local tint = "#9aa5b8"
               for key, c in pairs(GOLD_TINTS) do
                  if sfind(a.path or "", key, 1, true) then tint = c end
               end
               spans[#spans + 1] = sfmt('<tspan fill="%s">&#9679;</tspan>', tint)
            end
         end
         flushRun()
         emit(sfmt('<text x="%s" y="%s" font-size="%s" text-anchor="%s" xml:space="preserve"%s%s%s>%s</text>',
            num(ax), num(base), num(size), anchor, clipId and (' clip-path="url(#' .. clipId .. ')"') or "",
            opacityAttr(e.alpha), extraAttr or "", tconcat(spans)))
      end
   end

   local function drawFontString(e)
      if not e.text or e.text == "" or not e.lines then return end
      local size = e.fontSize * e.scale
      local clipId
      if e.constrainedW then clipId = newClip(e.x, e.y - 1, e.w, e.h + 2) end
      -- Wie die Engine: nur die Zeilen, die in die feste Hoehe passen; zu breite Zeilen abgeschnitten
      local lines = {}
      local limit = #e.lines
      if e.explicitH and e.constrainedW then
         limit = min(limit, max(1, floor((e.h / e.scale) / e.fontSize + 0.01)))
      end
      for i = 1, limit do
         lines[i] = e.constrainedW and cropLine(e.lines[i], e.fontSize, e.w / e.scale) or e.lines[i]
      end
      local color = e.textColor
      drawLines(e, lines, size, color, e.justifyH, e.justifyV, e.x, e.y, e.w, e.h, clipId, nil)
      drawn = drawn + 1
   end

   local function drawFrame(e)
      local a = e.alpha
      local title = "<title>" .. esc(titleOf(e)) .. "</title>"
      if e.bg and e.w > 0 and e.h > 0 then
         local fill = colorHex(e.bg)
         local fo = e.bg[4]
         if e.bgFile and slower(e.bgFile) ~= WHITE_TEXTURE then
            -- Blizzard-Hintergrund: gedeckt dunkel (Textur nicht verfuegbar)
            fill = "#1b1f27"
            fo = 0.92
         end
         emit(sfmt('<rect x="%s" y="%s" width="%s" height="%s" fill="%s" fill-opacity="%s"%s%s>%s</rect>',
            num(e.x), num(e.y), num(e.w), num(e.h), fill, num(fo), clipAttr(e), opacityAttr(a), title))
         title = ""
         drawn = drawn + 1
      end
      if e.border and e.w > 0 and e.h > 0 then
         local s = e.edgeSize or 1
         if e.edgeFile and slower(e.edgeFile) ~= WHITE_TEXTURE then s = min(s, 2) end
         local c = e.border
         emit(sfmt('<rect x="%s" y="%s" width="%s" height="%s" fill="none" stroke="%s" stroke-opacity="%s" '
            .. 'stroke-width="%s"%s%s>%s</rect>',
            num(e.x + s / 2), num(e.y + s / 2), num(max(0, e.w - s)), num(max(0, e.h - s)), colorHex(c),
            num(c[4]), num(s), clipAttr(e), opacityAttr(a), title))
         drawn = drawn + 1
      end
      if e.kind == "model" and e.w > 0 and e.h > 0 then
         emit(sfmt('<rect x="%s" y="%s" width="%s" height="%s" fill="url(#%s)" stroke="#6b7a94" '
            .. 'stroke-dasharray="4 3"%s%s><title>%s</title></rect>',
            num(e.x), num(e.y), num(e.w), num(e.h), hatchId, clipAttr(e), opacityAttr(a), esc(titleOf(e))))
         local what = e.unit and tostring(e.unit) or (e.modelPath and baseName(tostring(e.modelPath))) or "model"
         local labels = { (e.w >= 110 and "model: " or "") .. what }
         if e.tried and #e.tried > 0 then labels[#labels + 1] = #e.tried .. " TryOn" end
         if e.undressed then labels[#labels + 1] = "undressed" end
         local fsz = max(7, min(10, e.w / 9))
         local clipId = newClip(e.x, e.y, e.w, e.h)
         for li, label in ipairs(labels) do
            emit(sfmt('<text x="%s" y="%s" font-size="%s" fill="#b7c2d6" text-anchor="middle" clip-path="url(#%s)"%s>%s</text>',
               num(e.x + e.w / 2), num(e.y + e.h / 2 + (li - (#labels + 1) / 2) * (fsz + 2) + fsz * 0.35),
               num(fsz), clipId, opacityAttr(a), esc(label)))
         end
         drawn = drawn + 1
      end
      if e.kind == "edit" and e.text and e.text ~= "" and e.w > 0 then
         local ins = e.insets or { 0, 0, 0, 0 }
         local size = (e.fontSize or 12) * e.scale
         local clipId = newClip(e.x + (ins[1] or 0), e.y, max(0, e.w - (ins[1] or 0) - (ins[2] or 0)), e.h)
         local atoms = parseRich(e.text, size)
         local lines = layoutAtoms(atoms, size, nil)
         drawLines(e, lines, size, e.textColor or { 1, 1, 1, 1 }, e.justifyH or "LEFT", "MIDDLE",
            e.x + (ins[1] or 0), e.y, max(0, e.w - (ins[1] or 0) - (ins[2] or 0)), e.h, clipId, nil)
         drawn = drawn + 1
      end
      if e.kind == "tooltip" then
         emit(sfmt('<rect x="%s" y="%s" width="%s" height="%s" fill="#101318" fill-opacity="0.96" stroke="#c8ccd4" '
            .. 'stroke-opacity="0.8">%s</rect>', num(e.x + 0.5), num(e.y + 0.5), num(e.w - 1), num(e.h - 1), title))
         for i, ln in ipairs(e.tooltipLines or {}) do
            local r, g, b = ln.r or 1, ln.g or 1, ln.b or 1
            emit(sfmt('<text x="%s" y="%s" font-size="12" fill="%s">%s</text>',
               num(e.x + 10), num(e.y + 8 + i * 14 - 3), colorHex({ r, g, b }), esc(ln.left or "")))
            if ln.right then
               emit(sfmt('<text x="%s" y="%s" font-size="12" fill="%s" text-anchor="end">%s</text>',
                  num(e.x + e.w - 10), num(e.y + 8 + i * 14 - 3), colorHex({ ln.rr or 1, ln.rg or 1, ln.rb or 1 }),
                  esc(ln.right)))
            end
         end
         drawn = drawn + 1
      end
   end

   for _, e in ipairs(list) do
      if e.kind == "tooltip" and opts.tooltips == false then
         -- ausgelassen
      elseif e.region then
         if e.kind == "texture" then
            drawTexture(e)
         else
            drawFontString(e)
         end
      else
         drawFrame(e)
      end
   end

   -- Befunde markieren
   for i, p in ipairs(problems) do
      if p.w and p.h and (p.w > 0 or p.h > 0) and i <= maxProblems then
         local col = (p.severity == "error") and "#ff4d5e" or ((p.severity == "warning") and "#ffb020" or "#5aa9ff")
         emit(sfmt('<rect x="%s" y="%s" width="%s" height="%s" fill="none" stroke="%s" stroke-width="1.5" '
            .. 'stroke-dasharray="4 2"><title>%s</title></rect>',
            num(p.x), num(p.y), num(max(2, p.w)), num(max(2, p.h)), col, esc(p.kind .. ": " .. (p.message or ""))))
         emit(sfmt('<rect x="%s" y="%s" width="14" height="12" fill="%s"/>', num(p.x), num(p.y - 12), col))
         emit(sfmt('<text x="%s" y="%s" font-size="10" font-weight="bold" fill="#101318" text-anchor="middle">%d</text>',
            num(p.x + 7), num(p.y - 3), i))
      end
   end

   -- Legende
   if legendLines > 0 then
      local y0 = view.y + view.h + 6
      emit(sfmt('<rect x="%d" y="%d" width="%d" height="%d" fill="#1a1d23"/>', view.x, view.y + view.h, totalW, legendH))
      local c = problems.counts or { error = 0, warning = 0, info = 0 }
      emit(sfmt('<text x="%d" y="%s" font-size="11" fill="#e6e8ec" font-weight="bold">%s</text>', view.x + 8,
         num(y0 + 10), esc(sfmt("%d problem(s): %d error(s), %d warning(s)", #problems, c.error or 0, c.warning or 0))))
      for i = 1, min(#problems, maxProblems) do
         local p = problems[i]
         local col = (p.severity == "error") and "#ff8a96" or ((p.severity == "warning") and "#ffcf6b" or "#8fc3ff")
         local line = sfmt("%d. %s: %s - %s", i, p.kind, p.path, p.message)
         local maxChars = max(40, floor((totalW - 16) / 5.4))
         if #line > maxChars then line = ssub(line, 1, maxChars - 3) .. "..." end
         emit(sfmt('<text x="%d" y="%s" font-size="10" fill="%s">%s</text>', view.x + 8, num(y0 + 10 + i * 14),
            col, esc(line)))
      end
      if #problems > maxProblems then
         emit(sfmt('<text x="%d" y="%s" font-size="10" fill="#9aa3b2">%s</text>', view.x + 8,
            num(y0 + 10 + (maxProblems + 1) * 14), esc("... and " .. (#problems - maxProblems) .. " more")))
      end
   end

   emit("</svg>")
   buf[defsIndex] = "<defs>" .. tconcat(defs) .. "</defs>"
   local svg = tconcat(buf, "\n") .. "\n"
   return svg, { w = totalW, h = totalH, view = view, drawn = drawn, entries = entries }
end

return Layout
