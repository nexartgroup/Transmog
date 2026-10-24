-- Locales\enUS_SlotBar.lua
-- ---------------------------------------------------------------------------
-- Englische Texte fuer UI\SlotBar.lua (Tooltips der 14 Transmog-Plaetze).
--
-- Die Slotnamen selbst kommen aus den Blizzard-Globals (Slots.Label), die
-- Zahl am Knopf ist reine Ziffer ("99+") und braucht keinen Text.
-- Platzhalter (%d, %s) muessen in allen Sprachen in gleicher Anzahl und
-- Reihenfolge vorkommen.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   -- Grund, warum ein Platz nicht auswaehlbar ist
   SLOTBAR_NOTHING_EQUIPPED = "Nothing equipped",
   SLOTBAR_NEVER = "Cannot be transmogrified",

   -- Zustand des Platzes (%s = Name des Aussehens)
   SLOTBAR_APPLIED = "Transmogrified to: %s",
   SLOTBAR_HIDDEN = "Hidden",
   SLOTBAR_PENDING = "Pending: %s",
   SLOTBAR_PENDING_RESET = "Pending: reset to original",
   SLOTBAR_INACTIVE = "Inactive: %s (does not fit the equipped item)",
   SLOTBAR_UNKNOWN_ITEM = "Item %d",

   -- Anzahl verfuegbarer Aussehen / Ladefortschritt (empfangen, gesamt)
   SLOTBAR_AVAILABLE = "Available: %d",
   SLOTBAR_LOADING = "Loading appearances: %d / %d",

   -- Bedienhinweise am Ende des Tooltips
   SLOTBAR_HINT_EDIT = "Left-click: edit",
   SLOTBAR_HINT_DISCARD = "Right-click: discard pending change",
   SLOTBAR_HINT_REMOVE = "Right-click: remove transmog",
   SLOTBAR_HINT_LINK = "Shift-click: link in chat",
})
