# DR — decision records

Numbered, append-only. A decision is never edited after being recorded;
supersede it with a new record.

## DR-1 — NixOS over Omarchy as the end state

Date: 2026-11-05. Status: accepted.

Omarchy 4.5 ships the best out-of-the-box Apple Silicon experience
(Touch ID via Secure Enclave, external displays), but it is Arch-based
and imperative. The target machine is a daily driver; declarative,
rollback-able configuration wins over Touch ID. Omarchy remains the
fallback: its Mac installer is the known-good path if NixOS bring-up
stalls.

## DR-2 — Touch ID deferred, not blocked

Date: 2026-11-05. Status: deferred.

Touch ID on M-series requires the Omarchy kernel fork's Secure Enclave
work, not upstreamed to Asahi. Path if wanted later: package their
kernel tag as a `linux_asahi_omarchy` override on the
`nixos-apple-silicon` kernel plus the userspace helper. Requires
reverse-engineering the userspace contract; pinned to their exact
release tag.

## DR-3 — Rehearse on rented hardware before the Air

Date: 2026-11-05. Status: accepted.

Scaleway Mac mini M2 (€0.17/h, M2 chip — same chip class as the Air)
validates the parts qemu cannot: m1n1 on real BootROM, firmware
extraction from APFS, UEFI standalone install. Provider confirmed
personal-use Linux installs are acceptable; provider-side reset is the
failure recovery. The rehearsal box tests no laptop hardware (no Touch
ID, no speakers, no panel) — those gates only exist on the Air.

## DR-4 — Partition layout for the Air (1 TB)

Date: 2026-11-05. Status: accepted.

- macOS ~120 GB (kept for firmware updates and recovery; not optional)
- shared exFAT ~150 GB (transfer shelf; the only FS both OSes mount
  read-write natively; no journaling, no encryption — nothing precious
  lives here)
- rest: NixOS, LUKS2 + ext4 (software-only encryption; Apple's
  hardware-sealed FileVault keys are unavailable under Asahi)

## DR-5 — Boot chain updates stay manual

Date: 2026-11-05. Status: accepted.

`boot.loader.*` stays off in NixOS on Asahi machines. m1n1/U-Boot and
vendor firmware updates go through the documented Asahi installer steps
(`docs/runbook-scaleway.md`), not `nixos-rebuild`, to avoid a
half-updated boot chain that the OS cannot repair itself.
