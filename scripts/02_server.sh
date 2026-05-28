#!/bin/bash
# Game download/update script
# Handles Steam mode, Download mode, and Direct mode

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

#######################################
# STEAM MODE
#######################################

handle_steam_mode() {
    log_info "Using Steam mode - downloading via SteamCMD"

    local app_id="${STEAM_APP_ID}"
    local install_dir="${GAME_DIR}"
    local beta_branch="${STEAM_BETA:-}"
    local beta_password="${STEAM_BETA_PASSWORD:-}"

    # Special handling for Nitrox (Subnautica)
    # Nitrox expects Subnautica files in /game/Subnautica/
    if [[ "${GAME_CONFIG:-}" == "subnautica-nitrox" ]]; then
        install_dir="${GAME_DIR}/Subnautica"
        log_info "Nitrox mode: Installing Subnautica to ${install_dir}"
    fi

    # Pre-create steamapps dir so +force_install_dir IPC call doesn't time out
    # on slow (WSL2/NFS) filesystems, which causes "Missing configuration" errors
    mkdir -p "${install_dir}/steamapps"

    # Build validate flag - only pass if explicitly requested
    local validate_flag=""
    if [[ "${STEAM_VALIDATE:-false}" == "true" ]]; then
        validate_flag="validate"
    fi

    log_info "Downloading/Updating App ID $app_id..."

    local steam_user="${STEAM_USER:-anonymous}"

    # Command pieces shared by every login mode. The +login args are appended
    # between these two when we actually invoke SteamCMD.
    local steam_pre=(+@sSteamCmdForcePlatformType windows +force_install_dir "${install_dir}")
    local steam_post=()
    if [[ -n "$beta_branch" ]]; then
        log_info "Using beta branch: $beta_branch"
        steam_post=(+app_set_beta "$app_id" "$beta_branch" +app_update "$app_id" ${validate_flag} +quit)
    else
        steam_post=(+app_update "$app_id" ${validate_flag} +quit)
    fi

    # Run SteamCMD with the given +login args. Streams output live (tee) and
    # reports success based on the app actually updating — SteamCMD's exit code
    # is unreliable, so a silent auth failure must not look like success.
    # stdin from /dev/null so a credential prompt fails fast instead of hanging.
    run_steam_update() {
        local logf; logf="$(mktemp)"
        /steamcmd/steamcmd.sh "${steam_pre[@]}" "$@" "${steam_post[@]}" < /dev/null 2>&1 | tee "$logf"
        local ok=1
        grep -qE "Success! App|already up to date|fully installed" "$logf" && ok=0
        rm -f "$logf"
        return $ok
    }

    local updated=false
    if [[ "$steam_user" == "anonymous" ]]; then
        run_steam_update +login anonymous && updated=true
    elif steam_cache_restore; then
        # Cache restored: log in with username ONLY so SteamCMD reuses the stored
        # session. Passing the password here would force a full re-auth and
        # consume a Steam Guard code on every start — the bug this avoids.
        log_info "Using cached Steam session for '${steam_user}' — no password or Steam Guard code needed"
        if run_steam_update +login "$steam_user"; then
            updated=true
        else
            log_warn "Cached Steam session was rejected (likely expired) — retrying with full credentials"
            local login_args=(+login "$steam_user" "${STEAM_PASSWORD:-}")
            [[ -n "${STEAM_GUARD_CODE:-}" ]] && login_args+=("${STEAM_GUARD_CODE}")
            run_steam_update "${login_args[@]}" && updated=true
        fi
    else
        # No usable cache: full credential login. The Steam Guard code (if 2FA is
        # enabled) is needed once here to prime the cache for future starts.
        local login_args=(+login "$steam_user" "${STEAM_PASSWORD:-}")
        [[ -n "${STEAM_GUARD_CODE:-}" ]] && login_args+=("${STEAM_GUARD_CODE}")
        run_steam_update "${login_args[@]}" && updated=true
    fi

    # Persist the (possibly newly-written) Steam session so the next start can
    # skip the password + Guard code. Done BEFORE the executable check so a
    # failed install verification doesn't waste the user's Steam Guard code.
    steam_cache_save || true

    # Auth-specific guidance if SteamCMD didn't report a successful update. Not a
    # hard failure on its own — the file verification below is the final arbiter,
    # so an unusual-but-valid success message can't cause a false abort here.
    if [[ "$updated" != "true" ]]; then
        log_warn "SteamCMD did not report a successful update for App ID $app_id"
        log_warn "First run: set STEAM_USER, STEAM_PASSWORD and a CURRENT STEAM_GUARD_CODE (if 2FA is on)."
        log_warn "Changed STEAM_CACHE_KEY recently? That invalidates the cache — supply a fresh STEAM_GUARD_CODE once to re-prime."
    fi

    # Verify the right files for this preset actually landed in install_dir.
    # Nitrox is a special case: GAME_EXECUTABLE (Nitrox.Server.Subnautica) is
    # the Nitrox binary installed later by 03_config.sh into ${GAME_DIR}/Nitrox/,
    # not into the Subnautica install_dir. Verify Subnautica's own files instead.
    if [[ "${GAME_CONFIG:-}" == "subnautica-nitrox" ]]; then
        if [[ ! -f "${install_dir}/Subnautica.exe" ]] && [[ ! -d "${install_dir}/Subnautica_Data" ]]; then
            log_error "Subnautica game files not found in ${install_dir}"
            log_info "SteamCMD reported success but neither Subnautica.exe nor Subnautica_Data/ are present."
            log_info "Inspect actual install location with: find / -name Subnautica.exe -o -name appmanifest_264710.acf 2>/dev/null"
            exit 1
        fi
    else
        if [[ ! -f "${install_dir}/${GAME_EXECUTABLE}" ]]; then
            log_error "Game executable not found: ${install_dir}/${GAME_EXECUTABLE}"
            log_info "Search for executable with: find ${install_dir} -name '*.exe'"
            exit 1
        fi
    fi

    log_success "Game files ready via SteamCMD"
}

