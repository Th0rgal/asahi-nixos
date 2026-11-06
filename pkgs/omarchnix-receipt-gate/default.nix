{
  buildVerifiedLeanSys,
}:
buildVerifiedLeanSys {
  pname = "omarchnix-receipt-gate";
  version = "0.1.0";
  src = ./.;
  exeName = "omarchnix-receipt-gate";
  leanNativePrereqTargets = [ "OmarchnixGate.SimdRef" ];
  leanNativeInput = "OmarchnixGate/Kernel.lean";
  leanNativeAnchorSymbols = [
    "l_OmarchnixGate_Kernel_admitReceiptKernel"
    "lean_native_abi_l_OmarchnixGate_Kernel_admitReceiptKernel"
    "l_OmarchnixGate_Kernel_mixReceiptWord"
    "lean_native_abi_l_OmarchnixGate_Kernel_mixReceiptWord"
  ];
  axiomCheckImports = [
    "OmarchnixGate.SimdRef"
    "OmarchnixGate.Kernel"
    "OmarchnixGate.Spec"
    "OmarchnixGate.PluginGate"
    "OmarchnixGate.SandboxGate"
  ];
  axiomCheckDecls = [
    "OmarchnixGate.SimdRef.eor3_zero_right"
    "OmarchnixGate.SimdRef.pmull64_ref_eq"
    "OmarchnixGate.SimdRef.eor3_ref_matches_scalar"
    "OmarchnixGate.Kernel.admitReceiptKernel_iff"
    "OmarchnixGate.Spec.admitReceipt_iff"
    "OmarchnixGate.Spec.admitReceipt_eq_kernel"
    "OmarchnixGate.Spec.receiptAdmissionMetaSpec"
    "OmarchnixGate.Spec.lookupDecodedEntries_missing_iff"
    "OmarchnixGate.Spec.lookupDecodedEntries_duplicate_iff"
    "OmarchnixGate.Spec.admission_requires_digest_binding"
    "OmarchnixGate.Spec.admission_requires_clean_policy"
    "OmarchnixGate.Spec.extraction_error_rejects"
    "OmarchnixGate.Spec.evaluateExtractedReceipt_admit_iff"
    "OmarchnixGate.Spec.admitDecodedReceipt_iff"
    "OmarchnixGate.Spec.receiptPolicyMetaSpec"
    "OmarchnixGate.Spec.parseCliLoop_duplicate_receipt"
    "OmarchnixGate.Spec.parseCliLoop_duplicate_actual_binary"
    "OmarchnixGate.Spec.parseCliLoop_duplicate_crypto_sig"
    "OmarchnixGate.Spec.parseCliLoop_duplicate_json"
    "OmarchnixGate.Spec.finalizeCliOpts_requires_actual_binary"
    "OmarchnixGate.PluginGate.admitPlugin_iff"
    "OmarchnixGate.PluginGate.pluginMetaSpec"
    "OmarchnixGate.PluginGate.reserved_namespace_rejects"
    "OmarchnixGate.PluginGate.absolute_entrypoint_rejects"
    "OmarchnixGate.PluginGate.dotdot_entrypoint_rejects"
    "OmarchnixGate.SandboxGate.admitSandbox_iff"
    "OmarchnixGate.SandboxGate.sandboxMetaSpec"
    "OmarchnixGate.SandboxGate.secret_mount_rejects"
    "OmarchnixGate.SandboxGate.ssh_mount_requires_capability"
    "OmarchnixGate.SandboxGate.rw_outside_workspace_rejects"
  ];
  specAuditFiles = [
    "OmarchnixGate/Kernel.lean"
    "OmarchnixGate/Spec.lean"
    "OmarchnixGate/PluginGate.lean"
    "OmarchnixGate/SandboxGate.lean"
  ];
  selfTestArgs = [ "self-test" ];
  meta = {
    description = "Omarchnix Schema v2 receipt policy and extraction gate (Lean 4 policy/extraction invariants, LeanNative kernel, lean-sys JSON tape)";
    mainProgram = "omarchnix-receipt-gate";
  };
}
