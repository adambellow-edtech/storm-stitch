import AVFoundation

/// All sound in the vertical slice is synthesized at launch, so there are no audio
/// files to manage yet. Swap in recorded sounds and a composed score later.
final class GameAudio {
    static let shared = GameAudio()

    enum SFX: CaseIterable {
        case jump, land, whoosh, hit, closeCall, stitchFull, gameOver, finish, start, thunder, stitch
        case crack, evilLaugh, defeat
    }

    /// Short musical cues for the end of a run. The music ducks under them while they play.
    enum Sting: CaseIterable {
        case victory, fail
    }

    var musicOn = true {
        didSet { synth.volume = musicOn ? 0.5 : 0 }
    }

    // Recorded score: a calm layer that always plays and a drive layer (drums, accordion, fiddle)
    // that fades in as the storm closes. Both loop together. Falls back to the synth if missing.
    private let songFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private let songBase = AVAudioPlayerNode()
    private let songDrive = AVAudioPlayerNode()
    private var songLoaded = ""
    private var songName = "main"
    private var songWanted = false
    private var songRunning = false
    private var songFade: Float = 0
    private var driveLevel: Float = 0
    private var driveTarget: Float = 0
    private var songTimer: Timer?
    private var songRetry = 0
    private var songCache: (name: String, base: AVAudioPCMBuffer, drive: AVAudioPCMBuffer)?
    private var songLoading = false
    private lazy var hasSong: Bool = Bundle.main.url(forResource: "music-main-base", withExtension: "caf") != nil
    /// The Shredder chase's own song, once `music-chase-base/drive.caf` are in the app.
    private lazy var hasChaseSong: Bool =
        Bundle.main.url(forResource: "music-chase-base", withExtension: "caf") != nil &&
        Bundle.main.url(forResource: "music-chase-drive", withExtension: "caf") != nil
    /// The song the current world or holiday asks for (the chase song takes over during a chase).
    private var themeSong = "main"
    /// True when the current world has no song of its own, so the synth plays it in that world's colors.
    private var worldSynth = false
    /// True during a Shredder chase finale.
    private var chase = false
    /// Whether the game wants music right now; `routeMusic()` decides who plays it.
    private var musicPlaying = false
    /// Ducking under a sting: seconds left, and the eased level the song layers are multiplied by.
    private var duckTimer = 0.0
    private var duckLevel: Float = 1
    private static let duckDepth: Float = 0.25
    var sfxOn = true

    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private let format: AVAudioFormat
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [SFX: AVAudioPCMBuffer] = [:]
    private var stings: [Sting: AVAudioPCMBuffer] = [:]
    private var chimes: [AVAudioPCMBuffer] = []
    private let synth: MusicSynth
    private var started = false
    /// True while the engine is starting in the background; nothing else tries to start it meanwhile.
    private var engineStarting = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        synth = MusicSynth(sampleRate: sampleRate)
    }

    func start() {
        guard !started else { return }
        started = true


        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }

        let synth = self.synth
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let list = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in list {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                synth.render(Int(frameCount), into: data)
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)

        for node in [songBase, songDrive] {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: songFormat)
            node.volume = 0
        }

        buildSounds()
        engine.prepare()

        // Activating the audio session can block for a moment, so it and the engine start run off the
        // main thread. Ambient respects the silent switch and mixes with other audio, like most games.
        // Nothing plays until this finishes (the story score waits for it), so nothing can start under
        // the default category and stop the player's own music.
        engineStarting = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, engine = self.engine] in
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
            DispatchQueue.main.async { self?.engineStarting = false }
        }

        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tickSong() }
        RunLoop.main.add(timer, forMode: .common)
        songTimer = timer
    }

    /// Decodes one song's two layers. Runs off the main thread; touches no shared state.
    private static func decodeSong(_ name: String, format: AVAudioFormat) -> (AVAudioPCMBuffer, AVAudioPCMBuffer)? {
        func read(_ file: String) -> AVAudioPCMBuffer? {
            guard let url = Bundle.main.url(forResource: file, withExtension: "caf"),
                  let audio = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
                  audio.processingFormat.channelCount == 2, audio.processingFormat.sampleRate == 44_100,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.length)) else { return nil }
            do { try audio.read(into: buffer) } catch { return nil }
            return buffer
        }
        guard let base = read("music-\(name)-base"), let drive = read("music-\(name)-drive") else { return nil }
        return (base, drive)
    }

    /// Decodes a song in the background (about 23 MB of audio), then keeps it as the only one in memory.
    private func loadSongInBackground(_ name: String) {
        guard !songLoading else { return }
        songLoading = true
        let format = songFormat
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pair = GameAudio.decodeSong(name, format: format) ?? (name == "main" ? nil : GameAudio.decodeSong("main", format: format))
            DispatchQueue.main.async {
                guard let self else { return }
                self.songLoading = false
                if let pair {
                    self.songCache = (name, pair.0, pair.1)
                } else {
                    // The files wouldn't load: go back to the synthesized music for this session.
                    self.hasSong = false
                    self.routeMusic()
                }
            }
        }
    }

    /// Starts both layers from the top on the same sample so they stay locked together.
    private func startSong(_ cache: (name: String, base: AVAudioPCMBuffer, drive: AVAudioPCMBuffer)) {
        if !engine.isRunning && !engineStarting { try? engine.start() }
        guard engine.isRunning else { return }
        songBase.stop()
        songDrive.stop()
        songBase.scheduleBuffer(cache.base, at: nil, options: .loops, completionHandler: nil)
        songDrive.scheduleBuffer(cache.drive, at: nil, options: .loops, completionHandler: nil)
        let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.08))
        songBase.play(at: start)
        songDrive.play(at: start)
        songLoaded = cache.name
        songRunning = true
    }

    private func stopSong() {
        songBase.stop()
        songDrive.stop()
        songRunning = false
    }

    /// Runs 30 times a second: fades the song in and out, crossfades between versions,
    /// and eases the drive layer toward the current intensity.
    private func tickSong() {
        // Ducking under a sting: dip fast, come back up gently once it has finished.
        if duckTimer > 0 {
            duckTimer -= 1.0 / 30
            if duckTimer <= 0 { synth.duck = 1 }
        }
        let duckWanted: Float = duckTimer > 0 ? GameAudio.duckDepth : 1
        duckLevel += (duckWanted - duckLevel) * (duckWanted < duckLevel ? 0.35 : 0.08)

        guard hasSong else { return }
        // A route change or a phone call stops the engine and the players with it: start again.
        if songRunning && (!engine.isRunning || !songBase.isPlaying) { songRunning = false }
        let wanted = songWanted && musicOn
        let needsSwitch = songRunning && songLoaded != songName

        if wanted && !needsSwitch {
            if !songRunning {
                songRetry -= 1
                if let cache = songCache, cache.name == songName {
                    if songRetry <= 0 {
                        songRetry = 30  // At most one start attempt a second if the engine is unavailable.
                        songFade = 0
                        startSong(cache)
                    }
                } else {
                    loadSongInBackground(songName)
                }
            }
            if songRunning { songFade = min(1, songFade + Float(1.0 / 18)) }
        } else {
            // Fading out: for a pause or game over, or before switching to another version.
            songFade = max(0, songFade - Float(1.0 / 15))
            if needsSwitch && songCache?.name != songName { loadSongInBackground(songName) }
            if songFade == 0 && songRunning && (needsSwitch || !musicOn || synth.playing) {
                // Switch versions (the next tick starts the new one), or stop if music is off or the
                // synth has taken over (a world with no song, or a chase with no chase song).
                // Otherwise the loop keeps going silently, so a pause picks up where it left off.
                stopSong()
            }
        }
        // A chase plays its drive layer at full strength the whole way.
        driveLevel += ((chase ? 1 : driveTarget) - driveLevel) * 0.06
        songBase.volume = songFade * 0.6 * duckLevel
        songDrive.volume = songFade * 0.6 * driveLevel * duckLevel
    }

    // MARK: Playback

    func play(_ sfx: SFX, volume: Float = 1) {
        guard sfxOn, let buffer = buffers[sfx] else { return }
        schedule(buffer, volume: volume)
    }

    /// Spool pickup chime. Each step in a streak plays one note higher.
    func chime(step: Int) {
        guard sfxOn, !chimes.isEmpty else { return }
        schedule(chimes[min(step, chimes.count - 1)], volume: 0.7)
    }

    func setMusic(playing: Bool) {
        musicPlaying = playing
        routeMusic()
    }

    /// Picks who plays the music: the recorded song layers or the synth. The synth covers a world
    /// with no song of its own, a chase with no chase song, and any session where the songs won't load.
    private func routeMusic() {
        let chaseSong = chase && hasChaseSong
        let useSynth = !hasSong || (chase ? !chaseSong : worldSynth)
        songName = chaseSong ? "chase" : themeSong
        synth.chase = chase
        synth.playing = musicPlaying && useSynth
        songWanted = musicPlaying && !useSynth
    }

    /// Switches to the tense chase arrangement for a Shredder chase, and back.
    /// Uses `music-chase-base/drive.caf` when bundled, otherwise the synth's chase mode.
    func setChase(_ on: Bool) {
        guard on != chase else { return }
        chase = on
        routeMusic()
    }

    /// Plays the victory or fail sting and ducks the music under it.
    func playSting(_ sting: Sting, volume: Float = 0.85) {
        guard sfxOn, let buffer = stings[sting] else { return }
        duckTimer = Double(buffer.frameLength) / sampleRate
        synth.duck = GameAudio.duckDepth
        schedule(buffer, volume: volume)
    }

    // MARK: Story score

    private var storyPlayer: AVAudioPlayer?
    private var storyGeneration = 0
    /// False once the story has ended, so a delayed start doesn't play after it.
    private var storyWanted = false
    /// Each story panel lasts this long, and the score is written so each panel is exactly two bars.
    static let storyPanelSeconds: TimeInterval = 5.5

    /// Swaps the looping game music for the story's own score, from the top.
    func startStoryScore() {
        musicPlaying = false
        synth.playing = false
        songWanted = false
        guard musicOn else { return }
        storyWanted = true
        if engineStarting {
            // The audio session is still being set up on first launch: try again in a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.storyWanted else { return }
                self.startStoryScore()
            }
            return
        }
        if storyPlayer == nil, let url = Bundle.main.url(forResource: "story-score", withExtension: "m4a") {
            storyPlayer = try? AVAudioPlayer(contentsOf: url)
            storyPlayer?.prepareToPlay()
        }
        guard let player = storyPlayer else { return }
        storyGeneration += 1
        player.setVolume(0.8, fadeDuration: 0)
        player.currentTime = 0
        player.play()
    }

    /// Keeps the score lined up with the panel on screen when the player taps ahead.
    func cueStoryScore(panel: Int) {
        guard let player = storyPlayer, player.isPlaying else { return }
        let target = Double(panel) * GameAudio.storyPanelSeconds
        if abs(player.currentTime - target) > 0.3 { player.currentTime = target }
    }

    /// Fades the story score out: quickly on Skip, slowly when the story ends so its last chord rings out.
    func stopStoryScore(fade: TimeInterval = 0.4) {
        storyWanted = false
        guard let player = storyPlayer, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: fade)
        let generation = storyGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.05) { [weak self] in
            // Only stop if the story hasn't been started again during the fade.
            guard let self, self.storyGeneration == generation else { return }
            self.storyPlayer?.stop()
        }
    }

    /// Switches the song for a world or a holiday. Each world plays "music-<world>-base/drive.caf"
    /// once those files are in the app. Until then a later world plays the synth in its own colors
    /// (canyon twang, lagoon marimba, peaks koto and taiko), and Notebook Meadow plays its own song.
    func setMusicTheme(_ theme: Theme?) {
        let holiday = theme?.holiday
        synth.theme = holiday == .snow ? 2 : holiday == .harvest ? 1 : 0
        synth.world = 0
        worldSynth = false
        if let holiday {
            themeSong = holiday == .snow ? "winter" : "harvest"
        } else if let key = theme?.key,
                  Bundle.main.url(forResource: "music-\(key)-base", withExtension: "caf") != nil,
                  Bundle.main.url(forResource: "music-\(key)-drive", withExtension: "caf") != nil {
            themeSong = key
        } else {
            themeSong = "main"
            if let key = theme?.key, let flavor = MusicSynth.worldFlavor(key) {
                synth.world = flavor
                worldSynth = true
            }
        }
        routeMusic()
    }

    func setIntensity(_ value: Float) {
        synth.intensity = max(0, min(1, value))
        // The drive layer comes in once a run gets going and is at full strength as the storm closes.
        driveTarget = max(0, min(1, (value - 0.3) / 0.45))
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, volume: Float) {
        guard !players.isEmpty else { return }
        if !engine.isRunning && !engineStarting { try? engine.start() }
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    // MARK: Synthesis

    private func makeBuffer(_ duration: Double, _ generate: (Double) -> Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            channel[i] = max(-1, min(1, generate(Double(i) / sampleRate)))
        }
        return buffer
    }

    private func midi(_ note: Double) -> Double {
        440 * pow(2, (note - 69) / 12)
    }

    private func buildSounds() {
        var noise = NoiseSource()
        let twoPi = 2 * Double.pi

        // Spool chimes on a D major pentatonic scale, rising with the streak.
        for note in [74.0, 76, 78, 81, 83, 86, 88, 90, 93] {
            let f = midi(note)
            if let buffer = makeBuffer(0.45, { t in
                let env = exp(-t * 9)
                return Float((sin(twoPi * f * t) + 0.35 * sin(twoPi * f * 2 * t) + 0.12 * sin(twoPi * f * 3 * t)) * env * 0.5)
            }) {
                chimes.append(buffer)
            }
        }

        var phase = 0.0
        buffers[.jump] = makeBuffer(0.16) { t in
            let f = 300 + 900 * (t / 0.16)
            phase += twoPi * f / self.sampleRate
            let env = pow(1 - t / 0.16, 2)
            return Float(sin(phase) * env * 0.35)
        }

        buffers[.land] = makeBuffer(0.14) { t in
            Float(sin(twoPi * 85 * t) * exp(-t * 32) * 0.6 + noise.next() * exp(-t * 70) * 0.18)
        }

        var lowpass = 0.0
        buffers[.whoosh] = makeBuffer(0.18) { t in
            let cutoff = 0.08 + 0.35 * sin(Double.pi * t / 0.18)
            lowpass += cutoff * (noise.next() - lowpass)
            return Float(lowpass * sin(Double.pi * t / 0.18) * 0.9)
        }

        phase = 0
        buffers[.hit] = makeBuffer(0.4) { t in
            let f = 150 - 100 * min(1, t / 0.3)
            phase += twoPi * f / self.sampleRate
            let crunch = noise.next() * exp(-t * 11) * 0.55
            return Float(crunch + sin(phase) * exp(-t * 9) * 0.6)
        }

        let ccA = midi(81), ccB = midi(88)
        buffers[.closeCall] = makeBuffer(0.5) { t in
            var s = sin(twoPi * ccA * t) * exp(-t * 10)
            if t > 0.08 { s += sin(twoPi * ccB * (t - 0.08)) * exp(-(t - 0.08) * 8) }
            return Float(s * 0.4)
        }

        let arpeggio = [62.0, 66, 69, 74, 78, 81, 86]
        buffers[.stitchFull] = makeBuffer(1.4) { t in
            var s = 0.0
            for (i, note) in arpeggio.enumerated() {
                let start = Double(i) * 0.07
                if t >= start {
                    let local = t - start
                    s += sin(twoPi * self.midi(note) * local) * exp(-local * 3.5)
                }
            }
            return Float(s * 0.18)
        }

        let fall = [72.0, 69, 65, 62]
        buffers[.gameOver] = makeBuffer(1.0) { t in
            let index = min(3, Int(t / 0.18))
            let local = t - Double(index) * 0.18
            let f = self.midi(fall[index])
            let tri = 2 / Double.pi * asin(sin(twoPi * f * t))
            return Float(tri * exp(-local * 5) * 0.35)
        }

        let rise = [67.0, 72, 76, 79]
        buffers[.finish] = makeBuffer(1.2) { t in
            let index = min(3, Int(t / 0.12))
            let local = t - Double(index) * 0.12
            let f = self.midi(rise[index])
            let decay = index == 3 ? exp(-local * 2.5) : exp(-local * 9)
            return Float((sin(twoPi * f * t) + 0.3 * sin(twoPi * f * 2 * t)) * decay * 0.3)
        }

        buffers[.start] = makeBuffer(0.35) { t in
            let rate = 30 + 120 * t
            let gate = sin(twoPi * rate * t) > 0.2 ? 1.0 : 0.15
            return Float(noise.next() * gate * (1 - t / 0.35) * 0.35)
        }

        buffers[.stitch] = makeBuffer(0.22) { t in
            let rate = 90.0
            let gate = sin(twoPi * rate * t) > 0.5 ? 1.0 : 0.0
            return Float(noise.next() * gate * (1 - t / 0.22) * 0.18)
        }

        lowpass = 0
        buffers[.thunder] = makeBuffer(1.6) { t in
            lowpass += 0.025 * (noise.next() - lowpass)
            let env = min(1, t / 0.04) * exp(-t * 2.2)
            return Float(lowpass * env * 4)
        }

        buildStormSounds(noise: &noise)
        buildStings(noise: &noise)
        // Recorded takes win over the synthesized ones when they're bundled.
        if let laugh = loadBuffer("storm-laugh") { buffers[.evilLaugh] = laugh }
        if let defeat = loadBuffer("storm-defeat") { buffers[.defeat] = defeat }
        if let victory = loadBuffer("sting-victory") { stings[.victory] = victory }
        if let fail = loadBuffer("sting-fail") { stings[.fail] = fail }
    }

    /// The end-of-run stings, synthesized like the rest until `sting-victory.caf` / `sting-fail.caf` are bundled.
    private func buildStings(noise: inout NoiseSource) {
        let twoPi = 2 * Double.pi

        // Victory, about 4.4 s in D major: a quick rising run of plucks, each with a little stitch "zip",
        // a brassy ta-ta-taaa fanfare, then a ringing chord with a sparkle of bells and a soft timpani.
        let run: [(start: Double, note: Double)] = [(0.00, 62), (0.07, 66), (0.14, 69), (0.21, 74), (0.28, 78), (0.35, 81)]
        let horns: [(start: Double, note: Double, length: Double)] = [
            (0.50, 74, 0.13), (0.66, 74, 0.13), (0.82, 81, 0.40), (1.26, 78, 0.12), (1.40, 81, 0.12),
            (1.56, 62, 2.4), (1.56, 69, 2.4), (1.56, 74, 2.4), (1.56, 78, 2.4), (1.56, 86, 2.4)
        ]
        let bells: [(start: Double, note: Double)] = [(1.56, 86), (1.62, 90), (1.68, 93), (1.74, 98), (1.86, 102)]
        let brassWeights = [1.0, 0.55, 0.35, 0.2, 0.12]
        let victoryLength = 4.4
        var zipLow = 0.0
        var noiseV = noise
        stings[.victory] = makeBuffer(victoryLength) { t in
            var s = 0.0
            for pluck in run where t >= pluck.start {
                let local = t - pluck.start
                guard local < 0.6 else { continue }
                let f = self.midi(pluck.note)
                s += (sin(twoPi * f * local) + 0.35 * sin(twoPi * f * 2 * local)) * exp(-local * 8) * 0.22
            }
            // Stitch zips: a 25 ms burst of bright noise at each pluck of the run.
            let n = noiseV.next()
            zipLow += 0.3 * (n - zipLow)
            for pluck in run where t >= pluck.start && t < pluck.start + 0.025 {
                s += (n - zipLow) * (1 - (t - pluck.start) / 0.025) * 0.25
            }
            for horn in horns where t >= horn.start && t < horn.start + horn.length + 0.12 {
                let local = t - horn.start
                let attack = min(1, local / 0.025)
                let release = local > horn.length ? max(0, 1 - (local - horn.length) / 0.12) : 1
                let sustain = horn.length > 1 ? 0.75 + 0.25 * exp(-local * 3) : 1
                let vibrato = horn.length > 1 && local > 0.3 ? 1 + 0.004 * sin(twoPi * 5.5 * local) : 1
                let f = self.midi(horn.note) * vibrato
                var tone = 0.0
                for (k, weight) in brassWeights.enumerated() {
                    tone += weight * sin(twoPi * f * Double(k + 1) * local)
                }
                s += tone * attack * release * sustain * (horn.length > 1 ? 0.07 : 0.16)
            }
            for bell in bells where t >= bell.start {
                let local = t - bell.start
                let f = self.midi(bell.note)
                s += (sin(twoPi * f * local) + 0.3 * sin(twoPi * f * 2.76 * local)) * exp(-local * 4) * 0.08
            }
            if t >= 1.56 {
                let local = t - 1.56
                s += sin(twoPi * 73.4 * local) * min(1, local / 0.005) * exp(-local * 3) * 0.35
            }
            let fade = min(1, (victoryLength - t) / 0.3)
            return Float(tanh(s * 1.1) * 0.85 * fade)
        }

        // Fail, 3 s: a sad-trombone "wah, wah, wah, waaah" on a kazoo-ish voice, each note opening like a
        // wah mute, the last one wobbling and drooping, over plucked bass "bonks", then a tiny thread-snap plink.
        let wahs: [(start: Double, note: Double, length: Double)] = [(0.00, 70, 0.30), (0.36, 69, 0.30), (0.72, 68, 0.30), (1.08, 67, 1.45)]
        let failLength = 3.0
        var failPhase = 0.0
        var noiseF = noise
        stings[.fail] = makeBuffer(failLength) { t in
            var s = 0.0
            for (i, wah) in wahs.enumerated() where t >= wah.start && t < wah.start + wah.length + 0.06 {
                let local = t - wah.start
                let last = i == wahs.count - 1
                var note = wah.note
                if last {
                    if local > 0.25 { note += 0.6 * sin(twoPi * 6 * (local - 0.25)) }
                    note -= 0.5 * max(0, (local - 0.65) / 0.8)
                }
                failPhase += self.midi(note) / self.sampleRate
                if failPhase >= 1 { failPhase -= 1 }
                let wahOpen = min(1, local / 0.12)
                let brightness = 0.35 + 0.4 * wahOpen
                var tone = 0.0, weight = 1.0
                for k in 1...6 {
                    tone += weight * sin(twoPi * failPhase * Double(k))
                    weight *= brightness
                }
                let attack = min(1, local / 0.02)
                let release = local > wah.length ? max(0, 1 - (local - wah.length) / 0.06) : 1
                s += tone * attack * release * 0.18
                // A plucked bass "bonk" under each note.
                let f = self.midi(wah.note - 24)
                s += sin(twoPi * f * local) * exp(-local * 10) * 0.35
            }
            if t >= 2.62 {
                let local = t - 2.62
                s += sin(twoPi * 2093 * local) * exp(-local * 30) * 0.2 + noiseF.next() * exp(-local * 200) * 0.15
            }
            let fade = min(1, (failLength - t) / 0.15)
            return Float(tanh(s * 1.1) * 0.85 * fade)
        }
    }

    /// Reads a bundled mono 44.1 kHz CAF into a buffer the players can schedule.
    private func loadBuffer(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let file = try? AVAudioFile(forReading: url),
              file.processingFormat.sampleRate == sampleRate,
              file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            return nil
        }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        return buffer
    }

    /// Lightning crack, the Shredder's laugh and the defeat sting, all synthesized like the rest.
    private func buildStormSounds(noise: inout NoiseSource) {
        let twoPi = 2 * Double.pi
        let sr = sampleRate

        // A close lightning strike: a sharp white snap, a spray of crackles, then a deep rolling boom.
        var snapLow = 0.0, rumble = 0.0, rumble2 = 0.0, crackle = 0.0
        var noiseA = noise
        buffers[.crack] = makeBuffer(1.4) { t in
            let n = noiseA.next()
            snapLow += 0.35 * (n - snapLow)
            let snap = (n - snapLow) * exp(-t * 26) * 1.1
            if noiseA.next() > 0.93 - 0.3 * exp(-t * 6) { crackle = noiseA.next() }
            crackle *= 0.86
            let sparks = crackle * exp(-t * 7) * 0.7
            rumble += 0.018 * (n - rumble)
            rumble2 += 0.006 * (rumble - rumble2)
            let boom = (rumble * 4 + rumble2 * 7) * min(1, t / 0.06) * exp(-t * 1.9)
            return Float(tanh((snap + sparks + boom) * 0.9))
        }

        // The Shredder laughs: six deep "HA"s that sink in pitch, through an "ah" vowel, with a slap echo.
        struct Resonator {
            var a1 = 0.0, a2 = 0.0, gain = 0.0, y1 = 0.0, y2 = 0.0
            init(freq: Double, bandwidth: Double, sampleRate: Double) {
                let r = exp(-Double.pi * bandwidth / sampleRate)
                a1 = 2 * r * cos(2 * Double.pi * freq / sampleRate)
                a2 = -r * r
                gain = 1 - r
            }
            mutating func process(_ x: Double) -> Double {
                let y = gain * x + a1 * y1 + a2 * y2
                y2 = y1
                y1 = y
                return y
            }
        }
        var f1 = Resonator(freq: 700, bandwidth: 110, sampleRate: sr)
        var f2 = Resonator(freq: 1150, bandwidth: 130, sampleRate: sr)
        var f3 = Resonator(freq: 2500, bandwidth: 200, sampleRate: sr)
        var glottal = 0.0, glottalLow = 0.0, breath = 0.0
        var noiseB = noise
        let syllables: [(start: Double, length: Double, pitch: Double)] = [
            (0.00, 0.22, 150), (0.27, 0.22, 140), (0.54, 0.22, 131),
            (0.81, 0.22, 122), (1.08, 0.24, 113), (1.40, 0.70, 104)
        ]
        let laughLength = 2.5
        let echoDelay = Int(0.19 * sr)
        var history = [Double](repeating: 0, count: Int(laughLength * sr) + 1)
        var index = 0
        buffers[.evilLaugh] = makeBuffer(laughLength) { t in
            var voiced = 0.0, aspiration = 0.0, pitch = 110.0
            for syl in syllables where t >= syl.start && t < syl.start + syl.length + 0.05 {
                let local = t - syl.start
                let fall = 1 - 0.12 * local / syl.length
                pitch = syl.pitch * fall
                let attack = min(1, max(0, (local - 0.025) / 0.03))
                let release = max(0, min(1, (syl.length - local) / 0.08 + 0.2))
                voiced = attack * release
                aspiration = max(0, 1 - local / 0.05)
            }
            // Gravelly growl: a little roughness on the pitch.
            let growl = 1 + 0.04 * sin(twoPi * 33 * t)
            glottal += pitch * growl / sr
            if glottal >= 1 { glottal -= 1 }
            let saw = 2 * glottal - 1
            glottalLow += 0.25 * (saw - glottalLow)
            let lowVoice = sin(twoPi * pitch * 0.5 * t) * 0.35
            breath = noiseB.next()
            let source = (glottalLow + lowVoice) * voiced + breath * aspiration * 0.5
            let vowel = f1.process(source) * 1.0 + f2.process(source) * 0.7 + f3.process(source) * 0.3
            var out = vowel * 0.45
            if index >= echoDelay { out += history[index - echoDelay] * 0.32 }
            if index < history.count { history[index] = out }
            index += 1
            return Float(tanh(out * 1.4) * 0.8)
        }

        // Defeat: a slow, sinking minor line on a wheezy organ, then a low chord with a sour tritone.
        let line = [69.0, 68, 67, 66]
        let chord = [38.0, 50, 53, 56]
        buffers[.defeat] = makeBuffer(3.2) { t in
            func organ(_ note: Double, _ time: Double) -> Double {
                let f = self.midi(note)
                let tremolo = 1 + 0.12 * sin(twoPi * 5.5 * time)
                return (sin(twoPi * f * time) + 0.5 * sin(twoPi * f * 2 * time) + 0.25 * sin(twoPi * f * 3 * time)) * tremolo
            }
            var s = 0.0
            let step = 0.34
            let i = Int(t / step)
            if i < line.count {
                let local = t - Double(i) * step
                s += organ(line[i], t) * min(1, local / 0.02) * exp(-local * 2.5) * 0.3
            } else {
                let local = t - Double(line.count) * step
                let env = min(1, local / 0.05) * exp(-local * 1.1)
                for note in chord { s += organ(note, t) * env * 0.16 }
            }
            return Float(tanh(s * 1.2) * 0.85)
        }
    }
}

