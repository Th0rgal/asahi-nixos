{ pkgs, theme, ... }:
{
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        ignore_empty_input = true;
      };

      animations = {
        enabled = true;
        bezier = "linear, 1, 1, 0, 0";
        animation = [
          "fadeIn, 1, 4, linear"
          "fadeOut, 1, 4, linear"
          "inputFieldDots, 1, 2, linear"
        ];
      };

      background = [
        {
          monitor = "";
          path = "screenshot";
          color = "rgba(${theme.colors.bg}ff)";
          blur_passes = 3;
          blur_size = 6;
        }
      ];

      input-field = [
        {
          monitor = "";
          size = "280, 52";
          outline_thickness = theme.ui.borderSize;
          dots_size = 0.28;
          dots_spacing = 0.3;
          dots_center = true;
          fade_on_empty = false;
          rounding = theme.ui.rounding;
          outer_color = "rgba(${theme.colors.accent}ee) rgba(${theme.colors.accentAlt}ee) 45deg";
          inner_color = "rgba(${theme.colors.surface}e6)";
          font_color = "rgba(${theme.colors.fg}ff)";
          check_color = "rgba(${theme.colors.warning}ee)";
          fail_color = "rgba(${theme.colors.urgent}ee)";
          font_family = theme.fonts.sans.name;
          placeholder_text = "Password";
          fail_text = "$PAMFAIL";
          position = "0, -40";
          halign = "center";
          valign = "center";
        }
      ];

      label = [
        {
          monitor = "";
          text = "$TIME";
          color = "rgba(${theme.colors.fg}ff)";
          font_size = 76;
          font_family = theme.fonts.sans.name;
          position = "0, 120";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = ''cmd[update:60000] ${pkgs.coreutils}/bin/date +"%A, %d %B %Y"'';
          color = "rgba(${theme.colors.fgMuted}ff)";
          font_size = 18;
          font_family = theme.fonts.sans.name;
          position = "0, 48";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}
