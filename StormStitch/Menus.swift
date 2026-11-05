import SpriteKit
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
    func paperPanel(width: CGFloat, height: CGFloat) -> SKNode {
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
        if let image = artImage(icon) {
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

    /// A front-facing monster fitted inside a box, breathing and blinking.
    func monsterPortrait(_ monster: Monster, box: CGSize, locked: Bool = false) -> SKSpriteNode? {
        guard let sprite = imageSprite("\(monster.id)-front") else { return nil }
        let k = min(box.width / sprite.size.width, box.height / sprite.size.height)
        sprite.size = CGSize(width: sprite.size.width * k, height: sprite.size.height * k)
        if locked {
            sprite.color = Palette.ink
            sprite.colorBlendFactor = 1
            sprite.alpha = 0.45
        } else {
            bringToLife(sprite, id: monster.id)
        }
        return sprite
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
        applyTheme(currentHoliday())
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
        onTap(play) { [unowned self] in self.showMap() }

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

    func showMap() {
        state = .menu
        clearScreen()
        hud.alpha = 0
        let w = size.width
        let h = size.height
        let progress = Progress.shared

        // Background: the gray map, with color showing through around cleared stages.
        let background = SKNode()
        overlay.addChild(background)
        func fill(_ name: String, fallback: UIColor) -> SKNode {
            if let sprite = imageSprite(name) {
                let k = max(w / sprite.size.width, h / sprite.size.height)
                sprite.size = CGSize(width: sprite.size.width * k, height: sprite.size.height * k)
                sprite.position = CGPoint(x: w / 2, y: h / 2)
                return sprite
            }
            let plain = SKSpriteNode(color: fallback, size: size)
            plain.position = CGPoint(x: w / 2, y: h / 2)
            return plain
        }
        background.addChild(fill("map-gray", fallback: UIColor(hex: 0xA9ABB6)))
        let area = CGRect(x: 40, y: safeBottom + 140, width: w - 80, height: h - safeTop - 165 - (safeBottom + 140))
        let spots = mapSpots.map { CGPoint(x: area.minX + $0.x * area.width, y: area.minY + $0.y * area.height) }
        let reveal = SKCropNode()
        let mask = SKNode()
        for (i, spot) in spots.enumerated() where progress.stars(forStage: i) > 0 {
            let blob = SKShapeNode(circleOfRadius: w * 0.26)
            blob.fillColor = .white
            blob.strokeColor = .clear
            blob.position = spot
            mask.addChild(blob)
        }
        reveal.maskNode = mask
        reveal.addChild(fill("map-color", fallback: UIColor(hex: 0x7FCF84)))
        background.addChild(reveal)

        // The path, stitched in gold where you've been.
        for i in 0..<(spots.count - 1) {
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: spots[i])
            path.addLine(to: spots[i + 1])
            let done = progress.stars(forStage: i) > 0
            line.path = path.copy(dashingWithPhase: 0, lengths: done ? [14, 6] : [8, 10])
            line.strokeColor = done ? Palette.stitchGold : UIColor(white: 1, alpha: 0.75)
            line.lineWidth = done ? 6 : 4
            line.lineCap = .round
            line.zPosition = 1
            overlay.addChild(line)
        }

        // Stage spots.
        let current = progress.nextStageIndex
        for (i, spot) in spots.enumerated() {
            let isOpen = progress.isStageOpen(i)
            let node = SKNode()
            node.position = spot
            node.zPosition = 2
            overlay.addChild(node)
            let disc = SKShapeNode(circleOfRadius: 25)
            disc.fillColor = isOpen ? Palette.paper : UIColor(hex: 0x8A8C99)
            disc.strokeColor = isOpen ? Palette.stitchGold : .white
            disc.lineWidth = 4
            node.addChild(disc)
            let number = label("\(i + 1)", size: 22, color: isOpen ? Palette.stitchGold : .white)
            number.zPosition = 1
            node.addChild(number)
            let stars = progress.stars(forStage: i)
            for s in 0..<3 {
                let star = illustrated(s < stars ? "ui-star" : "ui-star-empty", width: 16) ?? art.star(filled: s < stars)
                let sprite = SKSpriteNode(texture: star.texture, size: CGSize(width: 17, height: 17))
                sprite.position = CGPoint(x: CGFloat(s - 1) * 17, y: -34)
                sprite.zPosition = 1
                node.addChild(sprite)
            }
            if i == current && isOpen {
                node.run(.repeatForever(.sequence([.scale(to: 1.1, duration: 0.5), .scale(to: 1, duration: 0.5)])))
                if let runner = monsterPortrait(monster, box: CGSize(width: 54, height: 54)) {
                    runner.position = CGPoint(x: 0, y: 58)
                    node.addChild(runner)
                }
            }
            onTap(node) { [unowned self] in
                if isOpen {
                    self.showStageCard(i)
                } else {
                    self.popText("Clear stage \(i) first", size: 20, color: .white, at: spot, rise: 30, life: 1, parent: self.overlay)
                }
            }
        }

        // Top bar.
        backButton { [unowned self] in self.showTitle() }
        let title = label("Notebook Meadow", size: 26)
        title.position = CGPoint(x: w / 2, y: h - safeTop - 30)
        title.zPosition = 5
        overlay.addChild(title)
        let starTotal = label("★ \(progress.totalStars)/\(Stage.meadow.count * 3)", size: 17, color: Palette.stitchGold)
        starTotal.anchorPoint = CGPoint(x: 1, y: 0.5)
        starTotal.position = CGPoint(x: w - 16, y: h - safeTop - 30)
        starTotal.zPosition = 5
        overlay.addChild(starTotal)
        if progress.stars(forStage: Stage.meadow.count - 1) > 0 {
            let next = label("Cardboard Canyon: coming soon!", size: 14, style: .body)
            next.position = CGPoint(x: w / 2, y: h - safeTop - 62)
            next.zPosition = 5
            overlay.addChild(next)
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
        let stage = Stage.meadow[index]
        let w = size.width
        let h = size.height
        _ = dimBackground { [unowned self] in self.showMap() }
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

        place(label("Stage \(stage.number)", size: 15, color: Palette.stormDark, style: .body), top - 36)
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
            let maxWidth = cardW / 2 - 52 - (-24)
            for sprite in [gadgetBlurb, passive] where sprite.size.width > maxWidth {
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

    /// Left and right arrows on a row; the closure gets -1 or +1.
    func addArrows(to row: SKNode, width: CGFloat, action: @escaping (Int) -> Void) {
        for side in [-1, 1] {
            let path = CGMutablePath()
            let s = CGFloat(side)
            path.move(to: CGPoint(x: s * 9, y: 0))
            path.addLine(to: CGPoint(x: -s * 6, y: 11))
            path.addLine(to: CGPoint(x: -s * 6, y: -11))
            path.closeSubpath()
            let arrow = SKShapeNode(path: path)
            arrow.fillColor = Palette.ink
            arrow.strokeColor = .clear
            arrow.position = CGPoint(x: s * (width / 2 - 14), y: 0)
            // A bigger invisible tap area around the arrow.
            let hit = SKSpriteNode(color: .clear, size: CGSize(width: 44, height: 50))
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
        if let shelf = imageSprite("trophy-case") {
            let k = max(w / shelf.size.width, h / shelf.size.height)
            shelf.size = CGSize(width: shelf.size.width * k, height: shelf.size.height * k)
            shelf.position = CGPoint(x: w / 2, y: h / 2)
            overlay.addChild(shelf)
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

        let gridTop = h - safeTop - 80
        let gridBottom = safeBottom + 16
        let progress = Progress.shared
        if tab == 0 {
            let columns = 3
            let rows = Int(ceil(Double(Monster.roster.count) / Double(columns)))
            let cellW = min(w - 24, 390) / CGFloat(columns)
            let cellH = min(170, (gridTop - gridBottom) / CGFloat(rows))
            for (i, monster) in Monster.roster.enumerated() {
                let unlocked = progress.isUnlocked(monster)
                let cell = SKNode()
                let column = CGFloat(i % columns)
                let row = CGFloat(i / columns)
                cell.position = CGPoint(x: w / 2 + (column - CGFloat(columns - 1) / 2) * cellW,
                                        y: gridTop - cellH * (row + 0.5))
                cell.zPosition = 2
                overlay.addChild(cell)
                let selected = unlocked && monster.id == self.monster.id
                let back = SKShapeNode(rect: CGRect(x: -cellW / 2 + 4, y: -cellH / 2 + 4, width: cellW - 8, height: cellH - 8), cornerRadius: 16)
                back.fillColor = Palette.paper.withAlphaComponent(unlocked ? 0.94 : 0.6)
                back.strokeColor = selected ? Palette.stitchGold : .white
                back.lineWidth = selected ? 5 : 3
                cell.addChild(back)
                if let portrait = monsterPortrait(monster, box: CGSize(width: cellW * 0.7, height: cellH * 0.5), locked: !unlocked) {
                    portrait.position = CGPoint(x: 0, y: cellH * 0.14)
                    portrait.zPosition = 1
                    cell.addChild(portrait)
                } else if !unlocked, let badge = imageSprite("badge-locked") {
                    badge.size = CGSize(width: cellH * 0.45, height: cellH * 0.45)
                    badge.position = CGPoint(x: 0, y: cellH * 0.14)
                    cell.addChild(badge)
                }
                let name = label(unlocked ? monster.name : "???", size: 15, color: unlocked ? Palette.ink : Palette.stormDark)
                name.position = CGPoint(x: 0, y: -cellH * 0.15)
                name.zPosition = 1
                cell.addChild(name)
                let line = unlocked ? monster.passive : monster.unlock.text
                let detail = paragraph(line, size: 10, width: cellW - 18, color: Palette.stormDark)
                detail.position = CGPoint(x: 0, y: -cellH * 0.3)
                detail.zPosition = 1
                cell.addChild(detail)
                if !unlocked {
                    let fraction = CGFloat(progress.progress(toward: monster))
                    let barW = cellW - 30
                    let bar = SKShapeNode(rect: CGRect(x: -barW / 2, y: 0, width: barW, height: 5), cornerRadius: 2.5)
                    bar.fillColor = UIColor(white: 0, alpha: 0.15)
                    bar.strokeColor = .clear
                    bar.position = CGPoint(x: 0, y: -cellH / 2 + 7)
                    cell.addChild(bar)
                    if fraction > 0.01 {
                        let fill = SKShapeNode(rect: CGRect(x: -barW / 2, y: 0, width: barW * fraction, height: 5), cornerRadius: 2.5)
                        fill.fillColor = Palette.stitchGold
                        fill.strokeColor = .clear
                        fill.position = bar.position
                        cell.addChild(fill)
                    }
                }
                onTap(cell) { [unowned self] in
                    if unlocked {
                        Monster.selectedIndex = i
                        self.monster = monster
                        self.currentPose = ""
                        self.audio.chime(step: i % 8)
                        self.showTrophyCase(tab: 0)
                    } else {
                        // Keep the hint on screen; it can be wider than its cell.
                        let x = min(max(cell.position.x, 158), self.size.width - 158)
                        let spot = CGPoint(x: x, y: cell.position.y)
                        self.popText(monster.unlock.text, size: 16, color: .white, at: spot, rise: 30, life: 1.4,
                                     parent: self.overlay)
                    }
                }
            }
        } else {
            let columns = 2
            let rows = Int(ceil(Double(Trophy.allCases.count) / Double(columns)))
            let cellW = min(w - 24, 400) / CGFloat(columns)
            let cellH = min(110, (gridTop - gridBottom) / CGFloat(rows))
            for (i, trophy) in Trophy.allCases.enumerated() {
                let earned = progress.hasTrophy(trophy)
                let cell = SKNode()
                cell.position = CGPoint(x: w / 2 + (CGFloat(i % columns) - 0.5) * cellW,
                                        y: gridTop - cellH * (CGFloat(i / columns) + 0.5))
                cell.zPosition = 2
                overlay.addChild(cell)
                let back = SKShapeNode(rect: CGRect(x: -cellW / 2 + 4, y: -cellH / 2 + 4, width: cellW - 8, height: cellH - 8), cornerRadius: 14)
                back.fillColor = Palette.paper.withAlphaComponent(earned ? 0.95 : 0.6)
                back.strokeColor = earned ? Palette.stitchGold : .white
                back.lineWidth = 3
                cell.addChild(back)
                let iconSize = min(cellH * 0.5, 48)
                let cup: SKSpriteNode
                if let image = imageSprite("menu-trophy") {
                    cup = image
                    let k = iconSize / max(image.size.width, image.size.height)
                    cup.size = CGSize(width: image.size.width * k, height: image.size.height * k)
                } else {
                    let star = art.star(filled: earned)
                    cup = SKSpriteNode(texture: star.texture, size: CGSize(width: iconSize, height: iconSize))
                }
                if !earned {
                    cup.color = Palette.stormDark
                    cup.colorBlendFactor = 0.9
                    cup.alpha = 0.6
                }
                cup.position = CGPoint(x: -cellW / 2 + 12 + iconSize / 2, y: 0)
                cup.zPosition = 1
                cell.addChild(cup)
                let textX = -cellW / 2 + 22 + iconSize
                let name = label(trophy.name, size: 14, color: earned ? Palette.ink : Palette.stormDark, anchorX: 0)
                name.position = CGPoint(x: textX, y: 10)
                name.zPosition = 1
                cell.addChild(name)
                let detail = label(trophy.detail, size: 10, color: Palette.stormDark, style: .body, anchorX: 0)
                detail.position = CGPoint(x: textX, y: -10)
                detail.zPosition = 1
                cell.addChild(detail)
                let room = cellW / 2 - 10 - textX
                for sprite in [name, detail] where sprite.size.width > room {
                    sprite.setScale(room / sprite.size.width)
                }
            }
        }
    }

    // MARK: Settings

    func showSettings() {
        let w = size.width
        _ = dimBackground { [unowned self] in self.showTitle() }
        let cardW = min(w - 32, 340)
        let rows: [(String, () -> Void)] = settingsRows()
        let cardH = CGFloat(110 + rows.count * 62)
        let card = paperPanel(width: cardW, height: cardH)
        card.position = CGPoint(x: w / 2, y: size.height * 0.52)
        card.zPosition = 11
        overlay.addChild(card)
        onTap(card) {}  // Taps on the card itself don't close it.
        let top = cardH / 2
        let title = label("Settings", size: 26, color: Palette.stitchGold)
        title.position = CGPoint(x: 0, y: top - 42)
        card.addChild(title)
        for (i, row) in rows.enumerated() {
            let button = paperButton(row.0, width: min(250, cardW - 60), pulse: false)
            button.setScale(0.55)
            button.position = CGPoint(x: 0, y: top - 96 - CGFloat(i) * 62)
            button.zPosition = 1
            card.addChild(button)
            onTap(button, row.1)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let footer = label("Storm Stitch \(version)", size: 11, color: Palette.stormDark, style: .body)
        footer.position = CGPoint(x: 0, y: -top + 24)
        card.addChild(footer)
        closeButton(at: CGPoint(x: w / 2 + cardW / 2 - 18, y: card.position.y + top - 18)) { [unowned self] in self.showTitle() }
    }

    func settingsRows() -> [(String, () -> Void)] {
        let data = Progress.shared.data
        var rows: [(String, () -> Void)] = [
            ("Music: \(data.music ? "On" : "Off")", { [unowned self] in
                Progress.shared.update { $0.music.toggle() }
                self.syncSettings()
                self.showTitle()
                self.showSettings()
            }),
            ("Sound: \(data.sound ? "On" : "Off")", { [unowned self] in
                Progress.shared.update { $0.sound.toggle() }
                self.syncSettings()
                self.showTitle()
                self.showSettings()
            }),
            ("Haptics: \(data.haptics ? "On" : "Off")", { [unowned self] in
                Progress.shared.update { $0.haptics.toggle() }
                self.syncSettings()
                self.showTitle()
                self.showSettings()
            }),
            ("Watch the story", { [unowned self] in self.playStory() }),
            ("Game Center", { GameCenter.showLeaderboards() }),
            ("Privacy and support", {
                if let url = URL(string: "\(Share.site)/privacy/") { UIApplication.shared.open(url) }
            })
        ]
        #if DEBUG
        rows.append(("Dev: unlock everything", { [unowned self] in
            Progress.shared.unlockEverything()
            self.showTitle()
        }))
        rows.append(("Dev: reset progress", { [unowned self] in
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
        let cardH = cardW * 855.0 / 1140.0
        let k = cardW / 380
        let card = paperPanel(width: cardW, height: cardH)
        card.position = CGPoint(x: w / 2, y: size.height - safeTop - 12 - cardH / 2)
        overlay.addChild(card)

        // Title and subtitle.
        var title = caught ? "Caught by the storm!" : "Out of hearts!"
        var subtitle = ""
        var starLabels = ["Finish", "No hits", "Stitched"]
        switch mode {
        case .stage(let index):
            let stage = Stage.meadow[index]
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
        let titleSprite = label(title, size: 23 * k, color: finished ? Palette.stitchGold : .white)
        if titleSprite.size.width > cardW - 60 { titleSprite.setScale((cardW - 60) / titleSprite.size.width) }
        titleSprite.position = CGPoint(x: 0, y: cardH * 0.29)
        titleSprite.zPosition = 1
        card.addChild(titleSprite)
        if !subtitle.isEmpty {
            let sub = paragraph(subtitle, size: 12.5 * k, width: cardW - 80, color: Palette.ink)
            sub.position = CGPoint(x: 0, y: cardH * 0.17)
            sub.zPosition = 1
            card.addChild(sub)
        }

        // Stars.
        for i in 0..<3 {
            let has = i < stars
            let starArt = illustrated(has ? "ui-star" : "ui-star-empty", width: 44 * k) ?? art.star(filled: has)
            let star = SKSpriteNode(texture: starArt.texture, size: CGSize(width: 44 * k, height: 44 * k))
            star.position = CGPoint(x: CGFloat(i - 1) * 84 * k, y: cardH * 0.0)
            star.zPosition = 1
            star.setScale(0)
            star.run(.sequence([
                .wait(forDuration: 0.25 + Double(i) * 0.18),
                .scale(to: 1.25, duration: 0.12),
                .scale(to: 1, duration: 0.1),
                .run { [weak self] in
                    if has {
                        self?.audio.chime(step: 2 + i * 2)
                        self?.haptics.spool()
                    }
                }
            ]))
            card.addChild(star)
            let caption = label(starLabels[i], size: 10 * k, color: Palette.stormDark, style: .body)
            if caption.size.width > 82 * k { caption.setScale(82 * k / caption.size.width) }
            caption.position = CGPoint(x: star.position.x, y: -cardH * 0.1)
            caption.zPosition = 1
            card.addChild(caption)
        }

        // Stats.
        let seconds = Int(stats.elapsed)
        var cells: [(String, String)] = [
            ("Spools", "\(stats.spools)"),
            ("Distance", "\(Int(stats.distance)) m"),
            ("Time", "\(seconds / 60):\(String(format: "%02d", seconds % 60))")
        ]
        if mode.isDailyLike || mode == .endless {
            cells.append(("Score", stats.score.formatted()))
        } else {
            cells.append(("Stitched", "\(stats.meterPercent)%"))
        }
        cells.append(("Streak", "\(stats.bestStreak)"))
        cells.append(("Close calls", "\(stats.closeCalls)"))
        for (index, cell) in cells.enumerated() {
            let column = CGFloat(index % 3 - 1)
            let rowY = index < 3 ? -cardH * 0.2 : -cardH * 0.32
            let value = SKLabelNode(fontNamed: "Fredoka-SemiBold")
            value.text = cell.1
            value.fontSize = 18 * k
            value.fontColor = Palette.ink
            value.verticalAlignmentMode = .center
            value.position = CGPoint(x: column * cardW * 0.27, y: rowY)
            value.zPosition = 1
            card.addChild(value)
            let name = SKLabelNode(fontNamed: "NunitoSans-Bold")
            name.text = cell.0
            name.fontSize = 10 * k
            name.fontColor = Palette.stormDark
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: value.position.x, y: rowY - 15 * k)
            name.zPosition = 1
            card.addChild(name)
        }

        card.setScale(0.7)
        card.alpha = 0
        card.run(.group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.25)]))

        // Unlocks, one after another.
        var y = card.position.y - cardH / 2 - 34
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
            banner.alpha = 0
            banner.setScale(0.6)
            banner.run(.sequence([
                .wait(forDuration: 0.9 + Double(i) * 0.5),
                .group([.fadeIn(withDuration: 0.15), .scale(to: 1, duration: 0.2)]),
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
            if finished && index + 1 < Stage.meadow.count {
                buttons.append(("Next", { [unowned self] in self.showMap(); self.showStageCard(index + 1) }))
            } else {
                buttons.append(("Retry", { [unowned self] in self.startRun(.stage(index)) }))
            }
            buttons.append(("Map", { [unowned self] in self.showMap() }))
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
            self.story?.removeFromParent()
            self.story = nil
            self.showTitle()
        }
        player.zPosition = 1200
        addChild(player)
        story = player
        audio.setMusic(playing: true)
        audio.setIntensity(0.3)
        player.start()
    }
}
