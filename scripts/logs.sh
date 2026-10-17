#!/bin/bash
set -euo pipefail
predicate='subsystem == "info.efcl.quick-translate-input"'
case "${1:-}" in
    --stream) exec /usr/bin/log stream --style compact --level debug --predicate "$predicate" ;;
    "") exec /usr/bin/log show --last 15m --style compact --info --debug --predicate "$predicate" ;;
    *) printf '%s\n' '使い方: bash scripts/logs.sh [--stream]' >&2; exit 1 ;;
esac
