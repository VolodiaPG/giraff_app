{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    flake-parts.url = "github:hercules-ci/flake-parts";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }: let
    inherit (nixpkgs) lib;
    opts = import ./opts.nix;
  in
    flake-parts.lib.mkFlake {inherit inputs;} rec {
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
      imports = [
        ./flake-modules
      ];
      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: let
        beamPackages = pkgs.beam.packagesWith pkgs.beam.interpreters.erlang_27;
        crossBuildFor = target: let
          crossPkgs = import nixpkgs {
            inherit system;
            crossSystem = lib.systems.elaborate target;
            stdenv.hostPlatform.emulator = "${pkgs.qemu}/bin/qemu-x86_64";
          };

          beamPackagesCross = crossPkgs.beam.packagesWith crossPkgs.beam.interpreters.erlang_27;
          mixNixDepsCross = import ./deps.nix {
            inherit lib;
            beamPackages = beamPackagesCross;
          };
          # mixNixDepsCross = mixNixDeps.override {
          #   buildRebar3 = beamPackages.buildRebar3;
          # };
        in {
          name = "prod-" + target;
          value = crossPkgs.callPackage ./giraff.nix {
            beamPackages = beamPackagesCross;
            mixNixDeps = mixNixDepsCross;
            inherit lib opts;
            inherit (crossPkgs) ffmpeg_7-headless;
            inherit (self.packages.${target}) vm_deploy vm_remove;
          };
        };
      in {
        checks = {
          pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              alejandra.enable = true;
              statix.enable = true;

              #credo.enable = true;
            };
          };
        };

        packages =
          rec {
            default = prod;
            prod = import ./giraff.nix {
              inherit lib beamPackages opts;
              inherit (pkgs) ffmpeg_7-headless;
              inherit (self'.packages) vm_deploy vm_remove;
            };
          }
          // builtins.listToAttrs (map crossBuildFor systems);

        apps = let
          mkApp = drv: {
            type = "app";
            program = "${drv}/bin/${drv.name}";
          };
        in {
          prod = mkApp self'.packages.prod;
        };
      };
    };
}
