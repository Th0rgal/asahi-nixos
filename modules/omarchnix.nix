{
  config,
  lib,
  options,
  pkgs,
  inputs ? { },
  ...
}:
let
  cfg = config.omarchnix;
  secCfg = config.security.omarchnix;
  hex64Type = lib.types.strMatching "^[0-9a-fA-F]{64}$";
  pkgNameType = lib.types.strMatching "^[a-zA-Z0-9][a-zA-Z0-9._+-]*$";
  normalizedTrustedReceiptKeys = lib.unique (map lib.toLower secCfg.trustedReceiptKeys);
  effectiveReceiptEnforcement =
    if secCfg.enforceReceipts != null then
      secCfg.enforceReceipts
    else
      normalizedTrustedReceiptKeys != [ ];
  omarchnixReceiptGatePkg =
    if (pkgs ? omarchnix) && (pkgs.omarchnix ? receipt-gate) then
      pkgs.omarchnix.receipt-gate
    else if (inputs ? lean-sys) && (inputs ? turbo-lean) then
      let
        leanSys = import ../pkgs/lean-sys.nix {
          inherit pkgs;
          leanSysSrc = inputs.lean-sys;
        };
        turboLean = import ../pkgs/turbo-lean.nix {
          inherit lib pkgs leanSys;
          turboLeanSrc = inputs.turbo-lean;
        };
        buildVerifiedLeanSys = import ../pkgs/build-verified-lean-sys.nix {
          inherit
            lib
            pkgs
            leanSys
            turboLean
            ;
        };
      in
      import ../pkgs/omarchnix-receipt-gate { inherit buildVerifiedLeanSys; }
    else
      null;
  omarchnixTurboLeanPkg =
    if (pkgs ? omarchnix) && (pkgs.omarchnix ? turbo-lean) then
      pkgs.omarchnix.turbo-lean
    else if (inputs ? lean-sys) && (inputs ? turbo-lean) then
      let
        leanSys = import ../pkgs/lean-sys.nix {
          inherit pkgs;
          leanSysSrc = inputs.lean-sys;
        };
      in
      import ../pkgs/turbo-lean.nix {
        inherit lib pkgs leanSys;
        turboLeanSrc = inputs.turbo-lean;
      }
    else
      null;
  omarchnixShellPkg =
    if (pkgs ? omarchnix) && (pkgs.omarchnix ? omarchy-shell) then
      pkgs.omarchnix.omarchy-shell
    else if inputs ? omarchy then
      import ../pkgs/omarchy-shell.nix {
        inherit lib pkgs;
        marketplaceSrc = inputs.omarchy-plugin-marketplace or null;
        omarchySrc = inputs.omarchy;
      }
    else
      null;
  omarchnixMarketplaceSrc =
    if (pkgs ? omarchnix) && (pkgs.omarchnix ? marketplaceSrc) then
      pkgs.omarchnix.marketplaceSrc
    else
      inputs.omarchy-plugin-marketplace or null;
  omarchnixCliPkg =
    if omarchnixShellPkg != null then
      import ../pkgs/omarchnix-cli.nix {
        inherit lib pkgs;
        omarchyShell = omarchnixShellPkg;
        marketplaceSrc = omarchnixMarketplaceSrc;
        turboLean = omarchnixTurboLeanPkg;
        receiptGate = omarchnixReceiptGatePkg;
        trustedReceiptKeys = normalizedTrustedReceiptKeys;
        requiredReceiptPackages = lib.optionals effectiveReceiptEnforcement secCfg.requiredReceiptPackages;
      }
    else if (pkgs ? omarchnix) && (pkgs.omarchnix ? cli) then
      pkgs.omarchnix.cli
    else
      null;
  trustedKeysFile = pkgs.writeText "omarchnix-trusted-receipt-keys" (
    lib.concatMapStrings (k: "${k}\n") normalizedTrustedReceiptKeys
  );
  requiredPackagesFile = pkgs.writeText "omarchnix-required-receipt-packages" (
    lib.concatMapStrings (p: "${p}\n") secCfg.requiredReceiptPackages
  );
  auditPolicyArgs =
    lib.optionals (normalizedTrustedReceiptKeys != [ ]) [
      "--trusted-keys-file"
      "${trustedKeysFile}"
    ]
    ++ lib.optionals (secCfg.requiredReceiptPackages != [ ]) [
      "--required-packages-file"
      "${requiredPackagesFile}"
    ]
    ++ lib.optionals (secCfg.receiptAttestationsDir != null) [
      "--attestations-dir"
      "${secCfg.receiptAttestationsDir}"
    ]
    ++ lib.optional secCfg.requireExternalAttestations "--require-attestations"
    ++ lib.optional (
      normalizedTrustedReceiptKeys == [ ] && secCfg.allowDevReceiptKeys
    ) "--allow-dev-keys";
