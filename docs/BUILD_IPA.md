# Unsigned IPA workflow — draft, currently blocked

This is packaging infrastructure, **not yet a working clean-checkout builder**.
No IPA has been produced or device-tested by this change. A fresh checkout fails
preflight intentionally and uploads a report; it does not upload a placeholder IPA.
Linux users will be able to use GitHub's macOS runner once the native build is
made reproducible. No Apple credentials are needed for unsigned packaging.

## Confirmed blockers at the initial main snapshot

- Seven FEX static archives under `FEX/build-ios/` are absent. The generated
  FEX headers also need the correct iOS CMake configuration.
- `app/Madeira/libwineserver.a` is absent. `build/wineserver/build.sh` patches
  an existing base archive and explicitly fails if it does not already exist.
  It is not a bootstrap script.
- `libntdll_unix.a` and `libwin32u_unix.a` are absent. Their scripts depend on
  generated Wine headers in `wine/build-macos` and `wine/build-arm64ec`.
- `libdxmt_combined.a` is absent. The committed `app/libdxmt_unix.a` is a
  different archive, not a replacement. See `build/dxmt-ios/README.md` for
  the host/iOS LLVM 15.0.7 builds and the combined archive procedure.
- FreeType source is an uncommitted checkout; its script documents 2.13.3.
- The ntdll WMA implementation needs `toolchains/ffmpeg-ios`. Its referenced
  `.xtool/build-ffmpeg.sh` is absent and `.xtool/` is ignored.
- `app/Madeira/x86_64-vcruntime` is absent; see `tools/fetch-vcruntime.md`.
  This workflow neither downloads those DLLs nor creates empty substitutes.
The duplicate Xcode IDs previously shared by liblzma and SteamDevice are
fixed in this PR by assigning liblzma unique IDs and updating its references.

The preflight reads archive/resource references from the actual project and
checks duplicate IDs. It does not establish ABI compatibility, symbol coverage,
submodule availability or correctness of generated headers. Passing it alone
is not proof that the app builds or runs.

## Finishing the native bootstrap

Add a source-pinned dependency build that runs before preflight on the macOS
runner. Restore the missing base wineserver recipe, Wine configuration/header
steps, FEX iOS configuration, LLVM/DXMT combination and FFmpeg recipe. Use the
submodule commits recorded by this fork (its `.gitmodules` points to `125hz`
forks), not arbitrary upstream branches. Decide explicitly how to supply the
runtime resources. Do not fetch unversioned binary bundles to hide these gaps.
The current preflight on Ubuntu is a cheap diagnostic while this work is open;
move the dependency-dependent checks after the bootstrap when it is implemented.

## Using the workflow once those blockers are resolved

1. Merge the completed workflow into the default branch so GitHub exposes
   **Actions → Build Madeira IPA → Run workflow**.
2. Run it and wait for the macOS build to succeed.
3. Download `Madeira-unsigned` from the run's Artifacts section and unzip it.
   It contains `Madeira-unsigned.ipa`, its SHA-256 and the source entitlements.
4. Sign/sideload the IPA separately. The archive is deliberately unsigned;
   signing and JIT/debugger attachment remain separate device requirements.

The shell script uses the existing Madeira target, builds Release for iphoneos
arm64 with signing disabled, verifies the executable architecture, and packages
`Payload/Madeira.app`. It retains the Xcode log even when compilation fails.
It can also be run on a prepared Mac with:

```sh
bash scripts/ci/build-unsigned-ipa.sh
```

Local validation for this draft: shell syntax, YAML structure, and preflight on
an unmodified clean-checkout dependency set. Full compilation requires the
missing native inputs and a macOS runner; it has not been validated here.
