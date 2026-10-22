#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
# SwiftPM stores binary artifacts here; use the resolved version's own tools.
framework="$project_dir/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$framework" ]]; then
    printf '%s\n' 'Resolved Sparkle framework is missing. Run swift package resolve first.' >&2
    exit 1
fi
case "${1:-framework}" in
    framework) printf '%s\n' "$framework" ;;
    bin) printf '%s\n' "$project_dir/.build/artifacts/sparkle/Sparkle/bin" ;;
    *) exit 1 ;;
esac
