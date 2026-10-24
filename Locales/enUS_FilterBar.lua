-- Locales\enUS_FilterBar.lua
-- ---------------------------------------------------------------------------
-- Englische Texte fuer UI\FilterBar.lua (Suche, Sortierung, Filtermenue,
-- Qualitaets-Chips, Schnellschalter).
--
-- Die Sortiernamen (SORT_QUALITY, SORT_NAME, SORT_ILEVEL) stehen in
-- enUS_Filter.lua, die Qualitaetsnamen sind die Blizzard-Globals
-- ITEM_QUALITY0_DESC..7_DESC (Filter.QualityLabel).
--
-- Regeln: Schluessel = FILTER_ + GROSSBUCHSTABEN_MIT_UNTERSTRICH; Format-Strings
-- nur mit %s und %d, in allen Sprachen gleiche Platzhalter in gleicher
-- Reihenfolge.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   -- Suchfeld
   FILTER_SEARCH_PLACEHOLDER = "Search name, type or #id",

   -- Sortierung
   FILTER_SORT               = "Sort: %s",
   FILTER_SORT_TIP           = "Sort order",
   FILTER_SORT_TIP_HINT      = "Click to choose how the appearances are sorted.",

   -- Filtermenue
   FILTER_BUTTON             = "Filter",
   FILTER_BUTTON_TIP         = "Filter appearances",
   FILTER_HIDE_DUPLICATES    = "Hide duplicate looks",
   FILTER_HIDE_DUPLICATES_TIP = "Shows one entry for appearances with the same icon, type and slot (an approximation: the client cannot read the real model).",
   FILTER_FAVORITES_ONLY     = "Favourites only",
   FILTER_NEW_ONLY           = "New only",
   FILTER_TYPE_TITLE         = "Type",
   FILTER_TYPE_ROW           = "%s (%d)",
   FILTER_TYPE_OWN           = "This is the type of your equipped item and cannot be hidden.",
   FILTER_RESET              = "Reset filters",

   -- Zuruecksetzen-Knopf (x)
   FILTER_RESET_TIP          = "Reset all filters",
   FILTER_RESET_NONE         = "No filters are active.",

   -- Qualitaets-Chips
   FILTER_QUALITY_COUNT      = "Appearances: %d",
   FILTER_QUALITY_HIDE       = "Click to hide this quality",
   FILTER_QUALITY_SHOW       = "Click to show this quality",

   -- Schnellschalter
   FILTER_FAVORITES_CHIP     = "Favourites",
   FILTER_FAVORITES_CHIP_TIP = "Show favourite appearances only",
   FILTER_NEW                = "New",
   FILTER_NEW_TIP            = "Show newly unlocked appearances only",
   FILTER_CHIP_ON            = "Active - click to turn off",
   FILTER_CHIP_OFF           = "Click to turn on",
})
