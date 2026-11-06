import SpriteKit
import UIKit

/// The opening story: six illustrated panels that slowly pan and zoom, each with a caption.
/// Plays on first launch and from the title screen. Tap to move on; Skip ends it.
final class StoryPlayer: SKNode {

    enum Effect { case confetti, scraps, sparkle, storm, none }

    struct Panel {
        let image: String
        /// Shown until the story art arrives. Character art sits centered; scenes fill the screen.
        let fallback: String
        let fallbackIsScene: Bool
        let caption: String
        let effect: Effect
    }

    static let panels: [Panel] = [
        Panel(image: "story-1", fallback: "backdrop-color", fallbackIsScene: true,
              caption: "Once upon a page, the Paper World was bright, folded and full of friends.", effect: .confetti),
        Panel(image: "story-2", fallback: "storm-wall", fallbackIsScene: false,
              caption: "Then the Shredder rolled in: a storm that tears paper into confetti and drains every color.", effect: .storm),
        Panel(image: "story-3", fallback: "backdrop-gray", fallbackIsScene: true,
              caption: "Meadows ripped. Rivers frayed. One by one, the pages went gray.", effect: .scraps),
        Panel(image: "story-4", fallback: "bramble-front", fallbackIsScene: false,
              caption: "But in the margins, a small leafy monster named Bramble found something golden.", effect: .sparkle),
        Panel(image: "story-5", fallback: "bramble-win", fallbackIsScene: false,
              caption: "A needle and a spool of storm-proof thread. Every stitch brings the color back.", effect: .sparkle),
        Panel(image: "story-6", fallback: "title-card", fallbackIsScene: true,
              caption: "So Bramble ran, the storm gave chase, and friends from every page joined in.", effect: .confetti)
    ]

    private let screen: CGSize
    private let safeTop: CGFloat
    private let safeBottom: CGFloat
    private let onFinish: () -> Void
    private let art = PaperArt.shared
    private var index = -1
    private var current: SKNode?
    private var dots: [SKShapeNode] = []
    private let skipButton = SKNode()
    private var finished = false
    /// Pages still turning or tearing away, cleared if the player taps ahead.
    private var leaving: [SKNode] = []
    private let panelTime: TimeInterval = GameAudio.storyPanelSeconds

    init(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, onFinish: @escaping () -> Void) {
        screen = size
        self.safeTop = safeTop
        self.safeBottom = safeBottom
        self.onFinish = onFinish
        super.init()

        let paper = SKSpriteNode(color: Palette.ink, size: size)
        paper.anchorPoint = .zero
        addChild(paper)

        // Skip, top right.
        let pill = SKShapeNode(rect: CGRect(x: -40, y: -18, width: 80, height: 36), cornerRadius: 18)
        pill.fillColor = UIColor(white: 0, alpha: 0.35)
        pill.strokeColor = UIColor(white: 1, alpha: 0.6)
        pill.lineWidth = 2
        skipButton.addChild(pill)
        let skipArt = art.text("Skip", size: 16, fill: .white, style: .body)
        skipButton.addChild(SKSpriteNode(texture: skipArt.texture, size: skipArt.size))
        skipButton.position = CGPoint(x: size.width - 56, y: size.height - safeTop - 26)
        skipButton.zPosition = 50
        addChild(skipButton)

        // Page dots.
        let count = StoryPlayer.panels.count
        for i in 0..<count {
            let dot = SKShapeNode(circleOfRadius: 4)
            dot.fillColor = UIColor(white: 1, alpha: 0.4)
            dot.strokeColor = .clear
            dot.position = CGPoint(x: size.width / 2 + (CGFloat(i) - CGFloat(count - 1) / 2) * 16, y: safeBottom + 14)
            dot.zPosition = 50
            addChild(dot)
            dots.append(dot)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func start() {
        advance()
    }

    /// A tap anywhere moves on; a tap on Skip ends the story.
    func tap(at point: CGPoint) {
        guard !finished else { return }
        let local = convert(point, from: scene ?? self)
        if skipButton.calculateAccumulatedFrame().insetBy(dx: -10, dy: -10).contains(local) {
            finish(skipped: true)
        } else {
            advance()
        }
    }

    private func advance() {
        guard !finished else { return }
        removeAction(forKey: "auto")
        index += 1
        guard index < StoryPlayer.panels.count else {
            finish(skipped: false)
            return
        }
        GameAudio.shared.cueStoryScore(panel: index)
        for (i, dot) in dots.enumerated() {
            dot.fillColor = i == index ? Palette.stitchGold : UIColor(white: 1, alpha: 0.4)
        }
        let panel = makePanel(StoryPlayer.panels[index])
        panel.zPosition = CGFloat(index + 1)
        addChild(panel)
        if let old = current {
            // The Shredder's panel rips the page in two; every other panel turns like a book page.
            transition(from: old, to: panel, tear: StoryPlayer.panels[index].effect == .storm)
        } else {
            panel.alpha = 0
            panel.run(.fadeIn(withDuration: 0.45))
        }
        current = panel
        run(.sequence([.wait(forDuration: panelTime), .run { [weak self] in self?.advance() }]), withKey: "auto")
    }

    private func finish(skipped: Bool) {
        guard !finished else { return }
        finished = true
        removeAllActions()
        // Skip cuts the score quickly; reaching the end lets its last chord ring out.
        GameAudio.shared.stopStoryScore(fade: skipped ? 0.4 : 3)
        // Build what comes next underneath first, then fade the book away over it,
        // so the running scene behind the story never shows through.
        onFinish()
        run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))
    }

