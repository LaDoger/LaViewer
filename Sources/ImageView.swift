import Cocoa
import UniformTypeIdentifiers

final class ImageView: NSView {
    private enum DisplayMode {
        case fit
        case real
    }

    private let fitImageView = NSImageView()
    private let scrollView = NSScrollView()
    private let realImageView = PannableImageView()

    private let overlay = NSView()
    private let legendLabel = NSTextField(labelWithString: "")
    private let resolutionLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "Drop a file here, or press ⌘O")

    private var currentURL: URL?
    private var siblings: [URL] = []
    private var currentIndex: Int = 0
    private var displayMode: DisplayMode = .fit

    private static func legend(toggleLabel: String) -> NSAttributedString {
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .backgroundColor: NSColor.white.withAlphaComponent(0.18),
        ]
        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]
        let items: [(key: String, desc: String)] = [
            ("←", "prev"),
            ("→", "next"),
            ("r", "random"),
            ("0", toggleLabel),
        ]
        let result = NSMutableAttributedString()
        for (i, item) in items.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "     ", attributes: descAttrs)) }
            result.append(NSAttributedString(string: " \(item.key) ", attributes: keyAttrs))
            result.append(NSAttributedString(string: " \(item.desc)", attributes: descAttrs))
        }
        return result
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        setupImageViews()
        setupOverlay()
        setupHint()

        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        if displayMode == .real {
            refreshRealSizeLayout()
        }
    }

    // MARK: - Setup

    private func setupImageViews() {
        fitImageView.translatesAutoresizingMaskIntoConstraints = false
        fitImageView.imageScaling = .scaleProportionallyUpOrDown
        // A large image's intrinsic size must never win against the window: NSWindow holds
        // its frame at ~500 priority, and the default 750 compression resistance would
        // let a big image stretch the window past the screen edge (hiding the bottom bar).
        for axis: NSLayoutConstraint.Orientation in [.horizontal, .vertical] {
            fitImageView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: axis)
            fitImageView.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: axis)
        }
        addSubview(fitImageView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = CenteringClipView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .black
        // No visible scroller indicators: they'd sit right on top of the bottom overlay bar.
        // Trackpad scrolling and click-drag panning both still work without them.
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.isHidden = true
        // Layer-back the scroll chain so trackpad scrolling is GPU-composited instead of
        // re-rendering the (possibly huge) image on every scroll tick.
        scrollView.wantsLayer = true
        scrollView.contentView.wantsLayer = true

        realImageView.imageScaling = .scaleNone
        realImageView.wantsLayer = true
        scrollView.documentView = realImageView

        addSubview(scrollView)

        NSLayoutConstraint.activate([
            fitImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fitImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fitImageView.topAnchor.constraint(equalTo: topAnchor),
            fitImageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupOverlay() {
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        overlay.layer?.cornerRadius = 12
        // Keep the bar composited above the scroll view no matter how AppKit
        // reshuffles sibling layers during scrolling of large images.
        overlay.layer?.zPosition = 100
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)

        legendLabel.font = .systemFont(ofSize: 11, weight: .regular)
        legendLabel.alignment = .center
        legendLabel.attributedStringValue = Self.legend(toggleLabel: "real size")

        resolutionLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        resolutionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        resolutionLabel.alignment = .right

        for field in [legendLabel, resolutionLabel] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isEditable = false
            field.isBordered = false
            field.drawsBackground = false
        }

        overlay.addSubview(legendLabel)
        overlay.addSubview(resolutionLabel)

        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            overlay.heightAnchor.constraint(equalToConstant: 28),

            legendLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            legendLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),

            resolutionLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -10),
            resolutionLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])
    }

    private func setupHint() {
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        hintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.isEditable = false
        hintLabel.isBordered = false
        hintLabel.drawsBackground = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Loading

    func load(url: URL) {
        display(url: url)
        scanSiblings(for: url)
    }

    private func display(url: URL) {
        currentURL = url
        let image = NSImage(contentsOf: url)
        fitImageView.image = image
        realImageView.image = image
        hintLabel.isHidden = true
        window?.title = url.path
        window?.representedURL = url
        UserDefaults.standard.set(url.path, forKey: "lastImagePath")
        window?.makeFirstResponder(self)

        if let image, let pixelSize = Self.pixelSize(of: image) {
            resolutionLabel.stringValue = String(format: "%d x %d", Int(pixelSize.width), Int(pixelSize.height))
        } else {
            resolutionLabel.stringValue = ""
        }

        applyDisplayMode()
    }

    private func scanSiblings(for url: URL) {
        let folder = url.deletingLastPathComponent()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        siblings = contents
            .filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        currentIndex = siblings.firstIndex(of: url) ?? 0
    }

    // MARK: - Navigation

    private func navigate(by delta: Int) {
        guard !siblings.isEmpty else {
            NSSound.beep()
            return
        }
        let newIndex = currentIndex + delta
        guard siblings.indices.contains(newIndex) else {
            NSSound.beep()
            return
        }
        currentIndex = newIndex
        display(url: siblings[currentIndex])
    }

    private func randomImage() {
        guard siblings.count > 1 else {
            NSSound.beep()
            return
        }
        var newIndex: Int
        repeat {
            newIndex = Int.random(in: 0..<siblings.count)
        } while newIndex == currentIndex
        currentIndex = newIndex
        display(url: siblings[currentIndex])
    }

    // MARK: - Display mode

    private func toggleDisplayMode() {
        displayMode = (displayMode == .fit) ? .real : .fit
        applyDisplayMode()
    }

    private func applyDisplayMode() {
        switch displayMode {
        case .fit:
            fitImageView.isHidden = false
            scrollView.isHidden = true
            legendLabel.attributedStringValue = Self.legend(toggleLabel: "real size")
        case .real:
            fitImageView.isHidden = true
            scrollView.isHidden = false
            legendLabel.attributedStringValue = Self.legend(toggleLabel: "fit screen")
            layoutRealSize()
        }
    }

    private func layoutRealSize() {
        guard let image = realImageView.image else { return }
        let pixelSize = Self.pixelSize(of: image) ?? image.size
        realImageView.frame = NSRect(origin: .zero, size: pixelSize)

        // Force the whole container to settle its final size now, so the clip view's
        // bounds below are accurate rather than relying on a later, uncertain layout pass.
        layoutSubtreeIfNeeded()
        refreshRealSizeLayout()
        // The first unhide of the scroll view can trigger one more layout pass that
        // shifts the scroll origin; recenter again after it settles.
        DispatchQueue.main.async { [weak self] in
            self?.refreshRealSizeLayout()
        }
    }

    /// Recenters the image and locks scrolling/panning on any axis where it already
    /// fits the window, so a fully-visible image can't rubber-band or be dragged.
    private func refreshRealSizeLayout() {
        let clipView = scrollView.contentView
        let doc = realImageView.frame.size
        let visible = clipView.bounds.size

        scrollView.horizontalScrollElasticity = doc.width > visible.width ? .automatic : .none
        scrollView.verticalScrollElasticity = doc.height > visible.height ? .automatic : .none

        let target = NSRect(
            origin: NSPoint(x: (doc.width - visible.width) / 2,
                            y: (doc.height - visible.height) / 2),
            size: visible
        )
        // Set the bounds origin directly (constrained the same way live scrolling is);
        // scroll(to:) can be coalesced away, this cannot.
        clipView.setBoundsOrigin(clipView.constrainBoundsRect(target).origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private static func pixelSize(of image: NSImage) -> NSSize? {
        guard let rep = image.representations.first else { return nil }
        return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: navigate(by: -1); return // left arrow
        case 124: navigate(by: 1); return  // right arrow
        default: break
        }

        if let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "r": randomImage(); return
            case "0": toggleDisplayMode(); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL else {
            return false
        }
        load(url: url)
        return true
    }
}
