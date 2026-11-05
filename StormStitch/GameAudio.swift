import AVFoundation

/// All sound in the vertical slice is synthesized at launch, so there are no audio
/// files to manage yet. Swap in recorded sounds and a composed score later.
final class GameAudio {
    static let shared = GameAudio()

    enum SFX: CaseIterable {
        case jump, land, whoosh, hit, closeCall, stitchFull, gameOver, finish, start, thunder, stitch
        case crack, evilLaugh, defeat
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
    private lazy var hasSong: Bool = Bundle.main.url(forResource: "music-main-base", withExtension: "caf") != nil
    var sfxOn = true

    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private let format: AVAudioFormat
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [SFX: AVAudioPCMBuffer] = [:]
    private var chimes: [AVAudioPCMBuffer] = []
    private let synth: MusicSynth
    private var started = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        synth = MusicSynth(sampleRate: sampleRate)
    }

    func start() {
        guard !started else { return }
        started = true

        // Ambient respects the silent switch and mixes with other audio, like most games.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

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
        try? engine.start()

        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tickSong() }
        RunLoop.main.add(timer, forMode: .common)
        songTimer = timer
    }

    private func loadSong(_ name: String) -> (AVAudioPCMBuffer, AVAudioPCMBuffer)? {
        if let cache = songCache, cache.name == name { return (cache.base, cache.drive) }
        func read(_ file: String) -> AVAudioPCMBuffer? {
            guard let url = Bundle.main.url(forResource: file, withExtension: "caf"),
                  let audio = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
                  audio.processingFormat.channelCount == 2, audio.processingFormat.sampleRate == 44_100,
                  let buffer = AVAudioPCMBuffer(pcmFormat: songFormat, frameCapacity: AVAudioFrameCount(audio.length)) else { return nil }
            do { try audio.read(into: buffer) } catch { return nil }
            return buffer
        }
        guard let base = read("music-\(name)-base"), let drive = read("music-\(name)-drive") else { return nil }
        songCache = (name, base, drive)  // Keep only the current song in memory.
        return (base, drive)
    }

    /// Starts both layers from the top on the same sample so they stay locked together.
    private func startSong() {
        guard let pair = loadSong(songName) ?? (songName == "main" ? nil : loadSong("main")) else {
            // The files wouldn't load: go back to the synthesized music for this session.
            hasSong = false
            synth.playing = songWanted
            return
        }
        let (base, drive) = pair
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        songBase.stop()
        songDrive.stop()
        songBase.scheduleBuffer(base, at: nil, options: .loops, completionHandler: nil)
        songDrive.scheduleBuffer(drive, at: nil, options: .loops, completionHandler: nil)
        let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.08))
        songBase.play(at: start)
        songDrive.play(at: start)
        songLoaded = songName
        songRunning = true
    }

    private func stopSong() {
        songBase.stop()
        songDrive.stop()
        songRunning = false
    }

    /// Fades the song in and out and eases the drive layer toward the current intensity.
    private func tickSong() {
        guard hasSong else { return }
        if songWanted && musicOn {
            songRetry -= 1
            if (!songRunning || songLoaded != songName) && songRetry <= 0 {
                songRetry = 30  // At most one start attempt a second if the engine is unavailable.
                songFade = 0
                startSong()
            }
            songFade = min(1, songFade + Float(1.0 / 18))
        } else {
            songFade = max(0, songFade - Float(1.0 / 15))
            if songFade == 0 && songRunning { stopSong() }
        }
        driveLevel += (driveTarget - driveLevel) * 0.06
        songBase.volume = songFade * 0.6
        songDrive.volume = songFade * 0.6 * driveLevel
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
        if hasSong {
            synth.playing = false
            songWanted = playing
        } else {
            synth.playing = playing
        }
    }

    // MARK: Story score

    private var storyPlayer: AVAudioPlayer?
    private var storyGeneration = 0
    /// Each story panel lasts this long, and the score is written so each panel is exactly two bars.
    static let storyPanelSeconds: TimeInterval = 5.5

    /// Swaps the looping game music for the story's own score, from the top.
    func startStoryScore() {
        synth.playing = false
        songWanted = false
        guard musicOn else { return }
        if storyPlayer == nil, let url = Bundle.main.url(forResource: "story-score", withExtension: "m4a") {
            storyPlayer = try? AVAudioPlayer(contentsOf: url)
            storyPlayer?.prepareToPlay()
        }
        guard let player = storyPlayer else { return }
        storyGeneration += 1
        player.volume = 0.8
        player.currentTime = 0
        player.play()
    }

    /// Keeps the score lined up with the panel on screen when the player taps ahead.
    func cueStoryScore(panel: Int) {
        guard let player = storyPlayer, player.isPlaying else { return }
        let target = Double(panel) * GameAudio.storyPanelSeconds
        if abs(player.currentTime - target) > 0.3 { player.currentTime = target }
    }

    func stopStoryScore() {
        guard let player = storyPlayer, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: 0.4)
        let generation = storyGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            // Only stop if the story hasn't been started again during the fade.
            guard let self, self.storyGeneration == generation else { return }
            self.storyPlayer?.stop()
        }
    }

    /// Switches the song to its holiday version (or back).
    func setMusicTheme(_ holiday: Holiday?) {
        synth.theme = holiday == .snow ? 2 : holiday == .harvest ? 1 : 0
        songName = holiday == .snow ? "winter" : holiday == .harvest ? "harvest" : "main"
    }

    func setIntensity(_ value: Float) {
        synth.intensity = max(0, min(1, value))
        // The drive layer comes in once a run gets going and is at full strength as the storm closes.
        driveTarget = max(0, min(1, (value - 0.3) / 0.45))
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, volume: Float) {
        guard !players.isEmpty else { return }
        if !engine.isRunning { try? engine.start() }
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
        // Recorded takes win over the synthesized ones when they're bundled.
        if let laugh = loadBuffer("storm-laugh") { buffers[.evilLaugh] = laugh }
        if let defeat = loadBuffer("storm-defeat") { buffers[.defeat] = defeat }
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
final class MusicSynth {
    /// 0 the usual spooky song, 1 the harvest (Thanksgiving) version, 2 the winter (Christmas) version.
    var theme = 0
    var playing = false
    var intensity: Float = 0.3
    var volume: Float = 0.5

    private let sr: Float
    private let samplesPerStep: Int
    private var sampleInStep = 0
    private var step = 0
    private var level: Float = 0

    private var bassPhase: Float = 0
    private var bassFreq: Float = 0
    private var bassEnv: Float = 0
    private var arpPhase: Float = 0
    private var arpFreq: Float = 0
    private var arpEnv: Float = 0
    private var leadPhase: Float = 0
    private var leadFreq: Float = 0
    private var leadTarget: Float = 0
    private var leadEnv: Float = 0
    private var leadGate = false
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
    /// Lead over two bars: 100 fifth, 101 third, 102 root, 103 octave, -1 hold, -99 release.
    private static let leadPattern = [
        100, -1, -1, -1, -1, -1, -1, -1, 101, -1, -1, -1, 102, -1, -1, -1,
        103, -1, -1, -1, -1, -1, 100, -1, 101, -1, -1, -1, -99, -99, -99, -99
    ]

    init(sampleRate: Double) {
        sr = Float(sampleRate)
        let bpm: Float = 112
        samplesPerStep = Int(sr * 60 / bpm / 4)
    }

    private func freq(_ midi: Int) -> Float {
        440 * powf(2, Float(midi - 69) / 12)
    }

    private func triggerStep() {
        let bar = (step / 16) % 8
        let s = step % 16
        let root = theme == 2 ? MusicSynth.winterRoots[bar] : theme == 1 ? MusicSynth.harvestRoots[bar] : MusicSynth.roots[bar]
        let third = theme == 2 ? MusicSynth.winterThirds[bar] : theme == 1 ? MusicSynth.harvestThirds[bar] : MusicSynth.thirds[bar]

        let bass = MusicSynth.bassPattern[s]
        if bass > -99 {
            bassFreq = freq(root + bass)
            bassEnv = 1
        }

        if s % 2 == 0 {
            let arp = third == 3 ? MusicSynth.arpMinor : MusicSynth.arpMajor
            arpFreq = freq(root + 12 + arp[(s / 2) % 4])
            arpEnv = 1
        }

        let code = MusicSynth.leadPattern[step % 32]
        if intensity > 0.35 {
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

        if s == 0 || s == 8 {
            kickEnv = 1
            kickFreq = 150
        }
        if s == 4 || s == 12 {
            snapEnv = 1
        }
        if s % 2 == 1 && intensity > 0.6 {
            hatEnv = 0.6
        }
        if theme == 2 && (s % 2 == 0 || intensity > 0.5) {
            // Sleigh bells shake on every eighth, and every sixteenth once the storm is close.
            bellEnv = s % 4 == 0 ? 1 : 0.55
        }
        if theme == 1 && (s == 6 || s == 14 || (s == 10 && intensity > 0.5)) {
            blockEnv = 1
            blockPhase = 0
        }

        step = (step + 1) % 128
    }

    func render(_ frames: Int, into out: UnsafeMutablePointer<Float>) {
        let twoPi: Float = 2 * .pi
        let target: Float = playing ? 1 : 0
        let leadLevel = min(1, intensity * 1.4)

        for i in 0..<frames {
            if sampleInStep == 0 && playing { triggerStep() }
            sampleInStep += 1
            if sampleInStep >= samplesPerStep { sampleInStep = 0 }
            level += (target - level) * 0.0004

            bassPhase += bassFreq / sr
            if bassPhase >= 1 { bassPhase -= 1 }
            let triangle = 4 * abs(bassPhase - 0.5) - 1
            bassEnv *= 0.99985
            var mix = triangle * bassEnv * 0.5

            arpPhase += arpFreq / sr
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
            } else {
                let square: Float = arpPhase < 0.5 ? 1 : -1
                arpEnv *= 0.99955
                mix += square * arpEnv * 0.1
            }

            leadFreq += (leadTarget - leadFreq) * 0.0008
            vibPhase += 5.5 / sr
            if vibPhase >= 1 { vibPhase -= 1 }
            let vibrato = 1 + 0.012 * sinf(twoPi * vibPhase)
            leadPhase += leadFreq * vibrato / sr
            if leadPhase >= 1 { leadPhase -= 1 }
            leadEnv += ((leadGate ? 1 : 0) - leadEnv) * 0.0006
            mix += sinf(twoPi * leadPhase) * leadEnv * 0.16 * leadLevel

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

            out[i] = tanhf(mix * 0.9) * volume * level
        }
    }
}
