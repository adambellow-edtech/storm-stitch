import GameKit
import QuartzCore
import SpriteKit
import UIKit

// MARK: Feature flag

/// "Race a Friend": live two-player races over Game Center real-time matches.
/// Ships dark: release builds keep it off until `enabled` flips to true.
/// Debug builds (run from Xcode) get it so it can be tested on two phones.
/// Needs the Game Center capability, which the app already has (project.yml entitlements).
enum LiveRaceFlags {
    static let enabled = false
    static let enabledInDebug = true

    static var isOn: Bool {
        #if DEBUG
        return enabledInDebug
        #else
        return enabled
        #endif
    }
}

// MARK: Packets

/// Everything the two phones say to each other. Small, binary, little-endian.
///
/// Every packet starts with a 4-byte header: `0x53 0x53` ("SS"), the protocol version, then the type.
///
/// | type | name    | mode       | body |
/// |------|---------|------------|------|
/// | 1    | hello   | reliable   | build u16 |
/// | 2    | start   | reliable   | raceID u32, daily i32, startAt f64 (Unix seconds) |
/// | 3    | state   | unreliable | raceID u32, seq u16, elapsed f32, distance f32, speed f32, x f32, y f32, flags u8, lane i8, spools u16 (33 bytes total) |
/// | 4    | power   | reliable   | raceID u32, length u8, UTF-8 PowerKind raw value |
/// | 5    | finish  | reliable   | raceID u32, ending u8 (0 finished, 1 caught, 2 out of hearts), elapsed f32, distance f32, spools u16, score i32 |
/// | 6    | rematch | reliable   | raceID u32 (the race just finished) |
/// | 7    | leave   | reliable   | (empty) |
///
/// State flags: bit 0 alive, bit 1 sliding, bit 2 jumping, bit 3 paused.
enum RacePacket: Equatable {
    struct Snapshot: Equatable {
        var raceID: UInt32
        var seq: UInt16
        var elapsed: Float
        var distance: Float
        var speed: Float
        var x: Float
        var y: Float
        var alive: Bool
        var sliding: Bool
        var jumping: Bool
        var paused: Bool
        var lane: Int8
        var spools: UInt16
    }

    struct Result: Equatable {
        enum Ending: UInt8 {
            case finished = 0, caught = 1, outOfHearts = 2
        }
        var raceID: UInt32
        var ending: Ending
        var elapsed: Float
        var distance: Float
        var spools: UInt16
        var score: Int32

        var finished: Bool { ending == .finished }
    }

    case hello(build: UInt16)
    case start(raceID: UInt32, daily: Int32, startAt: Double)
    case state(Snapshot)
    case power(raceID: UInt32, kind: String)
    case finish(Result)
    case rematch(raceID: UInt32)
    case leave

    static let version: UInt8 = 1
    /// Bumped whenever gameplay changes in a way that would make two builds run different courses.
    static let build: UInt16 = 1

    var isReliable: Bool {
        if case .state = self { return false }
        return true
    }

    func encoded() -> Data {
        var w = ByteWriter()
        w.u8(0x53)
        w.u8(0x53)
        w.u8(RacePacket.version)
        switch self {
        case .hello(let build):
            w.u8(1)
            w.u16(build)
        case .start(let raceID, let daily, let startAt):
            w.u8(2)
            w.u32(raceID)
            w.u32(UInt32(bitPattern: daily))
            w.f64(startAt)
        case .state(let s):
            w.u8(3)
            w.u32(s.raceID)
            w.u16(s.seq)
            w.f32(s.elapsed)
            w.f32(s.distance)
            w.f32(s.speed)
            w.f32(s.x)
            w.f32(s.y)
            var flags: UInt8 = 0
            if s.alive { flags |= 1 }
            if s.sliding { flags |= 2 }
            if s.jumping { flags |= 4 }
            if s.paused { flags |= 8 }
            w.u8(flags)
            w.u8(UInt8(bitPattern: s.lane))
            w.u16(s.spools)
        case .power(let raceID, let kind):
            w.u8(4)
            w.u32(raceID)
            let bytes = Array(kind.utf8.prefix(40))
            w.u8(UInt8(bytes.count))
            w.raw(bytes)
        case .finish(let r):
            w.u8(5)
            w.u32(r.raceID)
            w.u8(r.ending.rawValue)
            w.f32(r.elapsed)
            w.f32(r.distance)
            w.u16(r.spools)
            w.u32(UInt32(bitPattern: r.score))
        case .rematch(let raceID):
            w.u8(6)
            w.u32(raceID)
        case .leave:
            w.u8(7)
        }
        return Data(w.bytes)
    }

