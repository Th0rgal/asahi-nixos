import LeanSys.Spec
import LeanSys.Gate
import LeanSys.Hash
import LeanSys.Codec
import LeanSys.Posix
import OmarchnixGate.Kernel

namespace OmarchnixGate.Spec

structure ReceiptAdmissionInput where
  schemaV2 : Bool
  zeroSorryAx : Bool
  zeroForbidden : Bool
  sigVerified : Bool
  binaryBlake3Matches : Bool
  deriving Repr, DecidableEq

@[inline]
def admitReceipt (x : ReceiptAdmissionInput) : Bool :=
  x.schemaV2 && x.zeroSorryAx && x.zeroForbidden && x.sigVerified && x.binaryBlake3Matches

@[inline]
def boolToBit (b : Bool) : UInt8 :=
  if b then 1 else 0

theorem admitReceipt_iff (x : ReceiptAdmissionInput) :
    admitReceipt x = true ↔
      (x.schemaV2 = true ∧ x.zeroSorryAx = true ∧ x.zeroForbidden = true ∧
       x.sigVerified = true ∧ x.binaryBlake3Matches = true) := by
  unfold admitReceipt
  simp [Bool.and_eq_true, and_assoc]

theorem admitReceipt_eq_kernel (x : ReceiptAdmissionInput) :
    (OmarchnixGate.Kernel.admitReceiptKernel
      (boolToBit x.schemaV2)
      (boolToBit x.zeroSorryAx)
      (boolToBit x.zeroForbidden)
      (boolToBit x.sigVerified)
      (boolToBit x.binaryBlake3Matches) == 1) = admitReceipt x := by
  cases x with
  | mk s2 zs zf sv bm =>
    cases s2 <;> cases zs <;> cases zf <;> cases sv <;> cases bm <;> rfl

def receiptAdmissionMetaSpec : LeanSys.Contracts.MetaGateSpec ReceiptAdmissionInput
    (fun x =>
      x.schemaV2 = true ∧ x.zeroSorryAx = true ∧ x.zeroForbidden = true ∧
      x.sigVerified = true ∧ x.binaryBlake3Matches = true) where
  gate := admitReceipt
  sound x h := (admitReceipt_iff x).mp h
  complete x h := (admitReceipt_iff x).mpr h
  posWitness := ⟨true, true, true, true, true⟩
  negWitness := ⟨true, true, true, true, false⟩
  nonVacuous := rfl
  tight := rfl

def isLowerHex64 (s : String) : Bool :=
  s.length == 64 && s.all (fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f'))

end OmarchnixGate.Spec
