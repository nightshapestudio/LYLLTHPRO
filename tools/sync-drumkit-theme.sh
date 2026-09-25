#!/bin/sh
# Regenerates LYLLTH/DrumKitShared/NightshapeTheme+macOS.swift from DrumKit's
# Theme/NightshapeTheme.swift. Run after any DrumKit theme change; exits
# non-zero if the source has changed shape and the conversion no longer applies.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
src="$here/../nightshape-drumkit-ios/Theme/NightshapeTheme.swift"
out="$here/LYLLTH/DrumKitShared/NightshapeTheme+macOS.swift"
python3 - "$src" "$out" <<'PY'
import sys
src, out = sys.argv[1], sys.argv[2]
s = open(src).read()
marker = "extension Color {\n    init(hex: UInt32"
old_font = "guard let font = UIFont(name: fontName, size: size) else { return 0 }"
if "import UIKit\n" not in s or marker not in s or old_font not in s:
    sys.exit("NightshapeTheme.swift changed shape; update tools/sync-drumkit-theme.sh")
s = s.replace("import UIKit\n", "import AppKit\n")
s = s[:s.index(marker)]
s = s.replace(old_font, "guard let font = NSFont(name: fontName, size: size) else { return 0 }")
if "UIKit" in s or "UIFont" in s or "UIColor" in s:
    sys.exit("UIKit symbols remain after conversion")
header = """// macOS stand-in for DrumKit's Theme/NightshapeTheme.swift, which imports
// UIKit. Generated from that file: same tokens, NSFont in place of UIFont.
// LYLLTH compiles DrumKit's FX windows from the sibling checkout against this,
// so if DrumKit changes a theme token, regenerate this file rather than
// editing it by hand (tools/sync-drumkit-theme.sh).
"""
open(out, "w").write(header + s)
PY
echo "wrote $out"
