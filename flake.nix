{
  description = "rig - CLI for managing remote boxes over SSH";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;
      version = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./VERSION);

      mkRig = pkgs: pkgs.stdenvNoCC.mkDerivation {
        pname = "rig";
        inherit version;
        src = self;

        nativeBuildInputs = [ pkgs.makeWrapper ];

        dontBuild = true;
        installPhase = ''
          mkdir -p $out/libexec/rig $out/bin
          cp -r src $out/libexec/rig/
          # bin.sh resolves VERSION relative to the directory above src/.
          cp VERSION $out/libexec/rig/VERSION
          chmod +x $out/libexec/rig/src/bin.sh
          patchShebangs $out/libexec/rig/src

          # rig shells out to ssh, rsync, scp and curl. Without this the
          # binary works only when those happen to be on the user's PATH,
          # which is not the case on a minimal NixOS or nix-darwin profile.
          makeWrapper $out/libexec/rig/src/bin.sh $out/bin/rig \
            --prefix PATH : ${pkgs.lib.makeBinPath [
              pkgs.bash
              pkgs.coreutils
              pkgs.curl
              pkgs.openssh
              pkgs.rsync
            ]}
        '';

        meta = with pkgs.lib; {
          description = "CLI for managing remote boxes over SSH";
          homepage = "https://github.com/Pingid/rig";
          license = licenses.mit;
          platforms = platforms.unix;
          mainProgram = "rig";
        };
      };
    in
    {
      packages = forAllSystems (system: {
        default = mkRig nixpkgs.legacyPackages.${system};
      });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/rig";
        };
      });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [ pkgs.bats pkgs.shellcheck pkgs.shfmt ];
          };
        });

      checks = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          build = self.packages.${system}.default;

          lint = pkgs.runCommand "rig-lint"
            { nativeBuildInputs = [ pkgs.shellcheck pkgs.shfmt ]; } ''
            cd ${self}
            shellcheck -x src/*.sh test/helper.bash
            shfmt -d src/ test/
            touch $out
          '';

          tests = pkgs.runCommand "rig-tests"
            { nativeBuildInputs = [ pkgs.bats ]; } ''
            cp -r ${self} tree
            chmod -R +w tree
            cd tree
            export HOME=$TMPDIR/home
            bats test/
            touch $out
          '';
        });
    };
}
