#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace="$(cd "$source_dir/../.." && pwd)"
mode="${1:-release}"
case "$mode" in release|debug) ;; *) echo 'Expected release or debug' >&2; exit 2 ;; esac
sm="${SMSDK:-$workspace/sdk/sourcemod}"
deps="${SYSTEM2_DEPS:-/opt/system2-deps}"
cmp "$source_dir/dependencies.lock.json" "$deps/dependencies.lock.json" || {
  echo 'Dependency lock changed; rebuild the System2 Docker image.' >&2
  exit 1
}
build="${SYSTEM2_BUILD_DIR:-$source_dir/build-linux-$mode-x86}"
mkdir -p "$build"
cd "$build"
export CC="${CC:-clang-14}" CXX="${CXX:-clang++-14}"
flags=(--sm-path="$sm" --deps-path="$deps")
if [ "$mode" = debug ]; then flags+=(--enable-debug); else flags+=(--enable-optimize); fi
rm -f .ambuild2/vars
python3 ../configure.py "${flags[@]}"
test -f .ambuild2/vars || { echo 'AMBuild configuration failed' >&2; exit 1; }
ambuild
binary="$build/system2.ext/linux-x86/system2.ext.so"
file "$binary"
file "$binary" | grep -q 'ELF 32-bit LSB shared object, Intel 80386'
# Fail if an optional host library accidentally slipped into the link.
needed="$(readelf -wN -d "$binary" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')"
for library in $needed; do
  case "$library" in
    libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|ld-linux.so.2) ;;
    *) echo "Unexpected dynamic dependency: $library" >&2; exit 1 ;;
  esac
done
if nm -D --defined-only "$binary" | grep -E ' (curl_|OPENSSL_|SSL_|EVP_)' > /dev/null; then
  echo 'Static dependency symbols leaked into the extension export table.' >&2
  exit 1
fi
python3 "$source_dir/tests/smoke.py" "$binary" "$sm" "$deps" "$build"
out="${SYSTEM2_OUTPUT_DIR:-$workspace/output/System2/$mode}"
package="$out/package/addons/sourcemod"
mkdir -p "$package/extensions" "$package/data/system2" "$package/scripting" "$out/licenses"
cp "$binary" "$out/system2.ext.so"
cp "$binary" "$package/extensions/"
cp -R "$source_dir/sourcemod/scripting/." "$package/scripting/"
cp /etc/ssl/certs/ca-certificates.crt "$package/data/system2/ca-bundle.crt"
for pair in 'x86 i386' 'x64 amd64'; do
  read -r src dest <<< "$pair"
  mkdir -p "$package/data/system2/linux/$dest"
  cp "$deps/tools/$src/7z" "$deps/tools/$src/License.txt" "$package/data/system2/linux/$dest/"
  chmod +x "$package/data/system2/linux/$dest/7z"
done
cp -R "$deps/share/licenses/." "$out/licenses/"
cp -R "$deps/share/licenses" "$package/data/system2/"
cp "$deps/dependencies.lock.json" "$out/"
cp "$deps/dependencies.lock.json" "$package/data/system2/"
python3 "$source_dir/build-manifest.py" "$out" "$sm" "$mode"
cp "$out/build-manifest.json" "$package/data/system2/"
# tar preserves executable permissions when the package is moved from Windows.
tar -C "$out/package" -czf "$out/system2-linux-x86.tar.gz" addons
printf 'System2 build and smoke tests passed: %s\n' "$out"
