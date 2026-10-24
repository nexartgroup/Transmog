-- Locales\zhTW.lua
-- ---------------------------------------------------------------------------
-- Traditionelles Chinesisch (Taiwan). Alle Schluessel aus Locales\enUS_*.lua.
--
-- Begriffe (einheitlich): 外觀 = Aussehen, 造型 = aktueller Gesamt-Look,
-- 搭配 = Outfit, 欄位 = Slot, 最愛 = Favorit, 篩選 = Filter, 套用 = Anwenden,
-- 塑形 = Transmogrifikation, 塑形師 = Transmogrifizierer (NPC),
-- 待處理 = ausstehend, 部件 = Teil eines Outfits.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("zhTW", {
   -- ===== Core =====
   THOUSANDS_SEP = ",",
   LOADED = "%s %s 已載入 - 輸入 /transmog 開啟視窗。",
   MIGRATED_OUTFITS = "已從舊版 Transmog 匯入搭配：%d",

   -- ===== Boot =====
   BOOT_BINDING_HEADER = "塑形",
   BOOT_BINDING_TOGGLE = "開啟或關閉塑形視窗",

   BOOT_INIT_FAILED = "無法啟動「%s」模組。詳細資訊請見錯誤報告。",
   BOOT_UNAVAILABLE = "插件的這個部分無法使用。",

   BOOT_RESET_DONE = "視窗位置與大小已重置。",
   BOOT_LANG_SET = "語言已設定為 %s。",
   BOOT_LANG_CURRENT = "目前語言：%s。請使用 auto 或下列其中之一：%s",
   BOOT_LANG_UNKNOWN = "未知的語言「%s」。請使用 auto 或下列其中之一：%s",

   BOOT_DEBUG_ON = "已啟用除錯輸出。",
   BOOT_DEBUG_OFF = "已停用除錯輸出。",
   BOOT_DEBUG_INFO = "版本 %s，語言 %s，伺服器狀態 %s，已傳送訊息 %d，已接收 %d。",
   BOOT_DEBUG_STATE = "位於塑形師處：%s，待處理變更：%d，清單已就緒：%s。",
   BOOT_DEBUG_ITEMS = "待處理的物品查詢：%d，失敗：%d，計時器：%d，缺少文字：%d。",
   BOOT_YES = "是",
   BOOT_NO = "否",

   BOOT_HELP_TITLE = "指令（/transmog 或 /xmog）：",
   BOOT_HELP_TOGGLE = "/transmog - 開啟或關閉視窗",
   BOOT_HELP_OPTIONS = "/transmog options - 開啟設定",
   BOOT_HELP_RESET = "/transmog reset - 重置視窗位置與大小",
   BOOT_HELP_TOAST = "/transmog toast - 移動通知位置",
   BOOT_HELP_LANG = "/transmog lang <code|auto> - 設定語言",
   BOOT_HELP_DEBUG = "/transmog debug - 切換除錯輸出",
   BOOT_HELP_HELP = "/transmog help - 顯示此清單",

   -- ===== State =====
   APPLY_REASON_NONE         = "尚未變更任何內容。",
   APPLY_REASON_VENDOR       = "請前往塑形師處套用變更。",
   APPLY_REASON_BUSY         = "正在套用變更...",
   APPLY_REASON_COST_PENDING = "正在計算費用...",
   APPLY_REASON_MONEY        = "你的金錢不足。",
   APPLY_REASON_SERVER       = "塑形伺服器模組沒有回應。",

   MSG_APPLY_OK           = "外觀已套用。",
   MSG_APPLY_DONE         = "已變更 %d 個，失敗 %d 個。",
   MSG_APPLY_SLOT_FAILED  = "%s 無法套用。",
   MSG_SERVER_ABSENT      = "塑形伺服器模組沒有回應。",
   MSG_NO_VENDOR          = "預覽模式 - 前往塑形師處套用變更。",

   -- ===== Filter / Outfits (Core) =====
   SORT_QUALITY = "品質",
   SORT_NAME = "名稱",
   SORT_ILEVEL = "物品等級",

   OUTFIT_DEFAULT_NAME = "搭配 %d",
   OUTFIT_ERR_EMPTY = "請輸入搭配的名稱。",
   OUTFIT_ERR_EXISTS = "已有同名的搭配。",
   OUTFIT_ERR_LONG = "名稱太長（最多 32 個字元）。",
   OUTFIT_ERR_FULL = "搭配數量已達上限。",
   OUTFIT_ERR_NOITEMS = "沒有可儲存的內容：未套用或選擇任何外觀。",
   OUTFIT_ERR_MISSING = "此搭配已不存在。",

   OUTFIT_SKIP_EMPTY = "此欄位未裝備任何物品。",
   OUTFIT_SKIP_NEVER = "此欄位無法塑形。",
   OUTFIT_SKIP_LOADING = "此欄位的外觀清單仍在載入中。",
   OUTFIT_SKIP_UNAVAILABLE = "此外觀不適用於你所裝備的物品。",
   OUTFIT_SKIP_HIDDEN = "此欄位無法隱藏。",

   -- ===== Features: Tooltips / Toasts =====
   TIP_NOT_COLLECTED = "外觀尚未收集",

   TIP_APPLIED = "已塑形為：%s",
   TIP_APPLIED_HIDDEN = "已塑形為：隱藏",
   TIP_INACTIVE = "塑形未生效：%s",
   TIP_ITEM_UNKNOWN = "物品 %d",

   TOAST_TITLE = "已解鎖新外觀",
   TOAST_ITEM_UNKNOWN = "物品 %d",

   TOAST_BURST_TITLE = "已解鎖多個新外觀",
   TOAST_BURST_COUNT = "外觀數量：%d",

   TOAST_ANCHOR_LABEL = "拖曳移動",
   TOAST_ANCHOR_TIP_TITLE = "通知位置",
   TOAST_ANCHOR_TIP_DRAG = "拖曳以移動通知。",
   TOAST_ANCHOR_TIP_RESET = "右鍵點擊：重置位置。",

   -- ===== Window =====
   WIN_TITLE = "塑形",
   WIN_TAB_ITEMS = "物品",
   WIN_TAB_OUTFITS = "搭配",
   WIN_OPTIONS = "選項",
   WIN_CLOSE = "關閉",
   WIN_RESIZE_TIP = "拖曳以調整視窗大小。",

   WIN_APPLY = "套用",
   WIN_APPLY_RESET = "套用還原",
   WIN_APPLY_TIP = "套用待處理的變更：%d",
   WIN_TIP_REMOVE = "移除外觀",
   WIN_TIP_HIDDEN = "隱藏",

   WIN_DISCARD = "捨棄",
   WIN_DISCARD_TIP = "捨棄所有待處理的變更。",
   WIN_DISCARD_NONE = "沒有待處理的變更。",
   WIN_REMOVE_ALL = "全部移除",
   WIN_REMOVE_ALL_TIP = "移除所有已套用的外觀。",
   WIN_REMOVE_ALL_NONE = "沒有已套用的外觀。",
   WIN_REMOVE_ALL_TITLE = "移除所有外觀",
   WIN_REMOVE_ALL_TEXT = "要移除所有已套用的外觀嗎？你的裝備將重新顯示原始外觀。",
   WIN_REMOVED_ALL = "已移除所有外觀。",
   WIN_CANCEL = "取消",

   WIN_COST = "費用：",
   WIN_COST_FREE = "免費",
   WIN_COST_PENDING = "...",
   WIN_COST_UNKNOWN = "?",

   WIN_STATUS_PENDING = "待處理的變更：%d",
   WIN_STATUS_APPLYING = "正在套用變更（%d）...",

   -- ===== FilterBar =====
   FILTER_SEARCH_PLACEHOLDER = "搜尋名稱、類型或 #id",

   FILTER_SORT               = "排序：%s",
   FILTER_SORT_TIP           = "排序方式",
   FILTER_SORT_TIP_HINT      = "點擊以選擇外觀的排序方式。",

   FILTER_BUTTON             = "篩選",
   FILTER_BUTTON_TIP         = "篩選外觀",
   FILTER_HIDE_DUPLICATES    = "隱藏重複外觀",
   FILTER_HIDE_DUPLICATES_TIP = "圖示、類型與欄位相同的外觀只顯示一筆（近似判斷：用戶端無法讀取實際模型）。",
   FILTER_FAVORITES_ONLY     = "僅顯示最愛",
   FILTER_NEW_ONLY           = "僅顯示新解鎖",
   FILTER_TYPE_TITLE         = "類型",
   FILTER_TYPE_ROW           = "%s (%d)",
   FILTER_TYPE_OWN           = "這是你所裝備物品的類型，無法隱藏。",
   FILTER_RESET              = "重置篩選",

   FILTER_RESET_TIP          = "重置所有篩選",
   FILTER_RESET_NONE         = "沒有啟用任何篩選。",

   FILTER_QUALITY_COUNT      = "外觀數量：%d",
   FILTER_QUALITY_HIDE       = "點擊以隱藏此品質",
   FILTER_QUALITY_SHOW       = "點擊以顯示此品質",

   FILTER_FAVORITES_CHIP     = "最愛",
   FILTER_FAVORITES_CHIP_TIP = "僅顯示最愛的外觀",
   FILTER_NEW                = "新解鎖",
   FILTER_NEW_TIP            = "僅顯示新解鎖的外觀",
   FILTER_CHIP_ON            = "已啟用 - 點擊以關閉",
   FILTER_CHIP_OFF           = "點擊以開啟",

   -- ===== Grid =====
   GRID_NO_SLOT           = "請選擇裝備欄位",
   GRID_NO_SLOT_HINT      = "選擇左側的欄位以瀏覽其外觀。",
   GRID_EMPTY_SLOT        = "此欄位未裝備物品",
   GRID_EMPTY_SLOT_HINT   = "裝備物品後即可查看適用的外觀。",
   GRID_NEVER             = "此物品無法塑形",
   GRID_NEVER_HINT        = "戒指、項鍊、飾品與聖物無法改變外觀。",
   GRID_ABSENT            = "塑形伺服器模組沒有回應",
   GRID_ABSENT_HINT       = "外觀從伺服器載入。請確認已安裝並啟用 mod-transmog-plus。",
   GRID_NO_ITEMS          = "尚無符合的外觀",
   GRID_NO_ITEMS_HINT     = "取得適用於此欄位的物品後即可解鎖。",
   GRID_FILTERED          = "沒有符合篩選條件的外觀",
   GRID_FILTERED_HINT     = "更改或重置上方的篩選以查看更多。",
   GRID_RESET_FILTERS     = "重置篩選",

   GRID_LOADING           = "正在載入外觀... %s / %s",
   GRID_LOADING_PLAIN     = "正在載入外觀...",
   GRID_LOADING_HINT      = "正在向伺服器請求物品資料。",
   GRID_PLACEHOLDER       = "...",

   GRID_PAGE              = "第 %d / %d 頁",
   GRID_PAGE_SHORT        = "%d / %d",
   GRID_COUNT             = "%s / %s 個外觀",
   GRID_COUNT_FILTERED    = "%s / %s 個外觀（已篩選）",
   GRID_COUNT_DUPES       = "%s / %s 個外觀（已隱藏 %s 個重複外觀）",
   GRID_COUNT_SHORT       = "%s / %s",
   GRID_PAGE_FIRST        = "第一頁",
   GRID_PAGE_PREV         = "上一頁",
   GRID_PAGE_NEXT         = "下一頁",
   GRID_PAGE_LAST         = "最後一頁",

   GRID_ORIGINAL          = "原始",
   GRID_ORIGINAL_TITLE    = "原始外觀",
   GRID_ORIGINAL_TIP      = "選擇以移除塑形，並顯示所裝備物品本身的外觀。",
   GRID_HIDDEN            = "隱藏",
   GRID_HIDDEN_TIP        = "選擇以隱藏此欄位的裝備。",

   GRID_NEW               = "新",
   GRID_TIP_APPLIED       = "目前已套用",
   GRID_TIP_SELECTED      = "已選擇 - 尚未套用",
   GRID_TIP_FAVORITE      = "最愛",
   GRID_TIP_NEW           = "新解鎖",
   GRID_TIP_LEFT_SELECT   = "左鍵點擊：選擇",
   GRID_TIP_LEFT_DISCARD  = "左鍵點擊：取消選擇",
   GRID_TIP_RIGHT_FAV     = "右鍵點擊：切換最愛",
   GRID_TIP_SHIFT_LINK    = "Shift + 左鍵點擊：連結到聊天視窗",

   -- ===== SlotBar =====
   SLOTBAR_NOTHING_EQUIPPED = "未裝備物品",
   SLOTBAR_NEVER = "無法塑形",

   SLOTBAR_APPLIED = "已塑形為：%s",
   SLOTBAR_HIDDEN = "隱藏",
   SLOTBAR_PENDING = "待處理：%s",
   SLOTBAR_PENDING_RESET = "待處理：還原為原始外觀",
   SLOTBAR_INACTIVE = "未生效：%s（不適用於所裝備的物品）",
   SLOTBAR_UNKNOWN_ITEM = "物品 %d",

   SLOTBAR_AVAILABLE = "可用：%d",
   SLOTBAR_LOADING = "正在載入外觀：%d / %d",

   SLOTBAR_HINT_EDIT = "左鍵點擊：編輯",
   SLOTBAR_HINT_DISCARD = "右鍵點擊：捨棄待處理的變更",
   SLOTBAR_HINT_REMOVE = "右鍵點擊：移除塑形",
   SLOTBAR_HINT_LINK = "Shift + 點擊：連結到聊天視窗",

   -- ===== Preview =====
   PREVIEW_ROTATE_LEFT = "向左旋轉",
   PREVIEW_ROTATE_RIGHT = "向右旋轉",
   PREVIEW_ROTATE_HOLD = "按住滑鼠按鍵可持續旋轉。",

   PREVIEW_RESET = "重置檢視",
   PREVIEW_RESET_TIP = "重置旋轉、位置與縮放。",

   PREVIEW_HELP_ROTATE = "按住滑鼠左鍵拖曳：旋轉",
   PREVIEW_HELP_MOVE = "按住滑鼠右鍵拖曳：移動",
   PREVIEW_HELP_ZOOM = "滑鼠滾輪：縮放",

   PREVIEW_OFFHAND_NOTE = "此預覽不會顯示副手的單手武器。",
   PREVIEW_OFFHAND_NOTE_MAINHAND = "該單手武器顯示在主手（用戶端限制）。",

   -- ===== Options =====
   OPT_TITLE = "塑形選項",

   OPT_SECTION_LANGUAGE = "語言",
   OPT_LANG_AUTO = "自動（用戶端語言：%s）",
   OPT_LANG_TIP = "此插件所有文字的語言。",
   OPT_LANG_NOTE = "若語言與遊戲用戶端不同，字型可能缺少部分字元。",

   OPT_SECTION_WINDOW = "視窗",
   OPT_SCALE = "視窗縮放",
   OPT_SCALE_AUTO = "自動",
   OPT_SCALE_TIP = "自動會依螢幕調整視窗大小。移動滑桿可選擇固定的縮放比例。",
   OPT_PREVIEW_SIZE = "預覽大小",
   OPT_PREVIEW_TIP = "物品格中外觀預覽的大小。",
   OPT_PREVIEW_SMALL = "小",
   OPT_PREVIEW_MEDIUM = "中",
   OPT_PREVIEW_LARGE = "大",
   OPT_PREVIEW_XLARGE = "特大",
   OPT_RESET_WINDOW = "重置視窗位置與大小",
   OPT_RESET_WINDOW_TIP = "將衣櫥視窗還原為預設的位置與大小。",
   OPT_RESET_DONE = "視窗位置與大小已重置。",

   OPT_SECTION_GENERAL = "一般",
   OPT_SOUND = "套用時播放音效",
   OPT_SOUND_TIP = "成功套用變更時播放音效。",
   OPT_TOASTS = "新外觀通知",
   OPT_TOASTS_TIP = "解鎖新外觀時顯示小型通知。",
   OPT_TOOLTIP_COLLECTED = "提示：顯示「外觀尚未收集」",
   OPT_TOOLTIP_COLLECTED_TIP = "尚未收集該外觀時，在物品提示中加入一行說明。",
   OPT_TOOLTIP_APPLIED = "提示：顯示「已塑形為」",
   OPT_TOOLTIP_APPLIED_TIP = "在已裝備物品的提示中加入一行，顯示套用在其上的外觀。",
   OPT_ALLOW_ANYWHERE = "允許不在塑形師處套用",
   OPT_ALLOW_ANYWHERE_TIP = "伺服器不會檢查你與塑形師的距離。"
      .. "啟用後（預設）可在任何地方套用變更；"
      .. "關閉後，/transmog 只會開啟預覽模式，插件只會在你與塑形師對話時套用變更。",

   OPT_MOVE_TOASTS = "移動通知",
   OPT_MOVE_TOASTS_TIP = "顯示通知定位點，可將其拖曳到新位置。",
   OPT_TEST_TOAST = "測試通知",
   OPT_TEST_TOAST_TIP = "顯示範例通知。",

   -- ===== Outfits tab =====
   OUTFITS_SAVE = "儲存目前造型",
   OUTFITS_SAVE_TIP = "將目前已套用或已選擇的外觀儲存為新的搭配。",
   OUTFITS_COUNT = "%d / %d",

   OUTFITS_SAVE_TITLE = "儲存搭配",
   OUTFITS_SAVE_TEXT = "請輸入此搭配的名稱：",
   OUTFITS_SAVED = "搭配「%s」已儲存。",

   OUTFITS_PIECES = "部件：%d",
   OUTFITS_PIECES_PARTIAL = "可用：%d / %d",
   OUTFITS_HIDDEN = "隱藏",
   OUTFITS_LOADING = "載入中...",
   OUTFITS_ITEM_UNKNOWN = "物品 %d",
   OUTFITS_TIP_CURRENT = "與目前造型相同。",

   OUTFITS_LOAD = "載入",
   OUTFITS_LOAD_TIP = "在衣櫥中選擇此搭配的部件。在你點擊「套用」之前不會套用任何變更。",
   OUTFITS_LOADED = "已載入部件：%d",
   OUTFITS_LOADED_PARTIAL = "已載入部件：%d，無法使用：%d",
   OUTFITS_LOADED_NONE = "沒有可載入的部件（無法使用：%d）",
   OUTFITS_LOADED_PENDING = "已載入部件：%d，仍在載入：%d",
   OUTFITS_LOADED_WAIT = "外觀仍在載入中 - 請再試一次。",
   OUTFITS_LOADED_EMPTY = "此搭配不包含任何部件。",

   OUTFITS_OVERWRITE = "覆寫",
   OUTFITS_OVERWRITE_TIP = "以目前造型取代此搭配的部件。",
   OUTFITS_OVERWRITE_TITLE = "覆寫搭配",
   OUTFITS_OVERWRITE_TEXT = "要以目前造型取代搭配「%s」的部件嗎？",
   OUTFITS_OVERWRITTEN = "搭配「%s」已更新。",

   OUTFITS_RENAME = "重新命名",
   OUTFITS_RENAME_TIP = "變更此搭配的名稱。",
   OUTFITS_RENAME_TITLE = "重新命名搭配",
   OUTFITS_RENAME_TEXT = "請輸入搭配「%s」的新名稱：",
   OUTFITS_RENAMED = "搭配已重新命名為「%s」。",

   OUTFITS_DELETE = "刪除",
   OUTFITS_DELETE_TIP = "永久移除此搭配。",
   OUTFITS_DELETE_TITLE = "刪除搭配",
   OUTFITS_DELETE_TEXT = "要刪除搭配「%s」嗎？此操作無法復原。",
   OUTFITS_DELETED = "搭配「%s」已刪除。",

   OUTFITS_EMPTY_TITLE = "尚無搭配",
   OUTFITS_EMPTY_TEXT = "搭配會儲存你目前已選擇或已套用的部件，讓你一鍵還原整套造型。"
      .. "請在「物品」分頁中選擇外觀，然後點擊「儲存目前造型」並為搭配命名。",

   OUTFITS_PAGE = "第 %d / %d 頁",
   OUTFITS_PAGE_PREV = "上一頁",
   OUTFITS_PAGE_NEXT = "下一頁",

   -- Hinweis fuer die Nebenhand-Vorschau (Client-Grenze)
   GRID_TIP_OFFHAND_PREVIEW = "預覽中單手武器會顯示在主手（用戶端限制）。",
})
