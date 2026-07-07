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
| `⌘O` | Open an image |
| `⌃W` / `⌘Q` | Quit |

You can also drag an image file onto the window. The app reopens the last viewed image on launch.

In real-size mode the image is shown at its actual pixel dimensions, centered; when it is larger than the window you can pan with trackpad scrolling or by click-dragging. Every `0` press re-centers. The bottom-right corner shows the image resolution (e.g. `2704 x 1756`).

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
  main.swift               App entry point
  AppDelegate.swift        Window, menu, file-open handling
  ImageView.swift          Image display, folder navigation, hotkeys, overlay UI
  PannableImageView.swift  Centering clip view + click-drag panning for real-size mode
Info.plist                 Bundle metadata
icon.jpg                   App icon source (1024×1024+ square JPEG)
build.sh                   Build script → build/LaViewer.app
```

## Notes

- "Same folder" navigation lists sibling files whose extension conforms to `public.image`, sorted by filename (natural/numeric-aware order).
- At the first/last image, `←`/`→` do nothing (no wraparound).
- Real size means actual pixel dimensions (1 image pixel = 1 point), not adjusted for Retina backing scale.
- Scrolling/panning is locked on any axis where the image already fits the window, so a fully-visible image can't rubber-band or be dragged.
- The app is ad-hoc signed, so it runs locally but will trigger Gatekeeper if distributed to other machines.
