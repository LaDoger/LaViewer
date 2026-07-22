# LaViewer

A minimal macOS image viewer, sibling app to [LaPlayer](https://github.com/LaDoger/LaPlayer).

Native Swift + AppKit. No dependencies, no Xcode project — one shell script builds a standalone `.app`.

## Hotkeys

| Key | Action |
|---|---|
| `←` | Previous image in the same folder (by filename order) |
| `→` | Next image in the same folder |
| `r` | Jump to a random image in the same folder |
| `0` | Toggle between fit-screen (default) and real size |
| drag | Select a crop area (Preview-style) |
| `k` | Crop the selection — saves `{filename}_{i}.{extension}` next to the original |
| `esc` | Clear the crop selection (a plain click outside it clears it too) |
| `⌘O` | Open an image |
| `⌃W` / `⌘Q` | Quit |

You can also drag an image file onto the window. The app reopens the last viewed image on launch.

In real-size mode the image is shown at its actual pixel dimensions, centered; when it is larger than the window you can pan with trackpad scrolling. Every `0` press re-centers. The bottom-right corner shows the image resolution (e.g. `2704 x 1756`).

Once a crop area is selected it can be adjusted like in Preview: drag the corner brackets or edges to resize, drag inside the selection to move it, and a clickable `k crop` badge sits at the selection's bottom-right. The cursor changes to match (crosshair over the image, resize arrows on corners/edges, hand over the selection, pointer over the badge). Drags smaller than 10×10 px are discarded as accidental. The bottom-right of the bar swaps to `crop:` plus two editable width/height fields (digits only; clicking one selects its whole value) — type a number and press return to resize the selection precisely, anchored at its top-left and clamped to the image.

The bar's bottom-left shows a live color readout: a small swatch and the hex value (e.g. `#F6E0B5`) of the exact image pixel under the cursor.

## Building

Requires macOS command-line tools (`xcode-select --install`).

```sh
./build.sh
open build/LaViewer.app
```

The build script compiles `Sources/*.swift` with `swiftc`, assembles the `.app` bundle, converts `icon.jpg` into the app icon, and ad-hoc code-signs it.

## Project layout

```
Sources/
  main.swift          App entry point
  AppDelegate.swift   Window, menu, file-open handling
  ImageView.swift     Image display, folder navigation, hotkeys, crop selection, overlay UI
  SupportViews.swift  Centering clip view, mouse-passthrough image view, crop overlay
Info.plist            Bundle metadata
icon.jpg              App icon source (1024×1024+ square JPEG)
build.sh              Build script → build/LaViewer.app
```

## Notes

- "Same folder" navigation lists sibling files whose extension conforms to `public.image`, sorted by filename (natural/numeric-aware order).
- At the first/last image, `←`/`→` do nothing (no wraparound).
- Real size means actual pixel dimensions (1 image pixel = 1 point), not adjusted for Retina backing scale.
- Scrolling is locked on any axis where the image already fits the window, so a fully-visible image can't rubber-band.
- Crops are taken from the file's original pixels (via ImageIO), not the display pipeline, and are saved in the same format as the source. Filenames auto-increment and never overwrite.
- The app is ad-hoc signed, so it runs locally but will trigger Gatekeeper if distributed to other machines.
