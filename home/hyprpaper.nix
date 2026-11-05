{ pkgs, theme, ... }:
let
  wallpaperSvg = pkgs.writeText "m2air-wallpaper.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" width="2560" height="1664" viewBox="0 0 2560 1664">
      <defs>
        <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#${theme.colors.bg}"/>
          <stop offset="55%" stop-color="#${theme.colors.bgAlt}"/>
          <stop offset="100%" stop-color="#${theme.colors.surface}"/>
        </linearGradient>
        <radialGradient id="glow" cx="72%" cy="28%" r="55%">
          <stop offset="0%" stop-color="#${theme.colors.accent}" stop-opacity="0.22"/>
          <stop offset="55%" stop-color="#${theme.colors.accentAlt}" stop-opacity="0.08"/>
          <stop offset="100%" stop-color="#${theme.colors.bg}" stop-opacity="0"/>
        </radialGradient>
      </defs>
      <rect width="2560" height="1664" fill="url(#bg)"/>
      <rect width="2560" height="1664" fill="url(#glow)"/>
    </svg>
  '';
  wallpaperPng =
    pkgs.runCommand "m2air-wallpaper.png"
      {
        nativeBuildInputs = [ pkgs.librsvg ];
      }
      ''
        rsvg-convert -f png -o "$out" "${wallpaperSvg}"
      '';
in
{
  services.hyprpaper = {
    enable = true;
    settings = {
      splash = false;
      ipc = true;
      wallpaper = [
        {
          monitor = "";
          path = "${wallpaperPng}";
          fit_mode = "cover";
        }
      ];
    };
  };
}
