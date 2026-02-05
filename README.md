# Docker Stack CLI (`dsctl`)
Bash script for QoL improvements managing docker stacks from the CLI

`dsctl` is a lightweight shell helper to manage multiple Docker Compose stacks located in a single directory (`$HOME/services` by default). It allows you to start, stop, reload, update, edit, and inspect Docker stacks with a simple command interface.

---

## Installation

1. Download `dsctl.sh`
2. Make it executable:

```sh
chmod +x dsctl.sh
```
3. Install

```sh
./dsctl.sh install
```

### What happens then?:

### 1️⃣ Explain the steps

Before making any changes, the script will show a summary of actions:

- Create the directory `$HOME/.local/bin` if it doesn’t exist.
- Copy `dsctl.sh` to `$HOME/.local/bin/dsctl`.
- Make the script executable.
- Add a `source` line to your shell configuration (`~/.bashrc` or `~/.zshrc`).
- Enable autocompletion for `dsctl`.
- Check for Docker Compose (`docker compose` or `docker-compose`).
- Optionally create the services folder (default: `$HOME/services`).

### 2️⃣ Ask for user confirmation

The script prompts:

```text
Proceed with install? [y/N]
```

- **Y** → proceed with installation.
- **N** (or Enter) → cancel safely.


### 3️⃣ Create required directories

- Ensures `$HOME/.local/bin` exists for the command.
- Creates `$HOME/services` if it doesn’t exist.

### 4️⃣ Copy the script

- Copies itself to `$HOME/.local/bin/dsctl`.
- Sets executable permissions:

```bash
chmod +x $HOME/.local/bin/dsctl
```


### 5️⃣ Add source to shell configuration

- Detects your shell (`bash` or `zsh`).
- Adds this line to your shell rc file if missing:

```bash
source $HOME/.local/bin/dsctl
```

- Makes `dsctl` and autocomplete available in all new shell sessions.


### 6️⃣ Enable autocompletion

- Adds autocomplete for `dsctl` commands and services.
- Works immediately in the current shell session.


### 7️⃣ Check Docker Compose

- Detects `docker compose` or `docker-compose`.
- If neither is found, the script stops and asks you to install Docker Compose.


### 8️⃣ Finish installation

After completion, you will see:

```text
Installed to $HOME/.local/bin/dsctl and sourced in ~/.bashrc.
Autocomplete enabled.
```

- Now `dsctl` is fully ready to use.


### ✅ Result

- Run `dsctl` anywhere in your terminal.
- Autocomplete will suggest services and actions.
- You can manage services in parallel with color-coded success/failure.
- Persistent alias management is available:

```bash
dsctl alias ds       # create alias "ds"
dsctl alias off      # remove alias
dsctl alias status   # check alias status
```

- Run commands for all services or a single service:

```bash
dsctl list
dsctl all reload
dsctl romm up
dsctl romm edit
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
| new      | dsctl <service> new     | Create a new service folder and compose file, then open it in the editor. |
| del      | dsctl <service> del     | Delete the service folder and all its contents. |
| up       | dsctl <service> up      | Start the service in detached mode (`docker compose up -d`). |
| down     | dsctl <service> down    | Stop the service (`docker compose down`). |
| reload   | dsctl <service> reload  | Restart the service (`down` + `up`). |
| update   | dsctl <service> update  | Pull latest images and restart the service; prune unused images. |
| edit     | dsctl <service> edit    | Open the compose file in the configured editor. |
| env      | dsctl <service> env     | Open or create a `.env` file for the service in the editor. |
| cd       | dsctl <service> cd      | Change directory to the service folder. |
| ls       | dsctl <service> ls      | List files and folders under the service folder. |

---

### 2. Group target commands (`*` or `all`)

| Command | Usage              | Explanation |
|---------|------------------|-------------|
| up      | dsctl all up      | Start all services in parallel. |
| down    | dsctl all down    | Stop all services in parallel. |
| reload  | dsctl all reload  | Restart all services in parallel. |
| update  | dsctl all update  | Pull images and restart all services in parallel. |
| prune   | dsctl all prune   | Remove unused Docker images after updating all services. |

---

### 3. Other commands

| Command          | Usage               | Explanation |
|-----------------|-------------------|-------------|
| list             | dsctl list         | Show all service folders and their current status (`running`, `stopped`, `down`, or `non-stack`). |
| clean            | dsctl clean        | Delete all folders that do not contain a compose file. Prompts for confirmation. |
| dry-clean        | dsctl dry-clean    | Show all non-stack folders without deleting them. |
| help             | dsctl help         | Show usage information. |
| alias            | dsctl alias <name> | Create, remove, or check persistent aliases for dsctl (`alias <name>`, `off`, `status`). |
| install          | dsctl install      | Run interactive installation for dsctl and enable autocompletion. |

---

### 4. Configuration commands

| Command | Usage | Explanation |
|---------|-------|-------------|
| alias   | dsctl alias \<name> / off / status | Create, remove, or check persistent aliases for `dsctl`. |
| install | dsctl install | Run the interactive installation for `dsctl` and enable autocompletion. Already done during installation.|
