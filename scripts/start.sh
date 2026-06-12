#!/bin/bash
# Server startup script
# Handles Proton environment setup and server execution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

# Start cron daemon for automated backups
if command -v cron &> /dev/null; then
    # Cron jobs run with a bare environment and don't see the container's ENV
    # (GAME_CONFIG, DATA_DIR, BACKUP_DIR, ...). Snapshot the current environment
    # so backup.sh can source it; without this, scheduled backups archive nothing.
    mkdir -p /var/run
    export -p > /var/run/container.env 2>/dev/null || true
    cron 2>/dev/null || true
    log_info "Cron daemon started for automated backups"
fi

#######################################
# ENVIRONMENT SETUP
#######################################

setup_proton_environment() {
    # PROTON_APP_ID overrides STEAM_APP_ID for the Wine prefix path.
    # Some games (e.g. SotF dedicated server 2465200) use a different app ID
    # for their Proton prefix than their SteamCMD download.
    local proton_app_id="${PROTON_APP_ID:-${STEAM_APP_ID}}"

    export STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH:-${DATA_DIR}/.proton/${proton_app_id}}"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="/root/.steam/steam"
    export SteamAppId="${proton_app_id}"
    export SteamGameId="${proton_app_id}"
    export STEAM_COMPAT_APP_ID="${proton_app_id}"

    # Disable Steam Runtime
    export STEAM_RUNTIME=0

    # Proton-specific optimizations
    export PROTON_NO_FSYNC=1
    export PROTON_NO_ESYNC=1
    export PROTON_USE_XALIA=0
    # Disable NVIDIA API
    export PROTON_DISABLE_NVAPI=1
    # Disable NGX updater
    export PROTON_ENABLE_NGX_UPDATER=0
    # Prevents DXVK from initializing Vulkan in GPU-less containers.
    export PROTON_NO_D3D11=1

    # Proton requires the /pfx subdirectory as the Wine prefix root.
    export WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx"
    export WINEARCH=win64
    # Default to silencing Wine, but allow override (e.g. WINEDEBUG=fixme-all,err+all
    # to surface missing-DLL / load errors when a Windows server crashes silently).
    export WINEDEBUG="${WINEDEBUG:--all}"

    # XDG runtime directory
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR" || true

    # Bypasses Proton's steam.exe relay, which hangs indefinitely waiting for
    # a native Linux Steam IPC socket that doesn't exist in a container.
    export UMU_ID=0

    log_info "Proton environment configured"
    log_debug "SteamAppId: $SteamAppId"
    log_debug "STEAM_COMPAT_DATA_PATH: $STEAM_COMPAT_DATA_PATH"
}

setup_display_environment() {
    # Set up Xvfb for games requiring display
    if [[ "${NEEDS_DISPLAY:-false}" == "true" ]]; then
        export DISPLAY="${DISPLAY:-:5}"
        export XVFB_RESOLUTION="${XVFB_RESOLUTION:-1024x768x16}"

        # SDL environment variables for Unity games
        export SDL_VIDEODRIVER="dummy"
        export SDL_AUDIODRIVER="dummy"

        # Force software rendering
        export LIBGL_ALWAYS_SOFTWARE=1
        log_info "Starting Xvfb..."
        start_xvfb
    fi
}

#######################################
# WINE PREFIX DEPENDENCY PROVISIONING
#######################################

# Install Windows runtime libraries into the Proton/Wine prefix for games that
# need them. Opt-in per preset via WINETRICKS_VERBS (space-separated winetricks
# verbs). Runs once per prefix (tracked by a marker), so restarts are fast.
provision_wine_deps() {
    [[ -z "${WINETRICKS_VERBS:-}" ]] && return 0

    local marker="${STEAM_COMPAT_DATA_PATH}/.winetricks_done"
    if [[ -f "$marker" ]]; then
        log_info "Wine runtime deps already provisioned (${WINETRICKS_VERBS})"
        return 0
    fi
    if ! command -v winetricks >/dev/null 2>&1; then
        log_warn "winetricks not installed — cannot provision Wine deps: ${WINETRICKS_VERBS}"
        return 0
    fi

    log_info "Provisioning Wine runtime deps via winetricks: ${WINETRICKS_VERBS}"
    log_info "(first run for this prefix only — this can take several minutes)"

    # Install into the same prefix the game runs in. mscoree/mshtml=d skips the
    # Mono/Gecko install prompts. Word-splitting of the verb list is intentional.
    local wine_bin; wine_bin="$(command -v wine64 || command -v wine)"
    # shellcheck disable=SC2086
    if WINE="$wine_bin" WINEPREFIX="${STEAM_COMPAT_DATA_PATH}/pfx" \
       WINEDLLOVERRIDES="mscoree=d;mshtml=d" WINEDEBUG="-all" \
       winetricks -q -f ${WINETRICKS_VERBS} >> "$log_file" 2>&1; then
        touch "$marker"
        log_success "Wine runtime deps installed"
    else
        log_warn "winetricks reported errors — the server may still fail if deps are missing"
    fi
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

    # Cleanup
    kill $TAIL_PID 2>/dev/null || true

    log_info "Nitrox server exited with code: $exit_code"
    exit $exit_code
}

