import SpriteKit
import UIKit

/// The opening story: six illustrated panels with a slow camera push, a live cast of cutout rigs
/// acting in front of the paintings, and a caption that stitches itself in.
/// Plays on first launch and from the title screen. Tap to move on; Skip ends it.
final class StoryPlayer: SKNode {

    enum Effect { case confetti, scraps, sparkle, storm, none }

    /// What happens on each panel beyond its picture and caption.
    enum Staging {
        /// Friends wave hello in a bright world.
        case bright
        /// The Shredder rips in: thunder, lightning, the friends jump and shiver.
        case storm
        /// The color drains out of the friends and they slump.
        case drain
        /// Bramble's golden needle glimmers in the grey.
        case discovery
        /// Color floods back across the page from the needle's tip.
        case flood
        /// The friends run in to join the chase.
        case rally
    }

    struct Panel {
        let image: String
        /// Shown until the story art arrives. Character art sits centered; scenes fill the screen.
        let fallback: String
        let fallbackIsScene: Bool
        let caption: String
        let effect: Effect
        let staging: Staging
    }

    static let panels: [Panel] = [
        Panel(image: "story-1", fallback: "backdrop-color", fallbackIsScene: true,
              caption: "Once upon a page, the Paper World was bright, folded and full of friends.", effect: .confetti,
              staging: .bright),
        Panel(image: "story-2", fallback: "storm-wall", fallbackIsScene: false,
              caption: "Then the Shredder rolled in: a storm that tears paper into confetti and drains every color.", effect: .storm,
              staging: .storm),
        Panel(image: "story-3", fallback: "backdrop-gray", fallbackIsScene: true,
              caption: "Meadows ripped. Rivers frayed. One by one, the pages went gray.", effect: .scraps,
              staging: .drain),
        Panel(image: "story-4", fallback: "bramble-front", fallbackIsScene: false,
              caption: "But in the margins, a small leafy monster named Bramble found something golden.", effect: .sparkle,
              staging: .discovery),
        Panel(image: "story-5", fallback: "bramble-win", fallbackIsScene: false,
              caption: "A needle and a spool of storm-proof thread. Every stitch brings the color back.", effect: .sparkle,
              staging: .flood),
        Panel(image: "story-6", fallback: "title-card", fallbackIsScene: true,
              caption: "So Bramble ran, the storm gave chase, and friends from every page joined in.", effect: .confetti,
              staging: .rally)
    ]

    // MARK: Cast

    /// One rig on a panel: which monster, front or back view, and where it stands
    /// (x as a fraction of the picture's width, so it lines up with the painting on any screen).
    private struct Member {
        let id: String
        let front: Bool
        let fx: CGFloat
        /// Where a runner starts its entrance, also as a fraction of the picture's width.
        var fromFx: CGFloat = 0.5
    }

    /// Three friends who aren't painted into any panel, so they never double up with the art.
    /// Together with the friends painted on the last page, they make the whole roster.
    private static let friends = ["crumple", "squidge", "corrugo"]
    /// Off: the extra live cast read as clutter on top of the paintings. The scripts stay in case
    /// panels with open ground come later.
    private static let addsCast = false

    /// Spots are picked to stand on open ground in each painting, clear of the painted characters.
    private static func cast(for staging: Staging) -> [Member] {
        // The paintings carry the characters; no extra cast is added on top of them.
        if !addsCast { return [] }
        func trio(_ spots: [CGFloat]) -> [Member] {
            zip(friends, spots).map { Member(id: $0.0, front: true, fx: $0.1) }
        }
        switch staging {
        case .bright: return trio([0.25, 0.5, 0.75])
        // Bramble runs up the path on the left; the friends stand off to the sides.
        case .storm: return trio([0.17, 0.66, 0.84])
        case .drain: return trio([0.22, 0.5, 0.78])
        case .rally:
            return [
                Member(id: friends[0], front: false, fx: 0.3, fromFx: 0.12),
                Member(id: friends[1], front: false, fx: 0.5, fromFx: 0.5),
                Member(id: friends[2], front: false, fx: 0.7, fromFx: 0.88)
            ]
        case .discovery, .flood: return []
        }
    }

