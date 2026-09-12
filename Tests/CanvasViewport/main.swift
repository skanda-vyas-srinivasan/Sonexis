import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let presets = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
var cases = 0
for preset in presets {
    let graph = preset["graph"] as! [String: Any]
    let nodes = graph["nodes"] as! [[String: Any]]
    let positions = nodes.map { node -> CGPoint in
        let coordinates = node["position"] as! [Double]
        return CGPoint(x: coordinates[0], y: coordinates[1])
    }
    for viewport in [CGSize(width: 820, height: 300), CGSize(width: 820, height: 650), CGSize(width: 1240, height: 900)] {
        for scale: CGFloat in [0.4, 1, 1.8] {
            let size = CanvasViewportLayout.contentSize(viewport: viewport, positions: positions, nodeScale: scale)
            expect(size.width >= viewport.width && size.height >= viewport.height, "Document smaller than viewport")
            for point in positions {
                let halfTile = 65 * scale
                // A native scroll offset can reveal the entire node without moving it.
                let offset = CGPoint(x: min(max(0, point.x - viewport.width / 2), size.width - viewport.width),
                                     y: min(max(0, point.y - viewport.height / 2), size.height - viewport.height))
                let node = CGRect(x: point.x - halfTile, y: point.y - halfTile, width: halfTile * 2, height: halfTile * 2)
                // Existing zoom may extend a near-top tile above zero; test overflow at right/bottom.
                expect(node.maxX <= offset.x + viewport.width && node.maxY <= offset.y + viewport.height,
                       "Preset node remains unreachable: \(preset["name"]!)")
            }
            cases += 1
        }
    }
}
let viewport = CGSize(width: 820, height: 650)
expect(CanvasViewportLayout.contentSize(viewport: viewport, positions: [], nodeScale: 1) == viewport, "Empty canvas scrolls")
expect(CanvasViewportLayout.contentSize(viewport: viewport, positions: [CGPoint(x: 260, y: 180), CGPoint(x: 600, y: 180)], nodeScale: 1) == viewport, "Fitting chain unnecessarily scrolls")
expect(CanvasViewportLayout.terminalX(viewportWidth: viewport.width, documentWidth: 940) == 740,
       "Expanding the document must not push End outside the window")
expect(CanvasViewportLayout.terminalX(viewportWidth: 1240, documentWidth: viewport.width) == 740,
       "A window wider than its document keeps End inside the document")
let wide = CGSize(width: 1240, height: 900)
let points = [CGPoint(x: 264.6875, y: 81.57421875), CGPoint(x: 545.33203125, y: 532.03515625), CGPoint(x: 861.5546875, y: 148.2890625)]
let narrowSize = CanvasViewportLayout.contentSize(viewport: viewport, positions: points, nodeScale: 1)
expect(narrowSize.width > viewport.width, "Original Brighten clipping fixture has no scroll range")
expect(CanvasViewportLayout.contentSize(viewport: wide, positions: points, nodeScale: 1) == wide, "Widening retains unnecessary scroll range")
let visible = CanvasViewportLayout.visibleRect(viewport: CGRect(x: 250, y: 180, width: 820, height: 400),
                                               document: CGRect(x: -50, y: -120, width: 1200, height: 800))
expect(visible == CGRect(x: 300, y: 300, width: 820, height: 400), "Scrolled coordinate conversion is wrong")
for point in [CGPoint(x: 0, y: 0), CGPoint(x: 1200, y: 800), CGPoint(x: 600, y: 450)] {
    let menuSize = CGSize(width: 208, height: 240)
    let center = CanvasViewportLayout.overlayPosition(point, size: menuSize, visibleRect: visible)
    let frame = CGRect(x: center.x - menuSize.width / 2, y: center.y - menuSize.height / 2,
                       width: menuSize.width, height: menuSize.height)
    expect(visible.insetBy(dx: 12, dy: 12).contains(frame), "Scrolled menu extends outside viewport")
}
let contextSize = CGSize(width: 196, height: 108)
let centralClick = CGPoint(x: 600, y: 450)
let centralMenu = CanvasViewportLayout.contextMenuPosition(
    click: centralClick, size: contextSize, visibleRect: visible
)
expect(centralMenu == CGPoint(x: centralClick.x + 8 + contextSize.width / 2,
                              y: centralClick.y + 8 + contextSize.height / 2),
       "Context menu should open below-right of the click")
let attachedWireMenu = CanvasViewportLayout.contextMenuPosition(
    click: centralClick, size: contextSize, visibleRect: visible, gap: -18
)
expect(attachedWireMenu == CGPoint(x: centralClick.x - 18 + contextSize.width / 2,
                                   y: centralClick.y - 18 + contextSize.height / 2),
       "Wire context menu should place its first action beneath the click")
let edgeClick = CGPoint(x: visible.maxX - 4, y: visible.maxY - 4)
let edgeMenu = CanvasViewportLayout.contextMenuPosition(
    click: edgeClick, size: contextSize, visibleRect: visible
)
expect(edgeMenu.x < edgeClick.x && edgeMenu.y < edgeClick.y,
       "Context menu should flip left and up at the viewport edges")
let edgeFrame = CGRect(x: edgeMenu.x - contextSize.width / 2,
                       y: edgeMenu.y - contextSize.height / 2,
                       width: contextSize.width, height: contextSize.height)
expect(visible.insetBy(dx: 12, dy: 12).contains(edgeFrame),
       "Flipped context menu must remain inside the visible canvas")
print("PASS: \(cases) bundled-preset viewport/zoom cases; Brighten overflow, widening, empty/fitting canvas, scrolled menu coordinates")

let dragged = points.dropLast() + [CGPoint(x: points.last!.x - 40, y: points.last!.y + 30)]
let afterDrag = CanvasViewportLayout.contentSize(viewport: viewport, positions: Array(dragged), nodeScale: 1, minimumSize: narrowSize)
expect(afterDrag == narrowSize, "Dragging the rightmost node inward changes the scroll extent")
expect(CanvasViewportLayout.contentSize(viewport: viewport, positions: [], nodeScale: 1, minimumSize: narrowSize) == viewport,
       "Clearing the canvas retains an obsolete scroll extent")
print("PASS: drag retains scroll extent; clearing releases it")
