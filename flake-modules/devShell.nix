{
  lib,
  pkgs,
  ...
}: {
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
        [
          pkgs.hex
          pkgs.mix2nix
          self'.packages.elixir
          self'.packages.erlang
        ]
        ++ (with pkgs;
          [
            lexical
            statix
            just
            skopeo
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
