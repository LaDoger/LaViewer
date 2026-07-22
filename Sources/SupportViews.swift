import Cocoa

/// Centers its document view when the document is smaller than the visible area;
/// otherwise scrolls normally within the document's bounds.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let docFrame = documentView.frame
        if docFrame.width < rect.width {
            rect.origin.x = (docFrame.width - rect.width) / 2
        }
        if docFrame.height < rect.height {
            rect.origin.y = (docFrame.height - rect.height) / 2
        }
        return rect
    }
}

/// An image view that never intercepts mouse events, so clicks and drags fall
/// through to the container (ImageView), which owns crop-selection handling.
final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Draws the crop selection: everything outside the selection is dimmed, the
/// selection is outlined with corner handles and a "k crop" hint badge.
/// Mouse-transparent.
final class CropOverlayView: NSView {
    /// Selection rect in this view's coordinate space, or nil for no selection.
    var selectionRect: NSRect? {
        didSet {
            if selectionRect == nil { hintRect = nil }
            needsDisplay = true
        }
    }

    /// Where the "k crop" badge was last drawn (view coordinates), for click hit-testing.
    private(set) var hintRect: NSRect?

    private static let hintText: NSAttributedString = {
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75),
        ]
        let s = NSMutableAttributedString(string: "k", attributes: keyAttrs)
        s.append(NSAttributedString(string: " crop", attributes: descAttrs))
        return s
    }()

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let sel = selectionRect else { return }

        let outside = NSBezierPath(rect: bounds)
        outside.append(NSBezierPath(rect: sel))
        outside.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        outside.fill()

        let border = NSBezierPath(rect: sel.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        NSColor.white.setStroke()
        border.stroke()

        drawHandles(for: sel)
        drawHint(for: sel)
    }

    /// Preview-style corner brackets: thick rounded L-shapes hugging each corner.
    private func drawHandles(for sel: NSRect) {
        let leg: CGFloat = 14
        let corners: [(point: NSPoint, dx: CGFloat, dy: CGFloat)] = [
            (NSPoint(x: sel.minX, y: sel.minY), 1, 1),
            (NSPoint(x: sel.minX, y: sel.maxY), 1, -1),
            (NSPoint(x: sel.maxX, y: sel.minY), -1, 1),
            (NSPoint(x: sel.maxX, y: sel.maxY), -1, -1),
        ]
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        for corner in corners {
            path.move(to: NSPoint(x: corner.point.x, y: corner.point.y + corner.dy * leg))
            path.line(to: corner.point)
            path.line(to: NSPoint(x: corner.point.x + corner.dx * leg, y: corner.point.y))
        }
        // Dark underlay first so the brackets stay visible over light image areas.
        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 5
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = 3
        path.stroke()
    }

    private func drawHint(for sel: NSRect) {
        let textSize = Self.hintText.size()
        let padH: CGFloat = 7
        let padV: CGFloat = 3
        let pillSize = NSSize(width: textSize.width + padH * 2, height: textSize.height + padV * 2)

        // Inside the selection's bottom-right corner when it fits; otherwise just
        // below-right outside. Clamped to stay on screen either way.
        var origin = NSPoint(x: sel.maxX - 8 - pillSize.width, y: sel.minY + 8)
        if pillSize.width + 16 > sel.width || pillSize.height + 16 > sel.height {
            origin = NSPoint(x: sel.maxX - pillSize.width, y: sel.minY - 8 - pillSize.height)
        }
        origin.x = max(4, min(origin.x, bounds.maxX - pillSize.width - 4))
        origin.y = max(4, min(origin.y, bounds.maxY - pillSize.height - 4))

        let pillRect = NSRect(origin: origin, size: pillSize)
        hintRect = pillRect
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 5, yRadius: 5).fill()
        Self.hintText.draw(at: NSPoint(x: origin.x + padH, y: origin.y + padV))
    }
}
