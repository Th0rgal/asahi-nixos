{
  pkgs,
  lib,
  inputs,
  self,
}:
let
  omarchnixCli = pkgs.omarchnix.cli;
  receiptGate = pkgs.omarchnix.receipt-gate;
  turboLean = pkgs.omarchnix.turbo-lean;
  leanSys = pkgs.omarchnix.lean-sys;

  # Build a second proof-carrying derivation with a distinct deterministic test label so we can
  # verify key-rotation / signer-authority mismatch rejection cleanly without literal hex keys.
  alternateSeedReceiptGate = import ../pkgs/omarchnix-receipt-gate {
    buildVerifiedLeanSys =
      args:
      pkgs.omarchnix.buildVerifiedLeanSys (
        args
        // {
          pname = "omarchnix-receipt-gate-alt";
          receiptSigningSeedHex = builtins.hashString "sha256" "omarchnix-ci-alt-signer-rotation-test-v1";
        }
      );
  };

  verifiedNixosEval =
    nixpkgsEval:
    nixpkgsEval {
      inherit (pkgs.stdenv.hostPlatform) system;
      specialArgs = { inherit inputs; };
      modules = [
        { nixpkgs.overlays = [ self.overlays.omarchnix ]; }
        self.nixosModules.omarchnix
        {
          networking.hostName = "verified-lean-eval";
          omarchnix = {
            enable = true;
            profile = if pkgs.stdenv.hostPlatform.isAarch64 then "spark" else "workstation";
            verifiedUserspace.enable = true;
          };
          fileSystems."/" = {
            device = "/dev/vda1";
            fsType = "ext4";
          };
          fileSystems."/boot" = {
            device = "/dev/vda2";
            fsType = "vfat";
          };
        }
      ];
    };

  evaluatedSystem = (verifiedNixosEval inputs.nixpkgs.lib.nixosSystem).config;
