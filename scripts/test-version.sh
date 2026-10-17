#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts"
cp "$project_dir/scripts/version.sh" "$fixture/scripts/"

expect_bump() {
    printf '%s\n' "$1" > "$fixture/VERSION"
    actual="$(bash "$fixture/scripts/version.sh" --set "$2")"
    [[ "$actual" == "$2" && "$(cat "$fixture/VERSION")" == "$2" ]]
}

expect_rejected_bump() {
    printf '%s\n' "$1" > "$fixture/VERSION"
    if bash "$fixture/scripts/version.sh" --set "$2" >/dev/null 2>&1; then
        printf 'Unexpectedly accepted version: %s\n' "$2" >&2
        exit 1
    fi
    [[ "$(cat "$fixture/VERSION")" == "$1" ]]
}

expect_bump 0.1.0 0.1.1
expect_bump 0.1.9 0.1.10
expect_bump 0.9.99 0.10.0
expect_bump 0.99.99 1.0.0
expect_bump 9.99.99 10.0.0
expect_rejected_bump 0.1.0 0.1.0
expect_rejected_bump 0.1.10 0.1.9
expect_rejected_bump 1.0.0 0.99.99
for invalid in '' v0.2.0 01.2.0 0.02.0 0.2 0.2.0-beta.1 '0.2.0;touch nope' $'0.2.0\n0.3.0'; do
    expect_rejected_bump 0.1.0 "$invalid"
done
printf '0.1.0\n' > "$fixture/VERSION"
bash "$fixture/scripts/version.sh" --check-tag v0.1.0 >/dev/null
if bash "$fixture/scripts/version.sh" --check-tag v0.1.1 >/dev/null 2>&1; then
    printf '%s\n' 'Unexpectedly accepted mismatching tag.' >&2
    exit 1
fi
printf 'bad\n' > "$fixture/VERSION"
if bash "$fixture/scripts/version.sh" >/dev/null 2>&1; then
    printf '%s\n' 'Unexpectedly accepted invalid VERSION file.' >&2
    exit 1
fi
printf '%s\n' 'Version checks passed.'
