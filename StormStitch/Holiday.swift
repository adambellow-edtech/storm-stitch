import Foundation

/// Seasonal events. Each one reskins Notebook Meadow and adds a race against a rival
/// who joins the cast when you beat them.
enum Holiday: String, CaseIterable, Codable {
    case harvest
    case snow

    var name: String {
        switch self {
        case .harvest: return "Harvest Gale"
        case .snow: return "Snowstorm"
        }
    }

    var raceName: String {
        switch self {
        case .harvest: return "Turkey Trot"
        case .snow: return "Reindeer Race"
        }
    }

    /// The rival you race, who unlocks when you win.
    var rivalID: String {
        switch self {
        case .harvest: return "gobbler"
        case .snow: return "comet"
        }
    }

    var rivalName: String {
        switch self {
        case .harvest: return "Gobbler"
        case .snow: return "Comet"
        }
    }

    /// Spools the rival collects by the finish; beat it to win.
    var rivalTarget: Int {
        switch self {
        case .harvest: return 55
        case .snow: return 65
        }
    }

    var raceLength: Double { 75 }

    var dates: String {
        switch self {
        case .harvest: return "November 20 to December 1"
        case .snow: return "December 2 to January 4"
        }
    }

    // Art. Each falls back to the regular meadow art when the image isn't in the app yet.
    var lowHazard: String { self == .harvest ? "hazard-pumpkin" : "hazard-present" }
    var crateHazard: String { self == .harvest ? "hazard-hay" : "hazard-snowman" }
    var treeColor: String { self == .harvest ? "tree-autumn" : "pine-color" }
    var treeGray: String { self == .harvest ? "tree-gray" : "pine-gray" }
    var groundColor: String { self == .harvest ? "ground-autumn" : "ground-snow" }
    var roadColor: String? { self == .harvest ? nil : "road-snow" }
    /// Cut-paper pieces that drift down the screen: five leaves, or paper snowflakes, punched dots, a scrap and a star.
    var particles: [String] {
        self == .harvest ? ["leaf-1", "leaf-2", "leaf-3", "leaf-4", "leaf-5"]
                         : ["snow-1", "snow-2", "snow-3", "snow-4", "snow-5", "snow-6"]
    }

    /// The event running on a given day, if any.
    static func active(on date: Date = Date()) -> Holiday? {
        let calendar = Calendar(identifier: .gregorian)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        if (month == 11 && day >= 20) || (month == 12 && day <= 1) { return .harvest }
        if month == 12 || (month == 1 && day <= 4) { return .snow }
        return nil
    }
}
