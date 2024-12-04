{
  lib,
  beamPackages,
  ffmpeg_7-headless,
  vm_remove,
  vm_deploy,
  mixNixDeps ? import ./deps.nix {inherit lib beamPackages;},
  opts,
}: let
  inherit (beamPackages) elixir;
in
  beamPackages.mixRelease {
    inherit mixNixDeps;
    pname = opts.remote_container_name;
    src = ./.;
    version = opts.remote_container_version;
    mixEnv = "prod";

    # ERL_COMPILER_OPTIONS="deterministic";

    buildInputs = [
      elixir
      vm_deploy
      vm_remove
      ffmpeg_7-headless
    ];
    postInstall = ''
      #  mix phx.digest --no-deps-check
      find $out -type f -exec patchelf --shrink-rpath '{}' \; -exec strip '{}' \; 2>/dev/null
    '';

    ## Deploy assets before creating release
    preInstall = ''
      # https://github.com/phoenixframework/phoenix/issues/2690
       mix do deps.loadpaths --no-deps-check
    '';

    preFixup = ''
      makeWrapper $out/bin/server $out/bin/function \
      --prefix PATH : ${lib.makeBinPath [ffmpeg_7-headless]}
    '';
  }
