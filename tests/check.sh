#!/usr/bin/env bash
# =============================================================================
# tests/check.sh  -  statische Pruefungen und Tests des Transmog-Addons
#                    (WoW 3.3.5a, Lua 5.1, Interface 30300)
#
# Aufruf (von ueberall; das Skript wechselt selbst ins Addon-Verzeichnis):
#
#    bash tests/check.sh [Optionen]
#
# Reihenfolge der Schritte:
#   1. syntax   jede *.lua (auch tests/) mit  luajit -bl  uebersetzen
#   2. globals  tests/lint_globals.lua  (unbekannte/versehentliche Globals)
#   3. locale   tests/lint_locale.lua   (Schluessel, Platzhalter, Kodierung)
#   4. style    tests/lint_style.lua    (Lua-5.1-Regeln, Nicht-3.3.5-API,
#                                        Dateihygiene, TOC, XML)
#   5. api      tests/audit_api.lua     (Querpruefung der Modulschnittstellen:
#                                        gerufene Namen definiert, Argumentzahl,
#                                        Ereignisnamen)
#   6. tests    luajit tests/run.lua    (nur, wenn die Datei existiert)
#
# Optionen:
#   --partial   Arbeitsstand: in der TOC gelistete, aber noch nicht vorhandene
#               Dateien sind nur Warnungen (Module entstehen parallel)
#   --strict    Endabnahme: fehlende Sprachdateien (deDE frFR esES ruRU koKR
#               zhCN zhTW), ein fehlendes tests/run.lua und fehlende Module
#               (api) sind Fehler
#   --only LIST nur diese Schritte (Komma-getrennt aus: syntax globals locale
#               style api tests smoke selftest)
#   --smoke     zusaetzlich alle tests/_*_smoke.lua einzeln ausfuehren
#   --selftest  zusaetzlich die Linter gegen eingebaute Fixtures pruefen
#   -v          Linter ausfuehrlich (alle Meldungen, nicht gekuerzt)
#   -h, --help  diese Hilfe
#
# Umgebung:  LUAJIT=/pfad/zu/luajit   (Standard: luajit aus dem PATH)
#            NO_COLOR=1               keine Farben
#
# Exit-Code: 0 = alle ausgefuehrten Schritte bestanden (Warnungen erlaubt),
#            1 = mindestens ein Schritt fehlgeschlagen, 2 = Umgebungsproblem.
#
# Abhaengigkeiten: luajit; fuer die XML-Pruefung xmllint oder python3.
# Laeuft mit der bash 3.2 von macOS (keine assoziativen Arrays, kein mapfile).
# =============================================================================

PARTIAL=0
STRICT=0
VERBOSE=0
ONLY=""
WANT_SMOKE=0
WANT_SELFTEST=0

while [ $# -gt 0 ]; do
   case "$1" in
      --partial) PARTIAL=1 ;;
      --strict) STRICT=1 ;;
      --smoke) WANT_SMOKE=1 ;;
      --selftest) WANT_SELFTEST=1 ;;
      -v|--verbose) VERBOSE=1 ;;
      --only)
         shift
         if [ $# -eq 0 ]; then
            echo "check.sh: --only braucht eine Liste" >&2
            exit 2
         fi
         ONLY="$1"
         ;;
      -h|--help)
         sed -n '2,/^# =====/p' "$0" | sed -e '/^# =====/d' -e 's/^# \{0,1\}//'
         exit 0
         ;;
      *)
         echo "check.sh: unbekannte Option: $1 (siehe --help)" >&2
         exit 2
         ;;
   esac
   shift
done

# --only: nur bekannte Schrittnamen zulassen
if [ -n "$ONLY" ]; then
   OLD_IFS="$IFS"
   IFS=','
   for name in $ONLY; do
      case "$name" in
         syntax|globals|locale|style|api|tests|smoke|selftest) ;;
         *)
            IFS="$OLD_IFS"
            echo "check.sh: unbekannter Schritt in --only: '$name'" >&2
            exit 2
            ;;
      esac
   done
   IFS="$OLD_IFS"
fi

# ---------------------------------------------------------------------------
# Umgebung
# ---------------------------------------------------------------------------

