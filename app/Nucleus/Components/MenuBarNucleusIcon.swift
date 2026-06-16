import AppKit

enum MenuBarNucleusIcon {
    private static let cachedImage: NSImage = makeTemplateImage()

    static func templateImage() -> NSImage {
        cachedImage
    }

    private static func makeTemplateImage(pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.isTemplate = true
            return image
        }

        drawAtom(in: context, size: pointSize)
        image.isTemplate = true
        return image
    }

    private static func drawAtom(in context: CGContext, size: CGFloat) {
        let center = CGPoint(x: size / 2, y: size / 2)
        let orbitWidth = size * 0.92
        let orbitHeight = size * 0.36
        let lineWidth = max(1.15, size * 0.1)
        let nucleusRadius = size * 0.1

        context.setFillColor(NSColor.black.cgColor)
        context.addEllipse(in: CGRect(
            x: center.x - nucleusRadius,
            y: center.y - nucleusRadius,
            width: nucleusRadius * 2,
            height: nucleusRadius * 2
        ))
        context.fillPath()

        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)

        for degrees in [CGFloat(0), 60, -60] {
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: degrees * .pi / 180)
            context.addEllipse(in: CGRect(
                x: -orbitWidth / 2,
                y: -orbitHeight / 2,
                width: orbitWidth,
                height: orbitHeight
            ))
            context.strokePath()
            context.restoreGState()
        }
    }
}
