import SpriteKit
import UIKit

/// The state the Time Machine needs to put a run back exactly as it was.
struct RunSnapshot {
    var elapsed: Double
    var distance: Double
    var heartsLeft: Int
    var hitsTaken: Int
    var spools: Int
    var streak: Int
    var bestStreak: Int
    var closeCalls: Int
    var meter: Double
    var stormDistance: Double
    var playerX: Double
    var laneIndex: Int
    var laneFromX: Double
    var laneToX: Double
    var laneProgress: Double
    var playerY: Double
    var velocityY: Double
    var nextRowIn: Double
    var fullyStitched: Bool
    var gateSpawned: Bool
    var rng: GameRNG
    var powers: PowerState
    /// Patch Armor's spares live in `powers`, so the worn patch must rewind with them.
    var shieldActive: Bool
}

/// The Shredder's chase: every world's last stage is a run from the storm itself, to its own chase music.
/// A world can add cheap flavor of its own on top. Notebook Meadow and Origami Peaks keep their
/// finales as they were (only the chase music is new there).
struct ShredderChase {
    /// Tint for the storm's cloud layers; nil keeps the usual ink.
    var stormTint: UIColor? = nil
    /// Color of the torn scraps the storm throws up; nil keeps the usual gray paper.
    var scrapColor: UIColor? = nil
    /// Hazards are drawn from this table instead of an even mix (a repeated kind comes up more).
    var hazardMix: [RunScene.HazardKind]? = nil
    /// The storm strikes and the Shredder laughs a moment into the run, with this line on screen.
    var introLine: String? = nil
}

extension World {
    var shredderChase: ShredderChase {
        switch id {
        case "canyon":
            // Cardboard-brown clouds spitting box scraps, and the cartons come tumbling.
            return ShredderChase(stormTint: UIColor(hex: 0x6B4A2B), scrapColor: UIColor(hex: 0xC9A57A),
                                 hazardMix: [.crate, .crate, .low, .overhead],
                                 introLine: "The Shredder is tearing up the boxes!")
        case "lagoon":
            // Deep ink-blue clouds spraying ink drops, and blots to hop all the way.
            return ShredderChase(stormTint: UIColor(hex: 0x23306A), scrapColor: UIColor(hex: 0x5B7BD5),
                                 hazardMix: [.low, .low, .overhead, .crate],
                                 introLine: "The Shredder churns up the ink!")
        default:
            return ShredderChase()
        }
    }
}

extension RunScene {

    // MARK: Starting a run

    /// The settings for a mode.
    func makeConfig(for mode: RunMode) -> RunConfig {
        switch mode {
        case .stage(let index):
            return World.config(forStage: index)
        case .daily(let storm), .challenge(let storm, _, _):
            return storm.config
        case .race(let holiday):
            return RunConfig(length: holiday.raceLength, startSpeed: 9, endSpeed: 14, rampTime: holiday.raceLength,
                             intervalStart: 0.95, intervalEnd: 0.72, overheadFrom: 10, doubleChance: 0.3,
                             meterPerSpool: 1.0 / 90, rule: .calm, seed: GameRNG.freshSeed(), hints: false)
        case .endless:
            return RunConfig(length: .infinity, startSpeed: tuning.startSpeed, endSpeed: tuning.endSpeed,
                             rampTime: tuning.runLength, intervalStart: tuning.rowIntervalStart,
                             intervalEnd: tuning.rowIntervalEnd, overheadFrom: 15, doubleChance: 0.45,
                             meterPerSpool: 0.012, rule: .calm, seed: GameRNG.freshSeed(), hints: false)
        }
    }

