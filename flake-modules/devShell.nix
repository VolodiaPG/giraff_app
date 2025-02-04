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
      ELIXIR_LS_DIR = "${pkgs.elixir-ls}";
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
            elixir-ls
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
      shellHook =
        config.checks.pre-commit-check.shellHook
        + ''
          rm -rf .elixir-ls || true ; ln -s ${pkgs.elixir-ls} .elixir-ls
        '';
    };
  };
}
