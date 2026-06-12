#!/bin/bash
# Re-runs the CURRENT checkout per game/scenario and diffs against tests/golden/.
# Usage: compare-golden.sh [game ...]
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-golden.sh"

games=("$@"); [[ ${#games[@]} -eq 0 ]] && games=("${ALL_GAMES[@]}")
pass=0; fail=0; total=0
for g in "${games[@]}"; do
    for s in $(scenarios_for "$g"); do
        total=$((total+1))
        gold="${GOLDEN_DIR}/${g}/${s}"
        if [[ -f "${gold}/SKIPPED_NO_NS" ]]; then echo "SKIP ${g}/${s} (no golden)"; continue; fi
        cur="$(mktemp -d)"
        golden_run "$g" "$s" "$cur"
        if diff -ru "$gold" "$cur" > /tmp/golden.diff 2>&1; then
            echo "PASS ${g}/${s}"; pass=$((pass+1))
        else
            echo "FAIL ${g}/${s}:"; head -40 /tmp/golden.diff; fail=$((fail+1))
        fi
        rm -rf "$cur"
    done
done
echo "GOLDEN $( [[ $fail -eq 0 ]] && echo PASS || echo FAIL ): ${pass}/${total} scenarios identical"
[[ $fail -eq 0 ]]
