import SpriteKit
import UIKit

/// Gray-box run: three lanes, swipe to change lane, tap to jump, swipe down to slide,
/// hazards, spools, and a storm wall that chases you. Drawn with a simple pseudo-3D
/// projection so the camera sits behind the runner, like the hero style frame.
final class RunScene: SKScene {

    // MARK: Types

    enum State { case ready, running, over }

    enum HazardKind: CaseIterable {
        case low       // jump over
        case overhead  // slide under
        case crate     // change lanes
    }

    enum ObjectKind {
        case hazard(HazardKind)
        case spool
    }

    final class WorldObject {
        let node: SKNode
        let kind: ObjectKind
        let lane: Int
        var z: Double
        var prevZ: Double
        let y: Double
        var resolved = false

        init(node: SKNode, kind: ObjectKind, lane: Int, z: Double, y: Double) {
            self.node = node
            self.kind = kind
            self.lane = lane
            self.z = z
            self.prevZ = z
            self.y = y
        }
    }

    // MARK: Config

    private let tuning: Tuning
    private let haptics = Haptics()

    private let camHeight = 1.6
    private let camBack = 3.2
    private let laneWidth = 1.0
    private let spawnZ = 46.0
    private let dashSpacing = 3.0
    private let dashLength = 1.3
    private let dashesPerDivider = 26
    private let landSquashTime = 0.12
    private let jumpBufferTime = 0.12

    private var horizonY: CGFloat = 0
    /// Pixels per world unit at depth 1.
    private var unitK: CGFloat = 0

    // MARK: Nodes

    private let world = SKNode()
    private let staticLayer = SKNode()
    private let objectLayer = SKNode()
    private let hud = SKNode()
    private var dashes: [SKSpriteNode] = []
    private let player = SKShapeNode()
    private let playerShadow = SKShapeNode(ellipseOf: CGSize(width: 84, height: 24))
    private var stormNode = SKShapeNode()
    private let stormWarning = SKSpriteNode(color: UIColor(hex: 0xFF3B30), size: CGSize(width: 10, height: 10))
    private let timerLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let spoolLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var heartLabels: [SKLabelNode] = []
    private let messageNode = SKNode()

    // MARK: Run state

    private var state: State = .ready
    private var objects: [WorldObject] = []
    private var lastUpdate: TimeInterval = 0
    private var overAt: TimeInterval = 0
    private var elapsed = 0.0
    private var distance = 0.0
    private var runSpeed = 0.0
    private var nextRowIn = 0.0
    private var hearts = 3
    private var spools = 0
    private var stormDistance = 6.0
    private var invulnerable = 0.0

    // MARK: Player state

    private var laneIndex = 0
    private var playerX = 0.0
    private var laneFromX = 0.0
    private var laneToX = 0.0
    private var laneProgress = 1.0
    private var playerY = 0.0
    private var velocityY = 0.0
    private var slideTimer = 0.0
    private var landSquash = 0.0
    private var jumpBuffer = 0.0

    // MARK: Touch state

    private var trackedTouch: UITouch?
    private var touchStart = CGPoint.zero
    private var didSwipe = false
    private var lastSwipeDir = 0

    // MARK: Setup

