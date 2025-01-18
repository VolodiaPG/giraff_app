{lib, ...}: {
  perSystem = {
    config,
    self',
    inputs',
    pkgs,
    system,
    ...
  }: {
    formatter = pkgs.alejandra;
    devShells.default = pkgs.mkShell {
      packages =
        (with self'.packages; [
          elixir
          erlang
        ])
        ++ (with pkgs;
          [
            hex
            lexical
            statix
            just
            skopeo
            # Required at runtime
            ffmpeg-headless
          ]
          ++ lib.optional stdenv.isLinux inotify-tools
          ++ (
            lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
              CoreFoundation
              CoreServices
            ])
          ));
      inherit (config.checks.pre-commit-check) shellHook;
    };
  };
}
