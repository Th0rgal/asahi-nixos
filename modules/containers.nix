{
  inputs,
  pkgs,
  ...
}:
let
  hostWorkdir = "/var/lib/containers-workdir/dev-untrusted";
  forwardedHostPort = 18080;
  forwardedContainerPort = 8080;
in
{
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

  networking.firewall = {
    extraCommands = ''
      ip46tables -w -I nixos-fw 1 -i ve-+ -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept
      ip46tables -w -I nixos-fw 2 -i ve-+ -j nixos-fw-refuse
      ip46tables -w -I FORWARD 1 -i ve-+ -j DROP
    '';
    extraStopCommands = ''
      ip46tables -w -D nixos-fw -i ve-+ -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept 2>/dev/null || true
      ip46tables -w -D nixos-fw -i ve-+ -j nixos-fw-refuse 2>/dev/null || true
      ip46tables -w -D FORWARD -i ve-+ -j DROP 2>/dev/null || true
    '';
  };

  containers.dev-untrusted = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.233.1.1";
    localAddress = "10.233.1.2";
    privateUsers = "pick";
    nixpkgs = inputs.nixpkgs-toolchains;

    forwardPorts = [
      {
        protocol = "tcp";
        hostPort = forwardedHostPort;
        containerPort = forwardedContainerPort;
      }
    ];

    bindMounts."/workspace" = {
      hostPath = hostWorkdir;
      mountPoint = "/workspace:idmap";
      isReadOnly = false;
    };

    config =
      { pkgs, ... }:
      {
        system.stateVersion = "25.05";

        nix.registry.nixpkgs.flake = inputs.nixpkgs-toolchains;

        networking = {
          useHostResolvConf = false;
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
}
