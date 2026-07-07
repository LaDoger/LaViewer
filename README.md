# LaViewer

A minimal macOS image viewer, sibling app to [LaPlayer](https://github.com/LaDoger/LaPlayer).

Native Swift + AppKit. No dependencies, no Xcode project — one shell script builds a standalone `.app`.

## Hotkeys

| Key | Action |
|---|---|
| `←` | Previous image in the same folder (by filename order) |
| `→` | Next image in the same folder |
| `R` | Jump to a random image in the same folder |
| `⌘O` | Open an image |
| `⌃W` / `⌘Q` | Quit |

You can also drag an image file onto the window. The app reopens the last viewed image on launch.

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
  main.swift        App entry point
  AppDelegate.swift  Window, menu, file-open handling
  ImageView.swift    Image display, folder navigation, hotkeys, overlay UI
Info.plist           Bundle metadata
icon.jpg             App icon source (1024×1024+ square JPEG)
build.sh             Build script → build/LaViewer.app
```

## Notes

- "Same folder" navigation lists sibling files whose extension conforms to `public.image`, sorted by filename (natural/numeric-aware order).
- At the first/last image, `←`/`→` do nothing (no wraparound).
- The app is ad-hoc signed, so it runs locally but will trigger Gatekeeper if distributed to other machines.
