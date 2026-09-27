#!/bin/bash
# ipados-build.sh — Automates the Mac-only steps of the Madeira build for iPad.
# Same steps as ios-build.sh but targets iPadOS.
# Run this from ANYWHERE on your Mac — it finds (or clones) the madeira repo itself.
# Parts 1-4 of the README (toolchain, VC++ DLLs, licenses) still need to be
# done inside the repo first, OR pass --full to have the script do them too.
#
# Usage:
#   ./ipados-build.sh                     # find existing madeira checkout
#   ./ipados-build.sh --madeira-dir ~/src/madeira
#   ./ipados-build.sh --full              # clone + toolchain + DLLs + licenses, all automatic
#
# This script will:
#   1. Verify Xcode and iPhoneOS SDK are present
#   2. Locate (or clone) the madeira repo
#   3. Verify submodule commits match the pinned versions
#   4. Build FEX iOS static libraries
#   5. Build Wine Unix libraries
#   6. Build DXMT combined library
#   7. Verify all expected archives exist
#   8. Run the Debug Xcode build (iPadOS)
#
# STOP ON FIRST ERROR
set -euo pipefail

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
MADEIRA_DIR=""
FULL_AUTO=0
for arg in "$@"; do
    case "$arg" in
        --madeira-dir=*) MADEIRA_DIR="${arg#*=}" ;;
        --madeira-dir) shift; MADEIRA_DIR="$1" ;;
        --full) FULL_AUTO=1 ;;
    esac
done

# ── 2. Locate (or clone) the madeira repo ─────────────────────────────
step "Locating madeira repo..."
find_madeira() {
    # 1. Explicit --madeira-dir or $MADEIRA_DIR
    for d in "$MADEIRA_DIR" "$HOME/madeira" "$HOME/src/madeira" \
             "$HOME/workspace/madeira" "$HOME/Downloads/madeira" \
             "$HOME/Desktop/madeira" "$(pwd)" "$(pwd)/madeira" \
             "$(dirname "$0")" "$(dirname "$0")/.." "$(dirname "$0")/../madeira"; do
        [ -n "$d" ] && [ -d "$d/FEX" ] && [ -d "$d/app" ] && { echo "$d"; return 0; }
    done
    return 1
}

MADEIRA_DIR="${MADEIRA_DIR:-$(find_madeira)}" || true

if [ -z "$MADEIRA_DIR" ]; then
    if [ "$FULL_AUTO" -eq 1 ]; then
        MADEIRA_DIR="$HOME/madeira"
        step "Cloning madeira to $MADEIRA_DIR..."
        git clone --recurse-submodules https://github.com/willfaust/madeira.git "$MADEIRA_DIR" \
            || die "Clone failed."
    else
        red "Could not find a madeira checkout."
        echo ""
        echo "Options:"
        echo "  1. Run with --full to clone it automatically:"
        echo "       $0 --full"
        echo "  2. Point at your existing checkout:"
        echo "       $0 --madeira-dir ~/path/to/madeira"
        exit 1
    fi
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
    NEEDED="concrt140.dll msvcp140.dll msvcp140_1.dll msvcp140_2.dll msvcp140_atomic_wait.dll msvcp140_codecvt_ids.dll vcamp140.dll vccorlib140.dll vcomp140.dll vcruntime140.dll vcruntime140_1.dll vcruntime140_threads.dll"
    missing_dlls=""
    for dll in $NEEDED; do
        [ -f "$DLLDIR/$dll" ] || missing_dlls="$missing_dlls $dll"
    done
    if [ -n "$missing_dlls" ]; then
        yellow "Missing DLLs:$missing_dlls"
        echo "Downloading vc_redist.x64.exe — extract it with 7-Zip/Keka,"
        echo "then copy the 12 DLLs to $DLLDIR/"
        curl -sL -o vc_redist.x64.exe https://aka.ms/vs/17/release/vc_redist.x64.exe
        echo ""
        read -r -p "Press Enter once the DLLs are in place, or Ctrl-C to abort..." _
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

# ── 8. Xcode build (Debug, iPadOS) ────────────────────────────────────
step "Running Xcode build (Debug scheme, iPadOS)..."
xcodebuild \
  -project app/Madeira.xcodeproj \
  -scheme Madeira \
  -destination 'generic/platform=iPadOS' \
  -derivedDataPath ./build-output \
  -allowProvisioningUpdates \
  build || die "Xcode build failed."

APP_PATH="./build-output/Build/Products/Debug-ipadaos/Madeira.app"
[ -d "$APP_PATH" ] || die "Build succeeded but .app not found at $APP_PATH"

green ""
green "==================================="
green " BUILD COMPLETE (iPadOS)"
green "==================================="
green ""
echo "Your app is here:"
green "  $APP_PATH"
echo ""
echo "To install it on your iPad, run:"
echo "  xcrun devicectl device install app --device <your-ipad-udid> \"$APP_PATH\""
echo ""
echo "Or open Xcode > Window > Devices and Simulators, select your iPad,"
echo "and drag the .app onto it."
echo ""
echo "Then attach StikDebug for JIT — the app won't run without it."
