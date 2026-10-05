#!/bin/zsh
set -eu
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
master="$repo_root/assets/app-icon/master.png"
output_dir="$repo_root/build/app-icon"
iconset="$output_dir/AppIcon.iconset"
mkdir -p "$iconset"

for size in 16 32 128 256 512; do
    for scale in 1 2; do
        suffix=""
        if [[ "$scale" == 2 ]]; then suffix="@2x"; fi
        pixels=$((size * scale))
        sips --resampleHeightWidth "$pixels" "$pixels" "$master" \
            --out "$iconset/icon_${size}x${size}${suffix}.png" >/dev/null
    done
done
iconutil --convert icns --output "$output_dir/AppIcon.icns" "$iconset"
printf '%s\n' "$output_dir/AppIcon.icns"
