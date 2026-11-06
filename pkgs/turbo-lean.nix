{
  lib,
  pkgs,
  turboLeanSrc,
  leanSys,
}:
let
  patchModuleBuilder = pkgs.writeText "patch-turbo-lean-nix.py" ''
    from pathlib import Path

    mb_path = Path("crates/turbo-lean/src/module_builder.rs")
    src = mb_path.read_text()

    nix_lean_bin = "${pkgs.lean4}/bin/lean"
    nix_sys_path = "${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.binutils
        pkgs.clang
      ]
    }:/usr/bin:/bin"

    old_header = """pub(crate) fn parse_olean_header_version_and_githash(bytes: &[u8]) -> Option<(String, String)> {
        if bytes.len() < 80 || &bytes[0..5] != b"olean" || bytes[5] != 2 {
            return None;
        }
        let gh_bytes = &bytes[40..80];
        if !gh_bytes.iter().all(|b| b.is_ascii_hexdigit()) {
            return None;
        }
        let ver_end = bytes[7..40]
            .iter()
            .position(|&b| b == 0)
            .map(|i| 7 + i)
            .unwrap_or(40);
        let version = String::from_utf8_lossy(&bytes[7..ver_end])
            .trim()
            .to_string();
        let githash = String::from_utf8_lossy(gh_bytes).to_string();
        Some((version, githash))
    }"""
    new_header = f"""const NIX_PINNED_LEAN_BIN: &str = "{nix_lean_bin}";
    const NIX_VERIFIER_SYS_PATH: &str = "{nix_sys_path}";
    const NIX_NOGITHASH_PREFIX: &str = "00000000deca";

    fn nix_nogithash_identity(version: &str) -> String {{
        let h = blake3::hash(format!("nix-lean-nogithash:{{}}", version.trim()).as_bytes()).to_hex();
        format!("{{}}{{}}", NIX_NOGITHASH_PREFIX, &h[..28])
    }}

    fn lake_trace_githash_str(gh: &str) -> &str {{
        if gh.starts_with(NIX_NOGITHASH_PREFIX) {{
            ""
        }} else {{
            gh
        }}
    }}

    fn resolve_nix_store_empty_githash(canon_bin: &Path) -> Option<String> {{
        if !canon_bin.starts_with("/nix/store/") {{
            return None;
        }}
        let out = Command::new(canon_bin)
            .env("PATH", NIX_VERIFIER_SYS_PATH)
            .arg("--version")
            .output()
            .ok()?;
        if !out.status.success() {{
            return None;
        }}
        let stdout = String::from_utf8_lossy(&out.stdout);
        let after = stdout.split("version ").nth(1)?;
        let ver: String = after
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '.' || *c == '-')
            .collect();
        if ver.is_empty() {{
            return None;
        }}
        Some(nix_nogithash_identity(&ver))
    }}

    pub(crate) fn parse_olean_header_version_and_githash(bytes: &[u8]) -> Option<(String, String)> {{
        if bytes.len() < 80 || &bytes[0..5] != b"olean" || bytes[5] != 2 {{
            return None;
        }}
        let ver_end = bytes[7..40]
            .iter()
            .position(|&b| b == 0)
            .map(|i| 7 + i)
            .unwrap_or(40);
        let version = String::from_utf8_lossy(&bytes[7..ver_end])
            .trim()
            .to_string();
        let gh_bytes = &bytes[40..80];
        if gh_bytes.iter().all(|&b| b == 0) {{
            if version.is_empty() {{
                return None;
            }}
            return Some((version.clone(), nix_nogithash_identity(&version)));
        }}
        if !gh_bytes.iter().all(|b| b.is_ascii_hexdigit()) {{
            return None;
        }}
        let githash = String::from_utf8_lossy(gh_bytes).to_string();
        Some((version, githash))
    }}"""
    assert old_header in src, "missing parse_olean_header_version_and_githash"
    src = src.replace(old_header, new_header, 1)

    old_cand = """    for root in &elan_roots {
            let exact_tc = root.join("toolchains").join(&tc_dir_name).join("bin/lean");
            if exact_tc.is_file() {
                candidate_bins.push(exact_tc);
            }
        }"""
    new_cand = old_cand + """
        if candidate_bins.is_empty() {
            let nix_pinned = PathBuf::from(NIX_PINNED_LEAN_BIN);
            if nix_pinned.is_file() {
                candidate_bins.push(nix_pinned);
            }
        }"""
    assert old_cand in src, "missing elan_roots candidate loop"
    src = src.replace(old_cand, new_cand, 1)

    old_gh = """    if githash.is_empty() {
            anyhow::bail!(
                "`lean --githash` returned empty output for {}: fail-closed toolchain gate",
                canon_bin.display()
            );
        }
        // Verify that `canon_bin` matches the requested `toolchain` when `strict_tc` and `has_specific_tc` are true
        if !used_fallback_tc
            && has_specific_tc
            && !path_has_toolchain_component(&canon_bin, &tc_dir_name)
        {
            if is_untrusted
                || path_is_inside_any_toolchains_dir(&canon_bin)
                || path_is_elan_proxy_bin(&canon_bin)
            {"""
    new_gh = """    let githash = if githash.is_empty() {
            resolve_nix_store_empty_githash(&canon_bin).ok_or_else(|| {
                anyhow::anyhow!(
                    "`lean --githash` returned empty output for {}: fail-closed toolchain gate",
                    canon_bin.display()
                )
            })?
        } else {
            githash
        };
        // Verify that `canon_bin` matches the requested `toolchain` when `strict_tc` and `has_specific_tc` are true
        if !used_fallback_tc
            && has_specific_tc
            && !path_has_toolchain_component(&canon_bin, &tc_dir_name)
        {
            let is_nix_pinned = Path::new(NIX_PINNED_LEAN_BIN)
                .canonicalize()
                .ok()
                .as_deref()
                == Some(canon_bin.as_path());
            if (is_untrusted && !is_nix_pinned)
                || path_is_inside_any_toolchains_dir(&canon_bin)
                || path_is_elan_proxy_bin(&canon_bin)
            {"""
    assert old_gh in src, "missing githash/untrusted block in resolve_toolchain_compiler_with_roots"
    src = src.replace(old_gh, new_gh, 1)

    old_vpath = """pub(crate) fn verifier_path(lean: &Path) -> String {
        match lean.parent().filter(|p| p.is_absolute()) {
            Some(bin) => format!("{}:/usr/bin:/bin", bin.display()),
            None => "/usr/bin:/bin".into(),
        }
    }"""
    new_vpath = """pub(crate) fn verifier_path(lean: &Path) -> String {
        match lean.parent().filter(|p| p.is_absolute()) {
            Some(bin) => format!("{}:{}", bin.display(), NIX_VERIFIER_SYS_PATH),
            None => NIX_VERIFIER_SYS_PATH.into(),
        }
    }"""
    assert old_vpath in src, "missing verifier_path"
    src = src.replace(old_vpath, new_vpath, 1)

    old_gh_bin = """    let gh = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if gh.is_empty() {
            return None;
        }"""
    new_gh_bin = """    let gh_raw = String::from_utf8_lossy(&out.stdout).trim().to_string();
        let gh = if gh_raw.is_empty() {
            resolve_nix_store_empty_githash(&canon_bin)?
        } else {
            gh_raw
        };"""
    assert old_gh_bin in src, "missing lean_githash_for_bin check"
    src = src.replace(old_gh_bin, new_gh_bin, 1)

    src = src.replace(
        "let expected_gh = format!(\"{:016x}\", lake_hash_bytes(expected_bgh.as_bytes()));",
        "let expected_gh = format!(\"{:016x}\", lake_hash_bytes(lake_trace_githash_str(expected_bgh).as_bytes()));",
        1,
    )
    assert src.count("let expected_gh = format!(\"{:016x}\", lake_hash_bytes(cfg.lean_githash.as_bytes()));") == 2
    src = src.replace(
        "let expected_gh = format!(\"{:016x}\", lake_hash_bytes(cfg.lean_githash.as_bytes()));",
        "let expected_gh = format!(\"{:016x}\", lake_hash_bytes(lake_trace_githash_str(&cfg.lean_githash).as_bytes()));",
    )

    old_cap = """    let lean_cap = format!("Lean {}, commit {}", ver_short, cfg.lean_githash);
        let lean_gh_h = lake_hash_bytes(cfg.lean_githash.as_bytes());"""
    new_cap = """    let trace_gh = lake_trace_githash_str(&cfg.lean_githash);
        let lean_cap = format!("Lean {}, commit {}", ver_short, trace_gh);
        let lean_gh_h = lake_hash_bytes(trace_gh.as_bytes());"""
    assert src.count(old_cap) == 3, f"expected 3 lean_cap occurrences, got {src.count(old_cap)}"
    src = src.replace(old_cap, new_cap)

    old_target = """    let target = target.filter(|s| !s.is_empty()).ok_or_else(|| {"""
    new_target = """    let target = target.filter(|s| !s.is_empty() || canon_bin.starts_with("/nix/store/")).ok_or_else(|| {"""
    assert old_target in src, "missing System.Platform.target check"
    src = src.replace(old_target, new_target, 1)

    mb_path.write_text(src)

    types_path = Path("lean/LeanNative/IR/Types.lean")
    types_src = types_path.read_text()

    old_llvm_feats = """    (if a.lse then ["+lse"] else []) ++
        (if a.sha3 then ["+aes", "+sha2", "+sha3"] else [])"""
    new_llvm_feats = """    (if a.lse then ["+lse"] else []) ++
        (if a.sha3 then ["+aes", "+sha2", "+sha3"] else if a.vpclmulqdq then ["+aes", "+sha2"] else [])"""
    assert old_llvm_feats in types_src, "missing llvmTargetFeatures crypto branch"
    types_src = types_src.replace(old_llvm_feats, new_llvm_feats, 1)

    old_clang_arch = """    (if a.lse then ["+lse"] else []) ++
        (if a.sha3 then ["+sha3"] else [])
      "-march=" ++ baseStr ++ String.join exts"""
    new_clang_arch = """    (if a.lse then ["+lse"] else []) ++
        (if a.sha3 then ["+sha3"] else if a.vpclmulqdq then ["+crypto"] else [])
      "-march=" ++ baseStr ++ String.join exts

    def arm64Crypto : LeanSys.Par.IsaLevel :=
      { LeanSys.Par.IsaLevel.arm64Baseline with vpclmulqdq := true }"""
    assert old_clang_arch in types_src, "missing clangArchFlag crypto branch"
    types_src = types_src.replace(old_clang_arch, new_clang_arch, 1)
    types_path.write_text(types_src)

    llvm_path = Path("lean/LeanNative/Backend/LLVM.lean")
    llvm_src = llvm_path.read_text()

    old_codegen_req = """def codegenRequires (d : LNIRDecl) (targetIsa : IsaLevel := IsaLevel.arm64Baseline) : IsaLevel :=
      let usesAtomic := (selectDeclRcMode d == .atomic) && targetIsa.lse
      let usesSimd := codeHasParFor d.body
      let usesCrypto := codeHasCryptoOps d.body && targetIsa.sha3
      let emitSve2 := usesSimd && targetIsa.sve2
      let emitBitperm := emitSve2 && targetIsa.sveBitperm
      let reqRank :=
        if emitSve2 then 4
        else if usesCrypto then 2
        else if usesAtomic then 1
        else 0
      { base       := ArmBase.ofRank (Nat.min reqRank targetIsa.base.rank)
        neon       := targetIsa.neon
        fp16       := false
        dotprod    := false
        i8mm       := false
        bf16       := false
        sve2       := emitSve2
        sveBitperm := emitBitperm
        sme2       := false
        lse        := usesAtomic
        sha3       := usesCrypto }"""
    new_codegen_req = """def codegenRequires (d : LNIRDecl) (targetIsa : IsaLevel := IsaLevel.arm64Baseline) : IsaLevel :=
      let usesAtomic := (selectDeclRcMode d == .atomic) && targetIsa.lse
      let usesSimd := codeHasParFor d.body
      let hasCrypto := codeHasCryptoOps d.body
      let usesSha3 := hasCrypto && targetIsa.sha3
      let usesPmull := hasCrypto && targetIsa.vpclmulqdq
      let emitSve2 := usesSimd && targetIsa.sve2
      let emitBitperm := emitSve2 && targetIsa.sveBitperm
      let reqRank :=
        if emitSve2 then 4
        else if usesSha3 then 2
        else if usesPmull || usesAtomic then 1
        else 0
      { base       := ArmBase.ofRank (Nat.min reqRank targetIsa.base.rank)
        neon       := targetIsa.neon
        fp16       := false
        dotprod    := false
        i8mm       := false
        bf16       := false
        sve2       := emitSve2
        sveBitperm := emitBitperm
        sme2       := false
        lse        := usesAtomic
        sha3       := usesSha3
        vpclmulqdq := usesPmull }"""
    assert old_codegen_req in llvm_src, "missing codegenRequires"
    llvm_src = llvm_src.replace(old_codegen_req, new_codegen_req, 1)

    old_rank_thm = """theorem codegen_rank_le_target (s c a : Bool) (b : ArmBase) :
        decide ((ArmBase.ofRank (Nat.min (if s then 4 else if c then 2 else if a then 1 else 0) b.rank)).rank ≤ b.rank) = true := by
      cases s <;> cases c <;> cases a <;> cases b <;> rfl"""
    new_rank_thm = """theorem codegen_rank_le_target (s c p a : Bool) (b : ArmBase) :
        decide ((ArmBase.ofRank (Nat.min (if s then 4 else if c then 2 else if p || a then 1 else 0) b.rank)).rank ≤ b.rank) = true := by
      cases s <;> cases c <;> cases p <;> cases a <;> cases b <;> rfl"""
    assert old_rank_thm in llvm_src, "missing codegen_rank_le_target"
    llvm_src = llvm_src.replace(old_rank_thm, new_rank_thm, 1)

    old_pmull_guard = "else if st.optimized && st.target.isAArch64 && st.isa.sha3 then\n        let vp8 ← freshTmp \"cl_vp8\""
    new_pmull_guard = "else if st.optimized && st.target.isAArch64 && (st.isa.sha3 || st.isa.vpclmulqdq) then\n        let vp8 ← freshTmp \"cl_vp8\""
    assert old_pmull_guard in llvm_src, "missing pmull64 guard"
    llvm_src = llvm_src.replace(old_pmull_guard, new_pmull_guard, 1)

    old_clmul_decl = """def emitRuntimeAndCAbiHelpers (optimized : Bool) (target : TargetArch := .x86_64) : String :=
      let attr := if optimized then "#0" else "#1"
      let loopMd := if optimized then ", !llvm.loop !0" else ", !llvm.loop !3"
      let clmulDecl :=
        if target.isAArch64 then
          "declare <16 x i8> @llvm.aarch64.neon.pmull64(i64, i64) #2\\ndeclare <2 x i64> @llvm.aarch64.crypto.eor3u.v2i64(<2 x i64>, <2 x i64>, <2 x i64>) #2\\ndeclare i64 @llvm.vscale.i64() #2"
        else "declare <2 x i64> @llvm.x86.pclmulqdq(<2 x i64>, <2 x i64>, i8 immarg) #2\""""
    new_clmul_decl = """def emitRuntimeAndCAbiHelpers (optimized : Bool) (target : TargetArch := .x86_64) (isaOverride? : Option IsaLevel := none) : String :=
      let targetIsa := isaOverride?.getD target.isaLevel
      let attr := if optimized then "#0" else "#1"
      let loopMd := if optimized then ", !llvm.loop !0" else ", !llvm.loop !3"
      let clmulDecl :=
        if target.isAArch64 then
          let eor3Decl := if targetIsa.sha3 then "\\ndeclare <2 x i64> @llvm.aarch64.crypto.eor3u.v2i64(<2 x i64>, <2 x i64>, <2 x i64>) #2" else ""
          s!"declare <16 x i8> @llvm.aarch64.neon.pmull64(i64, i64) #2{eor3Decl}\\ndeclare i64 @llvm.vscale.i64() #2"
        else "declare <2 x i64> @llvm.x86.pclmulqdq(<2 x i64>, <2 x i64>, i8 immarg) #2\""""
    assert old_clmul_decl in llvm_src, "missing emitRuntimeAndCAbiHelpers clmulDecl"
    llvm_src = llvm_src.replace(old_clmul_decl, new_clmul_decl, 1)

    old_runtime_call = "  let runtimeStr := emitRuntimeAndCAbiHelpers optimized target"
    new_runtime_call = "  let runtimeStr := emitRuntimeAndCAbiHelpers optimized target isaOverride?"
    assert old_runtime_call in llvm_src, "missing emitRuntimeAndCAbiHelpers call"
    llvm_src = llvm_src.replace(old_runtime_call, new_runtime_call, 1)
    llvm_path.write_text(llvm_src)

    worker_path = Path("lean/LeanNative/Driver/Worker.lean")
    worker_src = worker_path.read_text()

    old_parse_arch = """def parseTargetArch (raw : String) : TargetArch :=
      (parseTargetArch? raw).getD .x86_64"""
    new_parse_arch = """def parseTargetArch (raw : String) : TargetArch :=
      (parseTargetArch? raw).getD .x86_64

    def parseIsaLevel? : String → Option IsaLevel
      | "" => some IsaLevel.arm64Baseline
      | "baseline" | "arm64-baseline" | "armv8.2" | "armv8.2-a" => some IsaLevel.arm64Baseline
      | "armv8.2-crypto" | "arm64-crypto" | "aarch64-crypto" | "armv8.2-a+crypto" => some IsaLevel.arm64Crypto
      | "apple-a15" | "apple-m2" | "armv8.5-sha3" => some IsaLevel.appleA15
      | "apple-a16" | "apple-a17" => some IsaLevel.appleA16_A17
      | "tensor-g3" | "sve2" => some IsaLevel.tensorG3
      | "apple-m4" | "apple-a18" => some IsaLevel.appleM4_A18
      | _ => none

    def parseIsaOverrideIO (raw : String) : IO (Option IsaLevel) := do
      if raw.isEmpty then return none
      match parseIsaLevel? raw with
      | some isa => return some isa
      | none => throw <| IO.userError s!"[lean-native] Unsupported ISA profile '{raw}' (expected arm64-baseline, armv8.2-crypto, apple-a15, apple-a16, tensor-g3, or apple-m4)\""""
    assert old_parse_arch in worker_src, "missing parseTargetArch in Worker.lean"
    worker_src = worker_src.replace(old_parse_arch, new_parse_arch, 1)

    old_worker_llvm = """        let isBase := hasRpcBoolField line "baseline" true
            let wasmSimd128 := hasRpcBoolField line "wasmSimd128" true || hasRpcBoolField line "wasm_simd128" true
            let modForCallCheck := match effModOpt with
              | some m => if isBase then m else (runDefaultPipeline m).1
              | none => if isBase then cache.baseMod else cache.optMod
            match findUnsupportedLLVMCall? modForCallCheck with
            | some (dName, callee) =>
              s!"\\{\\"id\\":{reqId},\\"ok\\":false,\\"error\\":\\"unsupported_llvm_call:{escapeJsonWorker dName}:{escapeJsonWorker callee}\\"}"
            | none =>
              let ir := match effModOpt with
                | some m =>
                  if isBase then emitLLVMBaseline m arch none wasmSimd128 else emitLLVMOptimized (runDefaultPipeline m).1 arch none wasmSimd128
                | none =>
                  if isBase then (if arch == .x86_64 then cache.llvmBaseX86 else emitLLVMBaseline cache.baseMod arch none wasmSimd128)
                  else if arch == .arm64 then cache.llvmOptArm
                  else if arch == .x86_64 then cache.llvmOptX86
                  else emitLLVMOptimized cache.optMod arch none wasmSimd128"""
    new_worker_llvm = """        let isaRaw := (extractRpcStringField line "isa").getD ""
            match if isaRaw.isEmpty then some none else (parseIsaLevel? isaRaw).map some with
            | none =>
              s!"\\{\\"id\\":{reqId},\\"ok\\":false,\\"error\\":\\"unsupported_isa_level:{escapeJsonWorker isaRaw}\\"}"
            | some isaOverride? =>
            let isBase := hasRpcBoolField line "baseline" true
            let wasmSimd128 := hasRpcBoolField line "wasmSimd128" true || hasRpcBoolField line "wasm_simd128" true
            let modForCallCheck := match effModOpt with
              | some m => if isBase then m else (runDefaultPipeline m).1
              | none => if isBase then cache.baseMod else cache.optMod
            match findUnsupportedLLVMCall? modForCallCheck with
            | some (dName, callee) =>
              s!"\\{\\"id\\":{reqId},\\"ok\\":false,\\"error\\":\\"unsupported_llvm_call:{escapeJsonWorker dName}:{escapeJsonWorker callee}\\"}"
            | none =>
              let ir := match effModOpt with
                | some m =>
                  if isBase then emitLLVMBaseline m arch isaOverride? wasmSimd128 else emitLLVMOptimized (runDefaultPipeline m).1 arch isaOverride? wasmSimd128
                | none =>
                  if isBase then (if arch == .x86_64 && isaOverride?.isNone then cache.llvmBaseX86 else emitLLVMBaseline cache.baseMod arch isaOverride? wasmSimd128)
                  else if arch == .arm64 && isaOverride?.isNone then cache.llvmOptArm
                  else if arch == .x86_64 && isaOverride?.isNone then cache.llvmOptX86
                  else emitLLVMOptimized cache.optMod arch isaOverride? wasmSimd128"""
    assert old_worker_llvm in worker_src, "missing compile-llvm branch in Worker.lean"
    worker_src = worker_src.replace(old_worker_llvm, new_worker_llvm, 1)
    worker_path.write_text(worker_src)

    cli_path = Path("lean/LeanNative/Driver/CoreCLI.lean")
    cli_src = cli_path.read_text()

    old_val_flags = """def valueTakingFlags : List String :=
      ["-o", "--arch", "--target", "--profile", "--sm", "--samples", "--lean","""
    new_val_flags = """def valueTakingFlags : List String :=
      ["-o", "--arch", "--target", "--isa", "--profile", "--sm", "--samples", "--lean","""
    assert old_val_flags in cli_src, "missing valueTakingFlags"
    cli_src = cli_src.replace(old_val_flags, new_val_flags, 1)

    old_compile_mode = """    writeOrPrint opts.outputPath (if opts.isBaseline then emitLLVMBaseline optMod opts.arch none wasmSimd128 else emitLLVMOptimized optMod opts.arch none wasmSimd128)"""
    new_compile_mode = """    let isaOverride? ← parseIsaOverrideIO (findFlagValue args "--isa" "")
        writeOrPrint opts.outputPath (if opts.isBaseline then emitLLVMBaseline optMod opts.arch isaOverride? wasmSimd128 else emitLLVMOptimized optMod opts.arch isaOverride? wasmSimd128)"""
    assert old_compile_mode in cli_src, "missing runCompileMode emitLLVM"
    cli_src = cli_src.replace(old_compile_mode, new_compile_mode, 1)

    old_compile_llvm = """  let arch ← parseTargetArchIO (findFlagValue args "--arch" (findFlagValue args "--target" "x86_64"))
      let isBaseline := hasFlag args "--baseline"
      let wasmSimd128 := hasFlag args "--wasm-simd128"
      let outPath := findFlagValue args "-o" "" """.rstrip()
    new_compile_llvm = """  let arch ← parseTargetArchIO (findFlagValue args "--arch" (findFlagValue args "--target" "x86_64"))
      let isaOverride? ← parseIsaOverrideIO (findFlagValue args "--isa" "")
      let isBaseline := hasFlag args "--baseline"
      let wasmSimd128 := hasFlag args "--wasm-simd128"
      let outPath := findFlagValue args "-o" "" """.rstrip()
    assert old_compile_llvm in cli_src, "missing runCompileLLVM header"
    cli_src = cli_src.replace(old_compile_llvm, new_compile_llvm, 1)

    old_compile_llvm_emit = "  let irText := if isBaseline then emitLLVMBaseline modToEmit arch none wasmSimd128 else emitLLVMOptimized modToEmit arch none wasmSimd128"
    new_compile_llvm_emit = "  let irText := if isBaseline then emitLLVMBaseline modToEmit arch isaOverride? wasmSimd128 else emitLLVMOptimized modToEmit arch isaOverride? wasmSimd128"
    assert old_compile_llvm_emit in cli_src, "missing runCompileLLVM emit"
    cli_src = cli_src.replace(old_compile_llvm_emit, new_compile_llvm_emit, 1)

    old_static_lib = """  let arch ← parseTargetArchIO (findFlagValue args "--arch" (findFlagValue args "--target" "x86_64"))
      if arch == .nvptx64 || arch == .hybridCpuGpu || arch == .wasm32 then
        throw <| IO.userError s!"[{tag}] Static archive verification unsupported for {arch.triple}"
      let wasmSimd128 := hasFlag args "--wasm-simd128" """.rstrip()
    new_static_lib = """  let arch ← parseTargetArchIO (findFlagValue args "--arch" (findFlagValue args "--target" "x86_64"))
      let isaOverride? ← parseIsaOverrideIO (findFlagValue args "--isa" "")
      if arch == .nvptx64 || arch == .hybridCpuGpu || arch == .wasm32 then
        throw <| IO.userError s!"[{tag}] Static archive verification unsupported for {arch.triple}"
      let wasmSimd128 := hasFlag args "--wasm-simd128" """.rstrip()
    assert old_static_lib in cli_src, "missing runCompileStaticLib header"
    cli_src = cli_src.replace(old_static_lib, new_static_lib, 1)

    old_static_emit = """  let irText := emitLLVMOptimized optMod arch none wasmSimd128
      let hdrText := emitCAbiHeaderFromSigs sigs (width? := some (ArchWidth.ofTargetArch arch))
      let nonce ← IO.monoNanosNow
      let (tmpLl, tmpObj, tmpArchive, tmpAsm) := (s!"{outPath}.{nonce}.tmp.ll", s!"{outPath}.{nonce}.tmp.o", s!"{outPath}.{nonce}.tmp.a", s!"{asmPath}.{nonce}.tmp.s")
      IO.FS.writeFile tmpLl irText
      let runCmd (cmd : String) (cmdArgs : Array String) : IO (Bool × String) := do
        try let res ← IO.Process.output { cmd, args := cmdArgs }; return (res.exitCode == 0, res.stderr.trimAscii.toString)
        catch e => return (false, toString e)
      let cpuFlags : Array String := arch.clangFlags none wasmSimd128"""
    new_static_emit = """  let irText := emitLLVMOptimized optMod arch isaOverride? wasmSimd128
      let hdrText := emitCAbiHeaderFromSigs sigs (width? := some (ArchWidth.ofTargetArch arch))
      let nonce ← IO.monoNanosNow
      let (tmpLl, tmpObj, tmpArchive, tmpAsm) := (s!"{outPath}.{nonce}.tmp.ll", s!"{outPath}.{nonce}.tmp.o", s!"{outPath}.{nonce}.tmp.a", s!"{asmPath}.{nonce}.tmp.s")
      IO.FS.writeFile tmpLl irText
      let runCmd (cmd : String) (cmdArgs : Array String) : IO (Bool × String) := do
        try let res ← IO.Process.output { cmd, args := cmdArgs }; return (res.exitCode == 0, res.stderr.trimAscii.toString)
        catch e => return (false, toString e)
      let cpuFlags : Array String := arch.clangFlags isaOverride? wasmSimd128"""
    assert old_static_emit in cli_src, "missing runCompileStaticLib emit block"
    cli_src = cli_src.replace(old_static_emit, new_static_emit, 1)

    old_sve2_test = 'let tmpLl := "/tmp/ln_sve2_verify.ll"'
    new_sve2_test = 'let tmpDir := (← IO.getEnv "TMPDIR").getD "/tmp"\n    let tmpLl := s!"{tmpDir}/ln_sve2_verify.ll"'
    assert old_sve2_test in cli_src, "missing ln_sve2_verify.ll in CoreCLI.lean"
    cli_src = cli_src.replace(old_sve2_test, new_sve2_test, 1)

    old_clang_test = 'let out ← IO.Process.output { cmd := clangCmd, args := #["--target=aarch64-linux-android29", "-O3", "-Wno-override-module", "-S", tmpLl, "-o", "-"] }'
    new_clang_test = 'let out ← IO.Process.output { cmd := "${pkgs.clang.cc}/bin/clang", args := #["--target=aarch64-linux-android29", "-O3", "-Wno-override-module", "-S", tmpLl, "-o", "-"] }'
    assert old_clang_test in cli_src, "missing clang process call in CoreCLI.lean"
    cli_src = cli_src.replace(old_clang_test, new_clang_test, 1)

    cli_path.write_text(cli_src)
  '';
