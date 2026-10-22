#!/bin/bash
# One-time setup. Never rotate these keys as part of a build or release.
set -euo pipefail
umask 077
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
destination="$project_dir/.update-signing"
config="$project_dir/config/update-signing.json"
if [[ -e "$destination" || -e "$config" ]]; then
    printf '%s\n' 'Signing material already exists. Refusing to replace update identity.' >&2
    exit 1
fi
secret_dir="$(mktemp -d "$project_dir/.update-signing.staging.XXXXXX")"
trap 'rm -rf "$secret_dir"' EXIT
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
    -subj '/CN=Quick Input Translator Release/' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=critical,codeSigning' \
    -keyout "$secret_dir/code-signing.key" -out "$secret_dir/code-signing.crt" 2>"$secret_dir/openssl.log"
openssl rand -base64 32 > "$secret_dir/p12-password"
# Legacy encryption lets the macOS Security framework import the PKCS#12 file.
openssl pkcs12 -export -legacy -inkey "$secret_dir/code-signing.key" \
    -in "$secret_dir/code-signing.crt" -name 'Quick Input Translator Release' \
    -out "$secret_dir/code-signing.p12" -passout "file:$secret_dir/p12-password"
swift scripts/create-update-key.swift "$secret_dir/sparkle-private-key" "$secret_dir/sparkle-public-key"
openssl x509 -in "$secret_dir/code-signing.crt" -outform DER -out "$secret_dir/code-signing.der"
mkdir -p config
python3 - "$secret_dir" "$config" <<'PY'
import hashlib, json, pathlib, sys
secret = pathlib.Path(sys.argv[1])
config = {"certificateSHA256": hashlib.sha256((secret / "code-signing.der").read_bytes()).hexdigest(),
          "sparklePublicKey": (secret / "sparkle-public-key").read_text().strip()}
pathlib.Path(sys.argv[2]).write_text(json.dumps(config, indent=2) + "\n")
PY
chmod 644 "$config"
mv "$secret_dir" "$destination"
printf '%s\n' 'Created config/update-signing.json (public) and .update-signing/ (private, ignored by git).' \
    'Back up .update-signing/ securely. Losing either key prevents future automatic updates.'
