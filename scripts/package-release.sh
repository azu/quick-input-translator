#!/bin/bash
# Explicit ad-hoc release packaging, isolated from the locally signed app.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
version="$(bash scripts/version.sh)"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    printf '%s\n' 'Release packaging requires an Apple Silicon Mac.' >&2
    exit 1
fi
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p dist
staging_dir="$(mktemp -d "$project_dir/dist/.release.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
bundle="$staging_dir/Quick Input Translator.app"
bash scripts/assemble-app.sh "$bundle" "$binary_dir/QuickTranslateInput"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
archive="quick-input-translator-macos-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$staging_dir/$archive"
# Verify the archive before publishing it, including its signature and version.
ditto -x -k "$staging_dir/$archive" "$staging_dir/unpacked"
codesign --verify --strict "$staging_dir/unpacked/Quick Input Translator.app"
actual_version="$(plutil -extract CFBundleShortVersionString raw "$staging_dir/unpacked/Quick Input Translator.app/Contents/Info.plist")"
[[ "$actual_version" == "$version" ]]
(cd "$staging_dir" && shasum -a 256 "$archive" > "$archive.sha256")
mv "$staging_dir/$archive" "$staging_dir/$archive.sha256" "$project_dir/dist/"
printf '%s\n' "$project_dir/dist/$archive"
