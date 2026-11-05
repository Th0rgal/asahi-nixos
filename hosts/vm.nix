# Plain aarch64 QEMU guest — software test target for hosts/common.nix
# and install-flow rehearsal. No Asahi hardware module: QEMU does not
# emulate Apple hardware.
{ modulesPath, lib, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  networking.hostName = "vmtest";

  # Software stand-in for the disk layout; only the mount points and the
  # shared-config surface are under test here.
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  boot.loader.systemd-boot.enable = lib.mkForce true;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce true;

  services.qemuGuest.enable = true;

  users.users.vmtest = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "vmtest";
  };

  # The apple-silicon overlay sets aarch64 pkgs regardless; nothing
  # Asahi-specific is enabled here.
}
