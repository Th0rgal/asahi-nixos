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
