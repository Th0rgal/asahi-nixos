{
  lib,
  pkgs,
  leanSys,
  turboLean,
}:
{
  pname,
  version ? "0.1.0",
  src,
  exeName ? pname,
  leanNativeInput,
  leanNativePrereqTargets ? [ ],
  leanNativeAnchorSymbols ? [ ],
  axiomCheckImports ? [ ],
  axiomCheckDecls ? [ ],
  specAuditFiles ? [ leanNativeInput ],
  selfTestArgs ? [ "self-test" ],
  receiptSigningSeedHex ? null,
  extraNativeBuildInputs ? [ ],
  meta ? { },
}:
let
  isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;
  isX86_64 = pkgs.stdenv.hostPlatform.isx86_64;
  leanNativeArch =
    if isAarch64 then
      "arm64"
    else if isX86_64 then
      "x86_64"
    else
      throw "buildVerifiedLeanSys: unsupported host architecture ${pkgs.stdenv.hostPlatform.system}";
  expectedElfMachine = if isAarch64 then "AArch64" else "Advanced Micro Devices X86-64";
  expectedObjectFormat = if isAarch64 then "ELF64 ET_REL EM_AARCH64" else "ELF64 ET_REL EM_X86_64";
  targetIsaLabel =
    if isAarch64 then
      "aarch64-linux+armv8.2a+neon+pmull64"
    else
      "x86_64-linux+x86-64-v2+sse2+pclmulqdq";

  # Deterministic Nix-sandbox Ed25519 receipt signing seed (DR-6: zero committed private keys).
  # Operators/CI may override via explicit `receiptSigningSeedHex` or runtime `TURBO_LEAN_RECEIPT_SIGNING_KEY`.
  defaultSeedHex = builtins.hashString "sha256" "omarchnix-verified-lean-sys-ed25519-v1:${pname}:${version}:${pkgs.stdenv.hostPlatform.system}";
  effectiveSeedHex = if receiptSigningSeedHex != null then receiptSigningSeedHex else defaultSeedHex;
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  inherit
    pname
    version
    src
    ;

  nativeBuildInputs = [
    pkgs.lean4
    pkgs.clang
    pkgs.binutils
    pkgs.b3sum
    pkgs.jq
    pkgs.patchelf
    turboLean
  ]
  ++ extraNativeBuildInputs;

  dontConfigure = true;
  # Preserve bit-identical binary BLAKE3 and LeanNative `.symtab` anchor symbols
  # across `installPhase` and `fixupPhase`; RPATHs are shrunk before signing.
  dontStrip = true;
  dontPatchELF = true;

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR/home"
    export TURBO_LEAN_STATE_DIR="$TMPDIR/turbo-lean-state"
    export LEAN_SYSROOT="${pkgs.lean4}"
    export TURBO_LEAN_BIN="${pkgs.lean4}/bin/lean"
    export TURBO_LEAN_STRICT_TOOLCHAIN=1
    export LEAN_CC="${pkgs.clang}/bin/clang"
    mkdir -p "$HOME" "$TURBO_LEAN_STATE_DIR" .lake/packages .lake/build/lib BuildArtifacts

    printf 'leanprover/lean4:v%s\n' "${pkgs.lean4.version}" > lean-toolchain

    rm -rf .lake/packages/lean-sys
    cp -r "${leanSys.pkgDir}" .lake/packages/lean-sys
    chmod -R u+w .lake/packages/lean-sys

    ${lib.concatMapStringsSep "\n" (
      target: "lake build ${lib.escapeShellArg target}"
    ) leanNativePrereqTargets}

    # 1. Compile the hot pure-Lean kernel module through LeanNative (LLVM 18 IR -> ELF64 .a).
    export LEAN_PATH="$PWD/.lake/build/lib/lean:$PWD/.lake/packages/lean-sys/.lake/build/lib/lean:${turboLean.leanLibDir}:${turboLean.leanSysLibDir}"

    ${
      if isAarch64 then
        ''
          lean-native compile-llvm \
            --input ${lib.escapeShellArg leanNativeInput} \
            --arch arm64 \
            --isa armv8.2-crypto \
            -o .lake/build/lib/liblean_native_kernels.ll

          ! grep -q '@llvm.aarch64.crypto.eor3u' .lake/build/lib/liblean_native_kernels.ll
          grep -q '@llvm.aarch64.neon.pmull64' .lake/build/lib/liblean_native_kernels.ll

          clang -O3 -fPIC -march=armv8.2-a+crypto+lse -Wno-override-module \
            -c .lake/build/lib/liblean_native_kernels.ll \
            -o "$TMPDIR/lean_native_kernels.o"
          ar rcs .lake/build/lib/liblean_native_kernels.a "$TMPDIR/lean_native_kernels.o"

          lean-native compile-static-lib \
            --input ${lib.escapeShellArg leanNativeInput} \
            --arch arm64 \
            --isa armv8.2-crypto \
            --clang-bin "$(command -v clang)" \
            --ar-bin "$(command -v ar)" \
            -o "$TMPDIR/lean_native_driver_check.a" \
            --header .lake/build/lib/liblean_native_kernels.h \
            --json > "$TMPDIR/lean_native_driver.json"
          jq -e '.status == "compiled_static_lib" and (.objectFormat | contains("${expectedObjectFormat}"))' "$TMPDIR/lean_native_driver.json" >/dev/null
        ''
      else
        ''
          lean-native compile-llvm \
            --input ${lib.escapeShellArg leanNativeInput} \
            --arch ${leanNativeArch} \
            -o .lake/build/lib/liblean_native_kernels.ll

          clang -O3 -fPIC -march=x86-64-v2 -mpclmul -Wno-override-module \
            -c .lake/build/lib/liblean_native_kernels.ll \
            -o "$TMPDIR/lean_native_kernels.o"
          ar rcs .lake/build/lib/liblean_native_kernels.a "$TMPDIR/lean_native_kernels.o"

          # Also emit the canonical C-ABI header and verify LeanNative's Linux ELF64 static-lib driver.
          lean-native compile-static-lib \
            --input ${lib.escapeShellArg leanNativeInput} \
            --arch ${leanNativeArch} \
            --clang-bin "$(command -v clang)" \
            --ar-bin "$(command -v ar)" \
            -o "$TMPDIR/lean_native_driver_check.a" \
            --header .lake/build/lib/liblean_native_kernels.h \
            --json > "$TMPDIR/lean_native_driver.json"
          jq -e '.status == "compiled_static_lib" and (.objectFormat | contains("${expectedObjectFormat}"))' "$TMPDIR/lean_native_driver.json" >/dev/null
        ''
    }

    readelf -h "$TMPDIR/lean_native_kernels.o" > "$TMPDIR/kernels_elf.txt"
    grep -q "Class:[[:space:]]*ELF64" "$TMPDIR/kernels_elf.txt"
    grep -q "Machine:[[:space:]]*${expectedElfMachine}" "$TMPDIR/kernels_elf.txt"

    # 2. Build the Lean 4 + lean-sys executable linked with liblean_native_kernels.a.
    unset LEAN_PATH
    lake build ${lib.escapeShellArg exeName}

    bin_path=".lake/build/bin/${exeName}"
    test -x "$bin_path"

    readelf -h "$bin_path" > "$TMPDIR/bin_elf.txt"
    grep -q "Class:[[:space:]]*ELF64" "$TMPDIR/bin_elf.txt"
    grep -q "Machine:[[:space:]]*${expectedElfMachine}" "$TMPDIR/bin_elf.txt"

    nm --defined-only "$bin_path" > "$TMPDIR/bin_nm.txt"
    ${lib.concatMapStringsSep "\n" (sym: ''
      grep -Eq "[[:space:]][Tt][[:space:]]+${sym}$" "$TMPDIR/bin_nm.txt"
    '') leanNativeAnchorSymbols}

    ${lib.optionalString (selfTestArgs != [ ]) ''
      "$bin_path" ${lib.escapeShellArgs selfTestArgs}
    ''}

    # 3. Kernel-level Lean.collectAxioms inspection via TurboLean.Inspector (0 sorryAx, 0 native_decide, 0 trustCompiler).
    ${lib.optionalString (axiomCheckDecls != [ ]) ''
      cat > "$TMPDIR/AxiomGate.lean" <<'AXIOM_EOF'
      import TurboLean.Inspector
      ${lib.concatMapStringsSep "\n" (imp: "import ${imp}") axiomCheckImports}

      #turbo_assert_clean_axioms [
      ${lib.concatMapStringsSep "\n" (d: "  ${d}") axiomCheckDecls}
      ]
      #turbo_inspect_axioms_json [
      ${lib.concatMapStringsSep "\n" (d: "  ${d}") axiomCheckDecls}
      ]
      AXIOM_EOF

      LEAN_PATH="$PWD/.lake/build/lib/lean:$PWD/.lake/packages/lean-sys/.lake/build/lib/lean:${turboLean.leanLibDir}:${turboLean.leanSysLibDir}" \
        lean "$TMPDIR/AxiomGate.lean" > "$TMPDIR/axiom_audit.json"

      jq -e 'length > 0 and all(.[]; .exists == true and .certified_clean == true and .has_sorry_ax == false and .has_reduce_bool == false and (.disallowed_axioms | length == 0))' \
        "$TMPDIR/axiom_audit.json" >/dev/null
    ''}

    # 4. Non-vacuity & tightness spec gate (`turbo-lean audit-spec`).
    ${lib.optionalString (specAuditFiles != [ ]) ''
      turbo-lean --json audit-spec --no-daemon --no-telemetry \
        ${lib.escapeShellArgs specAuditFiles} > "$TMPDIR/spec_audit.json"
      jq -e '.ok == true and .vacuous == false and .vacuous_specs == 0 and .trivial_specs == 0 and .tight_specs >= 1' \
        "$TMPDIR/spec_audit.json" >/dev/null
    ''}

    # 5. Shrink ELF RPATHs before hashing so the installed binary in `$out/bin`
    #    remains bit-for-bit identical to `BuildArtifacts/binary.blake3` and `.binary_blake3`.
    patchelf --shrink-rpath "$bin_path"

    # 6. Bind binary + LeanNative archive BLAKE3 digests into BuildArtifacts/
    #    BEFORE running `turbo-lean ci-verify --mode trusted` so the signed Schema v2
    #    `per_file_interfaces`, `action_key`, and `receipt_blake3` cryptographically
    #    cover the exact compiled binary and LeanNative static archive!
    rm -f BuildArtifacts/*.blake3 BuildArtifacts/*.lean
    binary_blake3="$(b3sum --no-names "$bin_path")"
    archive_blake3="$(b3sum --no-names .lake/build/lib/liblean_native_kernels.a)"
    ll_blake3="$(b3sum --no-names .lake/build/lib/liblean_native_kernels.ll)"
    printf '%s\n' "$binary_blake3" > BuildArtifacts/binary.blake3
    printf '%s\n' "$archive_blake3" > BuildArtifacts/lean_native_archive.blake3
    printf '%s\n' "$ll_blake3" > BuildArtifacts/lean_native_ir.blake3
    printf 'def omarchnixBinaryBlake3 : String := "%s"\n' "$binary_blake3" > "BuildArtifacts/BinaryBlake3_''${binary_blake3}.lean"
    printf 'def omarchnixArchiveBlake3 : String := "%s"\n' "$archive_blake3" > "BuildArtifacts/ArchiveBlake3_''${archive_blake3}.lean"

    signing_key="''${TURBO_LEAN_RECEIPT_SIGNING_KEY:-${effectiveSeedHex}}"
    turbo-lean --json ci-verify \
      --mode trusted \
      --no-daemon \
      --no-telemetry \
      --project-dir . \
      --receipt "$TMPDIR/raw.receipt.json" \
      --signing-key "$signing_key" > "$TMPDIR/ci_verify.json"

    jq -e '.schema_version == 2 and .mode == "trusted" and .forbidden_constructs_found == 0 and .signature_alg == "ed25519-v1" and (.ed25519_signature | length == 128) and (.ed25519_pubkey | length == 64)' \
      "$TMPDIR/raw.receipt.json" >/dev/null
    jq -e '.status == "ci_verified" and .zero_sorry == true and .zero_native_decide == true' \
      "$TMPDIR/ci_verify.json" >/dev/null

    # Re-verify that the installed binary is bit-identical to the recorded digest.
    test "$(b3sum --no-names "$bin_path")" = "$binary_blake3"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p \
      "$out/bin" \
      "$out/lib/omarchnix/${pname}" \
      "$out/include/omarchnix/${pname}" \
      "$out/share/omarchnix/receipts"

    install -Dm755 ".lake/build/bin/${exeName}" "$out/bin/${exeName}"
    install -Dm644 .lake/build/lib/liblean_native_kernels.a "$out/lib/omarchnix/${pname}/liblean_native_kernels.a"
    install -Dm644 .lake/build/lib/liblean_native_kernels.ll "$out/lib/omarchnix/${pname}/liblean_native_kernels.ll"
    if [[ -f .lake/build/lib/liblean_native_kernels.h ]]; then
      install -Dm644 .lake/build/lib/liblean_native_kernels.h "$out/include/omarchnix/${pname}/liblean_native_kernels.h"
    fi

    installed_bin_blake3="$(b3sum --no-names "$out/bin/${exeName}")"
    installed_archive_blake3="$(b3sum --no-names "$out/lib/omarchnix/${pname}/liblean_native_kernels.a")"
    installed_ir_blake3="$(b3sum --no-names "$out/lib/omarchnix/${pname}/liblean_native_kernels.ll")"
    axiom_audit_json="[]"
    if [[ -f "$TMPDIR/axiom_audit.json" ]]; then
      axiom_audit_json="$(cat "$TMPDIR/axiom_audit.json")"
    fi

    receipt_out="$out/share/omarchnix/receipts/${pname}.receipt.json"
    jq \
      --arg pkg "${pname}" \
      --arg ver "${version}" \
      --arg binPath "$out/bin/${exeName}" \
      --arg binBlake3 "$installed_bin_blake3" \
      --arg archivePath "$out/lib/omarchnix/${pname}/liblean_native_kernels.a" \
      --arg archiveBlake3 "$installed_archive_blake3" \
      --arg irBlake3 "$installed_ir_blake3" \
      --arg targetIsa "${targetIsaLabel}" \
      --arg objectFormat "${expectedObjectFormat}" \
      --argjson axiomAudit "$axiom_audit_json" \
      '. + {
        omarchnix_package: $pkg,
        omarchnix_version: $ver,
        binary_path: $binPath,
        binary_blake3: $binBlake3,
        lean_native_archive_path: $archivePath,
        lean_native_archive_blake3: $archiveBlake3,
        lean_native_ir_blake3: $irBlake3,
        codegen_backend: "LeanNative",
        target_isa: $targetIsa,
        object_format: $objectFormat,
        zero_sorry: (.forbidden_constructs_found == 0),
        zero_native_decide: (.forbidden_constructs_found == 0),
        sorry_ax_count: 0,
        axiom_audit: $axiomAudit
      }' "$TMPDIR/raw.receipt.json" > "$receipt_out"

    expected_pubkey="$(jq -r '.ed25519_pubkey' "$receipt_out")"
    turbo-lean --json verify-receipt \
      --no-daemon \
      --no-telemetry \
      --receipt "$receipt_out" \
      --require-signature \
      --verify-pubkey "$expected_pubkey" > "$TMPDIR/verify_receipt.json"
    jq -e '.status == "receipt_verified" and .schema_version == 2 and .signature_verified == true and .forbidden_constructs_found == 0' \
      "$TMPDIR/verify_receipt.json" >/dev/null

    runHook postInstall
  '';

  postFixup = ''
    receipt_out="$out/share/omarchnix/receipts/${pname}.receipt.json"
    recorded_bin_blake3="$(jq -r '.binary_blake3' "$receipt_out")"
    actual_bin_blake3="$(b3sum --no-names "$out/bin/${exeName}")"
    if [[ "$actual_bin_blake3" != "$recorded_bin_blake3" ]]; then
      echo "buildVerifiedLeanSys: postFixup binary BLAKE3 drift detected ($actual_bin_blake3 != $recorded_bin_blake3)" >&2
      exit 1
    fi
  '';

  passthru = {
    receiptPath = "${finalAttrs.finalPackage}/share/omarchnix/receipts/${pname}.receipt.json";
    inherit targetIsaLabel expectedObjectFormat;
  };

  meta = {
    description = "Verified Lean 4 + lean-sys + LeanNative binary with signed Schema v2 receipt (${pname})";
    mainProgram = exeName;
  }
  // meta;
})
