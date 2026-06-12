#!/bin/bash
# DayZ module — hook functions sourced by load_game_module().

game_configure() { generate_dayz_config; }

game_args() { echo "-config=server.cfg -port=${GAME_PORT:-2302}"; }

# --- moved verbatim from scripts/03_config.sh ---

# DayZ Configuration
generate_dayz_config() {
    log_info "Generating DayZ configuration..."

    local config_dir="${DATA_DIR}/config"
    local server_cfg="${config_dir}/server.cfg"
    mkdir -p "$config_dir"

    cat > "$server_cfg" << EOF
// DayZ Server Configuration
// Generated on $(date)

hostname = "${SERVER_NAME:-DayZ Docker Server}";
password = "${SERVER_PASSWORD:-}";
passwordAdmin = "${ADMIN_PASSWORD:-}";
maxPlayers = ${MAX_PLAYERS:-60};
verifySignatures = 2;
forceSameBuild = 1;
disableVoN = 0;
vonCodecQuality = 20;
enableDebugMonitor = 0;
 BattlEyeSecure = 1;
 BattlEyeNetwork = 1;
disable3rdPerson = 0;
disableCrosshair = 0;
serverTime="SystemTime";
serverTimeAcceleration = 1;
serverNightTimeAcceleration = 1;
serverTimePersistent = 0;
guaranteedUpdates = 1;
loginQueueCoalesce = 1;
instanceId = 1;
storeHouseStateDisabled = 0;
storageAutoFix = 1;
EOF

    log_success "DayZ configuration created"
}
