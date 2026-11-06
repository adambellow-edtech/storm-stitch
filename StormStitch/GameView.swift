import SwiftUI
import SpriteKit

/// Hosts the run scene plus a live feel-tuning panel (gear button, top left).
struct GameView: View {
    @StateObject private var tuning = Tuning()
    @State private var scene: RunScene?
    @State private var showTuning = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(red: 0.64, green: 0.65, blue: 0.69).ignoresSafeArea()

                if let scene {
                    SpriteView(
                        scene: scene,
                        preferredFramesPerSecond: 120,
                        debugOptions: tuning.showFPS ? [.showsFPS, .showsNodeCount] : []
                    )
                    .ignoresSafeArea()
                }

                #if DEBUG
                // Developer tuning panel: debug builds only, kept small and faint.
                Button {
                    withAnimation(.spring(duration: 0.3)) { showTuning.toggle() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .opacity(0.35)
                }
                .accessibilityLabel("Feel tuning")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 4)
                .padding(.bottom, 8)
                #endif

                if showTuning {
                    TuningPanel(tuning: tuning) {
                        withAnimation(.spring(duration: 0.3)) { showTuning = false }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                if scene == nil {
                    let newScene = RunScene(size: geo.size, tuning: tuning)
                    newScene.scaleMode = .resizeFill
                    scene = newScene
                }
            }
        }
    }
}

struct TuningPanel: View {
    @ObservedObject var tuning: Tuning
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Feel tuning").font(.headline)
                Spacer()
                Button("Reset") { tuning.reset() }
                Button("Done", action: onClose)
                    .bold()
                    .padding(.leading, 12)
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TuneRow(title: "Start speed", value: $tuning.startSpeed, range: 4...20, unit: "u/s")
                    TuneRow(title: "End speed", value: $tuning.endSpeed, range: 6...26, unit: "u/s")
                    TuneRow(title: "Jump strength", value: $tuning.jumpVelocity, range: 3...10)
                    TuneRow(title: "Gravity", value: $tuning.gravity, range: 6...40)
                    TuneRow(title: "Fall multiplier", value: $tuning.fallMultiplier, range: 1...3, unit: "x")
                    TuneRow(title: "Lane switch time", value: $tuning.laneSwitchTime, range: 0.04...0.3, unit: "s")
                    TuneRow(title: "Slide duration", value: $tuning.slideDuration, range: 0.2...1.2, unit: "s")
                    TuneRow(title: "Swipe threshold", value: $tuning.swipeThreshold, range: 8...60, unit: "pt")
                    TuneRow(title: "Rows apart at start", value: $tuning.rowIntervalStart, range: 0.4...1.6, unit: "s")
                    TuneRow(title: "Rows apart at end", value: $tuning.rowIntervalEnd, range: 0.3...1.2, unit: "s")
                    TuneRow(title: "Storm head start", value: $tuning.stormStart, range: 2...12, unit: "u")
                    TuneRow(title: "Storm gain per hit", value: $tuning.stormHitPenalty, range: 0.5...6, unit: "u")
                    TuneRow(title: "Storm fall-back rate", value: $tuning.stormRecoverRate, range: 0...1.5, unit: "u/s")
                    TuneRow(title: "Run length", value: $tuning.runLength, range: 30...180, unit: "s")
                    TuneRow(title: "Power gate 1", value: $tuning.powerGate1, range: 5...170, unit: "s")
                    TuneRow(title: "Power gate 2", value: $tuning.powerGate2, range: 5...170, unit: "s")
                    TuneRow(title: "Power gate 3", value: $tuning.powerGate3, range: 5...170, unit: "s")
                    Toggle("Music", isOn: $tuning.musicOn)
                        .font(.subheadline.weight(.semibold))
                    Toggle("Sound effects", isOn: $tuning.soundOn)
                        .font(.subheadline.weight(.semibold))
                    Toggle("Haptics", isOn: $tuning.hapticsOn)
                        .font(.subheadline.weight(.semibold))
                    Toggle("Show FPS", isOn: $tuning.showFPS)
                        .font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Holiday preview (applies on the next screen)").font(.subheadline.weight(.semibold))
                        Picker("Holiday", selection: $tuning.holidayOverride) {
                            Text("Auto").tag(0)
                            Text("None").tag(1)
                            Text("Harvest").tag(2)
                            Text("Snow").tag(3)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding([.horizontal, .bottom])
            }
        }
        .frame(maxHeight: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

struct TuneRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.2f", value) + (unit.isEmpty ? "" : " \(unit)"))
                    .font(.subheadline)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}
