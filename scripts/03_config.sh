#!/bin/bash
# Configuration generation script
# Creates and manages game server configuration files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

#######################################
# GAME-SPECIFIC CONFIG GENERATORS
#######################################

generate_game_config() {
    local game="$1"

    case "$game" in
        sons-of-the-forest)
            generate_sotf_config
            install_redloader
            ;;
        sons-of-the-forest-modded)
            generate_sotf_config
            install_redloader
            ;;
        valheim)
            generate_valheim_config
            ;;
        subnautica)
            generate_subnautica_config
            ;;
        subnautica-nitrox)
            generate_nitrox_config
            ;;
        dayz)
            generate_dayz_config
            ;;
        *)
            log_warn "No specific config generator for: $game"
            generate_generic_config
            ;;
    esac
}

# Sons of the Forest Configuration
generate_sotf_config() {
    log_info "Generating Sons of the Forest configuration..."

    local proton_app_id="${PROTON_APP_ID:-${STEAM_APP_ID}}"
    local prefix_base="${DATA_DIR}/.proton/${proton_app_id}"
    local wine_appdata="${prefix_base}/pfx/drive_c/users/steamuser/AppData/LocalLow/Endnight/SonsOfTheForestDS"
    local data_cfg_dir="${DATA_DIR}/config"
    local data_saves_dir="${DATA_DIR}/saves"

    # Create user-visible directories under /data
    mkdir -p "${data_cfg_dir}" "${data_saves_dir}" "${wine_appdata}"

    # ---- Config file symlinks ----
    # Files live in /data/config/ for easy access.
    # Wine prefix path contains symlinks pointing back to /data/config/.
    # Migrates any pre-existing Wine prefix files to /data/config/ on upgrade.
    for cfg_file in dedicatedserver.cfg ownerswhitelist.txt SonsGameSettings.cfg; do
        local wine_file="${wine_appdata}/${cfg_file}"
        local data_file="${data_cfg_dir}/${cfg_file}"
        # Migrate existing real file from Wine prefix to data dir
        if [[ -f "${wine_file}" && ! -L "${wine_file}" ]]; then
            if [[ ! -s "${data_file}" ]]; then
                cp "${wine_file}" "${data_file}"
                log_info "Migrated ${cfg_file} → ${data_cfg_dir}/"
            fi
            rm -f "${wine_file}"
        fi
        # Ensure target file exists
        [[ -f "${data_file}" ]] || touch "${data_file}"
        # Symlink: wine_appdata/file → /data/config/file
        ln -sf "${data_file}" "${wine_file}"
    done

    # ---- Saves directory symlink ----
    # Saves live in /data/saves/; Wine prefix Saves/ is a symlink to it.
    local wine_saves="${wine_appdata}/Saves"
    if [[ -d "${wine_saves}" && ! -L "${wine_saves}" ]]; then
        # Migrate existing saves
        if [[ -n "$(ls -A "${wine_saves}" 2>/dev/null)" ]]; then
            if command -v rsync &>/dev/null; then
                rsync -a "${wine_saves}/" "${data_saves_dir}/"
            else
                cp -r "${wine_saves}/." "${data_saves_dir}/"
            fi
            log_info "Migrated saves → ${data_saves_dir}/"
        fi
        rm -rf "${wine_saves}"
    fi
    [[ -L "${wine_saves}" ]] && rm -f "${wine_saves}"
    ln -sf "${data_saves_dir}" "${wine_saves}"

    # ---- dedicatedserver.cfg ----
    # Strategy: if the file is missing or invalid JSON, create it fresh with all defaults.
    # If it already exists, update only the env-var-controlled fields via jq — all other
    # fields (GameSettings, CustomGameModeSettings, any game-written fields) are preserved.
    local cfg="${data_cfg_dir}/dedicatedserver.cfg"
    local cfg_tmp="${cfg}.tmp"

    if [[ ! -s "$cfg" ]] || ! jq -e . "$cfg" > /dev/null 2>&1; then
        log_info "Creating dedicatedserver.cfg..."
        # Seed with an empty object; the jq update below fills in all fields.
        echo '{}' > "$cfg"
    fi

    # Normalise boolean env vars to valid JSON literals
    local lan_only_val
    case "${SOTF_LAN_ONLY:-false}" in true|True|TRUE|1|yes) lan_only_val="true" ;; *) lan_only_val="false" ;; esac
    local log_files_val
    case "${SOTF_LOG_FILES:-true}" in false|False|FALSE|0|no) log_files_val="false" ;; *) log_files_val="true" ;; esac
    local ts_filenames_val
    case "${SOTF_TIMESTAMP_FILENAMES:-true}" in false|False|FALSE|0|no) ts_filenames_val="false" ;; *) ts_filenames_val="true" ;; esac
    local ts_entries_val
    case "${SOTF_TIMESTAMP_ENTRIES:-true}" in false|False|FALSE|0|no) ts_entries_val="false" ;; *) ts_entries_val="true" ;; esac

    # Normalise numeric env vars (guard against non-integer values)
    local game_port="${GAME_PORT:-8766}";         [[ "$game_port"    =~ ^[0-9]+$ ]] || game_port=8766
    local query_port="${QUERY_PORT:-27016}";      [[ "$query_port"   =~ ^[0-9]+$ ]] || query_port=27016
    local blob_port="${BLOBSYNC_PORT:-9700}";     [[ "$blob_port"    =~ ^[0-9]+$ ]] || blob_port=9700
    local max_players="${MAX_PLAYERS:-8}";        [[ "$max_players"  =~ ^[0-9]+$ ]] || max_players=8
    local save_slot="${SAVE_SLOT:-1}";            [[ "$save_slot"    =~ ^[0-9]+$ ]] || save_slot=1
    local save_interval="${SOTF_SAVE_INTERVAL:-600}"; [[ "$save_interval" =~ ^[0-9]+$ ]] || save_interval=600
    local idle_day="${SOTF_IDLE_DAY_CYCLE_SPEED:-0.0}"; [[ "$idle_day" =~ ^[0-9]+\.?[0-9]*$ ]] || idle_day="0.0"
    local idle_fps="${SOTF_IDLE_TARGET_FPS:-5}";  [[ "$idle_fps"  =~ ^[0-9]+$ ]] || idle_fps=5
    local active_fps="${SOTF_ACTIVE_TARGET_FPS:-60}"; [[ "$active_fps" =~ ^[0-9]+$ ]] || active_fps=60

    # Update env-var-controlled fields; all other fields (GameSettings, etc.) are untouched.
    # .GameSettings //= {} and .CustomGameModeSettings //= {} seed the fields on first creation
    # without overwriting values the user (or game) has already set.
    jq \
        --arg     IpAddress             "0.0.0.0" \
        --argjson GamePort              "$game_port" \
        --argjson QueryPort             "$query_port" \
        --argjson BlobSyncPort          "$blob_port" \
        --arg     ServerName            "${SERVER_NAME:-Sons Of The Forest Server}" \
        --argjson MaxPlayers            "$max_players" \
        --arg     Password              "${SERVER_PASSWORD:-}" \
        --argjson LanOnly               "$lan_only_val" \
        --argjson SaveSlot              "$save_slot" \
        --arg     SaveMode              "${SOTF_SAVE_MODE:-Continue}" \
        --arg     GameMode              "${SOTF_GAME_MODE:-Normal}" \
        --argjson SaveInterval          "$save_interval" \
        --argjson IdleDayCycleSpeed     "$idle_day" \
        --argjson IdleTargetFramerate   "$idle_fps" \
        --argjson ActiveTargetFramerate "$active_fps" \
        --argjson LogFilesEnabled       "$log_files_val" \
        --argjson TimestampLogFilenames "$ts_filenames_val" \
        --argjson TimestampLogEntries   "$ts_entries_val" \
        '
        .IpAddress              = $IpAddress |
        .GamePort               = $GamePort |
        .QueryPort              = $QueryPort |
        .BlobSyncPort           = $BlobSyncPort |
        .ServerName             = $ServerName |
        .MaxPlayers             = $MaxPlayers |
        .Password               = $Password |
        .LanOnly                = $LanOnly |
        .SaveSlot               = $SaveSlot |
        .SaveMode               = $SaveMode |
        .GameMode               = $GameMode |
        .SaveInterval           = $SaveInterval |
        .IdleDayCycleSpeed      = $IdleDayCycleSpeed |
        .IdleTargetFramerate    = $IdleTargetFramerate |
        .ActiveTargetFramerate  = $ActiveTargetFramerate |
        .LogFilesEnabled        = $LogFilesEnabled |
        .TimestampLogFilenames  = $TimestampLogFilenames |
        .TimestampLogEntries    = $TimestampLogEntries |
        .SkipNetworkAccessibilityTest = true |
        .GameSettings //= {} |
        .CustomGameModeSettings //= {}
        ' \
        "$cfg" > "$cfg_tmp" && mv "$cfg_tmp" "$cfg"

    # Override GameSettings/CustomGameModeSettings only if the env var is explicitly
    # set to something non-trivial (i.e. not the bare default "{}").
    if [[ -n "${SOTF_GAME_SETTINGS:-}" ]] && [[ "${SOTF_GAME_SETTINGS}" != "{}" ]]; then
        jq --argjson gs "${SOTF_GAME_SETTINGS}" '.GameSettings = $gs' \
            "$cfg" > "$cfg_tmp" && mv "$cfg_tmp" "$cfg"
        log_info "GameSettings applied from SOTF_GAME_SETTINGS"
    fi
    if [[ -n "${SOTF_CUSTOM_GAME_SETTINGS:-}" ]] && [[ "${SOTF_CUSTOM_GAME_SETTINGS}" != "{}" ]]; then
        jq --argjson cgs "${SOTF_CUSTOM_GAME_SETTINGS}" '.CustomGameModeSettings = $cgs' \
            "$cfg" > "$cfg_tmp" && mv "$cfg_tmp" "$cfg"
        log_info "CustomGameModeSettings applied from SOTF_CUSTOM_GAME_SETTINGS"
    fi

    if [[ -n "${SERVER_PASSWORD:-}" ]]; then
        log_success "dedicatedserver.cfg updated (password set)"
    else
        log_success "dedicatedserver.cfg updated (no password — public server)"
    fi

    # ---- ownerswhitelist.txt ----
    # Pre-create to prevent self-test restart request. Populate from env var if provided.
    if [[ ! -s "${data_cfg_dir}/ownerswhitelist.txt" ]]; then
        if [[ -n "${SOTF_OWNER_STEAM_IDS:-}" ]]; then
            echo "${SOTF_OWNER_STEAM_IDS}" | tr ',' '\n' | sed 's/^ *//;s/ *$//' \
                > "${data_cfg_dir}/ownerswhitelist.txt"
            log_info "Populated ownerswhitelist.txt from SOTF_OWNER_STEAM_IDS"
        else
            : > "${data_cfg_dir}/ownerswhitelist.txt"
            log_info "Created empty ownerswhitelist.txt"
        fi
    fi

    # ---- SonsGameSettings.cfg ----
    # Pre-create as empty JSON object to prevent self-test restart request.
    if [[ ! -s "${data_cfg_dir}/SonsGameSettings.cfg" ]]; then
        echo '{}' > "${data_cfg_dir}/SonsGameSettings.cfg"
        log_info "Created empty SonsGameSettings.cfg"
    fi

    # ---- steam_appid.txt ----
    # The server expects the game client app ID (1326470), not the dedicated server app ID.
    mkdir -p "${GAME_DIR}"
    if [[ ! -f "${GAME_DIR}/steam_appid.txt" ]]; then
        echo "1326470" > "${GAME_DIR}/steam_appid.txt"
        log_info "Created steam_appid.txt (1326470)"
    fi

    # ---- boot.config patch ----
    # Disable GPU job threads — requires real GPU hardware, causes crashes in server mode.
    local boot_cfg="${GAME_DIR}/SonsOfTheForestDS_Data/boot.config"
    if [[ -f "$boot_cfg" ]]; then
        sed -i 's/gfx-enable-gfx-jobs=1/gfx-enable-gfx-jobs=0/' "$boot_cfg"
        sed -i 's/gfx-enable-native-gfx-jobs=1/gfx-enable-native-gfx-jobs=0/' "$boot_cfg"
        log_success "Patched boot.config: gfx-enable-gfx-jobs=0, gfx-enable-native-gfx-jobs=0"
    else
        log_warn "boot.config not found at ${boot_cfg} (game not yet downloaded?)"
    fi

    log_info "Config: ${data_cfg_dir}/"
    log_info "Saves:  ${data_saves_dir}/"
}

