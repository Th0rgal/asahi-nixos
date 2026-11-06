import OmarchnixGate.Spec
import OmarchnixGate.Kernel
import OmarchnixGate.PluginGate
import OmarchnixGate.SandboxGate

open LeanSys.Posix
open LeanSys.Codec
open LeanSys.Hash
open OmarchnixGate.Spec
open OmarchnixGate.PluginGate
open OmarchnixGate.SandboxGate

namespace OmarchnixGate.Main

def formatCliError : CliFlagError → String
  | .missingReceipt => "--receipt <file> is required"
  | .missingActualBinaryBlake3 => "--actual-binary-blake3 <hex64> is required"
  | .missingCryptoSigOk => "--crypto-sig-ok <0|1> is required"
  | .duplicateFlag flag => s!"duplicate argument: {flag}"
  | .invalidCryptoSigVal val => s!"invalid --crypto-sig-ok value: {val} (expected 0 or 1)"
  | .missingFlagValue flag => s!"missing value for {flag}"
  | .unknownArg arg => s!"unknown argument: {arg}"

def formatExtractError : ExtractError → String
  | .missingField key => s!"missing_field:{key}"
  | .duplicateKey key => s!"duplicate_key:{key}"
  | .invalidKeyEncoding => "invalid_key_encoding"
  | .invalidStringEncoding key => s!"invalid_string_encoding:{key}"
  | .wrongFieldType key expected => s!"wrong_field_type:{key}:expected_{expected}"
  | .malformedObject context => s!"malformed_object:{context}"

def escapeJson (s : String) : String :=
  escapeJsonString s

def parseStrictNatSlice? (s : ByteSlice) : Option Nat := Id.run do
  let ba := s.ba
  let stop := Nat.min (s.off + s.len) ba.size
  if s.len == 0 || stop <= s.off then
    return none
  if s.len > 1 && byteAt ba s.off == 48 then
    return none
  let mut acc : Nat := 0
  for i in [s.off:stop] do
    let b := byteAt ba i
    if 48 ≤ b && b ≤ 57 then
      acc := acc * 10 + (b - 48).toNat
    else
      return none
  return some acc

def parseStrictBoolSlice? (s : ByteSlice) : Option Bool :=
  let ba := s.ba
  if s.off + s.len > ba.size then
    none
  else if s.len == 4 &&
      byteAt ba s.off == 116 &&
      byteAt ba (s.off + 1) == 114 &&
      byteAt ba (s.off + 2) == 117 &&
      byteAt ba (s.off + 3) == 101 then
    some true
  else if s.len == 5 &&
      byteAt ba s.off == 102 &&
      byteAt ba (s.off + 1) == 97 &&
      byteAt ba (s.off + 2) == 108 &&
      byteAt ba (s.off + 3) == 115 &&
      byteAt ba (s.off + 4) == 101 then
    some false
  else
    none

def parseStrictNullSlice (s : ByteSlice) : Bool :=
  let ba := s.ba
  s.off + s.len ≤ ba.size &&
  s.len == 4 &&
  byteAt ba s.off == 110 &&
  byteAt ba (s.off + 1) == 117 &&
  byteAt ba (s.off + 2) == 108 &&
  byteAt ba (s.off + 3) == 108

def sliceIsBracketedBy (s : ByteSlice) (openByte closeByte : UInt8) : Bool :=
  let ba := s.ba
  let limit := Nat.min (s.off + s.len) ba.size
  let p0 := JsonTape.skipWs ba s.off limit
  if p0 >= limit || byteAt ba p0 != openByte then
    false
  else
    let rec findLastNonWs (k : Nat) : Option Nat :=
      match k with
      | 0 => none
      | k' + 1 =>
        let idx := p0 + k'
        let c := byteAt ba idx
        if c == 32 || c == 9 || c == 10 || c == 13 then
          findLastNonWs k'
        else
          some idx
    match findLastNonWs (limit - p0) with
    | none => false
    | some lastIdx => lastIdx > p0 && byteAt ba lastIdx == closeByte

