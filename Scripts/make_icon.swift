import AppKit

// Renders the app icon: indigo squircle, a fanned pair of cards and a gold magnifier.
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    ctx.saveGState()
    squircle.addClip()
    NSGradient(colors: [NSColor(red: 0.24, green: 0.18, blue: 0.50, alpha: 1), NSColor(red: 0.05, green: 0.04, blue: 0.15, alpha: 1)])!.draw(in: rect, angle: -60)

    func card(angle: CGFloat, dx: CGFloat, face: Bool) {
        ctx.saveGState()
        ctx.translateBy(x: s * (0.46 + dx), y: s * 0.54)
        ctx.rotate(by: angle)
        let cw = s * 0.34, ch = s * 0.48
        let r = CGRect(x: -cw / 2, y: -ch / 2, width: cw, height: ch)
        let p = NSBezierPath(roundedRect: r, xRadius: s * 0.03, yRadius: s * 0.03)
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        (face ? NSColor(white: 0.07, alpha: 1) : NSColor(red: 0.42, green: 0.36, blue: 0.80, alpha: 1)).setFill()
        p.fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        if face {
            // frame, name plate, art window, type line, text box, P/T box: the classic card anatomy
            func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rad: CGFloat) -> NSBezierPath {
                NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: rad, yRadius: rad)
            }
            let b = cw * 0.055, ix = -cw / 2 + b, iw = cw - 2 * b, top = ch / 2 - b
            let parchment = NSColor(red: 0.95, green: 0.90, blue: 0.80, alpha: 1)
            NSColor(red: 0.70, green: 0.20, blue: 0.20, alpha: 1).setFill()
            rr(ix, -ch / 2 + b, iw, ch - 2 * b, s * 0.02).fill()

            let nameH = ch * 0.07, nameY = top - ch * 0.012 - nameH
            parchment.setFill()
            rr(ix + cw * 0.02, nameY, iw - cw * 0.04, nameH, s * 0.012).fill()
            NSColor(white: 0.15, alpha: 1).setFill()
            rr(ix + cw * 0.06, nameY + nameH * 0.32, cw * 0.36, nameH * 0.36, s * 0.004).fill()
            NSColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: ix + iw - cw * 0.04 - nameH * 0.8, y: nameY + nameH * 0.1, width: nameH * 0.8, height: nameH * 0.8)).fill()

            let artH = ch * 0.34, artY = nameY - ch * 0.01 - artH
            let art = rr(ix + cw * 0.02, artY, iw - cw * 0.04, artH, s * 0.008)
            ctx.saveGState()
            art.addClip()
            let ax = ix + cw * 0.02, aw = iw - cw * 0.04
            NSGradient(colors: [NSColor(red: 0.99, green: 0.74, blue: 0.36, alpha: 1), NSColor(red: 0.50, green: 0.24, blue: 0.62, alpha: 1)])!
                .draw(in: CGRect(x: ax, y: artY, width: aw, height: artH), angle: 90)
            NSColor(red: 0.18, green: 0.10, blue: 0.30, alpha: 1).setFill()
            let m = NSBezierPath()
            m.move(to: CGPoint(x: ax, y: artY))
            m.line(to: CGPoint(x: ax, y: artY + artH * 0.30))
            m.line(to: CGPoint(x: ax + aw * 0.28, y: artY + artH * 0.62))
            m.line(to: CGPoint(x: ax + aw * 0.50, y: artY + artH * 0.30))
            m.line(to: CGPoint(x: ax + aw * 0.74, y: artY + artH * 0.52))
            m.line(to: CGPoint(x: ax + aw, y: artY + artH * 0.22))
            m.line(to: CGPoint(x: ax + aw, y: artY))
            m.close()
            m.fill()
            NSColor(white: 1, alpha: 0.9).setFill()
            NSBezierPath(ovalIn: CGRect(x: ax + aw * 0.70, y: artY + artH * 0.68, width: aw * 0.13, height: aw * 0.13)).fill()
            ctx.restoreGState()

            let typeH = ch * 0.055, typeY = artY - ch * 0.01 - typeH
            parchment.setFill()
            rr(ix + cw * 0.02, typeY, iw - cw * 0.04, typeH, s * 0.01).fill()
            NSColor(white: 0.15, alpha: 1).setFill()
            rr(ix + cw * 0.06, typeY + typeH * 0.34, cw * 0.30, typeH * 0.32, s * 0.003).fill()

            let tbY = -ch / 2 + b + ch * 0.02, tbH = typeY - ch * 0.01 - tbY
            parchment.setFill()
            rr(ix + cw * 0.02, tbY, iw - cw * 0.04, tbH, s * 0.008).fill()
            NSColor(white: 0.55, alpha: 1).setFill()
            for i in 0..<3 {
                rr(ix + cw * 0.07, tbY + tbH * (0.72 - CGFloat(i) * 0.22), (iw - cw * 0.14) * (i == 2 ? 0.55 : 1), tbH * 0.09, s * 0.003).fill()
            }
            let ptW = cw * 0.22, ptH = ch * 0.06
            let pt = rr(cw / 2 - b - ptW + cw * 0.01, -ch / 2 + b - ptH * 0.25, ptW, ptH, s * 0.01)
            parchment.setFill()
            pt.fill()
            NSColor(white: 0.07, alpha: 1).setStroke()
            pt.lineWidth = s * 0.004
            pt.stroke()
        } else {
            NSColor(white: 1, alpha: 0.25).setStroke()
            let inner = NSBezierPath(roundedRect: r.insetBy(dx: cw * 0.1, dy: cw * 0.1), xRadius: s * 0.02, yRadius: s * 0.02)
            inner.lineWidth = s * 0.008
            inner.stroke()
        }
        ctx.restoreGState()
    }
    card(angle: 0.20, dx: 0.07, face: false)
    card(angle: -0.14, dx: -0.02, face: true)

    // magnifier
    let c = CGPoint(x: s * 0.60, y: s * 0.38), rad = s * 0.15
    let gold = NSColor(red: 1.0, green: 0.80, blue: 0.35, alpha: 1)
    let handle = NSBezierPath()
    handle.move(to: CGPoint(x: c.x + rad * 0.72, y: c.y - rad * 0.72))
    handle.line(to: CGPoint(x: c.x + rad * 1.65, y: c.y - rad * 1.65))
    handle.lineWidth = s * 0.055
    handle.lineCapStyle = .round
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    gold.setStroke()
    handle.stroke()
    let ring = NSBezierPath(ovalIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
    NSColor(red: 0.25, green: 0.18, blue: 0.55, alpha: 0.55).setFill()
    ring.fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ring.lineWidth = s * 0.04
    gold.setStroke()
    ring.stroke()
    // glint
    let g = CGPoint(x: c.x - rad * 0.28, y: c.y + rad * 0.28), gl = rad * 0.36
    let star = NSBezierPath()
    star.move(to: CGPoint(x: g.x, y: g.y + gl))
    star.curve(to: CGPoint(x: g.x + gl, y: g.y), controlPoint1: CGPoint(x: g.x + gl * 0.1, y: g.y + gl * 0.1), controlPoint2: CGPoint(x: g.x + gl * 0.1, y: g.y + gl * 0.1))
    star.curve(to: CGPoint(x: g.x, y: g.y - gl), controlPoint1: CGPoint(x: g.x + gl * 0.1, y: g.y - gl * 0.1), controlPoint2: CGPoint(x: g.x + gl * 0.1, y: g.y - gl * 0.1))
    star.curve(to: CGPoint(x: g.x - gl, y: g.y), controlPoint1: CGPoint(x: g.x - gl * 0.1, y: g.y - gl * 0.1), controlPoint2: CGPoint(x: g.x - gl * 0.1, y: g.y - gl * 0.1))
    star.curve(to: CGPoint(x: g.x, y: g.y + gl), controlPoint1: CGPoint(x: g.x - gl * 0.1, y: g.y + gl * 0.1), controlPoint2: CGPoint(x: g.x - gl * 0.1, y: g.y + gl * 0.1))
    NSColor.white.setFill()
    star.fill()

    ctx.restoreGState()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