    func startRun(_ newMode: RunMode) {
        mode = newMode
        config = makeConfig(for: newMode)
        clearScreen()
        story?.removeFromParent()
        story = nil
        audio.stopStoryScore()

        // Daily runs use the day's monster and no gadgets, so every score is comparable.
        switch newMode {
        case .daily(let storm), .challenge(let storm, _, _):
            monster = Monster.named(storm.monsterID)
            gadget = nil
        default:
            monster = Monster.roster[Monster.selectedIndex]
            if !Progress.shared.isUnlocked(monster) { monster = Monster.roster[0] }
            gadget = Progress.shared.equippedGadget
        }
        currentPose = ""

        applyTheme(themeFor(newMode))
        let chase = shredderChase
        applyChaseLook(chase)

        resetWorld()
        if monster.ability == .frost {
            // Crumple starts every run behind a Stitch Shield.
            shieldActive = true
            shieldRing.isHidden = false
        }
        state = .running
        eyeGloat = false
        eyeDefeated = false
        runSpeed = config.startSpeed
        hud.removeAllActions()
        hud.alpha = 1
        shownSeconds = -1
        shownSpools = -1
        shownRival = -1
        refreshGadgetButton()
        setupRival()
        nightShade.alpha = config.rule == .night ? 0.86 : 0
        applyFog()
        updateHUD()
        audio.play(.start)
        audio.setChase(chase != nil)
        audio.setMusic(playing: true)
        haptics.success()
        velocityY = tuning.jumpVelocity * 0.7
        playerY = 0.0001

        // Opening banner.
        let banner: String
        switch newMode {
        case .stage(let index):
            let world = World.all[World.index(ofStage: index)]
            banner = "\(world.id == "meadow" ? "Stage" : world.name) \(Stage.all[index].number): \(Stage.all[index].name)"
        case .daily(let storm): banner = "\(storm.rule.emoji) \(storm.rule.name)"
        case .challenge(let storm, let target, let from): banner = liveRaceBanner ?? "Beat \(from): \(target.formatted()) \(storm.rule.emoji)"
        case .race(let holiday): banner = "\(holiday.raceName): beat \(holiday.rivalName)!"
        case .endless: banner = "Endless: outrun the storm!"
        }
        popText(banner, size: 24, color: .white, at: CGPoint(x: size.width / 2, y: size.height * 0.66), rise: 20, life: 2.2)

        removeAction(forKey: "chaseIntro")
        if let line = chase?.introLine {
            run(.sequence([
                .wait(forDuration: 1.6),
                .run { [weak self] in
                    guard let self, self.state == .running else { return }
                    self.lightningCooldown = 0
                    self.lightningStrike(power: 2)
                    self.audio.play(.evilLaugh, volume: 0.7)
                    self.popText(line, size: 22, color: UIColor(hex: 0xFFD9D2),
                                 at: CGPoint(x: self.size.width / 2, y: self.size.height * 0.58), rise: 16, life: 2.2)
                }
            ]), withKey: "chaseIntro")
        }
    }

    /// The Shredder chase for the stage being played, or nil when this run isn't one.
    var shredderChase: ShredderChase? {
        guard case .stage(let index) = mode, World.isShredderChase(stage: index) else { return nil }
        return World.all[World.index(ofStage: index)].shredderChase
    }

    /// Tints the storm for a chase that asks for it, or puts the usual ink storm back.
    func applyChaseLook(_ chase: ShredderChase?) {
        let tint = chase?.stormTint
        stormBack.color = tint ?? Palette.ink
        stormBack.colorBlendFactor = tint == nil ? 0.35 : 0.5
        stormFar?.color = tint ?? Palette.ink
        stormFar?.colorBlendFactor = tint == nil ? 0.45 : 0.55
        stormNear?.color = tint ?? Palette.ink
        stormNear?.colorBlendFactor = tint == nil ? 0.25 : 0.4
        stormScraps?.particleColor = chase?.scrapColor ?? UIColor(hex: 0xD2D4DB)
    }

    // MARK: Per-frame run additions

    /// Everything new that happens each frame of a run: gadgets, rules, the rival, hints,
    /// Time Machine snapshots and the finish gate.
    func stepExtras(_ dt: Double) {
        if magnetTimer > 0 { magnetTimer -= dt }
        if planeTimer > 0 {
            planeTimer -= dt
            if planeTimer <= 0 { velocityY = 0 }
        }
        if inkTimer > 0 { inkTimer -= dt * 2 }
        if foldTimer > 0 { foldTimer -= dt }
        shieldRing.isHidden = !shieldActive

        // Magnet: nearby spools drift to you.
        if magnetTimer > 0 {
            for thing in things where !thing.retired && thing.z < 14 && thing.z > -0.3 {
                if case .spool = thing.kind {
                    let pull = min(1, dt * 5)
                    thing.x += (playerX - thing.x) * pull
                    thing.y += (playerY + 0.5 - thing.y) * pull
                }
            }
        }

        // Gusty days push you between lanes, with a warning first.
        if config.rule == .gusty {
            gustTimer -= dt
            if gustTimer < 1 && !gustWarned {
                gustWarned = true
                gustDirection = laneIndex == 1 ? -1 : (laneIndex == -1 ? 1 : (gustRNG.next() % 2 == 0 ? 1 : -1))
                let arrow = gustDirection > 0 ? "💨 →" : "← 💨"
                popText(arrow, size: 34, color: .white, at: CGPoint(x: size.width / 2, y: size.height * 0.6), rise: 0, life: 0.9)
            }
            if gustTimer <= 0 {
                if planeTimer <= 0 { moveLane(gustDirection) }
                gustTimer = 5 + Double(gustRNG.next() % 30) / 10
                gustWarned = false
            }
        }

        updateRival(dt)
        showHints()

        // Time Machine: remember the last few seconds.
        if gadget == .rewind {
            snapshotTimer -= dt
            if snapshotTimer <= 0 {
                snapshotTimer = 0.1
                snapshots.append(makeSnapshot())
                snapshots.removeAll { elapsed - $0.elapsed > 4 }
            }
        }

        stepPowerGates(dt)
        guard state == .running else { return }

        // The finish gate rolls in near the end of a timed run.
        if config.length.isFinite && !gateSpawned && elapsed >= config.length - 3 {
            gateSpawned = true
            spawnGate(atZ: max(14, runSpeed * 3))
        }
        if let gate = gateThing, gate.z <= 6, state == .running {
            beginCelebration()
        }
    }

