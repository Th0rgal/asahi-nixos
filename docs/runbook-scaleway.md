# Runbook — Scaleway `M2-L-ASAHI` cutover to NixOS

Purpose: pass gates G4 (boot chain inspection on real BootROM) and G5
(NixOS install and `nixos-rebuild switch` on `rehearsal`) without touching
the MacBook Air. Record the session in `docs/logs/g4-g5-<date>.md`.

## Why `M2-L-ASAHI`

Scaleway macOS Mac minis (`M1-M` in `fr-par-3`, `M2-M` and `M2-L` in
`fr-par-1`) expose only macOS `screensharingd` VNC. There is no hardware
KVM, and MDM blocks 1TR Recovery and `bputil`, so `curl https://alx.sh | sh`
cannot run. `M4-*` has no Asahi support (DR-12).

`M2-L-ASAHI` (`fr-par-1`, Mac mini M2 Pro, 10 cores, 16 GiB RAM, 412 GB SSD,
€0.21/h, 0-hour minimum lease) boots Fedora Asahi Remix 42 with `m1n1`,
U-Boot, and `/boot/asahi` vendor firmware already installed.

> **Never halt or sleep the box.** Scaleway has no remote power button. A
> clean `poweroff`, `halt`, or suspend bricks the rental until a provider
> reset. `hosts/rehearsal.nix` forces `systemd-poweroff` and `systemd-halt`
> to `systemctl --force --force reboot` and disables every sleep target. Do
> the same from Fedora before touching disks.

## 0. Preconditions

- [ ] CI on `main` is green, including `installer-iso`.
- [ ] Hold the private half of the throwaway rehearsal key matching
      `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrDpszSSJT9ZfrkTp/pPvA9vfzV0QGizKDTP2HEBG4Q`
      outside git (DR-6).
- [ ] Scaleway project access in `fr-par-1` is ready. (As of 2026-11-06, Orb
      `spawn_managed_machine` does not yet allowlist `M2-L-ASAHI` — see
      `docs/logs/m5-m7-2026-11-06.md`; create it in the Scaleway console or
      `scw apple-silicon server create` directly.)

## 1. Provision `M2-L-ASAHI`

```console
$ scw apple-silicon server create zone=fr-par-1 type=M2-L-ASAHI name=omarchnix-rehearsal
```

- [ ] Encrypt the assigned IP into `secrets/rehearsal.yaml`:
      `sops --config .sops.yaml -e -i secrets/rehearsal.yaml`
- [ ] SSH into Fedora Asahi Remix 42 with the throwaway key and disarm halt
      immediately:

```console
# systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
# ln -sf /usr/lib/systemd/system/systemd-reboot.service /etc/systemd/system/systemd-poweroff.service
# ln -sf /usr/lib/systemd/system/systemd-reboot.service /etc/systemd/system/systemd-halt.service
# systemctl daemon-reload
```

## 2. Gate G4 — inspect and preserve the Asahi boot chain

Do **not** format the EFI system partition or overwrite `m1n1` / U-Boot.

```console
# lsblk -o NAME,PARTLABEL,FSTYPE,SIZE,MOUNTPOINTS
# ls -la /boot/efi /boot/efi/asahi /boot/efi/m1n1
# sha256sum /boot/efi/m1n1/boot.bin /boot/efi/asahi/*
```

- [ ] Record partition table, `m1n1` hash, U-Boot version, and peripheral
      firmware archive hashes in `docs/logs/g4-g5-<date>.md`.
- [ ] Copy `/boot/efi/asahi` (all `.cpio` / `.tar` firmware archives) to a
      temporary backup directory in RAM (`/tmp/asahi-fw`) and keep the EFI
      partition untouched.

## 3. Prepare `rehearsal-root` without touching EFI

Pick a spare root partition or shrink Fedora's Btrfs/ext4 volume from a
ramdisk pivot (`nixos-anywhere --no-substitute-on-destination` or kexec /
U-Boot EFI entry), keeping `/dev/disk/by-partlabel/EFI` intact:

1. Download the CI `installer-bootstrap` ISO artifact (or build
   `.#nixosConfigurations.rehearsal.config.system.build.toplevel` directly
   with Nix on Fedora Asahi).
2. Create or relabel the target ext4 filesystem as `rehearsal-root`:

```console
# mkfs.ext4 -L rehearsal-root /dev/<target-partition>
# mkdir -p /mnt
# mount /dev/disk/by-label/rehearsal-root /mnt
```

3. Stage U-Boot's UEFI payload on the existing EFI partition **alongside**
   `m1n1` (preserving `/boot/efi/m1n1` and `/boot/efi/asahi`): install
   NixOS's kernel/initrd EFI stub entry under `/boot/efi/EFI/BOOT/BOOTAA64.EFI`
   only after backing up Fedora's `EFI/fedora` entry so U-Boot falls back
   cleanly if needed.

## 4. Gate G5 — install and rebuild `rehearsal`

```console
# nix --extra-experimental-features 'nix-command flakes' \
    build github:Th0rgal/omarchnix#nixosConfigurations.rehearsal.config.system.build.toplevel \
    --out-link /tmp/rehearsal-system
# nixos-install --root /mnt --system /tmp/rehearsal-system --no-root-passwd --no-bootloader
# sync
# systemctl reboot
```

After reboot into NixOS (`ssh rehearsal@<ip>` with the throwaway key):

```console
$ uname -a
$ systemctl status systemd-poweroff.service systemd-halt.service
$ omarchnix status --json
$ sudo nixos-rebuild switch --flake github:Th0rgal/omarchnix#rehearsal
```

- [ ] Confirm `boot.loader.*` did not touch `/boot/asahi` (DR-5).
- [ ] Confirm `omarchnix status --json` reports the expected `asahi` profile on real M2 silicon.
- [ ] Confirm a second `sudo systemctl reboot` returns cleanly over SSH.

## 5. Teardown

```console
$ scw apple-silicon server delete <server-id> zone=fr-par-1
```

- [ ] Confirm `0` running Scaleway servers remain (`M2-L-ASAHI` has 0h
      minimum lease, so billing stops on deletion).
- [ ] Shred the local private half of the throwaway rehearsal key if rotated.
- [ ] Commit `docs/logs/g4-g5-<date>.md` and update the README gate table.
