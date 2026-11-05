import Foundation

/// Everything the game remembers between launches, saved as JSON in UserDefaults.
struct SaveData: Codable {
    var stageStars: [Int] = Array(repeating: 0, count: Stage.meadow.count)
    var stageBest: [Int] = Array(repeating: 0, count: Stage.meadow.count)
    var lifetimeSpools = 0
    var bestStreak = 0
    var bestEndlessScore = 0
    var bestEndlessMeters = 0
    var longestEndless = 0.0
    var unlockedMonsters: [String] = ["bramble"]
    var unlockedGadgets: [String] = []
    var equippedGadget: String? = nil
    var trophies: [String] = []
    /// Official (first) score for each Daily Storm played, by key.
    var dailyScores: [String: Int] = [:]
    var rewindsUsed = 0
    var holidayWins: [String] = []
    var storySeen = false
    var music = true
    var sound = true
    var haptics = true
}

/// Things that unlocked at the end of a run, to celebrate on the results card.
enum UnlockEvent {
    case monster(Monster)
    case gadget(Gadget)
    case trophy(Trophy)

    var title: String {
        switch self {
        case .monster(let m): return "New monster: \(m.name)!"
        case .gadget(let g): return "New gadget: \(g.name)!"
        case .trophy(let t): return "Trophy: \(t.name)!"
        }
    }

    var detail: String {
        switch self {
        case .monster(let m): return m.passive
        case .gadget(let g): return g.blurb
        case .trophy(let t): return t.detail
        }
    }

    var image: String {
        switch self {
        case .monster(let m): return "\(m.id)-front"
        case .gadget(let g): return g.icon
        case .trophy: return "menu-trophy"
        }
    }
}

final class Progress {
    static let shared = Progress()

    private let key = "stormStitchSave.v1"
    private(set) var data: SaveData

    private init() {
        if let raw = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(SaveData.self, from: raw) {
            data = saved
            // Older saves may have fewer stages than the game now has.
            let count = Stage.meadow.count
            if data.stageStars.count < count {
                data.stageStars += Array(repeating: 0, count: count - data.stageStars.count)
            }
            if data.stageBest.count < count {
                data.stageBest += Array(repeating: 0, count: count - data.stageBest.count)
            }
        } else {
            data = SaveData()
        }
    }

