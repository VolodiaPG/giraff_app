{
  perSystem = {pkgs, ...}: let
    # Base URL for the model files
    bert-tweeter = pkgs.stdenv.mkDerivation {
      pname = "bert-tweeter";
      version = "1.0.0";

      # We don't need src since we're fetching individual files
      dontUnpack = true;
      # src = pkgs.fetchgit {
      #   url = "https://huggingface.co/finiteautomata/bertweet-base-sentiment-analysis";
      #   fetchLFS = true;
      #   branchName = "main";
      #   sha256 = "sha256-HbInZZEjOFJILGAfqu9ksfUBSHcoqlpwl2bblnIbEWw=";
      # };

      src = pkgs.fetchgit {
        url = "https://huggingface.co/phanerozoic/BERT-Sentiment-Classifier";
        fetchLFS = true;
        branchName = "main";
        sha256 = "sha256-/Excwp5WaEXm10gbukUD3SXpc5tU9a32qrAn4cPna14=";
      };

      # model = pkgs.fetchurl {
      #   url = "https://huggingface.co/finiteautomata/bertweet-base-sentiment-analysis/resolve/main/pytorch_model.bin";
      #   hash = "sha256-pIFHQYO/DKgLSFzY2N1fCBH8zjxezvhMPKGA7VSRh3E=";
      # };

      # config = pkgs.fetchurl {
      #   url = "https://huggingface.co/finiteautomata/bertweet-base-sentiment-analysis/resolve/main/config.json";
      #   hash = "sha256-I1yw0gQuS93IhS9BR1Gn7FPZ07DW9Gd8c8y+RDYgjNQ=";
      # };

      # tokenizer = pkgs.fetchurl {
      #   url = "https://huggingface.co/vinai/bertweet-base/resolve/main/tokenizer.json";
      #   hash = "sha256-SKiXKzIckxY7eNmPQLtBDYmNiGnYQ5tqu1+Cg/VFuF0=";
      # };

      installPhase = ''
         mkdir -p $out/bert-tweeter

        # cp $tokenizer $out/bert-tweeter/tokenizer.json
        #  cp $config $out/bert-tweeter/config.json
        #  cp $model $out/bert-tweeter/pytorch_model.bin
         cp $src/* $out/bert-tweeter/
      '';
    };
  in {
    packages = {
      inherit bert-tweeter;
    };
  };
}
