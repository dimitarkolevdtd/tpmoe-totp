# tpmoe-totp
<img width="2560" height="1600" alt="screenshot" src="https://github.com/user-attachments/assets/b9250a47-4229-4211-b5ed-5dfeaf41d1cf" />
this boot animation is centered around showing a trusted boot TOTP (or the lack thereof) in a really obvious way.
it was created to be used with [tpm2-totp](https://github.com/tpm2-software/tpm2-totp), but it can show a numeric code of arbitrary length passed via Plymouth's `display-message` function.

## installation
### generic linux
after installing and setting up Plymouth and tpm2-totp (or an equivalent service), just copy the contents of the repo (specifically, `tpmoe.{plymouth, script}` and the `r34` folder) in `/usr/share/plymouth/themes/tpmoe` and switch the theme to `tpmoe`.

## troubleshooting
this theme requires Plymouth scripting support.
attempting to select the theme on a Plymouth installation without scripting support throws an error similar to:
```
/usr/lib64/plymouth/script.so does not exist
```
in particular, Fedora is known to ship the script plugin in a seperate package called `plymouth-plugin-script`.

## banners
### missing code
<img width="2560" height="1600" alt="screenshot_404" src="https://github.com/user-attachments/assets/5421c963-37ac-49be-b97e-ade39ff97b93" />
this banner will be shown on boot while waiting for a TOTP to get passed in.

### untrusted
<img width="2560" height="1600" alt="screenshot_403" src="https://github.com/user-attachments/assets/e0e7434d-892f-4c25-81c6-8add80fb48ba" />
the TPM does not verify the integrity of your system before your computer gets unsuspended.
this banner will be shown on resume to reflect that.

### shutdown & suspend
<img width="2560" height="1600" alt="screenshot_500" src="https://github.com/user-attachments/assets/da74daa9-123d-492e-a5ba-75e39d47186e" />
this banner will be shown on shutdown and suspend.
