//
//  TodayView.swift
//  outrunn
//

import Charts
import SwiftUI

enum AgeMetric: String, CaseIterable, Identifiable {
    case real = "Real Age"
    case biological = "Biological Age"
    case cardiac = "Cardiac Age"
    case respiratory = "Pulmonary Age"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .real: Neu.ink
        case .biological: Neu.accent
        case .cardiac: Color(red: 0.86, green: 0.38, blue: 0.40)
        case .respiratory: Color(red: 0.35, green: 0.55, blue: 0.86)
        }
    }
}

struct AgeChartPoint: Identifiable {
    var id: String
    var date: Date
    var index: Int
    var metric: AgeMetric
    var age: Double
}

private struct SnapshotStat: Identifiable {
    var id: String
    var title: String
    var value: String
    var unit: String
    var meaning: String
    var meaningColor: Color
}

struct TodayView: View {
    var state: UserRecoveryState
    var onOpenSettings: () -> Void = {}
    var scanRequestCount: Int = 0

    @State private var showActivityPrompt = false
    @State private var showScan = false
    @State private var pendingMinutes = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShellHeader(title: "outrunn") {
                SettingsGearButton(action: onOpenSettings)
            }
            .padding(.horizontal, ShellLayout.horizontalPadding)
            .padding(.top, ShellLayout.topPadding)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    scanButton

                    if state.hasCompletedBaseline {
                        ageRings
                        deltaCard
                    }

                    ageChart
                        .frame(height: 340)

                    if state.hasCompletedBaseline {
                        snapshotSection
                        yearsSection
                    }