def validateObjectFramingCount? (s : ByteSlice) : Option Nat := Id.run do
  if !sliceIsBracketedBy s 123 125 then
    return none
  let ba := s.ba
  let limit := Nat.min (s.off + s.len) ba.size
  let pOpen := JsonTape.skipWs ba s.off limit
  let mut p := JsonTape.skipWs ba (pOpen + 1) limit
  if p < limit && byteAt ba p == 125 then
    return if JsonTape.skipWs ba (p + 1) limit == limit then some 0 else none
  let mut count : Nat := 0
  while p < limit do
    if count > 0 then
      if byteAt ba p != 44 then
        return none
      p := JsonTape.skipWs ba (p + 1) limit
    if p >= limit || byteAt ba p != 34 then
      return none
    match JsonTape.scanQuotedString ba (p + 1) limit with
    | none => return none
    | some keyEnd =>
      p := JsonTape.skipWs ba (keyEnd + 1) limit
      if p >= limit || byteAt ba p != 58 then
        return none
      p := JsonTape.skipWs ba (p + 1) limit
      if p >= limit then
        return none
      if byteAt ba p == 34 then
        match JsonTape.scanQuotedString ba (p + 1) limit with
        | none => return none
        | some valEnd =>
          p := JsonTape.skipWs ba (valEnd + 1) limit
      else
        let (valEnd, _) := JsonTape.scanRawValue ba p limit
        if valEnd <= p then
          return none
        p := JsonTape.skipWs ba valEnd limit
      count := count + 1
      if p < limit && byteAt ba p == 125 then
        return if JsonTape.skipWs ba (p + 1) limit == limit then some count else none
  return none

def indexStrictJsonObject (s : ByteSlice) (context : String) :
    Except ExtractError JsonTape :=
  match validateObjectFramingCount? s with
  | none => .error (.malformedObject context)
  | some expectedCount =>
    let tape := JsonTape.indexJsonObject s
    if tape.entries.size == expectedCount then .ok tape
    else .error (.malformedObject context)

def decodeFlatStringObject (s : ByteSlice) (context : String) :
    Except ExtractError (List (String × JsonFieldVal)) := Id.run do
  let tape ←
    match indexStrictJsonObject s context with
    | .error err => return .error err
    | .ok t => pure t
  let ba := tape.root.ba
  let mut out : List (String × JsonFieldVal) := []
  for e in tape.entries do
    let keySlice : ByteSlice := { ba := ba, off := e.keyOff, len := e.keyLen }
    match unescapeJsonSlice? keySlice with
    | none => return .error .invalidKeyEncoding
    | some key =>
      if out.any (fun p => p.1 == key) then
        return .error (.duplicateKey key)
      if !e.isString then
        return .error (.wrongFieldType s!"{context}.{key}" "string")
      let valSlice : ByteSlice := { ba := ba, off := e.valOff, len := e.valLen }
      match unescapeJsonSlice? valSlice with
      | none => return .error (.invalidStringEncoding s!"{context}.{key}")
      | some strVal =>
        out := out ++ [(key, .str strVal)]
  return .ok out

def decodeReceiptRootObject (s : ByteSlice) :
    Except ExtractError (List (String × JsonFieldVal)) := Id.run do
  let tape ←
    match indexStrictJsonObject s "root" with
    | .error err => return .error err
    | .ok t => pure t
  let ba := tape.root.ba
  let mut out : List (String × JsonFieldVal) := []
  for e in tape.entries do
    let keySlice : ByteSlice := { ba := ba, off := e.keyOff, len := e.keyLen }
    match unescapeJsonSlice? keySlice with
    | none => return .error .invalidKeyEncoding
    | some key =>
      if out.any (fun p => p.1 == key) then
        return .error (.duplicateKey key)
      let valSlice : ByteSlice := { ba := ba, off := e.valOff, len := e.valLen }
      if e.isString then
        match unescapeJsonSlice? valSlice with
        | none => return .error (.invalidStringEncoding key)
        | some strVal =>
          out := out ++ [(key, .str strVal)]
      else if let some b := parseStrictBoolSlice? valSlice then
        out := out ++ [(key, .bool b)]
      else if let some n := parseStrictNatSlice? valSlice then
        out := out ++ [(key, .nat n)]
      else if parseStrictNullSlice valSlice then
        out := out ++ [(key, .other)]
      else if sliceIsBracketedBy valSlice 123 125 then
        if key == "per_file_interfaces" then
          match decodeFlatStringObject valSlice key with
          | .error err => return .error err
          | .ok subEntries =>
            out := out ++ [(key, .obj subEntries)]
        else
          if (validateObjectFramingCount? valSlice).isNone then
            return .error (.malformedObject key)
          out := out ++ [(key, .other)]
      else if sliceIsBracketedBy valSlice 91 93 then
        out := out ++ [(key, .other)]
      else
        return .error (.malformedObject key)
  return .ok out

