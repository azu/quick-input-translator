#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

# A real signing identity keeps the designated requirement stable across builds.
# Never fall back to ad-hoc signing: that would invalidate Accessibility grants.
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    signing_identity="$CODE_SIGN_IDENTITY"
else
    identities="$(security find-identity -v -p codesigning)"
    development_identities="$(printf '%s\n' "$identities" | awk '/"Apple Development: / { print $2 }')"
    identity_count="$(printf '%s\n' "$development_identities" | awk 'NF { count++ } END { print count+0 }')"
    if [[ "$identity_count" != 1 ]]; then
        printf '%s\n' 'Apple Developmentの署名元を一つに特定できません。' \
            'security find-identity -v -p codesigning で確認し、CODE_SIGN_IDENTITYに証明書のIDを指定してください。' >&2
        exit 1
    fi
    signing_identity="$development_identities"
fi
if [[ "$signing_identity" == "-" ]]; then
    printf '%s\n' '権限を維持するため、仮署名は利用しません。証明書のIDを指定してください。' >&2
    exit 1
fi

swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
bundle_dir="$project_dir/dist/Quick Translate Input.app"
mkdir -p "$project_dir/dist"
staging_dir="$(mktemp -d "$project_dir/dist/.QuickTranslateInput.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staged_bundle="$staging_dir/Quick Translate Input.app"
mkdir -p "$staged_bundle/Contents/MacOS"
cp "$binary_dir/QuickTranslateInput" "$staged_bundle/Contents/MacOS/QuickTranslateInput"
cat > "$staged_bundle/Contents/Info.plist" <<'PLIST'
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
plutil -insert QTIBuildID -string "$(date -u '+%Y%m%dT%H%M%SZ')" "$staged_bundle/Contents/Info.plist"
codesign --force --sign "$signing_identity" --timestamp=none "$staged_bundle"
codesign --verify --strict "$staged_bundle"

if [[ -d "$bundle_dir" ]]; then
    previous_requirement="$(codesign -d -r- "$bundle_dir" 2>&1 | sed -n 's/^#\{0,1\} *designated => //p')"
    if [[ -z "$previous_requirement" ]]; then
        printf '%s\n' '既存アプリの署名を確認できないため、更新を中止しました。' >&2
        exit 1
    fi
    if [[ "$previous_requirement" == cdhash* ]]; then
        printf '%s\n' '仮署名から証明書の署名へ切り替えます。今回は一度だけ権限の再登録が必要です。' >&2
    else
        codesign --verify --strict -R="$previous_requirement" "$staged_bundle"
    fi
    mv "$bundle_dir" "$staging_dir/previous.app"
fi
if ! mv "$staged_bundle" "$bundle_dir"; then
    if [[ -d "$staging_dir/previous.app" ]]; then mv "$staging_dir/previous.app" "$bundle_dir"; fi
    exit 1
fi
printf '%s\n' "$bundle_dir"
