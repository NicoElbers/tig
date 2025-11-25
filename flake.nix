{
  description = "Zig dev environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    zig = {
      url = "github:silversquirl/zig-flake/compat";
    };

    zls = {
      url = "github:zigtools/zls/e43fcc50782d86edb64e2ea1aadce34ad7983959";
      inputs.nixpkgs.follows = "nixpkgs";
      # inputs.zig-overlay.follows = "zig";
    };
  };

  outputs =
    {
      nixpkgs,
      zig,
      zls,
      ...
    }:
    let
      forAllSystems = f: builtins.mapAttrs f nixpkgs.legacyPackages;
    in
    {
      devShells = forAllSystems (
        system: pkgs: {

          default = pkgs.mkShellNoCC {
            packages = [
              zig.packages.${system}.nightly
              zls.packages.${system}.zls
            ];
          };
        }
      );
    };
}