def emitGateResult (opts : ValidatedCliOpts) (input : ReceiptAdmissionInput)
    (admitted : Bool) (receiptBlake3 recordedBinBlake3 : String)
    (digest mixed : UInt64) (extractError? : Option String) : IO Unit := do
  if opts.wantJson then
    let errField :=
      match extractError? with
      | none => ""
      | some msg => s!",\"error\":\"{escapeJson msg}\""
    let j1 := s!"\{\"admitted\":{admitted},\"schema_v2\":{input.schemaV2},\"zero_sorry_ax\":{input.zeroSorryAx},"
    let j2 := s!"\"zero_forbidden\":{input.zeroForbidden},\"sig_verified\":{input.sigVerified},\"binary_blake3_matches\":{input.binaryBlake3Matches},"
    let j3 := s!"\"receipt\":\"{escapeJson opts.receiptPath}\",\"receipt_blake3\":\"{escapeJson receiptBlake3}\","
    let j4 := s!"\"binary_blake3\":\"{escapeJson recordedBinBlake3}\",\"xxh64\":{digest},\"simd_mix64\":{mixed}{errField}}"
    IO.println (j1 ++ j2 ++ j3 ++ j4)
  else
    match extractError? with
    | none =>
      IO.println s!"admitted={admitted} receipt={opts.receiptPath} blake3={receiptBlake3}"
    | some msg =>
      IO.println s!"admitted=false receipt={opts.receiptPath} error={msg}"

def splitComma (s : String) : List String :=
  (s.splitOn ",").filter (fun p => !p.isEmpty)

def parsePluginArgs : List String → Except String PluginAdmissionInput
  | ["--schema", schema, "--id", id, "--entrypoints", eps] =>
    match schema.toNat? with
    | none => .error "invalid --schema"
    | some n => .ok { schemaVersion := n, id := id, entrypoints := splitComma eps }
  | _ => .error "usage: check-plugin --schema <n> --id <id> --entrypoints <a,b>"

def parseMountToken (tok : String) : Except String MountSpec :=
  match tok.splitOn ":" with
  | [src, "ro"] => .ok { source := src, mode := .ro }
  | [src, "rw"] => .ok { source := src, mode := .rw }
  | _ => .error s!"invalid mount token: {tok}"

def parseSandboxArgs : List String → Except String SandboxAdmissionInput
  | ["--backend", backend, "--roots", roots, "--mounts", mounts, "--allow", allow] => do
    let mut specs : List MountSpec := []
    for tok in splitComma mounts do
      specs := specs ++ [← parseMountToken tok]
    let caps := splitComma allow
    return {
      backend := backend
      workspaceRoots := splitComma roots
      mounts := specs
      allowSsh := caps.any (· == "ssh")
      allowSecrets := caps.any (· == "secrets")
      allowShadow := caps.any (· == "shadow")
      allowNixDaemon := caps.any (· == "nix-daemon")
    }
  | _ => .error "usage: check-sandbox --backend <bwrap|nixos-container> --roots <a,b> --mounts <src:ro,src:rw> --allow <none|ssh,secrets,shadow,nix-daemon>"

def runCheckReceipt (args : List String) : IO UInt32 := do
  match parseCheckReceiptCli args with
  | .error e =>
    IO.eprintln s!"omarchnix-receipt-gate: {formatCliError e}"
    return 2
  | .ok opts =>
    let bytes ← IO.FS.readBinFile opts.receiptPath
    let slice := ByteSlice.ofByteArray bytes
    let digest := xxh64Slice slice
    match decodeReceiptRootObject slice >>= extractReceiptFields with
    | .error err =>
      let rejected : ReceiptAdmissionInput := {
        schemaV2 := false
        zeroSorryAx := false
        zeroForbidden := false
        sigVerified := false
        binaryBlake3Matches := false
      }
      let mixed := OmarchnixGate.Kernel.mixReceiptWord digest 0 bytes.size.toUInt64
      let msg := formatExtractError err
      IO.eprintln s!"omarchnix-receipt-gate: receipt extraction failed: {msg}"
      emitGateResult opts rejected false "" "" digest mixed (some msg)
      return 1
    | .ok extracted =>
      let input := evaluateExtractedReceipt extracted opts.actualBinaryBlake3 opts.cryptoSigOk
      let admittedSpec := OmarchnixGate.Spec.admitReceipt input
      let admittedKernel :=
        OmarchnixGate.Kernel.admitReceiptKernel
          (OmarchnixGate.Spec.boolToBit input.schemaV2)
          (OmarchnixGate.Spec.boolToBit input.zeroSorryAx)
          (OmarchnixGate.Spec.boolToBit input.zeroForbidden)
          (OmarchnixGate.Spec.boolToBit input.sigVerified)
          (OmarchnixGate.Spec.boolToBit input.binaryBlake3Matches) == 1
      let admitted := admittedSpec && admittedKernel
      let mixed := OmarchnixGate.Kernel.mixReceiptWord digest extracted.schemaVersion.toUInt64 bytes.size.toUInt64
      emitGateResult opts input admitted extracted.receiptBlake3 extracted.binaryBlake3 digest mixed none
      return if admitted then 0 else 1

def runCheckPlugin (args : List String) : IO UInt32 := do
  match parsePluginArgs args with
  | .error e =>
    IO.eprintln s!"omarchnix-receipt-gate: {e}"
    return 2
  | .ok input =>
    let ok := admitPlugin input
    IO.println s!"\{\"admitted\":{ok},\"id\":\"{escapeJson input.id}\"}"
    return if ok then 0 else 1

