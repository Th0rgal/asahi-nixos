# `omarchnix` — Vision & Architecture

**`omarchnix`** combines three properties that rarely coexist in one Linux workstation operating system:

1. **Omarchy's instant aesthetic, QML shell, and keyboard-centric ergonomics** (`omacom/omarchy` themes, `quickshell` + `omarchy-shell` QML runtime, and `plugins.omarchy.org` ecosystem).
2. **Pure, rollback-safe NixOS + Home Manager declarativity and defense-in-depth hardening** across both **`aarch64-linux`** (Apple Silicon M-series via Asahi Linux, NVIDIA Grace / DGX Spark) and **`x86_64-linux`** workstations and cloud/QEMU VMs.
3. **Proof-carrying Lean 4 userspace** powered by `Th0rgal/turbo-lean`, `Th0rgal/lean-sys`, and `LeanNative` — where security-critical binaries carry `0 sorryAx` kernel axiom proofs, verified ARMv8.2+/NEON LLVM codegen, and offline-verifiable BLAKE3 + Ed25519 receipts inside `/nix/store`.

---

## 1. Cross-Architecture Hardware Targets

`omarchnix` exports reusable modules (`nixosModules.omarchnix`, `homeManagerModules.omarchnix`) and reference host configurations across architectures without duplicating desktop, security, or Lean verification logic:

| Profile / Host | Architecture | Target Class | Boot & Hardware Model |
| --- | --- | --- | --- |
| `m2air` | `aarch64-linux` | Apple Silicon MacBook Air M2 (`J413`/`J415`) | Manual `m1n1` + U-Boot + vendorfw (DR-5), LUKS2 `cryptroot` + shared exFAT (DR-4), PipeWire `asahi-audio` DSP + `speakersafetyd`, 1.6x HiDPI + notch geometry |
| `spark` | `aarch64-linux` | NVIDIA Grace / DGX Spark ARM64 server & workstation | UEFI `systemd-boot`, ARMv9/NEON/SVE2 `LeanNative` codegen, hardened headless or desktop profile |
| `workstation` | `x86_64-linux` | AMD / Intel Linux desktop & cloud workstation | UEFI `systemd-boot`, KVM + `nixos-container` sandboxing, full Hyprland + `omarchy-shell` desktop |
| `rehearsal` / `vm` | `aarch64-linux` | Scaleway Mac mini M2 & QEMU guests | Disposable BootROM dress rehearsal (DR-3) and CI/QEMU iteration |

---

## 2. The Omarchy Compatibility Contract (DR-8)

Instead of forking Omarchy's themes or rewriting its QML shell, `omarchnix` treats upstream `omacom/omarchy` as a declarative data and QML source:

- **`lib.omarchy.importTheme` & Live Switching:** Imports all 23+ bundled Omarchy `colors.toml` palettes (`tokyo-night`, `catppuccin`, `catppuccin-latte`, `ethereal`, `everforest`, `flexoki-light`, `gruvbox`, `hackerman`, `jade-horse`, `kanagawa`, `last-horizon`, `lumon`, `lupine`, `matte-black`, `miasma`, `nord`, `retro-82`, `ristretto`, `rose-pine`, `solitude`, `starship`, `vantablack`, `white`) or any custom `colors.toml` directory into a canonical Nix theme attrset, while staging `~/.local/state/omarchy/current/theme` so `omarchnix-theme-set <theme>` switches themes live at runtime in milliseconds.
- **`quickshell` + `omarchy-shell` QML Runtime:** Runs stock `quickshell` (`Qt 6.12`) over Nix-packaged `omarchy-shell` (`qs.Commons`, `qs.Ui`, and 26+ first-party QML plugins) with NixOS FHS path shims (`python3`, `fontconfig`, `socat` ~5 ms Unix-socket IPC, and `/usr/share/omarchy-platform/display-cutouts.json`).
- **Declarative + Runtime `plugins.omarchy.org` Loader:** Supports both Nix-locked plugins (`programs.omarchnix.plugins.locked`, enforcing `schemaVersion == 1`, non-`omarchy.*` IDs, relative entrypoints, and symlink-free trees inside Nix derivations) and user-installed plugins validated by `omarchnix-plugin`.
- **Agent-First Ergonomics:** Ships pre-wired configuration and a shared `omarchnix` system skill for `opencode`, `claude`, `codex`, and `hermes`, instructing agents to validate module edits via `omarchnix check` (`nix fmt`, flake evaluation, and KVM VM checks) before running `nixos-rebuild`.

---

## 3. Proof-Carrying Nix + `turbo-lean` Pipeline (DR-9)

Nix guarantees *reproducible derivation provenance* (inputs -> build script -> store hash), while Lean 4 guarantees *mathematical specification adherence*. `omarchnix` fuses both into **Proof-Carrying Store Paths**:

```text
Lean 4 Source (lean-sys / TurboLean, 0 sorryAx)
        │
        ├─► Kernel Axiom Gate (collectAxioms ⊆ {propext, Quot.sound, Classical.choice})
        │
        ├─► LeanNative Backend (aarch64 NEON pmull64/eor3u + LSE atomics / x86_64)
        │         └──► ELF64 Binary (/nix/store/.../bin/<exe>)
        │
        └─► Signed Receipt (/nix/store/.../share/omarchnix/receipts/<exe>.receipt.json)
                  ├── interface_hash & receipt_blake3 (turbo-lean Schema v2)
                  ├── binary_blake3 & target_isa ("aarch64-neon" | "x86_64-sse42")
                  └── ed25519-v1 signature verified offline by `omarchnix audit`
```

Running `omarchnix audit` on any booted `omarchnix` machine traverses `nix-store -qR /run/current-system`, discovers every proof-carrying package in the closure, checks `0 sorryAx` and kernel-axiom invariants, recomputes the ELF binary's BLAKE3 hash, and verifies its Ed25519 signature offline in `< 10 ms`.
