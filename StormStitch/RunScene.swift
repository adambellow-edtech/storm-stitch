import SpriteKit
import UIKit

/// Storm Stitch vertical slice: Notebook Meadow, with the full cast of eight monsters.
/// The world starts gray and torn. Every spool you grab stitches color back in
/// around you, and the storm chases from behind. Drawn with a simple pseudo-3D
/// projection so the camera sits behind the runner, like the hero style frame.
final class RunScene: SKScene {

    // MARK: Types

    enum State { case title, menu, story, running, paused, celebrating, over }

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
            case gate
            /// One of a pick-3 power gate's paper doors, by slot (0 left, 1 middle, 2 right).
            case powerDoor(Int)
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
        /// Taken out of the world (collected, crashed into, erased or passed), kept for the Time Machine.
        var retired = false
        var removedAt = 0.0
        var removedZ = 0.0
        /// Distance run when this thing appeared, so the Time Machine can unspawn it.
        var spawnedAt = 0.0

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

    let tuning: Tuning
    let haptics = Haptics()
    let audio = GameAudio.shared
    let art = PaperArt.shared

    // Camera matched to the K2 gameplay reference: high and behind, long road, runner in the lower third.
    let camHeight = 4.8
    let camBack = 3.6
    let laneWidth = 1.0
    let spawnZ = 46.0
    let dashSpacing = 3.0
    let dashLength = 1.3
    let dashesPerDivider = 26
    let rigBaseScale: CGFloat = 0.9
    let landSquashTime = 0.14
    let jumpBufferTime = 0.12
    let titleSpeed = 4.0

    var horizonY: CGFloat = 0
    var unitK: CGFloat = 0

    // MARK: Nodes

    let camRig = SKNode()
    let worldRoot = SKNode()
    let skyGray = SKSpriteNode(color: Palette.stormGray, size: CGSize(width: 10, height: 10))
    let skyBlue = SKSpriteNode(color: UIColor(hex: 0x8FD3FF), size: CGSize(width: 10, height: 10))
    var sunSprite = SKSpriteNode()
    var cloudSprites: [SKSpriteNode] = []
    var hillsGray = SKSpriteNode()
    var hillsColor = SKSpriteNode()
    /// Illustrated sky-and-hills backdrop; the gray version shows until color floods in.
    var backdropGray: SKSpriteNode?
    /// Shader-drawn paper road and ground (gray, and color revealed by stitching).
    var texturedGray: SKSpriteNode?
    var texturedColor: SKSpriteNode?
    var backdropColor: SKSpriteNode?
    let groundLayer = SKNode()
    let colorCrop = SKCropNode()
    let maskRoot = SKNode()
    let colorLayer = SKNode()
    let stitchLayer = SKNode()
    let dashLayer = SKNode()
    let objectLayer = SKNode()
    var dashes: [SKSpriteNode] = []

    let playerNode = SKNode()
    let rig = SKNode()
    var brambleSprite = SKSpriteNode()
    /// Bramble built from separate painted parts on joints, for the run and the jump.
    /// Nil if the rig art isn't in the app; the painted poses cover everything then.
    var cutout: CutoutRig?
    /// Which monster `cutout` belongs to, and every rig loaded so far (nil: that monster has no rig art yet).
    var cutoutID = ""
    var cutoutCache: [String: CutoutRig?] = [:]
    /// The same for the front-facing rig on the results card: an armless body and swappable arms.
    var frontCutout: CutoutRig?
    var frontCutoutID = ""
    var frontCutoutCache: [String: CutoutRig?] = [:]
    /// The monster just picked in a menu: its next portrait cheers and waves hello once.
    var portraitGreetID: String?
    let brambleBack = SKTexture(imageNamed: "bramble-back")
    let brambleFront = SKTexture(imageNamed: "bramble-front")
    /// Illustrated poses, loaded on first use: name to texture and pixel size.
    var poseTextures: [String: (texture: SKTexture, size: CGSize)] = [:]
    var currentPose = ""
    /// The monster running this session, and title-screen picker state.
    var monster = Monster.roster[Monster.selectedIndex]
    var pickerNode: SKNode?
    var pickerWidth: CGFloat = 0
    /// Bramble's once-per-run shrug.
    var shrugUsed = false
    var hitPoseTimer = 0.0
    /// Pause button in the HUD, and the 3-2-1 countdown when resuming.
    let pauseButton = SKNode()
    var resumeCountdown = 0.0
    var shownCountdown = 0
    var playerShadow = SKSpriteNode()

    let stormRoot = SKNode()
    var stormBack = SKSpriteNode()
    var stormFront = SKSpriteNode()
    /// Illustrated storm wall (eyes included) and the solid cloud base that fills below it.
    var stormArt: SKSpriteNode?
    /// Parallax storm layers: a dark one drifting behind, one rolling in front.
    var stormFar: SKSpriteNode?
    var stormNear: SKSpriteNode?
    /// The storm's glowing eyes, on their own layer so they can blink, squint and glare.
    var stormGlare: SKSpriteNode?
    var eyeBlinkTimer = 2.5
    var eyeBlinkPhase = -1.0
    var eyePop = 0.0
    var eyeGloat = false
    var eyeDefeated = false
    let stormFill = SKSpriteNode(color: UIColor(hex: 0x605362), size: CGSize(width: 10, height: 10))
    /// Eye line in the storm picture, measured up from its bottom edge.
    let stormEyeLine: CGFloat = 0.31
    var stormEyes: [SKSpriteNode] = []
    var stormScraps: SKEmitterNode?

    let fxRoot = SKNode()
    let hud = SKNode()
    let flash = SKSpriteNode(color: .white, size: CGSize(width: 10, height: 10))
    let vignette = SKSpriteNode(color: UIColor(hex: 0xFF3B30), size: CGSize(width: 10, height: 10))
    var timerSprite = SKSpriteNode()
    var spoolIcon = SKSpriteNode()
    var spoolCountSprite = SKSpriteNode()
    let timerPill = SKSpriteNode()
    let spoolPill = SKSpriteNode()
    var hearts: [SKSpriteNode] = []
    let meterBack = SKShapeNode()
    let meterFill = SKSpriteNode(color: Palette.stitchGold, size: CGSize(width: 10, height: 10))
    var meterLabel = SKSpriteNode()
    var meterWidth: CGFloat = 180
    let overlay = SKNode()

    // MARK: Run state

    var state: State = .title
    var things: [Thing] = []
    var patches: [Patch] = []
    var lastUpdate: TimeInterval = 0
    var overAt = 0.0
    var clock = 0.0
    var elapsed = 0.0
    var distance = 0.0
    var runSpeed = 0.0
    var nextRowIn = 0.0
    var nextSceneryIn = 0.0
    var nextPatchIn = 0.0
    var heartsLeft = 3
    var hitsTaken = 0
    var spools = 0
    var streak = 0
    var bestStreak = 0
    var streakTimer = 0.0
    var meter = 0.0
    var fullyStitched = false
    var stormDistance = 6.0
    var invulnerable = 0.0
    var timeScale = 1.0
    var hitStop = 0.0
    var shownSeconds = -1
    var shownSpools = -1
    var nextThunder = 6.0
    /// How close the storm has come this run (0 far ... 3 almost on you); crossing up a band cracks lightning.
    var stormBand = 0
    /// How far the whole view has risen so the runner stays clear of a growing storm.
    var viewLift: CGFloat = 0
    /// Height of the storm art above its anchor, measured last frame, for keeping it below the runner.
    var stormTopAbove: CGFloat = 0
    var lightningCooldown = 0.0

