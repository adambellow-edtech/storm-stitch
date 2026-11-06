import CoreGraphics
import Foundation

/// The art a run is dressed in. Every name is optional and falls back to Notebook Meadow's
/// art when it's nil or the picture isn't in the app yet, so a world is playable before its art lands.
struct Theme: Equatable {
    let key: String
    var lowHazard: String? = nil
    var crateHazard: String? = nil
    var overheadHazard: String? = nil
    var treeColor: String? = nil
    var treeGray: String? = nil
    var bushColor: String? = nil
    var bushGray: String? = nil
    var groundColor: String? = nil
    var groundGray: String? = nil
    var roadColor: String? = nil
    var roadGray: String? = nil
    var backdropColor: String? = nil
    var backdropGray: String? = nil
    /// Pictures that drift down the screen (leaves, snowflakes) during a holiday.
    var particles: [String] = []
    var holiday: Holiday? = nil
}

extension Holiday {
    /// The holiday look: it reskins Notebook Meadow, and its falling leaves or snow drift over every world.
    var theme: Theme {
        Theme(key: rawValue, lowHazard: lowHazard, crateHazard: crateHazard, treeColor: treeColor, treeGray: treeGray,
              groundColor: groundColor, roadColor: roadColor, particles: particles, holiday: self)
    }
}

/// A world is a map of ten stages with its own look, rival monster and difficulty.
/// Clearing a world's last stage opens the next one.
struct World {
    let id: String
    let name: String
    /// One line for the map and the "new world" banner.
    let blurb: String
    let stages: [Stage]

    static let stagesPerWorld = 10

    static let all: [World] = [
        World(id: "meadow", name: "Notebook Meadow", blurb: "Where the storm first struck.", stages: Stage.meadow),
        World(id: "canyon", name: "Cardboard Canyon", blurb: "Boxes, tape and tumbling cartons.", stages: Stage.canyon),
        World(id: "lagoon", name: "Ink Lagoon", blurb: "Inkwells, quills and paper boats.", stages: Stage.lagoon),
        World(id: "peaks", name: "Origami Peaks", blurb: "Folded mountains and the Shredder's lair.", stages: Stage.peaks)
    ]

    /// Which world a global stage index belongs to.
    static func index(ofStage stage: Int) -> Int {
        min(all.count - 1, max(0, stage / stagesPerWorld))
    }

    /// True for a world's last stage: the Shredder chase finale.
    static func isShredderChase(stage index: Int) -> Bool {
        index >= 0 && index < Stage.all.count && Stage.all[index].number == stagesPerWorld
    }

    /// Global index of this world's first stage.
    var firstStage: Int { (World.all.firstIndex { $0.id == id } ?? 0) * World.stagesPerWorld }

    /// Art names, "<id>-<part>". Notebook Meadow keeps its original names.
    func artName(_ part: String) -> String { id == "meadow" ? part : "\(id)-\(part)" }
    var mapColor: String { artName("map-color") }
    var mapGray: String { artName("map-gray") }

    /// Where the ten stage markers sit on this world's painted map: fractions of the picture,
    /// x from the left and y from the top, traced along its path from the first stage to the last.
    var mapPath: [CGPoint] {
        let points: [(CGFloat, CGFloat)]
        switch id {
        case "canyon":
            points = [(0.33, 0.76), (0.44, 0.70), (0.60, 0.64), (0.53, 0.58), (0.40, 0.52),
                      (0.46, 0.46), (0.59, 0.40), (0.48, 0.34), (0.45, 0.28), (0.50, 0.22)]
        case "lagoon":
            points = [(0.57, 0.76), (0.46, 0.70), (0.38, 0.64), (0.62, 0.58), (0.45, 0.52),
                      (0.45, 0.46), (0.65, 0.40), (0.52, 0.34), (0.49, 0.28), (0.57, 0.22)]
        case "peaks":
            points = [(0.51, 0.76), (0.27, 0.70), (0.48, 0.64), (0.73, 0.58), (0.38, 0.52),
                      (0.48, 0.46), (0.57, 0.40), (0.45, 0.34), (0.52, 0.28), (0.58, 0.22)]
        default:
            points = [(0.38, 0.76), (0.46, 0.70), (0.44, 0.64), (0.37, 0.58), (0.28, 0.52),
                      (0.47, 0.46), (0.59, 0.40), (0.46, 0.34), (0.56, 0.28), (0.66, 0.22)]
        }
        return points.map { CGPoint(x: $0.0, y: $0.1) }
    }

