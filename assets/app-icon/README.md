# Application icon artwork

Issue [#9](https://github.com/mint5auce/adsb-radar/issues/9) defines the accepted design.
The unchanged supplied reference is [app-icon-reference.png](../../docs/design/app-icon-reference.png).
`master.png` is the cleaned, authored 1254-pixel square RGBA master.
It preserves the dark tile, aircraft, green glow, and three fading trail dashes, with transparent space replacing the reference's exterior background and presentation shadow.
The current exports use the same composition at every size; no separate small-size variant was needed after visual inspection.

## Regenerate

From the repository root on macOS, run:

```sh
./scripts/generate-app-icon.sh
```

The script uses the system `sips` to export standard and Retina representations for 16, 32, 128, 256, and 512 point sizes, then `iconutil` to assemble `build/app-icon/AppIcon.icns`.
The largest representation is `icon_512x512@2x.png`, at 1024 pixels.
Generated `.iconset` and `.icns` files remain in ignored `build/app-icon/`; regenerate them rather than editing them.
Both `./scripts/build-app.sh` and `./scripts/build-app.sh release` regenerate the icon from the tracked master and install it in the main app bundle before signing.
Normal builds require no network access or image-generation service.

To inspect the packaged representations, choose a fresh output directory and run:

```sh
iconutil --convert iconset --output build/inspect-icon.iconset \
  'build/ADSB Radar.app/Contents/Resources/AppIcon.icns'
```

Inspect the PNGs at their native sizes on light and dark backgrounds.
Check the silhouette, three separated dashes, balanced margins, and transparent rounded corners.
At 16 pixels the trail is necessarily subtle; inspect the Retina representation as well.

## Master provenance

The cleaned master was produced using the built-in imagegen tool in background-extraction mode with the unchanged reference as its edit target and transparent output enabled.
The final prompt was:

```text
Use case: background-extraction
Asset type: cleaned master artwork for a native macOS application icon.
Input image 1 is the edit target. Remove ONLY the off-white exterior background and exterior presentation/drop shadow surrounding the glossy dark rounded-square tile, leaving real transparent pixels around the tile. Preserve the tile's own dark shading, bevel, reflections and silhouette. Preserve the existing green aircraft pointing upper-right, its exact silhouette, colours and green glow, and all three short fading green trail dashes towards lower-left. Keep their positions, spacing, scale and overall composition unchanged. Keep a square canvas with modest balanced transparent margins around the tile, comparable to the reference framing. No redesign, no text, no additional symbols, no new shadow outside the tile. Clean alpha edges with no white fringes. Preserve the artwork inside the tile as faithfully as possible.
```

The master is an authored source, not an automatically regenerated file.
Size exports are deterministic from this local source using the installed macOS tools.
See Apple's [high-resolution icon guidance](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html) for the native representations and `iconutil` workflow.
