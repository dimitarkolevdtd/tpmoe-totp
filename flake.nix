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

    flake = { config, ... }: {
      modules.nixos.default = import ./nix/module.nix inputs;
      nixosModules = config.modules.nixos;
    };

    perSystem = { config, pkgs, ... }: {
      packages = {
        default = pkgs.callPackage ./nix/package.nix { };
      };
    };
  });
}
