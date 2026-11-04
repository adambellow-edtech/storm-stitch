import SpriteKit
import UIKit

/// Storm Stitch vertical slice: Notebook Meadow with Bramble.
/// The world starts gray and torn. Every spool you grab stitches color back in
/// around you, and the storm chases from behind. Drawn with a simple pseudo-3D
/// projection so the camera sits behind the runner, like the hero style frame.
final class RunScene: SKScene {

    // MARK: Types

    enum State { case title, running, over }

    enum HazardKind: CaseIterable {
        case low       // eraser: jump over
        case overhead  // ruler: slide under
        case crate     // box: change lanes
    }

    enum SceneryKind { case tree, bush, flower }

    final class Thing {
        enum Kind {
            case hazard(HazardKind)
            case spool
            case scenery(SceneryKind, variant: Int)
        }

        let kind: Kind
        let sprite: SKSpriteNode
        let worldScale: CGFloat
        var x: Double
        var z: Double
        var prevZ: Double
        var y: Double
        var resolved = false
        var colored = false
        var popTime = -1.0
        let phase = Double.random(in: 0..<6.28)

        init(kind: Kind, sprite: SKSpriteNode, worldScale: CGFloat, x: Double, z: Double, y: Double) {
            self.kind = kind
            self.sprite = sprite
            self.worldScale = worldScale
            self.x = x
            self.z = z
            self.prevZ = z
            self.y = y
        }

        var isHazard: Bool {
            if case .hazard = kind { return true }
            return false
        }
    }

    final class Patch {
        let mask: SKSpriteNode
        let stitch: SKSpriteNode?
        let x: Double
        var z: Double
        let radius: Double
        var age = 0.0
        let growTime: Double

        init(mask: SKSpriteNode, stitch: SKSpriteNode?, x: Double, z: Double, radius: Double, growTime: Double) {
            self.mask = mask
            self.stitch = stitch
            self.x = x
            self.z = z
            self.radius = radius
            self.growTime = growTime
        }
    }

    // MARK: Config

    private let tuning: Tuning
    private let haptics = Haptics()
    private let audio = GameAudio.shared
    private let art = PaperArt.shared

    private let camHeight = 1.6
    private let camBack = 3.2
    private let laneWidth = 1.0
    private let spawnZ = 46.0
    private let dashSpacing = 3.0
    private let dashLength = 1.3
    private let dashesPerDivider = 26
    private let rigBaseScale: CGFloat = 0.75
    private let landSquashTime = 0.14
    private let jumpBufferTime = 0.12
    private let titleSpeed = 4.0

    private var horizonY: CGFloat = 0
    private var unitK: CGFloat = 0

    // MARK: Nodes

    private let camRig = SKNode()
    private let worldRoot = SKNode()
    private let skyGray = SKSpriteNode(color: Palette.stormGray, size: CGSize(width: 10, height: 10))
    private let skyBlue = SKSpriteNode(color: UIColor(hex: 0x8FD3FF), size: CGSize(width: 10, height: 10))
    private var sunSprite = SKSpriteNode()
    private var cloudSprites: [SKSpriteNode] = []
    private var hillsGray = SKSpriteNode()
    private var hillsColor = SKSpriteNode()
    private let groundLayer = SKNode()
    private let colorCrop = SKCropNode()
    private let maskRoot = SKNode()
    private let colorLayer = SKNode()
    private let stitchLayer = SKNode()
    private let dashLayer = SKNode()
    private let objectLayer = SKNode()
    private var dashes: [SKSpriteNode] = []

    private let playerNode = SKNode()
    private let rig = SKNode()
    private var body = SKSpriteNode()
    private var eyes = SKSpriteNode()
    private var armL = SKSpriteNode()
    private var armR = SKSpriteNode()
    private var footL = SKSpriteNode()
    private var footR = SKSpriteNode()
    private var playerShadow = SKSpriteNode()

    private let stormRoot = SKNode()
    private var stormBack = SKSpriteNode()
    private var stormFront = SKSpriteNode()
    private var stormEyes: [SKSpriteNode] = []
    private var stormScraps: SKEmitterNode?

    private let fxRoot = SKNode()
    private let hud = SKNode()
    private let flash = SKSpriteNode(color: .white, size: CGSize(width: 10, height: 10))
    private let vignette = SKSpriteNode(color: UIColor(hex: 0xFF3B30), size: CGSize(width: 10, height: 10))
    private var timerSprite = SKSpriteNode()
    private var spoolIcon = SKSpriteNode()
    private var spoolCountSprite = SKSpriteNode()
    private var hearts: [SKSpriteNode] = []
    private let meterBack = SKShapeNode()
    private let meterFill = SKSpriteNode(color: Palette.stitchGold, size: CGSize(width: 10, height: 10))
    private var meterLabel = SKSpriteNode()
    private var meterWidth: CGFloat = 180
    private let overlay = SKNode()

    // MARK: Run state

    private var state: State = .title
    private var things: [Thing] = []
    private var patches: [Patch] = []
    private var lastUpdate: TimeInterval = 0
    private var overAt = 0.0
    private var clock = 0.0
    private var elapsed = 0.0
    private var distance = 0.0
    private var runSpeed = 0.0
    private var nextRowIn = 0.0
    private var nextSceneryIn = 0.0
    private var nextPatchIn = 0.0
    private var heartsLeft = 3
    private var hitsTaken = 0
    private var spools = 0
    private var streak = 0
    private var bestStreak = 0
    private var streakTimer = 0.0
    private var meter = 0.0
    private var fullyStitched = false
    private var stormDistance = 6.0
    private var invulnerable = 0.0
    private var timeScale = 1.0
    private var hitStop = 0.0
    private var shownSeconds = -1
    private var shownSpools = -1
    private var nextThunder = 6.0

    // MARK: Player state

    private var laneIndex = 0
    private var playerX = 0.0
    private var laneFromX = 0.0
    private var laneToX = 0.0
    private var laneProgress = 1.0
    private var lastLaneChange = -10.0
    private var lastLaneFrom = 0
    private var playerY = 0.0
    private var velocityY = 0.0
    private var slideTimer = 0.0
    private var landSquash = 0.0
    private var jumpBuffer = 0.0
    private var runPhase = 0.0
    private var blinkTimer = 2.0

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
        if camRig.parent == nil {
            buildNodeTree()
            buildPlayer()
            buildStorm()
            buildHUD()
            audio.start()
        }
        layoutScene()
        if size.width > 10 && size.height > 10 { showTitle() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard camRig.parent != nil, size.width > 10, size.height > 10 else { return }
        layoutScene()
        if state == .title { showTitle() }
    }

