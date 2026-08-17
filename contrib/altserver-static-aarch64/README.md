# Static aarch64 AltServer (headless)

A statically linked `AltServer-Linux` for aarch64, to run on an Android shell
alongside the `usbmuxd`/`idevicepair` in `../idevicepair-static-aarch64`.

    AltServer-aarch64: ELF 64-bit LSB executable, ARM aarch64, statically linked, stripped
    11 MB, 0 NEEDED entries
    sha256 96ccad82176f14fdb1c8cc6ea19c06f31b8f430b47630d95862e4f55c64d410b

## Version

Built from AltServer-Windows **1.7.4** (2026-03-23), the newest that exists.
There is no 1.8: upstream's tags stop at 1.5.2b and its highest release branch
is 1.7.4. AltServer 1.8+ refers to the closed-source macOS app, which is not
buildable here.

Note that AltServer-Linux pins `upstream_repo` to AltServer-Windows' `develop`
branch, which upstream abandoned in July 2022 at **1.5.0** -- older than their
own 1.7.x branches. Building the project as-shipped therefore gives you 1.5.0.
`bootstrap.sh` repoints it at 1.7.4; override with `ALTSERVER_VERSION`.

Note this one is plain static, not static-PIE like the other two binaries (the
upstream Makefile drives the final link). Static executables are loaded by the
kernel directly with no dynamic loader, so this still runs on Android.

## Building

`./bootstrap.sh` does everything: builds an emulated aarch64 Alpine root, fetches
sources, and runs `build.sh` inside it. Budget ~40 minutes on 4 cores; corecrypto
is ~15 min and cpprestsdk ~17 min, both emulated.

Three things about that environment are worth knowing, because each cost a
debugging cycle:

- **`binfmt_misc` is mandatory.** Running `qemu-aarch64-static` explicitly only
  emulates that one process; anything it exec's (gcc → cc1, make → gcc) reaches
  the kernel as a foreign binary and fails with `Exec format error`. Register
  qemu with binfmt (`F` flag) and the kernel handles it transparently.
- **`/proc` must be mounted in the chroot**, or the emulated toolchain segfaults.
- **Run `apk` natively on the host**, not emulated — Alpine's apk segfaults under
  qemu-user. `apk.static --arch aarch64 --root <dir>` bootstraps a foreign root
  from x86_64 and is far faster anyway.

Native-emulated was chosen over cross-compiling because cpprestsdk needs Boost,
and Alpine ships prebuilt aarch64 `boost1.82-static` — which removes the single
most painful cross-compile. Alpine's `cpprestsdk` package is shared-only, so
that one still gets built from source.

## Local patches

- `0001-shim-missing-includes.patch` — `Archiver.cpp` uses `std::vector` without
  including `<vector>`; libstdc++ 13 no longer provides it transitively. Added to
  `shims/windows_shim.h`, which is force-included into every C++ TU and already
  pulls in `<algorithm>`/`<string>` behind an `#ifdef __cplusplus` guard.

- `0002-altserver-1.7.4-port.patch` — catches AltServer-Linux's Windows-stripping
  layer up to 1.7.x. The port works by regex-stripping Windows-only regions in
  `rewrite_altserver_source.py`, and 1.7.4 moved that code, so the markers went
  stale in both directions:
  - `altstoreSourceURL`/`altstoreBundleID` moved *above* `REGISTRY_ROOT_KEY`, so
    the registry-block strip swallowed them (which in turn poisoned the type of
    `debugDescription` and produced misleading `CocoaError` overload errors).
    Re-declared with production values.
  - The constructor now seeds a notification-icon GUID via `CoCreateGuid`; that
    icon is only used by the already-stripped `ShowNotification()`, so it goes.
  - `ShowErrorAlert()` switched to `MessageBoxIndirectW`. The message-building
    code above it is portable, so it is kept and routed to `ShowAlert()`.
  - The `MessageBox` macro used string-literal concatenation; 1.7.x passes
    non-literals, so it now uses `std::string(content) + ...`.
  - `GUID` typedef added to `src/common.h`, beside the existing `typedef int HWND`.
  - `-I$(LIB_DIR)`, because 1.7.x `DeviceManager.cpp` includes the *internal*
    `<libimobiledevice/src/idevice.h>`.
  - `-DHAVE_OPENSSL=1`, which must match
    `makefiles/libimobiledevice-build/config.h`. That define selects the TLS
    backend **and** the definition of `key_data_t` in `common/userpref.h`, so a
    mismatch between AltServer's objects and the vendored library is a struct
    layout mismatch across the link, not merely a missing header.

