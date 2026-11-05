{ theme, ... }:
{
  programs.foot = {
    enable = true;
    settings = {
      main = {
        term = "xterm-256color";
        font = "${theme.fonts.mono.name}:size=${toString theme.fonts.mono.size}";
        dpi-aware = "auto";
        pad = "12x12 center";
      };

      mouse = {
        hide-when-typing = "yes";
      };

      scrollback = {
        lines = 10000;
      };

      colors-dark = {
        alpha = "0.94";
        background = theme.colors.bg;
        foreground = theme.colors.fg;
        regular0 = theme.colors.bgAlt;
        regular1 = theme.colors.urgent;
        regular2 = theme.colors.success;
        regular3 = theme.colors.warning;
        regular4 = theme.colors.accent;
        regular5 = theme.colors.magenta;
        regular6 = theme.colors.accentAlt;
        regular7 = theme.colors.fgMuted;
        bright0 = theme.colors.border;
        bright1 = theme.colors.urgent;
        bright2 = theme.colors.success;
        bright3 = theme.colors.warning;
        bright4 = theme.colors.accent;
        bright5 = theme.colors.magenta;
        bright6 = theme.colors.accentAlt;
        bright7 = theme.colors.fg;
      };
    };
  };
}
