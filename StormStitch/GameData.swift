import Foundation

// MARK: Run modes

/// What kind of run is being played.
enum RunMode: Equatable {
    /// One of the Notebook Meadow stages, by index (0 to 9).
    case stage(Int)
    /// Run until the storm catches you.
    case endless
    /// Today's shared course.
    case daily(DailyStorm)
    /// A friend's course from a challenge link, with their score to beat.
    case challenge(DailyStorm, target: Int, from: String)
    /// A holiday race against the event's rival.
    case race(Holiday)

    var isDailyLike: Bool {
        switch self {
        case .daily, .challenge: return true
        default: return false
        }
    }
}

/// The settings for one run, worked out when the run starts.
struct RunConfig {
    var length: Double            // seconds; .infinity for endless
    var startSpeed: Double
    var endSpeed: Double
    var rampTime: Double          // seconds to reach end speed
    var intervalStart: Double     // seconds between hazard rows
    var intervalEnd: Double
    var overheadFrom: Double      // rulers appear after this many seconds
    var doubleChance: Double      // chance a row has two hazards
    var meterPerSpool: Double     // stitch meter gained per spool
    var rule: StormRule
    var seed: UInt64
    var hints: Bool               // first-stage how-to-play prompts
}

// MARK: Stages

enum Challenge: Equatable {
    case spools(Int)
    case noHits
    case closeCalls(Int)
    case streak(Int)

    var text: String {
        switch self {
        case .spools(let n): return "Collect \(n) spools"
        case .noHits: return "Finish without a hit"
        case .closeCalls(let n): return "Make \(n) close calls"
        case .streak(let n): return "Grab a streak of \(n)"
        }
    }

    func met(by stats: RunStats) -> Bool {
        switch self {
        case .spools(let n): return stats.spools >= n
        case .noHits: return stats.hits == 0
        case .closeCalls(let n): return stats.closeCalls >= n
        case .streak(let n): return stats.bestStreak >= n
        }
    }
}

struct Stage {
    let number: Int
    let name: String
    /// The story beat shown when the stage's seam is stitched shut.
    let beat: String
    let length: Double
    let challenge: Challenge
    /// Spools needed to fully stitch the stage (the third star).
    let stitchTarget: Int
    let gadget: Gadget?
    let monster: String?

    static let meadow: [Stage] = [
        Stage(number: 1, name: "First Stitch", beat: "The first seam holds. A patch of green peeks through the gray.",
              length: 45, challenge: .spools(30), stitchTarget: 40, gadget: .shield, monster: nil),
        Stage(number: 2, name: "Eraser Hills", beat: "Eraser Hills bloom again, and Blotch bounces out to help!",
              length: 50, challenge: .spools(45), stitchTarget: 50, gadget: .magnet, monster: "blotch"),
        Stage(number: 3, name: "Ruler Ridge", beat: "Ruler Ridge is mended. The storm growls somewhere far off.",
              length: 55, challenge: .closeCalls(2), stitchTarget: 60, gadget: .rewind, monster: nil),
        Stage(number: 4, name: "Cardboard Crossing", beat: "The boxes stop tumbling. Snipjaw snaps a happy hello!",
              length: 60, challenge: .noHits, stitchTarget: 70, gadget: nil, monster: "snipjaw"),
        Stage(number: 5, name: "Doodle Brook", beat: "Blue ink runs through Doodle Brook once more.",
              length: 60, challenge: .streak(20), stitchTarget: 75, gadget: .plane, monster: nil),
        Stage(number: 6, name: "Pencil Pines", beat: "The pencil pines stand tall and sharp again.",
              length: 65, challenge: .spools(70), stitchTarget: 85, gadget: .ink, monster: nil),
        Stage(number: 7, name: "Ink Pond", beat: "Ink Pond shimmers. Little paper frogs croak a thank-you.",
              length: 70, challenge: .closeCalls(4), stitchTarget: 95, gadget: .eraser, monster: nil),
        Stage(number: 8, name: "Margin Meadow", beat: "Even the margins are green now. The storm is getting angry.",
              length: 75, challenge: .streak(30), stitchTarget: 105, gadget: .fold, monster: nil),
        Stage(number: 9, name: "Spiral Bind", beat: "The spiral binding is tight. One seam left!",
              length: 80, challenge: .noHits, stitchTarget: 115, gadget: nil, monster: nil),
        Stage(number: 10, name: "The Shredder's Edge", beat: "Notebook Meadow is whole again! Thundercap switches sides to join you.",
              length: 90, challenge: .spools(110), stitchTarget: 130, gadget: nil, monster: "thundercap")
    ]

