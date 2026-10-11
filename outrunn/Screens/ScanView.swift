//
//  ScanView.swift
//  outrunn
//
//  Presage SmartSpectra camera scan. Saves vitals only, never video.
//

import SmartSpectra
import SwiftUI

struct ScanView: View {
    var store: Store
    var coach: Coach
    var minutesSinceWorkout: Int
    var onFinished: () -> Void

    private enum TraceWindow {
        static let rate = 120
        static let arterialWaveform = 240
        static let breathingWaveform = 180
    }

    @Bindable private var sdk = SmartSpectraSDK.shared

    @Environment(\.dismiss) private var dismiss
    @State private var startError: String?
    @State private var isSaving = false
    @State private var pulseRateBuffer: [MeasurementWithConfidence] = []
    @State private var breathingRateBuffer: [MeasurementWithConfidence] = []
    @State private var arterialPressureBuffer: [MeasurementWithConfidence] = []
    @State private var chestBuffer: [SmartSpectra.Measurement] = []
    @State private var abdomenBuffer: [SmartSpectra.Measurement] = []
    @State private var latestHrv: Hrv?

    private enum WaveformProminence {
        case primary
        case secondary
    }

    private var metrics: Metrics? { sdk.metrics }

    private var metricsUpdateToken: Int64 {
        [
            metrics?.cardio.pulseRate.last?.timestamp,
            metrics?.breathing.rate.last?.timestamp,
            metrics?.cardio.arterialPressureTrace.last?.timestamp,
            metrics?.breathing.upperTrace.last?.timestamp,
            metrics?.breathing.lowerTrace.last?.timestamp,
            metrics?.cardio.hrv.last?.timestamp
        ]
        .compactMap { $0 }
        .max() ?? 0
    }

    private var latestPulse: MeasurementWithConfidence? {
        pulseRateBuffer.last ?? sdk.metrics?.cardio.pulseRate.last
    }

    private var latestBreathing: MeasurementWithConfidence? {
        breathingRateBuffer.last ?? sdk.metrics?.breathing.rate.last
    }

    private var displayedHrv: Hrv? {
        latestHrv ?? sdk.metrics?.cardio.hrv.last
    }

    private var pulseRateText: String {
        formatMetric(latestPulse.map { Double($0.value) }, digits: 0, suffix: " bpm")
    }

    private var breathingRateText: String {
        formatMetric(latestBreathing.map { Double($0.value) }, digits: 0, suffix: " bpm")
    }

    private var hrvText: String {
        guard let value = displayedHrv?.rmssd, value > 0 else { return "--" }
        return formatMetric(value, digits: 1, suffix: " ms")
    }

    private var pulseConfidenceColor: Color {
        confidenceColor(latestPulse?.confidence)
    }

    private var breathingConfidenceColor: Color {
        confidenceColor(latestBreathing?.confidence)
    }

    private var arterialPressureSamples: [Double] {
        let buffered = arterialPressureBuffer.map { Double($0.value) }
        if buffered.count > 1 { return buffered }
        return (sdk.metrics?.cardio.arterialPressureTrace ?? []).map { Double($0.value) }
    }

    private var chestSamples: [Double] {
        chestBuffer.map { Double($0.value) }
    }

    private var abdomenSamples: [Double] {
        abdomenBuffer.map { Double($0.value) }
    }

    private var statusText: String {
        switch sdk.processingStatus {
        case .idle: return "Idle"
        case .starting: return "Starting"
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .error: return "Error"
        @unknown default: return "Unknown"
        }
    }

    private var validationTitle: String {
        guard let validationStatus = sdk.validationStatus else { return "Waiting" }
        return validationName(validationStatus.code)
    }

    private var statusColor: Color {
        switch sdk.processingStatus {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .error: return .red
        case .idle: return .gray
        @unknown default: return .gray
        }
    }

    private var validationColor: Color {
        guard let validationStatus = sdk.validationStatus else { return .gray }
        switch validationStatus.code {
        case .ok: return .green
        case .cameraTuning: return .orange
        default: return .yellow
        }
    }

    private var isTransitioning: Bool {
        sdk.processingStatus == .starting || sdk.processingStatus == .stopping
    }

    private var startStopTitle: String {
        switch sdk.processingStatus {
        case .running: return "Stop"
        case .starting: return "Starting"
        case .stopping: return "Stopping"
        default: return "Start"
        }
    }

