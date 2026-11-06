import SpriteKit
import UIKit

// MARK: Tuning knobs

/// Every number that shapes the pick-3 power gates, in one place.
/// The gate times also show in the live tuning panel (Tuning.powerGate1...3).
enum PowerTuning {
    /// Seconds into a run when each gate's doors reach you.
    static let gateTimes: [Double] = [25, 50, 75]
    /// A timed run skips any gate later than this many seconds before the finish.
    static let finishMargin = 6.0
    /// Stages before this global index have no gates (index 2 is Notebook Meadow stage 3).
    static let firstStageIndex = 2
    static let maxLevel = 3
    /// At most this many defensive powers among a gate's three doors.
    static let defensivePerGate = 1
    /// Mixed into the Daily Storm seed so the gates are shared but separate from the course.
    static let dailySalt: UInt64 = 0x9A7E_5EED_D00B_0003

    // Effects by level (index 0 is level 1).
    static let doubleSpoolsDuration: [Double] = [10, 14, 18]
    static let magnetDuration: [Double] = [6, 9, 12]
    static let stormBrakeRate: [Double] = [1.6, 2.1, 2.6]
    static let springStepBoost: [Double] = [1.1, 1.17, 1.24]
    static let colorBurstAmount: [Double] = [0.15, 0.2, 0.25]
    /// Close calls pay 3 spools times this.
    static let closeCallMultiplier: [Int] = [2, 3, 4]
    /// Every Nth spool is lucky and pays a bonus.
    static let luckyEvery: [Int] = [5, 4, 3]
    static let luckyBonus = 2
    /// Extra spools per box cut, on top of the usual Snip! +2.
    static let scissorBonus: [Int] = [0, 2, 4]
    /// Each pick adds this many slow-mo moments / streak saves.
    static let slowMoChargesPerPick = 3
    static let streakSavesPerPick = 1
    /// A streak shorter than this isn't worth spending a Streak Keeper save on.
    static let streakKeeperMin = 3
    static let slowMoDodgeScale = 0.3

    // Gate feel.
    /// The slow-mo beat as the doors close in.
    static let approachScale = 0.45
    /// The pick happens when the doors are this close (world units).
    static let resolveZ = 0.6
    /// Hazards this far in front of the doors are cleared when they appear.
    static let clearAhead = 7.0
    /// No new hazard rows until the doors are this far down the road.
    static let rowGap = 8.0

    /// Per-world weight tweaks (1 when missing). Keys: world ids, "endless", "daily".
    static let worldWeights: [String: [PowerKind: Double]] = [
        "meadow": [.colorBurst: 1.4, .doubleSpools: 1.2],
        "canyon": [.scissorSlide: 1.8, .springStep: 1.3],
        "lagoon": [.threadMagnet: 1.5, .slowMoDodge: 1.2],
        "peaks": [.stormBrake: 1.3, .springStep: 1.3, .closeCallX2: 1.2],
        "endless": [.stormBrake: 1.2, .patchArmor: 1.2],
        "daily": [:]
    ]

    static func value<T>(_ table: [T], _ level: Int) -> T {
        table[max(0, min(table.count - 1, level - 1))]
    }
}

// MARK: Powers

enum PowerKind: String, CaseIterable {
    case doubleSpools, threadMagnet, patchArmor, stormBrake, scissorSlide, springStep
    case streakKeeper, colorBurst, closeCallX2, gadgetCharge, luckySpools, slowMoDodge

    var name: String {
        switch self {
        case .doubleSpools: return "Double Spools"
        case .threadMagnet: return "Thread Magnet"
        case .patchArmor: return "Patch Armor"
        case .stormBrake: return "Storm Brake"
        case .scissorSlide: return "Scissor Slide"
        case .springStep: return "Spring Step"
        case .streakKeeper: return "Streak Keeper"
        case .colorBurst: return "Color Burst"
        case .closeCallX2: return "Close Call x2"
        case .gadgetCharge: return "Gadget Charge"
        case .luckySpools: return "Lucky Spools"
        case .slowMoDodge: return "Slow Mo Dodge"
        }
    }