/// Small white-noise generator.
struct NoiseSource {
    private var state: UInt32 = 0x1234_5678

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Double(state) / Double(UInt32.max) * 2 - 1
    }
}

/// Real-time music: a bouncy D minor groove with a spooky theremin lead.
/// Bass, pizzicato arpeggio, kick and snaps always play; hats and the lead join as intensity rises.
/// A later world with no song file of its own gets its own key and instrument color, and a Shredder
/// chase switches to a faster, darker arrangement. Everything here runs in the real-time render
/// callback: fixed tables and scalar state only, no allocation.
final class MusicSynth {
    /// 0 the usual spooky song, 1 the harvest (Thanksgiving) version, 2 the winter (Christmas) version.
    var theme = 0
    /// The world's color when it has no song file: 0 Notebook Meadow, 1 Cardboard Canyon (twangy pluck,
    /// E minor), 2 Ink Lagoon (bubbly marimba, A minor), 3 Origami Peaks (koto pluck and taiko).
    /// A holiday theme wins over it.
    var world = 0
    /// The Shredder chase arrangement: faster, minor, a pounding low pulse and a menacing lead, all layers in.
    var chase = false
    var playing = false
    var intensity: Float = 0.3
    var volume: Float = 0.5
    /// Music level under a sting (1 is full); eased per sample so it never clicks.
    var duck: Float = 1