    private func makePanel(_ panel: Panel) -> SKNode {
        let node = SKNode()
        let w = screen.width
        let h = screen.height

        let background = SKSpriteNode(color: Palette.paper, size: screen)
        background.anchorPoint = .zero
        node.addChild(background)

        // The picture, with a slow pan and zoom.
        let illustrated = artImage(panel.image)
        let image = illustrated ?? artImage(panel.fallback)
        let fillsScreen = illustrated != nil || panel.fallbackIsScene
        if let image {
            let picture = SKSpriteNode(texture: SKTexture(image: image))
            let aspect = image.size.width / max(image.size.height, 1)
            if fillsScreen {
                let k = max(w / image.size.width, h / image.size.height) * 1.04
                picture.size = CGSize(width: image.size.width * k, height: image.size.height * k)
                picture.position = CGPoint(x: w / 2, y: h / 2)
            } else {
                let boxH = h * 0.42
                picture.size = CGSize(width: min(w * 0.86, boxH * aspect), height: min(w * 0.86, boxH * aspect) / aspect)
                picture.position = CGPoint(x: w / 2, y: h * 0.56)
            }
            node.addChild(picture)
            // A slow camera move that eases in and out. Panels alternate pushing in and pulling back,
            // so the story doesn't feel like one long zoom.
            let pushIn = index % 2 == 0
            let drift = CGFloat(pushIn ? 1 : -1) * w * 0.03
            picture.setScale(pushIn ? 1 : 1.1)
            let zoom = SKAction.scale(to: pushIn ? 1.1 : 1, duration: panelTime + 1)
            let pan = SKAction.moveBy(x: drift, y: h * 0.012, duration: panelTime + 1)
            zoom.timingMode = .easeInEaseOut
            pan.timingMode = .easeInEaseOut
            picture.run(.group([zoom, pan]))
            if panel.effect == .storm && !Motion.reduced {
                // The storm rumbles: the picture jolts every so often, like thunder shaking the page.
                let jolt = SKAction.sequence([
                    .moveBy(x: 7, y: -4, duration: 0.04),
                    .moveBy(x: -12, y: 6, duration: 0.05),
                    .moveBy(x: 8, y: -3, duration: 0.05),
                    .moveBy(x: -3, y: 1, duration: 0.05)
                ])
                picture.run(.sequence([
                    .wait(forDuration: 0.7),
                    .repeatForever(.sequence([jolt, .wait(forDuration: 1.7, withRange: 0.8)]))
                ]))
            }
        }

        // Effects.
        switch panel.effect {
        case .confetti:
            addEmitter(to: node, texture: art.scrap.texture, colors: [Palette.stitchGold, Palette.heart, UIColor(hex: 0x7B5CFF), Palette.bramble],
                       rate: 14, speed: 60, fromTop: true)
        case .scraps, .storm:
            addEmitter(to: node, texture: art.scrap.texture, colors: [UIColor(hex: 0xD2D4DB), UIColor(hex: 0xA3A5B1)],
                       rate: 22, speed: 160, fromTop: false)
            if panel.effect == .storm, illustrated == nil {
                let flash = SKSpriteNode(color: .white, size: screen)
                flash.anchorPoint = .zero
                flash.alpha = 0
                flash.zPosition = 5
                node.addChild(flash)
                flash.run(.repeatForever(.sequence([
                    .wait(forDuration: 1.6, withRange: 1.2),
                    .fadeAlpha(to: 0.35, duration: 0.05),
                    .fadeAlpha(to: 0, duration: 0.3)
                ])))
            }
        case .sparkle:
            addEmitter(to: node, texture: art.spark.texture, colors: [Palette.stitchGold],
                       rate: 10, speed: 30, fromTop: false, center: true)
        case .none:
            break
        }

        // The caption on a paper strip.
        let stripW = min(w - 28, 420)
        let lines = PaperArt.wrap(panel.caption, fontSize: 18, maxWidth: stripW - 44, style: .heading)
        let lineHeight: CGFloat = 25
        let stripH = CGFloat(lines.count) * lineHeight + 40
        let strip = SKNode()
        strip.position = CGPoint(x: w / 2, y: safeBottom + 34 + stripH / 2)
        strip.zPosition = 10
        node.addChild(strip)
        let shadow = SKShapeNode(rect: CGRect(x: -stripW / 2, y: -stripH / 2 - 7, width: stripW, height: stripH), cornerRadius: 20)
        shadow.fillColor = UIColor(white: 0, alpha: 0.3)
        shadow.strokeColor = .clear
        strip.addChild(shadow)
        let paper = SKShapeNode(rect: CGRect(x: -stripW / 2, y: -stripH / 2, width: stripW, height: stripH), cornerRadius: 20)
        paper.fillColor = Palette.paper
        paper.strokeColor = .white
        paper.lineWidth = 5
        strip.addChild(paper)
        if Motion.reduced {
            // Gentle version: each line fades in.
            for (i, line) in lines.enumerated() {
                let textArt = art.text(line, size: 18, fill: Palette.ink, outline: Palette.paper, style: .heading)
                let sprite = SKSpriteNode(texture: textArt.texture, size: textArt.size)
                sprite.position = CGPoint(x: 0, y: (CGFloat(lines.count - 1) / 2 - CGFloat(i)) * lineHeight)
                sprite.alpha = 0
                sprite.run(.sequence([.wait(forDuration: 0.35 + Double(i) * 0.35), .fadeIn(withDuration: 0.4)]))
                strip.addChild(sprite)
            }
            strip.alpha = 0
            strip.run(.fadeIn(withDuration: 0.3))
        } else {
            addPoppingWords(lines, to: strip, lineHeight: lineHeight, startAt: 0.4)
            // The strip drops in from above, slightly crooked, and settles like a pasted paper label.
            let home = strip.position
            strip.position.y += 26
            strip.zRotation = -0.05
            strip.alpha = 0
            strip.run(.group([
                .fadeIn(withDuration: 0.12),
                .move(to: home, duration: 0.38).overshoot(),
                .rotate(toAngle: 0, duration: 0.38).overshoot()
            ]))
        }
        return node
    }

