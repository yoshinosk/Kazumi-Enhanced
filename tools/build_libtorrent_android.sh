#!/bin/bash
# Kazumi: rebuild Android liblibtorrent_flutter.so from the vendored bridge
# source (third_party/libtorrent_flutter/src/torrent_bridge.cpp) against the
# stable libtorrent 2.0.11 — the same generation the proven Windows DLL uses.
# Mirrors the upstream release workflow's Android recipe, with libtorrent
# 2.0.11 instead of 2.1.1.
#
# Run from Git Bash:
#   tools/build_libtorrent_android.sh hostprep  # MSYS make + perl modules (once)
#   tools/build_libtorrent_android.sh prepare   # download + extract sources (once)
#   tools/build_libtorrent_android.sh openssl   # OpenSSL 3.2.1 static libs, 3 ABIs
#   tools/build_libtorrent_android.sh lt        # libtorrent 2.0.11 static libs, 3 ABIs
#   tools/build_libtorrent_android.sh bridge    # vendored bridge -> liblibtorrent_flutter.so
#
# Outputs land in build_android/libtorrent_flutter_<abi>.so; copy them over
# third_party/libtorrent_flutter/prebuilt/android/<abi>/liblibtorrent_flutter.so
# when verified (build_android/ is git-ignored).
#
# Host requirements (all local, nothing installed system-wide):
#   - NDK 28.2.13676358 at D:/DevCache/Android/Sdk/ndk (toolchain clang + sysroot)
#   - SDK cmake/ninja at D:/DevCache/Android/Sdk/cmake/3.22.1
#   - MSYS2 GNU make (hostprep downloads it; Git Bash ships no make and the
#     NDK's native win32 make cannot read the POSIX paths OpenSSL's Makefile uses)
#   - MSYS perl + PERL5LIB modules (hostprep collects them: Locale::Maketext{,-Simple},
#     ExtUtils::MakeMaker, Pod::Usage + Pod::Text/Simple/Escapes — the stock
#     MSYS perl is missing all of them)
#   - Boost headers (uses the vcpkg boost the Windows DLL also builds against)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$REPO_ROOT/third_party/libtorrent_flutter/build_android"
NDK=/d/DevCache/Android/Sdk/ndk/28.2.13676358
TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/windows-x86_64
export ANDROID_NDK_ROOT=$NDK
export PATH="$TOOLCHAIN/bin:$ROOT/bin:/usr/bin:/bin"
export PERL5LIB=$ROOT/perl5lib
MAKE=$ROOT/bin/make.exe
CMAKE=/d/DevCache/Android/Sdk/cmake/3.22.1/bin/cmake.exe
NINJA=/d/DevCache/Android/Sdk/cmake/3.22.1/bin/ninja.exe
BOOST_INC="D:/Program Files/vcpkg/installed/x64-windows/include" # boost 1.91 headers, same as Windows DLL
LT_VERSION=2.0.11
OSSL_VERSION=3.2.1
ABIS="arm64-v8a armeabi-v7a x86_64"
JOBS=10

hostprep() {
  mkdir -p "$ROOT/bin" "$ROOT/perl5lib"
  # GNU make (MSYS2 package: zst outer, tar inner; Bandizip handles zst)
  curl -sL "https://repo.msys2.org/msys/x86_64/make-4.4.1-3-x86_64.pkg.tar.zst" -o "$ROOT/make.pkg.tar.zst"
  "/d/Program Files/Bandizip/bz.exe" x -y -o:"$ROOT/pkgtmp" "$ROOT/make.pkg.tar.zst"
  "/d/Program Files/Bandizip/bz.exe" x -y -o:"$ROOT/pkgtmp" "$ROOT/pkgtmp/make.pkg.tar"
  cp "$ROOT/pkgtmp/usr/bin/make.exe" "$ROOT/bin/"
  # perl modules the stock MSYS perl lacks (OpenSSL Configure needs them)
  perl_fetch() { # <author-path> <dist-dir>
    curl -sL "https://cpan.metacpan.org/authors/id/$1" -o "$ROOT/pkg.tar.gz"
    tar xzf "$ROOT/pkg.tar.gz" -C "$ROOT/"
    cp -r "$ROOT/$2/lib/"* "$ROOT/perl5lib/"
    rm -rf "$ROOT/$2"
  }
  perl_fetch "J/JE/JESSE/Locale-Maketext-Simple-0.21.tar.gz" "Locale-Maketext-Simple-0.21"
  perl_fetch "B/BI/BINGOS/ExtUtils-MakeMaker-7.70.tar.gz" "ExtUtils-MakeMaker-7.70"
  perl_fetch "M/MA/MAREKR/Pod-Usage-2.05.tar.gz" "Pod-Usage-2.05"
  perl_fetch "R/RR/RRA/podlators-v6.1.1.tar.gz" "podlators-v6.1.1"
  perl_fetch "K/KH/KHW/Pod-Simple-3.48.tar.gz" "Pod-Simple-3.48"
  perl_fetch "N/NE/NEILB/Pod-Escapes-1.07.tar.gz" "Pod-Escapes-1.07"
  # Locale::Maketext itself comes from the perl5 blead tree (no standalone dist)
  curl -sL "https://raw.githubusercontent.com/Perl/perl5/blead/dist/Locale-Maketext/lib/Locale/Maketext.pm" \
    -o "$ROOT/perl5lib/Locale/Maketext.pm" --create-dirs
}

