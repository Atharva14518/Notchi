# Third-party acknowledgements

Notchi launches FFmpeg as a separate command-line process. It does not link
FFmpeg libraries into the Swift app. The bundled FFmpeg/ffprobe build is LGPL
2.1-or-later, with GPL, version3 and nonfree components disabled. There is no
libx264 or libx265. H.264/HEVC output uses Apple's VideoToolbox implementation.
This configuration does not make a claim about codec patent rights.

- **FFmpeg 9.0.2** — Copyright © 2000–2026 the FFmpeg developers. LGPL 2.1 or later.
  https://ffmpeg.org/ — https://ffmpeg.org/legal.html
- **LAME 3.100** — Copyright © the LAME developers. LGPL 2.0 or later.
  https://lame.sourceforge.io/
- **libvpx 1.15.2** — Copyright © the WebM project authors. BSD 3-clause license,
  with the accompanying WebM patent grant.
  https://github.com/webmproject/libvpx
- **Opus 1.5.2** — Copyright © the Xiph.Org Foundation and contributors. BSD-style
  license and patent grants as described in COPYING.
  https://opus-codec.org/

Complete upstream license texts are in `FFmpegLicenses/` alongside this document
in the app's Resources. Exact unmodified source archives, their SHA-256 digests,
source URLs, build commands, and a rebuild script are bundled in `FFmpegSources/`.
No access to a separate server is required to obtain the corresponding sources.

To rebuild or replace FFmpeg from the repository, run `python3 Scripts/build_ffmpeg.py`.
From a bundled source folder, run `python3 /path/to/FFmpegSources/build_ffmpeg.py`
from any writable directory; it creates a `NotchiMediaRebuild` folder there.
The exact build commands are also recorded in BUILD_MANIFEST.json.
The script needs Xcode, Python 3.11+, make and pkg-config;
no Homebrew codec libraries are linked. Copy rebuilt ffmpeg/ffprobe into
Resources and build Notchi again; the build signs the nested executables before
signing the app. You may modify the LGPL components and replace their executables
under their licenses. App signing/permission identities may change when doing so.

Before distributing a modified build, include its corresponding source and
license notices, retain the upstream notices, and review FFmpeg's distribution
checklist. These notices do not grant rights beyond the upstream licenses.

## Poppins

Poppins — Copyright 2020 The Poppins Project Authors. SIL Open Font License 1.1.
Unmodified static Regular, Medium, SemiBold, Bold, ExtraBold and Black fonts are
bundled in `Fonts/Poppins/`. The complete license is `Fonts/Poppins/OFL.txt`;
`SOURCE.json` records the pinned Google Fonts repository commit and SHA-256 hashes.
Source: https://github.com/google/fonts/tree/main/ofl/poppins
