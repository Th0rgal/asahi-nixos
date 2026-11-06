{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.omarchnix;
  theme =
    if cfg.theme.attrset != null then cfg.theme.attrset else import ./theme.nix { inherit pkgs; };
in
{
  options.programs.omarchnix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the omarchnix Home Manager desktop & theme environment.";
    };

    theme = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "tokyo-night";
        description = "Active Omarchy theme name.";
      };

      attrset = lib.mkOption {
        type = lib.types.nullOr (lib.types.attrsOf lib.types.anything);
        default = null;
        description = "Optional custom theme attrset override (e.g. from lib.omarchy.importTheme).";
      };
    };
  };

  imports = [
    ./hyprland.nix
    ./waybar.nix
    ./foot.nix
    ./fuzzel.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./hyprpaper.nix
  ];

  config = lib.mkIf cfg.enable {
    _module.args.theme = theme;

    home = {
      username = lib.mkDefault "thomas";
      homeDirectory = lib.mkDefault "/home/thomas";
      stateVersion = lib.mkDefault "25.05";

      pointerCursor = {
        enable = true;
        name = theme.cursor.name;
        package = theme.cursor.package;
        size = theme.cursor.size;
        gtk.enable = true;
        x11.enable = true;
      };

      sessionVariables = {
        NIXOS_OZONE_WL = "1";
      };

      packages = [
        theme.fonts.sans.package
        theme.fonts.mono.package
        theme.fonts.icon.package
        pkgs.noto-fonts
        pkgs.brightnessctl
        pkgs.playerctl
        pkgs.grim
        pkgs.slurp
        pkgs.wl-clipboard
        pkgs.libnotify
      ];
    };

    fonts.fontconfig.enable = true;

    programs.zsh.enable = true;

    gtk = {
      enable = true;
      font = {
        name = theme.fonts.sans.name;
        size = theme.fonts.sans.size;
      };
    };
  };
}
