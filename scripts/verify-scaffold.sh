#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -f "$ROOT/apps/macos/SayItFlow/SayItFlowApp.swift"
test -f "$ROOT/apps/macos/SayItFlow/Core/VozEngine.swift"
echo "SayItFlow scaffold OK"
