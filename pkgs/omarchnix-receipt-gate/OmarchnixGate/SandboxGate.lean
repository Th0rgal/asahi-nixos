import LeanSys.Spec
import LeanSys.Gate

namespace OmarchnixGate.SandboxGate

inductive MountMode where
  | ro
  | rw
  deriving Repr, DecidableEq

structure MountSpec where
  source : String
  mode : MountMode
  deriving Repr, DecidableEq

structure SandboxAdmissionInput where
  backend : String
  workspaceRoots : List String
  mounts : List MountSpec
  allowSsh : Bool := false
  allowSecrets : Bool := false
  allowShadow : Bool := false
  allowNixDaemon : Bool := false
  deriving Repr, DecidableEq

def charsStartWith : List Char → List Char → Bool
  | [], _ => true
  | _ :: _, [] => false
  | p :: ps, c :: cs => p == c && charsStartWith ps cs

def isAbsoluteChars : List Char → Bool
  | '/' :: _ => true
  | _ => false

def isAbsolute (p : String) : Bool := isAbsoluteChars p.toList

def allAbsolute : List String → Bool
  | [] => true
  | r :: rs => isAbsolute r && allAbsolute rs

def hasDotDotSeg : List Char → List Char → Bool
  | [], ['.', '.'] => true
  | [], _ => false
  | '/' :: rest, cur => cur == ['.', '.'] || hasDotDotSeg rest []
  | c :: rest, cur => hasDotDotSeg rest (cur ++ [c])

def hasSshSeg : List Char → List Char → Bool
  | [], ['.', 's', 's', 'h'] => true
  | [], _ => false
  | '/' :: rest, cur => cur == ['.', 's', 's', 'h'] || hasSshSeg rest []
  | c :: rest, cur => hasSshSeg rest (cur ++ [c])

def underRootChars (root path : List Char) : Bool :=
  path == root || charsStartWith (root ++ ['/']) path

def underAnyRoot : List String → List Char → Bool
  | [], _ => false
  | r :: rs, p => underRootChars r.toList p || underAnyRoot rs p

def forbiddenPath (x : SandboxAdmissionInput) (p : List Char) : Bool :=
  (underRootChars "/run/secrets".toList p && !x.allowSecrets) ||
    (hasSshSeg p [] && !x.allowSsh) ||
    (charsStartWith "/etc/shadow".toList p && !x.allowShadow) ||
    (underRootChars "/nix/var/nix/daemon-socket".toList p && !x.allowNixDaemon)

def mountAllowed (x : SandboxAdmissionInput) (m : MountSpec) : Bool :=
  let cs := m.source.toList
  isAbsoluteChars cs && !hasDotDotSeg cs [] &&
    match m.mode with
    | .ro => !forbiddenPath x cs
    | .rw => underAnyRoot x.workspaceRoots cs && !forbiddenPath x cs

def allMountsAllowed : SandboxAdmissionInput → List MountSpec → Bool
  | _, [] => true
  | x, m :: rest => mountAllowed x m && allMountsAllowed x rest

def admitSandbox (x : SandboxAdmissionInput) : Bool :=
  (x.backend == "bwrap" || x.backend == "nixos-container") &&
    allAbsolute x.workspaceRoots &&
    allMountsAllowed x x.mounts

theorem admitSandbox_iff (x : SandboxAdmissionInput) :
    admitSandbox x = true ↔
      ((x.backend = "bwrap" ∨ x.backend = "nixos-container") ∧
        allAbsolute x.workspaceRoots = true ∧
        allMountsAllowed x x.mounts = true) := by
  simp [admitSandbox, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq, and_assoc]

def SafeSandbox (x : SandboxAdmissionInput) : Prop :=
  (x.backend = "bwrap" ∨ x.backend = "nixos-container") ∧
    allAbsolute x.workspaceRoots = true ∧
    allMountsAllowed x x.mounts = true

def sandboxMetaSpec : LeanSys.Contracts.MetaGateSpec SandboxAdmissionInput SafeSandbox where
  gate := admitSandbox
  sound x h := (admitSandbox_iff x).mp h
  complete x h := (admitSandbox_iff x).mpr h
  posWitness := {
    backend := "bwrap"
    workspaceRoots := ["/workspace"]
    mounts := [{ source := "/workspace/src", mode := .rw }]
  }
  negWitness := {
    backend := "bwrap"
    workspaceRoots := ["/workspace"]
    mounts := [{ source := "/root/.ssh", mode := .ro }]
  }
  nonVacuous := rfl
  tight := rfl

theorem secret_mount_rejects :
    admitSandbox {
      backend := "nixos-container"
      workspaceRoots := ["/workspace"]
      mounts := [{ source := "/run/secrets/age", mode := .ro }]
    } = false := rfl

theorem ssh_mount_requires_capability :
    admitSandbox {
      backend := "bwrap"
      workspaceRoots := ["/workspace"]
      mounts := [{ source := "/home/thomas/.ssh", mode := .ro }]
      allowSsh := true
    } = true := rfl

theorem rw_outside_workspace_rejects :
    admitSandbox {
      backend := "bwrap"
      workspaceRoots := ["/workspace"]
      mounts := [{ source := "/etc/hosts", mode := .rw }]
    } = false := rfl

end OmarchnixGate.SandboxGate
