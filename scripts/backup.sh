#!/bin/bash
# Automated backup script
# Run via cron or manually

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

# Backup settings
BACKUP_DIR="${BACKUP_DIR:-/data/backups}"
BACKUP_RETENTION="${BACKUP_RETENTION:-7}"
BACKUP_BEFORE_UPDATE="${BACKUP_BEFORE_UPDATE:-false}"

log_info "========================================="
log_info "Starting backup process"
log_info "========================================="

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Check if server is running
if check_game_server; then
    log_info "Server is running - pausing for backup..."

    # Send RCON save command if enabled
    if [[ "${RCON_ENABLED:-false}" == "true" ]]; then
        log_info "Triggering in-game save..."
        rcon_save
        sleep 5  # Give time for save to complete
    fi
fi

# Create the backup
if create_backup; then
    log_success "Backup completed successfully"

    # List current backups
    log_info "Current backups:"
    ls -lh "$BACKUP_DIR" | grep "backup_" | tail -5

    # Calculate total backup size
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    log_info "Total backup size: $total_size"
else
    log_error "Backup failed!"
    exit 1
fi

log_info "========================================="
log_info "Backup process completed"
log_info "========================================="
