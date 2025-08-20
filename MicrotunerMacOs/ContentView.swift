//  ContentView.swift
//  MicrotunerMacOs
//  Basic tuner UI with real‑time pitch detection (FFT-based)
//  Created by Ghifar on 20.08.25.


import SwiftUI
import AVFoundation
import Accelerate
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var tuner = Tuner()
    @State private var showSettings = false
    @State private var showSidebar = true
    @State private var showImporter = false

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                if showSidebar {
                    // Left scale sidebar
                    ScaleSidebar(tuner: tuner)
                        .frame(width: 340)
                        .background(.ultraThinMaterial)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    Divider()
                }

                // Main tuner content
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        // Sidebar toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { showSidebar.toggle() }
                        } label: {
                            Image(systemName: showSidebar ? "sidebar.leading" : "sidebar.leading")
                        }
                        .help(showSidebar ? "Hide scale list" : "Show scale list")

                        // Import .scl
                        Button("Import .scl…") { showImporter = true }

                        Spacer()

                        // Settings
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) { showSettings.toggle() }
                        } label: {
                            Image(systemName: "gearshape")
                                .imageScale(.large)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Microtonal Tuner")
                        .font(.largeTitle)
                        .bold()

                    // Current frequency
                    Text(String(format: "%.2f Hz", tuner.frequency))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("Detected frequency in Hertz")

                    // Absolute note + microtonal/12‑TET detune info
                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(tuner.noteName)
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                            // Show absolute 12‑TET detune right next to the note, integer cents
                            Text(String(format: "%+d", Int(round(tuner.absoluteCents))))
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(colorForCents(tuner.absoluteCents))
                        }
                        .background(
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                // Use representative tallest glyphs to reserve vertical space
                                Text("A♯4")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                Text("+88")
                                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                            .opacity(0)
                        )

                        // When a microtonal scale is loaded, also show deviation to the nearest scale anchor underneath
                        if tuner.scaleStepsCents != nil {
                            // Stabilized step label row (prevents vertical jump when it appears/disappears)
                            ZStack {
                                Text(tuner.stepLabel ?? "00 : A♯ +88")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .opacity(tuner.stepLabel == nil ? 0 : 1)
                            }
                            .background(
                                Text("00 : A♯ +88")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .opacity(0)
                            )

                            Text(String(format: "%+0.1f cents to scale", tuner.cents))
                                .font(.title3)
                                .monospacedDigit()
                                .foregroundStyle(colorForCents(tuner.cents))
                        }
                    }

                    // React/Figma-inspired arc indicator (responsive width)
                    GeometryReader { proxy in
                        // Make the arc span most of the available width, with sensible caps
                        let arcSize = max(360.0, min(Double(proxy.size.width) - 160.0, 960.0))
                        TunerArcIndicator(value: tuner.cents, frequency: tuner.frequency, size: CGFloat(arcSize))
                            .frame(width: proxy.size.width, height: CGFloat(arcSize) * 0.8, alignment: .center)
                    }
                    .frame(minHeight: 260) // ensures we reserve enough height for larger widths
                    .padding(.vertical, 8)

                    HStack(spacing: 12) {
                        Button(tuner.isRunning ? "Stop" : "Start") {
                            tuner.isRunning ? tuner.stop() : tuner.start()
                        }
                        .keyboardShortcut(.space, modifiers: [])
                    }
                }
                .padding(24)
                .onAppear { tuner.start() }
                .onDisappear { tuner.stop() }
            }

            // Right-side settings drawer
            if showSettings {
                SettingsPanel(tuner: tuner, close: { withAnimation(.easeIn(duration: 0.2)) { showSettings = false } })
                    .frame(width: 340)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .shadow(radius: 8)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "scl") ?? .plainText,
                .utf8PlainText,
                .text,
                .plainText,
                .data
            ]
        ) { result in
            switch result {
            case .success(let url):
                print("Importer picked URL: \(url)")
                var success = false
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    success = Tuner.handleSCLImport(url: url, into: tuner)
                } else {
                    success = Tuner.handleSCLImport(url: url, into: tuner)
                }
                if !success {
                    print("Failed to import .scl from \(url)")
                }
            case .failure(let err):
                print("Importer error: \(err)")
            }
        }
    }
}
struct ScaleSidebar: View {
    @ObservedObject var tuner: Tuner
    @State private var expanded: Bool = true

