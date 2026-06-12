#!/bin/bash
# Operability feature matrix: signature scanner, doctor verdicts, winetricks
# marker, Proton pinning, user hooks, crash capture. Mirrors loader-matrix.sh.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0; total=0
check() { total=$((total+1)); if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }

# Sourcing context shared by sections: functions.sh with repo paths.
SCRIPT_DIR="${REPO_ROOT}/scripts"
DATA_DIR="$T/data"; mkdir -p "$DATA_DIR"
DEBUG=false
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/functions.sh"

############################
# Section 1: signature scanner
############################
LOG="$T/server.log"

printf 'stuff\nRefusing to run with the root privileges.\nmore\n' > "$LOG"
out="$(scan_log_signatures "$LOG")"
check "scanner: root-refusal fires non-root hint" '[[ "$out" == *"non-root game_start"* ]]'

printf '0123:err:module:import_dll Library VCRUNTIME140.dll not found\n' > "$LOG"
out="$(scan_log_signatures "$LOG")"
check "scanner: missing DLL fires WINETRICKS hint" '[[ "$out" == *"WINETRICKS_VERBS"* ]]'

printf 'Error! App 3792580 state is 0x6 after update job.\n' > "$LOG"
out="$(scan_log_signatures "$LOG")"
check "scanner: 0x6 manifest fires acf hint" '[[ "$out" == *"appmanifest"* ]]'

printf 'all healthy here\nnothing to see\n' > "$LOG"
out="$(scan_log_signatures "$LOG")"
check "scanner: clean log is silent" '[[ -z "$out" ]]'

mkdir -p "$DATA_DIR/diagnostics.d"
printf 'MY_CUSTOM_FAILURE\tCustom hint fired.\n' > "$DATA_DIR/diagnostics.d/extra.conf"
printf 'blah MY_CUSTOM_FAILURE blah\n' > "$LOG"
out="$(scan_log_signatures "$LOG")"
check "scanner: user-overlay rule honored" '[[ "$out" == *"Custom hint fired."* ]]'

unset GAME_MODULE_PRESET_PATH GAME_MODULE_SETUP_PATH
GAME_CONFIG=vein load_game_module >/dev/null 2>&1 || true
check "loader exports provenance globals" '[[ "${GAME_MODULE_PRESET_PATH:-}" == *"/scripts/games/vein/preset.conf" ]]'

############################
# Section 2: doctor.sh
############################
# Doctor runs degradedly on the dev box: must not crash, must emit sections + RESULT.
drc=0
dout="$(GAME_CONFIG=vein DATA_DIR="$DATA_DIR" GAME_DIR="$T/game" bash "${REPO_ROOT}/scripts/doctor.sh" 2>&1)" || drc=$?
check "doctor: runs to completion off-container" '[[ "$dout" == *"RESULT:"* ]]'
check "doctor: module provenance reported" '[[ "$dout" == *"scripts/games/vein/preset.conf"* ]]'
check "doctor: exit code reflects severity (1 or 2 in degraded env)" '[[ $drc -eq 1 || $drc -eq 2 ]]'

############################
# Section 3: winetricks verb-hash marker
############################
# Drive provision_wine_deps (extracted from start.sh) with a stubbed winetricks.
eval "$(sed -n '/^provision_wine_deps()/,/^}/p' "${REPO_ROOT}/scripts/start.sh")"
WT="$T/wtbin"; mkdir -p "$WT"
printf '#!/bin/bash\necho RAN-WINETRICKS "$@" >> "%s/wt.log"\nexit 0\n' "$T" > "$WT/winetricks"
printf '#!/bin/bash\nexit 0\n' > "$WT/wine64"
chmod +x "$WT/winetricks" "$WT/wine64"
PFX="$T/prefix"; mkdir -p "$PFX/pfx"
log_file="$T/wt-run.log"; touch "$log_file"

wt_runs() { grep -c RAN-WINETRICKS "$T/wt.log" 2>/dev/null || echo 0; }

STEAM_COMPAT_DATA_PATH="$PFX" WINETRICKS_VERBS="vcrun2017 d3dcompiler_47" PATH="$WT:$PATH" provision_wine_deps >/dev/null 2>&1
check "marker: first run provisions + writes hash" '[[ "$(wt_runs)" == "1" && -f "$PFX/.winetricks_verbs.sha256" ]]'

STEAM_COMPAT_DATA_PATH="$PFX" WINETRICKS_VERBS="vcrun2017 d3dcompiler_47" PATH="$WT:$PATH" provision_wine_deps >/dev/null 2>&1
check "marker: unchanged verbs skip" '[[ "$(wt_runs)" == "1" ]]'

STEAM_COMPAT_DATA_PATH="$PFX" WINETRICKS_VERBS="vcrun2017 d3dcompiler_47 crypt32" PATH="$WT:$PATH" provision_wine_deps >/dev/null 2>&1
check "marker: changed verbs re-provision" '[[ "$(wt_runs)" == "2" ]]'

