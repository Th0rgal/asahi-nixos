# Gate logs

One file per gate pass, named `g<N>-<YYYY-MM-DD>.md`. A gate is passed
only when its log exists here. Logs are append-only: corrections go in
a new file, never by editing an old one.

- G1 (flake evaluates) — CI run on `main`, link the run in the log
- G2 (installer ISO builds) — CI artifact + SHA256
- G3 (VM boots shared config) — qemu invocation + boot log
- G4/G5 — rehearsal box, per `runbook-scaleway.md`
- G6 — the Air, per `install-m2air.md`
- G7 (security VM checks) — CI `checks` + `disko-declare` on `main`, plus test log and secret sweep
- G8 (Hyprland desktop) — `m2air` `home-manager` evaluation + KVM desktop screenshot artifact on `main`
