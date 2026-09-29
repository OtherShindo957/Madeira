#!/bin/bash
# Reconstruct the native prerequisites from the repository's pinned sources.
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
jobs="${BUILD_JOBS:-$(sysctl -n hw.ncpu)}"
export PATH="$(brew --prefix llvm)/bin:$(brew --prefix bison)/bin:$PATH"
mkdir -p artifacts toolchains
exec > >(tee -a artifacts/bootstrap.log) 2>&1
trap 'echo "Native bootstrap failed at line $LINENO" >&2' ERR

source_checkout() {
  local url="$1" revision="$2" destination="$3"
  if [[ ! -d "$destination/.git" ]]; then
    git init "$destination"
    git -C "$destination" remote add origin "$url"
    git -C "$destination" fetch --depth 1 origin "$revision"
    git -C "$destination" checkout --detach FETCH_HEAD
  fi
  [[ "$(git -C "$destination" rev-parse HEAD)" == "$revision" ]]
}

case "${1:-}" in
fex)
  # Use bundled libraries so Xcode's existing archive paths stay valid.
  cmake -S FEX -B FEX/build-ios -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_CXX_FLAGS=-include $root/scripts/ci/fex-apple-diagnostics.h" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DBUILD_TESTING=OFF -DBUILD_FEXCONFIG=OFF -DBUILD_THUNKS=OFF \
    -DENABLE_LTO=OFF -DENABLE_CCACHE=OFF -DENABLE_GDB_SYMBOLS=OFF \
    -DENABLE_OFFLINE_TELEMETRY=OFF -DTUNE_CPU=generic \
    -DCMAKE_DISABLE_FIND_PACKAGE_fmt=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_range-v3=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_unordered_dense=TRUE
  cmake --build FEX/build-ios --parallel "$jobs" --target \
    FEXCore FEXCore_Base JemallocLibs fmt cephes_128bit xxhash softfloat_3e
  ;;
wine-headers)
  # Generate host config and IDL headers; PE runtime modules already ship in app/.
  mkdir -p wine/build-macos
  (
    cd wine/build-macos
    CC="$(xcrun -f clang)" ../configure --enable-win64 --enable-archs=none \
      --without-x --without-freetype --without-gnutls --without-gstreamer \
      --without-vulkan
    make -j"$jobs" __tooldeps__
    make -j"$jobs" include/all
  )
  # ntdll's dwrite compilation uses this legacy generated-header location.
  mkdir -p wine/build-arm64ec
  ln -sfn ../build-macos/include wine/build-arm64ec/include
  ;;
crypto)
  (cd build/gnutls-ios/src && shasum -a 256 -c SHA256SUMS)
  bash build/gnutls-ios/build.sh
  for lib in gnutls hogweed nettle gmp; do
    cp "toolchains/gnutls-ios/lib/lib$lib.a" app/Madeira/
  done
  ;;
media)
  source_checkout https://github.com/freetype/freetype.git \
    42608f77f20749dd6ddc9e0536788eaad70ea4b5 research/freetype
  bash build/freetype-ios/build.sh
  source_checkout https://github.com/FFmpeg/FFmpeg.git \
    db69d06eeeab4f46da15030a80d539efb4503ca8 toolchains/ffmpeg
  mkdir -p toolchains/ffmpeg-build
  (
    cd toolchains/ffmpeg-build
    ../ffmpeg/configure --prefix="$root/toolchains/ffmpeg-ios" \
      --target-os=darwin --arch=aarch64 --enable-cross-compile \
      --cc="$(xcrun --sdk iphoneos -f clang)" \
      --sysroot="$(xcrun --sdk iphoneos --show-sdk-path)" \
      --extra-cflags='-arch arm64 -miphoneos-version-min=18.0 -fno-stack-protector' \
      --extra-ldflags='-arch arm64 -miphoneos-version-min=18.0' \
      --disable-everything --disable-autodetect --disable-programs --disable-doc \
      --disable-gpl --disable-nonfree --disable-shared --enable-static \
      --enable-avcodec --enable-avutil --enable-swresample \
      --enable-decoder=wmav1,wmav2,wmapro,wmalossless,xma1,xma2
    make -j"$jobs"
    make install
  )
  ;;
wine-native)
  bash build/wineserver/build.sh
  bash build/win32u-unix/build.sh
  bash build/ntdll-unix/build.sh
  # The WMA replacement calls these static libraries directly.
  xcrun --sdk iphoneos libtool -static -o app/Madeira/libntdll_with_media.a \
    app/Madeira/libntdll_unix.a toolchains/ffmpeg-ios/lib/libavcodec.a \
    toolchains/ffmpeg-ios/lib/libswresample.a toolchains/ffmpeg-ios/lib/libavutil.a
  mv app/Madeira/libntdll_with_media.a app/Madeira/libntdll_unix.a
  ;;
llvm)
  source_checkout https://github.com/llvm/llvm-project.git \
    8dfdcc7b7bf66834a761bd8de445840ef68e4d1a toolchains/llvm-project
  # LLVM 15's linker-GC selection predates CMake's iOS system name.
  python3 - <<'PY'
from pathlib import Path
p = Path('toolchains/llvm-project/llvm/cmake/modules/AddLLVM.cmake')
s = p.read_text()
s = s.replace('MATCHES "Darwin"', 'MATCHES "Darwin|iOS"')
p.write_text(s)
PY
  cmake -S toolchains/llvm-project/llvm -B toolchains/llvm-host-build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DLLVM_TARGETS_TO_BUILD= -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF
  cmake --build toolchains/llvm-host-build --parallel "$jobs" --target llvm-tblgen
  cmake -S toolchains/llvm-project/llvm -B toolchains/llvm-ios-build -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DLLVM_TABLEGEN="$root/toolchains/llvm-host-build/bin/llvm-tblgen" \
    -DLLVM_TARGETS_TO_BUILD= -DLLVM_BUILD_UTILS=OFF -DLLVM_BUILD_TOOLS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_LIBXML2=OFF
  cmake --build toolchains/llvm-ios-build --parallel "$jobs"
  ;;
dxmt)
  xcodebuild -downloadComponent MetalToolchain
  bash build/dxmt-ios/build.sh
  xcrun --sdk iphoneos libtool -static -o app/Madeira/libdxmt_combined.a \
    build/dxmt-ios/obj/*.o toolchains/llvm-ios-build/lib/*.a
  ;;
*) echo 'Usage: bootstrap-native.sh {fex|wine-headers|crypto|media|wine-native|llvm|dxmt}' >&2; exit 2 ;;
esac
