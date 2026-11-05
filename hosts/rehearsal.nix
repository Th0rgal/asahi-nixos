# Rehearsal machine: rented Mac mini M2 on Scaleway.
# Goal: validate boot chain + install flow + upgrade path on real BootROM
# with a provider-side reset as the only safety net. Nothing else.
# No personal config, no keys, no data. Disposable by design.
{ lib, ... }:
{
  networking.hostName = "rehearsal";

  hardware.asahi.enable = true;

  # Disposable box: single plain ext4 root, no LUKS (DR-3).
  fileSystems."/" = {
    device = "/dev/disk/by-label/rehearsal-root";
    fsType = "ext4";
  };

  # Allow a password during rehearsal only: the box has no SSH keys on
  # first boot from the ISO. Revert before the Air install runbook.
  services.openssh.settings.PasswordAuthentication = lib.mkForce true;

  users.users.rehearsal = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "rehearsal"; # disposable box, provider-side reset
  };
}
