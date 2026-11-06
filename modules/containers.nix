{
  config,
  lib,
  pkgs,
  ...
}@args:
let
  inputs = args.inputs or null;
  enabled = !(config ? omarchnix) || !config.omarchnix.enable || config.omarchnix.containers.enable;
  containerNixpkgs =
    if inputs != null && inputs ? nixpkgs-toolchains then
      inputs.nixpkgs-toolchains
    else if inputs != null && inputs ? nixpkgs then
      inputs.nixpkgs
    else
      pkgs.path;
  hostWorkdir = "/var/lib/containers-workdir/dev-untrusted";
  hostVeth = "ve-dev-untrust";
  forwardedHostPort = 18080;
  forwardedContainerPort = 8080;
in
{
  config = lib.mkIf enabled {
    boot.enableContainers = true;

    environment.systemPackages = [
      pkgs.bubblewrap
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/containers-workdir 0755 root root - -"
      "d ${hostWorkdir} 0755 1000 100 - -"
    ];

    systemd.services."container@dev-untrusted" = {
      after = [
        "systemd-tmpfiles-setup.service"
        "firewall.service"
      ];
      requires = [ "systemd-tmpfiles-setup.service" ];
    };

    boot.kernel.sysctl."net.ipv4.conf.${hostVeth}.route_localnet" = 1;
    boot.kernel.sysctl."net.ipv4.conf.all.route_localnet" = 1;

    networking.firewall = {
      extraCommands = ''
        ip46tables -w -I nixos-fw 1 -i ve-+ -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
        ip46tables -w -I nixos-fw 2 -i ve-+ -j nixos-fw-refuse
        ip46tables -w -I FORWARD 1 -i ve-+ -j DROP
        iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport ${toString forwardedHostPort} \
          -j DNAT --to-destination 10.233.1.2:${toString forwardedContainerPort}
        iptables -t nat -A POSTROUTING -o ${hostVeth} -p tcp -s 127.0.0.0/8 -d 10.233.1.2 --dport ${toString forwardedContainerPort} \
          -j SNAT --to-source 10.233.1.1
      '';
      extraStopCommands = ''
        iptables -t nat -D POSTROUTING -o ${hostVeth} -p tcp -s 127.0.0.0/8 -d 10.233.1.2 --dport ${toString forwardedContainerPort} \
          -j SNAT --to-source 10.233.1.1 2>/dev/null || true
        iptables -t nat -D OUTPUT -p tcp -d 127.0.0.1 --dport ${toString forwardedHostPort} \
          -j DNAT --to-destination 10.233.1.2:${toString forwardedContainerPort} 2>/dev/null || true
        ip46tables -w -D nixos-fw -i ve-+ -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept 2>/dev/null || true
        ip46tables -w -D nixos-fw -i ve-+ -j nixos-fw-refuse 2>/dev/null || true
        ip46tables -w -D FORWARD -i ve-+ -j DROP 2>/dev/null || true
      '';
    };

    containers.dev-untrusted = {
      autoStart = true;
      privateNetwork = true;
      extraVeths.${hostVeth} = {
        hostAddress = "10.233.1.1";
        localAddress = "10.233.1.2";
      };
      privateUsers = "pick";
      nixpkgs = containerNixpkgs;

      bindMounts."/workspace" = {
        hostPath = hostWorkdir;
        mountPoint = "/workspace:idmap";
        isReadOnly = false;
      };

      config =
        { pkgs, ... }:
        {
          system.stateVersion = "25.05";

          nix.registry = lib.mkIf (inputs != null && inputs ? nixpkgs-toolchains) {
            nixpkgs.flake = inputs.nixpkgs-toolchains;
          };

          networking = {
            useHostResolvConf = false;
            defaultGateway = {
              address = "10.233.1.1";
              interface = hostVeth;
            };
            firewall = {
              enable = true;
              allowPing = false;
              allowedTCPPorts = [ forwardedContainerPort ];
            };
          };

          users.users.dev = {
            isNormalUser = true;
            uid = 1000;
            group = "users";
          };

          environment.systemPackages = [
            pkgs.git
            pkgs.gnumake
            pkgs.netcat-openbsd
          ];
        };
    };
  };
}