    private var previewPlaceholderText: String {
        if startError != nil { return startError ?? "Camera unavailable" }
        switch sdk.processingStatus {
        case .starting: return "Starting camera…"
        case .running: return "Waiting for camera frames…"
        default: return "Tap Start to open the camera"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            statusBar(compact: true)

            if let startError {
                Text(startError)
                    .font(Neu.label(12))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            ScrollView {
                VStack(spacing: 12) {
                    previewCard
                        .frame(height: 280)

                    Text(healthContextText)
                        .font(Neu.body(11))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        metricCard(
                            title: "Pulse Rate",
                            value: pulseRateText,
                            valueColor: pulseConfidenceColor,
                            accent: .red,
                            compact: true
                        )
                        metricCard(
                            title: "Breathing Rate",
                            value: breathingRateText,
                            valueColor: breathingConfidenceColor,
                            accent: .cyan,
                            compact: true
                        )
                    }
                    .frame(height: 86)

                    metricCard(
                        title: "HRV RMSSD",
                        value: hrvText,
                        valueColor: .white,
                        accent: .mint,
                        compact: true
                    )
                    .frame(height: 86)

                    waveformCard(
                        title: "Arterial Pressure",
                        samples: arterialPressureSamples,
                        accent: .purple,
                        compact: true,
                        prominence: .primary
                    )
                    .frame(height: 140)

                    HStack(spacing: 12) {
                        waveformCard(
                            title: "Chest Waveform",
                            samples: chestSamples,
                            accent: .cyan,
                            compact: true,
                            prominence: .secondary
                        )
                        waveformCard(
                            title: "Abdomen Waveform",
                            samples: abdomenSamples,
                            accent: .blue,
                            compact: true,
                            prominence: .secondary
                        )
                    }
                    .frame(height: 120)

                    Text("Keep face and upper chest visible and still. Pulse ~12s, breathing ~30s, HRV ~60s. Tap Stop to save vitals and return to Today. Video is not stored.")
                        .font(Neu.body(11))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .background(backgroundGradient.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            await store.refreshHealth()
            await startMeasurement()
        }
        .task(id: metricsUpdateToken) {
            mergeCurrentMetrics()
        }
        .onDisappear {
            Task { try? await sdk.stop() }
        }
    }

    private var previewCard: some View {
        ZStack {
            if let image = sdk.imageOutput {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.16, green: 0.24, blue: 0.46), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Image(systemName: "camera.viewfinder")
                        .font(Neu.number(40))
                    Text(previewPlaceholderText)
                        .font(Neu.heading(17))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .foregroundStyle(.white.opacity(0.92))
            }

            LinearGradient(
                colors: [.black.opacity(0.68), .black.opacity(0.12), .clear],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }

    private func statusBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            Button("Cancel") {
                Task {
                    try? await sdk.stop()
                    onFinished()
                    dismiss()
                }
            }
            .font(Neu.label(12))
            .foregroundStyle(.white)

            badge(title: "Status", value: statusText, color: statusColor)
            badge(title: "Validation", value: validationTitle, color: validationColor)

            Spacer(minLength: 4)

            Button(action: {
                if sdk.processingStatus == .running {
                    saveAndReturn()
                } else {
                    toggleMeasurement()
                }
            }) {
                Text(isSaving ? "Saving" : startStopTitle)
                    .font(Neu.label(12))
                    .padding(.horizontal, compact ? 12 : 16)
                    .padding(.vertical, 8)
                    .background(sdk.processingStatus == .running ? Neu.accent : .white, in: Capsule())
                    .foregroundStyle(.black)
            }
            .disabled(isTransitioning || isSaving)
        }
    }

    private func metricCard(
        title: String,
        value: String,
        valueColor: Color,
        accent: Color,
        compact: Bool,
        monospacedValue: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(Neu.label(12))
                    .foregroundStyle(.white)
            }

            Text(value)
                .font(
                    monospacedValue
                        ? .system(size: compact ? 21 : 24, weight: .semibold, design: .monospaced)
                        : Neu.number(compact ? 21 : 24)
                )
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .presageDashboardCard()
    }

    private func waveformCard(
        title: String,
        samples: [Double],
        accent: Color,
        compact: Bool,
        prominence: WaveformProminence
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Text(title)
                .font(Neu.label(12))
                .foregroundStyle(.white)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.12))