prepare() {
  cd "$ROOT"
  curl -sL "https://github.com/arvidn/libtorrent/releases/download/v$LT_VERSION/libtorrent-rasterbar-$LT_VERSION.tar.gz" -o libtorrent.tar.gz
  tar xzf libtorrent.tar.gz && mv libtorrent-rasterbar-$LT_VERSION libtorrent-src
  curl -sL "https://github.com/openssl/openssl/releases/download/openssl-$OSSL_VERSION/openssl-$OSSL_VERSION.tar.gz" -o openssl.tar.gz
  tar xzf openssl.tar.gz && mv openssl-$OSSL_VERSION openssl-src
}

openssl_build() {
  cd "$ROOT"
  for abi in $ABIS; do
    case $abi in
      arm64-v8a)   target=android-arm64; extra="" ;;
      armeabi-v7a) target=android-arm;    extra="no-asm" ;; # 32-bit ARM asm is not PIC-clean in .so
      x86_64)      target=android-x86_64; extra="" ;;
    esac
    mkdir -p openssl-build-$abi && cd openssl-build-$abi
    perl $ROOT/openssl-src/Configure $target -D__ANDROID_API__=24 \
      --prefix="$ROOT/openssl-install-$abi" \
      -fPIC no-shared no-tests no-ui-console no-docs $extra
    "$MAKE" -j$JOBS build_libs
    "$MAKE" install_sw
    cd "$ROOT"
  done
}

lt_build() {
  cd "$ROOT"
  for abi in $ABIS; do
    mkdir -p lt-build-$abi && cd lt-build-$abi
    # OPENSSL_ROOT_DIR must be a Windows-form path and ALSO listed in
    # CMAKE_FIND_ROOT_PATH, otherwise the Android toolchain re-roots every
    # find_() search onto the sysroot and OpenSSL is not found.
    "$CMAKE" $ROOT/libtorrent-src -G Ninja \
      -DCMAKE_MAKE_PROGRAM=$NINJA \
      -DCMAKE_SYSTEM_NAME=Android \
      -DCMAKE_ANDROID_NDK="$(cygpath -m $NDK)" \
      -DCMAKE_ANDROID_ARCH_ABI=$abi \
      -DCMAKE_ANDROID_STL_TYPE=c++_static \
      -DCMAKE_SYSTEM_VERSION=24 \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DBUILD_SHARED_LIBS=OFF \
      -Dstatic_runtime=ON \
      -Ddeprecated-functions=ON \
      -Dencryption=ON \
      -DOPENSSL_ROOT_DIR="$(cygpath -m $ROOT/openssl-install-$abi)" \
      -DOPENSSL_USE_STATIC_LIBS=TRUE \
      -DCMAKE_FIND_ROOT_PATH="$(cygpath -m $ROOT/openssl-install-$abi)" \
      -DBOOST_ROOT="$BOOST_INC" \
      -DBoost_INCLUDE_DIR="$BOOST_INC" \
      -DBoost_NO_SYSTEM_PATHS=ON
    "$CMAKE" --build . --parallel $JOBS
    cd "$ROOT"
  done
}

bridge_build() {
  cd "$ROOT"
  for abi in $ABIS; do
    case $abi in
      arm64-v8a)   triple=aarch64-linux-android24 ;;
      armeabi-v7a) triple=armv7a-linux-androideabi24 ;;
      x86_64)      triple=x86_64-linux-android24 ;;
    esac
    "$TOOLCHAIN/bin/clang++.exe" --target=$triple \
      -shared -fPIC -O2 -std=c++17 \
      -fvisibility=hidden \
      -Wl,-z,max-page-size=16384 \
      -DTORRENT_BRIDGE_EXPORTS \
      -DTORRENT_USE_OPENSSL \
      -DBOOST_NO_IOSTREAM \
      -I$ROOT/libtorrent-src/include -I$ROOT/lt-build-$abi/include \
      -I"$BOOST_INC" -I$ROOT/openssl-install-$abi/include \
      -o libtorrent_flutter_$abi.so \
      "$ROOT/../src/torrent_bridge.cpp" \
      -Wl,--whole-archive $ROOT/lt-build-$abi/libtorrent-rasterbar.a -Wl,--no-whole-archive \
      $ROOT/openssl-install-$abi/lib/libssl.a $ROOT/openssl-install-$abi/lib/libcrypto.a \
      -llog -static-libstdc++
  done
}

case "${1:-}" in
  hostprep) hostprep ;;
  prepare)  prepare ;;
  openssl)  openssl_build ;;
  lt)       lt_build ;;
  bridge)   bridge_build ;;
  *) echo "usage: $0 hostprep|prepare|openssl|lt|bridge"; exit 1 ;;
esac
