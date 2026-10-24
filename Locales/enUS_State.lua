-- Locales\enUS_State.lua
-- Englische Texte fuer Core\State.lua (Gruende, warum "Anwenden" gesperrt ist,
-- und Chatmeldungen). Platzhalter (%d, %s) muessen in allen Sprachen in
-- gleicher Anzahl und Reihenfolge vorkommen.

local T = Transmog

T.Locale.Add("enUS", {
   -- Gruende fuer den gesperrten Anwenden-Knopf (State.CanApply -> reasonKey)
   APPLY_REASON_NONE         = "Nothing has been changed yet.",
   APPLY_REASON_VENDOR       = "Visit a transmogrifier to apply changes.",
   APPLY_REASON_BUSY         = "Applying changes...",
   APPLY_REASON_COST_PENDING = "Calculating the cost...",
   APPLY_REASON_MONEY        = "You cannot afford this.",
   APPLY_REASON_SERVER       = "The transmog server module does not answer.",

   -- Meldungen
   MSG_APPLY_OK           = "Appearance applied.",
   MSG_APPLY_DONE         = "%d changed, %d failed.",
   MSG_APPLY_SLOT_FAILED  = "%s could not be applied.",
   MSG_SERVER_ABSENT      = "The transmog server module does not answer.",
   MSG_NO_VENDOR          = "Preview mode - visit a transmogrifier to apply changes.",
})
