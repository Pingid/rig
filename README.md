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
rig                        # show usage (exit 1)
rig help                   # show usage (exit 0)
rig version                # print the installed version
rig ssh                    # ssh into the remote
rig run <cmd>              # run a command on the remote
rig apt <args>             # run apt non-interactively on the remote
rig push <from> <to>       # rsync files to the remote
rig pull <from> <to>       # rsync files from the remote
rig scp <from> <to>        # copy a file to the remote
rig copy-id [<identity>]   # install your ssh public key on the remote
rig install <target>       # install node/docker/tailscale on the remote
rig tunnel <port>          # forward a local port to the remote
rig remotes <sub>          # manage named remotes
```

Any command can be pointed at a different remote for one invocation with
`-r`, which must come before the subcommand:

```sh
rig -r staging ssh
rig --remote=staging push ./dist /srv/app
```

`rig run` passes its argument to the remote login shell, which parses it once.
Quote it the way you want the remote to see it:

```sh
rig run 'systemctl status nginx'
rig run 'echo $HOME'          # expands on the remote
rig run "echo $HOME"          # expands locally, before it is sent
```

## Named remotes

Hosts you use repeatedly live in the global config, each under a name, with one
of them marked as the default:

```sh
rig remotes add prod root@165.227.230.38 ~/.ssh/prod_ed25519
rig remotes add staging deploy@10.0.0.5
rig remotes use prod          # make prod the default
rig remotes                   # list them; * marks the default
rig remotes remove staging
```

```
* prod     root@165.227.230.38  (~/.ssh/prod_ed25519)
  staging  deploy@10.0.0.5
```

The first remote you add becomes the default automatically, so a single-host
setup needs no second step. With a default set, plain `rig ssh` uses it and
`rig -r staging ssh` overrides it for that one command.

A project directory can be pinned to a remote without typing `-r` every time,
by naming it in `./.rig.env`:

```
default = staging
```

## Configuration

The global config is `${XDG_CONFIG_HOME:-~/.config}/rig/config`. It is
INI-shaped: keys before the first `[section]` are top-level, and each section
defines one named remote.

```ini
default = prod

[prod]
  remote = root@165.227.230.38
  key    = ~/.ssh/prod_ed25519

[staging]
  remote = deploy@10.0.0.5
```

`#` and `;` start a comment, values may be quoted, a leading `~/` is expanded,
and keys are case-insensitive. `host` is accepted as a synonym for `remote`,
and `key` or `identity` for `remote_key`. Any other key is ignored.

`rig remotes` writes this file for you; editing it by hand is equally fine.

### How a remote is chosen

Highest priority first:

| Source | Form |
| --- | --- |
| command line | `rig -r <name>` / `--remote=<name>` |
| environment | `RIG_REMOTE=<name>`, or `REMOTE=<host>` for a raw host |
| local config | `./.rig.env` — `REMOTE=<host>` or `default = <name>` |
| global default | `default = <name>` in the global config |
| global fallback | a top-level `REMOTE=<host>` in the global config |

so `REMOTE=other rig ssh` remains a one-off override, and the last row is the
flat pre-named-remotes format, which still works unchanged.

`REMOTE_KEY` (an SSH identity path) follows the remote it belongs to, and can
also be overridden for one invocation from the environment.

Running a host command with no remote configured at all prompts for one and
offers to save it locally or globally. With no terminal attached it fails
instead of hanging.

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

## Copying your SSH key to a host

```sh
rig copy-id                    # install the remote's configured identity
rig -r staging copy-id         # ...for a specific remote
rig copy-id ~/.ssh/other.pub   # install a particular key
```

With no argument this installs the remote's `key` if it has one, and otherwise
lets `ssh-copy-id` pick your default identity. The connection deliberately does
*not* force that key as the login identity — the whole point is that it is not
on the host yet, so password auth has to remain available.

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