    // MARK: Caption words

    /// Lays out each line word by word, and pops each word in a beat after the one before,
    /// so the caption reads like it's being told.
    private func addPoppingWords(_ lines: [String], to strip: SKNode, lineHeight: CGFloat, startAt: TimeInterval) {
        let fontSize: CGFloat = 18
        let font = UIFont(name: "Fredoka-Bold", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .black)
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        // Text pictures carry padding around the letters for their outline; measure without it.
        let pad = ceil(fontSize * 0.25)
        var delay = startAt
        for (i, line) in lines.enumerated() {
            let words = line.split(separator: " ").map(String.init)
            let arts = words.map { art.text($0, size: fontSize, fill: Palette.ink, outline: Palette.paper, style: .heading) }
            let inked = arts.map { $0.size.width - pad * 2 }
            let lineWidth = inked.reduce(0, +) + space * CGFloat(max(0, words.count - 1))
            var x = -lineWidth / 2
            let y = (CGFloat(lines.count - 1) / 2 - CGFloat(i)) * lineHeight
            for (j, wordArt) in arts.enumerated() {
                let sprite = SKSpriteNode(texture: wordArt.texture, size: wordArt.size)
                sprite.position = CGPoint(x: x + inked[j] / 2, y: y)
                sprite.alpha = 0
                sprite.setScale(0.55)
                sprite.run(.sequence([
                    .wait(forDuration: delay),
                    .group([.fadeIn(withDuration: 0.08), .scale(to: 1, duration: 0.22).overshoot()])
                ]))
                strip.addChild(sprite)
                x += inked[j] + space
                delay += 0.07
            }
        }
    }