`build.sh` additionally patches corecrypto in place, for two defects in Apple's
public zip:

- `CMakeLists.txt` includes `scripts/code-coverage.cmake` (a third-party file
  from StableCoder) that is not shipped. `CODE_COVERAGE` is never declared as an
  option, so the macros behind it are unreachable — the include is made
  `OPTIONAL`.
- The generated source list expects `corecrypto_static/ccrng_static.c`, but the
  zip ships that file at the top level; it gets copied into place.

**Do not widen `ccrng_static.c`'s `#if CC_DARWIN` guard** to "fix" `ccrng()` on
Linux. `ccrng/src/ccrng_cryptographic.c` is guarded `#if !CC_DARWIN` and is
Apple's own non-Darwin implementation — widening the guard produces two
competing definitions of `ccrng` in one archive, where which one gets linked
depends on object pull order. This matters: AltSign calls `ccrng(NULL)` for SRP
blinding during Apple authentication.

## Runtime requirements

Beyond the static binary itself:

- **usbmuxd.** AltServer is a mux client. The setup in
  `../idevicepair-static-aarch64` carries over unchanged, including
  `USBMUXD_SOCKET_ADDRESS`. Installing over USB is the default path and needs
  nothing else:

  ```sh
  export USBMUXD_SOCKET_ADDRESS=UNIX:/data/local/tmp/usbmuxd.sock
  ./AltServer-aarch64 -u <UDID> -a you@example.com -p 'password' app.ipa
  ```

  `AltServerMain.cpp` branches on whether an IPA argument is present: with one it
  calls `InstallApplication()`, which reaches the device through libimobiledevice
  → usbmuxd → the cable, with no mDNS involved. Without one it enters server mode,
  which is the only path that needs the mDNS advertising below. Re-running the
  install command is also how you refresh a 7-day cert over USB.
- **An anisette server.** Apple's GSA authentication requires anisette data that
  cannot be generated off-Apple-hardware. `ALTSERVER_ANISETTE_SERVER` defaults to
  a third-party host, which means your Apple ID credentials transit a machine you
  do not control — self-host `alt_anisette_server` instead.
- **`python3` and `libdns_sd.so`, for server mode only.** `dnssd_loader` shells
  out to `python3 -c "...CDLL('libdns_sd.so')..."` to advertise `_altserver._tcp`
  over mDNS. On a busybox Android neither exists, and the advertisement fails
  with a traceback — non-fatal, the process keeps running. Installing an IPA
  directly (`-u UDID -a appleID -p password foo.ipa`) does not need it; only
  AltStore's over-WiFi discovery does.
- Free Apple developer certs expire every **7 days**, so unattended operation
  means stored credentials plus a reachable anisette server on a timer.

## What was and was not verified

Verified: it compiles and links fully static with zero `NEEDED` entries; the
binary runs under `qemu-aarch64` and prints usage; with no IPA argument it
enters server mode and reaches the mDNS advertising step.

Not verified: anything requiring a real Apple ID or a real iOS device — signing,
authentication, and installation are all untested. AltSign compiles against its
own bundled corecrypto headers in `upstream_repo/AltSign/Dependencies/corecrypto/`
while linking this 2024 corecrypto; the symbols it needs (`ccsrp_*`, `ccdh_*`,
`ccrng`) are present, but struct layout drift between those vintages would not
show at link time — it would surface as a failed Apple login.

## Licensing

corecrypto is under Apple's Internal Use License: use is limited to verifying the
security characteristics of Apple software on devices you own, and it states that
you may not redistribute the software or any portion of it. This binary
statically links it. Building and running it for yourself is a different question
from publishing the binary.
