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
# Parallel Execution
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
        [ "$jobs" -ge "$MAX_DS_JOBS" ] && wait && jobs=0
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
# Persistent alias
# ------------------------------
_ds_alias_persistent() {
    local action="$1"
    local alias_file="$HOME/.bash_aliases"
    touch "$alias_file"

    case "$action" in
        off)
            local existing
            existing=$(grep -E '^alias .*?=dsctl$' "$alias_file" | awk -F'=' '{print $1}' | sed 's/alias //')
            if [ -n "$existing" ]; then
                sed -i "/^alias $existing=.*$/d" "$alias_file"
                unalias "$existing" 2>/dev/null
                echo "Alias removed: $existing"
            else
                echo "No alias found."
            fi
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
# Autocomplete (bash + zsh)
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

if [ -n "$BASH_VERSION" ]; then
    complete -F _dsctl_completion dsctl 2>/dev/null
fi

if [ -n "$ZSH_VERSION" ]; then
    autoload -Uz compinit
    compinit
    compdef _dsctl_completion dsctl
fi

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
    if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
        echo "✨ Sourced install → activating now..."
        source "$shell_rc"
        echo "dsctl is now active."
    else
        echo "Run this to activate:"
        echo "  source $shell_rc"
        echo "or open a new terminal."
    fi
}

# ------------------------------
# Main dsctl
# ------------------------------
dsctl() {
    local argc=$#
    local arg1="$1"
    local arg2="$2"
    local target action services

    if [ "$arg1" = "install" ]; then _dsctl_install; return; fi
    if [ "$arg1" = "alias" ]; then _ds_alias_persistent "$arg2"; return; fi

    if [ "$argc" -eq 1 ]; then action="$arg1"; fi
    if [ "$argc" -eq 2 ]; then target="$arg1"; action="$arg2"; fi
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
            printf "\n%-22s %-12s\n" "SERVICE" "STATE"
            printf "%-22s %-12s\n" "----------------------" "------------"
            for svc in $(_list_services); do
                state=$(get_service_state "$svc")
                printf "%-22s %-12b\n" "$svc" "$state"
            done
            echo ""; return
            ;;
        dry-clean)
            echo "Non-stack folders:"
            for d in "$SERVICES_DIR"/*; do
                [ -d "$d" ] || continue
                _is_stack "$d" || echo " - $(basename "$d")"
            done; return
            ;;
        clean)
            for d in "$SERVICES_DIR"/*; do
                [ -d "$d" ] || continue
                _is_stack "$d" || rm -rf "$d"
            done
            echo "Cleaned."; return
            ;;
    esac

    [ "$target" = "all" ] || [ "$target" = "a" ] && services=$(_list_services) || services="$target"

    case "$action" in
        up) _run_parallel "_dc_up" $services ;;
        down) _run_parallel "_dc_down" $services ;;
        reload) _run_parallel "_dc_reload" $services ;;
        update) _run_parallel "_dc_update" $services ;;

        edit) $EDITOR "$SERVICES_DIR/$target/$COMPOSE_FILE" ;;
        env) $EDITOR "$SERVICES_DIR/$target/.env" ;;
        cd) cd "$SERVICES_DIR/$target" || return ;;
        ls) ls -lah "$SERVICES_DIR/$target" ;;
        new) mkdir -p "$SERVICES_DIR/$target" && $EDITOR "$SERVICES_DIR/$target/$COMPOSE_FILE" ;;
        del)
            [ "$target" = "ALL" ] && { echo "del is single-target only"; return; }
            [ ! -d "$SERVICES_DIR/$target" ] && { echo "Service '$target' not found."; return; }
            echo -e "${CLR_RED}⚠ WARNING:${CLR_RESET} This will permanently delete: $SERVICES_DIR/$target"
            read -r -p "Type '$target' to confirm deletion: " confirm
            if [ "$confirm" = "$target" ]; then
                rm -rf "$SERVICES_DIR/$target"
                echo -e "[${CLR_GREEN}$target${CLR_RESET}] ✅ deleted"
            else
                echo "Cancelled."
            fi
            ;;
        *)
            echo "Unknown action: $action"
            ;;
    esac
}

# ------------------------------
# AUTO-RUN ONLY IF EXECUTED DIRECTLY
# ------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    dsctl "$@"
fi
