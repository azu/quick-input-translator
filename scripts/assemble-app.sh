#!/bin/bash
# Shared bundle metadata for local and release builds. Destination must be new.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
staged_bundle="${1:?Bundle destination required}"
binary_path="${2:?Executable path required}"
version="$(bash "$project_dir/scripts/version.sh")"
if [[ -e "$staged_bundle" ]]; then
    printf '%s\n' 'Bundle destination already exists.' >&2
    exit 1
fi
mkdir -p "$staged_bundle/Contents/MacOS" "$staged_bundle/Contents/Resources"
cp "$binary_path" "$staged_bundle/Contents/MacOS/QuickTranslateInput"
bash "$project_dir/scripts/build-icon.sh" "$staged_bundle/Contents/Resources/AppIcon.icns"
cat > "$staged_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QuickTranslateInput</string>
<key>CFBundleIdentifier</key><string>info.efcl.quick-translate-input</string>
<key>CFBundleName</key><string>Quick Input Translator</string>
<key>CFBundleDisplayName</key><string>Quick Input Translator</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -replace CFBundleShortVersionString -string "$version" "$staged_bundle/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$version" "$staged_bundle/Contents/Info.plist"
plutil -insert QTIBuildID -string "$(date -u '+%Y%m%dT%H%M%SZ')" "$staged_bundle/Contents/Info.plist"
