{ pkgs, cfg, ... }:

{
  home.username = cfg.username;
  home.homeDirectory = cfg.homeDirectory;

  # Don't bump this after first install; see `man home-configuration.nix`
  home.stateVersion = "25.11";

  # Integrates with non-NixOS Linux (XDG_DATA_DIRS, locales, etc.)
  targets.genericLinux.enable = pkgs.stdenv.hostPlatform.isLinux;
  targets.genericLinux.gpu.enable = false; # headless server

  imports = (if builtins.pathExists ./pkg.nix then [ ./pkg.nix ] else [ ]);

  home.packages = with pkgs; [
    git
    curl
    just
  ];

  # Applied to every shell home-manager manages (bash + fish below)
  home.shellAliases = {
    rig = "just -f '${cfg.homeDirectory}/.config/rig/justfile'";
    docker = "podman";
  };

  # Or enable programs with pre-configured settings
  programs.bash.enable = true;

  programs.fish = {
    enable = true;
    shellAliases = { };
  };

  programs.home-manager.enable = true;

  programs.git = {
    enable = true;
    settings = {
      push = {
        autoSetupRemote = true;
        default = "current";
        forceWithLease = true;
      };
    };
  };
}
