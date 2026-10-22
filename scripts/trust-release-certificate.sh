#!/bin/bash
# One-time authoring-machine setup. Only trust this app's pinned certificate
# for code signing, never for TLS/HTTPS or other certificate policies.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
certificate="$project_dir/.update-signing/code-signing.crt"
python3 - "$project_dir/config/update-signing.json" "$certificate" <<'PY'
import hashlib, json, pathlib, subprocess, sys
expected = json.loads(pathlib.Path(sys.argv[1]).read_text())["certificateSHA256"]
certificate = subprocess.check_output(["openssl", "x509", "-in", sys.argv[2], "-outform", "DER"])
assert hashlib.sha256(certificate).hexdigest() == expected, "Certificate changed"
PY
security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$certificate"
