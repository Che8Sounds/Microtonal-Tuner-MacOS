//  ContentView.swift
//  MicrotunerMacOs
//  Basic tuner UI with real‑time pitch detection (FFT-based)
//  Created by Ghifar on 20.08.25.


#if os(macOS)
import AppKit
#endif
import SwiftUI
import AVFoundation
import Accelerate
import UniformTypeIdentifiers
import Lottie

struct ContentView: View {
    @StateObject private var tuner = Tuner()
    @State private var showSettings = false
    @State private var showSidebar = true
    @State private var showImporter = false
    @State private var showSplash = true
    @State private var splashScaleFG: CGFloat = 1.0
    @State private var showCreateScale = false
    @State private var showLoadScale = false
    @State private var showSaveConflict = false
    @State private var conflictURL: URL? = nil
    @State private var renameText: String = ""

    var body: some View {
        ZStack {
            ZStack(alignment: .trailing) {
                HStack(spacing: 0) {
                    if showSidebar {
                        // Left scale sidebar
                        ScaleSidebar(
                            tuner: tuner,
                            showSaveConflict: $showSaveConflict,
                            conflictURL: $conflictURL,
                            renameText: $renameText
                        )
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

                        // My scales (from saved library)
                        Button("My scales…") { showLoadScale = true }

                        // Custom scale
                        Button("Custom scale…") { showCreateScale = true }

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
            .sheet(isPresented: $showCreateScale) {
                ScaleCreatorSheet(tuner: tuner, isPresented: $showCreateScale)
                    .frame(minWidth: 520, minHeight: 520)
            }
            .sheet(isPresented: $showLoadScale) {
                LoadScaleSheet(tuner: tuner, isPresented: $showLoadScale)
                    .frame(minWidth: 520, minHeight: 520)
            }
            .sheet(isPresented: $showSaveConflict) {
                if let url = conflictURL {
                    SaveConflictSheet(tuner: tuner, existingURL: url, renameText: $renameText, isPresented: $showSaveConflict)
                        .frame(minWidth: 420, minHeight: 200)
                }
            }

            // Splash overlay
            if showSplash {
                ZStack {
                    Color.black.ignoresSafeArea()

                    // Foreground loader
                    GeometryReader { proxy in
                        let side = min(proxy.size.width, proxy.size.height) * 0.5 // base size ~ quarter of screen area
                        LottieView(animation: .named("3D Circle Loader"))
                            .playing(loopMode: .playOnce)
                            .animationSpeed(1.0)
                            .resizable()
                            .scaledToFit()
                            .frame(width: side, height: side)
                            .scaleEffect(splashScaleFG, anchor: .center)
                            .position(x: proxy.size.width/2, y: proxy.size.height/2)
                            .accessibilityLabel("Microtuner animated logo")
                    }
                    .ignoresSafeArea()
                }
                .onAppear {
                    withAnimation(.easeIn(duration: 3.0)) {
                        splashScaleFG = 2.0   // foreground zoom in
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .onAppear {
            tuner.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showSplash = false
                }
            }
        }
    }
}
struct ScaleSidebar: View {
    @ObservedObject var tuner: Tuner
    @Binding var showSaveConflict: Bool
    @Binding var conflictURL: URL?
    @Binding var renameText: String
    @State private var expanded: Bool = true
    @State private var showEditScale = false

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
                HStack(spacing: 8) {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save scale") {
                        guard let proposed = tuner.proposedLibraryURLForCurrentScale() else { return }
                        if FileManager.default.fileExists(atPath: proposed.path) {
                            conflictURL = proposed
                            renameText = proposed.deletingPathExtension().lastPathComponent
                            showSaveConflict = true
                        } else {
                            _ = tuner.saveCurrentScale(to: proposed, overwrite: false)
                        }
                    }
                    .disabled(tuner.scaleStepsCents == nil)
                }
                .padding(.trailing)
            } else {
                Text("No scale loaded")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            DisclosureGroup(isExpanded: $expanded) {
                if let steps = tuner.anchoredStepsCents ?? tuner.scaleStepsCents, !steps.isEmpty {
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
                    if let steps = tuner.anchoredStepsCents ?? tuner.scaleStepsCents { Text("(\(steps.count))").foregroundStyle(.secondary) }
                    Spacer()
                    Button("Edit") { showEditScale = true }
                        .disabled(tuner.scaleStepsCents == nil)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .sheet(isPresented: $showEditScale) {
            ScaleEditorSheet(tuner: tuner, isPresented: $showEditScale)
                .frame(minWidth: 520, minHeight: 520)
        }
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
/// Sheet to create a custom scale by entering step values (cents or ratios like a/b).
struct ScaleCreatorSheet: View {
    @ObservedObject var tuner: Tuner
    @Binding var isPresented: Bool

    @State private var descriptionText: String = "Custom scale"
    @State private var stepTexts: [String] = ["0.0", "100.0", "200.0"]
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Create Scale").font(.title2).bold()
                Spacer()
                Button { isPresented = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            Text("Description")
            TextField("e.g. Custom 13-TET", text: $descriptionText)
                .textFieldStyle(.roundedBorder)

            Divider()

            HStack {
                Text("Steps (cents or ratios like 3/2)").bold()
                Spacer()
                Button(action: addStep) { Label("Add step", systemImage: "plus") }
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(stepTexts.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "%02d", i)).font(.caption).monospacedDigit().frame(width: 28, alignment: .trailing)
                            TextField("value", text: Binding(
                                get: { stepTexts[i] },
                                set: { stepTexts[i] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .help("Examples: 100, 702.0, 3/2, 1.5/1, 100c")

                            Spacer()
                            Button(role: .destructive) {
                                removeStep(at: i)
                            } label: { Image(systemName: "trash") }
                            .disabled(stepTexts.count <= 1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.footnote)
            }

            HStack {
                Button("Reset") { resetPreset() }
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Create") { createScale() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func addStep() { stepTexts.append("") }
    private func removeStep(at index: Int) { if stepTexts.indices.contains(index) { stepTexts.remove(at: index) } }
    private func resetPreset() { stepTexts = ["0.0", "100.0", "200.0"] }

    private func parseToken(_ token: String) -> Double? {
        var t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: ",", with: ".")
        if t.hasSuffix("c") || t.hasSuffix("C") { t.removeLast() }
        if t.contains("/") {
            let parts = t.split(separator: "/", maxSplits: 1).map { String($0) }
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 {
                let ratio = a / b
                return 1200.0 * log2(ratio)
            } else { return nil }
        } else {
            return Double(t)
        }
    }

    private func createScale() {
        errorMessage = nil
        var cents: [Double] = []
        for raw in stepTexts {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            guard let v = parseToken(s) else {
                errorMessage = "Invalid step: \(raw)"
                return
            }
            cents.append(v)
        }

        // Normalize: keep [0,1200), include 0, sort, unique
        var norm = cents.filter { $0 >= 0 && $0 < 1200 }
        if !norm.contains(where: { abs($0 - 0.0) < 1e-6 }) { norm.append(0.0) }
        norm.sort()
        var unique: [Double] = []
        for v in norm {
            if let last = unique.last, abs(v - last) <= 1e-6 { continue }
            unique.append(v)
        }

        guard unique.count >= 2 else {
            errorMessage = "Add at least two distinct steps (0 and one more)."
            return
        }

        tuner.loadScale(description: descriptionText.isEmpty ? "Custom scale" : descriptionText, steps: unique)
        isPresented = false
    }
}

/// Sheet to edit the currently loaded scale (raw cents relative to C, 0≤step<1200)
struct ScaleEditorSheet: View {
    @ObservedObject var tuner: Tuner
    @Binding var isPresented: Bool

    @State private var descriptionText: String = ""
    @State private var stepTexts: [String] = []
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Edit Scale").font(.title2).bold()
                Spacer()
                Button { isPresented = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            Text("Description")
            TextField("Scale description", text: $descriptionText)
                .textFieldStyle(.roundedBorder)

            Divider()

            HStack {
                Text("Steps (cents or ratios like 3/2)").bold()
                Spacer()
                Button(action: addStep) { Label("Add step", systemImage: "plus") }
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(stepTexts.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "%02d", i)).font(.caption).monospacedDigit().frame(width: 28, alignment: .trailing)
                            TextField("value", text: Binding(
                                get: { stepTexts[i] },
                                set: { stepTexts[i] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .help("Examples: 100, 702.0, 3/2, 1.5/1, 100c")

                            Spacer()
                            Button(role: .destructive) { removeStep(at: i) } label: { Image(systemName: "trash") }
                                .disabled(stepTexts.count <= 1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.footnote)
            }

            HStack {
                Button("Revert") { loadFromTuner() }
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save") { saveEdits() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .onAppear { loadFromTuner() }
    }

    private func loadFromTuner() {
        descriptionText = tuner.scaleDescription ?? "Custom scale"
        if let steps = tuner.scaleStepsCents, !steps.isEmpty {
            stepTexts = steps.map { String(format: "%g", $0) }
        } else {
            stepTexts = ["0.0", "100.0", "200.0"]
        }
    }

    private func addStep() { stepTexts.append("") }
    private func removeStep(at index: Int) { if stepTexts.indices.contains(index) { stepTexts.remove(at: index) } }

    private func parseToken(_ token: String) -> Double? {
        var t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: ",", with: ".")
        if t.hasSuffix("c") || t.hasSuffix("C") { t.removeLast() }
        if t.contains("/") {
            let parts = t.split(separator: "/", maxSplits: 1).map { String($0) }
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 {
                let ratio = a / b
                return 1200.0 * log2(ratio)
            } else { return nil }
        } else {
            return Double(t)
        }
    }

    private func saveEdits() {
        errorMessage = nil
        var cents: [Double] = []
        for raw in stepTexts {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            guard let v = parseToken(s) else {
                errorMessage = "Invalid step: \(raw)"
                return
            }
            cents.append(v)
        }

        // Normalize: keep [0,1200), include 0, sort, unique
        var norm = cents.filter { $0 >= 0 && $0 < 1200 }
        if !norm.contains(where: { abs($0 - 0.0) < 1e-6 }) { norm.append(0.0) }
        norm.sort()
        var unique: [Double] = []
        for v in norm {
            if let last = unique.last, abs(v - last) <= 1e-6 { continue }
            unique.append(v)
        }

        guard unique.count >= 2 else {
            errorMessage = "Add at least two distinct steps (0 and one more)."
            return
        }

        tuner.loadScale(description: descriptionText.isEmpty ? "Custom scale" : descriptionText, steps: unique)
        isPresented = false
    }
}

// Settings panel drawer
struct SettingsPanel: View {
    @ObservedObject var tuner: Tuner
    var close: () -> Void
    @State private var a4Text: String = ""
    @State private var a4Error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings").font(.title2).bold()
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }

            Group {
                Text("Sensetivity")
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

            Group {
                Text("A4 Reference (Hz)")
                HStack(spacing: 8) {
                    TextField("e.g. 440.0", text: $a4Text)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onSubmit { applyA4() }
                    Button("Set") { applyA4() }
                        .keyboardShortcut(.return, modifiers: [])
                }
                if let err = a4Error { Text(err).foregroundStyle(.red).font(.footnote) }
                Text(String(format: "Current: %.2f Hz", tuner.a4Reference))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxHeight: .infinity)
        .background(.ultraThickMaterial)
        .onAppear { a4Text = String(format: "%.2f", tuner.a4Reference) }
        .onChange(of: tuner.a4Reference) { newVal in
            a4Text = String(format: "%.2f", newVal)
        }
    }

    private func applyA4() {
        a4Error = nil
        var text = a4Text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            a4Error = "Please enter a frequency in Hz."
            return
        }
        text = text.replacingOccurrences(of: ",", with: ".")
        guard let val = Double(text), val.isFinite, val > 0 else {
            a4Error = "Invalid number. Try 432, 440, 442, etc."
            return
        }
        // Clamp to a reasonable musical range if desired (optional)
        let clamped = max(200.0, min(1000.0, val))
        if clamped != val {
            a4Error = "Clamped to \(String(format: "%.2f", clamped)) Hz (200–1000 Hz)."
        }
        tuner.a4Reference = clamped
        a4Text = String(format: "%.2f", clamped)
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

    /// Helper: Returns the Library/Application Support/Microtuner/Scales directory, creating it if needed.
    private func libraryDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Microtuner/Scales", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Helper: Slugifies a string for use as a filename (alphanumeric, dash, underscore, no spaces).
    func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var result = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: " ", with: "-")
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        return result.isEmpty ? "scale" : result
    }

    func proposedLibraryURLForCurrentScale() -> URL? {
        let desc = (self.scaleDescription?.isEmpty == false) ? self.scaleDescription! : "Custom scale"
        let name = slug(desc)
        return libraryDirectory().appendingPathComponent("\(name).scl")
    }

    @discardableResult
    func saveCurrentScale(to url: URL, overwrite: Bool = false) -> Bool {
        guard let text = generateSCLText() else { return false }
        if !overwrite && FileManager.default.fileExists(atPath: url.path) {
            return false
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            print("Saved scale to \(url.path)")
            return true
        } catch {
            print("Failed to save scale: \(error)")
            return false
        }
    }

    /// Generate a Scala .scl text from the currently loaded scale.
    /// Format:
    ///   <description>\n
    ///   <count>\n
    ///   <step1>\n
    ///   <step2>\n
    ///   ... (values in cents with trailing 'c'), ending with the period as a ratio
    func generateSCLText() -> String? {
        guard let steps = self.scaleStepsCents, !steps.isEmpty else { return nil }
        let desc = (self.scaleDescription?.isEmpty == false) ? self.scaleDescription! : "Custom scale"
        var lines: [String] = []
        lines.append(desc)
        // Count is the number of notes including 1/1, but the list omits the initial 0.000c
        lines.append("\(steps.count)")
        for v in steps where abs(v) > 1e-9 {
            // Write cents with up to 6 decimals and a trailing 'c' per common .scl conventions
            lines.append(String(format: "%.6fc", v))
        }
        // Append the period explicitly as per user preference
        lines.append("2/1")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Save the current scale automatically to the app library folder as a .scl file.
    /// Location: ~/Library/Application Support/Microtuner/Scales/
    func saveCurrentScale() {
        guard let url = proposedLibraryURLForCurrentScale() else { return }
        _ = saveCurrentScale(to: url, overwrite: false)
    }

    struct ScaleRecord: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let description: String
        let stepCount: Int
        let modified: Date?
    }

    func libraryRecords() -> [ScaleRecord] {
        let dir = libraryDirectory()
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        var records: [ScaleRecord] = []
        for u in items where u.pathExtension.lowercased() == "scl" {
            let values = try? u.resourceValues(forKeys: [.contentModificationDateKey])
            if let parsed = Self.parseSCL(at: u) {
                records.append(ScaleRecord(url: u, description: parsed.description, stepCount: parsed.steps.count, modified: values?.contentModificationDate))
            }
        }
        // Sort by most recently modified first
        records.sort { (a, b) in
            switch (a.modified, b.modified) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.description.lowercased() < b.description.lowercased()
            }
        }
        return records
    }

    func loadFromLibrary(_ rec: ScaleRecord) {
        if let parsed = Self.parseSCL(at: rec.url) {
            self.loadScale(description: parsed.description, steps: parsed.steps)
        }
    }

    func deleteFromLibrary(_ rec: ScaleRecord) {
        do {
            try FileManager.default.removeItem(at: rec.url)
            print("Deleted \(rec.url.lastPathComponent)")
        } catch {
            print("Delete failed: \(error)")
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

struct LoadScaleSheet: View {
    @ObservedObject var tuner: Tuner
    @Binding var isPresented: Bool
    @State private var records: [Tuner.ScaleRecord] = []
    @State private var query: String = ""
    @State private var pendingDelete: Tuner.ScaleRecord? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Load Scale").font(.title2).bold()
                Spacer()
                Button { isPresented = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search by name", text: $query)
            }
            .textFieldStyle(.roundedBorder)

            List(filteredRecords, id: \.id) { rec in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.description).font(.body)
                        HStack(spacing: 8) {
                            Text("\(rec.stepCount) steps").font(.caption).foregroundStyle(.secondary)
                            if let d = rec.modified {
                                Text(d.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Spacer()
                    Button("Load") {
                        tuner.loadFromLibrary(rec)
                        isPresented = false
                    }
                    Button(role: .destructive) {
                        pendingDelete = rec
                    } label: {
                        Text("Delete")
                    }
                }
            }

            if records.isEmpty {
                VStack(spacing: 8) {
                    Text("No saved scales found").foregroundStyle(.secondary)
                    Text("Use ‘Save scale’ first.").font(.footnote).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Spacer()
                Button("Refresh") { reload() }
            }
        }
        .padding(16)
        .onAppear { reload() }
        .alert(item: $pendingDelete) { rec in
            Alert(
                title: Text("Delete scale?"),
                message: Text("Are you sure you want to delete \"\(rec.description)\"?"),
                primaryButton: .destructive(Text("Delete")) {
                    tuner.deleteFromLibrary(rec)
                    reload()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var filteredRecords: [Tuner.ScaleRecord] {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return records }
        let q = query.lowercased()
        return records.filter { $0.description.lowercased().contains(q) || $0.url.lastPathComponent.lowercased().contains(q) }
    }

    private func reload() {
        records = tuner.libraryRecords()
    }
}

// SaveConflictSheet view for save name collisions
struct SaveConflictSheet: View {
    @ObservedObject var tuner: Tuner
    let existingURL: URL
    @Binding var renameText: String
    @Binding var isPresented: Bool
    @State private var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A file named ‘\(existingURL.deletingPathExtension().lastPathComponent)’ already exists.")
                .font(.headline)
            Text("Do you want to replace it, or save with a different name?")
                .foregroundStyle(.secondary)

            if let err = error {
                Text(err).foregroundStyle(.red).font(.footnote)
            }

            HStack(spacing: 8) {
                Text("New name:")
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: renameText) { _ in error = nil }
            }

            Spacer()

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Replace", role: .destructive) {
                    _ = tuner.saveCurrentScale(to: existingURL, overwrite: true)
                    isPresented = false
                }
                Button("Rename") {
                    let slug = tuner.slug(renameText)
                    if slug.isEmpty { error = "Please enter a valid name."; return }
                    let newURL = existingURL.deletingLastPathComponent().appendingPathComponent("\(slug).scl")
                    if FileManager.default.fileExists(atPath: newURL.path) {
                        error = "A file with that name already exists."
                        return
                    }
                    _ = tuner.saveCurrentScale(to: newURL, overwrite: false)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}