    private let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]

    private func noteLabel(for cents: Double) -> String {
        // Map to nearest 100-cent step relative to selected root
        var c = cents.truncatingRemainder(dividingBy: 1200)
        if c < 0 { c += 1200 }
        let k = Int((c / 100.0).rounded()) // semitone steps from root
        let base = Double(k) * 100.0
        var dev = c - base
        if dev > 600 { dev -= 1200 }
        if dev < -600 { dev += 1200 }
        let idx = (tuner.rootNoteIndex + ((k % 12) + 12) % 12) % 12
        let name = noteNames[idx]
        let sign = dev >= 0 ? "+" : ""
        return "\(name) \(sign)\(String(format: "%.0f", dev))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scale")
                .font(.title3).bold()
                .padding(.top, 16)

            Picker("Root", selection: $tuner.rootNoteIndex) {
                ForEach(0..<noteNames.count, id: \.self) { i in
                    Text(noteNames[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding(.trailing)

            if let description = tuner.scaleDescription {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.trailing)
            } else {
                Text("No scale loaded")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            DisclosureGroup(isExpanded: $expanded) {
                if let steps = tuner.scaleStepsCents, !steps.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(steps.enumerated()), id: \.0) { idx, cents in
                                HStack {
                                    Text(String(format: "%02d", idx))
                                        .font(.caption).monospacedDigit()
                                        .frame(width: 28, alignment: .trailing)
                                    HStack(spacing: 6) {
                                        Text(String(format: "%.3f cents", cents))
                                            .font(.body).monospacedDigit()
                                        Text(noteLabel(for: cents))
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            } label: {
                HStack {
                    Text("Steps")
                    if let steps = tuner.scaleStepsCents { Text("(\(steps.count))").foregroundStyle(.secondary) }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }
}

    private func colorForCents(_ cents: Double) -> Color {
        let absCents = min(abs(cents), 50)
        let t = absCents / 50 // 0..1
        // Green when in tune, trending to red as it drifts
        return Color(hue: 0.33 * (1 - t), saturation: 0.9, brightness: 0.9)
    }

/// A simple discrete meter showing deviation from the nearest note in 10 steps
/// (5 to the left, 5 to the right) with a center neutral slot.
/// A simple discrete meter showing deviation from the nearest note in 10 steps
/// (5 to the left, 5 to the right) with a center neutral slot.
struct StepDeviationMeter: View {
    let cents: Double // expected range roughly -50..+50

    private let stepCountPerSide = 5 // 5 left, 5 right

    var body: some View {
        let clamped = max(-50.0, min(50.0, cents))
        // Map to integer steps of 10 cents: -5 ... +5
        let step = Int((clamped / 10.0).rounded())
        let range = (-stepCountPerSide)...(stepCountPerSide)

        return HStack(spacing: 6) {
            ForEach(Array(range), id: \.self) { i in
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fillColor(for: i, current: step))
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(borderColor(for: i), lineWidth: 1)
                }
                .overlay(
                    Group {
                        if i == 0 {
                            Text("0")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                )
                .frame(width: 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityLabel("Pitch deviation meter in ten steps")
    }

    private func fillColor(for index: Int, current: Int) -> Color {
        if index == current {
            // Active slot color: green near center, red near edges
            let absSteps = min(abs(index), stepCountPerSide)
            let t = Double(absSteps) / Double(stepCountPerSide) // 0..1
            return Color(hue: 0.33 * (1 - t), saturation: 0.9, brightness: 0.9)
        } else if index == 0 {
            return Color.gray.opacity(0.25)
        } else {
            return Color.gray.opacity(0.15)
        }
    }

    private func borderColor(for index: Int) -> Color {
        index == 0 ? .secondary.opacity(0.5) : .secondary.opacity(0.25)
    }
}

/// Figma/React-inspired arc tuner indicator (−50…+50¢ mapped to −45…+45°)
struct TunerArcIndicator: View {
    let value: Double
    let frequency: Double
    let size: CGFloat

    private var clampedValue: Double { max(-50, min(50, value)) }
    private var angleDegrees: Double { (clampedValue / 50.0) * 45.0 }

    private func indicatorColor(for v: Double) -> Color {
        let a = abs(v)
        if a < 5 { return Color(hex: 0x22c55e) }      // green
        if a < 15 { return Color(hex: 0xeab308) }     // yellow
        if a < 30 { return Color(hex: 0xf97316) }     // orange
        return Color(hex: 0xef4444)                   // red
    }

    var body: some View {
        let radius = size * 0.35
        let center = CGPoint(x: size/2, y: size * 0.6)
        let arcStrokeWidth: CGFloat = 8

        ZStack {
            // Main SVG area size
            ZStack {
                // Main silver arc (−45°..+45°)
                Arc(startAngle: .degrees(-45), endAngle: .degrees(45), radius: radius, center: center)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: 0xe5e7eb), Color(hex: 0x9ca3af), Color(hex: 0x6b7280)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: arcStrokeWidth, lineCap: .round)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)

                // Tick marks and labels every 10¢
                ForEach(Array(stride(from: -50, through: 50, by: 10)), id: \.self) { i in
                    let tickAngle = Angle.degrees(Double(i) / 50.0 * 45.0)
                    let start = point(on: center, radius: radius + 15, angle: tickAngle)
                    let end   = point(on: center, radius: radius + 25, angle: tickAngle)
                    let label = point(on: center, radius: radius + 35, angle: tickAngle)

                    // Tick line
                    Path { p in
                        p.move(to: start)
                        p.addLine(to: end)
                    }
                    .stroke(i == 0 ? Color(hex: 0x22c55e) : Color(hex: 0x6b7280), lineWidth: i == 0 ? 2 : 1)

                    // Label
                    Text("\(i)")
                        .font(.system(size: 11))
                        .fontWeight(i == 0 ? .semibold : .regular)
                        .foregroundStyle(i == 0 ? Color(hex: 0x22c55e) : Color(hex: 0x6b7280))
                        .position(label)
                }

                // Center point indicator
                Circle()
                    .fill(Color(hex: 0x9ca3af))
                    .overlay(Circle().stroke(Color(hex: 0x6b7280), lineWidth: 1))
                    .frame(width: 8, height: 8)
                    .position(center)

                // Moving indicator circle
                Circle()
                    .fill(indicatorColor(for: clampedValue))
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .frame(width: 32, height: 32)
                    .shadow(radius: 6, y: 3)
                    .position(point(on: center, radius: radius, angle: .degrees(angleDegrees)))
                    .animation(.interpolatingSpring(mass: 0.5, stiffness: 150, damping: 20), value: clampedValue)
            }
            .frame(width: size, height: size * 0.8)

            // Center display (frequency + cents chip)
            VStack(spacing: 6) {
                Text(String(format: "%.1f Hz", frequency))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x2563eb)) // blue-600

                Text(String(format: "%@%d¢", clampedValue >= 0 ? "+" : "", Int(round(clampedValue))))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill((abs(clampedValue) < 5) ? Color(hex: 0x22c55e).opacity(0.1) : .white.opacity(0.9))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    )
                    .foregroundStyle(indicatorColor(for: clampedValue))
                    .animation(.easeInOut(duration: 0.3), value: clampedValue)
            }
            .offset(y: size * 0.05)

            // Flat & sharp labels
            HStack {
                Text("♭").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("♯").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(width: size, height: size * 0.8, alignment: .bottom)
        }
        .frame(width: size, height: size * 0.8)
    }

    // Utility: convert polar to cartesian around arbitrary center
    private func point(on center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        let rad = CGFloat(angle.radians)
        return CGPoint(
            x: center.x + sin(rad) * radius,
            y: center.y - cos(rad) * radius
        )
    }
}

/// Simple arc segment from start to end angles around a center and radius
struct Arc: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let radius: CGFloat
    let center: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: center, radius: radius, startAngle: startAngle - .degrees(90), endAngle: endAngle - .degrees(90), clockwise: false)
        return p
    }
}

// Small utility to allow hex colors like in Tailwind
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self = Color(red: r, green: g, blue: b, opacity: alpha)
    }
}
// Settings panel drawer
struct SettingsPanel: View {
    @ObservedObject var tuner: Tuner
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings").font(.title2).bold()
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }

            Group {
                Text("Smoothing")
                Slider(value: Binding(get: { tuner.smoothingAlpha }, set: { tuner.smoothingAlpha = $0 }), in: 0.05...0.5)
                Text(String(format: "%.2f", tuner.smoothingAlpha)).monospacedDigit().foregroundStyle(.secondary)
            }

            Group {
                Text("Threshold")
                Slider(value: Binding(get: { tuner.thresholdDB }, set: { tuner.thresholdDB = $0 }), in: -90...0)
                Text(String(format: "%.0f dB", tuner.thresholdDB)).monospacedDigit().foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 8)

            if let desc = tuner.scaleDescription, let count = tuner.scaleStepsCents?.count {
                Text("Loaded scale: \(desc) (") + Text("\(count)").monospacedDigit() + Text(" steps)")
            } else {
                Text("No scale loaded")
                    .foregroundStyle(.secondary)
            }

            Button("Calibrate A4 = \(Int(tuner.a4Reference)) Hz") { tuner.cycleA4() }
                .help("Cycle A4 reference among 438/440/442 Hz")

            Spacer()
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .background(.ultraThickMaterial)
    }
}

