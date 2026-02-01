#!/usr/bin/env bash

# ==============================
# Docker Stack Helper (dsctl)
# ==============================
# Source this file in ~/.bashrc or ~/.zshrc
# Provides the `dsctl` command for managing multiple Docker Compose stacks

# -------- Check for Bash --------
if ! command -v bash >/dev/null 2>&1; then
echo "Error: Bash is required to run this script."
return 1 # use return so it works when sourced in shell
fi

# -------- Configuration --------
SERVICES_DIR="$HOME/services"
COMPOSE_FILE="compose.yml"
EDITOR="${EDITOR:-nano}"
MAX_DS_JOBS="${MAX_DS_JOBS:-4}"

# -------- Colors --------
CLR_RESET="\033[0m"
CLR_GREEN="\033[0;32m"
CLR_RED="\033[0;31m"
CLR_YELLOW="\033[0;33m"
CLR_GRAY="\033[0;90m"

# ==============================
# Internal helper functions
# ==============================
_is_stack() { [ -f "$1/$COMPOSE_FILE" ]; }
_list_services() { [ -d "$SERVICES_DIR" ] || return; for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; basename "$d"; done; }
_service_status() {
	local svc="$1" dir="$SERVICES_DIR/$svc"
	if ! _is_stack "$dir"; then echo -e "${CLR_GRAY}non-stack${CLR_RESET}"; return; fi
	if docker ps --format '{{.Names}}' | grep -q "^${svc}_"; then echo -e "${CLR_GREEN}running${CLR_RESET}";
	elif docker ps -a --format '{{.Names}}' | grep -q "^${svc}_"; then echo -e "${CLR_RED}stopped${CLR_RESET}";
	else echo -e "${CLR_YELLOW}down${CLR_RESET}"; fi
}
_run_parallel() { local cmd="$1"; shift; local jobs=0; for svc in "$@"; do (
	cd "$SERVICES_DIR/$svc" || exit; eval "$cmd" ) &
	jobs=$((jobs+1))
	[ "$jobs" -ge "$MAX_DS_JOBS" ] && wait && jobs=0
	done
	wait
}

# ==============================
# Main command: dsctl
# ==============================
dsctl() {
	local target="$1" action="$2"
	[ -z "$target" ] && action="help"
	[ "$target" = "*" ] && target="ALL"

	# Actions that don't require a single service
	case "$action" in
		help|"")
			echo "Usage:"
			echo "\n1. Single target commands: dsctl <target> <action>"
			echo "   Actions:"
			echo "     - new" 
			echo "     - del"
			echo "     - up"
			echo "     - down"
			echo "     - reload"
			echo "     - update"
			echo "     - edit"
			echo "     - env"
			echo "     - cd"
			echo "\n2. Group target commands: dsctl * <action>"
			echo "   Actions:"
			echo "     - up"
			echo "     - down"
			echo "     - reload"
			echo "     - update"
			echo "     - prune"
			echo "\n3. Other commands:"
			echo "     - dsctl list"
			echo "     - dsctl clean"
			echo "     - dsctl dry-clean"
			echo "     - dsctl help"
			echo "     - dsctl command-conflict"
			return
			;;

		list)
			for svc in $(_list_services); do printf " - %-20s [%b]\n" "$svc" "$(_service_status "$svc")"; done
			return
			;;

		dry-clean)
			for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; !_is_stack "$d" && echo " - $d"; done
			return
			;;

		clean)
			local found=0
			for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; !_is_stack "$d" && echo " - $d" && found=1; done
			[ "$found" -eq 0 ] && echo "(none)" && return
			read -r -p "Delete these folders? [y/N] " ans
			case "$ans" in y|Y) for d in "$SERVICES_DIR"/*; do [ -d "$d" ] || continue; !_is_stack "$d" && rm -rf "$d"; done;; esac
			return
			;;

		command-conflict)
			_ds_check_conflict
			return
			;;
	esac

	# Determine services to act on
	local services
	if [ "$target" = "ALL" ]; then services=$(_list_services); else services="$target"; fi

	# Actions that require single or multiple services
	case "$action" in
		up|down|reload|update)
			_run_parallel "docker compose $action -d" $services
			;;
		edit)
			[ "$target" = "ALL" ] && { echo "Error: edit can only be used on a single service"; return; }
			$EDITOR "$SERVICES_DIR/$target/$COMPOSE_FILE"
			;;
		env)
			[ "$target" = "ALL" ] && { echo "Error: env can only be used on a single service"; return; }
			[ -f "$SERVICES_DIR/$target/$COMPOSE_FILE" ] || return
			$EDITOR "$SERVICES_DIR/$target/.env"
			;;
		cd)
			[ "$target" = "ALL" ] && { echo "Error: cd can only be used on a single service"; return; }
			cd "$SERVICES_DIR/$target" || return
			;;
		new)
			[ "$target" = "ALL" ] && { echo "Error: new can only be used on a single service"; return; }
			mkdir -p "$SERVICES_DIR/$target"
			$EDITOR "$SERVICES_DIR/$target/$COMPOSE_FILE"
			;;
		del)
			[ "$target" = "ALL" ] && { echo "Error: del can only be used on a single service"; return; }
			rm -rf "$SERVICES_DIR/$target"
			;;
		*)
			echo "Unknown or invalid action: $action"
			;;
	esac
}

# ==============================
# Command conflict checking
# ==============================
_ds_check_conflict() {
	if type ds >/dev/null 2>&1 && ! declare -F ds >/dev/null; then
		echo "Warning: a command named 'ds' already exists."
		read -r -p "Do you want to alias dsctl to 'ds'? [y/N] " ans
		case "$ans" in y|Y) alias ds=dsctl; echo "ds alias created.";; *) echo "No alias created.";; esac
	fi
}

# Run conflict check automatically when sourced
_ds_check_conflict