    /// The name split over two short lines for a door.
    var doorLines: [String] {
        switch self {
        case .closeCallX2: return ["Close", "Call x2"]
        case .slowMoDodge: return ["Slow Mo", "Dodge"]
        default: return name.components(separatedBy: " ")
        }
    }

    /// A tiny tag for the HUD icon.
    var tag: String {
        switch self {
        case .doubleSpools: return "x2"
        case .threadMagnet: return "Mag"
        case .patchArmor: return "Arm"
        case .stormBrake: return "Brk"
        case .scissorSlide: return "Cut"
        case .springStep: return "Hop"
        case .streakKeeper: return "Stk"
        case .colorBurst: return "Clr"
        case .closeCallX2: return "CC"
        case .gadgetCharge: return "Gad"
        case .luckySpools: return "Lck"
        case .slowMoDodge: return "Slo"
        }
    }

    /// The felt color of its door and icon.
    var color: UIColor {
        switch self {
        case .doubleSpools: return UIColor(hex: 0xF2A93B)
        case .threadMagnet: return UIColor(hex: 0xE05A5A)
        case .patchArmor: return UIColor(hex: 0x5DBB63)
        case .stormBrake: return UIColor(hex: 0x6C7BD9)
        case .scissorSlide: return UIColor(hex: 0xFF8FA3)
        case .springStep: return UIColor(hex: 0x4FC3C9)
        case .streakKeeper: return UIColor(hex: 0xF08A3C)
        case .colorBurst: return UIColor(hex: 0xB46CE0)
        case .closeCallX2: return UIColor(hex: 0x3E9BE8)
        case .gadgetCharge: return UIColor(hex: 0x8A5A2B)
        case .luckySpools: return UIColor(hex: 0x7DBE3A)
        case .slowMoDodge: return UIColor(hex: 0xA792FF)
        }
    }

    /// Defensive powers are capped per gate so a gate can't be all safety nets.
    var isDefensive: Bool {
        switch self {
        case .patchArmor, .stormBrake, .streakKeeper, .slowMoDodge: return true
        case .doubleSpools, .threadMagnet, .scissorSlide, .springStep, .colorBurst,
             .closeCallX2, .gadgetCharge, .luckySpools: return false
        }
    }
}

/// Everything about the power gates in one run. A value type so the Time Machine can snapshot it.
struct PowerState {
    var levels: [PowerKind: Int] = [:]
    /// Powers in the order they were first taken, for the HUD row.
    var taken: [PowerKind] = []
    /// Gate times for this run, and each gate's three powers in lane order (left, middle, right).
    var schedule: [Double] = []
    var offers: [[PowerKind]] = []
    var nextGate = 0
    /// The gate whose doors are on the road.
    var openGate: Int? = nil
    var slowBeatDone = false
    var doubleSpoolsTimer = 0.0
    /// Spare Patch Armor patches beyond the one currently worn.
    var armorCharges = 0
    var streakSaves = 0
    var slowMoCharges = 0
    var luckyCount = 0
    var slowMoTarget: ObjectIdentifier? = nil
    var rowSignature = ""
}

extension RunScene.Thing {
    var isPowerDoor: Bool {
        if case .powerDoor = kind { return true }
        return false
    }
}

extension RunScene {

    // MARK: Hooks used by the core systems

    func powerLevel(_ kind: PowerKind) -> Int { powers.levels[kind] ?? 0 }

    /// Double Spools: every spool counts twice while it lasts.
    var powerSpoolMultiplier: Int { powers.doubleSpoolsTimer > 0 ? 2 : 1 }

    var stormBrakeMultiplier: Double {
        let level = powerLevel(.stormBrake)
        return level > 0 ? PowerTuning.value(PowerTuning.stormBrakeRate, level) : 1
    }

    var springStepMultiplier: Double {
        let level = powerLevel(.springStep)
        return level > 0 ? PowerTuning.value(PowerTuning.springStepBoost, level) : 1
    }