    // MARK: Page transitions

    private func transition(from old: SKNode, to new: SKNode, tear: Bool) {
        // Tapping ahead mid-turn: finish the earlier page at once.
        for page in leaving { page.removeFromParent() }
        leaving = []
        if Motion.reduced {
            new.alpha = 0
            new.run(.fadeIn(withDuration: 0.45))
            old.run(.sequence([.wait(forDuration: 0.45), .removeFromParent()]))
            leaving.append(old)
            return
        }
        if tear, tearAway(old, above: new) { return }
        turnPage(old, above: new)
    }

    /// The old page turns from its right edge toward the spine on the left, darkening as it lifts,
    /// and casts a moving shadow on the new page underneath.
    private func turnPage(_ old: SKNode, above new: SKNode) {
        let w = screen.width, h = screen.height
        let turn: TimeInterval = 0.55
        old.zPosition = new.zPosition + 1
        leaving.append(old)

        let shade = SKSpriteNode(color: .black, size: screen)
        shade.anchorPoint = .zero
        shade.alpha = 0
        shade.zPosition = 40
        old.addChild(shade)
        shade.run(.fadeAlpha(to: 0.4, duration: turn))

        let fold = SKAction.scaleX(to: 0.001, duration: turn)
        fold.timingMode = .easeIn
        let lift = SKAction.group([.scaleY(to: 1.04, duration: turn), .moveBy(x: 0, y: -h * 0.02, duration: turn)])
        old.run(.sequence([.group([fold, lift]), .removeFromParent()]))

        let shadow = SKSpriteNode(texture: StoryPlayer.edgeShadow, size: CGSize(width: w * 0.18, height: h))
        shadow.anchorPoint = CGPoint(x: 0, y: 0)
        shadow.zPosition = new.zPosition + 0.5
        shadow.alpha = 0
        addChild(shadow)
        leaving.append(shadow)
        shadow.run(.sequence([
            .customAction(withDuration: turn) { [weak old] node, _ in
                guard let old else { return }
                let progress = 1 - old.xScale
                node.position.x = w * old.xScale
                node.alpha = 0.55 * sin(.pi * progress)
            },
            .removeFromParent()
        ]))
    }

