#!/bin/bash
# SCUM module — hook functions sourced by load_game_module().

game_configure() { generate_scum_config; }

game_args() {
    # SCUM derives its query/raw ports from -port (game+2 / game+1).
    local a="-log -port=${GAME_PORT:-7777} -MaxPlayers=${MAX_PLAYERS:-64}"
    if [[ "${SCUM_DISABLE_BATTLEYE:-false}" == "true" ]]; then
        a="${a} -nobattleye"
    fi
    echo "$a"
}

game_healthcheck() {
    local query_port="${QUERY_PORT:-7779}"
    # SCUM's query / connect port is TCP (game port + 2).
    if command -v nc &> /dev/null; then
        if nc -z -w 2 127.0.0.1 "$query_port" 2>/dev/null; then
            log_debug "Health check: SCUM query port responsive"
        else
            log_warn "Health check: SCUM query port not responding"
        fi
    fi
}

# --- moved from scripts/03_config.sh (persist-helper refactor applied) ---

# SCUM Configuration
generate_scum_config() {
    log_info "Generating SCUM configuration..."

    local config_dir="${DATA_DIR}/config"
    local saves_dir="${DATA_DIR}/saves"
    # SCUM (Windows server via Proton) writes config under SCUM/Saved/Config/WindowsServer/
    # and saves under SCUM/Saved/SaveFiles/.
    local game_config="${GAME_DIR}/SCUM/Saved/Config/WindowsServer"
    local game_saves="${GAME_DIR}/SCUM/Saved/SaveFiles"

    mkdir -p "${config_dir}" "${saves_dir}"

    # ---- Config directory (ServerSettings.ini etc.) ----
    persist_dir "${game_config}" "${config_dir}"

    # ---- SaveFiles directory ----
    persist_dir "${game_saves}" "${saves_dir}"

    log_info "Config: ${config_dir}/ (edit ServerSettings.ini after first run)"
    log_info "Saves:  ${saves_dir}/"
}
