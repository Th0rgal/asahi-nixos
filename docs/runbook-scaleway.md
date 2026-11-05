# Runbook — rehearsal on Scaleway Mac mini M2

Purpose: pass gates G4 (Asahi bootstrap on real BootROM) and G5 (NixOS
install + rebuild) on disposable hardware. Budget the box at a few days
of €0.17/h. Record every session in `docs/logs/g4-g5-<date>.md`.

## 0. Preconditions

- [ ] `gh run` shows the CI `installer-iso` artifact green on `main`
- [ ] ISO downloaded and SHA256 recorded
- [ ] SSH key for the rehearsal box generated (throwaway)
- [ ] Scaleway console access + remote screen (VNC) confirmed working

## 1. Provision

- [ ] Create Mac mini M2 (M2-M), macOS image, PAR zone
- [ ] Enable remote screen (VNC) — the Asahi installer prompts and the
      first UEFI boot need console access, not just SSH
- [ ] Note the public IP; SSH to macOS as `root` (Scaleway default)

## 2. Asahi bootstrap (from macOS, as root)

```console
# curl https://alx.sh | sh
```

- [ ] Choose **Rebuild vendor firmware package**
- [ ] Quit the installer and reboot once done (per nixos-apple-silicon
      release notes)
- [ ] Reboot into macOS, rerun the installer, choose
      **Resign and save boot objects** — this writes m1n1/U-Boot without
      installing a distro
- [ ] Record: m1n1 version, U-Boot output on next boot (VNC)

## 3. Boot the NixOS ISO

- [ ] Attach the ISO: reboot into macOS, run the Asahi installer's
      option to set the UEFI boot medium to the internal disk UEFI
      (m1n1 → U-Boot → `boot.efi`), then place the ISO contents on a
      small FAT partition (or use the installer's UEFI env) — follow
      `nixos-apple-silicon/docs/uefi-standalone.md` for the supported
      path for this release
- [ ] Boot into the NixOS installer ISO over VNC

## 4. Install NixOS (gate G5)

- [ ] Partition: single ext4 root (no LUKS needed on a disposable box)
- [ ] Install with this flake's `rehearsal` host as the closure
- [ ] Reboot into NixOS on the mini — record the boot log
- [ ] `nixos-rebuild switch --flake .#rehearsal` — record output
- [ ] Confirm network, `nixos-rebuild --upgrade` path works

## 5. Teardown

- [ ] Delete the server from the Scaleway console
- [ ] Delete the throwaway SSH key
- [ ] Write the G4/G5 gate log; update the README status matrix
