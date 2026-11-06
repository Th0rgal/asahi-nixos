# MacBook Air M2 — the target machine.
{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
    ../modules/disko-m2air.nix
    ../modules/hardware-m2air.nix
    ../modules/hardening.nix
    ../modules/containers.nix
    ../modules/secrets.nix
  ];

  networking.hostName = "m2air";

  omarchnix.hardware.m2air.enable = true;

  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  security.pam.services.hyprlock = { };
  security.polkit.enable = true;

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

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.thomas = import ../home;
  };

  security.sudo.wheelNeedsPassword = true;
}
