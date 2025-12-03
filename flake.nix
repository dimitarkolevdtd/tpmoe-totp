{
  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };

    systems = {
      url = "github:nix-systems/default";
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } ({ flake-parts-lib, lib, ... }: {
    systems = import inputs.systems;

    perSystem = { config, pkgs, ... }: {
      packages = {
        default = pkgs.callPackage ./nix/package.nix { };
      };
    };
  });
}
