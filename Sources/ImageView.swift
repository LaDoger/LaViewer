import Cocoa
import UniformTypeIdentifiers

final class ImageView: NSView {
    private let imageView = NSImageView()
    private let overlay = NSView()
    private let legendLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "Drop an image file here, or press ⌘O")

    private var currentURL: URL?
    private var siblings: [URL] = []
    private var currentIndex: Int = 0

    private static let legend: NSAttributedString = {
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
            ("←", "prev image"),
            ("→", "next image"),
            ("R", "random image"),
        ]
        let result = NSMutableAttributedString()
        for (i, item) in items.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "     ", attributes: descAttrs)) }
            result.append(NSAttributedString(string: " \(item.key) ", attributes: keyAttrs))
            result.append(NSAttributedString(string: " \(item.desc)", attributes: descAttrs))
        }
        return result
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        setupImageView()
        setupOverlay()
        setupHint()

        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Setup

    private func setupImageView() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupOverlay() {
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        overlay.layer?.cornerRadius = 12
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)

        legendLabel.font = .systemFont(ofSize: 11, weight: .regular)
        legendLabel.alignment = .center
        legendLabel.attributedStringValue = Self.legend
        legendLabel.translatesAutoresizingMaskIntoConstraints = false
        legendLabel.isEditable = false
        legendLabel.isBordered = false
        legendLabel.drawsBackground = false

        overlay.addSubview(legendLabel)

        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            overlay.heightAnchor.constraint(equalToConstant: 28),

            legendLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            legendLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
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
        imageView.image = NSImage(contentsOf: url)
        hintLabel.isHidden = true
        window?.title = url.path
        window?.representedURL = url
        UserDefaults.standard.set(url.path, forKey: "lastImagePath")
        window?.makeFirstResponder(self)
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

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: navigate(by: -1); return // left arrow
        case 124: navigate(by: 1); return  // right arrow
        default: break
        }

        if let chars = event.charactersIgnoringModifiers?.lowercased(), chars == "r" {
            randomImage()
            return
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
