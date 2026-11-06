# DR — decision records

Numbered, append-only. A decision is never edited after being recorded;
supersede it with a new record.

## DR-1 — NixOS over Omarchy as the end state

Date: 2026-11-05. Status: accepted.

Omarchy 4.5 ships the best out-of-the-box Apple Silicon experience
(Touch ID via Secure Enclave, external displays), but it is Arch-based
and imperative. The target machine is a daily driver; declarative,
rollback-able configuration wins over Touch ID. Omarchy remains the
fallback: its Mac installer is the known-good path if NixOS bring-up
stalls.

## DR-2 — Touch ID deferred, not blocked

Date: 2026-11-05. Status: deferred.

Touch ID on M-series requires the Omarchy kernel fork's Secure Enclave
work, not upstreamed to Asahi. Path if wanted later: package their
kernel tag as a `linux_asahi_omarchy` override on the
`nixos-apple-silicon` kernel plus the userspace helper. Requires
reverse-engineering the userspace contract; pinned to their exact
release tag.

## DR-3 — Rehearse on rented hardware before the Air

Date: 2026-11-05. Status: accepted.

Scaleway Mac mini M2 (€0.17/h, M2 chip — same chip class as the Air)
validates the parts qemu cannot: m1n1 on real BootROM, firmware
extraction from APFS, UEFI standalone install. Provider confirmed
personal-use Linux installs are acceptable; provider-side reset is the
failure recovery. The rehearsal box tests no laptop hardware (no Touch
ID, no speakers, no panel) — those gates only exist on the Air.

## DR-4 — Partition layout for the Air (1 TB)

Date: 2026-11-05. Status: accepted.

- macOS ~120 GB (kept for firmware updates and recovery; not optional)
- shared exFAT ~150 GB (transfer shelf; the only FS both OSes mount
  read-write natively; no journaling, no encryption — nothing precious
  lives here)
- rest: NixOS, LUKS2 + ext4 (software-only encryption; Apple's
  hardware-sealed FileVault keys are unavailable under Asahi)

## DR-6 — Secrets via sops-nix, age root key held by the owner

Date: 2026-11-05. Status: accepted.

Repo contains zero plaintext secrets. sops-nix with an age keypair:
public key committed, private key only on the owner's machines and the
standing builder VM. Rehearsal-box IP and any credentials live in
`secrets/` (encrypted), never in git.

## DR-7 — Container isolation, not VMs (no KVM on Asahi)

Date: 2026-11-05. Status: accepted.

Qubes-style hardware isolation is unavailable: m1n1 owns the
hypervisor and KVM guests are not usable on Apple Silicon today.
Isolation model: declarative `nixos-container`s (systemd-nspawn)
with no-network-by-default and uid-shifted bind mounts, plus bwrap
sandboxing for untrusted `nix develop`. Revisit if KVM lands upstream.

## DR-5 — Boot chain updates stay manual

Date: 2026-11-05. Status: accepted.

`boot.loader.*` stays off in NixOS on Asahi machines. m1n1/U-Boot and
vendor firmware updates go through the documented Asahi installer steps
(`docs/runbook-scaleway.md`), not `nixos-rebuild`, to avoid a
half-updated boot chain that the OS cannot repair itself.

## DR-8 — Omarchy compatibility contract on pure NixOS

Date: 2026-11-06. Status: accepted. Supersedes DR-1's framing of Omarchy solely as an imperative Arch fallback.

`omarchnix` rebrands `asahi-nixos` into a reusable cross-architecture (`aarch64-linux` for Apple Silicon M-series + NVIDIA Grace/DGX Spark, and `x86_64-linux` for workstations/VMs) NixOS + Home Manager distribution layer (`nixosModules.omarchnix`, `homeManagerModules.omarchnix`) with first-class compatibility for the upstream Omarchy (`omacom/omarchy`) ecosystem:

1. **Theme contract (`lib.omarchy.importTheme`):** Parses upstream Omarchy `colors.toml` (and optional `shell.*.toml` overrides) across all 23+ first-party and community themes into a typed Nix palette + `shell.toml` surface token set, driving Hyprland 0.57 Lua, `omarchy-shell` / Waybar, Foot, Fuzzel, Hyprlock, and SVG/PNG wallpapers, plus atomic runtime theme switching (`omarchnix-theme-set` / `omarchy-theme-set`) via `~/.local/state/omarchy/current/theme` and `omarchy-shell` Unix-socket IPC.
2. **Shell & plugin contract (`quickshell` + `omarchy-shell` + `plugins.omarchy.org`):** Packages `quickshell` (Qt 6.12) and the upstream `omarchy-shell` QML tree (`qs.Commons`, `qs.Ui`, first-party plugins, and NixOS FHS shims) alongside a dual-mode `plugins.omarchy.org` loader supporting both Nix-locked declarative plugins (`programs.omarchnix.plugins.locked`, validated at build time for `manifest.json` `schemaVersion == 1`, non-`omarchy.*` reverse-DNS ID, relative entrypoints, and zero symlinks) and user-space runtime plugin management (`omarchnix-plugin`).
3. **Agent-first ergonomics:** Pre-wires coding agents (`opencode`, `claude`, `codex`, `hermes`) with a governed `omarchnix` system skill and `omarchnix check` CLI that runs `nix fmt`, host evaluations, and NixOS VM tests before permitting `nixos-rebuild switch`.

## DR-9 — Proof-carrying Lean 4 userspace (`turbo-lean` + `lean-sys` + `LeanNative`)

Date: 2026-11-06. Status: accepted.

Critical userspace components and system gates in `omarchnix` carry machine-checked proofs and cryptographic build receipts rather than relying on unverified C/shell utilities:

1. **Zero-`sorryAx` + kernel axiom hygiene:** `pkgs.omarchnix.buildVerifiedLeanSys` builds Lean 4 (`v4.35.0`) targets from pinned `Th0rgal/lean-sys` and `Th0rgal/turbo-lean` inputs while enforcing `0` `sorry`/`admit` tokens in source and `Lean.collectAxioms` restricted strictly to `{propext, Quot.sound, Classical.choice}` (`0 sorryAx`, `0 Lean.trustCompiler`, `0 Lean.ofReduceBool`).
2. **Architecture-verified `LeanNative` codegen:** On `aarch64-linux` (Apple M-series / Grace), `LeanNative` (`arm64` / `appleA15`) emits LLVM 18 IR with verified ARMv8.2+/NEON SIMD (`@llvm.aarch64.neon.pmull64`, `@llvm.aarch64.crypto.eor3u.v2i64`, LSE atomics, and SVE2 multi-versioned loops) and verifies ELF64 `EM_AARCH64` / `EM_X86_64` object invariants (`verifyObjectBytesForTarget`).
3. **Signed BLAKE3 + Ed25519 store receipts & live closure audit:** Every derivation built by `pkgs.omarchnix.buildVerifiedLeanSys` writes `<out>/share/omarchnix/receipts/<name>.receipt.json` (binding `turbo-lean` Schema v2 `receipt_blake3`, `interface_hash`, `lean_toolchain`, target binary BLAKE3 digest, `sorry_ax_count = 0`, `codegen_backend = "LeanNative"`, and target ISA features) signed with `ed25519-v1` (`turbo-lean verify-receipt --require-signature`). `omarchnix audit` walks the active NixOS system closure (`/run/current-system` or an explicit store path), recomputes every binary's BLAKE3 digest, and cryptographically verifies every Ed25519 receipt offline in milliseconds.