    private func buildNodeTree() {
        addChild(camRig)
        camRig.addChild(worldRoot)

        skyGray.anchorPoint = CGPoint(x: 0.5, y: 0)
        skyGray.zPosition = -200
        worldRoot.addChild(skyGray)
        skyBlue.anchorPoint = CGPoint(x: 0.5, y: 0)
        skyBlue.zPosition = -199
        skyBlue.alpha = 0
        worldRoot.addChild(skyBlue)

        let sunArt = art.sun
        sunSprite = SKSpriteNode(texture: sunArt.texture, size: sunArt.size)
        sunSprite.zPosition = -198
        sunSprite.alpha = 0
        worldRoot.addChild(sunSprite)

        let cloudArt = art.cloud
        for _ in 0..<3 {
            let cloud = SKSpriteNode(texture: cloudArt.texture, size: cloudArt.size)
            cloud.zPosition = -197
            cloud.alpha = 0
            worldRoot.addChild(cloud)
            cloudSprites.append(cloud)
        }

        let grayHills = art.hills(colored: false)
        hillsGray = SKSpriteNode(texture: grayHills.texture, size: grayHills.size)
        hillsGray.anchorPoint = CGPoint(x: 0.5, y: 0)
        hillsGray.zPosition = -196
        worldRoot.addChild(hillsGray)
        let colorHills = art.hills(colored: true)
        hillsColor = SKSpriteNode(texture: colorHills.texture, size: colorHills.size)
        hillsColor.anchorPoint = CGPoint(x: 0.5, y: 0)
        hillsColor.zPosition = -195
        hillsColor.alpha = 0
        worldRoot.addChild(hillsColor)

        groundLayer.zPosition = -150
        worldRoot.addChild(groundLayer)

        colorCrop.maskNode = maskRoot
        colorCrop.zPosition = -140
        colorCrop.addChild(colorLayer)
        worldRoot.addChild(colorCrop)

        stitchLayer.zPosition = -130
        worldRoot.addChild(stitchLayer)
        dashLayer.zPosition = -120
        worldRoot.addChild(dashLayer)
        objectLayer.zPosition = 0
        worldRoot.addChild(objectLayer)

        stormRoot.zPosition = 500
        addChild(stormRoot)
        fxRoot.zPosition = 600
        addChild(fxRoot)

        vignette.alpha = 0
        vignette.anchorPoint = .zero
        vignette.zPosition = 700
        addChild(vignette)
        flash.alpha = 0
        flash.anchorPoint = .zero
        flash.zPosition = 950
        addChild(flash)

        hud.zPosition = 1000
        addChild(hud)
        overlay.zPosition = 1100
        addChild(overlay)
    }

    private func buildPlayer() {
        let shadowArt = art.shadow
        playerShadow = SKSpriteNode(texture: shadowArt.texture, size: shadowArt.size)
        objectLayer.addChild(playerShadow)

        let bodyArt = art.brambleBody
        body = SKSpriteNode(texture: bodyArt.texture, size: bodyArt.size)
        body.anchorPoint = CGPoint(x: 0.5, y: 10.0 / 180.0)
        body.position = CGPoint(x: 0, y: 13)

        let eyeArt = art.brambleEyes(closed: false)
        eyes = SKSpriteNode(texture: eyeArt.texture, size: eyeArt.size)
        eyes.position = CGPoint(x: 2, y: 69)
        eyes.zPosition = 1

        let armArt = art.brambleArm
        armL = SKSpriteNode(texture: armArt.texture, size: armArt.size)
        armL.anchorPoint = CGPoint(x: 0.5, y: 0.82)
        armL.position = CGPoint(x: -58, y: 64)
        armL.zPosition = -1
        armR = SKSpriteNode(texture: armArt.texture, size: armArt.size)
        armR.anchorPoint = CGPoint(x: 0.5, y: 0.82)
        armR.position = CGPoint(x: 60, y: 64)
        armR.zPosition = -1

        let footArt = art.brambleFoot
        footL = SKSpriteNode(texture: footArt.texture, size: footArt.size)
        footL.position = CGPoint(x: -23, y: 12)
        footL.zPosition = -2
        footR = SKSpriteNode(texture: footArt.texture, size: footArt.size)
        footR.position = CGPoint(x: 23, y: 12)
        footR.zPosition = -2

        for part in [footL, footR, armL, armR, body, eyes] {
            rig.addChild(part)
        }
        rig.setScale(rigBaseScale)
        playerNode.addChild(rig)
        objectLayer.addChild(playerNode)
    }

    private func buildStorm() {
        let wall = art.stormWall
        stormBack = SKSpriteNode(texture: wall.texture, size: wall.size)
        stormBack.anchorPoint = CGPoint(x: 0.5, y: 1)
        stormBack.color = Palette.ink
        stormBack.colorBlendFactor = 0.35
        stormRoot.addChild(stormBack)

        stormFront = SKSpriteNode(texture: wall.texture, size: wall.size)
        stormFront.anchorPoint = CGPoint(x: 0.5, y: 1)
        stormFront.xScale = -1
        stormRoot.addChild(stormFront)

        let eyeArt = art.stormEye
        for side in [-1.0, 1.0] {
            let eye = SKSpriteNode(texture: eyeArt.texture, size: eyeArt.size)
            eye.xScale = CGFloat(side) * -1
            eye.zPosition = 2
            stormRoot.addChild(eye)
            stormEyes.append(eye)
        }

        let scraps = SKEmitterNode()
        scraps.particleTexture = art.scrap.texture
        scraps.particleBirthRate = 0
        scraps.particleLifetime = 1.6
        scraps.particleLifetimeRange = 0.6
        scraps.emissionAngle = .pi / 2
        scraps.emissionAngleRange = 0.9
        scraps.particleSpeed = 260
        scraps.particleSpeedRange = 120
        scraps.yAcceleration = -260
        scraps.particleRotationRange = .pi * 2
        scraps.particleRotationSpeed = 6
        scraps.particleScale = 1.2
        scraps.particleScaleRange = 0.6
        scraps.particleAlphaSpeed = -0.5
        scraps.particleColor = UIColor(hex: 0xD2D4DB)
        scraps.particleColorBlendFactor = 1
        scraps.zPosition = 1
        stormRoot.addChild(scraps)
        stormScraps = scraps
    }

    private func buildHUD() {
        for _ in 0..<3 {
            let heartArt = art.heart(full: true)
            let heart = SKSpriteNode(texture: heartArt.texture, size: CGSize(width: 36, height: 35))
            hud.addChild(heart)
            hearts.append(heart)
        }

        let spoolArt = art.spool
        spoolIcon = SKSpriteNode(texture: spoolArt.texture, size: CGSize(width: 28, height: 30))
        hud.addChild(spoolIcon)
        spoolCountSprite.anchorPoint = CGPoint(x: 1, y: 0.5)
        hud.addChild(spoolCountSprite)
        timerSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        hud.addChild(timerSprite)

        meterBack.fillColor = UIColor(white: 1, alpha: 0.9)
        meterBack.strokeColor = Palette.ink
        meterBack.lineWidth = 3
        hud.addChild(meterBack)
        meterFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        meterFill.zPosition = 1
        hud.addChild(meterFill)
        let label = art.text("STITCH", size: 13, fill: .white)
        meterLabel = SKSpriteNode(texture: label.texture, size: label.size)
        meterLabel.zPosition = 2
        hud.addChild(meterLabel)
    }

