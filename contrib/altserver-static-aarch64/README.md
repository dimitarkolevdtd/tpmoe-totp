# Static aarch64 AltServer (headless)

A statically linked `AltServer-Linux` for aarch64, to run on an Android shell
alongside the `usbmuxd`/`idevicepair` in `../idevicepair-static-aarch64`.

    AltServer-aarch64: ELF 64-bit LSB executable, ARM aarch64, statically linked, stripped
    9.9 MB, 0 NEEDED entries
    sha256 d99575daf5ea5202d5247d868cd9f64d019ca3089cccd15a9a8b118be79239c0

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
  `USBMUXD_SOCKET_ADDRESS`.
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