    var closeCallMultiplier: Int {
        let level = powerLevel(.closeCallX2)
        return level > 0 ? PowerTuning.value(PowerTuning.closeCallMultiplier, level) : 1
    }

    /// Lucky Spools: every Nth spool pays a bonus. Counted, not rolled, so the Daily Storm stays fair.
    func luckySpoolBonus() -> Int {
        let level = powerLevel(.luckySpools)
        guard level > 0 else { return 0 }
        powers.luckyCount += 1
        guard powers.luckyCount % PowerTuning.value(PowerTuning.luckyEvery, level) == 0 else { return 0 }
        sparkleBurst(at: playerScreenPoint(offsetY: 60), count: 8, spread: .pi * 2, speed: 140)
        return PowerTuning.luckyBonus
    }

    /// Scissor Slide level 2 and up: cut boxes pay extra.
    func scissorSlideBonus() {
        let level = powerLevel(.scissorSlide)
        guard level > 1 else { return }
        spools += PowerTuning.value(PowerTuning.scissorBonus, level)
    }

    /// Patch Armor: when the worn patch tears, sew on a spare.
    func refillPatchArmor() {
        guard powers.armorCharges > 0 else { return }
        powers.armorCharges -= 1
        shieldActive = true
    }

    /// Streak Keeper: a gap between spools doesn't break the streak. Returns true when it saved one.
    func savePowerStreak() -> Bool {
        guard powers.streakSaves > 0, streak >= PowerTuning.streakKeeperMin else { return false }
        powers.streakSaves -= 1
        streakTimer = 1.4
        popText("Streak kept!", size: 20, color: PowerKind.streakKeeper.color, at: playerScreenPoint(offsetY: 150), rise: 30, life: 0.8)
        return true
    }

    /// Holds back new hazard rows while a gate's doors are still near the horizon, so the pick stays free.
    var rowsHeldForPowerGate: Bool {
        guard powers.openGate != nil else { return false }
        return things.contains { $0.isPowerDoor && !$0.retired && $0.z > spawnZ - PowerTuning.rowGap }
    }

    // MARK: Run setup

    func resetPowers() {
        powers = PowerState()
        powers.schedule = powerGateSchedule()
        powers.offers = makePowerOffers(count: powers.schedule.count)
        refreshPowerRow()
    }

    func powerGateSchedule() -> [Double] {
        switch mode {
        case .stage(let index):
            guard index >= PowerTuning.firstStageIndex else { return [] }
        case .endless, .daily, .challenge:
            break
        case .race:
            // Holiday races are a straight spool count against the rival: no powers.
            return []
        }
        let times = [tuning.powerGate1, tuning.powerGate2, tuning.powerGate3].sorted()
        guard config.length.isFinite else { return times }
        return times.filter { $0 <= config.length - PowerTuning.finishMargin }
    }

    var powerWorldKey: String {
        switch mode {
        case .stage(let index): return World.all[World.index(ofStage: index)].id
        case .daily, .challenge: return "daily"
        case .endless: return "endless"
        case .race: return "race"
        }
    }

    /// Every gate's doors are rolled at the start of the run. The Daily Storm rolls from the day's seed,
    /// so everyone sees the same three gates whatever they picked before.
    func makePowerOffers(count: Int) -> [[PowerKind]] {
        var gateRNG = mode.isDailyLike ? GameRNG(seed: config.seed ^ PowerTuning.dailySalt)
                                       : GameRNG(seed: GameRNG.freshSeed())
        let pool = PowerKind.allCases.filter { $0 != .gadgetCharge || gadget != nil }
        let tweaks = PowerTuning.worldWeights[powerWorldKey] ?? [:]
        var result: [[PowerKind]] = []
        for _ in 0..<count {
            var picks: [PowerKind] = []
            var defensive = 0
            while picks.count < 3 {
                let options = pool.filter { kind in
                    !picks.contains(kind) && (!kind.isDefensive || defensive < PowerTuning.defensivePerGate)
                }
                guard let last = options.last else { break }
                let weights = options.map { max(0, tweaks[$0] ?? 1) }
                let total = weights.reduce(0, +)
                var roll = Double.random(in: 0..<max(total, 0.0001), using: &gateRNG)
                var choice = last
                for (i, weight) in weights.enumerated() {
                    if roll < weight {
                        choice = options[i]
                        break
                    }
                    roll -= weight
                }
                picks.append(choice)
                if choice.isDefensive { defensive += 1 }
            }
            result.append(picks.shuffled(using: &gateRNG))
        }
        return result
    }

