namespace OmarchnixGate.SimdRef

def clmul64 (a b : UInt64) : UInt64 :=
  let rec go (i : Nat) (acc : UInt64) : UInt64 :=
    if _ : i < 64 then let iu := i.toUInt64; go (i + 1) (if ((b >>> iu) &&& 1) == 1 then acc ^^^ (a <<< iu) else acc) else acc
  go 0 0

def eor3 (a b : UInt64) : UInt64 := a ^^^ (b >>> 32) ^^^ (b &&& 0xffffffff)

theorem eor3_zero_right (a : UInt64) : eor3 a 0 = a := by
  unfold eor3
  simp

end OmarchnixGate.SimdRef
