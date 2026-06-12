#!/bin/bash
# Vein module — native Linux server (no Proton); refuses to run as root, so
# game_start launches it as a non-root user.

game_configure() { generate_vein_config; }

game_start() { start_vein_server; }

game_healthcheck() {
    local query_port="${QUERY_PORT:-27015}"
    if command -v nc &> /dev/null; then
        if nc -z -u -w 2 127.0.0.1 "$query_port" 2>/dev/null; then
            log_debug "Health check: Vein query port responsive"
        else
            log_warn "Health check: Vein query port not responding"
        fi
    fi
}

# --- moved from scripts/03_config.sh and scripts/start.sh (persist-helper refactor applied to Game.ini + SaveGames wiring) ---

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
    # Config file lives in /data/config/; the game's expected path is a symlink
    # back to it (generation below writes through the link).
    persist_file "${game_ini}" "${config_dir}/Game.ini"

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

    # ---- SaveGames directory symlink ----
    # Saves live in /data/saves/; the game's SaveGames/ is a symlink to it.
    local game_saves="${GAME_DIR}/Vein/Saved/SaveGames"
    persist_dir "${game_saves}" "${saves_dir}"

    log_info "Config: ${config_dir}/"
    log_info "Saves:  ${saves_dir}/"
}

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
