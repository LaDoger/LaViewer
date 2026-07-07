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

/// An image view that can be click-and-dragged to pan within its enclosing scroll view.
final class PannableImageView: NSImageView {
    private var lastDragLocation: NSPoint?

    override func mouseDown(with event: NSEvent) {
        lastDragLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let scrollView = enclosingScrollView else { return }
        // Track the cursor's absolute position rather than event.deltaX/deltaY: the
        // latter are raw hardware deltas that aren't reliably populated by every
        // input source (e.g. some synthesized drags), so panning could silently no-op.
        let location = event.locationInWindow
        let previous = lastDragLocation ?? location
        lastDragLocation = location

        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        origin.x -= location.x - previous.x
        origin.y -= location.y - previous.y
        // scroll(to:) does not itself call constrainBoundsRect, so an unconstrained
        // origin here would let a fully-visible image be dragged around anyway.
        let constrained = clipView.constrainBoundsRect(NSRect(origin: origin, size: clipView.bounds.size))
        clipView.setBoundsOrigin(constrained.origin)
        scrollView.reflectScrolledClipView(clipView)
    }
}
