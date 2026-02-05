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

SINGLE_ACTIONS="new del up down reload update edit env cd ls"
GLOBAL_COMMANDS="help list clean dry-clean alias install"

CLR_RESET="\033[0m"
CLR_GREEN="\033[0;32m"
CLR_RED="\033[0;31m"
CLR_YELLOW="\033[0;33m"

# ------------------------------
# Detect Docker Compose once
# ------------------------------
DOCKER_COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif docker-compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "Error: docker-compose not found"
    exit 1
fi

# ------------------------------
# Helpers
# ------------------------------
_in_list() { local w="$1"; shift; for i in "$@"; do [ "$i" = "$w" ] && return 0; done; return 1; }
_is_stack() { [ -f "$1/$COMPOSE_FILE" ]; }
_list_services() { [ -d "$SERVICES_DIR" ] || return; for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; basename "$d"; done; }
_colorize_state() {
    case "$1" in
        running) echo -e "${CLR_GREEN}running${CLR_RESET}" ;;
        stopped) echo -e "${CLR_RED}stopped${CLR_RESET}" ;;
        down) echo -e "${CLR_YELLOW}down${CLR_RESET}" ;;
        *) echo "$1" ;;
    esac
}

# ------------------------------
# Docker Compose wrapper
# ------------------------------
_dc_exec() {
    local svc="$1"
    local action="$2"
    cd "$SERVICES_DIR/$svc" || { echo "[${CLR_RED}$svc${CLR_RESET}] ❌ cannot enter directory"; return 1; }
    case "$action" in
        up) $DOCKER_COMPOSE_CMD up -d ;;
        down) $DOCKER_COMPOSE_CMD down ;;
        reload) $DOCKER_COMPOSE_CMD down && $DOCKER_COMPOSE_CMD up -d ;;
        update) $DOCKER_COMPOSE_CMD pull && $DOCKER_COMPOSE_CMD up -d ;;
    esac
}

# ------------------------------
# Get service state
# ------------------------------
_get_service_state_parallel() {
    local svc="$1"
    if [ ! -f "$SERVICES_DIR/$svc/$COMPOSE_FILE" ]; then
        echo "down"
        return
    fi
    cd "$SERVICES_DIR/$svc" 2>/dev/null || { echo "down"; return; }
    local running_count stopped_count
    running_count=$($DOCKER_COMPOSE_CMD ps --filter "status=running" --format '{{.Name}}' 2>/dev/null | wc -l)
    stopped_count=$($DOCKER_COMPOSE_CMD ps --filter "status=exited" --format '{{.Name}}' 2>/dev/null | wc -l)
    if [ "$running_count" -gt 0 ]; then
        echo "running"
    elif [ "$stopped_count" -gt 0 ]; then
        echo "stopped"
    else
        echo "down"
    fi
}

# ------------------------------
# Parallel execution
# ------------------------------
_run_parallel() {
    local cmd="$1"; shift
    local jobs=0
    local svc exit_code
    declare -A results
    for svc in "$@"; do
        ( eval "$cmd \"$svc\"" ) &
        results[$!]="$svc"
        jobs=$((jobs + 1))
        [ "$jobs" -ge "$MAX_DS_JOBS" ] && wait && jobs=0
    done
    for pid in "${!results[@]}"; do
        wait "$pid"
        exit_code=$?
        svc="${results[$pid]}"
        if [ "$exit_code" -eq 0 ]; then
            echo -e "[${CLR_GREEN}$svc${CLR_RESET}] ✅ success"
        else
            echo -e "[${CLR_RED}$svc${CLR_RESET}] ❌ failed (exit $exit_code)"
        fi
    done
}

# ------------------------------
# Alias management
# ------------------------------
_ds_alias_persistent() {
    local action="$1"
    local alias_file="$HOME/.bash_aliases"
    touch "$alias_file"
    case "$action" in
        off)
            sed -i "/^alias .*?=dsctl$/d" "$alias_file"
            unalias $(grep -E '^alias .*?=dsctl$' "$alias_file" | awk -F= '{print $1}' | sed 's/alias //') 2>/dev/null
            echo "Alias removed"
            ;;
        status)
            grep -E '^alias .*?=dsctl$' "$alias_file" || echo "No persistent alias set."
            ;;
        *)
            [ -z "$action" ] && { echo "Usage: dsctl alias <name>|off|status"; return 1; }
            sed -i "/^alias .*?=dsctl$/d" "$alias_file"
            echo "alias $action=dsctl" >> "$alias_file"
            alias "$action"=dsctl
            echo "Alias added: $action → dsctl"
            ;;
    esac
}

