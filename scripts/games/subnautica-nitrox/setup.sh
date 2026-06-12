#!/bin/bash
# Subnautica + Nitrox module — native Linux server (no Proton for the server itself).
# SteamCMD downloads the Subnautica BASE GAME (app 264710) with the cached Steam
# Guard login; the Nitrox server is installed by game_configure and launched by
# game_start. Subnautica.exe is only ever a download-verification marker.

game_configure() { generate_nitrox_config; }

game_start() { start_nitrox_server; }

# Subnautica's own files (not Nitrox's binary) prove the SteamCMD download worked —
# GAME_EXECUTABLE points at the Nitrox binary, which doesn't exist until
# game_configure installs it.
game_verify_install() {
    local install_dir="${GAME_DIR}/${STEAM_INSTALL_SUBDIR:-Subnautica}"
    if [[ ! -f "${install_dir}/Subnautica.exe" ]] && [[ ! -d "${install_dir}/Subnautica_Data" ]]; then
        log_error "Subnautica game files not found in ${install_dir}"
        log_info "SteamCMD reported success but neither Subnautica.exe nor Subnautica_Data/ are present."
        log_info "Inspect actual install location with: find / -name Subnautica.exe -o -name appmanifest_264710.acf 2>/dev/null"
        return 1
    fi
    return 0
}

# --- moved verbatim from scripts/03_config.sh and scripts/start.sh — DO NOT REFACTOR ---

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
# NITROX SERVER STARTUP (Native Linux)
#######################################

start_nitrox_server() {
    local nitrox_path="${GAME_DIR}/Nitrox"
    local nitrox_save_name="${NITROX_SAVE_NAME:-MyServer}"
    local log_file="${DATA_DIR}/logs/server.log"

    log_info "========================================="
    log_info "Starting Nitrox Server (Native Linux)"
    log_info "========================================="

    # Verify Nitrox installation
    if [[ ! -f "${nitrox_path}/Nitrox.Server.Subnautica" ]]; then
        log_error "Nitrox.Server.Subnautica not found at ${nitrox_path}"
        log_error "Run setup again to install Nitrox"
        exit 1
    fi

    # Set up environment
    export SUBNAUTICA_INSTALLATION_PATH="${GAME_DIR}/Subnautica"
    export PATH="$PATH:/usr/share/dotnet"

    # Create logs directory
    mkdir -p "${DATA_DIR}/logs"
    rotate_logs "$log_file"

    # Build Nitrox command
    local nitrox_cmd="${nitrox_path}/Nitrox.Server.Subnautica --save \"${nitrox_save_name}\""

    log_info "========================================="
    log_info "Nitrox Configuration:"
    log_info "  Save Name: ${nitrox_save_name}"
    log_info "  Nitrox Path: ${nitrox_path}"
    log_info "  Subnautica: ${SUBNAUTICA_INSTALLATION_PATH}"
    log_info "  Config: ${DATA_DIR}/saves/${nitrox_save_name}/server.cfg"
    log_info "========================================="
    log_info "Starting: ${nitrox_cmd}"
    log_info "========================================="

    # Change to Nitrox directory
    cd "${nitrox_path}"

    # Start Nitrox server (native Linux, no Proton needed)
    local launch_ts; launch_ts=$(date +%s)
    eval "${nitrox_path}/Nitrox.Server.Subnautica --save \"${nitrox_save_name}\"" >> "$log_file" 2>&1 &
    SERVER_PID=$!

    log_success "Nitrox server started (PID: $SERVER_PID)"
    log_info "Log file: $log_file"

    # Wait a moment to check if server started successfully
    sleep 5

    if ! kill -0 $SERVER_PID 2>/dev/null; then
        log_error "Nitrox server exited immediately"
        log_info "Check logs for errors:"
        tail -n 50 "$log_file" >&2
        exit 1
    fi

    log_success "Nitrox server is running!"

    # Start log tailing in foreground for Docker logs
    log_info "Tailing logs..."
    tail -f "$log_file" &
    TAIL_PID=$!

    # Wait for server process
    wait $SERVER_PID
    local exit_code=$?
    capture_fast_exit "$exit_code" "$launch_ts" "$log_file"

    # Cleanup
    kill $TAIL_PID 2>/dev/null || true

    log_info "Nitrox server exited with code: $exit_code"
    exit $exit_code
}
