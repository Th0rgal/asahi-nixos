# Milestone 4 — Verified `lean-sys` + `turbo-lean` + `LeanNative` Store Receipts (`2026-11-06`)

## Summary

- **Flake inputs pinned:**
  - `lean-sys`: `github:Th0rgal/lean-sys/bbe3183d3fd57ee662405f0c63fde890fb878324`
  - `turbo-lean`: `github:Th0rgal/turbo-lean/7a8cb0c56865532397cc796327c7fa5e256f8f8e`
- **Packages & builders added (`overlays.omarchnix` & `packages.<system>`):**
  - `lean-sys` (`pkgs/lean-sys.nix`): builds `LeanSys` + `liblean_sys_shim.a` + `lean-sys-core` against binary-cached Nixpkgs `lean4` (`v4.35.0`) and runs C-ABI + benchmark self-checks.
  - `turbo-lean` (`pkgs/turbo-lean.nix`): builds `turbo-lean` + `lean-native` + `TurboLean.Inspector` / `LeanNative` `.olean` libraries with Nixpkgs `lean4` compatibility (`DR-11`).
  - `pkgs.omarchnix.buildVerifiedLeanSys` (`pkgs/build-verified-lean-sys.nix`): reusable verified Lean 4 + `lean-sys` + `LeanNative` derivation builder enforcing `TurboLean.Inspector` (`0 sorryAx`, `0 Lean.trustCompiler`, `0 Lean.ofReduceBool`), `turbo-lean audit-spec` non-vacuity/tightness, ELF64 `LeanNative` static archive linking (`pmull` NEON SIMD on `aarch64-linux`, `x86-64-v2` SSE2/PCLMULQDQ with zero AVX/VEX instructions on `x86_64-linux`), `patchelf --shrink-rpath` + `dontStrip`/`dontPatchELF`, signed `BuildArtifacts/BinaryBlake3_<hex>.lean` interface binding, and `postFixup` binary BLAKE3 drift verification.
  - `omarchnix-receipt-gate` (`pkgs/omarchnix-receipt-gate/`): proof-carrying Schema v2 store receipt admission utility (`OmarchnixGate.{SimdRef,Kernel,Spec,Main}`) linked against `lean-sys` (`JsonTape`, `xxh64Slice`) and `liblean_native_kernels.a`.
  - `omarchnix audit` (`pkgs/omarchnix-cli.nix`): offline system/store closure receipt auditor invoking `turbo-lean verify-receipt --require-signature`, checking signed `per_file_interfaces` binary-hash binding, and running `omarchnix-receipt-gate check-receipt`.
- **NixOS & test integration:**
  - `omarchnix.verifiedUserspace.enable` (default `true`) installs `omarchnix-receipt-gate` and links `/share/omarchnix` under `/run/current-system/sw/share/omarchnix/receipts`.
  - `checks.<system>.verified-lean` (`tests/verified-lean.nix`) verifies positive receipt admission plus 7 negative/tampering failure modes (corrupted binary bytes, co-tampered binary + `.binary_blake3`, corrupted `ed25519_signature`, tampered `interface_hash`, wrong `--pubkey`, deleted staged binary, and symlinked store receipt paired with tampered `sw/bin` binary).

## Local Build & Verification Evidence (`x86_64-linux`)

- Note: local host lacks unprivileged user namespaces (`sandbox-fallback` active); full Linux Nix sandbox execution on both `x86_64-linux` and `aarch64-linux` (`ubuntu-24.04-arm`) is verified in GitHub Actions CI (`build.yml`).
- Built store paths:
  - `lean-sys`: `/nix/store/bncy48m1yjs5pvyifd6byrkdq4djsnvl-lean-sys-0.1.0-bbe3183`
  - `turbo-lean`: `/nix/store/sq95p7zqhhvakz9gcwrla6ph7zq6jvfp-turbo-lean-0.1.0-7a8cb0c`
  - `omarchnix-receipt-gate`: `/nix/store/mg6dazf8h5phppk95qf94r7765kprn36-omarchnix-receipt-gate-0.1.0`
- Positive & negative tampering check (`nix build .#checks.x86_64-linux.verified-lean -L`):
  - `[1/9]` `lean-sys` C shim + Lean 4 archive artifacts: passed
  - `[2/9]` `LeanNative` ELF64 static archive, IR, anchor symbols, zero AVX/VEX disassembly check, and `self-test`: passed
  - `[3/9]` Schema v2 receipt invariants (`0 sorryAx`, `5/5` certified-clean declarations) and positive `omarchnix audit`: passed (`binary_blake3 = bdac2a39e09184a05780b9c9aa9e8bf25212860a859b901237ca9701df198a5d`, `receipt_blake3 = 291ed8f5765bf4a1976d430a2bbba068e364070effb977ececfb4c516fcf5a22`)
  - `[4/9]` Tampered binary bytes rejected (`binary_blake3_matches == false`)
  - `[5/9]` Co-tampered binary + `.binary_blake3` rejected (`sig_verified == false`, `binary_blake3_matches == false`)
  - `[6/9]` Tampered `ed25519_signature` and `interface_hash` rejected (`sig_verified == false`)
  - `[7/9]` Mismatched `--pubkey` rejected (`sig_verified == false`)
  - `[8/9]` Deleted staged binary (`actual_binary_blake3 == "missing"`) and symlinked store receipt paired with tampered `sw/bin` binary rejected (`binary_blake3_matches == false`)
  - `[9/9]` Empty directory rejected by default; accepted with `--allow-empty`

## Scope & Trust Boundary Caveats (`DR-11`)

- Default deterministic signing seeds in Nix builds are public build inputs that detect corruption relative to a trusted build artifact, not operator authentication; operator authority requires external key isolation and auditing with an independently trusted `--pubkey`.
- The Lean admission theorem (`OmarchnixGate.Spec.admitReceipt_iff` / `admitReceipt_eq_kernel`) proves the Boolean receipt admission policy and equivalence to the `LeanNative`-compiled kernel, not the JSON parser, compiler, cryptographic primitives, or whole operating system.
