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
def boolToBit (b : Bool) : UInt8 := if b then 1 else 0

theorem admitReceipt_iff (x : ReceiptAdmissionInput) :
    admitReceipt x = true ↔
      (x.schemaV2 = true ∧ x.zeroSorryAx = true ∧ x.zeroForbidden = true ∧
       x.sigVerified = true ∧ x.binaryBlake3Matches = true) := by
  simp [admitReceipt, Bool.and_eq_true, and_assoc]

theorem admitReceipt_eq_kernel (x : ReceiptAdmissionInput) :
    (OmarchnixGate.Kernel.admitReceiptKernel
      (boolToBit x.schemaV2) (boolToBit x.zeroSorryAx) (boolToBit x.zeroForbidden)
      (boolToBit x.sigVerified) (boolToBit x.binaryBlake3Matches) == 1) = admitReceipt x := by
  cases x with
  | mk s z f v b =>
    cases s
    · rfl
    · cases z
      · rfl
      · cases f
        · rfl
        · cases v
          · rfl
          · cases b
            · rfl
            · rfl

def receiptAdmissionMetaSpec : LeanSys.Contracts.MetaGateSpec ReceiptAdmissionInput
    (fun x => x.schemaV2 = true ∧ x.zeroSorryAx = true ∧ x.zeroForbidden = true ∧
      x.sigVerified = true ∧ x.binaryBlake3Matches = true) where
  gate := admitReceipt
  sound x h := (admitReceipt_iff x).mp h
  complete x h := (admitReceipt_iff x).mpr h
  posWitness := ⟨true, true, true, true, true⟩
  negWitness := ⟨true, true, true, true, false⟩
  nonVacuous := rfl
  tight := rfl

def isLowerHexChar (c : Char) : Bool :=
  let n := c.toNat
  (48 ≤ n && n ≤ 57) || (97 ≤ n && n ≤ 102)

def isLowerHexChars : List Char → Bool
  | [] => true
  | c :: cs => isLowerHexChar c && isLowerHexChars cs

def isLowerHex64 (s : String) : Bool :=
  let cs := s.toList
  cs.length == 64 && isLowerHexChars cs

def isLowerHex128 (s : String) : Bool :=
  let cs := s.toList
  cs.length == 128 && isLowerHexChars cs

inductive JsonFieldVal where
  | str (v : String)
  | nat (v : Nat)
  | bool (v : Bool)
  | obj (entries : List (String × JsonFieldVal))
  | other
  deriving Repr

inductive ExtractError where
  | missingField (key : String)
  | duplicateKey (key : String)
  | invalidKeyEncoding
  | invalidStringEncoding (key : String)
  | wrongFieldType (key : String) (expected : String)
  | malformedObject (context : String)
  deriving Repr, DecidableEq

def lookupDecodedEntries (entries : List (String × JsonFieldVal)) (key : String) :
    Except ExtractError JsonFieldVal :=
  match entries.filter (fun p => p.1 == key) with
  | [] => .error (.missingField key)
  | [(_, v)] => .ok v
  | _ => .error (.duplicateKey key)

def requireStringField (entries : List (String × JsonFieldVal)) (key : String) :
    Except ExtractError String := do
  match ← lookupDecodedEntries entries key with
  | .str s => return s
  | _ => .error (.wrongFieldType key "string")

def requireNatField (entries : List (String × JsonFieldVal)) (key : String) :
    Except ExtractError Nat := do
  match ← lookupDecodedEntries entries key with
  | .nat n => return n
  | _ => .error (.wrongFieldType key "nat")

def requireBoolField (entries : List (String × JsonFieldVal)) (key : String) :
    Except ExtractError Bool := do
  match ← lookupDecodedEntries entries key with
  | .bool b => return b
  | _ => .error (.wrongFieldType key "bool")

def requireObjectField (entries : List (String × JsonFieldVal)) (key : String) :
    Except ExtractError (List (String × JsonFieldVal)) := do
  match ← lookupDecodedEntries entries key with
  | .obj sub => return sub
  | _ => .error (.wrongFieldType key "object")

structure ExtractedReceipt where
  schemaVersion : Nat
  mode : String
  forbiddenConstructsFound : Nat
  zeroSorry : Bool
  zeroNativeDecide : Bool
  sorryAxCount : Nat
  codegenBackend : String
  receiptBlake3 : String
  interfaceHash : String
  signatureAlg : String
  ed25519Pubkey : String
  ed25519Signature : String
  binaryBlake3 : String
  leanNativeArchiveBlake3 : String
  perFileInterfaces : List (String × JsonFieldVal)
  deriving Repr

