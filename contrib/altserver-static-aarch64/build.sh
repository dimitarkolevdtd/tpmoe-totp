#!/bin/sh
# Runs INSIDE the aarch64 Alpine chroot (via binfmt+qemu). Mirrors upstream's
# buildenv/Dockerfile, which builds natively on an arm64 Alpine image.
set -e
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin
JOBS=4

log() { echo "=== [$(date +%T)] $* ==="; }

############ corecrypto ############
if [ ! -f /usr/local/lib64/libcorecrypto_static.a ] && [ ! -f /usr/lib/libcorecrypto_static.a ]; then
  log corecrypto
  cd /buildenv/corecrypto-2024
  # Apple's CMakeLists includes a third-party coverage script (from StableCoder)
  # that is not shipped in the zip. CODE_COVERAGE is never declared as an option,
  # so the coverage macros are unreachable -- make the include optional.
  sed -i 's|include(scripts/code-coverage.cmake)|include(scripts/code-coverage.cmake OPTIONAL)|' CMakeLists.txt
  # The generated source list expects corecrypto_static/ccrng_static.c, but the
  # public zip ships that file at the top level. Put it where cmake looks.
  # Copy verbatim, keeping its `#if CC_DARWIN` guard: on Linux it compiles to an
  # empty object, and ccrng()/ccrng_prng() come from ccrng/src/ccrng_cryptographic.c
  # instead, which is guarded `#if !CC_DARWIN` -- that is Apple's own non-Darwin
  # (Fortuna-based) implementation. Do NOT widen the guard here: that yields two
  # competing definitions of ccrng in one archive.
  if [ ! -f corecrypto_static/ccrng_static.c ]; then
    mkdir -p corecrypto_static
    cp ccrng_static.c corecrypto_static/ccrng_static.c
  fi
  mkdir -p build && cd build
  CC=clang CXX=clang++ cmake .. -DCMAKE_BUILD_TYPE=Release
  # upstream: drop the perf/test targets, they are not needed and do not build
  sed -i -E 's|^(all: CMakeFiles/corecrypto_perf)|#\1|' CMakeFiles/Makefile2 || true
  sed -i -E 's|^(all: corecrypto_perf)|#\1|' CMakeFiles/Makefile2 || true
  sed -i -E 's|^(all: CMakeFiles/corecrypto_test)|#\1|' CMakeFiles/Makefile2 || true
  sed -i -E 's|^(all: corecrypto_test)|#\1|' CMakeFiles/Makefile2 || true
  make -j$JOBS
  make install
fi

############ cpprestsdk ############
if [ ! -f /usr/local/lib64/libcpprest.a ] && [ ! -f /usr/lib/libcpprest.a ]; then
  log cpprestsdk
  cd /buildenv/cpprestsdk
  sed -i 's|-Wcast-align||' ./Release/CMakeLists.txt
  mkdir -p build && cd build
  cmake -DBUILD_SHARED_LIBS=0 -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTS=OFF -DBUILD_SAMPLES=OFF -DWERROR=OFF \
        -DCMAKE_CXX_FLAGS="-Wno-error -Wno-deprecated-declarations -include cstdint" ..
  make -j$JOBS
  make install
fi

############ libzip ############
if [ ! -f /usr/local/lib64/libzip.a ] && [ ! -f /usr/lib/libzip.a ]; then
  log libzip
  cd /buildenv/libzip
  mkdir -p build && cd build
  cmake -DBUILD_SHARED_LIBS=0 -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_GNUTLS=OFF -DENABLE_OPENSSL=ON -DENABLE_ZSTD=OFF -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF \
        -DBUILD_DOC=OFF -DBUILD_EXAMPLES=OFF -DBUILD_REGRESS=OFF -DBUILD_TOOLS=OFF ..
  make -j$JOBS
  make install
fi

############ AltServer ############
log AltServer
cd /buildenv/AltServer-Linux
mkdir -p build && cd build
make -f ../Makefile -j$JOBS

log result
ls -l /buildenv/AltServer-Linux/build/AltServer-* 2>/dev/null || echo "NO BINARY PRODUCED"
