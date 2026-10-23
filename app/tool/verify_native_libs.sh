#!/usr/bin/env bash
# Checks the libsignal native library against the pins in native_libs.sha256.
#
#   verify_native_libs.sh <app.aab|app.apk>   every ABI in the artifact must carry
#                                             exactly the pinned library
#   verify_native_libs.sh --from-upstream     download the upstream archives, check
#                                             their pins and re-derive the shipped
#                                             hashes (needs llvm-strip from the NDK)
#
# Exit code 0 = match, anything else = do not ship.
set -euo pipefail

TOOL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PINS="$TOOL_DIR/native_libs.sha256"
LOCK="$TOOL_DIR/../pubspec.lock"
LIB=liblibsignal_frb.so

die() { echo "verify_native_libs: $*" >&2; exit 1; }
pin() { awk -v k="$1" -v n="$2" '$1 == k && $2 == n { print $3 }' "$PINS"; }

pinned_package=$(pin package libsignal)
[ -n "$pinned_package" ] || die "no package line in $PINS"

# A libsignal upgrade without new pins must stop here with a clear reason,
# not later as an unexplained hash mismatch.
if [ -f "$LOCK" ]; then
  locked=$(awk '/^  libsignal:$/ { f = 1 } f && /^    version:/ { gsub(/"/, "", $2); print $2; exit }' "$LOCK")
  [ "$locked" = "$pinned_package" ] ||
    die "pubspec.lock has libsignal $locked, pins are for $pinned_package — update $PINS"
fi

sha() { sha256sum "$1" | cut -d' ' -f1; }

verify_artifact() {
  local artifact=$1 prefix entries abi want got checked=0
  [ -f "$artifact" ] || die "file not found: $artifact"
  case "$artifact" in
    *.aab) prefix=base/lib ;;
    *.apk) prefix=lib ;;
    *) die "expected .aab or .apk: $artifact" ;;
  esac
  entries=$(unzip -Z1 "$artifact" | grep -E "^$prefix/[^/]+/$LIB\$" || true)
  [ -n "$entries" ] || die "$LIB not found in $artifact"
  for entry in $entries; do
    abi=$(basename "$(dirname "$entry")")
    want=$(pin shipped "$abi")
    [ -n "$want" ] || die "no pin for ABI $abi"
    got=$(unzip -p "$artifact" "$entry" | sha256sum | cut -d' ' -f1)
    [ "$got" = "$want" ] || die "$abi: $got does not match pinned $want"
    echo "ok  $abi  $got"
    checked=$((checked + 1))
  done
  # Every pinned ABI has to be present: a missing one would crash on those devices.
  for abi in $(awk '$1 == "shipped" { print $2 }' "$PINS"); do
    grep -q "^$prefix/$abi/$LIB\$" <<<"$entries" || die "$abi missing in $artifact"
  done
  echo "verify_native_libs: $checked libraries match the pins"
}

from_upstream() {
  local strip=${LLVM_STRIP:-} work version url abi want got
  if [ -z "$strip" ]; then
    strip=$(ls "${ANDROID_HOME:-/opt/android-sdk}"/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-strip 2>/dev/null | sort -V | tail -1)
  fi
  [ -x "$strip" ] || die "llvm-strip not found, set LLVM_STRIP"
  # Archive names carry the version of the native crate, not of the Dart package.
  version=$(sed -n 's/.*releases\/tag\/libsignal_frb-\([0-9.]*\).*/\1/p' "$PINS" | head -1)
  [ -n "$version" ] || die "no release tag in $PINS"
  url="https://github.com/djx-y-z/libsignal_dart/releases/download/libsignal_frb-$version"
  work=$(mktemp -d); trap 'rm -rf "$work"' RETURN
  for abi in $(awk '$1 == "shipped" { print $2 }' "$PINS"); do
    curl -fsSL -o "$work/$abi.tar.gz" "$url/libsignal_frb-$version-android-$abi.tar.gz"
    want=$(pin archive "android-$abi"); got=$(sha "$work/$abi.tar.gz")
    [ "$got" = "$want" ] || die "archive android-$abi: $got does not match pinned $want"
    mkdir "$work/$abi" && tar -xzf "$work/$abi.tar.gz" -C "$work/$abi" "$LIB"
    "$strip" --strip-unneeded "$work/$abi/$LIB"
    want=$(pin shipped "$abi"); got=$(sha "$work/$abi/$LIB")
    [ "$got" = "$want" ] || die "stripped $abi: $got does not match pinned $want"
    echo "ok  $abi  archive and stripped library match"
  done
}

case "${1:-}" in
  --from-upstream) from_upstream ;;
  ""|-h|--help) sed -n '2,10p' "$0"; exit 64 ;;
  *) verify_artifact "$1" ;;
esac