def extractReceiptFields (entries : List (String × JsonFieldVal)) :
    Except ExtractError ExtractedReceipt := do
  let schemaVersion ← requireNatField entries "schema_version"
  let mode ← requireStringField entries "mode"
  let forbiddenConstructsFound ← requireNatField entries "forbidden_constructs_found"
  let zeroSorry ← requireBoolField entries "zero_sorry"
  let zeroNativeDecide ← requireBoolField entries "zero_native_decide"
  let sorryAxCount ← requireNatField entries "sorry_ax_count"
  let codegenBackend ← requireStringField entries "codegen_backend"
  let receiptBlake3 ← requireStringField entries "receipt_blake3"
  let interfaceHash ← requireStringField entries "interface_hash"
  let signatureAlg ← requireStringField entries "signature_alg"
  let ed25519Pubkey ← requireStringField entries "ed25519_pubkey"
  let ed25519Signature ← requireStringField entries "ed25519_signature"
  let binaryBlake3 ← requireStringField entries "binary_blake3"
  let leanNativeArchiveBlake3 ← requireStringField entries "lean_native_archive_blake3"
  let perFileInterfaces ← requireObjectField entries "per_file_interfaces"
  return {
    schemaVersion := schemaVersion
    mode := mode
    forbiddenConstructsFound := forbiddenConstructsFound
    zeroSorry := zeroSorry
    zeroNativeDecide := zeroNativeDecide
    sorryAxCount := sorryAxCount
    codegenBackend := codegenBackend
    receiptBlake3 := receiptBlake3
    interfaceHash := interfaceHash
    signatureAlg := signatureAlg
    ed25519Pubkey := ed25519Pubkey
    ed25519Signature := ed25519Signature
    binaryBlake3 := binaryBlake3
    leanNativeArchiveBlake3 := leanNativeArchiveBlake3
    perFileInterfaces := perFileInterfaces
  }

def binaryInterfaceKey (h : String) : String := "BuildArtifacts/BinaryBlake3_" ++ h ++ ".lean"
def archiveInterfaceKey (h : String) : String := "BuildArtifacts/ArchiveBlake3_" ++ h ++ ".lean"

def hasSignedInterfaceDigest (entries : List (String × JsonFieldVal)) (key : String) : Bool :=
  match requireStringField entries key with
  | .ok digest => isLowerHex64 digest
  | .error _ => false

def evaluateExtractedReceipt (r : ExtractedReceipt) (actual : String)
    (cryptoSigOk : Bool) : ReceiptAdmissionInput := {
  schemaV2 := r.schemaVersion == 2 && r.mode == "trusted" &&
    isLowerHex64 r.receiptBlake3 && isLowerHex64 r.interfaceHash
  zeroSorryAx := r.zeroSorry && r.forbiddenConstructsFound == 0 && r.sorryAxCount == 0
  zeroForbidden := r.zeroNativeDecide && r.forbiddenConstructsFound == 0 && r.codegenBackend == "LeanNative"
  sigVerified := cryptoSigOk && r.signatureAlg == "ed25519-v1" &&
    isLowerHex64 r.ed25519Pubkey && isLowerHex128 r.ed25519Signature
  binaryBlake3Matches := isLowerHex64 actual && actual == r.binaryBlake3 &&
    isLowerHex64 r.leanNativeArchiveBlake3 &&
    hasSignedInterfaceDigest r.perFileInterfaces (binaryInterfaceKey actual) &&
    hasSignedInterfaceDigest r.perFileInterfaces (archiveInterfaceKey r.leanNativeArchiveBlake3)
}

def admitDecodedReceipt (entries : List (String × JsonFieldVal)) (actual : String)
    (cryptoSigOk : Bool) : Bool :=
  match extractReceiptFields entries with
  | .error _ => false
  | .ok r => admitReceipt (evaluateExtractedReceipt r actual cryptoSigOk)

theorem lookupDecodedEntries_missing_iff (entries : List (String × JsonFieldVal)) (key : String) :
    lookupDecodedEntries entries key = .error (.missingField key) ↔
      entries.filter (fun p => p.1 == key) = [] := by
  unfold lookupDecodedEntries
  cases entries.filter (fun p => p.1 == key) with
  | nil => simp
  | cons hd tl => cases tl <;> simp

theorem lookupDecodedEntries_duplicate_iff (entries : List (String × JsonFieldVal)) (key : String) :
    lookupDecodedEntries entries key = .error (.duplicateKey key) ↔
      (entries.filter (fun p => p.1 == key)).length ≥ 2 := by
  unfold lookupDecodedEntries
  cases entries.filter (fun p => p.1 == key) with
  | nil => simp
  | cons hd tl => cases tl <;> simp

