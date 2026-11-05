{
  description = "NixOS on Apple Silicon (Asahi) for a MacBook Air M2 — configs, rehearsal targets, and install runbooks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    apple-silicon-support = {
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      apple-silicon-support,
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

      # Cross-buildable Asahi/NixOS installer ISO (via
      # nixos-apple-silicon's mkInstallerBootstrapCustom). Buildable on
      # x86_64 so CI can produce it without an ARM runner.
      packages = forAllSystems (system: rec {
        installer-bootstrap =
          (apple-silicon-support.lib.mkInstallerBootstrapCustom { inherit system; })
          .config.system.build.isoImage;
        default = installer-bootstrap;
      });

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
