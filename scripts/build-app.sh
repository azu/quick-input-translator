#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
bundle_dir="$project_dir/dist/Quick Translate Input.app"
mkdir -p "$bundle_dir/Contents/MacOS"
cp "$binary_dir/QuickTranslateInput" "$bundle_dir/Contents/MacOS/QuickTranslateInput"
cat > "$bundle_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>QuickTranslateInput</string>
<key>CFBundleIdentifier</key><string>info.efcl.quick-translate-input</string>
<key>CFBundleName</key><string>Quick Translate Input</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$bundle_dir"
printf '%s\n' "$bundle_dir"
