#!/bin/bash
# Sons of the Forest module — hook functions sourced by load_game_module().

game_configure() {
    generate_sotf_config
    install_redloader
}

game_args() {
    # Do NOT pass -nographics: it forces NullGfxDevice which crashes SotF's HDRP shaders.
    # Verbose logging is opt-in (generates large log output).
    if [[ "${SOTF_VERBOSE_LOGGING:-false}" == "true" ]]; then
        echo "-verboseLogging"
    else
        echo ""
    fi
}

game_healthcheck() {
    local query_port="${QUERY_PORT:-7778}"
    if command -v nc &> /dev/null; then
        if nc -z -u -w 2 127.0.0.1 "$query_port" 2>/dev/null; then
            log_debug "Health check: SotF query port responsive"
        else
            log_warn "Health check: SotF query port not responding"
        fi
    fi
}

# --- moved from scripts/03_config.sh (persist-helper refactor applied to file/saves wiring) ---

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
        persist_file "${wine_file}" "${data_file}"
        # The game expects the target file to exist even before first generation.
        [[ -f "${data_file}" ]] || touch "${data_file}"
    done

    # ---- Saves directory symlink ----
    # Saves live in /data/saves/; Wine prefix Saves/ is a symlink to it.
    local wine_saves="${wine_appdata}/Saves"
    persist_dir "${wine_saves}" "${data_saves_dir}"

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