theorem admission_requires_digest_binding (r : ExtractedReceipt) (actual : String) (crypto : Bool)
    (h : admitReceipt (evaluateExtractedReceipt r actual crypto) = true) :
    isLowerHex64 actual = true ∧ actual = r.binaryBlake3 ∧
    hasSignedInterfaceDigest r.perFileInterfaces (binaryInterfaceKey actual) = true ∧
    hasSignedInterfaceDigest r.perFileInterfaces (archiveInterfaceKey r.leanNativeArchiveBlake3) = true := by
  have hb := (admitReceipt_iff _).mp h |>.2.2.2.2
  simp only [evaluateExtractedReceipt, Bool.and_eq_true, beq_iff_eq] at hb
  exact ⟨hb.1.1.1.1, hb.1.1.1.2, hb.1.2, hb.2⟩

theorem admission_requires_clean_policy (r : ExtractedReceipt) (actual : String) (crypto : Bool)
    (h : admitReceipt (evaluateExtractedReceipt r actual crypto) = true) :
    r.zeroSorry = true ∧ r.zeroNativeDecide = true ∧ r.sorryAxCount = 0 ∧
    r.forbiddenConstructsFound = 0 ∧ r.codegenBackend = "LeanNative" ∧ crypto = true := by
  have hs := (admitReceipt_iff _).mp h
  simp only [evaluateExtractedReceipt, Bool.and_eq_true, beq_iff_eq] at hs
  exact ⟨hs.2.1.1.1, hs.2.2.1.1.1, hs.2.1.2, hs.2.1.1.2,
    hs.2.2.1.2, hs.2.2.2.1.1.1.1⟩

theorem extraction_error_rejects (entries : List (String × JsonFieldVal)) (e : ExtractError)
    (actual : String) (crypto : Bool) (h : extractReceiptFields entries = .error e) :
    admitDecodedReceipt entries actual crypto = false := by
  simp [admitDecodedReceipt, h]

structure ReceiptPolicyCheckInput where
  entries : List (String × JsonFieldVal)
  actualBinaryBlake3 : String
  cryptoSigOk : Bool
  deriving Repr

def admitDecodedReceiptInput (x : ReceiptPolicyCheckInput) : Bool :=
  admitDecodedReceipt x.entries x.actualBinaryBlake3 x.cryptoSigOk

def SafeDecodedReceiptPolicy (x : ReceiptPolicyCheckInput) : Prop :=
  ∃ r : ExtractedReceipt,
    extractReceiptFields x.entries = .ok r ∧
    r.schemaVersion = 2 ∧
    r.mode = "trusted" ∧
    isLowerHex64 r.receiptBlake3 = true ∧
    isLowerHex64 r.interfaceHash = true ∧
    r.zeroSorry = true ∧
    r.zeroNativeDecide = true ∧
    r.forbiddenConstructsFound = 0 ∧
    r.sorryAxCount = 0 ∧
    r.codegenBackend = "LeanNative" ∧
    x.cryptoSigOk = true ∧
    r.signatureAlg = "ed25519-v1" ∧
    isLowerHex64 r.ed25519Pubkey = true ∧
    isLowerHex128 r.ed25519Signature = true ∧
    isLowerHex64 x.actualBinaryBlake3 = true ∧
    x.actualBinaryBlake3 = r.binaryBlake3 ∧
    isLowerHex64 r.leanNativeArchiveBlake3 = true ∧
    hasSignedInterfaceDigest r.perFileInterfaces (binaryInterfaceKey x.actualBinaryBlake3) = true ∧
    hasSignedInterfaceDigest r.perFileInterfaces (archiveInterfaceKey r.leanNativeArchiveBlake3) = true

