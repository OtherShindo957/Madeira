# Building an unsigned Madeira IPA on GitHub

The workflow uses GitHub's macOS/Xcode runner, so your own machine can run Linux.
This PR is still under build validation: no successful IPA or device test has
been confirmed yet. Read the run's result before treating this as usable.

## Build stages

`scripts/ci/bootstrap-native.sh` builds the native libraries before checking
Xcode's required inputs:

1. FEX static iOS arm64 targets from the pinned submodule.
2. Wine host tools and generated headers from the pinned Wine source.
3. GMP, Nettle and GnuTLS from the committed, checksum-verified source archives.
4. FreeType 2.13.3 and FFmpeg 7.1.1 from pinned commits. FFmpeg enables only the
   WMA/XMA decoders used by Madeira, with GPL/nonfree features disabled.
5. Wineserver from the complete Wine source list with Madeira's replacements,
   plus win32u/FreeType and ntdll/FFmpeg. No pre-existing wineserver archive is
   required. A failed ntdll compilation stops the build rather than archiving
   stale objects.
6. LLVM 15.0.7 host table generator and iOS static libraries, then DXMT and
   iOS Metal shaders combined into the archive expected by Xcode.
7. Native input checks, prefix-template validation, Xcode Release compilation,
   executable architecture verification and `Payload/Madeira.app` packaging.

The existing committed Windows PE modules are reused; this workflow does not
rebuild the PE side or claim to validate their parity with the native source.
The CI app targets **iOS 18 or later**, matching the DXMT build's minimum.

The optional Microsoft x64 VC++ runtime overlay is excluded from the default
Xcode resources: it is absent from this repository and the app bridge already
tolerates its absence. Wine's committed runtime modules remain included.
Games requiring Microsoft's fuller runtime may not work with this artifact.
For a custom build with that overlay, supply the files described in
`tools/fetch-vcruntime.md` and add the folder as an Xcode resource. The workflow
does not download or fabricate those DLLs.

## Running

The PR runs the build for validation. Once the completed PR is merged, use
**Actions → Build Madeira IPA → Run workflow** from any OS. On success download
`Madeira-unsigned`, containing the IPA, SHA-256 and source entitlements.
Sign/sideload separately and enable JIT through the appropriate debugger setup.
No Apple ID, signing certificate or provisioning secret is stored in CI.

Failures upload `madeira-build-logs`, including native configuration/compiler
logs. Each major dependency is a separate step so the failing stage is visible.
The workflow has read-only repository permissions and never deploys or merges.

The preflight is a missing-file/duplicate-ID check, not an ABI or runtime test.
A successful Xcode link still needs physical-device testing, including JIT,
game compatibility and signing entitlements. The liblzma/SteamDevice duplicate
Xcode IDs were fixed in the initial revision of this PR.
