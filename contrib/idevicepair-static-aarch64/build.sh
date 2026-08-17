#!/bin/bash
# Cross-build a fully static aarch64 idevicepair (musl libc) for an Android shell.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$ROOT/prefix"
SRC="$ROOT/src"
TC="$ROOT/aarch64-linux-musl-cross/bin"
HOST=aarch64-linux-musl
JOBS="$(nproc)"

export PATH="$TC:$PATH"
export CC="$HOST-gcc"
export CXX="$HOST-g++"
export AR="$HOST-ar"
export RANLIB="$HOST-ranlib"
export STRIP="$HOST-strip"
export LD="$HOST-ld"
export CFLAGS="-Os -ffunction-sections -fdata-sections"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-static -Wl,--gc-sections"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR=""
export PKG_CONFIG="pkg-config --static"

mkdir -p "$PREFIX" "$SRC"
cd "$SRC"

log() { echo "=== [$(date +%T)] $* ==="; }

fetch_tar() { # url dir
  local url="$1" dir="$2"
  cd "$SRC"
  [ -d "$dir" ] && return 0
  curl -fsSL --retry 4 --retry-delay 2 --max-time 900 -o "$dir.tar.gz" "$url"
  mkdir -p "$dir"
  tar xzf "$dir.tar.gz" -C "$dir" --strip-components=1
}

fetch_git() { # url dir [ref]
  local url="$1" dir="$2" ref="${3:-}"
  cd "$SRC"
  [ -d "$dir" ] && return 0
  if [ -n "$ref" ]; then
    git clone -q --depth 1 --branch "$ref" "$url" "$dir"
  else
    git clone -q --depth 1 "$url" "$dir"
  fi
}

############ zlib ############
log "zlib"
fetch_tar "https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz" zlib
if [ ! -f "$PREFIX/lib/libz.a" ]; then
  cd "$SRC/zlib"
  CHOST="$HOST" ./configure --prefix="$PREFIX" --static
  make -j"$JOBS" && make install
fi

############ openssl ############
log "openssl"
fetch_tar "https://github.com/openssl/openssl/releases/download/openssl-3.5.1/openssl-3.5.1.tar.gz" openssl
if [ ! -f "$PREFIX/lib/libssl.a" ]; then
  cd "$SRC/openssl"
  ./Configure linux-aarch64 no-shared no-dso no-tests no-docs no-legacy \
    --prefix="$PREFIX" --openssldir="$PREFIX/ssl" --libdir=lib \
    -Os
  make -j"$JOBS"
  make install_sw
fi

############ curl (needed by libtatsu) ############
log "curl"
fetch_tar "https://github.com/curl/curl/releases/download/curl-8_11_1/curl-8.11.1.tar.gz" curl
if [ ! -f "$PREFIX/lib/libcurl.a" ]; then
  cd "$SRC/curl"
  ./configure --host="$HOST" --prefix="$PREFIX" \
    --disable-shared --enable-static \
    --with-openssl="$PREFIX" --with-zlib="$PREFIX" \
    --without-libpsl --without-brotli --without-zstd --without-libidn2 \
    --without-nghttp2 --without-ngtcp2 --without-librtmp \
    --disable-ldap --disable-ldaps --disable-manual --disable-docs \
    --disable-ftp --disable-file --disable-dict --disable-telnet \
    --disable-tftp --disable-pop3 --disable-imap --disable-smtp \
    --disable-gopher --disable-smb --disable-mqtt --disable-rtsp \
    --enable-ipv6 --enable-threaded-resolver
  make -j"$JOBS" && make install
fi

############ libimobiledevice stack ############
build_am() { # dir extra-configure-args...
  local dir="$1"; shift
  cd "$SRC/$dir"
  [ -f configure ] || ./autogen.sh --help >/dev/null 2>&1 || true
  NOCONFIGURE=1 ./autogen.sh
  ./configure --host="$HOST" --prefix="$PREFIX" --disable-shared --enable-static "$@"
  make -j"$JOBS"
  make install
}

# Revisions the shipped binary was built from. Unset PIN=1 to track master.
pin() { # dir sha
  [ "${PIN:-1}" = "1" ] || return 0
  git -C "$SRC/$1" fetch -q --depth 1 origin "$2" && git -C "$SRC/$1" checkout -q "$2"
}

log "libplist"
fetch_git https://github.com/libimobiledevice/libplist.git libplist
pin libplist 32428abacb909988e8e960a8845a6430b17b6a60
[ -f "$PREFIX/lib/libplist-2.0.a" ] || build_am libplist --without-cython --without-tests

log "libimobiledevice-glue"
fetch_git https://github.com/libimobiledevice/libimobiledevice-glue.git libimobiledevice-glue
pin libimobiledevice-glue da770a7687f35fbb981db4d7b47b1b032cd5c2c7
[ -f "$PREFIX/lib/libimobiledevice-glue-1.0.a" ] || build_am libimobiledevice-glue

log "libusbmuxd"
fetch_git https://github.com/libimobiledevice/libusbmuxd.git libusbmuxd
pin libusbmuxd 93eb168bf6b07472d17781328c21df0c60300524
[ -f "$PREFIX/lib/libusbmuxd-2.0.a" ] || build_am libusbmuxd

log "libtatsu"
fetch_git https://github.com/libimobiledevice/libtatsu.git libtatsu
pin libtatsu 60a39f36d719344360ec2e87563ed43f61f0530f
[ -f "$PREFIX/lib/libtatsu-1.0.a" ] || build_am libtatsu

log "libimobiledevice"
fetch_git https://github.com/libimobiledevice/libimobiledevice.git libimobiledevice
pin libimobiledevice fa0f79190142bc309307967c058f89c1b36eb6b8
# Make the pairing record location overridable via $LIBIMOBILEDEVICE_CONFIG_DIR;
# the hardcoded /var/lib/lockdown is not writable on an Android shell.
if ! git -C "$SRC/libimobiledevice" diff --quiet -- common/userpref.c; then
  echo "patch already applied"
else
  git -C "$SRC/libimobiledevice" apply "$ROOT/0001-userpref-configurable-config-dir.patch"
fi
build_am libimobiledevice --without-cython --with-openssl

# libtool treats bare -static as "prefer static libtool libs", which still leaves
# libc dynamic. -all-static is what actually produces a self-contained binary.
log "relink static"
cd "$SRC/libimobiledevice/tools"
rm -f idevicepair
make idevicepair LDFLAGS="-all-static -Wl,--gc-sections"
cp idevicepair "$ROOT/idevicepair"
"$STRIP" "$ROOT/idevicepair"

log "result"
file "$ROOT/idevicepair"
sha256sum "$ROOT/idevicepair"