// MARK: - Tuner Engine
final class Tuner: NSObject, ObservableObject {
    // Published values for UI
    @Published var frequency: Double = 0
    @Published var noteName: String = "–"
    @Published var cents: Double = 0
    @Published var absoluteCents: Double = 0
    @Published var isRunning: Bool = false
    @Published var stepLabel: String? = nil

    // Calibration (A4 reference).
    @Published var a4Reference: Double = 440

    // Microtuning scale (Scala .scl)
    @Published var scaleDescription: String? = nil
    /// Raw steps as parsed from the .scl (in cents, relative to C; includes 0, excludes 1200; sorted)
    @Published var scaleStepsCents: [Double]? = nil
    /// Steps re-anchored to the selected root so that **step 0 is exactly the root (0¢)**
    @Published var anchoredStepsCents: [Double]? = nil
    /// Selected root note as a 12-TET index (0=C … 11=B). Changing this **recomputes anchors**.
    @Published var rootNoteIndex: Int = 9 { // default A
        didSet { recomputeAnchors() }
    }
    
    /// Recompute the list of anchor points relative to the selected root.
    /// If raw steps are relative to C, we shift by `rootNoteIndex*100¢`, wrap to [0,1200),
    /// then translate so the smallest becomes 0, and sort. This guarantees step 0 == root.
    private func recomputeAnchors() {
        guard var steps = scaleStepsCents, !steps.isEmpty else {
            anchoredStepsCents = nil
            return
        }
        let rootOffset = Double(rootNoteIndex) * 100.0 // cents from C to root in 12-TET

        // Shift steps by −rootOffset, wrap to [0,1200)
        var shifted = steps.map { v -> Double in
            var x = v - rootOffset
            x = x.truncatingRemainder(dividingBy: 1200)
            if x < 0 { x += 1200 }
            return x
        }

        // Translate so the first anchor is exactly 0 and sort ascending
        if let minVal = shifted.min() {
            shifted = shifted.map { v in
                var x = v - minVal
                if x < 0 { x += 1200 }
                return x
            }
        }
        shifted.sort()
        anchoredStepsCents = shifted
    }

