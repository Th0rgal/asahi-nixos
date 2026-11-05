# Implementation plan — agent brief (opencode)

You are implementing the next phase of `asahi-nixos`: turning the
bootstrapped flake into the actual target system — a Hyprland desktop,
hardened, declaratively partitioned, container-isolated dev machine,
with CI-verifiable security invariants. Work happens in THIS repo,
on branch `main` via short-lived feature branches (one owner each,
no rebase, no force-push, ever).

## Ground rules (non-negotiable)

1. **Every claim is backed by execution.** A phase is done when its
   gate log exists in `docs/logs/` with real command output. CI green
   on `main` is the minimum bar for every merge.
2. **Nothing manual on real hardware.** Every operation on the
   Scaleway box or the Air follows a runbook file; if a step isn't
   written down, stop and write it first.
3. **No secrets in the repo.** Keys go through sops-nix (DR-6 below);
   files stay encrypted at rest, decrypted only at eval/build time on
   machines that hold the age key. Never commit a plaintext key, token,
   password, or private IP+credential pair.
4. **Never modify the boot chain from NixOS config** (DR-5):
   `boot.loader.*` stays off for Asahi hosts.
5. **Pinned world.** All new inputs (`home-manager`, `disko`, `sops-nix`)
   follow nixpkgs. Upgrades are single-purpose commits with the lockfile
   diff in the message.
6. Match the existing style: hosts in `hosts/`, shared logic in
   modules, no generated files that git can't diff.

## Phase 0 — request access immediately (do this first, in parallel)

Send the owner this exact list and block on it:

- **BOAT_API_KEY** access (or a provisioned boat.dev aarch64 VM,
  ≥8 GB, Ubuntu/nixos-infectable) — needed for Phase 1/2 build+test.
  If x86_64 only: acceptable, QEMU TCG emulation is slow but workable;
  note the slowdown in the gate log.
- **Scaleway**: owner provisions the Mac mini M2 (M2-M, PAR zones,
  hourly) OR grants console access. Do not create it yourself without
  explicit go — it is billable spend. When granted: enable remote
  screen (VNC), record IP in `secrets/` (sops), never in git.
- An **age keypair** for sops-nix: generate (`age-keygen`), give the
  public key to the owner, store the private key only on the owner's
  machines and the CI-eligible builder. This is the repo's secret root.
- A throwaway **SSH keypair** for the rehearsal box.

While waiting, Phases 1–2 are fully doable locally / on GitHub CI.

## Phase 1 — declarative disk + hardening + containers (no hardware needed)

- [ ] Add `disko` input. Write `modules/disko-m2air.nix` implementing
      DR-4 exactly: ESP (asahi layout), LUKS2 `cryptroot` + ext4,
      `shared` exFAT. A `disko --mode destroy,format,mount` dry-run
      must validate the config (`disko-declare` check in CI).
- [ ] `modules/hardening.nix`: default-deny firewall with explicit
      exceptions table at the top; AppArmor enable + profiles for the
      exposed daemons; `security.sudo.execWheelOnly`; ssh keys-only
      (already true — keep it asserted); kernel hardening options that
      the asahi kernel actually supports (check `boot.kernelSysctl`
      acceptance; do not break GPU/suspend).
- [ ] `modules/containers.nix`: one exemplar declarative nixos-container
      (`dev-untrusted`) with its own NixOS config: no network by
      default except explicit forward, uid-shifted bind mount of a
      workdir, its own pinned nixpkgs for toolchains. This is the
      Qubes-inspired pattern (KVM is unavailable on Asahi — DR-7).
- [ ] `tests/security.nix`: a NixOS VM test asserting the invariants:
      firewall default-deny, no password SSH, LUKS device present in
      initrd, container starts and cannot reach the host network.
      Wire into `checks` so CI runs it. Gate G7 = CI green + test log.

## Phase 2 — Hyprland desktop via home-manager (no hardware needed)

- [ ] Add `home-manager` input (follows nixpkgs).
- [ ] `home/` module set, imported for `m2air` only (VM/rehearsal stay
      headless): Hyprland with ALL config through
      `wayland.windowManager.hyprland.settings` (no raw hyprlang files,
      `extraConfig` budget: zero lines unless documented why); foot,
      waybar, fuzzel, hyprlock/hypridle/hyprpaper.
- [ ] MacBook specifics: fr keymap, natural scrolling, tap-to-click,
      3-finger workspace swipes bound, brightness/media keys,
      special-workspace scratchpad terminal. Variable font/theme from
      one Nix attrset so theming is a single point of change.
- [ ] Track upstream Hyprland-breaking-change risk by pinning via the
      flake's nixpkgs only (no unstable overlays for Hyprland).
      Gate G8 = `m2air` evaluates with home-manager + a screenshot
      placeholder test (VM boot with Hyprland is a G3-class artifact:
      log the `nix build` of the toplevel on the boat VM).

## Phase 3 — VM bring-up on boat.dev (needs Phase 0 keys)

- [ ] Install Nix on the boat VM (or nixos-infect; prefer installing
      Nix standalone — infect is destructive and against the rules
      unless the owner pre-approves wiping).
- [ ] `nix build .#nixosConfigurations.vm.config.system.build.vm` and
      boot it; then build `m2air`'s toplevel (cross/emu as needed).
      Gate G3 log: build times, boot log, `nix fmt && git diff clean`.
- [ ] Use this VM as the standing builder for G7/G8 artifacts.

## Phase 4 — rehearsal on Scaleway (needs Phase 0 keys + owner GO)

- [ ] Follow `docs/runbook-scaleway.md` verbatim. Any deviation gets
      written into the runbook as a proposed edit BEFORE executing.
- [ ] Gates G4/G5 with logs. Budget: stop after 3 days of rental or
      €25, whichever first, and report.
- [ ] Teardown immediately after G5 (delete server + throwaway key).

## Phase 5 — the Air (owner-executed)

- [ ] Produce a final printed-runbook version of `docs/install-m2air.md`
      updated with everything rehearsal taught you. The owner runs it;
      you stay on standby. G6 log from the owner's session.

## Definition of done (for the whole engagement)

CI on `main`: evaluate + format + installer-iso + `checks` (VM tests)
all green; `docs/logs/` holds G1–G8 with artifacts; no secrets in git
history (`git log -p | grep -i` sweep for key material documented as
run); status matrix in README fully updated.

## Failure protocol

Blocked on access → say exactly which Phase-0 item, keep working on
the highest phase that isn't blocked, and note the block in the gate
log. Something breaks on real hardware → stop, preserve state, write
down the exact failing condition, escalate. Never improvise a recovery
on the rehearsal box or the Air.