in
assert evaluatedSystem.omarchnix.verifiedUserspace.enable == true;
assert builtins.elem "/share/omarchnix" evaluatedSystem.environment.pathsToLink;
assert builtins.any (
  p: (p.pname or "") == "omarchnix-receipt-gate"
) evaluatedSystem.environment.systemPackages;
pkgs.runCommand "omarchnix-verified-lean-check"
  {
    nativeBuildInputs = [
      pkgs.b3sum
      pkgs.binutils
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
      omarchnixCli
      receiptGate
      turboLean
    ];
  }
  ''
    set -euo pipefail

    export HOME="$TMPDIR/home"
    export TURBO_LEAN_STATE_DIR="$TMPDIR/turbo-lean-state"
    mkdir -p "$HOME" "$TURBO_LEAN_STATE_DIR"

    echo "[1/9] Verify lean-sys C shim + Lean 4 archive artifacts"
    test -f "${leanSys.pkgDir}/.lake/build/lib/liblean_sys_shim.a"
    test -d "${leanSys.leanLibDir}/LeanSys"

    echo "[2/9] Verify LeanNative ELF64 static archive, IR, symbols, and self-test"
    receipt_file="${receiptGate.receiptPath}"
    bin_file="${receiptGate}/bin/omarchnix-receipt-gate"
    archive_file="${receiptGate}/lib/omarchnix/omarchnix-receipt-gate/liblean_native_kernels.a"
    ir_file="${receiptGate}/lib/omarchnix/omarchnix-receipt-gate/liblean_native_kernels.ll"

    test -x "$bin_file"
    test -f "$receipt_file"
    test -f "$archive_file"
    test -f "$ir_file"

    nm --defined-only "$bin_file" > "$TMPDIR/gate_nm.txt"
    grep -Eq '[[:space:]][Tt][[:space:]]+l_OmarchnixGate_Kernel_admitReceiptKernel$' "$TMPDIR/gate_nm.txt"
    grep -Eq '[[:space:]][Tt][[:space:]]+lean_native_abi_l_OmarchnixGate_Kernel_admitReceiptKernel$' "$TMPDIR/gate_nm.txt"
    grep -Eq '[[:space:]][Tt][[:space:]]+l_OmarchnixGate_Kernel_mixReceiptWord$' "$TMPDIR/gate_nm.txt"
    grep -Eq '[[:space:]][Tt][[:space:]]+lean_native_abi_l_OmarchnixGate_Kernel_mixReceiptWord$' "$TMPDIR/gate_nm.txt"

    ${lib.optionalString pkgs.stdenv.hostPlatform.isAarch64 ''
      grep -q '@llvm.aarch64.neon.pmull64' "$ir_file"
      ! grep -q '@llvm.aarch64.crypto.eor3u' "$ir_file"
    ''}
    ${lib.optionalString pkgs.stdenv.hostPlatform.isx86_64 ''
      grep -q 'x86_64-unknown-linux-gnu' "$ir_file"
      ! objdump -d "$archive_file" | grep -Eq '%ymm|%zmm|[[:space:]]v[a-z]'
    ''}

    "$bin_file" self-test | grep -q 'self-test ok'

    echo "[3/9] Verify Schema v2 receipt invariants and positive omarchnix audit"
    jq -e '
      .schema_version == 2
      and .mode == "trusted"
      and .forbidden_constructs_found == 0
      and .zero_sorry == true
      and .zero_native_decide == true
      and .sorry_ax_count == 0
      and .codegen_backend == "LeanNative"
      and .signature_alg == "ed25519-v1"
      and (.ed25519_pubkey | length == 64)
      and (.ed25519_signature | length == 128)
      and (.axiom_audit | length == 5)
      and (.axiom_audit | all(.[]; .certified_clean == true and .has_sorry_ax == false and (.disallowed_axioms | length == 0)))
    ' "$receipt_file" >/dev/null

    omarchnix audit --path "${receiptGate}" --json > "$TMPDIR/pos_audit.json"
    jq -e '
      .ok == true
      and .verified_count == 1
      and .total_count == 1
      and .receipts[0].ok == true
      and .receipts[0].gate.admitted == true
      and .receipts[0].gate.schema_v2 == true
      and .receipts[0].gate.zero_sorry_ax == true
      and .receipts[0].gate.zero_forbidden == true
      and .receipts[0].gate.sig_verified == true
      and .receipts[0].gate.binary_blake3_matches == true
    ' "$TMPDIR/pos_audit.json" >/dev/null

    expected_pub="$(jq -r '.ed25519_pubkey' "$receipt_file")"
    omarchnix audit --path "${receiptGate}" --pubkey "$expected_pub" --json > "$TMPDIR/pos_pubkey.json"
    jq -e '.ok == true and .verified_count == 1' "$TMPDIR/pos_pubkey.json" >/dev/null

    alt_pub="$(jq -r '.ed25519_pubkey' "${alternateSeedReceiptGate.receiptPath}")"
    test "$alt_pub" != "$expected_pub"
    omarchnix audit --path "${alternateSeedReceiptGate}" --pubkey "$alt_pub" --json > "$TMPDIR/alt_pos.json"
    jq -e '.ok == true and .verified_count == 1' "$TMPDIR/alt_pos.json" >/dev/null

    # Stage a mutable package root layout (`bin/` + `share/omarchnix/receipts/`) for negative tampering tests.
    stage_pkg() {
      local dst="$1"
      rm -rf "$dst"
      mkdir -p "$dst/bin" "$dst/share/omarchnix/receipts"
      cp -f "$bin_file" "$dst/bin/omarchnix-receipt-gate"
      chmod 755 "$dst/bin/omarchnix-receipt-gate"
      cp -f "$receipt_file" "$dst/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json"
      chmod 644 "$dst/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json"
    }

    stage_pkg "$TMPDIR/staged-clean"
    omarchnix audit --path "$TMPDIR/staged-clean" --json > "$TMPDIR/staged_clean.json"
    jq -e '.ok == true and .verified_count == 1' "$TMPDIR/staged_clean.json" >/dev/null

    echo "[4/9] Reject tampered binary bytes (BLAKE3 mismatch)"
    stage_pkg "$TMPDIR/tamper-bin"
    printf '\x00' >> "$TMPDIR/tamper-bin/bin/omarchnix-receipt-gate"
    if omarchnix audit --path "$TMPDIR/tamper-bin" --json > "$TMPDIR/tamper_bin.json"; then
      echo "ERROR: tampered binary unexpectedly passed omarchnix audit" >&2
      exit 1
    fi
    jq -e '.ok == false and .verified_count == 0 and .receipts[0].gate.binary_blake3_matches == false and .receipts[0].gate.admitted == false' \
      "$TMPDIR/tamper_bin.json" >/dev/null

    echo "[5/9] Reject co-tampered binary + top-level .binary_blake3 (signed per_file_interfaces binding)"
    stage_pkg "$TMPDIR/cotamper-bin"
    printf '\x42' >> "$TMPDIR/cotamper-bin/bin/omarchnix-receipt-gate"
    forged_blake3="$(b3sum --no-names "$TMPDIR/cotamper-bin/bin/omarchnix-receipt-gate")"
    jq --arg b "$forged_blake3" '.binary_blake3 = $b' \
      "$TMPDIR/cotamper-bin/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json" \
      > "$TMPDIR/cotamper-bin/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json.tmp"
    mv "$TMPDIR/cotamper-bin/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json.tmp" \
      "$TMPDIR/cotamper-bin/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json"
    if omarchnix audit --path "$TMPDIR/cotamper-bin" --json > "$TMPDIR/cotamper_bin.json"; then
      echo "ERROR: co-tampered binary + .binary_blake3 unexpectedly passed omarchnix audit" >&2
      exit 1
    fi
    jq -e '.ok == false and .verified_count == 0 and .receipts[0].gate.sig_verified == false and .receipts[0].gate.binary_blake3_matches == false and .receipts[0].gate.admitted == false' \
      "$TMPDIR/cotamper_bin.json" >/dev/null

    echo "[6/9] Reject tampered signed receipt fields and Ed25519 signature"
    stage_pkg "$TMPDIR/tamper-sig"
    jq '.ed25519_signature = ("00" + .ed25519_signature[2:])' \
      "$TMPDIR/tamper-sig/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json" \
      > "$TMPDIR/tamper-sig/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json.tmp"
    mv "$TMPDIR/tamper-sig/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json.tmp" \
      "$TMPDIR/tamper-sig/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json"
    if omarchnix audit --path "$TMPDIR/tamper-sig" --json > "$TMPDIR/tamper_sig.json"; then
      echo "ERROR: corrupted signature unexpectedly passed omarchnix audit" >&2
      exit 1
    fi
    jq -e '.ok == false and .verified_count == 0 and .receipts[0].gate.sig_verified == false' \
      "$TMPDIR/tamper_sig.json" >/dev/null

    stage_pkg "$TMPDIR/tamper-iface"
    jq '.interface_hash = ("ff" + .interface_hash[2:])' \
      "$TMPDIR/tamper-iface/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json" \
      > "$TMPDIR/tamper-iface/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json.tmp"
    mv "$TMPDIR/tamper-iface/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json.tmp" \
      "$TMPDIR/tamper-iface/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json"
    if omarchnix audit --path "$TMPDIR/tamper-iface" --json > "$TMPDIR/tamper_iface.json"; then
      echo "ERROR: tampered interface_hash unexpectedly passed omarchnix audit" >&2
      exit 1
    fi
    jq -e '.ok == false and .verified_count == 0 and .receipts[0].gate.sig_verified == false' \
      "$TMPDIR/tamper_iface.json" >/dev/null

    echo "[7/9] Reject wrong --pubkey (operator authority mismatch)"
    if omarchnix audit --path "${receiptGate}" --pubkey "$alt_pub" --json > "$TMPDIR/wrong_pub.json"; then
      echo "ERROR: mismatched --pubkey unexpectedly passed omarchnix audit" >&2
      exit 1
    fi
    jq -e '.ok == false and .verified_count == 0 and .receipts[0].gate.sig_verified == false' \
      "$TMPDIR/wrong_pub.json" >/dev/null

    echo "[8/9] Reject missing binary and symlinked-receipt binary swap in staged root"
    stage_pkg "$TMPDIR/missing-bin"
    rm -f "$TMPDIR/missing-bin/bin/omarchnix-receipt-gate"
    if omarchnix audit --path "$TMPDIR/missing-bin" --json > "$TMPDIR/missing_bin.json"; then
      echo "ERROR: staged receipt with deleted binary unexpectedly passed omarchnix audit" >&2
      exit 1
    fi
    jq -e '.ok == false and .verified_count == 0 and .receipts[0].actual_binary_blake3 == "missing" and .receipts[0].gate.admitted == false' \
      "$TMPDIR/missing_bin.json" >/dev/null

    mkdir -p "$TMPDIR/symlink-swap/sw/bin" "$TMPDIR/symlink-swap/sw/share/omarchnix/receipts"
    cp -f "$bin_file" "$TMPDIR/symlink-swap/sw/bin/omarchnix-receipt-gate"
    chmod 755 "$TMPDIR/symlink-swap/sw/bin/omarchnix-receipt-gate"
    printf '\x7f' >> "$TMPDIR/symlink-swap/sw/bin/omarchnix-receipt-gate"
    ln -s "$receipt_file" "$TMPDIR/symlink-swap/sw/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json"
    if omarchnix audit --path "$TMPDIR/symlink-swap" --json > "$TMPDIR/symlink_swap.json"; then
      echo "ERROR: symlinked store receipt with tampered sw/bin binary unexpectedly passed omarchnix audit" >&2
      exit 1
    fi
    jq -e '.ok == false and .verified_count == 0 and .receipts[0].gate.binary_blake3_matches == false and .receipts[0].gate.admitted == false' \
      "$TMPDIR/symlink_swap.json" >/dev/null

    echo "[9/9] Reject empty directory by default; succeed only with --allow-empty"
    mkdir -p "$TMPDIR/empty-root"
    if omarchnix audit --path "$TMPDIR/empty-root" --json > "$TMPDIR/empty_strict.json"; then
      echo "ERROR: empty directory without --allow-empty unexpectedly passed" >&2
      exit 1
    fi
    jq -e '.ok == false and .verified_count == 0' "$TMPDIR/empty_strict.json" >/dev/null

    omarchnix audit --path "$TMPDIR/empty-root" --allow-empty --json > "$TMPDIR/empty_allowed.json"
    jq -e '.ok == true and .verified_count == 0' "$TMPDIR/empty_allowed.json" >/dev/null

    cp "$TMPDIR/pos_audit.json" "$out"
  ''