                    Text("A wellness estimate, not medical advice or a diagnosis.")
                        .font(Neu.body(12))
                        .foregroundStyle(Neu.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, ShellLayout.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.35), value: state.biologicalAge)
        .sheet(isPresented: $showActivityPrompt) {
            AerobicRecencySheet { minutes in
                pendingMinutes = minutes
                showActivityPrompt = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showScan = true
                }
            }
        }
        .fullScreenCover(isPresented: $showScan) {
            ScanView(
                state: state,
                minutesSinceAerobicActivity: pendingMinutes
            ) {
                showScan = false
            }
        }
        .onChange(of: scanRequestCount) { _, count in
            guard count > 0 else { return }
            showActivityPrompt = true
        }
    }

    // MARK: Scan button

    private var scanButton: some View {
        Button {
            showActivityPrompt = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Neu.accent)
                    .frame(width: 44, height: 44)
                    .background(ConvexShape(shape: Circle(), isPressed: true))

                Text(state.hasCompletedBaseline ? "Take a New Scan" : "Take Your Baseline Scan")
                    .font(Neu.heading(18))
                    .italic()
                    .foregroundStyle(Neu.ink)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Neu.muted)
            }
            .padding(16)
            .background(
                ConvexShape(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Age rings

    private var ageRings: some View {
        HStack(spacing: 12) {
            ageRing(.cardiac, age: state.cardiacAge, size: 82)
            ageRing(.biological, age: state.biologicalAge, size: 152)
            ageRing(.respiratory, age: state.respiratoryAge, size: 82)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func ageRing(_ metric: AgeMetric, age: Double, size: CGFloat) -> some View {
        let isPrimary = metric == .biological
        return ZStack {
            ConvexShape(shape: Circle())

            Circle()
                .stroke(metric.color.opacity(isPrimary ? 1 : 0.45), lineWidth: isPrimary ? 7 : 5)

            VStack(spacing: isPrimary ? 6 : 4) {
                Text(String(format: "%.1f", age))
                    .font(Neu.number(isPrimary ? 40 : 20))
                    .foregroundStyle(Neu.ink)
                    .monospacedDigit()
                Text(metric.rawValue)
                    .font(Neu.label(isPrimary ? 13 : 10))
                    .foregroundStyle(Neu.muted)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
            }
        }
        .frame(width: size, height: size)
    }

    private var deltaCard: some View {
        let years = state.biologicalAge - state.chronologicalAge
        let headline: String
        if abs(years) < 0.15 {
            headline = "Biological Age matches your Real Age."
        } else {
            let amount = String(format: "%.1f", abs(years))
            headline = years < 0
                ? "\(amount) years younger than Real Age."
                : "\(amount) years older than Real Age."
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(Neu.number(22))
                .foregroundStyle(abs(years) < 0.15 ? Neu.ink : (years < 0 ? Neu.younger : Neu.older))
                .fixedSize(horizontal: false, vertical: true)
            Text("Your Real Age is \(String(format: "%.1f", state.chronologicalAge)).")
                .font(Neu.body())
                .foregroundStyle(Neu.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
    }

    // MARK: Trend chart

    private var ageChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Age Trends")
                .font(Neu.heading(16))
                .italic()
                .foregroundStyle(Neu.ink)

            Picker("Range", selection: chartRangeBinding) {
                ForEach(ChartTimeRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            if state.ageHistory.isEmpty {
                chartPlaceholder(title: nil, body: "Complete your baseline scan to unlock your age graph.")
            } else if state.chartRange.requiresWeekOfHistory && !state.hasWeekOfAgeData {
                chartPlaceholder(
                    title: "Not enough data",
                    body: "Keep scanning for a week to unlock this time range."
                )
            } else if chartPoints.isEmpty {
                chartPlaceholder(title: nil, body: "No readings in this time range yet.")
            } else {
                AgeTrendChart(points: chartPoints, range: state.chartRange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                legend
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ConvexShape(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
    }

    private func chartPlaceholder(title: String?, body: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            if let title {
                Text(title)
                    .font(Neu.heading(18))
                    .foregroundStyle(Neu.ink)
            }
            Text(body)
                .font(Neu.body(15))
                .foregroundStyle(Neu.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], spacing: 8) {
            ForEach(AgeMetric.allCases) { metric in
                HStack(spacing: 8) {
                    Circle()
                        .fill(metric.color)
                        .frame(width: 8, height: 8)
                    Text(metric.rawValue)
                        .font(Neu.body(12))
                        .foregroundStyle(Neu.ink)
                }
            }
        }
    }

    private var chartRangeBinding: Binding<ChartTimeRange> {
        Binding(
            get: { state.chartRange },
            set: {
                state.chartRange = $0
                state.persistSoon()
            }
        )
    }

    private var chartPoints: [AgeChartPoint] {
        let start = state.chartRange.startDate
        let readings = state.ageHistory
            .filter { $0.date >= start }
            .sorted { $0.date < $1.date }
        return readings.enumerated().flatMap { index, reading in
            AgeMetric.allCases.map { metric in
                AgeChartPoint(
                    id: "\(reading.id.uuidString)-\(metric.rawValue)",
                    date: reading.date,
                    index: index,
                    metric: metric,
                    age: value(in: reading, for: metric)
                )
            }
        }
    }

    private func value(in reading: AgeReading, for metric: AgeMetric) -> Double {
        switch metric {
        case .real: reading.chronologicalAge
        case .biological: reading.biologicalAge
        case .cardiac: reading.cardiacAge
        case .respiratory: reading.respiratoryAge
        }
    }

    // MARK: Last scan stats

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("From your last scan")
                .font(Neu.heading(18))
                .italic()
                .foregroundStyle(Neu.ink)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(snapshotStats) { stat in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stat.title)
                            .font(Neu.emphasis(13))
                            .foregroundStyle(Neu.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(stat.value)
                                .font(Neu.number(32))
                                .foregroundStyle(Neu.ink)
                                .monospacedDigit()
                            if !stat.unit.isEmpty {
                                Text(stat.unit)
                                    .font(Neu.body(13))
                                    .foregroundStyle(Neu.muted)
                            }
                        }
                        Text(stat.meaning)
                            .font(Neu.label(14))
                            .foregroundStyle(stat.meaningColor)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 20, style: .continuous)))
                }
            }
        }
    }

    private var snapshotStats: [SnapshotStat] {
        guard let scan = state.latestScan else { return [] }
        let stress = scan.stressScore
        return [
            SnapshotStat(
                id: "pulse",
                title: "Pulse",
                value: "\(scan.cameraHeartRate)",
                unit: "bpm",
                meaning: pulseMeaning(scan.cameraHeartRate),
                meaningColor: scan.cameraHeartRate <= 70 ? Neu.younger : Neu.older
            ),
            SnapshotStat(
                id: "breathing",
                title: "Breathing",
                value: "\(Int(scan.respiratoryRate.rounded()))",
                unit: "/min",
                meaning: breathingMeaning(scan.respiratoryRate),
                meaningColor: scan.respiratoryRate <= 16 ? Neu.younger : Neu.older
            ),
            SnapshotStat(
                id: "recovery",
                title: "Recovery",
                value: "\(scan.hrrObserved)",
                unit: "beats",
                meaning: recoveryMeaning(scan.hrrObserved),
                meaningColor: scan.hrrObserved >= 18 ? Neu.younger : Neu.older
            ),
            SnapshotStat(
                id: "stress",
                title: "Stress",
                value: stress > 0 ? String(format: "%.0f", stress) : "--",
                unit: "",
                meaning: stressMeaning(stress),
                meaningColor: stress <= 0 ? Neu.muted : (stress <= 150 ? Neu.younger : Neu.older)
            )
        ]
    }

    private func pulseMeaning(_ bpm: Int) -> String {
        if bpm < 55 { return "Very calm" }
        if bpm <= 70 { return "Steady" }
        if bpm <= 85 { return "A bit high" }
        return "Running high"
    }

    private func breathingMeaning(_ rate: Double) -> String {
        if rate <= 14 { return "Easy pace" }
        if rate <= 18 { return "Typical" }
        return "Working hard"
    }

    private func recoveryMeaning(_ drop: Int) -> String {
        if drop >= 25 { return "Calmed down fast" }
        if drop >= 18 { return "Solid bounce-back" }
        if drop >= 12 { return "Average recovery" }
        return "Slow to settle"
    }

    private func stressMeaning(_ score: Double) -> String {
        if score <= 0 { return "Not captured yet" }
        if score <= 80 { return "Calm" }
        if score <= 150 { return "Typical" }
        if score <= 300 { return "Elevated" }
        return "Running high"
    }

    // MARK: What is adding years

    private var visibleFactors: [AgeFactor] {
        state.factorBreakdown
            .filter { abs($0.yearsDelta) >= 0.15 }
            .sorted { abs($0.yearsDelta) > abs($1.yearsDelta) }
    }

    @ViewBuilder
    private var yearsSection: some View {
        let factors = visibleFactors
        let maxYears = max(factors.map { abs($0.yearsDelta) }.max() ?? 1, 0.8)
        if !factors.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What’s adding years")
                    .font(Neu.heading(18))
                    .italic()
                    .foregroundStyle(Neu.ink)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(factors) { factor in
                        let tint = factor.yearsDelta > 0 ? Neu.older : Neu.younger
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(friendlyFactor(factor.title))
                                    .font(Neu.emphasis(16))
                                    .foregroundStyle(Neu.ink)
                                Spacer()
                                Text(String(format: "%+.1f yrs", factor.yearsDelta))
                                    .font(Neu.button(16))
                                    .foregroundStyle(tint)
                                    .monospacedDigit()
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Neu.ink.opacity(0.08))
                                    Capsule()
                                        .fill(tint)
                                        .frame(width: geo.size.width * CGFloat(min(1, abs(factor.yearsDelta) / maxYears)))
                                }
                            }
                            .frame(height: 7)
                        }
                    }
                }
                .padding(16)
                .background(ConvexShape(shape: RoundedRectangle(cornerRadius: 20, style: .continuous)))
            }
        }
    }

    private func friendlyFactor(_ title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("cardiac") { return "Heart recovery" }
        if lower.contains("respiratory") { return "Breathing" }
        if lower.contains("hrv") { return "Day-to-day recovery" }
        if lower.contains("resting") { return "Resting pulse" }
        if lower.contains("vascular") { return "Circulation" }
        if lower.contains("sleep") { return "Sleep" }
        if lower.contains("step") { return "Daily movement" }
        return title
    }
}

