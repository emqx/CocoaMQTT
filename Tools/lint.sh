#!/bin/sh

set -eu

repository_root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)

exec swift package --package-path "$repository_root/Tools" \
    plugin --allow-writing-to-package-directory \
    swiftlint \
    --config "$repository_root/.swiftlint.yml" \
    --strict \
    --reporter github-actions-logging \
    "$repository_root"