theorem evaluateExtractedReceipt_admit_iff (r : ExtractedReceipt)
    (actual : String) (crypto : Bool) :
    admitReceipt (evaluateExtractedReceipt r actual crypto) = true ↔
      (r.schemaVersion = 2 ∧
       r.mode = "trusted" ∧
       isLowerHex64 r.receiptBlake3 = true ∧
       isLowerHex64 r.interfaceHash = true ∧
       r.zeroSorry = true ∧
       r.zeroNativeDecide = true ∧
       r.forbiddenConstructsFound = 0 ∧
       r.sorryAxCount = 0 ∧
       r.codegenBackend = "LeanNative" ∧
       crypto = true ∧
       r.signatureAlg = "ed25519-v1" ∧
       isLowerHex64 r.ed25519Pubkey = true ∧
       isLowerHex128 r.ed25519Signature = true ∧
       isLowerHex64 actual = true ∧
       actual = r.binaryBlake3 ∧
       isLowerHex64 r.leanNativeArchiveBlake3 = true ∧
       hasSignedInterfaceDigest r.perFileInterfaces (binaryInterfaceKey actual) = true ∧
       hasSignedInterfaceDigest r.perFileInterfaces (archiveInterfaceKey r.leanNativeArchiveBlake3) = true) := by
  rw [admitReceipt_iff]
  unfold evaluateExtractedReceipt
  simp only [Bool.and_eq_true, beq_iff_eq]
  constructor
  · intro h
    rcases h with ⟨⟨⟨⟨hs, hm⟩, hrb⟩, hih⟩, ⟨⟨hzs, hfc1⟩, hsa⟩, ⟨⟨hzn, _⟩, hcb⟩, ⟨⟨⟨hcs, halg⟩, hpub⟩, hsig⟩, ⟨⟨⟨⟨hact, heq⟩, harc⟩, hbi⟩, hai⟩⟩
    exact ⟨hs, hm, hrb, hih, hzs, hzn, hfc1, hsa, hcb, hcs, halg, hpub, hsig, hact, heq, harc, hbi, hai⟩
  · intro h
    rcases h with ⟨hs, hm, hrb, hih, hzs, hzn, hfc, hsa, hcb, hcs, halg, hpub, hsig, hact, heq, harc, hbi, hai⟩
    exact ⟨⟨⟨⟨hs, hm⟩, hrb⟩, hih⟩, ⟨⟨hzs, hfc⟩, hsa⟩, ⟨⟨hzn, hfc⟩, hcb⟩, ⟨⟨⟨hcs, halg⟩, hpub⟩, hsig⟩, ⟨⟨⟨⟨hact, heq⟩, harc⟩, hbi⟩, hai⟩⟩

