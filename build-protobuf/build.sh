#!/bin/bash
#
# Build Protobuf iOS xcframework
# Builds protobuf as a static library for iOS (arm64 device, arm64/x86_64 simulator)
#
# Requirements:
#   brew install autoconf automake libtool
#
# Usage:
#   ./build.sh [version]
#   ./build.sh          # builds default version (21.12 = 3.21.12)
#   ./build.sh 21.12    # builds specific version
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBMOSH_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration - Using 21.x series (3.21.x) which has simpler build system
PROTOBUF_VERSION="${1:-21.12}"
IOS_DEPLOYMENT_TARGET="17.0"

# Directories
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR/output"
SRC_DIR="$BUILD_DIR/protobuf-$PROTOBUF_VERSION"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Xcode paths
IPHONEOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
IPHONESIMULATOR_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

check_requirements() {
    log_info "Checking requirements..."

    local missing=()
    command -v autoconf >/dev/null || missing+=("autoconf")
    command -v automake >/dev/null || missing+=("automake")
    command -v libtool >/dev/null || missing+=("libtool")

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Install with: brew install ${missing[*]}"
        exit 1
    fi

    log_info "All requirements satisfied"
}

download_protobuf() {
    log_info "Downloading protobuf v$PROTOBUF_VERSION..."

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    if [ ! -d "$SRC_DIR" ]; then
        local URL="https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protobuf-cpp-3.${PROTOBUF_VERSION}.tar.gz"
        curl -L "$URL" -o "protobuf-${PROTOBUF_VERSION}.tar.gz"
        tar xzf "protobuf-${PROTOBUF_VERSION}.tar.gz"
        mv "protobuf-3.${PROTOBUF_VERSION}" "$SRC_DIR"
        rm "protobuf-${PROTOBUF_VERSION}.tar.gz"
    else
        log_info "Source already exists, skipping download"
    fi
}

build_host() {
    log_info "Building protobuf for host (protoc)..."

    cd "$SRC_DIR"
    make distclean 2>/dev/null || true

    ./configure \
        --disable-shared \
        --prefix="$OUTPUT_DIR/host"

    make -j$(sysctl -n hw.ncpu)
    make install

    PROTOC="$OUTPUT_DIR/host/bin/protoc"
    log_info "Built protoc: $PROTOC"
    log_info "Protoc version: $($PROTOC --version)"
}

build_ios() {
    local ARCH=$1
    local SDK_NAME=$2
    local SDK=$3
    local OUTPUT_NAME=$4

    log_info "Building protobuf for $OUTPUT_NAME ($ARCH)..."

    cd "$SRC_DIR"
    make distclean 2>/dev/null || true

    local CC="$(xcrun -sdk $SDK_NAME -find clang)"
    local CXX="$(xcrun -sdk $SDK_NAME -find clang++)"

    local MIN_VERSION_FLAG
    if [ "$SDK_NAME" = "iphoneos" ]; then
        MIN_VERSION_FLAG="-miphoneos-version-min=$IOS_DEPLOYMENT_TARGET"
    else
        MIN_VERSION_FLAG="-mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET"
    fi

    local COMMON_FLAGS="-arch $ARCH -isysroot $SDK $MIN_VERSION_FLAG"
    local CFLAGS="$COMMON_FLAGS"
    local CXXFLAGS="$COMMON_FLAGS -std=c++17 -stdlib=libc++"
    local LDFLAGS="-arch $ARCH -isysroot $SDK"

    local HOST
    case "$ARCH" in
        arm64) HOST="aarch64-apple-darwin" ;;
        x86_64) HOST="x86_64-apple-darwin" ;;
    esac

    export CC CXX CFLAGS CXXFLAGS LDFLAGS
    export CPPFLAGS="$CFLAGS"
    export AR="$(xcrun -sdk $SDK_NAME -find ar)"
    export RANLIB="$(xcrun -sdk $SDK_NAME -find ranlib)"

    ./configure \
        --host=$HOST \
        --with-protoc="$PROTOC" \
        --disable-shared \
        --prefix="$OUTPUT_DIR/$OUTPUT_NAME"

    make -j$(sysctl -n hw.ncpu)
    make install

    log_info "Built $OUTPUT_NAME"
}

