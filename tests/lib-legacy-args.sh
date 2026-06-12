#!/bin/bash
# FROZEN replica of the launch-args construction as of commit 44c7302
# (scripts/start.sh base_args case). This is the golden baseline definition.
# DO NOT EDIT — changes here invalidate every committed args golden.

legacy_base_args() {
    local game="$1"
    case "$game" in
        sons-of-the-forest|sons-of-the-forest-modded)
            if [[ "${SOTF_VERBOSE_LOGGING:-false}" == "true" ]]; then
                echo "-verboseLogging"
            else
                echo ""
            fi
            ;;
        valheim)
            echo "-batchmode -nographics -port ${GAME_PORT:-2456} -name \"${SERVER_NAME}\" -password \"${SERVER_PASSWORD:-}\" -world \"${WORLD_NAME:-Dedicated}\" -public 1"
            ;;
        subnautica)
            echo "-batchmode -nographics"
            ;;
        dayz)
            echo "-config=server.cfg -port=${GAME_PORT:-2302}"
            ;;
        starrupture)
            local a="-Log -nosound -Port=${GAME_PORT:-7777} -QueryPort=${QUERY_PORT:-27015} -ServerName=\"${SERVER_NAME}\" -MULTIHOME=0.0.0.0"
            if [[ "${SR_DISABLE_WEB_CONTROL:-true}" == "true" ]]; then a="${a} -RCWebControlDisable"; fi
            if [[ "${SR_DISABLE_WEB_INTERFACE:-true}" == "true" ]]; then a="${a} -RCWebInterfaceDisable"; fi
            echo "$a"
            ;;
        scum)
            local a="-log -port=${GAME_PORT:-7777} -MaxPlayers=${MAX_PLAYERS:-64}"
            if [[ "${SCUM_DISABLE_BATTLEYE:-false}" == "true" ]]; then a="${a} -nobattleye"; fi
            echo "$a"
            ;;
        *)
            echo ""
            ;;
    esac
}
