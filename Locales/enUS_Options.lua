-- Locales\enUS_Options.lua
-- ---------------------------------------------------------------------------
-- Englische Texte fuer UI\Options.lua (Optionsfenster).
--
-- Regeln: Schluessel = ASCII-GROSSBUCHSTABEN_MIT_UNTERSTRICH, Praefix OPT_;
-- Platzhalter nur %s und %d, in allen Sprachen gleich in Anzahl und
-- Reihenfolge. Die Sprachnamen selbst stehen in Locale.List() (native Namen).
--
-- Platz (Richtwerte bei 10-pt-Schrift; zu lange Texte werden abgeschnitten):
--   * OPT_TITLE: etwa 40 Zeichen. OPT_SECTION_*: eine Zeile, etwa 50 Zeichen.
--   * OPT_LANG_AUTO: Knopfbeschriftung mit dem Namen der Clientsprache, etwa 50.
--   * OPT_LANG_NOTE: zwei Zeilen, bis etwa 120 Zeichen.
--   * OPT_SCALE_AUTO: neben dem Regler, hoechstens etwa 11 Zeichen.
--   * OPT_PREVIEW_SMALL .. _XLARGE: Knoepfe, hoechstens etwa 14 Zeichen.
--   * OPT_RESET_WINDOW: ganze Breite, etwa 60 Zeichen.
--   * OPT_SOUND, _TOASTS, _TOOLTIP_*, _ALLOW_ANYWHERE: Haken, etwa 55 Zeichen.
--   * OPT_MOVE_TOASTS / OPT_TEST_TOAST: halbe Breite, hoechstens etwa 28 Zeichen.
--   * OPT_RESET_DONE: Chatzeile. Die *_TIP-Texte werden im Tooltip umbrochen.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   OPT_TITLE = "Transmog options",

   -- Sprache
   OPT_SECTION_LANGUAGE = "Language",
   OPT_LANG_AUTO = "Auto (client language: %s)",
   OPT_LANG_TIP = "Language of all texts in this addon.",
   OPT_LANG_NOTE = "If the language differs from your game client, the font may lack some characters.",

   -- Fenster
   OPT_SECTION_WINDOW = "Window",
   OPT_SCALE = "Window scale",
   OPT_SCALE_AUTO = "Auto",
   OPT_SCALE_TIP = "Auto fits the window to your screen. Move the slider to choose a fixed scale.",
   OPT_PREVIEW_SIZE = "Preview size",
   OPT_PREVIEW_TIP = "Size of the appearance previews in the item grid.",
   OPT_PREVIEW_SMALL = "Small",
   OPT_PREVIEW_MEDIUM = "Medium",
   OPT_PREVIEW_LARGE = "Large",
   OPT_PREVIEW_XLARGE = "Extra large",
   OPT_RESET_WINDOW = "Reset window position and size",
   OPT_RESET_WINDOW_TIP = "Puts the wardrobe window back to its default position and size.",
   OPT_RESET_DONE = "Window position and size were reset.",

   -- Allgemein
   OPT_SECTION_GENERAL = "General",
   OPT_SOUND = "Sound when applying",
   OPT_SOUND_TIP = "Plays a sound when changes were applied successfully.",
   OPT_TOASTS = "Notifications for new appearances",
   OPT_TOASTS_TIP = "Shows a small notification when you unlock a new appearance.",
   OPT_TOOLTIP_COLLECTED = "Tooltip: show \"appearance not collected\"",
   OPT_TOOLTIP_COLLECTED_TIP = "Adds a line to item tooltips when you have not collected the appearance yet.",
   OPT_TOOLTIP_APPLIED = "Tooltip: show \"transmogrified to\"",
   OPT_TOOLTIP_APPLIED_TIP = "Adds a line to the tooltip of your equipped items that shows the appearance applied to them.",
   OPT_ALLOW_ANYWHERE = "Allow applying without a transmogrifier",
   OPT_ALLOW_ANYWHERE_TIP = "The server does not check your distance to a transmogrifier. "
      .. "When this is enabled (the default), changes can be applied from anywhere. When it is disabled, "
      .. "/transmog only opens the preview mode and the addon applies changes only while you are talking "
      .. "to a transmogrifier.",

   -- Benachrichtigungen
   OPT_MOVE_TOASTS = "Move notifications",
   OPT_MOVE_TOASTS_TIP = "Shows the notification anchor so you can drag it to a new position.",
   OPT_TEST_TOAST = "Test notification",
   OPT_TEST_TOAST_TIP = "Shows a sample notification.",
})