    /// The synth flavor for a world id, or nil for one that plays the usual song.
    static func worldFlavor(_ key: String) -> Int? {
        switch key {
        case "canyon": return 1
        case "lagoon": return 2
        case "peaks": return 3
        default: return nil
        }
    }

    private let sr: Float
    private let samplesPerStep: Int
    private let chaseSamplesPerStep: Int
    private var sampleInStep = 0
    private var step = 0
    private var level: Float = 0
    private var duckLevel: Float = 1

    private var bassPhase: Float = 0
    private var bassFreq: Float = 0
    private var bassEnv: Float = 0
    private var bassDecay: Float = 0.99985
    private var arpPhase: Float = 0
    private var arpFreq: Float = 0
    private var arpEnv: Float = 0
    /// Pitch bend right after a pluck: the canyon twang settles down, the marimba blips, the koto rises.
    private var bendEnv: Float = 0
    /// State-variable filter for the canyon twang and the peaks koto.
    private var pluckLow: Float = 0
    private var pluckBand: Float = 0
    private var leadPhase: Float = 0
    private var leadFreq: Float = 0
    private var leadTarget: Float = 0
    private var leadEnv: Float = 0
    private var leadGate = false
    private var leadLow: Float = 0
    private var vibPhase: Float = 0
    private var kickPhase: Float = 0
    private var kickFreq: Float = 0
    private var kickEnv: Float = 0
    private var snapEnv: Float = 0
    private var hatEnv: Float = 0
    private var snapLowpass: Float = 0
    private var noiseState: UInt32 = 0x0BAD_5EED
    private var bellEnv: Float = 0        // winter: sleigh bells
    private var bellHigh: Float = 0
    private var blockEnv: Float = 0       // harvest: woodblock
    private var blockPhase: Float = 0
    private var bubbleEnv: Float = 0      // lagoon: rising bubbles
    private var bubblePhase: Float = 0
    private var bubbleFreq: Float = 0
    private var taikoEnv: Float = 0       // peaks: taiko
    private var taikoPhase: Float = 0
    private var taikoFreq: Float = 0
    private var taikoLow: Float = 0

