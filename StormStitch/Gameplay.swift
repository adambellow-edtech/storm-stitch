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
}

extension RunScene {

    // MARK: Starting a run

    /// The settings for a mode.
    func makeConfig(for mode: RunMode) -> RunConfig {
        switch mode {
        case .stage(let index):
            return Stage.meadow[max(0, min(index, Stage.meadow.count - 1))].config
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

        var raceHoliday: Holiday?
        if case .race(let holiday) = newMode { raceHoliday = holiday }
        applyTheme(raceHoliday ?? currentHoliday())

        resetWorld()
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
        audio.setMusic(playing: true)
        haptics.success()
        velocityY = tuning.jumpVelocity * 0.7
        playerY = 0.0001

        // Opening banner.
        let banner: String
        switch newMode {
        case .stage(let index): banner = "Stage \(index + 1): \(Stage.meadow[index].name)"
        case .daily(let storm): banner = "\(storm.rule.emoji) \(storm.rule.name)"
        case .challenge(let storm, let target, let from): banner = "Beat \(from): \(target.formatted()) \(storm.rule.emoji)"
        case .race(let holiday): banner = "\(holiday.raceName): beat \(holiday.rivalName)!"
        case .endless: banner = "Endless: outrun the storm!"
        }
        popText(banner, size: 24, color: .white, at: CGPoint(x: size.width / 2, y: size.height * 0.66), rise: 20, life: 2.2)
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

        // A golden needle zig-zags across the tear, trailing thread.
        let needleArt = illustrated("needle", width: 150) ?? art.needle
        let needle = SKSpriteNode(texture: needleArt.texture, size: needleArt.size)
        needle.zPosition = 20
        fxRoot.addChild(needle)
        let thread = SKShapeNode()
        thread.strokeColor = Palette.stitchGold
        thread.lineWidth = 6
        thread.lineCap = .round
        thread.glowWidth = 3
        thread.zPosition = 19
        fxRoot.addChild(thread)

        let stitches = 7
        let path = CGMutablePath()
        var actions: [SKAction] = [.wait(forDuration: 0.5)]
        for i in 0...stitches {
            actions.append(.run { [weak self, weak needle, weak thread] in
                guard let self, let needle, let thread else { return }
                let gatePoint = self.screenPoint(ofWorld: gate.sprite.position)
                let height = gate.sprite.size.height
                let topY = gatePoint.y + height * 0.85
                let bottomY = gatePoint.y + height * 0.12
                let y = topY - (topY - bottomY) * CGFloat(i) / CGFloat(stitches)
                let x = gatePoint.x + (i % 2 == 0 ? -1 : 1) * height * 0.13
                let point = CGPoint(x: x, y: y)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                thread.path = path
                needle.position = point
                needle.zRotation = i % 2 == 0 ? -0.6 : 0.6
                self.audio.play(.stitch, volume: 0.7)
                self.audio.chime(step: min(i, 8))
                self.haptics.spool()
                self.sparkleBurst(at: point, count: 8, spread: .pi * 2, speed: 140)
            })
            actions.append(.wait(forDuration: 0.12))
        }
        actions.append(.run { [weak self] in self?.celebrationFlood() })
        actions.append(.run { [weak needle, weak thread] in
            needle?.run(.sequence([.group([.moveBy(x: 260, y: 420, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
            thread?.run(.sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.6), .removeFromParent()]))
            gate.sprite.run(.group([.scale(by: 1.15, duration: 0.6), .fadeOut(withDuration: 0.6)]))
        })
        actions.append(.wait(forDuration: 1.8))
        actions.append(.run { [weak self] in self?.finishRun() })
        run(.sequence(actions), withKey: "celebrate")
    }

    /// The whole screen floods with color and confetti.
    func celebrationFlood() {
        fullyStitched = true
        audio.play(.stitchFull)
        haptics.success()
        flash.removeAllActions()
        flash.color = .white
        flash.alpha = 0.7
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
                    gateSpawned: gateSpawned, rng: rng)
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
        let hasArt = UIImage(named: "\(holiday.rivalID)-back") != nil
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

    /// Switches the world's look for a holiday (or back to normal).
    func applyTheme(_ holiday: Holiday?) {
        let changed = holiday != theme || !themeApplied
        theme = holiday
        themeApplied = true
        guard changed else { return }
        layoutScene()
        for emitter in holidayEmitters { emitter.removeFromParent() }
        holidayEmitters.removeAll()
        guard let holiday else { return }
        for (i, name) in holiday.particles.enumerated() {
            let texture: SKTexture
            if let image = UIImage(named: name) {
                texture = SKTexture(image: image)
            } else {
                texture = holiday == .harvest ? art.leaf(variant: i).texture : art.puff.texture
            }
            let emitter = SKEmitterNode()
            emitter.particleTexture = texture
            emitter.particleBirthRate = holiday == .harvest ? 1.6 : 6
            emitter.particleLifetime = 9
            emitter.particleSize = holiday == .harvest ? CGSize(width: 26, height: 26) : CGSize(width: 18, height: 18)
            emitter.particleScaleRange = 0.5
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
            emitter.zPosition = 650
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
        guard let blinkImage = UIImage(named: "\(id)-blink"), let open = sprite.texture else { return }
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
