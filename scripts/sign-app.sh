#!/bin/bash
# Sign nested Sparkle code before the outer app. Do not use --deep to sign.
set -euo pipefail
bundle="${1:?Bundle required}"
identity="${2:?Signing identity required}"
shift 2
framework="$bundle/Contents/Frameworks/Sparkle.framework"
args=(--force --sign "$identity" --timestamp=none "$@")
if [[ -d "$framework" ]]; then
    # Preserve upstream entitlements for helpers; the app is not sandboxed.
    while IFS= read -r -d '' path; do
        codesign "${args[@]}" --preserve-metadata=identifier,entitlements "$path"
    done < <(find "$framework" -type f -perm +111 -print0)
    while IFS= read -r -d '' path; do
        codesign "${args[@]}" --preserve-metadata=identifier,entitlements "$path"
    done < <(find "$framework" -depth -type d \( -name '*.app' -o -name '*.xpc' \) -print0)
    codesign "${args[@]}" "$framework"
fi
codesign "${args[@]}" "$bundle"
codesign --verify --deep --strict "$bundle"
