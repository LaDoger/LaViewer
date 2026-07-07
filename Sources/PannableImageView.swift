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
    override func mouseDragged(with event: NSEvent) {
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        origin.x -= event.deltaX
        origin.y += event.deltaY
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
    }
}