    // Input level threshold (dBFS). Pitch is computed only when level ≥ threshold.
    @Published var thresholdDB: Double = -50 // range ~ -90..0 dBFS
    private let eps: Double = 1e-12

    private let engine = AVAudioEngine()
    private var sampleRate: Double = 44100

    // FFT
    private let fftSize: Int = 4096
    private let hopSize: Int = 2048
    private var fftSetup: OpaquePointer?
    private var window: [Float] = []
    private var inReal: [Float]
    private var inImag: [Float]
    private var outReal: [Float]
    private var outImag: [Float]

    // Smoothing (one‑pole low‑pass / EMA)
    private var emaInitialized = false
    private var freqEMA: Double = 0
    private var centsEMA: Double = 0        // EMA for scale or 12‑TET (depending on mode)
    private var absCentsEMA: Double = 0     // EMA for absolute 12‑TET detune
    /// 0 < smoothingAlpha ≤ 1.0 (smaller = smoother). Try 0.12–0.2
    var smoothingAlpha: Double = 0.15

    override init() {
        inReal = .init(repeating: 0, count: fftSize)
        inImag = .init(repeating: 0, count: fftSize)
        outReal = .init(repeating: 0, count: fftSize)
        outImag = .init(repeating: 0, count: fftSize)
        super.init()
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), vDSP_DFT_Direction.FORWARD)
    }

    func start() {
        guard !isRunning else { return }
        do {
            try configureSession()
            try startEngine()
            isRunning = true
        } catch {
            print("Tuner start error: \(error)")
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func configureSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        sampleRate = session.sampleRate
        #else
        // macOS uses AVAudioEngine without AVAudioSession
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        sampleRate = inputFormat.sampleRate
        #endif
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(hopSize), format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        if frameCount == 0 { return }

        // Copy and (if needed) truncate/zero-pad to fftSize
        var x = [Float](repeating: 0, count: fftSize)
        let n = min(frameCount, fftSize)
        for i in 0..<n { x[i] = channel[i] }

        // Compute input RMS level (dBFS)
        var meanSquare: Float = 0
        vDSP_measqv(x, 1, &meanSquare, vDSP_Length(n))
        let rms = sqrt(meanSquare)
        let levelDB = 20.0 * log10(Double(rms) + eps)

        // Gate: if below threshold, clear UI and skip pitch detection
        if levelDB < thresholdDB {
            DispatchQueue.main.async { [weak self] in
                self?.frequency = 0
                self?.noteName = "–"
                self?.stepLabel = nil
                self?.cents = 0
                self?.absoluteCents = 0
            }
            return
        }

        // Remove DC & apply Hann window
        var mean: Float = 0
        vDSP_meanv(x, 1, &mean, vDSP_Length(n))
        vDSP_vsadd(x, 1, [-mean], &x, 1, vDSP_Length(n))
        vDSP_vmul(x, 1, window, 1, &x, 1, vDSP_Length(fftSize))

        // Real -> complex input
        inReal = x
        inImag.withUnsafeMutableBufferPointer { imagPtr in
            imagPtr.initialize(repeating: 0)
        }

        // FFT
        if let setup = fftSetup {
            vDSP_DFT_Execute(setup, inReal, inImag, &outReal, &outImag)
        }

        // Magnitude spectrum
        var mags = [Float](repeating: 0, count: fftSize/2)
        for i in 0..<(fftSize/2) {
            let re = outReal[i]
            let im = outImag[i]
            mags[i] = sqrt(re * re + im * im)
        }

        // Ignore very low bins (< 50 Hz) and hum bins (around 50/60Hz)
        let minFreq: Float = 50
        let minBin = max(1, Int((minFreq / Float(sampleRate)) * Float(fftSize)))

        // Peak picking
        var maxMag: Float = 0
        var maxIndex: Int = minBin
        for i in minBin..<(fftSize/2 - 1) {
            if mags[i] > maxMag { maxMag = mags[i]; maxIndex = i }
        }

        // Parabolic interpolation for sub-bin accuracy
        let i0 = max(1, min(maxIndex, fftSize/2 - 2))
        let alpha = mags[i0 - 1]
        let beta  = mags[i0]
        let gamma = mags[i0 + 1]
        let p = 0.5 * (alpha - gamma) / (alpha - 2*beta + gamma + 1e-12)
        let peakIndex = Double(i0) + Double(p)

        let freq = peakIndex * (sampleRate / Double(fftSize))
        updatePitch(frequency: freq.isFinite ? freq : 0)
    }

    private func updatePitch(frequency f: Double) {
        guard f > 20, f.isFinite else { return }

        // Map frequency to nearest 12‑TET note using current A4 reference
        let midi = 69.0 + 12.0 * log2(f / a4Reference)
        let nearest = round(midi)
        let refFreq = a4Reference * pow(2.0, (nearest - 69.0)/12.0)
        let cents12 = 1200.0 * log2(f / refFreq)

        var displayCents = cents12
        let absoluteName = Self.noteName(forMIDINote: Int(nearest))
        var microStepLabel: String? = nil

        if let anchors = anchoredStepsCents, !anchors.isEmpty {
            // Compute cents relative to **root**; wrap to [0,1200)
            let centsFromA4 = 1200.0 * log2(f / a4Reference)
            let centsFromC  = centsFromA4 + 900.0              // A is +900¢ above C
            var wrappedC    = centsFromC.truncatingRemainder(dividingBy: 1200)
            if wrappedC < 0 { wrappedC += 1200 }
            let rootOffset  = Double(rootNoteIndex) * 100.0
            var wrappedFromRoot = (wrappedC - rootOffset).truncatingRemainder(dividingBy: 1200)
            if wrappedFromRoot < 0 { wrappedFromRoot += 1200 }

            // Nearest anchor (anchors already 0-based with step 0 at root)
            var bestIdx = 0
            var bestDelta = Double.greatestFiniteMagnitude
            for (i, s) in anchors.enumerated() {
                let d = wrappedFromRoot - s
                let alt = d > 600 ? d - 1200 : (d < -600 ? d + 1200 : d)
                if abs(alt) < abs(bestDelta) { bestDelta = alt; bestIdx = i }
            }
            displayCents = bestDelta

            // Root-relative naming for the step label
            let names = ["C","C♯","D","D♯","E","F","F♯","G","G♯","A","A♯","B"]
            let stepCents = anchors[bestIdx]
            let k = Int((stepCents / 100.0).rounded())               // nearest semitone offset from root
            let baseCents = Double(k) * 100.0
            var stepDev = stepCents - baseCents                      // fixed deviation of the step
            if stepDev > 50 { stepDev -= 100 }
            if stepDev < -50 { stepDev += 100 }
            let nameIdx = (rootNoteIndex + ((k % 12) + 12) % 12) % 12
            let centsInt = Int(round(stepDev))
            let stepStr = String(format: "%02d", bestIdx)
            let signPart = centsInt >= 0 ? "+\(centsInt)" : "\(centsInt)"
            microStepLabel = "\(stepStr) : \(names[nameIdx]) \(signPart)"
        }

        // --- Smooth frequency & cents with an exponential moving average ---
        if !emaInitialized {
            freqEMA = f
            centsEMA = displayCents
            absCentsEMA = cents12
            emaInitialized = true
        } else {
            let a = max(0.01, min(1.0, smoothingAlpha))
            freqEMA = (1 - a) * freqEMA + a * f
            centsEMA = (1 - a) * centsEMA + a * displayCents
            absCentsEMA = (1 - a) * absCentsEMA + a * cents12
        }

        let clampedCents = max(-50, min(50, centsEMA))
        let clampedAbs   = max(-50, min(50, absCentsEMA))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.frequency = self.freqEMA
            self.noteName = absoluteName
            self.absoluteCents = clampedAbs          // always publish absolute 12‑TET detune
            self.cents = clampedCents                // scale detune if scale loaded, else 12‑TET detune
            self.stepLabel = (self.scaleStepsCents?.isEmpty == false) ? microStepLabel : nil
        }
    }

    func loadScale(description: String, steps: [Double]) {
        DispatchQueue.main.async {
            self.scaleDescription = description
            self.scaleStepsCents = steps
            self.recomputeAnchors()
        }
    }

    func clearScale() {
        DispatchQueue.main.async {
            self.scaleDescription = nil
            self.scaleStepsCents = nil
            self.anchoredStepsCents = nil
        }
    }

    static func readText(from url: URL) -> String? {
        // Try common encodings first
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16LittleEndian,
            .utf16BigEndian,
            .unicode,
            .isoLatin1,
            .macOSRoman
        ]
        for enc in encodings {
            if let s = try? String(contentsOf: url, encoding: enc) { return s }
        }
        // Fallback via Data
        if let data = try? Data(contentsOf: url) {
            for enc in encodings {
                if let s = String(data: data, encoding: enc) { return s }
            }
        }
        return nil
    }

    static func parseSCL(at url: URL) -> (description: String, steps: [Double])? {
        guard var text = readText(from: url) else { return nil }
        // Normalize newlines and remove BOM if present
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")

        let rawLines = text.components(separatedBy: "\n")
        var idx = 0

        func nextNonComment() -> String? {
            while idx < rawLines.count {
                var line = rawLines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                idx += 1
                if line.isEmpty { continue }
                if line.first == "!" { continue }
                // strip inline comments starting with ! or ;
                if let bang = line.firstIndex(of: "!") { line = String(line[..<bang]) }
                if let semi = line.firstIndex(of: ";") { line = String(line[..<semi]) }
                line = line.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                return line
            }
            return nil
        }

        // Per Scala format: first **non-comment** line is description
        guard let desc = nextNonComment() else { return nil }

        // Next non-comment line is the count (integer)
        guard let rawCount = nextNonComment() else { return nil }
        var countCore = rawCount
        if let excl = countCore.firstIndex(of: "!") { countCore = String(countCore[..<excl]) }
        if let sc = countCore.firstIndex(of: ";") { countCore = String(countCore[..<sc]) }
        countCore = countCore.trimmingCharacters(in: .whitespaces)
        guard let count = Int(countCore.components(separatedBy: .whitespaces).first ?? countCore) else { return nil }

        var steps: [Double] = []
        while steps.count < count, let line = nextNonComment() {
            var core = line
            // tolerate commas as decimal separators
            core = core.replacingOccurrences(of: ",", with: ".")
            // Remove trailing tokens again just in case
            if let excl = core.firstIndex(of: "!") { core = String(core[..<excl]) }
            if let sc = core.firstIndex(of: ";") { core = String(core[..<sc]) }
            core = core.trimmingCharacters(in: .whitespaces)
            if core.isEmpty { continue }

            if core.contains("/") {
                // ratio a/b
                let parts = core.split(separator: "/", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 {
                    let ratio = a / b
                    let cents = 1200.0 * log2(ratio)
                    steps.append(cents)
                }
            } else {
                // could be like "100.0c" or "100.0"
                var token = core
                if let space = token.firstIndex(of: " ") { token = String(token[..<space]) }
                token = token.replacingOccurrences(of: "c", with: "")
                if let cents = Double(token) { steps.append(cents) }
            }
        }

        // Normalize to intra-octave steps: include 0, exclude 1200. Ensure sorted & unique.
        var norm = steps.filter { $0 >= 0.0 && $0 < 1200.0 }
        if !norm.contains(where: { abs($0 - 0.0) < 1e-6 }) { norm.append(0.0) }
        norm.sort()
        var unique: [Double] = []
        for v in norm {
            if let last = unique.last, abs(v - last) <= 1e-6 { continue }
            unique.append(v)
        }
        steps = unique
        print("Parsed SCL: \(desc) — steps (incl. 0): \(steps.count)")
        return (description: desc, steps: steps)
    }

    static func handleSCLImport(url: URL, into tuner: Tuner) -> Bool {
        var released = false
        var success = false
        if url.startAccessingSecurityScopedResource() {
            released = true
        }
        defer { if released { url.stopAccessingSecurityScopedResource() } }

        if let parsed = parseSCL(at: url) {
            tuner.loadScale(description: parsed.description, steps: parsed.steps)
            success = true
        } else if let data = try? Data(contentsOf: url) {
            // Try UTF-8 text fallback via temp URL
            if let text = String(data: data, encoding: .utf8) {
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".scl")
                do { try text.write(to: tmp, atomically: true, encoding: .utf8) } catch { }
                if let parsed = parseSCL(at: tmp) {
                    tuner.loadScale(description: parsed.description, steps: parsed.steps)
                    success = true
                }
            }
        }
        return success
    }

    func cycleA4() {
        // Simple toggle set (you can extend to custom input later)
        let options: [Double] = [438, 440, 442]
        if let idx = options.firstIndex(of: a4Reference) {
            a4Reference = options[(idx + 1) % options.count]
        } else {
            a4Reference = 440
        }
    }

    private static func noteName(forMIDINote n: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let name = names[(n % 12 + 12) % 12]
        let octave = n/12 - 1
        return "\(name)\(octave)"
    }
}

#Preview {
    ContentView()
}