                if samples.count > 1 {
                    PresageWaveformView(
                        samples: samples,
                        strokeColor: accent,
                        verticalPaddingFraction: prominence == .primary ? 0.14 : 0.08
                    )
                    .padding(prominence == .primary ? 8 : 10)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.3), lineWidth: 1)
            )
        }
        .presageDashboardCard()
    }

    private func badge(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(title): \(value)")
                .font(Neu.label(12))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.white.opacity(0.12), in: Capsule())
        .foregroundStyle(.white)
    }

    private func mergeCurrentMetrics() {
        guard let metrics else { return }

        if !metrics.cardio.pulseRate.isEmpty {
            pulseRateBuffer.appendProtoArray(contentsOf: metrics.cardio.pulseRate)
            pulseRateBuffer = Array(pulseRateBuffer.suffix(TraceWindow.rate))
        }

        if !metrics.breathing.rate.isEmpty {
            breathingRateBuffer.appendProtoArray(contentsOf: metrics.breathing.rate)
            breathingRateBuffer = Array(breathingRateBuffer.suffix(TraceWindow.rate))
        }

        if !metrics.cardio.arterialPressureTrace.isEmpty {
            arterialPressureBuffer.appendProtoArray(contentsOf: metrics.cardio.arterialPressureTrace)
            arterialPressureBuffer = Array(arterialPressureBuffer.suffix(TraceWindow.arterialWaveform))
        }

        if !metrics.breathing.upperTrace.isEmpty {
            chestBuffer.appendProtoArray(contentsOf: metrics.breathing.upperTrace)
            chestBuffer = Array(chestBuffer.suffix(TraceWindow.breathingWaveform))
        }

        if !metrics.breathing.lowerTrace.isEmpty {
            abdomenBuffer.appendProtoArray(contentsOf: metrics.breathing.lowerTrace)
            abdomenBuffer = Array(abdomenBuffer.suffix(TraceWindow.breathingWaveform))
        }

        if let hrv = metrics.cardio.hrv.last {
            latestHrv = hrv
        }
    }

    private func resetBuffers() {
        pulseRateBuffer.removeAll(keepingCapacity: true)
        breathingRateBuffer.removeAll(keepingCapacity: true)
        arterialPressureBuffer.removeAll(keepingCapacity: true)
        chestBuffer.removeAll(keepingCapacity: true)
        abdomenBuffer.removeAll(keepingCapacity: true)
        latestHrv = nil
    }

    private var healthContextText: String {
        guard let health = store.data.health else {
            return "Turn on Apple Health in Settings to add sleep, steps, HRV, and heart rate recovery to this scan."
        }
        var parts: [String] = []
        if let hours = health.sleepHours { parts.append(String(format: "sleep %.1f h", hours)) }
        if let steps = health.stepCount { parts.append("\(steps) steps") }
        if let sdnn = health.hrvSDNN { parts.append(String(format: "HRV %.0f ms", sdnn)) }
        return "Apple Health: " + parts.joined(separator: ", ")
            + ". These are kept separate from the camera scan."
    }

    private func toggleMeasurement() {
        Task {
            switch sdk.processingStatus {
            case .running:
                saveAndReturn()
            case .idle, .error:
                await startMeasurement()
            default:
                break
            }
        }
    }

    private func startMeasurement() async {
        startError = nil
        ScanService.configure(sdk)

        guard !ScanService.apiKey.isEmpty else {
            startError = "Missing SmartSpectra API key."
            return
        }

        let cameraAllowed = await ScanService.ensureCameraAccess()
        guard cameraAllowed else {
            startError = "Camera access is required. Enable it in Settings → outrunn → Camera, then tap Start."
            return
        }

        switch sdk.processingStatus {
        case .running, .starting:
            return
        case .stopping:
            try? await sdk.stop()
        default:
            break
        }

        resetBuffers()
        do {
            try await sdk.start()
        } catch {
            startError = error.localizedDescription
        }
    }

    private func stopMeasurement() async {
        do {
            try await sdk.stop()
        } catch {
            startError = error.localizedDescription
        }
    }

    /// Saves only what the camera actually measured. With no pulse or
    /// breathing reading there is nothing to save, so the scan keeps running.
    private func saveAndReturn() {
        guard !isSaving else { return }
        mergeCurrentMetrics()

        guard let pulse = latestPulse, let breathing = latestBreathing else {
            startError = "No pulse and breathing reading yet. Hold still a little longer, then tap Stop."
            return
        }
        isSaving = true
        startError = nil

        let heartRate = Int(Double(pulse.value).rounded())
        let respiratoryRate = Double(breathing.value)
        let confidence = min(100, max(0, Double(pulse.confidence)))
        let rmssd = displayedHrv.flatMap { $0.rmssd > 0 ? Double($0.rmssd) : nil }
        let stressIndex = displayedHrv.flatMap { hrv -> Double? in
            hrv.baevsky.isFinite && hrv.baevsky > 0 ? Double(hrv.baevsky) : nil
        }

        Task {
            await stopMeasurement()
            await store.refreshHealth()
            // Persist vitals only. Never write camera frames or video to disk.
            store.addScan(
                Scan(
                    minutesSinceWorkout: minutesSinceWorkout,
                    heartRate: heartRate,
                    respiratoryRate: respiratoryRate,
                    pulseConfidence: confidence,
                    heartRateRecovery: AgeEngine.heartRateRecovery(
                        peak: store.data.health?.peakHeartRate,
                        current: heartRate,
                        minutesSinceWorkout: minutesSinceWorkout
                    ),
                    rmssd: rmssd,
                    stressIndex: stressIndex
                )
            )
            isSaving = false
            onFinished()
            dismiss()
            await coach.refreshPlan()
        }
    }

    private func confidenceColor(_ confidence: Float?) -> Color {
        guard let confidence, confidence.isFinite else { return .white.opacity(0.65) }
        let percent = min(max(Double(confidence), 0), 100)
        switch percent {
        case 85...:
            return .green
        case 60..<85:
            return .yellow
        default:
            return .red
        }
    }

    private func formatMetric(_ value: Double?, digits: Int = 0, suffix: String = "") -> String {
        guard let value else { return "--" }
        if digits == 0 {
            return "\(Int(value.rounded()))\(suffix)"
        }
        return String(format: "%.\(digits)f", value) + suffix
    }

    private func validationName(_ code: ValidationCode) -> String {
        switch code {
        case .ok: return "OK"
        case .noFaceFound: return "No Face"
        case .multipleFacesFound: return "Multi Face"
        case .faceNotCentered: return "Off Center"
        case .faceSizeOutOfRange: return "Face Size"
        case .tooDark: return "Too Dark"
        case .tooBright: return "Too Bright"
        case .chestNotVisible: return "Chest Missing"
        case .cameraTuning: return "Tuning"
        @unknown default: return "Unknown"
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.05, blue: 0.12),
                Color(red: 0.07, green: 0.09, blue: 0.18),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct PresageWaveformView: View {
    let samples: [Double]
    let strokeColor: Color
    let verticalPaddingFraction: Double

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard samples.count > 1 else { return }

                let minValue = samples.min() ?? 0
                let maxValue = samples.max() ?? 1
                let rawRange = max(maxValue - minValue, 0.0001)
                let padding = rawRange * verticalPaddingFraction
                let lowerBound = minValue - padding
                let upperBound = maxValue + padding
                let range = max(upperBound - lowerBound, 0.0001)

                for (index, sample) in samples.enumerated() {
                    let x = geometry.size.width * CGFloat(index) / CGFloat(samples.count - 1)
                    let normalized = (sample - lowerBound) / range
                    let y = geometry.size.height * (1 - normalized)

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }
}

private extension View {
    func presageDashboardCard() -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

struct AerobicRecencySheet: View {
    var onContinue: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedMinutes: Double = 30

    var body: some View {
        NavigationStack {
            ZStack {
                Neu.canvas.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    Text("Time After Workout")
                        .font(Neu.heading(26))
                        .foregroundStyle(Neu.ink)

                    Text(label(for: Int(selectedMinutes.rounded())))
                        .font(Neu.number(28))
                        .foregroundStyle(Neu.accent)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Slider(value: $selectedMinutes, in: 0...240, step: 5)
                        .tint(Neu.accent)

                    HStack {
                        Text("Just now")
                            .font(Neu.body(13))
                            .foregroundStyle(Neu.muted)
                        Spacer()
                        Text("4 hours")
                            .font(Neu.body(13))
                            .foregroundStyle(Neu.muted)
                    }

                    Text("The coach uses this to tell incomplete recovery apart from your resting state.")
                        .font(Neu.body())
                        .foregroundStyle(Neu.muted)

                    Spacer()

                    Button {
                        onContinue(Int(selectedMinutes.rounded()))
                    } label: {
                        Text("Continue to Scan")
                            .font(Neu.button(17))
                            .foregroundStyle(Neu.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(NeuButtonStyle())
                }
                .padding(22)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func label(for minutes: Int) -> String {
        if minutes == 0 { return "Just now" }
        if minutes < 60 { return "\(minutes) minutes ago" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        return "\(hours) hr \(remainder) min ago"
    }
}

#Preview {
    @Previewable @State var store = Store.preview
    ScanView(store: store, coach: Coach(store: store), minutesSinceWorkout: 45, onFinished: {})
}
