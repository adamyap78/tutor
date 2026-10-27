import AppKit

// Renders the app icon: a deep-indigo squircle with a tilted card and a spark.
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    ctx.saveGState()
    squircle.addClip()
    let grad = NSGradient(colors: [NSColor(red: 0.20, green: 0.16, blue: 0.42, alpha: 1), NSColor(red: 0.06, green: 0.05, blue: 0.16, alpha: 1)])!
    grad.draw(in: rect, angle: -60)
    // card
    ctx.translateBy(x: s * 0.5, y: s * 0.5)
    ctx.rotate(by: -0.18)
    let cw = s * 0.36, ch = s * 0.5
    let card = NSBezierPath(roundedRect: CGRect(x: -cw / 2, y: -ch / 2, width: cw, height: ch), xRadius: s * 0.03, yRadius: s * 0.03)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    NSColor(white: 0.97, alpha: 1).setFill()
    card.fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let art = NSBezierPath(roundedRect: CGRect(x: -cw * 0.42, y: ch * 0.02, width: cw * 0.84, height: ch * 0.38), xRadius: s * 0.015, yRadius: s * 0.015)
    NSGradient(colors: [NSColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1), NSColor(red: 0.85, green: 0.25, blue: 0.40, alpha: 1)])!.draw(in: art, angle: 70)
    NSColor(white: 0.82, alpha: 1).setFill()
    for i in 0..<3 {
        let l = NSBezierPath(roundedRect: CGRect(x: -cw * 0.42, y: -ch * 0.10 - CGFloat(i) * ch * 0.1, width: cw * (i == 2 ? 0.5 : 0.84), height: ch * 0.04), xRadius: s * 0.008, yRadius: s * 0.008)
        l.fill()
    }
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
