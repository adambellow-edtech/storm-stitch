import AVFoundation

/// All sound in the vertical slice is synthesized at launch, so there are no audio
/// files to manage yet. Swap in recorded sounds and a composed score later.
final class GameAudio {
    static let shared = GameAudio()

    enum SFX: CaseIterable {
        case jump, land, whoosh, hit, closeCall, stitchFull, gameOver, finish, start, thunder, stitch
    }

    var musicOn = true {
        didSet { synth.volume = musicOn ? 0.5 : 0 }
    }
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

        buildSounds()
        engine.prepare()
        try? engine.start()
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
        synth.playing = playing
    }

    /// 0 = calm, 1 = full energy. Adds hats and the theremin lead as it rises.
    func setIntensity(_ value: Float) {
        synth.intensity = max(0, min(1, value))
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

    /// Bass root per bar (MIDI): D, D, Bb, Bb, G, G, A, A.
    private static let roots = [50, 50, 46, 46, 43, 43, 45, 45]
    private static let thirds = [3, 3, 4, 4, 3, 3, 4, 4]
    /// Bass offsets per 16th step; -99 is a rest.
    private static let bassPattern = [0, -99, -99, 12, -99, -99, 0, -99, 0, -99, 7, -99, 12, -99, 7, -99]
    private static let arpMinor = [12, 15, 19, 24]
    private static let arpMajor = [12, 16, 19, 24]
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
        let root = MusicSynth.roots[bar]
        let third = MusicSynth.thirds[bar]

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
            let square: Float = arpPhase < 0.5 ? 1 : -1
            arpEnv *= 0.99955
            mix += square * arpEnv * 0.1

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

            out[i] = tanhf(mix * 0.9) * volume * level
        }
    }
}
