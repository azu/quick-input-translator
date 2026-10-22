"""Validate release metadata and prepare independent Ed25519 verification."""
import base64
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

feed, archive, config, version, output = sys.argv[1:]
feed, archive = pathlib.Path(feed), pathlib.Path(archive)
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
root = ET.fromstring(feed.read_bytes())
items = root.findall("./channel/item")
assert len(items) == 1, "Expected exactly one release"
item = items[0]
assert item.findtext("sparkle:version", namespaces=ns) == version, "Version mismatch"
assert item.findtext("sparkle:minimumSystemVersion", namespaces=ns) == "26.0", "Unexpected OS requirement"
enclosure = item.find("enclosure")
expected_url = f"https://github.com/azu/quick-input-translator/releases/download/v{version}/{archive.name}"
assert enclosure.get("url") == expected_url, "Unexpected download URL"
assert int(enclosure.get("length")) == archive.stat().st_size, "Archive length mismatch"
archive_signature = enclosure.get(f"{{{ns['sparkle']}}}edSignature")
key = json.loads(pathlib.Path(config).read_text())["sparklePublicKey"]
assert len(base64.b64decode(key, validate=True)) == 32
checks = [{"path": str(archive.resolve()), "signature": archive_signature}]
pathlib.Path(output).write_text(json.dumps({"publicKey": key, "checks": checks}))