    private func layoutScene() {
        guard size.width > 10, size.height > 10 else { return }
        let w = size.width
        let h = size.height

        horizonY = h * 0.62
        unitK = min(w, h * 0.56) * 0.92

        camRig.position = CGPoint(x: w / 2, y: h / 2)
        worldRoot.position = CGPoint(x: -w / 2, y: -h / 2)

        let wide = w * 1.8
        skyGray.size = CGSize(width: wide, height: h - horizonY + h * 0.3)
        skyGray.position = CGPoint(x: w / 2, y: horizonY)
        skyBlue.size = skyGray.size
        skyBlue.position = skyGray.position
        sunSprite.position = CGPoint(x: w * 0.78, y: horizonY + (h - horizonY) * 0.62)
        for (i, cloud) in cloudSprites.enumerated() {
            cloud.position = CGPoint(x: w * (0.15 + 0.32 * CGFloat(i)), y: horizonY + (h - horizonY) * (0.45 + 0.17 * CGFloat(i % 2)))
            cloud.setScale(0.7 + 0.15 * CGFloat(i))
        }

        let hillScale = wide / art.hills(colored: false).size.width
        for hills in [hillsGray, hillsColor] {
            hills.xScale = hillScale
            hills.yScale = min(hillScale, 0.9)
            hills.position = CGPoint(x: w / 2, y: horizonY - 22)
        }

        groundLayer.removeAllChildren()
        colorLayer.removeAllChildren()
        dashLayer.removeAllChildren()
        dashes.removeAll()

        let groundRect = CGSize(width: wide, height: horizonY + h * 0.4)
        let grayGround = SKSpriteNode(color: UIColor(hex: 0x8A8C99), size: groundRect)
        grayGround.anchorPoint = CGPoint(x: 0.5, y: 1)
        grayGround.position = CGPoint(x: w / 2, y: horizonY)
        groundLayer.addChild(grayGround)

        let colorGround = SKSpriteNode(color: UIColor(hex: 0x6CC66F), size: groundRect)
        colorGround.anchorPoint = CGPoint(x: 0.5, y: 1)
        colorGround.position = CGPoint(x: w / 2, y: horizonY)
        colorLayer.addChild(colorGround)

        if let roadPath = makeRoadPath() {
            let grayRoad = SKShapeNode(path: roadPath)
            grayRoad.fillColor = UIColor(hex: 0xC3C5CE)
            grayRoad.strokeColor = UIColor(hex: 0xE6E7EB)
            grayRoad.lineWidth = 6
            groundLayer.addChild(grayRoad)

            let colorRoad = SKShapeNode(path: roadPath)
            colorRoad.fillColor = UIColor(hex: 0xF4D58D)
            colorRoad.strokeColor = .white
            colorRoad.lineWidth = 6
            colorLayer.addChild(colorRoad)
        }

        for _ in 0..<(dashesPerDivider * 2) {
            let dash = SKSpriteNode(color: UIColor(white: 1, alpha: 0.85), size: CGSize(width: 2, height: 2))
            dashLayer.addChild(dash)
            dashes.append(dash)
        }

        let stormWidth = w * 1.3
        let stormScale = stormWidth / art.stormWall.size.width
        stormBack.setScale(stormScale)
        stormFront.xScale = -stormScale
        stormFront.yScale = stormScale
        stormBack.position.x = w / 2
        stormFront.position.x = w / 2
        stormScraps?.particlePositionRange = CGVector(dx: w, dy: 10)

        vignette.size = size
        flash.size = size

        let topInset = max(view?.safeAreaInsets.top ?? 0, 20)
        let top = h - topInset - 28
        for (i, heart) in hearts.enumerated() {
            heart.position = CGPoint(x: w - 30 - CGFloat(2 - i) * 38, y: top)
        }
        spoolCountSprite.position = CGPoint(x: w - 14, y: top - 40)
        spoolIcon.position = CGPoint(x: w - 34, y: top - 40)
        timerSprite.position = CGPoint(x: w / 2, y: top)
        meterWidth = min(200, w * 0.46)
        meterBack.path = CGPath(
            roundedRect: CGRect(x: -meterWidth / 2 - 4, y: -11, width: meterWidth + 8, height: 22),
            cornerWidth: 11, cornerHeight: 11, transform: nil
        )
        meterBack.position = CGPoint(x: w / 2, y: top - 38)
        meterFill.position = CGPoint(x: w / 2 - meterWidth / 2, y: top - 38)
        meterLabel.position = CGPoint(x: w / 2, y: top - 38)
        overlay.position = .zero

        render(dt: 0)
    }

    private func makeRoadPath() -> CGPath? {
        let edge = laneWidth * 1.5
        guard let nearLeft = project(x: -edge, z: -2.6),
              let nearRight = project(x: edge, z: -2.6),
              let farRight = project(x: edge, z: 90),
              let farLeft = project(x: -edge, z: 90) else { return nil }
        let path = CGMutablePath()
        path.move(to: nearLeft.point)
        path.addLine(to: nearRight.point)
        path.addLine(to: farRight.point)
        path.addLine(to: farLeft.point)
        path.closeSubpath()
        return path
    }

    // MARK: Projection

    /// World point to screen. `scale` is the node scale for art drawn at 100 points per world unit.
    private func project(x: Double, z: Double, y: Double = 0) -> (point: CGPoint, scale: CGFloat, depth: Double)? {
        let depth = z + camBack
        guard depth > 0.25 else { return nil }
        let s = CGFloat(1.0 / depth)
        let px = size.width / 2 + CGFloat(x) * s * unitK
        let py = horizonY - CGFloat(camHeight - y) * s * unitK
        return (CGPoint(x: px, y: py), s * unitK / 100, depth)
    }

    private func screenPoint(ofWorld point: CGPoint) -> CGPoint {
        worldRoot.convert(point, to: self)
    }

    // MARK: Screens

