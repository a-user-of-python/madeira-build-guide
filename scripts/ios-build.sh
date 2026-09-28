#!/bin/bash
# ios-build.sh — Automates the Mac-only steps of the Madeira build for iPhone.
# Put this script ANYWHERE and run it. It copies itself to ~/Desktop/m-ios,
# clones the madeira repo there, and does the whole build from that folder.
#
# Usage:
#   ./ios-build.sh            # full build from ~/Desktop/m-ios
#   ./ios-build.sh --full     # also auto-download toolchain, DLLs, licenses
#
# This script will:
#   1. Verify Xcode and iPhoneOS SDK are present
#   2. Locate (or clone) the madeira repo
#   3. Verify submodule commits match the pinned versions
#   4. Build FEX iOS static libraries
#   5. Build Wine Unix libraries
#   6. Build DXMT combined library
#   7. Verify all expected archives exist
#   8. Run the Debug Xcode build
#
# STOP ON FIRST ERROR
set -euo pipefail

# ── Self-install: live in ~/Desktop/m-ios ─────────────────────────────
# No matter where this script is run from, it copies itself into
# ~/Desktop/m-ios and re-launches from there.
TARGET_DIR="$HOME/Desktop/m-ios"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$SCRIPT_DIR" != "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
    cp "$0" "$TARGET_DIR/$SCRIPT_NAME"
    chmod +x "$TARGET_DIR/$SCRIPT_NAME"
    echo "Moved script to $TARGET_DIR/$SCRIPT_NAME — launching from there..."
    exec "$TARGET_DIR/$SCRIPT_NAME" "$@"
fi

# ── Helpers ──────────────────────────────────────────────────────────
red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()   { red "FATAL: $*"; exit 1; }

# ── 1. Xcode + SDK checks ────────────────────────────────────────────
step "Checking Xcode and iPhoneOS SDK..."
xcode-select -p >/dev/null 2>&1 || die "Xcode command-line tools not installed. Install Xcode from the App Store, then run: xcode-select --install"
xcrun -sdk iphoneos --show-sdk-path >/dev/null 2>&1 || die "iPhoneOS SDK not found. Open Xcode once to finish setup."
green "Xcode OK: $(xcodebuild -version | head -1)"
green "iPhoneOS SDK: $(xcrun -sdk iphoneos --show-sdk-path)"

# ── Parse arguments ──────────────────────────────────────────────────
FULL_AUTO=0
for arg in "$@"; do
    case "$arg" in
        --full) FULL_AUTO=1 ;;
    esac
done

# ── 2. Locate (or clone) the madeira repo ─────────────────────────────
# The repo lives in ~/Desktop/m-ios (where this script runs from).
step "Checking madeira repo..."
MADEIRA_DIR="$TARGET_DIR"
if [ ! -d "$MADEIRA_DIR/FEX" ] || [ ! -d "$MADEIRA_DIR/app" ]; then
    step "Cloning madeira into $MADEIRA_DIR..."
    # The script itself is already in here, so stash it, clone, restore it.
    tmp_script="$(mktemp)"
    cp "$0" "$tmp_script"
    rm -rf "$MADEIRA_DIR"
    git clone --recurse-submodules https://github.com/willfaust/madeira.git "$MADEIRA_DIR" \
        || die "Clone failed. Check your internet connection."
    cp "$tmp_script" "$MADEIRA_DIR/$SCRIPT_NAME"
    chmod +x "$MADEIRA_DIR/$SCRIPT_NAME"
    rm -f "$tmp_script"
fi

cd "$MADEIRA_DIR" || die "Cannot cd to $MADEIRA_DIR"
green "Using madeira repo: $(pwd)"

