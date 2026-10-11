//
//  Models.swift
//  outrunn
//

import Foundation

struct HealthContext: Hashable, Codable {
    var capturedAt: Date
    var sleepScore: Int
    var sleepHours: Double
    var stepCount: Int
    var restingHeartRate: Int
    var hrvSDNN: Int
    var respiratoryRate: Double
    var activeEnergyBurned: Double
    var peakHeartRate: Int

    var lifestyleYears: Double {
        let sleepYears = (75.0 - Double(sleepScore)) * 0.035
        let restYears = sleepHours > 0 ? (7.5 - sleepHours) * 0.35 : 0
        let stepYears = (8_000.0 - Double(stepCount)) / 4_000.0 * 0.55
        return ((sleepYears + restYears + stepYears) * 10).rounded() / 10
    }
}

struct VitalsBaseline: Hashable, Codable {
    var sleepScore: Int
    var hrv: Int
    var restingHeartRate: Int

    static let empty = VitalsBaseline(sleepScore: 0, hrv: 0, restingHeartRate: 0)
}

enum ChartTimeRange: String, CaseIterable, Identifiable, Codable {
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

enum DataResetScope {
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

enum BiologicalAgeBounds {
    static func clamp(_ estimate: Double, chronological chrono: Double, younger: Double, older: Double) -> Double {
        let floor = max(18, chrono - younger)
        let ceiling = min(90, chrono + older)
        let value = min(ceiling, max(floor, estimate))
        return (value * 10).rounded() / 10
    }
}

struct PreSageScan: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var capturedAt: Date = .now
    var hrrObserved: Int
    var minutesSinceAerobicActivity: Int
    var respiratoryRate: Double
    var vascularScore: Double
    var cameraHeartRate: Int
    var signalQuality: Double
    var stressScore: Double
}

struct AgeReading: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var date: Date
    var chronologicalAge: Double
    var biologicalAge: Double
    var cardiacAge: Double
    var respiratoryAge: Double
}

struct AgeFactor: Identifiable, Hashable, Codable {
    var id: String { title }
    var title: String
    var yearsDelta: Double
}