    /// Bass root per bar (MIDI): D, D, Bb, Bb, G, G, A, A.
    private static let roots = [50, 50, 46, 46, 43, 43, 45, 45]
    private static let thirds = [3, 3, 4, 4, 3, 3, 4, 4]
    /// Bass offsets per 16th step; -99 is a rest.
    private static let bassPattern = [0, -99, -99, 12, -99, -99, 0, -99, 0, -99, 7, -99, 12, -99, 7, -99]
    private static let arpMinor = [12, 15, 19, 24]
    private static let arpMajor = [12, 16, 19, 24]
    /// Winter: D, Bm, G, A, all bright and major-leaning.
    private static let winterRoots = [50, 50, 47, 47, 43, 43, 45, 45]
    private static let winterThirds = [4, 4, 3, 3, 4, 4, 4, 4]
    /// Harvest: a folky D, C, A minor, G turnaround.
    private static let harvestRoots = [50, 50, 48, 48, 45, 45, 43, 45]
    private static let harvestThirds = [4, 4, 4, 4, 3, 3, 4, 4]
    /// Cardboard Canyon: a spaghetti-western E minor, C, D, B.
    private static let canyonRoots = [52, 52, 48, 48, 50, 50, 47, 47]
    private static let canyonThirds = [3, 3, 4, 4, 4, 4, 4, 4]
    /// Ink Lagoon: a surfy A minor, F, G, E.
    private static let lagoonRoots = [45, 45, 41, 41, 43, 43, 40, 40]
    private static let lagoonThirds = [3, 3, 4, 4, 4, 4, 4, 4]
    /// Origami Peaks: the koto picks notes of the D "in" scale (D Eb G A Bb) per 16th; 0 is a rest.
    private static let peaksPattern = [74, 0, 69, 70, 0, 67, 0, 0, 74, 0, 75, 0, 69, 0, 62, 0]
    /// Lead over two bars: 100 fifth, 101 third, 102 root, 103 octave, -1 hold, -99 release.
    private static let leadPattern = [
        100, -1, -1, -1, -1, -1, -1, -1, 101, -1, -1, -1, 102, -1, -1, -1,
        103, -1, -1, -1, -1, -1, 100, -1, 101, -1, -1, -1, -99, -99, -99, -99
    ]
    /// Chase: D minor, Eb (a sinister flat second), Bb, A.
    private static let chaseRoots = [50, 50, 51, 51, 46, 46, 45, 45]
    private static let chaseThirds = [3, 3, 4, 4, 4, 4, 4, 4]
    /// Chase bass: a pounding sixteenth pulse an octave down, with octave kicks.
    private static let chaseBass = [0, 0, 12, 0, 0, 0, 12, 0, 0, 0, 12, 0, 0, 12, 0, 12]
    /// Chase lead over two bars, in semitones above the bar's root: a creeping chromatic riff.
    /// -1 holds, -99 releases.
    private static let chaseLead = [
        0, -1, -1, -1, 1, -1, 0, -1, 7, -1, -1, 6, -1, 5, -1, -1,
        3, -1, -1, -1, 1, -1, 0, -1, -99, -99, 12, -1, 11, -1, 7, -1
    ]

