#!/bin/bash
# Configuration generation script
# Creates and manages game server configuration files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"
load_game_module

#######################################
# GAME-SPECIFIC CONFIG GENERATORS
#######################################

generate_game_config() {
    local game="$1"

    case "$game" in
        *)
            log_warn "No specific config generator for: $game"
            generate_generic_config
            ;;
    esac
}

#######################################
# GENERIC CONFIG GENERATOR
#######################################

generate_generic_config() {
    log_info "Generating generic server configuration..."

    local config_dir="${DATA_DIR}/config"
    mkdir -p "$config_dir"

    # Create basic server.properties template
    cat > "${config_dir}/server.properties" << EOF
# Generic Server Configuration
# Generated on $(date)

# Server Identification
server-name=${SERVER_NAME:-Dedicated Server}
server-port=${GAME_PORT:-7777}
query-port=${QUERY_PORT:-7778}

# Authentication
server-password=${SERVER_PASSWORD:-}
rcon-port=${RCON_PORT:-27015}
rcon-password=${RCON_PASSWORD:-}

# Gameplay
max-players=${MAX_PLAYERS:-10}
world-name=${WORLD_NAME:-world}
game-mode=${GAME_MODE:-survival}

# Network
max-connections=20
connection-throttle=0
network-compression-threshold=256
EOF

    log_success "Generic configuration created"
}

#######################################
# MAIN
#######################################

log_info "[03] Generating server configuration..."

# Note: ${DATA_DIR}/config is created by the individual config generators that
# actually use it. Presets that store config elsewhere (e.g. modules with custom
# save routing) no longer get a stray empty config dir.

# Check for game-specific config generator
if declare -f game_configure >/dev/null; then
    game_configure
elif [[ -n "${GAME_CONFIG:-}" ]]; then
    generate_game_config "${GAME_CONFIG}"   # legacy dispatch — shrinks per migration
else
    generate_generic_config
fi

log_success "[03] Configuration generated"
