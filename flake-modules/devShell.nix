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
          pkgs.elixir
          pkgs.erlang
          pkgs.mix2nix
          self'.packages.vm_deploy
          self'.packages.vm_remove
          self'.packages.vm_get_ipv6
          self'.packages.vm_wait_online
          self'.packages.check_ts
        ]
        ++ (with pkgs;
          [
            lexical
            alejandra
            statix
            just
            postgresql
            ffmpeg_7-headless
            nix-output-monitor
            tailscale
            jq
            toybox
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
