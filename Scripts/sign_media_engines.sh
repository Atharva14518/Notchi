#!/bin/sh
set -eu
# Runs after Copy Bundle Resources, before Xcode's outer CodeSign step.
# Never use --deep to sign: nested Mach-O executables get their own runtime signature.
for name in ffmpeg ffprobe; do
    binary="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/${name}"
    if [ ! -x "$binary" ]; then
        echo "error: Missing LGPL media engine: $binary. Run python3 Scripts/build_ffmpeg.py." >&2
        exit 1
    fi
    config="$("$binary" -version 2>&1)"
    case "$config" in
        *--enable-gpl*|*--enable-nonfree*|*--enable-version3*|*--enable-libx264*|*--enable-libx265*)
            echo "error: GPL/nonfree media engines must not be bundled." >&2; exit 1 ;;
    esac
    if [ "${CODE_SIGNING_ALLOWED:-YES}" = "YES" ]; then
        identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
        if [ -z "$identity" ]; then identity="-"; fi
        /usr/bin/codesign --force --sign "$identity" --options runtime --timestamp=none "$binary"
        /usr/bin/codesign --verify --strict "$binary"
    fi
done