    /// Nil for Notebook Meadow, which uses the default art (or the holiday look).
    var theme: Theme? {
        guard id != "meadow" else { return nil }
        return Theme(key: id,
                     lowHazard: artName("hazard-low"), crateHazard: artName("hazard-crate"),
                     overheadHazard: artName("hazard-overhead"),
                     treeColor: artName("tree-color"), treeGray: artName("tree-gray"),
                     bushColor: artName("bush-color"), bushGray: artName("bush-gray"),
                     groundColor: artName("ground-color"), groundGray: artName("ground-gray"),
                     roadColor: artName("road-color"), roadGray: artName("road-gray"),
                     backdropColor: artName("backdrop-color"), backdropGray: artName("backdrop-gray"))
    }

    /// The run settings for a global stage index: each world starts faster and busier than the last.
    static func config(forStage index: Int) -> RunConfig {
        let clamped = max(0, min(index, Stage.all.count - 1))
        var config = Stage.all[clamped].config
        let w = Double(World.index(ofStage: clamped))
        guard w > 0 else { return config }
        config.startSpeed += w * 1.1
        config.endSpeed += w * 1.4
        config.intervalStart = max(0.62, config.intervalStart - w * 0.06)
        config.intervalEnd = max(0.5, config.intervalEnd - w * 0.06)
        config.overheadFrom = 0
        config.doubleChance = min(0.75, config.doubleChance + w * 0.1)
        config.hints = false
        return config
    }
}

extension Stage {
    /// Every stage in every world, in play order. Saves and stage indexes use this order.
    static let all: [Stage] = World.all.flatMap(\.stages)

    static let canyon: [Stage] = [
        Stage(number: 1, name: "Box Canyon Gate", beat: "The canyon gate swings open. Somewhere, packing tape squeaks.",
              length: 50, challenge: .spools(45), stitchTarget: 55, gadget: nil, monster: nil),
        Stage(number: 2, name: "Tape Trail", beat: "The tape trail sticks together again. Mostly.",
              length: 55, challenge: .closeCalls(3), stitchTarget: 60, gadget: nil, monster: nil),
        Stage(number: 3, name: "Corrugated Cliffs", beat: "The cliffs stand tall, ridges and all.",
              length: 60, challenge: .streak(25), stitchTarget: 70, gadget: nil, monster: nil),
        Stage(number: 4, name: "Glue Gulch", beat: "Glue Gulch is sticky, but whole.",
              length: 60, challenge: .noHits, stitchTarget: 75, gadget: nil, monster: nil),
        Stage(number: 5, name: "Packing Peanut Pass", beat: "Packing peanuts rain down like confetti. Hooray!",
              length: 65, challenge: .spools(80), stitchTarget: 85, gadget: nil, monster: nil),
        Stage(number: 6, name: "Shipping Label Mesa", beat: "Every label on the mesa points the right way again.",
              length: 70, challenge: .closeCalls(5), stitchTarget: 95, gadget: nil, monster: nil),
        Stage(number: 7, name: "Bubble Wrap Basin", beat: "Pop! Pop! The basin cheers for you.",
              length: 70, challenge: .streak(35), stitchTarget: 100, gadget: nil, monster: nil),
        Stage(number: 8, name: "Staple Switchbacks", beat: "The switchbacks are stapled tight.",
              length: 75, challenge: .noHits, stitchTarget: 110, gadget: nil, monster: nil),
        Stage(number: 9, name: "Carton Falls", beat: "Cartons tumble back into neat stacks.",
              length: 80, challenge: .spools(120), stitchTarget: 120, gadget: nil, monster: nil),
        Stage(number: 10, name: "The Big Box", beat: "The Shredder huffs off! Corrugo climbs out of the Big Box to join you!",
              length: 90, challenge: .closeCalls(6), stitchTarget: 135, gadget: nil, monster: "corrugo")
    ]

