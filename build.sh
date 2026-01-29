#!/bin/bash
#
# Modern build script for libmosh iOS xcframework
# Builds mosh as a static library for iOS (arm64 device, arm64/x86_64 simulator)
#
# Requirements:
#   brew install automake autoconf libtool pkg-config protobuf@21
#
# Usage (standalone):
#   ./build.sh
#
# Usage (from Wispy repo):
#   ./scripts/build-mosh.sh
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect if we're running from within libmosh or from scripts/
if [ -f "$SCRIPT_DIR/mosh/configure.ac" ]; then
    # Running from libmosh directory
    LIBMOSH_DIR="$SCRIPT_DIR"
    ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    # Running from scripts directory
    ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    LIBMOSH_DIR="$ROOT_DIR/libmosh"
fi

# Configuration
IOS_DEPLOYMENT_TARGET="17.0"

# Directories
MOSH_SRC="$LIBMOSH_DIR/mosh"
BUILD_DIR="$LIBMOSH_DIR/build"
OUTPUT_DIR="$LIBMOSH_DIR/output"
NCURSES_HEADERS="$BUILD_DIR/ncurses-headers"

# Protoc - check local build first, then parent, then homebrew
if [ -x "$LIBMOSH_DIR/build-protobuf/output/host/bin/protoc" ]; then
    PROTOC="$LIBMOSH_DIR/build-protobuf/output/host/bin/protoc"
elif [ -x "$ROOT_DIR/bin/protoc" ]; then
    PROTOC="$ROOT_DIR/bin/protoc"
elif [ -x "/opt/homebrew/opt/protobuf@21/bin/protoc" ]; then
    PROTOC="/opt/homebrew/opt/protobuf@21/bin/protoc"
else
    PROTOC=""
fi

# Protobuf xcframework - check local build first, then parent Frameworks
if [ -d "$LIBMOSH_DIR/build-protobuf/Protobuf.xcframework" ]; then
    PROTOBUF_XCFRAMEWORK="$LIBMOSH_DIR/build-protobuf/Protobuf.xcframework"
elif [ -d "$ROOT_DIR/Frameworks/Protobuf.xcframework" ]; then
    PROTOBUF_XCFRAMEWORK="$ROOT_DIR/Frameworks/Protobuf.xcframework"
elif [ -d "$ROOT_DIR/Frameworks/Protobuf_C_.xcframework" ]; then
    PROTOBUF_XCFRAMEWORK="$ROOT_DIR/Frameworks/Protobuf_C_.xcframework"
else
    PROTOBUF_XCFRAMEWORK=""
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Xcode paths
IPHONEOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
IPHONESIMULATOR_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

# Check requirements
check_requirements() {
    log_info "Checking requirements..."

    local missing=()
    command -v automake >/dev/null || missing+=("automake")
    command -v autoconf >/dev/null || missing+=("autoconf")
    xcrun -f libtool >/dev/null 2>&1 || { log_error "Xcode libtool not found"; exit 1; }

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Install with: brew install ${missing[*]}"
        exit 1
    fi

    if [ -z "$PROTOC" ] || [ ! -x "$PROTOC" ]; then
        log_error "protoc not found"
        log_error "Build protobuf first: ./build-protobuf/build.sh"
        exit 1
    fi

    if [ -z "$PROTOBUF_XCFRAMEWORK" ] || [ ! -d "$PROTOBUF_XCFRAMEWORK" ]; then
        log_error "Protobuf xcframework not found"
        log_error "Build protobuf first: ./build-protobuf/build.sh"
        exit 1
    fi

    if [ ! -d "$MOSH_SRC" ]; then
        log_error "Mosh source not found. Run: git submodule update --init --recursive"
        exit 1
    fi

    log_info "All requirements satisfied"
    log_info "Using protoc: $PROTOC"
    log_info "Using protobuf: $PROTOBUF_XCFRAMEWORK"
}

# Clean previous builds
clean() {
    log_info "Cleaning previous builds..."
    rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
    rm -rf "$LIBMOSH_DIR/mosh.xcframework"
    cd "$MOSH_SRC" && make distclean 2>/dev/null || true
}