SELF="${BASH_SOURCE[0]:-$0}"
ADDON_DIR="$(cd "$(dirname "$SELF")/.." && pwd)" || exit 2
cd "$ADDON_DIR" || exit 2

LUAJIT="${LUAJIT:-luajit}"
if ! command -v "$LUAJIT" >/dev/null 2>&1; then
   echo "check.sh: luajit nicht gefunden (PATH oder LUAJIT=... setzen)" >&2
   exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/transmog-check.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
   C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
   C_OK=""; C_BAD=""; C_DIM=""; C_OFF=""
fi

# Ergebnisliste (parallele Arrays)
R_NAME=()
R_STATE=()
R_INFO=()
FAILED=0

record() {   # Name Zustand(OK|FAIL|ERROR|SKIP) Info
   R_NAME[${#R_NAME[@]}]="$1"
   R_STATE[${#R_STATE[@]}]="$2"
   R_INFO[${#R_INFO[@]}]="$3"
   case "$2" in FAIL|ERROR) FAILED=$((FAILED + 1)) ;; esac
}

want() {   # Schritt ausgewaehlt?
   case ",$ONLY," in
      ",,") return 0 ;;
      *",$1,"*) return 0 ;;
   esac
   return 1
}

heading() {
   echo
   echo "== $1"
}

# Alle Lua-Dateien relativ zum Addon-Verzeichnis, sortiert; Fixtures ausgenommen.
list_lua_files() {
   find . -type f -name '*.lua' \
      -not -path './.*' -not -path '*/.*/*' \
      -not -path '*/_lintfixtures/*' -not -name 'lint_fixture_*' \
      | sed 's|^\./||' | LC_ALL=C sort
}

# ---------------------------------------------------------------------------
# Schritt 1: Syntax
# ---------------------------------------------------------------------------

step_syntax() {
   heading "syntax: luajit -bl (alle Lua-Dateien)"
   local n=0 bad=0 f
   while IFS= read -r f; do
      [ -n "$f" ] || continue
      n=$((n + 1))
      if ! "$LUAJIT" -bl "$f" >/dev/null 2>"$TMP/syntax.err"; then
         bad=$((bad + 1))
         echo "  $(head -n 1 "$TMP/syntax.err" | sed 's/^luajit: //')"
      fi
   done < <(list_lua_files)
   if [ "$n" -eq 0 ]; then
      echo "  keine Lua-Dateien gefunden"
      record syntax ERROR "keine Lua-Dateien"
   elif [ "$bad" -gt 0 ]; then
      echo "  $bad von $n Datei(en) mit Syntaxfehlern"
      record syntax FAIL "$bad von $n Datei(en) mit Syntaxfehlern"
   else
      echo "  $n Dateien in Ordnung"
      record syntax OK "$n Lua-Dateien"
   fi
}

# ---------------------------------------------------------------------------
# Schritte 2-4: Linter
# ---------------------------------------------------------------------------

run_lint() {   # Name Skript [Argumente...]
   local name="$1" script="$2" rc
   shift 2
   heading "$name: luajit tests/$script $*"
   "$LUAJIT" "tests/$script" "$@" >"$TMP/$name.out" 2>&1
   rc=$?
   cat "$TMP/$name.out"
   if [ "$rc" -eq 0 ]; then
      record "$name" OK "$(tail -n 1 "$TMP/$name.out")"
   elif [ "$rc" -eq 1 ]; then
      record "$name" FAIL "$(tail -n 1 "$TMP/$name.out")"
   else
      record "$name" ERROR "Werkzeugfehler (Exit $rc): $(tail -n 1 "$TMP/$name.out")"
   fi
}

step_globals() {
   if [ ! -f tests/lint_globals.lua ]; then
      record globals ERROR "tests/lint_globals.lua fehlt"
      return
   fi
   local args=()
   run_lint globals lint_globals.lua "${args[@]}"
}

step_locale() {
   if [ ! -f tests/lint_locale.lua ]; then
      record locale ERROR "tests/lint_locale.lua fehlt"
      return
   fi
   local args=()
   [ "$STRICT" -eq 1 ] && args[${#args[@]}]="--strict-locales"
   [ "$VERBOSE" -eq 1 ] && args[${#args[@]}]="-v"
   run_lint locale lint_locale.lua "${args[@]}"
}

step_style() {
   if [ ! -f tests/lint_style.lua ]; then
      record style ERROR "tests/lint_style.lua fehlt"
      return
   fi
   local args=()
   [ "$PARTIAL" -eq 1 ] && args[${#args[@]}]="--partial"
   [ "$VERBOSE" -eq 1 ] && args[${#args[@]}]="-v"
   run_lint style lint_style.lua "${args[@]}"
}

step_api() {
   if [ ! -f tests/audit_api.lua ]; then
      record api ERROR "tests/audit_api.lua fehlt"
      return
   fi
   local args=()
   [ "$STRICT" -eq 1 ] && args[${#args[@]}]="--strict"
   [ "$VERBOSE" -eq 1 ] && args[${#args[@]}]="-v"
   run_lint api audit_api.lua "${args[@]}"
}

# ---------------------------------------------------------------------------
# Schritt 6: Tests
# ---------------------------------------------------------------------------

step_tests() {
   if [ ! -f tests/run.lua ]; then
      heading "tests: tests/run.lua"
      if [ "$STRICT" -eq 1 ]; then
         echo "  tests/run.lua fehlt"
         record tests FAIL "tests/run.lua fehlt"
      else
         echo "  tests/run.lua noch nicht vorhanden - uebersprungen"
         record tests SKIP "tests/run.lua noch nicht vorhanden"
      fi
      return
   fi
   heading "tests: luajit tests/run.lua"
   "$LUAJIT" tests/run.lua >"$TMP/tests.out" 2>&1
   local rc=$?
   cat "$TMP/tests.out"
   if [ "$rc" -eq 0 ]; then
      record tests OK "$(tail -n 1 "$TMP/tests.out")"
   else
      record tests FAIL "Exit $rc: $(tail -n 1 "$TMP/tests.out")"
   fi
}

step_smoke() {
   heading "smoke: tests/_*_smoke.lua"
   local n=0 bad=0 f
   for f in tests/_*_smoke.lua; do
      [ -f "$f" ] || continue
      n=$((n + 1))
      if "$LUAJIT" "$f" >"$TMP/smoke.out" 2>&1; then
         echo "  ok    $f"
      else
         bad=$((bad + 1))
         echo "  FAIL  $f"
         sed 's/^/        /' "$TMP/smoke.out" | head -n 20
      fi
   done
   if [ "$n" -eq 0 ]; then
      echo "  keine Rauchtests vorhanden"
      record smoke SKIP "keine Rauchtests vorhanden"
   elif [ "$bad" -gt 0 ]; then
      record smoke FAIL "$bad von $n fehlgeschlagen"
   else
      record smoke OK "$n Rauchtests"
   fi
}

# ---------------------------------------------------------------------------
# Selbsttest der Linter (Fixtures werden hier erzeugt und danach geloescht)
# ---------------------------------------------------------------------------

ST_PASS=0
ST_FAIL=0

st_ok() {
   ST_PASS=$((ST_PASS + 1))
}

st_bad() {
   ST_FAIL=$((ST_FAIL + 1))
   echo "  FAIL: $1"
}

# st_expect Beschreibung Erwarteter-Exit Ausgabedatei Muster... (fixe Teilstrings)
st_expect() {
   local desc="$1" want_rc="$2" outfile="$3" got_rc="$4" pat
   shift 4
   if [ "$got_rc" -ne "$want_rc" ]; then
      st_bad "$desc: Exit $got_rc statt $want_rc"
      sed 's/^/        /' "$outfile" | head -n 12
      return
   fi
   for pat in "$@"; do
      if ! grep -F -q -- "$pat" "$outfile"; then
         st_bad "$desc: Ausgabe enthaelt nicht: $pat"
         sed 's/^/        /' "$outfile" | head -n 12
         return
      fi
   done
   st_ok
}

# st_absent Beschreibung Ausgabedatei Muster...
st_absent() {
   local desc="$1" outfile="$2" pat
   shift 2
   for pat in "$@"; do
      if grep -F -q -- "$pat" "$outfile"; then
         st_bad "$desc: Ausgabe enthaelt unerwartet: $pat"
         return
      fi
   done
   st_ok
}

step_selftest() {
   heading "selftest: Linter gegen eingebaute Fixtures"
   local d="$TMP/st" out rc
   mkdir -p "$d/g" "$d/s" "$d/loc_bad/Locales" "$d/loc_bad/Core" "$d/loc_ok/Locales" "$d/loc_ok/Core" \
      "$d/toc/Core" "$d/toc/Locales"

   # --- lint_globals ---------------------------------------------------------
   cat > "$d/g/bad.lua" <<'LUA'
local a = 1
leak_write = 5
local function outer()
   local function inner()
      return NoSuch_Read(a)
   end
   nested_leak = inner
   return function()
      deep_leak = true
   end
end
function GlobalFunc() end
print(this, arg1, C_Timer)
LUA
   cat > "$d/g/good.lua" <<'LUA'
local T = Transmog or {}
Transmog = T
TransmogDB = TransmogDB or {}
TransmogMyFrame = CreateFrame("Frame", "TransmogMyFrame", UIParent)
SLASH_TRANSMOG1 = "/transmog"
SlashCmdList["TRANSMOG"] = function() end
StaticPopupDialogs["TRANSMOG_X"] = {}
local ok = RegisterAddonMessagePrefix and RegisterAddonMessagePrefix("transmog")
print(HEADSLOT, floor(1.5), strsplit(",", "a,b"), GetTime(), bit.band(1, 1), ok)
LUA
   "$LUAJIT" tests/lint_globals.lua "$d/g/bad.lua" >"$d/out" 2>&1; rc=$?
   st_expect "globals: schlechte Datei" 1 "$d/out" "$rc" \
      "bad.lua:2: WRITE to global 'leak_write'" \
      "bad.lua:5: read of undefined global 'NoSuch_Read'" \
      "bad.lua:7: WRITE to global 'nested_leak'" \
      "bad.lua:9: WRITE to global 'deep_leak'" \
      "bad.lua:12: WRITE to global 'GlobalFunc'" \
      "'this'" "'arg1'" "'C_Timer'"
   "$LUAJIT" tests/lint_globals.lua "$d/g/good.lua" >"$d/out" 2>&1; rc=$?
   st_expect "globals: saubere Datei" 0 "$d/out" "$rc" "0 violation(s)"
   "$LUAJIT" tests/lint_globals.lua --explain "$d/g/bad.lua" >"$d/out" 2>&1; rc=$?
   st_expect "globals: --explain" 1 "$d/out" "$rc" "== " "leak_write" "WRITE 2"
   "$LUAJIT" tests/lint_globals.lua --listing "$d/g/bad.lua" >"$d/out" 2>&1; rc=$?
   st_expect "globals: --listing" 1 "$d/out" "$rc" "'deep_leak'" "'NoSuch_Read'"

   # --- lint_style -----------------------------------------------------------
   cat > "$d/s/bad.lua" <<'LUA'
local f = CreateFrame("Frame")
f:SetSize(1, 1)
f:SetShown(true)
local t = table.unpack({})
local x = math.type(1)
local y = 7 // 2
local z = 5 & 3
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
C_Timer.After(1, print)
RegisterAddonMessagePrefix("transmog")
local s = string.format("%i", 3)
local function h() return this, arg1 end
goto done
::done::
LUA
   cat > "$d/s/good.lua" <<'LUA'
-- goto, SetSize, C_Timer, this, arg1, table.unpack: nur Kommentar
--[[ langer Kommentar: SetShown utf8.char math.type ]]
local s = "goto SetSize C_Timer this arg1 table.unpack 5 // 2"
local t = [[ SetColorTexture Mixin ]]
local u = { Mixin = 1 }
if RegisterAddonMessagePrefix then
   RegisterAddonMessagePrefix("transmog")
end
local n = 5 ~= 3
return s, t, u, n
LUA
   "$LUAJIT" tests/lint_style.lua -v "$d/s/bad.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: schlechte Datei" 1 "$d/out" "$rc" \
      "bad.lua:2: error [no-api]" "bad.lua:3: error [no-api]" "bad.lua:4: error [lua52-lib]" \
      "bad.lua:5: error [lua52-lib]" "bad.lua:6: error [intdiv]" "bad.lua:7: error [bitop]" \
      "bad.lua:8: error [no-api]" "bad.lua:9: error [no-api]" "bad.lua:10: error [prefix-guard]" \
      "bad.lua:11: error [format-i]" "bad.lua:12: error [implicit-global]" "bad.lua:13: error [goto]" \
      "bad.lua:14: error [label]"
   "$LUAJIT" tests/lint_style.lua "$d/s/good.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: Strings/Kommentare ausgeblendet" 0 "$d/out" "$rc" "0 error(s)"
   cat > "$d/s/tricky.lua" <<'LUA'
-- Randfaelle des Tokenizers: nichts davon darf gemeldet werden
local a = [==[ goto ]] SetSize ]==]
--[==[ goto ::x:: this arg1 ]==]
--[ kein Langkommentar, goto ]
local b = "a\"b goto" .. 'c\'d C_Timer' .. "\\"
local c = 1e5 + 0xFF + 3. + .5 + 1E-3
local d = a --[[ inline goto ]] .. b
local e = "abc\
def goto"
local f = "\10\0\255\065"
local g = 7 % 3 ^ 2 / 4 - #a
local h = (a ~= b) and (c <= d) or (e >= f)
local i = "|cff33a0ea[Transmog]|r %d%% |TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t %s %5.1f %-10s %03d"
local k = a:gsub("(%d+)", "%1")
local t = { Mixin = 1, this = 2, goto_label = 3 }
t.Mixin = t.this
return a, b, c, d, e, f, g, h, i, k
LUA
   "$LUAJIT" -bl "$d/s/tricky.lua" >/dev/null 2>&1; rc=$?
   if [ "$rc" -ne 0 ]; then
      st_bad "style: Fixture tricky.lua ist kein gueltiges Lua"
   else
      "$LUAJIT" tests/lint_style.lua "$d/s/tricky.lua" >"$d/out" 2>&1; rc=$?
      st_expect "style: Tokenizer-Randfaelle ohne Fehlalarm" 0 "$d/out" "$rc" "0 error(s), 0 warning(s)"
   fi
   printf 'local a = 1  \r\nlocal b = 2\t\n' > "$d/s/ws.lua"
   "$LUAJIT" tests/lint_style.lua "$d/s/ws.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: Leerraum/CRLF/Tab" 1 "$d/out" "$rc" "[trailing-ws]" "[tab]" "[crlf]"
   printf '\357\273\277local a = 1\n' > "$d/s/bom.lua"
   "$LUAJIT" tests/lint_style.lua "$d/s/bom.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: BOM" 1 "$d/out" "$rc" "[bom]"
   printf 'local a = "\377\376"\n' > "$d/s/u8.lua"
   "$LUAJIT" tests/lint_style.lua "$d/s/u8.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: ungueltiges UTF-8" 1 "$d/out" "$rc" "[utf8]"
   printf 'local a = 1 -- lint:allow(no-api)\nlocal f = {}\nf:SetSize(1, 1) -- lint:allow(no-api)\n' > "$d/s/allow.lua"
   "$LUAJIT" tests/lint_style.lua "$d/s/allow.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: lint:allow" 0 "$d/out" "$rc" "0 error(s)"

   # --- lint_style: TOC und XML ----------------------------------------------
   printf '## Interface: 30300\n## Title: T\n## SavedVariables: TransmogGlobalDB\n' > "$d/toc/Transmog.toc"
   printf '## SavedVariablesPerCharacter: TransmogDB, transmogOutfits, transmogSettings\n' >> "$d/toc/Transmog.toc"
   printf 'Locales\\Locale.lua\nCore\\Gone.lua\nTransmog.xml\n' >> "$d/toc/Transmog.toc"
   printf 'Transmog = {}\n' > "$d/toc/Locales/Locale.lua"
   printf 'local T = Transmog\n' > "$d/toc/Core/Extra.lua"
   printf '<Ui><DressUpModel name="TransmogCellModelTemplate" virtual="true"></Ui>\n' > "$d/toc/Transmog.xml"
   "$LUAJIT" tests/lint_style.lua --root "$d/toc" >"$d/out" 2>&1; rc=$?
   st_expect "toc: fehlend, nicht gelistet, XML kaputt" 1 "$d/out" "$rc" \
      "[toc-missing] listed file does not exist: Core\\Gone.lua" \
      "[toc-unlisted]" "Core/Extra.lua" "[xml]"
   "$LUAJIT" tests/lint_style.lua --root "$d/toc" --partial >"$d/out" 2>&1; rc=$?
   st_expect "toc: --partial macht Fehlendes zur Warnung" 1 "$d/out" "$rc" \
      "warn  [toc-missing]" "error [toc-unlisted]"

   # --- audit_api ------------------------------------------------------------
   mkdir -p "$d/api/Core"
   printf '## Interface: 30300\nCore\\Mod.lua\nCore\\User.lua\n' > "$d/api/Transmog.toc"
   cat > "$d/api/Core/Mod.lua" <<'LUA'
Transmog = Transmog or {}
local T = Transmog
T.Mod = T.Mod or {}
local Mod = T.Mod
function Mod.Two(a, b) return a, b end
function Mod.Var(...) return ... end
Mod.Value = 5
local Data = { x = 1 }
Mod.Data = Data
T.Events = { Fire = function() end }
LUA
   cat > "$d/api/Core/User.lua" <<'LUA'
local T = Transmog
local Mod = T.Mod
Mod.Two(1, 2)
Mod.Var(1, 2, 3, 4)
local v = Mod.Value + Mod.Data.x
Mod.Two(1, 2, 3)
Mod.Missing()
T.Mod.AlsoMissing(1)
T.Events.Fire("NO_SUCH_EVENT")
local fn = function(a, b) return a, b end
Mod.Two(fn(1, 2), 3)
LUA
   "$LUAJIT" tests/audit_api.lua --root "$d/api" >"$d/out" 2>&1; rc=$?
   st_expect "api: Fehlgriffe werden gefunden" 1 "$d/out" "$rc" \
      "User.lua:6: T.Mod.Two mit 3 Argument(en)" \
      "User.lua:7: T.Mod.Missing ist nirgends definiert" \
      "User.lua:8: T.Mod.AlsoMissing ist nirgends definiert" \
      "unbekanntes Ereignis \"NO_SUCH_EVENT\""
   st_absent "api: korrekte Aufrufe bleiben still" "$d/out" "User.lua:3:" "User.lua:4:" \
      "User.lua:5:" "User.lua:11:"

   # --- lint_locale ----------------------------------------------------------
   if [ -f Locales/Locale.lua ]; then
      cp Locales/Locale.lua "$d/loc_bad/Locales/Locale.lua"
      cp Locales/Locale.lua "$d/loc_ok/Locales/Locale.lua"
      cat > "$d/loc_bad/Locales/enUS_Test.lua" <<'LUA'
local T = Transmog
T.Locale.Add("enUS", {
   GOOD_ONE = "One %s",
   GOOD_TWO = "Two %d of %d",
   UNUSED_KEY = "Never used",
   SORT_ALPHA = "Alpha",
   lower_key = "bad key name",
})
LUA
      cat > "$d/loc_bad/Locales/deDE.lua" <<'LUA'
Transmog.Locale.Add("deDE", {
   GOOD_ONE = "Eins %d",
   SORT_ALPHA = "Alpha",
})
LUA
      printf 'Transmog.Locale.Add("frFR", {\r\n   GOOD_ONE = "Un %%s",\r\n   GOOD_TWO = "Deux %%d sur %%d",\r\n   SORT_ALPHA = "Alpha",\r\n})\r\n' \
         > "$d/loc_bad/Locales/frFR.lua"
      cat > "$d/loc_bad/Core/User.lua" <<'LUA'
local T = Transmog
local L = T.L
local x = "ALPHA"
print(L.GOOD_ONE, L["GOOD_TWO"], L.MISSING_KEY, L["SORT_" .. x], L[x], T.L.OTHER_MISSING, L.lowercase)
LUA
      "$LUAJIT" tests/lint_locale.lua --root "$d/loc_bad" -v >"$d/out" 2>&1; rc=$?
      st_expect "locale: schlechte Sprachdateien" 1 "$d/out" "$rc" \
         "[key-undefined] locale key L.MISSING_KEY" \
         "[key-undefined] locale key L.OTHER_MISSING" \
         "[key-dynamic]" "[key-style]" \
         "[locale-missing]" "GOOD_TWO" \
         "[placeholder] key GOOD_ONE: enUS has (%s) but deDE has (%d)" \
         "[key-charset]" "lower_key" \
         "[crlf]" \
         "[key-unused]" "UNUSED_KEY"
      st_absent "locale: SORT_ALPHA gilt als benutzt" "$d/out" "SORT_ALPHA (enUS)" "not referenced from code: SORT_ALPHA"

      cat > "$d/loc_ok/Locales/enUS_Test.lua" <<'LUA'
local T = Transmog
T.Locale.Add("enUS", {
   GOOD_ONE = "One %s",
   GOOD_TWO = "Two %d of %d",
})
LUA
      cat > "$d/loc_ok/Locales/deDE.lua" <<'LUA'
Transmog.Locale.Add("deDE", {
   GOOD_ONE = "Eins %s",
   GOOD_TWO = "Zwei %d von %d",
})
LUA
      cat > "$d/loc_ok/Core/User.lua" <<'LUA'
local T = Transmog
local L = T.L
print(L.GOOD_ONE, L["GOOD_TWO"])
LUA
      "$LUAJIT" tests/lint_locale.lua --root "$d/loc_ok" >"$d/out" 2>&1; rc=$?
      st_expect "locale: saubere Sprachdateien" 0 "$d/out" "$rc" "0 error(s)"
      "$LUAJIT" tests/lint_locale.lua --root "$d/loc_ok" --strict-locales >"$d/out" 2>&1; rc=$?
      st_expect "locale: --strict-locales verlangt alle Sprachen" 1 "$d/out" "$rc" "[locale-absent]"
   else
      echo "  (Locales/Locale.lua fehlt - Locale-Selbsttests uebersprungen)"
   fi

   echo "  $ST_PASS Pruefungen bestanden, $ST_FAIL fehlgeschlagen"
   if [ "$ST_FAIL" -gt 0 ]; then
      record selftest FAIL "$ST_FAIL von $((ST_PASS + ST_FAIL)) Fixture-Pruefungen fehlgeschlagen"
   else
      record selftest OK "$ST_PASS Fixture-Pruefungen"
   fi
}

# ---------------------------------------------------------------------------
# Hauptlauf
# ---------------------------------------------------------------------------

echo "Transmog static checks  ($ADDON_DIR)"
echo "luajit: $("$LUAJIT" -v 2>&1 | head -n 1)"

if want syntax; then step_syntax; fi
if want globals; then step_globals; fi
if want locale; then step_locale; fi
if want style; then step_style; fi
if want api; then step_api; fi
if want tests; then step_tests; fi
if [ "$WANT_SMOKE" -eq 1 ] || { [ -n "$ONLY" ] && want smoke; }; then step_smoke; fi
if [ "$WANT_SELFTEST" -eq 1 ] || { [ -n "$ONLY" ] && want selftest; }; then step_selftest; fi

echo
echo "=============================================================================="
echo "Zusammenfassung"
i=0
while [ "$i" -lt "${#R_NAME[@]}" ]; do
   state="${R_STATE[$i]}"
   case "$state" in
      OK) tag="${C_OK}[ OK ]${C_OFF}" ;;
      SKIP) tag="${C_DIM}[SKIP]${C_OFF}" ;;
      *) tag="${C_BAD}[FAIL]${C_OFF}" ;;
   esac
   printf '  %s %-9s %s\n' "$tag" "${R_NAME[$i]}" "${R_INFO[$i]}"
   i=$((i + 1))
done

if [ "$FAILED" -gt 0 ]; then
   if [ "$PARTIAL" -eq 0 ] && [ -f "$TMP/style.out" ] && grep -q 'toc-missing' "$TMP/style.out"; then
      echo "  Hinweis: fehlende TOC-Dateien sind im Arbeitsstand normal, siehe --partial."
   fi
   echo "${C_BAD}ERGEBNIS: FEHLGESCHLAGEN${C_OFF} ($FAILED von ${#R_NAME[@]} Schritten)"
   exit 1
fi
echo "${C_OK}ERGEBNIS: BESTANDEN${C_OFF} (${#R_NAME[@]} Schritte)"
exit 0
