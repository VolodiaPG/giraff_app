{
  lib,
  beamPackages,
  elixir,
  erlang,
  mixNixDeps ? import ./deps.nix {inherit lib beamPackages;},
  opts,
}:
beamPackages.mixRelease {
  inherit mixNixDeps elixir erlang;
  inherit (opts.app) pname version;
  src = ./.;
  stripDebug = true;

  # postInstall = ''
  #   # Strip debug symbols and shrink rpath
  #   find $out -type f -exec patchelf --shrink-rpath '{}' \; -exec strip '{}' \; 2>/dev/null
  #   # Remove unnecessary files
  #   rm -rf $out/lib/*/consolidated
  #   rm -rf $out/lib/*/ebin/*.beam
  #   rm -rf $out/lib/*/priv/static
  # '';

  preFixup = ''
    makeWrapper $out/bin/server $out/bin/function
  '';
}
