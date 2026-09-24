import AppKit
import SwiftUI

/// Viewport geometry only: resizing must never rewrite graph coordinates or wiring.
enum CanvasViewportLayout {
    static func contentSize(viewport: CGSize, positions: [CGPoint], nodeScale: CGFloat, minimumSize: CGSize = .zero) -> CGSize {
        let margin = max(80, 78 * nodeScale)
        guard !positions.isEmpty else { return viewport }
        var size = CGSize(width: max(viewport.width, minimumSize.width),
                          height: max(viewport.height, minimumSize.height))
        for point in positions where point != .zero && point.x.isFinite && point.y.isFinite {
            // Leave room for End as well as the last effect.
            size.width = max(size.width, point.x + margin + 120)
            size.height = max(size.height, point.y + margin)
        }
        return size
    }

    static func visibleRect(viewport: CGRect, document: CGRect) -> CGRect {
        CGRect(x: viewport.minX - document.minX, y: viewport.minY - document.minY,
               width: viewport.width, height: viewport.height)
    }

    static func terminalX(viewportWidth: CGFloat, documentWidth: CGFloat) -> CGFloat {
        let availableWidth = viewportWidth > 0 ? min(viewportWidth, documentWidth) : documentWidth
        return max(availableWidth - 80, 100)
    }

    static func overlayPosition(_ point: CGPoint, size: CGSize, visibleRect: CGRect) -> CGPoint {
        let minX = visibleRect.minX + size.width * 0.5 + 12
        let minY = visibleRect.minY + size.height * 0.5 + 12
        return CGPoint(
            x: min(max(point.x, minX), max(minX, visibleRect.maxX - size.width * 0.5 - 12)),
            y: min(max(point.y, minY), max(minY, visibleRect.maxY - size.height * 0.5 - 12))
        )
    }

    /// Places a context panel next to the click instead of centering the panel
    /// on it. Prefer below-right, flip at the viewport edges, then clamp as a
    /// final safeguard for unusually small windows.
    static func contextMenuPosition(
        click: CGPoint,
        size: CGSize,
        visibleRect: CGRect,
        gap: CGFloat = 8
    ) -> CGPoint {
        let halfWidth = size.width * 0.5
        let halfHeight = size.height * 0.5
        var position = CGPoint(
            x: click.x + gap + halfWidth,
            y: click.y + gap + halfHeight
        )
        if position.x + halfWidth > visibleRect.maxX - 12 {
            position.x = click.x - gap - halfWidth
        }
        if position.y + halfHeight > visibleRect.maxY - 12 {
            position.y = click.y - gap - halfHeight
        }
        return overlayPosition(position, size: size, visibleRect: visibleRect)
    }
}
