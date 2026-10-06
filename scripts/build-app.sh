#!/bin/zsh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-debug}"
mode="${2:-}"
if [[ "$configuration" != debug && "$configuration" != release ]] || [[ -n "$mode" && "$mode" != --distribution ]] || (( $# > 2 )); then
    print -u2 'Usage: scripts/build-app.sh [debug|release] [--distribution]'
    exit 1
fi
cd "$repo_root"
build_dir="$repo_root/build"
build_options=(-c "$configuration" --product 'Phosphor')
metadata_options=(--configuration "$configuration" --manifest "${RELEASE_MANIFEST:-$repo_root/release.json}")
if [[ "$mode" == --distribution ]]; then
    : "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the signing identity}"
    : "${SPARKLE_PUBLIC_KEY:?Set SPARKLE_PUBLIC_KEY to the public update signing key}"
    build_dir="$repo_root/build/distribution"
    build_options+=(--arch arm64 --arch x86_64 -Xswiftc -g)
    metadata_options+=(--distribution --public-key "$SPARKLE_PUBLIC_KEY"
                      --feed-url "${UPDATES_FEED_URL:-https://jon-hadley.com/phosphor/appcast.xml}")
elif [[ "$configuration" == release ]]; then
    build_dir="$repo_root/build/release"
fi
mkdir -p "$build_dir"
staging="$(mktemp -d "$build_dir/.app-build.XXXXXX")"
app_dir="$build_dir/Phosphor.app"
candidate="$staging/Phosphor.app"
cleanup() {
    if [[ -d "$staging/previous.app" && ! -e "$app_dir" ]]; then
        mv "$staging/previous.app" "$app_dir"
    fi
    rm -rf "$staging"
}
trap cleanup EXIT
mkdir -p "$candidate/Contents/MacOS" "$candidate/Contents/Resources" "$candidate/Contents/Frameworks"
python3 scripts/release-metadata.py "${metadata_options[@]}" --output "$candidate/Contents/Info.plist"
swift build "${build_options[@]}"
bin_dir="$(swift build "${build_options[@]}" --show-bin-path)"
icon_file="$("$repo_root/scripts/generate-app-icon.sh")"
cp "$bin_dir/Phosphor" "$candidate/Contents/MacOS/Phosphor"
cp "$icon_file" "$candidate/Contents/Resources/AppIcon.icns"
ditto "$bin_dir/Phosphor_Phosphor.bundle" "$candidate/Contents/Resources/Phosphor_Phosphor.bundle"
framework="$candidate/Contents/Frameworks/Sparkle.framework"
ditto "$repo_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$framework"
if [[ "$mode" == --distribution ]]; then
    symbols="$repo_root/build/release-symbols"
    mkdir -p "$symbols"
    dsymutil "$bin_dir/Phosphor" -o "$symbols/Phosphor.dSYM"
    ditto "$repo_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/dSYMs" "$symbols"
    # Sign nested code first, preserving the downloader's sandbox entitlements.
    signing_options=(--force --sign "$DEVELOPER_ID_APPLICATION" --options runtime --timestamp)
    codesign "${signing_options[@]}" "$framework/Versions/B/XPCServices/Installer.xpc"
    codesign "${signing_options[@]}" --preserve-metadata=entitlements "$framework/Versions/B/XPCServices/Downloader.xpc"
    codesign "${signing_options[@]}" "$framework/Versions/B/Autoupdate"
    codesign "${signing_options[@]}" "$framework/Versions/B/Updater.app"
    codesign "${signing_options[@]}" "$framework"
    codesign "${signing_options[@]}" "$candidate"
    architectures="$(lipo "$candidate/Contents/MacOS/Phosphor" -archs)"
    [[ " $architectures " == *' arm64 '* && " $architectures " == *' x86_64 '* ]] || {
        print -u2 'Distribution executable must contain arm64 and x86_64.'
        exit 1
    }
else
    codesign --force --sign - "$candidate"
fi
codesign --verify --deep --strict "$candidate"
if [[ -e "$app_dir" ]]; then mv "$app_dir" "$staging/previous.app"; fi
mv "$candidate" "$app_dir"
printf '%s\n' "$app_dir"
