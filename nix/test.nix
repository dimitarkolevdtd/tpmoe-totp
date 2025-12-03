inputs:

{
  name = "tpmoe-totp test";

  enableOCR = true;

  nodes.machine = { config, ... }: {
    imports = [
      inputs.self.modules.nixos.default
    ];

    # NOTE: enable TPM in the VM
    virtualisation.tpm = {
      enable = true;
      # tpm.provisioning = _;
    };

    boot = {
      initrd.systemd.enable = true;
      loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };
    };
  };

  interactive.nodes.machine = import ./debug-host-module.nix;

  # TODO: research how to (if possible at all) configure `tpm2` on the test vm
  #       and do some OCR magic to test the codes
  testScript = /* python */ ''
    start_all()

    # WARN: is this boot-time?
    machine.wait_for_unit("plymouth-start.target")

    # TODO: screenshot and validate code
    machine.screenshot("banica")

    # TODO: confirm
    machine.send_key("enter")

    machine.wait_for_unit("plymouth-quit.target")

    machine.wait_for_unit("graphical.target")

    machine.succeed("whoami")
  '';
}
