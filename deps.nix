{
  pkgs,
  lib,
  beamPackages,
  overrides ? (x: y: {}),
  overrideFenixOverlay ? null,
}: let
  buildMix = lib.makeOverridable beamPackages.buildMix;
  buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;

  workarounds = {
    portCompiler = _unusedArgs: old: {
      buildPlugins = [pkgs.beamPackages.pc];
    };

    rustlerPrecompiled = {toolchain ? null, ...}: old: let
      extendedPkgs = pkgs.extend fenixOverlay;
      fenixOverlay =
        if overrideFenixOverlay == null
        then
          import "${
            fetchTarball {
              url = "https://github.com/nix-community/fenix/archive/056c9393c821a4df356df6ce7f14c722dc8717ec.tar.gz";
              sha256 = "sha256:1cdfh6nj81gjmn689snigidyq7w98gd8hkl5rvhly6xj7vyppmnd";
            }
          }/overlay.nix"
        else overrideFenixOverlay;
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
          nativeBuildInputs = [
            extendedPkgs.cmake
          ];
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
    acceptor_pool = let
      version = "1.0.0";
      drv = buildRebar3 {
        inherit version;
        name = "acceptor_pool";

        src = fetchHex {
          inherit version;
          pkg = "acceptor_pool";
          sha256 = "0cbcd83fdc8b9ad2eee2067ef8b91a14858a5883cb7cd800e6fcd5803e158788";
        };
      };
    in
      drv;

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
      version = "1.6.6";
      drv = buildMix {
        inherit version;
        name = "bandit";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "bandit";
          sha256 = "ceb19bf154bc2c07ee0c9addf407d817c48107e36a66351500846fc325451bf9";
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
      version = "1.0.11";
      drv = buildMix {
        inherit version;
        name = "castore";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "castore";
          sha256 = "e03990b4db988df56262852f20de0f659871c35154691427a5047f4967a16a62";
        };
      };
    in
      drv;

    certifi = let
      version = "2.12.0";
      drv = buildRebar3 {
        inherit version;
        name = "certifi";

        src = fetchHex {
          inherit version;
          pkg = "certifi";
          sha256 = "ee68d85df22e554040cdb4be100f33873ac6051387baf6a8f6ce82272340ff1c";
        };
      };
    in
      drv;

    chatterbox = let
      version = "0.15.1";
      drv = buildRebar3 {
        inherit version;
        name = "chatterbox";

        src = fetchHex {
          inherit version;
          pkg = "ts_chatterbox";
          sha256 = "4f75b91451338bc0da5f52f3480fa6ef6e3a2aeecfc33686d6b3d0a0948f31aa";
        };

        beamDeps = [
          hpack
        ];
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

    ctx = let
      version = "0.6.0";
      drv = buildRebar3 {
        inherit version;
        name = "ctx";

        src = fetchHex {
          inherit version;
          pkg = "ctx";
          sha256 = "a14ed2d1b67723dbebbe423b28d7615eb0bdcba6ff28f2d1f1b0a7e1d4aa5fc2";
        };
      };
    in
      drv;

    decimal = let
      version = "2.3.0";
      drv = buildMix {
        inherit version;
        name = "decimal";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "decimal";
          sha256 = "a4d66355cb29cb47c3cf30e71329e58361cfcb37c34235ef3bf1d7bf3773aeac";
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

    erlport = let
      version = "0.11.0";
      drv = buildRebar3 {
        inherit version;
        name = "erlport";

        src = fetchHex {
          inherit version;
          pkg = "erlport";
          sha256 = "8eb136ccaf3948d329b8d1c3278ad2e17e2a7319801bc4cc2da6db278204eee4";
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
      version = "0fd7758c433155934e5a54c000cbc8c5e81b9e00";
      drv = buildMix {
        inherit version;
        name = "flame";
        appConfigPath = ./config;

        src = pkgs.fetchFromGitHub {
          owner = "volodiapg";
          repo = "flame";
          rev = "0fd7758c433155934e5a54c000cbc8c5e81b9e00";
          hash = "sha256-9EOGoU34PZlZHD9X/VEbUAUpxokMRz0+N9X2Z0YTBgs=";
        };

        beamDeps = [
          jason
          castore
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

    gproc = let
      version = "0.9.1";
      drv = buildRebar3 {
        inherit version;
        name = "gproc";

        src = fetchHex {
          inherit version;
          pkg = "gproc";
          sha256 = "905088e32e72127ed9466f0bac0d8e65704ca5e73ee5a62cb073c3117916d507";
        };
      };
    in
      drv;

    grpcbox = let
      version = "0.17.1";
      drv = buildRebar3 {
        inherit version;
        name = "grpcbox";

        src = fetchHex {
          inherit version;
          pkg = "grpcbox";
          sha256 = "4a3b5d7111daabc569dc9cbd9b202a3237d81c80bf97212fbc676832cb0ceb17";
        };

        beamDeps = [
          acceptor_pool
          chatterbox
          ctx
          gproc
        ];
      };
    in
      drv;

    hackney = let
      version = "1.20.1";
      drv = buildRebar3 {
        inherit version;
        name = "hackney";

        src = fetchHex {
          inherit version;
          pkg = "hackney";
          sha256 = "fe9094e5f1a2a2c0a7d10918fee36bfec0ec2a979994cff8cfe8058cd9af38e3";
        };

        beamDeps = [
          certifi
          idna
          metrics
          mimerl
          parse_trans
          ssl_verify_fun
          unicode_util_compat
        ];
      };
    in
      drv;

    hpack = let
      version = "0.3.0";
      drv = buildRebar3 {
        inherit version;
        name = "hpack";

        src = fetchHex {
          inherit version;
          pkg = "hpack_erl";
          sha256 = "d6137d7079169d8c485c6962dfe261af5b9ef60fbc557344511c1e65e3d95fb0";
        };
      };
    in
      drv;

    hpax = let
      version = "1.0.2";
      drv = buildMix {
        inherit version;
        name = "hpax";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "hpax";
          sha256 = "2f09b4c1074e0abd846747329eaa26d535be0eb3d189fa69d812bfb8bfefd32f";
        };
      };
    in
      drv;

    httpoison = let
      version = "2.2.1";
      drv = buildMix {
        inherit version;
        name = "httpoison";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "httpoison";
          sha256 = "51364e6d2f429d80e14fe4b5f8e39719cacd03eb3f9a9286e61e216feac2d2df";
        };

        beamDeps = [
          hackney
        ];
      };
    in
      drv;

    idna = let
      version = "6.1.1";
      drv = buildRebar3 {
        inherit version;
        name = "idna";

        src = fetchHex {
          inherit version;
          pkg = "idna";
          sha256 = "92376eb7894412ed19ac475e4a86f7b413c1b9fbb5bd16dccd57934157944cea";
        };

        beamDeps = [
          unicode_util_compat
        ];
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

    metrics = let
      version = "1.0.1";
      drv = buildRebar3 {
        inherit version;
        name = "metrics";

        src = fetchHex {
          inherit version;
          pkg = "metrics";
          sha256 = "69b09adddc4f74a40716ae54d140f93beb0fb8978d8636eaded0c31b6f099f16";
        };
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

    mimerl = let
      version = "1.3.0";
      drv = buildRebar3 {
        inherit version;
        name = "mimerl";

        src = fetchHex {
          inherit version;
          pkg = "mimerl";
          sha256 = "a1e15a50d1887217de95f0b9b0793e32853f7c258a5cd227650889b38839fe9d";
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

    opentelemetry = let
      version = "1.5.0";
      drv = buildRebar3 {
        inherit version;
        name = "opentelemetry";

        src = fetchHex {
          inherit version;
          pkg = "opentelemetry";
          sha256 = "cdf4f51d17b592fc592b9a75f86a6f808c23044ba7cf7b9534debbcc5c23b0ee";
        };

        beamDeps = [
          opentelemetry_api
        ];
      };
    in
      drv;

    opentelemetry_api = let
      version = "1.4.0";
      drv = buildMix {
        inherit version;
        name = "opentelemetry_api";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "opentelemetry_api";
          sha256 = "3dfbbfaa2c2ed3121c5c483162836c4f9027def469c41578af5ef32589fcfc58";
        };
      };
    in
      drv;

    opentelemetry_exporter = let
      version = "1.8.0";
      drv = buildRebar3 {
        inherit version;
        name = "opentelemetry_exporter";

        src = fetchHex {
          inherit version;
          pkg = "opentelemetry_exporter";
          sha256 = "a1f9f271f8d3b02b81462a6bfef7075fd8457fdb06adff5d2537df5e2264d9af";
        };

        beamDeps = [
          grpcbox
          opentelemetry
          opentelemetry_api
          tls_certificate_check
        ];
      };
    in
      drv;

    parse_trans = let
      version = "3.4.1";
      drv = buildRebar3 {
        inherit version;
        name = "parse_trans";

        src = fetchHex {
          inherit version;
          pkg = "parse_trans";
          sha256 = "620a406ce75dada827b82e453c19cf06776be266f5a67cff34e1ef2cbb60e49a";
        };
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

    poolboy = let
      version = "1.5.2";
      drv = buildRebar3 {
        inherit version;
        name = "poolboy";

        src = fetchHex {
          inherit version;
          pkg = "poolboy";
          sha256 = "dad79704ce5440f3d5a3681c8590b9dc25d1a561e8f5a9c995281012860901e3";
        };
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

    ssl_verify_fun = let
      version = "1.1.7";
      drv = buildMix {
        inherit version;
        name = "ssl_verify_fun";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "ssl_verify_fun";
          sha256 = "fe4c190e8f37401d30167c8c405eda19469f34577987c76dde613e838bbc67f8";
        };
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
      version = "1.3.9";
      drv = buildMix {
        inherit version;
        name = "thousand_island";
        appConfigPath = ./config;

        src = fetchHex {
          inherit version;
          pkg = "thousand_island";
          sha256 = "25ab4c07badadf7f87adb4ab414e0ed374e5f19e72503aa85132caa25776e54f";
        };

        beamDeps = [
          telemetry
        ];
      };
    in
      drv;

    tls_certificate_check = let
      version = "1.26.0";
      drv = buildRebar3 {
        inherit version;
        name = "tls_certificate_check";

        src = fetchHex {
          inherit version;
          pkg = "tls_certificate_check";
          sha256 = "1bad73d88637f788b554a8e939c25db2bdaac88b10fffd5bba9d1b65f43a6b54";
        };

        beamDeps = [
          ssl_verify_fun
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

    unicode_util_compat = let
      version = "0.7.0";
      drv = buildRebar3 {
        inherit version;
        name = "unicode_util_compat";

        src = fetchHex {
          inherit version;
          pkg = "unicode_util_compat";
          sha256 = "25eee6d67df61960cf6a794239566599b09e17e668d3700247bc498638152521";
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
