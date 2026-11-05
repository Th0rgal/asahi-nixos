{
  description = "NixOS on Apple Silicon (Asahi) for a MacBook Air M2 — configs, rehearsal targets, and install runbooks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-toolchains.url = "github:NixOS/nixpkgs/nixos-unstable";

    apple-silicon-support = {
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      apple-silicon-support,
      ...
    }@inputs:
    let
      systems = [
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkNixos =
        {
          system ? "aarch64-linux",
          modules,
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs;
            modulesPath = nixpkgs + "/nixos/modules";
          };
          modules = modules ++ [
            {
              nixpkgs.overlays = [ apple-silicon-support.overlays.default ];
              nix.registry.nixpkgs.flake = nixpkgs;
            }
          ];
        };
    in
    {
      nixosConfigurations = {
        # Target machine: MacBook Air M2 (daily driver after cutover).
        m2air = mkNixos {
          modules = [
            apple-silicon-support.nixosModules.apple-silicon-support
            ./hosts/common.nix
            ./hosts/m2air.nix
          ];
        };

        # Rehearsal machine: rented Mac mini M2 (Scaleway). Same hardware
        # module, deliberately minimal — it exists to validate the boot
        # chain, install flow, and nixos-rebuild path on real BootROM
        # before touching the Air. No user data, no secrets.
        rehearsal = mkNixos {
          modules = [
            apple-silicon-support.nixosModules.apple-silicon-support
            ./hosts/common.nix
            ./hosts/rehearsal.nix
          ];
        };

        # Pure-software test target: plain aarch64 QEMU guest, no Asahi
        # bits. Used to iterate on hosts/common.nix and the installer
        # flow without hardware.
        vm = mkNixos {
          modules = [
            ./hosts/common.nix
            ./hosts/vm.nix
          ];
        };
      };

      diskoConfigurations.m2air = import ./modules/disko-m2air.nix;

      # Asahi/NixOS installer ISO (via nixos-apple-silicon's
      # mkInstallerBootstrapCustom; built natively on ubuntu-24.04-arm in CI
      # using the nixos-apple-silicon binary cache).
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          diskoSrc = inputs.disko;
        in
        rec {
          disko =
            let
              libexec = pkgs.runCommand "disko-libexec" { } ''
                mkdir -p "$out"
                cp -r "${diskoSrc}"/{cli.nix,default.nix,disk-deactivate,lib} "$out/"
                sed -e "s|libexec_dir=\".*\"|libexec_dir=\"$out\"|" "${diskoSrc}/disko" > "$out/disko"
                chmod 755 "$out/disko"
              '';
            in
            pkgs.writeShellApplication {
              name = "disko";
              runtimeInputs = [
                pkgs.nix
                pkgs.coreutils
                pkgs.xcp
                pkgs.nixos-install-tools
                pkgs.exfatprogs
              ];
              text = ''
                export DISKO_VERSION="${inputs.disko.shortRev or "pinned"}"
                export NIX_PATH="nixpkgs=${nixpkgs}"
                exec "${libexec}/disko" "$@"
              '';
            };
          installer-bootstrap =
            (apple-silicon-support.lib.mkInstallerBootstrapCustom { inherit system; })
            .config.system.build.isoImage;
          default = installer-bootstrap;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          diskoEval =
            (nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                inputs.disko.nixosModules.disko
                ./modules/disko-m2air.nix
                { system.stateVersion = "25.05"; }
              ];
            }).config.system.build.destroyFormatMount;
        in
        {
          disko-declare = pkgs.runCommand "disko-declare" { } ''
            script="${diskoEval}/bin/disko-destroy-format-mount"
            test -x "$script"
            ${pkgs.bash}/bin/bash -n "$script"
            ${pkgs.shellcheck}/bin/shellcheck -S warning -e SC2034,SC2054 "$script"
            grep -q 'cryptsetup -q luksFormat' "$script"
            grep -q 'mkfs.ext4' "$script"
            grep -q 'mkfs.exfat' "$script"
            grep -q 'mkfs.vfat' "$script"
            grep -q 'cryptroot' "$script"
            grep -q '/mnt/shared' "$script"
            echo "$script" > "$out"
          '';

          security = import ./tests/security.nix {
            inherit pkgs inputs;
            inherit (nixpkgs) lib;
            m2airConfig = self.nixosConfigurations.m2air.config;
          };
        }
      );

      # Wrapper: recent nixfmt chokes when 'nix fmt' invokes it with no
      # positional args, so collect the .nix files ourselves.
      formatter = forAllSystems (
        system:
        nixpkgs.legacyPackages.${system}.writeShellScriptBin "nix-fmt" ''
          exec ${nixpkgs.legacyPackages.${system}.nixfmt}/bin/nixfmt \
            $(git ls-files '*.nix' 2>/dev/null || find . -name '*.nix' -not -path './.git/*')
        ''
      );
    };
}
