{
  perSystem = {
    self',
    inputs',
    pkgs,
    lib,
    ...
  }: let
    beamPackages = pkgs.beam_minimal.packagesWith self'.packages.erlang;
    mixNixDeps = import ./deps.nix {
      inherit lib beamPackages pkgs;
      overrides = final: prev: {
        exla = prev.exla.overrideAttrs (old: {
          XLA_ARCHIVE_PATH = pkgs.fetchurl {
            url = let
              system =
                if pkgs.stdenv.hostPlatform.isGnu
                then "${pkgs.stdenv.hostPlatform.system}-gnu"
                else pkgs.stdenv.hostPlatform.system;
              inherit (prev.xla) version;
            in "https://github.com/elixir-nx/xla/releases/download/v${version}/xla_extension-${version}-${system}-cpu.tar.gz";
            hash = "sha256-o0ytpdo1lHWg014A8Lk3J+Jv141+oiBoahCTDAVn4iQ=";
          };

          prePatch = ''
            substituteInPlace mix.exs \
              --replace 'XLA.archive_path!()' 'System.get_env("XLA_ARCHIVE_PATH")'
            substituteInPlace mix.exs \
              --replace 'compilers: [:extract_xla, :cached_make] ++ Mix.compilers(),' 'compilers: [:extract_xla, :elixir_make] ++ Mix.compilers(),'
          '';

          postInstall = ''
            OUTDIR=$out/lib/erlang/lib/${old.name}/priv
            rm -rf $OUTDIR/{xla_extension,libexla.so}
            cp -Hrt $OUTDIR cache/{xla_extension,libexla.so}
          '';
        });
      };
    };
    drv = mixEnv:
      beamPackages.mixRelease {
        inherit mixNixDeps mixEnv;
        elixir = self'.packages.elixir;
        erlang = self'.packages.erlang;
        pname = "giraff";
        version = "0.1.0";
        src = ./.;
        stripDebug = true;

        preFixup = ''
          makeWrapper $out/bin/server $out/bin/function
        '';
      };
  in {
    packages = {
      prod = drv "prod";
      docker = drv "docker";
    };
  };
}