    static func decode(_ data: Data) -> RacePacket? {
        var r = ByteReader(data)
        guard r.u8() == 0x53, r.u8() == 0x53, r.u8() == RacePacket.version, let type = r.u8() else { return nil }
        switch type {
        case 1:
            guard let build = r.u16() else { return nil }
            return .hello(build: build)
        case 2:
            guard let raceID = r.u32(), let daily = r.u32(), let startAt = r.f64(), startAt.isFinite else { return nil }
            return .start(raceID: raceID, daily: Int32(bitPattern: daily), startAt: startAt)
        case 3:
            guard let raceID = r.u32(), let seq = r.u16(),
                  let elapsed = r.f32(), let distance = r.f32(), let speed = r.f32(),
                  let x = r.f32(), let y = r.f32(), let flags = r.u8(), let lane = r.u8(), let spools = r.u16(),
                  [elapsed, distance, speed, x, y].allSatisfy({ $0.isFinite }) else { return nil }
            return .state(Snapshot(raceID: raceID, seq: seq, elapsed: elapsed, distance: distance, speed: speed,
                                   x: x, y: y, alive: flags & 1 != 0, sliding: flags & 2 != 0,
                                   jumping: flags & 4 != 0, paused: flags & 8 != 0,
                                   lane: Int8(bitPattern: lane), spools: spools))
        case 4:
            guard let raceID = r.u32(), let count = r.u8(), let bytes = r.raw(Int(count)) else { return nil }
            return .power(raceID: raceID, kind: String(decoding: bytes, as: UTF8.self))
        case 5:
            guard let raceID = r.u32(), let endingRaw = r.u8(), let ending = Result.Ending(rawValue: endingRaw),
                  let elapsed = r.f32(), let distance = r.f32(), let spools = r.u16(), let score = r.u32(),
                  elapsed.isFinite, distance.isFinite else { return nil }
            return .finish(Result(raceID: raceID, ending: ending, elapsed: elapsed, distance: distance,
                                  spools: spools, score: Int32(bitPattern: score)))
        case 6:
            guard let raceID = r.u32() else { return nil }
            return .rematch(raceID: raceID)
        case 7:
            return .leave
        default:
            return nil
        }
    }
}

struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16(_ v: UInt16) { put(UInt64(v), count: 2) }
    mutating func u32(_ v: UInt32) { put(UInt64(v), count: 4) }
    mutating func u64(_ v: UInt64) { put(v, count: 8) }
    mutating func f32(_ v: Float) { u32(v.bitPattern) }
    mutating func f64(_ v: Double) { u64(v.bitPattern) }
    mutating func raw(_ more: [UInt8]) { bytes.append(contentsOf: more) }

    private mutating func put(_ v: UInt64, count: Int) {
        for k in 0..<count {
            bytes.append(UInt8(truncatingIfNeeded: v >> UInt64(8 * k)))
        }
    }
}

struct ByteReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func raw(_ count: Int) -> [UInt8]? {
        guard count >= 0, index + count <= bytes.count else { return nil }
        defer { index += count }
        return Array(bytes[index..<(index + count)])
    }

    private mutating func value(_ count: Int) -> UInt64? {
        guard let chunk = raw(count) else { return nil }
        var v: UInt64 = 0
        for (k, byte) in chunk.enumerated() {
            v |= UInt64(byte) << UInt64(8 * k)
        }
        return v
    }

    mutating func u8() -> UInt8? { value(1).map { UInt8(truncatingIfNeeded: $0) } }
    mutating func u16() -> UInt16? { value(2).map { UInt16(truncatingIfNeeded: $0) } }
    mutating func u32() -> UInt32? { value(4).map { UInt32(truncatingIfNeeded: $0) } }
    mutating func u64() -> UInt64? { value(8) }
    mutating func f32() -> Float? { u32().map { Float(bitPattern: $0) } }
    mutating func f64() -> Double? { u64().map { Double(bitPattern: $0) } }
}

// MARK: Who won

enum RaceVerdict: Equatable {
    case pending, win, lose, draw
    /// The opponent left while you were ahead.
    case forfeitWin
    /// The opponent left while you were behind or level.
    case noContest

    var isDecided: Bool { self != .pending }

    /// Same answer on both phones, given the same two results: a finish beats being caught,
    /// two finishers compare score, and of two runners caught by the storm the one who lasted longer wins.
    static func judge(mine m: RacePacket.Result, theirs t: RacePacket.Result) -> RaceVerdict {
        func compare<T: Comparable>(_ a: T, _ b: T) -> RaceVerdict? {
            if a == b { return nil }
            return a > b ? RaceVerdict.win : RaceVerdict.lose
        }
        switch (m.finished, t.finished) {
        case (true, true):
            return compare(m.score, t.score) ?? compare(m.distance, t.distance) ?? .draw
        case (true, false):
            return .win
        case (false, true):
            return .lose
        case (false, false):
            let gap = Double(m.elapsed) - Double(t.elapsed)
            if abs(gap) > RaceVerdict.sameMoment { return gap > 0 ? .win : .lose }
            return compare(m.distance, t.distance) ?? compare(m.spools, t.spools) ?? .draw
        }
    }

