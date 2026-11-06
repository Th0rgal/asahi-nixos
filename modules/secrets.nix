{
  config,
  lib,
  options,
  ...
}:
let
  enabled = !(config ? omarchnix) || !config.omarchnix.enable || config.omarchnix.secrets.enable;
in
{
  config = lib.optionalAttrs (options ? sops) (
    lib.mkIf enabled {
      sops = {
        defaultSopsFile = lib.mkDefault ../secrets/rehearsal.yaml;
        validateSopsFiles = lib.mkDefault true;
        age = {
          keyFile = lib.mkDefault "/var/lib/sops-nix/key.txt";
          generateKey = lib.mkDefault false;
        };
      };
    }
  );
}
