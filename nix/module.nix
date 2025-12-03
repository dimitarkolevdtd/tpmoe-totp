inputs:
{ pkgs, ... }:

{
  boot = {
    plymouth = {
      enable = true;

      tpm2-totp.enable = true;

      theme = "tpmoe";
      themePackages = [
        inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];
    };
  };
}
