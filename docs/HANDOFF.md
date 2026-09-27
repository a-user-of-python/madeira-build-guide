# Madeira Build Handoff — 2026-09-27

## What I did (Linux sandbox)

Everything that *can* be done without macOS is done. The repo is at
`~/workspace/madeira/src/` with all submodules at their pinned commits:

- FEX: `0f8edf8f6383ae8085e0ffac511c789cdae97514`
- wine: `723d1bf5132768276cea9bc35ab59c83557bb5fb`
- research/dxmt: `ca8a2516d819e7e1f366981825ad1f0d26f80fdd`

### Completed and verified

1. **LLVM-MinGW toolchain** (`20260421`, ARM64EC-capable) at
   `src/toolchains/llvm-mingw-20260421-ucrt-macos-universal/`
   (symlink to the extracted `ubuntu-22.04-x86_64` dir; the build scripts
   hardcode the `-macos-universal` name).

2. **VC++ redistributable DLLs** staged at
   `src/app/Madeira/x86_64-vcruntime/` (12 DLLs, from the official
   Microsoft `vc_redist.x64.exe`).

3. **Licenses refreshed** via `./build/stage-licenses.sh`.

4. **All Windows ARM64EC DLLs verified present and valid** in
   `src/app/Madeira/arm64ec-windows/` — every one checked as
   `coff-arm64ec` via llvm-objdump:
   - `xtajit64.dll` (FEX), `ntdll.dll` (correctly padded:
     SizeOfImage 0x130000 + 0x50000 = file size 0x180000),
     `winemetal.dll` (DXMT), `madeira_d3d12.dll`, `kernel32.dll`, etc.
   - `aarch64-windows/` also fully populated.

5. **iOS static libs already in repo**: `libgmp.a`, `libgnutls.a`,
   `libhogweed.a`, `libnettle.a` (GnuTLS) and `app/libdxmt_unix.a`.

### Build-script fixes (kept in the repo)

`src/build/fex-arm64ec/build.sh` was missing three things the fork's
build needs; all added:
- `-DMINGW_TRIPLE=arm64ec-w64-mingw32` (without it, CMake looks for
  literally `-clang++`)
- `-DFEX_IOS_HOST_BUILD=ON`
- `-DFEX_IOS_HOST` in C/CXX/ASM flags (the `.S` files need it via
  `CMAKE_ASM_FLAGS` — without it, `Module.S` emits `#SyncThreadContext`
  references that don't resolve)

Note: a from-scratch FEX ARM64EC link still fails on this Linux box —
the 20260421 llvm-mingw emits `__gxx_personality_seh0` references that
no shipped library provides. The repo's prebuilt `xtajit64.dll` is
valid, so rebuilding it is unnecessary.

## What needs your Mac

These can't be built on Linux (need Xcode + iPhoneOS SDK):

1. **FEX iOS static libs** → `src/build/fex-ios/build.sh`
   Produces: `libFEXCore.a`, `libFEXCore_Base.a`, `libJemallocLibs.a`,
   `libcephes_128bit.a`, `libfmt.a`, `libxxhash.a`, `libsoftfloat_3e.a`

2. **Wine Unix libs** → `src/build/ntdll-unix/`, `src/build/win32u-unix/`,
   `src/build/wineserver/` (check each dir's README/build.sh)
   Produces: `libntdll_unix.a`, `libwin32u_unix.a`, `libwineserver.a`

3. **DXMT combined lib** → `src/build/dxmt-ios/build.sh`
   Merges `app/libdxmt_unix.a` + LLVM archives into
   `app/Madeira/libdxmt_combined.a` via `xcrun -sdk iphoneos libtool`.

4. **Final Xcode build**:
   ```
   cd src
   xcodebuild -project app/Madeira.xcodeproj -scheme Madeira \
     -destination 'generic/platform=iOS' -allowProvisioningUpdates build
   ```
   Use **Debug** (Release is known to crash the guest).

## Constraints to keep in mind

- Targets `arm64-apple-ios17.0`; needs a device that runs iOS 17+
  (iPhone 13 Pro/A15 was the dev machine).
- Requires JIT — attach via StikDebug (or equivalent debugger).
- Free Apple signing works but expires every 7 days; sideload, not App Store.
- This is a rough research project; the full clean-machine build was
  never verified end-to-end by the author either.
