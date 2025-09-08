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
      VOSK_PATH = "${self'.packages.voskModel}/vosk";
      packages =
        (with self'.packages; [
          elixir
          erlang
          # For local running
          python-vosk
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
          ]
          ++ lib.optional stdenv.isLinux [inotify-tools libcgroup mimic]
          ++ (
            lib.optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
              CoreFoundation
              CoreServices
            ])
          ));
      shellHook =
        config.checks.pre-commit-check.shellHook
        + ''
          mkdir -p .venv/bin
          ln -s ${self'.packages.python-vosk}/bin/vosk .venv/bin/vosk
          VOSK_PATH=$(realpath --no-symlinks "priv/python/model")
          rm -rf "$VOSK_PATH" || true
          ln -s "${self'.packages.voskModel}" "$VOSK_PATH"
          VOSK_PATH=$(realpath --no-symlinks "model")
          rm -rf "$VOSK_PATH" || true
          ln -s "${self'.packages.voskModel}" "$VOSK_PATH"
          VOSK_PATH=$(realpath --no-symlinks "model/vosk")
        '';
    };
  };
}
