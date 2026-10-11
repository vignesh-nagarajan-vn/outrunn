//
//  RecoveryState.swift
//  outrunn
//

import Foundation
import Observation

@Observable
final class UserRecoveryState {
    var userName: String
    var chronologicalAge: Double
    var hasProfile: Bool
    var biologicalAge: Double
    var cardiacAge: Double
    var respiratoryAge: Double
    var baseline: VitalsBaseline
    var latestScan: PreSageScan?
    var scanHistory: [PreSageScan]
    var hasCompletedBaseline: Bool
    var ageHistory: [AgeReading]
    var factorBreakdown: [AgeFactor]
    var isHealthLinked: Bool
    var healthKitStatus: String?
    var recentPeakHeartRate: Int
    var chartRange: ChartTimeRange
    var healthContext: HealthContext?
    var latestCoachPlan: CoachPlan?
    var roadrunnerAskCount: Int
    var roadrunnerAskDay: Date

    var coachStatus: String?
    var isRefreshingCoach = false
    var roadrunnerMessages: [RoadrunnerMessage] = []
    var roadrunnerStatus: String?
    var isAskingRoadrunner = false
    var roadrunnerGeneration = 0

    init(userName: String = "", chronologicalAge: Double = 30) {
        self.userName = userName
        self.chronologicalAge = chronologicalAge
        hasProfile = false
        biologicalAge = chronologicalAge
        cardiacAge = chronologicalAge
        respiratoryAge = chronologicalAge
        baseline = .empty
        latestScan = nil
        scanHistory = []
        hasCompletedBaseline = false
        ageHistory = []
        factorBreakdown = []
        isHealthLinked = false
        healthKitStatus = nil
        recentPeakHeartRate = 0
        chartRange = .day
        healthContext = nil
        latestCoachPlan = nil
        roadrunnerAskCount = 0
        roadrunnerAskDay = Calendar.current.startOfDay(for: .now)
    }

    var pulmonaryAge: Double {
        get { respiratoryAge }
        set { respiratoryAge = newValue }
    }

    static let roadrunnerDailyLimit = 8

    var roadrunnerAsksRemaining: Int {
        let used = Calendar.current.isDate(roadrunnerAskDay, inSameDayAs: .now) ? roadrunnerAskCount : 0
        return max(0, Self.roadrunnerDailyLimit - used)
    }

    func consumeRoadrunnerAsk() {
        let today = Calendar.current.startOfDay(for: .now)
        if !Calendar.current.isDate(roadrunnerAskDay, inSameDayAs: today) {
            roadrunnerAskDay = today
            roadrunnerAskCount = 0
        }
        roadrunnerAskCount += 1
        persistSoon()
    }

