import Cocoa
import ImageIO
import UniformTypeIdentifiers

final class ImageView: NSView {
    private enum DisplayMode {
        case fit
        case real
    }

    private let fitImageView = PassthroughImageView()
    private let scrollView = NSScrollView()
    private let realImageView = PassthroughImageView()

    private let overlay = NSView()
    private let cropOverlay = CropOverlayView()
    private let legendLabel = NSTextField(labelWithString: "")
    private let resolutionLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "Drop a file here, or press ⌘O")
    private let centerMessageLabel = NSTextField(labelWithString: "")

    private var currentURL: URL?
    private var siblings: [URL] = []
    private var currentIndex: Int = 0
    private var displayMode: DisplayMode = .fit
    private var imagePixelSize: NSSize = .zero

    private let widthField = SelectAllTextField(string: "")
    private let heightField = SelectAllTextField(string: "")
    private let dimsSeparatorLabel = NSTextField(labelWithString: "x")
    private let editLabel = NSTextField(labelWithString: "edit:")
    private let colorSwatch = NSView()
    private let colorHexLabel = NSTextField(labelWithString: "")
    private var colorSampleRep: NSBitmapImageRep?

    /// Crop selection in image-pixel coordinates, origin at the image's top-left.
    private var cropSelectionPx: NSRect?

    /// What the current mouse drag is doing to the selection. Anchors/offsets are
    /// in image-pixel space.
    private enum DragMode {
        /// Rubber-banding a new selection from a fixed anchor point.
        case select(anchor: NSPoint)
        /// Moving the whole selection; offset is cursor minus selection origin.
        case move(offset: NSPoint)
        /// Resizing: a non-nil anchor means that axis rubber-bands between the anchor
        /// and the cursor; nil means that axis keeps its fixed range.
        case resize(anchorX: CGFloat?, anchorY: CGFloat?,
                    fixedX: (min: CGFloat, max: CGFloat), fixedY: (min: CGFloat, max: CGFloat))
    }
    private var dragMode: DragMode?

    private var boundsObserver: NSObjectProtocol?

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
        setupCropOverlay()
        setupOverlay()
        setupCenterMessage()
        setupHint()

        registerForDraggedTypes([.fileURL])

        // Keep the selection glued to the image while the user scrolls in real-size mode.
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.refreshCropOverlay()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        if displayMode == .real {
            refreshRealSizeLayout()
        }
        refreshCropOverlay()
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
        // Trackpad scrolling still works without them.
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

    private func setupCropOverlay() {
        cropOverlay.translatesAutoresizingMaskIntoConstraints = false
        cropOverlay.wantsLayer = true
        cropOverlay.layer?.zPosition = 50
        addSubview(cropOverlay)

        NSLayoutConstraint.activate([
            cropOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            cropOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            cropOverlay.topAnchor.constraint(equalTo: topAnchor),
            cropOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
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

        dimsSeparatorLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        dimsSeparatorLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        dimsSeparatorLabel.translatesAutoresizingMaskIntoConstraints = false
        dimsSeparatorLabel.isEditable = false
        dimsSeparatorLabel.isBordered = false
        dimsSeparatorLabel.drawsBackground = false
        dimsSeparatorLabel.isHidden = true

        // Style the editable fields like the resolution label (same font/color,
        // baseline-aligned) with a subtle grey chip as the editability hint.
        // The chip is the layer's background so the cell keeps its tight text
        // metrics and the vertical padding stays symmetric.
        for field in [widthField, heightField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.isEditable = true
            field.isBordered = false
            field.drawsBackground = false
            field.textColor = NSColor.white.withAlphaComponent(0.6)
            field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            field.focusRingType = .none
            field.wantsLayer = true
            field.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            field.layer?.cornerRadius = 3
            field.isHidden = true
            field.target = self
            field.action = #selector(dimensionFieldEdited(_:))
            field.delegate = self
        }
        widthField.alignment = .right
        heightField.alignment = .left
        widthField.nextKeyView = heightField
        heightField.nextKeyView = widthField

        editLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        editLabel.font = .systemFont(ofSize: 11)
        editLabel.translatesAutoresizingMaskIntoConstraints = false
        editLabel.isEditable = false
        editLabel.isBordered = false
        editLabel.drawsBackground = false
        editLabel.isHidden = true

        colorSwatch.translatesAutoresizingMaskIntoConstraints = false
        colorSwatch.wantsLayer = true
        colorSwatch.layer?.cornerRadius = 2
        colorSwatch.layer?.borderWidth = 1
        colorSwatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        colorSwatch.isHidden = true

        colorHexLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        colorHexLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        colorHexLabel.translatesAutoresizingMaskIntoConstraints = false
        colorHexLabel.isEditable = false
        colorHexLabel.isBordered = false
        colorHexLabel.drawsBackground = false
        colorHexLabel.isHidden = true

        overlay.addSubview(legendLabel)
        overlay.addSubview(resolutionLabel)
        overlay.addSubview(editLabel)
        overlay.addSubview(widthField)
        overlay.addSubview(dimsSeparatorLabel)
        overlay.addSubview(heightField)
        overlay.addSubview(colorSwatch)
        overlay.addSubview(colorHexLabel)

        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            overlay.heightAnchor.constraint(equalToConstant: 28),

            legendLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            legendLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),

            resolutionLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -10),
            resolutionLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),

            heightField.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -10),
            heightField.firstBaselineAnchor.constraint(equalTo: dimsSeparatorLabel.firstBaselineAnchor),
            heightField.widthAnchor.constraint(equalToConstant: 44),

            dimsSeparatorLabel.trailingAnchor.constraint(equalTo: heightField.leadingAnchor, constant: -4),
            dimsSeparatorLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),

            widthField.trailingAnchor.constraint(equalTo: dimsSeparatorLabel.leadingAnchor, constant: -4),
            widthField.firstBaselineAnchor.constraint(equalTo: dimsSeparatorLabel.firstBaselineAnchor),
            widthField.widthAnchor.constraint(equalToConstant: 44),

            editLabel.trailingAnchor.constraint(equalTo: widthField.leadingAnchor, constant: -6),
            editLabel.firstBaselineAnchor.constraint(equalTo: dimsSeparatorLabel.firstBaselineAnchor),

            colorSwatch.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 10),
            colorSwatch.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            colorSwatch.widthAnchor.constraint(equalToConstant: 10),
            colorSwatch.heightAnchor.constraint(equalToConstant: 10),

            colorHexLabel.leadingAnchor.constraint(equalTo: colorSwatch.trailingAnchor, constant: 6),
            colorHexLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])
    }

    private func setupCenterMessage() {
        centerMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        centerMessageLabel.isEditable = false
        centerMessageLabel.isBordered = false
        centerMessageLabel.drawsBackground = false
        centerMessageLabel.alignment = .center
        centerMessageLabel.textColor = .white
        centerMessageLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        centerMessageLabel.wantsLayer = true
        centerMessageLabel.layer?.zPosition = 200
        centerMessageLabel.alphaValue = 0
        centerMessageLabel.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.8)
            s.shadowBlurRadius = 6
            s.shadowOffset = NSSize(width: 0, height: -1)
            return s
        }()
        addSubview(centerMessageLabel)

        NSLayoutConstraint.activate([
            centerMessageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerMessageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            centerMessageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            centerMessageLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
        ])
    }

    /// Flash a message in the center that fades out.
    private func showCenterMessage(_ text: String) {
        centerMessageLabel.stringValue = text
        centerMessageLabel.layer?.removeAllAnimations()
        centerMessageLabel.alphaValue = 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 1.6
                self.centerMessageLabel.animator().alphaValue = 0
            }
        }
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
            imagePixelSize = pixelSize
        } else {
            imagePixelSize = .zero
        }

        // Bitmap for cursor color sampling, from the file's original pixels.
        colorSampleRep = nil
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            colorSampleRep = NSBitmapImageRep(cgImage: cgImage)
        }
        hideColorSample()

        setCropSelection(nil)
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
        setCropSelection(nil)
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
        guard realImageView.image != nil, imagePixelSize.width > 0 else { return }
        realImageView.frame = NSRect(origin: .zero, size: imagePixelSize)

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

    /// Recenters the image and locks scrolling on any axis where it already
    /// fits the window, so a fully-visible image can't rubber-band.
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

    // MARK: - Coordinate mapping (view space <-> image pixel space)

    /// The rect the image currently occupies, in this view's coordinates.
    private func currentImageFrameInView() -> NSRect? {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return nil }
        switch displayMode {
        case .fit:
            let scale = min(bounds.width / imagePixelSize.width, bounds.height / imagePixelSize.height)
            let size = NSSize(width: imagePixelSize.width * scale, height: imagePixelSize.height * scale)
            return NSRect(x: (bounds.width - size.width) / 2,
                          y: (bounds.height - size.height) / 2,
                          width: size.width, height: size.height)
        case .real:
            return convert(realImageView.bounds, from: realImageView)
        }
    }

    /// View point -> image pixel point (top-left origin), clamped to the image.
    private func pixelPoint(fromViewPoint point: NSPoint) -> NSPoint? {
        guard let frame = currentImageFrameInView(), frame.width > 0, frame.height > 0 else { return nil }
        let relX = min(max((point.x - frame.minX) / frame.width, 0), 1)
        let relY = min(max((point.y - frame.minY) / frame.height, 0), 1)
        return NSPoint(x: relX * imagePixelSize.width,
                       y: (1 - relY) * imagePixelSize.height)
    }

    /// Image pixel rect (top-left origin) -> view rect.
    private func viewRect(fromPixelRect rect: NSRect) -> NSRect? {
        guard let frame = currentImageFrameInView(), imagePixelSize.width > 0 else { return nil }
        let sx = frame.width / imagePixelSize.width
        let sy = frame.height / imagePixelSize.height
        return NSRect(x: frame.minX + rect.minX * sx,
                      y: frame.minY + (imagePixelSize.height - rect.maxY) * sy,
                      width: rect.width * sx,
                      height: rect.height * sy)
    }

    // MARK: - Crop selection

    private func setCropSelection(_ rect: NSRect?) {
        cropSelectionPx = rect
        refreshCropOverlay()
        updateDimensionControls()
    }

    private func refreshCropOverlay() {
        if let sel = cropSelectionPx, let viewSel = viewRect(fromPixelRect: sel) {
            cropOverlay.selectionRect = viewSel
        } else {
            cropOverlay.selectionRect = nil
        }
    }

    private func updateDimensionControls() {
        if let sel = cropSelectionPx {
            resolutionLabel.isHidden = true
            editLabel.isHidden = false
            widthField.isHidden = false
            dimsSeparatorLabel.isHidden = false
            heightField.isHidden = false
            widthField.stringValue = "\(Int(sel.width))"
            heightField.stringValue = "\(Int(sel.height))"
        } else {
            editLabel.isHidden = true
            widthField.isHidden = true
            dimsSeparatorLabel.isHidden = true
            heightField.isHidden = true
            resolutionLabel.isHidden = false
            if imagePixelSize.width > 0 {
                resolutionLabel.stringValue = String(
                    format: "%d x %d", Int(imagePixelSize.width), Int(imagePixelSize.height))
            } else {
                resolutionLabel.stringValue = ""
            }
        }
    }

    @objc private func dimensionFieldEdited(_ sender: NSTextField) {
        guard var sel = cropSelectionPx else { return }
        if sender === widthField {
            let value = CGFloat(max(1, Int(sender.stringValue) ?? Int(sel.width)))
            sel.size.width = min(value, imagePixelSize.width - sel.minX)
        } else {
            let value = CGFloat(max(1, Int(sender.stringValue) ?? Int(sel.height)))
            sel.size.height = min(value, imagePixelSize.height - sel.minY)
        }
        setCropSelection(sel.integral)
        window?.makeFirstResponder(self)
    }

    /// Where a view-space point falls relative to the current selection.
    /// `nearMinX`/`nearMinY` refer to the view-space min edges of the selection.
    private enum SelectionZone {
        case corner(nearMinX: Bool, nearMinY: Bool)
        case edgeLeft, edgeRight, edgeBottom, edgeTop
        case inside
    }

    private func selectionZone(at point: NSPoint) -> SelectionZone? {
        guard let sel = cropSelectionPx, let viewSel = viewRect(fromPixelRect: sel) else { return nil }

        let cornerTolerance: CGFloat = 14
        let edgeTolerance: CGFloat = 6

        let nearMinX = abs(point.x - viewSel.minX) <= cornerTolerance
        let nearMaxX = abs(point.x - viewSel.maxX) <= cornerTolerance
        let nearMinY = abs(point.y - viewSel.minY) <= cornerTolerance
        let nearMaxY = abs(point.y - viewSel.maxY) <= cornerTolerance
        if (nearMinX || nearMaxX) && (nearMinY || nearMaxY) {
            return .corner(nearMinX: nearMinX, nearMinY: nearMinY)
        }

        let withinY = (viewSel.minY - edgeTolerance...viewSel.maxY + edgeTolerance).contains(point.y)
        let withinX = (viewSel.minX - edgeTolerance...viewSel.maxX + edgeTolerance).contains(point.x)
        if withinY, abs(point.x - viewSel.minX) <= edgeTolerance { return .edgeLeft }
        if withinY, abs(point.x - viewSel.maxX) <= edgeTolerance { return .edgeRight }
        if withinX, abs(point.y - viewSel.minY) <= edgeTolerance { return .edgeBottom }
        if withinX, abs(point.y - viewSel.maxY) <= edgeTolerance { return .edgeTop }

        if viewSel.contains(point) { return .inside }
        return nil
    }

    /// Decide what a mouse press at `point` (view space) does to the existing selection.
    /// Note the y-flip: the view's minY edge is the image's bottom (pixel maxY), so the
    /// pixel-space anchor for a grabbed side is the opposite side.
    private func dragMode(forViewPoint point: NSPoint) -> DragMode? {
        guard let pixel = pixelPoint(fromViewPoint: point) else { return nil }
        guard let sel = cropSelectionPx else { return .select(anchor: pixel) }
        let fixedX = (sel.minX, sel.maxX)
        let fixedY = (sel.minY, sel.maxY)

        switch selectionZone(at: point) {
        case .corner(let nearMinX, let nearMinY):
            return .resize(anchorX: nearMinX ? sel.maxX : sel.minX,
                           anchorY: nearMinY ? sel.minY : sel.maxY,
                           fixedX: fixedX, fixedY: fixedY)
        case .edgeLeft:
            return .resize(anchorX: sel.maxX, anchorY: nil, fixedX: fixedX, fixedY: fixedY)
        case .edgeRight:
            return .resize(anchorX: sel.minX, anchorY: nil, fixedX: fixedX, fixedY: fixedY)
        case .edgeBottom:
            return .resize(anchorX: nil, anchorY: sel.minY, fixedX: fixedX, fixedY: fixedY)
        case .edgeTop:
            return .resize(anchorX: nil, anchorY: sel.maxY, fixedX: fixedX, fixedY: fixedY)
        case .inside:
            return .move(offset: NSPoint(x: pixel.x - sel.minX, y: pixel.y - sel.minY))
        case nil:
            return .select(anchor: pixel)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard currentURL != nil, !overlay.frame.contains(point) else { return }

        // The "k crop" badge acts as a button.
        if let hint = cropOverlay.hintRect, hint.contains(point) {
            cropAndSave()
            return
        }

        let mode = dragMode(forViewPoint: point)
        dragMode = mode
        switch mode {
        case .move:
            NSCursor.closedHand.set()
        case .select:
            // A plain press outside the selection clears it (a click leaves it cleared).
            setCropSelection(nil)
        default:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mode = dragMode else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let current = pixelPoint(fromViewPoint: point) else { return }

        switch mode {
        case .select(let anchor):
            setCropSelection(NSRect(x: min(anchor.x, current.x),
                                    y: min(anchor.y, current.y),
                                    width: abs(anchor.x - current.x),
                                    height: abs(anchor.y - current.y)).integral)
        case .resize(let anchorX, let anchorY, let fixedX, let fixedY):
            let minX = anchorX.map { min($0, current.x) } ?? fixedX.min
            let maxX = anchorX.map { max($0, current.x) } ?? fixedX.max
            let minY = anchorY.map { min($0, current.y) } ?? fixedY.min
            let maxY = anchorY.map { max($0, current.y) } ?? fixedY.max
            setCropSelection(NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral)
        case .move(let offset):
            guard let sel = cropSelectionPx else { return }
            let x = min(max(current.x - offset.x, 0), imagePixelSize.width - sel.width)
            let y = min(max(current.y - offset.y, 0), imagePixelSize.height - sel.height)
            setCropSelection(NSRect(x: x.rounded(), y: y.rounded(), width: sel.width, height: sel.height))
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = nil
        // Anything under 10x10 px was almost certainly an accidental drag or click.
        if let sel = cropSelectionPx, sel.width < 10 || sel.height < 10 {
            setCropSelection(nil)
        }
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    // MARK: - Cursor feedback

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursor(at: point).set()
        updateColorSample(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        hideColorSample()
    }

    // MARK: - Pixel color sampling

    private func updateColorSample(at viewPoint: NSPoint) {
        guard let rep = colorSampleRep,
              !overlay.frame.contains(viewPoint),
              let imageFrame = currentImageFrameInView(), imageFrame.contains(viewPoint),
              let pixel = pixelPoint(fromViewPoint: viewPoint) else {
            hideColorSample()
            return
        }
        let x = min(Int(pixel.x), Int(imagePixelSize.width) - 1)
        let y = min(Int(pixel.y), Int(imagePixelSize.height) - 1)
        guard x >= 0, y >= 0,
              let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
            hideColorSample()
            return
        }
        let r = Int((color.redComponent * 255).rounded())
        let g = Int((color.greenComponent * 255).rounded())
        let b = Int((color.blueComponent * 255).rounded())
        colorHexLabel.stringValue = String(format: "#%02X%02X%02X", r, g, b)
        colorSwatch.layer?.backgroundColor = color.cgColor
        colorSwatch.isHidden = false
        colorHexLabel.isHidden = false
    }

    private func hideColorSample() {
        colorSwatch.isHidden = true
        colorHexLabel.isHidden = true
    }

    /// The cursor that tells the user what a press at `point` would do.
    private func cursor(at point: NSPoint) -> NSCursor {
        guard currentURL != nil, !overlay.frame.contains(point) else { return .arrow }
        if let hint = cropOverlay.hintRect, hint.contains(point) { return .pointingHand }

        switch selectionZone(at: point) {
        case .corner(let nearMinX, let nearMinY):
            if #available(macOS 15.0, *) {
                // View-space corner -> screen position (view minY is the bottom).
                let position: NSCursor.FrameResizePosition = switch (nearMinX, nearMinY) {
                case (true, true): .bottomLeft
                case (true, false): .topLeft
                case (false, true): .bottomRight
                case (false, false): .topRight
                }
                return .frameResize(position: position, directions: .all)
            }
            return .crosshair
        case .edgeLeft, .edgeRight:
            return .resizeLeftRight
        case .edgeBottom, .edgeTop:
            return .resizeUpDown
        case .inside:
            return .openHand
        case nil:
            if let imageFrame = currentImageFrameInView(), imageFrame.contains(point) {
                return .crosshair
            }
            return .arrow
        }
    }

    // MARK: - Crop & save

    private func cropAndSave() {
        guard let url = currentURL,
              let sel = cropSelectionPx, sel.width >= 1, sel.height >= 1 else {
            NSSound.beep()
            return
        }
        // Crop from the file's original pixels, not the display pipeline.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let cropped = fullImage.cropping(to: CGRect(x: sel.minX, y: sel.minY,
                                                          width: sel.width, height: sel.height)) else {
            NSSound.beep()
            return
        }

        let destination = nextCropURL(for: url)
        let typeID = UTType(filenameExtension: destination.pathExtension)?.identifier ?? UTType.png.identifier
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, typeID as CFString, 1, nil) else {
            NSSound.beep()
            return
        }
        CGImageDestinationAddImage(dest, cropped, nil)
        guard CGImageDestinationFinalize(dest) else {
            NSSound.beep()
            return
        }

        setCropSelection(nil)
        showCenterMessage("Saved \(destination.lastPathComponent)")
        // The new file is a sibling image; rescan so arrow-key navigation can reach it.
        scanSiblings(for: url)
    }

    private func nextCropURL(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        var index = 1
        var candidate: URL
        repeat {
            candidate = folder.appendingPathComponent("\(base)_\(index).\(ext)")
            index += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: navigate(by: -1); return // left arrow
        case 124: navigate(by: 1); return  // right arrow
        case 53: setCropSelection(nil); return // escape
        default: break
        }

        if let chars = event.charactersIgnoringModifiers?.lowercased() {
            switch chars {
            case "r": randomImage(); return
            case "0": toggleDisplayMode(); return
            case "k": cropAndSave(); return
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

extension ImageView: NSTextFieldDelegate {
    // Keep the width/height fields digits-only.
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === widthField || field === heightField else { return }
        let filtered = field.stringValue.filter(\.isNumber)
        if filtered != field.stringValue {
            field.stringValue = filtered
        }
    }
}