    static let lagoon: [Stage] = [
        Stage(number: 1, name: "Inkwell Shore", beat: "The shore turns from gray back to deep blue.",
              length: 55, challenge: .spools(55), stitchTarget: 60, gadget: nil, monster: nil),
        Stage(number: 2, name: "Quill Reeds", beat: "The quill reeds rustle and write a thank-you note.",
              length: 60, challenge: .streak(25), stitchTarget: 70, gadget: nil, monster: nil),
        Stage(number: 3, name: "Blot Bay", beat: "Blot Bay settles into a calm, inky shine.",
              length: 60, challenge: .closeCalls(4), stitchTarget: 75, gadget: nil, monster: nil),
        Stage(number: 4, name: "Paper Boat Harbor", beat: "The paper boats set sail once more.",
              length: 65, challenge: .noHits, stitchTarget: 80, gadget: nil, monster: nil),
        Stage(number: 5, name: "Fountain Pen Falls", beat: "The falls flow in perfect cursive.",
              length: 70, challenge: .spools(90), stitchTarget: 95, gadget: nil, monster: nil),
        Stage(number: 6, name: "Smudge Marsh", beat: "The marsh is clean. Well, cleaner.",
              length: 70, challenge: .streak(35), stitchTarget: 100, gadget: nil, monster: nil),
        Stage(number: 7, name: "Calligraphy Current", beat: "The current curls in fancy loops again.",
              length: 75, challenge: .closeCalls(6), stitchTarget: 110, gadget: nil, monster: nil),
        Stage(number: 8, name: "Drip Rock", beat: "Drip Rock drips in rhythm. Plip. Plip. Plip.",
              length: 80, challenge: .noHits, stitchTarget: 115, gadget: nil, monster: nil),
        Stage(number: 9, name: "Stain Reef", beat: "The reef glows every color of ink.",
              length: 85, challenge: .spools(130), stitchTarget: 125, gadget: nil, monster: nil),
        Stage(number: 10, name: "The Deep Inkwell", beat: "The Shredder slinks off, soggy! Squidge paddles up in a paper boat!",
              length: 95, challenge: .streak(45), stitchTarget: 140, gadget: nil, monster: "squidge")
    ]

    static let peaks: [Stage] = [
        Stage(number: 1, name: "Crease Foothills", beat: "The foothills fold neatly into place.",
              length: 60, challenge: .spools(65), stitchTarget: 70, gadget: nil, monster: nil),
        Stage(number: 2, name: "Fold Trail", beat: "The trail unfolds ahead of you.",
              length: 65, challenge: .closeCalls(5), stitchTarget: 80, gadget: nil, monster: nil),
        Stage(number: 3, name: "Crane Pass", beat: "Paper cranes take wing over the pass.",
              length: 65, challenge: .streak(35), stitchTarget: 85, gadget: nil, monster: nil),
        Stage(number: 4, name: "Valley Fold", beat: "The valley folds back into green.",
              length: 70, challenge: .noHits, stitchTarget: 90, gadget: nil, monster: nil),
        Stage(number: 5, name: "Lantern Camp", beat: "Paper lanterns flicker on, one by one.",
              length: 75, challenge: .spools(105), stitchTarget: 105, gadget: nil, monster: nil),
        Stage(number: 6, name: "Mountain Fold Ridge", beat: "The ridge stands crisp against the sky.",
              length: 75, challenge: .closeCalls(7), stitchTarget: 110, gadget: nil, monster: nil),
        Stage(number: 7, name: "Snow Crimp", beat: "Fresh paper snow crunches underfoot.",
              length: 80, challenge: .streak(45), stitchTarget: 120, gadget: nil, monster: nil),
        Stage(number: 8, name: "Pleat Glacier", beat: "The glacier's pleats shine like new.",
              length: 85, challenge: .noHits, stitchTarget: 125, gadget: nil, monster: nil),
        Stage(number: 9, name: "Summit Square", beat: "Crumple waves from the summit. One seam left!",
              length: 90, challenge: .spools(150), stitchTarget: 135, gadget: nil, monster: "crumple"),
        Stage(number: 10, name: "The Shredder's Lair", beat: "The Shredder unwinds into harmless confetti. The Paper World is whole!",
              length: 100, challenge: .closeCalls(8), stitchTarget: 150, gadget: nil, monster: nil)
    ]
}