    var hasWeekOfAgeData: Bool {
        guard let first = ageHistory.map(\.date).min(),
              let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)
        else { return false }
        return first <= weekAgo
    }

    func updateProfile(name: String, chronologicalAge: Double) {
        userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chronologicalAge = chronologicalAge
        hasProfile = true
        if hasCompletedBaseline {
            recalculateBiologicalAge()
        } else {
            biologicalAge = chronologicalAge
            cardiacAge = chronologicalAge
            respiratoryAge = chronologicalAge
        }
        persistSoon()
    }

    func resetData(_ scope: DataResetScope) {
        if let cutoff = scope.cutoff {
            scanHistory.removeAll { $0.capturedAt >= cutoff }
            ageHistory.removeAll { $0.date >= cutoff }
        } else {
            scanHistory = []
            ageHistory = []
            chartRange = .day
        }
        latestScan = scanHistory.max(by: { $0.capturedAt < $1.capturedAt })

        latestCoachPlan = nil
        coachStatus = nil
        roadrunnerMessages = []
        roadrunnerStatus = nil
        roadrunnerGeneration += 1

        if scanHistory.isEmpty {
            hasCompletedBaseline = false
            biologicalAge = chronologicalAge
            cardiacAge = chronologicalAge
            respiratoryAge = chronologicalAge
            factorBreakdown = []
        } else {
            recalculateBiologicalAge()
        }
        persistSoon()
    }

    func applyPreSageScan(
        hrrObserved: Int,
        respiratoryRate: Double,
        vascularScore: Double,
        minutesSinceAerobicActivity: Int,
        cameraHeartRate: Int,
        signalQuality: Double,
        stressScore: Double
    ) {
        let scan = PreSageScan(
            hrrObserved: hrrObserved,
            minutesSinceAerobicActivity: minutesSinceAerobicActivity,
            respiratoryRate: respiratoryRate,
            vascularScore: vascularScore,
            cameraHeartRate: cameraHeartRate,
            signalQuality: signalQuality,
            stressScore: stressScore
        )
        scanHistory.append(scan)
        latestScan = scan
        hasCompletedBaseline = true
        recalculateBiologicalAge()
        appendHistory()
        persistSoon()
    }

    static func heartRateRecovery(
        cameraHR: Double,
        peakHR: Double,
        restingHR: Double,
        minutesSinceAerobicActivity: Int
    ) -> Int {
        if peakHR >= cameraHR + 4 {
            return Int(min(35, max(5, peakHR - cameraHR)).rounded())
        }
        // Resting rPPG is not a treadmill HRR test. Do not invent elite ~38 bpm recovery.
        let elevation = max(0, cameraHR - max(restingHR, 40))
        if minutesSinceAerobicActivity < 15 {
            return Int(min(18, max(8, 22 - elevation * 0.35)).rounded())
        }
        return Int(min(24, max(12, 20 - elevation * 0.25)).rounded())
    }

    func applyHealthKitVitals(_ vitals: HealthKitVitals) {
        isHealthLinked = true
        baseline = VitalsBaseline(
            sleepScore: vitals.sleepScore,
            hrv: vitals.hrvSDNN,
            restingHeartRate: vitals.restingHeartRate
        )
        recentPeakHeartRate = vitals.peakHeartRate
        healthContext = vitals.asHealthContext()
        healthKitStatus = "Apple Health sleep, steps, and vitals loaded."
        if hasCompletedBaseline {
            recalculateBiologicalAge()
        }
        persistSoon()
    }

    func unlinkHealth(reason: String? = nil) {
        isHealthLinked = false
        baseline = .empty
        recentPeakHeartRate = 0
        healthContext = nil
        healthKitStatus = reason
        if hasCompletedBaseline {
            recalculateBiologicalAge()
        }
        persistSoon()
    }

    /// Compounds camera scans with the Apple Health baseline. Ages never reset to a single reading.
    func recalculateBiologicalAge() {
        let chrono = chronologicalAge
        let scans = scanHistory
        let compoundedHRR = mean(scans.map { Double($0.hrrObserved) }, fallback: 22)
        let compoundedResp = mean(scans.map(\.respiratoryRate), fallback: 16.5)
        let compoundedVascular = mean(scans.map(\.vascularScore), fallback: 70)
        let hrvValue = baseline.hrv > 0 ? Double(baseline.hrv) : 55.0
        let rhrValue = baseline.restingHeartRate > 0 ? Double(baseline.restingHeartRate) : 55.0
        let healthYears = healthContext?.lifestyleYears ?? 0

        let baselineExpectedHRR = 30.0 - ((chrono - 20.0) * 0.2)
        let hrvDelta = (hrvValue - 55.0) * -0.1
        let cardiacRecoveryYears = (baselineExpectedHRR - compoundedHRR) * 0.4
        let cardiacOffset = cardiacRecoveryYears + hrvDelta
        let instantCardiac = roundedAge(chrono + cardiacOffset)
        let pulmonaryOffset = (compoundedResp - 14.0) * 0.8
        let instantPulmonary = roundedAge(chrono + pulmonaryOffset)
        let instantBiological = roundedAge(
            (instantCardiac * 0.50) + (instantPulmonary * 0.30) + (chrono * 0.20) + healthYears
        )

        let samples = scans.count
        cardiacAge = BiologicalAgeBounds.clamp(
            blend(previous: cardiacAge, instant: instantCardiac, samples: samples),
            chronological: chrono,
            younger: 10,
            older: 12
        )
        pulmonaryAge = BiologicalAgeBounds.clamp(
            blend(previous: pulmonaryAge, instant: instantPulmonary, samples: samples),
            chronological: chrono,
            younger: 10,
            older: 12
        )
        biologicalAge = BiologicalAgeBounds.clamp(
            blend(previous: biologicalAge, instant: instantBiological, samples: samples),
            chronological: chrono,
            younger: 8,
            older: 12
        )

        var breakdown: [AgeFactor] = [
            AgeFactor(title: "Compounded cardiac recovery", yearsDelta: cardiacRecoveryYears),
            AgeFactor(title: "Compounded respiratory rate", yearsDelta: pulmonaryOffset),
            AgeFactor(title: "Apple Health HRV", yearsDelta: hrvDelta),
            AgeFactor(title: "Apple Health resting HR", yearsDelta: (rhrValue - 55.0) * 0.1),
            AgeFactor(title: "Scan vascular quality", yearsDelta: (70 - compoundedVascular) * 0.04)
        ]
        if let health = healthContext {
            breakdown.append(
                AgeFactor(title: "Apple Health sleep", yearsDelta: (75.0 - Double(health.sleepScore)) * 0.035)
            )
            breakdown.append(
                AgeFactor(
                    title: "Apple Health steps",
                    yearsDelta: (8_000.0 - Double(health.stepCount)) / 4_000.0 * 0.55
                )
            )
        }
        factorBreakdown = breakdown
    }

    private func appendHistory() {
        ageHistory.append(
            AgeReading(
                date: .now,
                chronologicalAge: chronologicalAge,
                biologicalAge: biologicalAge,
                cardiacAge: cardiacAge,
                respiratoryAge: respiratoryAge
            )
        )
    }

    private func mean(_ values: [Double], fallback: Double) -> Double {
        guard !values.isEmpty else { return fallback }
        return values.reduce(0, +) / Double(values.count)
    }

    private func blend(previous: Double, instant: Double, samples: Int) -> Double {
        if samples <= 1 { return instant }
        return roundedAge(previous * 0.65 + instant * 0.35)
    }

    private func roundedAge(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    func persistSoon() {
        RecoveryPersistence.save(snapshot())
    }

    static func restored() -> UserRecoveryState {
        let state = UserRecoveryState()
        if let snapshot = RecoveryPersistence.load() {
            state.restore(from: snapshot)
        }
        return state
    }

    func restore(from snapshot: RecoverySnapshot) {
        userName = snapshot.userName
        chronologicalAge = snapshot.chronologicalAge
        hasProfile = snapshot.hasProfile
        biologicalAge = snapshot.biologicalAge
        cardiacAge = snapshot.cardiacAge
        respiratoryAge = snapshot.respiratoryAge
        baseline = snapshot.baseline
        latestScan = snapshot.latestScan
        scanHistory = snapshot.scanHistory
        hasCompletedBaseline = snapshot.hasCompletedBaseline
        ageHistory = snapshot.ageHistory
        factorBreakdown = snapshot.factorBreakdown
        isHealthLinked = snapshot.isHealthLinked
        healthKitStatus = snapshot.healthKitStatus
        recentPeakHeartRate = snapshot.recentPeakHeartRate
        chartRange = snapshot.chartRange
        healthContext = snapshot.healthContext
        latestCoachPlan = snapshot.latestCoachPlan
        roadrunnerAskCount = snapshot.roadrunnerAskCount
        roadrunnerAskDay = snapshot.roadrunnerAskDay
    }

    func snapshot() -> RecoverySnapshot {
        RecoverySnapshot(
            userName: userName,
            chronologicalAge: chronologicalAge,
            hasProfile: hasProfile,
            biologicalAge: biologicalAge,
            cardiacAge: cardiacAge,
            respiratoryAge: respiratoryAge,
            baseline: baseline,
            latestScan: latestScan,
            scanHistory: scanHistory,
            hasCompletedBaseline: hasCompletedBaseline,
            ageHistory: ageHistory,
            factorBreakdown: factorBreakdown,
            isHealthLinked: isHealthLinked,
            healthKitStatus: healthKitStatus,
            recentPeakHeartRate: recentPeakHeartRate,
            chartRange: chartRange,
            healthContext: healthContext,
            latestCoachPlan: latestCoachPlan,
            roadrunnerAskCount: roadrunnerAskCount,
            roadrunnerAskDay: roadrunnerAskDay
        )
    }

    #if DEBUG
    static var preview: UserRecoveryState {
        let state = UserRecoveryState(userName: "Alex", chronologicalAge: 30)
        state.hasProfile = true
        state.baseline = VitalsBaseline(sleepScore: 86, hrv: 62, restingHeartRate: 52)
        state.scanHistory = [
            PreSageScan(
                hrrObserved: 28,
                minutesSinceAerobicActivity: 45,
                respiratoryRate: 13.2,
                vascularScore: 88,
                cameraHeartRate: 64,
                signalQuality: 88,
                stressScore: 92
            )
        ]
        state.latestScan = state.scanHistory.last
        state.hasCompletedBaseline = true
        state.recalculateBiologicalAge()
        state.ageHistory = [
            AgeReading(
                date: .now,
                chronologicalAge: state.chronologicalAge,
                biologicalAge: state.biologicalAge,
                cardiacAge: state.cardiacAge,
                respiratoryAge: state.respiratoryAge
            )
        ]
        return state
    }
    #endif
}