#######################################
# VEIN SERVER STARTUP (Native Linux)
#######################################

start_vein_server() {
    local game_dir="${GAME_DIR}"
    local launcher="${game_dir}/VeinServer.sh"
    local bin_dir="${game_dir}/Vein/Binaries/Linux"
    local log_file="${DATA_DIR}/logs/server.log"
    local game_port="${GAME_PORT:-7777}"
    local query_port="${QUERY_PORT:-27015}"

    log_info "========================================="
    log_info "Starting Vein Server (Native Linux)"
    log_info "========================================="

    if [[ ! -f "$launcher" ]]; then
        log_error "VeinServer.sh not found at ${launcher}"
        log_error "Run setup again to install the Vein server"
        exit 1
    fi
    chmod +x "$launcher" 2>/dev/null || true
    [[ -d "$bin_dir" ]] && find "$bin_dir" -maxdepth 1 -name 'VeinServer-Linux-*' -exec chmod +x {} \; 2>/dev/null || true

    # Vein's native server refuses to run as root, so run it as a non-root user.
    # Defaults match Unraid's nobody:users (99:100); override with PUID/PGID.
    local run_uid="${PUID:-99}"
    local run_gid="${PGID:-100}"
    local run_user="vein"
    getent group "$run_gid" >/dev/null 2>&1 || groupadd -g "$run_gid" "$run_user" 2>/dev/null || true
    if ! getent passwd "$run_uid" >/dev/null 2>&1; then
        useradd -u "$run_uid" -g "$run_gid" -M -d "${DATA_DIR}" -s /bin/bash "$run_user" 2>/dev/null || true
    fi
    # Resolve the actual username for the requested UID (it may already exist under another name).
    run_user="$(getent passwd "$run_uid" | cut -d: -f1)"
    [[ -z "$run_user" ]] && run_user="vein"

    # Game files were downloaded as root; hand /data to the server user so it can
    # read the game and write saves/config/logs.
    log_info "Setting ownership of ${DATA_DIR} to ${run_uid}:${run_gid} (Vein runs non-root)..."
    chown -R "${run_uid}:${run_gid}" "${DATA_DIR}" 2>/dev/null || true

    mkdir -p "${DATA_DIR}/logs"
    rotate_logs "$log_file"

    log_info "========================================="
    log_info "Vein Configuration:"
    log_info "  Server Name: ${SERVER_NAME:-Vein Server}"
    log_info "  Game Port:   ${game_port}/udp"
    log_info "  Query Port:  ${query_port}/udp"
    log_info "  Max Players: ${MAX_PLAYERS:-16}"
    log_info "  Run As:      ${run_user} (${run_uid}:${run_gid})"
    log_info "  Config:      ${DATA_DIR}/config/Game.ini"
    log_info "========================================="
    log_info "Starting: ${launcher} -log -Port=${game_port} -QueryPort=${query_port}"
    log_info "========================================="

    cd "${game_dir}"

    # Native Linux server — no Proton — run as the non-root user. HOME under /data
    # so any ~/.steam writes persist and are writable. stdin from /dev/null for
    # clean backgrounding.
    su -s /bin/bash -c "cd \"${game_dir}\" && HOME=\"${DATA_DIR}\" \"${launcher}\" -log -Port=${game_port} -QueryPort=${query_port}${GAME_ARGS:+ ${GAME_ARGS}}" "$run_user" < /dev/null >> "$log_file" 2>&1 &
    SERVER_PID=$!

    log_success "Vein server started (PID: $SERVER_PID)"
    log_info "Log file: $log_file"

    sleep 5

    if ! kill -0 $SERVER_PID 2>/dev/null; then
        log_error "Vein server exited immediately"
        log_info "Check logs for errors:"
        tail -n 50 "$log_file" >&2
        exit 1
    fi

    log_success "Vein server is running!"

    log_info "Tailing logs..."
    tail -f "$log_file" &
    TAIL_PID=$!

    wait $SERVER_PID
    local exit_code=$?

    kill $TAIL_PID 2>/dev/null || true

    log_info "Vein server exited with code: $exit_code"
    exit $exit_code
}

#######################################
# MAIN STARTUP
#######################################