create_xcframework() {
    log_info "Creating xcframework..."

    cd "$SCRIPT_DIR"

    # Create fat library for simulator (arm64 + x86_64)
    mkdir -p "$OUTPUT_DIR/sim-universal/lib"
    lipo -create \
        "$OUTPUT_DIR/sim-arm64/lib/libprotobuf.a" \
        "$OUTPUT_DIR/sim-x86_64/lib/libprotobuf.a" \
        -output "$OUTPUT_DIR/sim-universal/lib/libprotobuf.a"

    lipo -create \
        "$OUTPUT_DIR/sim-arm64/lib/libprotobuf-lite.a" \
        "$OUTPUT_DIR/sim-x86_64/lib/libprotobuf-lite.a" \
        -output "$OUTPUT_DIR/sim-universal/lib/libprotobuf-lite.a"

    mkdir -p "$OUTPUT_DIR/sim-universal/include"
    cp -r "$OUTPUT_DIR/sim-arm64/include/"* "$OUTPUT_DIR/sim-universal/include/"

    # Create framework structures
    local IOS_FW="$OUTPUT_DIR/ios-arm64/Protobuf.framework"
    local SIM_FW="$OUTPUT_DIR/sim-universal/Protobuf.framework"

    mkdir -p "$IOS_FW/Headers"
    cp "$OUTPUT_DIR/ios-arm64/lib/libprotobuf.a" "$IOS_FW/Protobuf"
    cp -r "$OUTPUT_DIR/ios-arm64/include/google" "$IOS_FW/Headers/"

    cat > "$IOS_FW/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Protobuf</string>
    <key>CFBundleIdentifier</key>
    <string>com.google.protobuf</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Protobuf</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>3.$PROTOBUF_VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>$IOS_DEPLOYMENT_TARGET</string>
</dict>
</plist>
EOF

    mkdir -p "$SIM_FW/Headers"
    cp "$OUTPUT_DIR/sim-universal/lib/libprotobuf.a" "$SIM_FW/Protobuf"
    cp -r "$OUTPUT_DIR/sim-universal/include/google" "$SIM_FW/Headers/"

    cat > "$SIM_FW/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Protobuf</string>
    <key>CFBundleIdentifier</key>
    <string>com.google.protobuf</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Protobuf</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>3.$PROTOBUF_VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>$IOS_DEPLOYMENT_TARGET</string>
</dict>
</plist>
EOF

    rm -rf Protobuf.xcframework
    xcodebuild -create-xcframework \
        -framework "$IOS_FW" \
        -framework "$SIM_FW" \
        -output Protobuf.xcframework

    log_info "Created Protobuf.xcframework"
}

install_to_parent() {
    # Install to parent Frameworks/ if it exists (when used from Wispy repo)
    local FRAMEWORKS_DIR="$LIBMOSH_DIR/../Frameworks"
    local BIN_DIR="$LIBMOSH_DIR/../bin"

    if [ -d "$FRAMEWORKS_DIR" ]; then
        log_info "Installing to $FRAMEWORKS_DIR..."
        rm -rf "$FRAMEWORKS_DIR/Protobuf.xcframework"
        rm -rf "$FRAMEWORKS_DIR/Protobuf_C_.xcframework"
        cp -r "$SCRIPT_DIR/Protobuf.xcframework" "$FRAMEWORKS_DIR/"

        mkdir -p "$BIN_DIR"
        cp "$PROTOC" "$BIN_DIR/protoc"

        log_info "Installed Protobuf.xcframework and protoc"
    fi
}

clean() {
    log_info "Cleaning previous builds..."
    rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
    rm -rf "$SCRIPT_DIR/Protobuf.xcframework"
}

main() {
    log_info "Starting Protobuf build for iOS..."
    log_info "Protobuf version: 3.$PROTOBUF_VERSION"
    log_info "iOS Deployment Target: $IOS_DEPLOYMENT_TARGET"

    check_requirements
    clean
    download_protobuf
    build_host

    build_ios arm64 iphoneos "$IPHONEOS_SDK" ios-arm64
    build_ios arm64 iphonesimulator "$IPHONESIMULATOR_SDK" sim-arm64
    build_ios x86_64 iphonesimulator "$IPHONESIMULATOR_SDK" sim-x86_64

    create_xcframework
    install_to_parent

    log_info "Build complete!"
    log_info "Output: $SCRIPT_DIR/Protobuf.xcframework"
}

main "$@"