# Create minimal ncurses headers (iOS controller doesn't use ncurses at runtime)
setup_ncurses_headers() {
    log_info "Setting up ncurses headers..."
    mkdir -p "$NCURSES_HEADERS"

    # Create minimal headers - mosh iOS controller has hardcoded terminal caps
    cat > "$NCURSES_HEADERS/ncurses.h" << 'EOF'
#ifndef _NCURSES_H
#define _NCURSES_H
// Minimal ncurses header for iOS cross-compilation
// The iOS controller doesn't use ncurses at runtime
typedef char* TERMINAL;
#define OK 0
#define ERR (-1)
#endif
EOF

    cat > "$NCURSES_HEADERS/curses.h" << 'EOF'
#ifndef _CURSES_H
#define _CURSES_H
#include "ncurses.h"
#endif
EOF

    cat > "$NCURSES_HEADERS/term.h" << 'EOF'
#ifndef _TERM_H
#define _TERM_H
// Minimal term.h for iOS cross-compilation
#endif
EOF
}

# Get protobuf paths for a given platform
get_protobuf_paths() {
    local PLATFORM=$1

    # Detect framework name (Protobuf or Protobuf_C_)
    local FW_NAME
    if [ -d "$PROTOBUF_XCFRAMEWORK/ios-arm64/Protobuf.framework" ]; then
        FW_NAME="Protobuf"
    else
        FW_NAME="Protobuf_C_"
    fi

    case "$PLATFORM" in
        ios-arm64)
            echo "$PROTOBUF_XCFRAMEWORK/ios-arm64/$FW_NAME.framework"
            ;;
        sim-arm64|sim-x86_64)
            echo "$PROTOBUF_XCFRAMEWORK/ios-arm64_x86_64-simulator/$FW_NAME.framework"
            ;;
    esac
}

# Build mosh for a specific platform
build_mosh() {
    local ARCH=$1
    local SDK_NAME=$2
    local SDK=$3
    local OUTPUT_NAME=$4

    log_info "Building mosh for $OUTPUT_NAME ($ARCH)..."

    cd "$MOSH_SRC"

    # Clean previous build thoroughly
    make distclean 2>/dev/null || true
    rm -f config.cache config.status config.log
    rm -rf autom4te.cache

    # Get protobuf framework path
    local PROTOBUF_FW=$(get_protobuf_paths "$OUTPUT_NAME")
    local PROTOBUF_HEADERS="$PROTOBUF_FW/Headers"
    # Extract framework name from path (e.g., Protobuf.framework -> Protobuf)
    local FW_BASENAME=$(basename "$PROTOBUF_FW" .framework)
    local PROTOBUF_LIB="$PROTOBUF_FW/$FW_BASENAME"

    # Compiler flags
    local CC="$(xcrun -sdk $SDK_NAME -find clang)"
    local CXX="$(xcrun -sdk $SDK_NAME -find clang++)"

    # iOS has forkpty and cfmakeraw - define them to skip pty_compat.cc compilation
    local MIN_VERSION_FLAG
    if [ "$SDK_NAME" = "iphoneos" ]; then
        MIN_VERSION_FLAG="-miphoneos-version-min=$IOS_DEPLOYMENT_TARGET"
    else
        MIN_VERSION_FLAG="-mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET"
    fi
    local COMMON_FLAGS="-arch $ARCH -isysroot $SDK $MIN_VERSION_FLAG -I$NCURSES_HEADERS -DHAVE_FORKPTY=1 -DHAVE_CFMAKERAW=1"
    local CFLAGS="$COMMON_FLAGS"
    local CXXFLAGS="$COMMON_FLAGS -std=c++17 -stdlib=libc++"
    local LDFLAGS="-arch $ARCH -isysroot $SDK"

    # Clear any cached values from previous builds
    unset ac_cv_lib_z_compress

    # Configure environment - set cache variables for cross-compilation
    export ac_cv_path_PROTOC="$PROTOC"
    export ac_cv_lib_z_compress=yes
    export ac_cv_func_gettimeofday=yes
    export ac_cv_func_forkpty=yes
    export ac_cv_func_cfmakeraw=yes
    export ac_cv_func_posix_memalign=yes
    export ac_cv_func_pselect=yes
    export protobuf_LIBS="$PROTOBUF_LIB"
    export protobuf_CFLAGS="-I$PROTOBUF_HEADERS"
    export CC CXX
    export CFLAGS CXXFLAGS LDFLAGS
    export CPPFLAGS="$CFLAGS"
    export AR="$(xcrun -sdk $SDK_NAME -find ar)"
    export RANLIB="$(xcrun -sdk $SDK_NAME -find ranlib)"

    # Host triple
    local HOST
    case "$ARCH" in
        arm64) HOST="aarch64-apple-darwin" ;;
        x86_64) HOST="x86_64-apple-darwin" ;;
    esac

    # Run autogen if needed
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    ./configure \
        --host=$HOST \
        --disable-server \
        --disable-client \
        --enable-ios-controller \
        --prefix="$OUTPUT_DIR/$OUTPUT_NAME"

    make -j$(sysctl -n hw.ncpu)

    # Create combined static library
    mkdir -p "$OUTPUT_DIR/$OUTPUT_NAME/lib"

    # Use Xcode's libtool for creating static libraries
    local LIBTOOL_CMD="$(xcrun -sdk $SDK_NAME -find libtool)"

    $LIBTOOL_CMD -static -o "$OUTPUT_DIR/$OUTPUT_NAME/lib/libmosh.a" \
        src/crypto/libmoshcrypto.a \
        src/network/libmoshnetwork.a \
        src/protobufs/libmoshprotos.a \
        src/statesync/libmoshstatesync.a \
        src/terminal/libmoshterminal.a \
        src/frontend/libmoshiosclient.a \
        src/util/libmoshutil.a

    # Copy headers
    mkdir -p "$OUTPUT_DIR/$OUTPUT_NAME/include/mosh"
    cp src/frontend/moshiosbridge.h "$OUTPUT_DIR/$OUTPUT_NAME/include/mosh/"

    log_info "Built $OUTPUT_NAME"
}

