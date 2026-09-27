# Building Madeira (willfaust/madeira)

A complete guide to building the Madeira iOS app — FEX emulation + Wine + DXMT on iOS.

## What is this?

Madeira runs Windows games on iOS by combining:
- **FEX** — x86_64 emulation (ARM64EC)
- **Wine** — Windows API compatibility
- **DXMT** — DirectX-to-Metal translation

## Requirements

- **Mac** with Xcode installed
- **iPhone** running iOS 17+ (A15 chip or newer recommended)
  - ⚠️ iPhone 7 (iOS 15 max) **cannot** run this
- **StikDebug** (or equivalent) for JIT attachment — the app needs JIT
- Free Apple ID works for signing (expires every 7 days, must re-sideload)

## Part 1: Clone and prepare

```bash
# Clone with all submodules
git clone --recurse-submodules https://github.com/willfaust/madeira.git
cd madeira

# Verify submodule commits
git submodule status
# Should show:
#  0f8edf8... FEX
#  723d1bf... wine
#  ca8a251... research/dxmt
```

## Part 2: Get the toolchain

Download LLVM-MinGW (ARM64EC-capable):

```bash
mkdir -p toolchains
cd toolchains
curl -sL -o llvm-mingw.tar.xz \
  https://github.com/mstorsjo/llvm-mingw/releases/download/20260421/llvm-mingw-20260421-ucrt-ubuntu-22.04-x86_64.tar.xz
tar -xf llvm-mingw.tar.xz
# The build scripts expect the macOS directory name:
ln -s llvm-mingw-20260421-ucrt-ubuntu-22.04-x86_64 \
      llvm-mingw-20260421-ucrt-macos-universal
cd ..
```

Verify it works:
```bash
TC=toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin
$TC/arm64ec-w64-mingw32-clang --version
```

## Part 3: VC++ runtime DLLs

Download Microsoft's VC++ redistributable and extract the x64 DLLs:

```bash
curl -sL -o vc_redist.x64.exe https://aka.ms/vs/17/release/vc_redist.x64.exe
# Extract with 7-Zip, then copy these to app/Madeira/x86_64-vcruntime/:
#   concrt140.dll, msvcp140.dll, msvcp140_1.dll, msvcp140_2.dll,
#   msvcp140_atomic_wait.dll, msvcp140_codecvt_ids.dll, vcamp140.dll,
#   vccorlib140.dll, vcomp140.dll, vcruntime140.dll,
#   vcruntime140_1.dll, vcruntime140_threads.dll
```

## Part 4: Refresh licenses

```bash
./build/stage-licenses.sh
```

## Part 5: Build iOS components (Mac only)

These **require macOS + Xcode + iPhoneOS SDK**. They cannot be built on Linux.

### 5a. FEX iOS static libraries
```bash
./build/fex-ios/build.sh
```
Produces: `libFEXCore.a`, `libFEXCore_Base.a`, `libJemallocLibs.a`,
`libcephes_128bit.a`, `libfmt.a`, `libxxhash.a`, `libsoftfloat_3e.a`

### 5b. Wine Unix libraries
```bash
# Check each directory for its build script:
ls build/ntdll-unix/ build/win32u-unix/ build/wineserver/
# Run each build per its README
```
Produces: `libntdll_unix.a`, `libwin32u_unix.a`, `libwineserver.a`

### 5c. DXMT combined library
```bash
./build/dxmt-ios/build.sh
```
Merges `app/libdxmt_unix.a` + LLVM archives into
`app/Madeira/libdxmt_combined.a` via `xcrun -sdk iphoneos libtool`.

## Part 6: Windows ARM64EC components

**Good news:** these are already built and committed in the repo at
`app/Madeira/arm64ec-windows/` — all verified as valid ARM64EC:
- `xtajit64.dll` (FEX JIT)
- `ntdll.dll` (correctly padded: SizeOfImage + 0x50000)
- `winemetal.dll` (DXMT/Metal)
- `madeira_d3d12.dll`
- Full Wine DLL set + `aarch64-windows/` variants

If you ever need to rebuild them, see `scripts/build.sh` in this repo
— it's the fixed version of `build/fex-arm64ec/build.sh` with three
required fixes (see "Build script fixes" below).

## Part 7: Final Xcode build

```bash
xcodebuild \
  -project app/Madeira.xcodeproj \
  -scheme Madeira \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

**Use the Debug scheme.** Release builds are known to crash the guest.

Then sideload the `.app` to your device and attach StikDebug for JIT.

## Build script fixes

The upstream `build/fex-arm64ec/build.sh` is missing three things.
The fixed version is in `scripts/build.sh`:

1. **`-DMINGW_TRIPLE=arm64ec-w64-mingw32`** — without it, CMake looks
   for a compiler literally named `-clang++`.
2. **`-DFEX_IOS_HOST_BUILD=ON`** — selects the correct link path for
   the iOS-host build.
3. **`-DFEX_IOS_HOST` in C/CXX/ASM flags** — the fork's code expects
   this preprocessor define for PE builds. The `.S` assembly files need
   it via `CMAKE_ASM_FLAGS`; without it, `Module.S` emits
   `#SyncThreadContext` references that don't resolve.

## Pre-prepared environment

A Linux sandbox was used to prepare everything up to the Mac-only steps:
- All submodules verified at pinned commits
- Toolchain downloaded and tested (ARM64EC output confirmed)
- VC++ DLLs extracted and staged
- All prebuilt Windows DLLs verified valid (`coff-arm64ec`)
- Licenses refreshed

See `docs/HANDOFF.md` for the full preparation log.

## Known limitations

- Targets `arm64-apple-ios17.0` — needs iOS 17+ device
- Requires JIT via debugger attachment (StikDebug)
- Free signing expires every 7 days
- The author's own BUILDING.md notes the full clean-machine build was
  never verified end-to-end
- This is a research project with rough edges, not a polished product
