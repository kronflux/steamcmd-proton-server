#!/bin/bash
# Valheim module — hook functions sourced by load_game_module().

game_configure() { generate_valheim_config; }

game_args() {
    echo "-batchmode -nographics -port ${GAME_PORT:-2456} -name \"${SERVER_NAME}\" -password \"${SERVER_PASSWORD:-}\" -world \"${WORLD_NAME:-Dedicated}\" -public 1"
}

game_healthcheck() {
    local game_port="${GAME_PORT:-2456}"
    if command -v nc &> /dev/null; then
        if nc -z -u -w 2 127.0.0.1 "$game_port" 2>/dev/null; then
            log_debug "Health check: Valheim port responsive"
        else
            log_warn "Health check: Valheim port not responding"
        fi
    fi
}

# --- moved verbatim from scripts/03_config.sh ---

# Valheim Configuration
generate_valheim_config() {
    log_info "Generating Valheim configuration..."

    local config_dir="${DATA_DIR}/config"
    local save_dir="${DATA_DIR}/savefiles"

    mkdir -p "$config_dir" "$save_dir"

    cat > "${config_dir}/adminlist.txt" << EOF
# Admin list - one SteamID per line
EOF

    cat > "${config_dir}/bannedlist.txt" << EOF
# Banned players - one SteamID per line
EOF

    cat > "${config_dir}/permittedlist.txt" << EOF
# Permitted players - one SteamID per line
EOF

    # Valheim uses start parameters, not config files
    export VALHEIM_SERVER_NAME="${SERVER_NAME:-Valheim Docker Server}"
    export VALHEIM_SERVER_PASSWORD="${SERVER_PASSWORD:-}"
    export VALHEIM_SERVER_PORT="${GAME_PORT:-2456}"
    export VALHEIM_WORLD_NAME="${WORLD_NAME:-Dedicated}"

    log_success "Valheim configuration created"
}