# ── 2b. Full-auto: toolchain, DLLs, licenses ──────────────────────────
if [ "$FULL_AUTO" -eq 1 ]; then
    step "Setting up toolchain..."
    if [ ! -d "toolchains/llvm-mingw-20260421-ucrt-macos-universal" ]; then
        mkdir -p toolchains && cd toolchains
        curl -sL -o llvm-mingw.tar.xz https://github.com/mstorsjo/llvm-mingw/releases/download/20260421/llvm-mingw-20260421-ucrt-ubuntu-22.04-x86_64.tar.xz
        tar -xf llvm-mingw.tar.xz
        ln -sfn llvm-mingw-20260421-ucrt-ubuntu-22.04-x86_64 llvm-mingw-20260421-ucrt-macos-universal
        cd ..
        green "Toolchain ready."
    else
        green "Toolchain already present."
    fi

    step "Checking VC++ runtime DLLs..."
    DLLDIR="app/Madeira/x86_64-vcruntime"
    mkdir -p "$DLLDIR"
    NEEDED="concrt140.dll msvcp140.dll msvcp140_1.dll msvcp140_2.dll msvcp140_atomic_wait.dll msvcp140_codecvt_ids.dll vcamp140.dll vccorlib140.dll vcomp140.dll vcruntime140.dll vcruntime140_1.dll vcruntime140_threads.dll"
    missing_dlls=""
    for dll in $NEEDED; do
        [ -f "$DLLDIR/$dll" ] || missing_dlls="$missing_dlls $dll"
    done
    if [ -n "$missing_dlls" ]; then
        yellow "Missing DLLs:$missing_dlls"
        echo "Downloading VC++ runtime DLLs..."
        curl -sL -o msvc-redist.zip https://downloads.hydraulic.dev/msvc-redist/msvc-redist-x64-14.38.32919.zip
        rm -rf vc_extract && mkdir -p vc_extract
        unzip -q -o msvc-redist.zip -d vc_extract
        # Find and copy the 12 DLLs from wherever they ended up
        for dll in $NEEDED; do
            found_dll=$(find vc_extract -iname "$dll" 2>/dev/null | head -1)
            [ -n "$found_dll" ] && cp "$found_dll" "$DLLDIR/"
        done
        rm -rf vc_extract msvc-redist.zip
        # Re-check after download
        missing_dlls=""
        for dll in $NEEDED; do
            [ -f "$DLLDIR/$dll" ] || missing_dlls="$missing_dlls $dll"
        done
        if [ -n "$missing_dlls" ]; then
            yellow "Still missing:$missing_dlls"
            echo "Copy the 12 DLLs manually to:"
            echo "  $(pwd)/$DLLDIR/"
            echo ""
            read -r -p "Press Enter once the DLLs are in place, or Ctrl-C to abort..." _
        else
            green "All 12 VC++ DLLs present."
        fi
    else
        green "All 12 VC++ DLLs present."
    fi

    step "Refreshing licenses..."
    ./build/stage-licenses.sh || die "stage-licenses.sh failed."
fi

# ── 3. Submodule verification ─────────────────────────────────────────

check_submodule() {
    local path="$1" expected="$2"
    local actual
    actual=$(git -C "$path" rev-parse HEAD 2>/dev/null) || die "Submodule $path not initialized. Run: git submodule update --init --recursive"
    if [ "$actual" != "$expected" ]; then
        yellow "WARNING: $path is at $actual, expected $expected"
        read -r -p "Continue anyway? [y/N] " ans
        [[ "$ans" == [yY] ]] || die "Aborted."
    else
        green "$path OK ($actual)"
    fi
}

check_submodule "FEX"            "0f8edf8f6383ae8085e0ffac511c789cdae97514"
check_submodule "wine"           "723d1bf5132768276cea9bc35ab59c83557bb5fb"
check_submodule "research/dxmt"  "ca8a2516d819e7e1f366981825ad1f0d26f80fdd"