    // MARK: Modes, gadgets and menus

    var mode: RunMode = .endless
    var config = RunConfig(length: .infinity, startSpeed: 9, endSpeed: 15, rampTime: 120, intervalStart: 1,
                           intervalEnd: 0.62, overheadFrom: 15, doubleChance: 0.45, meterPerSpool: 0.012,
                           rule: .calm, seed: 1, hints: false)
    var rng = GameRNG(seed: 1)
    var gustRNG = GameRNG(seed: 2)
    var stats = RunStats()
    var closeCalls = 0
    var gateSpawned = false
    var gateThing: Thing?
    var celebrationSpeed = 0.0
    var fullyStitchedBeforeGate = false
    var gadget: Gadget?
    var gadgetCharge = 0
    var shieldActive = false
    var magnetTimer = 0.0
    var planeTimer = 0.0
    var inkTimer = 0.0
    var foldTimer = 0.0
    var rewindsThisRun = 0
    let gadgetButton = SKNode()
    let gadgetRing = SKShapeNode()
    let gadgetIcon = SKSpriteNode()
    let shieldRing = SKShapeNode()
    let planeSprite = SKSpriteNode()
    var snapshots: [RunSnapshot] = []
    var snapshotTimer = 0.0
    var graveyard: [Thing] = []
    var gustTimer = 6.0
    var gustWarned = false
    var gustDirection = 1
    let nightShade = SKSpriteNode()
    var theme: Theme?
    /// The world the stage map last showed, so menus return to it.
    var mapWorld: Int?
    var themeApplied = false
    var holidayEmitters: [SKEmitterNode] = []
    let rivalSprite = SKSpriteNode()
    var rivalX = 1.0
    var rivalTargetX = 1.0
    var rivalLaneTimer = 0.0
    let rivalLabel = SKSpriteNode()
    var shownRival = -1
    var tapTargets: [(node: SKNode, action: () -> Void)] = []
    var story: StoryPlayer?
    var hintIndex = 0
    /// Pick-3 power gates (PowerGates.swift).
    var powers = PowerState()
    let powerRow = SKNode()
    var frontBlinkTimer = 2.5
    var lastRenderDt = 0.0

    // MARK: Player state

    var laneIndex = 0
    var playerX = 0.0
    var laneFromX = 0.0
    var laneToX = 0.0
    var laneProgress = 1.0
    var lastLaneChange = -10.0
    /// True when the run just finished was today's first (scored) Daily Storm.
    var lastRunCountedDaily = false
    var lastLaneFrom = 0
    var playerY = 0.0
    var velocityY = 0.0
    var slideTimer = 0.0
    var landSquash = 0.0
    var jumpBuffer = 0.0
    var runPhase = 0.0
    /// Spring follow-through that makes the runner's body lag, bend, wobble and settle.
    var jelly = JellyBody()

    // MARK: Touch state

