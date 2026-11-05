# Runbook — MacBook Air M2 install (gate G6)

Do not start until G1–G5 are green and logged.

## 0. Preconditions

- [ ] All gates G1–G5 passed with logs in `docs/logs/`
- [ ] Time Machine backup of the Air, verified
- [ ] macOS updated to latest (firmware baseline)
- [ ] Free disk: shrink macOS APFS container to ~120 GB in Disk Utility
- [ ] Create the ~150 GB exFAT partition in Disk Utility
      (name: `shared`, scheme: GUID, FS: exFAT)

## 1. Install (in macOS)

Two known-good paths — DR-1:

- **Path A (NixOS target):** Asahi installer per
  `runbook-scaleway.md` steps 2–3, then the NixOS ISO built from this
  flake; partition the free space with LUKS2 + ext4, install the
  `m2air` closure.
- **Path B (fallback, if Path A stalls):** the Omarchy Mac installer,
  dual-boot, revisit Nix later (DR-1).

## 2. First boot checks

- [ ] Boot picker (hold power) shows both macOS and Linux
- [ ] Wi-Fi, keyboard, trackpad, display (incl. brightness) work
- [ ] Speaker + mic (ALS UCM) — `hardware.asahi.audio = "speakers"`
- [ ] Sleep/wake, battery reporting
- [ ] USB-C: at least charge + one device
- [ ] `shared` exFAT partition mounts read-write on both OSes
- [ ] LUKS unlock at boot; emergency: note the recovery path
- [ ] macOS partition still boots and can run firmware updates

## 3. Aftercare

- [ ] Firmware updates: boot macOS monthly, run Software Update, then
      the Asahi "Rebuild vendor firmware package" step (DR-5)
- [ ] `docs/logs/g6-<date>.md` with results; update the status matrix