    /// Two eliminations closer than this (seconds of race time) count as the same moment.
    static let sameMoment = 0.05
}

// MARK: Match manager

/// Owns the Game Center match: matchmaking, invites, packets, and the race's shared facts.
/// The scene side (ghost, HUD, countdown, results) lives in the RunScene extension below.
final class LiveRace: NSObject {
    static let shared = LiveRace()

    enum Phase { case idle, matchmaking, connecting, countdown, racing, ended }

    private(set) var phase: Phase = .idle
    weak var scene: RunScene?

    private var match: GKMatch?
    private(set) var opponent: GKPlayer?
    private var listening = false
    private var helloSent = false
    private var opponentSaidHello = false
    private var connectingSince = 0.0

    // The current race.
    private(set) var raceID: UInt32 = 0
    private(set) var raceMode: RunMode?
    private(set) var opponentState: RacePacket.Snapshot?
    private(set) var opponentStateAt = 0.0
    private var lastHeardAt = 0.0
    private(set) var opponentResult: RacePacket.Result?
    private(set) var myResult: RacePacket.Result?
    private(set) var opponentLeft = false
    private var leftWhileAhead = false
    private(set) var verdict: RaceVerdict = .pending
    private(set) var wantsRematch = false
    private(set) var opponentWantsRematch = false
    private var sendSeq: UInt16 = 0
    private var sendTimer = 0.0
    private var powersSent = 0

    // What the results card needs to redraw itself when the outcome lands.
    var lastCaught = false
    var lastFinished = false
    var lastStars = 0

    // Scene nodes, kept here because extensions can't add stored properties to RunScene.
    let ghost = SKSpriteNode()
    let ghostTag = SKSpriteNode()
    let leadLabel = SKSpriteNode()
    var ghostX = 0.0
    var ghostY = 0.0
    var leadText = ""
    var leadTimer = 0.0

    static let stateInterval = 0.1
    static let silenceLimit = 10.0
    static let connectLimit = 25.0
    static let countdownLead = 3.6

    /// Shown only when the flag is on and Game Center is signed in and allows multiplayer.
    static var isAvailable: Bool {
        LiveRaceFlags.isOn && GKLocalPlayer.local.isAuthenticated && !GKLocalPlayer.local.isMultiplayerGamingRestricted
    }

    var opponentName: String {
        let name = opponent?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Your friend" : String(name.prefix(14))
    }

    private var isHost: Bool {
        guard let opponent else { return false }
        return GKLocalPlayer.local.gamePlayerID < opponent.gamePlayerID
    }

    private var now: Double { CACurrentMediaTime() }

    /// True when this run is the live race (the mode a live race is played in).
    func owns(_ mode: RunMode) -> Bool {
        guard phase == .countdown || phase == .racing || phase == .ended, let raceMode else { return false }
        return raceMode == mode
    }

    // MARK: Starting

    /// Listens for invites from friends. Called once Game Center signs in.
    func registerForInvites() {
        guard LiveRaceFlags.isOn, !listening else { return }
        listening = true
        GKLocalPlayer.local.register(self)
    }

    /// The "Race a Friend" button: opens Game Center's friend picker.
    func findOpponent(from scene: RunScene) {
        guard LiveRace.isAvailable else { return }
        self.scene = scene
        leave()
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.inviteMessage = "Race me in Storm Stitch! Same course, live."
        present(GKMatchmakerViewController(matchRequest: request))
    }

    private func present(_ controller: GKMatchmakerViewController?) {
        guard let controller, let presenter = GameCenter.topViewController() else {
            phase = .idle
            return
        }
        if let scene, scene.state == .running { scene.pauseGame() }
        phase = .matchmaking
        controller.matchmakerDelegate = self
        presenter.present(controller, animated: true)
    }

    private func matchFound(_ newMatch: GKMatch) {
        match = newMatch
        newMatch.delegate = self
        phase = .connecting
        connectingSince = now
        helloSent = false
        opponentSaidHello = false
        scene?.showLiveRaceStatus("Finding your friend...", detail: "Hang tight while Game Center connects you.")
        if newMatch.expectedPlayerCount == 0 { playersConnected() }
    }

    private func playersConnected() {
        guard let match, phase == .connecting, let remote = match.players.first else { return }
        opponent = remote
        scene?.showLiveRaceStatus("Racing \(opponentName)!", detail: "Getting the course ready...")
        send(.hello(build: RacePacket.build))
        helloSent = true
        if isHost && opponentSaidHello { hostStart() }
    }

    /// The host rolls the course (a Daily Storm number, so both phones build the same seeded run,
    /// the same runner and the same power gates) and a start time a few seconds out.
    private func hostStart() {
        var id = UInt32.random(in: 1...UInt32.max)
        if id == raceID { id = id &+ 1 }
        let daily = Int32.random(in: 1_000...99_999)
        let startAt = Date().timeIntervalSince1970 + LiveRace.countdownLead
        send(.start(raceID: id, daily: daily, startAt: startAt))
        begin(raceID: id, daily: Int(daily), startAt: startAt)
    }

