import AppKit

/// Picto de la barre de menus : une pilule pleine (rectangle horizontal aux bords
/// arrondis) avec, evides en negatif, un mini-metronome a gauche et le tempo a droite.
/// Fond opaque, motifs transparents. Image "template" pour s'adapter aux barres
/// claire et sombre. La hauteur suit `pointSize` (plafond = hauteur de la barre).
enum MenuIcon {
    /// Hauteur du picto en points (plafond utile = NSStatusBar.system.thickness, ~22).
    static var pointSize: CGFloat = 22
    private static let baseH: CGFloat = 22

    /// Texte affiche a l'etat idle (aucun tempo). nil = pas de nombre (mini-metronome seul).
    static let idleText: String? = nil

    /// - label : tempo deja formate (ex. "108.5"), ou nil pour l'idle (metronome seul).
    /// - learning : pendant l'apprentissage, on montre la main dediee.
    static func image(label: String?, learning: Bool) -> NSImage {
        if learning {
            let img = NSImage(systemSymbolName: "hand.point.up.left", accessibilityDescription: "VolcaClock")
                ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
            img.isTemplate = true
            return img
        }
        return pill(text: label ?? idleText)
    }

    private static func numFont(_ pt: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: pt, weight: .bold)
    }

    // Tout est dessine dans une base de hauteur 22, puis mis a l'echelle vers pointSize.
    private static let inset: CGFloat = 1.5
    private static let padL: CGFloat = 3.5
    private static let gap: CGFloat = 3.0
    private static let padR: CGFloat = 4.0
    private static let hintW: CGFloat = 9.0
    private static let numPt: CGFloat = 12.5

    private static func pill(text: String?) -> NSImage {
        let scale = pointSize / baseH
        let numW: CGFloat = text.map { ($0 as NSString).size(withAttributes: [.font: numFont(numPt)]).width } ?? 0
        let contentW = padL + hintW + (text != nil ? gap + numW : 0) + padR
        let w0 = inset + contentW + inset

        let image = NSImage(size: NSSize(width: w0 * scale, height: pointSize))
        image.lockFocus()
        let t = NSAffineTransform()
        t.scale(by: scale)
        t.concat()

        NSColor.black.set()
        let pill = NSBezierPath(
            roundedRect: CGRect(x: inset, y: inset, width: w0 - 2 * inset, height: baseH - 2 * inset),
            xRadius: 5.5, yRadius: 5.5)
        pill.fill()

        // Motifs evides (transparents) dans la pilule pleine.
        let g = NSGraphicsContext.current!
        g.saveGraphicsState()
        g.compositingOperation = .destinationOut
        drawMetroHint(x: inset + padL)
        if let text { drawNumber(text, x: inset + padL + hintW + gap) }
        g.restoreGraphicsState()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // Mini-metronome : trapeze + aiguille, dans une boite de largeur hintW, centre vertical.
    private static func drawMetroHint(x: CGFloat) {
        let w = hintW, h: CGFloat = 12
        let y0 = (baseH - h) / 2
        NSColor.black.setStroke()
        let body = NSBezierPath()
        body.move(to: CGPoint(x: x + w * 0.32, y: y0 + h))
        body.line(to: CGPoint(x: x + w * 0.68, y: y0 + h))
        body.line(to: CGPoint(x: x + w, y: y0))
        body.line(to: CGPoint(x: x, y: y0))
        body.close()
        body.lineWidth = 1.2
        body.lineJoinStyle = .round
        body.stroke()
        let needle = NSBezierPath()
        needle.move(to: CGPoint(x: x + w * 0.5, y: y0 + h * 0.35))
        needle.line(to: CGPoint(x: x + w * 0.28, y: y0 + h))
        needle.lineWidth = 1.0
        needle.lineCapStyle = .round
        needle.stroke()
    }

    private static func drawNumber(_ text: String, x: CGFloat) {
        let font = numFont(numPt)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let size = (text as NSString).size(withAttributes: attrs)
        let y = (baseH - size.height) / 2
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }
}
