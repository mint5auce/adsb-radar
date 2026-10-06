#!/bin/zsh
# Build, notarise and sign release artifacts without publishing them.
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to a notarytool credentials profile}"
output_dir="${RELEASE_ASSETS_DIR:-$repo_root/build/release-assets}"
if [[ -e "$output_dir" ]]; then
    print -u2 'build/release-assets already exists. Move it aside before preparing another release.'
    exit 1
fi
release_manifest="${RELEASE_MANIFEST:-$repo_root/release.json}"
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$release_manifest")"
notes="${RELEASE_NOTES_FILE:-$repo_root/docs/releases/$version.md}"
[[ -s "$notes" ]] || { print -u2 "Release notes missing: $notes"; exit 1; }
mkdir -p "$repo_root/build"
if [[ -n "${PREVIOUS_APPCAST:-}" ]]; then
    python3 scripts/release-metadata.py --manifest "$release_manifest" --configuration release \
        --previous-appcast "$PREVIOUS_APPCAST" --output "$repo_root/build/release-preflight.plist"
fi
./scripts/build-app.sh release --distribution
sparkle_bin="$repo_root/.build/artifacts/sparkle/Sparkle/bin"
key_options=(--account dev.mint5auce.adsb-radar)
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    key_options=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi
if [[ -n "${PREVIOUS_APPCAST:-}" ]]; then
    "$sparkle_bin/sign_update" "${key_options[@]}" --verify "$PREVIOUS_APPCAST"
fi
app_dir="$repo_root/build/distribution/ADSB Radar.app"
mkdir -p "$output_dir"
archive="$output_dir/ADSB-Radar-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait --timeout 20m --output-format json > "$output_dir/notarisation.json"
python3 -c 'import json,sys; result=json.load(open(sys.argv[1])); sys.exit(0 if result.get("status") == "Accepted" else "Notarisation was not accepted; inspect " + sys.argv[1])' "$output_dir/notarisation.json"
xcrun stapler staple "$app_dir"
xcrun stapler validate "$app_dir"
codesign --verify --deep --strict "$app_dir"
spctl --assess --type execute --verbose "$app_dir"
# Stapling changes the archive bytes. Recreate it before Sparkle signs it.
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive"
cp "$notes" "$output_dir/ADSB-Radar-$version.md"
cp "$release_manifest" "$output_dir/release.json"
if [[ -n "${PREVIOUS_APPCAST:-}" ]]; then
    cp "$PREVIOUS_APPCAST" "$output_dir/appcast.xml"
fi
repository="${GITHUB_REPOSITORY:-mint5auce/adsb-radar}"
"$sparkle_bin/generate_appcast" "${key_options[@]}" --maximum-deltas 0 --maximum-versions 0 \
    --download-url-prefix "https://github.com/$repository/releases/download/v$version/" \
    --link "https://github.com/$repository/releases" --embed-release-notes "$output_dir"
"$sparkle_bin/sign_update" "${key_options[@]}" --verify "$output_dir/appcast.xml"
printf '%s\n' "$output_dir"