    /// Each friend's script. Beats are seconds from the start of the panel, in order.
    private static func beats(for staging: Staging, member k: Int) -> [StoryActor.Beat] {
        typealias Beat = StoryActor.Beat
        let lag = Double(k) * 0.18
        switch staging {
        case .bright:
            // Hellos land as the caption reaches "full of friends": wave, hop, wave.
            let hello = 1.9 + Double(k) * 0.4
            let greet = k == 1 ? StoryMotion.cheer : StoryMotion.wave
            return [Beat(at: 0, clip: StoryMotion.idle),
                    Beat(at: hello, clip: greet),
                    Beat(at: hello + greet.duration, clip: StoryMotion.idle)]
        case .storm:
            // The first thunderclap (see thunderAt) makes everyone jump.
            let jolt = thunderAt + Double(k) * 0.05
            return [Beat(at: 0, clip: StoryMotion.idle),
                    Beat(at: jolt, clip: StoryMotion.startle),
                    Beat(at: jolt + StoryMotion.startle.duration, clip: StoryMotion.tremble)]
        case .drain:
            // Still shivering, then they sag as the grey takes them (see drainAt).
            return [Beat(at: 0, clip: StoryMotion.tremble),
                    Beat(at: drainAt + 0.4 + lag, clip: StoryMotion.slump)]
        case .rally:
            // Running the whole time, with a joyful hop on the last caption words.
            let hop = 3.0 + lag
            return [Beat(at: 0, clip: StoryMotion.run),
                    Beat(at: hop, clip: StoryMotion.jump),
                    Beat(at: hop + StoryMotion.jump.duration, clip: StoryMotion.run)]
        case .discovery, .flood:
            return []
        }
    }

    /// Seconds into the storm panel for the first thunderclap, just after the tear has fallen away.
    private static let thunderAt: TimeInterval = 0.85
    /// Seconds into the grey panel when the friends start losing their color.
    private static let drainAt: TimeInterval = 0.7

    // MARK: State

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
    /// Rigs and pictures loaded a panel ahead, so a page turn never waits on decoding art.
    private var preloadedRigs: [Int: [CutoutRig?]] = [:]
    private var preloadedPictures: [Int: (texture: SKTexture, size: CGSize)] = [:]

    /// Each panel's z band. A page leaving sits half a band above the page it uncovers.
    private static let panelBand: CGFloat = 100

    init(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat, onFinish: @escaping () -> Void) {
        screen = size
        self.safeTop = safeTop
        self.safeBottom = safeBottom
        self.onFinish = onFinish
        super.init()

        let paper = SKSpriteNode(color: Palette.ink, size: size)
        paper.anchorPoint = .zero
        addChild(paper)

        // Skip, top right, above every page.
        let pill = SKShapeNode(rect: CGRect(x: -40, y: -18, width: 80, height: 36), cornerRadius: 18)
        pill.fillColor = UIColor(white: 0, alpha: 0.35)
        pill.strokeColor = UIColor(white: 1, alpha: 0.6)
        pill.lineWidth = 2
        skipButton.addChild(pill)
        let skipArt = art.text("Skip", size: 16, fill: .white, style: .body)
        skipButton.addChild(SKSpriteNode(texture: skipArt.texture, size: skipArt.size))
        skipButton.position = CGPoint(x: size.width - 56, y: size.height - safeTop - 26)
        skipButton.zPosition = 2000
        addChild(skipButton)

        // Page dots.
        let count = StoryPlayer.panels.count
        for i in 0..<count {
            let dot = SKShapeNode(circleOfRadius: 4)
            dot.fillColor = UIColor(white: 1, alpha: 0.4)
            dot.strokeColor = .clear
            dot.position = CGPoint(x: size.width / 2 + (CGFloat(i) - CGFloat(count - 1) / 2) * 16, y: safeBottom + 14)
            dot.zPosition = 2000
            addChild(dot)
            dots.append(dot)
        }

        preload(0)
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
        let panel = makePanel(StoryPlayer.panels[index], at: index)
        panel.zPosition = CGFloat(index + 1) * StoryPlayer.panelBand
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
        // Load the next panel's art once this page has settled.
        let next = index + 1
        run(.sequence([.wait(forDuration: 1.2), .run { [weak self] in self?.preload(next) }]), withKey: "preload")
    }

