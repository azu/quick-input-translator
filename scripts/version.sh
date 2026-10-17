#!/bin/bash
# Read, validate, and bump the single release version without extra dependencies.
set -euo pipefail
export LC_ALL=C
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version_file="$project_dir/VERSION"
current="$(cat "$version_file")"

validate_version() {
    if [[ ! "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        printf '%s\n' 'Version must be MAJOR.MINOR.PATCH, without a v prefix.' >&2
        exit 1
    fi
}

validate_version "$current"
case "${1:-}" in
    '') [[ "$#" == 0 ]] ;;
    --check-tag)
        [[ "$#" == 2 ]]
        if [[ "$2" != "v$current" ]]; then
            printf 'Tag must match VERSION: v%s\n' "$current" >&2
            exit 1
        fi
        ;;
    --set)
        [[ "$#" == 2 ]]
        validate_version "$2"
        IFS=. read -r -a current_parts <<< "$current"
        IFS=. read -r -a new_parts <<< "$2"
        newer=false
        for index in 0 1 2; do
            old="${current_parts[$index]}"
            new="${new_parts[$index]}"
            # Compare decimal components without arithmetic overflow.
            if [[ "${#new}" -gt "${#old}" ]] || { [[ "${#new}" == "${#old}" ]] && [[ "$new" > "$old" ]]; }; then
                newer=true
                break
            elif [[ "$new" != "$old" ]]; then
                break
            fi
        done
        if [[ "$newer" != true ]]; then
            printf '%s\n' 'New version must be greater than the current version.' >&2
            exit 1
        fi
        current="$2"
        printf '%s\n' "$current" > "$version_file"
        ;;
    *)
        printf '%s\n' 'Usage: bash scripts/version.sh [--set VERSION | --check-tag TAG]' >&2
        exit 1
        ;;
esac
printf '%s\n' "$current"