#######################################
# DOWNLOAD MODE
#######################################

handle_download_mode() {
    log_info "Using Download mode - downloading from URL"

    local download_url="${GAME_DOWNLOAD_URL:-}"

    if [[ -z "$download_url" ]]; then
        log_error "GAME_DOWNLOAD_URL not set for download mode"
        exit 1
    fi

    local filename=$(basename "$download_url")
    local temp_file="/tmp/${filename}"
    local temp_dir="/tmp/game_extract"

    # Download file
    log_info "Downloading from: $download_url"
    if [[ "$download_url" =~ \.tar\.gz$ ]]; then
        curl -sL "$download_url" | tar -xz -C "${GAME_DIR}"
    elif [[ "$download_url" =~ \.tar\.bz2$ ]]; then
        curl -sL "$download_url" | tar -xj -C "${GAME_DIR}"
    elif [[ "$download_url" =~ \.zip$ ]]; then
        curl -sL "$download_url" -o "$temp_file"
        unzip -q "$temp_file" -d "${GAME_DIR}"
        rm -f "$temp_file"
    elif [[ "$download_url" =~ \.7z$ ]]; then
        curl -sL "$download_url" -o "$temp_file"
        7z x "$temp_file" -o"${GAME_DIR}" -y
        rm -f "$temp_file"
    else
        # Try to download and extract
        curl -sL "$download_url" -o "$temp_file"
        mkdir -p "$temp_dir"
        tar -xf "$temp_file" -C "$temp_dir" 2>/dev/null || \
        unzip -q "$temp_file" -d "$temp_dir" 2>/dev/null || \
        cp "$temp_file" "${GAME_DIR}/"
        rm -f "$temp_file"

        # Move contents if extracted to subdirectory
        if [[ $(find "$temp_dir" -maxdepth 1 -mindepth 1 | wc -l) -eq 1 ]]; then
            mv "$temp_dir"/*/* "${GAME_DIR}/" 2>/dev/null || true
        else
            mv "$temp_dir"/* "${GAME_DIR}/" 2>/dev/null || true
        fi
        rm -rf "$temp_dir"
    fi

    log_success "Game files downloaded and extracted"
}

#######################################
# DIRECT MODE
#######################################

handle_direct_mode() {
    log_info "Using Direct mode - using pre-existing game files"

    # Verify game directory has content
    if [[ ! -d "${GAME_DIR}" ]] || [[ -z "$(ls -A ${GAME_DIR})" ]]; then
        log_error "GAME_DIR is empty or doesn't exist: ${GAME_DIR}"
        log_info "For direct mode, mount game files to ${GAME_DIR}"
        exit 1
    fi

    # Search for game executable if not exactly specified
    if [[ ! -f "${GAME_DIR}/${GAME_EXECUTABLE}" ]]; then
        log_warn "Exact executable path not found: ${GAME_DIR}/${GAME_EXECUTABLE}"
        log_info "Searching for Windows executables..."

        local found_exe=$(find "${GAME_DIR}" -name "*.exe" -type f 2>/dev/null | grep -i server | head -n 1)

        if [[ -n "$found_exe" ]]; then
            log_info "Found candidate: $found_exe"
            # Update GAME_EXECUTABLE to relative path
            GAME_EXECUTABLE="${found_exe#${GAME_DIR}/}"
            export GAME_EXECUTABLE
        else
            log_error "No server executable found in ${GAME_DIR}"
            exit 1
        fi
    fi

    log_success "Using existing game files"
}

#######################################
# MAIN
#######################################

log_info "[02] Processing game files..."

# Determine operation mode
mode="${GAME_MODE:-steam}"

# STEAM_UPDATE=false skips SteamCMD entirely (useful when game is already installed)
if [[ "$mode" == "steam" ]] && [[ "${STEAM_UPDATE:-true}" == "false" ]]; then
    if [[ -f "${GAME_DIR}/${GAME_EXECUTABLE}" ]]; then
        log_info "STEAM_UPDATE=false: skipping update, using existing game files"
    else
        log_warn "STEAM_UPDATE=false but game not found at ${GAME_DIR}/${GAME_EXECUTABLE}, running download anyway"
        handle_steam_mode
    fi
else
    case "$mode" in
        steam)
            handle_steam_mode
            ;;
        download)
            handle_download_mode
            ;;
        direct)
            handle_direct_mode
            ;;
        *)
            log_error "Invalid GAME_MODE: $mode (must be: steam|download|direct)"
            exit 1
            ;;
    esac
fi

log_success "[02] Game files processed"
