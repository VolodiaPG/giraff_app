{lib, ...}: {
  perSystem = {pkgs, ...}: let
    # Base URL for the model files
    baseUrl = "https://huggingface.co/openai/whisper-tiny/resolve/169d4a4341b33bc18d8881c4b69c2e104e1cc0af";

    whisper-tiny = pkgs.stdenv.mkDerivation {
      pname = "whisper-tiny";
      version = "1.0.0";

      # We don't need src since we're fetching individual files
      dontUnpack = true;

      model = pkgs.fetchurl {
        url = "${baseUrl}/model.safetensors";
        hash = "sha256-fr0OaeeBkP/hQ4SR+gXMH1wao6TE2zvBcjrbtVHqI5U=";
      };

      config = pkgs.fetchurl {
        url = "${baseUrl}/config.json";
        hash = "sha256-/9zOxPMhH0xjMQ8rcJjzCf5w85Us7cXk0R5D9bI3m5g=";
      };

      tokenizer = pkgs.fetchurl {
        url = "${baseUrl}/tokenizer.json";
        hash = "sha256-J/xHa/5/FymUgL4ic/wGCOTVqZq6KrXexTdLRILRpWY=";
      };

      vocab = pkgs.fetchurl {
        url = "${baseUrl}/vocab.json";
        hash = "sha256-j2gLujGeAaZT0uil28F6kVcXngV25s50zgwGNWxuJPk=";
      };

      merges = pkgs.fetchurl {
        url = "${baseUrl}/merges.txt";
        hash = "sha256-LfKZCjleNejfvHUR4IwS1WAY2NBGkeATPl1jsh4VTcY=";
      };

      generationConfig = pkgs.fetchurl {
        url = "${baseUrl}/generation_config.json";
        hash = "sha256-pdUyWRHxbnQAGnL6E9biCO7lFUj5lGRt4fS0zIs1tRI=";
      };

      tokenizerConfig = pkgs.fetchurl {
        url = "${baseUrl}/tokenizer_config.json";
        hash = "sha256-KkxCgc+fUaxszEBv3HEaCHr+ZTD2cfp7gJU+3EmCdc4=";
      };

      preprocessorConfig = pkgs.fetchurl {
        url = "${baseUrl}/preprocessor_config.json";
        hash = "sha256-m1zQOjb7uKYnxk2YpbWxJurZWndyByOURIcxHwEQtmY=";
      };

      specialTokensMap = pkgs.fetchurl {
        url = "${baseUrl}/special_tokens_map.json";
        hash = "sha256-5nrjoKqpmrzZ8YcTjhLbH2XBahR2HFDvEO7ywXSnppE=";
      };

      normalizer = pkgs.fetchurl {
        url = "${baseUrl}/normalizer.json";
        hash = "sha256-vxxQfchyTKnPmQNkDaz7adri8A7e5PIc66EGpzkvJt0=";
      };

      installPhase = ''
        mkdir -p $out/whisper

        # Copy all fetched files to the output directory
        cp $model $out/whisper/model.safetensors
        cp $config $out/whisper/config.json
        cp $tokenizer $out/whisper/tokenizer.json
        cp $vocab $out/whisper/vocab.json
        cp $merges $out/whisper/merges.txt
        cp $generationConfig $out/whisper/generation_config.json
        cp $tokenizerConfig $out/whisper/tokenizer_config.json
        cp $preprocessorConfig $out/whisper/preprocessor_config.json
        cp $specialTokensMap $out/whisper/special_tokens_map.json
        cp $normalizer $out/whisper/normalizer.json
      '';

      meta = {
        description = "OpenAI Whisper tiny model for speech recognition";
        homepage = "https://huggingface.co/openai/whisper-tiny";
        license = lib.licenses.asl20;
      };
    };
  in {
    packages = {
      inherit whisper-tiny;
    };
  };
}
