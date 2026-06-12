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
        vein)
            generate_vein_config
            ;;
        *)
            log_warn "No specific config generator for: $game"
            generate_generic_config
            ;;
    esac
}

# Vein Configuration
generate_vein_config() {
    log_info "Generating Vein configuration..."

    local config_dir="${DATA_DIR}/config"
    local saves_dir="${DATA_DIR}/saves"
    # Vein runs the native Linux server, so config and saves live under the
    # LinuxServer tree.
    local game_config_dir="${GAME_DIR}/Vein/Saved/Config/LinuxServer"
    local game_ini="${game_config_dir}/Game.ini"
    local bin_dir="${GAME_DIR}/Vein/Binaries/Linux"

    mkdir -p "${config_dir}" "${saves_dir}" "${game_config_dir}"

    # ---- steamclient.so ----
    # The native Linux server needs steamclient.so. Copy a REAL file (not a symlink
    # into /root, which the non-root server user can't traverse) both next to the
    # binary and under the user's HOME (/data/.steam/sdk64, where the Steam SDK
    # looks). These live under /data so the start script's chown makes them readable.
    local steamclient_src=""
    [[ -f /steamcmd/linux64/steamclient.so ]] && steamclient_src="/steamcmd/linux64/steamclient.so"
    [[ -z "$steamclient_src" && -f /root/.steam/sdk64/steamclient.so ]] && steamclient_src="/root/.steam/sdk64/steamclient.so"
    if [[ -n "$steamclient_src" ]]; then
        [[ -d "$bin_dir" ]] && cp -f "$steamclient_src" "${bin_dir}/steamclient.so"
        mkdir -p "${DATA_DIR}/.steam/sdk64"
        cp -f "$steamclient_src" "${DATA_DIR}/.steam/sdk64/steamclient.so"
    fi

    # ---- Game.ini ----
    # Config file lives in /data/config/ for easy access; the game's expected
    # path is a symlink pointing back to it. Migrates any pre-existing game file.
    if [[ -f "${game_ini}" && ! -L "${game_ini}" ]]; then
        if [[ ! -s "${config_dir}/Game.ini" ]]; then
            cp "${game_ini}" "${config_dir}/Game.ini"
            log_info "Migrated Game.ini → ${config_dir}/"
        fi
        rm -f "${game_ini}"
    fi
    [[ -L "${game_ini}" ]] && rm -f "${game_ini}"

    # Generate from environment variables if no config exists yet
    if [[ ! -f "${config_dir}/Game.ini" ]]; then
        local public_val
        case "${VEIN_PUBLIC:-true}" in false|False|FALSE|0|no) public_val="False" ;; *) public_val="True" ;; esac
        local max_players="${MAX_PLAYERS:-16}"; [[ "$max_players" =~ ^[0-9]+$ ]] || max_players=16

        {
            echo "[/Script/Engine.GameSession]"
            echo "MaxPlayers=${max_players}"
            echo ""
            echo "[/Script/Vein.VeinGameSession]"
            echo "bPublic=${public_val}"
            echo "ServerName=${SERVER_NAME:-Vein Server}"
            echo "BindAddr=0.0.0.0"
            echo "HeartbeatInterval=5.0"
            [[ -n "${SERVER_PASSWORD:-}" ]]       && echo "Password=${SERVER_PASSWORD}"
            [[ -n "${VEIN_SUPER_ADMIN_IDS:-}" ]]  && echo "SuperAdminSteamIDs=${VEIN_SUPER_ADMIN_IDS}"
            [[ -n "${VEIN_ADMIN_IDS:-}" ]]        && echo "AdminSteamIDs=${VEIN_ADMIN_IDS}"
            echo ""
            echo "[OnlineSubsystemSteam]"
            echo "GameServerQueryPort=${QUERY_PORT:-27015}"
        } > "${config_dir}/Game.ini"
        log_success "Generated Game.ini"
    else
        log_info "Using existing Game.ini from ${config_dir}/"
    fi

    # Symlink: game config path → /data/config/Game.ini
    ln -sf "${config_dir}/Game.ini" "${game_ini}"

    # ---- SaveGames directory symlink ----
    # Saves live in /data/saves/; the game's SaveGames/ is a symlink to it.
    local game_saves="${GAME_DIR}/Vein/Saved/SaveGames"
    if [[ -d "${game_saves}" && ! -L "${game_saves}" ]]; then
        if [[ -n "$(ls -A "${game_saves}" 2>/dev/null)" ]]; then
            if command -v rsync &>/dev/null; then
                rsync -a "${game_saves}/" "${saves_dir}/"
            else
                cp -r "${game_saves}/." "${saves_dir}/"
            fi
            log_info "Migrated saves → ${saves_dir}/"
        fi
        rm -rf "${game_saves}"
    fi
    [[ -L "${game_saves}" ]] && rm -f "${game_saves}"
    mkdir -p "${GAME_DIR}/Vein/Saved"
    ln -sf "${saves_dir}" "${game_saves}"

    log_info "Config: ${config_dir}/"
    log_info "Saves:  ${saves_dir}/"
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
