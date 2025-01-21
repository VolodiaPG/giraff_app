{
  perSystem = {
    self',
    inputs',
    pkgs,
    ...
  }: let
    makeLayer = {
      fromImage ? null,
      name,
      pathsToLink ? ["/bin"],
      paths ? [],
    }:
      pkgs.dockerTools.buildImage {
        inherit name fromImage;
        copyToRoot =
          pkgs.buildEnv
          {
            inherit name pathsToLink paths;
          };
      };

    dockerGen = {
      tag,
      fromImage,
    }:
      pkgs.dockerTools.streamLayeredImage {
        name = "giraff";
        inherit tag fromImage;

        config = {
          Env = [
            "LC_ALL=C.UTF-8"
            "mode=http"
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
      };

    watchdog = makeLayer {
      name = "watchdog";
      paths = [inputs'.giraff.packages.fwatchdog];
    };
    baseimage = makeLayer {
      name = "prod";
      fromImage = watchdog;
      paths = [self'.packages.prod];
    };
    models = makeLayer {
      name = "models";
      fromImage = baseimage;
      pathsToLink = ["/whisper"];
      paths = [self'.packages.whisper-tiny];
    };
  in {
    packages = {
      giraff_app = dockerGen {
        tag = "app";
        fromImage = baseimage;
      };
      giraff_speech = dockerGen {
        tag = "speech";
        fromImage = models;
      };
    };
  };
}
