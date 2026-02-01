#!/usr/bin/env bash

# ==============================
# Docker Stack Control Tool
# Command: dsctl
# ==============================

# ------------------------------
# Bash requirement
# ------------------------------
if [ -z "$BASH_VERSION" ]; then
    echo "Error: dsctl requires bash."
    return 1 2>/dev/null || exit 1
fi

# ------------------------------
# Configuration
# ------------------------------
SERVICES_DIR="$HOME/services"
COMPOSE_FILE="compose.yml"
EDITOR="${EDITOR:-nano}"
MAX_DS_JOBS="${MAX_DS_JOBS:-4}"

# ------------------------------
# Command definitions
# ------------------------------
GLOBAL_COMMANDS="help list clean dry-clean command-conflict"
SINGLE_ACTIONS="new del up down reload update edit env cd ls"
GROUP_ACTIONS="up down reload update"

# ------------------------------
# Colors
# ------------------------------
CLR_RESET="\033[0m"
CLR_GREEN="\033[0;32m"
CLR_RED="\033[0;31m"
CLR_YELLOW="\033[0;33m"
CLR_GRAY="\033[0;90m"

# ------------------------------
# Helpers
# ------------------------------
_in_list() {
    local word="$1"; shift
    for i in "$@"; do
        [ "$i" = "$word" ] && return 0
    done
    return 1
}

_is_stack() {
    [ -f "$1/$COMPOSE_FILE" ]
}

_list_services() {
    [ -d "$SERVICES_DIR" ] || return
    for d in "$SERVICES_DIR"/*; do
        [ -d "$d" ] || continue
        basename "$d"
    done
}

# ------------------------------
# Robust service state detection
# ------------------------------
get_service_state() {
    local svc="$1"

    # Check running containers (prefix match)
    if docker ps --format '{{.Names}}' | grep -Eq "^${svc}($|[_-])"; then
        echo -e "${CLR_GREEN}running${CLR_RESET}"
        return
    fi

    # Check stopped containers (prefix match)
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${svc}($|[_-])"; then
        echo -e "${CLR_RED}stopped${CLR_RESET}"
        return
    fi

    # No containers found
    echo -e "${CLR_YELLOW}down${CLR_RESET}"
}

_run_parallel() {
    local cmd="$1"; shift
    local jobs=0

    for svc in "$@"; do
        (
            cd "$SERVICES_DIR/$svc" || exit
            eval "$cmd"
        ) &
        jobs=$((jobs + 1))
        [ "$jobs" -ge "$MAX_DS_JOBS" ] && wait && jobs=0
    done
    wait
}

# ------------------------------
# Command conflict check
# ------------------------------
_ds_check_conflict() {
    if type ds >/dev/null 2>&1 && ! declare -F ds >/dev/null; then
        echo "Warning: a command named 'ds' already exists."
        read -r -p "Alias dsctl to 'ds'? [y/N] " ans
        case "$ans" in
            y|Y) alias ds=dsctl ;;
        esac
    fi
}

# ------------------------------
# Main command
# ------------------------------
dsctl() {
    local argc=$#
    local arg1="$1"
    local arg2="$2"
    local target action services

    # --------------------------
    # Global commands (1 arg)
    # --------------------------
    if [ "$argc" -eq 1 ]; then
        if _in_list "$arg1" $GLOBAL_COMMANDS; then
            action="$arg1"
        else
            echo "Unknown command: $arg1"
            return 1
        fi
    fi

    # --------------------------
    # Target + action (2 args)
    # --------------------------
    if [ "$argc" -eq 2 ]; then
        target="$arg1"
        action="$arg2"

        case "$target" in
            all|a) target="ALL" ;;
        esac
    fi

    # --------------------------
    # Invalid usage
    # --------------------------
    if [ "$argc" -eq 0 ] || [ "$argc" -gt 2 ]; then
        action="help"
    fi

    # --------------------------
    # Global actions
    # --------------------------
    case "$action" in
        help)
            echo "Single target:"
            echo "  dsctl <service> {new|del|up|down|reload|update|edit|env|cd|ls}"
            echo
            echo "Group target:"
            echo "  dsctl {all|a} {up|down|reload|update}"
            echo
            echo "Other:"
            echo "  dsctl list"
            echo "  dsctl clean"
            echo "  dsctl dry-clean"
            echo "  dsctl command-conflict"
            return
            ;;
        list)
            for svc in $(_list_services); do
                printf " - %-20s [%b]\n" "$svc" "$(get_service_state "$svc")"
            done
            return
            ;;
        dry-clean)
            echo "Non-stack folders detected:"
            for d in "$SERVICES_DIR"/*; do
                [ -d "$d" ] || continue
                _is_stack "$d" || echo " - $d"
            done
            return
            ;;
        clean)
            local found=0
            echo "Non-stack folders detected:"
            for d in "$SERVICES_DIR"/*; do
                [ -d "$d" ] || continue
                if ! _is_stack "$d"; then
                    echo " - $d"
                    found=1
                fi
            done
            [ "$found" -eq 0 ] && echo "(none)" && return
            read -r -p "Delete these folders? [y/N] " ans
            case "$ans" in
                y|Y)
                    for d in "$SERVICES_DIR"/*; do
                        [ -d "$d" ] || continue
                        _is_stack "$d" || rm -rf "$d"
                    done
                    ;;
            esac
            return
            ;;
        command-conflict)
            _ds_check_conflict
            return
            ;;
    esac

    # --------------------------
    # Resolve services
    # --------------------------
    if [ "$target" = "ALL" ]; then
        services=$(_list_services)
    else
        services="$target"
    fi

    # --------------------------
    # Service actions
    # --------------------------
    case "$action" in
        up|down|reload|update)
            _run_parallel "docker compose $action -d" $services
            ;;
        edit)
            [ "$target" = "ALL" ] && { echo "edit is single-target only"; return; }
            $EDITOR "$SERVICES_DIR/$target/$COMPOSE_FILE"
            ;;
        env)
            [ "$target" = "ALL" ] && { echo "env is single-target only"; return; }
            [ -f "$SERVICES_DIR/$target/$COMPOSE_FILE" ] || return
            $EDITOR "$SERVICES_DIR/$target/.env"
            ;;
        cd)
            [ "$target" = "ALL" ] && { echo "cd is single-target only"; return; }
            cd "$SERVICES_DIR/$target" || return
            ;;
        ls)
            [ "$target" = "ALL" ] && { echo "ls is single-target only"; return; }
            local svc_dir="$SERVICES_DIR/$target"
            if [ ! -d "$svc_dir" ]; then
                echo "Service folder '$target' does not exist."
                return
            fi
            echo "Contents of $svc_dir:"
            ls -lah "$svc_dir"
            ;;
        new)
            [ "$target" = "ALL" ] && { echo "new is single-target only"; return; }
            mkdir -p "$SERVICES_DIR/$target"
            $EDITOR "$SERVICES_DIR/$target/$COMPOSE_FILE"
            ;;
        del)
            [ "$target" = "ALL" ] && { echo "del is single-target only"; return; }
            rm -rf "$SERVICES_DIR/$target"
            ;;
        *)
            echo "Unknown action: $action"
            ;;
    esac
}

# Run conflict check when sourced
_ds_check_conflict
