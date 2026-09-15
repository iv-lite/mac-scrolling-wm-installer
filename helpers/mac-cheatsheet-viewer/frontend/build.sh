#!/usr/bin/env bash
# Build the static web assets for mac-cheatsheet-viewer.
#
# The sources live in this directory (frontend/); Tauri ships whatever
# frontend/dist/ contains (frontendDist in tauri.conf.json), so this stages a
# fresh copy every time and fails loudly if a source file is missing.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$SRC/dist"

for asset in index.html style.css app.js; do
	if [ ! -f "$SRC/$asset" ]; then
		echo "build.sh: missing web asset $SRC/$asset" >&2
		exit 1
	fi
done

rm -rf "$DIST"
mkdir -p "$DIST"
cp "$SRC/index.html" "$SRC/style.css" "$SRC/app.js" "$DIST/"
echo "build.sh: staged web assets → $DIST"