in
{
  imports = [
    ./hardware-m2air.nix
    ./hardening.nix
    ./containers.nix
    ./secrets.nix
  ];

  options = {
    security.omarchnix = {
      trustedReceiptKeys = lib.mkOption {
        type = lib.types.listOf hex64Type;
        default = [ ];
        description = "Externally pinned 64-character hex Ed25519 public keys trusted to authenticate Schema v2 receipts or detached receipt attestations.";
      };

      allowDevReceiptKeys = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Explicitly permit self-declared public dev/test signing keys in system receipt checks when trustedReceiptKeys is empty.";
      };

      enforceReceipts = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Enforce candidate pre-switch receipt verification and current-system receipt verification (defaults to true when trustedReceiptKeys is non-empty, false otherwise).";
      };

      verifyCurrentSystemService = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable systemd oneshot verifier for the active /run/current-system closure when receipt enforcement is active.";
      };

      requiredReceiptPackages = lib.mkOption {
        type = lib.types.listOf pkgNameType;
        default = lib.optional (cfg.enable && cfg.verifiedUserspace.enable) "omarchnix-receipt-gate";
        defaultText = lib.literalExpression ''lib.optional (config.omarchnix.enable && config.omarchnix.verifiedUserspace.enable) "omarchnix-receipt-gate"'';
        description = "Critical package binaries that must be present and covered by verified Schema v2 receipts in audited closures.";
      };

      receiptAttestationsDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional host directory containing detached operator Ed25519 attestations over store receipts.";
      };

      requireExternalAttestations = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Require detached external Ed25519 attestations signed by trustedReceiptKeys even if a store receipt carries a matching public key.";
      };
    };

    omarchnix = {
      enable = lib.mkEnableOption "omarchnix reusable NixOS workstation & server module (Apple Silicon Asahi, NVIDIA Grace / DGX Spark, and x86_64-linux)";

      profile = lib.mkOption {
        type = lib.types.enum [
          "asahi"
          "spark"
          "workstation"
          "vm"
        ];
        default = "workstation";
        description = ''
          Hardware/boot profile:
          - `asahi`: Apple Silicon (M-series) external BootROM/m1n1/U-Boot boot chain (DR-5: boot.loader.* disabled).
          - `spark`: ARM64 (`aarch64-linux`) UEFI server/workstation (e.g. NVIDIA Grace / DGX Spark) with systemd-boot.
          - `workstation`: Generic `x86_64-linux` or `aarch64-linux` UEFI workstation with systemd-boot.
          - `vm`: QEMU/KVM virtual machine target with systemd-boot.
        '';
      };

      hardening.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable defense-in-depth hardening (default-deny firewall, key-only AppArmor-confined sshd, wheel-only sudo, kernel sysctls).";
      };

      containers.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable user-namespaced, network-isolated dev-untrusted NixOS container + bubblewrap.";
      };

      secrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable sops-nix age secret decryption wiring.";
      };

      verifiedUserspace.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install proof-carrying Lean 4 + lean-sys + LeanNative userspace utilities (`omarchnix-receipt-gate`) and link signed Schema v2 receipts under `/run/current-system/sw/share/omarchnix/receipts`.";
      };

      desktop = {
        enable = lib.mkEnableOption "omarchnix Hyprland Wayland desktop stack";

        user = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Primary desktop user account to wire into Home Manager when non-null.";
        };

        theme = lib.mkOption {
          type = lib.types.str;
          default = "tokyo-night";
          description = "Default Omarchy theme name passed into Home Manager.";
        };

        shellBackend = lib.mkOption {
          type = lib.types.enum [
            "waybar"
            "omarchy-shell"
          ];
          default = "waybar";
          description = "Default desktop bar/panel backend passed into Home Manager (`omarchy-shell` or `waybar`).";
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.optionalAttrs (options ? home-manager) (
      lib.mkIf (cfg.enable && cfg.desktop.enable && cfg.desktop.user != null) {
        home-manager = {
          useGlobalPkgs = lib.mkDefault true;
          useUserPackages = lib.mkDefault true;
          extraSpecialArgs = lib.optionalAttrs (inputs != { }) {
            inherit inputs;
          };
          users.${cfg.desktop.user} =
            { ... }:
            {
              imports = [ ../home ];
              programs.omarchnix = {
                theme.name = lib.mkDefault cfg.desktop.theme;
                shell.backend = lib.mkDefault cfg.desktop.shellBackend;
              };
            };
        };
      }
    ))

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion =
            !effectiveReceiptEnforcement || normalizedTrustedReceiptKeys != [ ] || secCfg.allowDevReceiptKeys;
          message = "security.omarchnix.enforceReceipts requires externally pinned trustedReceiptKeys, or explicit allowDevReceiptKeys for unauthenticated development checks.";
        }
        {
          assertion = !effectiveReceiptEnforcement || omarchnixCliPkg != null;
          message = "security.omarchnix.enforceReceipts requires the omarchnix CLI package.";
        }
        {
          assertion = !effectiveReceiptEnforcement || secCfg.requiredReceiptPackages != [ ];
          message = "security.omarchnix.enforceReceipts requires at least one requiredReceiptPackages entry.";
        }
        {
          assertion = !secCfg.requireExternalAttestations || normalizedTrustedReceiptKeys != [ ];
          message = "security.omarchnix.requireExternalAttestations requires externally pinned trustedReceiptKeys.";
        }
      ];

      environment.etc = {
        "omarchnix/trusted-receipt-keys".source = trustedKeysFile;
      }
      // lib.optionalAttrs effectiveReceiptEnforcement {
        "omarchnix/required-receipt-packages".source = requiredPackagesFile;
      };

      time.timeZone = lib.mkDefault "Europe/Paris";
      i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
      console.keyMap = lib.mkDefault "fr";

      services.openssh = {
        enable = lib.mkDefault true;
        settings = {
          PasswordAuthentication = lib.mkDefault false;
          KbdInteractiveAuthentication = lib.mkDefault false;
        };
      };

      environment.variables.EDITOR = "hx";
      programs.zsh.enable = lib.mkDefault true;

      environment.pathsToLink = [
        "/share/omarchnix"
      ];

      environment.systemPackages = [
        pkgs.git
        pkgs.helix
        pkgs.jq
        pkgs.ripgrep
      ]
      ++ lib.optional (omarchnixCliPkg != null) omarchnixCliPkg
      ++ lib.optional (
        cfg.verifiedUserspace.enable && omarchnixReceiptGatePkg != null
      ) omarchnixReceiptGatePkg;

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        auto-optimise-store = lib.mkDefault true;
      };

      system.stateVersion = lib.mkDefault "25.05";
    })

    (lib.mkIf (cfg.enable && effectiveReceiptEnforcement && omarchnixCliPkg != null) {
      system.preSwitchChecks.omarchnix-receipts = ''
        candidate="''${1:?candidate system path required}"
        ${omarchnixCliPkg}/bin/omarchnix check --candidate "$candidate" ${lib.escapeShellArgs auditPolicyArgs} --json
      '';

      systemd.services.omarchnix-verify-receipts = lib.mkIf secCfg.verifyCurrentSystemService {
        description = "Verify receipts for the current system closure (not a pre-switch candidate check)";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        restartTriggers = [
          trustedKeysFile
          requiredPackagesFile
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          DynamicUser = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          NoNewPrivileges = true;
          ExecStart = "${omarchnixCliPkg}/bin/omarchnix audit --path /run/current-system ${lib.escapeShellArgs auditPolicyArgs} --json";
        };
      };
    })

    (lib.mkIf (cfg.enable && cfg.profile == "asahi") {
      boot.loader.systemd-boot.enable = false;
      boot.loader.grub.enable = false;
      boot.loader.efi.canTouchEfiVariables = false;

      nix.settings = {
        substituters = [ "https://nixos-apple-silicon.cachix.org" ];
        trusted-public-keys = [
          "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
        ];
      };
    })

    (lib.mkIf (cfg.enable && cfg.profile != "asahi") {
      boot.loader.systemd-boot.enable = lib.mkDefault true;
      boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
    })

    (lib.mkIf (cfg.enable && cfg.profile == "spark") {
      zramSwap = {
        enable = lib.mkDefault true;
        algorithm = lib.mkDefault "zstd";
        memoryPercent = lib.mkDefault 25;
      };
    })

    (lib.mkIf (cfg.enable && cfg.desktop.enable) {
      hardware.graphics.enable = lib.mkDefault true;

      programs.hyprland = {
        enable = true;
        withUWSM = true;
        xwayland.enable = true;
      };

      security.pam.services.hyprlock = { };
      security.pam.services.omarchy-lock-password = { };
      security.polkit.enable = true;
    })
  ];
}
