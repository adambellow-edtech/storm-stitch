import SpriteKit
import UIKit

/// Storm Stitch vertical slice: Notebook Meadow, with the full cast of eight monsters.
/// The world starts gray and torn. Every spool you grab stitches color back in
/// around you, and the storm chases from behind. Drawn with a simple pseudo-3D
/// projection so the camera sits behind the runner, like the hero style frame.
final class RunScene: SKScene {

    // MARK: Types

    enum State { case title, running, paused, over }

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

    // Camera matched to the K2 gameplay reference: high and behind, long road, runner in the lower third.
    private let camHeight = 4.8
    private let camBack = 3.6
    private let laneWidth = 1.0
    private let spawnZ = 46.0
    private let dashSpacing = 3.0
    private let dashLength = 1.3
    private let dashesPerDivider = 26
    private let rigBaseScale: CGFloat = 0.9
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
    /// Illustrated sky-and-hills backdrop; the gray version shows until color floods in.
    private var backdropGray: SKSpriteNode?
    /// Shader-drawn paper road and ground (gray, and color revealed by stitching).
    private var texturedGray: SKSpriteNode?
    private var texturedColor: SKSpriteNode?
    private var backdropColor: SKSpriteNode?
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
    private var brambleSprite = SKSpriteNode()
    private let brambleBack = SKTexture(imageNamed: "bramble-back")
    private let brambleFront = SKTexture(imageNamed: "bramble-front")
    /// Illustrated poses, loaded on first use: name to texture and pixel size.
    private var poseTextures: [String: (texture: SKTexture, size: CGSize)] = [:]
    private var currentPose = ""
    /// The monster running this session, and title-screen picker state.
    private var monster = Monster.roster[Monster.selectedIndex]
    private var pickerNode: SKNode?
    private var pickerWidth: CGFloat = 0
    /// Bramble's once-per-run shrug.
    private var shrugUsed = false
    private var hitPoseTimer = 0.0
    /// Pause button in the HUD, and the 3-2-1 countdown when resuming.
    private let pauseButton = SKNode()
    private var resumeCountdown = 0.0
    private var shownCountdown = 0
    private var playerShadow = SKSpriteNode()

    private let stormRoot = SKNode()
    private var stormBack = SKSpriteNode()
    private var stormFront = SKSpriteNode()
    /// Illustrated storm wall (eyes included) and the solid cloud base that fills below it.
    private var stormArt: SKSpriteNode?
    /// Parallax storm layers: a dark one drifting behind, one rolling in front.
    private var stormFar: SKSpriteNode?
    private var stormNear: SKSpriteNode?
    /// The storm's glowing eyes, on their own layer so they can blink, squint and glare.
    private var stormGlare: SKSpriteNode?
    private var eyeBlinkTimer = 2.5
    private var eyeBlinkPhase = -1.0
    private var eyePop = 0.0
    private var eyeGloat = false
    private var eyeDefeated = false
    private let stormFill = SKSpriteNode(color: UIColor(hex: 0x605362), size: CGSize(width: 10, height: 10))
    /// Eye line in the storm picture, measured up from its bottom edge.
    private let stormEyeLine: CGFloat = 0.31
    private var stormEyes: [SKSpriteNode] = []
    private var stormScraps: SKEmitterNode?

