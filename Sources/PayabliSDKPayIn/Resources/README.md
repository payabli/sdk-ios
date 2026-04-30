# PayabliBrandAssets

Bundled assets consumed by `CardFormView` / `CardBrandBadge` via
`Image(_, bundle: .module)`. Shipped as a single `.xcassets` catalog so the
host app doesn't need to install or expose any images.

## What to drop (PNG, 3 scales)

Each imageset's `Contents.json` already references the filenames below.
Drop PNGs with these exact names into the matching folder:

```
PayabliBrandAssets.xcassets/
  brand-visa.imageset/
    brand-visa.png
    brand-visa@2x.png
    brand-visa@3x.png
  brand-mastercard.imageset/
    brand-mastercard.png
    brand-mastercard@2x.png
    brand-mastercard@3x.png
  brand-amex.imageset/
    brand-amex.png
    brand-amex@2x.png
    brand-amex@3x.png
  brand-discover.imageset/
    brand-discover.png
    brand-discover@2x.png
    brand-discover@3x.png
```

### Pixel sizes

Render target is **22pt tall**. Sharp on every device means:

| Scale | Height (px) |
|-------|-------------|
| @1x   | 22          |
| @2x   | 44          |
| @3x   | 66          |

Width follows each brand's native aspect ratio — `CardBrandBadge` uses
`.aspectRatio(contentMode: .fit)` so non-square logos aren't distorted.

Transparent background (alpha channel) is recommended; the badge sits on the
form's system background.

## Generating PNG sizes from a single source

From an SVG:

```bash
brew install librsvg
rsvg-convert -h 22 -f png -o brand-visa.png     brand-visa.svg
rsvg-convert -h 44 -f png -o brand-visa@2x.png  brand-visa.svg
rsvg-convert -h 66 -f png -o brand-visa@3x.png  brand-visa.svg
```

From a large high-res PNG:

```bash
sips -Z 66 source.png --out brand-visa@3x.png
sips -Z 44 source.png --out brand-visa@2x.png
sips -Z 22 source.png --out brand-visa.png
```

## PDF vector alternative

If you prefer a single vector file per brand, replace each imageset's
`Contents.json` with:

```json
{
  "images" : [
    { "idiom" : "universal", "filename" : "brand-visa.pdf" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true }
}
```

…and drop a single `brand-visa.pdf` (vector) next to it. No 1x/2x/3x needed.

## Brand guidelines

Visa / Mastercard / American Express / Discover marks are trademarks of their
respective owners. Host apps are responsible for following each network's
brand-usage rules when rendering these logos.
