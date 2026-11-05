import SpriteKit
import UIKit

/// A texture plus the size (in art units) it should be drawn at.
struct Art {
    let texture: SKTexture
    let size: CGSize
}

/// Draws every piece of Storm Stitch art in code, in the cut-paper style from the
/// art direction board: a white cut edge, a hard drop shadow and a little paper grain.
/// Stand-ins until an illustrator delivers final assets; swap a texture by key later.
final class PaperArt {
    static let shared = PaperArt()

    private var cache: [String: Art] = [:]
    private let renderScale: CGFloat = 3

    // MARK: Core

    func art(_ key: String, size: CGSize, draw: (CGContext) -> Void) -> Art {
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = renderScale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(context.cgContext)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let result = Art(texture: texture, size: size)
        if cache.count > 600 { cache.removeAll(keepingCapacity: true) }
        cache[key] = result
        return result
    }

    /// Draws one piece of cut paper: shadow, white edge, fill, grain.
    static func cut(_ ctx: CGContext, _ path: CGPath, fill: UIColor,
                    edge: CGFloat = 5, shadow: CGFloat = 6, grain: Bool = true) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: shadow)
        ctx.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
        ctx.setStrokeColor(UIColor(white: 0, alpha: 0.22).cgColor)
        ctx.setLineWidth(edge * 2)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(edge * 2)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()

        ctx.setFillColor(fill.cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        if grain {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let box = path.boundingBox
            var rng = SeededRandom(seed: UInt64(abs(Int(box.width * 31 + box.height * 17))) + 7)
            let count = Int(box.width * box.height / 45)
            for i in 0..<count {
                let x = box.minX + rng.next() * box.width
                let y = box.minY + rng.next() * box.height
                let light = i % 2 == 0
                ctx.setFillColor(light ? UIColor(white: 1, alpha: 0.10).cgColor : UIColor(white: 0, alpha: 0.05).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 1.6, height: 1.6))
            }
            ctx.restoreGState()
        }
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
    }

    static func roundRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        UIBezierPath(roundedRect: rect, cornerRadius: min(radius, rect.width / 2, rect.height / 2)).cgPath
    }

    static func poly(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    // MARK: Bramble

    /// Body art, 200 x 180. The body's bottom sits at y = 170.
    var brambleBody: Art {
        art("bramble.body", size: CGSize(width: 200, height: 180)) { ctx in
            let tufts = PaperArt.poly([
                CGPoint(x: 58, y: 88), CGPoint(x: 66, y: 56), CGPoint(x: 80, y: 76),
                CGPoint(x: 92, y: 44), CGPoint(x: 104, y: 72), CGPoint(x: 116, y: 46),
                CGPoint(x: 126, y: 74), CGPoint(x: 140, y: 56), CGPoint(x: 144, y: 90)
            ])
            PaperArt.cut(ctx, tufts, fill: UIColor(hex: 0x3E8A44))

            let body = CGMutablePath()
            body.move(to: CGPoint(x: 42, y: 170))
            body.addQuadCurve(to: CGPoint(x: 60, y: 86), control: CGPoint(x: 30, y: 112))
            body.addQuadCurve(to: CGPoint(x: 140, y: 86), control: CGPoint(x: 100, y: 62))
            body.addQuadCurve(to: CGPoint(x: 160, y: 170), control: CGPoint(x: 172, y: 112))
            body.closeSubpath()
            PaperArt.cut(ctx, body, fill: Palette.bramble)

            ctx.setFillColor(UIColor(hex: 0x8ED68F).cgColor)
            ctx.addPath(PaperArt.ellipse(101, 150, 32, 17))
            ctx.fillPath()

            ctx.setFillColor(UIColor(hex: 0xFF8FA3, alpha: 0.6).cgColor)
            ctx.addPath(PaperArt.ellipse(66, 134, 8, 4.5))
            ctx.addPath(PaperArt.ellipse(136, 134, 8, 4.5))
            ctx.fillPath()

            let mouth = CGMutablePath()
            mouth.move(to: CGPoint(x: 86, y: 136))
            mouth.addQuadCurve(to: CGPoint(x: 118, y: 136), control: CGPoint(x: 102, y: 156))
            mouth.closeSubpath()
            ctx.setFillColor(Palette.ink.cgColor)
            ctx.addPath(mouth)
            ctx.fillPath()

            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(PaperArt.poly([CGPoint(x: 90, y: 137), CGPoint(x: 93, y: 128), CGPoint(x: 98, y: 139)]))
            ctx.addPath(PaperArt.poly([CGPoint(x: 114, y: 137), CGPoint(x: 111, y: 128), CGPoint(x: 106, y: 139)]))
            ctx.fillPath()
        }
    }

    /// Eyes, 80 x 44, eye centers 36 apart.
    func brambleEyes(closed: Bool) -> Art {
        art(closed ? "bramble.eyes.closed" : "bramble.eyes", size: CGSize(width: 80, height: 44)) { ctx in
            for cx in [CGFloat(22), CGFloat(58)] {
                if closed {
                    ctx.setStrokeColor(Palette.ink.cgColor)
                    ctx.setLineWidth(4)
                    ctx.setLineCap(.round)
                    ctx.move(to: CGPoint(x: cx - 11, y: 22))
                    ctx.addQuadLine(to: CGPoint(x: cx + 11, y: 22), control: CGPoint(x: cx, y: 30))
                    ctx.strokePath()
                } else {
                    ctx.setFillColor(UIColor.white.cgColor)
                    ctx.setStrokeColor(Palette.ink.cgColor)
                    ctx.setLineWidth(3)
                    ctx.addPath(PaperArt.ellipse(cx, 22, 15, 15))
                    ctx.drawPath(using: .fillStroke)
                    ctx.setFillColor(Palette.ink.cgColor)
                    ctx.addPath(PaperArt.ellipse(cx + 3, 24, 7.5, 7.5))
                    ctx.fillPath()
                    ctx.setFillColor(UIColor.white.cgColor)
                    ctx.addPath(PaperArt.ellipse(cx + 6, 20, 2.8, 2.8))
                    ctx.fillPath()
                }
            }
        }
    }

    var brambleArm: Art {
        art("bramble.arm", size: CGSize(width: 32, height: 42)) { ctx in
            PaperArt.cut(ctx, PaperArt.ellipse(16, 19, 11, 15), fill: Palette.bramble, edge: 4, shadow: 3, grain: false)
        }
    }

    var brambleFoot: Art {
        art("bramble.foot", size: CGSize(width: 48, height: 28)) { ctx in
            PaperArt.cut(ctx, PaperArt.ellipse(24, 12, 18, 9), fill: UIColor(hex: 0x3E8A44), edge: 4, shadow: 3, grain: false)
        }
    }

    // MARK: Hazards (Notebook Meadow: school supplies blown loose by the storm)

    /// Eraser block, 112 x 70. Ground at y = 58.
    var eraser: Art {
        art("hazard.eraser", size: CGSize(width: 112, height: 70)) { ctx in
            let body = PaperArt.roundRect(CGRect(x: 6, y: 12, width: 100, height: 46), 10)
            PaperArt.cut(ctx, body, fill: UIColor(hex: 0xFF8FA3))
            ctx.saveGState()
            ctx.addPath(body)
            ctx.clip()
            ctx.setFillColor(UIColor(hex: 0x4F7FE6).cgColor)
            ctx.fill(CGRect(x: 6, y: 12, width: 38, height: 46))
            ctx.setFillColor(UIColor(white: 1, alpha: 0.3).cgColor)
            ctx.fill(CGRect(x: 6, y: 14, width: 100, height: 8))
            ctx.restoreGState()
        }
    }

    /// Ruler held up by two pencils, 124 x 190. Ground at y = 180.
    var ruler: Art {
        art("hazard.ruler", size: CGSize(width: 124, height: 190)) { ctx in
            for px in [CGFloat(8), CGFloat(104)] {
                let pencil = CGMutablePath()
                pencil.addRect(CGRect(x: px, y: 92, width: 12, height: 72))
                PaperArt.cut(ctx, pencil, fill: Palette.stitchGold, edge: 3, shadow: 3, grain: false)
                let tip = PaperArt.poly([CGPoint(x: px, y: 164), CGPoint(x: px + 12, y: 164), CGPoint(x: px + 6, y: 180)])
                PaperArt.cut(ctx, tip, fill: UIColor(hex: 0xF2D2A9), edge: 3, shadow: 2, grain: false)
                ctx.setFillColor(Palette.ink.cgColor)
                ctx.addPath(PaperArt.poly([CGPoint(x: px + 3, y: 174), CGPoint(x: px + 9, y: 174), CGPoint(x: px + 6, y: 180)]))
                ctx.fillPath()
            }
            let bar = PaperArt.roundRect(CGRect(x: 4, y: 70, width: 116, height: 46), 6)
            PaperArt.cut(ctx, bar, fill: UIColor(hex: 0xF4C26B))
            ctx.setStrokeColor(UIColor(hex: 0x8A5A2B).cgColor)
            ctx.setLineWidth(2.5)
            var x: CGFloat = 12
            var i = 0
            while x < 116 {
                let long = i % 4 == 0
                ctx.move(to: CGPoint(x: x, y: 72))
                ctx.addLine(to: CGPoint(x: x, y: long ? 90 : 82))
                x += 8
                i += 1
            }
            ctx.strokePath()
        }
    }

    /// Cardboard box, 112 x 160. Ground at y = 150.
    var box: Art {
        art("hazard.box", size: CGSize(width: 112, height: 160)) { ctx in
            let body = PaperArt.roundRect(CGRect(x: 6, y: 12, width: 100, height: 138), 6)
            PaperArt.cut(ctx, body, fill: UIColor(hex: 0xC98A4B))
            ctx.setFillColor(UIColor(hex: 0xE3B37C).cgColor)
            ctx.fill(CGRect(x: 44, y: 12, width: 24, height: 56))
            ctx.setStrokeColor(UIColor(hex: 0x8A5A2B).cgColor)
            ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: 6, y: 50))
            ctx.addLine(to: CGPoint(x: 106, y: 50))
            ctx.strokePath()
            ctx.setStrokeColor(UIColor(hex: 0x8A5A2B, alpha: 0.6).cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: 20, y: 100))
            ctx.addLine(to: CGPoint(x: 34, y: 112))
            ctx.move(to: CGPoint(x: 34, y: 100))
            ctx.addLine(to: CGPoint(x: 20, y: 112))
            ctx.strokePath()
        }
    }

    // MARK: Pickups

    /// Thread spool, 56 x 56.
    var spool: Art {
        art("spool", size: CGSize(width: 56, height: 60)) { ctx in
            let thread = PaperArt.roundRect(CGRect(x: 12, y: 15, width: 32, height: 26), 4)
            PaperArt.cut(ctx, thread, fill: Palette.stitchGold, edge: 4, shadow: 3, grain: false)
            ctx.setStrokeColor(UIColor(hex: 0xE0A800).cgColor)
            ctx.setLineWidth(2)
            for y in stride(from: CGFloat(20), through: 36, by: 5) {
                ctx.move(to: CGPoint(x: 13, y: y))
                ctx.addLine(to: CGPoint(x: 43, y: y + 2))
            }
            ctx.strokePath()
            for y in [CGFloat(6), CGFloat(40)] {
                PaperArt.cut(ctx, PaperArt.roundRect(CGRect(x: 6, y: y, width: 44, height: 10), 5),
                             fill: UIColor(hex: 0xE7B97A), edge: 4, shadow: 3, grain: false)
            }
        }
    }

    // MARK: Scenery (gray when torn, color when stitched)

    /// Tree, 120 x 180. Ground at y = 172.
    func tree(colored: Bool) -> Art {
        art(colored ? "tree.c" : "tree.g", size: CGSize(width: 120, height: 180)) { ctx in
            PaperArt.cut(ctx, PaperArt.roundRect(CGRect(x: 52, y: 100, width: 16, height: 72), 4),
                         fill: colored ? UIColor(hex: 0x8A5A2B) : UIColor(hex: 0x6B6E7D), edge: 4, shadow: 4)
            PaperArt.cut(ctx, PaperArt.ellipse(60, 62, 46, 46),
                         fill: colored ? UIColor(hex: 0x3FA34D) : UIColor(hex: 0x8A8C99))
            PaperArt.cut(ctx, PaperArt.ellipse(36, 86, 24, 22),
                         fill: colored ? Palette.bramble : UIColor(hex: 0x9EA0AC), edge: 4, shadow: 4)
            PaperArt.cut(ctx, PaperArt.ellipse(86, 82, 24, 22),
                         fill: colored ? Palette.bramble : UIColor(hex: 0x9EA0AC), edge: 4, shadow: 4)
            if colored {
                ctx.setFillColor(UIColor(hex: 0xFF5C7A).cgColor)
                for (x, y) in [(CGFloat(48), CGFloat(44)), (76, 58), (56, 78), (88, 38)] {
                    ctx.addPath(PaperArt.ellipse(x, y, 5, 5))
                }
                ctx.fillPath()
            }
        }
    }

    /// Bush, 120 x 80. Ground at y = 72.
    func bush(colored: Bool) -> Art {
        art(colored ? "bush.c" : "bush.g", size: CGSize(width: 120, height: 80)) { ctx in
            let dark = colored ? UIColor(hex: 0x3FA34D) : UIColor(hex: 0x8A8C99)
            let light = colored ? Palette.bramble : UIColor(hex: 0x9EA0AC)
            PaperArt.cut(ctx, PaperArt.ellipse(38, 50, 30, 24), fill: dark, edge: 4, shadow: 4)
            PaperArt.cut(ctx, PaperArt.ellipse(84, 50, 30, 24), fill: dark, edge: 4, shadow: 4)
            PaperArt.cut(ctx, PaperArt.ellipse(60, 38, 32, 28), fill: light, edge: 4, shadow: 4)
        }
    }

    /// Flower, 44 x 72. Ground at y = 68. Variant picks the petal color.
    func flower(colored: Bool, variant: Int) -> Art {
        let petals = [UIColor(hex: 0xFF5C7A), Palette.stitchGold, UIColor(hex: 0x7B5CFF)]
        let key = colored ? "flower.c\(variant % 3)" : "flower.g"
        return art(key, size: CGSize(width: 44, height: 72)) { ctx in
            ctx.setStrokeColor(colored ? UIColor(hex: 0x3FA34D).cgColor : UIColor(hex: 0x6B6E7D).cgColor)
            ctx.setLineWidth(4)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 22, y: 68))
            ctx.addLine(to: CGPoint(x: 22, y: 30))
            ctx.strokePath()
            let petal = colored ? petals[variant % 3] : UIColor(hex: 0x9EA0AC)
            for (dx, dy) in [(CGFloat(0), CGFloat(-10)), (10, 0), (0, 10), (-10, 0)] {
                PaperArt.cut(ctx, PaperArt.ellipse(22 + dx, 22 + dy, 8, 8), fill: petal, edge: 2.5, shadow: 2, grain: false)
            }
            PaperArt.cut(ctx, PaperArt.ellipse(22, 22, 6, 6),
                         fill: colored ? Palette.stitchGold : UIColor(hex: 0xC3C5CE), edge: 2, shadow: 1, grain: false)
        }
    }

    // MARK: Stitched patches

    private func blobPoints(variant: Int, center: CGFloat, radius: CGFloat) -> [CGPoint] {
        var rng = SeededRandom(seed: UInt64(variant * 977 + 13))
        var points: [CGPoint] = []
        let count = 22
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2
            let r = radius * (0.82 + rng.next() * 0.18)
            points.append(CGPoint(x: center + cos(angle) * r, y: center + sin(angle) * r))
        }
        return points
    }

    /// White torn-edge blob for the color-flood mask, 128 x 128.
    func patchMask(variant: Int) -> Art {
        art("patch.mask\(variant)", size: CGSize(width: 128, height: 128)) { ctx in
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(PaperArt.poly(blobPoints(variant: variant, center: 64, radius: 60)))
            ctx.fillPath()
        }
    }

    /// Gold running stitch around the same blob, 128 x 128.
    func patchStitch(variant: Int) -> Art {
        art("patch.stitch\(variant)", size: CGSize(width: 128, height: 128)) { ctx in
            let path = PaperArt.poly(blobPoints(variant: variant, center: 64, radius: 56))
            ctx.setStrokeColor(UIColor(hex: 0xFFC93C, alpha: 0.35).cgColor)
            ctx.setLineWidth(9)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.setStrokeColor(Palette.stitchGold.cgColor)
            ctx.setLineWidth(4)
            ctx.setLineCap(.round)
            ctx.setLineDash(phase: 0, lengths: [9, 7])
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    // MARK: Sky and storm

    /// Horizon hills, 1024 x 170.
    func hills(colored: Bool) -> Art {
        art(colored ? "hills.c" : "hills.g", size: CGSize(width: 1024, height: 170)) { ctx in
            let far = CGMutablePath()
            far.move(to: CGPoint(x: 0, y: 170))
            far.addLine(to: CGPoint(x: 0, y: 92))
            far.addQuadCurve(to: CGPoint(x: 340, y: 70), control: CGPoint(x: 160, y: 30))
            far.addQuadCurve(to: CGPoint(x: 700, y: 64), control: CGPoint(x: 520, y: 110))
            far.addQuadCurve(to: CGPoint(x: 1024, y: 80), control: CGPoint(x: 880, y: 20))
            far.addLine(to: CGPoint(x: 1024, y: 170))
            far.closeSubpath()
            PaperArt.cut(ctx, far, fill: colored ? UIColor(hex: 0x7FCF84) : UIColor(hex: 0x9A9CA8), edge: 5, shadow: 6)

            let near = CGMutablePath()
            near.move(to: CGPoint(x: 0, y: 170))
            near.addLine(to: CGPoint(x: 0, y: 130))
            near.addQuadCurve(to: CGPoint(x: 520, y: 118), control: CGPoint(x: 260, y: 84))
            near.addQuadCurve(to: CGPoint(x: 1024, y: 124), control: CGPoint(x: 780, y: 150))
            near.addLine(to: CGPoint(x: 1024, y: 170))
            near.closeSubpath()
            PaperArt.cut(ctx, near, fill: colored ? Palette.bramble : UIColor(hex: 0x8A8C99), edge: 5, shadow: 6)
        }
    }

    var sun: Art {
        art("sun", size: CGSize(width: 140, height: 140)) { ctx in
            PaperArt.cut(ctx, PaperArt.ellipse(70, 66, 52, 52), fill: Palette.stitchGold, edge: 7, shadow: 5)
        }
    }

    var cloud: Art {
        art("cloud", size: CGSize(width: 180, height: 80)) { ctx in
            let path = CGMutablePath()
            path.addPath(PaperArt.ellipse(60, 46, 40, 24))
            path.addPath(PaperArt.ellipse(104, 36, 46, 30))
            path.addPath(PaperArt.ellipse(140, 50, 30, 20))
            PaperArt.cut(ctx, path, fill: .white, edge: 0.01, shadow: 4, grain: false)
        }
    }

    /// The storm wall, 512 x 300: churning dark scallops over a solid base.
    var stormWall: Art {
        art("storm.wall", size: CGSize(width: 512, height: 300)) { ctx in
            var rng = SeededRandom(seed: 99)
            ctx.setFillColor(UIColor(hex: 0x4A4D5C).cgColor)
            var x: CGFloat = -20
            while x < 540 {
                let r = 42 + rng.next() * 26
                ctx.addPath(PaperArt.ellipse(x, 70 + rng.next() * 20, r, r))
                x += 52
            }
            ctx.fillPath()
            ctx.setFillColor(UIColor(hex: 0x33353F).cgColor)
            x = 6
            while x < 540 {
                let r = 40 + rng.next() * 22
                ctx.addPath(PaperArt.ellipse(x, 100 + rng.next() * 16, r, r))
                x += 48
            }
            ctx.addRect(CGRect(x: 0, y: 110, width: 512, height: 190))
            ctx.fillPath()
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.18).cgColor)
            ctx.setLineWidth(4)
            ctx.setLineCap(.round)
            for _ in 0..<14 {
                let sx = rng.next() * 512
                let sy = 120 + rng.next() * 160
                ctx.move(to: CGPoint(x: sx, y: sy))
                ctx.addLine(to: CGPoint(x: sx + 18 + rng.next() * 20, y: sy - 6 + rng.next() * 12))
            }
            ctx.strokePath()
        }
    }

    /// One glowing storm eye, 72 x 44.
    var stormEye: Art {
        art("storm.eye", size: CGSize(width: 72, height: 44)) { ctx in
            ctx.setFillColor(UIColor(hex: 0xFFE36B, alpha: 0.25).cgColor)
            ctx.addPath(PaperArt.ellipse(36, 22, 34, 20))
            ctx.fillPath()
            ctx.setFillColor(UIColor(hex: 0xFFE36B).cgColor)
            ctx.addPath(PaperArt.poly([
                CGPoint(x: 10, y: 18), CGPoint(x: 62, y: 12), CGPoint(x: 56, y: 30), CGPoint(x: 18, y: 32)
            ]))
            ctx.fillPath()
            ctx.setFillColor(Palette.ink.cgColor)
            ctx.addPath(PaperArt.ellipse(38, 23, 6, 7))
            ctx.fillPath()
        }
    }

    // MARK: Particles and UI

    var scrap: Art {
        art("fx.scrap", size: CGSize(width: 16, height: 12)) { ctx in
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(PaperArt.poly([CGPoint(x: 1, y: 2), CGPoint(x: 15, y: 0), CGPoint(x: 13, y: 11), CGPoint(x: 2, y: 9)]))
            ctx.fillPath()
        }
    }

    var spark: Art {
        art("fx.spark", size: CGSize(width: 28, height: 28)) { ctx in
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.addPath(PaperArt.poly([
                CGPoint(x: 14, y: 0), CGPoint(x: 17, y: 11), CGPoint(x: 28, y: 14), CGPoint(x: 17, y: 17),
                CGPoint(x: 14, y: 28), CGPoint(x: 11, y: 17), CGPoint(x: 0, y: 14), CGPoint(x: 11, y: 11)
            ]))
            ctx.fillPath()
        }
    }

    var puff: Art {
        art("fx.puff", size: CGSize(width: 32, height: 32)) { ctx in
            let colors = [UIColor.white.cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                       endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
            }
        }
    }

    var shadow: Art {
        // A soft, slightly lumpy pool: a body blob plus two foot blobs, all feathered to nothing at the edge.
        art("fx.shadow.soft", size: CGSize(width: 100, height: 32)) { ctx in
            let colors = [UIColor(hex: 0x1E1830, alpha: 0.34).cgColor, UIColor(hex: 0x1E1830, alpha: 0.18).cgColor,
                          UIColor(hex: 0x1E1830, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                            locations: [0, 0.5, 1]) else { return }
            ctx.scaleBy(x: 1, y: 0.34)
            for (x, y, r) in [(50.0, 47.0, 46.0), (33.0, 50.0, 22.0), (67.0, 44.0, 22.0)] {
                let center = CGPoint(x: x, y: y)
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: CGFloat(r), options: [])
            }
        }
    }

    func heart(full: Bool) -> Art {
        art(full ? "ui.heart" : "ui.heart.empty", size: CGSize(width: 64, height: 62)) { ctx in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 32, y: 54))
            p.addCurve(to: CGPoint(x: 6, y: 22), control1: CGPoint(x: 16, y: 44), control2: CGPoint(x: 6, y: 34))
            p.addCurve(to: CGPoint(x: 32, y: 16), control1: CGPoint(x: 6, y: 6), control2: CGPoint(x: 26, y: 4))
            p.addCurve(to: CGPoint(x: 58, y: 22), control1: CGPoint(x: 38, y: 4), control2: CGPoint(x: 58, y: 6))
            p.addCurve(to: CGPoint(x: 32, y: 54), control1: CGPoint(x: 58, y: 34), control2: CGPoint(x: 48, y: 44))
            p.closeSubpath()
            PaperArt.cut(ctx, p, fill: full ? Palette.heart : UIColor(hex: 0x6B6E7D, alpha: 0.6), edge: 4, shadow: 4, grain: false)
        }
    }

    func star(filled: Bool) -> Art {
        art(filled ? "ui.star" : "ui.star.empty", size: CGSize(width: 72, height: 72)) { ctx in
            var points: [CGPoint] = []
            for i in 0..<10 {
                let angle = CGFloat(i) / 10 * .pi * 2 - .pi / 2
                let r: CGFloat = i % 2 == 0 ? 30 : 13
                points.append(CGPoint(x: 36 + cos(angle) * r, y: 36 + sin(angle) * r))
            }
            PaperArt.cut(ctx, PaperArt.poly(points), fill: filled ? Palette.stitchGold : UIColor(hex: 0xD2D4DB),
                         edge: 4, shadow: 4, grain: false)
        }
    }

    /// Game fonts: Fredoka for titles, headings and buttons; Nunito Sans for longer text.
    enum TextStyle {
        case heading
        case body
    }

    /// Chunky text with an ink outline and a hard shadow.
    func text(_ string: String, size: CGFloat, fill: UIColor = .white, outline: UIColor = Palette.ink,
              style: TextStyle = .heading) -> Art {
        let fontName = style == .heading ? "Fredoka-Bold" : "NunitoSans-ExtraBold"
        var font = UIFont(name: fontName, size: size) ?? UIFont.systemFont(ofSize: size, weight: .black)
        if UIFont(name: fontName, size: size) == nil,
           let rounded = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: rounded, size: size)
        }
        let key = "text|\(fontName)|\(string)|\(size)|\(fill.description)|\(outline.description)"
        let measured = (string as NSString).size(withAttributes: [.font: font])
        let pad = ceil(size * 0.25)
        let canvas = CGSize(width: ceil(measured.width) + pad * 2, height: ceil(measured.height) + pad * 2)
        return art(key, size: canvas) { _ in
            let shadowAttrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: UIColor(white: 0, alpha: 0.3),
                .strokeColor: UIColor(white: 0, alpha: 0.3), .strokeWidth: -24
            ]
            let outlineAttrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: outline, .strokeColor: outline, .strokeWidth: -24
            ]
            let fillAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fill]
            // Dark text sits on paper: draw it clean, without the outline and shadow.
            var white: CGFloat = 1
            var alpha: CGFloat = 1
            if !fill.getWhite(&white, alpha: &alpha) { white = 1 }
            if white > 0.45 {
                (string as NSString).draw(at: CGPoint(x: pad, y: pad + size * 0.08), withAttributes: shadowAttrs)
                (string as NSString).draw(at: CGPoint(x: pad, y: pad), withAttributes: outlineAttrs)
            }
            (string as NSString).draw(at: CGPoint(x: pad, y: pad), withAttributes: fillAttrs)
        }
    }

    /// Splits text into lines that fit a width in the game's fonts.
    static func wrap(_ string: String, fontSize: CGFloat, maxWidth: CGFloat, style: TextStyle) -> [String] {
        let fontName = style == .heading ? "Fredoka-Bold" : "NunitoSans-ExtraBold"
        let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        // Leave room for the outline the text is drawn with.
        let limit = maxWidth - fontSize * 0.5
        var lines: [String] = []
        var line = ""
        for word in string.split(separator: " ") {
            let candidate = line.isEmpty ? String(word) : line + " " + word
            if (candidate as NSString).size(withAttributes: [.font: font]).width > limit && !line.isEmpty {
                lines.append(line)
                line = String(word)
            } else {
                line = candidate
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    // MARK: Stand-ins for round 3 art

    /// The torn seam across the road at the end of a stage, 360 x 300. Ground at the bottom.
    var seamGate: Art {
        art("seam.gate", size: CGSize(width: 360, height: 300)) { ctx in
            for px in [CGFloat(14), CGFloat(326)] {
                PaperArt.cut(ctx, PaperArt.roundRect(CGRect(x: px, y: 20, width: 20, height: 276), 6),
                             fill: Palette.stitchGold, edge: 4, shadow: 4)
            }
            let banner = PaperArt.roundRect(CGRect(x: 26, y: 34, width: 308, height: 190), 10)
            PaperArt.cut(ctx, banner, fill: Palette.paper)
            // The jagged tear down the middle.
            var points: [CGPoint] = []
            var y: CGFloat = 34
            var left = true
            while y < 224 {
                points.append(CGPoint(x: left ? 168 : 192, y: y))
                y += 16
                left.toggle()
            }
            points.append(CGPoint(x: 180, y: 224))
            let tear = CGMutablePath()
            tear.addLines(between: points)
            ctx.setStrokeColor(Palette.ink.cgColor)
            ctx.setLineWidth(9)
            ctx.setLineJoin(.round)
            ctx.addPath(tear)
            ctx.strokePath()
            ctx.setStrokeColor(UIColor(hex: 0xFFE36B).cgColor)
            ctx.setLineWidth(3)
            ctx.addPath(tear)
            ctx.strokePath()
        }
    }

    /// A golden needle trailing thread, 150 x 60.
    var needle: Art {
        art("needle", size: CGSize(width: 150, height: 60)) { ctx in
            let body = CGMutablePath()
            body.move(to: CGPoint(x: 8, y: 30))
            body.addLine(to: CGPoint(x: 120, y: 22))
            body.addQuadCurve(to: CGPoint(x: 120, y: 38), control: CGPoint(x: 146, y: 30))
            body.closeSubpath()
            PaperArt.cut(ctx, body, fill: Palette.stitchGold, edge: 3, shadow: 3, grain: false)
            ctx.setFillColor(Palette.ink.cgColor)
            ctx.addPath(PaperArt.ellipse(124, 30, 8, 4))
            ctx.fillPath()
        }
    }

    /// An autumn leaf for the Harvest Gale, 40 x 40, in three colors.
    func leaf(variant: Int) -> Art {
        let colors = [UIColor(hex: 0xFF7A2F), UIColor(hex: 0xD93D3D), Palette.stitchGold]
        return art("leaf.\(variant % 3)", size: CGSize(width: 40, height: 40)) { ctx in
            let leaf = CGMutablePath()
            leaf.move(to: CGPoint(x: 20, y: 3))
            leaf.addQuadCurve(to: CGPoint(x: 20, y: 37), control: CGPoint(x: 42, y: 18))
            leaf.addQuadCurve(to: CGPoint(x: 20, y: 3), control: CGPoint(x: -2, y: 18))
            PaperArt.cut(ctx, leaf, fill: colors[variant % 3], edge: 2, shadow: 2, grain: false)
        }
    }
}

/// Small deterministic random generator so procedural art looks the same every launch.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> CGFloat {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return CGFloat(state % 10_000) / 10_000
    }
}

private extension CGContext {
    func addQuadLine(to point: CGPoint, control: CGPoint) {
        addQuadCurve(to: point, control: control)
    }
}
