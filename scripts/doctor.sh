#!/bin/bash
# doctor.sh — one-command container diagnosis.
#   docker exec <container> /scripts/doctor.sh
# Prints sectioned PASS/WARN/FAIL findings with actionable hints.
# Read-only; exit code: 0 = all pass, 1 = warnings, 2 = failures.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/functions.sh"
set +e   # doctor must never die mid-diagnosis; functions.sh sets -e

WORST=0
_say()  { printf '%s %s\n' "$1" "$2"; }
pass()  { _say "[PASS]" "$1"; }
warn()  { _say "[WARN]" "$1"; [[ -n "${2:-}" ]] && printf '       → %s\n' "$2"; [[ $WORST -lt 1 ]] && WORST=1; }
fail()  { _say "[FAIL]" "$1"; [[ -n "${2:-}" ]] && printf '       → %s\n' "$2"; WORST=2; }
section(){ printf '\n== %s ==\n' "$1"; }

doctor_image() {
    section "Image"
    pass "build: ${IMAGE_GIT_SHA:-dev} (${IMAGE_BUILD_DATE:-unknown})"
    command -v winetricks >/dev/null 2>&1 && pass "winetricks present" || warn "winetricks missing" "WINETRICKS_VERBS provisioning unavailable (image too old?)"
    command -v nc >/dev/null 2>&1 || warn "nc missing — port probes skipped"
}

doctor_module() {
    section "Module"
    if [[ -z "${GAME_CONFIG:-}" ]]; then
        warn "GAME_CONFIG not set" "running generic configuration"
        return
    fi
    load_game_module >/dev/null 2>&1
    if [[ -n "${GAME_MODULE_PRESET_PATH:-}" ]]; then
        local tag=""; [[ "$GAME_MODULE_PRESET_PATH" == "${DATA_DIR:-/data}/games/"* ]] && tag=" (USER OVERRIDE)"
        pass "preset: ${GAME_MODULE_PRESET_PATH}${tag}"
    else
        fail "no preset resolved for '${GAME_CONFIG}'" "check scripts/games/ or your /data/games/ overlay spelling"
    fi
    if [[ -n "${GAME_MODULE_SETUP_PATH:-}" ]]; then
        local tag=""; [[ "$GAME_MODULE_SETUP_PATH" == "${DATA_DIR:-/data}/games/"* ]] && tag=" (USER OVERRIDE)"
        pass "setup:  ${GAME_MODULE_SETUP_PATH}${tag}"
    else
        warn "no setup.sh for '${GAME_CONFIG}'" "generic launch path will be used"
    fi
}

doctor_environment() {
    section "Environment"
    [[ -n "${STEAM_APP_ID:-}" ]] && pass "STEAM_APP_ID=${STEAM_APP_ID}" || fail "STEAM_APP_ID unset"
    [[ -n "${GAME_EXECUTABLE:-}" ]] && pass "GAME_EXECUTABLE=${GAME_EXECUTABLE}" || fail "GAME_EXECUTABLE unset"
    if env | grep -q '^STEAM_PLATFORM='; then
        fail "STEAM_PLATFORM is set" "this name is reserved by steamcmd.sh itself and breaks it — remove the variable (use USE_LINUX_DEPOT=true for native games)"
    else
        pass "no reserved Steam env names in use"
    fi
}