private struct AgeMetricSeries: Identifiable {
    var metric: AgeMetric
    var points: [AgeChartPoint]
    var id: String { metric.rawValue }
}

private struct AgeTrendChart: View {
    var points: [AgeChartPoint]
    var range: ChartTimeRange

    private var series: [AgeMetricSeries] {
        AgeMetric.allCases.map { metric in
            AgeMetricSeries(
                metric: metric,
                points: points.filter { $0.metric == metric }.sorted { $0.date < $1.date }
            )
        }
    }

    var body: some View {
        if range == .day {
            evenChart
        } else {
            timeChart
        }
    }

    private var evenChart: some View {
        Chart(points) { point in
            PointMark(
                x: .value("Scan", point.index),
                y: .value("Age", point.age)
            )
            .foregroundStyle(point.metric.color)
            .symbol(.circle)
            .symbolSize(90)
        }
        .chartLegend(.hidden)
        .chartXScale(domain: -0.5 ... Double(evenLastIndex) + 0.5)
        .chartXAxis(.hidden)
        .chartYScale(domain: yDomain)
        .chartYAxis { yAxis }
        .chartPlotStyle { plot in
            plot.background(Neu.plotFill)
        }
    }

    private var timeChart: some View {
        Chart {
            ForEach(connectedSeries) { metricSeries in
                LinePlot(
                    metricSeries.points,
                    x: .value("Time", \.date),
                    y: .value("Age", \.age)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(metricSeries.metric.color)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            ForEach(points) { point in
                PointMark(
                    x: .value("Time", point.date),
                    y: .value("Age", point.age)
                )
                .foregroundStyle(point.metric.color)
                .symbol(.circle)
                .symbolSize(48)
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: range.startDate...Date.now)
        .chartXAxis {
            AxisMarks(values: xTickDates) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: xAxisFormat)
                            .font(Neu.body(11))
                            .foregroundStyle(Neu.muted)
                    }
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis { yAxis }
        .chartPlotStyle { plot in
            plot.background(Neu.plotFill)
        }
    }

    private var yAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
            AxisValueLabel {
                if let age = value.as(Double.self) {
                    Text(String(format: "%.0f", age))
                        .font(Neu.body(11).monospacedDigit())
                        .foregroundStyle(Neu.muted)
                }
            }
        }
    }

    private var connectedSeries: [AgeMetricSeries] {
        series.filter { $0.points.count >= 2 }
    }

    private var evenLastIndex: Int {
        max((series.map(\.points.count).max() ?? 1) - 1, 0)
    }

    private var xTickCount: Int {
        switch range {
        case .day: 0
        case .week: 7
        case .month: 5
        case .sixMonths, .year: 6
        }
    }

    private var xTickDates: [Date] {
        let start = range.startDate
        let end = Date.now
        let span = end.timeIntervalSince(start)
        guard span > 0, xTickCount > 1 else { return [end] }
        return (0..<xTickCount).map { index in
            start.addingTimeInterval(span * Double(index) / Double(xTickCount - 1))
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch range {
        case .day: .dateTime.hour().minute()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.month(.abbreviated).day()
        case .sixMonths, .year: .dateTime.month(.abbreviated)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.age)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 20...40
        }
        if minValue == maxValue {
            return (minValue - 2)...(maxValue + 2)
        }
        let pad = max(1.0, (maxValue - minValue) * 0.2)
        return (minValue - pad)...(maxValue + pad)
    }
}

#Preview {
    @Previewable @State var state = UserRecoveryState.preview
    TodayView(state: state)
}