    init(sampleRate: Double) {
        sr = Float(sampleRate)
        let bpm: Float = 112
        samplesPerStep = Int(sr * 60 / bpm / 4)
        let chaseBpm: Float = 138
        chaseSamplesPerStep = Int(sr * 60 / chaseBpm / 4)
    }

    private func freq(_ midi: Int) -> Float {
        440 * powf(2, Float(midi - 69) / 12)
    }

    private func triggerStep() {
        let bar = (step / 16) % 8
        let s = step % 16
        let holiday = theme != 0
        let flavor = holiday ? 0 : world
        let drive: Float = chase ? 1 : intensity

        let root: Int
        let third: Int
        if chase {
            root = MusicSynth.chaseRoots[bar]
            third = MusicSynth.chaseThirds[bar]
        } else if theme == 2 {
            root = MusicSynth.winterRoots[bar]
            third = MusicSynth.winterThirds[bar]
        } else if theme == 1 {
            root = MusicSynth.harvestRoots[bar]
            third = MusicSynth.harvestThirds[bar]
        } else if flavor == 1 {
            root = MusicSynth.canyonRoots[bar]
            third = MusicSynth.canyonThirds[bar]
        } else if flavor == 2 {
            root = MusicSynth.lagoonRoots[bar]
            third = MusicSynth.lagoonThirds[bar]
        } else {
            root = MusicSynth.roots[bar]
            third = MusicSynth.thirds[bar]
        }

        if chase {
            bassFreq = freq(root - 12 + MusicSynth.chaseBass[s])
            bassEnv = 1
            bassDecay = 0.99935
        } else {
            let bass = MusicSynth.bassPattern[s]
            if bass > -99 {
                bassFreq = freq(root + bass)
                bassEnv = 1
            }
            bassDecay = 0.99985
        }

        if flavor == 3 && !chase {
            let note = MusicSynth.peaksPattern[s]
            if note > 0 {
                arpFreq = freq(note)
                arpEnv = 1
                bendEnv = 1
            }
        } else if chase || s % 2 == 0 {
            // The chase runs the arpeggio in sixteenths, accenting the eighths.
            let arp = third == 3 ? MusicSynth.arpMinor : MusicSynth.arpMajor
            let index = chase ? s % 4 : (s / 2) % 4
            arpFreq = freq(root + 12 + arp[index])
            arpEnv = chase && s % 2 == 1 ? 0.6 : 1
            bendEnv = 1
        }

        if chase {
            let code = MusicSynth.chaseLead[step % 32]
            if code >= 0 {
                leadTarget = freq(root + 12 + code)
                if leadFreq == 0 { leadFreq = leadTarget }
                leadGate = true
            } else if code == -99 {
                leadGate = false
            }
        } else if drive > 0.35 {
            let code = MusicSynth.leadPattern[step % 32]
            if code >= 100 {
                let interval: Int
                switch code {
                case 100: interval = 7
                case 101: interval = third
                case 102: interval = 0
                default: interval = 12
                }
                leadTarget = freq(root + 24 + interval)
                if leadFreq == 0 { leadFreq = leadTarget }
                leadGate = true
            } else if code == -99 {
                leadGate = false
            }
        } else {
            leadGate = false
        }

        // Drums. The chase kicks on every beat; Origami Peaks swaps the kick for taiko outside a chase.
        let taiko = flavor == 3
        let kick = chase ? s % 4 == 0 : (!taiko && (s == 0 || s == 8))
        if kick {
            kickEnv = 1
            kickFreq = chase ? 170 : 150
        }
        if taiko && (s == 0 || s == 8 || (!chase && (s == 6 || (drive > 0.5 && (s == 11 || s == 14))))) {
            taikoEnv = 1
            taikoFreq = 125
        }
        if s == 4 || s == 12 {
            snapEnv = 1
        }
        if chase {
            hatEnv = s % 2 == 1 ? 0.7 : 0.35
        } else if s % 2 == 1 && drive > 0.6 {
            hatEnv = 0.6
        }
        if theme == 2 && (s % 2 == 0 || drive > 0.5) {
            // Sleigh bells shake on every eighth, and every sixteenth once the storm is close.
            bellEnv = s % 4 == 0 ? 1 : 0.55
        }
        if theme == 1 && (s == 6 || s == 14 || (s == 10 && drive > 0.5)) {
            blockEnv = 1
            blockPhase = 0
        }
        if flavor == 2 && (s == 3 || s == 11 || (drive > 0.5 && s == 7)) {
            // Ink bubbles rise from a slightly different pitch each time.
            bubbleEnv = 1
            bubblePhase = 0
            bubbleFreq = 520 + Float(noiseState & 255) * 1.6
        }

        step = (step + 1) % 128
    }