    // MARK: Hints

    func showHints() {
        guard config.hints else { return }
        let hints: [(Double, String)] = [
            (1.5, "Swipe left or right to change lanes"),
            (8, "Tap to jump over erasers"),
            (15, "Grab spools to stitch the world back"),
            (23, "Boxes block a lane: swipe around them"),
            (31, "Fill the Stitch meter for the third star")
        ]
        guard hintIndex < hints.count, elapsed >= hints[hintIndex].0 else { return }
        popText(hints[hintIndex].1, size: 19, color: .white, at: CGPoint(x: size.width / 2, y: size.height * 0.62), rise: 10, life: 3)
        hintIndex += 1
    }

    // MARK: Finish gate and celebration

    func spawnGate(atZ z: Double) {
        let gateArt = illustrated("seam-gate", width: 360) ?? art.seamGate
        let sprite = SKSpriteNode(texture: gateArt.texture, size: gateArt.size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.02)
        sprite.alpha = 0
        objectLayer.addChild(sprite)
        let gate = Thing(kind: .gate, sprite: sprite, worldScale: 1, x: 0, z: z, y: 0)
        gate.spawnedAt = distance
        gate.resolved = true
        things.append(gate)
        gateThing = gate
    }

    /// A lightning strike inside the storm wall: a crack, a flash, a jolt, and jagged bolts.
    func lightningStrike(power: Int) {
        guard lightningCooldown <= 0 else { return }
        lightningCooldown = 1.2
        audio.play(.crack, volume: min(1, 0.55 + Float(power) * 0.15))
        thunderFlash(strength: 0.35 + Double(power) * 0.15, withSound: false)
        shake(strength: CGFloat(3 + power * 3))
        haptics.hit()
        let top = (stormArt?.frame.maxY ?? size.height * 0.3) - 10
        let bottom = max(0, top - size.height * (0.12 + CGFloat(power) * 0.04))
        for _ in 0..<max(1, power) {
            let x = CGFloat.random(in: size.width * 0.12...size.width * 0.88)
            let bolt = SKShapeNode(path: boltPath(from: CGPoint(x: x, y: top), to: bottom))
            bolt.strokeColor = UIColor(hex: 0xF4F0FF)
            bolt.lineWidth = 3 + CGFloat(power)
            bolt.glowWidth = 6 + CGFloat(power) * 2
            bolt.lineCap = .round
            bolt.lineJoin = .round
            bolt.zPosition = 1.5
            stormRoot.addChild(bolt)
            bolt.run(.sequence([
                .fadeAlpha(to: 0.2, duration: 0.05),
                .fadeAlpha(to: 1, duration: 0.04),
                .fadeOut(withDuration: 0.3),
                .removeFromParent()
            ]))
        }
    }

    /// A jagged bolt with one fork, from a point in the cloud down to a height.
    func boltPath(from start: CGPoint, to bottomY: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        var point = start
        let steps = 7
        let drop = (start.y - bottomY) / CGFloat(steps)
        var forkPoint = start
        for i in 1...steps {
            point = CGPoint(x: point.x + CGFloat.random(in: -22...22), y: start.y - drop * CGFloat(i))
            path.addLine(to: point)
            if i == 3 { forkPoint = point }
        }
        path.move(to: forkPoint)
        var fork = forkPoint
        for _ in 0..<3 {
            fork = CGPoint(x: fork.x + CGFloat.random(in: 8...26) * (Bool.random() ? 1 : -1), y: fork.y - drop * 0.8)
            path.addLine(to: fork)
        }
        return path
    }

    /// Fog Day pulls the fog in close; every other run keeps it far off.
    func applyFog() {
        let fog = config.rule == .fog
        PaperGround.setFog(texturedGray, near: fog ? 3 : 16, far: fog ? 16 : 60)
        PaperGround.setFog(texturedColor, near: fog ? 3 : 16, far: fog ? 16 : 60)
    }

    /// Ends every timed gadget and pose so nothing sticks through the finish or the results.
    func clearActiveEffects() {
        planeTimer = 0
        foldTimer = 0
        magnetTimer = 0
        inkTimer = 0
        slideTimer = 0
        hitPoseTimer = 0
        shieldActive = false
        shieldRing.isHidden = true
        planeSprite.isHidden = true
    }

