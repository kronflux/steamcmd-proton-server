#!/bin/bash
# Shared library for the golden-snapshot harness.
# Runs scripts/03_config.sh for one game in a throwaway sandbox and snapshots
# the resulting filesystem (tree, symlink targets, generated file content) plus
# the launch-args string. Used by capture-golden.sh and compare-golden.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN_DIR="${REPO_ROOT}/tests/golden"
source "${REPO_ROOT}/tests/lib-legacy-args.sh"

ALL_GAMES=(valheim dayz starrupture scum sons-of-the-forest sons-of-the-forest-modded vein subnautica-nitrox)
# Games whose config generators have migrate-existing-files branches → extra "seeded" scenario.
SEEDED_GAMES=(sons-of-the-forest starrupture vein scum subnautica-nitrox)
# Proton games have an args golden; native games record a sentinel.
PROTON_GAMES=(sons-of-the-forest sons-of-the-forest-modded valheim dayz starrupture scum)

is_in() { local x="$1"; shift; local i; for i in "$@"; do [[ "$i" == "$x" ]] && return 0; done; return 1; }
needs_root_ns() { [[ "$1" == "subnautica-nitrox" ]]; }

# Resolve the game's preset wherever the current checkout keeps it.
preset_path_for() {
    local g="$1"
    if   [[ -f "${REPO_ROOT}/scripts/games/${g}/preset.conf" ]]; then echo "${REPO_ROOT}/scripts/games/${g}/preset.conf"
    elif [[ -f "${REPO_ROOT}/scripts/presets/${g}.conf"      ]]; then echo "${REPO_ROOT}/scripts/presets/${g}.conf"
    else echo ""; fi   # subnautica has no preset pre-migration — env-only
}

module_setup_for() {
    local g="$1"
    [[ -f "${REPO_ROOT}/scripts/games/${g}/setup.sh" ]] && echo "${REPO_ROOT}/scripts/games/${g}/setup.sh" || echo ""
}

# Pre-create files that keep generators deterministic and offline.
stub_sandbox() {
    local g="$1" data="$2" game="$3"
    case "$g" in
        subnautica-nitrox)
            mkdir -p "${game}/Nitrox"
            printf 'stub-binary' > "${game}/Nitrox/Nitrox.Server.Subnautica"   # skips the GitHub download branch
            ;;
    esac
}

# Seed pre-existing real files to exercise every migrate-and-symlink branch.
seed_sandbox() {
    local g="$1" data="$2" game="$3"
    case "$g" in
        sons-of-the-forest)
            local wad="${data}/.proton/2465200/pfx/drive_c/users/steamuser/AppData/LocalLow/Endnight/SonsOfTheForestDS"
            mkdir -p "${wad}/Saves/slot1"
            printf '{"GamePort":1234}'  > "${wad}/dedicatedserver.cfg"
            printf '7656119SEEDED\n'    > "${wad}/ownerswhitelist.txt"
            printf '{}'                 > "${wad}/SonsGameSettings.cfg"
            printf 'seed'               > "${wad}/Saves/slot1/save.dat"
            ;;
        starrupture)
            mkdir -p "${game}/StarRupture/Saved/SaveGames"
            printf '{"SessionName":"Seeded"}\n' > "${game}/DSSettings.txt"
            printf 'seed' > "${game}/StarRupture/Saved/SaveGames/auto.sav"
            ;;
        vein)
            mkdir -p "${game}/Vein/Saved/Config/LinuxServer" "${game}/Vein/Saved/SaveGames"
            printf '[Seeded]\nServerName=Seeded\n' > "${game}/Vein/Saved/Config/LinuxServer/Game.ini"
            printf 'seed' > "${game}/Vein/Saved/SaveGames/world.sav"
            ;;
        scum)
            mkdir -p "${game}/SCUM/Saved/Config/WindowsServer" "${game}/SCUM/Saved/SaveFiles"
            printf '[Scum.ServerSettings]\n' > "${game}/SCUM/Saved/Config/WindowsServer/ServerSettings.ini"
            printf 'seed' > "${game}/SCUM/Saved/SaveFiles/SCUM.db"
            ;;
        subnautica-nitrox)
            # Inside the unshare namespace /root is tmpfs — exercise the stash guard.
            mkdir -p /root/.config/Nitrox/saves/OldWorld
            printf 'seed' > /root/.config/Nitrox/saves/OldWorld/world.dat
            ;;
    esac
}

