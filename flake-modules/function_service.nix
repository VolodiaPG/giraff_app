{self, ...}: {
  flake.nixosModules.function = {pkgs, ...}: {
    systemd.services.flame = {
      description = "Remote FLAME function to execute and connect to the main app";
      after = ["tailscale-auth.service"];
      restartTriggers = ["${self.outputs.packages.${pkgs.system}.entrypoint}/bin/entrypoint}"];
      wantedBy = ["multi-user.target"];
      environment = {
        LANG = "C.UTF-8";
        SHELL = "${pkgs.bash}/bin/bash";
      };
      serviceConfig = {
        Type = "simple";
        RestartSec = 0;
        Restart = "on-failure";
        ExecStart = "${self.outputs.packages.${pkgs.system}.entrypoint}/bin/entrypoint";
        DynamicUser = "yes";
      };
    };
  };
}
