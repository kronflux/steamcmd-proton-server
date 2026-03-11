#!/bin/bash
# Main entrypoint for steamcmd-proton-server
# This script orchestrates the entire container lifecycle

set -e

# Source shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

# Global variables
SERVER_PID=""
FIRST_RUN=false

#######################################
# MAIN ENTRYPOINT
#######################################

main() {
    log_info "========================================="
    log_info "SteamCMD Proton Server v1.0.0"
    log_info "========================================="

    # Load game preset if specified
    load_game_preset

    # Validate required environment variables
    validate_required_vars || exit 1

    # Set up signal handlers
    setup_signal_handlers

    # Validate/create directories
    validate_data_dir
    validate_game_dir

    # Check if this is first run
    if [[ ! -f "${DATA_DIR}/.initialized" ]]; then
        FIRST_RUN=true
        log_info "First run detected"
    fi
    export FIRST_RUN

    # Run initialization scripts in order
    run_init_scripts

    # Mark as initialized
    touch "${DATA_DIR}/.initialized"

    # Start the server
    start_server
}

#######################################
# INIT SCRIPT EXECUTION
#######################################

run_init_scripts() {
    local scripts=(
        "00_firstrun.sh"
        "01_steam.sh"
        "02_server.sh"
        "03_config.sh"
    )

    for script in "${scripts[@]}"; do
        local script_path="${SCRIPT_DIR}/${script}"

        if [[ -f "$script_path" ]]; then
            log_info "Running: $script"
            bash "$script_path"
        else
            log_warn "Script not found: $script"
        fi
    done
}

#######################################
# SERVER STARTUP
#######################################

start_server() {
    log_info "Starting server..."

    # Execute start.sh which handles the actual server launch
    exec "${SCRIPT_DIR}/start.sh"
}

# Run main function
main "$@"
