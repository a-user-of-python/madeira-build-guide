# Building Madeira

## You need
- A Mac with Xcode
- An iPhone on iOS 17 or newer

## Steps

```bash
# Clone the source code with all submodules
git clone --recurse-submodules https://github.com/willfaust/madeira.git
cd madeira
```

```bash
# Download the compiler toolchain (needed to build Windows components)
mkdir -p toolchains && cd toolchains
curl -sL -o llvm-mingw.tar.xz https://github.com/mstorsjo/llvm-mingw/releases/download/20260421/llvm-mingw-20260421-ucrt-ubuntu-22.04-x86_64.tar.xz
tar -xf llvm-mingw.tar.xz
ln -s llvm-mingw-20260421-ucrt-ubuntu-22.04-x86_64 llvm-mingw-20260421-ucrt-macos-universal
cd ..
```

```bash
# Download Microsoft's VC++ runtime and extract these 12 DLLs to app/Madeira/x86_64-vcruntime/:
# concrt140.dll msvcp140.dll msvcp140_1.dll msvcp140_2.dll
# msvcp140_atomic_wait.dll msvcp140_codecvt_ids.dll vcamp140.dll vccorlib140.dll
# vcomp140.dll vcruntime140.dll vcruntime140_1.dll vcruntime140_threads.dll
curl -sL -o vc_redist.x64.exe https://aka.ms/vs/17/release/vc_redist.x64.exe
# (extract with 7-Zip, then copy the DLLs)
```

```bash
# Refresh the license files
./build/stage-licenses.sh
```

```bash
# Build the FEX emulation libraries for iOS
./build/fex-ios/build.sh
```

```bash
# Build the Wine libraries (run each one)
./build/ntdll-unix/build.sh
./build/win32u-unix/build.sh
./build/wineserver/build.sh
```

```bash
# Build the DXMT graphics library for iOS
./build/dxmt-ios/build.sh
```

```bash
# Build the final app for iPhone (use Debug — Release crashes)
xcodebuild -project app/Madeira.xcodeproj -scheme Madeira -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

```bash
# Or build for iPad instead
xcodebuild -project app/Madeira.xcodeproj -scheme Madeira -destination 'generic/platform=iPadOS' -allowProvisioningUpdates build
```

## Sideload it
The build does NOT install to your device automatically. To install:

```bash
# Find your device's UDID in Xcode > Window > Devices and Simulators,
# then install with:
xcrun devicectl device install app --device <your-device-udid> <path-to-Madeira.app>
```

Or open Xcode > Window > Devices and Simulators, select your device, and drag the `.app` onto it.

Then attach StikDebug so the app gets JIT access — it won't run without it.

## Or run it all at once
- `scripts/mac-build.sh` — does every step automatically for iPhone
- `scripts/mac-build-ipados.sh` — same but targets iPad
