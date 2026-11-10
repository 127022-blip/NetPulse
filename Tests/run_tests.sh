#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$ROOT/.." && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUT="$ROOT/.test_bin"
# 生产 TrafficLogic + 单测，禁止双份拷贝
swiftc -O -target arm64-apple-macosx13.0 -sdk "$SDK" \
  "$SRC/NetPulse/Utilities/TrafficLogic.swift" \
  "$ROOT/TrafficLogicTests.swift" -o "$OUT"
"$OUT"
rm -f "$OUT"
