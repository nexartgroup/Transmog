-- Locales\enUS_Features.lua
-- ---------------------------------------------------------------------------
-- Englische Texte fuer Features\Tooltips.lua (TIP_*) und Features\Toasts.lua
-- (TOAST_*).
--
-- Platzhalter (%d, %s) muessen in allen Sprachen in gleicher Anzahl und
-- Reihenfolge vorkommen. TIP_APPLIED und TIP_INACTIVE bekommen den Namen des
-- Gegenstands bereits in Qualitaetsfarbe eingefaerbt (%s).
--
-- Platz: die Titelzeilen der Toast-Karten (TOAST_TITLE, TOAST_BURST_TITLE,
-- TOAST_BURST_COUNT) haben eine feste Breite von etwa 30 Zeichen; was laenger
-- ist, wird abgeschnitten. TOAST_ANCHOR_LABEL: etwa 16 Zeichen.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   -- Tooltips: Zeile in Gegenstands-Tooltips (rosa)
   TIP_NOT_COLLECTED = "Appearance not collected",

   -- Tooltips: Zeile im Tooltip eines angelegten Gegenstands (rosa bzw. rot)
   TIP_APPLIED = "Transmogrified to: %s",
   TIP_APPLIED_HIDDEN = "Transmogrified to: Hidden",
   TIP_INACTIVE = "Transmog inactive: %s",
   TIP_ITEM_UNKNOWN = "Item %d",

   -- Toasts: Karte fuer ein neues Aussehen
   TOAST_TITLE = "New appearance unlocked",
   TOAST_ITEM_UNKNOWN = "Item %d",

   -- Toasts: eine Karte fuer viele Aussehen auf einmal (%d = Anzahl)
   TOAST_BURST_TITLE = "New appearances unlocked",
   TOAST_BURST_COUNT = "Appearances: %d",

   -- Toasts: Anker zum Verschieben
   TOAST_ANCHOR_LABEL = "Move me",
   TOAST_ANCHOR_TIP_TITLE = "Notification position",
   TOAST_ANCHOR_TIP_DRAG = "Drag to move the notifications.",
   TOAST_ANCHOR_TIP_RESET = "Right-click: reset the position.",
})
