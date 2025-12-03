inputs:
{ pkgs, ... }:

{
  boot = {
    initrd.systemd.enable = true;

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
