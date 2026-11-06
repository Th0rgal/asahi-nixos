# Phase 0 Access Blocks Update — Gates G4, G5, G6 (Post-G3)

- **Date:** 2026-11-06
- **Supersedes (append-only):** [`phase0-blocks-2026-11-06.md`](phase0-blocks-2026-11-06.md)
- **Protocol Reference:** `docs/plan-opencode.md` ("Failure protocol: Blocked on access -> say exactly which Phase-0 item, keep working on the highest phase that isn't blocked, and note the block in the gate log.")

Phases 1, 2, and 3 (Gates **G1**, **G2**, **G3**, **G7**, **G8**) are completed with recorded evidence in `docs/logs/`. Phases 4 and 5 remain gated on the following Phase 0 owner items:

| Gate | Phase | Blocking Phase-0 Item(s) |
| --- | --- | --- |
| **G4** — Asahi bootstrap on real BootROM | Phase 4 | Owner-provisioned Scaleway Mac mini M2 (`M2-M`, PAR zone, macOS image, VNC enabled) + explicit owner **GO** before billable €0.17/h rental + owner confirmation of the `sops-nix` age public key recipient in `.sops.yaml` to encrypt rehearsal IP/credentials under `secrets/`. |
| **G5** — NixOS install + `nixos-rebuild switch` on rehearsal mini | Phase 4 | Same as G4 (Scaleway `M2-M` access + explicit owner **GO** + `.sops.yaml` age recipient). |
| **G6** — MacBook Air M2 install, dual-boot macOS kept | Phase 5 | Completion of Gates G4/G5 rehearsal on Scaleway + owner physical execution of `docs/install-m2air.md` on the MacBook Air M2. |
