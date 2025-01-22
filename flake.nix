{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    giraff = {
      url = "github:volodiapg/giraff";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = ["https://elixir-tools.cachix.org"];
    extra-trusted-public-keys = ["elixir-tools.cachix.org-1:GfK9E139Ysi+YWeS1oNN9OaTfQjqpLwlBaz+/73tBjU="];
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
    flake-parts.lib.mkFlake {inherit inputs;} {
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
        elixir_nix_version = elixir_version:
          builtins.replaceStrings ["."] ["_"] "elixir_${elixir_version}";
        erlang_nix_version = erlang_version: "erlang_${erlang_version}";
        inherit (pkgs) beam_minimal;
        beamPackages =
          beam_minimal
          .packagesWith
          self'.packages.erlang;
      in {
        checks = {
          pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              alejandra.enable = true;
              statix = {
                enable = true;
                settings.ignore = [
                  "deps.nix"
                ];
              };
            };
          };
        };

        packages = rec {
          erlang = beam_minimal.interpreters.${erlang_nix_version opts.erlang_version};
          elixir = beamPackages.${elixir_nix_version opts.elixir_version};
          default = prod;
          prod = import ./giraff.nix {
            inherit lib beamPackages elixir erlang opts pkgs;
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
