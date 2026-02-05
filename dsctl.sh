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
    return 1 2>/dev/null || exit 1
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
CLR_GRAY="\033[0;90m"

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

get_service_state() {
    local svc="$1"
    local cmd=$(_get_docker_compose_cmd)
    [ -z "$cmd" ] && echo -e "${CLR_YELLOW}docker-compose not found${CLR_RESET}" && return
    if $cmd ps --format '{{.Name}}' 2>/dev/null | grep -Eq "^${svc}($|[_-])"; then echo -e "${CLR_GREEN}running${CLR_RESET}"; return; fi
    if $cmd ps -a --format '{{.Name}}' 2>/dev/null | grep -Eq "^${svc}($|[_-])"; then echo -e "${CLR_RED}stopped${CLR_RESET}"; return; fi
    echo -e "${CLR_YELLOW}down${CLR_RESET}"
}

# ------------------------------
# Docker Compose wrapper functions
# ------------------------------
_dc_up() {
    local svc="$1"
    local cmd=$(_get_docker_compose_cmd)
    cd "$SERVICES_DIR/$svc" || { echo "[${CLR_RED}$svc${CLR_RESET}] ❌ cannot enter directory"; return 1; }
    $cmd up -d
}

_dc_down() {
    local svc="$1"
    local cmd=$(_get_docker_compose_cmd)
    cd "$SERVICES_DIR/$svc" || { echo "[${CLR_RED}$svc${CLR_RESET}] ❌ cannot enter directory"; return 1; }
    $cmd down
}

_dc_reload() {
    local svc="$1"
    _dc_down "$svc" && _dc_up "$svc"
}

_dc_update() {
    local svc="$1"
    local cmd=$(_get_docker_compose_cmd)
    cd "$SERVICES_DIR/$svc" || { echo "[${CLR_RED}$svc${CLR_RESET}] ❌ cannot enter directory"; return 1; }
    $cmd pull && $cmd up -d
}

# ------------------------------
# Parallel execution with friendly output
# ------------------------------
_run_parallel() {
    local cmd="$1"; shift
    local jobs=0
    local svc exit_code
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
# Persistent alias management
# ------------------------------
_ds_alias_persistent() {
    local action="$1"
    local alias_file="$HOME/.bash_aliases"; touch "$alias_file"
    case "$action" in
        off)
            local existing
            existing=$(grep -E '^alias .*?=dsctl$' "$alias_file" | awk -F'=' '{print $1}' | sed 's/alias //')
            if [ -n "$existing" ]; then
                sed -i "/^alias $existing=.*$/d" "$alias_file"
                unalias "$existing" 2>/dev/null
                complete -r "$existing" 2>/dev/null
                echo "Persistent alias removed: $existing"
            else echo "No alias found for dsctl"; fi
            ;;
        status)
            local existing
            existing=$(grep -E '^alias .*?=dsctl$' "$alias_file" | awk -F'=' '{print $1}' | sed 's/alias //')
            if [ -n "$existing" ]; then
                echo "Alias active in session: $(alias $existing 2>/dev/null || echo 'not set')"
                echo "Persistent in ~/.bash_aliases"
            else echo "No alias found for dsctl"; fi
            ;;
        *)
            if [ -z "$action" ]; then echo "Usage: dsctl alias <aliasname>|off|status"; return 1; fi
            sed -i "/^alias .*?=dsctl$/d" "$alias_file"
            echo "alias $action=dsctl" >> "$alias_file"
            alias "$action"=dsctl
            echo "Persistent alias added: $action → dsctl"
            complete -F _dsctl_completion "$action"
            ;;
    esac
}

# ------------------------------
# Autocomplete
# ------------------------------
_dsctl_completion() {
    local cur prev first_word services actions globals
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    first_word="${COMP_WORDS[0]}"
    if type "$first_word" >/dev/null 2>&1; then [[ $(type -t "$first_word") == "alias" ]] && first_word="dsctl"; fi
    services=$( [ -d "$SERVICES_DIR" ] && ls "$SERVICES_DIR" 2>/dev/null || echo "" )
    actions="up down reload update edit env cd ls new del"
    globals="help list clean dry-clean alias install"
    [ $COMP_CWORD -eq 1 ] && { COMPREPLY=( $(compgen -W "$globals all a $services" -- "$cur") ); return 0; }
    [ $COMP_CWORD -eq 2 ] && { 
        if [[ "${COMP_WORDS[1]}" == "all" || "${COMP_WORDS[1]}" == "a" ]]; then
            COMPREPLY=( $(compgen -W "up down reload update" -- "$cur") )
        else
            COMPREPLY=( $(compgen -W "$actions" -- "$cur") )
        fi
        return 0
    }
}

complete -F _dsctl_completion dsctl
for a in $(alias | grep 'dsctl' | awk -F'[ =]' '{print $2}'); do complete -F _dsctl_completion "$a"; done

