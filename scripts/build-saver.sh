#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
swift build -c release --product NeveScreenSaver
saver_dir="$project_dir/dist/Neve no Mac.saver"
mkdir -p "$saver_dir/Contents/MacOS" "$saver_dir/Contents/Resources"
# The engine discovers Mach-O bundles; the SwiftPM library build supplies the compiled objects.
saver_sdk="$(xcrun --show-sdk-path)"
saver_swift_compiler="$(xcrun --find swiftc)"
saver_runtime="${saver_swift_compiler:h:h}/lib/swift/macosx"
xcrun clang -bundle -arch "$(uname -m)" -mmacosx-version-min=13.0 -isysroot "$saver_sdk" \
    -L "$saver_sdk/usr/lib/swift" -L "$saver_runtime" \
    -Wl,-rpath,/usr/lib/swift \
    @.build/release/NeveScreenSaver.product/Objects.LinkFileList \
    -o "$saver_dir/Contents/MacOS/NeveScreenSaver"
if [[ $# -ge 1 && -f "$1" ]]; then
    cp "$1" "$saver_dir/Contents/Resources/Background.image"
else
    # A new build without an image must not silently redistribute a previous local wallpaper.
    rm -f "$saver_dir/Contents/Resources/Background.image"
fi
rm -f "$saver_dir/Contents/Resources/SnowSettings.json"
python3 - "$saver_dir/Contents/Resources/SnowSettings.json" <<'PY'
from pathlib import Path
import plistlib,sys
path=Path.home()/'Library/Preferences/local.lucas.nevemac.plist'
try:
    values=plistlib.loads(path.read_bytes())
    if isinstance(values.get('snow'),bytes):Path(sys.argv[1]).write_bytes(values['snow'])
except (OSError,ValueError,plistlib.InvalidFileException):pass
PY
cat > "$saver_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Neve no Mac</string>
  <key>CFBundleIdentifier</key><string>local.lucas.nevemac.screensaver</string>
  <key>CFBundleExecutable</key><string>NeveScreenSaver</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>0.3.1</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>NeveScreenSaverView</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$saver_dir"
print -r -- "$saver_dir"
