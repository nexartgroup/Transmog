-- Locales\zhCN.lua
-- ---------------------------------------------------------------------------
-- Vereinfachtes Chinesisch (Festland). Alle Schluessel aus Locales\enUS_*.lua.
--
-- Begriffe (einheitlich, ein Wort je Konzept):
--   外观 = Aussehen (appearance, auch "look"), 套装 = Outfit, 部位 = Slot
--   (Ausruestungsplatz), 部件 = Teil eines Outfits, 收藏 = Favorit,
--   筛选 = Filter, 应用 = Anwenden, 放弃 = Verwerfen, 取消 = Abbrechen,
--   移除 = entfernen, 重置 = zuruecksetzen (Fenster, Filter, Kamera),
--   还原 = auf das Originalaussehen zurueck, 原始 = Original,
--   隐藏 = Verborgen, 品质 = Qualitaet, 物品 = Gegenstand,
--   幻化 = Transmogrifikation, 幻化师 = Transmogrifizierer (NPC),
--   解锁 = freischalten, 已收集 = gesammelt, 待应用 = ausstehend,
--   加载 = laden (auch Outfit laden), 鼠标提示 = Tooltip,
--   通知 = Toast/Benachrichtigung, 锚点 = Anker, 插件 = Addon.
--
-- Typografie: chinesische Voll-Breite-Zeichen (：，。？（）“”) in Saetzen,
-- Auslassung "……" (zwei U+2026) in Fliesstext, "..." nur als reines
-- Platzhalterzeichen (WIN_COST_PENDING, GRID_PLACEHOLDER). Kein Leerzeichen
-- zwischen CJK und Platzhaltern; Ausnahmen nur fuer woertliche lateinische
-- Zeichenfolgen (/transmog, auto, Transmog), fuer lateinisch gefuellte
-- Platzhalter in den /transmog-Ausgaben (BOOT_*) und fuer "Bezeichnung + Nummer"
-- ("物品 %d", "套装 %d"). Platzhalter (%s, %d) stehen in gleicher Anzahl und
-- Reihenfolge wie in enUS.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("zhCN", {
   -- =========================================================================
   -- Core
   -- =========================================================================
   THOUSANDS_SEP = ",",

   LOADED = "%s %s 已加载，输入 /transmog 打开窗口。",
   MIGRATED_OUTFITS = "已从旧版 Transmog 导入%d个套装。",

   -- =========================================================================
   -- Boot
   -- =========================================================================
   -- Tastenbelegung
   BOOT_BINDING_HEADER = "幻化",
   BOOT_BINDING_TOGGLE = "打开或关闭幻化窗口",

   BOOT_INIT_FAILED = "无法启动“%s”模块。请查看错误报告了解详细信息。",
   BOOT_UNAVAILABLE = "插件的这部分功能不可用。",

   BOOT_RESET_DONE = "窗口位置和大小已重置。",
   BOOT_LANG_SET = "语言已设置为 %s。",
   BOOT_LANG_CURRENT = "当前语言：%s。请使用 auto 或以下之一：%s",
   BOOT_LANG_UNKNOWN = "未知语言“%s”。请使用 auto 或以下之一：%s",

   BOOT_DEBUG_ON = "调试输出已开启。",
   BOOT_DEBUG_OFF = "调试输出已关闭。",
   BOOT_DEBUG_INFO = "版本 %s，语言 %s，服务器状态 %s，已发送 %d 条消息，已接收 %d 条。",
   BOOT_DEBUG_STATE = "在幻化师处：%s，待应用的更改：%d，列表已就绪：%s。",
   BOOT_DEBUG_ITEMS = "未完成的物品查询：%d，失败：%d，计时器：%d，缺失文本：%d。",
   BOOT_YES = "是",
   BOOT_NO = "否",

   BOOT_HELP_TITLE = "命令（/transmog 或 /xmog）：",
   BOOT_HELP_TOGGLE = "/transmog - 打开或关闭窗口",
   BOOT_HELP_OPTIONS = "/transmog options - 打开选项窗口",
   BOOT_HELP_RESET = "/transmog reset - 重置窗口位置和大小",
   BOOT_HELP_TOAST = "/transmog toast - 移动通知锚点",
   BOOT_HELP_LANG = "/transmog lang <code|auto> - 设置语言",
   BOOT_HELP_DEBUG = "/transmog debug - 开启或关闭调试输出",
   BOOT_HELP_HELP = "/transmog help - 显示此命令列表",

   -- =========================================================================
   -- State
   -- =========================================================================
   APPLY_REASON_NONE         = "尚未做出任何更改。",
   APPLY_REASON_VENDOR       = "请前往幻化师处应用更改。",
   APPLY_REASON_BUSY         = "正在应用更改……",
   APPLY_REASON_COST_PENDING = "正在计算费用……",
   APPLY_REASON_MONEY        = "你的金币不足。",
   APPLY_REASON_SERVER       = "服务器端幻化模块没有响应。",

   MSG_APPLY_OK           = "外观已应用。",
   MSG_APPLY_DONE         = "已更改%d项，失败%d项。",
   MSG_APPLY_SLOT_FAILED  = "无法应用%s的外观。",
   MSG_SERVER_ABSENT      = "服务器端幻化模块没有响应。",
   MSG_NO_VENDOR          = "预览模式：请前往幻化师处应用更改。",

   -- =========================================================================
   -- Filter / Outfits (Core)
   -- =========================================================================
   SORT_QUALITY = "品质",
   SORT_NAME = "名称",
   SORT_ILEVEL = "物品等级",

   OUTFIT_DEFAULT_NAME = "套装 %d",
   OUTFIT_ERR_EMPTY = "请输入套装名称。",
   OUTFIT_ERR_EXISTS = "已存在同名套装。",
   OUTFIT_ERR_LONG = "名称过长（最多32个字符）。",
   OUTFIT_ERR_FULL = "套装数量已达上限。",
   OUTFIT_ERR_NOITEMS = "没有可保存的内容：尚未应用或选择任何外观。",
   OUTFIT_ERR_MISSING = "此套装已不存在。",

   OUTFIT_SKIP_EMPTY = "此部位没有装备物品。",
   OUTFIT_SKIP_NEVER = "此部位无法幻化。",
   OUTFIT_SKIP_LOADING = "此部位的外观列表仍在加载。",
   OUTFIT_SKIP_UNAVAILABLE = "此外观不适用于你已装备的物品。",
   OUTFIT_SKIP_HIDDEN = "此部位无法隐藏。",

   -- =========================================================================
   -- Window
   -- =========================================================================
   WIN_TITLE = "幻化",
   WIN_TAB_ITEMS = "物品",
   WIN_TAB_OUTFITS = "套装",
   WIN_OPTIONS = "选项",
   WIN_CLOSE = "关闭",
   WIN_RESIZE_TIP = "拖动可调整窗口大小。",

   WIN_APPLY = "应用",
   WIN_APPLY_RESET = "应用还原",
   WIN_APPLY_TIP = "应用全部更改：%d",
   WIN_TIP_REMOVE = "移除外观",
   WIN_TIP_HIDDEN = "隐藏",

   WIN_DISCARD = "放弃",
   WIN_DISCARD_TIP = "放弃所有待应用的更改。",
   WIN_DISCARD_NONE = "没有待应用的更改。",
   WIN_REMOVE_ALL = "全部移除",
   WIN_REMOVE_ALL_TIP = "移除所有已应用的外观。",
   WIN_REMOVE_ALL_NONE = "没有已应用的外观。",
   WIN_REMOVE_ALL_TITLE = "移除所有外观",
   WIN_REMOVE_ALL_TEXT = "要移除所有已应用的外观吗？你的装备将恢复显示原始外观。",
   WIN_REMOVED_ALL = "已移除所有外观。",
   WIN_CANCEL = "取消",

   WIN_COST = "费用：",
   WIN_COST_FREE = "免费",
   WIN_COST_PENDING = "...",
   WIN_COST_UNKNOWN = "?",

   WIN_STATUS_PENDING = "待应用的更改：%d",
   WIN_STATUS_APPLYING = "正在应用更改（%d）……",

   -- =========================================================================
   -- Preview
   -- =========================================================================
   PREVIEW_ROTATE_LEFT = "向左旋转",
   PREVIEW_ROTATE_RIGHT = "向右旋转",
   PREVIEW_ROTATE_HOLD = "按住鼠标按键可持续旋转。",

   PREVIEW_RESET = "重置视角",
   PREVIEW_RESET_TIP = "重置旋转、位置和缩放。",

   PREVIEW_HELP_ROTATE = "按住鼠标左键拖动：旋转",
   PREVIEW_HELP_MOVE = "按住鼠标右键拖动：移动",
   PREVIEW_HELP_ZOOM = "鼠标滚轮：缩放",

   PREVIEW_OFFHAND_NOTE = "此预览不显示副手中的单手武器。",
   PREVIEW_OFFHAND_NOTE_MAINHAND = "该单手武器显示在主手（客户端限制）。",

   -- =========================================================================
   -- SlotBar
   -- =========================================================================
   SLOTBAR_NOTHING_EQUIPPED = "未装备物品",
   SLOTBAR_NEVER = "无法幻化",

   SLOTBAR_APPLIED = "已幻化为：%s",
   SLOTBAR_HIDDEN = "隐藏",
   SLOTBAR_PENDING = "待应用：%s",
   SLOTBAR_PENDING_RESET = "待应用：还原为原始外观",
   SLOTBAR_INACTIVE = "未生效：%s（与已装备的物品不匹配）",
   SLOTBAR_UNKNOWN_ITEM = "物品 %d",

   SLOTBAR_AVAILABLE = "可用外观：%d",
   SLOTBAR_LOADING = "正在加载外观：%d / %d",

   SLOTBAR_HINT_EDIT = "左键点击：编辑",
   SLOTBAR_HINT_DISCARD = "右键点击：放弃待应用的更改",
   SLOTBAR_HINT_REMOVE = "右键点击：移除幻化",
   SLOTBAR_HINT_LINK = "Shift+点击：链接到聊天框",

   -- =========================================================================
   -- Grid
   -- =========================================================================
   GRID_NO_SLOT           = "请选择装备部位",
   GRID_NO_SLOT_HINT      = "在左侧选择一个部位，即可浏览其外观。",
   GRID_EMPTY_SLOT        = "此部位没有装备物品",
   GRID_EMPTY_SLOT_HINT   = "装备物品后，即可查看适用于它的外观。",
   GRID_NEVER             = "此物品无法幻化",
   GRID_NEVER_HINT        = "戒指、项链、饰品和圣物无法更改外观。",
   GRID_ABSENT            = "服务器端幻化模块没有响应",
   GRID_ABSENT_HINT       = "外观数据从服务器加载。请确认已安装并启用 mod-transmog-plus。",
   GRID_NO_ITEMS          = "暂无匹配的外观",
   GRID_NO_ITEMS_HINT     = "获得适用于此部位的物品后，对应外观即会解锁。",
   GRID_FILTERED          = "没有符合筛选条件的外观",
   GRID_FILTERED_HINT     = "调整或重置上方的筛选条件，可查看更多外观。",
   GRID_RESET_FILTERS     = "重置筛选",

   GRID_LOADING           = "正在加载外观：%s / %s",
   GRID_LOADING_PLAIN     = "正在加载外观……",
   GRID_LOADING_HINT      = "正在向服务器请求物品数据。",
   GRID_PLACEHOLDER       = "...",

   GRID_PAGE              = "第%d / %d页",
   GRID_PAGE_SHORT        = "%d / %d",
   GRID_COUNT             = "%s / %s个外观",
   GRID_COUNT_FILTERED    = "%s / %s个外观（已筛选）",
   GRID_COUNT_DUPES       = "%s / %s个外观（已隐藏%s个重复外观）",
   GRID_COUNT_SHORT       = "%s / %s",
   GRID_PAGE_FIRST        = "第一页",
   GRID_PAGE_PREV         = "上一页",
   GRID_PAGE_NEXT         = "下一页",
   GRID_PAGE_LAST         = "最后一页",

   GRID_ORIGINAL          = "原始",
   GRID_ORIGINAL_TITLE    = "原始外观",
   GRID_ORIGINAL_TIP      = "选择后将移除幻化，并显示已装备物品自身的外观。",
   GRID_HIDDEN            = "隐藏",
   GRID_HIDDEN_TIP        = "选择后将隐藏此部位的装备。",

   GRID_NEW               = "新",
   GRID_TIP_APPLIED       = "当前已应用",
   GRID_TIP_SELECTED      = "已选择，尚未应用",
   GRID_TIP_FAVORITE      = "已收藏",
   GRID_TIP_NEW           = "新解锁",
   GRID_TIP_LEFT_SELECT   = "左键点击：选择",
   GRID_TIP_LEFT_DISCARD  = "左键点击：取消选择",
   GRID_TIP_RIGHT_FAV     = "右键点击：添加或取消收藏",
   GRID_TIP_SHIFT_LINK    = "Shift+左键点击：链接到聊天框",

   -- =========================================================================
   -- FilterBar
   -- =========================================================================
   FILTER_SEARCH_PLACEHOLDER = "搜索名称、类型或 #id",

   FILTER_SORT               = "排序：%s",
   FILTER_SORT_TIP           = "排序方式",
   FILTER_SORT_TIP_HINT      = "点击选择外观的排序方式。",

   FILTER_BUTTON             = "筛选",
   FILTER_BUTTON_TIP         = "筛选外观",
   FILTER_HIDE_DUPLICATES    = "隐藏重复外观",
   FILTER_HIDE_DUPLICATES_TIP = "图标、类型和部位相同的外观仅显示一个（此为近似判断：客户端无法读取真实模型）。",
   FILTER_FAVORITES_ONLY     = "仅显示收藏",
   FILTER_NEW_ONLY           = "仅显示新解锁",
   FILTER_TYPE_TITLE         = "类型",
   FILTER_TYPE_ROW           = "%s（%d）",
   FILTER_TYPE_OWN           = "这是你已装备物品的类型，无法隐藏。",
   FILTER_RESET              = "重置筛选",

   FILTER_RESET_TIP          = "重置所有筛选条件",
   FILTER_RESET_NONE         = "没有启用任何筛选条件。",

   FILTER_QUALITY_COUNT      = "外观数量：%d",
   FILTER_QUALITY_HIDE       = "点击隐藏此品质",
   FILTER_QUALITY_SHOW       = "点击显示此品质",

   FILTER_FAVORITES_CHIP     = "收藏",
   FILTER_FAVORITES_CHIP_TIP = "仅显示已收藏的外观",
   FILTER_NEW                = "新解锁",
   FILTER_NEW_TIP            = "仅显示新解锁的外观",
   FILTER_CHIP_ON            = "已启用，点击可关闭",
   FILTER_CHIP_OFF           = "点击启用",

   -- =========================================================================
   -- Outfits
   -- =========================================================================
   OUTFITS_SAVE = "保存当前外观",
   OUTFITS_SAVE_TIP = "将当前已应用或已选择的外观保存为新的套装。",
   OUTFITS_COUNT = "%d / %d",

   OUTFITS_SAVE_TITLE = "保存套装",
   OUTFITS_SAVE_TEXT = "请输入此套装的名称：",
   OUTFITS_SAVED = "套装“%s”已保存。",

   OUTFITS_PIECES = "部件：%d",
   OUTFITS_PIECES_PARTIAL = "可用：%d / %d",
   OUTFITS_HIDDEN = "隐藏",
   OUTFITS_LOADING = "正在加载……",
   OUTFITS_ITEM_UNKNOWN = "物品 %d",
   OUTFITS_TIP_CURRENT = "与当前外观相同。",

   OUTFITS_LOAD = "加载",
   OUTFITS_LOAD_TIP = "在幻化窗口中选中此套装的各个部件。点击“应用”之前不会应用任何更改。",
   OUTFITS_LOADED = "已加载部件：%d",
   OUTFITS_LOADED_PARTIAL = "已加载部件：%d，不可用：%d",
   OUTFITS_LOADED_NONE = "没有可加载的部件（不可用：%d）",
   OUTFITS_LOADED_PENDING = "已加载部件：%d，仍在加载：%d",
   OUTFITS_LOADED_WAIT = "外观仍在加载，请稍后重试。",
   OUTFITS_LOADED_EMPTY = "此套装不包含任何部件。",

   OUTFITS_OVERWRITE = "覆盖",
   OUTFITS_OVERWRITE_TIP = "用当前外观替换此套装的部件。",
   OUTFITS_OVERWRITE_TITLE = "覆盖套装",
   OUTFITS_OVERWRITE_TEXT = "要用当前外观替换套装“%s”的部件吗？",
   OUTFITS_OVERWRITTEN = "套装“%s”已更新。",

   OUTFITS_RENAME = "重命名",
   OUTFITS_RENAME_TIP = "更改此套装的名称。",
   OUTFITS_RENAME_TITLE = "重命名套装",
   OUTFITS_RENAME_TEXT = "请输入套装“%s”的新名称：",
   OUTFITS_RENAMED = "套装已重命名为“%s”。",

   OUTFITS_DELETE = "删除",
   OUTFITS_DELETE_TIP = "永久删除此套装。",
   OUTFITS_DELETE_TITLE = "删除套装",
   OUTFITS_DELETE_TEXT = "要删除套装“%s”吗？此操作无法撤销。",
   OUTFITS_DELETED = "套装“%s”已删除。",

   OUTFITS_EMPTY_TITLE = "还没有套装",
   OUTFITS_EMPTY_TEXT = "套装会保存你当前已选择或已应用的部件，让你一键恢复整套外观。"
      .. "请在“物品”标签页中选择外观，然后点击“保存当前外观”并为套装命名。",

   OUTFITS_PAGE = "第%d / %d页",
   OUTFITS_PAGE_PREV = "上一页",
   OUTFITS_PAGE_NEXT = "下一页",

   -- =========================================================================
   -- Options
   -- =========================================================================
   OPT_TITLE = "幻化选项",

   OPT_SECTION_LANGUAGE = "语言",
   OPT_LANG_AUTO = "自动（客户端语言：%s）",
   OPT_LANG_TIP = "插件中所有文本使用的语言。",
   OPT_LANG_NOTE = "如果所选语言与游戏客户端语言不同，字体可能缺少部分字符。",

   OPT_SECTION_WINDOW = "窗口",
   OPT_SCALE = "窗口缩放",
   OPT_SCALE_AUTO = "自动",
   OPT_SCALE_TIP = "“自动”会根据屏幕调整窗口大小。拖动滑块可选择固定的缩放比例。",
   OPT_PREVIEW_SIZE = "预览大小",
   OPT_PREVIEW_TIP = "物品网格中外观预览的大小。",
   OPT_PREVIEW_SMALL = "小",
   OPT_PREVIEW_MEDIUM = "中",
   OPT_PREVIEW_LARGE = "大",
   OPT_PREVIEW_XLARGE = "特大",
   OPT_RESET_WINDOW = "重置窗口位置和大小",
   OPT_RESET_WINDOW_TIP = "将幻化窗口恢复为默认的位置和大小。",
   OPT_RESET_DONE = "窗口位置和大小已重置。",

   OPT_SECTION_GENERAL = "常规",
   OPT_SOUND = "应用时播放音效",
   OPT_SOUND_TIP = "成功应用更改后播放音效。",
   OPT_TOASTS = "显示新外观通知",
   OPT_TOASTS_TIP = "解锁新外观时弹出一条小通知。",
   OPT_TOOLTIP_COLLECTED = "鼠标提示：显示“尚未收集此外观”",
   OPT_TOOLTIP_COLLECTED_TIP = "当你尚未收集某件物品的外观时，在其鼠标提示中添加一行说明。",
   OPT_TOOLTIP_APPLIED = "鼠标提示：显示“已幻化为”",
   OPT_TOOLTIP_APPLIED_TIP = "在已装备物品的鼠标提示中添加一行，显示其当前应用的外观。",
   OPT_ALLOW_ANYWHERE = "允许不在幻化师处应用更改",
   OPT_ALLOW_ANYWHERE_TIP = "服务器不会检查你与幻化师之间的距离。"
      .. "启用后（默认），可在任何地方应用更改；"
      .. "关闭后，/transmog 只会打开预览模式，插件只会在你与幻化师对话时应用更改。",

   OPT_MOVE_TOASTS = "移动通知",
   OPT_MOVE_TOASTS_TIP = "显示通知锚点，可将其拖动到新的位置。",
   OPT_TEST_TOAST = "测试通知",
   OPT_TEST_TOAST_TIP = "显示一条示例通知。",

   -- =========================================================================
   -- Features (Tooltips, Toasts)
   -- =========================================================================
   TIP_NOT_COLLECTED = "尚未收集此外观",

   TIP_APPLIED = "已幻化为：%s",
   TIP_APPLIED_HIDDEN = "已幻化为：隐藏",
   TIP_INACTIVE = "幻化未生效：%s",
   TIP_ITEM_UNKNOWN = "物品 %d",

   TOAST_TITLE = "已解锁新外观",
   TOAST_ITEM_UNKNOWN = "物品 %d",

   TOAST_BURST_TITLE = "已解锁多个新外观",
   TOAST_BURST_COUNT = "外观数量：%d",

   TOAST_ANCHOR_LABEL = "拖动我",
   TOAST_ANCHOR_TIP_TITLE = "通知位置",
   TOAST_ANCHOR_TIP_DRAG = "拖动即可移动通知。",
   TOAST_ANCHOR_TIP_RESET = "右键点击：重置位置。",

   -- Hinweis fuer die Nebenhand-Vorschau (Client-Grenze)
   GRID_TIP_OFFHAND_PREVIEW = "预览中单手武器会显示在主手（客户端限制）。",
})