# Create xcframework
create_xcframework() {
    log_info "Creating xcframework..."

    cd "$LIBMOSH_DIR"

    # Create fat library for simulator (arm64 + x86_64)
    mkdir -p "$OUTPUT_DIR/sim-universal/lib"
    lipo -create \
        "$OUTPUT_DIR/sim-arm64/lib/libmosh.a" \
        "$OUTPUT_DIR/sim-x86_64/lib/libmosh.a" \
        -output "$OUTPUT_DIR/sim-universal/lib/libmosh.a"

    # Copy headers for simulator
    mkdir -p "$OUTPUT_DIR/sim-universal/include"
    cp -r "$OUTPUT_DIR/sim-arm64/include/"* "$OUTPUT_DIR/sim-universal/include/"

    # Create temporary framework structures
    local IOS_FW="$OUTPUT_DIR/ios-arm64/mosh.framework"
    local SIM_FW="$OUTPUT_DIR/sim-universal/mosh.framework"

    mkdir -p "$IOS_FW/Headers"
    cp "$OUTPUT_DIR/ios-arm64/lib/libmosh.a" "$IOS_FW/mosh"
    cp -r "$OUTPUT_DIR/ios-arm64/include/mosh/"* "$IOS_FW/Headers/"

    # Create Info.plist for iOS framework
    cat > "$IOS_FW/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>mosh</string>
    <key>CFBundleIdentifier</key>
    <string>org.mosh.mosh</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>mosh</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.4.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>17.0</string>
</dict>
</plist>
EOF

    mkdir -p "$SIM_FW/Headers"
    cp "$OUTPUT_DIR/sim-universal/lib/libmosh.a" "$SIM_FW/mosh"
    cp -r "$OUTPUT_DIR/sim-universal/include/mosh/"* "$SIM_FW/Headers/"

    # Create Info.plist for Simulator framework
    cat > "$SIM_FW/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>mosh</string>
    <key>CFBundleIdentifier</key>
    <string>org.mosh.mosh</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>mosh</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.4.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>17.0</string>
</dict>
</plist>
EOF

    # Create xcframework from frameworks
    rm -rf mosh.xcframework
    xcodebuild -create-xcframework \
        -framework "$IOS_FW" \
        -framework "$SIM_FW" \
        -output mosh.xcframework

    log_info "Created mosh.xcframework"
}

# Copy to Wispy Frameworks (if running from Wispy repo)
install_framework() {
    local DEST="$ROOT_DIR/Frameworks"
    if [ -d "$DEST" ]; then
        log_info "Installing to Frameworks..."
        rm -rf "$DEST/mosh.xcframework"
        cp -r "$LIBMOSH_DIR/mosh.xcframework" "$DEST/"
        log_info "Installed to $DEST/mosh.xcframework"
    else
        log_info "Frameworks directory not found, skipping install"
        log_info "Output available at: $LIBMOSH_DIR/mosh.xcframework"
    fi
}

# Main build process
main() {
    log_info "Starting libmosh build for iOS..."
    log_info "iOS Deployment Target: $IOS_DEPLOYMENT_TARGET"

    check_requirements
    clean
    setup_ncurses_headers

    # Build mosh for each platform
    build_mosh arm64 iphoneos "$IPHONEOS_SDK" ios-arm64
    build_mosh arm64 iphonesimulator "$IPHONESIMULATOR_SDK" sim-arm64
    build_mosh x86_64 iphonesimulator "$IPHONESIMULATOR_SDK" sim-x86_64

    create_xcframework
    install_framework

    log_info "Build complete!"
}

# Run
main "$@"
