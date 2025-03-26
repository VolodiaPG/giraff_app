{
  perSystem = {pkgs, ...}: let
    python-vosk = pkgs.python3.withPackages (
      ps: (with ps; [
        (buildPythonPackage rec {
          pname = "vosk";
          version = "0.3.45";
          format = "wheel";

          src = pkgs.fetchPypi {
            inherit pname version format;
            hash = "sha256-JeAlCTxDmdcnj1Q1aO2MxUYKw6S/SMI2c6zh4l0mYZ8=";
            dist = python;
            python = "py3";
            abi = "none";
            platform = "manylinux_2_12_x86_64.manylinux2010_x86_64";
          };

          # https://pypi.org/pypi/vosk/json
          propagatedBuildInputs = with pkgs.python3Packages; [
            cffi
            requests
            srt
            tqdm
            websockets
          ];
        })
        # (buildPythonPackage rec {
        #   pname = "SpeechRecognition";
        #   version = "3.10.0";
        #   format = "wheel";

        #   src = pkgs.fetchPypi {
        #     inherit pname version format;
        #     hash = "sha256-eumWaIfZkJzj5aDCfsw+rPyhb9DAgp939VKRlBjoYwY=";
        #   };

        #   # https://pypi.org/pypi/SpeechRecognition/json
        #   propagatedBuildInputs = with pkgs.python3Packages; [
        #     requests
        #   ];
        # })
      ])
    );

    voskModel = pkgs.stdenv.mkDerivation rec {
      pname = "vosk-model-small-en-us";
      version = "0.15";
      src = builtins.fetchurl {
        url = "https://alphacephei.com/vosk/models/${pname}-${version}.zip";
        sha256 = "sha256:1614jj01gx4zz5kq6fj2lclwp1m6swnk1js2isa9yi7bqi165wih";
      };
      nativeBuildInputs = [pkgs.unzip];
      unpackPhase = "unzip $src -d folder";
      installPhase = ''
        mkdir -p $out/vosk
        cp -r folder/${pname}-${version}/* $out/vosk/
      '';
    };
  in {
    packages = {
      inherit voskModel python-vosk;
    };
  };
}
