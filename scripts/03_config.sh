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
        subnautica-nitrox)
            generate_nitrox_config
            ;;
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

# Configure and install Nitrox for Subnautica
generate_nitrox_config() {
    log_info "========================================="
    log_info "Setting up Nitrox for Subnautica"
    log_info "========================================="

    local game_dir="${GAME_DIR}"
    local subnautica_path="${game_dir}/Subnautica"
    local nitrox_path="${game_dir}/Nitrox"
    local data_path="${DATA_DIR}"
    local nitrox_save_name="${NITROX_SAVE_NAME:-MyServer}"
    local saves_dir="${data_path}/saves"
    local nitrox_save_dir="${saves_dir}/${nitrox_save_name}"
    local nitrox_config_dir="/root/.config/Nitrox"
    local log_dir="${data_path}/logs"

    log_info "Paths:"
    log_info "  Subnautica: ${subnautica_path}"
    log_info "  Nitrox: ${nitrox_path}"
    log_info "  Saves: ${saves_dir}"
    log_info "  Save Name: ${nitrox_save_name}"
    log_info "  Save Dir: ${nitrox_save_dir}"

    # ---- One-time: download + extract the Nitrox server binary ----
    # The binary lives under ${GAME_DIR}/Nitrox, which IS persisted in /data, so
    # we gate the (slow) download on the binary actually being present rather than
    # on a flag file. Everything AFTER this block must run on every start.
    if [[ ! -f "${nitrox_path}/Nitrox.Server.Subnautica" ]]; then
        # .NET 9 runtime is installed in the image (see Dockerfile) — no runtime install here.
        log_info "Downloading Nitrox..."
        mkdir -p "${nitrox_path}"

        local nitrox_url
        nitrox_url=$(curl -s https://api.github.com/repos/SubnauticaNitrox/Nitrox/releases/latest \
            | grep -o 'https://.*linux_x64\.zip' | head -n 1)

        if [[ -z "$nitrox_url" ]]; then
            log_error "Could not fetch Nitrox download URL"
            return 1
        fi

        log_info "Nitrox URL: $nitrox_url"

        local tmpfile="/tmp/$(basename "$nitrox_url")"
        curl -L "$nitrox_url" -o "$tmpfile"

        log_info "Extracting Nitrox..."
        # Nitrox releases now place all files at the zip root (older versions used
        # a linux-x64/ subdirectory). Extract directly into nitrox_path.
        unzip -qo "$tmpfile" -d "${nitrox_path}"
        rm -f "$tmpfile"

        if [[ ! -f "${nitrox_path}/Nitrox.Server.Subnautica" ]]; then
            log_error "Nitrox.Server.Subnautica not found in ${nitrox_path} after extraction"
            log_info "Archive layout may have changed again. Contents:"
            ls -la "${nitrox_path}" >&2
            return 1
        fi

        chmod +x "${nitrox_path}/Nitrox.Server.Subnautica"
        log_success "Nitrox extracted to: ${nitrox_path}"
    else
        log_info "Nitrox binary already present — skipping download"
    fi

    # ---- Every start: (re)build Nitrox config + save routing ----
    # nitrox.cfg and the saves/logs symlinks live under /root/.config/Nitrox,
    # which is NOT in the /data volume. When the container is recreated (Unraid
    # image update / template apply), /root is wiped while /data survives. If this
    # wiring only ran once, Nitrox would lose the route to /data/saves and quietly
    # start a brand-new world in an ephemeral location — overwriting nothing in
    # /data but abandoning the real save. Rebuilding it every start keeps the save
    # anchored in /data regardless of container churn.
    log_info "Wiring Nitrox config and save directories..."
    mkdir -p "${nitrox_config_dir}"

    cat > "${nitrox_config_dir}/nitrox.cfg" << EOF
{
  "PreferredGamePath": "${subnautica_path}",
  "IsMultipleGameInstancesAllowed": true
}
EOF

    # Persistent save/log directories live in /data.
    mkdir -p "${saves_dir}" "${nitrox_save_dir}" "${log_dir}"

    # Create default server.cfg only when absent — never clobber user edits.
    if [[ ! -f "${nitrox_save_dir}/server.cfg" ]]; then
        cat > "${nitrox_save_dir}/server.cfg" << 'EOF'
# Nitrox Server Configuration
# Port settings
ServerPort=11000

# Player settings
MaxConnections=100
ServerPassword=55555
AdminPassword=Chickenpotpie101

# Game settings
GameMode=SURVIVAL
Seed=

# Performance
CreateFullEntityCache=False
SaveInterval=120000
MaxBackups=10

# Player stats defaults
DefaultOxygenValue=45
DefaultMaxOxygenValue=45
DefaultHealthValue=80
DefaultHungerValue=50.5
DefaultThirstValue=90.5
DefaultInfectionValue=0.1

# Network
InitialSyncTimeout=300000
AutoPortForward=False
LANDiscoveryEnabled=True

# Features
DisableConsole=False
DisableAutoSave=False
DisableAutoBackup=False
KeepInventoryOnDeath=False
PvPEnabled=False
SafeBuilding=True

# Permissions
DefaultPlayerPerm=PLAYER
EOF
        log_success "Created server.cfg"
    fi

    # ---- saves symlink: ${nitrox_config_dir}/saves → /data/saves ----
    # If a previous start (running the old, broken setup) let Nitrox create a REAL
    # directory here, its contents are an ephemeral world that would be destroyed by
    # the relink. Stash a copy into /data first so no progress is silently lost.
    if [[ -d "${nitrox_config_dir}/saves" && ! -L "${nitrox_config_dir}/saves" ]]; then
        if [[ -n "$(ls -A "${nitrox_config_dir}/saves" 2>/dev/null)" ]]; then
            local stash="${saves_dir}/.recovered_$(date +%Y%m%d_%H%M%S)"
            mkdir -p "${stash}"
            cp -a "${nitrox_config_dir}/saves/." "${stash}/" 2>/dev/null || true
            log_warn "Found a non-symlinked saves dir at ${nitrox_config_dir}/saves"
            log_warn "Copied its contents to ${stash}/ before relinking — recover manually if needed"
        fi
        rm -rf "${nitrox_config_dir}/saves"
    fi
    [[ -L "${nitrox_config_dir}/saves" ]] && rm -f "${nitrox_config_dir}/saves"
    ln -s "${saves_dir}" "${nitrox_config_dir}/saves"

    # ---- logs symlink: ${nitrox_config_dir}/logs → /data/logs ----
    # Logs are disposable; clear whatever is there and relink.
    rm -rf "${nitrox_config_dir}/logs" 2>/dev/null || true
    ln -s "${log_dir}" "${nitrox_config_dir}/logs"

    mkdir -p "${nitrox_config_dir}/cache"

    # Set environment for Nitrox
    export SUBNAUTICA_INSTALLATION_PATH="${subnautica_path}"

    # Diagnostic markers only — the wiring above no longer gates on these.
    touch "${data_path}/.nitrox_initialized"
    echo "nitrox" > "${data_path}/.mod_type"

    log_success "========================================="
    log_info "Nitrox ready"
    log_info "Save directory: ${nitrox_save_dir}"
    log_info "Config: ${nitrox_save_dir}/server.cfg"
    log_info "========================================="
}

#######################################
# MAIN
#######################################

log_info "[03] Generating server configuration..."

# Note: ${DATA_DIR}/config is created by the individual config generators that
# actually use it. Presets that store config elsewhere (e.g. Nitrox, which uses
# ${DATA_DIR}/saves/<name>/server.cfg) no longer get a stray empty config dir.

# Check for game-specific config generator
if declare -f game_configure >/dev/null; then
    game_configure
elif [[ -n "${GAME_CONFIG:-}" ]]; then
    generate_game_config "${GAME_CONFIG}"   # legacy dispatch — shrinks per migration
else
    generate_generic_config
fi

log_success "[03] Configuration generated"
