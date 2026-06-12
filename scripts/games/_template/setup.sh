#!/bin/bash
# <Game Name> module — hook functions sourced by load_game_module().
# Every hook is OPTIONAL: delete the ones you don't need. functions.sh helpers
# (log_*, persist_dir, persist_file) and all preset env vars are available.

# Generate/wire config and saves. Use persist_file/persist_dir to keep real
# files in /data and symlink them into the game tree (idempotent).
# game_configure() {
#     local config_dir="${DATA_DIR}/config"
#     mkdir -p "${config_dir}"
#     persist_file "${GAME_DIR}/server.cfg" "${config_dir}/server.cfg"
#     if [[ ! -f "${config_dir}/server.cfg" ]]; then
#         printf 'name=%s\n' "${SERVER_NAME}" > "${config_dir}/server.cfg"
#     fi
#     persist_dir "${GAME_DIR}/Saved/SaveGames" "${DATA_DIR}/saves"
# }

# Echo the launch arguments (Proton games). The framework appends GAME_ARGS.
# game_args() { echo "-log -port=${GAME_PORT:-7777}"; }

# FULL launch override for native-Linux servers (owns lifecycle + exit code).
# Copy the shape from scripts/games/vein/setup.sh (non-root) or
# scripts/games/subnautica-nitrox/setup.sh.
# game_start() { ...; }

# Liveness probe for the container healthcheck (warn-only semantics).
# game_healthcheck() {
#     local query_port="${QUERY_PORT:-27015}"
#     if command -v nc &> /dev/null; then
#         nc -z -u -w 2 127.0.0.1 "$query_port" 2>/dev/null \
#             && log_debug "Health check: query port responsive" \
#             || log_warn  "Health check: query port not responding"
#     fi
# }

# Prove the SteamCMD download succeeded when GAME_EXECUTABLE alone can't.
# game_verify_install() { [[ -d "${GAME_DIR}/Content" ]]; }
