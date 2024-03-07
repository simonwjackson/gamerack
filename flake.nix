{
  description = "A Nix flake for gamerack including a NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05"; # Adjust the channel as needed
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
      in {
        packages.gamerack = gamerack;
        nixosModules.default = gamerack-module;

        defaultPackage = gamerack;
      }
    );
}
