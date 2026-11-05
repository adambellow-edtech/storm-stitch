import CoreGraphics
import Foundation

/// The playable cast. Each monster runs with its own art and one passive ability.
/// Art names: "<id>-back" runs away from the camera, "<id>-front" faces you on the results card.
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
    }

    let id: String
    let name: String
    /// One short line for the picker, under about 24 characters.
    let passive: String
    let ability: Ability
    /// On-screen heights (art units) for the running back view and the front view.
    let runHeight: CGFloat
    let frontHeight: CGFloat

    static let roster: [Monster] = [
        Monster(id: "bramble", name: "Bramble", passive: "Shrugs off the first hit",
                ability: .shrug, runHeight: 120, frontHeight: 120),
        Monster(id: "blotch", name: "Blotch", passive: "Hits pull the storm less",
                ability: .ink, runHeight: 110, frontHeight: 118),
        Monster(id: "snipjaw", name: "Snipjaw", passive: "Slides snip through boxes",
                ability: .snip, runHeight: 100, frontHeight: 104),
        Monster(id: "fizz", name: "Fizz", passive: "Faster lane changes",
                ability: .quick, runHeight: 122, frontHeight: 124),
        Monster(id: "origo", name: "Origo", passive: "Glides down from jumps",
                ability: .glide, runHeight: 120, frontHeight: 112),
        Monster(id: "wickling", name: "Wickling", passive: "Lights up extra spools",
                ability: .glow, runHeight: 128, frontHeight: 128),
        Monster(id: "stickle", name: "Stickle", passive: "Grabs spools a lane away",
                ability: .sticky, runHeight: 104, frontHeight: 104),
        Monster(id: "thundercap", name: "Thundercap", passive: "Storm falls back faster",
                ability: .counterstorm, runHeight: 116, frontHeight: 116)
    ]

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
