{
  pkgs,
  leanSysSrc,
}:
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "lean-sys";
  version = "0.1.0-${builtins.substring 0 7 (leanSysSrc.rev or "pinned")}";
  src = leanSysSrc;

  nativeBuildInputs = [
    pkgs.lean4
    pkgs.clang
    pkgs.binutils
    pkgs.python3
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    printf 'leanprover/lean4:v%s\n' "${pkgs.lean4.version}" > lean-toolchain

    lake build LeanSys lean-sys-core
    ./.lake/build/bin/lean-sys-core --c-abi | grep -q '"ok":true'
    ./.lake/build/bin/lean-sys-core bench 64 | grep -q '"ok":true'
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share/lean-sys"
    install -Dm755 .lake/build/bin/lean-sys-core "$out/bin/lean-sys-core"

    cp -r LeanSys LeanSys.lean c lakefile.lean lean-toolchain .lake "$out/share/lean-sys/"
    runHook postInstall
  '';

  passthru = {
    pkgDir = "${finalAttrs.finalPackage}/share/lean-sys";
    leanLibDir = "${finalAttrs.finalPackage}/share/lean-sys/.lake/build/lib/lean";
  };

  meta = {
    description = "Verified Systems Runtime & Unboxed C-ABI Kernel in Pure Lean 4 (0 import Lean, 0 sorryAx)";
    mainProgram = "lean-sys-core";
  };
})