def runCheckSandbox (args : List String) : IO UInt32 := do
  match parseSandboxArgs args with
  | .error e =>
    IO.eprintln s!"omarchnix-receipt-gate: {e}"
    return 2
  | .ok input =>
    let ok := admitSandbox input
    IO.println s!"\{\"admitted\":{ok},\"backend\":\"{escapeJson input.backend}\"}"
    return if ok then 0 else 1

def runSimdDiff : IO UInt32 := do
  let vectors : List (UInt64 × UInt64 × UInt64) := [
    (0, 0, 0),
    (1, 1, 1),
    (0x9e3779b97f4a7c15, 0xbf58476d1ce4e5b9, 0x94d049bb133111eb),
    (0xffffffffffffffff, 0x8000000000000001, 0x123456789abcdef0)
  ]
  for (a, b, c) in vectors do
    let k := OmarchnixGate.Kernel.mixReceiptWord a b c
    let r := OmarchnixGate.SimdRef.eor3Ref (OmarchnixGate.SimdRef.pmull64Ref a b) (c >>> 32) (c &&& 0xffffffff)
    if k != r then
      IO.eprintln s!"simd-diff mismatch: kernel={k} ref={r}"
      return 1
  IO.println "{\"ok\":true,\"vectors\":4}"
  return 0

end OmarchnixGate.Main

def main (args : List String) : IO UInt32 := do
  match args with
  | ["self-test"] =>
    let okPos := OmarchnixGate.Spec.admitReceipt ⟨true, true, true, true, true⟩
    let okNeg := !(OmarchnixGate.Spec.admitReceipt ⟨true, true, true, true, false⟩)
    let okPolPos :=
      OmarchnixGate.Spec.admitDecodedReceipt
        OmarchnixGate.Spec.sampleValidEntries
        OmarchnixGate.Spec.sampleHex64
        true
    let okPolDup :=
      !(OmarchnixGate.Spec.admitDecodedReceipt
        (("mode", .str "untrusted") :: OmarchnixGate.Spec.sampleValidEntries)
        OmarchnixGate.Spec.sampleHex64
        true)
    let okCliDup :=
      match OmarchnixGate.Spec.parseCheckReceiptCli
        ["--receipt", "a", "--receipt", "b", "--actual-binary-blake3", OmarchnixGate.Spec.sampleHex64, "--crypto-sig-ok", "1"] with
      | .error (.duplicateFlag "--receipt") => true
      | _ => false
    let okCliMissingBin :=
      match OmarchnixGate.Spec.parseCheckReceiptCli ["--receipt", "a", "--crypto-sig-ok", "1"] with
      | .error .missingActualBinaryBlake3 => true
      | _ => false
    let okEscDup :=
      match OmarchnixGate.Main.decodeReceiptRootObject
        (ByteSlice.ofString "{\"mode\":\"trusted\",\"\\u006dode\":\"untrusted\"}") with
      | .error (.duplicateKey "mode") => true
      | _ => false
    let kPos := OmarchnixGate.Kernel.admitReceiptKernel 1 1 1 1 1 == 1
    let kNeg := OmarchnixGate.Kernel.admitReceiptKernel 1 1 1 1 0 == 0
    let h := xxh64String "omarchnix-verified-lean-sys"
    let m := OmarchnixGate.Kernel.mixReceiptWord h 0x9e3779b97f4a7c15 0xbf58476d1ce4e5b9
    if okPos && okNeg && okPolPos && okPolDup && okCliDup && okCliMissingBin && okEscDup && kPos && kNeg && h != 0 && m != h then
      IO.println s!"omarchnix-receipt-gate: self-test ok (xxh64={h}, mix64={m})"
      return 0
    else
      IO.eprintln "omarchnix-receipt-gate: self-test FAILED"
      return 1
  | "check-receipt" :: rest =>
    OmarchnixGate.Main.runCheckReceipt rest
  | "check-plugin" :: rest =>
    OmarchnixGate.Main.runCheckPlugin rest
  | "check-sandbox" :: rest =>
    OmarchnixGate.Main.runCheckSandbox rest
  | ["simd-diff"] =>
    OmarchnixGate.Main.runSimdDiff
  | ["--help"] | ["-h"] | ["help"] =>
    IO.println "Usage: omarchnix-receipt-gate <self-test | simd-diff | check-receipt ... | check-plugin ... | check-sandbox ...>"
    return 0
  | _ =>
    IO.eprintln "Usage: omarchnix-receipt-gate <self-test | simd-diff | check-receipt ... | check-plugin ... | check-sandbox ...>"
    return 2