    private func begin(raceID id: UInt32, daily: Int, startAt: Double) {
        raceID = id
        opponentState = nil
        opponentResult = nil
        myResult = nil
        opponentLeft = false
        leftWhileAhead = false
        verdict = .pending
        wantsRematch = false
        opponentWantsRematch = false
        sendSeq = 0
        sendTimer = 0
        powersSent = 0
        lastHeardAt = now
        let storm = DailyStorm(number: daily)
        raceMode = .challenge(storm, target: 0, from: opponentName)
        phase = .countdown
        scene?.beginLiveRace(startAt: startAt)
    }

    // MARK: Leaving

    /// Ends the match on this phone and tells the other one.
    func leave() {
        if let match {
            send(.leave)
            match.delegate = nil
            match.disconnect()
        }
        match = nil
        opponent = nil
        raceMode = nil
        phase = .idle
        opponentState = nil
        opponentResult = nil
        myResult = nil
        opponentLeft = false
        verdict = .pending
        wantsRematch = false
        opponentWantsRematch = false
        ghost.isHidden = true
        leadLabel.isHidden = true
        leadText = ""
    }

    private func opponentDidLeave() {
        guard match != nil, !opponentLeft else { return }
        if phase == .connecting || phase == .matchmaking {
            let name = opponentName
            leave()
            scene?.showLiveRaceStatus("Couldn't start the race", detail: "\(name) isn't connected anymore. Try again in a moment.", failed: true)
            return
        }
        opponentLeft = true
        let mine = myResult.map { Double($0.distance) } ?? (scene?.distance ?? 0)
        let theirs = opponentResult.map { Double($0.distance) } ?? Double(opponentState?.distance ?? 0)
        leftWhileAhead = mine > theirs
        match?.delegate = nil
        match?.disconnect()
        match = nil
        refreshVerdict(notify: false)
        scene?.liveRaceOpponentLeft()
    }

    // MARK: Per frame

    func tick(_ scene: RunScene, dt: Double) {
        self.scene = scene
        let t = now
        switch phase {
        case .idle, .matchmaking:
            return
        case .connecting:
            if t - connectingSince > LiveRace.connectLimit {
                leave()
                scene.showLiveRaceStatus("Couldn't start the race", detail: "Game Center couldn't connect you. Try again in a moment.", failed: true)
            }
            return
        case .countdown, .racing, .ended:
            break
        }

        // Leaving the race screens (Quit from pause, a menu) leaves the match.
        let offRace: [RunScene.State] = [.title, .menu, .story]
        if !owns(scene.mode) || offRace.contains(scene.state) {
            leave()
            return
        }
        if phase == .countdown && scene.state == .running { phase = .racing }

        if phase != .ended {
            sendTimer -= dt
            if sendTimer <= 0 {
                sendTimer = LiveRace.stateInterval
                sendState(from: scene)
            }
            let taken = scene.powers.taken
            if taken.count < powersSent { powersSent = taken.count }
            if taken.count > powersSent {
                for kind in taken[powersSent...] { send(.power(raceID: raceID, kind: kind.rawValue)) }
                powersSent = taken.count
            }
        }

        if !opponentLeft && opponentResult == nil && t - lastHeardAt > LiveRace.silenceLimit {
            opponentDidLeave()
        }
        refreshVerdict()
    }

    private func sendState(from scene: RunScene) {
        sendSeq = sendSeq &+ 1
        let alive = scene.state == .running || scene.state == .paused || scene.state == .celebrating
        let snapshot = RacePacket.Snapshot(
            raceID: raceID, seq: sendSeq,
            elapsed: Float(scene.elapsed), distance: Float(scene.distance),
            speed: Float(scene.state == .running ? scene.runSpeed : 0),
            x: Float(scene.playerX), y: Float(scene.playerY),
            alive: alive, sliding: scene.slideTimer > 0, jumping: scene.playerY > 0.001,
            paused: scene.state == .paused,
            lane: Int8(clamping: scene.laneIndex), spools: UInt16(clamping: scene.spools))
        send(.state(snapshot))
    }

    /// Called from the scene when this phone's run ends (finish, caught, or out of hearts).
    func runEnded(_ stats: RunStats, caught: Bool, finished: Bool) {
        let ending: RacePacket.Result.Ending = finished ? .finished : (caught ? .caught : .outOfHearts)
        let result = RacePacket.Result(raceID: raceID, ending: ending, elapsed: Float(stats.elapsed),
                                       distance: Float(stats.distance), spools: UInt16(clamping: stats.spools),
                                       score: Int32(clamping: stats.score))
        myResult = result
        phase = .ended
        send(.finish(result))
        // The results card is drawn right after this, so it picks up the verdict without a redraw.
        refreshVerdict(notify: false)
    }

