import OmarchnixGate.SimdRef

namespace OmarchnixGate.Kernel

@[inline]
def admitReceiptKernel (schemaV2 zeroSorryAx zeroForbidden sigVerified binaryBlake3Matches : UInt8) : UInt8 :=
  if schemaV2 == 1 && zeroSorryAx == 1 && zeroForbidden == 1 && sigVerified == 1 && binaryBlake3Matches == 1 then 1 else 0

@[inline]
def mixReceiptWord (a b c : UInt64) : UInt64 :=
  OmarchnixGate.SimdRef.eor3 (OmarchnixGate.SimdRef.clmul64 a b) c

theorem admitReceiptKernel_iff (s2 zs zf sv bm : UInt8) :
    admitReceiptKernel s2 zs zf sv bm = 1 ↔
      (s2 == 1 ∧ zs == 1 ∧ zf == 1 ∧ sv == 1 ∧ bm == 1) := by
  unfold admitReceiptKernel
  split <;> simp_all [Bool.and_eq_true, and_assoc]

end OmarchnixGate.Kernel