# ── 4. FEX iOS static libraries ───────────────────────────────────────
step "Building FEX iOS static libraries (this takes a while)..."
# Patch: fix FEX build for macOS
# - Set target processor (needed on Intel Macs)
# - Disable native CPU detection (reads /proc/cpuinfo, Linux-only)
# - Define FEX_IOS_HOST (enables iOS-specific code in FEX)
if [ -f "build/fex-ios/build.sh" ]; then
    sed -i '' 's/-DCMAKE_SYSTEM_NAME=iOS/-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64/' build/fex-ios/build.sh 2>/dev/null || \
    sed -i 's/-DCMAKE_SYSTEM_NAME=iOS/-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64/' build/fex-ios/build.sh
    sed -i '' 's/-DENABLE_CLANG_THUNKS=ON/-DENABLE_CLANG_THUNKS=ON -DTUNE_CPU=none -DTUNE_ARCH=generic -DFEX_IOS_HOST_BUILD=ON -DCMAKE_C_FLAGS=-DFEX_IOS_HOST -DCMAKE_CXX_FLAGS=-DFEX_IOS_HOST -DCMAKE_ASM_FLAGS=-DFEX_IOS_HOST/' build/fex-ios/build.sh 2>/dev/null || \
    sed -i 's/-DENABLE_CLANG_THUNKS=ON/-DENABLE_CLANG_THUNKS=ON -DTUNE_CPU=none -DTUNE_ARCH=generic -DFEX_IOS_HOST_BUILD=ON -DCMAKE_C_FLAGS=-DFEX_IOS_HOST -DCMAKE_CXX_FLAGS=-DFEX_IOS_HOST -DCMAKE_ASM_FLAGS=-DFEX_IOS_HOST/' build/fex-ios/build.sh
fi
./build/fex-ios/build.sh || die "FEX iOS build failed."

# ── 5. Wine Unix libraries ────────────────────────────────────────────
step "Building Wine Unix libraries..."
for component in ntdll-unix win32u-unix wineserver; do
    if [ -x "build/$component/build.sh" ]; then
        echo "Building $component..."
        "./build/$component/build.sh" || die "$component build failed."
    else
        yellow "No build.sh in build/$component/ — check its README for manual steps."
        ls "build/$component/"
        read -r -p "Press Enter once $component is built, or Ctrl-C to abort..." _
    fi
done

# ── 6. DXMT combined library ──────────────────────────────────────────
step "Building DXMT combined iOS library..."
./build/dxmt-ios/build.sh || die "DXMT iOS build failed."

# ── 7. Verify all expected archives ───────────────────────────────────
step "Verifying all expected static libraries..."
missing=0
for lib in \
    libFEXCore.a libFEXCore_Base.a libJemallocLibs.a \
    libcephes_128bit.a libfmt.a libxxhash.a libsoftfloat_3e.a \
    libntdll_unix.a libwin32u_unix.a libwineserver.a \
    app/Madeira/libdxmt_combined.a \
    ; do
    found=$(find . -name "$lib" -not -path "*/node_modules/*" 2>/dev/null | head -1)
    if [ -z "$found" ]; then
        red "MISSING: $lib"
        missing=1
    else
        green "Found: $found"
    fi
done
[ "$missing" -eq 0 ] || die "Some libraries are missing. Fix the failed builds above."

# ── 8. Xcode build (Debug) ────────────────────────────────────────────
step "Running Xcode build (Debug scheme)..."
xcodebuild \
  -project app/Madeira.xcodeproj \
  -scheme Madeira \
  -destination 'generic/platform=iOS' \
  -derivedDataPath ./build-output \
  -allowProvisioningUpdates \
  build || die "Xcode build failed."

APP_PATH="./build-output/Build/Products/Debug-iphoneos/Madeira.app"
[ -d "$APP_PATH" ] || die "Build succeeded but .app not found at $APP_PATH"

# ── Package as .ipa ──────────────────────────────────────────────────
step "Packaging .ipa..."
IPA_PATH="./build-output/Madeira-iOS.ipa"
rm -rf ./build-output/Payload ./build-output/Madeira-iOS.ipa
mkdir -p ./build-output/Payload
cp -R "$APP_PATH" ./build-output/Payload/
(cd ./build-output && zip -qr Madeira-iOS.ipa Payload)
rm -rf ./build-output/Payload
[ -f "$IPA_PATH" ] || die "Failed to create .ipa"
green "IPA ready: $IPA_PATH"

green ""
green "==================================="
green " BUILD COMPLETE (iOS)"
green "==================================="
green ""
echo "Your files:"
green "  App: $APP_PATH"
green "  IPA: $IPA_PATH"
echo ""
echo "To install the .app directly:"
echo "  xcrun devicectl device install app --device <your-iphone-udid> \"$APP_PATH\""
echo ""
echo "Or sideload the .ipa with Sideloadly, AltStore, or:"
echo "  xcrun devicectl device install app --device <your-iphone-udid> \"$IPA_PATH\""
echo ""
echo "Then attach StikDebug for JIT — the app won't run without it."
