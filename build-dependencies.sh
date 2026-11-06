#!/usr/bin/env bash
set -euo pipefail
prefix=/opt/system2-deps
work=/tmp/system2-deps
mkdir -p "$work" "$prefix/share/licenses" "$prefix/tools"
python3 /opt/system2-build/fetch-dependencies.py /opt/system2-build/dependencies.lock.json "$work"
cd "$work"
for archive in *.tar.*; do
  case "$archive" in
    7z*) mkdir -p "${archive%.tar.xz}"; tar -xf "$archive" -C "${archive%.tar.xz}" ;;
    *) tar -xf "$archive" ;;
  esac
done
export CC=gcc CXX=g++
export CFLAGS='-m32 -O2 -fPIC -fvisibility=hidden'
export CXXFLAGS="$CFLAGS"
export LDFLAGS='-m32'
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
export CPPFLAGS="-I$prefix/include"
jobs="${BUILD_JOBS:-8}"
source_dir() {
  python3 -c 'import json, pathlib, sys; url = json.load(open(sys.argv[1]))["sources"][sys.argv[2]]["url"]; print(url.rsplit("/", 1)[1].removesuffix(".tar.gz").removesuffix(".tar.xz"))' \
    /opt/system2-build/dependencies.lock.json "$1"
}

cd "$work/$(source_dir openssl)"
./Configure linux-x86 --prefix="$prefix" --libdir=lib no-shared no-tests no-module no-dso -fPIC
make -j"$jobs"
make install_sw
cp LICENSE.txt "$prefix/share/licenses/openssl.txt"

cd "$work/$(source_dir zlib)"
./configure --static --prefix="$prefix"
make -j"$jobs"
make check
make install
cp LICENSE "$prefix/share/licenses/zlib.txt"

cd "$work/$(source_dir libunistring)"
./configure --prefix="$prefix" --libdir="$prefix/lib" --host=i686-pc-linux-gnu \
  --disable-shared --enable-static --with-pic --disable-rpath
make -j"$jobs"
make install
mkdir -p "$prefix/share/licenses/libunistring"
cp COPYING* "$prefix/share/licenses/libunistring/"

cd "$work/$(source_dir libidn2)"
./configure --prefix="$prefix" --libdir="$prefix/lib" --host=i686-pc-linux-gnu \
  --disable-shared --enable-static --with-pic --disable-doc --disable-nls \
  --with-libunistring-prefix="$prefix" --disable-rpath
make -j"$jobs"
make install
mkdir -p "$prefix/share/licenses/libidn2"
cp COPYING* "$prefix/share/licenses/libidn2/"

cd "$work/$(source_dir curl)"
LDFLAGS="-m32 -L$prefix/lib" LIBS='-lunistring -pthread -ldl' ./configure \
  --prefix="$prefix" --libdir="$prefix/lib" --host=i686-pc-linux-gnu \
  --disable-shared --enable-static --enable-symbol-hiding --with-openssl="$prefix" \
  --with-zlib="$prefix" --with-libidn2="$prefix" --without-libpsl \
  --without-brotli --without-zstd --without-libssh2 --without-libssh \
  --without-nghttp2 --without-nghttp3 --without-ngtcp2 --without-librtmp \
  --without-gssapi --disable-ldap --disable-ldaps --disable-rtsp --disable-manual \
  --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt --with-ca-path=/etc/ssl/certs
make -j"$jobs"
make install
cp COPYING "$prefix/share/licenses/curl.txt"

for arch in x86 x64; do
  mkdir -p "$prefix/tools/$arch"
  cp "$work/$(source_dir 7zip-$arch)/7zz" "$prefix/tools/$arch/7z"
  cp "$work/$(source_dir 7zip-$arch)/License.txt" "$prefix/tools/$arch/License.txt"
  chmod +x "$prefix/tools/$arch/7z"
done
cp /opt/system2-build/dependencies.lock.json "$prefix/"
"$prefix/bin/curl" --version
file "$prefix/bin/curl" "$prefix/tools/x86/7z"