# ------------------------------
# Autocomplete
# ------------------------------
_dsctl_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local services
    services=$(_list_services)
    local actions="up down reload update edit env cd ls new del"
    local globals="help list clean dry-clean alias install"

    if [ $COMP_CWORD -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$globals all a $services" -- "$cur") )
        return 0
    fi
    if [ $COMP_CWORD -eq 2 ]; then
        COMPREPLY=( $(compgen -W "$actions" -- "$cur") )
        return 0
    fi
}

[ -n "$BASH_VERSION" ] && complete -F _dsctl_completion dsctl 2>/dev/null
[ -n "$ZSH_VERSION" ] && { autoload -Uz compinit; compinit; compdef _dsctl_completion dsctl; }

# ------------------------------
# Installer
# ------------------------------
_dsctl_install() {
    local target_dir="$HOME/.local/bin"
    local target_file="$target_dir/dsctl"
    local SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"

    mkdir -p "$target_dir"
    cp "$SCRIPT_PATH" "$target_file"
    chmod +x "$target_file"

    local shell_rc="$HOME/.bashrc"
    [ -n "$ZSH_VERSION" ] && shell_rc="$HOME/.zshrc"

    if ! grep -Fxq "source $target_file" "$shell_rc"; then
        echo "" >> "$shell_rc"
        echo "# dsctl setup" >> "$shell_rc"
        echo "source $target_file" >> "$shell_rc"
        echo "Added dsctl to $shell_rc"
    fi

    echo -e "\n✅ Installed successfully!"
    [[ "${BASH_SOURCE[0]}" != "$0" ]] && source "$shell_rc"
}

# ------------------------------
# Main dsctl
# ------------------------------
dsctl() {
    local argc=$#
    local arg1="$1"
    local arg2="$2"
    local target action services

    [ "$arg1" = "install" ] && { _dsctl_install; return; }
    [ "$arg1" = "alias" ] && { _ds_alias_persistent "$arg2"; return; }

    [ "$argc" -eq 1 ] && action="$arg1"
    [ "$argc" -eq 2 ] && { target="$arg1"; action="$arg2"; }
    [ "$argc" -eq 0 ] && action="help"

    case "$action" in
        help)
            echo "Usage:"
            echo "  dsctl list"
            echo "  dsctl <service> up|down|reload|update|del"
            echo "  dsctl all up|down|reload|update"
            echo "  dsctl clean / dry-clean"
            echo "  dsctl alias <name>|off|status"
            echo "  dsctl install"
            return
            ;;
        list)
            local services=($(_list_services))
            declare -A STATE
            # Parallel safe & clean (no background job messages)
            for svc in "${services[@]}"; do
                STATE["$svc"]=$(_get_service_state_parallel "$svc")  # simple sequential
            done

            printf "\n%-22s %-12s\n" "SERVICE" "STATE"
            printf "%-22s %-12s\n" "----------------------" "------------"
            for svc in "${services[@]}"; do
                printf "%-22s %-12b\n" "$svc" "$(_colorize_state "${STATE[$svc]}")"
            done
            echo ""
            return
            ;;
        dry-clean)
            echo "Non-stack folders:"
            for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; _is_stack "$d" || echo " - $(basename "$d")"; done
            return
            ;;
        clean)
            for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; _is_stack "$d" || rm -rf "$d"; done
            echo "Cleaned."; return
            ;;
    esac

    [ "$target" = "all" ] || [ "$target" = "a" ] && services=$(_list_services) || services="$target"

    # All-stack actions
    if _in_list "$action" up down reload update && ([ "$target" = "all" ] || [ "$target" = "a" ]); then
        for svc in $services; do
            _dc_exec "$svc" "$action"
        done
        return
    fi

    # Single service actions
    case "$action" in
        up|down|reload|update) _dc_exec "$target" "$action" ;;
        edit) $EDITOR "$SERVICES_DIR/$target/$COMPOSE_FILE" ;;
        env) $EDITOR "$SERVICES_DIR/$target/.env" ;;
        cd) cd "$SERVICES_DIR/$target" || return ;;
        ls) ls -lah "$SERVICES_DIR/$target" ;;
        new) mkdir -p "$SERVICES_DIR/$target" && $EDITOR "$SERVICES_DIR/$target/$COMPOSE_FILE" ;;
        del)
            [ ! -d "$SERVICES_DIR/$target" ] && { echo "Service '$target' not found."; return; }
            echo -e "${CLR_RED}⚠ WARNING:${CLR_RESET} This will permanently delete: $SERVICES_DIR/$target"
            read -r -p "Type '$target' to confirm deletion: " confirm
            [ "$confirm" = "$target" ] && { rm -rf "$SERVICES_DIR/$target"; echo -e "[${CLR_GREEN}$target${CLR_RESET}] ✅ deleted"; } || echo "Cancelled."
            ;;
        *) echo "Unknown action: $action" ;;
    esac
}

# ------------------------------
# Auto-run if executed directly
# ------------------------------
[[ "${BASH_SOURCE[0]}" == "$0" ]] && dsctl "$@"
