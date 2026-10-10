// Рисует логотип, иконку приложения и баннер: swift art/art.swift
import AppKit

func eyePath(center c: CGPoint, width w: CGFloat) -> (NSBezierPath, CGFloat) {
    let h = w * 0.56
    let l = CGPoint(x: c.x - w / 2, y: c.y), r = CGPoint(x: c.x + w / 2, y: c.y)
    let p = NSBezierPath()
    p.move(to: l)
    p.curve(to: r, controlPoint1: CGPoint(x: c.x - w * 0.24, y: c.y + h * 0.78), controlPoint2: CGPoint(x: c.x + w * 0.24, y: c.y + h * 0.78))
    p.curve(to: l, controlPoint1: CGPoint(x: c.x + w * 0.24, y: c.y - h * 0.78), controlPoint2: CGPoint(x: c.x - w * 0.24, y: c.y - h * 0.78))
    p.close()
    return (p, h)
}

func drawEye(center c: CGPoint, width w: CGFloat, stroke: CGFloat, color: NSColor) {
    let (almond, h) = eyePath(center: c, width: w)
    color.set()
    almond.lineWidth = stroke; almond.lineJoinStyle = .round; almond.stroke()
    let ir = h * 0.36
    let iris = NSBezierPath(ovalIn: CGRect(x: c.x - ir, y: c.y - ir, width: ir * 2, height: ir * 2))
    iris.lineWidth = stroke; iris.stroke()
    let pr = ir * 0.42
    NSBezierPath(ovalIn: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)).fill()
}

func render(_ size: CGSize, _ out: String, _ draw: (CGRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let ink = NSColor.white

// Иконка приложения: чёрный скруглённый квадрат macOS, тонкий белый глаз.
func icon(_ s: CGFloat, _ out: String) {
    render(CGSize(width: s, height: s), out) { r in
        let inset = s * 0.1
        let tile = NSBezierPath(roundedRect: r.insetBy(dx: inset, dy: inset), xRadius: s * 0.18, yRadius: s * 0.18)
        NSGradient(starting: NSColor(white: 0.13, alpha: 1), ending: NSColor(white: 0.02, alpha: 1))!.draw(in: tile, angle: -90)
        NSColor(white: 1, alpha: 0.12).set(); tile.lineWidth = max(1, s * 0.004); tile.stroke()
        drawEye(center: CGPoint(x: r.midX, y: r.midY), width: s * 0.5, stroke: max(1, s * 0.022), color: ink)
    }
}
icon(1024, "\(dir)/logo.png")
let iconset = "\(dir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for b in [16, 32, 128, 256, 512] {
    icon(CGFloat(b), "\(iconset)/icon_\(b)x\(b).png")
    icon(CGFloat(b * 2), "\(iconset)/icon_\(b)x\(b)@2x.png")
}

// Баннер / social preview 1280×640: чёрный фон, глаз и имя очень тонким шрифтом.
render(CGSize(width: 2560, height: 1280), "\(dir)/banner.png") { r in
    NSColor.black.setFill(); r.fill()
    let glow = NSGradient(colors: [NSColor(white: 1, alpha: 0.07), NSColor(white: 1, alpha: 0)])!
    glow.draw(fromCenter: CGPoint(x: r.midX, y: r.midY + 120), radius: 0, toCenter: CGPoint(x: r.midX, y: r.midY + 120), radius: 900, options: [])
    drawEye(center: CGPoint(x: r.midX, y: r.midY + 250), width: 300, stroke: 7, color: ink)
    let title = NSAttributedString(string: "Yonder", attributes: [
        .font: NSFont.systemFont(ofSize: 300, weight: .ultraLight), .foregroundColor: ink, .kern: 18])
    let ts = title.size()
    title.draw(at: CGPoint(x: r.midX - ts.width / 2, y: r.midY - 300))
    let sub = NSAttributedString(string: "20 · 20 · 20   EYE BREAKS FOR MAC", attributes: [
        .font: NSFont.systemFont(ofSize: 46, weight: .light), .foregroundColor: NSColor(white: 1, alpha: 0.55), .kern: 12])
    let ss = sub.size()
    sub.draw(at: CGPoint(x: r.midX - ss.width / 2, y: r.midY - 420))
}
// Кнопка «Download for macOS» для README.
render(CGSize(width: 760, height: 168), "\(dir)/download.png") { r in
    let b = NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 2), xRadius: 30, yRadius: 30)
    NSColor.black.setFill(); b.fill()
    NSColor(white: 1, alpha: 0.35).set(); b.lineWidth = 3; b.stroke()
    let apple = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 64, weight: .regular))!
    let tinted = NSImage(size: apple.size, flipped: false) { rr in
        apple.draw(in: rr); NSColor.white.set(); rr.fill(using: .sourceAtop); return true }
    tinted.draw(in: CGRect(x: 70, y: (r.height - apple.size.height) / 2 + 4, width: apple.size.width, height: apple.size.height))
    let t = NSAttributedString(string: "Download for macOS", attributes: [
        .font: NSFont.systemFont(ofSize: 58, weight: .light), .foregroundColor: NSColor.white, .kern: 1])
    t.draw(at: CGPoint(x: 70 + apple.size.width + 34, y: (r.height - t.size().height) / 2))
}
print("ok")