    /// The seam gate is reached: slow down, sew the tear shut, flood the world with color.
    func beginCelebration() {
        // The third star counts only what you stitched before reaching the gate.
        fullyStitchedBeforeGate = fullyStitched
        clearActiveEffects()
        state = .celebrating
        celebrationSpeed = runSpeed
        trackedTouch = nil
        eyeDefeated = true
        hud.run(.fadeAlpha(to: 0.3, duration: 0.4))
        audio.setIntensity(1)
        haptics.lane()

        guard let gate = gateThing else {
            run(.sequence([.wait(forDuration: 1.2), .run { [weak self] in self?.finishRun() }]))
            return
        }

        // The needle sews cross-stitches down the tear, one X at a time, riding along with the gate.
        let gateSprite = gate.sprite
        // The gate is scaled by depth every frame; work in its unscaled painting size.
        let gateArtSize = (illustrated("seam-gate", width: 360) ?? art.seamGate).size
        let gateW = gateArtSize.width
        let gateH = gateArtSize.height
        // Where the tear runs in the seam-gate painting, as fractions (x from left, y from bottom).
        let tear: [(x: CGFloat, y: CGFloat)] = [(0.50, 0.72), (0.49, 0.65), (0.47, 0.58), (0.46, 0.51),
                                                (0.46, 0.44), (0.465, 0.37), (0.475, 0.30)]
        func local(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint {
            CGPoint(x: (fx - gateSprite.anchorPoint.x) * gateW, y: (fy - gateSprite.anchorPoint.y) * gateH)
        }
        let armX = gateW * 0.035, armY = gateH * 0.03

        let needle = SKNode()
        needle.zPosition = 6
        let needleArt = illustrated("needle", width: 72) ?? art.needle
        let needleSprite = SKSpriteNode(texture: needleArt.texture, size: needleArt.size)
        // The painted needle points down-left; turn it so its tip leads along the path.
        needleSprite.zRotation = 2.28
        needleSprite.anchorPoint = CGPoint(x: 0.4, y: 0.4)
        needle.addChild(needleSprite)
        needle.position = local(0.62, 0.85)
        gateSprite.addChild(needle)

        var actions: [SKAction] = [.wait(forDuration: 0.4)]
        var needleAt = needle.position
        func travel(to point: CGPoint, lift: CGFloat, duration: TimeInterval) -> SKAction {
            let path = CGMutablePath()
            path.move(to: needleAt)
            let mid = CGPoint(x: (needleAt.x + point.x) / 2 + lift * 0.4, y: max(needleAt.y, point.y) + lift)
            path.addQuadCurve(to: point, control: mid)
            needleAt = point
            return .run { [weak needle] in
                needle?.run(.follow(path, asOffset: false, orientToPath: true, duration: duration), withKey: "sew")
            }
        }
        for (i, spot) in tear.enumerated() {
            let center = local(spot.x, spot.y)
            let arms = [(CGPoint(x: center.x - armX, y: center.y + armY), CGPoint(x: center.x + armX, y: center.y - armY)),
                        (CGPoint(x: center.x + armX, y: center.y + armY), CGPoint(x: center.x - armX, y: center.y - armY))]
            for (j, arm) in arms.enumerated() {
                actions.append(travel(to: arm.0, lift: gateH * (j == 0 ? 0.06 : 0.04), duration: 0.07))
                actions.append(.wait(forDuration: 0.07))
                actions.append(.run { [weak self, weak gateSprite] in
                    guard let self, let gateSprite else { return }
                    let stroke = self.threadStroke(from: arm.0, to: arm.1, width: gateW * 0.016)
                    stroke.zPosition = 5
                    gateSprite.addChild(stroke)
                    if j == 1 {
                        self.audio.play(.stitch, volume: 0.7)
                        self.audio.chime(step: min(i + 1, 8))
                        self.haptics.spool()
                        self.sparkleBurst(at: gateSprite.convert(center, to: self), count: 6, spread: .pi * 2, speed: 110)
                    }
                })
                needleAt = arm.1
                actions.append(.run { [weak needle] in
                    needle?.run(.move(to: arm.1, duration: 0.06), withKey: "sew")
                })
                actions.append(.wait(forDuration: 0.06))
            }
        }
        // A last flourish: the needle swoops up and away, pulling the thread tight.
        actions.append(travel(to: local(0.75, 1.1), lift: gateH * 0.15, duration: 0.3))
        actions.append(.wait(forDuration: 0.2))
        actions.append(.run { [weak self] in self?.celebrationFlood() })
        actions.append(.run { [weak needle] in
            needle?.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            gate.sprite.run(.sequence([.wait(forDuration: 0.5), .group([.scale(by: 1.15, duration: 0.6), .fadeOut(withDuration: 0.6)])]))
        })
        actions.append(.wait(forDuration: 1.8))
        actions.append(.run { [weak self] in self?.finishRun() })
        run(.sequence(actions), withKey: "celebrate")
    }

    /// One arm of a cross-stitch: gold thread with a darker edge, drawn out from its start like it's being pulled through.
    func threadStroke(from a: CGPoint, to b: CGPoint, width: CGFloat) -> SKNode {
        let node = SKNode()
        node.position = a
        node.zRotation = atan2(b.y - a.y, b.x - a.x)
        let length = hypot(b.x - a.x, b.y - a.y)
        let path = CGMutablePath()
        path.move(to: .zero)
        // A slight sag makes it read as thread, not a ruled line.
        path.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length / 2, y: -width * 0.6))
        let edge = SKShapeNode(path: path)
        edge.strokeColor = UIColor(hex: 0x7A4E0E)
        edge.lineWidth = width * 1.7
        edge.lineCap = .round
        node.addChild(edge)
        let gold = SKShapeNode(path: path)
        gold.strokeColor = Palette.stitchGold
        gold.lineWidth = width
        gold.lineCap = .round
        gold.zPosition = 0.1
        node.addChild(gold)
        let shine = SKShapeNode(path: path)
        shine.strokeColor = UIColor(white: 1, alpha: 0.55)
        shine.lineWidth = width * 0.3
        shine.lineCap = .round
        shine.position = CGPoint(x: 0, y: width * 0.25)
        shine.zPosition = 0.2
        node.addChild(shine)
        node.xScale = 0.05
        node.run(.scaleX(to: 1, duration: 0.06))
        return node
    }

    /// The whole screen floods with color and confetti.
    func celebrationFlood() {
        fullyStitched = true
        audio.play(.stitchFull)
        haptics.success()
        flash.removeAllActions()
        flash.color = .white
        flash.alpha = 0.7 * (Motion.reduced ? Motion.reducedStrength : 1)
        flash.run(.fadeOut(withDuration: 0.6))
        var z = -2.0
        while z < spawnZ {
            for x in [-4.0, 0.0, 4.0] {
                addPatch(x: x + Double.random(in: -1...1), z: z, radius: Double.random(in: 3.5...5.5),
                         withStitch: false, growTime: 0.15 + max(0, z) * 0.01)
            }
            z += 4.5
        }
        for thing in things { colorize(thing) }
        for i in 0..<5 {
            let point = CGPoint(x: size.width * (0.15 + 0.175 * CGFloat(i)), y: size.height * 0.55)
            confettiBurst(at: point)
            sparkleBurst(at: point, count: 20, spread: .pi * 2, speed: 300)
        }
        popText("Stitched!", size: 46, color: Palette.stitchGold, at: CGPoint(x: size.width / 2, y: size.height * 0.62), rise: 30, life: 1.4)
    }

    func stepCelebration(_ dt: Double) {
        celebrationSpeed *= exp(-dt * 2.4)
        runSpeed = celebrationSpeed
        advanceWorld(runSpeed * dt, dt: dt)
        updatePlayerPhysics(dt)
        if laneProgress < 1 {
            laneProgress = min(1, laneProgress + dt / 0.2)
            playerX = laneFromX + (laneToX - laneFromX) * (1 - pow(1 - laneProgress, 2))
        }
    }

    // MARK: Gadgets

    func buildGadgetButton() {
        let radius: CGFloat = 34
        if let base = imageSprite("ui-round") {
            base.size = CGSize(width: radius * 2, height: radius * 2)
            gadgetButton.addChild(base)
        } else {
            let base = SKShapeNode(circleOfRadius: radius)
            base.fillColor = Palette.paper
            base.strokeColor = .white
            base.lineWidth = 4
            gadgetButton.addChild(base)
        }
        gadgetRing.lineWidth = 6
        gadgetRing.strokeColor = Palette.stitchGold
        gadgetRing.lineCap = .round
        gadgetRing.zPosition = 2
        gadgetButton.addChild(gadgetRing)
        gadgetIcon.zPosition = 1
        gadgetButton.addChild(gadgetIcon)
        hud.addChild(gadgetButton)

        shieldRing.path = CGPath(ellipseIn: CGRect(x: -62, y: 0, width: 124, height: 140), transform: nil)
        shieldRing.strokeColor = Palette.stitchGold
        shieldRing.lineWidth = 6
        shieldRing.glowWidth = 4
        shieldRing.fillColor = UIColor(red: 1, green: 0.79, blue: 0.24, alpha: 0.12)
        shieldRing.zPosition = 3
        shieldRing.isHidden = true
        playerNode.addChild(shieldRing)

        planeSprite.zPosition = -1
        planeSprite.isHidden = true
        playerNode.addChild(planeSprite)
    }

    func refreshGadgetButton() {
        gadgetCharge = 0
        gadgetButton.isHidden = gadget == nil
        guard let gadget else { return }
        if let icon = illustrated(gadget.icon, width: 44) {
            gadgetIcon.texture = icon.texture
            gadgetIcon.size = icon.size
        } else {
            let letter = art.text(gadget.letter, size: 28, fill: Palette.stitchGold)
            gadgetIcon.texture = letter.texture
            gadgetIcon.size = letter.size
        }
        if let plane = illustrated("gadget-plane", width: 150) {
            planeSprite.texture = plane.texture
            planeSprite.size = plane.size
        }
        updateGadgetRing()
    }

    var gadgetReady: Bool {
        guard let gadget else { return false }
        return gadgetCharge >= gadget.cost && planeTimer <= 0 && foldTimer <= 0
    }

    func updateGadgetRing() {
        guard let gadget else { return }
        let fraction = min(1, CGFloat(gadgetCharge) / CGFloat(gadget.cost))
        let path = CGMutablePath()
        if fraction > 0.001 {
            path.addArc(center: .zero, radius: 38, startAngle: .pi / 2, endAngle: .pi / 2 - fraction * .pi * 2, clockwise: true)
        }
        gadgetRing.path = path
        gadgetIcon.alpha = gadgetReady ? 1 : 0.45
        if gadgetReady && gadgetButton.action(forKey: "ready") == nil {
            gadgetButton.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.35), .scale(to: 1, duration: 0.35)])), withKey: "ready")
        } else if !gadgetReady {
            gadgetButton.removeAction(forKey: "ready")
            gadgetButton.setScale(1)
        }
    }

    /// Fires the gadget if the touch hit its button. Returns true when the touch was used.
    func tryFireGadget(at point: CGPoint) -> Bool {
        guard gadget != nil, !gadgetButton.isHidden,
              hypot(point.x - gadgetButton.position.x, point.y - gadgetButton.position.y) < 46 else { return false }
        if gadgetReady {
            fireGadget()
        } else {
            haptics.land()
        }
        return true
    }

    func fireGadget() {
        guard let gadget, gadgetReady else { return }
        var used = true
        switch gadget {
        case .shield:
            shieldActive = true
            popText("Stitch Shield!", size: 24, color: Palette.stitchGold, at: playerScreenPoint(offsetY: 140), rise: 30, life: 0.9)
        case .magnet:
            magnetTimer = 6
            popText("Thread Magnet!", size: 24, color: Palette.stitchGold, at: playerScreenPoint(offsetY: 140), rise: 30, life: 0.9)
        case .rewind:
            used = rewindTime()
        case .plane:
            planeTimer = 4
            slideTimer = 0
            popText("Paper Plane!", size: 24, color: .white, at: playerScreenPoint(offsetY: 160), rise: 30, life: 0.9)
        case .ink:
            inkTimer = 4
            popText("Slow Ink...", size: 26, color: UIColor(hex: 0xA792FF), at: playerScreenPoint(offsetY: 140), rise: 20, life: 1.2)
        case .eraser:
            for thing in things where thing.isHazard && !thing.retired && thing.z > -0.4 && thing.z < 32 {
                confettiBurst(at: screenPoint(ofWorld: thing.sprite.position))
                retire(thing)
            }
            shake(strength: 8)
            popText("Erased!", size: 30, color: UIColor(hex: 0xFF8FA3), at: playerScreenPoint(offsetY: 140), rise: 30, life: 0.9)
        case .fold:
            foldTimer = 1.1
            invulnerable = max(invulnerable, 1.5)
            flash.removeAllActions()
            flash.color = Palette.paper
            flash.alpha = 0.55
            flash.run(.fadeOut(withDuration: 0.5))
            popText("Page Fold!", size: 28, color: .white, at: playerScreenPoint(offsetY: 140), rise: 30, life: 0.9)
        }
        guard used else { return }
        gadgetCharge = 0
        audio.play(.closeCall)
        haptics.success()
        updateGadgetRing()
    }

    // MARK: Time Machine

    func makeSnapshot() -> RunSnapshot {
        RunSnapshot(elapsed: elapsed, distance: distance, heartsLeft: heartsLeft, hitsTaken: hitsTaken,
                    spools: spools, streak: streak, bestStreak: bestStreak, closeCalls: closeCalls,
                    meter: meter, stormDistance: stormDistance, playerX: playerX, laneIndex: laneIndex,
                    laneFromX: laneFromX, laneToX: laneToX, laneProgress: laneProgress, playerY: playerY,
                    velocityY: velocityY, nextRowIn: nextRowIn, fullyStitched: fullyStitched,
                    gateSpawned: gateSpawned, rng: rng, powers: powers, shieldActive: shieldActive)
    }

    /// Puts the run back the way it was about 3 seconds ago. Returns false if there isn't enough history yet.
    func rewindTime() -> Bool {
        let targetTime = elapsed - 3
        guard let snap = snapshots.last(where: { $0.elapsed <= targetTime }) ?? snapshots.first,
              distance - snap.distance > 1 else {
            popText("Not yet!", size: 22, color: .white, at: playerScreenPoint(offsetY: 140), rise: 20, life: 0.7)
            return false
        }
        let delta = distance - snap.distance

        // Everything still in the world slides back toward the horizon.
        for thing in things where !thing.retired {
            thing.z += delta
            thing.prevZ = thing.z
            if case .scenery = thing.kind { continue }
            thing.resolved = thing.z <= -0.35
        }
        // Spools you grabbed and hazards you hit come back.
        for dead in graveyard where dead.removedAt > snap.distance {
            dead.z = dead.removedZ + (dead.removedAt - snap.distance)
            dead.prevZ = dead.z
            dead.retired = false
            dead.resolved = false
            if dead.sprite.parent == nil { objectLayer.addChild(dead.sprite) }
            if !things.contains(where: { $0 === dead }) { things.append(dead) }
        }
        graveyard.removeAll { $0.removedAt > snap.distance }
        // Anything that appeared after the snapshot will appear again as you run.
        things.removeAll { thing in
            let isScenery: Bool
            if case .scenery = thing.kind { isScenery = true } else { isScenery = false }
            if (isScenery && thing.z > spawnZ + 1) || (!isScenery && thing.spawnedAt > snap.distance) {
                thing.sprite.removeFromParent()
                return true
            }
            return false
        }
        if !snap.gateSpawned, let gate = gateThing {
            gate.sprite.removeFromParent()
            things.removeAll { $0 === gate }
            gateThing = nil
        }
        if let gate = gateThing, !things.contains(where: { $0 === gate }) { gateThing = nil }
        for patch in patches { patch.z += delta }

        elapsed = snap.elapsed
        lastLaneChange = -10
        distance = snap.distance
        heartsLeft = snap.heartsLeft
        hitsTaken = snap.hitsTaken
        spools = snap.spools
        streak = snap.streak
        bestStreak = snap.bestStreak
        closeCalls = snap.closeCalls
        meter = snap.meter
        stormDistance = snap.stormDistance
        playerX = snap.playerX
        laneIndex = snap.laneIndex
        laneFromX = snap.laneFromX
        laneToX = snap.laneToX
        laneProgress = snap.laneProgress
        playerY = snap.playerY
        velocityY = snap.velocityY
        nextRowIn = snap.nextRowIn
        fullyStitched = snap.fullyStitched
        gateSpawned = snap.gateSpawned
        rng = snap.rng
        powers = snap.powers
        shieldActive = snap.shieldActive
        shieldRing.isHidden = !shieldActive
        snapshots.removeAll { $0.elapsed > snap.elapsed }
        slideTimer = 0
        hitPoseTimer = 0
        invulnerable = 1.2
        timeScale = 0.3
        rewindsThisRun += 1
        shownSpools = -1
        shownSeconds = -1

        // A sepia flash and a reverse whoosh.
        flash.removeAllActions()
        flash.color = UIColor(hex: 0xE8C88A)
        flash.alpha = 0.6
        flash.run(.fadeOut(withDuration: 0.5))
        audio.play(.whoosh)
        popText("Rewind!", size: 34, color: Palette.stitchGold, at: playerScreenPoint(offsetY: 150), rise: 30, life: 1)
        updateHUD()
        refreshPowerRow()
        return true
    }

    /// Takes a spool or hazard out of the world, keeping it for the Time Machine.
    func retire(_ thing: Thing) {
        thing.sprite.removeFromParent()
        thing.resolved = true
        guard !thing.retired else { return }
        thing.retired = true
        thing.removedAt = distance
        thing.removedZ = thing.z
        if gadget == .rewind {
            graveyard.append(thing)
            graveyard.removeAll { distance - $0.removedAt > 70 }
        }
    }

    // MARK: Holiday rival

    func setupRival() {
        rivalSprite.isHidden = true
        rivalLabel.isHidden = true
        guard case .race(let holiday) = mode else { return }
        let back = illustrated("\(holiday.rivalID)-back", width: 100) ?? illustrated("bramble-back", width: 100)
        if let back {
            rivalSprite.texture = back.texture
            rivalSprite.size = CGSize(width: 85, height: 85 * back.size.height / back.size.width)
        }
        rivalSprite.anchorPoint = CGPoint(x: 0.5, y: 0.02)
        let hasArt = artImage("\(holiday.rivalID)-back") != nil
        rivalSprite.color = holiday == .harvest ? UIColor(hex: 0xC2551F) : UIColor(hex: 0x8A5A2B)
        rivalSprite.colorBlendFactor = hasArt ? 0 : 0.55
        rivalSprite.isHidden = false
        rivalLabel.isHidden = false
        rivalX = laneIndex == 1 ? 0 : 1
        rivalTargetX = rivalX
        rivalLaneTimer = 2.5
    }

    func updateRival(_ dt: Double) {
        guard case .race = mode else { return }
        rivalLaneTimer -= dt
        if rivalLaneTimer <= 0 {
            rivalLaneTimer = Double.random(in: 1.8...3.4)
            let options = [-1.0, 0.0, 1.0].filter { abs($0 - laneToX) > 0.5 }
            rivalTargetX = options.randomElement() ?? 1
        }
        rivalX += (rivalTargetX - rivalX) * min(1, dt * 6)
    }

    var rivalCount: Int {
        guard case .race(let holiday) = mode else { return 0 }
        return Int(Double(holiday.rivalTarget) * min(1, elapsed / max(config.length, 1)))
    }

    func renderRival() {
        guard !rivalSprite.isHidden,
              let p = project(x: rivalX, z: 4.2, y: abs(sin(clock * 8.5)) * 0.18) else { return }
        rivalSprite.position = p.point
        rivalSprite.setScale(p.scale)
        rivalSprite.zPosition = CGFloat((spawnZ + 10 - 4.2) * 5)
        rivalSprite.zRotation = CGFloat(sin(clock * 8.5)) * 0.08 + CGFloat(rivalX - rivalTargetX) * 0.3
    }

    // MARK: Holiday themes

    func currentHoliday() -> Holiday? {
        switch tuning.holidayOverride {
        case 1: return nil
        case 2: return .harvest
        case 3: return .snow
        default: return Holiday.active()
        }
    }

    /// The look for a run: a later world wears its own art; Notebook Meadow, Endless and the Daily Storm
    /// wear the holiday look when one is on. Holiday leaves or snow fall over every world.
    func themeFor(_ mode: RunMode?) -> Theme? {
        var raceHoliday: Holiday?
        if case .race(let holiday)? = mode { raceHoliday = holiday }
        let holiday = raceHoliday ?? currentHoliday()
        if case .stage(let index)? = mode, var worldTheme = World.all[World.index(ofStage: index)].theme {
            if let holiday {
                worldTheme.particles = holiday.particles
                worldTheme.holiday = holiday
            }
            return worldTheme
        }
        return holiday?.theme
    }

    /// Switches the world's look (or back to Notebook Meadow's).
    func applyTheme(_ newTheme: Theme?) {
        let changed = newTheme != theme || !themeApplied
        theme = newTheme
        themeApplied = true
        audio.setMusicTheme(newTheme)
        // Menus and every new run start outside a chase; startRun turns one back on.
        audio.setChase(false)
        applyChaseLook(nil)
        guard changed else { return }
        layoutScene()
        for emitter in holidayEmitters { emitter.removeFromParent() }
        holidayEmitters.removeAll()
        guard let holiday = newTheme?.holiday, let particles = newTheme?.particles else { return }
        let harvest = holiday == .harvest
        // The total amount stays the same however many kinds of piece there are.
        let totalRate: CGFloat = harvest ? 4.5 : 11
        for (i, name) in particles.enumerated() {
            let texture: SKTexture
            // Size each piece by its picture's shape so nothing is squashed.
            let base: CGFloat = harvest ? 34 : 22
            var pieceSize = CGSize(width: base, height: base)
            if let image = artImage(name), image.size.height > 0 {
                texture = SKTexture(image: image)
                let aspect = image.size.width / image.size.height
                pieceSize = aspect >= 1 ? CGSize(width: base, height: base / aspect) : CGSize(width: base * aspect, height: base)
            } else {
                texture = harvest ? art.leaf(variant: i).texture : art.puff.texture
            }
            let emitter = SKEmitterNode()
            emitter.particleTexture = texture
            emitter.particleBirthRate = totalRate / CGFloat(max(1, particles.count))
            emitter.particleLifetime = 9
            emitter.particleSize = pieceSize
            emitter.particleScaleRange = 0.5
            // Paper flutters: each piece sways side to side as it falls.
            let sway: CGFloat = harvest ? 26 : 14
            let swayTime = harvest ? 1.1 : 1.5
            let half = SKAction.moveBy(x: sway, y: 0, duration: swayTime)
            half.timingMode = .easeInEaseOut
            let back = SKAction.moveBy(x: -sway, y: 0, duration: swayTime)
            back.timingMode = .easeInEaseOut
            emitter.particleAction = .repeatForever(.sequence([half, back]))
            emitter.particlePositionRange = CGVector(dx: size.width * 1.3, dy: 0)
            emitter.position = CGPoint(x: size.width / 2, y: size.height + 30)
            emitter.emissionAngle = -.pi / 2
            emitter.emissionAngleRange = 0.5
            emitter.particleSpeed = holiday == .harvest ? 90 : 70
            emitter.particleSpeedRange = 40
            emitter.xAcceleration = holiday == .harvest ? -18 : 6
            emitter.particleRotationRange = .pi * 2
            emitter.particleRotationSpeed = holiday == .harvest ? 1.5 : 0.6
            emitter.particleAlpha = 0.95
            // Above the menus too, so leaves and snow drift over the title and map screens.
            emitter.zPosition = 1150
            emitter.advanceSimulationTime(8)
            addChild(emitter)
            holidayEmitters.append(emitter)
        }
    }

    // MARK: Living characters

    /// Breathing and blinking for a front-facing character sprite in menus.
    func bringToLife(_ sprite: SKSpriteNode, id: String) {
        let base = sprite.yScale
        sprite.run(.repeatForever(.sequence([
            .scaleY(to: base * 1.03, duration: 1.1),
            .scaleY(to: base * 0.985, duration: 1.1)
        ])), withKey: "breathe")
        guard let blinkImage = artImage("\(id)-blink"), let open = sprite.texture else { return }
        let closed = SKTexture(image: blinkImage)
        sprite.run(.repeatForever(.sequence([
            .wait(forDuration: 3, withRange: 3),
            .setTexture(closed),
            .wait(forDuration: 0.12),
            .setTexture(open)
        ])), withKey: "blink")
    }

    /// Makes a night-run shade: dark everywhere except a soft circle of lantern light.
    func makeNightShade() -> SKTexture {
        let size = CGSize(width: 512, height: 512)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(hex: 0x0B0820, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.08, 0.32]) {
                context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 256, y: 256), startRadius: 0,
                                                     endCenter: CGPoint(x: 256, y: 256), endRadius: 256,
                                                     options: [.drawsAfterEndLocation])
            }
        }
        return SKTexture(image: image)
    }
}
