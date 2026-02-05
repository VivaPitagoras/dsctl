#!/usr/bin/env bash

# ==============================
# Docker Stack Control Tool
# Command: dsctl
# ==============================

# ------------------------------
# Bash/zsh requirement
# ------------------------------
if [ -z "$BASH_VERSION" ] && [ -z "$ZSH_VERSION" ]; then
    echo "Error: dsctl requires bash or zsh."
    exit 1
fi

# ------------------------------
# Configuration
# ------------------------------
SERVICES_DIR="${SERVICES_DIR:-$HOME/services}"
COMPOSE_FILE="compose.yml"
EDITOR="${EDITOR:-nano}"
MAX_DS_JOBS="${MAX_DS_JOBS:-4}"

GLOBAL_COMMANDS="help list clean dry-clean alias install"
SINGLE_ACTIONS="new del up down reload update edit env cd ls"
GROUP_ACTIONS="up down reload update"

CLR_RESET="\033[0m"
CLR_GREEN="\033[0;32m"
CLR_RED="\033[0;31m"
CLR_YELLOW="\033[0;33m"

# ------------------------------
# Helpers
# ------------------------------
_in_list() {
    local w="$1"; shift
    for i in "$@"; do
        [ "$i" = "$w" ] && return 0
    done
    return 1
}

_is_stack() { [ -f "$1/$COMPOSE_FILE" ]; }

_list_services() {
    [ -d "$SERVICES_DIR" ] || return
    for d in "$SERVICES_DIR"/*; do
        [ -d "$d" ] || continue
        basename "$d"
    done
}

_get_docker_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif docker-compose version >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo ""
    fi
}

get_service_state() {
    local svc="$1"
    local cmd=$(_get_docker_compose_cmd)

    [ -z "$cmd" ] && echo -e "${CLR_YELLOW}missing${CLR_RESET}" && return

    if $cmd ps --format '{{.Name}}' 2>/dev/null | grep -Eq "^${svc}"; then
        echo -e "${CLR_GREEN}running${CLR_RESET}"
        return
    fi

    if $cmd ps -a --format '{{.Name}}' 2>/dev/null | grep -Eq "^${svc}"; then
        echo -e "${CLR_RED}stopped${CLR_RESET}"
        return
    fi

    echo -e "${CLR_YELLOW}down${CLR_RESET}"
}

# ------------------------------
# Docker Compose wrappers
# ------------------------------
_dc_up() {
    local svc="$1"
    local cmd=$(_get_docker_compose_cmd)

    cd "$SERVICES_DIR/$svc" || return 1
    $cmd up -d
}

_dc_down() {
    local svc="$1"
    local cmd=$(_get_docker_compose_cmd)

    cd "$SERVICES_DIR/$svc" || return 1
    $cmd down
}

_dc_reload() {
    local svc="$1"
    _dc_down "$svc" && _dc_up "$svc"
}

_dc_update() {
    local svc="$1"
    local cmd=$(_get_docker_compose_cmd)

    cd "$SERVICES_DIR/$svc" || return 1
    $cmd pull && $cmd up -d
}

# ------------------------------
# Parallel execution
# ------------------------------
_run_parallel() {
    local cmd="$1"; shift
    local jobs=0
    declare -A results

    for svc in "$@"; do
        (
            eval "$cmd \"$svc\""
        ) &
        results[$!]="$svc"
        jobs=$((jobs + 1))

        if [ "$jobs" -ge "$MAX_DS_JOBS" ]; then
            wait
            jobs=0
        fi
    done

    for pid in "${!results[@]}"; do
        wait "$pid"
        local exit_code=$?
        local svc="${results[$pid]}"

        if [ "$exit_code" -eq 0 ]; then
            echo -e "[${CLR_GREEN}$svc${CLR_RESET}] ✅ success"
        else
            echo -e "[${CLR_RED}$svc${CLR_RESET}] ❌ failed"
        fi
    done
}

# ------------------------------
# Install function (FIXED)
# ------------------------------
_dsctl_install() {

    local target_dir="$HOME/.local/bin"
    local target_file="$target_dir/dsctl"

    # Correct script path whether sourced or executed
    local SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"

    echo "Installing dsctl..."
    echo "Script source: $SCRIPT_PATH"
    echo "Target:        $target_file"

    mkdir -p "$target_dir"
    cp "$SCRIPT_PATH" "$target_file"
    chmod +x "$target_file"

    # Pick correct shell rc file
    local shell_rc="$HOME/.bashrc"
    [ -n "$ZSH_VERSION" ] && shell_rc="$HOME/.zshrc"

    # Add source line if missing
    if ! grep -Fxq "source $target_file" "$shell_rc"; then
        echo "" >> "$shell_rc"
        echo "# dsctl setup" >> "$shell_rc"
        echo "source $target_file" >> "$shell_rc"
    fi

    echo "✅ Installed successfully!"
    echo ""
    echo "Now run:"
    echo "  source $shell_rc"
    echo "Then use:"
    echo "  dsctl list"
}

# ------------------------------
# Main dsctl command
# ------------------------------
dsctl() {

    local argc=$#
    local arg1="$1"
    local arg2="$2"

    local target action services

    # Global commands
    if [ "$argc" -ge 1 ] && [ "$arg1" = "install" ]; then
        _dsctl_install
        return
    fi

    if [ "$argc" -eq 1 ]; then
        action="$arg1"
    elif [ "$argc" -eq 2 ]; then
        target="$arg1"
        action="$arg2"
    else
        action="help"
    fi

    case "$action" in
        help)
            echo "Usage:"
            echo "  dsctl list"
            echo "  dsctl <service> up|down|reload|update"
            echo "  dsctl all up|down|reload|update"
            echo "  dsctl install"
            return
            ;;

        list)
            for svc in $(_list_services); do
                printf " - %-20s [%b]\n" "$svc" "$(get_service_state "$svc")"
            done
            return
            ;;
    esac

    # Service selection
    if [ "$target" = "all" ] || [ "$target" = "a" ]; then
        services=$(_list_services)
    else
        services="$target"
    fi

    case "$action" in
        up)     _run_parallel "_dc_up"     $services ;;
        down)   _run_parallel "_dc_down"   $services ;;
        reload) _run_parallel "_dc_reload" $services ;;
        update) _run_parallel "_dc_update" $services ;;
        *)
            echo "Unknown action: $action"
            ;;
    esac
}

# ======================================================
# ✅ AUTO-RUN FIX
# Only run dsctl if script is executed directly
# ======================================================
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    dsctl "$@"
fi
