-- Locales\koKR.lua
-- ---------------------------------------------------------------------------
-- Koreanische Texte fuer alle Module. Quelle: Locales\enUS_*.lua.
--
-- Begriffe (einheitlich): 외형 (Aussehen), 의상 (Outfit), 부위 (Ausruestungs-
-- platz und Teil eines Outfits), 즐겨찾기 (Favorit), 적용 (Anwenden),
-- 되돌리기 (Verwerfen), 취소 (Abbrechen), 숨김 (Verborgen), 등급 (Qualitaet),
-- 아이템 (Gegenstand), 형상변환 / 형상변환사 (Transmogrifikation /
-- Transmogrifizierer), 획득 (freischalten), 수집 (gesammelt), 대기 중 (ausstehend).
-- Stil: 해요체 bei Saetzen, Nominalformen bei Beschriftungen.
-- Platzhalter (%s, %d) stehen in gleicher Anzahl und Reihenfolge wie in enUS.
-- ---------------------------------------------------------------------------

local T = Transmog

T.Locale.Add("koKR", {
   -- =========================================================================
   -- Core
   -- =========================================================================
   THOUSANDS_SEP = ",",

   LOADED = "%s %s 로드됨 - /transmog 를 입력하면 창을 열 수 있어요.",
   MIGRATED_OUTFITS = "이전 Transmog 버전의 의상을 가져왔어요: %d",

   -- =========================================================================
   -- Boot
   -- =========================================================================
   -- Tastenbelegung
   BOOT_BINDING_HEADER = "형상변환",
   BOOT_BINDING_TOGGLE = "형상변환 창 열기/닫기",

   BOOT_INIT_FAILED = "%s 모듈을 시작할 수 없어요. 자세한 내용은 오류 보고서를 확인하세요.",
   BOOT_UNAVAILABLE = "애드온의 이 부분은 사용할 수 없어요.",

   BOOT_RESET_DONE = "창 위치와 크기를 초기화했어요.",
   BOOT_LANG_SET = "언어 설정: %s",
   BOOT_LANG_CURRENT = "현재 언어: %s. auto 또는 다음 중 하나를 사용하세요: %s",
   BOOT_LANG_UNKNOWN = "알 수 없는 언어 \"%s\". auto 또는 다음 중 하나를 사용하세요: %s",

   BOOT_DEBUG_ON = "디버그 출력을 켰어요.",
   BOOT_DEBUG_OFF = "디버그 출력을 껐어요.",
   BOOT_DEBUG_INFO = "버전 %s, 언어 %s, 서버 상태 %s, 보낸 메시지 %d, 받은 메시지 %d.",
   BOOT_DEBUG_STATE = "형상변환사 앞: %s, 대기 중인 변경: %d, 목록 준비: %s.",
   BOOT_DEBUG_ITEMS = "대기 중인 아이템 조회: %d, 실패: %d, 타이머: %d, 누락된 텍스트: %d.",
   BOOT_YES = "예",
   BOOT_NO = "아니요",

   BOOT_HELP_TITLE = "명령어 (/transmog 또는 /xmog):",
   BOOT_HELP_TOGGLE = "/transmog - 창 열기/닫기",
   BOOT_HELP_OPTIONS = "/transmog options - 옵션 열기",
   BOOT_HELP_RESET = "/transmog reset - 창 위치와 크기 초기화",
   BOOT_HELP_TOAST = "/transmog toast - 알림 위치 이동",
   BOOT_HELP_LANG = "/transmog lang <code|auto> - 언어 설정",
   BOOT_HELP_DEBUG = "/transmog debug - 디버그 출력 전환",
   BOOT_HELP_HELP = "/transmog help - 이 목록 표시",

   -- =========================================================================
   -- Filter / Outfits (Core)
   -- =========================================================================
   -- Sortierung
   SORT_QUALITY = "등급",
   SORT_NAME = "이름",
   SORT_ILEVEL = "아이템 레벨",

   -- Outfit-Namen und Speicherfehler
   OUTFIT_DEFAULT_NAME = "의상 %d",
   OUTFIT_ERR_EMPTY = "의상 이름을 입력하세요.",
   OUTFIT_ERR_EXISTS = "같은 이름의 의상이 이미 있어요.",
   OUTFIT_ERR_LONG = "이름이 너무 길어요 (최대 32자).",
   OUTFIT_ERR_FULL = "저장할 수 있는 의상의 최대 개수에 도달했어요.",
   OUTFIT_ERR_NOITEMS = "저장할 내용이 없어요. 적용하거나 선택한 외형이 없어요.",
   OUTFIT_ERR_MISSING = "이 의상은 더 이상 존재하지 않아요.",

   -- Gruende fuer uebersprungene Teile
   OUTFIT_SKIP_EMPTY = "이 부위에 착용한 장비가 없어요.",
   OUTFIT_SKIP_NEVER = "이 부위는 형상변환할 수 없어요.",
   OUTFIT_SKIP_LOADING = "이 부위의 외형 목록을 아직 불러오는 중이에요.",
   OUTFIT_SKIP_UNAVAILABLE = "이 외형은 착용 중인 장비에 사용할 수 없어요.",
   OUTFIT_SKIP_HIDDEN = "이 부위는 숨길 수 없어요.",

   -- =========================================================================
   -- State
   -- =========================================================================
   APPLY_REASON_NONE         = "아직 변경한 내용이 없어요.",
   APPLY_REASON_VENDOR       = "변경 사항을 적용하려면 형상변환사를 찾아가세요.",
   APPLY_REASON_BUSY         = "변경 사항을 적용하는 중...",
   APPLY_REASON_COST_PENDING = "비용 계산 중...",
   APPLY_REASON_MONEY        = "골드가 부족해요.",
   APPLY_REASON_SERVER       = "형상변환 서버 모듈이 응답하지 않아요.",

   MSG_APPLY_OK           = "외형을 적용했어요.",
   MSG_APPLY_DONE         = "%d개 변경, %d개 실패.",
   MSG_APPLY_SLOT_FAILED  = "%s 적용에 실패했어요.",
   MSG_SERVER_ABSENT      = "형상변환 서버 모듈이 응답하지 않아요.",
   MSG_NO_VENDOR          = "미리보기 모드 - 변경 사항을 적용하려면 형상변환사를 찾아가세요.",

   -- =========================================================================
   -- Features (Tooltips, Toasts)
   -- =========================================================================
   TIP_NOT_COLLECTED = "외형 미수집",

   TIP_APPLIED = "형상변환: %s",
   TIP_APPLIED_HIDDEN = "형상변환: 숨김",
   TIP_INACTIVE = "형상변환 비활성: %s",
   TIP_ITEM_UNKNOWN = "아이템 %d",

   TOAST_TITLE = "새 외형 획득",
   TOAST_ITEM_UNKNOWN = "아이템 %d",

   TOAST_BURST_TITLE = "새 외형 여러 개 획득",
   TOAST_BURST_COUNT = "외형: %d",

   TOAST_ANCHOR_LABEL = "드래그해서 이동",
   TOAST_ANCHOR_TIP_TITLE = "알림 위치",
   TOAST_ANCHOR_TIP_DRAG = "드래그해서 알림 위치를 옮기세요.",
   TOAST_ANCHOR_TIP_RESET = "오른쪽 클릭: 위치 초기화",

   -- =========================================================================
   -- Window
   -- =========================================================================
   WIN_TITLE = "형상변환",
   WIN_TAB_ITEMS = "아이템",
   WIN_TAB_OUTFITS = "의상",
   WIN_OPTIONS = "옵션",
   WIN_CLOSE = "닫기",
   WIN_RESIZE_TIP = "드래그해서 창 크기를 조절하세요.",

   WIN_APPLY = "적용",
   WIN_APPLY_RESET = "원본 적용",
   WIN_APPLY_TIP = "대기 중인 변경 사항 적용: %d",
   WIN_TIP_REMOVE = "외형 제거",
   WIN_TIP_HIDDEN = "숨김",

   WIN_DISCARD = "되돌리기",
   WIN_DISCARD_TIP = "대기 중인 모든 변경 사항을 되돌려요.",
   WIN_DISCARD_NONE = "대기 중인 변경 사항이 없어요.",
   WIN_REMOVE_ALL = "모두 제거",
   WIN_REMOVE_ALL_TIP = "적용된 모든 외형을 제거해요.",
   WIN_REMOVE_ALL_NONE = "적용된 외형이 없어요.",
   WIN_REMOVE_ALL_TITLE = "모든 외형 제거",
   WIN_REMOVE_ALL_TEXT = "적용된 모든 외형을 제거할까요? 장비가 본래의 외형으로 돌아가요.",
   WIN_REMOVED_ALL = "모든 외형을 제거했어요.",
   WIN_CANCEL = "취소",

   WIN_COST = "비용:",
   WIN_COST_FREE = "무료",
   WIN_COST_PENDING = "...",
   WIN_COST_UNKNOWN = "?",

   WIN_STATUS_PENDING = "대기 중인 변경: %d",
   WIN_STATUS_APPLYING = "변경 사항 적용 중 (%d)...",

   -- =========================================================================
   -- SlotBar
   -- =========================================================================
   SLOTBAR_NOTHING_EQUIPPED = "착용한 장비 없음",
   SLOTBAR_NEVER = "형상변환 불가",

   SLOTBAR_APPLIED = "형상변환: %s",
   SLOTBAR_HIDDEN = "숨김",
   SLOTBAR_PENDING = "대기 중: %s",
   SLOTBAR_PENDING_RESET = "대기 중: 원본으로 되돌리기",
   SLOTBAR_INACTIVE = "비활성: %s (착용한 장비와 맞지 않음)",
   SLOTBAR_UNKNOWN_ITEM = "아이템 %d",

   SLOTBAR_AVAILABLE = "사용 가능: %d",
   SLOTBAR_LOADING = "외형 불러오는 중: %d / %d",

   SLOTBAR_HINT_EDIT = "왼쪽 클릭: 편집",
   SLOTBAR_HINT_DISCARD = "오른쪽 클릭: 대기 중인 변경 되돌리기",
   SLOTBAR_HINT_REMOVE = "오른쪽 클릭: 형상변환 제거",
   SLOTBAR_HINT_LINK = "Shift + 클릭: 대화창에 링크",

   -- =========================================================================
   -- Grid
   -- =========================================================================
   GRID_NO_SLOT           = "장비 부위를 선택하세요",
   GRID_NO_SLOT_HINT      = "왼쪽에서 부위를 선택하면 해당 외형을 볼 수 있어요.",
   GRID_EMPTY_SLOT        = "이 부위에 착용한 장비가 없어요",
   GRID_EMPTY_SLOT_HINT   = "장비를 착용하면 어울리는 외형이 표시돼요.",
   GRID_NEVER             = "이 아이템은 형상변환할 수 없어요",
   GRID_NEVER_HINT        = "반지, 목걸이, 장신구, 유물은 외형을 바꿀 수 없어요.",
   GRID_ABSENT            = "형상변환 서버 모듈이 응답하지 않아요",
   GRID_ABSENT_HINT       = "외형은 서버에서 불러와요. mod-transmog-plus가 설치되어 있고 활성화되어 있는지 확인하세요.",
   GRID_NO_ITEMS          = "맞는 외형이 아직 없어요",
   GRID_NO_ITEMS_HINT     = "이 부위에 맞는 아이템을 획득하면 외형을 사용할 수 있어요.",
   GRID_FILTERED          = "필터와 일치하는 외형이 없어요",
   GRID_FILTERED_HINT     = "위의 필터를 변경하거나 초기화하세요.",
   GRID_RESET_FILTERS     = "필터 초기화",

   GRID_LOADING           = "외형 불러오는 중... %s / %s",
   GRID_LOADING_PLAIN     = "외형 불러오는 중...",
   GRID_LOADING_HINT      = "서버에 아이템 정보를 요청하고 있어요.",
   GRID_PLACEHOLDER       = "...",

   GRID_PAGE              = "페이지 %d / %d",
   GRID_PAGE_SHORT        = "%d / %d",
   GRID_COUNT             = "외형 %s / %s",
   GRID_COUNT_FILTERED    = "외형 %s / %s (필터 적용)",
   GRID_COUNT_DUPES       = "외형 %s / %s (중복 %s개 숨김)",
   GRID_COUNT_SHORT       = "%s / %s",
   GRID_PAGE_FIRST        = "첫 페이지",
   GRID_PAGE_PREV         = "이전 페이지",
   GRID_PAGE_NEXT         = "다음 페이지",
   GRID_PAGE_LAST         = "마지막 페이지",

   GRID_ORIGINAL          = "원본",
   GRID_ORIGINAL_TITLE    = "원본 외형",
   GRID_ORIGINAL_TIP      = "선택하면 형상변환을 제거하고 장비 본래의 외형을 표시해요.",
   GRID_HIDDEN            = "숨김",
   GRID_HIDDEN_TIP        = "선택하면 이 부위의 장비를 숨겨요.",

   GRID_NEW               = "신규",
   GRID_TIP_APPLIED       = "현재 적용 중",
   GRID_TIP_SELECTED      = "선택됨 - 아직 적용 안 됨",
   GRID_TIP_FAVORITE      = "즐겨찾기",
   GRID_TIP_NEW           = "새로 획득",
   GRID_TIP_LEFT_SELECT   = "왼쪽 클릭: 선택",
   GRID_TIP_LEFT_DISCARD  = "왼쪽 클릭: 선택 해제",
   GRID_TIP_RIGHT_FAV     = "오른쪽 클릭: 즐겨찾기 추가/해제",
   GRID_TIP_SHIFT_LINK    = "Shift + 왼쪽 클릭: 대화창에 링크",

   -- =========================================================================
   -- FilterBar
   -- =========================================================================
   FILTER_SEARCH_PLACEHOLDER = "이름, 유형 또는 #id 검색",

   FILTER_SORT               = "정렬: %s",
   FILTER_SORT_TIP           = "정렬 순서",
   FILTER_SORT_TIP_HINT      = "클릭해서 외형 정렬 방식을 선택하세요.",

   FILTER_BUTTON             = "필터",
   FILTER_BUTTON_TIP         = "외형 필터",
   FILTER_HIDE_DUPLICATES    = "중복 외형 숨기기",
   FILTER_HIDE_DUPLICATES_TIP = "아이콘, 유형, 부위가 같은 외형은 하나만 표시해요 (근사치: 클라이언트는 실제 모델을 읽을 수 없어요).",
   FILTER_FAVORITES_ONLY     = "즐겨찾기만",
   FILTER_NEW_ONLY           = "새 외형만",
   FILTER_TYPE_TITLE         = "유형",
   FILTER_TYPE_ROW           = "%s (%d)",
   FILTER_TYPE_OWN           = "착용 중인 장비의 유형이라 숨길 수 없어요.",
   FILTER_RESET              = "필터 초기화",

   FILTER_RESET_TIP          = "모든 필터 초기화",
   FILTER_RESET_NONE         = "활성화된 필터가 없어요.",

   FILTER_QUALITY_COUNT      = "외형: %d",
   FILTER_QUALITY_HIDE       = "클릭하면 이 등급 숨김",
   FILTER_QUALITY_SHOW       = "클릭하면 이 등급 표시",

   FILTER_FAVORITES_CHIP     = "즐겨찾기",
   FILTER_FAVORITES_CHIP_TIP = "즐겨찾기 외형만 표시",
   FILTER_NEW                = "새 외형",
   FILTER_NEW_TIP            = "새로 획득한 외형만 표시",
   FILTER_CHIP_ON            = "활성 - 클릭하면 끔",
   FILTER_CHIP_OFF           = "클릭하면 켬",

   -- =========================================================================
   -- Preview
   -- =========================================================================
   PREVIEW_ROTATE_LEFT = "왼쪽으로 회전",
   PREVIEW_ROTATE_RIGHT = "오른쪽으로 회전",
   PREVIEW_ROTATE_HOLD = "마우스 버튼을 누르고 있으면 계속 회전해요.",

   PREVIEW_RESET = "시점 초기화",
   PREVIEW_RESET_TIP = "회전, 위치, 확대/축소를 초기화해요.",

   PREVIEW_HELP_ROTATE = "왼쪽 버튼 드래그: 회전",
   PREVIEW_HELP_MOVE = "오른쪽 버튼 드래그: 이동",
   PREVIEW_HELP_ZOOM = "마우스 휠: 확대/축소",

   PREVIEW_OFFHAND_NOTE = "보조 장비 칸의 한손 무기는 이 미리보기에 표시되지 않아요.",
   PREVIEW_OFFHAND_NOTE_MAINHAND = "이 한손 무기는 주무기 손에 표시됩니다 (클라이언트 제한).",

   -- =========================================================================
   -- Outfits (Reiter)
   -- =========================================================================
   OUTFITS_SAVE = "현재 외형 저장",
   OUTFITS_SAVE_TIP = "현재 적용했거나 선택한 외형을 새 의상으로 저장해요.",
   OUTFITS_COUNT = "%d / %d",

   OUTFITS_SAVE_TITLE = "의상 저장",
   OUTFITS_SAVE_TEXT = "이 의상의 이름을 입력하세요:",
   OUTFITS_SAVED = "의상 \"%s\"을(를) 저장했어요.",

   OUTFITS_PIECES = "부위: %d",
   OUTFITS_PIECES_PARTIAL = "사용 가능: %d / %d",
   OUTFITS_HIDDEN = "숨김",
   OUTFITS_LOADING = "불러오는 중...",
   OUTFITS_ITEM_UNKNOWN = "아이템 %d",
   OUTFITS_TIP_CURRENT = "현재 외형과 같아요.",

   OUTFITS_LOAD = "불러오기",
   OUTFITS_LOAD_TIP = "이 의상의 부위를 옷장에서 선택해요. 적용 버튼을 클릭하기 전에는 아무것도 적용되지 않아요.",
   OUTFITS_LOADED = "불러온 부위: %d",
   OUTFITS_LOADED_PARTIAL = "불러온 부위: %d, 사용 불가: %d",
   OUTFITS_LOADED_NONE = "불러올 수 있는 부위가 없어요 (사용 불가: %d)",
   OUTFITS_LOADED_PENDING = "불러온 부위: %d, 불러오는 중: %d",
   OUTFITS_LOADED_WAIT = "외형을 아직 불러오는 중이에요. 다시 시도하세요.",
   OUTFITS_LOADED_EMPTY = "이 의상에는 부위가 없어요.",

   OUTFITS_OVERWRITE = "덮어쓰기",
   OUTFITS_OVERWRITE_TIP = "이 의상의 부위를 현재 외형으로 바꿔요.",
   OUTFITS_OVERWRITE_TITLE = "의상 덮어쓰기",
   OUTFITS_OVERWRITE_TEXT = "의상 \"%s\"의 부위를 현재 외형으로 바꿀까요?",
   OUTFITS_OVERWRITTEN = "의상 \"%s\"을(를) 업데이트했어요.",

   OUTFITS_RENAME = "이름 변경",
   OUTFITS_RENAME_TIP = "이 의상의 이름을 변경해요.",
   OUTFITS_RENAME_TITLE = "의상 이름 변경",
   OUTFITS_RENAME_TEXT = "의상 \"%s\"의 새 이름을 입력하세요:",
   OUTFITS_RENAMED = "의상 이름을 \"%s\"(으)로 변경했어요.",

   OUTFITS_DELETE = "삭제",
   OUTFITS_DELETE_TIP = "이 의상을 영구적으로 삭제해요.",
   OUTFITS_DELETE_TITLE = "의상 삭제",
   OUTFITS_DELETE_TEXT = "의상 \"%s\"을(를) 삭제할까요? 되돌릴 수 없어요.",
   OUTFITS_DELETED = "의상 \"%s\"을(를) 삭제했어요.",

   OUTFITS_EMPTY_TITLE = "아직 의상이 없어요",
   OUTFITS_EMPTY_TEXT = "의상은 현재 선택했거나 적용한 부위를 저장해 두는 기능이에요. 클릭 한 번으로 "
      .. "전체 외형을 다시 불러올 수 있어요. 아이템 탭에서 외형을 선택한 다음 "
      .. "\"현재 외형 저장\"을 클릭하고 의상 이름을 입력하세요.",

   OUTFITS_PAGE = "페이지 %d / %d",
   OUTFITS_PAGE_PREV = "이전 페이지",
   OUTFITS_PAGE_NEXT = "다음 페이지",

   -- =========================================================================
   -- Options
   -- =========================================================================
   OPT_TITLE = "형상변환 옵션",

   OPT_SECTION_LANGUAGE = "언어",
   OPT_LANG_AUTO = "자동 (클라이언트 언어: %s)",
   OPT_LANG_TIP = "이 애드온의 모든 텍스트에 사용할 언어예요.",
   OPT_LANG_NOTE = "게임 클라이언트와 다른 언어를 선택하면 글꼴에 일부 문자가 없을 수 있어요.",

   OPT_SECTION_WINDOW = "창",
   OPT_SCALE = "창 배율",
   OPT_SCALE_AUTO = "자동",
   OPT_SCALE_TIP = "자동은 창을 화면 크기에 맞춰요. 슬라이더를 움직이면 고정 배율을 선택해요.",
   OPT_PREVIEW_SIZE = "미리보기 크기",
   OPT_PREVIEW_TIP = "아이템 목록에 표시되는 외형 미리보기의 크기예요.",
   OPT_PREVIEW_SMALL = "작게",
   OPT_PREVIEW_MEDIUM = "보통",
   OPT_PREVIEW_LARGE = "크게",
   OPT_PREVIEW_XLARGE = "매우 크게",
   OPT_RESET_WINDOW = "창 위치와 크기 초기화",
   OPT_RESET_WINDOW_TIP = "옷장 창을 기본 위치와 크기로 되돌려요.",
   OPT_RESET_DONE = "창 위치와 크기를 초기화했어요.",

   OPT_SECTION_GENERAL = "일반",
   OPT_SOUND = "적용 시 소리 재생",
   OPT_SOUND_TIP = "변경 사항이 성공적으로 적용되면 소리를 재생해요.",
   OPT_TOASTS = "새 외형 알림",
   OPT_TOASTS_TIP = "새 외형을 획득하면 작은 알림을 표시해요.",
   OPT_TOOLTIP_COLLECTED = "툴팁: \"외형 미수집\" 표시",
   OPT_TOOLTIP_COLLECTED_TIP = "외형을 아직 수집하지 않았으면 아이템 툴팁에 한 줄을 추가해요.",
   OPT_TOOLTIP_APPLIED = "툴팁: \"형상변환\" 표시",
   OPT_TOOLTIP_APPLIED_TIP = "착용 중인 아이템의 툴팁에 적용된 외형을 보여 주는 줄을 추가해요.",
   OPT_ALLOW_ANYWHERE = "형상변환사 없이 적용 허용",
   OPT_ALLOW_ANYWHERE_TIP = "서버는 형상변환사와의 거리를 확인하지 않아요. "
      .. "켜면(기본값) 어디서든 변경 사항을 적용할 수 있어요. "
      .. "끄면 /transmog는 미리보기 모드만 열고, 형상변환사와 대화 중일 때만 적용해요.",

   OPT_MOVE_TOASTS = "알림 위치 이동",
   OPT_MOVE_TOASTS_TIP = "알림 위치 표시기를 보여 줘요. 드래그해서 새 위치로 옮길 수 있어요.",
   OPT_TEST_TOAST = "알림 테스트",
   OPT_TEST_TOAST_TIP = "샘플 알림을 표시해요.",

   -- Hinweis fuer die Nebenhand-Vorschau (Client-Grenze)
   GRID_TIP_OFFHAND_PREVIEW = "미리보기는 한손 무기를 주무기 손에 표시합니다 (클라이언트 제한).",
})
