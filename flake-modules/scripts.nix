{self, ...}: {
  perSystem = {
    config,
    self',
    pkgs,
    ...
  }: {
    scripts = {
      src = ../scripts;
      scripts = {
        vm_deploy = {
          substitutions = {
            flake = "${self}";
          };
          deps = with pkgs; [
            nix
            coreutils
            moreutils
          ];
        };
        vm_remove = {
          substitutions = {
            flake = "${self}";
          };
          deps = with pkgs; [
            coreutils
          ];
        };
        vm_get_ipv6 = {
          deps = with pkgs; [
            jq
            tailscale
          ];
        };
        vm_wait_online = {
          deps = with pkgs; [
            jq
            tailscale
          ];
        };
        check_ts = {
          deps = with pkgs; [
            jq
            tailscale
          ];
        };
        entrypoint = {
          deps = [
            self'.packages.node_name
            self'.packages.prod
            pkgs.ffmpeg_7-headless
          ];
        };
        node_name = {
          deps = with pkgs; [
            tailscale
            jq
          ];
        };
      };
    };
  };
}
