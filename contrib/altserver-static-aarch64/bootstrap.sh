#!/bin/bash
# Host side (x86_64 Debian/Ubuntu): build an emulated aarch64 Alpine root that can
# compile AltServer-Linux, then run build.sh inside it.
#
# Cross-compiling was rejected: cpprestsdk needs Boost, and Alpine ships prebuilt
# aarch64 boost statics, so building natively-emulated avoids the worst of it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$ROOT/work}"
ALPINE_VER=v3.19
ROOTFS="$WORK/alp"

mkdir -p "$WORK"

apt-get install -y qemu-user-static curl git unzip

############################################################
# 1. binfmt_misc -- the non-obvious prerequisite.
#
# Invoking qemu-aarch64-static explicitly only emulates THAT process. Every
# child it exec's (gcc -> cc1, make -> gcc) goes to the kernel as a foreign
# binary and dies with "Exec format error". Registering qemu with binfmt makes
# the kernel do it transparently, so multi-process builds work. The F flag
# preloads the interpreter so it also resolves inside the chroot.
############################################################
if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
  mount -t binfmt_misc none /proc/sys/fs/binfmt_misc 2>/dev/null || true
  printf ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F' \
    > /proc/sys/fs/binfmt_misc/register
fi

############################################################
# 2. Bootstrap the aarch64 root using apk.static running NATIVELY on the host.
#    (Alpine's own apk segfaults under qemu-user; running it native sidesteps
#    that entirely and is much faster.)
############################################################
if [ ! -d "$ROOTFS" ]; then
  mkdir -p "$WORK/apktools" && cd "$WORK/apktools"
  APKPKG=$(curl -sS "https://dl-cdn.alpinelinux.org/alpine/$ALPINE_VER/main/x86_64/" \
           | grep -o 'apk-tools-static-[0-9][^"]*\.apk' | head -1)
  curl -fsSL -o apk-static.apk "https://dl-cdn.alpinelinux.org/alpine/$ALPINE_VER/main/x86_64/$APKPKG"
  tar xzf apk-static.apk

  APK="$WORK/apktools/sbin/apk.static --arch aarch64 --root $ROOTFS \
       --repository https://dl-cdn.alpinelinux.org/alpine/$ALPINE_VER/main \
       --repository https://dl-cdn.alpinelinux.org/alpine/$ALPINE_VER/community \
       --allow-untrusted"
  mkdir -p "$ROOTFS/etc/apk"
  $APK --initdb add --no-scripts alpine-baselayout busybox musl
  $APK update
  # boost1.82-static is the win here: prebuilt aarch64 boost statics.
  $APK add --no-scripts build-base cmake samurai git bash curl perl python3 unzip \
      boost-dev boost1.82-static openssl-dev openssl-libs-static zlib-dev zlib-static \
      util-linux-dev util-linux-static libzip-dev linux-headers clang

  cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/"
  cp /etc/resolv.conf "$ROOTFS/etc/"
  mkdir -p "$ROOTFS/etc/ssl/certs"
  cp /etc/ssl/certs/ca-certificates.crt "$ROOTFS/etc/ssl/certs/" 2>/dev/null || true
fi

mkdir -p "$ROOTFS/proc" "$ROOTFS/dev"
mountpoint -q "$ROOTFS/proc" || mount -t proc proc "$ROOTFS/proc"
mountpoint -q "$ROOTFS/dev"  || mount --bind /dev "$ROOTFS/dev"
# /proc must be mounted: without it the emulated toolchain segfaults.
chroot "$ROOTFS" /bin/busybox --install -s 2>/dev/null || true

############################################################
# 3. Fetch sources natively (fast), into the rootfs.
############################################################
mkdir -p "$ROOTFS/buildenv"
cd "$ROOTFS/buildenv"

# corecrypto: opensource.apple.com now redirects to a GitHub org. Upstream's
# Dockerfile pulls it straight from developer.apple.com, which needs no account.
if [ ! -d corecrypto-2024 ]; then
  curl -sSL -JO 'https://developer.apple.com/file/?file=security&agree=Yes' \
       -H 'Referer: https://developer.apple.com/security/'
  unzip -q -o corecrypto.zip
fi
[ -d cpprestsdk ]       || git clone -q --recursive --depth 1 https://github.com/microsoft/cpprestsdk.git cpprestsdk
[ -d libzip ]           || git clone -q --depth 1 https://github.com/nih-at/libzip.git libzip
[ -d AltServer-Linux ]  || git clone -q --recursive https://github.com/NyaMisty/AltServer-Linux.git AltServer-Linux

# AltServer-Linux pins upstream_repo to AltServer-Windows' `develop` branch, which
# upstream abandoned in 2022 at 1.5.0 -- older than their own 1.7.x release
# branches. Track 1.7.4, the newest that exists. (There is no 1.8.)
git -C AltServer-Linux/upstream_repo fetch -q --depth 200 origin "${ALTSERVER_VERSION:-1.7.4}"
git -C AltServer-Linux/upstream_repo checkout -q FETCH_HEAD

# std::vector used without <vector>; libstdc++ 13 no longer pulls it in transitively.
git -C AltServer-Linux apply "$ROOT/0001-shim-missing-includes.patch" 2>/dev/null || true
# Catches AltServer-Linux's Windows-stripping layer up to 1.7.x (see README).
git -C AltServer-Linux apply "$ROOT/0002-altserver-1.7.4-port.patch" 2>/dev/null || true

cp "$ROOT/build.sh" "$ROOTFS/buildenv/build.sh"
chmod +x "$ROOTFS/buildenv/build.sh"

############################################################
# 4. Build (emulated; corecrypto ~15min, cpprestsdk ~17min on 4 cores).
############################################################
chroot "$ROOTFS" /bin/sh -c 'cd /buildenv && ./build.sh'

cp "$ROOTFS/buildenv/AltServer-Linux/build/AltServer-aarch64" "$ROOT/AltServer-aarch64"
echo "built: $ROOT/AltServer-aarch64"
