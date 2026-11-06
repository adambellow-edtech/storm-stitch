import SpriteKit
import StoreKit
import UIKit

/// Every screen that isn't the run itself. Screens are built on `overlay`; buttons register
/// a tap action with `onTap`, and `handleMenuTap` finds the one under a finger.
extension RunScene {

    // MARK: Building blocks

    func clearScreen() {
        overlay.removeAllChildren()
        tapTargets.removeAll()
    }

    func onTap(_ node: SKNode, _ action: @escaping () -> Void) {
        tapTargets.append((node: node, action: action))
    }

    /// Runs the action of the top-most button under the point. Returns true when one was hit.
    func handleMenuTap(at point: CGPoint) -> Bool {
        for target in tapTargets.reversed() {
            let node = target.node
            guard let parent = node.parent, node.scene != nil, !node.isHidden else { continue }
            let local = convert(point, to: parent)
            if node.calculateAccumulatedFrame().insetBy(dx: -6, dy: -6).contains(local) {
                haptics.lane()
                target.action()
                return true
            }
        }
        return false
    }

    /// One line of game text as a sprite.
    func label(_ string: String, size: CGFloat, color: UIColor = .white,
               style: PaperArt.TextStyle = .heading, anchorX: CGFloat = 0.5) -> SKSpriteNode {
        let textArt = art.text(string, size: size, fill: color, style: style)
        let sprite = SKSpriteNode(texture: textArt.texture, size: textArt.size)
        sprite.anchorPoint = CGPoint(x: anchorX, y: 0.5)
        return sprite
    }

    /// Several lines of wrapped text, centered on the node's origin.
    func paragraph(_ string: String, size: CGFloat, width: CGFloat, color: UIColor = .white,
                   style: PaperArt.TextStyle = .body) -> SKNode {
        let node = SKNode()
        let lines = PaperArt.wrap(string, fontSize: size, maxWidth: width, style: style)
        let lineHeight = size * 1.35
        for (i, line) in lines.enumerated() {
            let sprite = label(line, size: size, color: color, style: style)
            sprite.position = CGPoint(x: 0, y: (CGFloat(lines.count - 1) / 2 - CGFloat(i)) * lineHeight)
            node.addChild(sprite)
        }
        return node
    }

