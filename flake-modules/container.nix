{
  perSystem = {
    self',
    inputs',
    pkgs,
    ...
  }: let
    inherit (inputs'.nix2container.packages) nix2container;

    config = {
      Env = [
        "LC_ALL=C.UTF-8"
        "mode=http"
        "exec_timeout=100s"
        "WHISPER_TINY_DIR=/whisper"
        "http_upstream_url=http://127.0.0.1:5000"
        "ready_path=http://127.0.0.1:5000/health"
      ];
      ExposedPorts = {
        "8080/tcp" = {};
      };
      Cmd = ["of-watchdog"];
      WorkingDir = "/";
    };

    # weird layers are due to https://github.com/nlewo/nix2container/issues/41
    # where layers normally fail to remove duplicate deps

    whisper = nix2container.buildLayer {
      copyToRoot = pkgs.buildEnv {
        name = "whisper";
        paths = [self'.packages.whisper-tiny];
        pathsToLink = ["/whisper"];
      };
    };
    ffmpeg = nix2container.buildLayer {
      copyToRoot = pkgs.buildEnv {
        name = "ffmpeg";
        paths = [pkgs.ffmpeg-headless];
        pathsToLink = ["/bin"];
      };
    };
    prod_deps = nix2container.buildLayer {
      copyToRoot = pkgs.buildEnv {
        name = "root";
        paths = [self'.packages.prod.propagatedBuildInputs];
        pathsToLink = ["/bin"];
      };
    };
    prod = nix2container.buildLayer {
      copyToRoot = pkgs.buildEnv {
        name = "root";
        paths = [self'.packages.prod];
        pathsToLink = ["/bin"];
      };
    };
    watchdog = nix2container.buildLayer {
      copyToRoot = pkgs.buildEnv {
        name = "watchdog";
        paths = [inputs'.giraff.packages.fwatchdog];
        pathsToLink = ["/bin"];
      };
      layers = [
        prod
        prod_deps
      ];
    };
  in {
    packages = {
      giraff_app = nix2container.buildImage {
        name = "ghcr.io/volodiapg/giraff";
        tag = "giraff_app";
        inherit config;
        layers = [
          prod
          prod_deps
          watchdog
        ];
      };
      giraff_speech = nix2container.buildImage {
        name = "ghcr.io/volodiapg/giraff";
        tag = "giraff_speech";
        inherit config;
        layers = [
          whisper
          prod
          prod_deps
          ffmpeg
          watchdog
        ];
      };
    };
  };
}
