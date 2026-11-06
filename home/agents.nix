{
  config,
  lib,
  pkgs,
  theme,
  ...
}:
let
  cfg = config.programs.omarchnix;

  skillFiles = {
    "SKILL.md" = ''
      ---
      name: omarchnix
      description: >
        Governed customization and verification skill for omarchnix — the declarative,
        proof-carrying Omarchy-compatible NixOS & Home Manager workstation stack across
        aarch64-linux (Apple Silicon Asahi, NVIDIA Grace / DGX Spark) and x86_64-linux.
        Use when changing themes, Hyprland Lua config, omarchy-shell QML/plugins, coding
        agent skins, or NixOS / Home Manager modules.
      ---

      # `omarchnix` System Skill

      `omarchnix` combines upstream [Omarchy](https://omarchy.org) themes, `quickshell` + `omarchy-shell`, and the `plugins.omarchy.org` ecosystem with pure NixOS + Home Manager declarativity and proof-carrying Lean 4 (`turbo-lean` + `lean-sys` + `LeanNative`) userspace receipts.

      ## Topic Guides

      Read the relevant guide next to this file before making changes:

      - [`nixos-declarative.md`](nixos-declarative.md) — NixOS (`omarchnix.*`) & Home Manager (`programs.omarchnix.*`) options, host profiles (`asahi`, `spark`, `workstation`, `vm`), and safe `omarchnix check` validation before `nixos-rebuild`.
      - [`themes.md`](themes.md) — Declarative `lib.omarchy.importTheme` (all 23+ bundled palettes + custom `colors.toml` directories) and instant runtime switching via `omarchnix theme set <name>`.
      - [`shell-and-plugins.md`](shell-and-plugins.md) — `omarchy-shell` QML runtime, bar layout (`~/.config/omarchy/shell.json`), declarative `programs.omarchnix.plugins.locked` (`lib.omarchy.buildPlugin`), and runtime `plugins.omarchy.org` discovery/installation.
      - [`proofs-and-audit.md`](proofs-and-audit.md) — Proof-carrying Lean 4 derivations (`pkgs.omarchnix.buildVerifiedLeanSys`) and offline BLAKE3 + Ed25519 verification with `omarchnix audit`.

      ## Golden Rules for Agents

      1. **Never edit `/nix/store` or `$OMARCHY_PATH` directly.** Read `$OMARCHY_PATH` freely (`$OMARCHY_PATH/shell`, `$OMARCHY_PATH/themes`, `$OMARCHY_PATH/default/themed`) for reference.
      2. **Respect Asahi BootROM safety (DR-5).** Never enable `boot.loader.systemd-boot`, `boot.loader.grub`, or `boot.loader.efi.canTouchEfiVariables` on `omarchnix.profile = "asahi"` hosts (`m2air`, `rehearsal`).
      3. **Validate before switching.** Run `omarchnix check` (and `nix fmt` + `nix flake check` when modifying a system flake) before running `sudo nixos-rebuild switch`.
      4. **Zero symlinks inside `~/.config/omarchy/plugins/<id>`.** Both `omarchy-plugin-validate` and `PluginRegistry.qml` reject symlinks inside plugin directories; use `lib.omarchy.buildPlugin` + `programs.omarchnix.plugins.locked` or `omarchnix plugin install <id> --yes`.
    '';

    "nixos-declarative.md" = ''
      # Declarative NixOS & Home Manager Configuration

      ## Reusable Flake Outputs

      - `nixosModules.omarchnix` (`nixosModules.default`): Cross-architecture NixOS module (`aarch64-linux` and `x86_64-linux`).
      - `homeManagerModules.omarchnix` (`homeManagerModules.default`): Home Manager desktop, theme, shell, plugin, and agent-ergonomics module.
      - `overlays.default`: Adds `pkgs.omarchnix.{omarchy-shell, cli, buildPlugin, importTheme, themes, ...}`.
      - `lib.omarchy`: Pure Nix theme importer (`importTheme`, `allBundledThemes`, `themeNames`) and plugin builder (`buildPlugin`, `validatePluginManifest`).

      ## Key Options

      ```nix
      omarchnix = {
        enable = true;
        profile = "workstation"; # "asahi" | "spark" | "workstation" | "vm"
        hardening.enable = true;
        containers.enable = true;
        desktop = {
          enable = true;
          user = "alice";
          theme = "tokyo-night";
          shellBackend = "omarchy-shell"; # or "waybar"
        };
      };
      ```

      ## Safe Rebuild Workflow

      ```bash
      omarchnix status --json
      omarchnix check --flake /path/to/flake --json
      nix fmt
      sudo nixos-rebuild test --flake /path/to/flake#<host>
      ```
    '';

    "themes.md" = ''
      # Themes & Live Switching

      `omarchnix` supports all 23+ bundled Omarchy themes (`catppuccin`, `catppuccin-latte`, `ethereal`, `everforest`, `flexoki-light`, `gruvbox`, `hackerman`, `jade-horse`, `kanagawa`, `last-horizon`, `lumon`, `lupine`, `matte-black`, `miasma`, `nord`, `retro-82`, `ristretto`, `rose-pine`, `solitude`, `starship`, `tokyo-night`, `vantablack`, `white`) plus custom `colors.toml` directories.

      ## Declarative Default Theme

      Set `omarchnix.desktop.theme = "catppuccin";` (NixOS) or `programs.omarchnix.theme.name = "catppuccin";` (Home Manager), or pass a custom directory via `lib.omarchy.importTheme { theme = ./my-theme; inherit pkgs; }`.

      ## Live Runtime Switching

      ```bash
      omarchnix theme list --json
      omarchnix theme current
      omarchnix theme palette gruvbox --json
      omarchnix theme set rose-pine
      ```

      `omarchnix theme set` renders `$OMARCHY_PATH/default/themed/*.tpl` into `~/.local/state/omarchy/current/theme/`, updates `omarchy-shell` over Unix-socket IPC, retints running `foot` terminals via OSC sequences, reloads Hyprland borders, and updates `opencode` (`SIGUSR2`), `claude` (`~/.claude/themes/omarchy.json`), and `hermes` (`~/.hermes` skin).
    '';

    "shell-and-plugins.md" = ''
      # `omarchy-shell` Runtime & `plugins.omarchy.org` Loader

      ## Shell Runtime & IPC

      - Config file: `~/.config/omarchy/shell.json` (hot-reloaded by `omarchy-shell`; must remain a regular writable file with `"version": 1`).
      - Fast IPC (`~5 ms` via `socat`):
        - `omarchy-shell shell ping`
        - `omarchy-shell shell listPlugins`
        - `omarchy-shell shell rescanPlugins`
        - `omarchnix plugin enable <id> --section right`
        - `omarchnix plugin disable <id>`

      ## Declarative Nix-Locked Plugins

      ```nix
      programs.omarchnix.plugins.locked."dizziee.opencode-model-usage" = {
        package = inputs.omarchnix.lib.omarchy.buildPlugin {
          inherit pkgs;
          src = opencodeModelUsageSrc;
        };
        enable = true;
        section = "right";
      };
      ```

      `lib.omarchy.buildPlugin` enforces `schemaVersion == 1`, rejects reserved `omarchy.*` IDs, verifies relative entryPoints exist, and rejects symlinks at Nix build time. Home Manager copies locked plugins as real files into `~/.config/omarchy/plugins/<id>`.

      ## Runtime Marketplace Discovery (`plugins.omarchy.org`)

      ```bash
      omarchnix plugin registry --json
      omarchnix plugin registry opencode
      omarchnix plugin install dizziee.opencode-model-usage --enable --yes
      omarchnix plugin validate ~/.config/omarchy/plugins/<id>
      ```
    '';

    "proofs-and-audit.md" = ''
      # Proof-Carrying Lean 4 Userspace & `omarchnix audit`

      Security-critical `omarchnix` tools built with `pkgs.omarchnix.buildVerifiedLeanSys` (such as `omarchnix-receipt-gate`) enforce four independent build- and install-time gates:

      1. **Zero `sorryAx` & kernel axiom gate:** `TurboLean.Inspector` inspects `Lean.collectAxioms` across all exported specifications and permits only `{propext, Quot.sound, Classical.choice}` (`0 sorryAx`, `0 Lean.trustCompiler`, `0 Lean.ofReduceBool`, `0 native_decide`).
      2. **Non-vacuity & tightness audit:** `turbo-lean audit-spec` requires `0` vacuous or trivial theorems and `>= 1` tight functional equivalence theorems (`admitReceipt_eq_kernel`).
      3. **Architecture-verified `LeanNative` codegen:** Compiles hot pure-Lean kernels (`OmarchnixGate/Kernel.lean`) through `LeanNative` LLVM 18 IR into `liblean_native_kernels.a`, emitting verified ARMv8.2+ NEON `pmull` SIMD on `aarch64-linux` and SSE2/PCLMULQDQ ELF64 `EM_X86_64` code on `x86_64-linux`, verified via `readelf` + `nm` anchor symbols + runtime `self-test`.
      4. **Signed Schema v2 receipts + co-tampering defense:** Shrinks ELF RPATHs before hashing, records `BuildArtifacts/BinaryBlake3_<hex>.lean` and `BuildArtifacts/ArchiveBlake3_<hex>.lean` inside signed `per_file_interfaces`, emits `<out>/share/omarchnix/receipts/<name>.receipt.json` signed with `ed25519-v1`, and re-verifies zero binary BLAKE3 drift in `postFixup`.

      Default deterministic signing seeds are public test/build inputs, not operator authentication. Their signatures detect corruption relative to a trusted build artifact but anyone can regenerate them. Use an independently trusted public key and externally isolated release signing for operator authority; never put a private signing seed in Nix expressions or the store. `receiptSigningSeedHex` is only appropriate for public deterministic/test seeds. The admission proof covers the Boolean policy, not the parser, compiler, cryptographic implementation, or whole operating system.

      ## Offline Closure Audit Commands

      ```bash
      # Verify all proof-carrying receipts in /run/current-system
      omarchnix audit

      # Machine-readable audit of an explicit store path or staged package root
      omarchnix audit --path /run/current-system --json

      # Enforce an out-of-band operator/CI Ed25519 public key (64-char hex)
      omarchnix audit --path /run/current-system --pubkey <ed25519_pubkey_hex> --json
      ```
    '';
  };

  mkSkillFilesFor =
    prefix:
    lib.mapAttrs' (fileName: text: {
      name = "${prefix}/${fileName}";
      value = {
        inherit text;
      };
    }) skillFiles;
