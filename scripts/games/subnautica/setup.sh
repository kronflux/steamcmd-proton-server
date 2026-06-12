#!/bin/bash
# Subnautica module — hook functions sourced by load_game_module().

game_configure() { generate_subnautica_config; }

game_args() { echo "-batchmode -nographics"; }

# --- moved verbatim from scripts/03_config.sh ---

# Subnautica Configuration
generate_subnautica_config() {
    log_info "Generating Subnautica configuration..."

    local config_dir="${DATA_DIR}/config"
    mkdir -p "$config_dir"

    cat > "${config_dir}/serverconfig.ini" << EOF
[Subnautica]
ServerName=${SERVER_NAME:-Subnautica Docker Server}
ServerPassword=${SERVER_PASSWORD:-}
MaxPlayers=${MAX_PLAYERS:-100}
GamePort=${GAME_PORT:-7777}
QueryPort=${QUERY_PORT:-7778}
EOF

    log_success "Subnautica configuration created"
}
