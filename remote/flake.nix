{
  description = "User Home Manager Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  let cfg = import ./config.nix;

  outputs = { nixpkgs, home-manager, ... }:
    let
      system = cfg.systemType;
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      homeConfigurations."${cfg.username}" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix { inherit cfg; } ];
      };
    };
}