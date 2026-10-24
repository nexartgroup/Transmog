-- Locales\deDE.lua
-- ---------------------------------------------------------------------------
-- Deutsche Texte (Deutschland) fuer alle Module. Quelle: Locales\enUS_*.lua.
--
-- Begriffe (einheitlich): Aussehen, Outfit, Platz (Ausruestungsplatz), Teil
-- (Teil eines Outfits), Look (die Gesamtheit der gewaehlten/angewendeten
-- Aussehen), Favorit, Anwenden, Verwerfen, Verborgen, Qualitaet,
-- Gegenstand, Transmogrifizierer, angelegt (= ausgeruestet).
-- Anrede: du/dein. Hinweise mit der Maus im Infinitiv ("Klicken, um ..."),
-- Aufforderungen im Imperativ ("Gib einen Namen ein").
-- Anfuehrungszeichen: gerade ASCII-Zeichen (so verlangt es test_locales.lua;
-- die Schrift des 3.3.5a-Clients hat sie sicher).
-- Platzhalter (%s, %d) stehen in gleicher Anzahl und Reihenfolge wie in enUS.
-- Breiten: siehe die Platzangaben in den enUS-Dateien; die breitesten Stellen
-- sind SORT_ILEVEL mit FILTER_SORT (Sortierknopf, im Mindestfenster das
-- Suchfeld daneben), WIN_APPLY_RESET, OPT_MOVE_TOASTS und TOAST_TITLE.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("deDE", {
   -- =========================================================================
   -- Core
   -- =========================================================================
   THOUSANDS_SEP = ".",

   LOADED = "%s %s geladen - mit /transmog öffnest du das Fenster.",
   MIGRATED_OUTFITS = "Outfits aus der vorherigen Transmog-Version übernommen: %d",

   -- =========================================================================
   -- Boot
   -- =========================================================================
   -- Tastenbelegung
   BOOT_BINDING_HEADER = "Transmogrifikation",
   BOOT_BINDING_TOGGLE = "Transmogrifikationsfenster öffnen/schließen",

   BOOT_INIT_FAILED = "Das Modul %s konnte nicht gestartet werden. Details stehen im Fehlerbericht.",
   BOOT_UNAVAILABLE = "Dieser Teil des Addons ist nicht verfügbar.",

   BOOT_RESET_DONE = "Fensterposition und -größe wurden zurückgesetzt.",
   BOOT_LANG_SET = "Sprache auf %s gesetzt.",
   BOOT_LANG_CURRENT = "Aktuelle Sprache: %s. Mögliche Werte: %s",
   BOOT_LANG_UNKNOWN = "Unbekannte Sprache \"%s\". Mögliche Werte: %s",

   BOOT_DEBUG_ON = "Debug-Ausgabe aktiviert.",
   BOOT_DEBUG_OFF = "Debug-Ausgabe deaktiviert.",
   BOOT_DEBUG_INFO = "Version %s, Sprache %s, Serverstatus %s, Nachrichten: %d gesendet, %d empfangen.",
   BOOT_DEBUG_STATE = "Am Transmogrifizierer: %s, ausstehende Änderungen: %d, Listen bereit: %s.",
   BOOT_DEBUG_ITEMS = "Offene Gegenstandsabfragen: %d, fehlgeschlagen: %d, Timer: %d, fehlende Texte: %d.",
   BOOT_YES = "ja",
   BOOT_NO = "nein",

   BOOT_HELP_TITLE = "Befehle (/transmog oder /xmog):",
   BOOT_HELP_TOGGLE = "/transmog - Fenster öffnen oder schließen",
   BOOT_HELP_OPTIONS = "/transmog options - Optionen öffnen",
   BOOT_HELP_RESET = "/transmog reset - Fensterposition und -größe zurücksetzen",
   BOOT_HELP_TOAST = "/transmog toast - Benachrichtigungen verschieben",
   BOOT_HELP_LANG = "/transmog lang <code|auto> - Sprache festlegen",
   BOOT_HELP_DEBUG = "/transmog debug - Debug-Ausgabe ein- oder ausschalten",
   BOOT_HELP_HELP = "/transmog help - diese Liste anzeigen",

   -- =========================================================================
   -- State
   -- =========================================================================
   APPLY_REASON_NONE         = "Es wurde noch nichts geändert.",
   APPLY_REASON_VENDOR       = "Sprich mit einem Transmogrifizierer, um Änderungen anzuwenden.",
   APPLY_REASON_BUSY         = "Änderungen werden angewendet...",
   APPLY_REASON_COST_PENDING = "Kosten werden berechnet...",
   APPLY_REASON_MONEY        = "Du hast nicht genug Gold.",
   APPLY_REASON_SERVER       = "Das Transmog-Servermodul antwortet nicht.",

   MSG_APPLY_OK           = "Aussehen angewendet.",
   MSG_APPLY_DONE         = "%d angewendet, %d fehlgeschlagen.",
   MSG_APPLY_SLOT_FAILED  = "Anwenden fehlgeschlagen: %s",
   MSG_SERVER_ABSENT      = "Das Transmog-Servermodul antwortet nicht.",
   MSG_NO_VENDOR          = "Vorschau-Modus - sprich mit einem Transmogrifizierer, um Änderungen anzuwenden.",

   -- =========================================================================
   -- Filter / Outfits (Core)
   -- =========================================================================
   SORT_QUALITY = "Qualität",
   SORT_NAME = "Name",
   SORT_ILEVEL = "Gegenstandsstufe",

   OUTFIT_DEFAULT_NAME = "Outfit %d",
   OUTFIT_ERR_EMPTY = "Bitte gib einen Namen für das Outfit ein.",
   OUTFIT_ERR_EXISTS = "Dieser Name ist bereits vergeben.",
   OUTFIT_ERR_LONG = "Der Name ist zu lang (maximal 32 Zeichen).",
   OUTFIT_ERR_FULL = "Maximale Anzahl an Outfits erreicht.",
   OUTFIT_ERR_NOITEMS = "Kein Aussehen angewendet oder ausgewählt.",
   OUTFIT_ERR_MISSING = "Dieses Outfit existiert nicht mehr.",

   OUTFIT_SKIP_EMPTY = "Auf diesem Platz ist nichts angelegt.",
   OUTFIT_SKIP_NEVER = "Dieser Platz kann nicht transmogrifiziert werden.",
   OUTFIT_SKIP_LOADING = "Die Liste der Aussehen für diesen Platz wird noch geladen.",
   OUTFIT_SKIP_UNAVAILABLE = "Dieses Aussehen ist für deinen angelegten Gegenstand nicht verfügbar.",
   OUTFIT_SKIP_HIDDEN = "Dieser Platz kann nicht verborgen werden.",

   -- =========================================================================
   -- Window
   -- =========================================================================
   WIN_TITLE = "Transmogrifikation",
   WIN_TAB_ITEMS = "Gegenstände",
   WIN_TAB_OUTFITS = "Outfits",
   WIN_OPTIONS = "Optionen",
   WIN_CLOSE = "Schließen",
   WIN_RESIZE_TIP = "Ziehen, um die Fenstergröße zu ändern.",

   WIN_APPLY = "Anwenden",
   WIN_APPLY_RESET = "Original anwenden",
   WIN_APPLY_TIP = "Ausstehende Änderungen anwenden: %d",
   WIN_TIP_REMOVE = "Aussehen entfernen",
   WIN_TIP_HIDDEN = "Verborgen",

   WIN_DISCARD = "Verwerfen",
   WIN_DISCARD_TIP = "Alle ausstehenden Änderungen verwerfen.",
   WIN_DISCARD_NONE = "Es gibt keine ausstehenden Änderungen.",
   WIN_REMOVE_ALL = "Alle entfernen",
   WIN_REMOVE_ALL_TIP = "Alle angewendeten Aussehen entfernen.",
   WIN_REMOVE_ALL_NONE = "Es ist kein Aussehen angewendet.",
   WIN_REMOVE_ALL_TITLE = "Alle Aussehen entfernen",
   WIN_REMOVE_ALL_TEXT = "Alle angewendeten Aussehen entfernen? Deine Ausrüstung zeigt danach wieder ihr ursprüngliches Aussehen.",
   WIN_REMOVED_ALL = "Alle Aussehen entfernt.",
   WIN_CANCEL = "Abbrechen",

   WIN_COST = "Kosten:",
   WIN_COST_FREE = "Kostenlos",
   WIN_COST_PENDING = "...",
   WIN_COST_UNKNOWN = "?",

   WIN_STATUS_PENDING = "Ausstehende Änderungen: %d",
   WIN_STATUS_APPLYING = "Änderungen werden angewendet (%d)...",

   -- =========================================================================
   -- Preview
   -- =========================================================================
   PREVIEW_ROTATE_LEFT = "Nach links drehen",
   PREVIEW_ROTATE_RIGHT = "Nach rechts drehen",
   PREVIEW_ROTATE_HOLD = "Maustaste gedrückt halten, um weiterzudrehen.",

   PREVIEW_RESET = "Ansicht zurücksetzen",
   PREVIEW_RESET_TIP = "Setzt Drehung, Position und Zoom zurück.",

   PREVIEW_HELP_ROTATE = "Mit linker Maustaste ziehen: drehen",
   PREVIEW_HELP_MOVE = "Mit rechter Maustaste ziehen: verschieben",
   PREVIEW_HELP_ZOOM = "Mausrad: zoomen",

   PREVIEW_OFFHAND_NOTE = "Einhandwaffen in der Nebenhand werden in dieser Vorschau nicht angezeigt.",
   PREVIEW_OFFHAND_NOTE_MAINHAND = "Diese Einhandwaffe wird in der Haupthand gezeigt (Einschränkung des Clients).",

   -- =========================================================================
   -- SlotBar
   -- =========================================================================
   SLOTBAR_NOTHING_EQUIPPED = "Nichts angelegt",
   SLOTBAR_NEVER = "Nicht transmogrifizierbar",

   SLOTBAR_APPLIED = "Transmogrifiziert zu: %s",
   SLOTBAR_HIDDEN = "Verborgen",
   SLOTBAR_PENDING = "Ausstehend: %s",
   SLOTBAR_PENDING_RESET = "Ausstehend: auf Original zurücksetzen",
   SLOTBAR_INACTIVE = "Inaktiv: %s (passt nicht zum angelegten Gegenstand)",
   SLOTBAR_UNKNOWN_ITEM = "Gegenstand %d",

   SLOTBAR_AVAILABLE = "Verfügbar: %d",
   SLOTBAR_LOADING = "Aussehen werden geladen: %d / %d",

   SLOTBAR_HINT_EDIT = "Linksklick: bearbeiten",
   SLOTBAR_HINT_DISCARD = "Rechtsklick: ausstehende Änderung verwerfen",
   SLOTBAR_HINT_REMOVE = "Rechtsklick: Aussehen entfernen",
   SLOTBAR_HINT_LINK = "Umschalt-Klick: im Chat verlinken",

   -- =========================================================================
   -- Grid
   -- =========================================================================
   GRID_NO_SLOT           = "Wähle einen Ausrüstungsplatz",
   GRID_NO_SLOT_HINT      = "Wähle links einen Platz, um die passenden Aussehen anzuzeigen.",
   GRID_EMPTY_SLOT        = "Auf diesem Platz ist nichts angelegt",
   GRID_EMPTY_SLOT_HINT   = "Lege einen Gegenstand an, um passende Aussehen zu sehen.",
   GRID_NEVER             = "Dieser Gegenstand kann nicht transmogrifiziert werden",
   GRID_NEVER_HINT        = "Ringe, Halsketten, Schmuckstücke und Relikte können ihr Aussehen nicht ändern.",
   GRID_ABSENT            = "Das Transmog-Servermodul antwortet nicht",
   GRID_ABSENT_HINT       = "Die Aussehen werden vom Server geladen. Stelle sicher, dass mod-transmog-plus installiert und aktiviert ist.",
   GRID_NO_ITEMS          = "Noch keine passenden Aussehen",
   GRID_NO_ITEMS_HINT     = "Sie werden freigeschaltet, sobald du passende Gegenstände erhältst.",
   GRID_FILTERED          = "Keine Aussehen entsprechen deinen Filtern",
   GRID_FILTERED_HINT     = "Ändere die Filter oben oder setze sie zurück, um mehr zu sehen.",
   GRID_RESET_FILTERS     = "Filter zurücksetzen",

   GRID_LOADING           = "Aussehen werden geladen... %s / %s",
   GRID_LOADING_PLAIN     = "Aussehen werden geladen...",
   GRID_LOADING_HINT      = "Gegenstandsdaten werden vom Server angefordert.",
   GRID_PLACEHOLDER       = "...",

   GRID_PAGE              = "Seite %d / %d",
   GRID_PAGE_SHORT        = "%d / %d",
   GRID_COUNT             = "%s von %s Aussehen",
   GRID_COUNT_FILTERED    = "%s von %s Aussehen (gefiltert)",
   GRID_COUNT_DUPES       = "%s von %s Aussehen (%s Doppelte ausgeblendet)",
   GRID_COUNT_SHORT       = "%s / %s",
   GRID_PAGE_FIRST        = "Erste Seite",
   GRID_PAGE_PREV         = "Vorherige Seite",
   GRID_PAGE_NEXT         = "Nächste Seite",
   GRID_PAGE_LAST         = "Letzte Seite",

   GRID_ORIGINAL          = "Original",
   GRID_ORIGINAL_TITLE    = "Originalaussehen",
   GRID_ORIGINAL_TIP      = "Auswählen, um die Transmogrifikation zu entfernen und wieder das eigene Aussehen des Gegenstands anzuzeigen.",
   GRID_HIDDEN            = "Verborgen",
   GRID_HIDDEN_TIP        = "Auswählen, um die Ausrüstung auf diesem Platz zu verbergen.",

   GRID_NEW               = "NEU",
   GRID_TIP_APPLIED       = "Aktuell angewendet",
   GRID_TIP_SELECTED      = "Ausgewählt - noch nicht angewendet",
   GRID_TIP_FAVORITE      = "Favorit",
   GRID_TIP_NEW           = "Neu freigeschaltet",
   GRID_TIP_LEFT_SELECT   = "Linksklick: auswählen",
   GRID_TIP_LEFT_DISCARD  = "Linksklick: Auswahl verwerfen",
   GRID_TIP_RIGHT_FAV     = "Rechtsklick: Favorit setzen/entfernen",
   GRID_TIP_SHIFT_LINK    = "Umschalt + Linksklick: im Chat verlinken",

   -- =========================================================================
   -- FilterBar
   -- =========================================================================
   FILTER_SEARCH_PLACEHOLDER = "Name, Typ, #ID",

   FILTER_SORT               = "Sortierung: %s",
   FILTER_SORT_TIP           = "Sortierung",
   FILTER_SORT_TIP_HINT      = "Klicken, um die Sortierung der Aussehen zu wählen.",

   FILTER_BUTTON             = "Filter",
   FILTER_BUTTON_TIP         = "Aussehen filtern",
   FILTER_HIDE_DUPLICATES    = "Doppelte ausblenden",
   FILTER_HIDE_DUPLICATES_TIP = "Zeigt Aussehen mit gleichem Symbol, Typ und Platz nur einmal an. "
      .. "Das ist nur eine Näherung, denn der Client kann das echte Modell nicht auslesen.",
   FILTER_FAVORITES_ONLY     = "Nur Favoriten",
   FILTER_NEW_ONLY           = "Nur neue Aussehen",
   FILTER_TYPE_TITLE         = "Typ",
   FILTER_TYPE_ROW           = "%s (%d)",
   FILTER_TYPE_OWN           = "Der Typ deines angelegten Gegenstands kann nicht ausgeblendet werden.",
   FILTER_RESET              = "Filter zurücksetzen",

   FILTER_RESET_TIP          = "Alle Filter zurücksetzen",
   FILTER_RESET_NONE         = "Keine Filter aktiv.",

   FILTER_QUALITY_COUNT      = "Aussehen: %d",
   FILTER_QUALITY_HIDE       = "Zum Ausblenden klicken",
   FILTER_QUALITY_SHOW       = "Zum Einblenden klicken",

   FILTER_FAVORITES_CHIP     = "Favoriten",
   FILTER_FAVORITES_CHIP_TIP = "Nur favorisierte Aussehen anzeigen",
   FILTER_NEW                = "Neu",
   FILTER_NEW_TIP            = "Nur neu freigeschaltete Aussehen anzeigen",
   FILTER_CHIP_ON            = "Aktiv - zum Ausschalten klicken",
   FILTER_CHIP_OFF           = "Zum Einschalten klicken",

   -- =========================================================================
   -- Outfits
   -- =========================================================================
   OUTFITS_SAVE = "Aktuellen Look speichern",
   OUTFITS_SAVE_TIP = "Speichert die aktuell angewendeten oder ausgewählten Aussehen als neues Outfit.",
   OUTFITS_COUNT = "%d / %d",

   OUTFITS_SAVE_TITLE = "Outfit speichern",
   OUTFITS_SAVE_TEXT = "Gib einen Namen für dieses Outfit ein:",
   OUTFITS_SAVED = "Outfit \"%s\" gespeichert.",

   OUTFITS_PIECES = "Teile: %d",
   OUTFITS_PIECES_PARTIAL = "Verfügbar: %d / %d",
   OUTFITS_HIDDEN = "Verborgen",
   OUTFITS_LOADING = "Wird geladen...",
   OUTFITS_ITEM_UNKNOWN = "Gegenstand %d",
   OUTFITS_TIP_CURRENT = "Entspricht deinem aktuellen Look.",

   OUTFITS_LOAD = "Laden",
   OUTFITS_LOAD_TIP = "Wählt die Teile dieses Outfits in der Garderobe aus. "
      .. "Angewendet wird erst, wenn du auf \"Anwenden\" klickst.",
   OUTFITS_LOADED = "Teile geladen: %d",
   OUTFITS_LOADED_PARTIAL = "Teile geladen: %d, nicht verfügbar: %d",
   OUTFITS_LOADED_NONE = "Kein Teil geladen (nicht verfügbar: %d)",
   OUTFITS_LOADED_PENDING = "Teile geladen: %d, noch ausstehend: %d",
   OUTFITS_LOADED_WAIT = "Lädt noch - versuche es gleich erneut.",
   OUTFITS_LOADED_EMPTY = "Dieses Outfit enthält keine Teile.",

   OUTFITS_OVERWRITE = "Überschreiben",
   OUTFITS_OVERWRITE_TIP = "Ersetzt die Teile dieses Outfits durch deinen aktuellen Look.",
   OUTFITS_OVERWRITE_TITLE = "Outfit überschreiben",
   OUTFITS_OVERWRITE_TEXT = "Das Outfit \"%s\" mit deinem aktuellen Look überschreiben?",
   OUTFITS_OVERWRITTEN = "Outfit \"%s\" überschrieben.",

   OUTFITS_RENAME = "Umbenennen",
   OUTFITS_RENAME_TIP = "Ändert den Namen dieses Outfits.",
   OUTFITS_RENAME_TITLE = "Outfit umbenennen",
   OUTFITS_RENAME_TEXT = "Gib einen neuen Namen für das Outfit \"%s\" ein:",
   OUTFITS_RENAMED = "Outfit umbenannt in \"%s\".",

   OUTFITS_DELETE = "Löschen",
   OUTFITS_DELETE_TIP = "Löscht dieses Outfit dauerhaft.",
   OUTFITS_DELETE_TITLE = "Outfit löschen",
   OUTFITS_DELETE_TEXT = "Das Outfit \"%s\" löschen? Das kann nicht rückgängig gemacht werden.",
   OUTFITS_DELETED = "Outfit \"%s\" gelöscht.",

   OUTFITS_EMPTY_TITLE = "Noch keine Outfits",
   OUTFITS_EMPTY_TEXT = "Outfits speichern die Teile, die du gerade ausgewählt oder angewendet hast, damit du "
      .. "einen ganzen Look mit einem Klick wiederherstellen kannst. Wähle im Reiter \"Gegenstände\" "
      .. "Aussehen aus, klicke dann auf \"Aktuellen Look speichern\" und gib dem Outfit einen Namen.",

   OUTFITS_PAGE = "Seite %d / %d",
   OUTFITS_PAGE_PREV = "Vorherige Seite",
   OUTFITS_PAGE_NEXT = "Nächste Seite",

   -- =========================================================================
   -- Options
   -- =========================================================================
   OPT_TITLE = "Transmogrifikation - Optionen",

   OPT_SECTION_LANGUAGE = "Sprache",
   OPT_LANG_AUTO = "Auto (Spielsprache: %s)",
   OPT_LANG_TIP = "Sprache aller Texte in diesem Addon.",
   OPT_LANG_NOTE = "Weicht die Sprache von der deines Spielclients ab, können in der Schrift einige Zeichen fehlen.",

   OPT_SECTION_WINDOW = "Fenster",
   OPT_SCALE = "Skalierung",
   OPT_SCALE_AUTO = "Auto",
   OPT_SCALE_TIP = "Auto passt das Fenster an deinen Bildschirm an. Bewege den Regler, um eine feste Skalierung zu wählen.",
   OPT_PREVIEW_SIZE = "Vorschaugröße",
   OPT_PREVIEW_TIP = "Größe der Aussehen-Vorschauen im Raster.",
   OPT_PREVIEW_SMALL = "Klein",
   OPT_PREVIEW_MEDIUM = "Mittel",
   OPT_PREVIEW_LARGE = "Groß",
   OPT_PREVIEW_XLARGE = "Sehr groß",
   OPT_RESET_WINDOW = "Fensterposition und -größe zurücksetzen",
   OPT_RESET_WINDOW_TIP = "Setzt das Garderobenfenster auf Standardposition und -größe zurück.",
   OPT_RESET_DONE = "Fensterposition und -größe wurden zurückgesetzt.",

   OPT_SECTION_GENERAL = "Allgemein",
   OPT_SOUND = "Sound beim Anwenden",
   OPT_SOUND_TIP = "Spielt einen Sound ab, wenn Änderungen erfolgreich angewendet wurden.",
   OPT_TOASTS = "Benachrichtigungen für neue Aussehen",
   OPT_TOASTS_TIP = "Zeigt eine kleine Benachrichtigung, wenn du ein neues Aussehen freischaltest.",
   OPT_TOOLTIP_COLLECTED = "Tooltip: \"Aussehen noch nicht gesammelt\" anzeigen",
   OPT_TOOLTIP_COLLECTED_TIP = "Fügt Gegenstands-Tooltips eine Zeile hinzu, wenn du das Aussehen noch nicht gesammelt hast.",
   OPT_TOOLTIP_APPLIED = "Tooltip: \"Transmogrifiziert zu\" anzeigen",
   OPT_TOOLTIP_APPLIED_TIP = "Fügt dem Tooltip deiner angelegten Gegenstände eine Zeile mit dem angewendeten Aussehen hinzu.",
   OPT_ALLOW_ANYWHERE = "Anwenden auch ohne Transmogrifizierer",
   OPT_ALLOW_ANYWHERE_TIP = "Der Server prüft deine Entfernung zu einem Transmogrifizierer nicht. "
      .. "Ist diese Option aktiv (Vorgabe), lassen sich Änderungen von überall anwenden. Ist sie aus, "
      .. "öffnet /transmog nur den Vorschau-Modus, und das Addon wendet Änderungen nur an, während du "
      .. "mit einem Transmogrifizierer sprichst.",

   OPT_MOVE_TOASTS = "Benachrichtigung verschieben",
   OPT_MOVE_TOASTS_TIP = "Zeigt den Anker der Benachrichtigungen, damit du ihn an eine neue Position ziehen kannst.",
   OPT_TEST_TOAST = "Benachrichtigung testen",
   OPT_TEST_TOAST_TIP = "Zeigt eine Beispielbenachrichtigung.",

   -- =========================================================================
   -- Features (Tooltips, Toasts)
   -- =========================================================================
   TIP_NOT_COLLECTED = "Aussehen noch nicht gesammelt",

   TIP_APPLIED = "Transmogrifiziert zu: %s",
   TIP_APPLIED_HIDDEN = "Transmogrifiziert zu: Verborgen",
   TIP_INACTIVE = "Transmogrifikation inaktiv: %s",
   TIP_ITEM_UNKNOWN = "Gegenstand %d",

   TOAST_TITLE = "Neues Aussehen freigeschaltet",
   TOAST_ITEM_UNKNOWN = "Gegenstand %d",

   TOAST_BURST_TITLE = "Neue Aussehen freigeschaltet",
   TOAST_BURST_COUNT = "Aussehen: %d",

   TOAST_ANCHOR_LABEL = "Verschieben",
   TOAST_ANCHOR_TIP_TITLE = "Position der Benachrichtigungen",
   TOAST_ANCHOR_TIP_DRAG = "Ziehen, um die Benachrichtigungen zu verschieben.",
   TOAST_ANCHOR_TIP_RESET = "Rechtsklick: Position zurücksetzen.",

   -- Hinweis fuer die Nebenhand-Vorschau (Client-Grenze)
   GRID_TIP_OFFHAND_PREVIEW = "Die Vorschau zeigt Einhandwaffen in der Haupthand (Einschränkung des Clients).",
})