doctor_files() {
    section "Files"
    local exe="${GAME_DIR:-/data/server}/${GAME_EXECUTABLE:-}"
    if [[ -z "${GAME_EXECUTABLE:-}" ]]; then
        warn "executable check skipped (GAME_EXECUTABLE unset)"
    elif [[ -f "$exe" ]]; then
        local ftype; ftype="$(file -b "$exe" 2>/dev/null | cut -c1-60)"
        pass "executable present: ${exe}"
        [[ -n "$ftype" ]] && pass "type: ${ftype}"
    else
        fail "executable missing: ${exe}" "download incomplete or wrong GAME_EXECUTABLE; for module games this may be installed by game_configure on first start"
    fi
    local manifest
    for manifest in "${GAME_DIR:-/data/server}"/steamapps/appmanifest_*.acf "${GAME_DIR:-/data/server}"/*/steamapps/appmanifest_*.acf; do
        [[ -f "$manifest" ]] || continue
        if grep -q '"StateFlags"[[:space:]]*"6"' "$manifest" 2>/dev/null; then
            fail "manifest stuck at state 0x6: ${manifest}" "delete this file and restart to force re-validation"
        else
            pass "manifest healthy: $(basename "$manifest")"
        fi
    done
}

doctor_proton_wine() {
    section "Proton/Wine"
    local compat="/root/.steam/steam/compatibilitytools.d"
    if [[ -d "$compat" ]] && compgen -G "${compat}/GE-Proton*" >/dev/null; then
        pass "GE-Proton installed: $(basename "$(find "$compat" -maxdepth 1 -type d -name 'GE-Proton*' | sort -V | tail -1)")"
        if [[ -n "${PROTON_VERSION:-}" ]]; then
            [[ -d "${compat}/${PROTON_VERSION}" ]] && pass "pinned ${PROTON_VERSION} present" \
                || fail "PROTON_VERSION=${PROTON_VERSION} not installed" "check the tag at https://github.com/GloriousEggroll/proton-ge-custom/releases"
        fi
    else
        warn "GE-Proton not found" "expected inside the container; native-only games don't need it"
    fi
    local prefix="${STEAM_COMPAT_DATA_PATH:-${DATA_DIR:-/data}/.proton/${PROTON_APP_ID:-${STEAM_APP_ID:-}}}"
    if [[ -f "${prefix}/pfx/system.reg" ]]; then
        pass "Wine prefix initialized: ${prefix}/pfx"
    else
        warn "Wine prefix not initialized yet: ${prefix}/pfx" "created on first Proton start; irrelevant for native games"
    fi
    if [[ -n "${WINETRICKS_VERBS:-}" ]]; then
        local marker="${prefix}/.winetricks_verbs.sha256"
        local want; want="$(printf '%s' "${WINETRICKS_VERBS}" | sha256sum | cut -d' ' -f1)"
        if [[ -f "$marker" && "$(cat "$marker" 2>/dev/null)" == "$want" ]]; then
            pass "winetricks verbs provisioned (${WINETRICKS_VERBS})"
        elif [[ -f "${prefix}/.winetricks_done" ]]; then
            warn "legacy winetricks marker present" "will be adopted to the hash format on next start"
        else
            warn "winetricks verbs not yet provisioned (${WINETRICKS_VERBS})" "runs on next start; several minutes first time"
        fi
    fi
}

doctor_process_network() {
    section "Process/Network"
    if check_game_server 2>/dev/null; then
        pass "server process running (${GAME_EXECUTABLE:-?})"
    else
        warn "server process not running" "normal during startup/diagnosis of a crashed container"
    fi
    if command -v nc >/dev/null 2>&1; then
        local p
        for p in "${GAME_PORT:-}" "${QUERY_PORT:-}"; do
            [[ -z "$p" ]] && continue
            if nc -z -u -w 1 127.0.0.1 "$p" 2>/dev/null || nc -z -w 1 127.0.0.1 "$p" 2>/dev/null; then
                pass "port ${p} responsive"
            else
                warn "port ${p} not responding" "fine if the server is still booting"
            fi
        done
    fi
}

doctor_logs() {
    section "Logs"
    local lf="${DATA_DIR:-/data}/logs/server.log"
    if [[ -f "$lf" ]]; then
        pass "log present: ${lf} ($(wc -l < "$lf") lines)"
        local hits; hits="$(scan_log_signatures "$lf" 200)"
        if [[ -n "$hits" ]]; then
            printf '%s\n' "$hits"
            warn "known failure signatures found in the log tail (hints above)"
        else
            pass "no known failure signatures in the log tail"
        fi
    else
        warn "no server.log yet at ${lf}"
    fi
}

doctor_resources() {
    section "Resources"
    local avail_kb
    avail_kb="$(df -Pk "${DATA_DIR:-/data}" 2>/dev/null | awk 'NR==2{print $4}')"
    if [[ -n "$avail_kb" ]]; then
        local gib=$((avail_kb / 1024 / 1024))
        if   [[ $gib -lt 2  ]]; then fail "only ${gib}GiB free on ${DATA_DIR:-/data}" "game updates will fail; free space"
        elif [[ $gib -lt 10 ]]; then warn "${gib}GiB free on ${DATA_DIR:-/data}" "large game updates may not fit"
        else pass "${gib}GiB free on ${DATA_DIR:-/data}"; fi
    fi
    local mem_avail_kb
    mem_avail_kb="$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null)"
    if [[ -n "$mem_avail_kb" ]]; then
        local mgib=$((mem_avail_kb / 1024 / 1024))
        [[ $mgib -lt 2 ]] && warn "only ${mgib}GiB memory available" "UE servers typically want 8GiB+" \
                          || pass "${mgib}GiB memory available"
    fi
}

main() {
    printf 'steamcmd-proton-server doctor — %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    doctor_image
    doctor_module
    doctor_environment
    doctor_files
    doctor_proton_wine
    doctor_process_network
    doctor_logs
    doctor_resources
    printf '\n'
    case $WORST in
        0) printf 'RESULT: HEALTHY (all checks passed)\n' ;;
        1) printf 'RESULT: WARNINGS (see [WARN] lines above)\n' ;;
        2) printf 'RESULT: PROBLEMS FOUND (see [FAIL] lines above)\n' ;;
    esac
    exit $WORST
}

main "$@"
