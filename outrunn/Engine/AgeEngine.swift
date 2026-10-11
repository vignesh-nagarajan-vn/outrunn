//
//  AgeEngine.swift
//  outrunn
//
//  The age math. Inputs in, ages and a factor breakdown out.
//  No state, no I/O, no UI. Same inputs always give the same result.
//

import Foundation

nonisolated enum AgeEngine {
    nonisolated struct Input {
        var chronologicalAge: Double
        var scans: [Scan]
        var health: HealthSnapshot?
    }

    /// Weight of each new scan against the running value of earlier scans.
    static let scanWeight = 0.35
    /// A peak heart rate older than this says nothing about recovery.
    static let peakWindowMinutes = 180
    static let breathingBaseline = 14.0
    static let hrvBaselineSDNN = 55.0
    static let sleepBaselineHours = 7.5
    static let stepsBaseline = 8_000.0

    private static let cardiacShare = 0.5
    private static let pulmonaryShare = 0.3
    private static let recoveryCeiling = 35.0

    static func expectedHeartRateRecovery(age: Double) -> Double {
        30.0 - (age - 20.0) * 0.2
    }

    /// Heart rate recovery for a scan, or nil when it cannot be measured.
    /// It needs a real peak from Apple Health that is recent and clearly above the scan heart rate.
    /// This is a drop measured minutes after effort, not a clinical one minute test.
    static func heartRateRecovery(peak: Int?, current: Int, minutesSinceWorkout: Int) -> Int? {
        guard let peak,
              minutesSinceWorkout <= peakWindowMinutes,
              peak - current >= 5
        else { return nil }
        return peak - current
    }

    /// Nil until there is at least one scan.
    static func estimate(_ input: Input) -> AgeEstimate? {
        let scans = input.scans.sorted { $0.capturedAt < $1.capturedAt }
        guard let breathing = blend(scans.map(\.respiratoryRate)) else { return nil }

        let age = input.chronologicalAge
        var factors: [AgeFactor] = []

        var cardiacYears: Double?
        let recoveries = scans.compactMap { scan in
            scan.heartRateRecovery.map { min(Double($0), recoveryCeiling) }
        }
        if let recovery = blend(recoveries) {
            let years = (expectedHeartRateRecovery(age: age) - recovery) * 0.4
            cardiacYears = years
            factors.append(AgeFactor(kind: .heartRateRecovery, years: years * cardiacShare))
        }
        if let sdnn = input.health?.hrvSDNN {
            let years = (hrvBaselineSDNN - sdnn) * 0.1
            cardiacYears = (cardiacYears ?? 0) + years
            factors.append(AgeFactor(kind: .heartRateVariability, years: years * cardiacShare))
        }

        let pulmonaryYears = (breathing - breathingBaseline) * 0.8
        factors.append(AgeFactor(kind: .breathingRate, years: pulmonaryYears * pulmonaryShare))

        if let hours = input.health?.sleepHours {
            let score = min(100, hours / 8.0 * 100)
            let years = (75.0 - score) * 0.035 + (sleepBaselineHours - hours) * 0.35
            factors.append(AgeFactor(kind: .sleep, years: years))
        }
        if let steps = input.health?.stepCount {
            let years = (stepsBaseline - Double(steps)) / 4_000.0 * 0.55
            factors.append(AgeFactor(kind: .steps, years: years))
        }

        // Biological age is chronological age plus every factor. Anything
        // missing is simply not in the list, so it adds nothing.
        let biologicalYears = factors.reduce(0) { $0 + $1.years }

        return AgeEstimate(
            biological: clamp(age + biologicalYears, around: age, younger: 8, older: 12),
            cardiac: cardiacYears.map { clamp(age + $0, around: age, younger: 10, older: 12) },
            pulmonary: clamp(age + pulmonaryYears, around: age, younger: 10, older: 12),
            factors: factors
        )
    }

    /// Running value across scans in time order, so one scan never replaces the history.
    static func blend(_ values: [Double]) -> Double? {
        guard var running = values.first else { return nil }
        for value in values.dropFirst() {
            running = running * (1 - scanWeight) + value * scanWeight
        }
        return running
    }

    /// Keeps an age within a plausible band around chronological age and inside 18 to 90.
    static func clamp(_ value: Double, around age: Double, younger: Double, older: Double) -> Double {
        let floor = max(18, age - younger)
        let ceiling = max(floor, min(90, age + older))
        let bounded = min(ceiling, max(floor, value))
        return (bounded * 10).rounded() / 10
    }
}
