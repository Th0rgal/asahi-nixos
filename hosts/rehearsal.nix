# Rehearsal machine: rented Scaleway M2-L-ASAHI Mac mini.
# Goal: validate boot chain + install flow + upgrade path on real BootROM
# with a provider-side reset as the only safety net. Nothing else.
# No personal config, no owner keys, no data. Disposable by design.
{ lib, pkgs, ... }:
{
  imports = [
    ../modules/omarchnix.nix
  ];

  networking.hostName = "rehearsal";

  omarchnix = {
    enable = true;
    profile = "asahi";
    hardening.enable = false;
    containers.enable = false;
    secrets.enable = false;
    desktop.enable = false;
    verifiedUserspace.enable = true;
  };

  hardware.asahi = {
    enable = true;
    setupAsahiSound = false;
    extractPeripheralFirmware = false;
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/rehearsal-root";
    fsType = "ext4";
    options = [ "defaults" ];
  };

  fileSystems."/boot/asahi" = {
    device = "/dev/disk/by-partlabel/EFI";
    fsType = "vfat";
    options = [
      "ro"
      "nofail"
      "noauto"
    ];
  };

  services.logind.settings.Login = {
    HandlePowerKey = "reboot";
    HandlePowerKeyLongPress = "reboot";
    HandleRebootKey = "reboot";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    IdleAction = "ignore";
  };

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  systemd.services.systemd-poweroff.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${pkgs.systemd}/bin/systemctl --force --force reboot"
  ];
  systemd.services.systemd-halt.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${pkgs.systemd}/bin/systemctl --force --force reboot"
  ];

  security.sudo.wheelNeedsPassword = false;

  users.users.rehearsal = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrDpszSSJT9ZfrkTp/pPvA9vfzV0QGizKDTP2HEBG4Q rehearsal-throwaway"
    ];
  };
}