    var trackedTouch: UITouch?
    var touchStart = CGPoint.zero
    var didSwipe = false
    var lastSwipeDir = 0

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
            buildGadgetButton()
            syncSettings()
            audio.start()
            NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
                                                   name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(linkOpened),
                                                   name: DeepLink.opened, object: nil)
        }
        layoutScene()
        if size.width > 10 && size.height > 10 && state == .title {
            showTitle()
            if !Progress.shared.data.storySeen { playStory() }
        }
    }

    @objc func linkOpened() {
        if state == .title || state == .menu || state == .over { checkPendingLink() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard camRig.parent != nil, size.width > 10, size.height > 10 else { return }
        layoutScene()
        if state == .title { showTitle() }
    }

    func buildNodeTree() {
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

        nightShade.texture = makeNightShade()
        nightShade.alpha = 0
        nightShade.zPosition = 590
        addChild(nightShade)
        rivalSprite.isHidden = true
        objectLayer.addChild(rivalSprite)

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

    func buildPlayer() {
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

    func buildStorm() {
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

        let hasEyeLayer = artImage("storm-wall-noeyes") != nil && artImage("storm-eyes") != nil
        if let image = artImage(hasEyeLayer ? "storm-wall-noeyes" : "storm-wall") {
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

            if hasEyeLayer, let eyeImage = artImage("storm-eyes") {
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
            // Below the torn edge the storm deepens to dark ink instead of a flat gray band,
            // which showed on tall phones when the wall rises to its highest point.
            stormFill.texture = stormFillTexture()
            stormFill.color = .white
            stormFill.colorBlendFactor = 0
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

    func buildHUD() {
        for _ in 0..<3 {
            let heartArt = illustrated("ui-heart", width: 38) ?? art.heart(full: true)
            let heart = SKSpriteNode(texture: heartArt.texture, size: CGSize(width: 38, height: 38 * heartArt.size.height / heartArt.size.width))
            hud.addChild(heart)
            hearts.append(heart)
        }

        // Paper pause button, top left.
        let pausePaper = SKSpriteNode()
        if let image = artImage("ui-pill") {
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

        // The same paper spool the player collects on the road.
        let spoolArt = illustrated("spool", width: 30) ?? art.spool
        let spoolH = min(34, 30 * spoolArt.size.height / max(1, spoolArt.size.width))
        spoolIcon = SKSpriteNode(texture: spoolArt.texture, size: CGSize(width: 30, height: spoolH))
        hud.addChild(spoolIcon)
        spoolCountSprite.anchorPoint = CGPoint(x: 1, y: 0.5)
        hud.addChild(spoolCountSprite)
        timerSprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        hud.addChild(timerSprite)

        // Paper pills behind the timer and the spool count.
        for pill in [timerPill, spoolPill] {
            if let image = artImage("ui-pill") {
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

        rivalLabel.isHidden = true
        hud.addChild(rivalLabel)
    }

    func layoutScene() {
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
        let themedGray = theme?.backdropGray.flatMap { artImage($0) }
        let themedColor = theme?.backdropColor.flatMap { artImage($0) }
        if let grayImage = themedGray ?? artImage("backdrop-gray"), let colorImage = themedColor ?? artImage("backdrop-color") {
            if let gray = backdropGray, let color = backdropColor {
                // A different world may be showing: swap in its sky.
                gray.texture = SKTexture(image: grayImage)
                color.texture = SKTexture(image: colorImage)
            }
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
                                        camHeight: camHeight, camBack: camBack, centerX: w / 2,
                                        roadName: theme?.roadGray, groundName: theme?.groundGray)
        texturedColor = PaperGround.make(colored: true, rect: shaderRect, horizonY: horizonY, unitK: unitK,
                                         camHeight: camHeight, camBack: camBack, centerX: w / 2,
                                         roadName: theme?.roadColor, groundName: theme?.groundColor)
        if let texturedGray, let texturedColor {
            groundLayer.addChild(texturedGray)
            colorLayer.addChild(texturedColor)
            applyFog()
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
        if let stormArt, let image = artImage("storm-wall") {
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
        nightShade.size = CGSize(width: max(w, h) * 2.6, height: max(w, h) * 2.6)
        let bottomInset = max(view?.safeAreaInsets.bottom ?? 0, 16)
        gadgetButton.position = CGPoint(x: w - 52, y: bottomInset + 58)
        rivalLabel.position = CGPoint(x: 70, y: h - max(view?.safeAreaInsets.top ?? 0, 20) - 70)
        for emitter in holidayEmitters {
            emitter.position = CGPoint(x: w / 2, y: h + 30)
            emitter.particlePositionRange = CGVector(dx: w * 1.3, dy: 0)
        }

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

    func makeRoadPath() -> CGPath? {
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
    func project(x: Double, z: Double, y: Double = 0) -> (point: CGPoint, scale: CGFloat, depth: Double)? {
        let depth = z + camBack
        guard depth > 0.25 else { return nil }
        let s = CGFloat(1.0 / depth)
        let px = size.width / 2 + CGFloat(x) * s * unitK
        let py = horizonY - CGFloat(camHeight - y) * s * unitK
        return (CGPoint(x: px, y: py), s * unitK / 100, depth)
    }

    func screenPoint(ofWorld point: CGPoint) -> CGPoint {
        worldRoot.convert(point, to: self)
    }

    // MARK: Screens

    /// A sprite from a bundled PNG at its native pixel size; callers set the display size.
    func imageSprite(_ name: String) -> SKSpriteNode? {
        guard let image = artImage(name) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return SKSpriteNode(texture: texture, size: image.size)
    }

    /// A paper button with a label, sized by width.
    func paperButton(_ label: String, width: CGFloat, pulse: Bool = true) -> SKNode {
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
        if textSprite.size.width > width * 0.82 { textSprite.setScale(width * 0.82 / textSprite.size.width) }
        node.addChild(textSprite)
        if pulse {
            node.run(.repeatForever(.sequence([
                .scale(to: 1.05, duration: 0.55),
                .scale(to: 1.0, duration: 0.55)
            ])))
        }
        return node
    }

    /// Fades out whatever is on the overlay instead of cutting it.
    func fadeOverlay() {
        let leaving = SKNode()
        leaving.zPosition = overlay.zPosition
        addChild(leaving)
        for child in overlay.children {
            child.move(toParent: leaving)
        }
        leaving.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))
    }

    // MARK: Run flow

    func resetWorld() {
        for thing in things { thing.sprite.removeFromParent() }
        things.removeAll()
        graveyard.removeAll()
        snapshots.removeAll()
        snapshotTimer = 0
        rng = GameRNG(seed: config.seed)
        gustRNG = GameRNG(seed: config.seed &+ 99)
        gustTimer = 6
        gustWarned = false
        closeCalls = 0
        gateSpawned = false
        gateThing = nil
        fullyStitchedBeforeGate = false
        gadgetCharge = 0
        shieldActive = false
        shieldRing.isHidden = true
        lastLaneChange = -10
        lastLaneFrom = 0
        magnetTimer = 0
        planeTimer = 0
        inkTimer = 0
        foldTimer = 0
        rewindsThisRun = 0
        hintIndex = 0
        removeAction(forKey: "celebrate")
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
        stormBand = 0
        lightningCooldown = 0
        removeAction(forKey: "defeatAudio")

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
        jelly.reset()
        jumpBuffer = 0
        trackedTouch = nil

        // Pre-fill the scenery so the world isn't empty at the start.
        var z = 2.0
        while z < spawnZ {
            spawnScenery(atZ: z)
            z += 1.3
        }
        resetPowers()
    }

    /// Totals for the run that just ended.
    func makeStats(finished: Bool) -> RunStats {
        var result = RunStats()
        result.spools = spools
        result.distance = distance
        result.hits = hitsTaken
        result.closeCalls = closeCalls
        result.bestStreak = bestStreak
        result.stitched = finished ? fullyStitchedBeforeGate : fullyStitched
        result.meterPercent = Int(min(1, meter) * 100)
        result.elapsed = elapsed
        result.finished = finished
        result.rewinds = rewindsThisRun
        result.powers = powers.taken.map { (kind: $0, level: powerLevel($0)) }
        return result
    }

    func starsFor(_ result: RunStats) -> Int {
        switch mode {
        case .stage(let index):
            guard result.finished else { return 0 }
            return 1 + (Stage.all[index].challenge.met(by: result) ? 1 : 0) + (result.stitched ? 1 : 0)
        case .race(let holiday):
            guard result.finished, result.spools > holiday.rivalTarget else { return 0 }
            return 1 + (result.hits == 0 ? 1 : 0) + (result.stitched ? 1 : 0)
        case .endless:
            return (result.distance >= 1000 ? 1 : 0) + (result.hits == 0 ? 1 : 0) + (result.stitched ? 1 : 0)
        case .daily, .challenge:
            return (result.finished ? 1 : 0) + (result.hits == 0 ? 1 : 0) + (result.stitched ? 1 : 0)
        }
    }

    /// Saves the run, reports scores, and shows the results.
    func concludeRun(caught: Bool, finished: Bool) {
        state = .over
        overAt = clock
        trackedTouch = nil
        stats = makeStats(finished: finished)
        let stars = starsFor(stats)
        if case .daily(let storm) = mode {
            lastRunCountedDaily = Progress.shared.data.dailyScores[storm.key] == nil
        } else {
            lastRunCountedDaily = false
        }
        let unlocks = Progress.shared.record(stats, mode: mode, stars: stars)
        switch mode {
        case .daily:
            // Only the first run of the day counts; practice runs stay off the board.
            if lastRunCountedDaily { GameCenter.submit(stats.score, to: GameCenter.dailyBoard) }
        case .endless:
            GameCenter.submit(stats.score, to: GameCenter.endlessBoard)
        case .stage:
            GameCenter.submit(Progress.shared.totalStars, to: GameCenter.starsBoard)
        default:
            break
        }
        gadgetButton.isHidden = true
        rivalLabel.isHidden = true
        rivalSprite.isHidden = true
        clearActiveEffects()
        showRunResults(caught: caught, finished: finished, stars: stars, unlocks: unlocks)
    }

    func endRun(caught: Bool) {
        eyeGloat = true
        let chaseFinale = shredderChase != nil
        audio.setMusic(playing: false)
        audio.setChase(false)
        // The Shredder wins: one last strike, an evil laugh, then one sting. A chase finale gets the
        // Shredder's own defeat sting; any other run gets the playful fail sting. (The old quick
        // game-over blip is retired so the stings never double up.)
        lightningCooldown = 0
        lightningStrike(power: 3)
        run(.sequence([
            .wait(forDuration: 0.35),
            .run { [weak self] in
                guard let self, self.state != .running else { return }
                self.audio.play(.evilLaugh)
            },
            .wait(forDuration: 3.5),
            .run { [weak self] in
                guard let self, self.state != .running else { return }
                if chaseFinale {
                    self.audio.play(.defeat, volume: 0.8)
                } else {
                    self.audio.playSting(.fail)
                }
            }
        ]), withKey: "defeatAudio")
        haptics.gameOver()
        concludeRun(caught: caught, finished: false)
    }

    func finishRun() {
        eyeDefeated = true
        audio.setMusic(playing: false)
        audio.setChase(false)
        // A win gets the victory fanfare; reaching the gate behind a holiday rival is still a loss.
        var won = true
        if case .race(let holiday) = mode { won = spools > holiday.rivalTarget }
        audio.playSting(won ? .victory : .fail)
        haptics.success()
        concludeRun(caught: false, finished: true)
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
        if inkTimer > 0 && state == .running { dt *= 0.5 }

        switch state {
        case .running:
            step(dt)
        case .paused:
            stepCountdown(realDt)
        case .celebrating:
            stepCelebration(dt)
        case .title, .menu, .story, .over:
            ambient(dt)
        }
        render(dt: realDt)
    }

    /// Title and results screens: the world keeps drifting by so it feels alive.
    func ambient(_ dt: Double) {
        runSpeed += ((state == .over ? 0 : titleSpeed) - runSpeed) * min(1, dt * 2)
        advanceWorld(runSpeed * dt, dt: dt)
        if laneProgress < 1 {
            laneProgress = min(1, laneProgress + dt / 0.2)
            playerX = laneFromX + (laneToX - laneFromX) * (1 - pow(1 - laneProgress, 2))
        }
        updatePlayerPhysics(dt)
    }

    func step(_ dt: Double) {
        elapsed += dt
        let t = min(elapsed / max(config.rampTime, 1), 1)
        runSpeed = lerp(config.startSpeed, config.endSpeed, t) * (foldTimer > 0 ? 3.5 : 1)
        let move = runSpeed * dt
        advanceWorld(move, dt: dt)

        nextRowIn -= move
        if nextRowIn <= 0 {
            if elapsed < config.length - 4.5 && !rowsHeldForPowerGate {
                spawnRow(atZ: spawnZ + nextRowIn)
            }
            let interval = lerp(config.intervalStart, config.intervalEnd, t)
            nextRowIn += max(lerp(config.startSpeed, config.endSpeed, t) * interval, 4.5)
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
            if streakTimer <= 0 && !savePowerStreak() { streak = 0 }
        }

        checkCollisions()
        guard state == .running else { return }
        stepExtras(dt)
        guard state == .running else { return }

        let recover = tuning.stormRecoverRate * (monster.ability == .counterstorm ? 2.2 : 1) * stormBrakeMultiplier
        stormDistance = min(tuning.stormStart, stormDistance + recover * dt)
        if stormDistance <= 0 {
            endRun(caught: true)
            return
        }

        let closeness = 1 - stormDistance / max(tuning.stormStart, 0.1)
        lightningCooldown -= dt
        // The bigger the storm gets, the more it crackles: crossing into a closer band strikes lightning.
        let band = closeness > 0.85 ? 3 : closeness > 0.6 ? 2 : closeness > 0.35 ? 1 : 0
        if band > stormBand {
            lightningStrike(power: band)
        }
        if band > stormBand || closeness < [0, 0.27, 0.52, 0.77][stormBand] {
            stormBand = band
        }
        nextThunder -= dt
        if nextThunder <= 0 {
            nextThunder = Double.random(in: 5...10) * (1 - closeness * 0.6)
            if closeness > 0.5 {
                lightningStrike(power: closeness > 0.8 ? 2 : 1)
            } else {
                thunderFlash(strength: 0.25 + closeness * 0.4)
            }
        }

        audio.setIntensity(Float(0.3 + t * 0.5 + closeness * 0.4))
        updateHUD()
    }

    func updatePlayerPhysics(_ dt: Double) {
        if planeTimer > 0 {
            // The Paper Plane cruises above the hazards.
            playerY += (2.1 - playerY) * min(1, dt * 5)
            velocityY = 0
            return
        }
        if playerY > 0 || velocityY > 0 {
            var g = velocityY < 0 ? tuning.gravity * tuning.fallMultiplier : tuning.gravity
            // Origo floats down slowly unless you slam.
            if monster.ability == .glide && velocityY < 0 && velocityY > -tuning.jumpVelocity * 1.2 {
                g *= 0.4
            }
            // Comet hangs in the air a little longer.
            if monster.ability == .bounce && velocityY > -tuning.jumpVelocity * 1.2 {
                g *= 0.8
            }
            velocityY -= g * dt
            playerY += velocityY * dt
            if playerY <= 0 {
                playerY = 0
                // A slam lands harder than a normal fall.
                jelly.land(hard: velocityY < -tuning.jumpVelocity * 1.4)
                velocityY = 0
                landed()
            }
        }
        if landSquash > 0 { landSquash -= dt }
        if playerY <= 0 && slideTimer <= 0 {
            runPhase += runSpeed * dt * 0.95
        }
    }

    func advanceWorld(_ move: Double, dt: Double) {
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
                if case .scenery = thing.kind {
                    thing.sprite.removeFromParent()
                } else {
                    retire(thing)
                }
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

    func spawnRow(atZ z: Double) {
        // Every choice comes from the run's seeded generator, so a daily course is the same for everyone.
        var lanes = [-1, 0, 1].shuffled(using: &rng)
        let freeLane = lanes.removeFirst()
        let hazardCount = Double.random(in: 0...1, using: &rng) < config.doubleChance ? 2 : 1
        let allowed: [HazardKind] = elapsed < config.overheadFrom ? [.low, .crate] : HazardKind.allCases
        // A Shredder chase can lean on its world's signature hazards.
        let chaseMix = shredderChase?.hazardMix?.filter { allowed.contains($0) } ?? []
        let pool = chaseMix.isEmpty ? allowed : chaseMix

        var lowLane: Int?
        for i in 0..<hazardCount {
            let kind = pool.randomElement(using: &rng) ?? .low
            addHazard(kind, lane: lanes[i], z: z)
            if kind == .low { lowLane = lanes[i] }
        }

        let roll = Double.random(in: 0...1, using: &rng)
        let glow = monster.ability == .glow
        let rain = config.rule == .spoolRain
        if let lowLane, roll < (glow || rain ? 0.5 : 0.35) {
            let offsets = [-2.4, -1.2, 0.0, 1.2, 2.4]
            let heights = [0.5, 0.95, 1.2, 0.95, 0.5]
            for i in 0..<offsets.count {
                addSpool(lane: lowLane, z: z + offsets[i], y: heights[i])
            }
        } else if roll < (glow || rain ? 1.01 : 0.85) {
            for i in 0..<(glow ? 7 : 5) {
                addSpool(lane: freeLane, z: z + Double(i) * 1.2, y: 0.4)
            }
        }
        // Spool Rain fills the other open lane too.
        if rain && hazardCount == 1 && lanes.count > 1 {
            for i in 0..<5 {
                addSpool(lane: lanes[1], z: z + 0.6 + Double(i) * 1.2, y: 0.4)
            }
        }
    }

    /// Loads an illustrated PNG from the app bundle, sized to `width` art units (100 per world unit).
    /// Returns nil when the image hasn't been added yet, so the code-drawn stand-in is used instead.
    var illustratedCache: [String: Art] = [:]
    /// A vertical gradient from the near storm layer's bottom color down to deep ink.
    func stormFillTexture() -> SKTexture {
        let size = CGSize(width: 4, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(hex: 0x55485C).cgColor, UIColor(hex: 0x3A3048).cgColor, UIColor(hex: 0x2B2340).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.05, 0.14]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [.drawsAfterEndLocation])
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    func illustrated(_ name: String, width: CGFloat) -> Art? {
        if let cached = illustratedCache[name] { return cached }
        guard let image = artImage(name), image.size.width > 0 else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let art = Art(texture: texture, size: CGSize(width: width, height: width * image.size.height / image.size.width))
        illustratedCache[name] = art
        return art
    }

    func addHazard(_ kind: HazardKind, lane: Int, z: Double) {
        let hazardArt: Art
        let anchorY: CGFloat
        switch kind {
        case .low:
            if let name = theme?.lowHazard, let picture = illustrated(name, width: 100) {
                hazardArt = picture
                anchorY = 0.03
            } else if let picture = illustrated("hazard-eraser", width: 100) {
                hazardArt = picture
                anchorY = 0.03
            } else {
                hazardArt = art.eraser
                anchorY = 12.0 / 70.0
            }
        case .overhead:
            if let name = theme?.overheadHazard, let picture = illustrated(name, width: 105) {
                hazardArt = picture
                anchorY = 0.0
            } else if let picture = illustrated("hazard-ruler", width: 105) {
                hazardArt = picture
                anchorY = 0.0
            } else {
                hazardArt = art.ruler
                anchorY = 10.0 / 190.0
            }
        case .crate:
            if let name = theme?.crateHazard, let picture = illustrated(name, width: 100) {
                hazardArt = picture
                anchorY = 0.03
            } else if let picture = illustrated("hazard-box", width: 100) {
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
        let hazard = Thing(kind: .hazard(kind), sprite: sprite, worldScale: config.rule == .giant ? 1.35 : 1,
                           x: Double(lane) * laneWidth, z: z, y: 0)
        hazard.spawnedAt = distance
        things.append(hazard)
    }

    func addSpool(lane: Int, z: Double, y: Double) {
        let spoolArt = illustrated("spool", width: 58) ?? art.spool
        let sprite = SKSpriteNode(texture: spoolArt.texture, size: spoolArt.size)
        sprite.alpha = 0
        objectLayer.addChild(sprite)
        let spool = Thing(kind: .spool, sprite: sprite, worldScale: 0.8,
                          x: Double(lane) * laneWidth, z: z, y: y)
        spool.spawnedAt = distance
        things.append(spool)
    }

    func spawnScenery(atZ z: Double) {
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
    func illustratedScenery(_ kind: SceneryKind, variant: Int, colored: Bool) -> Art? {
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
        let themedNames: (String?, String?) = kind == .tree ? (theme?.treeColor, theme?.treeGray)
            : kind == .bush ? (theme?.bushColor, theme?.bushGray) : (nil, nil)
        if let colorTheme = themedNames.0, let grayTheme = themedNames.1,
           let themedColor = illustrated(colorTheme, width: width),
           let themedGray = illustrated(grayTheme, width: width) {
            return colored ? Art(texture: themedColor.texture, size: themedGray.size) : themedGray
        }
        guard let color = illustrated(colorName, width: width),
              let gray = illustrated(grayName, width: width) else { return nil }
        return colored ? Art(texture: color.texture, size: gray.size) : gray
    }

    func sceneryArt(_ kind: SceneryKind, variant: Int, colored: Bool) -> Art {
        if let picture = illustratedScenery(kind, variant: variant, colored: colored) {
            return picture
        }
        switch kind {
        case .tree: return art.tree(colored: colored)
        case .bush: return art.bush(colored: colored)
        case .flower: return art.flower(colored: colored, variant: variant)
        }
    }

    func spawnAmbientPatch(atZ z: Double) {
        let chance = fullyStitched ? 1.0 : meter * 1.15
        guard Double.random(in: 0...1) < chance else { return }
        let radius = fullyStitched ? Double.random(in: 3.5...6) : Double.random(in: 1.2...2.6) * (0.6 + meter)
        addPatch(x: Double.random(in: -5...5), z: z, radius: radius, withStitch: false, growTime: 0.01)
    }

    func addPatch(x: Double, z: Double, radius: Double, withStitch: Bool, growTime: Double) {
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
    func stitchBurst(atX x: Double, z: Double) {
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

    func colorize(_ thing: Thing) {
        guard case .scenery(let kind, let variant) = thing.kind, !thing.colored else { return }
        thing.colored = true
        thing.sprite.texture = sceneryArt(kind, variant: variant, colored: true).texture
        thing.popTime = 0
    }

    func worldFullyStitched() {
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

    func checkCollisions() {
        let playerTop = playerY + (slideTimer > 0 ? 0.45 : 1.0)

        let flying = planeTimer > 0 || foldTimer > 0
        for thing in things where !thing.resolved && !thing.retired {
            if case .scenery = thing.kind {
                thing.resolved = true
                continue
            }
            if case .gate = thing.kind {
                thing.resolved = true
                continue
            }
            if thing.isPowerDoor {
                // Doors are picked by lane in PowerGates.swift; they never hit you.
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
            if case .spool = thing.kind {
                if monster.ability == .sticky { reach = 1.55 }
                if magnetTimer > 0 { reach = 3 }
            }
            guard abs(thing.x - playerX) < reach else {
                if passing, thing.isHazard { checkCloseCall(thing) }
                continue
            }

            switch thing.kind {
            case .spool:
                if abs((playerY + 0.5) - thing.y) < 0.5 || magnetTimer > 0 || planeTimer > 0 {
                    collect(thing)
                }
            case .hazard(let hazard):
                var hit: Bool
                switch hazard {
                case .low: hit = playerY < 0.5
                case .overhead: hit = playerTop > 0.85
                case .crate: hit = playerY < 1.4
                }
                if flying { hit = false }
                if hit, hazard == .crate, ((monster.ability == .snip || powerLevel(.scissorSlide) > 0) && slideTimer > 0) || monster.ability == .barge {
                    thing.resolved = true
                    snipThrough(thing)
                    scissorSlideBonus()
                    continue
                }
                if hit {
                    thing.resolved = true
                    takeHit(from: thing)
                    if state != .running { return }
                }
            case .scenery, .gate, .powerDoor:
                break
            }
        }
    }

    func checkCloseCall(_ thing: Thing) {
        let hazardLane = Int((thing.x / laneWidth).rounded())
        guard hazardLane == lastLaneFrom, elapsed - lastLaneChange < 0.35 else { return }
        audio.play(.closeCall)
        haptics.spool()
        timeScale = 0.4
        let bonus = 3 * closeCallMultiplier
        spools += bonus
        closeCalls += 1
        gadgetCharge += monster.ability == .charge ? 6 : 3
        updateGadgetRing()
        meter = min(1, meter + config.meterPerSpool * 2.5)
        popText("Close call! +\(bonus)", size: 24, color: .white, at: playerScreenPoint(offsetY: 120), rise: 50, life: 0.9)
    }

    func collect(_ thing: Thing) {
        let point = screenPoint(ofWorld: thing.sprite.position)
        retire(thing)
        streak += 1
        // Gobbler's feast: during a streak of 10 or more, every spool counts double.
        let worth = (monster.ability == .feast && streak >= 10 ? 2 : 1) * powerSpoolMultiplier + luckySpoolBonus()
        spools += worth
        gadgetCharge += monster.ability == .charge ? worth * 2 : worth
        updateGadgetRing()
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
        meter = min(1, meter + config.meterPerSpool * Double(worth))
        stitchBurst(atX: thing.x, z: max(0.5, thing.z))
        if before < 1 && meter >= 1 && !fullyStitched {
            worldFullyStitched()
        }
    }

    func takeHit(from thing: Thing) {
        guard invulnerable <= 0 else { return }
        if shieldActive {
            shieldActive = false
            refillPatchArmor()
            invulnerable = 0.9
            audio.play(.closeCall)
            haptics.lane()
            shake(strength: 5)
            confettiBurst(at: screenPoint(ofWorld: thing.sprite.position))
            retire(thing)
            popText("Shield!", size: 26, color: Palette.stitchGold, at: playerScreenPoint(offsetY: 130), rise: 40, life: 0.9)
            return
        }
        if monster.ability == .shrug && !shrugUsed {
            shrugUsed = true
            invulnerable = 0.9
            eyePop = 0.3
            audio.play(.closeCall)
            haptics.lane()
            shake(strength: 5)
            let point = screenPoint(ofWorld: thing.sprite.position)
            retire(thing)
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
        jelly.hit()
        shake(strength: 14)

        // The hazard bursts into paper scraps.
        let point = screenPoint(ofWorld: thing.sprite.position)
        retire(thing)
        confettiBurst(at: point)
        flash.removeAllActions()
        flash.color = .white
        flash.alpha = 0.45 * (Motion.reduced ? Motion.reducedStrength : 1)
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

    func moveLane(_ direction: Int) {
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
        jelly.laneChange(direction: newLane - lastLaneFrom)
    }

    func jump() {
        guard playerY <= 0.0001 && velocityY <= 0 else {
            jumpBuffer = jumpBufferTime
            return
        }
        slideTimer = 0
        velocityY = tuning.jumpVelocity * (monster.ability == .bounce ? 1.15 : 1) * springStepMultiplier
        playerY = 0.0001
        audio.play(.jump, volume: 0.7)
        haptics.jump()
        jelly.jump()
    }

    func swipeDown() {
        if playerY > 0.0001 {
            velocityY = -tuning.jumpVelocity * 1.6
        } else {
            slideTimer = tuning.slideDuration
            audio.play(.whoosh, volume: 0.5)
            dustPuff()
            // Bramble's slide pose squashes on its own when it swaps in.
            if monster.id != "bramble" { jelly.poseChanged() }
        }
    }

    func landed() {
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

        let point = touch.location(in: self)
        switch state {
        case .title, .menu:
            _ = handleMenuTap(at: point)
            return
        case .over:
            if clock - overAt > 0.6 { _ = handleMenuTap(at: point) }
            return
        case .story:
            story?.tap(at: point)
            return
        case .celebrating:
            return
        case .paused:
            handlePausedTap(at: point)
            return
        case .running:
            if hud.alpha > 0.5, hypot(point.x - pauseButton.position.x, point.y - pauseButton.position.y) < 34 {
                pauseGame()
                return
            }
            if tryFireGadget(at: point) { return }
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
            var dir = dx > 0 ? 1 : -1
            if config.rule == .mirror { dir = -dir }
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

    func playerScreenPoint(offsetY: CGFloat) -> CGPoint {
        let world = playerNode.position
        let point = screenPoint(ofWorld: world)
        return CGPoint(x: point.x, y: point.y + offsetY)
    }

    func shake(strength: CGFloat) {
        camRig.removeAction(forKey: "shake")
        let base = camRig.position
        let s = strength * (Motion.reduced ? Motion.reducedStrength : 1)
        camRig.run(.sequence([
            .moveBy(x: s, y: s * 0.4, duration: 0.03),
            .moveBy(x: -s * 2, y: -s * 0.6, duration: 0.05),
            .moveBy(x: s * 1.5, y: s * 0.3, duration: 0.04),
            .move(to: base, duration: 0.04)
        ]), withKey: "shake")
    }

    func thunderFlash(strength: Double, withSound: Bool = true) {
        if withSound { audio.play(.thunder, volume: Float(min(1, 0.4 + strength))) }
        flash.removeAllActions()
        flash.color = UIColor(hex: 0xE8E9FF)
        flash.alpha = 0
        // Reduce Motion keeps a soft glow instead of a strobing double flash.
        let strength = strength * (Motion.reduced ? Double(Motion.reducedStrength) : 1)
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

    func popText(_ text: String, size fontSize: CGFloat, color: UIColor, at point: CGPoint, rise: CGFloat, life: Double,
                 parent: SKNode? = nil) {
        let textArt = art.text(text, size: fontSize, fill: color)
        let sprite = SKSpriteNode(texture: textArt.texture, size: textArt.size)
        sprite.position = point
        sprite.setScale(0.4)
        sprite.zPosition = parent == nil ? 10 : 60
        (parent ?? fxRoot).addChild(sprite)
        sprite.run(.sequence([
            .scale(to: 1.15, duration: 0.12),
            .scale(to: 1, duration: 0.08),
            .group([.moveBy(x: 0, y: rise, duration: life), .sequence([.wait(forDuration: life * 0.6), .fadeOut(withDuration: life * 0.4)])]),
            .removeFromParent()
        ]))
    }

    func emitter(texture: SKTexture, at point: CGPoint, count: Int, color: UIColor,
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

    func sparkleBurst(at point: CGPoint, count: Int, spread: CGFloat, speed: CGFloat) {
        _ = emitter(texture: art.spark.texture, at: point, count: count, color: Palette.stitchGold,
                    speed: speed, spread: spread, angle: .pi / 2, life: 0.5, gravity: -200, scale: 0.6)
    }

    func confettiBurst(at point: CGPoint) {
        for color in [UIColor.white, UIColor(hex: 0xD2D4DB), UIColor(hex: 0xFF8FA3)] {
            _ = emitter(texture: art.scrap.texture, at: point, count: 14, color: color,
                        speed: 320, spread: .pi * 0.9, angle: .pi / 2, life: 0.9, gravity: -700, scale: 1.1)
        }
    }

    func dustPuff() {
        guard let ground = project(x: playerX, z: 0) else { return }
        let point = screenPoint(ofWorld: ground.point)
        _ = emitter(texture: art.puff.texture, at: point, count: 8, color: .white,
                    speed: 90, spread: .pi * 0.6, angle: .pi / 2, life: 0.35, gravity: 0, scale: 0.9)
    }

    // MARK: Rendering

    func render(dt: Double) {
        guard unitK > 0, dashes.count == dashesPerDivider * 2 else { return }
        lastRenderDt = dt

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
        let fogDay = config.rule == .fog && state != .title && state != .menu
        for thing in things where !thing.retired {
            guard let p = project(x: thing.x, z: thing.z, y: thing.y) else {
                thing.sprite.isHidden = true
                continue
            }
            let sprite = thing.sprite
            sprite.isHidden = false
            sprite.position = p.point
            sprite.zPosition = CGFloat((spawnZ + 10 - thing.z) * 5)
            sprite.alpha = CGFloat(max(0, min(1, (spawnZ + 2 - thing.z) / 6)))
            if fogDay, case .scenery = thing.kind {} else if fogDay {
                // Fog Day: things loom out of the mist only when they're close.
                sprite.alpha = min(sprite.alpha, CGFloat(max(0, min(1, (19 - thing.z) / 7))))
            }
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
            case .gate:
                break
            case .powerDoor:
                // Doors stand up out of the page early, so there's time to read them.
                let rise = max(0, min(1, (spawnZ - 2 - thing.z) / 4))
                yScale *= CGFloat(easeOutBack(rise))
            }
            sprite.xScale = xScale
            sprite.yScale = yScale
        }

        renderPlayer()
        renderRival()
        renderCamera()
        renderSkyAndStorm(dt: dt)
    }

    func renderPlayer() {
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
        swapCutoutIfNeeded()
        // The jointed rig runs and jumps. Bramble's painted poses still cover his slides and hits;
        // monsters without painted poses get rig poses for those too (CutoutRig.slide and .hit).
        let useCutout = cutout != nil && state != .over && (!hasPoses || (hitPoseTimer <= 0 && !sliding))
        if sliding && state != .over {
            // A rigged slide ducks with its own pose, so it only needs a little extra squash.
            sx = hasPoses ? 1 : (useCutout ? 1.1 : 1.25)
            sy = hasPoses ? 1 : (useCutout ? 0.78 : 0.55)
        } else if landSquash > 0 {
            let amount = CGFloat(landSquash / landSquashTime)
            sx = 1 + 0.18 * amount
            sy = 1 - 0.24 * amount
        } else if airborne {
            // The rig stretches its own body in the air.
            sx = useCutout ? 1 : (velocityY > 0 ? 0.9 : 0.96)
            sy = useCutout ? 1 : (velocityY > 0 ? 1.12 : 1.04)
        } else if !useCutout {
            // The rig bobs on its own steps.
            bob = CGFloat(abs(stride)) * 9
            sy = 1 + CGFloat(abs(stride)) * 0.04
        }

        jelly.step(lastRenderDt)
        let give = jelly.scale
        rig.xScale = rigBaseScale * sx * give.x
        rig.yScale = rigBaseScale * sy * give.y
        rig.position = CGPoint(x: 0, y: bob * rigBaseScale)
        rig.zRotation = CGFloat((laneToX - playerX) * -0.35)

        // Pick the pose. Results: facing you (Bramble cheers or sits dizzy). Running: hit, slide, jump or run.
        let running = state != .over
        let id = monster.id
        swapFrontCutoutIfNeeded()
        // The front rig waves, cheers on a win and slumps when the storm wins. Bramble keeps his
        // painted dizzy pose for the loss.
        let useFront = frontCutout != nil && !running && !(hasPoses && eyeGloat)
        if !running {
            if hasPoses && eyeDefeated && !useFront {
                setPose("bramble-win", height: 150)
            } else if hasPoses && eyeGloat {
                setPose("bramble-lose", height: 150)
            } else {
                setPose("\(id)-front", height: monster.frontHeight)
            }
            if useFront {
                // The front rig does its own hopping and slumping.
            } else if !hasPoses && eyeDefeated {
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
            if hitPoseTimer > 0 && !useCutout {
                // The rig wobbles in its own hit pose; only the single painted view needs the shake.
                rig.zRotation += CGFloat(sin(hitPoseTimer * 40) * 0.3)
            } else if !airborne && !sliding && !useCutout {
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
        // Bend the body for follow-through; feet stay planted.
        brambleSprite.warpGeometry = jelly.warp(mirrored: brambleSprite.xScale < 0)

        if let cutout {
            cutout.isHidden = !useCutout
            brambleSprite.isHidden = useCutout
            if useCutout {
                let pose: [String: PartPose]
                if hitPoseTimer > 0 {
                    // Knocked off balance: 0 the moment of the hit, 1 when the hit pose ends.
                    pose = CutoutRig.hit(CGFloat(1 - hitPoseTimer / 0.45))
                } else if sliding {
                    pose = CutoutRig.slide(CGFloat(1 - slideTimer / max(tuning.slideDuration, 0.01)))
                } else if airborne {
                    // Rising at full jump speed is take-off (0), the peak is 0.5, falling fast is landing (1).
                    let v = velocityY / max(tuning.jumpVelocity, 0.1)
                    pose = CutoutRig.jump(CGFloat(max(0, min(1, 0.5 - 0.5 * v))))
                } else {
                    // One rig cycle is two steps, the same as the stride the bob already follows.
                    pose = CutoutRig.run(CGFloat((runPhase / 2).truncatingRemainder(dividingBy: 1)))
                }
                // The torso tips with the same follow-through spring the painted poses bend with.
                cutout.apply(pose, lean: -CGFloat(jelly.lean.value) * 0.8)
            }
        }

        if let front = frontCutout {
            front.isHidden = !useFront
            if useFront {
                brambleSprite.isHidden = true
                let pose: [String: PartPose]
                if eyeDefeated {
                    pose = CutoutRig.frontCheer(CGFloat((clock / 1.2).truncatingRemainder(dividingBy: 1)))
                } else if eyeGloat {
                    pose = CutoutRig.frontSlump(CGFloat((clock / 3).truncatingRemainder(dividingBy: 1)))
                } else {
                    pose = CutoutRig.frontIdle(CGFloat((clock / 4).truncatingRemainder(dividingBy: 1)))
                }
                front.apply(pose)
            } else if cutout?.isHidden != false {
                brambleSprite.isHidden = false
            }
        }

        // Blinking and breathing while facing the camera. The front rig blinks and breathes on its own,
        // so this is only for the single painted front view.
        if !running && !useFront && currentPose == "\(id)-front" {
            frontBlinkTimer -= lastRenderDt
            if frontBlinkTimer < -0.12 { frontBlinkTimer = Double.random(in: 2...5) }
            let blinkName = "\(id)-blink"
            if poseTextures[blinkName] == nil, let image = artImage(blinkName) {
                let texture = SKTexture(image: image)
                texture.filteringMode = .linear
                poseTextures[blinkName] = (texture, image.size)
            }
            if let blink = poseTextures[blinkName], let open = poseTextures[currentPose] {
                brambleSprite.texture = frontBlinkTimer < 0 ? blink.texture : open.texture
            }
            rig.yScale *= 1 + 0.025 * CGFloat(sin(clock * 2.4))
        }
        planeSprite.isHidden = planeTimer <= 0 || planeSprite.texture == nil
        planeSprite.position = CGPoint(x: 0, y: -6)
        if nightShade.alpha > 0 {
            nightShade.position = screenPoint(ofWorld: CGPoint(x: lifted.point.x, y: lifted.point.y + 50 * lifted.scale))
        }

        if invulnerable > 0 && state == .running {
            playerNode.alpha = Int(invulnerable * 14) % 2 == 0 ? 0.35 : 1
        } else {
            playerNode.alpha = 1
        }
    }

    /// Loads the selected monster's jointed rig the first time it's needed and swaps it in.
    func swapCutoutIfNeeded() {
        guard cutoutID != monster.id else { return }
        cutout?.removeFromParent()
        let loaded: CutoutRig?
        if let cached = cutoutCache[monster.id] {
            loaded = cached
        } else {
            loaded = CutoutRig(named: monster.id)
            cutoutCache[monster.id] = loaded
        }
        if let loaded {
            // The same on-screen height as the monster's painted back view.
            loaded.setScale(monster.runHeight / loaded.height)
            loaded.isHidden = true
            // Parts sit as low as z -4 (tails, back legs). Lift the rig so even those draw above the
            // player's shadow and nearby hazards, like the painted sprite did.
            loaded.zPosition = 4
            rig.addChild(loaded)
        }
        cutout = loaded
        cutoutID = monster.id
        brambleSprite.isHidden = false
    }

    /// Loads the selected monster's front-facing rig, if it has one, and swaps it in.
    func swapFrontCutoutIfNeeded() {
        guard frontCutoutID != monster.id else { return }
        frontCutout?.removeFromParent()
        let loaded: CutoutRig?
        if let cached = frontCutoutCache[monster.id] {
            loaded = cached
        } else {
            loaded = CutoutRig(named: "\(monster.id)-front")
            frontCutoutCache[monster.id] = loaded
        }
        if let loaded {
            loaded.setScale(monster.frontHeight / loaded.height)
            loaded.isHidden = true
            loaded.zPosition = 4
            rig.addChild(loaded)
        }
        frontCutout = loaded
        frontCutoutID = monster.id
    }

    func renderCamera() {
        let follow = CGFloat(playerX) * (unitK / CGFloat(camBack)) * 0.3
        let lean = CGFloat(laneToX - playerX) * 0.035
        let speedT = CGFloat(max(0, min(1, (runSpeed - tuning.startSpeed) / max(tuning.endSpeed - tuning.startSpeed, 0.1))))
        // As the storm closes in, the view rises so the runner stays in sight above it.
        let running = state == .running || state == .paused
        let closeness = running ? CGFloat(1 - max(0, min(1, stormDistance / max(tuning.stormStart, 0.1)))) : 0
        viewLift += (closeness * size.height * 0.12 - viewLift) * 0.08
        if camRig.action(forKey: "shake") == nil {
            camRig.position = CGPoint(x: size.width / 2 - follow, y: size.height / 2 + viewLift)
        }
        camRig.zRotation = lean
        camRig.setScale(1 + 0.05 * speedT)
    }

    func renderSkyAndStorm(dt: Double) {
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
        var visible = h * (0.07 + closeness * 0.33) + CGFloat(sin(clock * 2.2) * 6)
        if running && stormArt != nil {
            // Never let the wall swallow the runner: its top stays around the runner's knees.
            let feet = screenPoint(ofWorld: playerShadow.position).y
            let body = playerNode.calculateAccumulatedFrame().height
            let cap = feet + body * 0.3
            let capped = cap + 8 - stormTopAbove
            if visible > capped {
                // Meet halfway: the wall still climbs over the runner's legs, and its eyes never sink off screen.
                let eyesInView = h * (0.07 + closeness * 0.06)
                visible = max(eyesInView, (visible + capped) / 2)
            }
        }
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
            stormTopAbove = max(stormArt.frame.maxY, stormFar?.frame.maxY ?? 0) - stormArt.position.y
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

    func updateHUD() {
        // Timed runs count down; Endless shows how far you've run.
        let shown = config.length.isFinite ? max(0, Int((config.length - elapsed).rounded(.up))) : Int(distance)
        if shown != shownSeconds {
            shownSeconds = shown
            let words = config.length.isFinite ? "\(shown / 60):\(String(format: "%02d", shown % 60))" : "\(shown) m"
            let text = art.text(words, size: 28, fill: .white)
            timerSprite.texture = text.texture
            timerSprite.size = text.size
            if !config.length.isFinite { timerPill.size.width = max(116, text.size.width + 30) }
        }
        if case .race(let holiday) = mode, rivalCount != shownRival {
            shownRival = rivalCount
            let text = art.text("\(holiday.rivalName): \(rivalCount)", size: 17, fill: UIColor(hex: 0xFFB27A))
            rivalLabel.texture = text.texture
            rivalLabel.size = text.size
            rivalLabel.anchorPoint = CGPoint(x: 0, y: 0.5)
            rivalLabel.position.x = 16
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
    func updateStormEyes(closeness: CGFloat, dt: Double) {
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

    /// Snipjaw slices a box in half instead of crashing into it.
    func snipThrough(_ thing: Thing) {
        let point = screenPoint(ofWorld: thing.sprite.position)
        retire(thing)
        confettiBurst(at: point)
        audio.play(.closeCall)
        haptics.spool()
        spools += 2
        popText("Snip! +2", size: 24, color: .white, at: playerScreenPoint(offsetY: 120), rise: 40, life: 0.8)
    }

    /// Swaps the runner's picture, keeping the feet on the ground and the body a steady size.
    func setPose(_ name: String, height: CGFloat) {
        guard name != currentPose else { return }
        let entry: (texture: SKTexture, size: CGSize)
        if let cached = poseTextures[name] {
            entry = cached
        } else {
            guard let image = artImage(name) else { return }
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            entry = (texture, image.size)
            poseTextures[name] = entry
        }
        currentPose = name
        brambleSprite.xScale = 1
        brambleSprite.texture = entry.texture
        brambleSprite.size = CGSize(width: height * entry.size.width / entry.size.height, height: height)
        brambleSprite.childNode(withName: "dizzyEyes")?.removeFromParent()
        if name == "bramble-lose" { addDizzyEyes(imageSize: entry.size) }
        // A quick squash makes the swap read as a snappy pose change instead of a cut.
        // Run, jump and hit poses skip it: their own moves already kick the body.
        if !(name.hasSuffix("-back") || name.hasSuffix("-jump") || name.hasSuffix("-hit")) {
            jelly.poseChanged()
        }
    }

    /// Bramble's spiral eyes spin while he sits dazed after the storm wins.
    func addDizzyEyes(imageSize: CGSize) {
        // Eye centers and size in the bramble-lose painting (pixels, y from the top).
        let eyes: [(name: String, x: CGFloat, y: CGFloat, spin: CGFloat)] = [
            ("bramble-dizzy-eye-l", 170.7, 312.3, -1), ("bramble-dizzy-eye-r", 262.0, 313.8, 1)
        ]
        let diameter: CGFloat = 62
        let group = SKNode()
        group.name = "dizzyEyes"
        group.zPosition = 0.1
        let w = brambleSprite.size.width, h = brambleSprite.size.height
        let anchor = brambleSprite.anchorPoint
        for eye in eyes {
            guard let image = artImage(eye.name) else { return }
            let sprite = SKSpriteNode(texture: SKTexture(image: image),
                                      size: CGSize(width: diameter / imageSize.width * w, height: diameter / imageSize.height * h))
            sprite.position = CGPoint(x: (eye.x / imageSize.width - anchor.x) * w,
                                      y: ((imageSize.height - eye.y) / imageSize.height - anchor.y) * h)
            sprite.run(.repeatForever(.rotate(byAngle: eye.spin * 2 * .pi, duration: 1.1)))
            group.addChild(sprite)
        }
        brambleSprite.addChild(group)
    }

    // MARK: Pause

    @objc private func appWillResignActive() {
        if state == .paused && resumeCountdown > 0 { state = .running }
        if state == .running { pauseGame() }
    }

    func pauseGame() {
        guard state == .running else { return }
        state = .paused
        resumeCountdown = 0
        trackedTouch = nil
        audio.setMusic(playing: false)
        haptics.lane()

        clearScreen()
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

    func handlePausedTap(at point: CGPoint) {
        guard resumeCountdown <= 0 else { return }
        for node in nodes(at: point) {
            var current: SKNode? = node
            while let candidate = current {
                if candidate.name == "resume" {
                    resumeGame()
                    return
                }
                if candidate.name == "quit" {
                    // Quitting your first daily run still uses it up, so nobody can fish for a lucky start.
                    if case .daily(let storm) = mode, Progress.shared.data.dailyScores[storm.key] == nil {
                        state = .running
                        concludeRun(caught: false, finished: false)
                    } else {
                        showTitle()
                    }
                    return
                }
                current = candidate.parent
            }
        }
    }

    func resumeGame() {
        fadeOverlay()
        haptics.lane()
        resumeCountdown = 2.4
        shownCountdown = 0
    }

    /// 3, 2, 1, Go: gives the player a moment to get ready after a pause.
    func stepCountdown(_ dt: Double) {
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
    func fitSpoolPill() {
        let left = spoolIcon.position.x - 14
        let right = size.width - 26
        spoolPill.size = CGSize(width: (right - left) + 28, height: 37)
        spoolPill.position.x = (left + right) / 2
    }

    func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}
