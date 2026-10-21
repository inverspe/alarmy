import CoreGraphics

/// Draws a seeded, room-like test picture: a gradient with 12 random shapes.
/// `brightness` dims the whole scene; `offset` shifts it (fraction of the size).
enum SceneRenderer {
    static func render(seed: UInt64, brightness: CGFloat = 1, offset: CGFloat = 0, size: Int = 512) -> CGImage {
        var rng = SeededGenerator(seed: seed)
        func unit() -> CGFloat { CGFloat(Double(rng.next() % 10_000) / 10_000) }
        func color() -> CGColor {
            CGColor(red: unit() * brightness, green: unit() * brightness, blue: unit() * brightness, alpha: 1)
        }

        let s = CGFloat(size)
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.05 * brightness, green: 0.05 * brightness, blue: 0.05 * brightness, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
        ctx.translateBy(x: offset * s, y: offset * s)

        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(), color()] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: s, y: s), options: [])

        for i in 0..<12 {
            ctx.setFillColor(color())
            let rect = CGRect(x: unit() * s * 0.8, y: unit() * s * 0.8, width: s * (0.08 + unit() * 0.25), height: s * (0.08 + unit() * 0.25))
            if i.isMultiple(of: 2) { ctx.fill(rect) } else { ctx.fillEllipse(in: rect) }
        }
        return ctx.makeImage()!
    }
}
