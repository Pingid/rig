# rig

CLI for managing remote boxes over SSH: run commands, push/pull files, install
packages, and open tunnels against a `REMOTE` host.

## Install

### Homebrew

```sh
brew tap Pingid/rig https://github.com/Pingid/rig
brew install rig
```

### Nix

```sh
nix profile install github:Pingid/rig
# or, without installing:
nix run github:Pingid/rig -- ssh
```

The Nix build wraps `rig` with its runtime dependencies (`ssh`, `rsync`,
`scp`, `curl`), so it works on a minimal profile.

### Manual

Download a release archive from the [releases page](https://github.com/Pingid/rig/releases),
extract it, and symlink `src/bin.sh` onto your `PATH` as `rig`. Keep `VERSION`
in the directory above `src/`; `rig version` reads it from there.

## Usage

```sh
rig                       # show usage (exit 1)
rig help                  # show usage (exit 0)
rig version               # print the installed version
rig ssh                   # ssh into REMOTE
rig run <cmd>             # run a command on REMOTE
rig apt <args>            # run apt non-interactively on REMOTE
rig push <from> <to>      # rsync files to REMOTE
rig pull <from> <to>      # rsync files from REMOTE
rig scp <from> <to>       # copy a file to REMOTE
rig install <target>      # install node/docker/tailscale on REMOTE
rig tunnel <port>         # forward a local port to REMOTE
```

`rig run` passes its argument to the remote login shell, which parses it once.
Quote it the way you want the remote to see it:

```sh
rig run 'systemctl status nginx'
rig run 'echo $HOME'          # expands on the remote
rig run "echo $HOME"          # expands locally, before it is sent
```

## Configuration

Two variables are read: `REMOTE` (e.g. `root@165.227.230.38`) and the optional
`REMOTE_KEY`, a path to an SSH identity file.

They are resolved in this order, lowest priority first:

| Source | Path |
| --- | --- |
| global config | `${XDG_CONFIG_HOME:-~/.config}/rig/config` |
| local config | `./.rig.env` |
| environment | `REMOTE=other rig ssh` |

so the environment is always a one-off override. Config files are
`KEY=VALUE` per line; `#` starts a comment, values may be quoted, and keys
other than `REMOTE` and `REMOTE_KEY` are ignored.

Running a command with no remote configured prompts for one and offers to save
it locally or globally. With no terminal attached it fails instead of hanging.

### Migrating from older versions

Earlier versions stored config in a `.env` beside the script and read a bare
`./.env` from the working directory. Both are still read when no new-style
config exists, with a deprecation warning, but are never written to. Move them:

```sh
mkdir -p ~/.config/rig && mv <install-dir>/src/.env ~/.config/rig/config
mv ./.env ./.rig.env
```

The script-adjacent location never really worked: it is read-only under Nix and
discarded by every `brew upgrade`.

## Development

```sh
nix develop          # shellcheck, shfmt and bats on PATH
shellcheck -x src/*.sh test/helper.bash
shfmt -d src/ test/  # indent width comes from .editorconfig
bats test/
nix flake check      # build + lint + tests
```

The test suite puts stub `ssh`/`rsync`/`scp` binaries on `PATH` that echo their
argv, so it asserts on the exact command `rig` would have run without touching
the network.

`rig` targets **bash 3.2**, which is what `/usr/bin/env bash` resolves to on a
stock macOS. That rules out associative arrays and `mapfile`, and means
`"${arr[@]}"` on an empty array is an error under `set -u` — empty-capable
arrays are written `${arr[@]+"${arr[@]}"}`. CI re-runs the suite against
`/bin/bash` on macOS to keep that honest.

## Releasing

1. Bump `VERSION`.
2. Commit it.
3. Push a tag matching `v*.*.*` (e.g. `v0.2.0`).

The [release workflow](.github/workflows/release.yml) first checks that
`VERSION` matches the tag — the source archive is built from the tag, so a
mismatch would ship the wrong `VERSION` and `flake.nix` reads it. It then
builds the archive, publishes it as a GitHub release, and commits the new
version, URL, and checksum into `Formula/rig.rb` on the default branch.
