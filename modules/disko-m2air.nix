{
  disko.devices = {
    disk.nvme0n1 = {
      type = "disk";
      device = "/dev/nvme0n1";
      destroy = false;

      content = {
        type = "gpt";
        preCreateHook = ''
          if sgdisk -p "$device" 2>/dev/null | grep -Eq 'iBootSystemContainer|RecoveryOSContainer|AF0A'; then
            echo "Refusing full-disk disko format on live Apple Silicon GPT ($device): macOS/Asahi bootstrap partitions exist; format only free-space NixOS partitions per docs/install-m2air.md." >&2
            exit 1
          fi
        '';

        partitions = {
          ESP = {
            priority = 100;
            label = "ESP";
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              extraArgs = [
                "-F"
                "32"
                "-n"
                "ESP"
              ];
              mountpoint = "/boot";
              mountOptions = [
                "fmask=0077"
                "dmask=0077"
              ];
            };
          };

          shared = {
            priority = 200;
            label = "shared";
            size = "150G";
            type = "0700";
            content = {
              type = "filesystem";
              format = "exfat";
              extraArgs = [
                "-L"
                "shared"
              ];
              mountpoint = "/mnt/shared";
              mountOptions = [
                "defaults"
                "umask=000"
                "nofail"
              ];
            };
          };

          cryptroot = {
            priority = 300;
            label = "cryptroot";
            size = "100%";
            type = "8309";
            content = {
              type = "luks";
              name = "cryptroot";
              extraFormatArgs = [
                "--type"
                "luks2"
                "--pbkdf"
                "argon2id"
              ];
              settings = {
                allowDiscards = true;
              };
              content = {
                type = "filesystem";
                format = "ext4";
                extraArgs = [
                  "-L"
                  "nixos"
                ];
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
