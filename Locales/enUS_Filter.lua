-- Locales\enUS_Filter.lua
-- ---------------------------------------------------------------------------
-- Englische Texte fuer Core\Filter.lua und Core\Outfits.lua.
-- Qualitaetsnamen kommen aus den Blizzard-Globals ITEM_QUALITY0_DESC..7_DESC
-- (Filter.QualityLabel), deshalb gibt es hier keine QUALITY_n-Schluessel.
--
-- Die OUTFIT_ERR_*-Schluessel sind Fehlerschluessel, die Outfits.* zurueckgibt
-- (Anzeige per L[errKey], ohne Formatargumente). Die OUTFIT_SKIP_*-Schluessel
-- sind die Ueberspringen-Gruende von Outfits.Load/Outfits.Check.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   -- Sortierung
   SORT_QUALITY = "Quality",
   SORT_NAME = "Name",
   SORT_ILEVEL = "Item level",

   -- Outfit-Namen und Speicherfehler
   OUTFIT_DEFAULT_NAME = "Outfit %d",
   OUTFIT_ERR_EMPTY = "Please enter a name for the outfit.",
   OUTFIT_ERR_EXISTS = "An outfit with this name already exists.",
   OUTFIT_ERR_LONG = "The name is too long (maximum 32 characters).",
   OUTFIT_ERR_FULL = "You have reached the maximum number of outfits.",
   OUTFIT_ERR_NOITEMS = "Nothing to save: no appearance is applied or selected.",
   OUTFIT_ERR_MISSING = "This outfit no longer exists.",

   -- Gruende, warum ein Teil beim Laden eines Outfits uebersprungen wird
   OUTFIT_SKIP_EMPTY = "Nothing is equipped in this slot.",
   OUTFIT_SKIP_NEVER = "This slot cannot be transmogrified.",
   OUTFIT_SKIP_LOADING = "The appearance list for this slot is still loading.",
   OUTFIT_SKIP_UNAVAILABLE = "This appearance is not available for your equipped item.",
   OUTFIT_SKIP_HIDDEN = "This slot cannot be hidden.",
})
