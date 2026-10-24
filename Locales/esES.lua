-- Locales\esES.lua
-- ---------------------------------------------------------------------------
-- Spanische Texte (Spanien; esMX faellt darauf zurueck, deshalb nur Wortschatz,
-- der in ganz Spanischsprachig-Amerika verstanden wird) fuer alle Module.
-- Quelle: Locales\enUS_*.lua.
--
-- Begriffe (einheitlich): apariencia (Aussehen), aspecto (Look), conjunto
-- (Outfit), ranura (Ausruestungsplatz), pieza (Teil eines Outfits), favorita
-- (Favorit; weiblich wie apariencia), aplicar (Anwenden), descartar
-- (Verwerfen), quitar (Entfernen), restablecer (Zuruecksetzen), cancelar
-- (Abbrechen), oculto (Verborgen), calidad (Qualitaet), objeto (Gegenstand),
-- equipo (Ausruestung), transfiguracion / transfigurador / transfigurar
-- (Transmogrifikation / Transmogrifizierer, so nennt es das Spanische WoW),
-- desbloquear (freischalten), recopilada (gesammelt), pendiente (ausstehend),
-- descripcion (Tooltip), notificacion (Toast), coste (Kosten).
-- Anrede: tu (informell, Imperativ "elige", "equipa"); "Haz clic" fuer klicken.
-- Anfuehrungszeichen um Namen: gerade ("%s"), wie es die Tests verlangen.
-- Platzhalter (%s, %d) stehen in gleicher Anzahl und Reihenfolge wie in enUS.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("esES", {
   -- =========================================================================
   -- Core
   -- =========================================================================
   THOUSANDS_SEP = ".",

   LOADED = "%s %s cargado. Escribe /transmog para abrir la ventana.",
   MIGRATED_OUTFITS = "Conjuntos importados de la versión anterior de Transmog: %d",

   -- =========================================================================
   -- Boot
   -- =========================================================================
   -- Tastenbelegung
   BOOT_BINDING_HEADER = "Transfiguración",
   BOOT_BINDING_TOGGLE = "Abrir o cerrar la ventana de transfiguración",

   BOOT_INIT_FAILED = "No se pudo iniciar el módulo %s. Consulta el informe de errores para más detalles.",
   BOOT_UNAVAILABLE = "Esta parte del addon no está disponible.",

   BOOT_RESET_DONE = "Se han restablecido la posición y el tamaño de la ventana.",
   BOOT_LANG_SET = "Idioma cambiado a %s.",
   BOOT_LANG_CURRENT = "Idioma actual: %s. Usa auto o uno de estos: %s",
   BOOT_LANG_UNKNOWN = "Idioma desconocido \"%s\". Usa auto o uno de estos: %s",

   BOOT_DEBUG_ON = "Salida de depuración activada.",
   BOOT_DEBUG_OFF = "Salida de depuración desactivada.",
   BOOT_DEBUG_INFO = "Versión %s, idioma %s, estado del servidor %s, mensajes enviados %d, recibidos %d.",
   BOOT_DEBUG_STATE = "Junto a un transfigurador: %s, cambios pendientes: %d, listas preparadas: %s.",
   BOOT_DEBUG_ITEMS = "Consultas de objetos pendientes: %d, fallidas: %d, temporizadores: %d, textos que faltan: %d.",
   BOOT_YES = "sí",
   BOOT_NO = "no",

   BOOT_HELP_TITLE = "Comandos (/transmog o /xmog):",
   BOOT_HELP_TOGGLE = "/transmog - abrir o cerrar la ventana",
   BOOT_HELP_OPTIONS = "/transmog options - abrir las opciones",
   BOOT_HELP_RESET = "/transmog reset - restablecer la posición y el tamaño de la ventana",
   BOOT_HELP_TOAST = "/transmog toast - mover el ancla de las notificaciones",
   BOOT_HELP_LANG = "/transmog lang <código|auto> - establecer el idioma",
   BOOT_HELP_DEBUG = "/transmog debug - activar o desactivar la depuración",
   BOOT_HELP_HELP = "/transmog help - mostrar esta lista",

   -- =========================================================================
   -- State
   -- =========================================================================
   APPLY_REASON_NONE         = "Todavía no has cambiado nada.",
   APPLY_REASON_VENDOR       = "Visita a un transfigurador para aplicar los cambios.",
   APPLY_REASON_BUSY         = "Aplicando cambios...",
   APPLY_REASON_COST_PENDING = "Calculando el coste...",
   APPLY_REASON_MONEY        = "No tienes dinero suficiente.",
   APPLY_REASON_SERVER       = "El módulo de transfiguración del servidor no responde.",

   MSG_APPLY_OK           = "Apariencia aplicada.",
   MSG_APPLY_DONE         = "Aplicadas: %d, fallidas: %d.",
   MSG_APPLY_SLOT_FAILED  = "No se pudo aplicar: %s.",
   MSG_SERVER_ABSENT      = "El módulo de transfiguración del servidor no responde.",
   MSG_NO_VENDOR          = "Modo de vista previa: visita a un transfigurador para aplicar los cambios.",

   -- =========================================================================
   -- Filter / Outfits (Core)
   -- =========================================================================
   SORT_QUALITY = "Calidad",
   SORT_NAME = "Nombre",
   SORT_ILEVEL = "Nivel de objeto",

   OUTFIT_DEFAULT_NAME = "Conjunto %d",
   OUTFIT_ERR_EMPTY = "Introduce un nombre para el conjunto.",
   OUTFIT_ERR_EXISTS = "Ya existe un conjunto con ese nombre.",
   OUTFIT_ERR_LONG = "El nombre es demasiado largo (máximo 32 caracteres).",
   OUTFIT_ERR_FULL = "Has alcanzado el número máximo de conjuntos.",
   OUTFIT_ERR_NOITEMS = "Nada que guardar: no hay ninguna apariencia aplicada ni seleccionada.",
   OUTFIT_ERR_MISSING = "Este conjunto ya no existe.",

   OUTFIT_SKIP_EMPTY = "No hay nada equipado en esta ranura.",
   OUTFIT_SKIP_NEVER = "Esta ranura no se puede transfigurar.",
   OUTFIT_SKIP_LOADING = "La lista de apariencias de esta ranura aún se está cargando.",
   OUTFIT_SKIP_UNAVAILABLE = "Esta apariencia no está disponible para el objeto que llevas equipado.",
   OUTFIT_SKIP_HIDDEN = "Esta ranura no se puede ocultar.",

   -- =========================================================================
   -- Window
   -- =========================================================================
   WIN_TITLE = "Transfiguración",
   WIN_TAB_ITEMS = "Objetos",
   WIN_TAB_OUTFITS = "Conjuntos",
   WIN_OPTIONS = "Opciones",
   WIN_CLOSE = "Cerrar",
   WIN_RESIZE_TIP = "Arrastra para cambiar el tamaño de la ventana.",

   WIN_APPLY = "Aplicar",
   WIN_APPLY_RESET = "Aplicar original",
   WIN_APPLY_TIP = "Aplicar los cambios pendientes: %d",
   WIN_TIP_REMOVE = "Quitar apariencia",
   WIN_TIP_HIDDEN = "Oculto",

   WIN_DISCARD = "Descartar",
   WIN_DISCARD_TIP = "Descartar todos los cambios pendientes.",
   WIN_DISCARD_NONE = "No hay cambios pendientes.",
   WIN_REMOVE_ALL = "Quitar todo",
   WIN_REMOVE_ALL_TIP = "Quitar todas las apariencias aplicadas.",
   WIN_REMOVE_ALL_NONE = "No hay ninguna apariencia aplicada.",
   WIN_REMOVE_ALL_TITLE = "Quitar todas las apariencias",
   WIN_REMOVE_ALL_TEXT = "¿Quitar todas las apariencias aplicadas? Tu equipo volverá a mostrar su aspecto original.",
   WIN_REMOVED_ALL = "Se han quitado todas las apariencias.",
   WIN_CANCEL = "Cancelar",

   WIN_COST = "Coste:",
   WIN_COST_FREE = "Gratis",
   WIN_COST_PENDING = "...",
   WIN_COST_UNKNOWN = "?",

   WIN_STATUS_PENDING = "Cambios pendientes: %d",
   WIN_STATUS_APPLYING = "Aplicando cambios (%d)...",

   -- =========================================================================
   -- Preview
   -- =========================================================================
   PREVIEW_ROTATE_LEFT = "Girar a la izquierda",
   PREVIEW_ROTATE_RIGHT = "Girar a la derecha",
   PREVIEW_ROTATE_HOLD = "Mantén pulsado el botón del ratón para seguir girando.",

   PREVIEW_RESET = "Restablecer vista",
   PREVIEW_RESET_TIP = "Restablece la rotación, la posición y el zoom.",

   PREVIEW_HELP_ROTATE = "Arrastrar con el botón izquierdo: girar",
   PREVIEW_HELP_MOVE = "Arrastrar con el botón derecho: mover",
   PREVIEW_HELP_ZOOM = "Rueda del ratón: zoom",

   PREVIEW_OFFHAND_NOTE = "Esta vista previa no muestra las armas de una mano en la mano izquierda.",
   PREVIEW_OFFHAND_NOTE_MAINHAND = "Esta arma de una mano se muestra en la mano derecha (limitación del cliente).",

   -- =========================================================================
   -- SlotBar
   -- =========================================================================
   SLOTBAR_NOTHING_EQUIPPED = "Nada equipado",
   SLOTBAR_NEVER = "No se puede transfigurar",

   SLOTBAR_APPLIED = "Transfigurado en: %s",
   SLOTBAR_HIDDEN = "Oculto",
   SLOTBAR_PENDING = "Pendiente: %s",
   SLOTBAR_PENDING_RESET = "Pendiente: volver al original",
   SLOTBAR_INACTIVE = "Inactiva: %s (no encaja con el objeto equipado)",
   SLOTBAR_UNKNOWN_ITEM = "Objeto %d",

   SLOTBAR_AVAILABLE = "Apariencias disponibles: %d",
   SLOTBAR_LOADING = "Cargando apariencias: %d / %d",

   SLOTBAR_HINT_EDIT = "Clic izquierdo: editar",
   SLOTBAR_HINT_DISCARD = "Clic derecho: descartar el cambio pendiente",
   SLOTBAR_HINT_REMOVE = "Clic derecho: quitar la transfiguración",
   SLOTBAR_HINT_LINK = "Mayús + clic: enlazar en el chat",

   -- =========================================================================
   -- Grid
   -- =========================================================================
   GRID_NO_SLOT           = "Selecciona una ranura de equipo",
   GRID_NO_SLOT_HINT      = "Elige una ranura a la izquierda para explorar sus apariencias.",
   GRID_EMPTY_SLOT        = "No hay nada equipado en esta ranura",
   GRID_EMPTY_SLOT_HINT   = "Equipa un objeto para ver las apariencias compatibles.",
   GRID_NEVER             = "Este objeto no se puede transfigurar",
   GRID_NEVER_HINT        = "Los anillos, collares, abalorios y reliquias no pueden cambiar de aspecto.",
   GRID_ABSENT            = "El módulo de transfiguración del servidor no responde",
   GRID_ABSENT_HINT       = "Las apariencias se cargan desde el servidor. Comprueba que mod-transmog-plus esté instalado y activado.",
   GRID_NO_ITEMS          = "Aún no hay apariencias compatibles",
   GRID_NO_ITEMS_HINT     = "Se desbloquean al conseguir objetos que encajen en esta ranura.",
   GRID_FILTERED          = "Ninguna apariencia coincide con tus filtros",
   GRID_FILTERED_HINT     = "Cambia o restablece los filtros de arriba para ver más.",
   GRID_RESET_FILTERS     = "Restablecer filtros",

   GRID_LOADING           = "Cargando apariencias... %s / %s",
   GRID_LOADING_PLAIN     = "Cargando apariencias...",
   GRID_LOADING_HINT      = "Se están solicitando al servidor los datos de los objetos.",
   GRID_PLACEHOLDER       = "...",

   GRID_PAGE              = "Página %d / %d",
   GRID_PAGE_SHORT        = "%d / %d",
   GRID_COUNT             = "%s de %s apariencias",
   GRID_COUNT_FILTERED    = "%s de %s apariencias (filtradas)",
   GRID_COUNT_DUPES       = "%s de %s apariencias (%s duplicadas ocultas)",
   GRID_COUNT_SHORT       = "%s / %s",
   GRID_PAGE_FIRST        = "Primera página",
   GRID_PAGE_PREV         = "Página anterior",
   GRID_PAGE_NEXT         = "Página siguiente",
   GRID_PAGE_LAST         = "Última página",

   GRID_ORIGINAL          = "Original",
   GRID_ORIGINAL_TITLE    = "Apariencia original",
   GRID_ORIGINAL_TIP      = "Selecciónala para quitar la transfiguración y mostrar el aspecto original del objeto equipado.",
   GRID_HIDDEN            = "Oculto",
   GRID_HIDDEN_TIP        = "Selecciónalo para ocultar el equipo de esta ranura.",

   GRID_NEW               = "NUEVA",
   GRID_TIP_APPLIED       = "Aplicada actualmente",
   GRID_TIP_SELECTED      = "Seleccionada: aún sin aplicar",
   GRID_TIP_FAVORITE      = "Favorita",
   GRID_TIP_NEW           = "Recién desbloqueada",
   GRID_TIP_LEFT_SELECT   = "Clic izquierdo: seleccionar",
   GRID_TIP_LEFT_DISCARD  = "Clic izquierdo: descartar la selección",
   GRID_TIP_RIGHT_FAV     = "Clic derecho: marcar o desmarcar como favorita",
   GRID_TIP_SHIFT_LINK    = "Mayús + clic izquierdo: enlazar en el chat",

   -- =========================================================================
   -- FilterBar
   -- =========================================================================
   FILTER_SEARCH_PLACEHOLDER = "Nombre, tipo o #id",

   FILTER_SORT               = "Orden: %s",
   FILTER_SORT_TIP           = "Criterio de ordenación",
   FILTER_SORT_TIP_HINT      = "Haz clic para elegir cómo se ordenan las apariencias.",

   FILTER_BUTTON             = "Filtro",
   FILTER_BUTTON_TIP         = "Filtrar apariencias",
   FILTER_HIDE_DUPLICATES    = "Ocultar apariencias duplicadas",
   FILTER_HIDE_DUPLICATES_TIP = "Muestra una sola entrada para las apariencias con el mismo icono, tipo y ranura "
      .. "(es una aproximación: el cliente no puede leer el modelo real).",
   FILTER_FAVORITES_ONLY     = "Solo favoritas",
   FILTER_NEW_ONLY           = "Solo nuevas",
   FILTER_TYPE_TITLE         = "Tipo",
   FILTER_TYPE_ROW           = "%s (%d)",
   FILTER_TYPE_OWN           = "Es el tipo del objeto que llevas equipado y no se puede ocultar.",
   FILTER_RESET              = "Restablecer filtros",

   FILTER_RESET_TIP          = "Restablecer todos los filtros",
   FILTER_RESET_NONE         = "No hay filtros activos.",

   FILTER_QUALITY_COUNT      = "Apariencias: %d",
   FILTER_QUALITY_HIDE       = "Haz clic para ocultar esta calidad",
   FILTER_QUALITY_SHOW       = "Haz clic para mostrar esta calidad",

   FILTER_FAVORITES_CHIP     = "Favoritas",
   FILTER_FAVORITES_CHIP_TIP = "Mostrar solo las apariencias favoritas",
   FILTER_NEW                = "Nuevas",
   FILTER_NEW_TIP            = "Mostrar solo las apariencias recién desbloqueadas",
   FILTER_CHIP_ON            = "Activado: haz clic para desactivar",
   FILTER_CHIP_OFF           = "Haz clic para activar",

   -- =========================================================================
   -- Outfits
   -- =========================================================================
   OUTFITS_SAVE = "Guardar aspecto actual",
   OUTFITS_SAVE_TIP = "Guarda como un conjunto nuevo las apariencias que tienes aplicadas o seleccionadas ahora mismo.",
   OUTFITS_COUNT = "%d / %d",

   OUTFITS_SAVE_TITLE = "Guardar conjunto",
   OUTFITS_SAVE_TEXT = "Introduce un nombre para este conjunto:",
   OUTFITS_SAVED = "Conjunto \"%s\" guardado.",

   OUTFITS_PIECES = "Piezas: %d",
   OUTFITS_PIECES_PARTIAL = "Disponibles: %d / %d",
   OUTFITS_HIDDEN = "Oculto",
   OUTFITS_LOADING = "Cargando...",
   OUTFITS_ITEM_UNKNOWN = "Objeto %d",
   OUTFITS_TIP_CURRENT = "Coincide con tu aspecto actual.",

   OUTFITS_LOAD = "Cargar",
   OUTFITS_LOAD_TIP = "Selecciona las piezas de este conjunto en la ventana de transfiguración. "
      .. "No se aplica nada hasta que hagas clic en Aplicar.",
   OUTFITS_LOADED = "Piezas cargadas: %d",
   OUTFITS_LOADED_PARTIAL = "Piezas cargadas: %d, no disponibles: %d",
   OUTFITS_LOADED_NONE = "Ninguna pieza cargada (no disponibles: %d)",
   OUTFITS_LOADED_PENDING = "Piezas cargadas: %d, aún cargando: %d",
   OUTFITS_LOADED_WAIT = "Cargando apariencias. Inténtalo de nuevo.",
   OUTFITS_LOADED_EMPTY = "Este conjunto no contiene ninguna pieza.",

   OUTFITS_OVERWRITE = "Sobrescribir",
   OUTFITS_OVERWRITE_TIP = "Sustituye las piezas de este conjunto por tu aspecto actual.",
   OUTFITS_OVERWRITE_TITLE = "Sobrescribir conjunto",
   OUTFITS_OVERWRITE_TEXT = "¿Sustituir las piezas del conjunto \"%s\" por tu aspecto actual?",
   OUTFITS_OVERWRITTEN = "Conjunto \"%s\" actualizado.",

   OUTFITS_RENAME = "Renombrar",
   OUTFITS_RENAME_TIP = "Cambia el nombre de este conjunto.",
   OUTFITS_RENAME_TITLE = "Renombrar conjunto",
   OUTFITS_RENAME_TEXT = "Introduce un nombre nuevo para el conjunto \"%s\":",
   OUTFITS_RENAMED = "Conjunto renombrado como \"%s\".",

   OUTFITS_DELETE = "Eliminar",
   OUTFITS_DELETE_TIP = "Elimina este conjunto de forma permanente.",
   OUTFITS_DELETE_TITLE = "Eliminar conjunto",
   OUTFITS_DELETE_TEXT = "¿Eliminar el conjunto \"%s\"? Esta acción no se puede deshacer.",
   OUTFITS_DELETED = "Conjunto \"%s\" eliminado.",

   OUTFITS_EMPTY_TITLE = "Aún no hay conjuntos",
   OUTFITS_EMPTY_TEXT = "Los conjuntos guardan las piezas que tienes seleccionadas o aplicadas ahora mismo, para que "
      .. "puedas recuperar un aspecto completo con un solo clic. Elige apariencias en la pestaña Objetos, "
      .. "haz clic en \"Guardar aspecto actual\" y ponle un nombre al conjunto.",

   OUTFITS_PAGE = "Página %d / %d",
   OUTFITS_PAGE_PREV = "Página anterior",
   OUTFITS_PAGE_NEXT = "Página siguiente",

   -- =========================================================================
   -- Options
   -- =========================================================================
   OPT_TITLE = "Opciones de transfiguración",

   OPT_SECTION_LANGUAGE = "Idioma",
   OPT_LANG_AUTO = "Auto (idioma del cliente: %s)",
   OPT_LANG_TIP = "Idioma de todos los textos de este addon.",
   OPT_LANG_NOTE = "Si eliges un idioma distinto del de tu cliente de juego, puede que la fuente no tenga "
      .. "algunos caracteres.",

   OPT_SECTION_WINDOW = "Ventana",
   OPT_SCALE = "Escala de la ventana",
   OPT_SCALE_AUTO = "Auto",
   OPT_SCALE_TIP = "Con Auto, la ventana se ajusta a tu pantalla. Mueve el control deslizante para fijar una escala.",
   OPT_PREVIEW_SIZE = "Tamaño de la vista previa",
   OPT_PREVIEW_TIP = "Tamaño de las vistas previas de las apariencias en la cuadrícula de objetos.",
   OPT_PREVIEW_SMALL = "Pequeño",
   OPT_PREVIEW_MEDIUM = "Mediano",
   OPT_PREVIEW_LARGE = "Grande",
   OPT_PREVIEW_XLARGE = "Muy grande",
   OPT_RESET_WINDOW = "Restablecer posición y tamaño de la ventana",
   OPT_RESET_WINDOW_TIP = "Devuelve la ventana de transfiguración a su posición y tamaño predeterminados.",
   OPT_RESET_DONE = "Se han restablecido la posición y el tamaño de la ventana.",

   OPT_SECTION_GENERAL = "General",
   OPT_SOUND = "Sonido al aplicar",
   OPT_SOUND_TIP = "Reproduce un sonido cuando los cambios se aplican correctamente.",
   OPT_TOASTS = "Notificaciones de apariencias nuevas",
   OPT_TOASTS_TIP = "Muestra una pequeña notificación cuando desbloqueas una apariencia nueva.",
   OPT_TOOLTIP_COLLECTED = "Descripción: mostrar \"apariencia no recopilada\"",
   OPT_TOOLTIP_COLLECTED_TIP = "Añade una línea a las descripciones de los objetos cuando aún no has recopilado su apariencia.",
   OPT_TOOLTIP_APPLIED = "Descripción: mostrar \"transfigurado en\"",
   OPT_TOOLTIP_APPLIED_TIP = "Añade a la descripción de tus objetos equipados una línea con la apariencia que tienen aplicada.",
   OPT_ALLOW_ANYWHERE = "Permitir aplicar sin transfigurador",
   OPT_ALLOW_ANYWHERE_TIP = "El servidor no comprueba tu distancia a un transfigurador. "
      .. "Si esta opción está activada (por defecto), los cambios se pueden aplicar desde cualquier lugar. "
      .. "Si está desactivada, /transmog solo abre el modo de vista previa y el addon solo aplica los cambios "
      .. "mientras hablas con un transfigurador.",

   OPT_MOVE_TOASTS = "Mover notificaciones",
   OPT_MOVE_TOASTS_TIP = "Muestra el ancla de las notificaciones para que puedas arrastrarla a otra posición.",
   OPT_TEST_TOAST = "Notificación de prueba",
   OPT_TEST_TOAST_TIP = "Muestra una notificación de ejemplo.",

   -- =========================================================================
   -- Features (Tooltips, Toasts)
   -- =========================================================================
   TIP_NOT_COLLECTED = "Apariencia no recopilada",

   TIP_APPLIED = "Transfigurado en: %s",
   TIP_APPLIED_HIDDEN = "Transfigurado en: Oculto",
   TIP_INACTIVE = "Transfiguración inactiva: %s",
   TIP_ITEM_UNKNOWN = "Objeto %d",

   TOAST_TITLE = "Nueva apariencia desbloqueada",
   TOAST_ITEM_UNKNOWN = "Objeto %d",

   TOAST_BURST_TITLE = "Apariencias desbloqueadas",
   TOAST_BURST_COUNT = "Apariencias: %d",

   TOAST_ANCHOR_LABEL = "Muéveme",
   TOAST_ANCHOR_TIP_TITLE = "Posición de las notificaciones",
   TOAST_ANCHOR_TIP_DRAG = "Arrastra para mover las notificaciones.",
   TOAST_ANCHOR_TIP_RESET = "Clic derecho: restablecer la posición.",

   -- Hinweis fuer die Nebenhand-Vorschau (Client-Grenze)
   GRID_TIP_OFFHAND_PREVIEW = "La vista previa muestra las armas de una mano en la mano derecha (limitación del cliente).",
})