    // MARK: Per frame

    func stepPowerGates(_ dt: Double) {
        if powers.doubleSpoolsTimer > 0 { powers.doubleSpoolsTimer -= dt }
        stepSlowMoDodge()

        if powers.openGate == nil, !gateSpawned, powers.nextGate < powers.schedule.count {
            // Spawn on the horizon so the doors reach you right at the gate time.
            let lead = (spawnZ - 1) / max(runSpeed, 1)
            if elapsed >= powers.schedule[powers.nextGate] - lead {
                spawnPowerGate(powers.nextGate)
            }
        }

        if let gateIndex = powers.openGate {
            let doors = things.filter { $0.isPowerDoor && !$0.retired }
            if let front = doors.first {
                if !powers.slowBeatDone && front.z < max(4, runSpeed * 0.9) {
                    // A slow-mo beat as the doors close in: time to pick a lane.
                    powers.slowBeatDone = true
                    timeScale = min(timeScale, PowerTuning.approachScale)
                    haptics.lane()
                }
                if front.z <= PowerTuning.resolveZ {
                    resolvePowerGate(gateIndex, doors: doors)
                }
            } else {
                powers.openGate = nil
            }
        }

        let signature = powers.taken.map { "\($0.rawValue)\(powerLevel($0))\(powerIsSpent($0) ? 0 : 1)" }.joined()
        if signature != powers.rowSignature { refreshPowerRow() }
    }

    /// Slow Mo Dodge: time slows for a moment when a hazard is about to hit you.
    func stepSlowMoDodge() {
        guard powers.slowMoCharges > 0, invulnerable <= 0, planeTimer <= 0, foldTimer <= 0 else { return }
        let window = max(1.2, runSpeed * 0.25)
        let cuts = (monster.ability == .snip || powerLevel(.scissorSlide) > 0) && slideTimer > 0
        for thing in things where thing.isHazard && !thing.retired && !thing.resolved && thing.z > 0.35 && thing.z < window {
            guard abs(thing.x - laneToX) < 0.55, ObjectIdentifier(thing) != powers.slowMoTarget,
                  case .hazard(let hazard) = thing.kind else { continue }
            let threat: Bool
            switch hazard {
            case .low: threat = playerY < 0.5
            case .overhead: threat = slideTimer <= 0
            case .crate: threat = playerY < 1.4 && monster.ability != .barge && !cuts
            }
            guard threat else { continue }
            powers.slowMoTarget = ObjectIdentifier(thing)
            powers.slowMoCharges -= 1
            timeScale = min(timeScale, PowerTuning.slowMoDodgeScale)
            popText("Slow mo!", size: 20, color: PowerKind.slowMoDodge.color, at: playerScreenPoint(offsetY: 120), rise: 20, life: 0.7)
            return
        }
    }

    // MARK: Gates

    func spawnPowerGate(_ index: Int) {
        powers.nextGate = index + 1
        guard index < powers.offers.count else { return }
        let z = spawnZ - 1
        // Clear the road around the doors so the pick is a free choice.
        for thing in things where thing.isHazard && !thing.retired && thing.z > z - PowerTuning.clearAhead {
            retire(thing)
        }
        for (slot, kind) in powers.offers[index].enumerated() {
            let level = min(PowerTuning.maxLevel, powerLevel(kind) + 1)
            let sprite = makePowerDoorSprite(kind, level: level, withSeam: slot == 1)
            sprite.alpha = 0
            objectLayer.addChild(sprite)
            let door = Thing(kind: .powerDoor(slot), sprite: sprite, worldScale: 1,
                             x: Double(slot - 1) * laneWidth, z: z, y: 0)
            door.spawnedAt = distance
            things.append(door)
        }
        powers.openGate = index
        powers.slowBeatDone = false
        audio.play(.whoosh, volume: 0.5)

        // The very first gate a player ever sees teaches itself in three words.
        if Progress.shared.data.powerGateSeen != true {
            Progress.shared.update { $0.powerGateSeen = true }
            popText("Pick a power", size: 28, color: .white, at: CGPoint(x: size.width / 2, y: size.height * 0.6), rise: 10, life: 3)
        }
    }

