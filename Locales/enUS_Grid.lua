-- Locales\enUS_Grid.lua
-- ---------------------------------------------------------------------------
-- Englische Texte fuer UI\Grid.lua (Raster der Aussehen, Blaetterleiste,
-- Meldungen in der Rasterflaeche, Zellen-Tooltips).
--
-- Regeln: Schluessel = GRID_ + GROSSBUCHSTABEN_MIT_UNTERSTRICH; Format-Strings
-- nur mit %s und %d, in allen Sprachen gleiche Platzhalter in gleicher
-- Reihenfolge. Zahlen mit Tausendertrenner kommen als fertiger Text (%s).
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   -- Meldungen in der Rasterflaeche (Titel + Hinweiszeile)
   GRID_NO_SLOT           = "Select an equipment slot",
   GRID_NO_SLOT_HINT      = "Choose a slot on the left to browse its appearances.",
   GRID_EMPTY_SLOT        = "Nothing equipped in this slot",
   GRID_EMPTY_SLOT_HINT   = "Equip an item to see the appearances that fit it.",
   GRID_NEVER             = "This item cannot be transmogrified",
   GRID_NEVER_HINT        = "Rings, necklaces, trinkets and relics cannot change their look.",
   GRID_ABSENT            = "The transmog server module does not answer",
   GRID_ABSENT_HINT       = "Appearances are loaded from the server. Make sure mod-transmog-plus is installed and enabled.",
   GRID_NO_ITEMS          = "No matching appearances yet",
   GRID_NO_ITEMS_HINT     = "They unlock when you obtain items that fit this slot.",
   GRID_FILTERED          = "No appearances match your filters",
   GRID_FILTERED_HINT     = "Change or reset the filters above to see more.",
   GRID_RESET_FILTERS     = "Reset filters",

   -- Ladezustand: gelesen / gesamt (fertig formatierte Zahlen); PLAIN, solange die
   -- Gesamtzahl noch unbekannt ist
   GRID_LOADING           = "Loading appearances... %s / %s",
   GRID_LOADING_PLAIN     = "Loading appearances...",
   GRID_LOADING_HINT      = "Item data is requested from the server.",
   GRID_PLACEHOLDER       = "...",

   -- Blaetterleiste
   GRID_PAGE              = "Page %d / %d",
   GRID_PAGE_SHORT        = "%d / %d",
   GRID_COUNT             = "%s of %s appearances",
   GRID_COUNT_FILTERED    = "%s of %s appearances (filtered)",
   GRID_COUNT_DUPES       = "%s of %s appearances (%s duplicates hidden)",
   GRID_COUNT_SHORT       = "%s / %s",
   GRID_PAGE_FIRST        = "First page",
   GRID_PAGE_PREV         = "Previous page",
   GRID_PAGE_NEXT         = "Next page",
   GRID_PAGE_LAST         = "Last page",

   -- Synthetische Kacheln
   GRID_ORIGINAL          = "Original",
   GRID_ORIGINAL_TITLE    = "Original appearance",
   GRID_ORIGINAL_TIP      = "Select to remove the transmogrification and show the equipped item's own look.",
   GRID_HIDDEN            = "Hidden",
   GRID_HIDDEN_TIP        = "Select to hide the equipment in this slot.",

   -- Zellen: Marke und Tooltip-Zeilen
   GRID_NEW               = "NEW",
   GRID_TIP_APPLIED       = "Currently applied",
   GRID_TIP_SELECTED      = "Selected - not applied yet",
   GRID_TIP_FAVORITE      = "Favourite",
   GRID_TIP_NEW           = "Newly unlocked",
   GRID_TIP_LEFT_SELECT   = "Left click: select",
   GRID_TIP_LEFT_DISCARD  = "Left click: discard the selection",
   GRID_TIP_RIGHT_FAV     = "Right click: toggle favourite",
   GRID_TIP_SHIFT_LINK    = "Shift + left click: link in chat",

   -- Hinweis fuer die Nebenhand-Vorschau (Client-Grenze)
   GRID_TIP_OFFHAND_PREVIEW = "Preview shows one-handed weapons in the main hand (client limitation).",
})
