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
  ];
  axiomCheckDecls = [
    "OmarchnixGate.SimdRef.eor3_zero_right"
    "OmarchnixGate.Kernel.admitReceiptKernel_iff"
    "OmarchnixGate.Spec.admitReceipt_iff"
    "OmarchnixGate.Spec.admitReceipt_eq_kernel"
    "OmarchnixGate.Spec.receiptAdmissionMetaSpec"
  ];
  specAuditFiles = [
    "OmarchnixGate/Kernel.lean"
    "OmarchnixGate/Spec.lean"
  ];
  selfTestArgs = [ "self-test" ];
  meta = {
    description = "Formally verified Omarchnix Schema v2 store receipt admission gate (0 sorryAx, LeanNative SIMD, lean-sys zero-copy JSON tape)";
    mainProgram = "omarchnix-receipt-gate";
  };
}
