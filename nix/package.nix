{
  lib,
  plymouth,
  stdenvNoCC,
  fetchFromGitHub,
  unstableGitUpdater,
}:

let
  fs = lib.fileset;
in
stdenvNoCC.mkDerivation {
  pname = "plymouth-tpmoe-totp-theme";
  version = "0.1.0-unstable-2025-12-10";

  src = fs.toSource rec {
    root = ../.;
    fileset = fs.unions [
      (lib.path.append root "r34")
      (lib.path.append root "tpmoe.plymouth")
      (lib.path.append root "tpmoe.script")
    ];
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/plymouth/themes/tpmoe/
    cp -r . $out/share/plymouth/themes/tpmoe/
    find $out/share/plymouth/themes/ -name '*.plymouth' -exec sed -i "s@\/usr\/@$out\/@" {} ';'

    runHook postInstall
  '';

  passthru.updateScript = unstableGitUpdater { };

  meta = {
    description = "a Plymouth theme designed to display trusted boot TOTPs, themed after a popular image sharing website.";
    homepage = "https://github.com/dimitarkolevdtd/tpmoe-totp";
    license = lib.licenses.mit;
    platforms = plymouth.meta.platforms;
    maintainers = [ ];
  };
}
