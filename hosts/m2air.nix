# MacBook Air M2 — the target machine.
{ inputs, pkgs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    ../modules/disko-m2air.nix
    ../modules/hardening.nix
    ../modules/containers.nix
    ../modules/secrets.nix
  ];

  networking.hostName = "m2air";

  hardware.asahi = {
    enable = true;
  };
  # Audio: speaker support comes via the asahi ALSA UCM profiles shipped
  # in the hardware module's packages; tune in hosts/ if bring-up misbehaves.

  environment.systemPackages = [ pkgs.exfatprogs ];

  users.users.thomas = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" ];
    shell = "/run/current-system/sw/bin/zsh";
    # Provision the real key at install time; never commit it.
    openssh.authorizedKeys.keys = [ ];
  };

  security.sudo.wheelNeedsPassword = true;
}
