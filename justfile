set dotenv-load

[private]
default:
   @just --justfile '{{justfile()}}' --list --list-heading $'\n' --list-prefix "  → "

# If REMOTE is missing from env/.env, prompt the user with a question
REMOTE := `[ -n "${REMOTE:-}" ] && echo "$REMOTE" || (read -rp "Enter REMOTE: " v </dev/tty && echo "REMOTE=\"$v\"" >> .env && echo "$v")`

# Persist it automatically whenever any recipe runs
[private]
_save-env:
    @grep -q "^REMOTE=" .env 2>/dev/null || echo 'REMOTE="{{REMOTE}}"' >> .env

# Setup the remote server
init: _save-env
    @sh ./init.sh {{REMOTE}}

# SSH into the remote server
ssh: _save-env
    @ssh {{REMOTE}}

# Copy the SSH public key to the remote server
copy-id: _save-env
    @ssh-copy-id -i ~/.ssh/id_ed25519.pub {{REMOTE}}

# Run a command on the remote server
run *args: _save-env
    @ssh {{REMOTE}} {{args}}

# Run a recipe from the remote justfile (`rig` falls back to this for unknown recipes)
remote *args: _save-env
    @ssh -t {{REMOTE}} just -f .config/rig/justfile {{args}}

# Run a command on the remote server
docker *args: _save-env
    @ssh {{REMOTE}} podman {{args}}
