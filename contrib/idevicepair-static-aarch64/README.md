# Static aarch64 `idevicepair`

A self-contained `idevicepair` (libimobiledevice 1.4.0) for running on an aarch64
Android shell that has nothing but busybox. No shared libraries, no bionic
dependency, no NDK involved.

    idevicepair: ELF 64-bit LSB pie executable, ARM aarch64, static-pie linked, stripped
    ~4.7 MB, sha256 176e6d343d07077ee9bd248d406d344b50e3e791a7de2ae824fdfb7a0acd1ee4

Static-PIE, so it satisfies Android's W^X/PIE expectations while needing no
loader at all (`readelf -d` shows zero `NEEDED` entries).

## Usage

```sh
adb push idevicepair /data/local/tmp/
adb shell chmod 755 /data/local/tmp/idevicepair
adb shell /data/local/tmp/idevicepair --version
```

Two environment variables matter on Android:

```sh
# where pairing records live; upstream hardcodes /var/lib/lockdown, which
# does not exist and is not writable on Android
export LIBIMOBILEDEVICE_CONFIG_DIR=/data/local/tmp/lockdown

# how to reach usbmuxd — a unix socket path or host:port
export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015

/data/local/tmp/idevicepair list
```

`idevicepair` is a usbmuxd client; it does not talk to USB itself. Something has
to be serving the mux socket — usbmuxd running locally, or a forwarder to a host
that runs it.

`LIBIMOBILEDEVICE_CONFIG_DIR` is not upstream; it comes from
`0001-userpref-configurable-config-dir.patch` here. It is additive — with the
variable unset, behaviour is unchanged.

## Rebuilding

`build.sh` cross-compiles the whole dependency chain (zlib, OpenSSL, curl,
libplist, libimobiledevice-glue, libusbmuxd, libtatsu, libimobiledevice) against
an `aarch64-linux-musl` toolchain. On a Debian/Ubuntu x86_64 host:

```sh
apt-get install -y build-essential autoconf automake libtool pkg-config curl git
curl -fsSLO https://musl.cc/aarch64-linux-musl-cross.tgz
tar xzf aarch64-linux-musl-cross.tgz     # next to build.sh
./build.sh                                # binary lands beside the script
```

Upstream revisions are pinned in `build.sh`; run with `PIN=0` to build current
master instead.

To smoke-test on the build host: `apt-get install qemu-user-static && qemu-aarch64-static ./idevicepair --version`.

## Note on the TLS backend

Built against OpenSSL 3.5.1 (statically linked), which is what accounts for most
of the binary size. libimobiledevice also supports GnuTLS and mbedTLS if a
smaller binary matters more than matching the most-tested upstream configuration.