in
pkgs.rustPlatform.buildRustPackage (finalAttrs: {
  pname = "turbo-lean";
  version = "0.1.0-${builtins.substring 0 7 (turboLeanSrc.rev or "pinned")}";
  src = turboLeanSrc;

  cargoLock = {
    lockFile = "${turboLeanSrc}/Cargo.lock";
  };

  nativeBuildInputs = [
    pkgs.lean4
    pkgs.clang
    pkgs.binutils
    pkgs.makeWrapper
    pkgs.python3
  ];

  # Tests require live network/daemon fixtures outside the hermetic Nix sandbox;
  # we run `lean-native` and `turbo-lean --version` smoke checks in postCheck/postInstall.
  doCheck = false;

  preBuild = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export LEAN_SYSROOT="${pkgs.lean4}"
    export TURBO_LEAN_BIN="${pkgs.lean4}/bin/lean"

    chmod -R u+w crates lean
    python3 "${patchModuleBuilder}"

    printf 'leanprover/lean4:v%s\n' "${pkgs.lean4.version}" > lean/lean-toolchain

    awk '
      /^require «lean-sys» from git/ {
        print "require «lean-sys» from \".lake/packages/lean-sys\""
        getline
        next
      }
      { print }
    ' lean/lakefile.lean > lean/lakefile.lean.offline
    mv lean/lakefile.lean.offline lean/lakefile.lean

    cat > lean/lake-manifest.json <<'EOF'
    {"version": "1.3.0",
     "packagesDir": ".lake/packages",
     "packages":
     [{"type": "path",
       "scope": "",
       "name": "«lean-sys»",
       "manifestFile": "lake-manifest.json",
       "inherited": false,
       "dir": ".lake/packages/lean-sys",
       "configFile": "lakefile.lean"}],
     "name": "«turbo-lean-proofs»",
     "lakeDir": ".lake",
     "fixedToolchain": false}
    EOF

    mkdir -p lean/.lake/packages
    cp -r "${leanSys.pkgDir}" lean/.lake/packages/lean-sys
    chmod -R u+w lean/.lake/packages/lean-sys

    (
      cd lean
      lake build LeanNative.Spec TurboLean.Inspector lean-native
    )
  '';

  postInstall = ''
    mkdir -p "$out/share/turbo-lean" "$out/libexec/turbo-lean"
    install -Dm755 lean/.lake/build/bin/lean-native "$out/libexec/turbo-lean/lean-native-unwrapped"

    cp -r lean/.lake/build/lib/lean "$out/share/turbo-lean/lib-lean"
    cp -r lean/.lake/packages/lean-sys/.lake/build/lib/lean "$out/share/turbo-lean/lean-sys-lib-lean"

    makeWrapper "$out/libexec/turbo-lean/lean-native-unwrapped" "$out/bin/lean-native" \
      --set-default LEAN_SYSROOT "${pkgs.lean4}" \
      --suffix PATH : "${
        lib.makeBinPath [
          pkgs.lean4
          pkgs.clang
          pkgs.binutils
        ]
      }" \
      --suffix LEAN_PATH : "$out/share/turbo-lean/lib-lean:$out/share/turbo-lean/lean-sys-lib-lean"

    wrapProgram "$out/bin/turbo-lean" \
      --set-default LEAN_SYSROOT "${pkgs.lean4}" \
      --set-default TURBO_LEAN_BIN "${pkgs.lean4}/bin/lean" \
      --set-default LEAN_CC "${pkgs.clang}/bin/clang" \
      --suffix PATH : "${
        lib.makeBinPath [
          pkgs.lean4
          pkgs.clang
          pkgs.binutils
        ]
      }"

    "$out/bin/turbo-lean" --version >/dev/null
    "$out/bin/lean-native" --help >/dev/null

    cat > "$TMPDIR/Arm64Crypto.lean" <<'LEAN_EOF'
    import LeanNative.IR.Types

    def mixCrypto (a b c : UInt64) : UInt64 :=
      LeanNative.IR.eor3 (LeanNative.IR.clmul64 a b) c
    LEAN_EOF

    "$out/bin/lean-native" compile-llvm \
      --input "$TMPDIR/Arm64Crypto.lean" --arch arm64 --isa armv8.2-crypto \
      -o "$TMPDIR/arm64-crypto.ll"
    grep -Fq 'target triple = "aarch64-unknown-linux-gnu"' "$TMPDIR/arm64-crypto.ll"
    grep -Fq 'target datalayout = "e-m:e-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128"' "$TMPDIR/arm64-crypto.ll"
    grep -Fq 'call <16 x i8> @llvm.aarch64.neon.pmull64' "$TMPDIR/arm64-crypto.ll"
    grep -Fq '+aes,+sha2' "$TMPDIR/arm64-crypto.ll"
    ! grep -Fq '@llvm.aarch64.crypto.eor3u' "$TMPDIR/arm64-crypto.ll"
    "${pkgs.clang.cc}/bin/clang" --target=aarch64-unknown-linux-gnu -O3 -fPIC -march=armv8.2-a+crypto+lse \
      -c "$TMPDIR/arm64-crypto.ll" -o "$TMPDIR/arm64-crypto.o"
    readelf -h "$TMPDIR/arm64-crypto.o" > "$TMPDIR/arm64-crypto.elf"
    grep -q 'Machine:.*AArch64' "$TMPDIR/arm64-crypto.elf"

    "$out/bin/lean-native" compile-llvm \
      --input "$TMPDIR/Arm64Crypto.lean" --arch arm64 \
      -o "$TMPDIR/arm64-baseline.ll"
    ! grep -Fq 'call <16 x i8> @llvm.aarch64.neon.pmull64' "$TMPDIR/arm64-baseline.ll"
    ! grep -Fq 'call <2 x i64> @llvm.aarch64.crypto.eor3u' "$TMPDIR/arm64-baseline.ll"

    "$out/bin/lean-native" compile-llvm \
      --input "$TMPDIR/Arm64Crypto.lean" --arch arm64 --isa apple-a15 \
      -o "$TMPDIR/arm64-sha3.ll"
    grep -Fq 'call <2 x i64> @llvm.aarch64.crypto.eor3u' "$TMPDIR/arm64-sha3.ll"

    "$out/bin/lean-native" compile-static-lib \
      --input "$TMPDIR/Arm64Crypto.lean" --arch arm64 --isa armv8.2-crypto \
      --clang-bin "${pkgs.clang.cc}/bin/clang" --ar-bin "$(command -v ar)" \
      -o "$TMPDIR/arm64-crypto.a" --header "$TMPDIR/arm64-crypto.h"
    "$out/bin/lean-native" audit-axioms >/dev/null
    "$out/bin/lean-native" self-test >/dev/null
    if "$out/bin/lean-native" compile-llvm --input "$TMPDIR/Arm64Crypto.lean" --arch arm64 --isa unknown-isa \
      -o "$TMPDIR/invalid-isa.ll" 2>"$TMPDIR/invalid-isa.err"; then
      exit 1
    fi
    grep -Fq "Unsupported ISA profile 'unknown-isa'" "$TMPDIR/invalid-isa.err"
    test ! -e "$TMPDIR/invalid-isa.ll"
  '';

  passthru = {
    leanLibDir = "${finalAttrs.finalPackage}/share/turbo-lean/lib-lean";
    leanSysLibDir = "${finalAttrs.finalPackage}/share/turbo-lean/lean-sys-lib-lean";
  };

  meta = {
    description = "Verified proof build orchestrator, Schema v2 BLAKE3/Ed25519 receipt signer, and LeanNative LLVM 18 compiler";
    mainProgram = "turbo-lean";
  };
})
