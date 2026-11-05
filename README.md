# asahi-nixos

NixOS on Apple Silicon, via Asahi Linux — for a MacBook Air M2.

Three hosts, one flake:

| Host | Machine | Purpose |
| --- | --- | --- |
| `vm` | plain aarch64 QEMU guest | Software iteration: shared config, install flow. No Asahi bits. |
| `rehearsal` | rented Mac mini M2 (Scaleway, €0.17/h) | Dress rehearsal on real BootROM, disposable, provider-side reset as the only safety net. |
| `m2air` | MacBook Air M2 | The target. Everything the rehearsal proves lands here unchanged. |

Build the installer ISO (cross-compiles on x86_64):

```console
$ nix build .#installer-bootstrap
```

## Status matrix

Every cell is backed by a recorded gate (CI run or runbook log in
`docs/logs/`). No cell is marked done without evidence.

| Gate | What proves it | Status |
| --- | --- | --- |
| G1 — flake evaluates | `nix eval` on all three hosts, in CI | pending |
| G2 — installer ISO builds | `nix build .#installer-bootstrap` in CI, artifact attached | pending |
| G3 — VM boots shared config | qemu boot log in `docs/logs/` | pending |
| G4 — Asahi bootstrap on real BootROM | runbook log from the rehearsal box | pending |
| G5 — NixOS install + rebuild on rehearsal | `nixos-rebuild switch` log on the mini | pending |
| G6 — Air install, dual-boot macOS kept | runbook log from the Air | pending |

## Method

- **Runbooks, not memory.** Every operation on real hardware is written
  down in `docs/` before it is run, and produces a log in `docs/logs/`.
- **Gates with evidence.** See the matrix above. A gate without a
  recorded artifact is not passed.
- **Pinned inputs.** `flake.lock` is committed; upgrades are deliberate
  commits, not surprises.
- **Rehearse before you cut.** Nothing reaches the Air until the same
  code passed on the rehearsal box.
- **One writer, no rebase.** Straight commits on `main`, or a branch
  with one owner. No force-push, no history rewriting.

## What is intentionally out of scope

- Touch ID (Omarchy kernel-fork work, not upstreamed to Asahi; tracked
  in `docs/decisions.md` as DR-2)
- Metal (does not exist on Linux; Mesa OpenGL/Vulkan is what Asahi ships)
- Apple's verified boot / SIP (Apple security model is replaced by the
  Asahi boot chain + LUKS)

## References

- [nix-community/nixos-apple-silicon](https://github.com/nix-community/nixos-apple-silicon) — the hardware module and installer this builds on
- [Asahi Linux](https://asahilinux.org/) — kernel, m1n1, Mesa driver
- [Omarchy](https://omarchy.org/) — the distro that started this; M1/M2 first-class
