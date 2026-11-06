import OmarchnixGate.Spec
import OmarchnixGate.Kernel

open LeanSys.Posix
open LeanSys.Codec
open LeanSys.Hash

namespace OmarchnixGate.Main

structure CliOpts where
  receiptPath : String := ""
  actualBinaryBlake3 : Option String := none
  cryptoSigOk : Bool := false
  wantJson : Bool := false

def parseCheckReceiptArgs : List String → Except String CliOpts
  | [] => .ok {}
  | "--receipt" :: p :: rest => do
      let o ← parseCheckReceiptArgs rest
      return { o with receiptPath := p }
  | "--actual-binary-blake3" :: h :: rest => do
      let o ← parseCheckReceiptArgs rest
      return { o with actualBinaryBlake3 := some h }
  | "--crypto-sig-ok" :: "1" :: rest => do
      let o ← parseCheckReceiptArgs rest
      return { o with cryptoSigOk := true }
  | "--crypto-sig-ok" :: "0" :: rest => do
      let o ← parseCheckReceiptArgs rest
      return { o with cryptoSigOk := false }
  | "--json" :: rest => do
      let o ← parseCheckReceiptArgs rest
      return { o with wantJson := true }
  | flag :: _ => .error s!"unknown argument: {flag}"

def escapeJson (s : String) : String :=
  s.foldl (fun acc c =>
    if c == '"' then acc ++ "\\\""
    else if c == '\\' then acc ++ "\\\\"
    else if c == '\n' then acc ++ "\\n"
    else acc.push c) ""

def hasUniqueKey (tape : JsonTape) (key : String) : Bool := Id.run do
  let kb := key.toUTF8
  let ba := tape.root.ba
  let mut count : Nat := 0
  for e in tape.entries do
    if JsonTape.sliceEqBytes ba e.keyOff e.keyLen kb then
      count := count + 1
  return count == 1

def lookupUniqueString? (tape : JsonTape) (key : String) : Option String := do
  if !hasUniqueKey tape key then none
  let (_, isStr) ← JsonTape.lookupSlice? tape key
  if !isStr then none
  JsonTape.lookupString? tape key

def lookupUniqueNat? (tape : JsonTape) (key : String) : Option Nat := do
  if !hasUniqueKey tape key then none
  let (_, isStr) ← JsonTape.lookupSlice? tape key
  if isStr then none
  JsonTape.lookupNat? tape key

def lookupUniqueBool? (tape : JsonTape) (key : String) : Option Bool := do
  if !hasUniqueKey tape key then none
  let (_, isStr) ← JsonTape.lookupSlice? tape key
  if isStr then none
  JsonTape.lookupBool? tape key

def lookupUniqueObjectTape? (tape : JsonTape) (key : String) : Option JsonTape := do
  if !hasUniqueKey tape key then none
  let (sub, isStr) ← JsonTape.lookupSlice? tape key
  if isStr || sub.len < 2 || sub.off >= sub.ba.size then none
  if sub.ba.get! sub.off != 123 then none
  some (JsonTape.indexJsonObject sub)