# Valheim Configuration
generate_valheim_config() {
    log_info "Generating Valheim configuration..."

    local config_dir="${DATA_DIR}/config"
    local save_dir="${DATA_DIR}/savefiles"

    mkdir -p "$save_dir"

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

# Subnautica Configuration
generate_subnautica_config() {
    log_info "Generating Subnautica configuration..."

    local config_dir="${DATA_DIR}/config"

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

# DayZ Configuration
generate_dayz_config() {
    log_info "Generating DayZ configuration..."

    local config_dir="${DATA_DIR}/config"
    local server_cfg="${config_dir}/server.cfg"

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

#######################################
# GENERIC CONFIG GENERATOR
#######################################

generate_generic_config() {
    log_info "Generating generic server configuration..."

    local config_dir="${DATA_DIR}/config"

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
# MOD INSTALLATION FUNCTIONS
#######################################

# Install RedLoader for Sons of the Forest
install_redloader() {
    local install_flag="${INSTALL_REDLOADER:-false}"

    if [[ "$install_flag" != "true" ]]; then
        log_info "RedLoader: Skipped (set INSTALL_REDLOADER=true to enable)"
        return 0
    fi

    local version="${REDLOADER_VERSION:-latest}"
    local version_file="${DATA_DIR}/.redloader_version"
    local installed_version=""
    [[ -f "$version_file" ]] && installed_version=$(cat "$version_file")

    # Resolve the target tag (and download URL for "latest") upfront so we
    # can compare against the installed version before touching anything.
    local target_tag=""
    local download_url=""

    if [[ "$version" == "latest" ]]; then
        log_info "RedLoader: Checking latest release..."
        local release_json
        release_json=$(curl -sf https://api.github.com/repos/ToniMacaroni/RedLoader/releases/latest) || {
            log_warn "RedLoader: Could not reach GitHub API — skipping version check"
            return 0
        }
        target_tag=$(echo "$release_json" | jq -r '.tag_name')
        download_url=$(echo "$release_json" | jq -r '.assets[] | select(.name | test("redloader\\.zip"; "i")) | .browser_download_url')
    else
        target_tag="$version"
        download_url="https://github.com/ToniMacaroni/RedLoader/releases/download/${version}/Redloader.zip"
    fi

    if [[ -z "$target_tag" ]] || [[ "$target_tag" == "null" ]]; then
        log_error "RedLoader: Could not determine target version"
        return 1
    fi

    # Check if already installed at the correct version
    local install_dir_exists=false
    if [[ -d "${GAME_DIR}/_Redloader" ]] || [[ -d "${GAME_DIR}/_RedLoader" ]]; then
        install_dir_exists=true
    fi

    if [[ "$installed_version" == "$target_tag" ]] && [[ "$install_dir_exists" == "true" ]]; then
        log_info "RedLoader ${target_tag} is already installed — skipping"
        mkdir -p "${GAME_DIR}/Mods"
        return 0
    fi

    if [[ -n "$installed_version" ]] && [[ "$installed_version" != "$target_tag" ]]; then
        log_info "RedLoader: Updating ${installed_version} → ${target_tag}"
    else
        log_info "RedLoader: Installing ${target_tag}"
    fi

    log_info "========================================="
    log_info "Installing RedLoader ${target_tag}"
    log_info "========================================="

    # Verify game directory exists
    if [[ ! -d "${GAME_DIR}" ]]; then
        log_error "Game directory not found: ${GAME_DIR}"
        return 1
    fi

    if [[ -z "$download_url" ]] || [[ "$download_url" == "null" ]]; then
        log_error "Could not determine RedLoader download URL"
        return 1
    fi

    log_info "URL: $download_url"

    cd "${GAME_DIR}"

    log_info "Downloading RedLoader..."
    wget -qO /tmp/RedLoader.zip "$download_url"

    log_info "Extracting RedLoader..."
    unzip -qo /tmp/RedLoader.zip -d "${GAME_DIR}"
    rm -f /tmp/RedLoader.zip

    # Verify installation
    if [[ -d "${GAME_DIR}/_Redloader" ]] || [[ -d "${GAME_DIR}/_RedLoader" ]]; then
        log_success "RedLoader ${target_tag} installed successfully"

        mkdir -p "${GAME_DIR}/Mods"
        log_info "Mods directory: ${GAME_DIR}/Mods"

        echo "$target_tag" > "${DATA_DIR}/.redloader_version"
        touch "${DATA_DIR}/.redloader_installed"
    else
        log_error "RedLoader extraction may have failed"
        return 1
    fi

    log_success "========================================="
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

    # Check if already initialized
    if [[ -f "${data_path}/.nitrox_initialized" ]]; then
        log_info "Nitrox already initialized, skipping setup"
        return 0
    fi

    # Install .NET 9 if needed (for Nitrox Linux component)
    if [[ "${INSTALL_DOTNET9:-true}" == "true" ]]; then
        log_info "Installing .NET 9 runtime for Nitrox..."

        # Download and install .NET 9
        if ! command -v dotnet &> /dev/null; then
            local dotnet_url="https://dot.net/v1/dotnet-install.sh"
            curl -sSL "$dotnet_url" -o /tmp/dotnet-install.sh
            bash /tmp/dotnet-install.sh --channel 9.0 --runtime aspnetcore --install-dir /usr/share/dotnet
            rm -f /tmp/dotnet-install.sh
            export PATH="$PATH:/usr/share/dotnet"
            log_success ".NET 9 installed"
        else
            log_info ".NET already installed"
        fi
    fi

    # Download Nitrox from GitHub
    log_info "Downloading Nitrox..."
    mkdir -p "${nitrox_path}"

    local nitrox_url=$(curl -s https://api.github.com/repos/SubnauticaNitrox/Nitrox/releases/latest \
        | grep -o 'https://.*linux_x64\.zip' | head -n 1)

    if [[ -z "$nitrox_url" ]]; then
        log_error "Could not fetch Nitrox download URL"
        return 1
    fi

    log_info "Nitrox URL: $nitrox_url"

    local filename=$(basename "$nitrox_url")
    local tmpfile="/tmp/${filename}"
    local tmpdir="/tmp/Nitrox"

    curl -L "$nitrox_url" -o "$tmpfile"
    rm -rf "$tmpdir"
    mkdir -p "$tmpdir"

    log_info "Extracting Nitrox..."
    unzip -q "$tmpfile" 'linux-x64/*' -d "$tmpdir"

    if [[ -d "${tmpdir}/linux-x64" ]]; then
        rsync -a "${tmpdir}/linux-x64/" "${nitrox_path}/"
        log_success "Nitrox extracted to: ${nitrox_path}"
    else
        log_error "linux-x64 directory not found in Nitrox archive"
        return 1
    fi

    rm -rf "$tmpfile" "$tmpdir"

    # Make executable
    chmod +x "${nitrox_path}/NitroxServer-Subnautica"
    log_success "Nitrox executable configured"

    # Create Nitrox config
    log_info "Configuring Nitrox..."
    mkdir -p "${nitrox_config_dir}"

    cat > "${nitrox_config_dir}/nitrox.cfg" << EOF
{
  "PreferredGamePath": "${subnautica_path}",
  "IsMultipleGameInstancesAllowed": true
}
EOF
    log_success "Created nitrox.cfg"

    # Create saves directory structure
    mkdir -p "${saves_dir}"
    mkdir -p "${nitrox_save_dir}"
    mkdir -p "${log_dir}"

    # Create default server.cfg
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

    # Create symlinks
    rm -rf "${nitrox_config_dir}/saves" "${nitrox_config_dir}/logs" 2>/dev/null || true
    ln -s "${saves_dir}" "${nitrox_config_dir}/saves"
    ln -s "${log_dir}" "${nitrox_config_dir}/logs"
    mkdir -p "${nitrox_config_dir}/cache"

    log_success "Nitrox directory structure configured"

    # Set environment for Nitrox
    export SUBNAUTICA_INSTALLATION_PATH="${subnautica_path}"

    # Mark as initialized
    touch "${data_path}/.nitrox_initialized"
    echo "nitrox" > "${data_path}/.mod_type"

    log_success "========================================="
    log_info "Nitrox setup completed successfully!"
    log_info "Save directory: ${nitrox_save_dir}"
    log_info "Config: ${nitrox_save_dir}/server.cfg"
    log_info "========================================="
}

#######################################
# MAIN
#######################################

log_info "[03] Generating server configuration..."

# Create config directory
mkdir -p "${DATA_DIR}/config"

# Check for game-specific config generator
preset="${GAME_CONFIG:-}"

if [[ -n "$preset" ]]; then
    generate_game_config "$preset"
else
    generate_generic_config
fi

log_success "[03] Configuration generated"
