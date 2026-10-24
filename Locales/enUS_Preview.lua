-- Locales\enUS_Preview.lua
-- ---------------------------------------------------------------------------
-- Englische Texte fuer UI\Preview.lua (grosse Charaktervorschau mit den
-- Steuerknoepfen). Platzhalter (%d, %s) muessen in allen Sprachen in gleicher
-- Anzahl und Reihenfolge vorkommen.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   -- Drehknoepfe "<" und ">" (Tooltips)
   PREVIEW_ROTATE_LEFT = "Rotate left",
   PREVIEW_ROTATE_RIGHT = "Rotate right",
   PREVIEW_ROTATE_HOLD = "Hold the mouse button to keep turning.",

   -- Kamera zuruecksetzen: Beschriftung und Tooltip
   PREVIEW_RESET = "Reset view",
   PREVIEW_RESET_TIP = "Reset rotation, position and zoom.",

   -- Bedienhilfe (zweite Tooltip-Zeile des Reset-Knopfs und der Modellflaeche)
   PREVIEW_HELP_ROTATE = "Drag with the left mouse button: rotate",
   PREVIEW_HELP_MOVE = "Drag with the right mouse button: move",
   PREVIEW_HELP_ZOOM = "Mouse wheel: zoom",

   -- Hinweis unter dem Modell, wenn eine Nebenhand-Waffe nicht gezeigt werden kann
   PREVIEW_OFFHAND_NOTE = "One-handed weapons in the off hand are not shown in this preview.",
   -- Hinweis, solange die Waffe der bearbeiteten Nebenhand in der Haupthand gezeigt wird
   PREVIEW_OFFHAND_NOTE_MAINHAND = "This one-handed weapon is shown in the main hand (client limitation).",
})