    /// A paper panel: the illustrated card when the shape fits it, otherwise cut paper drawn in code.
    func paperPanel(width: CGFloat, height: CGFloat, tallArt: Bool = false) -> SKNode {
        let node = SKNode()
        let shadow = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2 - 9, width: width, height: height), cornerRadius: 26)
        shadow.fillColor = UIColor(white: 0, alpha: 0.28)
        shadow.strokeColor = .clear
        node.addChild(shadow)
        if abs(width / height - 4.0 / 3.0) < 0.12, let card = imageSprite("ui-card") {
            card.size = CGSize(width: width, height: height)
            node.addChild(card)
            return node
        }
        if tallArt, width / height < 4.0 / 3.0, width / height > 0.45, let tall = tallPaperCard(width: width, height: height) {
            node.addChild(tall)
            return node
        }
        let panel = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerRadius: 26)
        panel.fillColor = Palette.paper
        panel.strokeColor = .white
        panel.lineWidth = 6
        node.addChild(panel)
        let inset: CGFloat = 16
        let stitch = SKShapeNode(rect: CGRect(x: -width / 2 + inset, y: -height / 2 + inset,
                                              width: width - inset * 2, height: height - inset * 2), cornerRadius: 16)
        stitch.path = stitch.path?.copy(dashingWithPhase: 0, lengths: [10, 7])
        stitch.strokeColor = Palette.stitchGold
        stitch.lineWidth = 2.5
        stitch.fillColor = .clear
        node.addChild(stitch)
        return node
    }

    /// The illustrated card made taller: its top and bottom halves stay as drawn, and a band from
    /// the middle repeats between them, so the stitched border and corners keep their shape.
    func tallPaperCard(width: CGFloat, height: CGFloat) -> SKNode? {
        guard let image = artImage("ui-card"), image.size.width > 0 else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let baseH = width * image.size.height / image.size.width
        let node = SKNode()
        let top = SKSpriteNode(texture: SKTexture(rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5), in: texture),
                               size: CGSize(width: width, height: baseH / 2))
        top.position = CGPoint(x: 0, y: height / 2 - baseH / 4)
        top.zPosition = 0.1
        node.addChild(top)
        let bottom = SKSpriteNode(texture: SKTexture(rect: CGRect(x: 0, y: 0, width: 1, height: 0.5), in: texture),
                                  size: CGSize(width: width, height: baseH / 2))
        bottom.position = CGPoint(x: 0, y: -height / 2 + baseH / 4)
        bottom.zPosition = 0.1
        node.addChild(bottom)
        let bandFraction: CGFloat = 0.2
        let bandH = baseH * bandFraction
        var y = -height / 2 + baseH / 2
        let end = height / 2 - baseH / 2
        while y < end - 0.5 {
            let piece = min(bandH, end - y)
            let rect = CGRect(x: 0, y: 0.4, width: 1, height: bandFraction * piece / bandH)
            let band = SKSpriteNode(texture: SKTexture(rect: rect, in: texture), size: CGSize(width: width, height: piece + 0.5))
            band.position = CGPoint(x: 0, y: y + piece / 2)
            band.zPosition = 0.05
            node.addChild(band)
            y += piece
        }
        return node
    }

    /// A round paper button with an icon (or a fallback letter) and an optional caption.
    func roundButton(icon: String, fallback: String, size: CGFloat, caption: String?) -> SKNode {
        let node = SKNode()
        if let base = imageSprite("ui-round") {
            base.size = CGSize(width: size, height: size)
            node.addChild(base)
        } else {
            let base = SKShapeNode(circleOfRadius: size / 2)
            base.fillColor = Palette.paper
            base.strokeColor = .white
            base.lineWidth = 4
            node.addChild(base)
            let rim = SKShapeNode(circleOfRadius: size / 2 - 6)
            rim.strokeColor = UIColor(hex: 0x4A3C66)
            rim.lineWidth = 3
            node.addChild(rim)
        }
        if icon == "menu-back" && artImage(icon) == nil {
            // A cut-paper chevron, flipped here to point left; mirror the button (xScale = -1) to point right.
            let chevron = paperChevron(size: size * 0.46)
            chevron.xScale = -1
            chevron.position.x = -size * 0.03
            chevron.zPosition = 1
            node.addChild(chevron)
        } else if let image = artImage(icon) {
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            let k = size * 0.6 / max(image.size.width, image.size.height)
            sprite.size = CGSize(width: image.size.width * k, height: image.size.height * k)
            sprite.zPosition = 1
            node.addChild(sprite)
        } else {
            let letter = label(fallback, size: size * 0.4, color: Palette.stitchGold)
            letter.zPosition = 1
            node.addChild(letter)
        }
        if let caption {
            let text = label(caption, size: 13, style: .body)
            text.position = CGPoint(x: 0, y: -size / 2 - 13)
            text.zPosition = 1
            node.addChild(text)
        }
        return node
    }

    /// A front-facing monster fitted inside a box, breathing and blinking. Monsters with a front rig
    /// (`<id>-front-rig.json`) stand there as the jointed rig instead, idling and waving; the one
    /// just picked (`portraitGreetID`) cheers first. Locked monsters stay a painted silhouette.
    func monsterPortrait(_ monster: Monster, box: CGSize, locked: Bool = false) -> SKSpriteNode? {
        guard let sprite = imageSprite("\(monster.id)-front") else { return nil }
        let k = min(box.width / sprite.size.width, box.height / sprite.size.height)
        sprite.size = CGSize(width: sprite.size.width * k, height: sprite.size.height * k)
        if locked {
            sprite.color = Palette.ink
            sprite.colorBlendFactor = 1
            sprite.alpha = 0.45
        } else if let rig = CutoutRig(named: "\(monster.id)-front"), rig.height > 0 {
            // The sprite keeps the painting's size for layout and taps but draws nothing itself.
            sprite.texture = nil
            sprite.color = .clear
            sprite.colorBlendFactor = 0
            rig.setScale(sprite.size.height / rig.height)
            rig.position = CGPoint(x: 0, y: -sprite.size.height / 2)
            rig.zPosition = 2
            sprite.addChild(rig)
            let greet = portraitGreetID == monster.id
            if greet { portraitGreetID = nil }
            animateFrontRig(rig, greet: greet)
        } else {
            bringToLife(sprite, id: monster.id)
        }
        return sprite
    }

    /// Plays the front rig's idle (breathing, a wave, blinks) forever. A greeting starts with a quick
    /// cheer and goes straight into the wave. The rig stands on the bottom edge of its host sprite,
    /// wherever the caller moves the host's anchor.
    func animateFrontRig(_ rig: CutoutRig, greet: Bool) {
        let loop: CGFloat = 4
        // A greeting lands just before the wave; others start anywhere so a shelf of them doesn't wave in step.
        let offset: CGFloat = greet ? 0.27 : CGFloat.random(in: 0..<1)
        let stand: (SKNode) -> Void = { node in
            guard let host = node.parent as? SKSpriteNode else { return }
            node.position = CGPoint(x: host.size.width * (0.5 - host.anchorPoint.x),
                                    y: -host.size.height * host.anchorPoint.y)
        }
        let idle = SKAction.customAction(withDuration: TimeInterval(loop)) { node, elapsed in
            guard let rig = node as? CutoutRig else { return }
            stand(rig)
            rig.apply(CutoutRig.frontIdle((elapsed / loop + offset).truncatingRemainder(dividingBy: 1)))
        }
        rig.apply(CutoutRig.frontIdle(offset))
        var steps: [SKAction] = []
        if greet && !Motion.reduced {
            let cheerTime: CGFloat = 1.1
            steps.append(.customAction(withDuration: TimeInterval(cheerTime)) { node, elapsed in
                guard let rig = node as? CutoutRig else { return }
                stand(rig)
                rig.apply(CutoutRig.frontCheer(min(1, elapsed / cheerTime)))
            })
        }
        steps.append(.repeatForever(idle))
        rig.run(.sequence(steps), withKey: "frontRig")
    }

    func closeButton(at point: CGPoint, action: @escaping () -> Void) {
        let button = roundButton(icon: "menu-close", fallback: "X", size: 44, caption: nil)
        button.position = point
        button.zPosition = 20
        overlay.addChild(button)
        onTap(button, action)
    }

    func backButton(action: @escaping () -> Void) {
        let topInset = max(view?.safeAreaInsets.top ?? 0, 20)
        let button = roundButton(icon: "menu-back", fallback: "<", size: 48, caption: nil)
        button.position = CGPoint(x: 38, y: size.height - topInset - 30)
        button.zPosition = 5
        overlay.addChild(button)
        onTap(button, action)
    }

    func dimBackground(onTap action: @escaping () -> Void) -> SKSpriteNode {
        let dim = SKSpriteNode(color: UIColor(white: 0, alpha: 0.45), size: size)
        dim.anchorPoint = .zero
        dim.zPosition = 10
        overlay.addChild(dim)
        onTap(dim, action)
        return dim
    }

    var safeTop: CGFloat { max(view?.safeAreaInsets.top ?? 0, 20) }
    var safeBottom: CGFloat { max(view?.safeAreaInsets.bottom ?? 0, 16) }

    // MARK: Title

    func showTitle() {
        state = .title
        clearScreen()
        hud.removeAllActions()
        hud.alpha = 0
        nightShade.alpha = 0
        rivalSprite.isHidden = true
        gadgetButton.isHidden = true
        mode = .endless
        config = makeConfig(for: .endless)
        applyFog()
        applyTheme(themeFor(nil))
        monster = Monster.roster[Monster.selectedIndex]
        if !Progress.shared.isUnlocked(monster) { monster = Monster.roster[0] }
        currentPose = ""
        eyeGloat = false
        eyeDefeated = false
        resetWorld()
        runSpeed = titleSpeed
        audio.setMusic(playing: true)
        audio.setIntensity(0.25)
        let w = size.width
        let h = size.height

        if let card = imageSprite("title-card"), let cardTexture = card.texture {
            let fitted = CGSize(width: w, height: card.size.height * w / card.size.width)
            card.size = fitted
            card.anchorPoint = CGPoint(x: 0.5, y: 1)
            card.position = CGPoint(x: w / 2, y: h)
            overlay.addChild(card)
            let gap = h - fitted.height
            if gap > 0 {
                let stripTexture = SKTexture(rect: CGRect(x: 0, y: 0, width: 1, height: 0.15), in: cardTexture)
                let strip = SKSpriteNode(texture: stripTexture, size: CGSize(width: w, height: gap + 2))
                strip.anchorPoint = CGPoint(x: 0.5, y: 0)
                strip.position = CGPoint(x: w / 2, y: gap + 1)
                strip.yScale = -1
                overlay.addChild(strip)
            }
        } else {
            let logo = label("STORM STITCH", size: min(44, w * 0.1), color: Palette.stitchGold)
            logo.position = CGPoint(x: w / 2, y: h * 0.78)
            overlay.addChild(logo)
        }

        // Everything sits in the plain paper road at the bottom, clear of Bramble and the logo.
        let iconSize: CGFloat = min(58, w * 0.15)
        let rowY = safeBottom + 22 + iconSize / 2
        let items: [(String, String, String, () -> Void)] = [
            ("menu-daily", "D", "Daily", { [unowned self] in self.showDailyCard() }),
            ("menu-trophy", "T", "Trophies", { [unowned self] in self.showTrophyCase(tab: 0) }),
            ("menu-story", "S", "Story", { [unowned self] in self.playStory() }),
            ("menu-settings", "*", "Settings", { [unowned self] in self.showSettings() })
        ]
        let spacing = min(84, (w - 40) / CGFloat(items.count))
        for (i, item) in items.enumerated() {
            let button = roundButton(icon: item.0, fallback: item.1, size: iconSize, caption: item.2)
            button.position = CGPoint(x: w / 2 + (CGFloat(i) - CGFloat(items.count - 1) / 2) * spacing, y: rowY)
            button.zPosition = 2
            overlay.addChild(button)
            onTap(button, item.3)
        }
        // A dot on Daily until today's storm is played.
        if Progress.shared.data.dailyScores[DailyStorm.today().key] == nil {
            let dot = SKShapeNode(circleOfRadius: 7)
            dot.fillColor = Palette.heart
            dot.strokeColor = .white
            dot.lineWidth = 2
            dot.position = CGPoint(x: w / 2 - 1.5 * spacing + iconSize * 0.36, y: rowY + iconSize * 0.36)
            dot.zPosition = 3
            overlay.addChild(dot)
        }

        let playWidth = min(250, w * 0.62)
        let playHeight = playWidth * 300.0 / 720.0
        let play = paperButton("Play", width: playWidth)
        let playY = rowY + iconSize / 2 + 18 + playHeight / 2
        play.position = CGPoint(x: w / 2, y: playY)
        play.zPosition = 2
        overlay.addChild(play)
        onTap(play) { [unowned self] in self.showMap(world: World.index(ofStage: Progress.shared.nextStageIndex)) }

        if let holiday = currentHoliday() {
            let ribbon = paperButton("\(holiday.raceName)!", width: min(210, w * 0.54), pulse: false)
            ribbon.setScale(0.62)
            ribbon.position = CGPoint(x: w / 2, y: playY + playHeight * 0.525 + 33)
            ribbon.zPosition = 2
            overlay.addChild(ribbon)
            onTap(ribbon) { [unowned self] in self.showRaceCard(holiday) }
        }

        overlay.alpha = 0
        overlay.run(.fadeIn(withDuration: 0.3))
        checkPendingLink()
    }

    // MARK: Stage map

    /// Stage spots on the map, as fractions of the map area (x from the left, y from the bottom).
    var mapSpots: [CGPoint] {
        [CGPoint(x: 0.28, y: 0.04), CGPoint(x: 0.66, y: 0.13), CGPoint(x: 0.8, y: 0.26), CGPoint(x: 0.47, y: 0.34),
         CGPoint(x: 0.2, y: 0.45), CGPoint(x: 0.42, y: 0.56), CGPoint(x: 0.77, y: 0.63), CGPoint(x: 0.62, y: 0.76),
         CGPoint(x: 0.3, y: 0.83), CGPoint(x: 0.55, y: 0.96)]
    }

    /// A smooth curve between stage i and i+1 (Catmull-Rom through its neighbours), with a gentle sideways bow.
    func mapCurve(_ spots: [CGPoint], from i: Int) -> (path: CGPath, point: (CGFloat) -> CGPoint) {
        let p0 = spots[max(0, i - 1)], p1 = spots[i], p2 = spots[i + 1], p3 = spots[min(spots.count - 1, i + 2)]
        let bow: CGFloat = i % 2 == 0 ? 6 : -6
        let dx = p2.x - p1.x, dy = p2.y - p1.y
        let length = max(1, hypot(dx, dy))
        let normal = CGPoint(x: -dy / length * bow, y: dx / length * bow)
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6 + normal.x, y: p1.y + (p2.y - p0.y) / 6 + normal.y)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6 + normal.x, y: p2.y - (p3.y - p1.y) / 6 + normal.y)
        let path = CGMutablePath()
        path.move(to: p1)
        path.addCurve(to: p2, control1: c1, control2: c2)
        let point: (CGFloat) -> CGPoint = { t in
            let u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            return CGPoint(x: a * p1.x + b * c1.x + c * c2.x + d * p2.x,
                           y: a * p1.y + b * c1.y + c * c2.y + d * p2.y)
        }
        return (path, point)
    }

    /// A shader that shows a sprite only inside soft, lumpy blobs (given in scene points), feathered at the edges.
    func softReveal(frame: CGRect, blobs: [(center: CGPoint, radius: CGFloat, seed: UInt64)]) -> SKShader {
        let scale: CGFloat = 0.25
        let maskSize = CGSize(width: max(8, frame.width * scale), height: max(8, frame.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: maskSize, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.85).cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]) else { return }
            for blob in blobs {
                var rng = GameRNG(seed: blob.seed &* 2_654_435_761)
                // Map scene points into the mask picture (whose y runs downward).
                let cx = (blob.center.x - frame.minX) * scale
                let cy = (frame.maxY - blob.center.y) * scale
                for _ in 0..<7 {
                    let angle = CGFloat.random(in: 0..<(2 * .pi), using: &rng)
                    let reach = blob.radius * scale * CGFloat.random(in: 0...0.5, using: &rng)
                    let center = CGPoint(x: cx + cos(angle) * reach, y: cy + sin(angle) * reach)
                    let radius = blob.radius * scale * CGFloat.random(in: 0.5...0.85, using: &rng)
                    cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                          endCenter: center, endRadius: radius, options: [])
                }
            }
        }
        let shader = SKShader(source: """
        void main() {
            vec4 color = texture2D(u_texture, v_tex_coord);
            float keep = texture2D(u_mask, v_tex_coord).a;
            gl_FragColor = color * keep;
        }
        """)
        shader.uniforms = [SKUniform(name: "u_mask", texture: SKTexture(image: image))]
        return shader
    }

    func showMap(world requested: Int? = nil) {
        state = .menu
        clearScreen()
        hud.alpha = 0
        let w = size.width
        let h = size.height
        let progress = Progress.shared
        let worldIndex = requested ?? mapWorld ?? World.index(ofStage: progress.nextStageIndex)
        let world = World.all[worldIndex]
        let base = world.firstStage
        mapWorld = worldIndex
        // A world opens once the last stage of the one before it is cleared.
        let worldOpen = base == 0 || progress.stars(forStage: base - 1) > 0

        // Background: the gray map, with color showing through around cleared stages.
        let background = SKNode()
        overlay.addChild(background)
        func fill(_ name: String, fallback: UIColor) -> SKNode {
            // A world without its own map yet borrows Notebook Meadow's.
            let meadowName = name.replacingOccurrences(of: "\(world.id)-", with: "")
            if let sprite = imageSprite(name) ?? imageSprite(meadowName) {
                let k = max(w / sprite.size.width, h / sprite.size.height)
                sprite.size = CGSize(width: sprite.size.width * k, height: sprite.size.height * k)
                sprite.position = CGPoint(x: w / 2, y: h / 2)
                return sprite
            }
            let plain = SKSpriteNode(color: fallback, size: size)
            plain.position = CGPoint(x: w / 2, y: h / 2)
            return plain
        }
        background.addChild(fill(world.mapGray, fallback: UIColor(hex: 0xA9ABB6)))
        // Markers sit on the painted path. The map fills the screen (cropped to fit), so place them on the
        // picture itself, then keep them clear of the title bar and the Endless button.
        let picture = (background.children.first as? SKSpriteNode)?.frame ?? CGRect(origin: .zero, size: size)
        let lowest = safeBottom + 140, highest = h - safeTop - 110
        let spots = world.mapPath.map { p -> CGPoint in
            CGPoint(x: min(max(picture.minX + p.x * picture.width, 36), w - 36),
                    y: min(max(picture.maxY - p.y * picture.height, lowest), highest))
        }
        // Color soaks back in around cleared stages and along the path between them, with soft, uneven edges.
        let colorMap = fill(world.mapColor, fallback: UIColor(hex: 0x7FCF84))
        let cleared = (0..<spots.count).filter { progress.stars(forStage: base + $0) > 0 }
        if !cleared.isEmpty, let colorSprite = colorMap as? SKSpriteNode, colorSprite.texture != nil {
            var blobs: [(center: CGPoint, radius: CGFloat, seed: UInt64)] = cleared.map { (spots[$0], w * 0.3, UInt64(base + $0 + 1)) }
            for i in cleared where i + 1 < spots.count {
                let segment = mapCurve(spots, from: i)
                for (j, t) in [0.25, 0.5, 0.75].enumerated() {
                    blobs.append((segment.point(CGFloat(t)), w * 0.14, UInt64(100 + i * 10 + j)))
                }
            }
            colorSprite.shader = softReveal(frame: colorSprite.frame, blobs: blobs)
            background.addChild(colorSprite)
        }

        // The path curves between stages, stitched in gold where you've been.
        for i in 0..<(spots.count - 1) {
            let done = progress.stars(forStage: base + i) > 0
            let path = mapCurve(spots, from: i).path
            if done {
                let shadow = SKShapeNode(path: path.copy(dashingWithPhase: 0, lengths: [14, 7]))
                shadow.strokeColor = UIColor(hex: 0x6B4A12, alpha: 0.55)
                shadow.lineWidth = 8
                shadow.lineCap = .round
                shadow.position = CGPoint(x: 0, y: -2)
                shadow.zPosition = 1
                overlay.addChild(shadow)
            }
            let line = SKShapeNode(path: path.copy(dashingWithPhase: 0, lengths: done ? [14, 7] : [7, 11]))
            line.strokeColor = done ? Palette.stitchGold : UIColor(white: 1, alpha: 0.8)
            line.lineWidth = done ? 6 : 4
            line.lineCap = .round
            line.zPosition = 1.1
            overlay.addChild(line)
        }

        // Stage spots.
        let current = progress.nextStageIndex
        // Shrink the markers when the path packs them close (smaller iPhones), so the stars never overlap.
        let spacing = zip(spots, spots.dropFirst()).map { hypot($0.x - $1.x, $0.y - $1.y) }.min() ?? 80
        let markerScale = min(1, max(0.62, spacing / 68))
        for (i, spot) in spots.enumerated() {
            let isOpen = progress.isStageOpen(base + i)
            let node = SKNode()
            node.position = spot
            node.zPosition = 2
            node.setScale(markerScale)
            overlay.addChild(node)
            let disc = SKShapeNode(circleOfRadius: 25)
            disc.fillColor = isOpen ? Palette.paper : UIColor(hex: 0x8A8C99)
            disc.strokeColor = isOpen ? Palette.stitchGold : .white
            disc.lineWidth = 4
            node.addChild(disc)
            let number = label("\(i + 1)", size: 22, color: isOpen ? Palette.stitchGold : .white)
            number.zPosition = 1
            node.addChild(number)
            let stars = progress.stars(forStage: base + i)
            for s in 0..<3 {
                let star = illustrated(s < stars ? "ui-star" : "ui-star-empty", width: 16) ?? art.star(filled: s < stars)
                let sprite = SKSpriteNode(texture: star.texture, size: CGSize(width: 17, height: 17))
                sprite.position = CGPoint(x: CGFloat(s - 1) * 17, y: -34)
                sprite.zPosition = 1
                node.addChild(sprite)
            }
            if base + i == current && isOpen {
                node.run(.repeatForever(.sequence([.scale(to: markerScale * 1.1, duration: 0.5), .scale(to: markerScale, duration: 0.5)])))
                if let runner = monsterPortrait(monster, box: CGSize(width: 54, height: 54)) {
                    runner.position = CGPoint(x: 0, y: 58)
                    node.addChild(runner)
                }
            }
            onTap(node) { [unowned self] in
                if isOpen {
                    self.showStageCard(base + i)
                } else {
                    self.popText(!worldOpen ? "Finish the last world first" : "Clear stage \(i) first", size: 20, color: .white, at: spot, rise: 30, life: 1, parent: self.overlay)
                }
            }
        }

        // Top bar.
        backButton { [unowned self] in self.showTitle() }
        let title = label(world.name, size: 26)
        title.position = CGPoint(x: w / 2, y: h - safeTop - 30)
        title.zPosition = 5
        overlay.addChild(title)
        let worldStars = (base..<(base + world.stages.count)).reduce(0) { $0 + progress.stars(forStage: $1) }
        let starTotal = label("★ \(worldStars)/\(world.stages.count * 3)", size: 17, color: Palette.stitchGold)
        starTotal.anchorPoint = CGPoint(x: 1, y: 0.5)
        starTotal.position = CGPoint(x: w - 16, y: h - safeTop - 30)
        starTotal.zPosition = 5
        overlay.addChild(starTotal)
        let subtitle = label(worldOpen ? world.blurb : "Clear \(World.all[max(0, worldIndex - 1)].name) to open", size: 14,
                             style: .body)
        subtitle.position = CGPoint(x: w / 2, y: h - safeTop - 58)
        subtitle.zPosition = 5
        overlay.addChild(subtitle)

        // Arrows flip between worlds.
        for (direction, target) in [(-1, worldIndex - 1), (1, worldIndex + 1)] where World.all.indices.contains(target) {
            let arrow = roundButton(icon: "menu-back", fallback: direction < 0 ? "<" : ">", size: 46, caption: nil)
            if direction > 0 { arrow.xScale = -1 }
            arrow.position = CGPoint(x: direction < 0 ? 30 : w - 30, y: h * 0.5)
            arrow.zPosition = 6
            overlay.addChild(arrow)
            onTap(arrow) { [unowned self] in self.showMap(world: target) }
        }
        if !worldOpen {
            let shade = SKSpriteNode(color: UIColor(white: 0, alpha: 0.35), size: size)
            shade.anchorPoint = .zero
            shade.zPosition = 4
            overlay.addChild(shade)
        }

        // Bottom: Endless.
        let endless = paperButton("Endless", width: min(200, w * 0.5), pulse: false)
        endless.position = CGPoint(x: w / 2, y: safeBottom + 48)
        endless.zPosition = 5
        overlay.addChild(endless)
        onTap(endless) { [unowned self] in self.showEndlessCard() }
        let best = progress.data.bestEndlessMeters
        if best > 0 {
            let record = label("Best: \(best.formatted()) m", size: 13, style: .body)
            record.position = CGPoint(x: w / 2, y: endless.position.y + min(200, w * 0.5) * 300 / 720 / 2 + 12)
            record.zPosition = 5
            overlay.addChild(record)
        }
    }

    // MARK: Stage card

    func showStageCard(_ index: Int) {
        let stage = Stage.all[index]
        let w = size.width
        let h = size.height
        _ = dimBackground { [unowned self] in self.showMap(world: World.index(ofStage: index)) }
        let cardW = min(w - 32, 350)
        let cardH: CGFloat = 470
        let card = paperPanel(width: cardW, height: cardH)
        card.position = CGPoint(x: w / 2, y: h * 0.52)
        card.zPosition = 11
        overlay.addChild(card)
        onTap(card) {}  // Taps on the card itself don't close it.
        func place(_ node: SKNode, _ y: CGFloat) {
            node.position.y = y
            node.zPosition = 1
            card.addChild(node)
        }
        let top = cardH / 2

        place(label("\(World.all[World.index(ofStage: index)].name) · Stage \(stage.number)", size: 15, color: Palette.stormDark, style: .body), top - 36)
        place(label(stage.name, size: 27, color: Palette.stitchGold), top - 66)

        // The three stars.
        let earned = Progress.shared.stars(forStage: index)
        let goals = ["Reach the seam", stage.challenge.text, "Fully stitch the stage"]
        for (i, goal) in goals.enumerated() {
            let row = SKNode()
            let starArt = illustrated(i < earned ? "ui-star" : "ui-star-empty", width: 22) ?? art.star(filled: i < earned)
            let star = SKSpriteNode(texture: starArt.texture, size: CGSize(width: 24, height: 24))
            star.position = CGPoint(x: -cardW / 2 + 48, y: 0)
            row.addChild(star)
            let text = label(goal, size: 15, color: Palette.ink, style: .body, anchorX: 0)
            text.position = CGPoint(x: -cardW / 2 + 68, y: 0)
            row.addChild(text)
            place(row, top - 108 - CGFloat(i) * 30)
        }

        // Reward or best.
        var rewardText = "Best: \(Progress.shared.data.stageBest[index]) spools"
        if earned == 0 {
            if let gadget = stage.gadget {
                rewardText = "Reward: the \(gadget.name) gadget"
            } else if let id = stage.monster {
                rewardText = "Reward: \(Monster.named(id).name) joins your crew"
            } else {
                rewardText = "Reward: the next stage"
            }
        }
        place(label(rewardText, size: 14, color: Palette.stormDark, style: .body), top - 208)

        // Runner choice.
        let runnerRow = SKNode()
        place(runnerRow, top - 262)
        let unlocked = Monster.roster.filter { Progress.shared.isUnlocked($0) }
        if let portrait = monsterPortrait(monster, box: CGSize(width: 56, height: 56)) {
            portrait.position = CGPoint(x: -60, y: 0)
            runnerRow.addChild(portrait)
        }
        let name = label(monster.name, size: 19, color: Palette.ink, anchorX: 0)
        name.position = CGPoint(x: -24, y: 9)
        runnerRow.addChild(name)
        let passive = label(monster.passive, size: 12, color: Palette.stormDark, style: .body, anchorX: 0)
        passive.position = CGPoint(x: -24, y: -12)
        runnerRow.addChild(passive)
        if unlocked.count > 1 {
            addArrows(to: runnerRow, width: cardW - 40) { [unowned self] step in
                let ids = unlocked.map(\.id)
                let at = ids.firstIndex(of: self.monster.id) ?? 0
                let next = unlocked[(at + step + ids.count) % ids.count]
                Monster.selectedIndex = Monster.roster.firstIndex { $0.id == next.id } ?? 0
                self.monster = next
                self.currentPose = ""
                self.portraitGreetID = next.id
                self.showMap()
                self.showStageCard(index)
            }
        }

        // Gadget choice.
        let gadgets = Progress.shared.unlockedGadgets
        let gadgetRow = SKNode()
        place(gadgetRow, top - 330)
        if gadgets.isEmpty {
            gadgetRow.addChild(label("Clear stage 1 to earn a gadget", size: 13, color: Palette.stormDark, style: .body))
        } else {
            let equipped = Progress.shared.equippedGadget
            let icon = roundButton(icon: equipped?.icon ?? "menu-none", fallback: equipped?.letter ?? "-", size: 50, caption: nil)
            icon.position = CGPoint(x: -60, y: 0)
            gadgetRow.addChild(icon)
            let gadgetName = label(equipped?.name ?? "No gadget", size: 18, color: Palette.ink, anchorX: 0)
            gadgetName.position = CGPoint(x: -24, y: 9)
            gadgetRow.addChild(gadgetName)
            let detail = equipped.map { "\($0.blurb) (\($0.cost) spools)" } ?? "Tap the arrows to equip one"
            let gadgetBlurb = label(detail, size: 11, color: Palette.stormDark, style: .body, anchorX: 0)
            gadgetBlurb.position = CGPoint(x: -24, y: -12)
            gadgetRow.addChild(gadgetBlurb)
            let maxWidth = cardW / 2 - 62 - (-24)
            for sprite in [gadgetBlurb, passive, gadgetName, name] where sprite.size.width > maxWidth {
                sprite.setScale(maxWidth / sprite.size.width)
            }
            addArrows(to: gadgetRow, width: cardW - 40) { [unowned self] step in
                let options: [Gadget?] = [nil] + gadgets.map { Optional($0) }
                let at = options.firstIndex { $0 == equipped } ?? 0
                let next = options[(at + step + options.count) % options.count]
                Progress.shared.update { $0.equippedGadget = next?.rawValue }
                self.showMap()
                self.showStageCard(index)
            }
        }

        let play = paperButton("Play", width: min(220, cardW * 0.66))
        place(play, -top + 62)
        onTap(play) { [unowned self] in self.startRun(.stage(index)) }

        closeButton(at: CGPoint(x: w / 2 + cardW / 2 - 18, y: card.position.y + top - 18)) { [unowned self] in self.showMap() }
        card.setScale(0.85)
        card.run(.scale(to: 1, duration: 0.15))
    }

    /// A gold paper chevron with an ink edge and a soft drop shadow, pointing right.
    func paperChevron(size s: CGFloat) -> SKNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -0.28 * s, y: 0.46 * s))
        path.addLine(to: CGPoint(x: 0.04 * s, y: 0.46 * s))
        path.addLine(to: CGPoint(x: 0.36 * s, y: 0))
        path.addLine(to: CGPoint(x: 0.04 * s, y: -0.46 * s))
        path.addLine(to: CGPoint(x: -0.28 * s, y: -0.46 * s))
        path.addLine(to: CGPoint(x: 0.03 * s, y: 0))
        path.closeSubpath()
        let node = SKNode()
        let shadow = SKShapeNode(path: path)
        shadow.fillColor = Palette.ink.withAlphaComponent(0.3)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 1.5, y: -2)
        node.addChild(shadow)
        let face = SKShapeNode(path: path)
        face.fillColor = Palette.stitchGold
        face.strokeColor = Palette.ink
        face.lineWidth = max(2, s * 0.09)
        face.lineJoin = .round
        face.zPosition = 0.1
        node.addChild(face)
        return node
    }

    /// Left and right paper arrows on a row; the closure gets -1 or +1.
    func addArrows(to row: SKNode, width: CGFloat, action: @escaping (Int) -> Void) {
        for side in [-1, 1] {
            let s = CGFloat(side)
            let arrow = SKNode()
            if let disc = imageSprite("ui-round") {
                disc.size = CGSize(width: 34, height: 34)
                arrow.addChild(disc)
            }
            let chevron = paperChevron(size: 17)
            chevron.xScale = s
            chevron.position.x = s * 1
            chevron.zPosition = 1
            arrow.addChild(chevron)
            arrow.position = CGPoint(x: s * (width / 2 - 20), y: 0)
            // A bigger invisible tap area around the arrow.
            let hit = SKSpriteNode(color: .clear, size: CGSize(width: 46, height: 50))
            hit.zPosition = 2
            arrow.addChild(hit)
            row.addChild(arrow)
            onTap(arrow) { action(side) }
        }
    }

    // MARK: Endless, Daily, races and challenges

    func showEndlessCard() {
        let w = size.width
        _ = dimBackground { [unowned self] in self.showMap() }
        let cardW = min(w - 32, 340)
        let card = paperPanel(width: cardW, height: cardW * 0.75)
        card.position = CGPoint(x: w / 2, y: size.height * 0.52)
        card.zPosition = 11
        overlay.addChild(card)
        onTap(card) {}  // Taps on the card itself don't close it.
        let top = cardW * 0.375
        let title = label("Endless Storm", size: 26, color: Palette.stitchGold)
        title.position = CGPoint(x: 0, y: top - 44)
        card.addChild(title)
        let text = paragraph("Run as long as you can. The storm never stops, and it only gets faster.",
                             size: 14, width: cardW - 70, color: Palette.ink)
        text.position = CGPoint(x: 0, y: top - 96)
        card.addChild(text)
        let data = Progress.shared.data
        let best = label("Best: \(data.bestEndlessScore.formatted()) points  ·  \(data.bestEndlessMeters.formatted()) m",
                         size: 13, color: Palette.stormDark, style: .body)
        best.position = CGPoint(x: 0, y: top - 146)
        card.addChild(best)
        let play = paperButton("Run", width: min(200, cardW * 0.6))
        play.position = CGPoint(x: 0, y: -top + 52)
        play.zPosition = 1
        card.addChild(play)
        onTap(play) { [unowned self] in self.startRun(.endless) }
        closeButton(at: CGPoint(x: w / 2 + cardW / 2 - 18, y: card.position.y + top - 18)) { [unowned self] in self.showMap() }
    }

    func showDailyCard() {
        let storm = DailyStorm.today()
        let w = size.width
        _ = dimBackground { [unowned self] in self.showTitle() }
        let cardW = min(w - 32, 350)
        let cardH: CGFloat = 430
        let card = paperPanel(width: cardW, height: cardH)
        card.position = CGPoint(x: w / 2, y: size.height * 0.53)
        card.zPosition = 11
        overlay.addChild(card)
        onTap(card) {}  // Taps on the card itself don't close it.
        let top = cardH / 2
        func add(_ node: SKNode, _ y: CGFloat) {
            node.position.y = y
            node.zPosition = 1
            card.addChild(node)
        }
        add(label("Daily Storm #\(storm.number)", size: 26, color: Palette.stitchGold), top - 44)
        add(label("\(storm.rule.emoji) \(storm.rule.name)", size: 21, color: Palette.ink, style: .body), top - 82)
        add(label(storm.rule.blurb, size: 13, color: Palette.stormDark, style: .body), top - 108)
        let runner = Monster.named(storm.monsterID)
        if let portrait = monsterPortrait(runner, box: CGSize(width: 84, height: 84)) {
            add(portrait, top - 168)
        }
        add(label("Today's runner: \(runner.name)", size: 15, color: Palette.ink, style: .body), top - 224)
        add(paragraph("Everyone gets the same course today. Your first run is your score; after that it's practice.",
                      size: 12.5, width: cardW - 70, color: Palette.stormDark), top - 262)
        if let score = Progress.shared.data.dailyScores[storm.key] {
            add(label("Your score today: \(score.formatted())", size: 16, color: Palette.stitchGold), top - 304)
        }
        let play = paperButton(Progress.shared.data.dailyScores[storm.key] == nil ? "Play" : "Practice",
                               width: min(170, cardW * 0.48))
        play.position = CGPoint(x: -cardW * 0.22, y: -top + 58)
        play.zPosition = 1
        card.addChild(play)
        onTap(play) { [unowned self] in self.startRun(.daily(storm)) }
        let board = paperButton("Scores", width: min(150, cardW * 0.42), pulse: false)
        board.position = CGPoint(x: cardW * 0.25, y: -top + 58)
        board.zPosition = 1
        card.addChild(board)
        onTap(board) { GameCenter.showLeaderboards(GameCenter.dailyBoard) }
        addLiveRaceButton(below: card, cardHeight: cardH)
        closeButton(at: CGPoint(x: w / 2 + cardW / 2 - 18, y: card.position.y + top - 18)) { [unowned self] in self.showTitle() }
    }

    func showRaceCard(_ holiday: Holiday) {
        let w = size.width
        _ = dimBackground { [unowned self] in self.showTitle() }
        let cardW = min(w - 32, 350)
        let cardH: CGFloat = 400
        let card = paperPanel(width: cardW, height: cardH)
        card.position = CGPoint(x: w / 2, y: size.height * 0.53)
        card.zPosition = 11
        overlay.addChild(card)
        onTap(card) {}  // Taps on the card itself don't close it.
        let top = cardH / 2
        let won = Progress.shared.data.holidayWins.contains(holiday.rawValue)
        let rival = Monster.named(holiday.rivalID)
        let title = label(holiday.raceName, size: 28, color: Palette.stitchGold)
        title.position = CGPoint(x: 0, y: top - 44)
        card.addChild(title)
        let event = label("\(holiday.name) event", size: 14, color: Palette.stormDark, style: .body)
        event.position = CGPoint(x: 0, y: top - 74)
        card.addChild(event)
        if let portrait = monsterPortrait(rival, box: CGSize(width: 100, height: 100), locked: false) {
            portrait.position = CGPoint(x: 0, y: top - 146)
            card.addChild(portrait)
        }
        let goal = won
            ? "You beat \(holiday.rivalName)! \(holiday.rivalName) is in your crew. Race again any time."
            : "Collect more than \(holiday.rivalTarget) spools in \(Int(holiday.raceLength)) seconds to beat \(holiday.rivalName) and add them to your crew."
        let text = paragraph(goal, size: 14, width: cardW - 70, color: Palette.ink)
        text.position = CGPoint(x: 0, y: top - 238)
        card.addChild(text)
        let play = paperButton("Race!", width: min(200, cardW * 0.6))
        play.position = CGPoint(x: 0, y: -top + 56)
        play.zPosition = 1
        card.addChild(play)
        onTap(play) { [unowned self] in self.startRun(.race(holiday)) }
        closeButton(at: CGPoint(x: w / 2 + cardW / 2 - 18, y: card.position.y + top - 18)) { [unowned self] in self.showTitle() }
    }

    /// Opens a friend's challenge if the app was launched from a link.
    func checkPendingLink() {
        // On first launch the story plays first; the link waits until it ends.
        guard Progress.shared.data.storySeen, state == .title || state == .menu || state == .over,
              let url = DeepLink.pending else { return }
        DeepLink.pending = nil
        guard let challenge = Share.challenge(from: url) else { return }
        let storm = DailyStorm(number: challenge.daily)
        let w = size.width
        _ = dimBackground { [unowned self] in self.showTitle() }
        let cardW = min(w - 32, 340)
        let card = paperPanel(width: cardW, height: cardW * 0.85)
        card.position = CGPoint(x: w / 2, y: size.height * 0.53)
        card.zPosition = 11
        overlay.addChild(card)
        onTap(card) {}  // Taps on the card itself don't close it.
        let top = cardW * 0.425
        let title = label("\(challenge.from) challenges you!", size: 22, color: Palette.stitchGold)
        title.position = CGPoint(x: 0, y: top - 44)
        if title.size.width > cardW - 50 { title.setScale((cardW - 50) / title.size.width) }
        card.addChild(title)
        let detail = paragraph("Beat \(challenge.target.formatted()) points on Daily Storm #\(storm.number): \(storm.rule.emoji) \(storm.rule.name), running as \(Monster.named(storm.monsterID).name).",
                               size: 15, width: cardW - 70, color: Palette.ink)
        detail.position = CGPoint(x: 0, y: top - 112)
        card.addChild(detail)
        let play = paperButton("Accept", width: min(200, cardW * 0.6))
        play.position = CGPoint(x: 0, y: -top + 54)
        play.zPosition = 1
        card.addChild(play)
        onTap(play) { [unowned self] in self.startRun(.challenge(storm, target: challenge.target, from: challenge.from)) }
        closeButton(at: CGPoint(x: w / 2 + cardW / 2 - 18, y: card.position.y + top - 18)) { [unowned self] in self.showTitle() }
    }

    // MARK: Trophy case

    func showTrophyCase(tab: Int) {
        state = .menu
        clearScreen()
        hud.alpha = 0
        let w = size.width
        let h = size.height
        // Shelf geometry, in pixels of the trophy-case painting (941 x 1672, y from the top):
        // the board each row stands on, the top of each compartment, and the inside walls.
        let artSize = CGSize(width: 941, height: 1672)
        let shelfLines: [CGFloat] = [692, 888, 1088, 1300]
        let compartmentTops: [CGFloat] = [560, 745, 945, 1150]
        let insideLeft: CGFloat = 150, insideRight: CGFloat = 795
        var caseFrame = CGRect(x: (w - h * artSize.width / artSize.height) / 2, y: 0,
                               width: h * artSize.width / artSize.height, height: h)
        if let shelf = imageSprite("trophy-case") {
            let k = max(w / shelf.size.width, h / shelf.size.height)
            shelf.size = CGSize(width: shelf.size.width * k, height: shelf.size.height * k)
            shelf.position = CGPoint(x: w / 2, y: h / 2)
            overlay.addChild(shelf)
            caseFrame = shelf.frame
        } else {
            let wall = SKSpriteNode(color: UIColor(hex: 0x6B4A2E), size: size)
            wall.anchorPoint = .zero
            overlay.addChild(wall)
        }
        backButton { [unowned self] in self.showTitle() }

        // Tabs.
        let tabs = ["Monsters", "Trophies"]
        for (i, name) in tabs.enumerated() {
            let pill = paperButton(name, width: 150, pulse: false)
            pill.setScale(i == tab ? 0.82 : 0.7)
            pill.alpha = i == tab ? 1 : 0.7
            pill.position = CGPoint(x: w / 2 + (CGFloat(i) - 0.5) * 140, y: h - safeTop - 32)
            pill.zPosition = 5
            overlay.addChild(pill)
            onTap(pill) { [unowned self] in self.showTrophyCase(tab: i) }
        }

        func onCase(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: caseFrame.minX + x / artSize.width * caseFrame.width,
                    y: caseFrame.maxY - y / artSize.height * caseFrame.height)
        }
        let unit = caseFrame.width / artSize.width
        // Three to a shelf, or four once the cast outgrows twelve.
        let itemCount = tab == 0 ? Monster.roster.count : Trophy.allCases.count
        let perShelfCount = max(3, (itemCount + 3) / 4)
        let slotW = (insideRight - insideLeft) / CGFloat(perShelfCount) * unit
        let progress = Progress.shared

        // A paper strip along the bottom tells you about whatever you tap.
        let info = SKNode()
        info.position = CGPoint(x: w / 2, y: safeBottom + 36)
        info.zPosition = 6
        overlay.addChild(info)
        let infoW = min(w - 32, 420)
        let strip = SKShapeNode(rect: CGRect(x: -infoW / 2, y: -27, width: infoW, height: 54), cornerRadius: 27)
        strip.fillColor = Palette.paper
        strip.strokeColor = Palette.stitchGold
        strip.lineWidth = 3
        info.addChild(strip)
        let infoText = SKNode()
        infoText.zPosition = 1
        info.addChild(infoText)
        let showInfo: (String, String) -> Void = { [unowned self] title, detail in
            infoText.removeAllChildren()
            let top = self.label(title, size: 15, color: Palette.stitchGold)
            let bottom = self.label(detail, size: 12, color: Palette.ink, style: .body)
            for sprite in [top, bottom] where sprite.size.width > infoW - 40 {
                sprite.setScale((infoW - 40) / sprite.size.width)
            }
            top.position = CGPoint(x: 0, y: 9)
            bottom.position = CGPoint(x: 0, y: -10)
            infoText.addChild(top)
            infoText.addChild(bottom)
        }

        // Rows fill top to bottom, three to a shelf, spread as evenly as the count allows.
        func slots(for count: Int) -> [(row: Int, x: CGFloat)] {
            var result: [(row: Int, x: CGFloat)] = []
            let base = count / shelfLines.count, extra = count % shelfLines.count
            let center = (insideLeft + insideRight) / 2
            let perShelf = CGFloat(max(3, (count + shelfLines.count - 1) / shelfLines.count))
            for row in 0..<shelfLines.count {
                let inRow = base + (row < extra ? 1 : 0)
                for i in 0..<inRow {
                    let x = center + (CGFloat(i) - CGFloat(inRow - 1) / 2) * (insideRight - insideLeft) / perShelf
                    result.append((row, x))
                }
            }
            return result
        }

        /// A little name tag pinned to the front of the shelf board.
        func nameTag(_ text: String, highlighted: Bool, fraction: CGFloat?) -> SKNode {
            let tag = SKNode()
            let tagW = slotW * 0.86, tagH: CGFloat = fraction == nil ? 20 : 26
            let paper = SKShapeNode(rect: CGRect(x: -tagW / 2, y: -tagH / 2, width: tagW, height: tagH), cornerRadius: 6)
            paper.fillColor = highlighted ? Palette.stitchGold : Palette.paper
            paper.strokeColor = highlighted ? .white : UIColor(hex: 0x8A5A2B)
            paper.lineWidth = 1.5
            tag.addChild(paper)
            let name = label(text, size: 12, color: highlighted ? .white : Palette.ink)
            if name.size.width > tagW - 10 { name.setScale((tagW - 10) / name.size.width) }
            name.position = CGPoint(x: 0, y: fraction == nil ? 0 : 4)
            name.zPosition = 1
            tag.addChild(name)
            if let fraction {
                let barW = tagW - 16
                let bar = SKShapeNode(rect: CGRect(x: -barW / 2, y: -9, width: barW, height: 4), cornerRadius: 2)
                bar.fillColor = UIColor(white: 0, alpha: 0.15)
                bar.strokeColor = .clear
                bar.zPosition = 1
                tag.addChild(bar)
                if fraction > 0.01 {
                    let fill = SKShapeNode(rect: CGRect(x: -barW / 2, y: -9, width: barW * min(1, fraction), height: 4), cornerRadius: 2)
                    fill.fillColor = Palette.stitchGold
                    fill.strokeColor = .clear
                    fill.zPosition = 2
                    tag.addChild(fill)
                }
            }
            return tag
        }

        if tab == 0 {
            for (i, monster) in Monster.roster.enumerated() {
                let slot = slots(for: Monster.roster.count)[i]
                let unlocked = progress.isUnlocked(monster)
                let selected = unlocked && monster.id == self.monster.id
                let standPoint = onCase(slot.x, shelfLines[slot.row])
                let roomH = (shelfLines[slot.row] - compartmentTops[slot.row]) * unit
                let item = SKNode()
                item.position = standPoint
                item.zPosition = 2
                overlay.addChild(item)
                if selected {
                    let glow = SKShapeNode(ellipseOf: CGSize(width: slotW * 0.8, height: 14))
                    glow.fillColor = Palette.stitchGold.withAlphaComponent(0.55)
                    glow.strokeColor = .clear
                    glow.glowWidth = 6
                    glow.position = CGPoint(x: 0, y: 3)
                    item.addChild(glow)
                    glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.5, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])))
                }
                if let portrait = monsterPortrait(monster, box: CGSize(width: slotW * 0.86, height: roomH * 0.86), locked: !unlocked) {
                    portrait.anchorPoint = CGPoint(x: 0.5, y: 0)
                    portrait.position = CGPoint(x: 0, y: 1)
                    portrait.zPosition = 1
                    item.addChild(portrait)
                } else if let badge = imageSprite("badge-locked") {
                    badge.size = CGSize(width: roomH * 0.6, height: roomH * 0.6)
                    badge.anchorPoint = CGPoint(x: 0.5, y: 0)
                    item.addChild(badge)
                }
                let tag = nameTag(unlocked ? monster.name : "???", highlighted: selected,
                                  fraction: unlocked ? nil : CGFloat(progress.progress(toward: monster)))
                tag.position = CGPoint(x: 0, y: -18 * max(1, unit * 1.6))
                tag.zPosition = 3
                item.addChild(tag)
                onTap(item) { [unowned self] in
                    if unlocked {
                        Monster.selectedIndex = i
                        self.monster = monster
                        self.currentPose = ""
                        self.portraitGreetID = monster.id
                        self.audio.chime(step: i % 8)
                        self.showTrophyCase(tab: 0)
                    } else {
                        let percent = Int(progress.progress(toward: monster) * 100)
                        showInfo("Locked: \(percent)% there", monster.unlock.text)
                    }
                }
            }
            showInfo("\(self.monster.name) is running", self.monster.passive)
        } else {
            let earnedCount = Trophy.allCases.filter { progress.hasTrophy($0) }.count
            for (i, trophy) in Trophy.allCases.enumerated() {
                let slot = slots(for: Trophy.allCases.count)[i]
                let earned = progress.hasTrophy(trophy)
                let standPoint = onCase(slot.x, shelfLines[slot.row])
                let roomH = (shelfLines[slot.row] - compartmentTops[slot.row]) * unit
                let item = SKNode()
                item.position = standPoint
                item.zPosition = 2
                overlay.addChild(item)
                let iconH = roomH * 0.72
                let cup: SKSpriteNode
                if let image = imageSprite("trophy-\(trophy.rawValue)") ?? imageSprite("menu-trophy") {
                    cup = image
                    let k = iconH / image.size.height
                    cup.size = CGSize(width: image.size.width * k, height: iconH)
                } else {
                    let star = art.star(filled: earned)
                    cup = SKSpriteNode(texture: star.texture, size: CGSize(width: iconH, height: iconH))
                }
                cup.anchorPoint = CGPoint(x: 0.5, y: 0)
                cup.position = CGPoint(x: 0, y: 1)
                cup.zPosition = 1
                if earned {
                    cup.run(.repeatForever(.sequence([.wait(forDuration: 2 + Double(i) * 0.3),
                                                      .scale(to: 1.08, duration: 0.15), .scale(to: 1, duration: 0.2)])))
                } else {
                    cup.color = Palette.ink
                    cup.colorBlendFactor = 1
                    cup.alpha = 0.4
                }
                item.addChild(cup)
                let tag = nameTag(trophy.name, highlighted: earned, fraction: nil)
                tag.position = CGPoint(x: 0, y: -18 * max(1, unit * 1.6))
                tag.zPosition = 3
                item.addChild(tag)
                onTap(item) {
                    showInfo(earned ? "\(trophy.name): earned!" : trophy.name, trophy.detail)
                }
            }
            showInfo("\(earnedCount) of \(Trophy.allCases.count) trophies", "Tap a trophy to see how to earn it")
        }
    }

    // MARK: Settings

    func showSettings() {
        let w = size.width
        _ = dimBackground { [unowned self] in self.showTitle() }
        let cardW = min(w - 32, 340)
        let rows = settingsRows()
        let rowH: CGFloat = 44
        let gap: CGFloat = 10
        let cardH = CGFloat(rows.count) * (rowH + gap) + 150
        let card = paperPanel(width: cardW, height: cardH, tallArt: true)
        card.position = CGPoint(x: w / 2, y: min(size.height * 0.52, size.height - safeTop - 20 - cardH / 2))
        card.zPosition = 11
        overlay.addChild(card)
        onTap(card) {}  // Taps on the card itself don't close it.
        let top = cardH / 2
        let title = label("Settings", size: 26, color: Palette.stitchGold)
        title.position = CGPoint(x: 0, y: top - 62)
        card.addChild(title)
        let rowW = cardW - 70
        for (i, row) in rows.enumerated() {
            let node = settingsRow(row.title, value: row.value, width: rowW, height: rowH)
            node.position = CGPoint(x: 0, y: top - 112 - CGFloat(i) * (rowH + gap))
            node.zPosition = 1
            card.addChild(node)
            onTap(node, row.action)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let footer = label("Storm Stitch \(version)", size: 11, color: Palette.stormDark, style: .body)
        footer.position = CGPoint(x: 0, y: -top + 46)
        card.addChild(footer)
        closeButton(at: CGPoint(x: w / 2 + cardW / 2 - 24, y: card.position.y + top - 30)) { [unowned self] in self.showTitle() }
    }

    /// One settings line: the same size for every row, name on the left, an On/Off chip or an arrow on the right.
    func settingsRow(_ title: String, value: Bool?, width: CGFloat, height: CGFloat) -> SKNode {
        let node = SKNode()
        let strip = SKShapeNode(rect: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerRadius: height / 2)
        strip.fillColor = UIColor.white.withAlphaComponent(0.7)
        strip.strokeColor = Palette.stitchGold
        strip.lineWidth = 2
        node.addChild(strip)
        let name = label(title, size: 16, color: Palette.ink, style: .body, anchorX: 0)
        name.position = CGPoint(x: -width / 2 + 20, y: 0)
        name.zPosition = 1
        let room = width - 20 - 86
        if name.size.width > room { name.setScale(room / name.size.width) }
        node.addChild(name)
        if let on = value {
            let chipW: CGFloat = 58
            let chip = SKShapeNode(rect: CGRect(x: -chipW / 2, y: -14, width: chipW, height: 28), cornerRadius: 14)
            chip.fillColor = on ? UIColor(hex: 0x5DBB63) : UIColor(hex: 0xB9B6C6)
            chip.strokeColor = .clear
            chip.position = CGPoint(x: width / 2 - 12 - chipW / 2, y: 0)
            chip.zPosition = 1
            node.addChild(chip)
            let text = label(on ? "On" : "Off", size: 14, color: .white)
            text.zPosition = 1
            chip.addChild(text)
        } else {
            let arrow = paperChevron(size: 16)
            arrow.position = CGPoint(x: width / 2 - 22, y: 0)
            arrow.zPosition = 1
            node.addChild(arrow)
        }
        return node
    }

    func settingsRows() -> [(title: String, value: Bool?, action: () -> Void)] {
        let data = Progress.shared.data
        let refresh: () -> Void = { [unowned self] in
            self.syncSettings()
            self.showTitle()
            self.showSettings()
        }
        var rows: [(title: String, value: Bool?, action: () -> Void)] = [
            ("Music", data.music, { Progress.shared.update { $0.music.toggle() }; refresh() }),
            ("Sound effects", data.sound, { Progress.shared.update { $0.sound.toggle() }; refresh() }),
            ("Vibration", data.haptics, { Progress.shared.update { $0.haptics.toggle() }; refresh() }),
            ("Watch the story", nil, { [unowned self] in self.playStory() }),
            ("Game Center", nil, { GameCenter.showLeaderboards() }),
            ("Privacy and support", nil, {
                if let url = URL(string: "\(Share.site)/privacy/") { UIApplication.shared.open(url) }
            })
        ]
        #if DEBUG
        let looks = ["Auto", "None", "Harvest", "Snow"]
        let look = looks[max(0, min(looks.count - 1, tuning.holidayOverride))]
        rows.append(("Dev: holiday look: \(look)", nil, { [unowned self] in
            // Cycles Auto, None, Harvest, Snow and shows it at once on the title screen behind.
            self.tuning.holidayOverride = (self.tuning.holidayOverride + 1) % looks.count
            self.showTitle()
            self.showSettings()
        }))
        rows.append(("Dev: unlock everything", nil, { [unowned self] in
            Progress.shared.unlockEverything()
            self.showTitle()
        }))
        rows.append(("Dev: reset progress", nil, { [unowned self] in
            Progress.shared.resetAll()
            Monster.selectedIndex = 0
            self.showTitle()
        }))
        #endif
        return rows
    }

    /// Copies saved settings into the live switches.
    func syncSettings() {
        let data = Progress.shared.data
        tuning.musicOn = data.music
        tuning.soundOn = data.sound
        tuning.hapticsOn = data.haptics
    }

    // MARK: Results

    func showRunResults(caught: Bool, finished: Bool, stars: Int, unlocks: [UnlockEvent]) {
        clearScreen()
        hud.removeAllActions()
        hud.run(.fadeOut(withDuration: 0.25))
        let w = size.width
        let cardW = min(w - 16, 390)
        let k = cardW / 380
        let cardH = 322 * k
        // Everything sits inside the stitched border: its top and bottom stitches are about 14% of
        // the drawn card's height in from each edge.
        let innerTop = cardH / 2 - cardW * 0.75 * 0.145
        let card = paperPanel(width: cardW, height: cardH, tallArt: true)
        card.position = CGPoint(x: w / 2, y: size.height - safeTop - 12 - cardH / 2)
        overlay.addChild(card)

        // Title and subtitle.
        var title = caught ? "Caught by the storm!" : "Out of hearts!"
        var subtitle = ""
        var starLabels = ["Finish", "No hits", "Stitched"]
        switch mode {
        case .stage(let index):
            let stage = Stage.all[index]
            if finished {
                title = "\(stage.name) stitched!"
                subtitle = stage.beat
            } else {
                subtitle = "Stage \(stage.number): try again!"
            }
            starLabels = ["Finish", stage.challenge.text, "Stitched"]
        case .daily(let storm):
            title = finished ? "Daily #\(storm.number) done!" : title
            subtitle = "\(storm.rule.emoji) \(storm.rule.name)  ·  " + (lastRunCountedDaily ? "Today's score!" : "Practice run")
        case .challenge(_, let target, let from):
            title = stats.score > target ? "You beat \(from)!" : "\(from) wins this one"
            subtitle = "Their score: \(target.formatted())  ·  Yours: \(stats.score.formatted())"
        case .race(let holiday):
            let won = finished && stats.spools > holiday.rivalTarget
            title = won ? "You beat \(holiday.rivalName)!" : "\(holiday.rivalName) wins!"
            subtitle = "You: \(stats.spools) spools  ·  \(holiday.rivalName): \(holiday.rivalTarget)"
            starLabels = ["Win", "No hits", "Stitched"]
        case .endless:
            title = "Endless: \(Int(stats.distance).formatted()) m"
            subtitle = "Best: \(Progress.shared.data.bestEndlessMeters.formatted()) m"
            starLabels = ["1,000 m", "No hits", "Stitched"]
        }
        if let live = liveRaceResultText() { title = live.title; subtitle = live.subtitle }
        let titleSprite = label(title, size: 23 * k, color: finished ? Palette.stitchGold : .white)
        if titleSprite.size.width > cardW - 60 { titleSprite.setScale((cardW - 60) / titleSprite.size.width) }
        titleSprite.position = CGPoint(x: 0, y: innerTop - 20 * k)
        titleSprite.zPosition = 1
        card.addChild(titleSprite)
        if !subtitle.isEmpty {
            let sub = paragraph(subtitle, size: 12.5 * k, width: cardW - 80, color: Palette.ink)
            sub.position = CGPoint(x: 0, y: innerTop - 46 * k)
            sub.zPosition = 1
            card.addChild(sub)
        }

        // Stars.
        for i in 0..<3 {
            let has = i < stars
            let starArt = illustrated(has ? "ui-star" : "ui-star-empty", width: 44 * k) ?? art.star(filled: has)
            let star = SKSpriteNode(texture: starArt.texture, size: CGSize(width: 44 * k, height: 44 * k))
            star.position = CGPoint(x: CGFloat(i - 1) * 84 * k, y: innerTop - 88 * k)
            star.zPosition = 1
            // Earned stars stamp down: they drop in big and tilted, overshoot, settle, and sparkle.
            // Empty stars just fade in, so the earned ones stand out.
            let delay = 0.38 + Double(i) * 0.2
            if Motion.reduced || !has {
                star.alpha = 0
                star.run(.sequence([.wait(forDuration: delay), .fadeAlpha(to: has ? 1 : 0.75, duration: 0.18)]))
            } else {
                star.setScale(1.9)
                star.alpha = 0
                star.zRotation = 0.5
                star.run(.sequence([
                    .wait(forDuration: delay),
                    .group([
                        .fadeIn(withDuration: 0.08),
                        .scale(to: 1, duration: 0.26).overshoot(),
                        .rotate(toAngle: 0, duration: 0.26).glide()
                    ])
                ]))
            }
            star.run(.sequence([
                .wait(forDuration: delay + 0.12),
                .run { [weak self, weak star, weak card] in
                    guard has, let self else { return }
                    self.audio.chime(step: 2 + i * 2)
                    self.haptics.spool()
                    if !Motion.reduced, let star, let card {
                        // The effects layer sits under the results overlay, so lift the sparkles above the card.
                        let sparks = self.emitter(texture: self.art.spark.texture, at: card.convert(star.position, to: self),
                                                  count: 12, color: Palette.stitchGold, speed: 140, spread: .pi * 2,
                                                  angle: .pi / 2, life: 0.5, gravity: -200, scale: 0.6)
                        sparks.move(toParent: self.overlay)
                        sparks.zPosition = 5
                    }
                }
            ]))
            card.addChild(star)
            let caption = label(starLabels[i], size: 10 * k, color: Palette.stormDark, style: .body)
            if caption.size.width > 82 * k { caption.setScale(82 * k / caption.size.width) }
            caption.position = CGPoint(x: star.position.x, y: innerTop - 120 * k)
            caption.zPosition = 1
            card.addChild(caption)
        }

        // Stats.
        // Each stat is a number plus how to print it, so it can count up from zero.
        let clock: (Int) -> String = { "\($0 / 60):\(String(format: "%02d", $0 % 60))" }
        let plain: (Int) -> String = { "\($0)" }
        var cells: [(name: String, value: Int, format: (Int) -> String)] = [
            ("Spools", stats.spools, plain),
            ("Distance", Int(stats.distance), { "\($0) m" }),
            ("Time", Int(stats.elapsed), clock)
        ]
        if mode.isDailyLike || mode == .endless {
            cells.append(("Score", stats.score, { $0.formatted() }))
        } else {
            cells.append(("Stitched", stats.meterPercent, { "\($0)%" }))
        }
        cells.append(("Streak", stats.bestStreak, plain))
        cells.append(("Close calls", stats.closeCalls, plain))
        // With powers to show, the stats lift a little to make room for one row of them under the stats.
        let statsLift: CGFloat = stats.powers.isEmpty ? 0 : 6
        for (index, cell) in cells.enumerated() {
            let column = CGFloat(index % 3 - 1)
            let rowY = innerTop - ((index < 3 ? 150 : 192) - statsLift) * k
            let value = SKLabelNode(fontNamed: "Fredoka-SemiBold")
            value.text = cell.format(cell.value)
            if !Motion.reduced && cell.value > 0 {
                // Tick up from zero while the stars land; the top row first, then the bottom row.
                value.text = cell.format(0)
                value.run(.sequence([
                    .wait(forDuration: 0.35 + (index < 3 ? 0 : 0.15)),
                    .countUp(to: cell.value, duration: 0.75, format: cell.format)
                ]))
            }
            value.fontSize = 18 * k
            value.fontColor = Palette.ink
            value.verticalAlignmentMode = .center
            value.position = CGPoint(x: column * cardW * 0.27, y: rowY)
            value.zPosition = 1
            card.addChild(value)
            let name = SKLabelNode(fontNamed: "NunitoSans-Bold")
            name.text = cell.name
            name.fontSize = 10 * k
            name.fontColor = Palette.stormDark
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: value.position.x, y: rowY - 15 * k)
            name.zPosition = 1
            card.addChild(name)
        }

        // Powers taken at the gates: one compact row of icons and names, inside the bottom stitches.
        if let powerRow = resultsPowerRow(stats.powers, unit: k, maxWidth: cardW - 90) {
            powerRow.position = CGPoint(x: 0, y: innerTop - 223 * k)
            powerRow.zPosition = 1
            powerRow.alpha = 0
            powerRow.run(.sequence([.wait(forDuration: Motion.reduced ? 0.3 : 1.0), .fadeIn(withDuration: 0.25)]))
            card.addChild(powerRow)
        }

        // The card rises into place and pops slightly past full size before settling.
        let home = card.position
        card.alpha = 0
        if Motion.reduced {
            card.run(.fadeIn(withDuration: 0.2))
        } else {
            card.setScale(0.82)
            card.position.y -= 40
            card.run(.group([
                .fadeIn(withDuration: 0.12),
                .scale(to: 1, duration: 0.34).overshoot(),
                .move(to: home, duration: 0.34).glide()
            ]))
        }

        // Unlocks, one after another.
        var y = home.y - cardH / 2 - 34
        for (i, event) in unlocks.prefix(3).enumerated() {
            let banner = SKNode()
            banner.position = CGPoint(x: w / 2, y: y)
            banner.zPosition = 3
            overlay.addChild(banner)
            let pill = SKShapeNode(rect: CGRect(x: -cardW / 2 + 12, y: -24, width: cardW - 24, height: 48), cornerRadius: 24)
            pill.fillColor = Palette.paper
            pill.strokeColor = Palette.stitchGold
            pill.lineWidth = 3
            banner.addChild(pill)
            if let image = imageSprite(event.image) {
                let s = 38 / max(image.size.width, image.size.height)
                image.size = CGSize(width: image.size.width * s, height: image.size.height * s)
                image.position = CGPoint(x: -cardW / 2 + 40, y: 0)
                image.zPosition = 1
                banner.addChild(image)
            }
            let text = label(event.title, size: 15, color: Palette.stitchGold, anchorX: 0)
            text.position = CGPoint(x: -cardW / 2 + 68, y: 8)
            text.zPosition = 1
            banner.addChild(text)
            let detail = label(event.detail, size: 10.5, color: Palette.stormDark, style: .body, anchorX: 0)
            detail.position = CGPoint(x: -cardW / 2 + 68, y: -11)
            detail.zPosition = 1
            banner.addChild(detail)
            let room = cardW / 2 - 24 - (-cardW / 2 + 68)
            for sprite in [text, detail] where sprite.size.width > room {
                sprite.setScale(room / sprite.size.width)
            }
            // Unlocks slide up from below and pop, one after another, once the stars have landed.
            banner.alpha = 0
            let arrive: SKAction
            if Motion.reduced {
                arrive = .fadeIn(withDuration: 0.2)
            } else {
                banner.setScale(0.85)
                banner.position.y -= 28
                arrive = .group([
                    .fadeIn(withDuration: 0.12),
                    .scale(to: 1, duration: 0.3).overshoot(),
                    .move(to: CGPoint(x: w / 2, y: y), duration: 0.3).glide()
                ])
            }
            banner.run(.sequence([
                .wait(forDuration: 1.15 + Double(i) * 0.45),
                arrive,
                .run { [weak self] in
                    self?.audio.play(.stitchFull, volume: 0.5)
                    self?.haptics.success()
                }
            ]))
            y -= 56
        }

        // Buttons.
        var buttons: [(String, () -> Void)] = []
        switch mode {
        case .stage(let index):
            if finished && index + 1 < Stage.all.count {
                buttons.append(("Next", { [unowned self] in
                    self.showMap(world: World.index(ofStage: index + 1))
                    self.showStageCard(index + 1)
                }))
            } else {
                buttons.append(("Retry", { [unowned self] in self.startRun(.stage(index)) }))
            }
            // Clearing a world's last stage takes you straight to the next world's map.
            let mapTarget = World.index(ofStage: finished ? min(index + 1, Stage.all.count - 1) : index)
            buttons.append(("Map", { [unowned self] in self.showMap(world: mapTarget) }))
        case .daily(let storm):
            let result = stats
            let earned = stars
            buttons.append(("Share", { [unowned self] in self.shareDaily(storm, stats: result, stars: earned) }))
            buttons.append(("Challenge", { [unowned self] in self.shareChallenge(storm, stats: result) }))
            buttons.append(("Scores", { GameCenter.showLeaderboards(GameCenter.dailyBoard) }))
            buttons.append(("Home", { [unowned self] in self.showTitle() }))
        case .challenge(let storm, let target, let from):
            let result = stats
            let earned = stars
            buttons.append(("Share", { [unowned self] in
                self.shareDaily(storm, stats: result, stars: earned, beat: (from, target))
            }))
            buttons.append(("Retry", { [unowned self] in self.startRun(self.mode) }))
            buttons.append(("Home", { [unowned self] in self.showTitle() }))
        case .race(let holiday):
            buttons.append(("Retry", { [unowned self] in self.startRun(.race(holiday)) }))
            buttons.append(("Home", { [unowned self] in self.showTitle() }))
        case .endless:
            buttons.append(("Retry", { [unowned self] in self.startRun(.endless) }))
            buttons.append(("Scores", { GameCenter.showLeaderboards(GameCenter.endlessBoard) }))
            buttons.append(("Home", { [unowned self] in self.showTitle() }))
        }
        if let live = liveRaceResultButtons() { buttons = live }
        let perRow = buttons.count == 3 ? 3 : 2
        let buttonW = min(190, (w - 24) / CGFloat(perRow) - 8)
        let buttonH = buttonW * 300.0 / 720.0
        let firstRowY = y - 6 - buttonH / 2
        for (i, item) in buttons.enumerated() {
            let row = i / perRow
            let column = i % perRow
            let inRow = min(perRow, buttons.count - row * perRow)
            let button = paperButton(item.0, width: buttonW, pulse: i == 0)
            button.position = CGPoint(x: w / 2 + (CGFloat(column) - CGFloat(inRow - 1) / 2) * (buttonW + 8),
                                      y: firstRowY - CGFloat(row) * (buttonH + 8))
            button.zPosition = 3
            button.alpha = 0
            button.run(.sequence([.wait(forDuration: 0.6), .fadeIn(withDuration: 0.2)]))
            overlay.addChild(button)
            onTap(button, item.1)
        }

        // Clearing Notebook Meadow's last stage for the first time asks for a review, once the
        // stars, counts and unlock banners have all landed.
        if case .stage(let index) = mode, finished, stars > 0, index == World.stagesPerWorld - 1,
           Progress.shared.data.reviewRequested != true {
            scheduleReviewPrompt()
        }
    }

    /// The powers taken in a run as one row for the results card: an icon and a name for each
    /// ("Lv2" after one taken more than once). Centered on its origin and fitted to `maxWidth`.
    /// Nil when no powers were taken.
    func resultsPowerRow(_ picks: [(kind: PowerKind, level: Int)], unit k: CGFloat, maxWidth: CGFloat) -> SKNode? {
        guard !picks.isEmpty else { return nil }
        let row = SKNode()
        let iconSize = 15 * k
        let gap = 12 * k
        var x: CGFloat = 0
        for pick in picks {
            let icon: SKNode
            if let painted = powerIconSprite(pick.kind, fit: iconSize) {
                icon = painted
            } else {
                // The same felt color as its door and HUD badge.
                let disc = SKShapeNode(circleOfRadius: iconSize * 0.42)
                disc.fillColor = pick.kind.color
                disc.strokeColor = Palette.ink
                disc.lineWidth = max(1, 1.5 * k)
                icon = disc
            }
            icon.position = CGPoint(x: x + iconSize / 2, y: 0)
            row.addChild(icon)
            x += iconSize + 4 * k
            let text = pick.level > 1 ? "\(pick.kind.name) Lv\(pick.level)" : pick.kind.name
            let name = label(text, size: 11 * k, color: Palette.ink, style: .body, anchorX: 0)
            name.position = CGPoint(x: x, y: 0)
            row.addChild(name)
            x += name.size.width + gap
        }
        let width = x - gap
        for child in row.children {
            child.position.x -= width / 2
        }
        if width > maxWidth { row.setScale(maxWidth / width) }
        return row
    }

    /// Asks StoreKit for the review prompt a few seconds after the results card settles. Skipped if a
    /// run has started by then (the flag stays unset, so the next clear of the stage tries again).
    func scheduleReviewPrompt() {
        removeAction(forKey: "reviewPrompt")
        run(.sequence([
            .wait(forDuration: 3.2),
            .run { [weak self] in
                guard let self, self.state == .over || self.state == .menu || self.state == .title,
                      Progress.shared.data.reviewRequested != true,
                      let windowScene = self.view?.window?.windowScene else { return }
                Progress.shared.update { $0.reviewRequested = true }
                Task { @MainActor in
                    AppStore.requestReview(in: windowScene)
                }
            }
        ]), withKey: "reviewPrompt")
    }

    // MARK: Sharing

    func shareDaily(_ storm: DailyStorm, stats: RunStats, stars: Int, beat: (name: String, target: Int)? = nil) {
        let text = Share.text(storm: storm, stats: stats, stars: stars, beat: beat)
        let image = Share.card(storm: storm, title: "Daily #\(storm.number)", stats: stats, stars: stars, monsterID: storm.monsterID)
        var items: [Any] = [text, image]
        if let url = Share.challengeURL(daily: storm.number, score: stats.score, name: GameCenter.playerName ?? "A friend") {
            items.append(url)
        }
        Share.present(items: items)
    }

    func shareChallenge(_ storm: DailyStorm, stats: RunStats) {
        let name = GameCenter.playerName ?? "A friend"
        guard let url = Share.challengeURL(daily: storm.number, score: stats.score, name: name) else { return }
        let text = "I scored \(stats.score.formatted()) on Storm Stitch Daily #\(storm.number) \(storm.rule.emoji). Same course, your turn. Can you beat me?"
        Share.present(items: [text, url])
    }

    // MARK: Story

    func playStory() {
        state = .story
        clearScreen()
        hud.alpha = 0
        story?.removeFromParent()
        let player = StoryPlayer(size: size, safeTop: safeTop, safeBottom: safeBottom) { [unowned self] in
            Progress.shared.update { $0.storySeen = true }
            self.story = nil  // The player fades itself out over the title, then removes itself.
            self.showTitle()
        }
        player.zPosition = 1200
        addChild(player)
        story = player
        audio.startStoryScore()
        player.start()
    }
}