    private func showTitle() {
        state = .title
        audio.setMusic(playing: false)
        overlay.removeAllChildren()
        hud.alpha = 0
        let w = size.width
        let h = size.height

        let logoSize = min(56, w * 0.135)
        let storm = art.text("STORM", size: logoSize, fill: .white)
        let stitch = art.text("STITCH", size: logoSize, fill: Palette.stitchGold)
        let gap: CGFloat = 4
        let total = storm.size.width + stitch.size.width + gap
        let logoY = h * 0.80
        let stormSprite = SKSpriteNode(texture: storm.texture, size: storm.size)
        stormSprite.position = CGPoint(x: w / 2 - total / 2 + storm.size.width / 2, y: logoY)
        let stitchSprite = SKSpriteNode(texture: stitch.texture, size: stitch.size)
        stitchSprite.position = CGPoint(x: w / 2 + total / 2 - stitch.size.width / 2, y: logoY)
        overlay.addChild(stormSprite)
        overlay.addChild(stitchSprite)
        for (i, sprite) in [stormSprite, stitchSprite].enumerated() {
            sprite.setScale(0.6)
            sprite.alpha = 0
            sprite.run(.sequence([
                .wait(forDuration: 0.1 + Double(i) * 0.12),
                .group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.35)])
            ]))
            sprite.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 5, duration: 1.2 + Double(i) * 0.2),
                .moveBy(x: 0, y: -5, duration: 1.2 + Double(i) * 0.2)
            ])))
        }

        let underline = SKShapeNode()
        let line = CGMutablePath()
        line.move(to: CGPoint(x: -total / 2 + 10, y: 0))
        line.addLine(to: CGPoint(x: total / 2 - 10, y: 0))
        underline.path = line.copy(dashingWithPhase: 0, lengths: [16, 10])
        underline.strokeColor = Palette.stitchGold
        underline.lineWidth = 5
        underline.lineCap = .round
        underline.position = CGPoint(x: w / 2, y: logoY - logoSize * 0.72)
        overlay.addChild(underline)

        let tagline = art.text("Outrun the storm. Stitch the world back.", size: min(16, w * 0.04), fill: .white)
        let tagSprite = SKSpriteNode(texture: tagline.texture, size: tagline.size)
        tagSprite.position = CGPoint(x: w / 2, y: logoY - logoSize * 1.25)
        overlay.addChild(tagSprite)

        let prompt = art.text("Tap to run", size: 26, fill: Palette.stitchGold)
        let promptSprite = SKSpriteNode(texture: prompt.texture, size: prompt.size)
        promptSprite.position = CGPoint(x: w / 2, y: h * 0.2)
        promptSprite.run(.repeatForever(.sequence([
            .scale(to: 1.08, duration: 0.5),
            .scale(to: 1.0, duration: 0.5)
        ])))
        overlay.addChild(promptSprite)

        let best = UserDefaults.standard.integer(forKey: "bestSpools")
        if best > 0 {
            let bestArt = art.text("Best: \(best) spools", size: 15, fill: .white)
            let bestSprite = SKSpriteNode(texture: bestArt.texture, size: bestArt.size)
            bestSprite.position = CGPoint(x: w / 2, y: h * 0.2 - 40)
            overlay.addChild(bestSprite)
        }

        let help = art.text("Swipe to change lanes  \u{00B7}  Tap to jump  \u{00B7}  Swipe down to slide", size: min(12, w * 0.03), fill: UIColor(white: 1, alpha: 0.95))
        let helpSprite = SKSpriteNode(texture: help.texture, size: help.size)
        helpSprite.position = CGPoint(x: w / 2, y: h * 0.2 - 72)
        overlay.addChild(helpSprite)

        resetWorld()
        runSpeed = titleSpeed
    }

    private func showResults(caught: Bool, finished: Bool) {
        overlay.removeAllChildren()
        let w = size.width
        let h = size.height
        let cardW = min(w - 40, 340)
        let cardH: CGFloat = 330

        let card = SKNode()
        card.position = CGPoint(x: w / 2, y: h * 0.52)
        overlay.addChild(card)

        let shadow = SKShapeNode(rect: CGRect(x: -cardW / 2, y: -cardH / 2 - 8, width: cardW, height: cardH), cornerRadius: 26)
        shadow.fillColor = UIColor(white: 0, alpha: 0.28)
        shadow.strokeColor = .clear
        card.addChild(shadow)
        let panel = SKShapeNode(rect: CGRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH), cornerRadius: 26)
        panel.fillColor = Palette.paper
        panel.strokeColor = .white
        panel.lineWidth = 6
        card.addChild(panel)

        let titleText = finished ? "Run complete!" : (caught ? "Caught by the storm!" : "Out of hearts!")
        let title = art.text(titleText, size: 26, fill: finished ? Palette.stitchGold : .white)
        let titleSprite = SKSpriteNode(texture: title.texture, size: title.size)
        titleSprite.position = CGPoint(x: 0, y: cardH / 2 - 42)
        card.addChild(titleSprite)

        let earned = [finished, hitsTaken == 0 && finished, fullyStitched]
        let labels = ["Finish", "No hits", "Stitched"]
        for i in 0..<3 {
            let starArt = art.star(filled: earned[i])
            let star = SKSpriteNode(texture: starArt.texture, size: CGSize(width: 58, height: 58))
            star.position = CGPoint(x: CGFloat(i - 1) * 76, y: cardH / 2 - 108)
            star.setScale(0)
            star.run(.sequence([
                .wait(forDuration: 0.25 + Double(i) * 0.18),
                .scale(to: 1.25, duration: 0.12),
                .scale(to: 1, duration: 0.1),
                .run { [weak self] in
                    if earned[i] {
                        self?.audio.chime(step: 2 + i * 2)
                        self?.haptics.spool()
                    }
                }
            ]))
            card.addChild(star)
            let caption = art.text(labels[i], size: 11, fill: .white)
            let captionSprite = SKSpriteNode(texture: caption.texture, size: caption.size)
            captionSprite.position = CGPoint(x: star.position.x, y: star.position.y - 40)
            card.addChild(captionSprite)
        }

        let seconds = Int(elapsed)
        let rows = [
            ("Spools", "\(spools)"),
            ("Distance", "\(Int(distance)) m"),
            ("Stitched", "\(Int(meter * 100))%"),
            ("Best streak", "\(bestStreak)"),
            ("Time", "\(seconds / 60):\(String(format: "%02d", seconds % 60))")
        ]
        var y = cardH / 2 - 182
        for (name, value) in rows {
            let left = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            left.text = name
            left.fontSize = 16
            left.fontColor = Palette.stormDark
            left.horizontalAlignmentMode = .left
            left.verticalAlignmentMode = .center
            left.position = CGPoint(x: -cardW / 2 + 28, y: y)
            card.addChild(left)
            let right = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            right.text = value
            right.fontSize = 17
            right.fontColor = Palette.ink
            right.horizontalAlignmentMode = .right
            right.verticalAlignmentMode = .center
            right.position = CGPoint(x: cardW / 2 - 28, y: y)
            card.addChild(right)
            y -= 24
        }

        let best = UserDefaults.standard.integer(forKey: "bestSpools")
        if spools > best {
            UserDefaults.standard.set(spools, forKey: "bestSpools")
            let newBest = art.text("New best!", size: 16, fill: Palette.heart)
            let newBestSprite = SKSpriteNode(texture: newBest.texture, size: newBest.size)
            newBestSprite.position = CGPoint(x: cardW / 2 - 50, y: cardH / 2 + 6)
            newBestSprite.zRotation = -0.18
            card.addChild(newBestSprite)
        }

        let prompt = art.text("Tap to run again", size: 22, fill: Palette.stitchGold)
        let promptSprite = SKSpriteNode(texture: prompt.texture, size: prompt.size)
        promptSprite.position = CGPoint(x: w / 2, y: h * 0.52 - cardH / 2 - 44)
        promptSprite.run(.repeatForever(.sequence([.scale(to: 1.08, duration: 0.5), .scale(to: 1, duration: 0.5)])))
        overlay.addChild(promptSprite)

        card.setScale(0.7)
        card.alpha = 0
        card.run(.group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.25)]))
    }

    // MARK: Run flow

    private func resetWorld() {
        for thing in things { thing.sprite.removeFromParent() }
        things.removeAll()
        for patch in patches {
            patch.mask.removeFromParent()
            patch.stitch?.removeFromParent()
        }
        patches.removeAll()
        fxRoot.removeAllChildren()
        camRig.removeAction(forKey: "shake")

        elapsed = 0
        distance = 0
        nextRowIn = 14
        nextSceneryIn = 0
        nextPatchIn = 0
        heartsLeft = 3
        hitsTaken = 0
        spools = 0
        streak = 0
        bestStreak = 0
        streakTimer = 0
        meter = 0
        fullyStitched = false
        stormDistance = tuning.stormStart
        invulnerable = 0
        timeScale = 1
        hitStop = 0
        nextThunder = 6

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

        // Pre-fill the scenery so the world isn't empty at the start.
        var z = 2.0
        while z < spawnZ {
            spawnScenery(atZ: z)
            z += 1.8
        }
    }

    private func startRun() {
        overlay.removeAllChildren()
        resetWorld()
        state = .running
        runSpeed = tuning.startSpeed
        hud.alpha = 1
        shownSeconds = -1
        shownSpools = -1
        updateHUD()
        audio.play(.start)
        audio.setMusic(playing: true)
        haptics.success()
        // A hop to kick things off.
        velocityY = tuning.jumpVelocity * 0.7
        playerY = 0.0001
    }

    private func endRun(caught: Bool) {
        state = .over
        overAt = clock
        audio.setMusic(playing: false)
        audio.play(.gameOver)
        haptics.gameOver()
        hud.run(.fadeAlpha(to: 0.4, duration: 0.3))
        showResults(caught: caught, finished: false)
    }

    private func finishRun() {
        state = .over
        overAt = clock
        audio.setMusic(playing: false)
        audio.play(.finish)
        haptics.success()
        hud.run(.fadeAlpha(to: 0.4, duration: 0.3))
        showResults(caught: false, finished: true)
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let realDt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 30.0)
        lastUpdate = currentTime
        clock += realDt

        haptics.enabled = tuning.hapticsOn
        audio.sfxOn = tuning.soundOn
        audio.musicOn = tuning.musicOn

        var dt = realDt
        if hitStop > 0 {
            hitStop -= realDt
            dt = realDt * 0.05
        } else {
            timeScale += (1 - timeScale) * min(1, realDt * 6)
            dt = realDt * timeScale
        }

        switch state {
        case .running:
            step(dt)
        case .title, .over:
            ambient(dt)
        }
        render(dt: realDt)
    }

    /// Title and results screens: the world keeps drifting by so it feels alive.
    private func ambient(_ dt: Double) {
        runSpeed += ((state == .title ? titleSpeed : 0) - runSpeed) * min(1, dt * 2)
        advanceWorld(runSpeed * dt, dt: dt)
        if laneProgress < 1 {
            laneProgress = min(1, laneProgress + dt / 0.2)
            playerX = laneFromX + (laneToX - laneFromX) * (1 - pow(1 - laneProgress, 2))
        }
        updatePlayerPhysics(dt)
    }

    private func step(_ dt: Double) {
        elapsed += dt
        let t = min(elapsed / max(tuning.runLength, 1), 1)
        runSpeed = lerp(tuning.startSpeed, tuning.endSpeed, t)
        let move = runSpeed * dt
        advanceWorld(move, dt: dt)

        nextRowIn -= move
        if nextRowIn <= 0 {
            spawnRow(atZ: spawnZ + nextRowIn)
            let interval = lerp(tuning.rowIntervalStart, tuning.rowIntervalEnd, t)
            nextRowIn += max(runSpeed * interval, 4.5)
        }

        if laneProgress < 1 {
            laneProgress = min(1, laneProgress + dt / max(tuning.laneSwitchTime, 0.01))
            playerX = laneFromX + (laneToX - laneFromX) * (1 - pow(1 - laneProgress, 2))
        }
        updatePlayerPhysics(dt)

        if slideTimer > 0 { slideTimer -= dt }
        if invulnerable > 0 { invulnerable -= dt }
        if jumpBuffer > 0 { jumpBuffer -= dt }
        if streakTimer > 0 {
            streakTimer -= dt
            if streakTimer <= 0 { streak = 0 }
        }

        checkCollisions()
        guard state == .running else { return }

        stormDistance = min(tuning.stormStart, stormDistance + tuning.stormRecoverRate * dt)
        if stormDistance <= 0 {
            endRun(caught: true)
            return
        }

        let closeness = 1 - stormDistance / max(tuning.stormStart, 0.1)
        nextThunder -= dt
        if nextThunder <= 0 {
            nextThunder = Double.random(in: 5...10) * (1 - closeness * 0.6)
            thunderFlash(strength: 0.25 + closeness * 0.4)
        }

        audio.setIntensity(Float(0.3 + t * 0.5 + closeness * 0.4))

        if elapsed >= tuning.runLength {
            finishRun()
            return
        }

        updateHUD()
    }

    private func updatePlayerPhysics(_ dt: Double) {
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
        if landSquash > 0 { landSquash -= dt }
        if playerY <= 0 && slideTimer <= 0 {
            runPhase += runSpeed * dt * 0.95
        }
        blinkTimer -= dt
        if blinkTimer <= 0 {
            blinkTimer = Double.random(in: 2...5)
            let closed = art.brambleEyes(closed: true)
            let open = art.brambleEyes(closed: false)
            eyes.run(.sequence([
                .setTexture(closed.texture),
                .wait(forDuration: 0.11),
                .setTexture(open.texture)
            ]))
        }
    }

    private func advanceWorld(_ move: Double, dt: Double) {
        distance += move
        for thing in things {
            thing.prevZ = thing.z
            thing.z -= move
        }
        for patch in patches {
            patch.z -= move
            patch.age += dt
        }

        nextSceneryIn -= move
        while nextSceneryIn <= 0 {
            spawnScenery(atZ: spawnZ + nextSceneryIn)
            nextSceneryIn += 1.8
        }

        nextPatchIn -= move
        while nextPatchIn <= 0 {
            spawnAmbientPatch(atZ: spawnZ + nextPatchIn)
            nextPatchIn += fullyStitched ? 2.2 : 2.6
        }

        things.removeAll { thing in
            if thing.z < -3 {
                thing.sprite.removeFromParent()
                return true
            }
            return false
        }
        patches.removeAll { patch in
            if patch.z < -6 - patch.radius {
                patch.mask.removeFromParent()
                patch.stitch?.removeFromParent()
                return true
            }
            return false
        }
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
            addHazard(kind, lane: lanes[i], z: z)
            if kind == .low { lowLane = lanes[i] }
        }

        let roll = Double.random(in: 0...1)
        if let lowLane, roll < 0.35 {
            let offsets = [-2.4, -1.2, 0.0, 1.2, 2.4]
            let heights = [0.5, 0.95, 1.2, 0.95, 0.5]
            for i in 0..<offsets.count {
                addSpool(lane: lowLane, z: z + offsets[i], y: heights[i])
            }
        } else if roll < 0.85 {
            for i in 0..<5 {
                addSpool(lane: freeLane, z: z + Double(i) * 1.2, y: 0.4)
            }
        }
    }

    private func addHazard(_ kind: HazardKind, lane: Int, z: Double) {
        let hazardArt: Art
        let anchorY: CGFloat
        switch kind {
        case .low:
            hazardArt = art.eraser
            anchorY = 12.0 / 70.0
        case .overhead:
            hazardArt = art.ruler
            anchorY = 10.0 / 190.0
        case .crate:
            hazardArt = art.box
            anchorY = 10.0 / 160.0
        }
        let sprite = SKSpriteNode(texture: hazardArt.texture, size: hazardArt.size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: anchorY)
        sprite.alpha = 0
        objectLayer.addChild(sprite)
        things.append(Thing(kind: .hazard(kind), sprite: sprite, worldScale: 1,
                            x: Double(lane) * laneWidth, z: z, y: 0))
    }

    private func addSpool(lane: Int, z: Double, y: Double) {
        let spoolArt = art.spool
        let sprite = SKSpriteNode(texture: spoolArt.texture, size: spoolArt.size)
        sprite.alpha = 0
        objectLayer.addChild(sprite)
        things.append(Thing(kind: .spool, sprite: sprite, worldScale: 0.8,
                            x: Double(lane) * laneWidth, z: z, y: y))
    }

    private func spawnScenery(atZ z: Double) {
        let count = Int.random(in: 1...2)
        for _ in 0..<count {
            let side: Double = Bool.random() ? -1 : 1
            let x = side * Double.random(in: 2.3...5.2)
            let roll = Double.random(in: 0...1)
            let kind: SceneryKind = roll < 0.4 ? .tree : (roll < 0.7 ? .bush : .flower)
            let variant = Int.random(in: 0...2)
            let colored = Double.random(in: 0...1) < meter
            let pick = self.sceneryArt(kind, variant: variant, colored: colored)
            let sprite = SKSpriteNode(texture: pick.texture, size: pick.size)
            let groundY: CGFloat
            let scale: CGFloat
            switch kind {
            case .tree:
                groundY = 172
                scale = 1.25
            case .bush:
                groundY = 72
                scale = 1.0
            case .flower:
                groundY = 68
                scale = 0.85
            }
            sprite.anchorPoint = CGPoint(x: 0.5, y: (pick.size.height - groundY) / pick.size.height)
            sprite.alpha = 0
            objectLayer.addChild(sprite)
            let thing = Thing(kind: .scenery(kind, variant: variant), sprite: sprite, worldScale: scale,
                              x: x, z: z + Double.random(in: 0...1.2), y: 0)
            thing.colored = colored
            things.append(thing)
        }
    }

    private func sceneryArt(_ kind: SceneryKind, variant: Int, colored: Bool) -> Art {
        switch kind {
        case .tree: return art.tree(colored: colored)
        case .bush: return art.bush(colored: colored)
        case .flower: return art.flower(colored: colored, variant: variant)
        }
    }

    private func spawnAmbientPatch(atZ z: Double) {
        let chance = fullyStitched ? 1.0 : meter * 1.15
        guard Double.random(in: 0...1) < chance else { return }
        let radius = fullyStitched ? Double.random(in: 3.5...6) : Double.random(in: 1.2...2.6) * (0.6 + meter)
        addPatch(x: Double.random(in: -5...5), z: z, radius: radius, withStitch: false, growTime: 0.01)
    }

    private func addPatch(x: Double, z: Double, radius: Double, withStitch: Bool, growTime: Double) {
        let variant = Int.random(in: 0...3)
        let maskArt = art.patchMask(variant: variant)
        let mask = SKSpriteNode(texture: maskArt.texture, size: maskArt.size)
        maskRoot.addChild(mask)

        var stitch: SKSpriteNode?
        if withStitch {
            let stitchArt = art.patchStitch(variant: variant)
            let sprite = SKSpriteNode(texture: stitchArt.texture, size: stitchArt.size)
            stitchLayer.addChild(sprite)
            stitch = sprite
        }
        patches.append(Patch(mask: mask, stitch: stitch, x: x, z: z, radius: radius, growTime: growTime))
    }

    // MARK: Stitching

    /// Color floods in around a point as you collect thread.
    private func stitchBurst(atX x: Double, z: Double) {
        addPatch(x: x + Double.random(in: -0.4...0.4), z: z + Double.random(in: 0.5...2.0),
                 radius: Double.random(in: 0.9...1.4), withStitch: true, growTime: 0.25)
        if Double.random(in: 0...1) < 0.5 {
            addPatch(x: x + Double.random(in: -3...3), z: z + Double.random(in: 2...8),
                     radius: Double.random(in: 1.0...2.0), withStitch: true, growTime: 0.3)
        }
        for thing in things {
            guard case .scenery = thing.kind, !thing.colored else { continue }
            if thing.z > -1 && thing.z < 12 && Double.random(in: 0...1) < 0.3 {
                colorize(thing)
            }
        }
    }

    private func colorize(_ thing: Thing) {
        guard case .scenery(let kind, let variant) = thing.kind, !thing.colored else { return }
        thing.colored = true
        thing.sprite.texture = sceneryArt(kind, variant: variant, colored: true).texture
        thing.popTime = 0
    }

    private func worldFullyStitched() {
        fullyStitched = true
        audio.play(.stitchFull)
        haptics.success()
        timeScale = 0.35
        var z = 0.0
        while z < spawnZ {
            for x in [-4.0, 0.0, 4.0] {
                addPatch(x: x + Double.random(in: -1...1), z: z, radius: Double.random(in: 3.5...5.5),
                         withStitch: false, growTime: 0.2 + z * 0.012)
            }
            z += 5
        }
        for thing in things { colorize(thing) }
        popText("WORLD STITCHED!", size: 34, color: Palette.stitchGold, at: CGPoint(x: size.width / 2, y: size.height * 0.62), rise: 40, life: 1.6)
        sparkleBurst(at: CGPoint(x: size.width / 2, y: size.height * 0.5), count: 60, spread: .pi * 2, speed: 380)
    }

    // MARK: Collisions

    private func checkCollisions() {
        let playerTop = playerY + (slideTimer > 0 ? 0.45 : 1.0)

        for thing in things where !thing.resolved {
            if case .scenery = thing.kind {
                thing.resolved = true
                continue
            }
            let crossed = thing.prevZ >= -0.35 && thing.z < 0.35
            if thing.z <= -0.35 && !crossed {
                thing.resolved = true
                continue
            }
            guard crossed else { continue }
            let passing = thing.z <= -0.35
            if passing { thing.resolved = true }

            guard abs(thing.x - playerX) < 0.55 else {
                if passing, thing.isHazard { checkCloseCall(thing) }
                continue
            }

            switch thing.kind {
            case .spool:
                if abs((playerY + 0.5) - thing.y) < 0.5 {
                    collect(thing)
                }
            case .hazard(let hazard):
                let hit: Bool
                switch hazard {
                case .low: hit = playerY < 0.5
                case .overhead: hit = playerTop > 0.85
                case .crate: hit = playerY < 1.4
                }
                if hit {
                    thing.resolved = true
                    takeHit(from: thing)
                    if state != .running { return }
                }
            case .scenery:
                break
            }
        }
    }

    private func checkCloseCall(_ thing: Thing) {
        let hazardLane = Int((thing.x / laneWidth).rounded())
        guard hazardLane == lastLaneFrom, elapsed - lastLaneChange < 0.35 else { return }
        audio.play(.closeCall)
        haptics.spool()
        timeScale = 0.4
        spools += 3
        meter = min(1, meter + 0.03)
        popText("Close call! +3", size: 24, color: .white, at: playerScreenPoint(offsetY: 120), rise: 50, life: 0.9)
    }

    private func collect(_ thing: Thing) {
        thing.resolved = true
        let point = screenPoint(ofWorld: thing.sprite.position)
        thing.sprite.removeFromParent()
        spools += 1
        streak += 1
        bestStreak = max(bestStreak, streak)
        streakTimer = 1.4
        audio.chime(step: min(streak - 1, 8))
        if streak % 5 == 0 { audio.play(.stitch, volume: 0.8) }
        haptics.spool()
        sparkleBurst(at: point, count: 10, spread: .pi * 2, speed: 160)

        if streak > 0 && streak % 10 == 0 {
            popText("Streak x\(streak)!", size: 22, color: Palette.stitchGold, at: playerScreenPoint(offsetY: 150), rise: 40, life: 0.8)
        }

        let before = meter
        meter = min(1, meter + 0.012)
        stitchBurst(atX: thing.x, z: max(0.5, thing.z))
        if before < 1 && meter >= 1 && !fullyStitched {
            worldFullyStitched()
        }
    }

    private func takeHit(from thing: Thing) {
        guard invulnerable <= 0 else { return }
        heartsLeft -= 1
        hitsTaken += 1
        invulnerable = 1.3
        streak = 0
        stormDistance -= tuning.stormHitPenalty
        meter = max(0, meter - 0.08)
        hitStop = 0.07
        audio.play(.hit)
        haptics.hit()
        shake(strength: 14)

        // The hazard bursts into paper scraps.
        let point = screenPoint(ofWorld: thing.sprite.position)
        thing.sprite.removeFromParent()
        confettiBurst(at: point)
        flash.removeAllActions()
        flash.color = .white
        flash.alpha = 0.45
        flash.run(.fadeOut(withDuration: 0.25))

        if heartsLeft >= 0 && heartsLeft < hearts.count {
            let heart = hearts[heartsLeft]
            heart.run(.sequence([.scale(to: 1.5, duration: 0.08), .scale(to: 1, duration: 0.15)]))
        }
        updateHUD()

        if heartsLeft <= 0 {
            endRun(caught: false)
        } else if stormDistance <= 0 {
            endRun(caught: true)
        }
    }

    // MARK: Actions

    private func moveLane(_ direction: Int) {
        let newLane = max(-1, min(1, laneIndex + direction))
        guard newLane != laneIndex else {
            shake(strength: 4)
            return
        }
        lastLaneFrom = laneIndex
        lastLaneChange = elapsed
        laneIndex = newLane
        laneFromX = playerX
        laneToX = Double(newLane) * laneWidth
        laneProgress = 0
        audio.play(.whoosh, volume: 0.6)
        haptics.lane()
    }

    private func jump() {
        guard playerY <= 0.0001 && velocityY <= 0 else {
            jumpBuffer = jumpBufferTime
            return
        }
        slideTimer = 0
        velocityY = tuning.jumpVelocity
        playerY = 0.0001
        audio.play(.jump, volume: 0.7)
        haptics.jump()
    }

    private func swipeDown() {
        if playerY > 0.0001 {
            velocityY = -tuning.jumpVelocity * 1.6
        } else {
            slideTimer = tuning.slideDuration
            audio.play(.whoosh, volume: 0.5)
            dustPuff()
        }
    }

    private func landed() {
        landSquash = landSquashTime
        if state == .running {
            audio.play(.land, volume: 0.6)
            haptics.land()
            dustPuff()
        }
        if jumpBuffer > 0 {
            jumpBuffer = 0
            jump()
        }
    }

    // MARK: Touch input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackedTouch == nil, let touch = touches.first else { return }

        switch state {
        case .title:
            startRun()
            return
        case .over:
            if clock - overAt > 0.8 { startRun() }
            return
        case .running:
            break
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
        touchStart = point
        if abs(dx) > abs(dy) {
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

    // MARK: Effects

    private func playerScreenPoint(offsetY: CGFloat) -> CGPoint {
        let world = playerNode.position
        let point = screenPoint(ofWorld: world)
        return CGPoint(x: point.x, y: point.y + offsetY)
    }

    private func shake(strength: CGFloat) {
        camRig.removeAction(forKey: "shake")
        let base = camRig.position
        let s = strength
        camRig.run(.sequence([
            .moveBy(x: s, y: s * 0.4, duration: 0.03),
            .moveBy(x: -s * 2, y: -s * 0.6, duration: 0.05),
            .moveBy(x: s * 1.5, y: s * 0.3, duration: 0.04),
            .move(to: base, duration: 0.04)
        ]), withKey: "shake")
    }

    private func thunderFlash(strength: Double) {
        audio.play(.thunder, volume: Float(min(1, 0.4 + strength)))
        flash.removeAllActions()
        flash.color = UIColor(hex: 0xE8E9FF)
        flash.alpha = 0
        flash.run(.sequence([
            .fadeAlpha(to: CGFloat(strength * 0.6), duration: 0.04),
            .fadeAlpha(to: 0.05, duration: 0.08),
            .fadeAlpha(to: CGFloat(strength * 0.4), duration: 0.04),
            .fadeOut(withDuration: 0.3)
        ]))
        for eye in stormEyes {
            eye.run(.sequence([.scale(to: 1.4, duration: 0.08), .scale(to: 1, duration: 0.3)]))
        }
    }

    private func popText(_ text: String, size fontSize: CGFloat, color: UIColor, at point: CGPoint, rise: CGFloat, life: Double) {
        let textArt = art.text(text, size: fontSize, fill: color)
        let sprite = SKSpriteNode(texture: textArt.texture, size: textArt.size)
        sprite.position = point
        sprite.setScale(0.4)
        sprite.zPosition = 10
        fxRoot.addChild(sprite)
        sprite.run(.sequence([
            .scale(to: 1.15, duration: 0.12),
            .scale(to: 1, duration: 0.08),
            .group([.moveBy(x: 0, y: rise, duration: life), .sequence([.wait(forDuration: life * 0.6), .fadeOut(withDuration: life * 0.4)])]),
            .removeFromParent()
        ]))
    }

    private func emitter(texture: SKTexture, at point: CGPoint, count: Int, color: UIColor,
                         speed: CGFloat, spread: CGFloat, angle: CGFloat, life: CGFloat,
                         gravity: CGFloat, scale: CGFloat) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.numParticlesToEmit = count
        e.particleBirthRate = CGFloat(count) * 20
        e.particleLifetime = life
        e.particleLifetimeRange = life * 0.4
        e.emissionAngle = angle
        e.emissionAngleRange = spread
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.5
        e.yAcceleration = gravity
        e.particleAlphaSpeed = -1 / life
        e.particleScale = scale
        e.particleScaleRange = scale * 0.5
        e.particleRotationRange = .pi * 2
        e.particleRotationSpeed = 5
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.position = point
        fxRoot.addChild(e)
        e.run(.sequence([.wait(forDuration: Double(life) * 1.6 + 0.3), .removeFromParent()]))
        return e
    }

    private func sparkleBurst(at point: CGPoint, count: Int, spread: CGFloat, speed: CGFloat) {
        _ = emitter(texture: art.spark.texture, at: point, count: count, color: Palette.stitchGold,
                    speed: speed, spread: spread, angle: .pi / 2, life: 0.5, gravity: -200, scale: 0.6)
    }

    private func confettiBurst(at point: CGPoint) {
        for color in [UIColor.white, UIColor(hex: 0xD2D4DB), UIColor(hex: 0xFF8FA3)] {
            _ = emitter(texture: art.scrap.texture, at: point, count: 14, color: color,
                        speed: 320, spread: .pi * 0.9, angle: .pi / 2, life: 0.9, gravity: -700, scale: 1.1)
        }
    }

    private func dustPuff() {
        guard let ground = project(x: playerX, z: 0) else { return }
        let point = screenPoint(ofWorld: ground.point)
        _ = emitter(texture: art.puff.texture, at: point, count: 8, color: .white,
                    speed: 90, spread: .pi * 0.6, angle: .pi / 2, life: 0.35, gravity: 0, scale: 0.9)
    }

    // MARK: Rendering

    private func render(dt: Double) {
        guard unitK > 0, dashes.count == dashesPerDivider * 2 else { return }

        // Lane dashes stream toward you to sell the speed.
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

        // Stitched patches: flat on the ground, so squashed by perspective.
        for patch in patches {
            guard let p = project(x: patch.x, z: patch.z) else {
                patch.mask.isHidden = true
                patch.stitch?.isHidden = true
                continue
            }
            let grow = CGFloat(min(1, patch.age / max(patch.growTime, 0.01)))
            let eased = 1 - pow(1 - grow, 3)
            let width = CGFloat(patch.radius * 2) * p.scale * 100 * eased
            let squash = CGFloat(camHeight / p.depth)
            patch.mask.isHidden = false
            patch.mask.position = p.point
            patch.mask.size = CGSize(width: width, height: max(1, width * squash))
            if let stitch = patch.stitch {
                stitch.isHidden = false
                stitch.position = p.point
                stitch.size = patch.mask.size
                stitch.alpha = max(0, 1 - CGFloat(patch.age) / 1.6)
            }
        }

        // Hazards, spools, scenery.
        for thing in things {
            guard let p = project(x: thing.x, z: thing.z, y: thing.y) else {
                thing.sprite.isHidden = true
                continue
            }
            let sprite = thing.sprite
            sprite.isHidden = false
            sprite.position = p.point
            sprite.zPosition = CGFloat((spawnZ + 10 - thing.z) * 5)
            sprite.alpha = CGFloat(max(0, min(1, (spawnZ + 2 - thing.z) / 6)))
            var xScale = p.scale * thing.worldScale
            var yScale = xScale

            switch thing.kind {
            case .hazard:
                // Pop-up book: hazards fold up out of the page as they approach.
                let rise = max(0, min(1, (28 - thing.z) / 5))
                yScale *= CGFloat(easeOutBack(rise))
            case .spool:
                let spin = 0.35 + 0.65 * abs(cos(clock * 4 + thing.phase))
                xScale *= CGFloat(spin)
                sprite.position.y += CGFloat(sin(clock * 5 + thing.phase) * 6) * p.scale
            case .scenery:
                let sway = sin(clock * 1.6 + thing.phase) * 0.04
                sprite.zRotation = CGFloat(sway)
                if thing.popTime >= 0 {
                    thing.popTime += dt
                    let t = min(1, thing.popTime / 0.3)
                    let bounce = 1 + 0.35 * sin(t * .pi) * (1 - t)
                    xScale *= CGFloat(bounce)
                    yScale *= CGFloat(bounce)
                    if t >= 1 { thing.popTime = -1 }
                }
            }
            sprite.xScale = xScale
            sprite.yScale = yScale
        }

        renderPlayer()
        renderCamera()
        renderSkyAndStorm()
    }

    private func renderPlayer() {
        guard let ground = project(x: playerX, z: 0),
              let lifted = project(x: playerX, z: 0, y: playerY) else { return }

        playerShadow.position = ground.point
        playerShadow.setScale(ground.scale * CGFloat(max(0.35, 1 - playerY * 0.4)))
        playerShadow.zPosition = CGFloat((spawnZ + 10) * 5) + 0.5

        playerNode.position = lifted.point
        playerNode.setScale(lifted.scale)
        playerNode.zPosition = CGFloat((spawnZ + 10) * 5) + 2

        let airborne = playerY > 0.0001
        let sliding = slideTimer > 0
        var sx: CGFloat = 1
        var sy: CGFloat = 1
        var bob: CGFloat = 0
        let stride = sin(runPhase * .pi)

        if sliding {
            sx = 1.25
            sy = 0.5
        } else if landSquash > 0 {
            let amount = CGFloat(landSquash / landSquashTime)
            sx = 1 + 0.18 * amount
            sy = 1 - 0.24 * amount
        } else if airborne {
            sx = velocityY > 0 ? 0.9 : 0.96
            sy = velocityY > 0 ? 1.12 : 1.04
        } else {
            bob = CGFloat(abs(stride)) * 9
            sy = 1 + CGFloat(abs(stride)) * 0.04
        }

        rig.xScale = rigBaseScale * sx
        rig.yScale = rigBaseScale * sy
        rig.position = CGPoint(x: 0, y: bob * rigBaseScale)
        rig.zRotation = CGFloat((laneToX - playerX) * -0.35) + (sliding ? 0.25 : 0)

        if airborne {
            armL.zRotation = -2.4
            armR.zRotation = 2.4
            footL.position.y = 18
            footR.position.y = 18
        } else if sliding {
            armL.zRotation = -1.2
            armR.zRotation = 1.2
            footL.position.y = 12
            footR.position.y = 12
        } else {
            armL.zRotation = CGFloat(stride) * 0.7
            armR.zRotation = CGFloat(stride) * 0.7
            footL.position.y = 12 + CGFloat(max(0, stride)) * 14
            footR.position.y = 12 + CGFloat(max(0, -stride)) * 14
        }

        if invulnerable > 0 && state == .running {
            playerNode.alpha = Int(invulnerable * 14) % 2 == 0 ? 0.35 : 1
        } else {
            playerNode.alpha = 1
        }
    }

    private func renderCamera() {
        let follow = CGFloat(playerX) * (unitK / CGFloat(camBack)) * 0.3
        let lean = CGFloat(laneToX - playerX) * 0.035
        let speedT = CGFloat(max(0, min(1, (runSpeed - tuning.startSpeed) / max(tuning.endSpeed - tuning.startSpeed, 0.1))))
        if camRig.action(forKey: "shake") == nil {
            camRig.position = CGPoint(x: size.width / 2 - follow, y: size.height / 2)
        }
        camRig.zRotation = lean
        camRig.setScale(1 + 0.05 * speedT)
    }

    private func renderSkyAndStorm() {
        let m = CGFloat(fullyStitched ? 1 : meter)
        let colorAmount = min(1, m * 1.2)
        skyBlue.alpha = colorAmount
        hillsColor.alpha = colorAmount
        sunSprite.alpha = max(0, (colorAmount - 0.3) / 0.7)
        sunSprite.zRotation = CGFloat(clock * 0.15)
        for (i, cloud) in cloudSprites.enumerated() {
            cloud.alpha = max(0, (colorAmount - 0.15 * CGFloat(i)) * 0.95)
            cloud.position.x += CGFloat(4 + i * 2) * 0.016
            if cloud.position.x > size.width * 1.25 { cloud.position.x = -size.width * 0.25 }
        }

        // The storm wall rises from the bottom of the screen as it closes in.
        let running = state == .running
        let closeness = running ? CGFloat(1 - max(0, min(1, stormDistance / max(tuning.stormStart, 0.1)))) : 0.0
        let h = size.height
        let visible = h * (0.07 + closeness * 0.33) + CGFloat(sin(clock * 2.2) * 6)
        stormBack.position.y = visible + 18
        stormFront.position.y = visible + CGFloat(sin(clock * 3.1) * 5)
        stormBack.position.x = size.width / 2 + CGFloat(sin(clock * 0.9) * 16)
        stormFront.position.x = size.width / 2 + CGFloat(cos(clock * 1.1) * 14)

        let eyeY = visible - 60 * (size.width * 1.3 / 512)
        let eyeSpread = size.width * 0.16
        for (i, eye) in stormEyes.enumerated() {
            eye.position = CGPoint(x: size.width / 2 + (i == 0 ? -eyeSpread : eyeSpread), y: eyeY)
            eye.alpha = running ? 0.35 + closeness * 0.65 : 0.25
            eye.setScale(0.9 + closeness * 0.6)
        }
        stormScraps?.position = CGPoint(x: size.width / 2, y: visible - 20)
        stormScraps?.particleBirthRate = running ? 6 + closeness * 40 : 3

        if running && closeness > 0.6 {
            vignette.alpha = (closeness - 0.6) * 0.35 + CGFloat(sin(clock * 10) * 0.04)
        } else {
            vignette.alpha = 0
        }
    }

    private func updateHUD() {
        let remaining = max(0, Int((tuning.runLength - elapsed).rounded(.up)))
        if remaining != shownSeconds {
            shownSeconds = remaining
            let text = art.text("\(remaining / 60):\(String(format: "%02d", remaining % 60))", size: 28, fill: .white)
            timerSprite.texture = text.texture
            timerSprite.size = text.size
        }
        if spools != shownSpools {
            let grew = spools > shownSpools && shownSpools >= 0
            shownSpools = spools
            let text = art.text("\(spools)", size: 22, fill: Palette.stitchGold)
            spoolCountSprite.texture = text.texture
            spoolCountSprite.size = text.size
            spoolIcon.position.x = size.width - 14 - text.size.width - 12
            if grew {
                spoolIcon.removeAction(forKey: "bump")
                spoolIcon.run(.sequence([.scale(to: 1.3, duration: 0.05), .scale(to: 1, duration: 0.1)]), withKey: "bump")
            }
        }
        for (i, heart) in hearts.enumerated() {
            let full = i < heartsLeft
            heart.texture = art.heart(full: full).texture
        }
        meterFill.size = CGSize(width: max(0.01, meterWidth * CGFloat(meter)), height: 14)
    }

    private func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}
