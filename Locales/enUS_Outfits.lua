-- Locales\enUS_Outfits.lua
-- ---------------------------------------------------------------------------
-- Englische Texte fuer UI\OutfitsTab.lua (Outfit-Reiter und seine Dialoge).
--
-- Die Fehlertexte beim Speichern/Umbenennen (OUTFIT_ERR_*) und die Gruende,
-- warum ein Teil nicht geladen werden kann (OUTFIT_SKIP_*), stehen in
-- enUS_Filter.lua; der Reiter zeigt sie ueber L[errKey].
--
-- Regeln: Schluessel = ASCII-GROSSBUCHSTABEN_MIT_UNTERSTRICH, Praefix
-- OUTFITS_; Platzhalter nur %s und %d, in allen Sprachen gleich in Anzahl
-- und Reihenfolge. Keine Pluralformen (Formulierungen wie "Pieces: %d").
--
-- Platz (Richtwerte bei 10-pt-Schrift; zu lange Texte werden abgeschnitten):
--   * OUTFITS_LOAD / _OVERWRITE / _RENAME / _DELETE: Zeilenknoepfe, hoechstens
--     etwa 16 Zeichen (die breiteste Beschriftung bestimmt die Knopfbreite).
--   * OUTFITS_SAVE: Knopf oben, etwa 40 Zeichen.
--   * OUTFITS_PIECES / _PIECES_PARTIAL: Zeile neben dem Namen, etwa 22 Zeichen;
--     ist der Text laenger, steht dort stattdessen die Kurzform "7/10".
--   * OUTFITS_SAVED, _LOADED*, _OVERWRITTEN, _RENAMED, _DELETED: Statuszeile
--     im Fenster, etwa 45 Zeichen (der Name des Outfits kommt noch dazu).
--   * OUTFITS_EMPTY_TITLE: eine Zeile, etwa 40 Zeichen; _EMPTY_TEXT: bis etwa
--     400 Zeichen, wird umbrochen.
--   * OUTFITS_PAGE: etwa 20 Zeichen.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("enUS", {
   -- Kopfzeile
   OUTFITS_SAVE = "Save current look",
   OUTFITS_SAVE_TIP = "Stores the appearances you currently have applied or selected as a new outfit.",
   OUTFITS_COUNT = "%d / %d",

   -- Speichern-Dialog
   OUTFITS_SAVE_TITLE = "Save outfit",
   OUTFITS_SAVE_TEXT = "Enter a name for this outfit:",
   OUTFITS_SAVED = "Outfit \"%s\" saved.",

   -- Zeilen
   OUTFITS_PIECES = "Pieces: %d",
   OUTFITS_PIECES_PARTIAL = "Available: %d of %d",
   OUTFITS_HIDDEN = "Hidden",
   OUTFITS_LOADING = "Loading...",
   OUTFITS_ITEM_UNKNOWN = "Item %d",
   OUTFITS_TIP_CURRENT = "Matches your current look.",

   -- Laden
   OUTFITS_LOAD = "Load",
   OUTFITS_LOAD_TIP = "Selects the pieces of this outfit in the wardrobe. Nothing is applied until you click Apply.",
   OUTFITS_LOADED = "Pieces loaded: %d",
   OUTFITS_LOADED_PARTIAL = "Pieces loaded: %d, not available: %d",
   OUTFITS_LOADED_NONE = "No piece could be loaded (not available: %d)",
   OUTFITS_LOADED_PENDING = "Pieces loaded: %d, still loading: %d",
   OUTFITS_LOADED_WAIT = "Appearances are still loading - try again.",
   OUTFITS_LOADED_EMPTY = "This outfit contains no pieces.",

   -- Ueberschreiben
   OUTFITS_OVERWRITE = "Overwrite",
   OUTFITS_OVERWRITE_TIP = "Replaces the pieces of this outfit with your current look.",
   OUTFITS_OVERWRITE_TITLE = "Overwrite outfit",
   OUTFITS_OVERWRITE_TEXT = "Replace the pieces of the outfit \"%s\" with your current look?",
   OUTFITS_OVERWRITTEN = "Outfit \"%s\" updated.",

   -- Umbenennen
   OUTFITS_RENAME = "Rename",
   OUTFITS_RENAME_TIP = "Changes the name of this outfit.",
   OUTFITS_RENAME_TITLE = "Rename outfit",
   OUTFITS_RENAME_TEXT = "Enter a new name for the outfit \"%s\":",
   OUTFITS_RENAMED = "Outfit renamed to \"%s\".",

   -- Loeschen
   OUTFITS_DELETE = "Delete",
   OUTFITS_DELETE_TIP = "Removes this outfit permanently.",
   OUTFITS_DELETE_TITLE = "Delete outfit",
   OUTFITS_DELETE_TEXT = "Delete the outfit \"%s\"? This cannot be undone.",
   OUTFITS_DELETED = "Outfit \"%s\" deleted.",

   -- Leerzustand
   OUTFITS_EMPTY_TITLE = "No outfits yet",
   OUTFITS_EMPTY_TEXT = "Outfits save the pieces you currently have selected or applied, so you can bring "
      .. "back a whole look with one click. Choose appearances on the Items tab, then click "
      .. "\"Save current look\" and give the outfit a name.",

   -- Blaetterleiste
   OUTFITS_PAGE = "Page %d / %d",
   OUTFITS_PAGE_PREV = "Previous page",
   OUTFITS_PAGE_NEXT = "Next page",
})
