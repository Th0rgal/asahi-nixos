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

  pinnedTestPubkey = builtins.hashString "sha256" "omarchnix-external-operator-test-pubkey-v1";

  mkEval =
    extraConfig:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit (pkgs.stdenv.hostPlatform) system;
      specialArgs = { inherit inputs; };
      modules = [
        { nixpkgs.overlays = [ self.overlays.omarchnix ]; }
        self.nixosModules.omarchnix
        {
          networking.hostName = "receipt-trust-eval";
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
        extraConfig
      ];
    }).config;

  defaultConfig = mkEval { };

  enforcedConfig = mkEval {
    security.omarchnix = {
      trustedReceiptKeys = [ pinnedTestPubkey ];
      requireExternalAttestations = true;
    };
  };

  enforcedNoServiceConfig = mkEval {
    security.omarchnix = {
      trustedReceiptKeys = [ pinnedTestPubkey ];
      verifyCurrentSystemService = false;
    };
  };

  invalidEnforcedNoKeysConfig = mkEval {
    security.omarchnix.enforceReceipts = true;
  };

  failedAssertions = builtins.filter (a: !a.assertion) invalidEnforcedNoKeysConfig.assertions;

  preSwitchScriptPkg = pkgs.writeShellScript "test-omarchnix-pre-switch" enforcedConfig.system.preSwitchChecks.omarchnix-receipts;
in
assert defaultConfig.security.omarchnix.trustedReceiptKeys == [ ];
assert defaultConfig.security.omarchnix.allowDevReceiptKeys == false;
assert defaultConfig.security.omarchnix.enforceReceipts == null;
assert !(defaultConfig.system.preSwitchChecks ? omarchnix-receipts);
assert !(defaultConfig.systemd.services ? omarchnix-verify-receipts);
assert !(defaultConfig.environment.etc ? "omarchnix/required-receipt-packages");
assert enforcedConfig.system.preSwitchChecks ? omarchnix-receipts;
assert lib.hasInfix "check --candidate" enforcedConfig.system.preSwitchChecks.omarchnix-receipts;
assert lib.hasInfix "--require-attestations"
  enforcedConfig.system.preSwitchChecks.omarchnix-receipts;
assert enforcedConfig.systemd.services ? omarchnix-verify-receipts;
assert lib.hasInfix "audit --path /run/current-system"
  enforcedConfig.systemd.services.omarchnix-verify-receipts.serviceConfig.ExecStart;
assert lib.hasInfix "current system closure"
  enforcedConfig.systemd.services.omarchnix-verify-receipts.description;