    private func finish(skipped: Bool) {
        guard !finished else { return }
        finished = true
        removeAllActions()
        preloadedRigs.removeAll()
        preloadedPictures.removeAll()
        // Skip cuts the score quickly; reaching the end lets its last chord ring out.
        GameAudio.shared.stopStoryScore(fade: skipped ? 0.4 : 3)
        // Build what comes next underneath first, then fade the book away over it,
        // so the running scene behind the story never shows through.
        onFinish()
        run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))
    }

    /// Loads a panel's rigs and painting ahead of time and starts its texture uploading.
    private func preload(_ i: Int) {
        guard !finished, i < StoryPlayer.panels.count else { return }
        let panel = StoryPlayer.panels[i]
        if preloadedPictures[i] == nil, let image = artImage(panel.image) {
            let texture = SKTexture(image: image)
            texture.preload {}
            preloadedPictures[i] = (texture, image.size)
        }
        if preloadedRigs[i] == nil {
            preloadedRigs[i] = StoryPlayer.loadRigs(for: panel.staging)
        }
    }

    private static func loadRigs(for staging: Staging) -> [CutoutRig?] {
        cast(for: staging).map { CutoutRig(named: $0.front ? "\($0.id)-front" : $0.id) }
    }

    // MARK: Building a panel

    private func makePanel(_ panel: Panel, at i: Int) -> SKNode {
        let node = SKNode()
        let w = screen.width
        let h = screen.height
        let reduced = Motion.reduced
        let center = CGPoint(x: w / 2, y: h / 2)

        let background = SKSpriteNode(color: Palette.paper, size: screen)
        background.anchorPoint = .zero
        node.addChild(background)

        // The caption's size comes first: the cast stands just above the strip.
        let stripW = min(w - 28, 420)
        let lines = PaperArt.wrap(panel.caption, fontSize: 18, maxWidth: stripW - 44, style: .heading)
        let lineHeight: CGFloat = 25
        let stripH = CGFloat(lines.count) * lineHeight + 40
        let stripCenterY = safeBottom + 34 + stripH / 2
        let captionTop = stripCenterY + stripH / 2

        // The camera: shaker (thunder) holds world (the slow push and pan), which holds the picture
        // and, nearer the camera, the stage where the cast stands.
        let shaker = SKNode()
        shaker.zPosition = 1
        node.addChild(shaker)
        let world = SKNode()
        world.position = center
        shaker.addChild(world)

        let pictureArt: (texture: SKTexture, size: CGSize)?
        let illustrated: Bool
        if let cached = preloadedPictures.removeValue(forKey: i) {
            pictureArt = cached
            illustrated = true
        } else if let image = artImage(panel.image) {
            pictureArt = (SKTexture(image: image), image.size)
            illustrated = true
        } else if let image = artImage(panel.fallback) {
            pictureArt = (SKTexture(image: image), image.size)
            illustrated = false
        } else {
            pictureArt = nil
            illustrated = false
        }
        let fillsScreen = illustrated || panel.fallbackIsScene

        var pictureSprite: SKSpriteNode?
        if let pictureArt {
            let imageSize = pictureArt.size
            let picture = SKSpriteNode(texture: pictureArt.texture)
            let aspect = imageSize.width / max(imageSize.height, 1)
            if fillsScreen {
                let k = max(w / imageSize.width, h / imageSize.height) * 1.04
                picture.size = CGSize(width: imageSize.width * k, height: imageSize.height * k)
                picture.position = .zero
            } else {
                let boxH = h * 0.42
                picture.size = CGSize(width: min(w * 0.86, boxH * aspect), height: min(w * 0.86, boxH * aspect) / aspect)
                picture.position = CGPoint(x: 0, y: h * 0.56 - center.y)
            }
            world.addChild(picture)
            pictureSprite = picture
        }
        let pictureSize = pictureSprite?.size ?? screen
        /// A point in the painting (fractions of its width and height, y from the top), in world units.
        func spot(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: (fx - 0.5) * pictureSize.width, y: (0.5 - fy) * pictureSize.height)
        }

        // A slow camera move that eases in and out. Panels alternate pushing in and pulling back,
        // so the story doesn't feel like one long zoom. Under Reduce Motion the camera holds still.
        let pushIn = i % 2 == 0
        let drift = CGFloat(pushIn ? 1 : -1) * w * 0.03
        let parallax: CGFloat = 1.04
        if !reduced {
            world.setScale(pushIn ? 1 : 1.1)
            let zoom = SKAction.scale(to: pushIn ? 1.1 : 1, duration: panelTime + 1)
            let pan = SKAction.moveBy(x: drift, y: h * 0.012, duration: panelTime + 1)
            zoom.timingMode = .easeInEaseOut
            pan.timingMode = .easeInEaseOut
            world.run(.group([zoom, pan]))
        }

        // The stage, a layer nearer the camera than the painting: it pushes and drifts a little more,
        // so the cast separates from the picture behind them. Its feet line is set so that even at
        // the closest zoom the cast stays clear of the caption.
        let stage = SKNode()
        stage.position = CGPoint(x: 0, y: -(center.y - captionTop - 10) / (1.1 * parallax))
        stage.zPosition = 6
        world.addChild(stage)
        if !reduced {
            stage.setScale(pushIn ? 1 : parallax)
            let depth = SKAction.scale(to: pushIn ? parallax : 1, duration: panelTime + 1)
            let slide = SKAction.moveBy(x: drift * 0.5, y: 0, duration: panelTime + 1)
            depth.timingMode = .easeInEaseOut
            slide.timingMode = .easeInEaseOut
            stage.run(.group([depth, slide]))
        }

        // The cast. Only on the real paintings: their spots are chosen to fit the art.
        var actors: [StoryActor] = []
        if illustrated {
            let members = StoryPlayer.cast(for: panel.staging)
            let rigs = preloadedRigs.removeValue(forKey: i) ?? StoryPlayer.loadRigs(for: panel.staging)
            let castHeight = min(h * 0.105, w * 0.23)
            for (k, member) in members.enumerated() {
                guard k < rigs.count, let rig = rigs[k] else { continue }
                stage.addChild(rig)
                let home = CGPoint(x: spot(member.fx, 0).x, y: 0)
                var travel: StoryActor.Travel?
                var trail: [SKSpriteNode] = []
                if !member.front {
                    // Runners come up from below the bottom of the screen, behind the caption,
                    // shrinking as they head into the picture.
                    let start = CGPoint(x: spot(member.fromFx, 0).x, y: -(captionTop + castHeight * 1.6))
                    travel = StoryActor.Travel(from: start, to: home, start: 0.3 + Double(k) * 0.2,
                                               duration: 1.5, fromScale: 1.35, toScale: 0.9)
                    let stitch = StoryPlayer.stitchArt
                    for _ in 0..<5 {
                        let dash = SKSpriteNode(texture: stitch.texture, size: stitch.size)
                        dash.zRotation = .pi / 2
                        dash.zPosition = -4.5
                        dash.alpha = 0
                        stage.addChild(dash)
                        trail.append(dash)
                    }
                }
                let actor = StoryActor(rig: rig, height: castHeight, at: home,
                                       beats: StoryPlayer.beats(for: panel.staging, member: k),
                                       phase: Double(k) * 0.37, travel: travel, trail: trail)
                actor.update(0, still: reduced)
                actors.append(actor)
            }
            if !actors.isEmpty && !reduced {
                // One driver for the whole cast; each frame is a lookup into the baked motions.
                let troupe = actors
                node.run(.customAction(withDuration: panelTime + 3) { _, elapsed in
                    let t = TimeInterval(elapsed)
                    for actor in troupe { actor.update(t, still: false) }
                })
            }
        }

        // Effects.
        if illustrated {
            addStagingEffects(panel.staging, to: node, world: world, shaker: shaker, picture: pictureSprite,
                              actors: actors, spot: spot)
        }
        switch panel.effect {
        case .confetti:
            addEmitter(to: node, texture: art.scrap.texture, colors: [Palette.stitchGold, Palette.heart, UIColor(hex: 0x7B5CFF), Palette.bramble],
                       rate: 14, speed: 60, fromTop: true)
        case .scraps, .storm:
            addEmitter(to: node, texture: art.scrap.texture, colors: [UIColor(hex: 0xD2D4DB), UIColor(hex: 0xA3A5B1)],
                       rate: 22, speed: 160, fromTop: false)
            if panel.effect == .storm {
                // The last bright bits of the meadow, swept along in the storm.
                addEmitter(to: node, texture: art.scrap.texture, colors: [Palette.stitchGold, Palette.heart, Palette.bramble],
                           rate: 6, speed: 190, fromTop: false)
                if !illustrated {
                    addThunder(to: node, shaker: shaker)
                }
            }
        case .sparkle:
            if !illustrated {
                addEmitter(to: node, texture: art.spark.texture, colors: [Palette.stitchGold],
                           rate: 10, speed: 30, fromTop: false, center: true)
            }
        case .none:
            break
        }

        // The caption on a paper strip.
        let strip = SKNode()
        strip.position = CGPoint(x: w / 2, y: stripCenterY)
        strip.zPosition = 30
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
        if reduced {
            // Gentle version: each line fades in, and the stitching fades in with them.
            for (i, line) in lines.enumerated() {
                let textArt = art.text(line, size: 18, fill: Palette.ink, outline: Palette.paper, style: .heading)
                let sprite = SKSpriteNode(texture: textArt.texture, size: textArt.size)
                sprite.position = CGPoint(x: 0, y: (CGFloat(lines.count - 1) / 2 - CGFloat(i)) * lineHeight)
                sprite.alpha = 0
                sprite.run(.sequence([.wait(forDuration: 0.35 + Double(i) * 0.35), .fadeIn(withDuration: 0.4)]))
                strip.addChild(sprite)
            }
            addStitches(to: strip, width: stripW, height: stripH, startAt: 0.35, duration: 0)
            strip.alpha = 0
            strip.run(.fadeIn(withDuration: 0.3))
        } else {
            let wordsEnd = addPoppingWords(lines, to: strip, lineHeight: lineHeight, startAt: 0.4)
            // A needle's glint sews a running stitch around the label while the words appear.
            addStitches(to: strip, width: stripW, height: stripH, startAt: 0.4, duration: max(0.8, wordsEnd - 0.4))
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

    // MARK: Staging effects

    private func addStagingEffects(_ staging: Staging, to node: SKNode, world: SKNode, shaker: SKNode,
                                   picture: SKSpriteNode?, actors: [StoryActor],
                                   spot: (CGFloat, CGFloat) -> CGPoint) {
        let reduced = Motion.reduced
        switch staging {
        case .bright:
            break

        case .storm:
            addThunder(to: node, shaker: shaker)

        case .drain:
            // The friends' color seeps away to grey.
            let drain = StoryTint.make()
            for actor in actors { actor.tint(drain) }
            let fade: TimeInterval = 1.8
            node.run(.sequence([
                .wait(forDuration: StoryPlayer.drainAt),
                .customAction(withDuration: fade) { _, elapsed in
                    StoryTint.set(drain, "u_gray", CutoutRig.smooth(0, CGFloat(fade), elapsed))
                },
                .run { StoryTint.set(drain, "u_gray", 1) }
            ]))

        case .discovery:
            guard let picture else { return }
            let size = picture.size
            // Gold glints drift up the needle and around the spool.
            let glints = goldEmitter(rate: 12, speed: 24, lifetime: 2.4)
            glints.position = spot(0.68, 0.38)
            glints.particlePositionRange = CGVector(dx: size.width * 0.28, dy: size.height * 0.45)
            glints.emissionAngle = .pi / 2
            glints.emissionAngleRange = 0.8
            glints.advanceSimulationTime(1.5)
            glints.zPosition = 9
            world.addChild(glints)
            // A warm glow breathes where the needle's point meets the ground...
            let glow = SKSpriteNode(texture: art.puff.texture, size: CGSize(width: size.width * 0.32, height: size.width * 0.32))
            glow.color = Palette.stitchGold
            glow.colorBlendFactor = 1
            glow.blendMode = .add
            glow.alpha = 0.35
            glow.position = spot(0.55, 0.62)
            glow.zPosition = 8
            world.addChild(glow)
            if !reduced {
                let pulse = SKAction.sequence([
                    .group([.fadeAlpha(to: 0.6, duration: 0.9), .scale(to: 1.15, duration: 0.9)]),
                    .group([.fadeAlpha(to: 0.3, duration: 0.9), .scale(to: 1, duration: 0.9)])
                ])
                pulse.timingMode = .easeInEaseOut
                glow.run(.repeatForever(pulse))
            }
            // ...and flares as the caption says "found something golden".
            let point = spot(0.55, 0.62)
            node.run(.sequence([
                .wait(forDuration: 2.1),
                .run { [weak self, weak world] in
                    guard let self, let world else { return }
                    self.sparkBurst(in: world, at: point, count: reduced ? 10 : 34)
                }
            ]))

        case .flood:
            guard let picture else { return }
            // The page starts grey and the color floods out from the needle's tip,
            // with a golden seam along the spreading edge.
            let flood = StoryTint.make()
            let tip = CGPoint(x: 0.88, y: 0.29)
            StoryTint.set(flood, "u_gray", 1)
            StoryTint.set(flood, "u_cx", tip.x)
            StoryTint.set(flood, "u_cy", 1 - tip.y)
            StoryTint.set(flood, "u_aspect", picture.size.width / max(picture.size.height, 1))
            picture.shader = flood
            if reduced {
                // A plain crossfade from grey to color.
                node.run(.sequence([
                    .wait(forDuration: 0.5),
                    .customAction(withDuration: 1.6) { _, elapsed in
                        StoryTint.set(flood, "u_gray", 1 - CutoutRig.smooth(0, 1.6, elapsed))
                    },
                    .run { StoryTint.set(flood, "u_gray", 0) }
                ]))
            } else {
                let spread: TimeInterval = 2.6
                let tipPoint = spot(tip.x, tip.y)
                StoryTint.set(flood, "u_seam", 1)
                node.run(.sequence([
                    .wait(forDuration: 0.45),
                    .run { [weak self, weak world] in
                        guard let self, let world else { return }
                        self.sparkBurst(in: world, at: tipPoint, count: 28)
                    },
                    .customAction(withDuration: spread) { _, elapsed in
                        let k = elapsed / CGFloat(spread)
                        let eased = 1 - pow(1 - k, 2.2)
                        StoryTint.set(flood, "u_radius", -0.02 + 1.05 * eased)
                        StoryTint.set(flood, "u_seam", 1 - CutoutRig.smooth(0.7, 1, k))
                    },
                    .run {
                        StoryTint.set(flood, "u_gray", 0)
                        StoryTint.set(flood, "u_seam", 0)
                    }
                ]))
            }
            // Golden thread glints along the zigzag stitches Bramble has sewn, once the color reaches them.
            let thread = goldEmitter(rate: 0, speed: 18, lifetime: 2)
            thread.position = spot(0.27, 0.33)
            thread.particlePositionRange = CGVector(dx: picture.size.width * 0.4, dy: picture.size.height * 0.42)
            thread.emissionAngleRange = .pi * 2
            thread.zPosition = 9
            world.addChild(thread)
            node.run(.sequence([.wait(forDuration: 1.3), .run { thread.particleBirthRate = 14 }]))

        case .rally:
            break
        }
    }

    /// Thunder on the storm page: a white flash, a jagged bolt across the sky and a jolt of the camera.
    /// The first clap lands as the torn page clears; more follow every couple of seconds.
    private func addThunder(to node: SKNode, shaker: SKNode) {
        let flash = SKSpriteNode(color: .white, size: screen)
        flash.anchorPoint = .zero
        flash.alpha = 0
        flash.zPosition = 14
        node.addChild(flash)
        let bolt = makeBolt()
        bolt.isHidden = true
        bolt.zPosition = 13
        node.addChild(bolt)
        node.run(.sequence([
            .wait(forDuration: StoryPlayer.thunderAt),
            .run { [weak self] in self?.thunder(flash: flash, bolt: bolt, shaker: shaker, strong: true) },
            .repeatForever(.sequence([
                .wait(forDuration: 1.9, withRange: 0.8),
                .run { [weak self] in self?.thunder(flash: flash, bolt: bolt, shaker: shaker, strong: false) }
            ]))
        ]))
    }

    private func thunder(flash: SKSpriteNode, bolt: SKNode, shaker: SKNode, strong: Bool) {
        let reduced = Motion.reduced
        let peak: CGFloat = (strong ? 0.6 : 0.4) * (reduced ? Motion.reducedStrength : 1)
        flash.removeAllActions()
        flash.run(.sequence([
            .fadeAlpha(to: peak, duration: 0.03),
            .fadeAlpha(to: peak * 0.2, duration: 0.06),
            .fadeAlpha(to: peak * 0.8, duration: 0.03),
            .fadeAlpha(to: 0, duration: 0.4)
        ]))
        guard !reduced else { return }
        // The bolt forks down somewhere in the sky, a different spot each time.
        bolt.removeAllActions()
        bolt.position = CGPoint(x: screen.width * CGFloat.random(in: 0.2...0.8),
                                y: screen.height * CGFloat.random(in: 0.74...0.9))
        bolt.xScale = Bool.random() ? 1 : -1
        bolt.alpha = 1
        bolt.isHidden = false
        bolt.run(.sequence([
            .wait(forDuration: 0.07), .hide(), .wait(forDuration: 0.05), .unhide(),
            .fadeOut(withDuration: 0.25), .hide()
        ]))
        // The page jolts and settles.
        let a: CGFloat = strong ? 10 : 5
        shaker.removeAllActions()
        shaker.position = .zero
        shaker.run(.sequence([
            .moveBy(x: a, y: -a * 0.5, duration: 0.04),
            .moveBy(x: -a * 1.7, y: a * 0.8, duration: 0.05),
            .moveBy(x: a * 1.1, y: -a * 0.45, duration: 0.05),
            .moveBy(x: -a * 0.4, y: a * 0.15, duration: 0.05),
            .move(to: .zero, duration: 0.04)
        ]))
    }

    /// A forked lightning bolt hanging down from (0, 0): a soft glow under a white core.
    private func makeBolt() -> SKNode {
        let length = screen.height * 0.3
        var points: [CGPoint] = [.zero]
        let steps = 7
        for s in 1...steps {
            let y = -length * CGFloat(s) / CGFloat(steps)
            points.append(CGPoint(x: CGFloat.random(in: -22...22) + CGFloat(s) * 4, y: y))
        }
        let path = CGMutablePath()
        path.addLines(between: points)
        // A short fork off the middle.
        let fork = points[3]
        path.move(to: fork)
        path.addLine(to: CGPoint(x: fork.x + 34, y: fork.y - length * 0.12))
        path.addLine(to: CGPoint(x: fork.x + 46, y: fork.y - length * 0.24))

        let holder = SKNode()
        let glow = SKShapeNode(path: path)
        glow.strokeColor = UIColor(hex: 0xFFF3B0, alpha: 0.45)
        glow.lineWidth = 11
        glow.lineCap = .round
        glow.lineJoin = .round
        holder.addChild(glow)
        let core = SKShapeNode(path: path)
        core.strokeColor = .white
        core.lineWidth = 3.5
        core.lineCap = .round
        core.lineJoin = .round
        holder.addChild(core)
        return holder
    }

    private func goldEmitter(rate: CGFloat, speed: CGFloat, lifetime: CGFloat) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = art.spark.texture
        emitter.particleBirthRate = rate
        emitter.particleLifetime = lifetime
        emitter.particleLifetimeRange = lifetime * 0.4
        emitter.particleColor = Palette.stitchGold
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.particleScale = 0.35
        emitter.particleScaleRange = 0.25
        emitter.particleScaleSpeed = -0.08
        emitter.particleRotationRange = .pi
        emitter.particleRotationSpeed = 1.5
        emitter.particleSpeed = speed
        emitter.particleSpeedRange = speed * 0.6
        emitter.particleAlpha = 0
        emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [0, 1, 0] as [NSNumber], times: [0, 0.3, 1])
        return emitter
    }

    /// A one-off burst of gold sparks.
    private func sparkBurst(in parent: SKNode, at point: CGPoint, count: Int) {
        let burst = goldEmitter(rate: 400, speed: 170, lifetime: 0.9)
        burst.numParticlesToEmit = count
        burst.particleScale = 0.55
        burst.emissionAngleRange = .pi * 2
        burst.yAcceleration = -120
        burst.position = point
        burst.zPosition = 10
        parent.addChild(burst)
        burst.run(.sequence([.wait(forDuration: 1.4), .removeFromParent()]))
    }

    // MARK: Caption words

    /// Lays out each line word by word, and pops each word in a beat after the one before,
    /// so the caption reads like it's being told. Returns when the last word appears.
    @discardableResult
    private func addPoppingWords(_ lines: [String], to strip: SKNode, lineHeight: CGFloat, startAt: TimeInterval) -> TimeInterval {
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
        return delay
    }

    /// One gold running stitch.
    private static var stitchArt: Art {
        PaperArt.shared.art("story.stitch", size: CGSize(width: 9, height: 3.5)) { ctx in
            ctx.setFillColor(Palette.stitchGold.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 9, height: 3.5), cornerRadius: 1.75).cgPath)
            ctx.fillPath()
        }
    }

    /// A running stitch sewn around the caption label: along the top left to right, then back along
    /// the bottom, with a glint leading like the needle. Duration 0 fades it all in at once.
    private func addStitches(to strip: SKNode, width: CGFloat, height: CGFloat, startAt: TimeInterval, duration: TimeInterval) {
        let stitch = StoryPlayer.stitchArt
        let margin: CGFloat = 26
        let inset: CGFloat = 10
        let usable = width - margin * 2
        let count = max(2, Int(usable / 15))
        let topY = height / 2 - inset
        let bottomY = -height / 2 + inset
        let half = duration / 2
        for (row, y) in [(0, topY), (1, bottomY)] {
            for k in 0..<count {
                let along = CGFloat(k) / CGFloat(count - 1)
                // The top row sews left to right, the bottom row comes back right to left.
                let x = row == 0 ? -usable / 2 + usable * along : usable / 2 - usable * along
                let sprite = SKSpriteNode(texture: stitch.texture, size: stitch.size)
                sprite.position = CGPoint(x: x, y: y)
                sprite.alpha = 0
                strip.addChild(sprite)
                if duration <= 0 {
                    sprite.run(.sequence([.wait(forDuration: startAt), .fadeIn(withDuration: 0.4)]))
                } else {
                    sprite.setScale(0.3)
                    let delay = startAt + Double(row) * half + half * Double(along)
                    sprite.run(.sequence([
                        .wait(forDuration: delay),
                        .group([.fadeIn(withDuration: 0.05), .scale(to: 1, duration: 0.18).overshoot()])
                    ]))
                }
            }
        }
        guard duration > 0 else { return }
        // The glint: across the top, down the right end, back along the bottom.
        let route = CGMutablePath()
        route.move(to: CGPoint(x: -usable / 2, y: topY))
        route.addLine(to: CGPoint(x: usable / 2, y: topY))
        route.addLine(to: CGPoint(x: usable / 2, y: bottomY))
        route.addLine(to: CGPoint(x: -usable / 2, y: bottomY))
        let glint = SKSpriteNode(texture: art.spark.texture, size: CGSize(width: 16, height: 16))
        glint.color = Palette.stitchGold
        glint.colorBlendFactor = 1
        glint.blendMode = .add
        glint.position = CGPoint(x: -usable / 2, y: topY)
        glint.alpha = 0
        glint.zPosition = 2
        strip.addChild(glint)
        glint.run(.sequence([
            .wait(forDuration: startAt),
            .fadeIn(withDuration: 0.1),
            .group([
                .follow(route, asOffset: false, orientToPath: false, duration: duration),
                .rotate(byAngle: .pi * 4, duration: duration)
            ]),
            .fadeOut(withDuration: 0.2),
            .removeFromParent()
        ]))
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
        // Half a band up: above everything on the new page, caption included.
        old.zPosition = new.zPosition + StoryPlayer.panelBand / 2
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
        shadow.zPosition = new.zPosition + StoryPlayer.panelBand * 0.45
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
    /// and the two halves fall away in a burst of bright paper confetti. False if the page can't be captured.
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
        let above = new.zPosition + StoryPlayer.panelBand / 2

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
            holder.zPosition = above
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

        // The bright page bursts into confetti along the rip: its colors first, then grey scraps.
        let colors: [UIColor] = [Palette.stitchGold, Palette.heart, UIColor(hex: 0x7B5CFF), Palette.bramble,
                                 UIColor(hex: 0x4FC3F7), UIColor(hex: 0xD2D4DB), UIColor(hex: 0xA3A5B1)]
        for (k, color) in colors.enumerated() {
            let scraps = SKEmitterNode()
            scraps.particleTexture = art.scrap.texture
            scraps.numParticlesToEmit = k < 5 ? 12 : 16
            scraps.particleBirthRate = 600
            scraps.particleLifetime = 1.4
            scraps.particleLifetimeRange = 0.4
            scraps.particleColor = color
            scraps.particleColorBlendFactor = 1
            scraps.particleScale = 1
            scraps.particleScaleRange = 0.6
            scraps.particleSpeed = 300
            scraps.particleSpeedRange = 180
            scraps.emissionAngleRange = .pi * 2
            scraps.yAcceleration = -520
            scraps.particleRotationRange = .pi * 2
            scraps.particleRotationSpeed = 7
            scraps.particleAlphaSpeed = -0.7
            scraps.position = CGPoint(x: w / 2, y: h / 2)
            scraps.particlePositionRange = CGVector(dx: 36, dy: h * 0.85)
            scraps.zPosition = above + 10
            addChild(scraps)
            leaving.append(scraps)
            scraps.run(.sequence([.wait(forDuration: 2.2), .removeFromParent()]))
        }
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
            emitter.zPosition = 12
            emitter.advanceSimulationTime(2)
            node.addChild(emitter)
        }
    }
}