    private func refreshVerdict(notify: Bool = true) {
        guard !verdict.isDecided, let scene else { return }
        let next: RaceVerdict
        if let m = myResult, let t = opponentResult {
            next = RaceVerdict.judge(mine: m, theirs: t)
        } else if myResult == nil, let t = opponentResult, !t.finished, scene.state != .over,
                  scene.elapsed > Double(t.elapsed) + RaceVerdict.sameMoment {
            // They were caught and you're still going: you'll outlast them whatever happens next.
            next = .win
        } else if let m = myResult, !m.finished, opponentResult == nil, let s = opponentState, s.alive,
                  Double(s.elapsed) > Double(m.elapsed) + RaceVerdict.sameMoment {
            next = .lose
        } else if opponentLeft {
            next = leftWhileAhead ? .forfeitWin : .noContest
        } else {
            next = .pending
        }
        guard next != verdict else { return }
        verdict = next
        if notify { scene.liveRaceVerdictChanged() }
    }

    // MARK: Rematch

    var canRematch: Bool { phase == .ended && match != nil && !opponentLeft && verdict.isDecided }

    func requestRematch() {
        guard canRematch, !wantsRematch else { return }
        wantsRematch = true
        send(.rematch(raceID: raceID))
        if isHost && opponentWantsRematch { hostStart() }
    }

    // MARK: Sending and receiving

    private func send(_ packet: RacePacket) {
        guard let match else { return }
        do {
            try match.sendData(toAllPlayers: packet.encoded(), with: packet.isReliable ? .reliable : .unreliable)
        } catch {
            // Unreliable state packets are fire-and-forget; a failed reliable send shows up as a disconnect.
        }
    }

    private func received(_ packet: RacePacket) {
        lastHeardAt = now
        switch packet {
        case .hello(let build):
            guard build == RacePacket.build else {
                let name = opponentName
                leave()
                scene?.showLiveRaceStatus("Update needed", detail: "You and \(name) need the same version of Storm Stitch to race.", failed: true)
                return
            }
            opponentSaidHello = true
            if phase == .connecting && isHost && helloSent { hostStart() }
        case .start(let id, let daily, let startAt):
            guard !isHost, phase == .connecting || phase == .ended, id != raceID, daily > 0 else { return }
            begin(raceID: id, daily: Int(daily), startAt: startAt)
        case .state(let snapshot):
            guard snapshot.raceID == raceID else { return }
            if let last = opponentState, Int16(bitPattern: snapshot.seq &- last.seq) <= 0 { return }
            opponentState = snapshot
            opponentStateAt = now
        case .power(let id, let kind):
            guard id == raceID, let power = PowerKind(rawValue: kind) else { return }
            scene?.liveRaceNote("\(opponentName) took \(power.name)")
        case .finish(let result):
            guard result.raceID == raceID, opponentResult == nil else { return }
            opponentResult = result
            refreshVerdict(notify: false)
            scene?.liveRaceOpponentEnded(result)
        case .rematch(let id):
            guard id == raceID, phase == .ended else { return }
            opponentWantsRematch = true
            scene?.liveRaceNote("\(opponentName) wants a rematch!")
            if isHost && wantsRematch { hostStart() }
        case .leave:
            opponentDidLeave()
        }
    }
}

// MARK: Game Center callbacks

extension LiveRace: GKMatchmakerViewControllerDelegate {
    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        DispatchQueue.main.async {
            viewController.dismiss(animated: true)
            if self.phase == .matchmaking { self.phase = .idle }
        }
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        DispatchQueue.main.async {
            viewController.dismiss(animated: true)
            if self.phase == .matchmaking { self.phase = .idle }
            self.scene?.showLiveRaceStatus("Couldn't start the race", detail: "Game Center had a problem. Try again in a moment.", failed: true)
        }
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        DispatchQueue.main.async {
            viewController.dismiss(animated: true)
            self.matchFound(match)
        }
    }
}

extension LiveRace: GKMatchDelegate {
    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let packet = RacePacket.decode(data) else { return }
        DispatchQueue.main.async {
            guard match === self.match else { return }
            self.received(packet)
        }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        DispatchQueue.main.async {
            guard match === self.match else { return }
            switch state {
            case .connected:
                if match.expectedPlayerCount == 0 { self.playersConnected() }
            case .disconnected:
                self.opponentDidLeave()
            default:
                break
            }
        }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        DispatchQueue.main.async {
            guard match === self.match else { return }
            self.opponentDidLeave()
        }
    }

    func match(_ match: GKMatch, shouldReinviteDisconnectedPlayer player: GKPlayer) -> Bool {
        false
    }
}