normalize_stream() {
    local data="$1" game="$2"
    sed -e "s|${data}|@DATA@|g" \
        -e "s|${game}|@GAME@|g" \
        -e 's|/root/\.config/Nitrox|@NITROXCFG@|g' \
        -e 's|\.recovered_[0-9_]\{1,\}|.recovered_@TS@|g' \
        -e '/Generated on /d'
}

run_config() {
    local g="$1" data="$2" game="$3"
    local preset; preset="$(preset_path_for "$g")"
    (
        export GAME_CONFIG="$g" DATA_DIR="$data" GAME_DIR="$game" INSTALL_REDLOADER=false
        # shellcheck disable=SC1090
        [[ -n "$preset" ]] && source "$preset"
        bash "${REPO_ROOT}/scripts/03_config.sh"
    ) >/dev/null 2>&1
}

snapshot() {
    local g="$1" data="$2" game="$3" out="$4"
    local extra=""; needs_root_ns "$g" && extra="/root/.config/Nitrox"
    mkdir -p "$out"
    { for root in "$data" "$game" $extra; do
          [[ -d "$root" ]] && find "$root" -mindepth 1 \( -type f -o -type d -o -type l \) -printf '%y %p\n'
      done; } 2>/dev/null | normalize_stream "$data" "$game" | sort > "${out}/tree.txt"
    { for root in "$data" "$game" $extra; do
          [[ -d "$root" ]] && find "$root" -type l -printf '%p -> %l\n'
      done; } 2>/dev/null | normalize_stream "$data" "$game" | sort > "${out}/links.txt"
    { for root in "$data" $extra; do
          [[ -d "$root" ]] || continue
          find "$root" \( -path '*/.proton' -prune \) -o -type f -print 2>/dev/null | sort | \
          while IFS= read -r f; do printf '=== %s ===\n' "$f"; cat "$f"; printf '\n'; done
      done; } | normalize_stream "$data" "$game" > "${out}/content.txt"
}

capture_args() {
    local g="$1" out="$2"
    if ! is_in "$g" "${PROTON_GAMES[@]}"; then
        echo "(native — launch owned by game_start)" > "${out}/args.txt"; return 0
    fi
    local preset; preset="$(preset_path_for "$g")"
    local setup;  setup="$(module_setup_for "$g")"
    (
        export GAME_CONFIG="$g"
        # shellcheck disable=SC1090
        [[ -n "$preset" ]] && source "$preset"
        # shellcheck disable=SC1090
        [[ -n "$setup" ]] && source "$setup"
        if declare -f game_args >/dev/null; then game_args; else legacy_base_args "$g"; fi
    ) > "${out}/args.txt"
}

# Runs one (game, scenario) into $out. Re-execs itself inside unshare for nitrox.
golden_run() {
    local g="$1" scenario="$2" out="$3"
    if needs_root_ns "$g" && [[ "${GOLDEN_INNER:-}" != "1" ]]; then
        if unshare -rm true 2>/dev/null; then
            GOLDEN_INNER=1 unshare -rm bash -c \
                'mount -t tmpfs none /root && source "$1" && golden_run "$2" "$3" "$4"' _ \
                "${BASH_SOURCE[0]}" "$g" "$scenario" "$out"
            return $?
        fi
        mkdir -p "$out"; echo "no user-namespace support on this host" > "${out}/SKIPPED_NO_NS"
        echo "WARN: ${g}/${scenario} golden SKIPPED (no unshare -rm)" >&2
        return 0
    fi
    local sandbox; sandbox="$(mktemp -d)"
    local data="${sandbox}/data" game="${sandbox}/game"
    mkdir -p "$data" "$game"
    stub_sandbox "$g" "$data" "$game"
    [[ "$scenario" == "seeded" ]] && seed_sandbox "$g" "$data" "$game"
    run_config "$g" "$data" "$game"
    snapshot  "$g" "$data" "$game" "$out"
    capture_args "$g" "$out"
    rm -rf "$sandbox"
}

scenarios_for() {
    local g="$1"
    echo fresh
    is_in "$g" "${SEEDED_GAMES[@]}" && echo seeded
    return 0
}