    init(size: CGSize, tuning: Tuning) {
        self.tuning = tuning
        super.init(size: size)
        backgroundColor = Palette.stormGray
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func didMove(to view: SKView) {
        if world.parent == nil {
            addChild(world)
            world.addChild(staticLayer)
            world.addChild(objectLayer)
            addChild(hud)
            hud.zPosition = 1000
            buildPlayer()
            buildHUD()
        }
        layoutScene()
        updateHUD()
        showReady()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard world.parent != nil else { return }
        layoutScene()
    }

    private func buildPlayer() {
        player.path = CGPath(
            roundedRect: CGRect(x: -35, y: 0, width: 70, height: 100),
            cornerWidth: 24, cornerHeight: 24, transform: nil
        )
        player.fillColor = Palette.bramble
        player.strokeColor = .white
        player.lineWidth = 6

        for eyeX in [-14.0, 14.0] {
            let eye = SKShapeNode(circleOfRadius: 11)
            eye.fillColor = .white
            eye.strokeColor = Palette.ink
            eye.lineWidth = 2
            eye.position = CGPoint(x: eyeX, y: 66)
            let pupil = SKShapeNode(circleOfRadius: 5)
            pupil.fillColor = Palette.ink
            pupil.strokeColor = .clear
            pupil.position = CGPoint(x: 1.5, y: 2)
            eye.addChild(pupil)
            player.addChild(eye)
        }

        playerShadow.fillColor = UIColor(white: 0, alpha: 0.22)
        playerShadow.strokeColor = .clear

        objectLayer.addChild(playerShadow)
        objectLayer.addChild(player)
    }

    private func buildHUD() {
        timerLabel.fontSize = 30
        timerLabel.fontColor = .white
        timerLabel.verticalAlignmentMode = .center
        hud.addChild(timerLabel)

        spoolLabel.fontSize = 18
        spoolLabel.fontColor = .white
        spoolLabel.horizontalAlignmentMode = .right
        spoolLabel.verticalAlignmentMode = .center
        hud.addChild(spoolLabel)

        for _ in 0..<3 {
            let heart = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            heart.text = "\u{2665}"
            heart.fontSize = 30
            heart.fontColor = Palette.heart
            heart.horizontalAlignmentMode = .center
            heart.verticalAlignmentMode = .center
            heartLabels.append(heart)
            hud.addChild(heart)
        }

        stormWarning.alpha = 0
        stormWarning.anchorPoint = .zero
        stormWarning.zPosition = -1
        hud.addChild(stormWarning)

        hud.addChild(messageNode)
    }

    private func layoutScene() {
        guard size.width > 10, size.height > 10 else { return }

        horizonY = size.height * 0.64
        unitK = min(size.width, size.height * 0.56) * 0.92

        staticLayer.removeAllChildren()
        dashes.removeAll()

        let sky = SKSpriteNode(color: Palette.stormGray, size: CGSize(width: size.width, height: size.height - horizonY))
        sky.anchorPoint = CGPoint(x: 0.5, y: 0)
        sky.position = CGPoint(x: size.width / 2, y: horizonY)
        sky.zPosition = -100
        staticLayer.addChild(sky)

        let ground = SKSpriteNode(color: UIColor(hex: 0x8A8C99), size: CGSize(width: size.width, height: horizonY))
        ground.anchorPoint = CGPoint(x: 0.5, y: 0)
        ground.position = CGPoint(x: size.width / 2, y: 0)
        ground.zPosition = -100
        staticLayer.addChild(ground)

        let edge = laneWidth * 1.5
        if let nearLeft = project(x: -edge, z: -2.6),
           let nearRight = project(x: edge, z: -2.6),
           let farRight = project(x: edge, z: 90),
           let farLeft = project(x: -edge, z: 90) {
            let roadPath = CGMutablePath()
            roadPath.move(to: nearLeft.point)
            roadPath.addLine(to: nearRight.point)
            roadPath.addLine(to: farRight.point)
            roadPath.addLine(to: farLeft.point)
            roadPath.closeSubpath()
            let road = SKShapeNode(path: roadPath)
            road.fillColor = UIColor(hex: 0xD2D4DB)
            road.strokeColor = .white
            road.lineWidth = 5
            road.zPosition = -90
            staticLayer.addChild(road)
        }

        for _ in 0..<(dashesPerDivider * 2) {
            let dash = SKSpriteNode(color: UIColor(white: 1, alpha: 0.85), size: CGSize(width: 2, height: 2))
            dash.zPosition = -80
            staticLayer.addChild(dash)
            dashes.append(dash)
        }

        stormNode.removeFromParent()
        stormNode = makeStormShape(width: size.width)
        stormNode.position = .zero
        stormNode.zPosition = 500
        world.addChild(stormNode)

        stormWarning.size = size

        let topInset = max(view?.safeAreaInsets.top ?? 0, 20)
        let top = size.height - topInset - 30
        timerLabel.position = CGPoint(x: size.width / 2, y: top)
        for (i, heart) in heartLabels.enumerated() {
            heart.position = CGPoint(x: size.width - 30 - CGFloat(2 - i) * 32, y: top)
        }
        spoolLabel.position = CGPoint(x: size.width - 16, y: top - 36)
        messageNode.position = CGPoint(x: size.width / 2, y: size.height * 0.52)

        render()
    }

    private func makeStormShape(width: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -20, y: 0))
        var x: CGFloat = -20
        var up = true
        while x < width + 20 {
            path.addLine(to: CGPoint(x: x, y: up ? 108 : 88))
            up.toggle()
            x += 26
        }
        path.addLine(to: CGPoint(x: width + 20, y: 96))
        path.addLine(to: CGPoint(x: width + 20, y: 0))
        path.closeSubpath()
        let shape = SKShapeNode(path: path)
        shape.fillColor = UIColor(hex: 0x33353F, alpha: 0.96)
        shape.strokeColor = UIColor(white: 1, alpha: 0.35)
        shape.lineWidth = 3
        return shape
    }

    // MARK: Projection

    /// Projects a world point to the screen. Returns nil when the point is behind the camera.
    /// `scale` is the node scale for art drawn at 100 points per world unit.
    private func project(x: Double, z: Double, y: Double = 0) -> (point: CGPoint, scale: CGFloat)? {
        let depth = z + camBack
        guard depth > 0.25 else { return nil }
        let s = CGFloat(1.0 / depth)
        let px = size.width / 2 + CGFloat(x) * s * unitK
        let py = horizonY - CGFloat(camHeight - y) * s * unitK
        return (CGPoint(x: px, y: py), s * unitK / 100)
    }

    // MARK: Run flow

    private func startRun() {
        for obj in objects { obj.node.removeFromParent() }
        objects.removeAll()
        messageNode.removeAllChildren()
        world.removeAction(forKey: "shake")
        world.position = .zero

        state = .running
        elapsed = 0
        distance = 0
        runSpeed = tuning.startSpeed
        nextRowIn = 12
        hearts = 3
        spools = 0
        stormDistance = tuning.stormStart
        invulnerable = 0

        laneIndex = 0
        playerX = 0
        laneFromX = 0
        laneToX = 0
        laneProgress = 1
        playerY = 0
        velocityY = 0
        slideTimer = 0
        landSquash = 0
        jumpBuffer = 0
        trackedTouch = nil

        haptics.enabled = tuning.hapticsOn
        updateHUD()
    }

    private func endRun(caught: Bool) {
        state = .over
        overAt = lastUpdate
        haptics.gameOver()
        showMessage(
            title: caught ? "Caught by the storm!" : "Out of hearts!",
            lines: resultLines(),
            prompt: "Tap to run again"
        )
    }

    private func finishRun() {
        state = .over
        overAt = lastUpdate
        haptics.success()
        showMessage(
            title: "Run complete!",
            lines: resultLines() + ["The boss chase starts here in step 2."],
            prompt: "Tap to run again"
        )
    }

    private func resultLines() -> [String] {
        let seconds = Int(elapsed.rounded(.down))
        return [
            "\(spools) spools  \u{00B7}  \(Int(distance)) m  \u{00B7}  \(seconds / 60):\(String(format: "%02d", seconds % 60))"
        ]
    }

    private func showReady() {
        showMessage(
            title: "STORM STITCH",
            lines: [
                "Gray-box prototype",
                "Swipe left or right: change lane",
                "Tap: jump  \u{00B7}  Swipe down: slide",
                "Swipe down in the air: slam"
            ],
            prompt: "Tap to run"
        )
    }

    private func showMessage(title: String, lines: [String], prompt: String) {
        messageNode.removeAllChildren()

        let width = min(size.width - 40, 360)
        let height = CGFloat(120 + lines.count * 26)
        let panel = SKShapeNode(
            rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
            cornerRadius: 22
        )
        panel.fillColor = Palette.paper
        panel.strokeColor = .white
        panel.lineWidth = 5
        messageNode.addChild(panel)

        let shadow = SKShapeNode(
            rect: CGRect(x: -width / 2, y: -height / 2 - 7, width: width, height: height),
            cornerRadius: 22
        )
        shadow.fillColor = UIColor(white: 0, alpha: 0.25)
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        messageNode.addChild(shadow)

        var y = height / 2 - 40
        let titleLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        titleLabel.text = title
        titleLabel.fontSize = 26
        titleLabel.fontColor = Palette.ink
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: 0, y: y)
        messageNode.addChild(titleLabel)
        y -= 38

        for line in lines {
            let label = SKLabelNode(fontNamed: "AvenirNext-Medium")
            label.text = line
            label.fontSize = 16
            label.fontColor = Palette.stormDark
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: y)
            messageNode.addChild(label)
            y -= 26
        }

        let promptLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        promptLabel.text = prompt
        promptLabel.fontSize = 20
        promptLabel.fontColor = Palette.goldDark
        promptLabel.verticalAlignmentMode = .center
        promptLabel.position = CGPoint(x: 0, y: -height / 2 + 30)
        promptLabel.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.45, duration: 0.6),
            .fadeAlpha(to: 1, duration: 0.6)
        ])))
        messageNode.addChild(promptLabel)
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 30.0)
        lastUpdate = currentTime
        haptics.enabled = tuning.hapticsOn
        if state == .running {
            step(dt)
        }
        render()
    }

    private func step(_ dt: Double) {
        elapsed += dt
        let t = min(elapsed / max(tuning.runLength, 1), 1)
        runSpeed = lerp(tuning.startSpeed, tuning.endSpeed, t)
        let move = runSpeed * dt
        distance += move

        for obj in objects {
            obj.prevZ = obj.z
            obj.z -= move
        }

        nextRowIn -= move
        if nextRowIn <= 0 {
            spawnRow(atZ: spawnZ + nextRowIn)
            let interval = lerp(tuning.rowIntervalStart, tuning.rowIntervalEnd, t)
            nextRowIn += max(runSpeed * interval, 4.5)
        }

        if laneProgress < 1 {
            laneProgress = min(1, laneProgress + dt / max(tuning.laneSwitchTime, 0.01))
            let eased = 1 - pow(1 - laneProgress, 2)
            playerX = laneFromX + (laneToX - laneFromX) * eased
        }

        if playerY > 0 || velocityY > 0 {
            let g = velocityY < 0 ? tuning.gravity * tuning.fallMultiplier : tuning.gravity
            velocityY -= g * dt
            playerY += velocityY * dt
            if playerY <= 0 {
                playerY = 0
                velocityY = 0
                landed()
            }
        }

        if slideTimer > 0 { slideTimer -= dt }
        if invulnerable > 0 { invulnerable -= dt }
        if landSquash > 0 { landSquash -= dt }
        if jumpBuffer > 0 { jumpBuffer -= dt }

        checkCollisions()
        guard state == .running else { return }

        objects.removeAll { obj in
            if obj.z < -3 {
                obj.node.removeFromParent()
                return true
            }
            return false
        }

        stormDistance = min(tuning.stormStart, stormDistance + tuning.stormRecoverRate * dt)
        if stormDistance <= 0 {
            endRun(caught: true)
            return
        }

        if elapsed >= tuning.runLength {
            finishRun()
            return
        }

        updateHUD()
    }

    // MARK: Spawning

    private func spawnRow(atZ z: Double) {
        let t = elapsed / max(tuning.runLength, 1)
        var lanes = [-1, 0, 1].shuffled()
        let freeLane = lanes.removeFirst()
        let hazardCount = (t > 0.3 && Double.random(in: 0...1) < 0.5) ? 2 : 1
        let allowed: [HazardKind] = elapsed < 15 ? [.low, .crate] : HazardKind.allCases

        var lowLane: Int?
        for i in 0..<hazardCount {
            let kind = allowed.randomElement() ?? .low
            addObject(.hazard(kind), lane: lanes[i], z: z, y: 0)
            if kind == .low { lowLane = lanes[i] }
        }

        let roll = Double.random(in: 0...1)
        if let lowLane, roll < 0.35 {
            // An arc of spools over a low hazard rewards the jump.
            let offsets = [-2.4, -1.2, 0.0, 1.2, 2.4]
            let heights = [0.5, 0.95, 1.2, 0.95, 0.5]
            for i in 0..<offsets.count {
                addObject(.spool, lane: lowLane, z: z + offsets[i], y: heights[i])
            }
        } else if roll < 0.8 {
            for i in 0..<5 {
                addObject(.spool, lane: freeLane, z: z + Double(i) * 1.2, y: 0.4)
            }
        }
    }

    private func addObject(_ kind: ObjectKind, lane: Int, z: Double, y: Double) {
        let node = makeNode(for: kind)
        node.alpha = 0
        objectLayer.addChild(node)
        objects.append(WorldObject(node: node, kind: kind, lane: lane, z: z, y: y))
    }

    /// Art is drawn at 100 points per world unit, with y = 0 on the ground.
    private func makeNode(for kind: ObjectKind) -> SKNode {
        switch kind {
        case .hazard(.low):
            let block = SKShapeNode(rect: CGRect(x: -45, y: 0, width: 90, height: 50), cornerRadius: 8)
            block.fillColor = UIColor(hex: 0xE6E7EB)
            block.strokeColor = Palette.stormDark
            block.lineWidth = 5
            return block

        case .hazard(.overhead):
            let container = SKNode()
            for postX in [-50.0, 42.0] {
                let post = SKShapeNode(rect: CGRect(x: postX, y: 0, width: 8, height: 90))
                post.fillColor = UIColor(hex: 0x6B6E7D)
                post.strokeColor = .clear
                container.addChild(post)
            }
            let bar = SKShapeNode(rect: CGRect(x: -52, y: 85, width: 104, height: 90), cornerRadius: 8)
            bar.fillColor = UIColor(hex: 0x8A8C99)
            bar.strokeColor = Palette.stormDark
            bar.lineWidth = 5
            container.addChild(bar)
            return container

        case .hazard(.crate):
            let crate = SKShapeNode(rect: CGRect(x: -45, y: 0, width: 90, height: 140), cornerRadius: 6)
            crate.fillColor = Palette.stormDark
            crate.strokeColor = UIColor(hex: 0x33353F)
            crate.lineWidth = 5
            let cross = CGMutablePath()
            cross.move(to: CGPoint(x: -38, y: 8))
            cross.addLine(to: CGPoint(x: 38, y: 132))
            cross.move(to: CGPoint(x: 38, y: 8))
            cross.addLine(to: CGPoint(x: -38, y: 132))
            let lines = SKShapeNode(path: cross)
            lines.strokeColor = UIColor(white: 1, alpha: 0.3)
            lines.lineWidth = 5
            crate.addChild(lines)
            return crate

        case .spool:
            let spool = SKShapeNode(circleOfRadius: 20)
            spool.fillColor = Palette.stitchGold
            spool.strokeColor = .white
            spool.lineWidth = 5
            let core = SKShapeNode(circleOfRadius: 8)
            core.fillColor = Palette.goldDark
            core.strokeColor = .clear
            spool.addChild(core)
            return spool
        }
    }

    // MARK: Collisions

    private func checkCollisions() {
        let playerTop = playerY + (slideTimer > 0 ? 0.45 : 1.0)

        for obj in objects where !obj.resolved {
            // Test the span covered this frame, so fast speeds can't skip a hazard.
            let crossed = obj.prevZ >= -0.35 && obj.z < 0.35
            if obj.z <= -0.35 && !crossed {
                obj.resolved = true
                continue
            }
            guard crossed else { continue }
            if obj.z <= -0.35 { obj.resolved = true }

            let objX = Double(obj.lane) * laneWidth
            guard abs(objX - playerX) < 0.55 else { continue }

            switch obj.kind {
            case .spool:
                if abs((playerY + 0.5) - obj.y) < 0.5 {
                    collect(obj)
                }
            case .hazard(let hazard):
                let hit: Bool
                switch hazard {
                case .low: hit = playerY < 0.5
                case .overhead: hit = playerTop > 0.85
                case .crate: hit = playerY < 1.4
                }
                if hit {
                    obj.resolved = true
                    takeHit()
                    if state != .running { return }
                }
            }
        }
    }

    private func collect(_ obj: WorldObject) {
        obj.resolved = true
        obj.node.removeFromParent()
        spools += 1
        haptics.spool()
    }

    private func takeHit() {
        guard invulnerable <= 0 else { return }
        hearts -= 1
        invulnerable = 1.2
        stormDistance -= tuning.stormHitPenalty
        haptics.hit()
        shake()
        updateHUD()
        if hearts <= 0 {
            endRun(caught: false)
        } else if stormDistance <= 0 {
            endRun(caught: true)
        }
    }

    private func shake() {
        world.removeAction(forKey: "shake")
        world.position = .zero
        let shake = SKAction.sequence([
            .moveBy(x: 12, y: 0, duration: 0.03),
            .moveBy(x: -24, y: 0, duration: 0.05),
            .moveBy(x: 18, y: 0, duration: 0.04),
            .moveBy(x: -6, y: 0, duration: 0.03)
        ])
        world.run(shake, withKey: "shake")
    }

    // MARK: Actions

    private func moveLane(_ direction: Int) {
        let newLane = max(-1, min(1, laneIndex + direction))
        guard newLane != laneIndex else { return }
        laneIndex = newLane
        laneFromX = playerX
        laneToX = Double(newLane) * laneWidth
        laneProgress = 0
        haptics.lane()
    }

    private func jump() {
        guard playerY <= 0.0001 && velocityY <= 0 else {
            // Remember an early tap so it fires the moment you land.
            jumpBuffer = jumpBufferTime
            return
        }
        slideTimer = 0
        velocityY = tuning.jumpVelocity
        playerY = 0.0001
        haptics.jump()
    }

    private func swipeDown() {
        if playerY > 0.0001 {
            velocityY = -tuning.jumpVelocity * 1.6
        } else {
            slideTimer = tuning.slideDuration
        }
    }

    private func landed() {
        landSquash = landSquashTime
        haptics.land()
        if jumpBuffer > 0 {
            jumpBuffer = 0
            jump()
        }
    }

    // MARK: Touch input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackedTouch == nil, let touch = touches.first else { return }

        if state != .running {
            if state == .ready || lastUpdate - overAt > 0.6 {
                startRun()
            }
            return
        }

        trackedTouch = touch
        touchStart = touch.location(in: self)
        didSwipe = false
        lastSwipeDir = 0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .running, let tracked = trackedTouch, touches.contains(tracked) else { return }
        let point = tracked.location(in: self)
        let dx = point.x - touchStart.x
        let dy = point.y - touchStart.y
        guard max(abs(dx), abs(dy)) >= CGFloat(tuning.swipeThreshold) else { return }

        didSwipe = true
        touchStart = point  // allows chained swipes without lifting the finger
        if abs(dx) > abs(dy) {
            // One lane per flick; reversing direction mid-touch moves back.
            let dir = dx > 0 ? 1 : -1
            if dir != lastSwipeDir {
                moveLane(dir)
                lastSwipeDir = dir
            }
        } else if dy > 0 {
            jump()
        } else {
            swipeDown()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked = trackedTouch, touches.contains(tracked) else { return }
        if state == .running && !didSwipe {
            jump()
        }
        trackedTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        trackedTouch = nil
    }

    // MARK: Rendering

    private func render() {
        guard unitK > 0, dashes.count == dashesPerDivider * 2 else { return }

        let offset = distance.truncatingRemainder(dividingBy: dashSpacing)
        var index = 0
        for divider in [-0.5, 0.5] {
            for k in 0..<dashesPerDivider {
                let dash = dashes[index]
                index += 1
                let z0 = -3 + Double(k) * dashSpacing - offset
                guard let a = project(x: divider * laneWidth, z: z0),
                      let b = project(x: divider * laneWidth, z: z0 + dashLength) else {
                    dash.isHidden = true
                    continue
                }
                dash.isHidden = false
                let dx = b.point.x - a.point.x
                let dy = b.point.y - a.point.y
                dash.position = CGPoint(x: (a.point.x + b.point.x) / 2, y: (a.point.y + b.point.y) / 2)
                dash.size = CGSize(width: max(1.5, 7 * (a.scale + b.scale) / 2), height: hypot(dx, dy))
                dash.zRotation = atan2(dy, dx) - .pi / 2
            }
        }

        for obj in objects {
            guard let p = project(x: Double(obj.lane) * laneWidth, z: obj.z, y: obj.y) else {
                obj.node.isHidden = true
                continue
            }
            obj.node.isHidden = false
            obj.node.position = p.point
            obj.node.setScale(p.scale)
            obj.node.zPosition = CGFloat(-obj.z)
            obj.node.alpha = CGFloat(max(0, min(1, (spawnZ + 2 - obj.z) / 6)))
        }

        if let ground = project(x: playerX, z: 0),
           let body = project(x: playerX, z: 0, y: playerY) {
            playerShadow.position = ground.point
            playerShadow.setScale(ground.scale * CGFloat(max(0.4, 1 - playerY * 0.35)))
            playerShadow.zPosition = 0.05

            player.position = body.point
            var xScale = body.scale
            var yScale = body.scale
            if slideTimer > 0 {
                yScale *= 0.45
                xScale *= 1.2
            } else if landSquash > 0 {
                let amount = CGFloat(landSquash / landSquashTime)
                yScale *= 1 - 0.22 * amount
                xScale *= 1 + 0.15 * amount
            } else if playerY > 0 {
                yScale *= 1.08
                xScale *= 0.94
            }
            player.xScale = xScale
            player.yScale = yScale
            player.zPosition = 0.2
            player.zRotation = CGFloat((laneToX - playerX) * -0.3)
            if invulnerable > 0 {
                player.alpha = Int(invulnerable * 12) % 2 == 0 ? 0.35 : 1
            } else {
                player.alpha = 1
            }
        }

        let closeness = 1 - max(0, min(1, stormDistance / max(tuning.stormStart, 0.1)))
        stormNode.yScale = CGFloat(0.2 + closeness * 2.6)

        if state == .running && stormDistance < 2 {
            stormWarning.alpha = CGFloat(0.12 + 0.08 * sin(elapsed * 12))
        } else {
            stormWarning.alpha = 0
        }
    }

    private func updateHUD() {
        let remaining = max(0, Int((tuning.runLength - elapsed).rounded(.up)))
        timerLabel.text = "\(remaining / 60):\(String(format: "%02d", remaining % 60))"
        spoolLabel.text = "\(spools) spools"
        for (i, heart) in heartLabels.enumerated() {
            heart.alpha = i < hearts ? 1 : 0.25
        }
    }
}
