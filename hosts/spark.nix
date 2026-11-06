# NVIDIA Grace / DGX Spark ARM64 (`aarch64-linux`) reference workstation & server host.
{ inputs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    ../modules/omarchnix.nix
  ];

  networking.hostName = "spark";

  omarchnix = {
    enable = true;
    profile = "spark";
    hardening.enable = true;
    containers.enable = true;
    secrets.enable = true;
    desktop = {
      enable = true;
      user = "thomas";
    };
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/omarchnix-root";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  users.users.thomas = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [
      "wheel"
      "video"
      "render"
      "audio"
      "networkmanager"
    ];
    shell = "/run/current-system/sw/bin/zsh";
    openssh.authorizedKeys.keys = [ ];
  };

  security.sudo.wheelNeedsPassword = true;
}
