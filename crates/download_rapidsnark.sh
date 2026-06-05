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

# Pinned iden3 rapidsnark release. Bump this to update the prebuilt artifacts.
VERSION="v0.0.8"
BASE_URL="https://github.com/iden3/rapidsnark/releases/download/$VERSION"

BUILD_DIR="$OUT_DIR/rapidsnark"
mkdir -p "$BUILD_DIR"

arch=$(echo "$TARGET" | cut -d'-' -f1)

# Map the rust target triple to the iden3 release asset slug.
case "$TARGET" in
    x86_64-*-linux-*)                       asset="rapidsnark-linux-x86_64-$VERSION" ;;
    aarch64-*-linux-gnu*)                   asset="rapidsnark-linux-arm64-$VERSION" ;;
    aarch64-linux-android)                  asset="rapidsnark-android-arm64-$VERSION" ;;
    x86_64-linux-android)                   asset="rapidsnark-android-x86_64-$VERSION" ;;
    aarch64-apple-darwin)                   asset="rapidsnark-macOS-arm64-$VERSION" ;;
    x86_64-apple-darwin)                    asset="rapidsnark-macOS-x86_64-$VERSION" ;;
    aarch64-apple-ios-sim|x86_64-apple-ios) asset="rapidsnark-iOS-Simulator-$VERSION" ;;
    aarch64-apple-ios)                      asset="rapidsnark-iOS-$VERSION" ;;
    *)
        echo "Unsupported TARGET: $TARGET (no iden3 rapidsnark $VERSION asset mapping)"
        exit 1
        ;;
esac

zip_file="$BUILD_DIR/$asset.zip"

echo "Downloading $asset.zip ..."
if ! curl -fL -o "$zip_file" "$BASE_URL/$asset.zip"; then
    echo "Failed to download $BASE_URL/$asset.zip"
    exit 1
fi

echo "Unzipping $zip_file ..."
if ! unzip -o "$zip_file" -d "$BUILD_DIR"; then
    echo "Failed to unzip $zip_file"
    exit 1
fi

# iden3 archives extract to "$asset/{lib,bin,include}".
# build.rs expects the libraries directly under "$BUILD_DIR/$arch", so flatten the "lib" directory into that location.
# "bin" and "include" are unused (the FFI signatures are declared in src/lib.rs, no headers are needed).
dest="$BUILD_DIR/$arch"
mkdir -p "$dest"
cp "$BUILD_DIR/$asset/lib/"* "$dest/"

echo "✅ Successfully installed rapidsnark $VERSION ($asset) into $dest"
