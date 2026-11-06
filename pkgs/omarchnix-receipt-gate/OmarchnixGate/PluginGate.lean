import LeanSys.Spec
import LeanSys.Gate

namespace OmarchnixGate.PluginGate

def isPluginIdChar (c : Char) : Bool :=
  let n := c.toNat
  (48 ≤ n && n ≤ 57) || (65 ≤ n && n ≤ 90) || (97 ≤ n && n ≤ 122) || c == '.' || c == '_' || c == '-'

def allPluginIdChars : List Char → Bool
  | [] => true
  | c :: cs => isPluginIdChar c && allPluginIdChars cs

def hasOmarchyPrefix : List Char → Bool
  | 'o' :: 'm' :: 'a' :: 'r' :: 'c' :: 'h' :: 'y' :: '.' :: _ => true
  | _ => false

def validPluginId (id : String) : Bool :=
  let cs := id.toList
  match cs with
  | [] => false
  | c :: rest =>
    let n := c.toNat
    ((48 ≤ n && n ≤ 57) || (65 ≤ n && n ≤ 90) || (97 ≤ n && n ≤ 122)) &&
      allPluginIdChars rest && !hasOmarchyPrefix cs

def segmentsClean : List Char → List Char → Bool
  | [], [] => false
  | [], ['.', '.'] => false
  | [], _ => true
  | c :: rest, cur =>
    if c.toNat == 0 then
      false
    else if c == '/' then
      if cur == ['.', '.'] then false else segmentsClean rest []
    else
      segmentsClean rest (cur ++ [c])

def safeRelativeEntrypoint (ep : String) : Bool :=
  match ep.toList with
  | [] => false
  | '/' :: _ => false
  | cs => segmentsClean cs []

def allSafeEntrypoints : List String → Bool
  | [] => true
  | ep :: rest => safeRelativeEntrypoint ep && allSafeEntrypoints rest

structure PluginAdmissionInput where
  schemaVersion : Nat
  id : String
  entrypoints : List String
  deriving Repr, DecidableEq

def admitPlugin (x : PluginAdmissionInput) : Bool :=
  x.schemaVersion == 1 && validPluginId x.id && allSafeEntrypoints x.entrypoints

theorem admitPlugin_iff (x : PluginAdmissionInput) :
    admitPlugin x = true ↔
      (x.schemaVersion = 1 ∧ validPluginId x.id = true ∧ allSafeEntrypoints x.entrypoints = true) := by
  simp [admitPlugin, Bool.and_eq_true, beq_iff_eq, and_assoc]

def SafePlugin (x : PluginAdmissionInput) : Prop :=
  x.schemaVersion = 1 ∧ validPluginId x.id = true ∧ allSafeEntrypoints x.entrypoints = true

def pluginMetaSpec : LeanSys.Contracts.MetaGateSpec PluginAdmissionInput SafePlugin where
  gate := admitPlugin
  sound x h := (admitPlugin_iff x).mp h
  complete x h := (admitPlugin_iff x).mpr h
  posWitness := { schemaVersion := 1, id := "example.plugin", entrypoints := ["qml/main.qml"] }
  negWitness := { schemaVersion := 1, id := "omarchy.bar", entrypoints := ["qml/main.qml"] }
  nonVacuous := rfl
  tight := rfl

theorem reserved_namespace_rejects (eps : List String) :
    admitPlugin { schemaVersion := 1, id := "omarchy.bar", entrypoints := eps } = false := by
  simp [admitPlugin, validPluginId, hasOmarchyPrefix]

theorem absolute_entrypoint_rejects :
    admitPlugin { schemaVersion := 1, id := "example.plugin", entrypoints := ["/etc/passwd"] } = false := rfl

theorem dotdot_entrypoint_rejects :
    admitPlugin { schemaVersion := 1, id := "example.plugin", entrypoints := ["../secret.qml"] } = false := rfl

end OmarchnixGate.PluginGate
