namespace OmarchnixGate.SimdRef

def clmul64 (a b : UInt64) : UInt64 :=
  let rec go (i : Nat) (acc : UInt64) : UInt64 :=
    if _ : i < 64 then let iu := i.toUInt64; go (i + 1) (if ((b >>> iu) &&& 1) == 1 then acc ^^^ (a <<< iu) else acc) else acc
  go 0 0

def eor3 (a b : UInt64) : UInt64 := a ^^^ (b >>> 32) ^^^ (b &&& 0xffffffff)

theorem eor3_zero_right (a : UInt64) : eor3 a 0 = a := by
  unfold eor3
  simp

def pmull64Ref (a b : UInt64) : UInt64 := clmul64 a b

def eor3Ref (a b c : UInt64) : UInt64 := a ^^^ b ^^^ c

theorem pmull64_ref_eq (a b : UInt64) : pmull64Ref a b = clmul64 a b := rfl

theorem eor3_ref_matches_scalar (a b : UInt64) :
    eor3 a b = eor3Ref a (b >>> 32) (b &&& 0xffffffff) := by
  unfold eor3 eor3Ref
  ac_rfl

end OmarchnixGate.SimdRef
