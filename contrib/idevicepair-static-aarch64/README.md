# Static aarch64 `idevicepair` + `usbmuxd`

Self-contained aarch64 builds of libimobiledevice's `idevicepair` and the
`usbmuxd` daemon, for an Android shell that has nothing but busybox. No shared
libraries, no bionic dependency, no NDK involved.

| binary        | version         | size  | sha256 |
|---------------|-----------------|-------|--------|
| `idevicepair` | 1.4.0           | 4.7M  | `755c132f963ecc5b9d7eccf5e2532654f36a5601e266e47b434f85f7550f49c0` |
| `usbmuxd`     | 1.1.1-git-3ded00c | 4.7M | `e64e48bb273ab7c401c94308d4572bbbaee3dd45b3e2cd5c1f8ff0c4797bd7ee` |

Both are `ELF 64-bit LSB pie executable, ARM aarch64, static-pie linked,
stripped` with zero `NEEDED` entries — static-PIE satisfies Android's PIE
expectations while needing no loader at all.

## Running it

Root is required: `usbmuxd` needs `/dev/bus/usb` access, and the phone must be
in USB host mode for the iOS device to appear.

```sh
adb push usbmuxd idevicepair /data/local/tmp/
adb shell
su
cd /data/local/tmp && chmod 755 usbmuxd idevicepair
mkdir -p lockdown

# IMPORTANT: export this BEFORE launching the daemon, not just for the client.
# usbmuxd's preflight worker is itself a libusbmuxd client -- it connects back
# to the mux to reach lockdownd, and resolves the address from this variable,
# falling back to /var/run/usbmuxd. -S only sets the *listening* socket.
export USBMUXD_SOCKET_ADDRESS=UNIX:/data/local/tmp/usbmuxd.sock

# daemon: every writable path overridden, since /var/run and /var/lib do not
# exist on Android
./usbmuxd -f -v -S /data/local/tmp/usbmuxd.sock \
          -P /data/local/tmp/usbmuxd.pid \
          -C /data/local/tmp/lockdown &

# client: needs the config dir too. The daemon does not -- it keeps its records
# in its -C dir, and clients fetch pair records over the mux.
export LIBIMOBILEDEVICE_CONFIG_DIR=/data/local/tmp/lockdown

./idevicepair systembuid     # confirms the client reaches the daemon
./idevicepair pair
./idevicepair validate
```

Drop `-f` to daemonize. `-P NONE` disables the pid file entirely.

Note the asymmetry: `usbmuxd` already takes `-S`/`-C`/`-P` for its paths, but
`idevicepair` hardcodes `/var/lib/lockdown`, hence the
`LIBIMOBILEDEVICE_CONFIG_DIR` patch below. Both processes must agree on the
config dir — that is where `SystemConfiguration.plist` and the per-device
pairing records live.

### `lockdown error -8`, and `idevicepair` says "No device found"

Symptom: the daemon log shows the device connecting normally
(`Connected to v2.0 device N`) but then
`preflight_worker_handle_device_add: ERROR: Could not connect to lockdownd on
device ..., lockdown error -8`, and every client reports "No device found" even
though it talks to the socket fine.

Cause: `USBMUXD_SOCKET_ADDRESS` was not exported for the *daemon* process. -8 is
`LOCKDOWN_E_MUX_ERROR`; the preflight worker could not connect back to the mux,
because without that variable libusbmuxd falls back to `/var/run/usbmuxd`. The
device stays invisible because `client_device_add()` -- the call that announces a
device to clients -- is only reached on preflight paths that get past
`lockdownd_client_new()`; the error path jumps straight to cleanup.

Fix: export it before launching usbmuxd, as shown above. Passing `-p`
(`--no-preflight`) also works, and confirms the diagnosis immediately: it skips
preflight and announces the device directly.

### If the device never appears at all

`0 device(s) detected` counts only VID `0x05ac` with PID in `0x1290-0x12af`
(plus the T2 and Apple-Silicon-restore ranges), not USB devices in general.
Recovery (`0x1281`) and DFU (`0x1227`) are deliberately outside that range.

Check the device enumerated at the kernel level first -- the Android side must
be explicitly in USB host mode, which phone-to-phone USB-C does not reliably
negotiate on its own:

```sh
for d in /sys/bus/usb/devices/*/; do
  [ -f "$d/idVendor" ] || continue
  echo "$(basename $d) $(cat $d/idVendor):$(cat $d/idProduct)"
done
```

`-f -vvv` additionally enables libusb's own debug logging, which shows the
enumeration itself.

### If `usbmuxd` fails at startup

`libusb_init failed` means libusb could not enumerate USB. It reads
`/dev/bus/usb` and `/sys/bus/usb/devices`; check both exist and that the kernel
has USB host support enabled. If they are present and it still fails, try
`setenforce 0` to rule out SELinux, since the netlink hotplug socket and usbfs
access are both mediated by policy.

## Local patches

Two small patches against libimobiledevice, both in this directory and applied
by `build.sh`:

- **0001 — configurable config dir.** Honours `$LIBIMOBILEDEVICE_CONFIG_DIR`
  instead of the hardcoded `/var/lib/lockdown`, which is neither present nor
  writable on Android. Additive: with the variable unset, behaviour is unchanged.
- **0002 — systembuid NULL guard.** Upstream ignores the return value of
  `userpref_read_system_buid()` and passes the result straight to `printf("%s")`.
  glibc prints `(null)`, but musl dereferences it and segfaults, so
  `idevicepair systembuid` crashed whenever usbmuxd was unreachable — precisely
  the state you are in while setting this up. Now prints an error and exits 1.

## Rebuilding

`build.sh` cross-compiles the whole chain (zlib, OpenSSL, curl, libplist,
libimobiledevice-glue, libusbmuxd, libtatsu, libimobiledevice, libusb, usbmuxd)
against an `aarch64-linux-musl` toolchain. On a Debian/Ubuntu x86_64 host:

```sh
apt-get install -y build-essential autoconf automake libtool pkg-config curl git
curl -fsSLO https://musl.cc/aarch64-linux-musl-cross.tgz
tar xzf aarch64-linux-musl-cross.tgz     # next to build.sh
./build.sh                                # binaries land beside the script
```

Upstream revisions are pinned in `build.sh`; run with `PIN=0` to track master.

## What was and was not verified

Built and smoke-tested under `qemu-aarch64-static` on the build host. Verified:
both binaries run; `usbmuxd` reaches `Initialization complete`, registers
hotplug and serves its socket; `idevicepair` connects over
`USBMUXD_SOCKET_ADDRESS`, retrieves the system BUID, and writes
`SystemConfiguration.plist` into the relocated config dir; `list` reads pairing
records from that dir.

Not verified: enumeration of a real iOS device, and therefore actual pairing.
The build host has no USB subsystem — `libusb_init` fails there until
`/sys/bus/usb/devices` is faked, which is how the above was tested.

## Note on the TLS backend

OpenSSL 3.5.1, statically linked, accounts for most of the binary size.
libimobiledevice also supports GnuTLS and mbedTLS if a smaller binary matters
more than matching the most-tested upstream configuration.
