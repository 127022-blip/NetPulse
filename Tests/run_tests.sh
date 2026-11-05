#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUT="$ROOT/.test_bin"
swiftc -O -target arm64-apple-macosx13.0 -sdk "$SDK" \
  "$ROOT/TrafficLogicTests.swift" -o "$OUT"
"$OUT"
rm -f "$OUT"
