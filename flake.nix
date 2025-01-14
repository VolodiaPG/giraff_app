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
    giraff.url = "github:volodiapg/giraff/dynamicity";
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
        in {
          name = "prod-" + target;
          value = crossPkgs.callPackage ./giraff.nix {
            beamPackages = beamPackagesCross;
            mixNixDeps = mixNixDepsCross;
            inherit lib opts;
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
            };
          };
        };

        packages = rec {
          default = prod;
          prod = import ./giraff.nix {
            inherit lib beamPackages opts;
            inherit (self'.packages) vm_deploy vm_remove;
          };
          giraff_app = pkgs.dockerTools.streamLayeredImage {
            name = "giraff";
            tag = "giraff_app";
            contents = [prod pkgs.bash]; # pkgs.coreutils pkgs.bashInteractive ];

            config = {
              Env = [
                # "fprocess=${prod}/bin/function"
                "LC_ALL=C.UTF-8"
                "mode=http"
                "http_upstream_url=http://127.0.0.1:5000"
                "ready_path=http://127.0.0.1:5000/health"
              ];
              ExposedPorts = {
                "8080/tcp" = {};
              };
              Cmd = ["${inputs.giraff.packages.${system}.fwatchdog}/bin/of-watchdog"];
              WorkingDir = "/";
            };
          };
        };

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