STEAM_COMPAT_DATA_PATH="$PFX" WINETRICKS_VERBS="vcrun2017 d3dcompiler_47 crypt32" WINETRICKS_FORCE=true PATH="$WT:$PATH" provision_wine_deps >/dev/null 2>&1
check "marker: WINETRICKS_FORCE always provisions" '[[ "$(wt_runs)" == "3" ]]'

PFX2="$T/prefix2"; mkdir -p "$PFX2/pfx"; touch "$PFX2/.winetricks_done"
STEAM_COMPAT_DATA_PATH="$PFX2" WINETRICKS_VERBS="vcrun2017" PATH="$WT:$PATH" provision_wine_deps >/dev/null 2>&1
check "marker: legacy boolean adopted without re-run" '[[ "$(wt_runs)" == "3" && -f "$PFX2/.winetricks_verbs.sha256" && ! -f "$PFX2/.winetricks_done" ]]'

############################
# Section 4: PROTON_VERSION pinning
############################
# detect_proton hardcodes the compat dir; test the pin logic through a sandboxed
# clone of the function with the path substituted.
FAKE_COMPAT="$T/compat"; mkdir -p "$FAKE_COMPAT/GE-Proton9-1" "$FAKE_COMPAT/GE-Proton10-34"
eval "$(sed -n '/^detect_proton()/,/^}/p' "${REPO_ROOT}/scripts/functions.sh" | sed "s|/root/.steam/steam/compatibilitytools.d|$FAKE_COMPAT|")"

pin_path=""
PROTON_VERSION="GE-Proton9-1" detect_proton >/dev/null 2>&1 && pin_path="$PROTONPATH"
check "pin: pinned older version wins over newer" '[[ "$pin_path" == *"/GE-Proton9-1" ]]'

rc=0; PROTON_VERSION="GE-Proton99-99" detect_proton >/dev/null 2>&1 || rc=$?
check "pin: missing pinned version fails loud" '[[ $rc -ne 0 ]]'

unset PROTON_VERSION
detect_proton >/dev/null 2>&1 || true
check "pin: unset falls back to latest present" '[[ "$PROTONPATH" == *"/GE-Proton10-34" ]]'

url_line="$(grep -c 'releases/download/\${PROTON_VERSION}/\${PROTON_VERSION}.tar.gz' "${REPO_ROOT}/scripts/01_steam.sh" || true)"
check "pin: 01_steam builds exact tag URL" '[[ "$url_line" == "1" ]]'

############################
# Section 5: user lifecycle hooks
############################
mkdir -p "$DATA_DIR/hooks"
printf 'echo HOOK-RAN-WITH-%s "${GAME_CONFIG:-none}" > "%s/hook.out"\n' 'CONFIG' "$T" > "$DATA_DIR/hooks/pre-start.sh"
( GAME_CONFIG=demo run_user_hook pre-start >/dev/null 2>&1 )
check "hooks: executes with env available" '[[ "$(cat "$T/hook.out" 2>/dev/null)" == "HOOK-RAN-WITH-CONFIG demo" ]]'

printf 'this is ( not bash\n' > "$DATA_DIR/hooks/post-install.sh"
rc=0; ( run_user_hook post-install >/dev/null 2>&1 ) || rc=$?
check "hooks: broken hook aborts" '[[ $rc -ne 0 ]]'

rm -rf "$DATA_DIR/hooks"
out="$(run_user_hook pre-start 2>&1)"
check "hooks: absent hook is silent no-op" '[[ -z "$out" ]]'

############################
# Section 6: fast-exit crash capture
############################
CLOG="$T/crash.log"
printf 'boot\nRefusing to run with the root privileges.\nAborted\n' > "$CLOG"

out="$(capture_fast_exit 1 "$(( $(date +%s) - 5 ))" "$CLOG" 2>&1)"
check "crash: fast abnormal exit captures tail + hint" '[[ "$out" == *"last 40 lines"* && "$out" == *"non-root game_start"* && "$out" == *"doctor.sh"* ]]'

out="$(capture_fast_exit 1 "$(( $(date +%s) - 120 ))" "$CLOG" 2>&1)"
check "crash: slow exit is silent" '[[ -z "$out" ]]'

out="$(capture_fast_exit 0 "$(( $(date +%s) - 5 ))" "$CLOG" 2>&1)"
check "crash: exit 0 is silent" '[[ -z "$out" ]]'

out="$(CRASH_CAPTURE_SECONDS=0 capture_fast_exit 1 "$(( $(date +%s) - 5 ))" "$CLOG" 2>&1)"
check "crash: CRASH_CAPTURE_SECONDS=0 disables" '[[ -z "$out" ]]'

out="$(CRASH_CAPTURE_SECONDS=300 capture_fast_exit 137 "$(( $(date +%s) - 100 ))" "$CLOG" 2>&1)"
check "crash: custom threshold honored" '[[ "$out" == *"exit code 137"* ]]'

echo "OPERABILITY $( [[ $fail -eq 0 ]] && echo PASS || echo FAIL ) (${pass}/${total})"
[[ $fail -eq 0 ]]
