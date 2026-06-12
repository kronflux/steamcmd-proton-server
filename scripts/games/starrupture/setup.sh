#!/bin/bash
# Star Rupture module — hook functions sourced by load_game_module().

game_configure() { generate_starrupture_config; }

game_args() {
    local a="-Log -nosound -Port=${GAME_PORT:-7777} -QueryPort=${QUERY_PORT:-27015} -ServerName=\"${SERVER_NAME}\" -MULTIHOME=0.0.0.0"
    if [[ "${SR_DISABLE_WEB_CONTROL:-true}" == "true" ]]; then
        a="${a} -RCWebControlDisable"
    fi
    if [[ "${SR_DISABLE_WEB_INTERFACE:-true}" == "true" ]]; then
        a="${a} -RCWebInterfaceDisable"
    fi
    echo "$a"
}

game_healthcheck() {
    local query_port="${QUERY_PORT:-27015}"
    if command -v nc &> /dev/null; then
        if nc -z -u -w 2 127.0.0.1 "$query_port" 2>/dev/null; then
            log_debug "Health check: Star Rupture query port responsive"
        else
            log_warn "Health check: Star Rupture query port not responding"
        fi
    fi
}

# --- moved from scripts/03_config.sh (persist-helper refactor applied) ---

# Star Rupture Configuration
generate_starrupture_config() {
    log_info "Generating Star Rupture configuration..."

    local config_dir="${DATA_DIR}/config"
    local saves_dir="${DATA_DIR}/saves"
    local ds_settings="${GAME_DIR}/DSSettings.txt"

    mkdir -p "${config_dir}" "${saves_dir}"

    # ---- DSSettings.txt ----
    # Config file lives in /data/config/; the game path is a symlink back to it.
    persist_file "${ds_settings}" "${config_dir}/DSSettings.txt"

    # Generate from environment variables if no config exists yet
    if [[ ! -f "${config_dir}/DSSettings.txt" ]]; then
        local start_new_val
        case "${SR_START_NEW_GAME:-false}" in true|True|TRUE|1|yes) start_new_val="true" ;; *) start_new_val="false" ;; esac
        local load_saved_val
        case "${SR_LOAD_SAVED_GAME:-true}" in false|False|FALSE|0|no) load_saved_val="false" ;; *) load_saved_val="true" ;; esac

        cat > "${config_dir}/DSSettings.txt" << EOF
{
  "SessionName": "${SR_SESSION_NAME:-StarRuptureServer}",
  "SaveGameInterval": "${SR_SAVE_INTERVAL:-300}",
  "StartNewGame": "${start_new_val}",
  "LoadSavedGame": "${load_saved_val}",
  "SaveGameName": "${SR_SAVE_GAME_NAME:-AutoSave0.sav}"
}
EOF
        log_success "Generated DSSettings.txt"
    else
        log_info "Using existing DSSettings.txt from ${config_dir}/"
    fi

    local game_saves="${GAME_DIR}/StarRupture/Saved/SaveGames"

    # ---- SaveGames directory ----
    persist_dir "${game_saves}" "${saves_dir}"

    log_info "Config: ${config_dir}/"
    log_info "Saves:  ${saves_dir}/"
}
