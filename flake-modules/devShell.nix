{lib, ...}: {
  perSystem = {
    config,
    self',
    inputs',
    pkgs,
    ...
  }: {
    formatter = pkgs.alejandra;
    devShells.default = pkgs.mkShell {
      PATH_AUDIO = inputs'.giraff.packages.dataset_audio;
      BUMBLEBEE_CACHE_DIR = ".bumblebee_cache";
      WHISPER_TINY_DIR = "${self'.packages.whisper-tiny}/whisper";
      BERT_TWEETER_DIR = "${self'.packages.bert-tweeter}/bert-tweeter";
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
            nixd
            moreutils
            lazydocker
            # Required at runtime
            ffmpeg-headless
            mimic
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
