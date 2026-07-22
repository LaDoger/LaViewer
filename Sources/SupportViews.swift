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
/// selection itself is outlined. Mouse-transparent.
final class CropOverlayView: NSView {
    /// Selection rect in this view's coordinate space, or nil for no selection.
    var selectionRect: NSRect? {
        didSet { needsDisplay = true }
    }

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
    }
}
