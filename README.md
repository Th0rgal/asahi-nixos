# `omarchnix`

Proof-carrying, declarative Omarchy-compatible NixOS & Home Manager workstation stack across **`aarch64-linux`** (Apple Silicon M-series via Asahi Linux, NVIDIA Grace / DGX Spark) and **`x86_64-linux`** workstations and VMs.

See [`docs/VISION.md`](docs/VISION.md) for the full architecture and [`docs/decisions.md`](docs/decisions.md) (`DR-1`..`DR-9`) for recorded design decisions.

---

## Reusable Flake Outputs

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    omarchnix.url = "github:Th0rgal/omarchnix";
  };

  outputs = { nixpkgs, home-manager, omarchnix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux"; # or "aarch64-linux"
      modules = [
        omarchnix.nixosModules.omarchnix
        home-manager.nixosModules.home-manager
        {
          omarchnix = {
            enable = true;
            profile = "workstation"; # "asahi" | "spark" | "workstation" | "vm"
            desktop = {
              enable = true;
              user = "thomas";
            };
          };
        }
      ];
    };
  };
}
```

### Reference `nixosConfigurations`

| Host | Architecture | Target | Purpose |
| --- | --- | --- | --- |
| `m2air` | `aarch64-linux` | MacBook Air M2 (Asahi) | Primary Apple Silicon daily driver (LUKS2, `asahi-audio` DSP, 1.6x HiDPI, dual-boot macOS). |
| `spark` | `aarch64-linux` | NVIDIA Grace / DGX Spark | ARM64 UEFI server & workstation (`systemd-boot`, hardened + Hyprland desktop). |
| `workstation` | `x86_64-linux` | AMD / Intel desktop & cloud | Generic `x86_64-linux` UEFI workstation (`systemd-boot`, hardened + Hyprland desktop). |
| `rehearsal` | `aarch64-linux` | Scaleway Mac mini M2 (`M2-M`) | Disposable BootROM dress rehearsal target (`docs/runbook-scaleway.md`). |
| `vm` | `aarch64-linux` | Plain QEMU guest | Software iteration target without Apple hardware dependencies. |

Build the Asahi/NixOS installer ISO:

```console
$ nix build .#installer-bootstrap
```

---

## Status Matrix

Every cell is backed by a recorded gate (CI run or runbook log in `docs/logs/`). No cell is marked done without evidence.

| Gate | What proves it | Status |
| --- | --- | --- |
| G1 — flake evaluates | `nix eval` across all hosts + standalone module checks in CI | passed ([`g1-2026-11-06.md`](docs/logs/g1-2026-11-06.md)) |
| G2 — installer ISO builds | `nix build .#installer-bootstrap` in CI, artifact attached | passed ([`g2-2026-11-06.md`](docs/logs/g2-2026-11-06.md)) |
| G3 — VM boots shared config | QEMU boot log in `docs/logs/` | passed ([`g3-2026-11-06.md`](docs/logs/g3-2026-11-06.md)) |
| G4 — Asahi bootstrap on real BootROM | runbook log from the rehearsal box | Phase 0 unblocked; Scaleway `fr-par-1` `M2-M` HTTP 503 `out_of_stock` ([`g4-g5-2026-11-06.md`](docs/logs/g4-g5-2026-11-06.md)) |
| G5 — NixOS install + rebuild on rehearsal | `nixos-rebuild switch` log on the mini | Phase 0 unblocked; Scaleway `fr-par-1` `M2-M` HTTP 503 `out_of_stock` ([`g4-g5-2026-11-06.md`](docs/logs/g4-g5-2026-11-06.md)) |
| G6 — Air install, dual-boot macOS kept | runbook log from the Air | hardware polish + printed runbook ready ([`install-m2air.md`](docs/install-m2air.md), [`g4-g5-2026-11-06.md`](docs/logs/g4-g5-2026-11-06.md)) |
| G7 — security & container invariants | `checks.x86_64-linux.{disko-declare,security}` in CI + secret sweep | passed ([`g7-2026-11-06.md`](docs/logs/g7-2026-11-06.md)) |
| G8 — Hyprland desktop via Home Manager | `m2air` eval + `checks.x86_64-linux.desktop` screenshot in CI + `boat.dev` toplevel build | passed ([`g8-2026-11-06.md`](docs/logs/g8-2026-11-06.md), [`g3-2026-11-06.md`](docs/logs/g3-2026-11-06.md)) |

---

## Method

- **Runbooks, not memory.** Every operation on real hardware is written down in `docs/` before it is run, and produces a log in `docs/logs/`.
- **Gates with evidence.** A gate without a recorded artifact is not passed.
- **Pinned inputs.** `flake.lock` is committed; upgrades are deliberate commits, not surprises.
- **Rehearse before you cut.** Nothing reaches physical BootROM without rehearsal or explicit runbook verification.
- **One writer, no rebase.** Straight commits on `main`, or short-lived feature PRs merged cleanly. No force-push, no history rewriting.

## What Is Out of Scope on Apple Silicon

- Touch ID (Omarchy kernel-fork work, not upstreamed to Asahi; tracked in `docs/decisions.md` as DR-2)
- Metal (does not exist on Linux; Mesa Honeykrisp Vulkan 1.4 / OpenGL 4.6 is what Asahi ships)
- Apple's verified boot / SIP inside Linux (replaced by the Asahi `m1n1` + U-Boot boot chain + LUKS2 `cryptroot` + `omarchnix` Ed25519 store receipts)

## References

- [nix-community/nixos-apple-silicon](https://github.com/nix-community/nixos-apple-silicon) — Apple Silicon hardware module and installer bootstrap
- [Asahi Linux](https://asahilinux.org/) — kernel, `m1n1`, `asahi-audio`, Mesa Honeykrisp
- [Omarchy](https://omarchy.org/) — theme, shell, and plugin ecosystem compatible with `omarchnix`
- [Th0rgal/turbo-lean](https://github.com/Th0rgal/turbo-lean) & [Th0rgal/lean-sys](https://github.com/Th0rgal/lean-sys) — proof-carrying Lean 4 userspace & `LeanNative` backend