    /// The doors reach you: the one in your lane is yours, the others tear away.
    func resolvePowerGate(_ gateIndex: Int, doors: [Thing]) {
        powers.openGate = nil
        let slot = max(0, min(2, laneIndex + 1))
        let offer = gateIndex < powers.offers.count ? powers.offers[gateIndex] : []
        for door in doors {
            let point = screenPoint(ofWorld: door.sprite.position)
            if case .powerDoor(let doorSlot) = door.kind, doorSlot == slot {
                sparkleBurst(at: point, count: 24, spread: .pi * 2, speed: 260)
            } else {
                confettiBurst(at: point)
            }
            retire(door)
        }
        guard slot < offer.count else { return }
        takePower(offer[slot])
    }

    func takePower(_ kind: PowerKind) {
        let level = min(PowerTuning.maxLevel, powerLevel(kind) + 1)
        powers.levels[kind] = level
        if !powers.taken.contains(kind) { powers.taken.append(kind) }

        switch kind {
        case .doubleSpools:
            powers.doubleSpoolsTimer = max(powers.doubleSpoolsTimer, PowerTuning.value(PowerTuning.doubleSpoolsDuration, level))
        case .threadMagnet:
            // The same pull as the Thread Magnet gadget.
            magnetTimer = max(magnetTimer, PowerTuning.value(PowerTuning.magnetDuration, level))
        case .patchArmor:
            // The same patch as the Stitch Shield; a second pick sews on a spare.
            if shieldActive {
                powers.armorCharges += 1
            } else {
                shieldActive = true
            }
            shieldRing.isHidden = false
        case .stormBrake, .scissorSlide, .springStep, .closeCallX2, .luckySpools:
            // Read live by the run's systems through powerLevel.
            break
        case .streakKeeper:
            powers.streakSaves += PowerTuning.streakSavesPerPick
        case .colorBurst:
            let before = meter
            meter = min(1, meter + PowerTuning.value(PowerTuning.colorBurstAmount, level))
            stitchBurst(atX: playerX, z: 2)
            if before < 1 && meter >= 1 && !fullyStitched { worldFullyStitched() }
        case .gadgetCharge:
            if let gadget {
                gadgetCharge = max(gadgetCharge, gadget.cost)
                updateGadgetRing()
            }
        case .slowMoDodge:
            powers.slowMoCharges += PowerTuning.slowMoChargesPerPick
        }

        // Rip, then stitch.
        audio.play(.whoosh)
        run(.sequence([
            .wait(forDuration: 0.12),
            .run { [weak self] in self?.audio.play(.stitch, volume: 0.9) }
        ]))
        haptics.success()
        let title = level > 1 ? "\(kind.name) Lv \(level)!" : "\(kind.name)!"
        popText(title, size: 26, color: Palette.stitchGold, at: playerScreenPoint(offsetY: 170), rise: 40, life: 1.3)
        updateHUD()
        refreshPowerRow()
    }

    /// A timed or charged power that has run out shows faded on the HUD.
    func powerIsSpent(_ kind: PowerKind) -> Bool {
        switch kind {
        case .doubleSpools: return powers.doubleSpoolsTimer <= 0
        case .threadMagnet: return magnetTimer <= 0
        case .patchArmor: return !shieldActive && powers.armorCharges == 0
        case .streakKeeper: return powers.streakSaves == 0
        case .slowMoDodge: return powers.slowMoCharges == 0
        case .stormBrake, .scissorSlide, .springStep, .colorBurst, .closeCallX2, .gadgetCharge, .luckySpools:
            return false
        }
    }

