{
  description = "A Nix flake for gamerack including a NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        gamerack = import ./nix/default.nix {inherit pkgs;};
        gamerack-module = import ./nix/module.nix inputs;
        docker = pkgs.dockerTools.buildLayeredImage {
          name = "gamerack";
          tag = "latest";
          config = {
            Cmd = ["${gamerack}/bin/gamerack"];
          };
          contents = [
            gamerack
          ];
        };
      in {
        packages.gamerack = gamerack;
        packages.docker = docker;
        nixosModules.default = gamerack-module;

        defaultPackage = gamerack;
      }
    );
}
