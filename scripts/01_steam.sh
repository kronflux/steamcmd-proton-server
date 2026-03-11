#!/bin/bash
# SteamCMD initialization script
# Validates and updates SteamCMD installation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

log_info "[01] Initializing SteamCMD..."

# Verify SteamCMD installation
if [[ ! -f "/steamcmd/steamcmd.sh" ]]; then
    log_error "SteamCMD not found!"
    log_info "Reinstalling SteamCMD..."

    mkdir -p /steamcmd
    curl -sL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C /steamcmd
    chmod +x /steamcmd/steamcmd.sh

    log_success "SteamCMD reinstalled"
fi

# Update SteamCMD and prime the Windows platform app-info cache.
# Running +@sSteamCmdForcePlatformType windows here ensures the Windows depot
# manifests are cached before 02_server.sh attempts the game download.
log_info "Updating SteamCMD..."
/steamcmd/steamcmd.sh \
    +@sSteamCmdForcePlatformType windows \
    +login anonymous \
    +app_info_update 1 \
    +quit 2>&1 | grep -v "Steam client" || true

# Create steamapps directory structure
mkdir -p /steamapps/compatdata
mkdir -p /root/.steam/steam/steamapps/compatdata

# Detect and set up GE-Proton
log_info "Checking GE-Proton installation..."
if ! detect_proton; then
    log_error "GE-Proton not found!"
    log_info "Downloading latest GE-Proton..."

    mkdir -p /root/.steam/steam/compatibilitytools.d

    # Get latest GE-Proton release
    download_url=$(curl -sL https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
        | jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url' \
        | head -n 1)

    if [[ -n "$download_url" ]]; then
        log_info "Downloading from: $download_url"
        curl -sL "$download_url" | tar -xz -C /root/.steam/steam/compatibilitytools.d
        log_success "GE-Proton installed"
    else
        log_error "Failed to get GE-Proton download URL"
        exit 1
    fi
fi

# Verify Proton installation
proton_exe=$(get_proton_executable)
if [[ -x "$proton_exe" ]]; then
    log_success "Proton executable: $proton_exe"
else
    log_error "Proton executable not found or not executable: $proton_exe"
    exit 1
fi

log_success "[01] SteamCMD initialization completed"