in
{
  config = lib.mkIf (cfg.enable && cfg.agents.enable) {
    home.file =
      (mkSkillFilesFor ".agents/skills/omarchnix")
      // lib.optionalAttrs (builtins.elem "claude" cfg.agents.targets) (
        mkSkillFilesFor ".claude/skills/omarchnix"
      )
      // lib.optionalAttrs (builtins.elem "codex" cfg.agents.targets) (
        mkSkillFilesFor ".codex/skills/omarchnix"
      )
      // lib.optionalAttrs (builtins.elem "hermes" cfg.agents.targets) (
        mkSkillFilesFor ".hermes/skills/omarchnix"
      )
      // lib.optionalAttrs (builtins.elem "opencode" cfg.agents.targets) (
        mkSkillFilesFor ".config/opencode/skills/omarchnix"
      );

    xdg.configFile = lib.mkIf (builtins.elem "opencode" cfg.agents.targets) {
      "opencode/opencode.json".text =
        builtins.toJSON {
          "$schema" = "https://opencode.ai/config.json";
          update = "disable";
        }
        + "\n";
      "opencode/cli.json".text =
        builtins.toJSON {
          "$schema" = "https://opencode.ai/v2/cli.json";
          theme = {
            name = "system";
          };
        }
        + "\n";
    };
  };
}
