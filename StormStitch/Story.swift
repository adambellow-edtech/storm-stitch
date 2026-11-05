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
    private let panelTime: TimeInterval = 5.5

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
            finish()
        } else {
            advance()
        }
    }

    private func advance() {
        guard !finished else { return }
        removeAction(forKey: "auto")
        index += 1
        guard index < StoryPlayer.panels.count else {
            finish()
            return
        }
        for (i, dot) in dots.enumerated() {
            dot.fillColor = i == index ? Palette.stitchGold : UIColor(white: 1, alpha: 0.4)
        }
        let panel = makePanel(StoryPlayer.panels[index])
        panel.alpha = 0
        panel.zPosition = CGFloat(index + 1)
        addChild(panel)
        panel.run(.fadeIn(withDuration: 0.45))
        if let old = current {
            old.run(.sequence([.wait(forDuration: 0.45), .removeFromParent()]))
        }
        current = panel
        run(.sequence([.wait(forDuration: panelTime), .run { [weak self] in self?.advance() }]), withKey: "auto")
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        removeAllActions()
        run(.sequence([.fadeOut(withDuration: 0.35), .run { [weak self] in self?.onFinish() }]))
    }

    private func makePanel(_ panel: Panel) -> SKNode {
        let node = SKNode()
        let w = screen.width
        let h = screen.height

        let background = SKSpriteNode(color: Palette.paper, size: screen)
        background.anchorPoint = .zero
        node.addChild(background)

        // The picture, with a slow pan and zoom.
        let illustrated = UIImage(named: panel.image)
        let image = illustrated ?? UIImage(named: panel.fallback)
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
            let drift = CGFloat(index % 2 == 0 ? 1 : -1) * w * 0.03
            picture.run(.group([
                .scale(to: 1.1, duration: panelTime + 1),
                .moveBy(x: drift, y: h * 0.012, duration: panelTime + 1)
            ]))
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
        for (i, line) in lines.enumerated() {
            let textArt = art.text(line, size: 18, fill: Palette.ink, outline: Palette.paper, style: .heading)
            let sprite = SKSpriteNode(texture: textArt.texture, size: textArt.size)
            sprite.position = CGPoint(x: 0, y: (CGFloat(lines.count - 1) / 2 - CGFloat(i)) * lineHeight)
            sprite.alpha = 0
            sprite.run(.sequence([.wait(forDuration: 0.35 + Double(i) * 0.35), .fadeIn(withDuration: 0.4)]))
            strip.addChild(sprite)
        }
        strip.setScale(0.92)
        strip.run(.scale(to: 1, duration: 0.3))
        return node
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
