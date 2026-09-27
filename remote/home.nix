{ pkgs, cfg, ... }:

{   
  home.username = cfg.username;
  home.homeDirectory = cfg.homeDirectory;

  # Declare packages directly
  home.packages = with pkgs; [
    gh
    just
  ];

  # Or enable programs with pre-configured settings
  programs.fish = {
    enable = true;
    shellAliases = {
    #   j = "just";
    };
  };

  programs.home-manager.enable = true;
}