extension LiveRace: GKLocalPlayerListener {
    /// A friend's invite was accepted (from a notification or the Game Center sheet).
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        DispatchQueue.main.async {
            guard LiveRaceFlags.isOn, self.phase != .countdown, self.phase != .racing else { return }
            self.leave()
            self.present(GKMatchmakerViewController(invite: invite))
        }
    }

    /// The player started a game with friends from the Game Center app.
    func player(_ player: GKPlayer, didRequestMatchWithRecipients recipientPlayers: [GKPlayer]) {
        DispatchQueue.main.async {
            guard LiveRaceFlags.isOn, self.phase != .countdown, self.phase != .racing else { return }
            self.leave()
            let request = GKMatchRequest()
            request.minPlayers = 2
            request.maxPlayers = 2
            request.recipients = Array(recipientPlayers.prefix(1))
            request.inviteMessage = "Race me in Storm Stitch! Same course, live."
            self.present(GKMatchmakerViewController(matchRequest: request))
        }
    }
}

// MARK: Scene side

extension RunScene {

    // MARK: Hooks called from the core game

    /// RunScene.update: once per frame, in every state.
    func stepLiveRace(_ dt: Double) {
        let race = LiveRace.shared
        if race.scene !== self { race.scene = self }
        guard race.phase != .idle else {
            if !race.ghost.isHidden || !race.leadLabel.isHidden {
                race.ghost.isHidden = true
                race.leadLabel.isHidden = true
            }
            return
        }
        race.tick(self, dt: dt)
        renderLiveGhost(dt)
        updateLiveLead(dt)
    }

    /// Gameplay.startRun: the opening banner for a live race.
    var liveRaceBanner: String? {
        guard LiveRace.shared.owns(mode), case .challenge(let storm, _, _) = mode else { return nil }
        return "Race vs \(LiveRace.shared.opponentName)! \(storm.rule.emoji) \(storm.rule.name)"
    }

    /// RunScene.concludeRun: tells the other phone how this run ended.
    func liveRaceRunEnded(caught: Bool, finished: Bool, stars: Int) {
        let race = LiveRace.shared
        guard race.owns(mode), race.phase != .ended else { return }
        race.lastCaught = caught
        race.lastFinished = finished
        race.lastStars = stars
        race.ghost.isHidden = true
        race.leadLabel.isHidden = true
        race.runEnded(stats, caught: caught, finished: finished)
    }

    /// Results card: the race outcome as the title and subtitle.
    func liveRaceResultText() -> (title: String, subtitle: String)? {
        let race = LiveRace.shared
        guard race.owns(mode), race.phase == .ended else { return nil }
        let name = race.opponentName
        let title: String
        switch race.verdict {
        case .pending: title = "Waiting for \(name)..."
        case .win: title = "You beat \(name)!"
        case .lose: title = "\(name) wins!"
        case .draw: title = "Dead heat!"
        case .forfeitWin: title = "You win! \(name) left"
        case .noContest: title = "\(name) left the race"
        }
        let you = "You \(Int(stats.distance).formatted()) m, \(stats.spools) spools"
        let them: String
        if let r = race.opponentResult {
            them = "\(name) \(Int(r.distance).formatted()) m, \(r.spools) spools"
        } else if let s = race.opponentState {
            them = "\(name) \(Int(s.distance).formatted()) m so far"
        } else {
            them = "\(name) didn't get going"
        }
        return (title, "\(you)  ·  \(them)")
    }

    /// Results card: Rematch and Home instead of the solo challenge buttons.
    func liveRaceResultButtons() -> [(String, () -> Void)]? {
        let race = LiveRace.shared
        guard race.owns(mode), race.phase == .ended else { return nil }
        var buttons: [(String, () -> Void)] = []
        if race.canRematch {
            buttons.append((race.opponentWantsRematch ? "Accept rematch" : "Rematch", { [unowned self] in
                guard !LiveRace.shared.wantsRematch else { return }
                LiveRace.shared.requestRematch()
                if !LiveRace.shared.opponentWantsRematch {
                    self.liveRaceNote("Asked \(LiveRace.shared.opponentName) for a rematch")
                }
            }))
        }
        buttons.append(("Home", { [unowned self] in
            LiveRace.shared.leave()
            self.showTitle()
        }))
        return buttons
    }

    /// Daily card: the "Race a Friend" button, just under the card. Hidden unless Game Center is ready.
    func addLiveRaceButton(below card: SKNode, cardHeight: CGFloat) {
        guard LiveRace.isAvailable else { return }
        let button = paperButton("Race a Friend", width: min(220, size.width * 0.6), pulse: false)
        button.position = CGPoint(x: size.width / 2, y: card.position.y - cardHeight / 2 - 46)
        button.zPosition = 12
        overlay.addChild(button)
        onTap(button) { [unowned self] in LiveRace.shared.findOpponent(from: self) }
    }

    // MARK: Screens