    var config: RunConfig {
        let i = Double(number - 1)
        return RunConfig(length: length,
                         startSpeed: 8 + i * 0.35,
                         endSpeed: 10.5 + i * 0.6,
                         rampTime: length,
                         intervalStart: 1.05 - i * 0.03,
                         intervalEnd: 0.85 - i * 0.03,
                         overheadFrom: number == 1 ? .infinity : (number == 2 ? 12 : 0),
                         doubleChance: number <= 2 ? 0 : 0.2 + i * 0.04,
                         meterPerSpool: 1 / Double(stitchTarget),
                         rule: .calm,
                         seed: GameRNG.freshSeed(),
                         hints: number == 1)
    }
}

// MARK: Gadgets

/// Abilities you unlock by clearing stages, equip before a run, charge with spools and fire with the gadget button.
enum Gadget: String, CaseIterable, Codable {
    case shield, magnet, rewind, plane, ink, eraser, fold

    var name: String {
        switch self {
        case .shield: return "Stitch Shield"
        case .magnet: return "Thread Magnet"
        case .rewind: return "Time Machine"
        case .plane: return "Paper Plane"
        case .ink: return "Slow Ink"
        case .eraser: return "Big Eraser"
        case .fold: return "Page Fold"
        }
    }

    var blurb: String {
        switch self {
        case .shield: return "Sews a patch that blocks the next hit"
        case .magnet: return "Pulls in every spool for 6 seconds"
        case .rewind: return "Rewinds the last 3 seconds"
        case .plane: return "Fly over everything for 4 seconds"
        case .ink: return "Slows the world for 4 seconds"
        case .eraser: return "Erases every hazard ahead"
        case .fold: return "Folds the road and skips ahead"
        }
    }

    /// Image name of the icon.
    var icon: String { "gadget-" + iconSuffix }

    private var iconSuffix: String {
        switch self {
        case .shield: return "patch"
        case .magnet: return "magnet"
        case .rewind: return "rewind"
        case .plane: return "plane"
        case .ink: return "ink"
        case .eraser: return "eraser"
        case .fold: return "fold"
        }
    }

    /// Spools needed to charge it.
    var cost: Int {
        switch self {
        case .shield: return 12
        case .magnet: return 16
        case .rewind: return 25
        case .plane: return 20
        case .ink: return 15
        case .eraser: return 22
        case .fold: return 20
        }
    }

    /// A one-letter fallback for the button until the icon art arrives.
    var letter: String {
        switch self {
        case .shield: return "S"
        case .magnet: return "M"
        case .rewind: return "R"
        case .plane: return "P"
        case .ink: return "I"
        case .eraser: return "E"
        case .fold: return "F"
        }
    }
}

// MARK: Storm rules

/// The Daily Storm's twist of the day.
enum StormRule: String, CaseIterable, Codable {
    case calm, fog, mirror, gusty, spoolRain, speedy, giant, night

    var name: String {
        switch self {
        case .calm: return "Calm Skies"
        case .fog: return "Fog Day"
        case .mirror: return "Mirror Day"
        case .gusty: return "Gusty Day"
        case .spoolRain: return "Spool Rain"
        case .speedy: return "Speed Storm"
        case .giant: return "Giant Day"
        case .night: return "Night Run"
        }
    }

    var blurb: String {
        switch self {
        case .calm: return "No tricks. Just you and the storm."
        case .fog: return "Thick fog hides what's ahead."
        case .mirror: return "Left is right and right is left!"
        case .gusty: return "Gusts shove you between lanes."
        case .spoolRain: return "Twice the spools. Grab them all!"
        case .speedy: return "Everything runs 30% faster."
        case .giant: return "Every hazard is huge."
        case .night: return "Only your lantern lights the way."
        }
    }

    var emoji: String {
        switch self {
        case .calm: return "☀️"
        case .fog: return "🌫️"
        case .mirror: return "🪞"
        case .gusty: return "💨"
        case .spoolRain: return "🧵"
        case .speedy: return "⚡️"
        case .giant: return "🦣"
        case .night: return "🌙"
        }
    }
}

