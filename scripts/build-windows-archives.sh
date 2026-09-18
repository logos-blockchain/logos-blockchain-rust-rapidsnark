#!/bin/sh
# Build the rapidsnark-windows-x86_64 archives. Run inside the pinned toolchain:
#   nix develop .#windows-cross -c sh scripts/build-windows-archives.sh <out.zip>
set -eu
OUT_ZIP="$1"
ROOT=$(git rev-parse --show-toplevel)
: "${CROSS_GMP_LIB:?run inside: nix develop .#windows-cross}"
VERSION="v$(cat "$ROOT/RAPIDSNARK_VERSION")"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

git clone -q --depth 1 --branch "$VERSION" https://github.com/iden3/rapidsnark.git "$WORK/rs"
cd "$WORK/rs"
git submodule update --init --depth 1 depends/ffiasm depends/json
# Upstream has no MinGW port; see patches/ for what each hunk is for.
git apply "$ROOT/patches/rapidsnark-${VERSION#v}-mingw.patch"

# GMP from the same pinned package set as the compiler.
mkdir -p depends/gmp/package/lib depends/gmp/package/include
cp "$CROSS_GMP_LIB/libgmp.a" depends/gmp/package/lib/
cp "$CROSS_GMP_INCLUDE/gmp.h" depends/gmp/package/include/

# USE_ASM=OFF: build/fr.asm and fq.asm take arguments in the System V
# registers, and Windows x86-64 uses the Microsoft convention.
cmake -S . -B bp \
  -DCMAKE_TOOLCHAIN_FILE="$ROOT/cmake/mingw-w64-x86_64.cmake" \
  -DCMAKE_C_FLAGS="$CROSS_EXTRA_INCLUDES" -DCMAKE_CXX_FLAGS="$CROSS_EXTRA_INCLUDES" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DUSE_ASM=OFF -DUSE_OPENMP=OFF -DUSE_LOGGER=ON -DBUILD_TESTS=OFF
cmake --build bp -j "$(nproc)" --target rapidsnarkStatic fr fq

for a in librapidsnark.a libfr.a libfq.a; do
  x86_64-w64-mingw32-objdump -f "bp/src/$a" | grep -q 'pe-x86-64' \
    || { echo "::error::$a is not PE x86-64" >&2; exit 1; }
done

NAME="rapidsnark-windows-x86_64-$VERSION"
mkdir -p "$WORK/pkg/$NAME/lib"
cp bp/src/librapidsnark.a bp/src/libfr.a bp/src/libfq.a \
   depends/gmp/package/lib/libgmp.a "$WORK/pkg/$NAME/lib/"
# So a consumer can see which toolchain the archives need before it meets an
# undefined symbol at link.
echo "$TOOLCHAIN_ID" > "$WORK/pkg/$NAME/TOOLCHAIN"
( cd "$WORK/pkg" && zip -qr "$WORK/out.zip" "$NAME" )
cp "$WORK/out.zip" "$OUT_ZIP"
echo "built $OUT_ZIP with: $TOOLCHAIN_ID"