def runCheckReceipt (args : List String) : IO UInt32 := do
  match parseCheckReceiptArgs args with
  | .error e =>
    IO.eprintln s!"omarchnix-receipt-gate: {e}"
    return 2
  | .ok opts =>
    if opts.receiptPath.isEmpty then
      IO.eprintln "omarchnix-receipt-gate: --receipt <file> is required"
      return 2
    let bytes ← IO.FS.readBinFile opts.receiptPath
    let slice := ByteSlice.ofByteArray bytes
    let tape := JsonTape.indexJsonObject slice
    let schemaVer := (lookupUniqueNat? tape "schema_version").getD 0
    let mode := (lookupUniqueString? tape "mode").getD ""
    let forbiddenCount := (lookupUniqueNat? tape "forbidden_constructs_found").getD 1
    let zeroSorryField := (lookupUniqueBool? tape "zero_sorry").getD (forbiddenCount == 0)
    let zeroNativeDecide := (lookupUniqueBool? tape "zero_native_decide").getD (forbiddenCount == 0)
    let sorryAxCount := (lookupUniqueNat? tape "sorry_ax_count").getD 0
    let codegenBackend := (lookupUniqueString? tape "codegen_backend").getD "LeanNative"
    let receiptBlake3 := (lookupUniqueString? tape "receipt_blake3").getD ""
    let interfaceHash := (lookupUniqueString? tape "interface_hash").getD ""
    let sigAlg := (lookupUniqueString? tape "signature_alg").getD ""
    let ed25519Pub := (lookupUniqueString? tape "ed25519_pubkey").getD ""
    let ed25519Sig := (lookupUniqueString? tape "ed25519_signature").getD ""
    let recordedBinBlake3 := (lookupUniqueString? tape "binary_blake3").getD ""
    let archiveBlake3 := (lookupUniqueString? tape "lean_native_archive_blake3").getD ""
    let perFileTape? := lookupUniqueObjectTape? tape "per_file_interfaces"

    let schemaV2 :=
      schemaVer == 2 &&
      mode == "trusted" &&
      OmarchnixGate.Spec.isLowerHex64 receiptBlake3 &&
      OmarchnixGate.Spec.isLowerHex64 interfaceHash

    let zeroSorryAx := zeroSorryField && forbiddenCount == 0 && sorryAxCount == 0
    let zeroForbidden := zeroNativeDecide && forbiddenCount == 0 && codegenBackend == "LeanNative"
    let sigVerified :=
      opts.cryptoSigOk &&
      sigAlg == "ed25519-v1" &&
      OmarchnixGate.Spec.isLowerHex64 ed25519Pub &&
      ed25519Sig.length == 128

    let hasSignedInterfaceKey (key : String) : Bool :=
      match perFileTape? with
      | none => false
      | some subTape =>
          match lookupUniqueString? subTape key with
          | none => false
          | some h => OmarchnixGate.Spec.isLowerHex64 h

    let binaryBlake3Matches :=
      match opts.actualBinaryBlake3 with
      | none =>
          recordedBinBlake3.isEmpty || OmarchnixGate.Spec.isLowerHex64 recordedBinBlake3
      | some actual =>
          OmarchnixGate.Spec.isLowerHex64 actual &&
          actual == recordedBinBlake3 &&
          OmarchnixGate.Spec.isLowerHex64 archiveBlake3 &&
          hasSignedInterfaceKey s!"BuildArtifacts/BinaryBlake3_{actual}.lean" &&
          hasSignedInterfaceKey s!"BuildArtifacts/ArchiveBlake3_{archiveBlake3}.lean"

    let input : OmarchnixGate.Spec.ReceiptAdmissionInput := {
      schemaV2
      zeroSorryAx
      zeroForbidden
      sigVerified
      binaryBlake3Matches
    }
    let admittedSpec := OmarchnixGate.Spec.admitReceipt input
    let admittedKernel :=
      OmarchnixGate.Kernel.admitReceiptKernel
        (OmarchnixGate.Spec.boolToBit schemaV2)
        (OmarchnixGate.Spec.boolToBit zeroSorryAx)
        (OmarchnixGate.Spec.boolToBit zeroForbidden)
        (OmarchnixGate.Spec.boolToBit sigVerified)
        (OmarchnixGate.Spec.boolToBit binaryBlake3Matches) == 1
    let admitted := admittedSpec && admittedKernel
    let digest := xxh64Slice slice
    let mixed := OmarchnixGate.Kernel.mixReceiptWord digest schemaVer.toUInt64 bytes.size.toUInt64

    if opts.wantJson then
      let j1 := s!"\{\"admitted\":{admitted},\"schema_v2\":{schemaV2},\"zero_sorry_ax\":{zeroSorryAx},"
      let j2 := s!"\"zero_forbidden\":{zeroForbidden},\"sig_verified\":{sigVerified},\"binary_blake3_matches\":{binaryBlake3Matches},"
      let j3 := s!"\"receipt\":\"{escapeJson opts.receiptPath}\",\"receipt_blake3\":\"{escapeJson receiptBlake3}\","
      let j4 := s!"\"binary_blake3\":\"{escapeJson recordedBinBlake3}\",\"xxh64\":{digest},\"simd_mix64\":{mixed}}"
      IO.println (j1 ++ j2 ++ j3 ++ j4)
    else
      IO.println s!"admitted={admitted} receipt={opts.receiptPath} blake3={receiptBlake3}"

    return if admitted then 0 else 1

end OmarchnixGate.Main

def main (args : List String) : IO UInt32 := do
  match args with
  | ["self-test"] =>
    let okPos := OmarchnixGate.Spec.admitReceipt ⟨true, true, true, true, true⟩
    let okNeg := !(OmarchnixGate.Spec.admitReceipt ⟨true, true, true, true, false⟩)
    let kPos := OmarchnixGate.Kernel.admitReceiptKernel 1 1 1 1 1 == 1
    let kNeg := OmarchnixGate.Kernel.admitReceiptKernel 1 1 1 1 0 == 0
    let h := xxh64String "omarchnix-verified-lean-sys"
    let m := OmarchnixGate.Kernel.mixReceiptWord h 0x9e3779b97f4a7c15 0xbf58476d1ce4e5b9
    if okPos && okNeg && kPos && kNeg && h != 0 && m != h then
      IO.println s!"omarchnix-receipt-gate: self-test ok (xxh64={h}, mix64={m})"
      return 0
    else
      IO.eprintln "omarchnix-receipt-gate: self-test FAILED"
      return 1
  | "check-receipt" :: rest =>
    OmarchnixGate.Main.runCheckReceipt rest
  | ["--help"] | ["-h"] | ["help"] =>
    IO.println "Usage: omarchnix-receipt-gate <self-test | check-receipt --receipt <path> [--actual-binary-blake3 <hex64>] [--crypto-sig-ok 0|1] [--json]>"
    return 0
  | _ =>
    IO.eprintln "Usage: omarchnix-receipt-gate <self-test | check-receipt --receipt <path> [--actual-binary-blake3 <hex64>] [--crypto-sig-ok 0|1] [--json]>"
    return 2
