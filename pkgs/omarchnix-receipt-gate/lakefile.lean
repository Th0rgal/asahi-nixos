import Lake
open Lake DSL

package «omarchnix-receipt-gate» where
  version := v!"0.1.0"
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

require «lean-sys» from ".lake/packages/lean-sys"

input_dir buildArtifacts where
  path := "BuildArtifacts"
  filter := .extension "blake3"
  text := true

@[default_target]
lean_lib «OmarchnixGate» where
  globs := #[.andSubmodules `OmarchnixGate]
  needs := #[buildArtifacts]

@[default_target]
lean_exe «omarchnix-receipt-gate» where
  root := `OmarchnixGate.Main
  supportInterpreter := false
  moreLinkArgs := #[
    "-Wl,-u,lean_native_abi_l_OmarchnixGate_Kernel_admitReceiptKernel",
    "-Wl,-u,lean_native_abi_l_OmarchnixGate_Kernel_mixReceiptWord",
    ".lake/build/lib/liblean_native_kernels.a"
  ]
