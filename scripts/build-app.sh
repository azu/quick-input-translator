#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

# Replacing the bundle of a running process can leave trust preflight and AX
# requests disagreeing. Require the app to exit before updating its bundle.
ensure_app_stopped() {
    if pgrep -x QuickTranslateInput >/dev/null; then
        printf '%s\n' 'Quick Input Translatorを終了してからビルドしてください。起動中のアプリは更新しません。' >&2
        exit 1
    else
        local process_check_status=$?
        if [[ "$process_check_status" != 1 ]]; then
            printf '%s\n' 'アプリの起動状態を確認できないため、更新を中止しました。' >&2
            exit 1
        fi
    fi
}
ensure_app_stopped

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
bundle_dir="$project_dir/dist/Quick Input Translator.app"
legacy_bundle="$project_dir/dist/Quick Translate Input.app"
previous_bundle="$bundle_dir"
if [[ -d "$legacy_bundle" ]]; then
    if [[ -e "$bundle_dir" ]]; then
        printf '%s\n' '新旧両方のアプリがあります。利用する版を確認してからビルドしてください。' >&2
        exit 1
    fi
    previous_bundle="$legacy_bundle"
fi
mkdir -p "$project_dir/dist"
staging_dir="$(mktemp -d "$project_dir/dist/.QuickTranslateInput.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staged_bundle="$staging_dir/Quick Input Translator.app"
bash "$project_dir/scripts/assemble-app.sh" "$staged_bundle" "$binary_dir/QuickTranslateInput"
codesign --force --sign "$signing_identity" --timestamp=none "$staged_bundle"
codesign --verify --strict "$staged_bundle"

ensure_app_stopped
if [[ -d "$previous_bundle" ]]; then
    previous_requirement="$(codesign -d -r- "$previous_bundle" 2>&1 | sed -n 's/^#\{0,1\} *designated => //p')"
    if [[ -z "$previous_requirement" ]]; then
        printf '%s\n' '既存アプリの署名を確認できないため、更新を中止しました。' >&2
        exit 1
    fi
    if [[ "$previous_requirement" == cdhash* ]]; then
        printf '%s\n' '仮署名から証明書の署名へ切り替えます。今回は一度だけ権限の再登録が必要です。' >&2
    else
        codesign --verify --strict -R="$previous_requirement" "$staged_bundle"
    fi
    mv "$previous_bundle" "$staging_dir/previous.app"
fi
if ! mv "$staged_bundle" "$bundle_dir"; then
    if [[ -d "$staging_dir/previous.app" ]]; then mv "$staging_dir/previous.app" "$previous_bundle"; fi
    exit 1
fi
printf '%s\n' "$bundle_dir"
