# MacBook Air M2 — the target machine.
{ ... }:
{
  networking.hostName = "m2air";

  hardware.asahi = {
    enable = true;
  };
  # Audio: speaker support comes via the asahi ALSA UCM profiles shipped
  # in the hardware module's packages; tune in hosts/ if bring-up misbehaves.

  # Disk layout target (see docs/install-m2air.md and DR-4):
  #   - macOS partition ~120G (kept: firmware updates, recovery)
  #   - exFAT shared partition (transfer shelf; no journaling, no LUKS)
  #   - LUKS2 + ext4 root (hardware full-disk encryption is not available
  #     under Asahi; LUKS is software-only but sound)
  #
  # Device names are set at install time; these are the target-layout
  # declarations the installer writes into the system closure.
  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/ESP"; # Asahi ESP, shared with m1n1
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };
  fileSystems."/mnt/shared" = {
    device = "/dev/disk/by-label/shared"; # exFAT transfer shelf (DR-4)
    fsType = "exfat";
    options = [
      "defaults"
      "umask=000"
      "nofail"
    ];
  };
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-partlabel/cryptroot";
    allowDiscards = true;
  };

  users.users.thomas = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = "/run/current-system/sw/bin/zsh";
    # Provision the real key at install time; never commit it.
    openssh.authorizedKeys.keys = [ ];
  };

  security.sudo.wheelNeedsPassword = true;
}