# ------------------------------
# Interactive Install
# ------------------------------
_dsctl_install() {
    local target_dir="$HOME/.local/bin"
    local target_file="$target_dir/dsctl"
    local shell_rc

    if [ -n "$ZSH_VERSION" ]; then shell_rc="$HOME/.zshrc"; else shell_rc="$HOME/.bashrc"; fi

    echo "dsctl Install will perform:"
    echo "1. Create directory: $target_dir (if missing)"
    echo "2. Copy this script to: $target_file"
    echo "3. Make it executable"
    echo "4. Add source line to $shell_rc"
    echo "5. Enable autocomplete in current shell"
    
    local cmd=$(_get_docker_compose_cmd)
    [ -z "$cmd" ] && { echo "Error: No Docker Compose found. Install 'docker compose' or 'docker-compose' first."; return; }
    echo "Detected Docker Compose: $cmd"

    if [ ! -d "$SERVICES_DIR" ]; then
        echo "Services directory ($SERVICES_DIR) does not exist."
        read -r -p "Create it? [y/N] " ans_dir
        [[ "$ans_dir" =~ ^[yY]$ ]] && mkdir -p "$SERVICES_DIR" && echo "Created $SERVICES_DIR" || { echo "Install cancelled"; return; }
    fi

    read -r -p "Proceed with install? [y/N] " ans
    case "$ans" in
        y|Y)
            mkdir -p "$target_dir"
            cp "$BASH_SOURCE" "$target_file"
            chmod +x "$target_file"
            if ! grep -Fxq "source $target_file" "$shell_rc"; then
                echo "" >> "$shell_rc"
                echo "# dsctl setup" >> "$shell_rc"
                echo "source $target_file" >> "$shell_rc"
            fi
            source "$target_file"
            complete -F _dsctl_completion dsctl
            echo "Installed to $target_file and sourced in $shell_rc."
            echo "Autocomplete enabled."
            ;;
        *) echo "Installation cancelled";;
    esac
}

# ------------------------------
# Main dsctl function
# ------------------------------
dsctl() {
    local argc=$#
    local arg1="$1" arg2="$2"
    local target action services

    [ "$argc" -ge 1 ] && [ "$arg1" = "install" ] && { _dsctl_install; return; }
    [ "$argc" -ge 1 ] && [ "$arg1" = "alias" ] && { _ds_alias_persistent "$2"; return; }

    if [ "$argc" -eq 1 ]; then
        if _in_list "$arg1" $GLOBAL_COMMANDS; then action="$arg1"; else echo "Unknown command: $arg1"; return 1; fi
    fi
    [ "$argc" -eq 2 ] && { target="$arg1"; action="$arg2"; case "$target" in all|a) target="ALL";; esac; }
    [ "$argc" -eq 0 ] || [ "$argc" -gt 2 ] && action="help"

    case "$action" in
        help)
            echo "Single target: dsctl <service> {new|del|up|down|reload|update|edit|env|cd|ls}"
            echo "Group target: dsctl {all|a} {up|down|reload|update}"
            echo "Other: dsctl list, clean, dry-clean, alias <name>|off|status, install"
            return;;
        list)
            for svc in $(_list_services); do printf " - %-20s [%b]\n" "$svc" "$(get_service_state "$svc")"; done; return;;
        dry-clean)
            echo "Non-stack folders:"; for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; _is_stack "$d" || echo " - $d"; done; return;;
        clean)
            local found=0; echo "Non-stack folders:"; for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; _is_stack "$d" || { echo " - $d"; found=1; }; done
            [ "$found" -eq 0 ] && echo "(none)" && return
            read -r -p "Delete these folders? [y/N] " ans; case "$ans" in y|Y) for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; _is_stack "$d" || rm -rf "$d"; done;; esac
            return;;
    esac

    [ "$target" = "ALL" ] && services=$(_list_services) || services="$target"

    case "$action" in
        up) _run_parallel "_dc_up" $services ;;
        down) _run_parallel "_dc_down" $services ;;
        reload) _run_parallel "_dc_reload" $services ;;
        update) _run_parallel "_dc_update" $services ;;
        edit) [ "$target" = "ALL" ] && { echo "edit is single-target only"; return; }; $EDITOR "$SERVICES_DIR/$target/$COMPOSE_FILE" ;;
        env) [ "$target" = "ALL" ] && { echo "env is single-target only"; return; }; [ -f "$SERVICES_DIR/$target/$COMPOSE_FILE" ] || return; $EDITOR "$SERVICES_DIR/$target/.env" ;;
        cd) [ "$target" = "ALL" ] && { echo "cd is single-target only"; return; }; cd "$SERVICES_DIR/$target" || return ;;
        ls) [ "$target" = "ALL" ] && { echo "ls is single-target only"; return; }; [ -d "$SERVICES_DIR/$target" ] || { echo "Service '$target' not found"; return; }; ls -lah "$SERVICES_DIR/$target" ;;
        new) [ "$target" = "ALL" ] && { echo "new is single-target only"; return; }; mkdir -p "$SERVICES_DIR/$target"; $EDITOR "$SERVICES_DIR/$target/$COMPOSE_FILE" ;;
        del) [ "$target" = "ALL" ] && { echo "del is single-target only"; return; }; rm -rf "$SERVICES_DIR/$target" ;;
        *) echo "Unknown action: $action" ;;
    esac
}
