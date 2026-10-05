#!/bin/zsh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-debug}"
cd "$repo_root"
swift build -c "$configuration"
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$repo_root/build/ADSB Radar.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/ADSB Radar" "$app_dir/Contents/MacOS/ADSB Radar"
for bundle in "$bin_dir"/*.bundle(N); do
    cp -R "$bundle" "$app_dir/Contents/Resources/"
done
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.mint5auce.adsb-radar</string>
<key>CFBundleExecutable</key><string>ADSB Radar</string>
<key>CFBundleName</key><string>ADSB Radar</string>
<key>CFBundleDisplayName</key><string>ADSB Radar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSQuitAlwaysKeepsWindows</key><false/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
