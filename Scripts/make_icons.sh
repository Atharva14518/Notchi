#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/notchi-icon-module-cache"
export SWIFT_MODULECACHE_PATH="$CLANG_MODULE_CACHE_PATH"
swift "$ROOT/Scripts/MakeIcons.swift" "$ROOT"
