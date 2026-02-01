# Docker Stack CLI (`dsctl`)
Bash script for QoL improvements managing docker stacks from the CLI

`dsctl` is a lightweight shell helper to manage multiple Docker Compose stacks located in a single directory (`$HOME/services` by default). It allows you to start, stop, reload, update, edit, and inspect Docker stacks with a simple command interface.

---

## Installation

1. Copy the `dsctl.sh` script to a directory in your PATH, for example:

```sh
mkdir -p $HOME/.local/bin
cp dsctl.sh $HOME/.local/bin/dsctl
```

2. Source it in your shell configuration file (`~/.bashrc` or `~/.zshrc`):

```sh
source $HOME/.local/bin/dsctl
```

3. Reload your shell:

```sh
source ~/.bashrc   # or ~/.zshrc
```

---

## Configuration

- **Services directory**: `$HOME/services` (default).  
- **Compose file name**: `compose.yml` (default, can override via `COMPOSE_FILE`).  
- **Editor**: defaults to `nano` (can override via `EDITOR`).  
- **Parallel jobs**: maximum parallel operations via `MAX_DS_JOBS` (default: 4).

---

## Usage

```sh
dsctl <service|*> <action>
```

### 1. Single target commands

| Command  | Usage                   | Explanation |
|----------|------------------------|-------------|
| new      | dsctl \<service> new     | Create a new service folder and compose file, then open it in the editor. |
| del      | dsctl \<service> del     | Delete the service folder and all its contents. |
| up       | dsctl \<service> up      | Start the service in detached mode (`docker compose up -d`). |
| down     | dsctl \<service> down    | Stop the service (`docker compose down`). |
| reload   | dsctl \<service> reload  | Restart the service (`down` + `up`). |
| update   | dsctl \<service> update  | Pull latest images and restart the service; prune unused images. |
| edit     | dsctl \<service> edit    | Open the compose file in the configured editor. |
| env      | dsctl \<service> env     | Open or create a `.env` file for the service in the editor. |
| cd       | dsctl \<service> cd      | Change directory to the service folder. |

---

### 2. Group target commands (`*`)

| Command | Usage            | Explanation |
|---------|-----------------|-------------|
| up      | dsctl * up     | Start all services in parallel. |
| down    | dsctl * down   | Stop all services in parallel. |
| reload  | dsctl * reload | Restart all services in parallel. |
| update  | dsctl * update | Pull images and restart all services in parallel. |
| prune   | dsctl * prune  | Remove unused Docker images after updating all services. |


---

### 3. Other commands

| Command          | Usage                   | Explanation |
|-----------------|------------------------|-------------|
| list             | dsctl list              | Show all service folders and their current status (`running`, `stopped`, `down`, or `non-stack`). |
| clean            | dsctl clean             | Delete all folders that do not contain a compose file. Prompts for confirmation. |
| dry-clean        | dsctl dry-clean         | Show all non-stack folders without deleting them. |
| help             | dsctl help              | Show usage information. |
| command-conflict | dsctl command-conflict  | Check if another command named `ds` exists and optionally alias `dsctl` to `ds`. |