// MARK: Daily Storm

struct DailyStorm: Equatable {
    /// Days since launch, so players can say "Daily #42".
    let number: Int
    let seed: UInt64
    let rule: StormRule
    let monsterID: String

    static let length: Double = 90
    private static let epoch: Date = {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 11
        parts.day = 1
        return Calendar(identifier: .gregorian).date(from: parts) ?? Date(timeIntervalSince1970: 1_793_500_000)
    }()

    /// Today's storm in the player's own time zone, so it rolls over at their midnight.
    static func today(_ date: Date = Date()) -> DailyStorm {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: epoch)
        let now = calendar.startOfDay(for: date)
        let number = max(1, (calendar.dateComponents([.day], from: start, to: now).day ?? 0) + 1)
        return DailyStorm(number: number)
    }

    /// Everything about a daily comes from its number, so a challenge link only needs the number.
    init(number: Int) {
        self.number = number
        var rng = GameRNG(seed: UInt64(number) &* 7_919 &+ 104_729)
        seed = rng.next()
        let rules = StormRule.allCases
        // Every 7th day is calm so new players get an easy one each week.
        rule = number % 7 == 0 ? .calm : rules[Int(rng.next() % UInt64(rules.count - 1)) + 1]
        // The original eight: the Daily Storm's runner must look the same on every phone and app version.
        let cast = Array(Monster.roster.filter { $0.holiday == nil }.prefix(8))
        monsterID = cast[Int(rng.next() % UInt64(cast.count))].id
    }

    var key: String { "daily-\(number)" }

    var config: RunConfig {
        RunConfig(length: DailyStorm.length,
                  startSpeed: rule == .speedy ? 11 : 9,
                  endSpeed: rule == .speedy ? 18.5 : 14.5,
                  rampTime: DailyStorm.length,
                  intervalStart: 0.95,
                  intervalEnd: 0.68,
                  overheadFrom: 8,
                  doubleChance: 0.35,
                  meterPerSpool: 1.0 / 110,
                  rule: rule,
                  seed: seed,
                  hints: false)
    }
}

// MARK: Run results

struct RunStats {
    var spools = 0
    var distance = 0.0
    var hits = 0
    var closeCalls = 0
    var bestStreak = 0
    var stitched = false
    var meterPercent = 0
    var elapsed = 0.0
    var finished = false
    var rewinds = 0

    /// Daily, challenge and endless score.
    var score: Int { spools * 10 + Int(distance) }
}

// MARK: Trophies

enum Trophy: String, CaseIterable, Codable {
    case firstStitch, worldStitcher, closeShave, untouchable, hoarder, marathon
    case dailyDevotee, timeLord, fullCast, starCollector, stormChaser, holidaySpirit

    var name: String {
        switch self {
        case .firstStitch: return "First Stitch"
        case .worldStitcher: return "World Stitcher"
        case .closeShave: return "Close Shave"
        case .untouchable: return "Untouchable"
        case .hoarder: return "Spool Hoarder"
        case .marathon: return "Marathon"
        case .dailyDevotee: return "Daily Devotee"
        case .timeLord: return "Time Lord"
        case .fullCast: return "Full Cast"
        case .starCollector: return "Star Collector"
        case .stormChaser: return "Storm Chaser"
        case .holidaySpirit: return "Holiday Spirit"
        }
    }

    var detail: String {
        switch self {
        case .firstStitch: return "Clear your first stage"
        case .worldStitcher: return "Fully stitch a run"
        case .closeShave: return "5 close calls in one run"
        case .untouchable: return "Clear a stage with no hits"
        case .hoarder: return "100 spools in one run"
        case .marathon: return "Run 2,000 m in Endless"
        case .dailyDevotee: return "Play 7 Daily Storms"
        case .timeLord: return "Use the Time Machine 10 times"
        case .fullCast: return "Unlock all 8 monsters"
        case .starCollector: return "Earn 30 stars"
        case .stormChaser: return "Survive 3 minutes in Endless"
        case .holidaySpirit: return "Win a holiday race"
        }
    }

    /// Game Center achievement ID (set these up in App Store Connect).
    var gameCenterID: String { "com.adambellow.stormstitch.trophy.\(rawValue)" }
}