theorem admitDecodedReceipt_iff (x : ReceiptPolicyCheckInput) :
    admitDecodedReceiptInput x = true ↔ SafeDecodedReceiptPolicy x := by
  unfold admitDecodedReceiptInput admitDecodedReceipt SafeDecodedReceiptPolicy
  cases hex : extractReceiptFields x.entries with
  | error e =>
    simp
  | ok r =>
    simp only [Except.ok.injEq, exists_eq_left']
    exact evaluateExtractedReceipt_admit_iff r x.actualBinaryBlake3 x.cryptoSigOk

def sampleHex64 : String := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
def sampleHex128 : String := sampleHex64 ++ sampleHex64

def sampleValidEntries : List (String × JsonFieldVal) := [
  ("schema_version", .nat 2), ("mode", .str "trusted"),
  ("forbidden_constructs_found", .nat 0), ("zero_sorry", .bool true),
  ("zero_native_decide", .bool true), ("sorry_ax_count", .nat 0),
  ("codegen_backend", .str "LeanNative"), ("receipt_blake3", .str sampleHex64),
  ("interface_hash", .str sampleHex64), ("signature_alg", .str "ed25519-v1"),
  ("ed25519_pubkey", .str sampleHex64), ("ed25519_signature", .str sampleHex128),
  ("binary_blake3", .str sampleHex64), ("lean_native_archive_blake3", .str sampleHex64),
  ("per_file_interfaces", .obj [(binaryInterfaceKey sampleHex64, .str sampleHex64),
    (archiveInterfaceKey sampleHex64, .str sampleHex64)])]

set_option maxRecDepth 32768 in
def receiptPolicyMetaSpec : LeanSys.Contracts.MetaGateSpec ReceiptPolicyCheckInput
    SafeDecodedReceiptPolicy where
  gate := admitDecodedReceiptInput
  sound x h := (admitDecodedReceipt_iff x).mp h
  complete x h := (admitDecodedReceipt_iff x).mpr h
  posWitness := {
    entries := sampleValidEntries
    actualBinaryBlake3 := sampleHex64
    cryptoSigOk := true
  }
  negWitness := {
    entries := ("mode", .str "untrusted") :: sampleValidEntries
    actualBinaryBlake3 := sampleHex64
    cryptoSigOk := true
  }
  nonVacuous := rfl
  tight := rfl

inductive CliFlagError where
  | missingReceipt
  | missingActualBinaryBlake3
  | missingCryptoSigOk
  | duplicateFlag (flag : String)
  | invalidCryptoSigVal (val : String)
  | missingFlagValue (flag : String)
  | unknownArg (arg : String)
  deriving Repr, DecidableEq

structure ValidatedCliOpts where
  receiptPath : String
  actualBinaryBlake3 : String
  cryptoSigOk : Bool
  wantJson : Bool
  deriving Repr

structure PartialCliOpts where
  receiptPath : Option String := none
  actualBinaryBlake3 : Option String := none
  cryptoSigOk : Option Bool := none
  seenJson : Bool := false
  deriving Repr

def parseCliLoop : List String → PartialCliOpts → Except CliFlagError PartialCliOpts
  | [], acc => .ok acc
  | ["--receipt"], _ => .error (.missingFlagValue "--receipt")
  | "--receipt" :: p :: rest, acc =>
    if acc.receiptPath.isSome then .error (.duplicateFlag "--receipt")
    else if p.isEmpty then .error (.missingFlagValue "--receipt")
    else parseCliLoop rest { acc with receiptPath := some p }
  | ["--actual-binary-blake3"], _ => .error (.missingFlagValue "--actual-binary-blake3")
  | "--actual-binary-blake3" :: h :: rest, acc =>
    if acc.actualBinaryBlake3.isSome then .error (.duplicateFlag "--actual-binary-blake3")
    else if h.isEmpty then .error (.missingFlagValue "--actual-binary-blake3")
    else parseCliLoop rest { acc with actualBinaryBlake3 := some h }
  | ["--crypto-sig-ok"], _ => .error (.missingFlagValue "--crypto-sig-ok")
  | "--crypto-sig-ok" :: v :: rest, acc =>
    if acc.cryptoSigOk.isSome then .error (.duplicateFlag "--crypto-sig-ok")
    else if v == "1" then parseCliLoop rest { acc with cryptoSigOk := some true }
    else if v == "0" then parseCliLoop rest { acc with cryptoSigOk := some false }
    else .error (.invalidCryptoSigVal v)
  | "--json" :: rest, acc =>
    if acc.seenJson then .error (.duplicateFlag "--json")
    else parseCliLoop rest { acc with seenJson := true }
  | arg :: _, _ => .error (.unknownArg arg)

def finalizeCliOpts (acc : PartialCliOpts) : Except CliFlagError ValidatedCliOpts :=
  match acc.receiptPath, acc.actualBinaryBlake3, acc.cryptoSigOk with
  | none, _, _ => .error .missingReceipt
  | _, none, _ => .error .missingActualBinaryBlake3
  | _, _, none => .error .missingCryptoSigOk
  | some receiptPath, some actualBinaryBlake3, some cryptoSigOk =>
    .ok {
      receiptPath := receiptPath
      actualBinaryBlake3 := actualBinaryBlake3
      cryptoSigOk := cryptoSigOk
      wantJson := acc.seenJson
    }

def parseCheckReceiptCli (args : List String) : Except CliFlagError ValidatedCliOpts := do
  let acc ← parseCliLoop args {}
  finalizeCliOpts acc

theorem parseCliLoop_duplicate_receipt (p : String) (rest : List String)
    (acc : PartialCliOpts) (v : String) (h : acc.receiptPath = some v) :
    parseCliLoop ("--receipt" :: p :: rest) acc = .error (.duplicateFlag "--receipt") := by
  simp [parseCliLoop, h]

theorem parseCliLoop_duplicate_actual_binary (p : String) (rest : List String)
    (acc : PartialCliOpts) (v : String) (h : acc.actualBinaryBlake3 = some v) :
    parseCliLoop ("--actual-binary-blake3" :: p :: rest) acc =
      .error (.duplicateFlag "--actual-binary-blake3") := by
  simp [parseCliLoop, h]

theorem parseCliLoop_duplicate_crypto_sig (p : String) (rest : List String)
    (acc : PartialCliOpts) (v : Bool) (h : acc.cryptoSigOk = some v) :
    parseCliLoop ("--crypto-sig-ok" :: p :: rest) acc =
      .error (.duplicateFlag "--crypto-sig-ok") := by
  simp [parseCliLoop, h]

theorem parseCliLoop_duplicate_json (rest : List String)
    (acc : PartialCliOpts) (h : acc.seenJson = true) :
    parseCliLoop ("--json" :: rest) acc = .error (.duplicateFlag "--json") := by
  simp [parseCliLoop, h]

theorem finalizeCliOpts_requires_actual_binary (acc : PartialCliOpts)
    (hr : acc.receiptPath.isSome = true) (hb : acc.actualBinaryBlake3 = none) :
    finalizeCliOpts acc = .error .missingActualBinaryBlake3 := by
  cases hpath : acc.receiptPath with
  | none => simp [hpath] at hr
  | some p => simp [finalizeCliOpts, hpath, hb]

end OmarchnixGate.Spec
