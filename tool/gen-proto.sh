#!/usr/bin/env bash
# Generace wire typů z proto/sepot.proto — Rust řeší build.rs (prost),
# tenhle skript generuje Dart pro app/.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PATH:$HOME/.pub-cache/bin"
mkdir -p app/lib/proto
protoc --dart_out=app/lib/proto -I proto proto/sepot.proto
echo "OK: app/lib/proto/"
