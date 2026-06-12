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

echo "OPERABILITY $( [[ $fail -eq 0 ]] && echo PASS || echo FAIL ) (${pass}/${total})"
[[ $fail -eq 0 ]]
