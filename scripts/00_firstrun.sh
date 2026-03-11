#!/bin/bash
# First-run setup script
# One-time initialization tasks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

if [[ "${FIRST_RUN:-false}" != "true" ]]; then
    log_info "[00] Skipping first-run setup (already initialized)"
    exit 0
fi

log_info "[00] Running first-run setup..."

# Create necessary directories
mkdir -p "${DATA_DIR}/logs" \
         "${DATA_DIR}/config" \
         "${DATA_DIR}/saves" \
         "${BACKUP_DIR}" \
         "${GAME_DIR}" \
         /root/.steam/steam/steamapps/compatdata

# Set proper permissions
chmod -R 755 "${DATA_DIR}" 2>/dev/null || true
chmod -R 755 "${GAME_DIR}" 2>/dev/null || true

# Check for Steam credentials
if [[ "${STEAM_USER:-anonymous}" != "anonymous" ]] && [[ -n "${STEAM_PASSWORD:-}" ]]; then
    log_warn "Steam credentials provided - account may be guarded"
    log_warn "If prompted, set STEAM_GUARD_CODE environment variable"
fi

log_success "[00] First-run setup completed"
