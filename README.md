# rig

Bootstrap a fresh server with Nix + home-manager in one command.

```bash
./init.sh root@134.209.221.173
./init.sh me@myhost -p 2222 -i ~/.ssh/other_key   # extra args go to ssh
```

This copies `remote/` to the server and runs `remote/init.sh`, which:

1. Adds a 2GB swapfile if the machine has <2GB RAM and no swap (evaluating nixpkgs
   gets OOM-killed on small VPSes otherwise)
2. Installs Nix (multi-user) if it isn't already there
3. Enables flakes in `~/.config/nix/nix.conf`
4. Writes `~/.config/rig/config.nix` (arch, hostname, user, home) on first run
5. Copies `flake.nix`, `home.nix` and `justfile` to `~/.config/rig` and runs `home-manager switch`
6. Adds fish to `/etc/shells` and makes it the login shell (only if it runs cleanly)

Re-running is safe. It's also how you push changes: edit `remote/home.nix`, then run `./init.sh <host>` again.

To run it directly on a machine instead: `bash remote/init.sh`.

## Config overrides

The detected values can be overridden with env vars on the remote: `RIG_SYSTEM`,
`RIG_HOSTNAME`, `RIG_USERNAME`, `RIG_HOME`. Set `RIG_RECONFIGURE=1` to
regenerate `config.nix`, `RIG_SWAP_MB=0` to skip the swapfile, or `RIG_SET_SHELL=0`
to keep the existing login shell.

## On the server afterwards

The `rig` alias runs recipes from `remote/justfile`:

```bash
rig          # list recipes
rig apply    # re-apply the home-manager config
rig update   # bump nixpkgs/home-manager in flake.lock
```

Edits made directly in `~/.config/rig` on the server get overwritten by the next
`./init.sh`, so make changes in this repo instead.
