{
  lib,
  pkgs,
  ...
}:
let
  theme = import ./theme.nix { inherit pkgs; };
in
{
  _module.args.theme = theme;

  imports = [
    ./hyprland.nix
    ./waybar.nix
    ./foot.nix
    ./fuzzel.nix
    ./hyprlock.nix
    ./hypridle.nix
    ./hyprpaper.nix
  ];

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
}
