#!/bin/bash
# Shared utility functions for steamcmd-proton-server
# This file is sourced by all other scripts

set -e

#######################################
# LOGGING FUNCTIONS
#######################################

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*"
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEBUG] $*"
    fi
}

#######################################
# PROTON DETECTION
#######################################

detect_proton() {
    # Search for GE-Proton in compatibility tools directory
    local compat_dir="/root/.steam/steam/compatibilitytools.d"

    if [[ -d "$compat_dir" ]]; then
        # Find all GE-Proton versions
        local proton_versions=($(find "$compat_dir" -maxdepth 1 -type d -name "GE-Proton*" | sort -V))

        if [[ ${#proton_versions[@]} -gt 0 ]]; then
            # Return the latest version
            PROTONPATH="${proton_versions[-1]}"
            log_info "Found GE-Proton: $PROTONPATH"
            return 0
        fi
    fi

    # Fallback: check system Proton
    if [[ -f "/usr/bin/proton" ]]; then
        PROTONPATH="/usr/bin"
        log_info "Using system Proton"
        return 0
    fi

    log_error "No Proton installation found!"
    return 1
}

get_proton_executable() {
    local compat_dir="/root/.steam/steam/compatibilitytools.d"

    if [[ -d "$compat_dir" ]]; then
        local proton_versions=($(find "$compat_dir" -maxdepth 1 -type d -name "GE-Proton*" | sort -V))

        if [[ ${#proton_versions[@]} -gt 0 ]]; then
            echo "${proton_versions[-1]}/proton"
            return 0
        fi
    fi

    # Fallback: check system Proton
    if [[ -f "/usr/bin/proton" ]]; then
        echo "/usr/bin/proton"
        return 0
    fi

    return 1
}

# Export PROTONPATH for use in other scripts
export_proton_path() {
    detect_proton
    export PROTONPATH
}

#######################################
# WINE PREFIX MANAGEMENT
#######################################

init_wine_prefix() {
    local prefix="${1:-${STEAM_COMPAT_DATA_PATH}}"

    if [[ -z "$prefix" ]]; then
        log_error "STEAM_COMPAT_DATA_PATH not set"
        return 1
    fi

    log_info "Initializing Wine prefix: $prefix"

    # Create prefix directory
    mkdir -p "$prefix"

    # Set Wine environment
    export WINEPREFIX="$prefix"
    export WINEARCH=win64
    export WINEDEBUG="-all"

    # Initialize Wine prefix
    if [[ ! -f "$prefix/system.reg" ]]; then
        log_info "Creating new Wine prefix..."
        # Use full path to wine binary
        local wine_bin="/usr/lib/wine/wine"
        local wineserver_bin="/usr/lib/wine/wineserver"

        "$wine_bin" wineboot -i -u 2>&1 | grep -v "wine:|" || true
        "$wineserver_bin" -w 2>&1 || true
    fi

    log_success "Wine prefix initialized"
    return 0
}

#######################################
# XVFB MANAGEMENT
#######################################

start_xvfb() {
    local display="${DISPLAY:-:5}"
    local resolution="${XVFB_RESOLUTION:-1024x768x16}"

    # Check if Xvfb is already running
    if pgrep -f "Xvfb $display" > /dev/null; then
        log_debug "Xvfb already running on $display"
        return 0
    fi

    log_info "Starting Xvfb on $display ($resolution)"

    # Start Xvfb in background
    Xvfb "$display" -screen 0 "$resolution" -ac +extension GLX +render -noreset &
    local xvfb_pid=$!

    # Wait for Xvfb to be ready
    sleep 1

    if ! kill -0 "$xvfb_pid" 2>/dev/null; then
        log_error "Failed to start Xvfb"
        return 1
    fi

    log_success "Xvfb started (PID: $xvfb_pid)"
    return 0
}

stop_xvfb() {
    local display="${DISPLAY:-:5}"

    if pgrep -f "Xvfb $display" > /dev/null; then
        log_info "Stopping Xvfb on $display"
        pkill -f "Xvfb $display" || true
        log_success "Xvfb stopped"
    fi
    return 0
}

#######################################
# SIGNAL HANDLING
#######################################

setup_signal_handlers() {
    # Set up traps for graceful shutdown
    trap 'shutdown_handler SIGTERM' SIGTERM
    trap 'shutdown_handler SIGINT' SIGINT
}

shutdown_handler() {
    local signal="$1"
    log_info "Received $signal, shutting down gracefully..."

    # Stop Xvfb
    stop_xvfb

    # Kill server process if running
    if [[ -n "$SERVER_PID" ]]; then
        log_info "Stopping server process (PID: $SERVER_PID)"
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        # Wait for process to exit
        timeout 10 tail --pid="$SERVER_PID" -f /dev/null || kill -KILL "$SERVER_PID" 2>/dev/null || true
    fi

    # Stop Wine server
    wineserver -k 2>/dev/null || true

    log_success "Shutdown complete"
    exit 0
}

#######################################
# LOG ROTATION
#######################################

rotate_logs() {
    local log_file="${1:-${GAME_DIR}/logs/server.log}"
    local max_size="${LOG_MAX_SIZE:-100M}"
    local retention="${LOG_RETENTION:-5}"

    if [[ ! -f "$log_file" ]]; then
        return 0
    fi

    # Check file size
    local size_bytes=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)

    if [[ $size_bytes -gt 0 ]]; then
        # Rotate logs
        for ((i=retention-1; i>=1; i--)); do
            if [[ -f "${log_file}.${i}" ]]; then
                if [[ $i -eq $((retention-1)) ]]; then
                    rm -f "${log_file}.${i}" || true
                else
                    mv "${log_file}.${i}" "${log_file}.$((i+1))" 2>/dev/null || true
                fi
            fi
        done

        if [[ -f "${log_file}.1" ]]; then
            rm -f "${log_file}.1" || true
        fi

        mv "$log_file" "${log_file}.1" 2>/dev/null || true
        touch "$log_file"

        # Compress old logs
        find "$(dirname "$log_file")" -name "$(basename "$log_file").[1-9]" -exec gzip -f {} \; 2>/dev/null || true

        log_info "Log rotation completed"
    fi
}

#######################################
# BACKUP FUNCTIONS
#######################################

create_backup() {
    local backup_dir="${BACKUP_DIR:-/data/backups}"
    local retention="${BACKUP_RETENTION:-7}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="backup_${timestamp}"

    mkdir -p "$backup_dir"

    log_info "Creating backup: $backup_name"

    # Create temporary directory for this backup
    local temp_backup="${backup_dir}/temp_${timestamp}"
    mkdir -p "$temp_backup"

    # Backup game data
    if [[ -d "${GAME_DIR}" ]]; then
        log_info "Backing up game files..."
        # Use rsync for efficient copying if available
        if command -v rsync &> /dev/null; then
            rsync -a --exclude='*.tmp' --exclude='*.log' --exclude='cache' \
                "${GAME_DIR}/" "${temp_backup}/game/" 2>/dev/null || true
        else
            cp -r "${GAME_DIR}" "${temp_backup}/game" 2>/dev/null || true
        fi
    fi

    # Backup Wine prefix
    if [[ -n "${STEAM_COMPAT_DATA_PATH}" && -d "${STEAM_COMPAT_DATA_PATH}" ]]; then
        log_info "Backing up Wine prefix..."
        if command -v rsync &> /dev/null; then
            rsync -a --exclude='*.tmp' --exclude='temp' \
                "${STEAM_COMPAT_DATA_PATH}/" "${temp_backup}/wine/" 2>/dev/null || true
        else
            cp -r "${STEAM_COMPAT_DATA_PATH}" "${temp_backup}/wine" 2>/dev/null || true
        fi
    fi

    # Create compressed archive
    log_info "Compressing backup..."
    tar -czf "${backup_dir}/${backup_name}.tar.gz" -C "$temp_backup" . 2>/dev/null || true

    # Cleanup temp directory
    rm -rf "$temp_backup"

    # Verify backup was created
    if [[ -f "${backup_dir}/${backup_name}.tar.gz" ]]; then
        log_success "Backup created: ${backup_name}.tar.gz"

        # Calculate backup size
        local size=$(stat -f%z "${backup_dir}/${backup_name}.tar.gz" 2>/dev/null || stat -c%s "${backup_dir}/${backup_name}.tar.gz" 2>/dev/null || echo 0)
        log_info "Backup size: $(numfmt --to=iec $size 2>/dev/null || echo $size bytes)"
    else
        log_error "Backup creation failed"
        return 1
    fi

    # Clean old backups
    log_info "Cleaning old backups (keeping $retention)..."
    find "$backup_dir" -name "backup_*.tar.gz" -type f -mtime +$retention -delete 2>/dev/null || true

    return 0
}

#######################################
# GAME PRESET HANDLING
#######################################

load_game_preset() {
    local preset="${GAME_CONFIG:-}"
    local preset_dir="/scripts/presets"

    if [[ -z "$preset" ]]; then
        log_debug "No game preset specified"
        return 0
    fi

    local preset_file="${preset_dir}/${preset}.conf"

    if [[ -f "$preset_file" ]]; then
        log_info "Loading preset: $preset"
        # Source the preset file
        source "$preset_file"
        log_success "Preset loaded: $preset"
    else
        log_warn "Preset not found: $preset_file"
    fi
}

#######################################
# CONFIG VALIDATION
#######################################

validate_required_vars() {
    local missing=()

    # Core required variables
    [[ -z "${STEAM_APP_ID:-}" ]] && missing+=("STEAM_APP_ID")
    [[ -z "${GAME_EXECUTABLE:-}" ]] && missing+=("GAME_EXECUTABLE")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing[*]}"
        return 1
    fi

    log_debug "Required variables present"
    return 0
}

validate_game_dir() {
    if [[ ! -d "${GAME_DIR}" ]]; then
        log_info "Creating game directory: ${GAME_DIR}"
        mkdir -p "${GAME_DIR}"
    fi
}

validate_data_dir() {
    if [[ ! -d "${DATA_DIR}" ]]; then
        log_info "Creating data directory: ${DATA_DIR}"
        mkdir -p "${DATA_DIR}"
    fi
}

#######################################
# RCON FUNCTIONS
#######################################

rcon_send() {
    if [[ "${RCON_ENABLED:-false}" != "true" ]]; then
        return 0
    fi

    local rcon_host="${RCON_HOST:-127.0.0.1}"
    local rcon_port="${RCON_PORT:-27015}"
    local rcon_pass="${RCON_PASSWORD:-}"

    if [[ -z "$rcon_pass" ]]; then
        log_warn "RCON enabled but no password set"
        return 1
    fi

    if ! command -v rcon-cli &> /dev/null; then
        log_warn "rcon-cli not found"
        return 1
    fi

    log_debug "Sending RCON command: $1"
    rcon-cli --host "$rcon_host" --port "$rcon_port" --pass "$rcon_pass" "$1" 2>/dev/null || true
}

rcon_save() {
    rcon_send "Save"
}

rcon_shutdown() {
    rcon_send "Shutdown"
}

#######################################
# HEALTH CHECK FUNCTIONS
#######################################

check_server_process() {
    if [[ -z "$SERVER_PID" ]]; then
        return 1
    fi

    if kill -0 "$SERVER_PID" 2>/dev/null; then
        return 0
    fi

    return 1
}

check_game_server() {
    local game_exe="${GAME_EXECUTABLE}"

    # Check if game executable is running
    if pgrep -f "$game_exe" > /dev/null; then
        return 0
    fi

    return 1
}

#######################################
# STEAMCMD WRAPPERS
#######################################

steamcmd_login() {
    local steam_user="${STEAM_USER:-anonymous}"
    local steam_pass="${STEAM_PASSWORD:-}"
    local steam_guard="${STEAM_GUARD_CODE:-}"

    if [[ "$steam_user" == "anonymous" ]]; then
        echo "+login anonymous"
    else
        local login_cmd="+login $steam_user"
        [[ -n "$steam_pass" ]] && login_cmd="$login_cmd $steam_pass"
        [[ -n "$steam_guard" ]] && login_cmd="$login_cmd $steam_guard"
        echo "$login_cmd"
    fi
}

steamcmd_update() {
    local app_id="$1"
    local install_dir="${2:-${GAME_DIR}}"
    local validate="${STEAM_VALIDATE:-false}"

    local cmd="+app_update $app_id"
    [[ "$validate" == "true" ]] && cmd="$cmd validate"

    echo "$cmd +quit"
}

#######################################
# HELPER FUNCTIONS
#######################################

wait_for_file() {
    local file="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if [[ -f "$file" ]]; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    return 1
}

wait_for_process() {
    local process_name="$1"
    local timeout="${2:-120}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if pgrep -f "$process_name" > /dev/null; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    return 1
}

# Export functions for use in subshells
export -f log_info log_error log_warn log_success log_debug
export -f detect_proton get_proton_executable
export -f init_wine_prefix
export -f start_xvfb stop_xvfb
export -f create_backup rcon_send rcon_save rcon_shutdown
export -f rotate_logs check_server_process check_game_server