    func save() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: key)
        }
    }

    func update(_ change: (inout SaveData) -> Void) {
        change(&data)
        save()
    }

    // MARK: Queries

    var totalStars: Int { data.stageStars.reduce(0, +) }
    var dailiesPlayed: Int { data.dailyScores.count }

    func stars(forStage index: Int) -> Int {
        index >= 0 && index < data.stageStars.count ? data.stageStars[index] : 0
    }

    /// A stage is open once the one before it is cleared.
    func isStageOpen(_ index: Int) -> Bool {
        index == 0 || stars(forStage: index - 1) > 0
    }

    var nextStageIndex: Int {
        data.stageStars.firstIndex { $0 == 0 } ?? (Stage.meadow.count - 1)
    }

    func isUnlocked(_ monster: Monster) -> Bool {
        data.unlockedMonsters.contains(monster.id)
    }

    var unlockedGadgets: [Gadget] {
        Gadget.allCases.filter { data.unlockedGadgets.contains($0.rawValue) }
    }

    var equippedGadget: Gadget? {
        guard let raw = data.equippedGadget, let gadget = Gadget(rawValue: raw),
              data.unlockedGadgets.contains(raw) else { return nil }
        return gadget
    }

    func hasTrophy(_ trophy: Trophy) -> Bool {
        data.trophies.contains(trophy.rawValue)
    }

    /// Progress toward a locked monster, 0 to 1, for the trophy case.
    func progress(toward monster: Monster) -> Double {
        switch monster.unlock {
        case .start: return 1
        case .stage(let n): return stars(forStage: n - 1) > 0 ? 1 : Double(min(nextStageIndex, n - 1)) / Double(n)
        case .lifetimeSpools(let n): return min(1, Double(data.lifetimeSpools) / Double(n))
        case .stars(let n): return min(1, Double(totalStars) / Double(n))
        case .dailies(let n): return min(1, Double(dailiesPlayed) / Double(n))
        case .streak(let n): return min(1, Double(data.bestStreak) / Double(n))
        case .holiday(let h): return data.holidayWins.contains(h.rawValue) ? 1 : 0
        }
    }

    // MARK: Recording a run

    /// Saves a finished or failed run and returns everything that newly unlocked.
    @discardableResult
    func record(_ stats: RunStats, mode: RunMode, stars: Int) -> [UnlockEvent] {
        var events: [UnlockEvent] = []
        let monstersBefore = Set(data.unlockedMonsters)
        let gadgetsBefore = Set(data.unlockedGadgets)

        data.lifetimeSpools += stats.spools
        data.bestStreak = max(data.bestStreak, stats.bestStreak)
        data.rewindsUsed += stats.rewinds

        switch mode {
        case .stage(let index):
            if index < data.stageStars.count {
                data.stageStars[index] = max(data.stageStars[index], stars)
                data.stageBest[index] = max(data.stageBest[index], stats.spools)
            }
            if stats.finished, index < Stage.meadow.count, let gadget = Stage.meadow[index].gadget,
               !data.unlockedGadgets.contains(gadget.rawValue) {
                data.unlockedGadgets.append(gadget.rawValue)
                // Equip the first gadget automatically so players notice it.
                if data.equippedGadget == nil { data.equippedGadget = gadget.rawValue }
            }
        case .endless:
            data.bestEndlessScore = max(data.bestEndlessScore, stats.score)
            data.bestEndlessMeters = max(data.bestEndlessMeters, Int(stats.distance))
            data.longestEndless = max(data.longestEndless, stats.elapsed)
        case .daily(let storm):
            if data.dailyScores[storm.key] == nil {
                data.dailyScores[storm.key] = stats.score
            }
        case .challenge:
            break
        case .race(let holiday):
            if stats.finished && stars > 0 && !data.holidayWins.contains(holiday.rawValue) {
                data.holidayWins.append(holiday.rawValue)
            }
        }

        // Monsters.
        for monster in Monster.roster where !data.unlockedMonsters.contains(monster.id) {
            if progress(toward: monster) >= 1 {
                data.unlockedMonsters.append(monster.id)
            }
        }

        // Trophies.
        func award(_ trophy: Trophy, _ condition: Bool) {
            if condition && !data.trophies.contains(trophy.rawValue) {
                data.trophies.append(trophy.rawValue)
                events.append(.trophy(trophy))
                GameCenter.report(trophy)
            }
        }
        var clearedStage = false
        if case .stage = mode, stats.finished { clearedStage = true }
        var isEndless = false
        if case .endless = mode { isEndless = true }
        var wonRace = false
        if case .race = mode, stats.finished, stars > 0 { wonRace = true }
        award(.firstStitch, clearedStage)
        award(.worldStitcher, stats.stitched)
        award(.closeShave, stats.closeCalls >= 5)
        award(.untouchable, clearedStage && stats.hits == 0)
        award(.hoarder, stats.spools >= 100)
        award(.marathon, isEndless && stats.distance >= 2000)
        award(.dailyDevotee, dailiesPlayed >= 7)
        award(.timeLord, data.rewindsUsed >= 10)
        award(.fullCast, Monster.roster.filter { $0.holiday == nil }.allSatisfy { data.unlockedMonsters.contains($0.id) })
        award(.starCollector, totalStars >= Stage.meadow.count * 3)
        award(.stormChaser, isEndless && stats.elapsed >= 180)
        award(.holidaySpirit, wonRace)

        for id in data.unlockedMonsters where !monstersBefore.contains(id) {
            events.insert(.monster(Monster.named(id)), at: 0)
        }
        for raw in data.unlockedGadgets where !gadgetsBefore.contains(raw) {
            if let gadget = Gadget(rawValue: raw) { events.insert(.gadget(gadget), at: 0) }
        }
        save()
        return events
    }

    /// Developer helper: unlock everything for testing.
    func unlockEverything() {
        update { data in
            data.unlockedMonsters = Monster.roster.map(\.id)
            data.unlockedGadgets = Gadget.allCases.map(\.rawValue)
            data.stageStars = data.stageStars.map { max($0, 1) }
        }
    }

    /// Developer helper: start over.
    func resetAll() {
        let keepSettings = (data.music, data.sound, data.haptics)
        data = SaveData()
        (data.music, data.sound, data.haptics) = keepSettings
        save()
    }
}