main() {
    log_info "========================================="
    log_info "Starting Game Server"
    log_info "========================================="

    # Validate required variables
    validate_required_vars || exit 1

    load_game_module

    # Module-provided launcher (native-Linux servers own their full lifecycle)
    if declare -f game_start >/dev/null; then
        game_start
        return
    fi

    # Special handling for Nitrox (native Linux server)
    if [[ "${GAME_CONFIG:-}" == "subnautica-nitrox" ]]; then
        start_nitrox_server
        return
    fi

    # Special handling for Vein (native Linux server)
    if [[ "${GAME_CONFIG:-}" == "vein" ]]; then
        start_vein_server
        return
    fi

    # Set up Proton environment
    setup_proton_environment

    # Detect Proton
    detect_proton || exit 1

    # Initialize Wine prefix (must use /pfx subdirectory for Proton)
    log_info "Initializing Wine prefix..."
    mkdir -p "${STEAM_COMPAT_DATA_PATH}/pfx"
    init_wine_prefix "${STEAM_COMPAT_DATA_PATH}/pfx"

    # Set up display if needed
    setup_display_environment

    # Create logs directory
    mkdir -p "${DATA_DIR}/logs"
    local log_file="${DATA_DIR}/logs/server.log"

    # Rotate logs if needed
    rotate_logs "$log_file"

    # Install any required Windows runtime libs into the prefix (opt-in per preset).
    provision_wine_deps

    # Build command
    local game_exe="${GAME_DIR}/${GAME_EXECUTABLE}"
    local proton_cmd="${PROTONPATH}/proton run"

    local base_args=""
    if declare -f game_args >/dev/null; then
        base_args="$(game_args)"
    else
        case "${GAME_CONFIG:-}" in
            sons-of-the-forest|sons-of-the-forest-modded)
                # Do NOT pass -nographics: it forces NullGfxDevice which crashes SotF's HDRP shaders.
                # Verbose logging is opt-in (generates large log output).
                if [[ "${SOTF_VERBOSE_LOGGING:-false}" == "true" ]]; then
                    base_args="-verboseLogging"
                fi
                ;;
            scum)
                # SCUM derives its query/raw ports from -port (game+2 / game+1).
                base_args="-log -port=${GAME_PORT:-7777} -MaxPlayers=${MAX_PLAYERS:-64}"
                if [[ "${SCUM_DISABLE_BATTLEYE:-false}" == "true" ]]; then
                    base_args="${base_args} -nobattleye"
                fi
                ;;
        esac
    fi
    local game_args="${base_args}${GAME_ARGS:+ ${GAME_ARGS}}"

    # Use Windows Z:\ path - a Unix path triggers Proton's /unix dispatch which
    # detaches the game via start.exe and loses its exit code. Single-quote the
    # path so eval doesn't strip backslashes.
    local win_game_exe="Z:$(echo "$game_exe" | tr '/' '\\')"
    local full_cmd="${proton_cmd} '${win_game_exe}' ${game_args}"

    log_info "========================================="
    log_info "Server Configuration:"
    log_info "  Game: ${GAME_CONFIG:-generic}"
    log_info "  App ID: ${STEAM_APP_ID}"
    log_info "  Executable: ${game_exe}"
    log_info "  Working Dir: ${GAME_DIR}"
    log_info "  Save Data: ${DATA_DIR}"
    log_info "========================================="
    log_info "Starting: ${full_cmd}"
    log_info "========================================="

    # Change to game directory
    cd "${GAME_DIR}"

    # Some games exit 0 on first start after creating default config files.
    local restart_count=0
    local max_restarts=3

    while true; do
        log_success "Starting server..."
        log_info "Command: $full_cmd"
        log_info "Log file: $log_file"

        # stdin from /dev/null prevents a Wine SIGSEGV when stdin is a pipe (Docker default).
        # tee writes to server.log while keeping all output visible in the Docker console.
        local exit_code=0
        eval "$full_cmd" < /dev/null 2>&1 | tee -a "$log_file"
        exit_code=${PIPESTATUS[0]}
        SERVER_PID=""

        local needs_restart=false
        if [[ $restart_count -lt $max_restarts ]]; then
            if grep -q "Please restart the server" "$log_file" 2>/dev/null; then
                needs_restart=true
            fi
        fi

        if [[ "$needs_restart" == "true" ]]; then
            restart_count=$((restart_count + 1))
            log_info "Server requested restart after first-run setup (attempt ${restart_count}/${max_restarts})"
            log_info "Restarting in 3 seconds..."
            sed -i '/Please restart the server/d' "$log_file" 2>/dev/null || true
            sleep 3
            continue
        fi

        break
    done

    stop_xvfb
    log_info "Server exited with code: $exit_code"
    exit $exit_code
}

# Run main
main "$@"