    /// A shadow that is darkest at its left edge and fades to clear on the right.
    private static let edgeShadow: SKTexture = {
        let size = CGSize(width: 64, height: 4)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(white: 0, alpha: 1).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            }
        }
        return SKTexture(image: image)
    }()

    /// The Shredder's entrance: the old page rips down the middle along a jagged tear,
    /// and the two halves fall away with a puff of paper scraps. False if the page can't be captured.
    private func tearAway(_ old: SKNode, above new: SKNode) -> Bool {
        let w = screen.width, h = screen.height
        guard let view = scene?.view,
              let texture = view.texture(from: old, crop: CGRect(origin: .zero, size: screen)) else { return false }

        // The tear, top to bottom, wandering around the middle.
        var tear: [CGPoint] = []
        let steps = 14
        for i in 0...steps {
            let y = h - h * CGFloat(i) / CGFloat(steps)
            let wobble = i == 0 || i == steps ? 0 : CGFloat.random(in: -26...26)
            tear.append(CGPoint(x: w / 2 + wobble, y: y))
        }

        func half(left: Bool) -> SKNode {
            let outline = CGMutablePath()
            let corner = left ? CGFloat(0) : w
            outline.move(to: CGPoint(x: corner, y: h))
            for point in tear { outline.addLine(to: point) }
            outline.addLine(to: CGPoint(x: corner, y: 0))
            outline.closeSubpath()
            let mask = SKShapeNode(path: outline)
            mask.fillColor = .white
            mask.strokeColor = .clear
            let crop = SKCropNode()
            crop.maskNode = mask
            let picture = SKSpriteNode(texture: texture, size: screen)
            picture.anchorPoint = .zero
            crop.addChild(picture)

            // A pale torn edge along the rip, like paper fibers.
            let edgePath = CGMutablePath()
            edgePath.addLines(between: tear)
            let edge = SKShapeNode(path: edgePath)
            edge.strokeColor = Palette.paper
            edge.lineWidth = 5
            edge.lineJoin = .round
            edge.zPosition = 1

            // Each half pivots on its outer bottom corner as it falls away.
            let holder = SKNode()
            holder.position = CGPoint(x: corner, y: 0)
            crop.position = CGPoint(x: -corner, y: 0)
            edge.position = crop.position
            holder.addChild(crop)
            holder.addChild(edge)
            holder.zPosition = new.zPosition + 1
            return holder
        }

        let duration: TimeInterval = 0.7
        for left in [true, false] {
            let piece = half(left: left)
            addChild(piece)
            leaving.append(piece)
            let side: CGFloat = left ? -1 : 1
            // Each half starts slow and accelerates away, like paper dropping.
            let drop = SKAction.moveBy(x: side * w * 0.35, y: -h * 0.25, duration: duration)
            let tip = SKAction.rotate(byAngle: -side * 0.45, duration: duration)
            drop.timingMode = .easeIn
            tip.timingMode = .easeIn
            let fall = SKAction.group([
                drop,
                tip,
                .sequence([.wait(forDuration: duration * 0.5), .fadeOut(withDuration: duration * 0.5)])
            ])
            piece.run(.sequence([.wait(forDuration: 0.08), fall, .removeFromParent()]))
        }
        old.removeFromParent()

        // Scraps burst out of the rip.
        let scraps = SKEmitterNode()
        scraps.particleTexture = art.scrap.texture
        scraps.numParticlesToEmit = 46
        scraps.particleBirthRate = 600
        scraps.particleLifetime = 1.1
        scraps.particleColor = UIColor(hex: 0xD2D4DB)
        scraps.particleColorBlendFactor = 1
        scraps.particleColorRedRange = 0.15
        scraps.particleSpeed = 260
        scraps.particleSpeedRange = 140
        scraps.emissionAngleRange = .pi * 2
        scraps.yAcceleration = -500
        scraps.particleRotationRange = .pi * 2
        scraps.particleRotationSpeed = 6
        scraps.particleAlphaSpeed = -0.8
        scraps.position = CGPoint(x: w / 2, y: h / 2)
        scraps.particlePositionRange = CGVector(dx: 30, dy: h * 0.8)
        scraps.zPosition = new.zPosition + 2
        addChild(scraps)
        scraps.run(.sequence([.wait(forDuration: 2), .removeFromParent()]))
        return true
    }

    private func addEmitter(to node: SKNode, texture: SKTexture, colors: [UIColor], rate: CGFloat,
                            speed: CGFloat, fromTop: Bool, center: Bool = false) {
        for color in colors {
            let emitter = SKEmitterNode()
            emitter.particleTexture = texture
            emitter.particleBirthRate = rate / CGFloat(colors.count)
            emitter.particleLifetime = 6
            emitter.particleColor = color
            emitter.particleColorBlendFactor = 1
            emitter.particleScale = center ? 0.5 : 1
            emitter.particleScaleRange = 0.4
            emitter.particleRotationRange = .pi * 2
            emitter.particleRotationSpeed = 2
            emitter.particleSpeed = speed
            emitter.particleSpeedRange = speed * 0.5
            emitter.particleAlphaSpeed = -0.15
            if center {
                emitter.position = CGPoint(x: screen.width / 2, y: screen.height * 0.56)
                emitter.particlePositionRange = CGVector(dx: screen.width * 0.6, dy: screen.height * 0.3)
                emitter.emissionAngleRange = .pi * 2
            } else if fromTop {
                emitter.position = CGPoint(x: screen.width / 2, y: screen.height + 20)
                emitter.particlePositionRange = CGVector(dx: screen.width, dy: 0)
                emitter.emissionAngle = -.pi / 2
                emitter.emissionAngleRange = 0.6
            } else {
                emitter.position = CGPoint(x: -20, y: screen.height * 0.6)
                emitter.particlePositionRange = CGVector(dx: 0, dy: screen.height * 0.6)
                emitter.emissionAngle = 0.15
                emitter.emissionAngleRange = 0.6
            }
            emitter.zPosition = 6
            emitter.advanceSimulationTime(2)
            node.addChild(emitter)
        }
    }
}
