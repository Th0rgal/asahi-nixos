{
  sops = {
    defaultSopsFile = ../secrets/rehearsal.yaml;
    validateSopsFiles = true;
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      generateKey = false;
    };
  };
}