    private let fxRoot = SKNode()
    private let hud = SKNode()
    private let flash = SKSpriteNode(color: .white, size: CGSize(width: 10, height: 10))
    private let vignette = SKSpriteNode(color: UIColor(hex: 0xFF3B30), size: CGSize(width: 10, height: 10))
    private var timerSprite = SKSpriteNode()
    private var spoolIcon = SKSpriteNode()
    private var spoolCountSprite = SKSpriteNode()
    private let timerPill = SKSpriteNode()
    private let spoolPill = SKSpriteNode()
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
            NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
                                                   name: UIApplication.willResignActiveNotification, object: nil)
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

        // Illustrated Bramble: the back view runs (flipped every stride for a two-frame cycle),
        // the front view greets you on the results card.
        brambleBack.filteringMode = .linear
        brambleFront.filteringMode = .linear
        let height: CGFloat = 120
        brambleSprite = SKSpriteNode(texture: brambleBack,
                                     size: CGSize(width: height * 452.0 / 640.0, height: height))
        brambleSprite.anchorPoint = CGPoint(x: 0.5, y: 0.02)
        rig.addChild(brambleSprite)
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

        let hasEyeLayer = UIImage(named: "storm-wall-noeyes") != nil && UIImage(named: "storm-eyes") != nil
        if let image = UIImage(named: hasEyeLayer ? "storm-wall-noeyes" : "storm-wall") {
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear

            // Far layer: mirrored, darker, peeking over the main wall and drifting slowly.
            let far = SKSpriteNode(texture: texture)
            far.anchorPoint = CGPoint(x: 0.5, y: stormEyeLine)
            far.color = Palette.ink
            far.colorBlendFactor = 0.45
            far.zPosition = 0.3
            stormRoot.addChild(far)
            stormFar = far

            let sprite = SKSpriteNode(texture: texture)
            sprite.anchorPoint = CGPoint(x: 0.5, y: stormEyeLine)
            sprite.zPosition = 1
            stormRoot.addChild(sprite)
            stormArt = sprite

            if hasEyeLayer, let eyeImage = UIImage(named: "storm-eyes") {
                let eyeTexture = SKTexture(image: eyeImage)
                eyeTexture.filteringMode = .linear
                let eyes = SKSpriteNode(texture: eyeTexture)
                eyes.zPosition = 0.1
                sprite.addChild(eyes)
                stormGlare = eyes
            }

            // Near layer: mirrored and lower, rolling across the bottom in front of everything.
            let near = SKSpriteNode(texture: texture)
            near.anchorPoint = CGPoint(x: 0.5, y: 0)
            near.color = Palette.ink
            near.colorBlendFactor = 0.25
            near.zPosition = 2
            stormRoot.addChild(near)
            stormNear = near
            stormFill.anchorPoint = CGPoint(x: 0.5, y: 1)
            stormFill.zPosition = 0.5
            stormRoot.addChild(stormFill)
            for node in [stormBack, stormFront] + stormEyes {
                node.isHidden = true
            }
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
            let heartArt = illustrated("ui-heart", width: 38) ?? art.heart(full: true)
            let heart = SKSpriteNode(texture: heartArt.texture, size: CGSize(width: 38, height: 38 * heartArt.size.height / heartArt.size.width))
            hud.addChild(heart)
            hearts.append(heart)
        }

        // Paper pause button, top left.
        let pausePaper = SKSpriteNode()
        if let image = UIImage(named: "ui-pill") {
            pausePaper.texture = SKTexture(image: image)
        } else {
            pausePaper.color = UIColor(white: 1, alpha: 0.85)
        }
        pausePaper.centerRect = CGRect(x: 0.17, y: 0, width: 0.66, height: 1)
        pausePaper.size = CGSize(width: 54, height: 38)
        pauseButton.addChild(pausePaper)
        for x in [CGFloat(-5.5), 5.5] {
            let bar = SKShapeNode(rect: CGRect(x: x - 3, y: -8, width: 6, height: 16), cornerRadius: 2)
            bar.fillColor = Palette.ink
            bar.strokeColor = .clear
            bar.zPosition = 1
            pauseButton.addChild(bar)
        }
        pauseButton.name = "pause"
        hud.addChild(pauseButton)

        let spoolArt = art.spool
        spoolIcon = SKSpriteNode(texture: spoolArt.texture, size: CGSize(width: 28, height: 30))
        hud.addChild(spoolIcon)
        spoolCountSprite.anchorPoint = CGPoint(x: 1, y: 0.5)
        hud.addChild(spoolCountSprite)
        timerSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        hud.addChild(timerSprite)

        // Paper pills behind the timer and the spool count.
        for pill in [timerPill, spoolPill] {
            if let image = UIImage(named: "ui-pill") {
                pill.texture = SKTexture(image: image)
            } else {
                pill.color = UIColor(white: 1, alpha: 0.85)
            }
            pill.zPosition = -1
            hud.addChild(pill)
        }

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

        horizonY = h * 0.84
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

        // Illustrated backdrop replaces the code-drawn sky, sun, clouds and hills when present.
        if let grayImage = UIImage(named: "backdrop-gray"), let colorImage = UIImage(named: "backdrop-color") {
            if backdropGray == nil {
                let gray = SKSpriteNode(texture: SKTexture(image: grayImage))
                gray.zPosition = -190
                worldRoot.addChild(gray)
                backdropGray = gray
                let color = SKSpriteNode(texture: SKTexture(image: colorImage))
                color.zPosition = -189
                color.alpha = 0
                worldRoot.addChild(color)
                backdropColor = color
            }
            let backWidth = w * 1.35
            let backHeight = backWidth * grayImage.size.height / grayImage.size.width
            for backdrop in [backdropGray, backdropColor].compactMap({ $0 }) {
                backdrop.size = CGSize(width: backWidth, height: backHeight)
                // The hill crests sit about 72% of the way down the picture; put them on the horizon.
                backdrop.anchorPoint = CGPoint(x: 0.5, y: 0.28)
                backdrop.position = CGPoint(x: w / 2, y: horizonY)
            }
            // Fill any sky above the picture with its top color.
            skyGray.color = UIColor(hex: 0xA9ABB6)
            skyBlue.color = UIColor(hex: 0x4A9BE8)
            for node in [hillsGray, hillsColor, sunSprite] + cloudSprites {
                node.isHidden = true
            }
        }

        groundLayer.removeAllChildren()
        colorLayer.removeAllChildren()
        dashLayer.removeAllChildren()
        dashes.removeAll()

        let groundRect = CGSize(width: wide, height: horizonY + h * 0.4)
        let shaderRect = CGRect(x: w / 2 - wide / 2, y: -h * 0.4, width: wide, height: horizonY + h * 0.4)
        texturedGray = PaperGround.make(colored: false, rect: shaderRect, horizonY: horizonY, unitK: unitK,
                                        camHeight: camHeight, camBack: camBack, centerX: w / 2)
        texturedColor = PaperGround.make(colored: true, rect: shaderRect, horizonY: horizonY, unitK: unitK,
                                         camHeight: camHeight, camBack: camBack, centerX: w / 2)
        if let texturedGray, let texturedColor {
            groundLayer.addChild(texturedGray)
            colorLayer.addChild(texturedColor)
        } else {
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
        }

        for _ in 0..<(dashesPerDivider * 2) {
            let dash = SKSpriteNode(color: UIColor(red: 1, green: 0.98, blue: 0.93, alpha: 0.8), size: CGSize(width: 2, height: 2))
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
        if let stormArt, let image = UIImage(named: "storm-wall") {
            let artWidth = w * 1.45
            let artHeight = artWidth * image.size.height / image.size.width
            stormArt.setScale(1)
            stormArt.size = CGSize(width: artWidth, height: artHeight)
            stormFar?.setScale(1)
            stormFar?.size = CGSize(width: artWidth * 1.1, height: artHeight * 1.1)
            stormNear?.setScale(1)
            stormNear?.size = CGSize(width: artWidth * 1.05, height: artHeight * 1.05)
            // The eyes layer was cut from the art at these fractions of its width and height.
            stormGlare?.size = CGSize(width: artWidth * 0.2498, height: artHeight * 0.2788)
            stormGlare?.position = CGPoint(x: 0, y: artHeight * (0.3221 - stormEyeLine))
            stormFill.size = CGSize(width: artWidth * 1.1, height: h)
        }

        vignette.size = size
        flash.size = size

        let topInset = max(view?.safeAreaInsets.top ?? 0, 20)
        let top = h - topInset - 28
        for (i, heart) in hearts.enumerated() {
            heart.position = CGPoint(x: w - 30 - CGFloat(2 - i) * 38, y: top)
        }
        spoolCountSprite.position = CGPoint(x: w - 26, y: top - 42)
        spoolIcon.position = CGPoint(x: w - 26 - spoolCountSprite.size.width - 14, y: top - 42)
        timerSprite.position = CGPoint(x: w / 2, y: top)
        pauseButton.position = CGPoint(x: 38, y: top)
        timerPill.size = CGSize(width: 116, height: 39)
        timerPill.position = CGPoint(x: w / 2, y: top)
        spoolPill.position.y = top - 42
        fitSpoolPill()
        meterWidth = min(170, w * 0.36)
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

    /// A sprite from a bundled PNG at its native pixel size; callers set the display size.
    private func imageSprite(_ name: String) -> SKSpriteNode? {
        guard let image = UIImage(named: name) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return SKSpriteNode(texture: texture, size: image.size)
    }

    /// A paper button with a label, sized by width.
    private func paperButton(_ label: String, width: CGFloat) -> SKNode {
        let node = SKNode()
        let height = width * 300.0 / 720.0
        if let paper = imageSprite("ui-button") {
            paper.size = CGSize(width: width, height: height)
            node.addChild(paper)
        } else {
            let panel = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerRadius: height / 2)
            panel.fillColor = Palette.paper
            panel.strokeColor = .white
            panel.lineWidth = 5
            node.addChild(panel)
        }
        let text = art.text(label, size: height * 0.34, fill: Palette.stitchGold)
        let textSprite = SKSpriteNode(texture: text.texture, size: text.size)
        textSprite.position = CGPoint(x: 0, y: -height * 0.02)
        textSprite.zPosition = 1
        node.addChild(textSprite)
        node.run(.repeatForever(.sequence([
            .scale(to: 1.05, duration: 0.55),
            .scale(to: 1.0, duration: 0.55)
        ])))
        return node
    }

    private func showTitle() {
        state = .title
        eyeGloat = false
        eyeDefeated = false
        audio.setMusic(playing: false)
        overlay.removeAllChildren()
        hud.removeAllActions()
        hud.alpha = 0
        let w = size.width
        let h = size.height
        let bottomInset = max(view?.safeAreaInsets.bottom ?? 0, 16)

        resetWorld()
        runSpeed = titleSpeed

        if let card = imageSprite("title-card"), let cardTexture = card.texture {
            // Fit the title art to the screen width, top aligned so the logo clears the island.
            let fitted = CGSize(width: w, height: card.size.height * w / card.size.width)
            card.size = fitted
            card.anchorPoint = CGPoint(x: 0.5, y: 1)
            card.position = CGPoint(x: w / 2, y: h)
            overlay.addChild(card)
            // Taller screens: extend the paper road by mirroring the bottom of the art, so there's no seam.
            let gap = h - fitted.height
            if gap > 0 {
                let stripTexture = SKTexture(rect: CGRect(x: 0, y: 0, width: 1, height: 0.15), in: cardTexture)
                let strip = SKSpriteNode(texture: stripTexture, size: CGSize(width: w, height: gap + 2))
                strip.anchorPoint = CGPoint(x: 0.5, y: 0)
                strip.position = CGPoint(x: w / 2, y: gap + 1)
                strip.yScale = -1
                overlay.addChild(strip)
                strip.alpha = 0
                strip.run(.fadeIn(withDuration: 0.35))
            }
            card.alpha = 0
            card.run(.fadeIn(withDuration: 0.35))
        } else {
            let logo = art.text("STORM STITCH", size: min(44, w * 0.1), fill: Palette.stitchGold)
            let logoSprite = SKSpriteNode(texture: logo.texture, size: logo.size)
            logoSprite.position = CGPoint(x: w / 2, y: h * 0.78)
            overlay.addChild(logoSprite)
        }

        let buttonWidth = min(270, w * 0.66)
        let button = paperButton("Tap to run", width: buttonWidth)
        let buttonY = bottomInset + 64 + buttonWidth * 300.0 / 720.0 / 2
        button.position = CGPoint(x: w / 2, y: buttonY)
        button.zPosition = 2
        overlay.addChild(button)

        let buttonTop = buttonY + buttonWidth * 300.0 / 720.0 / 2
        buildPicker(aboveY: buttonTop + 8)

        let help = art.text("Swipe to change lanes  \u{00B7}  Tap to jump  \u{00B7}  Swipe down to slide",
                            size: min(12, w * 0.03), fill: .white, style: .body)
        let helpSprite = SKSpriteNode(texture: help.texture, size: help.size)
        helpSprite.position = CGPoint(x: w / 2, y: bottomInset + 26)
        helpSprite.zPosition = 2
        overlay.addChild(helpSprite)
    }

    private func showResults(caught: Bool, finished: Bool) {
        overlay.removeAllChildren()
        hud.removeAllActions()
        hud.run(.fadeOut(withDuration: 0.25))
        let w = size.width
        let h = size.height
        let topInset = max(view?.safeAreaInsets.top ?? 0, 20)
        let cardW = min(w - 16, 390)
        let cardH = cardW * 855.0 / 1140.0
        let k = cardW / 380

        let card = SKNode()
        card.position = CGPoint(x: w / 2, y: h - topInset - 12 - cardH / 2)
        overlay.addChild(card)

        if let paper = imageSprite("ui-card") {
            paper.size = CGSize(width: cardW, height: cardH)
            card.addChild(paper)
        } else {
            let panel = SKShapeNode(rect: CGRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH), cornerRadius: 24)
            panel.fillColor = Palette.paper
            panel.strokeColor = .white
            panel.lineWidth = 6
            card.addChild(panel)
        }

        let titleText = finished ? "Run complete!" : (caught ? "Caught by the storm!" : "Out of hearts!")
        let title = art.text(titleText, size: 24 * k, fill: finished ? Palette.stitchGold : .white)
        let titleSprite = SKSpriteNode(texture: title.texture, size: title.size)
        titleSprite.position = CGPoint(x: 0, y: cardH * 0.25)
        titleSprite.zPosition = 1
        card.addChild(titleSprite)

        let earned = [finished, hitsTaken == 0 && finished, fullyStitched]
        let labels = ["Finish", "No hits", "Stitched"]
        let starY = cardH * 0.07
        for i in 0..<3 {
            let starArt = illustrated(earned[i] ? "ui-star" : "ui-star-empty", width: 50 * k) ?? art.star(filled: earned[i])
            let star = SKSpriteNode(texture: starArt.texture, size: CGSize(width: 46 * k, height: 46 * k))
            star.position = CGPoint(x: CGFloat(i - 1) * 74 * k, y: starY)
            star.zPosition = 1
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
            let caption = art.text(labels[i], size: 10.5 * k, fill: .white, style: .body)
            let captionSprite = SKSpriteNode(texture: caption.texture, size: caption.size)
            captionSprite.position = CGPoint(x: star.position.x, y: starY - 31 * k)
            captionSprite.zPosition = 1
            card.addChild(captionSprite)
        }

        let bestBefore = UserDefaults.standard.integer(forKey: "bestSpools")
        let isNewBest = spools > bestBefore
        if isNewBest { UserDefaults.standard.set(spools, forKey: "bestSpools") }

        let seconds = Int(elapsed)
        let cells = [
            ("Spools", "\(spools)"),
            ("Distance", "\(Int(distance)) m"),
            ("Time", "\(seconds / 60):\(String(format: "%02d", seconds % 60))"),
            ("Stitched", "\(Int(meter * 100))%"),
            ("Best streak", "\(bestStreak)"),
            ("Best ever", "\(max(spools, bestBefore))")
        ]
        for (index, cell) in cells.enumerated() {
            let column = CGFloat(index % 3 - 1)
            let rowY = index < 3 ? -cardH * 0.13 : -cardH * 0.29
            let value = SKLabelNode(fontNamed: "Fredoka-SemiBold")
            value.text = cell.1
            value.fontSize = 20 * k
            value.fontColor = Palette.ink
            value.verticalAlignmentMode = .center
            value.position = CGPoint(x: column * cardW * 0.28, y: rowY)
            value.zPosition = 1
            card.addChild(value)
            let label = SKLabelNode(fontNamed: "NunitoSans-Bold")
            label.text = cell.0
            label.fontSize = 11 * k
            label.fontColor = Palette.stormDark
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: value.position.x, y: rowY - 17 * k)
            label.zPosition = 1
            card.addChild(label)
        }

        if isNewBest {
            let newBest = art.text("New best!", size: 17 * k, fill: Palette.heart)
            let newBestSprite = SKSpriteNode(texture: newBest.texture, size: newBest.size)
            newBestSprite.position = CGPoint(x: cardW / 2 - 52 * k, y: cardH / 2 - 14 * k)
            newBestSprite.zRotation = -0.2
            newBestSprite.zPosition = 2
            card.addChild(newBestSprite)
            newBestSprite.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.4), .scale(to: 1, duration: 0.4)])))
        }

        let buttonWidth = min(240, w * 0.6)
        let button = paperButton("Run again", width: buttonWidth)
        button.position = CGPoint(x: w / 2, y: card.position.y - cardH / 2 - 6 - buttonWidth * 300.0 / 720.0 / 2)
        overlay.addChild(button)

        card.setScale(0.7)
        card.alpha = 0
        card.run(.group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.25)]))
        button.alpha = 0
        button.run(.sequence([.wait(forDuration: 0.5), .fadeIn(withDuration: 0.2)]))
    }

    /// Fades out whatever is on the overlay instead of cutting it.
    private func fadeOverlay() {
        let leaving = SKNode()
        leaving.zPosition = overlay.zPosition
        addChild(leaving)
        for child in overlay.children {
            child.move(toParent: leaving)
        }
        leaving.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))
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
        hitPoseTimer = 0
        eyePop = 0
        shrugUsed = false
        landSquash = 0
        jumpBuffer = 0
        trackedTouch = nil

        // Pre-fill the scenery so the world isn't empty at the start.
        var z = 2.0
        while z < spawnZ {
            spawnScenery(atZ: z)
            z += 1.3
        }
    }

    private func startRun() {
        let fromTitle = state == .title
        fadeOverlay()
        if !fromTitle { resetWorld() }
        distance = 0
        state = .running
        eyeGloat = false
        eyeDefeated = false
        runSpeed = tuning.startSpeed
        hud.removeAllActions()
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
        eyeGloat = true
        overAt = clock
        audio.setMusic(playing: false)
        audio.play(.gameOver)
        haptics.gameOver()
        showResults(caught: caught, finished: false)
    }

    private func finishRun() {
        state = .over
        eyeDefeated = true
        overAt = clock
        audio.setMusic(playing: false)
        audio.play(.finish)
        haptics.success()
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
        case .paused:
            stepCountdown(realDt)
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
            let switchTime = tuning.laneSwitchTime * (monster.ability == .quick ? 0.7 : 1)
            laneProgress = min(1, laneProgress + dt / max(switchTime, 0.01))
            playerX = laneFromX + (laneToX - laneFromX) * (1 - pow(1 - laneProgress, 2))
        }
        updatePlayerPhysics(dt)

        if slideTimer > 0 { slideTimer -= dt }
        if hitPoseTimer > 0 { hitPoseTimer -= dt }
        if invulnerable > 0 { invulnerable -= dt }
        if jumpBuffer > 0 { jumpBuffer -= dt }
        if streakTimer > 0 {
            streakTimer -= dt
            if streakTimer <= 0 { streak = 0 }
        }

        checkCollisions()
        guard state == .running else { return }

        let recover = tuning.stormRecoverRate * (monster.ability == .counterstorm ? 2.2 : 1)
        stormDistance = min(tuning.stormStart, stormDistance + recover * dt)
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
            var g = velocityY < 0 ? tuning.gravity * tuning.fallMultiplier : tuning.gravity
            // Origo floats down slowly unless you slam.
            if monster.ability == .glide && velocityY < 0 && velocityY > -tuning.jumpVelocity * 1.2 {
                g *= 0.4
            }
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
            nextSceneryIn += 1.3
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
        let glow = monster.ability == .glow
        if let lowLane, roll < (glow ? 0.5 : 0.35) {
            let offsets = [-2.4, -1.2, 0.0, 1.2, 2.4]
            let heights = [0.5, 0.95, 1.2, 0.95, 0.5]
            for i in 0..<offsets.count {
                addSpool(lane: lowLane, z: z + offsets[i], y: heights[i])
            }
        } else if roll < (glow ? 1.01 : 0.85) {
            for i in 0..<(glow ? 7 : 5) {
                addSpool(lane: freeLane, z: z + Double(i) * 1.2, y: 0.4)
            }
        }
    }

    /// Loads an illustrated PNG from the app bundle, sized to `width` art units (100 per world unit).
    /// Returns nil when the image hasn't been added yet, so the code-drawn stand-in is used instead.
    private var illustratedCache: [String: Art] = [:]
    private func illustrated(_ name: String, width: CGFloat) -> Art? {
        if let cached = illustratedCache[name] { return cached }
        guard let image = UIImage(named: name), image.size.width > 0 else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let art = Art(texture: texture, size: CGSize(width: width, height: width * image.size.height / image.size.width))
        illustratedCache[name] = art
        return art
    }

    private func addHazard(_ kind: HazardKind, lane: Int, z: Double) {
        let hazardArt: Art
        let anchorY: CGFloat
        switch kind {
        case .low:
            if let picture = illustrated("hazard-eraser", width: 100) {
                hazardArt = picture
                anchorY = 0.03
            } else {
                hazardArt = art.eraser
                anchorY = 12.0 / 70.0
            }
        case .overhead:
            if let picture = illustrated("hazard-ruler", width: 105) {
                hazardArt = picture
                anchorY = 0.0
            } else {
                hazardArt = art.ruler
                anchorY = 10.0 / 190.0
            }
        case .crate:
            if let picture = illustrated("hazard-box", width: 100) {
                hazardArt = picture
                anchorY = 0.03
            } else {
                hazardArt = art.box
                anchorY = 10.0 / 160.0
            }
        }
        let sprite = SKSpriteNode(texture: hazardArt.texture, size: hazardArt.size)
        sprite.anchorPoint = CGPoint(x: 0.5, y: anchorY)
        sprite.alpha = 0
        objectLayer.addChild(sprite)
        things.append(Thing(kind: .hazard(kind), sprite: sprite, worldScale: 1,
                            x: Double(lane) * laneWidth, z: z, y: 0))
    }

    private func addSpool(lane: Int, z: Double, y: Double) {
        let spoolArt = illustrated("spool", width: 58) ?? art.spool
        let sprite = SKSpriteNode(texture: spoolArt.texture, size: spoolArt.size)
        sprite.alpha = 0
        objectLayer.addChild(sprite)
        things.append(Thing(kind: .spool, sprite: sprite, worldScale: 0.8,
                            x: Double(lane) * laneWidth, z: z, y: y))
    }

    private func spawnScenery(atZ z: Double) {
        let count = Int.random(in: 2...3)
        for _ in 0..<count {
            let side: Double = Bool.random() ? -1 : 1
            let x = side * Double.random(in: 2.0...4.6)
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
            if illustratedScenery(kind, variant: variant, colored: colored) != nil {
                sprite.anchorPoint = CGPoint(x: 0.5, y: 0.02)
            } else {
                sprite.anchorPoint = CGPoint(x: 0.5, y: (pick.size.height - groundY) / pick.size.height)
            }
            sprite.alpha = 0
            objectLayer.addChild(sprite)
            let thing = Thing(kind: .scenery(kind, variant: variant), sprite: sprite, worldScale: scale,
                              x: x, z: z + Double.random(in: 0...1.2), y: 0)
            thing.colored = colored
            things.append(thing)
        }
    }

    /// Illustrated scenery, used only when both the color and gray versions exist,
    /// so a stitched object swaps to a matching picture.
    private func illustratedScenery(_ kind: SceneryKind, variant: Int, colored: Bool) -> Art? {
        let colorName: String
        let grayName: String
        let width: CGFloat
        switch kind {
        case .tree:
            colorName = "tree-color"
            grayName = "tree-gray"
            width = 120
        case .bush:
            colorName = "bush-color"
            grayName = "bush-gray"
            width = 110
        case .flower:
            colorName = ["flower-pink", "flower-gold", "flower-violet"][variant % 3]
            grayName = "flower-gray"
            width = 44
        }
        guard let color = illustrated(colorName, width: width),
              let gray = illustrated(grayName, width: width) else { return nil }
        return colored ? Art(texture: color.texture, size: gray.size) : gray
    }

    private func sceneryArt(_ kind: SceneryKind, variant: Int, colored: Bool) -> Art {
        if let picture = illustratedScenery(kind, variant: variant, colored: colored) {
            return picture
        }
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

            var reach = 0.55
            if case .spool = thing.kind, monster.ability == .sticky { reach = 1.55 }
            guard abs(thing.x - playerX) < reach else {
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
                if hit, hazard == .crate, monster.ability == .snip, slideTimer > 0 {
                    thing.resolved = true
                    snipThrough(thing)
                    continue
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
        if monster.ability == .shrug && !shrugUsed {
            shrugUsed = true
            invulnerable = 0.9
            eyePop = 0.3
            audio.play(.closeCall)
            haptics.lane()
            shake(strength: 5)
            let point = screenPoint(ofWorld: thing.sprite.position)
            thing.sprite.removeFromParent()
            confettiBurst(at: point)
            popText("Shrugged it off!", size: 24, color: .white, at: playerScreenPoint(offsetY: 130), rise: 40, life: 0.9)
            return
        }
        heartsLeft -= 1
        hitsTaken += 1
        invulnerable = 1.3
        streak = 0
        stormDistance -= tuning.stormHitPenalty * (monster.ability == .ink ? 0.55 : 1)
        meter = max(0, meter - 0.08)
        hitStop = 0.07
        eyePop = 0.6
        hitPoseTimer = 0.45
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
            if handlePickerTap(at: touch.location(in: self)) { return }
            startRun()
            return
        case .over:
            if clock - overAt > 0.8 { startRun() }
            return
        case .paused:
            handlePausedTap(at: touch.location(in: self))
            return
        case .running:
            let point = touch.location(in: self)
            if hud.alpha > 0.5, hypot(point.x - pauseButton.position.x, point.y - pauseButton.position.y) < 34 {
                pauseGame()
                return
            }
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
        eyePop = max(eyePop, 0.35)
        // The illustrated storm flares bright with each lightning strike.
        stormArt?.run(.sequence([
            .colorize(with: .white, colorBlendFactor: 0.35, duration: 0.05),
            .colorize(withColorBlendFactor: 0, duration: 0.35)
        ]))
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

        PaperGround.setDistance(texturedGray, distance)
        PaperGround.setDistance(texturedColor, distance)

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
        renderSkyAndStorm(dt: dt)
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

        let hasPoses = monster.id == "bramble"
        if sliding && state != .over {
            sx = hasPoses ? 1 : 1.25
            sy = hasPoses ? 1 : 0.55
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
        rig.zRotation = CGFloat((laneToX - playerX) * -0.35)

        // Pick the pose. Results: facing you (Bramble cheers or sits dizzy). Running: hit, slide, jump or run.
        let running = state != .over
        let id = monster.id
        if !running {
            if hasPoses && eyeDefeated {
                setPose("bramble-win", height: 150)
            } else if hasPoses && eyeGloat {
                setPose("bramble-lose", height: 150)
            } else {
                setPose("\(id)-front", height: monster.frontHeight)
            }
            if !hasPoses && eyeDefeated {
                // A happy hop for the winners.
                rig.position.y = CGFloat(abs(sin(clock * 5.5))) * 16
            } else if !hasPoses && eyeGloat {
                rig.zRotation = 0.14 * CGFloat(sin(clock * 2))
                rig.yScale = rigBaseScale * 0.92
            }
        } else if hasPoses && hitPoseTimer > 0 {
            setPose("bramble-hit", height: 144)
        } else if hasPoses && sliding {
            setPose("bramble-slide", height: 96)
        } else if hasPoses && airborne {
            setPose("bramble-jump", height: 156)
        } else {
            setPose("\(id)-back", height: monster.runHeight)
        }
        if running && !hasPoses {
            if hitPoseTimer > 0 {
                rig.zRotation += CGFloat(sin(hitPoseTimer * 40) * 0.3)
            } else if !airborne && !sliding {
                // A waddle, since the others only have one back view.
                rig.zRotation += CGFloat(stride) * 0.09
            }
        }
        // Bramble's two-frame run cycle: flip the back view on every stride so the raised foot alternates.
        if running && currentPose == "bramble-back" {
            brambleSprite.xScale = stride >= 0 ? 1 : -1
        } else {
            brambleSprite.xScale = 1
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

    private func renderSkyAndStorm(dt: Double) {
        let m = CGFloat(fullyStitched ? 1 : meter)
        let colorAmount = min(1, m * 1.2)
        skyBlue.alpha = colorAmount
        hillsColor.alpha = colorAmount
        backdropColor?.alpha = colorAmount
        sunSprite.alpha = max(0, (colorAmount - 0.3) / 0.7)
        sunSprite.zRotation = CGFloat(clock * 0.15)
        for (i, cloud) in cloudSprites.enumerated() {
            cloud.alpha = max(0, (colorAmount - 0.15 * CGFloat(i)) * 0.95)
            cloud.position.x += CGFloat(4 + i * 2) * 0.016
            if cloud.position.x > size.width * 1.25 { cloud.position.x = -size.width * 0.25 }
        }

        // The storm wall rises from the bottom of the screen as it closes in.
        let running = state == .running || state == .paused
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
        if let stormArt {
            // Three layers drift at different speeds and shift by different amounts when you
            // change lanes, so the storm has depth. The whole wall swells as it closes in.
            let lane = CGFloat(playerX)
            let swell = 1 + closeness * 0.3
            stormArt.setScale(swell)
            stormArt.position = CGPoint(x: size.width / 2 + CGFloat(cos(clock * 1.1) * 10) - lane * 14,
                                        y: visible - 8 + CGFloat(sin(clock * 3.1) * 5))
            if let far = stormFar {
                far.xScale = -swell
                far.yScale = swell
                far.position = CGPoint(x: size.width / 2 + CGFloat(sin(clock * 0.5) * 26) - lane * 6,
                                       y: stormArt.position.y + far.frame.height * 0.16 + CGFloat(sin(clock * 1.3) * 4))
            }
            if let near = stormNear {
                near.xScale = -swell
                near.yScale = swell
                near.position = CGPoint(x: size.width / 2 + CGFloat(sin(clock * 1.7) * 18) - lane * 28,
                                        y: stormArt.frame.minY - near.frame.height * 0.44 + CGFloat(sin(clock * 2.4) * 6))
            }
            let lowest = min(stormArt.frame.minY, stormNear?.frame.minY ?? stormArt.frame.minY)
            stormFill.position = CGPoint(x: stormArt.position.x, y: lowest + 2)
            updateStormEyes(closeness: closeness, dt: dt)
        }

        // The sky backdrop sits far away: it shifts less than the ground when you change lanes.
        let follow = CGFloat(playerX) * (unitK / CGFloat(camBack)) * 0.3
        let skyX = size.width / 2 + follow * 0.75 + CGFloat(sin(clock * 0.08) * 8)
        backdropGray?.position.x = skyX
        backdropColor?.position.x = skyX
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
            spoolIcon.position.x = size.width - 26 - text.size.width - 14
            fitSpoolPill()
            if grew {
                spoolIcon.removeAction(forKey: "bump")
                spoolIcon.run(.sequence([.scale(to: 1.3, duration: 0.05), .scale(to: 1, duration: 0.1)]), withKey: "bump")
            }
        }
        for (i, heart) in hearts.enumerated() {
            let full = i < heartsLeft
            heart.texture = illustrated(full ? "ui-heart" : "ui-heart-empty", width: 38)?.texture ?? art.heart(full: full).texture
        }
        meterFill.size = CGSize(width: max(0.01, meterWidth * CGFloat(meter)), height: 14)
    }

    /// Blinks, squints and glares. The storm narrows its eyes and turns red as it closes in,
    /// widens them when it lands a hit, gloats when it catches you, and shuts them when you win.
    private func updateStormEyes(closeness: CGFloat, dt: Double) {
        guard let eyes = stormGlare else { return }
        let blinkLength = 0.22
        if eyeBlinkPhase >= 0 {
            eyeBlinkPhase += dt
            if eyeBlinkPhase > blinkLength { eyeBlinkPhase = -1 }
        } else {
            eyeBlinkTimer -= dt
            if eyeBlinkTimer <= 0 {
                eyeBlinkPhase = 0
                // An angry storm stares longer between blinks; now and then it double-blinks.
                eyeBlinkTimer = Double.random(in: 2.2...4.5) + Double(closeness) * 3
                if Double.random(in: 0...1) < 0.25 { eyeBlinkTimer = 0.3 }
            }
        }
        var closed: CGFloat = 0
        if eyeBlinkPhase >= 0 {
            let t = CGFloat(eyeBlinkPhase / blinkLength)
            closed = t < 0.4 ? t / 0.4 : max(0, 1 - (t - 0.4) / 0.6)
        }
        if eyePop > 0 { eyePop = max(0, eyePop - dt) }
        let pop = CGFloat(eyePop / 0.6)

        var squint = 1 - 0.38 * closeness
        var widen = 1 + 0.22 * closeness + 0.35 * pop
        var red = 0.65 * closeness + 0.4 * pop
        if eyeGloat {
            squint = 0.6
            widen = 1.3
            red = 0.85
        }
        if eyeDefeated { closed = max(closed, 0.93) }

        eyes.xScale = widen
        eyes.yScale = max(0.04, squint * (1 + 0.25 * pop) * (1 - closed * 0.96))
        eyes.color = UIColor(red: 1, green: 0.22, blue: 0.08, alpha: 1)
        eyes.colorBlendFactor = min(0.85, red)
        eyes.alpha = 0.88 + 0.12 * CGFloat(sin(clock * (4 + Double(closeness) * 8)))
    }

    // MARK: Monster picker

    /// A paper card on the title screen: the monster, its passive, and arrows to switch.
    private func buildPicker(aboveY bottom: CGFloat) {
        pickerNode?.removeFromParent()
        let w = size.width
        let cardW = min(w - 32, 340)
        let cardH = cardW * 300.0 / 720.0
        pickerWidth = cardW
        let node = SKNode()
        node.position = CGPoint(x: w / 2, y: bottom + cardH / 2)
        node.zPosition = 2
        overlay.addChild(node)
        pickerNode = node

        if let paper = imageSprite("ui-button") {
            paper.size = CGSize(width: cardW, height: cardH)
            node.addChild(paper)
        }

        // Arrows on both ends.
        for side in [CGFloat(-1), 1] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: side * 9, y: 0))
            path.addLine(to: CGPoint(x: -side * 6, y: 11))
            path.addLine(to: CGPoint(x: -side * 6, y: -11))
            path.closeSubpath()
            let arrow = SKShapeNode(path: path)
            arrow.fillColor = Palette.ink
            arrow.strokeColor = .clear
            arrow.position = CGPoint(x: side * (cardW / 2 - 26), y: 0)
            arrow.zPosition = 1
            node.addChild(arrow)
        }

        // The monster, facing you.
        let thumbBox = CGSize(width: cardW * 0.27, height: cardH * 0.76)
        let thumbX = -cardW / 2 + 44 + thumbBox.width / 2
        if let thumb = imageSprite("\(monster.id)-front") {
            let scale = min(thumbBox.width / thumb.size.width, thumbBox.height / thumb.size.height)
            thumb.size = CGSize(width: thumb.size.width * scale, height: thumb.size.height * scale)
            thumb.position = CGPoint(x: thumbX, y: 0)
            thumb.zPosition = 1
            node.addChild(thumb)
            thumb.setScale(0.8)
            thumb.run(.scale(to: 1, duration: 0.12))
        }

        // Name, passive, and best score.
        let textX = thumbX + thumbBox.width / 2 + 8
        let name = art.text(monster.name, size: min(23, cardW * 0.07), fill: Palette.stitchGold)
        let nameSprite = SKSpriteNode(texture: name.texture, size: name.size)
        nameSprite.anchorPoint = CGPoint(x: 0, y: 0.5)
        nameSprite.position = CGPoint(x: textX - 4, y: cardH * 0.16)
        nameSprite.zPosition = 1
        node.addChild(nameSprite)

        let passive = art.text(monster.passive, size: min(12, cardW * 0.036), fill: .white, style: .body)
        let passiveSprite = SKSpriteNode(texture: passive.texture, size: passive.size)
        passiveSprite.anchorPoint = CGPoint(x: 0, y: 0.5)
        passiveSprite.position = CGPoint(x: textX - 2, y: -cardH * 0.07)
        passiveSprite.zPosition = 1
        node.addChild(passiveSprite)

        let best = UserDefaults.standard.integer(forKey: "bestSpools")
        let index = Monster.selectedIndex
        let footer = best > 0 ? "\(index + 1) of \(Monster.roster.count)  \u{00B7}  Best: \(best)" : "\(index + 1) of \(Monster.roster.count)"
        let footerArt = art.text(footer, size: min(11, cardW * 0.032), fill: .white, style: .body)
        let footerSprite = SKSpriteNode(texture: footerArt.texture, size: footerArt.size)
        footerSprite.anchorPoint = CGPoint(x: 0, y: 0.5)
        footerSprite.position = CGPoint(x: textX - 2, y: -cardH * 0.26)
        footerSprite.zPosition = 1
        node.addChild(footerSprite)

        // Long names or lines shrink to stay clear of the right arrow.
        let maxWidth = cardW / 2 - 40 - textX
        for sprite in [nameSprite, passiveSprite, footerSprite] where sprite.size.width > maxWidth {
            sprite.setScale(maxWidth / sprite.size.width)
        }
    }

    /// Arrows switch monsters; tapping the card goes to the next one. Returns true when the tap was used.
    private func handlePickerTap(at point: CGPoint) -> Bool {
        guard let node = pickerNode else { return false }
        let cardH = pickerWidth * 300.0 / 720.0
        let dx = point.x - node.position.x
        let dy = point.y - node.position.y
        guard abs(dx) < pickerWidth / 2 + 10, dy > -cardH / 2, dy < cardH / 2 + 10 else { return false }
        let step = dx < -pickerWidth * 0.32 ? -1 : 1
        Monster.selectedIndex = Monster.selectedIndex + step
        monster = Monster.roster[Monster.selectedIndex]
        currentPose = ""
        audio.chime(step: Monster.selectedIndex % 5)
        haptics.lane()
        buildPicker(aboveY: node.position.y - cardH / 2)
        return true
    }

    /// Snipjaw slices a box in half instead of crashing into it.
    private func snipThrough(_ thing: Thing) {
        let point = screenPoint(ofWorld: thing.sprite.position)
        thing.sprite.removeFromParent()
        confettiBurst(at: point)
        audio.play(.closeCall)
        haptics.spool()
        spools += 2
        popText("Snip! +2", size: 24, color: .white, at: playerScreenPoint(offsetY: 120), rise: 40, life: 0.8)
    }

    /// Swaps the runner's picture, keeping the feet on the ground and the body a steady size.
    private func setPose(_ name: String, height: CGFloat) {
        guard name != currentPose else { return }
        let entry: (texture: SKTexture, size: CGSize)
        if let cached = poseTextures[name] {
            entry = cached
        } else {
            guard let image = UIImage(named: name) else { return }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            entry = (texture, image.size)
            poseTextures[name] = entry
        }
        currentPose = name
        brambleSprite.xScale = 1
        brambleSprite.texture = entry.texture
        brambleSprite.size = CGSize(width: height * entry.size.width / entry.size.height, height: height)
    }

    // MARK: Pause

    @objc private func appWillResignActive() {
        if state == .paused && resumeCountdown > 0 { state = .running }
        if state == .running { pauseGame() }
    }

    private func pauseGame() {
        guard state == .running else { return }
        state = .paused
        resumeCountdown = 0
        trackedTouch = nil
        audio.setMusic(playing: false)
        haptics.lane()

        overlay.removeAllChildren()
        let w = size.width
        let h = size.height
        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.4), size: size)
        dim.anchorPoint = .zero
        overlay.addChild(dim)

        let cardW = min(w - 60, 320)
        let cardH = cardW * 855.0 / 1140.0
        let card = SKNode()
        card.position = CGPoint(x: w / 2, y: h * 0.56)
        overlay.addChild(card)
        if let paper = imageSprite("ui-card") {
            paper.size = CGSize(width: cardW, height: cardH)
            card.addChild(paper)
        }
        let title = art.text("Paused", size: 30, fill: .white)
        let titleSprite = SKSpriteNode(texture: title.texture, size: title.size)
        titleSprite.position = CGPoint(x: 0, y: cardH * 0.17)
        titleSprite.zPosition = 1
        card.addChild(titleSprite)

        let resume = paperButton("Resume", width: min(210, cardW * 0.68))
        resume.name = "resume"
        resume.position = CGPoint(x: 0, y: -cardH * 0.14)
        resume.zPosition = 1
        card.addChild(resume)

        let quit = paperButton("Quit", width: 140)
        quit.name = "quit"
        quit.removeAllActions()
        quit.position = CGPoint(x: w / 2, y: card.position.y - cardH / 2 - 44)
        overlay.addChild(quit)

        card.setScale(0.8)
        card.run(.scale(to: 1, duration: 0.15))
    }

    private func handlePausedTap(at point: CGPoint) {
        guard resumeCountdown <= 0 else { return }
        for node in nodes(at: point) {
            var current: SKNode? = node
            while let candidate = current {
                if candidate.name == "resume" {
                    resumeGame()
                    return
                }
                if candidate.name == "quit" {
                    showTitle()
                    return
                }
                current = candidate.parent
            }
        }
    }

    private func resumeGame() {
        fadeOverlay()
        haptics.lane()
        resumeCountdown = 2.4
        shownCountdown = 0
    }

    /// 3, 2, 1, Go: gives the player a moment to get ready after a pause.
    private func stepCountdown(_ dt: Double) {
        guard resumeCountdown > 0 else { return }
        resumeCountdown -= dt
        let number = Int(ceil(resumeCountdown / 0.8))
        if number != shownCountdown && number > 0 {
            shownCountdown = number
            audio.chime(step: 3 - number)
            popText("\(number)", size: 64, color: .white, at: CGPoint(x: size.width / 2, y: size.height * 0.56), rise: 0, life: 0.6)
        }
        if resumeCountdown <= 0 {
            state = .running
            audio.setMusic(playing: true)
            audio.play(.start, volume: 0.6)
            popText("Go!", size: 52, color: Palette.stitchGold, at: CGPoint(x: size.width / 2, y: size.height * 0.56), rise: 30, life: 0.6)
        }
    }

    /// Sizes the paper pill to wrap the spool icon and count.
    private func fitSpoolPill() {
        let left = spoolIcon.position.x - 14
        let right = size.width - 26
        spoolPill.size = CGSize(width: (right - left) + 28, height: 37)
        spoolPill.position.x = (left + right) / 2
    }

    private func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}
