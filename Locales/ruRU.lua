-- Locales\ruRU.lua
-- ---------------------------------------------------------------------------
-- Russische Texte fuer alle Module. Quelle: Locales\enUS_*.lua.
--
-- Begriffe (einheitlich, ein Wort je Begriff):
--   внешний вид (Aussehen/Appearance; Zaehlform als Beschriftung "Внешних видов: %d"),
--   комплект (Outfit), ячейка (Ausruestungsplatz), предмет (Gegenstand),
--   избранное (Favorit), применить (Anwenden), отменить (Verwerfen einer
--   Auswahl/ausstehender Aenderungen), сбросить (Zuruecksetzen von Filtern/Kamera/
--   Fenster), скрыто (Verborgen), исходный (Original), качество (Qualitaet),
--   трансмогрификация / трансмогрификатор (Transmogrifikation / Transmogrifizierer),
--   открыт (freigeschaltet), собран (gesammelt), изменения к применению (ausstehende
--   Aenderungen), предпросмотр (Vorschau).
-- Anrede: Sie-Form (Plural-Imperativ "выберите"). Zaehlformen stehen nur als
-- Beschriftung vor dem Doppelpunkt ("Предметов: %d"), damit keine Pluralregeln
-- noetig sind; Platzhalter stehen nie in einem Satzgefuege, das sie beugt.
-- Namen in Anfuehrungszeichen: gerade "..." (verlangt tests/test_locales.lua).
-- Gedankenstrich: ASCII " - " wie in allen Sprachdateien (kein Geviertstrich: keine
-- Abhaengigkeit von einer Glyphe der Client-Schrift). Platzhalter (%s, %d) stehen in
-- gleicher Anzahl und Reihenfolge wie in enUS.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("ruRU", {
   -- =========================================================================
   -- Core
   -- =========================================================================
   THOUSANDS_SEP = " ",

   LOADED = "%s %s загружен. Откройте окно командой /transmog.",
   MIGRATED_OUTFITS = "Импортировано комплектов из предыдущей версии Transmog: %d",

   -- =========================================================================
   -- Boot
   -- =========================================================================
   -- Tastenbelegung
   BOOT_BINDING_HEADER = "Трансмогрификация",
   BOOT_BINDING_TOGGLE = "Открыть или закрыть окно трансмогрификации",

   BOOT_INIT_FAILED = "Не удалось запустить модуль %s. Подробности см. в отчёте об ошибке.",
   BOOT_UNAVAILABLE = "Эта часть аддона недоступна.",

   BOOT_RESET_DONE = "Положение и размер окна сброшены.",
   BOOT_LANG_SET = "Выбран язык: %s.",
   BOOT_LANG_CURRENT = "Текущий язык: %s. Укажите auto или один из: %s",
   BOOT_LANG_UNKNOWN = "Неизвестный язык \"%s\". Укажите auto или один из: %s",

   BOOT_DEBUG_ON = "Отладочный вывод включён.",
   BOOT_DEBUG_OFF = "Отладочный вывод выключен.",
   BOOT_DEBUG_INFO = "Версия %s, язык %s, состояние сервера %s, отправлено сообщений: %d, получено: %d.",
   BOOT_DEBUG_STATE = "У трансмогрификатора: %s, изменений к применению: %d, списки готовы: %s.",
   BOOT_DEBUG_ITEMS = "Запросов предметов в очереди: %d, неудачных: %d, таймеров: %d, отсутствующих текстов: %d.",
   BOOT_YES = "да",
   BOOT_NO = "нет",

   BOOT_HELP_TITLE = "Команды (/transmog или /xmog):",
   BOOT_HELP_TOGGLE = "/transmog - открыть или закрыть окно",
   BOOT_HELP_OPTIONS = "/transmog options - открыть настройки",
   BOOT_HELP_RESET = "/transmog reset - сбросить положение и размер окна",
   BOOT_HELP_TOAST = "/transmog toast - переместить рамку уведомлений",
   BOOT_HELP_LANG = "/transmog lang <код|auto> - выбрать язык",
   BOOT_HELP_DEBUG = "/transmog debug - включить или выключить отладочный вывод",
   BOOT_HELP_HELP = "/transmog help - показать этот список",

   -- =========================================================================
   -- State
   -- =========================================================================
   APPLY_REASON_NONE         = "Пока ничего не изменено.",
   APPLY_REASON_VENDOR       = "Чтобы применить изменения, подойдите к трансмогрификатору.",
   APPLY_REASON_BUSY         = "Применение изменений...",
   APPLY_REASON_COST_PENDING = "Расчёт стоимости...",
   APPLY_REASON_MONEY        = "У вас недостаточно денег.",
   APPLY_REASON_SERVER       = "Серверный модуль трансмогрификации не отвечает.",

   MSG_APPLY_OK           = "Внешний вид применён.",
   MSG_APPLY_DONE         = "Изменено: %d, не удалось: %d.",
   MSG_APPLY_SLOT_FAILED  = "%s: не удалось применить.",
   MSG_SERVER_ABSENT      = "Серверный модуль трансмогрификации не отвечает.",
   MSG_NO_VENDOR          = "Режим предпросмотра - чтобы применить изменения, подойдите к трансмогрификатору.",

   -- =========================================================================
   -- Filter / Outfits (Core)
   -- =========================================================================
   SORT_QUALITY = "Качество",
   SORT_NAME = "Название",
   SORT_ILEVEL = "Ур. предмета",

   OUTFIT_DEFAULT_NAME = "Комплект %d",
   OUTFIT_ERR_EMPTY = "Введите название комплекта.",
   OUTFIT_ERR_EXISTS = "Комплект с таким названием уже существует.",
   OUTFIT_ERR_LONG = "Название слишком длинное (до 32 символов).",
   OUTFIT_ERR_FULL = "Достигнуто максимальное число комплектов.",
   OUTFIT_ERR_NOITEMS = "Нечего сохранять: ничего не выбрано.",
   OUTFIT_ERR_MISSING = "Этого комплекта больше не существует.",

   OUTFIT_SKIP_EMPTY = "В этой ячейке ничего не надето.",
   OUTFIT_SKIP_NEVER = "Эту ячейку нельзя трансмогрифицировать.",
   OUTFIT_SKIP_LOADING = "Список внешних видов для этой ячейки ещё загружается.",
   OUTFIT_SKIP_UNAVAILABLE = "Этот внешний вид недоступен для надетого предмета.",
   OUTFIT_SKIP_HIDDEN = "Эту ячейку нельзя скрыть.",

   -- =========================================================================
   -- Window
   -- =========================================================================
   WIN_TITLE = "Трансмогрификация",
   WIN_TAB_ITEMS = "Предметы",
   WIN_TAB_OUTFITS = "Комплекты",
   WIN_OPTIONS = "Настройки",
   WIN_CLOSE = "Закрыть",
   WIN_RESIZE_TIP = "Перетащите, чтобы изменить размер окна.",

   WIN_APPLY = "Применить",
   WIN_APPLY_RESET = "Применить сброс",
   WIN_APPLY_TIP = "Применить изменения: %d",
   WIN_TIP_REMOVE = "Исходный вид",
   WIN_TIP_HIDDEN = "Скрыто",

   WIN_DISCARD = "Отменить",
   WIN_DISCARD_TIP = "Отменить все неприменённые изменения.",
   WIN_DISCARD_NONE = "Нет неприменённых изменений.",
   WIN_REMOVE_ALL = "Убрать всё",
   WIN_REMOVE_ALL_TIP = "Убрать трансмогрификацию со всей экипировки.",
   WIN_REMOVE_ALL_NONE = "Трансмогрификация не применена.",
   WIN_REMOVE_ALL_TITLE = "Убрать всю трансмогрификацию",
   WIN_REMOVE_ALL_TEXT = "Убрать всю трансмогрификацию? Экипировка снова примет исходный вид.",
   WIN_REMOVED_ALL = "Вся трансмогрификация убрана.",
   WIN_CANCEL = "Отмена",

   WIN_COST = "Стоимость:",
   WIN_COST_FREE = "Бесплатно",
   WIN_COST_PENDING = "...",
   WIN_COST_UNKNOWN = "?",

   WIN_STATUS_PENDING = "Изменений к применению: %d",
   WIN_STATUS_APPLYING = "Применение изменений (%d)...",

   -- =========================================================================
   -- Preview
   -- =========================================================================
   PREVIEW_ROTATE_LEFT = "Повернуть влево",
   PREVIEW_ROTATE_RIGHT = "Повернуть вправо",
   PREVIEW_ROTATE_HOLD = "Удерживайте кнопку мыши, чтобы продолжать вращение.",

   PREVIEW_RESET = "Сбросить камеру",
   PREVIEW_RESET_TIP = "Сбрасывает поворот, положение и масштаб.",

   PREVIEW_HELP_ROTATE = "Перетаскивание левой кнопкой мыши: поворот",
   PREVIEW_HELP_MOVE = "Перетаскивание правой кнопкой мыши: перемещение",
   PREVIEW_HELP_ZOOM = "Колесо мыши: масштаб",

   PREVIEW_OFFHAND_NOTE = "Одноручное оружие в левой руке не отображается в предпросмотре.",
   PREVIEW_OFFHAND_NOTE_MAINHAND = "Это одноручное оружие показано в правой руке (ограничение клиента).",

   -- =========================================================================
   -- SlotBar
   -- =========================================================================
   SLOTBAR_NOTHING_EQUIPPED = "Ничего не надето",
   SLOTBAR_NEVER = "Нельзя трансмогрифицировать",

   SLOTBAR_APPLIED = "Трансмогрификация: %s",
   SLOTBAR_HIDDEN = "Скрыто",
   SLOTBAR_PENDING = "Будет применено: %s",
   SLOTBAR_PENDING_RESET = "Будет применено: исходный вид",
   SLOTBAR_INACTIVE = "Неактивно: %s (не подходит для надетого предмета)",
   SLOTBAR_UNKNOWN_ITEM = "Предмет %d",

   SLOTBAR_AVAILABLE = "Доступно внешних видов: %d",
   SLOTBAR_LOADING = "Загрузка внешних видов: %d / %d",

   SLOTBAR_HINT_EDIT = "Левый клик: изменить",
   SLOTBAR_HINT_DISCARD = "Правый клик: отменить изменение",
   SLOTBAR_HINT_REMOVE = "Правый клик: убрать трансмогрификацию",
   SLOTBAR_HINT_LINK = "Shift + клик: ссылка в чат",

   -- =========================================================================
   -- Grid
   -- =========================================================================
   GRID_NO_SLOT           = "Выберите ячейку экипировки",
   GRID_NO_SLOT_HINT      = "Выберите ячейку слева, чтобы просмотреть её внешние виды.",
   GRID_EMPTY_SLOT        = "В этой ячейке ничего не надето",
   GRID_EMPTY_SLOT_HINT   = "Наденьте предмет, чтобы увидеть подходящие внешние виды.",
   GRID_NEVER             = "Этот предмет нельзя трансмогрифицировать",
   GRID_NEVER_HINT        = "Кольца, ожерелья, аксессуары и реликвии не могут менять внешний вид.",
   GRID_ABSENT            = "Серверный модуль трансмогрификации не отвечает",
   GRID_ABSENT_HINT       = "Внешние виды загружаются с сервера. Убедитесь, что mod-transmog-plus установлен и включён.",
   GRID_NO_ITEMS          = "Подходящих внешних видов пока нет",
   GRID_NO_ITEMS_HINT     = "Внешние виды открываются, когда вы получаете предметы, подходящие для этой ячейки.",
   GRID_FILTERED          = "Нет внешних видов, соответствующих фильтрам",
   GRID_FILTERED_HINT     = "Измените или сбросьте фильтры выше, чтобы увидеть больше.",
   GRID_RESET_FILTERS     = "Сбросить фильтры",

   GRID_LOADING           = "Загрузка внешних видов... %s / %s",
   GRID_LOADING_PLAIN     = "Загрузка внешних видов...",
   GRID_LOADING_HINT      = "Данные о предметах запрашиваются у сервера.",
   GRID_PLACEHOLDER       = "...",

   GRID_PAGE              = "Страница %d / %d",
   GRID_PAGE_SHORT        = "%d / %d",
   GRID_COUNT             = "Внешних видов: %s из %s",
   GRID_COUNT_FILTERED    = "Внешних видов: %s из %s (с фильтром)",
   GRID_COUNT_DUPES       = "Внешних видов: %s из %s (скрыто дубликатов: %s)",
   GRID_COUNT_SHORT       = "%s / %s",
   GRID_PAGE_FIRST        = "Первая страница",
   GRID_PAGE_PREV         = "Предыдущая страница",
   GRID_PAGE_NEXT         = "Следующая страница",
   GRID_PAGE_LAST         = "Последняя страница",

   GRID_ORIGINAL          = "Исходный",
   GRID_ORIGINAL_TITLE    = "Исходный внешний вид",
   GRID_ORIGINAL_TIP      = "Выберите, чтобы убрать трансмогрификацию и вернуть надетому предмету исходный вид.",
   GRID_HIDDEN            = "Скрыто",
   GRID_HIDDEN_TIP        = "Выберите, чтобы скрыть экипировку в этой ячейке.",

   GRID_NEW               = "НОВОЕ",
   GRID_TIP_APPLIED       = "Применено сейчас",
   GRID_TIP_SELECTED      = "Выбрано, ещё не применено",
   GRID_TIP_FAVORITE      = "Избранное",
   GRID_TIP_NEW           = "Недавно открыто",
   GRID_TIP_LEFT_SELECT   = "Левый клик: выбрать",
   GRID_TIP_LEFT_DISCARD  = "Левый клик: отменить выбор",
   GRID_TIP_RIGHT_FAV     = "Правый клик: в избранное / из избранного",
   GRID_TIP_SHIFT_LINK    = "Shift + левый клик: ссылка в чат",

   -- =========================================================================
   -- FilterBar
   -- =========================================================================
   FILTER_SEARCH_PLACEHOLDER = "Название, тип, #id",

   FILTER_SORT               = "Порядок: %s",
   FILTER_SORT_TIP           = "Порядок сортировки",
   FILTER_SORT_TIP_HINT      = "Нажмите, чтобы выбрать порядок сортировки внешних видов.",

   FILTER_BUTTON             = "Фильтр",
   FILTER_BUTTON_TIP         = "Фильтр внешних видов",
   FILTER_HIDE_DUPLICATES    = "Скрыть дубликаты",
   FILTER_HIDE_DUPLICATES_TIP = "Показывает одну запись для внешних видов с одинаковым значком, типом и ячейкой "
      .. "(приблизительно: клиент не может прочитать настоящую модель).",
   FILTER_FAVORITES_ONLY     = "Только избранное",
   FILTER_NEW_ONLY           = "Только новые",
   FILTER_TYPE_TITLE         = "Тип",
   FILTER_TYPE_ROW           = "%s (%d)",
   FILTER_TYPE_OWN           = "Это тип вашего надетого предмета, его нельзя скрыть.",
   FILTER_RESET              = "Сбросить фильтры",

   FILTER_RESET_TIP          = "Сбросить все фильтры",
   FILTER_RESET_NONE         = "Нет активных фильтров.",

   FILTER_QUALITY_COUNT      = "Внешних видов: %d",
   FILTER_QUALITY_HIDE       = "Нажмите, чтобы скрыть это качество",
   FILTER_QUALITY_SHOW       = "Нажмите, чтобы показать это качество",

   FILTER_FAVORITES_CHIP     = "Избранное",
   FILTER_FAVORITES_CHIP_TIP = "Показывать только избранные внешние виды",
   FILTER_NEW                = "Новые",
   FILTER_NEW_TIP            = "Показывать только недавно открытые внешние виды",
   FILTER_CHIP_ON            = "Включено - нажмите, чтобы выключить",
   FILTER_CHIP_OFF           = "Нажмите, чтобы включить",

   -- =========================================================================
   -- Outfits
   -- =========================================================================
   OUTFITS_SAVE = "Сохранить текущий внешний вид",
   OUTFITS_SAVE_TIP = "Сохраняет применённые или выбранные сейчас внешние виды как новый комплект.",
   OUTFITS_COUNT = "%d / %d",

   OUTFITS_SAVE_TITLE = "Сохранить комплект",
   OUTFITS_SAVE_TEXT = "Введите название комплекта:",
   OUTFITS_SAVED = "Комплект \"%s\" сохранён.",

   OUTFITS_PIECES = "Предметов: %d",
   OUTFITS_PIECES_PARTIAL = "Доступно: %d из %d",
   OUTFITS_HIDDEN = "Скрыто",
   OUTFITS_LOADING = "Загрузка...",
   OUTFITS_ITEM_UNKNOWN = "Предмет %d",
   OUTFITS_TIP_CURRENT = "Совпадает с вашим текущим внешним видом.",

   OUTFITS_LOAD = "Загрузить",
   OUTFITS_LOAD_TIP = "Выбирает предметы этого комплекта в гардеробе. Ничего не применяется, пока вы не нажмёте "
      .. "\"Применить\".",
   OUTFITS_LOADED = "Загружено: %d",
   OUTFITS_LOADED_PARTIAL = "Загружено: %d, недоступно: %d",
   OUTFITS_LOADED_NONE = "Ничего не загружено (недоступно: %d)",
   OUTFITS_LOADED_PENDING = "Загружено: %d, ещё загружается: %d",
   OUTFITS_LOADED_WAIT = "Идёт загрузка, повторите позже.",
   OUTFITS_LOADED_EMPTY = "В этом комплекте нет предметов.",

   OUTFITS_OVERWRITE = "Перезаписать",
   OUTFITS_OVERWRITE_TIP = "Заменяет содержимое этого комплекта вашим текущим внешним видом.",
   OUTFITS_OVERWRITE_TITLE = "Перезаписать комплект",
   OUTFITS_OVERWRITE_TEXT = "Заменить содержимое комплекта \"%s\" вашим текущим внешним видом?",
   OUTFITS_OVERWRITTEN = "Комплект \"%s\" обновлён.",

   OUTFITS_RENAME = "Переименовать",
   OUTFITS_RENAME_TIP = "Изменяет название этого комплекта.",
   OUTFITS_RENAME_TITLE = "Переименовать комплект",
   OUTFITS_RENAME_TEXT = "Введите новое название для комплекта \"%s\":",
   OUTFITS_RENAMED = "Комплект переименован в \"%s\".",

   OUTFITS_DELETE = "Удалить",
   OUTFITS_DELETE_TIP = "Безвозвратно удаляет этот комплект.",
   OUTFITS_DELETE_TITLE = "Удалить комплект",
   OUTFITS_DELETE_TEXT = "Удалить комплект \"%s\"? Это действие нельзя отменить.",
   OUTFITS_DELETED = "Комплект \"%s\" удалён.",

   OUTFITS_EMPTY_TITLE = "Комплектов пока нет",
   OUTFITS_EMPTY_TEXT = "Комплекты сохраняют выбранные или применённые сейчас внешние виды, чтобы одним щелчком "
      .. "вернуть сразу весь внешний вид. Выберите внешние виды на вкладке \"Предметы\", нажмите "
      .. "\"Сохранить текущий внешний вид\" и задайте комплекту название.",

   OUTFITS_PAGE = "Страница %d / %d",
   OUTFITS_PAGE_PREV = "Предыдущая страница",
   OUTFITS_PAGE_NEXT = "Следующая страница",

   -- =========================================================================
   -- Options
   -- =========================================================================
   OPT_TITLE = "Настройки трансмогрификации",

   OPT_SECTION_LANGUAGE = "Язык",
   OPT_LANG_AUTO = "Авто (язык клиента: %s)",
   OPT_LANG_TIP = "Язык всех текстов этого аддона.",
   OPT_LANG_NOTE = "Если язык отличается от языка игрового клиента, в шрифте могут отсутствовать некоторые символы.",

   OPT_SECTION_WINDOW = "Окно",
   OPT_SCALE = "Масштаб окна",
   OPT_SCALE_AUTO = "Авто",
   OPT_SCALE_TIP = "В режиме \"Авто\" размер окна подбирается под ваш экран. Передвиньте ползунок, чтобы задать "
      .. "фиксированный масштаб.",
   OPT_PREVIEW_SIZE = "Размер предпросмотра",
   OPT_PREVIEW_TIP = "Размер предпросмотра внешних видов в сетке предметов.",
   OPT_PREVIEW_SMALL = "Малый",
   OPT_PREVIEW_MEDIUM = "Средний",
   OPT_PREVIEW_LARGE = "Большой",
   OPT_PREVIEW_XLARGE = "Огромный",
   OPT_RESET_WINDOW = "Сбросить положение и размер окна",
   OPT_RESET_WINDOW_TIP = "Возвращает окно гардероба в положение и размер по умолчанию.",
   OPT_RESET_DONE = "Положение и размер окна сброшены.",

   OPT_SECTION_GENERAL = "Общие",
   OPT_SOUND = "Звук при применении",
   OPT_SOUND_TIP = "Воспроизводит звук, когда изменения успешно применены.",
   OPT_TOASTS = "Уведомления о новых внешних видах",
   OPT_TOASTS_TIP = "Показывает небольшое уведомление, когда вы открываете новый внешний вид.",
   OPT_TOOLTIP_COLLECTED = "Подсказка: \"внешний вид не собран\"",
   OPT_TOOLTIP_COLLECTED_TIP = "Добавляет строку в подсказки предметов, если вы ещё не собрали их внешний вид.",
   OPT_TOOLTIP_APPLIED = "Подсказка: \"трансмогрификация\"",
   OPT_TOOLTIP_APPLIED_TIP = "Добавляет в подсказку надетых предметов строку с применённым к ним внешним видом.",
   OPT_ALLOW_ANYWHERE = "Разрешить применение без трансмогрификатора",
   OPT_ALLOW_ANYWHERE_TIP = "Сервер не проверяет ваше расстояние до трансмогрификатора. "
      .. "Если эта настройка включена (по умолчанию), изменения можно применять где угодно. Если она выключена, "
      .. "/transmog открывает только режим предпросмотра, а аддон применяет изменения только во время "
      .. "разговора с трансмогрификатором.",

   OPT_MOVE_TOASTS = "Переместить уведомления",
   OPT_MOVE_TOASTS_TIP = "Показывает рамку, которую можно перетащить, чтобы изменить положение уведомлений.",
   OPT_TEST_TOAST = "Тестовое уведомление",
   OPT_TEST_TOAST_TIP = "Показывает пример уведомления.",

   -- =========================================================================
   -- Features (Tooltips, Toasts)
   -- =========================================================================
   TIP_NOT_COLLECTED = "Внешний вид не собран",

   TIP_APPLIED = "Трансмогрификация: %s",
   TIP_APPLIED_HIDDEN = "Трансмогрификация: скрыто",
   TIP_INACTIVE = "Трансмогрификация неактивна: %s",
   TIP_ITEM_UNKNOWN = "Предмет %d",

   TOAST_TITLE = "Открыт новый внешний вид",
   TOAST_ITEM_UNKNOWN = "Предмет %d",

   TOAST_BURST_TITLE = "Открыты новые внешние виды",
   TOAST_BURST_COUNT = "Внешних видов: %d",

   TOAST_ANCHOR_LABEL = "Сдвиньте меня",
   TOAST_ANCHOR_TIP_TITLE = "Положение уведомлений",
   TOAST_ANCHOR_TIP_DRAG = "Перетащите, чтобы переместить уведомления.",
   TOAST_ANCHOR_TIP_RESET = "Правый клик: сбросить положение.",

   -- Hinweis fuer die Nebenhand-Vorschau (Client-Grenze)
   GRID_TIP_OFFHAND_PREVIEW = "В предпросмотре одноручное оружие показывается в правой руке (ограничение клиента).",
})
