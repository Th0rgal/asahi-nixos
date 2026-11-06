# Phase 0 Access Blocks — Gates G3, G4, G5, G6

- **Date:** 2026-11-06
- **Protocol Reference:** `docs/plan-opencode.md` ("Failure protocol: Blocked on access -> say exactly which Phase-0 item, keep working on the highest phase that isn't blocked, and note the block in the gate log.")

Phases 1 and 2 (Gates G1, G2, G7, G8) are completed and green on `main`. Phases 3–5 remain gated on the following Phase 0 owner items:

| Gate | Phase | Blocking Phase-0 Item(s) |
| --- | --- | --- |
| **G3** — `aarch64` VM boots shared config + `m2air` native toplevel build | Phase 3 | Provisioned `boat.dev` `aarch64` VM (>= 8 GB RAM) or managed-VM budget grant (`BOAT_API_KEY` is core-reserved; current mission VM budget mode is `none`). |
| **G4** — Asahi bootstrap on real BootROM | Phase 4 | Owner-provisioned Scaleway Mac mini M2 (`M2-M`, PAR zone, VNC enabled) + explicit owner **GO** for billable rental + **age public key** (`sops-nix` secret root in `.sops.yaml` to encrypt rehearsal IP/credentials under `secrets/`) + rehearsal throwaway SSH keypair deployment. |
| **G5** — NixOS install + `nixos-rebuild switch` on rehearsal mini | Phase 4 | Same as G4 (Scaleway M2-M access + explicit owner GO + `.sops.yaml` age recipient). |
| **G6** — MacBook Air M2 install, dual-boot macOS kept | Phase 5 | Completion of Gates G3–G5 rehearsal + owner physical execution of `docs/install-m2air.md` on the MacBook Air M2. |
