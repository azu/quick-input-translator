#!/bin/bash
# Verify rejection, not only successful signing. Private key stays in a file.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
updates="${1:?Updates directory required}"
key_file="${2:?Private key file required}"
version="${3:?Version required}"
probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
sparkle_bin="$(bash "$project_dir/scripts/sparkle-path.sh" bin)"
archive=quick-input-translator-macos-arm64.zip
cp "$updates/$archive" "$updates/appcast.xml" "$probe/"
python3 "$project_dir/scripts/verify-appcast.py" "$probe/appcast.xml" "$probe/$archive" "$project_dir/config/update-signing.json" "$version" "$probe/check.json"
swift "$project_dir/scripts/verify-update.swift" "$probe/check.json"
"$sparkle_bin/sign_update" --verify --ed-key-file "$key_file" "$probe/appcast.xml"
# Change one byte without changing the advertised file length.
python3 - "$probe/$archive" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
data = bytearray(path.read_bytes())
data[len(data) // 2] ^= 1
path.write_bytes(data)
PY
if swift "$project_dir/scripts/verify-update.swift" "$probe/check.json" > "$probe/archive.log" 2>&1; then
    printf '%s\n' 'Tampered archive was accepted.' >&2
    exit 1
fi
# A different public key must also fail even with an otherwise genuine ZIP.
cp "$updates/$archive" "$probe/$archive"
python3 - "$probe/check.json" <<'PY'
import base64, json, pathlib, sys
path = pathlib.Path(sys.argv[1]); data = json.loads(path.read_text())
data['publicKey'] = base64.b64encode(bytes(32)).decode()
path.write_text(json.dumps(data))
PY
if swift "$project_dir/scripts/verify-update.swift" "$probe/check.json" > "$probe/key.log" 2>&1; then
    printf '%s\n' 'Different public key was accepted.' >&2
    exit 1
fi
python3 - "$probe/appcast.xml" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1]); data = path.read_bytes()
assert b'<title>' in data
path.write_bytes(data.replace(b'<title>', b'<title>tampered ', 1))
PY
if "$sparkle_bin/sign_update" --verify --ed-key-file "$key_file" "$probe/appcast.xml" > "$probe/feed.log" 2>&1; then
    printf '%s\n' 'Tampered update feed was accepted.' >&2
    exit 1
fi
printf '%s\n' 'Signature checks passed: genuine update accepted; altered ZIP, altered feed, and wrong key rejected.'
