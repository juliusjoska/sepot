# Verifying Šepot

This document lists what you can check yourself today, how to do it, and what
cannot be checked yet. If something here does not match what you observe,
please report it to security@sepot.cz.

## 1. Which relay code is running

The relay announces its source and revision:

```sh
curl -s https://relay.sepot.cz/v1/server-info
# {"source":"https://github.com/juliusjoska/sepot","revision":"<commit>", ...}
```

The revision is baked into the container image at build time
(`deploy/relay/Dockerfile`, build argument `GIT_SHA`, also stored as the OCI
label `org.opencontainers.image.revision`). To read the code behind it:

```sh
git clone https://github.com/juliusjoska/sepot && cd sepot
git show --stat <commit>
git log --oneline <commit> -- rust/ proto/ deploy/relay/
```

**Current state (October 2026).** The relay deployed on 9 October 2026 reports
`4b3f4bb`. That is a commit of our private development repository, so GitHub
does not know it. The public commit with the same relay code is
[`b824f62`](https://github.com/juliusjoska/sepot/commit/b824f628788afa3e1a3b64fa90de1fc7bf50feaf).
The two trees differ only in source comments, test fixture IP addresses in
`push.rs`, the `repository` URL in `rust/Cargo.toml`, and migration
`0001_init.sql`, which in the private tree already contained the
`attempt_count` column that `0003_queue_attempt_count.sql` adds with
`ADD COLUMN IF NOT EXISTS`. The resulting schema and behaviour are the same.

**From the next relay deployment on**, images are built from this public
repository only. The build script refuses a commit that is not on `main` here
and not yet mirrored to GitHub, and refuses to build when the relay sources in
the public and the development repository differ. The reported revision is
then a full commit hash you can open on GitHub.

What this does *not* prove: the revision is reported by the server itself.
There is no remote attestation, so you are trusting us that the binary was
built from that commit. The relay is designed so that this trust matters as
little as possible: message content is end-to-end encrypted on your device and
the relay never holds the keys.

## 2. Android APK

Direct downloads are attached to the
[GitHub releases](https://github.com/juliusjoska/sepot/releases), together
with a `SHA256SUMS` file.

Since 1.2.1 the APK on GitHub is the universal APK that Google Play generates
from the same app bundle it serves to Play users, signed with the same key.
That means:

- it installs over the Google Play version and vice versa, and
- its signing certificate must be:

```
SHA-256: 9B:4C:DA:44:A1:80:81:26:3D:79:86:01:2B:9D:11:CA:72:AB:D0:24:9C:D9:DC:AB:82:5F:BE:AE:95:40:2D:02
apksigner prints it as 9b4cda44a18081263d7986012b9d11ca72abd0249cd9dcab825fbeae95402d02
```

Check a download:

```sh
sha256sum -c sepot-1.2.1-SHA256SUMS.txt
apksigner verify --print-certs sepot-1.2.1-universal.apk | grep 'SHA-256'
```

Check the app already installed on your phone (USB debugging enabled):

```sh
adb pull "$(adb shell pm path cz.sepot.sepot | head -1 | cut -d: -f2)" installed.apk
apksigner verify --print-certs installed.apk | grep 'SHA-256'
```

**Older direct APKs (1.1.1 and earlier)** were signed with our upload key
(`E2:13:D6:60:63:B9:0E:A1:73:90:1C:37:9E:4B:43:9C:76:8A:F1:AF:C2:D6:55:68:CC:46:CF:31:36:72:3F:31`).
Android will not update such an install with the 1.2.1 APK. Write down your
24-word recovery phrase, uninstall, install the new APK and restore the
account from the phrase. Message history is not carried over.

Source of each release is the tag of the same name (`v1.2.1`, …). The public
tree is an export of our development tree: comments are rewritten, deployment
configuration is left out, and so is a store-screenshot demo mode. That mode
is behind a compile-time flag (`SEPOT_DEMO`) that is not set for release
builds, so the compiler removes it.

## 3. Native cryptography library

End-to-end encryption uses [libsignal](https://github.com/signalapp/libsignal)
through the Dart package [`libsignal`](https://pub.dev/packages/libsignal)
(5.0.9 at the moment). The Dart package itself is pinned by its SHA-256 in
`app/pubspec.lock`. Its build hook downloads a prebuilt native library,
`libsignal_frb`, from the GitHub releases of
[djx-y-z/libsignal_dart](https://github.com/djx-y-z/libsignal_dart) and only
compares it with a checksum file from the same release.

We pin those binaries ourselves in
[`app/tool/native_libs.sha256`](../app/tool/native_libs.sha256): the upstream
archives and the library exactly as it ends up in the APK (the Android Gradle
plugin strips it while packaging). Our release build runs
`app/tool/verify_native_libs.sh` on the finished bundle and does not ship it on
any mismatch.

You can repeat both checks:

```sh
# the library inside an APK or AAB matches the pins
app/tool/verify_native_libs.sh sepot-1.2.1-universal.apk

# the pins follow from the upstream release: download, check archive hashes,
# strip with llvm-strip from the Android NDK and compare
LLVM_STRIP=/path/to/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip \
  app/tool/verify_native_libs.sh --from-upstream
```

## 4. What is not reproducible (yet)

- **Android builds are not bit-for-bit reproducible.** A build from the tag
  gives you a working app, but not the same bytes: the Flutter AOT snapshot
  depends on the build environment, and Google Play re-signs and splits our
  bundle. Today you can compare the signing certificate, the APK hash between
  download channels, and the native crypto library. You cannot compare the
  compiled Dart code against your own build.
- **`libsignal_frb` is a third-party prebuilt binary.** The pins guarantee
  that every build ships the same file and that the file is the published
  upstream release. They do not prove that the release was built from the
  `libsignal_frb` source; the upstream release has no build provenance
  attestation.
- **iOS** binaries from the App Store are encrypted by Apple and cannot be
  compared with anything.
- **The relay image** is not reproducible either: the base images are
  referenced by tag and the build applies current Debian security updates.

## 5. Plan

1. Relay revision equal to a public commit: build tooling is in place, the next
   relay deployment will report it.
2. Build `libsignal_frb` from source on our own build server together with the
   upgrade to the current libsignal release, and publish the resulting hashes
   next to the pins above.
3. Relay: pin base images by digest and publish the image digest with each
   relay deployment.
4. Work towards a reproducible Android build that independent rebuilders
   (for example F-Droid) can confirm.
