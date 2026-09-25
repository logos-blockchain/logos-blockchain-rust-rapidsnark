#!/bin/sh

# Exit on error
set -e

# OUT_DIR is specified by the rust build environment
if [ -z "$OUT_DIR" ]; then
    echo "OUT_DIR not specified"
    exit 1
fi
# TARGET is specified by the rust build environment
if [ -z "$TARGET" ]; then
    echo "TARGET not specified"
    exit 1
fi

# Passed by build.rs from RAPIDSNARK_VERSION at the repo root. See CONTRIBUTING.md for bump instructions.
if [ -z "$RAPIDSNARK_VERSION" ]; then
    echo "RAPIDSNARK_VERSION not specified"
    exit 1
fi
VERSION="v${RAPIDSNARK_VERSION}"
# Upstream iden3 prebuilt archives (used for macOS / iOS / Android).
IDEN3_BASE="https://github.com/iden3/rapidsnark/releases/download/$VERSION"
# The iden3 Linux archives are non-PIC and built against a newer glibc, so they
# cannot be linked into a shared library (e.g. a downstream cdylib) on the build
# hosts. The Logos fork hosts -fPIC rebuilds of the Linux archives instead.
FORK_BASE="https://github.com/logos-blockchain/logos-blockchain-rust-rapidsnark/releases/download/rapidsnark-pic-$VERSION"

BUILD_DIR="$OUT_DIR/rapidsnark"
mkdir -p "$BUILD_DIR"

arch=$(echo "$TARGET" | cut -d'-' -f1)

# Map the rust target triple to the release asset slug and its hosting base URL.
# RAPIDSNARK_BASE_URL overrides the resolved base (e.g. a mirror or fork that
# hosts an asset not yet published upstream).
case "$TARGET" in
    x86_64-*-linux-*)                       asset="rapidsnark-linux-x86_64-pic-$VERSION"; base_url="$FORK_BASE" ;;
    aarch64-*-linux-gnu*)                   asset="rapidsnark-linux-aarch64-pic-$VERSION"; base_url="$FORK_BASE" ;;
    x86_64-pc-windows-*)                    asset="rapidsnark-windows-x86_64-pic-$VERSION"; base_url="$FORK_BASE" ;;
    aarch64-linux-android)                  asset="rapidsnark-android-arm64-$VERSION";    base_url="$IDEN3_BASE" ;;
    x86_64-linux-android)                   asset="rapidsnark-android-x86_64-$VERSION";   base_url="$IDEN3_BASE" ;;
    aarch64-apple-darwin)                   asset="rapidsnark-macOS-arm64-$VERSION";      base_url="$IDEN3_BASE" ;;
    x86_64-apple-darwin)                    asset="rapidsnark-macOS-x86_64-$VERSION";      base_url="$IDEN3_BASE" ;;
    aarch64-apple-ios-sim|x86_64-apple-ios) asset="rapidsnark-iOS-Simulator-$VERSION";    base_url="$IDEN3_BASE" ;;
    aarch64-apple-ios)                      asset="rapidsnark-iOS-$VERSION";              base_url="$IDEN3_BASE" ;;
    *)
        echo "Unsupported TARGET: $TARGET (no rapidsnark $VERSION asset mapping)"
        exit 1
        ;;
esac

base_url="${RAPIDSNARK_BASE_URL:-$base_url}"
zip_file="$BUILD_DIR/$asset.zip"

echo "Downloading $asset.zip ..."
if ! curl -fL -o "$zip_file" "$base_url/$asset.zip"; then
    echo "Failed to download $base_url/$asset.zip"
    exit 1
fi

echo "Unzipping $zip_file ..."
if ! unzip -o "$zip_file" -d "$BUILD_DIR"; then
    echo "Failed to unzip $zip_file"
    exit 1
fi

# iden3 archives extract to "$asset/{lib,bin,include}" — except the iOS zip,
# which places the libraries flat at the archive root.
# build.rs expects the libraries directly under "$BUILD_DIR/$arch", so flatten the "lib" directory into that location.
# "bin" and "include" are unused (the FFI signatures are declared in src/lib.rs, no headers are needed).
dest="$BUILD_DIR/$arch"
mkdir -p "$dest"
if [ -d "$BUILD_DIR/$asset/lib" ]; then
    cp "$BUILD_DIR/$asset/lib/"* "$dest/"
else
    find "$BUILD_DIR/$asset" -maxdepth 1 -name '*.a' -o -name '*.dylib' | while read -r f; do cp "$f" "$dest/"; done
fi

echo "✅ Successfully installed rapidsnark $VERSION ($asset) into $dest"
