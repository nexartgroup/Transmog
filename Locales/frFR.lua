-- Locales\frFR.lua
-- ---------------------------------------------------------------------------
-- Franzoesische Texte fuer alle Module. Quelle: Locales\enUS_*.lua.
--
-- Begriffe (einheitlich, ein Wort je Begriff; wie im franzoesischen Client):
--   apparence (Aussehen; "current look" = apparence actuelle), tenue (Outfit),
--   emplacement (Ausruestungsplatz), piece (Teil eines Outfits), favori
--   (Favorit), objet (Gegenstand), qualite (Qualitaet), garde-robe (Wardrobe),
--   transmogrification / transmogrificateur, debloquer (freischalten),
--   collectee (gesammelt), en attente (ausstehend), infobulle (Tooltip),
--   notification (Toast), ancre (Anker).
--   Verben: appliquer (Anwenden), abandonner (Verwerfen), annuler (Abbrechen),
--   retirer (Entfernen), supprimer (Loeschen), masquer / masque (Verbergen /
--   verborgen), afficher (Zeigen), reinitialiser (Zuruecksetzen).
-- Anrede: vous (wie die Blizzard-Texte in 3.3.5a). Hinweiszeilen und Knopf-
-- Tooltips im Infinitiv ("Clic gauche : modifier"), ganze Saetze im Imperativ
-- ("Cliquez pour ...").
-- Typografie: vor : ; ! ? steht ein normales Leerzeichen (die Tests verlangen
-- ASCII-Leerzeichen, kein geschuetztes); Namen stehen in "%s" mit geraden
-- Anfuehrungszeichen (ebenfalls Testvorgabe); Auslassung als "..." (der Client-
-- Font hat kein U+2026); Apostroph gerade.
-- Platzhalter (%s, %d) stehen in gleicher Anzahl und Reihenfolge wie in enUS.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("frFR", {
   -- =========================================================================
   -- Core
   -- =========================================================================
   THOUSANDS_SEP = " ",

   LOADED = "%s %s chargé - tapez /transmog pour ouvrir la fenêtre.",
   MIGRATED_OUTFITS = "Tenues importées depuis la version précédente de Transmog : %d",

   -- =========================================================================
   -- Boot
   -- =========================================================================
   -- Tastenbelegung
   BOOT_BINDING_HEADER = "Transmogrification",
   BOOT_BINDING_TOGGLE = "Ouvrir ou fermer la fenêtre de transmogrification",

   BOOT_INIT_FAILED = "Le module %s n'a pas pu démarrer. Consultez le rapport d'erreurs pour plus de détails.",
   BOOT_UNAVAILABLE = "Cette partie de l'addon n'est pas disponible.",

   BOOT_RESET_DONE = "La position et la taille de la fenêtre ont été réinitialisées.",
   BOOT_LANG_SET = "Langue définie sur %s.",
   BOOT_LANG_CURRENT = "Langue actuelle : %s. Utilisez auto ou l'un des codes suivants : %s",
   BOOT_LANG_UNKNOWN = "Langue inconnue \"%s\". Utilisez auto ou l'un des codes suivants : %s",

   BOOT_DEBUG_ON = "Sortie de débogage activée.",
   BOOT_DEBUG_OFF = "Sortie de débogage désactivée.",
   BOOT_DEBUG_INFO = "Version %s, langue %s, état du serveur %s, messages envoyés %d, reçus %d.",
   BOOT_DEBUG_STATE = "Chez le transmogrificateur : %s, modifications en attente : %d, listes prêtes : %s.",
   BOOT_DEBUG_ITEMS = "Requêtes d'objets en attente : %d, échouées : %d, minuteurs : %d, textes manquants : %d.",
   BOOT_YES = "oui",
   BOOT_NO = "non",

   BOOT_HELP_TITLE = "Commandes (/transmog ou /xmog) :",
   BOOT_HELP_TOGGLE = "/transmog - ouvrir ou fermer la fenêtre",
   BOOT_HELP_OPTIONS = "/transmog options - ouvrir les options",
   BOOT_HELP_RESET = "/transmog reset - réinitialiser la position et la taille de la fenêtre",
   BOOT_HELP_TOAST = "/transmog toast - déplacer l'ancre des notifications",
   BOOT_HELP_LANG = "/transmog lang <code|auto> - définir la langue",
   BOOT_HELP_DEBUG = "/transmog debug - activer ou désactiver le débogage",
   BOOT_HELP_HELP = "/transmog help - afficher cette liste",

   -- =========================================================================
   -- State
   -- =========================================================================
   APPLY_REASON_NONE         = "Rien n'a encore été modifié.",
   APPLY_REASON_VENDOR       = "Rendez-vous chez un transmogrificateur pour appliquer les modifications.",
   APPLY_REASON_BUSY         = "Application des modifications...",
   APPLY_REASON_COST_PENDING = "Calcul du coût...",
   APPLY_REASON_MONEY        = "Vous n'avez pas assez d'argent.",
   APPLY_REASON_SERVER       = "Le module serveur de transmogrification ne répond pas.",

   MSG_APPLY_OK           = "Apparence appliquée.",
   MSG_APPLY_DONE         = "Modifications réussies : %d, échouées : %d.",
   MSG_APPLY_SLOT_FAILED  = "Échec de l'application : %s.",
   MSG_SERVER_ABSENT      = "Le module serveur de transmogrification ne répond pas.",
   MSG_NO_VENDOR          = "Mode aperçu - rendez-vous chez un transmogrificateur pour appliquer les modifications.",

   -- =========================================================================
   -- Filter / Outfits (Core)
   -- =========================================================================
   SORT_QUALITY = "Qualité",
   SORT_NAME = "Nom",
   SORT_ILEVEL = "Niveau d'objet",

   OUTFIT_DEFAULT_NAME = "Tenue %d",
   OUTFIT_ERR_EMPTY = "Veuillez saisir un nom pour la tenue.",
   OUTFIT_ERR_EXISTS = "Une tenue portant ce nom existe déjà.",
   OUTFIT_ERR_LONG = "Le nom est trop long (32 caractères maximum).",
   OUTFIT_ERR_FULL = "Vous avez atteint le nombre maximal de tenues.",
   OUTFIT_ERR_NOITEMS = "Rien à enregistrer : aucune apparence n'est appliquée ou sélectionnée.",
   OUTFIT_ERR_MISSING = "Cette tenue n'existe plus.",

   OUTFIT_SKIP_EMPTY = "Rien n'est équipé à cet emplacement.",
   OUTFIT_SKIP_NEVER = "Cet emplacement ne peut pas être transmogrifié.",
   OUTFIT_SKIP_LOADING = "La liste des apparences de cet emplacement est en cours de chargement.",
   OUTFIT_SKIP_UNAVAILABLE = "Cette apparence n'est pas disponible pour l'objet équipé.",
   OUTFIT_SKIP_HIDDEN = "Cet emplacement ne peut pas être masqué.",

   -- =========================================================================
   -- Window
   -- =========================================================================
   WIN_TITLE = "Transmogrification",
   WIN_TAB_ITEMS = "Objets",
   WIN_TAB_OUTFITS = "Tenues",
   WIN_OPTIONS = "Options",
   WIN_CLOSE = "Fermer",
   WIN_RESIZE_TIP = "Faites glisser pour redimensionner la fenêtre.",

   WIN_APPLY = "Appliquer",
   WIN_APPLY_RESET = "Appliquer l'original",
   WIN_APPLY_TIP = "Appliquer les modifications en attente : %d",
   WIN_TIP_REMOVE = "Retirer l'apparence",
   WIN_TIP_HIDDEN = "Masqué",

   WIN_DISCARD = "Abandonner",
   WIN_DISCARD_TIP = "Abandonner toutes les modifications en attente.",
   WIN_DISCARD_NONE = "Aucune modification en attente.",
   WIN_REMOVE_ALL = "Tout retirer",
   WIN_REMOVE_ALL_TIP = "Retirer toutes les apparences appliquées.",
   WIN_REMOVE_ALL_NONE = "Aucune apparence n'est appliquée.",
   WIN_REMOVE_ALL_TITLE = "Retirer toutes les apparences",
   WIN_REMOVE_ALL_TEXT = "Retirer toutes les apparences appliquées ? Votre équipement retrouvera son apparence d'origine.",
   WIN_REMOVED_ALL = "Toutes les apparences ont été retirées.",
   WIN_CANCEL = "Annuler",

   WIN_COST = "Coût :",
   WIN_COST_FREE = "Gratuit",
   WIN_COST_PENDING = "...",
   WIN_COST_UNKNOWN = "?",

   WIN_STATUS_PENDING = "Modifications en attente : %d",
   WIN_STATUS_APPLYING = "Application des modifications (%d)...",

   -- =========================================================================
   -- Preview
   -- =========================================================================
   PREVIEW_ROTATE_LEFT = "Pivoter vers la gauche",
   PREVIEW_ROTATE_RIGHT = "Pivoter vers la droite",
   PREVIEW_ROTATE_HOLD = "Maintenez le bouton de la souris enfoncé pour continuer à pivoter.",

   PREVIEW_RESET = "Réinitialiser la vue",
   PREVIEW_RESET_TIP = "Réinitialiser la rotation, la position et le zoom.",

   PREVIEW_HELP_ROTATE = "Glisser avec le bouton gauche : pivoter",
   PREVIEW_HELP_MOVE = "Glisser avec le bouton droit : déplacer",
   PREVIEW_HELP_ZOOM = "Molette de la souris : zoomer",

   PREVIEW_OFFHAND_NOTE = "Les armes à une main tenues en main gauche ne sont pas affichées dans cet aperçu.",
   PREVIEW_OFFHAND_NOTE_MAINHAND = "Cette arme à une main est affichée dans la main droite (limite du client).",

   -- =========================================================================
   -- SlotBar
   -- =========================================================================
   SLOTBAR_NOTHING_EQUIPPED = "Aucun objet équipé",
   SLOTBAR_NEVER = "Ne peut pas être transmogrifié",

   SLOTBAR_APPLIED = "Transmogrifié en : %s",
   SLOTBAR_HIDDEN = "Masqué",
   SLOTBAR_PENDING = "En attente : %s",
   SLOTBAR_PENDING_RESET = "En attente : retour à l'original",
   SLOTBAR_INACTIVE = "Inactif : %s (incompatible avec l'objet équipé)",
   SLOTBAR_UNKNOWN_ITEM = "Objet %d",

   SLOTBAR_AVAILABLE = "Disponibles : %d",
   SLOTBAR_LOADING = "Chargement des apparences : %d / %d",

   SLOTBAR_HINT_EDIT = "Clic gauche : modifier",
   SLOTBAR_HINT_DISCARD = "Clic droit : abandonner la modification en attente",
   SLOTBAR_HINT_REMOVE = "Clic droit : retirer la transmogrification",
   SLOTBAR_HINT_LINK = "Maj + clic : lier dans la discussion",

   -- =========================================================================
   -- Grid
   -- =========================================================================
   GRID_NO_SLOT           = "Sélectionnez un emplacement d'équipement",
   GRID_NO_SLOT_HINT      = "Choisissez un emplacement à gauche pour parcourir ses apparences.",
   GRID_EMPTY_SLOT        = "Rien n'est équipé à cet emplacement",
   GRID_EMPTY_SLOT_HINT   = "Équipez un objet pour voir les apparences qui lui correspondent.",
   GRID_NEVER             = "Cet objet ne peut pas être transmogrifié",
   GRID_NEVER_HINT        = "Les anneaux, colliers, bijoux et reliques ne peuvent pas changer d'apparence.",
   GRID_ABSENT            = "Le module serveur de transmogrification ne répond pas",
   GRID_ABSENT_HINT       = "Les apparences sont chargées depuis le serveur. Vérifiez que mod-transmog-plus est installé et activé.",
   GRID_NO_ITEMS          = "Aucune apparence correspondante pour l'instant",
   GRID_NO_ITEMS_HINT     = "Elles se débloquent lorsque vous obtenez des objets adaptés à cet emplacement.",
   GRID_FILTERED          = "Aucune apparence ne correspond à vos filtres",
   GRID_FILTERED_HINT     = "Modifiez ou réinitialisez les filtres ci-dessus pour en voir davantage.",
   GRID_RESET_FILTERS     = "Réinitialiser les filtres",

   GRID_LOADING           = "Chargement des apparences... %s / %s",
   GRID_LOADING_PLAIN     = "Chargement des apparences...",
   GRID_LOADING_HINT      = "Les données des objets sont demandées au serveur.",
   GRID_PLACEHOLDER       = "...",

   GRID_PAGE              = "Page %d / %d",
   GRID_PAGE_SHORT        = "%d / %d",
   GRID_COUNT             = "%s sur %s apparences",
   GRID_COUNT_FILTERED    = "%s sur %s apparences (filtrées)",
   GRID_COUNT_DUPES       = "%s sur %s apparences (%s doublons masqués)",
   GRID_COUNT_SHORT       = "%s / %s",
   GRID_PAGE_FIRST        = "Première page",
   GRID_PAGE_PREV         = "Page précédente",
   GRID_PAGE_NEXT         = "Page suivante",
   GRID_PAGE_LAST         = "Dernière page",

   GRID_ORIGINAL          = "Original",
   GRID_ORIGINAL_TITLE    = "Apparence d'origine",
   GRID_ORIGINAL_TIP      = "Sélectionnez pour retirer la transmogrification et retrouver l'apparence d'origine de l'objet équipé.",
   GRID_HIDDEN            = "Masqué",
   GRID_HIDDEN_TIP        = "Sélectionnez pour masquer l'équipement de cet emplacement.",

   GRID_NEW               = "NOUV.",
   GRID_TIP_APPLIED       = "Actuellement appliquée",
   GRID_TIP_SELECTED      = "Sélectionnée - pas encore appliquée",
   GRID_TIP_FAVORITE      = "Favorite",
   GRID_TIP_NEW           = "Nouvellement débloquée",
   GRID_TIP_LEFT_SELECT   = "Clic gauche : sélectionner",
   GRID_TIP_LEFT_DISCARD  = "Clic gauche : abandonner la sélection",
   GRID_TIP_RIGHT_FAV     = "Clic droit : ajouter ou retirer des favoris",
   GRID_TIP_SHIFT_LINK    = "Maj + clic gauche : lier dans la discussion",

   -- =========================================================================
   -- FilterBar
   -- =========================================================================
   FILTER_SEARCH_PLACEHOLDER = "Nom, type ou #id",

   FILTER_SORT               = "Tri : %s",
   FILTER_SORT_TIP           = "Ordre de tri",
   FILTER_SORT_TIP_HINT      = "Cliquez pour choisir le tri des apparences.",

   FILTER_BUTTON             = "Filtres",
   FILTER_BUTTON_TIP         = "Filtrer les apparences",
   FILTER_HIDE_DUPLICATES    = "Masquer les doublons",
   FILTER_HIDE_DUPLICATES_TIP = "N'affiche qu'une seule entrée pour les apparences ayant la même icône, le même type et "
      .. "le même emplacement (approximation : le client ne peut pas lire le modèle réel).",
   FILTER_FAVORITES_ONLY     = "Favoris uniquement",
   FILTER_NEW_ONLY           = "Nouveautés uniquement",
   FILTER_TYPE_TITLE         = "Type",
   FILTER_TYPE_ROW           = "%s (%d)",
   FILTER_TYPE_OWN           = "C'est le type de votre objet équipé ; il ne peut pas être masqué.",
   FILTER_RESET              = "Réinitialiser les filtres",

   FILTER_RESET_TIP          = "Réinitialiser tous les filtres",
   FILTER_RESET_NONE         = "Aucun filtre actif.",

   FILTER_QUALITY_COUNT      = "Apparences : %d",
   FILTER_QUALITY_HIDE       = "Cliquez pour masquer cette qualité",
   FILTER_QUALITY_SHOW       = "Cliquez pour afficher cette qualité",

   FILTER_FAVORITES_CHIP     = "Favoris",
   FILTER_FAVORITES_CHIP_TIP = "Afficher uniquement les apparences favorites",
   FILTER_NEW                = "Nouveautés",
   FILTER_NEW_TIP            = "Afficher uniquement les apparences nouvellement débloquées",
   FILTER_CHIP_ON            = "Actif - cliquez pour désactiver",
   FILTER_CHIP_OFF           = "Cliquez pour activer",

   -- =========================================================================
   -- Outfits
   -- =========================================================================
   OUTFITS_SAVE = "Enregistrer l'apparence actuelle",
   OUTFITS_SAVE_TIP = "Enregistre les apparences actuellement appliquées ou sélectionnées comme nouvelle tenue.",
   OUTFITS_COUNT = "%d / %d",

   OUTFITS_SAVE_TITLE = "Enregistrer la tenue",
   OUTFITS_SAVE_TEXT = "Saisissez un nom pour cette tenue :",
   OUTFITS_SAVED = "Tenue \"%s\" enregistrée.",

   OUTFITS_PIECES = "Pièces : %d",
   OUTFITS_PIECES_PARTIAL = "Disponibles : %d/%d",
   OUTFITS_HIDDEN = "Masqué",
   OUTFITS_LOADING = "Chargement...",
   OUTFITS_ITEM_UNKNOWN = "Objet %d",
   OUTFITS_TIP_CURRENT = "Correspond à votre apparence actuelle.",

   OUTFITS_LOAD = "Charger",
   OUTFITS_LOAD_TIP = "Sélectionne les pièces de cette tenue dans la garde-robe. Rien n'est appliqué tant que vous ne "
      .. "cliquez pas sur Appliquer.",
   OUTFITS_LOADED = "Pièces chargées : %d",
   OUTFITS_LOADED_PARTIAL = "Pièces chargées : %d, indisponibles : %d",
   OUTFITS_LOADED_NONE = "Aucune pièce chargée (indisponibles : %d)",
   OUTFITS_LOADED_PENDING = "Pièces chargées : %d, en chargement : %d",
   OUTFITS_LOADED_WAIT = "Apparences en chargement - réessayez.",
   OUTFITS_LOADED_EMPTY = "Cette tenue ne contient aucune pièce.",

   OUTFITS_OVERWRITE = "Écraser",
   OUTFITS_OVERWRITE_TIP = "Remplace les pièces de cette tenue par votre apparence actuelle.",
   OUTFITS_OVERWRITE_TITLE = "Écraser la tenue",
   OUTFITS_OVERWRITE_TEXT = "Remplacer les pièces de la tenue \"%s\" par votre apparence actuelle ?",
   OUTFITS_OVERWRITTEN = "Tenue \"%s\" mise à jour.",

   OUTFITS_RENAME = "Renommer",
   OUTFITS_RENAME_TIP = "Modifie le nom de cette tenue.",
   OUTFITS_RENAME_TITLE = "Renommer la tenue",
   OUTFITS_RENAME_TEXT = "Saisissez un nouveau nom pour la tenue \"%s\" :",
   OUTFITS_RENAMED = "Tenue renommée en \"%s\".",

   OUTFITS_DELETE = "Supprimer",
   OUTFITS_DELETE_TIP = "Supprime définitivement cette tenue.",
   OUTFITS_DELETE_TITLE = "Supprimer la tenue",
   OUTFITS_DELETE_TEXT = "Supprimer la tenue \"%s\" ? Cette action est irréversible.",
   OUTFITS_DELETED = "Tenue \"%s\" supprimée.",

   OUTFITS_EMPTY_TITLE = "Aucune tenue pour l'instant",
   OUTFITS_EMPTY_TEXT = "Les tenues enregistrent les pièces que vous avez sélectionnées ou appliquées, afin de "
      .. "retrouver un ensemble complet d'un simple clic. Choisissez des apparences dans l'onglet Objets, "
      .. "cliquez sur \"Enregistrer l'apparence actuelle\", puis donnez un nom à la tenue.",

   OUTFITS_PAGE = "Page %d / %d",
   OUTFITS_PAGE_PREV = "Page précédente",
   OUTFITS_PAGE_NEXT = "Page suivante",

   -- =========================================================================
   -- Options
   -- =========================================================================
   OPT_TITLE = "Options de transmogrification",

   OPT_SECTION_LANGUAGE = "Langue",
   OPT_LANG_AUTO = "Auto (langue du client : %s)",
   OPT_LANG_TIP = "Langue de tous les textes de cet addon.",
   OPT_LANG_NOTE = "Si la langue diffère de celle de votre client de jeu, la police peut ne pas contenir "
      .. "certains caractères.",

   OPT_SECTION_WINDOW = "Fenêtre",
   OPT_SCALE = "Échelle de la fenêtre",
   OPT_SCALE_AUTO = "Auto",
   OPT_SCALE_TIP = "Auto adapte la fenêtre à votre écran. Déplacez le curseur pour choisir une échelle fixe.",
   OPT_PREVIEW_SIZE = "Taille de l'aperçu",
   OPT_PREVIEW_TIP = "Taille des aperçus d'apparences dans la grille d'objets.",
   OPT_PREVIEW_SMALL = "Petite",
   OPT_PREVIEW_MEDIUM = "Moyenne",
   OPT_PREVIEW_LARGE = "Grande",
   OPT_PREVIEW_XLARGE = "Très grande",
   OPT_RESET_WINDOW = "Réinitialiser la position et la taille de la fenêtre",
   OPT_RESET_WINDOW_TIP = "Remet la fenêtre de la garde-robe à sa position et à sa taille par défaut.",
   OPT_RESET_DONE = "La position et la taille de la fenêtre ont été réinitialisées.",

   OPT_SECTION_GENERAL = "Général",
   OPT_SOUND = "Son lors de l'application",
   OPT_SOUND_TIP = "Joue un son lorsque les modifications ont été appliquées avec succès.",
   OPT_TOASTS = "Notifications pour les nouvelles apparences",
   OPT_TOASTS_TIP = "Affiche une petite notification lorsque vous débloquez une nouvelle apparence.",
   OPT_TOOLTIP_COLLECTED = "Infobulle : afficher \"apparence non collectée\"",
   OPT_TOOLTIP_COLLECTED_TIP = "Ajoute une ligne aux infobulles des objets lorsque vous n'avez pas encore collecté l'apparence.",
   OPT_TOOLTIP_APPLIED = "Infobulle : afficher \"transmogrifié en\"",
   OPT_TOOLTIP_APPLIED_TIP = "Ajoute à l'infobulle de vos objets équipés une ligne indiquant l'apparence qui leur est appliquée.",
   OPT_ALLOW_ANYWHERE = "Autoriser l'application sans transmogrificateur",
   OPT_ALLOW_ANYWHERE_TIP = "Le serveur ne vérifie pas votre distance par rapport à un transmogrificateur. "
      .. "Si cette option est activée (par défaut), les modifications peuvent être appliquées de n'importe où. "
      .. "Si elle est désactivée, /transmog n'ouvre que le mode aperçu et l'addon n'applique les modifications "
      .. "que pendant que vous parlez à un transmogrificateur.",

   OPT_MOVE_TOASTS = "Déplacer les notifications",
   OPT_MOVE_TOASTS_TIP = "Affiche l'ancre des notifications pour que vous puissiez la faire glisser vers une nouvelle position.",
   OPT_TEST_TOAST = "Notification de test",
   OPT_TEST_TOAST_TIP = "Affiche un exemple de notification.",

   -- =========================================================================
   -- Features (Tooltips, Toasts)
   -- =========================================================================
   TIP_NOT_COLLECTED = "Apparence non collectée",

   TIP_APPLIED = "Transmogrifié en : %s",
   TIP_APPLIED_HIDDEN = "Transmogrifié en : Masqué",
   TIP_INACTIVE = "Transmogrification inactive : %s",
   TIP_ITEM_UNKNOWN = "Objet %d",

   TOAST_TITLE = "Nouvelle apparence débloquée",
   TOAST_ITEM_UNKNOWN = "Objet %d",

   TOAST_BURST_TITLE = "Apparences débloquées",
   TOAST_BURST_COUNT = "Apparences : %d",

   TOAST_ANCHOR_LABEL = "Déplacez-moi",
   TOAST_ANCHOR_TIP_TITLE = "Position des notifications",
   TOAST_ANCHOR_TIP_DRAG = "Faites glisser pour déplacer les notifications.",
   TOAST_ANCHOR_TIP_RESET = "Clic droit : réinitialiser la position.",

   -- Hinweis fuer die Nebenhand-Vorschau (Client-Grenze)
   GRID_TIP_OFFHAND_PREVIEW = "L'aperçu affiche les armes à une main dans la main droite (limite du client).",
})
