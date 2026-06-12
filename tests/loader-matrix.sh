#!/bin/bash
# Module-loader resolution matrix. Builds fake script/data roots and asserts
# resolution order, override behavior, reserved names, fail-loud syntax errors,
# and function availability in a Docker-healthcheck-like exec context.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }

mk_module() { # <root> <name> <preset-marker> [with-setup]
    mkdir -p "$1/games/$2"
    printf 'export MODSRC=%s\n' "$3" > "$1/games/$2/preset.conf"
    [[ "${4:-}" == "with-setup" ]] && printf 'game_configure() { echo HOOK-%s; }\n' "$3" > "$1/games/$2/setup.sh"
    return 0
}
run_loader() { # <script_dir> <data_dir> <game> — prints MODSRC + hook marker
    env -i bash -c "
        PATH=/usr/bin:/bin
        SCRIPT_DIR='$1' DATA_DIR='$2' GAME_CONFIG='$3' DEBUG=false
        source '${REPO_ROOT}/scripts/functions.sh' 2>/dev/null
        load_game_module >/dev/null 2>&1 || exit 9
        echo \"src=\${MODSRC:-none}\"
        declare -f game_configure >/dev/null && game_configure || echo HOOK-none
    "
}

S="$T/scripts"; D="$T/data"; mkdir -p "$S/presets" "$D"

mk_module "$S" demo baked with-setup
out="$(run_loader "$S" "$D" demo)"
check "baked module resolves (preset+setup)" '[[ "$out" == *"src=baked"* && "$out" == *"HOOK-baked"* ]]'

mk_module "$D" demo overlay
out="$(run_loader "$S" "$D" demo)"
check "overlay preset wins, baked setup retained" '[[ "$out" == *"src=overlay"* && "$out" == *"HOOK-baked"* ]]'

mk_module "$D" newgame datanew with-setup
out="$(run_loader "$S" "$D" newgame)"
check "brand-new /data game loads" '[[ "$out" == *"src=datanew"* && "$out" == *"HOOK-datanew"* ]]'

printf 'export MODSRC=legacy\n' > "$S/presets/oldgame.conf"
out="$(run_loader "$S" "$D" oldgame)"
check "legacy presets/ fallback" '[[ "$out" == *"src=legacy"* ]]'

mkdir -p "$D/games/broken"; printf 'this is ( not bash\n' > "$D/games/broken/setup.sh"
rc=0
# shellcheck disable=SC2034  # consumed via eval in check()
run_loader "$S" "$D" broken >/dev/null 2>&1 || rc=$?
check "broken overlay aborts (nonzero exit)" '[[ $rc -ne 0 ]]'

# shellcheck disable=SC2034  # consumed via eval in check()
out="$(run_loader "$S" "$D" _template)"
check "_-prefixed names reserved → generic" '[[ "$out" == *"src=none"* && "$out" == *"HOOK-none"* ]]'

echo "MATRIX $( [[ $fail -eq 0 ]] && echo PASS || echo FAIL ) (${pass}/6)"
[[ $fail -eq 0 ]]