    func render(_ frames: Int, into out: UnsafeMutablePointer<Float>) {
        let twoPi: Float = 2 * .pi
        let target: Float = playing ? 1 : 0
        let chasing = chase
        let drive: Float = chasing ? 1 : intensity
        let leadLevel = min(1, drive * 1.4)
        let stepLength = chasing ? chaseSamplesPerStep : samplesPerStep
        let flavor = theme != 0 ? 0 : world
        // How far each world's pluck bends right after it's struck.
        let bend: Float = flavor == 1 ? 0.012 : flavor == 2 ? 0.03 : flavor == 3 ? -0.015 : 0
        let duckTarget = duck

        for i in 0..<frames {
            if sampleInStep == 0 && playing { triggerStep() }
            sampleInStep += 1
            if sampleInStep >= stepLength { sampleInStep = 0 }
            level += (target - level) * 0.0004
            duckLevel += (duckTarget - duckLevel) * 0.0003

            bassPhase += bassFreq / sr
            if bassPhase >= 1 { bassPhase -= 1 }
            let triangle = 4 * abs(bassPhase - 0.5) - 1
            bassEnv *= bassDecay
            var mix = triangle * bassEnv * 0.5
            if chasing {
                // A little square grit makes the low pulse pound.
                mix += (bassPhase < 0.5 ? 0.16 : -0.16) * bassEnv
            }

            bendEnv *= 0.9993
            arpPhase += arpFreq * (1 + bend * bendEnv) / sr
            if arpPhase >= 1 { arpPhase -= 1 }
            if theme == 2 {
                // Glockenspiel: a sine with a bright inharmonic overtone, ringing a little longer.
                let bell = sinf(twoPi * arpPhase) + 0.35 * sinf(twoPi * arpPhase * 3.98)
                arpEnv *= 0.99975
                mix += bell * arpEnv * 0.11
            } else if theme == 1 {
                // Plucked string: a soft triangle that dies away quickly.
                let pluck = 4 * abs(arpPhase - 0.5) - 1
                arpEnv *= 0.99935
                mix += pluck * arpEnv * 0.16
            } else if flavor == 1 {
                // Canyon twang: a saw through a resonant filter that snaps shut, like a bent guitar string.
                let saw = 2 * arpPhase - 1
                let f = twoPi * (400 + 3600 * arpEnv * arpEnv) / sr
                pluckLow += f * pluckBand
                let high = saw - pluckLow - 0.3 * pluckBand
                pluckBand += f * high
                arpEnv *= 0.99945
                mix += pluckLow * arpEnv * 0.13
            } else if flavor == 2 {
                // Lagoon marimba: a round sine with a quick fourth-harmonic knock on the strike.
                let bar = sinf(twoPi * arpPhase) + 0.35 * arpEnv * sinf(twoPi * arpPhase * 4)
                arpEnv *= 0.99925
                mix += bar * arpEnv * 0.15
            } else if flavor == 3 {
                // Peaks koto: a bright filtered pluck that rings, rising into pitch.
                let saw = 2 * arpPhase - 1
                let f = twoPi * (900 + 3600 * arpEnv * arpEnv) / sr
                pluckLow += f * pluckBand
                let high = saw - pluckLow - 0.55 * pluckBand
                pluckBand += f * high
                arpEnv *= 0.9996
                mix += (pluckLow * 0.8 + pluckBand * 0.4) * arpEnv * 0.13
            } else {
                let square: Float = arpPhase < 0.5 ? 1 : -1
                arpEnv *= 0.99955
                mix += square * arpEnv * 0.1
            }

            if chasing {
                // Menacing lead: a darker, filtered saw that slides between notes.
                leadFreq += (leadTarget - leadFreq) * 0.002
                leadPhase += leadFreq / sr
                if leadPhase >= 1 { leadPhase -= 1 }
                leadLow += (2 * leadPhase - 1 - leadLow) * 0.12
                leadEnv += ((leadGate ? 1 : 0) - leadEnv) * 0.002
                mix += leadLow * leadEnv * 0.2
            } else {
                leadFreq += (leadTarget - leadFreq) * 0.0008
                vibPhase += 5.5 / sr
                if vibPhase >= 1 { vibPhase -= 1 }
                let vibrato = 1 + 0.012 * sinf(twoPi * vibPhase)
                leadPhase += leadFreq * vibrato / sr
                if leadPhase >= 1 { leadPhase -= 1 }
                leadEnv += ((leadGate ? 1 : 0) - leadEnv) * 0.0006
                mix += sinf(twoPi * leadPhase) * leadEnv * 0.16 * leadLevel
            }

            if kickEnv > 0.001 {
                kickFreq += (45 - kickFreq) * 0.0012
                kickPhase += kickFreq / sr
                if kickPhase >= 1 { kickPhase -= 1 }
                mix += sinf(twoPi * kickPhase) * kickEnv * 0.55
                kickEnv *= 0.9996
            }

            noiseState ^= noiseState << 13
            noiseState ^= noiseState >> 17
            noiseState ^= noiseState << 5
            let noise = Float(noiseState) / Float(UInt32.max) * 2 - 1

            if snapEnv > 0.001 {
                let high = noise - snapLowpass
                snapLowpass += (noise - snapLowpass) * 0.3
                mix += high * snapEnv * 0.3
                snapEnv *= 0.9992
            }
            if hatEnv > 0.001 {
                mix += noise * hatEnv * 0.05
                hatEnv *= 0.998
            }
            if bellEnv > 0.001 {
                // Bright, jangly noise: high-passed hard so it rings like little bells.
                let jangle = noise - bellHigh
                bellHigh += (noise - bellHigh) * 0.08
                let shimmer = 0.6 + 0.4 * sinf(twoPi * Float(sampleInStep) * 37 / sr)
                mix += jangle * bellEnv * 0.09 * shimmer
                bellEnv *= 0.9993
            }
            if blockEnv > 0.001 {
                blockPhase += 920 / sr
                if blockPhase >= 1 { blockPhase -= 1 }
                mix += sinf(twoPi * blockPhase) * blockEnv * 0.22
                blockEnv *= 0.9975
            }
            if bubbleEnv > 0.001 {
                bubbleFreq *= 1.00012
                bubblePhase += bubbleFreq / sr
                if bubblePhase >= 1 { bubblePhase -= 1 }
                mix += sinf(twoPi * bubblePhase) * bubbleEnv * 0.07
                bubbleEnv *= 0.9992
            }
            if taikoEnv > 0.001 {
                // A deep drum: a falling sine body plus a soft thump of low noise.
                taikoFreq += (58 - taikoFreq) * 0.0006
                taikoPhase += taikoFreq / sr
                if taikoPhase >= 1 { taikoPhase -= 1 }
                taikoLow += (noise - taikoLow) * 0.05
                mix += (sinf(twoPi * taikoPhase) * 0.6 + taikoLow * 1.2) * taikoEnv * 0.55
                taikoEnv *= 0.99965
            }

            out[i] = tanhf(mix * 0.9) * volume * level * duckLevel
        }
    }
}
