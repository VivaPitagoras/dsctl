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
_in_list() { local w="$1"; shift; for i in "$@"; do [ "$i" = "$w" ] && return 0; done; return 1; }
_is_stack() { [ -f "$1/$COMPOSE_FILE" ]; }
_list_services() { [ -d "$SERVICES_DIR" ] || return; for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; basename "$d"; done; }
_get_docker_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif docker-compose version >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo ""
    fi
}

# ------------------------------
# Get service state
# ------------------------------
_get_service_state_parallel() {
    local svc="$1"
    local cmd=$(_get_docker_compose_cmd)
    [ -z "$cmd" ] && echo -e "${CLR_YELLOW}missing${CLR_RESET}" && return

    if [ ! -f "$SERVICES_DIR/$svc/$COMPOSE_FILE" ]; then
        echo -e "${CLR_YELLOW}down${CLR_RESET}"
        return
    fi

    (
        cd "$SERVICES_DIR/$svc" 2>/dev/null || exit 1
        local running_count stopped_count
        running_count=$($cmd ps --filter "status=running" --format '{{.Name}}' 2>/dev/null | wc -l)
        stopped_count=$($cmd ps --filter "status=exited" --format '{{.Name}}' 2>/dev/null | wc -l)

        if [ "$running_count" -gt 0 ]; then
            echo -e "${CLR_GREEN}running${CLR_RESET}"
        elif [ "$stopped_count" -gt 0 ]; then
            echo -e "${CLR_RED}stopped${CLR_RESET}"
        else
            echo -e "${CLR_YELLOW}down${CLR_RESET}"
        fi
    )
}

# ------------------------------
# Docker Compose wrappers
# ------------------------------
_dc_up() { local svc="$1"; local cmd=$(_get_docker_compose_cmd); cd "$SERVICES_DIR/$svc" || return 1; $cmd up -d; }
_dc_down() { local svc="$1"; local cmd=$(_get_docker_compose_cmd); cd "$SERVICES_DIR/$svc" || return 1; $cmd down; }
_dc_reload() { local svc="$1"; _dc_down "$svc" && _dc_up "$svc"; }
_dc_update() { local svc="$1"; local cmd=$(_get_docker_compose_cmd); cd "$SERVICES_DIR/$svc" || return 1; $cmd pull && $cmd up -d; }

# ------------------------------
# Parallel execution helper
# ------------------------------
_run_parallel_live() {
    local cmd="$1"; shift
    local services=("$@")
    declare -A BEFORE AFTER
    declare -A PIDS

    # Capture BEFORE states
    for svc in "${services[@]}"; do
        BEFORE["$svc"]=$(_get_service_state_parallel "$svc" | sed "s/\x1b\[[0-9;]*m//g")
        AFTER["$svc"]="${BEFORE[$svc]}"
    done

    # Launch jobs
    for svc in "${services[@]}"; do
        (
            eval "$cmd \"$svc\""
        ) &
        PIDS[$!]="$svc"
    done

    # Live table
    while [ "${#PIDS[@]}" -gt 0 ]; do
        for pid in "${!PIDS[@]}"; do
            svc="${PIDS[$pid]}"
            if ! kill -0 "$pid" 2>/dev/null; then
                wait "$pid"
                AFTER["$svc"]=$(_get_service_state_parallel "$svc" | sed "s/\x1b\[[0-9;]*m//g")
                unset PIDS[$pid]
            fi
        done
        # Clear and redraw
        printf "\033[H\033[2J"  # clear screen
        printf "%-22s %-12s %-12s\n" "SERVICE" "BEFORE" "AFTER"
        printf "%-22s %-12s %-12s\n" "----------------------" "---------" "---------"
        for svc in "${services[@]}"; do
            local after_color
            case "${AFTER[$svc]}" in
                running) after_color="${CLR_GREEN}running${CLR_RESET}" ;;
                stopped) after_color="${CLR_RED}stopped${CLR_RESET}" ;;
                down) after_color="${CLR_YELLOW}down${CLR_RESET}" ;;
                *) after_color="${AFTER[$svc]}" ;;
            esac
            printf "%-22s %-12s %-12b\n" "$svc" "${BEFORE[$svc]}" "$after_color"
        done
        sleep 0.3
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
            [ -n "$existing" ] && sed -i "/^alias $existing=.*$/d" "$alias_file" && unalias "$existing" 2>/dev/null && echo "Alias removed: $existing" || echo "No alias found."
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
            # parallel
            for svc in "${services[@]}"; do
                _get_service_state_parallel "$svc" &
                STATE["$svc"]=$!
            done
            # wait and collect
            for svc in "${services[@]}"; do
                wait "${STATE[$svc]}"
                STATE["$svc"]=$(_get_service_state_parallel "$svc")
            done

            printf "\n%-22s %-12s\n" "SERVICE" "STATE"
            printf "%-22s %-12s\n" "----------------------" "------------"
            for svc in "${services[@]}"; do
                printf "%-22s %-12b\n" "$svc" "${STATE[$svc]}"
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

    # ------------------------------
    # All-stack actions with live table
    # ------------------------------
    if _in_list "$action" up down reload update && ([ "$target" = "all" ] || [ "$target" = "a" ]); then
        case "$action" in
            up) _run_parallel_live "_dc_up" $services ;;
            down) _run_parallel_live "_dc_down" $services ;;
            reload) _run_parallel_live "_dc_reload" $services ;;
            update) _run_parallel_live "_dc_update" $services ;;
        esac
        return
    fi

    # ------------------------------
    # Single service actions
    # ------------------------------
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
            [ "$confirm" = "$target" ] && { rm -rf "$SERVICES_DIR/$target"; echo -e "[${CLR_GREEN}$target${CLR_RESET}] ✅ deleted"; } || echo "Cancelled."
            ;;
        *) echo "Unknown action: $action" ;;
    esac
}

# ------------------------------
# Auto-run if executed directly
# ------------------------------
[[ "${BASH_SOURCE[0]}" == "$0" ]] && dsctl "$@"