    // MARK: Drawing

    /// A paper door with a felt frame, a gold running stitch and the power's name.
    /// Drawn in art units (100 per lane), standing on its bottom edge.
    func makePowerDoorSprite(_ kind: PowerKind, level: Int, withSeam: Bool) -> SKSpriteNode {
        let w: CGFloat = 84
        let h: CGFloat = 138
        let sprite = SKSpriteNode(color: .clear, size: CGSize(width: w + 8, height: h + 8))
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.02)

        let door = CGMutablePath()
        door.move(to: CGPoint(x: -w / 2, y: 0))
        door.addLine(to: CGPoint(x: -w / 2, y: h - w / 2))
        door.addArc(center: CGPoint(x: 0, y: h - w / 2), radius: w / 2, startAngle: .pi, endAngle: 0, clockwise: true)
        door.addLine(to: CGPoint(x: w / 2, y: 0))
        door.closeSubpath()

        let shadow = SKShapeNode(path: door)
        shadow.fillColor = UIColor(hex: 0x1E1B2E, alpha: 0.3)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 5, y: -3)
        shadow.zPosition = 0
        sprite.addChild(shadow)

        let frame = SKShapeNode(path: door)
        frame.fillColor = kind.color
        frame.strokeColor = Palette.ink
        frame.lineWidth = 4
        frame.lineJoin = .round
        frame.zPosition = 1
        sprite.addChild(frame)

        var stitchTransform = CGAffineTransform(translationX: 0, y: 5).scaledBy(x: 0.88, y: 0.92)
        if let stitchPath = door.copy(using: &stitchTransform) {
            let stitches = SKShapeNode(path: stitchPath.copy(dashingWithPhase: 0, lengths: [7, 5]))
            stitches.strokeColor = Palette.stitchGold
            stitches.lineWidth = 2.5
            stitches.lineCap = .round
            stitches.zPosition = 2
            sprite.addChild(stitches)
        }

        var panelTransform = CGAffineTransform(translationX: 0, y: 11).scaledBy(x: 0.74, y: 0.8)
        if let panelPath = door.copy(using: &panelTransform) {
            let panel = SKShapeNode(path: panelPath)
            panel.fillColor = Palette.paper
            panel.strokeColor = UIColor(hex: 0x1E1B2E, alpha: 0.35)
            panel.lineWidth = 1.5
            panel.zPosition = 3
            sprite.addChild(panel)
        }

        // A felt badge with the HUD tag, so the door matches its icon.
        let badge = SKShapeNode(circleOfRadius: 13)
        badge.fillColor = kind.color
        badge.strokeColor = Palette.ink
        badge.lineWidth = 2
        badge.position = CGPoint(x: 0, y: h * 0.7)
        badge.zPosition = 4
        sprite.addChild(badge)
        addFittedText(kind.tag, size: 11, fill: .white, maxWidth: 22, at: CGPoint(x: 0, y: h * 0.7), z: 5, to: sprite)

        let lines = kind.doorLines
        for (i, line) in lines.enumerated() {
            let y = h * (lines.count == 1 ? 0.42 : 0.5 - 0.14 * CGFloat(i))
            addFittedText(line, size: 15, fill: kind.color, maxWidth: w * 0.68, at: CGPoint(x: 0, y: y), z: 5, to: sprite)
        }
        if level > 1 {
            addFittedText("Lv \(level)", size: 13, fill: Palette.stitchGold, maxWidth: w * 0.6, at: CGPoint(x: 0, y: h * 0.17), z: 5, to: sprite)
        }

        if withSeam { addSeam(to: sprite) }
        return sprite
    }

    /// The torn seam the doors stand in: a ragged paper strip across all three lanes, tacked with gold.
    func addSeam(to sprite: SKSpriteNode) {
        let half: CGFloat = 165
        let strip = CGMutablePath()
        var x = -half
        strip.move(to: CGPoint(x: x, y: 6))
        var step = 0
        while x < half {
            x = min(half, x + 15)
            strip.addLine(to: CGPoint(x: x, y: step % 2 == 0 ? 12 : 4))
            step += 1
        }
        while x > -half {
            x = max(-half, x - 15)
            strip.addLine(to: CGPoint(x: x, y: step % 2 == 0 ? -6 : 1))
            step += 1
        }
        strip.closeSubpath()
        let tear = SKShapeNode(path: strip)
        tear.fillColor = UIColor(hex: 0x2B2340)
        tear.strokeColor = Palette.paper
        tear.lineWidth = 2
        tear.zPosition = -1
        sprite.addChild(tear)

        let tacks = CGMutablePath()
        var tx = -half + 20
        while tx < half - 10 {
            tacks.move(to: CGPoint(x: tx - 5, y: 10))
            tacks.addLine(to: CGPoint(x: tx + 5, y: -4))
            tacks.move(to: CGPoint(x: tx + 5, y: 10))
            tacks.addLine(to: CGPoint(x: tx - 5, y: -4))
            tx += 30
        }
        let gold = SKShapeNode(path: tacks)
        gold.strokeColor = Palette.stitchGold
        gold.lineWidth = 2.5
        gold.lineCap = .round
        gold.zPosition = -0.5
        sprite.addChild(gold)
    }

    func addFittedText(_ string: String, size: CGFloat, fill: UIColor, maxWidth: CGFloat, at point: CGPoint, z: CGFloat, to parent: SKNode) {
        let textArt = art.text(string, size: size, fill: fill)
        let text = SKSpriteNode(texture: textArt.texture, size: textArt.size)
        if textArt.size.width > maxWidth { text.setScale(maxWidth / textArt.size.width) }
        text.position = point
        text.zPosition = z
        parent.addChild(text)
    }

    /// The HUD row of taken powers, top left under the pause button, each with its level.
    func refreshPowerRow() {
        if powerRow.parent == nil {
            powerRow.zPosition = 5
            hud.addChild(powerRow)
        }
        powerRow.removeAllChildren()
        let topInset = max(view?.safeAreaInsets.top ?? 0, 20)
        powerRow.position = CGPoint(x: 26, y: size.height - topInset - 28 - 84)
        for (i, kind) in powers.taken.enumerated() {
            let icon = SKNode()
            icon.position = CGPoint(x: CGFloat(i) * 36, y: 0)
            let disc = SKShapeNode(circleOfRadius: 15)
            disc.fillColor = kind.color
            disc.strokeColor = Palette.ink
            disc.lineWidth = 3
            icon.addChild(disc)
            let ring = SKShapeNode(path: CGPath(ellipseIn: CGRect(x: -11, y: -11, width: 22, height: 22), transform: nil)
                .copy(dashingWithPhase: 0, lengths: [4, 3]))
            ring.strokeColor = Palette.stitchGold
            ring.lineWidth = 1.5
            ring.zPosition = 1
            icon.addChild(ring)
            addFittedText(kind.tag, size: 11, fill: .white, maxWidth: 22, at: .zero, z: 2, to: icon)
            let level = powerLevel(kind)
            if level > 1 {
                let pip = SKShapeNode(circleOfRadius: 8)
                pip.fillColor = Palette.stitchGold
                pip.strokeColor = Palette.ink
                pip.lineWidth = 2
                pip.position = CGPoint(x: 12, y: 12)
                pip.zPosition = 3
                icon.addChild(pip)
                addFittedText("\(level)", size: 10, fill: .white, maxWidth: 12, at: CGPoint(x: 12, y: 12), z: 4, to: icon)
            }
            icon.alpha = powerIsSpent(kind) ? 0.4 : 1
            powerRow.addChild(icon)
        }
        powers.rowSignature = powers.taken.map { "\($0.rawValue)\(powerLevel($0))\(powerIsSpent($0) ? 0 : 1)" }.joined()
    }
}