assert !(enforcedNoServiceConfig.systemd.services ? omarchnix-verify-receipts);
assert enforcedNoServiceConfig.system.preSwitchChecks ? omarchnix-receipts;
assert failedAssertions != [ ];
pkgs.runCommand "omarchnix-receipt-trust-check"
  {
    nativeBuildInputs = [
      pkgs.b3sum
      pkgs.coreutils
      pkgs.jq
      pkgs.openssl
      pkgs.python3
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

    receipt_file="${receiptGate.receiptPath}"
    bin_file="${receiptGate}/bin/omarchnix-receipt-gate"
    alt_receipt_file="${alternateSeedReceiptGate.receiptPath}"

    expected_pub="$(jq -r '.ed25519_pubkey' "$receipt_file")"
    alt_pub="$(jq -r '.ed25519_pubkey' "$alt_receipt_file")"
    receipt_b3="$(jq -r '.receipt_blake3' "$receipt_file")"
    bin_b3="$(b3sum --no-names "$bin_file")"

    stage_closure() {
      local dst="$1"
      rm -rf "$dst"
      mkdir -p "$dst/sw/bin" "$dst/sw/share/omarchnix/receipts"
      cp -f "$bin_file" "$dst/sw/bin/omarchnix-receipt-gate"
      chmod 755 "$dst/sw/bin/omarchnix-receipt-gate"
      cp -f "$receipt_file" "$dst/sw/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json"
      chmod 644 "$dst/sw/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json"
    }

    echo "[1/10] Fail closed when no trusted receipt public keys are configured"
    if omarchnix audit --path "${receiptGate}" --json > "$TMPDIR/no_keys.json"; then
      echo "ERROR: omarchnix audit unexpectedly succeeded without trusted keys" >&2
      exit 1
    fi
    jq -e '
      .ok == false
      and .error == "no_trusted_receipt_keys"
      and .trust_mode == "untrusted_missing_keys"
      and .verified_count == 0
    ' "$TMPDIR/no_keys.json" >/dev/null

    echo "[2/10] Explicit --allow-dev-keys permits unauthenticated dev/test verification only when opted in"
    omarchnix audit --path "${receiptGate}" --allow-dev-keys --json > "$TMPDIR/dev_keys.json"
    jq -e '
      .ok == true
      and .trust_mode == "dev_keys_unauthenticated"
      and .verified_count == 1
      and .receipts[0].trust_source == "dev_self_declared"
    ' "$TMPDIR/dev_keys.json" >/dev/null

    echo "[3/10] Reject self-signed receipt signed by untrusted key when pinned key differs"
    if omarchnix audit --path "${receiptGate}" --pubkey "$alt_pub" --json > "$TMPDIR/wrong_key.json"; then
      echo "ERROR: untrusted self-signed receipt unexpectedly passed pinned key audit" >&2
      exit 1
    fi
    jq -e '
      .ok == false
      and .error == "receipt_verification_failed"
      and .trust_mode == "pinned_trusted_keys"
      and .verified_count == 0
      and .receipts[0].ok == false
      and .receipts[0].gate.sig_verified == false
    ' "$TMPDIR/wrong_key.json" >/dev/null

    echo "[4/10] Candidate closure cannot self-supply trusted-receipt-keys"
    stage_closure "$TMPDIR/cand-self-key"
    mkdir -p "$TMPDIR/cand-self-key/etc/omarchnix"
    printf '%s\n' "$expected_pub" > "$TMPDIR/cand-self-key/etc/omarchnix/trusted-receipt-keys"
    if omarchnix check --candidate "$TMPDIR/cand-self-key" --json > "$TMPDIR/cand_self_key.json"; then
      echo "ERROR: candidate closure unexpectedly authenticated via its own etc/omarchnix/trusted-receipt-keys" >&2
      exit 1
    fi
    jq -e '
      .ok == false
      and .scope == "candidate"
      and (.checks | index("candidate_closure_receipts:failed") != null)
      and .candidate_audit.error == "no_trusted_receipt_keys"
    ' "$TMPDIR/cand_self_key.json" >/dev/null

    echo "[5/10] External operator Ed25519 attestation authenticates pure-sandbox store receipt without store secrets"
    openssl genpkey -algorithm ED25519 -out "$TMPDIR/op_priv.pem"
    openssl pkey -in "$TMPDIR/op_priv.pem" -pubout -outform DER -out "$TMPDIR/op_pub.der"
    op_pub_hex="$(python3 -c 'import pathlib, sys; d = pathlib.Path(sys.argv[1]).read_bytes(); assert len(d) == 44 and d[:12] == bytes.fromhex("302a300506032b6570032100"); print(d[12:].hex())' "$TMPDIR/op_pub.der")"
    test "$op_pub_hex" != "$expected_pub"

    printf 'omarchnix-receipt-attestation-v1\npackage=%s\nreceipt_blake3=%s\nbinary_blake3=%s\n' \
      "omarchnix-receipt-gate" \
      "$(printf '%s' "$receipt_b3" | tr '[:upper:]' '[:lower:]')" \
      "$(printf '%s' "$bin_b3" | tr '[:upper:]' '[:lower:]')" \
      > "$TMPDIR/att_payload.txt"
    openssl pkeyutl -sign -inkey "$TMPDIR/op_priv.pem" -rawin \
      -in "$TMPDIR/att_payload.txt" -out "$TMPDIR/att_sig.bin"
    op_sig_hex="$(python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).read_bytes().hex())' "$TMPDIR/att_sig.bin")"

    mkdir -p "$TMPDIR/attestations"
    jq -nc \
      --arg pkg "omarchnix-receipt-gate" \
      --arg rb3 "$receipt_b3" \
      --arg bb3 "$bin_b3" \
      --arg pub "$op_pub_hex" \
      --arg sig "$op_sig_hex" \
      '{
        schema: "omarchnix-receipt-attestation-v1",
        package: $pkg,
        receipt_blake3: $rb3,
        binary_blake3: $bb3,
        signature_alg: "ed25519-v1",
        signer_pubkey: $pub,
        ed25519_signature: $sig
      }' > "$TMPDIR/attestations/omarchnix-receipt-gate.''${receipt_b3}.attestation.json"

    omarchnix audit \
      --path "${receiptGate}" \
      --pubkey "$op_pub_hex" \
      --attestations-dir "$TMPDIR/attestations" \
      --require-attestations \
      --require-package omarchnix-receipt-gate \
      --json > "$TMPDIR/att_ok.json"
    jq -e '
      .ok == true
      and .verified_count == 1
      and .receipts[0].trust_source == "external_attestation"
      and .receipts[0].attestation_verified == true
      and .receipts[0].signer_pubkey == "'"$op_pub_hex"'"
    ' "$TMPDIR/att_ok.json" >/dev/null

    echo "[6/10] Reject tampered external attestation signature and --require-attestations without attestation"
    mkdir -p "$TMPDIR/bad-attestations"
    jq '.ed25519_signature = ("ff" + .ed25519_signature[2:])' \
      "$TMPDIR/attestations/omarchnix-receipt-gate.''${receipt_b3}.attestation.json" \
      > "$TMPDIR/bad-attestations/omarchnix-receipt-gate.''${receipt_b3}.attestation.json"
    if omarchnix audit \
      --path "${receiptGate}" \
      --pubkey "$op_pub_hex" \
      --attestations-dir "$TMPDIR/bad-attestations" \
      --require-attestations \
      --json > "$TMPDIR/att_bad.json"; then
      echo "ERROR: corrupted external attestation unexpectedly passed" >&2
      exit 1
    fi
    jq -e '.ok == false and .verified_count == 0 and .receipts[0].attestation_verified == false' "$TMPDIR/att_bad.json" >/dev/null

    mkdir -p "$TMPDIR/empty-attestations"
    if omarchnix audit \
      --path "${receiptGate}" \
      --pubkey "$expected_pub" \
      --attestations-dir "$TMPDIR/empty-attestations" \
      --require-attestations \
      --json > "$TMPDIR/att_missing_req.json"; then
      echo "ERROR: --require-attestations unexpectedly passed without external attestation" >&2
      exit 1
    fi
    jq -e '.ok == false and .verified_count == 0' "$TMPDIR/att_missing_req.json" >/dev/null

    echo "[7/10] Reject deleted/missing receipt for required critical package (even with --allow-empty)"
    stage_closure "$TMPDIR/deleted-receipt"
    rm -f "$TMPDIR/deleted-receipt/sw/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json"
    if omarchnix audit \
      --path "$TMPDIR/deleted-receipt" \
      --pubkey "$expected_pub" \
      --require-package omarchnix-receipt-gate \
      --allow-empty \
      --json > "$TMPDIR/deleted_receipt.json"; then
      echo "ERROR: deleted receipt for required package unexpectedly passed" >&2
      exit 1
    fi
    jq -e '
      .ok == false
      and .error == "missing_required_packages"
      and (.missing_packages | index("omarchnix-receipt-gate") != null)
    ' "$TMPDIR/deleted_receipt.json" >/dev/null

    echo "[8/10] Reject missing required package when another valid receipt is present"
    stage_closure "$TMPDIR/other-pkg-only"
    if omarchnix audit \
      --path "$TMPDIR/other-pkg-only" \
      --pubkey "$expected_pub" \
      --require-package omarchnix-receipt-gate \
      --require-package omarchnix-critical-missing \
      --json > "$TMPDIR/missing_second_pkg.json"; then
      echo "ERROR: missing second required package unexpectedly passed" >&2
      exit 1
    fi
    jq -e '
      .ok == false
      and .verified_count == 1
      and .error == "missing_required_packages"
      and (.missing_packages == ["omarchnix-critical-missing"])
    ' "$TMPDIR/missing_second_pkg.json" >/dev/null

    echo "[9/10] Reject uncovered duplicate binary when one receipt verifies but sw/bin binary is replaced"
    mkdir -p "$TMPDIR/uncovered-dup/pkg-good/bin" "$TMPDIR/uncovered-dup/pkg-good/share/omarchnix/receipts" "$TMPDIR/uncovered-dup/sw/bin"
    cp -f "$bin_file" "$TMPDIR/uncovered-dup/pkg-good/bin/omarchnix-receipt-gate"
    chmod 755 "$TMPDIR/uncovered-dup/pkg-good/bin/omarchnix-receipt-gate"
    cp -f "$receipt_file" "$TMPDIR/uncovered-dup/pkg-good/share/omarchnix/receipts/omarchnix-receipt-gate.receipt.json"
    cp -f "$bin_file" "$TMPDIR/uncovered-dup/sw/bin/omarchnix-receipt-gate"
    chmod 755 "$TMPDIR/uncovered-dup/sw/bin/omarchnix-receipt-gate"
    printf '\x55' >> "$TMPDIR/uncovered-dup/sw/bin/omarchnix-receipt-gate"
    if omarchnix audit \
      --path "$TMPDIR/uncovered-dup" \
      --pubkey "$expected_pub" \
      --require-package omarchnix-receipt-gate \
      --json > "$TMPDIR/uncovered_dup.json"; then
      echo "ERROR: uncovered duplicate sw/bin binary unexpectedly passed" >&2
      exit 1
    fi
    jq -e '
      .ok == false
      and .verified_count == 1
      and .error == "uncovered_required_binaries"
      and (.uncovered_binaries | length == 1)
    ' "$TMPDIR/uncovered_dup.json" >/dev/null

    echo "[10/10] Verify omarchnix check --candidate positive & negative pre-switch checks and module preSwitchChecks script"
    stage_closure "$TMPDIR/cand-good"
    printf '%s\n' "$expected_pub" > "$TMPDIR/trusted-keys.txt"
    printf 'omarchnix-receipt-gate\n' > "$TMPDIR/required-pkgs.txt"

    omarchnix check \
      --candidate "$TMPDIR/cand-good" \
      --trusted-keys-file "$TMPDIR/trusted-keys.txt" \
      --required-packages-file "$TMPDIR/required-pkgs.txt" \
      --json > "$TMPDIR/cand_good.json"
    jq -e '
      .ok == true
      and .scope == "candidate"
      and (.checks | index("candidate_closure_receipts:ok") != null)
      and .candidate_audit.ok == true
      and .candidate_audit.verified_count == 1
    ' "$TMPDIR/cand_good.json" >/dev/null

    stage_closure "$TMPDIR/cand-tampered"
    printf '\x99' >> "$TMPDIR/cand-tampered/sw/bin/omarchnix-receipt-gate"
    if omarchnix check \
      --candidate "$TMPDIR/cand-tampered" \
      --trusted-keys-file "$TMPDIR/trusted-keys.txt" \
      --required-packages-file "$TMPDIR/required-pkgs.txt" \
      --json > "$TMPDIR/cand_tampered.json"; then
      echo "ERROR: tampered candidate closure unexpectedly passed omarchnix check --candidate" >&2
      exit 1
    fi
    jq -e '
      .ok == false
      and .scope == "candidate"
      and (.checks | index("candidate_closure_receipts:failed") != null)
      and .candidate_audit.ok == false
    ' "$TMPDIR/cand_tampered.json" >/dev/null

    mkdir -p "$TMPDIR/preswitch-attestations"
    if OMARCHNIX_RECEIPT_ATTESTATIONS_DIR="$TMPDIR/preswitch-attestations" "${preSwitchScriptPkg}" "$TMPDIR/cand-good" switch > "$TMPDIR/preswitch_unattested.json"; then
      echo "ERROR: module preSwitchChecks script unexpectedly admitted unattested candidate" >&2
      exit 1
    fi
    jq -e '
      .ok == false
      and .scope == "candidate"
      and .candidate_audit.error == "receipt_verification_failed"
      and .candidate_audit.verified_count == 0
    ' "$TMPDIR/preswitch_unattested.json" >/dev/null

    cp "$TMPDIR/attestations/omarchnix-receipt-gate.''${receipt_b3}.attestation.json" \
      "$TMPDIR/preswitch-attestations/"
    printf '%s\n' "$op_pub_hex" > "$TMPDIR/op-keys.txt"
    omarchnix check \
      --candidate "$TMPDIR/cand-good" \
      --trusted-keys-file "$TMPDIR/op-keys.txt" \
      --required-packages-file "$TMPDIR/required-pkgs.txt" \
      --attestations-dir "$TMPDIR/preswitch-attestations" \
      --require-attestations \
      --json > "$TMPDIR/preswitch_attested.json"
    jq -e '
      .ok == true
      and .scope == "candidate"
      and .candidate_audit.ok == true
      and .candidate_audit.receipts[0].trust_source == "external_attestation"
    ' "$TMPDIR/preswitch_attested.json" >/dev/null

    cp "$TMPDIR/cand_good.json" "$out"
  ''
