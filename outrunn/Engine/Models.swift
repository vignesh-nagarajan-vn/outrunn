//
//  Models.swift
//  outrunn
//
//  Plain values shared by the engine, the store, and the screens.
//

import Foundation

nonisolated struct Profile: Hashable, Codable {
    var name: String
    var age: Double
}

/// One camera scan. Vitals only, never video.
nonisolated struct Scan: Identifiable, Hashable, Codable {
    var id = UUID()
    var capturedAt: Date = .now
    var minutesSinceWorkout: Int
    var heartRate: Int
    var respiratoryRate: Double
    /// Presage confidence in the pulse reading, 0 to 100.
    var pulseConfidence: Double
    /// Drop from the Apple Health peak heart rate to the scan heart rate.
    /// Nil when there is no real peak to measure from.
    var heartRateRecovery: Int?
    /// Presage HRV as RMSSD in ms. Displayed only. The engine's HRV term is
    /// calibrated for SDNN, so RMSSD never feeds it.
    var rmssd: Double?
    /// Presage Baevsky stress index.
    var stressIndex: Double?
}

/// What Apple Health had at the last read. Every value is nil when Health had no sample.
nonisolated struct HealthSnapshot: Hashable, Codable {
    var capturedAt: Date = .now
    /// Asleep time over the last 24 hours.
    var sleepHours: Double?
    /// Steps so far today.
    var stepCount: Int?
    /// 7 day average.
    var restingHeartRate: Int?
    /// 7 day average HRV as SDNN in ms.
    var hrvSDNN: Double?
    /// Highest heart rate inside `AgeEngine.peakWindowMinutes`.
    var peakHeartRate: Int?

    var isEmpty: Bool {
        sleepHours == nil && stepCount == nil && restingHeartRate == nil
            && hrvSDNN == nil && peakHeartRate == nil
    }
}

/// One input's contribution to biological age, in years. Negative is younger.
nonisolated struct AgeFactor: Identifiable, Hashable, Codable {
    nonisolated enum Kind: String, Codable {
        case heartRateRecovery
        case heartRateVariability
        case breathingRate
        case sleep
        case steps
    }

    var kind: Kind
    var years: Double

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .heartRateRecovery: "Heart rate recovery"
        case .heartRateVariability: "Heart rate variability"
        case .breathingRate: "Breathing rate"
        case .sleep: "Sleep"
        case .steps: "Daily steps"
        }
    }
}

nonisolated struct AgeEstimate: Hashable, Codable {
    var biological: Double
    /// Nil when there is neither heart rate recovery nor HRV to base it on.
    var cardiac: Double?
    var pulmonary: Double
    var factors: [AgeFactor]
}

/// The estimate as it stood right after a scan. Kept for the chart and History.
nonisolated struct AgeReading: Identifiable, Hashable, Codable {
    var id = UUID()
    var date: Date
    var chronological: Double
    var biological: Double
    var cardiac: Double?
    var pulmonary: Double
}

nonisolated enum ChartTimeRange: String, CaseIterable, Identifiable, Codable {
    case day
    case week
    case month
    case sixMonths
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "1D"
        case .week: "1W"
        case .month: "1M"
        case .sixMonths: "6M"
        case .year: "1Y"
        }
    }

    var requiresWeekOfHistory: Bool {
        self != .day
    }

    var startDate: Date {
        switch self {
        case .day:
            Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        case .week:
            Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        case .month:
            Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        case .sixMonths:
            Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
        case .year:
            Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now
        }
    }
}

nonisolated enum DataResetScope {
    case day
    case week
    case all

    var cutoff: Date? {
        switch self {
        case .day: Calendar.current.date(byAdding: .day, value: -1, to: .now)
        case .week: Calendar.current.date(byAdding: .day, value: -7, to: .now)
        case .all: nil
        }
    }
}
