#!/bin/bash
# Release identity is fixed; never silently fall back to ad-hoc signing.
set -euo pipefail
umask 077
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
version="$(bash scripts/version.sh)"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    printf '%s\n' 'Release packaging requires an Apple Silicon Mac.' >&2
    exit 1
fi
[[ -f config/update-signing.json ]] || { printf '%s\n' 'Run scripts/setup-update-signing.sh once and commit the public config.' >&2; exit 1; }
mkdir -p dist
staging_dir="$(mktemp -d "$project_dir/dist/.release.XXXXXX")"
keychain="$staging_dir/signing.keychain-db"
previous_keychains=()
while IFS= read -r path; do previous_keychains+=("$path"); done < <(security list-keychains -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')
cleanup() {
    if [[ "${trusted_in_ci:-0}" == 1 ]]; then
        sudo security remove-trusted-cert -d "$staging_dir/certificate.pem" >/dev/null 2>&1 || true
    fi
    security list-keychains -d user -s "${previous_keychains[@]}" >/dev/null 2>&1 || true
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$staging_dir"
}
trap cleanup EXIT
# Secrets are read from the environment or from the ignored one-time setup.
# Never write secrets to logs or pass them as command-line script arguments.
python3 - "$project_dir/.update-signing" "$staging_dir" <<'PY'
import base64, os, pathlib, sys
local, target = map(pathlib.Path, sys.argv[1:])
for env, source, dest, encoded in [
    ("CODE_SIGN_P12_BASE64", "code-signing.p12", "identity.p12", True),
    ("CODE_SIGN_P12_PASSWORD", "p12-password", "p12-password", False),
    ("SPARKLE_PRIVATE_KEY", "sparkle-private-key", "sparkle-private-key", False),
]:
    value = os.environ.get(env)
    if value:
        data = base64.b64decode(value, validate=True) if encoded else value.encode()
    elif (local / source).is_file():
        data = (local / source).read_bytes()
    else:
        raise SystemExit(f"Missing release secret: {env}")
    (target / dest).write_bytes(data)
PY
keychain_password="$(openssl rand -base64 32)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security list-keychains -d user -s "$keychain" "${previous_keychains[@]}"
security import "$staging_dir/identity.p12" -k "$keychain" -P "$(cat "$staging_dir/p12-password")" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
# Inspect the actual certificate before signing and compare its SHA-256 pin.
security find-certificate -p "$keychain" > "$staging_dir/certificate.pem"
openssl x509 -in "$staging_dir/certificate.pem" -outform DER -out "$staging_dir/certificate.der"
python3 - config/update-signing.json "$staging_dir/certificate.der" <<'PY'
import hashlib, json, pathlib, sys
config = json.loads(pathlib.Path(sys.argv[1]).read_text())
if hashlib.sha256(pathlib.Path(sys.argv[2]).read_bytes()).hexdigest() != config["certificateSHA256"]:
    raise SystemExit("Release certificate changed. Refusing to discard Accessibility identity.")
PY
identity="$(openssl x509 -in "$staging_dir/certificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
if [[ "${GITHUB_ACTIONS:-false}" == true ]]; then
    # Hosted runner only: trust for code signing and remove on exit. Never
    # change the system trust store on a developer's Mac from a build script.
    trusted_in_ci=1
    sudo security add-trusted-cert -d -r trustRoot -p codeSign -k "$keychain" "$staging_dir/certificate.pem"
fi
if ! security find-identity -v -p codesigning "$keychain" | grep -Fq "$identity"; then
    printf '%s\n' 'Release certificate is not trusted for code signing. Run scripts/trust-release-certificate.sh once on this authoring Mac.' >&2
    exit 1
fi
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
bundle="$staging_dir/Quick Input Translator.app"
QTI_RELEASE_BUILD=1 bash scripts/assemble-app.sh "$bundle" "$binary_dir/QuickTranslateInput"
# Keep secrets private without restricting a shared /Applications install.
chmod -R go+rX "$bundle"
bash scripts/sign-app.sh "$bundle" "$identity" --keychain "$keychain"
# The DR must accept future builds from this certificate, not only this hash.
requirement="identifier \"info.efcl.quick-translate-input\" and certificate leaf = H\"$identity\""
codesign --verify --strict -R="$requirement" "$bundle"
if codesign -d -r- "$bundle" 2>&1 | sed -n '/designated =>/p' | grep -q 'cdhash'; then
    printf '%s\n' 'Release has a build-specific signing requirement.' >&2
    exit 1
fi
archive="quick-input-translator-macos-arm64.zip"
updates="$staging_dir/updates"
mkdir "$updates"
ditto -c -k --sequesterRsrc --keepParent "$bundle" "$updates/$archive"
ditto -x -k "$updates/$archive" "$staging_dir/unpacked"
codesign --verify --deep --strict -R="$requirement" "$staging_dir/unpacked/Quick Input Translator.app"
actual_version="$(plutil -extract CFBundleShortVersionString raw "$staging_dir/unpacked/Quick Input Translator.app/Contents/Info.plist")"
[[ "$actual_version" == "$version" ]]
# A changed, re-signed bundle must still satisfy the previous bundle's DR.
previous_requirement="$(codesign -d -r- "$bundle" 2>&1 | sed -n 's/^#\{0,1\} *designated => //p')"
[[ -n "$previous_requirement" ]]
ditto "$bundle" "$staging_dir/identity-probe.app"
plutil -replace QTIBuildID -string identity-continuity-probe "$staging_dir/identity-probe.app/Contents/Info.plist"
codesign --force --sign "$identity" --timestamp=none --keychain "$keychain" "$staging_dir/identity-probe.app"
codesign --verify --deep --strict -R="$previous_requirement" "$staging_dir/identity-probe.app"
sparkle_bin="$(bash scripts/sparkle-path.sh bin)"
"$sparkle_bin/generate_appcast" --ed-key-file "$staging_dir/sparkle-private-key" \
    --download-url-prefix "https://github.com/azu/quick-input-translator/releases/download/v$version/" \
    --maximum-deltas 0 "$updates"
"$sparkle_bin/sign_update" --verify --ed-key-file "$staging_dir/sparkle-private-key" "$updates/appcast.xml"
# Verification uses only the embedded public key, independent of the private key.
python3 scripts/verify-appcast.py "$updates/appcast.xml" "$updates/$archive" config/update-signing.json "$version" "$staging_dir/verification.json"
swift scripts/verify-update.swift "$staging_dir/verification.json"
bash scripts/test-update-signatures.sh "$updates" "$staging_dir/sparkle-private-key" "$version"
(cd "$updates" && shasum -a 256 "$archive" > "$archive.sha256")
mv "$updates/$archive" "$updates/$archive.sha256" "$updates/appcast.xml" "$project_dir/dist/"
printf '%s\n' "$project_dir/dist/$archive"
