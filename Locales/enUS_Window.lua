-- Locales\enUS_Window.lua
-- ---------------------------------------------------------------------------
-- Englische Texte fuer UI\Window.lua (Hauptfenster: Kopf, Reiter, Fusszeile).
--
-- Die Hinweise der Hinweisleiste (Vorschau-Modus, Server antwortet nicht) und
-- die Gruende des gesperrten Anwenden-Knopfs stammen aus Locales\enUS_State.lua
-- (MSG_NO_VENDOR, MSG_SERVER_ABSENT, APPLY_REASON_*) und stehen hier nicht.
--
-- Schluesselpraefix WIN_. Platzhalter nur %s und %d.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   -- Kopfzeile
   WIN_TITLE = "Transmog",
   WIN_TAB_ITEMS = "Items",
   WIN_TAB_OUTFITS = "Outfits",
   WIN_OPTIONS = "Options",
   WIN_CLOSE = "Close",
   WIN_RESIZE_TIP = "Drag to resize the window.",

   -- Anwenden
   WIN_APPLY = "Apply",
   WIN_APPLY_RESET = "Apply reset",
   WIN_APPLY_TIP = "Apply pending changes: %d",
   WIN_TIP_REMOVE = "Remove appearance",
   WIN_TIP_HIDDEN = "Hidden",

   -- Verwerfen / Alles entfernen
   WIN_DISCARD = "Discard",
   WIN_DISCARD_TIP = "Discard all pending changes.",
   WIN_DISCARD_NONE = "There are no pending changes.",
   WIN_REMOVE_ALL = "Remove all",
   WIN_REMOVE_ALL_TIP = "Remove all applied appearances.",
   WIN_REMOVE_ALL_NONE = "No appearance is applied.",
   WIN_REMOVE_ALL_TITLE = "Remove all appearances",
   WIN_REMOVE_ALL_TEXT = "Remove all applied appearances? Your equipment will show its original look again.",
   WIN_REMOVED_ALL = "All appearances removed.",
   WIN_CANCEL = "Cancel",

   -- Kosten
   WIN_COST = "Cost:",
   WIN_COST_FREE = "Free",
   WIN_COST_PENDING = "...",
   WIN_COST_UNKNOWN = "?",

   -- Statuszeile (Leerlauf und Fortschritt)
   WIN_STATUS_PENDING = "Pending changes: %d",
   WIN_STATUS_APPLYING = "Applying changes (%d)...",
})
