# MacBook Air M2 — the primary Apple Silicon daily driver.
{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    ../modules/omarchnix.nix
    ../modules/disko-m2air.nix
  ];

  networking.hostName = "m2air";

  omarchnix = {
    enable = true;
    profile = "asahi";
    hardening.enable = true;
    containers.enable = true;
    secrets.enable = true;
    desktop = {
      enable = true;
      user = "thomas";
    };
    hardware.m2air.enable = true;
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
    # Provision the real key at install time; never commit it.
    openssh.authorizedKeys.keys = [ ];
  };

  security.sudo.wheelNeedsPassword = true;
}