    /// A small card while matching, or when something went wrong.
    func showLiveRaceStatus(_ title: String, detail: String, failed: Bool = false) {
        guard state != .running && state != .celebrating else { return }
        state = .menu
        clearScreen()
        hud.removeAllActions()
        hud.alpha = 0
        let w = size.width
        _ = dimBackground {}
        let cardW = min(w - 32, 330)
        let cardH: CGFloat = 220
        let card = paperPanel(width: cardW, height: cardH)
        card.position = CGPoint(x: w / 2, y: size.height * 0.53)
        card.zPosition = 11
        overlay.addChild(card)
        onTap(card) {}
        let top = cardH / 2
        let heading = label(title, size: 22, color: Palette.stitchGold)
        if heading.size.width > cardW - 50 { heading.setScale((cardW - 50) / heading.size.width) }
        heading.position = CGPoint(x: 0, y: top - 44)
        heading.zPosition = 1
        card.addChild(heading)
        let text = paragraph(detail, size: 14, width: cardW - 70, color: Palette.ink)
        text.position = CGPoint(x: 0, y: top - 98)
        text.zPosition = 1
        card.addChild(text)
        let button = paperButton(failed ? "OK" : "Cancel", width: min(160, cardW * 0.5), pulse: false)
        button.position = CGPoint(x: 0, y: -top + 46)
        button.zPosition = 1
        card.addChild(button)
        onTap(button) { [unowned self] in
            LiveRace.shared.leave()
            self.showTitle()
        }
    }

    /// Both phones: build the shared course, freeze it, and count down to the agreed start time.
    func beginLiveRace(startAt: Double) {
        guard let raceMode = LiveRace.shared.raceMode else { return }
        if let presented = GameCenter.topViewController(), presented is GKMatchmakerViewController {
            presented.dismiss(animated: true)
        }
        startRun(raceMode)
        state = .paused
        resumeCountdown = 0
        shownCountdown = 0
        audio.setMusic(playing: false)
        setupLiveGhost()

        // Phones agree on wall-clock time to within a few milliseconds; if this one is way off, start locally.
        var lead = startAt - Date().timeIntervalSince1970
        if lead > 10 || lead < -3 { lead = LiveRace.countdownLead }
        let goAt = Date().timeIntervalSince1970 + lead
        let raceID = LiveRace.shared.raceID
        removeAction(forKey: "liveRaceCountdown")
        run(.sequence([
            .wait(forDuration: max(0, lead - 2.4)),
            .run { [weak self] in
                guard let self, self.state == .paused, self.resumeCountdown <= 0,
                      LiveRace.shared.raceID == raceID, LiveRace.shared.phase == .countdown,
                      self.childNode(withName: "//resume") == nil else { return }
                // The existing resume countdown shows 3, 2, 1, Go and starts the run.
                self.resumeCountdown = max(0.05, min(2.4, goAt - Date().timeIntervalSince1970))
                self.shownCountdown = 0
            }
        ]), withKey: "liveRaceCountdown")
    }

    /// The outcome was settled by time passing (not by a packet): redraw the card, or cheer mid-run.
    func liveRaceVerdictChanged() {
        let race = LiveRace.shared
        if state == .over {
            refreshLiveRaceResults()
        } else if race.verdict == .win {
            liveRaceNote("\(race.opponentName) was caught. You win!", big: true)
        }
    }

    func liveRaceOpponentEnded(_ result: RacePacket.Result) {
        let race = LiveRace.shared
        if state == .over {
            refreshLiveRaceResults()
        } else if race.verdict == .win {
            liveRaceNote("\(race.opponentName) was caught. You win!", big: true)
        } else if result.finished {
            liveRaceNote("\(race.opponentName) crossed the finish!")
        }
    }

    /// Opponent left: you keep running solo, and win if you were ahead.
    func liveRaceOpponentLeft() {
        let race = LiveRace.shared
        if state == .over {
            refreshLiveRaceResults()
        } else if race.verdict == .forfeitWin {
            liveRaceNote("\(race.opponentName) left. You win! Keep running", big: true)
        } else if race.verdict == .noContest {
            liveRaceNote("\(race.opponentName) left the race. Keep running", big: true)
        } else {
            liveRaceNote("\(race.opponentName) left the race")
        }
    }

    /// Redraws the results card with the latest outcome (no unlock banners the second time).
    func refreshLiveRaceResults() {
        let race = LiveRace.shared
        guard state == .over, race.owns(mode) else { return }
        showRunResults(caught: race.lastCaught, finished: race.lastFinished, stars: race.lastStars, unlocks: [])
    }

    func liveRaceNote(_ text: String, big: Bool = false) {
        popText(text, size: big ? 24 : 17, color: big ? Palette.stitchGold : .white,
                at: CGPoint(x: size.width / 2, y: size.height * (big ? 0.64 : 0.72)), rise: 16, life: big ? 2.2 : 1.6,
                parent: state == .over ? overlay : nil)
    }

    // MARK: Ghost and lead

