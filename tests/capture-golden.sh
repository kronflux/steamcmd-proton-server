#!/bin/bash
# Captures golden baselines into tests/golden/<game>/<scenario>/.
# Usage: capture-golden.sh [game ...] | --self-check
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-golden.sh"

capture_to() {
    local dest_root="$1"; shift
    local games=("$@"); [[ ${#games[@]} -eq 0 ]] && games=("${ALL_GAMES[@]}")
    local g s
    for g in "${games[@]}"; do
        for s in $(scenarios_for "$g"); do
            echo "capturing ${g}/${s}..."
            golden_run "$g" "$s" "${dest_root}/${g}/${s}"
        done
    done
}

if [[ "${1:-}" == "--self-check" ]]; then
    a="$(mktemp -d)"; b="$(mktemp -d)"
    capture_to "$a" >/dev/null
    capture_to "$b" >/dev/null
    if diff -r "$a" "$b" >/dev/null; then
        echo "SELF-CHECK PASS: two captures identical"; rm -rf "$a" "$b"; exit 0
    else
        echo "SELF-CHECK FAIL: captures differ:"; diff -r "$a" "$b" | head -40; rm -rf "$a" "$b"; exit 1
    fi
fi

capture_to "$GOLDEN_DIR" "$@"
echo "goldens written to ${GOLDEN_DIR}"
