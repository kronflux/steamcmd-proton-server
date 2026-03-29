#!/bin/bash
# Health check script for the container
# Returns 0 if healthy, 1 if unhealthy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

# Health check timeout and thresholds
HEALTH_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-120}
HEALTH_START_TIME=${HEALTH_CHECK_START_TIME:-$(date +%s)}

main() {
    # Calculate elapsed time since start
    local current_time=$(date +%s)
    local elapsed=$((current_time - HEALTH_START_TIME))

    # Skip health checks during startup grace period
    if [[ $elapsed -lt 30 ]]; then
        log_debug "Health check: Startup grace period (${elapsed}s < 30s)"
        exit 0
    fi

    # Check if server process is running
    if ! check_server_process; then
        # Also check by executable name as fallback
        if ! check_game_server; then
            log_error "Health check: No server process found"
            exit 1
        fi
    fi

    # Check if process is responsive (not stuck)
    if [[ -n "$SERVER_PID" ]]; then
        # Check CPU usage - if 0% for extended period, might be deadlocked
        local cpu_usage=$(ps -p $SERVER_PID -o %cpu= 2>/dev/null || echo "0")

        # Check if process is consuming memory
        local mem_usage=$(ps -p $SERVER_PID -o rss= 2>/dev/null || echo "0")

        if [[ "$cpu_usage" == "0" ]] && [[ "$mem_usage" == "0" ]]; then
            log_error "Health check: Process appears dead (0 CPU, 0 memory)"
            exit 1
        fi
    fi

    # Game-specific health checks
    case "${GAME_CONFIG:-}" in
        sons-of-the-forest)
            check_sotf_health
            ;;
        starrupture)
            check_starrupture_health
            ;;
        valheim)
            check_valheim_health
            ;;
        *)
            # Generic health check - just verify process
            log_debug "Health check: Generic (process running)"
            ;;
    esac

    log_debug "Health check: OK"
    exit 0
}

#######################################
# GAME-SPECIFIC HEALTH CHECKS
#######################################

check_sotf_health() {
    local query_port="${QUERY_PORT:-7778}"

    # Check if port is listening
    if command -v nc &> /dev/null; then
        if nc -z -u -w 2 127.0.0.1 "$query_port" 2>/dev/null; then
            log_debug "Health check: SotF query port responsive"
        else
            log_warn "Health check: SotF query port not responding"
        fi
    fi
}

check_valheim_health() {
    local game_port="${GAME_PORT:-2456}"

    # Check if port is listening
    if command -v nc &> /dev/null; then
        if nc -z -u -w 2 127.0.0.1 "$game_port" 2>/dev/null; then
            log_debug "Health check: Valheim port responsive"
        else
            log_warn "Health check: Valheim port not responding"
        fi
    fi
}

check_starrupture_health() {
    local query_port="${QUERY_PORT:-27015}"

    # Check if query port is listening
    if command -v nc &> /dev/null; then
        if nc -z -u -w 2 127.0.0.1 "$query_port" 2>/dev/null; then
            log_debug "Health check: Star Rupture query port responsive"
        else
            log_warn "Health check: Star Rupture query port not responding"
        fi
    fi
}

main "$@"
