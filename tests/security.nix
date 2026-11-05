{
  pkgs,
  lib,
  inputs,
  m2airConfig,
}:
let
  inherit (import "${inputs.nixpkgs}/nixos/tests/ssh-keys.nix" pkgs)
    snakeOilPrivateKey
    snakeOilPublicKey
    ;
in
assert m2airConfig.boot.initrd.luks.devices ? cryptroot;
assert m2airConfig.boot.initrd.luks.devices.cryptroot.device == "/dev/disk/by-partlabel/cryptroot";
assert m2airConfig.boot.initrd.luks.devices.cryptroot.allowDiscards == true;
assert m2airConfig.fileSystems."/".device == "/dev/mapper/cryptroot";
assert m2airConfig.fileSystems."/".fsType == "ext4";
assert m2airConfig.fileSystems."/boot".device == "/dev/disk/by-partlabel/ESP";
assert m2airConfig.fileSystems."/mnt/shared".device == "/dev/disk/by-partlabel/shared";
assert m2airConfig.fileSystems."/mnt/shared".fsType == "exfat";
assert m2airConfig.boot.loader.systemd-boot.enable == false;
assert m2airConfig.boot.loader.efi.canTouchEfiVariables == false;
pkgs.testers.runNixOSTest {
  name = "asahi-nixos-security";

  node.specialArgs = { inherit inputs; };

  nodes = {
    host =
      { pkgs, ... }:
      {
        imports = [
          inputs.disko.nixosModules.disko
          inputs.sops-nix.nixosModules.sops
          ../hosts/common.nix
          ../modules/disko-m2air.nix
          ../modules/hardening.nix
          ../modules/containers.nix
          ../modules/secrets.nix
        ];

        networking.hostName = "m2air-test";

        virtualisation = {
          memorySize = 2048;
          useNixStoreImage = true;
          writableStore = false;
        };

        boot.initrd.luks.devices = lib.mkVMOverride {
          cryptroot = {
            device = "/dev/disk/by-partlabel/cryptroot";
            allowDiscards = true;
          };
        };

        users.users.thomas = {
          isNormalUser = true;
          uid = 1000;
          extraGroups = [ "wheel" ];
          initialPassword = "test-password-must-not-work-over-ssh";
          openssh.authorizedKeys.keys = [ snakeOilPublicKey ];
        };

        users.users.unpriv = {
          isNormalUser = true;
          uid = 1001;
        };

        environment.systemPackages = [
          pkgs.jq
          pkgs.netcat-openbsd
          pkgs.sshpass
        ];
      };

    attacker =
      { pkgs, ... }:
      {
        networking.firewall.enable = false;
        environment.systemPackages = [
          pkgs.netcat-openbsd
          pkgs.sshpass
        ];
      };
  };

  testScript = ''
    start_all()

    host.wait_for_unit("multi-user.target")
    host.wait_for_unit("apparmor.service")
    host.wait_for_unit("sshd.service")
    host.wait_for_unit("firewall.service")
    host.wait_for_unit("container@dev-untrusted.service")
    attacker.wait_for_unit("multi-user.target")

    with subtest("Firewall is default-deny with explicit TCP/22 exception only"):
        host.succeed("nc -lk 0.0.0.0 9999 >/tmp/unexposed.log 2>&1 &")
        host.wait_for_open_port(9999)
        attacker.succeed("nc -z -w 3 host 22")
        attacker.fail("nc -z -w 2 host 9999")
        attacker.fail("ping -c 1 -W 2 host")
        attacker.fail("nc -z -w 2 host 18080")

    with subtest("SSH enforces key-only authentication and confines sshd with AppArmor"):
        sshd_cfg = host.succeed("sshd -T")
        assert "passwordauthentication no" in sshd_cfg
        assert "kbdinteractiveauthentication no" in sshd_cfg
        assert "permitrootlogin no" in sshd_cfg

        aa_json = host.succeed("aa-status --json")
        host.succeed(
            "aa-status --json | jq -e '.profiles[\"sshd\"] == \"enforce\"'"
        )
        host.succeed(
            "aa-status --json | jq -e '(.processes | to_entries | map(.value[]) | map(select(.profile == \"sshd\" and .status == \"enforce\")) | length) >= 1'"
        )

        attacker.fail(
            "sshpass -p 'test-password-must-not-work-over-ssh' ssh "
            "-o PreferredAuthentications=password,keyboard-interactive "
            "-o PubkeyAuthentication=no "
            "-o StrictHostKeyChecking=no "
            "-o UserKnownHostsFile=/dev/null "
            "thomas@host true"
        )

        attacker.succeed("install -d -m 700 /root/.ssh")
        attacker.succeed("cat ${snakeOilPrivateKey} > /root/.ssh/id_key && chmod 600 /root/.ssh/id_key")
        out = attacker.succeed(
            "ssh -i /root/.ssh/id_key "
            "-o IdentitiesOnly=yes "
            "-o StrictHostKeyChecking=no "
            "-o UserKnownHostsFile=/dev/null "
            "thomas@host id -un"
        ).strip()
        assert out == "thomas", f"expected thomas, got {out!r}"

    with subtest("sudo execWheelOnly and supported kernel hardening sysctls"):
        host.fail("su -s /bin/sh unpriv -c 'sudo -n true'")
        host.succeed("systemctl is-active systemd-sysctl.service")
        assert host.succeed("sysctl -n kernel.kptr_restrict").strip() == "2"
        assert host.succeed("sysctl -n kernel.dmesg_restrict").strip() == "1"
        assert host.succeed("sysctl -n kernel.unprivileged_bpf_disabled").strip() == "1"
        assert host.succeed("sysctl -n kernel.yama.ptrace_scope").strip() == "1"
        assert host.succeed("sysctl -n fs.suid_dumpable").strip() == "0"
        assert host.succeed("sysctl -n net.ipv4.ip_forward").strip() == "0"

    with subtest("LUKS2 cryptroot device is wired into initrd"):
        host.succeed("lsinitrd /run/booted-system/initrd | grep -q cryptsetup")
        host.succeed("lsinitrd /run/booted-system/initrd | grep -q dm_crypt")
        initrd_init = host.succeed("lsinitrd /run/booted-system/initrd init")
        assert "cryptroot" in initrd_init or "cryptsetup" in initrd_init

    with subtest("Declarative dev-untrusted container starts, shifts UIDs, and cannot reach host or WAN"):
        state = host.succeed("nixos-container status dev-untrusted").strip()
        assert state == "up", f"expected container up, got {state!r}"

        leader_pid = host.succeed("machinectl show dev-untrusted -p Leader --value").strip()
        leader_uid = int(host.succeed(f"stat -c '%u' /proc/{leader_pid}").strip())
        assert leader_uid >= 65536, f"expected user-namespaced leader UID >= 65536, got {leader_uid}"

        host.succeed(
            "nixos-container run dev-untrusted -- su -s /bin/sh dev -c "
            "'echo isolated-ok > /workspace/from-container'"
        )
        assert host.succeed("cat /var/lib/containers-workdir/dev-untrusted/from-container").strip() == "isolated-ok"
        assert host.succeed("stat -c '%u:%g' /var/lib/containers-workdir/dev-untrusted/from-container").strip() == "1000:100"

        host.fail(
            "nixos-container run dev-untrusted -- "
            "bash -c 'exec 3<>/dev/tcp/10.233.1.1/22'"
        )
        host.fail(
            "nixos-container run dev-untrusted -- "
            "bash -c 'exec 3<>/dev/tcp/10.233.1.1/9999'"
        )
        attacker_ip = attacker.succeed("hostname -I | awk '{print $1}'").strip()
        host.fail(
            f"nixos-container run dev-untrusted -- bash -c 'exec 3<>/dev/tcp/{attacker_ip}/22'"
        )

        host.succeed(
            "nixos-container run dev-untrusted -- "
            "su -s /bin/sh dev -c "
            "'nohup nc -lk 0.0.0.0 8080 >/tmp/nc.log 2>&1 </dev/null &'"
        )
        host.wait_until_succeeds("nc -z -w 2 127.0.0.1 18080")
  '';
}
