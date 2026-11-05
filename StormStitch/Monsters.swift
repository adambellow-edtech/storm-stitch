import CoreGraphics
import Foundation

/// The playable cast. Each monster runs with its own art and one passive ability.
/// Art names: "<id>-back" runs away from the camera, "<id>-front" faces you, and an
/// optional "<id>-blink" (the front view with eyes closed) makes it blink.
/// Bramble also has dedicated jump, slide, hit, win and lose poses.
struct Monster {
    enum Ability {
        case shrug         // Bramble: the first hit each run costs no heart
        case ink           // Blotch: each hit pulls the storm in less
        case snip          // Snipjaw: sliding cuts straight through boxes
        case quick         // Fizz: faster lane changes
        case glide         // Origo: floats down slowly from every jump
        case glow          // Wickling: more spools appear
        case sticky        // Stickle: grabs spools from the next lane over
        case counterstorm  // Thundercap: the storm falls back faster
        case feast         // Gobbler: spools count double during a streak of 10 or more
        case bounce        // Comet: higher, longer jumps
        case barge         // Corrugo: crashes straight through boxes
        case charge        // Squidge: gadgets charge twice as fast
        case frost         // Crumple: starts every run with a Stitch Shield
    }

    /// How a monster joins the cast.
    enum Unlock {
        case start
        case stage(Int)            // clear this stage number
        case lifetimeSpools(Int)
        case stars(Int)
        case dailies(Int)
        case streak(Int)
        case holiday(Holiday)

        var text: String {
            switch self {
            case .start: return "Ready from the start"
            case .stage(let n):
                let world = World.all[World.index(ofStage: n - 1)]
                let local = (n - 1) % World.stagesPerWorld + 1
                return world.id == "meadow" ? "Clear stage \(n)" : "Clear \(world.name) \(local)"
            case .lifetimeSpools(let n): return "Collect \(n.formatted()) spools in all"
            case .stars(let n): return "Earn \(n) stars"
            case .dailies(let n): return "Play \(n) Daily Storms"
            case .streak(let n): return "Grab a streak of \(n)"
            case .holiday(let h): return "Win the \(h.raceName)"
            }
        }
    }

    let id: String
    let name: String
    /// One short line for menus, under about 24 characters.
    let passive: String
    let ability: Ability
    let unlock: Unlock
    /// On-screen heights (art units) for the running back view and the front view.
    let runHeight: CGFloat
    let frontHeight: CGFloat
    var holiday: Holiday? = nil

    static let roster: [Monster] = [
        Monster(id: "bramble", name: "Bramble", passive: "Shrugs off the first hit",
                ability: .shrug, unlock: .start, runHeight: 120, frontHeight: 120),
        Monster(id: "blotch", name: "Blotch", passive: "Hits pull the storm less",
                ability: .ink, unlock: .stage(2), runHeight: 110, frontHeight: 118),
        Monster(id: "snipjaw", name: "Snipjaw", passive: "Slides snip through boxes",
                ability: .snip, unlock: .stage(4), runHeight: 100, frontHeight: 104),
        Monster(id: "fizz", name: "Fizz", passive: "Faster lane changes",
                ability: .quick, unlock: .lifetimeSpools(1000), runHeight: 122, frontHeight: 124),
        Monster(id: "origo", name: "Origo", passive: "Glides down from jumps",
                ability: .glide, unlock: .stars(15), runHeight: 120, frontHeight: 112),
        Monster(id: "wickling", name: "Wickling", passive: "Lights up extra spools",
                ability: .glow, unlock: .dailies(3), runHeight: 128, frontHeight: 128),
        Monster(id: "stickle", name: "Stickle", passive: "Grabs spools a lane away",
                ability: .sticky, unlock: .streak(30), runHeight: 104, frontHeight: 104),
        Monster(id: "thundercap", name: "Thundercap", passive: "Storm falls back faster",
                ability: .counterstorm, unlock: .stage(10), runHeight: 116, frontHeight: 116),
        Monster(id: "gobbler", name: "Gobbler", passive: "Streaks count double",
                ability: .feast, unlock: .holiday(.harvest), runHeight: 120, frontHeight: 124, holiday: .harvest),
        Monster(id: "comet", name: "Comet", passive: "Higher, longer jumps",
                ability: .bounce, unlock: .holiday(.snow), runHeight: 122, frontHeight: 124, holiday: .snow),
        Monster(id: "corrugo", name: "Corrugo", passive: "Crashes through boxes",
                ability: .barge, unlock: .stage(20), runHeight: 122, frontHeight: 124),
        Monster(id: "squidge", name: "Squidge", passive: "Gadgets charge 2x faster",
                ability: .charge, unlock: .stage(30), runHeight: 116, frontHeight: 118),
        Monster(id: "crumple", name: "Crumple", passive: "Starts with a shield",
                ability: .frost, unlock: .stage(39), runHeight: 126, frontHeight: 128)
    ]

    static func named(_ id: String) -> Monster {
        roster.first { $0.id == id } ?? roster[0]
    }

    private static let savedKey = "selectedMonster"

    /// The monster the player last picked, Bramble by default.
    static var selectedIndex: Int {
        get {
            let saved = UserDefaults.standard.string(forKey: savedKey) ?? "bramble"
            return roster.firstIndex { $0.id == saved } ?? 0
        }
        set {
            let index = ((newValue % roster.count) + roster.count) % roster.count
            UserDefaults.standard.set(roster[index].id, forKey: savedKey)
        }
    }
}
