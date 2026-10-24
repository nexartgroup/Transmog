-- Locales\enUS_Boot.lua
-- ---------------------------------------------------------------------------
-- Englische Texte fuer Core\Boot.lua: Slash-Befehle, Hilfe, Diagnose und die
-- Anzeigenamen der Tastenbelegung (BINDING_HEADER_TRANSMOG /
-- BINDING_NAME_TRANSMOG_TOGGLE). Die Meldung beim Anmelden (LOADED) steht in
-- Locales\enUS_Core.lua.
--
-- Schluesselpraefix BOOT_. Platzhalter nur %s und %d.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   -- Tastenbelegung (Optionen > Tastaturbelegung)
   BOOT_BINDING_HEADER = "Transmog",
   BOOT_BINDING_TOGGLE = "Open or close the transmog window",

   -- Fehler beim Start eines Moduls (Modulname)
   BOOT_INIT_FAILED = "The %s module could not be started. See the error report for details.",
   BOOT_UNAVAILABLE = "This part of the addon is not available.",

   -- /transmog reset, /transmog lang
   BOOT_RESET_DONE = "Window position and size have been reset.",
   BOOT_LANG_SET = "Language set to %s.",
   BOOT_LANG_CURRENT = "Current language: %s. Use auto or one of: %s",
   BOOT_LANG_UNKNOWN = "Unknown language \"%s\". Use auto or one of: %s",

   -- /transmog debug
   BOOT_DEBUG_ON = "Debug output enabled.",
   BOOT_DEBUG_OFF = "Debug output disabled.",
   BOOT_DEBUG_INFO = "Version %s, language %s, server state %s, messages sent %d, received %d.",
   BOOT_DEBUG_STATE = "At transmogrifier: %s, pending changes: %d, lists ready: %s.",
   BOOT_DEBUG_ITEMS = "Item queries pending: %d, failed: %d, timers: %d, missing texts: %d.",
   BOOT_YES = "yes",
   BOOT_NO = "no",

   -- /transmog help
   BOOT_HELP_TITLE = "Commands (/transmog or /xmog):",
   BOOT_HELP_TOGGLE = "/transmog - open or close the window",
   BOOT_HELP_OPTIONS = "/transmog options - open the settings",
   BOOT_HELP_RESET = "/transmog reset - reset window position and size",
   BOOT_HELP_TOAST = "/transmog toast - move the notification anchor",
   BOOT_HELP_LANG = "/transmog lang <code|auto> - set the language",
   BOOT_HELP_DEBUG = "/transmog debug - toggle debug output",
   BOOT_HELP_HELP = "/transmog help - show this list",
})
