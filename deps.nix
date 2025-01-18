{
  pkgs,
  lib,
  beamPackages,
  overrides ? (x: y: {}),
}: let
  buildMix = lib.makeOverridable beamPackages.buildMix;
  buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;

  workarounds = {
    portCompiler = _unusedArgs: old: {
      buildPlugins = [pkgs.beamPackages.pc];
    };

    rustlerPrecompiled = {toolchain ? null, ...}: old: let
      extendedPkgs = pkgs.extend fenixOverlay;
      fenixOverlay = import "${
        fetchTarball {
          url = "https://github.com/nix-community/fenix/archive/056c9393c821a4df356df6ce7f14c722dc8717ec.tar.gz";
          sha256 = "sha256:1cdfh6nj81gjmn689snigidyq7w98gd8hkl5rvhly6xj7vyppmnd";
        }
      }/overlay.nix";
      nativeDir = "${old.src}/native/${with builtins; head (attrNames (readDir "${old.src}/native"))}";
      fenix =
        if toolchain == null
        then extendedPkgs.fenix.stable
        else extendedPkgs.fenix.fromToolchainName toolchain;
      native =
        (extendedPkgs.makeRustPlatform {
          inherit (fenix) cargo rustc;
        })
        .buildRustPackage
        {
          pname = "${old.packageName}-native";
          version = old.version;
          src = nativeDir;
          cargoLock = {
            lockFile = "${nativeDir}/Cargo.lock";
          };
          nativeBuildInputs =
            [
              extendedPkgs.cmake
            ]
            ++ extendedPkgs.lib.lists.optional extendedPkgs.stdenv.isDarwin extendedPkgs.darwin.IOKit;
          doCheck = false;
        };
    in {
      nativeBuildInputs = [extendedPkgs.cargo];

      env.RUSTLER_PRECOMPILED_FORCE_BUILD_ALL = "true";
      env.RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH = "unused-but-required";

      preConfigure = ''
        mkdir -p priv/native
        for lib in ${native}/lib/*
        do
          ln -s "$lib" "priv/native/$(basename "$lib")"
        done
      '';

      buildPhase = ''
        suggestion() {
          echo "***********************************************"
          echo "                 deps_nix                      "
          echo
          echo " Rust dependency build failed.                 "
          echo
          echo " If you saw network errors, you might need     "
          echo " to disable compilation on the appropriate     "
          echo " RustlerPrecompiled module in your             "
          echo " application config.                           "
          echo
          echo " We think you need this:                       "
          echo
          echo -n " "
          grep -Rl 'use RustlerPrecompiled' lib \
            | xargs grep 'defmodule' \
            | sed 's/defmodule \(.*\) do/config :${old.packageName}, \1, skip_compilation?: true/'
          echo "***********************************************"
          exit 1
        }
        trap suggestion ERR
        ${old.buildPhase}
      '';
    };
  };

  defaultOverrides = (
    final: prev: let
      apps = {
        crc32cer = [
          {
            name = "portCompiler";
          }
        ];
        explorer = [
          {
            name = "rustlerPrecompiled";
            toolchain = {
              name = "nightly-2024-11-01";
              sha256 = "sha256-wq7bZ1/IlmmLkSa3GUJgK17dTWcKyf5A+ndS9yRwB88=";
            };
          }
        ];
        snappyer = [
          {
            name = "portCompiler";
          }
        ];
      };

      applyOverrides = appName: drv: let
        allOverridesForApp =
          builtins.foldl' (
            acc: workaround: acc // (workarounds.${workaround.name} workaround) drv
          ) {}
          apps.${appName};
      in
        if builtins.hasAttr appName apps
        then drv.override allOverridesForApp
        else drv;
    in
      builtins.mapAttrs applyOverrides prev
  );

  self = packages // (defaultOverrides self packages) // (overrides self packages);

  packages = with beamPackages;
  with self; {
    axon = let
      version = "0.7.0";
      drv = buildMix {
        inherit version;
        name = "axon";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "axon";
          sha256 = "ee9857a143c9486597ceff434e6ca833dc1241be6158b01025b8217757ed1036";
        };

        beamDeps = [
          nx
          polaris
        ];
      };
    in
      drv;

    bandit = let
      version = "1.6.0";
      drv = buildMix {
        inherit version;
        name = "bandit";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "bandit";
          sha256 = "fd2491e564a7c5e11ff8496ebf530c342c742452c59de17ac0fb1f814a0ab01a";
        };

        beamDeps = [
          hpax
          plug
          telemetry
          thousand_island
          websock
        ];
      };
    in
      drv;

    bumblebee = let
      version = "0.6.0";
      drv = buildMix {
        inherit version;
        name = "bumblebee";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "bumblebee";
          sha256 = "a8b863179d314e9615b00291d5dcd2dc043b294edc25b4483d5c88d1c8d21c89";
        };

        beamDeps = [
          axon
          jason
          nx
          nx_image
          nx_signal
          progress_bar
          safetensors
          tokenizers
          unpickler
          unzip
        ];
      };
    in
      drv;

    castore = let
      version = "1.0.8";
      drv = buildMix {
        inherit version;
        name = "castore";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "castore";
          sha256 = "0b2b66d2ee742cb1d9cb8c8be3b43c3a70ee8651f37b75a8b982e036752983f1";
        };
      };
    in
      drv;

    complex = let
      version = "0.6.0";
      drv = buildMix {
        inherit version;
        name = "complex";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "complex";
          sha256 = "0a5fa95580dcaf30fcd60fe1aaf24327c0fe401e98c24d892e172e79498269f9";
        };
      };
    in
      drv;

    decimal = let
      version = "2.1.1";
      drv = buildMix {
        inherit version;
        name = "decimal";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "decimal";
          sha256 = "53cfe5f497ed0e7771ae1a475575603d77425099ba5faef9394932b35020ffcc";
        };
      };
    in
      drv;

    elixir_make = let
      version = "0.9.0";
      drv = buildMix {
        inherit version;
        name = "elixir_make";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "elixir_make";
          sha256 = "db23d4fd8b757462ad02f8aa73431a426fe6671c80b200d9710caf3d1dd0ffdb";
        };
      };
    in
      drv;

    ex_cmd = let
      version = "0.10.0";
      drv = buildMix {
        inherit version;
        name = "ex_cmd";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "ex_cmd";
          sha256 = "d2575237e754676cd3d38dc39d36a99da455253a0889c1c2231a619d3ca5d7a4";
        };

        beamDeps = [
          gen_state_machine
        ];
      };
    in
      drv;

    exla = let
      version = "0.9.2";
      drv = buildMix {
        inherit version;
        name = "exla";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "exla";
          sha256 = "e51085e196b466d235e93d9f5ea2cbf7d90315d216aa02e996f99bcaaa19c593";
        };

        beamDeps = [
          elixir_make
          nimble_pool
          nx
          telemetry
          xla
        ];
      };
    in
      drv;

    finch = let
      version = "0.19.0";
      drv = buildMix {
        inherit version;
        name = "finch";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "finch";
          sha256 = "fc5324ce209125d1e2fa0fcd2634601c52a787aff1cd33ee833664a5af4ea2b6";
        };

        beamDeps = [
          mime
          mint
          nimble_options
          nimble_pool
          telemetry
        ];
      };
    in
      drv;

    flame = let
      version = "0.3.0";
      drv = buildMix {
        inherit version;
        name = "flame";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "flame";
          sha256 = "263ffb2f8eaffdcaa3241072e515cb6af86c0280c763a3986934b039cac36300";
        };

        beamDeps = [
          castore
          jason
        ];
      };
    in
      drv;

    gen_state_machine = let
      version = "3.0.0";
      drv = buildMix {
        inherit version;
        name = "gen_state_machine";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "gen_state_machine";
          sha256 = "0a59652574bebceb7309f6b749d2a41b45fdeda8dbb4da0791e355dd19f0ed15";
        };
      };
    in
      drv;

    hpax = let
      version = "1.0.0";
      drv = buildMix {
        inherit version;
        name = "hpax";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "hpax";
          sha256 = "7f1314731d711e2ca5fdc7fd361296593fc2542570b3105595bb0bc6d0fad601";
        };
      };
    in
      drv;

    jason = let
      version = "1.4.4";
      drv = buildMix {
        inherit version;
        name = "jason";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "jason";
          sha256 = "c5eb0cab91f094599f94d55bc63409236a8ec69a21a67814529e8d5f6cc90b3b";
        };

        beamDeps = [
          decimal
        ];
      };
    in
      drv;

    mime = let
      version = "2.0.6";
      drv = buildMix {
        inherit version;
        name = "mime";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "mime";
          sha256 = "c9945363a6b26d747389aac3643f8e0e09d30499a138ad64fe8fd1d13d9b153e";
        };
      };
    in
      drv;

    mint = let
      version = "1.6.2";
      drv = buildMix {
        inherit version;
        name = "mint";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "mint";
          sha256 = "5ee441dffc1892f1ae59127f74afe8fd82fda6587794278d924e4d90ea3d63f9";
        };

        beamDeps = [
          castore
          hpax
        ];
      };
    in
      drv;

    nimble_options = let
      version = "1.1.1";
      drv = buildMix {
        inherit version;
        name = "nimble_options";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "nimble_options";
          sha256 = "821b2470ca9442c4b6984882fe9bb0389371b8ddec4d45a9504f00a66f650b44";
        };
      };
    in
      drv;

    nimble_pool = let
      version = "1.1.0";
      drv = buildMix {
        inherit version;
        name = "nimble_pool";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "nimble_pool";
          sha256 = "af2e4e6b34197db81f7aad230c1118eac993acc0dae6bc83bac0126d4ae0813a";
        };
      };
    in
      drv;

    nx = let
      version = "0.9.2";
      drv = buildMix {
        inherit version;
        name = "nx";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "nx";
          sha256 = "914d74741617d8103de8ab1f8c880353e555263e1c397b8a1109f79a3716557f";
        };

        beamDeps = [
          complex
          telemetry
        ];
      };
    in
      drv;

    nx_image = let
      version = "0.1.2";
      drv = buildMix {
        inherit version;
        name = "nx_image";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "nx_image";
          sha256 = "9161863c42405ddccb6dbbbeae078ad23e30201509cc804b3b3a7c9e98764b81";
        };

        beamDeps = [
          nx
        ];
      };
    in
      drv;

    nx_signal = let
      version = "0.2.0";
      drv = buildMix {
        inherit version;
        name = "nx_signal";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "nx_signal";
          sha256 = "7247e5e18a177a59c4cb5355952900c62fdeadeb2bad02a9a34237b68744e2bb";
        };

        beamDeps = [
          nx
        ];
      };
    in
      drv;

    plug = let
      version = "1.16.1";
      drv = buildMix {
        inherit version;
        name = "plug";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "plug";
          sha256 = "a13ff6b9006b03d7e33874945b2755253841b238c34071ed85b0e86057f8cddc";
        };

        beamDeps = [
          mime
          plug_crypto
          telemetry
        ];
      };
    in
      drv;

    plug_crypto = let
      version = "2.1.0";
      drv = buildMix {
        inherit version;
        name = "plug_crypto";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "plug_crypto";
          sha256 = "131216a4b030b8f8ce0f26038bc4421ae60e4bb95c5cf5395e1421437824c4fa";
        };
      };
    in
      drv;

    polaris = let
      version = "0.1.0";
      drv = buildMix {
        inherit version;
        name = "polaris";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "polaris";
          sha256 = "13ef2b166650e533cb24b10e2f3b8ab4f2f449ba4d63156e8c569527f206e2c2";
        };

        beamDeps = [
          nx
        ];
      };
    in
      drv;

    progress_bar = let
      version = "3.0.0";
      drv = buildMix {
        inherit version;
        name = "progress_bar";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "progress_bar";
          sha256 = "6981c2b25ab24aecc91a2dc46623658e1399c21a2ae24db986b90d678530f2b7";
        };

        beamDeps = [
          decimal
        ];
      };
    in
      drv;

    req = let
      version = "0.5.8";
      drv = buildMix {
        inherit version;
        name = "req";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "req";
          sha256 = "d7fc5898a566477e174f26887821a3c5082b243885520ee4b45555f5d53f40ef";
        };

        beamDeps = [
          finch
          jason
          mime
          plug
        ];
      };
    in
      drv;

    rustler = let
      version = "0.36.0";
      drv = buildMix {
        inherit version;
        name = "rustler";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "rustler";
          sha256 = "03808c7d289da01da29d8d2fe19d07cae9f3d2f05ebaed87f0820a4dcfabe9d5";
        };

        beamDeps = [
          jason
          req
          toml
        ];
      };
    in
      drv;

    rustler_precompiled = let
      version = "0.8.2";
      drv = buildMix {
        inherit version;
        name = "rustler_precompiled";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "rustler_precompiled";
          sha256 = "63d1bd5f8e23096d1ff851839923162096364bac8656a4a3c00d1fff8e83ee0a";
        };

        beamDeps = [
          castore
          rustler
        ];
      };
    in
      drv;

    safetensors = let
      version = "0.1.3";
      drv = buildMix {
        inherit version;
        name = "safetensors";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "safetensors";
          sha256 = "fe50b53ea59fde4e723dd1a2e31cfdc6013e69343afac84c6be86d6d7c562c14";
        };

        beamDeps = [
          jason
          nx
        ];
      };
    in
      drv;

    telemetry = let
      version = "1.3.0";
      drv = buildRebar3 {
        inherit version;
        name = "telemetry";

        src = fetchHex {
          inherit version;
          pkg = "telemetry";
          sha256 = "7015fc8919dbe63764f4b4b87a95b7c0996bd539e0d499be6ec9d7f3875b79e6";
        };
      };
    in
      drv;

    thousand_island = let
      version = "1.3.7";
      drv = buildMix {
        inherit version;
        name = "thousand_island";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "thousand_island";
          sha256 = "0139335079953de41d381a6134d8b618d53d084f558c734f2662d1a72818dd12";
        };

        beamDeps = [
          telemetry
        ];
      };
    in
      drv;

    tokenizers = let
      version = "0.5.1";
      drv = buildMix {
        inherit version;
        name = "tokenizers";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "tokenizers";
          sha256 = "5f08d97cc7f2ed3d71d370d68120da6d3de010948ccf676c9c0eb591ba4bacc9";
        };

        beamDeps = [
          castore
          rustler
          rustler_precompiled
        ];
      };
    in
      drv.override (workarounds.rustlerPrecompiled {} drv);

    toml = let
      version = "0.7.0";
      drv = buildMix {
        inherit version;
        name = "toml";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "toml";
          sha256 = "0690246a2478c1defd100b0c9b89b4ea280a22be9a7b313a8a058a2408a2fa70";
        };
      };
    in
      drv;

    unpickler = let
      version = "0.1.0";
      drv = buildMix {
        inherit version;
        name = "unpickler";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "unpickler";
          sha256 = "e2b3f61e62406187ac52afead8a63bfb4e49394028993f3c4c42712743cab79e";
        };
      };
    in
      drv;

    unzip = let
      version = "0.12.0";
      drv = buildMix {
        inherit version;
        name = "unzip";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "unzip";
          sha256 = "95655b72db368e5a84951f0bed586ac053b55ee3815fd96062fce10ce4fc998d";
        };
      };
    in
      drv;

    websock = let
      version = "0.5.3";
      drv = buildMix {
        inherit version;
        name = "websock";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "websock";
          sha256 = "6105453d7fac22c712ad66fab1d45abdf049868f253cf719b625151460b8b453";
        };
      };
    in
      drv;

    xla = let
      version = "0.8.0";
      drv = buildMix {
        inherit version;
        name = "xla";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "xla";
          sha256 = "739c61c8d93b97e12ba0369d10e76130224c208f1a76ad293e3581f056833e57";
        };

        beamDeps = [
          elixir_make
        ];
      };
    in
      drv;
  };
in
  self
