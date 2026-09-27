#!/bin/bash
# mac-build-ipados.sh — Automates the Mac-only steps of the Madeira build for iPad.
# Same as mac-build.sh but targets iPadOS.
# Run this on your Mac after cloning willfaust/madeira and completing
# Parts 1-4 of the README (clone, toolchain, VC++ DLLs, licenses).
#
# Usage: ./mac-build-ipados.sh
#
# This script will:
#   1. Verify Xcode and iPhoneOS SDK are present
#   2. Verify submodule commits match the pinned versions
#   3. Build FEX iOS static libraries
#   4. Build Wine Unix libraries
#   5. Build DXMT combined library
#   6. Verify all expected archives exist
#   7. Run the Debug Xcode build
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

# ── 2. Submodule verification ─────────────────────────────────────────
step "Verifying submodule commits..."
cd "$(dirname "$0")"
# Expect to be run from the madeira repo root or its parent
if [ ! -d "FEX" ]; then
    die "Run this from the madeira repo root (the directory containing FEX/, wine/, app/)."
fi

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

# ── 3. FEX iOS static libraries ───────────────────────────────────────
step "Building FEX iOS static libraries (this takes a while)..."
./build/fex-ios/build.sh || die "FEX iOS build failed."

# ── 4. Wine Unix libraries ────────────────────────────────────────────
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

# ── 5. DXMT combined library ──────────────────────────────────────────
step "Building DXMT combined iOS library..."
./build/dxmt-ios/build.sh || die "DXMT iOS build failed."

# ── 6. Verify all expected archives ───────────────────────────────────
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

# ── 7. Xcode build (Debug, iPadOS) ────────────────────────────────────
step "Running Xcode build (Debug scheme, iPadOS)..."
xcodebuild \
  -project app/Madeira.xcodeproj \
  -scheme Madeira \
  -destination 'generic/platform=iPadOS' \
  -allowProvisioningUpdates \
  build || die "Xcode build failed."

green ""
green "==================================="
green " BUILD COMPLETE (iPadOS)"
green "==================================="
green ""
echo "The .app is in the build output folder (see Xcode build log for path)."
echo ""
echo "To install it on your iPad, run:"
echo "  xcrun devicectl device install app --device <your-ipad-udid> <path-to-Madeira.app>"
echo ""
echo "Or open Xcode > Window > Devices and Simulators, select your iPad,"
echo "and drag the .app onto it."
echo ""
echo "Then attach StikDebug for JIT — the app won't run without it."