    func setupLiveGhost() {
        let race = LiveRace.shared
        let ghost = race.ghost
        if ghost.parent == nil { objectLayer.addChild(ghost) }
        let id = monster.id
        if let back = illustrated("\(id)-back", width: 100) ?? illustrated("bramble-back", width: 100) {
            ghost.texture = back.texture
            ghost.size = CGSize(width: 85, height: 85 * back.size.height / back.size.width)
        }
        ghost.anchorPoint = CGPoint(x: 0.5, y: 0.02)
        ghost.color = UIColor(hex: 0x7FD1FF)
        ghost.colorBlendFactor = 0.6
        ghost.alpha = 0.5
        ghost.isHidden = true

        let tag = race.ghostTag
        if tag.parent == nil { ghost.addChild(tag) }
        let text = art.text(race.opponentName, size: 20, fill: .white)
        tag.texture = text.texture
        tag.size = text.size
        tag.position = CGPoint(x: 0, y: ghost.size.height + 16)
        tag.zPosition = 1

        race.ghostX = 0
        race.ghostY = 0
        race.leadText = ""
        race.leadTimer = 0
        let lead = race.leadLabel
        if lead.parent == nil { hud.addChild(lead) }
        lead.anchorPoint = CGPoint(x: 0, y: 0.5)
        lead.zPosition = 5
        lead.isHidden = true
    }

    /// The opponent as a translucent, tinted copy of the runner, in their lane, as far ahead or behind as they are.
    func renderLiveGhost(_ dt: Double) {
        let race = LiveRace.shared
        let ghost = race.ghost
        let racing = race.phase == .countdown || race.phase == .racing
        guard racing, state == .running || state == .paused || state == .celebrating,
              let s = race.opponentState, race.opponentResult == nil, !race.opponentLeft else {
            ghost.isHidden = true
            return
        }
        // Fill the gaps between 10 Hz packets by running them forward at their last speed.
        let age = min(0.3, max(0, CACurrentMediaTime() - race.opponentStateAt))
        let theirDistance = Double(s.distance) + (s.alive && !s.paused ? Double(s.speed) * age : 0)
        let z = theirDistance - distance
        guard z > -1.2, z < spawnZ - 2 else {
            ghost.isHidden = true
            return
        }
        let blend = min(1, dt * 12)
        race.ghostX += (Double(s.x) - race.ghostX) * blend
        race.ghostY += (Double(s.y) - race.ghostY) * blend
        let running = s.alive && !s.paused && !s.jumping && !s.sliding
        let bob = running ? abs(sin(clock * 8.5)) * 0.18 : 0
        guard let p = project(x: race.ghostX, z: z, y: race.ghostY + bob) else {
            ghost.isHidden = true
            return
        }
        ghost.isHidden = false
        ghost.position = p.point
        ghost.xScale = p.scale
        ghost.yScale = p.scale * (s.sliding ? 0.6 : 1)
        ghost.zRotation = running ? CGFloat(sin(clock * 8.5)) * 0.08 : 0
        // Just behind your runner when level, so you always see yourself on top.
        ghost.zPosition = CGFloat((spawnZ + 10 - z) * 5) - 1
        // Fade when the two runners overlap, so the ghost never hides you.
        let overlapping = abs(z) < 1.2 && abs(race.ghostX - playerX) < 0.5
        ghost.alpha += ((overlapping ? 0.22 : 0.5) - ghost.alpha) * CGFloat(blend)
    }

    /// A tiny HUD line under the pause button: "You +12 m".
    func updateLiveLead(_ dt: Double) {
        let race = LiveRace.shared
        let lead = race.leadLabel
        let racing = race.phase == .countdown || race.phase == .racing
        guard racing, state == .running || state == .paused || state == .celebrating, lead.parent != nil else {
            lead.isHidden = true
            return
        }
        race.leadTimer -= dt
        guard race.leadTimer <= 0 else { return }
        race.leadTimer = 0.2
        let name = race.opponentName
        var color = UIColor.white
        let text: String
        if race.opponentLeft {
            text = "\(name) left"
        } else if let r = race.opponentResult {
            text = r.finished ? "\(name) finished" : "\(name) was caught"
            color = r.finished ? UIColor(hex: 0xFFB27A) : Palette.stitchGold
        } else if let s = race.opponentState {
            let gap = Int((distance - Double(s.distance)).rounded())
            if gap == 0 {
                text = "Neck and neck"
            } else if gap > 0 {
                text = "You +\(gap) m"
                color = Palette.stitchGold
            } else {
                text = "\(name) +\(-gap) m"
                color = UIColor(hex: 0xFFB27A)
            }
        } else {
            text = "Waiting for \(name)"
        }
        lead.isHidden = false
        lead.position = CGPoint(x: 16, y: size.height - safeTop - 70)
        guard text != race.leadText else { return }
        race.leadText = text
        let textArt = art.text(text, size: 17, fill: color)
        lead.texture = textArt.texture
        lead.size = textArt.size
    }
}
