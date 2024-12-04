{
  self,
  inputs,
  ...
}: let
  inherit (inputs) nixpkgs;
in {
  flake = {
    functions.x86_64-linux.buildVm = hostName:
      assert (builtins.stringLength hostName) <= 20 || abort "Hostname is required to be < 20";
      with rec {
        str = builtins.hashString "md5" hostName;
        len = builtins.stringLength str;
        id = builtins.substring (len - 6) 6 str;
        macpart = builtins.concatStringsSep ":" (map (idx: builtins.substring idx 2 id) (builtins.genList (x: x * 2) 3));
      };
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            self.nixosModules.function
            self.nixosModules.tailscale
            inputs.microvm.nixosModules.microvm
            ({
              config,
              lib,
              ...
            }: {
              boot.initrd.systemd.enable = false;

              users.users.root.password = "root";
              services.openssh = {
                enable = true;
                settings.PermitRootLogin = "yes";
              };
              system.switch.enable = false;

              services.tailscale = {
                enable = true;
                interfaceName = "tailscale0";
                auth = {
                  enable = true;
                  args = {
                    advertise-tags = ["tag:server"];
                    ssh = true;
                    accept-routes = false;
                    accept-dns = true;
                    auth-key = "file:/tailscale/tailscale.authkey";
                  };
                };
              };

              networking = {
                inherit hostName;
                firewall = {
                  allowedUDPPorts = [67];
                  trustedInterfaces = ["tailscale0"];
                };
                useNetworkd = true;
              };
              fileSystems = {
                "/tailscale".neededForBoot = true;
                "/nix/.ro-store".neededForBoot = true;
                "/meta".neededForBoot = true;
              };

              fileSystems."/" = {
                device = "none";
                fsType = "tmpfs";
                options = ["defaults" "mode=755"];
              };

              environment = {
                # Print the URL instead on servers
                variables.BROWSER = "echo";
                # Don't install the /lib/ld-linux.so.2 and /lib64/ld-linux-x86-64.so.2
                # stubs. Server users should know what they are doing.
                stub-ld.enable = lib.mkDefault false;
                noXlibs = false;
                # Don't install the /lib/ld-linux.so.2 stub. This saves one instance of
                # nixpkgs.
                ldso32 = null;
              };
              # Notice this also disables --help for some commands such es nixos-rebuild
              documentation = {
                enable = lib.mkDefault false;
                info.enable = lib.mkDefault false;
                man.enable = lib.mkDefault false;
                nixos.enable = lib.mkDefault false;
              };

              # No need for fonts on a server
              fonts.fontconfig.enable = lib.mkDefault false;

              systemd = {
                enableEmergencyMode = false;
                services.NetworkManager-wait-online.enable = false;
                network = {
                  wait-online.enable = false;
                  enable = true;
                };
              };

              # use TCP BBR has significantly increased throughput and reduced latency for connections
              boot.kernel.sysctl = {
                "net.core.default_qdisc" = lib.mkForce "cake"; #fq_codel also works but is older
                "net.ipv4.tcp_ecn" = 1;
                "net.ipv4.tcp_sack" = 1;
                "net.ipv4.tcp_dsack" = 1;
              };

              microvm = {
                vcpu = 4;
                mem = 4096;
                #volumes = [
                #      {
                #        mountPoint = "/var";
                #        image = "var.img";
                #        size = 256;
                #      }
                #    ];
                interfaces = [
                  {
                    type = "tap";
                    id = "vm-${toString id}";
                    mac = "02:00:00:${macpart}";
                  }
                ];
                shares = [
                  {
                    proto = "virtiofs";
                    tag = "ro-store";
                    source = "/nix/store";
                    mountPoint = "/nix/.ro-store";
                    socket = "ro-store.sock";
                  }
                  {
                    proto = "virtiofs";
                    tag = "ro-tailscale-authkey";
                    source = "/persistent/tailscale";
                    mountPoint = "/tailscale";
                    socket = "tailscale.sock";
                  }
                  {
                    proto = "virtiofs";
                    tag = "ro-env-vars";
                    source = "/var/lib/flame/${hostName}/meta";
                    mountPoint = "/meta";
                    socket = "meta.sock";
                  }
                ];

                hypervisor = "crosvm";
                socket = "control.socket";
              };
              system.stateVersion = config.system.nixos.version;
            })
          ];
        };

    packages.x86_64-linux.microvm = self.nixosConfigurations.microvm.config.microvm.deploy.installOnHost;
    nixosConfigurations.microvm = self.functions.x86_64-linux.buildVm "microvm";
  };
}
